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
  PaskalCPP.Debug.Target - one Win32 debug session of a PE program

  The process under the debugger: launch (an exe, or a dll through the host
  exe that loads it), the Win32 debug loop on its own thread, one event queue
  to the caller, the thread table (a context per thread), memory, and the
  patch table (int3 breakpoints, refcounted: our int3 = an address in the
  table, never "an int3 in .text"). API and the reference defects it does not
  port (T1-T10): research\editor\debugger-api.md (PLAN-EDITOR E3 e1).

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Resources (RTL, Win32)
  Notes:
    - The loop thread owns CreateProcess / WaitForDebugEvent /
      ContinueDebugEvent (the Win32 rule) and never touches TErrors (it is
      not thread-safe): a failure there is queued and reported by NextEvent
      on the caller's thread, before the event it precedes.
    - While a dekStopped event is out the whole process is frozen; Resume
      lets it go. A stop at a patched address steps over the patch (original
      byte, trap flag, every other thread suspended, int3 written back on the
      single step), then the requested resume goes on.
    - Every exception stop is resumed as not handled: the program sees it as
      it would without a debugger (a second chance ends the process; T4).
    - The program's standard handles, three modes (TPCDebugOutputMode):
      domConsole = the debugger's own console, shared; domPipes = stdout and
      stderr share ONE pipe (the order written, as TUtils.RunPE), stdin is
      NUL; domTerminal = a pseudo console the front-end feeds and resizes,
      its VT text is the output. A captured read is delivered at once, cut
      at its last complete UTF-8 character.
===============================================================================}

unit PaskalCPP.Debug.Target;

interface

uses
  WinApi.Windows,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  StdApp.Base;

const
  { PC_ERR_DBG_001 }
  PC_ERR_DBG_001 = 'DB0001';   // the program to debug does not exist
  { PC_ERR_DBG_002 }
  PC_ERR_DBG_002 = 'DB0002';   // the host does not exist
  { PC_ERR_DBG_003 }
  PC_ERR_DBG_003 = 'DB0003';   // the process cannot start under the debugger
  { PC_ERR_DBG_004 }
  PC_ERR_DBG_004 = 'DB0004';   // the debug loop / output thread failed
  { PC_ERR_DBG_008 }
  PC_ERR_DBG_008 = 'DB0008';   // code cannot be patched
  { PC_ERR_DBG_009 }
  PC_ERR_DBG_009 = 'DB0009';   // a thread's context cannot be read / written
  { PC_ERR_DBG_014 }
  PC_ERR_DBG_014 = 'DB0014';   // warning: the host exited before it loaded the dll
  { PC_ERR_DBG_017 }
  PC_ERR_DBG_017 = 'DB0017';   // the process cannot be paused

  { PC_DBG_INT3 }
  PC_DBG_INT3 = $CC;
  { PC_DBG_TRAP_FLAG }
  // RFLAGS bit 8: one instruction, then EXCEPTION_SINGLE_STEP
  PC_DBG_TRAP_FLAG = $100;
  { PC_DBG_EXC_BREAKPOINT }
  PC_DBG_EXC_BREAKPOINT = Cardinal($80000003);
  { PC_DBG_EXC_SINGLE_STEP }
  PC_DBG_EXC_SINGLE_STEP = Cardinal($80000004);
  { PC_DBG_TERMINATE_EXIT_CODE }
  // The exit code Terminate ends the process with (the dekExited event then
  // reports it: the process really exited with it)
  PC_DBG_TERMINATE_EXIT_CODE = 1;
  { PC_DBG_OUTPUT_POLL_MS }
  // How long the output reader waits for the process's exit while the pipe
  // is empty (it waits on an event, it does not spin)
  PC_DBG_OUTPUT_POLL_MS = 10;
  { PC_DBG_OUTPUT_BUFFER }
  PC_DBG_OUTPUT_BUFFER = 4096;
  { PC_DBG_TERMINAL_COLS }
  // domTerminal: the pseudo console's size until a front-end gives its own
  PC_DBG_TERMINAL_COLS = 120;
  { PC_DBG_TERMINAL_ROWS }
  PC_DBG_TERMINAL_ROWS = 30;
  { PC_DBG_TERMINAL_MAX }
  // A pseudo console's size is a COORD (SmallInt per side)
  PC_DBG_TERMINAL_MAX = 32767;
  { PC_DBG_CONTEXT_ALIGN }
  // x64 GetThreadContext / SetThreadContext need a 16-byte aligned CONTEXT
  PC_DBG_CONTEXT_ALIGN = 16;
  { PC_DBG_IMAGE_NAME_MAX }
  // The longest image name read from the debuggee (characters)
  PC_DBG_IMAGE_NAME_MAX = 32767;

