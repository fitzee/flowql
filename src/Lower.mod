IMPLEMENTATION MODULE Lower;

FROM SYSTEM IMPORT ADDRESS, ADR;
FROM Strings IMPORT Assign;
FROM InOut IMPORT WriteString, WriteLn;
FROM Ast IMPORT Pipeline, Source, Sink, Stage, StageKind,
     SourceKind, SinkKind, HeaderMode, HmDefault, HmNoheader,
     SkFile, SkStdin, SkLines,
     SkStdout, SkSinkFile,
     StFilter, StMap, StProject, StParseJson, StParseCsv,
     StParseTsv, StParseKv, StLines,
     StCount, StCountBy, StBatch, StWindow;
FROM Nodes IMPORT SourceCtx, SinkCtx, MapCtx, FilterCtx,
     BatchCtx, ReduceCtx, WindowCtx, NodeError,
     SourceRun, SinkRun, MapRun, FilterRun,
     BatchRun, ReduceRun, WindowRun;
IMPORT Pipe;
FROM Runtime IMPORT FileSourceData, SinkData, FilterData, MapData,
     CountData, CountByData, CsvParseData, TsvParseData,
     SourceGen, ParseJsonTransform, ParseCsvTransform,
     ParseTsvTransform, ParseKvTransform, LinesTransform,
     FilterPred, MapTransform,
     CountReduce, CountByReduce, BatchPassthrough,
     SinkConsume,
     OpenFileSource, CloseFileSource,
     OpenFileSink, CloseFileSink;

CONST
  ChanCap = 8;
  MaxNodes = 32;

TYPE
  NodeKind = (NkSource, NkSink, NkMap, NkFilter, NkBatch, NkReduce, NkWindow);

  NodeSlot = RECORD
    kind:       NodeKind;
    srcCtx:     SourceCtx;
    sinkCtx:    SinkCtx;
    mapCtx:     MapCtx;
    filterCtx:  FilterCtx;
    batchCtx:   BatchCtx;
    reduceCtx:  ReduceCtx;
    windowCtx:  WindowCtx;
    fileSrc:    FileSourceData;
    sinkData:   SinkData;
    filterData: FilterData;
    mapData:    MapData;
    countData:  CountData;
    countByData: CountByData;
    csvData:    CsvParseData;
    tsvData:    TsvParseData;
    nodeErr:    NodeError
  END;

PROCEDURE Execute(VAR p: Pipeline; VAR result: LowerResult);
VAR
  pipe:   Pipe.Pipeline;
  nodes:  ARRAY [0..MaxNodes-1] OF NodeSlot;
  nNodes: CARDINAL;
  i:      CARDINAL;
  ok:     BOOLEAN;
