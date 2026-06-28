package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/k8s"
	"github.com/spf13/cobra"
	"sigs.k8s.io/yaml"
)

type logsFlags struct {
	tail  int
	follow bool
}

var logsCmdFlags logsFlags

var logsCmd = &cobra.Command{
	Use:   "logs GROUP/APP",
	Short: "Tail workload logs from Kubernetes",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		group, app, err := parseWorkloadArg(args[0])
		if err != nil {
			return err
		}

		namespace := group + "-" + app
		appYaml := filepath.Join(Cfg.Scaffold.Dir, group, app, "app.yaml")
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

		client := k8s.New()
		podName, err := client.GetPodName(namespace, "app.kubernetes.io/instance="+app)
		if err != nil {
			return fmt.Errorf("get pod for %s/%s: %w", namespace, app, err)
		}

		logs, err := client.PodLogs(namespace, podName, logsCmdFlags.tail)
		if err != nil {
			return fmt.Errorf("get logs for %s/%s: %w", namespace, podName, err)
		}

		fmt.Print(logs)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(logsCmd)
	logsCmd.Flags().IntVar(&logsCmdFlags.tail, "tail", 50, "Number of lines to show from the end")
}
