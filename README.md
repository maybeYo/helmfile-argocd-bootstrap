# helmfile-argocd-bootstrap

[![CI](https://github.com/maybeYo/helmfile-argocd-bootstrap/actions/workflows/ci.yaml/badge.svg)](https://github.com/maybeYo/helmfile-argocd-bootstrap/actions/workflows/ci.yaml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

A small, opinionated GitOps starter: **Helmfile installs Argo CD once**, then
**Argo CD deploys everything else from this repository**. Adding a component is
one YAML file. Secrets are SOPS-encrypted and decrypted inside Argo CD.

[中文说明](README.zh-CN.md)

## How it works

```text
helmfile -e <env> apply ─┐
                         ├─▶ Argo CD  +  root ApplicationSet
                         │              │
                         │              │ scans argocd/environments/<env>/*/*.yaml
                         │              ▼
git push ────────────────┴─▶ one Argo CD Application per file
                                (Helm repo chart, OCI chart, or chart dir in git)
```

1. **Bootstrap** (once per cluster): Helmfile installs `argo-cd` and `argocd-apps`.
   The latter carries a single *root* ApplicationSet whose git generator points at
   this repo and environment.
2. **Everything else is Git**: drop `argocd/environments/<env>/<group>/<name>.yaml`
   describing a chart and its values files. Argo CD creates and syncs the
   Application. New groups (`platform/`, `apps/`, `ci/`, `aws/`, ...) need no
   configuration.
3. **Secrets**: values under `secrets/` are SOPS-encrypted (age by default, AWS KMS
   optional). Repo-server carries `helm-secrets`, so encrypted values files are
   referenced like any other.

## Quickstart on kind

Requirements: `kubectl`, `helm`, `helmfile`, `kind`, and the
[helm-diff](https://github.com/databus23/helm-diff) plugin.

```bash
git clone https://github.com/maybeYo/helmfile-argocd-bootstrap.git
cd helmfile-argocd-bootstrap

kind create cluster                        # context: kind-kind
make bootstrap ENV=local-kind              # argocd, then argocd-apps

kubectl -n argocd get applications         # argocd-projects, cert-manager, monitoring, hello
make argocd-password
make argocd-ui                             # http://localhost:8080, user admin
```

The `local-kind` environment deploys cert-manager, the Prometheus Operator CRDs,
kube-prometheus-stack and a demo workload from `charts/generic-app`.

> Forked the repo? Change `gitops.repoURL` in `helmfile/environments/<env>.yaml`
> before bootstrapping; that is the URL Argo CD pulls from.

## Repository layout

```text
helmfile/                         bootstrap only
├── helmfile.yaml.gotmpl          environments + 2 releases (argocd, argocd-apps)
├── environments/<env>.yaml       repo URL, secrets backend, cloud flags
├── values/common/                argocd.yaml.gotmpl, argocd-apps.yaml (root ApplicationSet)
├── values/<env>/argocd.yaml      per-environment Argo CD overrides
└── secrets/<env>/argocd.yaml     SOPS: account passwords, private repo creds

argocd/                           day-2: everything Argo CD deploys
├── environments/<env>/<group>/   one file = one Application  (see docs/application-definition.md)
├── values/common/<group>/        shared Helm values
├── values/<env>/<group>/         per-environment overrides
└── secrets/<env>/<group>/        SOPS-encrypted values, decrypted in repo-server

charts/                           in-repo charts, referenced with chartPath
├── generic-app/                  Deployment/Service/Ingress/HPA/ConfigMap/Secret for any HTTP service
├── image-pull-secrets/           dockerconfigjson Secrets from a (SOPS) values file
└── arc-runner-rbac/              RBAC for GitHub Actions runners

docs/                             secrets, RBAC, EKS, ARC, application reference
```

## Adding a component

```yaml
# argocd/environments/local-kind/platform/external-dns.yaml
app: external-dns
namespace: external-dns
project: platform

repoURL: https://kubernetes-sigs.github.io/external-dns/
chart: external-dns
targetRevision: 1.15.0

autoSync: true
valueFiles:
  - argocd/values/common/platform/external-dns.yaml
```

Commit, push, done. Full field list: [docs/application-definition.md](docs/application-definition.md).

For your own services use the in-repo chart:

```yaml
app: my-api
namespace: my-api
project: apps
chartPath: charts/generic-app
autoSync: true
valueFiles:
  - argocd/values/local-kind/apps/my-api.yaml
```

## Environments

| Environment    | Purpose                      | Secrets          | Extras                                    |
| -------------- | ---------------------------- | ---------------- | ----------------------------------------- |
| `local-kind`   | laptop quickstart            | off              | cert-manager, monitoring, demo app        |
| `example-dev`  | shared non-prod cluster      | SOPS + age       | + ingress-nginx, GitHub Actions runners   |
| `example-prod` | EKS                          | SOPS + AWS KMS   | + AWS Load Balancer Controller, Karpenter |

Add one by creating `helmfile/environments/<env>.yaml`, registering it under
`environments:` in `helmfile.yaml.gotmpl`, and populating `argocd/environments/<env>/`.

## Secrets

See [docs/secrets.md](docs/secrets.md). Short version:

```bash
age-keygen -o key.txt                               # put the public key into both .sops.yaml files
kubectl -n argocd create secret generic helm-secrets-age-key --from-file=key.txt
cp helmfile/secrets/example-dev/argocd.yaml.example helmfile/secrets/example-dev/argocd.yaml
sops -e -i helmfile/secrets/example-dev/argocd.yaml
```

CI and pre-commit refuse unencrypted YAML under any `secrets/` directory.

## Make targets

```text
make bootstrap ENV=<env>   install argocd + root ApplicationSet into the current cluster
make template  ENV=<env>   render the bootstrap releases without a cluster
make lint                  helm lint, yamllint, secrets encryption check
make argocd-password       print the initial admin password
make argocd-ui             port-forward the UI to :8080
```

## Troubleshooting

| Symptom                                           | Cause / fix                                                                              |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Application never appears                         | file pushed? path matches `environments/<env>/*/*.yaml`? Argo CD can reach the repo?    |
| `Add the .gotmpl file extension`                  | helmfile needs `helmfile.yaml.gotmpl` for templating                                     |
| AppProject chart fails to parse                   | `projects` must be a map keyed by name, not a list                                       |
| CRD `metadata.annotations: Too long`              | needs Server-Side Apply; the root ApplicationSet enables it, check for an override       |
| OCI chart `not found`                             | `repoURL` without `oci://`, and the registry must be in Argo CD `configs.repositories`   |
| encrypted values not decrypting in Argo CD        | `helm-secrets-age-key` Secret missing, or IRSA role lacks `kms:Decrypt`; check repo-server logs |
| `argocd-apps` Server-Side Apply conflict          | `kubectl -n argocd delete applicationset root` then re-apply `argocd-apps`              |

## Charts

Charts in `charts/` are published to GHCR on every version bump:

```bash
helm pull oci://ghcr.io/maybeyo/charts/generic-app --version 0.1.0
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache License 2.0. See [LICENSE](LICENSE).
