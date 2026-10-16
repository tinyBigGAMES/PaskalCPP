{===============================================================================
  PaskalCPP™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://paskalcpp.org

  SPDX-License-Identifier: MPL-2.0

  This Source Code Form is subject to the terms of the
  Mozilla Public License, v. 2.0. If a copy of the MPL
  was not distributed with this file, You can obtain one
  at https://mozilla.org/MPL/2.0/.
 -------------------------------------------------------------------------------
  PaskalCPP.Debug.REPL - the console debugger (pcpp <file> -d)

  Drives one TPCDebugRuntime in-process (no protocol, no port: CPaskal's REPL
  was a DAP client of a TCP server, not ported): reads a command line, runs
  it, prints what it shows. On a real console the program shares it (live
  output, the keyboard while it runs); otherwise its output comes through
  the engine's output pipe and is printed as it arrives, in order with the
  REPL's lines (ProgramOutputMode).
  The program's @breakpoint statements (TPCDebugRuntime.SourceBreakpoints,
  read from the AST) are its first breakpoints; a program with none at all
  is held at its entry (b, then c runs it). Commands adapted from the
  reference (CPaskal.Debug.REPL.pas:460-960): b bl bd bc c n s finish bt f
  locals p src threads r h q. The end of the input is q.
  Input and output are callbacks: a script and a buffer in the tests, the
  console from the CLI. Colors only when asked (a console).

  Dependencies: StdApp.Base, StdApp.Console, StdApp.Utils, StdApp.Resources,
    PaskalCPP.AST, PaskalCPP.Debug.Target, PaskalCPP.Debug.Runtime
===============================================================================}

unit PaskalCPP.Debug.REPL;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.AST,
  PaskalCPP.Debug.Target,
  PaskalCPP.Debug.Runtime;

const
  { PC_DBG_REPL_PROMPT }
  PC_DBG_REPL_PROMPT = '(dbg) ';
  { PC_DBG_REPL_WAIT_MS }
  // One wait for the engine's next event while the program runs
  PC_DBG_REPL_WAIT_MS = 100;
  { PC_DBG_REPL_CONTEXT_LINES }
  // Source lines shown before and after the line of a stop
  PC_DBG_REPL_CONTEXT_LINES = 2;
  { PC_DBG_REPL_SOURCE_LINE }
  // A source line: marker, line number, text
  PC_DBG_REPL_SOURCE_LINE = '%s %4d  %s';
  { PC_DBG_REPL_MARK_CURRENT }
  PC_DBG_REPL_MARK_CURRENT = '>>';
  { PC_DBG_REPL_MARK_OTHER }
  PC_DBG_REPL_MARK_OTHER = '  ';
  { PC_DBG_REPL_MARK_FRAME }
  // bt: the selected frame
  PC_DBG_REPL_MARK_FRAME = '>';
  { PC_DBG_REPL_MARK_THREAD }
  // threads: the thread of the stop
  PC_DBG_REPL_MARK_THREAD = '*';
  { PC_DBG_REPL_MARK_NONE }
  PC_DBG_REPL_MARK_NONE = ' ';
  { PC_DBG_REPL_READ_CHARS }
  // One console read (a longer line is read on in further reads)
  PC_DBG_REPL_READ_CHARS = 4096;
  { PC_DBG_REPL_BREAK_WAIT_MS }
  // A read that Ctrl+C ended gives nothing; the handler that says it was
  // Ctrl+C runs on a thread of its own: this long it may come after
  PC_DBG_REPL_BREAK_WAIT_MS = 200;
  { PC_DBG_REPL_CTRL_Z }
  // The console's end of input: Ctrl+Z first on its line
  PC_DBG_REPL_CTRL_Z = #26;
  { PC_DBG_REPL_MAX_REPORTS }
  // The session's reports are shown and cleared after each command; this
  // only bounds one command's
  PC_DBG_REPL_MAX_REPORTS = 1000;

