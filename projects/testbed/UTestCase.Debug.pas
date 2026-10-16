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
  UTestCase.Debug - the debugger engine on real debug builds

  TTestCase suite for PLAN-EDITOR E3: fixtures under tests\probe\dbg\
  (written by scripts\zb_ed\dbg\gen_dbg.py, never an editor), built with
  -opt debug through TPCCompiler into %TEMP%\pcpp-dbg\<case>, then run under
  TPCDebugTarget (e1): the entry stop, memory, contexts, the patch table and
  its step-over, a step, the output pipe, exceptions by chance, DLL mode;
  the engine (TPCDebugRuntime, e3) and the console debugger (TPCDebugREPL,
  e4) driven by a scripted input, its output collected.
  Expectations come from the Win32 debug contract and the fixtures' own
  behaviour run without a debugger (scripts\zb_ed\dbg\pos_control.cmd).

  Dependencies: StdApp.TestCase, StdApp.Base, StdApp.Utils,
    PaskalCPP.ZigBuild, PaskalCPP.Compiler, PaskalCPP.Debug.Target,
    UTestFrontend
===============================================================================}

unit UTestCase.Debug;

interface

uses
  StdApp.TestCase;

type

  { TPCDebugTests }
  TPCDebugTests = class(TTestCase)
  private
    procedure DoTestEntry();
    procedure DoTestOutput();
    procedure DoTestPatch();
    procedure DoTestGuard();
    procedure DoTestFirstChance();
    procedure DoTestRaise();
    procedure DoTestRaiseFinally();
    procedure DoTestFault();
    procedure DoTestDll();
    procedure DoTestDllNotLoaded();
    procedure DoTestRuntimeDll();
    procedure DoTestMissing();
    procedure DoTestSymbols();
    procedure DoTestNoDebugInfo();
    procedure DoTestRuntimeVars();
    procedure DoTestRuntimeOwners();
    procedure DoTestRuntimeRaw();
    procedure DoTestRuntimeSteps();
    procedure DoTestRuntimePause();
    procedure DoTestRuntimeTerminal();
    procedure DoTestImageSpelling();
    procedure DoTestReplSourceBreakpoints();
    procedure DoTestReplSession();
    procedure DoTestReplHeaderBreakpoint();
    procedure DoTestReplEndOfInput();
    procedure DoTestReplEntryHold();
    procedure DoTestReplLaunchFailure();
    procedure DoTestReplPause();
    procedure DoTestReplConsoleRead();
    procedure DoTestReplOutputMode();
    procedure DoTestDapSession();
    procedure DoTestDapLaunchFailure();
    procedure DoTestDapTransport();
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.ZigBuild,
  PaskalCPP.Compiler,
  PaskalCPP.Debug.Target,
  PaskalCPP.Debug.Symbols,
  PaskalCPP.Debug.Runtime,
  PaskalCPP.Debug.REPL,
  PaskalCPP.Debug.DAP,
  PaskalCPP.LSP.Transport,
  StdApp.JSON,
  PaskalCPP.AST,
  UTestFrontend;

const
  { PC_TEST_DBG_SESSION_MS }
  // A session that has not exited by then failed (the program is ended)
  PC_TEST_DBG_SESSION_MS = 60000;
  { PC_TEST_DBG_WAIT_MS }
  PC_TEST_DBG_WAIT_MS = 1000;
  { PC_TEST_DBG_ACCESS_VIOLATION }
  PC_TEST_DBG_ACCESS_VIOLATION = Cardinal($C0000005);
  { PC_TEST_DBG_EOL }
  // The fixtures' line end on a pipe: LF (probed 2026-10-10, run1: zig's
  // mingw stdio writes no CR)
  PC_TEST_DBG_EOL = #10;

type
  { TPCDebugRun }
  // What one session delivered, in order
  TPCDebugRun = record
    Stops: TArray<TPCDebugEvent>;
    Modules: TArray<TPCDebugEvent>;
    ModulesHeld: Integer;         // module loads the target reported as held (IsStopped)
    Output: string;
    Exited: Boolean;
    ExitCode: Cardinal;
  end;

  { TPCDebugOnStop }
  // Called at every stop while the process is frozen; returns how it goes on
  TPCDebugOnStop = reference to function(const ATarget: TPCDebugTarget;
    const AEvent: TPCDebugEvent): TPCResumeKind;

function DoFixturePath(const ACase: string): string;
begin
  Result := TPath.Combine(DoProbeDir('dbg\' + ACase), 'dbg_' + ACase + '.pcpp');
end;

function DoBuildFixture(const ACase: string; out AArtifact: string; out AReason: string): Boolean;
var
  LCompiler: TPCCompiler;
  LOut: string;
begin
  // tests\probe\dbg\<case>\dbg_<case>.pcpp, debug, into %TEMP%\pcpp-dbg\<case>
  AArtifact := '';
  AReason := '';
  LOut := TPath.Combine(TPath.Combine(TPath.GetTempPath(), 'pcpp-dbg'), ACase);
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetOptimizeLevel(olDebug);
    Result := LCompiler.Prepare(DoFixturePath(ACase), LOut) and
      LCompiler.Build(False);
    if Result then
      AArtifact := TPath.Combine(TPath.Combine(TPath.Combine(LOut, 'zig-out'), 'bin'),
        LCompiler.GetOutputFilename())
    else
      AReason := DoReports(LCompiler.GetErrors());
  finally
    LCompiler.Free();
  end;
end;

function DoShow(const AText: string): string;
begin
  // Line endings visible in a failure's label
  Result := AText.Replace(#13, '\r').Replace(#10, '\n');
end;

function DoSession(const ATarget: TPCDebugTarget; const AOnStop: TPCDebugOnStop): TPCDebugRun;
var
  LEvent: TPCDebugEvent;
  LStart: UInt64;
  LKind: TPCResumeKind;
begin
  // Every event until dekExited; a stop is resumed as AOnStop says
  // (rkContinue without one)
  Result := Default(TPCDebugRun);
  LStart := TUtils.GetTickCount64();
  while TUtils.GetTickCount64() - LStart < PC_TEST_DBG_SESSION_MS do
  begin
    if not ATarget.NextEvent(LEvent, PC_TEST_DBG_WAIT_MS) then
      Continue;
    case LEvent.Kind of
      dekStopped:
        begin
          Result.Stops := Result.Stops + [LEvent];
          LKind := rkContinue;
          if Assigned(AOnStop) then
            LKind := AOnStop(ATarget, LEvent);
          ATarget.Resume(LKind);
        end;
      dekModuleLoaded:
        begin
          // A module load holds the process until it is resumed
          Result.Modules := Result.Modules + [LEvent];
          if ATarget.IsStopped() then
            Inc(Result.ModulesHeld);
          ATarget.Resume(rkContinue);
        end;
      dekOutput:
        Result.Output := Result.Output + LEvent.OutputText;
      dekExited:
        begin
          Result.Exited := True;
          Result.ExitCode := LEvent.ExitCode;
          Exit;
        end;
    end;
  end;
  ATarget.Terminate();
end;

function DoCountStops(const ARun: TPCDebugRun; const AReason: TPCDebugStopReason): Integer;
var
  LEvent: TPCDebugEvent;
begin
  Result := 0;
  for LEvent in ARun.Stops do
    if LEvent.Reason = AReason then
      Inc(Result);
end;

function DoNewTarget(const AErrors: TErrors; const AProgram: string): TPCDebugTarget;
begin
  Result := TPCDebugTarget.Create();
  Result.SetErrors(AErrors);
  Result.SetProgram(AProgram, '');
  Result.SetOutputMode(domPipes);
end;

function DoMarkerLine(const ACase: string; const AMarker: string): Integer;
var
  LLines: TArray<string>;
  LIndex: Integer;
begin
  // The 1-based line of the fixture that ends in '// <AMarker>' (0 = none)
  Result := 0;
  LLines := TFile.ReadAllLines(DoFixturePath(ACase), TEncoding.UTF8);
  for LIndex := 0 to High(LLines) do
    if LLines[LIndex].EndsWith('// ' + AMarker) then
      Exit(LIndex + 1);
end;

function DoFindSymbol(const ASymbols: TArray<TPCDebugSymbol>; const ACppName: string;
  out ASymbol: TPCDebugSymbol): Boolean;
var
  LSymbol: TPCDebugSymbol;
begin
  ASymbol := Default(TPCDebugSymbol);
  for LSymbol in ASymbols do
    if LSymbol.CppName = ACppName then
    begin
      ASymbol := LSymbol;
      Exit(True);
    end;
  Result := False;
end;

function DoReadInt(const ATarget: TPCDebugTarget; const AAddress: UInt64; const ASize: Integer;
  out AValue: Int64): Boolean;
var
  LBytes: TBytes;
begin
  // A 1-, 4- or 8-byte integer of the program (1 byte unsigned, the others
  // signed)
  AValue := 0;
  Result := ATarget.ReadMemory(AAddress, ASize, LBytes) and (Length(LBytes) = ASize);
  if not Result then
    Exit;
  if ASize = 1 then
    AValue := LBytes[0]
  else if ASize = 4 then
    AValue := PInteger(@LBytes[0])^
  else if ASize = 8 then
    AValue := PInt64(@LBytes[0])^
  else
    Result := False;
end;

function DoSymbolValue(const ATarget: TPCDebugTarget; const ASymbols: TArray<TPCDebugSymbol>;
  const AFrame: TPCDebugFrame; const ACppName: string; const AFieldOffset: Cardinal;
  const ASize: Integer; out AValue: Int64): Boolean;
var
  LSymbol: TPCDebugSymbol;
  LAddress: UInt64;
begin
  // The integer at AFieldOffset inside the named symbol of AFrame
  AValue := 0;
  Result := DoFindSymbol(ASymbols, ACppName, LSymbol) and LSymbol.ValueAddress(AFrame, LAddress) and
    DoReadInt(ATarget, LAddress + AFieldOffset, ASize, AValue);
end;

function DoPlainType(const ASymbols: TPCDebugSymbols; const AModuleBase: UInt64;
  const ATypeIndex: Cardinal; out AType: TPCDebugType): Boolean;
var
  LDepth: Integer;
begin
  // The type with every typedef followed (std::int32_t is one)
  Result := ASymbols.DescribeType(AModuleBase, ATypeIndex, AType);
  LDepth := 0;
  while Result and (AType.Tag = dttTypedef) and (LDepth < 16) do
  begin
    Result := ASymbols.DescribeType(AModuleBase, AType.ElementType, AType);
    Inc(LDepth);
  end;
end;

function DoSymbolType(const ASymbols: TPCDebugSymbols; const AList: TArray<TPCDebugSymbol>;
  const ACppName: string; out AType: TPCDebugType): Boolean;
var
  LSymbol: TPCDebugSymbol;
begin
  AType := Default(TPCDebugType);
  Result := DoFindSymbol(AList, ACppName, LSymbol) and
    DoPlainType(ASymbols, LSymbol.ModuleBase, LSymbol.TypeIndex, AType);
end;

function DoFieldsText(const AType: TPCDebugType): string;
var
  LField: TPCDebugField;
  LItem: TPCDebugEnumerator;
begin
  // A layout as a failure label shows it: 'A@0 B@8', a parent part '^TBase@0',
  // enumerators 'cRed=0'
  Result := '';
  for LField in AType.Fields do
  begin
    if LField.IsBase then
      Result := Result + '^';
    Result := Result + Format('%s@%d ', [LField.CppName, LField.Offset]);
  end;
  for LItem in AType.Enumerators do
    Result := Result + Format('%s=%d ', [LItem.CppName, LItem.Value]);
  Result := Result.Trim();
end;

function DoFieldOffset(const AType: TPCDebugType; const ACppName: string; out AOffset: Cardinal): Boolean;
var
  LField: TPCDebugField;
begin
  AOffset := 0;
  for LField in AType.Fields do
    if LField.CppName = ACppName then
    begin
      AOffset := LField.Offset;
      Exit(True);
    end;
  Result := False;
end;

function DoNamesText(const ASymbols: TArray<TPCDebugSymbol>): string;
var
  LSymbol: TPCDebugSymbol;
begin
  Result := '';
  for LSymbol in ASymbols do
    Result := Result + LSymbol.CppName + ' ';
  Result := Result.Trim();
end;

type
  { TPCRuntimeRun }
  // What a TPCDebugRuntime session delivered besides its stops
  TPCRuntimeRun = record
    Output: string;
    Exited: Boolean;
    ExitCode: Cardinal;
  end;

function DoBuildProgram(const ACase: string; out AArtifact: string; out AReason: string): TPCCompiler;
var
  LOut: string;
begin
  // As DoBuildFixture, the compiler kept: it holds the analysed tree the
  // runtime names variables from (the caller frees it)
  AArtifact := '';
  AReason := '';
  LOut := TPath.Combine(TPath.Combine(TPath.GetTempPath(), 'pcpp-dbg'), ACase);
  Result := TPCCompiler.Create();
  Result.SetOptimizeLevel(olDebug);
  if Result.Prepare(DoFixturePath(ACase), LOut) and Result.Build(False) then
    AArtifact := TPath.Combine(TPath.Combine(TPath.Combine(LOut, 'zig-out'), 'bin'),
      Result.GetOutputFilename())
  else
    AReason := DoReports(Result.GetErrors());
end;

function DoNextStop(const ARuntime: TPCDebugRuntime; var ARun: TPCRuntimeRun; out AEvent: TPCDebugEvent): Boolean;
var
  LStart: UInt64;
begin
  // Events until the next stop (True) or the session's end (False); the
  // output is collected
  Result := False;
  AEvent := Default(TPCDebugEvent);
  LStart := TUtils.GetTickCount64();
  while TUtils.GetTickCount64() - LStart < PC_TEST_DBG_SESSION_MS do
  begin
    if not ARuntime.NextEvent(AEvent, PC_TEST_DBG_WAIT_MS) then
      Continue;
    case AEvent.Kind of
      dekStopped:
        Exit(True);
      dekOutput:
        ARun.Output := ARun.Output + AEvent.OutputText;
      dekExited:
        begin
          ARun.Exited := True;
          ARun.ExitCode := AEvent.ExitCode;
          Exit(False);
        end;
    end;
  end;
end;

procedure DoFinish(const ARuntime: TPCDebugRuntime; var ARun: TPCRuntimeRun);
var
  LEvent: TPCDebugEvent;
begin
  // The rest of the session: every stop continued, to the exit
  while DoNextStop(ARuntime, ARun, LEvent) do
    ARuntime.ContinueExecution();
  if not ARun.Exited then
    ARuntime.Terminate();
end;

function DoTop(const ARuntime: TPCDebugRuntime): TPCDebugStackItem;
var
  LStack: TArray<TPCDebugStackItem>;
begin
  // The stopped thread's top frame
  Result := Default(TPCDebugStackItem);
  LStack := ARuntime.StackTrace(ARuntime.StoppedThread());
  if Length(LStack) > 0 then
    Result := LStack[0];
end;

function DoStackText(const AStack: TArray<TPCDebugStackItem>): string;
var
  LItem: TPCDebugStackItem;
begin
  // 'Inner:24 Outer:53 ...' for a failure's label (.pcpp frames only)
  Result := '';
  for LItem in AStack do
    if LItem.IsPcpp then
      Result := Result + LItem.RoutineName + ':' + IntToStr(LItem.Line) + ' ';
  Result := Result.Trim();
end;

function DoScopesText(const AScopes: TArray<TPCDebugScopeKind>): string;
var
  LKind: TPCDebugScopeKind;
begin
  // 'params locals globals' (the kinds Scopes lists, in order)
  Result := '';
  for LKind in AScopes do
  begin
    case LKind of
      dskParams:
        Result := Result + 'params ';
      dskLocals:
        Result := Result + 'locals ';
    else
      Result := Result + 'globals ';
    end;
  end;
  Result := Result.Trim();
end;

function DoFindValue(const AValues: TArray<TPCDebugValue>; const AName: string; out AValue: TPCDebugValue): Boolean;
var
  LValue: TPCDebugValue;
begin
  for LValue in AValues do
    if LValue.DisplayName = AName then
    begin
      AValue := LValue;
      Exit(True);
    end;
  AValue := Default(TPCDebugValue);
  Result := False;
end;

function DoTextOf(const AValues: TArray<TPCDebugValue>; const AName: string): string;
var
  LValue: TPCDebugValue;
begin
  // A listed value's text; '(none)' when the name is not listed
  if DoFindValue(AValues, AName, LValue) then
    Result := LValue.ValueText
  else
    Result := '(none)';
end;

function DoValuesText(const AValues: TArray<TPCDebugValue>): string;
var
  LValue: TPCDebugValue;
begin
  // 'name: type = value; ...' for a failure's label
  Result := '';
  for LValue in AValues do
    Result := Result + LValue.DisplayName + ': ' + LValue.TypeText + ' = ' + LValue.ValueText + '; ';
  Result := DoShow(Result.Trim());
end;

function DoEvalText(const ARuntime: TPCDebugRuntime; const AFrameId: Integer; const AText: string;
  out AOk: Boolean): string;
var
  LValue: TPCDebugValue;
begin
  AOk := ARuntime.Evaluate(AFrameId, AText, LValue);
  Result := LValue.ValueText;
end;

function DoNewRuntime(const AErrors: TErrors; const AProgram: TPCCompiler; const AExe: string): TPCDebugRuntime;
begin
  Result := TPCDebugRuntime.Create();
  Result.SetErrors(AErrors);
  if AProgram <> nil then
    Result.SetProgram(AProgram.GetMainModule());
  Result.SetTarget(AExe, '');
  Result.SetOutputMode(domPipes);
end;

{ TPCDebugTests }

constructor TPCDebugTests.Create();
begin
  inherited;

  Title := 'Debug';
  RegisterTest('entry', DoTestEntry);
  RegisterTest('output', DoTestOutput);
  RegisterTest('patch', DoTestPatch);
  RegisterTest('guard', DoTestGuard);
  RegisterTest('first_chance', DoTestFirstChance);
  RegisterTest('raise', DoTestRaise);
  RegisterTest('raise_finally', DoTestRaiseFinally);
  RegisterTest('fault', DoTestFault);
  RegisterTest('dll', DoTestDll);
  RegisterTest('dll_not_loaded', DoTestDllNotLoaded);
  RegisterTest('runtime_dll', DoTestRuntimeDll);
  RegisterTest('missing', DoTestMissing);
  RegisterTest('symbols', DoTestSymbols);
  RegisterTest('no_debug_info', DoTestNoDebugInfo);
  RegisterTest('runtime_vars', DoTestRuntimeVars);
  RegisterTest('runtime_owners', DoTestRuntimeOwners);
  RegisterTest('runtime_raw', DoTestRuntimeRaw);
  RegisterTest('runtime_steps', DoTestRuntimeSteps);
  RegisterTest('runtime_pause', DoTestRuntimePause);
  RegisterTest('runtime_terminal', DoTestRuntimeTerminal);
  RegisterTest('image_spelling', DoTestImageSpelling);
  RegisterTest('repl_source_bps', DoTestReplSourceBreakpoints);
  RegisterTest('repl_session', DoTestReplSession);
  RegisterTest('repl_header_bp', DoTestReplHeaderBreakpoint);
  RegisterTest('repl_eof', DoTestReplEndOfInput);
  RegisterTest('repl_entry_hold', DoTestReplEntryHold);
  RegisterTest('repl_launch_fail', DoTestReplLaunchFailure);
  RegisterTest('repl_pause', DoTestReplPause);
  RegisterTest('repl_console_read', DoTestReplConsoleRead);
  RegisterTest('repl_output_mode', DoTestReplOutputMode);
  RegisterTest('dap_session', DoTestDapSession);
  RegisterTest('dap_launch_fail', DoTestDapLaunchFailure);
  RegisterTest('dap_transport', DoTestDapTransport);
end;

procedure TPCDebugTests.Run();
begin
  inherited;
end;

procedure TPCDebugTests.DoTestEntry();
var
  LExe: string;
  LReason: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LRun: TPCDebugRun;
  LContextOk: Boolean;
  LRip: UInt64;
  LMz: Boolean;
  LEmpty: Boolean;
begin
  Check(DoBuildFixture('hello', LExe, LReason), 'entry: dbg_hello builds (' + LReason + ')');
  if LExe = '' then
    Exit;
  LContextOk := False;
  LRip := 0;
  LMz := False;
  LEmpty := False;
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LExe);
  try
    Check(LTarget.Start(), 'entry: starts (' + DoReports(LErrors) + ')');
    LRun := DoSession(LTarget,
      function(const ATarget: TPCDebugTarget; const AEvent: TPCDebugEvent): TPCResumeKind
      var
        LContext: TPCDebugContext;
        LBytes: TBytes;
      begin
        Result := rkContinue;
        if AEvent.Reason <> dsrEntry then
          Exit;
        LContextOk := ATarget.GetContext(AEvent.ThreadId, LContext);
        LRip := LContext.Regs.Rip;
        LMz := ATarget.ReadMemory(ATarget.ImageBase(), 2, LBytes) and (Length(LBytes) = 2) and
          (LBytes[0] = Ord('M')) and (LBytes[1] = Ord('Z'));
        LEmpty := ATarget.ReadMemory(ATarget.ImageBase(), 0, LBytes) and (Length(LBytes) = 0);
      end);

    Check((Length(LRun.Stops) = 1) and (LRun.Stops[0].Reason = dsrEntry),
      'entry: one stop, the loader''s break (%d stops)', [Length(LRun.Stops)]);
    Check(LContextOk and (LRip <> 0), 'entry: the stopped thread''s context reads (aligned CONTEXT)');
    Check(LMz, 'entry: the image in memory starts with MZ');
    Check(LEmpty, 'entry: a read of 0 bytes is empty, not a failure');
    Check((Length(LRun.Modules) > 0) and TUtils.SamePath(LRun.Modules[0].ModulePath, LExe) and
      (LRun.Modules[0].Address = LTarget.ImageBase()),
      'entry: the first module is the exe, by its full path, at the image base');
    Check(LRun.Exited and (LRun.ExitCode = 0), 'entry: exits with 0 (%d)', [LRun.ExitCode]);
    Check(LErrors.Count() = 0, 'entry: nothing reported (' + DoReports(LErrors) + ')');
  finally
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestOutput();
var
  LExe: string;
  LReason: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LRun: TPCDebugRun;
  LExpected: string;
begin
  // stdout and stderr on one pipe in the order written (C stdio, flushed),
  // then println's own buffer at exit; UTF-8 kept
  Check(DoBuildFixture('hello', LExe, LReason), 'output: dbg_hello builds (' + LReason + ')');
  if LExe = '' then
    Exit;
  LExpected := 'out 1' + PC_TEST_DBG_EOL + 'err 1' + PC_TEST_DBG_EOL + 'out 2' +
    PC_TEST_DBG_EOL + 'out 3 ' + #$00E9 + PC_TEST_DBG_EOL;
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LExe);
  try
    Check(LTarget.Start(), 'output: starts (' + DoReports(LErrors) + ')');
    LRun := DoSession(LTarget, nil);
    Check(LRun.Output.StartsWith(LExpected), 'output: the program''s text in order (%s)',
      [DoShow(LRun.Output)]);
    Check(LRun.Exited and (LRun.ExitCode = 0), 'output: exits with 0 (%d)', [LRun.ExitCode]);
    Check(LErrors.Count() = 0, 'output: nothing reported (' + DoReports(LErrors) + ')');
  finally
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestPatch();
var
  LExe: string;
  LReason: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LRun: TPCDebugRun;
  LEntry: UInt64;
  LOriginal: Integer;
  LAdded: Boolean;
  LMasked: Boolean;
  LHitRip: UInt64;
  LHitThread: Cardinal;
  LCounted: Boolean;
  LStepAddress: UInt64;
begin
  // A patch at the process start address: hit there (RIP back on it), a
  // second AddPatch counted, a step off it, then the program runs as written
  Check(DoBuildFixture('hello', LExe, LReason), 'patch: dbg_hello builds (' + LReason + ')');
  if LExe = '' then
    Exit;
  LEntry := 0;
  LOriginal := -1;
  LAdded := False;
  LMasked := False;
  LHitRip := 0;
  LHitThread := 0;
  LCounted := False;
  LStepAddress := 0;
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LExe);
  try
    Check(LTarget.Start(), 'patch: starts (' + DoReports(LErrors) + ')');
    LRun := DoSession(LTarget,
      function(const ATarget: TPCDebugTarget; const AEvent: TPCDebugEvent): TPCResumeKind
      var
        LBytes: TBytes;
        LContext: TPCDebugContext;
      begin
        Result := rkContinue;
        case AEvent.Reason of
          dsrEntry:
            begin
              LEntry := ATarget.EntryAddress();
              if ATarget.ReadMemory(LEntry, 1, LBytes) then
                LOriginal := LBytes[0];
              LAdded := ATarget.AddPatch(LEntry) and ATarget.IsPatched(LEntry);
              LMasked := ATarget.ReadMemory(LEntry, 1, LBytes) and (LBytes[0] = LOriginal);
            end;
          dsrBreakpoint:
            begin
              LHitThread := AEvent.ThreadId;
              if ATarget.GetContext(AEvent.ThreadId, LContext) then
                LHitRip := LContext.Regs.Rip;
              LCounted := ATarget.AddPatch(LEntry) and ATarget.RemovePatch(LEntry) and
                ATarget.IsPatched(LEntry);
              Result := rkStep;
            end;
          dsrStep:
            LStepAddress := AEvent.Address;
        end;
      end);

    Check((LEntry <> 0) and (LOriginal >= 0) and (LOriginal <> PC_DBG_INT3),
      'patch: the start address reads (byte %d)', [LOriginal]);
    Check(LAdded, 'patch: AddPatch takes the start address');
    Check(LMasked, 'patch: a patched byte reads as the program''s own');
    Check((Length(LRun.Stops) = 3) and (LRun.Stops[1].Reason = dsrBreakpoint) and
      (LRun.Stops[1].Address = LEntry) and (LRun.Stops[2].Reason = dsrStep),
      'patch: entry, the hit at the patch, the step (%d stops)', [Length(LRun.Stops)]);
    Check(LHitRip = LEntry, 'patch: RIP is back on the patched address');
    Check(LHitThread = LTarget.MainThreadId(), 'patch: hit on the main thread');
    Check(LCounted, 'patch: a second AddPatch is counted (one RemovePatch leaves it patched)');
    Check((LStepAddress <> 0) and (LStepAddress <> LEntry), 'patch: the step stops past the patch');
    Check(LRun.Output.StartsWith('out 1'), 'patch: the program ran as written after the step-over (%s)',
      [DoShow(LRun.Output)]);
    Check(LRun.Exited and (LRun.ExitCode = 0), 'patch: exits with 0 (%d)', [LRun.ExitCode]);
    Check(LErrors.Count() = 0, 'patch: nothing reported (' + DoReports(LErrors) + ')');
  finally
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestGuard();
var
  LExe: string;
  LReason: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LRun: TPCDebugRun;
