package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var Version = "dev"

var rootCmd = &cobra.Command{
	Use:   "atlasctl",
	Short: "Workload lifecycle management CLI for Atlas IDP",
	Long: `atlasctl manages the full lifecycle of platform workloads —
from scaffolding golden-path templates to GitOps promotion via Argo CD.

  new       Scaffold a workload from golden-path templates
  seed      Provision DB, S3 bucket, and write secrets to Vault
  enable    Promote workload to GitOps (ArgoCD Application + gateway)
  disable   Remove workload from GitOps
  delete    Delete workload directory (only if disabled)
  status    Show workload status
  list      List all registered workloads
  logs      Tail workload logs
  backup    Trigger CNPG backup`,

	Version: Version,
	PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
		if Cfg == nil {
			if err := InitCfg(); err != nil {
				return err
			}
		}
		return nil
	},
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