type
  { TPCDebugEventKind }
  TPCDebugEventKind = (
    dekStopped,         // the process is frozen until Resume
    dekThreadStarted,
    dekThreadExited,
    dekModuleLoaded,    // the exe (at process creation) and every dll; frozen
                        // until Resume, so its breakpoints go in before it runs
    dekOutput,          // text the program wrote (output pipes only)
    dekExited           // the last event of a session
  );

  { TPCDebugStopReason }
  TPCDebugStopReason = (
    dsrNone,            // not a stop
    dsrEntry,           // the loader's break: modules known, nothing of the program ran
    dsrBreakpoint,      // an int3 at an address in the patch table
    dsrStep,            // the single step Resume(rkStep) asked for
    dsrPause,           // Pause: reported on the main thread
    dsrException        // a second chance, or a first chance when asked
  );

  { TPCResumeKind }
  TPCResumeKind = (
    rkContinue,
    rkStep              // one instruction on the stopped thread
  );

  { TPCDebugOutputMode }
  // Where the program's standard handles go. The rule: its stdout is a
  // terminal in every front-end that has one (a pipe makes the C runtime
  // buffer it: output only at exit, no keyboard)
  TPCDebugOutputMode = (
    domConsole,         // the debugger's own console, shared (a REPL on a console)
    domPipes,           // stdout + stderr captured as dekOutput, stdin NUL (no terminal)
    domTerminal         // a pseudo console the debugger relays: dekOutput = its VT text,
                        // WriteInput types into it, ResizeTerminal (the editor's pane)
  );

  { TPCDebugEvent }
  TPCDebugEvent = record
    Kind: TPCDebugEventKind;
    Reason: TPCDebugStopReason;
    ThreadId: Cardinal;
    Address: UInt64;          // stop: the instruction; module: its base
    ExceptionCode: Cardinal;  // dsrException (and the program's own int3)
    FirstChance: Boolean;
    ModulePath: string;       // dekModuleLoaded: resolved full path ('' = unknown)
    OutputText: string;       // dekOutput
    ExitCode: Cardinal;       // dekExited: as the process gave it, never made up
  end;

  { TPCDebugContext }
  // A thread's registers (x64 CONTEXT_FULL), stored as a plain value: the
  // target moves it through a 16-byte aligned buffer for the OS calls (T8)
  TPCDebugContext = record
    Regs: TContext;
  end;

  { TPCDebugPatch }
  // One patched address: the byte the int3 replaced (saved once) and how
  // many breakpoints want it (R1)
  TPCDebugPatch = record
    Original: Byte;
    RefCount: Integer;
  end;

  { TPCDebugFailure }
  // A failure the loop / output thread hit, reported later by NextEvent
  TPCDebugFailure = record
    Severity: TErrorSeverity;
    Code: string;
    Text: string;
  end;

  { TPCDebugTarget }
  // The PE debuggee of one session (Linux later is another engine below
  // TPCDebugRuntime, W5). Configure (SetProgram, SetHost, SetOutputMode,
  // SetBreakOnFirstChance), Start, then NextEvent / Resume until dekExited
  TPCDebugTarget = class(TBaseObject)
  private
    // Configuration (before Start)
    FProgramPath: string;
    FProgramArgs: string;
    FHostPath: string;
    FHostArgs: string;
    FOutputMode: TPCDebugOutputMode;
    FTerminalCols: Integer;
    FTerminalRows: Integer;
    FBreakOnFirstChance: Boolean;
    // The resolved paths Start launched / watches
    FLaunchPath: string;
    FTargetPath: string;

    // Shared between the threads: everything below FLock
    FLock: TCriticalSection;
    FQueue: TQueue<TPCDebugEvent>;
    FFailures: TList<TPCDebugFailure>;
    FThreads: TDictionary<Cardinal, THandle>;
    FPatches: TDictionary<UInt64, TPCDebugPatch>;
    FStarted: Boolean;
    FRunning: Boolean;
    FStopped: Boolean;
    FTerminating: Boolean;
    FPauseRequested: Boolean;
    FResumeKind: TPCResumeKind;
    FFirstChanceThread: Cardinal;   // a thread whose first chances stop too (0 = none)

    // Signals
    FQueueSignal: TEvent;       // manual: set while the queue holds events
    FResumeSignal: TEvent;      // auto: a stopped loop goes on
    FLaunchDone: TEvent;        // manual: the launch result is known
    FProcessExited: TEvent;     // manual: EXIT_PROCESS seen (the reader drains)
    FOutputDrained: TEvent;     // manual: the reader is done

    // The loop thread's own state (never touched by another thread)
    FStepOver: TDictionary<Cardinal, UInt64>;   // thread -> address to patch again
    FUserStep: TDictionary<Cardinal, Boolean>;  // threads with a requested step
    FSuspended: TList<THandle>;                 // held during a step-over
    FSeenLoaderBreak: Boolean;
    FDllLoaded: Boolean;

    // Written by the loop before the event that publishes them
    FLaunchOk: Boolean;
    FLaunchError: string;
    FProcessInfo: TProcessInformation;
    FMainThreadId: Cardinal;
    FImageBase: UInt64;
    FEntryAddress: UInt64;

    // Output pipe (domPipes; domTerminal: the pseudo console's output)
    FPipeRead: THandle;
    FPipeWrite: THandle;
    FNulInput: THandle;
    // domTerminal: the pseudo console (an HPCON; under FLock once started:
    // a resize races its close at exit) and its input
    FPseudoConsole: THandle;
    FTerminalInput: THandle;

    FLoopThread: TThread;
    FOutputThread: TThread;

    function IsDllMode(): Boolean;
    function DoCreatePipes(out AReason: string): Boolean;
    function DoCreateTerminal(out AReason: string): Boolean;
    procedure DoCloseTerminal();
    procedure DoCloseHandle(var AHandle: THandle);

    // Queue + failures
    procedure DoQueue(const AEvent: TPCDebugEvent);
    function DoDequeue(out AEvent: TPCDebugEvent): Boolean;
    procedure DoRecordFailure(const ASeverity: TErrorSeverity; const ACode: string;
      const AFormat: string; const AArgs: array of const);
    procedure DoFlushFailures();

    // Loop thread
    procedure DoLoop();
    procedure DoLaunch();
    procedure DoPump();
    function DoOnException(const AEvent: TDebugEvent): DWORD;
    procedure DoOnCreateProcess(const AEvent: TDebugEvent);
    procedure DoOnCreateThread(const AEvent: TDebugEvent);
    procedure DoOnExitThread(const AEvent: TDebugEvent);
    procedure DoOnLoadDll(const AEvent: TDebugEvent);
    procedure DoOnExitProcess(const AEvent: TDebugEvent);
    procedure DoStop(const AReason: TPCDebugStopReason; const AThreadId: Cardinal;
      const AAddress: UInt64; const AExceptionCode: Cardinal; const AFirstChance: Boolean);
    procedure DoHoldModule(const AEvent: TPCDebugEvent);
    procedure DoApplyResume(const AThreadId: Cardinal; const AKind: TPCResumeKind);
    function DoSetRip(const AThreadId: Cardinal; const AAddress: UInt64): Boolean;
    procedure DoRepatch(const AAddress: UInt64);
    procedure DoSuspendOthers(const AThreadId: Cardinal);
    procedure DoResumeOthers();
    function DoModulePath(const AFile: THandle; const AImageName: Pointer;
      const AUnicode: Word): string;
    function DoReadImageName(const AImageName: Pointer; const AUnicode: Word): string;
    function DoHandlePath(const AFile: THandle): string;
    function DoFinalPath(const APath: string): string;

    // Output thread
    procedure DoReadOutput();

    // Any thread (no reporting)
    function DoThreadHandle(const AThreadId: Cardinal; out AHandle: THandle): Boolean;
    function DoPatchOriginal(const AAddress: UInt64; out AOriginal: Byte): Boolean;
    function DoWriteCode(const AAddress: UInt64; const AValue: Byte; out AReason: string): Boolean;
    function DoReadRaw(const AAddress: UInt64; const ASize: NativeUInt; out ABytes: TBytes): Boolean;

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // The program to debug: an exe, or in DLL mode (SetHost) the dll
    procedure SetProgram(const AExePath: string; const AArgs: string);
    // DLL mode: the exe that loads the dll; '' = exe mode
    procedure SetHost(const AHostExePath: string; const AArgs: string);
    // Where the program's standard handles go (default domConsole)
    procedure SetOutputMode(const AMode: TPCDebugOutputMode);
    // domTerminal: the pseudo console's size at Start (default
    // PC_DBG_TERMINAL_COLS x PC_DBG_TERMINAL_ROWS; clamped to 1..32767)
    procedure SetTerminalSize(const ACols: Integer; const ARows: Integer);
    // False (default): a first-chance exception goes to the program (its
    // guards take faults as normal flow); a second chance always stops
    procedure SetBreakOnFirstChance(const AEnabled: Boolean);
    // While set, a first-chance exception on AThreadId stops too (dsrException,
    // FirstChance): a step must learn that its frame may unwind. 0 = none.
    // May be called at any time
    procedure SetFirstChanceThread(const AThreadId: Cardinal);

    // Launches the process under the debugger; returns once the launch result
    // is known. False = reported (DB0001 DB0002 DB0003 DB0004)
    function Start(): Boolean;
    // The image debugged (the exe; in DLL mode the dll) named as every
    // dekModuleLoaded names its module (the file's final path: 8.3 parts
    // expanded), so a load of it compares equal however it was spelled.
    // Valid after Start ('' before)
    function ImagePath(): string;
    // The next event, waiting up to ATimeoutMs; reports what the loop failed
    // at first. False = none in time
    function NextEvent(out AEvent: TPCDebugEvent; const ATimeoutMs: Cardinal): Boolean;
    // A dekStopped or dekModuleLoaded is out and not resumed yet
    function IsStopped(): Boolean;
    // The session's process is alive (Start succeeded, dekExited not reached)
    function IsRunning(): Boolean;
    // Lets a stopped process go. False = not stopped
    function Resume(const AKind: TPCResumeKind): Boolean;
    // domTerminal: types AText (sent as UTF-8; keys as the terminal spells
    // them: Enter = #13) into the program's terminal. False = no terminal, or
    // it is gone. Any thread
    function WriteInput(const AText: string): Boolean;
    // domTerminal: the terminal's new size (clamped as SetTerminalSize).
    // False = no terminal, or it is gone. Any thread
    function ResizeTerminal(const ACols: Integer; const ARows: Integer): Boolean;
    // Breaks into a running process (dsrPause). False = not running, or
    // reported (DB0017)
    function Pause(): Boolean;
    // Ends the process (the session then ends with dekExited)
    procedure Terminate();

    function Threads(): TArray<Cardinal>;
    // A thread's registers; False = reported (DB0009)
    function GetContext(const AThreadId: Cardinal; out AContext: TPCDebugContext): Boolean;
    function SetContext(const AThreadId: Cardinal; const AContext: TPCDebugContext): Boolean;
    // ASize bytes at AAddress, the original bytes where a patch sits; one
    // read, nothing reported (a caller shows the value as unreadable)
    function ReadMemory(const AAddress: UInt64; const ASize: NativeUInt; out ABytes: TBytes): Boolean;

    // The patch table: an int3 at AAddress, refcounted, the original byte
    // saved once. False = reported (DB0008), or (Remove) no such patch
    function AddPatch(const AAddress: UInt64): Boolean;
    function RemovePatch(const AAddress: UInt64): Boolean;
    function IsPatched(const AAddress: UInt64): Boolean;

    // Published by the session's first events (valid after dsrEntry)
    function ProcessHandle(): THandle;
    function ProcessId(): Cardinal;
    function MainThreadId(): Cardinal;
    // The launched exe's base and start address (CREATE_PROCESS)
    function ImageBase(): UInt64;
    function EntryAddress(): UInt64;
  end;

implementation

uses
  StdApp.Utils,
  StdApp.Resources;

{ KernelDebugBreakProcess }
function KernelDebugBreakProcess(AProcess: THandle): BOOL; stdcall;
  external kernel32 name 'DebugBreakProcess';

{ KernelGetFinalPathNameByHandle }
function KernelGetFinalPathNameByHandle(AFile: THandle; ABuffer: PWideChar;
  ASize: DWORD; AFlags: DWORD): DWORD; stdcall;
  external kernel32 name 'GetFinalPathNameByHandleW';

{ DoUtf8CompleteLength }
function DoUtf8CompleteLength(const ABytes: TBytes; const ACount: Integer): Integer;
var
  LIndex: Integer;
  LBack: Integer;
  LLead: Byte;
  LNeed: Integer;
begin
  // How many of ACount bytes end on a complete UTF-8 character: a trailing
  // lead byte whose continuation bytes have not all arrived is held back.
  // (TPCSourceText.Utf8Length clamps a cut sequence to the bytes present, so
  // it cannot tell a cut tail from a whole one: this needs the uncut length.)
  Result := ACount;
  LBack := 0;
  LIndex := ACount - 1;
  while (LIndex >= 0) and (LBack < 3) and ((ABytes[LIndex] and $C0) = $80) do
  begin
    Dec(LIndex);
    Inc(LBack);
  end;
  if LIndex < 0 then
    Exit;

  LLead := ABytes[LIndex];
  if LLead >= $F0 then
    LNeed := 4
  else if LLead >= $E0 then
    LNeed := 3
  else if LLead >= $C0 then
    LNeed := 2
  else
    LNeed := 1;
  if LIndex + LNeed > ACount then
    Result := LIndex;
