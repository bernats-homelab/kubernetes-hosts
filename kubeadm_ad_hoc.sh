#!/usr/bin/env bash
set -xeuo pipefail

# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

# disable swap
# apparently recommended to avoid Secrets being stored to disk
sudo swapoff -a # temporary
# permanent:
# remove a line with swap mentioned from /etc/fstab

# (check if htop displays 0 for swap usage or run free -h)
