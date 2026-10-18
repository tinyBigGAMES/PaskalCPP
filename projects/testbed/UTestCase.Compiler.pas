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
  UTestCase.Compiler - TPCCompiler, the facade, driven in-process

  TTestCase suite for PLAN-COMPILER A-CMP: fixtures under tests\probe\cmp\
  (written by scripts\zb_cmp\gen_cmp.py, never an editor). Prepare runs the
  real frontend and configures the real driver; the final settings are read
  back through the facade's getters and build.zig text (ZigBuild's own line
  forms). The expectations are the contract (research\compiler\
  r4-directives.md, r5-runtime-wiring.md), never the code's output. One case
  builds and runs a program end to end. Output under %TEMP%\pcpp-cmp\<case>.

  Dependencies: StdApp.TestCase, StdApp.Base, PaskalCPP.Common,
    PaskalCPP.ZigBuild, PaskalCPP.Compiler, UTestFrontend
===============================================================================}

unit UTestCase.Compiler;

interface

uses
  StdApp.TestCase;

type

  { TPCCompilerTests }
  TPCCompilerTests = class(TTestCase)
  private
    procedure DoTestDirectives();
    procedure DoTestOverrides();
    procedure DoTestDefaults();
    procedure DoTestTargetUnits();
    procedure DoTestBadOverride();
    procedure DoTestRetired();
    procedure DoTestMissingSource();
    procedure DoTestDebug();
    procedure DoTestDll();
    procedure DoTestUnit();
    procedure DoTestImport();
    procedure DoTestModulePaths();
    procedure DoTestValueMaps();
    procedure DoTestHello();
    procedure DoTestLibRuntime();
    procedure DoTestLibPlain();
    procedure DoTestAddSourceFile();
    procedure DoTestCppDefine();
    procedure DoTestMissingLib();
    procedure DoTestGeneratedChain();
    procedure DoTestPrintCheck();
    procedure DoTestPackedCheck();
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
  PaskalCPP.Common,
  PaskalCPP.ZigBuild,
  PaskalCPP.Compiler,
  UTestFrontend;

function DoSource(const ACase: string): string;
begin
  // tests\probe\cmp\<case>\cmp_<case>.pcpp
  Result := TPath.Combine(DoProbeDir('cmp\' + ACase), 'cmp_' + ACase + '.pcpp');
end;

function DoOutput(const ACase: string): string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetTempPath(), 'pcpp-cmp'), ACase);
end;

function DoFreshOutput(const ACase: string; out AError: string): string;
begin
  // A build case's folder starts empty: a file the test finds was written
  // by this build, a file it misses was not (AError = why it could not be cleared)
  AError := '';
  Result := DoOutput(ACase);
  try
    if TDirectory.Exists(Result) then
      TDirectory.Delete(Result, True);
  except
    on E: Exception do
      AError := E.Message;
  end;
end;

function DoRuntimeLibBeside(const AArtifact: string; const AProjectName: string): string;
begin
  // pcpp_runtime beside a lib, named by the same rule: the lib's file name
  // with its project name replaced (prefix and extension are the target's)
  Result := TPath.Combine(TPath.GetDirectoryName(AArtifact),
    TPath.GetFileName(AArtifact).Replace(AProjectName, PC_CMP_RUNTIME_NAME));
end;

function DoLinkLine(const ALibrary: string): string;
begin
  // The build.zig line a link library is written as (ZigBuild's own form)
  Result := PC_ZIG_FORM_LINKLIB_PRE + ZigStringLiteral(ALibrary) + PC_ZIG_FORM_LINKLIB_SUF;
end;

{ TPCCompilerTests }

constructor TPCCompilerTests.Create();
begin
  inherited;

  Title := 'Compiler';
  RegisterTest('directives', DoTestDirectives);
  RegisterTest('overrides', DoTestOverrides);
  RegisterTest('defaults', DoTestDefaults);
  RegisterTest('target_units', DoTestTargetUnits);
  RegisterTest('bad_override', DoTestBadOverride);
  RegisterTest('retired', DoTestRetired);
  RegisterTest('missing_source', DoTestMissingSource);
  RegisterTest('debug', DoTestDebug);
  RegisterTest('dll', DoTestDll);
  RegisterTest('unit', DoTestUnit);
  RegisterTest('import', DoTestImport);
  RegisterTest('module_paths', DoTestModulePaths);
  RegisterTest('value_maps', DoTestValueMaps);
  RegisterTest('hello', DoTestHello);
  RegisterTest('lib_runtime', DoTestLibRuntime);
  RegisterTest('lib_plain', DoTestLibPlain);
  RegisterTest('add_source_file', DoTestAddSourceFile);
  RegisterTest('cpp_define', DoTestCppDefine);
  RegisterTest('missing_lib', DoTestMissingLib);
  RegisterTest('generated_chain', DoTestGeneratedChain);
  RegisterTest('print_check', DoTestPrintCheck);
  RegisterTest('packed_check', DoTestPackedCheck);
end;

procedure TPCCompilerTests.Run();
begin
  inherited;
end;

procedure TPCCompilerTests.DoTestDirectives();
var
  LCompiler: TPCCompiler;
  LOk: Boolean;
  LZig: string;
