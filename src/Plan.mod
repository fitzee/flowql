IMPLEMENTATION MODULE Plan;

FROM SYSTEM IMPORT ADDRESS;
FROM Ast IMPORT Pipeline, Source, Sink, Stage, StageKind,
     SourceKind, SinkKind, Expr, ExprKind, BinOpKind, UnaryOpKind,
     SkFile, SkStdin, SkLines,
     SkStdout, SkSinkFile,
     StFilter, StMap, StProject, StParseJson, StParseCsv,
     StParseTsv, StParseKv, StLines,
     StCount, StCountBy, StBatch, StWindow,
     HeaderMode, HmDefault, HmHeader, HmNoheader,
     ExprPtr,
     EkIntLit, EkRealLit, EkStrLit, EkBoolLit, EkNullLit,
     EkFieldRef, EkBinOp, EkUnaryOp, EkParen,
     BopEq, BopNeq, BopGt, BopGe, BopLt, BopLe,
     BopAdd, BopSub, BopMul, BopDiv, BopAnd, BopOr, BopContains,
     UopNot, UopNeg;
FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM Strings IMPORT Length;

CONST
  ChanCap = 8;
  MultiLineThreshold = 3;

TYPE
  EP = POINTER TO Expr;

(* ── Expression printer ─────────────────────────── *)

PROCEDURE PrintExpr(e: ExprPtr);
VAR ep: EP;
BEGIN
  IF e = NIL THEN
    WriteString("?");
    RETURN
  END;
  ep := EP(e);
  CASE ep^.kind OF
    EkIntLit:
      WriteInt(ep^.intVal, 0)
  | EkRealLit:
      WriteString("<real>")
  | EkStrLit:
      WriteString('"');
      WriteString(ep^.strVal);
      WriteString('"')
  | EkBoolLit:
      IF ep^.boolVal THEN
        WriteString("true")
      ELSE
        WriteString("false")
      END
  | EkNullLit:
      WriteString("null")
  | EkFieldRef:
      WriteString(ep^.fieldName)
  | EkBinOp:
      PrintExpr(ep^.left);
      CASE ep^.binOp OF
        BopEq:  WriteString(" = ")
      | BopNeq: WriteString(" != ")
      | BopGt:  WriteString(" > ")
      | BopGe:  WriteString(" >= ")
      | BopLt:  WriteString(" < ")
      | BopLe:  WriteString(" <= ")
      | BopAdd: WriteString(" + ")
      | BopSub: WriteString(" - ")
      | BopMul: WriteString(" * ")
      | BopDiv: WriteString(" / ")
      | BopAnd: WriteString(" and ")
      | BopOr:  WriteString(" or ")
      | BopContains: WriteString(" contains ")
      END;
      PrintExpr(ep^.right)
  | EkUnaryOp:
      CASE ep^.unaryOp OF
        UopNot: WriteString("not ")
      | UopNeg: WriteString("-")
      END;
      PrintExpr(ep^.operand)
  | EkParen:
      WriteString("(");
      PrintExpr(ep^.operand);
      WriteString(")")
  END
END PrintExpr;

(* ── Short stage name ────────────────────────────── *)

PROCEDURE WriteStageName(VAR stg: Stage);
BEGIN
  CASE stg.kind OF
    StParseJson: WriteString("ParseJSON")
  | StParseCsv:  WriteString("ParseCSV")
  | StParseTsv:  WriteString("ParseTSV")
  | StParseKv:   WriteString("ParseKV")
  | StLines:     WriteString("Lines")
  | StFilter:    WriteString("Filter")
  | StMap:       WriteString("Map")
  | StProject:   WriteString("Project")
  | StCount:     WriteString("Count")
  | StCountBy:   WriteString("CountBy")
  | StBatch:     WriteString("Batch")
  | StWindow:    WriteString("Window")
  END
END WriteStageName;

PROCEDURE WriteSourceName(VAR src: Source);
BEGIN
  WriteString("Source(");
  CASE src.kind OF
    SkFile:  WriteString("file")
  | SkStdin: WriteString("stdin")
  | SkLines: WriteString("lines")
  END;
  WriteString(")")
