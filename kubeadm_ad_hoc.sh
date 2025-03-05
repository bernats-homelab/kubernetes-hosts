#!/usr/bin/env bash
set -xeuo pipefail

# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

# DISABLE SWAP
# apparently recommended to avoid Secrets being stored to disk
sudo swapoff -a # temporary
# permanent:
# remove a line with swap mentioned from /etc/fstab
# (check if htop displays 0 for swap usage or run free -h)

# INSTALL CONTAINER RUNTIME
# https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd
### https://github.com/containerd/containerd/blob/main/docs/getting-started.md
##### https://docs.docker.com/engine/install/ubuntu/
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" |
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install containerd.io
# install CNI (the -L is very important since github redirects these links)
# necessary because downloading containerd.io from docker repos doesn't install CNI
curl -LO https://github.com/containernetworking/plugins/releases/download/v1.6.2/cni-plugins-linux-amd64-v1.6.2.tgz
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.6.2.tgz
# check if everything works:
cat /etc/containerd/config.toml
## CRI is disabled by default, take it out of the disabled_plugins list in /etc/containerd/config.toml
## enable systemd cgroup driver in containerd putting these settings in the config.toml
# [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
#   [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
#     SystemdCgroup = true
sudo systemctl restart containerd
