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
  PaskalCPP.Debug.DAP - the debug adapter (pcpp --dap)

  Serves the Debug Adapter Protocol on a pair of streams (stdin / stdout for
  the editor, memory streams in the tests) over one TPCDebugRuntime, the
  engine the console debugger drives too. Framing is the LSP base protocol's
  (PaskalCPP.LSP.Transport: the same header block), reused, not copied.
  launch builds a .pcpp source debug first (TPCCompiler, as pcpp -d does),
  or takes a built exe, or a dll with the exe that loads it ("host"). The
  program's @breakpoint statements (TPCDebugRuntime.SourceBreakpoints, from
  the AST) are placed with the client's breakpoints of their file and are
  announced to the client as breakpoints of its own ("new").
  Requests: initialize, launch, setBreakpoints, setExceptionBreakpoints,
  configurationDone, threads, stackTrace, scopes, variables, continue, next,
  stepIn, stepOut, pause, evaluate, terminate, disconnect; PaskalCPP's own
  pcppTerminalInput (text) and pcppTerminalResize (cols, rows) (the program
  runs on a pseudo console: launch takes terminalCols / terminalRows). Events:
  initialized, stopped, output, breakpoint, thread, exited, terminated.
  Prior art: CPaskal.Debug.DAP.pas (CONCEPT: the request set and the
  initialized event; GEOMETRY rejected: no TCP server, no conditional
  breakpoints claimed (R7)).

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Resources,
    PaskalCPP.Common, PaskalCPP.ZigBuild, PaskalCPP.Compiler,
    PaskalCPP.LSP.Transport, PaskalCPP.Debug.Target, PaskalCPP.Debug.Runtime,
    StdApp.JSON (reads; messages are built with System.JSON)
  Notes:
    - One thread does everything but read: requests, the engine, every
      write. Run's reader thread only reads the input into a queue, so the
      program's events go out while no request comes.
    - stdout is the protocol: the build's status and reports and the
      program's output (the engine's output pipe) go out as output events.
    - A frame id or a variables reference is valid until the next resume.
===============================================================================}

unit PaskalCPP.Debug.DAP;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.JSON,
  PaskalCPP.Compiler,
  PaskalCPP.LSP.Transport,
  PaskalCPP.Debug.Target,
  PaskalCPP.Debug.Runtime;

const
  { PC_DAP_POLL_MS }
  // One wait for a request (Run), after which the engine's events go out
  PC_DAP_POLL_MS = 50;
  { PC_DAP_PUMP_MAX }
  // The most engine events one Pump sends before requests are read again
  PC_DAP_PUMP_MAX = 256;
  { PC_DAP_QUEUE_DEPTH }
  // Requests read ahead of the one being handled
  PC_DAP_QUEUE_DEPTH = 64;
  { PC_DAP_MAX_REPORTS }
  // The session's reports are sent and cleared after each step; this only
  // bounds one step's
  PC_DAP_MAX_REPORTS = 1000;
  { PC_DAP_READER_STOP_MS }
  // How long Run waits for its reader thread to stop at the end
  PC_DAP_READER_STOP_MS = 2000;
  { PC_DAP_EXIT_DISCONNECTED }
  // Run's exit code: the client disconnected
  PC_DAP_EXIT_DISCONNECTED = 0;
  { PC_DAP_EXIT_CLIENT_GONE }
  // Run's exit code: the input ended without a disconnect
  PC_DAP_EXIT_CLIENT_GONE = 1;
  { PC_DAP_FILTER_ALL }
  // The one exception filter: break on first chance exceptions too
  PC_DAP_FILTER_ALL = 'all';
  { PC_DAP_ERROR_NONE }
  // A failure response with no body.error: the client shows its message
  PC_DAP_ERROR_NONE = 0;
  { PC_DAP_ERROR_DLL_NO_HOST }
  // body.error.id of a launch refused because a dll has no host: the
  // editor then asks for the host exe (editor debug.js matches this
  // number). DAP's Message.id is a number, stable per meaning
  PC_DAP_ERROR_DLL_NO_HOST = 1;
  { PC_DAP_ERROR_HOST_ON_EXE }
  // body.error.id of a launch refused because "host" was given for an exe:
  // the editor forgets the host it remembered and launches without one
  PC_DAP_ERROR_HOST_ON_EXE = 2;

type
  { TPCDapRefKind }
  TPCDapRefKind = (
    drkScope,             // a frame's scope (Variables)
    drkChildren           // a value's children (Children)
  );

  { TPCDapRef }
  // What a variables reference (its index + 1) stands for
  TPCDapRef = record
    Kind: TPCDapRefKind;
    FrameId: Integer;
    Scope: TPCDebugScopeKind;
    ChildrenRef: Integer;
  end;

  { TPCDapFileLines }
  // The lines the client set in one file (setBreakpoints replaces them)
  TPCDapFileLines = record
    FileName: string;
    Lines: TArray<Integer>;
  end;

  { TPCDebugDAP }
  TPCDebugDAP = class(TBaseObject)
  private
    FSessionErrors: TErrors;
    FTransport: TPCLspTransport;
    FSeq: Integer;
    FFinished: Boolean;
    FCompiler: TPCCompiler;          // the build's: holds the AST the engine names from
    FRuntime: TPCDebugRuntime;
    FLaunched: Boolean;
    FExited: Boolean;
    FConfigured: Boolean;
    FFirstChance: Boolean;
    FClientFiles: TList<TPCDapFileLines>;
    FSourceLines: TArray<TPCDebugSourceLine>;
    FAnnounced: TList<Integer>;      // ids of @breakpoint lines sent as "new"
    FRefs: TList<TPCDapRef>;
    FThreads: TList<TPCDebugThread>;

    // output
    procedure DoSend(const AMessage: TJSONObject);
    procedure DoSendResponse(const ARequest: TJSON; const ASuccess: Boolean;
      const AMessage: string; const ABody: TJSONValue);
    procedure DoSendError(const ARequest: TJSON; const AErrorId: Integer;
      const AMessage: string);
    procedure DoSendEvent(const AEvent: string; const ABody: TJSONObject);
    procedure DoOutput(const ACategory: string; const AText: string);
    procedure DoSendReports();
    function DoTakeReportText(const AFallback: string): string;
    procedure DoSendCompilerErrors();
    function DoClientPath(const AFile: string): string;
    function DoSourceJson(const AFile: string): TJSONObject;
    function DoBreakpointJson(const AResult: TPCBreakpointResult): TJSONObject;

    // session
    function DoNeedLaunched(const ARequest: TJSON): Boolean;
    function DoNeedStop(const ARequest: TJSON): Boolean;
    procedure DoClearRefs();
    function DoAddRef(const ARef: TPCDapRef): Integer;
    procedure DoRefreshThreads();
    function DoThreadName(const AThread: TPCDebugThread): string;
    function DoFileIndex(const AFile: string): Integer;
    function DoPlaceFile(const AFile: string): TArray<TPCBreakpointResult>;
    procedure DoAnnounceSource(const AFile: string; const AResults: TArray<TPCBreakpointResult>);
    procedure DoSendChanges();
    procedure DoEndSession();

    // launch
    function DoArgs(const AArguments: TJSON; out AText: string): Boolean;
    function DoSizeArg(const AArguments: TJSON; const AName: string; var AValue: Integer): Boolean;
    function DoResolveArg(const AArguments: TJSON; const AName: string;
      out APath: string; out AFailure: string): Boolean;
    function DoBuild(const ASource: string; const AOutputPath: string; const AHost: string;
      out AImage: string; out AIsDll: Boolean; out AFailure: string; out AFailureId: Integer): Boolean;

    // engine events
    procedure DoOnEvent(const AEvent: TPCDebugEvent);
    procedure DoOnStopped(const AEvent: TPCDebugEvent);
    procedure DoOnThread(const AEvent: TPCDebugEvent);
    procedure DoOnExited(const AEvent: TPCDebugEvent);

    // requests
    procedure DoHandleRequest(const ARequest: TJSON; const ACommand: string;
      const AArguments: TJSON);
    procedure DoInitialize(const ARequest: TJSON);
    procedure DoLaunch(const ARequest: TJSON; const AArguments: TJSON);
    procedure DoSetBreakpoints(const ARequest: TJSON; const AArguments: TJSON);
    procedure DoSetExceptionBreakpoints(const ARequest: TJSON; const AArguments: TJSON);
    procedure DoConfigurationDone(const ARequest: TJSON);
    procedure DoThreads(const ARequest: TJSON);
    procedure DoStackTrace(const ARequest: TJSON; const AArguments: TJSON);
    procedure DoScopes(const ARequest: TJSON; const AArguments: TJSON);
    procedure DoVariables(const ARequest: TJSON; const AArguments: TJSON);
    procedure DoRunControl(const ARequest: TJSON; const ACommand: string);
    procedure DoPause(const ARequest: TJSON);
    procedure DoEvaluate(const ARequest: TJSON; const AArguments: TJSON);
    procedure DoTerminalInput(const ARequest: TJSON; const AArguments: TJSON);
    procedure DoTerminalResize(const ARequest: TJSON; const AArguments: TJSON);
    procedure DoTerminate(const ARequest: TJSON);
    procedure DoDisconnect(const ARequest: TJSON);
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Serves ATransport until disconnect or the end of its input:
    // PC_DAP_EXIT_DISCONNECTED or PC_DAP_EXIT_CLIENT_GONE
    function Run(const ATransport: TPCLspTransport): Integer;

    // The session as Run drives it (the tests drive it so too): Open sets
    // where messages are written, HandleMessage serves one message, Pump
    // sends the engine's events (waits up to ATimeoutMs for the first;
    // True when one went out)
    procedure Open(const ATransport: TPCLspTransport);
    procedure HandleMessage(const ABody: string);
    function Pump(const ATimeoutMs: Cardinal): Boolean;
    // disconnect was served
    function IsFinished(): Boolean;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.Common,
  PaskalCPP.ZigBuild,
  PaskalCPP.AST;

