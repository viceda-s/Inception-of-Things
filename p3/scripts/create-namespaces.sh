#!/usr/bin/bash
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NAMESPACES_FILE="${IOT_ROOT}/p3/confs/namespaces.yaml"

echo "==> Applying Part 3 namespaces"
kubectl apply -f "${NAMESPACES_FILE}"

echo "==> Verifying required namespaces"
kubectl get namespace argocd dev

echo "==> Part 3 namespaces are ready"