end;

{ DoGetThreadContext }
function DoGetThreadContext(const AThread: THandle; out AContext: TPCDebugContext): Boolean;
var
  LBuffer: TBytes;
  LContext: PContext;
begin
  // Through a 16-byte aligned buffer (x64 CONTEXT); the value copied out
  SetLength(LBuffer, SizeOf(TContext) + PC_DBG_CONTEXT_ALIGN);
  LContext := PContext((NativeUInt(@LBuffer[0]) + PC_DBG_CONTEXT_ALIGN - 1) and
    not NativeUInt(PC_DBG_CONTEXT_ALIGN - 1));
  FillChar(LContext^, SizeOf(TContext), 0);
  LContext^.ContextFlags := CONTEXT_FULL;
  Result := GetThreadContext(AThread, LContext^);
  if Result then
    AContext.Regs := LContext^
  else
    FillChar(AContext, SizeOf(AContext), 0);
end;

{ DoSetThreadContext }
function DoSetThreadContext(const AThread: THandle; const AContext: TPCDebugContext): Boolean;
var
  LBuffer: TBytes;
  LContext: PContext;
begin
  SetLength(LBuffer, SizeOf(TContext) + PC_DBG_CONTEXT_ALIGN);
  LContext := PContext((NativeUInt(@LBuffer[0]) + PC_DBG_CONTEXT_ALIGN - 1) and
    not NativeUInt(PC_DBG_CONTEXT_ALIGN - 1));
  LContext^ := AContext.Regs;
  LContext^.ContextFlags := CONTEXT_FULL;
  Result := SetThreadContext(AThread, LContext^);
end;

{ TPCDebugTarget }

constructor TPCDebugTarget.Create();
begin
  inherited;

  FLock := TCriticalSection.Create();
  FQueue := TQueue<TPCDebugEvent>.Create();
  FFailures := TList<TPCDebugFailure>.Create();
  FThreads := TDictionary<Cardinal, THandle>.Create();
  FPatches := TDictionary<UInt64, TPCDebugPatch>.Create();
  FStepOver := TDictionary<Cardinal, UInt64>.Create();
  FUserStep := TDictionary<Cardinal, Boolean>.Create();
  FSuspended := TList<THandle>.Create();
  FQueueSignal := TEvent.Create(nil, True, False, '');
  FResumeSignal := TEvent.Create(nil, False, False, '');
  FLaunchDone := TEvent.Create(nil, True, False, '');
  FProcessExited := TEvent.Create(nil, True, False, '');
  FOutputDrained := TEvent.Create(nil, True, False, '');
  FillChar(FProcessInfo, SizeOf(FProcessInfo), 0);
  FPipeRead := 0;
  FPipeWrite := 0;
  FNulInput := 0;
  FResumeKind := rkContinue;
  FOutputMode := domConsole;
  FTerminalCols := PC_DBG_TERMINAL_COLS;
  FTerminalRows := PC_DBG_TERMINAL_ROWS;
  FPseudoConsole := 0;
  FTerminalInput := 0;
end;

destructor TPCDebugTarget.Destroy();
begin
  // A live session is ended first: the loop thread finishes at EXIT_PROCESS
  Terminate();
  if Assigned(FLoopThread) then
  begin
    FLoopThread.WaitFor();
    FLoopThread.Free();
  end;
  // A pseudo console still open (the launch failed, or the loop never saw
  // the exit) is closed before the reader is waited for: that breaks its pipe
  DoCloseTerminal();
  if Assigned(FOutputThread) then
  begin
    FOutputThread.WaitFor();
    FOutputThread.Free();
  end;

  // The CreateProcess handles are the session's; the debug events' handles
  // are the system's and never closed here (T6)
  DoCloseHandle(FProcessInfo.hThread);
  DoCloseHandle(FProcessInfo.hProcess);
  DoCloseHandle(FPipeRead);
  DoCloseHandle(FPipeWrite);
  DoCloseHandle(FNulInput);
  DoCloseHandle(FTerminalInput);

  FOutputDrained.Free();
  FProcessExited.Free();
  FLaunchDone.Free();
  FResumeSignal.Free();
  FQueueSignal.Free();
  FSuspended.Free();
  FUserStep.Free();
  FStepOver.Free();
  FPatches.Free();
  FThreads.Free();
  FFailures.Free();
  FQueue.Free();
  FLock.Free();

  inherited;
end;

procedure TPCDebugTarget.SetProgram(const AExePath: string; const AArgs: string);
begin
  FProgramPath := AExePath;
  FProgramArgs := AArgs;
end;

procedure TPCDebugTarget.SetHost(const AHostExePath: string; const AArgs: string);
begin
  FHostPath := AHostExePath;
  FHostArgs := AArgs;
end;

procedure TPCDebugTarget.SetOutputMode(const AMode: TPCDebugOutputMode);
begin
  FOutputMode := AMode;
end;

{ DoTerminalSide }
// One side of a pseudo console's size, as COORD holds it
function DoTerminalSide(const AValue: Integer): SmallInt;
begin
  if AValue < 1 then
    Result := 1
  else if AValue > PC_DBG_TERMINAL_MAX then
    Result := PC_DBG_TERMINAL_MAX
  else
    Result := SmallInt(AValue);
end;

procedure TPCDebugTarget.SetTerminalSize(const ACols: Integer; const ARows: Integer);
begin
  FTerminalCols := DoTerminalSide(ACols);
  FTerminalRows := DoTerminalSide(ARows);
end;

procedure TPCDebugTarget.SetBreakOnFirstChance(const AEnabled: Boolean);
begin
  FBreakOnFirstChance := AEnabled;
end;

procedure TPCDebugTarget.SetFirstChanceThread(const AThreadId: Cardinal);
begin
  // Read by the loop thread at each exception: under the lock
  FLock.Enter();
  try
    FFirstChanceThread := AThreadId;
  finally
    FLock.Leave();
  end;
end;

function TPCDebugTarget.IsDllMode(): Boolean;
begin
  Result := FHostPath <> '';
end;

procedure TPCDebugTarget.DoCloseHandle(var AHandle: THandle);
begin
  if (AHandle <> 0) and (AHandle <> INVALID_HANDLE_VALUE) then
    CloseHandle(AHandle);
  AHandle := 0;
end;

function TPCDebugTarget.DoCreatePipes(out AReason: string): Boolean;
var
  LSecurity: TSecurityAttributes;
begin
  // One inheritable pipe for stdout + stderr (the order written), the read
  // end kept out of the child; stdin = NUL
  Result := False;
  AReason := '';
  LSecurity.nLength := SizeOf(TSecurityAttributes);
  LSecurity.bInheritHandle := True;
  LSecurity.lpSecurityDescriptor := nil;

  if not CreatePipe(FPipeRead, FPipeWrite, @LSecurity, 0) then
  begin
    AReason := SysErrorMessage(GetLastError());
    Exit;
  end;
  if not SetHandleInformation(FPipeRead, HANDLE_FLAG_INHERIT, 0) then
  begin
    AReason := SysErrorMessage(GetLastError());
    Exit;
  end;
  FNulInput := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
    @LSecurity, OPEN_EXISTING, 0, 0);
  if FNulInput = INVALID_HANDLE_VALUE then
  begin
    FNulInput := 0;
    AReason := SysErrorMessage(GetLastError());
    Exit;
  end;
  Result := True;
end;

function TPCDebugTarget.DoCreateTerminal(out AReason: string): Boolean;
var
  LInputRead: THandle;
  LOutputWrite: THandle;
  LSize: COORD;
  LResult: HRESULT;
begin
  // Two plain pipes, nothing inheritable: the program reaches only the
  // pseudo console, which keeps its own copies of the ends it was given.
  // Ours: its input (WriteInput) and its output (the reader, FPipeRead)
  Result := False;
  AReason := '';
  LInputRead := 0;
  LOutputWrite := 0;
  try
    if not CreatePipe(LInputRead, FTerminalInput, nil, 0) then
    begin
      AReason := SysErrorMessage(GetLastError());
      Exit;
    end;
    if not CreatePipe(FPipeRead, LOutputWrite, nil, 0) then
    begin
      AReason := SysErrorMessage(GetLastError());
      Exit;
    end;
    LSize.X := DoTerminalSide(FTerminalCols);
    LSize.Y := DoTerminalSide(FTerminalRows);
    LResult := CreatePseudoConsole(LSize, LInputRead, LOutputWrite, 0, FPseudoConsole);
    if Failed(LResult) then
    begin
      FPseudoConsole := 0;
      AReason := SysErrorMessage(Cardinal(LResult));
      Exit;
    end;
    Result := True;
  finally
    DoCloseHandle(LInputRead);
    DoCloseHandle(LOutputWrite);
  end;
end;

procedure TPCDebugTarget.DoCloseTerminal();
var
  LConsole: THandle;
