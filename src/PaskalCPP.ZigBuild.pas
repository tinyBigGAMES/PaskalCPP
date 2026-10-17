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
  PaskalCPP.ZigBuild - Zig/Clang build driver (configuration + target model).

  Drives the bundled Zig/Clang toolchain. This unit models the full target
  triple (arch-os-abi carried as a single raw string), collects build
  configuration (mode, optimize, subsystem, source files, include/library
  paths, link libraries, defines/undefines, copy-DLLs), tracks post-build
  resource metadata (version info, icon), and exposes the Zig target-query
  and platform extension derivations used by later build stages. There is
  no state stack: an imported unit has no build of its own (R25).

  Unlike the reference, SetTarget never injects platform -D defines. Platform
  macros come from the compiler for the selected target, not from a define
  list maintained here.

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Config, StdApp.Resources,
    PaskalCPP.Common (PC_TARGET_X86_64_WINDOWS_GNU), PaskalCPP.ZigBuild.Targets,
    PaskalCPP.BuildOutput
===============================================================================}

unit PaskalCPP.ZigBuild;

{$I StdApp.Defines.inc}

interface

uses
  WinAPI.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Config,
  StdApp.Resources,
  PaskalCPP.Common,
  PaskalCPP.BuildOutput,
  PaskalCPP.ZigBuild.Targets;