END WriteSourceName;

PROCEDURE WriteSinkName(VAR snk: Sink);
BEGIN
  WriteString("Sink(");
  CASE snk.kind OF
    SkStdout:   WriteString("stdout")
  | SkSinkFile: WriteString("file")
  END;
  WriteString(")")
END WriteSinkName;

(* ── Full node display ───────────────────────────── *)

PROCEDURE PrintSourceNode(VAR src: Source);
BEGIN
  WriteString("Source(");
  CASE src.kind OF
    SkFile:
      WriteString('file, "');
      WriteString(src.path);
      WriteString('"')
  | SkStdin:
      WriteString("stdin")
  | SkLines:
      WriteString('lines, "');
      WriteString(src.path);
      WriteString('"')
  END;
  WriteString(")")
END PrintSourceNode;

PROCEDURE PrintSinkNode(VAR snk: Sink);
BEGIN
  WriteString("Sink(");
  CASE snk.kind OF
    SkStdout:
      WriteString("stdout")
  | SkSinkFile:
      WriteString('file, "');
      WriteString(snk.path);
      WriteString('"')
  END;
  WriteString(")")
END PrintSinkNode;

PROCEDURE PrintFieldInline(VAR stg: Stage; idx: CARDINAL);
BEGIN
  WriteString(stg.fields[idx].name);
  IF stg.fields[idx].hasExpr THEN
    WriteString(" = ");
    PrintExpr(stg.fields[idx].expr)
  END
END PrintFieldInline;

PROCEDURE PrintStageNode(VAR stg: Stage);
VAR i: CARDINAL;
BEGIN
  CASE stg.kind OF
    StParseJson:
      WriteString("ParseJSON")
  | StParseCsv:
      WriteString("ParseCSV");
      IF stg.hdrMode = HmNoheader THEN
        WriteString(" noheader")
      ELSIF stg.hdrMode = HmHeader THEN
        WriteString(" header")
      END
  | StParseTsv:
      WriteString("ParseTSV");
      IF stg.hdrMode = HmNoheader THEN
        WriteString(" noheader")
      ELSIF stg.hdrMode = HmHeader THEN
        WriteString(" header")
      END
  | StParseKv:
      WriteString("ParseKV")
  | StLines:
      WriteString("Lines")
  | StFilter:
      WriteString("Filter(");
      PrintExpr(stg.filterExpr);
      WriteString(")")
  | StMap:
      IF stg.numFields > MultiLineThreshold THEN
        WriteString("Map {");
        WriteLn;
        i := 0;
        WHILE i < stg.numFields DO
          WriteString("          ");
          PrintFieldInline(stg, i);
          IF i < stg.numFields - 1 THEN
            WriteString(",")
          END;
          WriteLn;
          INC(i)
        END;
        WriteString("        }")
      ELSE
        WriteString("Map{");
        i := 0;
        WHILE i < stg.numFields DO
          IF i > 0 THEN WriteString(", ") END;
          PrintFieldInline(stg, i);
          INC(i)
        END;
        WriteString("}")
      END
  | StProject:
      IF stg.numFields > MultiLineThreshold THEN
        WriteString("Project {");
        WriteLn;
        i := 0;
        WHILE i < stg.numFields DO
          WriteString("          ");
          WriteString(stg.fields[i].name);
          IF i < stg.numFields - 1 THEN
            WriteString(",")
          END;
          WriteLn;
          INC(i)
        END;
        WriteString("        }")
      ELSE
        WriteString("Project{");
        i := 0;
        WHILE i < stg.numFields DO
          IF i > 0 THEN WriteString(", ") END;
          WriteString(stg.fields[i].name);
          INC(i)
        END;
        WriteString("}")
      END
  | StCount:
      WriteString("Count")
  | StCountBy:
      WriteString("CountBy(");
      WriteString(stg.groupField);
      WriteString(")")
  | StBatch:
      WriteString("Batch(");
      WriteCard(stg.size, 0);
      WriteString(")")
  | StWindow:
      WriteString("Window(");
      WriteCard(stg.size, 0);
      WriteString(")")
  END
END PrintStageNode;

