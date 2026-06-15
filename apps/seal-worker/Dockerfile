FROM golang:1.26-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./

RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .

ARG APP_NAME=worker

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 \
    go build \
      -trimpath \
      -ldflags="-s -w" \
      -o /app \
      ./cmd/${APP_NAME}

FROM cgr.dev/chainguard/static:latest

COPY --from=builder /app /app

ENTRYPOINT ["/app"]
