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
  PaskalCPP.CLI - pcpp command-line front end

  Parses the command line, pushes the options into TPCCompiler, runs the
  build. Single entry point: TPCCLI.Execute(). Shape from FreeStrike.CLI.pas.
  Exit codes: 0 ok, the auto-run program's own code when it ran and exited
  with one, 1 build failed or fatal, 2 bad arguments.
  The option values (-t, -opt) are checked by the compiler, as the directives
  they override: a bad one is a compiler error (exit 1), not a bad argument.

  -d / --debug: a debug build, then the console debugger (PaskalCPP.Debug.REPL)
  on it; --host <exe> for a dll.

  Dependencies: StdApp.Base, StdApp.Console, StdApp.Utils, StdApp.Resources,
    PaskalCPP.Common (PC_SRC_EXT), PaskalCPP.Compiler, PaskalCPP.ZigBuild
    (TPCBuildMode), PaskalCPP.Debug.Runtime, PaskalCPP.Debug.REPL,
    PaskalCPP.Debug.DAP, PaskalCPP.LSP.Transport, PaskalCPP.LSP.Server
===============================================================================}

unit PaskalCPP.CLI;

interface

uses
  System.SysUtils,
  StdApp.Base,
  StdApp.Utils,
  PaskalCPP.Compiler,
  PaskalCPP.LSP.Transport;

const
  { PC_CLI_EXIT_FAILED }
  // The build failed, or a fatal error escaped it
  PC_CLI_EXIT_FAILED = 1;
  { PC_CLI_EXIT_BADARGS }
  // The command line cannot be used
  PC_CLI_EXIT_BADARGS = 2;
  { PC_CLI_EDITOR_VERB }
  // `pcpp editor [files]`: the first argument
  PC_CLI_EDITOR_VERB = 'editor';
  { PC_CLI_EDITOR_EXE }
  // The PaskalCPP Editor (Electron, renamed), beside pcpp.exe's res folder
  PC_CLI_EDITOR_EXE = '$P:res\editor\editor.exe';
  { PC_CLI_LSP_FLAG }
  // `pcpp --lsp`: the language server on stdin / stdout (the editor runs it)
  PC_CLI_LSP_FLAG = '--lsp';
  { PC_CLI_DAP_FLAG }
  // `pcpp --dap`: the debug adapter on stdin / stdout (the editor runs it)
  PC_CLI_DAP_FLAG = '--dap';

  { PC_CLI_NO_BANNER_FLAG }
  // `pcpp ... --no-banner`: no banner (scripts, the test suite's cli tests:
  // the banner's version changes every release). Read before the banner
  // prints, anywhere before --, so -h and argument errors honour it too
  PC_CLI_NO_BANNER_FLAG = '--no-banner';

  { PC_CLI_ARGS_FLAG }
  // `pcpp <file> -r|-d -- <args>`: the rest of the line is the program's
  PC_CLI_ARGS_FLAG = '--';

type
  { TPCStdioServe }
  // A protocol server on stdin / stdout: serves ATransport, returns the
  // exit code
  TPCStdioServe = reference to function(const ATransport: TPCLspTransport): Integer;

  { TPCCLI }
  TPCCLI = class(TBaseObject)
  private
    FCompiler: TPCCompiler;
    FSourceFile: string;
    FAutoRun: Boolean;
    FOutputPath: string;
    FTarget: string;
    FOptimize: string;
    FDefaults: Boolean;         // --defaults: -opt / -t only stand in for missing directives
    FProgressInPlace: Boolean;  // stdout is a console, or --progress (the editor): progress is drawn in place
    FProgressShown: Boolean;    // a progress line is on screen, not yet ended
    FFlushFailed: Boolean;      // Output could not be flushed: its reader is gone, stop trying
    FDebug: Boolean;            // -d / --debug: build debug, then the console debugger
    FHostPath: string;          // --host: the exe that loads the dll debugged
    FTerminalPipe: string;      // --terminal: an editor's named pipe, the -r program's terminal
    FRunArgs: string;           // after --: the program's arguments, as written
    FHasRunArgs: Boolean;       // -- was given (even with nothing after it)
    FRunHost: TPtyHost;         // owned: the -r program's keyboard and size (DoCreateRunHost)
    FClean: Boolean;            // --clean: clear a pcpp output folder (FSourceFile = the folder, '' = current)
    FDryRun: Boolean;           // --dry-run: with --clean, check and list only
    FBuildFlag: string;         // the first build option on the line ('' = none): --clean takes none
    procedure ShowBanner();
    procedure DoCreateRunHost();
    procedure DoProgress(const AElapsedMs: UInt64);
    procedure DoEndProgress();
    procedure DoFlushOutput();
    procedure ShowHelp();
    procedure DoArgError(const AMessage: string; const AArgs: array of const;
      const AShowHint: Boolean);
    function DoFlagValue(const AFlag: string; const AMissingMessage: string;
      var AIndex: Integer; out AValue: string): Boolean;
    function DoResolveSource(): Boolean;
    function ParseArgs(): Boolean;
    procedure DoConfigureCompiler();
    procedure DoReportFailure();
    procedure DoCompile();
    procedure DoDebug();
    procedure DoClean();
    function DoAskYes(const ACount: Integer): Boolean;
    function DoRunEditor(): Boolean;
    function DoHasFlag(const AFlag: string): Boolean;
    procedure DoServeStdio(const AAloneMessage: string; const AServe: TPCStdioServe);
    procedure DoLsp();
    procedure DoDap();
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Execute();
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.IOUtils,
  StdApp.Console,
  StdApp.Resources,
  PaskalCPP.Common,
  PaskalCPP.ZigBuild,
  PaskalCPP.LSP.Server,
  PaskalCPP.Debug.Runtime,
  PaskalCPP.Debug.REPL,
  PaskalCPP.Debug.DAP;

