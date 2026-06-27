#!/bin/bash
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # NC = No Color = reset

mkdir -p ~/gpu-kubernetes-lab/logs
LOGFILE=~/gpu-kubernetes-lab/logs/shutdown-$(date +%Y%m%d-%H%M%S).log
exec > >(tee -a "$LOGFILE") 2>&1

echo -e "${CYAN}"
echo "================================================"
echo "   Kubernetes Cluster Shutdown Starting"
echo "   Log file: $LOGFILE"
echo -e "================================================${NC}"
echo ""

echo -e "${YELLOW}===> [1/4] Cordoning worker nodes...${NC}"
limactl shell control-plane -- kubectl cordon lima-worker-1
limactl shell control-plane -- kubectl cordon lima-worker-2
limactl shell control-plane -- kubectl cordon lima-worker-3
echo -e "${GREEN}===> [1/4] Done.${NC}"

echo -e "${YELLOW}===> [2/4] Stopping worker-1...${NC}"
limactl stop worker-1
echo -e "${GREEN}===> [2/4] Done.${NC}"

echo -e "${YELLOW}===> [3/4] Stopping worker-2 and worker-3...${NC}"
limactl stop worker-2
limactl stop worker-3
echo -e "${GREEN}===> [3/4] Done.${NC}"

echo -e "${YELLOW}===> [4/4] Stopping control-plane last...${NC}"
limactl stop control-plane
echo -e "${GREEN}===> [4/4] Done.${NC}"

echo ""
echo -e "${CYAN}"
echo "================================================"
echo "   Cluster shutdown complete"
echo -e "   Full log saved to: $LOGFILE${NC}"
echo "================================================"
echo ""

limactl list
