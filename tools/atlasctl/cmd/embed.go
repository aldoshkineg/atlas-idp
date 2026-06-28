package cmd

import (
	"fmt"
	"io/fs"
	"os"

	"github.com/aldoshkineg/atlas-idp/tools/atlasctl/pkg/config"
)

var (
	TemplatesFS fs.FS
	Cfg         *config.Config
)

func InitCfg() error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("load config: %w", err)
	}
	Cfg = cfg
	return nil
}

func InitTemplatesFS() error {
	if Cfg == nil {
		if err := InitCfg(); err != nil {
			return err
		}
	}

	if _, err := os.Stat(Cfg.Templates.Dir); err != nil {
		return fmt.Errorf("templates dir %s: %w (run 'atlasctl init' first)", Cfg.Templates.Dir, err)
	}
	TemplatesFS = os.DirFS(Cfg.Templates.Dir)
	return nil
}
