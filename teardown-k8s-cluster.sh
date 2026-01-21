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

echo -e "${YELLOW}Starting Kubernetes cluster teardown...${NC}"

# Check if VMs exist
VMS=($CONTROL_PLANE_NAME $WORKER1_NAME $WORKER2_NAME $BASTION_NAME)
EXISTING_VMS=()

for vm in "${VMS[@]}"; do
  if multipass list | grep -q "^$vm"; then
    EXISTING_VMS+=($vm)
  fi
done

if [ ${#EXISTING_VMS[@]} -eq 0 ]; then
  echo -e "${YELLOW}No cluster VMs found. Nothing to tear down.${NC}"
  exit 0
fi

echo -e "${YELLOW}Found the following cluster VMs:${NC}"
for vm in "${EXISTING_VMS[@]}"; do
  echo "  - $vm"
done

# Ask for confirmation
# echo -e "${RED}Warning: This will permanently delete all cluster VMs and data.${NC}"
# read -p "Are you sure you want to proceed? (yes/no): " confirmation
# 
# if [ "$confirmation" != "yes" ]; then
#   echo -e "${YELLOW}Teardown cancelled.${NC}"
#   exit 0
# fi

echo -e "${YELLOW}Stopping and deleting VMs...${NC}"

for vm in "${EXISTING_VMS[@]}"; do
  echo -e "${YELLOW}Deleting $vm...${NC}"
  multipass delete $vm
done

echo -e "${YELLOW}Purging deleted VMs...${NC}"
multipass purge

echo -e "${GREEN}Cluster teardown complete!${NC}"
echo "All VMs have been removed."