begin
  // A guarded fault is a first chance only: by default the guard takes it
  Check(DoBuildFixture('guard', LExe, LReason), 'guard: dbg_guard builds (' + LReason + ')');
  if LExe = '' then
    Exit;
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LExe);
  try
    Check(LTarget.Start(), 'guard: starts (' + DoReports(LErrors) + ')');
    LRun := DoSession(LTarget, nil);
    Check(DoCountStops(LRun, dsrException) = 0, 'guard: no exception stop');
    Check(LRun.Output.Contains('guarded 3') and LRun.Output.Contains('after'),
      'guard: the guard handled the fault (%s)', [DoShow(LRun.Output)]);
    Check(LRun.Exited and (LRun.ExitCode = 0), 'guard: exits with 0 (%d)', [LRun.ExitCode]);
  finally
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestFirstChance();
var
  LExe: string;
  LReason: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LRun: TPCDebugRun;
  LEvent: TPCDebugEvent;
  LFound: Boolean;
begin
  // Asked for, the first chance stops; resumed, the guard still takes it
  Check(DoBuildFixture('guard', LExe, LReason), 'first_chance: dbg_guard builds (' + LReason + ')');
  if LExe = '' then
    Exit;
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LExe);
  try
    LTarget.SetBreakOnFirstChance(True);
    Check(LTarget.Start(), 'first_chance: starts (' + DoReports(LErrors) + ')');
    LRun := DoSession(LTarget, nil);
    LFound := False;
    for LEvent in LRun.Stops do
      if (LEvent.Reason = dsrException) and LEvent.FirstChance and
        (LEvent.ExceptionCode = PC_TEST_DBG_ACCESS_VIOLATION) then
        LFound := True;
    Check(LFound, 'first_chance: the access violation stops as a first chance');
    Check(LRun.Output.Contains('guarded 3'), 'first_chance: resumed, the guard handled it (%s)',
      [DoShow(LRun.Output)]);
    Check(LRun.Exited and (LRun.ExitCode = 0), 'first_chance: exits with 0 (%d)', [LRun.ExitCode]);
  finally
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestRaise();
var
  LExe: string;
  LReason: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LRun: TPCDebugRun;
begin
  // An unhandled raise is the runtime's (::pcpp::enter): reported, exit 1,
  // as run alone; a first chance only, so no stop
  Check(DoBuildFixture('raise', LExe, LReason), 'raise: dbg_raise builds (' + LReason + ')');
  if LExe = '' then
    Exit;
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LExe);
  try
    Check(LTarget.Start(), 'raise: starts (' + DoReports(LErrors) + ')');
    LRun := DoSession(LTarget, nil);
    Check(DoCountStops(LRun, dsrException) = 0, 'raise: no exception stop');
    Check(LRun.Output.Contains('before') and
      (LRun.Output.IndexOf('before') < LRun.Output.IndexOf('unhandled exception 7: last')),
      'raise: the earlier output, then the runtime''s report (%s)', [DoShow(LRun.Output)]);
    Check(LRun.Exited and (LRun.ExitCode = 1), 'raise: exits with 1 (%d)', [LRun.ExitCode]);
  finally
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestRaiseFinally();
var
  LExe: string;
  LReason: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LRun: TPCDebugRun;
begin
  // A guard with only a finally: the finally runs, then the raise goes on
  // out (nothing after the guard runs) to the runtime's report, exit 1
  Check(DoBuildFixture('raise_finally', LExe, LReason),
    'raise_finally: dbg_raise_finally builds (' + LReason + ')');
  if LExe = '' then
    Exit;
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LExe);
  try
    Check(LTarget.Start(), 'raise_finally: starts (' + DoReports(LErrors) + ')');
    LRun := DoSession(LTarget, nil);
    Check(LRun.Output.Contains('finally ran') and LRun.Output.Contains('unhandled exception 7: last') and
      (LRun.Output.IndexOf('finally ran') < LRun.Output.IndexOf('unhandled exception')) and
      (not LRun.Output.Contains('unreached')),
      'raise_finally: the finally, then the report, nothing after the guard (%s)',
      [DoShow(LRun.Output)]);
    Check(LRun.Exited and (LRun.ExitCode = 1), 'raise_finally: exits with 1 (%d)', [LRun.ExitCode]);
  finally
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestFault();
var
  LExe: string;
  LReason: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LRun: TPCDebugRun;
begin
  // An unguarded fault: a second-chance stop, then the process ends with it
  Check(DoBuildFixture('fault', LExe, LReason), 'fault: dbg_fault builds (' + LReason + ')');
  if LExe = '' then
    Exit;
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LExe);
  try
    Check(LTarget.Start(), 'fault: starts (' + DoReports(LErrors) + ')');
    LRun := DoSession(LTarget, nil);
    Check((DoCountStops(LRun, dsrException) = 1) and (Length(LRun.Stops) = 2) and
      (not LRun.Stops[1].FirstChance) and (LRun.Stops[1].ExceptionCode = PC_TEST_DBG_ACCESS_VIOLATION),
      'fault: one second-chance access violation stop (%d stops)', [Length(LRun.Stops)]);
    Check(LRun.Exited and (LRun.ExitCode = PC_TEST_DBG_ACCESS_VIOLATION),
      'fault: exits with the access violation ($%x)', [LRun.ExitCode]);
  finally
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestDll();
var
  LLib: string;
  LHost: string;
  LReason: string;
  LCopy: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LRun: TPCDebugRun;
  LEvent: TPCDebugEvent;
  LLoaded: Boolean;
begin
  // DLL mode: the host loads the dll from its own folder (copied there)
  Check(DoBuildFixture('lib', LLib, LReason), 'dll: dbg_lib builds (' + LReason + ')');
  Check(DoBuildFixture('host', LHost, LReason), 'dll: dbg_host builds (' + LReason + ')');
  if (LLib = '') or (LHost = '') then
    Exit;
  LCopy := TPath.Combine(TPath.GetDirectoryName(LHost), TPath.GetFileName(LLib));
  LReason := '';
  try
    TFile.Copy(LLib, LCopy, True);
  except
    on E: Exception do
      LReason := E.Message;
  end;
  Check(LReason = '', 'dll: copied beside the host (' + LReason + ')');
  if LReason <> '' then
    Exit;

  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LCopy);
  try
    LTarget.SetHost(LHost, '');
    Check(LTarget.Start(), 'dll: starts (' + DoReports(LErrors) + ')');
    LRun := DoSession(LTarget, nil);
    LLoaded := False;
    for LEvent in LRun.Modules do
      if TUtils.SamePath(LEvent.ModulePath, LCopy) then
        LLoaded := True;
    Check(LLoaded, 'dll: the dll''s load event names it by its full path');
    // The dll's breakpoints go in before its code runs: every load holds
    Check(LRun.ModulesHeld = Length(LRun.Modules), 'dll: every module load holds the process (%d of %d)',
      [LRun.ModulesHeld, Length(LRun.Modules)]);
    Check((Length(LRun.Modules) > 0) and TUtils.SamePath(LRun.Modules[0].ModulePath, LHost),
      'dll: the first module is the host');
    Check(LRun.Output.Contains('loaded true'), 'dll: the host loaded it (%s)', [DoShow(LRun.Output)]);
    Check(LRun.Output.Contains('sum 7'), 'dll: the host called LibAdd(2, 3) (%s)', [DoShow(LRun.Output)]);
    Check(LRun.Exited and (LRun.ExitCode = 0), 'dll: exits with 0 (%d)', [LRun.ExitCode]);
    Check(LErrors.Count() = 0, 'dll: nothing reported (' + DoReports(LErrors) + ')');
  finally
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestDllNotLoaded();
var
  LLib: string;
  LHost: string;
  LReason: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LRun: TPCDebugRun;
begin
  // The host loads its own copy, never the dll named: DB0014 at the exit
  Check(DoBuildFixture('lib', LLib, LReason), 'dll_not_loaded: dbg_lib builds (' + LReason + ')');
  Check(DoBuildFixture('host', LHost, LReason), 'dll_not_loaded: dbg_host builds (' + LReason + ')');
  if (LLib = '') or (LHost = '') then
    Exit;
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LLib);
  try
    LTarget.SetHost(LHost, '');
    Check(LTarget.Start(), 'dll_not_loaded: starts (' + DoReports(LErrors) + ')');
    LRun := DoSession(LTarget, nil);
    Check(LRun.Exited and (LRun.ExitCode = 0), 'dll_not_loaded: exits with 0 (%d)', [LRun.ExitCode]);
    Check(DoCodes(LErrors) = PC_ERR_DBG_014, 'dll_not_loaded: DB0014 reported (' + DoReports(LErrors) + ')');
    Check(not LErrors.HasErrors(), 'dll_not_loaded: a warning, not an error');
  finally
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestMissing();
var
  LExe: string;
  LReason: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LMissing: string;
begin
  LMissing := TPath.Combine(TPath.Combine(TPath.GetTempPath(), 'pcpp-dbg'), 'no_such_program.exe');
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LMissing);
  try
    Check(not LTarget.Start(), 'missing: a missing program does not start');
    Check(DoCodes(LErrors) = PC_ERR_DBG_001, 'missing: DB0001 (' + DoReports(LErrors) + ')');
  finally
    LTarget.Free();
    LErrors.Free();
  end;

  Check(DoBuildFixture('lib', LExe, LReason), 'missing: dbg_lib builds (' + LReason + ')');
  if LExe = '' then
    Exit;
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LExe);
  try
    LTarget.SetHost(LMissing, '');
    Check(not LTarget.Start(), 'missing: a missing host does not start');
    Check(DoCodes(LErrors) = PC_ERR_DBG_002, 'missing: DB0002 (' + DoReports(LErrors) + ')');
  finally
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestSymbols();
var
  LExe: string;
  LReason: string;
  LSource: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LSymbols: TPCDebugSymbols;
  LRun: TPCDebugRun;
  LBodyLine: Integer;
  LRetLine: Integer;
  LEndLine: Integer;
  LForLine: Integer;
  LCallLine: Integer;
  LOuterLine: Integer;
  LHit: Boolean;