type
  { TPCReplReadKind }
  // What one read of the console gave
  TPCReplReadKind = (
    rrkLine,      // a line (maybe empty)
    rrkBreak,     // Ctrl+C / Ctrl+Break at the prompt: no line, the prompt again
    rrkEnd        // the end of the input (a failed read, Ctrl+Z): the REPL ends
  );

  { TPCDebugReplReader }
  // The next command line; False = no more input (the REPL ends as on q)
  TPCDebugReplReader = reference to function(out ALine: string): Boolean;

  { TPCDebugReplWriter }
  // Text to show as it is (line breaks included)
  TPCDebugReplWriter = reference to procedure(const AText: string);

  { TPCDebugReplBreakpoint }
  // One breakpoint the person set, or a @breakpoint of the program: kept
  // across runs (r); Placed is the current run's answer
  TPCDebugReplBreakpoint = record
    Number: Integer;          // the REPL's own, stable for the whole REPL
    FileName: string;         // resolved (a module's SourceFile, or ResolvePath)
    Line: Integer;
    IsPlaced: Boolean;        // False = no run has placed it yet
    Placed: TPCBreakpointResult;
  end;

  { TPCDebugREPL }
  TPCDebugREPL = class(TBaseObject)
  private
    FSessionErrors: TErrors;     // the REPL owns its session's reports
    FRuntime: TPCDebugRuntime;   // nil before the first run
    FProgram: TPCModule;
    FImagePath: string;
    FHostPath: string;           // '' = an exe; else the exe that loads the dll
    FArgs: string;
    FReader: TPCDebugReplReader;
    FWriter: TPCDebugReplWriter;
    FOwnIO: Boolean;             // a reader or writer was set (tests, scripts)
    FColor: Boolean;
    FWaitLimitMs: Cardinal;
    FBreakpoints: TList<TPCDebugReplBreakpoint>;
    FNextNumber: Integer;
    FSources: TDictionary<string, TArray<string>>;
    FFrameIndex: Integer;        // the frame locals / p / src look at
    FExited: Boolean;            // no live program (exited, or never started)
    FAtEntry: Boolean;           // launched, held at its entry: c starts it
    FLastExitCode: Cardinal;
    FAtLineStart: Boolean;
    FQuit: Boolean;
    FWaiting: Integer;           // 1 while DoWait waits on a running program (TInterlocked)
    FPauseAsked: Integer;        // 1 = RequestPause came during that wait (TInterlocked)
    FPromptBreak: Integer;       // 1 = Ctrl+C while no wait (at the prompt) (TInterlocked)

    // The console (the default reader) and its Ctrl+C
    procedure DoOnBreakKey();
    function DoReadInput(out ALine: string): Boolean;
    // A standard handle (STD_INPUT_HANDLE ...) that is a console; AHandle = it
    function DoStdConsole(const AStd: Cardinal; out AHandle: THandle): Boolean;
    function DoReadConsoleLine(const AInput: THandle; out ALine: string): Boolean;

    // Output
    procedure DoText(const AText: string);
    procedure DoLine(const AText: string; const AColor: string = '');
    procedure DoLineFmt(const AText: string; const AArgs: array of const; const AColor: string = '');
    procedure DoShowReports();
    function DoDisplayName(const AFile: string): string;

    // Session
    procedure DoNewRuntime();
    function DoStartSession(): Boolean;
    function DoRunFromEntry(): Boolean;
    procedure DoEndSession();
    procedure DoWait();
    procedure DoWaitEvents(const AStart: UInt64);
    function DoNeedStop(): Boolean;
    function DoStack(): TArray<TPCDebugStackItem>;
    function DoReasonText(const AEvent: TPCDebugEvent): string;
    procedure DoShowStop(const AEvent: TPCDebugEvent);
    procedure DoShowFrame(const AIndex: Integer; const AItem: TPCDebugStackItem);
    function DoSourceLines(const AFile: string; out ALines: TArray<string>): Boolean;
    procedure DoShowSource(const AFile: string; const ALine: Integer);

    // Breakpoints
    procedure DoAddSourceBreakpoints();
    function DoResolveFile(const AText: string; out AFile: string): Boolean;
    procedure DoSendFile(const AFile: string);
    procedure DoSendAll();
    procedure DoTakeChanges();
    procedure DoShowBreakpoint(const ABreakpoint: TPCDebugReplBreakpoint);

    // Commands
    procedure DoCommand(const ALine: string);
    procedure DoCmdBreak(const AArg: string);
    procedure DoCmdList();
    procedure DoCmdDelete(const AArg: string);
    procedure DoCmdClear();
    procedure DoCmdRun(const AKind: TPCDebugStepKind);
    procedure DoCmdBacktrace();
    procedure DoCmdFrame(const AArg: string);
    procedure DoCmdLocals();
    procedure DoCmdPrint(const AArg: string);
    procedure DoCmdSource();
    procedure DoCmdThreads();
    procedure DoCmdRestart();
    // Run's session: the program started, then commands until q or the end
    // of the input
    function DoSession(): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // The analysed tree of the program (the build's TPCCompiler keeps it and
    // outlives the REPL); nil = a prebuilt image: C++ names
    procedure SetProgram(const AMain: TPCModule);
    procedure SetTarget(const AExePath: string; const AArgs: string);
    // DLL mode: the dll debugged and the exe that loads it
    procedure SetHostTarget(const ADllPath: string; const AHostExePath: string; const AArgs: string);
    // Defaults: lines of the console's standard input, TConsole, no color
    procedure SetReader(const AReader: TPCDebugReplReader);
    procedure SetWriter(const AWriter: TPCDebugReplWriter);
    procedure SetColor(const AEnabled: Boolean);
    // How long one wait for a stop may last (ms) before the prompt comes back
    // with the program running; 0 = no limit (the default)
    procedure SetWaitLimit(const AMs: Cardinal);

    // Starts the program and reads commands until q or the end of the input.
    // False = the program did not start (its reports were shown). While it
    // runs, Ctrl+C / Ctrl+Break at the console is RequestPause (at the
    // prompt it does nothing: q quits)
    function Run(): Boolean;
    // Any thread: the running program the REPL waits on is paused (a stop
    // as dsrPause, then the prompt). Asked when nothing runs: dropped
    procedure RequestPause();
    // The program's exit code (0 when it did not exit)
    function GetLastExitCode(): Cardinal;

    // One console read: ok / characters read / its text, and whether the
    // Ctrl+C handler said the key was pressed at the prompt. Nothing read
    // after Ctrl+C is a break (the prompt again), nothing read otherwise or
    // a line that starts with Ctrl+Z is the end; a line wins over a stale key
    class function ClassifyConsoleRead(const AOk: Boolean; const ACount: Cardinal;
      const AText: string; const ABroken: Boolean): TPCReplReadKind; static;
    // A read line without its line end (CR LF, LF)
    class function ConsoleLineText(const AText: string): string; static;
    // Where the program's standard handles go: the REPL's own console,
    // shared, when its input and output are the console and the REPL reads
    // and writes them itself (live output, the keyboard while it runs);
    // otherwise pipes, its output coming through the engine in order
    class function ProgramOutputMode(const AInputIsConsole: Boolean;
      const AOutputIsConsole: Boolean; const AOwnIO: Boolean): TPCDebugOutputMode; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.IOUtils,
  System.SyncObjs,
  StdApp.Console,
  StdApp.Utils,
  StdApp.Resources;

var
  // The REPL whose Run holds the console (one at a time), and the lock the
  // console handler and Run share: the handler runs on a thread of its own
  GReplLock: TCriticalSection;
  GActiveRepl: TPCDebugREPL;

{ DoConsoleCtrl }
function DoConsoleCtrl(ACtrlType: DWORD): BOOL; stdcall;
begin
  // Ctrl+C / Ctrl+Break while a REPL runs: never the end of pcpp; a pause
  // of the program it waits on (the program is in its own process group,
  // so the key is not its). Nothing raises back into the OS
  Result := False;
  if (ACtrlType <> CTRL_C_EVENT) and (ACtrlType <> CTRL_BREAK_EVENT) then
    Exit;
  try
    GReplLock.Enter();
    try
      if GActiveRepl <> nil then
      begin
        GActiveRepl.DoOnBreakKey();
        Result := True;
      end;
    finally
      GReplLock.Leave();
    end;
  except
    on Exception do
      Result := True;
  end;
end;

{ TPCDebugREPL }

