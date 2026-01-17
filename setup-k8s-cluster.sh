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

CONTROL_PLANE_CPU=2
CONTROL_PLANE_MEM="2G"
CONTROL_PLANE_DISK="10G"

WORKER_CPU=2
WORKER_MEM="2G"
WORKER_DISK="10G"

BASTION_CPU=1
BASTION_MEM="1G"
BASTION_DISK="5G"

K8S_VERSION="1.34.0-00"
POD_CIDR="10.244.0.0/16"

echo -e "${GREEN}Starting Kubernetes cluster setup...${NC}"

# Create cloud-init file for control plane
cat > control-plane-init.yaml <<EOF
#cloud-config
package_update: true
package_upgrade: true
packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - lsb-release

runcmd:
  # Disable swap
  - swapoff -a
  - sed -i '/ swap / s/^/#/' /etc/fstab
  
  # Load kernel modules
  - modprobe overlay
  - modprobe br_netfilter
  
  # Setup kernel parameters
  - |
    cat <<SYSCTL > /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward = 1
    SYSCTL
  - sysctl --system
  
  # Install containerd
  - mkdir -p /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  - echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  - apt-get update
  - apt-get install -y containerd.io
  
  # Configure containerd
  - mkdir -p /etc/containerd
  - containerd config default | tee /etc/containerd/config.toml
  - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  - systemctl restart containerd
  - systemctl enable containerd
  
  # Install kubeadm, kubelet, kubectl
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
  - apt-get update
  - apt-get install -y kubelet=${K8S_VERSION} kubeadm=${K8S_VERSION} kubectl=${K8S_VERSION}
  - apt-mark hold kubelet kubeadm kubectl
  - systemctl enable kubelet
EOF

# Create cloud-init file for worker nodes
cat > worker-init.yaml <<EOF
#cloud-config
package_update: true
package_upgrade: true
packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - lsb-release

runcmd:
  # Disable swap
  - swapoff -a
  - sed -i '/ swap / s/^/#/' /etc/fstab
  
  # Load kernel modules
  - modprobe overlay
  - modprobe br_netfilter
  
  # Setup kernel parameters
  - |
    cat <<SYSCTL > /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward = 1
    SYSCTL
  - sysctl --system
  
  # Install containerd
  - mkdir -p /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  - echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  - apt-get update
  - apt-get install -y containerd.io
  
  # Configure containerd
  - mkdir -p /etc/containerd
  - containerd config default | tee /etc/containerd/config.toml
  - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  - systemctl restart containerd
  - systemctl enable containerd
  
  # Install kubeadm, kubelet, kubectl
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
  - apt-get update
  - apt-get install -y kubelet=${K8S_VERSION} kubeadm=${K8S_VERSION} kubectl=${K8S_VERSION}
  - apt-mark hold kubelet kubeadm kubectl
  - systemctl enable kubelet
EOF

# Create cloud-init file for bastion
cat > bastion-init.yaml <<EOF
#cloud-config
package_update: true
package_upgrade: true
packages:
  - curl
  - wget

runcmd:
  # Install kubectl
  - curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
  - install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  - rm kubectl
  
  # Install helm
  - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
EOF

echo -e "${YELLOW}Launching VMs...${NC}"

# Launch control plane
echo -e "${YELLOW}Creating control plane VM...${NC}"
multipass launch --name $CONTROL_PLANE_NAME \
  --cpus $CONTROL_PLANE_CPU \
  --memory $CONTROL_PLANE_MEM \
  --disk $CONTROL_PLANE_DISK \
  --cloud-init control-plane-init.yaml \
  22.04

# Launch worker nodes
echo -e "${YELLOW}Creating worker node 1...${NC}"
multipass launch --name $WORKER1_NAME \
  --cpus $WORKER_CPU \
  --memory $WORKER_MEM \
  --disk $WORKER_DISK \
  --cloud-init worker-init.yaml \
  22.04

echo -e "${YELLOW}Creating worker node 2...${NC}"
multipass launch --name $WORKER2_NAME \
  --cpus $WORKER_CPU \
  --memory $WORKER_MEM \
  --disk $WORKER_DISK \
  --cloud-init worker-init.yaml \
  22.04

# Launch bastion
echo -e "${YELLOW}Creating bastion VM...${NC}"
multipass launch --name $BASTION_NAME \
  --cpus $BASTION_CPU \
  --memory $BASTION_MEM \
  --disk $BASTION_DISK \
  --cloud-init bastion-init.yaml \
  22.04

echo -e "${YELLOW}Waiting for VMs to be ready...${NC}"
sleep 30

# Get IP addresses
CONTROL_PLANE_IP=$(multipass info $CONTROL_PLANE_NAME | grep IPv4 | awk '{print $2}')
WORKER1_IP=$(multipass info $WORKER1_NAME | grep IPv4 | awk '{print $2}')
WORKER2_IP=$(multipass info $WORKER2_NAME | grep IPv4 | awk '{print $2}')
BASTION_IP=$(multipass info $BASTION_NAME | grep IPv4 | awk '{print $2}')

echo -e "${GREEN}VMs created successfully!${NC}"
echo "Control Plane: $CONTROL_PLANE_IP"
echo "Worker 1: $WORKER1_IP"
echo "Worker 2: $WORKER2_IP"
echo "Bastion: $BASTION_IP"

echo -e "${YELLOW}Waiting for cloud-init to complete on all nodes...${NC}"
for vm in $CONTROL_PLANE_NAME $WORKER1_NAME $WORKER2_NAME $BASTION_NAME; do
  echo "Waiting for $vm..."
  multipass exec $vm -- cloud-init status --wait
done

echo -e "${YELLOW}Initializing Kubernetes control plane (without default CNI)...${NC}"
multipass exec $CONTROL_PLANE_NAME -- sudo kubeadm init \
  --pod-network-cidr=$POD_CIDR \
  --apiserver-advertise-address=$CONTROL_PLANE_IP \
  --skip-phases=addon/kube-proxy

echo -e "${YELLOW}Setting up kubectl on control plane...${NC}"
multipass exec $CONTROL_PLANE_NAME -- bash -c "mkdir -p /home/ubuntu/.kube && sudo cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config && sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config"

echo -e "${YELLOW}Installing Cilium CNI...${NC}"
multipass exec $CONTROL_PLANE_NAME -- bash -c "curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz && sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin && rm cilium-linux-amd64.tar.gz"

multipass exec $CONTROL_PLANE_NAME -- cilium install --version 1.14.5

echo -e "${YELLOW}Waiting for Cilium to be ready...${NC}"
multipass exec $CONTROL_PLANE_NAME -- cilium status --wait

echo -e "${YELLOW}Getting join command...${NC}"
JOIN_CMD=$(multipass exec $CONTROL_PLANE_NAME -- sudo kubeadm token create --print-join-command)

echo -e "${YELLOW}Joining worker nodes to cluster...${NC}"
multipass exec $WORKER1_NAME -- sudo $JOIN_CMD
multipass exec $WORKER2_NAME -- sudo $JOIN_CMD

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

# Cleanup cloud-init files
rm control-plane-init.yaml worker-init.yaml bastion-init.yaml

echo -e "${GREEN}Setup script completed successfully!${NC}"