begin
  // dbg_syms (gen_dbg.py) under the debugger: lines resolved at the entry
  // stop (every address patched), then at the hit on M_INNER_BODY the line,
  // the function, the walk, and both frames' locals read with their own
  // registers, the types' layouts and a global
  Check(DoBuildFixture('syms', LExe, LReason), 'symbols: dbg_syms builds (' + LReason + ')');
  if LExe = '' then
    Exit;
  LSource := DoFixturePath('syms');
  LBodyLine := DoMarkerLine('syms', 'M_INNER_BODY');
  LRetLine := DoMarkerLine('syms', 'M_INNER_RET');
  LEndLine := DoMarkerLine('syms', 'M_INNER_END');
  LForLine := DoMarkerLine('syms', 'M_FOR');
  LCallLine := DoMarkerLine('syms', 'M_CALL');
  // The next routine's header is its prologue: a code-less line before it
  // lands on Outer's first line past the prologue (e5b)
  LOuterLine := DoMarkerLine('syms', 'M_OUTER_FIRST');
  Check((LBodyLine > 0) and (LRetLine > 0) and (LEndLine > 0) and (LForLine > 0) and (LCallLine > 0) and
    (LOuterLine > 0), 'symbols: the fixture has its markers');
  LHit := False;
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LExe);
  LSymbols := TPCDebugSymbols.Create();
  try
    LSymbols.SetErrors(LErrors);
    Check(LTarget.Start(), 'symbols: starts (' + DoReports(LErrors) + ')');
    LRun := DoSession(LTarget,
      function(const ATarget: TPCDebugTarget; const AEvent: TPCDebugEvent): TPCResumeKind
      var
        LActual: Integer;
        LAddresses: TArray<UInt64>;
        LAddress: UInt64;
        LContext: TPCDebugContext;
        LLine: TPCDebugLine;
        LName: string;
        LStart: UInt64;
        LSize: Cardinal;
        LFrames: TArray<TPCDebugFrame>;
        LTop: TArray<TPCDebugSymbol>;
        LCaller: TArray<TPCDebugSymbol>;
        LSymbol: TPCDebugSymbol;
        LType: TPCDebugType;
        LBaseType: TPCDebugType;
        LValue: Int64;
        LOffset: Cardinal;
        LBaseOffset: Cardinal;
        LField: TPCDebugField;
        LHasBase: Boolean;
      begin
        Result := rkContinue;
        if AEvent.Reason = dsrEntry then
        begin
          Check(LSymbols.Open(ATarget.ProcessHandle()) and
            LSymbols.AddModule(LExe, ATarget.ImageBase(), True),
            'symbols: opened on the process, the exe added (' + DoReports(LErrors) + ')');
          Check(LSymbols.ResolveLine(LSource, LBodyLine, LActual, LAddresses) and (LActual = LBodyLine),
            'symbols: M_INNER_BODY resolves at its own line (%d)', [LActual]);
          for LAddress in LAddresses do
            ATarget.AddPatch(LAddress);
          // A line without code moves FORWARD to the next line that has
          // some (e2 probe: here the next routine's header)
          Check(LSymbols.ResolveLine(LSource, LEndLine, LActual, LAddresses) and (LActual = LOuterLine),
            'symbols: the end line after a return moves to the next line with code (%d, want %d)',
            [LActual, LOuterLine]);
          Check(LSymbols.ResolveLine(LSource, LRetLine, LActual, LAddresses) and (LActual = LRetLine),
            'symbols: M_INNER_RET resolves at its own line (%d)', [LActual]);
          Check(LSymbols.ResolveLine(LSource, LForLine, LActual, LAddresses) and (LActual = LForLine) and
            (Length(LAddresses) >= 2), 'symbols: the for line has every one of its code ranges (%d)',
            [Length(LAddresses)]);
          Check(not LSymbols.ResolveLine(TPath.Combine(TPath.GetDirectoryName(LSource), 'no_such.pcpp'), 1,
            LActual, LAddresses), 'symbols: a file the program does not hold resolves to nothing');
          Exit;
        end;
        if (AEvent.Reason <> dsrBreakpoint) or LHit then
          Exit;
        LHit := True;

        // The stop: line, function
        Check(ATarget.GetContext(AEvent.ThreadId, LContext), 'symbols: the stopped thread''s context');
        Check(LSymbols.LineAt(LContext.Regs.Rip, LLine) and (LLine.Line = LBodyLine) and LLine.IsPcpp and
          TUtils.SamePath(LLine.FileName, LSource),
          'symbols: the stop is on M_INNER_BODY of the .pcpp (%s:%d)', [LLine.FileName, LLine.Line]);
        Check(LSymbols.FunctionAt(LContext.Regs.Rip, LName, LStart, LSize) and
          (LName = 'pcpp_m_dbg_syms::Inner') and (LStart <= LContext.Regs.Rip) and
          (LContext.Regs.Rip < LStart + LSize), 'symbols: the function at the stop (%s)', [LName]);

        // The walk: Inner, Outer at the call's line, the module body
        LFrames := LSymbols.WalkStack(LContext,
          function(const AAddress: UInt64; const ASize: NativeUInt; out ABytes: TBytes): Boolean
          begin
            Result := ATarget.ReadMemory(AAddress, ASize, ABytes);
          end);
        Check(Length(LFrames) >= 3, 'symbols: the walk has 3 frames or more (%d)', [Length(LFrames)]);
        if Length(LFrames) < 3 then
          Exit;
        Check((LFrames[0].FunctionName = 'pcpp_m_dbg_syms::Inner') and LFrames[0].HasLine and
          (LFrames[0].Line.Line = LBodyLine) and (LFrames[0].LookupAddress = LContext.Regs.Rip),
          'symbols: frame 0 is Inner at the stop (%s:%d)', [LFrames[0].FunctionName, LFrames[0].Line.Line]);
        Check((LFrames[1].FunctionName = 'pcpp_m_dbg_syms::Outer') and LFrames[1].HasLine and
          (LFrames[1].Line.Line = LCallLine), 'symbols: frame 1 is Outer at the call (%s:%d, want %d)',
          [LFrames[1].FunctionName, LFrames[1].Line.Line, LCallLine]);
        Check(LFrames[2].FunctionName = 'pcpp_m_dbg_syms::pcpp_main_body',
          'symbols: frame 2 is the module body (%s)', [LFrames[2].FunctionName]);

        // Frame 0: the parameter, read with frame 0's registers
        Check(LSymbols.FrameSymbols(LFrames[0], LTop), 'symbols: frame 0''s scope (' + DoReports(LErrors) + ')');
        Check(DoFindSymbol(LTop, 'AValue', LSymbol) and LSymbol.IsParam and LSymbol.IsRegRel,
          'symbols: AValue is a register-relative parameter (%s)', [DoNamesText(LTop)]);
        Check(DoSymbolValue(ATarget, LTop, LFrames[0], 'AValue', 0, 4, LValue) and (LValue = 42),
          'symbols: AValue = 42 (%d)', [LValue]);
        Check(DoSymbolType(LSymbols, LTop, 'AValue', LType) and (LType.Tag = dttBase) and
          (LType.Length = 4) and (LType.BaseType = 6), 'symbols: AValue is a 4-byte int (tag %d, %d bytes, base %d)',
          [Ord(LType.Tag), LType.Length, LType.BaseType]);

        // Frame 1: locals read with frame 1's own unwound registers (R6)
        Check(LSymbols.FrameSymbols(LFrames[1], LCaller), 'symbols: frame 1''s scope (' + DoReports(LErrors) + ')');
        Check(DoSymbolValue(ATarget, LCaller, LFrames[1], 'LFrom', 0, 4, LValue) and (LValue = 42),
          'symbols: frame 1 LFrom = 42 (%d; %s)', [LValue, DoNamesText(LCaller)]);
        Check(DoSymbolValue(ATarget, LCaller, LFrames[1], 'LCppLocal', 0, 4, LValue) and (LValue = 21),
          'symbols: frame 1 verbatim C++ LCppLocal = 21 (%d)', [LValue]);

        // A record: layout and values
        Check(DoSymbolType(LSymbols, LCaller, 'LPair', LType) and (LType.Tag = dttUdt) and
          (LType.CppName = 'pcpp_m_dbg_syms::TPair') and (LType.Length = 24) and
          (DoFieldsText(LType) = 'A@0 B@8 C@16'), 'symbols: TPair layout (%s, %d bytes: %s)',
          [LType.CppName, LType.Length, DoFieldsText(LType)]);
        Check(DoSymbolValue(ATarget, LCaller, LFrames[1], 'LPair', 0, 4, LValue) and (LValue = 7) and
          DoSymbolValue(ATarget, LCaller, LFrames[1], 'LPair', 8, 8, LValue) and (LValue = 9) and
          DoSymbolValue(ATarget, LCaller, LFrames[1], 'LPair', 16, 1, LValue) and (LValue = 3),
          'symbols: LPair = 7 / 9 / 3');

        // A choice: enumerators with the given value, and the value held
        Check(DoSymbolType(LSymbols, LCaller, 'LCol', LType) and (LType.Tag = dttEnum) and
          (LType.CppName = 'pcpp_m_dbg_syms::TCol') and (LType.Length = 4) and
          (DoFieldsText(LType) = 'cRed=0 cGreen=5 cBlue=6'), 'symbols: TCol (%s, %d bytes: %s)',
          [LType.CppName, LType.Length, DoFieldsText(LType)]);
        Check(DoSymbolValue(ATarget, LCaller, LFrames[1], 'LCol', 0, 4, LValue) and (LValue = 6),
          'symbols: LCol = cBlue (6) (%d)', [LValue]);

        // An array: PaskalCPP's array is ::pcpp::Array (PLAN-RECORDS A8b), a
        // UDT whose one member is the C array: count, length, element type, a value
        Check(DoSymbolType(LSymbols, LCaller, 'LNums', LType) and (LType.Tag = dttUdt) and
          LType.CppName.Contains('pcpp::Array') and (LType.Length = 16) and (Length(LType.Fields) = 1) and
          (LType.Fields[0].Offset = 0), 'symbols: LNums is a 16-byte ::pcpp::Array (%s: %s)',
          [LType.CppName, DoFieldsText(LType)]);
        Check((Length(LType.Fields) = 1) and DoPlainType(LSymbols, LSymbol.ModuleBase, LType.Fields[0].TypeIndex,
          LBaseType) and (LBaseType.Tag = dttArray) and (LBaseType.Count = 4) and (LBaseType.Length = 16),
          'symbols: its member is a C array of 4 (tag %d, count %d, %d bytes)',
          [Ord(LBaseType.Tag), LBaseType.Count, LBaseType.Length]);
        Check(DoPlainType(LSymbols, LSymbol.ModuleBase, LBaseType.ElementType, LBaseType) and
          (LBaseType.Tag = dttBase) and (LBaseType.Length = 4), 'symbols: of a 4-byte base type (tag %d, %d bytes)',
          [Ord(LBaseType.Tag), LBaseType.Length]);
        Check(DoSymbolValue(ATarget, LCaller, LFrames[1], 'LNums', 8, 4, LValue) and (LValue = 11),
          'symbols: LNums[2] = 11 (%d)', [LValue]);

        // A string: libc++'s std::string as the PDB lays it out (e2 probe)
        Check(DoSymbolType(LSymbols, LCaller, 'LText', LType) and (LType.Tag = dttUdt) and
          LType.CppName.Contains('basic_string') and (LType.Length = 24),
          'symbols: LText is libc++''s 24-byte std::string (%s, %d bytes: %s)',
          [LType.CppName, LType.Length, DoFieldsText(LType)]);

        // An object with a parent: the parent part, then its own fields
        LHasBase := False;
        LBaseOffset := 0;
        Check(DoSymbolType(LSymbols, LCaller, 'LPoint', LType) and (LType.Tag = dttUdt) and
          (DoFieldsText(LType) = '^pcpp_m_dbg_syms::TBase@0 X@4 Y@8'), 'symbols: TPoint layout (%s: %s)',
          [LType.CppName, DoFieldsText(LType)]);
        for LField in LType.Fields do
          if LField.IsBase then
          begin
            LHasBase := DoPlainType(LSymbols, LSymbol.ModuleBase, LField.TypeIndex, LBaseType);
            LBaseOffset := LField.Offset;
          end;
        Check(LHasBase and DoFieldOffset(LBaseType, 'Z', LOffset) and
          DoSymbolValue(ATarget, LCaller, LFrames[1], 'LPoint', LBaseOffset + LOffset, 4, LValue) and
          (LValue = 8), 'symbols: LPoint.Z (the parent''s field) = 8 (%d)', [LValue]);
        Check(DoFieldOffset(LType, 'X', LOffset) and
          DoSymbolValue(ATarget, LCaller, LFrames[1], 'LPoint', LOffset, 4, LValue) and (LValue = 4),
          'symbols: LPoint.X = 4 (%d)', [LValue]);

        // A module var by its C++ name, at its absolute address
        Check(LSymbols.GlobalSymbol('pcpp_m_dbg_syms::GTotal', LSymbol) and (not LSymbol.IsRegRel) and
          LSymbol.ValueAddress(LFrames[0], LAddress) and DoReadInt(ATarget, LAddress, 4, LValue) and
          (LValue = 103), 'symbols: GTotal = 103 (%d)', [LValue]);
      end);

    Check(LHit and (DoCountStops(LRun, dsrBreakpoint) = 1), 'symbols: one hit on M_INNER_BODY (%d)',
      [DoCountStops(LRun, dsrBreakpoint)]);
    Check(LRun.Output.StartsWith('187'), 'symbols: the program ran as written (%s)', [DoShow(LRun.Output)]);
    Check(LRun.Exited and (LRun.ExitCode = 0), 'symbols: exits with 0 (%d)', [LRun.ExitCode]);
    Check(LErrors.Count() = 0, 'symbols: nothing reported (' + DoReports(LErrors) + ')');
  finally
    LSymbols.Free();
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestNoDebugInfo();
var
  LExe: string;
  LReason: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LSymbols: TPCDebugSymbols;
  LRun: TPCDebugRun;
  LRequired: Boolean;
  LPlain: Boolean;
  LCodes: string;
  LBuilt: string;
  LCopyDir: string;
begin
  // An image without its PDB has no line table: required, it is DB0006 (P5:
  // never a session that silently hits nothing); not required, it loads.
  // (e2 probe: zig writes a PDB with lines for release builds too, so the
  // case is an exe whose PDB is not beside it: a copy of the exe alone)
  Check(DoBuildFixture('syms', LBuilt, LReason), 'no_debug_info: dbg_syms builds (' + LReason + ')');
  if LBuilt = '' then
    Exit;
  LCopyDir := TPath.Combine(TPath.Combine(TPath.GetTempPath(), 'pcpp-dbg'), 'syms_nopdb');
  LExe := TPath.Combine(LCopyDir, TPath.GetFileName(LBuilt));
  LReason := '';
  try
    TDirectory.CreateDirectory(LCopyDir);
    TFile.Copy(LBuilt, LExe, True);
  except
    on E: Exception do
      LReason := E.Message;
  end;
  Check((LReason = '') and (not TFile.Exists(TPath.ChangeExtension(LExe, '.pdb'))),
    'no_debug_info: the exe copied alone (' + LReason + ')');
  if LReason <> '' then
    Exit;
  LRequired := True;
  LPlain := False;
  LCodes := '';
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LExe);
  LSymbols := TPCDebugSymbols.Create();
  try
    LSymbols.SetErrors(LErrors);
    Check(LTarget.Start(), 'no_debug_info: starts (' + DoReports(LErrors) + ')');
    LRun := DoSession(LTarget,
      function(const ATarget: TPCDebugTarget; const AEvent: TPCDebugEvent): TPCResumeKind
      begin
        Result := rkContinue;
        if (AEvent.Reason <> dsrEntry) or (not LSymbols.Open(ATarget.ProcessHandle())) then
          Exit;
        LRequired := LSymbols.AddModule(LExe, ATarget.ImageBase(), True);
        LCodes := DoCodes(LErrors);
        LPlain := LSymbols.AddModule(LExe, ATarget.ImageBase(), False);
      end);
    Check(not LRequired, 'no_debug_info: required line numbers refuse the release exe');
    Check(LCodes = PC_ERR_DBG_006, 'no_debug_info: DB0006 (' + LCodes + ')');
    Check(LPlain, 'no_debug_info: not required, the same image loads');
    Check(LRun.Exited and (LRun.ExitCode = 0), 'no_debug_info: exits with 0 (%d)', [LRun.ExitCode]);
  finally
    LSymbols.Free();
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestRuntimeVars();
var
  LExe: string;
  LReason: string;
  LSource: string;
  LCompiler: TPCCompiler;
  LErrors: TErrors;
  LRuntime: TPCDebugRuntime;
  LRun: TPCRuntimeRun;
  LEvent: TPCDebugEvent;
  LBodyLine: Integer;
  LCallLine: Integer;
  LEndLine: Integer;
  LOuterLine: Integer;
  LMainLine: Integer;
  LFirstId: Integer;
  LResults: TArray<TPCBreakpointResult>;
  LChanges: TArray<TPCBreakpointResult>;
  LStack: TArray<TPCDebugStackItem>;
  LValues: TArray<TPCDebugValue>;
  LValue: TPCDebugValue;
  LChildren: TArray<TPCDebugValue>;
  LBase: TArray<TPCDebugValue>;
  LOk: Boolean;
  LText: string;
begin
  // dbg_syms (gen_dbg.py) under the engine with its analysed tree: a
  // breakpoint set before launch is pending, then verified as the exe
  // loads; at M_INNER_BODY the stack in PaskalCPP names, both frames'
  // variables with PaskalCPP names and types, children, designators
  LRun := Default(TPCRuntimeRun);
  LCompiler := DoBuildProgram('syms', LExe, LReason);
  LErrors := TErrors.Create();
  LRuntime := DoNewRuntime(LErrors, LCompiler, LExe);
  try
    Check(LExe <> '', 'runtime_vars: dbg_syms builds (' + LReason + ')');
    if LExe = '' then
      Exit;
    LSource := DoFixturePath('syms');
    LBodyLine := DoMarkerLine('syms', 'M_INNER_BODY');
    LCallLine := DoMarkerLine('syms', 'M_CALL');
    LEndLine := DoMarkerLine('syms', 'M_INNER_END');
    // Past Outer's prologue (e5b), as in symbols
    LOuterLine := DoMarkerLine('syms', 'M_OUTER_FIRST');
    // the module body's println line (by marker, as every other line)
    LMainLine := DoMarkerLine('syms', 'M_MAIN');

    LResults := LRuntime.SetBreakpoints(LSource, [LBodyLine]);
    Check((Length(LResults) = 1) and (not LResults[0].Verified) and (LResults[0].MessageText = RSDbgBpPending),
      'runtime_vars: a breakpoint set before launch is pending');
    LFirstId := 0;
    if Length(LResults) = 1 then
      LFirstId := LResults[0].Id;
    Check(LRuntime.Launch(), 'runtime_vars: launches, held at entry (' + DoReports(LErrors) + ')');
    LChanges := LRuntime.TakeBreakpointChanges();
    Check((Length(LChanges) = 1) and LChanges[0].Verified and (LChanges[0].Id = LFirstId) and
      (LChanges[0].ActualLine = LBodyLine), 'runtime_vars: the pending one is verified as the exe loads, same id');

    // Re-set: the same file + line keeps its id; a line without code moves
    // forward (the next routine's header)
    LResults := LRuntime.SetBreakpoints(LSource, [LBodyLine, LEndLine]);
    LText := '';
    if Length(LResults) = 2 then
      LText := IntToStr(LResults[1].ActualLine);
    Check((Length(LResults) = 2) and LResults[0].Verified and (LResults[0].Id = LFirstId) and
      LResults[1].Verified and (LResults[1].ActualLine = LOuterLine),
      'runtime_vars: a re-set keeps the id, a line without code moves forward (%s, want %d)', [LText, LOuterLine]);
    LRuntime.SetBreakpoints(LSource, [LBodyLine]);

    Check(LRuntime.ConfigurationDone(), 'runtime_vars: runs on from the entry stop');
    Check(DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrBreakpoint),
      'runtime_vars: stops at the breakpoint');
    LStack := LRuntime.StackTrace(LRuntime.StoppedThread());
    Check((Length(LStack) >= 3) and (LStack[0].RoutineName = 'Inner') and (LStack[0].Line = LBodyLine) and
      LStack[0].IsPcpp and (LStack[1].RoutineName = 'Outer') and (LStack[1].Line = LCallLine) and
      (LStack[2].RoutineName = 'dbg_syms') and (LStack[2].Line = LMainLine) and
      (DoStackText(LStack) = Format('Inner:%d Outer:%d dbg_syms:%d', [LBodyLine, LCallLine, LMainLine])),
      'runtime_vars: the stack in PaskalCPP names, no trailer glue (%s)', [DoStackText(LStack)]);
    if Length(LStack) < 3 then
      Exit;
    Check(DoScopesText(LRuntime.Scopes(LStack[0].FrameId)) = 'params locals globals',
      'runtime_vars: a routine frame has params, locals, globals (%s)', [DoScopesText(LRuntime.Scopes(LStack[0].FrameId))]);
    // The module body: no params; Locals only because verbatim C++ declares
    // LBodyCpp there
    Check(DoScopesText(LRuntime.Scopes(LStack[2].FrameId)) = 'locals globals',
      'runtime_vars: the module body has locals (verbatim C++) and globals, no params (%s)',
      [DoScopesText(LRuntime.Scopes(LStack[2].FrameId))]);
    LValues := LRuntime.Variables(LStack[2].FrameId, dskLocals);
    Check(DoFindValue(LValues, 'LBodyCpp', LValue) and (LValue.ValueText = '5'),
      'runtime_vars: the module body''s verbatim C++ local, raw (%s)', [DoValuesText(LValues)]);

    LValues := LRuntime.Variables(LStack[0].FrameId, dskParams);
    Check(DoFindValue(LValues, 'AValue', LValue) and (LValue.TypeText = 'int32') and (LValue.ValueText = '42'),
      'runtime_vars: Inner''s param AValue: int32 = 42 (%s)', [DoValuesText(LValues)]);
    LValues := LRuntime.Variables(LStack[0].FrameId, dskLocals);
    Check(DoTextOf(LValues, 'LTwice') = '0', 'runtime_vars: Inner''s local LTwice = 0 (%s)', [DoValuesText(LValues)]);
    LValues := LRuntime.Variables(LStack[0].FrameId, dskGlobals);
    Check(DoTextOf(LValues, 'GTotal') = '103', 'runtime_vars: the global GTotal = 103 (%s)', [DoValuesText(LValues)]);

    // Frame 1 (Outer at M_CALL), read with its own registers
    LValues := LRuntime.Variables(LStack[1].FrameId, dskLocals);
    Check((DoTextOf(LValues, 'LFrom') = '42') and (DoTextOf(LValues, 'LPair') = '{A: 7, B: 9, C: 3}') and
      (DoTextOf(LValues, 'LCol') = 'cBlue') and (DoTextOf(LValues, 'LNums') = '[0, 0, 11, 0]') and
      (DoTextOf(LValues, 'LText') = '"hello"') and (DoTextOf(LValues, 'LPoint') = '{TBase: {...}, X: 4, Y: 0}'),
      'runtime_vars: Outer''s locals by their PaskalCPP types (%s)', [DoValuesText(LValues)]);
    Check(DoFindValue(LValues, 'LPair', LValue) and (LValue.TypeText = 'TPair') and
      DoFindValue(LValues, 'LText', LValue) and (LValue.TypeText = 'string'),
      'runtime_vars: types are PaskalCPP spellings (%s)', [DoValuesText(LValues)]);
    Check(DoFindValue(LValues, 'LCppLocal', LValue) and (LValue.ValueText = '21') and (LValue.TypeText <> ''),
      'runtime_vars: a verbatim C++ local is listed raw (%s)', [DoValuesText(LValues)]);

    // Children: an object's parent part first, then its own fields
    LChildren := nil;
    LBase := nil;
    if DoFindValue(LValues, 'LPoint', LValue) and (LValue.ChildrenRef > 0) then
      LChildren := LRuntime.Children(LValue.ChildrenRef);
    Check((Length(LChildren) = 3) and (LChildren[0].DisplayName = 'TBase') and (LChildren[1].DisplayName = 'X') and
      (LChildren[2].DisplayName = 'Y'), 'runtime_vars: LPoint''s children TBase, X, Y (%s)', [DoValuesText(LChildren)]);
    if (Length(LChildren) = 3) and (LChildren[0].ChildrenRef > 0) then
      LBase := LRuntime.Children(LChildren[0].ChildrenRef);
    Check(DoTextOf(LBase, 'Z') = '8', 'runtime_vars: the parent part holds Z = 8 (%s)', [DoValuesText(LBase)]);

    // PLAN-RECORDS A6 (M10): a record extension's parent part is its
    // pcpp_parent member, shown first as the object's base class is
    LChildren := nil;
    LBase := nil;
    if DoFindValue(LValues, 'LRExt', LValue) and (LValue.ChildrenRef > 0) then
      LChildren := LRuntime.Children(LValue.ChildrenRef);
    Check((Length(LChildren) = 2) and (LChildren[0].DisplayName = 'TRBase') and (LChildren[1].DisplayName = 'V') and
      (LChildren[1].ValueText = '6'), 'runtime_vars: LRExt''s children TRBase, V = 6 (%s)', [DoValuesText(LChildren)]);
    if (Length(LChildren) = 2) and (LChildren[0].ChildrenRef > 0) then
      LBase := LRuntime.Children(LChildren[0].ChildrenRef);
    Check(DoTextOf(LBase, 'W') = '3', 'runtime_vars: the record''s parent part holds W = 3 (%s)',
      [DoValuesText(LBase)]);
    Check((DoEvalText(LRuntime, LStack[1].FrameId, 'LRExt.W', LOk) = '3') and LOk,
      'runtime_vars: evaluate LRExt.W (inherited through the parent member)');

    // Designators in frame 1
    Check((DoEvalText(LRuntime, LStack[1].FrameId, 'LPair.B', LOk) = '9') and LOk,
      'runtime_vars: evaluate LPair.B');
    Check((DoEvalText(LRuntime, LStack[1].FrameId, 'LNums[2]', LOk) = '11') and LOk,
      'runtime_vars: evaluate LNums[2] (the array''s own index)');
    Check((DoEvalText(LRuntime, LStack[1].FrameId, 'LPoint.Z', LOk) = '8') and LOk,
      'runtime_vars: evaluate LPoint.Z (inherited)');
    LText := DoEvalText(LRuntime, LStack[1].FrameId, 'LNums[4]', LOk);
    Check((not LOk) and (LText = Format(RSDbgEvalBadIndex, ['LNums', 4])),
      'runtime_vars: LNums[4] is out of its bounds (%s)', [LText]);
    LText := DoEvalText(LRuntime, LStack[1].FrameId, 'LPair.B + 1', LOk);
    Check((not LOk) and (LText = Format(RSDbgEvalUnsupported, ['LPair.B + 1'])),
      'runtime_vars: an expression is not a designator (%s)', [LText]);
    LText := DoEvalText(LRuntime, LStack[0].FrameId, 'LPair', LOk);
    Check((not LOk) and (LText = Format(RSDbgEvalUnknownName, ['LPair'])),
      'runtime_vars: a name of another frame is unknown here (%s)', [LText]);

    LRuntime.SetBreakpoints(LSource, []);
    Check(LRuntime.ContinueExecution(), 'runtime_vars: continues');
    DoFinish(LRuntime, LRun);
    // A debug build's runtime prints its heap report after the program's own text
    Check(LRun.Exited and (LRun.ExitCode = 0) and LRun.Output.StartsWith('187' + PC_TEST_DBG_EOL),
      'runtime_vars: runs to its end (exit %d, output %s)', [LRun.ExitCode, DoShow(LRun.Output)]);
    Check(not LErrors.HasErrors(), 'runtime_vars: nothing reported (' + DoReports(LErrors) + ')');
  finally
    LRuntime.Free();
    LErrors.Free();
    LCompiler.Free();
  end;
