# FlowQL Language Reference

## Pipeline Structure

A FlowQL program is a linear pipeline:

```
source <source-spec>
| <stage>
| <stage>
| ...
| sink <sink-spec>
```

Stages are separated by `|` (pipe). A pipeline must begin with `source` and end with `sink`.

## Comments

Lines starting with `#` are comments:

```
# This is a comment
source stdin  # inline comment
| sink stdout
```

## Sources

### `source file("path")`
Read lines from a file. Each line becomes an event with a `_line` field.

### `source stdin`
Read lines from standard input.

### `source lines("path")`
Alias for `source file("path")`.

## Parse Stages

### `parse_json`
Parse the `_line` field of each event as a JSON object. The resulting event has one field per JSON key.

Input: `{"status": 200, "path": "/api"}` → Event with fields `status=200`, `path="/api"`

Supports: strings, integers, reals, booleans, null. Nested objects are not expanded.

### `parse_csv` / `parse_csv header` / `parse_csv noheader`
Parse the `_line` field as CSV (comma-separated values).

- `parse_csv` or `parse_csv header` — first line is treated as a header row defining field names
- `parse_csv noheader` — no header row; fields are named `c0`, `c1`, `c2`, etc.

Values are auto-detected as integer, real, boolean, or string.

### `parse_tsv` / `parse_tsv header` / `parse_tsv noheader`
Parse the `_line` field as TSV (tab-separated values). Same header modes as `parse_csv`.

- `parse_tsv` or `parse_tsv header` — first line is the header row
- `parse_tsv noheader` — fields named `c0`, `c1`, `c2`, etc.

### `parse_kv`
Parse the `_line` field as whitespace-separated `key=value` pairs. Supports quoted values (`key="value with spaces"`). Values are auto-detected as integer, real, boolean, or string.

Input: `level=error host=web01 latency=42` → Event with fields `level="error"`, `host="web01"`, `latency=42`

### `lines`
Rename the raw `_line` field to `line`. This is a simple transform (not a parse stage) that can coexist with parse stages. Useful for text processing pipelines that want to filter or count raw lines.

```
source file("errors.log")
| lines
| filter line != ""
| count
| sink stdout
```

## Transform Stages

### `filter <expr>`
Keep only events where the expression evaluates to true.

```
filter status >= 500
filter status >= 500 and latency_ms > 100
filter not (status = 200)
```

### `map { fields... }`
Create a new event with the specified fields. Fields can be bare (pass-through) or computed.

```
map { path, status }                          # pass-through
map { path, slow = latency_ms > 1000 }        # computed field
map { path, latency_s = latency_ms / 1000 }   # arithmetic
```

### `project { fields... }`
Select specific fields from the event. Like `map` but without computed fields.

```
project { name, email, age }
```

## Aggregation Stages

### `count`
Count all events. Emits a single event with a `count` field when the stream ends.

### `count by <field>`
Count events grouped by the value of a field. Emits a single event where each field name is a group key and the value is the count.

```
count by path
# Input: [{path:"/a"}, {path:"/b"}, {path:"/a"}]
# Output: {"/a": 2, "/b": 1}
```

### `batch <n>`
Collect events into groups of `n`. Each batch is passed through as a group. Maximum batch size: 64.

## Sinks

### `sink stdout`
Write each event as a JSON line to standard output.

### `sink file("path")`
Write each event as a JSON line to a file.

## Expression Language

### Literals
| Type | Examples |
|------|----------|
| Integer | `42`, `0`, `-1` |
| Real | `3.14`, `0.5` |
| String | `"hello"`, `"error"` |
| Boolean | `true`, `false` |
| Null | `null` |

### Field References
Bare identifiers refer to event fields: `status`, `latency_ms`, `path`

If a field doesn't exist, it evaluates to `null`.

### Operators

**Comparison** (produce boolean):
`=`, `!=`, `>`, `>=`, `<`, `<=`

**Arithmetic** (produce int or real):
`+`, `-`, `*`, `/`

String `+` performs concatenation.

**Logic** (produce boolean):
`and`, `or`, `not`

Short-circuit evaluation: `and` stops on first false, `or` stops on first true.

### Precedence (low to high)
1. `or`
2. `and`
3. `=`, `!=`, `>`, `>=`, `<`, `<=`
4. `+`, `-`
5. `*`, `/`
6. `not`, unary `-`
7. parentheses

### Truthiness
- `null` → false
- `false` → false
- `0` / `0.0` → false
- `""` (empty string) → false
- Everything else → true
