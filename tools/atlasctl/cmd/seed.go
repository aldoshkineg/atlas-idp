package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/k8s"
	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/seed"
	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/vault"
	"github.com/spf13/cobra"
)

type seedFlags struct {
	dryRun      bool
	force       bool
	skipConfirm bool
}

var seedCmdFlags seedFlags

var seedCmd = &cobra.Command{
	Use:   "seed GROUP/APP",
	Short: "Provision DB, S3 bucket, and write secrets to Vault",
	Long: `Provision PostgreSQL database (CNPG), MinIO bucket, and write
credentials to Vault for a workload.

Reads .secret-seed and vault/seed-mapping.conf from the workload directory.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		workloadArg := args[0]
		parts := strings.SplitN(workloadArg, "/", 2)
		if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
			return fmt.Errorf("invalid format: use GROUP/APP")
		}
		group, app := parts[0], parts[1]

		wl := seed.Workload{
			Group: group,
			App:   app,
			Dir:   filepath.Join(Cfg.Scaffold.Dir, group, app),
		}

		if !seedCmdFlags.force {
			if _, err := os.Stat(wl.Dir); os.IsNotExist(err) {
				return fmt.Errorf("workload not found: %s", wl.Dir)
			}
		}

		k8sClient := k8s.New()
		vaultClient := vault.New()
		svc := seed.New(k8sClient, vaultClient, Cfg)

		params, err := svc.LoadParams(wl)
		if err != nil {
			return fmt.Errorf("load params: %w", err)
		}

		if !seedCmdFlags.force {
			if err := svc.ValidateParams(params); err != nil {
				return fmt.Errorf("validate params: %w", err)
			}
		}

		fmt.Println("---")
		fmt.Printf("Seeding workload: %s/%s\n", group, app)
		fmt.Printf("  Namespace:      %s\n", group+"-"+app)
		fmt.Printf("  DB:             production-db-rw.database.svc.cluster.local/%s (user: %s)\n", app, app)
		fmt.Printf("  S3:             http://minio.minio.svc.cluster.local:9000/workloads/%s/%s\n", group, app)
		fmt.Printf("  Redis:          redis-master.redis.svc.cluster.local:6379\n")
		fmt.Printf("  Vault:          secret/workloads/%s/%s\n", group, app)
		fmt.Println("---")

		if seedCmdFlags.dryRun {
			fmt.Println("\nDRY RUN — no changes made")
			return nil
		}

		if !seedCmdFlags.skipConfirm {
			fmt.Print("Seed this workload? [y/N]: ")
			var resp string
			fmt.Scanln(&resp)
			resp = strings.TrimSpace(strings.ToLower(resp))
			if resp != "y" && resp != "yes" {
				return fmt.Errorf("aborted")
			}
		}

		fmt.Println("\n>> PostgreSQL: creating database and user...")
		if err := svc.ProvisionDB(params); err != nil {
			return fmt.Errorf("provision DB: %w", err)
		}

		fmt.Println("\n>> MinIO: creating bucket and user...")
		if err := svc.ProvisionS3(params); err != nil {
			return fmt.Errorf("provision S3: %w", err)
		}

		fmt.Println("\n>> Vault: writing secrets...")
		if err := svc.WriteVault(params); err != nil {
			return fmt.Errorf("write vault: %w", err)
		}

		fmt.Println("\n=== Seed complete for", group+"/"+app, "===")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(seedCmd)
	seedCmd.Flags().BoolVar(&seedCmdFlags.dryRun, "dry-run", false, "Preview changes without applying")
	seedCmd.Flags().BoolVar(&seedCmdFlags.force, "force", false, "Skip validation checks")
	seedCmd.Flags().BoolVarP(&seedCmdFlags.skipConfirm, "yes", "y", false, "Skip confirmation prompt")
}