begin
  LCompiler := TPCCompiler.Create();
  try
    LOk := LCompiler.Prepare(DoSource('dir'), DoOutput('dir'));
    Check(LOk and (DoCodes(LCompiler.GetErrors()) = ''),
      'directives: prepared without a report (' + DoReports(LCompiler.GetErrors()) + ')');
    if not LOk then
      Exit;

    Check(LCompiler.GetOptimizeLevel() = olFast, 'directives: @optimize fast');
    Check(LCompiler.GetSubsystem() = stGUI, 'directives: @subsystem gui');
    Check(LCompiler.GetBuildMode() = bmExe, 'directives: an exe builds as bmExe');
    Check(LCompiler.GetProjectName() = 'cmp_dir', 'directives: project name = the entry file name');
    Check(not LCompiler.HasDefine(PC_CMP_DEFINE_DEBUG), 'directives: no PCPP_DEBUG at fast');
    Check(not LCompiler.HasDefine(PC_CMP_DEFINE_DLL), 'directives: no PCPP_BUILD_DLL for an exe');

    LZig := LCompiler.GenerateBuildZig();
    Check(LZig.Contains(DoLinkLine('m')), 'directives: @linklibrary "m" is linked');
    Check(LZig.Contains(DoLinkLine('cmpext')), 'directives: the external clause''s library is linked');
    Check(TFile.Exists(TPath.Combine(TPath.Combine(DoOutput('dir'), PC_CMP_GENERATED_DIR),
      'cmp_dir.pcpp.cpp')), 'directives: the module was emitted under generated');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestOverrides();
var
  LCompiler: TPCCompiler;
  LOk: Boolean;
begin
  // The overrides win over @optimize / @subsystem; keys ignore case
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetKeyValue(PC_CMP_KEY_OPTIMIZE, 'debug');
    LCompiler.SetKeyValue('SUBSYSTEM', 'console');
    LOk := LCompiler.Prepare(DoSource('dir'), DoOutput('dir'));
    Check(LOk, 'overrides: prepared (' + DoReports(LCompiler.GetErrors()) + ')');
    if not LOk then
      Exit;

    Check(LCompiler.GetOptimizeLevel() = olDebug, 'overrides: optimize debug beats @optimize fast');
    Check(LCompiler.GetSubsystem() = stConsole, 'overrides: subsystem console beats @subsystem gui');
    Check(LCompiler.HasDefine(PC_CMP_DEFINE_DEBUG), 'overrides: PCPP_DEBUG follows the final level');
  finally
    LCompiler.Free();
  end;
end;

const
  { PC_UTC_LINUX_OS }
  // How build.zig names a Linux target (TPCZigBuild.DoZigTargetQuery)
  PC_UTC_LINUX_OS = '.os_tag = .linux';
  { PC_UTC_WINDOWS_OS }
  PC_UTC_WINDOWS_OS = '.os_tag = .windows';

procedure TPCCompilerTests.DoTestDefaults();
var
  LCompiler: TPCCompiler;
  LOk: Boolean;
begin
  // The defaults (the editor's -opt / -t with --defaults) stand in only for
  // what the source does not say: a directive wins over them, an override
  // wins over both

  // 1. dir has @optimize fast / @subsystem gui: the directives win
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetKeyDefault(PC_CMP_KEY_OPTIMIZE, 'debug');
    LCompiler.SetKeyDefault(PC_CMP_KEY_SUBSYSTEM, 'console');
    LOk := LCompiler.Prepare(DoSource('dir'), DoOutput('dir'));
    Check(LOk, 'defaults: dir prepared (' + DoReports(LCompiler.GetErrors()) + ')');
    if LOk then
    begin
      Check(LCompiler.GetOptimizeLevel() = olFast,
        'defaults: @optimize fast beats the default debug');
      Check(LCompiler.GetSubsystem() = stGUI, 'defaults: @subsystem gui beats the default console');
    end;
  finally
    LCompiler.Free();
  end;

  // 2. hello says nothing: the defaults are what is built
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetKeyDefault(PC_CMP_KEY_OPTIMIZE, 'small');
    LCompiler.SetKeyDefault(PC_CMP_KEY_TARGET, 'x86_64-linux-gnu');
    LOk := LCompiler.Prepare(DoSource('hello'), DoOutput('hello'));
    Check(LOk, 'defaults: hello prepared (' + DoReports(LCompiler.GetErrors()) + ')');
    if LOk then
    begin
      Check(LCompiler.GetOptimizeLevel() = olSmall,
        'defaults: no @optimize, the default small is built');
      Check(LCompiler.GenerateBuildZig().Contains(PC_UTC_LINUX_OS),
        'defaults: no @target, the default x86_64-linux-gnu is built');
    end;
  finally
    LCompiler.Free();
  end;

  // 3. tgt has @target "x86_64-linux-gnu": a default does not replace it,
  //    an override does
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetKeyDefault(PC_CMP_KEY_TARGET, 'x86_64-windows-gnu');
    LOk := LCompiler.Prepare(DoSource('tgt'), DoOutput('tgt'));
    Check(LOk and LCompiler.GenerateBuildZig().Contains(PC_UTC_LINUX_OS),
      'defaults: @target linux beats the default windows (' + DoReports(LCompiler.GetErrors()) + ')');
  finally
    LCompiler.Free();
  end;
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetKeyDefault(PC_CMP_KEY_TARGET, 'x86_64-linux-gnu');
    LCompiler.SetKeyValue(PC_CMP_KEY_TARGET, 'x86_64-windows-gnu');
    LOk := LCompiler.Prepare(DoSource('tgt'), DoOutput('tgt'));
    Check(LOk and LCompiler.GenerateBuildZig().Contains(PC_UTC_WINDOWS_OS),
      'defaults: an override (windows) beats @target linux and the default (' +
      DoReports(LCompiler.GetErrors()) + ')');
  finally
    LCompiler.Free();
  end;

  // 4. A bad default is CMP0001, as a bad override
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetKeyDefault(PC_CMP_KEY_OPTIMIZE, 'quick');
    LOk := LCompiler.Prepare(DoSource('hello'), DoOutput('hello'));
    Check((not LOk) and (DoCodes(LCompiler.GetErrors()) = PC_ERR_CMP_001),
      'defaults: a bad default value is CMP0001 (' + DoReports(LCompiler.GetErrors()) + ')');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestTargetUnits();
