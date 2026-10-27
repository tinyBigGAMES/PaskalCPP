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
  PaskalCPP.TestSuite - TPCTestSuite, the one class that finds, runs and
  reports every test

  Two kinds of test, one suite. A .pcpp test describes itself in its spec
  (TestSuite.Spec); AddSourceRoot names a folder whose .pcpp files are
  scanned. A Delphi code test is a TPCTestCase class (TestSuite.CodeTest);
  RegisterCase takes it. Every test is an item <area>.<name> with a kind,
  the cells it runs in and its dependencies; one result per (item, cell).

  Discover finds every item and checks the whole set at once: stems unique,
  ids unique, every dependency a test that builds, no cycle, every cell a
  consumer runs in one its dependencies build in, every dep test used.
  Run takes a TPCTestFilter (ids / globs, -from / -to, targets, optimize
  levels, subsystems, kinds, the last run's failures), builds each selected
  cell's dependencies in graph order (in that cell, never tallied), runs the
  cell, prints its result and, at the end, the matrix of cells and every
  failing cell; the results file in the output folder feeds -failed.
  RunCommandLine is the CLI (testbed.exe): exit 0 = every selected cell
  passed, 1 = a failure (or a discovery error), 2 = bad arguments,
  3 = stopped (TestSuite.Stop: Ctrl+Shift+Alt+X or the stop file).

  A source cell: TPCCompiler with the cell as defaults (the file's own
  directive wins, and is then reported: the cell must say what ran),
  Prepare + Build (a unit: Analyze), the reports against the markers of
  every file the build read, then for run / tests the program on the
  cell's target (Linux through WSL; no WSL = skip with the reason).

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Console,
    StdApp.Resources (RSTst*), PaskalCPP.Common, PaskalCPP.AST,
    PaskalCPP.ZigBuild, PaskalCPP.Compiler, PaskalCPP.TestSuite.Types,
    PaskalCPP.TestSuite.Spec, PaskalCPP.TestSuite.CodeTest,
    PaskalCPP.TestSuite.Stop, PaskalCPP.TestSuite.Control
  Notes: A run takes its cells cell-major (one target's opt levels, then
    the next target), so a target's toolchain and cache stay warm. A run
    owns its output folder's control channel (one run per folder);
    `testbed -rpc <command>` talks to a running one. Builds run one at a
    time: they share the output folder, its build.zig and pcpp-diag.
    Every build goes to the compiler's default output folder (no -o). The
    suite owns its TErrors (discovery reports); each compile's reports
    stay in that compile's own.
===============================================================================}

unit PaskalCPP.TestSuite;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.AST,
  PaskalCPP.ZigBuild,
  PaskalCPP.Compiler,
  PaskalCPP.TestSuite.Types,
  PaskalCPP.TestSuite.Spec,
  PaskalCPP.TestSuite.CodeTest,
  PaskalCPP.TestSuite.Stop,
  PaskalCPP.TestSuite.Control;

const
  { PC_ERR_TS_101 }
  PC_ERR_TS_101 = 'TS0101';   // a source folder that does not exist
  { PC_ERR_TS_102 }
  PC_ERR_TS_102 = 'TS0102';   // a stem two files share
  { PC_ERR_TS_103 }
  PC_ERR_TS_103 = 'TS0103';   // an id two tests share
  { PC_ERR_TS_104 }
  PC_ERR_TS_104 = 'TS0104';   // a dependency that is no test
  { PC_ERR_TS_105 }
  PC_ERR_TS_105 = 'TS0105';   // a dependency that does not build (not kind dep / build)
  { PC_ERR_TS_106 }
  PC_ERR_TS_106 = 'TS0106';   // a dependency cycle
  { PC_ERR_TS_107 }
  PC_ERR_TS_107 = 'TS0107';   // a cell a dependency does not build in
  { PC_ERR_TS_108 }
  PC_ERR_TS_108 = 'TS0108';   // a dep test nothing depends on
  { PC_ERR_TS_109 }
  PC_ERR_TS_109 = 'TS0109';   // warning: the results file could not be written

  { PC_TS_EXIT_PASSED }
  PC_TS_EXIT_PASSED = 0;
  { PC_TS_EXIT_FAILED }
  PC_TS_EXIT_FAILED = 1;
  { PC_TS_EXIT_BAD_ARGS }
  PC_TS_EXIT_BAD_ARGS = 2;
  { PC_TS_EXIT_STOPPED }
  // A stop press (TestSuite.Stop) ended the run before every selected cell ran
  PC_TS_EXIT_STOPPED = 3;
  { PC_TS_EXIT_NO_RUN }
  // -rpc: no testbed is running on the output folder
  PC_TS_EXIT_NO_RUN = 4;
  { PC_TS_EXIT_WAIT_TIMEOUT }
  // -rpc wait: the run was still going when the seconds ran out
  PC_TS_EXIT_WAIT_TIMEOUT = 5;

  { PC_TS_HEAP_REPORT_PREFIX }
  // The runtime's heap report lines (pcpp_runtime.cpp), printed when the
  // program ends, in a debug build only (PCPP_DEBUG is defined at debug)
  PC_TS_HEAP_REPORT_PREFIX = '[Heap] ';

  { PC_TS_RESULTS_FILE }
  // The last run's results, in the output folder: what -failed reads
  PC_TS_RESULTS_FILE = 'testsuite-results.txt';

  { PC_TS_EXAMPLES_AREA }
  // The area every example root's programs are in: id
  // examples.<folder>.<stem> (examples.raylib.BasicWindow)
  PC_TS_EXAMPLES_AREA = 'examples';

type
  { TPCTestItem }
  // One test: a .pcpp file with a spec, or one registered code test
  TPCTestItem = record
    Id: string;                     // <AreaName>.<TestName>
    AreaName: string;
    TestName: string;
    Kind: TPCTestKind;
    Stem: string;                   // a source test's handle in deps ('' = code test)
    Spec: TPCTestSpec;              // a source test's spec
    CaseIndex: Integer;             // a code test's case (-1 = source test)
    TestIndex: Integer;             // its index in the case
    Cells: TPCTestCells;            // every cell it can run in
    Deps: TArray<string>;           // stems
  end;

  { TPCTestRun }
  // One selected (item, cell)
  TPCTestRun = record
    ItemIndex: Integer;
    Cell: TPCTestCell;
  end;

  { TPCTestFilter }
  // What a run selects; an empty part selects everything
  TPCTestFilter = record
    Patterns: TArray<string>;       // ids or globs
    FromId: string;
    ToId: string;
    Targets: TArray<string>;
    OptLevels: TArray<TPCOptimizeLevel>;
    Subsystems: TArray<TPCSubsystemType>;
    Kinds: TPCTestKinds;
    FailedOnly: Boolean;            // the cells that failed in the last run
    AllCells: Boolean;              // -all: a test that names no opt runs at every level
    Verbose: Boolean;               // every check printed, passed ones too

    procedure Clear();
  end;

  { TPCTestLineWriter }
  // Where every line the suite prints goes: results, summary, list, help,
  // argument and discovery reports. nil = the console
  TPCTestLineWriter = reference to procedure(const ALine: string);

  { TPCTestSuite }
  TPCTestSuite = class(TBaseObject)
  private
    FWriter: TPCTestLineWriter;
    FScanner: TPCTestSpecScanner;
    FCases: TObjectList<TPCTestCase>;
    FItems: TList<TPCTestItem>;
    FSourceRoots: TList<string>;
    FExampleRoots: TList<string>;
    FUnspecced: TList<string>;      // .pcpp files without a spec (support files)
    FResults: TList<TPCTestResult>;
    FCaseSetups: TDictionary<Integer, string>;  // case index -> SetupClass's error ('' = it ran)
    FRepoRoot: string;
    FFixtureRoot: string;
    FOutputRoot: string;
    FDiscovered: Boolean;
    FWslChecked: Boolean;
    FWslAvailable: Boolean;
    FWslReason: string;
    FVerbose: Boolean;
    FTeardownFailed: Boolean;
    FStop: TPCTestStop;
    FControl: TPCTestControl;
    FRootsOnly: Boolean;            // -root given: only its roots' tests, no code tests

    // Discovery
    function DoResolveRoot(const APath: string): string;
    function DoAreaOf(const AFile: string; const ARoot: string; const AStem: string): string;
    procedure DoDiscoverRoot(const ARoot: string; const AIsExamples: Boolean);
    procedure DoDiscoverCases();
    procedure DoSortItems();
    function DoFindStem(const AStem: string): Integer;
    function DoFindId(const AId: string): Integer;
    function DoHasCell(const AIndex: Integer; const ACell: TPCTestCell): Boolean;
    procedure DoGraphError(const AItem: TPCTestItem; const ACode: string;
      const AMessage: string; const AArgs: array of const);
    procedure DoCheckIds();
    procedure DoCheckDeps();
    function DoBuildableDep(const ADep: string): Integer;
    procedure DoCheckCycles();
    procedure DoCycleVisit(const AIndex: Integer; var AColors: TArray<Integer>;
      const APath: TList<Integer>);
    procedure DoCheckCells();
    procedure DoCheckOrphans();
    function DoChainOf(const AIndex: Integer): TArray<Integer>;
    procedure DoChainVisit(const AIndex: Integer; const AChain: TList<Integer>);

    // Selection
    class function DoGlobMatch(const AText: string; const APattern: string): Boolean; static;
    function DoMatchesPatterns(const AId: string; const APatterns: TArray<string>): Boolean;
    function DoCheckRange(const AFilter: TPCTestFilter): Boolean;
    function DoCellAllowed(const ACell: TPCTestCell; const AFilter: TPCTestFilter): Boolean;
    function DoRunCells(const AItem: TPCTestItem; const AFilter: TPCTestFilter): TPCTestCells;
    function DoReadFailed(const AKeys: TList<string>): Boolean;
    function DoTargetRank(const ATarget: string): Integer;
    function DoCompareCells(const ALeft: TPCTestCell; const ARight: TPCTestCell): Integer;
    procedure DoOrderByCell(const ARuns: TList<TPCTestRun>);
    function DoSelect(const AFilter: TPCTestFilter; const ARuns: TList<TPCTestRun>;
      out AFailedCount: Integer): Boolean;

    // Running
    function DoNewCompiler(const AOutput: TList<string>): TPCCompiler;
    procedure DoApplyCell(const ACompiler: TPCCompiler; const ACell: TPCTestCell;
      const ADefines: TArray<string>);
    function DoReportsText(const AErrors: TErrors): string;
    function DoOutputTail(const AOutput: TList<string>): string;
    function DoBuildDep(const AIndex: Integer; const ACell: TPCTestCell;
      var AResult: TPCTestResult): Boolean;
    function DoBuildDeps(const AIndex: Integer; const ACell: TPCTestCell;
      var AResult: TPCTestResult): Boolean;
    function DoBuildFiles(const AMainFile: string; const AMain: TPCModule): TArray<string>;
    procedure DoCheckModuleKind(const AItem: TPCTestItem; const ACompiler: TPCCompiler;
      var AResult: TPCTestResult);
    procedure DoCheckCell(const ACompiler: TPCCompiler; const ACell: TPCTestCell;
      var AResult: TPCTestResult);
    procedure DoCheckMarkers(const AItem: TPCTestItem; const ACompiler: TPCCompiler;
      const ABuilt: Boolean; const AOutput: TList<string>; var AResult: TPCTestResult);
    function DoWslAvailable(): Boolean;
    function DoRunArtifact(const AIsWindows: Boolean; const AArtifact: string;
      const AArgs: string; const AWorkDir: string; const AStdin: string; out AOutput: string;
      out AExitCode: Integer; out ARaised: string): Boolean;
    class function DoWithoutHeapReport(const AText: string): string; static;
    procedure DoCheckRunOutput(const AItem: TPCTestItem; const ACell: TPCTestCell;
      const AGot: string; const AExitCode: Integer; var AResult: TPCTestResult);
    procedure DoCheckTestsOutput(const AGot: string; const AExitCode: Integer;
      var AResult: TPCTestResult);
    procedure DoRunProgram(const AItem: TPCTestItem; const ACell: TPCTestCell;
      const AArtifact: string; var AResult: TPCTestResult);
    procedure DoRunSource(const AItem: TPCTestItem; const ACell: TPCTestCell;
      var AResult: TPCTestResult);
    procedure DoRunCli(const AItem: TPCTestItem; const ACell: TPCTestCell;
      var AResult: TPCTestResult);
    procedure DoCollectSources(const ADir: string; const AFiles: TList<string>);
    procedure DoRunCode(const AItem: TPCTestItem; const ACell: TPCTestCell;
      var AResult: TPCTestResult);
    function DoRunOne(const ARun: TPCTestRun): TPCTestResult;
    // Every run in order until a stop press; True = stopped
    function DoRunSelected(const ARuns: TList<TPCTestRun>): Boolean;
    function DoCountCells(const ARuns: TList<TPCTestRun>): Integer;
    procedure DoPublishResult(const AResult: TPCTestResult);
    procedure DoTeardownCases();

    // Report
    procedure DoPrintLn(const ALine: string); overload;
    procedure DoPrintLn(); overload;
    procedure DoPrintData(const ALine: string);
    function DoResultsFile(): string;
    procedure DoPrintResult(const AResult: TPCTestResult);
    procedure DoPrintSummary(const ADurationMs: Int64; const ASelected: Integer;
      const AStopped: Boolean);
    procedure DoWriteResults();
    procedure DoPrintHelp();
    function DoParseArgs(const AArgs: TArray<string>; out AFilter: TPCTestFilter;
      out AList: Boolean; out AHelp: Boolean; out ASelected: Boolean): Boolean;

    function DoTakeRoots(const AArgs: TArray<string>; out ARest: TArray<string>): Boolean;

    // Control channel
    function DoRunFiltered(const AFilter: TPCTestFilter): Integer;
    procedure DoControlCommand(const ACommand: TPCTestControlCommand);
    function DoRpc(const AArgs: TArray<string>): Integer;
    function DoRpcSend(const AClient: TPCTestControlClient; const ACommand: TPCTestControlCommand;
      const AName: string): Integer;
    function DoRpcWait(const AClient: TPCTestControlClient; const ASeconds: Integer): Integer;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // The suite owns its TErrors: an outside instance is never adopted
    procedure SetErrors(const AErrors: TErrors); override;

    // Setup: a folder of .pcpp tests (scanned with its subfolders), the
    // repo (every fixture and scratch path stays inside it), the code
    // tests' fixture folder (<root>\<area>\fixtures\) and the output folder.
    // Defaults: repo = the exe's parent folder, output = <exe>\output
    procedure AddSourceRoot(const APath: string);
    // A folder of example programs (scanned with its subfolders, fixtures
    // folders left out): each .pcpp is a test of area examples, a build test
    // in the default cells when it has no spec of its own, so every example
    // must build clean on both targets
    procedure AddExampleRoot(const APath: string);
    procedure SetRepoRoot(const APath: string);
    procedure SetFixtureRoot(const APath: string);
    procedure SetOutputRoot(const APath: string);
    // One call: the class's tests become suite items (the suite owns the instance)
    procedure RegisterCase(const AClass: TPCTestCaseClass);
    // Every printed line goes to AWriter (nil = back to the console)
    procedure SetOutput(const AWriter: TPCTestLineWriter);

    // Every item, checked as a whole. False = discovery errors (GetErrors)
    function Discover(): Boolean;
    // Runs what AFilter selects; the exit code (PC_TS_EXIT_*)
    function Run(const AFilter: TPCTestFilter): Integer;
    // Prints the items AFilter's patterns and kinds select
    procedure List(const AFilter: TPCTestFilter);
    // The CLI over AArgs (the arguments after the program name): Discover,
    // List or Run; the exit code
    function RunArgs(const AArgs: TArray<string>): Integer;
    // testbed.exe: RunArgs over this process's command line
    function RunCommandLine(): Integer;

    function GetErrors(): TErrors;
    function ItemCount(): Integer;
    function ItemAt(const AIndex: Integer): TPCTestItem;
    // Every dependency of item AIndex, direct or not, as item indexes in the
    // order they are built before it (each once). Empty until Discover() has
    // passed: a graph with errors (a cycle) has no build order
    function ChainOf(const AIndex: Integer): TArray<Integer>;
    function ResultCount(): Integer;
    function ResultAt(const AIndex: Integer): TPCTestResult;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.IOUtils,
  System.Math,
  System.Diagnostics,
  System.RegularExpressions,
  System.Generics.Defaults,
  StdApp.Utils,
  StdApp.Console,
  StdApp.Resources,
  PaskalCPP.Common;