{ TPCCLI }

constructor TPCCLI.Create();
begin
  inherited;

  FCompiler := TPCCompiler.Create();
  FSourceFile := '';
  FAutoRun := False;
  FOutputPath := '';
  FTarget := '';
  FOptimize := '';
  FDefaults := False;
  // A console draws the progress in place; --progress asks for it over a pipe
  FProgressInPlace := GetFileType(GetStdHandle(STD_OUTPUT_HANDLE)) = FILE_TYPE_CHAR;
  FProgressShown := False;
  FFlushFailed := False;
  FDebug := False;
  FHostPath := '';
  FRunArgs := '';
  FHasRunArgs := False;
end;

destructor TPCCLI.Destroy();
begin
  FreeAndNil(FCompiler);
  FreeAndNil(FRunHost);

  inherited;
end;

procedure TPCCLI.DoCreateRunHost();
var
  LPipeHost: TPtyPipeHost;
  LConsoleHost: TPtyConsoleHost;
  LStreamHost: TPtyStreamHost;
  LInput: THandle;
  LMode: DWORD;
begin
  // The -r program reads the keyboard wherever its runner has one: an
  // editor's pane (--terminal: its output goes there too), the console
  // pcpp runs in, or a redirected stdin (a file, a pipe)
  LInput := GetStdHandle(STD_INPUT_HANDLE);
  if FTerminalPipe <> '' then
  begin
    LPipeHost := TPtyPipeHost.Create();
    LPipeHost.Init(FTerminalPipe);
    FRunHost := LPipeHost;
    FCompiler.SetRunOutputCallback(
      procedure(const ALine: string; const AUserData: Pointer)
      begin
        LPipeHost.WriteOutput(ALine);
      end, nil);
  end
  else if (LInput <> 0) and (LInput <> INVALID_HANDLE_VALUE) and GetConsoleMode(LInput, LMode) then
  begin
    LConsoleHost := TPtyConsoleHost.Create();
    LConsoleHost.Init(LInput, GetStdHandle(STD_OUTPUT_HANDLE));
    FRunHost := LConsoleHost;
  end
  else if (LInput <> 0) and (LInput <> INVALID_HANDLE_VALUE) then
  begin
    LStreamHost := TPtyStreamHost.Create();
    LStreamHost.Init(LInput);
    FRunHost := LStreamHost;
  end;
  FCompiler.SetRunHost(FRunHost);
end;

procedure TPCCLI.ShowBanner();
var
  LVerInfo: TVersionInfo;
begin
  // Product name, version and copyright come from pcpp.exe's version resource
  LVerInfo := Default(TVersionInfo);
  TUtils.GetVersionInfo(LVerInfo);
  TConsole.PrintLn(COLOR_WHITE + COLOR_BOLD + RSPcCliBannerTitle,
    [LVerInfo.ProductName, LVerInfo.VersionString]);
  TConsole.PrintLn(COLOR_WHITE + RSPcCliBannerCopyright, [LVerInfo.Copyright]);
  if LVerInfo.URL <> '' then
    TConsole.PrintLn(COLOR_YELLOW + LVerInfo.URL);
  TConsole.PrintLn('');
end;

procedure TPCCLI.DoProgress(const AElapsedMs: UInt64);
const
  { PC_CLI_PIPED_PROGRESS_SECS }
  // Piped output cannot redraw a line: one line every this many seconds
  PC_CLI_PIPED_PROGRESS_SECS = 10;
var
  LSeconds: Int64;
