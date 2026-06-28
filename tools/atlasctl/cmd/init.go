package cmd

import (
	"fmt"
	"os"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/config"
	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize atlasctl configuration",
	Long: `Discover the repository root and save absolute paths to
~/.config/atlasctl/config.yaml for all subsequent commands.

Run this once from within the repository.`,
	Args: cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		repoRoot, err := config.FindRepoRoot()
		if err != nil {
			return fmt.Errorf("not in a repository: %w.\nRun 'atlasctl init' from the repository root", err)
		}

		cfgDir := config.UserConfigDir()
		if err := os.MkdirAll(cfgDir, 0755); err != nil {
			return fmt.Errorf("create config dir %s: %w", cfgDir, err)
		}

		cfgPath := config.UserConfigPath()
		if _, err := os.Stat(cfgPath); err == nil {
			fmt.Print("Config already exists. Overwrite? [y/N]: ")
			var resp string
			fmt.Scanln(&resp)
			if resp != "y" && resp != "yes" {
				return fmt.Errorf("aborted")
			}
		}

		defaultCfg, err := config.Load()
		if err != nil {
			return fmt.Errorf("load config: %w", err)
		}

		userCfg := map[string]interface{}{
			"templates": map[string]string{"dir": defaultCfg.Templates.Dir},
			"scaffold":  map[string]string{"dir": defaultCfg.Scaffold.Dir},
			"gitops": map[string]string{
				"workloads_dir":      defaultCfg.Gitops.WorkloadsDir,
				"gateway_file":       defaultCfg.Gitops.GatewayFile,
				"gateway_routes_dir": defaultCfg.Gitops.GatewayRoutesDir,
			},
		}

		data, err := yaml.Marshal(userCfg)
		if err != nil {
			return fmt.Errorf("marshal config: %w", err)
		}

		if err := os.WriteFile(cfgPath, data, 0644); err != nil {
			return fmt.Errorf("write %s: %w", cfgPath, err)
		}

		fmt.Printf("Config written to %s\n", cfgPath)
		fmt.Printf("  Repo root:     %s\n", repoRoot)
		fmt.Printf("  Templates:     %s\n", defaultCfg.Templates.Dir)
		fmt.Printf("  Workloads:     %s\n", defaultCfg.Scaffold.Dir)
		fmt.Printf("  GitOps dir:    %s\n", defaultCfg.Gitops.WorkloadsDir)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(initCmd)
}
