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
  PaskalCPP.Compiler - the facade that compiles one .pcpp program end to end

  TPCCompiler owns everything a compile needs on one TErrors: the AST, the
  semantic pass, the emitter and the ZigBuild driver. Compile(source, output,
  autorun) runs: parse and analysis always run within the error budget; emit
  and build stop at the first phase with errors:
    1 ParseModuleFile: the main file, imports recurse inside the parser
    2 TPCSemantics.Analyze: every module
    3 TPCEmitter.WriteFiles: every module to <output>\generated
    4 TPCZigBuild: settings in this order -
        the caller's re-exported settings (replayed on a fresh driver),
        the option defaults (SetKeyDefault: the CLI's with --defaults, as the
        editor runs it; a directive wins over them),
        the build directives of every module (main-only rows from the main),
        the libraries every `external` clause names,
        the option overrides (SetKeyValue: the CLI's; they win over a directive),
        the derived settings (project name, build mode, target, generated
        TUs, the runtime, PCPP_BUILD_DLL / PCPP_DEBUG, the translator)
    5 Process, then Run when asked and the program is an exe
  The main module is an exe, dll or lib: a unit main is the parser's PR0004.

  Dependencies: StdApp.Base (TBaseObject, TErrors), StdApp.Utils (paths),
    StdApp.Resources (RSCmp*), PaskalCPP.Common, PaskalCPP.AST,
    PaskalCPP.Parser, PaskalCPP.Semantics, PaskalCPP.Emitter,
    PaskalCPP.ZigBuild
  Notes: a fresh AST, phases and driver per Compile: nothing carries over
    between two compiles except the caller's settings and the overrides.
===============================================================================}

unit PaskalCPP.Compiler;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Utils,
  PaskalCPP.Common,
  PaskalCPP.SourceText,
  PaskalCPP.AST,
  PaskalCPP.Parser,
  PaskalCPP.Semantics,
  PaskalCPP.Emitter,
  PaskalCPP.ZigBuild;

const
  { PC_ERR_CMP_001 }
  PC_ERR_CMP_001 = 'CMP0001';   // source file or option error
  { PC_ERR_CMP_002 }
  PC_ERR_CMP_002 = 'CMP0002';   // auto-run skipped (not an exe)
  { PC_ERR_CMP_003 }
  PC_ERR_CMP_003 = 'CMP0003';   // internal error (an invariant)
  { PC_ERR_CMP_004 }
  PC_ERR_CMP_004 = 'CMP0004';   // warning: a stale published runtime library could not be removed
  { PC_ERR_CMP_005 }
  PC_ERR_CMP_005 = 'CMP0005';   // warning: the output record could not be written
  { PC_ERR_CMP_006 }
  PC_ERR_CMP_006 = 'CMP0006';   // pcpp --clean refuses a folder (the check that failed is named)

  { PC_CMP_OUTPUT_RECORD }
  // pcpp's own record of an output folder, written by every build (beside
  // build.zig): what pcpp --clean proves the folder is a pcpp one with
  PC_CMP_OUTPUT_RECORD = 'pcpp-output.json';
  { PC_CMP_OUTPUT_FORMAT }
  // The record's format: raised only for a change that breaks the meaning of
  // an existing key (a new key is added without it; readers ignore unknown keys)
  PC_CMP_OUTPUT_FORMAT = 1;
  { PC_CMP_RECORD_FORMAT }
  PC_CMP_RECORD_FORMAT = 'format';
  { PC_CMP_RECORD_SOURCE }
  PC_CMP_RECORD_SOURCE = 'source';
  { PC_CMP_RECORD_OUTPUT }
  PC_CMP_RECORD_OUTPUT = 'output';
  { PC_CMP_RECORD_PROJECT }
  PC_CMP_RECORD_PROJECT = 'project';
  { PC_CMP_BUILD_FILE }
  // The build file zig builds an output folder from (TPCZigBuild.SaveBuildFile)
  PC_CMP_BUILD_FILE = 'build.zig';

  { PC_SYNTAX_CODE_PREFIXES }
  // The codes of the phases that read the text as written: the lexer
  // (PaskalCPP.Lexer LX*), the conditional filter (PaskalCPP.Conditionals
  // CD*), the parser (PaskalCPP.Parser PR*)
  PC_SYNTAX_CODE_PREFIXES: array[0..2] of string = (
    'LX',
    'CD',
    'PR'
  );

  { PC_CMP_GENERATED_DIR }
  // Where the emitted C++ goes, under the output folder
  PC_CMP_GENERATED_DIR = 'generated';
  { PC_CMP_DEFAULT_OUTPUT }
  PC_CMP_DEFAULT_OUTPUT = 'output';
  { PC_CMP_RUNTIME_SOURCE }
  // The runtime TU in ZigBuild's runtime folder (GetRuntimePath)
  PC_CMP_RUNTIME_SOURCE = 'pcpp_runtime.cpp';
  { PC_CMP_DEFINE_DLL }
  PC_CMP_DEFINE_DLL = 'PCPP_BUILD_DLL';
  { PC_CMP_DEFINE_DEBUG }
  PC_CMP_DEFINE_DEBUG = 'PCPP_DEBUG';
  { PC_CMP_RUNTIME_NAME }
  // The runtime library a lib that uses the runtime ships beside it (r5
  // D-R5-3): its project name, so the artifact is pcpp_runtime.lib /
  // libpcpp_runtime.a by ZigBuild's naming
  PC_CMP_RUNTIME_NAME = 'pcpp_runtime';
  { PC_CMP_RUNTIME_DIR }
  // That library's own build folder under the output path
  PC_CMP_RUNTIME_DIR = 'runtime';

  { PC_CMP_KEY_OPTIMIZE }
  // Option keys: overrides (SetKeyValue) are applied after the directives,
  // defaults (SetKeyDefault) before them
  PC_CMP_KEY_OPTIMIZE = 'optimize';
  { PC_CMP_KEY_SUBSYSTEM }
  PC_CMP_KEY_SUBSYSTEM = 'subsystem';
  { PC_CMP_KEY_TARGET }
  // An LLVM triple, as @target (BNF sec 2): goes to the parser (the filter
  // decides with it which conditionals are active)
  PC_CMP_KEY_TARGET = 'target';

  { PC_CMP_ON }
  // @addverinfo's value that switches it on (PC_DIRECTIVE_VALUES)
  PC_CMP_ON = 'on';

  { PC_CMP_OPTIMIZE_TEXT }
  // The @optimize / optimize spelling of each level (PC_DIRECTIVE_VALUES)
  PC_CMP_OPTIMIZE_TEXT: array[TPCOptimizeLevel] of string = (
    'debug',
    'safe',
    'fast',
    'small'
  );

  { PC_CMP_SUBSYSTEM_TEXT }
  // The @subsystem / subsystem spelling of each subsystem (PC_DIRECTIVE_VALUES)
  PC_CMP_SUBSYSTEM_TEXT: array[TPCSubsystemType] of string = (
    'console',
    'gui'
  );

  { PC_CMP_BUILD_MODES }
  // The build each module kind is (a unit is never built)
  PC_CMP_BUILD_MODES: array[mkExe..mkLib] of TPCBuildMode = (
    bmExe,
    bmDll,
    bmLib
  );

  { PC_CMP_KIND_TEXT }
  // A module kind as the header spells it (messages)
  PC_CMP_KIND_TEXT: array[TPCModuleKind] of string = (
    'exe',
    'dll',
    'lib',
    'unit'
  );