var
  LCompiler: TPCCompiler;
  LOk: Boolean;
begin
  // Command line first, then the @directives: an override (CLI -t) wins over
  // every @target of the build, an imported unit's too (the parser hands it
  // down); a default (--defaults) never replaces a @target. tgtu and its unit
  // both name Linux

  // 1. Override windows: no CD0012 in the unit, the build is Windows
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetKeyValue(PC_CMP_KEY_TARGET, 'x86_64-windows-gnu');
    LOk := LCompiler.Prepare(DoSource('tgtu'), DoOutput('tgtu'));
    Check(LOk and LCompiler.GenerateBuildZig().Contains(PC_UTC_WINDOWS_OS),
      'target_units: an override (windows) beats the main''s and the unit''s @target linux (' +
      DoReports(LCompiler.GetErrors()) + ')');
  finally
    LCompiler.Free();
  end;

  // 2. Default windows: the @targets win, the build is Linux, no report
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetKeyDefault(PC_CMP_KEY_TARGET, 'x86_64-windows-gnu');
    LOk := LCompiler.Prepare(DoSource('tgtu'), DoOutput('tgtu'));
    Check(LOk and LCompiler.GenerateBuildZig().Contains(PC_UTC_LINUX_OS),
      'target_units: a default (windows) does not replace @target linux (' +
      DoReports(LCompiler.GetErrors()) + ')');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestBadOverride();
var
  LCompiler: TPCCompiler;
begin
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetKeyValue(PC_CMP_KEY_OPTIMIZE, 'quick');
    Check(not LCompiler.Prepare(DoSource('dir'), DoOutput('dir')), 'bad_override: a bad value fails');
    Check(DoCodes(LCompiler.GetErrors()) = PC_ERR_CMP_001,
      'bad_override: reported as CMP0001 (' + DoReports(LCompiler.GetErrors()) + ')');
  finally
    LCompiler.Free();
  end;

  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetKeyValue('nope', 'x');
    Check(not LCompiler.Prepare(DoSource('dir'), DoOutput('dir')), 'bad_override: an unknown option fails');
    Check(DoCodes(LCompiler.GetErrors()) = PC_ERR_CMP_001,
      'bad_override: unknown option is CMP0001 (' + DoReports(LCompiler.GetErrors()) + ')');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestRetired();
var
  LCompiler: TPCCompiler;
begin
  // A retired level spelling (PC_RETIRED_VALUES) is an error naming the new
  // one, on all three paths: an override (-opt), a default (the editor) and
  // @optimize

  // 1. an override
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetKeyValue(PC_CMP_KEY_OPTIMIZE, 'release_fast');
    Check(not LCompiler.Prepare(DoSource('hello'), DoOutput('hello')), 'retired: an override fails');
    Check(DoCodes(LCompiler.GetErrors()) = PC_ERR_CMP_001,
      'retired: an override is CMP0001 (' + DoReports(LCompiler.GetErrors()) + ')');
    Check(DoReports(LCompiler.GetErrors()).Contains(
      '''release_fast'' is no longer a value of option optimize: write ''fast'''),
      'retired: an override names fast (' + DoReports(LCompiler.GetErrors()) + ')');
  finally
    LCompiler.Free();
  end;

  // 2. a default
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetKeyDefault(PC_CMP_KEY_OPTIMIZE, 'release_small');
    Check(not LCompiler.Prepare(DoSource('hello'), DoOutput('hello')), 'retired: a default fails');
    Check(DoCodes(LCompiler.GetErrors()) = PC_ERR_CMP_001,
      'retired: a default is CMP0001 (' + DoReports(LCompiler.GetErrors()) + ')');
    Check(DoReports(LCompiler.GetErrors()).Contains(
      '''release_small'' is no longer a value of option optimize: write ''small'''),
      'retired: a default names small (' + DoReports(LCompiler.GetErrors()) + ')');
  finally
    LCompiler.Free();
  end;

  // 3. @optimize release_fast (cmp_retired.pcpp line 2): SEM's SM0100
  LCompiler := TPCCompiler.Create();
  try
    Check(not LCompiler.Prepare(DoSource('retired'), DoOutput('retired')), 'retired: @optimize fails');
    Check(DoReports(LCompiler.GetErrors()) =
      'SM0100 2: ''release_fast'' is no longer a value of @optimize: write ''fast''',
      'retired: @optimize is one SM0100 naming fast (' + DoReports(LCompiler.GetErrors()) + ')');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestMissingSource();
