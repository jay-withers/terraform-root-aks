# GitOps tree

Everything the cluster runs that Terraform cannot install. The API server is
private, so there is no `kubernetes` or `helm` provider in `terraform/` and no route
from Terraform into the cluster: Flux arrives as the `microsoft.flux` AKS extension
through ARM, and this tree is what it reconciles.

```
gitops/
├── clusters/<env>/          bootstrap only — the Flux objects that own everything else
├── infrastructure/
│   ├── controllers/         cert-manager, Envoy Gateway, kube-prometheus-stack, Loki, Alloy
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

`admin` covers the `HTTPRoute` only because the `gateway-api-admin` ClusterRole in
`infrastructure/configs/gateway.yaml` says so. `admin`, `edit` and `view` are
aggregated ClusterRoles that pick up the
built-in namespaced kinds and nothing else, so **a CRD installed by a chart is
invisible to them** until a ClusterRole labelled
`rbac.authorization.k8s.io/aggregate-to-admin` names it. A tenant hitting
`cannot patch resource "<plural>" in API group ...` on a custom kind wants a rule
there — not a wider binding, and not `multiTenancy.enforce = "false"`. That the role
is cluster-scoped grants nothing by itself: the tenant reaches it through a
`RoleBinding`, so the rights stop at the namespace.

Each such role lives in the file declaring the resource it opens up, not in an
`rbac.yaml` — the grant and the thing granted are one decision, and splitting them
is how one gets changed without the other.

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

## Logs

Loki and Grafana Alloy sit alongside the metrics stack, and the split between them
is worth understanding before changing either.

**Alloy is the one component that must run everywhere.** It is a DaemonSet, and it
reads finished log files off each node's own filesystem under `/var/log/pods`. So
unlike every other block in `controllers/`, it carries no `nodeSelector` and a
toleration matching *everything* — the system pool is tainted `CriticalAddonsOnly`
and the monitoring pool `workload=monitoring`, and a collector that tolerates
neither quietly collects only from the apps pool while reporting itself healthy.

That it reads from the node, rather than receiving pushes, is also why tenants need
no new egress rule: no tenant pod ever sends Alloy anything. Same argument as the
Key Vault CSI mount, which the tenant policy already documents.

**Loki keeps nothing durable in the cluster.** Chunks and index go to the blob
account in `terraform/main.loki.tf`, over a private endpoint, authenticated with
workload identity — `useFederatedToken`, not `useManagedIdentity`, so it is Loki's
own service account token being exchanged rather than the node's identity. Shared
access keys are disabled on the account, so there is no key to configure and no
fallback if the identity is wrong. Its PVC holds only the write-ahead log; losing
it costs minutes of ingest, not history.

**Retention is the only bound on the blob bill.** Loki's own default is to keep
everything forever. `var.loki_retention_days` becomes `LOKI_RETENTION_PERIOD`, and
the compactor is what enforces it — `retention_enabled` must stay true, or the
period is read, reported and never acted on, with nothing anywhere reporting that.

**Loki's `auth_enabled` is false, and that is not the cluster's tenancy boundary.**
Every line carries its namespace as a label, but anyone who can query Loki can query
every namespace. Grafana's own login is the boundary today. Making Loki multi-tenant
means a tenant per namespace and a Grafana organisation to match — a migration, not
a flag.

Two chart defaults are turned off because they do not fit this cluster rather than
because they are wrong: `chunksCache` and `resultsCache` are memcached StatefulSets
that between them ask for more memory than a monitoring node has, and
`deploymentMode` is `SingleBinary` rather than the default `SimpleScalable`, which
would be three StatefulSets and a gateway.

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

**No log-based alerting.** Loki's ruler has a bucket and nothing in it. Alerting is
Prometheus's, through Alertmanager; a rule that fires on log content is a second
alerting path with its own silences and its own routing to keep in step.

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

`terraform/main.dns.tf` creates the `apps.internal` private DNS zone and links it to
this VNet, with a wildcard record pointing every name in it at that address. So
anything on this VNet — the jump box included — resolves these names with no hosts
entry, and onboarding a tenant needs no DNS change: the record already covers it.

Two consequences worth knowing. A name resolves whether or not an `HTTPRoute`
claims it, so a typo reaches Envoy and comes back 404 rather than NXDOMAIN. And the
zone is linked to this VNet only — resolving from the hub or another spoke needs a
link on that VNet, which is a grant in the platform repo, not a change here.

Setting `apps_dns_zone_name = null` skips the zone, and then it is back to a hosts
entry on the jump box:

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