const
  { Error codes }
  PC_ERR_ZIGBUILD_NOOUTPUTPATH = 'ZB0001';
  PC_ERR_ZIGBUILD_NOSOURCES     = 'ZB0002';
  PC_ERR_ZIGBUILD_SAVEFAILED    = 'ZB0003';
  PC_ERR_ZIGBUILD_ZIGNOTFOUND  = 'ZB0004';
  PC_ERR_ZIGBUILD_BUILDFAILED   = 'ZB0005';
  PC_ERR_ZIGBUILD_PUBLISHFAILED = 'ZB0010';
  PC_ERR_ZIGBUILD_DIAGFILEFAILED = 'ZB0012';
  PC_ERR_ZIGBUILD_CLEARFAILED   = 'ZB0013';
  PC_ERR_ZIGBUILD_COPYFAILED    = 'ZB0014';
  PC_ERR_ZIGBUILD_LOADFAILED    = 'ZB0015';
  // A path setting no file routine can take (a character Windows forbids,
  // longer than the RTL takes) or a project name no file can take:
  // reported, and the setting is not stored
  PC_ERR_ZIGBUILD_BADPATH       = 'ZB0020';
  // An output folder longer than zig can build in (PC_ZIG_BUILD_ROOT_MAX):
  // reported, and the setting is not stored
  PC_ERR_ZIGBUILD_ROOTTOOLONG   = 'ZB0021';
  // A target triple whose parts are not zig's names (a typo, another case, a
  // stray character): reported, and the target is not stored (R31)
  PC_ERR_ZIGBUILD_BADTARGET     = 'ZB0022';
  // A copy-DLL or publish request with an empty source: reported, not
  // dropped (R15 P3)
  PC_ERR_ZIGBUILD_EMPTYSOURCE   = 'ZB0024';
  // Two different files that would land on one destination file: neither
  // is copied, nothing of that list is (R15 P2, R16 D4)
  PC_ERR_ZIGBUILD_COLLISION     = 'ZB0025';
  // A file a copy-DLL or publish request names is not there: nothing of
  // that list is copied (a copy-DLL: the build is not run) (R16 D2 D3)
  PC_ERR_ZIGBUILD_SOURCEMISSING = 'ZB0026';
  // Run on an artifact that is not an executable (a static library or a
  // DLL) (R27)
  PC_ERR_ZIGBUILD_RUNNOTEXE     = 'ZB0027';
  // Run with no project name: there is no executable name (R39)
  PC_ERR_ZIGBUILD_NOPROJECTNAME = 'ZB0028';
  // Run: the built executable is not where the layout puts it (R27)
  PC_ERR_ZIGBUILD_EXENOTFOUND   = 'ZB0029';
  // Run: the program could not be started (the OS or WSL reason, a path WSL
  // cannot name, a chmod that failed) (R26 R34, R18 G4)
  PC_ERR_ZIGBUILD_RUNSTART      = 'ZB0030';
  // Run: the program ran and exited with a code other than 0 (R27)
  PC_ERR_ZIGBUILD_RUNEXIT       = 'ZB0031';
  // zig could not be started (the OS reason) (R27)
  PC_ERR_ZIGBUILD_ZIGSTART      = 'ZB0032';
  // A source file whose name the toolchain does not compile (a header, a
  // name clang would take as linker input, PC_SOURCE_EXTS): not stored
  PC_ERR_ZIGBUILD_NOTSOURCE     = 'ZB0033';
  // A requested icon / version info could not be stamped into the artifact:
  // the build stops before publishing (a published copy is always stamped)
  PC_ERR_ZIGBUILD_ICON          = 'ZB0008';
  PC_ERR_ZIGBUILD_VERSIONINFO   = 'ZB0009';

  { Warning codes }
  PC_ERR_ZIGBUILD_WRNCANNOTRUN   = 'ZB0006';
  PC_ERR_ZIGBUILD_WRNMANIFEST     = 'ZB0007';
  PC_ERR_ZIGBUILD_WRNCONFIG       = 'ZB0017';
  // A requested icon / version info the output cannot take (non-Windows
  // target, or an icon on a non-executable): ignored, said out loud
  PC_ERR_ZIGBUILD_WRNNOTAPPLICABLE = 'ZB0019';
  // A build.zig line LoadBuildFile does not know (not one GenerateBuildZig
  // writes, or a payload it cannot read): reported with its number, skipped
  PC_ERR_ZIGBUILD_WRNBUILDLINE     = 'ZB0023';
  { PC_ERR_ZIGBUILD_WRNSTALECOPY }
  // A copy an earlier build made beside the artifact, that no copy-DLL names
  // any more, could not be removed, or the record of those copies could not
  // be read or written (DoDeployCopyDLLs): the build goes on
  PC_ERR_ZIGBUILD_WRNSTALECOPY     = 'ZB0034';

  { PC_ZIG_PROGRESS_MS }
  // While zig prints nothing (a build for a new target / optimize level
  // compiles libc / libc++ / compiler_rt for minutes), the progress callback
  // is called this often with the elapsed time
  PC_ZIG_PROGRESS_MS = 1000;

  { PC_ZIG_GLOBAL_CACHE_DIR }
  // zig's global cache, under the toolchain folder (ZIG_GLOBAL_CACHE_DIR)
  PC_ZIG_GLOBAL_CACHE_DIR = '.zig-cache';

  { Build constants }
  PC_DEFAULT_TOOLCHAIN_PATH = '$P:res';
  // The language's default target, one spelling in one place (PaskalCPP.Common)
  PC_DEFAULT_TARGET        = PC_TARGET_X86_64_WINDOWS_GNU;
  PC_DEFAULT_PROJECT_NAME  = 'output';

  { PC_ZIG_LAUNCH_PATH_MAX }
  // The longest program path Windows launches (CreateProcess: MAX_PATH less
  // the terminating null). Probed: scripts\zb_e\a2b\sweep1.txt
  PC_ZIG_LAUNCH_PATH_MAX = 259;

  { PC_ZIG_CONFIGURER_TAIL }
  // zig build compiles its configure program and launches it from
  // <build root>\.zig-cache\o\<32 hex digits>\configurer.exe: the one program
  // it launches under the build root, at the same depth for every project
  PC_ZIG_CONFIGURER_TAIL = Length('\.zig-cache\o\') + 32 + Length('\configurer.exe');

  { PC_ZIG_BUILD_ROOT_MAX }
  // The longest output folder (build root) zig can build in: 198. One more
  // and zig cannot launch its configure program (FileNotFound). Measured for
  // exe, dll and lib, cold and cached; the project name and the source names
  // do not move it (scripts\zb_e\a2b\sweep1.txt, tail1.txt). Checked by
  // DoCheckBuildRoot; the hooked test zb19_root_limit builds at the limit.
  PC_ZIG_BUILD_ROOT_MAX = PC_ZIG_LAUNCH_PATH_MAX - PC_ZIG_CONFIGURER_TAIL;

  { Language standard flags }
  // Sources are grouped by extension: .c compiles as C, .S as assembly, .ll
  // as LLVM IR, everything else as C++. Each group has its own std flag
  // (assembly and IR none), so C libraries (raylib, ...) and C++23 sources can
  // coexist in one artifact.
  //
  // The C group uses the GNU dialect, not strict ISO. Strict ISO suppresses
  // the POSIX feature-test macros, so glibc headers hide declarations such as
  // sigjmp_buf, and third-party C libraries fail to compile for reasons that
  // have nothing to do with their own source. Vendored libraries are fetched,
  // never edited, so the standard must accommodate them rather than the other
  // way round. Upstream C projects universally assume the GNU dialect - bdwgc
  // and raylib both do - and this is the standard their own build scripts use.
  //
  // The C++ group follows the same rule for the same reason. The runtime is
  // systems code that calls the platform directly, and strict ISO C++ hides
  // the same declarations from it that strict ISO C hid from the collector.
  PC_C_STD_FLAG            = '"-std=gnu23"';
  PC_CPP_STD_FLAG          = '"-std=gnu++23"';
  // Which group a file joins is PaskalCPP.Common's PC_SOURCE_EXTS (exact case,
  // as clang reads the name). Assembly is a third group, and it takes NO -std=
  // flag of any kind. A dialect flag on an assembler-with-cpp input makes
  // clang define the matching language macro: -std=gnu++23 defines
  // __cplusplus, at which point any header opening `extern "C" {` is fed to
  // the assembler and fails with "invalid register name". -std=gnu23 is wrong
  // for the same reason, so folding .S into the C group is not an option either.

  { PC_DIAG_FILE_DIR }
  // Per-TU clang serialized diagnostics (cc1 -serialize-diagnostic-file) live
  // in this directory under the build root (FOutputPath), one file per TU:
  // <source file name>.<hash of its resolved path>.dia
  PC_DIAG_FILE_DIR = 'pcpp-diag';

  { PC_DIAG_FILE_EXT }
  PC_DIAG_FILE_EXT = '.dia';

  { PC_DIAG_FILE_PROBE }
  // Written and deleted in PC_DIAG_FILE_DIR before every build: proves clang
  // can write its .dia files there (DoDiagFilePrepare)
  PC_DIAG_FILE_PROBE = '.pcpp-write-probe';

  { PC_ZIG_COPYDLL_RECORD }
  // The record of the files the copy-DLL step copied beside the artifact, one
  // file name per line, in the build root (beside bin\ and lib\, never in
  // them: it is not shipped). A later build removes a recorded copy no
  // copy-DLL names any more (DoDeployCopyDLLs)
  PC_ZIG_COPYDLL_RECORD = 'pcpp-copydll.txt';

  { PC_ZIG_FORM_TARGET_PRE }
  // build.zig line forms (trimmed): GenerateBuildZig writes them and
  // LoadBuildFile reads exactly them back (see build.zig forms)
  PC_ZIG_FORM_TARGET_PRE   = 'const target = b.resolveTargetQuery(.{ ';

  { PC_ZIG_FORM_TARGET_SUF }
  PC_ZIG_FORM_TARGET_SUF   = ' });';

  { PC_ZIG_FORM_OPTIMIZE_PRE }
  PC_ZIG_FORM_OPTIMIZE_PRE = 'const optimize: std.builtin.OptimizeMode = ';

  { PC_ZIG_FORM_EXE }
  PC_ZIG_FORM_EXE          = 'const exe = b.addExecutable(.{';

  { PC_ZIG_FORM_LIB }
  PC_ZIG_FORM_LIB          = 'const lib = b.addLibrary(.{';

  { PC_ZIG_FORM_LINKAGE_PRE }
  PC_ZIG_FORM_LINKAGE_PRE  = '.linkage = ';

  { PC_ZIG_FORM_NAME_PRE }
  PC_ZIG_FORM_NAME_PRE     = '.name = ';

  { PC_ZIG_FORM_SUBSYSTEM }
  PC_ZIG_FORM_SUBSYSTEM    = 'exe.subsystem = .windows;';

  { PC_ZIG_FORM_INCLUDE_PRE }
  PC_ZIG_FORM_INCLUDE_PRE  = 'root_module.addIncludePath(.{ .cwd_relative = ';

  { PC_ZIG_FORM_LIBPATH_PRE }
  PC_ZIG_FORM_LIBPATH_PRE  = 'root_module.addLibraryPath(.{ .cwd_relative = ';

  { PC_ZIG_FORM_LAZY_SUF }
  PC_ZIG_FORM_LAZY_SUF     = ' });';

  { PC_ZIG_FORM_LINKLIB_PRE }
  PC_ZIG_FORM_LINKLIB_PRE  = 'root_module.linkSystemLibrary(';

  { PC_ZIG_FORM_LINKLIB_SUF }
  PC_ZIG_FORM_LINKLIB_SUF  = ', .{});';

  { PC_ZIG_FORM_LINKFILE_PRE }
  // A Linux target's link library found in a library path, handed over as the file itself:
  // zig 0.17.0 turns a found -l<name> into ld.lld -l:<absolute path>, which LLD searches
  // inside the -L folders and never finds on a Windows host. The trailing marker keeps the
  // library's name, so LoadBuildFile reads the same state back.
  PC_ZIG_FORM_LINKFILE_PRE = 'root_module.addObjectFile(.{ .cwd_relative = ';

  { PC_ZIG_FORM_LINKFILE_MID }
  PC_ZIG_FORM_LINKFILE_MID = ' }); // pcpp linklibrary ';

  { PC_ZIG_LINK_FILE_EXTS }
  // A Linux link library's file names, in the linker's order: shared before static
  PC_ZIG_LINK_FILE_EXTS: array[0..1] of string = (
    '.so',
    '.a'
  );

  { PC_ZIG_FORM_ROOT_PRE }
  PC_ZIG_FORM_ROOT_PRE     = '.root = .{ .cwd_relative = ';

  { PC_ZIG_FORM_ROOT_SUF }
  PC_ZIG_FORM_ROOT_SUF     = ' },';

  { PC_ZIG_FORM_FLAGS_PRE }
  PC_ZIG_FORM_FLAGS_PRE    = '.flags = &.{ ';

  { PC_ZIG_FORM_FLAGS_SUF }
  PC_ZIG_FORM_FLAGS_SUF    = ' },';

type

  { TPCBuildMode }
  TPCBuildMode = (
    bmExe,
    bmLib,
    bmDll
  );

  { TPCOptimizeLevel }
  TPCOptimizeLevel = (
    olDebug,
    olReleaseSafe,
    olReleaseFast,
    olReleaseSmall
  );

  { TPCSubsystemType }
  TPCSubsystemType = (
    stConsole,
    stGUI
  );

  { TPCPublishKind }
  // What a copy request copies
  TPCPublishKind = (
    pkArtifact,  // the built artifact: its path is known after the build
    pkFile       // a file the caller named
  );

  { TPCPublishItem }
  // One copy request: a copy-DLL (deployed beside the artifact before the
  // build) or a publish (finished output copied out after it). Resolved at
  // registration; the record carries all of it (R15).
  TPCPublishItem = record
    Kind: TPCPublishKind;
    // pkFile: the resolved source; '' for pkArtifact
    SourcePath: string;
    // The resolved destination folder; '' = the artifact folder (copy-DLLs)
    DestDir: string;
  end;

  { TPCLocationTranslator }
  // Declared with the build output commit (PaskalCPP.BuildOutput), which
  // applies it; SetLocationTranslator hands it over
  TPCLocationTranslator = PaskalCPP.BuildOutput.TPCLocationTranslator;

  { TPCLibraryLocator }
  // Where the frontend names a link library zig cannot find; BuildOutput
  // applies it; SetLibraryLocator hands it over
  TPCLibraryLocator = PaskalCPP.BuildOutput.TPCLibraryLocator;

  { TPCGeneratedFileTest }
  // Which files the frontend generated for this build; BuildOutput drops the
  // frontend's own include steps through them; SetGeneratedFileTest hands it over
  TPCGeneratedFileTest = PaskalCPP.BuildOutput.TPCGeneratedFileTest;

  { TPCFrontendCheck }
  // A check the frontend wrote into its C++ that clang judges; BuildOutput
  // reports its failure in the frontend's words; SetFrontendCheck hands it over
  TPCFrontendCheck = PaskalCPP.BuildOutput.TPCFrontendCheck;

  { TPCZigBuild }
  TPCZigBuild = class(TBaseObject)
  private
    FOutputPath: string;
    FProjectName: string;
    FBuildMode: TPCBuildMode;
    FOptimizeLevel: TPCOptimizeLevel;
    FTarget: string;
    FSubsystem: TPCSubsystemType;
    FSourceFiles: TStringList;
    FIncludePaths: TStringList;
    FLibraryPaths: TStringList;
    FLinkLibraries: TStringList;
    FDefines: TStringList;
    FUndefines: TStringList;
    // Copy-DLL requests (before the build, into the artifact folder) and
    // publish requests (after the stamps): records resolved at registration
    FCopyDLLs: TList<TPCPublishItem>;
    FPublishItems: TList<TPCPublishItem>;

    FOutput: TCallback<TCaptureConsoleCallback>;
    FRunOutput: TCallback<TCaptureConsoleCallback>;
    FProgress: TCallback<TCaptureConsoleTick>;
    FLastExitCode: DWORD;
    FRawOutput: Boolean;
    FRunArguments: string;
    FRunHost: TPtyHost;          // not owned; nil = the program reads no keyboard

    // Build output: zig's lines -> captures (FBuildOutput), then the commit
    // that reports them with the .dia entries (FBuildCommit). FBuildErrors =
    // errors reported for the last Process call (commit + safety net).
    FBuildOutput: TPCBuildOutputFilter;
    FBuildCommit: TPCBuildOutputCommit;
    FBuildErrors: Integer;

    // Maps diagnostic locations back to the frontend's source (nil = none)
    FLocationTranslator: TPCLocationTranslator;
    FLibraryLocator: TPCLibraryLocator;
    FGeneratedFileTest: TPCGeneratedFileTest;
    FFrontendCheck: TPCFrontendCheck;

    // Toolchain path + persisted build config (build.toml)
    FToolchainPath: string;
    FBuildConfig: TConfig;
    FBuildConfigPath: string;

    // Warnings about build.toml raised before an error sink was wired
    // (Create), reported by SetErrors. A build.toml that exists but cannot be
    // read is the user's and is never overwritten (FConfigReadable False).
    FConfigPending: TStringList;
    FConfigReadable: Boolean;
    // build.toml is read on first use (DoConfigLoad), never in Create (R6)
    FConfigLoaded: Boolean;

    // Version info / post-build resources
    FAddVersionInfo: Boolean;
    FVIMajor: Word;
    FVIMinor: Word;
    FVIPatch: Word;
    FVIProductName: string;
    FVIDescription: string;
    FVIFilename: string;
    FVICompanyName: string;
    FVICopyright: string;
    FExeIcon: string;

    function FindDefineIndex(const ADefineName: string): Integer;

    // Copy requests (see the implementation section of that name)
    function DoPostBuildCopies(const AArtifactPath: string): Boolean;
    function DoAcceptPublishDest(const ADestDir: string; out AResolved: string): Boolean;
    procedure DoAddCopyItem(const AList: TList<TPCPublishItem>;
      const AItem: TPCPublishItem);
    function DoCopySource(const AItem: TPCPublishItem;
      const AArtifactPath: string): string;
    function DoCopyDest(const AItem: TPCPublishItem;
      const ADefaultDir: string): string;
    function DoCheckCopies(const AList: TList<TPCPublishItem>;
      const AArtifactPath: string; const ADefaultDir: string): Boolean;
    function DoRunCopies(const AList: TList<TPCPublishItem>;
      const AArtifactPath: string; const ADefaultDir: string;
      const AFailCode: string; const AFailText: string;
      const AStatus: string): Boolean;
    function DoCopyRecordPath(): string;
    procedure DoReadCopyRecord(out ANames: TArray<string>);
    procedure DoWriteCopyRecord(const ANames: TArray<string>);
    function DoDeployCopyDLLs(): Boolean;

    // Artifact layout (see the implementation section of that name)
    function DoArtifactSubdir(const ABuildMode: TPCBuildMode): string;
    function DoArtifactDir(const ABuildMode: TPCBuildMode): string;
    function DoArtifactPath(): string;

    function DoSplitTarget(const ATarget: string; out AArch: string;
      out AOS: string; out AAbi: string): Boolean;

    // Path settings (see the implementation section of that name): the one
    // entry that resolves a path, once; add / remove a resolved list entry
    function DoAcceptPath(const ARaw: string; const ABase: string;
      const AWhat: string; out AResolved: string): Boolean;
    procedure DoAddPath(const AList: TStringList; const ARaw: string;
      const ABase: string; const AWhat: string);
    procedure DoRemovePath(const AList: TStringList; const ARaw: string;
      const AWhat: string);
    // The one gate of every source file (AddSourceFile(s), LoadBuildFile): a
    // name the toolchain does not compile is ZB0033 and not stored
    procedure DoAddSourcePath(const ARaw: string; const ABase: string);
    // An accepted output folder against zig's limit: ZB0021 when longer
    function DoCheckBuildRoot(const AResolved: string): Boolean;

    // build.zig generation helpers (decomposition of GenerateBuildZig)
    // build.zig forms (see the implementation section of that name)
    function DoZigPath(const APath: string): string;
    function DoOptimizeName(const ALevel: TPCOptimizeLevel): string;
    function DoAcceptTarget(const ATarget: string): Boolean;
    procedure DoLoadLine(const ALine: string; const ALineNo: Integer;
      const AFilename: string; var ATURoot: string);
    function DoLoadHeaderLine(const ALine: string): Boolean;
    function DoLoadArtifactLine(const ALine: string): Boolean;
    function DoLoadModuleLine(const ALine: string): Boolean;
    function DoLoadLinkFileLine(const ARest: string): Boolean;
    function DoLoadSourceLine(const ALine: string; var ATURoot: string): Boolean;
    function GetSourceLanguage(const ASourceFile: string): TPCSourceLanguage;
    procedure DoZigHeader(const ABuilder: TStringBuilder);
    procedure DoZigArtifact(const ABuilder: TStringBuilder;
      out AArtifactVar: string);
    procedure DoZigSourceGroup(const ABuilder: TStringBuilder;
      const AArtifactVar: string; const AFiles: TStringList;
      const ALanguage: TPCSourceLanguage);
    procedure DoZigSources(const ABuilder: TStringBuilder;
      const AArtifactVar: string);

    // Per-TU clang serialized diagnostics (see the implementation section of that name)
    function DoDiagFilePath(const ASourceFile: string): string;
    function DoDiagFilePrepare(): Boolean;

    // Build output (see the implementation section of that name)
    procedure DoFilterLine(const ALine: string);
    procedure DoFilterFlush();

    // Output routing: build lines go through the filter, the built
    // program's run output always passes through
    procedure HandleOutputLine(const ALine: string; const AUserData: Pointer);
    procedure HandleRunOutputLine(const ALine: string;
      const AUserData: Pointer);

    // Deletes the directory AName under the build root (ClearCache /
    // ClearOutput / ClearBuildDir): False, with an error, when there is no
    // output path, AName is a link (never entered, nothing deleted) or the
    // directory is still there afterwards
    function DoClearBuildDir(const AName: string): Boolean;
    // Deletes everything inside ADir and ADir itself, never through a link:
    // a junction or symbolic link inside it is removed as the link alone
    // (its target untouched). Failures are left for the caller to see (the
    // directory is still there); raises only what the RTL raises
    procedure DoDeleteTree(const ADir: string);
    // Deletes the file AName under the build root (ClearOutput: the copy-DLL
    // record), the same rules as DoClearBuildDir
    function DoClearBuildFile(const AName: string): Boolean;

    // build.toml (toolchain path): resolve a raw value (empty = default),
    // save it, report a warning now or when SetErrors wires the sink
    function DoResolveToolchainPath(const ARaw: string): string;
    // Reads build.toml once per location (GetBuildConfigPath), or writes
    // the template when absent; every toolchain path read goes through it
    procedure DoConfigLoad();
    procedure DoConfigSave();
    procedure DoConfigWarning(const AMessage: string;
      const AArgs: array of const);

    // Post-build helpers. ApplyPostBuildResources stamps the Windows
    // resources onto the built artifact; False = a requested stamp failed
    // (reported), so nothing is published
    function ApplyPostBuildResources(const AArtifactPath: string): Boolean;
    function DoIsWindowsTarget(): Boolean;
    function DoIsLinuxTarget(): Boolean;
    function DoFindLinkFile(const ALibrary: string; out APath: string): Boolean;
    procedure DoApplyManifest(const AExePath: string);
    function DoApplyIcon(const AExePath: string): Boolean;
    function DoApplyVersionInfo(const AArtifactPath: string): Boolean;

    // The target as build.zig's resolveTargetQuery text (GenerateBuildZig)
    function DoZigTargetQuery(): string;

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Also wires build.toml's config, and reports the warnings Create
    // raised before any error sink existed
    procedure SetErrors(const AErrors: TErrors); override;

    // Configuration
    procedure SetOutputPath(const APath: string);
    procedure SetProjectName(const AProjectName: string);
    procedure SetBuildMode(const ABuildMode: TPCBuildMode);
    procedure SetOptimizeLevel(const AOptimizeLevel: TPCOptimizeLevel);
    procedure SetSubsystem(const ASubsystem: TPCSubsystemType);
    // Called every PC_ZIG_PROGRESS_MS while zig build prints nothing, with
    // the time since zig started (unset: zig is read with a blocking read)
    procedure SetProgressCallback(const ACallback: TCaptureConsoleTick;
      const AUserData: Pointer = nil);
    procedure SetOutputCallback(const ACallback: TCaptureConsoleCallback;
      const AUserData: Pointer = nil);
    procedure SetRawOutput(const AValue: Boolean);
    procedure SetLocationTranslator(const ATranslator: TPCLocationTranslator);
    // Where the frontend names a link library: a library zig cannot find is
    // reported there (nil = without a location)
    procedure SetLibraryLocator(const ALocator: TPCLibraryLocator);
    // Which files the frontend generated: an include step through one of
    // them is the frontend's own and is not reported (nil = every step kept)
    procedure SetGeneratedFileTest(const ATest: TPCGeneratedFileTest);
    // The frontend's own checks in its C++: a failed one is reported as the
    // frontend says (nil = every failure is clang's)
    procedure SetFrontendCheck(const ACheck: TPCFrontendCheck);

    // Command line handed to the artifact when it is run. Empty means no
    // arguments, which is the behaviour every caller had before this existed.
    procedure SetRunArguments(const AArguments: string);
    function GetRunArguments(): string;
    // Where Run's program gets its keyboard and terminal size (TUtils.RunPE /
    // RunElf AHost: the console, a redirected stdin, an editor's pane). Not
    // owned: it outlives Run. nil (default) = none
    procedure SetRunHost(const AHost: TPtyHost);
    // Run's program output (pseudoconsole chunks, VT kept); unset = the
    // output callback
    procedure SetRunOutputCallback(const ACallback: TCaptureConsoleCallback;
      const AUserData: Pointer = nil);

    // Target model (raw triple string; no define injection)
    procedure SetTarget(const ATarget: string); overload;
    procedure SetTarget(const AArch: string; const AOS: string;
      const AAbi: string = ''); overload;
    function GetTarget(): string;

    // Source files
    procedure AddSourceFile(const ASourceFile: string);
    procedure AddSourceFiles(const AFiles: array of string); overload;
    procedure AddSourceFiles(const ABasePath: string;
      const AFiles: array of string); overload;
    procedure RemoveSourceFile(const ASourceFile: string);
    procedure ClearSourceFiles();

    // Include paths
    procedure AddIncludePath(const APath: string);
    procedure RemoveIncludePath(const APath: string);
    procedure ClearIncludePaths();

    // Library paths
    procedure AddLibraryPath(const APath: string);
    procedure RemoveLibraryPath(const APath: string);
    procedure ClearLibraryPaths();

    // Link libraries
    procedure AddLinkLibrary(const ALibrary: string);
    procedure AddLinkLibraries(const ALibraries: array of string);
    procedure RemoveLinkLibrary(const ALibrary: string);
    procedure ClearLinkLibraries();

    // Defines (-DNAME or -DNAME=VALUE)
    procedure SetDefine(const ADefineName: string); overload;
    procedure SetDefine(const ADefineName: string; const AValue: string); overload;
    procedure SetDefines(const ADefineNames: array of string);
    procedure RemoveDefine(const ADefineName: string);
    procedure ClearDefines();
    function HasDefine(const ADefineName: string): Boolean;
    function GetDefines(): TStringList;

    // Undefines (-UNAME)
    procedure UnsetDefine(const ADefineName: string);
    procedure RemoveUndefine(const ADefineName: string);
    procedure ClearUndefines();
    function HasUndefine(const ADefineName: string): Boolean;
    function GetUndefines(): TStringList;

    // Copy DLLs: the DLLs the program loads, deployed beside the artifact
    // (where a built DLL lands) BEFORE the build; a missing or colliding one
    // stops the build (R16)
    procedure AddCopyDLL(const ADLLPath: string);
    procedure RemoveCopyDLL(const ADLLPath: string);
    procedure ClearCopyDLLs();

    // Post-build copies (performed after post-build resources are applied)
    //
    // These run LATER than the copy-DLL step above, and deliberately so. The
    // copy-DLL step brings dependency DLLs in before the artifact is stamped;
    // these publish finished output out. Publishing before ApplyPostBuildResources
    // would ship a copy that predates its own version info.
    procedure AddPostBuildCopy(const ASourceFile: string;
      const ADestDir: string);
    procedure AddPublishArtifact(const ADestDir: string);
    procedure ClearPostBuildCopies();

    // Clear all
    procedure Clear();

    // Actions
    function LoadBuildFile(const AFilename: string): Boolean;
    function SaveBuildFile(): Boolean;
    function Process(const AAutoRun: Boolean = True): Boolean;
    function Run(): Boolean;
    function ClearCache(): Boolean;
    // bin\, lib\, the project's .zig-cache\, pcpp-diag\ and the copy-DLL
    // record; never the output folder itself, build.zig or anything else
    function ClearOutput(): Boolean;
    // A folder of a caller's own under the build root (the Compiler's
    // generated\): the same delete as ClearOutput's folders, one report per
    // failure
    function ClearBuildDir(const AName: string): Boolean;
    // The names ClearOutput deletes under the build root, in its order (the
    // folders, then the copy-DLL record): what a caller lists before asking
    function GetClearNames(): TArray<string>;

    // Getters
    function GetLastExitCode(): DWORD;
    function GetOutputPath(): string;
    function GetProjectName(): string;
    function GetBuildMode(): TPCBuildMode;
    function GetOptimizeLevel(): TPCOptimizeLevel;
    function GetSubsystem(): TPCSubsystemType;
    function GetSourceFileCount(): Integer;
    function GetSourceFile(const AIndex: Integer): string;

    // Platform extension helpers (derived from the target triple)
    function GetExeExtension(): string;
    function GetDllExtension(): string;
    function GetLibExtension(): string;
    function GetLibPrefix(): string;
    function GetOutputFilename(): string;
    // Where the built artifact lands under the output path (the layout rule,
    // DoArtifactSubdir: bin for an exe / dll, lib for a lib)
    // and its full path, in ResolvePath's spelling
    function GetArtifactDir(): string;
    function GetArtifactPath(): string;

    // Display names
    function GetTargetDisplayName(): string;
    function GetOptimizeLevelDisplayName(): string;
    function GetSubsystemDisplayName(): string;

    // build.zig generation
    function GetZigOptimizeString(): string;
    function BuildFlagsString(const ALanguage: TPCSourceLanguage): string;
    function GenerateBuildZig(): string;
    // A flags payload ('"<flag>", "<flag>", ...'): its defines and undefines
    // are set; False when it is not a list of zig string literals
    function ParseFlagsLine(const APayload: string): Boolean;

    // Version info / post-build resources
    procedure SetAddVersionInfo(const AValue: Boolean);
    function GetAddVersionInfo(): Boolean;
    procedure SetVIMajor(const AValue: Word);
    function GetVIMajor(): Word;
    procedure SetVIMinor(const AValue: Word);
    function GetVIMinor(): Word;
    procedure SetVIPatch(const AValue: Word);
    function GetVIPatch(): Word;
    procedure SetVIProductName(const AValue: string);
    function GetVIProductName(): string;
    procedure SetVIDescription(const AValue: string);
    function GetVIDescription(): string;
    procedure SetVIFilename(const AValue: string);
    function GetVIFilename(): string;
    procedure SetVICompanyName(const AValue: string);
    function GetVICompanyName(): string;
    procedure SetVICopyright(const AValue: string);
    function GetVICopyright(): string;
    procedure SetExeIcon(const AValue: string);
    function GetExeIcon(): string;

    // Toolchain paths
    // Where build.toml is read from (default $P:build.toml, next to the
    // executable). Create reads nothing: the file is read on first use, so an
    // owner (a test) can point it elsewhere first. A bad path is ZB0020.
    procedure SetBuildConfigPath(const APath: string);
    function GetBuildConfigPath(): string;
    procedure SetToolchainPath(const APath: string);
    function GetToolchainPath(): string;
    function GetZigPath(const AFilename: string = ''): string;
    function GetRuntimePath(const AFilename: string = ''): string;
    function GetLibsPath(const AFilename: string = ''): string;
    function GetAssetsPath(const AFilename: string = ''): string;
  end;

// R48: AText as one zig string literal: quoted, '\' '"' and the control
// characters escaped, every other character as it is (build.zig is UTF-8)
function ZigStringLiteral(const AText: string): string;

// The text of one zig string literal of the shape ZigStringLiteral writes;
// False (AText '') when ALiteral is not one
function ZigStringValue(const ALiteral: string; out AText: string): Boolean;

implementation

uses
  System.Hash;

{$R PaskalCPP.ResData.res}

// build.zig text helpers (see build.zig forms): unit-level, used by the
// writer and the loader alike

const
  { PC_ZIG_STRUCTURE_LINES }
  // The lines build.zig carries that hold nothing to read back
  PC_ZIG_STRUCTURE_LINES: array[0..22] of string = (
    '',
    'const std = @import("std");',
    'pub fn build(b: *std.Build) void {',
    '}',
    '.root_module = b.createModule(.{',
    '.target = target,',
    '.optimize = optimize,',
    '.link_libc = true,',
    '.link_libcpp = true,',
    '}),',
    '});',
    '// GUI subsystem: no console window',
    'if (target.result.os.tag == .windows) {',
    '.files = &.{',
    '},',
    'b.getInstallStep().dependOn(&b.addInstallArtifact(exe, .{',
    'b.getInstallStep().dependOn(&b.addInstallArtifact(lib, .{',
    '.dest_dir = .{ .override = .bin },',
    '.dest_dir = .{ .override = .lib },',
    '}).step);',
    'exe.root_module.addCSourceFiles(.{',
    'lib.root_module.addCSourceFiles(.{',
    'exe.root_module.addRPathSpecial("$ORIGIN");'
  );

function ZigStringLiteral(const AText: string): string;
var
  LBuilder: TStringBuilder;
  LI: Integer;
  LChar: Char;
begin
  LBuilder := TStringBuilder.Create();
  try
    LBuilder.Append('"');
    for LI := 0 to AText.Length - 1 do
    begin
      LChar := AText.Chars[LI];
      if LChar = '\' then
        LBuilder.Append('\\')
      else if LChar = '"' then
        LBuilder.Append('\"')
      else if LChar = #10 then
        LBuilder.Append('\n')
      else if LChar = #13 then
        LBuilder.Append('\r')
      else if LChar = #9 then
        LBuilder.Append('\t')
      else if (Ord(LChar) < 32) or (Ord(LChar) = 127) then
        LBuilder.Append('\x' + IntToHex(Ord(LChar), 2).ToLower())
      else
        LBuilder.Append(LChar);
    end;
    LBuilder.Append('"');
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

function ZigStringValue(const ALiteral: string; out AText: string): Boolean;
var
  LBuilder: TStringBuilder;
  LI: Integer;
  LLast: Integer;
  LCode: Integer;
begin
  AText := '';
  Result := False;
  if (ALiteral.Length < 2) or (ALiteral.Chars[0] <> '"') or
    (ALiteral.Chars[ALiteral.Length - 1] <> '"') then
    Exit;

  // LLast: the last character inside the quotes
  LLast := ALiteral.Length - 2;
  LBuilder := TStringBuilder.Create();
  try
    LI := 1;
    while LI <= LLast do
    begin
      // An unescaped quote inside ends the literal early: not one literal
      if ALiteral.Chars[LI] = '"' then
        Exit;
      if ALiteral.Chars[LI] <> '\' then
      begin
        LBuilder.Append(ALiteral.Chars[LI]);
        Inc(LI);
        Continue;
      end;

      // An escape: the escapes ZigStringLiteral writes, nothing else
      if LI + 1 > LLast then
        Exit;
      case ALiteral.Chars[LI + 1] of
        '\':
          LBuilder.Append('\');
        '"':
          LBuilder.Append('"');
        'n':
          LBuilder.Append(#10);
        'r':
          LBuilder.Append(#13);
        't':
          LBuilder.Append(#9);
        'x':
          begin
            if (LI + 3 > LLast) or
              (not TryStrToInt('$' + ALiteral.Substring(LI + 2, 2), LCode)) or
              (LCode < 0) then
              Exit;
            LBuilder.Append(Char(LCode));
            Inc(LI, 4);
            Continue;
          end;
      else
        Exit;
      end;
      Inc(LI, 2);
    end;
    AText := LBuilder.ToString();
    Result := True;
  finally
    LBuilder.Free();
  end;
end;

function ZigStringList(const APayload: string; out AItems: TArray<string>): Boolean;
var
  LPos: Integer;
  LEnd: Integer;
  LText: string;
begin
  // '"<a>", "<b>", ...': the literals, each read by ZigStringValue
  AItems := nil;
  Result := False;
  LPos := 0;
  while LPos < APayload.Length do
  begin
    if APayload.Chars[LPos] <> '"' then
      Exit;
    // The closing quote: the first one not escaped
    LEnd := LPos + 1;
    while (LEnd < APayload.Length) and (APayload.Chars[LEnd] <> '"') do
    begin
      if APayload.Chars[LEnd] = '\' then
        Inc(LEnd);
      Inc(LEnd);
    end;
    if LEnd >= APayload.Length then
      Exit;
    if not ZigStringValue(APayload.Substring(LPos, LEnd - LPos + 1), LText) then
      Exit;
    AItems := AItems + [LText];
    LPos := LEnd + 1;
    if LPos = APayload.Length then
      Break;
    if APayload.Substring(LPos, 2) <> ', ' then
      Exit;
    Inc(LPos, 2);
  end;
  Result := Length(AItems) > 0;
end;

function DoFormPayload(const ALine: string; const APrefix: string;
  const ASuffix: string; out APayload: string): Boolean;
begin
  // ALine = APrefix + <payload> + ASuffix
  APayload := '';
  Result := (ALine.Length >= APrefix.Length + ASuffix.Length) and
    ALine.StartsWith(APrefix) and ALine.EndsWith(ASuffix);
  if Result then
    APayload := ALine.Substring(APrefix.Length,
      ALine.Length - APrefix.Length - ASuffix.Length);
end;

function DoZigEnumName(const AName: string): string;
begin
  // A zig enum literal: a name that starts with a digit ('3ds') is quoted
  if (AName <> '') and CharInSet(AName.Chars[0], ['0'..'9']) then
    Result := '@"' + AName + '"'
  else
    Result := AName;
end;

function DoZigEnumValue(const AText: string): string;
begin
  // The inverse of DoZigEnumName
  if AText.StartsWith('@"') and AText.EndsWith('"') and (AText.Length >= 3) then
    Result := AText.Substring(2, AText.Length - 3)
  else
    Result := AText;
end;


{ TPCZigBuild }

constructor TPCZigBuild.Create();
begin
  inherited;

  FOutputPath := '';
  FProjectName := PC_DEFAULT_PROJECT_NAME;
  FBuildMode := bmExe;
  FOptimizeLevel := olDebug;
  FSubsystem := stConsole;
  FSourceFiles := TStringList.Create();
  FIncludePaths := TStringList.Create();
  FLibraryPaths := TStringList.Create();
  FLinkLibraries := TStringList.Create();
  FDefines := TStringList.Create();
  FUndefines := TStringList.Create();
  FCopyDLLs := TList<TPCPublishItem>.Create();
  FPublishItems := TList<TPCPublishItem>.Create();
  FLastExitCode := 0;
  FRawOutput := False;
  FRunArguments := '';

  // Build output: zig's lines -> captures -> commit (Process)
  FBuildOutput := TPCBuildOutputFilter.Create();
  FBuildCommit := TPCBuildOutputCommit.Create();
  FBuildErrors := 0;
  FLocationTranslator := nil;
  FLibraryLocator := nil;
  FGeneratedFileTest := nil;
  FFrontendCheck := nil;

  // Default target triple (raw string; no platform define injection)
  FTarget := PC_DEFAULT_TARGET;

  // Version info defaults
  FAddVersionInfo := False;
  FVIMajor := 0;
  FVIMinor := 0;
  FVIPatch := 0;
  FVIProductName := '';
  FVIDescription := '';
  FVIFilename := '';
  FVICompanyName := '';
  FVICopyright := '';
  FExeIcon := '';

  // Toolchain config: build.toml, read on first use (DoConfigLoad) from
  // GetBuildConfigPath, never here: Create does no file I/O, so an owner can
  // point it elsewhere first (SetBuildConfigPath) (R6). Warnings before an
  // error sink is wired wait in FConfigPending (SetErrors).
  FConfigPending := TStringList.Create();
  FConfigReadable := True;
  FConfigLoaded := False;
  FBuildConfig := TConfig.Create();
  FToolchainPath := '';
  try
    FBuildConfigPath := TUtils.ResolvePath('$P:build.toml');
  except
    on E: Exception do
    begin
      // No usable location: the default toolchain path, nothing read or saved
      FBuildConfigPath := '';
      DoConfigWarning(RSZigBuildConfigLoadFailed, ['$P:build.toml', E.Message]);
    end;
  end;
end;

destructor TPCZigBuild.Destroy();
begin
  // build.toml is saved where it changes (first use, SetToolchainPath), never
  // here: a destructor has no error sink it may rely on
  FreeAndNil(FBuildConfig);
  FreeAndNil(FConfigPending);

  FreeAndNil(FBuildCommit);
  FreeAndNil(FBuildOutput);
  FreeAndNil(FPublishItems);
  FreeAndNil(FCopyDLLs);
  FreeAndNil(FUndefines);
  FreeAndNil(FDefines);
  FreeAndNil(FLinkLibraries);
  FreeAndNil(FLibraryPaths);
  FreeAndNil(FIncludePaths);
  FreeAndNil(FSourceFiles);

  inherited;
end;

// Path settings
//
// Every path a setting takes is resolved once, here, through
// TUtils.ResolvePath (R18 G1): stored resolved, so two spellings of one path
// are one entry and no later use resolves it again. A path no file routine
// can take (a character Windows forbids, longer than the RTL takes) is
// ZB0020 and the setting is not stored. Empty means "no path" and is the
// caller's to handle.

function TPCZigBuild.DoAcceptPath(const ARaw: string; const ABase: string;
  const AWhat: string; out AResolved: string): Boolean;
begin
  AResolved := '';
  Result := False;
  try
    AResolved := TUtils.ResolvePath(ARaw, ABase);
    Result := True;
  except
    on E: Exception do
    begin
      // Without an error sink the setting is still refused
      if Assigned(FErrors) then
        FErrors.Add(esError, PC_ERR_ZIGBUILD_BADPATH, RSZigBuildBadPath,
          [AWhat, ARaw, E.Message]);
    end;
  end;
end;

procedure TPCZigBuild.DoAddPath(const AList: TStringList; const ARaw: string;
  const ABase: string; const AWhat: string);
var
  LPath: string;
begin
  if not DoAcceptPath(ARaw, ABase, AWhat, LPath) then
    Exit;
  if (LPath <> '') and (AList.IndexOf(LPath) < 0) then
    AList.Add(LPath);
end;

procedure TPCZigBuild.DoRemovePath(const AList: TStringList; const ARaw: string;
  const AWhat: string);
var
  LPath: string;
  LIndex: Integer;
begin
  // Looked up in the resolved form it was stored in
  if not DoAcceptPath(ARaw, '', AWhat, LPath) then
    Exit;
  LIndex := AList.IndexOf(LPath);
  if LIndex >= 0 then
    AList.Delete(LIndex);
end;

function TPCZigBuild.DoCheckBuildRoot(const AResolved: string): Boolean;
var
  LPlain: string;
  LLength: Integer;
begin
  // zig is launched in the folder's plain spelling, so that is what is
  // measured: a long-path spelling (past PATH_PLAIN_MAX) is measured
  // without its prefix
  LPlain := TUtils.StripLongPathPrefix(AResolved);
  LLength := Length(LPlain);
  Result := LLength <= PC_ZIG_BUILD_ROOT_MAX;
  if (not Result) and Assigned(FErrors) then
    FErrors.Add(esError, PC_ERR_ZIGBUILD_ROOTTOOLONG, RSZigBuildRootTooLong,
      [LLength, PC_ZIG_BUILD_ROOT_MAX, LPlain]);
end;

// Configuration

procedure TPCZigBuild.SetOutputPath(const APath: string);
var
  LPath: string;
begin
  // Every later use (build root, working dir, artifact paths) reads it as is
  if not DoAcceptPath(APath, '', RSZigBuildWhatOutputPath, LPath) then
    Exit;

  // zig cannot build in a longer folder: refused up front, not stored
  if not DoCheckBuildRoot(LPath) then
    Exit;

  FOutputPath := LPath;
end;

procedure TPCZigBuild.SetProjectName(const AProjectName: string);
begin
  // The project name becomes the artifact's file name: a name no file can
  // take is an error and is not stored. Empty clears it.
  if (AProjectName <> '') and
    (not TPath.HasValidFileNameChars(AProjectName, False)) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_BADPATH, RSZigBuildBadProjectName,
        [AProjectName]);
    Exit;
  end;

  FProjectName := AProjectName;
end;

procedure TPCZigBuild.SetBuildMode(const ABuildMode: TPCBuildMode);
begin
  FBuildMode := ABuildMode;
end;

procedure TPCZigBuild.SetOptimizeLevel(const AOptimizeLevel: TPCOptimizeLevel);
begin
  FOptimizeLevel := AOptimizeLevel;
end;

procedure TPCZigBuild.SetSubsystem(const ASubsystem: TPCSubsystemType);
begin
  FSubsystem := ASubsystem;
end;

procedure TPCZigBuild.SetProgressCallback(const ACallback: TCaptureConsoleTick;
  const AUserData: Pointer);
begin
  FProgress.Callback := ACallback;
  FProgress.UserData := AUserData;
end;

procedure TPCZigBuild.SetOutputCallback(const ACallback: TCaptureConsoleCallback;
  const AUserData: Pointer);
begin
  FOutput.Callback := ACallback;
  FOutput.UserData := AUserData;
end;

procedure TPCZigBuild.SetRawOutput(const AValue: Boolean);
begin
  FRawOutput := AValue;
end;

procedure TPCZigBuild.SetRunHost(const AHost: TPtyHost);
begin
  FRunHost := AHost;
end;

procedure TPCZigBuild.SetRunOutputCallback(const ACallback: TCaptureConsoleCallback;
  const AUserData: Pointer);
begin
  FRunOutput.Callback := ACallback;
  FRunOutput.UserData := AUserData;
end;

procedure TPCZigBuild.SetLocationTranslator(
  const ATranslator: TPCLocationTranslator);
begin
  FLocationTranslator := ATranslator;
end;

procedure TPCZigBuild.SetLibraryLocator(const ALocator: TPCLibraryLocator);
begin
  FLibraryLocator := ALocator;
end;

procedure TPCZigBuild.SetGeneratedFileTest(const ATest: TPCGeneratedFileTest);
begin
  FGeneratedFileTest := ATest;
end;

procedure TPCZigBuild.SetFrontendCheck(const ACheck: TPCFrontendCheck);
begin
  FFrontendCheck := ACheck;
end;

// Arguments passed to the artifact by Run(). Stored verbatim: the caller is
// responsible for quoting anything containing spaces, exactly as it would be
// when typing the command by hand.
procedure TPCZigBuild.SetRunArguments(const AArguments: string);
begin
  FRunArguments := AArguments;
end;

function TPCZigBuild.GetRunArguments(): string;
begin
  Result := FRunArguments;
end;

// Target model

procedure TPCZigBuild.SetTarget(const ATarget: string);
begin
  // Only a triple of zig's names is stored (R31): a typo would build for
  // another target, or write a build.zig zig cannot read
  if DoAcceptTarget(ATarget) then
    FTarget := ATarget;
end;

procedure TPCZigBuild.SetTarget(const AArch: string; const AOS: string;
  const AAbi: string);
var
  LTarget: string;
begin
  LTarget := AArch + '-' + AOS;
  if AAbi <> '' then
    LTarget := LTarget + '-' + AAbi;
  SetTarget(LTarget);
end;

function TPCZigBuild.GetTarget(): string;
begin
  Result := FTarget;
end;

function TPCZigBuild.DoSplitTarget(const ATarget: string; out AArch: string;
  out AOS: string; out AAbi: string): Boolean;
var
  LParts: TArray<string>;
  LI: Integer;
begin
  AArch := '';
  AOS := '';
  AAbi := '';
  Result := False;

  LParts := ATarget.Split(['-']);
  if Length(LParts) < 2 then
    Exit;

  AArch := LParts[0];
  AOS := LParts[1];

  // Third and any further segments together form the ABI, rejoined with '-'
  if Length(LParts) >= 3 then
  begin
    AAbi := LParts[2];
    for LI := 3 to High(LParts) do
      AAbi := AAbi + '-' + LParts[LI];
  end;

  Result := True;
end;

function TPCZigBuild.DoZigTargetQuery(): string;
var
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  // FTarget is always a triple of zig's names (SetTarget, R31): the inner
  // part of the target query, each name a zig enum literal
  DoSplitTarget(FTarget, LArch, LOS, LAbi);
  Result := '.cpu_arch = .' + DoZigEnumName(LArch) + ', .os_tag = .' + DoZigEnumName(LOS);
  if LAbi <> '' then
    Result := Result + ', .abi = .' + DoZigEnumName(LAbi);
end;

// Source files

procedure TPCZigBuild.DoAddSourcePath(const ARaw: string; const ABase: string);
var
  LPath: string;
  LLanguage: TPCSourceLanguage;
begin
  // DoAddPath's rule (one resolve: a path no file routine takes is ZB0020;
  // empty = no path; stored once) plus the name check on the accepted path:
  // a name clang does not compile (a .h, a linker input) is ZB0033. Exact
  // case: a .C file is C++
  if not DoAcceptPath(ARaw, ABase, RSZigBuildWhatSourceFile, LPath) then
    Exit;
  if LPath = '' then
    Exit;
  if not TPCSourceFiles.LanguageOf(LPath, LLanguage) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_NOTSOURCE, RSZigBuildNotSource,
        [ARaw, TPCSourceFiles.ExtensionsText()]);
    Exit;
  end;
  if FSourceFiles.IndexOf(LPath) < 0 then
    FSourceFiles.Add(LPath);
end;

procedure TPCZigBuild.AddSourceFile(const ASourceFile: string);
begin
  DoAddSourcePath(ASourceFile, '');
end;

// Adds a list of source files as given. Each entry is passed through
// AddSourceFile, so empty entries and duplicates are skipped.
procedure TPCZigBuild.AddSourceFiles(const AFiles: array of string);
var
  LIndex: Integer;
begin
  for LIndex := Low(AFiles) to High(AFiles) do
    AddSourceFile(AFiles[LIndex]);
end;

// Adds a list of source files resolved against a common base path. This is
// the curated-manifest form: the caller states exactly which files belong to
// the build, which matters for source trees where only a subset compiles as
// its own translation unit.
procedure TPCZigBuild.AddSourceFiles(const ABasePath: string;
  const AFiles: array of string);
var
  LIndex: Integer;
  LBase: string;
begin
  // The base is accepted once; each entry resolves against it (an absolute
  // entry ignores it, an empty one is skipped). An empty base means the CWD.
  if not DoAcceptPath(ABasePath, '', RSZigBuildWhatSourceBase, LBase) then
    Exit;

  for LIndex := Low(AFiles) to High(AFiles) do
    DoAddSourcePath(AFiles[LIndex], LBase);
end;

procedure TPCZigBuild.RemoveSourceFile(const ASourceFile: string);
begin
  DoRemovePath(FSourceFiles, ASourceFile, RSZigBuildWhatSourceFile);
end;

procedure TPCZigBuild.ClearSourceFiles();
begin
  FSourceFiles.Clear();
end;

// Include paths

procedure TPCZigBuild.AddIncludePath(const APath: string);
begin
  DoAddPath(FIncludePaths, APath, '', RSZigBuildWhatIncludePath);
end;

procedure TPCZigBuild.RemoveIncludePath(const APath: string);
begin
  DoRemovePath(FIncludePaths, APath, RSZigBuildWhatIncludePath);
end;

procedure TPCZigBuild.ClearIncludePaths();
begin
  FIncludePaths.Clear();
end;

// Library paths

procedure TPCZigBuild.AddLibraryPath(const APath: string);
begin
  DoAddPath(FLibraryPaths, APath, '', RSZigBuildWhatLibraryPath);
end;

procedure TPCZigBuild.RemoveLibraryPath(const APath: string);
begin
  DoRemovePath(FLibraryPaths, APath, RSZigBuildWhatLibraryPath);
end;

procedure TPCZigBuild.ClearLibraryPaths();
begin
  FLibraryPaths.Clear();
end;

// Link libraries

procedure TPCZigBuild.AddLinkLibrary(const ALibrary: string);
begin
  if (ALibrary <> '') and (FLinkLibraries.IndexOf(ALibrary) < 0) then
    FLinkLibraries.Add(ALibrary);
end;

// Adds a list of link libraries. Each entry is passed through
// AddLinkLibrary, so empty entries and duplicates are skipped.
procedure TPCZigBuild.AddLinkLibraries(const ALibraries: array of string);
var
  LIndex: Integer;
begin
  for LIndex := Low(ALibraries) to High(ALibraries) do
    AddLinkLibrary(ALibraries[LIndex]);
end;

procedure TPCZigBuild.RemoveLinkLibrary(const ALibrary: string);
var
  LIndex: Integer;
begin
  LIndex := FLinkLibraries.IndexOf(ALibrary);
  if LIndex >= 0 then
    FLinkLibraries.Delete(LIndex);
end;

procedure TPCZigBuild.ClearLinkLibraries();
begin
  FLinkLibraries.Clear();
end;

// Defines

function TPCZigBuild.FindDefineIndex(const ADefineName: string): Integer;
var
  LI: Integer;
  LEntry: string;
  LEqualPos: Integer;
  LName: string;
begin
  Result := -1;
  for LI := 0 to FDefines.Count - 1 do
  begin
    LEntry := FDefines[LI];
    LEqualPos := Pos('=', LEntry);
    if LEqualPos > 0 then
      LName := Copy(LEntry, 1, LEqualPos - 1)
    else
      LName := LEntry;

    if SameText(LName, ADefineName) then
    begin
      Result := LI;
      Exit;
    end;
  end;
end;

procedure TPCZigBuild.SetDefine(const ADefineName: string);
var
  LIndex: Integer;
begin
  if ADefineName = '' then
    Exit;

  // Update in place if already present, otherwise append
  LIndex := FindDefineIndex(ADefineName);
  if LIndex >= 0 then
    FDefines[LIndex] := ADefineName
  else
    FDefines.Add(ADefineName);
end;

procedure TPCZigBuild.SetDefine(const ADefineName: string; const AValue: string);
var
  LIndex: Integer;
  LEntry: string;
begin
  if ADefineName = '' then
    Exit;

  LEntry := ADefineName + '=' + AValue;

  // Update in place if already present, otherwise append
  LIndex := FindDefineIndex(ADefineName);
  if LIndex >= 0 then
    FDefines[LIndex] := LEntry
  else
    FDefines.Add(LEntry);
end;

// Sets a list of value-less defines. Each entry is passed through the
// single-argument SetDefine overload.
procedure TPCZigBuild.SetDefines(const ADefineNames: array of string);
var
  LIndex: Integer;
begin
  for LIndex := Low(ADefineNames) to High(ADefineNames) do
    SetDefine(ADefineNames[LIndex]);
end;

procedure TPCZigBuild.RemoveDefine(const ADefineName: string);
var
  LIndex: Integer;
begin
  LIndex := FindDefineIndex(ADefineName);
  if LIndex >= 0 then
    FDefines.Delete(LIndex);
end;

procedure TPCZigBuild.ClearDefines();
begin
  FDefines.Clear();
end;

function TPCZigBuild.HasDefine(const ADefineName: string): Boolean;
begin
  Result := FindDefineIndex(ADefineName) >= 0;
end;

function TPCZigBuild.GetDefines(): TStringList;
begin
  Result := FDefines;
end;

// Undefines

procedure TPCZigBuild.UnsetDefine(const ADefineName: string);
begin
  if ADefineName = '' then
    Exit;

  if FUndefines.IndexOf(ADefineName) < 0 then
    FUndefines.Add(ADefineName);
end;

procedure TPCZigBuild.RemoveUndefine(const ADefineName: string);
var
  LIndex: Integer;
begin
  LIndex := FUndefines.IndexOf(ADefineName);
  if LIndex >= 0 then
    FUndefines.Delete(LIndex);
end;

procedure TPCZigBuild.ClearUndefines();
begin
  FUndefines.Clear();
end;

function TPCZigBuild.HasUndefine(const ADefineName: string): Boolean;
begin
  Result := FUndefines.IndexOf(ADefineName) >= 0;
end;

function TPCZigBuild.GetUndefines(): TStringList;
begin
  Result := FUndefines;
end;

// Copy DLLs

// Copy requests
//
// A copy-DLL request (deployed beside the artifact before the build) and a
// publish request (finished output copied out after the stamps) are one
// record each, resolved once at registration (R15, R16). Before anything of a
// list is copied, every request in it is checked - its source is there, no
// two sources land on one destination file - and a list that fails copies
// nothing: no partial deployment, no partial publish.

procedure TPCZigBuild.DoAddCopyItem(const AList: TList<TPCPublishItem>;
  const AItem: TPCPublishItem);
var
  LI: Integer;
begin
  // The same request twice (any spelling: both are resolved) is one
  for LI := 0 to AList.Count - 1 do
  begin
    if (AList[LI].Kind = AItem.Kind) and
      TUtils.SamePath(AList[LI].SourcePath, AItem.SourcePath) and
      TUtils.SamePath(AList[LI].DestDir, AItem.DestDir) then
      Exit;
  end;
  AList.Add(AItem);
end;

function TPCZigBuild.DoAcceptPublishDest(const ADestDir: string;
  out AResolved: string): Boolean;
var
  LDestRaw: string;
begin
  // An empty destination is the CWD at registration
  LDestRaw := ADestDir;
  if LDestRaw.Trim() = '' then
    LDestRaw := '.';
  Result := DoAcceptPath(LDestRaw, '', RSZigBuildWhatPublishDest, AResolved);
end;

procedure TPCZigBuild.AddCopyDLL(const ADLLPath: string);
var
  LItem: TPCPublishItem;
begin
  // An empty request cannot be met: said, not dropped
  if ADLLPath.Trim() = '' then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_EMPTYSOURCE, RSZigBuildEmptySource,
        [RSZigBuildWhatCopyDLL]);
    Exit;
  end;

  // Its destination is the artifact folder, known at copy time
  LItem := Default(TPCPublishItem);
  LItem.Kind := pkFile;
  if not DoAcceptPath(ADLLPath, '', RSZigBuildWhatCopyDLL, LItem.SourcePath) then
    Exit;
  DoAddCopyItem(FCopyDLLs, LItem);
end;

procedure TPCZigBuild.RemoveCopyDLL(const ADLLPath: string);
var
  LResolved: string;
  LI: Integer;
begin
  if not DoAcceptPath(ADLLPath, '', RSZigBuildWhatCopyDLL, LResolved) then
    Exit;
  for LI := FCopyDLLs.Count - 1 downto 0 do
  begin
    if TUtils.SamePath(FCopyDLLs[LI].SourcePath, LResolved) then
      FCopyDLLs.Delete(LI);
  end;
end;

procedure TPCZigBuild.ClearCopyDLLs();
begin
  FCopyDLLs.Clear();
end;

procedure TPCZigBuild.AddPostBuildCopy(const ASourceFile: string;
  const ADestDir: string);
var
  LItem: TPCPublishItem;
begin
  if ASourceFile.Trim() = '' then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_EMPTYSOURCE, RSZigBuildEmptySource,
        [RSZigBuildWhatPublishSource]);
    Exit;
  end;

  LItem := Default(TPCPublishItem);
  LItem.Kind := pkFile;
  if not DoAcceptPath(ASourceFile, '', RSZigBuildWhatPublishSource, LItem.SourcePath) then
    Exit;
  if not DoAcceptPublishDest(ADestDir, LItem.DestDir) then
    Exit;
  DoAddCopyItem(FPublishItems, LItem);
end;

procedure TPCZigBuild.AddPublishArtifact(const ADestDir: string);
var
  LItem: TPCPublishItem;
begin
  // The artifact's path is the layout rule's (DoArtifactPath), known after
  // the build: callers never name zig's folders
  LItem := Default(TPCPublishItem);
  LItem.Kind := pkArtifact;
  if not DoAcceptPublishDest(ADestDir, LItem.DestDir) then
    Exit;
  DoAddCopyItem(FPublishItems, LItem);
end;

procedure TPCZigBuild.ClearPostBuildCopies();
begin
  FPublishItems.Clear();
end;

function TPCZigBuild.DoCopySource(const AItem: TPCPublishItem;
  const AArtifactPath: string): string;
begin
  if AItem.Kind = pkArtifact then
    Result := AArtifactPath
  else
    Result := AItem.SourcePath;
end;

function TPCZigBuild.DoCopyDest(const AItem: TPCPublishItem;
  const ADefaultDir: string): string;
begin
  if AItem.DestDir = '' then
    Result := ADefaultDir
  else
    Result := AItem.DestDir;
end;

function TPCZigBuild.DoCheckCopies(const AList: TList<TPCPublishItem>;
  const AArtifactPath: string; const ADefaultDir: string): Boolean;
var
  LI: Integer;
  LJ: Integer;
  LSource: string;
  LDest: string;
  LOther: string;
begin
  Result := True;
  for LI := 0 to AList.Count - 1 do
  begin
    // A source that is not there: the request cannot be met
    LSource := DoCopySource(AList[LI], AArtifactPath);
    if not FileExists(LSource) then
    begin
      Result := False;
      if Assigned(FErrors) then
        FErrors.Add(esError, PC_ERR_ZIGBUILD_SOURCEMISSING, RSZigBuildSourceMissing,
          [LSource]);
      Continue;
    end;

    // Two different sources onto one destination file: the later would
    // overwrite the earlier under a green build. Reported once per pair.
    LDest := TUtils.JoinResolvedPath(DoCopyDest(AList[LI], ADefaultDir),
      TPath.GetFileName(LSource));
    for LJ := LI + 1 to AList.Count - 1 do
    begin
      LOther := DoCopySource(AList[LJ], AArtifactPath);
      if (not TUtils.SamePath(LSource, LOther)) and TUtils.SamePath(LDest,
        TUtils.JoinResolvedPath(DoCopyDest(AList[LJ], ADefaultDir),
        TPath.GetFileName(LOther))) then
      begin
        Result := False;
        if Assigned(FErrors) then
          FErrors.Add(esError, PC_ERR_ZIGBUILD_COLLISION, RSZigBuildCopyCollision,
            [LSource, LOther, LDest]);
      end;
    end;
  end;
end;

function TPCZigBuild.DoRunCopies(const AList: TList<TPCPublishItem>;
  const AArtifactPath: string; const ADefaultDir: string;
  const AFailCode: string; const AFailText: string;
  const AStatus: string): Boolean;
var
  LI: Integer;
  LSource: string;
  LDestDir: string;
  LDestPath: string;
begin
  Result := True;
  for LI := 0 to AList.Count - 1 do
  begin
    LSource := DoCopySource(AList[LI], AArtifactPath);
    LDestDir := DoCopyDest(AList[LI], ADefaultDir);

    // Already where it is wanted
    if TUtils.SamePath(TPath.GetDirectoryName(LSource), LDestDir) then
      Continue;

    LDestPath := TUtils.JoinResolvedPath(LDestDir, TPath.GetFileName(LSource));
    try
      TUtils.EnsureDirectory(LDestDir);
      Status(AStatus, [TPath.GetFileName(LSource), TUtils.NormalizePath(LDestDir)]);
      TFile.Copy(LSource, LDestPath, True);
    except
      on E: Exception do
      begin
        if Assigned(FErrors) then
          FErrors.Add(esError, AFailCode, AFailText, [LDestPath, E.Message]);
        Exit(False);
      end;
    end;
  end;
end;

function TPCZigBuild.DoPostBuildCopies(const AArtifactPath: string): Boolean;
begin
  // Every request checked first: nothing is published unless all can be
  Result := DoCheckCopies(FPublishItems, AArtifactPath, '') and
    DoRunCopies(FPublishItems, AArtifactPath, '', PC_ERR_ZIGBUILD_PUBLISHFAILED,
    RSZigBuildPublishError, RSZigBuildPublishing);
end;

{ DoHasName }
// AName is in ANames, by the file system's rule for names in the copy-DLL
// folder (the host's: case-insensitive on Windows, whatever the target)
function DoHasName(const ANames: TList<string>; const AName: string): Boolean;
var
  LName: string;
begin
  for LName in ANames do
  begin
    if SameText(LName, AName) then
      Exit(True);
  end;
  Result := False;
end;

function TPCZigBuild.DoCopyRecordPath(): string;
begin
  Result := TUtils.JoinResolvedPath(FOutputPath, PC_ZIG_COPYDLL_RECORD);
end;

procedure TPCZigBuild.DoReadCopyRecord(out ANames: TArray<string>);
var
  LPath: string;
  LLines: TArray<string>;
  LList: TList<string>;
  LLine: string;
  LName: string;
begin
  // No record = no earlier copies. A record that is there but cannot be
  // read is ZB0034 and holds no names: nothing is removed on its word
  ANames := nil;
  LPath := DoCopyRecordPath();
  if not FileExists(LPath) then
    Exit;
  try
    LLines := TFile.ReadAllLines(LPath, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      if Assigned(FErrors) then
        FErrors.Add(esWarning, PC_ERR_ZIGBUILD_WRNSTALECOPY, RSZigBuildCopyRecordRead,
          [TUtils.StripLongPathPrefix(LPath), E.Message]);
      Exit;
    end;
  end;

  LList := TList<string>.Create();
  try
    for LLine in LLines do
    begin
      // A bare file name only: anything else (a folder, '.', '..', a path)
      // is no copy this step made, and is never deleted on the record's word
      LName := LLine.Trim();
      if (LName = '') or (LName = '.') or (LName = '..') or
        (TPath.GetFileName(LName) <> LName) then
        Continue;
      if not DoHasName(LList, LName) then
        LList.Add(LName);
    end;
    ANames := LList.ToArray();
  finally
    LList.Free();
  end;
end;

procedure TPCZigBuild.DoWriteCopyRecord(const ANames: TArray<string>);
var
  LPath: string;
begin
  // UTF-8 without a BOM, LF; no copies = no record
  LPath := DoCopyRecordPath();
  try
    if Length(ANames) = 0 then
    begin
      if FileExists(LPath) then
        TFile.Delete(LPath);
    end
    else
      TFile.WriteAllBytes(LPath, TEncoding.UTF8.GetBytes(string.Join(#10, ANames) + #10));
  except
    on E: Exception do
    begin
      if Assigned(FErrors) then
        FErrors.Add(esWarning, PC_ERR_ZIGBUILD_WRNSTALECOPY, RSZigBuildCopyRecordWrite,
          [TUtils.StripLongPathPrefix(LPath), E.Message]);
    end;
  end;
end;

function TPCZigBuild.DoDeployCopyDLLs(): Boolean;
var
  LDestDir: string;
  LOld: TArray<string>;
  LWanted: TList<string>;
  LOwned: TList<string>;
  LItem: TPCPublishItem;
  LName: string;
  LPath: string;
begin
  // Copy DLLs: the DLLs the program loads, deployed beside the artifact
  // (where a built DLL lands, DoArtifactDir) BEFORE the build. The linker
  // does not need them (it reads library paths); a deployment that cannot be
  // completed - a DLL missing, two DLLs of one name, a copy that fails -
  // stops here, and the build is not run (R16).
  // First, a copy an earlier build made that no copy-DLL names any more is
  // removed (F10): a program must not keep running here on a library it no
  // longer ships. Only the names the record holds, never the artifact; a file
  // whose source already sits in that folder is no copy and is never recorded
  LDestDir := DoArtifactDir(bmDll);
  DoReadCopyRecord(LOld);

  LWanted := TList<string>.Create();
  LOwned := TList<string>.Create();
  try
    for LItem in FCopyDLLs do
    begin
      if not TUtils.SamePath(TPath.GetDirectoryName(LItem.SourcePath), LDestDir) then
        LWanted.Add(TPath.GetFileName(LItem.SourcePath));
    end;

    for LName in LOld do
    begin
      // Copied again below: it stays
      if DoHasName(LWanted, LName) then
        Continue;
      LPath := TUtils.JoinResolvedPath(LDestDir, LName);
      if TUtils.SamePath(LPath, DoArtifactPath()) or (not FileExists(LPath)) then
        Continue;
      try
        Status(RSZigBuildStaleCopyRemoving, [LName]);
        TFile.Delete(LPath);
      except
        on E: Exception do
        begin
          // Still ours: the next build tries again
          if Assigned(FErrors) then
            FErrors.Add(esWarning, PC_ERR_ZIGBUILD_WRNSTALECOPY, RSZigBuildStaleCopyRemove,
              [TUtils.StripLongPathPrefix(LPath), E.Message]);
          LOwned.Add(LName);
        end;
      end;
    end;

    // This build's copies, every request checked first (R16)
    Result := True;
    if FCopyDLLs.Count > 0 then
      Result := DoCheckCopies(FCopyDLLs, '', LDestDir) and
        DoRunCopies(FCopyDLLs, '', LDestDir, PC_ERR_ZIGBUILD_COPYFAILED,
        RSZigBuildCopyFailed, RSZigBuildCopying);

    // The record: the copies of ours in the folder now, whatever the copy
    // step's outcome (an unreadable record is replaced: it was reported)
    for LName in LWanted do
    begin
      if (not DoHasName(LOwned, LName)) and
        FileExists(TUtils.JoinResolvedPath(LDestDir, LName)) then
        LOwned.Add(LName);
    end;
    DoWriteCopyRecord(LOwned.ToArray());
  finally
    LOwned.Free();
    LWanted.Free();
  end;
end;

// Artifact layout
//
// THE layout rule (R14, PLAN-OUTPUT): zig installs the artifact straight
// under the build root (zig build -p <root>, Process), in 'lib' for a static
// library and in 'bin' for an executable and a dynamic library (dynamic
// libraries beside the executable on every target, so a program finds its
// DLLs by one rule; static libraries are link-time input). build.zig's
// install step, the copy-DLL folder, the stamped and published artifact and
// Run all derive from it.

function TPCZigBuild.DoArtifactSubdir(const ABuildMode: TPCBuildMode): string;
begin
  if ABuildMode = bmLib then
    Result := 'lib'
  else
    Result := 'bin';
end;

function TPCZigBuild.DoArtifactDir(const ABuildMode: TPCBuildMode): string;
begin
  Result := TUtils.JoinResolvedPath(FOutputPath, DoArtifactSubdir(ABuildMode));
end;

function TPCZigBuild.DoArtifactPath(): string;
begin
  Result := TUtils.JoinResolvedPath(DoArtifactDir(FBuildMode), GetOutputFilename());
end;

function TPCZigBuild.GetArtifactDir(): string;
begin
  Result := DoArtifactDir(FBuildMode);
end;

function TPCZigBuild.GetArtifactPath(): string;
begin
  Result := DoArtifactPath();
end;

// Clear all

procedure TPCZigBuild.Clear();
begin
  ClearSourceFiles();
  ClearIncludePaths();
  ClearLibraryPaths();
  ClearLinkLibraries();
  ClearDefines();
  ClearUndefines();
  ClearCopyDLLs();
  ClearPostBuildCopies();
  FProjectName := PC_DEFAULT_PROJECT_NAME;
  FBuildMode := bmExe;
  FOptimizeLevel := olDebug;
  FTarget := PC_DEFAULT_TARGET;
  FSubsystem := stConsole;
  FLastExitCode := 0;

  // Reset version info
  FAddVersionInfo := False;
  FVIMajor := 0;
  FVIMinor := 0;
  FVIPatch := 0;
  FVIProductName := '';
  FVIDescription := '';
  FVIFilename := '';
  FVICompanyName := '';
  FVICopyright := '';
  FExeIcon := '';
end;

// Getters

function TPCZigBuild.GetLastExitCode(): DWORD;
begin
  Result := FLastExitCode;
end;

function TPCZigBuild.GetOutputPath(): string;
begin
  Result := FOutputPath;
end;

function TPCZigBuild.GetProjectName(): string;
begin
  Result := FProjectName;
end;

function TPCZigBuild.GetBuildMode(): TPCBuildMode;
begin
  Result := FBuildMode;
end;

function TPCZigBuild.GetOptimizeLevel(): TPCOptimizeLevel;
begin
  Result := FOptimizeLevel;
end;

function TPCZigBuild.GetSubsystem(): TPCSubsystemType;
begin
  Result := FSubsystem;
end;

function TPCZigBuild.GetSourceFileCount(): Integer;
begin
  Result := FSourceFiles.Count;
end;

function TPCZigBuild.GetSourceFile(const AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FSourceFiles.Count) then
    Result := FSourceFiles[AIndex]
  else
    Result := '';
end;

// Platform extension helpers

function TPCZigBuild.GetExeExtension(): string;
var
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(PC_DEFAULT_TARGET, LArch, LOS, LAbi);

  if SameText(LArch, ARCH_WASM32) or SameText(LArch, ARCH_WASM64) then
    Result := '.wasm'
  else if SameText(LOS, OS_WINDOWS) then
    Result := '.exe'
  else if SameText(LOS, OS_UEFI) then
    Result := '.efi'
  else
    Result := '';
end;

function TPCZigBuild.GetDllExtension(): string;
var
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(PC_DEFAULT_TARGET, LArch, LOS, LAbi);

  if SameText(LOS, OS_WINDOWS) then
    Result := '.dll'
  else if SameText(LOS, OS_MACOS) or SameText(LOS, OS_IOS)
       or SameText(LOS, OS_TVOS) or SameText(LOS, OS_WATCHOS)
       or SameText(LOS, OS_VISIONOS) or SameText(LOS, OS_DRIVERKIT)
       or SameText(LOS, OS_MACCATALYST) then
    Result := '.dylib'
  else if SameText(LArch, ARCH_WASM32) or SameText(LArch, ARCH_WASM64) then
    Result := '.wasm'
  else
    Result := '.so';
end;

function TPCZigBuild.GetLibExtension(): string;
var
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(PC_DEFAULT_TARGET, LArch, LOS, LAbi);

  if SameText(LOS, OS_WINDOWS) then
    Result := '.lib'
  else
    Result := '.a';
end;

// Unix toolchains prefix library artifacts with "lib" - libfoo.so, libfoo.a,
// libfoo.dylib. Windows does not, and neither does wasm. The prefix belongs
// to library build modes only; executables never take it.
function TPCZigBuild.GetLibPrefix(): string;
var
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(PC_DEFAULT_TARGET, LArch, LOS, LAbi);

  if SameText(LOS, OS_WINDOWS) then
    Result := ''
  else if SameText(LArch, ARCH_WASM32) or SameText(LArch, ARCH_WASM64) then
    Result := ''
  else
    Result := 'lib';
end;

function TPCZigBuild.GetOutputFilename(): string;
var
  LPrefix: string;
  LExtension: string;
begin
  LPrefix := '';

  case FBuildMode of
    bmExe:
      LExtension := GetExeExtension();
    bmLib:
      begin
        LPrefix := GetLibPrefix();
        LExtension := GetLibExtension();
      end;
    bmDll:
      begin
        LPrefix := GetLibPrefix();
        LExtension := GetDllExtension();
      end;
  else
    LExtension := GetExeExtension();
  end;

  Result := LPrefix + FProjectName + LExtension;
end;

// Display names

function TPCZigBuild.GetTargetDisplayName(): string;
begin
  if FTarget = '' then
    Result := 'native'
  else
    Result := FTarget;
end;

function TPCZigBuild.GetOptimizeLevelDisplayName(): string;
begin
  case FOptimizeLevel of
    olDebug:
      Result := 'Debug';
    olReleaseSafe:
      Result := 'ReleaseSafe';
    olReleaseFast:
      Result := 'ReleaseFast';
    olReleaseSmall:
      Result := 'ReleaseSmall';
  else
    Result := 'Unknown';
  end;
end;

function TPCZigBuild.GetSubsystemDisplayName(): string;
begin
  if FSubsystem = stGUI then
    Result := 'GUI'
  else
    Result := 'Console';
end;

// build.zig generation

function TPCZigBuild.GetZigOptimizeString(): string;
begin
  Result := DoOptimizeName(FOptimizeLevel);
end;

function TPCZigBuild.DoOptimizeName(const ALevel: TPCOptimizeLevel): string;
begin
  // One name per level both ways: build.zig's optimize line and its loader
  case ALevel of
    olDebug:
      Result := '.Debug';
    olReleaseSafe:
      Result := '.ReleaseSafe';
    olReleaseFast:
      Result := '.ReleaseFast';
    olReleaseSmall:
      Result := '.ReleaseSmall';
  else
    Result := '.Debug';
  end;
end;

function TPCZigBuild.BuildFlagsString(const ALanguage: TPCSourceLanguage): string;
var
  LFlags: TStringList;
  LI: Integer;
  LEntry: string;
  LMaxErrors: Integer;
begin
  LFlags := TStringList.Create();
  try
    // Language standard for this group. Assembly gets none: a dialect flag on
    // an assembler-with-cpp input defines the corresponding language macro,
    // and a defined __cplusplus turns every `extern "C" {` in an included
    // header into an assembler syntax error.
    if ALanguage = slCpp then
      LFlags.Add(PC_CPP_STD_FLAG)
    else if ALanguage = slC then
      LFlags.Add(PC_C_STD_FLAG);

    // C++-only flags
    if ALanguage = slCpp then
    begin
      LFlags.Add('"-fexceptions"');
      LFlags.Add('"-frtti"');
      LFlags.Add('"-fexperimental-library"');
    end;

    // Compiler codegen and diagnostic flags. These describe how to compile a
    // translation unit, so they apply to the C and C++ groups only - none of
    // them mean anything when assembling a .S.
    if (ALanguage <> slAsm) and (ALanguage <> slLLVMIR) then
    begin
      // Required for hardware exception handling
      LFlags.Add('"-fno-sanitize=undefined"');
      // A store or load through nil stays a real access at every optimize
      // level, so a guard catches it as exception 3. Without it clang treats a
      // nil it can prove as undefined and deletes the access or makes it a
      // trap at release_safe / release_fast: the guard never ran and the
      // program died (PLAN-RELEASE R2, TODO 13 (a))
      LFlags.Add('"-fno-delete-null-pointer-checks"');
      // Suppress warning about ((a == b)) in if statements
      LFlags.Add('"-Wno-parentheses-equality"');
      LFlags.Add('"-fdeclspec"');
      LFlags.Add('"-fms-extensions"');
      // Required for debugger stack unwinding via [RBP+8]
      LFlags.Add('"-fno-omit-frame-pointer"');

      // Hide symbols by default in DLLs to prevent runtime symbol conflicts
      if FBuildMode = bmDll then
        LFlags.Add('"-fvisibility=hidden"');
    end;

    // Suppress Zig-injected flags like -fno-rtlib-defaultlib. Every group
    // needs this, assembly included.
    LFlags.Add('"-Wno-unused-command-line-argument"');

    // Add defines (-DNAME or -DNAME=VALUE)
    for LI := 0 to FDefines.Count - 1 do
    begin
      LEntry := FDefines[LI];
      LFlags.Add(ZigStringLiteral('-D' + LEntry));
    end;

    // Add undefines (-UNAME)
    for LI := 0 to FUndefines.Count - 1 do
    begin
      LEntry := FUndefines[LI];
      LFlags.Add(ZigStringLiteral('-U' + LEntry));
    end;

    // Stop rule: by default the first error is fatal and clang stops right
    // there (-Wfatal-errors). A shared error budget above 1 asks clang for
    // that many errors instead (-ferror-limit=N). Both apply per TU.
    LMaxErrors := 1;
    if (FErrors <> nil) and (FErrors.GetMaxErrors() > 0) then
      LMaxErrors := FErrors.GetMaxErrors();
    if LMaxErrors > 1 then
      LFlags.Add(Format('"-ferror-limit=%d"', [LMaxErrors]))
    else
      LFlags.Add('"-Wfatal-errors"');

    // Join into a single comma-separated flag list
    Result := '';
    for LI := 0 to LFlags.Count - 1 do
    begin
      if LI > 0 then
        Result := Result + ', ';
      Result := Result + LFlags[LI];
    end;
  finally
    LFlags.Free();
  end;
end;

function TPCZigBuild.GetSourceLanguage(const ASourceFile: string): TPCSourceLanguage;
begin
  // PC_SOURCE_EXTS, exact case, as clang reads the name (a case-insensitive
  // match gave '.C', which clang compiles as C++, the C group's -std=gnu23:
  // a hard error). .S (preprocessed) and .s share the assembly group: clang
  // decides whether to preprocess from the literal file name. Every stored
  // source passed DoAddSourcePath, so a miss is an invariant
  if not TPCSourceFiles.LanguageOf(ASourceFile, Result) then
    raise EInvalidOpException.CreateFmt(RSZigBuildNotSource, [ASourceFile, TPCSourceFiles.ExtensionsText()]);
end;

procedure TPCZigBuild.DoZigHeader(const ABuilder: TStringBuilder);
begin
  ABuilder.AppendLine('const std = @import("std");');
  ABuilder.AppendLine();
  ABuilder.AppendLine('pub fn build(b: *std.Build) void {');

  // Explicit target query derived from the raw triple string
  ABuilder.AppendLine('    ' + PC_ZIG_FORM_TARGET_PRE + DoZigTargetQuery() +
    PC_ZIG_FORM_TARGET_SUF);
  ABuilder.AppendLine('    ' + PC_ZIG_FORM_OPTIMIZE_PRE + GetZigOptimizeString() + ';');
  ABuilder.AppendLine();
end;

procedure TPCZigBuild.DoZigArtifact(const ABuilder: TStringBuilder;
  out AArtifactVar: string);
var
  LLinkage: string;
begin
  // Executable vs library declaration
  if FBuildMode = bmExe then
  begin
    AArtifactVar := 'exe';
    ABuilder.AppendLine('    ' + PC_ZIG_FORM_EXE);
  end
  else
  begin
    AArtifactVar := 'lib';
    ABuilder.AppendLine('    ' + PC_ZIG_FORM_LIB);
    if FBuildMode = bmLib then
      LLinkage := '.static'
    else
      LLinkage := '.dynamic';
    ABuilder.AppendLine('        ' + PC_ZIG_FORM_LINKAGE_PRE + LLinkage + ',');
  end;

  // Name and root module
  ABuilder.AppendLine('        ' + PC_ZIG_FORM_NAME_PRE + ZigStringLiteral(FProjectName) + ',');
  ABuilder.AppendLine('        .root_module = b.createModule(.{');
  ABuilder.AppendLine('            .target = target,');
  ABuilder.AppendLine('            .optimize = optimize,');
  ABuilder.AppendLine('            .link_libc = true,');
  ABuilder.AppendLine('            .link_libcpp = true,');
  ABuilder.AppendLine('        }),');
  ABuilder.AppendLine('    });');

  // GUI subsystem: suppress the console window on Windows (executables only)
  if (FBuildMode = bmExe) and (FSubsystem = stGUI) then
  begin
    ABuilder.AppendLine();
    ABuilder.AppendLine('    // GUI subsystem: no console window');
    ABuilder.AppendLine('    if (target.result.os.tag == .windows) {');
    ABuilder.AppendLine('        ' + PC_ZIG_FORM_SUBSYSTEM);
    ABuilder.AppendLine('    }');
  end;

  ABuilder.AppendLine();
end;

procedure TPCZigBuild.DoZigSourceGroup(const ABuilder: TStringBuilder;
  const AArtifactVar: string; const AFiles: TStringList;
  const ALanguage: TPCSourceLanguage);
var
  LI: Integer;
  LFlagsStr: string;
  LDiagPath: string;
begin
  if AFiles.Count = 0 then
    Exit;

  LFlagsStr := BuildFlagsString(ALanguage);

  // Every TU gets its own block: cc1 takes one serialized-diagnostics file per
  // compile, so each TU carries its own flag (C, C++, LLVM IR, and a .S's
  // preprocessor job). The path is stable, so the flag (part of zig's cache
  // key) does not defeat the cache. The TU is its file name under its own
  // folder as .root: zig refuses an absolute path in .files, and a path on
  // another drive than the build root has no relative form (R30).
  for LI := 0 to AFiles.Count - 1 do
  begin
    // clang takes the plain spelling (text for another tool)
    LDiagPath := TUtils.StripLongPathPrefix(DoDiagFilePath(AFiles[LI])).Replace('\', '/');
    ABuilder.AppendLine('    ' + AArtifactVar + '.root_module.addCSourceFiles(.{');
    ABuilder.AppendLine('        ' + PC_ZIG_FORM_ROOT_PRE +
      ZigStringLiteral(DoZigPath(TPath.GetDirectoryName(AFiles[LI]))) + PC_ZIG_FORM_ROOT_SUF);
    ABuilder.AppendLine('        .files = &.{');
    ABuilder.AppendLine('            ' + ZigStringLiteral(TPath.GetFileName(AFiles[LI])));
    ABuilder.AppendLine('        },');
    ABuilder.AppendLine('        ' + PC_ZIG_FORM_FLAGS_PRE + LFlagsStr +
      ', "-Xclang", "-serialize-diagnostic-file", "-Xclang", ' +
      ZigStringLiteral(LDiagPath) + PC_ZIG_FORM_FLAGS_SUF);
    ABuilder.AppendLine('    });');
  end;
end;

procedure TPCZigBuild.DoZigSources(const ABuilder: TStringBuilder;
  const AArtifactVar: string);
var
  LI: Integer;
  LArch: string;
  LOS: string;
  LAbi: string;
  LCFiles: TStringList;
  LCppFiles: TStringList;
  LAsmFiles: TStringList;
  LLLFiles: TStringList;
  LLinkFile: string;
  LLinux: Boolean;
begin
  // Include and library paths, absolute (R30: a path on another drive than
  // the build root has no relative form)
  for LI := 0 to FIncludePaths.Count - 1 do
    ABuilder.AppendLine('    ' + AArtifactVar + '.' + PC_ZIG_FORM_INCLUDE_PRE +
      ZigStringLiteral(DoZigPath(FIncludePaths[LI])) + PC_ZIG_FORM_LAZY_SUF);

  for LI := 0 to FLibraryPaths.Count - 1 do
    ABuilder.AppendLine('    ' + AArtifactVar + '.' + PC_ZIG_FORM_LIBPATH_PRE +
      ZigStringLiteral(DoZigPath(FLibraryPaths[LI])) + PC_ZIG_FORM_LAZY_SUF);

  // On Linux (executables only), add rpath $ORIGIN so the binary finds .so
  // files in its own directory
  if FBuildMode = bmExe then
  begin
    if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
      DoSplitTarget(PC_DEFAULT_TARGET, LArch, LOS, LAbi);
    if SameText(LOS, OS_LINUX) then
      ABuilder.AppendLine('    ' + AArtifactVar +
        '.root_module.addRPathSpecial("$ORIGIN");');
  end;

  // Link libraries. On a Linux target one found in a library path is handed over as its
  // file (PC_ZIG_FORM_LINKFILE_PRE: zig 0.17.0's -l:<path> fails on a Windows host); the
  // binary still records the library's soname. A name found in no library path (zig's
  // own glibc libraries, or one that is missing) stays a system library, so a missing
  // one is still zig's "unable to find" error, reported at its @linklibrary.
  LLinux := DoIsLinuxTarget();
  for LI := 0 to FLinkLibraries.Count - 1 do
  begin
    if LLinux and DoFindLinkFile(FLinkLibraries[LI], LLinkFile) then
      ABuilder.AppendLine('    ' + AArtifactVar + '.' + PC_ZIG_FORM_LINKFILE_PRE +
        ZigStringLiteral(DoZigPath(LLinkFile)) + PC_ZIG_FORM_LINKFILE_MID +
        ZigStringLiteral(FLinkLibraries[LI]))
    else
      ABuilder.AppendLine('    ' + AArtifactVar + '.' + PC_ZIG_FORM_LINKLIB_PRE +
        ZigStringLiteral(FLinkLibraries[LI]) + PC_ZIG_FORM_LINKLIB_SUF);
  end;

  // Source files, partitioned by language. Each group has its own flag list,
  // so C libraries, C++23 sources, assembly and LLVM IR can live in one
  // artifact; every TU gets its own addCSourceFiles block (its own .dia flag,
  // DoZigSourceGroup). Empty groups emit nothing.
  if FSourceFiles.Count > 0 then
  begin
    LCFiles := TStringList.Create();
    try
      LCppFiles := TStringList.Create();
      try
        LAsmFiles := TStringList.Create();
        try
          LLLFiles := TStringList.Create();
          try
            for LI := 0 to FSourceFiles.Count - 1 do
            begin
              case GetSourceLanguage(FSourceFiles[LI]) of
                slC:
                  LCFiles.Add(FSourceFiles[LI]);
                slAsm:
                  LAsmFiles.Add(FSourceFiles[LI]);
                slLLVMIR:
                  LLLFiles.Add(FSourceFiles[LI]);
              else
                LCppFiles.Add(FSourceFiles[LI]);
              end;
            end;

            DoZigSourceGroup(ABuilder, AArtifactVar, LCppFiles, slCpp);
            DoZigSourceGroup(ABuilder, AArtifactVar, LCFiles, slC);
            DoZigSourceGroup(ABuilder, AArtifactVar, LAsmFiles, slAsm);
            DoZigSourceGroup(ABuilder, AArtifactVar, LLLFiles, slLLVMIR);
          finally
            LLLFiles.Free();
          end;
        finally
          LAsmFiles.Free();
        end;
      finally
        LCppFiles.Free();
      end;
    finally
      LCFiles.Free();
    end;
  end;

  ABuilder.AppendLine();

  // The install step: one form for every artifact kind, into the folder the
  // layout rule names (DoArtifactSubdir). For an executable and a static
  // library that is zig's own default (probed: r14-artifact-layout.md); for a
  // dynamic library it puts the Linux .so beside the executable too.
  ABuilder.AppendLine('    b.getInstallStep().dependOn(&b.addInstallArtifact(' +
    AArtifactVar + ', .{');
  ABuilder.AppendLine('        .dest_dir = .{ .override = .' +
    DoArtifactSubdir(FBuildMode) + ' },');
  ABuilder.AppendLine('    }).step);');
end;

function TPCZigBuild.GenerateBuildZig(): string;
var
  LBuilder: TStringBuilder;
  LArtifactVar: string;
begin
  LBuilder := TStringBuilder.Create();
  try
    DoZigHeader(LBuilder);
    DoZigArtifact(LBuilder, LArtifactVar);
    DoZigSources(LBuilder, LArtifactVar);

    LBuilder.AppendLine('}');

    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

function TPCZigBuild.ParseFlagsLine(const APayload: string): Boolean;
var
  LFlags: TArray<string>;
  LI: Integer;
  LFlag: string;
  LEqualPos: Integer;
begin
  // BuildFlagsString's list plus the .dia flag: the defines and undefines
  // are read back, every other flag follows from the settings
  Result := ZigStringList(APayload, LFlags);
  if not Result then
    Exit;
  for LI := 0 to High(LFlags) do
  begin
    LFlag := LFlags[LI];
    if LFlag.StartsWith('-D') then
    begin
      LEqualPos := LFlag.IndexOf('=');
      if LEqualPos > 2 then
        SetDefine(LFlag.Substring(2, LEqualPos - 2), LFlag.Substring(LEqualPos + 1))
      else
        SetDefine(LFlag.Substring(2));
    end
    else if LFlag.StartsWith('-U') then
      UnsetDefine(LFlag.Substring(2));
  end;
end;

// Diagnostics

// Per-TU clang serialized diagnostics
//
// Every TU gets its own cc1 -serialize-diagnostic-file (one addCSourceFiles
// block per TU). clang writes it on success and failure alike, with every
// diagnostic's true level and its notes in text order, the include chain
// included (research\zigbuild-followup\r4-include-chain.md). cc1 takes one
// such file, so ours replaces zig's own: zig can no longer read clang's
// diagnostics and prints a failed TU's raw clang stderr instead
// (TPCBuildOutputFilter). LLVM IR compiles through cc1 like C. A .S runs cc1
// for its preprocessor, then cc1as to assemble: its file holds the
// preprocessor's diagnostics, and cc1as takes no such option (probed,
// scripts\zb_e\a1b\r38c\). A TU served from zig's cache writes nothing, so
// every TU file is deleted before the build: a file absent afterwards means
// "not compiled in this build, nothing to report".

function TPCZigBuild.DoDiagFilePath(const ASourceFile: string): string;
var
  LSource: string;
  LKey: string;
begin
  // Keyed by the TU's resolved path, so two sources with the same name in
  // different directories never share a file. MD5 is stable across runs: the
  // same TU gets the same flag in build.zig, and zig's cache key with it.
  // Lower-cased because Windows paths compare without case.
  // The source and the output path are stored resolved (DoAcceptPath)
  LSource := ASourceFile;
  LKey := THashMD5.GetHashString(LSource.ToLower()).Substring(0, 16);
  // Joined as text in ResolvePath's spelling: past the plain limit a file
  // routine needs the long-path spelling, or the file reads as absent (R41)
  Result := TUtils.JoinResolvedPath(FOutputPath, PC_DIAG_FILE_DIR + '\' +
    TPath.GetFileName(LSource) + '.' + LKey + PC_DIAG_FILE_EXT);
end;

function TPCZigBuild.DoDiagFilePrepare(): Boolean;
var
  LI: Integer;
  LDir: string;
  LDiagPath: string;
  LProbePath: string;
  LMade: Boolean;
  LReason: string;
begin
  Result := False;

  LDir := TUtils.JoinResolvedPath(FOutputPath, PC_DIAG_FILE_DIR);
  LMade := False;
  LReason := '';
  try
    LMade := ForceDirectories(LDir);
    if not LMade then
      LReason := SysErrorMessage(GetLastError());
  except
    on E: Exception do
      LReason := E.Message;
  end;
  if not LMade then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_DIAGFILEFAILED,
        RSZigBuildDiagFilePrepare, [LDir, LReason]);
    Exit;
  end;

  // clang cannot write a .dia into a directory it may not write to, and on
  // a build that succeeds zig prints nothing: that TU's diagnostics would be
  // lost without a trace. Proven writable here, or the build is not run.
  LProbePath := TUtils.JoinResolvedPath(LDir, PC_DIAG_FILE_PROBE);
  try
    TFile.WriteAllText(LProbePath, '');
    TFile.Delete(LProbePath);
  except
    on E: Exception do
    begin
      if Assigned(FErrors) then
        FErrors.Add(esError, PC_ERR_ZIGBUILD_DIAGFILEFAILED,
          RSZigBuildDiagFilePrepare, [LDir, E.Message]);
      Exit;
    end;
  end;

  // A file left from an earlier build would be read as this build's: a TU
  // served from zig's cache writes none. A directory in the way would make
  // clang drop the TU's .dia, with the same silent loss as above.
  for LI := 0 to FSourceFiles.Count - 1 do
  begin
    LDiagPath := DoDiagFilePath(FSourceFiles[LI]);
    if DirectoryExists(LDiagPath) then
    begin
      if Assigned(FErrors) then
        FErrors.Add(esError, PC_ERR_ZIGBUILD_DIAGFILEFAILED,
          RSZigBuildDiagFilePrepare, [LDiagPath, RSZigBuildDiagFileIsDir]);
      Exit;
    end;
    if FileExists(LDiagPath) and (not System.SysUtils.DeleteFile(LDiagPath)) then
    begin
      if Assigned(FErrors) then
        FErrors.Add(esError, PC_ERR_ZIGBUILD_DIAGFILEFAILED,
          RSZigBuildDiagFilePrepare,
          [LDiagPath, SysErrorMessage(GetLastError())]);
      Exit;
    end;
  end;

  Result := True;
end;

// Build output
//
// zig build is captured over plain pipes (--color off): one clean line per
// callback, handed to FBuildOutput (TPCBuildOutputFilter, PaskalCPP.BuildOutput),
// which only captures. Nothing reaches FErrors before DoFilterFlush: the
// commit (TPCBuildOutputCommit) reports every .dia entry and every capture no
// entry claimed. A failed build whose commit reported no error then reports
// zig's unrecognised lines (safety net), so a failure is never silent.

procedure TPCZigBuild.DoFilterLine(const ALine: string);
begin
  FBuildOutput.AddLine(ALine);
end;

procedure TPCZigBuild.DoFilterFlush();
var
  LI: Integer;
  LDiagFiles: TArray<string>;
  LUnreported: TArray<string>;
begin
  FBuildErrors := 0;
  if not Assigned(FErrors) then
    Exit;

  FBuildOutput.Finish();

  // Raw mode passed zig's own text through: nothing was captured
  if not FRawOutput then
  begin
    // The .dia of every TU, in source order (DoDiagFilePrepare)
    LDiagFiles := nil;
    for LI := 0 to FSourceFiles.Count - 1 do
      LDiagFiles := LDiagFiles + [DoDiagFilePath(FSourceFiles[LI])];

    FBuildCommit.SetErrors(FErrors);
    FBuildCommit.Commit(FBuildOutput, LDiagFiles,
      FOutputPath, FLocationTranslator, FLibraryLocator, FGeneratedFileTest,
      FFrontendCheck);
    FBuildErrors := FBuildCommit.ErrorsReported();
  end;

  // Safety net: a failed build that no reported error explains shows what
  // zig printed (a warning never explains a failure)
  LUnreported := TPCBuildOutputCommit.UnreportedFailure(FBuildOutput,
    FLastExitCode <> 0, FBuildErrors);
  for LI := 0 to High(LUnreported) do
  begin
    FErrors.Add(esError, PC_ERR_ZIGBUILD_BUILDFAILED, LUnreported[LI]);
    Inc(FBuildErrors);
  end;
end;

procedure TPCZigBuild.HandleOutputLine(const ALine: string;
  const AUserData: Pointer);
begin
  // Raw mode, or no error sink to parse into: the build output passes through
  if FRawOutput or (not Assigned(FErrors)) then
  begin
    if FOutput.IsAssigned() then
      FOutput.Callback(ALine, FOutput.UserData);
    Exit;
  end;

  DoFilterLine(ALine);
end;

procedure TPCZigBuild.HandleRunOutputLine(const ALine: string;
  const AUserData: Pointer);
begin
  // The built program's own output always passes through unchanged: to its
  // own sink when one is set (an editor's terminal pane), else with the rest
  if FRunOutput.IsAssigned() then
    FRunOutput.Callback(ALine, FRunOutput.UserData)
  else if FOutput.IsAssigned() then
    FOutput.Callback(ALine, FOutput.UserData);
end;

// build.zig forms
//
// GenerateBuildZig writes build.zig from a fixed set of line forms, and
// LoadBuildFile reads exactly those forms back (R20 F3, R24): a line is
// matched whole and trimmed, never by a substring, and a payload is parsed by
// the inverse of its writer, so GenerateBuildZig after a load of a generated
// file reproduces it byte for byte. Every path is absolute, as a
// cwd_relative LazyPath, and every TU its file name under its own folder as
// .root (R30); every text in a zig string literal is escaped (R48).

function TPCZigBuild.DoZigPath(const APath: string): string;
begin
  // A stored (resolved) path as zig takes it: plain spelling, forward slashes
  Result := TUtils.StripLongPathPrefix(APath).Replace('\', '/');
end;

function TPCZigBuild.DoAcceptTarget(const ATarget: string): Boolean;
var
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  // <arch>-<os>[-<abi>], each exactly one of zig's names (case-sensitive)
  Result := DoSplitTarget(ATarget, LArch, LOS, LAbi) and IsZigArch(LArch) and
    IsZigOS(LOS) and ((LAbi = '') or IsZigAbi(LAbi));
  if (not Result) and Assigned(FErrors) then
    FErrors.Add(esError, PC_ERR_ZIGBUILD_BADTARGET, RSZigBuildBadTarget, [ATarget]);
end;

procedure TPCZigBuild.DoLoadLine(const ALine: string; const ALineNo: Integer;
  const AFilename: string; var ATURoot: string);
var
  LI: Integer;
begin
  // A structure line holds nothing to read
  for LI := Low(PC_ZIG_STRUCTURE_LINES) to High(PC_ZIG_STRUCTURE_LINES) do
  begin
    if ALine = PC_ZIG_STRUCTURE_LINES[LI] then
      Exit;
  end;

  if DoLoadHeaderLine(ALine) then
    Exit;
  if DoLoadArtifactLine(ALine) then
    Exit;
  if DoLoadModuleLine(ALine) then
    Exit;
  if DoLoadSourceLine(ALine, ATURoot) then
    Exit;

  // Not a line GenerateBuildZig writes, or a payload it cannot read: said,
  // skipped, the rest loads
  if Assigned(FErrors) then
    FErrors.Add(esWarning, PC_ERR_ZIGBUILD_WRNBUILDLINE, RSZigBuildUnknownLine,
      [ALineNo, AFilename, ALine]);
end;

function TPCZigBuild.DoLoadHeaderLine(const ALine: string): Boolean;
var
  LPayload: string;
  LParts: TArray<string>;
  LTarget: string;
  LLevel: TPCOptimizeLevel;
begin
  Result := False;

  // '.cpu_arch = .<arch>, .os_tag = .<os>[, .abi = .<abi>]' (DoZigTargetQuery)
  if DoFormPayload(ALine, PC_ZIG_FORM_TARGET_PRE, PC_ZIG_FORM_TARGET_SUF, LPayload) then
  begin
    LParts := LPayload.Split([', ']);
    if (Length(LParts) < 2) or (Length(LParts) > 3) or
      (not LParts[0].StartsWith('.cpu_arch = .')) or
      (not LParts[1].StartsWith('.os_tag = .')) or
      ((Length(LParts) = 3) and (not LParts[2].StartsWith('.abi = .'))) then
      Exit;
    LTarget := DoZigEnumValue(LParts[0].Substring(13)) + '-' +
      DoZigEnumValue(LParts[1].Substring(11));
    if Length(LParts) = 3 then
      LTarget := LTarget + '-' + DoZigEnumValue(LParts[2].Substring(8));
    // A triple that is not zig's is reported by SetTarget and not stored
    SetTarget(LTarget);
    Exit(True);
  end;

  // The optimize line: the inverse of DoOptimizeName
  if DoFormPayload(ALine, PC_ZIG_FORM_OPTIMIZE_PRE, ';', LPayload) then
  begin
    for LLevel := Low(TPCOptimizeLevel) to High(TPCOptimizeLevel) do
    begin
      if DoOptimizeName(LLevel) = LPayload then
      begin
        FOptimizeLevel := LLevel;
        Exit(True);
      end;
    end;
  end;
end;

function TPCZigBuild.DoLoadArtifactLine(const ALine: string): Boolean;
var
  LPayload: string;
  LText: string;
begin
  Result := True;
  if ALine = PC_ZIG_FORM_EXE then
    FBuildMode := bmExe
  else if ALine = PC_ZIG_FORM_LIB then
    FBuildMode := bmLib
  else if ALine = PC_ZIG_FORM_LINKAGE_PRE + '.static,' then
    FBuildMode := bmLib
  else if ALine = PC_ZIG_FORM_LINKAGE_PRE + '.dynamic,' then
    FBuildMode := bmDll
  else if ALine = PC_ZIG_FORM_SUBSYSTEM then
    FSubsystem := stGUI
  else if DoFormPayload(ALine, PC_ZIG_FORM_NAME_PRE, ',', LPayload) and
    ZigStringValue(LPayload, LText) then
    // A name no file can take is reported by SetProjectName
    SetProjectName(LText)
  else
    Result := False;
end;

function TPCZigBuild.DoLoadModuleLine(const ALine: string): Boolean;
var
  LRest: string;
  LPayload: string;
  LText: string;
begin
  // '<exe|lib>.root_module....'
  Result := False;
  if not (ALine.StartsWith('exe.') or ALine.StartsWith('lib.')) then
    Exit;
  LRest := ALine.Substring(4);

  Result := True;
  if DoFormPayload(LRest, PC_ZIG_FORM_INCLUDE_PRE, PC_ZIG_FORM_LAZY_SUF, LPayload) and
    ZigStringValue(LPayload, LText) then
    DoAddPath(FIncludePaths, LText, FOutputPath, RSZigBuildWhatIncludePath)
  else if DoFormPayload(LRest, PC_ZIG_FORM_LIBPATH_PRE, PC_ZIG_FORM_LAZY_SUF, LPayload) and
    ZigStringValue(LPayload, LText) then
    DoAddPath(FLibraryPaths, LText, FOutputPath, RSZigBuildWhatLibraryPath)
  else if DoFormPayload(LRest, PC_ZIG_FORM_LINKLIB_PRE, PC_ZIG_FORM_LINKLIB_SUF, LPayload) and
    ZigStringValue(LPayload, LText) then
    AddLinkLibrary(LText)
  // A Linux link library handed over as its file: the name it stands for is the state
  // (GenerateBuildZig finds the file again), the path only has to be a valid literal
  else if not DoLoadLinkFileLine(LRest) then
    Result := False;
end;

function TPCZigBuild.DoLoadLinkFileLine(const ARest: string): Boolean;
var
  LPos: Integer;
  LPath: string;
  LName: string;
begin
  // 'root_module.addObjectFile(.{ .cwd_relative = "<path>" }); // pcpp linklibrary "<name>"'
  // The marker is searched from the end: a path literal cannot hold it, the name follows it.
  Result := False;
  if not ARest.StartsWith(PC_ZIG_FORM_LINKFILE_PRE) then
    Exit;
  LPos := ARest.LastIndexOf(PC_ZIG_FORM_LINKFILE_MID);
  if LPos < Length(PC_ZIG_FORM_LINKFILE_PRE) then
    Exit;
  if not ZigStringValue(ARest.Substring(Length(PC_ZIG_FORM_LINKFILE_PRE),
    LPos - Length(PC_ZIG_FORM_LINKFILE_PRE)), LPath) then
    Exit;
  if not ZigStringValue(ARest.Substring(LPos + Length(PC_ZIG_FORM_LINKFILE_MID)), LName) then
    Exit;
  if LName = '' then
    Exit;
  AddLinkLibrary(LName);
  Result := True;
end;

function TPCZigBuild.DoLoadSourceLine(const ALine: string; var ATURoot: string): Boolean;
var
  LPayload: string;
  LText: string;
  LResolved: string;
begin
  Result := True;

  // A TU's folder: its file name follows. A folder no path can take is
  // reported, and its file is dropped with it.
  if DoFormPayload(ALine, PC_ZIG_FORM_ROOT_PRE, PC_ZIG_FORM_ROOT_SUF, LPayload) and
    ZigStringValue(LPayload, LText) then
  begin
    if DoAcceptPath(LText, FOutputPath, RSZigBuildWhatSourceFile, LResolved) then
      ATURoot := LResolved
    else
      ATURoot := '';
    Exit;
  end;

  if DoFormPayload(ALine, PC_ZIG_FORM_FLAGS_PRE, PC_ZIG_FORM_FLAGS_SUF, LPayload) and
    ParseFlagsLine(LPayload) then
    Exit;

  // A TU's file: one string literal on its own line
  if ALine.StartsWith('"') and ZigStringValue(ALine, LText) then
  begin
    if ATURoot <> '' then
      DoAddSourcePath(LText, ATURoot);
    Exit;
  end;

  Result := False;
end;

// Persistence

function TPCZigBuild.LoadBuildFile(const AFilename: string): Boolean;
var
  LLines: TStringList;
  LI: Integer;
  LFilename: string;
  LRoot: string;
  LTURoot: string;
begin
  Result := False;

  // The build file's own path is accepted like any path setting; a relative
  // path inside it resolves against its directory, the build root
  if not DoAcceptPath(AFilename, '', RSZigBuildWhatBuildFile, LFilename) then
    Exit;

  if not TFile.Exists(LFilename) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_LOADFAILED, RSZigBuildFileNotFound,
        [LFilename]);
    Exit;
  end;

  // The build root is the build file's directory: zig cannot build in a
  // longer one, so the file is refused before anything is cleared
  LRoot := TPath.GetDirectoryName(LFilename);
  if not DoCheckBuildRoot(LRoot) then
    Exit;

  // Clear existing data and set the output path from the file location
  Clear();
  FOutputPath := LRoot;

  LLines := TStringList.Create();
  try
    try
      // UTF-8, as SaveBuildFile writes it (a name or define may be any text)
      LLines.Text := TFile.ReadAllText(LFilename, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        if Assigned(FErrors) then
          FErrors.Add(esError, PC_ERR_ZIGBUILD_LOADFAILED,
            RSZigBuildLoadFailed, [LFilename, E.Message]);
        Exit;
      end;
    end;

    // Each line whole, in order: a TU's .root line comes before its file
    LTURoot := FOutputPath;
    for LI := 0 to LLines.Count - 1 do
      DoLoadLine(LLines[LI].Trim(), LI + 1, LFilename, LTURoot);

    Result := not FProjectName.IsEmpty;
  finally
    LLines.Free();
  end;
end;

function TPCZigBuild.SaveBuildFile(): Boolean;
var
  LBuildZigPath: string;
  LContent: string;
  LUTF8NoBOM: TEncoding;
begin
  Result := False;

  if FOutputPath = '' then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_NOOUTPUTPATH, RSZigBuildNoOutputPath);
    Exit;
  end;

  if FSourceFiles.Count = 0 then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_NOSOURCES, RSZigBuildNoSources);
    Exit;
  end;

  // Generate build.zig; its directory is created inside the guarded write,
  // so a directory that cannot be created is reported like a failed write
  LBuildZigPath := TUtils.JoinResolvedPath(FOutputPath, 'build.zig');
  LContent := GenerateBuildZig();

  // Write without a BOM - Zig does not accept a BOM in source files
  LUTF8NoBOM := TUTF8Encoding.Create(False);
  try
    try
      TUtils.CreateDirInPath(LBuildZigPath);
      TFile.WriteAllText(LBuildZigPath, LContent, LUTF8NoBOM);
      Result := True;
    except
      on E: Exception do
      begin
        if Assigned(FErrors) then
          FErrors.Add(esError, PC_ERR_ZIGBUILD_SAVEFAILED, RSZigBuildSaveFailed,
            [E.Message]);
      end;
    end;
  finally
    LUTF8NoBOM.Free();
  end;
end;

// Invocation

function TPCZigBuild.Process(const AAutoRun: Boolean): Boolean;
var
  LZigExe: string;
  LZigArgs: string;
  LOutputFile: string;
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  Result := False;

  // Status: target, optimize, and (Windows only) subsystem
  Status(RSZigBuildTargetPlatform, [GetTargetDisplayName()]);
  Status(RSZigBuildOptimizeLevel, [GetOptimizeLevelDisplayName()]);
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(PC_DEFAULT_TARGET, LArch, LOS, LAbi);
  if SameText(LOS, OS_WINDOWS) then
    Status(RSZigBuildSubsystem, [GetSubsystemDisplayName()]);

  // Always save the build file first
  Status(RSZigBuildSaving);
  if not SaveBuildFile() then
    Exit;

  // Locate the zig executable
  LZigExe := GetZigPath('zig.exe');
  if (LZigExe = '') or (not TFile.Exists(LZigExe)) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_ZIGNOTFOUND, RSZigBuildZigNotFound,
        [TUtils.StripLongPathPrefix(LZigExe)]);
    Exit;
  end;

  // No colour is forced: the build is captured over plain pipes and parsed
  // (see Build diagnostics filter); the caller prints FErrors itself. The
  // cache folder is text for zig: its plain spelling
  TUtils.SetEnv('ZIG_GLOBAL_CACHE_DIR', TUtils.StripLongPathPrefix(
    TUtils.JoinResolvedPath(GetZigPath(), PC_ZIG_GLOBAL_CACHE_DIR)));

  // Copy DLLs (DoDeployCopyDLLs): always run, also with none requested, since
  // a copy an earlier build made may be stale; a deployment that cannot be
  // completed stops here, and the build is not run (R16)
  if not DoDeployCopyDLLs() then
    Exit;

  // Run zig build over plain pipes. With no terminal attached zig prints no
  // progress tree or escape codes, and CaptureConsoleOutput hands over one
  // complete, UTF-8 decoded line per callback.
  // Fresh per-TU diagnostics files: a build that cannot start from them is
  // not run, since a stale file would report another build's diagnostics
  if not DoDiagFilePrepare() then
    Exit;

  // -p: zig installs straight into the build root (<root>\bin, <root>\lib:
  // the layout rule, DoArtifactSubdir), never into its default zig-out. The
  // path is text for zig: its plain spelling, quoted when it must be
  LZigArgs := 'build --color off --summary none -p ' +
    TUtils.QuoteCommandArg(TUtils.StripLongPathPrefix(FOutputPath));

  Status(RSZigBuildBuilding, [FProjectName]);
  FBuildOutput.Init(FOutputPath);
  try
    // zig prints no progress over pipes: with a progress callback the pipe is
    // polled and the callback hears the elapsed time every PC_ZIG_PROGRESS_MS
    // while zig is quiet (a build for a new target can be silent for minutes)
    if FProgress.IsAssigned() then
      TUtils.CaptureConsoleOutput(
        '',
        PChar(LZigExe),
        PChar(LZigArgs),
        FOutputPath,
        FLastExitCode,
        nil,
        HandleOutputLine,
        False,
        PC_ZIG_PROGRESS_MS,
        procedure(const AElapsedMs: UInt64; const AUserData: Pointer)
        begin
          FProgress.Callback(AElapsedMs, FProgress.UserData);
        end
      )
    else
      TUtils.CaptureConsoleOutput(
        '',
        PChar(LZigExe),
        PChar(LZigArgs),
        FOutputPath,
        FLastExitCode,
        nil,
        HandleOutputLine
      );
  except
    on E: Exception do
    begin
      if Assigned(FErrors) then
        FErrors.Add(esError, PC_ERR_ZIGBUILD_ZIGSTART, RSZigBuildZigStartFailed,
          [TUtils.StripLongPathPrefix(LZigExe), E.Message]);
      Exit;
    end;
  end;
  DoFilterFlush();

  if FLastExitCode <> 0 then
  begin
    Status(RSZigBuildFailedWithCode, [FLastExitCode]);

    // The generic failure only when no reported error already says why
    if Assigned(FErrors) and (FBuildErrors = 0) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_BUILDFAILED, RSZigBuildFailed,
        [FLastExitCode]);
    Exit;
  end;

  Status(RSZigBuildSucceeded);

  // The built artifact, where the layout rule puts it (DoArtifactPath), in
  // ResolvePath's spelling: stamps and publish reach it at any
  // length (R41)
  LOutputFile := DoArtifactPath();
  Status(RSZigBuildOutput, [TUtils.NormalizePath(LOutputFile)]);

  // Apply post-build resources (manifest, icon, version info). A requested
  // stamp that failed is an error: stop before anything is published
  if not ApplyPostBuildResources(LOutputFile) then
    Exit;

  // Publish finished output. AFTER the artifact is stamped, so a published
  // copy always carries its version info.
  if FPublishItems.Count > 0 then
  begin
    if not DoPostBuildCopies(LOutputFile) then
      Exit;
  end;

  if AAutoRun then
    Result := Run()
  else
    Result := True;
end;

function TPCZigBuild.Run(): Boolean;
var
  LExeFile: string;
  LExePath: string;
  LWorkDir: string;
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  Result := False;

  // Only executables can be run
  if FBuildMode <> bmExe then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_RUNNOTEXE, RSZigBuildCannotRunLib);
    Exit;
  end;

  // Only Windows and Linux hosts can be launched here
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(PC_DEFAULT_TARGET, LArch, LOS, LAbi);
  if not (SameText(LOS, OS_WINDOWS) or SameText(LOS, OS_LINUX)) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esWarning, PC_ERR_ZIGBUILD_WRNCANNOTRUN, RSZigBuildCannotRunCross,
        [GetTargetDisplayName()]);
    Result := True;
    Exit;
  end;

  // Validate the project name
  if FProjectName = '' then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_NOPROJECTNAME, RSZigBuildNoProjectName);
    Exit;
  end;

  // The executable lies under the build root: there is none without an
  // output path (a bare name would be looked up in the current directory)
  if FOutputPath = '' then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_NOOUTPUTPATH, RSZigBuildNoOutputPath);
    Exit;
  end;

  // Checked in ResolvePath's spelling (R41); launched and named in its plain
  // spelling (the capture routines launch a path of any length, A5). The
  // program runs in its own folder.
  LExeFile := DoArtifactPath();
  LExePath := TUtils.StripLongPathPrefix(LExeFile);
  LWorkDir := TUtils.StripLongPathPrefix(DoArtifactDir(FBuildMode));

  if not TFile.Exists(LExeFile) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_EXENOTFOUND, RSZigBuildExeNotFound,
        [LExePath]);
    Exit;
  end;

  // Run and capture output
  Status(RSZigBuildRunning, [GetOutputFilename()]);

  // A program that cannot start is reported with the reason (the OS, WSL,
  // chmod), never a made-up exit code. A Linux target runs through WSL with
  // its arguments as the program's literal argv, never through a shell
  // (R26 R34 R35, R18 G4)
  try
    // The keyboard and terminal size come from FRunHost (both targets: a
    // Linux program's pseudoconsole is wsl's)
    if SameText(LOS, OS_LINUX) then
      TUtils.RunElf(LExePath, FRunArguments, LWorkDir, FLastExitCode, nil,
        HandleRunOutputLine, False, FRunHost)
    else
      TUtils.RunPE(LExePath, FRunArguments, LWorkDir, FLastExitCode, nil,
        HandleRunOutputLine, False, FRunHost);
  except
    on E: Exception do
    begin
      if Assigned(FErrors) then
        FErrors.Add(esError, PC_ERR_ZIGBUILD_RUNSTART, RSZigBuildRunStartFailed,
          [LExePath, E.Message]);
      Exit;
    end;
  end;

  if FLastExitCode <> 0 then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_RUNEXIT, RSZigBuildRunFailed,
        [FLastExitCode]);
    Exit;
  end;

  Result := True;
