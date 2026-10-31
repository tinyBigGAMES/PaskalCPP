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
  PaskalCPP.Project - the project model (project.toml)

  A project is opt-in: a folder holding project.toml at its root. TPCProject
  finds the nearest project.toml above a path (Find), reads and validates it
  (Load, Validate) and writes it (Save). Every field is registered once, in
  PC_PRJ_FIELDS (its table, key, value kind, required): reading, the
  unknown-key check and the key paths all come from that table.

    format = 1
    [project]
    name   = "MyProject"           required, an identifier
    type   = "exe"                 required, exe | dll | lib
    main   = "src/MyProject.pcpp"  required, relative to the root
    output = "output"              optional, default output
    [pack]
    password = "..."               optional, printable ASCII; '' = no password

  Every problem in the file is reported (not only the first). An unknown key
  is a warning, so a misspelled optional key is never silently defaulted.

  Scaffold makes a new project (pcpp init): the folder, src\<name>.pcpp
  (PC_PRJ_STARTER, per kind), assets\, pack.cmd and project.toml with a new
  random pack password (NewPassword).

  ScramblePassword turns the pack password into the bytes a project build
  writes for ProjectPassword() (never the text); the runtime's
  ::pcpp::project_password is its other half.

  Dependencies: RTL + StdApp.Base + StdApp.Config + StdApp.Utils +
    StdApp.Crypto (TSecureRandom, TBlake2b) + StdApp.Resources + PaskalCPP.Common
  Notes: Reports through FErrors (SetErrors before use). With no FErrors the
    calls still return failure. MainPath / OutputPath and pcpp pack's
    AssetsPath / PackPath / DatPath resolve through TUtils.ResolvePath and
    may raise: callers wrap them.
===============================================================================}

unit PaskalCPP.Project;

interface

uses
  System.SysUtils,
  StdApp.Base,
  StdApp.Config;

const
  { PC_ERR_PRJ_001 }
  // project.toml cannot be read or parsed
  PC_ERR_PRJ_001 = 'PJ0001';
  { PC_ERR_PRJ_002 }
  // a required key is missing
  PC_ERR_PRJ_002 = 'PJ0002';
  { PC_ERR_PRJ_003 }
  // a key holds the wrong kind of value
  PC_ERR_PRJ_003 = 'PJ0003';
  { PC_ERR_PRJ_004 }
  // an unknown key or table (a warning)
  PC_ERR_PRJ_004 = 'PJ0004';
  { PC_ERR_PRJ_005 }
  // the project name is not valid
  PC_ERR_PRJ_005 = 'PJ0005';
  { PC_ERR_PRJ_006 }
  // the project type is not exe, dll or lib
  PC_ERR_PRJ_006 = 'PJ0006';
  { PC_ERR_PRJ_007 }
  // the main module path is not valid
  PC_ERR_PRJ_007 = 'PJ0007';
  { PC_ERR_PRJ_008 }
  // the main module does not exist
  PC_ERR_PRJ_008 = 'PJ0008';
  { PC_ERR_PRJ_009 }
  // the output folder is not valid
  PC_ERR_PRJ_009 = 'PJ0009';
  { PC_ERR_PRJ_010 }
  // the pack password holds a character that is not printable ASCII
  PC_ERR_PRJ_010 = 'PJ0010';
  { PC_ERR_PRJ_011 }
  // the file's format is not one this compiler reads
  PC_ERR_PRJ_011 = 'PJ0011';
  { PC_ERR_PRJ_012 }
  // project.toml cannot be saved
  PC_ERR_PRJ_012 = 'PJ0012';
  { PC_ERR_PRJ_013 }
  // the search for project.toml above a path failed
  PC_ERR_PRJ_013 = 'PJ0013';
  { PC_ERR_PRJ_014 }
  // a new project's folder already exists (pcpp init)
  PC_ERR_PRJ_014 = 'PJ0014';
  { PC_ERR_PRJ_015 }
  // a new project's folder or file cannot be created (pcpp init)
  PC_ERR_PRJ_015 = 'PJ0015';
  { PC_ERR_PRJ_016 }
  // a new pack password cannot be made (pcpp init)
  PC_ERR_PRJ_016 = 'PJ0016';

  { PC_PRJ_FILE_NAME }
  // The project file, at the project root
  PC_PRJ_FILE_NAME = 'project.toml';
  { PC_PRJ_FORMAT }
  // The newest project.toml format this compiler reads and the one it writes
  PC_PRJ_FORMAT = 1;
  { PC_PRJ_OUTPUT_DEFAULT }
  // The output folder when project.toml names none
  PC_PRJ_OUTPUT_DEFAULT = 'output';
  { PC_PRJ_SRC_DIR }
  // The project's source folder
  PC_PRJ_SRC_DIR = 'src';
  { PC_PRJ_ASSETS_DIR }
  // The project's assets folder (packed into the .dat)
  PC_PRJ_ASSETS_DIR = 'assets';
  { PC_PRJ_PACK_DIR }
  // The packer's own build folder inside the project's output folder: pcpp
  // pack builds its packer program there, so the exe's folder (bin) holds
  // only the project's own files
  PC_PRJ_PACK_DIR = 'pack';
  { PC_PRJ_DAT_EXT }
  // The packed assets: <name>.dat, a zip of assets\ beside the exe
  PC_PRJ_DAT_EXT = '.dat';
  { PC_PRJ_TABLE_PROJECT }
  // The [project] table
  PC_PRJ_TABLE_PROJECT = 'project';
  { PC_PRJ_TABLE_PACK }
  // The [pack] table
  PC_PRJ_TABLE_PACK = 'pack';
  { PC_PRJ_PACK_SCRIPT }
  // The script a new project gets beside project.toml: it runs pcpp pack
  PC_PRJ_PACK_SCRIPT = 'pack.cmd';
  { PC_PRJ_PASSWORD_LENGTH }
  // A new project's pack password, in characters (pcpp init)
  PC_PRJ_PASSWORD_LENGTH = 64;
  { PC_PRJ_SECRET_SALT }
  // What ScramblePassword hashes in front of the password for its key, so
  // the key is no plain hash of the password
  PC_PRJ_SECRET_SALT = 'PaskalCPP.ProjectPassword.1';

