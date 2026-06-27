# GPU Kubernetes Lab

A 4-node Kubernetes cluster built from scratch on Apple M4 (16GB RAM) using Lima VMs and kubeadm. This lab simulates a production-grade GPU cloud infrastructure environment for learning multi-tenant workload orchestration, GPU scheduling, and AI infrastructure operations.

## Architecture

    Mac Host (Apple M4, 16GB RAM)
    |
    |-- control-plane  (2 CPU, 3.5GB RAM, 20GB disk)
    |   |-- etcd
    |   |-- kube-apiserver
    |   |-- kube-scheduler
    |   |-- kube-controller-manager
    |
    |-- worker-1  (2 CPU, 2GB RAM, 10GB disk)
    |-- worker-2  (2 CPU, 2GB RAM, 10GB disk)
    |-- worker-3  (2 CPU, 3GB RAM, 10GB disk)
        |-- kubelet, kube-proxy, flannel, workloads

## Stack

| Component  | Version   | Purpose                    |
|------------|-----------|----------------------------|
| Kubernetes | v1.29.15  | Container orchestration    |
| kubeadm    | v1.29.15  | Cluster bootstrapping      |
| containerd | v2.2.1    | Container runtime          |
| Flannel    | latest    | Pod networking CNI         |
| Lima       | v2.1.3    | Linux VMs on Apple Silicon |
| Ubuntu     | 22.04 LTS | Node operating system      |

## Cluster Status

    NAME                 STATUS   ROLES           VERSION
    lima-control-plane   Ready    control-plane   v1.29.15
    lima-worker-1        Ready    worker          v1.29.15
    lima-worker-2        Ready    worker          v1.29.15
    lima-worker-3        Ready    worker          v1.29.15

## Repository Structure

    gpu-kubernetes-lab/
    |-- lima-configs/
    |   |-- control-plane.yaml
    |   |-- worker-1.yaml
    |   |-- worker-2.yaml
    |   |-- worker-3.yaml
    |-- scripts/
    |-- docs/
    |   |-- 01-prerequisites.md
    |   |-- troubleshooting.md
    |-- README.md

## Quick Start

1. Install tools

    brew install lima kubectl helm k9s

2. Install socket_vmnet for VM networking

    git clone https://github.com/lima-vm/socket_vmnet.git
    cd socket_vmnet && git checkout v1.2.2
    make && sudo make PREFIX=/opt/socket_vmnet install.bin
    limactl sudoers > /tmp/lima-sudoers
    sudo install -o root /tmp/lima-sudoers /etc/sudoers.d/lima

3. Start all VMs

    cd lima-configs
    limactl start control-plane.yaml
    limactl start worker-1.yaml &
    limactl start worker-2.yaml &
    limactl start worker-3.yaml &

4. Bootstrap cluster

    limactl shell control-plane
    sudo kubeadm init \
      --pod-network-cidr=10.244.0.0/16 \
      --kubernetes-version=v1.29.15 \
      --apiserver-advertise-address=192.168.105.2

5. Set up kubectl

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

6. Install Flannel CNI

    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

7. Join workers - run on each worker node

    sudo kubeadm join 192.168.105.2:6443 --token <token> \
      --discovery-token-ca-cert-hash sha256:<hash>

## What I Learned

- Kubernetes cluster architecture and component roles
- kubeadm bootstrap sequence and certificate generation
- CNI networking concepts and Flannel overlay networking
- Lima VM management on Apple Silicon
- Infrastructure as code with declarative YAML configs
- Debugging VM networking issues (vzNAT vs shared networking)
- socket_vmnet installation and Lima network modes

## Issues Encountered and Fixed

### vzNAT networking - worker nodes could not reach control-plane
- Reason: vzNAT gives each VM an isolated network
- Fix: Switched to shared networking mode using socket_vmnet
- socket_vmnet must be installed from source to /opt/socket_vmnet not via Homebrew

### YAML validation errors in provision scripts
- Reason: Single quotes and heredocs inside YAML confused the parser
- Fix: Used double quotes in sed commands and printf instead of heredocs

## Next Steps

- Install NVIDIA GPU operator with simulated GPU resources
- Deploy Prometheus and Grafana monitoring stack
- Set up DCGM exporter for GPU metrics
- Deploy model serving with Triton Inference Server
- Implement multi-tenant GPU scheduling with priority classes