constructor TPCDebugREPL.Create();
begin
  inherited;

  FSessionErrors := TErrors.Create();
  FSessionErrors.SetMaxErrors(PC_DBG_REPL_MAX_REPORTS);
  SetErrors(FSessionErrors);
  FRuntime := nil;
  FProgram := nil;
  FImagePath := '';
  FHostPath := '';
  FArgs := '';
  FColor := False;
  FWaitLimitMs := 0;
  FBreakpoints := TList<TPCDebugReplBreakpoint>.Create();
  FNextNumber := 1;
  FSources := TDictionary<string, TArray<string>>.Create();
  FFrameIndex := 0;
  FExited := True;
  FAtEntry := False;
  FLastExitCode := 0;
  FAtLineStart := True;
  FQuit := False;
  FWaiting := 0;
  FPauseAsked := 0;
  FPromptBreak := 0;

  // The console: one line of standard input per command
  FReader :=
    function(out ALine: string): Boolean
    begin
      Result := DoReadInput(ALine);
    end;
  FWriter :=
    procedure(const AText: string)
    begin
      TConsole.Print(AText, False);
    end;
end;

destructor TPCDebugREPL.Destroy();
begin
  DoEndSession();
  FreeAndNil(FSources);
  FreeAndNil(FBreakpoints);
  FreeAndNil(FSessionErrors);

  inherited;
end;

procedure TPCDebugREPL.SetProgram(const AMain: TPCModule);
begin
  FProgram := AMain;
end;

procedure TPCDebugREPL.SetTarget(const AExePath: string; const AArgs: string);
begin
  FImagePath := AExePath;
  FHostPath := '';
  FArgs := AArgs;
end;

procedure TPCDebugREPL.SetHostTarget(const ADllPath: string; const AHostExePath: string; const AArgs: string);
begin
  FImagePath := ADllPath;
  FHostPath := AHostExePath;
  FArgs := AArgs;
end;

procedure TPCDebugREPL.SetReader(const AReader: TPCDebugReplReader);
begin
  FReader := AReader;
  FOwnIO := True;
end;

procedure TPCDebugREPL.SetWriter(const AWriter: TPCDebugReplWriter);
begin
  FWriter := AWriter;
  FOwnIO := True;
end;

procedure TPCDebugREPL.SetColor(const AEnabled: Boolean);
begin
  FColor := AEnabled;
end;

procedure TPCDebugREPL.SetWaitLimit(const AMs: Cardinal);
begin
  FWaitLimitMs := AMs;
end;

function TPCDebugREPL.GetLastExitCode(): Cardinal;
begin
  Result := FLastExitCode;
end;

procedure TPCDebugREPL.RequestPause();
begin
  // Only a wait takes it (DoWait); one asked at the prompt would pause the
  // next run at random
  if TInterlocked.CompareExchange(FWaiting, 0, 0) = 1 then
    TInterlocked.Exchange(FPauseAsked, 1);
end;

procedure TPCDebugREPL.DoOnBreakKey();
begin
  // The console handler's thread: while a program runs, a pause; at the
  // prompt, the read it ended is not the end of the input (DoReadConsoleLine)
  if TInterlocked.CompareExchange(FWaiting, 0, 0) = 1 then
    TInterlocked.Exchange(FPauseAsked, 1)
  else
    TInterlocked.Exchange(FPromptBreak, 1);
end;

class function TPCDebugREPL.ClassifyConsoleRead(const AOk: Boolean; const ACount: Cardinal;
  const AText: string; const ABroken: Boolean): TPCReplReadKind;
begin
  if AOk and (ACount > 0) then
  begin
    if AText.StartsWith(PC_DBG_REPL_CTRL_Z) then
      Exit(rrkEnd);
    Exit(rrkLine);
  end;
  if ABroken then
    Result := rrkBreak
  else
    Result := rrkEnd;
end;

class function TPCDebugREPL.ProgramOutputMode(const AInputIsConsole: Boolean;
  const AOutputIsConsole: Boolean; const AOwnIO: Boolean): TPCDebugOutputMode;
begin
  // Shared only when nothing stands between the person and the console: a
  // pipe or a test's reader / writer would see the program's text out of
  // the REPL's order, or not at all
  if AInputIsConsole and AOutputIsConsole and (not AOwnIO) then
    Result := domConsole
  else
    Result := domPipes;
end;

