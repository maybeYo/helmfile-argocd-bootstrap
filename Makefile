# Common tasks. ENV selects the helmfile environment (see helmfile/environments/).
ENV ?= local-kind
HELMFILE := helmfile -f helmfile/helmfile.yaml.gotmpl -e $(ENV)
CHARTS := $(wildcard charts/*)

.PHONY: help lint lint-charts lint-yaml template diff bootstrap kind-up kind-down argocd-password argocd-ui check-secrets

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

lint: lint-charts lint-yaml check-secrets ## Run all linters

lint-charts: ## helm lint every chart in charts/
	@for c in $(CHARTS); do echo "== $$c"; helm lint "$$c" --set image.tag=lint || exit 1; done

lint-yaml: ## yamllint the repository
	yamllint -c .yamllint.yaml .

check-secrets: ## Verify files under secrets/ are SOPS-encrypted
	scripts/check-sops-encrypted.sh

template: ## Render the bootstrap releases for ENV without a cluster
	$(HELMFILE) template --state-values-set secrets.enabled=false

diff: ## helmfile diff for ENV (needs helm-diff plugin)
	$(HELMFILE) diff

bootstrap: ## Install Argo CD + root ApplicationSet into the current cluster
	$(HELMFILE) apply -l name=argocd
	$(HELMFILE) apply -l name=argocd-apps

kind-up: ## Create a local kind cluster (context kind-kind)
	kind create cluster

kind-down: ## Delete the local kind cluster
	kind delete cluster

argocd-password: ## Print the initial admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

argocd-ui: ## Port-forward the Argo CD UI to http://localhost:8080
	kubectl -n argocd port-forward svc/argocd-server 8080:80
