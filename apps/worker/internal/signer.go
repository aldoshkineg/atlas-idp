package internal

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/digitorus/pdfsign"
	"github.com/digitorus/pdfsign/sign"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

type Signer struct {
	cert *x509.Certificate
	key  crypto.PrivateKey
}

func NewSigner(ctx context.Context, certPath, keyPath string) (*Signer, error) {
	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return nil, fmt.Errorf("read cert %s: %w", certPath, err)
	}
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, fmt.Errorf("read key %s: %w", keyPath, err)
	}

	certBlock, _ := pem.Decode(certPEM)
	if certBlock == nil {
		return nil, fmt.Errorf("no PEM block in cert")
	}
	cert, err := x509.ParseCertificate(certBlock.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse cert: %w", err)
	}

	keyBlock, _ := pem.Decode(keyPEM)
	if keyBlock == nil {
		return nil, fmt.Errorf("no PEM block in key")
	}
	key, err := x509.ParsePKCS8PrivateKey(keyBlock.Bytes)
	if err != nil {
		key, err = x509.ParsePKCS1PrivateKey(keyBlock.Bytes)
		if err != nil {
			return nil, fmt.Errorf("parse key: %w", err)
		}
	}

	slog.Info("signer initialized",
		"cert_subject", cert.Subject.CommonName,
		"cert_issuer", cert.Issuer.CommonName,
	)

	return &Signer{cert: cert, key: key}, nil
}

func (s *Signer) Sign(ctx context.Context, pdfData []byte) ([]byte, error) {
	start := time.Now()

	rsaKey, ok := s.key.(*rsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("unsupported key type: only RSA supported")
	}

	input := bytes.NewReader(pdfData)
	var output bytes.Buffer

	signData := sign.SignData{
		Signature: sign.SignDataSignature{
			Info: sign.SignDataSignatureInfo{
				Name:        "Atlas IDP",
				Reason:      "Document authenticity",
				Location:    "Atlas IDP Worker",
				ContactInfo: "support@atlas-idp.local",
			},
			CertType:   sign.CertificationSignature,
			DocMDPPerm: sign.AllowAllChanges,
		},
		Signer:            input,
		TSACertificate:    nil,
		TSAHash:           crypto.SHA256,
		Certificate:       s.cert,
		CertificateChains: [][]*x509.Certificate{{s.cert}},
	}

	if err := pdfsign.Sign(input, &output, rsaKey, signData); err != nil {
		pdfSignErrorsTotal.Inc()
		return nil, fmt.Errorf("pdfsign: %w", err)
	}

	duration := time.Since(start)
	pdfSignDurationSeconds.Observe(duration.Seconds())
	slog.Debug("pdf signed", "duration", duration)

	return output.Bytes(), nil
}

func (s *Signer) Certificate() *x509.Certificate {
	return s.cert
}

func VerifySignature(pdfData []byte, caCert *x509.Certificate) error {
	reader := bytes.NewReader(pdfData)

	digest, err := pdfsign.Digest(reader)
	if err != nil {
		return fmt.Errorf("pdfsign digest: %w", err)
	}

	if len(digest.SignatureBlocks) == 0 {
		return fmt.Errorf("no signature blocks found")
	}

	for _, block := range digest.SignatureBlocks {
		for _, cert := range block.Certificates {
			verifyOpts := x509.VerifyOptions{
				Roots:     x509.NewCertPool(),
				CurrentTime: time.Now(),
			}
			verifyOpts.Roots.AddCert(caCert)

			chains, err := cert.Verify(verifyOpts)
			if err != nil {
				return fmt.Errorf("cert verify: %w", err)
			}
			if len(chains) > 0 {
				return nil
			}
		}
	}

	return fmt.Errorf("no valid signature found")
}

var (
	pdfSignDurationSeconds = promauto.NewHistogram(prometheus.HistogramOpts{
		Name:    "pdf_sign_duration_seconds",
		Help:    "Duration of PDF signing operation",
		Buckets: prometheus.DefBuckets,
	})

	pdfSignErrorsTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "pdf_sign_errors_total",
		Help: "Total number of PDF signing errors",
	})

	pdfVerifyTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "pdf_verify_total",
		Help: "Total number of PDF signature verifications",
	})
)

func ComputeHash(data []byte) string {
	h := sha256.Sum256(data)
	return fmt.Sprintf("%x", h)
}
