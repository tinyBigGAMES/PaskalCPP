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
  UTestCase.Project - the project model (TPCProject, project.toml)

  TPCTestCase suite for PaskalCPP.Project over the fixture projects in
  res\tests\prj\fixtures: finding the nearest project.toml (a file or a
  folder start, a project inside a project, none at all), reading every
  field and its default, every PJ report each bad fixture holds, the name and
  type rules, and Save refusing a model Load would refuse (nothing written).
  The $R: prefix: TUtils.ResolvePath with and without a project root, and the
  parser resolving $R: directives (an import's too) against the root it is
  handed, PR0065 without one.
  A code test because no .pcpp reaches the model until the compiler loads
  projects, and Save is reached only by pcpp init (user 2026-10-29); the
  root reaches the parser from the compiler only from PLAN-PROJECTS atom 3
  (user OK 2026-10-29).
  pcpp init / pcpp build (init_*): pcpp.exe run in the output folder makes
  output\prj_init_<kind> (the case's one folder, cleared first), the tree
  and project.toml are checked, then pcpp build builds it for both targets
  (an exe also runs). Several pcpp calls over one fresh folder: no cli test
  can (one call each, in the output root itself).
  pcpp pack (pack_*): an init'd project in output\prj_pack_<case> gets a
  fixed password (quotes, backslashes, a blank) and a reader main module;
  pack writes <root>\output\bin\<case>.dat (packer in <root>\output\pack),
  and the reader, built and run with -r -- <password>, prints each entry
  back. The right password reads, a wrong one or none reads nothing, an
  empty assets\ packs an empty archive, no assets\ fails. --clean lists and
  deletes output\pack on a project's own output folder only (pack_clean;
  the delete through TPCCompiler.CleanFolder: pcpp --clean asks a person).
  ProjectPassword() (password_*): a reader with no password of its own
  opens its packed .dat with ProjectPassword() on both targets; neither exe
  nor generated C++ holds the password (whole, UTF-16 or any run of more
  than PC_TEST_PRJ_SECRET_WINDOW bytes; a control text proves the scan
  reads); a .dat packed before a password change opens no entry until the
  old password is back; a project with no password gets ""; the editor's
  Analyze: fine in the main module, SM0409 with an argument, SM0433 in a
  project file that is not the main module.
  Stale files (stale_*): pcpp build in output\prj_stale_<case> removes what
  an earlier project build of its own output left for the same target (the
  debug .pdb after a fast build, the old exe after the main module is
  renamed) and nothing else: another target's artifact, a plain build's
  file, a name the plain record also lists, any file of a plain build or
  of the main module built with -o elsewhere; --clean lists and deletes the
  project records' folder. Several pcpp calls over one folder: a code test.

  Dependencies: PaskalCPP.TestSuite.CodeTest, PaskalCPP.Project,
  PaskalCPP.Parser, PaskalCPP.AST, PaskalCPP.ZigBuild (the record names)
===============================================================================}

unit UTestCase.Project;

interface

uses
  System.SysUtils,
  StdApp.Base,
  PaskalCPP.Common,
  PaskalCPP.AST,
  PaskalCPP.TestSuite.Types,
  PaskalCPP.TestSuite.CodeTest,
  PaskalCPP.Project;

type

  { TPCProjectTests }
  TPCProjectTests = class(TPCTestCase)
  private
    function DoNewErrors(): TErrors;
    function DoReportCodes(const AErrors: TErrors): string;
    procedure DoCheckCodes(const AErrors: TErrors; const AExpected: array of string;
      const ALabel: string);
    function DoLoad(const AProject: TPCProject; const AErrors: TErrors;
      const ARoot: string): Boolean;
    procedure DoCheckBad(const ALabel: string; const ARoot: string;
      const AExpected: array of string);
    procedure DoCheckFind(const AStart: string; const AExpected: string;
      const ALabel: string);
    procedure DoTestFind(const ACell: TPCTestCell);
    procedure DoTestLoadOk(const ACell: TPCTestCell);
    procedure DoTestLoadDefaults(const ACell: TPCTestCell);
    procedure DoTestLoadBad(const ACell: TPCTestCell);
    procedure DoTestNames(const ACell: TPCTestCell);
    procedure DoTestKinds(const ACell: TPCTestCell);
    procedure DoTestSaveRefused(const ACell: TPCTestCell);
    function DoSetupSaveFolder(out ARoot: string): Boolean;
    procedure DoCheckRoundtrip(const ARoot: string; const AKind: TPCProjectKind;
      const APassword: string; const ALabel: string);
    procedure DoTestSaveRoundtrip(const ACell: TPCTestCell);
    function DoRaisesNoRoot(const APath: string; const ARoot: string): Boolean;
    procedure DoTestRootResolve(const ACell: TPCTestCell);
    function DoParseRoot(const AErrors: TErrors; const AAst: TPCAst;
      const ARoot: string): TPCModule;
    procedure DoCheckPathArg(const AModule: TPCModule; const AKind: TPCBuildDirective;
      const AExpected: string; const ALabel: string);
    procedure DoTestRootParse(const ACell: TPCTestCell);
    function DoWriteCase(const ACase: string; const AToml: string;
      const ASourceName: string; const ASource: string; out AMain: string): string;
    procedure DoTestCompileOutput(const ACell: TPCTestCell);
    procedure DoTestCompileBadToml(const ACell: TPCTestCell);
    procedure DoTestCompileKind(const ACell: TPCTestCell);
    function DoFreshCase(const ACase: string): string;
    function DoRunPcpp(const AArgs: string; out AOutput: string): Int64;
    function DoOutputPath(const AOutput: string): string;
    function DoIsInside(const APath: string; const AFolder: string): Boolean;
    procedure DoCheckPassword(const APassword: string; const ALabel: string);
    procedure DoCheckPackScript(const ABytes: TBytes);
    procedure DoCheckInitTree(const ARoot: string; const ACase: string;
      const AKind: TPCProjectKind);
    procedure DoCheckInitBuild(const ARoot: string; const ACase: string;
      const AKind: TPCProjectKind; const ATarget: string; const ARun: Boolean);
    procedure DoCheckInit(const AKind: TPCProjectKind);
    procedure DoTestInitExe(const ACell: TPCTestCell);
    procedure DoTestInitDll(const ACell: TPCTestCell);
    procedure DoTestInitLib(const ACell: TPCTestCell);
    procedure DoTestInitExists(const ACell: TPCTestCell);
    procedure DoTestInitPassword(const ACell: TPCTestCell);
    function DoWriteText(const APath: string; const AText: string): Boolean;
    function DoSetupPackCase(const ACase: string; out ARoot: string): Boolean;
    function DoSetupProjectCase(const ACase: string; const AToml: string;
      const AMainSource: string; out ARoot: string): Boolean;
    function DoWritePackAssets(const ARoot: string): Boolean;
    function DoPack(const ACase: string; out AOutput: string): Int64;
    function DoReadBack(const ACase: string; const APassword: string): string;
    procedure DoCheckNotRead(const AOutput: string; const ALabel: string);
    procedure DoTestPackEntries(const ACell: TPCTestCell);
    procedure DoTestPackWrongPassword(const ACell: TPCTestCell);
    procedure DoTestPackEmpty(const ACell: TPCTestCell);
    function DoCleanFolder(const AFolder: string): Boolean;
    function DoMakeJunction(const ALink: string; const ATarget: string): Boolean;
    procedure DoTestPackClean(const ACell: TPCTestCell);
    function DoSetupSecretCase(const ACase: string; const APassword: string;
      out ARoot: string): Boolean;
    function DoPackCase(const ACase: string): Boolean;
    function DoBuildCase(const ACase: string; const ATarget: string; const ARun: Boolean;
      out AOutput: string; out AArtifact: string): Boolean;
    procedure DoCheckSecretRead(const AOutput: string; const APassword: string;
      const ALabel: string);
    function DoReadFileBytes(const APath: string; out ABytes: TBytes): Boolean;
    class function DoHasBytes(const AHaystack: TBytes; const ANeedle: TBytes): Boolean; static;
    procedure DoCheckNoPassword(const ABytes: TBytes; const APassword: string;
      const ALabel: string);
    procedure DoCheckHiddenArtifact(const AArtifact: string; const ALabel: string);
    procedure DoCheckHiddenGenerated(const ARoot: string; const ACase: string);
    procedure DoTestPasswordOpen(const ACell: TPCTestCell);
    procedure DoTestPasswordHidden(const ACell: TPCTestCell);
    procedure DoTestPasswordStale(const ACell: TPCTestCell);
    procedure DoTestPasswordNone(const ACell: TPCTestCell);
    procedure DoTestPasswordAnalyze(const ACell: TPCTestCell);
    function DoSetupStaleCase(const ACase: string; out ARoot: string): Boolean;
    function DoSetMain(const ARoot: string; const ACase: string; const AStem: string): Boolean;
    function DoStaleBuild(const AArgs: string; const ALabel: string): Boolean;
    function DoPlainSource(const ARoot: string; const AStem: string): string;
    function DoRecordNames(const APath: string): TArray<string>;
    function DoRecordHas(const ANames: TArray<string>; const AName: string): Boolean;
    function DoTargetRecord(const AOutput: string; const ATarget: string): string;
    procedure DoTestStaleDebugToFast(const ACell: TPCTestCell);
    procedure DoTestStaleRename(const ACell: TPCTestCell);
    procedure DoTestStalePlainKept(const ACell: TPCTestCell);
    procedure DoTestStaleSharedName(const ACell: TPCTestCell);
    procedure DoTestStaleOtherOutput(const ACell: TPCTestCell);
    procedure DoTestStalePlainUnchanged(const ACell: TPCTestCell);
    procedure DoTestStaleClean(const ACell: TPCTestCell);
  public
    constructor Create(); override;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.Generics.Collections,
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.Parser,
  PaskalCPP.ZigBuild,
  PaskalCPP.Compiler;