begin
  // Ends the pseudo console: it writes out what it holds, then its output
  // pipe breaks, which is the reader's end (nothing lost to timing). Called
  // by the loop thread at EXIT_PROCESS while the reader still reads (an
  // older Windows waits in ClosePseudoConsole for that drain), and by
  // Destroy; the second call finds nothing
  FLock.Enter();
  try
    LConsole := FPseudoConsole;
    FPseudoConsole := 0;
  finally
    FLock.Leave();
  end;
  if LConsole <> 0 then
    ClosePseudoConsole(LConsole);
end;

function TPCDebugTarget.WriteInput(const AText: string): Boolean;
var
  LBytes: TBytes;
  LOffset: Integer;
  LWritten: DWORD;
begin
  // The input handle lives until Destroy; once the pseudo console is closed
  // a write fails (broken pipe) and answers False
  Result := False;
  if (FOutputMode <> domTerminal) or (FTerminalInput = 0) then
    Exit;
  LBytes := TEncoding.UTF8.GetBytes(AText);
  LOffset := 0;
  while LOffset < Length(LBytes) do
  begin
    LWritten := 0;
    if not WriteFile(FTerminalInput, LBytes[LOffset], DWORD(Length(LBytes) - LOffset), LWritten, nil) then
      Exit;
    Inc(LOffset, Integer(LWritten));
  end;
  Result := True;
end;

function TPCDebugTarget.ResizeTerminal(const ACols: Integer; const ARows: Integer): Boolean;
var
  LSize: COORD;
begin
  Result := False;
  if FOutputMode <> domTerminal then
    Exit;
  LSize.X := DoTerminalSide(ACols);
  LSize.Y := DoTerminalSide(ARows);
  // Under the lock: the loop thread may be closing it at the program's exit
  FLock.Enter();
  try
    if FPseudoConsole <> 0 then
      Result := Succeeded(ResizePseudoConsole(FPseudoConsole, LSize));
  finally
    FLock.Leave();
  end;
end;

procedure TPCDebugTarget.DoQueue(const AEvent: TPCDebugEvent);
begin
  FLock.Enter();
  try
    FQueue.Enqueue(AEvent);
    FQueueSignal.SetEvent();
  finally
    FLock.Leave();
  end;
end;

function TPCDebugTarget.DoDequeue(out AEvent: TPCDebugEvent): Boolean;
begin
  FLock.Enter();
  try
    Result := FQueue.Count > 0;
    if Result then
      AEvent := FQueue.Dequeue()
    else
      AEvent := Default(TPCDebugEvent);
    if FQueue.Count = 0 then
      FQueueSignal.ResetEvent();
  finally
    FLock.Leave();
  end;
end;

procedure TPCDebugTarget.DoRecordFailure(const ASeverity: TErrorSeverity; const ACode: string;
  const AFormat: string; const AArgs: array of const);
var
  LFailure: TPCDebugFailure;
begin
  // The text is formatted now (the args do not outlive the call); NextEvent
  // reports it on the caller's thread
  LFailure.Severity := ASeverity;
  LFailure.Code := ACode;
  LFailure.Text := Format(AFormat, AArgs);
  FLock.Enter();
  try
    FFailures.Add(LFailure);
  finally
    FLock.Leave();
  end;
end;

procedure TPCDebugTarget.DoFlushFailures();
var
  LFailures: TArray<TPCDebugFailure>;
  LFailure: TPCDebugFailure;
begin
  FLock.Enter();
  try
    LFailures := FFailures.ToArray();
    FFailures.Clear();
  finally
    FLock.Leave();
  end;
  for LFailure in LFailures do
    FErrors.Add(LFailure.Severity, LFailure.Code, LFailure.Text);
end;

function TPCDebugTarget.Start(): Boolean;
var
  LReason: string;
begin
  Result := False;
  if FStarted then
    Exit;
  FStarted := True;

  // The program (DLL mode: the dll) and the host must exist; paths resolve
  // through TUtils.ResolvePath (the project rule)
  try
    FTargetPath := TUtils.ResolvePath(FProgramPath);
  except
    on E: Exception do
      FTargetPath := '';
  end;
  if (FTargetPath = '') or (not FileExists(FTargetPath)) then
  begin
    FErrors.Add(esError, PC_ERR_DBG_001, RSDbgProgramNotFound, [FProgramPath]);
    Exit;
  end;
  // Spelled as the loader's events will name it (ImagePath)
  FTargetPath := DoFinalPath(FTargetPath);
  if IsDllMode() then
  begin
    try
      FLaunchPath := TUtils.ResolvePath(FHostPath);
    except
      on E: Exception do
        FLaunchPath := '';
    end;
    if (FLaunchPath = '') or (not FileExists(FLaunchPath)) then
    begin
      FErrors.Add(esError, PC_ERR_DBG_002, RSDbgHostNotFound, [FHostPath]);
      Exit;
    end;
  end
  else
    FLaunchPath := FTargetPath;

  if (FOutputMode = domPipes) and (not DoCreatePipes(LReason)) then
  begin
    FErrors.Add(esError, PC_ERR_DBG_003, RSDbgStartFailed, [FLaunchPath, LReason]);
    Exit;
  end;
  if (FOutputMode = domTerminal) and (not DoCreateTerminal(LReason)) then
  begin
    FErrors.Add(esError, PC_ERR_DBG_003, RSDbgStartFailed, [FLaunchPath, LReason]);
    Exit;
  end;

  // CreateProcess happens on the loop thread (the thread that waits for
  // debug events must be the one that created the process)
  FRunning := True;
  try
    FLoopThread := TThread.CreateAnonymousThread(
      procedure
      begin
        DoLoop();
      end);
    FLoopThread.FreeOnTerminate := False;
    FLoopThread.Start();
  except
    on E: Exception do
    begin
      FRunning := False;
      FErrors.Add(esError, PC_ERR_DBG_004, RSDbgLoopFailed, [E.Message]);
      Exit;
    end;
  end;

  // The loop sets FLaunchDone on every path (DoLoop's finally)
  FLaunchDone.WaitFor(INFINITE);
  if not FLaunchOk then
  begin
    FLoopThread.WaitFor();
    FErrors.Add(esError, PC_ERR_DBG_003, RSDbgStartFailed, [FLaunchPath, FLaunchError]);
    Exit;
  end;

  if FOutputMode in [domPipes, domTerminal] then
  begin
    try
      FOutputThread := TThread.CreateAnonymousThread(
        procedure
        begin
          DoReadOutput();
        end);
      FOutputThread.FreeOnTerminate := False;
      FOutputThread.Start();
    except
      on E: Exception do
      begin
        // The program cannot be debugged without its output: end it
        FErrors.Add(esError, PC_ERR_DBG_004, RSDbgLoopFailed, [E.Message]);
        FOutputDrained.SetEvent();
        Terminate();
        Exit;
      end;
    end;
  end
  else
    FOutputDrained.SetEvent();

  Result := True;
end;

function TPCDebugTarget.NextEvent(out AEvent: TPCDebugEvent; const ATimeoutMs: Cardinal): Boolean;
begin
  // A failure is reported before the event it precedes (both were recorded
  // in that order)
  DoFlushFailures();
  Result := DoDequeue(AEvent);
  if not Result then
  begin
    FQueueSignal.WaitFor(ATimeoutMs);
    DoFlushFailures();
    Result := DoDequeue(AEvent);
  end;
end;

function TPCDebugTarget.IsStopped(): Boolean;
begin
  FLock.Enter();
  try
    Result := FStopped;
  finally
    FLock.Leave();
  end;
end;

function TPCDebugTarget.IsRunning(): Boolean;
begin
  FLock.Enter();
  try
    Result := FRunning;
  finally
    FLock.Leave();
  end;
end;

function TPCDebugTarget.Resume(const AKind: TPCResumeKind): Boolean;
begin
  FLock.Enter();
  try
    Result := FStopped;
    if not Result then
      Exit;
    FStopped := False;
    FResumeKind := AKind;
  finally
    FLock.Leave();
  end;
  FResumeSignal.SetEvent();
end;

function TPCDebugTarget.Pause(): Boolean;
var
  LReason: string;
begin
  FLock.Enter();
  try
    Result := FRunning and (not FStopped) and (not FTerminating);
    if not Result then
      Exit;
    FPauseRequested := True;
  finally
    FLock.Leave();
  end;

  // The break-in int3 runs on a new thread in ntdll; the loop reports it as
  // dsrPause on the main thread
  if not KernelDebugBreakProcess(FProcessInfo.hProcess) then
  begin
    LReason := SysErrorMessage(GetLastError());
    FLock.Enter();
    try
      FPauseRequested := False;
    finally
      FLock.Leave();
    end;
    FErrors.Add(esError, PC_ERR_DBG_017, RSDbgPauseFailed, [LReason]);
    Result := False;
  end;
end;

procedure TPCDebugTarget.Terminate();
var
  LWasStopped: Boolean;
begin
  FLock.Enter();
  try
    if (not FRunning) or FTerminating then
      Exit;
    FTerminating := True;
    LWasStopped := FStopped;
    FStopped := False;
    FResumeKind := rkContinue;
  finally
    FLock.Leave();
  end;

  // TerminateProcess fails only for a process already ending: its
  // EXIT_PROCESS event comes either way, which ends the loop
  TerminateProcess(FProcessInfo.hProcess, PC_DBG_TERMINATE_EXIT_CODE);
  if LWasStopped then
    FResumeSignal.SetEvent();
