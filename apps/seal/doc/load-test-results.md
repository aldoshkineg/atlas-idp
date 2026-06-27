# Load Test Results

## Environment

- **Stack:** Docker Compose (Postgres 17, Redis 7, MinIO, seal-api, seal-worker, seal-ui)
- **Tool:** [k6](https://k6.io/) via `grafana/k6:latest` Docker image
- **API endpoint:** `http://localhost:8080`
- **Date:** 2026-06-27

---

## Smoke Test (sanity check)

| Parameter  | Value |
| ---------- | ----- |
| Duration   | 5.3s  |
| VUs        | 1     |
| Iterations | 10    |

### Results

| Check             | Rate             |
| ----------------- | ---------------- |
| Checks passed     | **100%** (70/70) |
| HTTP failures     | **0%**           |
| Avg response time | 4.78ms           |
| p95 response time | 13.95ms          |
| Max response time | 17.13ms          |

**Thresholds:**

- `http_req_failed` < 1% → PASS
- `http_req_duration` p95 < 2000ms → PASS

---

## Load Test

| Parameter        | Value  |
| ---------------- | ------ |
| Duration         | 4m30s  |
| Max VUs          | 50     |
| Total iterations | 11,220 |
| Total requests   | 60,707 |

### Ramp-up profile

| Stage | Duration | Target VUs |
| ----- | -------- | ---------- |
| 1     | 30s      | 10         |
| 2     | 1m       | 10         |
| 3     | 30s      | 50         |
| 4     | 2m       | 50         |
| 5     | 30s      | 0          |

### Results

| Check         | Rate                     |
| ------------- | ------------------------ |
| Checks passed | **100%** (78,540/78,540) |
| HTTP failures | **0%**                   |

### Latency

| Metric  | Value       |
| ------- | ----------- |
| Average | 7.32ms      |
| Median  | 4.27ms      |
| p90     | 13.99ms     |
| **p95** | **19.57ms** |
| **p99** | **39.94ms** |
| Max     | 460.06ms    |

### Throughput

| Metric         | Value            |
| -------------- | ---------------- |
| Requests/sec   | **224.49**       |
| Iterations/sec | 41.49            |
| Data received  | 23 MB (86 kB/s)  |
| Data sent      | 8.2 MB (31 kB/s) |

### Iteration timing

| Metric  | Value    |
| ------- | -------- |
| Average | 750.02ms |
| Median  | 549.03ms |
| p95     | 1.08s    |
| Max     | 1.63s    |

### Full document lifecycle per iteration

Each iteration executed:

1. `POST /api/v1/documents` → creates document, pushes job to Redis
2. `GET /api/v1/documents/{id}` (polling) → waits until status becomes `completed`
3. `GET /api/v1/documents/{id}/download` → fetches download URL
4. `GET /api/v1/documents/{id}/verify` → confirms signed PDF is valid

**Thresholds:**

- `http_req_failed` < 1% → PASS
- `http_req_duration` p95 < 2000ms → PASS
- `http_req_duration` p99 < 5000ms → PASS
- `http_reqs` > 10 req/s → PASS

---

## Summary

The Seal platform (API + Worker + DB + Queue + Object Storage) handled all load profiles with zero errors:

| Test   | Max VUs | Duration | Requests | Req/s     | p95         | p99         | Errors |
| ------ | ------- | -------- | -------- | --------- | ----------- | ----------- | ------ |
| Smoke  | 1       | 5.3s     | 50       | 9.5       | 13.95ms     | —           | 0%     |
| Load   | 50      | 4m30s    | 60,707   | **224.5** | **19.57ms** | **39.94ms** | 0%     |
| Stress | 100     | 5m       | 91,646   | **305.3** | **10.69ms** | **37.44ms** | 0%     |
| Soak   | 20      | 6m       | 60,316   | **167.5** | **6.48ms**  | **25.33ms** | 0%     |

Key observations:

- **No breaking point found** at up to 100 concurrent VUs (the theoretical maximum for this Docker Compose setup on a single machine)
- p95 latency remained under **20ms** across all tests
- p99 latency stayed under **40ms** even at peak load
- Total documents processed in ~15 minutes: **40,851** across all tests
- Soak test showed no degradation over 5 minutes of sustained load — no memory leaks or queue buildup detected
