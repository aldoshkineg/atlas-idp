import { check, group } from "k6";

import {
  createDocument,
  pollDocument,
  getDownloadUrl,
  verifyDocument,
} from "../helpers/client.js";

export const options = {
  stages: [
    { duration: "1m", target: 10 },
    { duration: "1m", target: 25 },
    { duration: "1m", target: 50 },
    { duration: "1m", target: 100 },
    { duration: "1m", target: 0 },
  ],
  thresholds: {
    http_req_failed: [{ threshold: "rate<0.05" }],
    http_req_duration: [
      { threshold: "p(95)<5000" },
      { threshold: "p(99)<10000" },
    ],
  },
};

export default function () {
  group("full document lifecycle", function () {
    const text = `stress-test-${__VU}-${Date.now()}`;

    const id = createDocument(text);
    if (!id) {
      check(null, { "created document": false });
      return;
    }

    const doc = pollDocument(id);
    check(doc, { "document completed": (d) => d && d.status === "completed" });
    if (!doc || doc.status !== "completed") return;

    const url = getDownloadUrl(id);
    check(url, { "download url exists": (u) => u !== null });

    const verify = verifyDocument(id);
    check(verify, { "verification passed": (v) => v && v.valid === true });
  });
}
