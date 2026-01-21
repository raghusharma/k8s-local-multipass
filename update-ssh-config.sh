#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default SSH key location
SSH_KEY="$HOME/.ssh/id_rsa.pub"
SSH_CONFIG="$HOME/.ssh/config"

# Check if VM name is provided
if [ -z "$1" ]; then
  echo -e "${RED}Error: VM name not provided${NC}"
  echo "Usage: $0 <vm_name>"
  echo ""
  echo "Example: $0 k8s-bastion"
  echo ""
  echo "Available VMs:"
  multipass list
  exit 1
fi

VM_NAME="$1"

# Check if VM exists
if ! multipass list | grep -q "^$VM_NAME"; then
  echo -e "${RED}Error: VM '$VM_NAME' not found${NC}"
  echo ""
  echo "Available VMs:"
  multipass list
  exit 1
fi

# Check if SSH key exists
if [ ! -f "$SSH_KEY" ]; then
  echo -e "${RED}Error: SSH public key not found at $SSH_KEY${NC}"
  echo "Please generate an SSH key first with: ssh-keygen -t rsa -b 4096"
  exit 1
fi

echo -e "${YELLOW}Setting up SSH access for VM: $VM_NAME${NC}"

# Get VM IP address
VM_IP=$(multipass info "$VM_NAME" | grep IPv4 | awk '{print $2}')

if [ -z "$VM_IP" ] || [ "$VM_IP" == "--" ]; then
  echo -e "${RED}Error: Could not get IP address for VM '$VM_NAME'${NC}"
  exit 1
fi

echo "VM IP address: $VM_IP"

# Read the public key
PUB_KEY=$(cat "$SSH_KEY")

# Add SSH key to VM's authorized_keys
echo -e "${YELLOW}Adding SSH key to VM...${NC}"
multipass exec "$VM_NAME" -- bash -c "mkdir -p /home/ubuntu/.ssh && chmod 700 /home/ubuntu/.ssh && echo '$PUB_KEY' >> /home/ubuntu/.ssh/authorized_keys && chmod 600 /home/ubuntu/.ssh/authorized_keys && chown -R ubuntu:ubuntu /home/ubuntu/.ssh"

echo -e "${GREEN}SSH key added successfully!${NC}"

# Backup SSH config if it exists
if [ -f "$SSH_CONFIG" ]; then
  cp "$SSH_CONFIG" "$SSH_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
  echo -e "${YELLOW}Backed up existing SSH config${NC}"
fi

# Create SSH config directory if it doesn't exist
mkdir -p "$HOME/.ssh"

# Check if entry already exists in SSH config
if grep -q "^Host $VM_NAME$" "$SSH_CONFIG" 2>/dev/null; then
  echo -e "${YELLOW}Entry for '$VM_NAME' already exists in SSH config${NC}"
  echo -e "${YELLOW}Updating existing entry...${NC}"
  
  # Remove old entry
  sed -i.tmp "/^Host $VM_NAME$/,/^$/d" "$SSH_CONFIG"
  rm -f "$SSH_CONFIG.tmp"
fi

# Add new SSH config entry
cat >> "$SSH_CONFIG" <<EOF

Host $VM_NAME
    HostName $VM_IP
    User ubuntu
    IdentityFile ~/.ssh/id_rsa
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR

EOF

echo -e "${GREEN}SSH config updated!${NC}"

# Set proper permissions on SSH config
chmod 600 "$SSH_CONFIG"

echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "You can now SSH into the VM using:"
echo -e "${GREEN}  ssh $VM_NAME${NC}"
echo ""
echo "Testing connection..."
echo ""

# Test SSH connection
if ssh -o ConnectTimeout=5 "$VM_NAME" "echo 'SSH connection successful!'" 2>/dev/null; then
  echo -e "${GREEN}✓ SSH connection test passed!${NC}"
else
  echo -e "${YELLOW}⚠ SSH connection test failed. You may need to wait a moment and try again.${NC}"
  echo "Run: ssh $VM_NAME"
fi