type
  { TPCProjectKind }
  // What the project builds
  TPCProjectKind = (pkExe, pkDll, pkLib);

  { TPCProjectField }
  // Every field of project.toml
  TPCProjectField = (pfFormat, pfName, pfType, pfMain, pfOutput, pfPassword);

  { TPCProjectFields }
  TPCProjectFields = set of TPCProjectField;

  { TPCProjectValueKind }
  // The TOML value kind a field holds
  TPCProjectValueKind = (pvString, pvInteger);

  { TPCProjectFieldRow }
  // One field's registration
  TPCProjectFieldRow = record
    Table: string;                   // '' = the root table
    Key: string;
    ValueKind: TPCProjectValueKind;
    Required: Boolean;
  end;

const
  { PC_PRJ_FIELDS }
  // The one registration of every field, in the order Save writes them
  PC_PRJ_FIELDS: array[TPCProjectField] of TPCProjectFieldRow = (
    (Table: '';                   Key: 'format';   ValueKind: pvInteger; Required: True),
    (Table: PC_PRJ_TABLE_PROJECT; Key: 'name';     ValueKind: pvString;  Required: True),
    (Table: PC_PRJ_TABLE_PROJECT; Key: 'type';     ValueKind: pvString;  Required: True),
    (Table: PC_PRJ_TABLE_PROJECT; Key: 'main';     ValueKind: pvString;  Required: True),
    (Table: PC_PRJ_TABLE_PROJECT; Key: 'output';   ValueKind: pvString;  Required: False),
    (Table: PC_PRJ_TABLE_PACK;    Key: 'password'; ValueKind: pvString;  Required: False)
  );

  { PC_PRJ_KIND_TEXT }
  // How each kind is written in project.toml
  PC_PRJ_KIND_TEXT: array[TPCProjectKind] of string = (
    'exe',
    'dll',
    'lib'
  );

type
  { TPCProject }
  TPCProject = class(TBaseObject)
  private
    FRoot: string;
    FFileName: string;
    FFileFormat: Int64;
    FProjectName: string;
    FKind: TPCProjectKind;
    FKindText: string;               // type as written (its report quotes it)
    FMainModule: string;
    FOutputDir: string;
    FPassword: string;
    FHave: TPCProjectFields;         // fields holding a usable value
    FValid: Boolean;                 // no error reported since the last reset

    procedure DoClear();
    procedure DoError(const ACode: string; const AMessage: string;
      const AArgs: array of const);
    procedure DoWarning(const ACode: string; const AMessage: string;
      const AArgs: array of const);
    function DoKeyPath(const AField: TPCProjectField): string;
    function DoReadString(const AConfig: TConfig; const AField: TPCProjectField;
      const ADefault: string; out AValue: string): Boolean;
    function DoReadInteger(const AConfig: TConfig; const AField: TPCProjectField;
      const ADefault: Int64; out AValue: Int64): Boolean;
    procedure DoReadFields(const AConfig: TConfig);
    function DoIsKnownKey(const ATable: string; const AKey: string): Boolean;
    function DoIsKnownTable(const ATable: string): Boolean;
    function DoIsFirstOfTable(const AField: TPCProjectField): Boolean;
    procedure DoCheckUnknown(const AConfig: TConfig);
    function DoCheckRelative(const APath: string; out AReason: string): Boolean;
    function DoFirstSegment(const APath: string): string;
    procedure DoValidateFormat();
    procedure DoValidateName();
    procedure DoValidateType();
    procedure DoValidateMain();
    procedure DoValidateOutput();
    procedure DoValidatePassword();
    class function DoSplitMixNext(var AState: UInt64): UInt64; static;
    function DoScaffoldFiles(const ARoot: string; const AProjectName: string;
      const AKind: TPCProjectKind): Boolean;
  public
    constructor Create(); override;

    // The nearest folder holding project.toml at or above AStartPath (a file
    // or a folder); '' when there is none (projects are opt-in: no report)
    function Find(const AStartPath: string): string;

    // Reads ARoot\project.toml and validates it; False on any error
    function Load(const ARoot: string): Boolean;

    // Checks every field holding a value; False on any error
    function Validate(): Boolean;

    // Validates, then writes Root\project.toml; False on any error
    function Save(): Boolean;

    // A new project's model (pcpp init): main = src/<name>.pcpp, output =
    // the default, the current format. Nothing is written (Save)
    procedure InitNew(const ARoot: string; const AProjectName: string;
      const AKind: TPCProjectKind; const APassword: string);

    // pcpp init: a new project folder AProjectName inside AParent ('' = the
    // current folder) holding project.toml, src\<AProjectName>.pcpp (the
    // kind's starter module), an empty assets\ and pack.cmd, with a new pack
    // password. A folder or file of that name already there is refused with
    // nothing written. False on any error; Root is the new folder on success
    function Scaffold(const AParent: string; const AProjectName: string;
      const AKind: TPCProjectKind): Boolean;

    // A new pack password: PC_PRJ_PASSWORD_LENGTH printable ASCII characters
    // (no blank), each drawn evenly from the OS's secure random source;
    // False when that source fails
    class function NewPassword(out APassword: string): Boolean; static;

    // PLAN-PROJECTS atom 6: APassword scrambled for ProjectPassword(): the
    // build writes AData and AKey, never the text, and the runtime's
    // ::pcpp::project_password undoes it with the same keystream (the two
    // are one algorithm, kept in step). AKey = the first 8 bytes of
    // BLAKE2b(PC_PRJ_SECRET_SALT + password), little endian, so one password
    // always writes the same bytes (zig's cache keeps the build); AData[i] =
    // byte i of the password's UTF-8 XOR byte i of the SplitMix64 stream
    // AKey seeds (a word per 8 bytes, low byte first). An empty password
    // gives an empty AData
    class procedure ScramblePassword(const APassword: string; out AData: TBytes;
      out AKey: UInt64); static;

    // The main module and the output folder, full paths
    function MainPath(): string;
    function OutputPath(): string;

    // pcpp pack's paths, full: the folder packed (<root>\assets), the
    // packer's own build folder (<output>\pack), the exe's folder
    // (<output>\bin) and the archive written there (<name>.dat)
    function AssetsPath(): string;
    function PackPath(): string;
    function BinPath(): string;
    function DatPath(): string;

    // AText as a kind (exactly as PC_PRJ_KIND_TEXT writes it)
    class function KindFromText(const AText: string;
      out AKind: TPCProjectKind): Boolean; static;

    // Why AName cannot name a project; '' = it can
    class function NameProblem(const AName: string): string; static;

    property Root: string read FRoot;
    property FileName: string read FFileName;
    property FileFormat: Int64 read FFileFormat;
    property ProjectName: string read FProjectName;
    property Kind: TPCProjectKind read FKind;
    property MainModule: string read FMainModule;
    property OutputDir: string read FOutputDir;
    property Password: string read FPassword;
  end;

