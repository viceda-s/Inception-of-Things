# Part 2 – K3s and three applications (owner: brunmart)

## Goal

Run three simple web applications on a single-node K3s cluster and expose them via an Ingress that routes based on the HTTP `Host` header.

## Virtual machine

- VM – Server:
  - Hostname: `<login>S`
  - IP: `192.168.56.110`
  - Role: K3s server running all workloads

## Applications

Three applications run in the cluster, each with its own Deployment and Service:

- Application 1 – responds when the `Host` header is `app1.com`.
- Application 2 – responds when the `Host` header is `app2.com` (Deployment has 3 replicas).
- Application 3 – default application when no other host matches.

## Kubernetes resources

Typical resources under `p2/k8s/`:

- `namespace.yaml` – optional dedicated namespace for the apps.
- `app1-deployment.yaml`, `app1-service.yaml`.
- `app2-deployment.yaml`, `app2-service.yaml` (with `replicas: 3`).
- `app3-deployment.yaml`, `app3-service.yaml`.
- `ingress.yaml` – Ingress with host rules and a default backend.

## Ingress behavior

The Ingress must route:

- `Host: app1.com` → Service for Application 1.
- `Host: app2.com` → Service for Application 2.
- Any other host → Service for Application 3.

## Verification

- `kubectl get pods` shows all app pods running (with 3 replicas for Application 2).
- `curl` or a browser using different `Host` headers returns different app responses.
