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
# Remember to set systemd as the cgroup driver when running kubeadm init later
sudo systemctl restart containerd

# INSTALL CLI TOOLS
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet # check if kubelet is installed correctly, should keep failing

# CREATE CLUSTER
# back to https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
# check the control plane advertised IP with:
ip route show
kubeadm config images pull # do this before running kubeadm init to save some time
sudo kubeadm init
# got this error: [ERROR FileContent--proc-sys-net-ipv4-ip_forward]: /proc/sys/net/ipv4/ip_forward contents are not set to 1
# solve with setting net.ipv4.ip_forward to 1 on /etc/sysctl.conf and running sysctl -p to apply changes
## kubeadm init should give the output below
# Your Kubernetes control-plane has initialized successfully!
# To start using your cluster, you need to run the following as a regular user:
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
# Alternatively, if you are the root user, you can run:
# (remember to run sudo su before)
export KUBECONFIG=/etc/kubernetes/admin.conf
# You should now deploy a pod network to the cluster.
# Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
# https://kubernetes.io/docs/concepts/cluster-administration/addons/
## The kubelet service should keep crashing and kubectl should return a connection refused if you take too long to apply the CNI
## If necessary run systemctl restart kubelet

# DEPLOY POD NETWORK
# https://github.com/flannel-io/flannel#deploying-flannel-manually
# Pretty much just:
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
# Issues with flannel!
# Error: Failed to check br_netfilter: stat /proc/sys/net/bridge/bridge-nf-call-iptables: no such file or directory
sudo modprobe br_netfilter
lsmod | grep br_netfilter # check if it's installed
# Error: Failed to create SubnetManager: error retrieving pod spec for 'kube-flannel/kube-flannel-ds-bxbcj': Get "https://10.96.0.1:443/api/v1/namespaces/kube-flannel/pods/kube-flannel-ds-bxbcj": dial tcp 10.96.0.1:443: connect: connection refused
# (deleted the flannel pod and the error changed)
# Error: E0306 00:38:41.220625       1 main.go:359] Error registering network: failed to acquire lease: node "thinkpad-01" pod cidr not assigned
echo "br_netfilter" | sudo tee /etc/modules-load.d/k8s-bridge.conf
cat <<EOF | sudo tee /etc/sysctl.d/k8s-bridge.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system
kubectl delete pod flannel
# (still the same error)
# Put these 2 flags in /etc/kubernetes/manifests/kube-controller-manager.yaml:
# - --allocate-node-cidrs=true
# - --cluster-cidr=10.244.0.0/16 # This should match your flannel network config
# This Adds a PodCIDRs property to the node, now we should use this CIDR in the flannel config
kubectl get configmap --namespace kube-flannel
kubectl delete pod kube-flannel # ()
# In my case I also got kube proxy and kube scheduler in crashloopbackoff and kube-flannel went pending
# thought this was the fault of kube-scheduler (most likely it was), but after a few minutes things just started working