(* ── Stage kind tag ──────────────────────────────── *)

PROCEDURE WriteStageKindTag(VAR stg: Stage);
BEGIN
  CASE stg.kind OF
    StParseJson:  WriteString("  [standard, parser]")
  | StParseCsv:   WriteString("  [standard, parser]")
  | StParseTsv:   WriteString("  [standard, parser]")
  | StParseKv:    WriteString("  [standard, parser]")
  | StLines:      WriteString("  [standard, transform]")
  | StFilter:     WriteString("  [expr-eval, predicate]")
  | StMap:        WriteString("  [expr-eval, transform]")
  | StProject:    WriteString("  [standard, projection]")
  | StCount:      WriteString("  [aggregate, accumulator]")
  | StCountBy:    WriteString("  [aggregate, hash-group]")
  | StBatch:      WriteString("  [standard, buffering]")
  | StWindow:     WriteString("  [standard, windowing]")
  END
END WriteStageKindTag;

PROCEDURE WriteFlowNetNodeName(VAR stg: Stage);
BEGIN
  CASE stg.kind OF
    StParseJson, StParseCsv, StParseTsv, StParseKv, StLines, StMap, StProject:
      WriteString("MapRun")
  | StFilter:
      WriteString("FilterRun")
  | StCount, StCountBy:
      WriteString("ReduceRun")
  | StBatch:
      WriteString("BatchRun")
  | StWindow:
      WriteString("WindowRun")
  END
END WriteFlowNetNodeName;

(* ── Stage index annotation ──────────────────────── *)

PROCEDURE WriteStageIndex(idx: CARDINAL);
BEGIN
  WriteString("  [stage ");
  WriteCard(idx, 0);
  WriteString("]")
END WriteStageIndex;

(* ════════════════════════════════════════════════════
   Default plan printer
   ════════════════════════════════════════════════════ *)

PROCEDURE PrintPlan(VAR p: Pipeline);
VAR
  i:      CARDINAL;
  nNodes: CARDINAL;
  nChans: CARDINAL;
BEGIN
  nNodes := p.numStages + 2;
  nChans := p.numStages + 1;

  WriteString("=== FlowQL Execution Plan ===");
  WriteLn;
  WriteLn;

  WriteString("Pipeline:");
  WriteLn;
  WriteLn;

  WriteString("  ");
  PrintSourceNode(p.source);
  WriteLn;

  i := 0;
  WHILE i < p.numStages DO
    WriteString("    -> ");
    PrintStageNode(p.stages[i]);
    WriteStageIndex(i + 1);
    WriteLn;
    INC(i)
  END;

  WriteString("    -> ");
  PrintSinkNode(p.sink);
  WriteLn;

  WriteLn;
  WriteString("Channels:");
  WriteLn;

  i := 0;
  WHILE i < nChans DO
    WriteString("  ch");
    WriteCard(i + 1, 0);
    WriteString("  cap=");
    WriteCard(ChanCap, 0);
    WriteString("  ");

    IF i = 0 THEN
      WriteSourceName(p.source)
    ELSE
      WriteStageName(p.stages[i - 1])
    END;

    WriteString(" -> ");

    IF i = nChans - 1 THEN
      WriteSinkName(p.sink)
    ELSE
      WriteStageName(p.stages[i])
    END;

    WriteLn;
    INC(i)
  END;

  WriteLn;
  WriteString("FlowNet mapping:");
  WriteLn;

  WriteString("  ");
  WriteSourceName(p.source);
  WriteString(" -> SourceRun  [standard, generator]");
  WriteLn;

  i := 0;
  WHILE i < p.numStages DO
    WriteString("  ");
    WriteStageName(p.stages[i]);
    WriteString(" -> ");
    WriteFlowNetNodeName(p.stages[i]);
    WriteStageKindTag(p.stages[i]);
    WriteLn;
    INC(i)
  END;

  WriteString("  ");
  WriteSinkName(p.sink);
  WriteString(" -> SinkRun  [standard, consumer]");
  WriteLn;

  WriteLn;
  WriteString("Threads: ");
  WriteCard(nNodes, 0);
  WriteString("  Channels: ");
  WriteCard(nChans, 0);
  WriteString("  Lowering: Pipe.Stage()");
  WriteLn
