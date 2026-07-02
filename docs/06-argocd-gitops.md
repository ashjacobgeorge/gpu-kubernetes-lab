# Argo CD and GitOps Setup

## What is Argo CD

Argo CD is a GitOps continuous delivery tool that watches a Git
repository and automatically syncs the Kubernetes cluster to match
whatever is declared in Git. Instead of running helm install manually,
I push changes to Git and Argo CD handles the rest.

The core principle: Git is the single source of truth for cluster
state. Any gap between what Git declares and what the cluster actually
has is called drift, and Argo CD detects and fixes it automatically.

## Why I chose Argo CD over manual Helm installs

In Phase 2A I installed Prometheus and Grafana manually using
helm install. This works but has problems at scale:
- No audit trail of what was applied and when
- If someone manually changes something in the cluster, nobody
  knows and the change persists indefinitely
- Upgrading requires remembering to run helm upgrade manually

With Argo CD managing the same Helm charts:
- Every change goes through Git — full audit trail
- Manual cluster changes are detected and automatically reverted
- Upgrading means pushing a change to Git — Argo CD handles the rest
- 118 Kubernetes resources managed from one values file in Git

## Installation

### Step 1 - Check memory headroom before installing

    kubectl get pods -A --no-headers | wc -l

    kubectl get pods -n monitoring -o json | python3 -c "
    import json,sys
    data=json.load(sys.stdin)
    for p in data['items']:
        name=p['metadata']['name']
        for c in p['spec']['containers']:
            req=c.get('resources',{}).get('requests',{}).get('memory','none')
            print(f'{name[:50]:50} {c[\"name\"]:30} {req}')
    "

This shows total pod count and memory requests per container.
Argo CD in non-HA mode adds approximately 480MB. I confirmed
enough headroom existed before proceeding.

### Step 2 - Create the argocd namespace

    kubectl create namespace argocd

### Step 3 - Install Argo CD using server-side apply

    kubectl apply -n argocd \
      -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
      --server-side --force-conflicts

I used server-side apply from the start rather than the standard
kubectl apply. This is required because the Argo CD install manifest
includes large CRDs that exceed the 256KB Kubernetes annotation size
limit when using client-side apply. Server-side apply sends the object
to the API server for merging instead of the client storing the full
diff as an annotation.

The --force-conflicts flag resolves ownership conflicts when switching
from client-side to server-side apply on existing fields.

### Step 4 - Verify all pods are running

    kubectl get pods -n argocd -w

Expected output when healthy:

    argocd-application-controller-0                     1/1 Running
    argocd-applicationset-controller-76887dc888-xjzqh   1/1 Running
    argocd-dex-server-7ff9f9c864-dfxm7                  1/1 Running
    argocd-notifications-controller-5dbd7864d7-t6jvw    1/1 Running
    argocd-redis-c864db48d-89tww                        1/1 Running
    argocd-repo-server-666f756c89-d7hh6                 1/1 Running
    argocd-server-6666bdfdd6-l4vnh                      1/1 Running

### Step 5 - Get the initial admin password

    kubectl get secret -n argocd argocd-initial-admin-secret \
      -o jsonpath='{.data.password}' | base64 --decode

### Step 6 - Access the Argo CD UI

    kubectl port-forward -n argocd svc/argocd-server 8080:443

Open https://localhost:8080 in browser. Accept the self-signed
certificate warning (expected in a lab environment). Login with
username admin and the password from Step 5.

---

## Setting Up GitOps for the Monitoring Stack

### Step 7 - Create the gitops folder structure

    mkdir -p ~/gpu-kubernetes-lab/argocd-apps

This folder holds Argo CD Application manifests — the objects
that tell Argo CD what Git repo to watch and where to sync.

### Step 8 - Create the Application manifest

    vim ~/gpu-kubernetes-lab/argocd-apps/monitoring-app.yaml

Content:

    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: monitoring
      namespace: argocd
    spec:
      project: default
      sources:
        - repoURL: https://prometheus-community.github.io/helm-charts
          chart: kube-prometheus-stack
          targetRevision: "*"
          helm:
            releaseName: my-monitoring
            valueFiles:
              - $values/gitops-values/monitoring-values.yaml
        - repoURL: https://github.com/ashjacobgeorge/gpu-kubernetes-lab
          targetRevision: HEAD
          ref: values
      destination:
        server: https://kubernetes.default.svc
        namespace: monitoring
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true