var
  LCompiler: TPCCompiler;
begin
  LCompiler := TPCCompiler.Create();
  try
    Check(not LCompiler.Prepare(TPath.Combine(DoProbeDir('cmp'), 'nothere'), DoOutput('missing')),
      'missing_source: fails');
    Check(DoCodes(LCompiler.GetErrors()) = PC_ERR_CMP_001,
      'missing_source: CMP0001 (' + DoReports(LCompiler.GetErrors()) + ')');
    Check(not LCompiler.Build(), 'missing_source: nothing to build after a failed Prepare');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestDebug();
var
  LCompiler: TPCCompiler;
  LOk: Boolean;
begin
  LCompiler := TPCCompiler.Create();
  try
    LOk := LCompiler.Prepare(DoSource('debug'), DoOutput('debug'));
    Check(LOk, 'debug: prepared (' + DoReports(LCompiler.GetErrors()) + ')');
    Check(LOk and (LCompiler.GetOptimizeLevel() = olDebug), 'debug: @optimize debug');
    Check(LOk and LCompiler.HasDefine(PC_CMP_DEFINE_DEBUG), 'debug: PCPP_DEBUG defined');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestDll();
var
  LCompiler: TPCCompiler;
  LOk: Boolean;
begin
  LCompiler := TPCCompiler.Create();
  try
    LOk := LCompiler.Prepare(DoSource('dll'), DoOutput('dll'));
    Check(LOk, 'dll: prepared (' + DoReports(LCompiler.GetErrors()) + ')');
    Check(LOk and (LCompiler.GetBuildMode() = bmDll), 'dll: builds as bmDll');
    Check(LOk and LCompiler.HasDefine(PC_CMP_DEFINE_DLL), 'dll: PCPP_BUILD_DLL defined');
    if not LOk then
      Exit;

    // Built for real; asked to run, a dll is skipped with a warning only
    Check(LCompiler.Build(True), 'dll: built (' + DoReports(LCompiler.GetErrors()) + ')');
    Check(DoCodes(LCompiler.GetErrors()) = PC_ERR_CMP_002,
      'dll: auto-run skipped as CMP0002 (' + DoReports(LCompiler.GetErrors()) + ')');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestUnit();
var
  LCompiler: TPCCompiler;
  LOut: string;
  LReason: string;
begin
  // A unit cannot be the main module (the parser's PR0004): nothing emitted or built
  LOut := DoOutput('unit');
  LReason := '';
  try
    if TDirectory.Exists(LOut) then
      TDirectory.Delete(LOut, True);
  except
    on E: Exception do
      LReason := E.Message;
  end;
  Check(LReason = '', 'unit: output folder cleared (' + LReason + ')');

  LCompiler := TPCCompiler.Create();
  try
    Check(not LCompiler.Prepare(DoSource('unit'), LOut), 'unit: a unit main module fails');
    Check(DoCodes(LCompiler.GetErrors()) = 'PR0004',
      'unit: the parser''s PR0004 (' + DoReports(LCompiler.GetErrors()) + ')');
    Check(not LCompiler.Build(True), 'unit: nothing to build');
    Check(not TDirectory.Exists(TPath.Combine(LOut, PC_CMP_GENERATED_DIR)),
      'unit: nothing emitted');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestImport();
var
  LCompiler: TPCCompiler;
  LOk: Boolean;
begin
  LCompiler := TPCCompiler.Create();
  try
    LOk := LCompiler.Prepare(DoSource('imp'), DoOutput('imp'));
    Check(LOk, 'import: prepared (' + DoReports(LCompiler.GetErrors()) + ')');
    Check(LOk and LCompiler.GenerateBuildZig().Contains(DoLinkLine('iulib')),
      'import: the imported unit''s @linklibrary is linked');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestModulePaths();
var
  LCompiler: TPCCompiler;
  LPaths: TArray<string>;
  LCore: string;
  LMessage: string;
begin
  // The parser's import fixtures (tests\probe\par\core)
  LCore := DoProbeDir('par\core');

  // A new compiler's only module path is the standard library's
  LCompiler := TPCCompiler.Create();
  try
    LPaths := LCompiler.GetModulePaths();
    Check((Length(LPaths) = 1) and (LPaths[0] = PC_STD_MODULE_PATH),
      'module_paths: Create adds PC_STD_MODULE_PATH, and only it');
    LCompiler.AddModulePath(TPath.Combine(LCore, 'mp'));
    LPaths := LCompiler.GetModulePaths();
    Check((Length(LPaths) = 2) and (LPaths[0] = PC_STD_MODULE_PATH) and
      (LPaths[1] = TPath.Combine(LCore, 'mp')),
      'module_paths: AddModulePath appends, in order');

    // The parse searches the std folder: its resolved spelling is in the
    // not-found report
    Check(not LCompiler.Prepare(TPath.Combine(LCore, 'pa15_missing.pcpp'), DoOutput('modpaths')),
      'module_paths: a missing import fails');
    LMessage := '';
    if LCompiler.GetErrors().Count() > 0 then
      LMessage := LCompiler.GetErrors().GetItems()[0].Message;
    Check(LMessage.Contains(TUtils.ResolvePath(PC_STD_MODULE_PATH)),
      'module_paths: the std folder is searched (' + LMessage + ')');
  finally
    LCompiler.Free();
  end;

  // A folder added on the compiler reaches the parse: pa_mu is only in mp\
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.AddModulePath(TPath.Combine(LCore, 'mp'));
    LCompiler.Prepare(TPath.Combine(LCore, 'pa28_addpath.pcpp'), DoOutput('modpaths'));
    Check(not DoCodes(LCompiler.GetErrors()).Contains('PR0012'),
      'module_paths: the compiler''s AddModulePath folder is searched (' +
      DoReports(LCompiler.GetErrors()) + ')');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestValueMaps();
