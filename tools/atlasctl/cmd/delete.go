package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
)

type deleteFlags struct {
	dryRun      bool
	skipConfirm bool
}

var deleteCmdFlags deleteFlags

var deleteCmd = &cobra.Command{
	Use:   "delete GROUP/APP",
	Short: "Delete workload directory (only if disabled)",
	Long: `Deletes the workloads/<group>/<app>/ directory. Refuses if the
workload is still enabled (has a corresponding gitops/workloads/<group>/<app>.yaml).`,
	Args: cobra.ExactArgs(1),
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

		if _, err := os.Stat(gitopsFile); err == nil {
			return fmt.Errorf("workload %s/%s is still enabled. Run 'atlasctl disable %s/%s' first",
				group, app, group, app)
		}

		fmt.Println("---")
		fmt.Printf("Deleting workload: %s/%s\n", group, app)
		fmt.Printf("  Workload dir:   %s (remove)\n", workloadDir)
		fmt.Println("---")

		if deleteCmdFlags.dryRun {
			fmt.Println("\n>> Would delete: " + workloadDir + "/")
			fmt.Println("\nDRY RUN — no changes made")
			return nil
		}

		if !deleteCmdFlags.skipConfirm {
			fmt.Print("Delete workload directory? [y/N]: ")
			var resp string
			fmt.Scanln(&resp)
			resp = strings.TrimSpace(strings.ToLower(resp))
			if resp != "y" && resp != "yes" {
				return fmt.Errorf("aborted")
			}
		}

		if err := os.RemoveAll(workloadDir); err != nil {
			return fmt.Errorf("remove workload dir: %w", err)
		}
		fmt.Printf("  [workload] Removed %s/\n", workloadDir)

		groupDir := filepath.Dir(workloadDir)
		entries, err := os.ReadDir(groupDir)
		if err == nil && len(entries) == 0 {
			os.Remove(groupDir)
			fmt.Printf("  [workload] Removed empty directory %s\n", groupDir)
		}

		fmt.Println("\n=== Delete complete for", group+"/"+app, "===")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(deleteCmd)
	deleteCmd.Flags().BoolVar(&deleteCmdFlags.dryRun, "dry-run", false, "Preview changes without applying")
	deleteCmd.Flags().BoolVarP(&deleteCmdFlags.skipConfirm, "yes", "y", false, "Skip confirmation prompt")
}
