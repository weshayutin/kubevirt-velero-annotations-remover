# KubeVirt Velero Annotations Remover

A Go-based Kubernetes mutating admission webhook that automatically removes Velero backup hook annotations from KubeVirt virt-launcher pods. Also includes a shell script for retroactively cleaning up existing pods.

## Prerequisites

- OpenShift cluster with Service CA (default on OpenShift)
- OADP (OpenShift API for Data Protection) operator installed
- Sufficient permissions to create required resources in your namespace

## What does this code do?

This project deploys a Kubernetes mutating admission webhook that automatically removes Velero backup hook annotations from KubeVirt virtual machine pods.

### Background

When KubeVirt creates a virt-launcher pod for a virtual machine, it automatically adds Velero backup hook annotations:

- `pre.hook.backup.velero.io/container` - Specifies the container to run the freeze command
- `pre.hook.backup.velero.io/command` - Command to freeze the VM filesystem before backup
- `pre.hook.backup.velero.io/timeout` - Timeout for the pre-hook operation
- `post.hook.backup.velero.io/container` - Specifies the container to run the unfreeze command
- `post.hook.backup.velero.io/command` - Command to unfreeze the VM filesystem after backup

These annotations instruct Velero to execute filesystem freeze/unfreeze operations using `virt-freezer` during backups. However, in certain scenarios, you may want to prevent these operations.

### How it works

The webhook operates as a Kubernetes mutating admission controller that:

1. **Intercepts pod events**: Triggers on CREATE and UPDATE operations for pods with the `kubevirt.io=virt-launcher` label
2. **Identifies annotations**: Scans for any annotations starting with `pre.hook.backup.velero.io/` or `post.hook.backup.velero.io/`
3. **Removes annotations**: Generates a JSON patch to remove these annotations before the pod is persisted to etcd
4. **Logs activity**: Provides detailed logging showing which VM, pod, and specific annotations were removed

The webhook runs transparently in the background and requires no manual intervention once deployed.

## Deployment

### Build and push the container image (ARM64 or multi-arch)

Use the helper to build either ARM64-only (for ARM64 clusters) or a multi-arch image (amd64+arm64). Example using a temporary ttl.sh image. Run these from the repository root:

```bash
DATE_STRING=`date +%s`
IMAGE=ttl.sh/kubevirt-velero-annotations-remover-go-$DATE_STRING:8h

# ARM64-only build (pushes to registry):
./build-multiarch.sh arm64

# OR multi-arch (amd64 + arm64) manifest:
./build-multiarch.sh multi

# The build script prints the image it pushed (line starting with "Done:").
# Use that exact value as IMAGE for the render step below.
```

### Option 1: Deploy individual manifests

Apply the manifests in order (from the `openshift-manifests` directory). The `Service` will trigger OpenShift Service CA to create the `webhook-tls` secret used by the `Deployment`:

```bash
oc apply -f openshift-manifests/01-pvc.yaml
oc apply -f openshift-manifests/02-service.yaml
oc apply -f openshift-manifests/03-webhook.yaml
oc apply -f openshift-manifests/04-deployment.yaml
```

### Option 2: Deploy all-in-one manifest

```bash
oc apply -f openshift-manifests/all-in-one.yaml
```

### Option 3: Deploy all manifests at once

Use the render script to substitute namespace and image (run from the repo root):

```bash
NAMESPACE=openshift-adp IMAGE=$IMAGE ./scripts/render.sh
oc apply -f rendered/
```

## Configuration

The manifests are configured to deploy in the `openshift-adp` namespace by default. To use a different namespace and/or image, use the render script:

```bash
NAMESPACE=my-namespace IMAGE=quay.io/my-org/my-image:tag ./scripts/render.sh
```

## Retroactive Annotation Removal Script

The webhook only intercepts new CREATE and UPDATE events. To remove Velero annotations from virt-launcher pods that already exist (created before the webhook was deployed), use the included shell script:

```bash
# Remove annotations from pods in a single namespace
./scripts/remove-velero-annotations.sh -n <namespace>

# Remove annotations from pods across all namespaces
./scripts/remove-velero-annotations.sh --all

# Preview changes without applying (dry-run)
./scripts/remove-velero-annotations.sh --dry-run -n <namespace>
./scripts/remove-velero-annotations.sh --dry-run --all
```

The script uses `oc` if available, otherwise falls back to `kubectl`.

### Example output

```
$ ./scripts/remove-velero-annotations.sh --dry-run -n my-windows-vm
Scanning namespace 'my-windows-vm' for virt-launcher pods...
(dry-run mode — no changes will be made)

[dry-run] Would patch pod my-windows-vm/virt-launcher-my-windows-vm-xqc4f — removing 4 annotation(s):
  - pre.hook.backup.velero.io/container
  - pre.hook.backup.velero.io/command
  - post.hook.backup.velero.io/container
  - post.hook.backup.velero.io/command

--- Summary ---
Pods scanned:    1
Pods patched:    1
Annotations removed: 4
(dry-run — no changes were applied)
```

