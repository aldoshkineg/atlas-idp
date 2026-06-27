package internal

import (
	"context"

	"github.com/sethvargo/go-envconfig"
)

type Config struct {
	HTTP          HTTPConfig
	BackendAPIURL string `env:"BACKEND_API_URL, default=http://localhost:8080"`
	Telemetry     TelemetryConfig
}

type HTTPConfig struct {
	Port      int    `env:"HTTP_PORT, default=8081"`
	LogLevel  string `env:"LOG_LEVEL, default=info"`
	LogFormat string `env:"LOG_FORMAT, default=text"`
}

type TelemetryConfig struct {
	OTLPEndpoint string `env:"OTEL_EXPORTER_OTLP_ENDPOINT, default="`
}

func LoadConfig(ctx context.Context) (Config, error) {
	var cfg Config
	err := envconfig.Process(ctx, &cfg)
	return cfg, err
}
