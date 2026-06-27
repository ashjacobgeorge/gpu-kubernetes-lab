#!/bin/bash
set -e
set -x

mkdir -p ~/gpu-kubernetes-lab/logs

LOGFILE=~/gpu-kubernetes-lab/logs/startup-$(date +%Y%m%d-%H%M%S).log

exec > >(tee -a "$LOGFILE") 2>&1

echo ""
echo "================================================"
echo "   Kubernetes Cluster Startup Starting"
echo "   Log file: $LOGFILE"
echo "================================================"
echo ""

echo "===> [1/5] Starting control-plane first..."
limactl start control-plane
echo "===> [1/5] Done."

echo "===> [2/5] Starting worker nodes in parallel..."
limactl start worker-1 &
limactl start worker-2 &
limactl start worker-3 &
wait
echo "===> [2/5] Done."

echo "===> [3/5] Waiting 30 seconds for cluster to stabilise..."
sleep 30
echo "===> [3/5] Done."

echo "===> [4/5] Uncordoning worker nodes..."
limactl shell control-plane -- kubectl uncordon lima-worker-1
limactl shell control-plane -- kubectl uncordon lima-worker-2
limactl shell control-plane -- kubectl uncordon lima-worker-3
echo "===> [4/5] Done."

echo "===> [5/5] Checking cluster status..."
limactl shell control-plane -- kubectl get nodes
echo "===> [5/5] Done."

echo ""
echo "================================================"
echo "   Cluster is up and ready"
echo "   Full log saved to: $LOGFILE"
echo "================================================"
echo ""
