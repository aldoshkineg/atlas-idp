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

type enableFlags struct {
	dryRun      bool
	sync        bool
	push        bool
	force       bool
	skipConfirm bool
}

var enableCmdFlags enableFlags

var enableCmd = &cobra.Command{
	Use:   "enable GROUP/APP",
	Short: "Promote workload to GitOps (ArgoCD Application + gateway)",
	Long: `Creates an ArgoCD Application CR in gitops/workloads/<group>/<app>.yaml,
syncs manifests to gitops/workloads/<group>/<app>/resources/, copies
infra/gateway.yaml to gateway-routes/<app>.yaml, and adds a TLS listener
to the shared gateway.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		group, app, err := parseWorkloadArg(args[0])
		if err != nil {
			return err
		}

		ref := gitops.WorkloadRef{Group: group, App: app}
		p := gitops.ResolvePaths(ref, &Cfg.Gitops, Cfg.Scaffold.Dir)

		if !enableCmdFlags.force {
			if _, err := os.Stat(p.WorkloadDir); os.IsNotExist(err) {
				return fmt.Errorf("workload not found: %s", p.WorkloadDir)
			}
			if _, err := os.Stat(filepath.Join(p.WorkloadDir, "app.yaml")); os.IsNotExist(err) {
				return fmt.Errorf("app.yaml not found in %s", p.WorkloadDir)
			}
			if _, err := os.Stat(p.GitopsFile); err == nil {
				return fmt.Errorf("already enabled at %s (use --force to overwrite)", p.GitopsFile)
			}
		}

		namespace := group + "-" + app
		hasGateway := false
		gwYaml := filepath.Join(p.WorkloadDir, "infra", "gateway.yaml")
		if _, err := os.Stat(gwYaml); err == nil {
			hasGateway = true
		}

		fmt.Println("---")
		fmt.Printf("Enabling workload: %s/%s\n", group, app)
		fmt.Printf("  Namespace:      %s\n", namespace)
		fmt.Printf("  GitOps file:    %s\n", p.GitopsFile)
		fmt.Printf("  Gateway patch:  %v\n", hasGateway)
		fmt.Println("---")

		if enableCmdFlags.dryRun {
			fmt.Println("\n>> Would copy app.yaml → " + p.GitopsFile)
			fmt.Println(">> Would sync workload/ manifests → " + p.GitopsResources + "/")
			if hasGateway {
				fmt.Println("\n>> Would copy infra/gateway.yaml → " + p.GatewayRouteFile)
				fmt.Println(">> Would add listener to: " + p.GatewayFile)
				fmt.Println("   name: https-" + app)
				fmt.Println("   hostname: " + app + ".atlas")
			}
			fmt.Println("\nDRY RUN — no changes made")
			return nil
		}

		if !enableCmdFlags.skipConfirm {
			fmt.Print("Enable this workload? [y/N]: ")
			var resp string
			fmt.Scanln(&resp)
			resp = strings.TrimSpace(strings.ToLower(resp))
			if resp != "y" && resp != "yes" {
				return fmt.Errorf("aborted")
			}
		}

		if err := os.MkdirAll(p.GitopsDir, 0755); err != nil {
			return fmt.Errorf("mkdir gitops dir: %w", err)
		}

		if err := gitops.CopyWorkloadManifest(
			filepath.Join(p.WorkloadDir, "app.yaml"), p.GitopsFile); err != nil {
			return err
		}
		fmt.Printf("  [app] Copied to %s\n", p.GitopsFile)

		if err := gitops.SyncResources(p.WorkloadDir, p.GitopsResources); err != nil {
			return fmt.Errorf("sync resources: %w", err)
		}
		fmt.Printf("  [workload] Synced manifests to %s/\n", p.GitopsResources)

		if hasGateway {
			if err := os.MkdirAll(p.GatewayRoutesDir, 0755); err != nil {
				return fmt.Errorf("mkdir gateway-routes dir: %w", err)
			}
			if err := gitops.CopyWorkloadManifest(gwYaml, p.GatewayRouteFile); err != nil {
				return err
			}
			fmt.Printf("  [gateway-routes] Copied infra/gateway.yaml → %s\n", p.GatewayRouteFile)

			msg, err := gitops.ApplyGatewayListener(p.GatewayFile, gitops.GatewayListenerChange{
				App:      app,
				Hostname: app + ".atlas",
				CertName: app + "-cert",
				Add:      true,
			})
			if err != nil {
				return fmt.Errorf("add gateway listener: %w", err)
			}
			fmt.Println(msg)
		}

		if enableCmdFlags.sync {
			if err := gitCommitAndMaybePush(app, group, p, enableCmdFlags.push); err != nil {
				return err
			}
		}

		fmt.Println("\n=== Enable complete for", group+"/"+app, "===")
		fmt.Println("\nNext step: atlasctl status", group+"/"+app)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(enableCmd)
	enableCmd.Flags().BoolVar(&enableCmdFlags.dryRun, "dry-run", false, "Preview changes without applying")
	enableCmd.Flags().BoolVar(&enableCmdFlags.sync, "sync", false, "Commit changes to git")
	enableCmd.Flags().BoolVar(&enableCmdFlags.push, "push", false, "Push commits to remote (implies --sync)")
	enableCmd.Flags().BoolVar(&enableCmdFlags.force, "force", false, "Overwrite existing GitOps Application")
	enableCmd.Flags().BoolVarP(&enableCmdFlags.skipConfirm, "yes", "y", false, "Skip confirmation prompt")
}

func gitCommitAndMaybePush(app, group string, p gitops.Paths, push bool) error {
	gitArgs := []string{"add", p.GitopsFile, p.GitopsResources}
	if _, err := os.Stat(p.GatewayRouteFile); err == nil {
		gitArgs = append(gitArgs, p.GatewayFile, p.GatewayRouteFile)
	}
	if out, err := exec.Command("git", append(gitArgs, "-A")...).CombinedOutput(); err != nil {
		return fmt.Errorf("git add: %s: %w", string(out), err)
	}

	if out, err := exec.Command("git", "commit",
		"-m", fmt.Sprintf("enable(workloads): promote %s/%s", group, app)).CombinedOutput(); err != nil {
		fmt.Printf("   (nothing to commit: %s)", string(out))
	}

	if push {
		if out, err := exec.Command("git", "push").CombinedOutput(); err != nil {
			return fmt.Errorf("git push: %s: %w", string(out), err)
		}
		fmt.Println("  [push] Changes pushed")
	} else {
		fmt.Println("  (use --push to push commits)")
	}
	return nil
}

func parseWorkloadArg(arg string) (group, app string, err error) {
	parts := strings.SplitN(arg, "/", 2)
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", "", fmt.Errorf("invalid format: use GROUP/APP")
	}
	return parts[0], parts[1], nil
}
