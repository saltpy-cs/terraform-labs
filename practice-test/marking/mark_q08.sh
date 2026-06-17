#!/usr/bin/env bash
set -euo pipefail

POINTS=0
TOTAL=10

Q08_DIR="$(dirname "$0")/../q08"
if [[ ! -d "${Q08_DIR}" ]]; then
  echo "Q08 — for Expression Transforming a List (${TOTAL} points)"
  echo "---"
  echo "  FAIL: q08 directory not found — create it and complete the question first"
  echo "---"
  echo "Score: 0/${TOTAL}"
  echo "Result: FAIL"
  exit 1
fi
Q08_DIR="$(cd "${Q08_DIR}" && pwd)"
MAIN_TF="${Q08_DIR}/main.tf"

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

echo "Q08 — for Expression Transforming a List (${TOTAL} points)"
echo "---"

# 1. allowed_ips variable declared as list(string)
check 1 "allowed_ips variable declared as list(string)" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'variable.*"allowed_ips"' "${MAIN_TF}" && grep -q 'list(string)' "${MAIN_TF}" && echo true || echo false)"

# 2. default contains the three expected CIDRs
check 1 "default contains 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q '10\.0\.0\.0/8' "${MAIN_TF}" && grep -q '172\.16\.0\.0/12' "${MAIN_TF}" && grep -q '192\.168\.0\.0/16' "${MAIN_TF}" && echo true || echo false)"

# 3. locals block with a for expression
check 1 "locals block contains a for expression" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'locals' "${MAIN_TF}" && grep -q '\bfor\b' "${MAIN_TF}" && echo true || echo false)"

# 4. for expression iterates over var.allowed_ips
check 1 "for expression iterates over var.allowed_ips" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'for.*in.*var\.allowed_ips\|var\.allowed_ips.*for' "${MAIN_TF}" && echo true || echo false)"

# 5. each object has a cidr key
check 1 "each object has a cidr key" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'cidr' "${MAIN_TF}" && echo true || echo false)"

# 6. each object has a description key
check 1 "each object has a description key" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'description' "${MAIN_TF}" && echo true || echo false)"

# 7. description = "Allow traffic from ${cidr}"
check 1 "description uses \"Allow traffic from\" pattern" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'Allow traffic from' "${MAIN_TF}" && echo true || echo false)"

# 8. output "ip_objects" declared
check 1 "output \"ip_objects\" declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'output.*"ip_objects"' "${MAIN_TF}" && echo true || echo false)"

# 9. terraform init has been run
check 1 "terraform init has been run" \
  "$([[ -f "${Q08_DIR}/.terraform.lock.hcl" ]] && echo true || echo false)"

# 10. output contains three objects with cidr and description
if [[ -f "${Q08_DIR}/.terraform.lock.hcl" ]]; then
  OUTPUT=$(terraform -chdir="${Q08_DIR}" output -json ip_objects 2>/dev/null || true)
  COUNT=$(echo "${OUTPUT}" | jq 'length' 2>/dev/null || echo 0)
  check 1 "output ip_objects contains 3 objects with cidr and description" \
    "$([[ "${COUNT}" -eq 3 ]] && echo true || echo false)"
else
  check 1 "output ip_objects contains 3 objects with cidr and description" "false"
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
