# Part 3 – K3d and ArgoCD (owner: viceda-s)

## Goal

Create a local K3d-based Kubernetes cluster, install ArgoCD, and manage an application deployment in the `dev` namespace using a GitOps workflow from this GitHub repository.

## Cluster setup

- Install Docker on the virtual machine.
- Use K3d to create a Kubernetes cluster.
- Install `kubectl` and configure it to talk to the K3d cluster.

## Namespaces

Create two namespaces:

- `argocd` – for the ArgoCD control plane components.
- `dev` – for the application managed by ArgoCD.

## Application

Deploy an application in the `dev` namespace using manifests stored in `p3/k8s/`:

- `deployment.yaml` – Deployment using a container image with tags `v1` and `v2`.
- `service.yaml` – Service exposing the application inside the cluster.
- `ingress.yaml` – optional Ingress or port-forwarding to access the app.

## ArgoCD configuration

- Install ArgoCD into the `argocd` namespace.
- Expose the ArgoCD API/UI (via port-forward or Ingress).
- Create an ArgoCD Application that:
  - Points to this GitHub repository.
  - Uses `p3/k8s/` as the path.
  - Targets the `dev` namespace in the K3d cluster.

## GitOps flow

1. Application manifests in `p3/k8s/` reference image tag `v1`.
2. ArgoCD syncs the manifests, and the running application responds as version `v1`.
3. You change the image tag in `deployment.yaml` to `v2`, commit, and push.
4. ArgoCD detects the change and syncs, updating the running app to version `v2`.

## Verification

- ArgoCD shows the application as Synced and Healthy.
- Calling the application endpoint shows version `v1`, then `v2` after the update.
