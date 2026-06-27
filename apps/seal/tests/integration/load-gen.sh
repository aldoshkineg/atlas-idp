#!/usr/bin/env bash
set -euo pipefail

API="http://localhost:8080/api/v1/documents"

echo "=== Generating load ==="

# 1. Create 50 valid documents in parallel (flood the queue)
echo "--- Creating 50 documents (flood) ---"
for i in $(seq 1 50); do
  curl -s -X POST "$API" \
    -H "Content-Type: application/json" \
    -d "{\"text\":\"load-test doc $i $(date +%s%N)\"}" \
    -o /dev/null -w "%{http_code} " &
done
wait
echo ""

# 2. Create documents with invalid payloads (400 errors)
echo "--- Sending 20 bad requests ---"
for i in $(seq 1 20); do
  curl -s -X POST "$API" \
    -H "Content-Type: application/json" \
    -d "not-json" \
    -o /dev/null -w "%{http_code} " &
done
wait
echo ""

# 3. Send requests to nonexistent IDs (404 errors)
echo "--- Sending 20 404 requests ---"
for i in $(seq 1 20); do
  curl -s -X GET "$API/nonexistent-$i-$(date +%s%N)" \
    -o /dev/null -w "%{http_code} " &
done
wait
echo ""

# 4. Fetch real documents (200s) - first need to get some IDs
echo "--- Fetching existing documents ---"
for id in $(curl -s "$API" 2>/dev/null | python3 -c "
import json,sys
try:
    docs=json.load(sys.stdin)
    for d in docs[:20]:
        print(d.get('id',''))
except:
    pass
" 2>/dev/null); do
  curl -s -X GET "$API/$id" -o /dev/null -w "%{http_code} " &
done
wait
echo ""

# 5. Image/pdf dump of large payloads
echo "--- Sending 10 large payloads ---"
# Generate a 10KB text payload
LARGE_TEXT=$(python3 -c "print('A'*10000)")
for i in $(seq 1 10); do
  curl -s -X POST "$API" \
    -H "Content-Type: application/json" \
    -d "{\"text\":\"$LARGE_TEXT $i\"}" \
    -o /dev/null -w "%{http_code} " &
done
wait
echo ""

echo "=== Load complete. Waiting for worker to process... ==="
echo ""

# Wait for queue to drain
for attempt in $(seq 1 30); do
  QLEN=$(redis-cli -p 6379 LLEN seal:jobs 2>/dev/null || echo "?")
  echo "  Queue: $QLEN jobs remaining (attempt $attempt/30)"
  if [ "$QLEN" = "0" ] || [ "$QLEN" = "?" ]; then
    break
  fi
  sleep 2
done

echo ""
echo "=== Queue drained. Ready to check Grafana ==="
