#!/usr/bin/env bash
set -euo pipefail

Q01_DIR="$(cd "$(dirname "$0")/../q01" && pwd)"
MAIN_TF="${Q01_DIR}/main.tf"
EXPECTED_FILE="${Q01_DIR}/tf-practice.txt"
EXPECTED_CONTENT="Terraform Associate"

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

echo "Q01 — Local File Resource (${TOTAL} points)"
echo "---"

# 1. terraform block with required_providers
check 1 "terraform block with required_providers" \
  "$(grep -q 'required_providers' "${MAIN_TF}" && echo true || echo false)"

# 2. Correct provider source (hashicorp/local)
check 1 "provider source is hashicorp/local" \
  "$(grep -q 'hashicorp/local' "${MAIN_TF}" && echo true || echo false)"

# 3. Provider version constraint specified
check 1 "local provider has a version constraint" \
  "$(grep -A5 'hashicorp/local' "${MAIN_TF}" | grep -q 'version' && echo true || echo false)"

# 4. local_file resource declared
check 1 "resource \"local_file\" declared" \
  "$(grep -q 'resource.*local_file' "${MAIN_TF}" && echo true || echo false)"

# 5. filename argument present
check 1 "filename argument set" \
  "$(grep -q 'filename' "${MAIN_TF}" && echo true || echo false)"

# 6. content argument set to exactly "Terraform Associate"
check 1 "content is exactly \"Terraform Associate\"" \
  "$(grep -q 'content.*=.*"Terraform Associate"' "${MAIN_TF}" && echo true || echo false)"

# 7. terraform init has been run (.terraform.lock.hcl exists)
check 1 "terraform init has been run" \
  "$([[ -f "${Q01_DIR}/.terraform.lock.hcl" ]] && echo true || echo false)"

# 8. output file exists with correct content
if [[ -f "${EXPECTED_FILE}" ]]; then
  ACTUAL=$(cat "${EXPECTED_FILE}")
  check 1 "output file exists and contains \"${EXPECTED_CONTENT}\"" \
    "$([[ "${ACTUAL}" == "${EXPECTED_CONTENT}" ]] && echo true || echo false)"
else
  check 1 "output file exists and contains \"${EXPECTED_CONTENT}\"" "false"
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
