#!/usr/bin/env bash
# Enforces that `locals`, `variable`, and `output` blocks live in a file whose
# name starts with the matching keyword — locals.tf, variables.tf, outputs.tf,
# or a topic-scoped variant of any of them (e.g. outputs.network.tf,
# locals.network.tf). TFLint's terraform_standard_module_structure rule covers
# variables.tf/outputs.tf but hardcodes those exact filenames (no topic-scoped
# variants, no locals support), so this replaces it entirely.
set -euo pipefail

violations=0

check_block() {
  local file=$1 keyword=$2 pattern=$3
  local base
  base=$(basename "$file")
  if [[ ! "$base" =~ ^${keyword}(\..+)?\.tf$ ]] && grep -qE "$pattern" "$file"; then
    echo "error: ${keyword%s} block found in $file — move it to ${keyword}.tf (or ${keyword}.<topic>.tf)" >&2
    violations=1
  fi
}

while IFS= read -r -d '' file; do
  check_block "$file" locals '^locals[[:space:]]*\{'
  check_block "$file" variables '^variable[[:space:]]+"[^"]+"[[:space:]]*\{'
  check_block "$file" outputs '^output[[:space:]]+"[^"]+"[[:space:]]*\{'
done < <(find . -type d -name '.?*' -prune -o -type f -name '*.tf' -print0)

exit "$violations"
