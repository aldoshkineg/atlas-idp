import { check } from "k6";

import {
  createDocument,
  pollDocument,
  getDownloadUrl,
  verifyDocument,
} from "../helpers/client.js";

export const options = {
  vus: 1,
  iterations: 10,
  thresholds: {
    http_req_failed: [{ threshold: "rate<0.01", abortOnFail: true }],
    http_req_duration: [{ threshold: "p(95)<2000" }],
  },
};

export default function () {
  const text = `smoke-test-${Date.now()}-${__VU}`;
  const id = createDocument(text);
  if (!id) return;

  const doc = pollDocument(id);
  check(doc, { "document completed": (d) => d && d.status === "completed" });
  if (!doc || doc.status !== "completed") return;

  const url = getDownloadUrl(id);
  check(url, { "download url exists": (u) => u !== null });

  const verify = verifyDocument(id);
  check(verify, { "verification passed": (v) => v && v.valid === true });
}