end;

procedure TPCDebugTests.DoTestRuntimeOwners();
var
  LExe: string;
  LReason: string;
  LSource: string;
  LCompiler: TPCCompiler;
  LErrors: TErrors;
  LRuntime: TPCDebugRuntime;
  LRun: TPCRuntimeRun;
  LEvent: TPCDebugEvent;
  LStack: TArray<TPCDebugStackItem>;
  LValues: TArray<TPCDebugValue>;
  LValue: TPCDebugValue;
  LChildren: TArray<TPCDebugValue>;
  LObject: TArray<TPCDebugValue>;
  LBase: TArray<TPCDebugValue>;
  LOk: Boolean;
  LText: string;
begin
  // PLAN-OBJECT O14, dbg_owners (gen_dbg.py): stopped in Show, the module's
  // own / ref / weak globals read as PaskalCPP values through the runtime's
  // owners as the PDB lays them out: the object as the ^ child (parent part
  // first), nil, a weak whose object is gone expired; GO.X / GR.X evaluate
  // through the owner (Q2), a weak's member does not (SM0360)
  LRun := Default(TPCRuntimeRun);
  LCompiler := DoBuildProgram('owners', LExe, LReason);
  LErrors := TErrors.Create();
  LRuntime := DoNewRuntime(LErrors, LCompiler, LExe);
  try
    Check(LExe <> '', 'runtime_owners: dbg_owners builds (' + LReason + ')');
    if LExe = '' then
      Exit;
    LSource := DoFixturePath('owners');
    LRuntime.SetBreakpoints(LSource, [DoMarkerLine('owners', 'M_SHOW')]);
    Check(LRuntime.Launch(), 'runtime_owners: launches (' + DoReports(LErrors) + ')');
    Check(LRuntime.ConfigurationDone(), 'runtime_owners: runs on from the entry stop');
    Check(DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrBreakpoint),
      'runtime_owners: stops in Show');
    LStack := LRuntime.StackTrace(LRuntime.StoppedThread());
    if Length(LStack) < 1 then
    begin
      Check(False, 'runtime_owners: a stack');
      Exit;
    end;
    LValues := LRuntime.Variables(LStack[0].FrameId, dskGlobals);

    // own: its object is the ^ child; the object shows its parent part, then X
    Check(DoFindValue(LValues, 'GO', LValue) and (LValue.TypeText = 'own TObj') and
      LValue.ValueText.StartsWith('$') and (LValue.ChildrenRef > 0),
      'runtime_owners: GO is an own TObj with its object as a child (%s)', [DoValuesText(LValues)]);
    LChildren := nil;
    LObject := nil;
    LBase := nil;
    if DoFindValue(LValues, 'GO', LValue) and (LValue.ChildrenRef > 0) then
      LChildren := LRuntime.Children(LValue.ChildrenRef);
    Check((Length(LChildren) = 1) and (LChildren[0].DisplayName = '^') and (LChildren[0].TypeText = 'TObj'),
      'runtime_owners: GO''s one child is ^: TObj (%s)', [DoValuesText(LChildren)]);
    if (Length(LChildren) = 1) and (LChildren[0].ChildrenRef > 0) then
      LObject := LRuntime.Children(LChildren[0].ChildrenRef);
    Check((Length(LObject) = 2) and (LObject[0].DisplayName = 'TBase') and (DoTextOf(LObject, 'X') = '4'),
      'runtime_owners: GO^ holds TBase, X = 4 (%s)', [DoValuesText(LObject)]);
    if (Length(LObject) = 2) and (LObject[0].ChildrenRef > 0) then
      LBase := LRuntime.Children(LObject[0].ChildrenRef);
    Check(DoTextOf(LBase, 'Z') = '8', 'runtime_owners: GO^''s parent part holds Z = 8 (%s)', [DoValuesText(LBase)]);

    // ref and a live weak: the same object (one owner holds it)
    Check(DoFindValue(LValues, 'GR', LValue) and (LValue.TypeText = 'ref TObj') and
      LValue.ValueText.StartsWith('$') and (LValue.ChildrenRef > 0),
      'runtime_owners: GR is a ref TObj with its object as a child (%s)', [DoValuesText(LValues)]);
    LText := LValue.ValueText;
    Check(DoFindValue(LValues, 'GLive', LValue) and (LValue.TypeText = 'weak TObj') and
      (LValue.ValueText = LText) and (LValue.ChildrenRef > 0),
      'runtime_owners: GLive watches GR''s object (%s)', [DoValuesText(LValues)]);

    // A weak whose object is gone, an own never set, a ref set to nil
    Check(DoFindValue(LValues, 'GGone', LValue) and (LValue.ValueText = RSDbgWeakExpired) and
      (LValue.ChildrenRef = 0), 'runtime_owners: GGone is expired, no child (%s)', [DoValuesText(LValues)]);
    Check((DoTextOf(LValues, 'GNil') = 'nil') and (DoTextOf(LValues, 'GTmp') = 'nil'),
      'runtime_owners: GNil and GTmp are nil (%s)', [DoValuesText(LValues)]);

    // Designators as PaskalCPP writes them
    Check((DoEvalText(LRuntime, LStack[0].FrameId, 'GO.X', LOk) = '4') and LOk,
      'runtime_owners: evaluate GO.X (an own used as its object)');
    Check((DoEvalText(LRuntime, LStack[0].FrameId, 'GO.Z', LOk) = '8') and LOk,
      'runtime_owners: evaluate GO.Z (inherited, through the owner)');
    Check((DoEvalText(LRuntime, LStack[0].FrameId, 'GR.X', LOk) = '7') and LOk,
      'runtime_owners: evaluate GR.X');
    Check((DoEvalText(LRuntime, LStack[0].FrameId, 'GO^.X', LOk) = '4') and LOk,
      'runtime_owners: evaluate GO^.X');
    LText := DoEvalText(LRuntime, LStack[0].FrameId, 'GLive.X', LOk);
    Check((not LOk) and (LText = Format(RSDbgEvalNoMember, ['GLive', 'X'])),
      'runtime_owners: a weak has no member X (SM0360) (%s)', [LText]);

    LRuntime.SetBreakpoints(LSource, []);
    Check(LRuntime.ContinueExecution(), 'runtime_owners: continues');
    DoFinish(LRuntime, LRun);
    Check(LRun.Exited and (LRun.ExitCode = 0) and LRun.Output.StartsWith('11' + PC_TEST_DBG_EOL),
      'runtime_owners: runs to its end (exit %d, output %s)', [LRun.ExitCode, DoShow(LRun.Output)]);
    Check(not LErrors.HasErrors(), 'runtime_owners: nothing reported (' + DoReports(LErrors) + ')');
  finally
    LRuntime.Free();
    LErrors.Free();
    LCompiler.Free();
  end;
end;

procedure TPCDebugTests.DoTestRuntimeRaw();
var
  LExe: string;
  LReason: string;
  LCompiler: TPCCompiler;
  LErrors: TErrors;
  LRuntime: TPCDebugRuntime;
  LRun: TPCRuntimeRun;
  LEvent: TPCDebugEvent;
  LStack: TArray<TPCDebugStackItem>;
  LValues: TArray<TPCDebugValue>;
  LValue: TPCDebugValue;
begin
  // The same program with no sources (a prebuilt exe): said once (DB0015),
  // then the PDB's names and types
  LRun := Default(TPCRuntimeRun);
  LCompiler := DoBuildProgram('syms', LExe, LReason);
  LErrors := TErrors.Create();
  LRuntime := DoNewRuntime(LErrors, nil, LExe);
  try
    Check(LExe <> '', 'runtime_raw: dbg_syms builds (' + LReason + ')');
    if LExe = '' then
      Exit;
    Check(LRuntime.Launch(), 'runtime_raw: launches (' + DoReports(LErrors) + ')');
    Check(DoCodes(LErrors) = PC_ERR_DBG_015, 'runtime_raw: no sources is said once (' + DoCodes(LErrors) + ')');
    LRuntime.SetBreakpoints(DoFixturePath('syms'), [DoMarkerLine('syms', 'M_INNER_BODY')]);
    LRuntime.ConfigurationDone();
    Check(DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrBreakpoint), 'runtime_raw: stops');
    LStack := LRuntime.StackTrace(LRuntime.StoppedThread());
    Check((Length(LStack) > 0) and (LStack[0].RoutineName = 'pcpp_m_dbg_syms::Inner'),
      'runtime_raw: frame 0 has the C++ name (%s)', [DoStackText(LStack)]);
    if Length(LStack) = 0 then
      Exit;
    Check(Length(LRuntime.Scopes(LStack[0].FrameId)) = 1, 'runtime_raw: only the C++ locals scope');
    LValues := LRuntime.Variables(LStack[0].FrameId, dskLocals);
    Check(DoFindValue(LValues, 'LTwice', LValue) and (LValue.TypeText = 'int') and (LValue.ValueText = '0'),
      'runtime_raw: LTwice: int = 0 (%s)', [DoValuesText(LValues)]);
    LValues := LRuntime.Variables(LStack[0].FrameId, dskParams);
    Check(DoTextOf(LValues, 'AValue') = '42', 'runtime_raw: AValue = 42 (%s)', [DoValuesText(LValues)]);
    LRuntime.SetBreakpoints(DoFixturePath('syms'), []);
    LRuntime.ContinueExecution();
    DoFinish(LRuntime, LRun);
    Check(LRun.Exited and (LRun.ExitCode = 0), 'runtime_raw: exits with 0 (%d)', [LRun.ExitCode]);
  finally
    LRuntime.Free();
    LErrors.Free();
    LCompiler.Free();
  end;
end;

type
  { TPCStepRow }
  // One step of runtime_steps' Deep walk (e7 G1-G3) and where it must stop
  TPCStepRow = record
    Kind: TPCDebugStepKind;
    Marker: string;           // the stop's line (gen_dbg.py steps marker)
    Routine: string;
    AN: string;               // Deep's AN at the stop ('' = not Deep)
    Why: string;
  end;

const
  { PC_TEST_DEEP_STEPS }
  // From M_DEEP_CALL in Run: into Deep(2), through its guard (except +
  // finally: both parts run in lambdas the runtime calls), into Deep(1),
  // over Deep(0) (its guard parts run in a deeper frame: they pass), out of
  // a finally part (out of the routine), past the guards' glue lines
  PC_TEST_DEEP_STEPS: array[0..13] of TPCStepRow = (
    (Kind: dstIn;   Marker: 'M_DEEP_VAR';     Routine: 'Deep'; AN: '2'; Why: 'step in enters Deep(2) past its prologue'),
    (Kind: dstOver; Marker: 'M_DEEP_FIRST';   Routine: 'Deep'; AN: '2'; Why: 'the body''s first line'),
    (Kind: dstOver; Marker: 'M_DEEP_KW';      Routine: 'Deep'; AN: '2'; Why: 'the guard''s line'),
    (Kind: dstOver; Marker: 'M_DEEP_BODY';    Routine: 'Deep'; AN: '2'; Why: 'over a guard line (with finally): its body'),
    (Kind: dstOver; Marker: 'M_DEEP_REC';     Routine: 'Deep'; AN: '2'; Why: 'the body''s next line'),
    (Kind: dstIn;   Marker: 'M_DEEP_VAR';     Routine: 'Deep'; AN: '1'; Why: 'step in from a guard body: Deep(1)'),
    (Kind: dstOver; Marker: 'M_DEEP_FIRST';   Routine: 'Deep'; AN: '1'; Why: 'Deep(1)''s first line'),
    (Kind: dstOver; Marker: 'M_DEEP_KW';      Routine: 'Deep'; AN: '1'; Why: 'Deep(1)''s guard line'),
    (Kind: dstOver; Marker: 'M_DEEP_BODY';    Routine: 'Deep'; AN: '1'; Why: 'Deep(1)''s guard body'),
    (Kind: dstOver; Marker: 'M_DEEP_REC';     Routine: 'Deep'; AN: '1'; Why: 'Deep(1)''s recursive call'),
    (Kind: dstOver; Marker: 'M_DEEP_FINALLY'; Routine: 'Deep'; AN: '1';
      Why: 'over Deep(0) (its parts pass): this frame''s finally, not the except line'),
    (Kind: dstOut;  Marker: 'M_DEEP_FINALLY'; Routine: 'Deep'; AN: '2';
      Why: 'finish from a finally part leaves Deep(1): Deep(2)''s body ends, its finally'),
    (Kind: dstOver; Marker: 'M_DEEP_RET';     Routine: 'Deep'; AN: '2'; Why: 'past the guard''s end line'),
    (Kind: dstOut;  Marker: 'M_RUN_RET';      Routine: 'Run';  AN: '';  Why: 'finish from Deep: Run''s next line')
  );

function DoStepStop(const ARuntime: TPCDebugRuntime; var ARun: TPCRuntimeRun; const AKind: TPCDebugStepKind;
  out ATop: TPCDebugStackItem): Boolean;
var
  LEvent: TPCDebugEvent;
  LStarted: Boolean;
begin
  // One step of AKind: True = it ended as a step's stop; ATop = the top frame
  ATop := Default(TPCDebugStackItem);
  if AKind = dstIn then
    LStarted := ARuntime.StepIn()
  else if AKind = dstOut then
    LStarted := ARuntime.StepOut()
  else
    LStarted := ARuntime.StepOver();
  Result := LStarted and DoNextStop(ARuntime, ARun, LEvent) and (LEvent.Reason = dsrStep);
  if Result then
    ATop := DoTop(ARuntime);
end;

procedure TPCDebugTests.DoTestRuntimeDll();
var
  LLib: string;
  LHost: string;
  LReason: string;
  LCopy: string;
  LCompiler: TPCCompiler;
  LErrors: TErrors;
  LRuntime: TPCDebugRuntime;
  LRun: TPCRuntimeRun;
  LEvent: TPCDebugEvent;
  LTop: TPCDebugStackItem;
  LStack: TArray<TPCDebugStackItem>;
  LValues: TArray<TPCDebugValue>;
  LValue: TPCDebugValue;
  LIndex: Integer;
  LHostLines: Integer;
  LBelowPcpp: Boolean;
begin
  // e7 D1 D2: a dll's exported clink routine (its symbol is the bare C
  // name, outside the module's namespace) is the program's code: PaskalCPP
  // names and types, a step stays in it; a private clink routine (static:
  // namespaced) likewise. The host loads its own copy of the dll
  LRun := Default(TPCRuntimeRun);
  LCompiler := DoBuildProgram('lib', LLib, LReason);
  LErrors := TErrors.Create();
  LRuntime := TPCDebugRuntime.Create();
  try
    Check(LLib <> '', 'runtime_dll: dbg_lib builds (' + LReason + ')');
    Check(DoBuildFixture('host', LHost, LReason), 'runtime_dll: dbg_host builds (' + LReason + ')');
    if (LLib = '') or (LHost = '') then
      Exit;
    // The dll and its .pdb (the line table: DB0006 without it)
    LCopy := TPath.Combine(TPath.GetDirectoryName(LHost), TPath.GetFileName(LLib));
    LReason := '';
    try
      TFile.Copy(LLib, LCopy, True);
      TFile.Copy(TPath.ChangeExtension(LLib, '.pdb'), TPath.ChangeExtension(LCopy, '.pdb'), True);
    except
      on E: Exception do
        LReason := E.Message;
    end;
    Check(LReason = '', 'runtime_dll: copied beside the host with its pdb (' + LReason + ')');
    if LReason <> '' then
      Exit;

    LRuntime.SetErrors(LErrors);
    LRuntime.SetProgram(LCompiler.GetMainModule());
    LRuntime.SetHostTarget(LCopy, LHost, '');
    LRuntime.SetOutputMode(domPipes);
    Check(LRuntime.Launch(), 'runtime_dll: launches (' + DoReports(LErrors) + ')');
    LRuntime.SetBreakpoints(DoFixturePath('lib'), [DoMarkerLine('lib', 'M_LIB_SUM')]);
    LRuntime.ConfigurationDone();

    // The breakpoint in the exported clink routine: PaskalCPP names and types
    Check(DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrBreakpoint), 'runtime_dll: stops');
    LTop := DoTop(LRuntime);
    Check(LTop.IsPcpp and (LTop.RoutineName = 'LibAdd'), 'runtime_dll: LibAdd is program code (%s)',
      [LTop.RoutineName]);
    Check(LTop.Line = DoMarkerLine('lib', 'M_LIB_SUM'), 'runtime_dll: at M_LIB_SUM (%d)', [LTop.Line]);
    LValues := LRuntime.Variables(LTop.FrameId, dskParams);
    Check(DoTextOf(LValues, 'AA') = '2', 'runtime_dll: param AA = 2 (%s)', [DoValuesText(LValues)]);
    Check(DoTextOf(LValues, 'AB') = '3', 'runtime_dll: param AB = 3 (%s)', [DoValuesText(LValues)]);
    Check(DoFindValue(LValues, 'AA', LValue) and (LValue.TypeText = 'int32'),
      'runtime_dll: AA has its PaskalCPP type (%s)', [DoValuesText(LValues)]);
    LValues := LRuntime.Variables(LTop.FrameId, dskLocals);
    Check(DoFindValue(LValues, 'LSum', LValue) and (LValue.TypeText = 'int32') and (LValue.ValueText = '0'),
      'runtime_dll: LSum: int32 = 0 (%s)', [DoValuesText(LValues)]);

    // A step over stays in the routine (it never leaves into the host)
    Check(DoStepStop(LRuntime, LRun, dstOver, LTop) and (LTop.RoutineName = 'LibAdd') and
      (LTop.Line = DoMarkerLine('lib', 'M_LIB_HALF_CALL')),
      'runtime_dll: over -> LibAdd at M_LIB_HALF_CALL (%s:%d)', [LTop.RoutineName, LTop.Line]);
    LValues := LRuntime.Variables(LTop.FrameId, dskLocals);
    Check(DoTextOf(LValues, 'LSum') = '5', 'runtime_dll: LSum = 5 there (%s)', [DoValuesText(LValues)]);

    // Into the private clink routine (namespaced), its param named
    Check(DoStepStop(LRuntime, LRun, dstIn, LTop) and (LTop.RoutineName = 'LibHalf') and
      (LTop.Line = DoMarkerLine('lib', 'M_LIB_HALF')),
      'runtime_dll: in -> LibHalf at M_LIB_HALF (%s:%d)', [LTop.RoutineName, LTop.Line]);
    LValues := LRuntime.Variables(LTop.FrameId, dskParams);
    Check(DoFindValue(LValues, 'AN', LValue) and (LValue.TypeText = 'int32') and (LValue.ValueText = '5'),
      'runtime_dll: LibHalf''s AN: int32 = 5 (%s)', [DoValuesText(LValues)]);
    LStack := LRuntime.StackTrace(LRuntime.StoppedThread());
    Check((Length(LStack) > 1) and LStack[1].IsPcpp and (LStack[1].RoutineName = 'LibAdd') and
      (LStack[1].Line = DoMarkerLine('lib', 'M_LIB_HALF_CALL')),
      'runtime_dll: frame 1 is LibAdd at its call (%s)', [DoStackText(LStack)]);

    // Out: back in LibAdd, at the next line's start
    Check(DoStepStop(LRuntime, LRun, dstOut, LTop) and (LTop.RoutineName = 'LibAdd') and
      (LTop.Line = DoMarkerLine('lib', 'M_LIB_RET')),
      'runtime_dll: out -> LibAdd at M_LIB_RET (%s:%d)', [LTop.RoutineName, LTop.Line]);
    LValues := LRuntime.Variables(LTop.FrameId, dskLocals);
    Check(DoTextOf(LValues, 'LSum') = '7', 'runtime_dll: LSum = 7 there (%s)', [DoValuesText(LValues)]);

    // e7 H1: in DLL mode only the dll is the program. The host's frames
    // carry its own .pcpp lines, yet none of them is program code
    LStack := LRuntime.StackTrace(LRuntime.StoppedThread());
    LHostLines := 0;
    LBelowPcpp := False;
    for LIndex := 1 to High(LStack) do
    begin
      if TUtils.SamePath(LStack[LIndex].FileName, DoFixturePath('host')) then
        Inc(LHostLines);
      if LStack[LIndex].IsPcpp then
        LBelowPcpp := True;
    end;
    Check(LHostLines > 0, 'runtime_dll: the host frames carry dbg_host lines (%d frames)', [Length(LStack)]);
    Check(not LBelowPcpp, 'runtime_dll: no frame below LibAdd is program code (%s)', [DoStackText(LStack)]);

    // A step over off the dll's last line runs through the host to the exit
    LRuntime.SetBreakpoints(DoFixturePath('lib'), []);
    Check(not DoStepStop(LRuntime, LRun, dstOver, LTop),
      'runtime_dll: over off M_LIB_RET stops nowhere (%s:%d)', [LTop.RoutineName, LTop.Line]);
    // A wrong stop is resumed, so the rows below still judge the run
    if not LRun.Exited then
    begin
      LRuntime.ContinueExecution();
      DoFinish(LRuntime, LRun);
    end;
    Check(LRun.Output.Contains('sum 7'), 'runtime_dll: the host got 7 (%s)', [DoShow(LRun.Output)]);
    Check(LRun.Exited and (LRun.ExitCode = 0), 'runtime_dll: exits with 0 (%d)', [LRun.ExitCode]);
    Check(LErrors.Count() = 0, 'runtime_dll: nothing reported (' + DoReports(LErrors) + ')');
  finally
    LRuntime.Free();
    LErrors.Free();
    LCompiler.Free();
  end;
