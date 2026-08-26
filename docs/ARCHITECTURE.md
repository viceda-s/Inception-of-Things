# Inception-of-Things – Architecture

## Overview

This document describes the high-level architecture of the environments you build for the Inception-of-Things subject (K3s with Vagrant, K3s with three applications and Ingress, and K3d with ArgoCD and GitOps).

## Repository structure

- `p1/` – Part 1: two-node K3s cluster on Vagrant VMs.
- `p2/` – Part 2: single-node K3s cluster running three web applications behind an Ingress with host-based routing.
- `p3/` – Part 3: K3d cluster with ArgoCD and a GitOps-managed application in a `dev` namespace.
- `bonus/` – Optional GitLab integration for Part 3.
- `docs/` – Architecture and per-part documentation.

## Environments

### Part 1 – K3s and Vagrant

Two Vagrant-managed virtual machines form a minimal K3s cluster:

- Server node `<login>S` at `192.168.56.110` running the K3s controller.
- Worker node `<login>SW` at `192.168.56.111` running the K3s agent.

Both VMs are provisioned with minimal resources and configured for passwordless SSH access. K3s is installed on both nodes and joined into a single cluster.

### Part 2 – K3s and three applications

A single Vagrant VM `<login>S` at `192.168.56.110` runs K3s in server mode and hosts three web applications. An Ingress routes requests based on the HTTP `Host` header:

- `app1.com` → Application 1
- `app2.com` → Application 2 (with 3 replicas)
- Any other host → Application 3 (default backend)

### Part 3 – K3d and ArgoCD

A K3d cluster runs on a virtual machine with Docker installed. Two namespaces are created:

- `argocd` – Hosts the ArgoCD control plane.
- `dev` – Hosts the example application managed by ArgoCD.

ArgoCD is configured with an Application that points to this GitHub repository and syncs Kubernetes manifests from `p3/k8s/` into the `dev` namespace.

## GitOps workflow (Part 3)

The GitOps flow is:

1. You push Kubernetes manifests (including Deployment image tags) to the main branch of the repository.
2. ArgoCD watches the repository and detects changes in the configured path.
3. ArgoCD syncs those changes into the `dev` namespace.
4. The application is updated in-cluster, for example from `v1` to `v2` of the container image.

## Bonus – GitLab integration

If implemented, a local GitLab instance runs in its own namespace and integrates with the same cluster so that the Part 3 application can be managed via GitLab in addition to GitHub.
