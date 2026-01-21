#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTROL_PLANE_NAME="k8s-control"
WORKER1_NAME="k8s-worker1"
WORKER2_NAME="k8s-worker2"
BASTION_NAME="k8s-bastion"

VMS=($CONTROL_PLANE_NAME $WORKER1_NAME $WORKER2_NAME $BASTION_NAME)

# Function to display usage
usage() {
  echo -e "${BLUE}Usage: $0 {start|stop|restart|status}${NC}"
  echo ""
  echo "Commands:"
  echo "  start    - Start all cluster VMs"
  echo "  stop     - Stop all cluster VMs"
  echo "  restart  - Restart all cluster VMs"
  echo "  status   - Show status of all cluster VMs"
  echo ""
  echo "Examples:"
  echo "  $0 start"
  echo "  $0 stop"
  echo "  $0 status"
  exit 1
}

# Function to check if VMs exist
check_vms_exist() {
  local found=0
  for vm in "${VMS[@]}"; do
    if multipass list | grep -q "^$vm"; then
      found=1
      break
    fi
  done
  
  if [ $found -eq 0 ]; then
    echo -e "${RED}Error: No cluster VMs found${NC}"
    echo "Please run ./setup-k8s-cluster.sh first to create the cluster"
    exit 1
  fi
}

# Function to start VMs
start_vms() {
  echo -e "${YELLOW}Starting cluster VMs...${NC}"
  
  local started=0
  for vm in "${VMS[@]}"; do
    if multipass list | grep -q "^$vm"; then
      local state=$(multipass list | grep "^$vm" | awk '{print $2}')
      if [ "$state" == "Stopped" ]; then
        echo -e "${YELLOW}Starting $vm...${NC}"
        multipass start $vm &
        started=1
      else
        echo -e "${GREEN}$vm is already running${NC}"
      fi
    fi
  done
  
  if [ $started -eq 1 ]; then
    wait
    echo -e "${GREEN}All VMs started successfully!${NC}"
  else
    echo -e "${GREEN}All VMs were already running${NC}"
  fi
  
  echo ""
  show_status
}

# Function to stop VMs
stop_vms() {
  echo -e "${YELLOW}Stopping cluster VMs...${NC}"
  
  local stopped=0
  for vm in "${VMS[@]}"; do
    if multipass list | grep -q "^$vm"; then
      local state=$(multipass list | grep "^$vm" | awk '{print $2}')
      if [ "$state" == "Running" ]; then
        echo -e "${YELLOW}Stopping $vm...${NC}"
        multipass stop $vm &
        stopped=1
      else
        echo -e "${BLUE}$vm is already stopped${NC}"
      fi
    fi
  done
  
  if [ $stopped -eq 1 ]; then
    wait
    echo -e "${GREEN}All VMs stopped successfully!${NC}"
  else
    echo -e "${BLUE}All VMs were already stopped${NC}"
  fi
  
  echo ""
  show_status
}

# Function to restart VMs
restart_vms() {
  echo -e "${YELLOW}Restarting cluster VMs...${NC}"
  
  # Stop first
  for vm in "${VMS[@]}"; do
    if multipass list | grep -q "^$vm"; then
      local state=$(multipass list | grep "^$vm" | awk '{print $2}')
      if [ "$state" == "Running" ]; then
        echo -e "${YELLOW}Stopping $vm...${NC}"
        multipass stop $vm &
      fi
    fi
  done
  wait
  
  sleep 2
  
  # Then start
  for vm in "${VMS[@]}"; do
    if multipass list | grep -q "^$vm"; then
      echo -e "${YELLOW}Starting $vm...${NC}"
      multipass start $vm &
    fi
  done
  wait
  
  echo -e "${GREEN}All VMs restarted successfully!${NC}"
  echo ""
  show_status
}

# Function to show status
show_status() {
  echo -e "${BLUE}Cluster VM Status:${NC}"
  echo ""
  
  local all_running=1
  local all_stopped=1
  
  for vm in "${VMS[@]}"; do
    if multipass list | grep -q "^$vm"; then
      local state=$(multipass list | grep "^$vm" | awk '{print $2}')
      local ip=$(multipass list | grep "^$vm" | awk '{print $3}')
      
      if [ "$state" == "Running" ]; then
        echo -e "  ${GREEN}●${NC} $vm - ${GREEN}Running${NC} ($ip)"
        all_stopped=0
      else
        echo -e "  ${RED}●${NC} $vm - ${RED}Stopped${NC}"
        all_running=0
      fi
    else
      echo -e "  ${RED}✗${NC} $vm - ${RED}Not Found${NC}"
      all_running=0
      all_stopped=0
    fi
  done
  
  echo ""
  
  if [ $all_running -eq 1 ]; then
    echo -e "${GREEN}All cluster VMs are running${NC}"
    echo ""
    echo "Access the cluster:"
    echo "  multipass shell $BASTION_NAME"
    echo "  OR"
    echo "  ssh $BASTION_NAME  (if SSH is configured)"
  elif [ $all_stopped -eq 1 ]; then
    echo -e "${BLUE}All cluster VMs are stopped${NC}"
    echo ""
    echo "Start the cluster:"
    echo "  $0 start"
  else
    echo -e "${YELLOW}Cluster VMs are in mixed state${NC}"
  fi
}

# Main logic
if [ $# -eq 0 ]; then
  usage
fi

COMMAND=$1

case $COMMAND in
  start)
    check_vms_exist
    start_vms
    ;;
  stop)
    check_vms_exist
    stop_vms
    ;;
  restart)
    check_vms_exist
    restart_vms
    ;;
  status)
    check_vms_exist
    show_status
    ;;
  *)
    echo -e "${RED}Error: Unknown command '$COMMAND'${NC}"
    echo ""
    usage
    ;;
esac
