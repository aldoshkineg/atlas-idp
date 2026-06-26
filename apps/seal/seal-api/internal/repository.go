package internal

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type Document struct {
	ID        uuid.UUID `json:"id"`
	Status    string    `json:"status"`
	InputText string    `json:"input_text"`
	S3Path    string    `json:"s3_path,omitempty"`
	FileSize  int64     `json:"file_size"`
	Error     string    `json:"error,omitempty"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(ctx context.Context, connString string) (*Repository, error) {
	cfg, err := pgxpool.ParseConfig(connString)
	if err != nil {
		return nil, err
	}
	cfg.MaxConns = 5
	cfg.ConnConfig.Tracer = &pgxTracer{}
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		return nil, err
	}
	return &Repository{pool: pool}, nil
}

func (r *Repository) Close() {
	r.pool.Close()
}

func (r *Repository) Pool() *pgxpool.Pool {
	return r.pool
}

func (r *Repository) CreateDocument(ctx context.Context, text string) (uuid.UUID, error) {
	var id uuid.UUID
	err := r.pool.QueryRow(ctx,
		`INSERT INTO documents (input_text) VALUES ($1) RETURNING id`,
		text,
	).Scan(&id)
	return id, err
}

func (r *Repository) GetDocument(ctx context.Context, id uuid.UUID) (*Document, error) {
	doc := &Document{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, status, input_text, COALESCE(s3_path, ''), file_size, COALESCE(error, ''), created_at, updated_at
		 FROM documents WHERE id = $1`, id,
	).Scan(&doc.ID, &doc.Status, &doc.InputText, &doc.S3Path, &doc.FileSize, &doc.Error, &doc.CreatedAt, &doc.UpdatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return doc, nil
}

func (r *Repository) UpdateStatus(ctx context.Context, id uuid.UUID, status, s3Path, errorMsg string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE documents SET status = $2, s3_path = $3, error = $4, updated_at = now() WHERE id = $1`,
		id, status, s3Path, errorMsg,
	)
	return err
}

type pgxTracer struct{}

func (t *pgxTracer) TraceQueryStart(ctx context.Context, _ *pgx.Conn, data pgx.TraceQueryStartData) context.Context {
	sql := data.SQL
	if len(sql) > 80 {
		sql = sql[:80] + "..."
	}
	ctx, _ = otel.Tracer("seal-api").Start(ctx, "SQL "+sql,
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
			attribute.String("db.statement", data.SQL),
		))
	return ctx
}

func (t *pgxTracer) TraceQueryEnd(ctx context.Context, _ *pgx.Conn, data pgx.TraceQueryEndData) {
	span := trace.SpanFromContext(ctx)
	if data.Err != nil {
		span.RecordError(data.Err)
	}
	span.SetAttributes(attribute.Int64("db.rows_affected", data.CommandTag.RowsAffected()))
	span.End()
}
