# Contributing Guide

Standards for working on the **Inception-of-Things** project as a team.

---

## Project ownership

| Part | Scope | Primary owner |
| --- | --- | --- |
| `p1` | Vagrant, two-node K3s cluster, server/agent provisioning | `luis-fif` |
| `p2` | Single-node K3s, three applications, Services, Ingress | `brunmart` |
| `p3` | Docker, K3d, ArgoCD, GitOps, `dev` namespace | `viceda-s` |
| `bonus` | Local GitLab integration in the `gitlab` namespace | Shared |
| `docs` | Architecture, setup, validation and defense documentation | Shared; each owner maintains their part |

Ownership is also encoded in [`.github/CODEOWNERS`](.github/CODEOWNERS), so GitHub automatically requests
the right reviewer when a pull request touches a given path.

---

## Branch strategy

This project uses **[GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow)**:
`main` is always releasable, and all work happens on short-lived branches merged back into it through
reviewed pull requests. There is no long-lived integration branch.

```text
main                 ← always deployable; protected, no direct push
  └── feat/...       ← implementation branches
  └── fix/...        ← bug-fix branches
  └── docs/...       ← documentation-only branches
  └── chore/...      ← maintenance or repository work
```

### Rules

- Branch from the latest `main`.
- Open a pull request as soon as work starts (draft PRs are welcome) to keep changes visible.
- Keep branches short-lived: one issue-focused unit of work per branch and per pull request.
- Rebase or merge the latest `main` into your branch before requesting final review.
- Delete the branch after merge (GitHub does this automatically if enabled in repo settings).
- `main` is a protected branch: no direct pushes, pull requests required, checks must pass, at least
  one approval required. Configure this under **Settings → Branches → Branch protection rules**.
- Tag milestone states on `main` for defense/rollback purposes, e.g. `p1-ready`, `p2-ready`, `p3-ready`.

### Branch names

Use lowercase words separated with hyphens.

When the work has a GitHub issue, include its number:

```text
<type>/issue-<number>-<short-description>
```

Examples:

```text
feat/issue-12-p1-vagrant-two-node-cluster
feat/issue-18-p2-host-based-ingress
feat/issue-24-p3-argocd-gitops-bootstrap
fix/issue-31-k3s-agent-token-join
chore/issue-4-add-gitignore
```

For work without an issue:

```text
<type>/<short-description>
```

Examples:

```text
docs/update-architecture
chore/repository-layout
```

Allowed types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`.

---

## Commit messages

This project follows **[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)**.
The format is machine-parseable, so it stays compatible with tools like `commitlint` or
`semantic-release` if the project ever adopts them.

```text
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Rules

- `type` is one of: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.
- `scope` is the affected part in parentheses: `p1`, `p2`, `p3`, `bonus`, `docs`, `repo`.
- `description` is imperative, present tense, lowercase, no trailing period: `add`, not `added` or `adds`.
- Keep the summary line to 72 characters or fewer.
- Use the body only to explain **why**, not what (the diff already shows what).
- A breaking change is marked with `!` after the type/scope, or a `BREAKING CHANGE:` footer,
  and explains the impact and migration in the body.
- Reference the related issue in the footer when relevant: `Refs #12`.
- Keep commits small and focused; avoid unrelated formatting or generated files in the same commit.

### Examples

```text
feat(p1): add Vagrant two-node cluster
feat(p2): add host-based ingress routes
feat(p3): configure ArgoCD application sync
fix(p1): use server token when joining worker
fix(p2): configure default ingress backend
docs(p3): add v1 to v2 GitOps validation steps
chore(repo): add Kubernetes ignore rules
test(p2): verify app2 replica count

fix(p3)!: require explicit target namespace on ArgoCD Application

BREAKING CHANGE: applications without spec.destination.namespace
will no longer sync; set it explicitly to `dev`.

Refs #24
```

---

## Issues and project board

Use the GitHub Project board lifecycle:

```text
Backlog → Todo → In Progress → Done
```

| Status | Meaning |
| --- | --- |
| Backlog | Captured work that is not yet prioritized or ready to begin |
| Todo | Defined, prioritized work that can be started without blockers |
| In Progress | Work actively being implemented or validated |
| Done | Implemented, tested, documented, merged, and closed |

### Workflow rules

- Create an issue before starting meaningful work, using the templates in
  [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE) (`bug_report.md` or `task.md`).
- New issues enter **Backlog**.
- Move an issue to **Todo** when the team agrees it is ready.
- Move it to **In Progress** when implementation starts.
- Reference the issue number in the branch name.
- Link the pull request to the issue with a closing keyword recognized by GitHub:

```markdown
Closes #12
```

`Fixes #12` and `Resolves #12` work the same way. Since all work PRs merge into `main` (the default
branch), merging automatically closes the linked issue; move it to **Done** on the board at that point.

