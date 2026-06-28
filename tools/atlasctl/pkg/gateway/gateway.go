// Package gateway manages Gateway API resources — adding/removing listeners and routes.
package gateway

import (
	"fmt"
	"os"

	"sigs.k8s.io/yaml"
)

type Listener struct {
	Name          string        `json:"name"`
	Port          int           `json:"port"`
	Protocol      string        `json:"protocol"`
	Hostname      string        `json:"hostname"`
	AllowedRoutes AllowedRoutes `json:"allowedRoutes"`
	TLS           TLSConfig     `json:"tls"`
}

type AllowedRoutes struct {
	Namespaces NamespaceSelector `json:"namespaces"`
}

type NamespaceSelector struct {
	From string `json:"from"`
}

type TLSConfig struct {
	Mode             string           `json:"mode"`
	CertificateRefs  []CertificateRef `json:"certificateRefs"`
}

type CertificateRef struct {
	Name string `json:"name"`
}

type GatewaySpec struct {
	Listeners []Listener `json:"listeners"`
}

type Gateway struct {
	Spec GatewaySpec `json:"spec"`
}

func LoadGateway(path string) (*Gateway, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read gateway %s: %w", path, err)
	}
	var gw Gateway
	if err := yaml.Unmarshal(data, &gw); err != nil {
		return nil, fmt.Errorf("unmarshal gateway %s: %w", path, err)
	}
	return &gw, nil
}

func SaveGateway(path string, gw *Gateway) error {
	data, err := yaml.Marshal(gw)
	if err != nil {
		return fmt.Errorf("marshal gateway: %w", err)
	}
	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("write gateway %s: %w", path, err)
	}
	return nil
}

func (g *Gateway) HasListener(name string) bool {
	for _, l := range g.Spec.Listeners {
		if l.Name == name {
			return true
		}
	}
	return false
}

func (g *Gateway) AddListener(name, hostname, certName string) {
	g.Spec.Listeners = append(g.Spec.Listeners, Listener{
		Name:     name,
		Port:     443,
		Protocol: "HTTPS",
		Hostname: hostname,
		AllowedRoutes: AllowedRoutes{
			Namespaces: NamespaceSelector{From: "All"},
		},
		TLS: TLSConfig{
			Mode: "Terminate",
			CertificateRefs: []CertificateRef{{Name: certName}},
		},
	})
}

func (g *Gateway) RemoveListener(name string) bool {
	before := len(g.Spec.Listeners)
	filtered := make([]Listener, 0, before)
	for _, l := range g.Spec.Listeners {
		if l.Name != name {
			filtered = append(filtered, l)
		}
	}
	g.Spec.Listeners = filtered
	return len(filtered) < before
}
