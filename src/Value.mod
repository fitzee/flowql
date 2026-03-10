IMPLEMENTATION MODULE Value;

FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM SYSTEM IMPORT TSIZE;
FROM Strings IMPORT Assign, Length;
FROM InOut IMPORT WriteString;

PROCEDURE MakeInt(n: INTEGER; VAR v: Value);
BEGIN
  v.kind := VkInt;
  v.intVal := n;
  v.realVal := 0.0;
  v.boolVal := FALSE;
  v.strVal[0] := CHR(0)
END MakeInt;

PROCEDURE MakeReal(r: REAL; VAR v: Value);
BEGIN
  v.kind := VkReal;
  v.intVal := 0;
  v.realVal := r;
  v.boolVal := FALSE;
  v.strVal[0] := CHR(0)
END MakeReal;

PROCEDURE MakeBool(b: BOOLEAN; VAR v: Value);
BEGIN
  v.kind := VkBool;
  v.intVal := 0;
  v.realVal := 0.0;
  v.boolVal := b;
  v.strVal[0] := CHR(0)
END MakeBool;

PROCEDURE MakeStr(VAR s: ARRAY OF CHAR; VAR v: Value);
BEGIN
  v.kind := VkStr;
  v.intVal := 0;
  v.realVal := 0.0;
  v.boolVal := FALSE;
  Assign(s, v.strVal)
END MakeStr;

PROCEDURE MakeNull(VAR v: Value);
BEGIN
  v.kind := VkNull;
  v.intVal := 0;
  v.realVal := 0.0;
  v.boolVal := FALSE;
  v.strVal[0] := CHR(0)
END MakeNull;

PROCEDURE NewValue(): ValuePtr;
VAR p: ValuePtr;
BEGIN
  ALLOCATE(p, TSIZE(Value));
  MakeNull(p^);
  RETURN p
END NewValue;

PROCEDURE FreeValue(VAR p: ValuePtr);
BEGIN
  IF p # NIL THEN
    DEALLOCATE(p, TSIZE(Value));
    p := NIL
  END
END FreeValue;

PROCEDURE Compare(VAR a, b: Value): INTEGER;
VAR cmpI: INTEGER;
BEGIN
  IF (a.kind = VkNull) AND (b.kind = VkNull) THEN RETURN 0 END;
  IF a.kind = VkNull THEN RETURN -1 END;
  IF b.kind = VkNull THEN RETURN 1 END;

  IF (a.kind = VkInt) AND (b.kind = VkInt) THEN
    IF a.intVal < b.intVal THEN RETURN -1
    ELSIF a.intVal > b.intVal THEN RETURN 1
    ELSE RETURN 0
    END
  END;

  IF (a.kind = VkReal) AND (b.kind = VkReal) THEN
    IF a.realVal < b.realVal THEN RETURN -1
    ELSIF a.realVal > b.realVal THEN RETURN 1
    ELSE RETURN 0
    END
  END;

  (* Mixed int/real *)
  IF (a.kind = VkInt) AND (b.kind = VkReal) THEN
    IF FLOAT(a.intVal) < b.realVal THEN RETURN -1
    ELSIF FLOAT(a.intVal) > b.realVal THEN RETURN 1
    ELSE RETURN 0
    END
  END;
  IF (a.kind = VkReal) AND (b.kind = VkInt) THEN
    IF a.realVal < FLOAT(b.intVal) THEN RETURN -1
    ELSIF a.realVal > FLOAT(b.intVal) THEN RETURN 1
    ELSE RETURN 0
    END
  END;

  IF (a.kind = VkBool) AND (b.kind = VkBool) THEN
    IF a.boolVal = b.boolVal THEN RETURN 0
    ELSIF a.boolVal THEN RETURN 1
    ELSE RETURN -1
    END
  END;

  IF (a.kind = VkStr) AND (b.kind = VkStr) THEN
    RETURN StrCompare(a.strVal, b.strVal)
  END;

  (* Incompatible types — compare by kind ordinal *)
  IF ORD(a.kind) < ORD(b.kind) THEN RETURN -1
  ELSIF ORD(a.kind) > ORD(b.kind) THEN RETURN 1
  ELSE RETURN 0
  END
