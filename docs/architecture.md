# FlowQL Architecture

## Overview

FlowQL is a compiler pipeline:

```
Source Text → Lexer → Parser → AST → Sema → Plan → Lower → FlowNet → Execute
```

## Modules

### Token (Token.def/.mod)
Defines token kinds (keywords, operators, literals, identifiers) and helper functions. 42 token kinds total.

### Lexer (Lexer.def/.mod)
Hand-written scanner that produces tokens from source text. Tracks line/column for error reporting. Supports `#` line comments. Provides `Next()` and `Peek()`.

### Ast (Ast.def/.mod)
AST node types for pipelines:
- `Pipeline` = Source + Stage[] + Sink
- `Stage` variants: Filter, Map, Project, ParseJson, ParseCsv, ParseTsv, ParseKv, Lines, Count, CountBy, Batch, Window
- `HeaderMode`: Default, Header, Noheader — controls CSV/TSV header behavior
- `Expr` tree: BinOp, UnaryOp, FieldRef, literals
- Heap-allocated expression nodes via `NewExpr()`/`FreeExpr()`

### Parser (Parser.def/.mod)
Recursive-descent parser producing an AST Pipeline. Expression parsing uses precedence climbing with levels: or → and → comparison → addition → multiplication → primary.

### Sema (Sema.def/.mod)
Semantic validation:
- Source/sink presence
- No duplicate parse stages
- Parse stages cannot follow aggregation
- Batch/window size limits (FlowNet max 64)
- Filter requires expression, map/project require fields

### Value (Value.def/.mod)
Runtime value type with 5 variants: Int, Real, Bool, Str, Null. Supports comparison, truthiness, and string formatting.

### Event (Event.def/.mod)
Runtime event — a dictionary of up to 32 named fields, each holding a Value. Supports field get/set, existence check, and JSON formatting.

### ExprEval (ExprEval.def/.mod)
Tree-walk expression evaluator. Evaluates AST expressions against an Event to produce a Value. Supports arithmetic, comparison, boolean logic with short-circuit evaluation, and field references.

### Plan (Plan.def/.mod)
Prints the execution plan in two modes:
- **Default** (`PrintPlan`): pipeline graph with logical stage names and `[stage N]` annotations, channel topology with capacity and endpoint names, FlowNet mapping with kind tags (standard/expr-eval/aggregate), and a one-line summary (threads, channels, lowering strategy).
- **Verbose** (`PrintPlanVerbose`, via `plan -v`): adds per-node detail — context types (SourceCtx, MapCtx, FilterCtx, etc.), userData record types, callback procedure names, source/sink config values, channel type tags (`ADDRESS -> Event*`), and origin annotations distinguishing builtin FlowNet nodes from FlowQL runtime wrappers.

Includes an expression printer that renders filter predicates and map computed fields in human-readable form (e.g. `Filter(status >= 500 and latency_ms > 100)`, `Map{path, slow = latency_ms > 1000}`). Map/project stages with more than 3 fields are formatted multi-line for readability.

### Lower (Lower.def/.mod)
Compiles a validated AST pipeline into FlowNet Pipe.Stage() calls. Each FlowQL stage becomes a FlowNet node with appropriate context and callback. Manages node lifecycle (open/close sources and sinks).

### Runtime (Runtime.def/.mod)
FlowQL-specific FlowNet callbacks:
- `SourceGen` — reads lines from file/stdin
- `ParseJsonTransform` — parses JSON lines into Events
- `ParseCsvTransform` — parses CSV lines with header detection
- `ParseTsvTransform` — parses TSV lines with header detection
- `ParseKvTransform` — parses key=value log lines
- `LinesTransform` — renames `_line` to `line`
- `FilterPred` — evaluates filter expression
- `MapTransform` — evaluates map/project field expressions
- `CountReduce` / `CountByReduce` — counting aggregation
- `SinkConsume` — formats and outputs Events as JSON

## Lowering Strategy

All pipelines are linear → compiled via `Pipe.Stage()`:

| FlowQL Stage | FlowNet Node | Callback |
|--------------|-------------|----------|
| source | SourceRun | GenProc (SourceGen) |
| parse_json | MapRun | TransformProc (ParseJsonTransform) |
| parse_csv | MapRun | TransformProc (ParseCsvTransform) |
| parse_tsv | MapRun | TransformProc (ParseTsvTransform) |
| parse_kv | MapRun | TransformProc (ParseKvTransform) |
| lines | MapRun | TransformProc (LinesTransform) |
| filter | FilterRun | PredicateProc (FilterPred) |
| map/project | MapRun | TransformProc (MapTransform) |
| count | ReduceRun | ReduceProc (CountReduce) |
| count by | ReduceRun | ReduceProc (CountByReduce) |
| batch | BatchRun | BatchProc (BatchPassthrough) |
| sink | SinkRun | ConsumeProc (SinkConsume) |

## Data Flow

1. Source reads lines, wraps each in an Event with `_line` field
2. Parse stages transform `_line` into structured fields
3. Filter/map/project operate on structured Events
4. Aggregation reduces the stream
5. Sink formats Events as JSON lines

All Events flow as heap-allocated `ADDRESS` pointers through FlowNet's bounded FIFO channels.

## Threading Model

Each pipeline stage runs in its own OS thread (FlowNet model). Backpressure is automatic via bounded channels. Graceful shutdown cascades when the source exhausts.

## Limitations

- No static type system — all types checked at runtime
- Expression evaluation is interpreted (tree-walk), not compiled
- No optimizer — direct AST-to-FlowNet lowering
- Linear pipelines only — no fan-out, fan-in, or joins
- JSON parser is a simplified line-oriented parser (not full RFC 8259)