---

## Pull requests

Every change to `main` goes through a pull request using the template at
[`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md), which GitHub pre-fills
automatically when you open a PR.

**Required before merging:**

- [ ] The branch is up to date with `main`, or merge conflicts are resolved.
- [ ] At least one teammate approved the pull request (CODEOWNERS reviewer, when applicable).
- [ ] No review comments or requested changes remain unresolved.
- [ ] Relevant validation commands passed (see below) and are recorded in the PR description.
- [ ] Documentation is updated if setup, architecture, commands, or expected behavior changed.
- [ ] No secrets, kubeconfig files, Vagrant state, credentials, or generated artifacts are included.
- [ ] Commit messages follow Conventional Commits.

Prefer **squash merging** into `main` so each merged PR corresponds to one clean commit on the
mainline history; the squash commit message should itself follow Conventional Commits.

---

## Repository conventions

The required top-level directories are:

```text
p1/
p2/
p3/
bonus/       # optional
docs/
```

Keep the subject-required configuration in the corresponding root-level folder:

- Put Part 1 files in `p1/`.
- Put Part 2 files in `p2/`.
- Put Part 3 files in `p3/`.
- Put optional GitLab files in `bonus/`.
- Put explanations, diagrams, setup notes, and verification procedures in `docs/`.

Recommended local structure within each part:

```text
pX/
├── Vagrantfile        # when required by that part
├── scripts/           # executable installation/provisioning scripts
├── confs/             # configuration files or Helm values
├── k8s/               # Kubernetes manifests, where applicable
└── README.md          # local setup and verification instructions
```

---

## Shell and YAML style

### Shell scripts

- Use Bash consistently: `#!/usr/bin/env bash`.
- Start scripts with strict mode when compatible with the required commands:

  ```bash
  set -euo pipefail
  ```

- Quote shell variables: `"${VARIABLE}"`.
- Use descriptive, lowercase variable names where practical.
- Print clear progress and failure messages.
- Make scripts idempotent where possible: running them twice should not break an already configured environment.
- Do not put passwords, tokens, kubeconfigs, or private keys in scripts or Git.

### YAML manifests

- Use two-space indentation; never use tabs.
- Add labels consistently, especially `app.kubernetes.io/name` and `app.kubernetes.io/part-of` when appropriate.
- Keep one logical resource per file unless resources are inseparable and clearly separated using `---`.
- Use explicit namespaces except where a manifest deliberately creates the namespace.
- Prefer declarative resources over manual cluster changes.

---

## Validation and testing

Run the relevant checks before pushing and record the result in the pull request.

### General checks

```bash
# Inspect changed files
git status
git diff --check

# Validate YAML syntax if yq is available
yq '.' path/to/manifest.yaml
```

### Part 1 validation

```bash
cd p1
vagrant up
vagrant status
vagrant ssh <login>S -c 'sudo kubectl get nodes -o wide'
```

Expected result: the K3s server and agent nodes are both `Ready`.

### Part 2 validation

```bash
cd p2
vagrant up
vagrant ssh <login>S -c 'sudo kubectl get pods -A'

curl -H 'Host: app1.com' http://192.168.56.110
curl -H 'Host: app2.com' http://192.168.56.110
curl -H 'Host: unknown-host.example' http://192.168.56.110
```

Expected result: app1, app2, and the default app respond correctly; app2 has three ready replicas.

### Part 3 validation

```bash
kubectl get namespaces
kubectl get pods -n argocd
kubectl get pods -n dev
kubectl get applications -n argocd
```

Expected result: `argocd` and `dev` exist; ArgoCD is healthy; the application is synchronized and healthy. Validate the GitOps update by changing the image from `v1` to `v2`, committing and pushing, then confirming ArgoCD deploys the new version.

### Bonus validation

```bash
kubectl get namespace gitlab
kubectl get pods -n gitlab
```

Only work on the bonus after `p1`, `p2`, and `p3` are working reliably.

---

## Documentation expectations

Every part must document:

- Prerequisites and supported host assumptions.
- Installation and startup commands.
- How to verify the expected result.
- How to clean up or reset the environment.
- Known limitations or manual steps.

Update the relevant files under `docs/` whenever architecture, networking, Kubernetes resources, GitOps flow, or ownership changes.

---

## Team rhythm

- **Planning:** Review Backlog, prioritize work, assign owners, and move ready items to Todo.
- **During work:** Keep the Project status current and push incremental commits to your branch's PR.
- **Before merging:** Request review, perform validation, and confirm the PR links its GitHub issue.
- **Regular integration:** Rebase onto the latest `main` often to avoid large, risky merges.
- **Before defense:** Rehearse the setup and verification for all mandatory parts; every teammate should be able to explain the complete architecture.
