MODULE Main;
(* FlowQL test suite *)

FROM InOut IMPORT WriteString, WriteLn, WriteInt;
FROM Strings IMPORT Assign, CompareStr, Length;
FROM Token IMPORT Kind, Token, KindName, IsKeyword,
     TkSource, TkSink, TkFilter, TkMap, TkPipe, TkInt, TkString,
     TkIdent, TkEOF, TkGe, TkNeq, TkAnd, TkOr, TkTrue, TkFalse,
     TkLBrace, TkRBrace, TkComma, TkEq, TkReal, TkParseJson,
     TkParseCsv, TkParseTsv, TkParseKv, TkHeader, TkNoheader,
     TkLParen, TkRParen, TkGt, TkLt, TkLe, TkNull,
     TkCount, TkBy, TkBatch, TkStdin, TkStdout, TkProject,
     TkLines;
FROM Lexer IMPORT State, Init, Next, Peek;
FROM Parser IMPORT Parse, ParseResult;
FROM Sema IMPORT Validate, SemaResult;
FROM Ast IMPORT Pipeline, ExprKind, StageKind, SourceKind,
     EkFieldRef, EkBinOp, EkIntLit,
     StFilter, StMap, StProject, StParseJson, StParseCsv,
     StParseTsv, StParseKv, StLines,
     StCount, StCountBy, StBatch,
     SkNamed,
     HeaderMode, HmDefault, HmHeader, HmNoheader;
FROM Value IMPORT Value, ValueKind, VkInt, VkReal, VkBool, VkStr, VkNull,
     MakeInt, MakeReal, MakeBool, MakeStr, MakeNull,
     Compare, IsTruthy, Format;
FROM Event IMPORT Event, InitEvent, SetField, GetField, HasField,
     FormatJson;
FROM ExprEval IMPORT Eval, EvalBool;
FROM Plan IMPORT PrintPlan;

VAR
  passed, failed, total: CARDINAL;

PROCEDURE Assert(cond: BOOLEAN; msg: ARRAY OF CHAR);
BEGIN
  INC(total);
  IF cond THEN
    INC(passed)
  ELSE
    INC(failed);
    WriteString("  FAIL: ");
    WriteString(msg);
    WriteLn
  END
END Assert;

PROCEDURE Section(name: ARRAY OF CHAR);
BEGIN
  WriteLn;
  WriteString("--- ");
  WriteString(name);
  WriteString(" ---");
  WriteLn
END Section;

(* ══════════════════════════════════════════════════ *)
(* Lexer Tests                                        *)
(* ══════════════════════════════════════════════════ *)

PROCEDURE TestLexerKeywords;
VAR s: State; t: Token; ok: BOOLEAN;
    src: ARRAY [0..255] OF CHAR;
BEGIN
  Section("Lexer: Keywords");
  Assign("source sink filter map project parse_json parse_csv count by batch", src);
  Init(s, src, Length(src));

  ok := Next(s, t); Assert(t.kind = TkSource, "source keyword");
  ok := Next(s, t); Assert(t.kind = TkSink, "sink keyword");
  ok := Next(s, t); Assert(t.kind = TkFilter, "filter keyword");
  ok := Next(s, t); Assert(t.kind = TkMap, "map keyword");
  ok := Next(s, t); Assert(t.kind = TkProject, "project keyword");
  ok := Next(s, t); Assert(t.kind = TkParseJson, "parse_json keyword");
  ok := Next(s, t); Assert(t.kind = TkParseCsv, "parse_csv keyword");
  ok := Next(s, t); Assert(t.kind = TkCount, "count keyword");
  ok := Next(s, t); Assert(t.kind = TkBy, "by keyword")
END TestLexerKeywords;

PROCEDURE TestLexerOperators;
VAR s: State; t: Token; ok: BOOLEAN;
    src: ARRAY [0..255] OF CHAR;
