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
  UTestCase.Utils - StdApp.Utils directory and resource routine tests

  TTestCase suite for TUtils.CreateDirInPath (the argument names a file: its
  directory is created, whatever the file name looks like) and
  TUtils.EnsureDirectory (the argument is the directory itself). Real
  directories are made under tests\probe\utils\out, emptied first.
  The resource tests stamp copies of zig-built PE fixtures
  (tests\probe\utils\res: hello.exe, lib.dll, good and malformed .ico files)
  and read the result back through the Windows version / resource APIs.
  long_path checks TUtils.ResolvePath past the plain Win32 limit (R28, R36):
  the long-path spelling past PATH_PLAIN_MAX, every spelling of a real deep
  file readable and idempotent (tests\probe\utils\longpath, made and removed
  by the test). join_resolved checks TUtils.JoinResolvedPath equals
  ResolvePath around both limits (R41). resource_long_path stamps a file at
  and past PATH_RESOURCE_MAX in both spellings and reads every stamp back
  from a short copy (R42); a read-only file is left as it was; TMP points at
  a scratch folder, so a temp copy left behind is seen. resource_busy holds
  the file open for a moment (stamped once free) and for longer than the
  retry window (fails with the reason, after the window) (R46). quote_arg
  round-trips TUtils.QuoteCommandArg through CommandLineToArgvW for every
  argument shape; capture_spaces launches a real exe from a folder with a
  space through both capture routines (R49). capture_start: a program that
  cannot start raises through both routines with the OS reason, the exit
  code untouched (R34). launch_long_path runs the argv fixture at and past
  PATH_LAUNCH_MAX in either spelling through both (A5). run_elf runs
  argv.elf through WSL from a folder with a space: arguments a shell would
  change arrive as literal argv, the same as argv.exe's on Windows, exit 7
  kept (R35), and over pipes (AUsePipes) the program's own text with no
  console rendering; a chmod that fails and a path with no WSL form raise
  (R26, R18 G4). run_pe: RunPE's capturing overload runs argv.exe from a
  folder with a space through the pseudoconsole and over pipes (literal
  argv, exit 7, pipes with no console rendering); an empty or missing
  program raises. capture_lines: CaptureConsoleOutput delivers every line
  with AKeepEmptyLines (empty ones and a last unterminated one) and skips
  the empty ones without it. pty_key_text / pty_parse_frames: the pure key
  and pipe-frame decoders of the run hosts, by rows. pty_stream_host /
  pty_pipe_host: a program reading stdin to its end gets its input from a
  stream host (the program's own handle, real EOF) and from a pipe host
  (pseudoconsole keys, the terminal's end-of-input key), both targets.

  Dependencies: StdApp.TestCase, StdApp.Utils
===============================================================================}

unit UTestCase.Utils;

interface

uses
  StdApp.TestCase;

type

  { TPCUtilsTests }
  TPCUtilsTests = class(TTestCase)
  private
    // One test per routine; Create registers each under its CLI name
    procedure DoTestCreateDirInPath();
    procedure DoTestEnsureDirectory();
    procedure DoTestIconResource();
    procedure DoTestVersionResource();
    procedure DoTestManifestResource();
    procedure DoTestLongPath();
    procedure DoTestJoinResolved();
    procedure DoTestResourceLongPath();
    procedure DoTestResourceBusy();
    procedure DoTestQuoteArg();
    procedure DoTestCommandLineTail();
    procedure DoTestCaptureSpaces();
    procedure DoTestCaptureStart();
    procedure DoTestLaunchLongPath();
    procedure DoTestRunElf();
    procedure DoTestRunPE();
    procedure DoTestCaptureLines();
    procedure DoTestCaptureTick();
    procedure DoTestPtyKeyText();
    procedure DoTestPtyParseFrames();
    procedure DoTestPtyStreamHost();
    procedure DoTestPtyPipeHost();
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
  System.Classes,
  Winapi.ShellAPI,
  StdApp.Utils;

function DoScratchRoot(): string;
begin
  // tests\probe\utils\out, emptied first. The exe sits two levels below the
  // project root (repo\bin). Empty when it cannot be prepared.
  Result := TUtils.ResolvePath('..\..\tests\probe\utils\out',
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

function DoResPath(const AName: string): string;
begin
  // A fixture in tests\probe\utils\res
  Result := TUtils.ResolvePath('..\..\tests\probe\utils\res\' + AName,
    TPath.GetDirectoryName(ParamStr(0)));
end;

function DoCopyFixture(const ARoot: string; const AName: string;
  const ACopyName: string): string;
begin
  // A fresh copy of fixture AName as ARoot\ACopyName; empty when the copy fails
  Result := TPath.Combine(ARoot, ACopyName);
  try
    TFile.Copy(DoResPath(AName), Result, True);
  except
    on Exception do
      Result := '';
  end;
end;

function DoRaised(const AProc: TProc): string;
begin
  // '' when AProc returns normally, else '<class>: <message>' of what it raised
  Result := '';
  try
    AProc();
  except
    on E: Exception do
      Result := E.ClassName() + ': ' + E.Message;
  end;
end;

function DoHasMainIcon(const APath: string): Boolean;
var
  LModule: HMODULE;
begin
  // The RT_GROUP_ICON 'MAINICON' UpdateIconResource writes, read as data
  Result := False;
  LModule := LoadLibraryEx(PChar(APath), 0, LOAD_LIBRARY_AS_DATAFILE);
  if LModule = 0 then
    Exit;
  try
    Result := FindResource(LModule, 'MAINICON', RT_GROUP_ICON) <> 0;
  finally
    FreeLibrary(LModule);
  end;
end;

function DoReadVersion(const APath: string; out AFileType: DWORD;
  out AProductName: string; out AProductNameLen: UINT;
  out AInternalName: string): Boolean;
var
  LHandle: DWORD;
  LSize: DWORD;
  LBuffer: TBytes;
  LValue: Pointer;
  LValueLen: UINT;
begin
  // Reads back the version resource the way every Windows consumer does
  Result := False;
  AFileType := 0;
  AProductName := '';
  AProductNameLen := 0;
  AInternalName := '';

  LSize := GetFileVersionInfoSize(PChar(APath), LHandle);
  if LSize = 0 then
    Exit;
  SetLength(LBuffer, LSize);
  if not GetFileVersionInfo(PChar(APath), 0, LSize, @LBuffer[0]) then
    Exit;

  if not VerQueryValue(@LBuffer[0], '\', LValue, LValueLen) then
    Exit;
  AFileType := PVSFixedFileInfo(LValue)^.dwFileType;

  // puLen is the value's length as the resource states it (wValueLength)
  if not VerQueryValue(@LBuffer[0], '\StringFileInfo\040904B0\ProductName',
    LValue, LValueLen) then
    Exit;
  AProductName := PChar(LValue);
  AProductNameLen := LValueLen;

  if not VerQueryValue(@LBuffer[0], '\StringFileInfo\040904B0\InternalName',
    LValue, LValueLen) then
    Exit;
  AInternalName := PChar(LValue);

  Result := True;
end;

function DoLongRoot(): string;
begin
  // tests\probe\utils\longpath in its plain backslash spelling, removed
  // first through the long-path spelling (it holds paths past the plain
  // limit). Empty when it cannot be prepared.
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)),
    '..\..\tests\probe\utils\longpath'));
  try
    if TDirectory.Exists(PATH_LONG_PREFIX + Result) then
      TDirectory.Delete(PATH_LONG_PREFIX + Result, True);
    TDirectory.CreateDirectory(Result);
  except
    on Exception do
      Result := '';
  end;
end;

function DoResolves(const APath: string; out AResolved: string): Boolean;
begin
  // ResolvePath without letting a raise escape the test: False when it raises
  AResolved := '';
  try
    AResolved := TUtils.ResolvePath(APath);
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

function DoReadLength(const APath: string): Integer;
begin
  // Bytes read from APath, -1 when the read raises
  try
    Result := Length(TFile.ReadAllBytes(APath));
  except
    on Exception do
      Result := -1;
  end;
end;

function DoWslPath(const APath: string): string;
begin
  // TUtils.WindowsPathToWSL, or 'RAISE' when it raises
  try
    Result := TUtils.WindowsPathToWSL(APath);
  except
    on Exception do
      Result := 'RAISE';
  end;
end;

function DoResolvesIn(const APath: string; const ABase: string;
  out AResolved: string): Boolean;
begin
  // ResolvePath against ABase without letting a raise escape the test: False
  // when it raises
  AResolved := '';
  try
    AResolved := TUtils.ResolvePath(APath, ABase);
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

function DoHasManifest(const APath: string): Boolean;
var
  LModule: HMODULE;
begin
  // The RT_MANIFEST AddResManifestFromResource writes, read as data
  Result := False;
  LModule := LoadLibraryEx(PChar(APath), 0, LOAD_LIBRARY_AS_DATAFILE);
  if LModule = 0 then
    Exit;
  try
    Result := FindResource(LModule, CREATEPROCESS_MANIFEST_RESOURCE_ID, RT_MANIFEST) <> 0;
  finally
    FreeLibrary(LModule);
  end;
end;

function DoCopyTo(const ASource: string; const ADest: string): Boolean;
begin
  // TFile.Copy, overwriting, without letting a raise escape the test
  try
    TFile.Copy(ASource, ADest, True);
    Result := True;
  except
    on Exception do
      Result := False;
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

function DoEntryCount(const ADir: string): Integer;
begin
  // Files and folders in ADir; -1 when it cannot be listed
  try
    Result := Length(TDirectory.GetFileSystemEntries(ADir));
  except
    on Exception do
      Result := -1;
  end;
end;

type
  { TResourceTestCase }
  // A file of PathLength characters (plain spelling), named to the resource
  // routines in the long-path spelling or the plain one
  TResourceTestCase = record
    PathLength: Integer;
    LongSpelled: Boolean;
  end;

const
  { RESOURCE_TEST_CASES }
  // At the resource API's limit in both spellings (the long one failed there:
  // probe2.txt) and past it (long spelling only: a plain one reaches no file)
  RESOURCE_TEST_CASES: array[0..3] of TResourceTestCase = (
    (PathLength: PATH_RESOURCE_MAX; LongSpelled: False),
    (PathLength: PATH_RESOURCE_MAX; LongSpelled: True),
    (PathLength: PATH_RESOURCE_MAX + 1; LongSpelled: True),
    (PathLength: 300; LongSpelled: True)
  );

{ TPCUtilsTests }

