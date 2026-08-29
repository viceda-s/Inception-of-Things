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

#### K3s vs. K3d

The subject asks that this distinction be understood explicitly, since Part 1/2 use one and Part 3 uses the other:

- **K3s** is a lightweight Kubernetes *distribution* — a single binary that runs the API server, scheduler, controller-manager, kubelet, and a default CNI/Ingress/storage stack, meant to run directly on a VM or bare-metal host. Parts 1 and 2 install K3s straight onto Vagrant VMs.
- **K3d** is a *wrapper* that runs K3s **inside Docker containers** instead of on the host directly: each "node" (server or agent) is a container, and cluster lifecycle (`k3d cluster create/delete`) is just container lifecycle. Part 3 uses K3d specifically so the whole cluster can be created and destroyed on a single VM without Vagrant, using only Docker.

In short: K3d does not replace K3s, it packages K3s to run as Docker containers — the cluster you get is still K3s underneath (`kubectl get nodes` reports a K3s version), just started and torn down through Docker rather than installed on the host OS.

#### Architecture diagram

```text
Virtual Machine (Ubuntu, Docker installed)
│
└── Docker
    │
    └── K3d cluster "iot-p3"  (K3s running in Docker containers)
        │
        ├── k3d-iot-p3-server-0        — K3s server container (control plane + kubelet)
        ├── k3d-iot-p3-serverlb        — K3d load balancer container
        │     └── host port 8888 ──▶ container port 80 (Traefik HTTP entrypoint)
        │
        ├── namespace: kube-system     — CoreDNS, Traefik, metrics-server, local-path-provisioner
        │
        ├── namespace: argocd          — ArgoCD control plane
        │     └── Application "playground" watches this GitHub repo (p3/k8s/, branch main)
        │
        └── namespace: dev             — GitOps-managed application
              ├── Deployment "playground"  (wil42/playground:v1 or :v2)
              ├── Service "playground"     (ClusterIP, port 8888)
              └── Ingress "playground"     (Traefik, routes / → Service)
```

Request path for `curl http://localhost:8888/`:

```text
host:8888 → k3d-iot-p3-serverlb:80 → Traefik (kube-system) → Ingress "playground" (dev)
          → Service "playground" (dev) → Pod "playground" (dev), container port 8888
```

## GitOps workflow (Part 3)

The GitOps flow is:

1. You push Kubernetes manifests (including Deployment image tags) to the main branch of the repository.
2. ArgoCD watches the repository and detects changes in the configured path.
3. ArgoCD syncs those changes into the `dev` namespace.
4. The application is updated in-cluster, for example from `v1` to `v2` of the container image.

## Bonus – GitLab integration

If implemented, a local GitLab instance runs in its own namespace and integrates with the same cluster so that the Part 3 application can be managed via GitLab in addition to GitHub.