begin
  // zig is quiet (it prints no progress over pipes): show that the build is
  // alive. On a console, or a pipe whose reader draws like one (--progress:
  // the editor's OUTPUT), the 'Building <name>...' status line itself is
  // redrawn with the time: the first tick moves up onto it (ESC[1A), every
  // tick returns to its start and erases it (CR + ESC[2K); the cursor stays
  // on that line until DoEndProgress ends it
  LSeconds := Int64(AElapsedMs div 1000);
  if FProgressInPlace then
  begin
    if not FProgressShown then
      TConsole.Print(#27 + '[1A');
    TConsole.Print(#13 + #27 + '[2K' + RSPcCliBuildProgress,
      [FCompiler.GetProjectName(), LSeconds]);
    FProgressShown := True;
  end
  else if (LSeconds > 0) and (LSeconds mod PC_CLI_PIPED_PROGRESS_SECS = 0) then
    TConsole.PrintLn(RSPcCliBuildProgress, [FCompiler.GetProjectName(), LSeconds]);
end;

procedure TPCCLI.DoEndProgress();
begin
  // The redrawn 'Building <name>... Ns' line stays (the final time) and is
  // ended before anything else is printed
  if not FProgressShown then
    Exit;
  TConsole.PrintLn('');
  FProgressShown := False;
end;

procedure TPCCLI.DoFlushOutput();
begin
  // Over a pipe the RTL buffers Output (128 bytes) and sends it only when
  // the buffer is full: the editor would see a status line, a progress tick
  // or a run's output seconds late, in bursts. A console shows every write
  // at once; this makes a pipe do the same. A flush that fails means the
  // reader closed the pipe (the editor stopped the build): there is nowhere
  // left to report to, so later output is not flushed again
  if FFlushFailed then
    Exit;
  try
    Flush(Output);
  except
    on Exception do
      FFlushFailed := True;
  end;
end;

procedure TPCCLI.ShowHelp();
var
  LExeName: string;
begin
  LExeName := TPath.GetFileNameWithoutExtension(ParamStr(0));

  TConsole.PrintLn(COLOR_BOLD + RSPcCliHelpUsageHeader);
  TConsole.PrintLn('  ' + LExeName + ' ' + COLOR_CYAN + RSPcCliHelpSourceArg +
    COLOR_RESET + ' ' + RSPcCliHelpOptionsArg);
  // The clean form takes no source: its own usage line
  TConsole.PrintLn('  ' + LExeName + ' --clean ' + COLOR_CYAN + '[<folder>]' +
    COLOR_RESET + ' [--dry-run]');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + RSPcCliHelpRequiredHeader);
  TConsole.PrintLn('  ' + COLOR_CYAN + RSPcCliHelpSourceArg + COLOR_RESET +
    '                  ' + RSPcCliHelpSource);
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + RSPcCliHelpOptionsHeader);
  TConsole.PrintLn('  ' + COLOR_CYAN + '-r, --run                  ' + COLOR_RESET +
    '  ' + RSPcCliHelpRun);
  TConsole.PrintLn('  ' + COLOR_CYAN + '-o, --output    <path>     ' + COLOR_RESET +
    '  ' + RSPcCliHelpOutput);
  TConsole.PrintLn('  ' + COLOR_CYAN + '-t, --target    <triple>   ' + COLOR_RESET +
    '  ' + RSPcCliHelpTarget);
  TConsole.PrintLn('  ' + COLOR_CYAN + '-opt, --optimize <level>   ' + COLOR_RESET +
    '  ' + RSPcCliHelpOptimize);
  TConsole.PrintLn('  ' + COLOR_CYAN + '--defaults                 ' + COLOR_RESET +
    '  ' + RSPcCliHelpDefaults);
  TConsole.PrintLn('  ' + COLOR_CYAN + '--progress                 ' + COLOR_RESET +
    '  ' + RSPcCliHelpProgress);
  TConsole.PrintLn('  ' + COLOR_CYAN + '--no-banner                ' + COLOR_RESET +
    '  ' + RSPcCliHelpNoBanner);
  TConsole.PrintLn('  ' + COLOR_CYAN + '--terminal      <pipe>     ' + COLOR_RESET +
    '  ' + RSPcCliHelpTerminal);
  TConsole.PrintLn('  ' + COLOR_CYAN + 'editor [files]             ' + COLOR_RESET +
    '  ' + RSPcCliHelpEditor);
  TConsole.PrintLn('  ' + COLOR_CYAN + '-d, --debug                ' + COLOR_RESET +
    '  ' + RSPcCliHelpDebug);
  TConsole.PrintLn('  ' + COLOR_CYAN + '--host          <exe>      ' + COLOR_RESET +
    '  ' + RSPcCliHelpHost);
  TConsole.PrintLn('  ' + COLOR_CYAN + '-- <args>                  ' + COLOR_RESET +
    '  ' + RSPcCliHelpArgs);
  TConsole.PrintLn('  ' + COLOR_CYAN + '--lsp                      ' + COLOR_RESET +
    '  ' + RSPcCliHelpLsp);
  TConsole.PrintLn('  ' + COLOR_CYAN + '--dap                      ' + COLOR_RESET +
    '  ' + RSPcCliHelpDap);
  TConsole.PrintLn('  ' + COLOR_CYAN + '--clean         [<folder>] ' + COLOR_RESET +
    '  ' + RSPcCliHelpClean);
  TConsole.PrintLn('  ' + COLOR_CYAN + '--dry-run                  ' + COLOR_RESET +
    '  ' + RSPcCliHelpDryRun);
  TConsole.PrintLn('  ' + COLOR_CYAN + '-h, --help                 ' + COLOR_RESET +
    '  ' + RSPcCliHelpHelp);
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + RSPcCliHelpExamplesHeader);
  TConsole.PrintLn('  ' + COLOR_CYAN + LExeName + ' hello');
  TConsole.PrintLn('  ' + COLOR_CYAN + LExeName + ' hello -r');
  TConsole.PrintLn('  ' + COLOR_CYAN + LExeName + ' hello -r -opt fast');
  TConsole.PrintLn('  ' + COLOR_CYAN + LExeName + ' hello -d');
  TConsole.PrintLn('  ' + COLOR_CYAN + LExeName + ' hello --target x86_64-linux-gnu --output build');
  TConsole.PrintLn('  ' + COLOR_CYAN + LExeName + ' editor hello.pcpp');
  TConsole.PrintLn('  ' + COLOR_CYAN + LExeName + ' --clean output --dry-run');
  TConsole.PrintLn('');
