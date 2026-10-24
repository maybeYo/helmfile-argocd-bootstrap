# image-pull-secrets

Creates `kubernetes.io/dockerconfigjson` Secrets for `imagePullSecrets`.

```yaml
registries:
  ghcr-pull:                      # Secret name
    - url: https://ghcr.io
      username: my-user
      password: ghp_xxx
```

Install the chart once per namespace that needs to pull private images, and
keep the values file SOPS-encrypted (see `docs/secrets.md`).

Reference from a workload:

```yaml
imagePullSecrets:
  - name: ghcr-pull
```
