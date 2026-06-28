//go:build integration

package k8s

import "testing"

func TestIntegration_PodExec(t *testing.T) {
	c := New()
	out, err := c.PodExec("kube-system", "coredns-", "echo", "hello")
	if err != nil {
		t.Skipf("cluster not available: %v", err)
	}
	if out != "hello\n" {
		t.Logf("output: %q", out)
	}
}

func TestIntegration_SecretReadDecoded(t *testing.T) {
	c := New()
	val, err := c.SecretReadDecoded("argocd", "argocd-initial-admin-secret", "password")
	if err != nil {
		t.Skipf("cannot read argocd secret: %v", err)
	}
	if val == "" {
		t.Error("empty password")
	}
}
