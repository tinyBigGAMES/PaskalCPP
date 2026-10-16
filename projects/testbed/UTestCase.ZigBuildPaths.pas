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
  UTestCase.ZigBuildPaths - ZigBuild path-setting tests

  TTestCase suite for the one entry every TPCZigBuild path setting goes
  through (DoAcceptPath, R18 G1): a path no file routine can take is error
  ZB0020, never a raise, and the setting is not stored; a good one is stored
  resolved, once, so two spellings of one file are one entry, and the paths
  in a loaded build.zig resolve against its own directory. A bad project
  name and a bad toolchain path are refused the same way (nothing saved).
  An output folder longer than zig can build in (PC_ZIG_BUILD_ROOT_MAX) is
  ZB0021 from SetOutputPath and LoadBuildFile, and nothing is stored or
  cleared; one at the limit is taken (it builds: hooked zb19_root_limit).
  dia_emit: a .dia path past the plain limit is handed to clang in its
  plain spelling (R41; hooked zb20_long_names builds it). no_output_path:
  without an output path ClearCache, ClearOutput and Run report ZB0001 and
  leave the folders in the current directory alone (R44).
  build.zig forms (A4): a generated build.zig loads back to the same text
  byte for byte (every artifact kind, target family, optimize level and
  setting kind, R20 R24); a path on another drive is written absolute (R30);
  a name or define with '"', '\', a tab or non-ASCII text is escaped and
  comes back as it was (R48, UTF-8 load); an unknown line is one ZB0023
  warning; a target that is not zig's is ZB0022 and is not stored (R31).
  Copy requests (A3): an empty one is ZB0024; a copy-DLL list with a missing
  file (ZB0026, once for two spellings) or two DLLs of one name (ZB0025)
  stops Process before the build; build.zig names each artifact kind's
  install folder (layout_emit).
  Run (A5): run_codes - a library, no project name, a missing executable and
  a file that cannot start are each their own error (ZB0027 ZB0028 ZB0029
  ZB0030), never ZB0005 or a made-up exit code. run_program runs the prebuilt
  argv fixture (tests\probe\utils\res) from a folder with a space on Windows
  and on Linux (WSL): the same literal argv on both, exit 7 is ZB0031 with
  the code kept; an executable past the launch limit runs.
  build.toml (A6): config_file - Create and SetBuildConfigPath read and write
  nothing; on first use an absent file becomes the template (UTF-8, no BOM,
  LF only, R1); a malformed file (its position stated once, R2) or a
  toolchain_path no file routine can take (R18 G3, it raised) is one ZB0017
  warning, the default is used and the file is left as it was; a set value
  reads back. toolchain_launch - a zig.exe past the launch limit is found
  (R43); a zig.exe that cannot start is ZB0032.
  No zig run: build.zig is written by SaveBuildFile and read back. Scratch
  files under tests\probe\zbp, written by the tests themselves.

  Dependencies: StdApp.TestCase, StdApp.Base, StdApp.Utils,
    PaskalCPP.ZigBuild
===============================================================================}

unit UTestCase.ZigBuildPaths;

interface

uses
  StdApp.TestCase;

type

  { TPCZigBuildPathTests }
  TPCZigBuildPathTests = class(TTestCase)
  private
    // One test per concern; Create registers each under its CLI name
    procedure DoTestBadPaths();
    procedure DoTestResolvedOnce();
    procedure DoTestProjectName();
    procedure DoTestLoadRelative();
    procedure DoTestToolchainBad();
    procedure DoTestRootLimit();
    procedure DoTestDiaEmit();
    procedure DoTestNoOutputPath();
    procedure DoTestBuildZigRoundTrip();
    procedure DoTestBuildZigCrossDrive();
    procedure DoTestBuildZigEscape();
    procedure DoTestSourceGate();
    procedure DoTestBuildZigUnknownLine();
    procedure DoTestTargetCheck();
    procedure DoTestCopyRequests();
    procedure DoTestCopyDllChecks();
    procedure DoTestLayoutEmit();
    procedure DoTestRunCodes();
    procedure DoTestRunProgram();
    procedure DoTestConfigFile();
    procedure DoTestToolchainLaunch();
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
  PaskalCPP.ZigBuild,
  PaskalCPP.ZigBuild.Targets;

const
  { TEST_BAD_PATH }
  // '<' is a character Windows forbids in a path: ResolvePath raises on it
  TEST_BAD_PATH = 'in<valid';

function DoScratch(const AName: string): string;
begin
  // tests\probe\zbp\<AName>, emptied first; the exe sits two levels below
  // the project root (repo\bin). Empty when it cannot be prepared.
  Result := TUtils.ResolvePath('..\..\tests\probe\zbp\' + AName,
    TPath.GetDirectoryName(ParamStr(0)));
  try
    if TDirectory.Exists(Result) then
      TDirectory.Delete(Result, True);
    TDirectory.CreateDirectory(Result);
  except
    on Exception do
      Result := '';
  end;
end;

function DoPathOfLength(const ABase: string; const ALength: Integer): string;
begin
  // ABase + '/' + one segment padded so the whole path has ALength characters
  Result := ABase + '/' + StringOfChar('d', ALength - Length(ABase) - 1);
end;

function DoWriteBuildZig(const ADir: string; const AProjectName: string): Boolean;
var
  LText: string;
begin
  // ADir\build.zig naming project AProjectName; False when it cannot be written
  LText := Format('''
    const exe = b.addExecutable(.{
        .name = "%s",
  ''', [AProjectName]);
  try
    TDirectory.CreateDirectory(ADir);
    TFile.WriteAllText(TPath.Combine(ADir, 'build.zig'), LText);
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

function DoCountCode(const AErrors: TErrors; const ACode: string): Integer;
var
  LError: TError;
begin
  // Errors (not warnings) with this code
  Result := 0;
  for LError in AErrors.GetItems() do
  begin
    if (LError.Severity = esError) and (LError.Code = ACode) then
      Inc(Result);
  end;
end;

function DoBuildZigText(const AZig: TPCZigBuild): string;
begin
  // The build.zig SaveBuildFile writes for AZig's current settings; '' when
  // it cannot be written or read back
  Result := '';
  if not AZig.SaveBuildFile() then
    Exit;
  try
    Result := TFile.ReadAllText(TPath.Combine(AZig.GetOutputPath(), 'build.zig'));
  except
    on Exception do
      Result := '';
  end;
end;

function DoReadBytes(const APath: string): TBytes;
begin
  // The file's bytes; nil when it cannot be read
  try
    Result := TFile.ReadAllBytes(APath);
  except
    on Exception do
      Result := nil;
  end;
end;

function DoSameBytes(const ABytes1: TBytes; const ABytes2: TBytes): Boolean;
begin
  Result := Length(ABytes1) = Length(ABytes2);
  if Result and (Length(ABytes1) > 0) then
    Result := CompareMem(@ABytes1[0], @ABytes2[0], Length(ABytes1));
end;

{ TPCZigBuildPathTests }

constructor TPCZigBuildPathTests.Create();
begin
  inherited;

  Title := 'ZigBuildPaths';
  RegisterTest('bad_paths', DoTestBadPaths);
  RegisterTest('resolved_once', DoTestResolvedOnce);
  RegisterTest('project_name', DoTestProjectName);
  RegisterTest('load_relative', DoTestLoadRelative);
  RegisterTest('toolchain_bad', DoTestToolchainBad);
  RegisterTest('root_limit', DoTestRootLimit);
  RegisterTest('dia_emit', DoTestDiaEmit);
  RegisterTest('no_output_path', DoTestNoOutputPath);
  RegisterTest('build_zig_round_trip', DoTestBuildZigRoundTrip);
  RegisterTest('build_zig_cross_drive', DoTestBuildZigCrossDrive);
  RegisterTest('build_zig_escape', DoTestBuildZigEscape);
  RegisterTest('source_gate', DoTestSourceGate);
  RegisterTest('build_zig_unknown_line', DoTestBuildZigUnknownLine);
  RegisterTest('target_check', DoTestTargetCheck);
  RegisterTest('copy_requests', DoTestCopyRequests);
  RegisterTest('copy_dll_checks', DoTestCopyDllChecks);
  RegisterTest('layout_emit', DoTestLayoutEmit);
  RegisterTest('run_codes', DoTestRunCodes);
  RegisterTest('run_program', DoTestRunProgram);
  RegisterTest('config_file', DoTestConfigFile);
  RegisterTest('toolchain_launch', DoTestToolchainLaunch);
