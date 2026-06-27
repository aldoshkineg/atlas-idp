package internal

import (
	"context"

	"github.com/sethvargo/go-envconfig"
)

type Config struct {
	HTTP            HTTPConfig
	Database        DatabaseConfig
	Redis           RedisConfig
	MinioEndpoint   string `env:"MINIO_ENDPOINT, default=localhost:9000"`
	DownloadBaseURL string `env:"DOWNLOAD_URL_PREFIX, default=http://localhost:9000"`
	Telemetry       TelemetryConfig
}

type HTTPConfig struct {
	Port      int    `env:"HTTP_PORT, default=8080"`
	LogLevel  string `env:"LOG_LEVEL, default=info"`
	LogFormat string `env:"LOG_FORMAT, default=text"`
}

type DatabaseConfig struct {
	Host     string `env:"POSTGRES_HOST, default=localhost"`
	Port     int    `env:"POSTGRES_PORT, default=5432"`
	User     string `env:"POSTGRES_USER, default=seal"`
	Password string `env:"POSTGRES_PASSWORD, required"`
	DBName   string `env:"POSTGRES_DB, default=seal"`
}

func (d DatabaseConfig) ConnString() string {
	return "postgres://" + d.User + ":" + d.Password +
		"@" + d.Host + ":" + itoa(d.Port) + "/" + d.DBName +
		"?sslmode=disable"
}

type RedisConfig struct {
	Host     string `env:"REDIS_HOST, default=localhost"`
	Port     int    `env:"REDIS_PORT, default=6379"`
	Password string `env:"REDIS_PASSWORD, default="`
}

func (r RedisConfig) Addr() string {
	return r.Host + ":" + itoa(r.Port)
}

type TelemetryConfig struct {
	OTLPEndpoint string `env:"OTEL_EXPORTER_OTLP_ENDPOINT, default="`
}

func LoadConfig(ctx context.Context) (Config, error) {
	var cfg Config
	err := envconfig.Process(ctx, &cfg)
	return cfg, err
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	buf := make([]byte, 0, 10)
	for n > 0 {
		buf = append(buf, byte('0'+n%10))
		n /= 10
	}
	for i, j := 0, len(buf)-1; i < j; i, j = i+1, j-1 {
		buf[i], buf[j] = buf[j], buf[i]
	}
	return string(buf)
}