end;

procedure TPCDebugTarget.DoLoop();
var
  LExitCode: DWORD;
  LEvent: TPCDebugEvent;
begin
  try
    try
      DoLaunch();
    except
      on E: Exception do
      begin
        FLaunchOk := False;
        FLaunchError := E.Message;
      end;
    end;
  finally
    FLaunchDone.SetEvent();
  end;

  if FLaunchOk then
  begin
    try
      DoPump();
    except
      on E: Exception do
      begin
        // The debug loop itself broke (WaitForDebugEvent / ContinueDebugEvent
        // failed): detach, end the process and report its real exit code
        DoRecordFailure(esError, PC_ERR_DBG_004, RSDbgLoopFailed, [E.Message]);
        DebugActiveProcessStop(FProcessInfo.dwProcessId);
        TerminateProcess(FProcessInfo.hProcess, PC_DBG_TERMINATE_EXIT_CODE);
        WaitForSingleObject(FProcessInfo.hProcess, INFINITE);
        LExitCode := PC_DBG_TERMINATE_EXIT_CODE;
        GetExitCodeProcess(FProcessInfo.hProcess, LExitCode);
        // As DoOnExitProcess: the program's last output comes before the
        // exit (the reader drains it; the pseudo console breaks its pipe)
        FProcessExited.SetEvent();
        DoCloseTerminal();
        FOutputDrained.WaitFor(INFINITE);
        LEvent := Default(TPCDebugEvent);
        LEvent.Kind := dekExited;
        LEvent.ExitCode := LExitCode;
        DoQueue(LEvent);
      end;
    end;
  end;

  FLock.Enter();
  try
    FRunning := False;
    FStopped := False;
  finally
    FLock.Leave();
  end;
end;

procedure TPCDebugTarget.DoLaunch();
var
  LArgs: string;
  LCmdLine: string;
  LAppName: string;
  LAppNamePtr: PChar;
  LWorkDir: string;
  LWorkDirPtr: PChar;
  LStartup: STARTUPINFOEXW;
  LAttrList: PProcThreadAttributeList;
  LAttrSize: NativeUInt;
  LFlags: DWORD;
  LInherit: BOOL;
begin
  FLaunchOk := False;
  FLaunchError := '';
  LAttrList := nil;

  // The command line: the program path quoted as every launch does (R49),
  // past PATH_LAUNCH_MAX also named as the application (TUtils.LaunchName)
  if IsDllMode() then
    LArgs := FHostArgs
  else
    LArgs := FProgramArgs;
  LCmdLine := TUtils.QuoteCommandArg(TUtils.StripLongPathPrefix(FLaunchPath));
  if LArgs <> '' then
    LCmdLine := LCmdLine + ' ' + LArgs;
  // CreateProcessW may write into the command line buffer
  UniqueString(LCmdLine);
  LAppName := TUtils.LaunchName(FLaunchPath);
  if LAppName <> '' then
    LAppNamePtr := PChar(LAppName)
  else
    LAppNamePtr := nil;

  // The program runs in its own folder (as Run does)
  LWorkDir := TUtils.StripLongPathPrefix(FLaunchPath).Replace('/', '\');
  LWorkDir := ExtractFileDir(LWorkDir);
  if LWorkDir <> '' then
    LWorkDirPtr := PChar(LWorkDir)
  else
    LWorkDirPtr := nil;

  FillChar(LStartup, SizeOf(LStartup), 0);
  LStartup.StartupInfo.cb := SizeOf(LStartup.StartupInfo);
  // Its own process group: a Ctrl+C at the debugger's console is the
  // debugger's (the REPL pauses on it), never delivered to the program as
  // DBG_CONTROL_C (passed on, it would end the program)
  LFlags := DEBUG_ONLY_THIS_PROCESS or CREATE_NEW_PROCESS_GROUP;
  LInherit := False;
  if FOutputMode = domPipes then
  begin
    // No console of its own: everything it writes goes to the pipe
    LStartup.StartupInfo.dwFlags := STARTF_USESTDHANDLES;
    LStartup.StartupInfo.hStdInput := FNulInput;
    LStartup.StartupInfo.hStdOutput := FPipeWrite;
    LStartup.StartupInfo.hStdError := FPipeWrite;
    LFlags := LFlags or CREATE_NO_WINDOW;
    LInherit := True;
  end;

  try
    if FOutputMode = domTerminal then
    begin
      // The pseudo console is its console (prior art StdApp.Utils
      // CaptureConsolePTY): an attribute list naming it, and no standard
      // handles of the debugger's (a redirected debugger, as pcpp --dap,
      // would hand its own down, written around the terminal)
      LAttrSize := 0;
      InitializeProcThreadAttributeList(nil, 1, 0, LAttrSize);
      GetMem(LAttrList, LAttrSize);
      if not InitializeProcThreadAttributeList(LAttrList, 1, 0, LAttrSize) then
      begin
        FreeMem(LAttrList);
        LAttrList := nil;
        FLaunchError := SysErrorMessage(GetLastError());
        Exit;
      end;
      // lpReturnSize is reserved and must be nil (the RTL spells it var)
      if not UpdateProcThreadAttribute(LAttrList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
        Pointer(FPseudoConsole), SizeOf(HPCON), nil, PNativeUInt(nil)^) then
      begin
        FLaunchError := SysErrorMessage(GetLastError());
        Exit;
      end;
      LStartup.StartupInfo.cb := SizeOf(LStartup);
      LStartup.lpAttributeList := LAttrList;
      LStartup.StartupInfo.dwFlags := STARTF_USESTDHANDLES;
      LStartup.StartupInfo.hStdInput := 0;
      LStartup.StartupInfo.hStdOutput := 0;
      LStartup.StartupInfo.hStdError := 0;
      LFlags := LFlags or EXTENDED_STARTUPINFO_PRESENT;
    end;

    // STARTUPINFOEXW starts with the STARTUPINFOW: its address is the record's
    if CreateProcess(LAppNamePtr, PChar(LCmdLine), nil, nil, LInherit, LFlags, nil,
      LWorkDirPtr, LStartup.StartupInfo, FProcessInfo) then
      FLaunchOk := True
    else
      FLaunchError := SysErrorMessage(GetLastError());
  finally
    if LAttrList <> nil then
    begin
      DeleteProcThreadAttributeList(LAttrList);
      FreeMem(LAttrList);
    end;
  end;

  // Only the child holds the write end and NUL now: the pipe breaks when the
  // child (and whatever inherited them) is gone
  DoCloseHandle(FPipeWrite);
  DoCloseHandle(FNulInput);
end;

procedure TPCDebugTarget.DoPump();
var
  LEvent: TDebugEvent;
  LStatus: DWORD;
  LDone: Boolean;
begin
  LDone := False;
  repeat
    // Terminate always produces EXIT_PROCESS, so the wait has no timeout
    if not WaitForDebugEvent(LEvent, INFINITE) then
      RaiseLastOSError();

    LStatus := DBG_CONTINUE;
    try
      case LEvent.dwDebugEventCode of
        EXCEPTION_DEBUG_EVENT:
          LStatus := DoOnException(LEvent);
        CREATE_PROCESS_DEBUG_EVENT:
          DoOnCreateProcess(LEvent);
        CREATE_THREAD_DEBUG_EVENT:
          DoOnCreateThread(LEvent);
        EXIT_THREAD_DEBUG_EVENT:
          DoOnExitThread(LEvent);
        LOAD_DLL_DEBUG_EVENT:
          DoOnLoadDll(LEvent);
        EXIT_PROCESS_DEBUG_EVENT:
          begin
            DoOnExitProcess(LEvent);
            LDone := True;
          end;
      end;
    except
      // One event's handling failed (an RTL call raised): reported, and the
      // session goes on with the event continued
      on E: Exception do
        DoRecordFailure(esError, PC_ERR_DBG_004, RSDbgLoopFailed, [E.Message]);
    end;

    if not ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId, LStatus) then
      RaiseLastOSError();
  until LDone;
end;

function TPCDebugTarget.DoOnException(const AEvent: TDebugEvent): DWORD;
var
  LCode: Cardinal;
  LAddress: UInt64;
  LFirst: Boolean;
  LThreadId: Cardinal;
  LPatchAddress: UInt64;
  LPause: Boolean;
  LHandle: THandle;
  LContext: TPCDebugContext;
  LWatched: Boolean;