class function TPCDebugREPL.ConsoleLineText(const AText: string): string;
begin
  Result := AText;
  while Result.EndsWith(#10) or Result.EndsWith(#13) do
    Result := Result.Substring(0, Result.Length - 1);
end;

function TPCDebugREPL.DoStdConsole(const AStd: Cardinal; out AHandle: THandle): Boolean;
var
  LMode: DWORD;
begin
  AHandle := GetStdHandle(AStd);
  Result := (AHandle <> 0) and (AHandle <> INVALID_HANDLE_VALUE) and GetConsoleMode(AHandle, LMode);
end;

function TPCDebugREPL.DoReadInput(out ALine: string): Boolean;
var
  LInput: THandle;
begin
  // A console is read as a console (Ctrl+C at the prompt is no end of
  // input); redirected input (a file, a pipe) line by line, to its end
  ALine := '';
  if DoStdConsole(STD_INPUT_HANDLE, LInput) then
    Exit(DoReadConsoleLine(LInput, ALine));
  Result := not Eof(Input);
  if Result then
    ReadLn(Input, ALine);
end;

function TPCDebugREPL.DoReadConsoleLine(const AInput: THandle; out ALine: string): Boolean;
var
  LBuffer: array of WideChar;
  LRead: DWORD;
  LOk: Boolean;
  LText: string;
  LChunk: string;
  LStart: UInt64;
  LKind: TPCReplReadKind;
begin
  ALine := '';
  SetLength(LBuffer, PC_DBG_REPL_READ_CHARS);
  TInterlocked.Exchange(FPromptBreak, 0);
  LRead := 0;
  LOk := ReadConsoleW(AInput, @LBuffer[0], DWORD(Length(LBuffer)), LRead, nil);
  LText := '';
  if LOk and (LRead > 0) then
    SetString(LText, PWideChar(@LBuffer[0]), LRead);
  // Nothing read: Ctrl+C ended the read, or the input did; the handler's
  // word may come a moment after
  if (not LOk) or (LRead = 0) then
  begin
    LStart := TUtils.GetTickCount64();
    while (TInterlocked.CompareExchange(FPromptBreak, 0, 0) = 0) and
      (TUtils.GetTickCount64() - LStart < PC_DBG_REPL_BREAK_WAIT_MS) do
      Sleep(10);
  end;
  LKind := ClassifyConsoleRead(LOk, LRead, LText, TInterlocked.Exchange(FPromptBreak, 0) = 1);

  case LKind of
    rrkBreak:
      begin
        // The prompt again, on a line of its own
        FWriter(sLineBreak);
        Result := True;
      end;
    rrkLine:
      begin
        // A line longer than one read comes in further reads, to its end
        while not LText.EndsWith(#10) do
        begin
          LRead := 0;
          if (not ReadConsoleW(AInput, @LBuffer[0], DWORD(Length(LBuffer)), LRead, nil)) or (LRead = 0) then
            Break;
          SetString(LChunk, PWideChar(@LBuffer[0]), LRead);
          LText := LText + LChunk;
        end;
        ALine := ConsoleLineText(LText);
        Result := True;
      end;
  else
    Result := False;
  end;
end;

{ TPCDebugREPL: output }

procedure TPCDebugREPL.DoText(const AText: string);
begin
  if AText = '' then
    Exit;
  FWriter(AText);
  FAtLineStart := AText.EndsWith(#10);
end;

procedure TPCDebugREPL.DoLine(const AText: string; const AColor: string);
begin
  // A line of the REPL's own starts on a fresh line, also after program
  // output that did not end one
  if not FAtLineStart then
    DoText(sLineBreak);
  if FColor and (AColor <> '') then
    DoText(AColor + AText + COLOR_RESET + sLineBreak)
  else
    DoText(AText + sLineBreak);
end;

procedure TPCDebugREPL.DoLineFmt(const AText: string; const AArgs: array of const; const AColor: string);
begin
  DoLine(Format(AText, AArgs), AColor);
end;

procedure TPCDebugREPL.DoShowReports();
var
  LError: TError;
begin
  // What the engine reported since the last time, then forgotten: the
  // session runs as long as the person wants
  for LError in FErrors.GetItems() do
  begin
    // Plain text (ToIDEString): the REPL adds its own color, or none
    if LError.Severity in [esError, esFatal] then
      DoLine(LError.ToIDEString(), COLOR_RED)
    else
      DoLine(LError.ToIDEString(), COLOR_YELLOW);
  end;
  FErrors.Clear();
end;

function TPCDebugREPL.DoDisplayName(const AFile: string): string;
var
  LSlash: Integer;
begin
  // The file name alone; ResolvePath spells short paths with '/', long ones
  // with '\' (ExtractFileName knows only '\')
  LSlash := LastDelimiter('/\:', AFile);
  Result := Copy(AFile, LSlash + 1, MaxInt);
end;

{ TPCDebugREPL: session }

procedure TPCDebugREPL.DoNewRuntime();
var
  LI: Integer;
  LBreakpoint: TPCDebugReplBreakpoint;
  LInput: THandle;
  LOutput: THandle;
  LInputIsConsole: Boolean;
  LOutputIsConsole: Boolean;
begin
  DoEndSession();

  FRuntime := TPCDebugRuntime.Create();
  FRuntime.SetErrors(FErrors);
  FRuntime.SetProgram(FProgram);
  if FHostPath <> '' then
    FRuntime.SetHostTarget(FImagePath, FHostPath, FArgs)
  else
    FRuntime.SetTarget(FImagePath, FArgs);
  // On a console the program shares it (a terminal: live output, the
  // keyboard while it runs); otherwise its output comes through the engine
  // (dekOutput), in order with the REPL's own lines, stdin NUL
  LInputIsConsole := DoStdConsole(STD_INPUT_HANDLE, LInput);
  LOutputIsConsole := DoStdConsole(STD_OUTPUT_HANDLE, LOutput);
  FRuntime.SetOutputMode(ProgramOutputMode(LInputIsConsole, LOutputIsConsole, FOwnIO));

  FExited := True;
  FAtEntry := False;
  FLastExitCode := 0;
  FFrameIndex := 0;
  // A new run places every breakpoint again
  for LI := 0 to FBreakpoints.Count - 1 do
  begin
    LBreakpoint := FBreakpoints[LI];
    LBreakpoint.IsPlaced := False;
    LBreakpoint.Placed := Default(TPCBreakpointResult);
    FBreakpoints[LI] := LBreakpoint;
  end;
end;

function TPCDebugREPL.DoStartSession(): Boolean;
begin
  // Launch holds the program at its entry: the breakpoints go in, then it
  // runs to its first stop or its end. With no breakpoint nothing would
  // stop it, so it stays held at its entry: the person sets one with b,
  // c starts it
  Result := FRuntime.Launch();
  if not Result then
  begin
    DoShowReports();
    Exit;
  end;
  FExited := False;
  DoSendAll();
  if FBreakpoints.Count = 0 then
  begin
    FAtEntry := True;
    DoLine(RSDbgReplHeldAtEntry, COLOR_YELLOW);
    Exit;
  end;
  Result := DoRunFromEntry();
end;

function TPCDebugREPL.DoRunFromEntry(): Boolean;
begin
  // The program leaves its entry (ConfigurationDone) and runs to its first
  // stop or its end
  FAtEntry := False;
  Result := FRuntime.ConfigurationDone();
  if not Result then
  begin
    DoShowReports();
    Exit;
  end;
  DoWait();
end;

procedure TPCDebugREPL.DoEndSession();
begin
  if FRuntime = nil then
    Exit;
  if not FExited then
  begin
    FRuntime.Terminate();
    FExited := True;
  end;
  FAtEntry := False;
  FreeAndNil(FRuntime);
  DoShowReports();
end;

procedure TPCDebugREPL.DoWait();
var
  LStart: UInt64;
begin
  // Until the program stops or ends; its output is shown as it comes. A
  // RequestPause (Ctrl+C) during it breaks in: the stop comes as dsrPause
  LStart := TUtils.GetTickCount64();
  TInterlocked.Exchange(FPauseAsked, 0);
  TInterlocked.Exchange(FWaiting, 1);
  try
    DoWaitEvents(LStart);
  finally
    TInterlocked.Exchange(FWaiting, 0);
    TInterlocked.Exchange(FPauseAsked, 0);
  end;
end;

procedure TPCDebugREPL.DoWaitEvents(const AStart: UInt64);
var
  LEvent: TPCDebugEvent;
begin
  while True do
  begin
    if TInterlocked.Exchange(FPauseAsked, 0) = 1 then
      if not FRuntime.Pause() then
        DoShowReports();
    if not FRuntime.NextEvent(LEvent, PC_DBG_REPL_WAIT_MS) then
    begin
      if FErrors.Count() > 0 then
        DoShowReports();
      if (FWaitLimitMs > 0) and (TUtils.GetTickCount64() - AStart >= FWaitLimitMs) then
      begin
        DoLineFmt(RSDbgReplStillRunning, [Int64(FWaitLimitMs)], COLOR_YELLOW);
        Exit;
      end;
      Continue;
    end;

    case LEvent.Kind of
      dekOutput:
        DoText(LEvent.OutputText);
      dekStopped:
        begin
          DoTakeChanges();
          DoShowReports();
          FFrameIndex := 0;
          DoShowStop(LEvent);
          Exit;
        end;
      dekExited:
        begin
          FExited := True;
          FLastExitCode := LEvent.ExitCode;
          DoShowReports();
          DoLineFmt(RSDbgReplExited, [Int64(LEvent.ExitCode)], COLOR_YELLOW);
          Exit;
        end;
    end;
  end;
end;

function TPCDebugREPL.DoNeedStop(): Boolean;
begin
  // Inspection and run control need a live, stopped program
  Result := False;
  if (FRuntime = nil) or FExited then
  begin
    DoLine(RSDbgReplNotRunning, COLOR_RED);
    Exit;
  end;
  if FAtEntry then
  begin
    DoLine(RSDbgReplAtEntry, COLOR_RED);
    Exit;
  end;
  if not FRuntime.IsStopped() then
  begin
    DoLine(RSDbgRunning, COLOR_RED);
    Exit;
  end;
  Result := True;
end;

function TPCDebugREPL.DoStack(): TArray<TPCDebugStackItem>;
begin
  Result := nil;
  if (FRuntime <> nil) and (not FExited) and (not FAtEntry) and FRuntime.IsStopped() then
    Result := FRuntime.StackTrace(FRuntime.StoppedThread());
end;

function TPCDebugREPL.DoReasonText(const AEvent: TPCDebugEvent): string;
begin
  case AEvent.Reason of
    dsrEntry:
      Result := RSDbgReplReasonEntry;
    dsrBreakpoint:
      Result := RSDbgReplReasonBreakpoint;
    dsrStep:
      Result := RSDbgReplReasonStep;
    dsrPause:
      Result := RSDbgReplReasonPause;
    dsrException:
      begin
        if AEvent.FirstChance then
          Result := Format(RSDbgReplReasonFirstChance, [Int64(AEvent.ExceptionCode)])
        else
          Result := Format(RSDbgReplReasonException, [Int64(AEvent.ExceptionCode)]);
      end;
  else
    Result := '';
  end;
end;

procedure TPCDebugREPL.DoShowStop(const AEvent: TPCDebugEvent);
var
  LStack: TArray<TPCDebugStackItem>;
  LTop: TPCDebugStackItem;
begin
  LStack := DoStack();
  if Length(LStack) = 0 then
  begin
    DoLineFmt(RSDbgReplStoppedNoLine, [DoReasonText(AEvent), '$' + IntToHex(AEvent.Address)], COLOR_YELLOW);
    Exit;
  end;
  LTop := LStack[0];
  if LTop.FileName = '' then
  begin
    DoLineFmt(RSDbgReplStoppedNoLine, [DoReasonText(AEvent), LTop.RoutineName], COLOR_YELLOW);
    Exit;
  end;
  DoLineFmt(RSDbgReplStopped, [DoReasonText(AEvent), LTop.RoutineName, DoDisplayName(LTop.FileName),
    LTop.Line], COLOR_YELLOW);
  DoShowSource(LTop.FileName, LTop.Line);
end;

procedure TPCDebugREPL.DoShowFrame(const AIndex: Integer; const AItem: TPCDebugStackItem);
var
  LMark: string;
begin
  if AIndex = FFrameIndex then
    LMark := PC_DBG_REPL_MARK_FRAME
  else
    LMark := PC_DBG_REPL_MARK_NONE;
  if AItem.FileName <> '' then
    DoLineFmt(RSDbgReplFrame, [LMark, AIndex, AItem.RoutineName, DoDisplayName(AItem.FileName), AItem.Line])
  else
    DoLineFmt(RSDbgReplFrameNoLine, [LMark, AIndex, AItem.RoutineName, Int64(AItem.Address)]);
end;

function TPCDebugREPL.DoSourceLines(const AFile: string; out ALines: TArray<string>): Boolean;
begin
  // Each file read once; one that cannot be read is said once, then shown
  // without its text
  if not FSources.TryGetValue(AFile, ALines) then
  begin
    try
      ALines := TFile.ReadAllLines(AFile, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        DoLineFmt(RSDbgReplSourceUnreadable, [AFile, E.Message], COLOR_YELLOW);
        ALines := nil;
      end;
    end;
    FSources.Add(AFile, ALines);
  end;
  Result := Length(ALines) > 0;
end;

procedure TPCDebugREPL.DoShowSource(const AFile: string; const ALine: Integer);
var
  LLines: TArray<string>;
  LFirst: Integer;
  LLast: Integer;
  LIndex: Integer;
begin
  if not DoSourceLines(AFile, LLines) then
    Exit;
  LFirst := Max(1, ALine - PC_DBG_REPL_CONTEXT_LINES);
  LLast := Min(Length(LLines), ALine + PC_DBG_REPL_CONTEXT_LINES);
  for LIndex := LFirst to LLast do
  begin
    if LIndex = ALine then
      DoLineFmt(PC_DBG_REPL_SOURCE_LINE, [PC_DBG_REPL_MARK_CURRENT, LIndex, LLines[LIndex - 1]], COLOR_YELLOW)
    else
      DoLineFmt(PC_DBG_REPL_SOURCE_LINE, [PC_DBG_REPL_MARK_OTHER, LIndex, LLines[LIndex - 1]]);
  end;
end;

{ TPCDebugREPL: breakpoints }

procedure TPCDebugREPL.DoAddSourceBreakpoints();
var
  LLines: TArray<TPCDebugSourceLine>;
  LLine: TPCDebugSourceLine;
  LBreakpoint: TPCDebugReplBreakpoint;
begin
  // The program's own @breakpoint statements, from the AST
  LLines := FRuntime.SourceBreakpoints();
  for LLine in LLines do
  begin
    LBreakpoint := Default(TPCDebugReplBreakpoint);
    LBreakpoint.Number := FNextNumber;
    Inc(FNextNumber);
    LBreakpoint.FileName := LLine.FileName;
    LBreakpoint.Line := LLine.Line;
    FBreakpoints.Add(LBreakpoint);
  end;
  if Length(LLines) > 0 then
    DoLineFmt(RSDbgReplSourceBreakpoints, [Length(LLines)]);
end;

function TPCDebugREPL.DoResolveFile(const AText: string; out AFile: string): Boolean;
var
  LModule: TPCModule;
begin
  // A bare file name is one of the program's modules (its folder needs no
  // typing); a path is resolved as any path (TUtils.ResolvePath: the CWD)
  Result := False;
  AFile := '';
  if AText.IndexOfAny(['/', '\']) < 0 then
  begin
    if FRuntime <> nil then
      for LModule in FRuntime.ProgramModules() do
        if SameText(DoDisplayName(LModule.SourceFile), AText) then
        begin
          AFile := LModule.SourceFile;
          Exit(True);
        end;
    DoLineFmt(RSDbgReplBpUnknownFile, [AText], COLOR_RED);
    Exit;
  end;
  try
    AFile := TUtils.ResolvePath(AText);
    Result := True;
  except
    on E: Exception do
      DoLineFmt(RSDbgReplBpBadPath, [AText, E.Message], COLOR_RED);
  end;
end;

procedure TPCDebugREPL.DoSendFile(const AFile: string);
var
  LLines: TList<Integer>;
  LResults: TArray<TPCBreakpointResult>;
  LResult: TPCBreakpointResult;
  LBreakpoint: TPCDebugReplBreakpoint;
  LI: Integer;
begin
  // The engine takes a file's whole set (DAP semantics): every line of
  // AFile once, then each breakpoint gets its line's answer
  if (FRuntime = nil) or FExited then
    Exit;
  LLines := TList<Integer>.Create();
  try
    for LBreakpoint in FBreakpoints do
      if TUtils.SamePath(LBreakpoint.FileName, AFile) and (not LLines.Contains(LBreakpoint.Line)) then
        LLines.Add(LBreakpoint.Line);
    LResults := FRuntime.SetBreakpoints(AFile, LLines.ToArray());
  finally
    LLines.Free();
  end;

  for LI := 0 to FBreakpoints.Count - 1 do
  begin
    LBreakpoint := FBreakpoints[LI];
    if not TUtils.SamePath(LBreakpoint.FileName, AFile) then
      Continue;
    for LResult in LResults do
      if LResult.RequestedLine = LBreakpoint.Line then
      begin
        LBreakpoint.IsPlaced := True;
        LBreakpoint.Placed := LResult;
        FBreakpoints[LI] := LBreakpoint;
        Break;
      end;
  end;
  DoShowReports();
end;

procedure TPCDebugREPL.DoSendAll();
var
  LFiles: TList<string>;
  LBreakpoint: TPCDebugReplBreakpoint;
  LFile: string;
  LKnown: Boolean;
begin
  LFiles := TList<string>.Create();
  try
    for LBreakpoint in FBreakpoints do
    begin
      LKnown := False;
      for LFile in LFiles do
        if TUtils.SamePath(LFile, LBreakpoint.FileName) then
        begin
          LKnown := True;
          Break;
        end;
      if not LKnown then
        LFiles.Add(LBreakpoint.FileName);
    end;
    for LFile in LFiles do
      DoSendFile(LFile);
  finally
    LFiles.Free();
  end;
end;

procedure TPCDebugREPL.DoTakeChanges();
var
  LResult: TPCBreakpointResult;
  LBreakpoint: TPCDebugReplBreakpoint;
  LI: Integer;
begin
  // A pending breakpoint the engine placed as its image loaded (a dll's)
  if FRuntime = nil then
    Exit;
  for LResult in FRuntime.TakeBreakpointChanges() do
    for LI := 0 to FBreakpoints.Count - 1 do
    begin
      LBreakpoint := FBreakpoints[LI];
      if LBreakpoint.IsPlaced and (LBreakpoint.Placed.Id = LResult.Id) then
      begin
        LBreakpoint.Placed := LResult;
        FBreakpoints[LI] := LBreakpoint;
        DoShowBreakpoint(LBreakpoint);
      end;
    end;
end;

procedure TPCDebugREPL.DoShowBreakpoint(const ABreakpoint: TPCDebugReplBreakpoint);
var
  LName: string;
begin
  LName := DoDisplayName(ABreakpoint.FileName);
  if not ABreakpoint.IsPlaced then
    DoLineFmt(RSDbgReplBpNextRun, [ABreakpoint.Number, LName, ABreakpoint.Line])
  else if not ABreakpoint.Placed.Verified then
    DoLineFmt(RSDbgReplBpPending, [ABreakpoint.Number, LName, ABreakpoint.Line,
      ABreakpoint.Placed.MessageText], COLOR_YELLOW)
  else if ABreakpoint.Placed.ActualLine <> ABreakpoint.Line then
    DoLineFmt(RSDbgReplBpMoved, [ABreakpoint.Number, LName, ABreakpoint.Line,
      ABreakpoint.Placed.ActualLine])
  else
    DoLineFmt(RSDbgReplBpSet, [ABreakpoint.Number, LName, ABreakpoint.Line]);
end;

{ TPCDebugREPL: commands }

procedure TPCDebugREPL.DoCommand(const ALine: string);
var
  LSpace: Integer;
  LVerb: string;
  LArg: string;
begin
  if ALine = '' then
    Exit;
  LSpace := ALine.IndexOf(' ');
  if LSpace < 0 then
  begin
    LVerb := ALine;
    LArg := '';
  end
  else
  begin
    LVerb := ALine.Substring(0, LSpace);
    LArg := ALine.Substring(LSpace + 1).Trim();
  end;

  if (LVerb = 'h') or (LVerb = 'help') then
    DoLine(RSDbgReplHelp)
  else if LVerb = 'b' then
    DoCmdBreak(LArg)
  else if LVerb = 'bl' then
    DoCmdList()
  else if LVerb = 'bd' then
    DoCmdDelete(LArg)
  else if LVerb = 'bc' then
    DoCmdClear()
  else if LVerb = 'c' then
    DoCmdRun(dstNone)
  else if LVerb = 'n' then
    DoCmdRun(dstOver)
  else if LVerb = 's' then
    DoCmdRun(dstIn)
  else if LVerb = 'finish' then
    DoCmdRun(dstOut)
  else if LVerb = 'bt' then
    DoCmdBacktrace()
  else if LVerb = 'f' then
    DoCmdFrame(LArg)
  else if LVerb = 'locals' then
    DoCmdLocals()
  else if LVerb = 'p' then
    DoCmdPrint(LArg)
  else if LVerb = 'src' then
    DoCmdSource()
  else if LVerb = 'threads' then
    DoCmdThreads()
  else if LVerb = 'r' then
    DoCmdRestart()
  else if (LVerb = 'q') or (LVerb = 'quit') then
    FQuit := True
  else
    DoLineFmt(RSDbgReplUnknown, [ALine], COLOR_RED);
end;

procedure TPCDebugREPL.DoCmdBreak(const AArg: string);
var
  LColon: Integer;
  LFileText: string;
  LLineText: string;
  LFile: string;
  LLine: Integer;
  LStack: TArray<TPCDebugStackItem>;
  LBreakpoint: TPCDebugReplBreakpoint;
begin
  // b <file>:<line> (the last ':' splits: a drive letter has one too), or
  // b <line>: the selected frame's file while stopped in .pcpp code, else
  // the main module's
  LColon := AArg.LastIndexOf(':');
  if LColon > 0 then
  begin
    LFileText := AArg.Substring(0, LColon).Trim();
    LLineText := AArg.Substring(LColon + 1).Trim();
  end
  else
  begin
    LFileText := '';
    LLineText := AArg.Trim();
  end;
  LLine := StrToIntDef(LLineText, 0);
  if LLine <= 0 then
  begin
    DoLine(RSDbgReplBpUsage, COLOR_RED);
    Exit;
  end;

  LFile := '';
  if LFileText <> '' then
  begin
    if not DoResolveFile(LFileText, LFile) then
      Exit;
  end
  else
  begin
    LStack := DoStack();
    if (FFrameIndex < Length(LStack)) and LStack[FFrameIndex].IsPcpp then
      LFile := LStack[FFrameIndex].FileName;
    if (LFile = '') and (FProgram <> nil) then
      LFile := FProgram.SourceFile;
    if LFile = '' then
    begin
      DoLine(RSDbgReplBpUsage, COLOR_RED);
      Exit;
    end;
  end;

  LBreakpoint := Default(TPCDebugReplBreakpoint);
  LBreakpoint.Number := FNextNumber;
  Inc(FNextNumber);
  LBreakpoint.FileName := LFile;
  LBreakpoint.Line := LLine;
  FBreakpoints.Add(LBreakpoint);
  DoSendFile(LFile);
  DoShowBreakpoint(FBreakpoints.Last());
end;

procedure TPCDebugREPL.DoCmdList();
var
  LBreakpoint: TPCDebugReplBreakpoint;
begin
  if FBreakpoints.Count = 0 then
  begin
    DoLine(RSDbgReplBpNone);
    Exit;
  end;
  for LBreakpoint in FBreakpoints do
    DoShowBreakpoint(LBreakpoint);
end;

procedure TPCDebugREPL.DoCmdDelete(const AArg: string);
var
  LNumber: Integer;
  LI: Integer;
  LFile: string;
begin
  LNumber := StrToIntDef(AArg.TrimLeft(['#']), 0);
  for LI := 0 to FBreakpoints.Count - 1 do
    if FBreakpoints[LI].Number = LNumber then
    begin
      LFile := FBreakpoints[LI].FileName;
      FBreakpoints.Delete(LI);
      DoSendFile(LFile);
      DoLineFmt(RSDbgReplBpDeleted, [LNumber]);
      Exit;
    end;
  DoLineFmt(RSDbgReplBpNoId, [AArg], COLOR_RED);
end;

procedure TPCDebugREPL.DoCmdClear();
var
  LFiles: TList<string>;
  LBreakpoint: TPCDebugReplBreakpoint;
  LFile: string;
begin
  // Each file that had a breakpoint gets an empty set
  LFiles := TList<string>.Create();
  try
    for LBreakpoint in FBreakpoints do
      if not LFiles.Contains(LBreakpoint.FileName) then
        LFiles.Add(LBreakpoint.FileName);
    FBreakpoints.Clear();
    if (FRuntime <> nil) and (not FExited) then
      for LFile in LFiles do
        FRuntime.SetBreakpoints(LFile, []);
  finally
    LFiles.Free();
  end;
  DoShowReports();
  DoLine(RSDbgReplBpCleared);
end;

procedure TPCDebugREPL.DoCmdRun(const AKind: TPCDebugStepKind);
var
  LOk: Boolean;
begin
  // c (dstNone), n, s, finish: then wait for the next stop or the end.
  // Held at its entry the program has no line to step from: c starts it,
  // a step is refused (DoNeedStop says why)
  if FAtEntry and (AKind = dstNone) and (FRuntime <> nil) and (not FExited) then
  begin
    DoRunFromEntry();
    Exit;
  end;
  if not DoNeedStop() then
    Exit;
  case AKind of
    dstIn:
      LOk := FRuntime.StepIn();
    dstOver:
      LOk := FRuntime.StepOver();
    dstOut:
      LOk := FRuntime.StepOut();
  else
    LOk := FRuntime.ContinueExecution();
  end;
  if not LOk then
  begin
    DoShowReports();
    Exit;
  end;
  DoWait();
end;

procedure TPCDebugREPL.DoCmdBacktrace();
var
  LStack: TArray<TPCDebugStackItem>;
  LIndex: Integer;
begin
  if not DoNeedStop() then
    Exit;
  LStack := DoStack();
  if Length(LStack) = 0 then
  begin
    DoLine(RSDbgReplNoFrames);
    Exit;
  end;
  for LIndex := 0 to High(LStack) do
    DoShowFrame(LIndex, LStack[LIndex]);
end;

procedure TPCDebugREPL.DoCmdFrame(const AArg: string);
var
  LStack: TArray<TPCDebugStackItem>;
  LIndex: Integer;
begin
  if not DoNeedStop() then
    Exit;
  LStack := DoStack();
  LIndex := StrToIntDef(AArg, -1);
  if (LIndex < 0) or (LIndex >= Length(LStack)) then
  begin
    DoLineFmt(RSDbgReplFrameBad, [AArg], COLOR_RED);
    Exit;
  end;
  FFrameIndex := LIndex;
  DoShowFrame(LIndex, LStack[LIndex]);
  if LStack[LIndex].FileName <> '' then
    DoShowSource(LStack[LIndex].FileName, LStack[LIndex].Line);
end;

procedure TPCDebugREPL.DoCmdLocals();
var
  LStack: TArray<TPCDebugStackItem>;
  LFrameId: Integer;
  LScopes: TArray<TPCDebugScopeKind>;
  LScope: TPCDebugScopeKind;
  LValues: TArray<TPCDebugValue>;
  LValue: TPCDebugValue;
begin
  if not DoNeedStop() then
    Exit;
  LStack := DoStack();
  if FFrameIndex >= Length(LStack) then
  begin
    DoLine(RSDbgReplNoFrames);
    Exit;
  end;
  LFrameId := LStack[FFrameIndex].FrameId;
  LScopes := FRuntime.Scopes(LFrameId);
  if Length(LScopes) = 0 then
    DoLine(RSDbgReplNoValues);
  for LScope in LScopes do
  begin
    case LScope of
      dskParams:
        DoLine(RSDbgReplScopeParams);
      dskLocals:
        DoLine(RSDbgReplScopeLocals);
      dskGlobals:
        DoLine(RSDbgReplScopeGlobals);
    end;
    LValues := FRuntime.Variables(LFrameId, LScope);
    if Length(LValues) = 0 then
      DoLine(RSDbgReplNoValues);
    for LValue in LValues do
    begin
      if LValue.TypeText <> '' then
        DoLineFmt(RSDbgReplValue, [LValue.DisplayName, LValue.TypeText, LValue.ValueText])
      else
        DoLineFmt(RSDbgReplValueNoType, [LValue.DisplayName, LValue.ValueText]);
    end;
  end;
  DoShowReports();
end;

procedure TPCDebugREPL.DoCmdPrint(const AArg: string);
var
  LStack: TArray<TPCDebugStackItem>;
  LValue: TPCDebugValue;
begin
  if AArg = '' then
  begin
    DoLine(RSDbgReplEvalUsage, COLOR_RED);
    Exit;
  end;
  if not DoNeedStop() then
    Exit;
  LStack := DoStack();
  if FFrameIndex >= Length(LStack) then
  begin
    DoLine(RSDbgReplNoFrames);
    Exit;
  end;
  // False = ValueText says why (TPCDebugRuntime.Evaluate)
  if FRuntime.Evaluate(LStack[FFrameIndex].FrameId, AArg, LValue) then
    DoLineFmt(RSDbgReplEval, [AArg, LValue.ValueText])
  else
    DoLine(LValue.ValueText, COLOR_RED);
  DoShowReports();
end;

procedure TPCDebugREPL.DoCmdSource();
var
  LStack: TArray<TPCDebugStackItem>;
begin
  if not DoNeedStop() then
    Exit;
  LStack := DoStack();
  if (FFrameIndex < Length(LStack)) and (LStack[FFrameIndex].FileName <> '') then
    DoShowSource(LStack[FFrameIndex].FileName, LStack[FFrameIndex].Line)
  else
    DoLine(RSDbgReplNoFrames);
end;

procedure TPCDebugREPL.DoCmdThreads();
var
  LThread: TPCDebugThread;
  LMark: string;
  LMain: string;
begin
  if not DoNeedStop() then
    Exit;
  for LThread in FRuntime.Threads() do
  begin
    if LThread.ThreadId = FRuntime.StoppedThread() then
      LMark := PC_DBG_REPL_MARK_THREAD
    else
      LMark := PC_DBG_REPL_MARK_NONE;
    if LThread.IsMain then
      LMain := RSDbgReplThreadMain
    else
      LMain := '';
    DoLineFmt(RSDbgReplThread, [LMark, Int64(LThread.ThreadId), LMain]);
  end;
end;

procedure TPCDebugREPL.DoCmdRestart();
begin
  // A new process with the same breakpoints (DoNewRuntime ends the old one)
  DoNewRuntime();
  DoStartSession();
end;

function TPCDebugREPL.Run(): Boolean;
begin
  FQuit := False;
  DoLine(RSDbgReplTitle, COLOR_CYAN);
  DoLineFmt(RSDbgReplProgram, [TUtils.StripLongPathPrefix(FImagePath)]);
  if FHostPath <> '' then
    DoLineFmt(RSDbgReplHost, [TUtils.StripLongPathPrefix(FHostPath)]);
  DoLine(RSDbgReplHint);

  // The console's Ctrl+C / Ctrl+Break are this REPL's for the session
  // (DoConsoleCtrl); a handler that cannot be added leaves the console's
  // default (Ctrl+C ends pcpp), nothing else changes
  GReplLock.Enter();
  try
    GActiveRepl := Self;
  finally
    GReplLock.Leave();
  end;
  SetConsoleCtrlHandler(@DoConsoleCtrl, True);
  try
    Result := DoSession();
  finally
    SetConsoleCtrlHandler(@DoConsoleCtrl, False);
    GReplLock.Enter();
    try
      GActiveRepl := nil;
    finally
      GReplLock.Leave();
    end;
  end;
end;

function TPCDebugREPL.DoSession(): Boolean;
var
  LLine: string;
  LHasLine: Boolean;
begin
  DoNewRuntime();
  DoAddSourceBreakpoints();
  Result := DoStartSession();
  if not Result then
  begin
    DoEndSession();
    Exit;
  end;

  while not FQuit do
  begin
    if not FAtLineStart then
      DoText(sLineBreak);
    if FColor then
      DoText(COLOR_CYAN + PC_DBG_REPL_PROMPT + COLOR_RESET)
    else
      DoText(PC_DBG_REPL_PROMPT);
    LHasLine := False;
    try
      LHasLine := FReader(LLine);
    except
      on E: Exception do
      begin
        FAtLineStart := False;
        DoLineFmt(RSDbgReplInputFailed, [E.Message], COLOR_RED);
      end;
    end;
    // The person's Enter ended the prompt's line
    FAtLineStart := True;
    if not LHasLine then
      Break;
    DoCommand(LLine.Trim());
  end;

  DoEndSession();
end;

initialization
  GReplLock := TCriticalSection.Create();
  GActiveRepl := nil;

finalization
  FreeAndNil(GReplLock);

end.
