package handlers

import (
	"log/slog"
	"net/http"

	"github.com/aldoshkineg/atlas-idp/apps/seal-ui/internal/client"
	"github.com/aldoshkineg/atlas-idp/apps/seal-ui/internal/templates"
	"github.com/go-chi/chi/v5"
)

type DocumentHandler struct {
	api *client.Client
}

func NewDocumentHandler(backendAPIURL string) *DocumentHandler {
	return &DocumentHandler{
		api: client.New(backendAPIURL),
	}
}

func (h *DocumentHandler) Create(w http.ResponseWriter, r *http.Request) {
	text := r.FormValue("text")
	if text == "" {
		http.Error(w, "text is required", http.StatusBadRequest)
		return
	}

	resp, err := h.api.CreateDocument(r.Context(), text)
	if err != nil {
		slog.Error("create document via api", "error", err)
		http.Error(w, "failed to create document", http.StatusInternalServerError)
		return
	}

	slog.Info("document created via frontend", "id", resp.ID)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := templates.RenderStatus(w, resp.ID); err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
	}
}

func (h *DocumentHandler) Status(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if id == "" {
		http.Error(w, "missing id", http.StatusBadRequest)
		return
	}

	doc, err := h.api.GetDocument(r.Context(), id)
	if err != nil {
		slog.Error("get document status", "id", id, "error", err)
		http.Error(w, "failed to check status", http.StatusInternalServerError)
		return
	}
	if doc == nil {
		http.Error(w, "document not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")

	switch doc.Status {
	case "pending", "processing":
		if err := templates.RenderPending(w, id); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
		}
	case "completed":
		if err := templates.RenderDownload(w, id, doc.Status); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
		}
	default:
		w.Write([]byte(`<div class="bg-red-50 p-4 rounded-lg text-red-700">Failed: ` + doc.Error + `</div>`))
	}
}

func (h *DocumentHandler) Download(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if id == "" {
		http.Error(w, "missing id", http.StatusBadRequest)
		return
	}

	url, err := h.api.GetDownloadURL(r.Context(), id)
	if err != nil {
		slog.Error("get download url", "id", id, "error", err)
		http.Error(w, "document not ready", http.StatusConflict)
		return
	}

	http.Redirect(w, r, url, http.StatusSeeOther)
}

func (h *DocumentHandler) Verify(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if id == "" {
		http.Error(w, "missing id", http.StatusBadRequest)
		return
	}

	resp, err := h.api.VerifyDocument(r.Context(), id)
	if err != nil {
		slog.Error("verify document", "id", id, "error", err)
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write([]byte(`<div class="bg-red-50 p-4 rounded-lg text-red-700">Verification failed</div>`))
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if resp.Valid {
		w.Write([]byte(`<div class="bg-green-50 p-4 rounded-lg text-green-700">Signature valid — document is authentic and untampered.</div>`))
	} else {
		w.Write([]byte(`<div class="bg-yellow-50 p-4 rounded-lg text-yellow-700">` + resp.Error + `</div>`))
	}
}