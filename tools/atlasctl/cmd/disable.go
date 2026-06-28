package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/gitops"
	"github.com/spf13/cobra"
)

type disableFlags struct {
	dryRun      bool
	sync        bool
	push        bool
	skipConfirm bool
}

var disableCmdFlags disableFlags

var disableCmd = &cobra.Command{
	Use:   "disable GROUP/APP",
	Short: "Remove workload from GitOps",
	Long: `Removes gateway listener, ArgoCD Application CR from gitops/workloads/,
gateway route file, and empty group directory. Keeps the workload directory.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		group, app, err := parseWorkloadArg(args[0])
		if err != nil {
			return err
		}

		ref := gitops.WorkloadRef{Group: group, App: app}
		p := gitops.ResolvePaths(ref, &Cfg.Gitops, Cfg.Scaffold.Dir)

		if _, err := os.Stat(p.GitopsFile); os.IsNotExist(err) {
			return fmt.Errorf("not enabled — %s does not exist", p.GitopsFile)
		}

		hasGateway := false
		if _, err := os.Stat(p.GatewayRouteFile); err == nil {
			hasGateway = true
		}

		fmt.Println("---")
		fmt.Printf("Disabling workload: %s/%s\n", group, app)
		fmt.Printf("  GitOps file:    %s (remove)\n", p.GitopsFile)
		fmt.Printf("  Workload dir:   %s (kept)\n", p.WorkloadDir)
		fmt.Printf("  Gateway patch:  %v\n", hasGateway)
		fmt.Println("---")

		if disableCmdFlags.dryRun {
			fmt.Println("\n>> Would remove listener from: " + p.GatewayFile)
			fmt.Println("   name: https-" + app)
			fmt.Println("\n>> Would delete: " + p.GitopsFile)
			if _, err := os.Stat(p.GitopsResources); err == nil {
				fmt.Println(">> Would delete directory: " + p.GitopsResources + "/")
			}
			if hasGateway {
				fmt.Println(">> Would delete: " + p.GatewayRouteFile)
			}
			fmt.Println("\nDRY RUN — no changes made")
			return nil
		}

		if !disableCmdFlags.skipConfirm {
			fmt.Print("Disable this workload? [y/N]: ")
			var resp string
			fmt.Scanln(&resp)
			resp = strings.TrimSpace(strings.ToLower(resp))
			if resp != "y" && resp != "yes" {
				return fmt.Errorf("aborted")
			}
		}

		msg, err := gitops.ApplyGatewayListener(p.GatewayFile, gitops.GatewayListenerChange{
			App:      app,
			Hostname: app + ".atlas",
			Add:      false,
		})
		if err != nil {
			return fmt.Errorf("remove gateway listener: %w", err)
		}
		fmt.Println(msg)

		if err := os.Remove(p.GitopsFile); err != nil {
			return fmt.Errorf("remove gitops file: %w", err)
		}
		fmt.Printf("  [gitops] Removed %s\n", p.GitopsFile)

		gitops.RemoveAll(p.GitopsResources)
		if _, err := os.Stat(p.GitopsResources); os.IsNotExist(err) {
			fmt.Printf("  [gitops] Removed directory %s/\n", p.GitopsResources)
		}

		workloadAppDir := filepath.Dir(p.GitopsResources)
		gitops.RemoveEmptyDir(workloadAppDir)

		if hasGateway {
			if err := os.Remove(p.GatewayRouteFile); err != nil {
				return fmt.Errorf("remove gateway route: %w", err)
			}
			fmt.Printf("  [gateway-routes] Removed %s\n", p.GatewayRouteFile)
		}

		gitops.RemoveEmptyDir(p.GitopsDir)

		if disableCmdFlags.sync {
			gitArgs := []string{"add", "-A", "--", p.GitopsDir, p.GatewayFile}
			if hasGateway {
				gitArgs = append(gitArgs, p.GatewayRouteFile)
			}
			exec.Command("git", gitArgs...).Run()

			if out, err := exec.Command("git", "commit",
				"-m", fmt.Sprintf("disable(workloads): remove %s/%s", group, app)).CombinedOutput(); err != nil {
				fmt.Printf("   (nothing to commit: %s)", string(out))
			}

			if disableCmdFlags.push {
				if out, err := exec.Command("git", "push").CombinedOutput(); err != nil {
					return fmt.Errorf("git push: %s: %w", string(out), err)
				}
				fmt.Println("  [push] Changes pushed")
			} else {
				fmt.Println("  (use --push to push commits)")
			}
		}

		fmt.Println("\n=== Disable complete for", group+"/"+app, "===")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(disableCmd)
	disableCmd.Flags().BoolVar(&disableCmdFlags.dryRun, "dry-run", false, "Preview changes without applying")
	disableCmd.Flags().BoolVar(&disableCmdFlags.sync, "sync", false, "Commit changes to git")
	disableCmd.Flags().BoolVar(&disableCmdFlags.push, "push", false, "Push commits to remote (implies --sync)")
	disableCmd.Flags().BoolVarP(&disableCmdFlags.skipConfirm, "yes", "y", false, "Skip confirmation prompt")
}
