# Part 1 – K3s and Vagrant (owner: luis-fif)

## Goal

Provision two lightweight virtual machines with Vagrant and install K3s to create a minimal two-node Kubernetes cluster.

## Virtual machines

- VM 1 – Server:
  - Hostname: `<login>S`
  - IP: `192.168.56.110`
  - Role: K3s server (controller)
- VM 2 – Worker:
  - Hostname: `<login>SW`
  - IP: `192.168.56.111`
  - Role: K3s agent (worker)

Both machines use minimal resources (1 CPU, 512–1024 MB RAM) and passwordless SSH access via Vagrant.

## Vagrantfile responsibilities

- Define both machines, hostnames, and static IP addresses.
- Configure synced folders if needed.
- Run shell provisioning scripts to install dependencies and K3s.

## Provisioning scripts

- `scripts/bootstrap-common.sh` – common packages, users, SSH keys.
- `scripts/install-k3s-server.sh` – installs and configures K3s in server mode.
- `scripts/install-k3s-agent.sh` – installs and configures K3s in agent mode and joins it to the server.

## Verification

- `vagrant up` brings both VMs up.
- `kubectl get nodes` on the server lists both nodes as Ready.
