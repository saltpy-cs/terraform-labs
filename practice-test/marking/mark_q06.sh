#!/usr/bin/env bash
set -euo pipefail

POINTS=0
TOTAL=10

Q06_DIR="$(dirname "$0")/../q06"
if [[ ! -d "${Q06_DIR}" ]]; then
  echo "Q06 — for_each with a Map of Objects (${TOTAL} points)"
  echo "---"
  echo "  FAIL: q06 directory not found — create it and complete the question first"
  echo "---"
  echo "Score: 0/${TOTAL}"
  echo "Result: FAIL"
  exit 1
fi
Q06_DIR="$(cd "${Q06_DIR}" && pwd)"
MAIN_TF="${Q06_DIR}/main.tf"
VARS_TF="${Q06_DIR}/variables.tf"

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

echo "Q06 — for_each with a Map of Objects (${TOTAL} points)"
echo "---"

# 1. servers variable declared
check 1 "servers variable declared" \
  "$([[ -f "${VARS_TF}" ]] && grep -q 'variable.*"servers"' "${VARS_TF}" && echo true || echo false)"

# 2. type is map(object(...))
check 1 "servers type is map(object({...}))" \
  "$([[ -f "${VARS_TF}" ]] && grep -q 'map(object' "${VARS_TF}" && echo true || echo false)"

# 3. default has at least two entries (machine_type and zone present)
check 1 "default contains machine_type and zone attributes" \
  "$([[ -f "${VARS_TF}" ]] && grep -q 'machine_type' "${VARS_TF}" && grep -q 'zone' "${VARS_TF}" && echo true || echo false)"

# 4. null_resource named "server" declared with for_each
check 1 "null_resource \"server\" declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'resource.*"null_resource".*"server"' "${MAIN_TF}" && echo true || echo false)"

# 5. for_each = var.servers
check 1 "for_each = var.servers used" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'for_each.*=.*var\.servers' "${MAIN_TF}" && echo true || echo false)"

# 6. triggers uses each.value.machine_type
check 1 "triggers uses each.value.machine_type" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'machine_type.*=.*each\.value\.machine_type' "${MAIN_TF}" && echo true || echo false)"

# 7. triggers uses each.value.zone
check 1 "triggers uses each.value.zone" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'zone.*=.*each\.value\.zone' "${MAIN_TF}" && echo true || echo false)"

# 8. terraform init has been run
check 1 "terraform init has been run" \
  "$([[ -f "${Q06_DIR}/.terraform.lock.hcl" ]] && echo true || echo false)"

# 9. state contains null_resource.server["web"]
if [[ -f "${Q06_DIR}/.terraform.lock.hcl" ]]; then
  STATE=$(terraform -chdir="${Q06_DIR}" state list 2>/dev/null || true)
  check 1 "state contains null_resource.server[\"web\"]" \
    "$(echo "${STATE}" | grep -q 'null_resource\.server\["web"\]' && echo true || echo false)"

  # 10. state contains null_resource.server["api"]
  check 1 "state contains null_resource.server[\"api\"]" \
    "$(echo "${STATE}" | grep -q 'null_resource\.server\["api"\]' && echo true || echo false)"
else
  check 1 "state contains null_resource.server[\"web\"]" "false"
  check 1 "state contains null_resource.server[\"api\"]" "false"
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
