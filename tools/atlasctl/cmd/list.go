package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/gateway"
	"github.com/spf13/cobra"
)

type listFlags struct {
	json bool
}

var listCmdFlags listFlags

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List all registered workloads",
	RunE: func(cmd *cobra.Command, args []string) error {
		workloadsDir := Cfg.Scaffold.Dir
		if _, err := os.Stat(workloadsDir); os.IsNotExist(err) {
			if listCmdFlags.json {
				fmt.Println("[]")
			} else {
				fmt.Println("No workloads found")
			}
			return nil
		}

		type workloadItem struct {
			Name            string   `json:"name"`
			Features        []string `json:"features"`
			Enabled         bool     `json:"enabled"`
			GatewayListener bool     `json:"gateway_listener"`
		}

		var items []workloadItem

		groupEntries, _ := os.ReadDir(workloadsDir)
		for _, ge := range groupEntries {
			if !ge.IsDir() {
				continue
			}
			group := ge.Name()
			groupDir := filepath.Join(workloadsDir, group)
			appEntries, _ := os.ReadDir(groupDir)
			for _, ae := range appEntries {
				if !ae.IsDir() {
					continue
				}
				app := ae.Name()
				appYaml := filepath.Join(groupDir, app, "app.yaml")
				if _, err := os.Stat(appYaml); os.IsNotExist(err) {
					continue
				}

				features := detectFeatures(filepath.Join(groupDir, app))
				if len(features) == 0 {
					features = []string{"none"}
				}

				enabled := false
				gitopsFile := filepath.Join(Cfg.Gitops.WorkloadsDir, group, app+".yaml")
				if _, err := os.Stat(gitopsFile); err == nil {
					enabled = true
				}

				gwListener := gateway.HasListenerInFile(Cfg.Gitops.GatewayFile, app)

				items = append(items, workloadItem{
					Name:            group + "/" + app,
					Features:        features,
					Enabled:         enabled,
					GatewayListener: gwListener,
				})
			}
		}

		if listCmdFlags.json {
			data, _ := json.MarshalIndent(items, "", "  ")
			fmt.Println(string(data))
		} else {
			if len(items) == 0 {
				fmt.Println("No workloads found")
				return nil
			}
			fmt.Println("Workloads:")
			for _, item := range items {
				var statusIcon string
				if item.Enabled {
					statusIcon = ansiGreen("✓")
				} else {
					statusIcon = ansiYellow("○")
				}
				fmt.Printf("  %s %s  [%s]\n", statusIcon, item.Name, strings.Join(item.Features, " "))
			}
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(listCmd)
	listCmd.Flags().BoolVar(&listCmdFlags.json, "json", false, "Output as JSON")
}
