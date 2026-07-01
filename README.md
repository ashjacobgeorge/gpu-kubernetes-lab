# GPU Kubernetes Lab

A production-grade 4-node Kubernetes cluster built from scratch on Apple M4 (16GB RAM)
using Lima VMs and kubeadm, with a full monitoring stack and GitOps deployment pipeline.
This lab simulates the infrastructure patterns used in GPU cloud platforms for AI workloads.

---

## Lab Overview

| Phase | Status | What I Built |
|-------|--------|--------------|
| Phase 1 | Complete ✓ | 4-node kubeadm cluster on Lima VMs with Flannel CNI |
| Phase 2A | Complete ✓ | Helm-based Prometheus and Grafana monitoring stack |
| Phase 2B | In Progress | Argo CD GitOps deployment pipeline |
| Phase 2C | Planned | NVIDIA GPU Operator simulation and multi-tenant scheduling |
| Phase 3 | Planned | Model serving with Triton Inference Server |

---

## Architecture

    Mac Host (Apple M4, 16GB RAM)
    |
    |-- control-plane  (2 CPU, 3.5GB RAM, 20GB disk)
    |   |-- etcd, kube-apiserver, kube-scheduler
    |   |-- kube-controller-manager
    |
    |-- worker-1  (2 CPU, 2GB RAM, 10GB disk)
    |-- worker-2  (2 CPU, 2GB RAM, 10GB disk)
    |-- worker-3  (2 CPU, 3GB RAM, 10GB disk)
        |-- kubelet, kube-proxy, Flannel, workloads

All nodes run Ubuntu 22.04 ARM64 natively on Apple Silicon via
Lima's Apple Virtualization framework. No emulation.

---

## Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| Kubernetes | v1.29.15 | Container orchestration |
| kubeadm | v1.29.15 | Cluster bootstrapping |
| containerd | v2.2.1 | Container runtime |
| Flannel | latest | Pod networking CNI |
| Lima | v2.1.3 | Linux VMs on Apple Silicon |
| Ubuntu | 22.04 LTS | Node operating system |
| Helm | v4.2.2 | Kubernetes package manager |
| kube-prometheus-stack | latest | Prometheus and Grafana monitoring |

---

## Phase 1 — 4-Node Kubernetes Cluster

Built a real multi-node Kubernetes cluster from scratch using kubeadm,
not a simplified single-node setup or managed Kubernetes service.

Key decisions and why:
- Lima over minikube/kind — real Linux VMs, not containers or abstractions
- kubeadm over k3s — full Kubernetes with all components visible and configurable
- Flannel CNI — simplest overlay network, correct foundation before adding complexity
- Ubuntu 22.04 — most widely used Linux distribution for Kubernetes in production
- Kubernetes v1.29 — mature, stable, fully supported by NVIDIA GPU Operator

Cluster status after Phase 1:

    NAME                 STATUS   ROLES           VERSION
    lima-control-plane   Ready    control-plane   v1.29.15
    lima-worker-1        Ready    worker          v1.29.15
    lima-worker-2        Ready    worker          v1.29.15
    lima-worker-3        Ready    worker          v1.29.15

Phase 1 documentation:
- docs/01-prerequisites.md — full setup from zero including SSH keys and socket_vmnet
- docs/02-design-decisions.md — why each tool was chosen over alternatives
- docs/03-troubleshooting.md — real issues hit and fixed during Phase 1

---

## Phase 2A — Helm Monitoring Stack

Deployed a production-grade Kubernetes monitoring stack using Helm,
the same approach used by companies running Kubernetes in production.

What is running:
- Prometheus — metrics collection and storage
- Grafana — dashboards and visualization
- kube-state-metrics — Kubernetes object state metrics
- node-exporter — host-level metrics on all 4 nodes (DaemonSet)
- Prometheus Operator — manages Prometheus via CRDs

Key decisions:
- kube-prometheus-stack umbrella chart — bundles everything needed
- Alertmanager disabled — not needed for a lab environment
- Resource limits explicitly set — prevents unbounded memory usage
  on a 16GB Mac running 4 VMs simultaneously
- Retention set to 1d — lab does not need 10 days of metric history

Dashboard screenshots (docs/screenshots/):

| Dashboard | What it shows |
|-----------|---------------|
| grafana-cluster-resources.png | CPU and memory across all namespaces |
| grafana-node-exporter.png | Host-level metrics per Lima VM node |
| grafana-networking.png | Pod-to-pod network traffic |
| prometheus-targets.png | Active scrape targets and their status |