end;

procedure TPCCLI.DoArgError(const AMessage: string; const AArgs: array of const;
  const AShowHint: Boolean);
begin
  // Bad command line: message, optional "run -h" hint, exit code 2
  TConsole.PrintLn(COLOR_RED + AMessage, AArgs);
  TConsole.PrintLn('');
  if AShowHint then
  begin
    TConsole.PrintLn(RSPcCliSeeHelp, [TPath.GetFileNameWithoutExtension(ParamStr(0))]);
    TConsole.PrintLn('');
  end;
  ExitCode := PC_CLI_EXIT_BADARGS;
end;

function TPCCLI.DoFlagValue(const AFlag: string; const AMissingMessage: string;
  var AIndex: Integer; out AValue: string): Boolean;
begin
  // A flag that takes a value consumes the next argument
  AValue := '';
  Inc(AIndex);
  if AIndex > ParamCount() then
  begin
    DoArgError(AMissingMessage, [AFlag], False);
    Exit(False);
  end;
  AValue := ParamStr(AIndex).Trim();
  Result := True;
end;

function TPCCLI.DoResolveSource(): Boolean;
var
  LArg: string;
begin
  // The input is a PaskalCPP module: the extension is forced to .pcpp. The
  // RTL refuses some spellings (illegal characters): that is a bad argument
  // with the RTL's reason
  Result := False;
  LArg := FSourceFile;
  try
    FSourceFile := TUtils.ResolvePath(TPath.ChangeExtension(LArg, '.' + PC_SRC_EXT));
    if not TFile.Exists(FSourceFile) then
    begin
      DoArgError(RSPcCliSourceNotFound, [COLOR_YELLOW + FSourceFile], False);
      Exit;
    end;
  except
    on E: Exception do
    begin
      DoArgError(RSPcCliBadSource, [COLOR_YELLOW + LArg + COLOR_RED, E.Message], False);
      Exit;
    end;
  end;
  Result := True;
end;

function TPCCLI.ParseArgs(): Boolean;
var
  LI: Integer;
  LFlag: string;
