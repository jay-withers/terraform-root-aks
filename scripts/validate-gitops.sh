#!/usr/bin/env bash
# Builds every kustomize overlay under gitops/ and validates the result against the
# Kubernetes and CRD schemas.
#
# Worth doing because nothing else catches these. Flux applies whatever is on the
# branch to a cluster with no public API server: a malformed manifest is not a
# failed build, it is a Kustomization that reports NotReady where nobody is looking,
# and no `terraform test` suite exists to catch it either.
#
# kustomize and kubeconform are not in the dev container image, which is external to
# this repository. Missing tools are a skip rather than a failure so the hook stays
# usable locally; ci-gitops installs both and is the authoritative check.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
tree="${root}/gitops"

[ -d "$tree" ] || exit 0

missing=()
for tool in kustomize kubeconform; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done

if [ ${#missing[@]} -gt 0 ]; then
  echo "skipping gitops validation: ${missing[*]} not installed (ci-gitops runs it)" >&2
  exit 0
fi

# The built-in schemas cover core Kubernetes; the catalog covers the CRDs this tree
# uses — Flux, cert-manager, Gateway API, Cilium, the Key Vault CSI driver and Envoy
# Gateway. -ignore-missing-schemas keeps a newly introduced CRD from failing the
# build, so watch the "Skipped" count: anything above zero was not really checked.
catalog='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

# Flux resolves ${NAME} at reconcile time, from post-build substitution; kustomize
# does not, so what reaches kubeconform still carries the placeholders. Most survive
# validation because they sit in free-form strings, but some do not: an HTTPRoute
# hostname is pattern-checked, and "whoami.${APPS_DNS_ZONE_NAME}" is not a DNS name.
#
# So the placeholders are resolved here against stand-ins first. The values are not
# this cluster's and are not meant to be — they exist to be the right *shape*, so
# that what is checked is the manifest's structure rather than Terraform's outputs.
#
# Known names are listed so their shape is right where a schema cares. Anything else
# falls through to the generic rule, which means a mistyped variable name validates
# rather than failing here — that mistake surfaces as an empty string in the cluster,
# and the guard against it is keeping this list and
# local.flux_post_build_substitutions in step.
resolve_placeholders() {
  sed -E \
    -e 's/\$\{APPS_DNS_ZONE_NAME\}/example.internal/g' \
    -e 's/\$\{CLUSTER_ENVIRONMENT\}/dev/g' \
    -e 's/\$\{CLUSTER_NAME\}/aks-example-dev/g' \
    -e 's/\$\{GATEWAY_INTERNAL_IP\}/10.0.0.1/g' \
    -e 's/\$\{WORKLOAD_KEY_VAULT_NAME\}/kv-example-dev/g' \
    -e 's/\$\{AZURE_RESOURCE_GROUP\}/rg-example-dev/g' \
    -e 's/\$\{LOKI_STORAGE_ACCOUNT\}/stexampledev01/g' \
    -e 's/\$\{LOKI_CHUNKS_CONTAINER\}/loki-chunks/g' \
    -e 's/\$\{LOKI_RULER_CONTAINER\}/loki-ruler/g' \
    -e 's/\$\{LOKI_RETENTION_PERIOD\}/14d/g' \
    -e 's/\$\{(AZURE_TENANT_ID|AZURE_SUBSCRIPTION_ID|[A-Z0-9_]+_CLIENT_ID)\}/00000000-0000-0000-0000-000000000000/g' \
    -e 's/\$\{[A-Z0-9_]+\}/placeholder/g'
}

status=0
while IFS= read -r overlay; do
  echo "==> ${overlay#"${root}/"}"
  if ! kustomize build "$overlay" | resolve_placeholders | kubeconform \
    -strict \
    -summary \
    -schema-location default \
    -schema-location "$catalog" \
    -ignore-missing-schemas; then
    status=1
  fi
done < <(find "$tree" -name kustomization.yaml -printf '%h\n' | sort)

exit "$status"
