# Running on EKS

`example-prod` shows the AWS-specific pieces. Everything else is cloud-neutral.

## Add-ons via Argo CD

| Application                    | Chart                                   | Notes                                                   |
| ------------------------------ | --------------------------------------- | ------------------------------------------------------- |
| `aws-load-balancer-controller` | `aws/aws-load-balancer-controller`      | needs IRSA role with the ALB controller IAM policy      |
| `karpenter`                    | `public.ecr.aws/karpenter/karpenter`    | OCI chart; `repoURL` without `oci://`                   |
| `ingress-nginx`                | `ingress-nginx/ingress-nginx`           | NLB annotations in `argocd/values/example-prod/platform` |

Replace `<CLUSTER_NAME>`, `<ACCOUNT_ID>`, `<AWS_REGION>`, `<VPC_ID>` in
`argocd/values/common/aws/*.yaml`. NodePools and EC2NodeClasses are not included;
add them as their own Application (a small chart under `charts/` works well).

## OCI charts in Argo CD

Argo CD needs the registry declared before it can pull OCI charts, even public
ones. `helmfile/values/common/argocd.yaml.gotmpl` registers
`public.ecr.aws/karpenter` and `ghcr.io/actions/actions-runner-controller-charts`
under `configs.repositories` with `enableOCI: "true"`. Add more there.

## SOPS with KMS

1. Create a KMS key. Grant `kms:Encrypt`/`kms:Decrypt` to the humans who edit
   secrets and `kms:Decrypt` to the Argo CD repo-server role.
2. Point both `.sops.yaml` files at it:

   ```yaml
   creation_rules:
     - path_regex: .*
       kms: arn:aws:kms:<region>:<account-id>:key/<key-id>
   ```

3. In `helmfile/environments/example-prod.yaml`:

   ```yaml
   secrets:
     enabled: true
     backend: kms
   aws:
     enabled: true
     region: <region>
     repoServerRoleArn: arn:aws:iam::<account-id>:role/<cluster>-argocd-repo-server
   ```

   The role ARN becomes the `eks.amazonaws.com/role-arn` annotation on the
   repo-server ServiceAccount and `AWS_REGION` is set for the SOPS binary.

### IRSA role (Terraform sketch)

```hcl
module "argocd_repo_server_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-argocd-repo-server"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["argocd:argocd-repo-server"]
    }
  }

  role_policy_arns = {
    kms = aws_iam_policy.sops_decrypt.arn   # kms:Decrypt on the SOPS key
  }
}

module "sops_kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 3.0"

  description             = "SOPS key for helm-secrets"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  enable_default_policy   = false

  key_administrators = [var.platform_admin_role_arn]
  key_users          = [var.platform_admin_role_arn, module.argocd_repo_server_irsa.iam_role_arn]
  aliases            = ["sops/argocd"]
}
```

Pin a static role ARN if you hit a dependency cycle between the IRSA policy and
the key policy.

## Verifying

```bash
kubectl -n argocd get sa argocd-repo-server -o jsonpath='{.metadata.annotations}'
kubectl -n argocd exec deploy/argocd-repo-server -c argocd-repo-server -- \
  sh -c 'cd /tmp && /gitops-tools/sops --version'
```
