IMPLEMENTATION MODULE Runtime;

FROM SYSTEM IMPORT ADDRESS, ADR;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM Strings IMPORT Assign, Length, CompareStr, Concat;
IMPORT InOut;
FROM InOut IMPORT WriteString, WriteLn, Write;
FROM BinaryIO IMPORT OpenRead, OpenWrite, Close, ReadBytes, WriteBytes;
FROM Ast IMPORT ExprPtr, Expr, Stage, StageKind, StMap, StProject,
     FieldDef, MaxFields;
FROM Event IMPORT Event, EventPtr, NewEvent, FreeEvent, InitEvent,
     SetField, GetField, HasField, FormatJson, MaxEventFields;
FROM Value IMPORT Value, ValueKind, VkInt, VkReal, VkBool, VkStr, VkNull,
     MakeInt, MakeReal, MakeBool, MakeStr, MakeNull, Format;
FROM ExprEval IMPORT Eval, EvalBool;

TYPE
  EP = POINTER TO Expr;
  SP = POINTER TO Stage;

(* ── Source ──────────────────────────────────────── *)

PROCEDURE ReadLine(VAR data: FileSourceData; VAR got: BOOLEAN);
VAR
  ch:     CHAR;
  i:      CARDINAL;
  actual: CARDINAL;
  chBuf:  ARRAY [0..0] OF CHAR;
