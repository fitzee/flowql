IMPLEMENTATION MODULE Lexer;

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
FROM Strings IMPORT Assign, Length, CompareStr;

(* ── Helpers ──────────────────────────────────────── *)

PROCEDURE IsAlpha(c: CHAR): BOOLEAN;
BEGIN
  RETURN ((c >= 'a') AND (c <= 'z')) OR
         ((c >= 'A') AND (c <= 'Z')) OR
         (c = '_')
END IsAlpha;

PROCEDURE IsDigit(c: CHAR): BOOLEAN;
BEGIN
  RETURN (c >= '0') AND (c <= '9')
END IsDigit;

PROCEDURE IsAlNum(c: CHAR): BOOLEAN;
BEGIN
  RETURN IsAlpha(c) OR IsDigit(c)
END IsAlNum;

PROCEDURE IsSpace(c: CHAR): BOOLEAN;
BEGIN
  RETURN (c = ' ') OR (c = CHR(9)) OR (c = CHR(13)) OR (c = CHR(10))
END IsSpace;

PROCEDURE CurChar(VAR s: State): CHAR;
BEGIN
  IF s.pos < s.srcLen THEN
    RETURN s.src[s.pos]
  ELSE
    RETURN CHR(0)
  END
END CurChar;

PROCEDURE Advance(VAR s: State);
BEGIN
  IF s.pos < s.srcLen THEN
    IF s.src[s.pos] = CHR(10) THEN
      INC(s.line);
      s.col := 1
    ELSE
      INC(s.col)
    END;
    INC(s.pos)
  END
END Advance;

PROCEDURE SkipWhitespace(VAR s: State);
BEGIN
  WHILE (s.pos < s.srcLen) AND IsSpace(s.src[s.pos]) DO
    Advance(s)
  END
END SkipWhitespace;

