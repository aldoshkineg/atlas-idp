package templates

import (
	"embed"
	"html/template"
	"io"
)

//go:embed *.html
var templateFS embed.FS

var (
	base    *template.Template
	index   *template.Template
	status  *template.Template
	pending *template.Template
	download *template.Template
)

func init() {
	base = template.Must(template.ParseFS(templateFS, "base.html"))
	index = template.Must(template.Must(base.Clone()).ParseFS(templateFS, "index.html"))
	status = template.Must(template.ParseFS(templateFS, "status.html"))
	pending = template.Must(template.ParseFS(templateFS, "status_pending.html"))
	download = template.Must(template.ParseFS(templateFS, "download.html"))
}

func RenderIndex(w io.Writer) error {
	return index.ExecuteTemplate(w, "base.html", nil)
}

type StatusData struct {
	DocumentID string
}

func RenderStatus(w io.Writer, id string) error {
	return status.Execute(w, StatusData{DocumentID: id})
}

func RenderPending(w io.Writer, id string) error {
	return pending.Execute(w, StatusData{DocumentID: id})
}

type DownloadData struct {
	DocumentID string
	Status     string
}

func RenderDownload(w io.Writer, id, status string) error {
	return download.Execute(w, DownloadData{DocumentID: id, Status: status})
}