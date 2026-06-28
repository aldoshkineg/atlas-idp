package argocd

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

type Client struct {
	cliPath string
}

func New() *Client {
	return &Client{cliPath: "argocd"}
}

type AppStatus struct {
	Name      string `json:"name"`
	Sync      string `json:"sync"`
	Health    string `json:"health"`
	Namespace string `json:"namespace"`
	RepoURL   string `json:"repoURL"`
	TargetRev string `json:"targetRevision"`
}

func (c *Client) GetApp(name string) (*AppStatus, error) {
	cmd := exec.Command(c.cliPath, "app", "get", name, "-o", "json")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("argocd app get %s: %s: %w", name, strings.TrimSpace(stderr.String()), err)
	}

	var raw struct {
		Metadata struct {
			Name string `json:"name"`
		} `json:"metadata"`
		Status struct {
			Sync struct {
				Status string `json:"status"`
			} `json:"sync"`
			Health struct {
				Status string `json:"status"`
			} `json:"health"`
			Summary struct {
				ExternalURLs []string `json:"externalURLs"`
			} `json:"summary"`
		} `json:"status"`
		Spec struct {
			Source struct {
				RepoURL        string `json:"repoURL"`
				TargetRevision string `json:"targetRevision"`
			} `json:"source"`
			Destination struct {
				Namespace string `json:"namespace"`
			} `json:"destination"`
		} `json:"spec"`
	}
	if err := json.Unmarshal(stdout.Bytes(), &raw); err != nil {
		return nil, fmt.Errorf("parse argocd output: %w", err)
	}

	return &AppStatus{
		Name:      raw.Metadata.Name,
		Sync:      raw.Status.Sync.Status,
		Health:    raw.Status.Health.Status,
		Namespace: raw.Spec.Destination.Namespace,
		RepoURL:   raw.Spec.Source.RepoURL,
		TargetRev: raw.Spec.Source.TargetRevision,
	}, nil
}

func (c *Client) Available() bool {
	_, err := exec.LookPath(c.cliPath)
	return err == nil
}

func (c *Client) ListApps() ([]AppStatus, error) {
	cmd := exec.Command(c.cliPath, "app", "list", "-o", "json")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("argocd app list: %s: %w", strings.TrimSpace(stderr.String()), err)
	}

	var raw []struct {
		Metadata struct {
			Name string `json:"name"`
		} `json:"metadata"`
		Status struct {
			Sync struct {
				Status string `json:"status"`
			} `json:"sync"`
			Health struct {
				Status string `json:"status"`
			} `json:"health"`
		} `json:"status"`
	}
	if err := json.Unmarshal(stdout.Bytes(), &raw); err != nil {
		return nil, fmt.Errorf("parse argocd list: %w", err)
	}

	out := make([]AppStatus, 0, len(raw))
	for _, r := range raw {
		out = append(out, AppStatus{
			Name:   r.Metadata.Name,
			Sync:   r.Status.Sync.Status,
			Health: r.Status.Health.Status,
		})
	}
	return out, nil
}
