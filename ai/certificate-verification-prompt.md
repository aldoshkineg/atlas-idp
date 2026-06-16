# Certificate Verification Guide

## Objective

Verify that CA certificates used in this project are properly trusted by the system, and that TLS certificates signed by them are valid for browsers (especially Chrome).

## Certificate Locations

- Project CA: `clusters/kind/certs/ca.crt`
- Project CA key: `clusters/kind/certs/ca.key`
- System trust store (user-added): `/usr/local/share/ca-certificates/`
- System trust store (bundled): `/etc/ssl/certs/`

## GitHub Secrets Usage

The CA certificate and key are stored as GitHub repository secrets for use in CI/CD:

| Secret       | Source File                  | Created Via                                                                        |
| ------------ | ---------------------------- | ---------------------------------------------------------------------------------- |
| `DEV_CA_CRT` | `clusters/kind/certs/ca.crt` | `make github-secrets-ca` → `gh secret set DEV_CA_CRT < clusters/kind/certs/ca.crt` |
| `DEV_CA_KEY` | `clusters/kind/certs/ca.key` | `make github-secrets-ca` → `gh secret set DEV_CA_KEY < clusters/kind/certs/ca.key` |

**How they are consumed in CI/CD:**

1. `.github/workflows/ci.yaml` passes both secrets to the `terraform-kind` composite action
2. `.github/actions/terraform-kind/action.yml` uses them to create a Kubernetes TLS secret in the cluster:
   ```yaml
   kubectl create secret tls dev-ca-secret \
   --cert=<(echo "${{ inputs.dev_ca_crt }}") \
   --key=<(echo "${{ inputs.dev_ca_key }}") \
   -n cert-manager \
   --dry-run=client -o yaml | kubectl apply -f -
   ```
3. The resulting Kubernetes secret `dev-ca-secret` in namespace `cert-manager` is used as a CA issuer by cert-manager to sign certificates for in-cluster services (Ingress, etc.)

**Check secrets via CLI:**

```bash
gh secret list
```

## Verification Steps

### 1. Check if CA is trusted by the system

```bash
# Get the CA fingerprint
openssl x509 -in clusters/kind/certs/ca.crt -fingerprint -sha256 -noout

# Search system trust store for matching fingerprint
for f in /usr/local/share/ca-certificates/*.crt; do
  if sudo openssl x509 -in "$f" -fingerprint -sha256 -noout 2>/dev/null | grep -q "<FINGERPRINT>"; then
    echo "FOUND: $f"
  fi
done

# Or compare directly (if cert might be identical)
sudo diff /usr/local/share/ca-certificates/<file>.crt clusters/kind/certs/ca.crt
```

### 2. Check certificate details (SAN, validity, issuer)

```bash
openssl x509 -in <cert>.crt -text -noout | grep -A5 "Subject Alternative Name"
openssl x509 -in <cert>.crt -text -noout | grep -E "Not Before|Not After"
openssl x509 -in <cert>.crt -subject -issuer -noout
```

### 3. Add CA to system trust store

```bash
sudo cp clusters/kind/certs/ca.crt /usr/local/share/ca-certificates/<name>.crt
sudo update-ca-certificates --fresh
```

### 4. Remove CA from system trust store

```bash
sudo rm /usr/local/share/ca-certificates/<name>.crt
sudo update-ca-certificates --fresh
```

### 5. Generate a server certificate signed by the CA

Create an OpenSSL config with proper `subjectAltName` (required by Chrome):

```ini
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = RU
ST = Moscow
L = MSK
O = Test
CN = localhost

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
```

```bash
openssl genrsa -out /tmp/server.key 2048
openssl req -new -key /tmp/server.key -out /tmp/server.csr -config openssl-san.cnf
openssl x509 -req -in /tmp/server.csr \
  -CA clusters/kind/certs/ca.crt \
  -CAkey clusters/kind/certs/ca.key \
  -CAcreateserial -out /tmp/server.crt \
  -days 365 -sha256 \
  -extensions v3_req -extfile openssl-san.cnf
```

### 6. Start a test HTTPS server

```bash
nohup python3 -c "
import ssl, http.server
ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
ctx.load_cert_chain('/tmp/server.crt', '/tmp/server.key')
server = http.server.HTTPServer(('0.0.0.0', 4443), http.server.SimpleHTTPRequestHandler)
server.socket = ctx.wrap_socket(server.socket, server_side=True)
server.serve_forever()
" &
```

### 7. Test TLS validation

```bash
# Verbose check — look for "SSL certificate verified" or error
curl -sv https://localhost:4443/ 2>&1 | grep -iE "verify result|subject|issuer|subjectAltName|error"
```

- `OpenSSL verify result: 0` — certificate is valid
- `exit code 60` or `unable to get local issuer certificate` — CA not trusted

### 8. Chrome-specific notes

Chrome on Linux uses the system trust store (`/etc/ssl/certs/`), but may cache it at startup. After adding a new CA:

1. Fully restart Chrome (all windows)
2. Open `chrome://net-internals/#hsts` and check/clear localhost HSTS if needed
3. Use Incognito mode to bypass certificate cache
4. If still not trusted, verify the certificate has `subjectAltName` with `DNS:localhost` — Chrome rejects certificates without SAN

## Common Issues

| Issue                                            | Cause                        | Fix                              |
| ------------------------------------------------ | ---------------------------- | -------------------------------- |
| `unable to get local issuer certificate`         | CA not in system trust store | Add via `update-ca-certificates` |
| `certificate has expired`                        | Cert validity passed         | Regenerate with longer `-days`   |
| `IP mismatch` / `hostname mismatch`              | CN or SAN doesn't match URL  | Add `DNS:localhost` to SAN       |
| Chrome shows "NET::ERR_CERT_COMMON_NAME_INVALID" | Missing SAN extension        | Regenerate with SAN config       |
