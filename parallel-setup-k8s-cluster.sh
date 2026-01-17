#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CONTROL_PLANE_NAME="k8s-control"
WORKER1_NAME="k8s-worker1"
WORKER2_NAME="k8s-worker2"
BASTION_NAME="k8s-bastion"

CONTROL_PLANE_CPU=4
CONTROL_PLANE_MEM="4G"
CONTROL_PLANE_DISK="10G"

WORKER_CPU=2
WORKER_MEM="2G"
WORKER_DISK="10G"

BASTION_CPU=1
BASTION_MEM="1G"
BASTION_DISK="5G"

K8S_VERSION="1.35.0-1.1"
POD_CIDR="10.244.0.0/16"

echo -e "${GREEN}Starting Kubernetes cluster setup...${NC}"

# Create setup script for k8s nodes
cat > k8s-node-setup.sh <<'EOF'
#!/bin/bash
set -e

# Disable swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Load kernel modules
cat <<MODULES > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
MODULES
modprobe overlay
modprobe br_netfilter

# Setup kernel parameters
cat <<SYSCTL > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
SYSCTL
sysctl --system

# Install containerd
apt-get update
apt-get install -y containerd

# Configure containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Install kubeadm, kubelet, kubectl
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet
EOF

# Create bastion setup script
cat > bastion-setup.sh <<'EOF'
#!/bin/bash
set -e

# Detect architecture
ARCH=$(dpkg --print-architecture)

# Install kubectl
curl -LO "https://dl.k8s.io/release/v1.34.0/bin/linux/${ARCH}/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Install helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
EOF

echo -e "${YELLOW}Launching VMs in parallel...${NC}"

# Launch all VMs in parallel (much faster)
multipass launch --name $CONTROL_PLANE_NAME \
  --cpus $CONTROL_PLANE_CPU \
  --memory $CONTROL_PLANE_MEM \
  --disk $CONTROL_PLANE_DISK \
  24.04 &

sleep 5

multipass launch --name $WORKER1_NAME \
  --cpus $WORKER_CPU \
  --memory $WORKER_MEM \
  --disk $WORKER_DISK \
  24.04 && sleep 5 &

sleep 5

multipass launch --name $WORKER2_NAME \
  --cpus $WORKER_CPU \
  --memory $WORKER_MEM \
  --disk $WORKER_DISK \
  24.04 && sleep 5 &

sleep 5

multipass launch --name $BASTION_NAME \
  --cpus $BASTION_CPU \
  --memory $BASTION_MEM \
  --disk $BASTION_DISK \
  24.04 && sleep 5 &

# Wait for all VMs to be created
wait

echo -e "${GREEN}All VMs launched!${NC}"

# Get IP addresses
CONTROL_PLANE_IP=$(multipass info $CONTROL_PLANE_NAME | grep IPv4 | awk '{print $2}')
WORKER1_IP=$(multipass info $WORKER1_NAME | grep IPv4 | awk '{print $2}')
WORKER2_IP=$(multipass info $WORKER2_NAME | grep IPv4 | awk '{print $2}')
BASTION_IP=$(multipass info $BASTION_NAME | grep IPv4 | awk '{print $2}')

echo "Control Plane: $CONTROL_PLANE_IP"
echo "Worker 1: $WORKER1_IP"
echo "Worker 2: $WORKER2_IP"
echo "Bastion: $BASTION_IP"

echo -e "${YELLOW}Configuring k8s nodes in parallel...${NC}"

# Transfer and execute setup scripts in parallel
for node in $CONTROL_PLANE_NAME $WORKER1_NAME $WORKER2_NAME; do
  {
    multipass transfer k8s-node-setup.sh $node:/tmp/setup.sh
    multipass exec $node -- sudo bash /tmp/setup.sh
  } &
done

# Setup bastion in parallel
{
  multipass transfer bastion-setup.sh $BASTION_NAME:/tmp/setup.sh
  multipass exec $BASTION_NAME -- sudo bash /tmp/setup.sh
} &

# Wait for all setups to complete
wait

echo -e "${GREEN}All nodes configured!${NC}"

echo -e "${YELLOW}Initializing Kubernetes control plane (without default CNI)...${NC}"
multipass exec $CONTROL_PLANE_NAME -- sudo kubeadm init \
  --pod-network-cidr=$POD_CIDR \
  --apiserver-advertise-address=$CONTROL_PLANE_IP \
  --skip-phases=addon/kube-proxy

echo -e "${YELLOW}Setting up kubectl on control plane...${NC}"
multipass exec $CONTROL_PLANE_NAME -- bash -c "mkdir -p /home/ubuntu/.kube && sudo cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config && sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config"

echo -e "${YELLOW}Installing Cilium CLI and CNI...${NC}"
multipass exec $CONTROL_PLANE_NAME -- bash -c "CILIUM_CLI_VERSION=\$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt) && CLI_ARCH=\$(dpkg --print-architecture | sed 's/amd64/amd64/' | sed 's/arm64/arm64/') && curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/\${CILIUM_CLI_VERSION}/cilium-linux-\${CLI_ARCH}.tar.gz && sudo tar xzvfC cilium-linux-\${CLI_ARCH}.tar.gz /usr/local/bin && rm cilium-linux-\${CLI_ARCH}.tar.gz"

multipass exec $CONTROL_PLANE_NAME -- cilium install --version 1.16.5

echo -e "${YELLOW}Waiting for Cilium to be ready...${NC}"
multipass exec $CONTROL_PLANE_NAME -- cilium status --wait

echo -e "${YELLOW}Joining worker nodes to cluster in parallel...${NC}"
JOIN_CMD=$(multipass exec $CONTROL_PLANE_NAME -- sudo kubeadm token create --print-join-command)

multipass exec $WORKER1_NAME -- sudo $JOIN_CMD &
multipass exec $WORKER2_NAME -- sudo $JOIN_CMD &
wait

echo -e "${YELLOW}Copying kubeconfig to bastion...${NC}"
multipass exec $CONTROL_PLANE_NAME -- sudo cat /etc/kubernetes/admin.conf > /tmp/admin.conf
multipass transfer /tmp/admin.conf $BASTION_NAME:/tmp/config
multipass exec $BASTION_NAME -- bash -c "mkdir -p /home/ubuntu/.kube && mv /tmp/config /home/ubuntu/.kube/config && chown ubuntu:ubuntu /home/ubuntu/.kube/config"
rm /tmp/admin.conf

echo -e "${YELLOW}Waiting for all nodes to be ready...${NC}"
sleep 10
multipass exec $BASTION_NAME -- kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo -e "${GREEN}Cluster setup complete!${NC}"
echo ""
echo "To access your cluster, run:"
echo "  multipass shell $BASTION_NAME"
echo ""
echo "Then use kubectl commands, for example:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo ""
echo "Cluster information:"
multipass exec $BASTION_NAME -- kubectl get nodes -o wide

# Cleanup
rm k8s-node-setup.sh bastion-setup.sh

echo -e "${GREEN}Setup script completed successfully!${NC}"