var
  LIndex: Integer;
  LRow: TPCDirectiveValue;
  LLevel: TPCOptimizeLevel;
  LFound: TPCOptimizeLevel;
  LSubsystem: TPCSubsystemType;
  LFoundSubsystem: TPCSubsystemType;
begin
  // Both ways: every @optimize / @subsystem value has a driver setting, and
  // every driver setting is a value of the directive
  for LIndex := Low(PC_DIRECTIVE_VALUES) to High(PC_DIRECTIVE_VALUES) do
  begin
    LRow := PC_DIRECTIVE_VALUES[LIndex];
    if LRow.Directive = bdOptimize then
      Check(TPCCompiler.FindOptimizeLevel(LRow.ValueText, LFound),
        'value_maps: @optimize ' + LRow.ValueText + ' maps to a level')
    else if LRow.Directive = bdSubsystem then
      Check(TPCCompiler.FindSubsystem(LRow.ValueText, LFoundSubsystem),
        'value_maps: @subsystem ' + LRow.ValueText + ' maps to a subsystem');
  end;
  for LLevel := Low(TPCOptimizeLevel) to High(TPCOptimizeLevel) do
    Check(TPCVocabulary.IsDirectiveValue(bdOptimize, PC_CMP_OPTIMIZE_TEXT[LLevel]),
      'value_maps: level ' + PC_CMP_OPTIMIZE_TEXT[LLevel] + ' is an @optimize value');
  for LSubsystem := Low(TPCSubsystemType) to High(TPCSubsystemType) do
    Check(TPCVocabulary.IsDirectiveValue(bdSubsystem, PC_CMP_SUBSYSTEM_TEXT[LSubsystem]),
      'value_maps: subsystem ' + PC_CMP_SUBSYSTEM_TEXT[LSubsystem] + ' is a @subsystem value');
end;

procedure TPCCompilerTests.DoTestHello();
var
  LCompiler: TPCCompiler;
begin
  // The whole pipeline: parse, analyze, emit, build with the runtime, run
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetMaxErrors(10);
    LCompiler.Compile(DoSource('hello'), DoOutput('hello'), True);
    Check(not LCompiler.HasErrors(),
      'hello: built and run without an error (' + DoReports(LCompiler.GetErrors()) + ')');
    Check(LCompiler.GetLastExitCode() = 0, 'hello: exit code 0');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestLibRuntime();
var
  LCompiler: TPCCompiler;
  LOutput: string;
  LError: string;
  LArtifact: string;
  LRuntimeLib: string;
begin
  // r5 D-R5-3 / r10 D-R10-3: a lib that uses the runtime ships pcpp_runtime
  // beside its artifact, built for real
  LOutput := DoFreshOutput('librt', LError);
  Check(LError = '', 'librt: fresh output folder (' + LError + ')');
  if LError <> '' then
    Exit;
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetMaxErrors(10);
    LCompiler.Compile(DoSource('librt'), LOutput);
    Check(not LCompiler.HasErrors(), 'librt: built (' + DoReports(LCompiler.GetErrors()) + ')');
    LArtifact := LCompiler.GetArtifactPath();
    Check(TFile.Exists(LArtifact), 'librt: the lib exists: ' + LArtifact);
    LRuntimeLib := DoRuntimeLibBeside(LArtifact, 'cmp_librt');
    Check(TFile.Exists(LRuntimeLib), 'librt: the runtime library published beside it: ' + LRuntimeLib);
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestLibPlain();
var
  LCompiler: TPCCompiler;
  LOutput: string;
  LError: string;
  LArtifact: string;
  LRuntimeLib: string;
begin
  // Q2: a lib that does not use the runtime is its .lib alone: no runtime
  // library beside it and no runtime build at all
  LOutput := DoFreshOutput('libplain', LError);
  Check(LError = '', 'libplain: fresh output folder (' + LError + ')');
  if LError <> '' then
    Exit;
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetMaxErrors(10);
    LCompiler.Compile(DoSource('libplain'), LOutput);
    Check(not LCompiler.HasErrors(), 'libplain: built (' + DoReports(LCompiler.GetErrors()) + ')');
    LArtifact := LCompiler.GetArtifactPath();
    Check(TFile.Exists(LArtifact), 'libplain: the lib exists: ' + LArtifact);
    LRuntimeLib := DoRuntimeLibBeside(LArtifact, 'cmp_libplain');
    Check(not TFile.Exists(LRuntimeLib), 'libplain: no runtime library beside it: ' + LRuntimeLib);
    Check(not TDirectory.Exists(TPath.Combine(LOutput, PC_CMP_RUNTIME_DIR)),
      'libplain: no runtime build folder under ' + LOutput);
  finally
    LCompiler.Free();
  end;

  // A runtime library an earlier build published (the lib used the runtime
  // then) is stale now: the next build of this lib removes it
  try
    TFile.WriteAllText(LRuntimeLib, 'stale');
  except
    on E: Exception do
    begin
      Check(False, 'libplain: cannot plant the stale runtime library: ' + E.Message);
      Exit;
    end;
  end;
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetMaxErrors(10);
    LCompiler.Compile(DoSource('libplain'), LOutput);
    Check(not LCompiler.HasErrors(), 'libplain: rebuilt (' + DoReports(LCompiler.GetErrors()) + ')');
    Check(not TFile.Exists(LRuntimeLib), 'libplain: the stale runtime library was removed: ' + LRuntimeLib);
    Check(TFile.Exists(LArtifact), 'libplain: the lib itself stays: ' + LArtifact);
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestAddSourceFile();
var
  LCompiler: TPCCompiler;
  LDir: string;
  LOld: string;
