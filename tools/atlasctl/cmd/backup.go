package cmd

import (
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

type backupFlags struct {
	cluster   string
	namespace string
	dryRun    bool
}

var backupCmdFlags backupFlags

var backupCmd = &cobra.Command{
	Use:   "backup GROUP/APP",
	Short: "Trigger CNPG backup for the workload's database",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		_, app, err := parseWorkloadArg(args[0])
		if err != nil {
			return err
		}

		cluster := backupCmdFlags.cluster
		if cluster == "" {
			cluster = strings.ReplaceAll(Cfg.Backup.ClusterPattern, "{{APP}}", app)
		}
		namespace := backupCmdFlags.namespace
		if namespace == "" {
			namespace = Cfg.Backup.Namespace
		}

		backupName := fmt.Sprintf("manual-%s-%d", app, time.Now().Unix())
		yaml := fmt.Sprintf(`apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: %s
  namespace: %s
spec:
  cluster:
    name: %s
`, backupName, namespace, cluster)

		fmt.Println("---")
		fmt.Printf("Triggering backup for: %s/%s\n", args[0], cluster)
		fmt.Printf("  Backup name:    %s\n", backupName)
		fmt.Printf("  Cluster:        %s\n", cluster)
		fmt.Printf("  Namespace:      %s\n", namespace)
		fmt.Println("---")

		if backupCmdFlags.dryRun {
			fmt.Println("\n>> Would apply:")
			fmt.Println(yaml)
			fmt.Println("DRY RUN — no changes made")
			return nil
		}

		kc := exec.Command("kubectl", "apply", "-f", "-")
		kc.Stdin = strings.NewReader(yaml)
		out, err := kc.CombinedOutput()
		if err != nil {
			return fmt.Errorf("kubectl apply backup: %s: %w", strings.TrimSpace(string(out)), err)
		}
		fmt.Printf("  [backup] %s", strings.TrimSpace(string(out)))
		return nil
	},
}

func init() {
	rootCmd.AddCommand(backupCmd)
	backupCmd.Flags().StringVar(&backupCmdFlags.cluster, "cluster", "", "CNPG cluster name (default from config)")
	backupCmd.Flags().StringVar(&backupCmdFlags.namespace, "namespace", "", "Kubernetes namespace (default from config)")
	backupCmd.Flags().BoolVar(&backupCmdFlags.dryRun, "dry-run", false, "Preview without triggering")
}
