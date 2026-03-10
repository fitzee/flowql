IMPLEMENTATION MODULE Parser;

FROM Token IMPORT Kind, Token, MaxLexeme,
     TkSource, TkSink, TkFilter, TkMap, TkProject,
     TkParseJson, TkParseCsv, TkParseTsv, TkParseKv,
     TkHeader, TkNoheader,
     TkCount, TkBy, TkBatch, TkWindow,
     TkStdin, TkStdout, TkFile, TkLines,
     TkAnd, TkOr, TkNot, TkContains,
     TkTrue, TkFalse, TkNull,
     TkPipe, TkLBrace, TkRBrace, TkLParen, TkRParen,
     TkComma, TkEq, TkNeq, TkGt, TkGe, TkLt, TkLe,
     TkPlus, TkMinus, TkStar, TkSlash,
     TkInt, TkReal, TkString, TkIdent, TkEOF, TkError;
FROM Lexer IMPORT State, Init, Next;
FROM Ast IMPORT Pipeline, Source, Sink, Stage, ExprPtr, Expr,
     ExprKind, BinOpKind, UnaryOpKind, FieldDef,
     SourceKind, SinkKind, StageKind,
     EkIntLit, EkRealLit, EkStrLit, EkBoolLit, EkNullLit,
     EkFieldRef, EkBinOp, EkUnaryOp, EkParen,
     BopEq, BopNeq, BopGt, BopGe, BopLt, BopLe,
     BopAdd, BopSub, BopMul, BopDiv, BopAnd, BopOr, BopContains,
     UopNot, UopNeg,
     SkFile, SkStdin, SkLines, SkNamed,
     SkStdout, SkSinkFile,
     StFilter, StMap, StProject, StParseJson, StParseCsv,
     StParseTsv, StParseKv, StLines,
     StCount, StCountBy, StBatch, StWindow,
     HeaderMode, HmDefault, HmHeader, HmNoheader,
     MaxStages, MaxFields,
     InitPipeline, NewExpr;
FROM Strings IMPORT Assign, Concat, Length;
FROM InOut IMPORT WriteString, WriteLn;

TYPE
  EP = POINTER TO Expr;

(* ── Parser state ────────────────────────────────── *)

VAR
  lex:    State;
  cur:    Token;
  hasErr: BOOLEAN;
  errBuf: ARRAY [0..MaxParseErr] OF CHAR;
  errLn:  CARDINAL;
  errCl:  CARDINAL;

PROCEDURE SetError(msg: ARRAY OF CHAR; line, col: CARDINAL);
BEGIN
  IF NOT hasErr THEN
    hasErr := TRUE;
    Assign(msg, errBuf);
    errLn := line;
    errCl := col
  END
END SetError;

PROCEDURE Advance();
VAR dummy: BOOLEAN;
BEGIN
  dummy := Next(lex, cur)
END Advance;

PROCEDURE Expect(k: Kind): BOOLEAN;
VAR buf: ARRAY [0..63] OF CHAR;
BEGIN
  IF cur.kind # k THEN
    Assign("expected ", buf);
    CASE k OF
      TkPipe:   Concat(buf, "'|'", buf)
    | TkLParen: Concat(buf, "'('", buf)
    | TkRParen: Concat(buf, "')'", buf)
    | TkLBrace: Concat(buf, "'{'", buf)
    | TkRBrace: Concat(buf, "'}'", buf)
    | TkString: Concat(buf, "string", buf)
    | TkInt:    Concat(buf, "integer", buf)
    | TkIdent:  Concat(buf, "identifier", buf)
    ELSE
      Concat(buf, "token", buf)
    END;
    SetError(buf, cur.line, cur.col);
    RETURN FALSE
  END;
  RETURN TRUE
END Expect;

(* ── Number conversion helpers ───────────────────── *)

PROCEDURE StrToInt(VAR s: ARRAY OF CHAR): INTEGER;
VAR
  i, n: INTEGER;
  neg:  BOOLEAN;
