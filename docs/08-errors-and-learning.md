# Errors and Learning Guide

This document contains every error encountered across all phases
of the gpu-kubernetes-lab build. It is preserved deliberately so
that when rebuilding the lab, errors can be reproduced, diagnosed,
and fixed independently — building real debugging muscle memory.

Mac-specific errors are included for completeness but will not
reproduce on rebuild since the Mac environment (socket_vmnet,
sudoers, Local Network permission) persists across VM rebuilds.

---

# PHASE 1 ERRORS

## Error 1.1 - YAML validation - single quotes in sed command

### When it happens
When creating the Lima VM provision script containing a sed command
with single quotes inside a YAML block scalar.

### Error
    FATA[0000] failed to unmarshal YAML: value is not allowed
    in this context
    > 74 | sed -i 's/SystemdCgroup = false/SystemdCgroup = true/'

### Root cause
Single quotes inside a YAML block scalar confuse the YAML parser.
The parser treats the single quote as a YAML string delimiter.

### Fix
Use double quotes in sed commands inside YAML files:

    # Wrong
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' file

    # Correct
    sed -i "s/SystemdCgroup = false/SystemdCgroup = true/" file

### How to reproduce deliberately
Use single quotes in the sed command inside the provision script.
Run limactl validate and see the exact error.

---

## Error 1.2 - YAML validation - heredoc syntax inside provision script

### When it happens
When using heredoc markers inside a Lima YAML provision script.

### Error
    FATA[0000] failed to unmarshal YAML: non-map value is specified
    > 40 | overlay

### Root cause
Heredoc markers inside YAML block scalars are interpreted as YAML
syntax not bash syntax. The YAML parser sees content between
heredoc markers as YAML key-value pairs.

### Fix
Replace heredocs with printf statements:

    # Wrong - breaks inside YAML
    cat > /etc/modules-load.d/k8s.conf << MODULES
    overlay
    br_netfilter
    MODULES

    # Correct - works inside YAML
    printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/k8s.conf

### How to reproduce deliberately
Use heredoc syntax in the provision script. Run limactl validate.

---

## Error 1.3 - Worker nodes cannot reach control-plane

### When it happens
When running kubeadm join on worker nodes after bootstrapping
the control-plane with vzNAT networking.

### Error
    error execution phase preflight: couldn't validate the identity
    of the API Server: dial tcp <CONTROL-PLANE-IP>:6443:
    connect: no route to host

### Root cause
Lima vzNAT networking gives each VM its own isolated NAT network.
VMs cannot communicate directly with each other.

### Fix
Switch from vzNAT to shared networking in all Lima YAML files:

    # Wrong
    networks:
      - vzNAT: true

    # Correct
    networks:
      - lima: shared

Requires socket_vmnet installed from source at /opt/socket_vmnet.

### How to reproduce deliberately
Use vzNAT in the Lima configs. Start VMs. Try kubeadm join.
See the no route to host error. Then switch to shared networking.

---

## Error 1.4 - socket_vmnet Homebrew installation rejected

### When it happens
After switching to shared networking but installing socket_vmnet
via Homebrew instead of from source.

### Error
    FATA[0002] networks.yaml:
    "/opt/socket_vmnet/bin/socket_vmnet" has to be installed

### Root cause
Lima rejects socket_vmnet installed via Homebrew because Homebrew
installs to /opt/homebrew which is user-writable. Lima requires
socket_vmnet in a root-only writable location for security.

### Fix
Install from source to /opt/socket_vmnet:

    git clone https://github.com/lima-vm/socket_vmnet.git
    cd socket_vmnet && git checkout v1.2.2
    make && sudo make PREFIX=/opt/socket_vmnet install.bin
    limactl sudoers > /tmp/lima-sudoers
    sudo install -o root /tmp/lima-sudoers /etc/sudoers.d/lima

### How to reproduce deliberately
Install socket_vmnet via brew install socket_vmnet only.
Try to start a VM with shared networking. See the error.

### Mac specific
This error will NOT reproduce on rebuild since socket_vmnet
is already installed at /opt/socket_vmnet and the sudoers file
persists at /etc/sudoers.d/lima.

---

## Error 1.5 - kubeadm init used wrong network interface

