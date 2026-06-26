package internal

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

const (
	QueueKey        = "seal:jobs"
	ResultsQueueKey = "seal:results"
)

type Queue struct {
	client *redis.Client
}

func NewQueue(ctx context.Context, addr, password string) (*Queue, error) {
	client := redis.NewClient(&redis.Options{
		Addr:         addr,
		Password:     password,
		DialTimeout:  5 * time.Second,
		ReadTimeout:  3 * time.Second,
		WriteTimeout: 3 * time.Second,
	})
	if err := client.Ping(ctx).Err(); err != nil {
		return nil, err
	}
	client.AddHook(&redisTracer{})
	return &Queue{client: client}, nil
}

func (q *Queue) Close() error {
	return q.client.Close()
}

type JobMessage struct {
	DocumentID  string `json:"document_id"`
	InputText   string `json:"input_text"`
	TraceParent string `json:"traceparent,omitempty"`
}

func (q *Queue) PushTask(ctx context.Context, documentID, inputText string) error {
	msg := JobMessage{
		DocumentID: documentID,
		InputText:  inputText,
	}

	propagator := otel.GetTextMapPropagator()
	carrier := propagation.MapCarrier{}
	propagator.Inject(ctx, carrier)
	if tp, ok := carrier["traceparent"]; ok {
		msg.TraceParent = tp
	}

	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	return q.client.RPush(ctx, QueueKey, string(data)).Err()
}

func (q *Queue) PopResult(ctx context.Context, timeout time.Duration) (string, error) {
	items, err := q.client.BLPop(ctx, timeout, ResultsQueueKey).Result()
	if err != nil {
		return "", err
	}
	if len(items) < 2 {
		return "", fmt.Errorf("unexpected BLPop result: %v", items)
	}
	return items[1], nil
}

type redisTracer struct{}

func (h *redisTracer) DialHook(next redis.DialHook) redis.DialHook {
	return next
}

func (h *redisTracer) ProcessHook(next redis.ProcessHook) redis.ProcessHook {
	return func(ctx context.Context, cmd redis.Cmder) error {
		ctx, span := otel.Tracer("seal-api").Start(ctx, "REDIS "+cmd.Name(),
			trace.WithAttributes(attribute.String("redis.cmd", cmd.String())))
		defer span.End()
		err := next(ctx, cmd)
		if err != nil {
			span.RecordError(err)
		}
		return err
	}
}

func (h *redisTracer) ProcessPipelineHook(next redis.ProcessPipelineHook) redis.ProcessPipelineHook {
	return func(ctx context.Context, cmds []redis.Cmder) error {
		ctx, span := otel.Tracer("seal-api").Start(ctx, "REDIS pipeline",
			trace.WithAttributes(attribute.Int("redis.pipeline_size", len(cmds))))
		defer span.End()
		return next(ctx, cmds)
	}
}
