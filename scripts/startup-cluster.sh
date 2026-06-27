#!/bin/bash
set -e
set -x

echo ""
echo "================================================"
echo "   Kubernetes Cluster Startup Starting"
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
echo "================================================"
echo ""
