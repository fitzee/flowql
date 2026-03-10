IMPLEMENTATION MODULE Ast;

FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM SYSTEM IMPORT TSIZE, ADDRESS;

TYPE
  EP = POINTER TO Expr;

PROCEDURE InitPipeline(VAR p: Pipeline);
BEGIN
  p.numStages := 0;
  p.hasSource := FALSE;
  p.hasSink := FALSE;
  p.source.path[0] := CHR(0);
  p.sink.path[0] := CHR(0)
END InitPipeline;

PROCEDURE NewExpr(): ExprPtr;
VAR e: EP;
BEGIN
  ALLOCATE(e, TSIZE(Expr));
  e^.kind := EkNullLit;
  e^.intVal := 0;
  e^.realVal := 0.0;
  e^.strVal[0] := CHR(0);
  e^.boolVal := FALSE;
  e^.fieldName[0] := CHR(0);
  e^.left := NIL;
  e^.right := NIL;
  e^.operand := NIL;
  e^.line := 0;
  e^.col := 0;
  RETURN ExprPtr(e)
END NewExpr;

PROCEDURE FreeExpr(VAR e: ExprPtr);
VAR ep: EP;
BEGIN
  IF e # NIL THEN
    ep := EP(e);
    FreeExpr(ep^.left);
    FreeExpr(ep^.right);
    FreeExpr(ep^.operand);
    DEALLOCATE(ep, TSIZE(Expr));
    e := NIL
  END
END FreeExpr;

PROCEDURE AsExpr(e: ExprPtr): ADDRESS;
BEGIN
  RETURN e
END AsExpr;

END Ast.
