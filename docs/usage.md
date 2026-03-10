# FlowQL Usage Guide

## Installation

Build FlowQL from source:

```
cd flowql
m2c build
```

The binary is produced at `build/flowql` (or as configured by m2c).

Run tests:
```
m2c test
```

## Commands

### `flowql check <file.fq>`

Parse and validate a FlowQL program. Reports any lexical, parse, or semantic errors with line/column information.

```
$ flowql check examples/errors_by_path.fq
ok

$ flowql check bad_program.fq
parse error at line 3, col 5: expected expression
```

### `flowql plan <file.fq>`

Show the execution plan: pipeline graph, channel topology, and FlowNet lowering.

```
$ flowql plan examples/errors_by_path.fq
=== FlowQL Execution Plan ===

Pipeline:

  Source(file, "access.jsonl")
    -> ParseJSON  [stage 1]
    -> Filter(status >= 500)  [stage 2]
    -> CountBy(path)  [stage 3]
    -> Sink(stdout)

Channels:
  ch1  cap=8  Source(file) -> ParseJSON
  ch2  cap=8  ParseJSON -> Filter
  ch3  cap=8  Filter -> CountBy
  ch4  cap=8  CountBy -> Sink(stdout)

FlowNet mapping:
  Source(file) -> SourceRun  [standard, generator]
  ParseJSON -> MapRun  [standard, parser]
  Filter -> FilterRun  [expr-eval, predicate]
  CountBy -> ReduceRun  [aggregate, hash-group]
  Sink(stdout) -> SinkRun  [standard, consumer]

Threads: 5  Channels: 4  Lowering: Pipe.Stage()
```

The plan shows:
- **Pipeline graph** with logical stage names and `[stage N]` annotations for cross-referencing with runtime errors
- **Channels** connecting each pair of stages with their buffer capacity
- **FlowNet mapping** showing which FlowNet node type runs each stage, with kind tags distinguishing standard builtins, expression-evaluating wrappers, and aggregate stages

### `flowql plan -v <file.fq>`

Verbose plan adds per-node detail: context types, userData records, callback procedure names, builtin vs FlowQL-custom origin, and channel type tags.

```
$ flowql plan -v examples/errors_by_path.fq
=== FlowQL Execution Plan (verbose) ===

Pipeline:
  ...

Channels:
  ch1  cap=8  Source(file) -> ParseJSON  [ADDRESS -> Event*]
  ...

Nodes:

  Source(file) -> SourceRun  [standard, generator]
    context:  SourceCtx
    userData: FileSourceData
    callback: SourceGen
    record:   path="access.jsonl", isStdin=false
    origin:   builtin (FlowNet SourceRun)

  Filter  [stage 2] -> FilterRun  [expr-eval, predicate]
    context:  FilterCtx
    userData: FilterData {expr}
    callback: FilterPred
    origin:   FlowQL runtime (expr-eval wrapper)
  ...
```

### `flowql run <file.fq>`

Execute a FlowQL pipeline. Reads input, processes through all stages, and writes output.

```
$ flowql run examples/slow_requests.fq
{"path":"/api/search","status":500,"latency_ms":2341}
{"path":"/api/upload","status":503,"latency_ms":5120}
```

## Workflows

### Develop and Test

1. Write a `.fq` file
2. `flowql check myquery.fq` — verify syntax and semantics
3. `flowql plan myquery.fq` — review the execution plan
4. `flowql run myquery.fq` — execute

### Pipe from stdin

```
cat access.log | flowql run examples/stdin_json.fq
curl -s api/logs | flowql run examples/stdin_json.fq
```

### Write to file

```
source file("input.jsonl")
| parse_json
| filter level = "error"
| sink file("errors.jsonl")
```

## Data Format

### Input
- **JSON**: One JSON object per line (JSONL format)
- **CSV**: Comma-separated values; `parse_csv` or `parse_csv header` uses first line as headers, `parse_csv noheader` generates `c0`, `c1`, `c2` field names
- **TSV**: Tab-separated values; same header modes as CSV
- **Key=Value**: Whitespace-separated `key=value` pairs (supports quoted values)
- **Raw lines**: Use `lines` stage to access raw text as `line` field

### Output
- Events are formatted as JSON objects, one per line

## Error Messages

FlowQL provides source-location-aware errors:

- **Lexical errors**: Invalid characters, unterminated strings
- **Parse errors**: Missing keywords, malformed expressions
- **Semantic errors**: Missing source/sink, invalid stage order, limit violations
- **Runtime errors**: File not found, evaluation errors

## Examples

See the `examples/` directory for complete runnable programs:

| File | Description |
|------|-------------|
| `errors_by_path.fq` | Count HTTP 500 errors by path |
| `slow_requests.fq` | Find requests over 1s latency |
| `csv_filter.fq` | Filter CSV data |
| `batch_example.fq` | Batch processing |
| `simple_project.fq` | Field selection |
| `stdin_json.fq` | Stdin JSON filtering |
| `count_all.fq` | Count total events |
| `computed_fields.fq` | Computed/derived fields |
| `log_triage.fq` | Filter high-severity log entries |
| `csv_sales_filter.fq` | Filter CSV sales over threshold |
| `security_scan.fq` | Extract critical/high security findings |
| `ci_failures.fq` | Count CI test failures by suite |
| `slow_endpoints.fq` | Find and count slow API endpoints |
| `sensor_agg.fq` | Aggregate sensor readings by ID |
| `nginx_errors.fq` | Triage nginx 5xx errors |
| `api_latency_report.fq` | Latency report with computed fields |
| `user_activity.fq` | Filter user login/signup activity |
| `pipeline_metrics.fq` | CI/CD pipeline metrics with batching |
| `csv_header_filter.fq` | CSV with explicit header mode |
| `csv_noheader_filter.fq` | CSV without headers (c0/c1/c2 fields) |
| `tsv_status_filter.fq` | TSV status code filtering |
| `lines_errors.fq` | Raw line counting |
| `kv_latency_filter.fq` | Key=value log filtering |
