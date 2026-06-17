#!/usr/bin/env bash
set -euo pipefail

Q02_DIR="$(cd "$(dirname "$0")/../q02" && pwd)"
MAIN_TF="${Q02_DIR}/main.tf"
VARS_TF="${Q02_DIR}/variables.tf"

POINTS=0
TOTAL=8

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

echo "Q02 — Variables, Validation, and count (${TOTAL} points)"
echo "---"

# 1. environment variable declared as string
check 1 "environment variable declared as string" \
  "$([[ -f "${VARS_TF}" ]] && grep -q 'variable.*"environment"' "${VARS_TF}" && grep -A5 'variable.*"environment"' "${VARS_TF}" | grep -q 'string' && echo true || echo false)"

# 2. environment validation rejects values outside dev/staging/prod
check 1 "environment has validation for dev/staging/prod" \
  "$([[ -f "${VARS_TF}" ]] && grep -A10 'variable.*"environment"' "${VARS_TF}" | grep -q 'validation' && echo true || echo false)"

# 3. replica_count declared as number with default 2
check 1 "replica_count declared as number with default 2" \
  "$([[ -f "${VARS_TF}" ]] && grep -q 'variable.*"replica_count"' "${VARS_TF}" && grep -A5 'variable.*"replica_count"' "${VARS_TF}" | grep -q 'default.*=.*2' && echo true || echo false)"

# 4. replica_count has validation for 1-10
check 1 "replica_count has validation for range 1-10" \
  "$([[ -f "${VARS_TF}" ]] && grep -A10 'variable.*"replica_count"' "${VARS_TF}" | grep -q 'validation' && echo true || echo false)"

# 5. null_resource uses count = var.replica_count
check 1 "null_resource uses count = var.replica_count" \
  "$(grep -q 'count.*=.*var\.replica_count' "${MAIN_TF}" && echo true || echo false)"

# 6. trigger uses name = "app-${var.environment}-${count.index}"
check 1 "trigger uses name = \"app-\${var.environment}-\${count.index}\"" \
  "$(grep -q 'var\.environment.*count\.index\|count\.index.*var\.environment' "${MAIN_TF}" && echo true || echo false)"

# 7. terraform init has been run
check 1 "terraform init has been run" \
  "$([[ -f "${Q02_DIR}/.terraform.lock.hcl" ]] && echo true || echo false)"

# 8. state contains null_resource.app[0] and null_resource.app[1]
if [[ -f "${Q02_DIR}/.terraform.lock.hcl" ]]; then
  STATE=$(terraform -chdir="${Q02_DIR}" state list 2>/dev/null || true)
  HAS_0=$(echo "${STATE}" | grep -q 'null_resource\.app\[0\]' && echo true || echo false)
  HAS_1=$(echo "${STATE}" | grep -q 'null_resource\.app\[1\]' && echo true || echo false)
  check 1 "state contains null_resource.app[0] and null_resource.app[1]" \
    "$([[ "${HAS_0}" == "true" && "${HAS_1}" == "true" ]] && echo true || echo false)"
else
  check 1 "state contains null_resource.app[0] and null_resource.app[1]" "false"
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
