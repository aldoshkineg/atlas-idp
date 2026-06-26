# Distributed Tracing with OpenTelemetry

## What Is Distributed Tracing?

Distributed tracing is a technique to track a single request as it travels across multiple services in a distributed system. It answers questions like:

- Why is this request slow? Which service caused the delay?
- Where exactly did the error occur?
- What is the full path of a request through the system?

## Core Concepts

### Trace

A **trace** represents the entire journey of a single request — from the moment it enters the system (e.g., HTTP request) until the response is returned. Each trace has a globally unique **trace ID**.

### Span

A **span** is a single unit of work within a trace. Each span has:

| Field                      | Description                                                         |
| -------------------------- | ------------------------------------------------------------------- |
| **Name**                   | e.g., `HTTP POST`, `SQL SELECT`, `ProcessJob`                       |
| **Trace ID**               | Links this span to its parent trace                                 |
| **Span ID**                | Unique identifier of this span                                      |
| **Parent Span ID**         | Links this span to its caller                                       |
| **Start / End timestamps** | Duration = end - start                                              |
| **Attributes**             | Key-value metadata (`http.method`, `db.statement`, `error.message`) |
| **Status**                 | `OK`, `ERROR`, or `UNSET`                                           |
| **Events**                 | Timestamped log messages within a span                              |

Multiple spans form a **waterfall diagram**:

```
Trace: a1b2c3d4
├── HTTP POST /documents               (seal-ui)     150ms
│   ├── HTTP POST /api/documents       (seal-api)    120ms
│   │   ├── SQL INSERT                 (seal-api)     10ms
│   │   ├── REDIS RPUSH                (seal-api)      5ms
│   │   └── PopResult (wait + read)    (seal-api)     80ms
│   │       └── REDIS BLMOVE           (seal-api)     70ms
│   ├── ProcessJob                     (seal-worker)  60ms
│   │   ├── Sign                       (seal-worker)  30ms
│   │   ├── Upload                     (seal-worker)  15ms
│   │   └── REDIS RPUSH                (seal-worker)   5ms
```

### Context Propagation

For spans to connect into a trace, the **trace ID** and **parent span ID** must travel with the request across service boundaries.

#### Synchronous (HTTP)

The W3C `traceparent` header is used:

```
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
              │  └────── trace ID ──────┘ └── span ID ──┘ │
              └ version                                    └ sampling flag
```

When Service A calls Service B via HTTP, it injects this header. Service B extracts it and creates a child span.

#### Asynchronous (Message Queues)

For Redis, RabbitMQ, Kafka, etc., there is no standard header mechanism. The `traceparent` must be **manually serialized into the message payload**:

```
Producer                         Consumer
  │                                │
  ├─ Inject traceparent ── JSON ──▶ ── Extract traceparent
  │   into message                  │   from message
  │   {                             │   { traceparent: "..." }
  │     traceparent: "00-..."       │   → create child span
  │   }                             │
```

## OpenTelemetry SDK

### Tracer Provider

The Tracer Provider is the central object that manages spans. It is configured once at application startup:

```
TracerProvider
├── Exporter       ── sends spans to a backend (OTLP, Jaeger, Zipkin)
├── BatchProcessor ── buffers and batches spans before export
└── Resource       ── metadata about the service (service.name, version, env)
```

### Instrumentation

Instrumentation can be:

- **Automatic**: HTTP middleware (`otelhttp.NewHandler`), gRPC interceptors, database drivers
- **Manual**: explicit `tracer.Start(ctx, "spanName")` calls for custom operations

### Exporters

Spans are sent to a backend via **exporters**:

| Exporter  | Protocol      | Backend                      |
| --------- | ------------- | ---------------------------- |
| OTLP/gRPC | gRPC          | Tempo, Jaeger, Grafana Cloud |
| OTLP/HTTP | HTTP/Protobuf | Tempo, Alloy, Collector      |
| Jaeger    | Thrift        | Jaeger                       |

### Sampling

Not all requests need tracing. Sampling strategies:

- **Always sample** (for dev/test)
- **Probabilistic**: trace 1% of requests
- **Parent-based**: inherit sampling decision from parent span
- **Head-based**: decide at the entry point

## Architecture Patterns

### Direct Export (Simpler)

```
Service ──OTLP──▶ Tempo (storage + query)
                  ▲
                  │ TempoQL
              Grafana
```

### Collector / Alloy (Production)

```
Service ──OTLP──▶ Alloy ──OTLP──▶ Tempo
                            (batch, filter,
                             retry, multi-tenant)
```

The collector handles:

- **Batching**: reduces network overhead
- **Retries**: resilient to backend outages
- **Filtering**: drop noisy spans (e.g., health checks)
- **Multi-tenancy**: route spans by service or namespace
- **Load shedding**: drop when backend is overloaded

## Storage Backends

| Backend           | Storage                          | Strengths                           |
| ----------------- | -------------------------------- | ----------------------------------- |
| **Grafana Tempo** | Local disk, S3, GCS, Azure       | Native Grafana integration, TraceQL |
| **Jaeger**        | Cassandra, Elasticsearch, Badger | Mature, UI + search                 |
| **Zipkin**        | Cassandra, Elasticsearch         | Legacy, simple                      |
| **Grafana Cloud** | Managed SaaS                     | No ops, retention configurable      |

## Metrics vs Traces vs Logs

| Signal      | What it answers               | Example                                |
| ----------- | ----------------------------- | -------------------------------------- |
| **Metrics** | How many? How fast?           | `http_requests_total`, `p99_latency`   |
| **Traces**  | Why is this request slow?     | Full waterfall of one specific request |
| **Logs**    | What happened at this moment? | `"user 42 created document abc"`       |

The three are often **correlated**: logs carry a `trace_id` field, metrics are aggregated from trace data, and traces link to relevant log entries.

## Common Issues

| Problem                                | Cause                    | Fix                                        |
| -------------------------------------- | ------------------------ | ------------------------------------------ |
| Missing spans                          | No exporter configured   | Set `OTEL_EXPORTER_OTLP_ENDPOINT`          |
| Broken trace (2+ traces for 1 request) | Propagation not set up   | Check `traceparent` header/message passing |
| Missing child spans                    | No parent context passed | Ensure `ctx` with span is threaded through |
| Spans but no trace in backend          | Network, backend down    | Check exporter logs, backend health        |
| Too many traces in production          | Always-sample            | Configure probabilistic sampling           |

## Key Takeaways

1. A **trace** is one request's journey; a **span** is one step in that journey
2. **Trace ID** is propagated across services via `traceparent` header (HTTP) or in message payload (queues)
3. **OTLP** is the standard protocol for exporting spans
4. A **collector** (Alloy, OpenTelemetry Collector) is recommended between services and backend for batching/resilience
5. Traces complement metrics (what) and logs (details) — together they form the observability triad