### When it happens
When running kubeadm init without specifying
--apiserver-advertise-address on a VM with multiple interfaces.

### Error
Worker nodes fail to join. The kubeadm join command generated
uses an IP that workers cannot reach (192.168.5.15 instead of
the shared network IP 192.168.105.x).

### Root cause
Without --apiserver-advertise-address, kubeadm auto-detects the
IP from the first available interface which is eth0 (192.168.5.15)
not lima0 (192.168.105.x). Workers cannot reach eth0.

### Fix
Always specify the correct IP explicitly:

    sudo kubeadm init \
      --pod-network-cidr=10.244.0.0/16 \
      --kubernetes-version=v1.29.15 \
      --apiserver-advertise-address=<LIMA0-IP>

Find the correct IP first:
    limactl shell control-plane -- ip addr show dev lima0 | grep inet

### How to reproduce deliberately
Run kubeadm init without --apiserver-advertise-address.
Check the generated join command IP. Try to join a worker.
See it fail. Then redo with the correct flag.

---

## Error 1.6 - macOS Local Network permission blocking connectivity

### When it happens
After restarting VMs, kubectl fails with no route to host despite
the cluster being completely healthy inside the VMs.

### Error
    dial tcp 192.168.105.2:6443: connect: no route to host

### Root cause
macOS Sequoia Local Network privacy permission for Terminal was
OFF. macOS silently fails local network calls when this permission
is disabled, producing errors that look like Lima or Kubernetes
networking failures.

### Fix
System Settings -> Privacy and Security -> Local Network
Find Terminal (or iTerm2) and toggle ON.

### How to reproduce deliberately
Toggle the Local Network permission OFF for Terminal in System
Settings. Try kubectl get nodes. See the error. Toggle back ON.

### Mac specific
This error will NOT reproduce on rebuild if the permission stays
ON. Check this setting first whenever kubectl fails unexpectedly.
Make it the first debugging step before any Lima or K8s diagnosis.

---

# PHASE 2A ERRORS — HELM AND MONITORING

## Error 2.1 - Helm values file corrupted by copy-paste

### When it happens
When pasting a Helm values file from a markdown source into vim,
the code fence marker gets included as literal text.

### Error
    Error: failed to parse monitoring-values.yaml:
    cannot unmarshal yaml document: json: cannot unmarshal
    string into Go value of type map[string]interface {}

### Root cause
The markdown code fence marker (yaml) was included as literal
text on the first line of the file:

    yaml# Trimmed values for kube-prometheus-stack

### Fix
Open file in vim and delete the stray yaml text from line 1.
Then verify with:

    head -3 gitops-values/monitoring-values.yaml

Always validate before installing:

    helm template my-monitoring chart/ -f values.yaml > rendered.yaml

### How to reproduce deliberately
Paste values file content including the yaml code fence marker.
Run helm template. See the parse error.

---

## Error 2.2 - Worker node port-forward failing

### When it happens
When running kubectl port-forward to pods running on worker nodes.
Works fine for pods on control-plane but fails for worker pods.

### Error
    error: error upgrading connection: unable to upgrade
    connection: pod does not exist

### Root cause
Worker nodes registered the wrong InternalIP (eth0/192.168.5.15)
instead of the shared network IP (lima0/192.168.105.x). The API
server uses InternalIP to open streaming connections to kubelets
for port-forward, exec, and log streaming.

### Fix
Add --node-ip to each worker kubelet flags:

    limactl shell worker-1 -- sudo sed -i \
      's/KUBELET_KUBEADM_ARGS="/KUBELET_KUBEADM_ARGS="--node-ip=192.168.105.3 /' \
      /var/lib/kubelet/kubeadm-flags.env
    limactl shell worker-1 -- sudo systemctl restart kubelet

Repeat for worker-2 (192.168.105.4) and worker-3 (192.168.105.5).

Verify:
    kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[0].address}{"\n"}{end}'

### How to reproduce deliberately
Skip the --node-ip fix. Try kubectl port-forward to a pod on
a worker node. See the error. Then apply the fix.

---

## Error 2.3 - Prometheus scraping DOWN for etcd and controller-manager

### When it happens
After installing the monitoring stack, Prometheus targets page
shows etcd and kube-controller-manager as DOWN.