begin
  // @addsourcefile, built and run for real: asf_c.c (C) and asf_cpp.C (C++
  // only, exact case) join the exe; the program raises unless both answer.
  // The paths are relative: the parse runs with the CWD = the case folder
  LDir := DoProbeDir('cmp\asf');
  LOld := GetCurrentDir();
  if not SetCurrentDir(LDir) then
  begin
    Check(False, 'add_source_file: cwd ' + LDir);
    Exit;
  end;
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetMaxErrors(10);
    LCompiler.Compile(DoSource('asf'), DoOutput('asf'), True);
    Check(not LCompiler.HasErrors(),
      'add_source_file: built and run without an error (' + DoReports(LCompiler.GetErrors()) + ')');
    // Exit code 0 also means "nothing ran": it counts only after a clean build
    Check((not LCompiler.HasErrors()) and (LCompiler.GetLastExitCode() = 0),
      'add_source_file: the program ran and both added files answered (exit code %d)',
      [LCompiler.GetLastExitCode()]);
  finally
    LCompiler.Free();
    SetCurrentDir(LOld);
  end;
end;

procedure TPCCompilerTests.DoTestCppDefine();
var
  LCompiler: TPCCompiler;
  LDir: string;
  LOld: string;
  LOk: Boolean;
  LBuildZig: string;
begin
  // @cppdefine / @cppundef: -D / -U in build.zig, then a real build: the added
  // C file and the emitted C++ #error without the macros, the program raises
  // unless the C file returns CPPDEF_V
  LDir := DoProbeDir('cmp\cppdef');
  LOld := GetCurrentDir();
  if not SetCurrentDir(LDir) then
  begin
    Check(False, 'cpp_define: cwd ' + LDir);
    Exit;
  end;
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetMaxErrors(10);
    LOk := LCompiler.Prepare(DoSource('cppdef'), DoOutput('cppdef'));
    Check(LOk, 'cpp_define: prepared (' + DoReports(LCompiler.GetErrors()) + ')');
    if not LOk then
      Exit;
    LBuildZig := LCompiler.GenerateBuildZig();
    Check(LBuildZig.Contains('"-DCPPDEF_ON"'), 'cpp_define: -DCPPDEF_ON in build.zig');
    Check(LBuildZig.Contains('"-DCPPDEF_V=7"'), 'cpp_define: -DCPPDEF_V=7 in build.zig');
    Check(LBuildZig.Contains('"-UCPPDEF_GONE"'), 'cpp_define: -UCPPDEF_GONE in build.zig');
    LOk := LCompiler.Build(True);
    Check(LOk and (not LCompiler.HasErrors()) and (LCompiler.GetLastExitCode() = 0),
      'cpp_define: built and ran: the macros reached the C file and the emitted C++ (%s, exit code %d)',
      [DoReports(LCompiler.GetErrors()), LCompiler.GetLastExitCode()]);
  finally
    LCompiler.Free();
    SetCurrentDir(LOld);
  end;
end;

const
  { PC_UTC_MLIB_TARGETS }
  // The official targets missing_lib builds for (DESIGN.md sec 7)
  PC_UTC_MLIB_TARGETS: array[0..1] of string = ('x86_64-windows-gnu', 'x86_64-linux-gnu');

function DoNamingAt(const AFile: string; const AText: string; out ALine: Integer;
  out AColumn: Integer): Boolean;
var
  LLines: TArray<string>;
  LI: Integer;
begin
  // The 1-based line and column where AText first stands in AFile (a
  // fixture's library naming, found by its text, never by number)
  Result := False;
  ALine := 0;
  AColumn := 0;
  try
    LLines := TFile.ReadAllLines(AFile, TEncoding.UTF8);
  except
    on Exception do
      Exit;
  end;
  for LI := 0 to High(LLines) do
  begin
    if LLines[LI].Contains(AText) then
    begin
      ALine := LI + 1;
      AColumn := LLines[LI].IndexOf(AText) + 1;
      Exit(True);
    end;
  end;
end;

function DoIsAt(const AError: TError; const AFile: string; const ALine: Integer;
  const AColumn: Integer): Boolean;
begin
  // A report's stored location (byte column: the fixture lines are ASCII)
  Result := TUtils.SamePath(AError.Range.Filename, AFile) and
    (AError.Range.StartLine = UInt64(ALine)) and (AError.Range.StartColumn = UInt64(AColumn));
