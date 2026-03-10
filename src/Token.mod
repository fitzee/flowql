IMPLEMENTATION MODULE Token;

FROM Strings IMPORT Assign;

PROCEDURE KindName(k: Kind; VAR buf: ARRAY OF CHAR);
BEGIN
  CASE k OF
    TkSource:    Assign("source", buf)
  | TkSink:      Assign("sink", buf)
  | TkFilter:    Assign("filter", buf)
  | TkMap:       Assign("map", buf)
  | TkProject:   Assign("project", buf)
  | TkParseJson: Assign("parse_json", buf)
  | TkParseCsv:  Assign("parse_csv", buf)
  | TkParseTsv:  Assign("parse_tsv", buf)
  | TkParseKv:   Assign("parse_kv", buf)
  | TkHeader:    Assign("header", buf)
  | TkNoheader:  Assign("noheader", buf)
  | TkCount:     Assign("count", buf)
  | TkBy:        Assign("by", buf)
  | TkBatch:     Assign("batch", buf)
  | TkWindow:    Assign("window", buf)
  | TkStdin:     Assign("stdin", buf)
  | TkStdout:    Assign("stdout", buf)
  | TkFile:      Assign("file", buf)
  | TkLines:     Assign("lines", buf)
  | TkAnd:       Assign("and", buf)
  | TkOr:        Assign("or", buf)
  | TkNot:       Assign("not", buf)
  | TkContains:  Assign("contains", buf)
  | TkTrue:      Assign("true", buf)
  | TkFalse:     Assign("false", buf)
  | TkNull:      Assign("null", buf)
  | TkPipe:      Assign("|", buf)
  | TkLBrace:    Assign("{", buf)
  | TkRBrace:    Assign("}", buf)
  | TkLParen:    Assign("(", buf)
  | TkRParen:    Assign(")", buf)
  | TkComma:     Assign(",", buf)
  | TkEq:        Assign("=", buf)
  | TkNeq:       Assign("!=", buf)
  | TkGt:        Assign(">", buf)
  | TkGe:        Assign(">=", buf)
  | TkLt:        Assign("<", buf)
  | TkLe:        Assign("<=", buf)
  | TkPlus:      Assign("+", buf)
  | TkMinus:     Assign("-", buf)
  | TkStar:      Assign("*", buf)
  | TkSlash:     Assign("/", buf)
  | TkInt:       Assign("<int>", buf)
  | TkReal:      Assign("<real>", buf)
  | TkString:    Assign("<string>", buf)
  | TkIdent:     Assign("<ident>", buf)
  | TkEOF:       Assign("<eof>", buf)
  | TkError:     Assign("<error>", buf)
  END
END KindName;

PROCEDURE IsKeyword(k: Kind): BOOLEAN;
BEGIN
  RETURN (k >= TkSource) AND (k <= TkNull)
END IsKeyword;

END Token.