END PrintPlan;

(* ════════════════════════════════════════════════════
   Verbose plan printer
   ════════════════════════════════════════════════════ *)

PROCEDURE WriteSourceCtxType(VAR src: Source);
BEGIN
  WriteString("    context:  SourceCtx");
  WriteLn;
  WriteString("    userData: FileSourceData");
  WriteLn;
  WriteString("    callback: SourceGen");
  WriteLn;
  WriteString("    record:   ");
  CASE src.kind OF
    SkFile:
      WriteString('path="');
      WriteString(src.path);
      WriteString('", isStdin=false')
  | SkStdin:
      WriteString("isStdin=true")
  | SkLines:
      WriteString('path="');
      WriteString(src.path);
      WriteString('", isStdin=false')
  END;
  WriteLn;
  WriteString("    origin:   builtin (FlowNet SourceRun)");
  WriteLn
END WriteSourceCtxType;

PROCEDURE WriteSinkCtxType(VAR snk: Sink);
BEGIN
  WriteString("    context:  SinkCtx");
  WriteLn;
  WriteString("    userData: SinkData");
  WriteLn;
  WriteString("    callback: SinkConsume");
  WriteLn;
  WriteString("    record:   ");
  CASE snk.kind OF
    SkStdout:
      WriteString("isStdout=true")
  | SkSinkFile:
      WriteString('path="');
      WriteString(snk.path);
      WriteString('", isStdout=false')
  END;
  WriteLn;
  WriteString("    origin:   builtin (FlowNet SinkRun)");
  WriteLn
END WriteSinkCtxType;

PROCEDURE WriteStageCtxType(VAR stg: Stage);
BEGIN
  CASE stg.kind OF
    StParseJson:
      WriteString("    context:  MapCtx");
      WriteLn;
      WriteString("    userData: nil");
      WriteLn;
      WriteString("    callback: ParseJsonTransform");
      WriteLn;
      WriteString("    origin:   FlowQL runtime (custom transform)")
  | StParseCsv:
      WriteString("    context:  MapCtx");
      WriteLn;
      WriteString("    userData: CsvParseData");
      WriteLn;
      WriteString("    callback: ParseCsvTransform");
      WriteLn;
      WriteString("    origin:   FlowQL runtime (custom transform)")
  | StParseTsv:
      WriteString("    context:  MapCtx");
      WriteLn;
      WriteString("    userData: TsvParseData");
      WriteLn;
      WriteString("    callback: ParseTsvTransform");
      WriteLn;
      WriteString("    origin:   FlowQL runtime (custom transform)")
  | StParseKv:
      WriteString("    context:  MapCtx");
      WriteLn;
      WriteString("    userData: nil");
      WriteLn;
      WriteString("    callback: ParseKvTransform");
      WriteLn;
      WriteString("    origin:   FlowQL runtime (custom transform)")
  | StLines:
      WriteString("    context:  MapCtx");
      WriteLn;
      WriteString("    userData: nil");
      WriteLn;
      WriteString("    callback: LinesTransform");
      WriteLn;
      WriteString("    origin:   FlowQL runtime (line transform)")
  | StFilter:
      WriteString("    context:  FilterCtx");
      WriteLn;
      WriteString("    userData: FilterData {expr}");
      WriteLn;
      WriteString("    callback: FilterPred");
      WriteLn;
      WriteString("    origin:   FlowQL runtime (expr-eval wrapper)")
  | StMap:
      WriteString("    context:  MapCtx");
      WriteLn;
      WriteString("    userData: MapData {stage}");
      WriteLn;
      WriteString("    callback: MapTransform");
      WriteLn;
      WriteString("    origin:   FlowQL runtime (expr-eval wrapper)")
  | StProject:
      WriteString("    context:  MapCtx");
      WriteLn;
      WriteString("    userData: MapData {stage}");
      WriteLn;
      WriteString("    callback: MapTransform");
      WriteLn;
      WriteString("    origin:   FlowQL runtime (projection wrapper)")
  | StCount:
      WriteString("    context:  ReduceCtx");
      WriteLn;
      WriteString("    userData: CountData {count}");
      WriteLn;
      WriteString("    callback: CountReduce");
      WriteLn;
      WriteString("    origin:   FlowQL runtime (aggregate)")
  | StCountBy:
      WriteString("    context:  ReduceCtx");
      WriteLn;
      WriteString("    userData: CountByData {fieldName, HashMap}");
      WriteLn;
      WriteString("    callback: CountByReduce");
      WriteLn;
      WriteString("    origin:   FlowQL runtime (hash-group aggregate)")
  | StBatch:
      WriteString("    context:  BatchCtx");
      WriteLn;
      WriteString("    userData: nil");
      WriteLn;
      WriteString("    callback: BatchPassthrough");
      WriteLn;
      WriteString("    origin:   builtin (FlowNet BatchRun)")
  | StWindow:
      WriteString("    context:  WindowCtx");
      WriteLn;
      WriteString("    userData: nil");
      WriteLn;
      WriteString("    callback: nil");
      WriteLn;
      WriteString("    origin:   builtin (FlowNet WindowRun)")
  END;
  WriteLn
