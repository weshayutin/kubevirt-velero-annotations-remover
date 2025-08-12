# kubevirt-velero-annotations-remover Helm Chart

## Purpose
This Helm chart deploys a Kubernetes Mutating Admission Webhook that automatically removes Velero-related annotations from `virt-launcher` pods created by KubeVirt. This helps prevent unwanted Velero backup/restore behaviors on these pods.

## Features
- MutatingWebhookConfiguration for `virt-launcher` pods
- Automatic TLS certificate management using cert-manager
- CA bundle injection via cert-manager annotation (no manual caBundle handling)
- Minimal configuration required

## Prerequisites
- Kubernetes cluster (v1.16+ recommended)
- [cert-manager](https://cert-manager.io/) installed in your cluster
- [Helm](https://helm.sh/) 3.x

## Installation
1. **Install cert-manager** (if not already present):
   ```sh
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
   ```

2. **Install the chart**:
   ```sh
   helm install kubevirt-velero-annotations-remover ./charts/kubevirt-velero-annotations-remover \
     --namespace <your-namespace> --create-namespace
   ```

## How it works
- The webhook intercepts pod creation and update requests for pods labeled `kubevirt.io=virt-launcher`.
- It removes any Velero-related annotations from these pods.
- TLS certificates are automatically generated and managed by cert-manager.
- The CA bundle is injected into the webhook configuration by cert-manager using the `cert-manager.io/inject-ca-from` annotation.

## Uninstallation
```sh
helm uninstall kubevirt-velero-annotations-remover --namespace <your-namespace>
```

## Notes
- Make sure cert-manager is running and ready before installing this chart.
- The webhook only affects pods with the label `kubevirt.io=virt-launcher`.
- No manual CA or certificate management is required.

## Configuration
You can override the following values in `values.yaml`:

```yaml
service:
  port: 443
webhook:
  caBundle: "" # Not required, managed by cert-manager
```

## License
This project is licensed under the Unlicense. You can use, modify, and distribute it without restriction.