begin
  Result := False;

  if ParamCount() = 0 then
  begin
    ShowHelp();
    Exit;
  end;

  LI := 1;
  while LI <= ParamCount() do
  begin
    LFlag := ParamStr(LI).Trim();

    // The first build option is kept: --clean builds nothing and takes none
    // (an unknown flag is reported below either way)
    if (FBuildFlag = '') and LFlag.StartsWith('-') and (LFlag <> '--clean') and
      (LFlag <> '--dry-run') and (LFlag <> '-h') and (LFlag <> '--help') and
      (LFlag <> PC_CLI_NO_BANNER_FLAG) then
      FBuildFlag := LFlag;

    if (LFlag = '-h') or (LFlag = '--help') then
    begin
      ShowHelp();
      Exit;
    end
    else if (LFlag = '-r') or (LFlag = '--run') then
      FAutoRun := True
    else if (LFlag = '-o') or (LFlag = '--output') then
    begin
      if not DoFlagValue(LFlag, RSPcCliNeedsPath, LI, FOutputPath) then
        Exit;
    end
    else if (LFlag = '-t') or (LFlag = '--target') then
    begin
      if not DoFlagValue(LFlag, RSPcCliNeedsTarget, LI, FTarget) then
        Exit;
    end
    else if (LFlag = '-opt') or (LFlag = '--optimize') then
    begin
      if not DoFlagValue(LFlag, RSPcCliNeedsOptimize, LI, FOptimize) then
        Exit;
    end
    else if LFlag = '--clean' then
      FClean := True
    else if LFlag = '--dry-run' then
      FDryRun := True
    else if LFlag = '--defaults' then
      FDefaults := True
    else if LFlag = '--progress' then
      FProgressInPlace := True
    else if LFlag = PC_CLI_NO_BANNER_FLAG then
    begin
      // Taken before the banner (Execute): nothing more to do here
    end
    else if (LFlag = '-d') or (LFlag = '--debug') then
      FDebug := True
    else if LFlag = '--host' then
    begin
      if not DoFlagValue(LFlag, RSPcCliNeedsHost, LI, FHostPath) then
        Exit;
    end
    else if LFlag = '--terminal' then
    begin
      if not DoFlagValue(LFlag, RSPcCliNeedsPipe, LI, FTerminalPipe) then
        Exit;
    end
    else if LFlag = PC_CLI_ARGS_FLAG then
    begin
      // Everything after -- is the program's: the raw text, never ParamStr's
      // values re-quoted (ParamStr is not the C runtime's argv rule)
      FRunArgs := TUtils.CommandLineTail(GetCommandLine(), LI);
      FHasRunArgs := True;
      Break;
    end
    else if LFlag.StartsWith('-') then
    begin
      DoArgError(RSPcCliUnknownFlag, [COLOR_YELLOW + LFlag], True);
      Exit;
    end
    else if FSourceFile = '' then
      // Positional argument: the main module
      FSourceFile := LFlag
    else
    begin
      DoArgError(RSPcCliUnexpectedArg, [COLOR_YELLOW + LFlag], False);
      Exit;
    end;

    Inc(LI);
  end;

  if FDryRun and (not FClean) then
  begin
    DoArgError(RSPcCliDryRunWithoutClean, [], True);
    Exit;
  end;
  // --clean [<folder>]: the positional is the folder ('' = the current
  // one), no source and no build option; the folder is checked by the
  // compiler (CheckCleanFolder), never here
  if FClean then
  begin
    if FBuildFlag <> '' then
    begin
      DoArgError(RSPcCliCleanWithOption, [COLOR_YELLOW + FBuildFlag], True);
      Exit;
    end;
    Exit(True);
  end;

  if FSourceFile = '' then
  begin
    DoArgError(RSPcCliSourceRequired, [], True);
    Exit;
  end;

  // -d builds debug and runs the program itself, under the debugger
  if FDebug and FAutoRun then
  begin
    DoArgError(RSPcCliDebugWithRun, [], True);
    Exit;
  end;
  if FDebug and (FOptimize <> '') then
  begin
    DoArgError(RSPcCliDebugWithOptimize, [], True);
    Exit;
  end;
  if (FHostPath <> '') and (not FDebug) then
  begin
    DoArgError(RSPcCliHostWithoutDebug, [], True);
    Exit;
  end;
  if (FTerminalPipe <> '') and (not FAutoRun) then
  begin
    DoArgError(RSPcCliTerminalWithoutRun, [], True);
    Exit;
  end;
  if FHasRunArgs and (not FAutoRun) and (not FDebug) then
  begin
    DoArgError(RSPcCliArgsWithoutRun, [], True);
    Exit;
  end;
  if FHostPath <> '' then
  begin
    try
      FHostPath := TUtils.ResolvePath(FHostPath);
    except
      on E: Exception do
      begin
        DoArgError(RSPcCliBadHost, [COLOR_YELLOW + FHostPath + COLOR_RED, E.Message], False);
        Exit;
      end;
    end;
  end;

  Result := DoResolveSource();
end;

procedure TPCCLI.DoConfigureCompiler();
begin
  // The compiler's callbacks and the command line's options: one setup for
  // a build (DoCompile) and a debug build (DoDebug)
  FCompiler.SetStatusCallback(
    procedure(const AText: string; const AUserData: Pointer)
    begin
      DoEndProgress();
      TConsole.PrintLn(AText);
      DoFlushOutput();
    end, nil);

  // Every second while zig is quiet: the build is alive (DoProgress)
  FCompiler.SetProgressCallback(
    procedure(const AElapsedMs: UInt64; const AUserData: Pointer)
    begin
      DoProgress(AElapsedMs);
      DoFlushOutput();
    end, nil);

  // An auto-run program's output arrives as it is written (pseudoconsole
  // chunks, not lines): printed unchanged, no line end added and no color
  // reset at a chunk boundary (prior art CPaskal.CLI.pas:175-179)
  FCompiler.SetOutputCallback(
    procedure(const ALine: string; const AUserData: Pointer)
    begin
      TConsole.Print(ALine, False);
      DoFlushOutput();
    end, nil);

  // -opt / -t: from the command line they override the source directives;
  // with --defaults (the editor runs pcpp so) they only stand in where the
  // source has no @optimize / @target. The compiler checks the values
  // either way
  if FDefaults then
  begin
    if FOptimize <> '' then
      FCompiler.SetKeyDefault(PC_CMP_KEY_OPTIMIZE, FOptimize);
    if FTarget <> '' then
      FCompiler.SetKeyDefault(PC_CMP_KEY_TARGET, FTarget);
  end
  else
  begin
    if FOptimize <> '' then
      FCompiler.SetKeyValue(PC_CMP_KEY_OPTIMIZE, FOptimize);
    if FTarget <> '' then
      FCompiler.SetKeyValue(PC_CMP_KEY_TARGET, FTarget);
  end;
end;