END Compare;

PROCEDURE StrCompare(VAR a, b: ARRAY OF CHAR): INTEGER;
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE (i <= HIGH(a)) AND (i <= HIGH(b)) AND
        (ORD(a[i]) # 0) AND (ORD(b[i]) # 0) DO
    IF a[i] < b[i] THEN RETURN -1
    ELSIF a[i] > b[i] THEN RETURN 1
    END;
    INC(i)
  END;
  IF (i <= HIGH(a)) AND (ORD(a[i]) # 0) THEN RETURN 1
  ELSIF (i <= HIGH(b)) AND (ORD(b[i]) # 0) THEN RETURN -1
  ELSE RETURN 0
  END
END StrCompare;

PROCEDURE IsTruthy(VAR v: Value): BOOLEAN;
BEGIN
  CASE v.kind OF
    VkNull: RETURN FALSE
  | VkBool: RETURN v.boolVal
  | VkInt:  RETURN v.intVal # 0
  | VkReal: RETURN v.realVal # 0.0
  | VkStr:  RETURN ORD(v.strVal[0]) # 0
  END
END IsTruthy;

PROCEDURE IntToStr(n: INTEGER; VAR buf: ARRAY OF CHAR);
VAR
  tmp:  ARRAY [0..20] OF CHAR;
  i, j: CARDINAL;
  neg:  BOOLEAN;
  abs:  CARDINAL;
BEGIN
  IF n = 0 THEN
    buf[0] := '0';
    buf[1] := CHR(0);
    RETURN
  END;
  neg := n < 0;
  IF neg THEN abs := CARDINAL(-n) ELSE abs := CARDINAL(n) END;
  i := 0;
  WHILE abs > 0 DO
    tmp[i] := CHR(ORD('0') + (abs MOD 10));
    abs := abs DIV 10;
    INC(i)
  END;
  j := 0;
  IF neg THEN
    buf[0] := '-';
    j := 1
  END;
  WHILE i > 0 DO
    DEC(i);
    buf[j] := tmp[i];
    INC(j)
  END;
  buf[j] := CHR(0)
END IntToStr;

PROCEDURE Format(VAR v: Value; VAR buf: ARRAY OF CHAR);
BEGIN
  CASE v.kind OF
    VkNull: Assign("null", buf)
  | VkBool:
      IF v.boolVal THEN Assign("true", buf)
      ELSE Assign("false", buf)
      END
  | VkInt:  IntToStr(v.intVal, buf)
  | VkReal: RealToStr(v.realVal, buf)
  | VkStr:  Assign(v.strVal, buf)
  END
END Format;

PROCEDURE RealToStr(r: REAL; VAR buf: ARRAY OF CHAR);
VAR
  whole: INTEGER;
  frac:  CARDINAL;
  tmp:   ARRAY [0..20] OF CHAR;
  i, j:  CARDINAL;
BEGIN
  IF r < 0.0 THEN
    buf[0] := '-';
    r := -r;
    IntToStr(TRUNC(r), tmp);
    j := 1;
    i := 0;
    WHILE (ORD(tmp[i]) # 0) AND (j < HIGH(buf)) DO
      buf[j] := tmp[i];
      INC(i); INC(j)
    END
  ELSE
    IntToStr(TRUNC(r), tmp);
    j := 0;
    i := 0;
    WHILE (ORD(tmp[i]) # 0) AND (j < HIGH(buf)) DO
      buf[j] := tmp[i];
      INC(i); INC(j)
    END
  END;
  IF j < HIGH(buf) THEN
    buf[j] := '.';
    INC(j)
  END;
  frac := TRUNC((r - FLOAT(TRUNC(r))) * 1000.0);
  IF frac = 0 THEN
    IF j < HIGH(buf) THEN buf[j] := '0'; INC(j) END
  ELSE
    IntToStr(INTEGER(frac), tmp);
    i := 0;
    WHILE (ORD(tmp[i]) # 0) AND (j < HIGH(buf)) DO
      buf[j] := tmp[i];
      INC(i); INC(j)
    END
  END;
  buf[j] := CHR(0)
END RealToStr;

END Value.