end;

procedure TPCZigBuildPathTests.Run();
begin
  inherited;
end;

procedure TPCZigBuildPathTests.DoTestBadPaths();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LDir: string;
  LText: string;
begin
  // Every path setting given a path no file routine can take: one ZB0020
  // error each, never a raise, and nothing stored
  LDir := DoScratch('bad');
  Check(LDir <> '', 'bad paths: scratch dir prepared');
  if LDir = '' then
    Exit;

  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetOutputPath(LDir);
      LZig.SetOutputPath(TEST_BAD_PATH);
      LZig.AddSourceFile(TEST_BAD_PATH);
      LZig.AddSourceFiles(TEST_BAD_PATH, ['a.cpp']);
      LZig.AddSourceFiles(LDir, [TEST_BAD_PATH]);
      LZig.RemoveSourceFile(TEST_BAD_PATH);
      LZig.AddIncludePath(TEST_BAD_PATH);
      LZig.AddLibraryPath(TEST_BAD_PATH);
      LZig.AddCopyDLL(TEST_BAD_PATH);
      LZig.AddPostBuildCopy(TEST_BAD_PATH, LDir);
      LZig.AddPublishArtifact(TEST_BAD_PATH);
      LZig.SetExeIcon(TEST_BAD_PATH);

      Check((LErrors.ErrorCount() = 11) and
        (DoCountCode(LErrors, PC_ERR_ZIGBUILD_BADPATH) = 11),
        'bad paths: one ZB0020 error per setting (11)');
      Check(LErrors.GetItems()[LErrors.Count() - 1].Message.Contains(TEST_BAD_PATH),
        'bad paths: the message names the path');
      Check(TUtils.SamePath(LZig.GetOutputPath(), LDir),
        'bad paths: the output path set before is kept');
      Check(LZig.GetSourceFileCount() = 0, 'bad paths: no source stored');
      Check(LZig.GetExeIcon() = '', 'bad paths: no icon stored');

      // Include and library paths: build.zig names neither
      LZig.SetProjectName('zbp');
      LZig.AddSourceFile(TPath.Combine(LDir, 'a.cpp'));
      LText := DoBuildZigText(LZig);
      Check((LText <> '') and (not LText.Contains('addIncludePath')) and
        (not LText.Contains('addLibraryPath')),
        'bad paths: no include or library path stored');
      Check(LErrors.ErrorCount() = 11, 'bad paths: build.zig written without new errors');
    finally
      LZig.Free();
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestResolvedOnce();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LDir: string;
  LText: string;
begin
  // A path is stored resolved, once: a relative path against the CWD, two
  // spellings of one file are one entry, a base-relative list resolves
  // against its base, and build.zig names a path absolute (R30)
  LDir := DoScratch('once');
  Check(LDir <> '', 'resolved once: scratch dir prepared');
  if LDir = '' then
    Exit;

  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetOutputPath('rel_out');
      Check(LZig.GetOutputPath() = TUtils.ResolvePath('rel_out'),
        'resolved once: a relative output path is stored resolved');

      LZig.AddSourceFile('rel\a.cpp');
      LZig.AddSourceFile(TPath.Combine(TDirectory.GetCurrentDirectory(), 'rel\a.cpp'));
      LZig.AddSourceFile('REL/A.CPP');
      Check((LZig.GetSourceFileCount() = 1) and
        (LZig.GetSourceFile(0) = TUtils.ResolvePath('rel\a.cpp')),
        'resolved once: three spellings of one file are one entry');
      LZig.RemoveSourceFile('./rel/a.cpp');
      Check(LZig.GetSourceFileCount() = 0,
        'resolved once: removed through another spelling');

      LZig.AddSourceFiles(LDir, ['a.cpp', 'sub\b.c', '']);
      Check((LZig.GetSourceFileCount() = 2) and
        (LZig.GetSourceFile(0) = TUtils.ResolvePath('a.cpp', LDir)) and
        (LZig.GetSourceFile(1) = TUtils.ResolvePath('sub\b.c', LDir)),
        'resolved once: a base-relative list resolves against its base, empty skipped');

      LZig.SetOutputPath(LDir);
      LZig.SetProjectName('zbp');
      LZig.AddIncludePath(TPath.Combine(LDir, 'inc'));
      LText := DoBuildZigText(LZig);
      Check(LText.Contains('addIncludePath(.{ .cwd_relative = "' +
        TUtils.ResolvePath(TPath.Combine(LDir, 'inc')) + '" })'),
        'resolved once: build.zig names the include path absolute (R30)');
      Check(LErrors.ErrorCount() = 0, 'resolved once: no errors');
    finally
      LZig.Free();
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestProjectName();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
begin
  // The project name becomes the artifact's file name: a name no file can
  // take is ZB0020 and the previous name is kept; empty clears it
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetProjectName('zbp_ok');
      LZig.SetProjectName('a/b');
      LZig.SetProjectName('a\b');
      LZig.SetProjectName('a<b');
      LZig.SetProjectName('a:b');
      Check((DoCountCode(LErrors, PC_ERR_ZIGBUILD_BADPATH) = 4) and
        (LErrors.ErrorCount() = 4), 'project name: one ZB0020 per bad name (4)');
      Check(LZig.GetProjectName() = 'zbp_ok', 'project name: the good name is kept');
      LZig.SetProjectName('');
      Check((LZig.GetProjectName() = '') and (LErrors.ErrorCount() = 4),
        'project name: empty clears it without an error');
    finally
      LZig.Free();
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestLoadRelative();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LDir: string;
  LBuildZig: string;
  LLoaded: Boolean;
  LText: string;
begin
  // A loaded build.zig's paths resolve against its own directory, not the
  // CWD; a path in it no file routine can take is ZB0020, the rest loads
  LDir := DoScratch('load');
  Check(LDir <> '', 'load relative: scratch dir prepared');
  if LDir = '' then
    Exit;

  LBuildZig := TPath.Combine(LDir, 'build.zig');
  LText := '''
    const exe = b.addExecutable(.{
        .name = "zbp",
    exe.root_module.addIncludePath(.{ .cwd_relative = "inc" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "in<c" });
        .root = .{ .cwd_relative = "src" },
        .files = &.{
            "a.cpp"
        },
  ''';
  try
    TFile.WriteAllText(LBuildZig, LText);
  except
    on Exception do
    begin
      Check(False, 'load relative: build.zig written');
      Exit;
    end;
  end;

  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LLoaded := LZig.LoadBuildFile(LBuildZig);
      Check(LLoaded, 'load relative: loaded');
      Check((LErrors.ErrorCount() = 1) and
        (DoCountCode(LErrors, PC_ERR_ZIGBUILD_BADPATH) = 1),
        'load relative: the bad include path is the one ZB0020');
      Check(TUtils.SamePath(LZig.GetOutputPath(), LDir),
        'load relative: the build root is the build file''s directory');
      Check((LZig.GetSourceFileCount() = 1) and
        (LZig.GetSourceFile(0) = TUtils.ResolvePath('src/a.cpp', LDir)),
        'load relative: a source resolves against the build root');

      LText := DoBuildZigText(LZig);
      Check(LText.Contains('addIncludePath(.{ .cwd_relative = "' +
        TUtils.ResolvePath('inc', LDir) + '" })') and
        (not LText.Contains('in<c')),
        'load relative: the good include path round-trips, the bad one is gone');
    finally
      LZig.Free();
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestToolchainBad();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LConfig: string;
  LBefore: string;
  LBytes: TBytes;
