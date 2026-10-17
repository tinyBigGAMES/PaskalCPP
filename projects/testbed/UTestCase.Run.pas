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
  UTestCase.Run - emitted programs built with the real runtime and run

  TTestCase suite for PLAN-RUNTIME V2: every fixture under tests\probe\run\
  (written by scripts\zb_rt\gen_run.py, never an editor) is analyzed and
  emitted by the real frontend (UTestFrontend.DoWithEmit, TPCEmitter
  WriteFiles), each main module of the case is built in order with the real
  runtime (res\runtime: its folder as an include path, pcpp_runtime.cpp as a
  TU of an exe or dll, never a lib; PCPP_BUILD_DLL for a dll) on both
  official targets, and the last one
  is run over pipes, every line kept (TUtils.RunPE / TUtils.RunElf with
  pipes). Its stdout and stderr, one stream in the
  order written, and its exit code are compared with expected.txt / run.txt. A
  later main links every earlier one (library paths, link library, a dll
  copied beside the program).
  Builds go to %TEMP%\pcpp-run\<case>\<target>\<module>, kept so zig's cache
  makes reruns fast.

  Dependencies: StdApp.TestCase, StdApp.Base, StdApp.Utils, PaskalCPP.AST,
    PaskalCPP.Emitter, PaskalCPP.ZigBuild, UTestFrontend
===============================================================================}

unit UTestCase.Run;

interface

uses
  StdApp.TestCase;

type

  { TPCRunTests }
  TPCRunTests = class(TTestCase)
  private
    // One test per fixture case; Create registers each under its CLI name
    procedure DoTestGuards();
    procedure DoTestRaises();
    procedure DoTestPassOn();
    procedure DoTestUnguarded();
    procedure DoTestUnguardedOverflow();
    procedure DoTestFmtErr();
    procedure DoTestSets();
    procedure DoTestWcharBits();
    procedure DoTestWideText();
    procedure DoTestPrintAll();
    procedure DoTestExported();
    procedure DoTestAsserts();
    procedure DoTestVarargs();
    procedure DoTestTestMode();
    procedure DoTestDllPair();
    procedure DoTestLibPair();
    procedure DoTestHeap();
    procedure DoTestRecExt();
    procedure DoTestMisalign();
    procedure DoTestSetAssign();
    procedure DoTestOverlayZero();
    procedure DoTestDispatch();
    procedure DoTestLifecycle();
    procedure DoTestValues();
    procedure DoTestOwners();
    procedure DoTestCreates();

    // tests\probe\run\<ACase>: built and run on every official target
    procedure DoRunCase(const ACase: string);
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  StdApp.Base,
  StdApp.Utils,
  PaskalCPP.AST,
  PaskalCPP.Emitter,
  PaskalCPP.ZigBuild,
  UTestFrontend;

const
  { PC_TEST_RUN_TARGETS }
  // The official targets (DESIGN sec 7)
  PC_TEST_RUN_TARGETS: array[0..1] of string = ('x86_64-windows-gnu', 'x86_64-linux-gnu');

type

  { TPCRunPlan }
  // A case's run.txt: the mains in build order, the run's command line,
  // the defines of every build and the expected exit code
  TPCRunPlan = record
    Mains: TArray<string>;
    Args: string;
    Defines: TArray<string>;
    ExitCode: Cardinal;
  end;

  { TPCRunBuilt }
  // One main module built for a target: what a later main links
  TPCRunBuilt = record
    ModuleName: string;
    Kind: TPCModuleKind;
    BinDir: string;
    LibDir: string;
    FileName: string;
  end;

function DoReadPlan(const ADir: string; out APlan: TPCRunPlan; out AReason: string): Boolean;
var
  LLines: TArray<string>;
  LLine: string;
  LText: string;