PROCEDURE SkipLineComment(VAR s: State);
BEGIN
  (* skip # comment to end of line *)
  WHILE (s.pos < s.srcLen) AND (s.src[s.pos] # CHR(10)) DO
    Advance(s)
  END
END SkipLineComment;

PROCEDURE SkipWhitespaceAndComments(VAR s: State);
VAR done: BOOLEAN;
BEGIN
  done := FALSE;
  WHILE NOT done DO
    SkipWhitespace(s);
    IF (s.pos < s.srcLen) AND (s.src[s.pos] = '#') THEN
      SkipLineComment(s)
    ELSE
      done := TRUE
    END
  END
END SkipWhitespaceAndComments;

PROCEDURE LookupKeyword(VAR lex: ARRAY OF CHAR): Kind;
BEGIN
  IF CompareStr(lex, "source") = 0 THEN RETURN TkSource
  ELSIF CompareStr(lex, "sink") = 0 THEN RETURN TkSink
  ELSIF CompareStr(lex, "filter") = 0 THEN RETURN TkFilter
  ELSIF CompareStr(lex, "map") = 0 THEN RETURN TkMap
  ELSIF CompareStr(lex, "project") = 0 THEN RETURN TkProject
  ELSIF CompareStr(lex, "parse_json") = 0 THEN RETURN TkParseJson
  ELSIF CompareStr(lex, "parse_csv") = 0 THEN RETURN TkParseCsv
  ELSIF CompareStr(lex, "parse_tsv") = 0 THEN RETURN TkParseTsv
  ELSIF CompareStr(lex, "parse_kv") = 0 THEN RETURN TkParseKv
  ELSIF CompareStr(lex, "header") = 0 THEN RETURN TkHeader
  ELSIF CompareStr(lex, "noheader") = 0 THEN RETURN TkNoheader
  ELSIF CompareStr(lex, "count") = 0 THEN RETURN TkCount
  ELSIF CompareStr(lex, "by") = 0 THEN RETURN TkBy
  ELSIF CompareStr(lex, "batch") = 0 THEN RETURN TkBatch
  ELSIF CompareStr(lex, "window") = 0 THEN RETURN TkWindow
  ELSIF CompareStr(lex, "stdin") = 0 THEN RETURN TkStdin
  ELSIF CompareStr(lex, "stdout") = 0 THEN RETURN TkStdout
  ELSIF CompareStr(lex, "file") = 0 THEN RETURN TkFile
  ELSIF CompareStr(lex, "lines") = 0 THEN RETURN TkLines
  ELSIF CompareStr(lex, "and") = 0 THEN RETURN TkAnd
  ELSIF CompareStr(lex, "or") = 0 THEN RETURN TkOr
  ELSIF CompareStr(lex, "not") = 0 THEN RETURN TkNot
  ELSIF CompareStr(lex, "contains") = 0 THEN RETURN TkContains
  ELSIF CompareStr(lex, "true") = 0 THEN RETURN TkTrue
  ELSIF CompareStr(lex, "false") = 0 THEN RETURN TkFalse
  ELSIF CompareStr(lex, "null") = 0 THEN RETURN TkNull
  ELSE RETURN TkIdent
  END
END LookupKeyword;

(* ── Public API ──────────────────────────────────── *)

PROCEDURE Init(VAR s: State; VAR source: ARRAY OF CHAR; len: CARDINAL);
VAR i: CARDINAL;
BEGIN
  IF len > MaxSource THEN
    len := MaxSource
  END;
  i := 0;
  WHILE i < len DO
    s.src[i] := source[i];
    INC(i)
  END;
  s.src[len] := CHR(0);
  s.srcLen := len;
  s.pos := 0;
  s.line := 1;
  s.col := 1
END Init;

PROCEDURE ScanToken(VAR s: State; VAR tok: Token): BOOLEAN;
VAR
  c:   CHAR;
  i:   CARDINAL;
  startLine, startCol: CARDINAL;
  hasDot: BOOLEAN;
BEGIN
  SkipWhitespaceAndComments(s);

  IF s.pos >= s.srcLen THEN
    tok.kind := TkEOF;
    tok.lexeme[0] := CHR(0);
    tok.line := s.line;
    tok.col := s.col;
    RETURN FALSE
  END;

  startLine := s.line;
  startCol := s.col;
  c := CurChar(s);

  (* Single/double character operators *)
  IF c = '|' THEN
    tok.kind := TkPipe;
    Assign("|", tok.lexeme);
    tok.line := startLine; tok.col := startCol;
    Advance(s);
    RETURN TRUE
  ELSIF c = '{' THEN
    tok.kind := TkLBrace;
    Assign("{", tok.lexeme);
    tok.line := startLine; tok.col := startCol;
    Advance(s);
    RETURN TRUE
  ELSIF c = '}' THEN
    tok.kind := TkRBrace;
    Assign("}", tok.lexeme);
    tok.line := startLine; tok.col := startCol;
    Advance(s);
    RETURN TRUE
  ELSIF c = '(' THEN
    tok.kind := TkLParen;
    Assign("(", tok.lexeme);
    tok.line := startLine; tok.col := startCol;
    Advance(s);
    RETURN TRUE
  ELSIF c = ')' THEN
    tok.kind := TkRParen;
    Assign(")", tok.lexeme);
    tok.line := startLine; tok.col := startCol;
    Advance(s);
    RETURN TRUE
  ELSIF c = ',' THEN
    tok.kind := TkComma;
    Assign(",", tok.lexeme);
    tok.line := startLine; tok.col := startCol;
    Advance(s);
    RETURN TRUE
  ELSIF c = '+' THEN
    tok.kind := TkPlus;
    Assign("+", tok.lexeme);
    tok.line := startLine; tok.col := startCol;
    Advance(s);
    RETURN TRUE
  ELSIF c = '-' THEN
    tok.kind := TkMinus;
    Assign("-", tok.lexeme);
    tok.line := startLine; tok.col := startCol;
    Advance(s);
    RETURN TRUE
  ELSIF c = '*' THEN
    tok.kind := TkStar;
    Assign("*", tok.lexeme);
    tok.line := startLine; tok.col := startCol;
    Advance(s);
    RETURN TRUE
  ELSIF c = '/' THEN
    tok.kind := TkSlash;
    Assign("/", tok.lexeme);
    tok.line := startLine; tok.col := startCol;
    Advance(s);
    RETURN TRUE
  ELSIF c = '>' THEN
    Advance(s);
    IF (s.pos < s.srcLen) AND (CurChar(s) = '=') THEN
      tok.kind := TkGe;
      Assign(">=", tok.lexeme);
      Advance(s)
    ELSE
      tok.kind := TkGt;
      Assign(">", tok.lexeme)
    END;
    tok.line := startLine; tok.col := startCol;
    RETURN TRUE
  ELSIF c = '<' THEN
    Advance(s);
    IF (s.pos < s.srcLen) AND (CurChar(s) = '=') THEN
      tok.kind := TkLe;
      Assign("<=", tok.lexeme);
      Advance(s)
    ELSE
      tok.kind := TkLt;
      Assign("<", tok.lexeme)
    END;
    tok.line := startLine; tok.col := startCol;
    RETURN TRUE
  ELSIF c = '!' THEN
    Advance(s);
    IF (s.pos < s.srcLen) AND (CurChar(s) = '=') THEN
      tok.kind := TkNeq;
      Assign("!=", tok.lexeme);
      Advance(s)
    ELSE
      tok.kind := TkError;
      Assign("!", tok.lexeme)
    END;
    tok.line := startLine; tok.col := startCol;
    RETURN TRUE
  ELSIF c = '=' THEN
    tok.kind := TkEq;
    Assign("=", tok.lexeme);
    tok.line := startLine; tok.col := startCol;
    Advance(s);
    RETURN TRUE
  END;

  (* String literal *)
  IF c = '"' THEN
    Advance(s);
    i := 0;
    WHILE (s.pos < s.srcLen) AND (CurChar(s) # '"') AND (i < MaxLexeme - 1) DO
      IF CurChar(s) = CHR(10) THEN
        tok.kind := TkError;
        tok.lexeme[i] := CHR(0);
        tok.line := startLine; tok.col := startCol;
        RETURN TRUE
      END;
      tok.lexeme[i] := CurChar(s);
      INC(i);
      Advance(s)
    END;
    tok.lexeme[i] := CHR(0);
    IF (s.pos < s.srcLen) AND (CurChar(s) = '"') THEN
      Advance(s);
      tok.kind := TkString
    ELSE
      tok.kind := TkError
    END;
    tok.line := startLine; tok.col := startCol;
    RETURN TRUE
  END;

  (* Number literal *)
  IF IsDigit(c) THEN
    i := 0;
    hasDot := FALSE;
    WHILE (s.pos < s.srcLen) AND (IsDigit(CurChar(s)) OR (CurChar(s) = '.')) AND (i < MaxLexeme - 1) DO
      IF CurChar(s) = '.' THEN
        IF hasDot THEN
          (* second dot — stop *)
          tok.lexeme[i] := CHR(0);
          tok.kind := TkReal;
          tok.line := startLine; tok.col := startCol;
          RETURN TRUE
        END;
        hasDot := TRUE
      END;
      tok.lexeme[i] := CurChar(s);
      INC(i);
      Advance(s)
    END;
    tok.lexeme[i] := CHR(0);
    IF hasDot THEN
      tok.kind := TkReal
    ELSE
      tok.kind := TkInt
    END;
    tok.line := startLine; tok.col := startCol;
    RETURN TRUE
  END;

  (* Identifier or keyword *)
  IF IsAlpha(c) THEN
    i := 0;
    WHILE (s.pos < s.srcLen) AND IsAlNum(CurChar(s)) AND (i < MaxLexeme - 1) DO
      tok.lexeme[i] := CurChar(s);
      INC(i);
      Advance(s)
    END;
    tok.lexeme[i] := CHR(0);
    tok.kind := LookupKeyword(tok.lexeme);
    tok.line := startLine; tok.col := startCol;
    RETURN TRUE
  END;

  (* Unknown character *)
  tok.kind := TkError;
  tok.lexeme[0] := c;
  tok.lexeme[1] := CHR(0);
  tok.line := startLine; tok.col := startCol;
  Advance(s);
  RETURN TRUE
END ScanToken;

PROCEDURE Next(VAR s: State; VAR tok: Token): BOOLEAN;
BEGIN
  RETURN ScanToken(s, tok)
END Next;

PROCEDURE Peek(VAR s: State; VAR tok: Token): BOOLEAN;
VAR
  savedPos:  CARDINAL;
  savedLine: CARDINAL;
  savedCol:  CARDINAL;
  result:    BOOLEAN;
BEGIN
  savedPos := s.pos;
  savedLine := s.line;
  savedCol := s.col;
  result := ScanToken(s, tok);
  s.pos := savedPos;
  s.line := savedLine;
  s.col := savedCol;
  RETURN result
END Peek;

END Lexer.