implementation

uses
  System.IOUtils,
  StdApp.Utils,
  StdApp.Crypto,
  StdApp.Resources,
  PaskalCPP.Common;

const
  { PC_PRJ_STARTER_HEADER }
  // The comment every new main module starts with, %0:s = the project name.
  // The module is the user's code, not PaskalCPP's: a blank header the user
  // fills in, never the PaskalCPP copyright / license header (user
  // 2026-10-29; pack.cmd keeps PaskalCPP's, pcpp wrote that file)
  PC_PRJ_STARTER_HEADER = '''
/*******************************************************************************
  %0:s.pcpp - main module of %0:s

  Description:
  Author:
  Copyright:
  License:
*******************************************************************************/


''';

  { PC_PRJ_STARTER }
  // A new project's main module, per kind (%0:s = the project name): the
  // smallest module of that kind that builds, after PC_PRJ_STARTER_HEADER
  PC_PRJ_STARTER: array[TPCProjectKind] of string = (
    '''
module exe %0:s;

begin
  println("%0:s runs");
end.

''',
    '''
module dll %0:s;

exported routine clink %0:s_add(AA: int32; AB: int32): int32;
begin
  return AA + AB;
end;

end.

''',
    '''
module lib %0:s;

exported routine clink %0:s_add(AA: int32; AB: int32): int32;
begin
  return AA + AB;
end;

end.

'''
  );

  { PC_PRJ_PACK_SCRIPT_TEXT }
  // pack.cmd: the .cmd header (ASCII only: cmd does not run a file with
  // non-ASCII characters), then pcpp pack on the script's own folder (%~dp0
  // ends in a separator; the '.' keeps it from escaping the closing quote).
  // Written with CRLF line ends (DoScaffoldFiles): cmd reads it so
  PC_PRJ_PACK_SCRIPT_TEXT = '''
@echo off

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: PaskalCPP(tm) Programming Language                                        ::
::                                                                           ::
:: Copyright (c) 2026-present tinyBigGAMES(tm) LLC                           ::
:: All Rights Reserved.                                                      ::
::                                                                           ::
:: https://paskalcpp.org                                                     ::
::                                                                           ::
:: SPDX-License-Identifier: MPL-2.0                                          ::
::                                                                           ::
:: This Source Code Form is subject to the terms of the                      ::
:: Mozilla Public License, v. 2.0. If a copy of the MPL                      ::
:: was not distributed with this file, You can obtain one                    ::
:: at https://mozilla.org/MPL/2.0/.                                          ::
::---------------------------------------------------------------------------::
:: pack.cmd -- zip assets\ into this project's .dat (pcpp pack)              ::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

pcpp pack "%~dp0."

''';

  { PC_PRJ_PASSWORD_FIRST }
  // The pack password's alphabet: printable ASCII without the blank ('!'
  // to '~'), so a password copied by hand never loses an edge
  PC_PRJ_PASSWORD_FIRST = 33;
  { PC_PRJ_PASSWORD_LAST }
  PC_PRJ_PASSWORD_LAST = 126;

  { PC_PRJ_DEVICE_NAMES }
  // Names Windows reserves for devices: no file or folder may be named so
  PC_PRJ_DEVICE_NAMES: array[0..23] of string = (
    'CON', 'PRN', 'AUX', 'NUL',
    'COM0', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT0', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
  );

  { PC_PRJ_COMMENT_MARK }
  // What starts a TOML comment line Save writes
  PC_PRJ_COMMENT_MARK = '# ';

