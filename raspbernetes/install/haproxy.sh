#!/bin/bash
set -euo pipefail

haproxy_version="1.8.19-1+rpi1"

echo "Installing haproxy ${haproxy_version}..."
apt-get install -y --no-install-recommends "haproxy=${haproxy_version}"
apt-mark hold haproxy

# create a configuration file for all other master hosts
cat << EOF >> /etc/haproxy/haproxy.cfg

frontend kube-api
  bind 0.0.0.0:8443
  bind 127.0.0.1:8443
  mode tcp
  option tcplog
  timeout client 4h
  default_backend kube-api-be

backend kube-api-be
  mode tcp
  option tcp-check
  timeout server 4h
  balance roundrobin
  default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
EOF

echo ${KUBE_MASTER_IPS} | awk -F'\n' \
	'{ \
		split($1, a, "[[:space:]]"); \
		for (i in a) { \
			printf "  server kube-master-%02d %s:6443 check\n", i, a[i] \
		} \
	}' >> /etc/haproxy/haproxy.cfg

# reload after new configuration file has been updated
systemctl reload haproxy
