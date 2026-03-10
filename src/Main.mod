MODULE Main;
(* FlowQL CLI — check, plan, run *)

FROM Args IMPORT ArgCount, GetArg;
FROM InOut IMPORT WriteString, WriteLn, WriteInt;
FROM BinaryIO IMPORT OpenRead, Close, ReadBytes;
FROM Strings IMPORT Assign, CompareStr, Length;
FROM Parser IMPORT Parse, ParseResult;
FROM Sema IMPORT Validate, SemaResult;
FROM Plan IMPORT PrintPlan, PrintPlanVerbose;
FROM Lower IMPORT Execute, LowerResult;

CONST
  MaxSourceFile = 65535;

VAR
  cmd:     ARRAY [0..31] OF CHAR;
  path:    ARRAY [0..255] OF CHAR;
  flag:    ARRAY [0..31] OF CHAR;
  source:  ARRAY [0..MaxSourceFile] OF CHAR;
  srcLen:  CARDINAL;
  verbose: BOOLEAN;
  parseR:  ParseResult;
  semaR:   SemaResult;
  lowerR:  LowerResult;

PROCEDURE ReadSourceFile(VAR filePath: ARRAY OF CHAR;
                         VAR buf: ARRAY OF CHAR;
                         VAR len: CARDINAL): BOOLEAN;
VAR
  fh:     CARDINAL;
  actual: CARDINAL;
  chBuf:  ARRAY [0..0] OF CHAR;
BEGIN
  OpenRead(filePath, fh);
  IF fh = 0 THEN
    WriteString("error: cannot open file: ");
    WriteString(filePath);
    WriteLn;
    RETURN FALSE
  END;
  len := 0;
  LOOP
    actual := 0;
    ReadBytes(fh, chBuf, 1, actual);
    IF actual = 0 THEN EXIT END;
    buf[len] := chBuf[0];
    INC(len);
    IF len >= MaxSourceFile THEN EXIT END
  END;
  buf[len] := CHR(0);
  Close(fh);
  RETURN TRUE
END ReadSourceFile;

PROCEDURE PrintUsage;
BEGIN
  WriteString("FlowQL v0.1.0 — Streaming Pipeline DSL for FlowNet");
  WriteLn;
  WriteLn;
  WriteString("Usage:");
  WriteLn;
  WriteString("  flowql check <file.fq>  — Parse and validate");
  WriteLn;
  WriteString("  flowql plan  <file.fq>  — Show logical plan");
  WriteLn;
  WriteString("  flowql plan -v <file.fq> — Verbose plan");
  WriteLn;
  WriteString("  flowql run   <file.fq>  — Execute pipeline");
  WriteLn
END PrintUsage;

PROCEDURE DoCheck;
BEGIN
  Parse(source, srcLen, parseR);
  IF NOT parseR.ok THEN
    WriteString("parse error at line ");
    WriteInt(INTEGER(parseR.errLine), 0);
    WriteString(", col ");
    WriteInt(INTEGER(parseR.errCol), 0);
    WriteString(": ");
    WriteString(parseR.errMsg);
    WriteLn;
    HALT
  END;

  Validate(parseR.pipeline, semaR);
  IF NOT semaR.ok THEN
    WriteString("semantic error at line ");
    WriteInt(INTEGER(semaR.errLine), 0);
    WriteString(", col ");
    WriteInt(INTEGER(semaR.errCol), 0);
    WriteString(": ");
    WriteString(semaR.errMsg);
    WriteLn;
    HALT
  END;

  WriteString("ok");
  WriteLn
END DoCheck;

PROCEDURE DoPlan;
BEGIN
  Parse(source, srcLen, parseR);
  IF NOT parseR.ok THEN
    WriteString("parse error at line ");
    WriteInt(INTEGER(parseR.errLine), 0);
    WriteString(", col ");
    WriteInt(INTEGER(parseR.errCol), 0);
    WriteString(": ");
    WriteString(parseR.errMsg);
    WriteLn;
    HALT
  END;

  Validate(parseR.pipeline, semaR);
  IF NOT semaR.ok THEN
    WriteString("semantic error at line ");
    WriteInt(INTEGER(semaR.errLine), 0);
    WriteString(", col ");
    WriteInt(INTEGER(semaR.errCol), 0);
    WriteString(": ");
    WriteString(semaR.errMsg);
    WriteLn;
    HALT
  END;

  IF verbose THEN
    PrintPlanVerbose(parseR.pipeline)
  ELSE
    PrintPlan(parseR.pipeline)
  END
END DoPlan;

PROCEDURE DoRun;
BEGIN
  Parse(source, srcLen, parseR);
  IF NOT parseR.ok THEN
    WriteString("parse error at line ");
    WriteInt(INTEGER(parseR.errLine), 0);
    WriteString(", col ");
    WriteInt(INTEGER(parseR.errCol), 0);
    WriteString(": ");
    WriteString(parseR.errMsg);
    WriteLn;
    HALT
  END;

  Validate(parseR.pipeline, semaR);
  IF NOT semaR.ok THEN
    WriteString("semantic error at line ");
    WriteInt(INTEGER(semaR.errLine), 0);
    WriteString(", col ");
    WriteInt(INTEGER(semaR.errCol), 0);
    WriteString(": ");
    WriteString(semaR.errMsg);
    WriteLn;
    HALT
  END;

  Execute(parseR.pipeline, lowerR);
  IF NOT lowerR.ok THEN
    WriteString("runtime error: ");
    WriteString(lowerR.errMsg);
    WriteLn;
    HALT
  END
END DoRun;

BEGIN
  IF ArgCount() < 2 THEN
    PrintUsage;
    HALT
  END;

  verbose := FALSE;
  GetArg(1, cmd);
  GetArg(2, path);

  (* Check for -v flag: flowql plan -v <file> *)
  IF (CompareStr(path, "-v") = 0) OR (CompareStr(path, "--verbose") = 0) THEN
    verbose := TRUE;
    IF ArgCount() < 3 THEN
      PrintUsage;
      HALT
    END;
    GetArg(3, path)
  END;

  IF NOT ReadSourceFile(path, source, srcLen) THEN
    HALT
  END;

  IF CompareStr(cmd, "check") = 0 THEN
    DoCheck
  ELSIF CompareStr(cmd, "plan") = 0 THEN
    DoPlan
  ELSIF CompareStr(cmd, "run") = 0 THEN
    DoRun
  ELSE
    WriteString("unknown command: ");
    WriteString(cmd);
    WriteLn;
    PrintUsage;
    HALT
  END
END Main.