end;

procedure TPCDebugTests.DoTestRuntimeSteps();
var
  LExe: string;
  LReason: string;
  LSource: string;
  LCompiler: TPCCompiler;
  LErrors: TErrors;
  LRuntime: TPCDebugRuntime;
  LRun: TPCRuntimeRun;
  LEvent: TPCDebugEvent;
  LTop: TPCDebugStackItem;
  LValues: TArray<TPCDebugValue>;
  LValue: TPCDebugValue;
  LOk: Boolean;
  LRow: TPCStepRow;
  LAN: string;
begin
  // dbg_steps (gen_dbg.py): step over, step in, step out ending on the next
  // line start, a recursive step over, values (strings short / long / wide,
  // a dynamic array, a set, a var param) and guard bodies (a lambda's
  // closure holds the routine's names); steps into, through and out of
  // guard parts (e7 G1-G3)
  LRun := Default(TPCRuntimeRun);
  LCompiler := DoBuildProgram('steps', LExe, LReason);
  LErrors := TErrors.Create();
  LRuntime := DoNewRuntime(LErrors, LCompiler, LExe);
  try
    Check(LExe <> '', 'runtime_steps: dbg_steps builds (' + LReason + ')');
    if LExe = '' then
      Exit;
    LSource := DoFixturePath('steps');
    Check(LRuntime.Launch(), 'runtime_steps: launches (' + DoReports(LErrors) + ')');

    LRuntime.SetBreakpoints(LSource, [DoMarkerLine('steps', 'M_RUN_FIRST')]);
    LRuntime.ConfigurationDone();
    Check(DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrBreakpoint) and
      (DoTop(LRuntime).Line = DoMarkerLine('steps', 'M_RUN_FIRST')), 'runtime_steps: stops at M_RUN_FIRST');

    // Step over: the next line
    Check(LRuntime.StepOver() and DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrStep),
      'runtime_steps: step over stops');
    LTop := DoTop(LRuntime);
    Check((LTop.RoutineName = 'Run') and (LTop.Line = DoMarkerLine('steps', 'M_RUN_SECOND')),
      'runtime_steps: step over lands on the next line (%s:%d)', [LTop.RoutineName, LTop.Line]);

    // Values at M_MIDLINE
    LRuntime.SetBreakpoints(LSource, [DoMarkerLine('steps', 'M_MIDLINE')]);
    LRuntime.ContinueExecution();
    Check(DoNextStop(LRuntime, LRun, LEvent) and (DoTop(LRuntime).Line = DoMarkerLine('steps', 'M_MIDLINE')),
      'runtime_steps: stops at M_MIDLINE');
    LTop := DoTop(LRuntime);
    LValues := LRuntime.Variables(LTop.FrameId, dskLocals);
    Check(DoTextOf(LValues, 'LShort') = '"hi"', 'runtime_steps: a short string (%s)', [DoValuesText(LValues)]);
    Check(DoTextOf(LValues, 'LLong') = '"a string longer than twenty-two chars"',
      'runtime_steps: a long string (%s)', [DoValuesText(LValues)]);
    // Character values spelled as their C++ literals (literals follow C++)
    Check(DoTextOf(LValues, 'LWide') = 'L"wi\"de"', 'runtime_steps: a wstring, L and its quote escaped (%s)',
      [DoValuesText(LValues)]);
    Check(DoTextOf(LValues, 'LCh') = '''q''', 'runtime_steps: a char (%s)', [DoValuesText(LValues)]);
    Check(DoTextOf(LValues, 'LCtl') = '''\n''', 'runtime_steps: a control char by name (%s)', [DoValuesText(LValues)]);
    Check(DoTextOf(LValues, 'LQuote') = '''\''''', 'runtime_steps: the quote char escaped (%s)', [DoValuesText(LValues)]);
    Check(DoTextOf(LValues, 'LHigh') = '''\x{E9}''', 'runtime_steps: a char past ASCII is a byte (%s)',
      [DoValuesText(LValues)]);
    Check(DoTextOf(LValues, 'LWch') = 'L''w''', 'runtime_steps: a wchar (%s)', [DoValuesText(LValues)]);
    Check(DoTextOf(LValues, 'LDyn') = '[0, 5, 0]', 'runtime_steps: a dynamic array (%s)', [DoValuesText(LValues)]);
    Check(DoTextOf(LValues, 'LSet') = '[cRed, cBlue]', 'runtime_steps: a set (%s)', [DoValuesText(LValues)]);
    Check(DoTextOf(LValues, 'LFlags') = '{A: 5, B: -3, C: true, D: cBlue}',
      'runtime_steps: bitfields: unsigned, signed (extended), bool, choices (%s)', [DoValuesText(LValues)]);
    Check((DoEvalText(LRuntime, LTop.FrameId, 'LFlags.B', LOk) = '-3') and LOk,
      'runtime_steps: evaluate a signed bitfield');
    Check((DoEvalText(LRuntime, LTop.FrameId, 'LDyn[1]', LOk) = '5') and LOk,
      'runtime_steps: evaluate LDyn[1]');
    LValues := LRuntime.Variables(LTop.FrameId, dskParams);
    Check(DoTextOf(LValues, 'ATotal') = '0', 'runtime_steps: a var param through its reference (%s)',
      [DoValuesText(LValues)]);
    LRuntime.SetBreakpoints(LSource, []);

    // Step in: the first call's routine, past its prologue (e5b): its body
    // line, where its param is readable
    Check(LRuntime.StepIn() and DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrStep),
      'runtime_steps: step in stops');
    LTop := DoTop(LRuntime);
    Check((LTop.RoutineName = 'Twice') and (LTop.Line = DoMarkerLine('steps', 'M_TWICE_BODY')),
      'runtime_steps: step in enters Twice past its prologue (%s:%d)', [LTop.RoutineName, LTop.Line]);
    LValues := LRuntime.Variables(LTop.FrameId, dskParams);
    // M_MIDLINE calls Twice(3) first
    Check(DoTextOf(LValues, 'AV') = '3', 'runtime_steps: Twice''s param is readable at the step-in stop (%s)',
      [DoValuesText(LValues)]);

    // Step out: back in Run, past the line's second call, on the next line
    Check(LRuntime.StepOut() and DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrStep),
      'runtime_steps: step out stops');
    LTop := DoTop(LRuntime);
    Check((LTop.RoutineName = 'Run') and (LTop.Line = DoMarkerLine('steps', 'M_RECCALL')),
      'runtime_steps: step out ends on the next line start (%s:%d)', [LTop.RoutineName, LTop.Line]);

    // A recursive step over: Fact(2) and deeper return to the same address in
    // deeper frames; the step comes back in Run
    LRuntime.SetBreakpoints(LSource, [DoMarkerLine('steps', 'M_FACT_REC')]);
    LRuntime.ContinueExecution();
    Check(DoNextStop(LRuntime, LRun, LEvent) and (DoTop(LRuntime).RoutineName = 'Fact'),
      'runtime_steps: stops in Fact');
    LTop := DoTop(LRuntime);
    LValues := LRuntime.Variables(LTop.FrameId, dskParams);
    Check(DoTextOf(LValues, 'AN') = '3', 'runtime_steps: the outermost Fact (%s)', [DoValuesText(LValues)]);
    LRuntime.SetBreakpoints(LSource, []);
    Check(LRuntime.StepOver() and DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrStep),
      'runtime_steps: the recursive step over stops');
    // Fact's end line has code of its own (the epilogue two returns share):
    // the step stops there, in the SAME frame (AN still 3), not in a deeper
    // Fact the recursive call ran through
    LTop := DoTop(LRuntime);
    LValues := LRuntime.Variables(LTop.FrameId, dskParams);
    Check((LTop.RoutineName = 'Fact') and (LTop.Line = DoMarkerLine('steps', 'M_FACT_END')) and
      (DoTextOf(LValues, 'AN') = '3'), 'runtime_steps: the recursive step over stays in its frame (%s:%d, %s)',
      [LTop.RoutineName, LTop.Line, DoValuesText(LValues)]);
    Check(LRuntime.StepOver() and DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrStep),
      'runtime_steps: stepping over Fact''s end stops');
    LTop := DoTop(LRuntime);
    Check((LTop.RoutineName = 'Run') and (LTop.Line = DoMarkerLine('steps', 'M_GUARD_KW')),
      'runtime_steps: back in Run on the next line start (%s:%d)', [LTop.RoutineName, LTop.Line]);

    // G1: a step over a guard's line stops in its body (a lambda the
    // runtime calls); the routine's names through the lambda's closure
    Check(DoStepStop(LRuntime, LRun, dstOver, LTop) and (LTop.Line = DoMarkerLine('steps', 'M_GUARD')),
      'runtime_steps: a step over a guard line stops in its body (%s:%d)', [LTop.RoutineName, LTop.Line]);
    Check(LTop.RoutineName = 'Run', 'runtime_steps: the guard body is Run''s (%s)', [LTop.RoutineName]);
    LValues := LRuntime.Variables(LTop.FrameId, dskLocals);
    Check(DoTextOf(LValues, 'LA') = '20', 'runtime_steps: a local in a guard body (%s)', [DoValuesText(LValues)]);
    LValues := LRuntime.Variables(LTop.FrameId, dskParams);
    Check(DoTextOf(LValues, 'ATotal') = '0', 'runtime_steps: a var param in a guard body (%s)',
      [DoValuesText(LValues)]);
    // G2: off the body's last statement: the guard's except and end lines
    // are its glue, nothing raised: the next stop is after the guard
    Check(DoStepStop(LRuntime, LRun, dstOver, LTop) and (LTop.RoutineName = 'Run') and
      (LTop.Line = DoMarkerLine('steps', 'M_AFTER_GUARD')),
      'runtime_steps: off a guard body''s end: after the guard (%s:%d)', [LTop.RoutineName, LTop.Line]);
    LRuntime.SetBreakpoints(LSource, [DoMarkerLine('steps', 'M_METHOD_GUARD')]);
    LRuntime.ContinueExecution();
    Check(DoNextStop(LRuntime, LRun, LEvent) and (DoTop(LRuntime).Line = DoMarkerLine('steps', 'M_METHOD_GUARD')),
      'runtime_steps: stops in the method''s guard body');
    LTop := DoTop(LRuntime);
    Check(LTop.RoutineName = 'TBox.Grow', 'runtime_steps: the method''s name (%s)', [LTop.RoutineName]);
    LValues := LRuntime.Variables(LTop.FrameId, dskParams);
    Check((DoTextOf(LValues, 'self') = '{W: 1}') and (DoTextOf(LValues, 'AD') = '2') and
      DoFindValue(LValues, 'self', LValue) and (LValue.TypeText = 'TBox'),
      'runtime_steps: self: TBox and a param in a method''s guard body (%s)', [DoValuesText(LValues)]);
    LRuntime.SetBreakpoints(LSource, []);
    // G3: finish from a guard body leaves the method (the body's lambda is
    // no routine): Run's next line start (the finally part runs on the way,
    // no stop: a finish arms no guard part)
    Check(DoStepStop(LRuntime, LRun, dstOut, LTop) and (LTop.RoutineName = 'Run') and
      (LTop.Line = DoMarkerLine('steps', 'M_GROW_AGAIN')),
      'runtime_steps: finish from a guard body leaves the method (%s:%d)', [LTop.RoutineName, LTop.Line]);
    // G4: in a part that uses neither self nor AD (its lambda captures only
    // LD) both are read from the method's own frame
    LRuntime.SetBreakpoints(LSource, [DoMarkerLine('steps', 'M_METHOD_FINALLY')]);
    LRuntime.ContinueExecution();
    Check(DoNextStop(LRuntime, LRun, LEvent) and (DoTop(LRuntime).Line = DoMarkerLine('steps', 'M_METHOD_FINALLY')),
      'runtime_steps: stops in the method''s finally part');
    LRuntime.SetBreakpoints(LSource, []);
    LTop := DoTop(LRuntime);
    LValues := LRuntime.Variables(LTop.FrameId, dskParams);
    Check((DoTextOf(LValues, 'self') = '{W: 6}') and (DoTextOf(LValues, 'AD') = '3') and
      DoFindValue(LValues, 'self', LValue) and (LValue.TypeText = 'TBox'),
      'runtime_steps: self and a param not captured by a part: the method''s frame (%s)', [DoValuesText(LValues)]);
    LValues := LRuntime.Variables(LTop.FrameId, dskLocals);
    Check(DoTextOf(LValues, 'LD') = '0', 'runtime_steps: a local the part captures (%s)', [DoValuesText(LValues)]);
    // G3 from a finally part: out of the method too
    Check(DoStepStop(LRuntime, LRun, dstOut, LTop) and (LTop.RoutineName = 'Run') and
      (LTop.Line = DoMarkerLine('steps', 'M_RAISE_KW')),
      'runtime_steps: finish from a finally part leaves the method (%s:%d)', [LTop.RoutineName, LTop.Line]);
    // G1 for a step in: into the guard's body
    Check(DoStepStop(LRuntime, LRun, dstIn, LTop) and (LTop.RoutineName = 'Run') and
      (LTop.Line = DoMarkerLine('steps', 'M_RAISE_CALL')),
      'runtime_steps: a step in on a guard line stops in its body (%s:%d)', [LTop.RoutineName, LTop.Line]);

    // A raise unwinds the step's own frame (the guard body): the step stops
    // on the except list's first line, not after the guard
    Check(LRuntime.StepOver() and DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrStep),
      'runtime_steps: the step over a raise stops');
    // The except keyword's line has code (the guard's dispatch, emitter A7):
    // the first stop in Run, then the except list's first statement
    LTop := DoTop(LRuntime);
    Check((LTop.RoutineName = 'Run') and (LTop.Line = DoMarkerLine('steps', 'M_EXCEPT_KW')),
      'runtime_steps: the step over a raise comes back in Run at except (%s:%d)', [LTop.RoutineName, LTop.Line]);
    Check(LRuntime.StepOver() and DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrStep),
      'runtime_steps: stepping from except stops');
    LTop := DoTop(LRuntime);
    Check((LTop.RoutineName = 'Run') and (LTop.Line = DoMarkerLine('steps', 'M_EXCEPT')),
      'runtime_steps: then the except list''s first statement (%s:%d)', [LTop.RoutineName, LTop.Line]);
    // G2 after an except list: the guard's end line is glue
    Check(DoStepStop(LRuntime, LRun, dstOver, LTop) and (LTop.RoutineName = 'Run') and
      (LTop.Line = DoMarkerLine('steps', 'M_DEEP_CALL')),
      'runtime_steps: off an except list: after the guard (%s:%d)', [LTop.RoutineName, LTop.Line]);

    // Deep: a guard with except + finally, recursion from its body
    for LRow in PC_TEST_DEEP_STEPS do
    begin
      Check(DoStepStop(LRuntime, LRun, LRow.Kind, LTop), 'runtime_steps: %s: stops', [LRow.Why]);
      LAN := '';
      if LRow.AN <> '' then
        LAN := DoTextOf(LRuntime.Variables(LTop.FrameId, dskParams), 'AN');
      Check((LTop.RoutineName = LRow.Routine) and (LTop.Line = DoMarkerLine('steps', LRow.Marker)) and
        (LAN = LRow.AN), 'runtime_steps: %s (%s:%d AN %s; want %s:%d AN %s)',
        [LRow.Why, LTop.RoutineName, LTop.Line, LAN, LRow.Routine, DoMarkerLine('steps', LRow.Marker), LRow.AN]);
    end;

    LRuntime.ContinueExecution();
    DoFinish(LRuntime, LRun);
    Check(LRun.Exited and (LRun.ExitCode = 0) and LRun.Output.StartsWith('23' + PC_TEST_DBG_EOL),
      'runtime_steps: runs to its end (exit %d, output %s)', [LRun.ExitCode, DoShow(LRun.Output)]);
    Check(not LErrors.HasErrors(), 'runtime_steps: nothing reported (' + DoReports(LErrors) + ')');
  finally
    LRuntime.Free();
    LErrors.Free();
    LCompiler.Free();
  end;
end;

procedure TPCDebugTests.DoTestRuntimePause();
var
  LExe: string;
  LReason: string;
  LCompiler: TPCCompiler;
  LErrors: TErrors;
  LRuntime: TPCDebugRuntime;
  LRun: TPCRuntimeRun;
  LEvent: TPCDebugEvent;
  LStart: UInt64;
  LTop: TPCDebugStackItem;
  LThread: TPCDebugThread;
  LMain: Cardinal;
  LValues: TArray<TPCDebugValue>;
  LCount: Int64;
begin
  // dbg_spin never ends: Pause breaks in on the main thread, in the loop;
  // Terminate ends it with PC_DBG_TERMINATE_EXIT_CODE
  LRun := Default(TPCRuntimeRun);
  LCompiler := DoBuildProgram('spin', LExe, LReason);
  LErrors := TErrors.Create();
  LRuntime := DoNewRuntime(LErrors, LCompiler, LExe);
  try
    Check(LExe <> '', 'runtime_pause: dbg_spin builds (' + LReason + ')');
    if LExe = '' then
      Exit;
    Check(LRuntime.Launch() and LRuntime.ConfigurationDone(), 'runtime_pause: runs (' + DoReports(LErrors) + ')');
    // Let it spin a while (no event comes)
    LStart := TUtils.GetTickCount64();
    while TUtils.GetTickCount64() - LStart < PC_TEST_DBG_WAIT_MS do
      LRuntime.NextEvent(LEvent, 50);
    Check(LRuntime.Pause(), 'runtime_pause: pause is asked (' + DoReports(LErrors) + ')');
    Check(DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrPause), 'runtime_pause: stops as a pause');
    LMain := 0;
    for LThread in LRuntime.Threads() do
      if LThread.IsMain then
        LMain := LThread.ThreadId;
    Check((LMain <> 0) and (LRuntime.StoppedThread() = LMain), 'runtime_pause: reported on the main thread');
    LTop := DoTop(LRuntime);
    Check(LTop.IsPcpp and (LTop.RoutineName = 'dbg_spin'), 'runtime_pause: in the module body''s loop (%s:%d)',
      [LTop.RoutineName, LTop.Line]);
    LValues := LRuntime.Variables(LTop.FrameId, dskGlobals);
    Check(TryStrToInt64(DoTextOf(LValues, 'GCount'), LCount) and (LCount > 0),
      'runtime_pause: the loop ran (%s)', [DoValuesText(LValues)]);
    LRuntime.Terminate();
    DoFinish(LRuntime, LRun);
    Check(LRun.Exited and (LRun.ExitCode = PC_DBG_TERMINATE_EXIT_CODE),
      'runtime_pause: terminated (exit %d)', [LRun.ExitCode]);
  finally
    LRuntime.Free();
    LErrors.Free();
    LCompiler.Free();
  end;
end;

procedure TPCDebugTests.DoTestRuntimeTerminal();
var
  LExe: string;
  LReason: string;
  LCompiler: TPCCompiler;
  LErrors: TErrors;
  LRuntime: TPCDebugRuntime;
  LRun: TPCRuntimeRun;
  LEvent: TPCDebugEvent;
  LStart: UInt64;
  LReady: Boolean;
