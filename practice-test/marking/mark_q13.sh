#!/usr/bin/env bash
set -euo pipefail

POINTS=0
TOTAL=8

Q13_DIR="$(dirname "$0")/../q13"
if [[ ! -d "${Q13_DIR}" ]]; then
  echo "Q13 — lifecycle Rules (${TOTAL} points)"
  echo "---"
  echo "  FAIL: q13 directory not found — create it and complete the question first"
  echo "---"
  echo "Score: 0/${TOTAL}"
  echo "Result: FAIL"
  exit 1
fi
Q13_DIR="$(cd "${Q13_DIR}" && pwd)"
MAIN_TF="${Q13_DIR}/main.tf"

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

echo "Q13 — lifecycle Rules (${TOTAL} points)"
echo "---"

# 1. null_resource.production_db declared
check 1 "null_resource \"production_db\" declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'resource.*"null_resource".*"production_db"' "${MAIN_TF}" && echo true || echo false)"

# 2. lifecycle block present on production_db
check 1 "lifecycle block present on production_db" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'lifecycle' "${MAIN_TF}" && echo true || echo false)"

# 3. create_before_destroy = true present
check 1 "create_before_destroy = true set" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'create_before_destroy.*=.*true' "${MAIN_TF}" && echo true || echo false)"

# 4. null_resource.app_server declared
check 1 "null_resource \"app_server\" declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'resource.*"null_resource".*"app_server"' "${MAIN_TF}" && echo true || echo false)"

# 5. app_server trigger references production_db.id
check 1 "app_server trigger references null_resource.production_db.id" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'null_resource\.production_db\.id' "${MAIN_TF}" && echo true || echo false)"

# 6. terraform init has been run
check 1 "terraform init has been run" \
  "$([[ -f "${Q13_DIR}/.terraform.lock.hcl" ]] && echo true || echo false)"

# 7. both resources in state
if [[ -f "${Q13_DIR}/.terraform.lock.hcl" ]]; then
  STATE=$(terraform -chdir="${Q13_DIR}" state list 2>/dev/null || true)
  HAS_DB=$(echo "${STATE}" | grep -q 'null_resource\.production_db' && echo true || echo false)
  HAS_APP=$(echo "${STATE}" | grep -q 'null_resource\.app_server' && echo true || echo false)
  check 1 "both null_resource.production_db and null_resource.app_server in state" \
    "$([[ "${HAS_DB}" == "true" && "${HAS_APP}" == "true" ]] && echo true || echo false)"
else
  check 1 "both null_resource.production_db and null_resource.app_server in state" "false"
fi

# 8. prevent_destroy was exercised: check terraform destroy failed or prevent_destroy was removed
# We check for evidence that the learner worked through the exercise:
# Either prevent_destroy is no longer present (removed in step 6) and version is "v2"
HAS_V2=$(grep -q '"v2"' "${MAIN_TF}" 2>/dev/null && echo true || echo false)
NO_PREVENT=$(grep -q 'prevent_destroy' "${MAIN_TF}" 2>/dev/null && echo false || echo true)
check 1 "prevent_destroy removed and version changed to v2 (steps 6-8 completed)" \
  "$([[ "${HAS_V2}" == "true" && "${NO_PREVENT}" == "true" ]] && echo true || echo false)"

echo "---"
echo "Score: ${POINTS}/${TOTAL}"

if [[ "${POINTS}" -eq "${TOTAL}" ]]; then
  echo "Result: PASS"
  exit 0
else
  echo "Result: FAIL"
  exit 1
fi
