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
  PaskalCPP.TestSuite.Stop - TPCTestStop, the clean way out of a test run

  A run is stopped by a press: the key combo Ctrl+Shift+Alt+X (read from the
  whole keyboard, so it reaches a run with no console window), the stop
  file appearing in the output folder (taken and deleted, so making it again
  is the next press), or Press from code (the control channel's stop and
  abort, `testbed -rpc`). One thread polls the key and the file every
  PC_TS_STOP_POLL_MS and runs the poll hook (the control channel's
  heartbeat and mailbox) each round.
  First press: the suite runs no further cell; the one running finishes.
  Second press: every process the suite started (and theirs) is ended, so
  a hung cell returns at once. Ctrl+C keeps its own meaning: it is no stop.

  Dependencies: StdApp.Base, StdApp.Input, StdApp.Utils
  Notes: Start deletes a stop file left from an earlier run before the
    thread looks, so an old file stops nothing.
===============================================================================}

unit PaskalCPP.TestSuite.Stop;

interface

uses
  System.SysUtils,
  System.Classes,
  StdApp.Base;

const
  { PC_ERR_TS_110 }
  PC_ERR_TS_110 = 'TS0110';   // warning: the stop file cannot be used (the key still stops)

  { PC_TS_STOP_FILE }
  // Made in the output folder (any content) to press stop from outside
  PC_TS_STOP_FILE = 'testbed.stop';

  { PC_TS_STOP_POLL_MS }
  PC_TS_STOP_POLL_MS = 50;

  { PC_TS_STOP_KEY }
  // The letter of the combo, held with Ctrl+Shift+Alt
  PC_TS_STOP_KEY = Ord('X');

  { PC_TS_STOP_FORCE }
  // Presses at which the suite's child processes are ended
  PC_TS_STOP_FORCE = 2;

  { PC_TS_STOP_KILL_EXIT }
  // Exit code given to a child process a forced stop ends
  PC_TS_STOP_KILL_EXIT = 1;

type
  { TPCTestStop }
  TPCTestStop = class(TBaseObject)
  private
    FStopFile: string;
    FPresses: Integer;
    FThread: TThread;
    FDone: Boolean;
    FPollHook: TProc;
    procedure DoPoll();
    function DoKeyComboPressed(): Boolean;
    function DoStopFileTaken(): Boolean;
    procedure DoPress();
    procedure DoKillChildren();
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // AOutputRoot: the folder the stop file is looked for in ('' = key only)
    procedure Start(const AOutputRoot: string);
    procedure Halt();

    // A press from code (the control channel's stop / abort): the same as
    // the key or the stop file. Safe from any thread
    procedure Press();
    // Called on the stop thread every poll round, before the presses are
    // read (nil = none); set before Start
    procedure SetPollHook(const AHook: TProc);

    // Presses so far (0 = run on)
    function Presses(): Integer;
    function StopRequested(): Boolean;
    function ForceRequested(): Boolean;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.TlHelp32,
  System.SyncObjs,
  System.Generics.Collections,
  StdApp.Input,
  StdApp.Utils,
  StdApp.Resources;

{ TPCTestStop }

constructor TPCTestStop.Create();
begin
  inherited;

  FStopFile := '';
  FPresses := 0;
  FThread := nil;
  FDone := False;
  FPollHook := nil;
end;

destructor TPCTestStop.Destroy();
begin
  Halt();

  inherited;
end;