end;

function TPCZigBuild.DoClearBuildDir(const AName: string): Boolean;
var
  LPath: string;
  LReason: string;
  LAttr: Integer;
begin
  Result := False;

  // Without an output path there is no build root: nothing is deleted (a
  // bare name would be a folder in the current directory)
  if FOutputPath = '' then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_NOOUTPUTPATH, RSZigBuildNoOutputPath);
    Exit;
  end;
  LPath := TUtils.JoinResolvedPath(FOutputPath, AName);

  // The entry's own attributes (FollowLink False): a junction or symbolic
  // link is never entered, since TDirectory.Delete walks into one and
  // empties the folder it points at; the link itself stays too (it is not
  // a folder this driver wrote). Absent, or a file in its place: nothing to
  // delete. A recursive delete can leave the directory behind (a locked
  // file): the result is whether it is gone
  LReason := RSZigBuildClearStillPresent;
  try
    LAttr := FileGetAttr(LPath, False);
    if (LAttr <> faInvalid) and ((LAttr and System.SysUtils.faSymLink) <> 0) then
      LReason := RSZigBuildClearLink
    else
    begin
      if (LAttr <> faInvalid) and ((LAttr and System.SysUtils.faDirectory) <> 0) then
        DoDeleteTree(LPath);
      Result := not TDirectory.Exists(LPath, False);
    end;
  except
    on E: Exception do
      LReason := E.Message;
  end;

  if (not Result) and Assigned(FErrors) then
    FErrors.Add(esError, PC_ERR_ZIGBUILD_CLEARFAILED, RSZigBuildClearFailed,
      [LPath, LReason]);
