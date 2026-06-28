package cmd

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/template"
	"github.com/spf13/cobra"
)

type newFlags struct {
	group       string
	repoURL     string
	namespace   string
	repoPath    string
	helm        bool
	helmValues  string
	sa          string
	skipConfirm bool
}

var newCmdFlags newFlags

var newCmd = &cobra.Command{
	Use:   "new APP --group GROUP --repo URL",
	Short: "Scaffold a new workload from golden-path templates",
	Long: `Scaffold a workload directory under workloads/<group>/<app>/ with
golden-path manifests (ArgoCD Application, ExternalSecrets, Vault policies,
monitoring, and infrastructure resources).

Required:
  --group GROUP   Team/group name
  --repo URL      Application repository URL`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		app := args[0]

		if newCmdFlags.group == "" {
			return fmt.Errorf("--group is required")
		}
		if newCmdFlags.repoURL == "" {
			return fmt.Errorf("--repo is required")
		}

		appUC := strings.ToUpper(strings.ReplaceAll(app, "-", "_"))
		groupUC := strings.ToUpper(strings.ReplaceAll(newCmdFlags.group, "-", "_"))
		namespace := newCmdFlags.namespace
		if namespace == "" {
			namespace = newCmdFlags.group + "-" + app
		}
		sa := newCmdFlags.sa
		if sa == "" {
			sa = app
		}

		workloadDir := filepath.Join(Cfg.Scaffold.Directory, newCmdFlags.group, app)
		if _, err := os.Stat(workloadDir); err == nil {
			return fmt.Errorf("workload already exists: %s", workloadDir)
		} else if !os.IsNotExist(err) {
			return fmt.Errorf("stat %s: %w", workloadDir, err)
		}

		var helmValuesIndented, gitopsHelmValues string
		if newCmdFlags.helm && newCmdFlags.helmValues != "" {
			helmValuesIndented = indentLines(newCmdFlags.helmValues, "        ")
			gitopsHelmValues = indentLines(newCmdFlags.helmValues, "          ")
		}

		fmt.Println("---")
		fmt.Printf("Scaffolding new workload:\n")
		fmt.Printf("  App:       %s\n", app)
		fmt.Printf("  Group:     %s\n", newCmdFlags.group)
		fmt.Printf("  Namespace: %s\n", namespace)
		fmt.Printf("  Repo:      %s (path: %s)\n", newCmdFlags.repoURL, newCmdFlags.repoPath)
		fmt.Println("---")

		if !newCmdFlags.skipConfirm {
			fmt.Print("Create workload? [y/N]: ")
			var resp string
			fmt.Scanln(&resp)
			resp = strings.TrimSpace(strings.ToLower(resp))
			if resp != "y" && resp != "yes" {
				return fmt.Errorf("aborted")
			}
		}

		v := template.Vars{
			APP:           app,
			APP_UC:        appUC,
			GROUP:         newCmdFlags.group,
			GROUP_UC:      groupUC,
			NAMESPACE:     namespace,
			REPO_URL:      newCmdFlags.repoURL,
			REPO_PATH:     newCmdFlags.repoPath,
			HOSTNAME:      app + ".atlas",
			SERVICE_ACCOUNTS: sa,
			HelmValuesIndented:  helmValuesIndented,
			GitopsHelmValues:   gitopsHelmValues,
		}

		if err := os.MkdirAll(workloadDir, 0755); err != nil {
			return fmt.Errorf("mkdir %s: %w", workloadDir, err)
		}

		if err := renderAllTemplates(workloadDir, v); err != nil {
			return err
		}

		secrets, err := template.GenerateSeed(Cfg.Seed.Keys)
		if err != nil {
			return fmt.Errorf("generate seed: %w", err)
		}
		secretSeedContent := template.SecretSeedEnv(groupUC, appUC, secrets)
		secretSeedPath := filepath.Join(workloadDir, ".secret-seed")
		if err := os.WriteFile(secretSeedPath, []byte(secretSeedContent), 0644); err != nil {
			return fmt.Errorf("write .secret-seed: %w", err)
		}

		fmt.Println()
		fmt.Printf("=== Workload %s/%s scaffolded ===\n", newCmdFlags.group, app)
		fmt.Println()
		fmt.Println("Next steps:")
		fmt.Println("  1. Review and customize files in " + workloadDir + "/")
		fmt.Println("  2. Edit .secret-seed if needed (passwords already generated)")
		fmt.Println("  3. Run: atlasctl seed " + newCmdFlags.group + "/" + app)
		fmt.Println("  4. Run: atlasctl enable " + newCmdFlags.group + "/" + app + " [--sync]")

		return nil
	},
}

func indentLines(s, indent string) string {
	lines := strings.Split(s, "\n")
	for i, line := range lines {
		if line != "" {
			lines[i] = indent + line
		}
	}
	return strings.Join(lines, "\n")
}

func renderAllTemplates(workloadDir string, v template.Vars) error {
	srcPrefix := Cfg.Templates.GoldDir

	return fs.WalkDir(TemplatesFS, srcPrefix, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		if !strings.HasSuffix(path, ".tmpl") {
			return nil
		}

		rel, _ := filepath.Rel(srcPrefix, path)
		dstName := strings.TrimSuffix(rel, ".tmpl")
		dst := filepath.Join(workloadDir, dstName)

		if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
			return fmt.Errorf("mkdir %s: %w", filepath.Dir(dst), err)
		}

		rendered, err := template.RenderFile(TemplatesFS, path, v, &Cfg.Defaults)
		if err != nil {
			return fmt.Errorf("render %s: %w", path, err)
		}
		if err := os.WriteFile(dst, []byte(rendered), 0644); err != nil {
			return fmt.Errorf("write %s: %w", dst, err)
		}
		return nil
	})
}

func init() {
	rootCmd.AddCommand(newCmd)
	newCmd.Flags().StringVar(&newCmdFlags.group, "group", "", "Team/group name (required)")
	newCmd.Flags().StringVar(&newCmdFlags.repoURL, "repo", "", "Application repository URL (required)")
	newCmd.Flags().StringVar(&newCmdFlags.namespace, "namespace", "", "Kubernetes namespace (default: <group>-<app>)")
	newCmd.Flags().StringVar(&newCmdFlags.repoPath, "repo-path", ".", "Path to manifests within repo")
	newCmd.Flags().BoolVar(&newCmdFlags.helm, "helm", false, "Use Helm chart")
	newCmd.Flags().StringVar(&newCmdFlags.helmValues, "helm-values", "", "Inline Helm values string or file path")
	newCmd.Flags().StringVar(&newCmdFlags.sa, "sa", "", "Service account for Vault auth (default: <app>)")
	newCmd.Flags().BoolVarP(&newCmdFlags.skipConfirm, "yes", "y", false, "Skip confirmation prompt")
}
