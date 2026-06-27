# Design Decisions

This document explains why specific tools and approaches were chosen
over alternatives. Understanding these trade-offs is as important as
knowing how to use the tools themselves.

---

## Why Lima over alternatives

### Options considered

| Tool            | Type                    | Rejected reason                          |
|-----------------|-------------------------|------------------------------------------|
| Lima            | Linux VM manager        | CHOSEN                                   |
| k3s             | Lightweight Kubernetes  | Hides too much internals                 |
| kind            | Kubernetes in Docker    | Nodes are containers not real VMs        |
| minikube        | Single node Kubernetes  | Single node, not multi-node              |
| Docker Desktop  | Container platform      | Kubernetes hidden behind UI abstraction  |
| Proxmox         | VM hypervisor           | Requires separate machine or bare metal  |
| Multipass       | Ubuntu VM manager       | Less control over networking             |

### Why Lima was chosen

Lima creates real Linux VMs using Apple's native Virtualization framework
on Apple Silicon. This means:

- VMs run natively on ARM64 - no emulation, full performance
- Each VM is a real Linux machine with its own network interface
- kubeadm behaves exactly as it would on real Linux servers
- Networking, kernel modules, systemd all work as in production
- You learn the real thing, not an abstraction

Lima is what a real infrastructure engineer would use when they need
genuine Linux VMs on a Mac for testing production-like behaviour.

---

## Why kubeadm over k3s

### What is k3s

k3s is a lightweight Kubernetes distribution made by Rancher. It packages
everything into a single binary and makes cluster setup extremely simple.
A cluster can be running in under 5 minutes.

### Why I did not use k3s

| Aspect          | k3s                        | kubeadm                          |
|-----------------|----------------------------|----------------------------------|
| Setup time      | 5 minutes                  | 30-60 minutes                    |
| Complexity      | Very simple                | More involved                    |
| What it hides   | etcd, certificates, components | Nothing - you see everything |
| Production use  | Edge, IoT, small setups    | Enterprise, cloud providers      |
| GPU cloud use   | Rarely                     | Yes - standard choice            |
| Recruiter signal| Used a shortcut            | Knows the real thing             |

kubeadm installs full Kubernetes and makes you understand every component:
- How certificates are generated and why each one exists
- How etcd is bootstrapped before anything else can start
- How nodes join securely using tokens and certificate hashes
- How control plane components start as static pods
- How kubelet communicates with the API server

k3s hides all of this. For a GPU cloud infrastructure role where you are
expected to operate close to the hardware and understand the full stack,
kubeadm knowledge is essential.

### When k3s IS the right choice
- Edge computing deployments with limited resources
- IoT devices running Kubernetes
- Quick proof of concept that does not need production fidelity
- Raspberry Pi clusters

---

## Why Flannel over other CNI plugins

### What is a CNI plugin

CNI stands for Container Network Interface. Kubernetes does not handle
pod-to-pod networking itself. It delegates that to a CNI plugin.
Every pod gets a unique IP address and the CNI plugin is responsible
for making sure pods on different nodes can reach each other.

### Options considered

| CNI Plugin | How it works           | Production use        | Complexity |
|------------|------------------------|-----------------------|------------|
| Flannel    | VXLAN overlay          | Small clusters, labs  | Very low   |
| Calico     | BGP routing or VXLAN   | Enterprise standard   | Medium     |
| Cilium     | eBPF kernel bypass     | AI/GPU workloads      | High       |
| Weave      | Mesh network           | Declining             | Medium     |
| Canal      | Flannel + Calico       | Moderate              | Medium     |

### Why Flannel was chosen for this lab

- Simplest to install - one kubectl apply command
- Works perfectly on Lima shared networking
- Default pod CIDR 10.244.0.0/16 requires zero extra configuration
- Lets me focus on learning Kubernetes, not debugging networking
- Most tutorials use it so easier to find help

### What I would use in production GPU cloud

For a real GPU cloud marketplace the CNI choice depends on requirements:

