#!/usr/bin/env bash
set -euo pipefail

SCENARIO="${1:-smoke}"
REPORT_DIR="${PWD}/${2:-reports}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIO_FILE="${SCRIPT_DIR}/scenarios/${SCENARIO}.js"

if [ ! -f "$SCENARIO_FILE" ]; then
  echo "Usage: $0 {smoke|load|stress|soak} [report-dir]"
  echo "  Available scenarios:"
  for f in "${SCRIPT_DIR}/scenarios/"*.js; do
    name=$(basename "$f" .js)
    echo "    - $name"
  done
  exit 1
fi

mkdir -p "$REPORT_DIR" && chmod 777 "$REPORT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${REPORT_DIR}/${SCENARIO}-${TIMESTAMP}.json"
SUMMARY_FILE="${REPORT_DIR}/${SCENARIO}-${TIMESTAMP}.summary.txt"

echo "========================================"
echo "  Scenario: ${SCENARIO}"
echo "  Report:   ${REPORT_FILE}"
echo "========================================"
echo ""

docker run --rm --network=host \
  -v "${SCRIPT_DIR}:/scripts:ro" \
  -v "${REPORT_DIR}:/reports:rw" \
  -e SEAL_API_URL="${SEAL_API_URL:-http://localhost:8080}" \
  grafana/k6:latest run \
    --out json="/reports/$(basename "$REPORT_FILE")" \
    --summary-export="/reports/$(basename "$SUMMARY_FILE")" \
    "/scripts/scenarios/${SCENARIO}.js"