{ TPCProject }

constructor TPCProject.Create();
begin
  inherited;

  DoClear();
end;

procedure TPCProject.DoClear();
begin
  FRoot := '';
  FFileName := '';
  FFileFormat := 0;
  FProjectName := '';
  FKind := pkExe;
  FKindText := '';
  FMainModule := '';
  FOutputDir := '';
  FPassword := '';
  FHave := [];
  FValid := True;
end;

procedure TPCProject.DoError(const ACode: string; const AMessage: string;
  const AArgs: array of const);
begin
  FValid := False;
  if Assigned(FErrors) then
    FErrors.Add(esError, ACode, AMessage, AArgs);
end;

procedure TPCProject.DoWarning(const ACode: string; const AMessage: string;
  const AArgs: array of const);
begin
  if Assigned(FErrors) then
    FErrors.Add(esWarning, ACode, AMessage, AArgs);
end;

function TPCProject.DoKeyPath(const AField: TPCProjectField): string;
begin
  if PC_PRJ_FIELDS[AField].Table = '' then
    Result := PC_PRJ_FIELDS[AField].Key
  else
    Result := PC_PRJ_FIELDS[AField].Table + '.' + PC_PRJ_FIELDS[AField].Key;
end;

function TPCProject.DoReadString(const AConfig: TConfig;
  const AField: TPCProjectField; const ADefault: string;
  out AValue: string): Boolean;
var
  LPath: string;
  LFirst: string;
  LSecond: string;
begin
  // True = AValue is usable: read, or the default of an absent optional key
  LPath := DoKeyPath(AField);
  AValue := ADefault;

  if not AConfig.HasKey(LPath) then
  begin
    Result := not PC_PRJ_FIELDS[AField].Required;
    if not Result then
      DoError(PC_ERR_PRJ_002, RSPrjKeyMissing, [FFileName, LPath]);
    Exit;
  end;

  // GetString gives its default for a value that is not a string: asking
  // with two different defaults tells that apart from a string equal to one
  LFirst := AConfig.GetString(LPath, 'a');
  LSecond := AConfig.GetString(LPath, 'b');
  if (LFirst = 'a') and (LSecond = 'b') then
  begin
    DoError(PC_ERR_PRJ_003, RSPrjKeyType, [FFileName, LPath, RSPrjKindString]);
    Exit(False);
  end;

  AValue := LFirst;
  Result := True;
end;

function TPCProject.DoReadInteger(const AConfig: TConfig;
  const AField: TPCProjectField; const ADefault: Int64;
  out AValue: Int64): Boolean;
var
  LPath: string;
  LFirst: Int64;
  LSecond: Int64;
begin
  // As DoReadString, for an integer
  LPath := DoKeyPath(AField);
  AValue := ADefault;

  if not AConfig.HasKey(LPath) then
  begin
    Result := not PC_PRJ_FIELDS[AField].Required;
    if not Result then
      DoError(PC_ERR_PRJ_002, RSPrjKeyMissing, [FFileName, LPath]);
    Exit;
  end;

  LFirst := AConfig.GetInteger(LPath, 0);
  LSecond := AConfig.GetInteger(LPath, 1);
  if (LFirst = 0) and (LSecond = 1) then
  begin
    DoError(PC_ERR_PRJ_003, RSPrjKeyType, [FFileName, LPath, RSPrjKindInteger]);
    Exit(False);
  end;

  AValue := LFirst;
  Result := True;
end;

procedure TPCProject.DoReadFields(const AConfig: TConfig);
var
  LText: string;
  LNumber: Int64;
begin
  if DoReadInteger(AConfig, pfFormat, 0, LNumber) then
  begin
    FFileFormat := LNumber;
    Include(FHave, pfFormat);
  end;

  if DoReadString(AConfig, pfName, '', LText) then
  begin
    FProjectName := LText;
    Include(FHave, pfName);
  end;

  if DoReadString(AConfig, pfType, '', LText) then
  begin
    FKindText := LText;
    Include(FHave, pfType);
  end;

  if DoReadString(AConfig, pfMain, '', LText) then
  begin
    FMainModule := LText;
    Include(FHave, pfMain);
  end;

  if DoReadString(AConfig, pfOutput, PC_PRJ_OUTPUT_DEFAULT, LText) then
  begin
    FOutputDir := LText;
    Include(FHave, pfOutput);
  end;

  if DoReadString(AConfig, pfPassword, '', LText) then
  begin
    FPassword := LText;
    Include(FHave, pfPassword);
  end;
end;

function TPCProject.DoIsKnownKey(const ATable: string; const AKey: string): Boolean;
var
  LField: TPCProjectField;
begin
  Result := False;
  for LField := Low(TPCProjectField) to High(TPCProjectField) do
  begin
    if (PC_PRJ_FIELDS[LField].Table = ATable) and (PC_PRJ_FIELDS[LField].Key = AKey) then
      Exit(True);
  end;
end;

function TPCProject.DoIsKnownTable(const ATable: string): Boolean;
var
  LField: TPCProjectField;
begin
  Result := False;
  if ATable = '' then
    Exit;
  for LField := Low(TPCProjectField) to High(TPCProjectField) do
  begin
    if PC_PRJ_FIELDS[LField].Table = ATable then
      Exit(True);
  end;
end;