const
  { PC_TS_MAX_ERRORS }
  // Every expected marker must be reportable: the budget a build stops at
  PC_TS_MAX_ERRORS = 100;

  { PC_TS_DISCOVERY_MAX_ERRORS }
  // Discovery reports every broken spec of the suite, never a first few
  PC_TS_DISCOVERY_MAX_ERRORS = MaxInt;

  { PC_TS_NO_EXIT }
  // An exit code no program returns: the run did not set it
  PC_TS_NO_EXIT = 4242;

  { PC_TS_EXIT_MAX }
  // A program's exit status as both targets keep it (Linux: the low 8 bits);
  // a tests exe's exit code is its failed count capped here
  PC_TS_EXIT_MAX = 255;

  { PC_TS_OUTPUT_TAIL }
  // The build output lines a failed build check shows
  PC_TS_OUTPUT_TAIL = 30;

  { PC_TS_CHAIN_ARROW }
  PC_TS_CHAIN_ARROW = ' -> ';

  { PC_TS_RESULTS_LINE }
  // The runtime's unit test summary (pcpp_runtime.cpp run_tests)
  PC_TS_RESULTS_LINE = '^Results: (\d+) passed, (\d+) failed, (\d+) total$';

  { PC_TS_RESULT_WORDS }
  // The results file's status words (read back by -failed, never translated)
  PC_TS_RESULT_WORDS: array[TPCTestStatus] of string = (
    'PASS',
    'FAIL',
    'SKIP'
  );

  { PC_TS_WSL_EXE }
  PC_TS_WSL_EXE = 'wsl.exe';

  { PC_TS_PCPP_EXE }
  // The compiler a cli test runs: the one beside the suite's host (repo\bin)
  PC_TS_PCPP_EXE = '$P:pcpp.exe';

  { PC_TS_WSL_PROBE }
  // A command that does nothing: WSL is there when it exits 0
  PC_TS_WSL_PROBE = '-e true';

  { PC_TS_ARG_HELP }
  PC_TS_ARG_HELP = '-h';
  { PC_TS_ARG_HELP_LONG }
  PC_TS_ARG_HELP_LONG = '--help';
  { PC_TS_ARG_ALL }
  PC_TS_ARG_ALL = '-all';
  { PC_TS_ARG_LIST }
  PC_TS_ARG_LIST = '-list';
  { PC_TS_ARG_FROM }
  PC_TS_ARG_FROM = '-from';
  { PC_TS_ARG_TO }
  PC_TS_ARG_TO = '-to';
  { PC_TS_ARG_TARGET }
  PC_TS_ARG_TARGET = '-t';
  { PC_TS_ARG_OPT }
  PC_TS_ARG_OPT = '-opt';
  { PC_TS_ARG_GUI }
  PC_TS_ARG_GUI = '-gui';
  { PC_TS_ARG_CONSOLE }
  PC_TS_ARG_CONSOLE = '-console';
  { PC_TS_ARG_KIND }
  PC_TS_ARG_KIND = '-kind';
  { PC_TS_ARG_FAILED }
  PC_TS_ARG_FAILED = '-failed';
  { PC_TS_ARG_VERBOSE }
  PC_TS_ARG_VERBOSE = '-v';
  { PC_TS_ARG_RPC }
  // First argument only: talk to the testbed running on the output folder
  PC_TS_ARG_RPC = '-rpc';
  { PC_TS_ARG_ROOT }
  // A folder of .pcpp tests (repeatable): the roots given replace the
  // host's (its tests and its examples), e.g. a probe's planted fixtures
  PC_TS_ARG_ROOT = '-root';

  { PC_TS_RPC_STATUS }
  PC_TS_RPC_STATUS = 'status';
  { PC_TS_RPC_FAILURES }
  PC_TS_RPC_FAILURES = 'failures';
  { PC_TS_RPC_STOP }
  PC_TS_RPC_STOP = 'stop';
  { PC_TS_RPC_ABORT }
  PC_TS_RPC_ABORT = 'abort';
  { PC_TS_RPC_WAIT }
  PC_TS_RPC_WAIT = 'wait';

  { PC_TS_RPC_POLL_MS }
  // How often -rpc wait and a sent command look at the block
  PC_TS_RPC_POLL_MS = 250;
  { PC_TS_RPC_TAKEN_MS }
  // How long a sent stop / abort waits to be taken before saying it is queued
  PC_TS_RPC_TAKEN_MS = 3000;

  { PC_TS_CHECK_INDENT }
  // A check text's continuation lines, under its first
  PC_TS_CHECK_INDENT = '        ';

{ TPCTestFilter }

procedure TPCTestFilter.Clear();
begin
  Self := Default(TPCTestFilter);
end;

{ TPCTestSuite }

constructor TPCTestSuite.Create();
begin
  inherited;

  // Every printed line goes through DoPrintLn; nil = the console
  FWriter := nil;

  // The top-level owner of its TErrors (PROJECT.md Error Handling); its
  // reports print through DoPrintLn like every other line
  FErrors := TErrors.Create();
  FErrors.SetMaxErrors(PC_TS_DISCOVERY_MAX_ERRORS);
  FErrors.SetStatusCallback(
    procedure(const AText: string; const AUserData: Pointer)
    begin
      DoPrintLn(AText);
    end);

  FScanner := TPCTestSpecScanner.Create();
  FScanner.SetErrors(FErrors);
  FStop := TPCTestStop.Create();
  FStop.SetErrors(FErrors);
  // The control channel: its heartbeat and mailbox ride on the stop
  // thread, its stop / abort commands become stop presses
  FControl := TPCTestControl.Create();
  FControl.SetErrors(FErrors);
  FControl.OnCommand := DoControlCommand;
  FStop.SetPollHook(
    procedure
    begin
      FControl.Service();
    end);
  FCases := TObjectList<TPCTestCase>.Create(True);
  FItems := TList<TPCTestItem>.Create();
  FSourceRoots := TList<string>.Create();
  FExampleRoots := TList<string>.Create();
  FUnspecced := TList<string>.Create();
  FResults := TList<TPCTestResult>.Create();
  FCaseSetups := TDictionary<Integer, string>.Create();
  FDiscovered := False;
  FRootsOnly := False;
  FWslChecked := False;
  FWslAvailable := False;
  FWslReason := '';
  FVerbose := False;
  FTeardownFailed := False;
  FFixtureRoot := '';

  // Defaults: testbed.exe lives in repo\bin
  try
    FRepoRoot := TUtils.ResolvePath('$P:..');
    FOutputRoot := TUtils.ResolvePath('$P:' + PC_CMP_DEFAULT_OUTPUT);
  except
    on E: Exception do
    begin
      FErrors.Add(esError, PC_ERR_TS_101, RSTstRootMissing, ['$P: ' + E.Message]);
      FRepoRoot := '';
      FOutputRoot := '';
    end;
  end;
end;

destructor TPCTestSuite.Destroy();
begin
  FCaseSetups.Free();
  FResults.Free();
  FUnspecced.Free();
  FExampleRoots.Free();
  FSourceRoots.Free();
  FItems.Free();
  FCases.Free();
  // The stop thread runs the control channel's hook: it ends first
  FStop.Free();
  FControl.Free();
  FScanner.Free();
  FreeAndNil(FErrors);

  inherited;
end;

procedure TPCTestSuite.SetErrors(const AErrors: TErrors);
begin
  // Never adopted: the suite created its own in Create
end;

procedure TPCTestSuite.AddSourceRoot(const APath: string);
begin
  FSourceRoots.Add(APath);
  FDiscovered := False;
end;

procedure TPCTestSuite.AddExampleRoot(const APath: string);
begin
  FExampleRoots.Add(APath);
  FDiscovered := False;
end;

function TPCTestSuite.DoResolveRoot(const APath: string): string;
begin
  // Every root is stored resolved (TUtils.ResolvePath), so no '$P:' or
  // relative spelling ever reaches a test case or a path check
  Result := '';
  if APath = '' then
    Exit;
  try
    Result := TUtils.ResolvePath(APath);
  except
    on E: Exception do
      FErrors.Add(esError, PC_ERR_TS_101, RSTstRootMissing, [APath + ': ' + E.Message]);
  end;
end;

procedure TPCTestSuite.SetRepoRoot(const APath: string);
begin
  FRepoRoot := DoResolveRoot(APath);
end;

procedure TPCTestSuite.SetFixtureRoot(const APath: string);
begin
  FFixtureRoot := DoResolveRoot(APath);
end;

procedure TPCTestSuite.SetOutputRoot(const APath: string);
begin
  FOutputRoot := DoResolveRoot(APath);
end;

procedure TPCTestSuite.RegisterCase(const AClass: TPCTestCaseClass);
begin
  FCases.Add(AClass.Create());
  FDiscovered := False;
end;

procedure TPCTestSuite.SetOutput(const AWriter: TPCTestLineWriter);
begin
  FWriter := AWriter;
end;

function TPCTestSuite.GetErrors(): TErrors;
begin
  Result := FErrors;
end;

function TPCTestSuite.ItemCount(): Integer;
begin
  Result := FItems.Count;
end;

function TPCTestSuite.ItemAt(const AIndex: Integer): TPCTestItem;
begin
  Result := FItems[AIndex];
end;

function TPCTestSuite.ChainOf(const AIndex: Integer): TArray<Integer>;
begin
  Result := [];
  if (not FDiscovered) or FErrors.HasErrors() then
    Exit;
  Result := DoChainOf(AIndex);
end;

function TPCTestSuite.ResultCount(): Integer;
begin
  Result := FResults.Count;
end;

function TPCTestSuite.ResultAt(const AIndex: Integer): TPCTestResult;
begin
  Result := FResults[AIndex];
end;

{ Discovery }

function TPCTestSuite.DoAreaOf(const AFile: string; const ARoot: string;
  const AStem: string): string;
var
  LRelative: string;
  LSlash: Integer;
  LUnderscore: Integer;
begin
  // The file's folder under the root, folders joined by '.'; a file in the
  // root itself: its stem's prefix (mod_kinds -> mod), else the stem.
  // GetRelativePath works in '/' whatever slashes ResolvePath and the file
  // list carry (an RTL '\' helper on a '/' path gives '..')
  LRelative := TUtils.GetRelativePath(ARoot, AFile);
  LSlash := LRelative.LastIndexOf('/');
  if LSlash > 0 then
    Exit(LRelative.Substring(0, LSlash).Replace('/', PC_TS_ID_SEPARATOR));

  LUnderscore := AStem.IndexOf('_');
  if LUnderscore > 0 then
    Result := AStem.Substring(0, LUnderscore)
  else
    Result := AStem;