begin
  // domTerminal (the editor's pane): the program's stdout is a terminal, so
  // its first line comes while it runs (over a pipe the C runtime holds it
  // to the exit); keys typed into the terminal reach its stdin; a resize is
  // taken; a terminal closed at the exit takes no more keys
  LRun := Default(TPCRuntimeRun);
  LCompiler := DoBuildProgram('term', LExe, LReason);
  LErrors := TErrors.Create();
  LRuntime := DoNewRuntime(LErrors, LCompiler, LExe);
  try
    Check(LExe <> '', 'runtime_terminal: dbg_term builds (' + LReason + ')');
    if LExe = '' then
      Exit;
    LRuntime.SetOutputMode(domTerminal);
    LRuntime.SetTerminalSize(80, 24);
    Check(LRuntime.Launch() and LRuntime.ConfigurationDone(), 'runtime_terminal: runs (' + DoReports(LErrors) + ')');

    // It now waits for a line: the line it printed before must be here
    LReady := False;
    LStart := TUtils.GetTickCount64();
    while (not LReady) and (not LRun.Exited) and
      (TUtils.GetTickCount64() - LStart < PC_TEST_DBG_SESSION_MS) do
    begin
      if not LRuntime.NextEvent(LEvent, PC_TEST_DBG_WAIT_MS) then
        Continue;
      if LEvent.Kind = dekOutput then
      begin
        LRun.Output := LRun.Output + LEvent.OutputText;
        LReady := LRun.Output.Contains('term ready');
      end
      else if LEvent.Kind = dekExited then
      begin
        LRun.Exited := True;
        LRun.ExitCode := LEvent.ExitCode;
      end;
    end;
    Check(LReady and (not LRun.Exited), 'runtime_terminal: its line comes (%s)',
      [LRun.Output.Replace(#27, '\e')]);
    // ... while it runs: it is still there to pause, waiting for its line
    // (over a pipe the line would come only with its exit)
    Check(LRuntime.Pause() and DoNextStop(LRuntime, LRun, LEvent) and (LEvent.Reason = dsrPause),
      'runtime_terminal: it still runs after its line (exited %s)', [BoolToStr(LRun.Exited, True)]);
    if not LRun.Exited then
      LRuntime.ContinueExecution();

    Check(LRuntime.ResizeTerminal(100, 30), 'runtime_terminal: the terminal takes a new size');
    Check(LRuntime.WriteInput('abc'#13), 'runtime_terminal: keys are typed into it');
    DoFinish(LRuntime, LRun);
    Check(LRun.Output.Contains('got abc'), 'runtime_terminal: the program read the typed line (%s)',
      [LRun.Output.Replace(#27, '\e')]);
    Check(LRun.Exited and (LRun.ExitCode = 0), 'runtime_terminal: exits 0 (exit %d)', [LRun.ExitCode]);
    Check(not LRuntime.WriteInput('x'), 'runtime_terminal: the closed terminal takes no keys');
  finally
    LRuntime.Free();
    LErrors.Free();
    LCompiler.Free();
  end;
end;

{ REPL helpers (e4) }

function DoMarkerLineIn(const APath: string; const AMarker: string): Integer;
var
  LLines: TArray<string>;
  LIndex: Integer;
begin
  // The 1-based line of APath that ends in '// <AMarker>' (0 = none): a
  // fixture's further files (DoMarkerLine reads the main file)
  Result := 0;
  LLines := TFile.ReadAllLines(APath, TEncoding.UTF8);
  for LIndex := 0 to High(LLines) do
    if LLines[LIndex].EndsWith('// ' + AMarker) then
      Exit(LIndex + 1);
end;

function DoCountOf(const AText: string; const APart: string): Integer;
var
  LAt: Integer;
begin
  Result := 0;
  LAt := AText.IndexOf(APart);
  while LAt >= 0 do
  begin
    Inc(Result);
    LAt := AText.IndexOf(APart, LAt + APart.Length);
  end;
end;

function DoReplRun(const AProgram: TPCCompiler; const AExe: string; const AScript: array of string;
  const ACase: string; out AOutput: string; out AExitCode: Cardinal): Boolean;
var
  LLines: TArray<string>;
  LIndex: Integer;
  LI: Integer;
  LText: TStringBuilder;
  LRepl: TPCDebugREPL;
begin
  // The REPL as the CLI runs it, its console replaced: the script's lines,
  // then the end of the input; all it shows collected (and kept in
  // %TEMP%\pcpp-dbg\<case>.txt to read when a check fails)
  SetLength(LLines, Length(AScript));
  for LI := 0 to High(AScript) do
    LLines[LI] := AScript[LI];
  LIndex := 0;
  LText := TStringBuilder.Create();
  try
    LRepl := TPCDebugREPL.Create();
    try
      if AProgram <> nil then
        LRepl.SetProgram(AProgram.GetMainModule());
      LRepl.SetTarget(AExe, '');
      LRepl.SetWaitLimit(PC_TEST_DBG_SESSION_MS);
      LRepl.SetReader(
        function(out ALine: string): Boolean
        begin
          ALine := '';
          Result := LIndex < Length(LLines);
          if Result then
          begin
            ALine := LLines[LIndex];
            Inc(LIndex);
          end;
        end);
      LRepl.SetWriter(
        procedure(const AText: string)
        begin
          LText.Append(AText);
        end);
      Result := LRepl.Run();
      AExitCode := LRepl.GetLastExitCode();
    finally
      // Freeing ends the program: what that shows is collected too
      LRepl.Free();
    end;
    AOutput := LText.ToString();
  finally
    LText.Free();
  end;
  try
    TFile.WriteAllText(TPath.Combine(TPath.Combine(TPath.GetTempPath(), 'pcpp-dbg'), ACase + '.txt'),
      AOutput, TEncoding.UTF8);
  except
    on E: Exception do
      AOutput := AOutput + sLineBreak + '(not kept: ' + E.Message + ')';
  end;
end;

procedure TPCDebugTests.DoTestImageSpelling();
var
  LExe: string;
  LReason: string;
  LBuffer: array[0..1023] of Char;
  LLength: DWORD;
  LShort: string;
  LErrors: TErrors;
  LTarget: TPCDebugTarget;
  LRun: TPCDebugRun;
begin
  // The image given in an 8.3 spelling (a %TEMP% often has one): the target
  // names it as the loader names its load (the file's final path), so the
  // load is recognized (DLL mode's dll, the program's line requirement)
  Check(DoBuildFixture('hello', LExe, LReason), 'image_spelling: dbg_hello builds (' + LReason + ')');
  if LExe = '' then
    Exit;
  LShort := '';
  LLength := GetShortPathName(PChar(LExe.Replace('/', '\')), LBuffer, Length(LBuffer));
  if (LLength > 0) and (LLength < DWORD(Length(LBuffer))) then
    SetString(LShort, PChar(@LBuffer[0]), LLength);
  Check((LShort <> '') and (not SameText(LShort, LExe.Replace('/', '\'))),
    'image_spelling: the exe has an 8.3 spelling (%s)', [LShort]);
  if LShort = '' then
    Exit;
  LErrors := TErrors.Create();
  LTarget := DoNewTarget(LErrors, LShort);
  try
    Check(LTarget.Start(), 'image_spelling: starts (' + DoReports(LErrors) + ')');
    LRun := DoSession(LTarget,
      function(const ATarget: TPCDebugTarget; const AEvent: TPCDebugEvent): TPCResumeKind
      begin
        Result := rkContinue;
      end);
    Check((Length(LRun.Modules) > 0) and TUtils.SamePath(LRun.Modules[0].ModulePath, LTarget.ImagePath()) and
      TUtils.SamePath(LTarget.ImagePath(), LExe),
      'image_spelling: ImagePath is the loader''s name of the exe (%s)', [LTarget.ImagePath()]);
  finally
    LTarget.Free();
    LErrors.Free();
  end;
end;

procedure TPCDebugTests.DoTestReplSourceBreakpoints();
var
  LExe: string;
  LReason: string;
  LCompiler: TPCCompiler;
  LErrors: TErrors;
  LRuntime: TPCDebugRuntime;
  LMain: string;
  LUnit: string;
  LModules: TArray<TPCModule>;
  LLines: TArray<TPCDebugSourceLine>;
begin
  // The program's @breakpoint statements come from the AST: the main
  // body's and the imported unit's, per module in import order; the
  // prologue's has no effect (SM0109) and is not one. The engine's target
  LCompiler := DoBuildProgram('repl', LExe, LReason);
  LErrors := TErrors.Create();
  LRuntime := DoNewRuntime(LErrors, LCompiler, LExe);
  try
    Check(LExe <> '', 'repl_source_bps: dbg_repl builds (' + LReason + ')');
    if LExe = '' then
      Exit;
    LMain := DoFixturePath('repl');
    LUnit := TPath.Combine(TPath.GetDirectoryName(LMain), 'dbg_repl_u.pcpp');
    LModules := LRuntime.ProgramModules();
    Check((Length(LModules) = 2) and TUtils.SamePath(LModules[0].SourceFile, LMain) and
      TUtils.SamePath(LModules[1].SourceFile, LUnit),
      'repl_source_bps: the modules are the main one, then its import (%d)', [Length(LModules)]);
    LLines := LRuntime.SourceBreakpoints();
    Check((Length(LLines) = 2) and
      TUtils.SamePath(LLines[0].FileName, LMain) and (LLines[0].Line = DoMarkerLine('repl', 'M_BP')) and
      TUtils.SamePath(LLines[1].FileName, LUnit) and (LLines[1].Line = DoMarkerLineIn(LUnit, 'M_U_BP')),
      'repl_source_bps: the two body @breakpoint lines, not the prologue''s (%d)', [Length(LLines)]);
    Check(TPCDebugRuntime.SupportsTarget('x86_64-windows-gnu') and
      (not TPCDebugRuntime.SupportsTarget('x86_64-linux-gnu')),
      'repl_source_bps: the engine debugs x86_64-windows-gnu only');
  finally
    LRuntime.Free();
    LErrors.Free();
    LCompiler.Free();
  end;
end;

procedure TPCDebugTests.DoTestReplSession();
var
  LExe: string;
  LReason: string;
  LCompiler: TPCCompiler;
  LUnit: string;
  LOut: string;
  LExit: Cardinal;
  LOk: Boolean;
  LBp: Integer;
  LCall: Integer;
  LUBp: Integer;
  LURet: Integer;
  LPrint: Integer;
  LTriple: Integer;
begin
  // A whole REPL session over dbg_repl, the way a person types it: the
  // @breakpoint stops (moved forward to the next line with code), steps,
  // the variables with PaskalCPP names and types (in a var section too),
  // p, the scope of an imported unit's frame, f, bt, bd, b, the exit, a
  // command with no program, an unknown command, r (same breakpoints), q
  LCompiler := DoBuildProgram('repl', LExe, LReason);
  try
    Check(LExe <> '', 'repl_session: dbg_repl builds (' + LReason + ')');
    if LExe = '' then
      Exit;
    LUnit := TPath.Combine(TPath.GetDirectoryName(DoFixturePath('repl')), 'dbg_repl_u.pcpp');
    LBp := DoMarkerLine('repl', 'M_BP');
    LCall := DoMarkerLine('repl', 'M_CALL');
    LTriple := DoMarkerLine('repl', 'M_TRIPLE');
    LPrint := DoMarkerLine('repl', 'M_PRINT');
    LUBp := DoMarkerLineIn(LUnit, 'M_U_BP');
    LURet := DoMarkerLineIn(LUnit, 'M_U_RETURN');
    LOk := DoReplRun(LCompiler, LExe, ['bl', 's', 'locals', 'p AA', 'n', 'p AA + 1', 'finish', 'p GTotal',
      'c', 'p GTotal', 'f 1', 'p GTotal', 'bt', 'bd 2', Format('b dbg_repl.pcpp:%d', [LPrint]), 'c', 'c',
      'p GTotal', 'xyz', 'r', 'bl', 'q'], 'repl_session', LOut, LExit);
    Check(LOk, 'repl_session: the program starts');
    Check(LOut.Contains(Format(RSDbgReplSourceBreakpoints, [2])), 'repl_session: 2 breakpoints from @breakpoint');
    Check(DoCountOf(LOut, Format(RSDbgReplStopped, [RSDbgReplReasonBreakpoint, 'dbg_repl', 'dbg_repl.pcpp',
      LCall])) = 2, 'repl_session: the main @breakpoint stops on the next line with code, in both runs');
    Check(DoCountOf(LOut, Format(RSDbgReplBpMoved, [1, 'dbg_repl.pcpp', LBp, LCall])) = 2,
      'repl_session: bl shows #1 moved forward (both runs)');
    Check(DoCountOf(LOut, Format(RSDbgReplBpMoved, [2, 'dbg_repl_u.pcpp', LUBp, LURet])) = 1,
      'repl_session: bl shows #2 in the unit moved forward, once (deleted before r)');
    // s stops past Add's prologue: its first line with code after the
    // header (the var line), where the params are already stored (e5b)
    Check(LOut.Contains(Format(RSDbgReplStopped, [RSDbgReplReasonStep, 'Add', 'dbg_repl.pcpp',
      DoMarkerLine('repl', 'M_ADD_VAR')])), 'repl_session: s enters Add past its prologue (the var line)');
    Check(not LOut.Contains(Format(RSDbgReplStopped, [RSDbgReplReasonStep, 'Add', 'dbg_repl.pcpp',
      DoMarkerLine('repl', 'M_ADD_HEAD')])), 'repl_session: s never stops on Add''s header (its prologue)');
    Check(LOut.Contains(Format(RSDbgReplStopped, [RSDbgReplReasonStep, 'Add', 'dbg_repl.pcpp',
      DoMarkerLine('repl', 'M_ADD_BODY')])), 'repl_session: n stops on the body''s first line');
    Check(LOut.Contains(Format(RSDbgReplValue, ['AA', 'int32', '2'])) and
      LOut.Contains(Format(RSDbgReplValue, ['AB', 'int32', '3'])),
      'repl_session: locals at the s stop shows the params (readable past the prologue)');
    Check(LOut.Contains(Format(RSDbgReplValue, ['LSum', 'int32', ''])),
      'repl_session: a local on its own var line has its PaskalCPP name and type');
    Check(LOut.Contains(Format(RSDbgReplEval, ['AA', '2'])), 'repl_session: p AA');
    Check(LOut.Contains(Format(RSDbgEvalUnsupported, ['AA + 1'])), 'repl_session: p of an expression says why not');
    Check(LOut.Contains(Format(RSDbgReplStopped, [RSDbgReplReasonStep, 'dbg_repl', 'dbg_repl.pcpp', LTriple])),
      'repl_session: finish returns to the next line of the caller');
    Check(DoCountOf(LOut, Format(RSDbgReplEval, ['GTotal', '5'])) = 2,
      'repl_session: p GTotal in the main body, and in frame 1 after f 1');
    Check(LOut.Contains(Format(RSDbgReplStopped, [RSDbgReplReasonBreakpoint, 'Triple', 'dbg_repl_u.pcpp', LURet])),
      'repl_session: the unit''s @breakpoint stops in Triple');
    Check(LOut.Contains(Format(RSDbgEvalUnknownName, ['GTotal'])),
      'repl_session: the main module''s variable is not visible in the unit''s frame');
    Check(LOut.Contains(Format(RSDbgReplFrame, [' ', 0, 'Triple', 'dbg_repl_u.pcpp', LURet])) and
      LOut.Contains(Format(RSDbgReplFrame, ['>', 1, 'dbg_repl', 'dbg_repl.pcpp', LTriple])),
      'repl_session: bt marks the selected frame');
    Check(LOut.Contains(Format(RSDbgReplBpDeleted, [2])), 'repl_session: bd 2');
    Check(DoCountOf(LOut, Format(RSDbgReplBpSet, [3, 'dbg_repl.pcpp', LPrint])) = 2,
      'repl_session: b file:line is #3, kept for the next run');
    Check(LOut.Contains(Format(RSDbgReplStopped, [RSDbgReplReasonBreakpoint, 'dbg_repl', 'dbg_repl.pcpp', LPrint])),
      'repl_session: stops at the new breakpoint');
    Check(LOut.Contains('total 15') and LOut.Contains(Format(RSDbgReplExited, [0])),
      'repl_session: the program''s output, then its exit');
    Check(LOut.Contains(RSDbgReplNotRunning), 'repl_session: a command with no program says so');
    Check(LOut.Contains(Format(RSDbgReplUnknown, ['xyz'])), 'repl_session: an unknown command');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCDebugTests.DoTestReplHeaderBreakpoint();
var
  LExe: string;
  LReason: string;
  LCompiler: TPCCompiler;
  LOut: string;
  LExit: Cardinal;
  LHead: Integer;
  LVar: Integer;
begin
  // A breakpoint on a routine's header line is its prologue's code: it is
  // placed where the prologue ends (the var line), and the stop there reads
  // the params (e5b). The @breakpoint lines are #1 and #2
  LCompiler := DoBuildProgram('repl', LExe, LReason);
  try
    Check(LExe <> '', 'repl_header_bp: dbg_repl builds (' + LReason + ')');
    if LExe = '' then
      Exit;
    LHead := DoMarkerLine('repl', 'M_ADD_HEAD');
    LVar := DoMarkerLine('repl', 'M_ADD_VAR');
    Check(DoReplRun(LCompiler, LExe, [Format('b dbg_repl.pcpp:%d', [LHead]), 'c', 'bl', 'locals', 'q'],
      'repl_header_bp', LOut, LExit), 'repl_header_bp: the program starts');
    Check(LOut.Contains(Format(RSDbgReplStopped, [RSDbgReplReasonBreakpoint, 'Add', 'dbg_repl.pcpp', LVar])),
      'repl_header_bp: the header breakpoint stops in Add on its var line');
    Check(LOut.Contains(Format(RSDbgReplBpMoved, [3, 'dbg_repl.pcpp', LHead, LVar])),
      'repl_header_bp: bl shows #3 moved past the prologue');
    Check(LOut.Contains(Format(RSDbgReplValue, ['AA', 'int32', '2'])) and
      LOut.Contains(Format(RSDbgReplValue, ['AB', 'int32', '3'])),
      'repl_header_bp: locals at the stop shows the params');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCDebugTests.DoTestReplEndOfInput();
var
  LExe: string;
  LReason: string;
  LCompiler: TPCCompiler;
  LUnit: string;
  LOut: string;
  LExit: Cardinal;
begin
  // The end of the input ends the REPL as q does: the program, stopped in
  // Triple, is ended (no exit of its own)
  LCompiler := DoBuildProgram('repl', LExe, LReason);
  try
    Check(LExe <> '', 'repl_eof: dbg_repl builds (' + LReason + ')');
    if LExe = '' then
      Exit;
    LUnit := TPath.Combine(TPath.GetDirectoryName(DoFixturePath('repl')), 'dbg_repl_u.pcpp');
    Check(DoReplRun(LCompiler, LExe, ['c'], 'repl_eof', LOut, LExit), 'repl_eof: the program starts');
    Check(LOut.Contains(Format(RSDbgReplStopped, [RSDbgReplReasonBreakpoint, 'Triple', 'dbg_repl_u.pcpp',
      DoMarkerLineIn(LUnit, 'M_U_RETURN')])), 'repl_eof: c reaches Triple');
    // RSDbgReplExited up to its code
    Check((not LOut.Contains('total 15')) and
      (DoCountOf(LOut, RSDbgReplExited.Substring(0, RSDbgReplExited.IndexOf('%'))) = 0),
      'repl_eof: the program is ended where it stood');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCDebugTests.DoTestReplEntryHold();
var
  LExe: string;
  LReason: string;
  LCompiler: TPCCompiler;
  LSteps: string;
  LBodyLine: Integer;
  LOut: string;
  LExit: Cardinal;
begin
  // A program with no breakpoint at all is held at its entry: a step and
  // an inspection are refused (not started yet), c runs it to its end
  LCompiler := DoBuildProgram('hello', LExe, LReason);
  try
    Check(LExe <> '', 'repl_entry_hold: dbg_hello builds (' + LReason + ')');
    if LExe = '' then
      Exit;
    Check(DoReplRun(LCompiler, LExe, ['n', 'locals', 'c'], 'repl_entry_hold', LOut, LExit),
      'repl_entry_hold: the program starts');
    Check(LOut.Contains(RSDbgReplHeldAtEntry), 'repl_entry_hold: held at its entry');
    Check(DoCountOf(LOut, RSDbgReplAtEntry) = 2, 'repl_entry_hold: n and locals are refused (%d)',
      [DoCountOf(LOut, RSDbgReplAtEntry)]);
    Check(LOut.Contains('out 1') and LOut.Contains(Format(RSDbgReplExited, [0])),
      'repl_entry_hold: c runs it to its end');
  finally
    LCompiler.Free();
  end;

  // A breakpoint set while held is placed: c stops there
  LCompiler := DoBuildProgram('steps', LExe, LReason);
  try
    Check(LExe <> '', 'repl_entry_hold: dbg_steps builds (' + LReason + ')');
    if LExe = '' then
      Exit;
    LSteps := DoFixturePath('steps');
    LBodyLine := DoMarkerLineIn(LSteps, 'M_TWICE_BODY');
    Check(DoReplRun(LCompiler, LExe, ['b ' + IntToStr(LBodyLine), 'c', 'q'], 'repl_entry_hold', LOut, LExit),
      'repl_entry_hold: dbg_steps starts');
    Check(LOut.Contains(RSDbgReplHeldAtEntry), 'repl_entry_hold: dbg_steps is held at its entry');
    Check(LOut.Contains(Format(RSDbgReplStopped, [RSDbgReplReasonBreakpoint, 'Twice', 'dbg_steps.pcpp',
      LBodyLine])), 'repl_entry_hold: a b set while held stops the run');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCDebugTests.DoTestReplLaunchFailure();
var
  LOut: string;
  LExit: Cardinal;
begin
  // A program that cannot start: Run is False, the engine's report is shown
  Check(not DoReplRun(nil, TPath.Combine(TPath.GetTempPath(), 'pcpp-dbg\no_such_program.exe'), ['bl'],
    'repl_launch_fail', LOut, LExit), 'repl_launch_fail: Run is False');
  Check(LOut.Contains(PC_ERR_DBG_001), 'repl_launch_fail: DB0001 is shown');
end;

const
  { PC_TEST_DBG_PAUSE_LIMIT_MS }
  // repl_pause's wait limit: a pause that never comes fails in this time
  PC_TEST_DBG_PAUSE_LIMIT_MS = 15000;
  { PC_TEST_DBG_PAUSE_ASK_MS }
  // How often the asking thread asks again
  PC_TEST_DBG_PAUSE_ASK_MS = 200;

procedure TPCDebugTests.DoTestReplPause();
var
  LExe: string;
  LReason: string;
  LCompiler: TPCCompiler;
  LRepl: TPCDebugREPL;
  LText: TStringBuilder;
  LLines: TArray<string>;
  LIndex: Integer;
  LStopped: Integer;
  LDone: Integer;
  LAsker: TThread;
  LOk: Boolean;
  LOut: string;
  LPrefix: string;
  LValueAt: Integer;
  LDigits: string;
  LCount: Int64;
begin
  // dbg_spin never stops by itself: RequestPause (what the console's Ctrl+C
  // handler calls, from a thread of its own) breaks in while the REPL
  // waits; the prompt comes back with the program paused in its loop, q
  // ends it. The asker asks again until the stop shows: one asked before
  // the REPL waits is dropped (RequestPause's own rule)
  LCompiler := DoBuildProgram('spin', LExe, LReason);
  try
    Check(LExe <> '', 'repl_pause: dbg_spin builds (' + LReason + ')');
    if LExe = '' then
      Exit;
    LPrefix := Format(RSDbgReplStopped, [RSDbgReplReasonPause, 'dbg_spin', 'dbg_spin.pcpp', 0]);
    LPrefix := LPrefix.Substring(0, LPrefix.LastIndexOf(':') + 1);
    // dbg_spin has no breakpoint: held at its entry, c runs it
    LLines := ['c', 'p GCount', 'q'];
    LIndex := 0;
    LStopped := 0;
    LDone := 0;
    LAsker := nil;
    LText := TStringBuilder.Create();
    LRepl := TPCDebugREPL.Create();
    try
      LRepl.SetProgram(LCompiler.GetMainModule());
      LRepl.SetTarget(LExe, '');
      LRepl.SetWaitLimit(PC_TEST_DBG_PAUSE_LIMIT_MS);
      LRepl.SetReader(
        function(out ALine: string): Boolean
        begin
          ALine := '';
          Result := LIndex < Length(LLines);
          if Result then
          begin
            ALine := LLines[LIndex];
            Inc(LIndex);
          end;
        end);
      LRepl.SetWriter(
        procedure(const AText: string)
        begin
          LText.Append(AText);
          if AText.Contains(LPrefix) then
            TInterlocked.Exchange(LStopped, 1);
        end);
      LAsker := TThread.CreateAnonymousThread(
        procedure
        var
          LStart: UInt64;
        begin
          LStart := TUtils.GetTickCount64();
          while (TInterlocked.CompareExchange(LStopped, 0, 0) = 0) and
            (TInterlocked.CompareExchange(LDone, 0, 0) = 0) and
            (TUtils.GetTickCount64() - LStart < PC_TEST_DBG_PAUSE_LIMIT_MS) do
          begin
            Sleep(PC_TEST_DBG_PAUSE_ASK_MS);
            LRepl.RequestPause();
          end;
        end);
      LAsker.FreeOnTerminate := False;
      LAsker.Start();
      LOk := LRepl.Run();
    finally
      // The asker is gone before the REPL it calls
      TInterlocked.Exchange(LDone, 1);
      if LAsker <> nil then
      begin
        LAsker.WaitFor();
        LAsker.Free();
      end;
      LRepl.Free();
      LOut := LText.ToString();
      LText.Free();
    end;

    Check(LOk, 'repl_pause: the program starts');
    Check(LOut.Contains(LPrefix), 'repl_pause: RequestPause stops it in its loop');
    // 'GCount = <n>': the loop ran (n > 0)
    LCount := 0;
    LValueAt := LOut.IndexOf(Format(RSDbgReplEval, ['GCount', '']));
    if LValueAt >= 0 then
    begin
      LDigits := '';
      LValueAt := LValueAt + Format(RSDbgReplEval, ['GCount', '']).Length;
      while (LValueAt < LOut.Length) and CharInSet(LOut.Chars[LValueAt], ['0'..'9']) do
      begin
        LDigits := LDigits + LOut.Chars[LValueAt];
        Inc(LValueAt);
      end;
      LCount := StrToInt64Def(LDigits, 0);
    end;
    Check(LCount > 0, 'repl_pause: p GCount shows the loop ran (%d)', [LCount]);
  finally
    LCompiler.Free();
  end;
end;

type
  { TPCReplReadRow }
  // One console read and what the REPL must make of it
  TPCReplReadRow = record
    Ok: Boolean;
    Count: Cardinal;
    Text: string;
    Broken: Boolean;
    Want: TPCReplReadKind;
    Why: string;
  end;

const
  { PC_TEST_REPL_READ_ROWS }
  PC_TEST_REPL_READ_ROWS: array[0..7] of TPCReplReadRow = (
    (Ok: True;  Count: 4; Text: 'bl'#13#10;  Broken: False; Want: rrkLine;  Why: 'a typed line'),
    (Ok: True;  Count: 2; Text: #13#10;      Broken: False; Want: rrkLine;  Why: 'Enter alone: an empty line'),
    (Ok: True;  Count: 0; Text: '';          Broken: True;  Want: rrkBreak; Why: 'Ctrl+C at the prompt (nothing read): the prompt again'),
    (Ok: False; Count: 0; Text: '';          Broken: True;  Want: rrkBreak; Why: 'Ctrl+C at the prompt (the read failed): the prompt again'),
    (Ok: True;  Count: 0; Text: '';          Broken: False; Want: rrkEnd;   Why: 'nothing read, no Ctrl+C: the end'),
    (Ok: False; Count: 0; Text: '';          Broken: False; Want: rrkEnd;   Why: 'a failed read, no Ctrl+C: the end'),
    (Ok: True;  Count: 3; Text: #26#13#10;   Broken: False; Want: rrkEnd;   Why: 'Ctrl+Z Enter: the end'),
    (Ok: True;  Count: 4; Text: 'bl'#13#10;  Broken: True;  Want: rrkLine;  Why: 'a line wins over a stale Ctrl+C')
  );

procedure TPCDebugTests.DoTestReplConsoleRead();
var
  LRow: TPCReplReadRow;
  LGot: TPCReplReadKind;
begin
  // The console reader's one decision (TPCDebugREPL.ClassifyConsoleRead):
  // Ctrl+C at the (dbg) prompt is never the end of the input. The real
  // key is the person's check (a test cannot press it)
  for LRow in PC_TEST_REPL_READ_ROWS do
  begin
    LGot := TPCDebugREPL.ClassifyConsoleRead(LRow.Ok, LRow.Count, LRow.Text, LRow.Broken);
    Check(LGot = LRow.Want, 'repl_console_read: %s (got %d, want %d)', [LRow.Why, Ord(LGot), Ord(LRow.Want)]);
  end;
  Check((TPCDebugREPL.ConsoleLineText('p AA'#13#10) = 'p AA') and (TPCDebugREPL.ConsoleLineText('bt'#10) = 'bt') and
    (TPCDebugREPL.ConsoleLineText('c') = 'c'), 'repl_console_read: the line end is cut, the text kept');
end;

type
  { TPCReplModeRow }
  // The REPL's standard handles and where the program's go
  TPCReplModeRow = record
    InputIsConsole: Boolean;
    OutputIsConsole: Boolean;
    OwnIO: Boolean;
    Want: TPCDebugOutputMode;
    Why: string;
  end;

const
  { PC_TEST_REPL_MODE_ROWS }
  PC_TEST_REPL_MODE_ROWS: array[0..7] of TPCReplModeRow = (
    (InputIsConsole: True;  OutputIsConsole: True;  OwnIO: False; Want: domConsole; Why: 'pcpp -d at a console: the program shares it'),
    (InputIsConsole: True;  OutputIsConsole: True;  OwnIO: True;  Want: domPipes;   Why: 'a test reader / writer: pipes'),
    (InputIsConsole: False; OutputIsConsole: True;  OwnIO: False; Want: domPipes;   Why: 'scripted input (check_dbg.py): pipes'),
    (InputIsConsole: True;  OutputIsConsole: False; OwnIO: False; Want: domPipes;   Why: 'output to a file: pipes'),
    (InputIsConsole: False; OutputIsConsole: False; OwnIO: False; Want: domPipes;   Why: 'both redirected: pipes'),
    (InputIsConsole: False; OutputIsConsole: True;  OwnIO: True;  Want: domPipes;   Why: 'scripted input and own io: pipes'),
    (InputIsConsole: True;  OutputIsConsole: False; OwnIO: True;  Want: domPipes;   Why: 'output to a file and own io: pipes'),
    (InputIsConsole: False; OutputIsConsole: False; OwnIO: True;  Want: domPipes;   Why: 'all redirected and own io: pipes')
  );

procedure TPCDebugTests.DoTestReplOutputMode();
var
  LRow: TPCReplModeRow;
  LGot: TPCDebugOutputMode;
begin
  // The REPL's one decision on the program's handles
  // (TPCDebugREPL.ProgramOutputMode): a terminal whenever the person is at
  // one. The shared console itself is the person's check
  for LRow in PC_TEST_REPL_MODE_ROWS do
  begin
    LGot := TPCDebugREPL.ProgramOutputMode(LRow.InputIsConsole, LRow.OutputIsConsole, LRow.OwnIO);
    Check(LGot = LRow.Want, 'repl_output_mode: %s (got %d, want %d)', [LRow.Why, Ord(LGot), Ord(LRow.Want)]);
  end;
end;

{ DoDapFrame }
// One message as the client writes it (the LSP base protocol's framing)
function DoDapFrame(const ABody: string): TBytes;
var
  LBody: TBytes;
begin
  LBody := TEncoding.UTF8.GetBytes(ABody);
  Result := TEncoding.ASCII.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(LBody)])) + LBody;
end;

{ DoDapCollect }
// Every complete message AStream holds from ARead on, parsed into AInto;
// ARead moves past them (the stream's Position is not touched)
procedure DoDapCollect(const AStream: TMemoryStream; var ARead: Int64; const AInto: TObjectList<TJSON>);
var
  LBytes: TBytes;
  LEnd: Int64;
  LHeader: string;
  LLine: string;
  LLength: Integer;
  LValue: TJSON;
begin
  SetLength(LBytes, AStream.Size);
  if AStream.Size > 0 then
    Move(AStream.Memory^, LBytes[0], AStream.Size);
  while ARead < Length(LBytes) do
  begin
    // The header block ends at the first CR LF CR LF
    LEnd := ARead;
    while (LEnd + 3 < Length(LBytes)) and
      not ((LBytes[LEnd] = 13) and (LBytes[LEnd + 1] = 10) and (LBytes[LEnd + 2] = 13) and (LBytes[LEnd + 3] = 10)) do
      Inc(LEnd);
    if LEnd + 3 >= Length(LBytes) then
      Exit;
    LHeader := TEncoding.ASCII.GetString(LBytes, ARead, LEnd - ARead);
    LLength := -1;
    for LLine in LHeader.Split([#13#10]) do
      if LLine.ToLower().StartsWith('content-length:') then
        LLength := StrToIntDef(LLine.Substring(Length('content-length:')).Trim(), -1);
    if (LLength < 0) or (LEnd + 4 + LLength > Length(LBytes)) then
      Exit;
    // A message that is no JSON object is not kept
    if TJSON.TryFromString(TEncoding.UTF8.GetString(LBytes, LEnd + 4, LLength), LValue) then
    begin
      if LValue.IsObject() then
        AInto.Add(LValue)
      else
        LValue.Free();
    end;
    ARead := LEnd + 4 + LLength;
  end;
end;

{ DoJsonText }
// The string at APath of a message ('' when absent; AValue nil = no message)
function DoJsonText(const AValue: TJSON; const APath: string): string;
begin
  if (AValue = nil) or (not AValue.TryGetString(APath, Result)) then
    Result := '';
end;

{ DoJsonInt }
// The integer at APath of a message (-1 when absent; AValue nil = no message)
function DoJsonInt(const AValue: TJSON; const APath: string): Integer;
begin
  if (AValue = nil) or (not AValue.TryGetInt32(APath, Result)) then
    Result := -1;
end;

{ DoJsonFlag }
// The boolean at APath of a message (False when absent; AValue nil = no message)
function DoJsonFlag(const AValue: TJSON; const APath: string): Boolean;
begin
  if (AValue = nil) or (not AValue.TryGetBoolean(APath, Result)) then
    Result := False;
end;

{ DoDapArgs }
// {"<AName>": "<AValue>", ...}: names and values in pairs
function DoDapArgs(const APairs: array of string): TJSONObject;
var
  LIndex: Integer;
begin
  Result := TJSONObject.Create();
  LIndex := 0;
  while LIndex + 1 <= High(APairs) do
  begin
    Result.AddPair(APairs[LIndex], APairs[LIndex + 1]);
    Inc(LIndex, 2);
  end;
end;

{ DoDapIntArgs }
function DoDapIntArgs(const AName: string; const AValue: Integer): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair(AName, TJSONNumber.Create(AValue));
end;

{ DoDapBreakpointArgs }
// setBreakpoints: AFile's whole set
function DoDapBreakpointArgs(const AFile: string; const ALines: array of Integer): TJSONObject;
var
  LSource: TJSONObject;
  LArray: TJSONArray;
  LItem: TJSONObject;
  LLine: Integer;
begin
  Result := TJSONObject.Create();
  LSource := TJSONObject.Create();
  LSource.AddPair('path', AFile);
  Result.AddPair('source', LSource);
  LArray := TJSONArray.Create();
  for LLine in ALines do
  begin
    LItem := TJSONObject.Create();
    LItem.AddPair('line', TJSONNumber.Create(LLine));
    LArray.AddElement(LItem);
  end;
  Result.AddPair('breakpoints', LArray);
end;

type
  { TPCDapClient }
  // The client side of a DAP session in the tests: requests go to the
  // adapter in-process (HandleMessage, as Run hands them over), what it
  // writes is read back from its output stream frame by frame
  TPCDapClient = class(TBaseObject)
  private
    FAdapter: TPCDebugDAP;
    FOutput: TMemoryStream;
    FTransport: TPCLspTransport;
    FRead: Int64;
    FSeq: Integer;
    FMessages: TObjectList<TJSON>;
    FTaken: TList<Integer>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    // Sends ACommand (AArguments owned; nil = none); its response, nil = none
    function Request(const ACommand: string; const AArguments: TJSONObject): TJSON;
    // The next AEvent not taken yet, pumping the adapter up to ATimeoutMs;
    // nil = none came
    function WaitEvent(const AEvent: string; const ATimeoutMs: Cardinal): TJSON;
    // Every output event's text of ACategory so far
    function OutputText(const ACategory: string): string;
    property Adapter: TPCDebugDAP read FAdapter;
  end;

{ TPCDapClient }

constructor TPCDapClient.Create();
begin
  inherited;

  FOutput := TMemoryStream.Create();
  FTransport := TPCLspTransport.Create();
  FTransport.Init(nil, FOutput);
  FAdapter := TPCDebugDAP.Create();
  FAdapter.Open(FTransport);
  FRead := 0;
  FSeq := 0;
  FMessages := TObjectList<TJSON>.Create(True);
  FTaken := TList<Integer>.Create();
end;

destructor TPCDapClient.Destroy();
begin
  // The adapter ends its program and may still write: it goes first
  FAdapter.Free();
  FTransport.Free();
  FOutput.Free();
  FMessages.Free();
  FTaken.Free();

  inherited;
end;

function TPCDapClient.Request(const ACommand: string; const AArguments: TJSONObject): TJSON;
var
  LMessage: TJSONObject;
  LText: string;
  LItem: TJSON;
begin
  Inc(FSeq);
  LMessage := TJSONObject.Create();
  try
    LMessage.AddPair('seq', TJSONNumber.Create(FSeq));
    LMessage.AddPair('type', 'request');
    LMessage.AddPair('command', ACommand);
    if AArguments <> nil then
      LMessage.AddPair('arguments', AArguments);
    LText := LMessage.ToJSON();
  finally
    LMessage.Free();
  end;
  FAdapter.HandleMessage(LText);
  DoDapCollect(FOutput, FRead, FMessages);
  for LItem in FMessages do
    if (DoJsonText(LItem, 'type') = 'response') and (DoJsonInt(LItem, 'request_seq') = FSeq) then
      Exit(LItem);
  Result := nil;
end;

function TPCDapClient.WaitEvent(const AEvent: string; const ATimeoutMs: Cardinal): TJSON;
var
  LStart: UInt64;
  LIndex: Integer;
begin
  LStart := TUtils.GetTickCount64();
  while True do
  begin
    for LIndex := 0 to FMessages.Count - 1 do
      if (not FTaken.Contains(LIndex)) and (DoJsonText(FMessages[LIndex], 'type') = 'event') and
        (DoJsonText(FMessages[LIndex], 'event') = AEvent) then
      begin
        FTaken.Add(LIndex);
        Exit(FMessages[LIndex]);
      end;
    if TUtils.GetTickCount64() - LStart >= ATimeoutMs then
      Exit(nil);
    FAdapter.Pump(PC_TEST_DBG_WAIT_MS div 10);
    DoDapCollect(FOutput, FRead, FMessages);
  end;
end;

function TPCDapClient.OutputText(const ACategory: string): string;
var
  LItem: TJSON;
begin
  Result := '';
  for LItem in FMessages do
    if (DoJsonText(LItem, 'event') = 'output') and (DoJsonText(LItem, 'body.category') = ACategory) then
      Result := Result + DoJsonText(LItem, 'body.output');
end;

{ DoDapTopFrame }
// The stopped thread's top frame: its id, routine and line
function DoDapTopFrame(const AClient: TPCDapClient; const AThreadId: Integer; out AName: string;
  out ALine: Integer): Integer;
var
  LResponse: TJSON;
begin
  LResponse := AClient.Request('stackTrace', DoDapIntArgs('threadId', AThreadId));
  AName := DoJsonText(LResponse, 'body.stackFrames[0].name');
  ALine := DoJsonInt(LResponse, 'body.stackFrames[0].line');
  Result := DoJsonInt(LResponse, 'body.stackFrames[0].id');
end;

{ DoDapScopeRef }
// The variables reference of AFrameId's scope named AScope (0 = none)
function DoDapScopeRef(const AClient: TPCDapClient; const AFrameId: Integer; const AScope: string): Integer;
var
  LResponse: TJSON;
  LScopes: TJSON;
  LItem: TJSON;
begin
  Result := 0;
  LResponse := AClient.Request('scopes', DoDapIntArgs('frameId', AFrameId));
  if (LResponse <> nil) and LResponse.TryGetArray('body.scopes', LScopes) then
    for LItem in LScopes.Items() do
      if DoJsonText(LItem, 'name') = AScope then
        Exit(DoJsonInt(LItem, 'variablesReference'));
end;

{ DoDapVariables }
// 'name: type = value; ...' of a variables reference (a failure's label too)
function DoDapVariables(const AClient: TPCDapClient; const AReference: Integer): string;
var
  LResponse: TJSON;
  LItems: TJSON;
  LItem: TJSON;
begin
  Result := '';
  LResponse := AClient.Request('variables', DoDapIntArgs('variablesReference', AReference));
  if (LResponse <> nil) and LResponse.TryGetArray('body.variables', LItems) then
    for LItem in LItems.Items() do
      Result := Result + DoJsonText(LItem, 'name') + ': ' + DoJsonText(LItem, 'type') + ' = ' +
        DoJsonText(LItem, 'value') + '; ';
  Result := Result.Trim();
end;

{ DoDapStep }
// A run-control request, then its stop; the stopped event's reason ('' = none came)
function DoDapStep(const AClient: TPCDapClient; const ACommand: string; const AThreadId: Integer): string;
var
  LEvent: TJSON;
begin
  AClient.Request(ACommand, DoDapIntArgs('threadId', AThreadId));
  LEvent := AClient.WaitEvent('stopped', PC_TEST_DBG_SESSION_MS);
  Result := DoJsonText(LEvent, 'body.reason');
end;

procedure TPCDebugTests.DoTestDapSession();
var
  LClient: TPCDapClient;
  LMain: string;
  LUnit: string;
  LOut: string;
  LArgs: TJSONObject;
  LResponse: TJSON;
  LEvent: TJSON;
  LThread: Integer;
  LFrame: Integer;
  LName: string;
  LLine: Integer;
  LGlobals: Integer;
  LReason: string;
  LCall: Integer;
  LHead: Integer;
  LVar: Integer;
  LBody: Integer;
  LTriple: Integer;
  LPrint: Integer;
  LURet: Integer;
begin
  // A whole DAP session over dbg_repl as the editor runs one: launch builds
  // the .pcpp debug, the program's @breakpoint lines come as new
  // breakpoints (moved forward to their code), a client breakpoint, step in
  // / over / out, scopes and variables in PaskalCPP names, evaluate,
  // references die at a resume, a request that needs a stop while it runs,
  // the program's output, its exit, disconnect
  LMain := DoFixturePath('repl');
  LUnit := TPath.Combine(TPath.GetDirectoryName(LMain), 'dbg_repl_u.pcpp');
  LCall := DoMarkerLine('repl', 'M_CALL');
  LHead := DoMarkerLine('repl', 'M_ADD_HEAD');
  LVar := DoMarkerLine('repl', 'M_ADD_VAR');
  LBody := DoMarkerLine('repl', 'M_ADD_BODY');
  LTriple := DoMarkerLine('repl', 'M_TRIPLE');
  LPrint := DoMarkerLine('repl', 'M_PRINT');
  LURet := DoMarkerLineIn(LUnit, 'M_U_RETURN');
  LOut := TPath.Combine(TPath.Combine(TPath.GetTempPath(), 'pcpp-dbg'), 'dap');
  LClient := TPCDapClient.Create();
  try
    LResponse := LClient.Request('initialize', DoDapArgs(['adapterID', 'pcpp']));
    Check(DoJsonFlag(LResponse, 'success') and DoJsonFlag(LResponse, 'body.supportsConfigurationDoneRequest') and
      DoJsonFlag(LResponse, 'body.supportsEvaluateForHovers') and
      (not DoJsonFlag(LResponse, 'body.supportsConditionalBreakpoints')) and
      (DoJsonText(LResponse, 'body.exceptionBreakpointFilters[0].filter') = PC_DAP_FILTER_ALL),
      'dap_session: initialize answers the capabilities');
    LResponse := LClient.Request('stackTrace', DoDapIntArgs('threadId', 1));
    Check((not DoJsonFlag(LResponse, 'success')) and (DoJsonText(LResponse, 'message') = RSDbgDapNotLaunched),
      'dap_session: a stack trace before launch says no program');
    LResponse := LClient.Request('pcppTerminalInput', DoDapArgs(['text', 'x']));
    Check((not DoJsonFlag(LResponse, 'success')) and (DoJsonText(LResponse, 'message') = RSDbgDapNotLaunched),
      'dap_session: terminal input before launch says no program');

    LArgs := DoDapArgs(['program', LMain, 'outputPath', LOut]);
    LResponse := LClient.Request('launch', LArgs);
    Check(DoJsonFlag(LResponse, 'success'), 'dap_session: launch builds and starts (%s)',
      [DoJsonText(LResponse, 'message')]);
    if not DoJsonFlag(LResponse, 'success') then
      Exit;
    Check(LClient.OutputText('console') <> '', 'dap_session: the build''s status goes out as console output');
    Check(LClient.WaitEvent('initialized', 0) <> nil, 'dap_session: initialized after launch');

    // The program's terminal (held at its entry): the pane's size and keys
    LArgs := DoDapIntArgs('cols', 100);
    LArgs.AddPair('rows', TJSONNumber.Create(30));
    LResponse := LClient.Request('pcppTerminalResize', LArgs);
    Check(DoJsonFlag(LResponse, 'success'), 'dap_session: pcppTerminalResize (%s)', [DoJsonText(LResponse, 'message')]);
    LResponse := LClient.Request('pcppTerminalResize', DoDapIntArgs('cols', 0));
    Check((not DoJsonFlag(LResponse, 'success')) and
      (DoJsonText(LResponse, 'message') = Format(RSDbgDapBadArgument, ['pcppTerminalResize', 'cols'])),
      'dap_session: pcppTerminalResize with no width says which argument');
    LResponse := LClient.Request('pcppTerminalInput', DoDapArgs(['text', '']));
    Check(DoJsonFlag(LResponse, 'success'), 'dap_session: pcppTerminalInput (%s)', [DoJsonText(LResponse, 'message')]);
    LResponse := LClient.Request('pcppTerminalInput', nil);
    Check((not DoJsonFlag(LResponse, 'success')) and
      (DoJsonText(LResponse, 'message') = Format(RSDbgDapBadArgument, ['pcppTerminalInput', 'text'])),
      'dap_session: pcppTerminalInput with no text says which argument');

    LResponse := LClient.Request('setBreakpoints', DoDapBreakpointArgs(LMain, [LPrint]));
    Check(DoJsonFlag(LResponse, 'success') and DoJsonFlag(LResponse, 'body.breakpoints[0].verified') and
      (DoJsonInt(LResponse, 'body.breakpoints[0].line') = LPrint) and
      (DoJsonInt(LResponse, 'body.breakpoints[0].id') > 0),
      'dap_session: the client''s breakpoint is verified at its line');
    LEvent := LClient.WaitEvent('breakpoint', 0);
    Check((DoJsonText(LEvent, 'body.reason') = 'new') and DoJsonFlag(LEvent, 'body.breakpoint.verified') and
      (DoJsonInt(LEvent, 'body.breakpoint.line') = LCall) and
      TUtils.SamePath(DoJsonText(LEvent, 'body.breakpoint.source.path'), LMain),
      'dap_session: the main @breakpoint comes as new, at its code line %d (%d)',
      [LCall, DoJsonInt(LEvent, 'body.breakpoint.line')]);
    LResponse := LClient.Request('setExceptionBreakpoints', nil);
    Check(DoJsonFlag(LResponse, 'success'), 'dap_session: setExceptionBreakpoints');
    LResponse := LClient.Request('configurationDone', nil);
    Check(DoJsonFlag(LResponse, 'success'), 'dap_session: configurationDone');
    LEvent := LClient.WaitEvent('breakpoint', 0);
    Check((DoJsonText(LEvent, 'body.reason') = 'new') and (DoJsonInt(LEvent, 'body.breakpoint.line') = LURet) and
      (DoJsonText(LEvent, 'body.breakpoint.source.name') = 'dbg_repl_u.pcpp'),
      'dap_session: the unit''s @breakpoint (a file the client set nothing in) comes as new at %d', [LURet]);

    LEvent := LClient.WaitEvent('stopped', PC_TEST_DBG_SESSION_MS);
    Check(DoJsonText(LEvent, 'body.reason') = 'breakpoint', 'dap_session: stops at the @breakpoint');
    LThread := DoJsonInt(LEvent, 'body.threadId');
    LResponse := LClient.Request('threads', nil);
    Check(DoJsonFlag(LResponse, 'success') and (DoJsonInt(LResponse, 'body.threads[0].id') > 0),
      'dap_session: threads lists the program''s');
    LFrame := DoDapTopFrame(LClient, LThread, LName, LLine);
    Check((LName = 'dbg_repl') and (LLine = LCall), 'dap_session: the top frame is dbg_repl at %d (%s:%d)',
      [LCall, LName, LLine]);
    // The module body: no parameters, and no locals (it declares none and
    // holds no verbatim C++ local): only Globals
    LGlobals := DoDapScopeRef(LClient, LFrame, RSDbgDapScopeGlobals);
    Check((LGlobals > 0) and (DoDapScopeRef(LClient, LFrame, RSDbgDapScopeParams) = 0) and
      (DoDapScopeRef(LClient, LFrame, RSDbgDapScopeLocals) = 0), 'dap_session: the module body has Globals only');
    Check(DoDapVariables(LClient, LGlobals).Contains('GTotal: int32 = 0;'),
      'dap_session: Globals shows GTotal with its PaskalCPP type (%s)', [DoDapVariables(LClient, LGlobals)]);

    // stepIn stops past Add's prologue (its var line, not the header): the
    // params are already stored there (e5b)
    LReason := DoDapStep(LClient, 'stepIn', LThread);
    LFrame := DoDapTopFrame(LClient, LThread, LName, LLine);
    Check((LReason = 'step') and (LName = 'Add') and (LLine = LVar) and (LLine <> LHead),
      'dap_session: stepIn enters Add past its prologue at %d (%s %s:%d)', [LVar, LReason, LName, LLine]);
    LResponse := LClient.Request('variables', DoDapIntArgs('variablesReference', LGlobals));
    Check((not DoJsonFlag(LResponse, 'success')) and
      (DoJsonText(LResponse, 'message') = Format(RSDbgDapBadReference, [LGlobals])),
      'dap_session: a reference from before the resume is gone');
    // After the check above: each scopes request mints new references
    Check((DoDapScopeRef(LClient, LFrame, RSDbgDapScopeParams) > 0) and
      (DoDapScopeRef(LClient, LFrame, RSDbgDapScopeLocals) > 0) and
      (DoDapScopeRef(LClient, LFrame, RSDbgDapScopeGlobals) > 0), 'dap_session: a routine has its three scopes');
    Check(DoDapVariables(LClient, DoDapScopeRef(LClient, LFrame, RSDbgDapScopeParams)) =
      'AA: int32 = 2; AB: int32 = 3;', 'dap_session: Parameters at the stepIn stop (%s)',
      [DoDapVariables(LClient, DoDapScopeRef(LClient, LFrame, RSDbgDapScopeParams))]);

    LReason := DoDapStep(LClient, 'next', LThread);
    LFrame := DoDapTopFrame(LClient, LThread, LName, LLine);
    Check((LReason = 'step') and (LName = 'Add') and (LLine = LBody),
      'dap_session: next stops on the body line %d (%s:%d)', [LBody, LName, LLine]);
    LArgs := DoDapArgs(['expression', 'AA', 'context', 'hover']);
    LArgs.AddPair('frameId', TJSONNumber.Create(LFrame));
    LResponse := LClient.Request('evaluate', LArgs);
    Check(DoJsonFlag(LResponse, 'success') and (DoJsonText(LResponse, 'body.result') = '2') and
      (DoJsonText(LResponse, 'body.type') = 'int32'), 'dap_session: evaluate AA (hover)');
    LResponse := LClient.Request('evaluate', DoDapArgs(['expression', 'AA + 1', 'context', 'watch']));
    Check((not DoJsonFlag(LResponse, 'success')) and
      (DoJsonText(LResponse, 'message') = Format(RSDbgEvalUnsupported, ['AA + 1'])),
      'dap_session: evaluate of an expression (no frame: the top one) says why not');
    LResponse := LClient.Request('variables', DoDapIntArgs('variablesReference', 999));
    Check((not DoJsonFlag(LResponse, 'success')) and
      (DoJsonText(LResponse, 'message') = Format(RSDbgDapBadReference, [999])),
      'dap_session: an unknown reference');

    LReason := DoDapStep(LClient, 'stepOut', LThread);
    DoDapTopFrame(LClient, LThread, LName, LLine);
    Check((LReason = 'step') and (LLine = LTriple), 'dap_session: stepOut returns to the caller''s next line %d (%d)',
      [LTriple, LLine]);
    LResponse := LClient.Request('continue', DoDapIntArgs('threadId', LThread));
    Check(DoJsonFlag(LResponse, 'success') and DoJsonFlag(LResponse, 'body.allThreadsContinued'),
      'dap_session: continue');
    LEvent := LClient.WaitEvent('stopped', PC_TEST_DBG_SESSION_MS);
    DoDapTopFrame(LClient, LThread, LName, LLine);
    Check((DoJsonText(LEvent, 'body.reason') = 'breakpoint') and (LName = 'Triple') and (LLine = LURet),
      'dap_session: stops at the unit''s @breakpoint in Triple (%s:%d)', [LName, LLine]);
    LReason := DoDapStep(LClient, 'continue', LThread);
    DoDapTopFrame(LClient, LThread, LName, LLine);
    Check((LReason = 'breakpoint') and (LLine = LPrint), 'dap_session: stops at the client''s breakpoint %d (%d)',
      [LPrint, LLine]);

    LClient.Request('continue', DoDapIntArgs('threadId', LThread));
    LResponse := LClient.Request('stackTrace', DoDapIntArgs('threadId', LThread));
    Check((not DoJsonFlag(LResponse, 'success')) and (DoJsonText(LResponse, 'message') = RSDbgRunning),
      'dap_session: a stack trace while the program runs needs a stop');
    LEvent := LClient.WaitEvent('exited', PC_TEST_DBG_SESSION_MS);
    Check((LEvent <> nil) and (DoJsonInt(LEvent, 'body.exitCode') = 0), 'dap_session: the program exits 0');
    Check(LClient.WaitEvent('terminated', PC_TEST_DBG_WAIT_MS) <> nil, 'dap_session: terminated follows');
    Check(LClient.OutputText('stdout').Contains('total 15'), 'dap_session: the program''s output (%s)',
      [DoShow(LClient.OutputText('stdout'))]);

    LResponse := LClient.Request('foo', nil);
    Check((not DoJsonFlag(LResponse, 'success')) and
      (DoJsonText(LResponse, 'message') = Format(RSDbgDapUnknownCommand, ['foo'])), 'dap_session: an unknown request');
    LResponse := LClient.Request('disconnect', nil);
    Check(DoJsonFlag(LResponse, 'success') and LClient.Adapter.IsFinished(), 'dap_session: disconnect ends the session');
  finally
    LClient.Free();
  end;
end;

procedure TPCDebugTests.DoTestDapLaunchFailure();
var
  LClient: TPCDapClient;
  LMissing: string;
  LResponse: TJSON;
  LThreads: TJSON;
  LArgs: TJSONObject;
begin
  // A launch that cannot start says why in its response, and the session
  // goes on; requests that need a program say there is none
  LMissing := TPath.Combine(TPath.Combine(TPath.GetTempPath(), 'pcpp-dbg'), 'no_such_dap.exe');
  LClient := TPCDapClient.Create();
  try
    LResponse := LClient.Request('launch', nil);
    Check((not DoJsonFlag(LResponse, 'success')) and (DoJsonText(LResponse, 'message') = RSDbgDapNoProgram),
      'dap_launch_fail: no program (%s)', [DoJsonText(LResponse, 'message')]);
    Check(DoJsonInt(LResponse, 'body.error.id') = -1, 'dap_launch_fail: a failure no client acts on has no body.error');
    LResponse := LClient.Request('launch', DoDapArgs(['program', LMissing]));
    Check((not DoJsonFlag(LResponse, 'success')) and
      DoJsonText(LResponse, 'message').StartsWith(Format(RSDbgProgramNotFound, [''])),
      'dap_launch_fail: a missing exe (%s)', [DoJsonText(LResponse, 'message')]);
    LArgs := DoDapArgs(['program', LMissing]);
    LArgs.AddPair('terminalRows', TJSONNumber.Create(0));
    LResponse := LClient.Request('launch', LArgs);
    Check((not DoJsonFlag(LResponse, 'success')) and
      (DoJsonText(LResponse, 'message') = Format(RSDbgDapBadArgument, ['launch', 'terminalRows'])),
      'dap_launch_fail: a terminal of no rows (%s)', [DoJsonText(LResponse, 'message')]);
    LResponse := LClient.Request('launch', DoDapArgs(['program', ChangeFileExt(LMissing, '.dll')]));
    Check((not DoJsonFlag(LResponse, 'success')) and (DoJsonText(LResponse, 'message') = RSDbgDapDllNoHost),
      'dap_launch_fail: a dll without host');
    // The editor asks for the host on this id (DAP Message: id + format)
    Check((DoJsonInt(LResponse, 'body.error.id') = PC_DAP_ERROR_DLL_NO_HOST) and
      (DoJsonText(LResponse, 'body.error.format') = RSDbgDapDllNoHost),
      'dap_launch_fail: a dll without host carries body.error id %d (%d)',
      [PC_DAP_ERROR_DLL_NO_HOST, DoJsonInt(LResponse, 'body.error.id')]);
    LResponse := LClient.Request('launch', DoDapArgs(['program', DoFixturePath('lib')]));
    Check((not DoJsonFlag(LResponse, 'success')) and (DoJsonText(LResponse, 'message') = RSDbgDapDllNoHost) and
      (DoJsonInt(LResponse, 'body.error.id') = PC_DAP_ERROR_DLL_NO_HOST),
      'dap_launch_fail: a .pcpp dll without host: refused before the build, same id (%s / %d)',
      [DoJsonText(LResponse, 'message'), DoJsonInt(LResponse, 'body.error.id')]);
    LResponse := LClient.Request('launch', DoDapArgs(['program', LMissing, 'host', LMissing]));
    Check((not DoJsonFlag(LResponse, 'success')) and (DoJsonText(LResponse, 'message') = RSDbgDapHostOnExe),
      'dap_launch_fail: host on an exe');
    // The editor forgets a remembered host on this id
    Check(DoJsonInt(LResponse, 'body.error.id') = PC_DAP_ERROR_HOST_ON_EXE,
      'dap_launch_fail: host on an exe carries body.error id %d (%d)',
      [PC_DAP_ERROR_HOST_ON_EXE, DoJsonInt(LResponse, 'body.error.id')]);
    LResponse := LClient.Request('launch', DoDapArgs(['program', DoFixturePath('repl'), 'host', LMissing]));
    Check((not DoJsonFlag(LResponse, 'success')) and (DoJsonText(LResponse, 'message') = RSDbgDapHostOnExe) and
      (DoJsonInt(LResponse, 'body.error.id') = PC_DAP_ERROR_HOST_ON_EXE),
      'dap_launch_fail: host on a .pcpp exe: refused before the build, same id (%s / %d)',
      [DoJsonText(LResponse, 'message'), DoJsonInt(LResponse, 'body.error.id')]);
    LArgs := DoDapArgs(['program', LMissing, 'args', 'not an array']);
    LResponse := LClient.Request('launch', LArgs);
    Check((not DoJsonFlag(LResponse, 'success')) and
      (DoJsonText(LResponse, 'message') = Format(RSDbgDapBadArgument, ['launch', 'args'])),
      'dap_launch_fail: args that is no array');
    LResponse := LClient.Request('configurationDone', nil);
    Check((not DoJsonFlag(LResponse, 'success')) and (DoJsonText(LResponse, 'message') = RSDbgDapNotLaunched),
      'dap_launch_fail: configurationDone with no program');
    LResponse := LClient.Request('threads', nil);
    Check(DoJsonFlag(LResponse, 'success') and LResponse.TryGetArray('body.threads', LThreads) and
      (LThreads.Count() = 0), 'dap_launch_fail: threads with no program: none');
    // A "breakpoints" value that is no list is a bad argument: it must not
    // read as an empty list and clear the file's set
    LArgs := DoDapBreakpointArgs(LMissing, [3]);
    LArgs.RemovePair('breakpoints').Free();
    LArgs.AddPair('breakpoints', 'not a list');
    LResponse := LClient.Request('setBreakpoints', LArgs);
    Check((not DoJsonFlag(LResponse, 'success')) and
      (DoJsonText(LResponse, 'message') = Format(RSDbgDapBadArgument, ['setBreakpoints', 'breakpoints'])),
      'dap_launch_fail: setBreakpoints with breakpoints that is no list (%s)',
      [DoJsonText(LResponse, 'message')]);
    // "filters" likewise: a list of names, anything else fails
    LResponse := LClient.Request('setExceptionBreakpoints', DoDapArgs(['filters', 'all']));
    Check((not DoJsonFlag(LResponse, 'success')) and
      (DoJsonText(LResponse, 'message') = Format(RSDbgDapBadArgument, ['setExceptionBreakpoints', 'filters'])),
      'dap_launch_fail: setExceptionBreakpoints with filters that is no list (%s)',
      [DoJsonText(LResponse, 'message')]);
    LArgs := TJSONObject.Create();
    LArgs.AddPair('filters', TJSONArray.Create(TJSONNumber.Create(1)));
    LResponse := LClient.Request('setExceptionBreakpoints', LArgs);
    Check((not DoJsonFlag(LResponse, 'success')) and
      (DoJsonText(LResponse, 'message') = Format(RSDbgDapBadArgument, ['setExceptionBreakpoints', 'filters'])),
      'dap_launch_fail: setExceptionBreakpoints with a filter that is no name (%s)',
      [DoJsonText(LResponse, 'message')]);
    LResponse := LClient.Request('setExceptionBreakpoints', DoDapArgs([]));
    Check(DoJsonFlag(LResponse, 'success'), 'dap_launch_fail: setExceptionBreakpoints without filters');
    LClient.Adapter.HandleMessage('{"seq":99,"type":"event","event":"x"}');
    Check(LClient.Request('threads', nil) <> nil, 'dap_launch_fail: a message that is no request is skipped');
    Check(LClient.OutputText('stderr').Contains(RSDbgDapNotRequest),
      'dap_launch_fail: ... and said on stderr');
  finally
    LClient.Free();
  end;
end;

procedure TPCDebugTests.DoTestDapTransport();
var
  LInput: TMemoryStream;
  LOutput: TMemoryStream;
  LTransport: TPCLspTransport;
  LAdapter: TPCDebugDAP;
  LMessages: TObjectList<TJSON>;
  LRead: Int64;
  LBytes: TBytes;
  LCode: Integer;
  LRound: Integer;
begin
  // Run over a stream pair: the framing, the reader thread, the exit code
  // (disconnect = 0; the input ending first = the client is gone)
  for LRound := 0 to 1 do
  begin
    LInput := TMemoryStream.Create();
    LOutput := TMemoryStream.Create();
    LTransport := TPCLspTransport.Create();
    LAdapter := TPCDebugDAP.Create();
    LMessages := TObjectList<TJSON>.Create(True);
    try
      LBytes := DoDapFrame('{"seq":1,"type":"request","command":"initialize","arguments":{}}');
      LInput.WriteBuffer(LBytes[0], Length(LBytes));
      if LRound = 0 then
      begin
        LBytes := DoDapFrame('{"seq":2,"type":"request","command":"disconnect"}');
        LInput.WriteBuffer(LBytes[0], Length(LBytes));
      end;
      LInput.Position := 0;
      LTransport.Init(LInput, LOutput);
      LCode := LAdapter.Run(LTransport);
      LRead := 0;
      DoDapCollect(LOutput, LRead, LMessages);
      if LRound = 0 then
      begin
        Check(LCode = PC_DAP_EXIT_DISCONNECTED, 'dap_transport: disconnect = exit %d (%d)',
          [PC_DAP_EXIT_DISCONNECTED, LCode]);
        Check((LMessages.Count = 2) and (DoJsonInt(LMessages[0], 'request_seq') = 1) and
          DoJsonFlag(LMessages[0], 'success') and (DoJsonInt(LMessages[1], 'request_seq') = 2) and
          (DoJsonText(LMessages[1], 'command') = 'disconnect') and
          (DoJsonInt(LMessages[0], 'seq') = 1) and (DoJsonInt(LMessages[1], 'seq') = 2),
          'dap_transport: two framed responses, in order, seq counted (%d)', [LMessages.Count]);
      end
      else
      begin
        Check(LCode = PC_DAP_EXIT_CLIENT_GONE, 'dap_transport: the input ended first = exit %d (%d)',
          [PC_DAP_EXIT_CLIENT_GONE, LCode]);
        Check((LMessages.Count = 1) and DoJsonFlag(LMessages[0], 'success'),
          'dap_transport: the request before the end is answered (%d)', [LMessages.Count]);
      end;
    finally
      LMessages.Free();
      LAdapter.Free();
      LTransport.Free();
      LOutput.Free();
      LInput.Free();
    end;
  end;
end;

end.