const
  { PC_DAP_CATEGORY_CONSOLE }
  // output event categories: the adapter's own lines, the program's output,
  // reports
  PC_DAP_CATEGORY_CONSOLE = 'console';
  { PC_DAP_CATEGORY_STDOUT }
  PC_DAP_CATEGORY_STDOUT = 'stdout';
  { PC_DAP_CATEGORY_STDERR }
  PC_DAP_CATEGORY_STDERR = 'stderr';
  { PC_DAP_TERMINAL_INPUT }
  // PaskalCPP's own requests (DAP has no stdin request): keys typed in the
  // client's terminal pane {text}, and its size {cols, rows}
  PC_DAP_TERMINAL_INPUT = 'pcppTerminalInput';
  { PC_DAP_TERMINAL_RESIZE }
  PC_DAP_TERMINAL_RESIZE = 'pcppTerminalResize';
  { PC_DAP_LINE_END }
  // An output event's line end (the client renders text as given)
  PC_DAP_LINE_END = #10;

type
  { TPCDapInput }
  // One read of the input as the reader thread hands it over
  TPCDapInput = record
    ReadResult: TPCLspReadResult;
    Body: string;
  end;

  { TPCDapReader }
  // Reads the input into the queue until it ends; touches nothing else
  TPCDapReader = class(TThread)
  private
    FTransport: TPCLspTransport;
    FQueue: TThreadedQueue<TPCDapInput>;
  protected
    procedure Execute(); override;
  public
    constructor Create(const ATransport: TPCLspTransport; const AQueue: TThreadedQueue<TPCDapInput>); reintroduce;
  end;

{ TPCDapReader }

constructor TPCDapReader.Create(const ATransport: TPCLspTransport; const AQueue: TThreadedQueue<TPCDapInput>);
begin
  FTransport := ATransport;
  FQueue := AQueue;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TPCDapReader.Execute();
var
  LInput: TPCDapInput;
begin
  // A read that fails (a cancelled read, a broken pipe) is the end of the
  // input (TPCLspTransport reads it so); a shut down queue takes nothing
  repeat
    LInput.Body := '';
    LInput.ReadResult := FTransport.ReadMessage(LInput.Body);
    if FQueue.PushItem(LInput) <> wrSignaled then
      Exit;
  until (LInput.ReadResult = rrEndOfStream) or Terminated;
end;

{ TPCDebugDAP }

constructor TPCDebugDAP.Create();
begin
  inherited;

  FSessionErrors := TErrors.Create();
  FSessionErrors.SetMaxErrors(PC_DAP_MAX_REPORTS);
  SetErrors(FSessionErrors);
  FTransport := nil;
  FSeq := 0;
  FFinished := False;
  FCompiler := nil;
  FRuntime := nil;
  FLaunched := False;
  FExited := False;
  FConfigured := False;
  FFirstChance := False;
  FClientFiles := TList<TPCDapFileLines>.Create();
  FSourceLines := nil;
  FAnnounced := TList<Integer>.Create();
  FRefs := TList<TPCDapRef>.Create();
  FThreads := TList<TPCDebugThread>.Create();
end;

destructor TPCDebugDAP.Destroy();
begin
  DoEndSession();
  FreeAndNil(FThreads);
  FreeAndNil(FRefs);
  FreeAndNil(FAnnounced);
  FreeAndNil(FClientFiles);
  FreeAndNil(FSessionErrors);

  inherited;
end;

procedure TPCDebugDAP.Open(const ATransport: TPCLspTransport);
begin
  FTransport := ATransport;
end;

function TPCDebugDAP.IsFinished(): Boolean;
begin
  Result := FFinished;
end;

function TPCDebugDAP.Run(const ATransport: TPCLspTransport): Integer;
var
  LQueue: TThreadedQueue<TPCDapInput>;
  LReader: TPCDapReader;
  LInput: TPCDapInput;
  LClientGone: Boolean;
  LStart: UInt64;
  LStopped: Boolean;
begin
  Open(ATransport);
  LClientGone := False;
  LQueue := TThreadedQueue<TPCDapInput>.Create(PC_DAP_QUEUE_DEPTH, INFINITE, PC_DAP_POLL_MS);
  LReader := TPCDapReader.Create(ATransport, LQueue);
  LStopped := False;
  try
    while not FFinished do
    begin
      // A request, or the poll's end: then the engine's events go out
      if LQueue.PopItem(LInput) = wrSignaled then
      begin
        if LInput.ReadResult = rrMessage then
          HandleMessage(LInput.Body)
        else if LInput.ReadResult = rrMalformed then
          DoOutput(PC_DAP_CATEGORY_STDERR, RSDbgDapMalformed + PC_DAP_LINE_END)
        else
        begin
          // The input ended without disconnect: the client is gone
          LClientGone := True;
          FFinished := True;
        end;
      end;
      if not FFinished then
        Pump(0);
    end;
  finally
    // The program does not outlive its debugger
    DoEndSession();
    // The reader may wait on a full queue or block in a read of stdin
    LQueue.DoShutDown();
    LReader.Terminate();
    LStart := TUtils.GetTickCount64();
    while TUtils.GetTickCount64() - LStart < PC_DAP_READER_STOP_MS do
    begin
      if WaitForSingleObject(LReader.Handle, PC_DAP_POLL_MS) = WAIT_OBJECT_0 then
      begin
        LStopped := True;
        Break;
      end;
      // Ends the reader's blocking read on stdin (Winapi.Windows)
      CancelSynchronousIo(LReader.Handle);
    end;
    // A reader that cannot be stopped still holds the queue: both are left
    // to the process's end rather than freed under it
    if LStopped then
    begin
      LReader.Free();
      LQueue.Free();
    end;
  end;

  if LClientGone then
    Result := PC_DAP_EXIT_CLIENT_GONE
  else
    Result := PC_DAP_EXIT_DISCONNECTED;
end;

procedure TPCDebugDAP.HandleMessage(const ABody: string);
var
  LRequest: TJSON;
  LType: string;
  LCommand: string;