begin
  APlan := Default(TPCRunPlan);
  AReason := '';
  try
    LLines := TFile.ReadAllLines(TPath.Combine(ADir, 'run.txt'), TEncoding.UTF8);
  except
    on E: Exception do
    begin
      AReason := E.Message;
      Exit(False);
    end;
  end;
  for LLine in LLines do
  begin
    LText := LLine.Trim();
    if LText.StartsWith('main ') then
      APlan.Mains := APlan.Mains + [LText.Substring(5).Trim()]
    else if LText.StartsWith('args ') then
      APlan.Args := LText.Substring(5).Trim()
    else if LText.StartsWith('define ') then
      APlan.Defines := APlan.Defines + [LText.Substring(7).Trim()]
    else if LText.StartsWith('exit ') then
      APlan.ExitCode := StrToUIntDef(LText.Substring(5).Trim(), 4242)
    else if LText <> '' then
    begin
      AReason := 'unknown run.txt line: ' + LText;
      Exit(False);
    end;
  end;
  Result := Length(APlan.Mains) > 0;
  if not Result then
    AReason := 'run.txt names no main module';
end;

function DoExpectedText(const ADir: string; const APlan: TPCRunPlan; out AText: string): Boolean;
var
  LFile: string;
  LName: string;
begin
  // expected.txt with <SRC:name> = that module file's path as the parser
  // resolves it, '/' slashes (as UTestCase.Emitter's <SRC>)
  try
    AText := TEncoding.UTF8.GetString(TFile.ReadAllBytes(TPath.Combine(ADir, 'expected.txt')));
  except
    on E: Exception do
    begin
      AText := '<cannot read expected.txt: ' + E.Message + '>';
      Exit(False);
    end;
  end;
  AText := AText.Replace(#13#10, #10);
  for LFile in TDirectory.GetFiles(ADir, '*.pcpp') do
  begin
    LName := TPath.GetFileNameWithoutExtension(LFile);
    AText := AText.Replace('<SRC:' + LName + '>', TUtils.ResolvePath(LFile).Replace('\', '/'));
  end;
  Result := True;
end;

function DoBuildMode(const AKind: TPCModuleKind): TPCBuildMode;
begin
  if AKind = mkDll then
    Result := bmDll
  else if AKind = mkLib then
    Result := bmLib
  else
    Result := bmExe;
end;

{ TPCRunTests }

constructor TPCRunTests.Create();
begin
  inherited;

  Title := 'Run';
  RegisterTest('guards', DoTestGuards);
  RegisterTest('raises', DoTestRaises);
  RegisterTest('passon', DoTestPassOn);
  RegisterTest('unguarded', DoTestUnguarded);
  RegisterTest('unguardedso', DoTestUnguardedOverflow);
  RegisterTest('fmterr', DoTestFmtErr);
  RegisterTest('sets', DoTestSets);
  RegisterTest('wcharbits', DoTestWcharBits);
  RegisterTest('widetext', DoTestWideText);
  RegisterTest('printall', DoTestPrintAll);
  RegisterTest('exported', DoTestExported);
  RegisterTest('asserts', DoTestAsserts);
  RegisterTest('varargs', DoTestVarargs);
  RegisterTest('testmode', DoTestTestMode);
  RegisterTest('dllpair', DoTestDllPair);
  RegisterTest('libpair', DoTestLibPair);
  RegisterTest('heap', DoTestHeap);
  RegisterTest('recext', DoTestRecExt);
  RegisterTest('misalign', DoTestMisalign);
  RegisterTest('setassign', DoTestSetAssign);
  RegisterTest('ovzero', DoTestOverlayZero);
  RegisterTest('dispatch', DoTestDispatch);
  RegisterTest('lifecycle', DoTestLifecycle);
  RegisterTest('values', DoTestValues);
  RegisterTest('owners', DoTestOwners);
  RegisterTest('creates', DoTestCreates);
end;

procedure TPCRunTests.Run();
begin
  inherited;
end;

procedure TPCRunTests.DoTestGuards();
begin
  DoRunCase('guards');
end;

procedure TPCRunTests.DoTestRaises();
begin
  DoRunCase('raises');
end;

procedure TPCRunTests.DoTestPassOn();
begin
  DoRunCase('passon');
end;

procedure TPCRunTests.DoTestUnguarded();
begin
  DoRunCase('unguarded');
end;

procedure TPCRunTests.DoTestUnguardedOverflow();
begin
  DoRunCase('unguardedso');
end;

procedure TPCRunTests.DoTestFmtErr();
begin
  DoRunCase('fmterr');
end;

procedure TPCRunTests.DoTestSets();
begin
  DoRunCase('sets');
end;

procedure TPCRunTests.DoTestWcharBits();
begin
  // F25: a wchar bitfield holds 0 .. 2^w - 1 on every target
  DoRunCase('wcharbits');
end;

procedure TPCRunTests.DoTestWideText();
begin
  // PLAN-PASKAL-ERRORS E4: print / println of wide text is UTF-8 on every target
  DoRunCase('widetext');
end;

procedure TPCRunTests.DoTestPrintAll();
begin
  // PLAN-PASKAL-ERRORS E7: typed pointers, routine values and arrays print
  // by their type's form (a nil ptr to char element used to crash)
  DoRunCase('printall');
end;

procedure TPCRunTests.DoTestExported();
begin
  // F22: a unit's exported sections name private consts; the exe uses them
  DoRunCase('exported');
end;

procedure TPCRunTests.DoTestAsserts();
begin
  DoRunCase('asserts');
end;

procedure TPCRunTests.DoTestVarargs();
begin
  DoRunCase('varargs');
end;

procedure TPCRunTests.DoTestTestMode();
begin
  DoRunCase('testmode');
end;

procedure TPCRunTests.DoTestDllPair();
begin
  DoRunCase('dllpair');
end;

procedure TPCRunTests.DoTestLibPair();
begin
  DoRunCase('libpair');
end;

procedure TPCRunTests.DoTestHeap();
begin
  DoRunCase('heap');
end;

procedure TPCRunTests.DoTestRecExt();
begin
  // PLAN-RECORDS A6: record extensions with the parent as a member (M10):
  // literals, inherited members, pointer / value / var upcasts, a downcast,
  // ranked overloads, a C/C++ parent, a packed extension
  DoRunCase('recext');
end;

procedure TPCRunTests.DoTestMisalign();
begin
  // PLAN-RECORDS A8 (M8): fields a packed record misaligns reach a const
  // aggregate parameter, print and a const base parameter as copies
  DoRunCase('misalign');
end;

procedure TPCRunTests.DoTestSetAssign();
begin
  // PLAN-RECORDS F-A8c: a set's += -= *= are union / difference /
  // intersection, &= |= C++'s as & | are
  DoRunCase('setassign');
end;

procedure TPCRunTests.DoTestOverlayZero();
begin
  // PLAN-COMPLIANCE F35: an overlay starts zeroed in every byte at every
  // creation site; the zero member moves no size
  DoRunCase('ovzero');
end;

procedure TPCRunTests.DoTestDispatch();
begin
  // PLAN-OBJECT O3 (D7): virtual / override dispatch through an ancestor's
  // pointer and var parameter, plain methods bound statically, final, the
  // root's virtual destructor deleting a descendant
  DoRunCase('dispatch');
end;

procedure TPCRunTests.DoTestLifecycle();
begin
  // PLAN-OBJECT O4 (D3): init / done order (parent, fields, body; reverse
  // at the end), a local before the leading init calls, an init that
  // raises (its field ends, its done never runs), the virtual done deleting
  // a descendant through its root's pointer
  DoRunCase('lifecycle');
end;

procedure TPCRunTests.DoTestValues();
begin
  // PLAN-OBJECT O5 (D5 / D6): a value with a done ends once whatever moves
  // it (a moved return, an assignment from a call result: the old value
  // ends then, a call result passed by value), a copy runs the type's copy
  // (copy-and-swap: the old value ends), values end at scope end in
  // reverse, a plain descendant converts to its base by value
  DoRunCase('values');
end;

procedure TPCRunTests.DoTestOwners();
begin
  // PLAN-OBJECT O6 (D4, Q1-Q3), a debug build: an own frees its object with
  // it (through a polymorphic root: the whole object), a ref with the last
  // ref, a weak watches (alive / lock); a leaked ref cycle names each
  // object's creation site in the leak report; a nil own raises
  DoRunCase('owners');
end;

procedure TPCRunTests.DoTestCreates();
begin
  // PLAN-INTRINSICS I3, a debug build: create / destroy count in the heap
  // report as an owner's objects do (a nil destroy counts nothing), a create
  // never destroyed names its site; a packed record's pointer field takes
  // both (assigned, never bound to a reference)
  DoRunCase('creates');
end;

procedure TPCRunTests.DoRunCase(const ACase: string);
var
  LDir: string;
  LRuntime: string;
  LPlan: TPCRunPlan;
  LReason: string;
  LExpected: string;
  LTarget: string;
  LTargetRoot: string;
  LBuilt: TArray<TPCRunBuilt>;
  LMain: string;
  LIndex: Integer;
  LSrcDir: string;
  LKind: TPCModuleKind;
  LWritten: Boolean;
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LPrior: TPCRunBuilt;
  LThis: TPCRunBuilt;
  LDefine: string;
  LFile: string;
  LOk: Boolean;
  LAllBuilt: Boolean;
  LExePath: string;
  LExitCode: DWORD;
  LOutput: TStringBuilder;
  LGot: string;
  LRaised: string;
begin
  LDir := DoProbeDir('run\' + ACase);
  LRuntime := TUtils.ResolvePath('$P:res\runtime');
  if not DoReadPlan(LDir, LPlan, LReason) then
  begin
    Check(False, ACase + ': run.txt read (' + LReason + ')');
    Exit;
  end;
  if not DoExpectedText(LDir, LPlan, LExpected) then
  begin
    Check(False, ACase + ': ' + LExpected);
    Exit;
  end;

  for LTarget in PC_TEST_RUN_TARGETS do
  begin
    LTargetRoot := TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetTempPath(), 'pcpp-run'), ACase), LTarget);
    LBuilt := nil;
    LAllBuilt := True;
    for LIndex := 0 to High(LPlan.Mains) do
    begin
      LMain := LPlan.Mains[LIndex];
      LSrcDir := TPath.Combine(TPath.Combine(LTargetRoot, LMain), 'src');
      LKind := mkExe;
      LWritten := False;

      // The real frontend: parse, analyze, emit every module of the main's
      // AST into its source folder (the files the build gets)
      DoWithEmit(TPath.Combine(LDir, LMain + '.pcpp'),
        procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors; const AHeader: string;
          const ASource: string)
        var
          LEmitter: TPCEmitter;
        begin
          if AErrors.HasErrors() then
          begin
            Check(False, ACase + ': ' + LMain + ' analyzed (' + DoReports(AErrors) + ')');
            Exit;
          end;
          LKind := AModule.ModuleKind;
          LEmitter := TPCEmitter.Create();
          try
            LEmitter.SetErrors(AErrors);
            LEmitter.Init(AAst, AModule);
            LWritten := LEmitter.WriteFiles(LSrcDir);
          finally
            LEmitter.Free();
          end;
          Check(LWritten, ACase + ': ' + LMain + ' written (' + DoReports(AErrors) + ')');
        end);
      if not LWritten then
      begin
        LAllBuilt := False;
        Break;
      end;

      // The build the Compiler phase will make: the emitted TUs, the runtime
      // TU and folder, PCPP_BUILD_DLL for a dll, the case's defines; every
      // earlier main linked
      LErrors := TErrors.Create();
      LZig := TPCZigBuild.Create();
      try
        LErrors.SetMaxErrors(10);
        LZig.SetErrors(LErrors);
        LZig.SetOutputPath(TPath.Combine(LTargetRoot, LMain));
        LZig.SetProjectName(LMain);
        LZig.SetTarget(LTarget);
        LZig.SetBuildMode(DoBuildMode(LKind));
        LZig.AddIncludePath(LRuntime);
        for LDefine in LPlan.Defines do
          LZig.SetDefine(LDefine);
        if LKind = mkDll then
          LZig.SetDefine('PCPP_BUILD_DLL');
        for LFile in TDirectory.GetFiles(LSrcDir, '*.pcpp.cpp') do
          LZig.AddSourceFile(LFile);
        // A lib carries no runtime: the exe / dll that links it supplies the
        // one copy (user 2026-10-08; api.md Dependencies)
        if LKind <> mkLib then
          LZig.AddSourceFile(TPath.Combine(LRuntime, 'pcpp_runtime.cpp'));
        for LPrior in LBuilt do
        begin
          if TDirectory.Exists(LPrior.LibDir) then
            LZig.AddLibraryPath(LPrior.LibDir);
          if TDirectory.Exists(LPrior.BinDir) then
            LZig.AddLibraryPath(LPrior.BinDir);
          LZig.AddLinkLibrary(LPrior.ModuleName);
          if LPrior.Kind = mkDll then
            LZig.AddCopyDLL(TPath.Combine(LPrior.BinDir, LPrior.FileName));
        end;
        LOk := LZig.Process(False);
        LThis.ModuleName := LMain;
        LThis.Kind := LKind;
        LThis.BinDir := TPath.Combine(TPath.Combine(LTargetRoot, LMain), 'bin');
        LThis.LibDir := TPath.Combine(TPath.Combine(LTargetRoot, LMain), 'lib');
        LThis.FileName := LZig.GetOutputFilename();
        Check(LOk and (LErrors.Count() = 0), Format('%s: %s builds for %s without a report (%s)',
          [ACase, LMain, LTarget, DoReports(LErrors)]));
      finally
        LZig.Free();
        LErrors.Free();
      end;
      if not LOk then
      begin
        LAllBuilt := False;
        Break;
      end;
      LBuilt := LBuilt + [LThis];
    end;
    if not LAllBuilt then
      Continue;

    // The last main runs in its own folder over pipes: stdout and stderr in
    // the order the program wrote them, every line kept (RunPE / RunElf
    // with pipes)
    LThis := LBuilt[High(LBuilt)];
    LExePath := TPath.Combine(LThis.BinDir, LThis.FileName);
    LExitCode := 4242;
    LRaised := '';
    LOutput := TStringBuilder.Create();
    try
      try
        if LTarget.Contains('-linux-') then
          TUtils.RunElf(LExePath, LPlan.Args, LThis.BinDir, LExitCode, nil,
            procedure(const ALine: string; const AData: Pointer)
            begin
              LOutput.Append(ALine).Append(#10);
            end, True)
        else
          TUtils.RunPE(LExePath, LPlan.Args, LThis.BinDir, LExitCode, nil,
            procedure(const ALine: string; const AData: Pointer)
            begin
              LOutput.Append(ALine).Append(#10);
            end, True);
      except
        on E: Exception do
          LRaised := E.Message;
      end;
      LGot := LOutput.ToString();
    finally
      LOutput.Free();
    end;
    Check(LRaised = '', Format('%s: %s runs on %s (%s)', [ACase, LThis.ModuleName, LTarget, LRaised]));
    Check(LExitCode = LPlan.ExitCode, Format('%s on %s exits %d (got %d)%s%s',
      [ACase, LTarget, LPlan.ExitCode, LExitCode, sLineBreak, LGot]));
    Check(LGot = LExpected, Format('%s on %s: output as expected%s--- got%s%s--- want%s%s',
      [ACase, LTarget, sLineBreak, sLineBreak, LGot, sLineBreak, LExpected]));
  end;
end;

end.
