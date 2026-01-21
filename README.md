# Kubernetes Cluster on Multipass

Automated scripts to set up a local Kubernetes cluster using Multipass on macOS (Apple Silicon).

## Overview

This project provides automated scripts to deploy a fully functional Kubernetes cluster with Cilium CNI on your local machine using Multipass VMs. Perfect for development, testing, and learning Kubernetes.

## Cluster Architecture

- **1 Control Plane Node** (4 CPU, 4GB RAM, 10GB Disk)
- **2 Worker Nodes** (2 CPU, 2GB RAM, 10GB Disk each)
- **1 Bastion Node** (1 CPU, 1GB RAM, 5GB Disk)

## Features

- Kubernetes 1.34
- Ubuntu 24.04 LTS
- Cilium CNI (latest stable version)
- ARM64 architecture support (Apple Silicon)
- Parallel VM creation for faster setup
- Pre-configured kubectl access from bastion
- Helm pre-installed on bastion
- SSH access configuration
- Start/stop cluster management
- One-command cluster creation and teardown

## Prerequisites

- macOS with Apple Silicon (M1/M2/M3/M4)
- [Multipass](https://multipass.run/) installed
- SSH key generated at `~/.ssh/id_rsa` (optional, for SSH access)

### Install Multipass

```bash
brew install --cask multipass
```

### Generate SSH Key (if you don't have one)

```bash
ssh-keygen -t rsa -b 4096
```

## Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd <repository-name>
```

### 2. Make Scripts Executable

```bash
chmod +x setup-k8s-cluster.sh teardown-k8s-cluster.sh setup-ssh-access.sh control-cluster.sh
```

### 3. Create the Cluster

```bash
./setup-k8s-cluster.sh
```

This will take approximately **3-5 minutes** to complete.

### 4. Access the Cluster

#### Option A: Using Multipass Shell

```bash
multipass shell k8s-bastion
kubectl get nodes
kubectl get pods -A
```

#### Option B: Using SSH (Recommended)

Set up SSH access for easier connection:

```bash
./setup-ssh-access.sh k8s-bastion
ssh k8s-bastion
```

### 5. Verify Cluster

```bash
kubectl get nodes
kubectl get pods -A
cilium status
```

### 6. Control the Cluster (Start/Stop)
Pause and resume your cluster without destroying it:

```
# Stop all VMs (saves resources when not in use)
./control-cluster.sh stop

# Start all VMs
./control-cluster.sh start

# Restart all VMs
./control-cluster.sh restart

# Check cluster status
./control-cluster.sh status
```

### 7. Tear Down the Cluster

When you're done, clean up all resources:

```bash
./teardown-k8s-cluster.sh
```

## Scripts

### `setup-k8s-cluster.sh`

Creates the entire Kubernetes cluster including:
- VM provisioning (parallel)
- Kubernetes installation (kubeadm, kubelet, kubectl)
- Containerd runtime configuration
- Control plane initialization
- Cilium CNI installation
- Worker node joining
- Kubeconfig distribution to bastion

### `teardown-k8s-cluster.sh`

Safely removes all cluster VMs with confirmation prompt.

### `control-cluster.sh`

Manages cluster VM lifecycle without destroying data:
- **`start`** - Starts all stopped VMs
- **`stop`** - Stops all running VMs (saves resources)
- **`restart`** - Restarts all VMs
- **`status`** - Shows current state of all VMs

**Usage:**

```bash
./control-cluster.sh start
./control-cluster.sh stop
./control-cluster.sh restart
./control-cluster.sh status
```

This is useful when you want to pause your cluster to save system resources but don't want to tear it down completely.

### `setup-ssh-access.sh`

Configures SSH access to Multipass VMs:
- Transfers your SSH public key to the VM
- Updates `~/.ssh/config` with VM entry
- Enables direct SSH using: `ssh <vm-name>`

**Usage:**

```bash
./setup-ssh-access.sh <vm-name>
```

**Example:**

```bash
./setup-ssh-access.sh k8s-bastion
./setup-ssh-access.sh k8s-control
./setup-ssh-access.sh k8s-worker1
./setup-ssh-access.sh k8s-worker2
```

## VM Details

| VM Name | Role | IP Address | Resources |
|---------|------|------------|-----------|
| k8s-control | Control Plane | Auto-assigned | 4 CPU, 4GB RAM, 10GB Disk |
| k8s-worker1 | Worker Node | Auto-assigned | 2 CPU, 2GB RAM, 10GB Disk |
| k8s-worker2 | Worker Node | Auto-assigned | 2 CPU, 2GB RAM, 10GB Disk |
| k8s-bastion | Bastion/Client | Auto-assigned | 1 CPU, 1GB RAM, 5GB Disk |

## Configuration

You can customize the cluster configuration by editing variables at the top of `setup-k8s-cluster.sh`:

```bash
# VM Names
CONTROL_PLANE_NAME="k8s-control"
WORKER1_NAME="k8s-worker1"
WORKER2_NAME="k8s-worker2"
BASTION_NAME="k8s-bastion"

# Resources
CONTROL_PLANE_CPU=4
CONTROL_PLANE_MEM="4G"
CONTROL_PLANE_DISK="10G"

# Kubernetes Version
K8S_VERSION="1.34.0-1.1"

# Pod Network CIDR
POD_CIDR="10.244.0.0/16"
```

## Useful Commands

### Cluster Control

```bash
# Check cluster status
./control-cluster.sh status

# Stop cluster (save resources)
./control-cluster.sh stop

# Start cluster
./control-cluster.sh start

# Restart cluster
./control-cluster.sh restart
```

### Check VM Status

```bash
multipass list
```

### Get VM Info

```bash
multipass info k8s-control
```

### Shell into VMs

```bash
multipass shell k8s-bastion
multipass shell k8s-control
multipass shell k8s-worker1
```

### Stop/Start VMs

```bash
multipass stop k8s-control
multipass start k8s-control
```

### Access Kubernetes from Bastion

```bash
ssh k8s-bastion
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

## Known Limitations

### IP Address Allocation Issue

**Multipass does not handle multi-processing well.** When multiple VMs are created simultaneously, there is a possibility that two or more VMs may be allocated the same IP address. This is a known limitation of Multipass's DHCP/networking layer when handling concurrent VM launches.

**Symptoms:**
- Two or more VMs showing identical IP addresses
- Network connectivity issues between nodes
- Cluster initialization or node join failures

**Solution:**

If you encounter duplicate IP addresses:

1. Tear down the cluster:
   ```bash
   ./teardown-k8s-cluster.sh
   ```

2. Recreate the cluster:
   ```bash
   ./setup-k8s-cluster.sh
   ```

The script includes IP address validation and waiting periods to minimize this issue, but it may still occur occasionally due to Multipass's limitations.

**Workaround:**

~~If the issue persists, you can modify the `setup-k8s-cluster.sh` script to launch VMs sequentially instead of in parallel by removing the `&` background operators, though this will increase setup time.~~

I have added 5s sleep between VM creation. An acceptable trade-off to avoid frustating setup failures due to IP conflicts.

## Troubleshooting

### Cluster nodes not ready

Wait a few moments for Cilium to fully initialize:

```bash
kubectl get nodes --watch
```

### Cilium pods not running

Check Cilium status:

```bash
ssh k8s-control
cilium status
```

### Can't access bastion

Ensure the VM is running:

```bash
multipass list
multipass start k8s-bastion
```

### SSH connection fails

Re-run the SSH setup script:

```bash
./setup-ssh-access.sh k8s-bastion
```

## Architecture Highlights

- **CNI:** Cilium (eBPF-based networking, replaces kube-proxy)
- **Container Runtime:** containerd with systemd cgroup driver
- **OS:** Ubuntu 24.04 LTS (ARM64)
- **Kubernetes:** v1.34 (latest stable)

## Credits

Built for local Kubernetes development on Apple Silicon Macs using Multipass and Cilium CNI.
