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
| Phase 2B | Complete ✓ | Argo CD GitOps deployment pipeline with drift detection |
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
| kube-prometheus-stack | v87.5.1 | Prometheus and Grafana monitoring |
| Argo CD | v3.4.4 | GitOps continuous delivery |

---

## Phase 1 — 4-Node Kubernetes Cluster

Built a real multi-node Kubernetes cluster from scratch using kubeadm,
not a simplified single-node setup or managed Kubernetes service.

Key decisions:
- Lima over minikube/kind — real Linux VMs, not containers or abstractions
- kubeadm over k3s — full Kubernetes with all components visible
- Flannel CNI — simplest overlay network, correct foundation before complexity
- Ubuntu 22.04 — most widely used Linux distribution for Kubernetes in production
- Kubernetes v1.29 — mature, stable, fully supported by NVIDIA GPU Operator

Cluster status after Phase 1:

    NAME                 STATUS   ROLES           VERSION
    lima-control-plane   Ready    control-plane   v1.29.15
    lima-worker-1        Ready    worker          v1.29.15
    lima-worker-2        Ready    worker          v1.29.15
    lima-worker-3        Ready    worker          v1.29.15

Phase 1 documentation:
- docs/01-prerequisites.md
- docs/02-design-decisions.md
- docs/03-troubleshooting.md

---

## Phase 2A — Helm Monitoring Stack

Deployed a production-grade Kubernetes monitoring stack using Helm,
the same approach used by companies running Kubernetes in production.

What is running:
- Prometheus — metrics collection and storage
- Grafana — dashboards and visualization
- kube-state-metrics — Kubernetes object state metrics
- node-exporter — host-level metrics on all 4 nodes via DaemonSet
- Prometheus Operator — manages Prometheus via CRDs

Key decisions:
- kube-prometheus-stack umbrella chart — bundles everything needed
- Alertmanager disabled — not needed for a lab environment
- Resource limits explicitly set — prevents unbounded memory usage
- Retention set to 1d — lab does not need 10 days of metric history

Dashboard screenshots in docs/screenshots/grafana-prometheus/:

| Screenshot | What it shows |
|------------|---------------|
| grafana-cluster-resources.png | CPU and memory across all namespaces |
| grafana-node-exporter.png | Host-level metrics per Lima VM node |
| grafana-networking.png | Pod-to-pod network traffic |
| prometheus-targets.png | Active scrape targets and their status |

Phase 2A documentation:
- docs/04-helm-monitoring.md
- docs/05-troubleshooting-phase2.md

---

## Phase 2B — Argo CD GitOps

Deployed Argo CD to manage cluster resources declaratively via Git.
Instead of running helm install manually, Argo CD watches this
repository and automatically syncs the cluster state to match
what is declared in Git.

What I demonstrated:

Drift detection — manually deleted the Grafana Deployment to simulate
an unauthorised manual change. Argo CD detected the cluster was
OutOfSync with Git and automatically recreated the Deployment within
seconds via selfHeal. The pod age difference (seconds vs 48 minutes
for other pods) proved the automatic recovery.

Server-side apply — required for large CRDs from kube-prometheus-stack
that exceed the 256KB Kubernetes annotation limit. Added
ServerSideApply=true to the Application syncOptions.

Multiple sources — used Argo CD's multi-source feature to reference
the Helm chart from prometheus-community and the values file from
my GitHub repo simultaneously.

Key GitOps concepts proven:
- Git as single source of truth for cluster state
- Automated sync on Git changes (no manual helm install needed)
- Self-healing — manual cluster changes automatically reverted
- 118 Kubernetes resources managed from one values file in Git
- Drift detection visible in real time via Argo CD UI

Argo CD UI screenshots in docs/screenshots/argocd/:

| Screenshot | What it shows |
|------------|---------------|
| argocd-applications-list.png | Applications overview |
| argocd-resource-tree.png | Visual resource tree (118 resources) |
| argocd-synced-healthy.png | Clean Synced and Healthy state |
| argocd-drift-detection-terminal.png | Pod age proving auto-recovery |
| argocd-drift-healed.png | Argo CD UI after drift healed |
| argocd-crd-annotation-error.png | CRD size limit error |
| argocd-sync-error.png | Sync error state for reference |

Phase 2B documentation:
- argocd-apps/monitoring-app.yaml

---

## Repository Structure

    gpu-kubernetes-lab/
    |-- lima-configs/              VM blueprint files (Phase 1)
    |   |-- control-plane.yaml
    |   |-- worker-1.yaml
    |   |-- worker-2.yaml
    |   |-- worker-3.yaml
    |-- gitops-values/             Helm values files (Phase 2A)
    |   |-- monitoring-values.yaml
    |-- argocd-apps/               Argo CD Application manifests (Phase 2B)
    |   |-- monitoring-app.yaml
    |-- scripts/                   Operational scripts
    |   |-- startup-cluster.sh
    |   |-- shutdown-cluster.sh
    |-- docs/                      Documentation
    |   |-- screenshots/
    |   |   |-- argocd/            Argo CD UI screenshots
    |   |   |-- grafana-prometheus/ Monitoring dashboard screenshots
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

### Deploy monitoring via Argo CD
    kubectl create namespace argocd
    kubectl apply -n argocd \
      -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
      --server-side --force-conflicts

    kubectl apply -f argocd-apps/monitoring-app.yaml

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
- CNI networking — how Flannel overlay networking works
- Lima VM management on Apple Silicon — vmType vz vs QEMU trade-offs
- Infrastructure as code with declarative YAML VM blueprints
- Debugging VM networking issues — vzNAT vs shared networking
- socket_vmnet installation requirements and Lima network modes

### Phase 2A
- Helm chart structure — charts, values, releases, and revision history
- kube-prometheus-stack umbrella chart architecture
- Kubernetes Operator pattern and CRD-based resource management
- ServiceMonitor as the mechanism connecting apps to Prometheus scraping
- DaemonSet scheduling including toleration for control-plane taint
- Port-forward proxy chain from Mac browser to pod inside cluster
- Worker node InternalIP registration and kubelet --node-ip fix

### Phase 2B
- Argo CD Application CRD — the core GitOps object
- Multi-source Application manifest — separate chart and values repos
- Server-side apply for large CRDs exceeding annotation size limits
- selfHeal and prune sync policies
- Drift detection and automatic cluster reconciliation
- Migrating from manual Helm release to Argo CD management
- ApplicationSet controller CRD installation ordering issue

---

## Next Steps

- NVIDIA GPU Operator simulation with fake-gpu-operator (Phase 2C)
- Multi-tenant GPU scheduling with priority classes
- Model serving with Triton Inference Server (Phase 3)
- Cloud GPU validation on Lambda Labs or vast.ai
- Full cluster teardown and rebuild for practice
