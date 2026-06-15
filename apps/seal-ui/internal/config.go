package internal

import (
	"context"

	"github.com/sethvargo/go-envconfig"
)

type Config struct {
	HTTP          HTTPConfig
	BackendAPIURL string `env:"BACKEND_API_URL, default=http://localhost:8080"`
}

type HTTPConfig struct {
	Port     int    `env:"HTTP_PORT, default=8081"`
	LogLevel string `env:"LOG_LEVEL, default=info"`
}

func LoadConfig(ctx context.Context) (Config, error) {
	var cfg Config
	err := envconfig.Process(ctx, &cfg)
	return cfg, err
}
