# Trivy configuration

Scan configuration for the repository.

## Files

- `trivy.yaml` — scan **configuration**: severity thresholds, modules, and
  skip rules. Consumed by `.github/actions/scan` (`trivy fs --config …`) and
  `tools/ci/validate.sh` (`trivy config --config …`).
- Root `.trivyignore` — explicit **ignore rules** for known/intentional findings
  (e.g. the committed CA private key, test fixtures). Trivy auto-loads
  `.trivyignore` from the repo root.

## Notes

Keep the two separate: scan _behavior_ in `trivy.yaml`, finding _exceptions_ in
`.trivyignore`. Prefer fixing the root cause over widening the ignore list, and
review `.trivyignore` periodically.