begin
  // A toolchain path no file routine can take is ZB0020: the toolchain
  // path is unchanged and build.toml is not rewritten
  LConfig := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'build.toml');
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LBefore := LZig.GetToolchainPath();
      LBytes := DoReadBytes(LConfig);
      Check(Length(LBytes) > 0, 'toolchain bad: build.toml present before');

      LZig.SetToolchainPath(TEST_BAD_PATH);
      Check((DoCountCode(LErrors, PC_ERR_ZIGBUILD_BADPATH) = 1) and
        (LErrors.ErrorCount() = 1), 'toolchain bad: one ZB0020');
      Check(LZig.GetToolchainPath() = LBefore, 'toolchain bad: path unchanged');
      Check(DoSameBytes(DoReadBytes(LConfig), LBytes),
        'toolchain bad: build.toml not rewritten');
    finally
      LZig.Free();
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestRootLimit();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LBase: string;
  LAt: string;
  LPast: string;
  LLong: string;
  LMessage: string;
begin
  // zig cannot build in an output folder longer than PC_ZIG_BUILD_ROOT_MAX:
  // SetOutputPath and LoadBuildFile refuse one with ZB0021 and keep what
  // they had; a folder at the limit is taken
  LBase := DoScratch('limit');
  Check(LBase <> '', 'root limit: scratch dir prepared');
  if LBase = '' then
    Exit;

  LAt := DoPathOfLength(LBase, PC_ZIG_BUILD_ROOT_MAX);
  LPast := DoPathOfLength(LBase, PC_ZIG_BUILD_ROOT_MAX + 1);
  // Past PATH_PLAIN_MAX: stored resolved in the long-path spelling
  LLong := DoPathOfLength(LBase, 300);
  Check(DoWriteBuildZig(LAt, 'zbp_at') and DoWriteBuildZig(LPast, 'zbp_past'),
    'root limit: build files written');

  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetOutputPath(LAt);
      Check((LErrors.Count() = 0) and TUtils.SamePath(LZig.GetOutputPath(), LAt),
        'root limit: a folder at the limit is taken');

      LZig.SetOutputPath(LPast);
      Check((LErrors.ErrorCount() = 1) and
        (DoCountCode(LErrors, PC_ERR_ZIGBUILD_ROOTTOOLONG) = 1),
        'root limit: one past the limit is one ZB0021');
      Check(TUtils.SamePath(LZig.GetOutputPath(), LAt),
        'root limit: the folder set before is kept');
      LMessage := LErrors.GetItems()[LErrors.Count() - 1].Message;
      Check(LMessage.Contains(LPast) and
        LMessage.Contains(IntToStr(PC_ZIG_BUILD_ROOT_MAX + 1)) and
        LMessage.Contains(IntToStr(PC_ZIG_BUILD_ROOT_MAX)),
        'root limit: the message names the folder, its length and the limit');

      LZig.SetOutputPath(LLong);
      Check((LErrors.ErrorCount() = 2) and
        (DoCountCode(LErrors, PC_ERR_ZIGBUILD_ROOTTOOLONG) = 2),
        'root limit: a long-path spelling is measured plain: ZB0021, not ZB0020');
      Check(TUtils.SamePath(LZig.GetOutputPath(), LAt),
        'root limit: the folder is still kept');

      Check(LZig.LoadBuildFile(TPath.Combine(LAt, 'build.zig')) and
        (LErrors.ErrorCount() = 2),
        'root limit: a build file in a folder at the limit loads');
      Check(LZig.GetProjectName() = 'zbp_at', 'root limit: its project name is read');

      Check(not LZig.LoadBuildFile(TPath.Combine(LPast, 'build.zig')),
        'root limit: a build file one past the limit is refused');
      Check((LErrors.ErrorCount() = 3) and
        (DoCountCode(LErrors, PC_ERR_ZIGBUILD_ROOTTOOLONG) = 3),
        'root limit: the refused build file is one ZB0021');
      Check(TUtils.SamePath(LZig.GetOutputPath(), LAt) and
        (LZig.GetProjectName() = 'zbp_at'),
        'root limit: nothing cleared or replaced by the refused file');
    finally
      LZig.Free();
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestDiaEmit();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LBase: string;
  LRoot: string;
  LName: string;
  LText: string;
  LFlag: string;
