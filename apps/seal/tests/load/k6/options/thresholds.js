import { smokeThresholds } from "../helpers/checks.js";

export const smokeOptions = {
  vus: 1,
  iterations: 10,
  thresholds: smokeThresholds(),
};

export const loadOptions = {
  stages: [
    { duration: "30s", target: 10 },
    { duration: "1m", target: 10 },
    { duration: "30s", target: 50 },
    { duration: "2m", target: 50 },
    { duration: "30s", target: 0 },
  ],
  thresholds: {
    http_req_failed: [{ threshold: "rate<0.01", abortOnFail: true }],
    http_req_duration: [
      { threshold: "p(95)<2000" },
      { threshold: "p(99)<5000" },
    ],
    http_reqs: [{ threshold: "rate>10" }],
  },
};

export const stressOptions = {
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

export const soakOptions = {
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
