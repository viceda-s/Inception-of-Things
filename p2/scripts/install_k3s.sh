#!/usr/bin/env bash
set -euo pipefail  # exit on error/unset var, fail pipelines if any stage fails

K3S_VERSION="v1.28.5+k3s1"  # pinned so every machine gets the same cluster

echo "==> Installing K3s ${K3S_VERSION} in server mode..."
# installs the k3s binary + systemd service, enabled and started automatically
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" sh -

echo "==> Waiting for K3s service to be active..."
# installer can return before the service finishes starting
until sudo systemctl is-active --quiet k3s; do
  sleep 2
done

echo "==> Waiting for node to reach Ready state..."
# service can be active while the node internals (CNI etc.) are still initializing
sudo kubectl wait node --all --for=condition=Ready --timeout=120s

echo "==> K3s installed and node is Ready."
sudo kubectl get nodes
