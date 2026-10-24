# Self-hosted GitHub Actions runners (ARC)

`example-dev` deploys
[Actions Runner Controller](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/get-started)
through Argo CD:

| Application       | Chart                                 | Namespace     |
| ----------------- | ------------------------------------- | ------------- |
| `arc-controller`  | `gha-runner-scale-set-controller`     | `arc-systems` |
| `arc-runner-set`  | `gha-runner-scale-set`                | `arc-runners` |
| `arc-runner-rbac` | `charts/arc-runner-rbac` (this repo)  | `arc-runners` |

Workflows target the runner set by its Application name:

```yaml
jobs:
  deploy:
    runs-on: arc-runner-set
```

## Credentials

Set `githubConfigUrl` in `argocd/values/common/ci/arc-runner-set.yaml` to your
repository, organisation or enterprise URL. Then provide credentials one of two ways.

**Pre-created Secret** (default in the example):

```bash
kubectl -n arc-runners create secret generic arc-github-config \
  --from-literal=github_token='ghp_...'
```

**SOPS-encrypted values file**, referenced from the Application:

```yaml
# argocd/secrets/example-dev/ci/arc-runner-set.yaml (encrypted)
githubConfigSecret:
  github_app_id: "123456"
  github_app_installation_id: "654321"
  github_app_private_key: |
    -----BEGIN RSA PRIVATE KEY-----
    ...
```

A PAT needs `repo` (and `admin:org` for org-level runners). A GitHub App is the
better long-term option. IDs must be strings.

## RBAC for deploy jobs

ARC's default runner ServiceAccount is `<runner-set>-gha-rs-no-permission` and,
as the name says, can do nothing in the cluster. `charts/arc-runner-rbac` adds:

- cluster-wide `get`/`list` on secrets, namespaces, nodes and services, which is
  what `helm list -A` needs;
- optional `namespaceRoles`, binding the built-in `admin` ClusterRole inside
  specific namespaces so a runner can `helm upgrade` there and nowhere else.

## Ordering

`arc-runner-set` needs the CRDs from `arc-controller`. With `autoSync` on both,
Argo CD retries the runner set until the controller is healthy. If you prefer
explicit ordering, give the two Applications different `argocd.argoproj.io/sync-wave`
values via a small patch, or sync them manually once.
