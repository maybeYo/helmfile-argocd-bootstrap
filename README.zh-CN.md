# helmfile-argocd-bootstrap

一个小而完整的 GitOps 起步模板：**Helmfile 只负责装一次 Argo CD**，之后**所有组件都由 Argo CD 从本仓库部署**。加一个组件就是加一个 YAML 文件。密钥用 SOPS 加密，在 Argo CD 内部解密。

[English](README.md)

## 工作方式

```text
helmfile -e <env> apply ─┐
                         ├─▶ Argo CD + 根 ApplicationSet
                         │              │
                         │              │ 扫描 argocd/environments/<env>/*/*.yaml
                         │              ▼
git push ────────────────┴─▶ 每个文件一个 Argo CD Application
                                (Helm 仓库 chart、OCI chart 或 git 里的 chart 目录)
```

1. **Bootstrap**（每个集群一次）：Helmfile 安装 `argo-cd` 和 `argocd-apps`，后者只包含一个根 ApplicationSet，其 git generator 指向本仓库和当前环境。
2. **之后全靠 Git**：在 `argocd/environments/<env>/<分组>/<名字>.yaml` 写明 chart 和 values 文件，Argo CD 自动创建并同步 Application。新增分组目录（`platform/`、`apps/`、`ci/`、`aws/`……）不需要改任何配置。
3. **密钥**：`secrets/` 下的 values 用 SOPS 加密（默认 age，可选 AWS KMS）。repo-server 内置 `helm-secrets`，加密文件和普通 values 一样引用即可。

## 在 kind 上快速开始

需要 `kubectl`、`helm`、`helmfile`、`kind` 和 [helm-diff](https://github.com/databus23/helm-diff) 插件。

```bash
git clone https://github.com/maybeYo/helmfile-argocd-bootstrap.git
cd helmfile-argocd-bootstrap

kind create cluster                        # context: kind-kind
make bootstrap ENV=local-kind              # 先 argocd，再 argocd-apps

kubectl -n argocd get applications         # argocd-projects, cert-manager, monitoring, hello
make argocd-password
make argocd-ui                             # http://localhost:8080，用户 admin
```

`local-kind` 环境会部署 cert-manager、Prometheus Operator CRDs、kube-prometheus-stack，以及一个基于 `charts/generic-app` 的示例应用。

> Fork 之后请先改 `helmfile/environments/<env>.yaml` 里的 `gitops.repoURL`，Argo CD 从这个地址拉取定义。

## 目录结构

```text
helmfile/                         只做 bootstrap
├── helmfile.yaml.gotmpl          环境声明 + 两个 release（argocd、argocd-apps）
├── environments/<env>.yaml       仓库地址、密钥后端、云厂商开关
├── values/common/                argocd.yaml.gotmpl、argocd-apps.yaml（根 ApplicationSet）
├── values/<env>/argocd.yaml      各环境 Argo CD 覆盖
└── secrets/<env>/argocd.yaml     SOPS：账号密码、私有仓库凭证

argocd/                           日常：Argo CD 部署的一切
├── environments/<env>/<分组>/    一个文件 = 一个 Application（见 docs/application-definition.md）
├── values/common/<分组>/         共用 Helm values
├── values/<env>/<分组>/          各环境覆盖
└── secrets/<env>/<分组>/         SOPS 加密 values，在 repo-server 解密

charts/                           仓库内 chart，用 chartPath 引用
├── generic-app/                  任意 HTTP 服务的 Deployment/Service/Ingress/HPA/ConfigMap/Secret
├── image-pull-secrets/           从（SOPS）values 生成 dockerconfigjson Secret
└── arc-runner-rbac/              GitHub Actions runner 的 RBAC

docs/                             密钥、RBAC、EKS、ARC、Application 字段参考
```

## 加一个组件

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

提交推送即可。完整字段见 [docs/application-definition.md](docs/application-definition.md)。

自己的服务用仓库内 chart：

```yaml
app: my-api
namespace: my-api
project: apps
chartPath: charts/generic-app
autoSync: true
valueFiles:
  - argocd/values/local-kind/apps/my-api.yaml
```

## 环境

| 环境           | 用途           | 密钥           | 额外组件                                  |
| -------------- | -------------- | -------------- | ----------------------------------------- |
| `local-kind`   | 本机快速体验   | 关闭           | cert-manager、监控、示例应用              |
| `example-dev`  | 共享非生产集群 | SOPS + age     | + ingress-nginx、GitHub Actions runner    |
| `example-prod` | EKS            | SOPS + AWS KMS | + AWS Load Balancer Controller、Karpenter |

新增环境：创建 `helmfile/environments/<env>.yaml`，在 `helmfile.yaml.gotmpl` 的 `environments:` 下注册，再填充 `argocd/environments/<env>/`。

## 密钥

详见 [docs/secrets.md](docs/secrets.md)。最短路径：

```bash
age-keygen -o key.txt                               # 公钥填入两个 .sops.yaml
kubectl -n argocd create secret generic helm-secrets-age-key --from-file=key.txt
cp helmfile/secrets/example-dev/argocd.yaml.example helmfile/secrets/example-dev/argocd.yaml
sops -e -i helmfile/secrets/example-dev/argocd.yaml
```

CI 和 pre-commit 会拒绝任何 `secrets/` 目录下未加密的 YAML。

## 排障

| 现象                                 | 原因 / 处理                                                                           |
| ------------------------------------ | ------------------------------------------------------------------------------------- |
| Application 不出现                   | 推送了吗？路径符合 `environments/<env>/*/*.yaml`？Argo CD 能访问仓库？                |
| `Add the .gotmpl file extension`     | helmfile 模板必须叫 `helmfile.yaml.gotmpl`                                            |
| AppProject chart 解析失败            | `projects` 必须是按名字为 key 的 map，不是 list                                       |
| CRD `metadata.annotations: Too long` | 需要 Server-Side Apply；根 ApplicationSet 默认已开，检查是否被覆盖                    |
| OCI chart `not found`                | `repoURL` 不带 `oci://`，且 registry 要在 Argo CD `configs.repositories` 中声明       |
| 加密 values 在 Argo CD 里不解密      | 缺 `helm-secrets-age-key` Secret，或 IRSA 角色没有 `kms:Decrypt`；看 repo-server 日志 |
| `argocd-apps` Server-Side Apply 冲突 | `kubectl -n argocd delete applicationset root` 后重新 apply `argocd-apps`             |

## 许可

Apache License 2.0，见 [LICENSE](LICENSE)。