end;

function DoNamesMissingLib(const AMessage: string; const ALibrary: string): Boolean;
begin
  // zig's "unable to find <kind> system library <name>" quotes the name with ' (zig 0.16) or
  // " (zig 0.17.0); the report names ALibrary in either spelling
  Result := AMessage.Contains('system library ''' + ALibrary + '''') or
    AMessage.Contains('system library "' + ALibrary + '"');
end;

procedure TPCCompilerTests.DoTestMissingLib();
var
  LCompiler: TPCCompiler;
  LMain: string;
  LUnit: string;
  LLineA: Integer;
  LColA: Integer;
  LLineB: Integer;
  LColB: Integer;
  LTarget: string;
  LError: TError;
  LHitA: Boolean;
  LHitB: Boolean;
  LElsewhere: string;
begin
  // F11: a library no search folder holds is reported where the source names
  // it: the main module's @linklibrary value, the unit's external clause
  // library; never without a location (DESIGN.md sec 5). Both targets
  LMain := DoSource('mlib');
  LUnit := TPath.Combine(TPath.GetDirectoryName(LMain), 'cmp_mlib_u.pcpp');
  Check(DoNamingAt(LMain, '"pcpp_mlib_a"', LLineA, LColA) and
    DoNamingAt(LUnit, '"pcpp_mlib_b"', LLineB, LColB), 'missing_lib: fixture namings found');

  for LTarget in PC_UTC_MLIB_TARGETS do
  begin
    LCompiler := TPCCompiler.Create();
    try
      LCompiler.SetMaxErrors(100);
      LCompiler.SetKeyValue(PC_CMP_KEY_TARGET, LTarget);
      LCompiler.Compile(LMain, DoOutput('mlib_' + LTarget));

      LHitA := False;
      LHitB := False;
      LElsewhere := '';
      for LError in LCompiler.GetErrors().GetItems() do
      begin
        if DoIsAt(LError, LMain, LLineA, LColA) and
          DoNamesMissingLib(LError.Message, 'pcpp_mlib_a') then
          LHitA := True
        else if DoIsAt(LError, LUnit, LLineB, LColB) and
          DoNamesMissingLib(LError.Message, 'pcpp_mlib_b') then
          LHitB := True
        else
          LElsewhere := LElsewhere + ' | ' + LError.Code + ' ' + LError.Message;
      end;
      Check(LHitA, 'missing_lib on %s: pcpp_mlib_a at its @linklibrary (%d,%d) (%s)',
        [LTarget, LLineA, LColA, DoReports(LCompiler.GetErrors())]);
      Check(LHitB, 'missing_lib on %s: pcpp_mlib_b at its external clause (%d,%d) (%s)',
        [LTarget, LLineB, LColB, DoReports(LCompiler.GetErrors())]);
      Check(LElsewhere = '', 'missing_lib on %s: nothing else reported (%s)', [LTarget, LElsewhere]);
    finally
      LCompiler.Free();
    end;
  end;
end;

procedure TPCCompilerTests.DoTestGeneratedChain();
var
  LCompiler: TPCCompiler;
  LUnit: string;
  LLine: Integer;
  LCol: Integer;
  LTarget: string;
  LError: TError;
  LHit: Boolean;
  LNotes: string;
  LElsewhere: string;
  LI: Integer;
begin
  // F13: a unit's module-level #include of a header no folder holds is
  // reported at its .pcpp line, and the include chain clang gives it runs
  // only through files the compiler generated (a TU's .pcpp.cpp line 1 that
  // includes its module header; the first TU's copy is reported): no note of
  // it is shown (DESIGN.md sec 5). Both targets
  LUnit := TPath.Combine(TPath.GetDirectoryName(DoSource('gchain')), 'cmp_gchain_u.pcpp');
  Check(DoNamingAt(LUnit, '"cmp_gchain_missing.h"', LLine, LCol),
    'generated_chain: fixture #include found');

  for LTarget in PC_UTC_MLIB_TARGETS do
  begin
    LCompiler := TPCCompiler.Create();
    try
      LCompiler.SetMaxErrors(100);
      LCompiler.SetKeyValue(PC_CMP_KEY_TARGET, LTarget);
      LCompiler.Compile(DoSource('gchain'), DoOutput('gchain_' + LTarget));

      LHit := False;
      LNotes := '';
      LElsewhere := '';
      for LError in LCompiler.GetErrors().GetItems() do
      begin
        if DoIsAt(LError, LUnit, LLine, LCol) and
          LError.Message.Contains('''cmp_gchain_missing.h'' file not found') then
        begin
          LHit := True;
          for LI := 0 to High(LError.Related) do
            LNotes := LNotes + ' | ' + LError.Related[LI].Range.Filename + ' ' +
              LError.Related[LI].Msg;
        end
        else
          LElsewhere := LElsewhere + ' | ' + LError.Code + ' ' + LError.Message;
      end;
      Check(LHit, 'generated_chain on %s: the missing header at the unit''s #include (%d,%d) (%s)',
        [LTarget, LLine, LCol, DoReports(LCompiler.GetErrors())]);
      Check(LNotes = '', 'generated_chain on %s: no include step through a generated file (%s)',
        [LTarget, LNotes]);
      Check(LElsewhere = '', 'generated_chain on %s: nothing else reported (%s)',
        [LTarget, LElsewhere]);
    finally
      LCompiler.Free();
    end;
  end;
end;

procedure TPCCompilerTests.DoTestPrintCheck();
var
  LCompiler: TPCCompiler;
  LMain: string;
  LLineS: Integer;
  LColS: Integer;
  LLineA: Integer;
  LColA: Integer;
  LTarget: string;
  LError: TError;
  LHitS: Boolean;
  LHitA: Boolean;
  LElsewhere: string;
begin
  // PLAN-PASKAL-ERRORS E7: a print argument of a C/C++ type with no
  // std::formatter (a struct value, an array of it) is SM0425 at the argument
  // in PaskalCPP words (the emitter's check, reported by the frontend), and
  // nothing else: no libc++ line, no second copy under a budget above 1.
  // Both targets (scripts\zb_cmp\gen_pcheck.py)
  LMain := DoSource('pcheck');
  Check(DoNamingAt(LMain, 'LS);', LLineS, LColS) and DoNamingAt(LMain, 'LA);', LLineA, LColA),
    'print_check: fixture arguments found');

  for LTarget in PC_UTC_MLIB_TARGETS do
  begin
    LCompiler := TPCCompiler.Create();
    try
      LCompiler.SetMaxErrors(100);
      LCompiler.SetKeyValue(PC_CMP_KEY_TARGET, LTarget);
      LCompiler.Compile(LMain, DoOutput('pcheck_' + LTarget));

      LHitS := False;
      LHitA := False;
      LElsewhere := '';
      for LError in LCompiler.GetErrors().GetItems() do
      begin
        if (LError.Code = 'SM0425') and DoIsAt(LError, LMain, LLineS, LColS) and
          LError.Message.Contains('''S'' cannot be printed') then
          LHitS := True
        else if (LError.Code = 'SM0425') and DoIsAt(LError, LMain, LLineA, LColA) and
          LError.Message.Contains('''array[0..0] of S'' cannot be printed') then
          LHitA := True
        else
          LElsewhere := LElsewhere + ' | ' + LError.Code + ' ' + LError.Message;
      end;
      Check(LHitS, 'print_check on %s: SM0425 at LS (%d,%d) (%s)',
        [LTarget, LLineS, LColS, DoReports(LCompiler.GetErrors())]);
      Check(LHitA, 'print_check on %s: SM0425 at LA (%d,%d) (%s)',
        [LTarget, LLineA, LColA, DoReports(LCompiler.GetErrors())]);
      Check(LElsewhere = '', 'print_check on %s: nothing else reported (%s)', [LTarget, LElsewhere]);
    finally
      LCompiler.Free();
    end;
  end;
end;

procedure TPCCompilerTests.DoTestPackedCheck();
var
  LCompiler: TPCCompiler;
  LMain: string;
  LLineF: Integer;
  LColF: Integer;
  LLineP: Integer;
  LColP: Integer;
  LTarget: string;
  LError: TError;
  LHitF: Boolean;
  LHitP: Boolean;
  LElsewhere: string;
begin
  // PLAN-RECORDS M9: a packed field of a C++ class with a constructor (F)
  // and a packed extension's parent holding one (TBad) do not pack: SM0331
  // at the field / the parent in PaskalCPP words (the emitter's
  // packs_as_field check, reported by the frontend); the C struct field G
  // packs; nothing else is reported. Both targets (scripts\zb_cmp\gen_pkcheck.py)
  LMain := DoSource('pkcheck');
  Check(DoNamingAt(LMain, 'F: K;', LLineF, LColF) and DoNamingAt(LMain, 'TBad) packed', LLineP, LColP),
    'packed_check: fixture field and parent found');

  for LTarget in PC_UTC_MLIB_TARGETS do
  begin
    LCompiler := TPCCompiler.Create();
    try
      LCompiler.SetMaxErrors(100);
      LCompiler.SetKeyValue(PC_CMP_KEY_TARGET, LTarget);
      LCompiler.Compile(LMain, DoOutput('pkcheck_' + LTarget));

      LHitF := False;
      LHitP := False;
      LElsewhere := '';
      for LError in LCompiler.GetErrors().GetItems() do
      begin
        if (LError.Code = 'SM0331') and DoIsAt(LError, LMain, LLineF, LColF) and
          (LError.Message = 'field ''F'' of packed record ''TP'' cannot be packed: ''K'' is not plain data') then
          LHitF := True
        else if (LError.Code = 'SM0331') and DoIsAt(LError, LMain, LLineP, LColP) and
          (LError.Message = 'the parent of packed record ''TQ'' cannot be packed: ''TBad'' is not plain data') then
          LHitP := True
        else
          LElsewhere := LElsewhere + ' | ' + LError.Code + ' ' + LError.Message;
      end;
      Check(LHitF, 'packed_check on %s: SM0331 at F (%d,%d) (%s)',
        [LTarget, LLineF, LColF, DoReports(LCompiler.GetErrors())]);
      Check(LHitP, 'packed_check on %s: SM0331 at the parent TBad (%d,%d) (%s)',
        [LTarget, LLineP, LColP, DoReports(LCompiler.GetErrors())]);
      Check(LElsewhere = '', 'packed_check on %s: nothing else reported (%s)', [LTarget, LElsewhere]);
    finally
      LCompiler.Free();
    end;
  end;
end;

end.
