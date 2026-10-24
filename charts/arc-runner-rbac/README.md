# arc-runner-rbac

Minimal RBAC for ARC runners that run `helm` / `kubectl` against the cluster
they live in.

- `serviceAccounts`: get/list on secrets, namespaces, nodes, services cluster-wide.
- `namespaceRoles`: per-namespace `admin` RoleBinding (optionally creating the namespace).

ARC's default runner ServiceAccount is `<scale-set-release>-gha-rs-no-permission`.