type
  { TPCZigSetup }
  // One caller setting, replayed on each compile's fresh driver
  TPCZigSetup = reference to procedure(const AZig: TPCZigBuild);

  { TPCCompiler }
  TPCCompiler = class(TBaseObject)
  private
    FAst: TPCAst;
    FSemantics: TPCSemantics;
    FEmitter: TPCEmitter;
    FZigBuild: TPCZigBuild;
    FSetup: TList<TPCZigSetup>;       // the program's settings: the main driver only
    FToolSetup: TList<TPCZigSetup>;   // the session's (output, progress, raw output, build.toml): every driver
    FKeyValues: TDictionary<string, string>;     // overrides: win over a directive
    FKeyDefaults: TDictionary<string, string>;   // defaults: a directive wins over them
    FModulePaths: TArray<string>;                // AddModulePath, in order: the main parser's first module paths
    FMainModule: TPCModule;
    FSourceFile: string;
    FOutputPath: string;
    FOutputGiven: Boolean;        // Prepare got an explicit folder (-o): @outputpath does not apply
    FGeneratedPath: string;
    FProjectName: string;
    FLastExitCode: Cardinal;
    FPrepared: Boolean;   // the last Prepare succeeded: Build may run
    FSourceProvider: TPCSourceProvider;          // texts that win over the disk (the LSP's buffers); nil = disk
    // Printing only (DoDisplayColumn): each reported file's bytes, read once
    // when a location of it is printed; nil = could not be read
    FDisplaySources: TObjectDictionary<string, TPCSourceText>;

    procedure DoAddSetup(const ASetup: TPCZigSetup);
    procedure DoAddToolSetup(const ASetup: TPCZigSetup);
    procedure DoApplyToolSetup(const AZig: TPCZigBuild);
    function DoBuildRuntimeLib(): Boolean;
    procedure DoRemoveStaleRuntimeLib();
    function DoDisplayColumn(const AFilename: string; const ALine: UInt64;
      const AColumn: UInt64): UInt64;
    function DoIsGeneratedFile(const AFilename: string): Boolean;
    function DoFrontendCheck(const AFilename: string; const ALine: UInt64;
      const AColumn: UInt64; const AMessage: string; const AEvaluated: string;
      const AFlag: string; out ACode: string; out AText: string; out AOutFilename: string;
      out AOutLine: UInt64; out AOutColumn: UInt64): Boolean;
    // PLAN-VENDOR 1e: DoFrontendCheck's two format cases. A std::format_string
    // argument clang could not check (SM0502 / SM0500), and the runtime's
    // format_arg check at a C++ routine's call (SM0425); True = owned
    function DoFormatStringCheck(const AFilename: string; const ALine: UInt64;
      const AColumn: UInt64; out ACode: string; out AText: string; out AOutFilename: string;
      out AOutLine: UInt64; out AOutColumn: UInt64): Boolean;
    function DoFormatArgCheck(const AFilename: string; const ALine: UInt64;
      const AColumn: UInt64; out ACode: string; out AText: string; out AOutFilename: string;
      out AOutLine: UInt64; out AOutColumn: UInt64): Boolean;
    procedure DoInternalError(const AException: Exception);
    procedure DoFreePhases();
    procedure DoCreatePhases();
    function DoResolveSource(const ASourceFile: string): Boolean;
    function DoPrepare(const ASourceFile: string; const AOutputPath: string): Boolean;
    function DoAnalyze(const ACheckOnly: Boolean): Boolean;
    function DoApplyOutputPath(): Boolean;
    function DoFrontend(): Boolean;
    procedure DoApplyDirective(const ADirective: TPCDirective);
    procedure DoApplyDirectives(const AModule: TPCModule; const AIsMain: Boolean);
    procedure DoCollectLinks(const ANode: TPCNode);
    function DoApplyKeys(const AKeys: TDictionary<string, string>): Boolean;
    function DoKeyTarget(const AKeys: TDictionary<string, string>;
      out ATarget: TPCTargetTriple): Boolean;
    procedure DoApplyDerived();
    function DoConfigureBuild(): Boolean;
    function DoValidateAutoRun(const AAutoRun: Boolean): Boolean;
    procedure DoWriteOutputRecord();
    // pcpp --clean's checks, each one concern; False = refused (CMP0006
    // added, naming the folder and the reason)
    procedure DoCleanRefuse(const AFolder: string; const AReason: string);
    function DoCheckCleanPlace(const AFolder: string): Boolean;
    function DoReadOutputRecord(const AFolder: string; out ASource: string;
      out AProject: string): Boolean;
    function DoCheckCleanBuildFile(const AFolder: string; const AProject: string): Boolean;
    function DoCheckCleanSource(const AFolder: string; const ASource: string): Boolean;
    function DoCollectCleanTargets(const AFolder: string;
      out ATargets: TArray<string>): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Top-level owner of FErrors: an outside instance is never adopted
    procedure SetErrors(const AErrors: TErrors); override;
    procedure SetStatusCallback(const ACallback: TStatusCallback;
      const AUserData: Pointer = nil);
    procedure SetMaxErrors(const AMaxErrors: Integer);

    // Option overrides ('optimize', 'subsystem', 'target'): win over the
    // directives (pcpp run from the command line)
    procedure SetKeyValue(const AKey: string; const AValue: string);
    function GetKeyValue(const AKey: string): string;
    // Option defaults (same keys): a directive wins over them (pcpp run by
    // the editor, --defaults); an override for the same key wins over both
    procedure SetKeyDefault(const AKey: string; const AValue: string);
    function GetKeyDefault(const AKey: string): string;

    // Prepare + Build
    procedure Compile(const ASourceFile: string; const AOutputPath: string;
      const AAutoRun: Boolean = False);
    // Everything up to the build: parse, analyze, emit and configure the
    // driver. False = errors reported
    function Prepare(const ASourceFile: string; const AOutputPath: string): Boolean;
    // Parse + analyze only (the editor's LSP): the errors a build would report
    // before emitting, except the build-only PR0004 (a unit may be checked on
    // its own); nothing is written. False = errors reported
    function Analyze(const ASourceFile: string): Boolean;
    // Texts that win over the disk for every file the frontend reads (an
    // editor's open buffers); nil = the disk only
    procedure SetSourceProvider(const AProvider: TPCSourceProvider);
    // Builds what Prepare configured, then runs it when asked and it is an
    // exe. False = errors reported (or nothing prepared)
    function Build(const AAutoRun: Boolean = False): Boolean;
    // Runs the last built exe; False when nothing was built or it failed
    function Run(): Boolean;
    // Clears the output folder of the last Prepare: generated\ (what the
    // Compiler writes), then the driver's folders (TPCZigBuild.ClearOutput).
    // Each folder is tried and each failure reported; False when nothing was
    // prepared (as Build / Run) or a folder stayed
    function ClearOutput(): Boolean;
    // pcpp --clean: proves AFolder ('' = the current folder) is a pcpp
    // output folder, both records present and in step (pcpp-output.json and
    // build.zig), and is no drive root and not the source's own folder or
    // above it. AResolved = the folder; ATargets = what CleanFolder would
    // delete that exists now, in its order. Reads only, never deletes. False
    // = refused, the failed check reported (CMP0006)
    function CheckCleanFolder(const AFolder: string; out AResolved: string;
      out ATargets: TArray<string>): Boolean;
    // Runs every CheckCleanFolder check again, then deletes the targets (the
    // driver's link-safe delete). False = refused or a target stayed (each
    // reported)
    function CleanFolder(const AFolder: string): Boolean;
    function HasErrors(): Boolean;
    procedure PrintErrors(const ASeverities: TErrorSeverities = [esHint, esWarning, esError, esFatal]);
    function GetErrors(): TErrors;
    // Exit code of the last run program (0 when none ran)
    function GetLastExitCode(): Cardinal;
    // The last compile's values ('' before the first build)
    function GetOutputPath(): string;
    function GetOutputFilename(): string;
    // The built artifact's full path (ZigBuild's layout rule)
    function GetArtifactPath(): string;
    function GetTarget(): string;
    function GetMainModule(): TPCModule;
    // A report of the lexer (LX), the conditional filter (CD) or the parser
    // (PR): the text does not parse as written (SEM and later reports do not
    // count)
    class function IsSyntaxReport(const AError: TError): Boolean; static;
    // The last run holds a syntax report for AFilename (a report with no
    // file counts as the main file's); '' = for any file
    function HasSyntaxReport(const AFilename: string): Boolean;
    // The last run's directive paths SEM tested against the disk (none
    // before SEM ran): what the LSP server watches for an open file
    function DiskPaths(): TArray<string>;
    // The driver's final settings after Prepare (read back by tools and
    // tests); before the first Prepare they are ZigBuild's defaults
    function GetProjectName(): string;
    function GetBuildMode(): TPCBuildMode;
    function GetOptimizeLevel(): TPCOptimizeLevel;
    function GetSubsystem(): TPCSubsystemType;
    function HasDefine(const ADefineName: string): Boolean;
    function GenerateBuildZig(): string;

    // Re-exported ZigBuild settings: kept for every compile and applied
    // before the directives, so a directive or an override wins over them
    procedure SetOutputCallback(const ACallback: TCaptureConsoleCallback;
      const AUserData: Pointer = nil);
    procedure SetProgressCallback(const ACallback: TCaptureConsoleTick;
      const AUserData: Pointer = nil);
    procedure SetRawOutput(const AValue: Boolean);
    procedure SetRunArguments(const AArguments: string);
    // Run's keyboard and terminal size (TPCZigBuild.SetRunHost; not owned)
    // and its program's output (TPCZigBuild.SetRunOutputCallback)
    procedure SetRunHost(const AHost: TPtyHost);
    procedure SetRunOutputCallback(const ACallback: TCaptureConsoleCallback;
      const AUserData: Pointer = nil);
    procedure SetOptimizeLevel(const AOptimizeLevel: TPCOptimizeLevel);
    procedure SetSubsystem(const ASubsystem: TPCSubsystemType);
    procedure AddSourceFile(const ASourceFile: string);
    // A folder imports are searched in, for every compile. Create adds
    // PC_STD_MODULE_PATH first. Handed to the parser in order
    // (TPCParser.AddModulePath: resolved there, a folder already added is not
    // added again, the main module's @addmodulepath folders come after)
    procedure AddModulePath(const APath: string);
    function GetModulePaths(): TArray<string>;
    procedure AddIncludePath(const APath: string);
    procedure AddLibraryPath(const APath: string);
    procedure AddLinkLibrary(const ALibrary: string);
    procedure SetDefine(const ADefineName: string); overload;
    procedure SetDefine(const ADefineName: string; const AValue: string); overload;
    procedure UnsetDefine(const ADefineName: string);
    procedure AddCopyDLL(const ADLLPath: string);
    procedure AddPostBuildCopy(const ASourceFile: string; const ADestDir: string);
    procedure SetExeIcon(const AValue: string);
    // Where build.toml is read from. Not SetToolchainPath: ZigBuild persists
    // that into build.toml, a setting of the install, not of one compile
    procedure SetBuildConfigPath(const APath: string);

    // The level / subsystem spelled AText (PC_CMP_OPTIMIZE_TEXT /
    // PC_CMP_SUBSYSTEM_TEXT, exact case); False = none
    class function FindOptimizeLevel(const AText: string;
      out ALevel: TPCOptimizeLevel): Boolean; static;
    class function FindSubsystem(const AText: string;
      out ASubsystem: TPCSubsystemType): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.JSON,
  StdApp.JSON,
  StdApp.Resources;

{ TPCCompiler }

constructor TPCCompiler.Create();
begin
  inherited;

  FErrors := TErrors.Create();
  FSetup := TList<TPCZigSetup>.Create();
  FToolSetup := TList<TPCZigSetup>.Create();
  FKeyValues := TDictionary<string, string>.Create();
  FKeyDefaults := TDictionary<string, string>.Create();
  FAst := nil;
  FSemantics := nil;
  FEmitter := nil;
  FZigBuild := nil;
  FMainModule := nil;
  FSourceFile := '';
  FOutputPath := '';
  FOutputGiven := False;
  FGeneratedPath := '';
  FProjectName := '';
  FLastExitCode := 0;
  FPrepared := False;

  // The standard library's units are found by every program
  FModulePaths := nil;
  AddModulePath(PC_STD_MODULE_PATH);

  // Every printed location shows the column a person and an editor count
  // (UTF-16, as Monaco / LSP); stored columns stay bytes (clang's unit)
  FDisplaySources := TObjectDictionary<string, TPCSourceText>.Create([doOwnsValues]);
  FErrors.SetColumnMapper(DoDisplayColumn);

  // A driver from the start: the getters read ZigBuild's defaults until the
  // first Prepare replaces it (ZigBuild's Create does no file I/O)
  DoCreatePhases();
end;

destructor TPCCompiler.Destroy();
begin
  DoFreePhases();
  FreeAndNil(FKeyDefaults);
  FreeAndNil(FKeyValues);
  FreeAndNil(FToolSetup);
  FreeAndNil(FSetup);
  // The mapper refers to FDisplaySources: unhook it before either goes
  FErrors.SetColumnMapper(nil);
  FreeAndNil(FDisplaySources);
  FreeAndNil(FErrors);

  inherited;
end;

function TPCCompiler.DoIsGeneratedFile(const AFilename: string): Boolean;
var
  LIndex: Integer;
  LName: string;
begin
  // The files WriteFiles wrote for this build: each module's header and
  // source under <output>\generated, named from the AST. Never a test of the
  // folder alone: what a person keeps there is not the compiler's
  Result := False;
  if (FAst = nil) or (FGeneratedPath = '') then
    Exit;
  for LIndex := 0 to FAst.ModuleCount() - 1 do
  begin
    LName := FAst.ModuleAt(LIndex).ModuleName;
    if TUtils.SamePath(AFilename,
         TUtils.JoinResolvedPath(FGeneratedPath, LName + PC_EMT_HEADER_EXT)) or
       TUtils.SamePath(AFilename,
         TUtils.JoinResolvedPath(FGeneratedPath, LName + PC_EMT_SOURCE_EXT)) then
      Exit(True);
  end;
end;

