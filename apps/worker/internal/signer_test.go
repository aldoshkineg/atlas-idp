package internal

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestSignVerifyRoundTrip(t *testing.T) {
	caPath, certPath, keyPath := generateTestChain(t)
	defer os.Remove(caPath)
	defer os.Remove(certPath)
	defer os.Remove(keyPath)

	signer, err := NewSigner(context.Background(), certPath, keyPath)
	if err != nil {
		t.Fatalf("NewSigner() error = %v", err)
	}

	caBlock, _ := pem.Decode([]byte(mustReadFile(t, caPath)))
	caCert, _ := x509.ParseCertificate(caBlock.Bytes)

	pdfData, err := GeneratePDF("Test PDF for signing")
	if err != nil {
		t.Fatalf("GeneratePDF() error = %v", err)
	}

	signed, err := signer.Sign(context.Background(), pdfData)
	if err != nil {
		t.Fatalf("Sign() error = %v", err)
	}

	if len(signed) == 0 {
		t.Fatal("Sign() returned empty data")
	}

	if len(signed) <= len(pdfData) {
		t.Fatal("signed PDF should be larger than unsigned")
	}

	result := VerifyPDFSignature(signed, caCert)
	if !result.Valid {
		t.Fatalf("expected valid signature, got error: %s", result.Error)
	}
	if result.Subject != "Atlas IDP PDF Signer" {
		t.Fatalf("expected subject 'Atlas IDP PDF Signer', got %q", result.Subject)
	}
	if result.Issuer != "Atlas IDP Test CA" {
		t.Fatalf("expected issuer 'Atlas IDP Test CA', got %q", result.Issuer)
	}
	if result.SigningTime == "" {
		t.Fatal("expected signing time to be set")
	}
}

func TestSignVerifyTamperedData(t *testing.T) {
	caPath, certPath, keyPath := generateTestChain(t)
	defer os.Remove(caPath)
	defer os.Remove(certPath)
	defer os.Remove(keyPath)

	signer, err := NewSigner(context.Background(), certPath, keyPath)
	if err != nil {
		t.Fatalf("NewSigner() error = %v", err)
	}

	caBlock, _ := pem.Decode([]byte(mustReadFile(t, caPath)))
	caCert, _ := x509.ParseCertificate(caBlock.Bytes)

	pdfData, err := GeneratePDF("Test PDF for signing")
	if err != nil {
		t.Fatalf("GeneratePDF() error = %v", err)
	}

	signed, err := signer.Sign(context.Background(), pdfData)
	if err != nil {
		t.Fatalf("Sign() error = %v", err)
	}

	tampered := make([]byte, len(signed))
	copy(tampered, signed)
	mid := len(tampered) / 2
	tampered[mid] ^= 0xFF

	result := VerifyPDFSignature(tampered, caCert)
	if result.Valid {
		t.Fatal("expected tampered PDF to be invalid")
	}
}

func TestSignVerifyWithUntrustedCACert(t *testing.T) {
	caPath, certPath, keyPath := generateTestChain(t)
	defer os.Remove(caPath)
	defer os.Remove(certPath)
	defer os.Remove(keyPath)

	signer, err := NewSigner(context.Background(), certPath, keyPath)
	if err != nil {
		t.Fatalf("NewSigner() error = %v", err)
	}

	pdfData, err := GeneratePDF("Test PDF")
	if err != nil {
		t.Fatalf("GeneratePDF() error = %v", err)
	}

	signed, err := signer.Sign(context.Background(), pdfData)
	if err != nil {
		t.Fatalf("Sign() error = %v", err)
	}

	otherCAPath, _, _ := generateTestChain(t)
	defer os.Remove(otherCAPath)
	otherBlock, _ := pem.Decode([]byte(mustReadFile(t, otherCAPath)))
	otherCA, _ := x509.ParseCertificate(otherBlock.Bytes)

	result := VerifyPDFSignature(signed, otherCA)
	if result.Valid {
		t.Fatal("expected verification with wrong CA to fail")
	}
}

func generateTestChain(t *testing.T) (caPath, certPath, keyPath string) {
	t.Helper()

	caKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate CA key: %v", err)
	}

	leafKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate leaf key: %v", err)
	}

	caTemplate := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "Atlas IDP Test CA"},
		NotBefore:             time.Now().Add(-1 * time.Hour),
		NotAfter:              time.Now().Add(10 * 365 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
	}

	caDER, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &caKey.PublicKey, caKey)
	if err != nil {
		t.Fatalf("create CA cert: %v", err)
	}
	caCert, err := x509.ParseCertificate(caDER)
	if err != nil {
		t.Fatalf("parse CA cert: %v", err)
	}

	leafTemplate := &x509.Certificate{
		SerialNumber:          big.NewInt(2),
		Subject:               pkix.Name{CommonName: "Atlas IDP PDF Signer"},
		NotBefore:             time.Now().Add(-1 * time.Hour),
		NotAfter:              time.Now().Add(10 * 365 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageCodeSigning},
	}

	leafDER, err := x509.CreateCertificate(rand.Reader, leafTemplate, caCert, &leafKey.PublicKey, caKey)
	if err != nil {
		t.Fatalf("create leaf cert: %v", err)
	}

	dir := t.TempDir()

	caPath = filepath.Join(dir, "ca.crt")
	certPath = filepath.Join(dir, "signer.crt")
	keyPath = filepath.Join(dir, "signer.key")

	writePEM(t, caPath, "CERTIFICATE", caDER)
	writePEM(t, certPath, "CERTIFICATE", leafDER)
	writePEM(t, keyPath, "RSA PRIVATE KEY", x509.MarshalPKCS1PrivateKey(leafKey))

	return caPath, certPath, keyPath
}

func writePEM(t *testing.T, path, blockType string, bytes []byte) {
	t.Helper()
	f, err := os.Create(path)
	if err != nil {
		t.Fatalf("create %s: %v", path, err)
	}
	defer f.Close()
	if err := pem.Encode(f, &pem.Block{Type: blockType, Bytes: bytes}); err != nil {
		t.Fatalf("encode %s: %v", path, err)
	}
}

func mustReadFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read file %s: %v", path, err)
	}
	return string(data)
}
