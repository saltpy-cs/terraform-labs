#!/usr/bin/env bash
set -euo pipefail

POINTS=0
TOTAL=8

Q04_DIR="$(dirname "$0")/../q04"
if [[ ! -d "${Q04_DIR}" ]]; then
  echo "Q04 — Data Source and Output (${TOTAL} points)"
  echo "---"
  echo "  FAIL: q04 directory not found — create it and complete the question first"
  echo "---"
  echo "Score: 0/${TOTAL}"
  echo "Result: FAIL"
  exit 1
fi
Q04_DIR="$(cd "${Q04_DIR}" && pwd)"
MAIN_TF="${Q04_DIR}/main.tf"
SELFLINK_FILE="${Q04_DIR}/vpc-selflink.txt"

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

echo "Q04 — Data Source and Output (${TOTAL} points)"
echo "---"

# 1. hashicorp/google provider declared
check 1 "hashicorp/google provider declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'hashicorp/google' "${MAIN_TF}" && echo true || echo false)"

# 2. version constraint on google provider
check 1 "google provider has a version constraint" \
  "$([[ -f "${MAIN_TF}" ]] && grep -A5 'hashicorp/google' "${MAIN_TF}" | grep -q 'version' && echo true || echo false)"

# 3. data "google_compute_network" declared
check 1 "data \"google_compute_network\" data source declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'data.*"google_compute_network"' "${MAIN_TF}" && echo true || echo false)"

# 4. name set to "practice-vpc"
check 1 "network name is \"practice-vpc\"" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'name.*=.*"practice-vpc"' "${MAIN_TF}" && echo true || echo false)"

# 5. project argument supplied
check 1 "project argument supplied to data source" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'project' "${MAIN_TF}" && echo true || echo false)"

# 6. output "vpc_self_link" declared
check 1 "output \"vpc_self_link\" declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'output.*"vpc_self_link"' "${MAIN_TF}" && echo true || echo false)"

# 7. output value references self_link from the data source
check 1 "output value references self_link from data source" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'self_link' "${MAIN_TF}" && echo true || echo false)"

# 8. terraform output matches vpc-selflink.txt
if [[ -f "${Q04_DIR}/.terraform.lock.hcl" && -f "${SELFLINK_FILE}" ]]; then
  EXPECTED=$(cat "${SELFLINK_FILE}")
  ACTUAL=$(terraform -chdir="${Q04_DIR}" output -raw vpc_self_link 2>/dev/null || true)
  check 1 "terraform output vpc_self_link matches vpc-selflink.txt" \
    "$([[ "${ACTUAL}" == "${EXPECTED}" ]] && echo true || echo false)"
else
  check 1 "terraform output vpc_self_link matches vpc-selflink.txt" "false"
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
