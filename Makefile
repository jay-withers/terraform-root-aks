TF_DIR := terraform

# Environment selector, defaulting to dev. Always loads a tfvars file: the module
# defaults are production's shape (three zones, three nodes per pool, Standard
# tier), so a run without one quietly turns whatever it touches into a prd-sized
# cluster. `make plan ENV=prd` selects another.
ENV ?= dev
TF_VARS := -var-file=environments/$(ENV).tfvars

ifeq ($(wildcard $(TF_DIR)/environments/$(ENV).tfvars),)
$(error no tfvars for ENV=$(ENV): expected $(TF_DIR)/environments/$(ENV).tfvars)
endif

# Each environment's state lives in its own landing zone's state account, named in
# environments/<env>.tfbackend. init always passes -reconfigure: .terraform/ is
# shared across environments, so without it switching ENV either reuses the last
# environment's backend or stops to offer a state migration nobody wants. Moving
# state between backends is a deliberate `terraform init -migrate-state`, never
# something make does.
TF_BACKEND := -backend-config=environments/$(ENV).tfbackend

.DEFAULT_GOAL := help

.PHONY: help install lint init fmt validate plan apply destroy validate-gitops

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

install: ## Install pre-commit hooks (run once after cloning)
	pre-commit install
	pre-commit install --hook-type commit-msg

lint: ## Run all pre-commit hooks against every file
	pre-commit run --all-files

init: ## terraform init against ENV's remote state (default dev)
	@test -f $(TF_DIR)/environments/$(ENV).tfbackend || { echo "no backend for ENV=$(ENV): expected $(TF_DIR)/environments/$(ENV).tfbackend" >&2; exit 1; }
	terraform -chdir=$(TF_DIR) init -reconfigure $(TF_BACKEND)

fmt: ## terraform fmt -recursive
	terraform -chdir=$(TF_DIR) fmt -recursive

validate: ## terraform init (no backend) + validate — needs no Azure auth, as in CI
	terraform -chdir=$(TF_DIR) init -backend=false
	terraform -chdir=$(TF_DIR) validate

plan: init ## terraform init + plan (ENV=dev|stg|prd, default dev)
	terraform -chdir=$(TF_DIR) plan $(TF_VARS)

apply: init ## terraform init + apply (ENV=dev|stg|prd, default dev)
	terraform -chdir=$(TF_DIR) apply $(TF_VARS)

destroy: init ## terraform init + destroy (ENV=dev|stg|prd, default dev)
	terraform -chdir=$(TF_DIR) destroy $(TF_VARS)

validate-gitops: ## kustomize build + kubeconform over gitops/ (skips if the tools are absent)
	./scripts/validate-gitops.sh