end;

procedure TPCZigBuild.DoDeleteTree(const ADir: string);
var
  LSearch: TSearchRec;
  LEntry: string;
  LIsDir: Boolean;
  LIsLink: Boolean;
  LKeep: Integer;
begin
  // Children first, then ADir (empty by then unless something stayed).
  // SearchRec.Attr holds the entry's own attributes: a junction or a
  // directory symbolic link is faDirectory + faSymLink and is removed with
  // RemoveDir, which deletes the link and never its target; a file symbolic
  // link is removed with DeleteFile, the link alone as well
  if FindFirst(TUtils.JoinResolvedPath(ADir, '*'), System.SysUtils.faAnyFile,
    LSearch) = 0 then
  begin
    try
      repeat
        if (LSearch.Name = '.') or (LSearch.Name = '..') then
          Continue;
        LEntry := TUtils.JoinResolvedPath(ADir, LSearch.Name);
        LIsDir := (LSearch.Attr and System.SysUtils.faDirectory) <> 0;
        LIsLink := (LSearch.Attr and System.SysUtils.faSymLink) <> 0;

        // A read-only entry refuses deletion: clear that bit on the entry
        // itself (FollowLink False: a link's target is not changed), keeping
        // only the bits SetFileAttributes takes
        if (LSearch.Attr and System.SysUtils.faReadOnly) <> 0 then
        begin
          LKeep := LSearch.Attr and (System.SysUtils.faHidden or
            System.SysUtils.faSysFile or System.SysUtils.faArchive);
          if LKeep = 0 then
            LKeep := System.SysUtils.faNormal;
          FileSetAttr(LEntry, LKeep, False);
        end;

        if LIsDir and (not LIsLink) then
          DoDeleteTree(LEntry)
        else if LIsDir then
          RemoveDir(LEntry)
        else
          System.SysUtils.DeleteFile(LEntry);
      until FindNext(LSearch) <> 0;
    finally
      FindClose(LSearch);
    end;
  end;
  RemoveDir(ADir);