function TPCCompiler.DoFrontendCheck(const AFilename: string; const ALine: UInt64;
  const AColumn: UInt64; const AMessage: string; const AEvaluated: string;
  const AFlag: string; out ACode: string; out AText: string; out AOutFilename: string;
  out AOutLine: UInt64; out AOutColumn: UInt64): Boolean;
var
  LRecord: TPCRecordType;
  LArg: TPCExpr;
  LTypeName: string;
  LValueText: string;
  LNaturalText: string;
  LNatural: UInt64;
  LAt: Integer;
  LOwner: TPCNode;
  LRecordName: string;
  LFieldName: string;
  LMethod: TPCMethodItem;
  LCppParent: string;
  LRange: TSourceRange;
begin
  // One of the emitter's align checks failed: its code at the record's align
  // value, the message SEM writes for it (TPCSemantics.Align*Text). The
  // record and the value come from the AST at clang's location (r-b-align.md
  // D2). SM0311's natural alignment is clang's own number, the right side of
  // its note ('4 >= 8': the condition is always <value> >= <one value>, P5);
  // SM0310 / SM0312 (F31: a C++ value) need no number
  Result := False;
  ACode := '';
  AText := '';
  AOutFilename := AFilename;
  AOutLine := ALine;
  AOutColumn := AColumn;
  if FAst = nil then
    Exit;
  // PLAN-OBJECT O13b (D7 across D14): clang's -Wsuggest-override, an error
  // only inside the class of an object whose chain reaches C/C++: one of its
  // methods overrides a C/C++ parent's virtual without `override`. SM0332 at
  // the method's `virtual` word or name, as SEM reports a PaskalCPP
  // ancestor's (TPCSemantics.NeedsOverrideText)
  if AFlag = PC_FRONTEND_FLAG_OVERRIDE then
  begin
    if not FAst.CppOverrideAt(AFilename, ALine, AColumn, LMethod, LCppParent, LRecordName) then
      Exit;
    if LMethod.IsVirtual then
      LRange := LMethod.VirtualRange
    else
      LRange := LMethod.Routine.NameRange;
    ACode := PC_ERR_SEM_332;
    AText := TPCSemantics.NeedsOverrideText(LMethod.Routine.DeclName, LCppParent);
    AOutFilename := LRange.Filename;
    AOutLine := LRange.StartLine;
    AOutColumn := LRange.StartColumn;
    Exit(True);
  end;
  // PLAN-OBJECT O13b (4): an `override` on a chain reaching C/C++ with no
  // PaskalCPP base is written through for clang to judge; clang's own error
  // when it overrides nothing (its texts, PC_CLANG_OVERRIDE_*: no warning
  // group) is reported in SEM's words, only at such a method: a C/C++
  // virtual of the name it does not match (parameters, result, const) is
  // SM0334 at the name, none of the name SM0333 at `override`
  if AMessage.Contains(PC_CLANG_OVERRIDE_HIDES) or AMessage.Contains(PC_CLANG_OVERRIDE_NOTHING) or
    AMessage.Contains(PC_CLANG_OVERRIDE_NOT_VIRTUAL) then
  begin
    if not FAst.CppOverrideAt(AFilename, ALine, AColumn, LMethod, LCppParent, LRecordName) then
      Exit;
    if not LMethod.IsOverride then
      Exit;
    if AMessage.Contains(PC_CLANG_OVERRIDE_HIDES) then
    begin
      ACode := PC_ERR_SEM_334;
      AText := TPCSemantics.OverrideCppSignatureText(LMethod.Routine.DeclName, LCppParent);
      LRange := LMethod.Routine.NameRange;
    end
    else
    begin
      ACode := PC_ERR_SEM_333;
      AText := TPCSemantics.OverridesNothingText(LMethod.Routine.DeclName, LRecordName);
      LRange := LMethod.OverrideRange;
    end;
    AOutFilename := LRange.Filename;
    AOutLine := LRange.StartLine;
    AOutColumn := LRange.StartColumn;
    Exit(True);
  end;
  // PLAN-VENDOR 1e: a std::format_string argument clang could not check
  // against the arguments after it (no warning group: its texts,
  // PC_CLANG_FORMAT_STRING)
  if AMessage.Contains(PC_CLANG_FORMAT_STRING) and AMessage.Contains(PC_CLANG_NOT_CONSTANT) then
    Exit(DoFormatStringCheck(AFilename, ALine, AColumn, ACode, AText, AOutFilename, AOutLine,
      AOutColumn));
  // PLAN-OBJECT O13b: a rule SEM left to clang's view of an object's
  // polymorphism (a C/C++ base): the expression SEM marked, its code by the
  // rule, SEM's own message (TPCExpr.ResolvedPolyText)
  if AMessage.EndsWith(PC_FRONTEND_CHECK_POLY) then
  begin
    if not FAst.PolyCheckAt(AFilename, ALine, AColumn, LArg) then
      Exit;
    case LArg.ResolvedPolyCheck of
      pcIsPolymorphic:
        ACode := PC_ERR_SEM_271;
      pcSlice, pcSliceHeld:
        ACode := PC_ERR_SEM_428;
      pcSliceAssign:
        ACode := PC_ERR_SEM_429;
      pcOwnUpcast:
        ACode := PC_ERR_SEM_200;
    else
      Exit;
    end;
    AText := LArg.ResolvedPolyText;
    AOutFilename := LArg.Range.Filename;
    AOutLine := LArg.Range.StartLine;
    AOutColumn := LArg.Range.StartColumn;
    Exit(True);
  end;
  // E7: a print argument of a C/C++ type with no std::formatter: SM0425 at
  // the argument, its PaskalCPP type spelling; an opaque C/C++ type has no
  // PaskalCPP spelling (TypeText is 'opaque'), so the argument as written
  // names it (F64)
  if AMessage.EndsWith(PC_FRONTEND_CHECK_PRINT) then
  begin
    // PLAN-VENDOR 1e: not a print / println argument: the runtime's
    // format_arg check, asked at a C++ routine's call
    if not FAst.PrintArgAt(AFilename, ALine, AColumn, LArg) then
      Exit(DoFormatArgCheck(AFilename, ALine, AColumn, ACode, AText, AOutFilename, AOutLine,
        AOutColumn));
    if (LArg.ResolvedType <> nil) and (not (LArg.ResolvedType is TPCOpaqueType)) then
      LTypeName := LArg.ResolvedType.TypeText()
    else
      LTypeName := LArg.ExprText();
    ACode := PC_ERR_SEM_425;
    AText := TPCSemantics.PrintNoFormatterText(LTypeName);
    AOutFilename := LArg.Range.Filename;
    AOutLine := LArg.Range.StartLine;
    AOutColumn := LArg.Range.StartColumn;
    Exit(True);
  end;
  // F47: a type too large to exist, SM0277 in SEM's words: the runtime's
  // Array check (BuildOutput asks at each instantiation note: the use), or
  // clang's own record text at a PaskalCPP record's, overlay's or object's
  // name. A count SEM folded past any size is SEM's own report
  if AMessage.EndsWith(PC_FRONTEND_CHECK_SIZE) or AMessage.Contains(PC_CLANG_RECORD_TOO_LARGE) then
  begin
    if not FAst.SizeCheckAt(AFilename, ALine, AColumn, not AMessage.EndsWith(PC_FRONTEND_CHECK_SIZE),
      LRange, LTypeName) then
      Exit;
    ACode := PC_ERR_SEM_277;
    AText := TPCSemantics.TooLargeText(LTypeName);
    AOutFilename := LRange.Filename;
    AOutLine := LRange.StartLine;
    AOutColumn := LRange.StartColumn;
    Exit(True);
  end;
  // PLAN-RECORDS M9: a packed field (or parent) of a type only clang lays
  // out that does not pack: SM0331 at the field, its PaskalCPP spelling
  if AMessage.EndsWith(PC_FRONTEND_CHECK_PACKED) then
  begin
    if not FAst.FieldCheckAt(AFilename, ALine, AColumn, LOwner, LRecordName, LFieldName, LTypeName) then
      Exit;
    ACode := PC_ERR_SEM_331;
    AText := TPCSemantics.PackedFieldText(LFieldName, LRecordName, LTypeName, True);
    AOutFilename := LOwner.Range.Filename;
    AOutLine := LOwner.Range.StartLine;
    AOutColumn := LOwner.Range.StartColumn;
    Exit(True);
  end;
  // F34: an overlay's field (a union member) of a type only clang knows that
  // is not trivial data: SM0313 at the field, its PaskalCPP spelling
  if AMessage.EndsWith(PC_FRONTEND_CHECK_OVERLAY) then
  begin
    if not FAst.FieldCheckAt(AFilename, ALine, AColumn, LOwner, LRecordName, LFieldName, LTypeName) then
      Exit;
    if not (LOwner is TPCField) then
      Exit;
    ACode := PC_ERR_SEM_313;
    AText := TPCSemantics.OverlayFieldText(LFieldName, LRecordName, LTypeName, True);
    AOutFilename := LOwner.Range.Filename;
    AOutLine := LOwner.Range.StartLine;
    AOutColumn := LOwner.Range.StartColumn;
    Exit(True);
  end;
  if not (AMessage.EndsWith(PC_FRONTEND_CHECK_NATURAL) or AMessage.EndsWith(PC_FRONTEND_CHECK_POWER) or
    AMessage.EndsWith(PC_FRONTEND_CHECK_MAX)) then
    Exit;
  if not FAst.AlignRecordAt(AFilename, ALine, AColumn, LRecord, LTypeName) then
    Exit;

  // The value as SEM prints a folded one; a C++ value in its PaskalCPP spelling
  if not TPCAst.FoldedText(LRecord.AlignExpr, LValueText) then
    LValueText := LRecord.AlignExpr.ExprText();

  if AMessage.EndsWith(PC_FRONTEND_CHECK_POWER) then
  begin
    ACode := PC_ERR_SEM_310;
    AText := TPCSemantics.AlignPowerText(LValueText);
  end
  else if AMessage.EndsWith(PC_FRONTEND_CHECK_MAX) then
  begin
    ACode := PC_ERR_SEM_312;
    AText := TPCSemantics.AlignMaxText(LValueText);
  end
  else
  begin
    LAt := AEvaluated.LastIndexOf('>= ');
    if LAt < 0 then
      Exit;
    LNaturalText := AEvaluated.Substring(LAt + Length('>= ')).Trim();
    if not TryStrToUInt64(LNaturalText, LNatural) then
      Exit;
    ACode := PC_ERR_SEM_311;
    AText := TPCSemantics.AlignNaturalText(LValueText, LNatural, LTypeName);
  end;
  AOutFilename := LRecord.AlignExpr.Range.Filename;
  AOutLine := LRecord.AlignExpr.Range.StartLine;
  AOutColumn := LRecord.AlignExpr.Range.StartColumn;
  Result := True;
end;