begin
  // Text that is no JSON is no request either
  if not TJSON.TryFromString(ABody, LRequest) then
  begin
    DoOutput(PC_DAP_CATEGORY_STDERR, RSDbgDapNotRequest + PC_DAP_LINE_END);
    Exit;
  end;
  try
    // The client sends requests only (DAP: no responses to the adapter's
    // reverse requests, which it sends none of)
    if not (LRequest.IsObject() and LRequest.TryGetString('type', LType, True) and
      (LType = 'request') and LRequest.TryGetString('command', LCommand, True)) then
    begin
      DoOutput(PC_DAP_CATEGORY_STDERR, RSDbgDapNotRequest + PC_DAP_LINE_END);
      Exit;
    end;

    try
      // Absent arguments read as a null view: every read of it answers False
      DoHandleRequest(LRequest, LCommand, LRequest.Get('arguments', True));
    except
      // An invariant broke inside a handler: the request is still answered
      on E: Exception do
        DoSendResponse(LRequest, False, E.Message, nil);
    end;
    DoSendReports();
  finally
    LRequest.Free();
  end;
end;

function TPCDebugDAP.Pump(const ATimeoutMs: Cardinal): Boolean;
var
  LEvent: TPCDebugEvent;
  LWait: Cardinal;
  LCount: Integer;
begin
  Result := False;
  if (FRuntime = nil) or (not FLaunched) or FExited then
    Exit;

  // The first event may take ATimeoutMs; the ones already there follow at
  // once, a bounded number before requests are read again
  LWait := ATimeoutMs;
  LCount := 0;
  while (LCount < PC_DAP_PUMP_MAX) and (not FExited) and FRuntime.NextEvent(LEvent, LWait) do
  begin
    DoOnEvent(LEvent);
    Result := True;
    LWait := 0;
    Inc(LCount);
  end;
  // A pending breakpoint placed as its image loaded (inside NextEvent)
  if not FExited then
    DoSendChanges();
  DoSendReports();
end;

{ TPCDebugDAP: output }

procedure TPCDebugDAP.DoSend(const AMessage: TJSONObject);
var
  LText: string;
begin
  // Takes ownership of AMessage. Every message gets the next seq
  Inc(FSeq);
  try
    AMessage.AddPair('seq', TJSONNumber.Create(FSeq));
    LText := AMessage.ToJSON();
  finally
    AMessage.Free();
  end;
  // The client cannot be reached any more: the session ends as if it left
  if (FTransport <> nil) and (not FTransport.WriteMessage(LText)) then
    FFinished := True;
end;

procedure TPCDebugDAP.DoSendResponse(const ARequest: TJSON; const ASuccess: Boolean;
  const AMessage: string; const ABody: TJSONValue);
var
  LMessage: TJSONObject;
  LSeq: Integer;
  LCommand: string;
begin
  // Takes ownership of ABody (nil = none)
  LMessage := TJSONObject.Create();
  try
    LMessage.AddPair('type', 'response');
    // A seq that is no Integer answers as 0 (HandleMessage read the command)
    ARequest.TryGetInt32('seq', LSeq, True);
    LMessage.AddPair('request_seq', TJSONNumber.Create(LSeq));
    LMessage.AddPair('success', TJSONBool.Create(ASuccess));
    ARequest.TryGetString('command', LCommand, True);
    LMessage.AddPair('command', LCommand);
    if not ASuccess then
      LMessage.AddPair('message', AMessage);
    if ABody <> nil then
      LMessage.AddPair('body', ABody);
  except
    LMessage.Free();
    raise;
  end;
  DoSend(LMessage);
end;

procedure TPCDebugDAP.DoSendError(const ARequest: TJSON; const AErrorId: Integer;
  const AMessage: string);
var
  LBody: TJSONObject;
  LError: TJSONObject;
begin
  // A failure the client acts on: DAP's ErrorResponse body, error =
  // Message { id, format }. The client matches the id, never the text
  LBody := TJSONObject.Create();
  try
    LError := TJSONObject.Create();
    LBody.AddPair('error', LError);
    LError.AddPair('id', TJSONNumber.Create(AErrorId));
    LError.AddPair('format', AMessage);
  except
    LBody.Free();
    raise;
  end;
  DoSendResponse(ARequest, False, AMessage, LBody);
end;

procedure TPCDebugDAP.DoSendEvent(const AEvent: string; const ABody: TJSONObject);
var
  LMessage: TJSONObject;
begin
  // Takes ownership of ABody (nil = none)
  LMessage := TJSONObject.Create();
  LMessage.AddPair('type', 'event');
  LMessage.AddPair('event', AEvent);
  if ABody <> nil then
    LMessage.AddPair('body', ABody);
  DoSend(LMessage);
end;

procedure TPCDebugDAP.DoOutput(const ACategory: string; const AText: string);
var
  LBody: TJSONObject;
begin
  if AText = '' then
    Exit;
  LBody := TJSONObject.Create();
  LBody.AddPair('category', ACategory);
  LBody.AddPair('output', AText);
  DoSendEvent('output', LBody);
end;

procedure TPCDebugDAP.DoSendReports();
var
  LError: TError;
begin
  // What the engine reported since the last time, then forgotten: the
  // session runs as long as the client wants
  for LError in FSessionErrors.GetItems() do
  begin
    if LError.Severity in [esWarning, esError, esFatal] then
      DoOutput(PC_DAP_CATEGORY_STDERR, LError.ToIDEString() + PC_DAP_LINE_END)
    else
      DoOutput(PC_DAP_CATEGORY_CONSOLE, LError.ToIDEString() + PC_DAP_LINE_END);
  end;
  FSessionErrors.Clear();
end;

function TPCDebugDAP.DoTakeReportText(const AFallback: string): string;
var
  LError: TError;
begin
  // A failed request's message: the first warning or error the engine
  // reported for it (the rest go out as output), else AFallback
  Result := AFallback;
  for LError in FSessionErrors.GetItems() do
    if LError.Severity in [esWarning, esError, esFatal] then
    begin
      Result := LError.Message;
      Break;
    end;
  DoSendReports();
end;

procedure TPCDebugDAP.DoSendCompilerErrors();
var
  LError: TError;
begin
  // A build that failed: its errors (hints and warnings already went out
  // through the status callback, as at the command line)
  if FCompiler = nil then
    Exit;
  for LError in FCompiler.GetErrors().GetItems() do
    if LError.Severity in [esError, esFatal] then
      DoOutput(PC_DAP_CATEGORY_STDERR, LError.ToIDEString() + PC_DAP_LINE_END);
end;