end;

function TPCZigBuild.DoClearBuildFile(const AName: string): Boolean;
var
  LPath: string;
  LReason: string;
begin
  Result := False;

  // Without an output path there is no build root (as DoClearBuildDir)
  if FOutputPath = '' then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_NOOUTPUTPATH, RSZigBuildNoOutputPath);
    Exit;
  end;
  LPath := TUtils.JoinResolvedPath(FOutputPath, AName);

  // The result is whether the file is gone (a locked file stays)
  LReason := RSZigBuildClearFileStillPresent;
  try
    if TFile.Exists(LPath) then
      TFile.Delete(LPath);
    Result := not TFile.Exists(LPath);
  except
    on E: Exception do
      LReason := E.Message;
  end;

  if (not Result) and Assigned(FErrors) then
    FErrors.Add(esError, PC_ERR_ZIGBUILD_CLEARFAILED, RSZigBuildClearFailed,
      [LPath, LReason]);
end;

function TPCZigBuild.ClearCache(): Boolean;
begin
  Result := DoClearBuildDir('.zig-cache');
end;

function TPCZigBuild.ClearOutput(): Boolean;
var
  LBinCleared: Boolean;
  LLibCleared: Boolean;
  LCacheCleared: Boolean;
  LDiagCleared: Boolean;
  LRecordCleared: Boolean;
