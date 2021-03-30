#!/bin/bash
set -euo pipefail

docker_version="5:19.03.9~3-0~raspbian-buster"

# Get the Docker signing key for packages
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | apt-key add -

# Add the Docker official repos

cat << EOF >> /etc/apt/sources.list.d/docker.list
deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(lsb_release -cs) stable
EOF

# update mirrors and install docker
echo "Installing docker ${docker_version}..."
apt-get update
apt-get install -y --no-install-recommends "docker-ce=${docker_version}"
apt-mark hold docker-ce

# setup daemon to user systemd as per kubernetes best practices
cat << EOF >> /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

mkdir -p /etc/systemd/system/docker.service.d

# restart docker
systemctl daemon-reload
systemctl restart docker
