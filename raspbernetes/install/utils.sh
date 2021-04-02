#!/bin/bash
set -euo pipefail

echo "Updating core packages..."
apt-get update

echo "Installing base packages..."
apt-get install -y --no-install-recommends \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg2 \
  software-properties-common \
  nfs-common \
  zip \
  jq \
  git \
  vim
