#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-openshift-adp}"
IMAGE="${IMAGE:-quay.io/migtools/kubevirt-velero-annotations-remover-go:latest}"

manifests_dir="openshift-manifests"
output_dir="rendered"

mkdir -p "$output_dir"

for f in 01-pvc.yaml 02-service.yaml 03-webhook.yaml 04-deployment.yaml; do
  sed \
    -e "s/namespace: .*/namespace: ${NAMESPACE}/g" \
    -e "s/kubevirt-velero-annotations-remover\.openshift-adp\./kubevirt-velero-annotations-remover.${NAMESPACE}./g" \
    -e "s|quay.io/migtools/kubevirt-velero-annotations-remover-go:latest|${IMAGE}|g" \
    "$manifests_dir/$f" > "$output_dir/$f"
done

printf -- '---\n' > "$output_dir/all-in-one.yaml"
for f in 01-pvc.yaml 02-service.yaml 03-webhook.yaml 04-deployment.yaml; do
  cat "$output_dir/$f" >> "$output_dir/all-in-one.yaml"
  printf -- '\n---\n' >> "$output_dir/all-in-one.yaml"
done

echo "Rendered manifests in $output_dir (namespace=$NAMESPACE, image=$IMAGE)"

