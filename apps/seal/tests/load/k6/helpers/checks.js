export function smokeThresholds() {
  return {
    http_req_failed: [{ threshold: "rate<0.01", abortOnFail: true }],
    http_req_duration: [{ threshold: "p(95)<2000" }],
    iterations: [{ threshold: "count>0" }],
  };
}

export function loadThresholds() {
  return {
    http_req_failed: [{ threshold: "rate<0.01", abortOnFail: true }],
    http_req_duration: [
      { threshold: "p(95)<2000" },
      { threshold: "p(99)<5000" },
    ],
    http_reqs: [{ threshold: "rate>10" }],
  };
}

export function stressThresholds() {
  return {
    http_req_failed: [{ threshold: "rate<0.05" }],
    http_req_duration: [
      { threshold: "p(95)<5000" },
      { threshold: "p(99)<10000" },
    ],
  };
}

export function soakThresholds() {
  return {
    http_req_failed: [{ threshold: "rate<0.01" }],
    http_req_duration: [
      { threshold: "p(95)<2000" },
      { threshold: "p(99)<5000" },
    ],
    http_reqs: [{ threshold: "rate>5" }],
  };
}