function TPCCompiler.DoFormatStringCheck(const AFilename: string; const ALine: UInt64;
  const AColumn: UInt64; out ACode: string; out AText: string; out AOutFilename: string;
  out AOutLine: UInt64; out AOutColumn: UInt64): Boolean;
var
  LCall: TPCCall;
  LArgIndex: Integer;
  LArg: TPCExpr;
  LDecl: TPCNode;
  LWide: Boolean;
begin
  // clang's location is the format string argument (println's, a C++
  // routine's: TPCAst.CallAt). A string literal, or a string const holding
  // one, does not fit the arguments after it (SM0502); any other value is no
  // text the build can check: a string variable never is a C++ constant
  // (SM0500). A location in verbatim C++ (no PaskalCPP call's argument)
  // stays clang's
  Result := False;
  ACode := '';
  AText := '';
  AOutFilename := AFilename;
  AOutLine := ALine;
  AOutColumn := AColumn;
  if not FAst.CallAt(AFilename, ALine, AColumn, LCall, LArgIndex) then
    Exit;
  if LArgIndex < 0 then
    Exit;

  LArg := LCall.Args[LArgIndex];
  // A string const holding a literal is read as its constant text there
  // (TPCConstDecl.HasConstText): its text is checked, as a literal's is
  LDecl := nil;
  if LArg is TPCName then
    LDecl := TPCName(LArg).ResolvedDecl
  else if LArg is TPCMember then
    LDecl := TPCMember(LArg).ResolvedDecl;
  if ((LArg is TPCLiteral) and (TPCLiteral(LArg).LiteralKind = lkString)) or
    ((LDecl is TPCConstDecl) and TPCConstDecl(LDecl).HasConstText(LWide)) then
  begin
    ACode := PC_ERR_SEM_502;
    AText := TPCSemantics.FormatMismatchText(LArg.ExprText(), LCall.Args.Count - LArgIndex - 1);
  end
  else
  begin
    ACode := PC_ERR_SEM_500;
    AText := TPCSemantics.FormatNotLiteralText(LArg.ExprText());
  end;
  AOutFilename := LArg.Range.Filename;
  AOutLine := LArg.Range.StartLine;
  AOutColumn := LArg.Range.StartColumn;
  Result := True;
end;

function TPCCompiler.DoFormatArgCheck(const AFilename: string; const ALine: UInt64;
  const AColumn: UInt64; out ACode: string; out AText: string; out AOutFilename: string;
  out AOutLine: UInt64; out AOutColumn: UInt64): Boolean;
var
  LCall: TPCCall;
  LArgIndex: Integer;
  LIndex: Integer;
  LAt: TPCNode;
  LCppArg: TPCExpr;
  LCppCount: Integer;
begin
  // The runtime's format_arg check failed while a C++ routine's parameter
  // types were formed (SysUtils.FormatStr): clang names the call only in its
  // substitution note, not which argument. The AST tells what it can: the
  // first argument with no print form (a record, object or overlay; SEM's
  // own text), else the one C/C++ argument (std::formatter is clang's to
  // know), else the call itself
  Result := False;
  ACode := '';
  AText := '';
  AOutFilename := AFilename;
  AOutLine := ALine;
  AOutColumn := AColumn;
  if not FAst.CallAt(AFilename, ALine, AColumn, LCall, LArgIndex) then
    Exit;

  LAt := nil;
  LCppArg := nil;
  LCppCount := 0;
  for LIndex := 0 to LCall.Args.Count - 1 do
  begin
    AText := TPCSemantics.UnprintableArgText(LCall.Args[LIndex]);
    if AText <> '' then
    begin
      LAt := LCall.Args[LIndex];
      Break;
    end;
    if TPCTypeExpr.PrintFormOfArg(LCall.Args[LIndex]) = pfCppChecked then
    begin
      Inc(LCppCount);
      LCppArg := LCall.Args[LIndex];
    end;
  end;

  if LAt = nil then
  begin
    if LCppCount = 1 then
    begin
      // Its PaskalCPP spelling, else as written (F64: an opaque type has none)
      LAt := LCppArg;
      if (LCppArg.ResolvedType <> nil) and (not (LCppArg.ResolvedType is TPCOpaqueType)) then
        AText := TPCSemantics.PrintNoFormatterText(LCppArg.ResolvedType.TypeText())
      else
        AText := TPCSemantics.PrintNoFormatterText(LCppArg.ExprText());
    end
    else
    begin
      LAt := LCall;
      if LCall.Callee <> nil then
        AText := TPCSemantics.NoFormatterArgsText(LCall.Callee.ExprText())
      else
        AText := TPCSemantics.NoFormatterArgsText(LCall.ExprText());
    end;
  end;
  ACode := PC_ERR_SEM_425;
  AOutFilename := LAt.Range.Filename;
  AOutLine := LAt.Range.StartLine;
  AOutColumn := LAt.Range.StartColumn;
  Result := True;
end;

function TPCCompiler.DoDisplayColumn(const AFilename: string; const ALine: UInt64;
  const AColumn: UInt64): UInt64;
var
  LText: TPCSourceText;
  LBytes: TBytes;
begin
  Result := AColumn;
  if not FDisplaySources.TryGetValue(AFilename, LText) then
  begin
    LText := nil;
    try
      LBytes := TFile.ReadAllBytes(TUtils.ResolvePath(AFilename));
      LText := TPCSourceText.Create();
      LText.Init(LBytes, AFilename);
    except
      // Runs inside TErrors' printing, which cannot take a new item: a file
      // that cannot be read prints its stored (byte) columns
      FreeAndNil(LText);
    end;
    FDisplaySources.Add(AFilename, LText);
  end;
  if LText <> nil then
    Result := LText.Utf16Column(ALine, AColumn);
end;

procedure TPCCompiler.SetErrors(const AErrors: TErrors);
begin
  // Owns its own FErrors (FreeStrike.Compiler.pas:178-181 pattern)
end;

procedure TPCCompiler.SetStatusCallback(const ACallback: TStatusCallback;
  const AUserData: Pointer);
begin
  FErrors.SetStatusCallback(ACallback, AUserData);
end;

procedure TPCCompiler.SetMaxErrors(const AMaxErrors: Integer);
begin
  FErrors.SetMaxErrors(AMaxErrors);
end;

procedure TPCCompiler.SetKeyValue(const AKey: string; const AValue: string);
begin
  FKeyValues.AddOrSetValue(AKey.ToLower(), AValue);
end;

function TPCCompiler.GetKeyValue(const AKey: string): string;
begin
  if not FKeyValues.TryGetValue(AKey.ToLower(), Result) then
    Result := '';
end;

procedure TPCCompiler.SetKeyDefault(const AKey: string; const AValue: string);
begin
  FKeyDefaults.AddOrSetValue(AKey.ToLower(), AValue);
end;

function TPCCompiler.GetKeyDefault(const AKey: string): string;
begin
  if not FKeyDefaults.TryGetValue(AKey.ToLower(), Result) then
    Result := '';
end;

function TPCCompiler.HasErrors(): Boolean;
begin
  Result := FErrors.HasErrors();
end;

procedure TPCCompiler.PrintErrors(const ASeverities: TErrorSeverities);
begin
  FErrors.PrintErrors(ASeverities);
end;

function TPCCompiler.GetErrors(): TErrors;
begin
  Result := FErrors;
end;

function TPCCompiler.GetLastExitCode(): Cardinal;
begin
  Result := FLastExitCode;
end;

function TPCCompiler.GetOutputPath(): string;
begin
  Result := FOutputPath;
end;

function TPCCompiler.GetOutputFilename(): string;
begin
  Result := FZigBuild.GetOutputFilename();
end;

function TPCCompiler.GetArtifactPath(): string;
begin
  Result := FZigBuild.GetArtifactPath();
end;

function TPCCompiler.GetTarget(): string;
begin
  Result := FZigBuild.GetTarget();
end;

function TPCCompiler.GetMainModule(): TPCModule;
begin
  Result := FMainModule;
end;

class function TPCCompiler.IsSyntaxReport(const AError: TError): Boolean;
var
  LPrefix: string;
begin
  for LPrefix in PC_SYNTAX_CODE_PREFIXES do
  begin
    if AError.Code.StartsWith(LPrefix) then
      Exit(True);
  end;
  Result := False;
end;

function TPCCompiler.DiskPaths(): TArray<string>;
var
  LIndex: Integer;
  LFile: string;
begin
  // SEM's directive paths, then every module's own file (an imported unit
  // edited outside the editor), then every unit file an import lookup tried
  // (one not found yet, or one earlier in the search order); the main file
  // is the caller's to leave out, a repeat the caller's to drop
  Result := nil;
  if Assigned(FSemantics) then
    Result := FSemantics.DiskPaths();
  if not Assigned(FAst) then
    Exit;
  for LIndex := 0 to FAst.ModuleCount() - 1 do
  begin
    LFile := TUtils.StripLongPathPrefix(FAst.ModuleAt(LIndex).SourceFile);
    if LFile <> '' then
      Result := Result + [LFile];
  end;
  Result := Result + FAst.LookupPaths();
end;

function TPCCompiler.HasSyntaxReport(const AFilename: string): Boolean;
var
  LError: TError;
begin
  for LError in GetErrors().GetItems() do
  begin
    if not IsSyntaxReport(LError) then
      Continue;
    if (AFilename = '') or (LError.Range.Filename = '') then
      Exit(True);
    // A report path no file routine can take names no file, so not this
    // one (a query: nothing to report)
    try
      if TUtils.SamePath(LError.Range.Filename, AFilename) then
        Exit(True);
    except
      on Exception do
        Continue;
    end;
  end;
  Result := False;
end;

function TPCCompiler.GetProjectName(): string;
begin
  Result := FZigBuild.GetProjectName();
end;

function TPCCompiler.GetBuildMode(): TPCBuildMode;
begin
  Result := FZigBuild.GetBuildMode();
end;

function TPCCompiler.GetOptimizeLevel(): TPCOptimizeLevel;
begin
  Result := FZigBuild.GetOptimizeLevel();
end;

function TPCCompiler.GetSubsystem(): TPCSubsystemType;
begin
  Result := FZigBuild.GetSubsystem();
end;

function TPCCompiler.HasDefine(const ADefineName: string): Boolean;
begin
  Result := FZigBuild.HasDefine(ADefineName);
end;

function TPCCompiler.GenerateBuildZig(): string;
begin
  Result := FZigBuild.GenerateBuildZig();
end;

class function TPCCompiler.FindOptimizeLevel(const AText: string;
  out ALevel: TPCOptimizeLevel): Boolean;
var
  LLevel: TPCOptimizeLevel;
begin
  Result := False;
  ALevel := Low(TPCOptimizeLevel);
  for LLevel := Low(TPCOptimizeLevel) to High(TPCOptimizeLevel) do
  begin
    if PC_CMP_OPTIMIZE_TEXT[LLevel] = AText then
    begin
      ALevel := LLevel;
      Exit(True);
    end;
  end;