end;

procedure TPCTestSuite.DoDiscoverRoot(const ARoot: string; const AIsExamples: Boolean);
var
  LDir: string;
  LFiles: TArray<string>;
  LFile: string;
  LSpec: TPCTestSpec;
  LHasSpec: Boolean;
  LScanned: Boolean;
  LItem: TPCTestItem;
  LOther: Integer;
  LCollected: TList<string>;
begin
  LCollected := TList<string>.Create();
  try
    try
      LDir := TUtils.ResolvePath(ARoot);
      if not TDirectory.Exists(LDir) then
      begin
        FErrors.Add(esError, PC_ERR_TS_101, RSTstRootMissing, [LDir]);
        Exit;
      end;
      // Every source file, fixtures folders left out
      DoCollectSources(LDir, LCollected);
    except
      on E: Exception do
      begin
        FErrors.Add(esError, PC_ERR_TS_101, RSTstRootMissing, [ARoot + ': ' + E.Message]);
        Exit;
      end;
    end;
    LFiles := LCollected.ToArray();
  finally
    LCollected.Free();
  end;
  TArray.Sort<string>(LFiles);

  for LFile in LFiles do
  begin
    // A file whose spec is broken is reported by the scanner and left out.
    // An example always has a spec: its own, or the implied build one
    if AIsExamples then
    begin
      LScanned := FScanner.ScanExample(LFile, LSpec);
      LHasSpec := True;
    end
    else
      LScanned := FScanner.Scan(LFile, LSpec, LHasSpec);
    if not LScanned then
      Continue;
    if not LHasSpec then
    begin
      FUnspecced.Add(LFile);
      Continue;
    end;

    LOther := DoFindStem(LSpec.Stem);
    if LOther >= 0 then
    begin
      FErrors.Add(LSpec.SpecRange, esError, PC_ERR_TS_102, RSTstDuplicateStem,
        [LSpec.Stem, FItems[LOther].Spec.Filename]);
      Continue;
    end;

    LItem := Default(TPCTestItem);
    LItem.AreaName := DoAreaOf(LSpec.Filename, LDir, LSpec.Stem);
    if AIsExamples then
      LItem.AreaName := PC_TS_EXAMPLES_AREA + PC_TS_ID_SEPARATOR + LItem.AreaName;
    LItem.TestName := LSpec.Stem;
    LItem.Id := LItem.AreaName + PC_TS_ID_SEPARATOR + LItem.TestName;
    LItem.Kind := LSpec.Kind;
    LItem.Stem := LSpec.Stem;
    LItem.Spec := LSpec;
    LItem.CaseIndex := -1;
    LItem.TestIndex := -1;
    LItem.Cells := LSpec.Cells();
    LItem.Deps := LSpec.Deps;
    FItems.Add(LItem);
  end;
end;

procedure TPCTestSuite.DoDiscoverCases();
var
  LCaseIndex: Integer;
  LCase: TPCTestCase;
  LI: Integer;
  LTest: TPCCodeTest;
  LItem: TPCTestItem;
begin
  for LCaseIndex := 0 to FCases.Count - 1 do
  begin
    LCase := FCases[LCaseIndex];
    for LI := 0 to LCase.TestCount() - 1 do
    begin
      LTest := LCase.TestAt(LI);
      LItem := Default(TPCTestItem);
      LItem.AreaName := LCase.GetAreaName();
      LItem.TestName := LTest.TestName;
      LItem.Id := LItem.AreaName + PC_TS_ID_SEPARATOR + LItem.TestName;
      LItem.Kind := skCode;
      LItem.Stem := '';
      LItem.CaseIndex := LCaseIndex;
      LItem.TestIndex := LI;
      // A code test runs in the host's default cell unless it names its own
      // (its Delphi code is the host's; a cell matters only to what it builds)
      if Length(LTest.Cells) > 0 then
        LItem.Cells := LTest.Cells
      else
        LItem.Cells := [TPCTestCell.Make(PC_TARGET_X86_64_WINDOWS_GNU, olDebug, stConsole)];
      LItem.Deps := LTest.Deps;
      FItems.Add(LItem);
    end;
  end;
end;

procedure TPCTestSuite.DoSortItems();
begin
  FItems.Sort(TComparer<TPCTestItem>.Construct(
    function(const ALeft: TPCTestItem; const ARight: TPCTestItem): Integer
    begin
      Result := CompareText(ALeft.Id, ARight.Id);
    end));
end;

function TPCTestSuite.DoFindStem(const AStem: string): Integer;
var
  LI: Integer;
begin
  for LI := 0 to FItems.Count - 1 do
  begin
    if (FItems[LI].Stem <> '') and SameText(FItems[LI].Stem, AStem) then
      Exit(LI);
  end;
  Result := -1;
end;

function TPCTestSuite.DoFindId(const AId: string): Integer;
var
  LI: Integer;
begin
  for LI := 0 to FItems.Count - 1 do
  begin
    if SameText(FItems[LI].Id, AId) then
      Exit(LI);
  end;
  Result := -1;
end;

function TPCTestSuite.DoHasCell(const AIndex: Integer; const ACell: TPCTestCell): Boolean;
var
  LCell: TPCTestCell;
begin
  for LCell in FItems[AIndex].Cells do
  begin
    if LCell.SameAs(ACell) then
      Exit(True);
  end;
  Result := False;
end;

procedure TPCTestSuite.DoGraphError(const AItem: TPCTestItem; const ACode: string;
  const AMessage: string; const AArgs: array of const);
begin
  // A source test is reported at its spec; a code test has no place in a file
  if AItem.Kind = skCode then
    FErrors.Add(esError, ACode, AMessage, AArgs)
  else
    FErrors.Add(AItem.Spec.SpecRange, esError, ACode, AMessage, AArgs);
end;

procedure TPCTestSuite.DoCheckIds();
var
  LI: Integer;
begin
  // Sorted: a shared id sits next to its twin
  for LI := 1 to FItems.Count - 1 do
  begin
    if SameText(FItems[LI - 1].Id, FItems[LI].Id) then
      DoGraphError(FItems[LI], PC_ERR_TS_103, RSTstDuplicateId, [FItems[LI].Id]);
  end;
end;

procedure TPCTestSuite.DoCheckDeps();
var
  LItem: TPCTestItem;
  LDep: string;
  LJ: Integer;
begin
  for LItem in FItems do
  begin
    for LDep in LItem.Deps do
    begin
      LJ := DoFindStem(LDep);
      if LJ < 0 then
        DoGraphError(LItem, PC_ERR_TS_104, RSTstMissingDep, [LItem.Id, LDep])
      else if not (FItems[LJ].Kind in [skDep, skBuild]) then
        DoGraphError(LItem, PC_ERR_TS_105, RSTstDepNotBuildable,
          [LItem.Id, LDep, PC_TS_KIND_TEXT[FItems[LJ].Kind]]);
    end;
  end;
end;

function TPCTestSuite.DoBuildableDep(const ADep: string): Integer;
begin
  // The item a dependency names, or -1 when DoCheckDeps reports that edge
  // (no such stem, or a test that does not build): the graph checks after
  // DoCheckDeps follow only these edges, so one mistake gets one report
  Result := DoFindStem(ADep);
  if (Result >= 0) and (not (FItems[Result].Kind in [skDep, skBuild])) then
    Result := -1;
end;

procedure TPCTestSuite.DoCycleVisit(const AIndex: Integer; var AColors: TArray<Integer>;
  const APath: TList<Integer>);
var
  LDep: string;
  LJ: Integer;
  LK: Integer;
  LText: string;
begin
  // Depth first: 0 = not seen, 1 = on the path, 2 = done. An edge back to
  // the path is a cycle, reported once with its whole chain
  AColors[AIndex] := 1;
  APath.Add(AIndex);
  for LDep in FItems[AIndex].Deps do
  begin
    LJ := DoBuildableDep(LDep);
    if LJ < 0 then
      Continue;
    if AColors[LJ] = 1 then
    begin
      LText := '';
      for LK := APath.IndexOf(LJ) to APath.Count - 1 do
        LText := LText + FItems[APath[LK]].Id + PC_TS_CHAIN_ARROW;
      LText := LText + FItems[LJ].Id;
      DoGraphError(FItems[AIndex], PC_ERR_TS_106, RSTstDepCycle, [LText]);
    end
    else if AColors[LJ] = 0 then
      DoCycleVisit(LJ, AColors, APath);
  end;
  APath.Delete(APath.Count - 1);
  AColors[AIndex] := 2;
end;

procedure TPCTestSuite.DoCheckCycles();
var
  LColors: TArray<Integer>;
  LPath: TList<Integer>;
  LI: Integer;
begin
  // Each cycle is reported once with its chain; a cycle is a discovery
  // error, so Run never walks a cyclic chain
  SetLength(LColors, FItems.Count);
  LPath := TList<Integer>.Create();
  try
    for LI := 0 to FItems.Count - 1 do
    begin
      if LColors[LI] = 0 then
        DoCycleVisit(LI, LColors, LPath);
    end;
  finally
    LPath.Free();
  end;
end;

procedure TPCTestSuite.DoChainVisit(const AIndex: Integer; const AChain: TList<Integer>);
var
  LDep: string;
  LJ: Integer;
begin
  // Post order: a dependency's own dependencies first (the graph is acyclic)
  for LDep in FItems[AIndex].Deps do
  begin
    LJ := DoFindStem(LDep);
    if (LJ < 0) or AChain.Contains(LJ) then
      Continue;
    DoChainVisit(LJ, AChain);
    AChain.Add(LJ);
  end;
end;

function TPCTestSuite.DoChainOf(const AIndex: Integer): TArray<Integer>;
var
  LChain: TList<Integer>;
begin
  // Every dependency of item AIndex, direct or not, in build order
  LChain := TList<Integer>.Create();
  try
    DoChainVisit(AIndex, LChain);
    Result := LChain.ToArray();
  finally
    LChain.Free();
  end;
end;

procedure TPCTestSuite.DoCheckCells();
var
  LI: Integer;
  LJ: Integer;
  LDep: string;
  LCell: TPCTestCell;
begin
  // A dependency takes its consumer's cell: it must build in each of them.
  // Checked per direct edge only: when every edge holds, every chain holds
  // (the cells nest), and a broken edge is reported once, at that edge, not
  // again by each consumer further up. No chain walk, so a cycle elsewhere
  // does not hide a conflict
  for LI := 0 to FItems.Count - 1 do
  begin
    for LDep in FItems[LI].Deps do
    begin
      LJ := DoBuildableDep(LDep);
      if LJ < 0 then
        Continue;
      for LCell in FItems[LI].Cells do
      begin
        if not DoHasCell(LJ, LCell) then
        begin
          DoGraphError(FItems[LI], PC_ERR_TS_107, RSTstCellConflict,
            [FItems[LI].Id, LCell.ToText(), FItems[LJ].Id]);
          Break;
        end;
      end;
    end;
  end;
end;

procedure TPCTestSuite.DoCheckOrphans();
var
  LI: Integer;
  LItem: TPCTestItem;
  LDep: string;
  LUsed: TArray<Boolean>;
  LJ: Integer;
begin
  // A dep test is never run for itself: one that nothing uses is dead
  SetLength(LUsed, FItems.Count);
  for LItem in FItems do
  begin
    for LDep in LItem.Deps do
    begin
      LJ := DoFindStem(LDep);
      if LJ >= 0 then
        LUsed[LJ] := True;
    end;
  end;
  for LI := 0 to FItems.Count - 1 do
  begin
    if (FItems[LI].Kind = skDep) and (not LUsed[LI]) then
      DoGraphError(FItems[LI], PC_ERR_TS_108, RSTstOrphanDep, [FItems[LI].Id]);
  end;
end;

function TPCTestSuite.Discover(): Boolean;
var
  LRoot: string;
begin
  FErrors.Clear();
  FItems.Clear();
  FUnspecced.Clear();

  for LRoot in FSourceRoots do
    DoDiscoverRoot(LRoot, False);
  for LRoot in FExampleRoots do
    DoDiscoverRoot(LRoot, True);
  // -root runs only the .pcpp tests under the roots it names: the host's
  // registered code tests are left out with its own tests and examples
  if not FRootsOnly then
    DoDiscoverCases();
  DoSortItems();

  DoCheckIds();
  DoCheckDeps();
  DoCheckCycles();
  DoCheckCells();
  DoCheckOrphans();

  FDiscovered := True;
  Result := not FErrors.HasErrors();
end;

{ Selection }

class function TPCTestSuite.DoGlobMatch(const AText: string; const APattern: string): Boolean;
var
  LText: string;
  LPattern: string;
  LT: Integer;
  LP: Integer;
  LStarP: Integer;
  LStarT: Integer;
begin
  // An id glob: '*' = any run of characters (none too), '?' = one
  // character, every other character itself, case-insensitively (ids
  // compare like DoFindId). Not a file-name mask: '.' is an ordinary
  // character and nothing is rejected.
  // Greedy scan with one backtrack point: on a mismatch after a '*', the
  // '*' takes one more character and the rest is tried again
  LText := UpperCase(AText);
  LPattern := UpperCase(APattern);
  LT := 1;
  LP := 1;
  LStarP := 0;
  LStarT := 0;
  while LT <= LText.Length do
  begin
    if (LP <= LPattern.Length) and
      ((LPattern[LP] = '?') or ((LPattern[LP] <> '*') and (LPattern[LP] = LText[LT]))) then
    begin
      Inc(LT);
      Inc(LP);
    end
    else if (LP <= LPattern.Length) and (LPattern[LP] = '*') then
    begin
      LStarP := LP;
      LStarT := LT;
      Inc(LP);
    end
    else if LStarP > 0 then
    begin
      Inc(LStarT);
      LT := LStarT;
      LP := LStarP + 1;
    end
    else
      Exit(False);
  end;

  // The text is used up: only '*'s may be left of the pattern
  while (LP <= LPattern.Length) and (LPattern[LP] = '*') do
    Inc(LP);
  Result := LP > LPattern.Length;