begin
  LCode := AEvent.Exception.ExceptionRecord.ExceptionCode;
  LAddress := UInt64(NativeUInt(AEvent.Exception.ExceptionRecord.ExceptionAddress));
  LFirst := AEvent.Exception.dwFirstChance <> 0;
  LThreadId := AEvent.dwThreadId;
  Result := DBG_CONTINUE;

  if LCode = PC_DBG_EXC_BREAKPOINT then
  begin
    // The loader's own break comes first: the configuration point
    if not FSeenLoaderBreak then
    begin
      FSeenLoaderBreak := True;
      DoStop(dsrEntry, LThreadId, LAddress, 0, LFirst);
      Exit;
    end;

    // Ours: the address is in the patch table (T3). RIP goes back onto the
    // int3, so the resume steps over the original instruction
    if IsPatched(LAddress) then
    begin
      DoSetRip(LThreadId, LAddress);
      DoStop(dsrBreakpoint, LThreadId, LAddress, 0, LFirst);
      Exit;
    end;

    // Pause's break-in thread: reported on the main thread, where the
    // program is
    FLock.Enter();
    try
      LPause := FPauseRequested;
      FPauseRequested := False;
    finally
      FLock.Leave();
    end;
    if LPause then
    begin
      LAddress := 0;
      if DoThreadHandle(FMainThreadId, LHandle) and DoGetThreadContext(LHandle, LContext) then
        LAddress := LContext.Regs.Rip;
      DoStop(dsrPause, FMainThreadId, LAddress, 0, LFirst);
      Exit;
    end;
    // Else the program's own int3: an exception like any other (below)
  end
  else if LCode = PC_DBG_EXC_SINGLE_STEP then
  begin
    // A step over a patch finished: the int3 goes back, the other threads
    // run again, and a requested step stops here
    if FStepOver.TryGetValue(LThreadId, LPatchAddress) then
    begin
      FStepOver.Remove(LThreadId);
      DoRepatch(LPatchAddress);
      DoResumeOthers();
      if FUserStep.ContainsKey(LThreadId) then
      begin
        FUserStep.Remove(LThreadId);
        DoStop(dsrStep, LThreadId, LAddress, 0, LFirst);
      end;
      Exit;
    end;
    if FUserStep.ContainsKey(LThreadId) then
    begin
      FUserStep.Remove(LThreadId);
      DoStop(dsrStep, LThreadId, LAddress, 0, LFirst);
      Exit;
    end;
    // Else the program's own trap: an exception like any other (below)
  end;

  // The program sees every exception as without a debugger: a first chance
  // goes to its handlers (guards), a second chance ends it after the stop
  Result := DBG_EXCEPTION_NOT_HANDLED;
  FLock.Enter();
  try
    LWatched := (FFirstChanceThread <> 0) and (FFirstChanceThread = LThreadId);
  finally
    FLock.Leave();
  end;
  if LFirst and (not FBreakOnFirstChance) and (not LWatched) then
    Exit;
  DoStop(dsrException, LThreadId, LAddress, LCode, LFirst);
end;

procedure TPCDebugTarget.DoOnCreateProcess(const AEvent: TDebugEvent);
var
  LEvent: TPCDebugEvent;
  LThread: TPCDebugEvent;
begin
  FMainThreadId := AEvent.dwThreadId;
  FImageBase := UInt64(NativeUInt(AEvent.CreateProcessInfo.lpBaseOfImage));
  FEntryAddress := UInt64(NativeUInt(AEvent.CreateProcessInfo.lpStartAddress));
  FLock.Enter();
  try
    FThreads.AddOrSetValue(AEvent.dwThreadId, AEvent.CreateProcessInfo.hThread);
  finally
    FLock.Leave();
  end;

  LEvent := Default(TPCDebugEvent);
  LEvent.Kind := dekModuleLoaded;
  LEvent.ThreadId := AEvent.dwThreadId;
  LEvent.Address := FImageBase;
  LEvent.ModulePath := DoModulePath(AEvent.CreateProcessInfo.hFile,
    AEvent.CreateProcessInfo.lpImageName, AEvent.CreateProcessInfo.fUnicode);
  // hFile is ours to close; hProcess / hThread are the system's
  if AEvent.CreateProcessInfo.hFile <> 0 then
    CloseHandle(AEvent.CreateProcessInfo.hFile);

  LThread := Default(TPCDebugEvent);
  LThread.Kind := dekThreadStarted;
  LThread.ThreadId := AEvent.dwThreadId;
  DoQueue(LThread);
  DoHoldModule(LEvent);
end;

procedure TPCDebugTarget.DoOnCreateThread(const AEvent: TDebugEvent);
var
  LEvent: TPCDebugEvent;
begin
  FLock.Enter();
  try
    FThreads.AddOrSetValue(AEvent.dwThreadId, AEvent.CreateThread.hThread);
  finally
    FLock.Leave();
  end;
  LEvent := Default(TPCDebugEvent);
  LEvent.Kind := dekThreadStarted;
  LEvent.ThreadId := AEvent.dwThreadId;
  DoQueue(LEvent);
end;

procedure TPCDebugTarget.DoOnExitThread(const AEvent: TDebugEvent);
var
  LEvent: TPCDebugEvent;
  LPatchAddress: UInt64;
begin
  // A thread that ends in the middle of a step-over: its patch goes back and
  // the others run again
  if FStepOver.TryGetValue(AEvent.dwThreadId, LPatchAddress) then
  begin
    FStepOver.Remove(AEvent.dwThreadId);
    DoRepatch(LPatchAddress);
    DoResumeOthers();
  end;
  FUserStep.Remove(AEvent.dwThreadId);

  FLock.Enter();
  try
    FThreads.Remove(AEvent.dwThreadId);
  finally
    FLock.Leave();
  end;
  LEvent := Default(TPCDebugEvent);
  LEvent.Kind := dekThreadExited;
  LEvent.ThreadId := AEvent.dwThreadId;
  DoQueue(LEvent);
end;

procedure TPCDebugTarget.DoOnLoadDll(const AEvent: TDebugEvent);
var
  LEvent: TPCDebugEvent;
begin
  LEvent := Default(TPCDebugEvent);
  LEvent.Kind := dekModuleLoaded;
  LEvent.ThreadId := AEvent.dwThreadId;
  LEvent.Address := UInt64(NativeUInt(AEvent.LoadDll.lpBaseOfDll));
  LEvent.ModulePath := DoModulePath(AEvent.LoadDll.hFile, AEvent.LoadDll.lpImageName,
    AEvent.LoadDll.fUnicode);
  if AEvent.LoadDll.hFile <> 0 then
    CloseHandle(AEvent.LoadDll.hFile);

  // DLL mode: the dll being debugged is now in the process
  if IsDllMode() and (LEvent.ModulePath <> '') and
    TUtils.SamePath(LEvent.ModulePath, FTargetPath) then
    FDllLoaded := True;
  DoHoldModule(LEvent);
end;

procedure TPCDebugTarget.DoOnExitProcess(const AEvent: TDebugEvent);
var
  LEvent: TPCDebugEvent;
begin
  // Everything the program wrote is in the pipe by now (domTerminal: in the
  // pseudo console, which writes it out and breaks its pipe as it closes):
  // the reader drains it, so its output events come before the exit
  FProcessExited.SetEvent();
  DoCloseTerminal();
  FOutputDrained.WaitFor(INFINITE);

  if IsDllMode() and (not FDllLoaded) then
    DoRecordFailure(esWarning, PC_ERR_DBG_014, RSDbgHostExitedEarly,
      [AEvent.ExitProcess.dwExitCode, FTargetPath]);

  LEvent := Default(TPCDebugEvent);
  LEvent.Kind := dekExited;
  LEvent.ThreadId := AEvent.dwThreadId;
  LEvent.ExitCode := AEvent.ExitProcess.dwExitCode;
  DoQueue(LEvent);
end;

procedure TPCDebugTarget.DoStop(const AReason: TPCDebugStopReason; const AThreadId: Cardinal;
  const AAddress: UInt64; const AExceptionCode: Cardinal; const AFirstChance: Boolean);
var
  LEvent: TPCDebugEvent;
  LKind: TPCResumeKind;
begin
  // A session being terminated stops nowhere: the event continues and the
  // process's exit follows
  FLock.Enter();
  try
    if FTerminating then
      Exit;
    FStopped := True;
  finally
    FLock.Leave();
  end;

  LEvent := Default(TPCDebugEvent);
  LEvent.Kind := dekStopped;
  LEvent.Reason := AReason;
  LEvent.ThreadId := AThreadId;
  LEvent.Address := AAddress;
  LEvent.ExceptionCode := AExceptionCode;
  LEvent.FirstChance := AFirstChance;
  DoQueue(LEvent);

  // Frozen until Resume (or Terminate) lets it go
  FResumeSignal.WaitFor(INFINITE);
  FLock.Enter();
  try
    LKind := FResumeKind;
  finally
    FLock.Leave();
  end;
  DoApplyResume(AThreadId, LKind);
end;

procedure TPCDebugTarget.DoHoldModule(const AEvent: TPCDebugEvent);
begin
  // A module load holds the process like a stop, so the engine adds its
  // symbols and patches its breakpoints before any of its code runs (a dll
  // the host calls at once would otherwise run first). Stopped is set before
  // the event is out, as DoStop does: a Resume right after it is never lost.
  // No thread steps from here: the resume kind is not used
  FLock.Enter();
  try
    if FTerminating then
      Exit;
    FStopped := True;
  finally
    FLock.Leave();
  end;
  DoQueue(AEvent);
  FResumeSignal.WaitFor(INFINITE);
end;

