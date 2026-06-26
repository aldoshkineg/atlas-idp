package client

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

const maxRetries = 3

type Client struct {
	baseURL    string
	httpClient *http.Client
}

type CreateDocumentResponse struct {
	ID string `json:"id"`
}

type DocumentResponse struct {
	ID        string `json:"id"`
	Status    string `json:"status"`
	InputText string `json:"input_text"`
	S3Path    string `json:"s3_path,omitempty"`
	FileSize  int64  `json:"file_size"`
	Error     string `json:"error,omitempty"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

type DownloadURLResponse struct {
	URL string `json:"url"`
}

type VerifyResponse struct {
	Valid    bool   `json:"valid"`
	Subject  string `json:"subject,omitempty"`
	S3Path   string `json:"s3_path,omitempty"`
	SignedBy string `json:"signed_by,omitempty"`
	Error    string `json:"error,omitempty"`
}

func New(baseURL string) *Client {
	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Transport: otelhttp.NewTransport(http.DefaultTransport),
			Timeout:   10 * time.Second,
		},
	}
}

func (c *Client) CreateDocument(ctx context.Context, text string) (*CreateDocumentResponse, error) {
	body := map[string]string{"text": text}
	data, _ := json.Marshal(body)

	resp, err := c.doRequest(ctx, http.MethodPost, "/api/v1/documents", data, "CreateDocument")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("unexpected status %d: %s", resp.StatusCode, string(b))
	}

	var result CreateDocumentResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return &result, nil
}

func (c *Client) GetDocument(ctx context.Context, id string) (*DocumentResponse, error) {
	resp, err := c.doRequest(ctx, http.MethodGet, "/api/v1/documents/"+id, nil, "GetDocument")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, nil
	}
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("unexpected status %d: %s", resp.StatusCode, string(b))
	}

	var result DocumentResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return &result, nil
}

func (c *Client) GetDownloadURL(ctx context.Context, id string) (string, error) {
	resp, err := c.doRequest(ctx, http.MethodGet, "/api/v1/documents/"+id+"/download", nil, "GetDownloadURL")
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("unexpected status %d: %s", resp.StatusCode, string(b))
	}

	var result DownloadURLResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("decode response: %w", err)
	}
	return result.URL, nil
}

func (c *Client) VerifyDocument(ctx context.Context, id string) (*VerifyResponse, error) {
	resp, err := c.doRequest(ctx, http.MethodGet, "/api/v1/documents/"+id+"/verify", nil, "VerifyDocument")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result VerifyResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return &result, nil
}

func (c *Client) doRequest(ctx context.Context, method, path string, body []byte, endpoint string) (*http.Response, error) {
	var lastErr error
	for attempt := range maxRetries {
		if attempt > 0 {
			time.Sleep(time.Duration(100*(1<<attempt)) * time.Millisecond)
		}

		var reader io.Reader
		if body != nil {
			reader = bytes.NewReader(body)
		}

		req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, reader)
		if err != nil {
			return nil, fmt.Errorf("create request: %w", err)
		}
		if body != nil {
			req.Header.Set("Content-Type", "application/json")
		}

		resp, err := c.httpClient.Do(req)
		backendRequestsTotal.WithLabelValues(endpoint, statusLabel(err, resp)).Inc()

		if err != nil {
			lastErr = fmt.Errorf("do request: %w", err)
			continue
		}

		if resp.StatusCode >= http.StatusInternalServerError {
			resp.Body.Close()
			lastErr = fmt.Errorf("unexpected status %d", resp.StatusCode)
			continue
		}

		return resp, nil
	}
	return nil, fmt.Errorf("request failed after %d attempts: %w", maxRetries, lastErr)
}

func statusLabel(err error, resp *http.Response) string {
	if err != nil {
		return "error"
	}
	return http.StatusText(resp.StatusCode)
}

var backendRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "frontend_backend_requests_total",
	Help: "Total number of requests to backend API",
}, []string{"endpoint", "status"})
