#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   IMAGE=quay.io/migtools/kubevirt-velero-annotations-remover:latest ./scripts/build-multiarch.sh arm64
#   IMAGE=quay.io/migtools/kubevirt-velero-annotations-remover:latest ./scripts/build-multiarch.sh multi
#
# Requires: podman 4+ (recommended). For docker, see README.

DATE_STRING=`date +%s`
IMAGE=ttl.sh/kubevirt-velero-annotations-remover-$DATE_STRING:8h
MODE="${1:-multi}"   # values: arm64 | amd64 | multi

case "$MODE" in
  arm64)
    echo "Building ARM64-only image: $IMAGE"
    podman build --platform linux/arm64 -t "$IMAGE" -f Dockerfile .
    podman push "$IMAGE"
    ;;
  amd64)
    echo "Building AMD64-only image: $IMAGE"
    podman build --platform linux/amd64 -t "$IMAGE" -f Dockerfile .
    podman push "$IMAGE"
    ;;
  multi)
    echo "Building multi-arch manifest (amd64+arm64) for $IMAGE"
    podman build --platform linux/amd64 -t "${IMAGE}-amd64" -f Dockerfile .
    podman build --platform linux/arm64 -t "${IMAGE}-arm64" -f Dockerfile .

    # Create and push manifest list
    podman manifest create "$IMAGE"
    podman manifest add "$IMAGE" "${IMAGE}-amd64"
    podman manifest add "$IMAGE" "${IMAGE}-arm64"
    podman manifest push --all "$IMAGE" "docker://$IMAGE"
    ;;
  *)
    echo "Unknown mode: $MODE (expected: arm64 | amd64 | multi)" >&2
    exit 1
    ;;
esac

echo "Done: $IMAGE"