procedure TPCDebugTarget.DoApplyResume(const AThreadId: Cardinal; const AKind: TPCResumeKind);
var
  LHandle: THandle;
  LContext: TPCDebugContext;
  LOriginal: Byte;
  LStepOver: Boolean;
  LReason: string;
begin
  if FTerminating then
    Exit;
  if not DoThreadHandle(AThreadId, LHandle) then
    Exit;
  if not DoGetThreadContext(LHandle, LContext) then
  begin
    DoRecordFailure(esError, PC_ERR_DBG_009, RSDbgContextFailed,
      [AThreadId, SysErrorMessage(GetLastError())]);
    Exit;
  end;

  // On a patched address: the original byte runs once under the trap flag
  // with every other thread held, then the int3 goes back (single step)
  LStepOver := DoPatchOriginal(LContext.Regs.Rip, LOriginal);
  if LStepOver then
  begin
    if not DoWriteCode(LContext.Regs.Rip, LOriginal, LReason) then
    begin
      DoRecordFailure(esError, PC_ERR_DBG_008, RSDbgPatchFailed,
        [LContext.Regs.Rip, LReason]);
      Exit;
    end;
    FStepOver.AddOrSetValue(AThreadId, LContext.Regs.Rip);
    DoSuspendOthers(AThreadId);
  end;

  if LStepOver or (AKind = rkStep) then
  begin
    LContext.Regs.EFlags := LContext.Regs.EFlags or PC_DBG_TRAP_FLAG;
    if not DoSetThreadContext(LHandle, LContext) then
    begin
      DoRecordFailure(esError, PC_ERR_DBG_009, RSDbgContextFailed,
        [AThreadId, SysErrorMessage(GetLastError())]);
      // No single step will come: undo the step-over now
      if LStepOver then
      begin
        FStepOver.Remove(AThreadId);
        DoRepatch(LContext.Regs.Rip);
        DoResumeOthers();
      end;
      Exit;
    end;
  end;
  if AKind = rkStep then
    FUserStep.AddOrSetValue(AThreadId, True);
end;

function TPCDebugTarget.DoSetRip(const AThreadId: Cardinal; const AAddress: UInt64): Boolean;
var
  LHandle: THandle;
  LContext: TPCDebugContext;
begin
  Result := DoThreadHandle(AThreadId, LHandle) and DoGetThreadContext(LHandle, LContext);
  if Result then
  begin
    LContext.Regs.Rip := AAddress;
    Result := DoSetThreadContext(LHandle, LContext);
  end;
  if not Result then
    DoRecordFailure(esError, PC_ERR_DBG_009, RSDbgContextFailed,
      [AThreadId, SysErrorMessage(GetLastError())]);
end;

procedure TPCDebugTarget.DoRepatch(const AAddress: UInt64);
var
  LReason: string;
begin
  // Only while some breakpoint still wants the address
  if not IsPatched(AAddress) then
    Exit;
  if not DoWriteCode(AAddress, PC_DBG_INT3, LReason) then
    DoRecordFailure(esError, PC_ERR_DBG_008, RSDbgPatchFailed, [AAddress, LReason]);
end;

procedure TPCDebugTarget.DoSuspendOthers(const AThreadId: Cardinal);
var
  LPair: TPair<Cardinal, THandle>;
begin
  FLock.Enter();
  try
    for LPair in FThreads do
    begin
      if LPair.Key = AThreadId then
        Continue;
      if SuspendThread(LPair.Value) <> DWORD(-1) then
        FSuspended.Add(LPair.Value);
    end;
  finally
    FLock.Leave();
  end;
end;

procedure TPCDebugTarget.DoResumeOthers();
var
  LHandle: THandle;
begin
  for LHandle in FSuspended do
    ResumeThread(LHandle);
  FSuspended.Clear();
end;

function TPCDebugTarget.DoModulePath(const AFile: THandle; const AImageName: Pointer;
  const AUnicode: Word): string;
begin
  // The image's file handle names it exactly; the debuggee's own name
  // pointer only when there is no handle
  Result := DoHandlePath(AFile);
  if Result = '' then
    Result := DoReadImageName(AImageName, AUnicode);
  if Result = '' then
    Exit;
  try
    Result := TUtils.ResolvePath(Result);
  except
    // A spelling no path routine takes stays as the OS gave it (as
    // ZigBuild's ResolveReportedPath keeps a reported path)
    on Exception do
      Exit;
  end;
end;

function TPCDebugTarget.DoHandlePath(const AFile: THandle): string;
var
  LBuffer: array of WideChar;
  LLength: DWORD;
begin
  // The final path of an open file: the one spelling of a module (a loaded
  // image's, and the debugged image's own: DoFinalPath); '' = none
  Result := '';
  if (AFile = 0) or (AFile = INVALID_HANDLE_VALUE) then
    Exit;
  SetLength(LBuffer, PC_DBG_IMAGE_NAME_MAX + 1);
  LLength := KernelGetFinalPathNameByHandle(AFile, @LBuffer[0], PC_DBG_IMAGE_NAME_MAX, 0);
  if (LLength > 0) and (LLength <= PC_DBG_IMAGE_NAME_MAX) then
    SetString(Result, PWideChar(@LBuffer[0]), LLength);
end;

function TPCDebugTarget.DoFinalPath(const APath: string): string;
var
  LFile: THandle;
  LFinal: string;
