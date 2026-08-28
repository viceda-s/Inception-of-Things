# Part 2 – K3s and three applications (owner: brunmart)

## Goal

Run three simple web applications on a single-node K3s cluster and expose them via an Ingress
that routes based on the HTTP `Host` header:

- `app1.com` → Application 1
- `app2.com` → Application 2 (3 replicas)
- any other host → Application 3 (default backend)

## Architecture

```
                     Your PC
                        |
                        | HTTP, Host: app1.com / app2.com / other
                        |
                 192.168.56.110
                        |
                    K3s Node (brunmartS)
                        |
                 Ingress (Traefik, apps-ingress)
                 /      |      \
                /       |       \
         app1.com   app2.com   (no host match)
             |           |         |
             v           v         v
        app1-service app2-service app3-service
             |           |         |
          App 1      App 2 x3   App 3
       (1 replica) (3 replicas) (1 replica)
```

All application resources (Deployments, Services, Ingress) live in the `apps` namespace.

### VM topology

This environment is nested: the machine you get for the project (`iot`) is itself a VM, and
Vagrant creates a *second*, inner VM (`brunmartS`) inside it to run K3s.

```
Physical machine
   └── outer VM (hostname: iot)      ← where the repo is cloned, where `vagrant` runs
          └── inner VM (brunmartS)   ← created by `vagrant up`, runs K3s
```

- The repo lives on the outer VM, e.g. `~/Inception-of-Things`.
- `vagrant up` (run from `~/Inception-of-Things/p2` on the outer VM) creates `brunmartS`.
- `vagrant ssh` (also from `p2/` on the outer VM) opens a shell **inside** `brunmartS` — that is
  where `kubectl` and K3s actually live. `kubectl` will not work on the outer VM itself.
- The repo's `p2/` directory is synced into `brunmartS` at `/vagrant` via an `rsync`-type synced
  folder — see **Troubleshooting → Stale files inside the VM** below, this does *not* happen
  automatically on every edit.

## Virtual machine

