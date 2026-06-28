package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/argocd"
	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/gateway"
	"github.com/spf13/cobra"
	"sigs.k8s.io/yaml"
)

type statusFlags struct {
	json bool
}

var statusCmdFlags statusFlags

func detectFeatures(workloadDir string) []string {
	var features []string
	if _, err := os.Stat(filepath.Join(workloadDir, ".secret-seed")); err == nil {
		features = append(features, "secrets")
	} else if _, err := os.Stat(filepath.Join(workloadDir, "vault", "policy.hcl")); err == nil {
		features = append(features, "secrets")
	}
	if _, err := os.Stat(filepath.Join(workloadDir, "gateway.yaml")); err == nil {
		features = append(features, "gateway")
	} else if _, err := os.Stat(filepath.Join(workloadDir, "infra", "gateway.yaml")); err == nil {
		features = append(features, "gateway")
	}
	if _, err := os.Stat(filepath.Join(workloadDir, "monitoring", "prometheus-rule.yaml")); err == nil {
		features = append(features, "monitoring")
	}
	return features
}

type workloadStatus struct {
	Name            string   `json:"name"`
	Namespace       string   `json:"namespace"`
	Features        []string `json:"features"`
	Enabled         bool     `json:"enabled"`
	GatewayListener bool     `json:"gateway_listener"`
	ArgoCDSync      *string  `json:"argocd_sync,omitempty"`
}

var statusCmd = &cobra.Command{
	Use:   "status GROUP/APP",
	Short: "Show workload status",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		group, app, err := parseWorkloadArg(args[0])
		if err != nil {
			return err
		}

		workloadDir := filepath.Join(Cfg.Scaffold.Dir, group, app)
		gitopsFile := filepath.Join(Cfg.Gitops.WorkloadsDir, group, app+".yaml")

		if _, err := os.Stat(workloadDir); os.IsNotExist(err) {
			return fmt.Errorf("workload not found: %s", workloadDir)
		}

		namespace := group + "-" + app
		appYaml := filepath.Join(workloadDir, "app.yaml")
		if data, err := os.ReadFile(appYaml); err == nil {
			var appSpec struct {
				Spec struct {
					Destination struct {
						Namespace string `json:"namespace"`
					} `json:"destination"`
				} `json:"spec"`
			}
			if err := yaml.Unmarshal(data, &appSpec); err == nil && appSpec.Spec.Destination.Namespace != "" {
				namespace = appSpec.Spec.Destination.Namespace
			}
		}

		features := detectFeatures(workloadDir)
		if len(features) == 0 {
			features = []string{"none"}
		}

		enabled := false
		if _, err := os.Stat(gitopsFile); err == nil {
			enabled = true
		}

		gwListener := false
		gwPath := filepath.Join(Cfg.Gitops.GatewayFile)
		if gw, err := gateway.LoadGateway(gwPath); err == nil {
			gwListener = gw.HasListener("https-" + app)
		}

		var argocdSync *string
		ac := argocd.New()
		if ac.Available() {
			appStatus, err := ac.GetApp(group + "-" + app)
			if err == nil {
				argocdSync = &appStatus.Sync
			}
		}

		ws := workloadStatus{
			Name:            group + "/" + app,
			Namespace:       namespace,
			Features:        features,
			Enabled:         enabled,
			GatewayListener: gwListener,
			ArgoCDSync:      argocdSync,
		}

		if statusCmdFlags.json {
			data, _ := json.MarshalIndent(ws, "", "  ")
			fmt.Println(string(data))
		} else {
			fmt.Printf("=== %s/%s ===\n", group, app)
			fmt.Printf("  Namespace:      %s\n", ws.Namespace)
			fmt.Printf("  Features:       %s\n", strings.Join(ws.Features, " "))
			if ws.Enabled {
				fmt.Printf("  Enabled:        %s\n", ansiGreen("yes"))
			} else {
				fmt.Printf("  Enabled:        %s\n", ansiYellow("no"))
			}
			if ws.GatewayListener {
				fmt.Printf("  Gateway:        %s\n", ansiGreen("yes"))
			} else {
				fmt.Printf("  Gateway:        %s\n", ansiYellow("no"))
			}
			if ws.ArgoCDSync != nil {
				switch *ws.ArgoCDSync {
				case "Synced":
					fmt.Printf("  ArgoCD Sync:    %s\n", ansiGreen(*ws.ArgoCDSync))
				case "OutOfSync":
					fmt.Printf("  ArgoCD Sync:    %s\n", ansiRed(*ws.ArgoCDSync))
				default:
					fmt.Printf("  ArgoCD Sync:    %s\n", *ws.ArgoCDSync)
				}
			}
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(statusCmd)
	statusCmd.Flags().BoolVar(&statusCmdFlags.json, "json", false, "Output as JSON")
}

func ansiGreen(s string) string  { return "\033[0;32m" + s + "\033[0m" }
func ansiYellow(s string) string { return "\033[0;33m" + s + "\033[0m" }
func ansiRed(s string) string    { return "\033[0;31m" + s + "\033[0m" }
