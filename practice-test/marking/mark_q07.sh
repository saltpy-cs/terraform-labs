#!/usr/bin/env bash
set -euo pipefail

POINTS=0
TOTAL=10

Q07_DIR="$(dirname "$0")/../q07"
if [[ ! -d "${Q07_DIR}" ]]; then
  echo "Q07 — templatefile() Function (${TOTAL} points)"
  echo "---"
  echo "  FAIL: q07 directory not found — create it and complete the question first"
  echo "---"
  echo "Score: 0/${TOTAL}"
  echo "Result: FAIL"
  exit 1
fi
Q07_DIR="$(cd "${Q07_DIR}" && pwd)"
MAIN_TF="${Q07_DIR}/main.tf"
TEMPLATE="${Q07_DIR}/startup.sh.tpl"

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

echo "Q07 — templatefile() Function (${TOTAL} points)"
echo "---"

# 1. startup.sh.tpl exists in q07 directory
check 1 "startup.sh.tpl exists in q07 directory" \
  "$([[ -f "${TEMPLATE}" ]] && echo true || echo false)"

# 2. templatefile() function used in config
check 1 "templatefile() function used" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'templatefile(' "${MAIN_TF}" && echo true || echo false)"

# 3. template path references startup.sh.tpl
check 1 "templatefile() references startup.sh.tpl" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'startup\.sh\.tpl' "${MAIN_TF}" && echo true || echo false)"

# 4. env = "production" passed
check 1 "env = \"production\" passed to templatefile()" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'env.*=.*"production"' "${MAIN_TF}" && echo true || echo false)"

# 5. project = "my-app" passed
check 1 "project = \"my-app\" passed to templatefile()" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'project.*=.*"my-app"' "${MAIN_TF}" && echo true || echo false)"

# 6. result stored in a locals block
check 1 "result stored in a locals block" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'locals' "${MAIN_TF}" && echo true || echo false)"

# 7. output "rendered_script" declared
check 1 "output \"rendered_script\" declared" \
  "$([[ -f "${MAIN_TF}" ]] && grep -q 'output.*"rendered_script"' "${MAIN_TF}" && echo true || echo false)"

# 8. output value references local (not templatefile directly)
check 1 "output value references local" \
  "$([[ -f "${MAIN_TF}" ]] && grep -A3 'output.*"rendered_script"' "${MAIN_TF}" | grep -q 'local\.' && echo true || echo false)"

# 9. terraform init has been run
check 1 "terraform init has been run" \
  "$([[ -f "${Q07_DIR}/.terraform.lock.hcl" ]] && echo true || echo false)"

# 10. rendered output contains "Running my-app in production"
if [[ -f "${Q07_DIR}/.terraform.lock.hcl" ]]; then
  OUTPUT=$(terraform -chdir="${Q07_DIR}" output -raw rendered_script 2>/dev/null || true)
  check 1 "rendered_script contains \"Running my-app in production\"" \
    "$(echo "${OUTPUT}" | grep -q 'Running my-app in production' && echo true || echo false)"
else
  check 1 "rendered_script contains \"Running my-app in production\"" "false"
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
