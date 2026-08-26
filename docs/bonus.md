# Bonus – GitLab Integration (optional)

## Goal

Extend the Part 3 environment by adding a local GitLab instance that integrates with the same Kubernetes cluster, so that the application managed by ArgoCD can be driven from GitLab in addition to (or instead of) GitHub.

## Namespace

All GitLab components must run in a dedicated namespace:

- `gitlab`

This keeps GitLab separate from the `argocd` and `dev` namespaces used in Part 3.

## Installation approach

Typical steps (to be implemented in `bonus/scripts/` and `bonus/confs/`):

- Install required dependencies (Helm, if not already present).
- Add the official GitLab Helm chart repository.
- Deploy GitLab into the `gitlab` namespace using Helm (or equivalent manifests).
- Configure access (initial root password, external URL if needed, etc.).
- Optionally configure:
  - A project to host the application manifests.
  - CI/CD variables or tokens if you integrate GitLab CI with the cluster.

## Integration with Part 3

The bonus must ensure that everything done in Part 3 still works, but now using GitLab:

- The application in the `dev` namespace can be managed via a GitLab repository.
- ArgoCD (or another tool, if you choose) can be configured to sync from GitLab instead of GitHub, or in parallel.
- The v1 → v2 update flow demonstrated in Part 3 should also be possible via GitLab.

Implementation options include:

- Pointing the existing ArgoCD Application to a GitLab repository URL.
- Creating a second ArgoCD Application that targets the GitLab repo.
- Using GitLab CI to update manifests that ArgoCD then syncs.

## Files and folders

Expected structure under the `bonus/` directory:

- `bonus/Vagrantfile` (if you use an additional VM for this).
- `bonus/scripts/`
  - `install-gitlab.sh` or similar.
  - Any helper scripts for configuration.
- `bonus/confs/`
  - Helm values files, configuration snippets, access notes.
- `bonus/README.md`
  - How to install, access, and demonstrate the GitLab integration.

## Verification

During the defense, you should be able to show:

- GitLab running in the `gitlab` namespace.
- The application in `dev` being updated via changes pushed to GitLab.
- That the mandatory Part 3 functionality remains intact.

## Evaluation note

The bonus is only evaluated if the mandatory parts (p1, p2, p3) are fully completed and working without issues. If any mandatory requirement is missing or broken, the bonus will not be assessed.