- VM – Server:
  - Hostname: `brunmartS`
  - Static IP: `192.168.56.110` (private, host-only network)
  - Provider: VirtualBox
  - Resources: 1 CPU, 2048 MB RAM
  - SSH: passwordless (Vagrant's default insecure keypair)
  - Synced folder: `p2/` (outer VM) → `/vagrant` (inner VM), `type: rsync`

Defined in [`p2/Vagrantfile`](../p2/Vagrantfile).

## K3s configuration

- Installed via [`p2/scripts/install_k3s.sh`](../p2/scripts/install_k3s.sh), run automatically as
  a Vagrant shell provisioner on `vagrant up`.
- Pinned version: `v1.28.5+k3s1` (so every teammate's VM gets an identical cluster).
- Installed in **server** mode (single node, no separate agent — this differs from Part 1, which
  splits controller/agent across two machines).
- The script waits for the `k3s` systemd service to become active and for the node to reach
  `Ready` before finishing provisioning, so `vagrant up` completing means the cluster is usable.
- `kubectl` is installed alongside K3s and reads `/etc/rancher/k3s/k3s.yaml` by default. That file
  is root-owned — see **Troubleshooting → kubectl permission denied** below.

## Kubernetes resources

All manifests live under [`p2/k8s/`](../p2/k8s/):

| File | Resource | Purpose |
|---|---|---|
| `namespace.yaml` | `Namespace/apps` | Namespace all other Part 2 resources live in |
| `app1-deployment.yaml` | `Deployment/app1-deployment` | 1 replica, `http-echo`, text `"Hello from App1"` |
| `app1-service.yaml` | `Service/app1-service` | ClusterIP, port 80 → 5678 |
| `app2-deployment.yaml` | `Deployment/app2-deployment` | **3 replicas**, `http-echo`, text `"Hello from App2"` |
| `app2-service.yaml` | `Service/app2-service` | ClusterIP, port 80 → 5678 |
| `app3-deployment.yaml` | `Deployment/app3-deployment` | 1 replica, `http-echo`, text `"Hello from App3"` |
| `app3-service.yaml` | `Service/app3-service` | ClusterIP, port 80 → 5678 |
| `ingress.yaml` | `Ingress/apps-ingress` | Host-based routing across all three Services |

## Application architecture

All three apps use the same image, [`hashicorp/http-echo`](https://hub.docker.com/r/hashicorp/http-echo),
which starts an HTTP server on port `5678` and replies to every request with a fixed text string.
This makes it trivial to prove routing is correct — the response text alone identifies which app
answered.

| App | Replicas | Response text | Service ClusterIP port |
|---|---|---|---|
| App 1 | 1 | `Hello from App1` | 80 → 5678 |
| App 2 | 3 | `Hello from App2` | 80 → 5678 |
| App 3 | 1 | `Hello from App3` | 80 → 5678 |

Each Deployment's pod template carries the label `app: <name>`, which its Service selects on —
the standard Deployment/Service pairing pattern, repeated identically three times.

## Ingress routing rules

[`p2/k8s/ingress.yaml`](../p2/k8s/ingress.yaml) uses Traefik (K3s's bundled default Ingress
controller, no separate install needed) with `spec.ingressClassName: traefik`:

- `Host: app1.com`, path `/` → `app1-service:80`
- `Host: app2.com`, path `/` → `app2-service:80`
- a rule with **no `host` field** → `app3-service:80` — this matches any request whose `Host`
  header didn't match one of the rules above, acting as the default backend.

### Why not `spec.defaultBackend`?

The standard Kubernetes way to express "anything unmatched" is `spec.defaultBackend`. We tried
that first — it was accepted by the API server and showed up correctly in
`kubectl describe ingress`, but every request to an unmatched host returned a 404 from Traefik
instead of reaching `app3-service`. This is a known limitation: K3s's bundled Traefik does not
reliably serve `spec.defaultBackend` for Ingress resources that also have host-based rules.

The fix that actually works is an explicit rule with **no host** — Traefik resolves this as a
catch-all with lower priority than the host-matched rules, and it is what `ingress.yaml` uses now.
If you see this pattern elsewhere and wonder why it's not just `defaultBackend`, this is why.

## Reproducing this from scratch

Tested by fully destroying and rebuilding `brunmartS` (`vagrant destroy -f && vagrant up`) and
redeploying from a clean cluster.

```bash
# from the outer VM, in the repo root
cd p2
vagrant up          # provisions brunmartS: static IP, K3s server, kubectl — fully automated
vagrant ssh          # opens a shell inside brunmartS
```

Inside `brunmartS`:

```bash
cd /vagrant

# IMPORTANT: apply the namespace first, on its own. Applying the whole
# directory in one shot can race — the namespaced resources sometimes get
# submitted before the Namespace exists, producing `NotFound` errors.
sudo kubectl apply -f k8s/namespace.yaml
sudo kubectl apply -f k8s/

# confirm everything is up
sudo kubectl get all -n apps
```

Expected: 5 pods total (1× app1, 3× app2, 1× app3), all `1/1 Running`; 3 Services; 1 Ingress.

### Local host resolution (optional, for browser/`curl` without `-H`)

On the **outer VM** (same host-only network as `brunmartS`), add to `/etc/hosts`:

```
192.168.56.110 app1.com
192.168.56.110 app2.com
```

`other.com`/any unmapped domain is deliberately **not** added — it's a real public domain, so
resolving it locally would defeat the point. Test the default-backend case with an explicit
`Host` header instead (see below).

## Testing commands used

All of the following were run against `brunmartS` and reflect actual captured output.

**Host-based routing:**

```bash
$ curl http://app1.com
Hello from App1
$ curl http://app2.com
Hello from App2
$ curl -H "Host: other.com" http://192.168.56.110
Hello from App3
```

**Load balancing across app2's 3 replicas** — `http-echo` returns identical text from every pod,
so proving load-balancing needs pod-level logs, not response bodies:

```bash
# terminal 1, inside brunmartS
sudo kubectl logs -n apps -l app=app2 --prefix -f

# terminal 2, inside brunmartS
for i in $(seq 1 15); do curl -s -H "Host: app2.com" http://192.168.56.110 > /dev/null; done
```

Result: requests landed on all three pods in a round-robin pattern
(`...-mmjqk` → `...-fxbpq` → `...-rgdr4` → repeat), confirming Traefik spreads load across every
replica rather than pinning to one.

**Self-healing (failure & recovery):**

```bash
$ sudo kubectl get pods -n apps -w      # in one terminal, left running
$ sudo kubectl delete pod <app2-pod-name> -n apps   # in another terminal
pod "app2-deployment-...-mmjqk" deleted
```

Watching the first terminal: the deleted pod goes `Terminating`, and a replacement is created
automatically (`Pending` → `ContainerCreating` → `Running`), restoring the Deployment to its
desired replica count with no manual intervention. Repeated for App 1's single pod with the same
result. The Ingress kept responding correctly to both `app1.com` and `app2.com` throughout.

**Full resource check:**

```bash
$ sudo kubectl get all -n apps
NAME                                   READY   STATUS    RESTARTS   AGE
pod/app1-deployment-...               1/1     Running   0          ...
pod/app2-deployment-... (x3)          1/1     Running   0          ...
pod/app3-deployment-...               1/1     Running   0          ...

NAME                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/app1-service   ClusterIP   10.43.x.x       <none>        80/TCP    ...
service/app2-service   ClusterIP   10.43.x.x       <none>        80/TCP    ...
service/app3-service   ClusterIP   10.43.x.x       <none>        80/TCP    ...

NAME                              READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/app1-deployment   1/1     1            1           ...
deployment.apps/app2-deployment   3/3     3            3           ...
deployment.apps/app3-deployment   1/1     1            1           ...
```

## Troubleshooting notes

Real issues hit while building and verifying this part — documented so nobody has to debug them
twice.

### `kubectl` says "connection refused" to `localhost:8080`

You're running `kubectl` on the **outer VM**, not inside `brunmartS`. `kubectl`/K3s only exist on
the inner VM. Run `vagrant ssh` from `p2/` on the outer VM first.

### `kubectl` says `permission denied` reading `/etc/rancher/k3s/k3s.yaml`

That file is root-owned by design. Prefix commands with `sudo` (as this doc does throughout), or
copy it to your own `~/.kube/config` with adjusted ownership if you want passwordless `kubectl`.

### `the path "k8s/appN-....yaml" does not exist` inside `brunmartS`

Almost always one of:
1. You're not in `/vagrant` (the synced-folder mount point) — `cd /vagrant` first.
2. The synced folder is stale — see next entry.
3. Your local git branch is missing the commit that added the file (e.g. you branched before
   another PR merged) — `git fetch origin && git merge origin/main` on the outer VM to catch up.

### Stale files inside the VM (`vagrant`'s `rsync` synced folder doesn't auto-sync)

Unlike VirtualBox's default shared-folder mechanism, an `rsync`-type synced folder only syncs at
specific moments: `vagrant up`, `vagrant reload`, and `vagrant provision`. Editing files on the
outer VM after that does **not** propagate automatically. If `brunmartS` is behaving like it's
running old manifests, force a sync from the **outer VM** (not inside `brunmartS`):

```bash
cd p2
vagrant rsync
```

### `NotFound: namespaces "apps" not found` when applying the whole `k8s/` directory at once

`kubectl apply -f k8s/` submits every file's create/update in one batch with no guaranteed
ordering; the Namespace can be processed after resources that already need it to exist. Apply the
namespace first, on its own, then the rest:

```bash
sudo kubectl apply -f k8s/namespace.yaml
sudo kubectl apply -f k8s/
```

### Requests to an unmatched host return 404 instead of reaching App 3

See **Ingress routing rules → Why not `spec.defaultBackend`?** above. Use a host-less rule, not
`spec.defaultBackend`.

### `Ingress Class: <none>` in `kubectl describe ingress`

Caused by using the deprecated `kubernetes.io/ingress.class` annotation. Use
`spec.ingressClassName: traefik` instead.

## Verification checklist

- [x] `kubectl get pods -n apps` shows all app pods running (3 replicas for Application 2).
- [x] `curl`/browser with different `Host` headers returns the correct app's response for all
      three routing cases, including the unmatched-host default.
- [x] Load is distributed across all 3 of Application 2's replicas (confirmed via pod logs).
- [x] Deleting a pod triggers automatic replacement with no manual intervention, for both a
      single-replica (App 1) and multi-replica (App 2) Deployment.
- [x] The full stack reproduces from a freshly destroyed/rebuilt VM using only the documented
      two-step apply order.
