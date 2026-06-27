#!/bin/bash
set -e
set -x

mkdir -p ~/gpu-kubernetes-lab/logs

LOGFILE=~/gpu-kubernetes-lab/logs/shutdown-$(date +%Y%m%d-%H%M%S).log

exec > >(tee -a "$LOGFILE") 2>&1

echo ""
echo "================================================"
echo "   Kubernetes Cluster Shutdown Starting"
echo "   Log file: $LOGFILE"
echo "================================================"
echo ""

echo "===> [1/4] Cordoning worker nodes..."
limactl shell control-plane -- kubectl cordon lima-worker-1
limactl shell control-plane -- kubectl cordon lima-worker-2
limactl shell control-plane -- kubectl cordon lima-worker-3
echo "===> [1/4] Done."

echo "===> [2/4] Stopping worker-1..."
limactl stop worker-1
echo "===> [2/4] Done."

echo "===> [3/4] Stopping worker-2 and worker-3..."
limactl stop worker-2
limactl stop worker-3
echo "===> [3/4] Done."

echo "===> [4/4] Stopping control-plane last..."
limactl stop control-plane
echo "===> [4/4] Done."

echo ""
echo "================================================"
echo "   Cluster shutdown complete"
echo "   Full log saved to: $LOGFILE"
echo "================================================"
echo ""

limactl list