Calico - if multi-tenant network isolation is the priority
- Network policies to isolate tenant workloads
- Prevent tenant A from accessing tenant B pods
- Most common enterprise choice

Cilium - if performance is the priority
- Uses eBPF to process packets in the kernel directly
- Bypasses iptables entirely - much faster at scale
- Built-in observability - see exactly what traffic flows where
- Growing adoption at major GPU cloud providers
- Best choice for AI training workloads moving large tensors

SR-IOV with RDMA - for GPU-to-GPU communication on real hardware
- Bypasses the kernel entirely
- Near wire-speed between GPUs on different nodes
- Used by CoreWeave and Lambda Labs for distributed training

---

## Why Ubuntu 22.04 over other Linux distributions

| Distribution    | Notes                                              |
|-----------------|----------------------------------------------------|
| Ubuntu 22.04    | CHOSEN                                             |
| Ubuntu 24.04    | Too new - some Kubernetes packages lag behind      |
| Debian          | Fewer cloud-init examples available                |
| CentOS/RHEL     | Different package manager - apt vs yum             |
| Alpine          | Too minimal - missing many tools by default        |

Ubuntu 22.04 LTS is the most widely used Linux distribution for
Kubernetes in production. LTS means Long Term Support - security
updates guaranteed until 2027. Most Kubernetes documentation assumes
Ubuntu which makes troubleshooting much easier.

---

## Why Kubernetes v1.29 over latest version

| Version    | Status              | Notes                                    |
|------------|---------------------|------------------------------------------|
| v1.29.15   | CHOSEN              | Stable, well documented, wide support    |
| v1.30.x    | Stable              | Newer but fewer community examples       |
| v1.31.x    | Stable              | Too new, some GPU operators lag behind   |
| v1.32.x    | Latest              | Cutting edge, avoid for learning labs    |

### Why v1.29 was chosen

Kubernetes releases a new minor version every 4 months. Each version
is supported for about 14 months. v1.29 was chosen because:

- Mature and stable with all known bugs patched
- NVIDIA GPU operator fully supports it
- Extensive documentation and community examples available
- Most enterprise production clusters run 1-2 versions behind latest
- Matches what you would find in real GPU cloud environments today

Always pin a specific Kubernetes version using --kubernetes-version
flag in kubeadm init. Never let kubeadm pick the latest automatically
as it may not match the kubelet version already installed on nodes
causing version mismatch errors.

    sudo kubeadm init \
      --kubernetes-version=v1.29.15 \
      --pod-network-cidr=10.244.0.0/16 \
      --apiserver-advertise-address=<CONTROL-PLANE-IP>

---

## Why shared networking over vzNAT

### What I tried first

Initially configured vzNAT networking in Lima YAML files:

    networks:
      - vzNAT: true

### Why it failed

vzNAT gives each VM its own isolated NAT network. VMs cannot
communicate directly with each other. When worker nodes tried to
join the cluster:

    dial tcp <CONTROL-PLANE-IP>:6443: connect: no route to host

### Why shared networking works

Shared networking puts all VMs on the same bridge network.
Every VM gets a different IP in that range and can reach every
other VM directly. This is required for:

- kubeadm join - workers must reach control-plane API server
- Pod networking - Flannel must route between nodes
- kubectl - commands must reach the API server

### Why socket_vmnet must be installed from source

Lima requires socket_vmnet in a root-only writable location
for security. socket_vmnet runs as root and creates network
interfaces. If installed in a user-writable location a malicious
program could replace it.

Homebrew installs to /opt/homebrew which is user-writable.
Lima rejects this. Must install from source to /opt/socket_vmnet
which is only writable by root.

---

## Why containerd over Docker

| Runtime     | Notes                                           |
|-------------|-------------------------------------------------|
| containerd  | CHOSEN - industry standard, direct CRI support  |
| Docker      | Deprecated in Kubernetes 1.24+                  |
| CRI-O       | Good alternative, less documentation            |

Docker was removed as a supported container runtime in Kubernetes
1.24. containerd is what Docker itself uses internally and is now
the direct standard. Using containerd means one less abstraction
layer and better performance.