const
  { PC_TEST_PRJ_WARN }
  // Marks a warning's code in DoReportCodes ('PJ0004/warn')
  PC_TEST_PRJ_WARN = '/warn';

  { PC_TEST_PRJ_MAX_ERRORS }
  // The error budget of each check (TErrors stops at one by default): every
  // problem a file holds is reported, so a check must see them all
  PC_TEST_PRJ_MAX_ERRORS = 100;

  { PC_TEST_PRJ_SAVE_NAME }
  // The round-trip project: its name and its one folder in the output
  // folder (a project is a tree: the one subfolder project tests may make,
  // user 2026-10-29)
  PC_TEST_PRJ_SAVE_NAME = 'prj_save_roundtrip';

  { PC_TEST_PRJ_SAVE_SOURCE }
  // The round-trip project's main module
  PC_TEST_PRJ_SAVE_SOURCE = '''
module exe prj_save_roundtrip;

begin
end.
''';

  { PC_TEST_PRJ_CASE_TOML }
  // A compile case's project.toml: its name, its type
  PC_TEST_PRJ_CASE_TOML = '''
format = 1

[project]
name = "%s"
type = "%s"
main = "src/%s.pcpp"
''';

  { PC_TEST_PRJ_CASE_EXE }
  // A main module that is an exe: its name
  PC_TEST_PRJ_CASE_EXE = '''
module exe %s;

begin
end.
''';

  { PC_TEST_PRJ_BAD_TOML }
  // A project.toml no TOML reader takes (PJ0001)
  PC_TEST_PRJ_BAD_TOML = '''
format = 1
[project
''';

  { PC_TEST_PRJ_PCPP }
  // The compiler beside testbed (pcpp init / pcpp build run it)
  PC_TEST_PRJ_PCPP = '$P:pcpp.exe';

  { PC_TEST_PRJ_INIT_PREFIX }
  // An init case's folder: this prefix and the kind (prj_init_exe, ...)
  PC_TEST_PRJ_INIT_PREFIX = 'prj_init_';

  { PC_TEST_PRJ_OUTPUT_MARK }
  // pcpp's line naming what a build wrote ('Output: <path>')
  PC_TEST_PRJ_OUTPUT_MARK = 'Output: ';

  { PC_TEST_PRJ_LINUX }
  // The second official target an init case builds for
  PC_TEST_PRJ_LINUX = 'x86_64-linux-gnu';

  { PC_TEST_PRJ_PACK_LINE }
  // pack.cmd's last line: pcpp pack on the script's own folder
  PC_TEST_PRJ_PACK_LINE = 'pcpp pack "%~dp0."';

  { PC_TEST_PRJ_HEADER_MARK }
  // A line of PaskalCPP's file header: pack.cmd carries it, the starter
  // module (the user's code) must not
  PC_TEST_PRJ_HEADER_MARK = 'SPDX-License-Identifier: MPL-2.0';

  { PC_TEST_PRJ_STARTER_FIELDS }
  // The blank fields of a new main module's header (PC_PRJ_STARTER_HEADER),
  // each '  <Field>:' on its own line for the user to fill in
  PC_TEST_PRJ_STARTER_FIELDS: array[0..3] of string = (
    'Description',
    'Author',
    'Copyright',
    'License'
  );

  { PC_TEST_PRJ_BOX_WIDTH }
  // Every line of a .cmd header's '::' box, in characters
  PC_TEST_PRJ_BOX_WIDTH = 79;

  { PC_TEST_PRJ_PACK_PREFIX }
  // A pack case's folder: this prefix and the case (prj_pack_entries, ...)
  PC_TEST_PRJ_PACK_PREFIX = 'prj_pack_';

  { PC_TEST_PRJ_PACK_PASSWORD }
  // A pack case's password: a quote, lone and doubled backslashes before a
  // quote, a blank and a trailing backslash, the forms a command line must
  // carry exactly (pcpp to the packer, pcpp to the reader after --)
  PC_TEST_PRJ_PACK_PASSWORD = 'q"w\e\\"r x\';

  { PC_TEST_PRJ_PACK_TOML }
  // A pack case's project.toml (%0:s = the name, %1:s = the password, a
  // TOML literal string: the password holds no single quote)
  PC_TEST_PRJ_PACK_TOML = '''
format = 1

[project]
name = "%0:s"
type = "exe"
main = "src/%0:s.pcpp"

[pack]
password = '%1:s'
''';

  { PC_TEST_PRJ_PACK_READER }
  // A pack case's main module (%0:s = the name): reads its .dat beside it
  // with the password it is given and prints each entry's text in brackets,
  // or none / unreadable
  PC_TEST_PRJ_PACK_READER = '''
module exe %0:s;

import
  CustomIO;

// One entry of $P:%0:s.dat read with APassword: its text, "none" when it
// does not open (a wrong password, no such entry), "unreadable" when it
// opens but its bytes do not come out
routine Show(const AEntry: string; const APassword: string);
var
  LEntry: IO;
  LText: string;
begin
  LEntry := CreateZipFileIO("$P:%0:s.dat", AEntry, APassword);
  if LEntry = nil then
    println("{} none", AEntry);
    return;
  end;
  LText := "";
  if IOReadAll(LEntry, LText) then
    println("{} [{}]", AEntry, LText);
  else
    println("{} unreadable", AEntry);
  end;
  IOClose(LEntry);
end;

begin
  Show("hello.txt", paramstr(1));
  Show("sprites/ship.txt", paramstr(1));
  Show("ünï €.txt", paramstr(1));
  Show("assets/hello.txt", paramstr(1));
end.
''';

  { PC_TEST_PRJ_PACKER_EXE }
  // The packer pcpp pack builds, by its file name
  PC_TEST_PRJ_PACKER_EXE = 'AssetPacker.exe';

  { PC_TEST_PRJ_PACK_ENTRIES }
  // The files a pack case puts in assets\, by their entry names: one at the
  // top, one a folder down, one non-ASCII name (stored as UTF-8)
  PC_TEST_PRJ_PACK_ENTRIES: array[0..2] of string = (
    'hello.txt',
    'sprites/ship.txt',
    'ünï €.txt'
  );

  { PC_TEST_PRJ_PACK_PLAIN }
  // A plain file build inside the clean case's project (not its main
  // module): an output folder of a project's tree that is not the project's
  PC_TEST_PRJ_PACK_PLAIN = '''
module exe prj_pack_clean_plain;

begin
end.
''';

  { PC_TEST_PRJ_PACK_TEXTS }
  // Each entry's text, in PC_TEST_PRJ_PACK_ENTRIES' order
  PC_TEST_PRJ_PACK_TEXTS: array[0..2] of string = (
    'hello',
    'ship',
    'utf8'
  );

  { PC_TEST_PRJ_SECRET_PREFIX }
  // A password case's folder: a pack case (DoFreshCase clears it), this
  // prefix and the case (prj_pack_secret_open, ...)
  PC_TEST_PRJ_SECRET_PREFIX = 'prj_pack_secret_';

  { PC_TEST_PRJ_SECRET_TOML }
  // A password case's project.toml with no [pack] password (%0:s = the name)
  PC_TEST_PRJ_SECRET_TOML = '''
format = 1

[project]
name = "%0:s"
type = "exe"
main = "src/%0:s.pcpp"
''';

  { PC_TEST_PRJ_SECRET_READER }
  // A password case's main module (%0:s = the name): opens its .dat with
  // ProjectPassword() alone (no password text of its own, so none can be in
  // the exe), prints the password's length, then each entry as the pack
  // reader does (its text in brackets, none, unreadable)
  PC_TEST_PRJ_SECRET_READER = '''
module exe %0:s;

import
  CustomIO;

// One entry of $P:%0:s.dat read with the project's password
routine Show(const AEntry: string);
var
  LEntry: IO;
  LText: string;
begin
  LEntry := CreateZipFileIO("$P:%0:s.dat", AEntry, ProjectPassword());
  if LEntry = nil then
    println("{} none", AEntry);
    return;
  end;
  LText := "";
  if IOReadAll(LEntry, LText) then
    println("{} [{}]", AEntry, LText);
  else
    println("{} unreadable", AEntry);
  end;
  IOClose(LEntry);
end;

begin
  println("password length {}", len(ProjectPassword()));
  Show("hello.txt");
  Show("sprites/ship.txt");
  Show("ünï €.txt");
end.
''';

  { PC_TEST_PRJ_SECRET_CHANGED }
  // The password a stale case changes project.toml to after packing
  PC_TEST_PRJ_SECRET_CHANGED = 'changed-Pa55word';

  { PC_TEST_PRJ_SECRET_WINDOW }
  // The longest run of the password's bytes a scanned file may hold: any
  // longer run found is a leak of part of the text
  PC_TEST_PRJ_SECRET_WINDOW = 5;

  { PC_TEST_PRJ_SECRET_CONTROL }
  // Text the reader's exe does hold (its println format): finding it proves
  // a scan reads the binary at all
  PC_TEST_PRJ_SECRET_CONTROL = '{} unreadable';

  { PC_TEST_PRJ_SECRET_CALL_MARK }
  // How the generated C++ writes ProjectPassword(): the runtime call with
  // the scrambled bytes as \x escapes
  PC_TEST_PRJ_SECRET_CALL_MARK = '::pcpp::project_password("\x';

  { PC_TEST_PRJ_SECRET_CALL }
  // An analyze case's module (%0:s = the name, %1:s = the call written)
  PC_TEST_PRJ_SECRET_CALL = '''
module exe %0:s;

begin
  println("{}", len(%1:s));
end.
''';

  { PC_TEST_PRJ_STALE_PREFIX }
  // A stale-file case's folder: this prefix and the case (prj_stale_debug, ...)
  PC_TEST_PRJ_STALE_PREFIX = 'prj_stale_';

  { PC_TEST_PRJ_STALE_TOML }
  // A stale-file case's project.toml (%0:s = the project name, %1:s = the
  // main module's file stem, which names the artifact)
  PC_TEST_PRJ_STALE_TOML = '''
format = 1

[project]
name = "%0:s"
type = "exe"
main = "src/%1:s.pcpp"
''';

  { PC_TEST_PRJ_STALE_SOURCE }
  // A stale-file case's module (%0:s = the module name): an empty program
  PC_TEST_PRJ_STALE_SOURCE = '''
module exe %0:s;

begin
end.
''';

  { PC_TEST_PRJ_STALE_PLAIN_DIR }
  // The folder of a stale case's plain sources (not the main module: a
  // plain build, PLAN-PROJECTS DECISIONS)
  PC_TEST_PRJ_STALE_PLAIN_DIR = 'plain';

{ TPCProjectTests }

constructor TPCProjectTests.Create();
begin
  inherited;

  AreaName := 'prj';
  RegisterTest('find', DoTestFind);
  RegisterTest('load_ok', DoTestLoadOk);
  RegisterTest('load_defaults', DoTestLoadDefaults);
  RegisterTest('load_bad', DoTestLoadBad);
  RegisterTest('names', DoTestNames);
  RegisterTest('kinds', DoTestKinds);
  RegisterTest('save_refused', DoTestSaveRefused);
  RegisterTest('save_roundtrip', DoTestSaveRoundtrip);
  RegisterTest('root_resolve', DoTestRootResolve);
  RegisterTest('root_parse', DoTestRootParse);
  RegisterTest('compile_output', DoTestCompileOutput);
  RegisterTest('compile_bad_toml', DoTestCompileBadToml);
  RegisterTest('compile_kind', DoTestCompileKind);
  RegisterTest('init_exe', DoTestInitExe);
  RegisterTest('init_dll', DoTestInitDll);
  RegisterTest('init_lib', DoTestInitLib);
  RegisterTest('init_exists', DoTestInitExists);
  RegisterTest('init_password', DoTestInitPassword);
  RegisterTest('pack_entries', DoTestPackEntries);
  RegisterTest('pack_wrong_password', DoTestPackWrongPassword);
  RegisterTest('pack_empty', DoTestPackEmpty);
  RegisterTest('pack_clean', DoTestPackClean);
  RegisterTest('password_open', DoTestPasswordOpen);
  RegisterTest('password_hidden', DoTestPasswordHidden);
  RegisterTest('password_stale', DoTestPasswordStale);
  RegisterTest('password_none', DoTestPasswordNone);
  RegisterTest('password_analyze', DoTestPasswordAnalyze);
  RegisterTest('stale_debug_to_fast', DoTestStaleDebugToFast);
  RegisterTest('stale_rename', DoTestStaleRename);
  RegisterTest('stale_plain_kept', DoTestStalePlainKept);
  RegisterTest('stale_shared_name', DoTestStaleSharedName);
  RegisterTest('stale_other_output', DoTestStaleOtherOutput);
  RegisterTest('stale_plain_unchanged', DoTestStalePlainUnchanged);
  RegisterTest('stale_clean', DoTestStaleClean);
end;

function TPCProjectTests.DoNewErrors(): TErrors;
begin
  Result := TErrors.Create();
  Result.SetMaxErrors(PC_TEST_PRJ_MAX_ERRORS);
end;

function TPCProjectTests.DoReportCodes(const AErrors: TErrors): string;
var
  LCodes: TList<string>;
  LError: TError;
  LText: string;
begin
  // Every report's code (a warning marked), sorted: the order reports come
  // in is the reader's, not this test's concern
  LCodes := TList<string>.Create();
  try
    for LError in AErrors.GetItems() do
    begin
      LText := LError.Code;
      if LError.Severity = esWarning then
        LText := LText + PC_TEST_PRJ_WARN;
      LCodes.Add(LText);
    end;
    LCodes.Sort();
    Result := string.Join(' ', LCodes.ToArray());
  finally
    LCodes.Free();
  end;
end;

procedure TPCProjectTests.DoCheckCodes(const AErrors: TErrors;
  const AExpected: array of string; const ALabel: string);
var
  LExpected: TList<string>;
  LCode: string;
begin
  LExpected := TList<string>.Create();
  try
    for LCode in AExpected do
      LExpected.Add(LCode);
    LExpected.Sort();
    CheckEqual(string.Join(' ', LExpected.ToArray()), DoReportCodes(AErrors), ALabel);
  finally
    LExpected.Free();
  end;
end;

function TPCProjectTests.DoLoad(const AProject: TPCProject; const AErrors: TErrors;
  const ARoot: string): Boolean;
begin
  // Loads the project at ARoot ('' = the harness refused the path: failed)
  AProject.SetErrors(AErrors);
  if ARoot = '' then
    Exit(False);
  Result := AProject.Load(ARoot);
end;

procedure TPCProjectTests.DoCheckBad(const ALabel: string; const ARoot: string;
  const AExpected: array of string);
var
  LErrors: TErrors;
  LProject: TPCProject;
begin
  Section(ALabel);
  LErrors := DoNewErrors();
  LProject := TPCProject.Create();
  try
    Check(not DoLoad(LProject, LErrors, ARoot), '%s: refused', [ALabel]);
    DoCheckCodes(LErrors, AExpected, ALabel + ': reports');
  finally
    LProject.Free();
    LErrors.Free();
  end;
end;

procedure TPCProjectTests.DoCheckFind(const AStart: string; const AExpected: string;
  const ALabel: string);
var
  LErrors: TErrors;
  LProject: TPCProject;
  LFound: string;
begin
  LErrors := DoNewErrors();
  LProject := TPCProject.Create();
  try
    LProject.SetErrors(LErrors);
    LFound := LProject.Find(AStart);
    if AExpected = '' then
      CheckEqual('', LFound, ALabel)
    else
      Check(TUtils.SamePath(AExpected, LFound), '%s: %s found (got ''%s'')',
        [ALabel, AExpected, LFound]);
    DoCheckCodes(LErrors, [], ALabel + ': no reports');
  finally
    LProject.Free();
    LErrors.Free();
  end;
end;

procedure TPCProjectTests.DoTestFind(const ACell: TPCTestCell);
begin
  // From the main module, from a folder, from the root itself
  Section('nearest');
  DoCheckFind(Fixture('ok/src/prj_ok.pcpp'), Fixture('ok'), 'a file in src');
  DoCheckFind(Fixture('ok/src'), Fixture('ok'), 'the src folder');
  DoCheckFind(Fixture('ok'), Fixture('ok'), 'the root');

  // A project inside a project: the nearest wins, from either side
  Section('nested');
  DoCheckFind(Fixture('nested/inner/src/prj_inner.pcpp'), Fixture('nested/inner'),
    'inside the inner project');
  DoCheckFind(Fixture('nested/src/prj_outer.pcpp'), Fixture('nested'),
    'inside the outer project');

  // No project.toml at or above the area's folder: '' and no report
  Section('none');
  DoCheckFind(AreaFolder(), '', 'no project above');
end;

procedure TPCProjectTests.DoTestLoadOk(const ACell: TPCTestCell);
var
  LErrors: TErrors;
  LProject: TPCProject;
begin
  LErrors := DoNewErrors();
  LProject := TPCProject.Create();
  try
    Check(DoLoad(LProject, LErrors, Fixture('ok')), 'ok: loaded');
    DoCheckCodes(LErrors, [], 'ok: no reports');
    CheckEqual(Int64(1), LProject.FileFormat, 'format');
    CheckEqual('prj_ok', LProject.ProjectName, 'name');
    Check(LProject.Kind = pkDll, 'type dll');
    CheckEqual('src/prj_ok.pcpp', LProject.MainModule, 'main as written');
    CheckEqual('build/out', LProject.OutputDir, 'output as written');
    CheckEqual('Abc 123 !~', LProject.Password, 'password');
    Check(TUtils.SamePath(Fixture('ok'), LProject.Root), 'root');
    Check(TUtils.SamePath(Fixture('ok/project.toml'), LProject.FileName), 'file name');
    Check(TUtils.SamePath(Fixture('ok/src/prj_ok.pcpp'), LProject.MainPath()), 'main path');
    Check(TUtils.SamePath(Fixture('ok/build/out'), LProject.OutputPath()), 'output path');
  finally
    LProject.Free();
    LErrors.Free();
  end;

  // A lib project found inside another project loads on its own
  LErrors := DoNewErrors();
  LProject := TPCProject.Create();
  try
    Check(DoLoad(LProject, LErrors, Fixture('nested/inner')), 'inner: loaded');
    DoCheckCodes(LErrors, [], 'inner: no reports');
    Check(LProject.Kind = pkLib, 'inner: type lib');
    CheckEqual('prj_inner', LProject.ProjectName, 'inner: name');
  finally
    LProject.Free();
    LErrors.Free();
  end;
end;

procedure TPCProjectTests.DoTestLoadDefaults(const ACell: TPCTestCell);
var
  LErrors: TErrors;
  LProject: TPCProject;
begin
  LErrors := DoNewErrors();
  LProject := TPCProject.Create();
  try
    Check(DoLoad(LProject, LErrors, Fixture('defaults')), 'defaults: loaded');
    DoCheckCodes(LErrors, [], 'defaults: no reports');
    Check(LProject.Kind = pkExe, 'type exe');
    CheckEqual(PC_PRJ_OUTPUT_DEFAULT, LProject.OutputDir, 'output defaults');
    CheckEqual('', LProject.Password, 'no password');
    Check(TUtils.SamePath(Fixture('defaults/output'), LProject.OutputPath()), 'output path');
  finally
    LProject.Free();
    LErrors.Free();
  end;