end;

function TPCTestSuite.DoMatchesPatterns(const AId: string; const APatterns: TArray<string>): Boolean;
var
  LPattern: string;
begin
  // No pattern = every id
  if Length(APatterns) = 0 then
    Exit(True);
  for LPattern in APatterns do
  begin
    if DoGlobMatch(AId, LPattern) then
      Exit(True);
  end;
  Result := False;
end;

function TPCTestSuite.DoCheckRange(const AFilter: TPCTestFilter): Boolean;
var
  LFrom: Integer;
  LTo: Integer;
begin
  // -from / -to name tests, and -from comes first in id order
  Result := False;
  LFrom := -1;
  LTo := -1;
  if AFilter.FromId <> '' then
  begin
    LFrom := DoFindId(AFilter.FromId);
    if LFrom < 0 then
    begin
      DoPrintLn(COLOR_RED + Format(RSTstUnknownId, [AFilter.FromId]));
      Exit;
    end;
  end;
  if AFilter.ToId <> '' then
  begin
    LTo := DoFindId(AFilter.ToId);
    if LTo < 0 then
    begin
      DoPrintLn(COLOR_RED + Format(RSTstUnknownId, [AFilter.ToId]));
      Exit;
    end;
  end;
  if (LFrom >= 0) and (LTo >= 0) and (LFrom > LTo) then
  begin
    DoPrintLn(COLOR_RED + Format(RSTstBadRange, [AFilter.FromId, AFilter.ToId]));
    Exit;
  end;
  Result := True;
end;

function TPCTestSuite.DoCellAllowed(const ACell: TPCTestCell; const AFilter: TPCTestFilter): Boolean;
var
  LTarget: string;
  LOpt: TPCOptimizeLevel;
  LSubsystem: TPCSubsystemType;
  LFound: Boolean;
begin
  Result := False;

  if Length(AFilter.Targets) > 0 then
  begin
    LFound := False;
    for LTarget in AFilter.Targets do
    begin
      if LTarget = ACell.Target then
        LFound := True;
    end;
    if not LFound then
      Exit;
  end;

  if Length(AFilter.OptLevels) > 0 then
  begin
    LFound := False;
    for LOpt in AFilter.OptLevels do
    begin
      if LOpt = ACell.OptLevel then
        LFound := True;
    end;
    if not LFound then
      Exit;
  end;

  if Length(AFilter.Subsystems) > 0 then
  begin
    LFound := False;
    for LSubsystem in AFilter.Subsystems do
    begin
      if LSubsystem = ACell.Subsystem then
        LFound := True;
    end;
    if not LFound then
      Exit;
  end;

  Result := True;
end;

function TPCTestSuite.DoRunCells(const AItem: TPCTestItem; const AFilter: TPCTestFilter): TPCTestCells;
var
  LLevels: TArray<TPCOptimizeLevel>;
  LLevel: TPCOptimizeLevel;
  LCell: TPCTestCell;
  LNew: TPCTestCell;
  LHave: TPCTestCell;
  LDuplicate: Boolean;
begin
  // A source test whose spec names no opt runs at the levels the run asks
  // for (-opt), not at its default debug; under -all every level is
  // offered (the full target x opt matrix), and under -failed too, so a
  // failed cell of any level is found again. A test with its own opt, and
  // every code test, keeps the cells it declares
  if (AItem.CaseIndex >= 0) or (not AItem.Spec.OptDefault) then
    Exit(AItem.Cells);
  if Length(AFilter.OptLevels) > 0 then
    LLevels := AFilter.OptLevels
  else if AFilter.FailedOnly or AFilter.AllCells then
  begin
    LLevels := [];
    for LLevel := Low(TPCOptimizeLevel) to High(TPCOptimizeLevel) do
      LLevels := LLevels + [LLevel];
  end
  else
    Exit(AItem.Cells);

  Result := [];
  for LCell in AItem.Cells do
  begin
    for LLevel in LLevels do
    begin
      LNew := TPCTestCell.Make(LCell.Target, LLevel, LCell.Subsystem);
      // -opt is repeatable: a level named twice gives its cell once
      LDuplicate := False;
      for LHave in Result do
      begin
        if (LHave.Target = LNew.Target) and (LHave.OptLevel = LNew.OptLevel) and
          (LHave.Subsystem = LNew.Subsystem) then
          LDuplicate := True;
      end;
      if not LDuplicate then
        Result := Result + [LNew];
    end;
  end;
end;

function TPCTestSuite.DoReadFailed(const AKeys: TList<string>): Boolean;
var
  LFile: string;
  LLines: TArray<string>;
  LLine: string;
  LPrefix: string;
