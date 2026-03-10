IMPLEMENTATION MODULE ExprEval;

FROM Ast IMPORT ExprPtr, Expr, ExprKind,
     EkIntLit, EkRealLit, EkStrLit, EkBoolLit, EkNullLit,
     EkFieldRef, EkBinOp, EkUnaryOp, EkParen,
     BinOpKind, BopEq, BopNeq, BopGt, BopGe, BopLt, BopLe,
     BopAdd, BopSub, BopMul, BopDiv, BopAnd, BopOr, BopContains,
     UnaryOpKind, UopNot, UopNeg;
FROM Strings IMPORT Length;
FROM Event IMPORT Event, GetField;
FROM Value IMPORT Value, ValueKind,
     VkInt, VkReal, VkBool, VkStr, VkNull,
     MakeInt, MakeReal, MakeBool, MakeStr, MakeNull,
     Compare, IsTruthy;

TYPE
  EP = POINTER TO Expr;

(* Brute-force substring search: does haystack contain needle? *)
PROCEDURE StrContains(VAR haystack, needle: ARRAY OF CHAR): BOOLEAN;
VAR
  hLen, nLen, i, j: CARDINAL;
  matched: BOOLEAN;
BEGIN
  hLen := Length(haystack);
  nLen := Length(needle);
  IF nLen = 0 THEN RETURN TRUE END;
  IF nLen > hLen THEN RETURN FALSE END;
  i := 0;
  WHILE i <= hLen - nLen DO
    matched := TRUE;
    j := 0;
    WHILE j < nLen DO
      IF haystack[i + j] # needle[j] THEN
        matched := FALSE;
        j := nLen  (* break *)
      ELSE
        INC(j)
      END
    END;
    IF matched THEN RETURN TRUE END;
    INC(i)
  END;
  RETURN FALSE
END StrContains;

PROCEDURE EvalAdd(VAR a, b: Value; VAR result: Value; VAR ok: BOOLEAN);
BEGIN
  IF (a.kind = VkInt) AND (b.kind = VkInt) THEN
    MakeInt(a.intVal + b.intVal, result)
  ELSIF (a.kind = VkReal) AND (b.kind = VkReal) THEN
    MakeReal(a.realVal + b.realVal, result)
  ELSIF (a.kind = VkInt) AND (b.kind = VkReal) THEN
    MakeReal(FLOAT(a.intVal) + b.realVal, result)
  ELSIF (a.kind = VkReal) AND (b.kind = VkInt) THEN
    MakeReal(a.realVal + FLOAT(b.intVal), result)
  ELSE
    ok := FALSE;
    MakeNull(result)
  END
END EvalAdd;

PROCEDURE EvalSub(VAR a, b: Value; VAR result: Value; VAR ok: BOOLEAN);
BEGIN
  IF (a.kind = VkInt) AND (b.kind = VkInt) THEN
    MakeInt(a.intVal - b.intVal, result)
  ELSIF (a.kind = VkReal) AND (b.kind = VkReal) THEN
    MakeReal(a.realVal - b.realVal, result)
  ELSIF (a.kind = VkInt) AND (b.kind = VkReal) THEN
    MakeReal(FLOAT(a.intVal) - b.realVal, result)
  ELSIF (a.kind = VkReal) AND (b.kind = VkInt) THEN
    MakeReal(a.realVal - FLOAT(b.intVal), result)
  ELSE
    ok := FALSE;
    MakeNull(result)
  END
END EvalSub;

PROCEDURE EvalMul(VAR a, b: Value; VAR result: Value; VAR ok: BOOLEAN);
BEGIN
  IF (a.kind = VkInt) AND (b.kind = VkInt) THEN
    MakeInt(a.intVal * b.intVal, result)
  ELSIF (a.kind = VkReal) AND (b.kind = VkReal) THEN
    MakeReal(a.realVal * b.realVal, result)
  ELSIF (a.kind = VkInt) AND (b.kind = VkReal) THEN
    MakeReal(FLOAT(a.intVal) * b.realVal, result)
  ELSIF (a.kind = VkReal) AND (b.kind = VkInt) THEN
    MakeReal(a.realVal * FLOAT(b.intVal), result)
  ELSE
    ok := FALSE;
    MakeNull(result)
  END
END EvalMul;