Phase 2A documentation:
- docs/04-helm-monitoring.md — Helm concepts and full install steps
- docs/05-troubleshooting-phase2.md — issues hit during Phase 2

---

## Phase 2B — Argo CD GitOps (In Progress)

Installing Argo CD to manage cluster deployments declaratively via Git.
Instead of running helm install manually, Argo CD watches this repository
and automatically syncs the cluster state to match what is declared in Git.

This means:
- Git is the single source of truth for what runs in the cluster
- Any manual change to the cluster is detected as drift and can be auto-healed
- All deployment history is visible as Git commit history

---

## Repository Structure

    gpu-kubernetes-lab/
    |-- lima-configs/              VM blueprint files (Phase 1)
    |   |-- control-plane.yaml
    |   |-- worker-1.yaml
    |   |-- worker-2.yaml
    |   |-- worker-3.yaml
    |-- gitops-values/             Helm values files (Phase 2)
    |   |-- monitoring-values.yaml
    |-- scripts/                   Operational scripts
    |   |-- startup-cluster.sh
    |   |-- shutdown-cluster.sh
    |-- docs/                      Documentation
    |   |-- screenshots/           Dashboard screenshots
    |   |-- 01-prerequisites.md
    |   |-- 02-design-decisions.md
    |   |-- 03-troubleshooting.md
    |   |-- 04-helm-monitoring.md
    |   |-- 05-troubleshooting-phase2.md
    |-- .gitignore
    |-- README.md

---

## Quick Start

### Prerequisites
    brew install lima kubectl helm k9s

    git clone https://github.com/lima-vm/socket_vmnet.git
    cd socket_vmnet && git checkout v1.2.2
    make && sudo make PREFIX=/opt/socket_vmnet install.bin
    limactl sudoers > /tmp/lima-sudoers
    sudo install -o root /tmp/lima-sudoers /etc/sudoers.d/lima

### Start the cluster
    cd lima-configs
    limactl start control-plane.yaml
    limactl start worker-1.yaml &
    limactl start worker-2.yaml &
    limactl start worker-3.yaml &

### Bootstrap Kubernetes
    limactl shell control-plane
    sudo kubeadm init \
      --pod-network-cidr=10.244.0.0/16 \
      --kubernetes-version=v1.29.15 \
      --apiserver-advertise-address=<CONTROL-PLANE-IP>

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

### Join workers
    sudo kubeadm join <CONTROL-PLANE-IP>:6443 --token <token> \
      --discovery-token-ca-cert-hash sha256:<hash>

### Deploy monitoring stack
    kubectl create namespace monitoring
    helm install my-monitoring prometheus-community/kube-prometheus-stack \
      -f gitops-values/monitoring-values.yaml -n monitoring

---

## Operational Scripts

    # Start the cluster
    ~/gpu-kubernetes-lab/scripts/startup-cluster.sh

    # Shut down gracefully
    ~/gpu-kubernetes-lab/scripts/shutdown-cluster.sh

Both scripts include colored output, progress markers, timestamped
logging, and graceful node cordoning before shutdown.

---

## What I Learned

### Phase 1
- Kubernetes cluster architecture and all control plane component roles
- kubeadm bootstrap sequence and the full certificate generation process
- CNI networking concepts — how Flannel overlay networking works
- Lima VM management on Apple Silicon — vmType vz vs QEMU trade-offs
- Infrastructure as code with declarative YAML VM blueprints
- Debugging VM networking issues — vzNAT vs shared networking
- socket_vmnet installation requirements and Lima network modes
- macOS Sequoia Local Network privacy permission and its effect on
  VM connectivity

### Phase 2
- Helm chart structure — charts, values, releases, and revision history
- kube-prometheus-stack umbrella chart architecture
- Kubernetes Operator pattern and CRD-based resource management
- ServiceMonitor as the mechanism connecting apps to Prometheus scraping
- DaemonSet scheduling including toleration for control-plane taint
- Port-forward proxy chain from Mac browser to pod inside cluster
- Worker node InternalIP registration and kubelet --node-ip fix
- kubeadm cluster limitation for etcd and controller-manager metrics

---

## Next Steps

- Complete Argo CD GitOps pipeline (Phase 2B)
- NVIDIA GPU Operator simulation with fake-gpu-operator (Phase 2C)
- Multi-tenant GPU scheduling with priority classes
- Model serving with Triton Inference Server (Phase 3)
- Cloud GPU validation on Lambda Labs or vast.ai