end;

procedure TPCProjectTests.DoTestLoadBad(const ACell: TPCTestCell);
begin
  DoCheckBad('bad_parse', Fixture('bad_parse'), ['PJ0001']);
  DoCheckBad('bad_missing', Fixture('bad_missing'), ['PJ0002', 'PJ0002', 'PJ0002']);
  DoCheckBad('bad_types', Fixture('bad_types'),
    ['PJ0003', 'PJ0003', 'PJ0003', 'PJ0003', 'PJ0003', 'PJ0003']);
  DoCheckBad('bad_values', Fixture('bad_values'),
    ['PJ0011', 'PJ0005', 'PJ0006', 'PJ0007', 'PJ0009', 'PJ0010',
    'PJ0004' + PC_TEST_PRJ_WARN, 'PJ0004' + PC_TEST_PRJ_WARN]);
  DoCheckBad('bad_paths', Fixture('bad_paths'), ['PJ0008', 'PJ0009']);
  DoCheckBad('bad_ext', Fixture('bad_ext'), ['PJ0005', 'PJ0007', 'PJ0009']);

  // A folder with no project.toml at all (the area's own folder)
  DoCheckBad('no file', AreaFolder(), ['PJ0001']);
end;

procedure TPCProjectTests.DoTestNames(const ACell: TPCTestCell);
begin
  Section('valid');
  CheckEqual('', TPCProject.NameProblem('Defender'), 'Defender');
  CheckEqual('', TPCProject.NameProblem('_a1'), '_a1');
  CheckEqual('', TPCProject.NameProblem('prj_ok'), 'prj_ok');

  Section('not valid');
  Check(TPCProject.NameProblem('') <> '', 'empty');
  Check(TPCProject.NameProblem('9lives') <> '', 'starts with a digit');
  Check(TPCProject.NameProblem('my-game') <> '', 'a hyphen');
  Check(TPCProject.NameProblem('my game') <> '', 'a blank');
  Check(TPCProject.NameProblem('caf'#$00E9) <> '', 'a letter outside ASCII');
  Check(TPCProject.NameProblem('module') <> '', 'a PaskalCPP keyword');
  Check(TPCProject.NameProblem('Begin') <> '', 'a keyword in another case');
  Check(TPCProject.NameProblem('class') <> '', 'a C++ keyword');
  Check(TPCProject.NameProblem('int32') <> '', 'a built-in type');
  Check(TPCProject.NameProblem('nul') <> '', 'a device name');
  Check(TPCProject.NameProblem('LPT9') <> '', 'a numbered device name');
end;

procedure TPCProjectTests.DoTestKinds(const ACell: TPCTestCell);
var
  LKind: TPCProjectKind;
  LRead: TPCProjectKind;
  LText: string;
begin
  // Every kind's text reads back as that kind
  for LKind := Low(TPCProjectKind) to High(TPCProjectKind) do
  begin
    LText := PC_PRJ_KIND_TEXT[LKind];
    Check(TPCProject.KindFromText(LText, LRead) and (LRead = LKind),
      '%s reads back', [LText]);
  end;

  Check(not TPCProject.KindFromText('EXE', LRead), 'EXE (case) refused');
  Check(not TPCProject.KindFromText('app', LRead), 'app refused');
  Check(not TPCProject.KindFromText('', LRead), 'empty refused');
end;

procedure TPCProjectTests.DoTestSaveRefused(const ACell: TPCTestCell);
var
  LErrors: TErrors;
  LProject: TPCProject;
  LRoot: string;
begin
  // A new model whose main module is not there: Save validates first, so it
  // reports PJ0008 and writes no project.toml
  LRoot := ScratchFolder();
  LErrors := DoNewErrors();
  LProject := TPCProject.Create();
  try
    LProject.SetErrors(LErrors);
    LProject.InitNew(LRoot, 'prj_save_refused', pkExe, 'secret');
    Check(not LProject.Save(), 'save refused');
    DoCheckCodes(LErrors, ['PJ0008'], 'save: reports');
    Check(not TFile.Exists(TPath.Combine(LRoot, PC_PRJ_FILE_NAME)), 'no project.toml written');
  finally
    LProject.Free();
    LErrors.Free();
  end;

  // A bad name is refused the same way, before any file is touched
  LErrors := DoNewErrors();
  LProject := TPCProject.Create();
  try
    LProject.SetErrors(LErrors);
    LProject.InitNew(LRoot, 'my-game', pkExe, '');
    Check(not LProject.Save(), 'bad name: save refused');
    DoCheckCodes(LErrors, ['PJ0005', 'PJ0008'], 'bad name: reports');
    Check(not TFile.Exists(TPath.Combine(LRoot, PC_PRJ_FILE_NAME)), 'bad name: nothing written');
  finally
    LProject.Free();
    LErrors.Free();
  end;
end;

function TPCProjectTests.DoSetupSaveFolder(out ARoot: string): Boolean;
var
  LMain: string;
begin
  // output\prj_save_roundtrip: its main module in place, no project.toml
  // left from an earlier run (so what Load reads is this run's Save)
  Result := False;
  ARoot := Scratch(PC_TEST_PRJ_SAVE_NAME);
  if ARoot = '' then
    Exit;

  try
    LMain := TPath.Combine(TPath.Combine(ARoot, PC_PRJ_SRC_DIR), PC_TEST_PRJ_SAVE_NAME + '.pcpp');
    TDirectory.CreateDirectory(TPath.GetDirectoryName(LMain));
    TFile.WriteAllText(LMain, PC_TEST_PRJ_SAVE_SOURCE, TEncoding.UTF8);
    if TFile.Exists(TPath.Combine(ARoot, PC_PRJ_FILE_NAME)) then
      TFile.Delete(TPath.Combine(ARoot, PC_PRJ_FILE_NAME));
  except
    on E: Exception do
    begin
      Fail(Format('%s cannot be set up: %s', [ARoot, E.Message]));
      Exit;
    end;
  end;
  Result := True;
end;

procedure TPCProjectTests.DoCheckRoundtrip(const ARoot: string;
  const AKind: TPCProjectKind; const APassword: string; const ALabel: string);
var
  LErrors: TErrors;
  LProject: TPCProject;
  LBack: TPCProject;
  LText: string;
begin
  LErrors := DoNewErrors();
  LProject := TPCProject.Create();
  LBack := TPCProject.Create();
  try
    // Save a new model
    LProject.SetErrors(LErrors);
    LProject.InitNew(ARoot, PC_TEST_PRJ_SAVE_NAME, AKind, APassword);
    Check(LProject.Save(), '%s: saved', [ALabel]);
    DoCheckCodes(LErrors, [], ALabel + ': save reports nothing');

    // Read it back: the same fields, no report (no unknown key either)
    LBack.SetErrors(LErrors);
    Check(LBack.Load(ARoot), '%s: loaded back', [ALabel]);
    DoCheckCodes(LErrors, [], ALabel + ': load reports nothing');
    CheckEqual(Int64(PC_PRJ_FORMAT), LBack.FileFormat, ALabel + ': format');
    CheckEqual(PC_TEST_PRJ_SAVE_NAME, LBack.ProjectName, ALabel + ': name');
    Check(LBack.Kind = AKind, '%s: type %s', [ALabel, PC_PRJ_KIND_TEXT[AKind]]);
    CheckEqual(PC_PRJ_SRC_DIR + '/' + PC_TEST_PRJ_SAVE_NAME + '.pcpp', LBack.MainModule,
      ALabel + ': main');
    CheckEqual(PC_PRJ_OUTPUT_DEFAULT, LBack.OutputDir, ALabel + ': output');
    CheckEqual(APassword, LBack.Password, ALabel + ': password');

    // No password = no [pack] table at all
    try
      LText := TFile.ReadAllText(LBack.FileName, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        Fail(Format('%s: %s cannot be read: %s', [ALabel, LBack.FileName, E.Message]));
        Exit;
      end;
    end;
    CheckEqual(APassword <> '', LText.Contains('[' + PC_PRJ_TABLE_PACK + ']'),
      ALabel + ': [pack] table only with a password');
  finally
    LBack.Free();
    LProject.Free();
    LErrors.Free();
  end;
end;

procedure TPCProjectTests.DoTestSaveRoundtrip(const ACell: TPCTestCell);
var
  LRoot: string;
begin
  Section('with password');
  if not DoSetupSaveFolder(LRoot) then
    Exit;
  DoCheckRoundtrip(LRoot, pkLib, 'p@ss word ~#"\', 'with password');

  // A second Save over the first: no password, another kind
  Section('no password');
  DoCheckRoundtrip(LRoot, pkDll, '', 'no password');
end;

function TPCProjectTests.DoRaisesNoRoot(const APath: string; const ARoot: string): Boolean;
begin
  // True when ResolvePath refuses APath for want of a root: it raises, and
  // the message names the path as written (RSUtlNoProjectRoot)
  Result := False;
  try
    TUtils.ResolvePath(APath, '', ARoot);
  except
    on E: Exception do
      Result := E.Message.Contains(APath);
  end;
end;

procedure TPCProjectTests.DoTestRootResolve(const ACell: TPCTestCell);
var
  LRoot: string;
  LBase: string;
begin
  LRoot := Fixture('root');
  LBase := Fixture('ok');

  // $R: resolves against the root it is given, in either case, over any
  // base; a rooted path after it is only normalized
  Section('with a root');
  Check(TUtils.SamePath(Fixture('root/src/prj_root.pcpp'),
    TUtils.ResolvePath('$R:src/prj_root.pcpp', '', LRoot)), 'a relative path');
  Check(TUtils.SamePath(Fixture('root/src'), TUtils.ResolvePath('$r:src', '', LRoot)),
    'lower case prefix');
  Check(TUtils.SamePath(Fixture('root/src'), TUtils.ResolvePath('$R:src', LBase, LRoot)),
    'the root wins over the base');
  Check(TUtils.SamePath(Fixture('root/units'), TUtils.ResolvePath('$R:  units', '', LRoot)),
    'trim after prefix');
  CheckEqual('', TUtils.ResolvePath('$R:  ', '', LRoot), 'prefix only');
  Check(TUtils.SamePath(LBase, TUtils.ResolvePath('$R:' + LBase, '', LRoot)),
    'a rooted path after the prefix');

  // The root changes nothing for a path without $R:
  Section('other paths');
  Check(TUtils.SamePath(Fixture('ok/x'), TUtils.ResolvePath('x', LBase, LRoot)),
    'no prefix: the base');
  Check(TUtils.SamePath(Fixture('ok/x'), TUtils.ResolvePath('$S:x', LBase, LRoot)),
    '$S: the base');

  // No root: raised, never a silent fallback to the base or the CWD
  Section('no root');
  Check(DoRaisesNoRoot('$R:src', ''), 'no root raises');
  Check(DoRaisesNoRoot('$R:src', '   '), 'a blank root raises');
end;

function TPCProjectTests.DoParseRoot(const AErrors: TErrors; const AAst: TPCAst;
  const ARoot: string): TPCModule;
begin
  // The fixture's main module parsed as the compiler parses one: no targets,
  // no module paths, the disk only; ARoot is the project root ('' = none)
  AAst.SetErrors(AErrors);
  Result := ParseModuleFile(AAst, AErrors, Fixture('root/src/prj_root.pcpp'), nil,
    Default(TPCTargetTriple), Default(TPCTargetTriple), Default(TPCTargetTriple), nil,
    nil, False, ARoot);
end;

procedure TPCProjectTests.DoCheckPathArg(const AModule: TPCModule;
  const AKind: TPCBuildDirective; const AExpected: string; const ALabel: string);
var
  LDirective: TPCDirective;
  LFound: Boolean;
begin
  // The module's first directive of AKind holds AExpected, resolved once by
  // the parser (Args[0].ResolvedText)
  LFound := False;
  for LDirective in AModule.Directives do
  begin
    if (LDirective.DirectiveKind <> AKind) or (LDirective.Args.Count = 0) then
      Continue;
    LFound := True;
    Check(TUtils.SamePath(AExpected, LDirective.Args[0].ResolvedText), '%s: %s (got ''%s'')',
      [ALabel, AExpected, LDirective.Args[0].ResolvedText]);
    Break;
  end;
  Check(LFound, '%s: directive found', [ALabel]);
end;

procedure TPCProjectTests.DoTestRootParse(const ACell: TPCTestCell);
var
  LErrors: TErrors;
  LAst: TPCAst;
  LMain: TPCModule;
  LUnit: TPCModule;
begin
  // With the root: every $R: directive resolves under it, the import is
  // found through $R:units, and the unit's own $R: gets the same root
  Section('with a root');
  LErrors := DoNewErrors();
  LAst := TPCAst.Create();
  try
    LMain := DoParseRoot(LErrors, LAst, Fixture('root'));
    DoCheckCodes(LErrors, [], 'no reports');
    DoCheckPathArg(LMain, bdAddModulePath, Fixture('root/units'), 'main $R:units');
    DoCheckPathArg(LMain, bdAddIncludePath, Fixture('root/inc'), 'main $r:inc');
    LUnit := LAst.FindModule('prj_root_unit');
    Check(LUnit <> nil, 'the unit is found through $R:units');
    if LUnit <> nil then
      DoCheckPathArg(LUnit, bdAddIncludePath, Fixture('root/units/inc'), 'unit $R:units/inc');
  finally
    LAst.Free();
    LErrors.Free();
  end;

  // No root: each $R: directive is PR0065 (not PR0022), and the import its
  // module path would have found is not found (PR0012)
  Section('no root');
  LErrors := DoNewErrors();
  LAst := TPCAst.Create();
  try
    DoParseRoot(LErrors, LAst, '');
    DoCheckCodes(LErrors, ['PR0012', 'PR0065', 'PR0065'], 'reports');
  finally
    LAst.Free();
    LErrors.Free();
  end;
end;

function TPCProjectTests.DoWriteCase(const ACase: string; const AToml: string;
  const ASourceName: string; const ASource: string; out AMain: string): string;
begin
  // output\<ACase>: its project.toml and src\<ASourceName>.pcpp, written
  // fresh each run (no BOM: what pcpp init writes). The one subfolder a
  // project test may make (user 2026-10-29). '' = not written (a failed check)
  AMain := '';
  Result := Scratch(ACase);
  if Result = '' then
    Exit;
  try
    AMain := TPath.Combine(TPath.Combine(Result, PC_PRJ_SRC_DIR), ASourceName + '.pcpp');
    TDirectory.CreateDirectory(TPath.GetDirectoryName(AMain));
    TFile.WriteAllBytes(TPath.Combine(Result, PC_PRJ_FILE_NAME), TEncoding.UTF8.GetBytes(AToml));
    TFile.WriteAllBytes(AMain, TEncoding.UTF8.GetBytes(ASource));
  except
    on E: Exception do
    begin
      Fail(Format('%s cannot be set up: %s', [ACase, E.Message]));
      AMain := '';
      Result := '';
    end;
  end;
end;

procedure TPCProjectTests.DoTestCompileOutput(const ACell: TPCTestCell);
const
  { PC_TEST_PRJ_OUT_NAME }
  PC_TEST_PRJ_OUT_NAME = 'prj_compile_output';
  { PC_TEST_PRJ_OTHER_NAME }
  PC_TEST_PRJ_OTHER_NAME = 'prj_compile_other';
var
  LRoot: string;
  LMain: string;
  LOther: string;
  LCompiler: TPCCompiler;
begin
  LRoot := DoWriteCase(PC_TEST_PRJ_OUT_NAME,
    Format(PC_TEST_PRJ_CASE_TOML, [PC_TEST_PRJ_OUT_NAME, PC_PRJ_KIND_TEXT[pkExe], PC_TEST_PRJ_OUT_NAME]),
    PC_TEST_PRJ_OUT_NAME, Format(PC_TEST_PRJ_CASE_EXE, [PC_TEST_PRJ_OUT_NAME]), LMain);
  if LRoot = '' then
    Exit;
  // A second exe in the project's src\, not its main module
  LOther := TPath.Combine(TPath.GetDirectoryName(LMain), PC_TEST_PRJ_OTHER_NAME + '.pcpp');
  try
    TFile.WriteAllBytes(LOther, TEncoding.UTF8.GetBytes(Format(PC_TEST_PRJ_CASE_EXE,
      [PC_TEST_PRJ_OTHER_NAME])));
  except
    on E: Exception do
    begin
      Fail(Format('%s cannot be written: %s', [LOther, E.Message]));
      Exit;
    end;
  end;

  // The main module, no -o, no host default: the project's root and its
  // output folder (<root>\output); the build's files land inside the case
  Section('project default');
  LCompiler := TPCCompiler.Create();
  try
    Check(LCompiler.Prepare(LMain, ''), 'prepared');
    CheckEqual('', DoReportCodes(LCompiler.GetErrors()), 'no reports');
    Check(TUtils.SamePath(LRoot, LCompiler.GetProjectRoot()), 'project root (got ''%s'')',
      [LCompiler.GetProjectRoot()]);
    Check(TUtils.SamePath(TUtils.ResolvePath(PC_PRJ_OUTPUT_DEFAULT, LRoot), LCompiler.GetOutputPath()),
      'output <root>\%s (got ''%s'')', [PC_PRJ_OUTPUT_DEFAULT, LCompiler.GetOutputPath()]);
  finally
    LCompiler.Free();
  end;

  // A host's default folder (testbed's own) wins over the project's: a
  // project under res\tests never writes outside the output folder
  Section('host default');
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetDefaultOutputPath(ScratchFolder());
    Check(LCompiler.Prepare(LMain, ''), 'host: prepared');
    Check(TUtils.SamePath(LRoot, LCompiler.GetProjectRoot()), 'host: still a project build');
    Check(TUtils.SamePath(ScratchFolder(), LCompiler.GetOutputPath()), 'host: output (got ''%s'')',
      [LCompiler.GetOutputPath()]);
  finally
    LCompiler.Free();
  end;

  // A file in the project that is not its main module: a plain build
  Section('not the main module');
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetDefaultOutputPath(ScratchFolder());
    Check(LCompiler.Prepare(LOther, ''), 'other: prepared');
    CheckEqual('', LCompiler.GetProjectRoot(), 'other: no project');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCProjectTests.DoTestCompileBadToml(const ACell: TPCTestCell);
const
  { PC_TEST_PRJ_BAD_NAME }
  PC_TEST_PRJ_BAD_NAME = 'prj_compile_bad_toml';
var
  LRoot: string;
  LMain: string;
  LCompiler: TPCCompiler;
begin
  // An invalid project.toml above the source stops the check with its PJ
  // report (user 2026-10-29): whether the source is the main module cannot
  // be told. Analyze parses only: nothing is written
  LRoot := DoWriteCase(PC_TEST_PRJ_BAD_NAME, PC_TEST_PRJ_BAD_TOML, PC_TEST_PRJ_BAD_NAME,
    Format(PC_TEST_PRJ_CASE_EXE, [PC_TEST_PRJ_BAD_NAME]), LMain);
  if LRoot = '' then
    Exit;
  LCompiler := TPCCompiler.Create();
  try
    Check(not LCompiler.Analyze(LMain), 'refused');
    CheckEqual('PJ0001', DoReportCodes(LCompiler.GetErrors()), 'reports');
    CheckEqual('', LCompiler.GetProjectRoot(), 'no project');
  finally
    LCompiler.Free();
  end;
end;

procedure TPCProjectTests.DoTestCompileKind(const ACell: TPCTestCell);
const
  { PC_TEST_PRJ_KIND_NAME }
  PC_TEST_PRJ_KIND_NAME = 'prj_compile_kind';
var
  LRoot: string;
  LMain: string;
  LCompiler: TPCCompiler;
begin
  // project.toml says dll, the main module says exe: CMP0009 (SEM still
  // runs: no phase gate)
  LRoot := DoWriteCase(PC_TEST_PRJ_KIND_NAME,
    Format(PC_TEST_PRJ_CASE_TOML, [PC_TEST_PRJ_KIND_NAME, PC_PRJ_KIND_TEXT[pkDll], PC_TEST_PRJ_KIND_NAME]),
    PC_TEST_PRJ_KIND_NAME, Format(PC_TEST_PRJ_CASE_EXE, [PC_TEST_PRJ_KIND_NAME]), LMain);
  if LRoot = '' then
    Exit;
  LCompiler := TPCCompiler.Create();
  try
    Check(not LCompiler.Analyze(LMain), 'refused');
    CheckEqual('CMP0009', DoReportCodes(LCompiler.GetErrors()), 'reports');
    Check(TUtils.SamePath(LRoot, LCompiler.GetProjectRoot()), 'a project build');
  finally
    LCompiler.Free();
  end;
end;

function TPCProjectTests.DoFreshCase(const ACase: string): string;
begin
  // output\<ACase>, gone before the case starts (an earlier run's tree would
  // make pcpp init refuse). Only an init, pack or stale case's own folder,
  // directly in the output folder, is ever removed; '' (and a failed check)
  // otherwise
  Result := Scratch(ACase);
  if Result = '' then
    Exit;
  if ((not ACase.StartsWith(PC_TEST_PRJ_INIT_PREFIX)) and
    (not ACase.StartsWith(PC_TEST_PRJ_PACK_PREFIX)) and
    (not ACase.StartsWith(PC_TEST_PRJ_STALE_PREFIX))) or
    (not TUtils.SamePath(TPath.GetDirectoryName(Result), ScratchFolder())) then
  begin
    Fail(Format('%s is not an init, pack or stale case folder in the output folder', [Result]));
    Exit('');
  end;
  // Never through a link (TUtils.DeleteTree): what stays is the failure
  TUtils.DeleteTree(Result);
  if TDirectory.Exists(Result) then
  begin
    Fail(Format('%s cannot be cleared', [Result]));
    Exit('');
  end;
end;

function TPCProjectTests.DoRunPcpp(const AArgs: string; out AOutput: string): Int64;
var
  LExe: string;
  LExitCode: DWORD;
  LBuilder: TStringBuilder;
begin
  // pcpp.exe with AArgs, run in the output folder over pipes (stdout and
  // stderr in written order): its whole output and its exit code; -1 (and a
  // failed check) when it cannot be started
  AOutput := '';
  Result := -1;
  LExitCode := 0;
  LBuilder := TStringBuilder.Create();
  try
    try
      LExe := TUtils.ResolvePath(PC_TEST_PRJ_PCPP);
      TUtils.RunPE(LExe, AArgs, ScratchFolder(), LExitCode, nil,
        procedure(const ALine: string; const AUserData: Pointer)
        begin
          LBuilder.Append(ALine);
          LBuilder.Append(#10);
        end, True);
    except
      on E: Exception do
      begin
        Fail(Format('pcpp %s cannot be run: %s', [AArgs, E.Message]));
        Exit;
      end;
    end;
    AOutput := LBuilder.ToString();
    Result := LExitCode;
  finally
    LBuilder.Free();
  end;
end;

function TPCProjectTests.DoOutputPath(const AOutput: string): string;
var
  LStart: Integer;
  LEnd: Integer;
begin
  // The path on pcpp's 'Output: ' line, up to the line's end or the colour
  // code that ends it; '' when there is no such line
  Result := '';
  LStart := AOutput.IndexOf(PC_TEST_PRJ_OUTPUT_MARK);
  if LStart < 0 then
    Exit;
  LStart := LStart + Length(PC_TEST_PRJ_OUTPUT_MARK);
  LEnd := LStart;
  while (LEnd < AOutput.Length) and (not CharInSet(AOutput.Chars[LEnd], [#10, #13, #27])) do
    Inc(LEnd);
  Result := AOutput.Substring(LStart, LEnd - LStart).Trim();
end;

function TPCProjectTests.DoIsInside(const APath: string; const AFolder: string): Boolean;
var
  LPath: string;
  LFolder: string;
begin
  // APath lies under AFolder: both in one spelling ('/', no long-path
  // prefix, no trailing separator), compared without case (Windows paths)
  LPath := TUtils.StripLongPathPrefix(APath).Replace('\', '/');
  LFolder := TUtils.StripLongPathPrefix(AFolder).Replace('\', '/');
  if LFolder.EndsWith('/') then
    LFolder := LFolder.Substring(0, LFolder.Length - 1);
  Result := (LFolder <> '') and LPath.ToLower().StartsWith(LFolder.ToLower() + '/');
end;

procedure TPCProjectTests.DoCheckPassword(const APassword: string; const ALabel: string);
var
  LI: Integer;
  LOutside: Integer;
begin
  // pcpp init's password: its length, every character '!' to '~'
  CheckEqual(Int64(PC_PRJ_PASSWORD_LENGTH), Int64(Length(APassword)), ALabel + ': length');
  LOutside := 0;
  for LI := 1 to Length(APassword) do
  begin
    if (Ord(APassword[LI]) < 33) or (Ord(APassword[LI]) > 126) then
      Inc(LOutside);
  end;
  CheckEqual(Int64(0), Int64(LOutside), ALabel + ': characters outside ! to ~');
end;

procedure TPCProjectTests.DoCheckPackScript(const ABytes: TBytes);
var
  LByte: Byte;
  LNonAscii: Integer;
  LLoneLf: Integer;
  LI: Integer;
  LText: string;
  LLines: TArray<string>;
  LLine: string;
  LBadBox: Integer;
  LLast: string;
begin
  // pack.cmd: ASCII only and CRLF only (cmd runs neither otherwise), the
  // header's '::' box lines all one width, the header there, and the pcpp
  // pack line last
  LNonAscii := 0;
  for LByte in ABytes do
  begin
    if LByte > 127 then
      Inc(LNonAscii);
  end;
  CheckEqual(Int64(0), Int64(LNonAscii), 'pack.cmd: non-ASCII bytes');

  LLoneLf := 0;
  for LI := 0 to High(ABytes) do
  begin
    if (ABytes[LI] = 10) and ((LI = 0) or (ABytes[LI - 1] <> 13)) then
      Inc(LLoneLf);
  end;
  CheckEqual(Int64(0), Int64(LLoneLf), 'pack.cmd: line ends that are not CRLF');

  LText := TEncoding.ASCII.GetString(ABytes);
  Check(LText.Contains(PC_TEST_PRJ_HEADER_MARK), 'pack.cmd: the header holds the SPDX line');

  LLines := LText.Replace(#13#10, #10).Split([#10]);
  LBadBox := 0;
  LLast := '';
  for LLine in LLines do
  begin
    if LLine.StartsWith('::') and (Length(LLine) <> PC_TEST_PRJ_BOX_WIDTH) then
      Inc(LBadBox);
    if LLine.Trim() <> '' then
      LLast := LLine;
  end;
  CheckEqual(Int64(0), Int64(LBadBox), 'pack.cmd: header box lines not 79 wide');
  CheckEqual(PC_TEST_PRJ_PACK_LINE, LLast, 'pack.cmd: the last line runs pcpp pack');
end;

procedure TPCProjectTests.DoCheckInitTree(const ARoot: string; const ACase: string;
  const AKind: TPCProjectKind);
var
  LErrors: TErrors;
  LProject: TPCProject;
  LMain: string;
  LMainBytes: TBytes;
  LPackBytes: TBytes;
  LText: string;
  LField: string;
begin
  // What pcpp init wrote: the folders, the starter (no BOM: its first bytes
  // are its header comment), pack.cmd byte for byte
  Section('tree');
  LMain := TPath.Combine(TPath.Combine(ARoot, PC_PRJ_SRC_DIR), ACase + '.' + PC_SRC_EXT);
  Check(TFile.Exists(TPath.Combine(ARoot, PC_PRJ_FILE_NAME)), 'project.toml');
  Check(TDirectory.Exists(TPath.Combine(ARoot, PC_PRJ_ASSETS_DIR)), 'assets folder');
  try
    LMainBytes := TFile.ReadAllBytes(LMain);
    LPackBytes := TFile.ReadAllBytes(TPath.Combine(ARoot, PC_PRJ_PACK_SCRIPT));
  except
    on E: Exception do
    begin
      Fail(Format('%s: the tree cannot be read: %s', [ACase, E.Message]));
      Exit;
    end;
  end;
  // The starter: the user's blank header first (no BOM), never PaskalCPP's
  // license header (the module is the user's code), then the module line
  LText := TEncoding.UTF8.GetString(LMainBytes);
  Check(LText.StartsWith('/*****'), 'the starter opens with its header comment (no BOM)');
  Check(not LText.Contains(PC_TEST_PRJ_HEADER_MARK), 'the starter header holds no SPDX line');
  Check(LText.Contains('  ' + ACase + '.' + PC_SRC_EXT + ' - main module of ' + ACase),
    'the starter header names the module');
  for LField in PC_TEST_PRJ_STARTER_FIELDS do
    Check(LText.Contains('  ' + LField + ':'), 'the starter header has the field %s to fill in', [LField]);
  Check(LText.Contains(#10 + 'module ' + PC_PRJ_KIND_TEXT[AKind] + ' ' + ACase + ';'),
    'the starter is a %s module named %s', [PC_PRJ_KIND_TEXT[AKind], ACase]);
  DoCheckPackScript(LPackBytes);

  // project.toml reads back as the model init made
  Section('project.toml');
  LErrors := DoNewErrors();
  LProject := TPCProject.Create();
  try
    Check(DoLoad(LProject, LErrors, ARoot), 'loaded');
    DoCheckCodes(LErrors, [], 'no reports');
    CheckEqual(ACase, LProject.ProjectName, 'name');
    Check(LProject.Kind = AKind, 'type %s', [PC_PRJ_KIND_TEXT[AKind]]);
    CheckEqual(PC_PRJ_SRC_DIR + '/' + ACase + '.' + PC_SRC_EXT, LProject.MainModule, 'main');
    CheckEqual(PC_PRJ_OUTPUT_DEFAULT, LProject.OutputDir, 'output');
    DoCheckPassword(LProject.Password, 'password');
  finally
    LProject.Free();
    LErrors.Free();
  end;
end;

procedure TPCProjectTests.DoCheckInitBuild(const ARoot: string; const ACase: string;
  const AKind: TPCProjectKind; const ATarget: string; const ARun: Boolean);
var
  LArgs: string;
  LOutput: string;
  LArtifact: string;
  LCode: Int64;
  LLabel: string;
begin
  // pcpp build <case> from the output folder: the artifact lands in the
  // project's own output folder; an exe run with -r prints its line
  LLabel := ATarget;
  if LLabel = '' then
    LLabel := 'host target';
  Section('build, ' + LLabel);

  LArgs := '--no-banner build ' + TUtils.QuoteCommandArg(ACase);
  if ATarget <> '' then
    LArgs := LArgs + ' -t ' + TUtils.QuoteCommandArg(ATarget);
  if ARun then
    LArgs := LArgs + ' -r';
  LCode := DoRunPcpp(LArgs, LOutput);
  CheckEqual(Int64(0), LCode, LLabel + ': exit 0');
  if LCode <> 0 then
  begin
    Fail(Format('pcpp %s said: %s', [LArgs, LOutput]));
    Exit;
  end;

  LArtifact := DoOutputPath(LOutput);
  Check(DoIsInside(LArtifact, TPath.Combine(ARoot, PC_PRJ_OUTPUT_DEFAULT)),
    '%s: built into <root>\%s (got ''%s'')', [LLabel, PC_PRJ_OUTPUT_DEFAULT, LArtifact]);
  Check((LArtifact <> '') and TFile.Exists(LArtifact), '%s: the artifact exists', [LLabel]);
  if ARun then
    Check(LOutput.Contains(ACase + ' runs'), '%s: the program ran', [LLabel]);
end;

procedure TPCProjectTests.DoCheckInit(const AKind: TPCProjectKind);
var
  LCase: string;
  LRoot: string;
  LOutput: string;
  LCode: Int64;
begin
  // pcpp init <case> <kind> in the output folder, then pcpp build on it
  // for both targets (the host's run for an exe)
  LCase := PC_TEST_PRJ_INIT_PREFIX + PC_PRJ_KIND_TEXT[AKind];
  LRoot := DoFreshCase(LCase);
  if LRoot = '' then
    Exit;

  Section('init');
  LCode := DoRunPcpp('--no-banner init ' + LCase + ' ' + PC_PRJ_KIND_TEXT[AKind], LOutput);
  CheckEqual(Int64(0), LCode, 'init: exit 0');
  if LCode <> 0 then
  begin
    Fail(Format('pcpp init said: %s', [LOutput]));
    Exit;
  end;
  Check(LOutput.Contains(Format(RSPcCliInitDone, [PC_PRJ_KIND_TEXT[AKind], LCase, ''])),
    'init: reported');

  DoCheckInitTree(LRoot, LCase, AKind);
  DoCheckInitBuild(LRoot, LCase, AKind, '', AKind = pkExe);
  DoCheckInitBuild(LRoot, LCase, AKind, PC_TEST_PRJ_LINUX, False);
end;

procedure TPCProjectTests.DoTestInitExe(const ACell: TPCTestCell);
begin
  DoCheckInit(pkExe);
end;

procedure TPCProjectTests.DoTestInitDll(const ACell: TPCTestCell);
begin
  DoCheckInit(pkDll);
end;

procedure TPCProjectTests.DoTestInitLib(const ACell: TPCTestCell);
begin
  DoCheckInit(pkLib);
end;

procedure TPCProjectTests.DoTestInitExists(const ACell: TPCTestCell);
const
  { PC_TEST_PRJ_KEEP_TEXT }
  PC_TEST_PRJ_KEEP_TEXT = 'keep';
var
  LCase: string;
  LRoot: string;
  LKeep: string;
  LOutput: string;
  LCode: Int64;
  LText: string;
begin
  // A folder of that name is already there: PJ0014, exit 1, and nothing in
  // it written or touched
  LCase := PC_TEST_PRJ_INIT_PREFIX + 'exists';
  LRoot := DoFreshCase(LCase);
  if LRoot = '' then
    Exit;
  LKeep := TPath.Combine(LRoot, 'keep.txt');
  try
    TDirectory.CreateDirectory(LRoot);
    TFile.WriteAllBytes(LKeep, TEncoding.UTF8.GetBytes(PC_TEST_PRJ_KEEP_TEXT));
  except
    on E: Exception do
    begin
      Fail(Format('%s cannot be set up: %s', [LRoot, E.Message]));
      Exit;
    end;
  end;

  LCode := DoRunPcpp('--no-banner init ' + LCase + ' ' + PC_PRJ_KIND_TEXT[pkExe], LOutput);
  CheckEqual(Int64(1), LCode, 'exit 1');
  Check(LOutput.Contains(PC_ERR_PRJ_014), '%s reported', [PC_ERR_PRJ_014]);
  Check(not TFile.Exists(TPath.Combine(LRoot, PC_PRJ_FILE_NAME)), 'no project.toml');
  Check(not TDirectory.Exists(TPath.Combine(LRoot, PC_PRJ_SRC_DIR)), 'no src folder');
  Check(not TFile.Exists(TPath.Combine(LRoot, PC_PRJ_PACK_SCRIPT)), 'no pack.cmd');
  try
    LText := TEncoding.UTF8.GetString(TFile.ReadAllBytes(LKeep));
  except
    on E: Exception do
    begin
      Fail(Format('%s cannot be read: %s', [LKeep, E.Message]));
      Exit;
    end;
  end;
  CheckEqual(PC_TEST_PRJ_KEEP_TEXT, LText, 'the folder''s own file untouched');

  // The case's folder is not a project: it goes once checked, so the output
  // folder holds no stray subfolder (scripts\audit\find_leftovers.py)
  TUtils.DeleteTree(LRoot);
  Check(not TDirectory.Exists(LRoot), '%s removed', [LRoot]);
end;

procedure TPCProjectTests.DoTestInitPassword(const ACell: TPCTestCell);
var
  LFirst: string;
  LSecond: string;
begin
  // Two new passwords: each well formed, and not the same (64 characters
  // from the secure source never repeat in practice: a repeat is a stuck
  // source)
  Check(TPCProject.NewPassword(LFirst), 'first made');
  Check(TPCProject.NewPassword(LSecond), 'second made');
  DoCheckPassword(LFirst, 'first');
  DoCheckPassword(LSecond, 'second');
  Check(LFirst <> LSecond, 'two passwords differ');
end;

function TPCProjectTests.DoWriteText(const APath: string; const AText: string): Boolean;
begin
  // AText as UTF-8 with no BOM, its folder made first; False (and a failed
  // check) when the disk refuses
  Result := False;
  try
    TDirectory.CreateDirectory(TPath.GetDirectoryName(APath));
    TFile.WriteAllBytes(APath, TEncoding.UTF8.GetBytes(AText));
  except
    on E: Exception do
    begin
      Fail(Format('%s cannot be written: %s', [APath, E.Message]));
      Exit;
    end;
  end;
  Result := True;
end;

function TPCProjectTests.DoSetupPackCase(const ACase: string; out ARoot: string): Boolean;
begin
  // A pack case: the fixed password and the reader that takes it as its
  // first argument
  Result := DoSetupProjectCase(ACase, Format(PC_TEST_PRJ_PACK_TOML, [ACase, PC_TEST_PRJ_PACK_PASSWORD]),
    Format(PC_TEST_PRJ_PACK_READER, [ACase]), ARoot);
end;

function TPCProjectTests.DoSetupProjectCase(const ACase: string; const AToml: string;
  const AMainSource: string; out ARoot: string): Boolean;
var
  LOutput: string;
  LCode: Int64;
  LMain: string;
begin
  // A fresh project from pcpp init, then its project.toml (AToml) and its
  // main module (AMainSource) replaced; assets\ as init made it (empty)
  Result := False;
  ARoot := DoFreshCase(ACase);
  if ARoot = '' then
    Exit;
  LCode := DoRunPcpp('--no-banner init ' + ACase + ' ' + PC_PRJ_KIND_TEXT[pkExe], LOutput);
  CheckEqual(Int64(0), LCode, 'init: exit 0');
  if LCode <> 0 then
  begin
    Fail(Format('pcpp init said: %s', [LOutput]));
    Exit;
  end;
  if not DoWriteText(TPath.Combine(ARoot, PC_PRJ_FILE_NAME), AToml) then
    Exit;
  LMain := TPath.Combine(TPath.Combine(ARoot, PC_PRJ_SRC_DIR), ACase + '.' + PC_SRC_EXT);
  if not DoWriteText(LMain, AMainSource) then
    Exit;
  Result := True;
end;

function TPCProjectTests.DoWritePackAssets(const ARoot: string): Boolean;
var
  LAssets: string;
  LI: Integer;
begin
  // Every PC_TEST_PRJ_PACK_ENTRIES file under assets\ with its text
  Result := False;
  LAssets := TPath.Combine(ARoot, PC_PRJ_ASSETS_DIR);
  for LI := Low(PC_TEST_PRJ_PACK_ENTRIES) to High(PC_TEST_PRJ_PACK_ENTRIES) do
  begin
    if not DoWriteText(TPath.Combine(LAssets, PC_TEST_PRJ_PACK_ENTRIES[LI].Replace('/', '\')),
      PC_TEST_PRJ_PACK_TEXTS[LI]) then
      Exit;
  end;
  Result := True;
end;

function TPCProjectTests.DoPack(const ACase: string; out AOutput: string): Int64;
begin
  // pcpp pack <case>, run in the output folder
  Result := DoRunPcpp('--no-banner pack ' + TUtils.QuoteCommandArg(ACase), AOutput);
end;

function TPCProjectTests.DoReadBack(const ACase: string; const APassword: string): string;
var
  LCode: Int64;
begin
  // The case's reader built and run (pcpp build <case> -r -- <password>,
  // the password quoted as any argument): its whole output
  LCode := DoRunPcpp('--no-banner build ' + TUtils.QuoteCommandArg(ACase) + ' -r -- ' +
    TUtils.QuoteCommandArg(APassword), Result);
  CheckEqual(Int64(0), LCode, 'read back: exit 0');
end;

procedure TPCProjectTests.DoCheckNotRead(const AOutput: string; const ALabel: string);
var
  LI: Integer;
  LEntry: string;
begin
  // A password that is not the archive's: no entry's text comes out. ZipCrypto
  // checks one byte of a random header, so an entry either does not open
  // (none) or, about 1 time in 256, opens and its bytes fail (unreadable)
  for LI := Low(PC_TEST_PRJ_PACK_ENTRIES) to High(PC_TEST_PRJ_PACK_ENTRIES) do
  begin
    LEntry := PC_TEST_PRJ_PACK_ENTRIES[LI];
    Check(not AOutput.Contains(LEntry + ' [' + PC_TEST_PRJ_PACK_TEXTS[LI] + ']'),
      '%s: %s not read', [ALabel, LEntry]);
    Check(AOutput.Contains(LEntry + ' none') or AOutput.Contains(LEntry + ' unreadable'),
      '%s: %s refused', [ALabel, LEntry]);
  end;
end;

procedure TPCProjectTests.DoTestPackEntries(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LOutput: string;
  LCode: Int64;
  LOutDir: string;
  LBin: string;
  LI: Integer;
begin
  // assets\ (a folder, a non-ASCII name) packed into
  // <root>\output\bin\<case>.dat, its entries named below assets\; the
  // packer built in <root>\output\pack, never beside the exe; the reader
  // opens the .dat with the password and prints every text back; a second
  // pack (the packer from zig's cache) replaces the archive
  LCase := PC_TEST_PRJ_PACK_PREFIX + 'entries';
  if not DoSetupPackCase(LCase, LRoot) then
    Exit;
  if not DoWritePackAssets(LRoot) then
    Exit;
  LOutDir := TPath.Combine(LRoot, PC_PRJ_OUTPUT_DEFAULT);
  LBin := TPath.Combine(LOutDir, PC_OUTPUT_BIN_DIR);

  Section('pack');
  LCode := DoPack(LCase, LOutput);
  CheckEqual(Int64(0), LCode, 'pack: exit 0');
  if LCode <> 0 then
  begin
    Fail(Format('pcpp pack said: %s', [LOutput]));
    Exit;
  end;
  for LI := Low(PC_TEST_PRJ_PACK_ENTRIES) to High(PC_TEST_PRJ_PACK_ENTRIES) do
    Check(LOutput.Contains('  ' + PC_TEST_PRJ_PACK_ENTRIES[LI]), 'pack: %s listed',
      [PC_TEST_PRJ_PACK_ENTRIES[LI]]);
  Check(LOutput.Contains('entries 3'), 'pack: three entries');
  Check(LOutput.Contains(Format(RSPcCliPackDone, [''])), 'pack: reported');
  Check(TFile.Exists(TPath.Combine(LBin, LCase + PC_PRJ_DAT_EXT)), 'pack: the .dat beside the exe');
  Check(TFile.Exists(TPath.Combine(TPath.Combine(TPath.Combine(LOutDir, PC_PRJ_PACK_DIR),
    PC_OUTPUT_BIN_DIR), PC_TEST_PRJ_PACKER_EXE)), 'pack: the packer in output\pack');

  Section('read back');
  LOutput := DoReadBack(LCase, PC_TEST_PRJ_PACK_PASSWORD);
  for LI := Low(PC_TEST_PRJ_PACK_ENTRIES) to High(PC_TEST_PRJ_PACK_ENTRIES) do
    Check(LOutput.Contains(PC_TEST_PRJ_PACK_ENTRIES[LI] + ' [' + PC_TEST_PRJ_PACK_TEXTS[LI] + ']'),
      'read back: %s', [PC_TEST_PRJ_PACK_ENTRIES[LI]]);
  Check(LOutput.Contains('assets/hello.txt none'), 'read back: no entry named with assets/');
  Check(not TFile.Exists(TPath.Combine(LBin, PC_TEST_PRJ_PACKER_EXE)), 'read back: no packer beside the exe');

  Section('pack again');
  LCode := DoPack(LCase, LOutput);
  CheckEqual(Int64(0), LCode, 'pack again: exit 0');
  Check(LOutput.Contains('entries 3'), 'pack again: three entries');
end;

procedure TPCProjectTests.DoTestPackWrongPassword(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LOutput: string;
  LCode: Int64;
begin
  // The archive opens with project.toml's password only: the right one
  // reads (the control), a wrong one and none at all read nothing
  LCase := PC_TEST_PRJ_PACK_PREFIX + 'wrong';
  if not DoSetupPackCase(LCase, LRoot) then
    Exit;
  if not DoWritePackAssets(LRoot) then
    Exit;
  LCode := DoPack(LCase, LOutput);
  CheckEqual(Int64(0), LCode, 'pack: exit 0');
  if LCode <> 0 then
  begin
    Fail(Format('pcpp pack said: %s', [LOutput]));
    Exit;
  end;

  Section('right password');
  LOutput := DoReadBack(LCase, PC_TEST_PRJ_PACK_PASSWORD);
  Check(LOutput.Contains(PC_TEST_PRJ_PACK_ENTRIES[0] + ' [' + PC_TEST_PRJ_PACK_TEXTS[0] + ']'),
    'right password: read');

  Section('wrong password');
  DoCheckNotRead(DoReadBack(LCase, 'wrong'), 'wrong password');

  Section('no password');
  DoCheckNotRead(DoReadBack(LCase, ''), 'no password');
end;

procedure TPCProjectTests.DoTestPackEmpty(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LAssets: string;
  LOutput: string;
  LCode: Int64;
  LI: Integer;
begin
  // An empty assets\ (as init makes it) packs an empty archive that opens
  // with no entry; with no assets\ at all, pack fails (exit 1) and says so
  LCase := PC_TEST_PRJ_PACK_PREFIX + 'empty';
  if not DoSetupPackCase(LCase, LRoot) then
    Exit;
  LAssets := TPath.Combine(LRoot, PC_PRJ_ASSETS_DIR);

  Section('empty assets');
  Check(TDirectory.Exists(LAssets), 'empty assets: init made assets\');
  LCode := DoPack(LCase, LOutput);
  CheckEqual(Int64(0), LCode, 'empty assets: exit 0');
  Check(LOutput.Contains('entries 0'), 'empty assets: no entry');
  Check(TFile.Exists(TPath.Combine(TPath.Combine(TPath.Combine(LRoot, PC_PRJ_OUTPUT_DEFAULT),
    PC_OUTPUT_BIN_DIR), LCase + PC_PRJ_DAT_EXT)), 'empty assets: the .dat written');
  LOutput := DoReadBack(LCase, PC_TEST_PRJ_PACK_PASSWORD);
  for LI := Low(PC_TEST_PRJ_PACK_ENTRIES) to High(PC_TEST_PRJ_PACK_ENTRIES) do
    Check(LOutput.Contains(PC_TEST_PRJ_PACK_ENTRIES[LI] + ' none'), 'empty assets: %s absent',
      [PC_TEST_PRJ_PACK_ENTRIES[LI]]);

  Section('no assets folder');
  TUtils.DeleteTree(LAssets);
  Check(not TDirectory.Exists(LAssets), 'no assets folder: removed');
  LCode := DoPack(LCase, LOutput);
  CheckEqual(Int64(1), LCode, 'no assets folder: exit 1');
  Check(LOutput.Contains(Format(RSPcCliPackNoAssets, [''])), 'no assets folder: reported');
end;

function TPCProjectTests.DoCleanFolder(const AFolder: string): Boolean;
var
  LCompiler: TPCCompiler;
begin
  // The compiler's clean in-process (pcpp --clean asks a person first: a
  // process with a pipe for stdin is refused)
  LCompiler := TPCCompiler.Create();
  try
    Result := LCompiler.CleanFolder(AFolder);
    if not Result then
      Fail(Format('%s not cleaned: %s', [AFolder, DoReportCodes(LCompiler.GetErrors())]));
  finally
    LCompiler.Free();
  end;
end;

function TPCProjectTests.DoMakeJunction(const ALink: string; const ATarget: string): Boolean;
var
  LExitCode: DWORD;
  LAttr: DWORD;
begin
  // ALink as a junction to ATarget (cmd's mklink /J: no elevation needed);
  // True when ALink is then a link (its own attributes)
  Result := False;
  LExitCode := 0;
  try
    TUtils.RunPE(System.SysUtils.GetEnvironmentVariable('ComSpec'), '/c mklink /J ' +
      TUtils.QuoteCommandArg(TUtils.StripLongPathPrefix(ALink).Replace('/', '\')) + ' ' +
      TUtils.QuoteCommandArg(TUtils.StripLongPathPrefix(ATarget).Replace('/', '\')),
      ScratchFolder(), LExitCode, nil,
      procedure(const ALine: string; const AUserData: Pointer)
      begin
      end, True);
  except
    on E: Exception do
    begin
      Fail(Format('mklink /J %s cannot be run: %s', [ALink, E.Message]));
      Exit;
    end;
  end;
  // The entry's own attributes: GetFileAttributes never follows a link
  LAttr := GetFileAttributes(PChar(TUtils.StripLongPathPrefix(ALink).Replace('/', '\')));
  Result := (LExitCode = 0) and (LAttr <> INVALID_FILE_ATTRIBUTES) and
    ((LAttr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0);
  if not Result then
    Fail(Format('%s is not a junction (mklink exit %d)', [ALink, LExitCode]));
end;

procedure TPCProjectTests.DoTestPackClean(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LOutDir: string;
  LLinked: string;
  LPlainSrc: string;
  LPlainDir: string;
  LKeep: string;
  LOutput: string;
  LCode: Int64;
begin
  // pcpp --clean on a project's own output folder lists and deletes its
  // packer folder (output\pack) with the rest, a junction inside it as the
  // link alone (its target, in the case's own folder, untouched); on any
  // other output folder, a folder named pack is not pcpp's: not listed, kept
  LCase := PC_TEST_PRJ_PACK_PREFIX + 'clean';
  if not DoSetupPackCase(LCase, LRoot) then
    Exit;
  LOutDir := TPath.Combine(LRoot, PC_PRJ_OUTPUT_DEFAULT);
  LLinked := TPath.Combine(LRoot, 'linked');

  Section('project output');
  LCode := DoPack(LCase, LOutput);
  CheckEqual(Int64(0), LCode, 'project output: pack exit 0');
  // A build writes the records that make output a pcpp output folder
  DoReadBack(LCase, PC_TEST_PRJ_PACK_PASSWORD);
  if not DoWriteText(TPath.Combine(LLinked, 'kept.txt'), 'kept') then
    Exit;
  if not DoMakeJunction(TPath.Combine(TPath.Combine(LOutDir, PC_PRJ_PACK_DIR), 'link'), LLinked) then
    Exit;
  LCode := DoRunPcpp('--no-banner --clean ' + TUtils.QuoteCommandArg(LOutDir) + ' --dry-run', LOutput);
  CheckEqual(Int64(0), LCode, 'project output: dry run exit 0');
  Check(LOutput.Contains('/' + PC_PRJ_PACK_DIR + '  ('), 'project output: pack listed');
  if DoCleanFolder(LOutDir) then
  begin
    Check(not TDirectory.Exists(TPath.Combine(LOutDir, PC_PRJ_PACK_DIR)), 'project output: pack deleted');
    Check(not TDirectory.Exists(TPath.Combine(LOutDir, PC_OUTPUT_BIN_DIR)), 'project output: bin deleted');
  end;
  Check(TFile.Exists(TPath.Combine(LLinked, 'kept.txt')), 'project output: the junction''s target untouched');

  Section('other output');
  LPlainSrc := TPath.Combine(TPath.Combine(LRoot, 'plain'), 'prj_pack_clean_plain.' + PC_SRC_EXT);
  LPlainDir := TPath.Combine(LRoot, 'plainout');
  LKeep := TPath.Combine(TPath.Combine(LPlainDir, PC_PRJ_PACK_DIR), 'keep.txt');
  if not DoWriteText(LPlainSrc, PC_TEST_PRJ_PACK_PLAIN) then
    Exit;
  LCode := DoRunPcpp('--no-banner ' + TUtils.QuoteCommandArg(LPlainSrc) + ' -o ' +
    TUtils.QuoteCommandArg(LPlainDir), LOutput);
  CheckEqual(Int64(0), LCode, 'other output: build exit 0');
  if not DoWriteText(LKeep, 'keep') then
    Exit;
  LCode := DoRunPcpp('--no-banner --clean ' + TUtils.QuoteCommandArg(LPlainDir) + ' --dry-run', LOutput);
  CheckEqual(Int64(0), LCode, 'other output: dry run exit 0');
  Check(not LOutput.Contains('/' + PC_PRJ_PACK_DIR + '  ('), 'other output: pack not listed');
  if DoCleanFolder(LPlainDir) then
    Check(TFile.Exists(LKeep), 'other output: pack kept');
end;

function TPCProjectTests.DoSetupSecretCase(const ACase: string; const APassword: string;
  out ARoot: string): Boolean;
var
  LToml: string;
begin
  // A password case: project.toml with APassword ('' = no [pack] password
  // at all), the reader that opens its .dat with ProjectPassword(), and
  // the pack entries in assets\
  if APassword <> '' then
    LToml := Format(PC_TEST_PRJ_PACK_TOML, [ACase, APassword])
  else
    LToml := Format(PC_TEST_PRJ_SECRET_TOML, [ACase]);
  Result := DoSetupProjectCase(ACase, LToml, Format(PC_TEST_PRJ_SECRET_READER, [ACase]), ARoot);
  if Result then
    Result := DoWritePackAssets(ARoot);
end;

function TPCProjectTests.DoPackCase(const ACase: string): Boolean;
var
  LOutput: string;
  LCode: Int64;
begin
  // pcpp pack <case>: exit 0, else a failed check with what pack said
  LCode := DoPack(ACase, LOutput);
  CheckEqual(Int64(0), LCode, 'pack: exit 0');
  Result := LCode = 0;
  if not Result then
    Fail(Format('pcpp pack said: %s', [LOutput]));
end;

function TPCProjectTests.DoBuildCase(const ACase: string; const ATarget: string;
  const ARun: Boolean; out AOutput: string; out AArtifact: string): Boolean;
var
  LArgs: string;
  LCode: Int64;
  LLabel: string;
begin
  // pcpp build <case> [-t ATarget] [-r]: exit 0 and the artifact on pcpp's
  // Output line; False (and a failed check with pcpp's words) otherwise
  LLabel := ATarget;
  if LLabel = '' then
    LLabel := 'host target';
  LArgs := '--no-banner build ' + TUtils.QuoteCommandArg(ACase);
  if ATarget <> '' then
    LArgs := LArgs + ' -t ' + TUtils.QuoteCommandArg(ATarget);
  if ARun then
    LArgs := LArgs + ' -r';
  LCode := DoRunPcpp(LArgs, AOutput);
  AArtifact := DoOutputPath(AOutput);
  CheckEqual(Int64(0), LCode, LLabel + ': build exit 0');
  Result := (LCode = 0) and (AArtifact <> '') and TFile.Exists(AArtifact);
  if not Result then
    Fail(Format('pcpp %s said: %s', [LArgs, AOutput]));
end;

procedure TPCProjectTests.DoCheckSecretRead(const AOutput: string; const APassword: string;
  const ALabel: string);
var
  LI: Integer;
begin
  // The reader got APassword back (its UTF-8 length) and read every entry
  // with it
  Check(AOutput.Contains(Format('password length %d', [TEncoding.UTF8.GetByteCount(APassword)])),
    '%s: the password''s length', [ALabel]);
  for LI := Low(PC_TEST_PRJ_PACK_ENTRIES) to High(PC_TEST_PRJ_PACK_ENTRIES) do
    Check(AOutput.Contains(PC_TEST_PRJ_PACK_ENTRIES[LI] + ' [' + PC_TEST_PRJ_PACK_TEXTS[LI] + ']'),
      '%s: %s read', [ALabel, PC_TEST_PRJ_PACK_ENTRIES[LI]]);
end;

function TPCProjectTests.DoReadFileBytes(const APath: string; out ABytes: TBytes): Boolean;
begin
  // APath's bytes; False (and a failed check) when it cannot be read
  ABytes := nil;
  try
    ABytes := TFile.ReadAllBytes(APath);
  except
    on E: Exception do
    begin
      Fail(Format('%s cannot be read: %s', [APath, E.Message]));
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TPCProjectTests.DoHasBytes(const AHaystack: TBytes; const ANeedle: TBytes): Boolean;
var
  LStart: Int64;
  LI: Int64;
  LFound: Boolean;
begin
  // ANeedle somewhere in AHaystack (a plain scan: the files are a few MB);
  // an empty needle is found nowhere
  Result := False;
  if (Length(ANeedle) = 0) or (Length(ANeedle) > Length(AHaystack)) then
    Exit;
  for LStart := 0 to Int64(Length(AHaystack)) - Length(ANeedle) do
  begin
    if AHaystack[LStart] <> ANeedle[0] then
      Continue;
    LFound := True;
    for LI := 1 to High(ANeedle) do
    begin
      if AHaystack[LStart + LI] <> ANeedle[LI] then
      begin
        LFound := False;
        Break;
      end;
    end;
    if LFound then
      Exit(True);
  end;
end;

procedure TPCProjectTests.DoCheckNoPassword(const ABytes: TBytes; const APassword: string;
  const ALabel: string);
var
  LPlain: TBytes;
  LStart: Integer;
  LLeaks: Integer;
begin
  // Neither the whole password (UTF-8, UTF-16) nor any run of more than
  // PC_TEST_PRJ_SECRET_WINDOW of its bytes is in ABytes
  LPlain := TEncoding.UTF8.GetBytes(APassword);
  Check(not DoHasBytes(ABytes, LPlain), '%s: no UTF-8 password', [ALabel]);
  Check(not DoHasBytes(ABytes, TEncoding.Unicode.GetBytes(APassword)), '%s: no UTF-16 password', [ALabel]);
  LLeaks := 0;
  for LStart := 0 to Length(LPlain) - (PC_TEST_PRJ_SECRET_WINDOW + 1) do
  begin
    if DoHasBytes(ABytes, Copy(LPlain, LStart, PC_TEST_PRJ_SECRET_WINDOW + 1)) then
      Inc(LLeaks);
  end;
  CheckEqual(Int64(0), Int64(LLeaks), ALabel + ': no part of the password');
end;

procedure TPCProjectTests.DoCheckHiddenArtifact(const AArtifact: string; const ALabel: string);
var
  LBytes: TBytes;
begin
  // The control first: the scan finds text the exe does hold, so a missing
  // password is not a scan that read nothing
  if not DoReadFileBytes(AArtifact, LBytes) then
    Exit;
  Check(DoHasBytes(LBytes, TEncoding.UTF8.GetBytes(PC_TEST_PRJ_SECRET_CONTROL)),
    '%s: the scan finds the exe''s own text', [ALabel]);
  DoCheckNoPassword(LBytes, PC_TEST_PRJ_PACK_PASSWORD, ALabel);
end;

procedure TPCProjectTests.DoCheckHiddenGenerated(const ARoot: string; const ACase: string);
var
  LFolder: string;
  LMain: string;
  LFiles: TArray<string>;
  LFile: string;
  LBytes: TBytes;
begin
  // The generated C++ holds the scrambled call (the control: these are the
  // files the build wrote) and no password text in any file
  LFolder := TPath.Combine(TPath.Combine(ARoot, PC_PRJ_OUTPUT_DEFAULT), PC_CMP_GENERATED_DIR);
  LMain := TPath.Combine(LFolder, ACase + '.' + PC_SRC_EXT + '.cpp');
  if not DoReadFileBytes(LMain, LBytes) then
    Exit;
  Check(DoHasBytes(LBytes, TEncoding.UTF8.GetBytes(PC_TEST_PRJ_SECRET_CALL_MARK)),
    'generated: the scrambled call');
  try
    LFiles := TDirectory.GetFiles(LFolder, '*', TSearchOption.soAllDirectories);
  except
    on E: Exception do
    begin
      Fail(Format('%s cannot be listed: %s', [LFolder, E.Message]));
      Exit;
    end;
  end;
  for LFile in LFiles do
  begin
    if DoReadFileBytes(LFile, LBytes) then
      DoCheckNoPassword(LBytes, PC_TEST_PRJ_PACK_PASSWORD, 'generated ' + TPath.GetFileName(LFile));
  end;
end;

procedure TPCProjectTests.DoTestPasswordOpen(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LOutput: string;
  LArtifact: string;
begin
  // pcpp pack zips assets\ with project.toml's password; the exe, given no
  // password of its own, opens the .dat through CreateZipFileIO with
  // ProjectPassword() and reads every entry, on both targets
  LCase := PC_TEST_PRJ_SECRET_PREFIX + 'open';
  if not DoSetupSecretCase(LCase, PC_TEST_PRJ_PACK_PASSWORD, LRoot) then
    Exit;
  if not DoPackCase(LCase) then
    Exit;

  Section('host target');
  if DoBuildCase(LCase, '', True, LOutput, LArtifact) then
    DoCheckSecretRead(LOutput, PC_TEST_PRJ_PACK_PASSWORD, 'host target');

  Section(PC_TEST_PRJ_LINUX);
  if DoBuildCase(LCase, PC_TEST_PRJ_LINUX, True, LOutput, LArtifact) then
    DoCheckSecretRead(LOutput, PC_TEST_PRJ_PACK_PASSWORD, PC_TEST_PRJ_LINUX);
end;

procedure TPCProjectTests.DoTestPasswordHidden(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LOutput: string;
  LArtifact: string;
begin
  // The password is in neither the exe (both targets) nor the C++ the
  // build wrote: not whole, not as UTF-16, no run of it
  LCase := PC_TEST_PRJ_SECRET_PREFIX + 'hidden';
  if not DoSetupSecretCase(LCase, PC_TEST_PRJ_PACK_PASSWORD, LRoot) then
    Exit;

  Section('host target');
  if DoBuildCase(LCase, '', False, LOutput, LArtifact) then
  begin
    DoCheckHiddenArtifact(LArtifact, 'host target');
    DoCheckHiddenGenerated(LRoot, LCase);
  end;

  Section(PC_TEST_PRJ_LINUX);
  if DoBuildCase(LCase, PC_TEST_PRJ_LINUX, False, LOutput, LArtifact) then
  begin
    DoCheckHiddenArtifact(LArtifact, PC_TEST_PRJ_LINUX);
    DoCheckHiddenGenerated(LRoot, LCase);
  end;
end;

procedure TPCProjectTests.DoTestPasswordStale(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LToml: string;
  LOutput: string;
  LArtifact: string;
begin
  // A .dat packed before project.toml's password changed: the rebuilt exe
  // carries the new password, so no entry opens (nil: none, never garbage
  // read as data); the old password back reads again (the control: the
  // change, nothing else, is why)
  LCase := PC_TEST_PRJ_SECRET_PREFIX + 'stale';
  if not DoSetupSecretCase(LCase, PC_TEST_PRJ_PACK_PASSWORD, LRoot) then
    Exit;
  if not DoPackCase(LCase) then
    Exit;
  LToml := TPath.Combine(LRoot, PC_PRJ_FILE_NAME);

  Section('packed password');
  if DoBuildCase(LCase, '', True, LOutput, LArtifact) then
    DoCheckSecretRead(LOutput, PC_TEST_PRJ_PACK_PASSWORD, 'packed password');

  Section('password changed');
  if not DoWriteText(LToml, Format(PC_TEST_PRJ_PACK_TOML, [LCase, PC_TEST_PRJ_SECRET_CHANGED])) then
    Exit;
  if DoBuildCase(LCase, '', True, LOutput, LArtifact) then
  begin
    Check(LOutput.Contains(Format('password length %d', [Length(PC_TEST_PRJ_SECRET_CHANGED)])),
      'password changed: the new password');
    DoCheckNotRead(LOutput, 'password changed');
  end;

  Section('changed back');
  if not DoWriteText(LToml, Format(PC_TEST_PRJ_PACK_TOML, [LCase, PC_TEST_PRJ_PACK_PASSWORD])) then
    Exit;
  if DoBuildCase(LCase, '', True, LOutput, LArtifact) then
    DoCheckSecretRead(LOutput, PC_TEST_PRJ_PACK_PASSWORD, 'changed back');
end;

procedure TPCProjectTests.DoTestPasswordNone(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LOutput: string;
  LArtifact: string;
begin
  // A project with no [pack] password: pack writes entries with none, and
  // ProjectPassword() is "" (an empty scrambled literal), which opens them
  LCase := PC_TEST_PRJ_SECRET_PREFIX + 'none';
  if not DoSetupSecretCase(LCase, '', LRoot) then
    Exit;
  if not DoPackCase(LCase) then
    Exit;
  if DoBuildCase(LCase, '', True, LOutput, LArtifact) then
    DoCheckSecretRead(LOutput, '', 'no password');
end;

procedure TPCProjectTests.DoTestPasswordAnalyze(const ACell: TPCTestCell);
const
  { PC_TEST_PRJ_ANALYZE_NAME }
  PC_TEST_PRJ_ANALYZE_NAME = 'prj_password_analyze';
  { PC_TEST_PRJ_ANALYZE_OTHER }
  PC_TEST_PRJ_ANALYZE_OTHER = 'prj_password_analyze_other';
var
  LRoot: string;
  LMain: string;
  LOther: string;
  LToml: string;
  LCompiler: TPCCompiler;
begin
  // SEM's side (the editor's Analyze, which writes nothing): the main
  // module's ProjectPassword() is fine, one with an argument is SM0409, a
  // project file that is not the main module gets SM0433
  LToml := Format(PC_TEST_PRJ_CASE_TOML, [PC_TEST_PRJ_ANALYZE_NAME, PC_PRJ_KIND_TEXT[pkExe],
    PC_TEST_PRJ_ANALYZE_NAME]);

  Section('main module');
  LRoot := DoWriteCase(PC_TEST_PRJ_ANALYZE_NAME, LToml, PC_TEST_PRJ_ANALYZE_NAME,
    Format(PC_TEST_PRJ_SECRET_CALL, [PC_TEST_PRJ_ANALYZE_NAME, 'ProjectPassword()']), LMain);
  if LRoot = '' then
    Exit;
  LCompiler := TPCCompiler.Create();
  try
    Check(LCompiler.Analyze(LMain), 'main: checked');
    CheckEqual('', DoReportCodes(LCompiler.GetErrors()), 'main: no reports');
  finally
    LCompiler.Free();
  end;

  Section('an argument');
  LRoot := DoWriteCase(PC_TEST_PRJ_ANALYZE_NAME, LToml, PC_TEST_PRJ_ANALYZE_NAME,
    Format(PC_TEST_PRJ_SECRET_CALL, [PC_TEST_PRJ_ANALYZE_NAME, 'ProjectPassword(1)']), LMain);
  if LRoot = '' then
    Exit;
  LCompiler := TPCCompiler.Create();
  try
    Check(not LCompiler.Analyze(LMain), 'argument: refused');
    CheckEqual('SM0409', DoReportCodes(LCompiler.GetErrors()), 'argument: reports');
  finally
    LCompiler.Free();
  end;

  Section('not the main module');
  LOther := TPath.Combine(TPath.GetDirectoryName(LMain), PC_TEST_PRJ_ANALYZE_OTHER + '.' + PC_SRC_EXT);
  if not DoWriteText(LOther, Format(PC_TEST_PRJ_SECRET_CALL,
    [PC_TEST_PRJ_ANALYZE_OTHER, 'ProjectPassword()'])) then
    Exit;
  LCompiler := TPCCompiler.Create();
  try
    Check(not LCompiler.Analyze(LOther), 'other: refused');
    CheckEqual('SM0433', DoReportCodes(LCompiler.GetErrors()), 'other: reports');
    CheckEqual('', LCompiler.GetProjectRoot(), 'other: no project');
  finally
    LCompiler.Free();
  end;
end;

function TPCProjectTests.DoSetupStaleCase(const ACase: string; out ARoot: string): Boolean;
begin
  // A stale case: an init'd exe project whose main module is <ACase> (an
  // empty program: its artifact <ACase>.exe, <ACase> on Linux)
  Result := DoSetupProjectCase(ACase, Format(PC_TEST_PRJ_STALE_TOML, [ACase, ACase]),
    Format(PC_TEST_PRJ_STALE_SOURCE, [ACase]), ARoot);
end;

function TPCProjectTests.DoSetMain(const ARoot: string; const ACase: string;
  const AStem: string): Boolean;
begin
  // The main module renamed: src\<AStem>.pcpp written and project.toml's
  // main pointed at it (the old source stays, no longer the main module)
  Result := DoWriteText(TPath.Combine(TPath.Combine(ARoot, PC_PRJ_SRC_DIR),
    AStem + '.' + PC_SRC_EXT), Format(PC_TEST_PRJ_STALE_SOURCE, [AStem]));
  if Result then
    Result := DoWriteText(TPath.Combine(ARoot, PC_PRJ_FILE_NAME),
      Format(PC_TEST_PRJ_STALE_TOML, [ACase, AStem]));
end;

function TPCProjectTests.DoStaleBuild(const AArgs: string; const ALabel: string): Boolean;
var
  LOutput: string;
  LCode: Int64;
begin
  // pcpp --no-banner AArgs, run in the output folder: exit 0, else a failed
  // check with what pcpp said
  LCode := DoRunPcpp('--no-banner ' + AArgs, LOutput);
  CheckEqual(Int64(0), LCode, ALabel + ': exit 0');
  Result := LCode = 0;
  if not Result then
    Fail(Format('pcpp %s said: %s', [AArgs, LOutput]));
end;

function TPCProjectTests.DoPlainSource(const ARoot: string; const AStem: string): string;
begin
  // <root>\plain\<AStem>.pcpp, an empty program: inside the project but not
  // its main module, so a plain build; '' when it cannot be written
  Result := TPath.Combine(TPath.Combine(ARoot, PC_TEST_PRJ_STALE_PLAIN_DIR),
    AStem + '.' + PC_SRC_EXT);
  if not DoWriteText(Result, Format(PC_TEST_PRJ_STALE_SOURCE, [AStem])) then
    Result := '';
end;

function TPCProjectTests.DoRecordNames(const APath: string): TArray<string>;
var
  LLines: TArray<string>;
  LLine: string;
begin
  // A record's names, one per line, blank lines dropped; none when the
  // record is not there
  Result := nil;
  if not TFile.Exists(APath) then
    Exit;
  try
    LLines := TFile.ReadAllLines(APath, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      Fail(Format('%s cannot be read: %s', [APath, E.Message]));
      Exit;
    end;
  end;
  for LLine in LLines do
  begin
    if LLine.Trim() <> '' then
      Result := Result + [LLine.Trim()];
  end;
end;

function TPCProjectTests.DoRecordHas(const ANames: TArray<string>; const AName: string): Boolean;
var
  LName: string;
begin
  // The driver compares recorded names without case (DoHasName)
  for LName in ANames do
  begin
    if SameText(LName, AName) then
      Exit(True);
  end;
  Result := False;
end;

function TPCProjectTests.DoTargetRecord(const AOutput: string; const ATarget: string): string;
begin
  // A project build's record for ATarget in the output folder AOutput
  Result := TPath.Combine(TPath.Combine(AOutput, PC_ZIG_PROJECT_RECORD_DIR),
    ATarget + PC_ZIG_PROJECT_RECORD_EXT);
end;

procedure TPCProjectTests.DoTestStaleDebugToFast(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LOutDir: string;
  LBin: string;
  LExe: string;
  LPdb: string;
  LElf: string;
  LBuild: string;
  LNames: TArray<string>;
begin
  // A project build's own leftovers go, per target: the .pdb of a debug
  // build goes when the next Windows build is fast; a Linux build never
  // takes the Windows exe for a leftover, nor the next Windows build the
  // Linux one (each target's record is its own)
  LCase := PC_TEST_PRJ_STALE_PREFIX + 'debug';
  if not DoSetupStaleCase(LCase, LRoot) then
    Exit;
  LOutDir := TPath.Combine(LRoot, PC_PRJ_OUTPUT_DEFAULT);
  LBin := TPath.Combine(LOutDir, PC_OUTPUT_BIN_DIR);
  LExe := LCase + '.exe';
  LPdb := LCase + '.pdb';
  LElf := LCase;
  LBuild := 'build ' + TUtils.QuoteCommandArg(LCase) + ' -t ';

  Section('windows debug');
  if not DoStaleBuild(LBuild + PC_TARGET_X86_64_WINDOWS_GNU + ' -opt debug', 'windows debug') then
    Exit;
  Check(TFile.Exists(TPath.Combine(LBin, LExe)), 'windows debug: the exe');
  Check(TFile.Exists(TPath.Combine(LBin, LPdb)), 'windows debug: the .pdb');
  LNames := DoRecordNames(DoTargetRecord(LOutDir, PC_TARGET_X86_64_WINDOWS_GNU));
  Check(DoRecordHas(LNames, PC_OUTPUT_BIN_DIR + '/' + LExe), 'windows debug: the exe recorded');
  Check(DoRecordHas(LNames, PC_OUTPUT_BIN_DIR + '/' + LPdb), 'windows debug: the .pdb recorded');
  Check(not TFile.Exists(TPath.Combine(LOutDir, PC_ZIG_INSTALLED_RECORD)),
    'windows debug: no plain record');

  Section('windows fast');
  if not DoStaleBuild(LBuild + PC_TARGET_X86_64_WINDOWS_GNU + ' -opt fast', 'windows fast') then
    Exit;
  Check(TFile.Exists(TPath.Combine(LBin, LExe)), 'windows fast: the exe');
  Check(not TFile.Exists(TPath.Combine(LBin, LPdb)), 'windows fast: the debug .pdb removed');
  LNames := DoRecordNames(DoTargetRecord(LOutDir, PC_TARGET_X86_64_WINDOWS_GNU));
  Check(DoRecordHas(LNames, PC_OUTPUT_BIN_DIR + '/' + LExe), 'windows fast: the exe recorded');
  Check(not DoRecordHas(LNames, PC_OUTPUT_BIN_DIR + '/' + LPdb), 'windows fast: the .pdb unrecorded');

  Section('linux debug, then fast');
  if not DoStaleBuild(LBuild + PC_TARGET_X86_64_LINUX_GNU + ' -opt debug', 'linux debug') then
    Exit;
  if not DoStaleBuild(LBuild + PC_TARGET_X86_64_LINUX_GNU + ' -opt fast', 'linux fast') then
    Exit;
  Check(TFile.Exists(TPath.Combine(LBin, LElf)), 'linux: the binary');
  Check(TFile.Exists(TPath.Combine(LBin, LExe)), 'linux: the windows exe kept');
  LNames := DoRecordNames(DoTargetRecord(LOutDir, PC_TARGET_X86_64_LINUX_GNU));
  Check(DoRecordHas(LNames, PC_OUTPUT_BIN_DIR + '/' + LElf), 'linux: the binary recorded');
  Check(not DoRecordHas(LNames, PC_OUTPUT_BIN_DIR + '/' + LExe), 'linux: the exe not in its record');
  LNames := DoRecordNames(DoTargetRecord(LOutDir, PC_TARGET_X86_64_WINDOWS_GNU));
  Check(DoRecordHas(LNames, PC_OUTPUT_BIN_DIR + '/' + LExe), 'linux: the windows record kept');

  Section('windows again');
  if not DoStaleBuild(LBuild + PC_TARGET_X86_64_WINDOWS_GNU + ' -opt fast', 'windows again') then
    Exit;
  Check(TFile.Exists(TPath.Combine(LBin, LElf)), 'windows again: the linux binary kept');
  Check(TFile.Exists(TPath.Combine(LBin, LExe)), 'windows again: the exe');
end;

procedure TPCProjectTests.DoTestStaleRename(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LBin: string;
  LNewStem: string;
  LBuild: string;
  LNames: TArray<string>;
begin
  // The main module renamed (project.toml's main): the old artifact goes,
  // the new one is built and recorded in its place
  LCase := PC_TEST_PRJ_STALE_PREFIX + 'rename';
  if not DoSetupStaleCase(LCase, LRoot) then
    Exit;
  LBin := TPath.Combine(TPath.Combine(LRoot, PC_PRJ_OUTPUT_DEFAULT), PC_OUTPUT_BIN_DIR);
  LNewStem := LCase + '_b';
  LBuild := 'build ' + TUtils.QuoteCommandArg(LCase) + ' -t ' + PC_TARGET_X86_64_WINDOWS_GNU +
    ' -opt fast';
  if not DoStaleBuild(LBuild, 'first build') then
    Exit;
  Check(TFile.Exists(TPath.Combine(LBin, LCase + '.exe')), 'first build: the exe');
  if not DoSetMain(LRoot, LCase, LNewStem) then
    Exit;
  if not DoStaleBuild(LBuild, 'renamed') then
    Exit;
  Check(not TFile.Exists(TPath.Combine(LBin, LCase + '.exe')), 'renamed: the old exe removed');
  Check(TFile.Exists(TPath.Combine(LBin, LNewStem + '.exe')), 'renamed: the new exe');
  LNames := DoRecordNames(DoTargetRecord(TPath.Combine(LRoot, PC_PRJ_OUTPUT_DEFAULT),
    PC_TARGET_X86_64_WINDOWS_GNU));
  Check(DoRecordHas(LNames, PC_OUTPUT_BIN_DIR + '/' + LNewStem + '.exe'), 'renamed: the new exe recorded');
  Check(not DoRecordHas(LNames, PC_OUTPUT_BIN_DIR + '/' + LCase + '.exe'), 'renamed: the old exe unrecorded');
end;

procedure TPCProjectTests.DoTestStalePlainKept(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LOutDir: string;
  LBin: string;
  LPlain: string;
  LOther: string;
  LProjectBuild: string;
  LNames: TArray<string>;
begin
  // A plain build's file in the project's output (a project file that is
  // not the main module, built with -o into it) survives the next project
  // build: it is in the plain record only, never the project's
  LCase := PC_TEST_PRJ_STALE_PREFIX + 'plain';
  if not DoSetupStaleCase(LCase, LRoot) then
    Exit;
  LOutDir := TPath.Combine(LRoot, PC_PRJ_OUTPUT_DEFAULT);
  LBin := TPath.Combine(LOutDir, PC_OUTPUT_BIN_DIR);
  LOther := LCase + '_other';
  LProjectBuild := 'build ' + TUtils.QuoteCommandArg(LCase) + ' -t ' +
    PC_TARGET_X86_64_WINDOWS_GNU + ' -opt fast';
  if not DoStaleBuild(LProjectBuild, 'project build') then
    Exit;
  LPlain := DoPlainSource(LRoot, LOther);
  if LPlain = '' then
    Exit;
  if not DoStaleBuild(TUtils.QuoteCommandArg(LPlain) + ' -o ' + TUtils.QuoteCommandArg(LOutDir) +
    ' -t ' + PC_TARGET_X86_64_WINDOWS_GNU + ' -opt fast', 'plain build') then
    Exit;
  Check(DoRecordHas(DoRecordNames(TPath.Combine(LOutDir, PC_ZIG_INSTALLED_RECORD)),
    PC_OUTPUT_BIN_DIR + '/' + LOther + '.exe'), 'plain build: in the plain record');
  if not DoStaleBuild(LProjectBuild, 'project again') then
    Exit;
  Check(TFile.Exists(TPath.Combine(LBin, LOther + '.exe')), 'project again: the plain exe kept');
  Check(TFile.Exists(TPath.Combine(LBin, LCase + '.exe')), 'project again: the project exe');
  LNames := DoRecordNames(DoTargetRecord(LOutDir, PC_TARGET_X86_64_WINDOWS_GNU));
  Check(not DoRecordHas(LNames, PC_OUTPUT_BIN_DIR + '/' + LOther + '.exe'),
    'project again: the plain exe not in the project record');
end;

procedure TPCProjectTests.DoTestStaleSharedName(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LOutDir: string;
  LBin: string;
  LPlain: string;
  LNewStem: string;
  LProjectBuild: string;
  LNames: TArray<string>;
begin
  // A name both records list stays: the project built <case>.exe, a plain
  // build of the same name wrote it again into the project's output, then
  // the main module is renamed; <case>.exe is now no file of the project
  // build, but the plain record lists it, so it is kept (and stays in the
  // project record, for when the plain record no longer lists it)
  LCase := PC_TEST_PRJ_STALE_PREFIX + 'shared';
  if not DoSetupStaleCase(LCase, LRoot) then
    Exit;
  LOutDir := TPath.Combine(LRoot, PC_PRJ_OUTPUT_DEFAULT);
  LBin := TPath.Combine(LOutDir, PC_OUTPUT_BIN_DIR);
  LNewStem := LCase + '_b';
  LProjectBuild := 'build ' + TUtils.QuoteCommandArg(LCase) + ' -t ' +
    PC_TARGET_X86_64_WINDOWS_GNU + ' -opt fast';
  if not DoStaleBuild(LProjectBuild, 'project build') then
    Exit;
  LPlain := DoPlainSource(LRoot, LCase);
  if LPlain = '' then
    Exit;
  if not DoStaleBuild(TUtils.QuoteCommandArg(LPlain) + ' -o ' + TUtils.QuoteCommandArg(LOutDir) +
    ' -t ' + PC_TARGET_X86_64_WINDOWS_GNU + ' -opt fast', 'plain build') then
    Exit;
  if not DoSetMain(LRoot, LCase, LNewStem) then
    Exit;
  if not DoStaleBuild(LProjectBuild, 'renamed') then
    Exit;
  Check(TFile.Exists(TPath.Combine(LBin, LCase + '.exe')), 'renamed: the shared name kept');
  Check(TFile.Exists(TPath.Combine(LBin, LNewStem + '.exe')), 'renamed: the new exe');
  LNames := DoRecordNames(DoTargetRecord(LOutDir, PC_TARGET_X86_64_WINDOWS_GNU));
  Check(DoRecordHas(LNames, PC_OUTPUT_BIN_DIR + '/' + LCase + '.exe'),
    'renamed: the shared name still in the project record');
end;

procedure TPCProjectTests.DoTestStaleOtherOutput(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LElse: string;
  LBin: string;
  LBuild: string;
begin
  // The main module built with -o elsewhere is a plain build of that
  // folder: debug then fast leaves the .pdb, and no project record is made
  // there
  LCase := PC_TEST_PRJ_STALE_PREFIX + 'other';
  if not DoSetupStaleCase(LCase, LRoot) then
    Exit;
  LElse := TPath.Combine(LRoot, 'elsewhere');
  LBin := TPath.Combine(LElse, PC_OUTPUT_BIN_DIR);
  LBuild := 'build ' + TUtils.QuoteCommandArg(LCase) + ' -o ' + TUtils.QuoteCommandArg(LElse) +
    ' -t ' + PC_TARGET_X86_64_WINDOWS_GNU + ' -opt ';
  if not DoStaleBuild(LBuild + 'debug', 'debug') then
    Exit;
  if not DoStaleBuild(LBuild + 'fast', 'fast') then
    Exit;
  Check(TFile.Exists(TPath.Combine(LBin, LCase + '.pdb')), 'the .pdb kept');
  Check(TFile.Exists(TPath.Combine(LBin, LCase + '.exe')), 'the exe');
  Check(not TDirectory.Exists(TPath.Combine(LElse, PC_ZIG_PROJECT_RECORD_DIR)), 'no project record');
  Check(TFile.Exists(TPath.Combine(LElse, PC_ZIG_INSTALLED_RECORD)), 'the plain record');
end;

procedure TPCProjectTests.DoTestStalePlainUnchanged(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LPlain: string;
  LShared: string;
  LBin: string;
  LStem: string;
  LBuild: string;
  LNames: TArray<string>;
begin
  // A plain build into a shared folder removes nothing, as before: debug
  // then fast leaves the .pdb, the plain record is reset to the last build's
  // files, no project record
  LCase := PC_TEST_PRJ_STALE_PREFIX + 'plainout';
  if not DoSetupStaleCase(LCase, LRoot) then
    Exit;
  LStem := LCase + '_p';
  LPlain := DoPlainSource(LRoot, LStem);
  if LPlain = '' then
    Exit;
  LShared := TPath.Combine(LRoot, 'shared');
  LBin := TPath.Combine(LShared, PC_OUTPUT_BIN_DIR);
  LBuild := TUtils.QuoteCommandArg(LPlain) + ' -o ' + TUtils.QuoteCommandArg(LShared) +
    ' -t ' + PC_TARGET_X86_64_WINDOWS_GNU + ' -opt ';
  if not DoStaleBuild(LBuild + 'debug', 'debug') then
    Exit;
  if not DoStaleBuild(LBuild + 'fast', 'fast') then
    Exit;
  Check(TFile.Exists(TPath.Combine(LBin, LStem + '.pdb')), 'the .pdb kept');
  Check(TFile.Exists(TPath.Combine(LBin, LStem + '.exe')), 'the exe');
  LNames := DoRecordNames(TPath.Combine(LShared, PC_ZIG_INSTALLED_RECORD));
  Check(DoRecordHas(LNames, PC_OUTPUT_BIN_DIR + '/' + LStem + '.exe'), 'the exe recorded');
  Check(not DoRecordHas(LNames, PC_OUTPUT_BIN_DIR + '/' + LStem + '.pdb'), 'the record reset');
  Check(not TDirectory.Exists(TPath.Combine(LShared, PC_ZIG_PROJECT_RECORD_DIR)), 'no project record');
end;

procedure TPCProjectTests.DoTestStaleClean(const ACell: TPCTestCell);
var
  LCase: string;
  LRoot: string;
  LOutDir: string;
  LRecordDir: string;
  LOutput: string;
  LCode: Int64;
begin
  // pcpp --clean lists the project records' folder and deletes it with the
  // rest
  LCase := PC_TEST_PRJ_STALE_PREFIX + 'clean';
  if not DoSetupStaleCase(LCase, LRoot) then
    Exit;
  LOutDir := TPath.Combine(LRoot, PC_PRJ_OUTPUT_DEFAULT);
  LRecordDir := TPath.Combine(LOutDir, PC_ZIG_PROJECT_RECORD_DIR);
  if not DoStaleBuild('build ' + TUtils.QuoteCommandArg(LCase) + ' -t ' +
    PC_TARGET_X86_64_WINDOWS_GNU + ' -opt fast', 'build') then
    Exit;
  Check(TDirectory.Exists(LRecordDir), 'build: the project records');
  LCode := DoRunPcpp('--no-banner --clean ' + TUtils.QuoteCommandArg(LOutDir) + ' --dry-run', LOutput);
  CheckEqual(Int64(0), LCode, 'dry run exit 0');
  Check(LOutput.Contains('/' + PC_ZIG_PROJECT_RECORD_DIR + '  ('), 'dry run: the project records listed');
  if DoCleanFolder(LOutDir) then
    Check(not TDirectory.Exists(LRecordDir), 'clean: the project records deleted');
end;

end.