function TPCProject.DoIsFirstOfTable(const AField: TPCProjectField): Boolean;
var
  LField: TPCProjectField;
begin
  // True for the first field registered in its table (each table once)
  Result := True;
  if AField = Low(TPCProjectField) then
    Exit;
  for LField := Low(TPCProjectField) to Pred(AField) do
  begin
    if PC_PRJ_FIELDS[LField].Table = PC_PRJ_FIELDS[AField].Table then
      Exit(False);
  end;
end;

procedure TPCProject.DoCheckUnknown(const AConfig: TConfig);
var
  LKey: string;
  LField: TPCProjectField;
  LTable: string;
begin
  // The root: its own keys and the registered tables
  for LKey in AConfig.GetKeys('') do
  begin
    if not (DoIsKnownKey('', LKey) or DoIsKnownTable(LKey)) then
      DoWarning(PC_ERR_PRJ_004, RSPrjKeyUnknown, [FFileName, LKey]);
  end;

  // Each registered table's keys
  for LField := Low(TPCProjectField) to High(TPCProjectField) do
  begin
    LTable := PC_PRJ_FIELDS[LField].Table;
    if (LTable = '') or (not DoIsFirstOfTable(LField)) then
      Continue;
    for LKey in AConfig.GetKeys(LTable) do
    begin
      if not DoIsKnownKey(LTable, LKey) then
        DoWarning(PC_ERR_PRJ_004, RSPrjKeyUnknown, [FFileName, LTable + '.' + LKey]);
    end;
  end;
end;

function TPCProject.DoCheckRelative(const APath: string; out AReason: string): Boolean;
var
  LSegment: string;
  LRooted: Boolean;
