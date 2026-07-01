# Troubleshooting — Phase 2 (Helm and Monitoring)

Real issues encountered during Phase 2 and how I resolved them.
Every issue below actually happened during the build.

---

## Issue 1 - limactl snapshot unimplemented on macOS vz backend

### Symptom
Attempting to snapshot VMs before risky Phase 2 work failed:

    limactl snapshot create control-plane --tag pre-phase2
    WARN[0000] `limactl snapshot` is experimental
    FATA[0000] unimplemented

### Root cause
limactl snapshot is only implemented for the QEMU VM backend.
My setup uses vmType: vz (Apple Virtualization framework) for
native ARM64 performance on the M4 chip. The vz backend does
not support snapshots at all in Lima 2.1.3.

### Fix
Used limactl clone instead — creates a full disk copy of each VM
that can be used as a rollback point. Requires the VM to be stopped
first.

    ~/gpu-kubernetes-lab/scripts/shutdown-cluster.sh
    limactl clone control-plane control-plane-backup
    limactl clone worker-1 worker-1-backup
    limactl clone worker-2 worker-2-backup
    limactl clone worker-3 worker-3-backup

Verify clones created:

    limactl list

To roll back a specific VM if something breaks:

    limactl delete worker-1
    limactl clone worker-1-backup worker-1

### Trade-off
Each clone is a full sparse disk copy, not a lightweight delta.
Disk usage is manageable since Lima uses sparse allocation, but
old clones should be deleted once a phase is confirmed stable:

    limactl delete worker-1-backup

### Lesson learned
Check limactl snapshot support for your vmType before relying on
it as a safety mechanism. For vz backend on Apple Silicon, use
limactl clone as the alternative. Always verify the backup
mechanism actually works before starting risky work.

---

## Issue 2 - Helm values file corrupted by copy-paste

### Symptom
helm template failed with a confusing parse error:

    Error: failed to parse gitops-values/monitoring-values.yaml:
    cannot unmarshal yaml document: error unmarshaling JSON:
    while decoding JSON: json: cannot unmarshal string into
    Go value of type map[string]interface {}

### Root cause
When pasting the values file content into vim, the markdown code
fence marker (yaml) from the source got included as literal text
on the first line of the file:

    yaml# Trimmed values for kube-prometheus-stack

The YAML parser saw "yaml" as a key-value string rather than a
comment, which broke the entire document structure.

Discovered by inspecting the file directly:

    cat -v gitops-values/monitoring-values.yaml | head -5

Output showed:
    yaml# Trimmed values for kube-prometheus-stack

### Fix
Opened the file in vim and deleted the stray "yaml" text from the
first line:

    vim gitops-values/monitoring-values.yaml
    # In vim: go to first line, press 0, type 4x to delete 4 chars

Verified fix:

    head -3 gitops-values/monitoring-values.yaml

Re-ran the dry-run render — succeeded with no errors.

### Lesson learned
Always validate values files before running helm install.
Use helm template as a dry-run to catch parse errors locally
before they fail against the live cluster. When pasting content
from a markdown source into vim, watch for code fence markers
(yaml, bash, etc) appearing as literal text in the file.

---

## Issue 3 - macOS Local Network permission blocking VM connectivity

### Symptom
kubectl get nodes failed with no route to host error after a
cluster restart, even though the cluster itself was completely
healthy:

    dial tcp 192.168.105.2:6443: connect: no route to host

Extensive debugging showed:
- kube-apiserver was running and listening on port 6443 inside VM
- kubelet was active and healthy
- bridge100 interface was UP with correct MAC addresses cached
- Mac could ping bridge gateway (192.168.105.1) successfully
- Mac could NOT ping the VM (192.168.105.2) — no route to host

### Things tried that did NOT fix it
- Restarting the control-plane VM alone
- Flushing and re-adding the bridge interface (ifconfig down/up)
- Removing and re-adding vmenet0 from bridge100
- Fully killing socket_vmnet and letting Lima recreate from scratch
- A full macOS restart appeared to fix it temporarily but the
  issue returned on the next VM restart cycle

### Root cause
macOS Sequoia introduced a Local Network privacy permission under:
System Settings → Privacy and Security → Local Network

The Terminal app toggle was OFF. When this permission is off, macOS
silently fails local network calls including ping and kubectl
connections, producing "no route to host" errors that look exactly
like a networking or bridge problem. The silence makes this
extremely difficult to diagnose since no clear error message points
to the permission system.

A full Mac restart appeared to fix it once because it happened to
reset something related to the permission state, but it was not a
reliable fix since the underlying toggle was never corrected.

### Fix
1. Open System Settings
2. Go to Privacy and Security
3. Click Local Network
4. Find Terminal (or iTerm2)
5. Toggle ON
6. If already showing ON, toggle OFF then back ON to force
   macOS to re-grant the permission cleanly

Verify immediately:

    ping 192.168.105.2 -c 3
    kubectl get nodes

### Lesson learned
On macOS Sequoia and later, always check System Settings →
Privacy and Security → Local Network BEFORE doing any Lima or
Kubernetes network debugging. This single toggle produces symptoms
identical to a broken bridge, stale socket_vmnet, or cluster-level
networking failure. Check it first — it takes 5 seconds and saves
hours of debugging.

Make this a standard first step in any session where kubectl
fails unexpectedly.

---

## Issue 4 - Worker nodes registered wrong InternalIP causing port-forward failures

