#!/usr/bin/env bash
set -euo pipefail  # exit on error/unset var, fail pipelines if any stage fails

# Installs ArgoCD into the existing argocd namespace.
# ArgoCD version is pinned for reproducibility setup and defense runs.
# The application controller is StatefulSet: server.repo-server are Deployments.

ARGOCD_VERSION="v2.13.2"
ARGOCD_NAMESPACE="argocd"
ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
ARGOCD_CLI_URL="https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
WAIT_TIMEOUT=300  # seconds

echo "==> Checking required commands"

for command in kubectl curl base64; do
    if ! command -v "${command}" &> /dev/null; then
        echo "Error: ${command} is not installed. Please install it and try again."
        exit 1
    fi
done

echo "==> Checking Kubernetes cluster access"

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "Error: kubectl cannot reach a Kubernetes cluster. Please run 'kubectl config use-context <context>' to select a cluster and try again." >&2
    exit 1
fi

echo "==> Ensuring namespace '${ARGOCD_NAMESPACE}' exists"

kubectl create namespace "${ARGOCD_NAMESPACE}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

echo "==> Checking ArgoCD CLI"

if command -v argocd >/dev/null 2>&1; then
    INSTALLED_VERSION="$(argocd version --client --short 2>/dev/null || true)"

    if printf '%s' "${INSTALLED_VERSION}" | grep -q "${ARGOCD_VERSION}"; then
        echo "==> ArgoCD CLI version ${ARGOCD_VERSION} is already installed."
    else
        echo "==> ArgoCD CLI exists but is not ${INSTALLED_VERSION}; installing pinned version"
        sudo curl -fsSL "${ARGOCD_CLI_URL}" -o /usr/local/bin/argocd
        sudo chmod +x /usr/local/bin/argocd
    fi
else 
    echo "==> Installing ArgoCD CLI ${ARGOCD_VERSION}"
    sudo curl -fsSL "${ARGOCD_CLI_URL}" -o /usr/local/bin/argocd
    sudo chmod +x /usr/local/bin/argocd
fi

echo "==> ArgoCD CLI version"
argocd version --client --short

echo "==> Applying ArgoCD ${ARGOCD_VERSION} manifests"

kubectl apply \
    --server-side \
    --force-conflicts \
    -n "${ARGOCD_NAMESPACE}" \
    -f "${ARGOCD_MANIFEST_URL}"

echo "==> Waiting for ArgoCD server deployment"

kubectl rollout status \
    deployment/argocd-server \
    -n "${ARGOCD_NAMESPACE}" \
    --timeout="${WAIT_TIMEOUT}s"

echo "==> Waiting for ArgoCD repository server deployment"

kubectl rollout status \
    deployment/argocd-repo-server \
    -n "${ARGOCD_NAMESPACE}" \
    --timeout="${WAIT_TIMEOUT}s"

echo "==> Waiting for ArgoCD application controller StatefulSet"

kubectl rollout status \
    statefulset/argocd-application-controller \
    -n "${ARGOCD_NAMESPACE}" \
    --timeout="${WAIT_TIMEOUT}s"

echo "==> Applying ArgoCD Application manifest"

APPLICATION_MANIFEST="$(dirname "${BASH_SOURCE[0]}")/../confs/application.yaml"

kubectl apply -f "${APPLICATION_MANIFEST}"

echo "==> Waiting for Application 'playground' to sync"

kubectl wait \
    --for=jsonpath='{.status.sync.status}'=Synced \
    application/playground \
    -n "${ARGOCD_NAMESPACE}" \
    --timeout="${WAIT_TIMEOUT}s"

echo "==> Application sync complete"

echo "==> ArgoCD installation complete"

echo
echo "==> ArgoCD Pods"
kubectl get pods -n "${ARGOCD_NAMESPACE}"

echo
echo "==> ArgoCD Services"
kubectl get svc -n "${ARGOCD_NAMESPACE}"

echo
echo "==> Initial admin password"
echo "WARNING: Treat this as a secret. Do not commit it to Git."
kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d
echo

echo
echo "==> Open the ArgoCD UI locally"
echo "kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443"
echo "Then open https://localhost:8080 --username admin --insecure"

echo
echo "==> Verify ArgoCD"
echo "argocd version"
echo "argocd app list"
echo "kubectl get pods -n ${ARGOCD_NAMESPACE}"
echo "kubectl get events -n ${ARGOCD_NAMESPACE} --sort-by=.metadata.creationTimestamp"


