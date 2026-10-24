# Application definition reference

Every file matched by `argocd/environments/<env>/*/*.yaml` becomes one Argo CD
Application. The directory under `<env>` is free-form (`platform`, `apps`, `ci`,
`aws`, `jobs`, ...); adding a new one needs no change anywhere else.

```yaml
app: kube-prometheus-stack            # Application name (required)
namespace: monitoring                 # destination namespace (required; created automatically)
project: platform                     # AppProject, default "default"

# Chart source: ONE of
repoURL: https://prometheus-community.github.io/helm-charts
chart: kube-prometheus-stack
targetRevision: 87.16.1               # default "*" (latest) for repo charts
# or
chartPath: charts/generic-app         # directory in a git repo
# repoURL: https://github.com/you/other-repo.git   # default: the GitOps repo
# targetRevision: main                            # default: the GitOps revision

autoSync: true                        # automated sync with prune + selfHeal
cascadeDelete: false                  # add the resources finalizer
syncOptions: []                       # appended to ServerSideApply=true, CreateNamespace=true
releaseName: ""                       # Helm release name, default = app
kubeVersion: ""                       # override Capabilities.KubeVersion for picky charts
cluster: ""                           # destination server, default in-cluster

valueFiles:                           # repo-root-relative paths in the GitOps repo
  - argocd/values/common/platform/kube-prometheus-stack.yaml
  - argocd/secrets/example-dev/platform/kube-prometheus-stack.yaml   # SOPS, decrypted in repo-server
valuesInline:                         # becomes helm.valuesObject
  grafana:
    enabled: false
```

## Rules of the road

- **Only Application definitions go under `environments/`.** A stray values file
  there is parsed as an Application and fails validation. Values belong in
  `argocd/values/`, secrets in `argocd/secrets/`.
- **OCI charts**: `repoURL` is the registry path without `oci://`
  (`public.ecr.aws/karpenter`), and the registry must be listed in Argo CD's
  `configs.repositories` with `enableOCI: "true"`.
- **Do not use `path`.** The git files generator already populates `.path` with
  file metadata, which is why the key is `chartPath`.
- **`values` is reserved** by the generator (it carries `repoURL`/`revision`), which
  is why inline values are called `valuesInline`.
- **Large CRDs** (prometheus-operator, Gateway API) need Server-Side Apply, which
  is on for every Application.

## What the root ApplicationSet renders

Two sources, always:

1. the chart (Helm repo, OCI, or git directory);
2. the GitOps repo under `ref: values`, so `valueFiles` resolve as
   `$values/<repo-root-relative path>` regardless of where the chart lives.

The template lives in `helmfile/values/common/argocd-apps.yaml`. Booleans and
lists are emitted from `templatePatch` because the ApplicationSet CRD validates
`template` before Go templating runs.