## TLS with OpenShift Service CA

These manifests use OpenShift's Service CA instead of cert-manager:
- The `Service` has annotation `service.beta.openshift.io/serving-cert-secret-name: webhook-tls` which creates the TLS secret.
- The `MutatingWebhookConfiguration` has annotation `service.beta.openshift.io/inject-cabundle: "true"` which injects the cluster CA bundle.
- The `Deployment` mounts the `webhook-tls` secret at `/tls` and serves HTTPS on 8443.
- The `Deployment` runs with `serviceAccountName: velero` in the target namespace.

## Security

The deployment includes OpenShift security best practices:
- Non-root user execution
- Dropped capabilities
- Read-only root filesystem considerations
- SecurityContext configuration

## Troubleshooting

1. Verify the serving certificate secret exists (created by Service CA after the Service is applied):

```bash
oc get secret webhook-tls -n openshift-adp
```

2. Check webhook logs:

```bash
oc logs -n openshift-adp deployment/kubevirt-velero-annotations-remover
```

3. Verify the webhook configuration:

```bash
oc get mutatingwebhookconfiguration kubevirt-velero-annotations-remover -o yaml
```

## Status of Testing

* Pod runs:

```
$ oc get all -n openshift-adp
NAME                                                       READY   STATUS    RESTARTS   AGE
pod/kubevirt-velero-annotations-remover-6f596dfb7b-h9zvd   1/1     Running   0          11m
pod/node-agent-ckkrt                                       1/1     Running   0          34d
pod/node-agent-mtrq6                                       1/1     Running   0          34d
```

* Webhook log output:

```
time=2026-02-11T19:01:15.569Z level=INFO msg="Processing admission request" operation=CREATE vm=my-windows-vm pod=unknown namespace=my-windows-vm
time=2026-02-11T19:01:15.569Z level=INFO msg="  Removing annotation" key=pre.hook.backup.velero.io/command value="[\"/usr/bin/virt-freezer\", \"--freeze\", \"--name\", \"my-windows-vm\", \"--namespace\", \"my-windows-vm\"]"
time=2026-02-11T19:01:15.569Z level=INFO msg="  Removing annotation" key=pre.hook.backup.velero.io/timeout value=60s
time=2026-02-11T19:01:15.569Z level=INFO msg="  Removing annotation" key=post.hook.backup.velero.io/command value="[\"/usr/bin/virt-freezer\", \"--unfreeze\", \"--name\", \"my-windows-vm\", \"--namespace\", \"my-windows-vm\"]"
time=2026-02-11T19:01:15.569Z level=INFO msg="  Removing annotation" key=pre.hook.backup.velero.io/container value=compute
time=2026-02-11T19:01:15.569Z level=INFO msg="  Removing annotation" key=post.hook.backup.velero.io/container value=compute
time=2026-02-11T19:01:15.569Z level=INFO msg="Removed Velero backup hook annotations" count=5 vm=my-windows-vm
time=2026-02-11T19:01:18.524Z level=INFO msg="Processing admission request" operation=UPDATE vm=my-windows-vm pod=virt-launcher-my-windows-vm-4p2rd namespace=my-windows-vm
time=2026-02-11T19:01:18.524Z level=INFO msg="No Velero annotations found - no changes needed" vm=my-windows-vm
```

## Inspecting VM Annotations

### Check Velero-specific annotations on the virt-launcher pod

```bash
oc get pod -n <namespace> -l kubevirt.io=virt-launcher -o jsonpath='{.items[0].metadata.annotations}' | jq 'with_entries(select(.key | contains("velero")))'
```

If the webhook is working correctly, this should return `{}` (empty), confirming all Velero annotations were removed.

### Check all annotations on the virt-launcher pod

```bash
oc get pod -n <namespace> -l kubevirt.io=virt-launcher -o jsonpath='{.items[0].metadata.annotations}' | jq
```

### Check VM object annotations

Note: Backup hooks are on the pod, not the VM object itself.

```bash
oc get vm <vm-name> -n <namespace> -o jsonpath='{.metadata.annotations}' | jq
```

### Detailed view with YAML output

```bash
oc get pod -n <namespace> -l kubevirt.io=virt-launcher -o yaml | grep -A 20 "annotations:"
```

### Annotations Removed by the Webhook

The webhook removes any Velero backup hook annotations starting with `pre.hook.backup.velero.io/` or `post.hook.backup.velero.io/`, including:

- `pre.hook.backup.velero.io/container`
- `pre.hook.backup.velero.io/command`
- `pre.hook.backup.velero.io/timeout`
- `post.hook.backup.velero.io/container`
- `post.hook.backup.velero.io/command`
