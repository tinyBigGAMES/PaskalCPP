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
  PaskalCPP.TestSuite.Control - the control channel of a running test run

  A run owns one named shared-memory block (TPCTestControlBlock) for its
  output folder: its state, the cell and test it is in, its counts, its
  recent failures and a heartbeat, plus a one-slot mailbox for commands.
  TPCTestControl is the owner side (the run publishes into the block and
  answers the mailbox); TPCTestControlClient is the other side
  (`testbed -rpc`: read the block, send a command, wait for the end).

  The block's name is made from the resolved output folder, so the name
  being taken means a testbed already runs on that folder: the owner's
  Start refuses then (one run per output folder). Every read and write of
  the block holds a named mutex, so a reader never sees half an update.

  Dependencies: StdApp.Base, StdApp.VirtualMemory
  Notes: the owner's mailbox is answered by Service, which the suite calls
    from its stop thread; a command sent before the cells start waits in
    the mailbox and is taken at the first poll.
===============================================================================}

unit PaskalCPP.TestSuite.Control;

interface

uses
  System.SysUtils,
  StdApp.Base,
  StdApp.VirtualMemory;

const
  { PC_ERR_TS_111 }
  PC_ERR_TS_111 = 'TS0111';   // a testbed already runs on this output folder
  { PC_ERR_TS_112 }
  PC_ERR_TS_112 = 'TS0112';   // warning: the control channel cannot be opened (the run goes on)

  { PC_TS_CTL_MAGIC }
  // 'PCTB': the block is a testbed's control block
  PC_TS_CTL_MAGIC = $42544350;

  { PC_TS_CTL_VERSION }
  // Bumped whenever TPCTestControlBlock's layout changes
  PC_TS_CTL_VERSION = 1;

  { PC_TS_CTL_TEXT_LEN }
  // UTF-16 units of a text field, its terminating zero included
  PC_TS_CTL_TEXT_LEN = 256;

  { PC_TS_CTL_FAILS }
  // Failures kept in the block's ring (the newest ones)
  PC_TS_CTL_FAILS = 64;

  { PC_TS_CTL_LOCK_MS }
  // The longest wait for the block's mutex
  PC_TS_CTL_LOCK_MS = 2000;

  { PC_TS_CTL_PREFIX }
  // The block's name: this prefix, then the output folder's hash
  PC_TS_CTL_PREFIX = 'Local\PaskalCPP.Testbed.';

  { PC_TS_CTL_LOCK_SUFFIX }
  // The mutex's name: the block's name with this suffix
  PC_TS_CTL_LOCK_SUFFIX = '.lock';

