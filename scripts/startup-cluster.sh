#!/bin/bash
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p ~/gpu-kubernetes-lab/logs
LOGFILE=~/gpu-kubernetes-lab/logs/startup-$(date +%Y%m%d-%H%M%S).log
exec > >(tee -a "$LOGFILE") 2>&1

echo -e "${CYAN}"
echo "================================================"
echo "   Kubernetes Cluster Startup Starting"
echo "   Log file: $LOGFILE"
echo -e "================================================${NC}"
echo ""

echo -e "${YELLOW}===> [1/5] Starting control-plane first...${NC}"
limactl start control-plane
echo -e "${GREEN}===> [1/5] Done.${NC}"

echo -e "${YELLOW}===> [2/5] Starting worker nodes in parallel...${NC}"
limactl start worker-1 &
limactl start worker-2 &
limactl start worker-3 &
wait
echo -e "${GREEN}===> [2/5] Done.${NC}"

echo -e "${YELLOW}===> [3/5] Waiting 30 seconds for cluster to stabilise...${NC}"
sleep 30
echo -e "${GREEN}===> [3/5] Done.${NC}"

echo -e "${YELLOW}===> [4/5] Uncordoning worker nodes...${NC}"
limactl shell control-plane -- kubectl uncordon lima-worker-1
limactl shell control-plane -- kubectl uncordon lima-worker-2
limactl shell control-plane -- kubectl uncordon lima-worker-3
echo -e "${GREEN}===> [4/5] Done.${NC}"

echo -e "${YELLOW}===> [5/5] Checking cluster status...${NC}"
limactl shell control-plane -- kubectl get nodes
echo -e "${GREEN}===> [5/5] Done.${NC}"

echo ""
echo -e "${CYAN}"
echo "================================================"
echo "   Cluster is up and ready"
echo -e "   Full log saved to: $LOGFILE${NC}"
echo "================================================"
echo ""
