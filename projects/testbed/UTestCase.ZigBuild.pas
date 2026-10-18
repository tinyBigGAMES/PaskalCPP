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
  UTestCase.ZigBuild - ZigBuild diagnostics tests

  TTestCase suite for TPCZigBuild's diagnostics filter and for related-note
  rendering in TErrors. Each zbNN test builds a real C++ probe in
  tests\probe\zbNN with the bundled Zig toolchain and asserts the outcome
  (OK, exit code) and every diagnostic it must produce, file(line,col)
  exact; the diagnostics are also printed for eyeballing. zb05_map routes
  locations through a fake translator standing in for the AST's EmitSpans.
  zb10 checks that clang's copies of the lexer's own lexical warnings are
  dropped only at locations the translator claims (fixture bytes written by
  scripts\zb_c\gen_fixtures.py). zb11 checks that clang's warnings reach
  TErrors as warnings on a build that succeeds (zig build prints none: they
  come from the per-TU clang .dia files, include chain included), and that
  a rebuild served
  from zig's cache reports none (fixture bytes written by
  scripts\zb_d\gen_fixtures.py), with the toolchain diagnostic code. zb12
  checks LoadBuildFile's code for a missing build file. zb16 checks the
  post-build stamps: a failed icon stamp is an error and nothing is
  published, a good stamp publishes, and an icon / version info request on
  a non-Windows target is a warning, not a silent no-op. zb18 checks the
  cross-TU rules: a header's diagnostic seen by two TUs is reported once
  (the first TU's notes), the same line as a C warning and a C++ error is
  both, a duplicate never spends the error budget, and a directory in the
  way of a TU's .dia stops the build (fixture bytes written by
  scripts\zb_e\a1\a1_zbt_draft.py). zb19 checks that an output folder
  exactly PC_ZIG_BUILD_ROOT_MAX long builds: cold with its warning, cached
  without, published both times (fixture written by the test itself).
  zb20 puts derived paths past the plain limit under a folder at that limit:
  a source name of 80 (its .dia path is 310 characters: the warning still
  comes through), a project name of 80 (stamps and publish reach the
  294-character artifact) and a copy-DLL named 80 (R41, R42). zb22 builds
  with defines holding '"' and '\' (R48) and with a source on another drive
  (a subst drive made and removed by the test, R30). zb23 builds and runs
  the runtime regression program (tests\probe\rt\rt_test.cpp, exit 0) and the
  unit-test runtime program (rt_tests.cpp, exit code = its failed count, 2),
  the exit code cap (rt_tests_many.cpp, 256 failures, exit 255 on every target)
  and the debug build's leak report (rt_leak.cpp, PCPP_DEBUG)
  with the runtime for Windows, Linux glibc and Linux musl (Linux through WSL)
  and compares each one's output with its <program>_expected.txt
  (PLAN-RUNTIME); the runtime builds without a warning. zb13 checks the copy paths
  (A3): a copy-DLL lands beside the artifact and the stamped artifact plus a
  file are published (bytes equal); a publish list with two files of one
  name or a missing file publishes nothing (no partial publish); a static
  library and a DLL are published from their own folders and a Linux DLL
  lands beside the executable. PCPP_TEST_RUNTIME, when set,
  names another runtime folder (scratch runs of draft runtimes only).

  Dependencies: StdApp.TestCase, StdApp.Base, StdApp.Console,
    StdApp.Resources, StdApp.Utils, PaskalCPP.ZigBuild, PaskalCPP.BuildOutput
===============================================================================}

unit UTestCase.ZigBuild;

interface

uses
  StdApp.TestCase,
  StdApp.Base;

type

  { TPCZigBuildTests }
  TPCZigBuildTests = class(TTestCase)
  private
    // One test per probe; Create registers each under its CLI name
    procedure DoTestNotes();
    procedure DoTestZb01First();
    procedure DoTestZb01All();
    procedure DoTestZb02First();
    procedure DoTestZb02All();
    procedure DoTestZb03Fatal();
    procedure DoTestZb04Run();
    procedure DoTestZb05Line();
    procedure DoTestZb05Map();
    procedure DoTestZb06Linker();
    procedure DoTestZb07Header();
    procedure DoTestZb10Owned();
    procedure DoTestZb10Map();
    procedure DoTestZb11Success();
    procedure DoTestZb12LoadMissing();
    procedure DoTestZb16IconBad();
    procedure DoTestZb16IconMissing();
    procedure DoTestZb16StampOk();
    procedure DoTestZb16NotWindows();
    procedure DoTestZb18Warn();
    procedure DoTestZb18Error();
    procedure DoTestZb18Level();
    procedure DoTestZb18Budget();
    procedure DoTestZb18DirInWay();
    procedure DoTestZb18AsmLl();
    procedure DoTestZb19RootLimit();
    procedure DoTestZb20LongNames();
    procedure DoTestZb22Forms();
    procedure DoTestZb23Runtime();
    procedure DoZb23Program(const AProgram: string; const AExpectedExit: Cardinal; const ADefine: string);
    procedure DoTestZb13CopyPublish();
    procedure DoTestZb13StaleCopy();
    procedure DoTestZb13Levels();
    procedure DoTestZb13PublishChecks();
    procedure DoTestZb13Layout();
    procedure DoTestZb25CStringParity();

    // Builds tests\probe\<AName>\<ASource>; diagnostics land in AErrors
    // (caller owns it), program output of a run is returned in ARunOutput
    procedure DoRunProbe(const AName: string; const ASource: string;
      const AAutoRun: Boolean; const AFakeMap: Boolean; const AErrors: TErrors;
      out AOk: Boolean; out AExitCode: Cardinal; out ARunOutput: string);

    // Builds the sources ASources (in that order) of tests\probe\<AName>
    // as one project; DoRunProbe is the one-source case
    procedure DoRunProbeTUs(const AName: string; const ASources: array of string;
      const AAutoRun: Boolean; const AFakeMap: Boolean; const AErrors: TErrors;
      out AOk: Boolean; out AExitCode: Cardinal; out ARunOutput: string);

    // Checks item AIndex carries exactly one note: the include site
    // <AFileSuffix>(ALine,AColumn), worded as clang words it
    procedure DoCheckIncludeNote(const AErrors: TErrors; const AIndex: Integer;
      const AFileSuffix: string; const ALine: UInt64; const AColumn: UInt64);

    // Checks item AIndex carries no notes
    procedure DoCheckNoNotes(const AErrors: TErrors; const AIndex: Integer);

    // Checks item AIndex is an error at <AFileSuffix>(ALine,AColumn)
    procedure DoCheckErrorAt(const AErrors: TErrors; const AIndex: Integer;
      const AFileSuffix: string; const ALine: UInt64; const AColumn: UInt64);

    // Checks item AIndex is a warning at <AFileSuffix>(ALine,AColumn)
    procedure DoCheckWarningAt(const AErrors: TErrors; const AIndex: Integer;
      const AFileSuffix: string; const ALine: UInt64; const AColumn: UInt64);
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
    class function InRunAll(): Boolean; override;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  StdApp.Console,
  StdApp.Resources,
  StdApp.Utils,
  PaskalCPP.ZigBuild,
  PaskalCPP.BuildOutput,
  PaskalCPP.Common,
  UTestCase.CString;

type
  { TFakeSpan }
  // One emitted span: what EmitSpans will record on an AST node
  TFakeSpan = record
    PcppLine: UInt64;
    CppColStart: UInt64;
    CppColEnd: UInt64;
    PcppCol: UInt64;
  end;

const
  { FAKE_SPANS }
  // Stand-in for EmitSpans: tests\probe\zb05 gen.cpp against test.pcpp
  FAKE_SPANS: array[0..2] of TFakeSpan = (
    // x        : C++ 'int x = "hello";' col 5   -> pcpp 'x: int32 ...' col 3
    (PcppLine: 4; CppColStart: 5; CppColEnd: 5; PcppCol: 3),
    // "hello"  : C++ cols 9..15                 -> pcpp 'hello' col 15
    (PcppLine: 4; CppColStart: 9; CppColEnd: 15; PcppCol: 15),
    // call     : C++ 'undeclared_fn(42)' 3..19  -> pcpp col 3
    (PcppLine: 7; CppColStart: 3; CppColEnd: 19; PcppCol: 3)
  );

  { TEST_CSTRING_PARITY }
  // zb25: decoded by TPCCString AND compiled by clang, compared byte for
  // byte: every escape form, \N{} table / alias / generated names, Hangul,
  // two unknown-escape warnings, raw strings, direct UTF-8 (no literal may
  // hold a '%': the C++ source is built without Format)
  TEST_CSTRING_PARITY: array[0..18] of string = (
    '"\a\b\f\n\r\t\v\e\E\"\''\?\\"',
    '"\101\0\1011\18\177"',
    '"\303\251"',
    '"\o{101}\o{0000000000101}"',
    '"\x41\x0000000000000041\x4a\x41G"',
    '"\xC3\xA9\x{41}\x{c3}\x{A9}"',
    '"\u00E9\u00e9\u00E9F\U0001F600\u{1F600}\u{e9}\u0041\u0001"',
    '"\N{LATIN SMALL LETTER E WITH ACUTE}\N{NULL}\N{LINE FEED}"',
    '"\N{LATIN CAPITAL LETTER GHA}\N{LATIN CAPITAL LETTER OI}\N{BYTE ORDER MARK}"',
    '"\N{CJK UNIFIED IDEOGRAPH-4E00}\N{CJK UNIFIED IDEOGRAPH-000004E00}\N{CJK UNIFIED IDEOGRAPH-2EBF0}"',
    '"\N{TANGUT IDEOGRAPH-17000}\N{TANGUT COMPONENT-001}\N{KHITAN SMALL SCRIPT CHARACTER-18B00}"',
    '"\N{NUSHU CHARACTER-1B170}\N{CJK COMPATIBILITY IDEOGRAPH-F900}"',
    '"\N{HANGUL SYLLABLE GA}\N{HANGUL SYLLABLE HIH}"',
    '"\q\8"',
    '"??="',
    'R"xy(a\n)"b)xy"',
    'R"(a\b)"',
    '"direct ' + #$E9 + ' ' + #$D83D + #$DE00 + '"',
    '"\xF0\x9F\x98\x80"'
  );

  { TEST_CSTRING_16ONLY }
  // A Unicode 16.0 name: unknown to clang 22.1.8 (Unicode 15.1) and to the
  // generated table; when clang moves on, this side of zb25 fails first
  TEST_CSTRING_16ONLY = 'ALIEN CRAB STEPPING LEFT';

  { TEST_CSTRING_DUMP }
  // The C++ helper zb25 writes with: index, then the literal's bytes in hex.
  // Into a file, not stdout: Run passes stdout through a PTY, which adds
  // terminal control sequences (zb23 does the same)
  TEST_CSTRING_DUMP =
    '#include <cstdio>' + #10 +
    'static FILE *g_out;' + #10 +
    'static void dump(int i, const char *s, unsigned long n) {' + #10 +
    '  std::fprintf(g_out, "%d:", i);' + #10 +
    '  for (unsigned long k = 0; k < n; ++k) std::fprintf(g_out, "%02X", (unsigned)(unsigned char)s[k]);' + #10 +
    '  std::fprintf(g_out, "|");' + #10 +
    '}' + #10;

// Fake frontend translator: maps zb05's test.pcpp columns through FAKE_SPANS
// the way the Compiler will through the AST's EmitSpans
function FakeTranslate(const AFilename: string; const ALine: UInt64;
  const AColumn: UInt64; out AOutFilename: string; out AOutLine: UInt64;
  out AOutColumn: UInt64): Boolean;
var
  LI: Integer;
