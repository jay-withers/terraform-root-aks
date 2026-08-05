TF_DIR := terraform

# Optional environment selector. `make plan ENV=dev` loads
# environments/dev.tfvars; with no ENV set, the module defaults apply.
ifdef ENV
TF_VARS := -var-file=environments/$(ENV).tfvars
endif

# CHECKS has no default here (unlike BRANCH) - it must stay unset/empty so that
# the recipe below passes an empty string through to protect-branch.sh, which
# supplies its own (newline-separated) default. A Make variable can't hold that
# default itself: GNU Make invokes a separate shell per recipe line, splitting on
# any raw newline in an expanded value - even one inside a quoted shell string -
# which would break the quoting in the recipe below.
BRANCH ?= main

.DEFAULT_GOAL := help

.PHONY: help install protect-branch lint init fmt validate plan apply destroy test

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

install: ## Install pre-commit hooks (run once after cloning)
	pre-commit install
	pre-commit install --hook-type commit-msg

protect-branch: ## Configure GitHub repo settings (auto-merge, branch protection) via gh CLI - override BRANCH/CHECKS if your repo's checks differ
	./scripts/protect-branch.sh "$(BRANCH)" "$(CHECKS)"

lint: ## Run all pre-commit hooks against every file
	pre-commit run --all-files

init: ## terraform init
	terraform -chdir=$(TF_DIR) init

fmt: ## terraform fmt -recursive
	terraform -chdir=$(TF_DIR) fmt -recursive

validate: init ## terraform init + validate
	terraform -chdir=$(TF_DIR) validate

plan: init ## terraform init + plan (set ENV=dev|stg|prd to load a tfvars file)
	terraform -chdir=$(TF_DIR) plan $(TF_VARS)

apply: init ## terraform init + apply (set ENV=dev|stg|prd to load a tfvars file)
	terraform -chdir=$(TF_DIR) apply $(TF_VARS)

destroy: init ## terraform init + destroy (set ENV=dev|stg|prd to load a tfvars file)
	terraform -chdir=$(TF_DIR) destroy $(TF_VARS)

test: init ## terraform test (mocked providers — no Azure auth)
	terraform -chdir=$(TF_DIR) test
