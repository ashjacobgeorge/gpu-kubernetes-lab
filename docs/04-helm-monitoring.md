# Helm and Kubernetes Monitoring Setup

## What is Helm

Helm is a package manager for Kubernetes — the same role apt plays
for Ubuntu packages or pip for Python. Instead of hand-writing every
Deployment, Service, ConfigMap, and RBAC rule needed to run something
like Prometheus (which can be 50+ separate YAML files), someone
packages all of that into a reusable bundle called a chart, and I can
install the whole thing with one command, overriding only the values
I care about.

## Three core Helm concepts

### Chart
A chart is a directory containing templated Kubernetes YAML files plus
metadata and default values. The files inside use Go templating syntax
with placeholders like {{ .Values.replicaCount }} that get filled in
at install time. I do not edit chart internals directly.

### Values
Instead of editing the chart's internal templates, I supply my own
values.yaml that overrides only what I need. Helm merges my overrides
on top of the chart's defaults. Whatever I do not specify uses the
chart's original default unchanged.

### Release
When I run helm install, Helm creates a named release and tracks every
change to it as a numbered revision. This is what makes helm rollback
possible — Helm remembers the exact rendered manifests at every revision.

## Why kube-prometheus-stack

kube-prometheus-stack is an umbrella chart from the Prometheus community
that bundles together everything needed for Kubernetes monitoring:

    Component                  Purpose
    ─────────────────────────────────────────────────────────────
    Prometheus                 Metrics collection and storage database
    Prometheus Operator        Manages Prometheus/Alertmanager via CRDs
    Alertmanager               Alert routing (disabled - not needed for lab)
    Grafana                    Dashboard and visualization layer
    kube-state-metrics         Translates K8s object state into metrics
    prometheus-node-exporter   Host-level metrics, runs on every node

This is the real industry-standard approach for Kubernetes monitoring —
not a simplified lab version. The same chart, same mechanism, runs in
production at companies using Kubernetes. Outside Kubernetes (bare metal
or VMs without K8s), Prometheus is installed differently — as a binary
or Docker container with hand-written prometheus.yml scrape configs.
None of the Operator/CRD/ServiceMonitor patterns exist outside Kubernetes.

## Key concepts introduced by this chart

### Operator
A pod that actively manages other Kubernetes resources on your behalf.
The Prometheus Operator watches for CRD objects and automatically creates
the actual Prometheus StatefulSet, configures scraping targets, and keeps
everything in sync. I never manually edit Prometheus's raw config —
I create a simple declarative object and the Operator translates it.

### CRD (Custom Resource Definition)
CRDs teach Kubernetes about new object types that do not exist by default.
Once installed, I can kubectl get prometheus or kubectl apply a manifest
with kind: Prometheus exactly like a built-in object. CRDs are schema
definitions only — they cost nothing in CPU or memory since they are not
running pods. This is why Alertmanager CRDs were still installed even
though I disabled Alertmanager itself.

### ServiceMonitor
A CRD type that tells Prometheus what to scrape. Instead of manually
editing prometheus.yml every time a new app needs monitoring, each app
gets a ServiceMonitor object saying "scrape metrics from me on this port
every 30 seconds." The Operator sees these and automatically updates
Prometheus's actual config.

### DaemonSet
A controller type that runs exactly one pod copy on every node that
matches its criteria, automatically. When node-exporter is deployed as
a DaemonSet, I never specify "4 copies" — it dynamically tracks whatever
nodes exist. When I add a node, a new pod appears automatically.
node-exporter pods include a toleration for the control-plane NoSchedule
taint specifically, because monitoring needs host metrics from every node
including the control-plane.

## Installation steps

### Step 1 — Verify Helm was already installed
Helm was installed back in Phase 1 alongside lima, kubectl, and k9s.

    helm version

### Step 2 — Add the Prometheus community chart repository
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

This registers the remote chart repository and pulls its index so Helm
knows what charts and versions are available. Like adding an apt source.

### Step 3 — Inspect the chart's full default values
    cd ~/gpu-kubernetes-lab
    helm show values prometheus-community/kube-prometheus-stack > default-values.yaml
    wc -l default-values.yaml

The chart has 5,659 lines of configurable options. I used grep and sed
to jump to specific sections rather than reading the entire file:

    grep -n "^alertmanager:" default-values.yaml
    grep -n "^prometheus:" default-values.yaml
    grep -n "^grafana:" default-values.yaml
    sed -n '396,420p' default-values.yaml
    sed -n '4048,4060p' default-values.yaml

Key findings from inspection:
- alertmanager: enabled: true (default) — I disabled this
- prometheus resources: {} (unbounded by default) — dangerous on 16GB Mac
- retention: 10d (default) — overkill for a learning lab
- grafana resources: {} (unbounded by default) — I capped these

### Step 4 — Write a trimmed values file for the 16GB Mac
    mkdir -p ~/gpu-kubernetes-lab/gitops-values
    vim ~/gpu-kubernetes-lab/gitops-values/monitoring-values.yaml

Content:

    alertmanager:
      enabled: false

    grafana:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 200m
          memory: 256Mi

    prometheus:
      prometheusSpec:
        retention: 1d
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi

    prometheusOperator:
      resources:
        requests:
          cpu: 100m
          memory: 100Mi
        limits:
          cpu: 200m
          memory: 200Mi

Rationale for each override:
- alertmanager disabled: not needed for a learning lab, saves 50-100MB RAM
- retention 1d: lab does not need 10 days of metric history, saves disk
- resource limits set: prevents unbounded memory usage on 16GB Mac
- resource requests set: gives scheduler accurate placement information