begin
  // The last run's FAIL lines: '<id> <cell>' each
  LFile := DoResultsFile();
  try
    if not FileExists(LFile) then
    begin
      DoPrintLn(COLOR_RED + Format(RSTstNoResultsFile, [LFile]));
      Exit(False);
    end;
    LLines := TFile.ReadAllLines(LFile, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      DoPrintLn(COLOR_RED + Format(RSTstNoResultsFile, [LFile + ': ' + E.Message]));
      Exit(False);
    end;
  end;

  LPrefix := PC_TS_RESULT_WORDS[trFail] + ' ';
  for LLine in LLines do
  begin
    if LLine.StartsWith(LPrefix) then
      AKeys.Add(LLine.Substring(LPrefix.Length).Trim());
  end;
  Result := True;
end;

function TPCTestSuite.DoTargetRank(const ATarget: string): Integer;
begin
  // The official targets first, Windows then Linux; any other after them
  if ATarget = PC_TARGET_X86_64_WINDOWS_GNU then
    Result := 0
  else if ATarget = PC_TARGET_X86_64_LINUX_GNU then
    Result := 1
  else
    Result := 2;
end;

function TPCTestSuite.DoCompareCells(const ALeft: TPCTestCell; const ARight: TPCTestCell): Integer;
begin
  // Target outer, then the opt level in its enum order (debug, safe, fast,
  // small), then the subsystem
  Result := DoTargetRank(ALeft.Target) - DoTargetRank(ARight.Target);
  if Result = 0 then
    Result := CompareStr(ALeft.Target, ARight.Target);
  if Result = 0 then
    Result := Ord(ALeft.OptLevel) - Ord(ARight.OptLevel);
  if Result = 0 then
    Result := Ord(ALeft.Subsystem) - Ord(ARight.Subsystem);
end;

procedure TPCTestSuite.DoOrderByCell(const ARuns: TList<TPCTestRun>);
var
  LCells: TList<TPCTestCell>;
  LOrdered: TList<TPCTestRun>;
  LRun: TPCTestRun;
  LCell: TPCTestCell;
  LHave: TPCTestCell;
  LKnown: Boolean;
begin
  // Cell-major: every selected test of one cell, then the next cell, so a
  // target's toolchain and build cache stay warm instead of every test
  // hopping between targets. The cells are distinct, so sorting them is
  // a total order; the runs keep their id order inside a cell
  LCells := TList<TPCTestCell>.Create();
  LOrdered := TList<TPCTestRun>.Create();
  try
    for LRun in ARuns do
    begin
      LKnown := False;
      for LHave in LCells do
      begin
        if LHave.SameAs(LRun.Cell) then
          LKnown := True;
      end;
      if not LKnown then
        LCells.Add(LRun.Cell);
    end;

    LCells.Sort(TComparer<TPCTestCell>.Construct(
      function(const ALeft: TPCTestCell; const ARight: TPCTestCell): Integer
      begin
        Result := DoCompareCells(ALeft, ARight);
      end));

    for LCell in LCells do
    begin
      for LRun in ARuns do
      begin
        if LRun.Cell.SameAs(LCell) then
          LOrdered.Add(LRun);
      end;
    end;

    ARuns.Clear();
    ARuns.AddRange(LOrdered);
  finally
    LOrdered.Free();
    LCells.Free();
  end;
end;

function TPCTestSuite.DoSelect(const AFilter: TPCTestFilter; const ARuns: TList<TPCTestRun>;
  out AFailedCount: Integer): Boolean;
var
  LFailed: TList<string>;
  LFrom: Integer;
  LTo: Integer;
  LI: Integer;
  LItem: TPCTestItem;
  LCell: TPCTestCell;
  LRun: TPCTestRun;
begin
  Result := False;
  AFailedCount := 0;
  LFailed := TList<string>.Create();
  try
    if AFilter.FailedOnly and (not DoReadFailed(LFailed)) then
      Exit;
    // How many cells the last run failed (-failed only): none = a clean run
    AFailedCount := LFailed.Count;

    // -from / -to: a range of the id order (checked by the caller)
    LFrom := 0;
    LTo := FItems.Count - 1;
    if AFilter.FromId <> '' then
      LFrom := DoFindId(AFilter.FromId);
    if AFilter.ToId <> '' then
      LTo := DoFindId(AFilter.ToId);
    if (LFrom < 0) or (LTo < 0) then
      Exit;

    for LI := LFrom to LTo do
    begin
      LItem := FItems[LI];
      // A dep test is built for its consumers, never run on its own; a
      // manual test is checked by a person, never run by the suite (even
      // named alone or under -kind manual: -list shows it)
      if LItem.Kind in [skDep, skManual] then
        Continue;
      if (AFilter.Kinds <> []) and (not (LItem.Kind in AFilter.Kinds)) then
        Continue;
      if not DoMatchesPatterns(LItem.Id, AFilter.Patterns) then
        Continue;

      for LCell in DoRunCells(LItem, AFilter) do
      begin
        if not DoCellAllowed(LCell, AFilter) then
          Continue;
        if AFilter.FailedOnly and (not LFailed.Contains(LItem.Id + ' ' + LCell.ToText())) then
          Continue;
        LRun.ItemIndex := LI;
        LRun.Cell := LCell;
        ARuns.Add(LRun);
      end;
    end;
    DoOrderByCell(ARuns);
    Result := True;
  finally
    LFailed.Free();
  end;
end;

{ Running }

function TPCTestSuite.DoNewCompiler(const AOutput: TList<string>): TPCCompiler;
var
  LOutput: TList<string>;
begin
  // A fresh compiler per build: its own reports, quiet; the build tool's
  // output kept for a failed build check
  LOutput := AOutput;
  Result := TPCCompiler.Create();
  Result.SetMaxErrors(PC_TS_MAX_ERRORS);
  // Every build writes into the suite's output root, never into whatever
  // folder the host was started from ($P:output in a test's @addlibrarypath
  // must name the folder its dep was just built into); a test's own
  // @outputpath still wins, as it does for pcpp
  Result.SetDefaultOutputPath(FOutputRoot);
  Result.SetStatusCallback(
    procedure(const AText: string; const AUserData: Pointer)
    begin
      // Status lines are progress, not results: the reporter prints results
    end);
  Result.SetOutputCallback(
    procedure(const ALine: string; const AUserData: Pointer)
    begin
      LOutput.Add(ALine);
    end);
end;

procedure TPCTestSuite.DoApplyCell(const ACompiler: TPCCompiler; const ACell: TPCTestCell;
  const ADefines: TArray<string>);
var
  LDefine: string;
  LAt: Integer;
begin
  // The cell as defaults: a directive of the file still wins (and is then
  // reported by DoCheckCell); the spec's defines go to the build
  ACompiler.SetKeyDefault(PC_CMP_KEY_TARGET, ACell.Target);
  ACompiler.SetKeyDefault(PC_CMP_KEY_OPTIMIZE, PC_CMP_OPTIMIZE_TEXT[ACell.OptLevel]);
  ACompiler.SetKeyDefault(PC_CMP_KEY_SUBSYSTEM, PC_CMP_SUBSYSTEM_TEXT[ACell.Subsystem]);
  for LDefine in ADefines do
  begin
    LAt := LDefine.IndexOf('=');
    if LAt < 0 then
      ACompiler.SetDefine(LDefine)
    else
      ACompiler.SetDefine(LDefine.Substring(0, LAt), LDefine.Substring(LAt + 1));
  end;
end;

function TPCTestSuite.DoReportsText(const AErrors: TErrors): string;
var
  LError: TError;
begin
  Result := '';
  for LError in AErrors.GetItems() do
    Result := Result + #10 + TPCTestReports.ReportText(AErrors, LError);
end;

function TPCTestSuite.DoOutputTail(const AOutput: TList<string>): string;
var
  LI: Integer;
begin
  Result := '';
  if AOutput.Count = 0 then
    Exit;
  Result := #10 + RSTstBuildOutput;
  for LI := Max(0, AOutput.Count - PC_TS_OUTPUT_TAIL) to AOutput.Count - 1 do
    Result := Result + #10 + AOutput[LI];
end;

function TPCTestSuite.DoBuildDep(const AIndex: Integer; const ACell: TPCTestCell;
  var AResult: TPCTestResult): Boolean;
var
  LItem: TPCTestItem;
  LOutput: TList<string>;
  LCompiler: TPCCompiler;
  LShape: TPCTestResult;
  LShapeText: string;
  LCheck: TPCTestCheck;
begin
  LItem := FItems[AIndex];
  LOutput := TList<string>.Create();
  try
    LCompiler := DoNewCompiler(LOutput);
    try
      DoApplyCell(LCompiler, ACell, LItem.Spec.Defines);
      Result := LCompiler.Prepare(LItem.Spec.Filename, '');

      // A dep is never a result of its own, so its shape is checked here:
      // the module kind its kind says, built in exactly the consumer's cell.
      // A wrong shape is this dep's failure, before any build is spent on it
      LShapeText := '';
      if Result then
      begin
        LShape.Clear();
        DoCheckModuleKind(LItem, LCompiler, LShape);
        DoCheckCell(LCompiler, ACell, LShape);
        for LCheck in LShape.Checks do
        begin
          if not LCheck.Passed then
            LShapeText := LShapeText + #10 + LCheck.Text;
        end;
        Result := LShapeText = '';
      end;

      Result := Result and LCompiler.Build(False);
      if not Result then
        AResult.AddCheck(False, Format(RSTstDepFailed, [LItem.Id, ACell.ToText()]) +
          LShapeText + DoReportsText(LCompiler.GetErrors()) + DoOutputTail(LOutput));
    finally
      LCompiler.Free();
    end;
  finally
    LOutput.Free();
  end;
end;

function TPCTestSuite.DoBuildDeps(const AIndex: Integer; const ACell: TPCTestCell;
  var AResult: TPCTestResult): Boolean;
var
  LJ: Integer;
begin
  // Rebuilt before each cell, in that cell, in graph order; never tallied
  for LJ in DoChainOf(AIndex) do
  begin
    if not DoBuildDep(LJ, ACell, AResult) then
      Exit(False);
  end;
  Result := True;
end;

function TPCTestSuite.DoBuildFiles(const AMainFile: string; const AMain: TPCModule): TArray<string>;
var
  LFiles: TList<string>;
  LPending: TList<TPCModule>;
  LSeen: TList<TPCModule>;
  LModule: TPCModule;
  LImport: TPCImport;
  LDirective: TPCDirective;

  procedure DoAdd(const AFile: string);
  var
    LFile: string;
  begin
    // A file that does not exist was never read (a test naming a missing
    // file): it holds no markers
    if (AFile = '') or (not FileExists(AFile)) then
      Exit;
    for LFile in LFiles do
    begin
      if TUtils.SamePath(LFile, AFile) then
        Exit;
    end;
    LFiles.Add(AFile);
  end;

begin
  // The files this build read: the main file, every module the parser
  // loaded through the imports, every @addsourcefile
  LFiles := TList<string>.Create();
  LPending := TList<TPCModule>.Create();
  LSeen := TList<TPCModule>.Create();
  try
    DoAdd(AMainFile);
    if AMain <> nil then
      LPending.Add(AMain);
    while LPending.Count > 0 do
    begin
      LModule := LPending[LPending.Count - 1];
      LPending.Delete(LPending.Count - 1);
      if LSeen.Contains(LModule) then
        Continue;
      LSeen.Add(LModule);
      DoAdd(LModule.SourceFile);
      for LDirective in LModule.Directives do
      begin
        if (LDirective.DirectiveKind = bdAddSourceFile) and (LDirective.Args.Count > 0) and
           LDirective.Args[0].HasValue then
          DoAdd(LDirective.Args[0].ResolvedText);
      end;
      for LImport in LModule.Imports do
      begin
        if LImport.ImportedModule <> nil then
          LPending.Add(LImport.ImportedModule);
      end;
    end;
    Result := LFiles.ToArray();
  finally
    LSeen.Free();
    LPending.Free();
    LFiles.Free();
  end;
end;

procedure TPCTestSuite.DoCheckModuleKind(const AItem: TPCTestItem; const ACompiler: TPCCompiler;
  var AResult: TPCTestResult);
var
  LModule: TPCModule;
  LWant: set of TPCModuleKind;
  LWantText: string;
  LKind: TPCModuleKind;
begin
  // The kind says what the file must be: run / tests an exe, dep a dll or
  // lib, build anything that builds, unit a unit; an error test any
  LModule := ACompiler.GetMainModule();
  if LModule = nil then
    Exit;
  case AItem.Kind of
    skRun, skTests:
      LWant := [mkExe];
    skDep:
      LWant := [mkDll, mkLib];
    skBuild:
      LWant := [mkExe, mkDll, mkLib];
    skUnit:
      LWant := [mkUnit];
  else
    Exit;
  end;
  if LModule.ModuleKind in LWant then
    Exit;

  LWantText := '';
  for LKind := Low(TPCModuleKind) to High(TPCModuleKind) do
  begin
    if LKind in LWant then
    begin
      if LWantText <> '' then
        LWantText := LWantText + '/';
      LWantText := LWantText + PC_CMP_KIND_TEXT[LKind];
    end;
  end;
  AResult.AddCheck(False, Format(RSTstWrongModuleKind, [PC_TS_KIND_TEXT[AItem.Kind],
    PC_CMP_KIND_TEXT[LModule.ModuleKind], LWantText]));
end;

procedure TPCTestSuite.DoCheckCell(const ACompiler: TPCCompiler; const ACell: TPCTestCell;
  var AResult: TPCTestResult);
begin
  // The cell must say what ran: a file directive that won over it is
  // reported, so the spec lists the cell the file really builds in
  if ACompiler.GetTarget() <> ACell.Target then
    AResult.AddCheck(False, Format(RSTstCellOverridden, [PC_CMP_KEY_TARGET,
      ACompiler.GetTarget(), ACell.Target]));
  if ACompiler.GetOptimizeLevel() <> ACell.OptLevel then
    AResult.AddCheck(False, Format(RSTstCellOverridden, [PC_CMP_KEY_OPTIMIZE,
      PC_CMP_OPTIMIZE_TEXT[ACompiler.GetOptimizeLevel()], PC_CMP_OPTIMIZE_TEXT[ACell.OptLevel]]));
  if ACompiler.GetSubsystem() <> ACell.Subsystem then
    AResult.AddCheck(False, Format(RSTstCellOverridden, [PC_CMP_KEY_SUBSYSTEM,
      PC_CMP_SUBSYSTEM_TEXT[ACompiler.GetSubsystem()], PC_CMP_SUBSYSTEM_TEXT[ACell.Subsystem]]));
end;

procedure TPCTestSuite.DoCheckMarkers(const AItem: TPCTestItem; const ACompiler: TPCCompiler;
  const ABuilt: Boolean; const AOutput: TList<string>; var AResult: TPCTestResult);
var
  LMarkers: TArray<TPCTestMarker>;
  LMarker: TPCTestMarker;
  LFile: string;
  LBefore: Integer;
  LText: string;
  LI: Integer;
  LWantsError: Boolean;
  LUnexpected: TArray<string>;
  LMissing: TArray<string>;
begin
  // The markers of exactly the files this build read; a malformed one is
  // this cell's failure (its report taken back out of the suite's TErrors)
  LMarkers := [];
  LBefore := FErrors.Count();
  for LFile in DoBuildFiles(AItem.Spec.Filename, ACompiler.GetMainModule()) do
  begin
    if not FScanner.ScanMarkers(LFile, LMarkers) then
    begin
      LText := Format(RSTstMarkersUnread, [LFile]);
      for LI := LBefore to FErrors.Count() - 1 do
        LText := LText + #10 + TPCTestReports.ReportText(FErrors, FErrors.GetItems()[LI]);
      FErrors.TruncateTo(LBefore);
      AResult.AddCheck(False, LText);
      Exit;
    end;
  end;

  LWantsError := False;
  for LMarker in LMarkers do
  begin
    if LMarker.Severity in [esError, esFatal] then
      LWantsError := True;
  end;
  if (AItem.Kind = skError) and (not LWantsError) then
    AResult.AddCheck(False, RSTstErrorNoMarker)
  else if (AItem.Kind <> skError) and LWantsError then
    AResult.AddCheck(False, RSTstOnlyErrorKind);

  TPCTestReports.Match(ACompiler.GetErrors(), LMarkers, AItem.Spec.AllowWarnings,
    LUnexpected, LMissing);
  if Length(LUnexpected) = 0 then
    AResult.AddCheck(True, RSTstReportsMarked)
  else
    AResult.AddCheck(False, RSTstReportsMarked + #10 + string.Join(#10, LUnexpected));
  if Length(LMissing) = 0 then
    AResult.AddCheck(True, RSTstMarkersReported)
  else
    AResult.AddCheck(False, RSTstMarkersReported + #10 + string.Join(#10, LMissing));

  // It builds exactly when no ERROR / FATAL marker exists
  if ABuilt = (not LWantsError) then
    AResult.AddCheck(True, Format(RSTstBuildsAsMarked, [BoolToStr(ABuilt, True)]))
  else
    AResult.AddCheck(False, Format(RSTstBuildsAsMarked, [BoolToStr(ABuilt, True)]) +
      DoOutputTail(AOutput));
end;

function TPCTestSuite.DoWslAvailable(): Boolean;
var
  LExit: DWORD;
begin
  // Asked once per suite: wsl.exe runs a command that does nothing
  if not FWslChecked then
  begin
    FWslChecked := True;
    FWslAvailable := False;
    FWslReason := '';
    LExit := 1;
    try
      TUtils.CaptureConsoleOutput('', PChar(PC_TS_WSL_EXE), PChar(PC_TS_WSL_PROBE),
        TPath.GetDirectoryName(ParamStr(0)), LExit, nil,
        procedure(const ALine: string; const AUserData: Pointer)
        begin
          // The probe prints nothing worth keeping
        end);
      FWslAvailable := LExit = 0;
    except
      on E: Exception do
        FWslReason := E.Message;
    end;
  end;
  Result := FWslAvailable;
end;

function TPCTestSuite.DoRunArtifact(const AIsWindows: Boolean; const AArtifact: string;
  const AArgs: string; const AWorkDir: string; const AStdin: string; out AOutput: string;
  out AExitCode: Integer; out ARaised: string): Boolean;
var
  LExit: DWORD;
  LBuilder: TStringBuilder;
  LSource: TFileStream;
  LHost: TPtyStreamHost;
begin
  // As pcpp -r: in AWorkDir, with AArgs; over pipes, stdout and stderr in
  // written order; stdin AStdin's bytes ('' = NUL), as 'prog < file'
  ARaised := '';
  AOutput := '';
  LExit := PC_TS_NO_EXIT;
  LSource := nil;
  LHost := nil;
  LBuilder := TStringBuilder.Create();
  try
    if AStdin <> '' then
    begin
      try
        LSource := TFileStream.Create(AStdin, fmOpenRead or fmShareDenyWrite);
      except
        on E: Exception do
        begin
          ARaised := Format(RSTstStdinUnread, [AStdin, E.Message]);
          AExitCode := Integer(LExit);
          Exit(False);
        end;
      end;
      // The host only hands the file's handle to the child as its stdin
      LHost := TPtyStreamHost.Create();
      LHost.Init(LSource.Handle);
    end;

    try
      if AIsWindows then
        TUtils.RunPE(AArtifact, AArgs, AWorkDir, LExit, nil,
          procedure(const ALine: string; const AUserData: Pointer)
          begin
            LBuilder.Append(ALine).Append(#10);
          end, True, LHost)
      else
        TUtils.RunElf(AArtifact, AArgs, AWorkDir, LExit, nil,
          procedure(const ALine: string; const AUserData: Pointer)
          begin
            LBuilder.Append(ALine).Append(#10);
          end, True, LHost);
    except
      on E: Exception do
        ARaised := E.Message;
    end;
    AOutput := LBuilder.ToString();
  finally
    LHost.Free();
    LSource.Free();
    LBuilder.Free();
  end;
  AExitCode := Integer(LExit);
  Result := ARaised = '';
end;

class function TPCTestSuite.DoWithoutHeapReport(const AText: string): string;
var
  LLines: TArray<string>;
  LKept: TList<string>;
  LLine: string;
begin
  // AText normalized (LF, no trailing blanks or empty lines): every [Heap]
  // line goes, wherever it stands. The report is printed by the module that
  // exits, so a DLL's comes before the host's later lines, not at the tail
  LLines := AText.Split([#10]);
  LKept := TList<string>.Create();
  try
    for LLine in LLines do
    begin
      if not LLine.StartsWith(PC_TS_HEAP_REPORT_PREFIX) then
        LKept.Add(LLine);
    end;
    Result := string.Join(#10, LKept.ToArray());
  finally
    LKept.Free();
  end;
end;

procedure TPCTestSuite.DoCheckRunOutput(const AItem: TPCTestItem; const ACell: TPCTestCell;
  const AGot: string; const AExitCode: Integer; var AResult: TPCTestResult);
var
  LExpect: TPCTestExpect;
  LWant: string;
  LOutRoot: string;
  LDifference: string;
begin
  if AExitCode = AItem.Spec.ExitCode then
    AResult.AddCheck(True, Format(RSTstExitCode, [AItem.Spec.ExitCode, AExitCode]))
  else
    AResult.AddCheck(False, Format(RSTstExitCode, [AItem.Spec.ExitCode, AExitCode]) + #10 + AGot);

  // No expect for this target = the program prints nothing
  LWant := '';
  if AItem.Spec.ExpectFor(ACell.Target, LExpect) then
  begin
    if LExpect.IsFile then
    begin
      try
        LWant := TFile.ReadAllText(LExpect.FilePath, TEncoding.UTF8);
      except
        on E: Exception do
        begin
          AResult.AddCheck(False, Format(RSTstExpectFileUnread, [LExpect.FilePath, E.Message]));
          Exit;
        end;
      end;
    end
    else
    begin
      // Expect lines (and a cli test's args, DoRunCli): <DIR> is the test
      // file's folder, in '/' form; <OUT> (expect lines only) the suite's
      // output root, in '/' form without a trailing separator
      LWant := LExpect.Text.Replace(PC_TS_DIR_MARK, PCTestFolderOf(AItem.Spec.Filename));
      LOutRoot := FOutputRoot.Replace('/', '\');
      LOutRoot := ExcludeTrailingPathDelimiter(LOutRoot).Replace('\', '/');
      LWant := LWant.Replace(PC_TS_OUT_MARK, LOutRoot);
    end;
  end;

  LWant := TPCTestText.Normalize(LWant);
  // The heap report is the debug runtime's: a cell at another level
  // expects the output without it
  if ACell.OptLevel <> olDebug then
    LWant := DoWithoutHeapReport(LWant);

  LDifference := TPCTestText.FirstDifference(LWant, AGot);
  if LDifference = '' then
    AResult.AddCheck(True, RSTstOutputAsExpected)
  else
    AResult.AddCheck(False, RSTstOutputAsExpected + #10 + LDifference);
end;

procedure TPCTestSuite.DoCheckTestsOutput(const AGot: string; const AExitCode: Integer;
  var AResult: TPCTestResult);
var
  LLines: TArray<string>;
  LI: Integer;
  LMatch: TMatch;
  LFound: Boolean;
  LPassed: Integer;
  LFailed: Integer;
  LTotal: Integer;
  LWantExit: Integer;
begin
  // The runtime's Results: line, the last one printed
  LFound := False;
  LPassed := 0;
  LFailed := 0;
  LTotal := 0;
  LLines := AGot.Split([#10]);
  for LI := High(LLines) downto 0 do
  begin
    LMatch := TRegEx.Match(LLines[LI].Trim(), PC_TS_RESULTS_LINE);
    if LMatch.Success then
    begin
      LPassed := StrToIntDef(LMatch.Groups[1].Value, 0);
      LFailed := StrToIntDef(LMatch.Groups[2].Value, 0);
      LTotal := StrToIntDef(LMatch.Groups[3].Value, 0);
      LFound := True;
      Break;
    end;
  end;
  if not LFound then
  begin
    AResult.AddCheck(False, RSTstNoResultsLine + #10 + AGot);
    Exit;
  end;
  AResult.AddCheck(True, RSTstNoResultsLine);

  // Zero tests proves nothing: a fail
  AResult.AddCheck(LTotal > 0, Format(RSTstZeroTests, [LTotal]));
  if LFailed = 0 then
    AResult.AddCheck(LPassed = LTotal, Format(RSTstTestsFailed, [LFailed, LTotal]))
  else
    AResult.AddCheck(False, Format(RSTstTestsFailed, [LFailed, LTotal]) + #10 + AGot);
  LWantExit := Min(LFailed, PC_TS_EXIT_MAX);
  AResult.AddCheck(AExitCode = LWantExit, Format(RSTstTestsExit, [LWantExit, AExitCode]));
end;

procedure TPCTestSuite.DoRunProgram(const AItem: TPCTestItem; const ACell: TPCTestCell;
  const AArtifact: string; var AResult: TPCTestResult);
var
  LTriple: TPCTargetTriple;
  LIsWindows: Boolean;
  LOutput: string;
  LExitCode: Integer;
  LRaised: string;
  LGot: string;
begin
  LIsWindows := (TPCTargetTriple.Parse(ACell.Target, LTriple) = tsOk) and LTriple.IsWindows();
  if (not LIsWindows) and (not DoWslAvailable()) then
  begin
    // Built and checked; only the run cannot happen here
    AResult.Reason := RSTstNoWsl;
    if FWslReason <> '' then
      AResult.Reason := AResult.Reason + ' (' + FWslReason + ')';
    Exit;
  end;

  // In the program's own folder (the artifact path is in '/' form)
  if not DoRunArtifact(LIsWindows, AArtifact, AItem.Spec.Args, PCTestFolderOf(AArtifact),
    AItem.Spec.Stdin, LOutput, LExitCode, LRaised) then
  begin
    AResult.AddCheck(False, Format(RSTstRunRaised, [LRaised]));
    Exit;
  end;
  AResult.AddCheck(True, RSTstRuns);

  LGot := TPCTestText.Normalize(LOutput);
  if AItem.Kind = skTests then
    DoCheckTestsOutput(LGot, LExitCode, AResult)
  else
    DoCheckRunOutput(AItem, ACell, LGot, LExitCode, AResult);
end;

procedure TPCTestSuite.DoRunSource(const AItem: TPCTestItem; const ACell: TPCTestCell;
  var AResult: TPCTestResult);
var
  LOutput: TList<string>;
  LCompiler: TPCCompiler;
  LPrepared: Boolean;
  LBuilt: Boolean;
begin
  LOutput := TList<string>.Create();
  try
    LCompiler := DoNewCompiler(LOutput);
    try
      DoApplyCell(LCompiler, ACell, AItem.Spec.Defines);
      // A unit is analyzed only; everything else is prepared, then built
      if AItem.Kind = skUnit then
      begin
        LPrepared := LCompiler.Analyze(AItem.Spec.Filename);
        LBuilt := LPrepared;
      end
      else
      begin
        LPrepared := LCompiler.Prepare(AItem.Spec.Filename, '');
        LBuilt := LPrepared and LCompiler.Build(False);
      end;

      if LPrepared then
      begin
        DoCheckModuleKind(AItem, LCompiler, AResult);
        if AItem.Kind <> skUnit then
          DoCheckCell(LCompiler, ACell, AResult);
      end;
      DoCheckMarkers(AItem, LCompiler, LBuilt, LOutput, AResult);

      // The program runs only when everything about its build held
      if (AItem.Kind in [skRun, skTests]) and LBuilt and (AResult.FailedCount() = 0) then
        DoRunProgram(AItem, ACell, LCompiler.GetArtifactPath(), AResult);
    finally
      LCompiler.Free();
    end;
  finally
    LOutput.Free();
  end;
end;

procedure TPCTestSuite.DoRunCli(const AItem: TPCTestItem; const ACell: TPCTestCell;
  var AResult: TPCTestResult);
var
  LPcpp: string;
  LOutput: string;
  LExitCode: Integer;
  LRaised: string;
  LArgs: string;
begin
  // pcpp as a user runs it: the compiler beside the suite's host, in the
  // suite's output root, so whatever it writes (its default output folder
  // is the current folder's) lands there and never beside the shipped
  // test. Args name the test's files through <DIR> (the test file's
  // folder, as in expect lines); its output and exit code are compared as
  // a run test's
  if FOutputRoot = '' then
  begin
    AResult.AddCheck(False, Format(RSTstRootMissing, [PC_CMP_DEFAULT_OUTPUT]));
    Exit;
  end;
  try
    LPcpp := TUtils.ResolvePath(PC_TS_PCPP_EXE);
  except
    on E: Exception do
    begin
      AResult.AddCheck(False, Format(RSTstRunRaised, [E.Message]));
      Exit;
    end;
  end;
  LArgs := AItem.Spec.Args.Replace(PC_TS_DIR_MARK, PCTestFolderOf(AItem.Spec.Filename));
  if not DoRunArtifact(True, LPcpp, LArgs, FOutputRoot, '',
    LOutput, LExitCode, LRaised) then
  begin
    AResult.AddCheck(False, Format(RSTstRunRaised, [LRaised]));
    Exit;
  end;
  AResult.AddCheck(True, RSTstRuns);
  // pcpp colours its text even over pipes, and a run program's console
  // leaves its title: presentation, not what a cli test checks, so they are
  // taken out. So are pcpp's build progress lines, whose count is the
  // machine's and the zig cache's (cli only)
  LOutput := TPCTestText.StripTerminalCodes(LOutput);
  LOutput := TPCTestText.DropBuildProgress(LOutput);
  DoCheckRunOutput(AItem, ACell, TPCTestText.Normalize(LOutput), LExitCode, AResult);
end;

procedure TPCTestSuite.DoCollectSources(const ADir: string; const AFiles: TList<string>);
var
  LFile: string;
  LSub: string;
  LSubName: string;
begin
  // Every source file under ADir, folders named fixtures left out (with
  // everything below them): their files are inputs, never tests. RTL calls
  // that raise are the caller's (DoDiscoverRoot reports them)
  for LFile in TDirectory.GetFiles(ADir, '*.' + PC_SRC_EXT, TSearchOption.soTopDirectoryOnly) do
    AFiles.Add(LFile);
  for LSub in TDirectory.GetDirectories(ADir) do
  begin
    // The folder's own name: after the last separator of either kind
    LSubName := LSub.Substring(LSub.LastDelimiter('/\') + 1);
    if SameText(LSubName, PC_TS_FIXTURES_FOLDER) then
      Continue;
    DoCollectSources(LSub, AFiles);
  end;
end;

procedure TPCTestSuite.DoRunCode(const AItem: TPCTestItem; const ACell: TPCTestCell;
  var AResult: TPCTestResult);
var
  LCase: TPCTestCase;
  LError: string;
begin
  // SetupClass once per run, before the class's first test
  LCase := FCases[AItem.CaseIndex];
  if not FCaseSetups.TryGetValue(AItem.CaseIndex, LError) then
  begin
    LCase.SetRoots(FRepoRoot, FFixtureRoot, FOutputRoot);
    LCase.RunSetupClass(LError);
    FCaseSetups.Add(AItem.CaseIndex, LError);
  end;
  if LError <> '' then
    AResult.AddCheck(False, LError)
  else
    LCase.RunTest(AItem.TestIndex, ACell, AResult);
end;

function TPCTestSuite.DoRunOne(const ARun: TPCTestRun): TPCTestResult;
var
  LItem: TPCTestItem;
  LWatch: TStopwatch;
begin
  LItem := FItems[ARun.ItemIndex];
  Result.Clear();
  Result.Id := LItem.Id;
  Result.Kind := LItem.Kind;
  Result.Cell := ARun.Cell;

  LWatch := TStopwatch.StartNew();
  // Nothing out of one cell ends the run: an exception is its failed check
  try
    if DoBuildDeps(ARun.ItemIndex, ARun.Cell, Result) then
    begin
      if LItem.Kind = skCode then
        DoRunCode(LItem, ARun.Cell, Result)
      else if LItem.Kind = skCli then
        DoRunCli(LItem, ARun.Cell, Result)
      else
        DoRunSource(LItem, ARun.Cell, Result);
    end;
  except
    on E: Exception do
      Result.AddCheck(False, Format(RSTstPhaseRaised, [RSTstPhaseTest, E.ClassName, E.Message]));
  end;
  Result.DurationMs := LWatch.ElapsedMilliseconds;
  Result.Settle();
end;

procedure TPCTestSuite.DoTeardownCases();
var
  LPair: TPair<Integer, string>;
  LError: string;
begin
  // TeardownClass for every class whose SetupClass ran
  for LPair in FCaseSetups do
  begin
    if LPair.Value <> '' then
      Continue;
    if not FCases[LPair.Key].RunTeardownClass(LError) then
    begin
      FTeardownFailed := True;
      DoPrintLn(COLOR_RED + FCases[LPair.Key].GetAreaName() + ': ' + LError);
    end;
  end;
  FCaseSetups.Clear();
end;

{ Report }

procedure TPCTestSuite.DoPrintLn(const ALine: string);
begin
  // The one place a line leaves the suite
  if Assigned(FWriter) then
    FWriter(ALine)
  else
  begin
    TConsole.PrintLn(ALine);
    // The RTL flushes Output per line only on a console: redirected to a
    // log or a pipe it holds lines back, and whoever watches the run (a
    // progress check, a stop probe) would see each result late
    Flush(Output);
  end;
end;

procedure TPCTestSuite.DoPrintData(const ALine: string);
begin
  // A line a program reads (-rpc's JSON): exactly the text, no colour or
  // reset sequence around it, which TConsole.PrintLn adds
  if Assigned(FWriter) then
    FWriter(ALine)
  else
  begin
    WriteLn(Output, ALine);
    Flush(Output);
  end;
end;

procedure TPCTestSuite.DoPrintLn();
begin
  DoPrintLn('');
end;

function TPCTestSuite.DoResultsFile(): string;
begin
  // Resolved onto the output root: one separator form in every printed path
  Result := '';
  if FOutputRoot = '' then
    Exit;
  try
    Result := TUtils.ResolvePath(PC_TS_RESULTS_FILE, FOutputRoot);
  except
    on E: Exception do
      FErrors.Add(esWarning, PC_ERR_TS_109, RSTstResultsWriteFailed, [PC_TS_RESULTS_FILE, E.Message]);
  end;
end;

procedure TPCTestSuite.DoPrintResult(const AResult: TPCTestResult);
var
  LStatus: string;
  LCheck: TPCTestCheck;
  LLines: TArray<string>;
  LMark: string;
  LI: Integer;
  LFirst: string;
begin
  case AResult.Status of
    trPass:
      LStatus := COLOR_GREEN + RSTstStatusPass + COLOR_RESET;
    trFail:
      LStatus := COLOR_RED + RSTstStatusFail + COLOR_RESET;
  else
    LStatus := COLOR_YELLOW + RSTstStatusSkip + COLOR_RESET;
  end;
  DoPrintLn(Format(RSTstResultLine, [LStatus, AResult.Id, AResult.Cell.ToText(),
    AResult.DurationMs]));
  if AResult.Status = trSkip then
    DoPrintLn(COLOR_YELLOW + Format(RSTstSkipReason, [AResult.Reason]));

  // A failed cell shows its failed checks; -v shows every check
  if (AResult.Status <> trFail) and (not FVerbose) then
    Exit;
  for LCheck in AResult.Checks do
  begin
    if LCheck.Passed and (not FVerbose) then
      Continue;
    if LCheck.Passed then
      LMark := COLOR_GREEN + RSTstCheckOk + COLOR_RESET
    else
      LMark := COLOR_RED + RSTstCheckFail + COLOR_RESET;
    LLines := LCheck.Text.Split([#10]);
    if Length(LLines) = 0 then
      LLines := [''];
    LFirst := LLines[0];
    if LCheck.SectionTitle <> '' then
      LFirst := '[' + LCheck.SectionTitle + '] ' + LFirst;
    DoPrintLn(Format(RSTstCheckLine, [LMark, LFirst]));
    for LI := 1 to High(LLines) do
      DoPrintLn(PC_TS_CHECK_INDENT + LLines[LI]);
  end;
end;

procedure TPCTestSuite.DoPrintSummary(const ADurationMs: Int64; const ASelected: Integer;
  const AStopped: Boolean);
var
  LCells: TList<string>;
  LResult: TPCTestResult;
  LCellText: string;
  LPassed: Integer;
  LFailed: Integer;
  LSkipped: Integer;
  LTotalPassed: Integer;
  LTotalFailed: Integer;
  LTotalSkipped: Integer;
begin
  // The matrix: one line per cell, then the totals and every failing cell
  LCells := TList<string>.Create();
  try
    for LResult in FResults do
    begin
      if not LCells.Contains(LResult.Cell.ToText()) then
        LCells.Add(LResult.Cell.ToText());
    end;

    DoPrintLn();
    DoPrintLn(COLOR_BOLD + RSTstSummaryTitle);
    LTotalPassed := 0;
    LTotalFailed := 0;
    LTotalSkipped := 0;
    for LCellText in LCells do
    begin
      LPassed := 0;
      LFailed := 0;
      LSkipped := 0;
      for LResult in FResults do
      begin
        if LResult.Cell.ToText() <> LCellText then
          Continue;
        case LResult.Status of
          trPass:
            Inc(LPassed);
          trFail:
            Inc(LFailed);
        else
          Inc(LSkipped);
        end;
      end;
      Inc(LTotalPassed, LPassed);
      Inc(LTotalFailed, LFailed);
      Inc(LTotalSkipped, LSkipped);
      DoPrintLn(Format(RSTstSummaryCell, [LCellText, LPassed, LFailed, LSkipped]));
    end;
    DoPrintLn(Format(RSTstSummaryTotal, [LTotalPassed, LTotalFailed, LTotalSkipped,
      ADurationMs]));

    if LTotalFailed > 0 then
    begin
      DoPrintLn(COLOR_RED + RSTstSummaryFailures);
      for LResult in FResults do
      begin
        if LResult.Status = trFail then
          DoPrintLn(COLOR_RED + Format(RSTstSummaryFailure, [LResult.Id,
            LResult.Cell.ToText()]));
      end;
    end;

    // A stopped run never says ALL PASSED: a cell it selected did not run,
    // or the last one was ended by a forced stop (DoRunSelected's verdict)
    if AStopped then
      DoPrintLn(COLOR_YELLOW + Format(RSTstSummaryStopped, [FResults.Count, ASelected]))
    else if (LTotalFailed = 0) and (not FTeardownFailed) then
      DoPrintLn(COLOR_GREEN + RSTstAllPassed)
    else
      DoPrintLn(COLOR_RED + RSTstSomeFailed);
  finally
    LCells.Free();
  end;
end;

procedure TPCTestSuite.DoWriteResults();
var
  LFile: string;
  LBuilder: TStringBuilder;
  LResult: TPCTestResult;
begin
  // '<STATUS> <id> <cell>' per result: -failed reads the FAIL lines back
  LFile := DoResultsFile();
  LBuilder := TStringBuilder.Create();
  try
    for LResult in FResults do
      LBuilder.Append(PC_TS_RESULT_WORDS[LResult.Status]).Append(' ').Append(LResult.Id)
        .Append(' ').Append(LResult.Cell.ToText()).Append(sLineBreak);
    try
      ForceDirectories(FOutputRoot);
      // UTF-8 without a BOM: a plain line file other tools read too
      // (TFile.WriteAllText with TEncoding.UTF8 writes the preamble)
      TFile.WriteAllBytes(LFile, TEncoding.UTF8.GetBytes(LBuilder.ToString()));
    except
      on E: Exception do
      begin
        FErrors.Add(esWarning, PC_ERR_TS_109, RSTstResultsWriteFailed, [LFile, E.Message]);
        FErrors.Flush();
      end;
    end;
  finally
    LBuilder.Free();
  end;
end;

procedure TPCTestSuite.DoPrintHelp();
begin
  DoPrintLn(COLOR_BOLD + RSTstHelpTitle);
  DoPrintLn(RSTstHelpUsage);
  DoPrintLn(RSTstHelpAll);
  DoPrintLn(RSTstHelpIds);
  DoPrintLn(RSTstHelpList);
  DoPrintLn(RSTstHelpFromTo);
  DoPrintLn(RSTstHelpTarget);
  DoPrintLn(RSTstHelpOpt);
  DoPrintLn(RSTstHelpGui);
  DoPrintLn(RSTstHelpKind);
  DoPrintLn(RSTstHelpFailed);
  DoPrintLn(RSTstHelpVerbose);
  DoPrintLn(RSTstHelpRoot);
  DoPrintLn(RSTstHelpRpc);
  DoPrintLn(RSTstHelpHelp);
  DoPrintLn(Format(RSTstHelpStop, [PC_TS_STOP_FILE]));
  DoPrintLn(RSTstHelpExit);
end;

function TPCTestSuite.DoParseArgs(const AArgs: TArray<string>; out AFilter: TPCTestFilter;
  out AList: Boolean; out AHelp: Boolean; out ASelected: Boolean): Boolean;
var
  LI: Integer;
  LArg: string;
  LValue: string;
  LOpt: TPCOptimizeLevel;
  LKind: TPCTestKind;
  LFound: Boolean;

  // The value after a switch; False (reported) when there is none
  function DoValue(): Boolean;
  begin
    Result := LI < High(AArgs);
    if Result then
    begin
      Inc(LI);
      LValue := AArgs[LI];
    end
    else
      DoPrintLn(COLOR_RED + Format(RSTstArgNeedsValue, [LArg]));
  end;

begin
  AFilter.Clear();
  AList := False;
  AHelp := False;
  ASelected := False;
  Result := False;

  LI := 0;
  while LI <= High(AArgs) do
  begin
    LArg := AArgs[LI];
    if (LArg = PC_TS_ARG_HELP) or (LArg = PC_TS_ARG_HELP_LONG) then
      AHelp := True
    else if LArg = PC_TS_ARG_ALL then
    begin
      AFilter.AllCells := True;
      ASelected := True;
    end
    else if LArg = PC_TS_ARG_LIST then
    begin
      AList := True;
      // An optional glob after it
      if (LI < High(AArgs)) and (not AArgs[LI + 1].StartsWith('-')) then
      begin
        Inc(LI);
        AFilter.Patterns := AFilter.Patterns + [AArgs[LI]];
      end;
    end
    else if LArg = PC_TS_ARG_FROM then
    begin
      if not DoValue() then
        Exit;
      AFilter.FromId := LValue;
      ASelected := True;
    end
    else if LArg = PC_TS_ARG_TO then
    begin
      if not DoValue() then
        Exit;
      AFilter.ToId := LValue;
      ASelected := True;
    end
    else if LArg = PC_TS_ARG_TARGET then
    begin
      if not DoValue() then
        Exit;
      if not TPCTestSpecScanner.IsTarget(LValue) then
      begin
        DoPrintLn(COLOR_RED + Format(RSTstBadArgValue, [LArg, LValue,
          TPCTargetTriple.SupportedTargetsText()]));
        Exit;
      end;
      AFilter.Targets := AFilter.Targets + [LValue];
    end
    else if LArg = PC_TS_ARG_OPT then
    begin
      if not DoValue() then
        Exit;
      if not TPCCompiler.FindOptimizeLevel(LValue, LOpt) then
      begin
        DoPrintLn(COLOR_RED + Format(RSTstBadArgValue, [LArg, LValue,
          string.Join(', ', PC_CMP_OPTIMIZE_TEXT)]));
        Exit;
      end;
      AFilter.OptLevels := AFilter.OptLevels + [LOpt];
    end
    else if LArg = PC_TS_ARG_GUI then
      AFilter.Subsystems := AFilter.Subsystems + [stGUI]
    else if LArg = PC_TS_ARG_CONSOLE then
      AFilter.Subsystems := AFilter.Subsystems + [stConsole]
    else if LArg = PC_TS_ARG_KIND then
    begin
      if not DoValue() then
        Exit;
      LFound := False;
      for LKind := Low(TPCTestKind) to High(TPCTestKind) do
      begin
        if PC_TS_KIND_TEXT[LKind] = LValue then
        begin
          Include(AFilter.Kinds, LKind);
          LFound := True;
        end;
      end;
      if not LFound then
      begin
        DoPrintLn(COLOR_RED + Format(RSTstBadArgValue, [LArg, LValue,
          string.Join(', ', PC_TS_KIND_TEXT)]));
        Exit;
      end;
    end
    else if LArg = PC_TS_ARG_FAILED then
    begin
      AFilter.FailedOnly := True;
      ASelected := True;
    end
    else if LArg = PC_TS_ARG_VERBOSE then
      AFilter.Verbose := True
    else if LArg.StartsWith('-') then
    begin
      DoPrintLn(COLOR_RED + Format(RSTstBadArg, [LArg]));
      Exit;
    end
    else
    begin
      AFilter.Patterns := AFilter.Patterns + [LArg];
      ASelected := True;
    end;
    Inc(LI);
  end;
  Result := True;
end;

procedure TPCTestSuite.List(const AFilter: TPCTestFilter);
var
  LItem: TPCTestItem;
  LCell: TPCTestCell;
  LCells: TPCTestCells;
  LCount: Integer;
begin
  LCount := 0;
  for LItem in FItems do
  begin
    if (AFilter.Kinds <> []) and (not (LItem.Kind in AFilter.Kinds)) then
      Continue;
    if not DoMatchesPatterns(LItem.Id, AFilter.Patterns) then
      Continue;

    // The cells a run with the same filter would use (-opt widens a test
    // that names no opt, -t / -gui / -console narrow): what is listed is
    // what runs. A test left with no cell would not run, so it is not listed
    LCells := [];
    for LCell in DoRunCells(LItem, AFilter) do
    begin
      if DoCellAllowed(LCell, AFilter) then
        LCells := LCells + [LCell];
    end;
    if Length(LCells) = 0 then
      Continue;

    Inc(LCount);
    DoPrintLn(Format(RSTstListLine, [LItem.Id, PC_TS_KIND_TEXT[LItem.Kind],
      Length(LCells)]));
    if Length(LItem.Deps) > 0 then
      DoPrintLn(Format(RSTstListDeps, [string.Join(', ', LItem.Deps)]));
    if AFilter.Verbose then
    begin
      for LCell in LCells do
        DoPrintLn(Format(RSTstListCell, [LCell.ToText()]));
    end;
  end;
  DoPrintLn(Format(RSTstListCount, [LCount, FUnspecced.Count]));
end;

function TPCTestSuite.Run(const AFilter: TPCTestFilter): Integer;
begin
  // One run per output folder: the control channel's name being taken
  // means a testbed already runs here (reported by Start)
  if not FControl.Start(FOutputRoot) then
  begin
    FErrors.PrintErrors();
    Exit(PC_TS_EXIT_FAILED);
  end;

  // Whatever way the run ends, the channel says so with its exit code
  Result := PC_TS_EXIT_FAILED;
  try
    Result := DoRunFiltered(AFilter);
  finally
    FControl.Finish(Result);
  end;
end;

function TPCTestSuite.DoRunFiltered(const AFilter: TPCTestFilter): Integer;
var
  LRuns: TList<TPCTestRun>;
  LResult: TPCTestResult;
  LWatch: TStopwatch;
  LFailed: Boolean;
  LStopped: Boolean;
  LFailedCount: Integer;
begin
  FVerbose := AFilter.Verbose;
  FTeardownFailed := False;
  FResults.Clear();

  if not FDiscovered then
    Discover();
  if FErrors.HasErrors() then
  begin
    FErrors.PrintErrors();
    DoPrintLn(COLOR_RED + Format(RSTstDiscoveryFailed, [FErrors.ErrorCount()]));
    Exit(PC_TS_EXIT_FAILED);
  end;
  // Warnings of discovery are shown, they stop nothing
  FErrors.PrintErrors();

  // -from / -to name tests in order (reported here, for every caller)
  if not DoCheckRange(AFilter) then
    Exit(PC_TS_EXIT_BAD_ARGS);

  LRuns := TList<TPCTestRun>.Create();
  try
    if not DoSelect(AFilter, LRuns, LFailedCount) then
      Exit(PC_TS_EXIT_BAD_ARGS);
    if LRuns.Count = 0 then
    begin
      // -failed after a clean run has nothing to do. Anything else matched
      // nothing, -failed whose other parts leave out every failed cell too:
      // a mistyped glob must not pass as a clean run
      if AFilter.FailedOnly and (LFailedCount = 0) then
      begin
        DoPrintLn(RSTstNoFailures);
        Exit(PC_TS_EXIT_PASSED);
      end;
      DoPrintLn(RSTstNothingSelected);
      Exit(PC_TS_EXIT_BAD_ARGS);
    end;

    LWatch := TStopwatch.StartNew();
    FCaseSetups.Clear();
    LStopped := DoRunSelected(LRuns);
    DoTeardownCases();
    DoPrintSummary(LWatch.ElapsedMilliseconds, LRuns.Count, LStopped);
    DoWriteResults();
  finally
    LRuns.Free();
  end;

  LFailed := FTeardownFailed;
  for LResult in FResults do
  begin
    if LResult.Status = trFail then
      LFailed := True;
  end;
  // Stopped says the run is incomplete, whatever the cells that ran did
  if LStopped then
    Result := PC_TS_EXIT_STOPPED
  else if LFailed then
    Result := PC_TS_EXIT_FAILED
  else
    Result := PC_TS_EXIT_PASSED;
end;

function TPCTestSuite.DoRunSelected(const ARuns: TList<TPCTestRun>): Boolean;
var
  LRun: TPCTestRun;
  LResult: TPCTestResult;
  LPresses: Integer;
  LI: Integer;
  LCellIndex: Integer;
  LForced: Boolean;
begin
  FControl.BeginRun(ARuns.Count, DoCountCells(ARuns));
  LCellIndex := 0;
  LForced := False;

  // The stop thread runs only while cells do; its presses are read
  // between cells (first press: no next cell) and after one (second
  // press: the cell's processes were ended, so its result is no verdict)
  FStop.Start(FOutputRoot);
  try
    for LI := 0 to ARuns.Count - 1 do
    begin
      LRun := ARuns[LI];
      if FStop.StopRequested() then
      begin
        FControl.SetStopping();
        Exit(True);
      end;
      if (LI = 0) or (not LRun.Cell.SameAs(ARuns[LI - 1].Cell)) then
      begin
        Inc(LCellIndex);
        FControl.BeginCell(LCellIndex, LRun.Cell.ToText());
      end;
      FControl.BeginTest(LI + 1, FItems[LRun.ItemIndex].Id);
      LPresses := FStop.Presses();
      LResult := DoRunOne(LRun);
      if FStop.ForceRequested() and (LPresses < PC_TS_STOP_FORCE) then
      begin
        LResult.Reason := RSTstStoppedReason;
        LResult.Status := trSkip;
        LForced := True;
        DoPrintLn(COLOR_YELLOW + RSTstForceNotice);
      end
      else if FStop.StopRequested() and (LPresses = 0) then
        DoPrintLn(COLOR_YELLOW + RSTstStopNotice);
      FResults.Add(LResult);
      DoPrintResult(LResult);
      DoPublishResult(LResult);
    end;
    // Stopped = the run is incomplete: a test never started, or the one
    // running was ended by a forced stop (no verdict), the last one included
    Result := FStop.StopRequested() and ((FResults.Count < ARuns.Count) or LForced);
  finally
    FStop.Halt();
  end;
end;

function TPCTestSuite.DoCountCells(const ARuns: TList<TPCTestRun>): Integer;
var
  LI: Integer;
begin
  // The runs come cell-major (DoOrderByCell): a new cell starts wherever
  // the cell changes
  Result := 0;
  for LI := 0 to ARuns.Count - 1 do
  begin
    if (LI = 0) or (not ARuns[LI].Cell.SameAs(ARuns[LI - 1].Cell)) then
      Inc(Result);
  end;
end;

procedure TPCTestSuite.DoPublishResult(const AResult: TPCTestResult);
var
  LOutcome: TPCTestControlOutcome;
begin
  if AResult.Status = trPass then
    LOutcome := coPass
  else if AResult.Status = trFail then
    LOutcome := coFail
  else
    LOutcome := coSkip;
  FControl.EndTest(LOutcome, AResult.Id, AResult.Cell.ToText());
  if FStop.StopRequested() then
    FControl.SetStopping();
end;

function TPCTestSuite.DoTakeRoots(const AArgs: TArray<string>; out ARest: TArray<string>): Boolean;
var
  LI: Integer;
  LRoots: TArray<string>;
  LRoot: string;
begin
  // -root <dir> pairs come out of the arguments; the rest go to the filter
  Result := False;
  ARest := [];
  LRoots := [];
  LI := 0;
  while LI <= High(AArgs) do
  begin
    if AArgs[LI] = PC_TS_ARG_ROOT then
    begin
      if LI = High(AArgs) then
      begin
        DoPrintLn(COLOR_RED + Format(RSTstArgNeedsValue, [PC_TS_ARG_ROOT]));
        Exit;
      end;
      Inc(LI);
      LRoots := LRoots + [AArgs[LI]];
    end
    else
      ARest := ARest + [AArgs[LI]];
    Inc(LI);
  end;

  // The roots given replace the host's tests and examples; a root that
  // does not exist is reported by discovery (TS0101)
  if Length(LRoots) > 0 then
  begin
    FSourceRoots.Clear();
    FExampleRoots.Clear();
    for LRoot in LRoots do
      AddSourceRoot(LRoot);
    FRootsOnly := True;
    FDiscovered := False;
  end;
  Result := True;
end;

{ Control channel }

procedure TPCTestSuite.DoControlCommand(const ACommand: TPCTestControlCommand);
begin
  // On the stop thread: a command is a stop press, so it takes the same
  // path as the key and the stop file (stop = the first press, abort =
  // up to the press that ends the running test's processes)
  if ACommand = ccStop then
  begin
    if not FStop.StopRequested() then
      FStop.Press();
  end
  else if ACommand = ccAbort then
  begin
    while not FStop.ForceRequested() do
      FStop.Press();
  end;
  FControl.SetStopping();
end;

function TPCTestSuite.DoRpc(const AArgs: TArray<string>): Integer;
var
  LCommand: string;
  LSeconds: Integer;
  LClient: TPCTestControlClient;
  LBlock: TPCTestControlBlock;
begin
  // testbed -rpc <command> [seconds]
  if Length(AArgs) < 2 then
  begin
    DoPrintLn(COLOR_RED + Format(RSTstRpcBadCommand, ['""']));
    Exit(PC_TS_EXIT_BAD_ARGS);
  end;
  LCommand := AArgs[1].ToLower();
  LSeconds := 0;
  if (LCommand <> PC_TS_RPC_STATUS) and (LCommand <> PC_TS_RPC_FAILURES) and
    (LCommand <> PC_TS_RPC_STOP) and (LCommand <> PC_TS_RPC_ABORT) and
    (LCommand <> PC_TS_RPC_WAIT) then
  begin
    DoPrintLn(COLOR_RED + Format(RSTstRpcBadCommand, [AArgs[1]]));
    Exit(PC_TS_EXIT_BAD_ARGS);
  end;
  // wait [seconds]: no seconds (or 0) waits for as long as the run takes
  if (LCommand = PC_TS_RPC_WAIT) and (Length(AArgs) > 2) and
    ((not TryStrToInt(AArgs[2], LSeconds)) or (LSeconds < 0)) then
  begin
    DoPrintLn(COLOR_RED + Format(RSTstRpcBadCommand, [PC_TS_RPC_WAIT + ' ' + AArgs[2]]));
    Exit(PC_TS_EXIT_BAD_ARGS);
  end;

  LClient := TPCTestControlClient.Create();
  try
    LClient.SetErrors(FErrors);
    if not LClient.Open(FOutputRoot) then
    begin
      FErrors.PrintErrors();
      DoPrintLn(Format(RSTstRpcNoRun, [FOutputRoot]));
      Exit(PC_TS_EXIT_NO_RUN);
    end;

    if (LCommand = PC_TS_RPC_STATUS) or (LCommand = PC_TS_RPC_FAILURES) then
    begin
      if not LClient.Snapshot(LBlock) then
      begin
        DoPrintLn(COLOR_RED + RSTstRpcLockFailed);
        Exit(PC_TS_EXIT_FAILED);
      end;
      if LCommand = PC_TS_RPC_STATUS then
        DoPrintData(TPCTestControlFormat.StatusJson(LBlock, LClient.OwnerAlive(LBlock)))
      else
        DoPrintData(TPCTestControlFormat.FailuresJson(LBlock));
      Exit(PC_TS_EXIT_PASSED);
    end;

    if LCommand = PC_TS_RPC_STOP then
      Result := DoRpcSend(LClient, ccStop, PC_TS_RPC_STOP)
    else if LCommand = PC_TS_RPC_ABORT then
      Result := DoRpcSend(LClient, ccAbort, PC_TS_RPC_ABORT)
    else
      Result := DoRpcWait(LClient, LSeconds);
  finally
    LClient.Free();
  end;
end;

function TPCTestSuite.DoRpcSend(const AClient: TPCTestControlClient;
  const ACommand: TPCTestControlCommand; const AName: string): Integer;
var
  LSeq: UInt32;
  LBlock: TPCTestControlBlock;
  LWatch: TStopwatch;
begin
  if not AClient.Send(ACommand, LSeq) then
  begin
    DoPrintLn(COLOR_RED + RSTstRpcLockFailed);
    Exit(PC_TS_EXIT_FAILED);
  end;

  // Taken once the run's stop thread answers the mailbox; before its cells
  // start nothing answers, and the command waits there to be taken then
  LWatch := TStopwatch.StartNew();
  while LWatch.ElapsedMilliseconds < PC_TS_RPC_TAKEN_MS do
  begin
    if not AClient.Snapshot(LBlock) then
    begin
      DoPrintLn(COLOR_RED + RSTstRpcLockFailed);
      Exit(PC_TS_EXIT_FAILED);
    end;
    if LBlock.ReplySeq = LSeq then
    begin
      DoPrintLn(Format(RSTstRpcTaken, [AName, LBlock.ProcessId]));
      Exit(PC_TS_EXIT_PASSED);
    end;
    if not AClient.OwnerAlive(LBlock) then
    begin
      DoPrintLn(COLOR_RED + Format(RSTstRpcRunDied, [LBlock.ProcessId]));
      Exit(PC_TS_EXIT_FAILED);
    end;
    Sleep(PC_TS_RPC_POLL_MS);
  end;
  DoPrintLn(COLOR_YELLOW + Format(RSTstRpcNotTaken, [AName]));
  Result := PC_TS_EXIT_PASSED;
end;

function TPCTestSuite.DoRpcWait(const AClient: TPCTestControlClient; const ASeconds: Integer): Integer;
var
  LBlock: TPCTestControlBlock;
  LWatch: TStopwatch;
begin
  // The client keeps the block mapped while it waits, so the run's last
  // write (done, its exit code) is read even after its process has ended
  LWatch := TStopwatch.StartNew();
  while True do
  begin
    if not AClient.Snapshot(LBlock) then
    begin
      DoPrintLn(COLOR_RED + RSTstRpcLockFailed);
      Exit(PC_TS_EXIT_FAILED);
    end;
    if LBlock.State = Ord(csDone) then
    begin
      DoPrintLn(Format(RSTstRpcDone, [LBlock.ExitCode]));
      Exit(LBlock.ExitCode);
    end;
    if not AClient.OwnerAlive(LBlock) then
    begin
      DoPrintLn(COLOR_RED + Format(RSTstRpcRunDied, [LBlock.ProcessId]));
      Exit(PC_TS_EXIT_FAILED);
    end;
    if (ASeconds > 0) and (LWatch.ElapsedMilliseconds >= Int64(ASeconds) * 1000) then
    begin
      DoPrintLn(COLOR_YELLOW + Format(RSTstRpcWaitTimeout, [ASeconds]));
      Exit(PC_TS_EXIT_WAIT_TIMEOUT);
    end;
    Sleep(PC_TS_RPC_POLL_MS);
  end;
end;

function TPCTestSuite.RunCommandLine(): Integer;
var
  LArgs: TArray<string>;
  LI: Integer;
begin
  SetLength(LArgs, ParamCount());
  for LI := 1 to ParamCount() do
    LArgs[LI - 1] := ParamStr(LI);
  Result := RunArgs(LArgs);
end;

function TPCTestSuite.RunArgs(const AArgs: TArray<string>): Integer;
var
  LFilter: TPCTestFilter;
  LList: Boolean;
  LHelp: Boolean;
  LSelected: Boolean;
  LArgs: TArray<string>;
begin
  // A client of a running testbed: no discovery, no run of its own
  if (Length(AArgs) > 0) and (AArgs[0] = PC_TS_ARG_RPC) then
    Exit(DoRpc(AArgs));

  if not DoTakeRoots(AArgs, LArgs) then
    Exit(PC_TS_EXIT_BAD_ARGS);
  if not DoParseArgs(LArgs, LFilter, LList, LHelp, LSelected) then
    Exit(PC_TS_EXIT_BAD_ARGS);
  if LHelp then
  begin
    DoPrintHelp();
    Exit(PC_TS_EXIT_PASSED);
  end;
  // Pure CLI: nothing selected and nothing to list is a usage error
  if (not LList) and (not LSelected) then
  begin
    DoPrintHelp();
    Exit(PC_TS_EXIT_BAD_ARGS);
  end;

  if not Discover() then
  begin
    FErrors.PrintErrors();
    DoPrintLn(COLOR_RED + Format(RSTstDiscoveryFailed, [FErrors.ErrorCount()]));
    Exit(PC_TS_EXIT_FAILED);
  end;

  if LList then
  begin
    List(LFilter);
    Exit(PC_TS_EXIT_PASSED);
  end;
  Result := Run(LFilter);
end;

end.
