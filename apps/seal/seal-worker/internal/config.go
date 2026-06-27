package internal

import (
	"context"

	"github.com/sethvargo/go-envconfig"
)

type Config struct {
	Crypto    CryptoConfig
	Redis     RedisConfig
	Minio     MinioConfig
	Telemetry TelemetryConfig
	Worker    WorkerConfig
}

type CryptoConfig struct {
	CertPath string `env:"SIGN_CERT_PATH, default=/vault/secrets/tls.crt"`
	KeyPath  string `env:"SIGN_KEY_PATH, default=/vault/secrets/tls.key"`
}

type RedisConfig struct {
	Host     string `env:"REDIS_HOST, default=localhost"`
	Port     int    `env:"REDIS_PORT, default=6379"`
	Password string `env:"REDIS_PASSWORD, default="`
}

func (r RedisConfig) Addr() string {
	return r.Host + ":" + itoa(r.Port)
}

type MinioConfig struct {
	Endpoint  string `env:"MINIO_ENDPOINT, default=localhost:9000"`
	AccessKey string `env:"MINIO_ACCESS_KEY, required"`
	SecretKey string `env:"MINIO_SECRET_KEY, required"`
	UseSSL    bool   `env:"MINIO_USE_SSL, default=false"`
}

type TelemetryConfig struct {
	OTLPEndpoint string `env:"OTEL_EXPORTER_OTLP_ENDPOINT, default="`
}

type WorkerConfig struct {
	PollInterval int    `env:"WORKER_POLL_INTERVAL_MS, default=1000"`
	LogLevel     string `env:"LOG_LEVEL, default=info"`
	LogFormat    string `env:"LOG_FORMAT, default=text"`
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