### Step 5 — Dry-run render the chart
    helm template my-monitoring prometheus-community/kube-prometheus-stack \
      -f gitops-values/monitoring-values.yaml > rendered-test.yaml

Verified overrides took effect in rendered output:

    grep -A3 "retention:" rendered-test.yaml | head -10
    grep -B2 "kind: StatefulSet" rendered-test.yaml | grep -i alertmanager
    grep -B2 "kind: Deployment" rendered-test.yaml | grep -i alertmanager

Results:
- retention: "1d" confirmed in rendered output
- No Alertmanager StatefulSet or Deployment found — override worked

### Step 6 — Create the monitoring namespace
    kubectl create namespace monitoring

Kubernetes resources are scoped to namespaces. I created a dedicated
monitoring namespace to keep all monitoring components isolated from
application workloads and kube-system components.

### Step 7 — Real install into the cluster
    helm install my-monitoring prometheus-community/kube-prometheus-stack \
      -f gitops-values/monitoring-values.yaml -n monitoring

Watched pods come up:

    kubectl get pods -n monitoring -w

All pods reached Running state:

    my-monitoring-grafana                  3/3 Running
    my-monitoring-kube-prometh-operator    1/1 Running
    my-monitoring-kube-state-metrics       1/1 Running
    my-monitoring-prometheus-node-exporter 1/1 Running (x4 nodes)
    prometheus-my-monitoring-...           2/2 Running

Grafana shows 3/3 because it runs 3 containers in one pod: the main
Grafana app plus sidecars for auto-loading dashboards and datasources.

### Step 8 — Verify deployment
    kubectl get pods -n monitoring
    kubectl get svc -n monitoring
    kubectl get daemonset -n monitoring
    kubectl get pods -n monitoring -o wide | grep node-exporter
    kubectl get endpoints my-monitoring-grafana -n monitoring

Services created:

    my-monitoring-grafana              ClusterIP   80/TCP
    my-monitoring-kube-prometh-prometheus  ClusterIP   9090/TCP,8080/TCP
    my-monitoring-prometheus-node-exporter ClusterIP   9100/TCP
    prometheus-operated                ClusterIP   None (headless)

The headless service (ClusterIP: None) is used by the Operator for
direct pod discovery without going through kube-proxy load balancing.

### Step 9 — Fix worker node InternalIP registration
Port-forward to worker node pods was failing because worker nodes had
registered the wrong network interface (eth0/192.168.5.15) as their
InternalIP. The API server uses this IP to open streaming connections
to kubelets for port-forward, exec, and log streaming.

Fixed by adding --node-ip to each worker's kubelet flags:

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

### Step 10 — Access Grafana
    kubectl port-forward -n monitoring svc/my-monitoring-grafana 3000:80

What this does: creates a tunnel from localhost:3000 on my Mac through
the API server to the Grafana Service inside the cluster on port 80.
The format is LOCAL_PORT:REMOTE_PORT. Port 3000 is my choice (any
unused port works). Port 80 is what the Service exposes (fixed by chart).

Get the admin password from the cluster Secret:

    kubectl get secret -n monitoring my-monitoring-grafana \
      -o jsonpath='{.data.admin-password}' | base64 --decode

Access at http://localhost:3000 with username admin.

### Step 11 — Verify Prometheus scraping
    kubectl port-forward -n monitoring svc/my-monitoring-kube-prometh-prometheus 9090:9090

Access at http://localhost:9090/targets to see all scrape targets and
their UP/DOWN status.

## How localhost:3000 reaches a pod on worker-3

The port-forward mechanism works as a transparent proxy chain:

    Mac browser (localhost:3000)
          ↓
    kubectl port-forward process on Mac
          ↓ opens streaming connection through API server
    kubelet on worker-3 (192.168.105.5)
          ↓
    Grafana container (10.244.3.3:3000)

This is why fixing the worker node InternalIP was critical — without
the correct shared network IP registered, the API server could not
reach worker-3's kubelet to complete the streaming connection.

## How scheduler placed pods across nodes

I did not specify which pod goes to which node. The scheduler made all
placement decisions automatically based on:
- Spreading pods across nodes to reduce blast radius
- Available CPU and memory on each node
- The control-plane NoSchedule taint (blocks regular pods)
- No explicit nodeAffinity or nodeSelector in my values file

In a production GPU cloud environment I would add explicit constraints:
taints on GPU nodes to keep CPU workloads off, tolerations on GPU pods
to allow them through, and nodeAffinity to pull them specifically toward
GPU nodes.

## Dashboard screenshots

Screenshots of the working dashboards are in docs/screenshots/:
- grafana-cluster-resources.png  — CPU/memory across all namespaces
- grafana-node-exporter.png      — host-level VM metrics per node
- grafana-networking.png         — pod-to-pod network traffic
- prometheus-targets.png         — active scrape targets showing UP status

## Industry context

kube-prometheus-stack via Helm is the real production approach for
Kubernetes monitoring. This is not a simplified lab version — it is the
same chart companies actually run. The Operator pattern, CRDs, and
ServiceMonitors are Kubernetes-specific. Outside Kubernetes (bare metal
or VMs), Prometheus is installed as a binary or Docker container with
hand-written prometheus.yml scrape configs — a genuinely different skill
set with the same underlying Prometheus concepts but completely different
tooling and workflow.

## RAM constraint decision

Due to the 16GB RAM constraint on the M4 Mac running 4 Lima VMs
simultaneously, I chose to install Prometheus and Grafana manually via
Helm first (Part A) to understand the full Helm lifecycle hands-on
before moving to GitOps management via Argo CD. In Part B, I will
uninstall this manual release and redeploy the same chart through
Argo CD, demonstrating that GitOps manages the same underlying Helm
chart — just driven by Git state instead of manual commands.
