IMPLEMENTATION MODULE Event;

FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM SYSTEM IMPORT TSIZE;
FROM Strings IMPORT Assign, Length, Concat, CompareStr;
FROM Value IMPORT Value, ValueKind, VkInt, VkReal, VkBool, VkStr, VkNull, Format;

PROCEDURE InitEvent(VAR e: Event);
BEGIN
  e.numFields := 0
END InitEvent;

PROCEDURE FindField(VAR e: Event; VAR name: ARRAY OF CHAR): INTEGER;
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE i < e.numFields DO
    IF CompareStr(e.fields[i].name, name) = 0 THEN
      RETURN INTEGER(i)
    END;
    INC(i)
  END;
  RETURN -1
END FindField;

PROCEDURE SetField(VAR e: Event; VAR name: ARRAY OF CHAR; VAR v: Value): BOOLEAN;
VAR idx: INTEGER;
BEGIN
  idx := FindField(e, name);
  IF idx >= 0 THEN
    e.fields[idx].val := v;
    RETURN TRUE
  END;
  IF e.numFields >= MaxEventFields THEN
    RETURN FALSE
  END;
  Assign(name, e.fields[e.numFields].name);
  e.fields[e.numFields].val := v;
  INC(e.numFields);
  RETURN TRUE
END SetField;

PROCEDURE GetField(VAR e: Event; VAR name: ARRAY OF CHAR; VAR v: Value): BOOLEAN;
VAR idx: INTEGER;
BEGIN
  idx := FindField(e, name);
  IF idx >= 0 THEN
    v := e.fields[idx].val;
    RETURN TRUE
  END;
  RETURN FALSE
END GetField;

PROCEDURE HasField(VAR e: Event; VAR name: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN FindField(e, name) >= 0
END HasField;

PROCEDURE NewEvent(): EventPtr;
VAR p: EventPtr;
BEGIN
  ALLOCATE(p, TSIZE(Event));
  InitEvent(p^);
  RETURN p
END NewEvent;

PROCEDURE FreeEvent(VAR p: EventPtr);
BEGIN
  IF p # NIL THEN
    DEALLOCATE(p, TSIZE(Event));
    p := NIL
  END
END FreeEvent;

PROCEDURE CopyEvent(VAR src, dst: Event);
VAR i: CARDINAL;
BEGIN
  dst.numFields := src.numFields;
  i := 0;
  WHILE i < src.numFields DO
    Assign(src.fields[i].name, dst.fields[i].name);
    dst.fields[i].val := src.fields[i].val;
    INC(i)
  END
END CopyEvent;

PROCEDURE EscapeJsonStr(VAR s: ARRAY OF CHAR; VAR buf: ARRAY OF CHAR;
                        VAR pos: CARDINAL);
VAR i: CARDINAL;
BEGIN
  IF pos < HIGH(buf) THEN buf[pos] := '"'; INC(pos) END;
  i := 0;
  WHILE (i <= HIGH(s)) AND (ORD(s[i]) # 0) AND (pos < HIGH(buf) - 1) DO
    IF s[i] = '"' THEN
      IF pos < HIGH(buf) - 1 THEN buf[pos] := '\'; INC(pos) END;
      IF pos < HIGH(buf) THEN buf[pos] := '"'; INC(pos) END
    ELSIF s[i] = '\' THEN
      IF pos < HIGH(buf) - 1 THEN buf[pos] := '\'; INC(pos) END;
      IF pos < HIGH(buf) THEN buf[pos] := '\'; INC(pos) END
    ELSE
      buf[pos] := s[i]; INC(pos)
    END;
    INC(i)
  END;
  IF pos < HIGH(buf) THEN buf[pos] := '"'; INC(pos) END
END EscapeJsonStr;

PROCEDURE AppendStr(VAR src: ARRAY OF CHAR; VAR buf: ARRAY OF CHAR;
                    VAR pos: CARDINAL);
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE (i <= HIGH(src)) AND (ORD(src[i]) # 0) AND (pos < HIGH(buf)) DO
    buf[pos] := src[i];
    INC(pos);
    INC(i)
  END
END AppendStr;

PROCEDURE FormatJson(VAR e: Event; VAR buf: ARRAY OF CHAR);
VAR
  i:    CARDINAL;
  pos:  CARDINAL;
  vBuf: ARRAY [0..255] OF CHAR;
BEGIN
  pos := 0;
  IF pos < HIGH(buf) THEN buf[pos] := '{'; INC(pos) END;

  i := 0;
  WHILE i < e.numFields DO
    IF i > 0 THEN
      IF pos < HIGH(buf) THEN buf[pos] := ','; INC(pos) END
    END;
    EscapeJsonStr(e.fields[i].name, buf, pos);
    IF pos < HIGH(buf) THEN buf[pos] := ':'; INC(pos) END;

    CASE e.fields[i].val.kind OF
      VkStr:
        EscapeJsonStr(e.fields[i].val.strVal, buf, pos)
    | VkNull:
        AppendStr("null", buf, pos)
    | VkBool:
        IF e.fields[i].val.boolVal THEN
          AppendStr("true", buf, pos)
        ELSE
          AppendStr("false", buf, pos)
        END
    | VkInt:
        Format(e.fields[i].val, vBuf);
        AppendStr(vBuf, buf, pos)
    | VkReal:
        Format(e.fields[i].val, vBuf);
        AppendStr(vBuf, buf, pos)
    END;
    INC(i)
  END;

  IF pos < HIGH(buf) THEN buf[pos] := '}'; INC(pos) END;
  buf[pos] := CHR(0)
END FormatJson;

END Event.
