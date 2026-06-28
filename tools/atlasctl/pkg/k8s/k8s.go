// Package k8s provides a shell-based kubectl wrapper for pod exec, secret reads, and namespace checks.
package k8s

import (
	"bytes"
	"fmt"
	"os/exec"
	"strings"
)

type Client struct {
	kubectlPath string
}

func New() *Client {
	return &Client{kubectlPath: "kubectl"}
}

func (c *Client) PodExec(namespace, pod string, args ...string) (string, error) {
	cmdArgs := []string{"exec", "-n", namespace, pod, "--"}
	cmdArgs = append(cmdArgs, args...)
	return c.run(cmdArgs...)
}

func (c *Client) SecretRead(namespace, name, jsonPath string) (string, error) {
	out, err := c.run("get", "secret", "-n", namespace, name, "-o", "jsonpath={.data."+jsonPath+"}")
	if err != nil {
		return "", fmt.Errorf("read secret %s/%s key %s: %w", namespace, name, jsonPath, err)
	}
	return strings.TrimSpace(out), nil
}

func (c *Client) SecretReadDecoded(namespace, name, jsonPath string) (string, error) {
	encoded, err := c.SecretRead(namespace, name, jsonPath)
	if err != nil {
		return "", err
	}
	if encoded == "" {
		return "", nil
	}
	return base64Decode(encoded)
}

func (c *Client) GetPodName(namespace, labelSelector string) (string, error) {
	out, err := c.run("get", "pod", "-n", namespace, "-l", labelSelector, "-o", "jsonpath={.items[0].metadata.name}")
	if err != nil {
		return "", fmt.Errorf("get pod %s/%s: %w", namespace, labelSelector, err)
	}
	return strings.TrimSpace(out), nil
}

func (c *Client) NamespaceExists(namespace string) (bool, error) {
	out, err := c.run("get", "namespace", namespace, "-o", "name")
	if err != nil {
		return false, nil
	}
	return strings.TrimSpace(out) != "", nil
}

func (c *Client) PodLogs(namespace, pod string, tail int) (string, error) {
	tailStr := fmt.Sprintf("%d", tail)
	return c.run("logs", "-n", namespace, pod, "--tail="+tailStr)
}

func (c *Client) run(args ...string) (string, error) {
	cmd := exec.Command(c.kubectlPath, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("kubectl %s: %s: %w", strings.Join(args, " "), strings.TrimSpace(stderr.String()), err)
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
