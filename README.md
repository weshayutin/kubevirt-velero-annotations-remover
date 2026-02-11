# OpenShift Manifests for KubeVirt Velero Annotations Remover

This directory contains static OpenShift YAML manifests converted from the original Helm charts. These manifests deploy a mutating webhook that removes Velero backup annotations from KubeVirt virt-launcher pods.

## Prerequisites

- OpenShift cluster with Service CA (default on OpenShift)
- OADP (OpenShift API for Data Protection) operator installed
- Sufficient permissions to create required resources in your namespace

## What does this code do?

This project deploys a Kubernetes mutating admission webhook that automatically removes Velero backup hook annotations from KubeVirt virtual machine pods.

### Background

When KubeVirt creates a virt-launcher pod for a virtual machine, it automatically adds four Velero backup hook annotations:

- `pre.hook.backup.velero.io/container` - Specifies the container to run the freeze command
- `pre.hook.backup.velero.io/command` - Command to freeze the VM filesystem before backup
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
IMAGE=ttl.sh/kubevirt-velero-annotations-remover-$DATE_STRING:8h

# ARM64-only build (pushes to registry):
./scripts/build-multiarch.sh arm64

# OR multi-arch (amd64 + arm64) manifest:
./scripts/build-multiarch.sh multi

# The build script prints the image it pushed (line starting with "Done:").
# Use that exact value as IMAGE for the render step below.
```

### Option 1: Deploy individual manifests

Apply the manifests in order (from this `openshift-manifests` directory). The `Service` will trigger OpenShift Service CA to create the `webhook-tls` secret used by the `Deployment`:

```bash
oc apply -f 01-pvc.yaml
oc apply -f 02-service.yaml
oc apply -f 03-webhook.yaml
oc apply -f 04-deployment.yaml
```

### Option 2: Deploy all-in-one manifest

```bash
# From this `openshift-manifests` directory
oc apply -f all-in-one.yaml

# Or from the repo root
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

## How it works

The webhook intercepts CREATE and UPDATE operations on pods with the label `kubevirt.io: virt-launcher` and removes any annotations that start with:
- `pre.hook.backup.velero.io/`
- `post.hook.backup.velero.io/`

This prevents issues during Velero backups of KubeVirt VMs by removing problematic annotations from virt-launcher pods.

### TLS with OpenShift Service CA

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

1. Check if cert-manager is running:
   ```bash
   oc get pods -n cert-manager
   ```

2. Verify the serving certificate secret exists (created by Service CA after the Service is applied):
   ```bash
   oc get secret webhook-tls -n openshift-adp
   ```

3. Check webhook logs:
   ```bash
   oc logs -n openshift-adp deployment/kubevirt-velero-annotations-remover
   ```

4. Verify the webhook configuration:
   ```bash
   oc get mutatingwebhookconfiguration kubevirt-velero-annotations-remover -o yaml
   ```


## Status of Testing

* pod runs
```
all -n openshift-adp
Warning: apps.openshift.io/v1 DeploymentConfig is deprecated in v4.14+, unavailable in v4.10000+
NAME                                                       READY   STATUS    RESTARTS   AGE
pod/kubevirt-velero-annotations-remover-6f596dfb7b-h9zvd   1/1     Running   0          11m
pod/node-agent-ckkrt                                       1/1     Running   0          34d
pod/node-agent-mtrq6                                       1/1     Running   0          34d

```

* service is running
```
whayutin@fedora:~/OPENSHIFT/git/OADP/kubevirt-velero-annotations-remover$ oc logs -f pod/kubevirt-velero-annotations-remover-6f596dfb7b-h9zvd
time=2026-02-11T14:08:00.000Z level=INFO msg="Starting webhook server..."
```

## SUCCESS
```
time=2026-01-29T20:57:29.339Z level=INFO msg="Starting webhook server..."
time=2026-01-29T20:58:19.770Z level=INFO msg="Processing admission request" operation=CREATE vm=my-windows-vm pod=unknown namespace=my-windows-vm
time=2026-01-29T20:58:19.770Z level=INFO msg="  Removing annotation" key=post.hook.backup.velero.io/command value="["/usr/bin/virt-freezer", "--unfreeze", "--name", "my-windows-vm", "--namespace", "my-windows-vm"]"
time=2026-01-29T20:58:19.770Z level=INFO msg="  Removing annotation" key=post.hook.backup.velero.io/container value=compute
time=2026-01-29T20:58:19.770Z level=INFO msg="  Removing annotation" key=pre.hook.backup.velero.io/command value="["/usr/bin/virt-freezer", "--freeze", "--name", "my-windows-vm", "--namespace", "my-windows-vm"]"
time=2026-01-29T20:58:19.770Z level=INFO msg="  Removing annotation" key=pre.hook.backup.velero.io/container value=compute
time=2026-01-29T20:58:19.770Z level=INFO msg="Removed Velero backup hook annotations" count=4 vm=my-windows-vm
time=2026-01-29T20:58:32.731Z level=INFO msg="Processing admission request" operation=UPDATE vm=my-windows-vm pod=virt-launcher-my-windows-vm-g5hkx namespace=my-windows-vm
time=2026-01-29T20:58:32.731Z level=INFO msg="No Velero annotations found - no changes needed" vm=my-windows-vm

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

The webhook removes these four Velero backup hook annotations:

- `pre.hook.backup.velero.io/container`
- `pre.hook.backup.velero.io/command`
- `post.hook.backup.velero.io/container`
- `post.hook.backup.velero.io/command`