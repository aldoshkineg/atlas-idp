package client

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestCreateDocument_Success(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("method = %s, want POST", r.Method)
		}
		if r.URL.Path != "/api/v1/documents" {
			t.Errorf("path = %s, want /api/v1/documents", r.URL.Path)
		}
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(CreateDocumentResponse{ID: "doc-123"})
	}))
	defer srv.Close()

	c := New(srv.URL)
	resp, err := c.CreateDocument(context.Background(), "hello")
	if err != nil {
		t.Fatalf("CreateDocument() error = %v", err)
	}
	if resp.ID != "doc-123" {
		t.Errorf("ID = %s, want doc-123", resp.ID)
	}
}

func TestCreateDocument_Error(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"error":"text is required"}`))
	}))
	defer srv.Close()

	c := New(srv.URL)
	_, err := c.CreateDocument(context.Background(), "")
	if err == nil {
		t.Fatal("expected error, got nil")
	}
}

func TestGetDocument_Success(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			t.Errorf("method = %s, want GET", r.Method)
		}
		json.NewEncoder(w).Encode(DocumentResponse{
			ID:     "doc-123",
			Status: "completed",
		})
	}))
	defer srv.Close()

	c := New(srv.URL)
	doc, err := c.GetDocument(context.Background(), "doc-123")
	if err != nil {
		t.Fatalf("GetDocument() error = %v", err)
	}
	if doc == nil {
		t.Fatal("expected doc, got nil")
	}
	if doc.Status != "completed" {
		t.Errorf("Status = %s, want completed", doc.Status)
	}
}

func TestGetDocument_NotFound(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	c := New(srv.URL)
	doc, err := c.GetDocument(context.Background(), "nonexistent")
	if err != nil {
		t.Fatalf("GetDocument() error = %v", err)
	}
	if doc != nil {
		t.Fatal("expected nil doc for not found")
	}
}

func TestGetDownloadURL_Success(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/documents/doc-123/download" {
			t.Errorf("path = %s", r.URL.Path)
		}
		json.NewEncoder(w).Encode(DownloadURLResponse{URL: "http://minio:9000/doc.pdf"})
	}))
	defer srv.Close()

	c := New(srv.URL)
	url, err := c.GetDownloadURL(context.Background(), "doc-123")
	if err != nil {
		t.Fatalf("GetDownloadURL() error = %v", err)
	}
	if url != "http://minio:9000/doc.pdf" {
		t.Errorf("URL = %s", url)
	}
}

func TestVerifyDocument_Valid(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(VerifyResponse{
			Valid:    true,
			Subject:  "PDF Signer",
			S3Path:   "doc-123.pdf",
			SignedBy: "worker",
		})
	}))
	defer srv.Close()

	c := New(srv.URL)
	resp, err := c.VerifyDocument(context.Background(), "doc-123")
	if err != nil {
		t.Fatalf("VerifyDocument() error = %v", err)
	}
	if !resp.Valid {
		t.Error("expected valid=true")
	}
}

func TestVerifyDocument_NotReady(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusConflict)
		json.NewEncoder(w).Encode(VerifyResponse{
			Valid: false,
			Error: "document not ready yet",
		})
	}))
	defer srv.Close()

	c := New(srv.URL)
	resp, err := c.VerifyDocument(context.Background(), "doc-123")
	if err != nil {
		t.Fatalf("VerifyDocument() error = %v", err)
	}
	if resp.Valid {
		t.Error("expected valid=false")
	}
	if resp.Error != "document not ready yet" {
		t.Errorf("Error = %s", resp.Error)
	}
}
