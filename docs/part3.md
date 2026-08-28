# Part 3 – K3d and ArgoCD (owner: viceda-s)

## Goal

Create a local K3d-based Kubernetes cluster, install ArgoCD, and manage an application deployment in the `dev` namespace using a GitOps workflow from this GitHub repository.

## Cluster setup

- Install Docker on the virtual machine.
- Use K3d to create a Kubernetes cluster.
- Install `kubectl` and configure it to talk to the K3d cluster.

### Cluster creation and deletion

`p3/scripts/create-cluster.sh` creates a single-node K3d cluster named `iot-p3` (one K3s server, no agents — enough for ArgoCD plus one application across the two namespaces below). Host port `8888` is published through K3d's load balancer so the app is reachable at `http://localhost:8888/`, matching the port used by Wil's playground application.

The script is safe to re-run: if a cluster named `iot-p3` already exists it is deleted and recreated, then `kubectl`'s context is set to `k3d-iot-p3` and the script waits for the node and `kube-system` pods to be ready.

```bash
# Create (or safely recreate) the cluster
./p3/scripts/create-cluster.sh

# Delete the cluster manually
k3d cluster delete iot-p3

# Verify
k3d cluster list
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -A
```

## Namespaces

`p3/scripts/create-namespaces.sh` applies `p3/confs/namespaces.yaml`, creating:

- `argocd` – for the ArgoCD control plane components.
- `dev` – for the application managed by ArgoCD.

This manifest is kept in `p3/confs/` rather than `p3/k8s/`, since `p3/k8s/` is the ArgoCD
Application source path — placing it there would make ArgoCD manage and prune the
namespaces (including its own) against the `dev` destination.

```bash
# Create the namespaces
./p3/scripts/create-namespaces.sh

# Verify
kubectl get namespace argocd dev
```

## Application

Deploy an application in the `dev` namespace using manifests stored in `p3/k8s/`:

- `deployment.yaml` – Deployment using a container image with tags `v1` and `v2`.
- `service.yaml` – Service exposing the application inside the cluster.
- `ingress.yaml` – optional Ingress or port-forwarding to access the app.

## ArgoCD configuration

`p3/scripts/bootstrap-argocd.sh` installs a pinned ArgoCD release into the `argocd` namespace (creating it if `create-namespaces.sh` hasn't run yet), applies the official manifests server-side, and installs the matching `argocd` CLI if it is missing or a different version. The script waits for the `argocd-server` and `argocd-repo-server` Deployments and the `argocd-application-controller` StatefulSet to roll out before it exits, then prints the initial admin password and the commands below.

The script is safe to re-run: the namespace apply and CLI install are idempotent, and re-applying the pinned manifest just reconciles the existing resources.

```bash
# Install (or reconcile) ArgoCD
./p3/scripts/bootstrap-argocd.sh

# Verify
kubectl get pods -n argocd
kubectl get svc -n argocd
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
```

### Accessing ArgoCD

The initial admin password is only ever printed to the terminal by the bootstrap script — it is never written to a file or committed to Git. Retrieve it again at any time with:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Reach the UI/API locally with a port-forward (no Ingress needed for this project):

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open `https://localhost:8080` and log in as `admin` with the password above. The ArgoCD CLI installed by the bootstrap script can be used the same way:

```bash
argocd login localhost:8080 --username admin --password <password> --insecure
argocd app list
```

### Troubleshooting

```bash
# Pods stuck Pending/CrashLoopBackOff
kubectl describe pod -n argocd <pod-name>
kubectl logs -n argocd <pod-name>

# Recent events, oldest first
kubectl get events -n argocd --sort-by=.metadata.creationTimestamp

# Re-run the bootstrap script to reconcile drifted/missing resources
./p3/scripts/bootstrap-argocd.sh
```

Once ArgoCD is healthy, create an ArgoCD Application that:

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
