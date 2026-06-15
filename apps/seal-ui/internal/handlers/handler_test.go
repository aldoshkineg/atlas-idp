package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/aldoshkineg/atlas-idp/apps/seal-ui/internal/client"
	"github.com/go-chi/chi/v5"
)

func newTestRouter(backendURL string) chi.Router {
	r := chi.NewRouter()
	ph := NewPageHandler()
	dh := NewDocumentHandler(backendURL)

	r.Get("/", ph.Index)
	r.Post("/documents", dh.Create)
	r.Get("/documents/{id}/status", dh.Status)
	r.Get("/documents/{id}/download", dh.Download)
	r.Get("/documents/{id}/verify", dh.Verify)

	return r
}

func TestCreateDocument_Success(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(client.CreateDocumentResponse{ID: "doc-123"})
	}))
	defer backend.Close()

	frontend := httptest.NewServer(newTestRouter(backend.URL))
	defer frontend.Close()

	resp, err := http.PostForm(frontend.URL+"/documents", map[string][]string{"text": {"hello"}})
	if err != nil {
		t.Fatalf("PostForm error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("status = %d, want 200", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); ct != "text/html; charset=utf-8" {
		t.Errorf("Content-Type = %s, want text/html", ct)
	}
}

func TestCreateDocument_EmptyText(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("should not reach backend")
	}))
	defer backend.Close()

	frontend := httptest.NewServer(newTestRouter(backend.URL))
	defer frontend.Close()

	resp, err := http.PostForm(frontend.URL+"/documents", nil)
	if err != nil {
		t.Fatalf("PostForm error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("status = %d, want 400", resp.StatusCode)
	}
}

func TestStatus_Pending(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(client.DocumentResponse{ID: "doc-123", Status: "pending"})
	}))
	defer backend.Close()

	frontend := httptest.NewServer(newTestRouter(backend.URL))
	defer frontend.Close()

	resp, err := http.Get(frontend.URL + "/documents/doc-123/status")
	if err != nil {
		t.Fatalf("Get error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("status = %d, want 200", resp.StatusCode)
	}
}

func TestStatus_Completed(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(client.DocumentResponse{ID: "doc-123", Status: "completed"})
	}))
	defer backend.Close()

	frontend := httptest.NewServer(newTestRouter(backend.URL))
	defer frontend.Close()

	resp, err := http.Get(frontend.URL + "/documents/doc-123/status")
	if err != nil {
		t.Fatalf("Get error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("status = %d, want 200", resp.StatusCode)
	}
}

func TestStatus_Failed(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(client.DocumentResponse{ID: "doc-123", Status: "failed", Error: "processing error"})
	}))
	defer backend.Close()

	frontend := httptest.NewServer(newTestRouter(backend.URL))
	defer frontend.Close()

	resp, err := http.Get(frontend.URL + "/documents/doc-123/status")
	if err != nil {
		t.Fatalf("Get error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("status = %d, want 200", resp.StatusCode)
	}
}

func TestVerify_Valid(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(client.VerifyResponse{Valid: true})
	}))
	defer backend.Close()

	frontend := httptest.NewServer(newTestRouter(backend.URL))
	defer frontend.Close()

	resp, err := http.Get(frontend.URL + "/documents/doc-123/verify")
	if err != nil {
		t.Fatalf("Get error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("status = %d, want 200", resp.StatusCode)
	}
}

func TestDownload_Redirect(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(client.DownloadURLResponse{URL: "http://minio:9000/doc.pdf"})
	}))
	defer backend.Close()

	frontend := httptest.NewServer(newTestRouter(backend.URL))
	defer frontend.Close()

	httpClient := &http.Client{CheckRedirect: func(req *http.Request, via []*http.Request) error {
		return http.ErrUseLastResponse
	}}

	resp, err := httpClient.Get(frontend.URL + "/documents/doc-123/download")
	if err != nil {
		t.Fatalf("Get error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusSeeOther {
		t.Errorf("status = %d, want 303", resp.StatusCode)
	}
	if loc := resp.Header.Get("Location"); loc != "http://minio:9000/doc.pdf" {
		t.Errorf("Location = %s", loc)
	}
}

func TestIndex(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	defer backend.Close()

	frontend := httptest.NewServer(newTestRouter(backend.URL))
	defer frontend.Close()

	resp, err := http.Get(frontend.URL + "/")
	if err != nil {
		t.Fatalf("Get error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("status = %d, want 200", resp.StatusCode)
	}
}