//go:build integration

package vault

import "testing"

func TestIntegration_ReadRootToken(t *testing.T) {
	c := New()
	token, err := c.readRootToken()
	if err != nil {
		t.Skipf("vault not available: %v", err)
	}
	if token == "" {
		t.Error("empty vault token")
	}
}

func TestIntegration_KVPut(t *testing.T) {
	c := New()
	err := c.KVPut("secret/test/atlasctl-integration", map[string]string{
		"test_key": "test_value",
	})
	if err != nil {
		t.Skipf("vault kv put failed: %v", err)
	}
}
