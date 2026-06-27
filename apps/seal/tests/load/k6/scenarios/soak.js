import { check, group } from "k6";

import {
  createDocument,
  pollDocument,
  getDownloadUrl,
  verifyDocument,
} from "../helpers/client.js";

export const options = {
  stages: [
    { duration: "30s", target: 20 },
    { duration: "5m", target: 20 },
    { duration: "30s", target: 0 },
  ],
  thresholds: {
    http_req_failed: [{ threshold: "rate<0.01" }],
    http_req_duration: [
      { threshold: "p(95)<2000" },
      { threshold: "p(99)<5000" },
    ],
    http_reqs: [{ threshold: "rate>5" }],
  },
};

export default function () {
  group("full document lifecycle", function () {
    const text = `soak-test-${__VU}-${Date.now()}`;

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