### Error
    Error scraping target: Get "https://192.168.5.15:10257/metrics":
    dial tcp 192.168.5.15:10257: connect: connection refused

### Root cause
Two combined problems:
1. Wrong IP - Prometheus tries 192.168.5.15 (wrong interface)
2. Localhost binding - etcd and controller-manager only bind
   metrics endpoints to 127.0.0.1 by default in kubeadm clusters

### Fix (not applied in this lab)
Patch static pod manifests on control-plane:

    # For etcd - add to /etc/kubernetes/manifests/etcd.yaml
    --listen-metrics-urls=http://0.0.0.0:2381

    # For kube-controller-manager
    --bind-address=0.0.0.0

### How to reproduce deliberately
This happens automatically with a default kubeadm cluster and
kube-prometheus-stack. No deliberate action needed.

### Impact
Grafana etcd dashboard shows No data. All other dashboards
work correctly since they use kube-state-metrics and
node-exporter data which are functioning correctly.

---

# PHASE 2B ERRORS — ARGO CD

## Error 3.1 - unknown field spec.source.helm.chart

### When it happens
When creating an Argo CD Application manifest combining path
and chart in the same source block.

### Error
    strict decoding error: unknown field "spec.source.helm.chart"

### Fix
Use multiple sources (sources plural not source singular).
See docs/07-argocd-troubleshooting.md Issue 3 for full details.

### How to reproduce deliberately
Use single source with both path and helm.chart fields.
Run kubectl apply. See the error.

---

## Error 3.2 - CRD annotation size limit

### When it happens
When Argo CD tries to sync kube-prometheus-stack without
ServerSideApply enabled.

### Error
    metadata.annotations: Too long: must have at most 262144 bytes

### Fix
Add ServerSideApply=true to syncOptions.
See docs/07-argocd-troubleshooting.md Issue 1 for full details.

### How to reproduce deliberately
Create Application manifest without ServerSideApply=true.
Apply it. Watch the sync fail with the annotation error.

---

## Error 3.3 - ApplicationSet controller CrashLoopBackOff

### When it happens
After installing Argo CD without server-side apply, the
ApplicationSet controller crashes repeatedly.

### Error
    failed to get restmapping: no matches for kind "ApplicationSet"
    in version "argoproj.io/v1alpha1"

### Fix
Reapply install manifest with --server-side --force-conflicts.
See docs/07-argocd-troubleshooting.md Issue 2 for full details.

### How to reproduce deliberately
Install Argo CD with standard kubectl apply (without --server-side).
Check pods. See ApplicationSet controller in CrashLoopBackOff.

---

## Error 3.4 - Pods disappeared after helm uninstall

### When it happens
When running helm uninstall before Argo CD has fully taken
ownership of the resources.

### Symptom
    kubectl get pods -n monitoring
    No resources found in monitoring namespace.

### Fix
Click SYNC in Argo CD UI or wait for automated sync cycle.
Argo CD recreates everything from Git automatically.
See docs/07-argocd-troubleshooting.md Issue 5 for full details.

### How to reproduce deliberately
Run helm uninstall immediately after applying the Application
manifest without waiting for Argo CD to fully sync first.

---

# REBUILD CHECKLIST

Use this checklist when rebuilding the lab from scratch:

## Before starting
    - socket_vmnet installed at /opt/socket_vmnet  (persists)
    - /etc/sudoers.d/lima exists                   (persists)
    - Local Network permission ON for Terminal      (check first)
    - Homebrew tools installed                      (persists)
    - GitHub repo cloned fresh

## Phase 1 deliberate errors to reproduce
    1. Use vzNAT first -> hit no route to host -> switch to shared
    2. Skip --apiserver-advertise-address -> hit wrong IP -> add flag
    3. Skip --node-ip on workers -> hit port-forward failure -> add flag

## Phase 2A deliberate errors to reproduce
    1. Paste values file with code fence -> hit parse error -> fix file
    2. Try port-forward to worker pod before --node-ip fix -> fail

## Phase 2B deliberate errors to reproduce
    1. Use single source with chart field -> hit unknown field error
    2. Skip ServerSideApply -> hit annotation size error
    3. Install Argo CD without --server-side -> hit CrashLoopBackOff
    4. Run helm uninstall before Argo CD syncs -> pods disappear