end;

class function TPCCompiler.FindSubsystem(const AText: string;
  out ASubsystem: TPCSubsystemType): Boolean;
var
  LSubsystem: TPCSubsystemType;
begin
  Result := False;
  ASubsystem := Low(TPCSubsystemType);
  for LSubsystem := Low(TPCSubsystemType) to High(TPCSubsystemType) do
  begin
    if PC_CMP_SUBSYSTEM_TEXT[LSubsystem] = AText then
    begin
      ASubsystem := LSubsystem;
      Exit(True);
    end;
  end;
end;

procedure TPCCompiler.DoAddSetup(const ASetup: TPCZigSetup);
begin
  FSetup.Add(ASetup);
end;

procedure TPCCompiler.DoAddToolSetup(const ASetup: TPCZigSetup);
begin
  FToolSetup.Add(ASetup);
end;

procedure TPCCompiler.DoApplyToolSetup(const AZig: TPCZigBuild);
var
  LSetup: TPCZigSetup;
begin
  // How builds are shown and where the toolchain is: the same for every
  // driver of the session, in the order they were made
  for LSetup in FToolSetup do
    LSetup(AZig);
end;

procedure TPCCompiler.SetOutputCallback(const ACallback: TCaptureConsoleCallback;
  const AUserData: Pointer);
begin
  DoAddToolSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.SetOutputCallback(ACallback, AUserData);
    end);
end;

procedure TPCCompiler.SetRunHost(const AHost: TPtyHost);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.SetRunHost(AHost);
    end);
end;

procedure TPCCompiler.SetRunOutputCallback(const ACallback: TCaptureConsoleCallback;
  const AUserData: Pointer);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.SetRunOutputCallback(ACallback, AUserData);
    end);
end;

procedure TPCCompiler.SetProgressCallback(const ACallback: TCaptureConsoleTick;
  const AUserData: Pointer);
begin
  DoAddToolSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.SetProgressCallback(ACallback, AUserData);
    end);
end;

procedure TPCCompiler.SetRawOutput(const AValue: Boolean);
begin
  DoAddToolSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.SetRawOutput(AValue);
    end);
end;

procedure TPCCompiler.SetRunArguments(const AArguments: string);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.SetRunArguments(AArguments);
    end);
end;

procedure TPCCompiler.SetOptimizeLevel(const AOptimizeLevel: TPCOptimizeLevel);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.SetOptimizeLevel(AOptimizeLevel);
    end);
end;

procedure TPCCompiler.SetSubsystem(const ASubsystem: TPCSubsystemType);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.SetSubsystem(ASubsystem);
    end);
end;

procedure TPCCompiler.AddSourceFile(const ASourceFile: string);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.AddSourceFile(ASourceFile);
    end);
end;

procedure TPCCompiler.AddModulePath(const APath: string);
begin
  // Kept as given: the parser resolves it and drops a folder already added
  FModulePaths := FModulePaths + [APath];
end;

function TPCCompiler.GetModulePaths(): TArray<string>;
begin
  Result := FModulePaths;
end;

procedure TPCCompiler.AddIncludePath(const APath: string);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.AddIncludePath(APath);
    end);
end;

procedure TPCCompiler.AddLibraryPath(const APath: string);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.AddLibraryPath(APath);
    end);
end;

procedure TPCCompiler.AddLinkLibrary(const ALibrary: string);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.AddLinkLibrary(ALibrary);
    end);
end;

procedure TPCCompiler.SetDefine(const ADefineName: string);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.SetDefine(ADefineName);
    end);
end;

procedure TPCCompiler.SetDefine(const ADefineName: string; const AValue: string);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.SetDefine(ADefineName, AValue);
    end);
end;

procedure TPCCompiler.UnsetDefine(const ADefineName: string);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.UnsetDefine(ADefineName);
    end);
end;

procedure TPCCompiler.AddCopyDLL(const ADLLPath: string);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.AddCopyDLL(ADLLPath);
    end);
end;

procedure TPCCompiler.AddPostBuildCopy(const ASourceFile: string; const ADestDir: string);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.AddPostBuildCopy(ASourceFile, ADestDir);
    end);
end;

procedure TPCCompiler.SetExeIcon(const AValue: string);
begin
  DoAddSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.SetExeIcon(AValue);
    end);
end;

procedure TPCCompiler.SetBuildConfigPath(const APath: string);
begin
  DoAddToolSetup(
    procedure(const AZig: TPCZigBuild)
    begin
      AZig.SetBuildConfigPath(APath);
    end);
end;

procedure TPCCompiler.DoFreePhases();
begin
  // The driver first: its location translator refers to FAst
  FreeAndNil(FZigBuild);
  FreeAndNil(FEmitter);
  FreeAndNil(FSemantics);
  FreeAndNil(FAst);
  FMainModule := nil;
  // A new compile reads the files again (they may have changed); nil before
  // Create made the dictionary
  if FDisplaySources <> nil then
    FDisplaySources.Clear();
end;

procedure TPCCompiler.DoCreatePhases();
var
  LSetup: TPCZigSetup;
begin
  FAst := TPCAst.Create();
  FAst.SetErrors(FErrors);
  FSemantics := TPCSemantics.Create();
  FSemantics.SetErrors(FErrors);
  FEmitter := TPCEmitter.Create();
  FEmitter.SetErrors(FErrors);
  FZigBuild := TPCZigBuild.Create();
  FZigBuild.SetErrors(FErrors);

  // The session's settings, then the program's, each in the order they were made
  DoApplyToolSetup(FZigBuild);
  for LSetup in FSetup do
    LSetup(FZigBuild);
end;

function TPCCompiler.DoResolveSource(const ASourceFile: string): Boolean;
var
  LSource: string;
  LExists: Boolean;
  LBytes: TBytes;
begin
  // A fresh AST, phases and driver per compile: no state carries over
  Result := False;
  FErrors.Clear();
  DoFreePhases();
  DoCreatePhases();

  // No extension = the PaskalCPP one; every path through TUtils.ResolvePath.
  // A file the source provider has exists (an editor buffer not saved yet)
  try
    LSource := ASourceFile;
    if TPath.GetExtension(LSource) = '' then
      LSource := LSource + '.' + PC_SRC_EXT;
    FSourceFile := TUtils.ResolvePath(LSource);
    FProjectName := TPath.GetFileNameWithoutExtension(FSourceFile);
    LExists := Assigned(FSourceProvider) and FSourceProvider(FSourceFile, LBytes);
    if not LExists then
      LExists := TFile.Exists(FSourceFile);
  except
    on E: Exception do
    begin
      FErrors.Add(esFatal, PC_ERR_CMP_001, RSCmpPathFailed, [ASourceFile, E.Message]);
      Exit;
    end;
  end;
  if not LExists then
  begin
    FErrors.Add(esFatal, PC_ERR_CMP_001, RSCmpSourceNotFound, [FSourceFile]);
    Exit;
  end;
  Result := True;
end;

function TPCCompiler.DoPrepare(const ASourceFile: string; const AOutputPath: string): Boolean;
var
  LOutput: string;
begin
  Result := False;
  if not DoResolveSource(ASourceFile) then
    Exit;

  // An explicit folder (-o) wins over the main module's @outputpath, as -t
  // over @target; without one the directive decides, else 'output'
  // (DoApplyOutputPath, once the source is read)
  LOutput := AOutputPath;
  FOutputGiven := LOutput.Trim() <> '';
  if not FOutputGiven then
    LOutput := PC_CMP_DEFAULT_OUTPUT;
  try
    FOutputPath := TUtils.ResolvePath(LOutput);
    FGeneratedPath := TUtils.JoinResolvedPath(FOutputPath, PC_CMP_GENERATED_DIR);
  except
    on E: Exception do
    begin
      FErrors.Add(esFatal, PC_ERR_CMP_001, RSCmpPathFailed, [LOutput, E.Message]);
      Exit;
    end;
  end;
  Result := True;
end;

function TPCCompiler.DoKeyTarget(const AKeys: TDictionary<string, string>;
  out ATarget: TPCTargetTriple): Boolean;
var
  LValue: string;
begin
  // AKeys' 'target' option (the overrides or the defaults). It decides the
  // conditionals (TARGET_* defines), so it goes to the parser before
  // anything is parsed: an override wins over the main module's @target, a
  // default only stands in for a missing one. Same check as @target
  // (TPCTargetTriple.Parse: a supported triple only)
  ATarget := Default(TPCTargetTriple);
  Result := True;
  if not AKeys.TryGetValue(PC_CMP_KEY_TARGET, LValue) then
    Exit;

  if TPCTargetTriple.Parse(LValue.Trim(), ATarget) <> tsOk then
  begin
    ATarget := Default(TPCTargetTriple);
    FErrors.Add(esError, PC_ERR_CMP_001, RSCmpBadOption,
      [LValue, PC_CMP_KEY_TARGET, TPCTargetTriple.SupportedTargetsText()]);
    Result := False;
  end;
end;

function TPCCompiler.DoAnalyze(const ACheckOnly: Boolean): Boolean;
var
  LOverride: TPCTargetTriple;
  LDefault: TPCTargetTriple;
  LKeysOk: Boolean;
begin
  // Parse (imports recurse in the parser), then analyze, both within the error
  // budget: SEM runs on whatever the parser built, recovered nodes included
  // (PLAN-RECOVERY); nothing is emitted with errors (DoFrontend). ACheckOnly:
  // the main file is checked, not built (Analyze), so it may be a unit (no
  // PR0004)
  Result := False;

  // Both checked, so a bad override and a bad default are both reported
  LKeysOk := DoKeyTarget(FKeyValues, LOverride);
  LKeysOk := DoKeyTarget(FKeyDefaults, LDefault) and LKeysOk;
  if not LKeysOk then
    Exit;

  // The compiler's module paths go to the main parser; it hands them (and
  // the source provider) to every import's parser
  FMainModule := ParseModuleFile(FAst, FErrors, FSourceFile, nil,
    Default(TPCTargetTriple), LOverride, LDefault, FModulePaths, FSourceProvider, ACheckOnly);

  FSemantics.Analyze(FAst);
  Result := not FErrors.HasErrors();
end;

function TPCCompiler.DoApplyOutputPath(): Boolean;
var
  LDirective: TPCDirective;
