# FlowQL

**Streaming Pipeline DSL for Modula-2+, built on FlowNet**

FlowQL is a compact declarative language for describing streaming data pipelines. It compiles to [FlowNet](../flownet/) pipelines, leveraging FlowNet's bounded channels, threaded processes, and reusable nodes.

## Example

```
source file("access.jsonl")
| parse_json
| filter status >= 500
| map { path, status, latency_ms }
| count by path
| sink stdout
```

## What FlowQL Is

- A pipeline DSL — not a general-purpose language
- A front-end compiler over FlowNet
- A practical way to describe streaming transforms over records/events
- Intentionally small and explicit

## v1 Features

### Sources
- `source file("path")` — read lines from a file
- `source stdin` — read lines from stdin
- `source lines("path")` — alias for file

### Parse Stages
- `parse_json` — parse each line as a JSON object
- `parse_csv` / `parse_csv header` / `parse_csv noheader` — parse CSV with configurable header mode
- `parse_tsv` / `parse_tsv header` / `parse_tsv noheader` — parse TSV (tab-separated)
- `parse_kv` — parse key=value log lines
- `lines` — rename `_line` to `line` for raw text processing

### Transforms
- `filter <expr>` — keep events matching a boolean expression
- `map { field1, field2, computed = expr }` — select and compute fields
- `project { field1, field2 }` — select fields (no computed)

### Aggregation
- `count` — count total events
- `count by <field>` — count grouped by a field value
- `batch <n>` — group events into batches of n

### Sinks
- `sink stdout` — write JSON lines to stdout
- `sink file("path")` — write JSON lines to a file

### Expressions
- Field references: `status`, `latency_ms`
- Literals: integers, reals, strings, booleans, null
- Comparison: `=`, `!=`, `>`, `>=`, `<`, `<=`
- Arithmetic: `+`, `-`, `*`, `/`
- Logic: `and`, `or`, `not`
- Parentheses: `(expr)`

## CLI

```
flowql check <file.fq>      # Parse and validate
flowql plan  <file.fq>      # Show execution plan
flowql plan -v <file.fq>    # Verbose plan (context types, callbacks, origins)
flowql run   <file.fq>      # Execute the pipeline
```

## Building

Requires [mx](https://github.com/fitzee/mx) and [FlowNet](https://github.com/fitzee/flownet).

```
mx build
mx test
```

## Limitations (v1)

- Linear pipelines only (no fan-out/fan-in)
- Dynamic typing only (no static type inference)
- No joins, subqueries, or user-defined functions
- No plugins or extensibility mechanism
- JSON/CSV/TSV/KV input only
- JSON output only
- Max 32 fields per event, max 30 pipeline stages
- Batch/window size max 64 items
- No time-based windows
- No distributed execution
- FlowNet runtime limits apply (32 nodes, 32 channels per pipeline)

## Documentation

- [Language Reference](docs/language.md)
- [Architecture](docs/architecture.md)
- [Usage Guide](docs/usage.md)

---

Copyright (c) 2026 Matt Fitzgerald. Licensed under the [MIT License](LICENSE).
