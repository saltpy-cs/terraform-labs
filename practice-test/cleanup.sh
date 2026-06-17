#!/usr/bin/env bash
set -euo pipefail

PRACTICE_DIR="$(cd "$(dirname "$0")" && pwd)"
SETUP_DIR="${PRACTICE_DIR}/setup"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { echo "  $*"; }
warn() { echo "  [!] $*"; }
header() { echo ""; echo "--- $* ---"; }

# Read gcp_project from setup/terraform.tfvars if available
GCP_PROJECT=""
if [[ -f "${SETUP_DIR}/terraform.tfvars" ]]; then
  GCP_PROJECT=$(grep 'gcp_project' "${SETUP_DIR}/terraform.tfvars" | sed 's/.*=[ ]*"\(.*\)".*/\1/' | tr -d ' ')
fi

destroy_q() {
  local q=$1
  shift
  local dir="${PRACTICE_DIR}/${q}"
  [[ -d "${dir}" ]] || return 0
  [[ -f "${dir}/.terraform.lock.hcl" ]] || { log "${q}: no init found, skipping destroy"; return 0; }
  log "${q}: destroying..."
  terraform -chdir="${dir}" destroy -auto-approve -no-color "$@" 2>&1 | grep -E 'Destroy complete|Error|error' || true
}

# ---------------------------------------------------------------------------
# Phase 1: destroy terraform-managed resources in q folders
# ---------------------------------------------------------------------------

header "Phase 1: destroy resources in question directories"

# q01 — local_file
destroy_q q01

# q02 — null_resource, needs environment variable
destroy_q q02 -var="environment=dev"

# q03 — null_resource with remote GCS backend (cleans up GCS state file)
destroy_q q03

# q04 — data source only, no resources; needs gcp_project for provider init
if [[ -n "${GCP_PROJECT}" ]]; then
  destroy_q q04 -var="gcp_project=${GCP_PROJECT}"
else
  log "q04: skipping (no gcp_project found in setup/terraform.tfvars)"
fi

# q05 — null_resource (module)
destroy_q q05

# q06 — null_resource (for_each)
destroy_q q06

# q07 — outputs only, no resources
destroy_q q07

# q08 — outputs only, no resources
destroy_q q08

# q09 — DO NOT destroy: the imported bucket is owned by setup and will be
#        removed when setup is destroyed in Phase 2.
if [[ -d "${PRACTICE_DIR}/q09" ]]; then
  log "q09: skipping destroy (bucket is managed by setup, removed in Phase 2)"
fi

# q10 — workspaces: destroy each workspace independently
if [[ -d "${PRACTICE_DIR}/q10" && -f "${PRACTICE_DIR}/q10/.terraform.lock.hcl" ]]; then
  log "q10: destroying all workspaces..."
  for ws in dev staging prod; do
    if terraform -chdir="${PRACTICE_DIR}/q10" workspace select "${ws}" -no-color 2>/dev/null; then
      terraform -chdir="${PRACTICE_DIR}/q10" destroy -auto-approve -no-color 2>&1 \
        | grep -E 'Destroy complete|Error' || true
    fi
  done
  terraform -chdir="${PRACTICE_DIR}/q10" workspace select default -no-color 2>/dev/null || true
fi

# q11 — terraform test only, no persistent resources
destroy_q q11

# q12 — outputs only, no resources
destroy_q q12

# q13 — null_resource (lifecycle)
destroy_q q13

# q14 — null_resource (operational trigger)
destroy_q q14

# ---------------------------------------------------------------------------
# Phase 2: delete question directories
# ---------------------------------------------------------------------------

header "Phase 2: removing question directories"

for q in "${PRACTICE_DIR}"/q*/; do
  [[ -d "${q}" ]] || continue
  log "removing ${q##*/practice-test/}..."
  rm -rf "${q}"
done

log "question directories removed"

# ---------------------------------------------------------------------------
# Phase 3: destroy setup infrastructure (GCS buckets + VPC)
# ---------------------------------------------------------------------------

header "Phase 3: destroy setup infrastructure"

if [[ ! -f "${SETUP_DIR}/terraform.tfvars" ]]; then
  warn "setup/terraform.tfvars not found — skipping setup destroy"
  warn "Run 'terraform destroy' in practice-test/setup/ manually when ready"
else
  echo ""
  echo "  This will destroy the GCS buckets and VPC created by setup."
  echo "  These are the only resources that incur ongoing cost."
  echo ""
  read -r -p "  Destroy setup infrastructure? [y/N] " CONFIRM
  if [[ "${CONFIRM}" =~ ^[Yy]$ ]]; then
    log "destroying setup infrastructure..."
    terraform -chdir="${SETUP_DIR}" destroy -auto-approve -no-color 2>&1 \
      | grep -E 'Destroy complete|Error' || true
    log "setup infrastructure destroyed"
  else
    log "skipped — remember to run 'terraform destroy' in practice-test/setup/ to avoid ongoing charges"
  fi
fi

echo ""
echo "Cleanup complete."
