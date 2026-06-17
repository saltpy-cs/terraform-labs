#!/usr/bin/env bash
set -euo pipefail

Q01_DIR="$(cd "$(dirname "$0")/../q01" && pwd)"
EXPECTED_FILE="${Q01_DIR}/tf-practice.txt"
EXPECTED_CONTENT="Terraform Associate"

PASS=true

if [[ ! -f "${EXPECTED_FILE}" ]]; then
  echo "FAIL: file not found at ${EXPECTED_FILE}"
  PASS=false
else
  ACTUAL=$(cat "${EXPECTED_FILE}")
  if [[ "${ACTUAL}" == "${EXPECTED_CONTENT}" ]]; then
    echo "PASS: ${EXPECTED_FILE} contains '${EXPECTED_CONTENT}'"
  else
    echo "FAIL: expected '${EXPECTED_CONTENT}', got '${ACTUAL}'"
    PASS=false
  fi
fi

if [[ "${PASS}" == "true" ]]; then
  exit 0
else
  exit 1
fi
