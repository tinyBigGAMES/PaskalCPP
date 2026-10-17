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
  UTestCase.BuildOutput - zig build output filter + commit tests

  TTestCase suite for PaskalCPP.BuildOutput. The filter tests feed REAL zig
  build output (tests\probe\bo\<case>.txt, captured by
  scripts\zb_e\a1b\a1b_capture.py) line by line and compare every capture,
  note and unrecognised line with the text derived from that output. The
  commit tests report into a TErrors: one report per diagnostic, an
  unreadable .dia (ZB0011), clang's stop marker, the location translator,
  frontend-owned warnings, zig's own error lines and the safety net rule
  (a failed build that no reported error explains). reported_long_path: a
  reported path past the plain limit comes back in the plain spelling (R45).

  Dependencies: StdApp.TestCase, StdApp.Base, StdApp.Utils,
    StdApp.Resources, PaskalCPP.BuildOutput
===============================================================================}

unit UTestCase.BuildOutput;

interface

uses
  StdApp.TestCase;

type

  { TPCBuildOutputTests }
  TPCBuildOutputTests = class(TTestCase)
  private
    // Shared checks
    procedure DoCheckFilter(const AName: string; const AWant: string);
    // Commits fixture AName's zig output with its TUs' .dia files
    // (<AName>.a.dia, <AName>.b.dia); returns what was reported
    function DoCommitCase(const AName: string; out AErrorsReported: Integer): string;
    // One test per concern; Create registers each under its CLI name
    procedure DoTestTwoFail();
    procedure DoTestRawDir();
    procedure DoTestRawMacro();
    procedure DoTestErrorLimit();
    procedure DoTestLinkerWin();
    procedure DoTestLinkerLinux();
    procedure DoTestLinkerMacos();
    procedure DoTestAsmFail();
    procedure DoTestAsmUnc();
    procedure DoTestAsmSpelling();
    procedure DoTestAsmPpFail();
    procedure DoTestLlFail();
    procedure DoTestMixedFail();
    procedure DoTestEmpty();
    procedure DoTestReinit();
    procedure DoTestCommitDedupe();
    procedure DoTestCommitUnreadable();
    procedure DoTestCommitStop();
    procedure DoTestCommitTranslate();
    procedure DoTestCommitOwned();
    procedure DoTestCommitGenerated();
    procedure DoTestCommitFrontendCheck();
    procedure DoTestCommitZigError();
    procedure DoTestCommitMissingLib();
    procedure DoTestStepStderr();
    procedure DoTestCommitAsmLl();
    procedure DoTestCommitMultiline();
    procedure DoTestSafetyNet();
    procedure DoTestReportedLongPath();
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.BuildOutput;

const
  { PC_BOT_ROOT }
  // The build root every fixture is read against (zig's relative paths)
  PC_BOT_ROOT = 'C:\bo';

  { PC_BOT_CAP }
  // Where the linker fixtures were built (lld prints absolute source paths)
  PC_BOT_CAP = 'C:/Dev/Delphi/Projects/PaskalCPP/scripts/zb_e/a1b/cap/';

function DoProbePath(const ARelative: string): string;
begin
  // tests\probe\...; the exe sits two levels below the project root
  Result := TUtils.ResolvePath('..\..\tests\probe\' + ARelative,
    TPath.GetDirectoryName(ParamStr(0)));
end;

function DoFeedFixture(const AFilter: TPCBuildOutputFilter;
  const AName: string; out AReason: string): Boolean;
var
  LText: string;
  LLines: TArray<string>;
  LI: Integer;
  LLine: string;
