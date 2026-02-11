#!/usr/bin/env bash
set -euo pipefail

# Annotations to remove from virt-launcher pods
ANNOTATIONS=(
  "pre.hook.backup.velero.io/container"
  "pre.hook.backup.velero.io/command"
  "pre.hook.backup.velero.io/timeout"
  "post.hook.backup.velero.io/container"
  "post.hook.backup.velero.io/command"
)

NAMESPACE=""
ALL_NAMESPACES=false
DRY_RUN=false

usage() {
  cat <<EOF
Usage:
  $(basename "$0") -n <namespace>         Remove annotations in a single namespace
  $(basename "$0") --all                  Remove annotations across all namespaces
  $(basename "$0") --dry-run -n <ns>      Preview changes without applying
  $(basename "$0") --dry-run --all        Preview cluster-wide changes

Options:
  -n, --namespace <ns>   Target a specific namespace
  --all                  Target all namespaces
  --dry-run              Print what would be done without making changes
  -h, --help             Show this help message
EOF
  exit "${1:-0}"
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --all)
      ALL_NAMESPACES=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "Error: unknown option '$1'" >&2
      usage 1
      ;;
  esac
done

# --- Validate arguments ---
if [[ -z "$NAMESPACE" ]] && [[ "$ALL_NAMESPACES" == false ]]; then
  echo "Error: specify either -n <namespace> or --all" >&2
  usage 1
fi

if [[ -n "$NAMESPACE" ]] && [[ "$ALL_NAMESPACES" == true ]]; then
  echo "Error: cannot use both -n and --all" >&2
  usage 1
fi

# --- Detect CLI tool (oc or kubectl) ---
if command -v oc &>/dev/null; then
  CLI="oc"
elif command -v kubectl &>/dev/null; then
  CLI="kubectl"
else
  echo "Error: neither oc nor kubectl found in PATH" >&2
  exit 1
fi

# --- Build namespace flag ---
if [[ "$ALL_NAMESPACES" == true ]]; then
  NS_FLAG="--all-namespaces"
  echo "Scanning all namespaces for virt-launcher pods..."
else
  NS_FLAG="-n $NAMESPACE"
  echo "Scanning namespace '$NAMESPACE' for virt-launcher pods..."
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run mode — no changes will be made)"
fi
echo ""

# --- Find virt-launcher pods ---
# Output: NAMESPACE NAME (tab-separated)
PODS=$($CLI get pods $NS_FLAG -l kubevirt.io=virt-launcher \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

if [[ -z "$PODS" ]]; then
  echo "No virt-launcher pods found."
  exit 0
fi

TOTAL_PODS=0
PATCHED_PODS=0
TOTAL_ANNOTATIONS=0

while IFS=$'\t' read -r pod_ns pod_name; do
  [[ -z "$pod_name" ]] && continue
  TOTAL_PODS=$((TOTAL_PODS + 1))

  # Get current annotations as JSON
  CURRENT=$($CLI get pod "$pod_name" -n "$pod_ns" \
    -o jsonpath='{.metadata.annotations}' 2>/dev/null || echo "{}")

  # Check which Velero annotations are present
  REMOVE_ARGS=()
  for ann in "${ANNOTATIONS[@]}"; do
    if echo "$CURRENT" | grep -q "$ann"; then
      REMOVE_ARGS+=("${ann}-")
      TOTAL_ANNOTATIONS=$((TOTAL_ANNOTATIONS + 1))
    fi
  done

  if [[ ${#REMOVE_ARGS[@]} -eq 0 ]]; then
    continue
  fi

  PATCHED_PODS=$((PATCHED_PODS + 1))

  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] Would patch pod $pod_ns/$pod_name — removing ${#REMOVE_ARGS[@]} annotation(s):"
    for arg in "${REMOVE_ARGS[@]}"; do
      echo "  - ${arg%-}"
    done
  else
    echo "Patching pod $pod_ns/$pod_name — removing ${#REMOVE_ARGS[@]} annotation(s):"
    for arg in "${REMOVE_ARGS[@]}"; do
      echo "  - ${arg%-}"
    done
    $CLI annotate pod "$pod_name" -n "$pod_ns" "${REMOVE_ARGS[@]}"
  fi
done <<< "$PODS"

# --- Summary ---
echo ""
echo "--- Summary ---"
echo "Pods scanned:    $TOTAL_PODS"
echo "Pods patched:    $PATCHED_PODS"
echo "Annotations removed: $TOTAL_ANNOTATIONS"
if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run — no changes were applied)"
fi
