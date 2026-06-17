#!/usr/bin/env bash
set -euo pipefail

POINTS=0
TOTAL=6

Q11_DIR="$(dirname "$0")/../q11"
if [[ ! -d "${Q11_DIR}" ]]; then
  echo "Q11 — terraform test (${TOTAL} points)"
  echo "---"
  echo "  FAIL: q11 directory not found — create it and complete the question first"
  echo "---"
  echo "Score: 0/${TOTAL}"
  echo "Result: FAIL"
  exit 1
fi
Q11_DIR="$(cd "${Q11_DIR}" && pwd)"
MODULE_DIR="${Q11_DIR}/modules/labeler"
TEST_FILE="${Q11_DIR}/tests/validate.tftest.hcl"

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

MODULE_TF=$(find "${MODULE_DIR}" -name '*.tf' 2>/dev/null | xargs cat 2>/dev/null || true)

echo "Q11 — terraform test (${TOTAL} points)"
echo "---"

# 1. module declares prefix and env variables
HAS_PREFIX=$(echo "${MODULE_TF}" | grep -q 'variable.*"prefix"' && echo true || echo false)
HAS_ENV=$(echo "${MODULE_TF}" | grep -q 'variable.*"env"' && echo true || echo false)
check 1 "module declares prefix and env variables" \
  "$([[ "${HAS_PREFIX}" == "true" && "${HAS_ENV}" == "true" ]] && echo true || echo false)"

# 2. null_resource.marker with trigger label = "${prefix}-${env}"
check 1 "null_resource.marker trigger uses prefix and env" \
  "$(echo "${MODULE_TF}" | grep -q 'resource.*"null_resource".*"marker"' && echo "${MODULE_TF}" | grep -q 'var\.prefix.*var\.env\|var\.env.*var\.prefix' && echo true || echo false)"

# 3. output full_label = "${prefix}-${env}"
check 1 "output \"full_label\" declared with prefix-env value" \
  "$(echo "${MODULE_TF}" | grep -q 'output.*"full_label"' && echo "${MODULE_TF}" | grep -q 'var\.prefix.*var\.env' && echo true || echo false)"

# 4. test file exists
check 1 "tests/validate.tftest.hcl exists" \
  "$([[ -f "${TEST_FILE}" ]] && echo true || echo false)"

# 5. mock_provider and assert present in test file
check 1 "test file has mock_provider \"null\" and assert block" \
  "$([[ -f "${TEST_FILE}" ]] && grep -q 'mock_provider.*"null"' "${TEST_FILE}" && grep -q 'assert' "${TEST_FILE}" && echo true || echo false)"

# 6. terraform test passes
if [[ -f "${Q11_DIR}/.terraform.lock.hcl" ]]; then
  TEST_OUTPUT=$(terraform -chdir="${Q11_DIR}" test 2>&1 || true)
  check 1 "terraform test passes (1 passed, 0 failed)" \
    "$(echo "${TEST_OUTPUT}" | grep -q '1 passed, 0 failed' && echo true || echo false)"
else
  check 1 "terraform test passes (1 passed, 0 failed)" "false"
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