procedure TPCCLI.DoReportFailure();
begin
  // A Prepare or Build that returned False, or a debug check that failed:
  // its errors (hints and warnings already went out inline through the
  // status callback)
  DoEndProgress();
  FCompiler.PrintErrors([esError, esFatal]);
  TConsole.PrintLn(COLOR_RED + RSPcCliFailed);
  ExitCode := PC_CLI_EXIT_FAILED;
end;

procedure TPCCLI.DoCompile();
var
  LExitCode: Cardinal;
begin
  DoConfigureCompiler();
  FCompiler.SetRunArguments(FRunArgs);
  if FAutoRun then
    DoCreateRunHost();

  // An empty output path is the compiler's default folder (PC_CMP_DEFAULT_OUTPUT)
  FCompiler.Compile(FSourceFile, FOutputPath, FAutoRun);
  DoEndProgress();
  // Hints and warnings already went out inline through the status callback
  FCompiler.PrintErrors([esError, esFatal]);

  // A program that ran returns its own exit code. Only a run sets a non-zero
  // code (TPCZigBuild.Run, reported as ZB0031); a failed build or a failed
  // start leaves it 0
  LExitCode := FCompiler.GetLastExitCode();
  if LExitCode <> 0 then
    ExitCode := Integer(LExitCode)
  else if FCompiler.HasErrors() then
  begin
    TConsole.PrintLn(COLOR_RED + RSPcCliFailed);
    ExitCode := PC_CLI_EXIT_FAILED;
  end
  else
    ExitCode := 0;
end;

procedure TPCCLI.DoDebug();
var
  LMode: TPCBuildMode;
  LRepl: TPCDebugREPL;
begin
  // pcpp <file> -d: a debug build (an override: it wins over @optimize),
  // then the console debugger on it. The engine debugs one target (W5):
  // checked once the source's @target is known, before anything is built
  DoConfigureCompiler();
  FCompiler.SetKeyValue(PC_CMP_KEY_OPTIMIZE, PC_CMP_OPTIMIZE_TEXT[olDebug]);
  if not FCompiler.Prepare(FSourceFile, FOutputPath) then
  begin
    DoReportFailure();
    Exit;
  end;
  if not TPCDebugRuntime.SupportsTarget(FCompiler.GetTarget()) then
  begin
    FCompiler.GetErrors().Add(esError, PC_ERR_DBG_012, RSDbgNotWin64,
      [PC_DBG_TARGET, FCompiler.GetTarget()]);
    DoReportFailure();
    Exit;
  end;

  // An exe runs on its own; a dll runs in the exe that loads it (--host)
  LMode := FCompiler.GetBuildMode();
  if LMode = bmLib then
  begin
    DoArgError(RSPcCliDebugLib, [], False);
    Exit;
  end;
  if (LMode = bmDll) and (FHostPath = '') then
  begin
    DoArgError(RSPcCliDebugDllNoHost, [], False);
    Exit;
  end;
  if (LMode = bmExe) and (FHostPath <> '') then
  begin
    DoArgError(RSPcCliDebugHostOnExe, [], False);
    Exit;
  end;

  if not FCompiler.Build(False) then
  begin
    DoReportFailure();
    Exit;
  end;
  DoEndProgress();

  // The compiler outlives the REPL: it holds the analysed tree the debugger
  // names variables and finds @breakpoint statements in
  LRepl := TPCDebugREPL.Create();
  try
    LRepl.SetColor(GetFileType(GetStdHandle(STD_OUTPUT_HANDLE)) = FILE_TYPE_CHAR);
    LRepl.SetProgram(FCompiler.GetMainModule());
    if LMode = bmDll then
      LRepl.SetHostTarget(FCompiler.GetArtifactPath(), FHostPath, FRunArgs)
    else
      LRepl.SetTarget(FCompiler.GetArtifactPath(), FRunArgs);
    // The program's own exit code, as with -r
    if LRepl.Run() then
      ExitCode := Integer(LRepl.GetLastExitCode())
    else
      ExitCode := PC_CLI_EXIT_FAILED;
  finally
    LRepl.Free();
  end;
end;

procedure DoMeasureTarget(const APath: string; var AFiles: Int64; var ABytes: Int64);
var
  LSearch: TSearchRec;
  LAttr: DWORD;
  LEntry: string;
  LIsDir: Boolean;
  LIsLink: Boolean;
