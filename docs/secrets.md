# Secrets with SOPS

Two places hold encrypted data, for two different consumers:

| Path                       | Decrypted by                                   | Used for                                                  |
| -------------------------- | ---------------------------------------------- | --------------------------------------------------------- |
| `helmfile/secrets/<env>/`  | your machine, via the `helm-secrets` plugin    | Argo CD bootstrap: account passwords, private repo creds  |
| `argocd/secrets/<env>/`    | Argo CD repo-server, via `helm-secrets` + SOPS | values for Applications (Grafana password, API keys, ...) |

Encrypted files are committed. Plaintext never is; `scripts/check-sops-encrypted.sh`
(run by CI and pre-commit) fails on any unencrypted YAML under a `secrets/` directory.
`*.example` files are plaintext templates with placeholders.

## 1. Pick a backend

### age (default, no cloud dependency)

```bash
age-keygen -o key.txt            # prints: Public key: age1...
export SOPS_AGE_KEY_FILE=$PWD/key.txt
```

Put the public key into both `.sops.yaml` files:

```yaml
creation_rules:
  - path_regex: .*
    age: age1yourpublickey...
```

Give repo-server the private key so Argo CD can decrypt:

```bash
kubectl -n argocd create secret generic helm-secrets-age-key --from-file=key.txt=key.txt
kubectl -n argocd rollout restart deploy/argocd-repo-server
```

The Secret is mounted as `optional`, so repo-server starts without it; decryption
simply fails until the key exists. Set `secrets.backend: age` in
`helmfile/environments/<env>.yaml` (the default).

### AWS KMS (EKS)

Set `secrets.backend: kms` and `aws.repoServerRoleArn` in the environment file,
switch `.sops.yaml` to the `kms:` rule, and grant the IRSA role `kms:Decrypt`.
Details in [aws-eks.md](aws-eks.md).

## 2. Local tooling

```bash
helm plugin install https://github.com/jkroepke/helm-secrets
brew install sops age     # or download releases
```

## 3. Bootstrap secrets (helmfile)

```bash
cd helmfile/secrets
cp example-dev/argocd.yaml.example example-dev/argocd.yaml
$EDITOR example-dev/argocd.yaml      # fill in bcrypt hashes, repo credentials
sops -e -i example-dev/argocd.yaml   # or: helm secrets encrypt ...
```

Then set `secrets.enabled: true` in `helmfile/environments/example-dev.yaml`.
Helmfile decrypts the file during `apply` and merges it into the Argo CD values.

Edit later with `sops example-dev/argocd.yaml` (or `helm secrets edit`).

## 4. Application secrets (Argo CD)

```bash
cd argocd/secrets
cp example-dev/platform/kube-prometheus-stack.yaml.example example-dev/platform/kube-prometheus-stack.yaml
$EDITOR example-dev/platform/kube-prometheus-stack.yaml
sops -e -i example-dev/platform/kube-prometheus-stack.yaml
```

Reference it from the Application definition like any other values file:

```yaml
valueFiles:
  - argocd/values/common/platform/kube-prometheus-stack.yaml
  - argocd/secrets/example-dev/platform/kube-prometheus-stack.yaml
```

No `secrets://` prefix. The helm-secrets wrapper installed in repo-server
(`HELM_SECRETS_WRAPPER_ENABLED=true`) detects SOPS metadata and decrypts
transparently. A `secrets://` prefix, if present, is stripped by the root
ApplicationSet because it conflicts with the `$values/` multi-source reference.

## How repo-server gets the tools

`helmfile/values/common/argocd.yaml.gotmpl` adds an init container that downloads
pinned versions of `helm-secrets`, `sops`, `age`, `vals` and `kubectl` into an
`emptyDir`, and mounts the helm-secrets wrapper over `helm` on `PATH`. Versions are
plain env vars at the top of the init container; Renovate keeps them current.

## Private GitOps repository

If the repo Argo CD reads from is private, add credentials to the bootstrap
secrets file (`configs.repositories`, GitHub App or deploy key). The example
template shows the GitHub App shape. See
[Argo CD: Private Repositories](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/).