END WriteStageCtxType;

PROCEDURE PrintPlanVerbose(VAR p: Pipeline);
VAR
  i:      CARDINAL;
  nNodes: CARDINAL;
  nChans: CARDINAL;
BEGIN
  nNodes := p.numStages + 2;
  nChans := p.numStages + 1;

  WriteString("=== FlowQL Execution Plan (verbose) ===");
  WriteLn;
  WriteLn;

  (* Pipeline graph — same as default but with stage indices *)
  WriteString("Pipeline:");
  WriteLn;
  WriteLn;

  WriteString("  ");
  PrintSourceNode(p.source);
  WriteLn;

  i := 0;
  WHILE i < p.numStages DO
    WriteString("    -> ");
    PrintStageNode(p.stages[i]);
    WriteStageIndex(i + 1);
    WriteLn;
    INC(i)
  END;

  WriteString("    -> ");
  PrintSinkNode(p.sink);
  WriteLn;

  (* Channels with type tags *)
  WriteLn;
  WriteString("Channels:");
  WriteLn;

  i := 0;
  WHILE i < nChans DO
    WriteString("  ch");
    WriteCard(i + 1, 0);
    WriteString("  cap=");
    WriteCard(ChanCap, 0);
    WriteString("  ");

    IF i = 0 THEN
      WriteSourceName(p.source)
    ELSE
      WriteStageName(p.stages[i - 1])
    END;

    WriteString(" -> ");

    IF i = nChans - 1 THEN
      WriteSinkName(p.sink)
    ELSE
      WriteStageName(p.stages[i])
    END;

    WriteString("  [ADDRESS -> Event*]");

    WriteLn;
    INC(i)
  END;

  (* Detailed node info *)
  WriteLn;
  WriteString("Nodes:");
  WriteLn;

  WriteLn;
  WriteString("  ");
  WriteSourceName(p.source);
  WriteString(" -> SourceRun  [standard, generator]");
  WriteLn;
  WriteSourceCtxType(p.source);

  i := 0;
  WHILE i < p.numStages DO
    WriteLn;
    WriteString("  ");
    WriteStageName(p.stages[i]);
    WriteStageIndex(i + 1);
    WriteString(" -> ");
    WriteFlowNetNodeName(p.stages[i]);
    WriteStageKindTag(p.stages[i]);
    WriteLn;
    WriteStageCtxType(p.stages[i]);
    INC(i)
  END;

  WriteLn;
  WriteString("  ");
  WriteSinkName(p.sink);
  WriteString(" -> SinkRun  [standard, consumer]");
  WriteLn;
  WriteSinkCtxType(p.sink);

  (* Summary *)
  WriteLn;
  WriteString("Threads: ");
  WriteCard(nNodes, 0);
  WriteString("  Channels: ");
  WriteCard(nChans, 0);
  WriteString("  Lowering: Pipe.Stage()");
  WriteLn
END PrintPlanVerbose;

END Plan.