BEGIN
  i := 0;
  neg := FALSE;
  IF s[0] = '-' THEN
    neg := TRUE;
    i := 1
  END;
  n := 0;
  WHILE (ORD(s[i]) # 0) AND (s[i] >= '0') AND (s[i] <= '9') DO
    n := n * 10 + (ORD(s[i]) - ORD('0'));
    INC(i)
  END;
  IF neg THEN n := -n END;
  RETURN n
END StrToInt;

PROCEDURE StrToReal(VAR s: ARRAY OF CHAR): REAL;
VAR
  i:     INTEGER;
  whole: REAL;
  frac:  REAL;
  div:   REAL;
BEGIN
  i := 0;
  whole := 0.0;
  WHILE (ORD(s[i]) # 0) AND (s[i] >= '0') AND (s[i] <= '9') DO
    whole := whole * 10.0 + FLOAT(ORD(s[i]) - ORD('0'));
    INC(i)
  END;
  frac := 0.0;
  div := 1.0;
  IF (ORD(s[i]) # 0) AND (s[i] = '.') THEN
    INC(i);
    WHILE (ORD(s[i]) # 0) AND (s[i] >= '0') AND (s[i] <= '9') DO
      frac := frac * 10.0 + FLOAT(ORD(s[i]) - ORD('0'));
      div := div * 10.0;
      INC(i)
    END
  END;
  RETURN whole + frac / div
END StrToReal;

(* ── Expression parsing (precedence climbing) ────── *)

TYPE
  ExprParseFn = PROCEDURE(): ExprPtr;

VAR
  doParseExpr: ExprParseFn;

PROCEDURE ParsePrimary(): ExprPtr;
VAR e: EP;
    r: ExprPtr;
BEGIN
  IF hasErr THEN RETURN NIL END;

  IF cur.kind = TkInt THEN
    r := NewExpr(); e := EP(r);
    e^.kind := EkIntLit;
    e^.intVal := StrToInt(cur.lexeme);
    e^.line := cur.line; e^.col := cur.col;
    Advance();
    RETURN r
  ELSIF cur.kind = TkReal THEN
    r := NewExpr(); e := EP(r);
    e^.kind := EkRealLit;
    e^.realVal := StrToReal(cur.lexeme);
    e^.line := cur.line; e^.col := cur.col;
    Advance();
    RETURN r
  ELSIF cur.kind = TkString THEN
    r := NewExpr(); e := EP(r);
    e^.kind := EkStrLit;
    Assign(cur.lexeme, e^.strVal);
    e^.line := cur.line; e^.col := cur.col;
    Advance();
    RETURN r
  ELSIF cur.kind = TkTrue THEN
    r := NewExpr(); e := EP(r);
    e^.kind := EkBoolLit;
    e^.boolVal := TRUE;
    e^.line := cur.line; e^.col := cur.col;
    Advance();
    RETURN r
  ELSIF cur.kind = TkFalse THEN
    r := NewExpr(); e := EP(r);
    e^.kind := EkBoolLit;
    e^.boolVal := FALSE;
    e^.line := cur.line; e^.col := cur.col;
    Advance();
    RETURN r
  ELSIF cur.kind = TkNull THEN
    r := NewExpr(); e := EP(r);
    e^.kind := EkNullLit;
    e^.line := cur.line; e^.col := cur.col;
    Advance();
    RETURN r
  ELSIF cur.kind = TkIdent THEN
    r := NewExpr(); e := EP(r);
    e^.kind := EkFieldRef;
    Assign(cur.lexeme, e^.fieldName);
    e^.line := cur.line; e^.col := cur.col;
    Advance();
    RETURN r
  ELSIF cur.kind = TkLParen THEN
    Advance();
    r := doParseExpr();
    IF hasErr THEN RETURN r END;
    IF NOT Expect(TkRParen) THEN RETURN r END;
    Advance();
    RETURN r
  ELSIF cur.kind = TkNot THEN
    r := NewExpr(); e := EP(r);
    e^.kind := EkUnaryOp;
    e^.unaryOp := UopNot;
    e^.line := cur.line; e^.col := cur.col;
    Advance();
    e^.operand := ParsePrimary();
    RETURN r
  ELSIF cur.kind = TkMinus THEN
    r := NewExpr(); e := EP(r);
    e^.kind := EkUnaryOp;
    e^.unaryOp := UopNeg;
    e^.line := cur.line; e^.col := cur.col;
    Advance();
    e^.operand := ParsePrimary();
    RETURN r
  ELSE
    SetError("expected expression", cur.line, cur.col);
    RETURN NIL
  END
END ParsePrimary;

PROCEDURE ParseMul(): ExprPtr;
VAR left, right: ExprPtr;
    node: EP;
    r: ExprPtr;
    lp: EP;
    op: BinOpKind;
BEGIN
  left := ParsePrimary();
  WHILE (NOT hasErr) AND ((cur.kind = TkStar) OR (cur.kind = TkSlash)) DO
    IF cur.kind = TkStar THEN op := BopMul ELSE op := BopDiv END;
    Advance();
    right := ParsePrimary();
    r := NewExpr(); node := EP(r);
    lp := EP(left);
    node^.kind := EkBinOp;
    node^.binOp := op;
    node^.left := left;
    node^.right := right;
    node^.line := lp^.line; node^.col := lp^.col;
    left := r
  END;
  RETURN left
END ParseMul;

PROCEDURE ParseAdd(): ExprPtr;
VAR left, right: ExprPtr;
    node: EP;
    r: ExprPtr;
    lp: EP;
    op: BinOpKind;
BEGIN
  left := ParseMul();
  WHILE (NOT hasErr) AND ((cur.kind = TkPlus) OR (cur.kind = TkMinus)) DO
    IF cur.kind = TkPlus THEN op := BopAdd ELSE op := BopSub END;
    Advance();
    right := ParseMul();
    r := NewExpr(); node := EP(r);
    lp := EP(left);
    node^.kind := EkBinOp;
    node^.binOp := op;
    node^.left := left;
    node^.right := right;
    node^.line := lp^.line; node^.col := lp^.col;
    left := r
  END;
  RETURN left
END ParseAdd;

PROCEDURE ParseComparison(): ExprPtr;
VAR left, right: ExprPtr;
    node: EP;
    r: ExprPtr;
    lp: EP;
    op: BinOpKind;
BEGIN
  left := ParseAdd();
  IF hasErr THEN RETURN left END;
  IF (cur.kind = TkEq) OR (cur.kind = TkNeq) OR
     (cur.kind = TkGt) OR (cur.kind = TkGe) OR
     (cur.kind = TkLt) OR (cur.kind = TkLe) THEN
    CASE cur.kind OF
      TkEq:  op := BopEq
    | TkNeq: op := BopNeq
    | TkGt:  op := BopGt
    | TkGe:  op := BopGe
    | TkLt:  op := BopLt
    | TkLe:  op := BopLe
    END;
    Advance();
    right := ParseAdd();
    r := NewExpr(); node := EP(r);
    lp := EP(left);
    node^.kind := EkBinOp;
    node^.binOp := op;
    node^.left := left;
    node^.right := right;
    node^.line := lp^.line; node^.col := lp^.col;
    RETURN r
  ELSIF cur.kind = TkContains THEN
    Advance();
    right := ParseAdd();
    r := NewExpr(); node := EP(r);
    lp := EP(left);
    node^.kind := EkBinOp;
    node^.binOp := BopContains;
    node^.left := left;
    node^.right := right;
    node^.line := lp^.line; node^.col := lp^.col;
    RETURN r
  END;
  RETURN left
END ParseComparison;

PROCEDURE ParseAndExpr(): ExprPtr;
VAR left, right: ExprPtr;
    node: EP;
    r: ExprPtr;
    lp: EP;
BEGIN
  left := ParseComparison();
  WHILE (NOT hasErr) AND (cur.kind = TkAnd) DO
    Advance();
    right := ParseComparison();
    r := NewExpr(); node := EP(r);
    lp := EP(left);
    node^.kind := EkBinOp;
    node^.binOp := BopAnd;
    node^.left := left;
    node^.right := right;
    node^.line := lp^.line; node^.col := lp^.col;
    left := r
  END;
  RETURN left
END ParseAndExpr;

PROCEDURE ParseExpr(): ExprPtr;
VAR left, right: ExprPtr;
    node: EP;
    r: ExprPtr;
    lp: EP;
BEGIN
  left := ParseAndExpr();
  WHILE (NOT hasErr) AND (cur.kind = TkOr) DO
    Advance();
    right := ParseAndExpr();
    r := NewExpr(); node := EP(r);
    lp := EP(left);
    node^.kind := EkBinOp;
    node^.binOp := BopOr;
    node^.left := left;
    node^.right := right;
    node^.line := lp^.line; node^.col := lp^.col;
    left := r
  END;
  RETURN left
END ParseExpr;

(* ── Stage parsing ───────────────────────────────── *)

PROCEDURE ParseSource(VAR src: Source): BOOLEAN;
VAR ln, cl: CARDINAL;
BEGIN
  ln := cur.line; cl := cur.col;
  Advance();

  IF cur.kind = TkFile THEN
    src.kind := SkFile;
    Advance();
    IF NOT Expect(TkLParen) THEN RETURN FALSE END;
    Advance();
    IF NOT Expect(TkString) THEN RETURN FALSE END;
    Assign(cur.lexeme, src.path);
    Advance();
    IF NOT Expect(TkRParen) THEN RETURN FALSE END;
    Advance()
  ELSIF cur.kind = TkLines THEN
    src.kind := SkLines;
    Advance();
    IF NOT Expect(TkLParen) THEN RETURN FALSE END;
    Advance();
    IF NOT Expect(TkString) THEN RETURN FALSE END;
    Assign(cur.lexeme, src.path);
    Advance();
    IF NOT Expect(TkRParen) THEN RETURN FALSE END;
    Advance()
  ELSIF cur.kind = TkStdin THEN
    src.kind := SkStdin;
    src.path[0] := CHR(0);
    Advance()
  ELSIF cur.kind = TkIdent THEN
    src.kind := SkNamed;
    Assign(cur.lexeme, src.path);
    Advance()
  ELSE
    SetError("expected file(...), lines(...), stdin, or name after source", cur.line, cur.col);
    RETURN FALSE
  END;

  src.line := ln; src.col := cl;
  RETURN TRUE
END ParseSource;

PROCEDURE ParseSink(VAR snk: Sink): BOOLEAN;
VAR ln, cl: CARDINAL;
BEGIN
  ln := cur.line; cl := cur.col;
  Advance();

  IF cur.kind = TkStdout THEN
    snk.kind := SkStdout;
    snk.path[0] := CHR(0);
    Advance()
  ELSIF cur.kind = TkFile THEN
    snk.kind := SkSinkFile;
    Advance();
    IF NOT Expect(TkLParen) THEN RETURN FALSE END;
    Advance();
    IF NOT Expect(TkString) THEN RETURN FALSE END;
    Assign(cur.lexeme, snk.path);
    Advance();
    IF NOT Expect(TkRParen) THEN RETURN FALSE END;
    Advance()
  ELSE
    SetError("expected stdout or file(...) after sink", cur.line, cur.col);
    RETURN FALSE
  END;

  snk.line := ln; snk.col := cl;
  RETURN TRUE
END ParseSink;

PROCEDURE ParseFieldList(VAR stg: Stage): BOOLEAN;
VAR
  i: CARDINAL;
BEGIN
  IF NOT Expect(TkLBrace) THEN RETURN FALSE END;
  Advance();

  i := 0;
  WHILE (NOT hasErr) AND (cur.kind # TkRBrace) AND (cur.kind # TkEOF) DO
    IF i >= MaxFields THEN
      SetError("too many fields in map/project", cur.line, cur.col);
      RETURN FALSE
    END;
    IF NOT Expect(TkIdent) THEN RETURN FALSE END;
    Assign(cur.lexeme, stg.fields[i].name);
    stg.fields[i].line := cur.line;
    stg.fields[i].col := cur.col;
    Advance();

    IF cur.kind = TkEq THEN
      stg.fields[i].hasExpr := TRUE;
      Advance();
      stg.fields[i].expr := ParseExpr();
      IF hasErr THEN RETURN FALSE END
    ELSE
      stg.fields[i].hasExpr := FALSE;
      stg.fields[i].expr := NIL
    END;

    INC(i);
    IF cur.kind = TkComma THEN
      Advance()
    END
  END;

  stg.numFields := i;
  IF NOT Expect(TkRBrace) THEN RETURN FALSE END;
  Advance();
  RETURN TRUE
END ParseFieldList;

PROCEDURE ParseStage(VAR stg: Stage): BOOLEAN;
VAR ln, cl: CARDINAL;
BEGIN
  ln := cur.line; cl := cur.col;
  stg.line := ln; stg.col := cl;
  stg.filterExpr := NIL;
  stg.numFields := 0;
  stg.groupField[0] := CHR(0);
  stg.size := 0;
  stg.hdrMode := HmDefault;

  IF cur.kind = TkFilter THEN
    stg.kind := StFilter;
    Advance();
    stg.filterExpr := ParseExpr();
    RETURN NOT hasErr
  ELSIF cur.kind = TkMap THEN
    stg.kind := StMap;
    Advance();
    RETURN ParseFieldList(stg)
  ELSIF cur.kind = TkProject THEN
    stg.kind := StProject;
    Advance();
    RETURN ParseFieldList(stg)
  ELSIF cur.kind = TkParseJson THEN
    stg.kind := StParseJson;
    Advance();
    RETURN TRUE
  ELSIF cur.kind = TkParseCsv THEN
    stg.kind := StParseCsv;
    Advance();
    IF cur.kind = TkHeader THEN
      stg.hdrMode := HmHeader;
      Advance()
    ELSIF cur.kind = TkNoheader THEN
      stg.hdrMode := HmNoheader;
      Advance()
    END;
    RETURN TRUE
  ELSIF cur.kind = TkParseTsv THEN
    stg.kind := StParseTsv;
    Advance();
    IF cur.kind = TkHeader THEN
      stg.hdrMode := HmHeader;
      Advance()
    ELSIF cur.kind = TkNoheader THEN
      stg.hdrMode := HmNoheader;
      Advance()
    END;
    RETURN TRUE
  ELSIF cur.kind = TkParseKv THEN
    stg.kind := StParseKv;
    Advance();
    RETURN TRUE
  ELSIF cur.kind = TkLines THEN
    stg.kind := StLines;
    Advance();
    RETURN TRUE
  ELSIF cur.kind = TkCount THEN
    Advance();
    IF cur.kind = TkBy THEN
      stg.kind := StCountBy;
      Advance();
      IF NOT Expect(TkIdent) THEN RETURN FALSE END;
      Assign(cur.lexeme, stg.groupField);
      Advance()
    ELSE
      stg.kind := StCount
    END;
    RETURN TRUE
  ELSIF cur.kind = TkBatch THEN
    stg.kind := StBatch;
    Advance();
    IF NOT Expect(TkInt) THEN RETURN FALSE END;
    stg.size := CARDINAL(StrToInt(cur.lexeme));
    Advance();
    RETURN TRUE
  ELSIF cur.kind = TkWindow THEN
    stg.kind := StWindow;
    Advance();
    IF cur.kind = TkCount THEN
      Advance()
    END;
    IF NOT Expect(TkInt) THEN RETURN FALSE END;
    stg.size := CARDINAL(StrToInt(cur.lexeme));
    Advance();
    RETURN TRUE
  ELSE
    SetError("expected stage (filter, map, project, parse_json, parse_csv, parse_tsv, parse_kv, lines, count, batch, window)", cur.line, cur.col);
    RETURN FALSE
  END
END ParseStage;

(* ── Main parse entry ────────────────────────────── *)

PROCEDURE Parse(VAR source: ARRAY OF CHAR; len: CARDINAL;
                VAR result: ParseResult);
VAR
  dummy: BOOLEAN;
BEGIN
  hasErr := FALSE;
  errBuf[0] := CHR(0);
  errLn := 0;
  errCl := 0;

  Init(lex, source, len);
  dummy := Next(lex, cur);

  InitPipeline(result.pipeline);

  IF cur.kind # TkSource THEN
    SetError("pipeline must begin with 'source'", cur.line, cur.col);
    result.ok := FALSE;
    Assign(errBuf, result.errMsg);
    result.errLine := errLn;
    result.errCol := errCl;
    RETURN
  END;

  IF NOT ParseSource(result.pipeline.source) THEN
    result.ok := FALSE;
    Assign(errBuf, result.errMsg);
    result.errLine := errLn;
    result.errCol := errCl;
    RETURN
  END;
  result.pipeline.hasSource := TRUE;

  WHILE (NOT hasErr) AND (cur.kind = TkPipe) DO
    Advance();

    IF cur.kind = TkSink THEN
      IF NOT ParseSink(result.pipeline.sink) THEN
        result.ok := FALSE;
        Assign(errBuf, result.errMsg);
        result.errLine := errLn;
        result.errCol := errCl;
        RETURN
      END;
      result.pipeline.hasSink := TRUE;
      result.ok := TRUE;
      result.errMsg[0] := CHR(0);
      result.errLine := 0;
      result.errCol := 0;
      RETURN
    END;

    IF result.pipeline.numStages >= MaxStages THEN
      SetError("too many pipeline stages", cur.line, cur.col);
      result.ok := FALSE;
      Assign(errBuf, result.errMsg);
      result.errLine := errLn;
      result.errCol := errCl;
      RETURN
    END;

    IF NOT ParseStage(result.pipeline.stages[result.pipeline.numStages]) THEN
      result.ok := FALSE;
      Assign(errBuf, result.errMsg);
      result.errLine := errLn;
      result.errCol := errCl;
      RETURN
    END;
    INC(result.pipeline.numStages)
  END;

  IF hasErr THEN
    result.ok := FALSE;
    Assign(errBuf, result.errMsg);
    result.errLine := errLn;
    result.errCol := errCl;
    RETURN
  END;

  (* Sink is optional — embedded use may not have a sink *)

  result.ok := TRUE;
  result.errMsg[0] := CHR(0);
  result.errLine := 0;
  result.errCol := 0
END Parse;

BEGIN
  doParseExpr := ParseExpr
END Parser.