BEGIN
  result.ok := TRUE;
  result.errMsg[0] := CHR(0);
  nNodes := 0;

  Pipe.Init(pipe);

  (* === Source node === *)
  nodes[0].kind := NkSource;
  nodes[0].nodeErr.hasError := FALSE;
  nodes[0].srcCtx.err := ADR(nodes[0].nodeErr);
  nodes[0].srcCtx.genFn := SourceGen;

  CASE p.source.kind OF
    SkFile, SkLines:
      Assign(p.source.path, nodes[0].fileSrc.path);
      nodes[0].fileSrc.isStdin := FALSE;
      nodes[0].fileSrc.done := FALSE;
      nodes[0].fileSrc.linePtr := NIL;
      nodes[0].fileSrc.lineCap := 0;
      nodes[0].fileSrc.lineLen := 0
  | SkStdin:
      nodes[0].fileSrc.path[0] := CHR(0);
      nodes[0].fileSrc.isStdin := TRUE;
      nodes[0].fileSrc.done := FALSE;
      nodes[0].fileSrc.linePtr := NIL;
      nodes[0].fileSrc.lineCap := 0;
      nodes[0].fileSrc.lineLen := 0
  END;

  nodes[0].srcCtx.userData := ADR(nodes[0].fileSrc);

  IF NOT OpenFileSource(nodes[0].fileSrc) THEN
    result.ok := FALSE;
    Assign("failed to open source file", result.errMsg);
    Pipe.Destroy(pipe);
    RETURN
  END;

  ok := Pipe.Stage(pipe, "source", SourceRun, ADR(nodes[0].srcCtx),
                   NIL, ADR(nodes[0].srcCtx.outCh), 0);
  IF NOT ok THEN
    result.ok := FALSE;
    Assign("failed to add source stage", result.errMsg);
    CloseFileSource(nodes[0].fileSrc);
    Pipe.Destroy(pipe);
    RETURN
  END;

  nNodes := 1;

  (* === Middle stages === *)
  i := 0;
  WHILE (i < p.numStages) AND result.ok DO
    nodes[nNodes].nodeErr.hasError := FALSE;

    CASE p.stages[i].kind OF
      StParseJson:
        nodes[nNodes].kind := NkMap;
        nodes[nNodes].mapCtx.mapFn := ParseJsonTransform;
        nodes[nNodes].mapCtx.userData := NIL;
        nodes[nNodes].mapCtx.err := ADR(nodes[nNodes].nodeErr);
        ok := Pipe.Stage(pipe, "parse_json", MapRun,
                         ADR(nodes[nNodes].mapCtx),
                         ADR(nodes[nNodes].mapCtx.inCh),
                         ADR(nodes[nNodes].mapCtx.outCh), ChanCap)

    | StParseCsv:
        nodes[nNodes].kind := NkMap;
        nodes[nNodes].csvData.hasHeader := p.stages[i].hdrMode # HmNoheader;
        nodes[nNodes].csvData.headerDone := FALSE;
        nodes[nNodes].csvData.numHeaders := 0;
        nodes[nNodes].mapCtx.mapFn := ParseCsvTransform;
        nodes[nNodes].mapCtx.userData := ADR(nodes[nNodes].csvData);
        nodes[nNodes].mapCtx.err := ADR(nodes[nNodes].nodeErr);
        ok := Pipe.Stage(pipe, "parse_csv", MapRun,
                         ADR(nodes[nNodes].mapCtx),
                         ADR(nodes[nNodes].mapCtx.inCh),
                         ADR(nodes[nNodes].mapCtx.outCh), ChanCap)

    | StParseTsv:
        nodes[nNodes].kind := NkMap;
        nodes[nNodes].tsvData.hasHeader := p.stages[i].hdrMode # HmNoheader;
        nodes[nNodes].tsvData.headerDone := FALSE;
        nodes[nNodes].tsvData.numHeaders := 0;
        nodes[nNodes].mapCtx.mapFn := ParseTsvTransform;
        nodes[nNodes].mapCtx.userData := ADR(nodes[nNodes].tsvData);
        nodes[nNodes].mapCtx.err := ADR(nodes[nNodes].nodeErr);
        ok := Pipe.Stage(pipe, "parse_tsv", MapRun,
                         ADR(nodes[nNodes].mapCtx),
                         ADR(nodes[nNodes].mapCtx.inCh),
                         ADR(nodes[nNodes].mapCtx.outCh), ChanCap)

    | StParseKv:
        nodes[nNodes].kind := NkMap;
        nodes[nNodes].mapCtx.mapFn := ParseKvTransform;
        nodes[nNodes].mapCtx.userData := NIL;
        nodes[nNodes].mapCtx.err := ADR(nodes[nNodes].nodeErr);
        ok := Pipe.Stage(pipe, "parse_kv", MapRun,
                         ADR(nodes[nNodes].mapCtx),
                         ADR(nodes[nNodes].mapCtx.inCh),
                         ADR(nodes[nNodes].mapCtx.outCh), ChanCap)

    | StLines:
        nodes[nNodes].kind := NkMap;
        nodes[nNodes].mapCtx.mapFn := LinesTransform;
        nodes[nNodes].mapCtx.userData := NIL;
        nodes[nNodes].mapCtx.err := ADR(nodes[nNodes].nodeErr);
        ok := Pipe.Stage(pipe, "lines", MapRun,
                         ADR(nodes[nNodes].mapCtx),
                         ADR(nodes[nNodes].mapCtx.inCh),
                         ADR(nodes[nNodes].mapCtx.outCh), ChanCap)

    | StFilter:
        nodes[nNodes].kind := NkFilter;
        nodes[nNodes].filterData.expr := p.stages[i].filterExpr;
        nodes[nNodes].filterCtx.predFn := FilterPred;
        nodes[nNodes].filterCtx.userData := ADR(nodes[nNodes].filterData);
        nodes[nNodes].filterCtx.err := ADR(nodes[nNodes].nodeErr);
        ok := Pipe.Stage(pipe, "filter", FilterRun,
                         ADR(nodes[nNodes].filterCtx),
                         ADR(nodes[nNodes].filterCtx.inCh),
                         ADR(nodes[nNodes].filterCtx.outCh), ChanCap)

    | StMap, StProject:
        nodes[nNodes].kind := NkMap;
        nodes[nNodes].mapData.stage := ADR(p.stages[i]);
        nodes[nNodes].mapCtx.mapFn := MapTransform;
        nodes[nNodes].mapCtx.userData := ADR(nodes[nNodes].mapData);
        nodes[nNodes].mapCtx.err := ADR(nodes[nNodes].nodeErr);
        ok := Pipe.Stage(pipe, "map", MapRun,
                         ADR(nodes[nNodes].mapCtx),
                         ADR(nodes[nNodes].mapCtx.inCh),
                         ADR(nodes[nNodes].mapCtx.outCh), ChanCap)

    | StCount:
        nodes[nNodes].kind := NkReduce;
        nodes[nNodes].countData.count := 0;
        nodes[nNodes].reduceCtx.reduceFn := CountReduce;
        nodes[nNodes].reduceCtx.userData := ADR(nodes[nNodes].countData);
        nodes[nNodes].reduceCtx.acc := NIL;
        nodes[nNodes].reduceCtx.err := ADR(nodes[nNodes].nodeErr);
        ok := Pipe.Stage(pipe, "count", ReduceRun,
                         ADR(nodes[nNodes].reduceCtx),
                         ADR(nodes[nNodes].reduceCtx.inCh),
                         ADR(nodes[nNodes].reduceCtx.outCh), ChanCap)

    | StCountBy:
        nodes[nNodes].kind := NkReduce;
        Assign(p.stages[i].groupField, nodes[nNodes].countByData.fieldName);
        nodes[nNodes].countByData.inited := FALSE;
        nodes[nNodes].reduceCtx.reduceFn := CountByReduce;
        nodes[nNodes].reduceCtx.userData := ADR(nodes[nNodes].countByData);
        nodes[nNodes].reduceCtx.acc := NIL;
        nodes[nNodes].reduceCtx.err := ADR(nodes[nNodes].nodeErr);
        ok := Pipe.Stage(pipe, "count_by", ReduceRun,
                         ADR(nodes[nNodes].reduceCtx),
                         ADR(nodes[nNodes].reduceCtx.inCh),
                         ADR(nodes[nNodes].reduceCtx.outCh), ChanCap)

    | StBatch:
        nodes[nNodes].kind := NkBatch;
        nodes[nNodes].batchCtx.batchFn := BatchPassthrough;
        nodes[nNodes].batchCtx.batchSize := p.stages[i].size;
        nodes[nNodes].batchCtx.userData := NIL;
        nodes[nNodes].batchCtx.err := ADR(nodes[nNodes].nodeErr);
        ok := Pipe.Stage(pipe, "batch", BatchRun,
                         ADR(nodes[nNodes].batchCtx),
                         ADR(nodes[nNodes].batchCtx.inCh),
                         ADR(nodes[nNodes].batchCtx.outCh), ChanCap)

    | StWindow:
        nodes[nNodes].kind := NkWindow;
        nodes[nNodes].windowCtx.windowFn := NIL;
        nodes[nNodes].windowCtx.windowSize := p.stages[i].size;
        nodes[nNodes].windowCtx.slideBy := p.stages[i].size;
        nodes[nNodes].windowCtx.userData := NIL;
        nodes[nNodes].windowCtx.err := ADR(nodes[nNodes].nodeErr);
        ok := Pipe.Stage(pipe, "window", WindowRun,
                         ADR(nodes[nNodes].windowCtx),
                         ADR(nodes[nNodes].windowCtx.inCh),
                         ADR(nodes[nNodes].windowCtx.outCh), ChanCap)
    END;

    IF NOT ok THEN
      result.ok := FALSE;
      Assign("failed to add pipeline stage", result.errMsg);
      CloseFileSource(nodes[0].fileSrc);
      Pipe.Destroy(pipe);
      RETURN
    END;

    INC(nNodes);
    INC(i)
  END;

  (* === Sink node === *)
  nodes[nNodes].kind := NkSink;
  nodes[nNodes].nodeErr.hasError := FALSE;
  nodes[nNodes].sinkCtx.consumeFn := SinkConsume;
  nodes[nNodes].sinkCtx.err := ADR(nodes[nNodes].nodeErr);

  CASE p.sink.kind OF
    SkStdout:
      nodes[nNodes].sinkData.isStdout := TRUE;
      nodes[nNodes].sinkData.path[0] := CHR(0)
  | SkSinkFile:
      nodes[nNodes].sinkData.isStdout := FALSE;
      Assign(p.sink.path, nodes[nNodes].sinkData.path)
  END;

  IF NOT OpenFileSink(nodes[nNodes].sinkData) THEN
    result.ok := FALSE;
    Assign("failed to open sink file", result.errMsg);
    CloseFileSource(nodes[0].fileSrc);
    Pipe.Destroy(pipe);
    RETURN
  END;

  nodes[nNodes].sinkCtx.userData := ADR(nodes[nNodes].sinkData);

  ok := Pipe.Stage(pipe, "sink", SinkRun, ADR(nodes[nNodes].sinkCtx),
                   ADR(nodes[nNodes].sinkCtx.inCh), NIL, ChanCap);
  IF NOT ok THEN
    result.ok := FALSE;
    Assign("failed to add sink stage", result.errMsg);
    CloseFileSource(nodes[0].fileSrc);
    CloseFileSink(nodes[nNodes].sinkData);
    Pipe.Destroy(pipe);
    RETURN
  END;

  INC(nNodes);

  (* === Run === *)
  Pipe.Run(pipe);

  (* === Cleanup === *)
  CloseFileSource(nodes[0].fileSrc);
  CloseFileSink(nodes[nNodes - 1].sinkData);

  i := 0;
  WHILE i < nNodes DO
    IF nodes[i].nodeErr.hasError THEN
      result.ok := FALSE;
      Assign(nodes[i].nodeErr.msg, result.errMsg);
      Pipe.Destroy(pipe);
      RETURN
    END;
    INC(i)
  END;

  Pipe.Destroy(pipe)
END Execute;

END Lower.
