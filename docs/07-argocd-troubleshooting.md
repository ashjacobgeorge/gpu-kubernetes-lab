# Troubleshooting — Argo CD and GitOps (Phase 2B)

Real issues encountered during Argo CD installation and GitOps
setup. Every issue below actually happened during the build.

---

## Issue 1 - CRD annotation size limit exceeded

### Symptom
After installing Argo CD and creating the monitoring Application,
sync failed with:

    CustomResourceDefinition "alertmanagerconfigs.monitoring.coreos.com"
    is invalid: metadata.annotations: Too long:
    must have at most 262144 bytes

    one or more synchronization tasks completed unsuccessfully

### Root cause
Standard kubectl apply stores the entire last-applied-configuration
as an annotation on each resource. The CRDs from kube-prometheus-stack
are very large — their rendered YAML exceeds the 256KB Kubernetes
annotation size limit. This is a known issue specifically with
kube-prometheus-stack and Argo CD.

### Fix
Add ServerSideApply=true to the Application manifest syncOptions:

    syncPolicy:
      syncOptions:
        - ServerSideApply=true

Server-side apply sends the object to the API server for merging
instead of the client computing and storing the full diff as an
annotation. This bypasses the 262144 byte limit entirely.

Also apply the Argo CD install manifest itself using server-side
apply to ensure the Argo CD CRDs are installed correctly:

    kubectl apply -n argocd \
      -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
      --server-side --force-conflicts

### Lesson learned
Any Helm chart with large CRDs (kube-prometheus-stack,
cert-manager, istio) will hit this issue with Argo CD.
Always add ServerSideApply=true to syncOptions as a default
for charts known to have large CRDs.

---

## Issue 2 - ApplicationSet controller CrashLoopBackOff

### Symptom
After installing Argo CD, one pod was stuck in CrashLoopBackOff:

    argocd-applicationset-controller   0/1   CrashLoopBackOff   146 restarts

Logs showed:

    failed to get restmapping: no matches for kind "ApplicationSet"
    in version "argoproj.io/v1alpha1"
    CRD should be installed before calling Start

### Root cause
The ApplicationSet CRD was not installed because the initial
kubectl apply used client-side apply which hit the annotation
size limit. The CRD installation failed silently and the
ApplicationSet controller could not find its own CRD.

### Fix
Reapply the full Argo CD install manifest using server-side apply
with force-conflicts to properly install all CRDs including
the ApplicationSet CRD:

    kubectl apply -n argocd \
      -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
      --server-side \
      --force-conflicts

The --force-conflicts flag is required because some fields already
had owners from the previous client-side apply. This takes ownership
of those fields and resolves the conflict.

Verify fix:

    kubectl get pods -n argocd
    kubectl logs -n argocd argocd-applicationset-controller-xxx --tail=20

### Lesson learned
Always use --server-side when installing Argo CD, not the standard
kubectl apply. The standard install docs show kubectl apply without
--server-side which works in most environments but fails with
large CRD bundles. Add --server-side --force-conflicts to the
install command as a standard practice.

---

## Issue 3 - unknown field spec.source.helm.chart

### Symptom
kubectl apply on the Application manifest failed:

    Error from server (BadRequest): error when creating
    "argocd-apps/monitoring-app.yaml": Application in version
    "v1alpha1" cannot be handled as a Application: strict decoding
    error: unknown field "spec.source.helm.chart"

### Root cause
Tried to combine path (a folder path inside a Git repo) and chart
(an external Helm chart repository) in the same single source block.
These are mutually exclusive source types in Argo CD:

    # Wrong - cannot combine path and chart in same source
    source:
      repoURL: https://github.com/ashjacobgeorge/gpu-kubernetes-lab
      path: gitops-values
      helm:
        chart: kube-prometheus-stack   # invalid here

### Fix
Use multiple sources — one source for the Helm chart repository
and a second source for the values file in your GitHub repo:

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

The ref: values aliases the second source as $values so the first
source can reference files from it.

### Lesson learned
When using an external Helm chart with a values file from your own
Git repo, you must use the multi-source feature (sources plural,
not source singular). Check Argo CD version supports multi-source
(requires Argo CD v2.6+).

---

## Issue 4 - Conflict migrating from manual Helm to Argo CD

### Symptom
After creating the Argo CD Application, the sync showed errors
about patching CRDs:

    error when patching "/dev/shm/1736654374":
    CustomResourceDefinition.apiextensions.k8s.io is invalid

Both Helm and Argo CD were trying to manage the same resources
simultaneously, causing ownership conflicts on the CRDs.

### Root cause
When Argo CD synced the monitoring Application, it tried to apply
the same CRDs that the existing manual Helm release had already
installed. Both had different owner annotations and conflicted.

### Fix
The correct migration sequence is:

    Step 1: Install Argo CD
    Step 2: Create Application manifest pointing at chart and values
    Step 3: Commit manifest to GitHub
    Step 4: Apply the Application manifest
    Step 5: Verify Argo CD synced successfully (Synced + Healthy)
    Step 6: THEN run helm uninstall to remove Helm tracking
    Step 7: Argo CD detects OutOfSync and recreates everything
    Step 8: Verify all pods running again under Argo CD management

Never run helm install and Argo CD simultaneously on the same
release. One must fully hand off to the other.

Verify Helm release is gone:

    helm list -n monitoring
    # Should show empty

Verify Argo CD owns everything:

    kubectl get application -n argocd
    # Should show Synced + Healthy

### Lesson learned
When migrating from manual Helm to Argo CD, always do the full
handover sequence. Do not delete the Helm release before Argo CD
has successfully synced — there will be a brief outage if you do.
Let Argo CD sync first, then uninstall Helm.

---

## Issue 5 - Pods disappeared after helm uninstall

### Symptom
After running helm uninstall my-monitoring -n monitoring, all
monitoring pods disappeared and Argo CD showed OutOfSync:

    kubectl get pods -n monitoring
    No resources found in monitoring namespace.

    kubectl get application -n argocd
    NAME         SYNC STATUS   HEALTH STATUS
    monitoring   OutOfSync     Healthy

### Root cause
helm uninstall deleted the pods because Argo CD had not yet
fully taken ownership. The ServerSideApply sync had not completed
when helm uninstall was run, leaving a gap in ownership.

### Fix
Click SYNC in the Argo CD UI to force an immediate sync, or wait
for the automated sync cycle (up to 3 minutes). Argo CD detects
the OutOfSync state and recreates all monitoring resources from Git.

This is actually Argo CD self-healing working correctly — it sees
the cluster does not match Git and fixes it automatically.

Verify recovery:

    kubectl get pods -n monitoring
    kubectl get application -n argocd
    # Should show all pods Running and Synced + Healthy

### Lesson learned
After helm uninstall, expect a brief period of OutOfSync before
Argo CD recreates the resources. This is normal and expected.
Do not panic — Argo CD will restore everything automatically.
The recovery time depends on image pull speed and cluster resources.
