#!/usr/bin/env bash
set -euo pipefail

POINTS=0
TOTAL=6

Q12_DIR="$(dirname "$0")/../q12"
if [[ ! -d "${Q12_DIR}" ]]; then
  echo "Q12 — Complex for Expression (${TOTAL} points)"
  echo "---"
  echo "  FAIL: q12 directory not found — create it and complete the question first"
  echo "---"
  echo "Score: 0/${TOTAL}"
  echo "Result: FAIL"
  exit 1
fi
Q12_DIR="$(cd "${Q12_DIR}" && pwd)"
MAIN_TF="${Q12_DIR}/main.tf"

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

echo "Q12 — Complex for Expression (${TOTAL} points)"
echo "---"

# 1. instances variable declared as map(object)
check 1 "instances variable declared as map(object({ip, port}))" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'variable.*"instances"' "${MAIN_TF}" && grep -q 'map(object' "${MAIN_TF}" && echo true || echo false)"

# 2. default has web and api entries
check 1 "default contains web and api entries" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'web' "${MAIN_TF}" && grep -q 'api' "${MAIN_TF}" && echo true || echo false)"

# 3. locals uses a for expression over instances
check 1 "locals uses for expression over var.instances" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'for.*in.*var\.instances' "${MAIN_TF}" && echo true || echo false)"

# 4. format is "name: ip:port"
check 1 "format string produces \"name: ip:port\" pattern" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'attrs\.ip.*attrs\.port\|\.ip.*:.*\.port' "${MAIN_TF}" && echo true || echo false)"

# 5. output "connection_strings" declared
check 1 "output \"connection_strings\" declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'output.*"connection_strings"' "${MAIN_TF}" && echo true || echo false)"

# 6. output contains expected strings
if [[ -f "${Q12_DIR}/.terraform.lock.hcl" ]]; then
  OUTPUT=$(terraform -chdir="${Q12_DIR}" output -json connection_strings 2>/dev/null || true)
  HAS_API=$(echo "${OUTPUT}" | grep -q 'api: 10.0.2.5:8080' && echo true || echo false)
  HAS_WEB=$(echo "${OUTPUT}" | grep -q 'web: 10.0.1.5:80' && echo true || echo false)
  check 1 "output contains \"api: 10.0.2.5:8080\" and \"web: 10.0.1.5:80\"" \
    "$([[ "${HAS_API}" == "true" && "${HAS_WEB}" == "true" ]] && echo true || echo false)"
else
  check 1 "output contains \"api: 10.0.2.5:8080\" and \"web: 10.0.1.5:80\"" "false"
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
