package internal

import (
	"context"
	"time"

	"github.com/redis/go-redis/v9"
)

const QueueKey = "text2pdf:jobs"

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
	return &Queue{client: client}, nil
}

func (q *Queue) Close() error {
	return q.client.Close()
}

func (q *Queue) PushTask(ctx context.Context, taskID string) error {
	return q.client.RPush(ctx, QueueKey, taskID).Err()
}