begin
  // A .dia path past the plain limit (output folder at PC_ZIG_BUILD_ROOT_MAX,
  // source name 80: 310 characters) is handed to clang in its plain spelling
  // with forward slashes, never the long-path spelling: only ZigBuild's own
  // file routines read it long (R41)
  LBase := DoScratch('dia');
  Check(LBase <> '', 'dia emit: scratch dir prepared');
  if LBase = '' then
    Exit;

  LRoot := DoPathOfLength(LBase, PC_ZIG_BUILD_ROOT_MAX);
  LName := StringOfChar('s', 76) + '.cpp';
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetOutputPath(LRoot);
      LZig.AddSourceFile(LRoot + '/' + LName);
      LText := DoBuildZigText(LZig);
    finally
      LZig.Free();
    end;

    Check((LErrors.Count() = 0) and (LText <> ''), 'dia emit: build.zig written');
    LFlag := '"-serialize-diagnostic-file", "-Xclang", "' + LRoot + '/pcpp-diag/' +
      LName + '.';
    Check(LText.Contains(LFlag), 'dia emit: the .dia flag names the plain path');
    Check((not LText.Contains('//?/')) and (not LText.Contains('\\?\')),
      'dia emit: no long-path spelling in build.zig');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestNoOutputPath();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LDir: string;
  LOldDir: string;
  LCache: string;
  LOutBin: string;
  LCleared: Boolean;
  LOutCleared: Boolean;
  LRan: Boolean;
begin
  // Without an output path there is no build root: ClearCache, ClearOutput
  // and Run report ZB0001 and touch nothing. The current directory holds a
  // .zig-cache and a zig-out\bin\<exe> that must be left alone (R44: the two
  // folders were deleted, and Run looked for the exe there)
  LDir := DoScratch('nooutput');
  Check(LDir <> '', 'no output path: scratch dir prepared');
  if LDir = '' then
    Exit;

  LCache := TPath.Combine(LDir, '.zig-cache');
  LOutBin := TPath.Combine(LDir, 'zig-out\bin');
  try
    TDirectory.CreateDirectory(LCache);
    TDirectory.CreateDirectory(LOutBin);
    TFile.WriteAllText(TPath.Combine(LOutBin, 'zbp_none.exe'), 'x');
  except
    on E: Exception do
    begin
      Check(False, 'no output path: fixture folders made: %s', [E.Message]);
      Exit;
    end;
  end;

  LOldDir := TDirectory.GetCurrentDirectory();
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetProjectName('zbp_none');
      TDirectory.SetCurrentDirectory(LDir);
      try
        LCleared := LZig.ClearCache();
        LOutCleared := LZig.ClearOutput();
        LRan := LZig.Run();
      finally
        TDirectory.SetCurrentDirectory(LOldDir);
      end;
    finally
      LZig.Free();
    end;

    Check((not LCleared) and (not LOutCleared) and (not LRan),
      'no output path: none of the three reports success');
    Check((LErrors.ErrorCount() = 3) and
      (DoCountCode(LErrors, PC_ERR_ZIGBUILD_NOOUTPUTPATH) = 3),
      'no output path: three ZB0001');
    Check(TDirectory.Exists(LCache) and TDirectory.Exists(LOutBin),
      'no output path: the folders in the current directory are left alone');
  finally
    LErrors.Free();
  end;
end;

function DoRoundTrip(const ADir: string; const ASetup: TProc<TPCZigBuild>;
  out AFirst: string; out ASecond: string; out AItems: Integer): Boolean;
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
begin
  // build.zig written for ASetup's settings, then loaded into a fresh driver
  // and written again; AItems = every error and warning on the way
  AFirst := '';
  ASecond := '';
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetOutputPath(ADir);
      ASetup(LZig);
      AFirst := DoBuildZigText(LZig);
    finally
      LZig.Free();
    end;
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      if LZig.LoadBuildFile(TPath.Combine(ADir, 'build.zig')) then
        ASecond := DoBuildZigText(LZig);
    finally
      LZig.Free();
    end;
    AItems := LErrors.Count();
    Result := (AFirst <> '') and (AFirst = ASecond);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestBuildZigRoundTrip();
var
  LDir: string;
  LFirst: string;
  LSecond: string;
  LItems: Integer;
  LCase: Integer;
  LKind: Integer;
  LOk: Boolean;
begin
  // Every artifact kind, a target per OS family (one without an ABI), every
  // optimize level and every setting kind build.zig carries
  LDir := DoScratch('forms');
  Check(LDir <> '', 'round trip: scratch dir prepared');
  if LDir = '' then
    Exit;

  for LCase := 1 to 4 do
  begin
    LKind := LCase;
    LOk := DoRoundTrip(LDir,
      procedure(AZig: TPCZigBuild)
      begin
        AZig.SetProjectName('zbf');
        AZig.AddSourceFile(TPath.Combine(LDir, 'a.cpp'));
        case LKind of
          1:
            begin
              AZig.SetTarget('x86_64-windows-gnu');
              AZig.SetOptimizeLevel(olDebug);
            end;
          2:
            begin
              AZig.SetSubsystem(stGUI);
              AZig.SetOptimizeLevel(olReleaseSafe);
              AZig.AddIncludePath(TPath.Combine(LDir, 'inc'));
              AZig.AddLibraryPath(TPath.Combine(LDir, 'lib'));
              AZig.AddLinkLibrary('user32');
              AZig.SetDefine('A');
              AZig.SetDefine('B', '2');
              AZig.UnsetDefine('C');
              AZig.AddSourceFile(TPath.Combine(LDir, 'sub\b.c'));
              AZig.AddSourceFile(TPath.Combine(LDir, 'c.S'));
              AZig.AddSourceFile(TPath.Combine(LDir, 'd.ll'));
            end;
          3:
            begin
              AZig.SetBuildMode(bmLib);
              AZig.SetTarget(ARCH_X86_64, OS_LINUX, ABI_GNU);
              AZig.SetOptimizeLevel(olReleaseFast);
            end;
          4:
            begin
              AZig.SetBuildMode(bmDll);
              AZig.SetTarget('aarch64-macos');
              AZig.SetOptimizeLevel(olReleaseSmall);
            end;
        end;
      end, LFirst, LSecond, LItems);
    Check(LOk and (LItems = 0), 'round trip: case %d loads back byte for byte (%d items)' +
      sLineBreak + '--- written' + sLineBreak + '%s' + sLineBreak + '--- after a load' +
      sLineBreak + '%s', [LCase, LItems, LFirst, LSecond]);
  end;
end;

procedure TPCZigBuildPathTests.DoTestBuildZigCrossDrive();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LDir: string;
  LText: string;
begin
  // A source and an include path on another drive than the build root: no
  // relative form exists, build.zig names them absolute (R30). Text only:
  // the drive need not exist (the hooked zb22 builds from one)
  LDir := DoScratch('xdrive');
  Check(LDir <> '', 'cross drive: scratch dir prepared');
  if LDir = '' then
    Exit;

  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetOutputPath(LDir);
      LZig.SetProjectName('zbx');
      LZig.AddSourceFile('Q:\x\a.cpp');
      LZig.AddIncludePath('Q:\inc');
      LText := DoBuildZigText(LZig);
    finally
      LZig.Free();
    end;
    Check(LErrors.Count() = 0, 'cross drive: no errors (%d)', [LErrors.Count()]);
    Check(LText.Contains('.root = .{ .cwd_relative = "Q:/x" },') and
      LText.Contains('            "a.cpp"'), 'cross drive: the TU under its own folder');
    Check(LText.Contains('addIncludePath(.{ .cwd_relative = "Q:/inc" })'),
      'cross drive: the include path absolute');
    Check(not LText.Contains('..'), 'cross drive: no relative path left');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestBuildZigEscape();
var
  LDir: string;
  LFirst: string;
  LSecond: string;
  LItems: Integer;
  LOk: Boolean;
  LText: string;
begin
  // A project name and defines with '"', '\', a tab and non-ASCII text are
  // escaped in build.zig and load back as they were (R48, UTF-8); a target
  // name that starts with a digit is a quoted enum literal
  LDir := DoScratch('escape');
  Check(LDir <> '', 'escape: scratch dir prepared');
  if LDir = '' then
    Exit;

  LOk := DoRoundTrip(LDir,
    procedure(AZig: TPCZigBuild)
    begin
      AZig.SetProjectName('pr' + #$00F3 + 'j');
      AZig.AddSourceFile(TPath.Combine(LDir, 'a.cpp'));
      AZig.SetDefine('MSG', '"hi \ there"');
      AZig.SetDefine('U', #$00E9 + #$4E2D);
      AZig.SetDefine('T', 'a' + #9 + 'b');
      AZig.SetTarget('arm-3ds');
    end, LFirst, LSecond, LItems);
  Check(LOk and (LItems = 0), 'escape: loads back byte for byte (%d items)' + sLineBreak +
    '--- written' + sLineBreak + '%s' + sLineBreak + '--- after a load' + sLineBreak + '%s',
    [LItems, LFirst, LSecond]);
  Check(LFirst.Contains('"-DMSG=\"hi \\ there\""'), 'escape: the quote and backslash escaped');
  Check(LFirst.Contains('"-DT=a\tb"'), 'escape: the tab escaped');
  Check(LFirst.Contains('"-DU=' + #$00E9 + #$4E2D + '"'), 'escape: non-ASCII as it is');
  Check(LFirst.Contains('.os_tag = .@"3ds"'), 'escape: a digit-led enum name quoted');
  Check(ZigStringValue(ZigStringLiteral('a"b\c' + #1 + #127), LText) and
    (LText = 'a"b\c' + #1 + #127), 'escape: control characters round-trip');
  Check(not ZigStringValue('"a"b"', LText), 'escape: an unescaped quote inside is not one literal');
  Check(not ZigStringValue('"a\q"', LText), 'escape: an unknown escape is not read');
end;

function DoFlagsAfter(const AText: string; const AFileLiteral: string): string;
var
  LPos: Integer;
  LFlags: Integer;
  LEnd: Integer;
begin
  // The .flags line of the addCSourceFiles block naming AFileLiteral (the
  // block writes .files, then .flags); '' = no such block
  Result := '';
  LPos := AText.IndexOf(AFileLiteral);
  if LPos < 0 then
    Exit;
  LFlags := AText.IndexOf(PC_ZIG_FORM_FLAGS_PRE, LPos);
  if LFlags < 0 then
    Exit;
  LEnd := AText.IndexOf(#10, LFlags);
  if LEnd < 0 then
    LEnd := AText.Length;
  Result := AText.Substring(LFlags, LEnd - LFlags);
end;

procedure TPCZigBuildPathTests.DoTestSourceGate();
var
  LDir: string;
  LFirst: string;
  LSecond: string;
  LItems: Integer;
  LOk: Boolean;
  LErrors: TErrors;
  LZig: TPCZigBuild;
begin
  // PC_SOURCE_EXTS, exact case (@addsourcefile, 2026-10-11): a .C file is
  // C++ (clang reads the name; the old case-insensitive match gave it the C
  // group's -std=gnu23, a hard error), .c is C, .S / .s assembly, .ll IR;
  // the groups survive a load of the written build.zig
  LDir := DoScratch('gate');
  Check(LDir <> '', 'source gate: scratch dir prepared');
  if LDir = '' then
    Exit;

  LOk := DoRoundTrip(LDir,
    procedure(AZig: TPCZigBuild)
    begin
      AZig.SetProjectName('gate');
      AZig.AddSourceFile(TPath.Combine(LDir, 'upper.C'));
      AZig.AddSourceFile(TPath.Combine(LDir, 'lower.c'));
      AZig.AddSourceFile(TPath.Combine(LDir, 'plus.c++'));
      AZig.AddSourceFile(TPath.Combine(LDir, 'pre.S'));
      AZig.AddSourceFile(TPath.Combine(LDir, 'ir.ll'));
    end, LFirst, LSecond, LItems);
  Check(LOk and (LItems = 0), 'source gate: loads back byte for byte (%d items)', [LItems]);
  Check(DoFlagsAfter(LFirst, '"upper.C"').Contains('-std=gnu++23'),
    'source gate: upper.C is C++: ' + DoFlagsAfter(LFirst, '"upper.C"'));
  Check(DoFlagsAfter(LFirst, '"lower.c"').Contains('-std=gnu23"'),
    'source gate: lower.c is C: ' + DoFlagsAfter(LFirst, '"lower.c"'));
  Check(DoFlagsAfter(LFirst, '"plus.c++"').Contains('-std=gnu++23'),
    'source gate: plus.c++ is C++: ' + DoFlagsAfter(LFirst, '"plus.c++"'));
  Check(not DoFlagsAfter(LFirst, '"pre.S"').Contains('-std='),
    'source gate: pre.S is assembly (no -std): ' + DoFlagsAfter(LFirst, '"pre.S"'));
  Check(not DoFlagsAfter(LFirst, '"ir.ll"').Contains('-std='),
    'source gate: ir.ll is LLVM IR (no -std): ' + DoFlagsAfter(LFirst, '"ir.ll"'));

  // A header and a name clang would take as linker input: ZB0033 each, not stored
  LErrors := TErrors.Create();
  LZig := TPCZigBuild.Create();
  try
    // Both reports kept (a fresh TErrors keeps one error: the build's budget)
    LErrors.SetMaxErrors(10);
    LZig.SetErrors(LErrors);
    LZig.AddSourceFile(TPath.Combine(LDir, 'a.h'));
    LZig.AddSourceFile(TPath.Combine(LDir, 'notes.txt'));
    LZig.AddSourceFile(TPath.Combine(LDir, 'ok.cpp'));
    Check((DoCountCode(LErrors, PC_ERR_ZIGBUILD_NOTSOURCE) = 2) and (LErrors.GetItems().Count = 2),
      'source gate: a.h and notes.txt are ZB0033, nothing else (%d reports)', [LErrors.GetItems().Count]);
    Check(LZig.GetSourceFileCount() = 1, 'source gate: only ok.cpp is stored (%d)',
      [LZig.GetSourceFileCount()]);
  finally
    LZig.Free();
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestBuildZigUnknownLine();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LDir: string;
  LBuildZig: string;
  LItem: TError;
begin
  // A line LoadBuildFile does not know is one ZB0023 warning naming its
  // line; the lines around it load
  LDir := DoScratch('unknown');
  Check(LDir <> '', 'unknown line: scratch dir prepared');
  if LDir = '' then
    Exit;

  LBuildZig := TPath.Combine(LDir, 'build.zig');
  try
    TFile.WriteAllText(LBuildZig, '''
      const exe = b.addExecutable(.{
          .name = "zbu",
          .something = else,
          .linkage = .dynamic,
      ''');
  except
    on Exception do
    begin
      Check(False, 'unknown line: build.zig written');
      Exit;
    end;
  end;

  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      Check(LZig.LoadBuildFile(LBuildZig), 'unknown line: loaded');
      Check((LZig.GetProjectName() = 'zbu') and (LZig.GetBuildMode() = bmDll),
        'unknown line: the lines around it load');
    finally
      LZig.Free();
    end;
    Check(LErrors.Count() = 1, 'unknown line: exactly 1 item (%d)', [LErrors.Count()]);
    if LErrors.Count() = 1 then
    begin
      LItem := LErrors.GetItems()[0];
      Check((LItem.Severity = esWarning) and (LItem.Code = PC_ERR_ZIGBUILD_WRNBUILDLINE) and
        LItem.Message.Contains('Line 3 ') and LItem.Message.Contains('.something = else,'),
        'unknown line: ZB0023 naming line 3 (%s)', [LItem.Message]);
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestTargetCheck();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
begin
  // A target whose parts are not zig's names is ZB0022 and is not stored
  // (R31); zig's names are taken, with or without an ABI
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetTarget('x86_64');
      LZig.SetTarget('X86_64-windows-gnu');
      LZig.SetTarget('x86_64-windows-gnu ');
      LZig.SetTarget('x86_64-windos-gnu');
      LZig.SetTarget('x86_64-windows-gnu-extra');
      LZig.SetTarget('x86_64', 'linux', 'gnux');
      Check((DoCountCode(LErrors, PC_ERR_ZIGBUILD_BADTARGET) = 6) and
        (LErrors.Count() = 6), 'target check: one ZB0022 per bad target (6, got %d)',
        [LErrors.Count()]);
      Check(LZig.GetTarget() = PC_DEFAULT_TARGET, 'target check: the target is unchanged');

      LZig.SetTarget('aarch64-macos');
      Check(LZig.GetTarget() = 'aarch64-macos', 'target check: a triple without an ABI');
      LZig.SetTarget(ARCH_X86_64, OS_LINUX, ABI_MUSL);
      Check((LZig.GetTarget() = 'x86_64-linux-musl') and (LErrors.Count() = 6),
        'target check: the constants make a triple, no new error');
    finally
      LZig.Free();
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestCopyRequests();
var
  LErrors: TErrors;
  LZig: TPCZigBuild;
begin
  // An empty copy-DLL or publish source is a request that cannot be met:
  // one ZB0024 each, nothing stored (R15 P3)
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.AddCopyDLL('');
      LZig.AddCopyDLL('   ');
      LZig.AddPostBuildCopy('', '.');
      Check((DoCountCode(LErrors, PC_ERR_ZIGBUILD_EMPTYSOURCE) = 3) and (LErrors.Count() = 3),
        'copy requests: one ZB0024 per empty source (3, got %d)', [LErrors.Count()]);
    finally
      LZig.Free();
    end;
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestCopyDllChecks();
var
  LDir: string;
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LOk: Boolean;
begin
  // The copy-DLL list is checked before the build: a missing DLL (named in
  // two spellings: one request) and two DLLs of one name each stop Process
  // with one error, and the build is not run (no pcpp-diag, nothing copied)
  LDir := DoScratch('copydll');
  Check(LDir <> '', 'copy dll: scratch dir prepared');
  if LDir = '' then
    Exit;
  try
    TFile.WriteAllText(TPath.Combine(LDir, 'a.cpp'), 'int main() { return 0; }');
    TDirectory.CreateDirectory(TPath.Combine(LDir, 'a'));
    TDirectory.CreateDirectory(TPath.Combine(LDir, 'b'));
    TFile.WriteAllText(TPath.Combine(LDir, 'a\x.dll'), 'dll a');
    TFile.WriteAllText(TPath.Combine(LDir, 'b\x.dll'), 'dll b');
  except
    on E: Exception do
    begin
      Check(False, 'copy dll: fixtures written: %s', [E.Message]);
      Exit;
    end;
  end;

  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetOutputPath(TPath.Combine(LDir, 'out1'));
      LZig.AddSourceFile(TPath.Combine(LDir, 'a.cpp'));
      LZig.AddCopyDLL(TPath.Combine(LDir, 'missing.dll'));
      LZig.AddCopyDLL(LDir + '/./missing.dll');
      LOk := LZig.Process(False);
    finally
      LZig.Free();
    end;
    Check((not LOk) and (LErrors.Count() = 1) and
      (DoCountCode(LErrors, PC_ERR_ZIGBUILD_SOURCEMISSING) = 1),
      'copy dll: a missing DLL is one ZB0026 and stops Process (%d items)', [LErrors.Count()]);
    Check(not TDirectory.Exists(TPath.Combine(LDir, 'out1\pcpp-diag')),
      'copy dll: the build was not run');

    LErrors.Clear();
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetOutputPath(TPath.Combine(LDir, 'out2'));
      LZig.AddSourceFile(TPath.Combine(LDir, 'a.cpp'));
      LZig.AddCopyDLL(TPath.Combine(LDir, 'a\x.dll'));
      LZig.AddCopyDLL(TPath.Combine(LDir, 'b\x.dll'));
      LOk := LZig.Process(False);
    finally
      LZig.Free();
    end;
    Check((not LOk) and (LErrors.Count() = 1) and
      (DoCountCode(LErrors, PC_ERR_ZIGBUILD_COLLISION) = 1),
      'copy dll: two DLLs of one name are one ZB0025 and stop Process (%d items)',
      [LErrors.Count()]);
    Check(not FileExists(TPath.Combine(LDir, 'out2\zig-out\bin\x.dll')),
      'copy dll: neither DLL was copied');
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestLayoutEmit();
var
  LDir: string;
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LText: string;
  LMode: TPCBuildMode;
  LWant: string;
  LArtifactDir: string;
  LArtifactPath: string;
  LArtifactFile: string;
  LWantDir: string;
begin
  // build.zig's install step names each artifact kind's folder (the layout
  // rule, R14): bin for an executable and a DLL, lib for a static library
  LDir := DoScratch('layout');
  Check(LDir <> '', 'layout emit: scratch dir prepared');
  if LDir = '' then
    Exit;
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);
    for LMode := Low(TPCBuildMode) to High(TPCBuildMode) do
    begin
      LZig := TPCZigBuild.Create();
      try
        LZig.SetErrors(LErrors);
        LZig.SetOutputPath(LDir);
        LZig.SetProjectName('zbl');
        LZig.SetBuildMode(LMode);
        LZig.AddSourceFile(TPath.Combine(LDir, 'a.cpp'));
        LText := DoBuildZigText(LZig);
        LArtifactDir := LZig.GetArtifactDir();
        LArtifactPath := LZig.GetArtifactPath();
        LArtifactFile := LZig.GetOutputFilename();
      finally
        LZig.Free();
      end;
      if LMode = bmLib then
      begin
        LWant := '.dest_dir = .{ .override = .lib },';
        LWantDir := TPath.Combine(TPath.Combine(LDir, 'zig-out'), 'lib');
      end
      else
      begin
        LWant := '.dest_dir = .{ .override = .bin },';
        LWantDir := TPath.Combine(TPath.Combine(LDir, 'zig-out'), 'bin');
      end;
      Check(LText.Contains(LWant) and (not LText.Contains('b.installArtifact(')),
        'layout emit: mode %d installs with "%s"', [Ord(LMode), LWant]);
      // GetArtifactDir / GetArtifactPath name the folder build.zig installs to
      Check(TUtils.SamePath(LArtifactDir, LWantDir) and
        TUtils.SamePath(LArtifactPath, TPath.Combine(LWantDir, LArtifactFile)),
        'layout emit: mode %d artifact dir %s, path %s', [Ord(LMode), LArtifactDir, LArtifactPath]);
    end;
    Check(LErrors.Count() = 0, 'layout emit: no errors (%d)', [LErrors.Count()]);
  finally
    LErrors.Free();
  end;
end;

const
  { PC_ZBP_RUN_ARGS }
  // Run arguments a shell would change: a variable, a quoted space, a
  // command separator (R35)
  PC_ZBP_RUN_ARGS = '$HOME "p q" ;x';

  { PC_ZBP_RUN_ARGV }
  // What the argv fixture prints for PC_ZBP_RUN_ARGS: the arguments as given
  PC_ZBP_RUN_ARGV: array[0..3] of string = (
    '[1]=$HOME',
    '[2]=p q',
    '[3]=;x',
    'argc=4'
  );

  { PC_ZBP_LAUNCH_LENGTH }
  // An executable path past the launch limit (PATH_LAUNCH_MAX, 259)
  PC_ZBP_LAUNCH_LENGTH = 280;

function DoUtilsFixture(const AName: string): string;
begin
  // A prebuilt fixture in tests\probe\utils\res (argv.exe, argv.elf)
  Result := TUtils.ResolvePath('..\..\tests\probe\utils\res\' + AName,
    TPath.GetDirectoryName(ParamStr(0)));
end;

function DoPlaceArtifact(const ADir: string; const AFileName: string;
  const AFixture: string): Boolean;
var
  LBin: string;
  LTarget: string;
begin
  // ADir\zig-out\bin\AFileName: a copy of fixture AFixture, or the text 'x'
  // (not a program) when AFixture is empty. False when it cannot be written.
  Result := False;
  try
    LBin := TUtils.ResolvePath(ADir + '\zig-out\bin');
    if not TUtils.EnsureDirectory(LBin) then
      Exit;
    LTarget := TUtils.JoinResolvedPath(LBin, AFileName);
    if AFixture = '' then
      TFile.WriteAllText(LTarget, 'x')
    else
      TFile.Copy(DoUtilsFixture(AFixture), LTarget, True);
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

function DoRunWith(const AOutputDir: string; const AMode: TPCBuildMode;
  const ATarget: string; const AProjectName: string; const AArguments: string;
  const AErrors: TErrors; out AOutput: string; out AExitCode: DWORD): Boolean;
var
  LZig: TPCZigBuild;
  LOutput: string;
begin
  // One Run of a ZigBuild set up for an artifact already in place (no zig):
  // AErrors holds this run's items only; the program's output and the exit
  // code ZigBuild kept
  AErrors.Clear();
  LOutput := '';
  LZig := TPCZigBuild.Create();
  try
    LZig.SetErrors(AErrors);
    LZig.SetOutputPath(AOutputDir);
    LZig.SetProjectName(AProjectName);
    LZig.SetBuildMode(AMode);
    if ATarget <> '' then
      LZig.SetTarget(ATarget);
    LZig.SetRunArguments(AArguments);
    LZig.SetOutputCallback(
      procedure(const ALine: string; const AData: Pointer)
      begin
        LOutput := LOutput + ALine;
      end, nil);
    Result := LZig.Run();
    AExitCode := LZig.GetLastExitCode();
  finally
    LZig.Free();
  end;
  AOutput := LOutput;
end;

function DoOnlyError(const AErrors: TErrors; const ACode: string): Boolean;
begin
  // Exactly one item, an error with this code
  Result := (AErrors.Count() = 1) and (DoCountCode(AErrors, ACode) = 1);
end;

function DoFirstMessage(const AErrors: TErrors): string;
begin
  // The first item's code and message, '' when there is none
  if AErrors.Count() = 0 then
    Result := ''
  else
    Result := AErrors.GetItems()[0].Code + ' ' + AErrors.GetItems()[0].Message;
end;

function DoMissingArgv(const AOutput: string): string;
var
  LLine: string;
begin
  // '' when AOutput holds every PC_ZBP_RUN_ARGV line, else the first missing
  Result := '';
  for LLine in PC_ZBP_RUN_ARGV do
  begin
    if not AOutput.Contains(LLine) then
    begin
      Result := LLine;
      Exit;
    end;
  end;
end;

procedure TPCZigBuildPathTests.DoTestRunCodes();
var
  LDir: string;
  LErrors: TErrors;
  LOutput: string;
  LExitCode: DWORD;
  LRan: Boolean;
begin
  // Each reason Run cannot run is its own error, and no exit code is made
  // up (R27 R39: these were ZB0005 'build failed' or ZB0001 'no output
  // path', a missing executable set exit code 2; R34: a program that could
  // not start was exit code 1 with no reason)
  LDir := DoScratch('run codes');
  Check(LDir <> '', 'run codes: scratch dir prepared');
  if LDir = '' then
    Exit;

  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);

    LRan := DoRunWith(LDir, bmLib, '', 'zbp_run', '', LErrors, LOutput, LExitCode);
    Check((not LRan) and DoOnlyError(LErrors, PC_ERR_ZIGBUILD_RUNNOTEXE),
      'run codes: a static library is ZB0027 (%s)', [DoFirstMessage(LErrors)]);

    LRan := DoRunWith(LDir, bmDll, '', 'zbp_run', '', LErrors, LOutput, LExitCode);
    Check((not LRan) and DoOnlyError(LErrors, PC_ERR_ZIGBUILD_RUNNOTEXE),
      'run codes: a DLL is ZB0027 (%s)', [DoFirstMessage(LErrors)]);

    LRan := DoRunWith(LDir, bmExe, '', '', '', LErrors, LOutput, LExitCode);
    Check((not LRan) and DoOnlyError(LErrors, PC_ERR_ZIGBUILD_NOPROJECTNAME),
      'run codes: no project name is ZB0028 (%s)', [DoFirstMessage(LErrors)]);

    LRan := DoRunWith(LDir, bmExe, '', 'zbp_run', '', LErrors, LOutput, LExitCode);
    Check((not LRan) and DoOnlyError(LErrors, PC_ERR_ZIGBUILD_EXENOTFOUND) and
      (LExitCode = 0) and DoFirstMessage(LErrors).Contains('zbp_run.exe'),
      'run codes: a missing executable is ZB0029 naming it, exit code untouched (exit %d, %s)',
      [LExitCode, DoFirstMessage(LErrors)]);

    Check(DoPlaceArtifact(LDir, 'zbp_run.exe', ''), 'run codes: a non-program placed');
    LRan := DoRunWith(LDir, bmExe, '', 'zbp_run', '', LErrors, LOutput, LExitCode);
    Check((not LRan) and DoOnlyError(LErrors, PC_ERR_ZIGBUILD_RUNSTART) and
      (LExitCode = 0) and DoFirstMessage(LErrors).Contains('zbp_run.exe'),
      'run codes: a file that cannot start is ZB0030 with the reason (exit %d, %s)',
      [LExitCode, DoFirstMessage(LErrors)]);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestRunProgram();
var
  LDir: string;
  LName: string;
  LErrors: TErrors;
  LOutput: string;
  LExitCode: DWORD;
  LRan: Boolean;
begin
  // The prebuilt argv fixture as the artifact, from a folder with a space:
  // Windows through the pseudoconsole, Linux through WSL (wsl.exe -e, no
  // shell). The same arguments arrive as the same literal argv on both (R35:
  // bash expanded $HOME and ran ';x'); exit 7 is ZB0031 with the code kept.
  // An executable past the launch limit runs (A5).
  LDir := DoScratch('run program');
  Check(LDir <> '', 'run program: scratch dir prepared');
  if LDir = '' then
    Exit;

  // A project name that puts the executable at PC_ZBP_LAUNCH_LENGTH
  // characters, plain spelling
  LName := StringOfChar('n', PC_ZBP_LAUNCH_LENGTH -
    Length(TUtils.StripLongPathPrefix(LDir)) - Length('\zig-out\bin\.exe'));
  Check(DoPlaceArtifact(LDir, 'zbp_run.exe', 'argv.exe') and
    DoPlaceArtifact(LDir, 'zbp_run', 'argv.elf') and
    DoPlaceArtifact(LDir, LName + '.exe', 'argv.exe'),
    'run program: fixtures placed');

  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);

    LRan := DoRunWith(LDir, bmExe, '', 'zbp_run', '', LErrors, LOutput, LExitCode);
    Check(LRan and (LErrors.Count() = 0) and (LExitCode = 0) and
      LOutput.Contains('argc=1'),
      'run program: windows, no arguments: runs, exit 0 (exit %d, %s)',
      [LExitCode, DoFirstMessage(LErrors)]);

    LRan := DoRunWith(LDir, bmExe, '', 'zbp_run', PC_ZBP_RUN_ARGS, LErrors,
      LOutput, LExitCode);
    Check((not LRan) and DoOnlyError(LErrors, PC_ERR_ZIGBUILD_RUNEXIT) and
      (LExitCode = 7),
      'run program: windows, exit 7 is ZB0031 with the code kept (exit %d, %s)',
      [LExitCode, DoFirstMessage(LErrors)]);
    Check(DoMissingArgv(LOutput) = '',
      'run program: windows, literal argv (missing %s)', [DoMissingArgv(LOutput)]);

    LRan := DoRunWith(LDir, bmExe, 'x86_64-linux-gnu', 'zbp_run', '', LErrors,
      LOutput, LExitCode);
    Check(LRan and (LErrors.Count() = 0) and (LExitCode = 0) and
      LOutput.Contains('argc=1'),
      'run program: linux, no arguments: runs, exit 0 (exit %d, %s)',
      [LExitCode, DoFirstMessage(LErrors)]);

    LRan := DoRunWith(LDir, bmExe, 'x86_64-linux-gnu', 'zbp_run', PC_ZBP_RUN_ARGS,
      LErrors, LOutput, LExitCode);
    Check((not LRan) and DoOnlyError(LErrors, PC_ERR_ZIGBUILD_RUNEXIT) and
      (LExitCode = 7),
      'run program: linux, exit 7 is ZB0031 with the code kept (exit %d, %s)',
      [LExitCode, DoFirstMessage(LErrors)]);
    Check(DoMissingArgv(LOutput) = '',
      'run program: linux, the same literal argv (missing %s)', [DoMissingArgv(LOutput)]);

    LRan := DoRunWith(LDir, bmExe, '', LName, '"p q"', LErrors, LOutput, LExitCode);
    Check((not LRan) and DoOnlyError(LErrors, PC_ERR_ZIGBUILD_RUNEXIT) and
      (LExitCode = 7) and LOutput.Contains('[1]=p q'),
      'run program: an executable past the launch limit runs (exit %d, %s)',
      [LExitCode, DoFirstMessage(LErrors)]);
  finally
    LErrors.Free();
  end;
end;

function DoWriteBytes(const APath: string; const AText: string): Boolean;
begin
  // AText as UTF-8 bytes, no BOM (a fixture exactly as given); its folder
  // made first. False when it cannot be written.
  try
    TUtils.CreateDirInPath(APath);
    TFile.WriteAllBytes(APath, TEncoding.UTF8.GetBytes(AText));
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

function DoCountText(const AText: string; const APart: string): Integer;
var
  LFrom: Integer;
begin
  // How many times APart occurs in AText
  Result := 0;
  LFrom := Pos(APart, AText);
  while LFrom > 0 do
  begin
    Inc(Result);
    LFrom := Pos(APart, AText, LFrom + Length(APart));
  end;
end;

function DoOnlyWarning(const AErrors: TErrors; const ACode: string): Boolean;
begin
  // Exactly one item, a warning with this code
  Result := (AErrors.Count() = 1) and
    (AErrors.GetItems()[0].Severity = esWarning) and
    (AErrors.GetItems()[0].Code = ACode);
end;

function DoConfigToolchain(const AConfigPath: string; const AErrors: TErrors): string;
var
  LZig: TPCZigBuild;
begin
  // The toolchain path a fresh ZigBuild reads from the build.toml at
  // AConfigPath; AErrors holds this read's items only
  AErrors.Clear();
  LZig := TPCZigBuild.Create();
  try
    LZig.SetErrors(AErrors);
    LZig.SetBuildConfigPath(AConfigPath);
    Result := LZig.GetToolchainPath();
  finally
    LZig.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestConfigFile();
var
  LDir: string;
  LToml: string;
  LText: string;
  LPath: string;
  LDefault: string;
  LBefore: TBytes;
  LAfter: TBytes;
  LErrors: TErrors;
  LZig: TPCZigBuild;
begin
  // build.toml (R6 R1 R2, R18 G3): read on first use from the path set,
  // never in Create; absent = the template; unreadable or a bad value = one
  // ZB0017 warning, the default, the file left as it was
  LDir := DoScratch('config');
  Check(LDir <> '', 'config: scratch dir prepared');
  if LDir = '' then
    Exit;
  LDefault := TUtils.ResolvePath(PC_DEFAULT_TOOLCHAIN_PATH);

  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);

    // Create and SetBuildConfigPath do no file I/O
    LToml := LDir + '/lazy/build.toml';
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetBuildConfigPath(LToml);
    finally
      LZig.Free();
    end;
    Check((not TFile.Exists(LToml)) and (LErrors.Count() = 0),
      'config: Create and SetBuildConfigPath write nothing');

    // Absent: the template, UTF-8 without a BOM, LF only (R1)
    LToml := LDir + '/absent/build.toml';
    LPath := DoConfigToolchain(LToml, LErrors);
    LAfter := DoReadBytes(LToml);
    LText := TEncoding.UTF8.GetString(LAfter);
    Check(TUtils.SamePath(LPath, LDefault) and (LErrors.Count() = 0),
      'config: absent file = the default toolchain path (%s, %s)',
      [LPath, DoFirstMessage(LErrors)]);
    Check((Length(LAfter) > 0) and (LAfter[0] <> $EF) and
      (not LText.Contains(#13)) and LText.Contains('toolchain_path = "$P:res"'),
      'config: the template is UTF-8 without a BOM, LF only (%s)',
      [LText.Replace(#13, '<CR>').Replace(#10, '<LF>')]);

    // A custom value is read; the file is not touched
    LToml := LDir + '/custom/build.toml';
    Check(DoWriteBytes(LToml, '[build]'#10'toolchain_path = "$P:custom_tc"'#10),
      'config: custom fixture written');
    LBefore := DoReadBytes(LToml);
    LPath := DoConfigToolchain(LToml, LErrors);
    Check(TUtils.SamePath(LPath, TUtils.ResolvePath('$P:custom_tc')) and
      (LErrors.Count() = 0) and DoSameBytes(LBefore, DoReadBytes(LToml)),
      'config: a custom value is read, the file unchanged (%s, %s)',
      [LPath, DoFirstMessage(LErrors)]);

    // Malformed: one warning, its position stated once (R2), default, untouched
    LToml := LDir + '/malformed/build.toml';
    Check(DoWriteBytes(LToml, '[[[ not toml'#10), 'config: malformed fixture written');
    LBefore := DoReadBytes(LToml);
    LPath := DoConfigToolchain(LToml, LErrors);
    Check(TUtils.SamePath(LPath, LDefault) and
      DoOnlyWarning(LErrors, PC_ERR_ZIGBUILD_WRNCONFIG) and
      (DoCountText(DoFirstMessage(LErrors), ' at line ') = 1) and
      DoSameBytes(LBefore, DoReadBytes(LToml)),
      'config: a malformed file is one ZB0017 with one position, the default, untouched (%s)',
      [DoFirstMessage(LErrors)]);

    // A value no file routine can take: a warning, not a raise (R18 G3)
    LToml := LDir + '/badvalue/build.toml';
    Check(DoWriteBytes(LToml, '[build]'#10'toolchain_path = "in<valid"'#10),
      'config: bad value fixture written');
    LBefore := DoReadBytes(LToml);
    LPath := DoConfigToolchain(LToml, LErrors);
    Check(TUtils.SamePath(LPath, LDefault) and
      DoOnlyWarning(LErrors, PC_ERR_ZIGBUILD_WRNCONFIG) and
      DoFirstMessage(LErrors).Contains('in<valid') and
      DoSameBytes(LBefore, DoReadBytes(LToml)),
      'config: a bad toolchain_path is one ZB0017, the default, untouched (%s)',
      [DoFirstMessage(LErrors)]);

    // A set value reads back in a fresh instance
    LToml := LDir + '/set/build.toml';
    Check(DoWriteBytes(LToml, '[build]'#10'toolchain_path = "$P:custom_tc"'#10),
      'config: set fixture written');
    LErrors.Clear();
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetBuildConfigPath(LToml);
      LZig.SetToolchainPath('$P:other');
    finally
      LZig.Free();
    end;
    Check(LErrors.Count() = 0, 'config: set saved without items (%s)',
      [DoFirstMessage(LErrors)]);
    LPath := DoConfigToolchain(LToml, LErrors);
    Check(TUtils.SamePath(LPath, TUtils.ResolvePath('$P:other')) and
      (LErrors.Count() = 0),
      'config: the set value reads back (%s, %s)', [LPath, DoFirstMessage(LErrors)]);
  finally
    LErrors.Free();
  end;
end;

procedure TPCZigBuildPathTests.DoTestToolchainLaunch();
var
  LDir: string;
  LToolchain: string;
  LZigExe: string;
  LFound: Boolean;
  LErrors: TErrors;
  LZig: TPCZigBuild;
  LBuilt: Boolean;
begin
  // A toolchain whose zig.exe lies past the launch limit is found (R43: it
  // was "zig not found"); a zig.exe that cannot start is ZB0032, with the
  // reason (it was ZB0005 with a bare '%s')
  LDir := DoScratch('toolchain');
  Check(LDir <> '', 'toolchain: scratch dir prepared');
  if LDir = '' then
    Exit;

  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(100);

    // zig\zig.exe at PC_ZBP_LAUNCH_LENGTH characters (plain spelling)
    LToolchain := TUtils.StripLongPathPrefix(LDir).Replace('/', '\') + '\' +
      StringOfChar('t', PC_ZBP_LAUNCH_LENGTH -
      Length(TUtils.StripLongPathPrefix(LDir)) - 1 - Length('\zig\zig.exe'));
    Check(DoWriteBytes(TUtils.ResolvePath(LToolchain + '\zig\zig.exe'), 'x') and
      DoWriteBytes(LDir + '/long/build.toml',
      '[build]'#10'toolchain_path = ''' + LToolchain + ''''#10),
      'toolchain: long fixture written');
    LErrors.Clear();
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetBuildConfigPath(LDir + '/long/build.toml');
      LZigExe := LZig.GetZigPath('zig.exe');
      LFound := TFile.Exists(LZigExe);
    finally
      LZig.Free();
    end;
    Check(LFound and (LErrors.Count() = 0) and
      (Length(TUtils.StripLongPathPrefix(LZigExe)) = PC_ZBP_LAUNCH_LENGTH),
      'toolchain: a zig.exe past the launch limit is found (%d chars, %s)',
      [Length(TUtils.StripLongPathPrefix(LZigExe)), DoFirstMessage(LErrors)]);

    // zig.exe that is not a program: ZB0032 with the OS reason
    LToolchain := TUtils.StripLongPathPrefix(LDir).Replace('/', '\') + '\bad_tc';
    Check(DoWriteBytes(LToolchain + '\zig\zig.exe', 'not a program') and
      DoWriteBytes(LDir + '/bad/build.toml',
      '[build]'#10'toolchain_path = ''' + LToolchain + ''''#10) and
      DoWriteBytes(LDir + '/src/a.cpp', 'int main() { return 0; }'#10),
      'toolchain: bad zig fixture written');
    LErrors.Clear();
    LZig := TPCZigBuild.Create();
    try
      LZig.SetErrors(LErrors);
      LZig.SetBuildConfigPath(LDir + '/bad/build.toml');
      LZig.SetOutputPath(LDir + '/out');
      LZig.SetProjectName('zbp_zig');
      LZig.AddSourceFile(LDir + '/src/a.cpp');
      LBuilt := LZig.Process(False);
    finally
      LZig.Free();
    end;
    Check((not LBuilt) and (LErrors.ErrorCount() = 1) and
      (DoCountCode(LErrors, PC_ERR_ZIGBUILD_ZIGSTART) = 1) and
      DoFirstMessage(LErrors).Contains('zig.exe'),
      'toolchain: a zig.exe that cannot start is ZB0032 with the reason (%s)',
      [DoFirstMessage(LErrors)]);
  finally
    LErrors.Free();
  end;
end;

end.
