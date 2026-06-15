CREATE TABLE IF NOT EXISTS documents (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    status     VARCHAR(20) NOT NULL DEFAULT 'pending',
    input_text TEXT        NOT NULL,
    s3_path    VARCHAR(512),
    file_size  BIGINT      NOT NULL DEFAULT 0,
    error      TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status);
CREATE INDEX IF NOT EXISTS idx_documents_created_at ON documents(created_at);