begin
  Result := False;
  AOutFilename := AFilename;
  AOutLine := ALine;
  AOutColumn := AColumn;

  // zb10's test.pcpp is a frontend file with no column remapping: claimed,
  // location as reported
  if AFilename.Replace('\', '/').EndsWith('/zb10/test.pcpp', True) then
    Exit(True);

  // Otherwise only zb05's simulated frontend file is ours
  if not AFilename.Replace('\', '/').EndsWith('/zb05/test.pcpp', True) then
    Exit;

  // The line is already exact through #line; only the column is looked up
  Result := True;
  for LI := Low(FAKE_SPANS) to High(FAKE_SPANS) do
  begin
    if (FAKE_SPANS[LI].PcppLine = ALine) and
      (AColumn >= FAKE_SPANS[LI].CppColStart) and
      (AColumn <= FAKE_SPANS[LI].CppColEnd) then
    begin
      AOutColumn := FAKE_SPANS[LI].PcppCol;
      Exit;
    end;
  end;
end;

function DoProbePath(const ARelative: string): string;
begin
  // The exe sits two levels below the project root (repo\bin)
  Result := TPath.GetFullPath(TPath.Combine(
    TPath.GetDirectoryName(ParamStr(0)), '..\..\tests\probe\' + ARelative));
end;

function DoFileIs(const AFilename: string; const AFileSuffix: string): Boolean;
begin
  // Diagnostics carry absolute forward-slash paths; match the tail
  Result := AFilename.Replace('\', '/').EndsWith('/' + AFileSuffix, True);
end;

function DoZb16PublishDir(): string;
begin
  // tests\probe\zb16\pub, removed first so a published file proves this run
  Result := DoProbePath('zb16\pub');
  try
    if TDirectory.Exists(Result) then
      TDirectory.Delete(Result, True);
  except
    on Exception do
      Result := '';
  end;
end;

function DoBuildZb16(const AErrors: TErrors;
  const AConfigure: TProc<TPCZigBuild>): Boolean;
var
  LZig: TPCZigBuild;
  LProbeDir: string;
begin
  // Builds tests\probe\zb16\good.cpp as zb16 after AConfigure set it up
  LProbeDir := DoProbePath('zb16');
  LZig := TPCZigBuild.Create();
  try
    LZig.SetErrors(AErrors);
    LZig.SetOutputPath(LProbeDir);
    LZig.SetProjectName('zb16');
    LZig.AddSourceFile(TPath.Combine(LProbeDir, 'good.cpp'));
    AConfigure(LZig);
    Result := LZig.Process(False);
  finally
    LZig.Free();
  end;

  TConsole.PrintLn('OK=%s ERRCOUNT=%d', [BoolToStr(Result, True), AErrors.Count()]);
  AErrors.PrintErrors();
end;

function DoItemIs(const AErrors: TErrors; const AIndex: Integer;
  const ASeverity: TErrorSeverity; const ACode: string; const AText: string): Boolean;
var
  LError: TError;
begin
  // Item AIndex has this severity and code, and its message contains AText
  Result := False;
  if AIndex >= AErrors.Count() then
    Exit;
  LError := AErrors.GetItems()[AIndex];
  Result := (LError.Severity = ASeverity) and (LError.Code = ACode) and
    LError.Message.Contains(AText);
end;

{ TPCZigBuildTests }

constructor TPCZigBuildTests.Create();
begin
  inherited;

  Title := 'ZigBuild';
  RegisterTest('notes', DoTestNotes);
  RegisterTest('zb01_first', DoTestZb01First);
  RegisterTest('zb01_all', DoTestZb01All);
  RegisterTest('zb02_first', DoTestZb02First);
  RegisterTest('zb02_all', DoTestZb02All);
  RegisterTest('zb03_fatal', DoTestZb03Fatal);
  RegisterTest('zb04_run', DoTestZb04Run);
  RegisterTest('zb05_line', DoTestZb05Line);
  RegisterTest('zb05_map', DoTestZb05Map);
  RegisterTest('zb06_linker', DoTestZb06Linker);
  RegisterTest('zb07_header', DoTestZb07Header);
  RegisterTest('zb10_owned', DoTestZb10Owned);
  RegisterTest('zb10_map', DoTestZb10Map);
  RegisterTest('zb11_success', DoTestZb11Success);
  RegisterTest('zb12_load_missing', DoTestZb12LoadMissing);
  RegisterTest('zb16_icon_bad', DoTestZb16IconBad);
  RegisterTest('zb16_icon_missing', DoTestZb16IconMissing);
  RegisterTest('zb16_stamp_ok', DoTestZb16StampOk);
  RegisterTest('zb16_not_windows', DoTestZb16NotWindows);
  RegisterTest('zb18_warn', DoTestZb18Warn);
  RegisterTest('zb18_error', DoTestZb18Error);
  RegisterTest('zb18_level', DoTestZb18Level);
  RegisterTest('zb18_budget', DoTestZb18Budget);
  RegisterTest('zb18_dir_in_way', DoTestZb18DirInWay);
  RegisterTest('zb18_asm_ll', DoTestZb18AsmLl);
  RegisterTest('zb19_root_limit', DoTestZb19RootLimit);
  RegisterTest('zb20_long_names', DoTestZb20LongNames);
  RegisterTest('zb22_forms', DoTestZb22Forms);
  RegisterTest('zb23_runtime', DoTestZb23Runtime);
  RegisterTest('zb13_copy_publish', DoTestZb13CopyPublish);
  RegisterTest('zb13_stale_copy', DoTestZb13StaleCopy);
  RegisterTest('zb13_levels', DoTestZb13Levels);
  RegisterTest('zb13_publish_checks', DoTestZb13PublishChecks);
  RegisterTest('zb13_layout', DoTestZb13Layout);
  RegisterTest('zb25_cstring_parity', DoTestZb25CStringParity);
end;

procedure TPCZigBuildTests.Run();
begin
  inherited;
end;

class function TPCZigBuildTests.InRunAll(): Boolean;
begin
  // Slow (real zig builds): run by name, `testbed.exe ZigBuild`, when a
  // change touches ZigBuild, TErrors or diagnostics; never part of -all
  Result := False;
end;

procedure TPCZigBuildTests.DoRunProbe(const AName: string; const ASource: string;
  const AAutoRun: Boolean; const AFakeMap: Boolean; const AErrors: TErrors;
  out AOk: Boolean; out AExitCode: Cardinal; out ARunOutput: string);
begin
  DoRunProbeTUs(AName, [ASource], AAutoRun, AFakeMap, AErrors, AOk, AExitCode,
    ARunOutput);
end;

procedure TPCZigBuildTests.DoRunProbeTUs(const AName: string;
  const ASources: array of string; const AAutoRun: Boolean;
  const AFakeMap: Boolean; const AErrors: TErrors; out AOk: Boolean;
  out AExitCode: Cardinal; out ARunOutput: string);
var
  LZig: TPCZigBuild;
  LProbeDir: string;
  LRunOutput: string;
  LSource: string;
begin
  LProbeDir := DoProbePath(AName);
  LRunOutput := '';

  LZig := TPCZigBuild.Create();
  try
    LZig.SetErrors(AErrors);
    LZig.SetOutputPath(LProbeDir);
    LZig.SetProjectName(AName);
    for LSource in ASources do
      LZig.AddSourceFile(TPath.Combine(LProbeDir, LSource));
    if AFakeMap then
      LZig.SetLocationTranslator(FakeTranslate);

    // In filtered build mode nothing reaches the callback; a run's program
    // output arrives here, fenced so control bytes are visible
    LZig.SetOutputCallback(
      procedure(const ALine: string; const AUserData: Pointer)
      begin
        LRunOutput := LRunOutput + ALine;
        TConsole.PrintLn('RUN|%s|', [ALine.Replace(#27, '<ESC>')
          .Replace(#13, '<CR>').Replace(#10, '<LF>')]);
      end);

    AOk := LZig.Process(AAutoRun);
    AExitCode := LZig.GetLastExitCode();
  finally
    LZig.Free();
  end;

  TConsole.PrintLn('OK=%s EXIT=%d ERRCOUNT=%d',
    [BoolToStr(AOk, True), AExitCode, AErrors.Count()]);
  AErrors.PrintErrors();
  ARunOutput := LRunOutput;
end;

procedure TPCZigBuildTests.DoCheckIncludeNote(const AErrors: TErrors;
  const AIndex: Integer; const AFileSuffix: string; const ALine: UInt64;
  const AColumn: UInt64);
var
  LError: TError;
  LLabel: string;
begin
  LLabel := Format('item %d: include note at %s(%d,%d)',
    [AIndex + 1, AFileSuffix, ALine, AColumn]);
  if AIndex >= AErrors.Count() then
  begin
    Check(False, LLabel + ': item missing');
    Exit;
  end;

  // Exactly one note: the include site, worded as clang words it
  LError := AErrors.GetItems()[AIndex];
  Check((Length(LError.Related) = 1) and
    DoFileIs(LError.Related[0].Range.Filename, AFileSuffix) and
    (LError.Related[0].Range.StartLine = ALine) and
    (LError.Related[0].Range.StartColumn = AColumn) and
    LError.Related[0].Msg.StartsWith('in file included from '),
    LLabel);
end;

procedure TPCZigBuildTests.DoCheckNoNotes(const AErrors: TErrors;
  const AIndex: Integer);
begin
  if AIndex >= AErrors.Count() then
  begin
    Check(False, Format('item %d: no notes: item missing', [AIndex + 1]));
    Exit;
  end;
  Check(Length(AErrors.GetItems()[AIndex].Related) = 0,
    Format('item %d: no notes', [AIndex + 1]));
end;

procedure TPCZigBuildTests.DoCheckErrorAt(const AErrors: TErrors; const AIndex: Integer;
  const AFileSuffix: string; const ALine: UInt64; const AColumn: UInt64);
var
  LError: TError;
begin
  if AIndex >= AErrors.Count() then
  begin
    Check(False, Format('error %d at %s(%d,%d): missing', [AIndex + 1, AFileSuffix, ALine, AColumn]));
    Exit;
  end;
  LError := AErrors.GetItems()[AIndex];
  Check((LError.Severity = esError) and DoFileIs(LError.Range.Filename, AFileSuffix) and
    (LError.Range.StartLine = ALine) and (LError.Range.StartColumn = AColumn),
    Format('error %d at %s(%d,%d)', [AIndex + 1, AFileSuffix, ALine, AColumn]));
end;

procedure TPCZigBuildTests.DoCheckWarningAt(const AErrors: TErrors; const AIndex: Integer;
  const AFileSuffix: string; const ALine: UInt64; const AColumn: UInt64);
var
  LError: TError;
begin
  if AIndex >= AErrors.Count() then
  begin
    Check(False, Format('warning %d at %s(%d,%d): missing', [AIndex + 1, AFileSuffix, ALine, AColumn]));
    Exit;
  end;
  LError := AErrors.GetItems()[AIndex];
  Check((LError.Severity = esWarning) and DoFileIs(LError.Range.Filename, AFileSuffix) and
    (LError.Range.StartLine = ALine) and (LError.Range.StartColumn = AColumn),
    Format('warning %d at %s(%d,%d)', [AIndex + 1, AFileSuffix, ALine, AColumn]));
end;

// Related notes through TErrors, without zig: every note shape it can carry
// and render. Every location is REAL and can be opened and checked:
//   tests\probe\notes\notes.pcpp, tests\probe\zb07\mylib.h, and the bundled
//   libc++ vector.h lines clang itself reports for push_back candidates.
procedure TPCZigBuildTests.DoTestNotes();
var
  LErrors: TErrors;
  LRange: TSourceRange;
  LNotes: string;
  LMyLib: string;
  LVector: string;
  LItems: TArray<TError>;
begin
  // Absolute, forward-slash paths, as clang/zig report them
  LNotes := DoProbePath('notes\notes.pcpp').Replace('\', '/');
  LMyLib := DoProbePath('zb07\mylib.h').Replace('\', '/');
  LVector := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)),
    'res\zig\lib\libcxx\include\__vector\vector.h')).Replace('\', '/');

  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);

    // notes.pcpp(10,5) 'push_back' with two located notes: the libc++
    // candidates at vector.h(462,60) and (464,60)
    LErrors.Add(LNotes, 10, 5, esError, PC_ERR_BUILDOUTPUT_TOOLDIAG,
      'no matching member function for call to ''push_back''');
    LRange.Clear();
    LRange.Filename := LVector;
    LRange.StartLine := 462;
    LRange.StartColumn := 60;
    LRange.EndLine := 462;
    LRange.EndColumn := 60;
    LErrors.AddRelated(LRange, 'candidate function not viable (const int&)');
    LRange.StartLine := 464;
    LRange.EndLine := 464;
    LErrors.AddRelated(LRange, 'candidate function not viable (int&&)');

    // mylib.h(6,12) 'undeclared_in_header', with the notes.pcpp(3,10)
    // #include that pulled the header in
    LErrors.Add(LMyLib, 6, 12, esError, PC_ERR_BUILDOUTPUT_TOOLDIAG,
      'use of undeclared identifier ''undeclared_in_header''');
    LRange.Clear();
    LRange.Filename := LNotes;
    LRange.StartLine := 3;
    LRange.StartColumn := 10;
    LRange.EndLine := 3;
    LRange.EndColumn := 10;
    LErrors.AddRelated(LRange, 'in file included from here');

    // notes.pcpp(7,3) 'y' declared, never used: a warning with an unlocated
    // note (no range: the simple note form)
    LErrors.Add(LNotes, 7, 3, esWarning, PC_ERR_BUILDOUTPUT_TOOLDIAG, 'unused variable ''y''');
    LRange.Clear();
    LErrors.AddRelated(LRange, 'remove it or mark it unused');

    // notes.pcpp(11,18) one past the ')' of writeln('done'): an error with no
    // notes prints exactly as before
    LErrors.Add(LNotes, 11, 18, esError, PC_ERR_BUILDOUTPUT_TOOLDIAG,
      'expected '';'' after expression');

    LErrors.PrintErrors();

    LItems := LErrors.GetItems().ToArray();
    Check(Length(LItems) = 4, 'notes: 4 items');
    if Length(LItems) <> 4 then
      Exit;
    Check((Length(LItems[0].Related) = 2) and
      DoFileIs(LItems[0].Related[0].Range.Filename, '__vector/vector.h') and
      (LItems[0].Related[0].Range.StartLine = 462) and
      (LItems[0].Related[1].Range.StartLine = 464),
      'notes: two located notes on the first error');
    Check((Length(LItems[1].Related) = 1) and
      DoFileIs(LItems[1].Related[0].Range.Filename, 'notes/notes.pcpp') and
      (LItems[1].Related[0].Range.StartLine = 3) and
      (LItems[1].Related[0].Range.StartColumn = 10),
      'notes: include note on the header error');
    Check((LItems[2].Severity = esWarning) and (Length(LItems[2].Related) = 1) and
      LItems[2].Related[0].Range.IsEmpty(),
      'notes: unlocated note on the warning');
    Check(Length(LItems[3].Related) = 0, 'notes: plain error has no notes');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb01First();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // 3 compile errors in bad.cpp; a budget of 1 stops at the first
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(1);
    DoRunProbe('zb01', 'bad.cpp', False, False, LErrors, LOk, LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb01: build fails');
    Check(LErrors.Count() = 1, 'zb01: exactly 1 error (budget 1)');
    DoCheckErrorAt(LErrors, 0, 'zb01/bad.cpp', 6, 9);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb01All();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // All 3 errors; only the third (push_back) carries notes
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    DoRunProbe('zb01', 'bad.cpp', False, False, LErrors, LOk, LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb01: build fails');
    Check(LErrors.Count() = 3, 'zb01: exactly 3 errors');
    DoCheckErrorAt(LErrors, 0, 'zb01/bad.cpp', 6, 9);
    DoCheckErrorAt(LErrors, 1, 'zb01/bad.cpp', 7, 5);
    DoCheckErrorAt(LErrors, 2, 'zb01/bad.cpp', 9, 7);
    if LErrors.Count() = 3 then
      Check((Length(LErrors.GetItems()[0].Related) = 0) and
        (Length(LErrors.GetItems()[1].Related) = 0) and
        (Length(LErrors.GetItems()[2].Related) = 2),
        'zb01: notes on error 3 only (2 candidates)');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb02First();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // Linker errors: the first, located by its 'referenced by' note
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(1);
    DoRunProbe('zb02', 'bad.cpp', False, False, LErrors, LOk, LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb02: link fails');
    Check(LErrors.Count() = 1, 'zb02: exactly 1 error (budget 1)');
    DoCheckErrorAt(LErrors, 0, 'zb02/bad.cpp', 7, 0);
    if LErrors.Count() = 1 then
      Check(LErrors.GetItems()[0].Message.Contains('missing_function'),
        'zb02: undefined missing_function');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb02All();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // Both linker errors; missing_global has no 'referenced by' location
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    DoRunProbe('zb02', 'bad.cpp', False, False, LErrors, LOk, LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb02: link fails');
    Check(LErrors.Count() = 2, 'zb02: exactly 2 errors');
    DoCheckErrorAt(LErrors, 0, 'zb02/bad.cpp', 7, 0);
    if LErrors.Count() = 2 then
      Check((LErrors.GetItems()[1].Severity = esError) and
        (LErrors.GetItems()[1].Range.Filename = '') and
        LErrors.GetItems()[1].Message.Contains('missing_global'),
        'zb02: undefined missing_global, unlocated');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb03Fatal();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // A missing include is clang's 'fatal error': it is reported as an error
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(1);
    DoRunProbe('zb03', 'bad.cpp', False, False, LErrors, LOk, LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb03: build fails');
    Check(LErrors.Count() = 1, 'zb03: exactly 1 error');
    DoCheckErrorAt(LErrors, 0, 'zb03/bad.cpp', 2, 10);
    if LErrors.Count() = 1 then
      Check(LErrors.GetItems()[0].Message.Contains('does_not_exist.h'),
        'zb03: names the missing header');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb04Run();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // Clean build, then the program runs through the PTY; its output reaches
  // the output callback untouched
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(1);
    DoRunProbe('zb04', 'good.cpp', True, False, LErrors, LOk, LExit, LRun);
    Check(LOk and (LExit = 0), 'zb04: builds and runs, exit 0');
    Check(LErrors.Count() = 0, 'zb04: no diagnostics');
    Check(LRun.Contains('hello from zb04') and LRun.Contains('second line'),
      'zb04: program output reaches the callback');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb05Line();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // gen.cpp carries absolute #line directives: errors land on test.pcpp
  // lines, with the C++ columns (no translator)
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    DoRunProbe('zb05', 'gen.cpp', False, False, LErrors, LOk, LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb05: build fails');
    Check(LErrors.Count() = 2, 'zb05: exactly 2 errors');
    DoCheckErrorAt(LErrors, 0, 'zb05/test.pcpp', 4, 5);
    DoCheckErrorAt(LErrors, 1, 'zb05/test.pcpp', 7, 3);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb05Map();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // Same build through the fake translator: C++ column 5 -> .pcpp column 3
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    DoRunProbe('zb05', 'gen.cpp', False, True, LErrors, LOk, LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb05: build fails');
    Check(LErrors.Count() = 2, 'zb05: exactly 2 errors');
    DoCheckErrorAt(LErrors, 0, 'zb05/test.pcpp', 4, 3);
    DoCheckErrorAt(LErrors, 1, 'zb05/test.pcpp', 7, 3);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb06Linker();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // Relative #line + a linker error: still located on test.pcpp
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    DoRunProbe('zb06', 'gen.cpp', False, False, LErrors, LOk, LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb06: link fails');
    Check(LErrors.Count() = 1, 'zb06: exactly 1 error');
    DoCheckErrorAt(LErrors, 0, 'zb06/test.pcpp', 6, 0);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb07Header();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // An error inside an included header: located in mylib.h, with the
  // test.pcpp #include as its note
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    DoRunProbe('zb07', 'gen.cpp', False, False, LErrors, LOk, LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb07: build fails');
    Check(LErrors.Count() = 1, 'zb07: exactly 1 error');
    DoCheckErrorAt(LErrors, 0, 'zb07/mylib.h', 6, 12);
    DoCheckIncludeNote(LErrors, 0, 'zb07/test.pcpp', 3, 10);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb10Owned();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // No translator, so no frontend ran: all three lexical warnings are
  // clang's own and reach TErrors as warnings, their level from the clang
  // .dia (the header's first: it is included first), then the real error at
  // test.pcpp(8,14)
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    DoRunProbe('zb10', 'gen.cpp', False, False, LErrors, LOk, LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb10: build fails');
    Check(LErrors.Count() = 4, 'zb10: exactly 4 items');
    DoCheckWarningAt(LErrors, 0, 'zb10/mylib.h', 2, 6);
    DoCheckWarningAt(LErrors, 1, 'zb10/test.pcpp', 4, 6);
    DoCheckWarningAt(LErrors, 2, 'zb10/test.pcpp', 5, 13);
    DoCheckErrorAt(LErrors, 3, 'zb10/test.pcpp', 8, 14);

    // The header's warning carries its include site (#line maps it to
    // test.pcpp); the source's own items carry none
    DoCheckIncludeNote(LErrors, 0, 'zb10/test.pcpp', 3, 10);
    DoCheckNoNotes(LErrors, 1);
    DoCheckNoNotes(LErrors, 2);
    DoCheckNoNotes(LErrors, 3);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb10Map();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // The translator claims test.pcpp: its two warnings are the lexer's own
  // reports seen again and are dropped; the header's warning and the real
  // error stand
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    DoRunProbe('zb10', 'gen.cpp', False, True, LErrors, LOk, LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb10: build fails');
    Check(LErrors.Count() = 2, 'zb10: exactly 2 items');
    DoCheckWarningAt(LErrors, 0, 'zb10/mylib.h', 2, 6);
    DoCheckErrorAt(LErrors, 1, 'zb10/test.pcpp', 8, 14);
    DoCheckIncludeNote(LErrors, 0, 'zb10/test.pcpp', 3, 10);
    DoCheckNoNotes(LErrors, 1);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb11Success();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LCleared: Boolean;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // A build that succeeds: zig build prints nothing, so both warnings come
  // from the per-TU clang .dia, with their true level, exact text and notes
  // (the header's first: it is included first). The cache is cleared
  // first, so the TU really compiles.
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetOutputPath(DoProbePath('zb11'));
      LCleared := LZig.ClearCache();
    finally
      LZig.Free();
    end;
    Check(LCleared and (LErrors.Count() = 0), 'zb11: cache cleared');

    DoRunProbe('zb11', 'gen.cpp', False, False, LErrors, LOk, LExit, LRun);
    Check(LOk and (LExit = 0), 'zb11: build succeeds');
    Check(LErrors.Count() = 2, 'zb11: exactly 2 items');
    DoCheckWarningAt(LErrors, 0, 'zb11/mylib.h', 2, 2);
    DoCheckWarningAt(LErrors, 1, 'zb11/gen.cpp', 2, 2);
    if LErrors.Count() = 2 then
      Check((LErrors.GetItems()[0].Message = 'zb11 header') and
        (LErrors.GetItems()[1].Message = 'zb11 source'), 'zb11: warning texts');
    if LErrors.Count() = 2 then
      Check((LErrors.GetItems()[0].Code = PC_ERR_BUILDOUTPUT_TOOLDIAG) and
        (LErrors.GetItems()[1].Code = PC_ERR_BUILDOUTPUT_TOOLDIAG),
        'zb11: toolchain diagnostic code');

    // The header's warning carries its include chain on a build that
    // succeeds (research\zigbuild-followup\r4-include-chain.md)
    DoCheckIncludeNote(LErrors, 0, 'zb11/gen.cpp', 1, 10);
    DoCheckNoNotes(LErrors, 1);

    // Unchanged rebuild: zig serves the TU from its cache, clang writes no
    // .dia, and nothing is reported (only TUs compiled in this build report)
    LErrors.Clear();
    DoRunProbe('zb11', 'gen.cpp', False, False, LErrors, LOk, LExit, LRun);
    Check(LOk and (LExit = 0), 'zb11: rebuild succeeds');
    Check(LErrors.Count() = 0, 'zb11: cache hit reports nothing');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb12LoadMissing();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LLoaded: Boolean;
begin
  // A build file that does not exist (tests\probe\zb12 is never created):
  // LoadBuildFile fails with the load code, not the save code. No zig run.
  LErrors := TErrors.Create();
  try
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LLoaded := LZig.LoadBuildFile(DoProbePath('zb12\missing\build.zig'));
    finally
      LZig.Free();
    end;
    LErrors.PrintErrors();
    Check(not LLoaded, 'zb12: load fails');
    Check(LErrors.Count() = 1, 'zb12: exactly 1 item');
    if LErrors.Count() = 1 then
      Check((LErrors.GetItems()[0].Severity = esError) and
        (LErrors.GetItems()[0].Code = PC_ERR_ZIGBUILD_LOADFAILED),
        'zb12: error with the load code');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb16IconBad();
var
  LErrors: TErrors;
  LPub: string;
  LOk: Boolean;
begin
  // A malformed icon: error ZB0008 with StdApp's reason, nothing published
  LPub := DoZb16PublishDir();
  Check(LPub <> '', 'zb16: publish dir reset');
  LErrors := TErrors.Create();
  try
    LOk := DoBuildZb16(LErrors,
      procedure(AZig: TPCZigBuild)
      begin
        AZig.SetExeIcon(DoProbePath('zb16\bad_offset.ico'));
        AZig.AddPublishArtifact(LPub);
      end);
    Check(not LOk, 'zb16_icon_bad: build reports failure');
    Check(LErrors.Count() = 1, 'zb16_icon_bad: exactly 1 item');
    Check(DoItemIs(LErrors, 0, esError, PC_ERR_ZIGBUILD_ICON, 'Invalid icon file'),
      'zb16_icon_bad: ZB0008 error carrying the reason');
    Check(not TFile.Exists(TPath.Combine(LPub, 'zb16.exe')),
      'zb16_icon_bad: nothing published');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb16IconMissing();
var
  LErrors: TErrors;
  LOk: Boolean;
begin
  // A requested icon that does not exist: error ZB0008
  LErrors := TErrors.Create();
  try
    LOk := DoBuildZb16(LErrors,
      procedure(AZig: TPCZigBuild)
      begin
        AZig.SetExeIcon(DoProbePath('zb16\missing.ico'));
      end);
    Check(not LOk, 'zb16_icon_missing: build reports failure');
    Check(LErrors.Count() = 1, 'zb16_icon_missing: exactly 1 item');
    Check(DoItemIs(LErrors, 0, esError, PC_ERR_ZIGBUILD_ICON, 'missing.ico'),
      'zb16_icon_missing: ZB0008 error naming the icon');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb16StampOk();
var
  LErrors: TErrors;
  LPub: string;
  LOk: Boolean;
begin
  // A good icon and version info: stamped, no diagnostics, then published
  LPub := DoZb16PublishDir();
  Check(LPub <> '', 'zb16: publish dir reset');
  LErrors := TErrors.Create();
  try
    LOk := DoBuildZb16(LErrors,
      procedure(AZig: TPCZigBuild)
      begin
        AZig.SetExeIcon(DoProbePath('zb16\good.ico'));
        AZig.SetAddVersionInfo(True);
        AZig.SetVIMajor(1);
        AZig.SetVIMinor(2);
        AZig.SetVIPatch(3);
        AZig.SetVIProductName('Zb16');
        AZig.SetVIFilename('zb16.exe');
        AZig.AddPublishArtifact(LPub);
      end);
    Check(LOk, 'zb16_stamp_ok: build succeeds');
    Check(LErrors.Count() = 0, 'zb16_stamp_ok: no diagnostics');
    Check(TFile.Exists(TPath.Combine(LPub, 'zb16.exe')),
      'zb16_stamp_ok: published');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb16NotWindows();
var
  LErrors: TErrors;
  LOk: Boolean;
begin
  // Icon and version info on a Linux target: the build succeeds and each
  // ignored request is a ZB0019 warning, never a silent no-op
  LErrors := TErrors.Create();
  try
    LOk := DoBuildZb16(LErrors,
      procedure(AZig: TPCZigBuild)
      begin
        AZig.SetTarget('x86_64-linux-gnu');
        AZig.SetExeIcon(DoProbePath('zb16\good.ico'));
        AZig.SetAddVersionInfo(True);
      end);
    Check(LOk, 'zb16_not_windows: build succeeds');
    Check(LErrors.ErrorCount() = 0, 'zb16_not_windows: no errors');
    Check((LErrors.Count() = 2) and
      DoItemIs(LErrors, 0, esWarning, PC_ERR_ZIGBUILD_WRNNOTAPPLICABLE, 'Icon ignored') and
      DoItemIs(LErrors, 1, esWarning, PC_ERR_ZIGBUILD_WRNNOTAPPLICABLE, 'Version info ignored'),
      'zb16_not_windows: two ZB0019 warnings, icon then version info');
  finally
    LErrors.Free();
  end;
end;

function DoClearProbeCache(const AName: string; const AErrors: TErrors): Boolean;
var
  LZig: TPCZigBuild;
begin
  // zig's cache would serve an unchanged TU and clang would write no .dia:
  // cleared, so every TU of the probe really compiles
  LZig := TPCZigBuild.Create();
  try
    LZig.SetErrors(AErrors);
    LZig.SetOutputPath(DoProbePath(AName));
    Result := LZig.ClearCache() and (AErrors.Count() = 0);
  finally
    LZig.Free();
  end;
end;

function DoDiagFileOf(const AName: string; const ASource: string): string;
var
  LText: string;
  LMarker: string;
  LPos: Integer;
  LEnd: Integer;
begin
  // The .dia path build.zig gives ASource: the flag after its file name in
  // its own addCSourceFiles block. '' when it cannot be found.
  Result := '';
  try
    LText := TFile.ReadAllText(TPath.Combine(DoProbePath(AName), 'build.zig'));
  except
    on Exception do
      Exit;
  end;

  LPos := LText.IndexOf('"' + ASource + '"');
  if LPos < 0 then
    Exit;
  LMarker := '"-serialize-diagnostic-file", "-Xclang", "';
  LPos := LText.IndexOf(LMarker, LPos);
  if LPos < 0 then
    Exit;
  LPos := LPos + LMarker.Length;
  LEnd := LText.IndexOf('"', LPos);
  if LEnd < 0 then
    Exit;
  Result := LText.Substring(LPos, LEnd - LPos);
end;

function DoHasNoteFile(const AError: TError; const AFilename: string): Boolean;
var
  LI: Integer;
begin
  // A note located in AFilename, spelled exactly so
  Result := False;
  for LI := 0 to High(AError.Related) do
  begin
    if AError.Related[LI].Range.Filename = AFilename then
      Exit(True);
  end;
end;

procedure TPCZigBuildTests.DoTestZb18Warn();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // A header warning seen by both TUs on a build that succeeds: one report,
  // with the first TU's include site as its note
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    Check(DoClearProbeCache('zb18_warn', LErrors), 'zb18_warn: cache cleared');
    DoRunProbeTUs('zb18_warn', ['a.cpp', 'b.cpp'], False, False, LErrors, LOk,
      LExit, LRun);
    Check(LOk and (LExit = 0), 'zb18_warn: build succeeds');
    Check(LErrors.Count() = 1, 'zb18_warn: exactly 1 item');
    DoCheckWarningAt(LErrors, 0, 'zb18_warn/h.h', 2, 2);
    DoCheckIncludeNote(LErrors, 0, 'zb18_warn/a.cpp', 1, 10);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb18AsmLl();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
  LItem: TError;
begin
  // R38c: a .S preprocessor warning and a .ll warning on a build that
  // succeeds reach the user (each TU's .dia), in source order
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    Check(DoClearProbeCache('zb18_asm_ll', LErrors), 'zb18_asm_ll: cache cleared');
    DoRunProbeTUs('zb18_asm_ll', ['a.cpp', 'b.S', 'c.ll'], False, False, LErrors, LOk,
      LExit, LRun);
    Check(LOk and (LExit = 0), 'zb18_asm_ll: build succeeds');
    Check(LErrors.Count() = 2, 'zb18_asm_ll: exactly 2 items');
    DoCheckWarningAt(LErrors, 0, 'zb18_asm_ll/b.S', 1, 2);
    if LErrors.Count() = 2 then
    begin
      LItem := LErrors.GetItems()[1];
      Check((LItem.Severity = esWarning) and (LItem.Range.Filename = '') and
        (LItem.Message = 'overriding the module target triple with x86_64-unknown-windows-gnu'),
        'zb18_asm_ll: the .ll warning, no location');
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb18Error();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // A header error seen by both TUs: one report, the first TU's note
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    DoRunProbeTUs('zb18_error', ['a.cpp', 'b.cpp'], False, False, LErrors, LOk,
      LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb18_error: build fails');
    Check(LErrors.Count() = 1, 'zb18_error: exactly 1 item');
    DoCheckErrorAt(LErrors, 0, 'zb18_error/h.h', 2, 19);
    DoCheckIncludeNote(LErrors, 0, 'zb18_error/a.cpp', 1, 10);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb18Level();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // One header line is a warning in the C TU and an error in the C++ TU:
  // both are facts, both are reported. Their macro notes name clang's
  // '<scratch space>' buffer, kept as spelled (not a path).
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    Check(DoClearProbeCache('zb18_level', LErrors), 'zb18_level: cache cleared');
    DoRunProbeTUs('zb18_level', ['a.c', 'b.cpp'], False, False, LErrors, LOk,
      LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb18_level: build fails');
    Check(LErrors.Count() = 2, 'zb18_level: exactly 2 items');
    DoCheckWarningAt(LErrors, 0, 'zb18_level/h.h', 7, 1);
    DoCheckErrorAt(LErrors, 1, 'zb18_level/h.h', 7, 1);
    if LErrors.Count() = 2 then
    begin
      Check((LErrors.GetItems()[0].Message = 'zb18 level') and
        (LErrors.GetItems()[1].Message = 'zb18 level'), 'zb18_level: one message');
      Check(DoHasNoteFile(LErrors.GetItems()[0], '<scratch space>') and
        DoHasNoteFile(LErrors.GetItems()[1], '<scratch space>'),
        'zb18_level: <scratch space> notes kept as spelled');
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb18Budget();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
begin
  // Two errors allowed: the header's error, seen by both TUs, is reported
  // once, so b.cpp's own error still fits the budget
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(2);
    DoRunProbeTUs('zb18_budget', ['a.cpp', 'b.cpp'], False, False, LErrors, LOk,
      LExit, LRun);
    Check((not LOk) and (LExit <> 0), 'zb18_budget: build fails');
    Check(LErrors.Count() = 2, 'zb18_budget: exactly 2 items');
    DoCheckErrorAt(LErrors, 0, 'zb18_budget/h.h', 2, 19);
    DoCheckErrorAt(LErrors, 1, 'zb18_budget/b.cpp', 2, 21);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb18DirInWay();
var
  LErrors: TErrors;
  LOk: Boolean;
  LExit: Cardinal;
  LRun: string;
  LDiag: string;
begin
  // A directory where a TU's .dia goes: clang could not write it, and on a
  // build that succeeds that TU's diagnostics would vanish. The build is not
  // run: one ZB0012 that says why.
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    DoRunProbeTUs('zb18_warn', ['a.cpp', 'b.cpp'], False, False, LErrors, LOk,
      LExit, LRun);
    LDiag := DoDiagFileOf('zb18_warn', 'a.cpp');
    Check(LDiag <> '', 'zb18_dir: the .dia path of a.cpp is in build.zig');
    if LDiag = '' then
      Exit;

    try
      TDirectory.CreateDirectory(LDiag);
    except
      on E: Exception do
      begin
        Check(False, 'zb18_dir: cannot make the directory: %s', [E.Message]);
        Exit;
      end;
    end;

    try
      LErrors.Clear();
      DoRunProbeTUs('zb18_warn', ['a.cpp', 'b.cpp'], False, False, LErrors, LOk,
        LExit, LRun);
      Check(not LOk, 'zb18_dir: build not run');
      Check(LErrors.Count() = 1, 'zb18_dir: exactly 1 item');
      Check(DoItemIs(LErrors, 0, esError, PC_ERR_ZIGBUILD_DIAGFILEFAILED,
        RSZigBuildDiagFileIsDir), 'zb18_dir: ZB0012, a directory is in the way');
    finally
      try
        TDirectory.Delete(LDiag);
      except
        on E: Exception do
          Check(False, 'zb18_dir: cleanup: %s', [E.Message]);
      end;
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb19RootLimit();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LBase: string;
  LRoot: string;
  LPub: string;
  LOk: Boolean;
  LLength: Integer;
  LRound: Integer;
begin
  // An output folder exactly PC_ZIG_BUILD_ROOT_MAX long builds (one more is
  // ZB0021: ZigBuildPaths.root_limit). tests\probe\zb19 is removed first, so
  // round 1 is a cold build: its warning comes through its .dia; round 2 is
  // served from zig's cache: nothing reported. Both rounds publish.
  LBase := DoProbePath('zb19');
  LRoot := LBase + '\' + StringOfChar('d', PC_ZIG_BUILD_ROOT_MAX - Length(LBase) - 1);
  LPub := TPath.Combine(LBase, 'pub');
  try
    if TDirectory.Exists(LBase) then
      TDirectory.Delete(LBase, True);
    TDirectory.CreateDirectory(LRoot);
    TFile.WriteAllText(TPath.Combine(LRoot, 'a.cpp'),
      '#warning zb19' + #13#10 + 'int main() { return 0; }' + #13#10, TEncoding.ASCII);
  except
    on E: Exception do
    begin
      Check(False, 'zb19: fixture written: %s', [E.Message]);
      Exit;
    end;
  end;

  for LRound := 1 to 2 do
  begin
    // A published file proves this round published
    try
      if TDirectory.Exists(LPub) then
        TDirectory.Delete(LPub, True);
    except
      on E: Exception do
      begin
        Check(False, 'zb19: publish dir emptied: %s', [E.Message]);
        Exit;
      end;
    end;

    LErrors := TErrors.Create();
    try
      LErrors.SetMaxErrors(10);
      LZig := TPCZigBuild.Create();
      try
        LZig.SetErrors(LErrors);
        LZig.SetOutputPath(LRoot);
        LLength := Length(LZig.GetOutputPath());
        LZig.SetProjectName('zb19');
        LZig.AddSourceFile(TPath.Combine(LRoot, 'a.cpp'));
        LZig.AddPublishArtifact(LPub);
        LOk := LZig.Process(False);
      finally
        LZig.Free();
      end;

      TConsole.PrintLn('ROUND=%d OK=%s ERRCOUNT=%d', [LRound, BoolToStr(LOk, True),
        LErrors.Count()]);
      LErrors.PrintErrors();
      Check(LLength = PC_ZIG_BUILD_ROOT_MAX, 'zb19: round %d: the folder is at the limit',
        [LRound]);
      Check(LOk, 'zb19: round %d: builds', [LRound]);
      Check(TFile.Exists(TPath.Combine(LPub, 'zb19.exe')), 'zb19: round %d: published',
        [LRound]);
      if LRound = 1 then
      begin
        Check(LErrors.Count() = 1, 'zb19: cold: exactly 1 item');
        DoCheckWarningAt(LErrors, 0, 'a.cpp', 1, 2);
      end
      else
        Check(LErrors.Count() = 0, 'zb19: cached: nothing reported');
    finally
      LErrors.Free();
    end;
  end;
end;

procedure TPCZigBuildTests.DoTestZb20LongNames();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LBase: string;
  LRoot: string;
  LPub: string;
  LSourceName: string;
  LProjectName: string;
  LDllName: string;
  LOk: Boolean;
  LRound: Integer;
  LInfo: TVersionInfo;
  LVersionOk: Boolean;
begin
  // Names that put derived paths past the plain limit under an output folder
  // at PC_ZIG_BUILD_ROOT_MAX (R41, R42): a source name of 80 (its .dia path
  // is 310 characters: the warning comes through cold, nothing when cached),
  // a project name of 80 (the artifact path is 294: manifest, icon and
  // version info stamped, then published) and a copy-DLL named 80 (copied
  // into bin). tests\probe\zb20 is removed first; round 2 is served
  // from zig's cache.
  LBase := DoProbePath('zb20');
  LRoot := LBase + '\' + StringOfChar('d', PC_ZIG_BUILD_ROOT_MAX - Length(LBase) - 1);
  LPub := TPath.Combine(LBase, 'pub');
  LSourceName := StringOfChar('s', 76) + '.cpp';
  LProjectName := StringOfChar('p', 80);
  LDllName := StringOfChar('l', 76) + '.dll';
  try
    if TDirectory.Exists(PATH_LONG_PREFIX + LBase) then
      TDirectory.Delete(PATH_LONG_PREFIX + LBase, True);
    TDirectory.CreateDirectory(LRoot);
    TFile.WriteAllText(PATH_LONG_PREFIX + LRoot + '\' + LSourceName,
      '#warning zb20' + #13#10 + 'int main() { return 0; }' + #13#10, TEncoding.ASCII);
    TFile.Copy(DoProbePath('utils\res\lib.dll'), TPath.Combine(LBase, LDllName), True);
  except
    on E: Exception do
    begin
      Check(False, 'zb20: fixture written: %s', [E.Message]);
      Exit;
    end;
  end;

  for LRound := 1 to 2 do
  begin
    // A published file proves this round published
    try
      if TDirectory.Exists(LPub) then
        TDirectory.Delete(LPub, True);
    except
      on E: Exception do
      begin
        Check(False, 'zb20: publish dir emptied: %s', [E.Message]);
        Exit;
      end;
    end;

    LErrors := TErrors.Create();
    try
      LErrors.SetMaxErrors(10);
      LZig := TPCZigBuild.Create();
      try
        LZig.SetErrors(LErrors);
        LZig.SetOutputPath(LRoot);
        LZig.SetProjectName(LProjectName);
        LZig.AddSourceFile(LRoot + '\' + LSourceName);
        LZig.AddCopyDLL(TPath.Combine(LBase, LDllName));
        LZig.SetExeIcon(DoProbePath('zb16\good.ico'));
        LZig.SetAddVersionInfo(True);
        LZig.SetVIMajor(1);
        LZig.SetVIMinor(2);
        LZig.SetVIPatch(3);
        LZig.SetVIProductName('Zb20');
        LZig.SetVIFilename('zb20.exe');
        LZig.AddPublishArtifact(LPub);
        LOk := LZig.Process(False);
      finally
        LZig.Free();
      end;

      TConsole.PrintLn('ROUND=%d OK=%s ERRCOUNT=%d', [LRound, BoolToStr(LOk, True),
        LErrors.Count()]);
      LErrors.PrintErrors();
      Check(LOk, 'zb20: round %d: builds, stamps and publishes', [LRound]);
      LVersionOk := TUtils.GetVersionInfo(LInfo,
        TPath.Combine(LPub, LProjectName + '.exe')) and
        (LInfo.VersionString = '1.2.3') and (LInfo.ProductName = 'Zb20');
      Check(LVersionOk, 'zb20: round %d: the published exe carries its version info',
        [LRound]);
      Check(TFile.Exists(TUtils.ResolvePath('bin\' + LDllName, LRoot)),
        'zb20: round %d: the DLL is copied into bin', [LRound]);
      if LRound = 1 then
      begin
        Check(LErrors.Count() = 1, 'zb20: cold: exactly 1 item (the warning)');
        DoCheckWarningAt(LErrors, 0, LSourceName, 1, 2);
        Check((LErrors.Count() > 0) and
          (not LErrors.GetItems()[0].Range.Filename.Contains('?')),
          'zb20: cold: the warning names its source in the plain spelling');
      end
      else
        Check(LErrors.Count() = 0, 'zb20: cached: nothing reported');
    finally
      LErrors.Free();
    end;
  end;
end;

function DoSubst(const AArgs: string; out AReason: string): Boolean;
var
  LExitCode: Cardinal;
  LLines: string;
begin
  // subst.exe with AArgs; False + its output when it fails
  LLines := '';
  LExitCode := 1;
  AReason := '';
  try
    TUtils.CaptureConsoleOutput('', 'subst.exe', PChar(AArgs), '', LExitCode, nil,
      procedure(const ALine: string; const AUserData: Pointer)
      begin
        LLines := LLines + ALine + ' ';
      end);
  except
    on E: Exception do
      LLines := E.Message;
  end;
  Result := LExitCode = 0;
  if not Result then
    AReason := Format('exit %d: %s', [LExitCode, LLines.Trim()]);
end;

procedure TPCZigBuildTests.DoTestZb22Forms();
var
  LBase: string;
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LOk: Boolean;
  LDrive: string;
  LLetter: Char;
  LReason: string;
begin
  // R48: defines holding '"' and '\' reach the compiler as they are (the
  // static_assert checks the string's length). R30: a source on another
  // drive than the build root builds (a subst drive, removed after).
  LBase := DoProbePath('zb22');
  try
    if TDirectory.Exists(LBase) then
      TDirectory.Delete(LBase, True);
    TDirectory.CreateDirectory(TPath.Combine(LBase, 'xd'));
    TFile.WriteAllText(TPath.Combine(LBase, 'a.cpp'),
      'static_assert(sizeof(MSG) == 4, "MSG");' + #13#10 +
      'int b_value();' + #13#10 +
      'int main() { return b_value() - 1; }' + #13#10, TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(LBase, 'xd\b.cpp'),
      'int b_value() { return 1; }' + #13#10, TEncoding.ASCII);
  except
    on E: Exception do
    begin
      Check(False, 'zb22: fixture written: %s', [E.Message]);
      Exit;
    end;
  end;

  // A drive letter nothing uses
  LDrive := '';
  for LLetter := 'Z' downto 'P' do
  begin
    if not DirectoryExists(LLetter + ':\') then
    begin
      LDrive := LLetter + ':';
      Break;
    end;
  end;
  Check(LDrive <> '', 'zb22: a free drive letter');
  if LDrive = '' then
    Exit;
  if not DoSubst(LDrive + ' ' + TUtils.QuoteCommandArg(
    TUtils.StripLongPathPrefix(TPath.Combine(LBase, 'xd'))), LReason) then
  begin
    Check(False, 'zb22: subst %s: %s', [LDrive, LReason]);
    Exit;
  end;

  try
    LErrors := TErrors.Create();
    try
      LErrors.SetMaxErrors(10);
      Check(DoClearProbeCache('zb22', LErrors), 'zb22: cache cleared');
      LErrors.Clear();
      LZig := TPCZigBuild.Create();
      try
        LZig.SetErrors(LErrors);
        LZig.SetOutputPath(LBase);
        LZig.SetProjectName('zb22');
        // '"a\\b"' is the C string a\b: 'a', '\', 'b', NUL = sizeof 4; a
        // '\' lost on the way would make it 3 (or break build.zig, R48)
        LZig.SetDefine('MSG', '"a\\b"');
        LZig.SetDefine('DIR', 'C:\x\y');
        LZig.AddSourceFile(TPath.Combine(LBase, 'a.cpp'));
        LZig.AddSourceFile(LDrive + '\b.cpp');
        LOk := LZig.Process(True);
      finally
        LZig.Free();
      end;
      TConsole.PrintLn('OK=%s ERRCOUNT=%d', [BoolToStr(LOk, True), LErrors.Count()]);
      LErrors.PrintErrors();
      Check(LOk and (LErrors.Count() = 0),
        'zb22: builds and runs (defines with quote and backslash, a source on %s)', [LDrive]);
    finally
      LErrors.Free();
    end;
  finally
    if not DoSubst(LDrive + ' /d', LReason) then
      Check(False, 'zb22: subst %s removed: %s', [LDrive, LReason]);
  end;
end;

const
  { PC_ZB23_TARGETS }
  // Every runtime platform family that runs on this machine
  PC_ZB23_TARGETS: array[0..2] of string = (
    'x86_64-windows-gnu',
    'x86_64-linux-gnu',
    'x86_64-linux-musl'
  );

procedure TPCZigBuildTests.DoTestZb23Runtime();
begin
  // The runtime regression program (exit 0), the unit-test runtime program
  // (exit code = its failed count, 2; a release build: its report holds no
  // leak line), 256 failing tests (exit code capped at 255 on every target:
  // Linux keeps only the low 8 bits) and the debug build's leak report (PCPP_DEBUG)
  DoZb23Program('rt_test', 0, '');
  DoZb23Program('rt_tests', 2, '');
  DoZb23Program('rt_tests_many', 255, '');
  DoZb23Program('rt_leak', 0, 'PCPP_DEBUG');
end;

procedure TPCZigBuildTests.DoZb23Program(const AProgram: string; const AExpectedExit: Cardinal;
  const ADefine: string);
var
  LBase: string;
  LRuntime: string;
  LOutFile: string;
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LOk: Boolean;
  LExitCode: Cardinal;
  LRanAsExpected: Boolean;
  LGot: string;
  LWant: string;
  LI: Integer;
begin
  // tests\probe\rt\<AProgram>.cpp, built with the runtime the emitter will
  // use and run on each target: no warnings, the expected exit code, its
  // output file (<AProgram>_out.txt in its folder) against the expected text
  LBase := DoProbePath('rt');
  LRuntime := TUtils.GetEnv('PCPP_TEST_RUNTIME');
  if LRuntime = '' then
    LRuntime := TUtils.ResolvePath('res\runtime', TPath.GetDirectoryName(ParamStr(0)));
  LOutFile := TPath.Combine(LBase, 'bin\' + AProgram + '_out.txt');
  try
    LWant := TFile.ReadAllText(TPath.Combine(LBase, AProgram + '_expected.txt'),
      TEncoding.UTF8).Replace(#13#10, #10);
  except
    on E: Exception do
    begin
      Check(False, 'zb23: %s expected text read: %s', [AProgram, E.Message]);
      Exit;
    end;
  end;

  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    for LI := Low(PC_ZB23_TARGETS) to High(PC_ZB23_TARGETS) do
    begin
      LErrors.Clear();
      try
        if FileExists(LOutFile) then
          TFile.Delete(LOutFile);
      except
        on E: Exception do
          Check(False, 'zb23: old output removed: %s', [E.Message]);
      end;

      LZig := TPCZigBuild.Create();
      try
        LZig.SetErrors(LErrors);
        LZig.SetOutputPath(LBase);
        LZig.SetProjectName(AProgram);
        LZig.SetTarget(PC_ZB23_TARGETS[LI]);
        LZig.AddIncludePath(LRuntime);
        if ADefine <> '' then
          LZig.SetDefine(ADefine);
        LZig.AddSourceFile(TPath.Combine(LBase, AProgram + '.cpp'));
        LZig.AddSourceFile(TPath.Combine(LRuntime, 'pcpp_runtime.cpp'));
        LOk := LZig.Process(True);
        LExitCode := LZig.GetLastExitCode();
      finally
        LZig.Free();
      end;
      TConsole.PrintLn('%s %s: OK=%s EXIT=%d ERRCOUNT=%d', [AProgram, PC_ZB23_TARGETS[LI],
        BoolToStr(LOk, True), LExitCode, LErrors.Count()]);
      LErrors.PrintErrors();
      // Exit 0 is a clean run; another expected exit code is ZB0031 alone,
      // with the code kept
      if AExpectedExit = 0 then
        LRanAsExpected := LOk and (LErrors.Count() = 0) and (LExitCode = 0)
      else
        LRanAsExpected := (not LOk) and (LErrors.Count() = 1) and
          (LErrors.GetItems()[0].Code = PC_ERR_ZIGBUILD_RUNEXIT) and (LExitCode = AExpectedExit);
      Check(LRanAsExpected, 'zb23: %s on %s builds without a warning and exits %d (got %d)',
        [AProgram, PC_ZB23_TARGETS[LI], AExpectedExit, LExitCode]);

      LGot := '';
      try
        if FileExists(LOutFile) then
          LGot := TFile.ReadAllText(LOutFile, TEncoding.UTF8).Replace(#13#10, #10);
      except
        on E: Exception do
          Check(False, 'zb23: output read: %s', [E.Message]);
      end;
      Check(LGot = LWant, 'zb23: %s on %s: the program''s output as expected' + sLineBreak +
        '--- got' + sLineBreak + '%s' + '--- want' + sLineBreak + '%s',
        [AProgram, PC_ZB23_TARGETS[LI], LGot, LWant]);
    end;
  finally
    LErrors.Free();
  end;
end;

function DoZb13Prepare(const AErrors: TErrors; out ABase: string): Boolean;
begin
  // tests\probe\zb13, written fresh: a program, a stand-in DLL (copied,
  // never loaded), publish sources with one name in two folders
  ABase := DoProbePath('zb13');
  Result := False;
  try
    if TDirectory.Exists(ABase) then
      TDirectory.Delete(ABase, True);
    TDirectory.CreateDirectory(TPath.Combine(ABase, 'a'));
    TDirectory.CreateDirectory(TPath.Combine(ABase, 'b'));
    TFile.WriteAllText(TPath.Combine(ABase, 'gen.cpp'),
      'int zb13_value() { return 0; }' + #13#10 + 'int main() { return zb13_value(); }' + #13#10,
      TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(ABase, 'stub.dll'), 'not loaded', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(ABase, 'a\data.txt'), 'from a', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(ABase, 'b\data.txt'), 'from b', TEncoding.ASCII);
    Result := True;
  except
    on E: Exception do
      AErrors.Add(esError, 'TEST', 'zb13 fixture: %s', [E.Message]);
  end;
end;

function DoSameFile(const APath1: string; const APath2: string): Boolean;
var
  LBytes1: TBytes;
  LBytes2: TBytes;
begin
  // Both readable, with the same bytes
  Result := False;
  try
    LBytes1 := TFile.ReadAllBytes(APath1);
    LBytes2 := TFile.ReadAllBytes(APath2);
  except
    on Exception do
      Exit;
  end;
  Result := (Length(LBytes1) = Length(LBytes2)) and
    ((Length(LBytes1) = 0) or CompareMem(@LBytes1[0], @LBytes2[0], Length(LBytes1)));
end;

procedure TPCZigBuildTests.DoTestZb13CopyPublish();
var
  LBase: string;
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LOk: Boolean;
  LPub: string;
begin
  // The copy-DLL lands beside the artifact before the build; after it the
  // artifact and a file are published, bytes equal
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    Check(DoZb13Prepare(LErrors, LBase), 'zb13: fixture written');
    LPub := TPath.Combine(LBase, 'pub.v1\bin');
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetOutputPath(TPath.Combine(LBase, 'out.v1'));
      LZig.SetProjectName('zb13');
      LZig.AddSourceFile(TPath.Combine(LBase, 'gen.cpp'));
      LZig.AddCopyDLL(TPath.Combine(LBase, 'stub.dll'));
      LZig.AddPublishArtifact(LPub);
      LZig.AddPostBuildCopy(TPath.Combine(LBase, 'a\data.txt'), LPub);
      LOk := LZig.Process(False);
    finally
      LZig.Free();
    end;
    LErrors.PrintErrors();
    Check(LOk and (LErrors.Count() = 0), 'zb13_copy_publish: builds and publishes (%d items)',
      [LErrors.Count()]);
    Check(DoSameFile(TPath.Combine(LBase, 'stub.dll'),
      TPath.Combine(LBase, 'out.v1\bin\stub.dll')),
      'zb13_copy_publish: the DLL beside the artifact');
    Check(DoSameFile(TPath.Combine(LBase, 'out.v1\bin\zb13.exe'),
      TPath.Combine(LPub, 'zb13.exe')), 'zb13_copy_publish: the artifact published');
    Check(DoSameFile(TPath.Combine(LBase, 'a\data.txt'), TPath.Combine(LPub, 'data.txt')),
      'zb13_copy_publish: the file published');
  finally
    LErrors.Free();
  end;
end;

{ DoZb13StaleBuild }
// One build of a project into out.stale, with the stand-in DLL as a copy-DLL or none
function DoZb13StaleBuild(const ABase: string; const AErrors: TErrors;
  const AWithCopy: Boolean; const AProject: string = 'zb13'): Boolean;
var
  LZig: TPCZigBuild;
begin
  LZig := TPCZigBuild.Create();
  try
    LZig.SetErrors(AErrors);
    LZig.SetOutputPath(TPath.Combine(ABase, 'out.stale'));
    LZig.SetProjectName(AProject);
    LZig.AddSourceFile(TPath.Combine(ABase, 'gen.cpp'));
    if AWithCopy then
      LZig.AddCopyDLL(TPath.Combine(ABase, 'stub.dll'));
    Result := LZig.Process(False);
  finally
    LZig.Free();
  end;
  AErrors.PrintErrors();
end;

{ DoZb13RecordHas }
// The record of installed files holds exactly this line (trimmed)
function DoZb13RecordHas(const ARecord: string; const AName: string): Boolean;
var
  LLines: TArray<string>;
  LLine: string;
begin
  Result := False;
  if not FileExists(ARecord) then
    Exit;
  try
    LLines := TFile.ReadAllLines(ARecord, TEncoding.UTF8);
  except
    on Exception do
      Exit;
  end;
  for LLine in LLines do
  begin
    if LLine.Trim() = AName then
      Exit(True);
  end;
end;

procedure TPCZigBuildTests.DoTestZb13StaleCopy();
var
  LBase: string;
  LBin: string;
  LRecord: string;
  LLegacy: string;
  LMine: string;
  LOutside: string;
  LErrors: TErrors;
  LOk: Boolean;
begin
  // F10 + PLAN-RELEASE-NAMES atom 5: every file a build puts beside the
  // artifact is recorded (pcpp-installed.txt: the artifact, its .pdb, the
  // copy-DLLs); a recorded file the next build does not produce is removed (a
  // copy-DLL no longer named, a renamed project's artifact and .pdb). A file
  // the person put beside the program, the artifact, and a record line naming
  // a path outside bin\ / lib\ are never touched. An old pcpp-copydll.txt is
  // read once in place of the record, then replaced
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    Check(DoZb13Prepare(LErrors, LBase), 'zb13: fixture written');
    LBin := TPath.Combine(LBase, 'out.stale\bin');
    LRecord := TPath.Combine(LBase, 'out.stale\pcpp-installed.txt');
    LLegacy := TPath.Combine(LBase, 'out.stale\pcpp-copydll.txt');
    LMine := TPath.Combine(LBin, 'mine.txt');
    LOutside := TPath.Combine(LBase, 'out.stale\outside.txt');

    // 1. With the copy-DLL: copied, and it and the build's own files recorded
    LOk := DoZb13StaleBuild(LBase, LErrors, True);
    Check(LOk and (LErrors.Count() = 0) and FileExists(TPath.Combine(LBin, 'stub.dll')),
      'zb13_stale_copy: round 1 copies stub.dll (%d items)', [LErrors.Count()]);
    Check(DoZb13RecordHas(LRecord, 'bin/stub.dll') and DoZb13RecordHas(LRecord, 'bin/zb13.exe') and
      DoZb13RecordHas(LRecord, 'bin/zb13.pdb'),
      'zb13_stale_copy: round 1 records stub.dll, zb13.exe and zb13.pdb');

    // The person's file beside the program, and record lines naming a path
    // outside bin\ / lib\ (only '<bin|lib>/<bare name>' is a file of ours)
    try
      TFile.WriteAllText(LMine, 'mine', TEncoding.ASCII);
      TFile.WriteAllText(LOutside, 'outside', TEncoding.ASCII);
      TFile.AppendAllText(LRecord, 'bin/../outside.txt' + #10 + '..\outside.txt' + #10 +
        'outside.txt' + #10, TEncoding.ASCII);
    except
      on E: Exception do
        Check(False, 'zb13_stale_copy: setup (%s)', [E.Message]);
    end;

    // 2. No copy-DLL: the stale copy goes, nothing else
    LErrors.Clear();
    LOk := DoZb13StaleBuild(LBase, LErrors, False);
    Check(LOk and (LErrors.Count() = 0), 'zb13_stale_copy: round 2 builds with no report (%d items)',
      [LErrors.Count()]);
    Check(not FileExists(TPath.Combine(LBin, 'stub.dll')),
      'zb13_stale_copy: round 2 removed the stale stub.dll');
    Check(FileExists(LMine) and FileExists(LOutside) and FileExists(TPath.Combine(LBin, 'zb13.exe')),
      'zb13_stale_copy: round 2 kept the person''s files and the artifact');
    Check(DoZb13RecordHas(LRecord, 'bin/zb13.exe') and (not DoZb13RecordHas(LRecord, 'bin/stub.dll')) and
      (not DoZb13RecordHas(LRecord, 'bin/../outside.txt')),
      'zb13_stale_copy: round 2 records the artifact, not the removed copy or the outside line');

    // 3. The copy-DLL again: copied and recorded again
    LErrors.Clear();
    LOk := DoZb13StaleBuild(LBase, LErrors, True);
    Check(LOk and (LErrors.Count() = 0) and FileExists(TPath.Combine(LBin, 'stub.dll')) and
      DoZb13RecordHas(LRecord, 'bin/stub.dll'),
      'zb13_stale_copy: round 3 copies and records stub.dll again (%d items)', [LErrors.Count()]);

    // 4. The project renamed: the old artifact and its .pdb go, the copy stays
    LErrors.Clear();
    LOk := DoZb13StaleBuild(LBase, LErrors, True, 'zb13r');
    Check(LOk and (LErrors.Count() = 0) and FileExists(TPath.Combine(LBin, 'zb13r.exe')),
      'zb13_stale_copy: round 4 builds the renamed project (%d items)', [LErrors.Count()]);
    Check((not FileExists(TPath.Combine(LBin, 'zb13.exe'))) and
      (not FileExists(TPath.Combine(LBin, 'zb13.pdb'))),
      'zb13_stale_copy: round 4 removed the old project''s zb13.exe and zb13.pdb');
    Check(FileExists(LMine) and FileExists(TPath.Combine(LBin, 'stub.dll')) and
      DoZb13RecordHas(LRecord, 'bin/zb13r.exe') and (not DoZb13RecordHas(LRecord, 'bin/zb13.exe')),
      'zb13_stale_copy: round 4 kept the person''s file and the copy, records zb13r.exe only');

    // 5. An old pcpp-copydll.txt (0.1.0: bare copy-DLL names) and no new
    // record: read once, its stale copy removed, then replaced by the record
    try
      TFile.Delete(LRecord);
      TFile.WriteAllText(LLegacy, 'stub.dll' + #10, TEncoding.ASCII);
    except
      on E: Exception do
        Check(False, 'zb13_stale_copy: legacy setup (%s)', [E.Message]);
    end;
    LErrors.Clear();
    LOk := DoZb13StaleBuild(LBase, LErrors, False, 'zb13r');
    Check(LOk and (LErrors.Count() = 0) and (not FileExists(TPath.Combine(LBin, 'stub.dll'))),
      'zb13_stale_copy: round 5 removed the copy the old record names (%d items)', [LErrors.Count()]);
    Check((not FileExists(LLegacy)) and DoZb13RecordHas(LRecord, 'bin/zb13r.exe') and
      FileExists(LMine),
      'zb13_stale_copy: round 5 replaced the old record, kept the person''s file');
  finally
    LErrors.Free();
  end;
end;

{ DoZb13LevelBuild }
// One build of gen.cpp (project zb13) for ATarget at ALevel into AOutput;
// AArtifact = the built file's path
function DoZb13LevelBuild(const ABase: string; const AErrors: TErrors; const ATarget: string;
  const ALevel: TPCOptimizeLevel; const AOutput: string; out AArtifact: string): Boolean;
var
  LZig: TPCZigBuild;
begin
  AArtifact := '';
  LZig := TPCZigBuild.Create();
  try
    LZig.SetErrors(AErrors);
    LZig.SetOutputPath(TPath.Combine(ABase, AOutput));
    LZig.SetProjectName('zb13');
    LZig.SetTarget(ATarget);
    LZig.SetOptimizeLevel(ALevel);
    LZig.AddSourceFile(TPath.Combine(ABase, 'gen.cpp'));
    Result := LZig.Process(False);
    AArtifact := LZig.GetArtifactPath();
  finally
    LZig.Free();
  end;
  AErrors.PrintErrors();
end;

{ DoZb13ReadLE }
// ACount little-endian bytes at AAt (the caller checked the range)
function DoZb13ReadLE(const ABytes: TBytes; const AAt: UInt64; const ACount: Integer): UInt64;
var
  LI: Integer;
begin
  Result := 0;
  for LI := ACount - 1 downto 0 do
    Result := (Result shl 8) or ABytes[NativeInt(AAt) + LI];
end;

{ DoZb13ElfSection }
// Whether an ELF64 little-endian file holds a section named ASection:
// 1 yes, 0 no, -1 not such a file or its tables lie outside it. Read from
// the section header table (e_shoff +$28, e_shentsize +$3A, e_shnum +$3C,
// e_shstrndx +$3E); each entry's sh_name (+$00) indexes the section-name
// string table, whose sh_offset is at +$18 and sh_size at +$20
function DoZb13ElfSection(const APath: string; const ASection: string): Integer;
var
  LBytes: TBytes;
  LFileSize: UInt64;
  LShOff: UInt64;
  LShEntSize: UInt64;
  LShNum: UInt64;
  LShStrNdx: UInt64;
  LEntry: UInt64;
  LStrOff: UInt64;
  LStrSize: UInt64;
  LPos: UInt64;
  LIndex: Integer;
  LName: string;
begin
  Result := -1;
  try
    LBytes := TFile.ReadAllBytes(APath);
  except
    on Exception do
      Exit;
  end;
  LFileSize := UInt64(Length(LBytes));

  // The ELF magic, class 64-bit (EI_CLASS = 2), little-endian (EI_DATA = 1)
  if (LFileSize < 64) or (LBytes[0] <> $7F) or (LBytes[1] <> Ord('E')) or
    (LBytes[2] <> Ord('L')) or (LBytes[3] <> Ord('F')) or (LBytes[4] <> 2) or
    (LBytes[5] <> 1) then
    Exit;

  LShOff := DoZb13ReadLE(LBytes, $28, 8);
  LShEntSize := DoZb13ReadLE(LBytes, $3A, 2);
  LShNum := DoZb13ReadLE(LBytes, $3C, 2);
  LShStrNdx := DoZb13ReadLE(LBytes, $3E, 2);
  if (LShEntSize < 64) or (LShStrNdx >= LShNum) or (LShOff > LFileSize) or
    (LShNum * LShEntSize > LFileSize - LShOff) then
    Exit;

  // The section-name string table
  LEntry := LShOff + LShStrNdx * LShEntSize;
  LStrOff := DoZb13ReadLE(LBytes, LEntry + $18, 8);
  LStrSize := DoZb13ReadLE(LBytes, LEntry + $20, 8);
  if (LStrOff > LFileSize) or (LStrSize > LFileSize - LStrOff) then
    Exit;

  Result := 0;
  for LIndex := 0 to Integer(LShNum) - 1 do
  begin
    LEntry := LShOff + UInt64(LIndex) * LShEntSize;
    LPos := LStrOff + DoZb13ReadLE(LBytes, LEntry, 4);

    // The name runs to its NUL, inside the string table
    LName := '';
    while (LPos < LStrOff + LStrSize) and (LBytes[NativeInt(LPos)] <> 0) do
    begin
      LName := LName + Char(LBytes[NativeInt(LPos)]);
      Inc(LPos);
    end;
    if LName = ASection then
      Exit(1);
  end;
end;

procedure TPCZigBuildTests.DoTestZb13Levels();
var
  LBase: string;
  LErrors: TErrors;
  LRecord: string;

  { DoWindowsStep }
  // A Windows build at ALevel into out.levels.win: the .pdb beside the exe
  // (and in the record) exactly when AWantPdb
  procedure DoWindowsStep(const ALevel: TPCOptimizeLevel; const ALevelText: string;
    const AWantPdb: Boolean);
  var
    LArtifact: string;
    LPdb: string;
    LOk: Boolean;
  begin
    LErrors.Clear();
    LOk := DoZb13LevelBuild(LBase, LErrors, 'x86_64-windows-gnu', ALevel, 'out.levels.win',
      LArtifact);
    Check(LOk and (LErrors.Count() = 0) and FileExists(LArtifact),
      'zb13_levels: windows %s builds (%d items)', [ALevelText, LErrors.Count()]);
    LPdb := TPath.ChangeExtension(LArtifact, '.pdb');
    if AWantPdb then
      Check(FileExists(LPdb) and DoZb13RecordHas(LRecord, 'bin/zb13.pdb'),
        'zb13_levels: windows %s: zb13.pdb beside the exe and recorded', [ALevelText])
    else
      Check((not FileExists(LPdb)) and (not DoZb13RecordHas(LRecord, 'bin/zb13.pdb')),
        'zb13_levels: windows %s: no zb13.pdb beside the exe or in the record', [ALevelText]);
  end;

  { DoLinuxStep }
  // A Linux build at ALevel into out.levels.linux: the ELF holds .debug_info
  // exactly when AWantDebug
  procedure DoLinuxStep(const ALevel: TPCOptimizeLevel; const ALevelText: string;
    const AWantDebug: Boolean);
  var
    LArtifact: string;
    LSection: Integer;
    LOk: Boolean;
  begin
    LErrors.Clear();
    LOk := DoZb13LevelBuild(LBase, LErrors, 'x86_64-linux-gnu', ALevel, 'out.levels.linux',
      LArtifact);
    Check(LOk and (LErrors.Count() = 0) and FileExists(LArtifact),
      'zb13_levels: linux %s builds (%d items)', [ALevelText, LErrors.Count()]);
    LSection := DoZb13ElfSection(LArtifact, '.debug_info');
    Check(LSection >= 0, 'zb13_levels: linux %s: the artifact is an ELF64 file', [ALevelText]);
    if AWantDebug then
      Check(LSection = 1, 'zb13_levels: linux %s: .debug_info in the ELF', [ALevelText])
    else
      Check(LSection = 0, 'zb13_levels: linux %s: no .debug_info in the ELF', [ALevelText]);
  end;

begin
  // PLAN-RELEASE-NAMES atom 6: a build carries debug info at debug only.
  // Windows: the .pdb lies beside the exe at debug only, and the next build
  // at another level removes the one a debug build left (fast after the
  // first debug build, safe after the second). Linux: the ELF holds
  // .debug_info at debug only
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    Check(DoZb13Prepare(LErrors, LBase), 'zb13: fixture written');
    LRecord := TPath.Combine(LBase, 'out.levels.win\pcpp-installed.txt');

    DoWindowsStep(olDebug, 'debug', True);
    DoWindowsStep(olFast, 'fast', False);
    DoWindowsStep(olDebug, 'debug again', True);
    DoWindowsStep(olSafe, 'safe', False);

    DoLinuxStep(olDebug, 'debug', True);
    DoLinuxStep(olSafe, 'safe', False);
    DoLinuxStep(olFast, 'fast', False);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb13PublishChecks();
var
  LBase: string;
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LOk: Boolean;
  LPub: string;
  LRound: Integer;
begin
  // A publish list is checked as a whole after the build: two files of one
  // name (round 1) or a missing file (round 2) is one error, and nothing of
  // the list is published, the artifact included (no partial publish)
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    Check(DoZb13Prepare(LErrors, LBase), 'zb13: fixture written');
    for LRound := 1 to 2 do
    begin
      LErrors.Clear();
      LPub := TPath.Combine(LBase, Format('pubchk%d', [LRound]));
      LZig := TPCZigBuild.Create();
      try
        LZig.SetErrors(LErrors);
        LZig.SetOutputPath(TPath.Combine(LBase, 'out.v1'));
        LZig.SetProjectName('zb13');
        LZig.AddSourceFile(TPath.Combine(LBase, 'gen.cpp'));
        LZig.AddPublishArtifact(LPub);
        LZig.AddPostBuildCopy(TPath.Combine(LBase, 'a\data.txt'), LPub);
        if LRound = 1 then
          LZig.AddPostBuildCopy(TPath.Combine(LBase, 'b\data.txt'), LPub)
        else
          LZig.AddPostBuildCopy(TPath.Combine(LBase, 'missing.txt'), LPub);
        LOk := LZig.Process(False);
      finally
        LZig.Free();
      end;
      LErrors.PrintErrors();
      if LRound = 1 then
        Check((not LOk) and (LErrors.Count() = 1) and
          (LErrors.GetItems()[0].Code = PC_ERR_ZIGBUILD_COLLISION),
          'zb13_publish_checks: two files of one name: one ZB0025 (%d items)', [LErrors.Count()])
      else
        Check((not LOk) and (LErrors.Count() = 1) and
          (LErrors.GetItems()[0].Code = PC_ERR_ZIGBUILD_SOURCEMISSING),
          'zb13_publish_checks: a missing file: one ZB0026 (%d items)', [LErrors.Count()]);
      Check(not TDirectory.Exists(LPub), 'zb13_publish_checks: round %d published nothing',
        [LRound]);
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb13Layout();
var
  LBase: string;
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LOk: Boolean;
  LCase: Integer;
  LWant: string;
  LOutDir: string;
  LLayout: TArray<string>;
  LMissing: string;
  LPath: string;
begin
  // Every artifact kind from its own folder (the layout rule): a static
  // library and a DLL published; a Linux DLL beside the executable.
  // PLAN-OUTPUT: zig installs straight into the output folder (<out>\bin,
  // <out>\lib), never into a zig-out folder
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    Check(DoZb13Prepare(LErrors, LBase), 'zb13: fixture written');
    for LCase := 1 to 3 do
    begin
      LErrors.Clear();
      LWant := '';
      LOutDir := TPath.Combine(LBase, Format('kind%d', [LCase]));

      // A folder an earlier run (or the old layout) left would hide a
      // zig-out the build itself created: every case starts empty
      try
        if TDirectory.Exists(LOutDir) then
          TDirectory.Delete(LOutDir, True);
      except
        on E: Exception do
          Check(False, 'zb13_layout: case %d: cannot empty %s: %s', [LCase, LOutDir, E.Message]);
      end;

      LZig := TPCZigBuild.Create();
      try
        LZig.SetErrors(LErrors);
        LZig.SetOutputPath(LOutDir);
        LZig.SetProjectName('zb13k');
        LZig.AddSourceFile(TPath.Combine(LBase, 'gen.cpp'));
        case LCase of
          1:
            begin
              LZig.SetBuildMode(bmLib);
              LZig.AddPublishArtifact(TPath.Combine(LBase, 'pubk1'));
              LWant := TPath.Combine(LBase, 'pubk1\zb13k.lib');
              LLayout := ['lib\zb13k.lib'];
            end;
          2:
            begin
              LZig.SetBuildMode(bmDll);
              LZig.AddPublishArtifact(TPath.Combine(LBase, 'pubk2'));
              LWant := TPath.Combine(LBase, 'pubk2\zb13k.dll');
              // the DLL beside a program, its import library with the libraries
              LLayout := ['bin\zb13k.dll', 'lib\zb13k.lib'];
            end;
          3:
            begin
              LZig.SetBuildMode(bmDll);
              LZig.SetTarget('x86_64-linux-gnu');
              LWant := TPath.Combine(LBase, 'kind3\bin\libzb13k.so');
              LLayout := ['bin\libzb13k.so'];
            end;
        end;
        LOk := LZig.Process(False);
      finally
        LZig.Free();
      end;
      LErrors.PrintErrors();
      Check(LOk and (LErrors.Count() = 0) and FileExists(LWant),
        'zb13_layout: case %d: %s (%d items)', [LCase, LWant, LErrors.Count()]);

      // The artifact sits in the layout folder under the output folder itself
      LMissing := '';
      for LPath in LLayout do
        if not FileExists(TPath.Combine(LOutDir, LPath)) then
          LMissing := LMissing + ' ' + LPath;
      Check(LMissing = '', 'zb13_layout: case %d: in the output folder (missing:%s)',
        [LCase, LMissing]);
      Check(not TDirectory.Exists(TPath.Combine(LOutDir, 'zig-out')),
        'zb13_layout: case %d: no zig-out folder', [LCase]);
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildTests.DoTestZb25CStringParity();
var
  LCpp: string;
  LMain: string;
  LExpected: string;
  LI: Integer;
  LK: Integer;
  LStatus: TPCCStringStatus;
  LValue: string;
  LReason: string;
  LBytes: TBytes;
  LDir: string;
  LErrors: TErrors;
  LOk: Boolean;
  LExitCode: Cardinal;
  LOutput: string;
  LOutFile: string;
  LFound: Boolean;
  LError: TError;
begin
  // Every TEST_CSTRING_PARITY literal is decoded by TPCCString and compiled
  // into tests\probe\zb25\parity.cpp (generated from the same list, so one
  // source of truth), whose program prints clang's bytes: both must agree.
  // Then a Unicode 16.0-only name must be unknown to both (zb25b): a
  // toolchain upgrade that moves clang's Unicode version fails here, and
  // scripts\zb_ngen.py is rerun for the new version.
  LCpp := TEST_CSTRING_DUMP;
  LMain := 'int main() {' + #10 +
    '  g_out = std::fopen("zb25_out.txt", "wb");' + #10 +
    '  if (!g_out) return 2;' + #10;
  LExpected := '';
  for LI := Low(TEST_CSTRING_PARITY) to High(TEST_CSTRING_PARITY) do
  begin
    if (not DecodeCSource(TEST_CSTRING_PARITY[LI], LStatus, LValue, LReason)) or
      (LStatus = csError) then
    begin
      Check(False, 'zb25: literal %d decodes: %s', [LI, LReason]);
      Exit;
    end;
    LCpp := LCpp + 'static const char s' + IntToStr(LI) + '[] = ' +
      TEST_CSTRING_PARITY[LI] + ';' + #10;
    LMain := LMain + '  dump(' + IntToStr(LI) + ', s' + IntToStr(LI) + ', sizeof(s' +
      IntToStr(LI) + ') - 1);' + #10;
    LBytes := TEncoding.UTF8.GetBytes(LValue);
    LExpected := LExpected + IntToStr(LI) + ':';
    for LK := 0 to High(LBytes) do
      LExpected := LExpected + IntToHex(LBytes[LK], 2);
    LExpected := LExpected + '|';
  end;
  LCpp := LCpp + LMain + '  std::fprintf(g_out, "END");' + #10 + '  std::fclose(g_out);' + #10 +
    '  return 0;' + #10 + '}' + #10;
  LExpected := LExpected + 'END';

  // UTF-8 without a BOM (GetBytes writes no preamble). The program runs in
  // its own folder, so its output file lands in bin; an old one is
  // removed first, so a stale file can never pass
  LDir := DoProbePath('zb25');
  LOutFile := TPath.Combine(LDir, 'bin\zb25_out.txt');
  try
    TDirectory.CreateDirectory(LDir);
    TFile.WriteAllBytes(TPath.Combine(LDir, 'parity.cpp'), TEncoding.UTF8.GetBytes(LCpp));
    if FileExists(LOutFile) then
      TFile.Delete(LOutFile);
  except
    on E: Exception do
    begin
      Check(False, 'zb25: fixture written: %s', [E.Message]);
      Exit;
    end;
  end;

  LErrors := TErrors.Create();
  try
    DoRunProbe('zb25', 'parity.cpp', True, False, LErrors, LOk, LExitCode, LOutput);
    Check(LOk and (LExitCode = 0) and (LErrors.ErrorCount() = 0), 'zb25: builds and runs');
    try
      LOutput := TFile.ReadAllText(LOutFile, TEncoding.ASCII);
    except
      on E: Exception do
      begin
        Check(False, 'zb25: output read: %s', [E.Message]);
        Exit;
      end;
    end;
    Check(LOutput = LExpected, 'zb25: TPCCString bytes = clang bytes');
    if LOutput <> LExpected then
    begin
      TConsole.PrintLn('expected: %s', [LExpected]);
      TConsole.PrintLn('clang:    %s', [LOutput]);
    end;
  finally
    LErrors.Free();
  end;

  // The 16.0-only name: Decode refuses it, and clang refuses it
  Check(DecodeCSource('"\N{' + TEST_CSTRING_16ONLY + '}"', LStatus, LValue, LReason) and
    (LStatus = csError) and
    (LReason = RSComCStrUnknownName.Replace('%s', TEST_CSTRING_16ONLY)),
    'zb25b: Decode: 16.0 name unknown');
  LDir := DoProbePath('zb25b');
  try
    TDirectory.CreateDirectory(LDir);
    TFile.WriteAllBytes(TPath.Combine(LDir, 'only16.cpp'), TEncoding.UTF8.GetBytes(
      'static const char s[] = "\N{' + TEST_CSTRING_16ONLY + '}";' + #10 +
      'int main() { return s[0]; }' + #10));
  except
    on E: Exception do
    begin
      Check(False, 'zb25b: fixture written: %s', [E.Message]);
      Exit;
    end;
  end;
  LErrors := TErrors.Create();
  try
    DoRunProbe('zb25b', 'only16.cpp', False, False, LErrors, LOk, LExitCode, LOutput);
    LFound := False;
    for LError in LErrors.GetItems() do
    begin
      if (LError.Severity = esError) and
        LError.Message.Contains('is not a valid Unicode character name') then
        LFound := True;
    end;
    Check((not LOk) and LFound, 'zb25b: clang: 16.0 name unknown');
  finally
    LErrors.Free();
  end;
end;

end.
