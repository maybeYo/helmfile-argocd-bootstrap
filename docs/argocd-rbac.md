# Argo CD users, projects and RBAC

Three layers, all in Git:

1. **Accounts** (`configs.cm.accounts.*`) in `helmfile/values/common/argocd.yaml.gotmpl`.
2. **Passwords** (`configs.secret.extra.accounts.<name>.password`) in the
   SOPS-encrypted `helmfile/secrets/<env>/argocd.yaml`.
3. **Roles and bindings**: global `policy.csv` in the Argo CD values, and
   per-project roles in `argocd/values/common/platform/argocd-projects.yaml`.

## Accounts

```yaml
configs:
  cm:
    accounts.apps-admin: apiKey, login
```

Generate a password hash and put it in the secrets file:

```bash
argocd account bcrypt --password 'change-me'
```

```yaml
configs:
  secret:
    extra:
      accounts.apps-admin.password: "$2a$10$..."
```

## Deny by default

```yaml
configs:
  rbac:
    policy.default: ""
```

With an empty default, a logged-in user sees nothing until a `g` line grants a
role. This avoids the common "everyone is read-only on everything" footgun.

## Project-scoped roles

The shipped example scopes three roles to AppProject `apps`:

| Account         | Can                                           |
| --------------- | --------------------------------------------- |
| `apps-readonly` | view Applications and logs in `apps`          |
| `apps-sync`     | readonly + trigger sync                       |
| `apps-admin`    | full control of Applications in `apps`, exec  |
| `platform-admin`| everything (`role:admin`)                     |

Policy lines follow `p, <subject>, <resource>, <action>, <project>/<app>, allow`.
Scoping the object to `apps/*` is what keeps a role inside one project.

The same roles are also declared on the AppProject itself (`roles:` in
`argocd-projects.yaml`) with `groups:` bound to the account names. Either layer
alone works; keeping both makes `argocd proj role` tooling and the UI agree.

## Projects

`argocd-projects` (chart `argocd-apps`) creates:

- `platform`: cluster-scoped resources allowed. For add-ons.
- `apps`: namespaced resources only, plus `Namespace` so `CreateNamespace=true`
  works. For workloads.

`projects` in that chart is a **map** keyed by project name, not a list. A list
renders a YAML parse error.

## SSO

Replace local accounts with Dex or OIDC (`configs.cm.dex.config` /
`configs.cm.oidc.config`) and bind groups instead of accounts in `policy.csv`:

```text
g, my-github-org:platform-team, role:admin
```
