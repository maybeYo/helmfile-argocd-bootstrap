# Contributing

Thanks for taking the time. This repository is a template; changes should keep
it generic, small and runnable on a laptop.

## Local checks

```bash
make lint          # helm lint, yamllint, secrets/ encryption check
make template      # render the bootstrap releases (ENV=local-kind by default)
pre-commit install # optional: run the same checks on every commit
```

## Conventions

- **Helmfile only bootstraps.** New components go under
  `argocd/environments/<env>/<group>/`, never as new helmfile releases.
- **Values live next to the environment.** Shared values in
  `argocd/values/common/<group>/`, overrides in `argocd/values/<env>/<group>/`.
- **Charts are versioned.** Bump `version` in `Chart.yaml` for any change under
  `charts/<chart>/`; the *Release charts* workflow can publish them to GHCR on demand.
- **Nothing company-specific.** Use `example.com`, `<ACCOUNT_ID>`-style
  placeholders and generic names. CI runs gitleaks on every push.
- **Secrets are encrypted or they are templates.** Any YAML under a `secrets/`
  directory must be SOPS-encrypted, except `*.example` files, which must contain
  placeholders only.

## Pull requests

Keep PRs focused. Explain *why* in the description; the diff already says what.
