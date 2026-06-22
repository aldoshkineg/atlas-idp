package internal

import (
	"bytes"
	"fmt"

	"github.com/jung-kurt/gofpdf"
)

func GeneratePDF(text string) ([]byte, error) {
	pdf := gofpdf.New("P", "mm", "A4", "")
	pdf.AddPage()

	pdf.SetFont("Courier", "", 10)
	pdf.MultiCell(190, 5, text, "", "L", false)

	var buf bytes.Buffer
	if err := pdf.Output(&buf); err != nil {
		return nil, fmt.Errorf("generate pdf: %w", err)
	}
	return buf.Bytes(), nil
}
