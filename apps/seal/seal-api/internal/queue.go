package internal

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	QueueKey       = "seal:jobs"
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
	return &Queue{client: client}, nil
}

func (q *Queue) Close() error {
	return q.client.Close()
}

type JobMessage struct {
	DocumentID string `json:"document_id"`
	InputText  string `json:"input_text"`
}

func (q *Queue) PushTask(ctx context.Context, documentID, inputText string) error {
	msg := JobMessage{DocumentID: documentID, InputText: inputText}
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
