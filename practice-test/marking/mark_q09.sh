#!/usr/bin/env bash
set -euo pipefail

POINTS=0
TOTAL=10

Q09_DIR="$(dirname "$0")/../q09"
if [[ ! -d "${Q09_DIR}" ]]; then
  echo "Q09 — terraform import (${TOTAL} points)"
  echo "---"
  echo "  FAIL: q09 directory not found — create it and complete the question first"
  echo "---"
  echo "Score: 0/${TOTAL}"
  echo "Result: FAIL"
  exit 1
fi
Q09_DIR="$(cd "${Q09_DIR}" && pwd)"
MAIN_TF="${Q09_DIR}/main.tf"
IMPORT_FILE="${Q09_DIR}/import-bucket.txt"

check() {
  local points=$1
  local desc=$2
  local result=$3
  if [[ "${result}" == "true" ]]; then
    echo "  PASS (+${points}) ${desc}"
    POINTS=$((POINTS + points))
  else
    echo "  FAIL (+0)  ${desc}"
  fi
}

echo "Q09 — terraform import (${TOTAL} points)"
echo "---"

# 1. hashicorp/google provider declared
check 1 "hashicorp/google provider declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'hashicorp/google' "${MAIN_TF}" && echo true || echo false)"

# 2. version constraint on google provider
check 1 "google provider has a version constraint" \
  "$([[ -f "${MAIN_TF}" ]] && grep -A5 'hashicorp/google' "${MAIN_TF}" | grep -q 'version' && echo true || echo false)"

# 3. google_storage_bucket.imported resource declared
check 1 "resource \"google_storage_bucket\" \"imported\" declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'resource.*"google_storage_bucket".*"imported"' "${MAIN_TF}" && echo true || echo false)"

# 4. bucket name matches import-bucket.txt
if [[ -f "${IMPORT_FILE}" && -f "${MAIN_TF}" ]]; then
  BUCKET=$(cat "${IMPORT_FILE}")
  check 1 "bucket name matches import-bucket.txt" \
    "$(grep -q "${BUCKET}" "${MAIN_TF}" && echo true || echo false)"
else
  check 1 "bucket name matches import-bucket.txt" "false"
fi

# 5. location = "US-CENTRAL1"
check 1 "location = \"US-CENTRAL1\"" \
  "$([[ -f "${MAIN_TF}" ]] && grep -qi 'location.*=.*"us-central1"' "${MAIN_TF}" && echo true || echo false)"

# 6. project argument set
check 1 "project argument set" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'project' "${MAIN_TF}" && echo true || echo false)"

# 7. terraform init has been run
check 1 "terraform init has been run" \
  "$([[ -f "${Q09_DIR}/.terraform.lock.hcl" ]] && echo true || echo false)"

# 8. resource exists in state (import completed)
if [[ -f "${Q09_DIR}/.terraform.lock.hcl" ]]; then
  STATE=$(terraform -chdir="${Q09_DIR}" state list 2>/dev/null || true)
  check 1 "google_storage_bucket.imported exists in state" \
    "$(echo "${STATE}" | grep -q 'google_storage_bucket\.imported' && echo true || echo false)"
else
  check 1 "google_storage_bucket.imported exists in state" "false"
fi

# 9. state show returns bucket attributes
if [[ -f "${Q09_DIR}/.terraform.lock.hcl" ]]; then
  STATE_SHOW=$(terraform -chdir="${Q09_DIR}" state show google_storage_bucket.imported 2>/dev/null || true)
  check 1 "state show returns bucket name and location" \
    "$(echo "${STATE_SHOW}" | grep -q 'name' && echo "${STATE_SHOW}" | grep -q 'location' && echo true || echo false)"
else
  check 1 "state show returns bucket name and location" "false"
fi

# 10. terraform plan shows no destructive changes (0 to destroy)
if [[ -f "${Q09_DIR}/.terraform.lock.hcl" ]]; then
  PLAN=$(terraform -chdir="${Q09_DIR}" plan -lock=false -no-color 2>/dev/null || true)
  check 1 "terraform plan shows no destructive changes (0 to destroy)" \
    "$(echo "${PLAN}" | grep -q 'No changes\|0 to destroy' && echo true || echo false)"
else
  check 1 "terraform plan shows no destructive changes (0 to destroy)" "false"
fi

echo "---"
echo "Score: ${POINTS}/${TOTAL}"

if [[ "${POINTS}" -eq "${TOTAL}" ]]; then
  echo "Result: PASS"
  exit 0
else
  echo "Result: FAIL"
  exit 1
fi
