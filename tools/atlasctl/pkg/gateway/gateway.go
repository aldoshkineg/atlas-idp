package gateway

import (
	_ "embed"
	"bytes"
	"fmt"
	"os"
	"strings"
	"text/template"
)

//go:embed listener.tmpl
var listenerTemplate string

type ListenerData struct {
	Name     string
	Port     int
	Hostname string
	CertName string
}

func RenderListener(data ListenerData) (string, error) {
	tmpl, err := template.New("listener").Parse(listenerTemplate)
	if err != nil {
		return "", fmt.Errorf("parse listener template: %w", err)
	}
	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", fmt.Errorf("execute listener template: %w", err)
	}
	return buf.String(), nil
}

func RemoveListenerFromFile(path, appName string) (bool, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return false, fmt.Errorf("read %s: %w", path, err)
	}

	marker := "    - name: https-" + appName

	lines := strings.Split(string(data), "\n")
	startIdx := -1
	for i, line := range lines {
		if strings.TrimRight(line, " ") == marker {
			startIdx = i
			break
		}
	}
	if startIdx == -1 {
		return false, nil
	}

	indent := countIndent(lines[startIdx])

	endIdx := startIdx + 1
	for endIdx < len(lines) {
		line := lines[endIdx]
		if strings.TrimSpace(line) == "" {
			endIdx++
			continue
		}
		lineIndent := countIndent(line)
		if lineIndent <= indent && strings.HasPrefix(strings.TrimSpace(line), "-") {
			break
		}
		if lineIndent <= indent && lineIndent > 0 {
			break
		}
		if lineIndent == 0 && strings.TrimSpace(line) != "" {
			break
		}
		endIdx++
	}

	var result []string
	result = append(result, lines[:startIdx]...)
	result = append(result, lines[endIdx:]...)

	// Clean up extra blank lines
	output := strings.Join(result, "\n")
	output = strings.TrimPrefix(output, "\n")
	output = strings.TrimSuffix(output, "\n") + "\n"

	return true, os.WriteFile(path, []byte(output), 0644)
}

func HasListenerInFile(path, appName string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	marker := "    - name: https-" + appName
	return strings.Contains(string(data), marker)
}

func AppendListenerToFile(path string, data ListenerData) error {
	rendered, err := RenderListener(data)
	if err != nil {
		return err
	}

	existing, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read %s: %w", path, err)
	}

	content := strings.TrimRight(string(existing), "\n") + "\n" + rendered
	return os.WriteFile(path, []byte(content), 0644)
}

func countIndent(line string) int {
	return len(line) - len(strings.TrimLeft(line, " "))
}