begin
  // Files and bytes under APath as the delete sees them: a link is one
  // entry, never entered (its target is not this folder's); a file target
  // (the copy-DLL record) is itself. GetFileAttributes and SearchRec.Attr
  // are the entries' own attributes (a reparse point is not followed)
  LAttr := GetFileAttributes(PChar(APath));
  if LAttr = INVALID_FILE_ATTRIBUTES then
    Exit;
  if (LAttr and FILE_ATTRIBUTE_DIRECTORY) = 0 then
  begin
    Inc(AFiles);
    if System.SysUtils.FindFirst(APath, faAnyFile, LSearch) = 0 then
    begin
      ABytes := ABytes + LSearch.Size;
      System.SysUtils.FindClose(LSearch);
    end;
    Exit;
  end;
  if System.SysUtils.FindFirst(TUtils.JoinResolvedPath(APath, '*'), faAnyFile, LSearch) <> 0 then
    Exit;
  try
    repeat
      if (LSearch.Name = '.') or (LSearch.Name = '..') then
        Continue;
      LEntry := TUtils.JoinResolvedPath(APath, LSearch.Name);
      LIsDir := (DWORD(LSearch.Attr) and FILE_ATTRIBUTE_DIRECTORY) <> 0;
      LIsLink := (DWORD(LSearch.Attr) and FILE_ATTRIBUTE_REPARSE_POINT) <> 0;
      if LIsDir and (not LIsLink) then
        DoMeasureTarget(LEntry, AFiles, ABytes)
      else
      begin
        Inc(AFiles);
        if not LIsLink then
          ABytes := ABytes + LSearch.Size;
      end;
    until System.SysUtils.FindNext(LSearch) <> 0;
  finally
    System.SysUtils.FindClose(LSearch);
  end;
end;

function DoSizeText(const ABytes: Int64): string;
begin
  // A size a person reads at a glance
  if ABytes >= 1024 * 1024 * 1024 then
    Result := Format('%.1f GB', [ABytes / (1024 * 1024 * 1024)])
  else if ABytes >= 1024 * 1024 then
    Result := Format('%.1f MB', [ABytes / (1024 * 1024)])
  else if ABytes >= 1024 then
    Result := Format('%.1f KB', [ABytes / 1024])
  else
    Result := Format('%d bytes', [ABytes]);
end;

function TPCCLI.DoAskYes(const ACount: Integer): Boolean;
var
  LAnswer: string;
begin
  // One line from the console: only y / Y is yes. An empty line, anything
  // else, end of input (ReadLn gives '') or a read that fails is no: the
  // caller then prints "Nothing deleted."
  Result := False;
  LAnswer := '';
  TConsole.Print(RSPcCliCleanAsk, [ACount]);
  DoFlushOutput();
  try
    ReadLn(Input, LAnswer);
  except
    on Exception do
      Exit;
  end;
  Result := (LAnswer.Trim() = 'y') or (LAnswer.Trim() = 'Y');
end;

procedure TPCCLI.DoClean();
var
  LFolder: string;
  LTargets: TArray<string>;
  LTarget: string;
  LFiles: Int64;
  LBytes: Int64;
  LInput: THandle;
  LMode: DWORD;
begin
  // pcpp --clean [<folder>] [--dry-run]: the compiler proves the folder is a
  // pcpp output folder (CheckCleanFolder reads only), the targets are
  // listed, a person answers y/N, and CleanFolder checks everything again
  // before the first delete. Nothing is deleted on any other path
  ExitCode := PC_CLI_EXIT_FAILED;
  if not FCompiler.CheckCleanFolder(FSourceFile, LFolder, LTargets) then
  begin
    FCompiler.PrintErrors([esError, esFatal]);
    TConsole.PrintLn(COLOR_RED + RSPcCliCleanNothing);
    Exit;
  end;
  if Length(LTargets) = 0 then
  begin
    TConsole.PrintLn(RSPcCliCleanEmpty, [TUtils.StripLongPathPrefix(LFolder)]);
    ExitCode := 0;
    Exit;
  end;

  TConsole.PrintLn(RSPcCliCleanHeader, [TUtils.StripLongPathPrefix(LFolder)]);
  for LTarget in LTargets do
  begin
    // FindFirst / FileGetAttr report failure by result, never raise: an
    // entry that cannot be read is not counted
    LFiles := 0;
    LBytes := 0;
    DoMeasureTarget(LTarget, LFiles, LBytes);
    TConsole.PrintLn(RSPcCliCleanTarget,
      [TUtils.StripLongPathPrefix(LTarget), LFiles, DoSizeText(LBytes)]);
  end;

  if FDryRun then
  begin
    TConsole.PrintLn(RSPcCliCleanDryRun);
    ExitCode := 0;
    Exit;
  end;

  // A person answers: a stdin that is not a console (a pipe, a file, NUL or
  // another character device) is refused, never read as an answer.
  // GetConsoleMode succeeds only on a console input handle; the file type
  // alone does not tell NUL from a console (both are FILE_TYPE_CHAR)
  LInput := GetStdHandle(STD_INPUT_HANDLE);
  if (LInput = 0) or (LInput = INVALID_HANDLE_VALUE) or
    not GetConsoleMode(LInput, LMode) then
  begin
    TConsole.PrintLn(COLOR_RED + RSPcCliCleanNotConsole);
    Exit;
  end;
  if not DoAskYes(Length(LTargets)) then
  begin
    TConsole.PrintLn(RSPcCliCleanNothing);
    ExitCode := 0;
    Exit;
  end;

  if not FCompiler.CleanFolder(LFolder) then
  begin
    FCompiler.PrintErrors([esError, esFatal]);
    TConsole.PrintLn(COLOR_RED + RSPcCliCleanFailed);
    Exit;
  end;
  TConsole.PrintLn(RSPcCliCleanDone, [Length(LTargets)]);
  ExitCode := 0;
