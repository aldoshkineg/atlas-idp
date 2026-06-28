// Package vault provides Vault API access via the vault-0 k8s pod.
package vault

import (
	"bytes"
	"fmt"
	"os/exec"
	"strings"
)

const (
	vaultNamespace = "vault"
	vaultPod       = "vault-0"
	vaultAddress    = "http://127.0.0.1:8200"
)

type Client struct {
	kubectlPath string
}

func New() *Client {
	return &Client{kubectlPath: "kubectl"}
}

func (c *Client) KVPut(path string, data map[string]string) error {
	if len(data) == 0 {
		return fmt.Errorf("no data to write")
	}

	token, err := c.readRootToken()
	if err != nil {
		return fmt.Errorf("read vault root token: %w", err)
	}

	args := []string{"exec", "-n", vaultNamespace, vaultPod, "--",
		"env", "VAULT_TOKEN=" + token, "VAULT_ADDR=" + vaultAddress,
		"vault", "kv", "put", path,
	}
	for k, v := range data {
		args = append(args, fmt.Sprintf("%s=%s", k, v))
	}

	cmd := exec.Command(c.kubectlPath, args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("vault kv put %s: %s: %w", path, strings.TrimSpace(stderr.String()), err)
	}
	return nil
}

func (c *Client) KVGet(path string) (map[string]string, error) {
	token, err := c.readRootToken()
	if err != nil {
		return nil, err
	}

	out, err := c.execVault(token, "kv", "get", "-format=json", path)
	if err != nil {
		return nil, fmt.Errorf("vault kv get %s: %w", path, err)
	}
	_ = out
	return nil, fmt.Errorf("Vault KV get not implemented yet: see vault API client")
}

func (c *Client) readRootToken() (string, error) {
	cmd := exec.Command(c.kubectlPath, "get", "secret", "-n", vaultNamespace, "vault-unseal-keys",
		"-o", "jsonpath={.data.vault-root}")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("get vault root token: %s: %w", strings.TrimSpace(stderr.String()), err)
	}
	token := strings.TrimSpace(stdout.String())
	if token == "" {
		return "", fmt.Errorf("vault root token is empty")
	}

	decoded, err := base64Decode(token)
	if err != nil {
		return "", fmt.Errorf("decode vault token: %w", err)
	}
	return decoded, nil
}

func (c *Client) execVault(token, subcommand string, args ...string) (string, error) {
	cmdArgs := []string{"exec", "-n", vaultNamespace, vaultPod, "--",
		"env", "VAULT_TOKEN=" + token, "VAULT_ADDR=" + vaultAddress,
		"vault", subcommand,
	}
	cmdArgs = append(cmdArgs, args...)

	cmd := exec.Command(c.kubectlPath, cmdArgs...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("vault %s: %s: %w", subcommand, strings.TrimSpace(stderr.String()), err)
	}
	return stdout.String(), nil
}

func base64Decode(s string) (string, error) {
	cmd := exec.Command("base64", "-d")
	cmd.Stdin = strings.NewReader(s)
	var out bytes.Buffer
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("base64 decode: %w", err)
	}
	return strings.TrimSpace(out.String()), nil
}