begin
  // Everything zig and this driver write into the build root: the artifact
  // folders (the layout rule), the project's own zig cache and the copy-DLL
  // record, which describes bin's contents. Each is cleared even when an
  // earlier one fails (each failure reports itself). The Compiler clears
  // what it writes (generated) before it calls this.
  // No output path: one report (ZB0001), nothing deleted
  if FOutputPath = '' then
  begin
    Result := DoClearBuildDir(DoArtifactSubdir(bmExe));
    Exit;
  end;
  LBinCleared := DoClearBuildDir(DoArtifactSubdir(bmExe));
  LLibCleared := DoClearBuildDir(DoArtifactSubdir(bmLib));
  LCacheCleared := ClearCache();
  // clang's .dia files: every build checks the folder and deletes the old
  // ones before zig runs, so nothing depends on them surviving a clear
  LDiagCleared := DoClearBuildDir(PC_DIAG_FILE_DIR);
  LRecordCleared := DoClearBuildFile(PC_ZIG_COPYDLL_RECORD);
  Result := LBinCleared and LLibCleared and LCacheCleared and LDiagCleared and
    LRecordCleared;
end;

function TPCZigBuild.ClearBuildDir(const AName: string): Boolean;
begin
  Result := DoClearBuildDir(AName);
end;