type
  { TPCTestControlState }
  TPCTestControlState = (csStarting, csRunning, csStopping, csDone);

  { TPCTestControlCommand }
  TPCTestControlCommand = (ccNone, ccStop, ccAbort);

  { TPCTestControlOutcome }
  TPCTestControlOutcome = (coPass, coFail, coSkip);

  { TPCTestControlText }
  // A fixed text field: UTF-16, zero-terminated, cut to fit
  TPCTestControlText = array[0..PC_TS_CTL_TEXT_LEN - 1] of WideChar;

  { TPCTestControlFail }
  TPCTestControlFail = record
    Id: TPCTestControlText;
    Cell: TPCTestControlText;
  end;

  { TPCTestControlBlock }
  // The shared block. Plain data only (no managed types): it lives in
  // memory two processes map. Times are UTC milliseconds since 1970
  TPCTestControlBlock = record
    Magic: UInt32;
    Version: UInt32;
    ProcessId: UInt32;
    State: Int32;                   // Ord(TPCTestControlState)
    ExitCode: Int32;                // the run's exit code once State is csDone
    StartedMs: Int64;
    HeartbeatMs: Int64;             // the stop thread's last poll, or the last update
    TestStartedMs: Int64;           // when the running test started
    CellIndex: Int32;               // 1-based; 0 = no cell yet
    CellCount: Int32;
    CellText: TPCTestControlText;
    RunIndex: Int32;                // 1-based index of the running test in the whole run
    RunCount: Int32;
    TestId: TPCTestControlText;
    Passed: Int32;
    Failed: Int32;
    Skipped: Int32;
    CellPassed: Int32;
    CellFailed: Int32;
    CellSkipped: Int32;
    FailTotal: Int32;               // failures so far; the ring holds the newest
    Fails: array[0..PC_TS_CTL_FAILS - 1] of TPCTestControlFail;
    RequestSeq: UInt32;             // the client bumps it with each command
    RequestCommand: Int32;          // Ord(TPCTestControlCommand)
    ReplySeq: UInt32;               // the owner sets it to RequestSeq once taken
  end;

  { PPCTestControlBlock }
  PPCTestControlBlock = ^TPCTestControlBlock;

  { TPCTestCommandHandler }
  // Called on the stop thread with a command the mailbox brought
  TPCTestCommandHandler = reference to procedure(const ACommand: TPCTestControlCommand);

  { TPCTestControl }
  // The owner side: one per run
  TPCTestControl = class(TBaseObject)
  private
    FMemory: TVirtualMemory<Byte>;
    FMemoryErrors: TErrors;
    FMutex: THandle;
    FBlock: PPCTestControlBlock;
    FHandledSeq: UInt32;
    FOnCommand: TPCTestCommandHandler;
    function DoLock(): Boolean;
    procedure DoUnlock();
    procedure DoClose();
    function DoNameTaken(): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // False only when another testbed already runs on AOutputRoot
    // (reported as PC_ERR_TS_111). A channel that cannot be opened for any
    // other reason is a warning: the run goes on without -rpc
    function Start(const AOutputRoot: string): Boolean;
    function IsOpen(): Boolean;

    procedure BeginRun(const ARunCount: Integer; const ACellCount: Integer);
    procedure BeginCell(const ACellIndex: Integer; const ACellText: string);
    procedure BeginTest(const ARunIndex: Integer; const ATestId: string);
    procedure EndTest(const AOutcome: TPCTestControlOutcome; const ATestId: string;
      const ACellText: string);
    procedure SetStopping();
    procedure Finish(const AExitCode: Integer);

    // Stop thread: the heartbeat, then the mailbox (OnCommand)
    procedure Service();

    property OnCommand: TPCTestCommandHandler read FOnCommand write FOnCommand;
  end;

  { TPCTestControlClient }
  // The other side: `testbed -rpc`
  TPCTestControlClient = class(TBaseObject)
  private
    FMemory: TVirtualMemory<Byte>;
    FMemoryErrors: TErrors;
    FMutex: THandle;
    FBlock: PPCTestControlBlock;
    function DoLock(): Boolean;
    procedure DoUnlock();
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // False when no testbed runs on AOutputRoot
    function Open(const AOutputRoot: string): Boolean;
    procedure Close();

    // A consistent copy of the block; False when it cannot be locked
    function Snapshot(out ABlock: TPCTestControlBlock): Boolean;
    // Puts ACommand in the mailbox; ASeq is the request number to wait for
    function Send(const ACommand: TPCTestControlCommand; out ASeq: UInt32): Boolean;
    // Whether the run's process still exists
    function OwnerAlive(const ABlock: TPCTestControlBlock): Boolean;
  end;

  { TPCTestControlFormat }
  // The block's name, clock and texts, and the block as JSON for -rpc
  // (status, failures): static functions only, no instance
  TPCTestControlFormat = record
  public
    class function ChannelName(const AOutputRoot: string): string; static;
    class function NowMs(): Int64; static;
    class procedure SetText(var AText: TPCTestControlText; const AValue: string); static;
    class function GetText(const AText: TPCTestControlText): string; static;
    class function StateText(const AState: Int32): string; static;
    class function StatusJson(const ABlock: TPCTestControlBlock; const AAlive: Boolean): string; static;
    class function FailuresJson(const ABlock: TPCTestControlBlock): string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Hash,
  System.JSON,
  StdApp.Utils,
  StdApp.Resources;

const
  { PC_TS_CTL_STATE_TEXT }
  PC_TS_CTL_STATE_TEXT: array[TPCTestControlState] of string = (
    'starting',
    'running',
    'stopping',
    'done'
  );

  { PC_TS_CTL_EPOCH_MS }
  // Milliseconds from 1601-01-01 (FILETIME's origin) to 1970-01-01
  PC_TS_CTL_EPOCH_MS = 11644473600000;

{ TPCTestControlFormat }

class function TPCTestControlFormat.ChannelName(const AOutputRoot: string): string;
var
  LRoot: string;
begin
  // One name per output folder, whatever its spelling: the resolved path,
  // lower case (Windows paths compare without case), hashed
  LRoot := TUtils.ResolvePath(AOutputRoot).ToLower();
  Result := PC_TS_CTL_PREFIX + THashSHA1.GetHashString(LRoot);