constructor TPCUtilsTests.Create();
begin
  inherited;

  Title := 'Utils';
  RegisterTest('create_dir_in_path', DoTestCreateDirInPath);
  RegisterTest('ensure_directory', DoTestEnsureDirectory);
  RegisterTest('icon_resource', DoTestIconResource);
  RegisterTest('version_resource', DoTestVersionResource);
  RegisterTest('manifest_resource', DoTestManifestResource);
  RegisterTest('long_path', DoTestLongPath);
  RegisterTest('join_resolved', DoTestJoinResolved);
  RegisterTest('resource_long_path', DoTestResourceLongPath);
  RegisterTest('resource_busy', DoTestResourceBusy);
  RegisterTest('quote_arg', DoTestQuoteArg);
  RegisterTest('command_line_tail', DoTestCommandLineTail);
  RegisterTest('capture_spaces', DoTestCaptureSpaces);
  RegisterTest('capture_start', DoTestCaptureStart);
  RegisterTest('launch_long_path', DoTestLaunchLongPath);
  RegisterTest('run_elf', DoTestRunElf);
  RegisterTest('run_pe', DoTestRunPE);
  RegisterTest('capture_lines', DoTestCaptureLines);
  RegisterTest('capture_tick', DoTestCaptureTick);
  RegisterTest('pty_key_text', DoTestPtyKeyText);
  RegisterTest('pty_parse_frames', DoTestPtyParseFrames);
  RegisterTest('pty_stream_host', DoTestPtyStreamHost);
  RegisterTest('pty_pipe_host', DoTestPtyPipeHost);
end;

procedure TPCUtilsTests.Run();
begin
  inherited;
end;

procedure TPCUtilsTests.DoTestLongPath();
var
  LRoot: string;
  LDir247: string;
  LDir248: string;
  LLongDir: string;
  LFile: string;
  LSpellings: TArray<string>;
  LSpelling: string;
  LResolved: string;
  LAgain: string;
  LUncTail: string;