function TPCZigBuild.GetClearNames(): TArray<string>;
begin
  // ClearOutput's own names, in its order: one list, so what is shown is
  // what is deleted
  Result := [DoArtifactSubdir(bmExe), DoArtifactSubdir(bmLib), '.zig-cache',
    PC_DIAG_FILE_DIR, PC_ZIG_COPYDLL_RECORD];
end;

// Post-build resources

function TPCZigBuild.ApplyPostBuildResources(const AArtifactPath: string): Boolean;
begin
  Result := True;

  // PE resources exist only on Windows: a request for another target is
  // ignored and said so, never silently dropped
  if not DoIsWindowsTarget() then
  begin
    if Assigned(FErrors) then
    begin
      if FExeIcon <> '' then
        FErrors.Add(esWarning, PC_ERR_ZIGBUILD_WRNNOTAPPLICABLE,
          RSZigBuildIconNotWindows, [GetTargetDisplayName()]);
      if FAddVersionInfo then
        FErrors.Add(esWarning, PC_ERR_ZIGBUILD_WRNNOTAPPLICABLE,
          RSZigBuildVersionInfoNotWindows, [GetTargetDisplayName()]);
    end;
    Exit;
  end;

  // Manifest: executables only (the compiler's own, not a user request)
  if FBuildMode = bmExe then
    DoApplyManifest(AArtifactPath);

  // Icon: executables only
  if FExeIcon <> '' then
  begin
    if FBuildMode <> bmExe then
    begin
      if Assigned(FErrors) then
        FErrors.Add(esWarning, PC_ERR_ZIGBUILD_WRNNOTAPPLICABLE,
          RSZigBuildIconNotExe);
    end
    else if not DoApplyIcon(AArtifactPath) then
      Exit(False);
  end;

  // Version info: executables and DLLs; a static library takes none
  if FAddVersionInfo then
  begin
    if FBuildMode = bmLib then
    begin
      if Assigned(FErrors) then
        FErrors.Add(esWarning, PC_ERR_ZIGBUILD_WRNNOTAPPLICABLE,
          RSZigBuildVersionInfoNotLib);
    end
    else if not DoApplyVersionInfo(AArtifactPath) then
      Exit(False);
  end;
