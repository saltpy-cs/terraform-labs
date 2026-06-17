#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TOTAL_POINTS=0
TOTAL_POSSIBLE=0
FAILURES=()

run_marker() {
  local script=$1
  local possible=$2
  local name="${script%.sh}"
  name="${name#mark_}"

  echo "Running ${script}..."
  OUTPUT=$("${SCRIPT_DIR}/${script}" 2>&1)
  SCORE=$(echo "${OUTPUT}" | grep '^Score:' | grep -o '[0-9]*' | head -1)
  POSSIBLE_CHECK=$(echo "${OUTPUT}" | grep '^Score:' | grep -o '[0-9]*' | tail -1)

  echo "${OUTPUT}"
  echo ""

  TOTAL_POINTS=$((TOTAL_POINTS + SCORE))
  TOTAL_POSSIBLE=$((TOTAL_POSSIBLE + possible))

  if [[ "${SCORE}" -lt "${possible}" ]]; then
    FAILURES+=("${name} (${SCORE}/${possible})")
  fi
}

echo "========================================"
echo " Terraform Practice Test — Full Results"
echo "========================================"
echo ""

run_marker mark_q01.sh 8
run_marker mark_q02.sh 8
run_marker mark_q03.sh 8
run_marker mark_q04.sh 8
run_marker mark_q05.sh 10
run_marker mark_q06.sh 10
run_marker mark_q07.sh 10
run_marker mark_q08.sh 10
run_marker mark_q09.sh 10
run_marker mark_q10.sh 6
run_marker mark_q11.sh 6
run_marker mark_q12.sh 6
run_marker mark_q13.sh 8
run_marker mark_q14.sh 6

echo "========================================"
echo " FINAL SCORE: ${TOTAL_POINTS}/${TOTAL_POSSIBLE}"

if [[ "${TOTAL_POINTS}" -ge 97 ]]; then
  echo " Result: DISTINCTION (>=97)"
elif [[ "${TOTAL_POINTS}" -ge 80 ]]; then
  echo " Result: PASS (>=80)"
elif [[ "${TOTAL_POINTS}" -ge 63 ]]; then
  echo " Result: NEAR MISS (>=63)"
else
  echo " Result: NEEDS MORE PRACTICE (<63)"
fi

if [[ "${#FAILURES[@]}" -gt 0 ]]; then
  echo ""
  echo " Incomplete questions:"
  for f in "${FAILURES[@]}"; do
    echo "   - ${f}"
  done
fi
echo "========================================"

if [[ "${TOTAL_POINTS}" -ge 80 ]]; then
  exit 0
else
  exit 1
fi
