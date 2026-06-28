// Package gitops manages the GitOps workflow — copying workload manifests,
// creating ArgoCD Application CRs, and managing gateway listener entries.
package gitops

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/config"
	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/gateway"
)

type WorkloadRef struct {
	Group string
	App   string
}

func (w WorkloadRef) String() string { return w.Group + "/" + w.App }

type Paths struct {
	WorkloadDir      string
	GitopsDir        string
	GitopsFile       string
	GitopsResources  string
	GatewayFile      string
	GatewayRoutesDir string
	GatewayRouteFile string
}

func ResolvePaths(ref WorkloadRef, cfg *config.GitopsConfig, scaffoldDir string) Paths {
	groupDir := filepath.Join(cfg.WorkloadsDir, ref.Group)
	resourcesDir := filepath.Join(groupDir, ref.App, "resources")
	return Paths{
		WorkloadDir:      filepath.Join(scaffoldDir, ref.Group, ref.App),
		GitopsDir:        filepath.Join(groupDir),
		GitopsFile:       filepath.Join(groupDir, ref.App+".yaml"),
		GitopsResources:  filepath.Join(resourcesDir),
		GatewayFile:      cfg.GatewayFile,
		GatewayRoutesDir: cfg.GatewayRoutesDir,
		GatewayRouteFile: filepath.Join(cfg.GatewayRoutesDir, ref.App+".yaml"),
	}
}

func CopyWorkloadManifest(src, dst string) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return fmt.Errorf("mkdir gitops dir: %w", err)
	}
	data, err := os.ReadFile(src)
	if err != nil {
		return fmt.Errorf("read %s: %w", src, err)
	}
	if err := os.WriteFile(dst, data, 0644); err != nil {
		return fmt.Errorf("write %s: %w", dst, err)
	}
	return nil
}

func SyncResources(workloadDir, resourcesDir string) error {
	if err := os.MkdirAll(resourcesDir, 0755); err != nil {
		return fmt.Errorf("mkdir resources: %w", err)
	}

	entries, err := os.ReadDir(workloadDir)
	if err != nil {
		return fmt.Errorf("read workload dir %s: %w", workloadDir, err)
	}

	for _, e := range entries {
		name := e.Name()
		if name == "app.yaml" || name == ".secret-seed" || name == "vault" || strings.HasSuffix(name, ".tmpl") {
			continue
		}
		src := filepath.Join(workloadDir, name)
		dst := filepath.Join(resourcesDir, name)

		if e.IsDir() {
			if name == "infra" {
				if err := syncInfraResources(src, dst, workloadDir); err != nil {
					return err
				}
				continue
			}
			if err := copyDir(src, dst); err != nil {
				return err
			}
		} else {
			data, err := os.ReadFile(src)
			if err != nil {
				return fmt.Errorf("read %s: %w", src, err)
			}
			if err := os.WriteFile(dst, data, 0644); err != nil {
				return fmt.Errorf("write %s: %w", dst, err)
			}
		}
	}
	return nil
}

func syncInfraResources(srcDir, dstDir, workloadDir string) error {
	if err := os.MkdirAll(dstDir, 0755); err != nil {
		return err
	}
	entries, err := os.ReadDir(srcDir)
	if err != nil {
		return err
	}
	for _, e := range entries {
		name := e.Name()
		if name == "gateway.yaml" {
			continue
		}
		src := filepath.Join(srcDir, name)
		dst := filepath.Join(dstDir, name)
		if e.IsDir() {
			if err := copyDir(src, dst); err != nil {
				return err
			}
		} else {
			data, err := os.ReadFile(src)
			if err != nil {
				return err
			}
			if err := os.WriteFile(dst, data, 0644); err != nil {
				return err
			}
		}
	}
	return nil
}

func copyDir(src, dst string) error {
	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dst, 0755); err != nil {
		return err
	}
	for _, e := range entries {
		srcPath := filepath.Join(src, e.Name())
		dstPath := filepath.Join(dst, e.Name())
		if e.IsDir() {
			if err := copyDir(srcPath, dstPath); err != nil {
				return err
			}
		} else {
			data, err := os.ReadFile(srcPath)
			if err != nil {
				return err
			}
			if err := os.WriteFile(dstPath, data, 0644); err != nil {
				return err
			}
		}
	}
	return nil
}

func RemoveAll(paths ...string) error {
	for _, p := range paths {
		if err := os.RemoveAll(p); err != nil {
			return fmt.Errorf("remove %s: %w", p, err)
		}
	}
	return nil
}

func RemoveEmptyDir(dir string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	if len(entries) == 0 {
		os.Remove(dir)
	}
}

type GatewayListenerChange struct {
	App      string
	Hostname string
	CertName string
	Add      bool
}

func ApplyGatewayListener(gwPath string, change GatewayListenerChange) (string, error) {
	listenerName := "https-" + change.App

	if change.Add {
		if gateway.HasListenerInFile(gwPath, change.App) {
			return fmt.Sprintf("  [gateway] Listener '%s' already exists — skipping", listenerName), nil
		}
		if err := gateway.AppendListenerToFile(gwPath, gateway.ListenerData{
			Name:     listenerName,
			Port:     443,
			Hostname: change.Hostname,
			CertName: change.CertName,
		}); err != nil {
			return "", err
		}
		return fmt.Sprintf("  [gateway] Added listener '%s' (%s)", listenerName, change.Hostname), nil
	}

	removed, err := gateway.RemoveListenerFromFile(gwPath, change.App)
	if err != nil {
		return "", fmt.Errorf("remove gateway listener: %w", err)
	}
	if !removed {
		return fmt.Sprintf("  [gateway] Listener '%s' not found — skipping", listenerName), nil
	}
	return fmt.Sprintf("  [gateway] Removed listener '%s' (%s)", listenerName, change.Hostname), nil
}