end;

function TPCCLI.DoRunEditor(): Boolean;
var
  LI: Integer;
  LParams: string;
  LExe: string;
begin
  // `pcpp editor [files...]`: start the PaskalCPP Editor and return at once
  // (FreeStrike.CLI.pas DoRunEditor). File arguments are made absolute: the
  // editor runs with its own folder as the working directory. Each is handed
  // over in its plain spelling, quoted only when it must be
  Result := (ParamCount() >= 1) and SameText(ParamStr(1), PC_CLI_EDITOR_VERB);
  if not Result then
    Exit;

  LParams := '';
  try
    for LI := 2 to ParamCount() do
      LParams := LParams + ' ' +
        TUtils.QuoteCommandArg(TUtils.StripLongPathPrefix(TUtils.ResolvePath(ParamStr(LI))));
    LExe := TUtils.ResolvePath(PC_CLI_EDITOR_EXE);
    TUtils.RunPE(LExe, LParams.Trim(), TPath.GetDirectoryName(LExe), False);
  except
    on E: Exception do
    begin
      TConsole.PrintLn(COLOR_RED + RSPcCliEditorFailed, [E.Message]);
      ExitCode := PC_CLI_EXIT_FAILED;
    end;
  end;
end;

function TPCCLI.DoHasFlag(const AFlag: string): Boolean;
var
  LI: Integer;
begin
  // --lsp / --dap anywhere on the line: decided before anything is printed
  // (FreeStrike.CLI.pas DoIsLspMode)
  Result := False;
  for LI := 1 to ParamCount() do
  begin
    // Nothing after -- is pcpp's: a program argument --lsp is the program's
    if ParamStr(LI).Trim() = PC_CLI_ARGS_FLAG then
      Exit;
    if ParamStr(LI).Trim() = AFlag then
      Exit(True);
  end;
end;

procedure TPCCLI.DoServeStdio(const AAloneMessage: string; const AServe: TPCStdioServe);
var
  LInput: THandleStream;
  LOutput: THandleStream;
  LTransport: TPCLspTransport;
begin
  // A bad line goes to a person at a console: no protocol has started yet
  if ParamCount() <> 1 then
  begin
    DoArgError(AAloneMessage, [], True);
    Exit;
  end;

  // From here stdout carries only protocol frames; failures go to stderr
  // (the editor ignores it, a person at a console sees it). The server is
  // freed inside AServe, before the transport it writes through
  LInput := nil;
  LOutput := nil;
  LTransport := nil;
  try
    try
      LInput := THandleStream.Create(GetStdHandle(STD_INPUT_HANDLE));
      LOutput := THandleStream.Create(GetStdHandle(STD_OUTPUT_HANDLE));
      LTransport := TPCLspTransport.Create();
      LTransport.Init(LInput, LOutput);
      ExitCode := AServe(LTransport);
    finally
      LTransport.Free();
      LOutput.Free();
      LInput.Free();
    end;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, Format(RSPcCliFatalError, [E.Message]));
      ExitCode := PC_CLI_EXIT_FAILED;
    end;
  end;
end;

procedure TPCCLI.DoLsp();
begin
  DoServeStdio(RSPcCliLspAlone,
    function(const ATransport: TPCLspTransport): Integer
    var
      LServer: TPCLspServer;
    begin
      LServer := TPCLspServer.Create();
      try
        Result := LServer.Run(ATransport);
      finally
        LServer.Free();
      end;
    end);
end;

procedure TPCCLI.DoDap();
begin
  // The debug adapter: launch builds a .pcpp debug itself (its build's
  // status and reports go out as output events, never on stdout)
  DoServeStdio(RSPcCliDapAlone,
    function(const ATransport: TPCLspTransport): Integer
    var
      LAdapter: TPCDebugDAP;
    begin
      LAdapter := TPCDebugDAP.Create();
      try
        Result := LAdapter.Run(ATransport);
      finally
        LAdapter.Free();
      end;
    end);
end;

procedure TPCCLI.Execute();
begin
  // The editor runs on its own: no banner, pcpp returns at once
  if DoRunEditor() then
    Exit;

  // The language server and the debug adapter: stdout is the protocol, so
  // no banner either
  if DoHasFlag(PC_CLI_LSP_FLAG) then
  begin
    DoLsp();
    Exit;
  end;
  if DoHasFlag(PC_CLI_DAP_FLAG) then
  begin
    DoDap();
    Exit;
  end;

  try
    if not DoHasFlag(PC_CLI_NO_BANNER_FLAG) then
      ShowBanner();

    if not ParseArgs() then
      Exit;

    if FClean then
      DoClean()
    else if FDebug then
      DoDebug()
    else
      DoCompile();
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + COLOR_BOLD + RSPcCliFatalError, [E.Message]);
      TConsole.PrintLn('');
      ExitCode := PC_CLI_EXIT_FAILED;
    end;
  end;
end;

end.
