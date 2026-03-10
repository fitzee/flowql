IMPLEMENTATION MODULE Sema;

FROM Ast IMPORT Pipeline, Stage, StageKind,
     StFilter, StMap, StProject, StParseJson, StParseCsv,
     StParseTsv, StParseKv, StLines,
     StCount, StCountBy, StBatch, StWindow,
     MaxStages;
FROM Strings IMPORT Assign, Length;

PROCEDURE SetErr(VAR r: SemaResult; msg: ARRAY OF CHAR;
                 line, col: CARDINAL);
BEGIN
  IF r.ok THEN
    r.ok := FALSE;
    Assign(msg, r.errMsg);
    r.errLine := line;
    r.errCol := col
  END
END SetErr;

PROCEDURE Validate(VAR p: Pipeline; VAR result: SemaResult);
VAR
  i:             CARDINAL;
  hadParse:      BOOLEAN;
  hadAggregate:  BOOLEAN;
BEGIN
  result.ok := TRUE;
  result.errMsg[0] := CHR(0);
  result.errLine := 0;
  result.errCol := 0;

  IF NOT p.hasSource THEN
    SetErr(result, "pipeline has no source", 1, 1);
    RETURN
  END;

  (* Sink is optional — embedded use may omit it *)

  hadParse := FALSE;
  hadAggregate := FALSE;

  i := 0;
  WHILE i < p.numStages DO
    CASE p.stages[i].kind OF
      StParseJson, StParseCsv, StParseTsv, StParseKv:
        IF hadParse THEN
          SetErr(result, "multiple parse stages not allowed",
                 p.stages[i].line, p.stages[i].col);
          RETURN
        END;
        hadParse := TRUE;
        IF hadAggregate THEN
          SetErr(result, "parse stage cannot appear after aggregation",
                 p.stages[i].line, p.stages[i].col);
          RETURN
        END

    | StLines:
        (* lines is a simple transform, no special validation *)

    | StFilter:
        IF p.stages[i].filterExpr = NIL THEN
          SetErr(result, "filter requires an expression",
                 p.stages[i].line, p.stages[i].col);
          RETURN
        END

    | StMap, StProject:
        IF p.stages[i].numFields = 0 THEN
          SetErr(result, "map/project requires at least one field",
                 p.stages[i].line, p.stages[i].col);
          RETURN
        END

    | StCount, StCountBy:
        hadAggregate := TRUE

    | StBatch:
        IF p.stages[i].size = 0 THEN
          SetErr(result, "batch size must be positive",
                 p.stages[i].line, p.stages[i].col);
          RETURN
        END;
        IF p.stages[i].size > 64 THEN
          SetErr(result, "batch size exceeds FlowNet maximum (64)",
                 p.stages[i].line, p.stages[i].col);
          RETURN
        END

    | StWindow:
        IF p.stages[i].size = 0 THEN
          SetErr(result, "window size must be positive",
                 p.stages[i].line, p.stages[i].col);
          RETURN
        END;
        IF p.stages[i].size > 64 THEN
          SetErr(result, "window size exceeds FlowNet maximum (64)",
                 p.stages[i].line, p.stages[i].col);
          RETURN
        END;
        hadAggregate := TRUE
    END;
    INC(i)
  END
END Validate;

END Sema.