begin
  // The main module's @outputpath, when no -o was given: the parser resolved
  // its value once (TPCDirectiveArg.ResolvedText); everything the build
  // writes (generated C++, zig's folders, the artifact) goes there
  Result := True;
  if FOutputGiven or (FMainModule = nil) then
    Exit;
  for LDirective in FMainModule.Directives do
  begin
    if (LDirective.DirectiveKind <> bdOutputPath) or LDirective.ResolvedNoEffect or
      (LDirective.Args.Count = 0) or (not LDirective.Args[0].HasValue) then
      Continue;
    try
      FOutputPath := TUtils.ResolvePath(LDirective.Args[0].ResolvedText);
      FGeneratedPath := TUtils.JoinResolvedPath(FOutputPath, PC_CMP_GENERATED_DIR);
    except
      on E: Exception do
      begin
        FErrors.Add(esFatal, PC_ERR_CMP_001, RSCmpPathFailed, [LDirective.Args[0].ResolvedText, E.Message]);
        Exit(False);
      end;
    end;
  end;
end;

function TPCCompiler.DoFrontend(): Boolean;
begin
  // Parse and analyze (DoAnalyze), then emit
  Result := False;
  Status(RSCmpCompiling, [FSourceFile]);
  if not DoAnalyze(False) then
    Exit;
  if not DoApplyOutputPath() then
    Exit;

  FEmitter.Init(FAst, FMainModule);
  if not FEmitter.WriteFiles(FGeneratedPath) then
    Exit;
  Result := not FErrors.HasErrors();
end;

procedure TPCCompiler.DoApplyDirective(const ADirective: TPCDirective);
var
  LValue: string;
  LInt: UInt64;
  LLevel: TPCOptimizeLevel;
  LSubsystem: TPCSubsystemType;
begin
  // SEM checked every value (research\compiler\r4-directives.md): a value
  // the maps do not know is an invariant, raised and reported as CMP0003
  LValue := '';
  LInt := 0;
  if ADirective.Args.Count > 0 then
  begin
    LValue := ADirective.Args[0].ResolvedText;
    LInt := ADirective.Args[0].IntValue;
  end;

  case ADirective.DirectiveKind of
    bdOptimize:
      begin
        if not FindOptimizeLevel(LValue, LLevel) then
          raise Exception.CreateFmt(RSCmpBadOption, [LValue, ADirective.DirectiveName,
            TPCVocabulary.DirectiveValuesText(bdOptimize)]);
        FZigBuild.SetOptimizeLevel(LLevel);
      end;
    bdSubsystem:
      begin
        if not FindSubsystem(LValue, LSubsystem) then
          raise Exception.CreateFmt(RSCmpBadOption, [LValue, ADirective.DirectiveName,
            TPCVocabulary.DirectiveValuesText(bdSubsystem)]);
        FZigBuild.SetSubsystem(LSubsystem);
      end;
    bdAddVerInfo:
      FZigBuild.SetAddVersionInfo(LValue = PC_CMP_ON);
    bdVIMajor:
      FZigBuild.SetVIMajor(Word(LInt));
    bdVIMinor:
      FZigBuild.SetVIMinor(Word(LInt));
    bdVIPatch:
      FZigBuild.SetVIPatch(Word(LInt));
    bdVIProductName:
      FZigBuild.SetVIProductName(LValue);
    bdVIDescription:
      FZigBuild.SetVIDescription(LValue);
    bdVIFileName:
      FZigBuild.SetVIFilename(LValue);
    bdVICompanyName:
      FZigBuild.SetVICompanyName(LValue);
    bdVICopyright:
      FZigBuild.SetVICopyright(LValue);
    bdExeIcon:
      FZigBuild.SetExeIcon(LValue);
    bdCopyDLL:
      FZigBuild.AddCopyDLL(LValue);
    bdLinkLibrary:
      FZigBuild.AddLinkLibrary(LValue);
    bdAddLibraryPath:
      FZigBuild.AddLibraryPath(LValue);
    bdAddIncludePath:
      FZigBuild.AddIncludePath(LValue);
    bdAddSourceFile:
      FZigBuild.AddSourceFile(LValue);
    bdCppDefine:
      begin
        // -DNAME, or -DNAME=VALUE with a second argument (SEM checked both)
        if ADirective.Args.Count > 1 then
          FZigBuild.SetDefine(LValue, ADirective.Args[1].ResolvedText)
        else
          FZigBuild.SetDefine(LValue);
      end;
    bdCppUndef:
      FZigBuild.UnsetDefine(LValue);
    // Read elsewhere: @target by the filter (TPCModule.ResolvedTarget),
    // @unittestmode by the emitter, @addmodulepath by the parser, @breakpoint
    // and @message by SEM, @outputpath by DoApplyOutputPath (before emitting)
    bdTarget, bdUnitTestMode, bdAddModulePath, bdBreakpoint, bdMessage, bdOutputPath:
      ;
  end;
end;

procedure TPCCompiler.DoApplyDirectives(const AModule: TPCModule; const AIsMain: Boolean);
var
  LDirective: TPCDirective;
begin
  // Source order; a directive SEM reported as not applied sets nothing, and a
  // main-only one in a unit was reported by the parser
  for LDirective in AModule.Directives do
  begin
    if LDirective.ResolvedNoEffect then
      Continue;
    if PC_BUILD_DIRECTIVES[LDirective.DirectiveKind].IsMainOnly and (not AIsMain) then
      Continue;
    DoApplyDirective(LDirective);
  end;
end;

procedure TPCCompiler.DoCollectLinks(const ANode: TPCNode);
begin
  // Every `external` clause's library (SEM: TPCExternal.ResolvedLib)
  if ANode = nil then
    Exit;

  if ANode is TPCVarDecl then
  begin
    if TPCVarDecl(ANode).ExternalClause.ResolvedLib <> '' then
      FZigBuild.AddLinkLibrary(TPCVarDecl(ANode).ExternalClause.ResolvedLib);
  end
  else if ANode is TPCRoutine then
  begin
    if TPCRoutine(ANode).ExternalClause.ResolvedLib <> '' then
      FZigBuild.AddLinkLibrary(TPCRoutine(ANode).ExternalClause.ResolvedLib);
  end;

  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      DoCollectLinks(AChild);
    end);
end;

function TPCCompiler.DoApplyKeys(const AKeys: TDictionary<string, string>): Boolean;
var
  LKeys: TArray<string>;
  LKey: string;
  LValue: string;
  LCurrent: string;
  LLevel: TPCOptimizeLevel;
  LSubsystem: TPCSubsystemType;
begin
  // One option store onto the driver: the defaults run before the
  // directives (a directive wins), the overrides after them (they win,
  // FreeStrike.Compiler.pas DoCLIDirectives); one check for both. Keys
  // sorted so the reports come in a stable order
  Result := True;
  LKeys := AKeys.Keys.ToArray();
  TArray.Sort<string>(LKeys);

  for LKey in LKeys do
  begin
    LValue := AKeys[LKey];
    if LKey = PC_CMP_KEY_OPTIMIZE then
    begin
      if FindOptimizeLevel(LValue, LLevel) then
        FZigBuild.SetOptimizeLevel(LLevel)
      else if TPCVocabulary.FindRetiredValue(bdOptimize, LValue, LCurrent) then
      begin
        // A retired spelling (PC_RETIRED_VALUES) names the one that replaced it
        FErrors.Add(esError, PC_ERR_CMP_001, RSCmpBadOptionRetired, [LValue, LKey, LCurrent]);
        Result := False;
      end
      else
      begin
        FErrors.Add(esError, PC_ERR_CMP_001, RSCmpBadOption,
          [LValue, LKey, TPCVocabulary.DirectiveValuesText(bdOptimize)]);
        Result := False;
      end;
    end
    else if LKey = PC_CMP_KEY_TARGET then
      // Applied before parsing (DoKeyTarget): the main module's
      // ResolvedTarget carries it, DoApplyDerived sets it on ZigBuild
      Continue
    else if LKey = PC_CMP_KEY_SUBSYSTEM then
    begin
      if FindSubsystem(LValue, LSubsystem) then
        FZigBuild.SetSubsystem(LSubsystem)
      else
      begin
        FErrors.Add(esError, PC_ERR_CMP_001, RSCmpBadOption,
          [LValue, LKey, TPCVocabulary.DirectiveValuesText(bdSubsystem)]);
        Result := False;
      end;
    end
    else
    begin
      FErrors.Add(esError, PC_ERR_CMP_001, RSCmpUnknownOption, [LKey]);
      Result := False;
    end;
  end;
end;

procedure TPCCompiler.DoApplyDerived();
var
  LKind: TPCModuleKind;
  LTarget: TPCTargetTriple;
  LIndex: Integer;
begin
  // What the AST and the final settings decide (research\compiler\
  // r5-runtime-wiring.md 1-7)
  LKind := FMainModule.ModuleKind;
  LTarget := FMainModule.ResolvedTarget;
  if LTarget.IsEmpty() then
    LTarget := TPCTargetTriple.DefaultTriple();

  FZigBuild.SetOutputPath(FOutputPath);
  FZigBuild.SetProjectName(FProjectName);
  FZigBuild.SetBuildMode(PC_CMP_BUILD_MODES[LKind]);
  FZigBuild.SetTarget(LTarget.ToZig());

  // One TU per module, the names WriteFiles wrote (from the AST, never by
  // listing the folder: a stale file of an earlier compile is not built)
  for LIndex := 0 to FAst.ModuleCount() - 1 do
    FZigBuild.AddSourceFile(TUtils.JoinResolvedPath(FGeneratedPath,
      FAst.ModuleAt(LIndex).ModuleName + PC_EMT_SOURCE_EXT));

  // The runtime: its headers for every build, its TU for an exe or dll (a
  // lib carries none: the exe / dll that links it supplies the one copy; a
  // lib that uses the runtime ships pcpp_runtime beside it, DoBuildRuntimeLib)
  FZigBuild.AddIncludePath(FZigBuild.GetRuntimePath());
  if LKind <> mkLib then
    FZigBuild.AddSourceFile(FZigBuild.GetRuntimePath(PC_CMP_RUNTIME_SOURCE));
  if LKind = mkDll then
    FZigBuild.SetDefine(PC_CMP_DEFINE_DLL);
  // The debug runtime (heap report) follows the final level: directive, then override
  if FZigBuild.GetOptimizeLevel() = olDebug then
    FZigBuild.SetDefine(PC_CMP_DEFINE_DEBUG);

  // clang's locations back to .pcpp columns through the AST's EmitSpans
  FZigBuild.SetLocationTranslator(FAst.TranslateLocation);
  // A library zig cannot find, at the @linklibrary / external clause naming it
  FZigBuild.SetLibraryLocator(FAst.LocateLibrary);
  // The compiler's own include steps through the files it generated: not shown
  FZigBuild.SetGeneratedFileTest(DoIsGeneratedFile);
  // The emitter's own checks clang judges: reported in PaskalCPP words
  FZigBuild.SetFrontendCheck(DoFrontendCheck);
end;

function TPCCompiler.DoConfigureBuild(): Boolean;
var
  LIndex: Integer;
  LModule: TPCModule;
