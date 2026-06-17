#!/usr/bin/env bash
set -euo pipefail

POINTS=0
TOTAL=10

Q05_DIR="$(dirname "$0")/../q05"
if [[ ! -d "${Q05_DIR}" ]]; then
  echo "Q05 — Writing and Calling a Module (${TOTAL} points)"
  echo "---"
  echo "  FAIL: q05 directory not found — create it and complete the question first"
  echo "---"
  echo "Score: 0/${TOTAL}"
  echo "Result: FAIL"
  exit 1
fi
Q05_DIR="$(cd "${Q05_DIR}" && pwd)"
ROOT_TF="${Q05_DIR}/main.tf"
MODULE_DIR="${Q05_DIR}/modules/tagger"

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

echo "Q05 — Writing and Calling a Module (${TOTAL} points)"
echo "---"

# 1. modules/tagger/ directory exists
check 1 "modules/tagger/ directory exists" \
  "$([[ -d "${MODULE_DIR}" ]] && echo true || echo false)"

# 2. module declares resource_name, environment, team variables
MODULE_TF=$(find "${MODULE_DIR}" -name '*.tf' 2>/dev/null | xargs cat 2>/dev/null || true)
HAS_RESOURCE_NAME=$(echo "${MODULE_TF}" | grep -q 'variable.*"resource_name"' && echo true || echo false)
HAS_ENVIRONMENT=$(echo "${MODULE_TF}" | grep -q 'variable.*"environment"' && echo true || echo false)
HAS_TEAM=$(echo "${MODULE_TF}" | grep -q 'variable.*"team"' && echo true || echo false)
check 1 "module declares resource_name, environment, and team variables" \
  "$([[ "${HAS_RESOURCE_NAME}" == "true" && "${HAS_ENVIRONMENT}" == "true" && "${HAS_TEAM}" == "true" ]] && echo true || echo false)"

# 3. module has output named "labels"
check 1 "module has output named \"labels\"" \
  "$(echo "${MODULE_TF}" | grep -q 'output.*"labels"' && echo true || echo false)"

# 4. module output contains all four required keys
HAS_NAME_KEY=$(echo "${MODULE_TF}" | grep -q 'name.*=.*var\.resource_name' && echo true || echo false)
HAS_ENV_KEY=$(echo "${MODULE_TF}" | grep -q 'environment.*=.*var\.environment' && echo true || echo false)
HAS_TEAM_KEY=$(echo "${MODULE_TF}" | grep -q 'team.*=.*var\.team' && echo true || echo false)
HAS_MANAGED=$(echo "${MODULE_TF}" | grep -q 'managed_by.*=.*"terraform"' && echo true || echo false)
check 1 "module output map contains name, environment, team, managed_by keys" \
  "$([[ "${HAS_NAME_KEY}" == "true" && "${HAS_ENV_KEY}" == "true" && "${HAS_TEAM_KEY}" == "true" && "${HAS_MANAGED}" == "true" ]] && echo true || echo false)"

# 5. root config calls module with source = "./modules/tagger"
check 1 "root config calls module with source \"./modules/tagger\"" \
  "$([[ -f "${ROOT_TF}" ]] && grep -q 'source.*=.*"./modules/tagger"' "${ROOT_TF}" && echo true || echo false)"

# 6. module called with correct values
HAS_WEB=$(grep -q 'resource_name.*=.*"web-server"' "${ROOT_TF}" 2>/dev/null && echo true || echo false)
HAS_PROD=$(grep -q 'environment.*=.*"prod"' "${ROOT_TF}" 2>/dev/null && echo true || echo false)
HAS_PLATFORM=$(grep -q 'team.*=.*"platform"' "${ROOT_TF}" 2>/dev/null && echo true || echo false)
check 1 "module called with web-server / prod / platform" \
  "$([[ "${HAS_WEB}" == "true" && "${HAS_PROD}" == "true" && "${HAS_PLATFORM}" == "true" ]] && echo true || echo false)"

# 7. null_resource.example declared
check 1 "null_resource \"example\" declared in root config" \
  "$([[ -f "${ROOT_TF}" ]] && grep -q 'resource.*"null_resource".*"example"' "${ROOT_TF}" && echo true || echo false)"

# 8. null_resource triggers reference module labels output
check 1 "null_resource triggers reference module.tagger.labels" \
  "$([[ -f "${ROOT_TF}" ]] && grep -q 'module\.tagger\.labels' "${ROOT_TF}" && echo true || echo false)"

# 9. output "labels" declared in root config
check 1 "output \"labels\" declared in root config" \
  "$([[ -f "${ROOT_TF}" ]] && grep -q 'output.*"labels"' "${ROOT_TF}" && echo true || echo false)"

# 10. terraform output labels contains all four required keys
if [[ -f "${Q05_DIR}/.terraform.lock.hcl" ]]; then
  OUTPUT=$(terraform -chdir="${Q05_DIR}" output -json labels 2>/dev/null || true)
  HAS_N=$(echo "${OUTPUT}" | grep -q '"name"' && echo true || echo false)
  HAS_E=$(echo "${OUTPUT}" | grep -q '"environment"' && echo true || echo false)
  HAS_T=$(echo "${OUTPUT}" | grep -q '"team"' && echo true || echo false)
  HAS_M=$(echo "${OUTPUT}" | grep -q '"managed_by"' && echo true || echo false)
  check 1 "terraform output labels contains name, environment, team, managed_by" \
    "$([[ "${HAS_N}" == "true" && "${HAS_E}" == "true" && "${HAS_T}" == "true" && "${HAS_M}" == "true" ]] && echo true || echo false)"
else
  check 1 "terraform output labels contains name, environment, team, managed_by" "false"
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
