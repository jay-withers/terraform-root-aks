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

status=0
while IFS= read -r overlay; do
  echo "==> ${overlay#"${root}/"}"
  if ! kustomize build "$overlay" | kubeconform \
    -strict \
    -summary \
    -schema-location default \
    -schema-location "$catalog" \
    -ignore-missing-schemas; then
    status=1
  fi
done < <(find "$tree" -name kustomization.yaml -printf '%h\n' | sort)

exit "$status"
