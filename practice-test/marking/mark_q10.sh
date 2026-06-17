#!/usr/bin/env bash
set -euo pipefail

POINTS=0
TOTAL=6

Q10_DIR="$(dirname "$0")/../q10"
if [[ ! -d "${Q10_DIR}" ]]; then
  echo "Q10 — Workspaces (${TOTAL} points)"
  echo "---"
  echo "  FAIL: q10 directory not found — create it and complete the question first"
  echo "---"
  echo "Score: 0/${TOTAL}"
  echo "Result: FAIL"
  exit 1
fi
Q10_DIR="$(cd "${Q10_DIR}" && pwd)"
MAIN_TF="${Q10_DIR}/main.tf"

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

echo "Q10 — Workspaces (${TOTAL} points)"
echo "---"

# 1. null_resource.env_marker declared
check 1 "null_resource \"env_marker\" declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'resource.*"null_resource".*"env_marker"' "${MAIN_TF}" && echo true || echo false)"

# 2. trigger uses terraform.workspace
check 1 "trigger uses terraform.workspace" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'terraform\.workspace' "${MAIN_TF}" && echo true || echo false)"

# 3-5. workspaces dev, staging, prod exist
if [[ -f "${Q10_DIR}/.terraform.lock.hcl" ]]; then
  WORKSPACES=$(terraform -chdir="${Q10_DIR}" workspace list 2>/dev/null || true)
  check 1 "workspace \"dev\" exists" \
    "$(echo "${WORKSPACES}" | grep -q 'dev' && echo true || echo false)"
  check 1 "workspace \"staging\" exists" \
    "$(echo "${WORKSPACES}" | grep -q 'staging' && echo true || echo false)"
  check 1 "workspace \"prod\" exists" \
    "$(echo "${WORKSPACES}" | grep -q 'prod' && echo true || echo false)"
else
  check 1 "workspace \"dev\" exists" "false"
  check 1 "workspace \"staging\" exists" "false"
  check 1 "workspace \"prod\" exists" "false"
fi

# 6. each workspace has null_resource.env_marker in its state
if [[ -f "${Q10_DIR}/.terraform.lock.hcl" ]]; then
  CURRENT=$(terraform -chdir="${Q10_DIR}" workspace show 2>/dev/null || true)
  DEV_STATE=$(terraform -chdir="${Q10_DIR}" workspace select dev 2>/dev/null && terraform -chdir="${Q10_DIR}" state list 2>/dev/null || true)
  STG_STATE=$(terraform -chdir="${Q10_DIR}" workspace select staging 2>/dev/null && terraform -chdir="${Q10_DIR}" state list 2>/dev/null || true)
  PRD_STATE=$(terraform -chdir="${Q10_DIR}" workspace select prod 2>/dev/null && terraform -chdir="${Q10_DIR}" state list 2>/dev/null || true)
  terraform -chdir="${Q10_DIR}" workspace select "${CURRENT}" >/dev/null 2>&1 || true
  HAS_DEV=$(echo "${DEV_STATE}" | grep -q 'null_resource\.env_marker' && echo true || echo false)
  HAS_STG=$(echo "${STG_STATE}" | grep -q 'null_resource\.env_marker' && echo true || echo false)
  HAS_PRD=$(echo "${PRD_STATE}" | grep -q 'null_resource\.env_marker' && echo true || echo false)
  check 1 "each workspace has null_resource.env_marker in its state" \
    "$([[ "${HAS_DEV}" == "true" && "${HAS_STG}" == "true" && "${HAS_PRD}" == "true" ]] && echo true || echo false)"
else
  check 1 "each workspace has null_resource.env_marker in its state" "false"
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