begin
  // ResolvePath returns a path past PATH_PLAIN_MAX in the long-path
  // spelling (the plain one fails in Win32 routines), takes every spelling
  // of it back, and returns each of its own results unchanged (R28, R36)
  LRoot := DoLongRoot();
  Check(LRoot <> '', 'long path: scratch root prepared');
  if LRoot = '' then
    Exit;

  try
    // The boundary: 247 characters stay plain, 248 take the prefix
    LDir247 := LRoot + '\' + StringOfChar('a', PATH_PLAIN_MAX - Length(LRoot) - 1);
    LDir248 := LDir247 + 'b';
    Check(DoResolves(LDir247, LResolved) and
      (LResolved = TUtils.NormalizePath(LDir247)),
      'long path: 247 characters stay in the plain spelling');
    Check(DoResolves(LDir248, LResolved) and
      (LResolved = PATH_LONG_PREFIX + LDir248),
      'long path: 248 characters take the long-path spelling');
    Check(TUtils.EnsureDirectory(LDir248) and
      TDirectory.Exists(PATH_LONG_PREFIX + LDir248),
      'long path: a 248-character directory is created');

    // A real file deep past the limit, read through every spelling
    LLongDir := LRoot + '\' + StringOfChar('e', 120) + '\' + StringOfChar('f', 120);
    LFile := LLongDir + '\f.txt';
    Check(TUtils.EnsureDirectory(LLongDir), 'long path: deep directory created');
    try
      TFile.WriteAllBytes(PATH_LONG_PREFIX + LFile, TEncoding.ASCII.GetBytes('12345'));
    except
      on Exception do
        Check(False, 'long path: fixture written');
    end;
    LSpellings := [LFile, LFile.Replace('\', '/'), PATH_LONG_PREFIX + LFile,
      ('//?/' + LFile).Replace('\', '/')];
    for LSpelling in LSpellings do
    begin
      Check(DoResolves(LSpelling, LResolved) and (DoReadLength(LResolved) = 5),
        'long path: readable through ' + LSpelling.Substring(0, 6) + '...');
      Check(DoResolves(LResolved, LAgain) and (LAgain = LResolved),
        'long path: idempotent from ' + LSpelling.Substring(0, 6) + '...');
    end;

    // A short path in the long-path spelling is kept and usable
    Check(DoResolves(PATH_LONG_PREFIX + LRoot, LResolved) and
      (LResolved = PATH_LONG_PREFIX + LRoot) and TDirectory.Exists(LResolved),
      'long path: a short long-path spelling is kept and usable');

    // A long UNC path takes the UNC long-path spelling (no network access)
    LUncTail := 'srv\share\' + StringOfChar('u', 250);
    Check(DoResolves('\\' + LUncTail, LResolved) and
      (LResolved = PATH_LONG_UNC_PREFIX + LUncTail),
      'long path: a long UNC path takes \\?\UNC\');

    Check((TUtils.NormalizePath('//?/C:/x/y') = '\\?\C:\x\y') and
      (TUtils.NormalizePath('C:\x\y') = 'C:/x/y'),
      'long path: the long-path spelling keeps backslashes, a plain one normalizes');
    Check((TUtils.StripLongPathPrefix('\\?\C:\x') = 'C:\x') and
      (TUtils.StripLongPathPrefix('\\?\UNC\srv\share\x') = '\\srv\share\x') and
      (TUtils.StripLongPathPrefix('C:/x') = 'C:/x'),
      'long path: prefix stripped, any other path unchanged');
    Check(TUtils.SamePath('\\?\C:\A\b\', 'c:/a/B') and
      (not TUtils.SamePath('C:/a', 'C:/ab')),
      'long path: SamePath compares one spelling');
    Check(DoWslPath('\\?\C:\a\b') = '/mnt/c/a/b',
      'long path: WSL path of a long-path spelling');
  finally
    try
      TDirectory.Delete(PATH_LONG_PREFIX + LRoot, True);
    except
      on Exception do
        Check(False, 'long path: scratch root removed');
    end;
  end;
end;

procedure TPCUtilsTests.DoTestCreateDirInPath();
var
  LRoot: string;
begin
  // The argument names a file, whatever its name looks like: its directory
  // is created, never the file name itself
  LRoot := DoScratchRoot();
  Check(LRoot <> '', 'utils: scratch root prepared');
  if LRoot = '' then
    Exit;

  Check(TUtils.CreateDirInPath(TPath.Combine(LRoot, 'a.v1\data.txt')) and
    TDirectory.Exists(TPath.Combine(LRoot, 'a.v1')),
    'file with an extension: its dotted directory is created');
  Check(TUtils.CreateDirInPath(TPath.Combine(LRoot, 'b\Makefile')) and
    TDirectory.Exists(TPath.Combine(LRoot, 'b')) and
    (not TDirectory.Exists(TPath.Combine(LRoot, 'b\Makefile'))),
    'file without an extension: not made a directory');
  Check(not TUtils.CreateDirInPath(''), 'empty name: nothing created');
end;

procedure TPCUtilsTests.DoTestEnsureDirectory();
var
  LRoot: string;
begin
  // The argument is the directory itself: a dotted name is not a file name
  LRoot := DoScratchRoot();
  Check(LRoot <> '', 'utils: scratch root prepared');
  if LRoot = '' then
    Exit;

  Check(TUtils.EnsureDirectory(TPath.Combine(LRoot, 'c.v2')) and
    TDirectory.Exists(TPath.Combine(LRoot, 'c.v2')),
    'dotted directory: created itself');
  Check(TUtils.EnsureDirectory(TPath.Combine(LRoot, 'd\e\f')) and
    TDirectory.Exists(TPath.Combine(LRoot, 'd\e\f')),
    'nested directory: created with its parents');
  Check(TUtils.EnsureDirectory(TPath.Combine(LRoot, 'c.v2')),
    'existing directory: True');
  Check(not TUtils.EnsureDirectory(''), 'empty path: False');
end;

procedure TPCUtilsTests.DoTestIconResource();
const
  { BAD_ICONS }
  // Each must raise a clean Exception before the executable is touched
  BAD_ICONS: array[0..3] of string = (
    'empty.ico',        // 0 bytes: no header
    'header_only.ico',  // header says 1 image, no directory entry
    'bad_offset.ico',   // image offset far past the end of the file
    'cursor_type.ico'   // idType 2: a cursor, not an icon
  );
var
  LRoot: string;
  LExe: string;
  LIcon: string;
  LHashBefore: string;
  LRaised: string;
  LI: Integer;
begin
  LRoot := DoScratchRoot();
  Check(LRoot <> '', 'utils: scratch root prepared');
  if LRoot = '' then
    Exit;

  // A good icon is stamped
  LExe := DoCopyFixture(LRoot, 'hello.exe', 'icon_good.exe');
  Check(LExe <> '', 'icon: fixture copied');
  if LExe = '' then
    Exit;
  LRaised := DoRaised(
    procedure
    begin
      TUtils.UpdateIconResource(LExe, DoResPath('good.ico'));
    end);
  Check(LRaised = '', Format('icon good.ico: stamped without a raise (%s)', [LRaised]));
  Check(DoHasMainIcon(LExe), 'icon good.ico: MAINICON group present');

  // Every malformed .ico raises "Invalid icon file", executable unchanged
  for LI := Low(BAD_ICONS) to High(BAD_ICONS) do
  begin
    LIcon := BAD_ICONS[LI];
    LExe := DoCopyFixture(LRoot, 'hello.exe',
      'icon_' + TPath.GetFileNameWithoutExtension(LIcon) + '.exe');
    if LExe = '' then
    begin
      Check(False, Format('icon %s: fixture copied', [LIcon]));
      Continue;
    end;
    LHashBefore := TUtils.GetFileSHA256(LExe);
    LRaised := DoRaised(
      procedure
      begin
        TUtils.UpdateIconResource(LExe, DoResPath(LIcon));
      end);
    Check(LRaised.StartsWith('Exception: Invalid icon file'),
      Format('icon %s: raises "Invalid icon file" (%s)', [LIcon, LRaised]));
    Check(TUtils.GetFileSHA256(LExe) = LHashBefore,
      Format('icon %s: executable unchanged', [LIcon]));
  end;

  // A missing executable raises
  LRaised := DoRaised(
    procedure
    begin
      TUtils.UpdateIconResource(TPath.Combine(LRoot, 'missing.exe'), DoResPath('good.ico'));
    end);
  Check(LRaised.Contains('does not exist'),
    Format('icon: missing executable raises (%s)', [LRaised]));
end;

procedure TPCUtilsTests.DoTestVersionResource();
var
  LRoot: string;
  LExe: string;
  LDll: string;
  LRaised: string;
  LFileType: DWORD;
  LProduct: string;
  LProductLen: UINT;
  LInternal: string;
begin
  LRoot := DoScratchRoot();
  Check(LRoot <> '', 'utils: scratch root prepared');
  if LRoot = '' then
    Exit;

  LExe := DoCopyFixture(LRoot, 'hello.exe', 'ver.exe');
  LDll := DoCopyFixture(LRoot, 'lib.dll', 'ver.dll');
  Check((LExe <> '') and (LDll <> ''), 'version: fixtures copied');
  if (LExe = '') or (LDll = '') then
    Exit;

  // Executable: VFT_APP; a String's length is characters + null (Windows
  // consumers read exactly that many); InternalName is the module name
  LRaised := DoRaised(
    procedure
    begin
      TUtils.UpdateVersionInfoResource(LExe, 1, 2, 3, 'ProbeProduct',
        'ProbeDescription', 'probe.bin', 'ProbeCompany', 'ProbeCopyright');
    end);
  Check(LRaised = '', Format('version exe: stamped without a raise (%s)', [LRaised]));
  Check(DoReadVersion(LExe, LFileType, LProduct, LProductLen, LInternal),
    'version exe: readable through GetFileVersionInfo');
  Check(LFileType = VFT_APP, Format('version exe: file type %d = VFT_APP', [LFileType]));
  Check(LProduct = 'ProbeProduct', Format('version exe: ProductName %s', [LProduct]));
  Check(LProductLen = UINT(Length('ProbeProduct') + 1),
    Format('version exe: ProductName length %d = 13 (characters + null)', [LProductLen]));
  Check(LInternal = 'probe', Format('version exe: InternalName %s = probe', [LInternal]));

  // DLL: VFT_DLL, decided by the image's own header
  LRaised := DoRaised(
    procedure
    begin
      TUtils.UpdateVersionInfoResource(LDll, 1, 2, 3, 'ProbeProduct',
        'ProbeDescription', 'probe.dll', 'ProbeCompany', 'ProbeCopyright');
    end);
  Check(LRaised = '', Format('version dll: stamped without a raise (%s)', [LRaised]));
  Check(DoReadVersion(LDll, LFileType, LProduct, LProductLen, LInternal),
    'version dll: readable through GetFileVersionInfo');
  Check(LFileType = VFT_DLL, Format('version dll: file type %d = VFT_DLL', [LFileType]));

  // A missing file raises
  LRaised := DoRaised(
    procedure
    begin
      TUtils.UpdateVersionInfoResource(TPath.Combine(LRoot, 'missing.exe'), 1, 2, 3,
        'P', 'D', 'f.exe', 'C', 'R');
    end);
  Check(LRaised <> '', 'version: missing file raises');
end;

procedure TPCUtilsTests.DoTestManifestResource();
var
  LRoot: string;
  LExe: string;
  LMessage: string;
begin
  LRoot := DoScratchRoot();
  Check(LRoot <> '', 'utils: scratch root prepared');
  if LRoot = '' then
    Exit;

  LExe := DoCopyFixture(LRoot, 'hello.exe', 'manifest.exe');
  Check(LExe <> '', 'manifest: fixture copied');
  if LExe = '' then
    Exit;

  // A failure says why; the original overload still answers False
  Check((not TUtils.AddResManifestFromResource('PCPP_NO_SUCH_RES', LExe, LMessage)) and
    LMessage.Contains('not found'),
    Format('manifest: missing resource -> False with a reason (%s)', [LMessage]));
  Check(not TUtils.AddResManifestFromResource('PCPP_NO_SUCH_RES', LExe),
    'manifest: original overload -> False');
end;

procedure TPCUtilsTests.DoTestJoinResolved();
var
  LDirs: TArray<string>;
  LDir: string;
  LLength: Integer;
  LNameLength: Integer;
  LName: string;
  LJoined: string;
  LResolved: string;
  LBad: string;
begin
  // JoinResolvedPath is ResolvePath(name, dir) joined as text: the same result
  // at every length around PATH_PLAIN_MAX and PATH_RESOURCE_MAX, from a plain,
  // a UNC and a long-path directory (R41). Nothing here touches the file
  // system: the directories need not exist.
  LDirs := [TUtils.ResolvePath('C:\' + StringOfChar('j', 200)),
    TUtils.ResolvePath('\\srv\share\' + StringOfChar('u', 200)),
    TUtils.ResolvePath('C:\' + StringOfChar('k', 130) + '\' + StringOfChar('k', 130))];
  Check(LDirs[2].StartsWith(PATH_LONG_PREFIX), 'join: the long directory is long-spelled');

  LBad := '';
  for LDir in LDirs do
  begin
    for LLength := PATH_PLAIN_MAX - 10 to PATH_RESOURCE_MAX + 10 do
    begin
      // The plain and UNC directories cross both limits; the long one is
      // past them already
      LNameLength := LLength - Length(TUtils.StripLongPathPrefix(LDir)) - 1;
      if LNameLength < 1 then
        LNameLength := 1;
      LName := StringOfChar('n', LNameLength);
      LJoined := TUtils.JoinResolvedPath(LDir, LName);
      if (not DoResolvesIn(LName, LDir, LResolved)) or (LJoined <> LResolved) then
        LBad := LBad + Format(' [%d: %s <> %s]', [LLength, LJoined, LResolved]);
    end;
  end;
  Check(LBad = '', 'join: equal to ResolvePath at every length' + LBad);

  LDir := LDirs[0];
  Check((TUtils.JoinResolvedPath(LDir, 'zig-out\bin\x.exe') =
    TUtils.ResolvePath('zig-out\bin\x.exe', LDir)) and
    (TUtils.JoinResolvedPath(LDir, 'zig-out/bin/x.exe') =
    TUtils.ResolvePath('zig-out\bin\x.exe', LDir)),
    'join: a relative path in either slash');
  Check(TUtils.JoinResolvedPath(LDir + '/', 'a') = TUtils.JoinResolvedPath(LDir, 'a'),
    'join: a trailing delimiter on the directory');
  Check(TUtils.JoinResolvedPath(TUtils.ResolvePath('C:\'), 'a') = 'C:/a',
    'join: a drive root');
end;

procedure TPCUtilsTests.DoTestResourceLongPath();
var
  LRoot: string;
  LTmp: string;
  LOldTmp: string;
  LCheckCopy: string;
  LI: Integer;
  LCase: TResourceTestCase;
  LFile: string;
  LArg: string;
  LTag: string;
  LMessage: string;
  LFileType: DWORD;
  LProductName: string;
  LProductNameLen: UINT;
  LInternalName: string;
  LBefore: TBytes;
begin
  // The resource routines stamp any file the RTL reaches (R42): the Win32
  // resource API takes at most PATH_RESOURCE_MAX characters as spelled, so a
  // longer path is stamped through a temp copy. Each stamp is read back from
  // a short copy (the loader takes no longer path either). TMP points at a
  // scratch folder, so a temp copy left behind is seen.
  LRoot := DoLongRoot();
  Check(LRoot <> '', 'resource long path: scratch root prepared');
  if LRoot = '' then
    Exit;

  LTmp := LRoot + '\tmp';
  LCheckCopy := LRoot + '\check.exe';
  LOldTmp := GetEnvironmentVariable('TMP');
  try
    Check(DoRaised(
      procedure
      begin
        TDirectory.CreateDirectory(LTmp);
      end) = '', 'resource long path: scratch temp folder made');
    SetEnvironmentVariable('TMP', PChar(LTmp));

    // The fixture carries none of the stamps: each one read back is new
    Check(DoCopyTo(DoResPath('hello.exe'), LCheckCopy) and
      (not DoHasManifest(LCheckCopy)) and (not DoHasMainIcon(LCheckCopy)) and
      (not DoReadVersion(LCheckCopy, LFileType, LProductName, LProductNameLen,
      LInternalName)),
      'resource long path: the fixture carries no manifest, icon or version info');

    for LI := Low(RESOURCE_TEST_CASES) to High(RESOURCE_TEST_CASES) do
    begin
      LCase := RESOURCE_TEST_CASES[LI];
      LFile := LRoot + '\' + StringOfChar('r', LCase.PathLength - Length(LRoot) - 5) + '.exe';
      if LCase.LongSpelled then
      begin
        LArg := PATH_LONG_PREFIX + LFile;
        LTag := Format('%d long', [Length(LFile)]);
      end
      else
      begin
        LArg := LFile;
        LTag := Format('%d plain', [Length(LFile)]);
      end;

      Check(DoCopyTo(DoResPath('hello.exe'), PATH_LONG_PREFIX + LFile),
        'resource long path %s: fixture copied', [LTag]);
      Check(TUtils.AddResManifestFromResource('EXE_MANIFEST', LArg, LMessage),
        'resource long path %s: manifest stamped (%s)', [LTag, LMessage]);
      LMessage := DoRaised(
        procedure
        begin
          TUtils.UpdateIconResource(LArg, DoResPath('good.ico'));
        end);
      Check(LMessage = '', 'resource long path %s: icon stamped (%s)', [LTag, LMessage]);
      LMessage := DoRaised(
        procedure
        begin
          TUtils.UpdateVersionInfoResource(LArg, 1, 2, 3, 'LongPath', 'Long path',
            'long.exe', 'Company', 'Copyright');
        end);
      Check(LMessage = '', 'resource long path %s: version info stamped (%s)',
        [LTag, LMessage]);

      // Read back from a short copy
      Check(DoCopyTo(PATH_LONG_PREFIX + LFile, LCheckCopy) and
        DoHasManifest(LCheckCopy) and DoHasMainIcon(LCheckCopy) and
        DoReadVersion(LCheckCopy, LFileType, LProductName, LProductNameLen,
        LInternalName) and (LProductName = 'LongPath'),
        'resource long path %s: manifest, icon and version info read back', [LTag]);
    end;
    Check(DoEntryCount(LTmp) = 0, 'resource long path: no temp copy left behind');

    // A read-only file past the limit: every stamp fails, the file is left as
    // it was, and no temp copy stays behind
    LFile := LRoot + '\' + StringOfChar('o', 300 - Length(LRoot) - 5) + '.exe';
    LArg := PATH_LONG_PREFIX + LFile;
    Check(DoCopyTo(DoResPath('hello.exe'), LArg), 'resource read-only: fixture copied');
    LBefore := DoReadBytes(LArg);
    Check(DoRaised(
      procedure
      begin
        if not SetFileAttributes(PChar(LArg), FILE_ATTRIBUTE_READONLY) then
          RaiseLastOSError();
      end) = '', 'resource read-only: made read-only');
    LMessage := DoRaised(
      procedure
      begin
        TUtils.UpdateVersionInfoResource(LArg, 1, 2, 3, 'P', 'D', 'f.exe', 'C', 'X');
      end);
    Check(LMessage <> '', 'resource read-only: the version stamp raises (%s)', [LMessage]);
    LMessage := DoRaised(
      procedure
      begin
        TUtils.UpdateIconResource(LArg, DoResPath('good.ico'));
      end);
    Check(LMessage <> '', 'resource read-only: the icon stamp raises (%s)', [LMessage]);
    Check((not TUtils.AddResManifestFromResource('EXE_MANIFEST', LArg, LMessage)) and
      (LMessage <> ''),
      'resource read-only: the manifest answers False with a reason (%s)', [LMessage]);
    Check((Length(LBefore) > 0) and DoSameBytes(LBefore, DoReadBytes(LArg)),
      'resource read-only: the file is unchanged');
    Check(DoEntryCount(LTmp) = 0, 'resource read-only: no temp copy left behind');
    Check(DoRaised(
      procedure
      begin
        if not SetFileAttributes(PChar(LArg), FILE_ATTRIBUTE_NORMAL) then
          RaiseLastOSError();
      end) = '', 'resource read-only: attribute restored');
  finally
    if LOldTmp = '' then
      SetEnvironmentVariable('TMP', nil)
    else
      SetEnvironmentVariable('TMP', PChar(LOldTmp));
    try
      TDirectory.Delete(PATH_LONG_PREFIX + LRoot, True);
    except
      on Exception do
        Check(False, 'resource long path: scratch root removed');
    end;
  end;
end;

procedure TPCUtilsTests.DoTestResourceBusy();
var
  LRoot: string;
  LFile: string;
  LHandle: THandle;
  LReleaser: TThread;
  LMessage: string;
  LManifestMessage: string;
  LManifestOk: Boolean;
  LStart: UInt64;
  LElapsed: UInt64;
  LFileType: DWORD;
  LProductName: string;
  LProductNameLen: UINT;
  LInternalName: string;
begin
  // A file another process holds for a moment (a virus scanner reading a new
  // executable, R46) is stamped once it is free: the update is tried again
  // while Windows reports the file busy. A file held past the retry window
  // (RESOURCE_UPDATE_ATTEMPTS, RESOURCE_UPDATE_RETRY_MS apart) fails with the
  // reason, after that window and not much later.
  LRoot := DoScratchRoot();
  Check(LRoot <> '', 'busy: scratch root prepared');
  if LRoot = '' then
    Exit;
  LFile := DoCopyFixture(LRoot, 'hello.exe', 'busy.exe');
  Check(LFile <> '', 'busy: fixture copied');
  if LFile = '' then
    Exit;

  // Held the way a scanner reading a new executable holds it (others may
  // read, nobody may write); a second thread lets go after 150 ms
  LHandle := CreateFile(PChar(LFile), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL, 0);
  Check(LHandle <> INVALID_HANDLE_VALUE, 'busy: file held');
  if LHandle = INVALID_HANDLE_VALUE then
    Exit;
  LReleaser := TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(150);
      CloseHandle(LHandle);
    end);
  LReleaser.FreeOnTerminate := False;
  LReleaser.Start();
  try
    LStart := TUtils.GetTickCount64();
    LMessage := DoRaised(
      procedure
      begin
        TUtils.UpdateVersionInfoResource(LFile, 1, 2, 3, 'Busy', 'Busy file', 'busy.exe',
          'Company', 'Copyright');
      end);
    LElapsed := TUtils.GetTickCount64() - LStart;
  finally
    LReleaser.WaitFor();
    LReleaser.Free();
  end;
  Check(LMessage = '', 'busy: stamped once the file is free (%s)', [LMessage]);
  Check(LElapsed >= 100, 'busy: the first attempt met the held file (%d ms)', [Int64(LElapsed)]);
  Check(DoReadVersion(LFile, LFileType, LProductName, LProductNameLen, LInternalName) and
    (LProductName = 'Busy'), 'busy: version info read back');

  // Held for the whole call: it fails with the reason, after the window
  LHandle := CreateFile(PChar(LFile), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL, 0);
  Check(LHandle <> INVALID_HANDLE_VALUE, 'busy: file held again');
  if LHandle = INVALID_HANDLE_VALUE then
    Exit;
  try
    LStart := TUtils.GetTickCount64();
    LMessage := DoRaised(
      procedure
      begin
        TUtils.UpdateVersionInfoResource(LFile, 1, 2, 3, 'P', 'D', 'f.exe', 'C', 'X');
      end);
    LElapsed := TUtils.GetTickCount64() - LStart;
    LManifestOk := TUtils.AddResManifestFromResource('EXE_MANIFEST', LFile, LManifestMessage);
  finally
    CloseHandle(LHandle);
  end;
  Check(LMessage <> '', 'busy: a file held past the window fails (%s)', [LMessage]);
  Check((LElapsed >= (RESOURCE_UPDATE_ATTEMPTS - 1) * RESOURCE_UPDATE_RETRY_MS) and
    (LElapsed < RESOURCE_UPDATE_ATTEMPTS * RESOURCE_UPDATE_RETRY_MS + 3000),
    'busy: it fails after the retry window, not much later (%d ms)', [Int64(LElapsed)]);
  Check((not LManifestOk) and (LManifestMessage <> '') and
    (not LManifestMessage.Contains('Code:')),
    'busy: the manifest answers False with the plain reason (%s)', [LManifestMessage]);
end;

const
  { PC_UTT_QUOTE_ARGS }
  // Every shape an argument can take: spaces, quotes, backslashes before a
  // quote and at the end, empty, a define value, a Windows path, a tab
  PC_UTT_QUOTE_ARGS: array[0..10] of string = (
    'plain',
    'with space',
    'q"uote',
    'trail\',
    'dir with space\',
    'a\"b',
    'a\\"b',
    '',
    '-DMSG="hi there"',
    'C:\x\y',
    'tab'#9'arg'
  );

type
  { TPCUttArgVector }
  // CommandLineToArgvW's result, indexed
  TPCUttArgVector = array[0..8191] of PWideChar;

  { PPCUttArgVector }
  PPCUttArgVector = ^TPCUttArgVector;

procedure TPCUtilsTests.DoTestQuoteArg();
var
  LLine: string;
  LI: Integer;
  LCount: Integer;
  LArgv: PPCUttArgVector;
  LBad: string;
begin
  // Each argument quoted and joined, then split back by CommandLineToArgvW
  // (the C runtime's rule, which clang reads its argv by): the same text
  Check(TUtils.QuoteCommandArg('plain') = 'plain', 'quote_arg: a plain argument stays as is');
  Check(TUtils.QuoteCommandArg('') = '""', 'quote_arg: an empty argument is ""');

  LLine := 'prog';
  for LI := Low(PC_UTT_QUOTE_ARGS) to High(PC_UTT_QUOTE_ARGS) do
    LLine := LLine + ' ' + TUtils.QuoteCommandArg(PC_UTT_QUOTE_ARGS[LI]);
  LCount := 0;
  LArgv := PPCUttArgVector(CommandLineToArgvW(PWideChar(LLine), LCount));
  if LArgv = nil then
  begin
    Check(False, 'quote_arg: CommandLineToArgvW failed: %s', [SysErrorMessage(GetLastError())]);
    Exit;
  end;
  try
    Check(LCount = Length(PC_UTT_QUOTE_ARGS) + 1, 'quote_arg: %d arguments back (got %d)',
      [Length(PC_UTT_QUOTE_ARGS) + 1, LCount]);
    LBad := '';
    for LI := Low(PC_UTT_QUOTE_ARGS) to High(PC_UTT_QUOTE_ARGS) do
    begin
      if (LI + 1 < LCount) and (string(LArgv^[LI + 1]) <> PC_UTT_QUOTE_ARGS[LI]) then
        LBad := LBad + Format(' [%d: %s -> %s]', [LI, PC_UTT_QUOTE_ARGS[LI],
          string(LArgv^[LI + 1])]);
    end;
    Check(LBad = '', 'quote_arg: every argument comes back as it was' + LBad);
  finally
    LocalFree(HLOCAL(LArgv));
  end;
end;

type
  { TPCUttTailRow }
  TPCUttTailRow = record
    CommandLine: string;
    ArgIndex: Integer;
    Tail: string;
  end;

const
  { PC_UTT_TAIL_ROWS }
  // Expected tails from ParamStr's scan rule (research\compliance\cli-args.md),
  // never from the routine. Row 4: "" before an argument is skipped as
  // ParamStr skips it, so -- is argument 1
  PC_UTT_TAIL_ROWS: array[0..9] of TPCUttTailRow = (
    (CommandLine: 'p a -- x y';                ArgIndex: 2; Tail: 'x y'),
    (CommandLine: '"C:\a b\p.exe" -- x';       ArgIndex: 1; Tail: 'x'),
    (CommandLine: 'p -- "a\"b" " c "';         ArgIndex: 1; Tail: '"a\"b" " c "'),
    (CommandLine: 'p "" -- x';                 ArgIndex: 1; Tail: 'x'),
    (CommandLine: 'p a';                       ArgIndex: 5; Tail: ''),
    (CommandLine: 'p'#9'--'#9'x';              ArgIndex: 1; Tail: 'x'),
    (CommandLine: 'p a --';                    ArgIndex: 2; Tail: ''),
    (CommandLine: 'p --  x   ';                ArgIndex: 1; Tail: 'x   '),
    (CommandLine: 'p "a b"c -- x';             ArgIndex: 2; Tail: 'x'),
    (CommandLine: 'p -- -o out --lsp';         ArgIndex: 1; Tail: '-o out --lsp')
  );

procedure TPCUtilsTests.DoTestCommandLineTail();
var
  LI: Integer;
  LGot: string;
begin
  // The program's arguments after pcpp's -- are forwarded as written
  for LI := Low(PC_UTT_TAIL_ROWS) to High(PC_UTT_TAIL_ROWS) do
  begin
    LGot := TUtils.CommandLineTail(PC_UTT_TAIL_ROWS[LI].CommandLine, PC_UTT_TAIL_ROWS[LI].ArgIndex);
    Check(LGot = PC_UTT_TAIL_ROWS[LI].Tail, 'command_line_tail: [%s] after %d = [%s] (got [%s])',
      [PC_UTT_TAIL_ROWS[LI].CommandLine, PC_UTT_TAIL_ROWS[LI].ArgIndex,
       PC_UTT_TAIL_ROWS[LI].Tail, LGot]);
  end;
end;

procedure TPCUtilsTests.DoTestCaptureSpaces();
var
  LRoot: string;
  LDir: string;
  LExe: string;
  LExitCode: DWORD;
  LRaised: string;
begin
  // A program in a folder with a space (an install under 'C:\Program
  // Files') and a file at the path before the space ('...\with.exe', which
  // Windows tries first for an unquoted path: probe7.txt, error 216): both
  // capture routines launch the program (R49). hello.exe prints nothing and
  // exits 0.
  LRoot := DoScratchRoot();
  Check(LRoot <> '', 'capture_spaces: scratch folder ready');
  if LRoot = '' then
    Exit;
  LDir := TPath.Combine(LRoot, 'with space');
  LExe := '';
  try
    TUtils.EnsureDirectory(LDir);
    LExe := DoCopyFixture(LDir, 'hello.exe', 'hello.exe');
    TFile.WriteAllText(TPath.Combine(LRoot, 'with.exe'), 'not a program');
  except
    on E: Exception do
      Check(False, 'capture_spaces: folder made: %s', [E.Message]);
  end;
  Check(LExe <> '', 'capture_spaces: fixture copied');
  if LExe = '' then
    Exit;

  LExitCode := 1;
  LRaised := DoRaised(
    procedure
    begin
      TUtils.CaptureConsoleOutput('', PChar(LExe), '', LDir, LExitCode, nil, nil);
    end);
  Check((LRaised = '') and (LExitCode = 0),
    'capture_spaces: CaptureConsoleOutput runs it (%s, exit %d)', [LRaised, LExitCode]);

  LExitCode := 1;
  LRaised := DoRaised(
    procedure
    begin
      TUtils.CaptureConsolePTY(PChar(LExe), '', LDir, LExitCode, nil, nil);
    end);
  Check((LRaised = '') and (LExitCode = 0),
    'capture_spaces: CaptureConsolePTY runs it (%s, exit %d)', [LRaised, LExitCode]);
end;

const
  { PC_UTT_RUN_ARGS }
  // Run arguments a shell would change: a variable, a quoted space, a
  // command separator (R35)
  PC_UTT_RUN_ARGS = '$HOME "p q" ;x';

  { PC_UTT_RUN_ARGV }
  // What the argv fixture prints for PC_UTT_RUN_ARGS: the arguments as given
  PC_UTT_RUN_ARGV: array[0..3] of string = (
    '[1]=$HOME',
    '[2]=p q',
    '[3]=;x',
    'argc=4'
  );

  { PC_UTT_LAUNCH_LENGTHS }
  // Program path lengths around PATH_LAUNCH_MAX (259): at it, one past, well past
  PC_UTT_LAUNCH_LENGTHS: array[0..2] of Integer = (
    259,
    260,
    300
  );

function DoMissingRunArgv(const AOutput: string): string;
var
  LLine: string;
begin
  // '' when AOutput holds every PC_UTT_RUN_ARGV line, else the first missing
  Result := '';
  for LLine in PC_UTT_RUN_ARGV do
  begin
    if not AOutput.Contains(LLine) then
    begin
      Result := LLine;
      Exit;
    end;
  end;
end;

function DoRoutineName(const APTY: Boolean): string;
begin
  if APTY then
    Result := 'CaptureConsolePTY'
  else
    Result := 'CaptureConsoleOutput';
end;

function DoCapture(const APTY: Boolean; const AProgram: string;
  const AParams: string; const AWorkDir: string; out AExitCode: DWORD;
  out AOutput: string): string;
var
  LExitCode: DWORD;
  LOutput: string;
begin
  // '' or what the capture routine raised; the exit code it left (42 when
  // it set none) and everything the program printed
  LExitCode := 42;
  LOutput := '';
  Result := DoRaised(
    procedure
    begin
      if APTY then
        TUtils.CaptureConsolePTY(PChar(AProgram), PChar(AParams), AWorkDir,
          LExitCode, nil,
          procedure(const ALine: string; const AData: Pointer)
          begin
            LOutput := LOutput + ALine + #10;
          end)
      else
        TUtils.CaptureConsoleOutput('', PChar(AProgram), PChar(AParams),
          AWorkDir, LExitCode, nil,
          procedure(const ALine: string; const AData: Pointer)
          begin
            LOutput := LOutput + ALine + #10;
          end);
    end);
  AExitCode := LExitCode;
  AOutput := LOutput;
end;

function DoRunElf(const AElf: string; const AParams: string;
  const AWorkDir: string; out AExitCode: DWORD; out AOutput: string;
  const AUsePipes: Boolean = False): string;
var
  LExitCode: DWORD;
  LOutput: string;
  LUsePipes: Boolean;
begin
  // '' or what TUtils.RunElf raised; the exit code it left (42 when it set
  // none) and everything the program printed
  LExitCode := 42;
  LOutput := '';
  LUsePipes := AUsePipes;
  Result := DoRaised(
    procedure
    begin
      TUtils.RunElf(AElf, AParams, AWorkDir, LExitCode, nil,
        procedure(const ALine: string; const AData: Pointer)
        begin
          LOutput := LOutput + ALine + #10;
        end, LUsePipes);
    end);
  AExitCode := LExitCode;
  AOutput := LOutput;
end;

function DoLongFixture(const ARoot: string; const ALength: Integer): string;
var
  LDir: string;
begin
  // argv.exe copied to a path of ALength characters (plain spelling,
  // backslashes) under ARoot; '' when it cannot be placed. Written through
  // the long-path spelling: the folder alone is past PATH_PLAIN_MAX.
  LDir := ARoot.Replace('/', '\') + '\' +
    StringOfChar('d', ALength - Length(ARoot) - 1 - Length('\argv.exe'));
  Result := LDir + '\argv.exe';
  try
    if not TUtils.EnsureDirectory(TUtils.ResolvePath(LDir)) then
      Result := ''
    else
      TFile.Copy(DoResPath('argv.exe'), TUtils.ResolvePath(Result), True);
  except
    on Exception do
      Result := '';
  end;
end;

procedure TPCUtilsTests.DoTestCaptureStart();
var
  LRoot: string;
  LMissing: string;
  LBadExe: string;
  LExitCode: DWORD;
  LOutput: string;
  LRaised: string;
  LPTY: Boolean;
begin
  // A program that cannot be started raises through both capture routines
  // with the OS reason, and no exit code is set (R34: CaptureConsolePTY
  // returned exit code 1 with no reason). A missing file and a file that is
  // not a program.
  LRoot := DoScratchRoot();
  Check(LRoot <> '', 'capture_start: scratch folder ready');
  if LRoot = '' then
    Exit;
  LMissing := TPath.Combine(LRoot, 'missing.exe');
  LBadExe := TPath.Combine(LRoot, 'bad.exe');
  try
    TFile.WriteAllText(LBadExe, 'not a program');
  except
    on E: Exception do
    begin
      Check(False, 'capture_start: fixture written: %s', [E.Message]);
      Exit;
    end;
  end;

  for LPTY := False to True do
  begin
    LRaised := DoCapture(LPTY, LMissing, '', LRoot, LExitCode, LOutput);
    Check(LRaised.StartsWith('EOSError') and (LExitCode = 42),
      'capture_start: %s, a missing program raises, no exit code (%s, exit %d)',
      [DoRoutineName(LPTY), LRaised, LExitCode]);
    LRaised := DoCapture(LPTY, LBadExe, '', LRoot, LExitCode, LOutput);
    Check(LRaised.StartsWith('EOSError') and (LExitCode = 42),
      'capture_start: %s, a file that is not a program raises, no exit code (%s, exit %d)',
      [DoRoutineName(LPTY), LRaised, LExitCode]);
  end;
end;

procedure TPCUtilsTests.DoTestLaunchLongPath();
var
  LRoot: string;
  LExe: string;
  LSpelling: string;
  LOutput: string;
  LRaised: string;
  LExitCode: DWORD;
  LLength: Integer;
  LPTY: Boolean;
  LLong: Boolean;
begin
  // A program at, one past and well past PATH_LAUNCH_MAX runs through both
  // capture routines with its arguments, given in the plain or the long
  // spelling (A5: past the limit CreateProcess finds a program only as the
  // application name in the long spelling; from the command line alone it
  // is error 206, scripts\zb_e\a5\probe1.txt)
  LRoot := DoScratchRoot();
  Check(LRoot <> '', 'launch_long_path: scratch folder ready');
  if LRoot = '' then
    Exit;

  for LLength in PC_UTT_LAUNCH_LENGTHS do
  begin
    LExe := DoLongFixture(LRoot, LLength);
    Check(Length(LExe) = LLength, 'launch_long_path: fixture at %d chars placed (%d)',
      [LLength, Length(LExe)]);
    if LExe = '' then
      Continue;

    for LLong := False to True do
    begin
      if LLong then
        LSpelling := TUtils.ResolvePath(LExe)
      else
        LSpelling := LExe;
      for LPTY := False to True do
      begin
        LRaised := DoCapture(LPTY, LSpelling, '"p q"', LRoot, LExitCode, LOutput);
        Check((LRaised = '') and (LExitCode = 7) and LOutput.Contains('[1]=p q'),
          'launch_long_path: %d chars, long spelling %s, %s runs it (%s, exit %d)',
          [LLength, BoolToStr(LLong, True), DoRoutineName(LPTY), LRaised, LExitCode]);
      end;
    end;
  end;
end;

procedure TPCUtilsTests.DoTestRunElf();
var
  LRoot: string;
  LDir: string;
  LElf: string;
  LExe: string;
  LOutput: string;
  LRaised: string;
  LExitCode: DWORD;
begin
  // argv.elf through WSL from a folder with a space: the arguments arrive as
  // the program's literal argv (R35: bash expanded $HOME, ran ';x' and kept
  // its exit code), the same argv argv.exe prints on Windows, and the exit
  // code is the program's. chmod failing (a missing file) and a path with no
  // WSL form (UNC) raise with the reason (R26, R18 G4).
  LRoot := DoScratchRoot();
  Check(LRoot <> '', 'run_elf: scratch folder ready');
  if LRoot = '' then
    Exit;
  LDir := TPath.Combine(LRoot, 'run elf');
  LElf := '';
  LExe := '';
  try
    TUtils.EnsureDirectory(LDir);
    LElf := DoCopyFixture(LDir, 'argv.elf', 'argv.elf');
    LExe := DoCopyFixture(LDir, 'argv.exe', 'argv.exe');
  except
    on E: Exception do
      Check(False, 'run_elf: folder made: %s', [E.Message]);
  end;
  Check((LElf <> '') and (LExe <> ''), 'run_elf: fixtures copied');
  if (LElf = '') or (LExe = '') then
    Exit;

  LRaised := DoRunElf(LElf, PC_UTT_RUN_ARGS, LDir, LExitCode, LOutput);
  Check((LRaised = '') and (LExitCode = 7),
    'run_elf: runs with arguments, exit 7 kept (%s, exit %d)', [LRaised, LExitCode]);
  Check(DoMissingRunArgv(LOutput) = '', 'run_elf: literal argv (missing %s)',
    [DoMissingRunArgv(LOutput)]);

  LRaised := DoCapture(True, LExe, PC_UTT_RUN_ARGS, LDir, LExitCode, LOutput);
  Check((LRaised = '') and (LExitCode = 7) and (DoMissingRunArgv(LOutput) = ''),
    'run_elf: argv.exe on Windows prints the same argv (%s, exit %d, missing %s)',
    [LRaised, LExitCode, DoMissingRunArgv(LOutput)]);

  LRaised := DoRunElf(LElf, PC_UTT_RUN_ARGS, LDir, LExitCode, LOutput, True);
  Check((LRaised = '') and (LExitCode = 7) and (DoMissingRunArgv(LOutput) = '') and
    not LOutput.Contains(#27),
    'run_elf: over pipes the literal argv, exit 7, no console rendering (%s, exit %d, missing %s)',
    [LRaised, LExitCode, DoMissingRunArgv(LOutput)]);

  LRaised := DoRunElf(LElf, '', LDir, LExitCode, LOutput);
  Check((LRaised = '') and (LExitCode = 0) and LOutput.Contains('argc=1'),
    'run_elf: runs with no arguments, exit 0 (%s, exit %d)', [LRaised, LExitCode]);

  LRaised := DoRunElf(TPath.Combine(LDir, 'missing.elf'), '', LDir, LExitCode, LOutput);
  Check(LRaised.Contains('chmod') and LRaised.Contains('missing.elf') and
    (LExitCode = 42),
    'run_elf: a chmod that fails raises with its reason, nothing run (%s, exit %d)',
    [LRaised, LExitCode]);

  LRaised := DoRunElf('\\srv\share\argv.elf', '', LDir, LExitCode, LOutput);
  Check(LRaised.Contains('WindowsPathToWSL') and (LExitCode = 42),
    'run_elf: a path with no WSL form raises (%s, exit %d)', [LRaised, LExitCode]);
end;

function DoRunPE(const AExe: string; const AParams: string; const AWorkDir: string;
  const AUsePipes: Boolean; out AExitCode: DWORD; out AOutput: string): string;
var
  LExitCode: DWORD;
  LOutput: string;
  LUsePipes: Boolean;
begin
  // '' or what TUtils.RunPE raised; the exit code it left (42 when it set
  // none) and everything the program printed
  LExitCode := 42;
  LOutput := '';
  LUsePipes := AUsePipes;
  Result := DoRaised(
    procedure
    begin
      TUtils.RunPE(AExe, AParams, AWorkDir, LExitCode, nil,
        procedure(const ALine: string; const AData: Pointer)
        begin
          LOutput := LOutput + ALine + #10;
        end, LUsePipes);
    end);
  AExitCode := LExitCode;
  AOutput := LOutput;
end;

procedure TPCUtilsTests.DoTestRunPE();
var
  LRoot: string;
  LDir: string;
  LExe: string;
  LOutput: string;
  LRaised: string;
  LExitCode: DWORD;
  LUsePipes: Boolean;
begin
  // argv.exe from a folder with a space through the pseudoconsole and over
  // pipes: literal argv, exit 7 kept; over pipes the program's own text (no
  // escape sequence); an empty or a missing program raises, exit untouched
  LRoot := DoScratchRoot();
  Check(LRoot <> '', 'run_pe: scratch folder ready');
  if LRoot = '' then
    Exit;
  LDir := TPath.Combine(LRoot, 'run pe');
  LExe := '';
  try
    TUtils.EnsureDirectory(LDir);
    LExe := DoCopyFixture(LDir, 'argv.exe', 'argv.exe');
  except
    on E: Exception do
      Check(False, 'run_pe: folder made: %s', [E.Message]);
  end;
  Check(LExe <> '', 'run_pe: fixture copied');
  if LExe = '' then
    Exit;

  for LUsePipes in [False, True] do
  begin
    LRaised := DoRunPE(LExe, PC_UTT_RUN_ARGS, LDir, LUsePipes, LExitCode, LOutput);
    Check((LRaised = '') and (LExitCode = 7) and (DoMissingRunArgv(LOutput) = ''),
      'run_pe: pipes %s: literal argv, exit 7 (%s, exit %d, missing %s)',
      [BoolToStr(LUsePipes, True), LRaised, LExitCode, DoMissingRunArgv(LOutput)]);
    if LUsePipes then
      Check(not LOutput.Contains(#27), 'run_pe: over pipes no console rendering');
  end;

  LRaised := DoRunPE('', '', LDir, True, LExitCode, LOutput);
  Check((LRaised <> '') and (LExitCode = 42), 'run_pe: an empty path raises (%s, exit %d)',
    [LRaised, LExitCode]);

  LRaised := DoRunPE(TPath.Combine(LDir, 'missing.exe'), '', LDir, True, LExitCode, LOutput);
  Check((LRaised <> '') and (LExitCode = 42), 'run_pe: a missing program raises (%s, exit %d)',
    [LRaised, LExitCode]);
end;

procedure TPCUtilsTests.DoTestCaptureLines();
const
  { PC_UTT_LINES_PARAMS }
  // cmd writes 'a' CR LF, an empty line (CR LF), 'b' CR LF, then 'c' with no
  // line end (set /p leaves errorlevel 1: exit 0 ends cmd clean)
  PC_UTT_LINES_PARAMS = '/d /c "echo a&echo.&echo b&<nul set /p =c&exit 0"';
var
  LKeep: Boolean;
  LExitCode: DWORD;
  LLines: string;
  LRaised: string;
  LWant: string;
begin
  // With AKeepEmptyLines every line arrives once (CR LF is one end, the
  // empty line kept, the last line without an end too); without it the
  // empty line is skipped as before
  for LKeep in [False, True] do
  begin
    LExitCode := 42;
    LLines := '';
    LRaised := '';
    try
      TUtils.CaptureConsoleOutput('', 'cmd.exe', PC_UTT_LINES_PARAMS, '', LExitCode, nil,
        procedure(const ALine: string; const AData: Pointer)
        begin
          LLines := LLines + '[' + ALine + ']';
        end, LKeep);
    except
      on E: Exception do
        LRaised := E.Message;
    end;
    if LKeep then
      LWant := '[a][][b][c]'
    else
      LWant := '[a][b][c]';
    Check((LRaised = '') and (LExitCode = 0) and (LLines = LWant),
      'capture_lines: keep empty lines %s gives %s (got %s, exit %d%s)',
      [BoolToStr(LKeep, True), LWant, LLines, LExitCode, LRaised]);
  end;
end;

procedure TPCUtilsTests.DoTestCaptureTick();
const
  { PC_UTT_TICK_PARAMS }
  // 'a', about 3 s with no output (ping waits 1 s between its 4 echoes,
  // its output discarded), then 'b'
  PC_UTT_TICK_PARAMS = '/d /c "echo a&ping -n 4 127.0.0.1 >nul&echo b&exit 0"';
  { PC_UTT_TICK_MS }
  PC_UTT_TICK_MS = 500;
var
  LExitCode: DWORD;
  LLines: string;
  LRaised: string;
  LTicks: Integer;
  LLastElapsed: UInt64;
  LOrdered: Boolean;
begin
  // A polled capture (ATickMs + ATick): the tick fires while the program is
  // silent, its elapsed time grows, and every line still arrives in order
  LExitCode := 42;
  LLines := '';
  LRaised := '';
  LTicks := 0;
  LLastElapsed := 0;
  LOrdered := True;
  try
    TUtils.CaptureConsoleOutput('', 'cmd.exe', PC_UTT_TICK_PARAMS, '', LExitCode, nil,
      procedure(const ALine: string; const AData: Pointer)
      begin
        LLines := LLines + '[' + ALine + ']';
      end, False, PC_UTT_TICK_MS,
      procedure(const AElapsedMs: UInt64; const AData: Pointer)
      begin
        Inc(LTicks);
        if AElapsedMs < LLastElapsed then
          LOrdered := False;
        LLastElapsed := AElapsedMs;
      end);
  except
    on E: Exception do
      LRaised := E.Message;
  end;

  // About 6 ticks in 3 s: at least 3 leaves room for a loaded machine
  Check((LRaised = '') and (LExitCode = 0) and (LLines = '[a][b]') and
    (LTicks >= 3) and LOrdered and (LLastElapsed >= 1500),
    'capture_tick: ticks while silent, lines kept (got %s, %d ticks, last %d ms, exit %d%s)',
    [LLines, LTicks, Int64(LLastElapsed), LExitCode, LRaised]);
end;

const
  { PC_UTT_WATCHDOG }
  // readline's argument: its watchdog (seconds). A run whose input never
  // ends exits 3 instead of hanging the testbed
  PC_UTT_WATCHDOG = '30';
  { PC_UTT_PIPE_WAIT_MS }
  // How long the pipe host test waits for the run to connect, or for its
  // pipe to move, before it fails
  PC_UTT_PIPE_WAIT_MS = 60000;

function DoKeyRecord(const AChar: WideChar; const ADown: Boolean;
  const ARepeat: Word): TInputRecord;
begin
  // One console key record, as the console's VT input mode delivers it
  Result := Default(TInputRecord);
  Result.EventType := KEY_EVENT;
  Result.Event.KeyEvent.bKeyDown := ADown;
  Result.Event.KeyEvent.wRepeatCount := ARepeat;
  Result.Event.KeyEvent.UnicodeChar := AChar;
end;

function DoFocusRecord(): TInputRecord;
begin
  // A record that is not a key (the window gained the focus)
  Result := Default(TInputRecord);
  Result.EventType := FOCUS_EVENT;
end;

function DoCodes(const AText: string): string;
var
  LIndex: Integer;
begin
  // AText as character codes ('#97#13'): control characters stay readable
  Result := '';
  for LIndex := 1 to Length(AText) do
    Result := Result + '#' + IntToStr(Ord(AText[LIndex]));
  if Result = '' then
    Result := '(none)';
end;

function DoBytes(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

function DoFrameBytes(const AKind: AnsiChar; const ALength: Cardinal;
  const APayload: TBytes): TBytes;
var
  LHead: TBytes;
begin
  // A frame head saying ALength (a row may make it disagree with APayload),
  // then APayload
  SetLength(LHead, PTY_FRAME_HEAD);
  LHead[0] := Byte(AKind);
  LHead[1] := Byte(ALength and $FF);
  LHead[2] := Byte((ALength shr 8) and $FF);
  LHead[3] := Byte((ALength shr 16) and $FF);
  LHead[4] := Byte((ALength shr 24) and $FF);
  Result := LHead + APayload;
end;

function DoSizeBytes(const ACols: Word; const ARows: Word): TBytes;
var
  LResult: TBytes;
begin
  // A resize payload: cols, rows as u16 little-endian
  SetLength(LResult, 4);
  LResult[0] := Byte(ACols and $FF);
  LResult[1] := Byte(ACols shr 8);
  LResult[2] := Byte(ARows and $FF);
  LResult[3] := Byte(ARows shr 8);
  Result := LResult;
end;

function DoFramesText(const AFrames: TArray<TPtyFrame>): string;
var
  LFrame: TPtyFrame;
begin
  // 'K:<keys>' / 'R:<cols>x<rows>' per frame, space separated
  Result := '';
  for LFrame in AFrames do
  begin
    if Result <> '' then
      Result := Result + ' ';
    if LFrame.Kind = PTY_FRAME_KEYS then
      Result := Result + 'K:' + TEncoding.UTF8.GetString(LFrame.Keys)
    else
      Result := Result + 'R:' + IntToStr(LFrame.Cols) + 'x' + IntToStr(LFrame.Rows);
  end;
end;

function DoInOrder(const AText: string; const AParts: array of string): Boolean;
var
  LIndex: Integer;
  LFrom: Integer;
  LAt: Integer;
begin
  // Every one of AParts in AText, in this order
  Result := True;
  LFrom := 1;
  for LIndex := 0 to High(AParts) do
  begin
    LAt := Pos(AParts[LIndex], AText, LFrom);
    if LAt = 0 then
      Exit(False);
    LFrom := LAt + Length(AParts[LIndex]);
  end;
end;

function DoCount(const AText: string; const APart: string): Integer;
var
  LAt: Integer;
begin
  // How often APart occurs in AText
  Result := 0;
  LAt := Pos(APart, AText);
  while LAt > 0 do
  begin
    Inc(Result);
    LAt := Pos(APart, AText, LAt + Length(APart));
  end;
end;

function DoShown(const AText: string): string;
begin
  // AText on one line for a message: escape, CR and LF spelled; at most 300
  Result := AText.Replace(#27, '\e').Replace(#13, '\r').Replace(#10, '\n');
  if Length(Result) > 300 then
    Result := Copy(Result, 1, 300) + '...';
end;

function DoSourcePipe(const AText: string; out ARead: THandle): Boolean;
var
  LWrite: THandle;
  LBytes: TBytes;
  LWritten: DWORD;
begin
  // A pipe holding AText (UTF-8) whose writer is gone: a redirected stdin
  // with an end. False (ARead 0) when it cannot be made
  ARead := 0;
  LWrite := 0;
  Result := False;
  if not CreatePipe(ARead, LWrite, nil, 0) then
  begin
    ARead := 0;
    Exit;
  end;
  try
    LBytes := DoBytes(AText);
    LWritten := 0;
    if Length(LBytes) = 0 then
      Result := True
    else
      Result := WriteFile(LWrite, LBytes[0], DWORD(Length(LBytes)), LWritten, nil) and
        (LWritten = DWORD(Length(LBytes)));
  finally
    CloseHandle(LWrite);
  end;
  if not Result then
  begin
    CloseHandle(ARead);
    ARead := 0;
  end;
end;

function DoRunHosted(const AProgram: string; const AElf: Boolean;
  const AWorkDir: string; const AHost: TPtyHost; out AExitCode: DWORD;
  out AOutput: string): string;
var
  LProgram: string;
  LElf: Boolean;
  LWorkDir: string;
  LHost: TPtyHost;
  LExitCode: DWORD;
  LOutput: string;
begin
  // '' or what RunPE (AElf False) / RunElf raised, run through the
  // pseudoconsole with AHost and readline's watchdog; the exit code (42
  // when none was set) and everything the program printed
  LProgram := AProgram;
  LElf := AElf;
  LWorkDir := AWorkDir;
  LHost := AHost;
  LExitCode := 42;
  LOutput := '';
  Result := DoRaised(
    procedure
    var
      LCallback: TCaptureConsoleCallback;
    begin
      LCallback :=
        procedure(const ALine: string; const AData: Pointer)
        begin
          LOutput := LOutput + ALine;
        end;
      if LElf then
        TUtils.RunElf(LProgram, PC_UTT_WATCHDOG, LWorkDir, LExitCode, nil, LCallback, False, LHost)
      else
        TUtils.RunPE(LProgram, PC_UTT_WATCHDOG, LWorkDir, LExitCode, nil, LCallback, False, LHost);
    end);
  AExitCode := LExitCode;
  AOutput := LOutput;
end;

function DoReadlineFixtures(const ADir: string; out APrograms: TArray<string>): Boolean;
var
  LPrograms: TArray<string>;
begin
  // readline.exe (index 0) and readline.elf (index 1) copied into ADir,
  // a folder with a space; False when either cannot be placed
  SetLength(LPrograms, 2);
  LPrograms[0] := '';
  LPrograms[1] := '';
  try
    TUtils.EnsureDirectory(ADir);
    LPrograms[0] := DoCopyFixture(ADir, 'readline.exe', 'readline.exe');
    LPrograms[1] := DoCopyFixture(ADir, 'readline.elf', 'readline.elf');
  except
    on Exception do
      LPrograms[0] := '';
  end;
  APrograms := LPrograms;
  Result := (LPrograms[0] <> '') and (LPrograms[1] <> '');
end;

function DoPipeWrite(const APipe: THandle; const AEvent: THandle;
  const ABytes: TBytes): Boolean;
var
  LOverlapped: TOverlapped;
  LWritten: DWORD;
begin
  // All of ABytes onto the overlapped pipe, waited for (at most
  // PC_UTT_PIPE_WAIT_MS)
  Result := Length(ABytes) = 0;
  if Result then
    Exit;
  LOverlapped := Default(TOverlapped);
  LOverlapped.hEvent := AEvent;
  LWritten := 0;
  if not WriteFile(APipe, ABytes[0], DWORD(Length(ABytes)), LWritten, @LOverlapped) then
  begin
    if GetLastError() <> ERROR_IO_PENDING then
      Exit;
    if WaitForSingleObject(AEvent, PC_UTT_PIPE_WAIT_MS) <> WAIT_OBJECT_0 then
    begin
      CancelIo(APipe);
      GetOverlappedResult(APipe, LOverlapped, LWritten, True);
      Exit;
    end;
  end;
  Result := GetOverlappedResult(APipe, LOverlapped, LWritten, False) and
    (LWritten = DWORD(Length(ABytes)));
end;

function DoPipeReadAll(const APipe: THandle; const AEvent: THandle;
  out ABytes: TBytes): Boolean;
var
  LOverlapped: TOverlapped;
  LChunk: array[0..4095] of Byte;
  LRead: DWORD;
  LResult: TBytes;
  LOld: Integer;
  LOk: Boolean;
begin
  // Everything the other end writes until it closes its end (True), or
  // until the pipe stays silent for PC_UTT_PIPE_WAIT_MS (False)
  Result := False;
  LResult := nil;
  repeat
    LOverlapped := Default(TOverlapped);
    LOverlapped.hEvent := AEvent;
    LRead := 0;
    LOk := ReadFile(APipe, LChunk[0], SizeOf(LChunk), LRead, @LOverlapped);
    if (not LOk) and (GetLastError() = ERROR_IO_PENDING) then
    begin
      if WaitForSingleObject(AEvent, PC_UTT_PIPE_WAIT_MS) <> WAIT_OBJECT_0 then
      begin
        CancelIo(APipe);
        GetOverlappedResult(APipe, LOverlapped, LRead, True);
        Break;
      end;
      LOk := GetOverlappedResult(APipe, LOverlapped, LRead, False);
    end;
    if not LOk then
    begin
      // The other end closed: everything is here
      Result := GetLastError() = ERROR_BROKEN_PIPE;
      Break;
    end;
    LOld := Length(LResult);
    SetLength(LResult, LOld + Integer(LRead));
    if LRead > 0 then
      Move(LChunk[0], LResult[LOld], LRead);
  until False;
  ABytes := LResult;
end;

procedure TPCUtilsTests.DoTestPtyKeyText();

  procedure DoRow(const ARow: string; const AGot: string; const AWant: string);
  begin
    Check(AGot = AWant, 'pty_key_text: %s (got %s, want %s)',
      [ARow, DoCodes(AGot), DoCodes(AWant)]);
  end;

begin
  // TPtyConsoleHost.KeyText: the characters of the key-down records among
  // the first ACount, each as often as it repeats; key-up records, records
  // that are not keys and #0 (a shift key alone) type nothing
  DoRow('a key down types it',
    TPtyConsoleHost.KeyText([DoKeyRecord('a', True, 1)], 1), 'a');
  DoRow('a key up types nothing',
    TPtyConsoleHost.KeyText([DoKeyRecord('a', False, 1)], 1), '');
  DoRow('a record that is not a key types nothing',
    TPtyConsoleHost.KeyText([DoFocusRecord()], 1), '');
  DoRow('a key with no character (shift) types nothing',
    TPtyConsoleHost.KeyText([DoKeyRecord(#0, True, 1)], 1), '');
  DoRow('Enter types CR',
    TPtyConsoleHost.KeyText([DoKeyRecord(#13, True, 1)], 1), #13);
  DoRow('a key held down types it as often as it repeats',
    TPtyConsoleHost.KeyText([DoKeyRecord('x', True, 3)], 1), 'xxx');
  DoRow('a repeat count of 0 types it once',
    TPtyConsoleHost.KeyText([DoKeyRecord('x', True, 0)], 1), 'x');
  DoRow('a surrogate pair over two records types both halves',
    TPtyConsoleHost.KeyText([DoKeyRecord(#$D83D, True, 1), DoKeyRecord(#$DE00, True, 1)], 2),
    #$D83D#$DE00);
  DoRow('an arrow in VT input mode types ESC [ A',
    TPtyConsoleHost.KeyText([DoKeyRecord(#27, True, 1), DoKeyRecord('[', True, 1),
      DoKeyRecord('A', True, 1)], 3), #27'[A');
  DoRow('only the first ACount records count',
    TPtyConsoleHost.KeyText([DoKeyRecord('a', True, 1), DoKeyRecord('b', True, 1)], 1), 'a');
  DoRow('an ACount past the records takes them all',
    TPtyConsoleHost.KeyText([DoKeyRecord('a', True, 1), DoKeyRecord('b', True, 1)], 5), 'ab');
  DoRow('an ACount of 0 types nothing',
    TPtyConsoleHost.KeyText([DoKeyRecord('a', True, 1)], 0), '');
  DoRow('key-up and other records between keys are skipped',
    TPtyConsoleHost.KeyText([DoKeyRecord('a', True, 1), DoKeyRecord('a', False, 1),
      DoFocusRecord(), DoKeyRecord('b', True, 1)], 4), 'ab');
end;

procedure TPCUtilsTests.DoTestPtyParseFrames();
var
  LAda: TBytes;
  LSize: TBytes;
  LPartial: TBytes;
  LUnknown: TBytes;
  LBadSize: TBytes;
  LTooLong: TBytes;
  LLongest: TBytes;

  procedure DoRow(const ARow: string; const AInput: TBytes; const AWantOk: Boolean;
    const AWantFrames: string; const AWantLeft: TBytes);
  var
    LBuffer: TBytes;
    LFrames: TArray<TPtyFrame>;
    LOk: Boolean;
    LGot: string;
  begin
    LBuffer := Copy(AInput);
    LFrames := nil;
    LOk := TPtyPipeHost.ParseFrames(LBuffer, LFrames);
    LGot := DoFramesText(LFrames);
    Check((LOk = AWantOk) and (LGot = AWantFrames) and DoSameBytes(LBuffer, AWantLeft),
      'pty_parse_frames: %s (got %s [%s] left %d, want %s [%s] left %d)',
      [ARow, BoolToStr(LOk, True), LGot, Length(LBuffer), BoolToStr(AWantOk, True),
      AWantFrames, Length(AWantLeft)]);
  end;

begin
  // TPtyPipeHost.ParseFrames takes the complete frames off the front; a
  // frame not complete yet stays in the buffer; a stream that cannot be
  // frames (unknown kind, a resize that is not 4 bytes, a length past
  // PTY_FRAME_MAX) is False with the frames before it, the rest left
  LAda := DoFrameBytes(PTY_FRAME_KEYS, 3, DoBytes('Ada'));
  LSize := DoFrameBytes(PTY_FRAME_RESIZE, 4, DoSizeBytes(120, 30));
  LPartial := Copy(DoFrameBytes(PTY_FRAME_KEYS, 3, DoBytes('Bob')), 0, 6);
  LUnknown := DoFrameBytes('X', 0, nil);
  LBadSize := DoFrameBytes(PTY_FRAME_RESIZE, 3, DoBytes('abc'));
  LTooLong := DoFrameBytes(PTY_FRAME_KEYS, PTY_FRAME_MAX + 1, nil);
  LLongest := DoFrameBytes(PTY_FRAME_KEYS, PTY_FRAME_MAX, nil);

  DoRow('one keys frame', LAda, True, 'K:Ada', nil);
  DoRow('one resize frame', LSize, True, 'R:120x30', nil);
  DoRow('a part of a head waits', Copy(LAda, 0, 3), True, '', Copy(LAda, 0, 3));
  DoRow('a part of a payload waits', Copy(LAda, 0, 7), True, '', Copy(LAda, 0, 7));
  DoRow('two frames and the start of a third', LAda + LSize + LPartial, True,
    'K:Ada R:120x30', LPartial);
  DoRow('an unknown kind breaks the stream after the frames before it',
    LAda + LUnknown, False, 'K:Ada', LUnknown);
  DoRow('a resize of 3 bytes breaks the stream', LBadSize, False, '', LBadSize);
  DoRow('a length past PTY_FRAME_MAX breaks the stream', LTooLong, False, '', LTooLong);
  DoRow('a length of PTY_FRAME_MAX waits for its payload', LLongest, True, '', LLongest);
  DoRow('an empty keys frame', DoFrameBytes(PTY_FRAME_KEYS, 0, nil), True, 'K:', nil);
  DoRow('an empty buffer', nil, True, '', nil);
  DoRow('a resize uses both bytes of each side',
    DoFrameBytes(PTY_FRAME_RESIZE, 4, DoSizeBytes(65535, 258)), True, 'R:65535x258', nil);
end;

procedure TPCUtilsTests.DoTestPtyStreamHost();
var
  LRoot: string;
  LDir: string;
  LPrograms: TArray<string>;
  LElf: Boolean;
  LUseElf: Boolean;
  LTarget: string;

  procedure DoRow(const ARow: string; const AHosted: Boolean; const AInput: string;
    const AWant: array of string; const AHellos: Integer);
  var
    LRead: THandle;
    LHost: TPtyStreamHost;
    LRaised: string;
    LOutput: string;
    LExitCode: DWORD;
  begin
    LHost := nil;
    LRead := 0;
    if AHosted then
    begin
      if not DoSourcePipe(AInput, LRead) then
      begin
        Check(False, 'pty_stream_host: %s: %s: source pipe made', [LTarget, ARow]);
        Exit;
      end;
      LHost := TPtyStreamHost.Create();
      LHost.Init(LRead);
    end;
    try
      LRaised := DoRunHosted(LPrograms[Ord(LUseElf)], LUseElf, LDir, LHost, LExitCode, LOutput);
    finally
      LHost.Free();
      if LRead <> 0 then
        CloseHandle(LRead);
    end;
    Check((LRaised = '') and (LExitCode = 0) and DoInOrder(LOutput, AWant) and
      (DoCount(LOutput, 'hello ') = AHellos),
      'pty_stream_host: %s: %s (raised %s, exit %d, output %s)',
      [LTarget, ARow, LRaised, LExitCode, DoShown(LOutput)]);
  end;

begin
  // A run through the pseudoconsole reads a redirected stdin
  // (TPtyStreamHost) as its own: every line arrives and the program sees
  // the end ("end", exit 0, never the watchdog's 3); an empty one ends at
  // once; with no host the program reads NUL, an end at once (the
  // pseudoconsole's input never ends: such a program waited forever).
  // readline.exe through RunPE, readline.elf through RunElf (WSL)
  LRoot := DoScratchRoot();
  Check(LRoot <> '', 'pty_stream_host: scratch folder ready');
  if LRoot = '' then
    Exit;
  LDir := TPath.Combine(LRoot, 'pty stream');
  Check(DoReadlineFixtures(LDir, LPrograms), 'pty_stream_host: fixtures copied');
  if (Length(LPrograms) < 2) or (LPrograms[0] = '') or (LPrograms[1] = '') then
    Exit;

  for LElf in [False, True] do
  begin
    LUseElf := LElf;
    if LUseElf then
      LTarget := 'linux'
    else
      LTarget := 'windows';
    DoRow('every line of a redirected stdin arrives, then its end', True,
      'Ada'#13#10'Bob'#13#10, ['hello Ada', 'hello Bob', 'end'], 2);
    DoRow('an empty redirected stdin ends at once', True, '', ['end'], 0);
    DoRow('no host: NUL, the input ends at once', False, '', ['end'], 0);
  end;
end;

procedure TPCUtilsTests.DoTestPtyPipeHost();
var
  LRoot: string;
  LDir: string;
  LPrograms: TArray<string>;
  LElf: Boolean;
  LUseElf: Boolean;
  LTarget: string;
  LProgram: string;
  LName: string;
  LServer: THandle;
  LEvent: THandle;
  LOverlapped: TOverlapped;
  LHost: TPtyPipeHost;
  LThread: TThread;
  LRaised: string;
  LExitCode: DWORD;
  LConnected: Boolean;
  LError: DWORD;
  LDone: DWORD;
  LEndKey: string;
  LWrote: Boolean;
  LDrained: Boolean;
  LBytes: TBytes;
  LOutput: string;
begin
  // A run hosted by an app's named pipe (TPtyPipeHost, the editor's
  // TERMINAL): the test is the app. A resize frame and a keys frame go in,
  // then the terminal's end-of-input key (Ctrl+Z Enter on Windows, Ctrl+D
  // on Linux); the program's output comes out on the pipe (WriteOutput, as
  // the CLI's --terminal) until the host closes it: "hello Ada", "end",
  // exit 0 (the watchdog's 3 = keys or the end did not arrive)
  LRoot := DoScratchRoot();
  Check(LRoot <> '', 'pty_pipe_host: scratch folder ready');
  if LRoot = '' then
    Exit;
  LDir := TPath.Combine(LRoot, 'pty pipe');
  Check(DoReadlineFixtures(LDir, LPrograms), 'pty_pipe_host: fixtures copied');
  if (Length(LPrograms) < 2) or (LPrograms[0] = '') or (LPrograms[1] = '') then
    Exit;

  for LElf in [False, True] do
  begin
    LUseElf := LElf;
    if LUseElf then
    begin
      LTarget := 'linux';
      LEndKey := #4;
    end
    else
    begin
      LTarget := 'windows';
      LEndKey := #26#13;
    end;
    LProgram := LPrograms[Ord(LUseElf)];

    LName := '\\.\pipe\pcpp-utt-' + IntToStr(GetCurrentProcessId()) + '-' +
      IntToStr(GetTickCount64());
    LServer := CreateNamedPipe(PChar(LName), PIPE_ACCESS_DUPLEX or FILE_FLAG_OVERLAPPED,
      PIPE_TYPE_BYTE or PIPE_READMODE_BYTE or PIPE_WAIT, 1, 65536, 65536, 0, nil);
    Check(LServer <> INVALID_HANDLE_VALUE, 'pty_pipe_host: %s: pipe made (%s)',
      [LTarget, SysErrorMessage(GetLastError())]);
    if LServer = INVALID_HANDLE_VALUE then
      Continue;
    LEvent := CreateEvent(nil, True, False, nil);
    try
      LRaised := '';
      LExitCode := 42;
      LWrote := False;
      LDrained := False;
      LBytes := nil;
      LHost := TPtyPipeHost.Create();
      LHost.Init(LName);
      // The run and the host live on their own thread; freeing the host
      // closes its pipe, which ends the read below
      LThread := TThread.CreateAnonymousThread(
        procedure
        begin
          LRaised := DoRaised(
            procedure
            var
              LCallback: TCaptureConsoleCallback;
            begin
              LCallback :=
                procedure(const ALine: string; const AData: Pointer)
                begin
                  LHost.WriteOutput(ALine);
                end;
              if LUseElf then
                TUtils.RunElf(LProgram, PC_UTT_WATCHDOG, LDir, LExitCode, nil, LCallback,
                  False, LHost)
              else
                TUtils.RunPE(LProgram, PC_UTT_WATCHDOG, LDir, LExitCode, nil, LCallback,
                  False, LHost);
            end);
          LHost.Free();
        end);
      LThread.FreeOnTerminate := False;
      LThread.Start();
      try
        // The host connects as the run starts (TPtyPipeHost.DoStart)
        LOverlapped := Default(TOverlapped);
        LOverlapped.hEvent := LEvent;
        LDone := 0;
        LConnected := ConnectNamedPipe(LServer, @LOverlapped);
        if not LConnected then
        begin
          LError := GetLastError();
          if LError = ERROR_PIPE_CONNECTED then
            LConnected := True
          else if LError = ERROR_IO_PENDING then
          begin
            LConnected := (WaitForSingleObject(LEvent, PC_UTT_PIPE_WAIT_MS) = WAIT_OBJECT_0) and
              GetOverlappedResult(LServer, LOverlapped, LDone, False);
            if not LConnected then
            begin
              CancelIo(LServer);
              GetOverlappedResult(LServer, LOverlapped, LDone, True);
            end;
          end;
        end;

        if LConnected then
        begin
          LWrote := DoPipeWrite(LServer, LEvent,
              DoFrameBytes(PTY_FRAME_RESIZE, 4, DoSizeBytes(100, 40))) and
            DoPipeWrite(LServer, LEvent,
              DoFrameBytes(PTY_FRAME_KEYS, Length(DoBytes('Ada'#13)), DoBytes('Ada'#13))) and
            DoPipeWrite(LServer, LEvent,
              DoFrameBytes(PTY_FRAME_KEYS, Length(DoBytes(LEndKey)), DoBytes(LEndKey)));
          LDrained := DoPipeReadAll(LServer, LEvent, LBytes);
        end;
      finally
        LThread.WaitFor();
        LThread.Free();
      end;
    finally
      CloseHandle(LEvent);
      CloseHandle(LServer);
    end;

    LOutput := TEncoding.UTF8.GetString(LBytes);
    Check(LConnected, 'pty_pipe_host: %s: the run connects to the app''s pipe (raised %s)',
      [LTarget, LRaised]);
    Check((LRaised = '') and (LExitCode = 0) and LWrote and LDrained and
      DoInOrder(LOutput, ['hello Ada', 'end']) and (DoCount(LOutput, 'hello ') = 1),
      'pty_pipe_host: %s: keys in, output out, the end key ends the input ' +
      '(raised %s, exit %d, wrote %s, drained %s, output %s)',
      [LTarget, LRaised, LExitCode, BoolToStr(LWrote, True), BoolToStr(LDrained, True),
      DoShown(LOutput)]);
  end;
end;

end.
