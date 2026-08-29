# Part 3 – K3d and ArgoCD (owner: viceda-s)

## Goal

Create a local K3d-based Kubernetes cluster, install ArgoCD, and manage an application deployment in the `dev` namespace using a GitOps workflow from this GitHub repository.

## K3s vs. K3d

Parts 1 and 2 install **K3s**, a lightweight Kubernetes distribution, directly on a
VM. Part 3 uses **K3d** instead: K3d runs K3s *inside Docker containers*, so a full
cluster (control plane and, optionally, agents) can be created and destroyed with a
single command on any machine with Docker, without provisioning a VM per node. The
cluster is still K3s underneath — K3d only changes how it is started and torn down.
See [`docs/ARCHITECTURE.md`](ARCHITECTURE.md#k3s-vs-k3d) for a longer explanation and
the full architecture diagram.

## Prerequisites

- A VM (or host) running a Debian/Ubuntu distribution with `apt` and `sudo` access.
- Internet access to `get.docker.com`, `dl.k8s.io`, `raw.githubusercontent.com`, and
  `github.com` (all scripts below download pinned tool versions from these hosts).
- Nothing else needs to be preinstalled: `p3/scripts/install-deps.sh` (below) installs
  Docker, `kubectl`, and K3d from scratch.

## Cluster setup

- Install Docker on the virtual machine.
- Use K3d to create a Kubernetes cluster.
- Install `kubectl` and configure it to talk to the K3d cluster.

### Installing dependencies

`p3/scripts/install-deps.sh` installs everything Part 3 needs on a fresh VM:

- `curl` and `ca-certificates` (if missing).
- Docker, via the official `get.docker.com` install script, then enables and starts
  the `docker` systemd service.
- Adds the current user to the `docker` group if not already a member.
- `kubectl` (pinned to `v1.28.5`), downloaded from `dl.k8s.io`.
- K3d (pinned to `v5.6.0`), via the official K3d install script.

The script is idempotent: every step first checks whether its tool is already present
(and at least installed) before doing any work, so it is safe to re-run on a
partially-provisioned machine.

```bash
# Install (or reconcile) all Part 3 dependencies
./p3/scripts/install-deps.sh

# Verify
docker version
kubectl version --client
k3d version
```

**Manual step that cannot be scripted:** if the script just added your user to the
`docker` group for the first time, group membership only takes effect in a *new*
login shell or process tree — a script running in your current shell cannot change
that shell's own group membership. Log out and back in, or run `newgrp docker`,
before continuing. If `id -nG "$USER"` already lists `docker` (for example, on a
machine where this was done in a previous session), no action is needed and `docker
version` will work immediately.

### Cluster creation and deletion

`p3/scripts/create-cluster.sh` creates a single-node K3d cluster named `iot-p3` (one K3s server, no agents — enough for ArgoCD plus one application across the two namespaces below). Host port `8888` is published through K3d's load balancer straight to Traefik's HTTP entrypoint (container port `80`), so the app is reachable at `http://localhost:8888/` once its Ingress is deployed — see [Application](#application) below.

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

Deploy the `playground` application in the `dev` namespace using manifests stored in
`p3/k8s/`.

The directory contains only application resources managed by ArgoCD:

- `deployment.yaml` – Runs one `playground` replica using `wil42/playground:v1`
  (or `v2`, see below) on container port `8888`.
- `service.yaml` – Exposes the application internally on port `8888` (`ClusterIP`).
- `ingress.yaml` – A Traefik `Ingress` routing `/` to the `playground` Service. This
  is what makes `http://localhost:8888/` (published by `create-cluster.sh`, see
  [Cluster creation and deletion](#cluster-creation-and-deletion)) actually reach the
  app: the K3d load balancer forwards host `8888` to Traefik, and Traefik needs this
  Ingress to know where to send it. Without it, requests reach Traefik and get a
  `404`.

**Note:** `main` currently has the image tag already set to `v2` (from a previous
GitOps demonstration). The walkthrough below narrates starting from `v1` for
teaching purposes; run `grep image p3/k8s/deployment.yaml` to see the actual current
tag before following along.

All resources use the following labels and selectors:

```yaml
app.kubernetes.io/name: playground
app.kubernetes.io/part-of: p3
```

The Deployment defines HTTP readiness and liveness probes against `/` on port `8888`.
The image update from `v1` to `v2` requires changing only the image tag in
`p3/k8s/deployment.yaml`:

```diff
- image: wil42/playground:v1
+ image: wil42/playground:v2
```

Once ArgoCD is bootstrapped (see [ArgoCD Application](#argocd-application)), it
applies and keeps these resources in sync automatically — no manual `kubectl apply`
is needed. To apply them directly instead (e.g. before ArgoCD is set up, or while
iterating on the manifests):

```bash
kubectl apply -f p3/k8s/
kubectl rollout status deployment/playground -n dev
kubectl get deployment,pods,svc -n dev
```

With the Ingress applied and the K3d cluster's port mapping in place (see
[Cluster creation and deletion](#cluster-creation-and-deletion)), the app is reachable
directly at `http://localhost:8888/` — no port-forward needed:

```bash
curl http://localhost:8888/
```

If you need to bypass Traefik and the Ingress entirely (e.g. to debug the Service or
Pod in isolation), port-forward the Service directly on a different local port:

```bash
kubectl port-forward -n dev svc/playground 8080:8888
curl http://localhost:8080/
```

Expected response, starting from `v1`:

```json
{"status":"ok","message":"v1"}
```

After changing the image tag to `v2`, commit and push the change. ArgoCD should
detect the Git change and synchronize the Deployment. Verify the new version with:

```bash
curl http://localhost:8888/
```

Expected response after synchronization:

```json
{"status":"ok","message":"v2"}
```

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

Reach the ArgoCD UI/API locally with a port-forward (only the `playground` app has an
Ingress; ArgoCD itself is accessed via port-forward for this project):

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

## ArgoCD Application

`p3/confs/application.yaml` defines the ArgoCD `Application` resource that connects
this GitHub repository to the `dev` namespace:

- `spec.source.repoURL` – `https://github.com/viceda-s/Inception-of-Things.git`
- `spec.source.targetRevision` – `main`, this project's only long-lived branch.
- `spec.source.path` – `p3/k8s`, containing only the application resources.
- `spec.destination` – the in-cluster API server, namespace `dev`.
- `spec.syncPolicy.automated` – `prune: true` and `selfHeal: true`, so ArgoCD
  applies new commits automatically and reverts manual drift, without a
  `kubectl apply -f p3/k8s/` step.
- `syncOptions: [CreateNamespace=false]` – `dev` is already created by
  `create-namespaces.sh`; ArgoCD only manages the application resources inside it.

Like the `p3/k8s/` manifests, this file lives outside `p3/k8s/` (in `p3/confs/`)
so ArgoCD does not try to manage or prune itself.

`p3/scripts/bootstrap-argocd.sh` applies this manifest once ArgoCD's Deployments
and StatefulSet are ready, then waits for the Application to report `Synced`:

```bash
kubectl get applications -n argocd
kubectl describe application playground -n argocd
```

## GitOps flow

1. `p3/k8s/deployment.yaml` references a `wil42/playground` image tag (`v1` or `v2`;
   see the note in [Application](#application) for the tag currently on `main`).
2. ArgoCD's `playground` Application (`p3/confs/application.yaml`) automatically
   synchronizes the resources from `p3/k8s/` into the `dev` namespace.
3. The Deployment becomes ready after its HTTP readiness probe succeeds.
4. The application endpoint returns the corresponding version.
5. Change only the image tag in `p3/k8s/deployment.yaml`, e.g. from `v1` to `v2`.
6. Commit and push the change to GitHub.
7. ArgoCD detects the change and automatically synchronizes the new Deployment —
   no manual `kubectl apply` is needed.
8. The application endpoint returns the new version.

## Verification

- ArgoCD shows the application as `Synced` and `Healthy`.
- `kubectl rollout status deployment/playground -n dev` completes successfully.
- `kubectl get pods -n dev` shows the application Pod as `Running` and `Ready`.
- `curl http://localhost:8888/` returns version `v1`.
- After the GitOps image update, the same endpoint returns version `v2`.

## Evidence

Captured from `p3/scripts/bootstrap-argocd.sh` on a cluster created by
`p3/scripts/create-cluster.sh`, immediately after the `playground` Application's
resources were synced:

```text
$ kubectl get applications -n argocd
NAME         SYNC STATUS   HEALTH STATUS
playground   Synced        Healthy

$ kubectl get pods,svc,ingress -n dev
NAME                             READY   STATUS    RESTARTS   AGE
pod/playground-d4f4ddb9c-kzk2q   1/1     Running   0          40s

NAME                 TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/playground   ClusterIP   10.43.249.43   <none>        8888/TCP   40s

NAME                                   CLASS     HOSTS   ADDRESS      PORTS   AGE
ingress.networking.k8s.io/playground   traefik   *       172.18.0.2   80      40s

$ curl http://localhost:8888/
{"status":"ok", "message": "v2"}
```

(This run's `deployment.yaml` was already on `v2` on `main`; the same `curl` returns
`v1` right after applying a `deployment.yaml` pinned to `wil42/playground:v1`.)

### Proving the `v1` → `v2` GitOps update

To reproduce the version-change proof required for the defense:

```bash
# 1. Confirm the current tag and running version
grep image: p3/k8s/deployment.yaml
curl http://localhost:8888/

# 2. Edit only the tag, e.g. v1 -> v2
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/' p3/k8s/deployment.yaml
git add p3/k8s/deployment.yaml
git commit -m "feat(p3): bump playground image to v2"
git push origin main

# 3. Watch ArgoCD pick up the change (self-heal/auto-sync, no kubectl apply)
kubectl get application playground -n argocd -w
kubectl get pods -n dev -w

# 4. Confirm the endpoint changed
curl http://localhost:8888/
```

Illustrative transcript once ArgoCD reconciles the new commit (pod name and exact
timing will differ per run — capture your own output here as defense evidence):

```text
$ kubectl get application playground -n argocd
NAME         SYNC STATUS   HEALTH STATUS
playground   Synced        Healthy

$ kubectl get pods -n dev
NAME                         READY   STATUS    RESTARTS   AGE
playground-d4f4ddb9c-k6g6z   1/1     Running   0          12s

$ curl http://localhost:8888/
{"status":"ok", "message": "v2"}
```

ArgoCD's default polling interval is about three minutes; to force an immediate
reconciliation instead of waiting, either click **Sync** in the ArgoCD UI
(`kubectl port-forward svc/argocd-server -n argocd 8080:443`, see
[Accessing ArgoCD](#accessing-argocd)), or trigger it from the CLI:

```bash
argocd app sync playground
# or, without the CLI:
kubectl patch application playground -n argocd --type merge -p '{"operation":{"sync":{}}}'
```
