package internal

import (
	"testing"
)

func TestGeneratePDF(t *testing.T) {
	data, err := GeneratePDF("Hello, World!")
	if err != nil {
		t.Fatalf("GeneratePDF() error = %v", err)
	}
	if len(data) == 0 {
		t.Fatal("GeneratePDF() returned empty data")
	}
	if len(data) < 100 {
		t.Fatalf("GeneratePDF() returned %d bytes, expected at least 100", len(data))
	}
}

func TestGeneratePDFEmptyText(t *testing.T) {
	data, err := GeneratePDF("")
	if err != nil {
		t.Fatalf("GeneratePDF() error = %v", err)
	}
	if len(data) == 0 {
		t.Fatal("GeneratePDF() returned empty data")
	}
}

func TestGeneratePDFMultiLine(t *testing.T) {
	text := "Line 1\nLine 2\nLine 3"
	data, err := GeneratePDF(text)
	if err != nil {
		t.Fatalf("GeneratePDF() error = %v", err)
	}
	if len(data) == 0 {
		t.Fatal("GeneratePDF() returned empty data")
	}
}