end;

function TPCZigBuild.DoIsWindowsTarget(): Boolean;
var
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  // Same resolution as GetExeExtension: an unparseable target is the default
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(PC_DEFAULT_TARGET, LArch, LOS, LAbi);
  Result := SameText(LOS, OS_WINDOWS);
end;

function TPCZigBuild.DoIsLinuxTarget(): Boolean;
var
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  // Same resolution as DoIsWindowsTarget: an unparseable target is the default
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(PC_DEFAULT_TARGET, LArch, LOS, LAbi);
  Result := SameText(LOS, OS_LINUX);
end;

function TPCZigBuild.DoFindLinkFile(const ALibrary: string; out APath: string): Boolean;
var
  LI: Integer;
  LExt: Integer;
  LCandidate: string;
begin
  // The linker's own search for -l<name>: each library path in order, a shared library
  // before a static one in the same folder (zig's paths_first). FLibraryPaths are stored
  // resolved, so JoinResolvedPath joins without touching the file system; FileExists
  // reports by result and never raises.
  Result := False;
  APath := '';
  for LI := 0 to FLibraryPaths.Count - 1 do
    for LExt := Low(PC_ZIG_LINK_FILE_EXTS) to High(PC_ZIG_LINK_FILE_EXTS) do
    begin
      LCandidate := TUtils.JoinResolvedPath(FLibraryPaths[LI],
        'lib' + ALibrary + PC_ZIG_LINK_FILE_EXTS[LExt]);
      if FileExists(LCandidate) then
      begin
        APath := LCandidate;
        Exit(True);
      end;
    end;
end;

procedure TPCZigBuild.DoApplyManifest(const AExePath: string);
var
  LErrorMessage: string;
begin
  // The compiler's own EXE_MANIFEST, when it carries one. Not a user request,
  // so a failure is a warning; AddResManifestFromResource never raises
  if not TUtils.ResourceExist('EXE_MANIFEST') then
    Exit;
  if not TUtils.AddResManifestFromResource('EXE_MANIFEST', AExePath,
    LErrorMessage) then
    if Assigned(FErrors) then
      FErrors.Add(esWarning, PC_ERR_ZIGBUILD_WRNMANIFEST,
        RSZigBuildManifestFailed, [LErrorMessage]);
end;

function TPCZigBuild.DoApplyIcon(const AExePath: string): Boolean;
var
  LExists: Boolean;
  LFailed: Boolean;
  LErrorMessage: string;
begin
  // Every raise is caught here and reported after the try, so an error sink
  // set to raise is never caught by this routine's own except
  Result := False;
  LExists := False;
  LFailed := False;
  LErrorMessage := '';
  try
    LExists := TFile.Exists(FExeIcon);
    if LExists then
      TUtils.UpdateIconResource(AExePath, FExeIcon);
  except
    on E: Exception do
    begin
      LFailed := True;
      LErrorMessage := E.Message;
    end;
  end;

  if LFailed then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_ICON, RSZigBuildIconFailed,
        [FExeIcon, LErrorMessage]);
    Exit;
  end;

  if not LExists then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_ICON, RSZigBuildIconNotFound,
        [FExeIcon]);
    Exit;
  end;

  Result := True;
end;

function TPCZigBuild.DoApplyVersionInfo(const AArtifactPath: string): Boolean;
var
  LFailed: Boolean;
  LErrorMessage: string;
begin
  // Same shape as DoApplyIcon: catch, then report outside the try
  Result := False;
  LFailed := False;
  LErrorMessage := '';
  try
    TUtils.UpdateVersionInfoResource(AArtifactPath,
      FVIMajor, FVIMinor, FVIPatch, FVIProductName,
      FVIDescription, FVIFilename, FVICompanyName, FVICopyright);
  except
    on E: Exception do
    begin
      LFailed := True;
      LErrorMessage := E.Message;
    end;
  end;

  if LFailed then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, PC_ERR_ZIGBUILD_VERSIONINFO,
        RSZigBuildVersionInfoFailed, [LErrorMessage]);
    Exit;
  end;

  Result := True;
end;

// Version info / post-build resources

procedure TPCZigBuild.SetAddVersionInfo(const AValue: Boolean);
begin
  FAddVersionInfo := AValue;
end;

function TPCZigBuild.GetAddVersionInfo(): Boolean;
begin
  Result := FAddVersionInfo;
end;

procedure TPCZigBuild.SetVIMajor(const AValue: Word);
begin
  FVIMajor := AValue;
end;

function TPCZigBuild.GetVIMajor(): Word;
begin
  Result := FVIMajor;
end;

procedure TPCZigBuild.SetVIMinor(const AValue: Word);
begin
  FVIMinor := AValue;
end;

function TPCZigBuild.GetVIMinor(): Word;
begin
  Result := FVIMinor;
end;

procedure TPCZigBuild.SetVIPatch(const AValue: Word);
begin
  FVIPatch := AValue;
end;

function TPCZigBuild.GetVIPatch(): Word;
begin
  Result := FVIPatch;
end;

procedure TPCZigBuild.SetVIProductName(const AValue: string);
begin
  FVIProductName := AValue;
end;

function TPCZigBuild.GetVIProductName(): string;
begin
  Result := FVIProductName;
end;

procedure TPCZigBuild.SetVIDescription(const AValue: string);
begin
  FVIDescription := AValue;
end;

function TPCZigBuild.GetVIDescription(): string;
begin
  Result := FVIDescription;
end;

procedure TPCZigBuild.SetVIFilename(const AValue: string);
begin
  FVIFilename := AValue;
end;

function TPCZigBuild.GetVIFilename(): string;
begin
  Result := FVIFilename;
end;

procedure TPCZigBuild.SetVICompanyName(const AValue: string);
begin
  FVICompanyName := AValue;
end;

function TPCZigBuild.GetVICompanyName(): string;
begin
  Result := FVICompanyName;
end;

procedure TPCZigBuild.SetVICopyright(const AValue: string);
begin
  FVICopyright := AValue;
end;

function TPCZigBuild.GetVICopyright(): string;
begin
  Result := FVICopyright;
end;

procedure TPCZigBuild.SetExeIcon(const AValue: string);
var
  LPath: string;
begin
  // Stored resolved; empty clears the request
  if DoAcceptPath(AValue, '', RSZigBuildWhatExeIcon, LPath) then
    FExeIcon := LPath;
end;

function TPCZigBuild.GetExeIcon(): string;
begin
  Result := FExeIcon;
end;

// Toolchain paths

procedure TPCZigBuild.SetBuildConfigPath(const APath: string);
var
  LPath: string;
begin
  // A path no file routine can take is ZB0020 and is not stored. The next
  // use reads the new location
  if not DoAcceptPath(APath, '', RSZigBuildWhatBuildConfig, LPath) then
    Exit;
  FBuildConfigPath := LPath;
  FConfigLoaded := False;
  FConfigReadable := True;
end;

function TPCZigBuild.GetBuildConfigPath(): string;
begin
  Result := FBuildConfigPath;
end;

procedure TPCZigBuild.DoConfigLoad();
var
  LRaw: string;
begin
  // Once per location; marked first so the template save below cannot
  // come back here
  if FConfigLoaded then
    Exit;
  FConfigLoaded := True;
  FConfigReadable := True;
  FBuildConfig.Clear();
  FToolchainPath := DoResolveToolchainPath('');

  // No location (Create could not resolve one): the default, nothing saved
  if FBuildConfigPath = '' then
  begin
    FConfigReadable := False;
    Exit;
  end;

  // Absent: written once with the default, as a template to edit
  if not FileExists(FBuildConfigPath) then
  begin
    FBuildConfig.SetString('build.toolchain_path', PC_DEFAULT_TOOLCHAIN_PATH);
    DoConfigSave();
    Exit;
  end;

  // Unreadable: the user's file, left alone (never overwritten)
  if not FBuildConfig.LoadFromFile(FBuildConfigPath) then
  begin
    FConfigReadable := False;
    DoConfigWarning(RSZigBuildConfigLoadFailed,
      [FBuildConfigPath, FBuildConfig.GetLastError()]);
    Exit;
  end;

  // A toolchain_path no file routine can take is warned about and the
  // default used, never a raise (R18 G3: it raised out of Create)
  LRaw := FBuildConfig.GetString('build.toolchain_path', '');
  try
    FToolchainPath := DoResolveToolchainPath(LRaw);
  except
    on E: Exception do
      DoConfigWarning(RSZigBuildConfigBadToolchain,
        [FBuildConfigPath, LRaw, E.Message]);
  end;
end;

procedure TPCZigBuild.SetToolchainPath(const APath: string);
var
  LRaw: string;
  LPath: string;
begin
  // The file is read first: its state decides whether it may be saved, and
  // a later first use must not overwrite the value set here
  DoConfigLoad();

  // A path no file routine can take is an error: nothing changes and
  // nothing is saved. Empty means the default.
  LRaw := APath;
  if LRaw.Trim() = '' then
    LRaw := PC_DEFAULT_TOOLCHAIN_PATH;
  if not DoAcceptPath(LRaw, '', RSZigBuildWhatToolchainPath, LPath) then
    Exit;
  FToolchainPath := LPath;

  // Persist the raw value (empty or user-provided): a '$P:' path stays valid
  // when the executable moves, and empty reads back as the default
  FBuildConfig.SetString('build.toolchain_path', APath);
  DoConfigSave();
end;

function TPCZigBuild.DoResolveToolchainPath(const ARaw: string): string;
begin
  // Empty means the default, here and when build.toml is read back
  if ARaw.Trim() = '' then
    Result := TUtils.ResolvePath(PC_DEFAULT_TOOLCHAIN_PATH)
  else
    Result := TUtils.ResolvePath(ARaw);
end;

procedure TPCZigBuild.DoConfigSave();
begin
  // An existing build.toml that could not be read is the user's: left as is
  if not FConfigReadable then
  begin
    DoConfigWarning(RSZigBuildConfigNotSaved, [FBuildConfigPath]);
    Exit;
  end;

  if not FBuildConfig.SaveToFile(FBuildConfigPath) then
    DoConfigWarning(RSZigBuildConfigSaveFailed,
      [FBuildConfigPath, FBuildConfig.GetLastError()]);
end;

procedure TPCZigBuild.DoConfigWarning(const AMessage: string;
  const AArgs: array of const);
begin
  // Before SetErrors there is nowhere to report: held for SetErrors
  if Assigned(FErrors) then
    FErrors.Add(esWarning, PC_ERR_ZIGBUILD_WRNCONFIG, AMessage, AArgs)
  else
    FConfigPending.Add(Format(AMessage, AArgs));
end;

procedure TPCZigBuild.SetErrors(const AErrors: TErrors);
var
  LI: Integer;
begin
  inherited;

  FBuildConfig.SetErrors(AErrors);

  // The warnings Create raised before any error sink was wired; the
  // message is already formatted
  if not Assigned(FErrors) then
    Exit;
  for LI := 0 to FConfigPending.Count - 1 do
    FErrors.Add(esWarning, PC_ERR_ZIGBUILD_WRNCONFIG, FConfigPending[LI]);
  FConfigPending.Clear();
end;

function TPCZigBuild.GetToolchainPath(): string;
begin
  DoConfigLoad();
  Result := FToolchainPath;
end;

// The toolchain folders, joined under the resolved toolchain path in
// ResolvePath's spelling: a file past the plain limit is found there (R43:
// a long zig.exe was "not found") and launched (A5)

function TPCZigBuild.GetZigPath(const AFilename: string): string;
begin
  Result := TUtils.JoinResolvedPath(GetToolchainPath(), 'zig');
  if AFilename <> '' then
    Result := TUtils.JoinResolvedPath(Result, AFilename);
end;

function TPCZigBuild.GetRuntimePath(const AFilename: string): string;
begin
  Result := TUtils.JoinResolvedPath(GetToolchainPath(), 'runtime');
  if AFilename <> '' then
    Result := TUtils.JoinResolvedPath(Result, AFilename);
end;

function TPCZigBuild.GetLibsPath(const AFilename: string): string;
begin
  Result := TUtils.JoinResolvedPath(GetToolchainPath(), 'libs');
  if AFilename <> '' then
    Result := TUtils.JoinResolvedPath(Result, AFilename);
end;

function TPCZigBuild.GetAssetsPath(const AFilename: string): string;
begin
  Result := TUtils.JoinResolvedPath(GetToolchainPath(), 'assets');
  if AFilename <> '' then
    Result := TUtils.JoinResolvedPath(Result, AFilename);
end;

end.
