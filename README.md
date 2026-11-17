# terraform-root-aks

A private AKS cluster — VNet, NSGs, Key Vault, Loki log storage, jump box and Flux —
deployed as an **application landing zone spoke** of the platform in
[`jay-withers/azure-landingzone`](https://github.com/jay-withers/azure-landingzone).

## This is a spoke: apply the landing zone first

This repo does not stand alone. The landing zone's `landingzones` component vends it a
resource group and an identity, and its `connectivity` component owns the hub VNet and
the private DNS zones this cluster links to. Those components must already be applied
in [`jay-withers/azure-landingzone`](https://github.com/jay-withers/azure-landingzone)
before anything here can deploy — see that repo for its own apply order and commands.

What that means in practice:

| | Owned by | Notes |
| --- | --- | --- |
| Resource group | landing zone | Looked up, not created — the group *is* the landing zone, and this cluster's identity cannot create resource groups |
| Region | landing zone | Taken from the vended group; there is no `location` variable |
| `privatelink.vaultcore.azure.net` | hub | For the workload Key Vault. This creates only its own VNet link, in the hub's resource group |
| `privatelink.blob.core.windows.net` | hub | For Loki's log store. Same as above — only the VNet link is created here |
| Hub VNet | hub | This creates **both** halves of the peering — one side alone stays Initiated |
| Address space | this repo | `10.1.0.0/16`, kept clear of the hub's `10.0.0.0/22`; Azure refuses to peer overlapping ranges |

Both private DNS zones must be named in this landing zone's `linkable_dns_zones` in
the landing zone repo, or the link fails with `AuthorizationFailed` while everything
else applies cleanly.

`workload_name` (default `aks`) must match the landing zone's key in the
`landingzones` component — it derives the resource group name being looked up.

If an apply fails with `AuthorizationFailed`, add a targeted grant in the landing zone
repo rather than widening this identity's scope. The identity holds `Contributor` on
its own resource group, `Role Based Access Control Administrator` there (this cluster
creates its own role assignments), a five-action custom peering role on the hub VNet,
and `Private DNS Zone Contributor` on the specific zones it was granted.

## Getting started

Once per machine, set up the tools with
[jay-withers/toolchain](https://github.com/jay-withers/toolchain)
(`bash src/setup.sh`), which installs [mise](https://mise.jdx.dev). Then, in
this repo:

```bash
mise trust && make install   # make install runs `mise install` first
```

`mise.toml` pins every tool this repo's hooks, build and CI use; CI installs
the same versions (jay-withers/workflows v1.26.1+). Add a tool there rather
than installing it by hand.

## Commands

Run `make` (or `make help`) to list the available targets:

```bash
make install   # install mise tools and pre-commit hooks (run once after cloning)
make lint      # run all pre-commit hooks against every file
make fmt       # terraform fmt -recursive
make validate  # terraform init -backend=false + validate (no Azure auth)
make init      # terraform init against ENV's remote state (default dev)
make plan      # terraform init + plan (ENV=dev|stg|prd, default dev)
make apply     # break-glass only: dev is applied by running cd-terraform
make destroy   # terraform destroy (ENV, default dev)
make validate-gitops  # kustomize build + kubeconform over gitops/ (skips if the tools are absent)
```

Terraform targets run against the `terraform/` directory via `-chdir`. The
Terraform version is pinned in `mise.toml` (used locally and by CI).

## Testing

There is no `terraform test` suite at present. What runs is `terraform validate`
(locally and in `ci-terraform`), the pre-commit hooks (TFLint and Checkov once per
environment), and `ci-gitops` over the manifest tree. There is no plan on a pull
request: the plan only succeeds once the landing zone is applied, since the resource
group, hub VNet and hub private DNS zones are all looked up.

## Delivery and Azure auth

You do not create the pipeline identity yourself. The landing zone repo's
`landingzones` component vends `uai-aks-dev`, already federated to this repository
(`pull_request`, `main` and `environment:dev`) and scoped to this cluster's resource
group. github-repos' `pipeline_environments` creates the `dev` GitHub environment and
sets its `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID` from that
identity by name, so nothing is copied by hand.

- **cd-terraform** plans dev on every merge touching Terraform and opens a
  `terraform-pending` issue when the plan has changes. **Actions → cd-terraform → Run
  workflow** applies it. `make apply` locally is break-glass only.
- **schedule-drift** plans dev nightly and records the result in the platform's
  `OpsEvents_CL` table. It never applies.
- **cd-dev-power** starts the dev cluster at 12:00 and stops it at 22:00 UK time, so
  node compute only bills in that window. Run it by hand to start or stop the cluster
  now; a run near a boundary may undo a manual override.
- **manual-terraform-unlock** releases a stuck state lock, given the lock ID from an
  "Error acquiring the state lock" message.

All four run in the `dev` environment as the vended identity.

A local `make plan` needs `az login` with Storage Blob Data Contributor on the landing
zone's state account (`stlzstatedev02d6`), plus `TF_VAR_key_vault_administrator_object_ids`
and `TF_VAR_administrator_object_id` exported (`gh variable list --env dev` shows them).
Only dev has a backend file, so `ENV=stg` or `prd` fails until one exists.

## Pull request checks

Required in the "Protect main" ruleset, which
[github-repos](https://github.com/jay-withers/github-repos) manages (not this repo):

- `pre-commit / Pre-commit` (**ci-pre-commit**: every hook)
- `terraform / Terraform` (**ci-terraform**: credential-free init + validate, behind
  the shared workflow's always-reporting gate)
- `ci-gitops`, `changes` and `validate` (**ci-gitops**: `kustomize build` piped into
  `kubeconform` when `gitops/**` changes, behind the always-running `ci-gitops` gate)

**ci-codeql** scans the workflows with CodeQL, and code scanning is on for this repo,
so a new high or critical alert blocks the merge. **cd-tag** tags a semver release on
every merge to `main`.

## Structure

```text
mise.toml              # pinned tool versions, used locally and in CI
terraform/              # root config — applied directly, no examples/ (see CLAUDE.md)
  versions.tf          # required_version / required_providers + provider block
  data.tf              # looked-up resource group, hub VNet, hub private DNS zones
  locals.tf            # shared locals
  main.tf              # naming module
  main.aks.tf          # the cluster
  main.network.tf      # VNet, NSGs, cluster identity
  main.dns.tf          # apps.internal zone + external-dns identity (created here, not the hub)
  main.hub.tf          # both halves of the hub peering
  main.keyvault.tf     # private workload Key Vault
  main.loki.tf         # Loki log storage account + identity (hub-owned blob DNS zone link)
  main.jumpbox.tf      # jump box + Developer Bastion
  main.flux.tf         # microsoft.flux extension + bootstrap configuration
  main.tenants.tf      # tenant workload identities
  variables.tf         # inputs
  outputs.tf           # outputs
  README.md            # generated by terraform-docs
  .tflint.hcl          # TFLint config (terraform ruleset, recommended preset)
  environments/        # dev.tfvars, stg.tfvars, prd.tfvars
gitops/                 # what Flux reconciles — see gitops/README.md
  clusters/<env>/      # bootstrap: the Flux objects that own everything else
  infrastructure/      # cert-manager, Envoy Gateway, external-dns, kube-prometheus-stack, Loki, Alloy
  tenants/             # per-tenant onboarding (platform) + workloads (tenant)
.pre-commit-config.yaml
commitlint.config.js
.github/
  workflows/
    ci-pre-commit.yml  # lints all files on PRs to main
    ci-terraform.yml   # terraform validate, gated to Terraform changes
    ci-gitops.yml      # kustomize build + kubeconform, gated to gitops changes
    ci-codeql.yml      # CodeQL over the workflows
    cd-terraform.yml   # plans dev on merge; applies when run by hand
    cd-dev-power.yml   # starts/stops the dev cluster on a UK-time schedule
    cd-tag.yml         # auto-tags on merge to main (semver patch bump)
    schedule-drift.yml # nightly drift plan
    manual-terraform-unlock.yml  # releases a stuck state lock
scripts/
  check-tf-standards.sh, tflint-per-env.sh, checkov-per-env.sh  # pre-commit hooks
  validate-gitops.sh   # make validate-gitops / ci-gitops
renovate.json          # automated dependency updates
Makefile
```
