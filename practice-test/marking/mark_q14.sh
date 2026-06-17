#!/usr/bin/env bash
set -euo pipefail

POINTS=0
TOTAL=6

Q14_DIR="$(dirname "$0")/../q14"
if [[ ! -d "${Q14_DIR}" ]]; then
  echo "Q14 — Operational Trigger Pattern (${TOTAL} points)"
  echo "---"
  echo "  FAIL: q14 directory not found — create it and complete the question first"
  echo "---"
  echo "Score: 0/${TOTAL}"
  echo "Result: FAIL"
  exit 1
fi
Q14_DIR="$(cd "${Q14_DIR}" && pwd)"
MAIN_TF="${Q14_DIR}/main.tf"

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

echo "Q14 — Operational Trigger Pattern (${TOTAL} points)"
echo "---"

# 1. variable operation_timestamp with default ""
check 1 "variable \"operation_timestamp\" with default \"\"" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'variable.*"operation_timestamp"' "${MAIN_TF}" && grep -A5 'variable.*"operation_timestamp"' "${MAIN_TF}" | grep -q 'default.*=.*""' && echo true || echo false)"

# 2. null_resource.trigger with count conditional
check 1 "null_resource \"trigger\" uses count conditional on operation_timestamp" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'resource.*"null_resource".*"trigger"' "${MAIN_TF}" && grep -q 'count.*operation_timestamp' "${MAIN_TF}" && echo true || echo false)"

# 3. triggers.ts = var.operation_timestamp
check 1 "triggers block has ts = var.operation_timestamp" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'ts.*=.*var\.operation_timestamp' "${MAIN_TF}" && echo true || echo false)"

# 4. local-exec provisioner present
check 1 "local-exec provisioner present" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'local-exec' "${MAIN_TF}" && echo true || echo false)"

# 5. output "operation_ran" with conditional value
check 1 "output \"operation_ran\" with yes/no conditional" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'output.*"operation_ran"' "${MAIN_TF}" && grep -q '"yes"' "${MAIN_TF}" && grep -q '"no"' "${MAIN_TF}" && echo true || echo false)"

# 6. operation_ran = "yes" after apply with a timestamp
if [[ -f "${Q14_DIR}/.terraform.lock.hcl" ]]; then
  TS=$(date +%s)
  terraform -chdir="${Q14_DIR}" apply -auto-approve -var="operation_timestamp=${TS}" -no-color >/dev/null 2>&1 || true
  OUTPUT=$(terraform -chdir="${Q14_DIR}" output -raw operation_ran 2>/dev/null || true)
  check 1 "operation_ran outputs \"yes\" after apply with a timestamp" \
    "$([[ "${OUTPUT}" == "yes" ]] && echo true || echo false)"
else
  check 1 "operation_ran outputs \"yes\" after apply with a timestamp" "false"
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