BEGIN
  Section("Lexer: Operators");
  Assign("| { } ( ) , = != > >= < <=", src);
  Init(s, src, Length(src));

  ok := Next(s, t); Assert(t.kind = TkPipe, "pipe");
  ok := Next(s, t); Assert(t.kind = TkLBrace, "lbrace");
  ok := Next(s, t); Assert(t.kind = TkRBrace, "rbrace");
  ok := Next(s, t); Assert(t.kind = TkLParen, "lparen");
  ok := Next(s, t); Assert(t.kind = TkRParen, "rparen");
  ok := Next(s, t); Assert(t.kind = TkComma, "comma");
  ok := Next(s, t); Assert(t.kind = TkEq, "eq");
  ok := Next(s, t); Assert(t.kind = TkNeq, "neq");
  ok := Next(s, t); Assert(t.kind = TkGt, "gt");
  ok := Next(s, t); Assert(t.kind = TkGe, "ge");
  ok := Next(s, t); Assert(t.kind = TkLt, "lt");
  ok := Next(s, t); Assert(t.kind = TkLe, "le")
END TestLexerOperators;

PROCEDURE TestLexerLiterals;
VAR s: State; t: Token; ok: BOOLEAN;
    src: ARRAY [0..255] OF CHAR;
BEGIN
  Section("Lexer: Literals");
  Assign('42 3.14 "hello" true false null myField', src);
  Init(s, src, Length(src));

  ok := Next(s, t);
  Assert(t.kind = TkInt, "int literal");
  Assert(CompareStr(t.lexeme, "42") = 0, "int value");

  ok := Next(s, t);
  Assert(t.kind = TkReal, "real literal");
  Assert(CompareStr(t.lexeme, "3.14") = 0, "real value");

  ok := Next(s, t);
  Assert(t.kind = TkString, "string literal");
  Assert(CompareStr(t.lexeme, "hello") = 0, "string value");

  ok := Next(s, t); Assert(t.kind = TkTrue, "true literal");
  ok := Next(s, t); Assert(t.kind = TkFalse, "false literal");
  ok := Next(s, t); Assert(t.kind = TkNull, "null literal");
  ok := Next(s, t); Assert(t.kind = TkIdent, "identifier")
END TestLexerLiterals;

PROCEDURE TestLexerLineCol;
VAR s: State; t: Token; ok: BOOLEAN;
    src: ARRAY [0..255] OF CHAR;
BEGIN
  Section("Lexer: Line/Col tracking");
  src[0] := 'a';
  src[1] := CHR(10);
  src[2] := 'b';
  src[3] := CHR(0);
  Init(s, src, 3);

  ok := Next(s, t);
  Assert(t.line = 1, "first token line 1");
  Assert(t.col = 1, "first token col 1");

  ok := Next(s, t);
  Assert(t.line = 2, "second token line 2");
  Assert(t.col = 1, "second token col 1")
END TestLexerLineCol;

PROCEDURE TestLexerComments;
VAR s: State; t: Token; ok: BOOLEAN;
    src: ARRAY [0..255] OF CHAR;
BEGIN
  Section("Lexer: Comments");
  Assign("source # this is a comment", src);
  Init(s, src, Length(src));
  ok := Next(s, t);
  Assert(t.kind = TkSource, "token before comment");
  ok := Next(s, t);
  Assert(t.kind = TkEOF, "EOF after comment")
END TestLexerComments;

PROCEDURE TestLexerPeek;
VAR s: State; t1, t2: Token; ok: BOOLEAN;
    src: ARRAY [0..255] OF CHAR;
BEGIN
  Section("Lexer: Peek");
  Assign("source stdin", src);
  Init(s, src, Length(src));
  ok := Peek(s, t1);
  Assert(t1.kind = TkSource, "peek returns source");
  ok := Next(s, t2);
  Assert(t2.kind = TkSource, "next also returns source");
  ok := Next(s, t2);
  Assert(t2.kind = TkStdin, "next returns stdin")
END TestLexerPeek;

(* ══════════════════════════════════════════════════ *)
(* Parser Tests                                       *)
(* ══════════════════════════════════════════════════ *)

