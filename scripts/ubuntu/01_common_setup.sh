# Turn off swap for the current session
sudo swapoff -a

# Comment out swap entries in /etc/fstab to disable swap permanently
sudo sed -i '/\sswap\s/s/^\(.*\)$/#\1/' /etc/fstab

# load kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# apply sysctl params without reboot
sudo sysctl --system

# check that the modules are loaded:
lsmod | grep -E 'overlay|br_netfilter'

# confirm that the sysctl values are set correctly:
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

# Install containerd from Ubuntu repositories
sudo apt-get update
sudo apt-get install -y containerd

# create config dir & write default config
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# configure containerd to use systemd cgroups
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true

# restart and enable containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# check that containerd service is up and running
systemctl status containerd --no-pager

# install prerequisites for apt repo
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# create apt keyrings dir (if it doesn't exist)
sudo mkdir -p -m 755 /etc/apt/keyrings

# import the Kubernetes repo signing key (The same signing key is used for all repositories so you can disregard the version in the URL)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# add the repo (this file points to v1.34 packages). If you want a different minor version, change v1.34 in the URL.
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

# install kubelet, kubeadm, kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# hold them to avoid accidental upgrades
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable --now kubelet

#Install CNI Plugins
CNI_PLUGINS_VERSION="v1.3.0"
ARCH="arm64"
DEST="/opt/cni/bin"

sudo mkdir -p "$DEST"
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-${CNI_PLUGINS_VERSION}.tgz" \
  | sudo tar -C "$DEST" -xz
