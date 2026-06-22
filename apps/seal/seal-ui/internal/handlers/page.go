package handlers

import (
	"net/http"

	"github.com/aldoshkineg/atlas-idp/apps/seal-ui/internal/templates"
)

type PageHandler struct{}

func NewPageHandler() *PageHandler {
	return &PageHandler{}
}

func (h *PageHandler) Index(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := templates.RenderIndex(w); err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
	}
}