BEGIN
  got := FALSE;
  i := 0;
  IF data.isStdin THEN
    LOOP
      InOut.Read(ch);
      IF NOT InOut.Done THEN
        IF i > 0 THEN got := TRUE END;
        data.done := TRUE;
        data.lineBuf[i] := CHR(0);
        RETURN
      END;
      IF ch = CHR(10) THEN
        data.lineBuf[i] := CHR(0);
        got := TRUE;
        RETURN
      END;
      IF (ch # CHR(13)) AND (i < MaxLineBuf) THEN
        data.lineBuf[i] := ch;
        INC(i)
      END
    END
  ELSE
    LOOP
      actual := 0;
      ReadBytes(data.fh, chBuf, 1, actual);
      IF actual = 0 THEN
        IF i > 0 THEN got := TRUE END;
        data.done := TRUE;
        data.lineBuf[i] := CHR(0);
        RETURN
      END;
      ch := chBuf[0];
      IF ch = CHR(10) THEN
        data.lineBuf[i] := CHR(0);
        got := TRUE;
        RETURN
      END;
      IF (ch # CHR(13)) AND (i < MaxLineBuf) THEN
        data.lineBuf[i] := ch;
        INC(i)
      END
    END
  END
END ReadLine;

PROCEDURE SourceGen(userData: ADDRESS; VAR item: ADDRESS;
                    VAR done: BOOLEAN);
VAR
  data: POINTER TO FileSourceData;
  evt:  EventPtr;
  val:  Value;
  got:  BOOLEAN;
BEGIN
  data := userData;
  IF data^.done THEN
    done := TRUE;
    RETURN
  END;
  ReadLine(data^, got);
  IF NOT got THEN
    done := TRUE;
    RETURN
  END;
  evt := NewEvent();
  MakeStr(data^.lineBuf, val);
  IF NOT SetField(evt^, "_line", val) THEN END;
  item := ADDRESS(evt);
  done := data^.done
END SourceGen;

(* ── Parse JSON ──────────────────────────────────── *)

PROCEDURE ParseJsonTransform(userData: ADDRESS; inItem: ADDRESS;
                             VAR outItem: ADDRESS);
VAR
  inEvt:  EventPtr;
  outEvt: EventPtr;
  val:    Value;
  line:   ARRAY [0..MaxLineBuf] OF CHAR;
  found:  BOOLEAN;
BEGIN
  inEvt := inItem;
  found := GetField(inEvt^, "_line", val);
  IF (NOT found) OR (val.kind # VkStr) THEN
    outItem := inItem;
    RETURN
  END;
  Assign(val.strVal, line);
  outEvt := NewEvent();
  ParseJsonLine(line, outEvt^);
  outItem := ADDRESS(outEvt)
END ParseJsonTransform;

PROCEDURE HasDot(VAR s: ARRAY OF CHAR): BOOLEAN;
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE (i <= HIGH(s)) AND (ORD(s[i]) # 0) DO
    IF s[i] = '.' THEN RETURN TRUE END;
    INC(i)
  END;
  RETURN FALSE
END HasDot;

PROCEDURE ParseIntVal(VAR s: ARRAY OF CHAR): INTEGER;
VAR
  i, n: INTEGER;
  neg:  BOOLEAN;
BEGIN
  i := 0; n := 0;
  neg := FALSE;
  IF s[0] = '-' THEN neg := TRUE; i := 1 END;
  WHILE (ORD(s[i]) # 0) AND (s[i] >= '0') AND (s[i] <= '9') DO
    n := n * 10 + (ORD(s[i]) - ORD('0'));
    INC(i)
  END;
  IF neg THEN RETURN -n ELSE RETURN n END
END ParseIntVal;

PROCEDURE ParseRealVal(VAR s: ARRAY OF CHAR): REAL;
VAR
  i:     INTEGER;
  whole: REAL;
  frac:  REAL;
  div:   REAL;
  neg:   BOOLEAN;
BEGIN
  i := 0; whole := 0.0; neg := FALSE;
  IF s[0] = '-' THEN neg := TRUE; i := 1 END;
  WHILE (ORD(s[i]) # 0) AND (s[i] >= '0') AND (s[i] <= '9') DO
    whole := whole * 10.0 + FLOAT(ORD(s[i]) - ORD('0'));
    INC(i)
  END;
  frac := 0.0; div := 1.0;
  IF (ORD(s[i]) # 0) AND (s[i] = '.') THEN
    INC(i);
    WHILE (ORD(s[i]) # 0) AND (s[i] >= '0') AND (s[i] <= '9') DO
      frac := frac * 10.0 + FLOAT(ORD(s[i]) - ORD('0'));
      div := div * 10.0;
      INC(i)
    END
  END;
  IF neg THEN RETURN -(whole + frac / div)
  ELSE RETURN whole + frac / div
  END
END ParseRealVal;

PROCEDURE ParseJsonLine(VAR line: ARRAY OF CHAR; VAR evt: Event);
VAR
  i:       CARDINAL;
  key:     ARRAY [0..63] OF CHAR;
  valBuf:  ARRAY [0..255] OF CHAR;
  val:     Value;
  ki, vi:  CARDINAL;
  ch:      CHAR;
BEGIN
  InitEvent(evt);
  i := 0;
  WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND (line[i] # '{') DO
    INC(i)
  END;
  IF (i > HIGH(line)) OR (ORD(line[i]) = 0) THEN RETURN END;
  INC(i);

  LOOP
    WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND
          ((line[i] = ' ') OR (line[i] = CHR(9)) OR
           (line[i] = CHR(10)) OR (line[i] = CHR(13))) DO
      INC(i)
    END;
    IF (i > HIGH(line)) OR (ORD(line[i]) = 0) OR (line[i] = '}') THEN
      EXIT
    END;

    IF line[i] = '"' THEN
      INC(i);
      ki := 0;
      WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND (line[i] # '"') AND (ki < 63) DO
        key[ki] := line[i];
        INC(ki); INC(i)
      END;
      key[ki] := CHR(0);
      IF (i <= HIGH(line)) AND (line[i] = '"') THEN INC(i) END
    ELSE
      EXIT
    END;

    WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND
          ((line[i] = ':') OR (line[i] = ' ') OR (line[i] = CHR(9))) DO
      INC(i)
    END;

    IF (i > HIGH(line)) OR (ORD(line[i]) = 0) THEN EXIT END;

    ch := line[i];
    IF ch = '"' THEN
      INC(i);
      vi := 0;
      WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND (line[i] # '"') AND (vi < 255) DO
        IF (line[i] = '\') AND (i + 1 <= HIGH(line)) THEN
          INC(i);
          valBuf[vi] := line[i]
        ELSE
          valBuf[vi] := line[i]
        END;
        INC(vi); INC(i)
      END;
      valBuf[vi] := CHR(0);
      IF (i <= HIGH(line)) AND (line[i] = '"') THEN INC(i) END;
      MakeStr(valBuf, val)
    ELSIF ch = 't' THEN
      MakeBool(TRUE, val);
      INC(i, 4)
    ELSIF ch = 'f' THEN
      MakeBool(FALSE, val);
      INC(i, 5)
    ELSIF ch = 'n' THEN
      MakeNull(val);
      INC(i, 4)
    ELSIF ((ch >= '0') AND (ch <= '9')) OR (ch = '-') THEN
      vi := 0;
      IF ch = '-' THEN
        valBuf[vi] := ch; INC(vi); INC(i)
      END;
      WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND
            (((line[i] >= '0') AND (line[i] <= '9')) OR (line[i] = '.')) AND
            (vi < 255) DO
        valBuf[vi] := line[i];
        INC(vi); INC(i)
      END;
      valBuf[vi] := CHR(0);
      IF HasDot(valBuf) THEN
        MakeReal(ParseRealVal(valBuf), val)
      ELSE
        MakeInt(ParseIntVal(valBuf), val)
      END
    ELSE
      EXIT
    END;

    IF NOT SetField(evt, key, val) THEN END;

    WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND
          ((line[i] = ',') OR (line[i] = ' ') OR (line[i] = CHR(9)) OR
           (line[i] = CHR(10)) OR (line[i] = CHR(13))) DO
      INC(i)
    END
  END
END ParseJsonLine;

(* ── Parse CSV ──────────────────────────────────── *)

PROCEDURE ParseCsvTransform(userData: ADDRESS; inItem: ADDRESS;
                            VAR outItem: ADDRESS);
VAR
  data:   POINTER TO CsvParseData;
  inEvt:  EventPtr;
  outEvt: EventPtr;
  val:    Value;
  line:   ARRAY [0..MaxLineBuf] OF CHAR;
  found:  BOOLEAN;
  i:      CARDINAL;
BEGIN
  data := userData;
  inEvt := inItem;
  found := GetField(inEvt^, "_line", val);
  IF (NOT found) OR (val.kind # VkStr) THEN
    outItem := inItem;
    RETURN
  END;
  Assign(val.strVal, line);

  IF data^.hasHeader AND (NOT data^.headerDone) THEN
    ParseCsvHeaders(data^, line);
    data^.headerDone := TRUE;
    outEvt := NewEvent();
    InitEvent(outEvt^);
    i := 0;
    WHILE i < data^.numHeaders DO
      MakeStr(data^.headers[i], val);
      IF NOT SetField(outEvt^, data^.headers[i], val) THEN END;
      INC(i)
    END;
    outItem := ADDRESS(outEvt);
    RETURN
  END;

  outEvt := NewEvent();
  ParseCsvLine(line, data^, outEvt^);
  outItem := ADDRESS(outEvt)
END ParseCsvTransform;

PROCEDURE ParseCsvHeaders(VAR data: CsvParseData;
                          VAR line: ARRAY OF CHAR);
VAR
  i, fi: CARDINAL;
BEGIN
  data.numHeaders := 0;
  i := 0;
  fi := 0;
  WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) DO
    IF line[i] = ',' THEN
      data.headers[data.numHeaders][fi] := CHR(0);
      INC(data.numHeaders);
      fi := 0
    ELSE
      IF fi < 63 THEN
        data.headers[data.numHeaders][fi] := line[i];
        INC(fi)
      END
    END;
    INC(i)
  END;
  data.headers[data.numHeaders][fi] := CHR(0);
  INC(data.numHeaders)
END ParseCsvHeaders;

PROCEDURE IntToColName(n: CARDINAL; VAR buf: ARRAY OF CHAR);
VAR tmp: ARRAY [0..15] OF CHAR;
    i, j: CARDINAL;
BEGIN
  Assign("c", buf);
  IF n = 0 THEN
    Concat(buf, "0", buf);
    RETURN
  END;
  i := 0;
  WHILE n > 0 DO
    tmp[i] := CHR(ORD('0') + (n MOD 10));
    n := n DIV 10;
    INC(i)
  END;
  j := Length(buf);
  WHILE i > 0 DO
    DEC(i);
    IF j < HIGH(buf) THEN
      buf[j] := tmp[i];
      INC(j)
    END
  END;
  buf[j] := CHR(0)
END IntToColName;

PROCEDURE MakeSmartVal(VAR s: ARRAY OF CHAR; VAR v: Value);
VAR
  isNum: BOOLEAN;
  hasDot: BOOLEAN;
  i: CARDINAL;
BEGIN
  IF ORD(s[0]) = 0 THEN
    MakeNull(v);
    RETURN
  END;
  IF CompareStr(s, "true") = 0 THEN MakeBool(TRUE, v); RETURN END;
  IF CompareStr(s, "false") = 0 THEN MakeBool(FALSE, v); RETURN END;
  IF CompareStr(s, "null") = 0 THEN MakeNull(v); RETURN END;

  isNum := TRUE;
  hasDot := FALSE;
  i := 0;
  IF s[0] = '-' THEN i := 1 END;
  IF (i > HIGH(s)) OR (ORD(s[i]) = 0) THEN isNum := FALSE END;
  WHILE (i <= HIGH(s)) AND (ORD(s[i]) # 0) AND isNum DO
    IF (s[i] >= '0') AND (s[i] <= '9') THEN
      (* ok *)
    ELSIF s[i] = '.' THEN
      IF hasDot THEN isNum := FALSE END;
      hasDot := TRUE
    ELSE
      isNum := FALSE
    END;
    INC(i)
  END;
  IF isNum THEN
    IF hasDot THEN
      MakeReal(ParseRealVal(s), v)
    ELSE
      MakeInt(ParseIntVal(s), v)
    END
  ELSE
    MakeStr(s, v)
  END
END MakeSmartVal;

PROCEDURE ParseCsvLine(VAR line: ARRAY OF CHAR; VAR data: CsvParseData;
                       VAR evt: Event);
VAR
  i, fi, col: CARDINAL;
  field:      ARRAY [0..255] OF CHAR;
  val:        Value;
  colName:    ARRAY [0..63] OF CHAR;
BEGIN
  InitEvent(evt);
  i := 0;
  fi := 0;
  col := 0;
  WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) DO
    IF line[i] = ',' THEN
      field[fi] := CHR(0);
      MakeSmartVal(field, val);
      IF (col < data.numHeaders) AND data.hasHeader THEN
        IF NOT SetField(evt, data.headers[col], val) THEN END
      ELSE
        IntToColName(col, colName);
        IF NOT SetField(evt, colName, val) THEN END
      END;
      fi := 0;
      INC(col)
    ELSE
      IF fi < 255 THEN
        field[fi] := line[i];
        INC(fi)
      END
    END;
    INC(i)
  END;
  field[fi] := CHR(0);
  MakeSmartVal(field, val);
  IF (col < data.numHeaders) AND data.hasHeader THEN
    IF NOT SetField(evt, data.headers[col], val) THEN END
  ELSE
    IntToColName(col, colName);
    IF NOT SetField(evt, colName, val) THEN END
  END
END ParseCsvLine;

(* ── Parse TSV ─────────────────────────────────────── *)

PROCEDURE ParseTsvHeaders(VAR data: TsvParseData;
                          VAR line: ARRAY OF CHAR);
VAR
  i, fi: CARDINAL;
BEGIN
  data.numHeaders := 0;
  i := 0;
  fi := 0;
  WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) DO
    IF line[i] = CHR(9) THEN
      data.headers[data.numHeaders][fi] := CHR(0);
      INC(data.numHeaders);
      fi := 0
    ELSE
      IF fi < 63 THEN
        data.headers[data.numHeaders][fi] := line[i];
        INC(fi)
      END
    END;
    INC(i)
  END;
  data.headers[data.numHeaders][fi] := CHR(0);
  INC(data.numHeaders)
END ParseTsvHeaders;

PROCEDURE ParseTsvLine(VAR line: ARRAY OF CHAR; VAR data: TsvParseData;
                       VAR evt: Event);
VAR
  i, fi, col: CARDINAL;
  field:      ARRAY [0..255] OF CHAR;
  val:        Value;
  colName:    ARRAY [0..63] OF CHAR;
BEGIN
  InitEvent(evt);
  i := 0;
  fi := 0;
  col := 0;
  WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) DO
    IF line[i] = CHR(9) THEN
      field[fi] := CHR(0);
      MakeSmartVal(field, val);
      IF (col < data.numHeaders) AND data.hasHeader THEN
        IF NOT SetField(evt, data.headers[col], val) THEN END
      ELSE
        IntToColName(col, colName);
        IF NOT SetField(evt, colName, val) THEN END
      END;
      fi := 0;
      INC(col)
    ELSE
      IF fi < 255 THEN
        field[fi] := line[i];
        INC(fi)
      END
    END;
    INC(i)
  END;
  field[fi] := CHR(0);
  MakeSmartVal(field, val);
  IF (col < data.numHeaders) AND data.hasHeader THEN
    IF NOT SetField(evt, data.headers[col], val) THEN END
  ELSE
    IntToColName(col, colName);
    IF NOT SetField(evt, colName, val) THEN END
  END
END ParseTsvLine;

PROCEDURE ParseTsvTransform(userData: ADDRESS; inItem: ADDRESS;
                            VAR outItem: ADDRESS);
VAR
  data:   POINTER TO TsvParseData;
  inEvt:  EventPtr;
  outEvt: EventPtr;
  val:    Value;
  line:   ARRAY [0..MaxLineBuf] OF CHAR;
  found:  BOOLEAN;
  i:      CARDINAL;
BEGIN
  data := userData;
  inEvt := inItem;
  found := GetField(inEvt^, "_line", val);
  IF (NOT found) OR (val.kind # VkStr) THEN
    outItem := inItem;
    RETURN
  END;
  Assign(val.strVal, line);

  IF data^.hasHeader AND (NOT data^.headerDone) THEN
    ParseTsvHeaders(data^, line);
    data^.headerDone := TRUE;
    outEvt := NewEvent();
    InitEvent(outEvt^);
    i := 0;
    WHILE i < data^.numHeaders DO
      MakeStr(data^.headers[i], val);
      IF NOT SetField(outEvt^, data^.headers[i], val) THEN END;
      INC(i)
    END;
    outItem := ADDRESS(outEvt);
    RETURN
  END;

  outEvt := NewEvent();
  ParseTsvLine(line, data^, outEvt^);
  outItem := ADDRESS(outEvt)
END ParseTsvTransform;

(* ── Parse KV ──────────────────────────────────────── *)

PROCEDURE ParseKvTransform(userData: ADDRESS; inItem: ADDRESS;
                           VAR outItem: ADDRESS);
VAR
  inEvt:   EventPtr;
  outEvt:  EventPtr;
  val:     Value;
  line:    ARRAY [0..MaxLineBuf] OF CHAR;
  found:   BOOLEAN;
  i:       CARDINAL;
  key:     ARRAY [0..63] OF CHAR;
  valBuf:  ARRAY [0..255] OF CHAR;
  ki, vi:  CARDINAL;
BEGIN
  inEvt := inItem;
  found := GetField(inEvt^, "_line", val);
  IF (NOT found) OR (val.kind # VkStr) THEN
    outItem := inItem;
    RETURN
  END;
  Assign(val.strVal, line);

  outEvt := NewEvent();
  InitEvent(outEvt^);
  i := 0;

  LOOP
    (* skip whitespace *)
    WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND
          ((line[i] = ' ') OR (line[i] = CHR(9))) DO
      INC(i)
    END;
    IF (i > HIGH(line)) OR (ORD(line[i]) = 0) THEN EXIT END;

    (* read key *)
    ki := 0;
    WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND
          (line[i] # '=') AND (line[i] # ' ') AND
          (line[i] # CHR(9)) AND (ki < 63) DO
      key[ki] := line[i];
      INC(ki); INC(i)
    END;
    key[ki] := CHR(0);

    IF (i > HIGH(line)) OR (ORD(line[i]) = 0) OR (line[i] # '=') THEN
      (* no = sign — skip this token *)
      WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND
            (line[i] # ' ') AND (line[i] # CHR(9)) DO
        INC(i)
      END
    ELSE
      (* skip = *)
      INC(i);
      (* read value *)
      vi := 0;
      IF (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND (line[i] = '"') THEN
        (* quoted value *)
        INC(i);
        WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND
              (line[i] # '"') AND (vi < 255) DO
          valBuf[vi] := line[i];
          INC(vi); INC(i)
        END;
        IF (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND (line[i] = '"') THEN
          INC(i)
        END
      ELSE
        (* unquoted value *)
        WHILE (i <= HIGH(line)) AND (ORD(line[i]) # 0) AND
              (line[i] # ' ') AND (line[i] # CHR(9)) AND (vi < 255) DO
          valBuf[vi] := line[i];
          INC(vi); INC(i)
        END
      END;
      valBuf[vi] := CHR(0);

      IF ki > 0 THEN
        MakeSmartVal(valBuf, val);
        IF NOT SetField(outEvt^, key, val) THEN END
      END
    END
  END;

  outItem := ADDRESS(outEvt)
END ParseKvTransform;

(* ── Lines ─────────────────────────────────────────── *)

PROCEDURE LinesTransform(userData: ADDRESS; inItem: ADDRESS;
                         VAR outItem: ADDRESS);
VAR
  inEvt:  EventPtr;
  outEvt: EventPtr;
  val:    Value;
  found:  BOOLEAN;
BEGIN
  inEvt := inItem;
  found := GetField(inEvt^, "_line", val);
  IF (NOT found) OR (val.kind # VkStr) THEN
    outItem := inItem;
    RETURN
  END;
  outEvt := NewEvent();
  InitEvent(outEvt^);
  IF NOT SetField(outEvt^, "line", val) THEN END;
  outItem := ADDRESS(outEvt)
END LinesTransform;

(* ── Filter ──────────────────────────────────────── *)

PROCEDURE FilterPred(userData: ADDRESS; item: ADDRESS): BOOLEAN;
VAR
  data:   POINTER TO FilterData;
  evt:    EventPtr;
  result: BOOLEAN;
  ok:     BOOLEAN;
BEGIN
  data := userData;
  evt := item;
  EvalBool(data^.expr, evt^, result, ok);
  IF NOT ok THEN RETURN FALSE END;
  RETURN result
END FilterPred;

(* ── Map/Project ─────────────────────────────────── *)

PROCEDURE MapTransform(userData: ADDRESS; inItem: ADDRESS;
                       VAR outItem: ADDRESS);
VAR
  data:   POINTER TO MapData;
  stg:    SP;
  inEvt:  EventPtr;
  outEvt: EventPtr;
  val:    Value;
  ok:     BOOLEAN;
  i:      CARDINAL;
  found:  BOOLEAN;
BEGIN
  data := userData;
  stg := data^.stage;
  inEvt := inItem;
  outEvt := NewEvent();

  i := 0;
  WHILE i < stg^.numFields DO
    IF stg^.fields[i].hasExpr THEN
      Eval(stg^.fields[i].expr, inEvt^, val, ok);
      IF ok THEN
        IF NOT SetField(outEvt^, stg^.fields[i].name, val) THEN END
      END
    ELSE
      found := GetField(inEvt^, stg^.fields[i].name, val);
      IF found THEN
        IF NOT SetField(outEvt^, stg^.fields[i].name, val) THEN END
      ELSE
        MakeNull(val);
        IF NOT SetField(outEvt^, stg^.fields[i].name, val) THEN END
      END
    END;
    INC(i)
  END;

  outItem := ADDRESS(outEvt)
END MapTransform;

(* ── Count ───────────────────────────────────────── *)

PROCEDURE CountReduce(userData: ADDRESS; acc: ADDRESS;
                      item: ADDRESS; VAR newAcc: ADDRESS);
VAR
  data:   POINTER TO CountData;
  outEvt: EventPtr;
  val:    Value;
BEGIN
  data := userData;
  INC(data^.count);
  outEvt := NewEvent();
  MakeInt(data^.count, val);
  IF NOT SetField(outEvt^, "count", val) THEN END;
  newAcc := ADDRESS(outEvt)
END CountReduce;

(* ── Count By ────────────────────────────────────── *)

PROCEDURE CountByReduce(userData: ADDRESS; acc: ADDRESS;
                        item: ADDRESS; VAR newAcc: ADDRESS);
VAR
  data:     POINTER TO CountByData;
  inEvt:    EventPtr;
  accEvt:   EventPtr;
  val, cnt: Value;
  key:      ARRAY [0..63] OF CHAR;
  found:    BOOLEAN;
  curCount: INTEGER;
BEGIN
  data := userData;
  inEvt := item;

  IF acc = NIL THEN
    accEvt := NewEvent()
  ELSE
    accEvt := acc
  END;

  found := GetField(inEvt^, data^.fieldName, val);
  IF found AND (val.kind = VkStr) THEN
    Assign(val.strVal, key)
  ELSIF found AND (val.kind = VkInt) THEN
    Format(val, key)
  ELSE
    Assign("(unknown)", key)
  END;

  found := GetField(accEvt^, key, cnt);
  IF found AND (cnt.kind = VkInt) THEN
    curCount := cnt.intVal + 1
  ELSE
    curCount := 1
  END;
  MakeInt(curCount, cnt);
  IF NOT SetField(accEvt^, key, cnt) THEN END;

  newAcc := ADDRESS(accEvt)
END CountByReduce;

(* ── Batch ───────────────────────────────────────── *)

PROCEDURE BatchPassthrough(userData: ADDRESS; inBuf: ADDRESS;
                           inCount: CARDINAL; outBuf: ADDRESS;
                           VAR outCount: CARDINAL);
VAR
  i: CARDINAL;
  inArr, outArr: POINTER TO ARRAY [0..63] OF ADDRESS;
BEGIN
  inArr := inBuf;
  outArr := outBuf;
  i := 0;
  WHILE i < inCount DO
    outArr^[i] := inArr^[i];
    INC(i)
  END;
  outCount := inCount
END BatchPassthrough;

(* ── Sink ────────────────────────────────────────── *)

PROCEDURE SinkConsume(userData: ADDRESS; item: ADDRESS);
VAR
  data: POINTER TO SinkData;
  evt:  EventPtr;
  buf:  ARRAY [0..MaxLineBuf] OF CHAR;
  len:  CARDINAL;
  nl:   ARRAY [0..0] OF CHAR;
BEGIN
  data := userData;
  evt := item;
  FormatJson(evt^, buf);
  len := Length(buf);

  IF data^.isStdout THEN
    WriteString(buf);
    WriteLn
  ELSE
    WriteBytes(data^.fh, buf, len);
    nl[0] := CHR(10);
    WriteBytes(data^.fh, nl, 1)
  END
END SinkConsume;

(* ── Lifecycle ──────────────────────────────────── *)

PROCEDURE OpenFileSource(VAR data: FileSourceData): BOOLEAN;
BEGIN
  IF data.isStdin THEN
    data.fh := 0;
    data.done := FALSE;
    RETURN TRUE
  END;
  OpenRead(data.path, data.fh);
  data.done := FALSE;
  RETURN data.fh # 0
END OpenFileSource;

PROCEDURE CloseFileSource(VAR data: FileSourceData);
BEGIN
  IF (NOT data.isStdin) AND (data.fh # 0) THEN
    Close(data.fh)
  END
END CloseFileSource;

PROCEDURE OpenFileSink(VAR data: SinkData): BOOLEAN;
BEGIN
  IF data.isStdout THEN
    data.fh := 0;
    RETURN TRUE
  END;
  OpenWrite(data.path, data.fh);
  RETURN data.fh # 0
END OpenFileSink;

PROCEDURE CloseFileSink(VAR data: SinkData);
BEGIN
  IF (NOT data.isStdout) AND (data.fh # 0) THEN
    Close(data.fh)
  END
END CloseFileSink;

END Runtime.