begin
  // A path relative to the root that never leaves it
  AReason := '';

  if APath.Trim() = '' then
  begin
    AReason := RSPrjPathEmpty;
    Exit(False);
  end;

  try
    LRooted := APath.StartsWith('$') or APath.Contains(':') or TPath.IsPathRooted(APath);
  except
    on E: Exception do
    begin
      AReason := E.Message;
      Exit(False);
    end;
  end;
  if LRooted then
  begin
    AReason := RSPrjPathRooted;
    Exit(False);
  end;

  for LSegment in APath.Split(['/', '\']) do
  begin
    if LSegment.Trim() = '..' then
    begin
      AReason := RSPrjPathParent;
      Exit(False);
    end;
  end;

  Result := True;
end;

function TPCProject.DoFirstSegment(const APath: string): string;
var
  LSegment: string;
begin
  // The first segment that names a folder ('' and '.' name none)
  Result := '';
  for LSegment in APath.Split(['/', '\']) do
  begin
    if (LSegment.Trim() <> '') and (LSegment.Trim() <> '.') then
      Exit(LSegment.Trim());
  end;
end;

procedure TPCProject.DoValidateFormat();
begin
  if (FFileFormat < 1) or (FFileFormat > PC_PRJ_FORMAT) then
    DoError(PC_ERR_PRJ_011, RSPrjFormatInvalid, [FFileName, FFileFormat, PC_PRJ_FORMAT]);
end;

procedure TPCProject.DoValidateName();
var
  LReason: string;
begin
  LReason := NameProblem(FProjectName);
  if LReason <> '' then
    DoError(PC_ERR_PRJ_005, RSPrjNameInvalid, [FProjectName, LReason]);
end;

procedure TPCProject.DoValidateType();
var
  LKind: TPCProjectKind;
begin
  if KindFromText(FKindText, LKind) then
    FKind := LKind
  else
    DoError(PC_ERR_PRJ_006, RSPrjTypeInvalid, [FKindText]);
end;

procedure TPCProject.DoValidateMain();
var
  LReason: string;
  LPath: string;
  LExists: Boolean;
begin
  if not DoCheckRelative(FMainModule, LReason) then
  begin
    DoError(PC_ERR_PRJ_007, RSPrjMainInvalid, [FMainModule, LReason]);
    Exit;
  end;

  if not SameText(TPath.GetExtension(FMainModule), '.' + PC_SRC_EXT) then
  begin
    DoError(PC_ERR_PRJ_007, RSPrjMainInvalid,
      [FMainModule, Format(RSPrjMainExt, [PC_SRC_EXT])]);
    Exit;
  end;

  try
    LPath := MainPath();
    LExists := TFile.Exists(LPath);
  except
    on E: Exception do
    begin
      DoError(PC_ERR_PRJ_008, RSPrjMainMissing, [FMainModule, E.Message]);
      Exit;
    end;
  end;
  if not LExists then
    DoError(PC_ERR_PRJ_008, RSPrjMainMissing, [FMainModule, LPath]);
end;

procedure TPCProject.DoValidateOutput();
var
  LReason: string;
  LFirst: string;
begin
  if not DoCheckRelative(FOutputDir, LReason) then
  begin
    DoError(PC_ERR_PRJ_009, RSPrjOutputInvalid, [FOutputDir, LReason]);
    Exit;
  end;

  // Never the root itself (a build would fill it), never inside src or
  // assets (pack would zip build output into the .dat)
  LFirst := DoFirstSegment(FOutputDir);
  if LFirst = '' then
    DoError(PC_ERR_PRJ_009, RSPrjOutputInvalid, [FOutputDir, RSPrjOutputRoot])
  else if SameText(LFirst, PC_PRJ_SRC_DIR) or SameText(LFirst, PC_PRJ_ASSETS_DIR) then
    DoError(PC_ERR_PRJ_009, RSPrjOutputInvalid,
      [FOutputDir, Format(RSPrjOutputReserved, [LFirst])]);
end;

procedure TPCProject.DoValidatePassword();
var
  LI: Integer;
begin
  // ZipCrypto keys on bytes: printable ASCII is one byte in every encoding
  for LI := 1 to Length(FPassword) do
  begin
    if (Ord(FPassword[LI]) < 32) or (Ord(FPassword[LI]) > 126) then
    begin
      DoError(PC_ERR_PRJ_010, RSPrjPasswordInvalid, [LI]);
      Exit;
    end;
  end;
end;

function TPCProject.Find(const AStartPath: string): string;
var
  LDir: string;
  LParent: string;
begin
  Result := '';
  try
    LDir := TUtils.ResolvePath(AStartPath);
    if TFile.Exists(LDir) then
      LDir := TPath.GetDirectoryName(LDir);

    while LDir <> '' do
    begin
      if TFile.Exists(TPath.Combine(LDir, PC_PRJ_FILE_NAME)) then
        Exit(LDir);

      // The drive root has no parent: GetDirectoryName gives '' or itself
      LParent := TPath.GetDirectoryName(LDir);
      if (LParent = '') or TUtils.SamePath(LParent, LDir) then
        Break;
      LDir := LParent;
    end;
  except
    on E: Exception do
    begin
      DoError(PC_ERR_PRJ_013, RSPrjFindFailed, [AStartPath, E.Message]);
      Result := '';
    end;
  end;
end;

function TPCProject.Load(const ARoot: string): Boolean;
var
  LConfig: TConfig;
  LLoaded: Boolean;
  LReadValid: Boolean;
begin
  DoClear();
  Result := False;

  try
    FRoot := TUtils.ResolvePath(ARoot);
    FFileName := TUtils.JoinResolvedPath(FRoot, PC_PRJ_FILE_NAME);
  except
    on E: Exception do
    begin
      DoError(PC_ERR_PRJ_001, RSPrjReadFailed, [ARoot, E.Message]);
      Exit;
    end;
  end;

  LConfig := TConfig.Create();
  try
    try
      LLoaded := LConfig.LoadFromFile(FFileName);
    except
      on E: Exception do
      begin
        DoError(PC_ERR_PRJ_001, RSPrjReadFailed, [FFileName, E.Message]);
        Exit;
      end;
    end;
    if not LLoaded then
    begin
      DoError(PC_ERR_PRJ_001, RSPrjReadFailed, [FFileName, LConfig.GetLastError()]);
      Exit;
    end;

    DoReadFields(LConfig);
    DoCheckUnknown(LConfig);
  finally
    LConfig.Free();
  end;

  // Validate resets FValid: the read's errors are kept apart
  LReadValid := FValid;
  Result := Validate() and LReadValid;
  FValid := Result;
end;

function TPCProject.Validate(): Boolean;
begin
  FValid := True;

  if pfFormat in FHave then
    DoValidateFormat();
  if pfName in FHave then
    DoValidateName();
  if pfType in FHave then
    DoValidateType();
  if pfMain in FHave then
    DoValidateMain();
  if pfOutput in FHave then
    DoValidateOutput();
  if pfPassword in FHave then
    DoValidatePassword();

  Result := FValid;
end;

function TPCProject.Save(): Boolean;
var
  LConfig: TConfig;
  LSaved: Boolean;
begin
  // Never writes a file Load would refuse
  Result := False;
  if not Validate() then
    Exit;

  LConfig := TConfig.Create();
  try
    LConfig.SetFileComment(PC_PRJ_COMMENT_MARK + RSPrjFileComment);
    LConfig.SetInteger(DoKeyPath(pfFormat), FFileFormat);
    LConfig.SetString(DoKeyPath(pfName), FProjectName);
    LConfig.SetString(DoKeyPath(pfType), PC_PRJ_KIND_TEXT[FKind]);
    LConfig.SetString(DoKeyPath(pfMain), FMainModule);
    LConfig.SetString(DoKeyPath(pfOutput), FOutputDir);
    LConfig.SetTableComment(PC_PRJ_TABLE_PROJECT, 0, PC_PRJ_COMMENT_MARK + RSPrjProjectComment);

    // No password = no [pack] table (absent and '' mean the same)
    if FPassword <> '' then
    begin
      LConfig.SetString(DoKeyPath(pfPassword), FPassword);
      LConfig.SetTableComment(PC_PRJ_TABLE_PACK, 0, PC_PRJ_COMMENT_MARK + RSPrjPackComment);
    end;

    try
      LSaved := LConfig.SaveToFile(FFileName);
    except
      on E: Exception do
      begin
        DoError(PC_ERR_PRJ_012, RSPrjSaveFailed, [FFileName, E.Message]);
        Exit;
      end;
    end;
    if not LSaved then
    begin
      DoError(PC_ERR_PRJ_012, RSPrjSaveFailed, [FFileName, LConfig.GetLastError()]);
      Exit;
    end;
  finally
    LConfig.Free();
  end;

  Result := True;
end;

procedure TPCProject.InitNew(const ARoot: string; const AProjectName: string;
  const AKind: TPCProjectKind; const APassword: string);
begin
  DoClear();
  FRoot := TUtils.ResolvePath(ARoot);
  FFileName := TUtils.JoinResolvedPath(FRoot, PC_PRJ_FILE_NAME);
  FFileFormat := PC_PRJ_FORMAT;
  FProjectName := AProjectName;
  FKind := AKind;
  FKindText := PC_PRJ_KIND_TEXT[AKind];
  FMainModule := PC_PRJ_SRC_DIR + '/' + AProjectName + '.' + PC_SRC_EXT;
  FOutputDir := PC_PRJ_OUTPUT_DEFAULT;
  FPassword := APassword;
  FHave := [Low(TPCProjectField)..High(TPCProjectField)];
end;

function TPCProject.DoScaffoldFiles(const ARoot: string; const AProjectName: string;
  const AKind: TPCProjectKind): Boolean;
var
  LSrcDir: string;
  LPath: string;
begin
  // The folders, the starter module and pack.cmd: everything but
  // project.toml, which Save writes once the main module is there. Written
  // without a BOM; the path reported is the one that failed
  Result := False;
  LPath := ARoot;
  try
    TDirectory.CreateDirectory(ARoot);

    LSrcDir := TUtils.JoinResolvedPath(ARoot, PC_PRJ_SRC_DIR);
    LPath := LSrcDir;
    TDirectory.CreateDirectory(LSrcDir);

    LPath := TUtils.JoinResolvedPath(ARoot, PC_PRJ_ASSETS_DIR);
    TDirectory.CreateDirectory(LPath);

    LPath := TUtils.JoinResolvedPath(LSrcDir, AProjectName + '.' + PC_SRC_EXT);
    TFile.WriteAllBytes(LPath, TEncoding.UTF8.GetBytes(
      Format(PC_PRJ_STARTER_HEADER + PC_PRJ_STARTER[AKind], [AProjectName])));

    // CRLF whatever line ends the literal took from this unit's file: a
    // .cmd with LF ends breaks cmd's labels
    LPath := TUtils.JoinResolvedPath(ARoot, PC_PRJ_PACK_SCRIPT);
    TFile.WriteAllBytes(LPath, TEncoding.ASCII.GetBytes(
      PC_PRJ_PACK_SCRIPT_TEXT.Replace(#13#10, #10).Replace(#10, #13#10)));
  except
    on E: Exception do
    begin
      DoError(PC_ERR_PRJ_015, RSPrjScaffoldFailed, [LPath, E.Message]);
      Exit;
    end;
  end;
  Result := True;
end;

function TPCProject.Scaffold(const AParent: string; const AProjectName: string;
  const AKind: TPCProjectKind): Boolean;
var
  LProblem: string;
  LRoot: string;
  LTaken: Boolean;
  LPassword: string;
begin
  DoClear();
  Result := False;

  // The name first: it names the folder, the main module and the .dat
  LProblem := NameProblem(AProjectName);
  if LProblem <> '' then
  begin
    DoError(PC_ERR_PRJ_005, RSPrjNameInvalid, [AProjectName, LProblem]);
    Exit;
  end;

  try
    LRoot := TUtils.ResolvePath(AProjectName, AParent);
    LTaken := TDirectory.Exists(LRoot) or TFile.Exists(LRoot);
  except
    on E: Exception do
    begin
      DoError(PC_ERR_PRJ_015, RSPrjScaffoldFailed, [AProjectName, E.Message]);
      Exit;
    end;
  end;
  // Never into a folder that is there: nothing of it is touched
  if LTaken then
  begin
    DoError(PC_ERR_PRJ_014, RSPrjFolderExists, [LRoot]);
    Exit;
  end;

  // The password before any file: a failure leaves the disk as it was
  if not NewPassword(LPassword) then
  begin
    DoError(PC_ERR_PRJ_016, RSPrjPasswordFailed, [RSCryRandomFailed]);
    Exit;
  end;

  if not DoScaffoldFiles(LRoot, AProjectName, AKind) then
    Exit;

  InitNew(LRoot, AProjectName, AKind, LPassword);
  Result := Save();
end;

class function TPCProject.NewPassword(out APassword: string): Boolean;
var
  LSize: Integer;
  LLimit: Integer;
  LBytes: TBytes;
  LByte: Byte;
  LBuilder: TStringBuilder;
begin
  // Rejection sampling: a byte below the largest multiple of the alphabet's
  // size that fits in a byte maps evenly onto the alphabet; the rest are
  // dropped, so no character is likelier than another (a plain mod would
  // favour the first 256 mod 94 characters)
  APassword := '';
  LSize := PC_PRJ_PASSWORD_LAST - PC_PRJ_PASSWORD_FIRST + 1;
  LLimit := (256 div LSize) * LSize;

  LBuilder := TStringBuilder.Create();
  try
    while LBuilder.Length < PC_PRJ_PASSWORD_LENGTH do
    begin
      if not TSecureRandom.GetBytes(PC_PRJ_PASSWORD_LENGTH * 2, LBytes) then
        Exit(False);
      for LByte in LBytes do
      begin
        if LBuilder.Length = PC_PRJ_PASSWORD_LENGTH then
          Break;
        if LByte < LLimit then
          LBuilder.Append(Char(PC_PRJ_PASSWORD_FIRST + (LByte mod LSize)));
      end;
    end;
    APassword := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
  Result := True;
end;

// SplitMix64 computes modular results on purpose (the state's add and the
// mix's multiplies wrap): overflow and range checks are off for it and
// ScramblePassword only, and restored after
{$IFOPT Q+}
  {$DEFINE PC_PRJ_SCRAMBLE_Q}
  {$Q-}
{$ENDIF}
{$IFOPT R+}
  {$DEFINE PC_PRJ_SCRAMBLE_R}
  {$R-}
{$ENDIF}

class function TPCProject.DoSplitMixNext(var AState: UInt64): UInt64;
const
  { PC_PRJ_SPLITMIX_GAMMA }
  // SplitMix64's state step (the golden ratio's 64-bit fraction)
  PC_PRJ_SPLITMIX_GAMMA: UInt64 = $9E3779B97F4A7C15;
  { PC_PRJ_SPLITMIX_MUL1 }
  // The mix's first multiplier
  PC_PRJ_SPLITMIX_MUL1: UInt64 = $BF58476D1CE4E5B9;
  { PC_PRJ_SPLITMIX_MUL2 }
  // The mix's second multiplier
  PC_PRJ_SPLITMIX_MUL2: UInt64 = $94D049BB133111EB;
var
  LZ: UInt64;
begin
  // One SplitMix64 step: the state moves on by the gamma, the word is the
  // state mixed (the runtime's project_password_word is the same step)
  AState := AState + PC_PRJ_SPLITMIX_GAMMA;
  LZ := AState;
  LZ := (LZ xor (LZ shr 30)) * PC_PRJ_SPLITMIX_MUL1;
  LZ := (LZ xor (LZ shr 27)) * PC_PRJ_SPLITMIX_MUL2;
  Result := LZ xor (LZ shr 31);
end;

class procedure TPCProject.ScramblePassword(const APassword: string; out AData: TBytes;
  out AKey: UInt64);
var
  LPlain: TBytes;
  LDigest: TBytes;
  LState: UInt64;
  LWord: UInt64;
  LI: Integer;
begin
  // The key: the digest's first 8 bytes, the first one lowest
  LPlain := TEncoding.UTF8.GetBytes(APassword);
  LDigest := TBlake2b.HashBytes(TEncoding.UTF8.GetBytes(PC_PRJ_SECRET_SALT + APassword));
  AKey := 0;
  for LI := 7 downto 0 do
    AKey := (AKey shl 8) or LDigest[LI];

  // Each byte XOR the keystream's byte at its place: a new word every 8
  // bytes, its bytes taken low first
  SetLength(AData, Length(LPlain));
  LState := AKey;
  LWord := 0;
  for LI := 0 to High(LPlain) do
  begin
    if (LI mod 8) = 0 then
      LWord := DoSplitMixNext(LState);
    AData[LI] := LPlain[LI] xor Byte(LWord shr (8 * (LI mod 8)));
  end;
end;

{$IFDEF PC_PRJ_SCRAMBLE_Q}
  {$Q+}
  {$UNDEF PC_PRJ_SCRAMBLE_Q}
{$ENDIF}
{$IFDEF PC_PRJ_SCRAMBLE_R}
  {$R+}
  {$UNDEF PC_PRJ_SCRAMBLE_R}
{$ENDIF}

function TPCProject.MainPath(): string;
begin
  Result := TUtils.ResolvePath(FMainModule, FRoot);
end;

function TPCProject.OutputPath(): string;
begin
  Result := TUtils.ResolvePath(FOutputDir, FRoot);
end;

function TPCProject.AssetsPath(): string;
begin
  Result := TUtils.ResolvePath(PC_PRJ_ASSETS_DIR, FRoot);
end;

function TPCProject.PackPath(): string;
begin
  Result := TUtils.JoinResolvedPath(OutputPath(), PC_PRJ_PACK_DIR);
end;

function TPCProject.BinPath(): string;
begin
  // The build's own layout folder for the exe (PC_OUTPUT_BIN_DIR)
  Result := TUtils.JoinResolvedPath(OutputPath(), PC_OUTPUT_BIN_DIR);
end;

function TPCProject.DatPath(): string;
begin
  // Beside the exe, so the program opens it as $P:<name>.dat
  Result := TUtils.JoinResolvedPath(BinPath(), FProjectName + PC_PRJ_DAT_EXT);
end;

class function TPCProject.KindFromText(const AText: string;
  out AKind: TPCProjectKind): Boolean;
var
  LKind: TPCProjectKind;
begin
  Result := False;
  AKind := pkExe;
  for LKind := Low(TPCProjectKind) to High(TPCProjectKind) do
  begin
    if AText = PC_PRJ_KIND_TEXT[LKind] then
    begin
      AKind := LKind;
      Exit(True);
    end;
  end;
end;

class function TPCProject.NameProblem(const AName: string): string;
var
  LI: Integer;
  LRow: TPCTokenRow;
  LDevice: string;
begin
  // An identifier (it names the main module and the .dat), never a word
  // either token table reserves, never a Windows device name
  Result := '';

  if (AName = '') or (not CharInSet(AName[1], ['A'..'Z', 'a'..'z', '_'])) then
    Exit(RSPrjNameNotIdent);
  for LI := 2 to Length(AName) do
  begin
    if not CharInSet(AName[LI], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Exit(RSPrjNameNotIdent);
  end;

  for LRow in PC_PASKAL_TOKENS do
  begin
    if (LRow.Category in [tcKeyword, tcCppKeyword, tcPrimitive]) and SameText(LRow.Text, AName) then
      Exit(RSPrjNameReserved);
  end;
  for LRow in PC_CPP_TOKENS do
  begin
    if (LRow.Category in [tcKeyword, tcCppKeyword, tcPrimitive]) and SameText(LRow.Text, AName) then
      Exit(RSPrjNameReserved);
  end;

  for LDevice in PC_PRJ_DEVICE_NAMES do
  begin
    if SameText(LDevice, AName) then
      Exit(RSPrjNameDevice);
  end;
end;

end.