function TPCDebugDAP.DoClientPath(const AFile: string): string;
begin
  // The plain Windows spelling (ResolvePath spells a short path with '/')
  Result := TUtils.StripLongPathPrefix(AFile).Replace('/', '\');
end;

function TPCDebugDAP.DoSourceJson(const AFile: string): TJSONObject;
var
  LPath: string;
begin
  LPath := DoClientPath(AFile);
  Result := TJSONObject.Create();
  Result.AddPair('name', TPath.GetFileName(LPath));
  Result.AddPair('path', LPath);
end;

function TPCDebugDAP.DoBreakpointJson(const AResult: TPCBreakpointResult): TJSONObject;
begin
  // A verified breakpoint shows where its code is (a line without code
  // moves forward); an unverified one where it was asked, with why
  Result := TJSONObject.Create();
  if AResult.Id > 0 then
    Result.AddPair('id', TJSONNumber.Create(AResult.Id));
  Result.AddPair('verified', TJSONBool.Create(AResult.Verified));
  if AResult.Verified then
    Result.AddPair('line', TJSONNumber.Create(AResult.ActualLine))
  else
    Result.AddPair('line', TJSONNumber.Create(AResult.RequestedLine));
  if AResult.FileName <> '' then
    Result.AddPair('source', DoSourceJson(AResult.FileName));
  if (not AResult.Verified) and (AResult.MessageText <> '') then
    Result.AddPair('message', AResult.MessageText);
end;

{ TPCDebugDAP: session }

function TPCDebugDAP.DoNeedLaunched(const ARequest: TJSON): Boolean;
begin
  Result := (FRuntime <> nil) and FLaunched and (not FExited);
  if not Result then
    DoSendResponse(ARequest, False, RSDbgDapNotLaunched, nil);
end;

function TPCDebugDAP.DoNeedStop(const ARequest: TJSON): Boolean;
begin
  // Inspection and run control need a live, stopped program
  Result := DoNeedLaunched(ARequest);
  if not Result then
    Exit;
  Result := FRuntime.IsStopped();
  if not Result then
    DoSendResponse(ARequest, False, RSDbgRunning, nil);
end;

procedure TPCDebugDAP.DoClearRefs();
begin
  // Frame ids and children references die with the stop (the engine's)
  FRefs.Clear();
end;

function TPCDebugDAP.DoAddRef(const ARef: TPCDapRef): Integer;
begin
  FRefs.Add(ARef);
  Result := FRefs.Count;
end;

procedure TPCDebugDAP.DoRefreshThreads();
var
  LThread: TPCDebugThread;
begin
  // The engine lists threads while the program is stopped; while it runs
  // the list kept follows the thread events
  if (FRuntime = nil) or FExited or (not FRuntime.IsStopped()) then
    Exit;
  FThreads.Clear();
  for LThread in FRuntime.Threads() do
    FThreads.Add(LThread);
end;

function TPCDebugDAP.DoThreadName(const AThread: TPCDebugThread): string;
begin
  if AThread.IsMain then
    Result := Format(RSDbgDapThreadMain, [Int64(AThread.ThreadId)])
  else
    Result := Format(RSDbgDapThread, [Int64(AThread.ThreadId)]);
end;

function TPCDebugDAP.DoFileIndex(const AFile: string): Integer;
var
  LIndex: Integer;
begin
  for LIndex := 0 to FClientFiles.Count - 1 do
    if TUtils.SamePath(FClientFiles[LIndex].FileName, AFile) then
      Exit(LIndex);
  Result := -1;
end;

function TPCDebugDAP.DoPlaceFile(const AFile: string): TArray<TPCBreakpointResult>;
var
  LLines: TList<Integer>;
  LIndex: Integer;
  LLine: Integer;
  LSource: TPCDebugSourceLine;
begin
  // The engine takes a file's whole set: the client's lines of AFile and
  // the program's @breakpoint lines of it, each once
  LLines := TList<Integer>.Create();
  try
    LIndex := DoFileIndex(AFile);
    if LIndex >= 0 then
      for LLine in FClientFiles[LIndex].Lines do
        if not LLines.Contains(LLine) then
          LLines.Add(LLine);
    for LSource in FSourceLines do
      if TUtils.SamePath(LSource.FileName, AFile) and (not LLines.Contains(LSource.Line)) then
        LLines.Add(LSource.Line);
    Result := FRuntime.SetBreakpoints(AFile, LLines.ToArray());
  finally
    LLines.Free();
  end;
  DoSendReports();
end;

procedure TPCDebugDAP.DoAnnounceSource(const AFile: string; const AResults: TArray<TPCBreakpointResult>);
var
  LSource: TPCDebugSourceLine;
  LResult: TPCBreakpointResult;
  LIndex: Integer;
  LLine: Integer;
  LClientHas: Boolean;
  LBody: TJSONObject;
begin
  // A @breakpoint line the client did not set is the program's own: the
  // client learns it once, as a new breakpoint
  LIndex := DoFileIndex(AFile);
  for LSource in FSourceLines do
  begin
    if not TUtils.SamePath(LSource.FileName, AFile) then
      Continue;
    LClientHas := False;
    if LIndex >= 0 then
      for LLine in FClientFiles[LIndex].Lines do
        if LLine = LSource.Line then
        begin
          LClientHas := True;
          Break;
        end;
    if LClientHas then
      Continue;
    for LResult in AResults do
      if (LResult.RequestedLine = LSource.Line) and (LResult.Id > 0) and
        (not FAnnounced.Contains(LResult.Id)) then
      begin
        FAnnounced.Add(LResult.Id);
        LBody := TJSONObject.Create();
        LBody.AddPair('reason', 'new');
        LBody.AddPair('breakpoint', DoBreakpointJson(LResult));
        DoSendEvent('breakpoint', LBody);
        Break;
      end;
  end;
end;

procedure TPCDebugDAP.DoSendChanges();
var
  LResult: TPCBreakpointResult;
  LBody: TJSONObject;
begin
  // A pending breakpoint the engine placed as its image loaded (a dll's)
  if FRuntime = nil then
    Exit;
  for LResult in FRuntime.TakeBreakpointChanges() do
  begin
    LBody := TJSONObject.Create();
    LBody.AddPair('reason', 'changed');
    LBody.AddPair('breakpoint', DoBreakpointJson(LResult));
    DoSendEvent('breakpoint', LBody);
  end;
end;

procedure TPCDebugDAP.DoEndSession();
begin
  // The program ends with the session; the build (its AST) after the engine
  if FRuntime <> nil then
  begin
    if FLaunched and (not FExited) then
      FRuntime.Terminate();
    FreeAndNil(FRuntime);
  end;
  FreeAndNil(FCompiler);
  FLaunched := False;
  FConfigured := False;
  FRefs.Clear();
  FThreads.Clear();
  FAnnounced.Clear();
  FSourceLines := nil;
  DoSendReports();
end;

{ TPCDebugDAP: launch }

function TPCDebugDAP.DoArgs(const AArguments: TJSON; out AText: string): Boolean;
var
  LArray: TJSON;
  LItem: TJSON;
  LArg: string;
begin
  // "args": the program's arguments, each one quoted only when it must be;
  // absent = none
  AText := '';
  Result := True;
  if not AArguments.Has('args', True) then
    Exit;
  if not AArguments.TryGetArray('args', LArray, True) then
    Exit(False);
  for LItem in LArray.Items() do
  begin
    if not LItem.TryGetString('', LArg) then
      Exit(False);
    if AText <> '' then
      AText := AText + ' ';
    AText := AText + TUtils.QuoteCommandArg(LArg);
  end;
end;

function TPCDebugDAP.DoSizeArg(const AArguments: TJSON; const AName: string;
  var AValue: Integer): Boolean;
var
  LValue: Integer;
begin
  // A terminal size argument: absent keeps AValue; present it must be a
  // whole number of at least 1
  Result := True;
  if not AArguments.Has(AName) then
    Exit;
  if (not AArguments.TryGetInt32(AName, LValue)) or (LValue < 1) then
    Exit(False);
  AValue := LValue;
end;

function TPCDebugDAP.DoResolveArg(const AArguments: TJSON; const AName: string;
  out APath: string; out AFailure: string): Boolean;
var
  LText: string;
begin
  // A path argument: True with APath resolved, or with APath '' when it is
  // absent; False (AFailure says why) when it is not a usable path
  APath := '';
  AFailure := '';
  Result := True;
  if not AArguments.Has(AName) then
    Exit;
  if (not AArguments.TryGetString(AName, LText)) or (LText.Trim() = '') then
  begin
    AFailure := Format(RSDbgDapBadArgument, ['launch', AName]);
    Exit(False);
  end;
  try
    APath := TUtils.ResolvePath(LText);
  except
    on E: Exception do
    begin
      AFailure := Format(RSDbgDapBadPath, [LText, E.Message]);
      Result := False;
    end;
  end;
end;

function TPCDebugDAP.DoBuild(const ASource: string; const AOutputPath: string; const AHost: string;
  out AImage: string; out AIsDll: Boolean; out AFailure: string; out AFailureId: Integer): Boolean;
var
  LMode: TPCBuildMode;
begin
  // As pcpp <file> -d: a debug build (an override: it wins over @optimize),
  // the target and the kind of program checked before anything is built.
  // AFailureId: the body.error id of a failure the client acts on
  Result := False;
  AImage := '';
  AIsDll := False;
  AFailure := RSDbgDapBuildFailed;
  AFailureId := PC_DAP_ERROR_NONE;
  FCompiler := TPCCompiler.Create();
  // stdout is the protocol: the build's status lines go to the client
  FCompiler.SetStatusCallback(
    procedure(const AText: string; const AUserData: Pointer)
    begin
      DoOutput(PC_DAP_CATEGORY_CONSOLE, TUtils.StripAnsi(AText) + PC_DAP_LINE_END);
    end, nil);
  FCompiler.SetKeyValue(PC_CMP_KEY_OPTIMIZE, PC_CMP_OPTIMIZE_TEXT[olDebug]);
  if not FCompiler.Prepare(ASource, AOutputPath) then
  begin
    DoSendCompilerErrors();
    Exit;
  end;
  if not TPCDebugRuntime.SupportsTarget(FCompiler.GetTarget()) then
  begin
    AFailure := Format(RSDbgNotWin64, [PC_DBG_TARGET, FCompiler.GetTarget()]);
    Exit;
  end;

  // An exe runs on its own; a dll runs in the exe that loads it ("host")
  LMode := FCompiler.GetBuildMode();
  if LMode = bmLib then
  begin
    AFailure := RSDbgDapLib;
    Exit;
  end;
  if (LMode = bmDll) and (AHost = '') then
  begin
    AFailure := RSDbgDapDllNoHost;
    AFailureId := PC_DAP_ERROR_DLL_NO_HOST;
    Exit;
  end;
  if (LMode = bmExe) and (AHost <> '') then
  begin
    AFailure := RSDbgDapHostOnExe;
    AFailureId := PC_DAP_ERROR_HOST_ON_EXE;
    Exit;
  end;

  if not FCompiler.Build(False) then
  begin
    DoSendCompilerErrors();
    Exit;
  end;
  AImage := FCompiler.GetArtifactPath();
  AIsDll := LMode = bmDll;
  Result := True;
end;

procedure TPCDebugDAP.DoLaunch(const ARequest: TJSON; const AArguments: TJSON);
var
  LProgram: string;
  LHost: string;
  LOutputPath: string;
  LArgs: string;
  LImage: string;
  LIsDll: Boolean;
  LFailure: string;
  LFailureId: Integer;
  LMain: TPCModule;
  LFile: TPCDapFileLines;
  LCols: Integer;
  LRows: Integer;
begin
  if FLaunched then
  begin
    DoSendResponse(ARequest, False, RSDbgDapLaunchTwice, nil);
    Exit;
  end;

  // "program" (required), "host", "outputPath", "args"
  if not DoResolveArg(AArguments, 'program', LProgram, LFailure) then
  begin
    DoSendResponse(ARequest, False, LFailure, nil);
    Exit;
  end;
  if LProgram = '' then
  begin
    DoSendResponse(ARequest, False, RSDbgDapNoProgram, nil);
    Exit;
  end;
  if (not DoResolveArg(AArguments, 'host', LHost, LFailure)) or
    (not DoResolveArg(AArguments, 'outputPath', LOutputPath, LFailure)) then
  begin
    DoSendResponse(ARequest, False, LFailure, nil);
    Exit;
  end;
  if not DoArgs(AArguments, LArgs) then
  begin
    DoSendResponse(ARequest, False, Format(RSDbgDapBadArgument, ['launch', 'args']), nil);
    Exit;
  end;
  // "terminalCols" / "terminalRows": the client's terminal pane (optional)
  LCols := PC_DBG_TERMINAL_COLS;
  LRows := PC_DBG_TERMINAL_ROWS;
  if not DoSizeArg(AArguments, 'terminalCols', LCols) then
  begin
    DoSendResponse(ARequest, False, Format(RSDbgDapBadArgument, ['launch', 'terminalCols']), nil);
    Exit;
  end;
  if not DoSizeArg(AArguments, 'terminalRows', LRows) then
  begin
    DoSendResponse(ARequest, False, Format(RSDbgDapBadArgument, ['launch', 'terminalRows']), nil);
    Exit;
  end;

  // A .pcpp source is built debug first (its AST names the variables); a
  // built image is debugged with C++ names (no sources)
  LMain := nil;
  if SameText(TPath.GetExtension(LProgram), '.' + PC_SRC_EXT) then
  begin
    if not DoBuild(LProgram, LOutputPath, LHost, LImage, LIsDll, LFailure, LFailureId) then
    begin
      FreeAndNil(FCompiler);
      if LFailureId <> PC_DAP_ERROR_NONE then
        DoSendError(ARequest, LFailureId, LFailure)
      else
        DoSendResponse(ARequest, False, LFailure, nil);
      Exit;
    end;
    LMain := FCompiler.GetMainModule();
  end
  else
  begin
    LImage := LProgram;
    LIsDll := SameText(TPath.GetExtension(LProgram), '.dll');
    if LIsDll and (LHost = '') then
    begin
      DoSendError(ARequest, PC_DAP_ERROR_DLL_NO_HOST, RSDbgDapDllNoHost);
      Exit;
    end;
    if (not LIsDll) and (LHost <> '') then
    begin
      DoSendError(ARequest, PC_DAP_ERROR_HOST_ON_EXE, RSDbgDapHostOnExe);
      Exit;
    end;
  end;

  FRuntime := TPCDebugRuntime.Create();
  FRuntime.SetErrors(FSessionErrors);
  FRuntime.SetProgram(LMain);
  if LIsDll then
    FRuntime.SetHostTarget(LImage, LHost, LArgs)
  else
    FRuntime.SetTarget(LImage, LArgs);
  // The program runs on a terminal (a pseudo console) the client shows:
  // its text comes as output events (category stdout, VT sequences kept),
  // the client's keys and size go back as pcppTerminalInput /
  // pcppTerminalResize. stdout itself is the protocol
  FRuntime.SetOutputMode(domTerminal);
  FRuntime.SetTerminalSize(LCols, LRows);
  FRuntime.SetBreakOnFirstChance(FFirstChance);
  if not FRuntime.Launch() then
  begin
    LFailure := DoTakeReportText(RSDbgDapLaunchFailed);
    FreeAndNil(FRuntime);
    FreeAndNil(FCompiler);
    DoSendResponse(ARequest, False, LFailure, nil);
    Exit;
  end;

  // Held at its entry: breakpoints go in until configurationDone
  FLaunched := True;
  FExited := False;
  FConfigured := False;
  FSourceLines := FRuntime.SourceBreakpoints();
  DoRefreshThreads();
  for LFile in FClientFiles.ToArray() do
    DoPlaceFile(LFile.FileName);
  DoSendReports();
  DoSendResponse(ARequest, True, '', nil);
  DoSendEvent('initialized', nil);
end;

{ TPCDebugDAP: requests }

procedure TPCDebugDAP.DoHandleRequest(const ARequest: TJSON; const ACommand: string;
  const AArguments: TJSON);
begin
  if ACommand = 'initialize' then
    DoInitialize(ARequest)
  else if ACommand = 'launch' then
    DoLaunch(ARequest, AArguments)
  else if ACommand = 'setBreakpoints' then
    DoSetBreakpoints(ARequest, AArguments)
  else if ACommand = 'setExceptionBreakpoints' then
    DoSetExceptionBreakpoints(ARequest, AArguments)
  else if ACommand = 'configurationDone' then
    DoConfigurationDone(ARequest)
  else if ACommand = 'threads' then
    DoThreads(ARequest)
  else if ACommand = 'stackTrace' then
    DoStackTrace(ARequest, AArguments)
  else if ACommand = 'scopes' then
    DoScopes(ARequest, AArguments)
  else if ACommand = 'variables' then
    DoVariables(ARequest, AArguments)
  else if (ACommand = 'continue') or (ACommand = 'next') or (ACommand = 'stepIn') or
    (ACommand = 'stepOut') then
    DoRunControl(ARequest, ACommand)
  else if ACommand = 'pause' then
    DoPause(ARequest)
  else if ACommand = 'evaluate' then
    DoEvaluate(ARequest, AArguments)
  else if ACommand = PC_DAP_TERMINAL_INPUT then
    DoTerminalInput(ARequest, AArguments)
  else if ACommand = PC_DAP_TERMINAL_RESIZE then
    DoTerminalResize(ARequest, AArguments)
  else if ACommand = 'terminate' then
    DoTerminate(ARequest)
  else if ACommand = 'disconnect' then
    DoDisconnect(ARequest)
  else
    DoSendResponse(ARequest, False, Format(RSDbgDapUnknownCommand, [ACommand]), nil);
end;

procedure TPCDebugDAP.DoInitialize(const ARequest: TJSON);
var
  LBody: TJSONObject;
  LFilters: TJSONArray;
  LFilter: TJSONObject;
begin
  // What this adapter does: breakpoints by line only (no conditions, hit
  // counts or function breakpoints: R7 not ported), values read only
  LBody := TJSONObject.Create();
  LBody.AddPair('supportsConfigurationDoneRequest', TJSONBool.Create(True));
  LBody.AddPair('supportsEvaluateForHovers', TJSONBool.Create(True));
  LBody.AddPair('supportsTerminateRequest', TJSONBool.Create(True));
  LBody.AddPair('supportsConditionalBreakpoints', TJSONBool.Create(False));
  LBody.AddPair('supportsHitConditionalBreakpoints', TJSONBool.Create(False));
  LBody.AddPair('supportsFunctionBreakpoints', TJSONBool.Create(False));
  LBody.AddPair('supportsSetVariable', TJSONBool.Create(False));
  LBody.AddPair('supportsStepBack', TJSONBool.Create(False));
  LBody.AddPair('supportsRestartFrame', TJSONBool.Create(False));
  LFilters := TJSONArray.Create();
  LFilter := TJSONObject.Create();
  LFilter.AddPair('filter', PC_DAP_FILTER_ALL);
  LFilter.AddPair('label', RSDbgDapExceptionAll);
  LFilter.AddPair('default', TJSONBool.Create(False));
  LFilters.AddElement(LFilter);
  LBody.AddPair('exceptionBreakpointFilters', LFilters);
  DoSendResponse(ARequest, True, '', LBody);
end;

procedure TPCDebugDAP.DoSetBreakpoints(const ARequest: TJSON; const AArguments: TJSON);
var
  LText: string;
  LFile: string;
  LArray: TJSON;
  LItem: TJSON;
  LLine: Integer;
  LLines: TList<Integer>;
  LEntry: TPCDapFileLines;
  LIndex: Integer;
  LResults: TArray<TPCBreakpointResult>;
  LResult: TPCBreakpointResult;
  LFound: TPCBreakpointResult;
  LBreakpoints: TJSONArray;
  LBody: TJSONObject;
  LPlaced: Boolean;
begin
  // A file's whole set, as the client has it now
  if (not AArguments.TryGetString('source.path', LText)) or (LText.Trim() = '') then
  begin
    DoSendResponse(ARequest, False, Format(RSDbgDapBadArgument, ['setBreakpoints', 'source.path']), nil);
    Exit;
  end;
  try
    LFile := TUtils.ResolvePath(LText);
  except
    on E: Exception do
    begin
      DoSendResponse(ARequest, False, Format(RSDbgDapBadPath, [LText, E.Message]), nil);
      Exit;
    end;
  end;

  LLines := TList<Integer>.Create();
  try
    // Absent = none; present it must be an array of {line >= 1}: a value
    // that is no list must not clear the file's set
    if AArguments.TryGetArray('breakpoints', LArray) then
    begin
      for LItem in LArray.Items() do
      begin
        if (not LItem.TryGetInt32('line', LLine)) or (LLine < 1) then
        begin
          DoSendResponse(ARequest, False, Format(RSDbgDapBadArgument, ['setBreakpoints', 'breakpoints']), nil);
          Exit;
        end;
        LLines.Add(LLine);
      end;
    end
    else if AArguments.Has('breakpoints') then
    begin
      DoSendResponse(ARequest, False, Format(RSDbgDapBadArgument, ['setBreakpoints', 'breakpoints']), nil);
      Exit;
    end;
    LEntry.FileName := LFile;
    LEntry.Lines := LLines.ToArray();
  finally
    LLines.Free();
  end;
  LIndex := DoFileIndex(LFile);
  if LIndex >= 0 then
    FClientFiles[LIndex] := LEntry
  else
    FClientFiles.Add(LEntry);

  // Placed now when a program runs; else when launch starts it
  LPlaced := (FRuntime <> nil) and FLaunched and (not FExited);
  LResults := nil;
  if LPlaced then
    LResults := DoPlaceFile(LFile);

  LBreakpoints := TJSONArray.Create();
  for LLine in LEntry.Lines do
  begin
    LFound := Default(TPCBreakpointResult);
    LFound.FileName := LFile;
    LFound.RequestedLine := LLine;
    LFound.MessageText := RSDbgDapNotLaunched;
    for LResult in LResults do
      if LResult.RequestedLine = LLine then
      begin
        LFound := LResult;
        Break;
      end;
    LBreakpoints.AddElement(DoBreakpointJson(LFound));
  end;
  LBody := TJSONObject.Create();
  LBody.AddPair('breakpoints', LBreakpoints);
  DoSendResponse(ARequest, True, '', LBody);
  if LPlaced then
    DoAnnounceSource(LFile, LResults);
end;

procedure TPCDebugDAP.DoSetExceptionBreakpoints(const ARequest: TJSON; const AArguments: TJSON);
var
  LArray: TJSON;
  LItem: TJSON;
  LFilter: string;
  LFirstChance: Boolean;
begin
  // "all" = first chance exceptions stop too; a second chance always does.
  // "filters" is a list of names: anything else is a bad argument, and the
  // setting stays as it was
  LFirstChance := False;
  if AArguments.TryGetArray('filters', LArray) then
  begin
    for LItem in LArray.Items() do
    begin
      if not LItem.TryGetString('', LFilter) then
      begin
        DoSendResponse(ARequest, False,
          Format(RSDbgDapBadArgument, ['setExceptionBreakpoints', 'filters']), nil);
        Exit;
      end;
      if LFilter = PC_DAP_FILTER_ALL then
        LFirstChance := True;
    end;
  end
  else if AArguments.Has('filters') then
  begin
    DoSendResponse(ARequest, False,
      Format(RSDbgDapBadArgument, ['setExceptionBreakpoints', 'filters']), nil);
    Exit;
  end;
  FFirstChance := LFirstChance;
  if FRuntime <> nil then
    FRuntime.SetBreakOnFirstChance(FFirstChance);
  DoSendResponse(ARequest, True, '', nil);
end;

procedure TPCDebugDAP.DoConfigurationDone(const ARequest: TJSON);
var
  LSource: TPCDebugSourceLine;
  LDone: TList<string>;
  LKnown: Boolean;
  LFile: string;
begin
  if not DoNeedLaunched(ARequest) then
    Exit;
  // The @breakpoint lines of files the client set nothing in
  LDone := TList<string>.Create();
  try
    for LSource in FSourceLines do
    begin
      if DoFileIndex(LSource.FileName) >= 0 then
        Continue;
      LKnown := False;
      for LFile in LDone do
        if TUtils.SamePath(LFile, LSource.FileName) then
        begin
          LKnown := True;
          Break;
        end;
      if LKnown then
        Continue;
      LDone.Add(LSource.FileName);
      DoAnnounceSource(LSource.FileName, DoPlaceFile(LSource.FileName));
    end;
  finally
    LDone.Free();
  end;

  // Held at the entry until now
  if not FConfigured then
  begin
    if not FRuntime.ConfigurationDone() then
    begin
      DoSendResponse(ARequest, False, DoTakeReportText(Format(RSDbgDapRequestFailed,
        ['configurationDone'])), nil);
      Exit;
    end;
    FConfigured := True;
    DoClearRefs();
  end;
  DoSendResponse(ARequest, True, '', nil);
end;

procedure TPCDebugDAP.DoThreads(const ARequest: TJSON);
var
  LThreads: TJSONArray;
  LThread: TPCDebugThread;
  LItem: TJSONObject;
  LBody: TJSONObject;
begin
  // No program = no threads (not an error: clients ask at any time)
  DoRefreshThreads();
  LThreads := TJSONArray.Create();
  if FLaunched and (not FExited) then
    for LThread in FThreads do
    begin
      LItem := TJSONObject.Create();
      LItem.AddPair('id', TJSONNumber.Create(Int64(LThread.ThreadId)));
      LItem.AddPair('name', DoThreadName(LThread));
      LThreads.AddElement(LItem);
    end;
  LBody := TJSONObject.Create();
  LBody.AddPair('threads', LThreads);
  DoSendResponse(ARequest, True, '', LBody);
end;

procedure TPCDebugDAP.DoStackTrace(const ARequest: TJSON; const AArguments: TJSON);
var
  LThreadId: Integer;
  LStart: Integer;
  LLevels: Integer;
  LStack: TArray<TPCDebugStackItem>;
  LIndex: Integer;
  LItem: TPCDebugStackItem;
  LFrames: TJSONArray;
  LFrame: TJSONObject;
  LBody: TJSONObject;
begin
  if not DoNeedStop(ARequest) then
    Exit;
  if not AArguments.TryGetInt32('threadId', LThreadId) then
    LThreadId := Integer(FRuntime.StoppedThread());
  if (not AArguments.TryGetInt32('startFrame', LStart)) or (LStart < 0) then
    LStart := 0;
  // levels 0 or absent = every frame
  if (not AArguments.TryGetInt32('levels', LLevels)) or (LLevels < 0) then
    LLevels := 0;

  LStack := FRuntime.StackTrace(Cardinal(LThreadId));
  LFrames := TJSONArray.Create();
  for LIndex := LStart to High(LStack) do
  begin
    if (LLevels > 0) and (LIndex - LStart >= LLevels) then
      Break;
    LItem := LStack[LIndex];
    LFrame := TJSONObject.Create();
    LFrame.AddPair('id', TJSONNumber.Create(LItem.FrameId));
    LFrame.AddPair('name', LItem.RoutineName);
    if LItem.FileName <> '' then
    begin
      LFrame.AddPair('source', DoSourceJson(LItem.FileName));
      LFrame.AddPair('line', TJSONNumber.Create(LItem.Line));
      LFrame.AddPair('column', TJSONNumber.Create(1));
    end
    else
    begin
      LFrame.AddPair('line', TJSONNumber.Create(0));
      LFrame.AddPair('column', TJSONNumber.Create(0));
    end;
    // Runtime, C, C++ and system frames: shown dimmed (W3)
    if not LItem.IsPcpp then
      LFrame.AddPair('presentationHint', 'subtle');
    LFrames.AddElement(LFrame);
  end;
  LBody := TJSONObject.Create();
  LBody.AddPair('stackFrames', LFrames);
  LBody.AddPair('totalFrames', TJSONNumber.Create(Length(LStack)));
  DoSendResponse(ARequest, True, '', LBody);
end;

procedure TPCDebugDAP.DoScopes(const ARequest: TJSON; const AArguments: TJSON);
var
  LFrameId: Integer;
  LKind: TPCDebugScopeKind;
  LRef: TPCDapRef;
  LScopes: TJSONArray;
  LScope: TJSONObject;
  LBody: TJSONObject;
begin
  if not DoNeedStop(ARequest) then
    Exit;
  if not AArguments.TryGetInt32('frameId', LFrameId) then
  begin
    DoSendResponse(ARequest, False, Format(RSDbgDapBadArgument, ['scopes', 'frameId']), nil);
    Exit;
  end;
  LScopes := TJSONArray.Create();
  for LKind in FRuntime.Scopes(LFrameId) do
  begin
    LRef := Default(TPCDapRef);
    LRef.Kind := drkScope;
    LRef.FrameId := LFrameId;
    LRef.Scope := LKind;
    LScope := TJSONObject.Create();
    case LKind of
      dskParams:
        begin
          LScope.AddPair('name', RSDbgDapScopeParams);
          LScope.AddPair('presentationHint', 'arguments');
        end;
      dskLocals:
        begin
          LScope.AddPair('name', RSDbgDapScopeLocals);
          LScope.AddPair('presentationHint', 'locals');
        end;
    else
      LScope.AddPair('name', RSDbgDapScopeGlobals);
    end;
    LScope.AddPair('variablesReference', TJSONNumber.Create(DoAddRef(LRef)));
    LScope.AddPair('expensive', TJSONBool.Create(False));
    LScopes.AddElement(LScope);
  end;
  LBody := TJSONObject.Create();
  LBody.AddPair('scopes', LScopes);
  DoSendResponse(ARequest, True, '', LBody);
end;

procedure TPCDebugDAP.DoVariables(const ARequest: TJSON; const AArguments: TJSON);
var
  LReference: Integer;
  LRef: TPCDapRef;
  LValues: TArray<TPCDebugValue>;
  LValue: TPCDebugValue;
  LChild: TPCDapRef;
  LVariables: TJSONArray;
  LVariable: TJSONObject;
  LBody: TJSONObject;
begin
  if not DoNeedStop(ARequest) then
    Exit;
  if (not AArguments.TryGetInt32('variablesReference', LReference)) or (LReference < 1) or
    (LReference > FRefs.Count) then
  begin
    DoSendResponse(ARequest, False, Format(RSDbgDapBadReference, [LReference]), nil);
    Exit;
  end;
  LRef := FRefs[LReference - 1];
  if LRef.Kind = drkScope then
    LValues := FRuntime.Variables(LRef.FrameId, LRef.Scope)
  else
    LValues := FRuntime.Children(LRef.ChildrenRef);

  LVariables := TJSONArray.Create();
  for LValue in LValues do
  begin
    LVariable := TJSONObject.Create();
    LVariable.AddPair('name', LValue.DisplayName);
    LVariable.AddPair('value', LValue.ValueText);
    LVariable.AddPair('type', LValue.TypeText);
    if LValue.ChildrenRef <> 0 then
    begin
      LChild := Default(TPCDapRef);
      LChild.Kind := drkChildren;
      LChild.ChildrenRef := LValue.ChildrenRef;
      LVariable.AddPair('variablesReference', TJSONNumber.Create(DoAddRef(LChild)));
    end
    else
      LVariable.AddPair('variablesReference', TJSONNumber.Create(0));
    LVariables.AddElement(LVariable);
  end;
  LBody := TJSONObject.Create();
  LBody.AddPair('variables', LVariables);
  DoSendResponse(ARequest, True, '', LBody);
end;

procedure TPCDebugDAP.DoRunControl(const ARequest: TJSON; const ACommand: string);
var
  LOk: Boolean;
  LBody: TJSONObject;
begin
  if not DoNeedLaunched(ARequest) then
    Exit;
  if ACommand = 'continue' then
    LOk := FRuntime.ContinueExecution()
  else if ACommand = 'next' then
    LOk := FRuntime.StepOver()
  else if ACommand = 'stepIn' then
    LOk := FRuntime.StepIn()
  else
    LOk := FRuntime.StepOut();
  if not LOk then
  begin
    DoSendResponse(ARequest, False, DoTakeReportText(Format(RSDbgDapRequestFailed, [ACommand])), nil);
    Exit;
  end;
  // The program runs: what was read at the stop is gone
  DoClearRefs();
  LBody := nil;
  if ACommand = 'continue' then
  begin
    LBody := TJSONObject.Create();
    LBody.AddPair('allThreadsContinued', TJSONBool.Create(True));
  end;
  DoSendResponse(ARequest, True, '', LBody);
end;

procedure TPCDebugDAP.DoPause(const ARequest: TJSON);
begin
  if not DoNeedLaunched(ARequest) then
    Exit;
  // The stop comes as a stopped event (pause)
  if not FRuntime.Pause() then
  begin
    DoSendResponse(ARequest, False, DoTakeReportText(Format(RSDbgDapRequestFailed, ['pause'])), nil);
    Exit;
  end;
  DoSendResponse(ARequest, True, '', nil);
end;

procedure TPCDebugDAP.DoTerminalInput(const ARequest: TJSON; const AArguments: TJSON);
var
  LText: string;
begin
  // Keys typed in the client's terminal pane, as the terminal spells them
  // (Enter = #13): to the program, running or stopped
  if not DoNeedLaunched(ARequest) then
    Exit;
  if not AArguments.TryGetString('text', LText) then
  begin
    DoSendResponse(ARequest, False, Format(RSDbgDapBadArgument, [PC_DAP_TERMINAL_INPUT, 'text']), nil);
    Exit;
  end;
  if not FRuntime.WriteInput(LText) then
  begin
    DoSendResponse(ARequest, False, Format(RSDbgDapRequestFailed, [PC_DAP_TERMINAL_INPUT]), nil);
    Exit;
  end;
  DoSendResponse(ARequest, True, '', nil);
end;

procedure TPCDebugDAP.DoTerminalResize(const ARequest: TJSON; const AArguments: TJSON);
var
  LCols: Integer;
  LRows: Integer;
begin
  // The client's terminal pane changed size: the program's terminal follows
  if not DoNeedLaunched(ARequest) then
    Exit;
  if (not AArguments.TryGetInt32('cols', LCols)) or (LCols < 1) then
  begin
    DoSendResponse(ARequest, False, Format(RSDbgDapBadArgument, [PC_DAP_TERMINAL_RESIZE, 'cols']), nil);
    Exit;
  end;
  if (not AArguments.TryGetInt32('rows', LRows)) or (LRows < 1) then
  begin
    DoSendResponse(ARequest, False, Format(RSDbgDapBadArgument, [PC_DAP_TERMINAL_RESIZE, 'rows']), nil);
    Exit;
  end;
  if not FRuntime.ResizeTerminal(LCols, LRows) then
  begin
    DoSendResponse(ARequest, False, Format(RSDbgDapRequestFailed, [PC_DAP_TERMINAL_RESIZE]), nil);
    Exit;
  end;
  DoSendResponse(ARequest, True, '', nil);
end;

procedure TPCDebugDAP.DoEvaluate(const ARequest: TJSON; const AArguments: TJSON);
var
  LText: string;
  LFrameId: Integer;
  LStack: TArray<TPCDebugStackItem>;
  LValue: TPCDebugValue;
  LRef: TPCDapRef;
  LBody: TJSONObject;
begin
  // Watch, hover and the debug console: a designator in PaskalCPP names
  // (TPCDebugRuntime.Evaluate); nothing is run, nothing changes
  if not DoNeedStop(ARequest) then
    Exit;
  if not AArguments.TryGetString('expression', LText) then
  begin
    DoSendResponse(ARequest, False, Format(RSDbgDapBadArgument, ['evaluate', 'expression']), nil);
    Exit;
  end;
  // No frame = the top frame of the stop
  if not AArguments.TryGetInt32('frameId', LFrameId) then
  begin
    LStack := FRuntime.StackTrace(FRuntime.StoppedThread());
    if Length(LStack) = 0 then
    begin
      DoSendResponse(ARequest, False, Format(RSDbgDapBadFrame, [0]), nil);
      Exit;
    end;
    LFrameId := LStack[0].FrameId;
  end;
  if not FRuntime.Evaluate(LFrameId, LText.Trim(), LValue) then
  begin
    DoSendResponse(ARequest, False, LValue.ValueText, nil);
    Exit;
  end;
  LBody := TJSONObject.Create();
  LBody.AddPair('result', LValue.ValueText);
  LBody.AddPair('type', LValue.TypeText);
  if LValue.ChildrenRef <> 0 then
  begin
    LRef := Default(TPCDapRef);
    LRef.Kind := drkChildren;
    LRef.ChildrenRef := LValue.ChildrenRef;
    LBody.AddPair('variablesReference', TJSONNumber.Create(DoAddRef(LRef)));
  end
  else
    LBody.AddPair('variablesReference', TJSONNumber.Create(0));
  DoSendResponse(ARequest, True, '', LBody);
end;

procedure TPCDebugDAP.DoTerminate(const ARequest: TJSON);
begin
  // The program ends; exited and terminated follow as events
  if not DoNeedLaunched(ARequest) then
    Exit;
  FRuntime.Terminate();
  DoSendResponse(ARequest, True, '', nil);
end;

procedure TPCDebugDAP.DoDisconnect(const ARequest: TJSON);
begin
  // A launched program does not outlive the session (terminateDebuggee is
  // a launch's default and the only behaviour offered)
  DoEndSession();
  DoSendResponse(ARequest, True, '', nil);
  FFinished := True;
end;

{ TPCDebugDAP: engine events }

procedure TPCDebugDAP.DoOnEvent(const AEvent: TPCDebugEvent);
begin
  // The engine consumes module loads itself: they never reach here
  case AEvent.Kind of
    dekOutput:
      DoOutput(PC_DAP_CATEGORY_STDOUT, AEvent.OutputText);
    dekStopped:
      DoOnStopped(AEvent);
    dekThreadStarted, dekThreadExited:
      DoOnThread(AEvent);
    dekExited:
      DoOnExited(AEvent);
  end;
end;

procedure TPCDebugDAP.DoOnStopped(const AEvent: TPCDebugEvent);
var
  LBody: TJSONObject;
begin
  DoSendChanges();
  DoClearRefs();
  DoRefreshThreads();
  DoSendReports();
  LBody := TJSONObject.Create();
  case AEvent.Reason of
    dsrEntry:
      LBody.AddPair('reason', 'entry');
    dsrBreakpoint:
      LBody.AddPair('reason', 'breakpoint');
    dsrStep:
      LBody.AddPair('reason', 'step');
    dsrPause:
      LBody.AddPair('reason', 'pause');
    dsrException:
      begin
        LBody.AddPair('reason', 'exception');
        if AEvent.FirstChance then
          LBody.AddPair('description', Format(RSDbgDapExceptionFirstChance, [Int64(AEvent.ExceptionCode)]))
        else
          LBody.AddPair('description', Format(RSDbgDapException, [Int64(AEvent.ExceptionCode)]));
      end;
  else
    LBody.AddPair('reason', 'pause');
  end;
  LBody.AddPair('threadId', TJSONNumber.Create(Int64(AEvent.ThreadId)));
  LBody.AddPair('allThreadsStopped', TJSONBool.Create(True));
  DoSendEvent('stopped', LBody);
end;

procedure TPCDebugDAP.DoOnThread(const AEvent: TPCDebugEvent);
var
  LIndex: Integer;
  LThread: TPCDebugThread;
  LBody: TJSONObject;
begin
  // The list kept while the program runs (DoRefreshThreads at a stop)
  LIndex := FThreads.Count - 1;
  while (LIndex >= 0) and (FThreads[LIndex].ThreadId <> AEvent.ThreadId) do
    Dec(LIndex);
  LBody := TJSONObject.Create();
  if AEvent.Kind = dekThreadStarted then
  begin
    if LIndex < 0 then
    begin
      LThread.ThreadId := AEvent.ThreadId;
      LThread.IsMain := False;
      FThreads.Add(LThread);
    end;
    LBody.AddPair('reason', 'started');
  end
  else
  begin
    if LIndex >= 0 then
      FThreads.Delete(LIndex);
    LBody.AddPair('reason', 'exited');
  end;
  LBody.AddPair('threadId', TJSONNumber.Create(Int64(AEvent.ThreadId)));
  DoSendEvent('thread', LBody);
end;

procedure TPCDebugDAP.DoOnExited(const AEvent: TPCDebugEvent);
var
  LBody: TJSONObject;
begin
  FExited := True;
  DoClearRefs();
  FThreads.Clear();
  DoSendReports();
  LBody := TJSONObject.Create();
  LBody.AddPair('exitCode', TJSONNumber.Create(Int64(AEvent.ExitCode)));
  DoSendEvent('exited', LBody);
  DoSendEvent('terminated', nil);
end;

end.
