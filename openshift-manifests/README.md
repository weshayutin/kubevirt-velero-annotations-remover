# OpenShift Manifests for KubeVirt Velero Annotations Remover

This directory contains static OpenShift YAML manifests converted from the original Helm charts. These manifests deploy a mutating webhook that removes Velero backup annotations from KubeVirt virt-launcher pods.

## Prerequisites

- OpenShift cluster with Service CA (default on OpenShift)
- OADP (OpenShift API for Data Protection) operator installed
- Sufficient permissions to create required resources in your namespace

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