begin
  // The captured bytes as CaptureConsoleOutput hands them over: one line per
  // call, without its terminator
  AReason := '';
  try
    LText := TEncoding.UTF8.GetString(
      TFile.ReadAllBytes(DoProbePath('bo\' + AName + '.txt')));
  except
    on E: Exception do
    begin
      AReason := E.Message;
      Exit(False);
    end;
  end;

  AFilter.Init(PC_BOT_ROOT);
  LLines := LText.Split([#10]);
  for LI := 0 to High(LLines) do
  begin
    LLine := LLines[LI];
    if LLine.EndsWith(#13) then
      LLine := LLine.Substring(0, LLine.Length - 1);
    // The text after the last terminator is no line
    if (LI = High(LLines)) and (LLine = '') then
      Break;
    AFilter.AddLine(LLine);
  end;
  AFilter.Finish();
  Result := True;
end;

procedure DoFeedLines(const AFilter: TPCBuildOutputFilter;
  const ALines: array of string);
var
  LI: Integer;
begin
  AFilter.Init(PC_BOT_ROOT);
  for LI := Low(ALines) to High(ALines) do
    AFilter.AddLine(ALines[LI]);
  AFilter.Finish();
end;

function DoSeverityText(const ASeverity: TErrorSeverity): string;
begin
  if ASeverity = esError then
    Result := 'E'
  else if ASeverity = esWarning then
    Result := 'W'
  else
    Result := '?';
end;

function DoRenderFilter(const AFilter: TPCBuildOutputFilter): string;
var
  LLines: TArray<string>;
  LI: Integer;
  LJ: Integer;
  LDiag: TPCBuildDiag;
begin
  // Captures with their notes, then the unrecognised lines
  LLines := nil;
  for LI := 0 to AFilter.CaptureCount() - 1 do
  begin
    LDiag := AFilter.GetCapture(LI);
    LLines := LLines + [Format('%s %s:%d:%d %s', [DoSeverityText(LDiag.Severity),
      LDiag.Filename, LDiag.Line, LDiag.Column, LDiag.MessageText])];
    for LJ := 0 to High(LDiag.Notes) do
      LLines := LLines + [Format('  N %s:%d:%d %s', [LDiag.Notes[LJ].Filename,
        LDiag.Notes[LJ].Line, LDiag.Notes[LJ].Column, LDiag.Notes[LJ].MessageText])];
  end;
  for LI := 0 to AFilter.UnknownCount() - 1 do
    LLines := LLines + ['U ' + AFilter.GetUnknown(LI)];
  Result := string.Join(sLineBreak, LLines);
end;

function DoRenderErrors(const AErrors: TErrors): string;
var
  LLines: TArray<string>;
  LItem: TError;
  LJ: Integer;
begin
  // Every reported item with its related notes
  LLines := nil;
  for LItem in AErrors.GetItems() do
  begin
    LLines := LLines + [Format('%s %s %s:%d:%d %s', [DoSeverityText(LItem.Severity),
      LItem.Code, LItem.Range.Filename, LItem.Range.StartLine,
      LItem.Range.StartColumn, LItem.Message])];
    for LJ := 0 to High(LItem.Related) do
      LLines := LLines + [Format('  R %s:%d:%d %s', [LItem.Related[LJ].Range.Filename,
        LItem.Related[LJ].Range.StartLine, LItem.Related[LJ].Range.StartColumn,
        LItem.Related[LJ].Msg])];
  end;
  Result := string.Join(sLineBreak, LLines);
end;

constructor TPCBuildOutputTests.Create();
begin
  inherited;

  Title := 'BuildOutput';
  RegisterTest('two_fail', DoTestTwoFail);
  RegisterTest('raw_dir', DoTestRawDir);
  RegisterTest('raw_macro', DoTestRawMacro);
  RegisterTest('error_limit', DoTestErrorLimit);
  RegisterTest('linker_win', DoTestLinkerWin);
  RegisterTest('linker_linux', DoTestLinkerLinux);
  RegisterTest('linker_macos', DoTestLinkerMacos);
  RegisterTest('asm_fail', DoTestAsmFail);
  RegisterTest('asm_unc', DoTestAsmUnc);
  RegisterTest('asm_spelling', DoTestAsmSpelling);
  RegisterTest('asm_pp_fail', DoTestAsmPpFail);
  RegisterTest('ll_fail', DoTestLlFail);
  RegisterTest('mixed_fail', DoTestMixedFail);
  RegisterTest('empty', DoTestEmpty);
  RegisterTest('reinit', DoTestReinit);
  RegisterTest('commit_dedupe', DoTestCommitDedupe);
  RegisterTest('commit_unreadable', DoTestCommitUnreadable);
  RegisterTest('commit_stop', DoTestCommitStop);
  RegisterTest('commit_translate', DoTestCommitTranslate);
  RegisterTest('commit_owned', DoTestCommitOwned);
  RegisterTest('commit_generated', DoTestCommitGenerated);
  RegisterTest('commit_frontend_check', DoTestCommitFrontendCheck);
  RegisterTest('commit_zig_error', DoTestCommitZigError);
  RegisterTest('commit_missing_lib', DoTestCommitMissingLib);
  RegisterTest('step_stderr', DoTestStepStderr);
  RegisterTest('commit_asm_ll', DoTestCommitAsmLl);
  RegisterTest('commit_multiline', DoTestCommitMultiline);
  RegisterTest('safety_net', DoTestSafetyNet);
  RegisterTest('reported_long_path', DoTestReportedLongPath);
end;

procedure TPCBuildOutputTests.Run();
begin
  inherited;
end;

procedure TPCBuildOutputTests.DoCheckFilter(const AName: string;
  const AWant: string);
var
  LFilter: TPCBuildOutputFilter;
  LReason: string;
  LGot: string;
begin
  LFilter := TPCBuildOutputFilter.Create();
  try
    if not DoFeedFixture(LFilter, AName, LReason) then
    begin
      Check(False, '%s: fixture unreadable: %s', [AName, LReason]);
      Exit;
    end;
    LGot := DoRenderFilter(LFilter);
    Check(LGot = AWant, '%s: captures as derived from the fixture' + sLineBreak +
      '--- got' + sLineBreak + '%s' + sLineBreak + '--- want' + sLineBreak + '%s',
      [AName, LGot, AWant]);
  finally
    LFilter.Free();
  end;
end;

function TPCBuildOutputTests.DoCommitCase(const AName: string;
  out AErrorsReported: Integer): string;
var
  LFilter: TPCBuildOutputFilter;
  LCommit: TPCBuildOutputCommit;
  LErrors: TErrors;
  LReason: string;
  LDiagA: string;
  LDiagB: string;
begin
  // An absent .dia reads as a cached TU (nothing to report): the fixtures
  // must exist, or the test would pass on nothing
  Result := '';
  AErrorsReported := -1;
  LDiagA := DoProbePath('bo\' + AName + '.a.dia');
  LDiagB := DoProbePath('bo\' + AName + '.b.dia');
  Check(FileExists(LDiagA) and FileExists(LDiagB), '%s: .dia fixtures exist', [AName]);

  LFilter := TPCBuildOutputFilter.Create();
  LCommit := TPCBuildOutputCommit.Create();
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LCommit.SetErrors(LErrors);
    if not DoFeedFixture(LFilter, AName, LReason) then
    begin
      Check(False, '%s: fixture unreadable: %s', [AName, LReason]);
      Exit;
    end;
    LCommit.Commit(LFilter, [LDiagA, LDiagB], PC_BOT_ROOT, nil, nil, nil, nil);
    Result := DoRenderErrors(LErrors);
    AErrorsReported := LCommit.ErrorsReported();
  finally
    LErrors.Free();
    LCommit.Free();
    LFilter.Free();
  end;
end;

procedure TPCBuildOutputTests.DoTestTwoFail();
begin
  // Two raw blocks: include chain -> notes (column 0), [-W...] tag stripped,
  // 'fatal error' an error; 'clang exited' lines unrecognised
  DoCheckFilter('two_fail', '''
    W C:/bo/leaf.h:2:2 leaf_warn
      N C:/bo/b.cpp:2:0 in file included from .\b.cpp:2:
      N C:/bo/mid.h:3:0 in file included from ./mid.h:3:
    E C:/bo/b.cpp:4:11 expected expression
    W C:/bo/leaf.h:2:2 leaf_warn
      N C:/bo/a.cpp:2:0 in file included from .\a.cpp:2:
      N C:/bo/mid.h:3:0 in file included from ./mid.h:3:
    E C:/bo/a.cpp:4:11 expected expression
    U .\b.cpp:1:1: error: clang exited with code 1
    U .\a.cpp:1:1: error: clang exited with code 1
    ''');
end;

procedure TPCBuildOutputTests.DoTestRawDir();
begin
  // A location-less warning in a.cpp's block keeps its level, no location
  DoCheckFilter('raw_dir', '''
    W C:/bo/h.h:2:2 raw shared
      N C:/bo/b.cpp:2:0 in file included from .\b.cpp:2:
    E C:/bo/h.h:3:16 expected expression
    W C:/bo/h.h:2:2 raw shared
      N C:/bo/a.cpp:2:0 in file included from .\a.cpp:2:
    E C:/bo/h.h:3:16 expected expression
    W :0:0 unable to open file C:/Dev/Delphi/Projects/PaskalCPP/scripts/zb_e/a1b/cap/raw_dir/a.dia for serializing diagnostics (Is a directory)
    U .\b.cpp:1:1: error: clang exited with code 1
    U .\a.cpp:1:1: error: clang exited with code 1
    ''');
end;

procedure TPCBuildOutputTests.DoTestRawMacro();
begin
  // The chain comes first, then clang's own notes; '<scratch space>' kept
  DoCheckFilter('raw_macro', '''
    E C:/bo/h.h:4:1 raw macro
      N C:/bo/a.cpp:2:0 in file included from .\a.cpp:2:
      N C:/bo/h.h:2:18 expanded from macro 'RAW_DIAG'
      N <scratch space>:4:6 expanded from here
    U .\a.cpp:1:1: error: clang exited with code 1
    ''');
end;

procedure TPCBuildOutputTests.DoTestErrorLimit();
begin
  // clang's stop marker under -ferror-limit is not a diagnostic
  DoCheckFilter('elimit', '''
    E C:/bo/a.cpp:3:11 expected expression
    E C:/bo/a.cpp:4:11 expected expression
    U .\a.cpp:1:1: error: clang exited with code 1
    ''');
end;

procedure TPCBuildOutputTests.DoTestLinkerWin();
begin
  // lld-link: 'referenced by <path>:<line>' locates it; the object-file
  // note stays with the error
  DoCheckFilter('linker_win',
    'E ' + PC_BOT_CAP + 'linker_win/a.cpp:5:0 undefined symbol: missing_one()' + sLineBreak +
    'E ' + PC_BOT_CAP + 'linker_win/a.cpp:5:0 undefined symbol: missing_two()');
end;

procedure TPCBuildOutputTests.DoTestLinkerLinux();
begin
  // ld.lld: 'a.cpp:5 (./a.cpp:5)' - located by the parenthesised path (R38b)
  DoCheckFilter('linker_linux', '''
    E C:/bo/a.cpp:5:0 undefined symbol: missing_one()
    E C:/bo/a.cpp:6:0 undefined symbol: missing_two()
    ''');
end;

procedure TPCBuildOutputTests.DoTestLinkerMacos();
begin
  // zig's own linker: no linker name, only object references - an error
  // without a location, never only a safety-net line (R38d)
  DoCheckFilter('linker_macos', '''
    E :0:0 undefined symbol: __Z11missing_onev
    E :0:0 undefined symbol: __Z11missing_twov
    ''');
end;

procedure TPCBuildOutputTests.DoTestAsmFail();
begin
  // 'clang failed with stderr:' block, path spelled '.\\b.S' (R38a)
  DoCheckFilter('asm_fail', '''
    E C:/bo/b.S:3:3 invalid instruction mnemonic 'bogus_instruction'
    U .\b.S:1:1: error: clang exited with code 1
    U   bogus_instruction %rax
    U   ^~~~~~~~~~~~~~~~~
    ''');
end;

procedure TPCBuildOutputTests.DoTestAsmUnc();
var
  LFilter: TPCBuildOutputFilter;
  LWant: string;
  LGot: string;
begin
  // The stderr block doubles every backslash of a path (asm_fail: '.\\b.S').
  // A UNC path is where '\\' cannot be read as one separator by path
  // resolution alone: it is the share prefix.
  LFilter := TPCBuildOutputFilter.Create();
  try
    DoFeedLines(LFilter, [
      'error: error(compilation): clang failed with stderr: \\\\srv\\share\\b.S:3:3: error: x']);
    LWant := ResolveReportedPath('\\srv\share\b.S', PC_BOT_ROOT);
    LGot := '';
    if LFilter.CaptureCount() = 1 then
      LGot := LFilter.GetCapture(0).Filename;
    Check(LGot = LWant, 'asm_unc: the share path "%s" (got "%s")', [LWant, LGot]);
  finally
    LFilter.Free();
  end;
end;

procedure TPCBuildOutputTests.DoTestAsmSpelling();
var
  LFilter: TPCBuildOutputFilter;
  LWant: string;
  LGot: string;
begin
  // One stderr block, two spellings (R38e): a preprocessor line spells its
  // path as is ('\\srv\share\b.S'), an assembler line doubles every
  // backslash. Both name the same file.
  LFilter := TPCBuildOutputFilter.Create();
  try
    DoFeedLines(LFilter, [
      'error: error(compilation): clang failed with stderr: \\srv\share\b.S:2:2: warning: w',
      '       \\\\srv\\share\\b.S:3:3: error: x']);
    LWant := ResolveReportedPath('\\srv\share\b.S', PC_BOT_ROOT);
    LGot := '';
    if LFilter.CaptureCount() = 2 then
      LGot := LFilter.GetCapture(0).Filename + '|' + LFilter.GetCapture(1).Filename;
    Check(LGot = LWant + '|' + LWant, 'asm_spelling: both name "%s" (got "%s")',
      [LWant, LGot]);
  finally
    LFilter.Free();
  end;
end;

procedure TPCBuildOutputTests.DoTestAsmPpFail();
begin
  // A .S preprocessor error: the stderr block spells its path as is
  DoCheckFilter('asm_pp_fail', '''
    E C:/bo/b.S:2:2 pp fail
    U .\b.S:1:1: error: clang exited with code 1
    U     2 | #error pp fail
    U       |  ^
    U 1 error generated.
    ''');
end;

procedure TPCBuildOutputTests.DoTestLlFail();
begin
  // LLVM IR carries our .dia flag (R38c): zig falls back to its raw block;
  // the 'clang exited' line unrecognised
  DoCheckFilter('ll_fail', '''
    E C:/bo/b.ll:3:11 expected value token
    U .\b.ll:1:1: error: clang exited with code 1
    ''');
end;

procedure TPCBuildOutputTests.DoTestMixedFail();
begin
  // A C++ block and an assembly block in one build: both errors captured
  DoCheckFilter('mixed_fail', '''
    E C:/bo/a.cpp:3:11 expected expression
    E C:/bo/b.S:3:3 invalid instruction mnemonic 'bogus_instruction'
    U .\a.cpp:1:1: error: clang exited with code 1
    U .\b.S:1:1: error: clang exited with code 1
    U   bogus_instruction %rax
    U   ^~~~~~~~~~~~~~~~~
    ''');
end;

procedure TPCBuildOutputTests.DoTestEmpty();
begin
  // A successful build with a .S warning: zig prints nothing at all
  DoCheckFilter('asm_warn', '');
end;

procedure TPCBuildOutputTests.DoTestReinit();
var
  LFilter: TPCBuildOutputFilter;
  LReason: string;
begin
  // Init forgets the last build: captures, unknowns, a pending block
  LFilter := TPCBuildOutputFilter.Create();
  try
    Check(DoFeedFixture(LFilter, 'two_fail', LReason), 'reinit: two_fail: %s', [LReason]);
    Check(LFilter.CaptureCount() = 4, 'reinit: two_fail has 4 captures (%d)',
      [LFilter.CaptureCount()]);
    Check(DoFeedFixture(LFilter, 'elimit', LReason), 'reinit: elimit: %s', [LReason]);
    Check((LFilter.CaptureCount() = 2) and (LFilter.UnknownCount() = 1),
      'reinit: only elimit''s 2 captures + 1 line (%d, %d)',
      [LFilter.CaptureCount(), LFilter.UnknownCount()]);
  finally
    LFilter.Free();
  end;
end;

procedure TPCBuildOutputTests.DoTestCommitDedupe();
var
  LFilter: TPCBuildOutputFilter;
  LCommit: TPCBuildOutputCommit;
  LErrors: TErrors;
  LReason: string;
  LGot: string;
  LWant: string;
begin
  // The header's warning arrives from both TUs: reported once, with the
  // first TU's notes; the duplicate spends nothing
  LFilter := TPCBuildOutputFilter.Create();
  LCommit := TPCBuildOutputCommit.Create();
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LCommit.SetErrors(LErrors);
    Check(DoFeedFixture(LFilter, 'two_fail', LReason), 'commit_dedupe: %s', [LReason]);
    LCommit.Commit(LFilter, nil, PC_BOT_ROOT, nil, nil, nil, nil);
    LGot := DoRenderErrors(LErrors);
    LWant := '''
      W ZB0016 C:/bo/leaf.h:2:2 leaf_warn
        R C:/bo/b.cpp:2:0 in file included from .\b.cpp:2:
        R C:/bo/mid.h:3:0 in file included from ./mid.h:3:
      E ZB0016 C:/bo/b.cpp:4:11 expected expression
      E ZB0016 C:/bo/a.cpp:4:11 expected expression
      ''';
    Check(LGot = LWant, 'commit_dedupe: reported' + sLineBreak + '%s', [LGot]);
    Check(LCommit.ErrorsReported() = 2, 'commit_dedupe: 2 errors reported (%d)',
      [LCommit.ErrorsReported()]);
  finally
    LErrors.Free();
    LCommit.Free();
    LFilter.Free();
  end;
end;

procedure TPCBuildOutputTests.DoTestCommitUnreadable();
var
  LFilter: TPCBuildOutputFilter;
  LCommit: TPCBuildOutputCommit;
  LErrors: TErrors;
  LReason: string;
  LBad: string;
  LGot: string;
  LWant: string;
begin
  // A .dia that is not clang's: one ZB0011 warning, and the lines zig
  // printed for its TU stand in. An absent .dia (cached TU) says nothing.
  LBad := DoProbePath('zb14\badsig.dia');
  LFilter := TPCBuildOutputFilter.Create();
  LCommit := TPCBuildOutputCommit.Create();
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LCommit.SetErrors(LErrors);
    Check(FileExists(LBad), 'commit_unreadable: fixture %s exists', [LBad]);
    Check(DoFeedFixture(LFilter, 'elimit', LReason), 'commit_unreadable: %s', [LReason]);
    LCommit.Commit(LFilter, [LBad, TPath.Combine(PC_BOT_ROOT, 'absent.dia')],
      PC_BOT_ROOT, nil, nil, nil, nil);
    LGot := DoRenderErrors(LErrors);
    LWant := Format('W ZB0011 :0:0 ' + RSBdoDiagFileUnreadable,
      [LBad, RSSdgBadSignature]) + sLineBreak + '''
      E ZB0016 C:/bo/a.cpp:3:11 expected expression
      E ZB0016 C:/bo/a.cpp:4:11 expected expression
      ''';
    Check(LGot = LWant, 'commit_unreadable: reported' + sLineBreak + '%s' +
      sLineBreak + '--- want' + sLineBreak + '%s', [LGot, LWant]);
    Check(LCommit.ErrorsReported() = 2, 'commit_unreadable: 2 errors reported (%d)',
      [LCommit.ErrorsReported()]);
  finally
    LErrors.Free();
    LCommit.Free();
    LFilter.Free();
  end;
end;

procedure TPCBuildOutputTests.DoTestCommitStop();
var
  LFilter: TPCBuildOutputFilter;
  LCommit: TPCBuildOutputCommit;
  LErrors: TErrors;
begin
  // clang's location-less stop marker (as a .dia writes it) is never reported
  LFilter := TPCBuildOutputFilter.Create();
  LCommit := TPCBuildOutputCommit.Create();
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LCommit.SetErrors(LErrors);
    DoFeedLines(LFilter, [
      'error: error(compilation): error.FileNotFound: failed to parse clang diagnostics: .\a.cpp:3:11: error: expected expression',
      '       fatal error: too many errors emitted, stopping now [-ferror-limit=]',
      'error: ' + PC_CLANG_STOP_MARKER]);
    LCommit.Commit(LFilter, nil, PC_BOT_ROOT, nil, nil, nil, nil);
    Check(DoRenderErrors(LErrors) = 'E ZB0016 C:/bo/a.cpp:3:11 expected expression',
      'commit_stop: only the error' + sLineBreak + '%s', [DoRenderErrors(LErrors)]);
  finally
    LErrors.Free();
    LCommit.Free();
    LFilter.Free();
  end;
end;

procedure TPCBuildOutputTests.DoTestCommitTranslate();
var
  LFilter: TPCBuildOutputFilter;
  LCommit: TPCBuildOutputCommit;
  LErrors: TErrors;
  LReason: string;
  LGot: string;
  LWant: string;
begin
  // The frontend's locations (here: b.cpp) map back, notes included
  LFilter := TPCBuildOutputFilter.Create();
  LCommit := TPCBuildOutputCommit.Create();
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LCommit.SetErrors(LErrors);
    Check(DoFeedFixture(LFilter, 'two_fail', LReason), 'commit_translate: %s', [LReason]);
    LCommit.Commit(LFilter, nil, PC_BOT_ROOT,
      function(const AFilename: string; const ALine: UInt64;
        const AColumn: UInt64; out AOutFilename: string; out AOutLine: UInt64;
        out AOutColumn: UInt64): Boolean
      begin
        Result := AFilename = 'C:/bo/b.cpp';
        AOutFilename := 'X.pcpp';
        AOutLine := ALine + 100;
        AOutColumn := AColumn;
      end, nil, nil, nil);
    LGot := DoRenderErrors(LErrors);
    LWant := '''
      W ZB0016 C:/bo/leaf.h:2:2 leaf_warn
        R X.pcpp:102:0 in file included from .\b.cpp:2:
        R C:/bo/mid.h:3:0 in file included from ./mid.h:3:
      E ZB0016 X.pcpp:104:11 expected expression
      E ZB0016 C:/bo/a.cpp:4:11 expected expression
      ''';
    Check(LGot = LWant, 'commit_translate: reported' + sLineBreak + '%s', [LGot]);
  finally
    LErrors.Free();
    LCommit.Free();
    LFilter.Free();
  end;
end;

procedure TPCBuildOutputTests.DoTestCommitOwned();
var
  LFilter: TPCBuildOutputFilter;
  LCommit: TPCBuildOutputCommit;
  LErrors: TErrors;
begin
  // A lexical warning the frontend reported itself (at its own location) is
  // dropped whatever its label; the same text elsewhere stands
  LFilter := TPCBuildOutputFilter.Create();
  LCommit := TPCBuildOutputCommit.Create();
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LCommit.SetErrors(LErrors);
    DoFeedLines(LFilter, [
      '.\b.cpp:7:3: error: ' + PC_FRONTEND_LEXICAL_WARNINGS[0],
      '.\a.cpp:7:3: warning: ' + PC_FRONTEND_LEXICAL_WARNINGS[0]]);
    LCommit.Commit(LFilter, nil, PC_BOT_ROOT,
      function(const AFilename: string; const ALine: UInt64;
        const AColumn: UInt64; out AOutFilename: string; out AOutLine: UInt64;
        out AOutColumn: UInt64): Boolean
      begin
        Result := AFilename = 'C:/bo/b.cpp';
        AOutFilename := 'X.pcpp';
        AOutLine := ALine;
        AOutColumn := AColumn;
      end, nil, nil, nil);
    Check(DoRenderErrors(LErrors) = 'W ZB0016 C:/bo/a.cpp:7:3 ' +
      PC_FRONTEND_LEXICAL_WARNINGS[0], 'commit_owned: only a.cpp''s' + sLineBreak +
      '%s', [DoRenderErrors(LErrors)]);
    Check(LCommit.ErrorsReported() = 0, 'commit_owned: the dropped error is not counted (%d)',
      [LCommit.ErrorsReported()]);
  finally
    LErrors.Free();
    LCommit.Free();
    LFilter.Free();
  end;
end;

procedure TPCBuildOutputTests.DoTestCommitGenerated();
var
  LPass: Integer;
  LFilter: TPCBuildOutputFilter;
  LCommit: TPCBuildOutputCommit;
  LErrors: TErrors;
  LGot: string;
  LWant: string;
begin
  // F13: an include-chain step through a file the frontend generated (its own
  // #include of a module header, on a preamble line) is not shown; a step
  // through the person's header stays, and so does a report located in a
  // generated file (an invariant). Pass 0 has no test: every step is kept
  for LPass := 0 to 1 do
  begin
    LFilter := TPCBuildOutputFilter.Create();
    LCommit := TPCBuildOutputCommit.Create();
    LErrors := TErrors.Create();
    try
      LErrors.SetMaxErrors(100);
      LCommit.SetErrors(LErrors);
      DoFeedLines(LFilter, [
        '.\generated\M.pcpp.cpp:2:5: error: generated_error',
        '.\generated\M.pcpp.cpp:3:1: note: generated_note',
        '.\generated\M.pcpp.cpp:1:1: error: clang exited with code 1',
        'error: error(compilation): error.FileNotFound: failed to parse clang diagnostics: In file included from .\generated\M.pcpp.cpp:1:',
        '       In file included from .\generated\U.pcpp.h:4:',
        '       In file included from ./user.h:3:',
        '       C:\bo\U.pcpp:23:10: fatal error: ''x.h'' file not found',
        '',
        'error: 1 compilation errors']);
      if LPass = 0 then
        LCommit.Commit(LFilter, nil, PC_BOT_ROOT, nil, nil, nil, nil)
      else
        LCommit.Commit(LFilter, nil, PC_BOT_ROOT, nil, nil,
          function(const AFilename: string): Boolean
          begin
            Result := SameText(AFilename, 'C:/bo/generated/M.pcpp.cpp') or
              SameText(AFilename, 'C:/bo/generated/U.pcpp.h');
          end, nil);
      LGot := DoRenderErrors(LErrors);

      if LPass = 0 then
        LWant := '''
          E ZB0016 C:/bo/generated/M.pcpp.cpp:2:5 generated_error
            R C:/bo/generated/M.pcpp.cpp:3:1 generated_note
          E ZB0016 C:/bo/U.pcpp:23:10 'x.h' file not found
            R C:/bo/generated/M.pcpp.cpp:1:0 in file included from .\generated\M.pcpp.cpp:1:
            R C:/bo/generated/U.pcpp.h:4:0 in file included from .\generated\U.pcpp.h:4:
            R C:/bo/user.h:3:0 in file included from ./user.h:3:
          '''
      else
        LWant := '''
          E ZB0016 C:/bo/generated/M.pcpp.cpp:2:5 generated_error
            R C:/bo/generated/M.pcpp.cpp:3:1 generated_note
          E ZB0016 C:/bo/U.pcpp:23:10 'x.h' file not found
            R C:/bo/user.h:3:0 in file included from ./user.h:3:
          ''';
      Check(LGot = LWant, 'commit_generated: pass %d (generated test %s)' + sLineBreak + '%s',
        [LPass, BoolToStr(LPass = 1, True), LGot]);
    finally
      LErrors.Free();
      LCommit.Free();
      LFilter.Free();
    end;
  end;
end;

procedure TPCBuildOutputTests.DoTestCommitFrontendCheck();
var
  LPass: Integer;
  LFilter: TPCBuildOutputFilter;
  LCommit: TPCBuildOutputCommit;
  LErrors: TErrors;
  LGot: string;
  LWant: string;
  LSeen: string;
begin
  // PLAN-PASKAL-ERRORS E3: a located error the frontend's check owns is
  // reported with the check's code, text and location, its notes not shown,
  // once per build (a header's copy in a second TU is the same report) and
  // counted; the check gets the untranslated location and the quoted text of
  // clang's 'expression evaluates to' note, unquoted. An error it does not own
  // stays clang's with its notes. Pass 0 has no check: both are clang's
  for LPass := 0 to 1 do
  begin
    LFilter := TPCBuildOutputFilter.Create();
    LCommit := TPCBuildOutputCommit.Create();
    LErrors := TErrors.Create();
    try
      LErrors.SetMaxErrors(100);
      LCommit.SetErrors(LErrors);
      LSeen := '';
      DoFeedLines(LFilter, [
        '.\m.cpp:3:9: error: static assertion failed due to requirement ''x'': pcpp:SM0311',
        '.\m.cpp:3:9: note: expression evaluates to ''4 >= 8''',
        '.\a.cpp:5:2: error: other_error',
        '.\a.cpp:5:3: note: other_note',
        '.\m.cpp:3:9: error: static assertion failed due to requirement ''x'': pcpp:SM0311',
        '.\m.cpp:3:9: note: expression evaluates to ''4 >= 8''',
        'error: 1 compilation errors']);
      if LPass = 0 then
        LCommit.Commit(LFilter, nil, PC_BOT_ROOT, nil, nil, nil, nil)
      else
        LCommit.Commit(LFilter, nil, PC_BOT_ROOT, nil, nil, nil,
          function(const AFilename: string; const ALine: UInt64;
            const AColumn: UInt64; const AMessage: string;
            const AEvaluated: string; const AFlag: string; out ACode: string; out AText: string;
            out AOutFilename: string; out AOutLine: UInt64;
            out AOutColumn: UInt64): Boolean
          begin
            Result := AMessage.EndsWith('pcpp:SM0311');
            // O13b: a diagnostic read from zig's lines has no warning group
            if Result then
              LSeen := LSeen + Format('%s:%s:%s [%s] {%s};', [AFilename, UIntToStr(ALine),
                UIntToStr(AColumn), AEvaluated, AFlag]);
            ACode := 'SM0311';
            AText := 'own_text';
            AOutFilename := 'X.pcpp';
            AOutLine := 7;
            AOutColumn := 21;
          end);
      LGot := DoRenderErrors(LErrors);

      if LPass = 0 then
        LWant := '''
          E ZB0016 C:/bo/m.cpp:3:9 static assertion failed due to requirement 'x': pcpp:SM0311
            R C:/bo/m.cpp:3:9 expression evaluates to '4 >= 8'
          E ZB0016 C:/bo/a.cpp:5:2 other_error
            R C:/bo/a.cpp:5:3 other_note
          '''
      else
        LWant := '''
          E SM0311 X.pcpp:7:21 own_text
          E ZB0016 C:/bo/a.cpp:5:2 other_error
            R C:/bo/a.cpp:5:3 other_note
          ''';
      Check(LGot = LWant, 'commit_frontend_check: pass %d' + sLineBreak + '%s', [LPass, LGot]);
      Check(LCommit.ErrorsReported() = 2, 'commit_frontend_check: pass %d counts 2 errors (%d)',
        [LPass, LCommit.ErrorsReported()]);
      if LPass = 1 then
        Check(LSeen = 'C:/bo/m.cpp:3:9 [4 >= 8] {};C:/bo/m.cpp:3:9 [4 >= 8] {};',
          'commit_frontend_check: the check is asked with the reported location and the bare values (%s)',
          [LSeen]);
    finally
      LErrors.Free();
      LCommit.Free();
      LFilter.Free();
    end;
  end;
end;

procedure TPCBuildOutputTests.DoTestCommitZigError();
var
  LFilter: TPCBuildOutputFilter;
  LCommit: TPCBuildOutputCommit;
  LErrors: TErrors;
begin
  // Any top-level zig error that is not its wrapper text is an error of its
  // own, never only a safety-net line
  LFilter := TPCBuildOutputFilter.Create();
  LCommit := TPCBuildOutputCommit.Create();
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LCommit.SetErrors(LErrors);
    DoFeedLines(LFilter, [
      'error: unable to find something zig needed',
      'error: 1 compilation errors',
      '.\a.cpp:2:1: warning: w']);
    LCommit.Commit(LFilter, nil, PC_BOT_ROOT, nil, nil, nil, nil);
    Check(DoRenderErrors(LErrors) = 'E ZB0016 :0:0 unable to find something zig needed' +
      sLineBreak + 'W ZB0016 C:/bo/a.cpp:2:1 w', 'commit_zig_error: reported' +
      sLineBreak + '%s', [DoRenderErrors(LErrors)]);
    Check(LCommit.ErrorsReported() = 1, 'commit_zig_error: 1 error (%d)',
      [LCommit.ErrorsReported()]);
  finally
    LErrors.Free();
    LCommit.Free();
    LFilter.Free();
  end;
end;

procedure TPCBuildOutputTests.DoTestCommitMissingLib();
var
  LFilter: TPCBuildOutputFilter;
  LCommit: TPCBuildOutputCommit;
  LErrors: TErrors;
  LPlain: TErrors;
  LGot: string;
  LWant: string;
begin
  // F11: zig's location-less "unable to find <kind> system library '<name>'"
  // is reported where the source names the library (the locator); another
  // message, a library the locator does not know, a kind of two words and a
  // located line keep their own location (none / the line's)
  LFilter := TPCBuildOutputFilter.Create();
  LCommit := TPCBuildOutputCommit.Create();
  LErrors := TErrors.Create();
  LPlain := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LPlain.SetMaxErrors(100);
    DoFeedLines(LFilter, [
      'error: unable to find dynamic system library ''lib_x'' using strategy ''paths_first''. searched paths: none',
      'error: unable to find static system library ''lib_y'' using strategy ''no_fallback''. searched paths: C:/a',
      'error: unable to find something zig needed',
      'error: unable to find dynamic system library ''lib_z'' using strategy ''paths_first''. searched paths: none',
      'error: unable to find a dynamic system library ''lib_x''',
      '.\a.cpp:2:1: error: unable to find dynamic system library ''lib_x'' using strategy ''paths_first''. searched paths: none',
      // zig 0.17.0 quotes the name with " (and the strategy not at all); a name opened with
      // one quote and closed with the other is no name
      'error: unable to find dynamic system library "lib_y" using strategy paths_first. searched paths: none',
      'error: unable to find dynamic system library "lib_x'' using strategy paths_first']);

    Check((LFilter.CaptureCount() = 8) and (LFilter.GetCapture(0).LibraryName = 'lib_x') and
      (LFilter.GetCapture(1).LibraryName = 'lib_y') and (LFilter.GetCapture(2).LibraryName = '') and
      (LFilter.GetCapture(3).LibraryName = 'lib_z') and (LFilter.GetCapture(4).LibraryName = '') and
      (LFilter.GetCapture(5).LibraryName = '') and (LFilter.GetCapture(6).LibraryName = 'lib_y') and
      (LFilter.GetCapture(7).LibraryName = ''),
      'commit_missing_lib: names lib_x lib_y - lib_z - - lib_y - (%d captures)', [LFilter.CaptureCount()]);

    LCommit.SetErrors(LErrors);
    LCommit.Commit(LFilter, nil, PC_BOT_ROOT, nil,
      function(const ALibrary: string; out AOutFilename: string;
        out AOutLine: UInt64; out AOutColumn: UInt64): Boolean
      begin
        Result := True;
        if ALibrary = 'lib_x' then
        begin
          AOutFilename := 'X.pcpp';
          AOutLine := 3;
          AOutColumn := 14;
        end
        else if ALibrary = 'lib_y' then
        begin
          AOutFilename := 'Y.pcpp';
          AOutLine := 5;
          AOutColumn := 9;
        end
        else
        begin
          AOutFilename := '';
          AOutLine := 0;
          AOutColumn := 0;
          Result := False;
        end;
      end, nil, nil);
    LGot := DoRenderErrors(LErrors);
    LWant := '''
      E ZB0016 X.pcpp:3:14 unable to find dynamic system library 'lib_x' using strategy 'paths_first'. searched paths: none
      E ZB0016 Y.pcpp:5:9 unable to find static system library 'lib_y' using strategy 'no_fallback'. searched paths: C:/a
      E ZB0016 :0:0 unable to find something zig needed
      E ZB0016 :0:0 unable to find dynamic system library 'lib_z' using strategy 'paths_first'. searched paths: none
      E ZB0016 :0:0 unable to find a dynamic system library 'lib_x'
      E ZB0016 C:/bo/a.cpp:2:1 unable to find dynamic system library 'lib_x' using strategy 'paths_first'. searched paths: none
      E ZB0016 Y.pcpp:5:9 unable to find dynamic system library "lib_y" using strategy paths_first. searched paths: none
      E ZB0016 :0:0 unable to find dynamic system library "lib_x' using strategy paths_first
      ''';
    Check(LGot = LWant, 'commit_missing_lib: located' + sLineBreak + '%s', [LGot]);

    // No locator (no frontend ran): the same error stays without a location
    LCommit.SetErrors(LPlain);
    LCommit.Commit(LFilter, nil, PC_BOT_ROOT, nil, nil, nil, nil);
    LGot := DoRenderErrors(LPlain);
    Check(LGot.StartsWith('E ZB0016 :0:0 unable to find dynamic system library ''lib_x'''),
      'commit_missing_lib: no locator' + sLineBreak + '%s', [LGot]);
  finally
    LPlain.Free();
    LErrors.Free();
    LCommit.Free();
    LFilter.Free();
  end;
end;

procedure TPCBuildOutputTests.DoTestStepStderr();
var
  LFilter: TPCBuildOutputFilter;
  LCommit: TPCBuildOutputCommit;
  LErrors: TErrors;
  LGot: string;
  LWant: string;
begin
  // F11: a failed step's child stderr as zig's build runner prints it
  // (scripts\zb_cmpl\f2a\raw.txt, every line as probed): 'error: error: X'
  // is the child's error X, an indented 'error: Y' its next error Y, each
  // one diagnostic; 'error: process exited with code 1' is the step's
  // summary, kept for the safety net only. An indented 'error:' line with no
  // child stderr before it is no error of its own
  LFilter := TPCBuildOutputFilter.Create();
  LCommit := TPCBuildOutputCommit.Create();
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFeedLines(LFilter, [
      'install',
      '+- install cmp_mlib',
      '   +- compile exe cmp_mlib Debug x86_64-windows-gnu failure',
      'error: error: unable to find dynamic system library ''pcpp_mlib_b'' using strategy ''paths_first''. searched paths: none',
      '       error: unable to find dynamic system library ''pcpp_mlib_a'' using strategy ''paths_first''. searched paths: none',
      '',
      'error: process exited with code 1',
      'failed command: "zig.exe" build-exe -lpcpp_mlib_b -lpcpp_mlib_a',
      '',
      'error: the following build command exited with code 1:',
      'C:\z\maker.exe build',
      'error: plain zig error',
      '       error: not a child line']);

    Check((LFilter.CaptureCount() = 3) and
      (LFilter.GetCapture(0).LibraryName = 'pcpp_mlib_b') and
      (LFilter.GetCapture(1).LibraryName = 'pcpp_mlib_a') and
      (LFilter.GetCapture(2).MessageText = 'plain zig error'),
      'step_stderr: 3 captures, b then a then the plain error (%d)', [LFilter.CaptureCount()]);
    Check((LFilter.UnknownCount() = 2) and
      (LFilter.GetUnknown(0) = 'error: process exited with code 1') and
      (LFilter.GetUnknown(1) = '       error: not a child line'),
      'step_stderr: unrecognised = the summary and the stray indented line (%d)',
      [LFilter.UnknownCount()]);

    LCommit.SetErrors(LErrors);
    LCommit.Commit(LFilter, nil, PC_BOT_ROOT, nil,
      function(const ALibrary: string; out AOutFilename: string;
        out AOutLine: UInt64; out AOutColumn: UInt64): Boolean
      begin
        Result := True;
        if ALibrary = 'pcpp_mlib_a' then
        begin
          AOutFilename := 'M.pcpp';
          AOutLine := 2;
          AOutColumn := 14;
        end
        else
        begin
          AOutFilename := 'U.pcpp';
          AOutLine := 3;
          AOutColumn := 48;
        end;
      end, nil, nil);
    LGot := DoRenderErrors(LErrors);
    LWant := '''
      E ZB0016 U.pcpp:3:48 unable to find dynamic system library 'pcpp_mlib_b' using strategy 'paths_first'. searched paths: none
      E ZB0016 M.pcpp:2:14 unable to find dynamic system library 'pcpp_mlib_a' using strategy 'paths_first'. searched paths: none
      E ZB0016 :0:0 plain zig error
      ''';
    Check(LGot = LWant, 'step_stderr: reported' + sLineBreak + '%s', [LGot]);
  finally
    LErrors.Free();
    LCommit.Free();
    LFilter.Free();
  end;
end;

procedure TPCBuildOutputTests.DoTestCommitAsmLl();
var
  LGot: string;
  LCount: Integer;
begin
  // R38c: a .S's preprocessor diagnostics and a .ll's come from their .dia,
  // on a build that succeeds too; a failure in both the .dia and zig's block
  // is reported once; an assembler error (no .dia entry) comes from the block
  LGot := DoCommitCase('asm_pp_warn', LCount);
  Check((LGot = 'W ZB0016 C:/bo/b.S:2:2 pp warn') and (LCount = 0),
    'commit_asm_ll: asm_pp_warn' + sLineBreak + '%s', [LGot]);

  LGot := DoCommitCase('ll_warn', LCount);
  Check((LGot = 'W ZB0016 :0:0 overriding the module target triple with ' +
    'x86_64-unknown-windows-gnu') and (LCount = 0),
    'commit_asm_ll: ll_warn' + sLineBreak + '%s', [LGot]);

  LGot := DoCommitCase('asm_pp_fail', LCount);
  Check((LGot = 'E ZB0016 C:/bo/b.S:2:2 pp fail') and (LCount = 1),
    'commit_asm_ll: asm_pp_fail' + sLineBreak + '%s', [LGot]);

  LGot := DoCommitCase('ll_fail', LCount);
  Check((LGot = 'E ZB0016 C:/bo/b.ll:3:11 expected value token') and (LCount = 1),
    'commit_asm_ll: ll_fail' + sLineBreak + '%s', [LGot]);

  LGot := DoCommitCase('asm_fail', LCount);
  Check((LGot = 'E ZB0016 C:/bo/b.S:3:3 invalid instruction mnemonic ''bogus_instruction''') and
    (LCount = 1), 'commit_asm_ll: asm_fail' + sLineBreak + '%s', [LGot]);
end;

procedure TPCBuildOutputTests.DoTestCommitMultiline();
var
  LGot: string;
  LCount: Integer;
  LHead: string;
  LFirst: Integer;
begin
  // PLAN-PASKAL-ERRORS E6: clang prints a static_assert's requirement over
  // several lines (a lambda); zig's raw block carries only the first one on
  // its error: line. The .dia entry still claims that line: one report, the
  // whole message, its note (real capture, scripts\zb_pe\e6\capture_multiline.py)
  LGot := DoCommitCase('multiline_fail', LCount);
  LHead := 'E ZB0016 C:/bo/a.cpp:2:15 static assertion failed due to requirement ''[]() {';
  Check(LGot.StartsWith(LHead), 'commit_multiline: the entry first' + sLineBreak + '%s', [LGot]);
  Check(LGot.Contains('}() == 2'': multi'), 'commit_multiline: the whole message' + sLineBreak + '%s',
    [LGot]);
  Check(LGot.Contains('R C:/bo/a.cpp:2:47 expression evaluates to ''1 == 2'''),
    'commit_multiline: its note' + sLineBreak + '%s', [LGot]);

  // zig's copy of the first line is not reported a second time
  LFirst := LGot.IndexOf('E ZB0016');
  Check((LFirst = 0) and (LGot.IndexOf('E ZB0016', LFirst + 1) < 0),
    'commit_multiline: reported once' + sLineBreak + '%s', [LGot]);
  Check(LCount = 1, 'commit_multiline: 1 error counted (%d)', [LCount]);
end;

procedure TPCBuildOutputTests.DoTestSafetyNet();
var
  LFilter: TPCBuildOutputFilter;
  LCommit: TPCBuildOutputCommit;
  LErrors: TErrors;
  LLines: TArray<string>;
begin
  // A failed build whose only report is a warning still shows zig's
  // unrecognised lines; a reported error, or a build that succeeded, not
  LFilter := TPCBuildOutputFilter.Create();
  LCommit := TPCBuildOutputCommit.Create();
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LCommit.SetErrors(LErrors);
    DoFeedLines(LFilter, ['.\a.cpp:1:2: warning: w', 'an odd line']);
    LCommit.Commit(LFilter, nil, PC_BOT_ROOT, nil, nil, nil, nil);
    Check(LCommit.ErrorsReported() = 0, 'safety_net: a warning is no error (%d)',
      [LCommit.ErrorsReported()]);

    LLines := TPCBuildOutputCommit.UnreportedFailure(LFilter, True,
      LCommit.ErrorsReported());
    Check((Length(LLines) = 1) and (LLines[0] = 'an odd line'),
      'safety_net: failed + no error -> the odd line (%d lines)', [Length(LLines)]);

    LLines := TPCBuildOutputCommit.UnreportedFailure(LFilter, True, 1);
    Check(Length(LLines) = 0, 'safety_net: failed + an error -> none (%d)', [Length(LLines)]);

    LLines := TPCBuildOutputCommit.UnreportedFailure(LFilter, False, 0);
    Check(Length(LLines) = 0, 'safety_net: succeeded -> none (%d)', [Length(LLines)]);
  finally
    LErrors.Free();
    LCommit.Free();
    LFilter.Free();
  end;
end;

procedure TPCBuildOutputTests.DoTestReportedLongPath();
var
  LBase: string;
  LUncBase: string;
  LName: string;
begin
  // A path the toolchain reports is text for the person and the location
  // translator: past the plain limit it comes back in the plain spelling
  // with forward slashes, like a short one, never the long-path spelling
  // (R45: TErrors showed it as //?/C:/...)
  LBase := 'C:\' + StringOfChar('b', 200);
  LUncBase := '\\srv\share\' + StringOfChar('u', 200);
  LName := StringOfChar('s', 76) + '.cpp';
  Check(ResolveReportedPath(LName, LBase) = 'C:/' + StringOfChar('b', 200) + '/' + LName,
    'reported_long_path: a drive path past the limit');
  Check(ResolveReportedPath(LName, LUncBase) =
    '//srv/share/' + StringOfChar('u', 200) + '/' + LName,
    'reported_long_path: a UNC path past the limit');
  Check(ResolveReportedPath('a.cpp', 'C:\x') = 'C:/x/a.cpp',
    'reported_long_path: a short path as before');
  Check(ResolveReportedPath('<scratch space>', LBase) = '<scratch space>',
    'reported_long_path: a clang buffer as reported');
end;

end.