begin
  // Defaults, then the directives over them, then the overrides over both
  if not DoApplyKeys(FKeyDefaults) then
    Exit(False);

  for LIndex := 0 to FAst.ModuleCount() - 1 do
  begin
    LModule := FAst.ModuleAt(LIndex);
    DoApplyDirectives(LModule, LModule = FMainModule);
    DoCollectLinks(LModule);
  end;

  if not DoApplyKeys(FKeyValues) then
    Exit(False);
  DoApplyDerived();
  Result := not FErrors.HasErrors();
end;

function TPCCompiler.DoValidateAutoRun(const AAutoRun: Boolean): Boolean;
begin
  Result := False;
  if not AAutoRun then
    Exit;

  // Only an exe runs
  if FMainModule.ModuleKind <> mkExe then
  begin
    FErrors.Add(esWarning, PC_ERR_CMP_002, RSCmpNoRun,
      [PC_CMP_KIND_TEXT[FMainModule.ModuleKind]]);
    Exit;
  end;
  Result := True;
end;

procedure TPCCompiler.DoInternalError(const AException: Exception);
begin
  // An error TErrors raised itself (RaiseOnError) is reported already;
  // anything else is an internal error
  if not (FErrors.RaiseOnError and (AException is EStdAppException)) then
    FErrors.Add(esFatal, PC_ERR_CMP_003, RSCmpInternalError, [AException.Message]);
  FErrors.RaiseOnError := False;
end;

function TPCCompiler.Prepare(const ASourceFile: string; const AOutputPath: string): Boolean;
begin
  Result := False;
  FPrepared := False;
  FLastExitCode := 0;

  try
    try
      if not DoPrepare(ASourceFile, AOutputPath) then
        Exit;
      if not DoFrontend() then
        Exit;
      if not DoConfigureBuild() then
        Exit;
      FPrepared := True;
      Result := True;
    except
      on E: Exception do
        DoInternalError(E);
    end;
  finally
    // No phase ends with a hint / warning unshown (TErrors.Flush)
    FErrors.Flush();
  end;
end;

function TPCCompiler.Analyze(const ASourceFile: string): Boolean;
begin
  // The build's frontend alone (the editor's LSP): no output path, no emit,
  // no build; nothing is prepared for Build
  Result := False;
  FPrepared := False;
  FLastExitCode := 0;

  try
    try
      if not DoResolveSource(ASourceFile) then
        Exit;
      Result := DoAnalyze(True);
    except
      on E: Exception do
        DoInternalError(E);
    end;
  finally
    // No phase ends with a hint / warning unshown (TErrors.Flush)
    FErrors.Flush();
  end;
end;

procedure TPCCompiler.SetSourceProvider(const AProvider: TPCSourceProvider);
begin
  FSourceProvider := AProvider;
end;

function TPCCompiler.DoBuildRuntimeLib(): Boolean;
var
  LRuntime: TPCZigBuild;
begin
  // Q2 / r5 D-R5-3: a lib whose program uses the runtime (TPCAst.UsesRuntime,
  // the emitter's lib hook rule) ships pcpp_runtime beside it, for a consumer
  // built by another toolchain. A PaskalCPP exe / dll that links the lib
  // compiles its own runtime TU and never links this one (pcpp:: twice).
  // Its own fresh driver: the session's settings only, the lib's target,
  // optimize level and debug rule; zig's cache makes a rebuild free
  LRuntime := TPCZigBuild.Create();
  try
    LRuntime.SetErrors(FErrors);
    DoApplyToolSetup(LRuntime);
    LRuntime.SetOutputPath(TUtils.JoinResolvedPath(FOutputPath, PC_CMP_RUNTIME_DIR));
    LRuntime.SetProjectName(PC_CMP_RUNTIME_NAME);
    LRuntime.SetBuildMode(bmLib);
    LRuntime.SetTarget(FZigBuild.GetTarget());
    LRuntime.SetOptimizeLevel(FZigBuild.GetOptimizeLevel());
    if FZigBuild.GetOptimizeLevel() = olDebug then
      LRuntime.SetDefine(PC_CMP_DEFINE_DEBUG);
    LRuntime.AddIncludePath(LRuntime.GetRuntimePath());
    LRuntime.AddSourceFile(LRuntime.GetRuntimePath(PC_CMP_RUNTIME_SOURCE));
    // Beside the lib's artifact, through ZigBuild's checked copy
    LRuntime.AddPublishArtifact(FZigBuild.GetArtifactDir());
    // A setting the driver refused (an output path too long, ZB0021) is reported
    if FErrors.HasErrors() then
      Exit(False);
    Result := LRuntime.Process(False);
  finally
    LRuntime.Free();
  end;
end;

procedure TPCCompiler.DoRemoveStaleRuntimeLib();
var
  LPath: string;
begin
  // A lib that does not use the runtime: the pcpp_runtime an earlier build of
  // it published beside it (that exact file, named by the layout rule) goes,
  // so no consumer finds a stale runtime beside a lib that needs none. The
  // <output>\runtime build folder stays: a cache, and -o may name a folder of
  // the user's where a 'runtime' folder is theirs
  LPath := TUtils.JoinResolvedPath(FZigBuild.GetArtifactDir(),
    FZigBuild.GetLibPrefix() + PC_CMP_RUNTIME_NAME + FZigBuild.GetLibExtension());
  try
    if not TFile.Exists(LPath) then
      Exit;
    TFile.Delete(LPath);
  except
    on E: Exception do
    begin
      // The lib itself built: a warning, the stale file named
      FErrors.Add(esWarning, PC_ERR_CMP_004, RSCmpStaleRuntime,
        [TUtils.StripLongPathPrefix(LPath), E.Message]);
      Exit;
    end;
  end;
  Status(RSCmpRemovedStaleRuntime, [TUtils.StripLongPathPrefix(LPath)]);
end;

function TPCCompiler.Build(const AAutoRun: Boolean): Boolean;
begin
  Result := False;
  if not FPrepared then
    Exit;

  try
    try
      // pcpp's record of the folder before zig writes into it, so every
      // build leaves one (pcpp --clean proves the folder with it)
      DoWriteOutputRecord();
      if not FZigBuild.Process(False) then
        Exit;
      if (FMainModule.ModuleKind = mkLib) and FAst.UsesRuntime() then
      begin
        if not DoBuildRuntimeLib() then
          Exit;
      end
      else if FMainModule.ModuleKind = mkLib then
        DoRemoveStaleRuntimeLib();
      Result := True;

      if DoValidateAutoRun(AAutoRun) then
        Result := Run();
    except
      on E: Exception do
      begin
        DoInternalError(E);
        Result := False;
      end;
    end;
  finally
    // No phase ends with a hint / warning unshown (TErrors.Flush)
    FErrors.Flush();
  end;
end;

procedure TPCCompiler.Compile(const ASourceFile: string; const AOutputPath: string;
  const AAutoRun: Boolean);
begin
  if Prepare(ASourceFile, AOutputPath) then
    Build(AAutoRun);
end;

function TPCCompiler.Run(): Boolean;
begin
  Result := False;
  if (not FPrepared) or (FMainModule.ModuleKind <> mkExe) then
    Exit;

  try
    Result := FZigBuild.Run();
    FLastExitCode := FZigBuild.GetLastExitCode();
  except
    on E: Exception do
      DoInternalError(E);
  end;
end;

function TPCCompiler.ClearOutput(): Boolean;
var
  LGeneratedCleared: Boolean;
  LDriverCleared: Boolean;
begin
  Result := False;
  if not FPrepared then
    Exit;

  // The driver owns the build root (its delete never enters a link): the
  // Compiler's own folder goes through it by name, then the driver clears
  // what zig and the driver wrote. The second runs even when the first fails
  try
    try
      LGeneratedCleared := FZigBuild.ClearBuildDir(PC_CMP_GENERATED_DIR);
      LDriverCleared := FZigBuild.ClearOutput();
      Result := LGeneratedCleared and LDriverCleared;
    except
      on E: Exception do
      begin
        DoInternalError(E);
        Result := False;
      end;
    end;
  finally
    FErrors.Flush();
  end;
end;

procedure TPCCompiler.DoWriteOutputRecord();
var
  LObject: TJSONObject;
  LPath: string;
  LUtf8: TEncoding;
