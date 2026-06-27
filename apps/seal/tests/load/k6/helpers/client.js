import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.SEAL_API_URL || "http://localhost:8080";

export function createDocument(text) {
  const url = `${BASE_URL}/api/v1/documents`;
  const payload = JSON.stringify({ text });
  const params = { headers: { "Content-Type": "application/json" } };

  const res = http.post(url, payload, params);
  check(res, {
    "create status is 201": (r) => r.status === 201,
    "create has id": (r) => {
      try {
        return JSON.parse(r.body).id !== undefined;
      } catch {
        return false;
      }
    },
  });
  return res.status === 201 ? JSON.parse(res.body).id : null;
}

export function pollDocument(id, timeoutMs = 30000, intervalMs = 500) {
  const url = `${BASE_URL}/api/v1/documents/${id}`;
  const start = Date.now();

  while (Date.now() - start < timeoutMs) {
    const res = http.get(url);
    if (res.status === 200) {
      const doc = JSON.parse(res.body);
      if (doc.status === "completed") return doc;
      if (doc.status === "failed") return doc;
    }
    sleep(intervalMs / 1000);
  }
  return null;
}

export function getDownloadUrl(id) {
  const url = `${BASE_URL}/api/v1/documents/${id}/download`;
  const res = http.get(url);
  check(res, { "download status is 200": (r) => r.status === 200 });
  return res.status === 200 ? JSON.parse(res.body).url : null;
}

export function verifyDocument(id) {
  const url = `${BASE_URL}/api/v1/documents/${id}/verify`;
  const res = http.get(url);
  check(res, { "verify status is 200": (r) => r.status === 200 });
  return res.status === 200 ? JSON.parse(res.body) : null;
}
