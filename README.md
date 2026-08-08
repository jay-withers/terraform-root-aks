# terraform-root-aks

A private AKS cluster — VNet, NSGs, Key Vault, jump box and Flux — deployed as an
**application landing zone spoke** of the platform in
[`jay-withers/azure-landingzone`](https://github.com/jay-withers/azure-landingzone).

## This is a spoke: apply the landing zone first

This repo does not stand alone. The landing zone's `landingzones` component vends it a
resource group and an identity, and its `connectivity` component owns the hub VNet and
the private DNS zones this cluster links to. In the landing zone repo:

```bash
make apply C=management
make apply C=governance
make apply C=connectivity
make apply C=landingzones
```

Only then does `make apply` here have anywhere to deploy. What that means in practice:

| | Owned by | Notes |
| --- | --- | --- |
| Resource group | landing zone | Looked up, not created — the group *is* the landing zone, and this cluster's identity cannot create resource groups |
| Region | landing zone | Taken from the vended group; there is no `location` variable |
| `privatelink.vaultcore.azure.net` | hub | This creates only its own VNet link, in the hub's resource group |
| Hub VNet | hub | This creates **both** halves of the peering — one side alone stays Initiated |
| Address space | this repo | `10.1.0.0/16`, kept clear of the hub's `10.0.0.0/22`; Azure refuses to peer overlapping ranges |

`workload_name` (default `aks`) must match the landing zone's key in the
`landingzones` component — it derives the resource group name being looked up.

If an apply fails with `AuthorizationFailed`, add a targeted grant in the landing zone
repo rather than widening this identity's scope. The identity holds `Contributor` on
its own resource group, `Role Based Access Control Administrator` there (this cluster
creates its own role assignments), a five-action custom peering role on the hub VNet,
and `Private DNS Zone Contributor` on the specific zones it was granted.

## Getting started

Open the repository in the dev container (VS Code: **Reopen in Container**, or
GitHub Codespaces). The container ships with Terraform, TFLint, terraform-docs,
and Checkov, and runs `make install` on creation to wire up the pre-commit hooks.

Outside a dev container, install the hooks manually:

```bash
make install
```

## Commands

Run `make` (or `make help`) to list the available targets:

```bash
make install   # install pre-commit hooks (run once after cloning)
make lint      # run all pre-commit hooks against every file
make fmt       # terraform fmt -recursive
make validate  # terraform init + validate
make plan      # terraform init + plan
```

Terraform targets run against the `terraform/` directory via `-chdir`. The
Terraform version is pinned in `.terraform-version` (used by tfenv/tenv and CI).

## Testing

There is no `terraform test` suite at present. The checks that do run are
`terraform validate` and the `ci-terraform` **plan** job, plus `ci-gitops` over the
manifest tree. If a `terraform/tests/` directory comes back, re-add a `test` job to
`ci-terraform.yml` and list it in that workflow's gate job.

## Azure auth for `terraform plan`

The `ci-terraform` **plan** job runs `terraform plan` against `terraform/` using
GitHub OIDC (no long-lived secrets), once per environment. It is **skipped until you
set the `AZURE_CLIENT_ID` repository variable**, so the repo stays green until Azure
auth is wired up.

You do not create the identity yourself — the landing zone repo's `landingzones`
component vends it, already federated to this repository and scoped to this cluster's
resource group. To enable the plan job:

1. In the landing zone repo, run `terraform output github_secrets` after applying
   `landingzones`.
2. Add the three values it prints as **repository variables** here (Settings → Secrets
   and variables → Actions → Variables): `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
   `AZURE_SUBSCRIPTION_ID`. None are secret — a client ID is useless without a
   matching federated credential.

Note the plan only succeeds once the landing zone is applied: the resource group, hub
VNet and private DNS zone are all looked up, and a data source for something that does
not exist yet fails at plan time.

## Branch protection

Add a ruleset (or branch protection rule) on `main` requiring these status
checks before merge:

- **ci-pre-commit** — `pre-commit` job
- **ci-terraform** — the `ci-terraform` gate job
- **ci-gitops** — the `ci-gitops` gate job

`ci-terraform` runs `terraform plan` only when a PR touches Terraform
(`terraform/**`, `.terraform-version`, or the workflow), but the `ci-terraform`
gate job always runs and reports, so it is safe to require: a PR with no
Terraform changes still satisfies it. Do **not** require `test`/`plan` directly
— require the `ci-terraform` gate instead. `ci-gitops` works the same way for
`gitops/**`.

## Structure

```text
.devcontainer/
  devcontainer.json    # dev container (ghcr.io/jay-withers/dev-container/terraform)
.terraform-version     # pinned Terraform version (tfenv/tenv + CI)
terraform/              # root config — applied directly, no examples/ (see CLAUDE.md)
  versions.tf          # required_version / required_providers + provider block
  main.tf              # naming module
  main.aks.tf          # the cluster
  main.network.tf      # VNet, NSGs, cluster identity
  main.hub.tf          # both halves of the hub peering
  main.keyvault.tf     # private workload Key Vault
  main.jumpbox.tf      # jump box + Bastion
  main.flux.tf         # microsoft.flux extension + bootstrap configuration
  main.tenants.tf      # tenant workload identities
  variables.tf         # inputs
  outputs.tf           # outputs
  README.md            # generated by terraform-docs
  .tflint.hcl          # TFLint config (terraform ruleset, recommended preset)
  environments/        # dev.tfvars, stg.tfvars, prd.tfvars
gitops/                 # what Flux reconciles — see gitops/README.md
  clusters/<env>/      # bootstrap: the Flux objects that own everything else
  infrastructure/      # cert-manager, Envoy Gateway, kube-prometheus-stack
  tenants/             # per-tenant onboarding (platform) + workloads (tenant)
.pre-commit-config.yaml
commitlint.config.js
.github/
  workflows/
    ci-pre-commit.yml  # lints all files on PRs to main
    ci-terraform.yml   # terraform validate + plan, gated to Terraform changes
    ci-gitops.yml      # kustomize build + kubeconform, gated to gitops changes
    cd-tag.yml         # auto-tags on merge to main (semver patch bump)
renovate.json          # automated dependency updates
Makefile
```