begin
  // <output>\pcpp-output.json: UTF-8 without a BOM, LF. A failure is a
  // warning: the build still runs, and pcpp --clean refuses the folder
  LPath := TUtils.JoinResolvedPath(FOutputPath, PC_CMP_OUTPUT_RECORD);
  LObject := TJSONObject.Create();
  LUtf8 := TUTF8Encoding.Create(False);
  try
    LObject.AddPair(PC_CMP_RECORD_FORMAT, TJSONNumber.Create(PC_CMP_OUTPUT_FORMAT));
    LObject.AddPair(PC_CMP_RECORD_SOURCE, FSourceFile);
    LObject.AddPair(PC_CMP_RECORD_OUTPUT, FOutputPath);
    LObject.AddPair(PC_CMP_RECORD_PROJECT, FProjectName);
    try
      TUtils.EnsureDirectory(FOutputPath);
      TFile.WriteAllText(LPath, LObject.Format(2).Replace(#13#10, #10) + #10, LUtf8);
    except
      on E: Exception do
        FErrors.Add(esWarning, PC_ERR_CMP_005, RSCmpRecordFailed,
          [TUtils.StripLongPathPrefix(LPath), E.Message]);
    end;
  finally
    LUtf8.Free();
    LObject.Free();
  end;
end;

function DoFolderKey(const APath: string): string;
begin
  // One spelling of a folder for comparing places: plain, backslashes, a
  // trailing separator, lower case (NTFS folder names ignore case)
  Result := IncludeTrailingPathDelimiter(
    TUtils.StripLongPathPrefix(APath).Replace('/', '\')).ToLower();
end;

procedure TPCCompiler.DoCleanRefuse(const AFolder: string; const AReason: string);
begin
  FErrors.Add(esError, PC_ERR_CMP_006, RSCmpCleanRefused,
    [TUtils.StripLongPathPrefix(AFolder), AReason]);
end;

function DoOwnAttributes(const APath: string): DWORD;
begin
  // APath's own attributes, a link never followed (GetFileAttributes does
  // not follow a reparse point); INVALID_FILE_ATTRIBUTES = absent
  Result := GetFileAttributes(PChar(APath));
end;

function TPCCompiler.DoCheckCleanPlace(const AFolder: string): Boolean;
var
  LAttr: DWORD;
  LKey: string;
begin
  // The folder exists as a real folder (its own attributes: a link is never
  // followed) and is not a drive root
  Result := False;
  LAttr := DoOwnAttributes(AFolder);
  if (LAttr = INVALID_FILE_ATTRIBUTES) or ((LAttr and FILE_ATTRIBUTE_DIRECTORY) = 0) then
  begin
    DoCleanRefuse(AFolder, RSCmpCleanNotFolder);
    Exit;
  end;
  if (LAttr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
  begin
    DoCleanRefuse(AFolder, RSCmpCleanIsLink);
    Exit;
  end;
  LKey := DoFolderKey(AFolder);
  if (ExtractFileDrive(LKey) = '') or
    (LKey = IncludeTrailingPathDelimiter(ExtractFileDrive(LKey))) then
  begin
    DoCleanRefuse(AFolder, RSCmpCleanDriveRoot);
    Exit;
  end;
  Result := True;
end;

function TPCCompiler.DoReadOutputRecord(const AFolder: string; out ASource: string;
  out AProject: string): Boolean;
var
  LPath: string;
  LText: string;
  LJson: TJSON;
  LFormat: Integer;
  LOutput: string;
begin
  // pcpp-output.json, read strictly: an object, format exactly 1, source /
  // output / project as text, output naming this very folder. Keys this
  // pcpp does not know are ignored (a later pcpp may add some)
  Result := False;
  ASource := '';
  AProject := '';
  LPath := TUtils.JoinResolvedPath(AFolder, PC_CMP_OUTPUT_RECORD);
  if not TFile.Exists(LPath) then
  begin
    DoCleanRefuse(AFolder, Format(RSCmpCleanNoRecord, [PC_CMP_OUTPUT_RECORD]));
    Exit;
  end;
  try
    LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      DoCleanRefuse(AFolder, Format(RSCmpCleanBadRecord, [PC_CMP_OUTPUT_RECORD, E.Message]));
      Exit;
    end;
  end;

  LJson := nil;
  try
    if (not TJSON.TryFromString(LText, LJson)) or (LJson = nil) or (not LJson.IsObject()) then
    begin
      DoCleanRefuse(AFolder, Format(RSCmpCleanRecordNotJson, [PC_CMP_OUTPUT_RECORD]));
      Exit;
    end;
    if (not LJson.TryGetInt32(PC_CMP_RECORD_FORMAT, LFormat)) or
      (LFormat <> PC_CMP_OUTPUT_FORMAT) then
    begin
      DoCleanRefuse(AFolder, Format(RSCmpCleanRecordFormat,
        [PC_CMP_OUTPUT_RECORD, PC_CMP_OUTPUT_FORMAT]));
      Exit;
    end;
    if (not LJson.TryGetString(PC_CMP_RECORD_SOURCE, ASource)) or (ASource.Trim() = '') then
    begin
      DoCleanRefuse(AFolder, Format(RSCmpCleanRecordKey, [PC_CMP_OUTPUT_RECORD, PC_CMP_RECORD_SOURCE]));
      Exit;
    end;
    if (not LJson.TryGetString(PC_CMP_RECORD_OUTPUT, LOutput)) or (LOutput.Trim() = '') then
    begin
      DoCleanRefuse(AFolder, Format(RSCmpCleanRecordKey, [PC_CMP_OUTPUT_RECORD, PC_CMP_RECORD_OUTPUT]));
      Exit;
    end;
    if (not LJson.TryGetString(PC_CMP_RECORD_PROJECT, AProject)) or (AProject.Trim() = '') then
    begin
      DoCleanRefuse(AFolder, Format(RSCmpCleanRecordKey, [PC_CMP_OUTPUT_RECORD, PC_CMP_RECORD_PROJECT]));
      Exit;
    end;
  finally
    LJson.Free();
  end;

  // A record copied in from another folder (or the folder moved) is not
  // this folder's
  if DoFolderKey(LOutput) <> DoFolderKey(AFolder) then
  begin
    DoCleanRefuse(AFolder, Format(RSCmpCleanOtherFolder,
      [PC_CMP_OUTPUT_RECORD, TUtils.StripLongPathPrefix(LOutput)]));
    Exit;
  end;
  Result := True;
end;

function TPCCompiler.DoCheckCleanBuildFile(const AFolder: string; const AProject: string): Boolean;
var
  LPath: string;
  LZig: TPCZigBuild;
  LLoadErrors: TErrors;
  LLoaded: Boolean;
  LReason: string;
  LGenerated: string;
  LIndex: Integer;
  LDir: string;
  LGeneratedCount: Integer;
begin
  // build.zig, read by ZigBuild's own reader into a driver of its own: it
  // must load with no error and no warning (a file pcpp did not write has
  // lines that reader does not know), name the record's project, and build
  // at least one TU from THIS folder's generated\ and none from another's
  Result := False;
  LPath := TUtils.JoinResolvedPath(AFolder, PC_CMP_BUILD_FILE);
  if not TFile.Exists(LPath) then
  begin
    DoCleanRefuse(AFolder, RSCmpCleanNoBuildZig);
    Exit;
  end;

  LGenerated := TUtils.JoinResolvedPath(AFolder, PC_CMP_GENERATED_DIR);
  LLoadErrors := TErrors.Create();
  LZig := TPCZigBuild.Create();
  try
    LLoadErrors.SetMaxErrors(100);
    LZig.SetErrors(LLoadErrors);
    LLoaded := LZig.LoadBuildFile(LPath);
    if (not LLoaded) or (LLoadErrors.Count() > 0) then
    begin
      LReason := '';
      if LLoadErrors.Count() > 0 then
        LReason := LLoadErrors.GetItems()[0].Code + ' ' + LLoadErrors.GetItems()[0].Message;
      DoCleanRefuse(AFolder, Format(RSCmpCleanBuildZigBad, [LReason]));
      Exit;
    end;
    if LZig.GetProjectName() <> AProject then
    begin
      DoCleanRefuse(AFolder, Format(RSCmpCleanProjectMismatch,
        [PC_CMP_OUTPUT_RECORD, AProject, LZig.GetProjectName()]));
      Exit;
    end;

    LGeneratedCount := 0;
    for LIndex := 0 to LZig.GetSourceFileCount() - 1 do
    begin
      LDir := TPath.GetDirectoryName(LZig.GetSourceFile(LIndex));
      if not SameText(TPath.GetFileName(LDir), PC_CMP_GENERATED_DIR) then
        Continue;
      if DoFolderKey(LDir) <> DoFolderKey(LGenerated) then
      begin
        DoCleanRefuse(AFolder, Format(RSCmpCleanGeneratedElsewhere,
          [TUtils.StripLongPathPrefix(LZig.GetSourceFile(LIndex))]));
        Exit;
      end;
      Inc(LGeneratedCount);
    end;
    if LGeneratedCount = 0 then
    begin
      DoCleanRefuse(AFolder, RSCmpCleanNoGenerated);
      Exit;
    end;
  finally
    LZig.Free();
    LLoadErrors.Free();
  end;
  Result := True;
end;

function TPCCompiler.DoCheckCleanSource(const AFolder: string; const ASource: string): Boolean;
var
  LSourceDir: string;
begin
  // The folder must not be the project's own folder or above it: its bin\ /
  // lib\ may be the person's (an output folder of '.' or '..')
  Result := False;
  LSourceDir := DoFolderKey(TPath.GetDirectoryName(ASource));
  if LSourceDir.StartsWith(DoFolderKey(AFolder)) then
  begin
    DoCleanRefuse(AFolder, Format(RSCmpCleanHoldsSource, [TUtils.StripLongPathPrefix(ASource)]));
    Exit;
  end;
  Result := True;
end;

function TPCCompiler.DoCollectCleanTargets(const AFolder: string;
  out ATargets: TArray<string>): Boolean;
var
  LZig: TPCZigBuild;
  LNames: TArray<string>;
  LName: string;
  LPath: string;
  LAttr: DWORD;
begin
  // generated\ (the Compiler's), then the driver's names, in the order
  // CleanFolder deletes them; only what exists. A target that is a link
  // refuses the whole clean (the delete would refuse it anyway, after the
  // person said yes)
  Result := False;
  ATargets := nil;
  LZig := TPCZigBuild.Create();
  try
    LNames := [PC_CMP_GENERATED_DIR] + LZig.GetClearNames();
  finally
    LZig.Free();
  end;
  for LName in LNames do
  begin
    LPath := TUtils.JoinResolvedPath(AFolder, LName);
    LAttr := DoOwnAttributes(LPath);
    if LAttr = INVALID_FILE_ATTRIBUTES then
      Continue;
    if (LAttr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
    begin
      DoCleanRefuse(AFolder, Format(RSCmpCleanTargetLink, [TUtils.StripLongPathPrefix(LPath)]));
      Exit;
    end;
    ATargets := ATargets + [LPath];
  end;
  Result := True;
end;

function TPCCompiler.CheckCleanFolder(const AFolder: string; out AResolved: string;
  out ATargets: TArray<string>): Boolean;
var
  LFolder: string;
  LSource: string;
  LProject: string;
begin
  // Reads only. Every check in order; the first that fails is the report
  Result := False;
  AResolved := '';
  ATargets := nil;
  FErrors.Clear();
  try
    try
      LFolder := AFolder.Trim();
      if LFolder = '' then
        LFolder := TDirectory.GetCurrentDirectory();
      try
        AResolved := TUtils.ResolvePath(LFolder);
      except
        on E: Exception do
        begin
          FErrors.Add(esError, PC_ERR_CMP_006, RSCmpCleanBadFolder, [LFolder, E.Message]);
          Exit;
        end;
      end;

      if not DoCheckCleanPlace(AResolved) then
        Exit;
      if not DoReadOutputRecord(AResolved, LSource, LProject) then
        Exit;
      if not DoCheckCleanBuildFile(AResolved, LProject) then
        Exit;
      if not DoCheckCleanSource(AResolved, LSource) then
        Exit;
      if not DoCollectCleanTargets(AResolved, ATargets) then
        Exit;
      Result := True;
    except
      on E: Exception do
      begin
        DoInternalError(E);
        Result := False;
      end;
    end;
  finally
    FErrors.Flush();
  end;
end;

function TPCCompiler.CleanFolder(const AFolder: string): Boolean;
var
  LResolved: string;
  LTargets: TArray<string>;
  LZig: TPCZigBuild;
  LGeneratedCleared: Boolean;
  LDriverCleared: Boolean;
begin
  // The checks again, right before the first delete (the folder may have
  // changed while the person read the list), then generated\ and the
  // driver's names through the driver's delete, which never enters a link
  Result := False;
  if not CheckCleanFolder(AFolder, LResolved, LTargets) then
    Exit;

  try
    try
      LZig := TPCZigBuild.Create();
      try
        LZig.SetErrors(FErrors);
        LZig.SetOutputPath(LResolved);
        if LZig.GetOutputPath() = '' then
          Exit;
        LGeneratedCleared := LZig.ClearBuildDir(PC_CMP_GENERATED_DIR);
        LDriverCleared := LZig.ClearOutput();
        Result := LGeneratedCleared and LDriverCleared;
      finally
        LZig.Free();
      end;
    except
      on E: Exception do
      begin
        DoInternalError(E);
        Result := False;
      end;
    end;
  finally
    FErrors.Flush();
  end;
end;

end.
