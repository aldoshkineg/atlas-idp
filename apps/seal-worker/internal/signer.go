package internal

import (
	"bytes"
	"context"
	"crypto"
	"crypto/sha256"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"io"
	"log/slog"
	"os"
	"time"

	"github.com/digitorus/pdf"
	"github.com/digitorus/pdfsign/sign"
	"github.com/digitorus/pdfsign/verify"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

type Signer struct {
	cert *x509.Certificate
	key  crypto.Signer
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

	signer, ok := key.(crypto.Signer)
	if !ok {
		return nil, fmt.Errorf("key does not implement crypto.Signer")
	}

	slog.Info("signer initialized",
		"cert_subject", cert.Subject.CommonName,
		"cert_issuer", cert.Issuer.CommonName,
	)

	return &Signer{cert: cert, key: signer}, nil
}

func (s *Signer) Sign(ctx context.Context, pdfData []byte) ([]byte, error) {
	start := time.Now()

	input := bytes.NewReader(pdfData)

	reader, err := pdf.NewReader(input, int64(len(pdfData)))
	if err != nil {
		pdfSignErrorsTotal.Inc()
		return nil, fmt.Errorf("pdf reader: %w", err)
	}

	if _, err := input.Seek(0, io.SeekStart); err != nil {
		pdfSignErrorsTotal.Inc()
		return nil, fmt.Errorf("seek: %w", err)
	}

	var output bytes.Buffer
	signData := sign.SignData{
		Signature: sign.SignDataSignature{
			Info: sign.SignDataSignatureInfo{
				Name:        "Atlas IDP",
				Reason:      "Document authenticity",
				Location:    "Atlas IDP Worker",
				ContactInfo: "support@atlas-idp.local",
				Date:        time.Now(),
			},
			CertType:   sign.CertificationSignature,
			DocMDPPerm: sign.AllowFillingExistingFormFieldsAndSignaturesPerms,
		},
		Signer:            s.key,
		DigestAlgorithm:   crypto.SHA256,
		Certificate:       s.cert,
		CertificateChains: [][]*x509.Certificate{{s.cert}},
	}

	if err := sign.Sign(input, &output, reader, int64(len(pdfData)), signData); err != nil {
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

type VerifyResult struct {
	Valid       bool   `json:"valid"`
	Subject     string `json:"subject"`
	Issuer      string `json:"issuer"`
	Expiry      string `json:"expiry"`
	SigningTime string `json:"signing_time,omitempty"`
	Error       string `json:"error,omitempty"`
}

func VerifyPDFSignature(pdfData []byte, caCert *x509.Certificate) VerifyResult {
	pdfVerifyTotal.Inc()

	reader := bytes.NewReader(pdfData)

	result, err := verify.VerifyWithOptions(reader, int64(len(pdfData)), &verify.VerifyOptions{
		RequireDigitalSignatureKU: true,
		AllowUntrustedRoots:       true,
	})
	if err != nil {
		return VerifyResult{
			Valid: false,
			Error: fmt.Sprintf("verification failed: %v", err),
		}
	}

	for _, sigResult := range result.Signers {
		if len(sigResult.Certificates) == 0 {
			continue
		}

		signerCert := sigResult.Certificates[0].Certificate
		if signerCert == nil {
			continue
		}

		if !issuerMatchesCA(signerCert, caCert) {
			continue
		}

		res := VerifyResult{
			Valid:   true,
			Subject: signerCert.Subject.CommonName,
			Issuer:  signerCert.Issuer.CommonName,
			Expiry:  signerCert.NotAfter.Format(time.RFC3339),
		}

		if sigResult.SignatureTime != nil {
			res.SigningTime = sigResult.SignatureTime.Format(time.RFC3339)
		}

		return res
	}

	return VerifyResult{
		Valid: false,
		Error: "no valid signature found in chain",
	}
}

func ComputeHash(data []byte) string {
	h := sha256.Sum256(data)
	return fmt.Sprintf("%x", h)
}

func issuerMatchesCA(leaf *x509.Certificate, ca *x509.Certificate) bool {
	if leaf == nil || ca == nil {
		return false
	}
	return leaf.Issuer.CommonName == ca.Subject.CommonName &&
		bytes.Equal(leaf.AuthorityKeyId, ca.SubjectKeyId)
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