Key fields explained:

    sources (plural)
      Multi-source Application — one source is the Helm chart repo,
      the second is my GitHub repo containing the values file.
      These two work together via the $values reference.

    ref: values
      Aliases my GitHub repo as $values so the first source can
      reference files from it using $values/path/to/file.

    destination.server: https://kubernetes.default.svc
      The internal address of the API server — means deploy to the
      cluster Argo CD itself is running in.

    automated.prune: true
      Resources removed from Git get deleted from the cluster too.

    automated.selfHeal: true
      Manual cluster changes are automatically reverted to match
      Git within 3 minutes.

    ServerSideApply=true
      Required for large CRDs from kube-prometheus-stack that
      exceed the 256KB annotation size limit.

### Step 9 - Commit the Application manifest to GitHub

Argo CD reads from Git not from local files. The manifest must
exist in the repo before Argo CD can act on it.

    cd ~/gpu-kubernetes-lab
    git add argocd-apps/
    git commit -m "Add Argo CD Application manifest for monitoring stack"
    git push origin main

### Step 10 - Apply the Application to the cluster

    kubectl apply -f argocd-apps/monitoring-app.yaml

Expected output:
    application.argoproj.io/monitoring created

### Step 11 - Verify sync status

    kubectl get application -n argocd

Expected output:
    NAME         SYNC STATUS   HEALTH STATUS
    monitoring   Synced        Healthy

Also verify in the Argo CD UI — the monitoring application should
show Synced and Healthy with a visual resource tree showing all
118 managed resources.

---

## Migrating from Manual Helm to Argo CD

At this point both Helm and Argo CD were managing the same resources
simultaneously, causing CRD ownership conflicts. I uninstalled the
manual Helm release to give Argo CD sole ownership.

### Step 12 - Verify the manual Helm release still exists

    helm list -n monitoring

Expected:
    NAME          NAMESPACE   REVISION  STATUS    CHART
    my-monitoring monitoring  1         deployed  kube-prometheus-stack-87.4.0

### Step 13 - Uninstall the manual Helm release

    helm uninstall my-monitoring -n monitoring

This removes Helm's tracking record. The actual pods may briefly
disappear since Helm manages their lifecycle. Argo CD detects the
OutOfSync state and automatically recreates everything.

### Step 14 - Force Argo CD to sync

After helm uninstall, click SYNC in the Argo CD UI or wait for
the automated sync cycle. Argo CD recreates all monitoring
resources from Git.

### Step 15 - Verify pods are back

    kubectl get pods -n monitoring

All pods should return to Running state, now solely managed by
Argo CD.

---

## Drift Detection Demo

This demonstrates the core GitOps value proposition — manual
changes to the cluster are automatically detected and reverted.

### Step 16 - Simulate an unauthorised manual change

    kubectl delete deployment my-monitoring-grafana -n monitoring

### Step 17 - Watch automatic recovery

    kubectl get pods -n monitoring -w

Argo CD detects the deleted Deployment (cluster no longer matches
Git) and recreates it automatically via selfHeal.

Evidence of automatic recovery:

    NAME                                     READY  STATUS   AGE
    my-monitoring-grafana-5686767964-f2kt2   3/3    Running  23s
    prometheus-my-monitoring-...-0           2/2    Running  48m

The Grafana pod AGE is 23 seconds while everything else shows 48
minutes. Argo CD recreated it without any manual intervention.

The same ReplicaSet hash (5686767964) with a new random suffix
(f2kt2 instead of the original 8422k) confirms Argo CD recreated
the Deployment which created a new ReplicaSet which created a new
pod — all automatically.

---

## Screenshots

Screenshots are in docs/screenshots/argocd/:

    argocd-applications-list.png      Applications overview page
    argocd-resource-tree.png          Visual tree of 118 managed resources
    argocd-synced-healthy.png         Clean Synced and Healthy state
    argocd-drift-detection-terminal.png  Pod age proving auto-recovery
    argocd-drift-healed.png           UI after drift healed
    argocd-crd-annotation-error.png   CRD size limit error for reference
    argocd-sync-error.png             Sync error state for reference

---

## Argo CD Components Summary

    argocd-application-controller  StatefulSet  Runs the GitOps loop
    argocd-repo-server             Deployment   Clones repos, renders charts
    argocd-server                  Deployment   Web UI and API
    argocd-dex-server              Deployment   Authentication and SSO
    argocd-redis                   Deployment   Caching layer
    argocd-applicationset-controller Deployment Manages ApplicationSet CRDs
    argocd-notifications-controller  Deployment Sends notifications

---

## Industry Context

Argo CD is a CNCF graduated project and one of the two dominant
GitOps engines (alongside Flux CD). It is used at scale by companies
including Intuit (where it originated), BMW, Adobe, and many others.

The pattern I implemented — Helm for chart packaging, Argo CD for
GitOps delivery — is the standard cloud-native deployment stack.
In a GPU cloud marketplace this same pattern would manage GPU Operator
deployments, monitoring stacks, and tenant workload configurations
across multiple clusters, with Git providing the audit trail and
rollback capability that regulated or multi-tenant environments require.