PROCEDURE EvalDiv(VAR a, b: Value; VAR result: Value; VAR ok: BOOLEAN);
BEGIN
  IF (b.kind = VkInt) AND (b.intVal = 0) THEN
    ok := FALSE;
    MakeNull(result);
    RETURN
  END;
  IF (b.kind = VkReal) AND (b.realVal = 0.0) THEN
    ok := FALSE;
    MakeNull(result);
    RETURN
  END;
  IF (a.kind = VkInt) AND (b.kind = VkInt) THEN
    MakeInt(a.intVal DIV b.intVal, result)
  ELSIF (a.kind = VkReal) AND (b.kind = VkReal) THEN
    MakeReal(a.realVal / b.realVal, result)
  ELSIF (a.kind = VkInt) AND (b.kind = VkReal) THEN
    MakeReal(FLOAT(a.intVal) / b.realVal, result)
  ELSIF (a.kind = VkReal) AND (b.kind = VkInt) THEN
    MakeReal(a.realVal / FLOAT(b.intVal), result)
  ELSE
    ok := FALSE;
    MakeNull(result)
  END
END EvalDiv;

PROCEDURE Eval(e: ExprPtr; VAR evt: Event; VAR val: Value; VAR ok: BOOLEAN);
VAR
  ep:          EP;
  left, right: Value;
  cmp:         INTEGER;
  found:       BOOLEAN;
BEGIN
  ok := TRUE;
  IF e = NIL THEN
    MakeNull(val);
    ok := FALSE;
    RETURN
  END;

  ep := EP(e);

  CASE ep^.kind OF
    EkIntLit:
      MakeInt(ep^.intVal, val)

  | EkRealLit:
      MakeReal(ep^.realVal, val)

  | EkStrLit:
      MakeStr(ep^.strVal, val)

  | EkBoolLit:
      MakeBool(ep^.boolVal, val)

  | EkNullLit:
      MakeNull(val)

  | EkFieldRef:
      found := GetField(evt, ep^.fieldName, val);
      IF NOT found THEN
        MakeNull(val)
      END

  | EkParen:
      Eval(ep^.operand, evt, val, ok)

  | EkUnaryOp:
      Eval(ep^.operand, evt, left, ok);
      IF NOT ok THEN RETURN END;
      CASE ep^.unaryOp OF
        UopNot:
          MakeBool(NOT IsTruthy(left), val)
      | UopNeg:
          IF left.kind = VkInt THEN
            MakeInt(-left.intVal, val)
          ELSIF left.kind = VkReal THEN
            MakeReal(-left.realVal, val)
          ELSE
            ok := FALSE;
            MakeNull(val)
          END
      END

  | EkBinOp:
      Eval(ep^.left, evt, left, ok);
      IF NOT ok THEN RETURN END;

      IF ep^.binOp = BopAnd THEN
        IF NOT IsTruthy(left) THEN
          MakeBool(FALSE, val);
          RETURN
        END;
        Eval(ep^.right, evt, right, ok);
        IF NOT ok THEN RETURN END;
        MakeBool(IsTruthy(right), val);
        RETURN
      END;

      IF ep^.binOp = BopOr THEN
        IF IsTruthy(left) THEN
          MakeBool(TRUE, val);
          RETURN
        END;
        Eval(ep^.right, evt, right, ok);
        IF NOT ok THEN RETURN END;
        MakeBool(IsTruthy(right), val);
        RETURN
      END;

      Eval(ep^.right, evt, right, ok);
      IF NOT ok THEN RETURN END;

      CASE ep^.binOp OF
        BopEq:
          cmp := Compare(left, right);
          MakeBool(cmp = 0, val)
      | BopNeq:
          cmp := Compare(left, right);
          MakeBool(cmp # 0, val)
      | BopGt:
          cmp := Compare(left, right);
          MakeBool(cmp > 0, val)
      | BopGe:
          cmp := Compare(left, right);
          MakeBool(cmp >= 0, val)
      | BopLt:
          cmp := Compare(left, right);
          MakeBool(cmp < 0, val)
      | BopLe:
          cmp := Compare(left, right);
          MakeBool(cmp <= 0, val)
      | BopAdd:
          EvalAdd(left, right, val, ok)
      | BopSub:
          EvalSub(left, right, val, ok)
      | BopMul:
          EvalMul(left, right, val, ok)
      | BopDiv:
          EvalDiv(left, right, val, ok)
      | BopAnd:
          MakeBool(IsTruthy(left) AND IsTruthy(right), val)
      | BopOr:
          MakeBool(IsTruthy(left) OR IsTruthy(right), val)
      | BopContains:
          IF (left.kind = VkStr) AND (right.kind = VkStr) THEN
            MakeBool(StrContains(left.strVal, right.strVal), val)
          ELSE
            ok := FALSE;
            MakeNull(val)
          END
      END
  END
END Eval;

PROCEDURE EvalBool(e: ExprPtr; VAR evt: Event; VAR result: BOOLEAN;
                   VAR ok: BOOLEAN);
VAR val: Value;
BEGIN
  Eval(e, evt, val, ok);
  IF ok THEN
    result := IsTruthy(val)
  ELSE
    result := FALSE
  END
END EvalBool;

END ExprEval.