procedure TPCTestStop.Start(const AOutputRoot: string);
begin
  Halt();
  FPresses := 0;
  FDone := False;
  FStopFile := '';
  if AOutputRoot <> '' then
  begin
    try
      FStopFile := TUtils.ResolvePath(PC_TS_STOP_FILE, AOutputRoot);
      // A file left from an earlier run is no press for this one
      if FileExists(FStopFile) then
        System.SysUtils.DeleteFile(FStopFile);
    except
      on E: Exception do
      begin
        // Without the file the key still stops the run
        FStopFile := '';
        if Assigned(FErrors) then
          FErrors.Add(esWarning, PC_ERR_TS_110, RSTstStopFileFailed, [PC_TS_STOP_FILE, E.Message]);
      end;
    end;
  end;

  FThread := TThread.CreateAnonymousThread(
    procedure
    begin
      DoPoll();
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start();
end;

procedure TPCTestStop.Halt();
begin
  if FThread = nil then
    Exit;
  FDone := True;
  FThread.WaitFor();
  FThread.Free();
  FThread := nil;
end;

procedure TPCTestStop.DoPoll();
begin
  TInput.Clear();
  while not FDone do
  begin
    if Assigned(FPollHook) then
      FPollHook();
    if DoKeyComboPressed() or DoStopFileTaken() then
      DoPress();
    // A forced stop keeps ending what the running cell starts after it
    if ForceRequested() then
      DoKillChildren();
    Sleep(PC_TS_STOP_POLL_MS);
  end;
end;

function TPCTestStop.DoKeyComboPressed(): Boolean;
var
  LLetter: Boolean;
begin
  // KeyPressed is polled every round so its edge state follows the key;
  // the press counts only with all three modifiers held
  LLetter := TInput.KeyPressed(PC_TS_STOP_KEY);
  Result := LLetter and TInput.KeyDown(VK_CONTROL) and TInput.KeyDown(VK_SHIFT) and
    TInput.KeyDown(VK_MENU);
end;

function TPCTestStop.DoStopFileTaken(): Boolean;
begin
  Result := False;
  if FStopFile = '' then
    Exit;
  if not FileExists(FStopFile) then
    Exit;
  // Taken: deleted, so making it again is the next press. A file that
  // cannot be deleted yet (still being written) is taken next round
  Result := System.SysUtils.DeleteFile(FStopFile);
end;

procedure TPCTestStop.DoPress();
begin
  TInterlocked.Increment(FPresses);
end;

procedure TPCTestStop.Press();
begin
  DoPress();
end;

procedure TPCTestStop.SetPollHook(const AHook: TProc);
begin
  FPollHook := AHook;
end;

function TPCTestStop.Presses(): Integer;
begin
  Result := TInterlocked.CompareExchange(FPresses, 0, 0);
end;

function TPCTestStop.StopRequested(): Boolean;
begin
  Result := Presses() > 0;
end;

function TPCTestStop.ForceRequested(): Boolean;
begin
  Result := Presses() >= PC_TS_STOP_FORCE;
end;

procedure TPCTestStop.DoKillChildren();
var
  LSnapshot: THandle;
  LEntry: TProcessEntry32;
  LParents: TDictionary<DWORD, DWORD>;
  LOwned: TList<DWORD>;
  LPair: TPair<DWORD, DWORD>;
  LAdded: Boolean;
  LPid: DWORD;
  LProcess: THandle;
begin
  // Every process whose parent chain reaches this one: zig, clang, the
  // program a cell runs, wsl.exe and theirs
  LSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if LSnapshot = INVALID_HANDLE_VALUE then
    Exit;
  LParents := TDictionary<DWORD, DWORD>.Create();
  LOwned := TList<DWORD>.Create();
  try
    LEntry.dwSize := SizeOf(LEntry);
    if Process32First(LSnapshot, LEntry) then
    begin
      repeat
        LParents.AddOrSetValue(LEntry.th32ProcessID, LEntry.th32ParentProcessID);
      until not Process32Next(LSnapshot, LEntry);
    end;

    // Grow the owned set until no process joins it
    LOwned.Add(GetCurrentProcessId());
    repeat
      LAdded := False;
      for LPair in LParents do
      begin
        if (LPair.Key <> LPair.Value) and LOwned.Contains(LPair.Value) and
          (not LOwned.Contains(LPair.Key)) then
        begin
          LOwned.Add(LPair.Key);
          LAdded := True;
        end;
      end;
    until not LAdded;

    // Index 0 is this process: never ended
    for LPid in LOwned.ToArray() do
    begin
      if LPid = GetCurrentProcessId() then
        Continue;
      LProcess := OpenProcess(PROCESS_TERMINATE, False, LPid);
      if LProcess = 0 then
        Continue;
      // Fails only for a process already ending: nothing more to do
      TerminateProcess(LProcess, PC_TS_STOP_KILL_EXIT);
      CloseHandle(LProcess);
    end;
  finally
    LOwned.Free();
    LParents.Free();
    CloseHandle(LSnapshot);
  end;
end;

end.