begin
  // APath as DoModulePath names a load of it (8.3 parts expanded, links
  // followed): a text compare with the loader's name is then exact. APath
  // as it is when the file cannot be opened (no access: Start fails later
  // with the OS reason)
  Result := APath;
  LFile := CreateFile(PChar(APath), 0, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if LFile = INVALID_HANDLE_VALUE then
    Exit;
  try
    LFinal := DoHandlePath(LFile);
  finally
    CloseHandle(LFile);
  end;
  if LFinal = '' then
    Exit;
  try
    Result := TUtils.ResolvePath(LFinal);
  except
    on Exception do
      Result := APath;
  end;
end;

function TPCDebugTarget.ImagePath(): string;
begin
  Result := FTargetPath;
end;

function TPCDebugTarget.DoReadImageName(const AImageName: Pointer; const AUnicode: Word): string;
var
  LPointer: TBytes;
  LAddress: UInt64;
  LChunk: TBytes;
  LText: TBytes;
  LIndex: Integer;
  LCharSize: Integer;
  LEnded: Boolean;
begin
  // lpImageName: the address (in the debuggee) of a pointer to the name
  Result := '';
  if AImageName = nil then
    Exit;
  if not DoReadRaw(UInt64(NativeUInt(AImageName)), SizeOf(UInt64), LPointer) then
    Exit;
  Move(LPointer[0], LAddress, SizeOf(UInt64));
  if LAddress = 0 then
    Exit;

  if AUnicode <> 0 then
    LCharSize := 2
  else
    LCharSize := 1;
  LText := nil;
  LEnded := False;
  // Small reads: a name may end just before an unreadable page
  while (not LEnded) and (Length(LText) < PC_DBG_IMAGE_NAME_MAX * LCharSize) do
  begin
    if not DoReadRaw(LAddress + UInt64(Length(LText)), 64, LChunk) then
      Break;
    LIndex := 0;
    while LIndex + LCharSize <= Length(LChunk) do
    begin
      if (LChunk[LIndex] = 0) and ((LCharSize = 1) or (LChunk[LIndex + 1] = 0)) then
      begin
        LEnded := True;
        Break;
      end;
      Inc(LIndex, LCharSize);
    end;
    LText := LText + Copy(LChunk, 0, LIndex);
  end;
  if not LEnded then
    Exit;
  if LCharSize = 2 then
    Result := TEncoding.Unicode.GetString(LText)
  else
    Result := TEncoding.ANSI.GetString(LText);
end;

procedure TPCDebugTarget.DoReadOutput();
var
  LBuffer: TBytes;
  LPending: TBytes;
  LAvail: DWORD;
  LRead: DWORD;
  LWant: DWORD;
  LCut: Integer;
  LEvent: TPCDebugEvent;
begin
  SetLength(LBuffer, PC_DBG_OUTPUT_BUFFER);
  LPending := nil;
  try
    try
      repeat
        // Broken pipe = every writer is gone: the end
        LAvail := 0;
        if not PeekNamedPipe(FPipeRead, nil, 0, nil, @LAvail, nil) then
          Break;
        if (LAvail = 0) and (FOutputMode = domTerminal) then
        begin
          // The pseudo console may still be writing the program's last
          // screen after the exit; it breaks the pipe once done (closed at
          // EXIT_PROCESS), and only that ends the reader
          if FProcessExited.WaitFor(PC_DBG_OUTPUT_POLL_MS) = wrSignaled then
            Sleep(PC_DBG_OUTPUT_POLL_MS);
          Continue;
        end;
        if LAvail = 0 then
        begin
          // The program has ended: what it wrote is in the pipe already, so
          // an empty pipe now is the end (a process it started that holds
          // the pipe does not keep the session open)
          if FProcessExited.WaitFor(PC_DBG_OUTPUT_POLL_MS) = wrSignaled then
          begin
            LAvail := 0;
            if (not PeekNamedPipe(FPipeRead, nil, 0, nil, @LAvail, nil)) or (LAvail = 0) then
              Break;
          end
          else
            Continue;
        end;

        LWant := LAvail;
        if LWant > PC_DBG_OUTPUT_BUFFER then
          LWant := PC_DBG_OUTPUT_BUFFER;
        LRead := 0;
        if not ReadFile(FPipeRead, LBuffer[0], LWant, LRead, nil) then
          Break;
        LPending := LPending + Copy(LBuffer, 0, Integer(LRead));

        // Delivered at once, up to the last complete UTF-8 character
        LCut := DoUtf8CompleteLength(LPending, Length(LPending));
        if LCut > 0 then
        begin
          LEvent := Default(TPCDebugEvent);
          LEvent.Kind := dekOutput;
          LEvent.OutputText := TEncoding.UTF8.GetString(LPending, 0, LCut);
          DoQueue(LEvent);
          LPending := Copy(LPending, LCut, Length(LPending) - LCut);
        end;
      until False;

      // A cut character at the very end is text too (decoded as invalid)
      if Length(LPending) > 0 then
      begin
        LEvent := Default(TPCDebugEvent);
        LEvent.Kind := dekOutput;
        LEvent.OutputText := TEncoding.UTF8.GetString(LPending);
        DoQueue(LEvent);
      end;
    except
      on E: Exception do
        DoRecordFailure(esError, PC_ERR_DBG_004, RSDbgLoopFailed, [E.Message]);
    end;
  finally
    FOutputDrained.SetEvent();
  end;
end;

function TPCDebugTarget.DoThreadHandle(const AThreadId: Cardinal; out AHandle: THandle): Boolean;
begin
  FLock.Enter();
  try
    Result := FThreads.TryGetValue(AThreadId, AHandle);
  finally
    FLock.Leave();
  end;
end;

function TPCDebugTarget.DoPatchOriginal(const AAddress: UInt64; out AOriginal: Byte): Boolean;
var
  LPatch: TPCDebugPatch;
begin
  FLock.Enter();
  try
    Result := FPatches.TryGetValue(AAddress, LPatch);
    if Result then
      AOriginal := LPatch.Original
    else
      AOriginal := 0;
  finally
    FLock.Leave();
  end;
end;

function TPCDebugTarget.DoWriteCode(const AAddress: UInt64; const AValue: Byte;
  out AReason: string): Boolean;
var
  LOldProtect: DWORD;
  LUnused: DWORD;
  LWritten: SIZE_T;
begin
  // Code pages are read-only: writable for the one byte, then as they were
  AReason := '';
  Result := False;
  if not VirtualProtectEx(FProcessInfo.hProcess, Pointer(NativeUInt(AAddress)), 1,
    PAGE_EXECUTE_READWRITE, LOldProtect) then
  begin
    AReason := SysErrorMessage(GetLastError());
    Exit;
  end;
  LWritten := 0;
  Result := WriteProcessMemory(FProcessInfo.hProcess, Pointer(NativeUInt(AAddress)),
    @AValue, 1, LWritten) and (LWritten = 1);
  if not Result then
    AReason := SysErrorMessage(GetLastError());
  VirtualProtectEx(FProcessInfo.hProcess, Pointer(NativeUInt(AAddress)), 1, LOldProtect, LUnused);
  if Result then
    FlushInstructionCache(FProcessInfo.hProcess, Pointer(NativeUInt(AAddress)), 1);
end;

function TPCDebugTarget.DoReadRaw(const AAddress: UInt64; const ASize: NativeUInt;
  out ABytes: TBytes): Boolean;
var
  LRead: SIZE_T;
begin
  // One read of the whole range (T2); nothing reported
  ABytes := nil;
  if ASize = 0 then
    Exit(True);
  SetLength(ABytes, ASize);
  LRead := 0;
  Result := ReadProcessMemory(FProcessInfo.hProcess, Pointer(NativeUInt(AAddress)),
    @ABytes[0], ASize, LRead) and (LRead = ASize);
  if not Result then
    ABytes := nil;
end;

function TPCDebugTarget.Threads(): TArray<Cardinal>;
begin
  FLock.Enter();
  try
    Result := FThreads.Keys.ToArray();
  finally
    FLock.Leave();
  end;
end;

function TPCDebugTarget.GetContext(const AThreadId: Cardinal; out AContext: TPCDebugContext): Boolean;
var
  LHandle: THandle;
begin
  FillChar(AContext, SizeOf(AContext), 0);
  if not DoThreadHandle(AThreadId, LHandle) then
  begin
    FErrors.Add(esError, PC_ERR_DBG_009, RSDbgContextFailed,
      [AThreadId, SysErrorMessage(ERROR_INVALID_THREAD_ID)]);
    Exit(False);
  end;
  Result := DoGetThreadContext(LHandle, AContext);
  if not Result then
    FErrors.Add(esError, PC_ERR_DBG_009, RSDbgContextFailed,
      [AThreadId, SysErrorMessage(GetLastError())]);
end;

function TPCDebugTarget.SetContext(const AThreadId: Cardinal; const AContext: TPCDebugContext): Boolean;
var
  LHandle: THandle;
begin
  if not DoThreadHandle(AThreadId, LHandle) then
  begin
    FErrors.Add(esError, PC_ERR_DBG_009, RSDbgContextFailed,
      [AThreadId, SysErrorMessage(ERROR_INVALID_THREAD_ID)]);
    Exit(False);
  end;
  Result := DoSetThreadContext(LHandle, AContext);
  if not Result then
    FErrors.Add(esError, PC_ERR_DBG_009, RSDbgContextFailed,
      [AThreadId, SysErrorMessage(GetLastError())]);
end;

function TPCDebugTarget.ReadMemory(const AAddress: UInt64; const ASize: NativeUInt;
  out ABytes: TBytes): Boolean;
var
  LPair: TPair<UInt64, TPCDebugPatch>;
begin
  Result := DoReadRaw(AAddress, ASize, ABytes);
  if (not Result) or (ASize = 0) then
    Exit;

  // A patched byte reads as the program's own
  FLock.Enter();
  try
    for LPair in FPatches do
      if (LPair.Key >= AAddress) and (LPair.Key - AAddress < ASize) then
        ABytes[LPair.Key - AAddress] := LPair.Value.Original;
  finally
    FLock.Leave();
  end;
end;

function TPCDebugTarget.AddPatch(const AAddress: UInt64): Boolean;
var
  LPatch: TPCDebugPatch;
  LBytes: TBytes;
  LReason: string;
begin
  FLock.Enter();
  try
    // Another breakpoint at the address: counted, the saved byte kept (R1)
    if FPatches.TryGetValue(AAddress, LPatch) then
    begin
      Inc(LPatch.RefCount);
      FPatches[AAddress] := LPatch;
      Exit(True);
    end;

    if not DoReadRaw(AAddress, 1, LBytes) then
    begin
      FErrors.Add(esError, PC_ERR_DBG_008, RSDbgPatchFailed,
        [AAddress, SysErrorMessage(GetLastError())]);
      Exit(False);
    end;
    if not DoWriteCode(AAddress, PC_DBG_INT3, LReason) then
    begin
      FErrors.Add(esError, PC_ERR_DBG_008, RSDbgPatchFailed, [AAddress, LReason]);
      Exit(False);
    end;
    LPatch.Original := LBytes[0];
    LPatch.RefCount := 1;
    FPatches.Add(AAddress, LPatch);
    Result := True;
  finally
    FLock.Leave();
  end;
end;

function TPCDebugTarget.RemovePatch(const AAddress: UInt64): Boolean;
var
  LPatch: TPCDebugPatch;
  LReason: string;
begin
  FLock.Enter();
  try
    if not FPatches.TryGetValue(AAddress, LPatch) then
      Exit(False);
    if LPatch.RefCount > 1 then
    begin
      Dec(LPatch.RefCount);
      FPatches[AAddress] := LPatch;
      Exit(True);
    end;

    // The last one: the program's byte goes back. If it cannot, the int3
    // stays in the table (still recognised as ours)
    if not DoWriteCode(AAddress, LPatch.Original, LReason) then
    begin
      FErrors.Add(esError, PC_ERR_DBG_008, RSDbgPatchFailed, [AAddress, LReason]);
      Exit(False);
    end;
    FPatches.Remove(AAddress);
    Result := True;
  finally
    FLock.Leave();
  end;
end;

function TPCDebugTarget.IsPatched(const AAddress: UInt64): Boolean;
begin
  FLock.Enter();
  try
    Result := FPatches.ContainsKey(AAddress);
  finally
    FLock.Leave();
  end;
end;

function TPCDebugTarget.ProcessHandle(): THandle;
begin
  Result := FProcessInfo.hProcess;
end;

function TPCDebugTarget.ProcessId(): Cardinal;
begin
  Result := FProcessInfo.dwProcessId;
end;

function TPCDebugTarget.MainThreadId(): Cardinal;
begin
  Result := FMainThreadId;
end;

function TPCDebugTarget.ImageBase(): UInt64;
begin
  Result := FImageBase;
end;

function TPCDebugTarget.EntryAddress(): UInt64;
begin
  Result := FEntryAddress;
end;

end.