### Symptom
kubectl port-forward to pods running on worker nodes failed:

    error: error upgrading connection: unable to upgrade connection:
    pod does not exist

Regular kubectl commands (get, describe, logs) worked fine.
Port-forward to pods on the control-plane worked fine.
Port-forward to pods on worker nodes always failed.

### Diagnosis
Checked what IP each node registered as its InternalIP:

    kubectl get node lima-worker-3 -o jsonpath='{.status.addresses}'

Result:
    [{"address":"192.168.5.15","type":"InternalIP"},
     {"address":"lima-worker-3","type":"Hostname"}]

192.168.5.15 is the eth0 NAT interface — the same IP on every
node, not actually routable between nodes. The correct reachable
IP is the lima0 shared network interface (192.168.105.x).

### Root cause
kubelet auto-detects its node IP from the first available network
interface, which was eth0 (192.168.5.15) rather than lima0
(192.168.105.x). Port-forward requires the API server to open a
direct streaming connection to the kubelet on the specific node
using its registered InternalIP. Since 192.168.5.15 is a NAT
interface unreachable from the API server's perspective, the
streaming connection failed even though the pod existed and was
running perfectly.

Regular kubectl commands work because they go through the API
server's standard proxy mechanism, which does not require a direct
connection to the node's IP.

### Fix
Explicitly set --node-ip on each worker's kubelet to force it to
register the correct shared network IP:

    limactl shell worker-1 -- sudo sed -i \
      's/KUBELET_KUBEADM_ARGS="/KUBELET_KUBEADM_ARGS="--node-ip=192.168.105.3 /' \
      /var/lib/kubelet/kubeadm-flags.env
    limactl shell worker-1 -- sudo systemctl restart kubelet

    limactl shell worker-2 -- sudo sed -i \
      's/KUBELET_KUBEADM_ARGS="/KUBELET_KUBEADM_ARGS="--node-ip=192.168.105.4 /' \
      /var/lib/kubelet/kubeadm-flags.env
    limactl shell worker-2 -- sudo systemctl restart kubelet

    limactl shell worker-3 -- sudo sed -i \
      's/KUBELET_KUBEADM_ARGS="/KUBELET_KUBEADM_ARGS="--node-ip=192.168.105.5 /' \
      /var/lib/kubelet/kubeadm-flags.env
    limactl shell worker-3 -- sudo systemctl restart kubelet

Verified fix:

    kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[0].address}{"\n"}{end}'

Result:
    lima-control-plane    192.168.5.15     (unchanged, not needed)
    lima-worker-1         192.168.105.3    fixed
    lima-worker-2         192.168.105.4    fixed
    lima-worker-3         192.168.105.5    fixed

Port-forward worked immediately after the fix.

### Lesson learned
In multi-network-interface environments (common with Lima VMs which
have both eth0 NAT and lima0 shared interfaces), always explicitly
set --node-ip on each kubelet to the correct reachable interface.
Do not rely on kubelet's auto-detection. This is especially important
in any lab environment where nodes have multiple network interfaces
with different reachability characteristics.

Set --node-ip in /var/lib/kubelet/kubeadm-flags.env during initial
cluster setup to avoid this issue entirely in future rebuilds.

---

## Issue 5 - Prometheus scraping errors for etcd and kube-controller-manager

### Symptom
In Prometheus targets page (localhost:9090/targets), two targets
showed DOWN with connection refused errors:

    kube-controller-manager: dial tcp 192.168.5.15:10257:
      connect: connection refused

    kube-etcd: dial tcp 192.168.5.15:2381:
      connect: connection refused

Screenshot of this state is in docs/screenshots/prometheus-targets.png
which shows both the working UP targets and the DOWN targets for
reference.

### Root cause
Two separate problems combined:

Problem 1 - Wrong IP: Prometheus was trying to reach these
components via 192.168.5.15 (the eth0 NAT IP registered as
InternalIP) rather than 192.168.105.2 (the actual reachable IP).
This is the same InternalIP registration issue as Issue 4 above,
but affecting the control-plane components rather than worker nodes.

Problem 2 - Localhost binding: etcd and kube-controller-manager
by default only bind their metrics endpoints to 127.0.0.1 (localhost)
inside the control-plane VM, not to any external interface. Even
with the correct IP, Prometheus running in a different pod cannot
reach metrics endpoints that only listen on localhost.

### Fix (not yet applied)
Requires patching the static pod manifests on the control-plane
to bind metrics endpoints to 0.0.0.0 instead of 127.0.0.1:

For etcd, edit /etc/kubernetes/manifests/etcd.yaml and add:
    --listen-metrics-urls=http://0.0.0.0:2381

For kube-controller-manager, edit
/etc/kubernetes/manifests/kube-controller-manager.yaml and change:
    --bind-address=127.0.0.1
to:
    --bind-address=0.0.0.0

This is a known limitation with kubeadm clusters and
kube-prometheus-stack. It does not affect the main monitoring
dashboards since those use kube-state-metrics and node-exporter
data, not controller-manager or etcd metrics directly.

### Impact
The Grafana etcd dashboard shows No data as a result. All other
dashboards (Compute Resources, Node Exporter, Networking) work
correctly since they rely on targets that are UP.

### Lesson learned
kubeadm clusters require additional configuration to expose etcd
and controller-manager metrics externally. The kube-prometheus-stack
chart assumes these endpoints are accessible, which they are on
managed Kubernetes clusters (EKS, GKE, AKS) but not on self-hosted
kubeadm clusters without manual patching of the static pod manifests.
