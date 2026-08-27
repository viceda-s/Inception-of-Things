#!/usr/bin/env bash
set -euo pipefail  # exit on error/unset var, fail pipelines if any stage fails

# Supported OS: Debian/Ubuntu (apt-based), run as a user with sudo privileges.
# Installs Docker, kubectl, K3d, and curl. Safe to re-run on an already
# provisioned machine (each step checks whether its tool is already present).

KUBECTL_VERSION="v1.28.5"
K3D_VERSION="v5.6.0"

echo "==> Installing prerequisite packages (curl, ca-certificates)..."
if ! command -v curl >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y curl ca-certificates
else
  echo "curl already installed, skipping."
fi

echo "==> Installing Docker..."
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
else
  echo "Docker already installed, skipping."
fi

echo "==> Ensuring Docker daemon is enabled and running..."
sudo systemctl enable --now docker

echo "==> Verifying Docker daemon is responsive..."
sudo docker version >/dev/null

echo "==> Adding current user (${USER}) to the docker group..."
if ! id -nG "${USER}" | grep -qw docker; then
  sudo usermod -aG docker "${USER}"
  echo "NOTE: log out and back in (or run 'newgrp docker') for group membership to take effect."
else
  echo "${USER} is already in the docker group."
fi

echo "==> Installing kubectl ${KUBECTL_VERSION}..."
if ! command -v kubectl >/dev/null 2>&1; then
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x /tmp/kubectl
  sudo mv /tmp/kubectl /usr/local/bin/kubectl
else
  echo "kubectl already installed, skipping."
fi

echo "==> Installing K3d ${K3D_VERSION}..."
if ! command -v k3d >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \
    | TAG="${K3D_VERSION}" bash
else
  echo "K3d already installed, skipping."
fi

echo "==> Installed versions:"
sudo docker version
kubectl version --client
k3d version

echo "==> Done. If the docker group was just added, log out and back in before running docker without sudo."
