#!/bin/bash
# Copyright (C) 2022 Alessandro Accardo
# 
# This file is part of klez-kluster-r08075.
# 
# klez-kluster-r08075 is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# klez-kluster-r08075 is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with klez-kluster-r08075.  If not, see <http://www.gnu.org/licenses/>.

set -euo pipefail

# change to directory where bootstrap lives
cd "${0%/*}"

# source the environment variables for hostname, IP addresses and node type
# shellcheck disable=SC1091
source ./rpi-env

# remove the last 3 lines from /etc/sysctl.conf
sed -i "$(($(wc -l </etc/sysctl.conf) - 3 + 1)),$ d" /etc/sysctl.conf

# remove the last 16+N lines from /etc/haproxy/haproxy.cfg

sed -i "$(($(wc -l </etc/haproxy/haproxy.cfg) - (14+${#KUBE_MASTER_IPS[@]}) + 1)),$ d" /etc/haproxy/haproxy.cfg

echo "Reverting complete!"