end;

class function TPCTestControlFormat.NowMs(): Int64;
var
  LTime: TFileTime;
  LTicks: Int64;
begin
  // FILETIME counts 100 ns ticks since 1601 (UTC)
  GetSystemTimeAsFileTime(LTime);
  LTicks := (Int64(LTime.dwHighDateTime) shl 32) or Int64(LTime.dwLowDateTime);
  Result := (LTicks div 10000) - PC_TS_CTL_EPOCH_MS;
end;

class procedure TPCTestControlFormat.SetText(var AText: TPCTestControlText; const AValue: string);
var
  LCount: Integer;
  LI: Integer;
begin
  // Cut to the field, always zero-terminated
  LCount := Length(AValue);
  if LCount > PC_TS_CTL_TEXT_LEN - 1 then
    LCount := PC_TS_CTL_TEXT_LEN - 1;
  for LI := 0 to LCount - 1 do
    AText[LI] := AValue[LI + 1];
  AText[LCount] := #0;
end;

class function TPCTestControlFormat.GetText(const AText: TPCTestControlText): string;
var
  LCount: Integer;
begin
  // Up to the zero, never past the field
  LCount := 0;
  while (LCount < PC_TS_CTL_TEXT_LEN) and (AText[LCount] <> #0) do
    Inc(LCount);
  SetString(Result, PWideChar(@AText[0]), LCount);
end;

class function TPCTestControlFormat.StateText(const AState: Int32): string;
begin
  if (AState >= Ord(Low(TPCTestControlState))) and (AState <= Ord(High(TPCTestControlState))) then
    Result := PC_TS_CTL_STATE_TEXT[TPCTestControlState(AState)]
  else
    Result := 'unknown';
end;

class function TPCTestControlFormat.StatusJson(const ABlock: TPCTestControlBlock;
  const AAlive: Boolean): string;
var
  LJson: TJSONObject;
  LNow: Int64;
begin
  LNow := NowMs();
  LJson := TJSONObject.Create();
  try
    LJson.AddPair('state', StateText(ABlock.State));
    LJson.AddPair('alive', TJSONBool.Create(AAlive));
    LJson.AddPair('pid', TJSONNumber.Create(Int64(ABlock.ProcessId)));
    LJson.AddPair('cell', GetText(ABlock.CellText));
    LJson.AddPair('cellIndex', TJSONNumber.Create(ABlock.CellIndex));
    LJson.AddPair('cellCount', TJSONNumber.Create(ABlock.CellCount));
    LJson.AddPair('test', GetText(ABlock.TestId));
    LJson.AddPair('runIndex', TJSONNumber.Create(ABlock.RunIndex));
    LJson.AddPair('runCount', TJSONNumber.Create(ABlock.RunCount));
    LJson.AddPair('passed', TJSONNumber.Create(ABlock.Passed));
    LJson.AddPair('failed', TJSONNumber.Create(ABlock.Failed));
    LJson.AddPair('skipped', TJSONNumber.Create(ABlock.Skipped));
    LJson.AddPair('cellPassed', TJSONNumber.Create(ABlock.CellPassed));
    LJson.AddPair('cellFailed', TJSONNumber.Create(ABlock.CellFailed));
    LJson.AddPair('cellSkipped', TJSONNumber.Create(ABlock.CellSkipped));
    LJson.AddPair('elapsedMs', TJSONNumber.Create(LNow - ABlock.StartedMs));
    // How long since the run last showed it is alive, and how long the
    // running test has been going: a hang shows here
    LJson.AddPair('heartbeatAgeMs', TJSONNumber.Create(LNow - ABlock.HeartbeatMs));
    LJson.AddPair('testElapsedMs', TJSONNumber.Create(LNow - ABlock.TestStartedMs));
    if TPCTestControlState(ABlock.State) = csDone then
      LJson.AddPair('exitCode', TJSONNumber.Create(ABlock.ExitCode));
    Result := LJson.ToJSON();
  finally
    LJson.Free();
  end;
end;

class function TPCTestControlFormat.FailuresJson(const ABlock: TPCTestControlBlock): string;
var
  LJson: TJSONObject;
  LList: TJSONArray;
  LEntry: TJSONObject;
  LKept: Integer;
  LFirst: Integer;
  LI: Integer;
  LSlot: Integer;
begin
  // The ring holds the newest PC_TS_CTL_FAILS failures, oldest first here
  LKept := ABlock.FailTotal;
  if LKept > PC_TS_CTL_FAILS then
    LKept := PC_TS_CTL_FAILS;
  LFirst := ABlock.FailTotal - LKept;

  LJson := TJSONObject.Create();
  try
    LJson.AddPair('failed', TJSONNumber.Create(ABlock.FailTotal));
    LJson.AddPair('shown', TJSONNumber.Create(LKept));
    LList := TJSONArray.Create();
    LJson.AddPair('failures', LList);
    for LI := LFirst to ABlock.FailTotal - 1 do
    begin
      LSlot := LI mod PC_TS_CTL_FAILS;
      LEntry := TJSONObject.Create();
      LEntry.AddPair('id', GetText(ABlock.Fails[LSlot].Id));
      LEntry.AddPair('cell', GetText(ABlock.Fails[LSlot].Cell));
      LList.AddElement(LEntry);
    end;
    Result := LJson.ToJSON();
  finally
    LJson.Free();
  end;
end;

{ TPCTestControl }

constructor TPCTestControl.Create();
begin
  inherited;

  FMemory := nil;
  FMemoryErrors := nil;
  FMutex := 0;
  FBlock := nil;
  FHandledSeq := 0;
  FOnCommand := nil;
end;

destructor TPCTestControl.Destroy();
begin
  DoClose();

  inherited;
end;

procedure TPCTestControl.DoClose();
begin
  FBlock := nil;
  if FMemory <> nil then
  begin
    FMemory.Close();
    FreeAndNil(FMemory);
  end;
  FreeAndNil(FMemoryErrors);
  if FMutex <> 0 then
  begin
    CloseHandle(FMutex);
    FMutex := 0;
  end;
end;

function TPCTestControl.DoLock(): Boolean;
var
  LWait: DWORD;
begin
  // An abandoned mutex (a client that died holding it) is still ours now
  Result := False;
  if (FMutex = 0) or (FBlock = nil) then
    Exit;
  LWait := WaitForSingleObject(FMutex, PC_TS_CTL_LOCK_MS);
  Result := (LWait = WAIT_OBJECT_0) or (LWait = WAIT_ABANDONED);
end;

procedure TPCTestControl.DoUnlock();
begin
  ReleaseMutex(FMutex);
end;

function TPCTestControl.DoNameTaken(): Boolean;
var
  LError: TError;
begin
  Result := False;
  for LError in FMemoryErrors.GetItems() do
  begin
    if LError.Code = VM_ERR_ALLOC_NAME_EXISTS then
      Result := True;
  end;
end;

function TPCTestControl.Start(const AOutputRoot: string): Boolean;
var
  LName: string;
  LClient: TPCTestControlClient;
  LOther: TPCTestControlBlock;
  LOtherPid: UInt32;
begin
  Result := True;
  DoClose();
  try
    LName := TPCTestControlFormat.ChannelName(AOutputRoot);
    // The memory reports into its own list: a taken name is this unit's
    // error (PC_ERR_TS_111), anything else this unit's warning
    FMemoryErrors := TErrors.Create();
    FMemory := TVirtualMemory<Byte>.Create();
    FMemory.SetErrors(FMemoryErrors);
    if not FMemory.Allocate(SizeOf(TPCTestControlBlock), LName) then
    begin
      if DoNameTaken() then
      begin
        // The other run's pid, when its block can be read
        LOtherPid := 0;
        LClient := TPCTestControlClient.Create();
        try
          if LClient.Open(AOutputRoot) and LClient.Snapshot(LOther) then
            LOtherPid := LOther.ProcessId;
        finally
          LClient.Free();
        end;
        DoClose();
        FErrors.Add(esError, PC_ERR_TS_111, RSTstCtlAlreadyRunning, [AOutputRoot, LOtherPid]);
        Exit(False);
      end;
      FErrors.Add(esWarning, PC_ERR_TS_112, RSTstCtlStartFailed,
        [FMemoryErrors.GetItems().Last().Message]);
      DoClose();
      Exit;
    end;

    FMutex := CreateMutex(nil, False, PChar(LName + PC_TS_CTL_LOCK_SUFFIX));
    if FMutex = 0 then
    begin
      FErrors.Add(esWarning, PC_ERR_TS_112, RSTstCtlStartFailed,
        [SysErrorMessage(GetLastError())]);
      DoClose();
      Exit;
    end;

    FMemory.ZeroMemory();
    FBlock := PPCTestControlBlock(FMemory.Memory);
    FHandledSeq := 0;
    if DoLock() then
    begin
      try
        FBlock^.Magic := PC_TS_CTL_MAGIC;
        FBlock^.Version := PC_TS_CTL_VERSION;
        FBlock^.ProcessId := GetCurrentProcessId();
        FBlock^.State := Ord(csStarting);
        FBlock^.StartedMs := TPCTestControlFormat.NowMs();
        FBlock^.HeartbeatMs := FBlock^.StartedMs;
        FBlock^.TestStartedMs := FBlock^.StartedMs;
      finally
        DoUnlock();
      end;
    end;
  except
    on E: Exception do
    begin
      // The run goes on without -rpc
      DoClose();
      FErrors.Add(esWarning, PC_ERR_TS_112, RSTstCtlStartFailed, [E.Message]);
    end;
  end;
end;

function TPCTestControl.IsOpen(): Boolean;
begin
  Result := FBlock <> nil;
end;

procedure TPCTestControl.BeginRun(const ARunCount: Integer; const ACellCount: Integer);
begin
  if not DoLock() then
    Exit;
  try
    FBlock^.State := Ord(csRunning);
    FBlock^.RunCount := ARunCount;
    FBlock^.CellCount := ACellCount;
    FBlock^.HeartbeatMs := TPCTestControlFormat.NowMs();
  finally
    DoUnlock();
  end;
end;

procedure TPCTestControl.BeginCell(const ACellIndex: Integer; const ACellText: string);
begin
  if not DoLock() then
    Exit;
  try
    FBlock^.CellIndex := ACellIndex;
    TPCTestControlFormat.SetText(FBlock^.CellText, ACellText);
    FBlock^.CellPassed := 0;
    FBlock^.CellFailed := 0;
    FBlock^.CellSkipped := 0;
  finally
    DoUnlock();
  end;
end;

procedure TPCTestControl.BeginTest(const ARunIndex: Integer; const ATestId: string);
begin
  if not DoLock() then
    Exit;
  try
    FBlock^.RunIndex := ARunIndex;
    TPCTestControlFormat.SetText(FBlock^.TestId, ATestId);
    FBlock^.TestStartedMs := TPCTestControlFormat.NowMs();
    FBlock^.HeartbeatMs := FBlock^.TestStartedMs;
  finally
    DoUnlock();
  end;
end;

procedure TPCTestControl.EndTest(const AOutcome: TPCTestControlOutcome; const ATestId: string;
  const ACellText: string);
var
  LSlot: Integer;
begin
  if not DoLock() then
    Exit;
  try
    if AOutcome = coPass then
    begin
      Inc(FBlock^.Passed);
      Inc(FBlock^.CellPassed);
    end
    else if AOutcome = coFail then
    begin
      Inc(FBlock^.Failed);
      Inc(FBlock^.CellFailed);
      // The ring: the newest failure overwrites the oldest
      LSlot := FBlock^.FailTotal mod PC_TS_CTL_FAILS;
      TPCTestControlFormat.SetText(FBlock^.Fails[LSlot].Id, ATestId);
      TPCTestControlFormat.SetText(FBlock^.Fails[LSlot].Cell, ACellText);
      Inc(FBlock^.FailTotal);
    end
    else
    begin
      Inc(FBlock^.Skipped);
      Inc(FBlock^.CellSkipped);
    end;
    FBlock^.HeartbeatMs := TPCTestControlFormat.NowMs();
  finally
    DoUnlock();
  end;
end;

procedure TPCTestControl.SetStopping();
begin
  if not DoLock() then
    Exit;
  try
    if FBlock^.State <> Ord(csDone) then
      FBlock^.State := Ord(csStopping);
  finally
    DoUnlock();
  end;
end;

procedure TPCTestControl.Finish(const AExitCode: Integer);
begin
  if not DoLock() then
    Exit;
  try
    FBlock^.ExitCode := AExitCode;
    FBlock^.State := Ord(csDone);
    FBlock^.HeartbeatMs := TPCTestControlFormat.NowMs();
  finally
    DoUnlock();
  end;
end;

procedure TPCTestControl.Service();
var
  LCommand: TPCTestControlCommand;
begin
  LCommand := ccNone;
  if not DoLock() then
    Exit;
  try
    FBlock^.HeartbeatMs := TPCTestControlFormat.NowMs();
    if FBlock^.RequestSeq <> FHandledSeq then
    begin
      FHandledSeq := FBlock^.RequestSeq;
      if (FBlock^.RequestCommand > Ord(ccNone)) and
        (FBlock^.RequestCommand <= Ord(High(TPCTestControlCommand))) then
        LCommand := TPCTestControlCommand(FBlock^.RequestCommand);
      FBlock^.ReplySeq := FHandledSeq;
    end;
  finally
    DoUnlock();
  end;
  // Outside the lock: the handler may take its time
  if (LCommand <> ccNone) and Assigned(FOnCommand) then
    FOnCommand(LCommand);
end;

{ TPCTestControlClient }

constructor TPCTestControlClient.Create();
begin
  inherited;

  FMemory := nil;
  FMemoryErrors := nil;
  FMutex := 0;
  FBlock := nil;
end;

destructor TPCTestControlClient.Destroy();
begin
  Close();

  inherited;
end;

procedure TPCTestControlClient.Close();
begin
  FBlock := nil;
  if FMemory <> nil then
  begin
    FMemory.Close();
    FreeAndNil(FMemory);
  end;
  FreeAndNil(FMemoryErrors);
  if FMutex <> 0 then
  begin
    CloseHandle(FMutex);
    FMutex := 0;
  end;
end;

function TPCTestControlClient.Open(const AOutputRoot: string): Boolean;
var
  LName: string;
begin
  Result := False;
  Close();
  try
    LName := TPCTestControlFormat.ChannelName(AOutputRoot);
    // A block that cannot be opened is no running testbed: the memory's
    // own report of it is not shown (the caller says so in its words)
    FMemoryErrors := TErrors.Create();
    FMemory := TVirtualMemory<Byte>.Create();
    FMemory.SetErrors(FMemoryErrors);
    if not FMemory.OpenShared(LName, SizeOf(TPCTestControlBlock)) then
    begin
      Close();
      Exit;
    end;
    FBlock := PPCTestControlBlock(FMemory.Memory);
    if (FBlock^.Magic <> PC_TS_CTL_MAGIC) or (FBlock^.Version <> PC_TS_CTL_VERSION) then
    begin
      Close();
      Exit;
    end;
    FMutex := CreateMutex(nil, False, PChar(LName + PC_TS_CTL_LOCK_SUFFIX));
    if FMutex = 0 then
    begin
      Close();
      Exit;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      Close();
      if Assigned(FErrors) then
        FErrors.Add(esWarning, PC_ERR_TS_112, RSTstCtlStartFailed, [E.Message]);
    end;
  end;
end;

function TPCTestControlClient.DoLock(): Boolean;
var
  LWait: DWORD;
begin
  Result := False;
  if (FMutex = 0) or (FBlock = nil) then
    Exit;
  LWait := WaitForSingleObject(FMutex, PC_TS_CTL_LOCK_MS);
  Result := (LWait = WAIT_OBJECT_0) or (LWait = WAIT_ABANDONED);
end;

procedure TPCTestControlClient.DoUnlock();
begin
  ReleaseMutex(FMutex);
end;

function TPCTestControlClient.Snapshot(out ABlock: TPCTestControlBlock): Boolean;
begin
  ABlock := Default(TPCTestControlBlock);
  Result := DoLock();
  if not Result then
    Exit;
  try
    ABlock := FBlock^;
  finally
    DoUnlock();
  end;
end;

function TPCTestControlClient.Send(const ACommand: TPCTestControlCommand; out ASeq: UInt32): Boolean;
begin
  ASeq := 0;
  Result := DoLock();
  if not Result then
    Exit;
  try
    FBlock^.RequestCommand := Ord(ACommand);
    FBlock^.RequestSeq := FBlock^.RequestSeq + 1;
    ASeq := FBlock^.RequestSeq;
  finally
    DoUnlock();
  end;
end;

function TPCTestControlClient.OwnerAlive(const ABlock: TPCTestControlBlock): Boolean;
var
  LProcess: THandle;
begin
  Result := False;
  if ABlock.ProcessId = 0 then
    Exit;
  LProcess := OpenProcess(SYNCHRONIZE, False, ABlock.ProcessId);
  if LProcess = 0 then
    Exit;
  try
    Result := WaitForSingleObject(LProcess, 0) = WAIT_TIMEOUT;
  finally
    CloseHandle(LProcess);
  end;
end;

end.