PROCEDURE TestParserSimplePipeline;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: Simple pipeline");
  Assign("source stdin | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "simple pipeline parses");
  Assert(r.pipeline.hasSource, "has source");
  Assert(r.pipeline.hasSink, "has sink");
  Assert(r.pipeline.numStages = 0, "no middle stages")
END TestParserSimplePipeline;

PROCEDURE TestParserMultiStage;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: Multi-stage pipeline");
  Assign('source file("data.jsonl") | parse_json | filter status >= 500 | map { path, status } | sink stdout', src);
  Parse(src, Length(src), r);
  Assert(r.ok, "multi-stage parses");
  Assert(r.pipeline.numStages = 3, "3 middle stages");
  Assert(r.pipeline.stages[0].kind = StParseJson, "stage 0 is parse_json");
  Assert(r.pipeline.stages[1].kind = StFilter, "stage 1 is filter");
  Assert(r.pipeline.stages[2].kind = StMap, "stage 2 is map")
END TestParserMultiStage;

PROCEDURE TestParserFilter;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: Filter expression");
  Assign("source stdin | filter status >= 500 and latency > 100 | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "filter with and parses");
  Assert(r.pipeline.stages[0].kind = StFilter, "is filter");
  Assert(r.pipeline.stages[0].filterExpr # NIL, "has filter expr")
END TestParserFilter;

PROCEDURE TestParserMapComputed;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: Map with computed fields");
  Assign("source stdin | map { path, slow = latency_ms > 1000 } | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "map with computed field parses");
  Assert(r.pipeline.stages[0].kind = StMap, "is map");
  Assert(r.pipeline.stages[0].numFields = 2, "2 fields");
  Assert(NOT r.pipeline.stages[0].fields[0].hasExpr, "field 0 is bare");
  Assert(r.pipeline.stages[0].fields[1].hasExpr, "field 1 is computed")
END TestParserMapComputed;

PROCEDURE TestParserCountBy;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: Count by");
  Assign("source stdin | count by path | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "count by parses");
  Assert(r.pipeline.stages[0].kind = StCountBy, "is count_by");
  Assert(CompareStr(r.pipeline.stages[0].groupField, "path") = 0, "group field is path")
END TestParserCountBy;

PROCEDURE TestParserBatch;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: Batch");
  Assign("source stdin | batch 10 | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "batch parses");
  Assert(r.pipeline.stages[0].kind = StBatch, "is batch");
  Assert(r.pipeline.stages[0].size = 10, "batch size 10")
END TestParserBatch;

PROCEDURE TestParserFileSource;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: File source");
  Assign('source file("data.jsonl") | sink stdout', src);
  Parse(src, Length(src), r);
  Assert(r.ok, "file source parses");
  Assert(CompareStr(r.pipeline.source.path, "data.jsonl") = 0, "path matches")
END TestParserFileSource;

PROCEDURE TestParserErrors;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: Error cases");

  (* No source *)
  Assign("filter status > 500 | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(NOT r.ok, "no source fails");

  (* No sink — now valid for embedded use *)
  Assign("source stdin | filter status > 500", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "sinkless pipeline ok");
  Assert(NOT r.pipeline.hasSink, "hasSink false");

  (* Bad stage *)
  Assign("source stdin | foobar | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(NOT r.ok, "unknown stage fails")
END TestParserErrors;

PROCEDURE TestNamedSource;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
    sr:  SemaResult;
BEGIN
  Section("Parser: Named source");
  Assign('source spans | filter status = "error" | count', src);
  Parse(src, Length(src), r);
  Assert(r.ok, "named source parses");
  Assert(r.pipeline.source.kind = SkNamed, "kind is SkNamed");
  Assert(NOT r.pipeline.hasSink, "no sink ok");
  Assert(r.pipeline.numStages = 2, "2 stages");
  Validate(r.pipeline, sr);
  Assert(sr.ok, "sema ok for named sinkless")
END TestNamedSource;

(* ══════════════════════════════════════════════════ *)
(* Semantic Analysis Tests                            *)
(* ══════════════════════════════════════════════════ *)

PROCEDURE TestSemaValid;
VAR src: ARRAY [0..511] OF CHAR;
    pr:  ParseResult;
    sr:  SemaResult;
BEGIN
  Section("Sema: Valid pipelines");
  Assign('source file("x.jsonl") | parse_json | filter status >= 500 | map { path } | sink stdout', src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse ok");
  Validate(pr.pipeline, sr);
  Assert(sr.ok, "sema ok for valid pipeline")
END TestSemaValid;

PROCEDURE TestSemaDuplicateParse;
VAR src: ARRAY [0..511] OF CHAR;
    pr:  ParseResult;
    sr:  SemaResult;
BEGIN
  Section("Sema: Duplicate parse");
  Assign("source stdin | parse_json | parse_json | sink stdout", src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse ok");
  Validate(pr.pipeline, sr);
  Assert(NOT sr.ok, "duplicate parse rejected")
END TestSemaDuplicateParse;

PROCEDURE TestSemaBatchLimit;
VAR src: ARRAY [0..511] OF CHAR;
    pr:  ParseResult;
    sr:  SemaResult;
BEGIN
  Section("Sema: Batch limit");
  Assign("source stdin | batch 100 | sink stdout", src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse ok");
  Validate(pr.pipeline, sr);
  Assert(NOT sr.ok, "batch > 64 rejected")
END TestSemaBatchLimit;

(* ══════════════════════════════════════════════════ *)
(* Value Tests                                        *)
(* ══════════════════════════════════════════════════ *)

PROCEDURE TestValues;
VAR a, b: Value;
    buf:  ARRAY [0..255] OF CHAR;
BEGIN
  Section("Value: Basic operations");

  MakeInt(42, a);
  Assert(a.kind = VkInt, "int kind");
  Assert(a.intVal = 42, "int value");

  MakeReal(3.14, b);
  Assert(b.kind = VkReal, "real kind");

  Assert(Compare(a, b) > 0, "42 > 3.14");

  MakeBool(TRUE, a);
  Assert(IsTruthy(a), "true is truthy");

  MakeNull(a);
  Assert(NOT IsTruthy(a), "null is not truthy");

  MakeInt(0, a);
  Assert(NOT IsTruthy(a), "0 is not truthy");

  MakeStr("hello", a);
  Format(a, buf);
  Assert(CompareStr(buf, "hello") = 0, "string format")
END TestValues;

(* ══════════════════════════════════════════════════ *)
(* Event Tests                                        *)
(* ══════════════════════════════════════════════════ *)

PROCEDURE TestEvents;
VAR e: Event;
    v: Value;
    buf: ARRAY [0..1023] OF CHAR;
    found: BOOLEAN;
BEGIN
  Section("Event: Basic operations");

  InitEvent(e);
  Assert(e.numFields = 0, "empty event");

  MakeInt(200, v);
  Assert(SetField(e, "status", v), "set field");
  Assert(e.numFields = 1, "one field");

  found := GetField(e, "status", v);
  Assert(found, "get field found");
  Assert(v.intVal = 200, "field value 200");

  Assert(HasField(e, "status"), "has status");
  Assert(NOT HasField(e, "path"), "no path");

  MakeStr("/api", v);
  Assert(SetField(e, "path", v), "set path");

  FormatJson(e, buf);
  Assert(Length(buf) > 0, "json format non-empty")
END TestEvents;

(* ══════════════════════════════════════════════════ *)
(* Expression Evaluator Tests                         *)
(* ══════════════════════════════════════════════════ *)

PROCEDURE TestExprEval;
VAR
  src: ARRAY [0..511] OF CHAR;
  pr:  ParseResult;
  evt: Event;
  val: Value;
  ok:  BOOLEAN;
  result: BOOLEAN;
BEGIN
  Section("ExprEval: Filter evaluation");

  (* Build an event *)
  InitEvent(evt);
  MakeInt(503, val);
  Assert(SetField(evt, "status", val), "set status");
  MakeInt(250, val);
  Assert(SetField(evt, "latency_ms", val), "set latency");

  (* Parse a filter pipeline to get an expression *)
  Assign("source stdin | filter status >= 500 | sink stdout", src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse ok for expr test");

  (* Evaluate *)
  EvalBool(pr.pipeline.stages[0].filterExpr, evt, result, ok);
  Assert(ok, "eval ok");
  Assert(result, "503 >= 500 is true");

  (* Change status to 200 *)
  MakeInt(200, val);
  Assert(SetField(evt, "status", val), "set status 200");
  EvalBool(pr.pipeline.stages[0].filterExpr, evt, result, ok);
  Assert(ok, "eval ok 2");
  Assert(NOT result, "200 >= 500 is false")
END TestExprEval;

PROCEDURE TestExprArithmetic;
VAR
  src: ARRAY [0..511] OF CHAR;
  pr:  ParseResult;
  evt: Event;
  val: Value;
  ok:  BOOLEAN;
BEGIN
  Section("ExprEval: Arithmetic");

  InitEvent(evt);
  MakeInt(10, val);
  Assert(SetField(evt, "x", val), "set x");

  Assign("source stdin | filter x + 5 > 12 | sink stdout", src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse arithmetic");

  Eval(pr.pipeline.stages[0].filterExpr, evt, val, ok);
  Assert(ok, "eval arithmetic ok");
  Assert(val.kind = VkBool, "result is bool");
  Assert(val.boolVal, "10 + 5 > 12 is true")
END TestExprArithmetic;

PROCEDURE TestExprBooleanLogic;
VAR
  src: ARRAY [0..511] OF CHAR;
  pr:  ParseResult;
  evt: Event;
  val: Value;
  ok:  BOOLEAN;
  result: BOOLEAN;
BEGIN
  Section("ExprEval: Boolean logic");

  InitEvent(evt);
  MakeInt(503, val);
  Assert(SetField(evt, "status", val), "set status");
  MakeInt(250, val);
  Assert(SetField(evt, "latency", val), "set latency");

  Assign("source stdin | filter status >= 500 and latency > 100 | sink stdout", src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse bool logic");

  EvalBool(pr.pipeline.stages[0].filterExpr, evt, result, ok);
  Assert(ok, "eval and ok");
  Assert(result, "503>=500 and 250>100 is true");

  MakeInt(50, val);
  Assert(SetField(evt, "latency", val), "set latency 50");
  EvalBool(pr.pipeline.stages[0].filterExpr, evt, result, ok);
  Assert(ok, "eval and ok 2");
  Assert(NOT result, "503>=500 and 50>100 is false")
END TestExprBooleanLogic;

(* ══════════════════════════════════════════════════ *)
(* V1.x Feature Tests: New Keywords                   *)
(* ══════════════════════════════════════════════════ *)

PROCEDURE TestLexerNewKeywords;
VAR s: State; t: Token; ok: BOOLEAN;
    src: ARRAY [0..255] OF CHAR;
BEGIN
  Section("Lexer: New v1.x keywords");
  Assign("parse_tsv parse_kv header noheader lines", src);
  Init(s, src, Length(src));

  ok := Next(s, t); Assert(t.kind = TkParseTsv, "parse_tsv keyword");
  ok := Next(s, t); Assert(t.kind = TkParseKv, "parse_kv keyword");
  ok := Next(s, t); Assert(t.kind = TkHeader, "header keyword");
  ok := Next(s, t); Assert(t.kind = TkNoheader, "noheader keyword");
  ok := Next(s, t); Assert(t.kind = TkLines, "lines keyword");
  ok := Next(s, t); Assert(t.kind = TkEOF, "EOF after new keywords")
END TestLexerNewKeywords;

(* ══════════════════════════════════════════════════ *)
(* V1.x Feature Tests: Parser                         *)
(* ══════════════════════════════════════════════════ *)

PROCEDURE TestParserParseCsvHeader;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: parse_csv header");
  Assign("source stdin | parse_csv header | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "parse_csv header parses");
  Assert(r.pipeline.stages[0].kind = StParseCsv, "is parse_csv");
  Assert(r.pipeline.stages[0].hdrMode = HmHeader, "hdrMode is header")
END TestParserParseCsvHeader;

PROCEDURE TestParserParseCsvNoheader;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: parse_csv noheader");
  Assign("source stdin | parse_csv noheader | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "parse_csv noheader parses");
  Assert(r.pipeline.stages[0].kind = StParseCsv, "is parse_csv");
  Assert(r.pipeline.stages[0].hdrMode = HmNoheader, "hdrMode is noheader")
END TestParserParseCsvNoheader;

PROCEDURE TestParserParseCsvDefault;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: parse_csv default");
  Assign("source stdin | parse_csv | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "parse_csv default parses");
  Assert(r.pipeline.stages[0].kind = StParseCsv, "is parse_csv");
  Assert(r.pipeline.stages[0].hdrMode = HmDefault, "hdrMode is default")
END TestParserParseCsvDefault;

PROCEDURE TestParserParseTsv;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: parse_tsv");
  Assign("source stdin | parse_tsv header | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "parse_tsv header parses");
  Assert(r.pipeline.stages[0].kind = StParseTsv, "is parse_tsv");
  Assert(r.pipeline.stages[0].hdrMode = HmHeader, "tsv hdrMode is header")
END TestParserParseTsv;

PROCEDURE TestParserParseTsvNoheader;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: parse_tsv noheader");
  Assign("source stdin | parse_tsv noheader | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "parse_tsv noheader parses");
  Assert(r.pipeline.stages[0].kind = StParseTsv, "is parse_tsv noheader");
  Assert(r.pipeline.stages[0].hdrMode = HmNoheader, "tsv hdrMode is noheader")
END TestParserParseTsvNoheader;

PROCEDURE TestParserParseKv;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: parse_kv");
  Assign("source stdin | parse_kv | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "parse_kv parses");
  Assert(r.pipeline.stages[0].kind = StParseKv, "is parse_kv")
END TestParserParseKv;

PROCEDURE TestParserLines;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: lines");
  Assign("source stdin | lines | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "lines parses");
  Assert(r.pipeline.stages[0].kind = StLines, "is lines")
END TestParserLines;

PROCEDURE TestParserLinesWithFilter;
VAR src: ARRAY [0..511] OF CHAR;
    r:   ParseResult;
BEGIN
  Section("Parser: lines + filter pipeline");
  Assign("source stdin | lines | filter line >= 500 | sink stdout", src);
  Parse(src, Length(src), r);
  Assert(r.ok, "lines+filter parses");
  Assert(r.pipeline.numStages = 2, "2 stages");
  Assert(r.pipeline.stages[0].kind = StLines, "stage 0 is lines");
  Assert(r.pipeline.stages[1].kind = StFilter, "stage 1 is filter")
END TestParserLinesWithFilter;

(* ══════════════════════════════════════════════════ *)
(* V1.x Feature Tests: Sema                           *)
(* ══════════════════════════════════════════════════ *)

PROCEDURE TestSemaDupliceParseTsv;
VAR src: ARRAY [0..511] OF CHAR;
    pr:  ParseResult;
    sr:  SemaResult;
BEGIN
  Section("Sema: Duplicate parse (tsv+json)");
  Assign("source stdin | parse_tsv | parse_json | sink stdout", src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse ok");
  Validate(pr.pipeline, sr);
  Assert(NOT sr.ok, "duplicate parse tsv+json rejected")
END TestSemaDupliceParseTsv;

PROCEDURE TestSemaDupliceParseKv;
VAR src: ARRAY [0..511] OF CHAR;
    pr:  ParseResult;
    sr:  SemaResult;
BEGIN
  Section("Sema: Duplicate parse (kv+csv)");
  Assign("source stdin | parse_kv | parse_csv | sink stdout", src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse ok");
  Validate(pr.pipeline, sr);
  Assert(NOT sr.ok, "duplicate parse kv+csv rejected")
END TestSemaDupliceParseKv;

PROCEDURE TestSemaLinesCoexists;
VAR src: ARRAY [0..511] OF CHAR;
    pr:  ParseResult;
    sr:  SemaResult;
BEGIN
  Section("Sema: lines coexists with parse");
  Assign("source stdin | lines | parse_json | sink stdout", src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse ok");
  Validate(pr.pipeline, sr);
  Assert(sr.ok, "lines + parse_json allowed")
END TestSemaLinesCoexists;

PROCEDURE TestSemaValidTsv;
VAR src: ARRAY [0..511] OF CHAR;
    pr:  ParseResult;
    sr:  SemaResult;
BEGIN
  Section("Sema: Valid TSV pipeline");
  Assign("source stdin | parse_tsv noheader | filter c0 >= 500 | sink stdout", src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse ok");
  Validate(pr.pipeline, sr);
  Assert(sr.ok, "tsv noheader pipeline valid")
END TestSemaValidTsv;

PROCEDURE TestSemaValidKv;
VAR src: ARRAY [0..511] OF CHAR;
    pr:  ParseResult;
    sr:  SemaResult;
BEGIN
  Section("Sema: Valid KV pipeline");
  Assign("source stdin | parse_kv | filter level = 500 | sink stdout", src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse ok");
  Validate(pr.pipeline, sr);
  Assert(sr.ok, "kv pipeline valid")
END TestSemaValidKv;

(* ══════════════════════════════════════════════════ *)
(* V1.x Feature Tests: Plan output                    *)
(* ══════════════════════════════════════════════════ *)

PROCEDURE TestPlanTsv;
VAR src: ARRAY [0..511] OF CHAR;
    pr:  ParseResult;
    sr:  SemaResult;
BEGIN
  Section("Plan: TSV pipeline (visual check)");
  Assign('source file("data.tsv") | parse_tsv header | filter status >= 500 | sink stdout', src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse ok for tsv plan");
  Validate(pr.pipeline, sr);
  Assert(sr.ok, "sema ok for tsv plan");
  PrintPlan(pr.pipeline)
END TestPlanTsv;

PROCEDURE TestPlanKv;
VAR src: ARRAY [0..511] OF CHAR;
    pr:  ParseResult;
    sr:  SemaResult;
BEGIN
  Section("Plan: KV pipeline (visual check)");
  Assign("source stdin | parse_kv | filter level != 200 | sink stdout", src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse ok for kv plan");
  Validate(pr.pipeline, sr);
  Assert(sr.ok, "sema ok for kv plan");
  PrintPlan(pr.pipeline)
END TestPlanKv;

PROCEDURE TestPlanLines;
VAR src: ARRAY [0..511] OF CHAR;
    pr:  ParseResult;
    sr:  SemaResult;
BEGIN
  Section("Plan: Lines pipeline (visual check)");
  Assign("source stdin | lines | count | sink stdout", src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse ok for lines plan");
  Validate(pr.pipeline, sr);
  Assert(sr.ok, "sema ok for lines plan");
  PrintPlan(pr.pipeline)
END TestPlanLines;

(* ══════════════════════════════════════════════════ *)
(* Plan Tests                                         *)
(* ══════════════════════════════════════════════════ *)

PROCEDURE TestPlanOutput;
VAR src: ARRAY [0..511] OF CHAR;
    pr:  ParseResult;
    sr:  SemaResult;
BEGIN
  Section("Plan: Output (visual check)");
  Assign('source file("access.jsonl") | parse_json | filter status >= 500 | map { path, status } | count by path | sink stdout', src);
  Parse(src, Length(src), pr);
  Assert(pr.ok, "parse ok for plan");
  Validate(pr.pipeline, sr);
  Assert(sr.ok, "sema ok for plan");
  PrintPlan(pr.pipeline)
END TestPlanOutput;

(* ══════════════════════════════════════════════════ *)
(* Main                                               *)
(* ══════════════════════════════════════════════════ *)

BEGIN
  passed := 0;
  failed := 0;
  total := 0;

  WriteString("FlowQL Test Suite");
  WriteLn;
  WriteString("==================");
  WriteLn;

  (* Lexer tests *)
  TestLexerKeywords;
  TestLexerOperators;
  TestLexerLiterals;
  TestLexerLineCol;
  TestLexerComments;
  TestLexerPeek;

  (* Parser tests *)
  TestParserSimplePipeline;
  TestParserMultiStage;
  TestParserFilter;
  TestParserMapComputed;
  TestParserCountBy;
  TestParserBatch;
  TestParserFileSource;
  TestParserErrors;
  TestNamedSource;

  (* Sema tests *)
  TestSemaValid;
  TestSemaDuplicateParse;
  TestSemaBatchLimit;

  (* Value tests *)
  TestValues;

  (* Event tests *)
  TestEvents;

  (* Expression evaluator tests *)
  TestExprEval;
  TestExprArithmetic;
  TestExprBooleanLogic;

  (* V1.x Lexer tests *)
  TestLexerNewKeywords;

  (* V1.x Parser tests *)
  TestParserParseCsvHeader;
  TestParserParseCsvNoheader;
  TestParserParseCsvDefault;
  TestParserParseTsv;
  TestParserParseTsvNoheader;
  TestParserParseKv;
  TestParserLines;
  TestParserLinesWithFilter;

  (* V1.x Sema tests *)
  TestSemaDupliceParseTsv;
  TestSemaDupliceParseKv;
  TestSemaLinesCoexists;
  TestSemaValidTsv;
  TestSemaValidKv;

  (* V1.x Plan tests *)
  TestPlanTsv;
  TestPlanKv;
  TestPlanLines;

  (* Plan tests *)
  TestPlanOutput;

  (* Summary *)
  WriteLn;
  WriteString("==================");
  WriteLn;
  WriteString("Total: ");
  WriteInt(INTEGER(total), 0);
  WriteString("  Passed: ");
  WriteInt(INTEGER(passed), 0);
  WriteString("  Failed: ");
  WriteInt(INTEGER(failed), 0);
  WriteLn;

  IF failed > 0 THEN
    HALT
  END
END Main.
