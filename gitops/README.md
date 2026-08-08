# GitOps tree

Everything the cluster runs that Terraform cannot install. The API server is
private, so there is no `kubernetes` or `helm` provider in `terraform/` and no route
from Terraform into the cluster: Flux arrives as the `microsoft.flux` AKS extension
through ARM, and this tree is what it reconciles.

```
gitops/
├── clusters/<env>/          bootstrap only — the Flux objects that own everything else
├── infrastructure/
│   ├── controllers/         cert-manager, Envoy Gateway, kube-prometheus-stack
│   └── configs/             the custom resources those controllers serve
└── tenants/
    ├── onboarding/<env>/    platform-owned: namespace, identity, RBAC, policy, sources
    └── <tenant>/<env>/      tenant-owned: the workloads themselves
```

## How a change reaches the cluster

`terraform/main.flux.tf` creates one Flux `Kustomization`, named `cluster`, building
`gitops/clusters/<environment>`. That path is derived from `var.environment` — see
`local.flux_kustomization_path` — so the directory names here are load-bearing.

That single Kustomization declares four more, and stops:

```
cluster (ARM)  ->  infra-controllers  ->  infra-configs  ->  tenants  ->  <tenant>
                   Helm charts + CRDs     Gateway, issuers   namespaces   workloads
```

Each arrow is a `dependsOn` with `wait: true`, so a stage only starts once the one
before it is healthy. The controllers/configs split exists because a Kustomization
containing both a CRD and a custom resource of that kind fails its first apply.

## Multi-tenancy

The Flux extension is installed at its defaults, which means multi-tenancy is
enforced: `--no-cross-namespace-refs=true`. A `Kustomization` in a tenant namespace
**cannot** reference the `flux-system` `GitRepository`. Everything about the layout
follows from that.

Each tenant gets, all of it platform-owned in `tenants/onboarding/`:

| Object | Why the platform owns it |
| --- | --- |
| `Namespace` | carries the `gateway-access` label that grants the right to publish |
| `ServiceAccount` (workload) | annotated with the Azure client ID — a tenant that could edit this could run as any identity in the subscription |
| `ServiceAccount` (reconciler) | separate identity; holds no Azure credential |
| `RoleBinding` → `admin` | namespaced, never a `ClusterRoleBinding` |
| `SecretProviderClass` | names which Key Vault secrets the tenant may mount |
| `GitRepository` | in the tenant's namespace, because a cross-namespace source is refused |
| `Kustomization` | carries `serviceAccountName` — a tenant able to edit this could delete that line and reconcile as cluster-admin |
| `CiliumNetworkPolicy` | isolation is not something a tenant opts into |

The tenant owns only its `Deployment`, `Service` and `HTTPRoute`. The check that the
isolation is real: commit a `ClusterRoleBinding` under `tenants/<tenant>/` and watch
the Kustomization refuse it.

`azurerm_kubernetes_flux_configuration`'s `kustomizations` block has no
`service_account_name` attribute, which is why every Kustomization except the
bootstrap one is declared here rather than in Terraform.

## Values that come from Terraform

Some values are Azure-assigned and have no pre-image — a workload identity's client
ID most of all. Rather than apply, read an output, paste a GUID and apply again, the
bootstrap Kustomization carries `postBuild.substitute` from
`local.flux_post_build_substitutions`.

That substitution applies **only** to `clusters/<env>/`. Everything else reads
`clusters/base/cluster-vars.yaml` through `postBuild.substituteFrom`, which is why
that ConfigMap is in `flux-system` — enforced multi-tenancy will not let a
Kustomization read one elsewhere.

Consequence: a literal `${` anywhere in `clusters/<env>/` is replaced with an empty
string if Terraform has no value for it. Keep that directory to bootstrap objects.
`terraform output flux_post_build_substitutions` lists what is defined.

## Deliberate omissions

**No cluster-wide default-deny network policy.** In Cilium, a policy that selects an
endpoint default-denies every direction it mentions, so a cluster-wide one would
have to enumerate the egress of `kube-system`, `flux-system` and `cert-manager`
before it did anything useful — and take the cluster off the air the moment it
missed one. Isolation is per tenant, where getting it wrong costs one namespace.

**No L7 or FQDN rules.** AKS's managed Cilium serves L3/L4 only; L7 and DNS-based
policy need the chargeable Advanced Container Networking Services add-on. A policy
written with them applies without error and silently fails to filter.

**No public DNS, no ACME.** There is no public DNS zone in the landing zone, so
Let's Encrypt can complete neither HTTP-01 nor DNS-01. cert-manager runs a private
CA instead, which is the right answer for names that only resolve inside the VNet —
but nothing trusts it until told to.

**No ingress-nginx.** The project is in retirement, and AKS's managed Cilium does not
serve Gateway API itself, so the data plane is Envoy Gateway.

## Prerequisites an operator has to do once

Neither is automatable from here: the workload Key Vault answers only on a private
endpoint, and a Grafana password does not belong in git. Both are run from the jump
box, or through `az aks command invoke`.

```bash
# The secret the example tenant mounts. Without it the pod stays in ContainerCreating.
az keyvault secret set --vault-name "$(terraform -chdir=terraform output -raw workload_key_vault_name)" \
  --name whoami-demo --value hello

# Grafana's admin credentials. Without it Grafana will not start — which is the
# intended failure: visibly absent beats quietly reachable on a published default.
kubectl create secret generic grafana-admin -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24)"
```

## Reaching what it publishes

Hostnames are under `apps.internal`, served by the internal gateway at
`terraform output gateway_internal_ip` (`10.1.3.251` on the default node subnet).
There is no DNS zone for them yet — creating one needs a Private DNS Zone
Contributor grant in the platform repo — so add a hosts entry on the jump box:

```
10.1.3.251  whoami.apps.internal grafana.apps.internal
```

Certificates are issued by the cluster's private CA. Export and trust it, or use
`curl -k`:

```bash
kubectl get secret internal-ca -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d
```

## Adding a tenant

1. Copy `tenants/onboarding/base/whoami.yaml`, changing the tenant name throughout.
2. Add the workload manifests under `tenants/<tenant>/{base,dev,stg,prd}/`.
3. Add the tenant to each cluster's `tenants/onboarding/<env>/kustomization.yaml`.
4. Add a matching entry to `var.workload_identities` in
   `terraform/environments/<env>.tfvars`, and add `<TENANT>_CLIENT_ID` to
   `clusters/base/cluster-vars.yaml`.

Step 4 is the one that is easy to forget and produces the least helpful failure: the
namespace and service account in tfvars are matched by Entra ID as a literal string,
and a mismatch surfaces as `AADSTS70021` at the pod's first token request.
`terraform output workload_identity_subjects` prints what Azure is expecting.
