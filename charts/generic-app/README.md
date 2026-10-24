# generic-app

A single chart for "yet another stateless HTTP service". Point it at an image,
set the port, and get a Deployment + Service with sane, mostly-empty defaults.

## What it renders

| Resource     | Enabled by                                   |
| ------------ | -------------------------------------------- |
| Deployment   | always                                       |
| Service      | always                                       |
| ServiceAccount | `serviceAccount.create` (default `true`)   |
| Ingress      | `ingress.enabled`                            |
| HTTPRoute    | `httpRoute.enabled` (Gateway API)            |
| HPA          | `autoscaling.enabled`                        |
| ConfigMap    | `configMap.enabled` (injected via `envFrom`) |
| Secret       | `secret.enabled` (injected via `envFrom`)    |

ConfigMap and Secret changes roll the Deployment through `checksum/*` pod
annotations.

## Required values

`image.tag` has no default. The chart is deliberately app-agnostic, so a
release without a tag fails at render time instead of silently deploying
`latest`.

## Minimal example

```yaml
image:
  repository: nginxinc/nginx-unprivileged
  tag: "1.27"
containerPort: 8080
readinessProbe:
  httpGet:
    path: /
    port: http
```

Probes are empty by default because non-HTTP workloads would crash-loop on an
HTTP probe. Set them per release.

## Secrets

`secret.stringData` is plain text in values. Keep it in a SOPS-encrypted values
file (see `docs/secrets.md` at the repository root) and reference that file
from the Argo CD Application definition, never in a plaintext values file.
