#!/usr/bin/env bash
set -euo pipefail  # exit on error/unset var, fail pipelines if any stage fails

# Part 3 K3d cluster configuration.
# The cluster uses one K3s server and no agents to keep the mandatory setup minimal.
# Host port 8888 is forwarded through K3d's load balancer to Traefik's HTTP entrypoint
# (port 80 in-cluster), matching the app port used by the subject's
# "curl http://localhost:8888/" check. Routing from there to the playground Service
# is done by the Ingress in p3/k8s/ingress.yaml, applied by ArgoCD.
CLUSTER_NAME="iot-p3"
CLUSTER_CONTEXT="k3d-${CLUSTER_NAME}"
APP_PORT="8888"
TRAEFIK_HTTP_PORT="80"
NODE_WAIT_TIMEOUT="180s"

echo "==> Checking required commands..."
for cmd in k3d kubectl docker; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: '${cmd}' is required but was not found in PATH." >&2
    echo "Run p3/scripts/install-deps.sh first." >&2
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker is not available for the current user." >&2
  echo "Make sure the Docker daemon is running and log out/in after joining the docker group." >&2
  exit 1
fi

echo "==> Checking for an existing '${CLUSTER_NAME}' cluster..."
if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -Fxq "${CLUSTER_NAME}"; then
  echo "==> Found existing cluster '${CLUSTER_NAME}'; deleting it for a clean re-run..."
  k3d cluster delete "${CLUSTER_NAME}"
fi

echo "==> Creating K3d cluster '${CLUSTER_NAME}'..."
k3d cluster create "${CLUSTER_NAME}" \
  --servers 1 \
  --agents 0 \
  --port "${APP_PORT}:${TRAEFIK_HTTP_PORT}@loadbalancer" \
  --wait

echo "==> Selecting kubectl context '${CLUSTER_CONTEXT}'..."
kubectl config use-context "${CLUSTER_CONTEXT}"

echo "==> Waiting for the node to reach Ready state..."
kubectl wait node --all --for=condition=Ready --timeout="${NODE_WAIT_TIMEOUT}"

kube_system_pods_ready() {
  local pod_lines
  pod_lines=$(kubectl get pods -n kube-system --no-headers 2>/dev/null)
  [ -n "${pod_lines}" ] || return 1
  echo "${pod_lines}" | awk '
    $3 == "Completed" { next }
    { split($2, ready, "/"); if (ready[1] != ready[2]) exit 1 }
  '
}

echo "==> Waiting for kube-system pods to become ready..."
for _ in {1..36}; do
  kube_system_pods_ready && break
  sleep 5
done

echo "==> Cluster '${CLUSTER_NAME}' is ready."
echo
echo "==> K3d clusters:"
k3d cluster list
echo
echo "==> Kubernetes nodes:"
kubectl get nodes -o wide
echo
echo "==> Pods (all namespaces):"
kubectl get pods -A
echo
echo "==> Host port ${APP_PORT} is mapped to Traefik's HTTP entrypoint on the K3d load balancer."
echo "==> Once the app and its Ingress are deployed, it will be reachable at http://localhost:${APP_PORT}/"
