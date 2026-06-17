#!/usr/bin/env bash
set -euo pipefail

POINTS=0
TOTAL=8

Q03_DIR="$(dirname "$0")/../q03"
if [[ ! -d "${Q03_DIR}" ]]; then
  echo "Q03 — Remote GCS Backend (${TOTAL} points)"
  echo "---"
  echo "  FAIL: q03 directory not found — create it and complete the question first"
  echo "---"
  echo "Score: 0/${TOTAL}"
  echo "Result: FAIL"
  exit 1
fi
Q03_DIR="$(cd "${Q03_DIR}" && pwd)"
MAIN_TF="${Q03_DIR}/main.tf"
BUCKET_FILE="${Q03_DIR}/bucket-name.txt"
EXPECTED_PREFIX="practice/q03"

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

echo "Q03 — Remote GCS Backend (${TOTAL} points)"
echo "---"

# 1. backend "gcs" block declared
check 1 "backend \"gcs\" block declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'backend.*"gcs"' "${MAIN_TF}" && echo true || echo false)"

# 2. bucket argument set in backend block or via -backend-config
IN_CODE=false
IN_BACKEND=false
[[ -f "${MAIN_TF}" ]] && grep -q 'bucket' "${MAIN_TF}" && IN_CODE=true
[[ -f "${Q03_DIR}/.terraform/terraform.tfstate" ]] && grep -q '"bucket"' "${Q03_DIR}/.terraform/terraform.tfstate" && IN_BACKEND=true
check 1 "bucket argument present in backend block or -backend-config" \
  "$([[ "${IN_CODE}" == "true" || "${IN_BACKEND}" == "true" ]] && echo true || echo false)"

# 3. prefix set to practice/q03
check 1 "prefix is \"practice/q03\"" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'prefix.*=.*"practice/q03"' "${MAIN_TF}" && echo true || echo false)"

# 4. hashicorp/null provider declared
check 1 "hashicorp/null provider declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'hashicorp/null' "${MAIN_TF}" && echo true || echo false)"

# 5. at least one null_resource declared
check 1 "at least one null_resource declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'resource.*"null_resource"' "${MAIN_TF}" && echo true || echo false)"

# 6. terraform init has been run
check 1 "terraform init has been run" \
  "$([[ -f "${Q03_DIR}/.terraform.lock.hcl" ]] && echo true || echo false)"

# 7. state file exists in GCS under practice/q03/
if [[ -f "${BUCKET_FILE}" ]]; then
  BUCKET=$(cat "${BUCKET_FILE}")
  GCS_STATE=$(gsutil ls "gs://${BUCKET}/practice/" 2>/dev/null || true)
  check 1 "state file exists in GCS under practice/q03/" \
    "$(echo "${GCS_STATE}" | grep -q 'practice/q03/' && echo true || echo false)"
else
  echo "  FAIL (+0)  state file exists in GCS under practice/q03/ (${BUCKET_FILE} not found — run setup first)"
fi

# 8. null_resource present in remote state
if [[ -f "${BUCKET_FILE}" ]]; then
  BUCKET=$(cat "${BUCKET_FILE}")
  STATE_JSON=$(gsutil cat "gs://${BUCKET}/practice/q03/default.tfstate" 2>/dev/null || true)
  check 1 "null_resource present in remote state after apply" \
    "$(echo "${STATE_JSON}" | grep -q 'null_resource' && echo true || echo false)"
else
  echo "  FAIL (+0)  null_resource present in remote state after apply (${BUCKET_FILE} not found — run setup first)"
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
