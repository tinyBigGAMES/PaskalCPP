{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  SPDX-License-Identifier: MPL-2.0

  This Source Code Form is subject to the terms of the
  Mozilla Public License, v. 2.0. If a copy of the MPL
  was not distributed with this file, You can obtain one
  at https://mozilla.org/MPL/2.0/.

 -------------------------------------------------------------------------------

  StdApp.Utils - General-purpose utility routines

  Static utility class covering string encoding (UTF-8, ANSI), process
  launching with output capture, PE validation, version info extraction,
  resource manipulation (icons, manifests, version, RCDATA), file
  encoding detection, path helpers, environment variables, and line
  counting. Also provides raw pointer array types for typed memory access.

  Key types:
  - TUtils: Static class -- AsUTF8, RunPE, RunElf, CaptureConsoleOutput,
    CaptureConsolePTY (a program path of any length: PATH_LAUNCH_MAX),
    GetVersionInfo, UpdateIconResource, UpdateVersionInfoResource,
    IsValidWin64PE, GetFileSHA256, GetRelativePath, GetAppType, and more
  - TCommandBuilder: Fluent command-line argument builder
  - TVersionInfo: Record holding parsed PE version resource fields
  - TAppType: Console/GUI/Unknown application type enum
  - Raw pointer array types: PInt8Array..PDoubleArray for typed access

  Dependencies: StdApp.Base, StdApp.Resources
  Notes: InitConsole() enables Windows Virtual Terminal Processing for
    ANSI escape sequences. Called automatically on first console output.
===============================================================================}

unit StdApp.Utils;

{$I StdApp.Defines.inc}

interface

uses
  WinAPI.Windows,
  WinAPI.ShellAPI,
  System.SysUtils,
  System.IOUtils,
  System.AnsiStrings,
  System.Classes,
  System.Generics.Collections,
  System.Math,
  System.Hash,
  StdApp.Base,
  StdApp.Resources;

const

  { PATH_PREFIX_PROCESS }
  // Resolve the remainder against the running process directory.
  PATH_PREFIX_PROCESS = '$P:';

  { PATH_PREFIX_CURRENT }
  // Resolve the remainder against the current working directory.
  PATH_PREFIX_CURRENT = '$D:';

  { PATH_PREFIX_SOURCE }
  // Resolve the remainder against the caller-supplied contextual base.
  // This is the explicit spelling of the default behavior.
  PATH_PREFIX_SOURCE = '$S:';

  { PATH_LONG_PREFIX }
  // The Win32 long-path spelling: \\?\C:\... is passed to the OS without the
  // MAX_PATH limit. Backslashes only: //?/ is not honoured (probed, R28).
  PATH_LONG_PREFIX = '\\?\';

  { PATH_LONG_UNC_PREFIX }
  // The long-path spelling of a UNC path: \\server\share -> \\?\UNC\server\share
  PATH_LONG_UNC_PREFIX = '\\?\UNC\';

  { PATH_PLAIN_MAX }
  // The longest path every Win32 file routine takes in its plain spelling:
  // CreateDirectory refuses 248 characters and more, a file stops at 259
  // (probed, scripts\zb_e\a2\probe1.txt). ResolvePath returns a longer path
  // in the long-path spelling.
  PATH_PLAIN_MAX = 247;

  { PATH_RESOURCE_MAX }
  // The longest path the Win32 resource-update routines (BeginUpdateResource)
  // take, as spelled: the long-path prefix counts and does not lift the limit
  // (error 122 past it; probed, scripts\zb_e\a2c\probe2.txt). The resource
  // routines stamp a longer path through a temp copy (DoUpdateResources).
  PATH_RESOURCE_MAX = 259;

  { PATH_LAUNCH_MAX }
  // The longest program path CreateProcess finds from the command line
  // alone: error 206 past it. Named as the application in the long-path
  // spelling, a program launches at any length (probed,
  // scripts\zb_e\a5\probe1.txt); the capture routines name it so past this.
  PATH_LAUNCH_MAX = 259;

  { PTY_FRAME_KEYS }
  // TPtyPipeHost frames: keys typed in the host app's terminal (UTF-8)
  PTY_FRAME_KEYS = 'K';
  { PTY_FRAME_RESIZE }
  // TPtyPipeHost frames: the terminal's new size (cols, rows: u16 LE each)
  PTY_FRAME_RESIZE = 'R';
  { PTY_FRAME_HEAD }
  // A frame's head: its kind (1 byte) and its payload's length (u32 LE)
  PTY_FRAME_HEAD = 5;
  { PTY_FRAME_MAX }
  // The longest payload taken: a longer length is a broken stream
  PTY_FRAME_MAX = 1048576;
  { PTY_SIDE_MAX }
  // A pseudoconsole's size is a COORD: SmallInt per side
  PTY_SIDE_MAX = 32767;
  { PTY_READ_CHUNK }
  // What a host's thread reads at once (bytes or console records)
  PTY_READ_CHUNK = 4096;

  { RESOURCE_UPDATE_ATTEMPTS }
  // A file just written is often held for a moment (a virus scanner reading
  // a new executable): EndUpdateResource then fails with "access denied"
  // about once in a hundred stamps under build load and succeeds 25 ms later
  // (probed, scripts\zb_e\a2c\probe3b.txt). A resource update that Windows
  // reports busy is tried this many times, RESOURCE_UPDATE_RETRY_MS apart.
  RESOURCE_UPDATE_ATTEMPTS = 20;

  { RESOURCE_UPDATE_RETRY_MS }
  RESOURCE_UPDATE_RETRY_MS = 50;

type

  { Raw Pointer Array Helpers }
  PInt8Array   = ^TInt8Array;
  TInt8Array   = array[0..MaxInt div SizeOf(Int8) - 1]   of Int8;

  PUInt8Array  = ^TUInt8Array;
  TUInt8Array  = array[0..MaxInt div SizeOf(UInt8) - 1]  of UInt8;

  PInt16Array  = ^TInt16Array;
  TInt16Array  = array[0..MaxInt div SizeOf(Int16) - 1]  of Int16;

  PUInt16Array = ^TUInt16Array;
  TUInt16Array = array[0..MaxInt div SizeOf(UInt16) - 1] of UInt16;

  PInt32Array  = ^TInt32Array;
  TInt32Array  = array[0..MaxInt div SizeOf(Int32) - 1]  of Int32;

  PUInt32Array = ^TUInt32Array;
  TUInt32Array = array[0..MaxInt div SizeOf(UInt32) - 1] of UInt32;

  PInt64Array  = ^TInt64Array;
  TInt64Array  = array[0..MaxInt div SizeOf(Int64) - 1]  of Int64;

  PUInt64Array = ^TUInt64Array;
  TUInt64Array = array[0..MaxInt div SizeOf(UInt64) - 1] of UInt64;

  PSingleArray = ^TSingleArray;
  TSingleArray = array[0..MaxInt div SizeOf(Single) - 1] of Single;

  PDoubleArray = ^TDoubleArray;
  TDoubleArray = array[0..MaxInt div SizeOf(Double) - 1] of Double;

  { TCaptureConsoleCallback }
  TCaptureConsoleCallback = reference to procedure(const ALine: string; const AUserData: Pointer);

  { TCaptureConsoleTick }
  // Called while a captured program writes nothing, every tick interval:
  // AElapsedMs = time since the program started
  TCaptureConsoleTick = reference to procedure(const AElapsedMs: UInt64; const AUserData: Pointer);

  { TOutputCallback }
  TOutputCallback = reference to procedure(const AText: string; const AUserData: Pointer);

  { TVersionInfo }
  TVersionInfo = record
    Major: Word;
    Minor: Word;
    Patch: Word;
    Build: Word;
    VersionString: string;
    ProductName: string;
    CompanyName: string;
    Copyright: string;
    Description: string;
    URL: string;
  end;

  { TAppType }
  TAppType = (
    atUnknown,
    atConsole,
    atGUI
  );

  { TPtyFrame }
  // One message from a TPtyPipeHost's host app (TPtyPipeHost.ParseFrames)
  TPtyFrame = record
    Kind: AnsiChar;     // PTY_FRAME_KEYS or PTY_FRAME_RESIZE
    Keys: TBytes;       // PTY_FRAME_KEYS: UTF-8, as a terminal spells them (Enter = #13)
    Cols: Word;         // PTY_FRAME_RESIZE
    Rows: Word;
  end;

  { TPtyHost }
  // The other end of a run's pseudoconsole (TUtils.CaptureConsolePTY): where
  // the program's keyboard and terminal size come from while it runs. Start
  // is called before the program starts (AInput: the pseudoconsole's input,
  // written as UTF-8; AConsole: the pseudoconsole, an HPCON, to resize it),
  // Stop once it ended; each host feeds them from a thread of its own.
  // Construction parameters go through each host's Init
  TPtyHost = class(TBaseObject)
  private
    FStarted: Boolean;
  protected
    FInput: THandle;
    FConsole: THandle;
    // Every byte of ABytes into the program's terminal. False = it is gone
    function DoWriteKeys(const ABytes: TBytes): Boolean;
    // The terminal's new size (each side clamped to 1..32767)
    function DoResize(const ACols: Integer; const ARows: Integer): Boolean;
    procedure DoStart(); virtual; abstract;
    procedure DoStop(); virtual; abstract;
  public
    // A host still running is stopped first
    destructor Destroy(); override;
    // The size the pseudoconsole starts with; False = the caller's own
    function InitialSize(out ASize: COORD): Boolean; virtual;
    // What the program reads as its standard input: 0 = the pseudoconsole
    // (keys this host writes, a terminal's end of input); a handle = that
    // handle itself, so its end is the program's end of input, as
    // 'prog < file' in a shell. Read before Start
    function StdInput(): THandle; virtual;
    // Raises when the host cannot serve (the run then does not start)
    procedure Start(const AInput: THandle; const AConsole: THandle);
    // Waits for the host's thread; a second call does nothing
    procedure Stop();
  end;

  { TPtyConsoleHost }
  // The console the parent runs in: its keys go raw to the program (the
  // console's input in VT mode: no line editing, no echo, Ctrl+C is the
  // program's), its window size follows; the console's mode comes back at
  // Stop
  TPtyConsoleHost = class(TPtyHost)
  private
    FConsoleInput: THandle;
    FConsoleOutput: THandle;
    FSavedMode: DWORD;
    FModeSet: Boolean;
    FStopEvent: THandle;
    FThread: TThread;
    procedure DoRun();
    function DoWindowSize(out ASize: COORD): Boolean;
  protected
    procedure DoStart(); override;
    procedure DoStop(); override;
  public
    procedure Init(const AConsoleInput: THandle; const AConsoleOutput: THandle);
    // The text the key-down records among the first ACount of AEvents type
    // (each as often as it repeats); other records type nothing
    class function KeyText(const AEvents: array of TInputRecord; const ACount: Integer): string; static;
    function InitialSize(out ASize: COORD): Boolean; override;
  end;

  { TPtyStreamHost }
  // A redirected standard input (a file, a pipe): the program reads it
  // itself (StdInput), so it sees the input end where the source ends, as
  // 'prog < file' in a shell; its output still goes through the
  // pseudoconsole. No thread: nothing to forward
  TPtyStreamHost = class(TPtyHost)
  private
    FSource: THandle;
  protected
    procedure DoStart(); override;
    procedure DoStop(); override;
  public
    // ASource: not owned; open until the run ended
    procedure Init(const ASource: THandle);
    function StdInput(): THandle; override;
  end;

  { TPtyPipeHost }
  // A named pipe the host app (an editor's terminal pane) listens on: the
  // program's output goes to it raw (WriteOutput), keys and sizes come back
  // as frames: a kind byte (PTY_FRAME_KEYS / PTY_FRAME_RESIZE), the payload's
  // length (u32, little-endian), the payload (keys: UTF-8; resize: cols, rows
  // as u16 little-endian). Overlapped: a write never waits on the read
  TPtyPipeHost = class(TPtyHost)
  private
    FPipeName: string;
    FPipe: THandle;
    FStopEvent: THandle;
    FReadEvent: THandle;
    FWriteEvent: THandle;
    FThread: TThread;
    procedure DoRun();
    procedure DoApply(const AFrames: TArray<TPtyFrame>);
  protected
    procedure DoStart(); override;
    procedure DoStop(); override;
  public
    destructor Destroy(); override;
    // APipeName: the full name (\\.\pipe\...)
    procedure Init(const APipeName: string);
    // Takes the complete frames off the front of ABuffer (what is left: a
    // frame not complete yet). False = the stream is broken (an unknown
    // kind, a resize that is not 4 bytes, a length past PTY_FRAME_MAX);
    // AFrames holds the frames before it
    class function ParseFrames(var ABuffer: TBytes; out AFrames: TArray<TPtyFrame>): Boolean; static;
    // The program's output (UTF-8). False = not connected, or the host app is gone
    function WriteOutput(const AText: string): Boolean;
  end;

  { TUtils }
  TUtils = class
  private class var
    FMarshaller: TMarshaller;
  private
    class function  EnableVirtualTerminalProcessing(): Boolean; static;
    class procedure InitConsole(); static;

  public
    // The application name CreateProcess needs for AProgram: '' when the
    // command line alone finds it (a bare name searched on PATH, or a path of
    // at most PATH_LAUNCH_MAX), else its long-path spelling. Every caller of
    // CreateProcess that names a program uses it (the capture routines, the
    // debugger)
    class function  LaunchName(const AProgram: string): string; static;
    class procedure FailIf(const Cond: Boolean; const Msg: string; const AArgs: array of const);

    class function  GetTickCount(): DWORD; static;
    class function  GetTickCount64(): UInt64; static;

    class function  AsUTF8(const AValue: string; ALength: PCardinal = nil): Pointer; static;
    class function  ToAnsi(const AValue: string): AnsiString; static;
    class function  FromUtf8(const APtr: PAnsiChar): string; static;

    class procedure ProcessMessages(); static;

    class function  RunPE(const AExe, AParams, AWorkDir: string; const AWait: Boolean = True; const AShowCmd: Word = SW_SHOWNORMAL): Cardinal; overload; static;
    // Runs a Windows program with its output to ACallback, the twin of
    // RunElf: through a pseudoconsole as CaptureConsolePTY, or with AUsePipes
    // over pipes as CaptureConsoleOutput with every line kept (the program's
    // text as written, stdout and stderr in the order written, no console
    // rendering). Raises when the program cannot start. AHost: the
    // pseudoconsole's keyboard and size (CaptureConsolePTY; nil = none); with
    // AUsePipes only its StdInput is used, as the program's stdin (0 = NUL)
    class procedure RunPE(const AExe: string; const AParams: string; const AWorkDir: string; var AExitCode: DWORD; const AUserData: Pointer; const ACallback: TCaptureConsoleCallback; const AUsePipes: Boolean = False; const AHost: TPtyHost = nil); overload; static;
    // Runs a Linux ELF through WSL (wsl.exe -e; AParams are split by the
    // Windows argv rule into the program's own argv, never parsed by a
    // shell), its output through a pseudoconsole as CaptureConsolePTY, or
    // with AUsePipes over pipes as CaptureConsoleOutput with every line kept
    // (the program's text as written, stdout and stderr merged in Linux in
    // the order written, no console rendering). Raises when the path has no
    // WSL form, chmod fails (its output in the message) or wsl cannot start.
    // AHost as RunPE
    class procedure RunElf(const AElf: string; const AParams: string; const AWorkDir: string; var AExitCode: DWORD; const AUserData: Pointer; const ACallback: TCaptureConsoleCallback; const AUsePipes: Boolean = False; const AHost: TPtyHost = nil); static;
    class function  ShellOpen(const AFilename: string; const AWorkDir: string = ''; const AShowCmd: Word = SW_SHOWNORMAL): Boolean; static;
    class function  WindowsPathToWSL(const APath: string): string; static;
    // Runs ACommand with stdout and stderr on one pipe; ACallback gets each
    // line in the order written. Empty lines are skipped unless
    // AKeepEmptyLines: then CR+LF is one terminator and every line arrives,
    // empty ones included (a final line without a terminator too)
    // ATickMs > 0 with ATick: the pipe is polled instead of a blocking read,
    // and ATick is called every ATickMs while the program writes nothing
    // (a heartbeat for a long silent run); otherwise the read blocks.
    // AStdin (0 = none: the child reads NUL): the child's standard input, a
    // handle the caller keeps open until the call returns (duplicated
    // inheritable for the child; RunPE / RunElf pass AHost.StdInput())
    class procedure CaptureConsoleOutput(const ATitle: string; const ACommand: PChar; const AParameters: PChar; const AWorkDir: string; var AExitCode: DWORD; const AUserData: Pointer; const ACallback: TCaptureConsoleCallback; const AKeepEmptyLines: Boolean = False; const ATickMs: Cardinal = 0; const ATick: TCaptureConsoleTick = nil; const AStdin: THandle = 0); static;
    // Runs ACommand on a pseudoconsole; its output (VT kept) to ACallback as
    // it arrives, to the very end: the pseudoconsole is closed after the exit
    // and read until its pipe breaks. AHost (nil = none) feeds the program's
    // keyboard and terminal size from Start (before the program starts) to
    // Stop (after it ended); a host that cannot start stops the run (raises)
    class procedure CaptureConsolePTY(const ACommand: PChar; const AParameters: PChar; const AWorkDir: string; var AExitCode: DWORD; const AUserData: Pointer; const ACallback: TCaptureConsoleCallback; const AHost: TPtyHost = nil); static;
    class function  CreateProcessWithPipes(const AExe, AParams, AWorkDir: string; out AStdinWrite: THandle; out AStdoutRead: THandle; out AProcessHandle: THandle; out AThreadHandle: THandle): Boolean; static;

    // Creates the directory AFilename sits in (AFilename names a file)
    class function  CreateDirInPath(const AFilename: string): Boolean;
    // Creates ADirectory itself, with any missing parents
    class function  EnsureDirectory(const ADirectory: string): Boolean; static;
    class function  GetVersionInfo(out AVersionInfo: TVersionInfo; const AFilePath: string = ''): Boolean; static;
    class function  GetModuleVersionString(const AModule: HMODULE): string; static;

    class procedure CopyFilePreservingEncoding(const ASourceFile, ADestFile: string); static;
    class function  DetectFileEncoding(const AFilePath: string): TEncoding; static;
    class function  EnsureBOM(const AText: string): string; static;
    class function  EscapeString(const AText: string): string; static;
    class function  StripAnsi(const AText: string): string; static;
    class function  ExtractAnsiCodes(const AText: string): string; static;

    class function  IsValidWin64PE(const AFilePath: string): Boolean; static;
    class procedure UpdateIconResource(const AExeFilePath, AIconFilePath: string); static;
    class procedure UpdateVersionInfoResource(const APEFilePath: string; const AMajor, AMinor, APatch: Word; const AProductName, ADescription, AFilename, ACompanyName, ACopyright: string; const AURL: string = ''); static;
    class function  ResourceExist(const AResName: string): Boolean; static;
    class function  AddResManifestFromResource(const AResName: string; const AModuleFile: string; const ALanguage: Integer = 1033): Boolean; overload; static;
    // Same, and AErrorMessage says why when it returns False (OS reason included)
    class function  AddResManifestFromResource(const AResName: string; const AModuleFile: string; out AErrorMessage: string; const ALanguage: Integer = 1033): Boolean; overload; static;
    class procedure UpdateRCDataResource(const AExeFilePath: string; const AResourceName: string; const AData: TStream); static;

    class function  GetFileSHA256(const APath: string): string; static;
    class function  GetRelativePath(const ABasePath, AFullPath: string): string; static;
    class function  NormalizePath(const APath: string): string; static;
    // The path without the long-path prefix, backslashes (\\?\C:\x -> C:\x,
    // \\?\UNC\srv\share\x -> \\srv\share\x); any other path unchanged
    class function  StripLongPathPrefix(const APath: string): string; static;
    // One path in two spellings (long-path prefix or not, either slash, a
    // trailing delimiter) is the same path; Windows paths compare without case
    class function  SamePath(const APath1: string; const APath2: string): Boolean; static;
    // AFilename exists and its on-disk name has exactly the case of
    // AFilename's name part (the folders are not compared). Windows finds a
    // file whatever the case asked; a case-sensitive lookup (a module name)
    // needs this so it resolves as on Linux. Never raises
    class function  FileExistsExactCase(const AFilename: string): Boolean; static;
    // A file that exists under AFilename's name in another case gets exactly
    // that name (a case-only rename; writing over it keeps the old case on a
    // case-blind file system). True = no such file, or renamed; False = the
    // rename failed, AError = the OS's reason. Never raises
    class function  MatchFileNameCase(const AFilename: string; out AError: string): Boolean; static;
    // A name or a relative path (no '.' or '..' segment, no drive or root)
    // under a directory ResolvePath returned, joined as text: no file system
    // access and no exception. ResolvePath's spelling (the long-path spelling
    // past PATH_PLAIN_MAX): equal to ResolvePath(ARelPath, AResolvedDir)
    class function  JoinResolvedPath(const AResolvedDir: string; const ARelPath: string): string; static;
    // One argument of a Windows command line (CreateProcess), quoted only when
    // it must be, by the rule the C runtime and LLVM split argv with:
    // backslashes are literal except before a '"' (R49)
    class function  QuoteCommandArg(const AArg: string): string; static;
    // The text of a command line after argument AIndex (ParamStr's numbering:
    // 0 = the program), as written: found with ParamStr's own scan (System.pas
    // GetParamStr: blanks and "" pairs before an argument skipped, '"' toggles
    // a quoted run), leading blanks of the tail dropped; '' when there are not
    // that many arguments. Program arguments are forwarded raw (pcpp -- args)
    class function  CommandLineTail(const ACommandLine: string; const AIndex: Integer): string; static;
    class function  DisplayPath(const APath: string): string; static;

    class function  GetEnv(const AName: string): string; static;
    class procedure SetEnv(const AName: string; const AValue: string); static;
    class function  HasEnv(const AName: string): Boolean; static;
    class procedure AddToEnvPath(const APath: string); static;
    class function  RunFromIDE(): Boolean; static;
    class function  CountLines(const APath, APattern: string; const ARecursive: Boolean = True): Int64; static;
    class function  GetAppType(): TAppType; static;
    class function  ResolvePath(const APath: string;
      const ABaseDir: string = ''): string; static;
    class procedure CopyDirectory(const ASrcDir: string;
      const ADestDir: string); static;

  end;

  { TCommandBuilder }
  TCommandBuilder = class(TBaseObject)
  private
    FParams: TStringList;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    procedure Clear();
    procedure AddParam(const AParam: string); overload;
    procedure AddParam(const AFlag, AValue: string); overload;
    procedure AddQuotedParam(const AFlag, AValue: string); overload;
    procedure AddQuotedParam(const AValue: string); overload;
    procedure AddFlag(const AFlag: string);

    function Dump(const AId: Integer = 0): string; override;
    function GetParamCount(): Integer;
  end;

// ConPTY (kernel32, Windows 10 1809+): what Winapi.Windows does not declare.
// COORD, EXTENDED_STARTUPINFO_PRESENT and the proc thread attribute list
// routines are Winapi.Windows'
const
  { PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE }
  PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = $00020016;
  { PROC_THREAD_ATTRIBUTE_HANDLE_LIST }
  // The only handles a child inherits (ProcThreadAttributeValue(2, False,
  // True, False)): a child given a stdin of its own inherits nothing else
  PROC_THREAD_ATTRIBUTE_HANDLE_LIST = $00020002;

type
  { HPCON }
  HPCON = THandle;

  { PSTARTUPINFOEXW }
  PSTARTUPINFOEXW = ^STARTUPINFOEXW;
  { STARTUPINFOEXW }
  STARTUPINFOEXW = record
    StartupInfo: TStartupInfoW;
    lpAttributeList: Pointer;
  end;

function CreatePseudoConsole(ASize: COORD; AInput: THandle; AOutput: THandle; AFlags: DWORD;
  out APseudoConsole: HPCON): HRESULT; stdcall; external kernel32 name 'CreatePseudoConsole';
function ResizePseudoConsole(APseudoConsole: HPCON; ASize: COORD): HRESULT; stdcall;
  external kernel32 name 'ResizePseudoConsole';
function ClosePseudoConsole(APseudoConsole: HPCON): HRESULT; stdcall;
  external kernel32 name 'ClosePseudoConsole';

implementation

function AddDllDirectory(NewDirectory: LPCWSTR): Pointer; stdcall; external kernel32 name 'AddDllDirectory';
function RemoveDllDirectory(Cookie: Pointer): BOOL; stdcall; external kernel32 name 'RemoveDllDirectory';
function SetDefaultDllDirectories(DirectoryFlags: DWORD): BOOL; stdcall; external kernel32 name 'SetDefaultDllDirectories';
function GetEnvironmentStringsW(): PWideChar; stdcall; external kernel32 name 'GetEnvironmentStringsW';
function FreeEnvironmentStringsW(lpszEnvironmentBlock: PWideChar): BOOL; stdcall; external kernel32 name 'FreeEnvironmentStringsW';

// Proc thread attribute list routines in the untyped form CaptureConsolePTY uses
function InitializeProcThreadAttributeList(lpAttributeList: Pointer; dwAttributeCount: DWORD; dwFlags: DWORD; var lpSize: SIZE_T): BOOL; stdcall; external kernel32 name 'InitializeProcThreadAttributeList';
function UpdateProcThreadAttribute(lpAttributeList: Pointer; dwFlags: DWORD; Attribute: DWORD_PTR; lpValue: Pointer; cbSize: SIZE_T; lpPreviousValue: Pointer; lpReturnSize: PSIZE_T): BOOL; stdcall; external kernel32 name 'UpdateProcThreadAttribute';
procedure DeleteProcThreadAttributeList(lpAttributeList: Pointer); stdcall; external kernel32 name 'DeleteProcThreadAttributeList';

{ PtySide }
// One side of a pseudoconsole's size, as COORD holds it
function PtySide(const AValue: Integer): SmallInt;
begin
  if AValue < 1 then
    Result := 1
  else if AValue > PTY_SIDE_MAX then
    Result := PTY_SIDE_MAX
  else
    Result := SmallInt(AValue);
end;

{ TPtyHost }

destructor TPtyHost.Destroy();
begin
  Stop();

  inherited;
end;

function TPtyHost.InitialSize(out ASize: COORD): Boolean;
begin
  ASize.X := 0;
  ASize.Y := 0;
  Result := False;
end;

function TPtyHost.StdInput(): THandle;
begin
  // The pseudoconsole: the keys this host writes
  Result := 0;
end;

procedure TPtyHost.Start(const AInput: THandle; const AConsole: THandle);
begin
  // DoStart releases what it made when it raises: a host that did not
  // start has nothing to stop
  if FStarted then
    Exit;
  FInput := AInput;
  FConsole := AConsole;
  DoStart();
  FStarted := True;
end;

procedure TPtyHost.Stop();
begin
  if not FStarted then
    Exit;
  FStarted := False;
  DoStop();
end;

function TPtyHost.DoWriteKeys(const ABytes: TBytes): Boolean;
var
  LOffset: Integer;
  LWritten: DWORD;
begin
  Result := False;
  LOffset := 0;
  while LOffset < Length(ABytes) do
  begin
    LWritten := 0;
    if not WriteFile(FInput, ABytes[LOffset], DWORD(Length(ABytes) - LOffset), LWritten, nil) then
      Exit;
    Inc(LOffset, Integer(LWritten));
  end;
  Result := True;
end;

function TPtyHost.DoResize(const ACols: Integer; const ARows: Integer): Boolean;
var
  LSize: COORD;
begin
  LSize.X := PtySide(ACols);
  LSize.Y := PtySide(ARows);
  Result := Succeeded(ResizePseudoConsole(FConsole, LSize));
end;

{ TPtyConsoleHost }

procedure TPtyConsoleHost.Init(const AConsoleInput: THandle; const AConsoleOutput: THandle);
begin
  FConsoleInput := AConsoleInput;
  FConsoleOutput := AConsoleOutput;
end;

class function TPtyConsoleHost.KeyText(const AEvents: array of TInputRecord; const ACount: Integer): string;
var
  LCount: Integer;
  LIndex: Integer;
  LRepeat: Integer;
begin
  // In VT input mode the console spells every key as text (an arrow is
  // ESC [ A over three records): the key-down characters are the bytes
  Result := '';
  LCount := Min(ACount, Length(AEvents));
  for LIndex := 0 to LCount - 1 do
  begin
    if AEvents[LIndex].EventType <> KEY_EVENT then
      Continue;
    if not AEvents[LIndex].Event.KeyEvent.bKeyDown then
      Continue;
    if AEvents[LIndex].Event.KeyEvent.UnicodeChar = #0 then
      Continue;
    // A key held down comes once with its repeat count
    for LRepeat := 1 to Max(1, Integer(AEvents[LIndex].Event.KeyEvent.wRepeatCount)) do
      Result := Result + AEvents[LIndex].Event.KeyEvent.UnicodeChar;
  end;
end;

function TPtyConsoleHost.DoWindowSize(out ASize: COORD): Boolean;
var
  LInfo: TConsoleScreenBufferInfo;
begin
  ASize.X := 0;
  ASize.Y := 0;
  Result := GetConsoleScreenBufferInfo(FConsoleOutput, LInfo);
  if Result then
  begin
    ASize.X := LInfo.srWindow.Right - LInfo.srWindow.Left + 1;
    ASize.Y := LInfo.srWindow.Bottom - LInfo.srWindow.Top + 1;
  end;
end;

function TPtyConsoleHost.InitialSize(out ASize: COORD): Boolean;
begin
  Result := DoWindowSize(ASize);
end;

procedure TPtyConsoleHost.DoStart();
var
  LReason: string;
begin
  // Raw keys: the program's terminal echoes and edits lines itself
  if not GetConsoleMode(FConsoleInput, FSavedMode) then
    raise Exception.CreateFmt('TPtyConsoleHost: the input is not a console (%s)',
      [SysErrorMessage(GetLastError())]);
  if not SetConsoleMode(FConsoleInput, ENABLE_VIRTUAL_TERMINAL_INPUT or ENABLE_WINDOW_INPUT) then
    raise Exception.CreateFmt('TPtyConsoleHost: the console takes no VT input (%s)',
      [SysErrorMessage(GetLastError())]);
  FModeSet := True;
  try
    FStopEvent := CreateEvent(nil, True, False, nil);
    if FStopEvent = 0 then
    begin
      LReason := SysErrorMessage(GetLastError());
      raise Exception.CreateFmt('TPtyConsoleHost: no stop event (%s)', [LReason]);
    end;
    FThread := TThread.CreateAnonymousThread(
      procedure
      begin
        DoRun();
      end);
    FThread.FreeOnTerminate := False;
    FThread.Start();
  except
    if FStopEvent <> 0 then
    begin
      CloseHandle(FStopEvent);
      FStopEvent := 0;
    end;
    FreeAndNil(FThread);
    SetConsoleMode(FConsoleInput, FSavedMode);
    FModeSet := False;
    raise;
  end;
end;

procedure TPtyConsoleHost.DoRun();
var
  LHandles: array[0..1] of THandle;
  LRecords: array of TInputRecord;
  LCount: DWORD;
  LIndex: Integer;
  LText: string;
  LResized: Boolean;
  LSize: COORD;
begin
  SetLength(LRecords, PTY_READ_CHUNK div SizeOf(TInputRecord));
  LHandles[0] := FStopEvent;
  LHandles[1] := FConsoleInput;
  // Wakes for console input or Stop: never blocked in a read at the end
  while WaitForMultipleObjects(2, @LHandles[0], False, INFINITE) = WAIT_OBJECT_0 + 1 do
  begin
    LCount := 0;
    if not ReadConsoleInputW(FConsoleInput, LRecords[0], DWORD(Length(LRecords)), LCount) then
      Break;
    LText := KeyText(LRecords, Integer(LCount));
    if (LText <> '') and (not DoWriteKeys(TEncoding.UTF8.GetBytes(LText))) then
      Break;
    // The window changed: the program's terminal follows
    LResized := False;
    for LIndex := 0 to Integer(LCount) - 1 do
      if LRecords[LIndex].EventType = WINDOW_BUFFER_SIZE_EVENT then
        LResized := True;
    if LResized and DoWindowSize(LSize) then
      DoResize(LSize.X, LSize.Y);
  end;
end;

procedure TPtyConsoleHost.DoStop();
begin
  SetEvent(FStopEvent);
  FThread.WaitFor();
  FreeAndNil(FThread);
  CloseHandle(FStopEvent);
  FStopEvent := 0;
  if FModeSet then
  begin
    SetConsoleMode(FConsoleInput, FSavedMode);
    FModeSet := False;
  end;
end;

{ TPtyStreamHost }

procedure TPtyStreamHost.Init(const ASource: THandle);
begin
  FSource := ASource;
end;

function TPtyStreamHost.StdInput(): THandle;
begin
  Result := FSource;
end;

procedure TPtyStreamHost.DoStart();
begin
  // The program reads FSource itself (StdInput): nothing to forward
end;

procedure TPtyStreamHost.DoStop();
begin
  // Nothing started
end;

{ TPtyPipeHost }

destructor TPtyPipeHost.Destroy();
begin
  // Stop ends the input; the pipe stays for the output until here
  Stop();
  if (FPipe <> 0) and (FPipe <> INVALID_HANDLE_VALUE) then
    CloseHandle(FPipe);
  FPipe := 0;
  if FStopEvent <> 0 then
    CloseHandle(FStopEvent);
  if FReadEvent <> 0 then
    CloseHandle(FReadEvent);
  if FWriteEvent <> 0 then
    CloseHandle(FWriteEvent);
  FStopEvent := 0;
  FReadEvent := 0;
  FWriteEvent := 0;

  inherited;
end;

procedure TPtyPipeHost.Init(const APipeName: string);
begin
  FPipeName := APipeName;
end;

class function TPtyPipeHost.ParseFrames(var ABuffer: TBytes; out AFrames: TArray<TPtyFrame>): Boolean;
var
  LList: TList<TPtyFrame>;
  LOffset: Integer;
  LKind: AnsiChar;
  LLength: Cardinal;
  LFrame: TPtyFrame;
begin
  Result := True;
  LList := TList<TPtyFrame>.Create();
  try
    LOffset := 0;
    while Length(ABuffer) - LOffset >= PTY_FRAME_HEAD do
    begin
      LKind := AnsiChar(ABuffer[LOffset]);
      LLength := Cardinal(ABuffer[LOffset + 1]) or (Cardinal(ABuffer[LOffset + 2]) shl 8) or
        (Cardinal(ABuffer[LOffset + 3]) shl 16) or (Cardinal(ABuffer[LOffset + 4]) shl 24);

      // A stream that cannot be frames: an unknown kind, a resize of another
      // size, a length past the limit
      if ((LKind <> PTY_FRAME_KEYS) and (LKind <> PTY_FRAME_RESIZE)) or
        ((LKind = PTY_FRAME_RESIZE) and (LLength <> 4)) or (LLength > PTY_FRAME_MAX) then
      begin
        Result := False;
        Break;
      end;

      // Not all of it here yet: the next read completes it
      if Cardinal(Length(ABuffer) - LOffset - PTY_FRAME_HEAD) < LLength then
        Break;

      LFrame := Default(TPtyFrame);
      LFrame.Kind := LKind;
      if LKind = PTY_FRAME_KEYS then
        LFrame.Keys := Copy(ABuffer, LOffset + PTY_FRAME_HEAD, Integer(LLength))
      else
      begin
        LFrame.Cols := Word(ABuffer[LOffset + PTY_FRAME_HEAD]) or
          (Word(ABuffer[LOffset + PTY_FRAME_HEAD + 1]) shl 8);
        LFrame.Rows := Word(ABuffer[LOffset + PTY_FRAME_HEAD + 2]) or
          (Word(ABuffer[LOffset + PTY_FRAME_HEAD + 3]) shl 8);
      end;
      LList.Add(LFrame);
      Inc(LOffset, PTY_FRAME_HEAD + Integer(LLength));
    end;
    ABuffer := Copy(ABuffer, LOffset, Length(ABuffer) - LOffset);
    AFrames := LList.ToArray();
  finally
    LList.Free();
  end;
end;

procedure TPtyPipeHost.DoStart();
var
  LReason: string;
begin
  FPipe := CreateFile(PChar(FPipeName), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING,
    FILE_FLAG_OVERLAPPED, 0);
  if FPipe = INVALID_HANDLE_VALUE then
  begin
    LReason := SysErrorMessage(GetLastError());
    FPipe := 0;
    raise Exception.CreateFmt('TPtyPipeHost: cannot connect to %s (%s)', [FPipeName, LReason]);
  end;
  try
    FStopEvent := CreateEvent(nil, True, False, nil);
    FReadEvent := CreateEvent(nil, True, False, nil);
    FWriteEvent := CreateEvent(nil, True, False, nil);
    if (FStopEvent = 0) or (FReadEvent = 0) or (FWriteEvent = 0) then
    begin
      LReason := SysErrorMessage(GetLastError());
      raise Exception.CreateFmt('TPtyPipeHost: no events (%s)', [LReason]);
    end;
    FThread := TThread.CreateAnonymousThread(
      procedure
      begin
        DoRun();
      end);
    FThread.FreeOnTerminate := False;
    FThread.Start();
  except
    // Nothing of a host that did not start stays (Destroy finds zeros)
    FreeAndNil(FThread);
    CloseHandle(FPipe);
    FPipe := 0;
    if FStopEvent <> 0 then
      CloseHandle(FStopEvent);
    if FReadEvent <> 0 then
      CloseHandle(FReadEvent);
    if FWriteEvent <> 0 then
      CloseHandle(FWriteEvent);
    FStopEvent := 0;
    FReadEvent := 0;
    FWriteEvent := 0;
    raise;
  end;
end;

procedure TPtyPipeHost.DoApply(const AFrames: TArray<TPtyFrame>);
var
  LFrame: TPtyFrame;
begin
  for LFrame in AFrames do
  begin
    if LFrame.Kind = PTY_FRAME_KEYS then
      DoWriteKeys(LFrame.Keys)
    else
      DoResize(LFrame.Cols, LFrame.Rows);
  end;
end;

procedure TPtyPipeHost.DoRun();
var
  LChunk: TBytes;
  LBuffer: TBytes;
  LOverlapped: TOverlapped;
  LHandles: array[0..1] of THandle;
  LRead: DWORD;
  LFrames: TArray<TPtyFrame>;
  LOk: Boolean;
begin
  SetLength(LChunk, PTY_READ_CHUNK);
  LBuffer := nil;
  LHandles[0] := FStopEvent;
  LHandles[1] := FReadEvent;
  repeat
    FillChar(LOverlapped, SizeOf(LOverlapped), 0);
    LOverlapped.hEvent := FReadEvent;
    ResetEvent(FReadEvent);
    LRead := 0;
    if (not ReadFile(FPipe, LChunk[0], DWORD(Length(LChunk)), LRead, @LOverlapped)) and
      (GetLastError() <> ERROR_IO_PENDING) then
      Break;

    // Stop: the pending read (this thread's) is cancelled and waited for,
    // its buffer is this thread's own
    if WaitForMultipleObjects(2, @LHandles[0], False, INFINITE) <> WAIT_OBJECT_0 + 1 then
    begin
      CancelIo(FPipe);
      GetOverlappedResult(FPipe, LOverlapped, LRead, True);
      Break;
    end;

    // A read that fails: the host app is gone
    LRead := 0;
    if not GetOverlappedResult(FPipe, LOverlapped, LRead, False) then
      Break;
    LBuffer := LBuffer + Copy(LChunk, 0, Integer(LRead));
    LOk := ParseFrames(LBuffer, LFrames);
    DoApply(LFrames);
    if not LOk then
      Break;
  until False;
end;

procedure TPtyPipeHost.DoStop();
begin
  // Only the input ends here: the program's last output still goes out
  // (CaptureConsolePTY drains after Stop), the pipe closes in Destroy
  SetEvent(FStopEvent);
  FThread.WaitFor();
  FreeAndNil(FThread);
end;

function TPtyPipeHost.WriteOutput(const AText: string): Boolean;
var
  LBytes: TBytes;
  LOverlapped: TOverlapped;
  LOffset: Integer;
  LWritten: DWORD;
begin
  Result := False;
  if (FPipe = 0) or (FPipe = INVALID_HANDLE_VALUE) then
    Exit;
  LBytes := TEncoding.UTF8.GetBytes(AText);
  LOffset := 0;
  while LOffset < Length(LBytes) do
  begin
    FillChar(LOverlapped, SizeOf(LOverlapped), 0);
    LOverlapped.hEvent := FWriteEvent;
    ResetEvent(FWriteEvent);
    LWritten := 0;
    if (not WriteFile(FPipe, LBytes[LOffset], DWORD(Length(LBytes) - LOffset), LWritten, @LOverlapped)) and
      (GetLastError() <> ERROR_IO_PENDING) then
      Exit;
    if not GetOverlappedResult(FPipe, LOverlapped, LWritten, True) then
      Exit;
    Inc(LOffset, Integer(LWritten));
  end;
  Result := True;
end;

{ DoIsLongPathForm }
// True for the long-path spelling in either slash (\\?\..., //?/..., or a
// mix): read as the same path, whichever slash it was typed with
function DoIsLongPathForm(const APath: string): Boolean;
begin
  Result := (Length(APath) >= 4) and CharInSet(APath[1], ['\', '/']) and
    CharInSet(APath[2], ['\', '/']) and (APath[3] = '?') and
    CharInSet(APath[4], ['\', '/']);
end;

{ DoFinishResolvedPath }
// ResolvePath's one output form for a full path: past PATH_PLAIN_MAX the
// long-path spelling, since the plain one fails in Win32 routines; else the
// normalized forward-slash spelling. Idempotent on both.
function DoFinishResolvedPath(const AFullPath: string): string;
var
  LPath: string;
begin
  if DoIsLongPathForm(AFullPath) then
    Exit(AFullPath.Replace('/', '\'));

  if Length(AFullPath) <= PATH_PLAIN_MAX then
    Exit(TUtils.NormalizePath(AFullPath));

  LPath := AFullPath.Replace('/', '\');

  // A device path (\\.\...) is passed to the OS as is, like the long form
  if LPath.StartsWith('\\.\') then
    Exit(LPath);

  // A UNC path starts with two delimiters: \\server\share
  if LPath.StartsWith('\\') then
    Result := PATH_LONG_UNC_PREFIX + LPath.Substring(2)
  else
    Result := PATH_LONG_PREFIX + LPath;
end;

type
  { TResourceUpdateProc }
  // One BeginUpdateResource .. EndUpdateResource pass on AWorkPath
  TResourceUpdateProc = reference to procedure(const AWorkPath: string);

{ DoRaiseOSError }
// Raises EOSError for ACode with the plain system message: the code is what
// DoRunResourceUpdate's retry decision reads
procedure DoRaiseOSError(const ACode: DWORD);
var
  LError: EOSError;
begin
  LError := EOSError.Create(SysErrorMessage(ACode));
  LError.ErrorCode := ACode;
  raise LError;
end;

{ DoIsBusyFileError }
// The OS codes for a file another process holds for a moment: EndUpdateResource
// reports it as access denied (probe3b.txt), BeginUpdateResource on a file
// held against writing as ERROR_OPEN_FAILED (the testbed's resource_busy)
function DoIsBusyFileError(const ACode: DWORD): Boolean;
begin
  Result := (ACode = ERROR_ACCESS_DENIED) or (ACode = ERROR_SHARING_VIOLATION) or
    (ACode = ERROR_LOCK_VIOLATION) or (ACode = ERROR_OPEN_FAILED);
end;

{ DoRunResourceUpdate }
// Runs one resource-update pass on AWorkPath, again while Windows reports the
// file busy (RESOURCE_UPDATE_ATTEMPTS, RESOURCE_UPDATE_RETRY_MS apart; R46).
// Any other failure, and the last busy one, raises as it came.
procedure DoRunResourceUpdate(const AWorkPath: string; const AUpdate: TResourceUpdateProc);
var
  LAttempt: Integer;
begin
  for LAttempt := 1 to RESOURCE_UPDATE_ATTEMPTS do
  begin
    try
      AUpdate(AWorkPath);
      Exit;
    except
      on E: EOSError do
      begin
        if (LAttempt = RESOURCE_UPDATE_ATTEMPTS) or (not DoIsBusyFileError(E.ErrorCode)) then
          raise;
      end;
    end;
    Sleep(RESOURCE_UPDATE_RETRY_MS);
  end;
end;

{ DoUpdateResources }
// Runs AUpdate on a spelling of APath the Win32 resource API takes: the plain
// spelling when it fits PATH_RESOURCE_MAX; else a copy in the temp folder,
// copied back over the file only once AUpdate succeeded, so a failure leaves
// the file as it was. Raises with the reason on any failure.
procedure DoUpdateResources(const APath: string; const AUpdate: TResourceUpdateProc);
var
  LPlain: string;
  LWorkPath: string;
begin
  LPlain := TUtils.StripLongPathPrefix(APath);
  if Length(LPlain) <= PATH_RESOURCE_MAX then
  begin
    DoRunResourceUpdate(LPlain, AUpdate);
    Exit;
  end;

  LWorkPath := TPath.Combine(TPath.GetTempPath(),
    TPath.GetGUIDFileName() + TPath.GetExtension(LPlain));
  if Length(LWorkPath) > PATH_RESOURCE_MAX then
    raise Exception.CreateFmt(
      'The temp folder is too long for a resource update (%d characters, the limit is %d): %s',
      [Length(LWorkPath), PATH_RESOURCE_MAX, LWorkPath]);

  TFile.Copy(APath, LWorkPath, False);
  try
    // A read-only file copies read-only: the copy must take the update
    TFile.SetAttributes(LWorkPath, [TFileAttribute.faNormal]);
    DoRunResourceUpdate(LWorkPath, AUpdate);
    TFile.Copy(LWorkPath, APath, True);
  except
    // The update's own reason is the one raised; the copy goes with it
    System.SysUtils.DeleteFile(LWorkPath);
    raise;
  end;

  // The file holds the update: a copy that cannot be removed is a failure
  TFile.Delete(LWorkPath);
end;



{ TCbrUtils }

class function TUtils.EnableVirtualTerminalProcessing(): Boolean;
var
  LHOut: THandle;
  LMode: DWORD;
begin
  Result := False;

  LHOut := GetStdHandle(STD_OUTPUT_HANDLE);
  if LHOut = INVALID_HANDLE_VALUE then Exit;
  if not GetConsoleMode(LHOut, LMode) then Exit;

  LMode := LMode or ENABLE_VIRTUAL_TERMINAL_PROCESSING;
  if not SetConsoleMode(LHOut, LMode) then Exit;

  Result := True;
end;

class procedure TUtils.InitConsole();
begin
  EnableVirtualTerminalProcessing();
  SetConsoleCP(CP_UTF8);
  SetConsoleOutputCP(CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  SetTextCodePage(ErrOutput, CP_UTF8);
end;

class procedure TUtils.FailIf(const Cond: Boolean; const Msg: string; const AArgs: array of const);
begin
  if Cond then
    raise Exception.CreateFmt(Msg, AArgs);
end;

class function TUtils.GetTickCount(): DWORD;
begin
  Result := WinApi.Windows.GetTickCount();
end;

class function TUtils.GetTickCount64(): UInt64;
begin
  Result := WinApi.Windows.GetTickCount64();
end;

class function TUtils.AsUTF8(const AValue: string; ALength: PCardinal): Pointer;
begin
  Result := FMarshaller.AsUtf8(AValue).ToPointer;
  if Assigned(ALength) then
    ALength^ := System.AnsiStrings.StrLen(PAnsiChar(Result));
end;

class function TUtils.ToAnsi(const AValue: string): AnsiString;
var
  LBytes: TBytes;
begin
  LBytes := TEncoding.ANSI.GetBytes(AValue);
  if Length(LBytes) = 0 then
    Exit('');
  SetString(Result, PAnsiChar(@LBytes[0]), Length(LBytes));
end;

class function TUtils.FromUtf8(const APtr: PAnsiChar): string;
begin
  if APtr = nil then
    Result := ''
  else
    Result := string(UTF8String(APtr));
end;

class procedure TUtils.ProcessMessages();
var
  LMsg: TMsg;
begin
  while Integer(PeekMessage(LMsg, 0, 0, 0, PM_REMOVE)) <> 0 do
  begin
    TranslateMessage(LMsg);
    DispatchMessage(LMsg);
  end;
end;

class function TUtils.RunPE(const AExe, AParams, AWorkDir: string; const AWait: Boolean; const AShowCmd: Word): Cardinal;
var
  LAppPath: string;
  LCmd: UnicodeString;
  LSI: STARTUPINFOW;
  LPI: PROCESS_INFORMATION;
  LExit: DWORD;
  LCreationFlags: DWORD;
  LWorkDirPW: PWideChar;
begin
  if AExe = '' then
    raise Exception.Create('RunPE: Executable path is empty');

  // Resolve the executable path against the workdir if only a filename was provided
  if TPath.IsPathRooted(TUtils.ResolvePath(AExe)) or (Pos('\', AExe) > 0) or (Pos('/', AExe) > 0) then
    LAppPath := TUtils.ResolvePath(AExe)
  else if AWorkDir <> '' then
    LAppPath := TPath.Combine(AWorkDir, AExe)
  else
    LAppPath := AExe; // will rely on caller's current dir / PATH

  // Quote the app path and build a mutable command line
  if AParams <> '' then
    LCmd := '"' + LAppPath + '" ' + AParams
  else
    LCmd := '"' + LAppPath + '"';
  UniqueString(LCmd);

  // Ensure the exe exists when a workdir is provided
  if (AWorkDir <> '') and (not TFile.Exists(LAppPath)) then
    raise Exception.CreateFmt('RunPE: Executable not found: %s', [LAppPath]);

  ZeroMemory(@LSI, SizeOf(LSI));
  ZeroMemory(@LPI, SizeOf(LPI));
  LSI.cb := SizeOf(LSI);
  LSI.dwFlags := STARTF_USESHOWWINDOW;
  LSI.wShowWindow := AShowCmd;

  if AWorkDir <> '' then
    LWorkDirPW := PWideChar(AWorkDir)
  else
    LWorkDirPW := nil;

  LCreationFlags := CREATE_UNICODE_ENVIRONMENT;

  // Pass the resolved path in lpApplicationName so Windows won't search using the caller's current directory
  if not CreateProcessW(
    PWideChar(LAppPath),
    PWideChar(LCmd),
    nil,
    nil,
    False,
    LCreationFlags,
    nil,
    LWorkDirPW,
    LSI,
    LPI
  ) then
    raise Exception.CreateFmt('RunPE: CreateProcess failed (%d) %s', [GetLastError, SysErrorMessage(GetLastError)]);

  try
    if AWait then
    begin
      WaitForSingleObject(LPI.hProcess, INFINITE);
      LExit := 0;
      if GetExitCodeProcess(LPI.hProcess, LExit) then
        Result := LExit
      else
        raise Exception.CreateFmt('RunPE: GetExitCodeProcess failed (%d) %s', [GetLastError, SysErrorMessage(GetLastError)]);
    end
    else
      Result := 0;
  finally
    CloseHandle(LPI.hThread);
    CloseHandle(LPI.hProcess);
  end;
end;

{ DoHostStdin }
// A host's standard input for a pipe run (TPtyHost.StdInput); 0 = none: NUL
function DoHostStdin(const AHost: TPtyHost): THandle;
begin
  Result := 0;
  if AHost <> nil then
    Result := AHost.StdInput();
end;

class procedure TUtils.RunPE(const AExe: string; const AParams: string; const AWorkDir: string;
  var AExitCode: DWORD; const AUserData: Pointer; const ACallback: TCaptureConsoleCallback;
  const AUsePipes: Boolean; const AHost: TPtyHost);
begin
  // The Windows twin of RunElf: the program's output to ACallback through a
  // pseudoconsole, or with AUsePipes over pipes, every line kept (stdout and
  // stderr share one pipe: the order written). A program that cannot start
  // raises, the exit code untouched
  if AExe = '' then
    raise Exception.Create('RunPE: Executable path is empty');
  // Pipes: a host's StdInput is the program's stdin (a TPtyStreamHost over a
  // file: real end of file); no host = NUL
  if AUsePipes then
    CaptureConsoleOutput('', PChar(AExe), PChar(AParams), AWorkDir, AExitCode, AUserData, ACallback, True,
      0, nil, DoHostStdin(AHost))
  else
    CaptureConsolePTY(PChar(AExe), PChar(AParams), AWorkDir, AExitCode, AUserData, ACallback, AHost);
end;

class function TUtils.LaunchName(const AProgram: string): string;
var
  LPlain: string;
begin
  // A bare name, or a path the command line names in full: CreateProcess
  // finds it from the command line (and searches PATH for a bare name)
  Result := '';
  LPlain := StripLongPathPrefix(AProgram);
  if Length(LPlain) <= PATH_LAUNCH_MAX then
    Exit;

  // Longer: named by its long-path spelling (ResolvePath returns it past
  // PATH_PLAIN_MAX), which CreateProcess launches at any length
  Result := ResolvePath(LPlain);
end;

class function TUtils.WindowsPathToWSL(const APath: string): string;
var
  LFullPath: string;
  LDrive: Char;
begin
  // A long-path spelling names the same drive path (ResolvePath returns it
  // past PATH_PLAIN_MAX): read without its prefix
  LFullPath := StripLongPathPrefix(TPath.GetFullPath(APath));

  // Convert Windows path to WSL path: C:\foo\bar -> /mnt/c/foo/bar
  if (Length(LFullPath) >= 3) and (LFullPath[2] = ':') and (LFullPath[3] = '\') then
  begin
    LDrive := LowerCase(LFullPath[1])[1];
    Result := '/mnt/' + LDrive + '/' +
      StringReplace(Copy(LFullPath, 4, MaxInt), '\', '/', [rfReplaceAll]);
  end
  else
    raise Exception.CreateFmt('WindowsPathToWSL: Expected absolute Windows path: %s', [LFullPath]);
end;

class procedure TUtils.RunElf(const AElf: string; const AParams: string;
  const AWorkDir: string; var AExitCode: DWORD; const AUserData: Pointer;
  const ACallback: TCaptureConsoleCallback; const AUsePipes: Boolean; const AHost: TPtyHost);
var
  LWslPath: string;
  LChmodArgs: string;
  LChmodExit: DWORD;
  LChmodOutput: string;
  LCommand: string;
begin
  if AElf = '' then
    raise Exception.Create('RunElf: ELF path is empty');

  // The ELF as WSL names it (raises on a path with no drive form: UNC)
  LWslPath := WindowsPathToWSL(AElf);

  // Make it executable. wsl.exe -e runs the program itself, no shell, so the
  // path is one literal argument. A chmod that fails stops the run with its
  // own words (R26: its exit code was never read)
  LChmodArgs := '-e chmod +x ' + QuoteCommandArg(LWslPath);
  LChmodExit := 0;
  LChmodOutput := '';
  CaptureConsoleOutput('', 'wsl.exe', PChar(LChmodArgs), AWorkDir, LChmodExit,
    nil,
    procedure(const ALine: string; const AData: Pointer)
    begin
      if LChmodOutput <> '' then
        LChmodOutput := LChmodOutput + ' ';
      LChmodOutput := LChmodOutput + ALine;
    end);
  if LChmodExit <> 0 then
    raise Exception.CreateFmt('RunElf: chmod +x %s failed (exit %d): %s',
      [LWslPath, LChmodExit, LChmodOutput]);

  // Run it: AParams follow the path as the program's own arguments, split by
  // the Windows argv rule exactly as for a Windows program (the same argv on
  // both: scripts\zb_e\a5\fixtures.txt), never through bash (R35)
  // Pipes: the program's own text, every line (a pseudoconsole renders it).
  // wsl relays a Linux program's stdout and stderr on separate channels, so
  // their order is merged inside Linux: sh runs a fixed script that execs
  // the program with stderr on stdout; the program and its arguments are
  // sh's positional parameters ("$0" "$@"), never parsed by it (R35)
  if AUsePipes then
    LCommand := '-e sh -c ' + QuoteCommandArg('exec "$0" "$@" 2>&1') + ' ' + QuoteCommandArg(LWslPath)
  else
    LCommand := '-e ' + QuoteCommandArg(LWslPath);
  if AParams <> '' then
    LCommand := LCommand + ' ' + AParams;
  if AUsePipes then
    CaptureConsoleOutput('', 'wsl.exe', PChar(LCommand), AWorkDir, AExitCode, AUserData,
      ACallback, True, 0, nil, DoHostStdin(AHost))
  else
    CaptureConsolePTY('wsl.exe', PChar(LCommand), AWorkDir, AExitCode, AUserData,
      ACallback, AHost);
end;

{ Opens a file with its registered default handler, the way a double-click
  would. Unlike RunPE (CreateProcessW), this resolves file associations, so it
  can open documents, folders and URLs -- not just executable images.

  There is no process handle and therefore no exit code: the handler runs
  detached. Callers that need an exit code must use RunPE instead. }
class function TUtils.ShellOpen(const AFilename: string; const AWorkDir: string;
  const AShowCmd: Word): Boolean;
var
  LResult: HINST;
  LWorkDir: PChar;
begin
  Result := False;

  if AFilename = '' then
    Exit;

  if AWorkDir = '' then
    LWorkDir := nil
  else
    LWorkDir := PChar(AWorkDir);

  LResult := ShellExecute(0, 'open', PChar(AFilename), nil, LWorkDir, AShowCmd);

  // ShellExecute returns a value greater than 32 on success. Anything at or
  // below 32 is an error code, not an instance handle.
  Result := LResult > 32;
end;

class procedure TUtils.CaptureConsoleOutput(const ATitle: string; const ACommand: PChar; const AParameters: PChar; const AWorkDir: string; var AExitCode: DWORD; const AUserData: Pointer; const ACallback: TCaptureConsoleCallback; const AKeepEmptyLines: Boolean; const ATickMs: Cardinal; const ATick: TCaptureConsoleTick; const AStdin: THandle);
const
  CReadBuffer = 1024 * 2;
  // How often a polled read looks at the pipe while it is empty
  CPollMs = 50;
var
  LSASecurity: TSecurityAttributes;
  LHRead: THandle;
  LHWrite: THandle;
  LHNul: THandle;
  LSUIStartup: TStartupInfo;
  LPIProcess: TProcessInformation;
  LBuffer: array [0 .. CReadBuffer - 1] of Byte;
  LDRead: DWORD;
  LCmdLine: string;
  LAppName: string;
  LAppNamePtr: PChar;
  LExitCode: DWORD;
  LWorkDirPtr: PChar;
  LLineBytes: TMemoryStream;
  LI: Integer;
  LAfterCR: Boolean;
  LPolled: Boolean;
  LStartMs: UInt64;
  LLastTickMs: UInt64;

  // Polled read: waits for data in steps of CPollMs and calls ATick every
  // ATickMs meanwhile, so a caller hears from a program that is quiet for a
  // long time. False = the pipe is closed and empty (every writer exited):
  // the same end as a failed blocking ReadFile
  function DoPollRead(): Boolean;
  var
    LAvail: DWORD;
    LNowMs: UInt64;
  begin
    LDRead := 0;
    while True do
    begin
      LAvail := 0;
      if not PeekNamedPipe(LHRead, nil, 0, nil, @LAvail, nil) then
        Exit(False);
      if LAvail > 0 then
      begin
        if LAvail > CReadBuffer then
          LAvail := CReadBuffer;
        Exit(ReadFile(LHRead, LBuffer[0], LAvail, LDRead, nil));
      end;

      LNowMs := GetTickCount64();
      if LNowMs - LLastTickMs >= ATickMs then
      begin
        LLastTickMs := LNowMs;
        ATick(LNowMs - LStartMs, AUserData);
      end;
      Sleep(CPollMs);
    end;
  end;

  // One output line: UTF-8 (esbuild, binaryen); bytes that are not valid
  // UTF-8 come from a tool writing the OEM code page and decode as that
  function DoDecodeLine(): string;
  var
    LCodePage: UINT;
    LFlags: DWORD;
    LLen: Integer;
  begin
    Result := '';
    LCodePage := CP_UTF8;
    LFlags := MB_ERR_INVALID_CHARS;
    LLen := MultiByteToWideChar(LCodePage, LFlags, PAnsiChar(LLineBytes.Memory),
      Integer(LLineBytes.Size), nil, 0);
    if LLen = 0 then
    begin
      LCodePage := CP_OEMCP;
      LFlags := 0;
      LLen := MultiByteToWideChar(LCodePage, LFlags, PAnsiChar(LLineBytes.Memory),
        Integer(LLineBytes.Size), nil, 0);
    end;
    if LLen = 0 then
      Exit;
    SetLength(Result, LLen);
    MultiByteToWideChar(LCodePage, LFlags, PAnsiChar(LLineBytes.Memory),
      Integer(LLineBytes.Size), PChar(Result), LLen);
  end;

  // Emit the accumulated line; an empty one only with AKeepEmptyLines
  procedure DoEmitLine();
  var
    LLine: string;
  begin
    if (LLineBytes.Size = 0) and (not AKeepEmptyLines) then
      Exit;
    LLine := '';
    if LLineBytes.Size > 0 then
      LLine := DoDecodeLine();
    LLineBytes.Clear();
    if Assigned(ACallback) then
      ACallback(LLine, AUserData);
  end;

begin
  LSASecurity.nLength := SizeOf(TSecurityAttributes);
  LSASecurity.bInheritHandle := True;
  LSASecurity.lpSecurityDescriptor := nil;

  if not CreatePipe(LHRead, LHWrite, @LSASecurity, 0) then
    RaiseLastOSError();
  LHNul := INVALID_HANDLE_VALUE;
  try
    // The read end stays in this process: a child that inherited it could
    // read its own output
    SetHandleInformation(LHRead, HANDLE_FLAG_INHERIT, 0);

    // The child's input: AStdin (duplicated inheritable: the caller's handle
    // need not be), else NUL; never the output pipe
    if AStdin <> 0 then
    begin
      if not DuplicateHandle(GetCurrentProcess(), AStdin, GetCurrentProcess(), @LHNul, 0, True,
        DUPLICATE_SAME_ACCESS) then
      begin
        LHNul := INVALID_HANDLE_VALUE;
        RaiseLastOSError();
      end;
    end
    else
    begin
      LHNul := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
        @LSASecurity, OPEN_EXISTING, 0, 0);
      if LHNul = INVALID_HANDLE_VALUE then
        RaiseLastOSError();
    end;

    FillChar(LSUIStartup, SizeOf(TStartupInfo), #0);
    LSUIStartup.cb := SizeOf(TStartupInfo);
    LSUIStartup.hStdInput := LHNul;
    LSUIStartup.hStdOutput := LHWrite;
    LSUIStartup.hStdError := LHWrite;
    LSUIStartup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    LSUIStartup.wShowWindow := SW_HIDE;

    if ATitle.IsEmpty then
      LSUIStartup.lpTitle := nil
    else
      LSUIStartup.lpTitle := PChar(ATitle);

    // The program path quoted: CreateProcess splits an unquoted one at its
    // first space ('C:\Program Files\...') (R49). Past PATH_LAUNCH_MAX the
    // program is also named as the application, long spelling (A5)
    LCmdLine := QuoteCommandArg(StripLongPathPrefix(string(ACommand))) + ' ' +
      AParameters;
    LAppName := LaunchName(string(ACommand));
    if LAppName <> '' then
      LAppNamePtr := PChar(LAppName)
    else
      LAppNamePtr := nil;

    if AWorkDir <> '' then
      LWorkDirPtr := PChar(AWorkDir)
    else
      LWorkDirPtr := nil;

    // A tool that cannot start is an error for the caller (every caller
    // wraps this call and reports it), never a silent exit code 0
    if not CreateProcess(LAppNamePtr, PChar(LCmdLine), @LSASecurity, @LSASecurity, True,
      NORMAL_PRIORITY_CLASS, nil, LWorkDirPtr, LSUIStartup, LPIProcess) then
      RaiseLastOSError();
    try
      // Only the child holds the write end now: the pipe breaks when the
      // child exits, so the read loop ends on EOF, never on a buffer size
      CloseHandle(LHWrite);
      LHWrite := 0;

      LLineBytes := TMemoryStream.Create();
      LAfterCR := False;
      LPolled := (ATickMs > 0) and Assigned(ATick);
      LStartMs := GetTickCount64();
      LLastTickMs := LStartMs;
      try
        repeat
          LDRead := 0;
          if LPolled then
          begin
            if not DoPollRead() then
              Break;
          end
          else if not ReadFile(LHRead, LBuffer[0], CReadBuffer, LDRead, nil) then
            Break;
          for LI := 0 to Integer(LDRead) - 1 do
          begin
            // CR, LF and CR+LF each end one line: the LF of a pair ends
            // nothing (the pair may span two reads). Without
            // AKeepEmptyLines the empty lines are skipped in DoEmitLine
            if LBuffer[LI] = 13 then
            begin
              DoEmitLine();
              LAfterCR := True;
            end
            else if LBuffer[LI] = 10 then
            begin
              if not LAfterCR then
                DoEmitLine();
              LAfterCR := False;
            end
            else
            begin
              LLineBytes.WriteBuffer(LBuffer[LI], 1);
              LAfterCR := False;
            end;
          end;
          ProcessMessages();
        until False;

        // Any final line without a terminator (never an empty one: the
        // text ended with a terminator)
        if LLineBytes.Size > 0 then
          DoEmitLine();
      finally
        FreeAndNil(LLineBytes);
      end;

      WaitForSingleObject(LPIProcess.hProcess, INFINITE);
      if GetExitCodeProcess(LPIProcess.hProcess, LExitCode) then
        AExitCode := LExitCode;
    finally
      CloseHandle(LPIProcess.hProcess);
      CloseHandle(LPIProcess.hThread);
    end;
  finally
    CloseHandle(LHRead);
    if LHWrite <> 0 then
      CloseHandle(LHWrite);
    if LHNul <> INVALID_HANDLE_VALUE then
      CloseHandle(LHNul);
  end;
end;

class procedure TUtils.CaptureConsolePTY(const ACommand: PChar; const AParameters: PChar; const AWorkDir: string; var AExitCode: DWORD; const AUserData: Pointer; const ACallback: TCaptureConsoleCallback; const AHost: TPtyHost);
const
  CReadBuffer = 4096;
var
  LInputReadSide: THandle;
  LInputWriteSide: THandle;
  LOutputReadSide: THandle;
  LOutputWriteSide: THandle;
  LConsoleSize: COORD;
  LConsoleHandle: THandle;
  LConsoleInfo: TConsoleScreenBufferInfo;
  LPseudoConsole: HPCON;
  LAttrListSize: SIZE_T;
  LAttrList: Pointer;
  LStartupInfoEx: STARTUPINFOEXW;
  LProcessInfo: TProcessInformation;
  LCmdLine: string;
  LAppName: string;
  LAppNamePtr: PChar;
  LWorkDirPtr: PChar;
  LExitCode: DWORD;
  LError: DWORD;
  LHResult: HRESULT;
  LBuffer: array[0..CReadBuffer - 1] of AnsiChar;
  LBytesRead: DWORD;
  LBytesAvailable: DWORD;
  LRunning: DWORD;
  LPending: RawByteString;
  LCloser: TThread;
  LClosing: HPCON;
  LChildInput: THandle;
  LSecurity: TSecurityAttributes;
  LAttrCount: DWORD;

  // Pass ACount bytes of LBuffer to the callback. Output is handed over as it
  // arrives (an interactive prompt has no line end), but a UTF-8 sequence cut
  // by the read size is held back in LPending and completed by the next read.
  procedure DoEmitChunk(const ACount: DWORD);
  var
    LData: RawByteString;
    LLen: Integer;
    LLead: Integer;
    LNeed: Integer;
  begin
    SetString(LData, PAnsiChar(@LBuffer[0]), ACount);
    LData := LPending + LData;
    LPending := '';

    // Walk back over at most 3 continuation bytes (10xxxxxx) to the lead byte
    LLen := Length(LData);
    LLead := LLen;
    while (LLead > 0) and (LLen - LLead < 3) and
      ((Byte(LData[LLead]) and $C0) = $80) do
      Dec(LLead);

    // A lead byte whose sequence is not complete yet waits for the next read
    if (LLead > 0) and (Byte(LData[LLead]) >= $C0) then
    begin
      if Byte(LData[LLead]) >= $F0 then
        LNeed := 4
      else if Byte(LData[LLead]) >= $E0 then
        LNeed := 3
      else
        LNeed := 2;

      if LLen - LLead + 1 < LNeed then
      begin
        LPending := Copy(LData, LLead, LLen - LLead + 1);
        SetLength(LData, LLead - 1);
      end;
    end;

    if (LData <> '') and Assigned(ACallback) then
      ACallback(UTF8ToString(LData), AUserData);
  end;

begin
  // AExitCode is set only by a program that ran: one that cannot be started
  // raises, as in CaptureConsoleOutput (R34: exit code 1 with no reason)
  LPending := '';
  LPseudoConsole := 0;
  LAttrList := nil;
  LInputReadSide := 0;
  LInputWriteSide := 0;
  LOutputReadSide := 0;
  LOutputWriteSide := 0;
  LChildInput := 0;

  // Create pipes for ConPTY
  if not CreatePipe(LInputReadSide, LInputWriteSide, nil, 0) then
    RaiseLastOSError();

  if not CreatePipe(LOutputReadSide, LOutputWriteSide, nil, 0) then
  begin
    // The reason before CloseHandle can change it
    LError := GetLastError();
    CloseHandle(LInputReadSide);
    CloseHandle(LInputWriteSide);
    RaiseLastOSError(Integer(LError));
  end;

  try
    // The host's size (an editor's pane); else the visible window of the
    // console this runs in; else 120 x 30
    if (AHost = nil) or (not AHost.InitialSize(LConsoleSize)) then
    begin
      LConsoleSize.X := 120;
      LConsoleSize.Y := 30;
      LConsoleHandle := GetStdHandle(STD_OUTPUT_HANDLE);
      if (LConsoleHandle <> INVALID_HANDLE_VALUE) and GetConsoleScreenBufferInfo(LConsoleHandle, LConsoleInfo) then
      begin
        LConsoleSize.X := LConsoleInfo.srWindow.Right - LConsoleInfo.srWindow.Left + 1;
        LConsoleSize.Y := LConsoleInfo.srWindow.Bottom - LConsoleInfo.srWindow.Top + 1;
      end;
    end;

    LHResult := CreatePseudoConsole(LConsoleSize, LInputReadSide,
      LOutputWriteSide, 0, LPseudoConsole);
    if Failed(LHResult) then
      RaiseLastOSError(LHResult);

    try
      // Close the handles that were given to the pseudoconsole
      CloseHandle(LInputReadSide);
      LInputReadSide := 0;
      CloseHandle(LOutputWriteSide);
      LOutputWriteSide := 0;

      // The program's standard input. A host that types keys leaves it to
      // the pseudoconsole (0). Otherwise the program reads a handle of its
      // own and sees the input end where it ends, as in a shell: the host's
      // source ('prog < file'), or NUL when there is no host (as the pipes
      // mode, CaptureConsoleOutput); the pseudoconsole's input would never
      // end, and a program reading again would wait forever
      LSecurity.nLength := SizeOf(TSecurityAttributes);
      LSecurity.bInheritHandle := True;
      LSecurity.lpSecurityDescriptor := nil;
      if AHost = nil then
      begin
        LChildInput := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
          @LSecurity, OPEN_EXISTING, 0, 0);
        if LChildInput = INVALID_HANDLE_VALUE then
        begin
          LChildInput := 0;
          RaiseLastOSError();
        end;
      end
      else if AHost.StdInput() <> 0 then
      begin
        // An inheritable copy: the host's own handle may not be
        if not DuplicateHandle(GetCurrentProcess(), AHost.StdInput(), GetCurrentProcess(),
            @LChildInput, 0, True, DUPLICATE_SAME_ACCESS) then
        begin
          LChildInput := 0;
          RaiseLastOSError();
        end;
      end;

      // The pseudoconsole; with a stdin of its own, the list of the only
      // handles the program inherits (that one: never a pipe end of this run)
      if LChildInput <> 0 then
        LAttrCount := 2
      else
        LAttrCount := 1;

      // Get attribute list size
      LAttrListSize := 0;
      InitializeProcThreadAttributeList(nil, LAttrCount, 0, LAttrListSize);

      // Allocate attribute list
      LAttrList := AllocMem(LAttrListSize);
      if not InitializeProcThreadAttributeList(LAttrList, LAttrCount, 0, LAttrListSize) then
        RaiseLastOSError();

      try
        // Set pseudoconsole attribute
        if not UpdateProcThreadAttribute(LAttrList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
            Pointer(LPseudoConsole), SizeOf(HPCON), nil, nil) then
          RaiseLastOSError();

        // LChildInput stays put until CreateProcess: the list points at it
        if (LChildInput <> 0) and (not UpdateProcThreadAttribute(LAttrList, 0,
            PROC_THREAD_ATTRIBUTE_HANDLE_LIST, @LChildInput, SizeOf(THandle), nil, nil)) then
          RaiseLastOSError();

        // Initialize extended startup info
        FillChar(LStartupInfoEx, SizeOf(LStartupInfoEx), 0);
        LStartupInfoEx.StartupInfo.cb := SizeOf(STARTUPINFOEXW);
        LStartupInfoEx.lpAttributeList := LAttrList;

        // The child must reach the pseudoconsole only. Without this, a parent
        // whose own stdio is redirected (an IDE, an editor, a pipe) passes
        // those handles to the child, which then writes around the
        // pseudoconsole straight into the parent's output. A 0 handle is the
        // pseudoconsole's; stdin is the one decided above
        LStartupInfoEx.StartupInfo.dwFlags := STARTF_USESTDHANDLES;
        LStartupInfoEx.StartupInfo.hStdInput := LChildInput;
        LStartupInfoEx.StartupInfo.hStdOutput := 0;
        LStartupInfoEx.StartupInfo.hStdError := 0;

        // Build command line
        // The program path quoted: CreateProcess splits an unquoted one at
        // its first space ('C:\Program Files\...') (R49)
        // Past PATH_LAUNCH_MAX the program is also named as the application,
        // long spelling (A5)
        LCmdLine := QuoteCommandArg(StripLongPathPrefix(string(ACommand))) +
          ' ' + string(AParameters);
        LAppName := LaunchName(string(ACommand));
        if LAppName <> '' then
          LAppNamePtr := PChar(LAppName)
        else
          LAppNamePtr := nil;

        if AWorkDir <> '' then
          LWorkDirPtr := PChar(AWorkDir)
        else
          LWorkDirPtr := nil;

        // The keyboard and size come from the host from here (keys typed
        // before the program reads wait in the pseudoconsole's input); a
        // host that cannot serve raises: the program is not started
        if AHost <> nil then
          AHost.Start(LInputWriteSide, LPseudoConsole);
        try
          // Create process - pass nil for environment to inherit from parent
          FillChar(LProcessInfo, SizeOf(LProcessInfo), 0);
          // Inheriting is on only for a stdin of its own; the handle list
          // limits it to that handle
          if not CreateProcessW(LAppNamePtr, PWideChar(LCmdLine), nil, nil, LChildInput <> 0,
              EXTENDED_STARTUPINFO_PRESENT,
              nil, LWorkDirPtr, LStartupInfoEx.StartupInfo, LProcessInfo) then
            RaiseLastOSError();

          try
            repeat
              LRunning := WaitForSingleObject(LProcessInfo.hProcess, 50);

              // Read available output
              while True do
              begin
                LBytesAvailable := 0;
                if not PeekNamedPipe(LOutputReadSide, nil, 0, nil, @LBytesAvailable, nil) then
                  Break;

                if LBytesAvailable = 0 then
                  Break;

                LBytesRead := 0;
                if not ReadFile(LOutputReadSide, LBuffer[0], CReadBuffer - 1, LBytesRead, nil) then
                  Break;

                if LBytesRead = 0 then
                  Break;

                DoEmitChunk(LBytesRead);
              end;

              ProcessMessages();
            until LRunning <> WAIT_TIMEOUT;

            // The program ended: no more keys or sizes for its terminal
            if AHost <> nil then
              AHost.Stop();

            // The pseudoconsole writes out what it still holds and breaks its
            // output pipe as it closes: it is closed on a thread of its own
            // (an older Windows waits in ClosePseudoConsole for that drain)
            // while this one reads to the broken pipe. Nothing is lost to
            // timing: no sleeps, no "empty now = the end"
            LClosing := LPseudoConsole;
            LCloser := TThread.CreateAnonymousThread(
              procedure
              begin
                ClosePseudoConsole(LClosing);
              end);
            LCloser.FreeOnTerminate := False;
            LPseudoConsole := 0;
            LCloser.Start();
            try
              repeat
                LBytesRead := 0;
                if not ReadFile(LOutputReadSide, LBuffer[0], CReadBuffer - 1, LBytesRead, nil) then
                  Break;
                if LBytesRead > 0 then
                  DoEmitChunk(LBytesRead);
              until False;
            finally
              LCloser.WaitFor();
              LCloser.Free();
            end;

            // A sequence still held back at exit is truncated output; hand it
            // over as it is rather than drop it
            if (LPending <> '') and Assigned(ACallback) then
              ACallback(UTF8ToString(LPending), AUserData);

            // Get exit code
            if GetExitCodeProcess(LProcessInfo.hProcess, LExitCode) then
              AExitCode := LExitCode;
          finally
            CloseHandle(LProcessInfo.hProcess);
            CloseHandle(LProcessInfo.hThread);
          end;
        finally
          // A run that ended early (it raised) stops its host here
          if AHost <> nil then
            AHost.Stop();
        end;
      finally
        DeleteProcThreadAttributeList(LAttrList);
      end;
    finally
      // Closed above once the program ran; here when it never did
      if LPseudoConsole <> 0 then
        ClosePseudoConsole(LPseudoConsole);
    end;
  finally
    if LAttrList <> nil then
      FreeMem(LAttrList);
    if LInputReadSide <> 0 then
      CloseHandle(LInputReadSide);
    if LInputWriteSide <> 0 then
      CloseHandle(LInputWriteSide);
    if LOutputReadSide <> 0 then
      CloseHandle(LOutputReadSide);
    if LOutputWriteSide <> 0 then
      CloseHandle(LOutputWriteSide);
    // The program holds its own copy of its stdin
    if LChildInput <> 0 then
      CloseHandle(LChildInput);
  end;
end;

class function TUtils.CreateProcessWithPipes(const AExe, AParams, AWorkDir: string; out AStdinWrite: THandle; out AStdoutRead: THandle; out AProcessHandle: THandle; out AThreadHandle: THandle): Boolean;
var
  LSA: TSecurityAttributes;
  LStdinReadChild: THandle;
  LStdoutWriteChild: THandle;
  LSI: TStartupInfoW;
  LPI: TProcessInformation;
  LCmdLine: UnicodeString;
  LWorkDirPW: PWideChar;
begin
  Result := False;
  AStdinWrite := INVALID_HANDLE_VALUE;
  AStdoutRead := INVALID_HANDLE_VALUE;
  AProcessHandle := INVALID_HANDLE_VALUE;
  AThreadHandle := INVALID_HANDLE_VALUE;
  LStdinReadChild := INVALID_HANDLE_VALUE;
  LStdoutWriteChild := INVALID_HANDLE_VALUE;

  // Set up security attributes for inheritable handles
  LSA.nLength := SizeOf(TSecurityAttributes);
  LSA.bInheritHandle := True;
  LSA.lpSecurityDescriptor := nil;

  // Create pipe for child's stdin (parent writes, child reads)
  if not CreatePipe(LStdinReadChild, AStdinWrite, @LSA, 0) then
    Exit;

  // Create pipe for child's stdout (child writes, parent reads)
  if not CreatePipe(AStdoutRead, LStdoutWriteChild, @LSA, 0) then
  begin
    CloseHandle(LStdinReadChild);
    CloseHandle(AStdinWrite);
    AStdinWrite := INVALID_HANDLE_VALUE;
    Exit;
  end;

  // Ensure parent-side handles are NOT inherited by the child
  SetHandleInformation(AStdinWrite, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(AStdoutRead, HANDLE_FLAG_INHERIT, 0);

  // Set up startup info with redirected standard handles
  ZeroMemory(@LSI, SizeOf(LSI));
  LSI.cb := SizeOf(LSI);
  LSI.hStdInput := LStdinReadChild;
  LSI.hStdOutput := LStdoutWriteChild;
  LSI.hStdError := LStdoutWriteChild;
  LSI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  LSI.wShowWindow := SW_HIDE;

  // Build command line
  if AParams <> '' then
    LCmdLine := '"' + AExe + '" ' + AParams
  else
    LCmdLine := '"' + AExe + '"';
  UniqueString(LCmdLine);

  if AWorkDir <> '' then
    LWorkDirPW := PWideChar(AWorkDir)
  else
    LWorkDirPW := nil;

  ZeroMemory(@LPI, SizeOf(LPI));

  if not CreateProcessW(
    nil,
    PWideChar(LCmdLine),
    nil,
    nil,
    True,
    CREATE_UNICODE_ENVIRONMENT or CREATE_NO_WINDOW,
    nil,
    LWorkDirPW,
    LSI,
    LPI
  ) then
  begin
    CloseHandle(LStdinReadChild);
    CloseHandle(LStdoutWriteChild);
    CloseHandle(AStdinWrite);
    CloseHandle(AStdoutRead);
    AStdinWrite := INVALID_HANDLE_VALUE;
    AStdoutRead := INVALID_HANDLE_VALUE;
    Exit;
  end;

  // Close child-side pipe handles (child process has its own copies)
  CloseHandle(LStdinReadChild);
  CloseHandle(LStdoutWriteChild);

  AProcessHandle := LPI.hProcess;
  AThreadHandle := LPI.hThread;
  Result := True;
end;

class function TUtils.CreateDirInPath(const AFilename: string): Boolean;
var
  LResolved: string;
begin
  // AFilename names a file, with or without an extension ('Makefile',
  // 'out.v1/data'): its directory is created. A directory itself goes
  // through EnsureDirectory - an extension says nothing about which it is.
  // An empty name is False before TPath.GetDirectoryName, which raises on it.
  LResolved := TUtils.ResolvePath(AFilename);
  if LResolved.IsEmpty() then
    Exit(False);

  Result := EnsureDirectory(TPath.GetDirectoryName(LResolved));
end;

class function TUtils.EnsureDirectory(const ADirectory: string): Boolean;
var
  LPath: string;
begin
  // False only for an empty path; a directory that cannot be created raises
  // (TDirectory.CreateDirectory), as CreateDirInPath always did
  LPath := TUtils.ResolvePath(ADirectory);
  if LPath.IsEmpty() then
    Exit(False);

  if not TDirectory.Exists(LPath) then
    TDirectory.CreateDirectory(LPath);

  Result := True;
end;

class procedure TUtils.CopyFilePreservingEncoding(const ASourceFile, ADestFile: string);
var
  LSourceBytes: TBytes;
begin
  // Validate source file exists
  if not TFile.Exists(ASourceFile) then
    raise Exception.CreateFmt('CopyFilePreservingEncoding: Source file not found: %s', [ASourceFile]);

  // Ensure destination directory exists
  CreateDirInPath(ADestFile);

  // Read all bytes from source file
  LSourceBytes := TFile.ReadAllBytes(ASourceFile);

  // Write bytes to destination - this preserves EVERYTHING including BOM
  TFile.WriteAllBytes(ADestFile, LSourceBytes);
end;

class function TUtils.DetectFileEncoding(const AFilePath: string): TEncoding;
var
  LBytes: TBytes;
  LEncoding: TEncoding;
begin
  // Validate file exists
  if not TFile.Exists(AFilePath) then
    raise Exception.CreateFmt('DetectFileEncoding: File not found: %s', [AFilePath]);

  // Read a sample of bytes (first 4KB should be enough for BOM detection)
  LBytes := TFile.ReadAllBytes(AFilePath);

  if Length(LBytes) = 0 then
    Exit(TEncoding.Default);

  // Let TEncoding detect the encoding from BOM
  LEncoding := nil;
  TEncoding.GetBufferEncoding(LBytes, LEncoding, TEncoding.Default);

  Result := LEncoding;
end;

class function TUtils.EnsureBOM(const AText: string): string;
const
  UTF16_BOM = #$FEFF;
begin
  Result := AText;
  if (Length(Result) = 0) or (Result[1] <> UTF16_BOM) then
    Result := UTF16_BOM + Result;
end;

class function TUtils.EscapeString(const AText: string): string;
var
  LI: Integer;
  LChar: Char;
  LNextChar: Char;
begin
  Result := '';
  LI := 1;

  while LI <= Length(AText) do
  begin
    LChar := AText[LI];

    case LChar of
      #13: // Carriage return
        begin
          Result := Result + '\r';
          Inc(LI);
        end;
      #10: // Line feed
        begin
          Result := Result + '\n';
          Inc(LI);
        end;
      #9: // Tab
        begin
          Result := Result + '\t';
          Inc(LI);
        end;
      '"': // Quote
        begin
          Result := Result + '\"';
          Inc(LI);
        end;
      '\': // Backslash - requires look-ahead
        begin
          if LI < Length(AText) then
          begin
            LNextChar := AText[LI + 1];

            // Preserve valid C++ escape sequences: \x (hex), \n, \r, \t, \", \\
            if CharInSet(LNextChar, ['x', 'n', 'r', 't', '"', '\']) then
              Result := Result + '\'  // Valid C++ escape sequence - preserve the backslash
            else
              Result := Result + '\\'; // Not a recognized escape - escape the backslash
          end
          else
            Result := Result + '\\'; // Backslash at end of string - escape it

          Inc(LI);
        end;
    else
      // Regular character - append as-is
      Result := Result + LChar;
      Inc(LI);
    end;
  end;
end;

class function TUtils.StripAnsi(const AText: string): string;
var
  LResult: TStringBuilder;
  LIdx: Integer;
  LLen: Integer;
  LInEscape: Boolean;
begin
  LResult := TStringBuilder.Create();
  try
    LLen := Length(AText);
    LIdx := 1;
    LInEscape := False;
    while LIdx <= LLen do
    begin
      if LInEscape then
      begin
        if CharInSet(AText[LIdx], ['A'..'Z', 'a'..'z', '~']) then
          LInEscape := False;
      end
      else if AText[LIdx] = #27 then
        LInEscape := True
      else
        LResult.Append(AText[LIdx]);
      Inc(LIdx);
    end;
    Result := LResult.ToString();
  finally
    LResult.Free();
  end;
end;

class function TUtils.ExtractAnsiCodes(const AText: string): string;
var
  LResult: TStringBuilder;
  LIdx: Integer;
  LLen: Integer;
  LInEscape: Boolean;
begin
  LResult := TStringBuilder.Create();
  try
    LLen := Length(AText);
    LIdx := 1;
    LInEscape := False;
    while LIdx <= LLen do
    begin
      if LInEscape then
      begin
        LResult.Append(AText[LIdx]);
        if CharInSet(AText[LIdx], ['A'..'Z', 'a'..'z', '~']) then
          LInEscape := False;
      end
      else if AText[LIdx] = #27 then
      begin
        LInEscape := True;
        LResult.Append(AText[LIdx]);
      end;
      Inc(LIdx);
    end;
    Result := LResult.ToString();
  finally
    LResult.Free();
  end;
end;

class function TUtils.GetVersionInfo(out AVersionInfo: TVersionInfo; const AFilePath: string): Boolean;
var
  LFileName: string;
  LInfoSize: DWORD;
  LHandle: DWORD;
  LBuffer: Pointer;
  LFileInfo: PVSFixedFileInfo;
  LLen: UINT;
  LStrValue: PChar;
  LStrLen: UINT;
  LTranslation: Pointer;
  LTransLen: UINT;
  LCodePage: string;

  function ReadStringValue(const AKey: string): string;
  begin
    Result := '';
    if VerQueryValue(LBuffer,
       PChar('\StringFileInfo\' + LCodePage + '\' + AKey),
       Pointer(LStrValue), LStrLen) and (LStrLen > 0) then
      Result := LStrValue;
  end;

begin
  // Initialize output
  AVersionInfo.Major := 0;
  AVersionInfo.Minor := 0;
  AVersionInfo.Patch := 0;
  AVersionInfo.Build := 0;
  AVersionInfo.VersionString := '';
  AVersionInfo.ProductName := '';
  AVersionInfo.CompanyName := '';
  AVersionInfo.Copyright := '';
  AVersionInfo.Description := '';
  AVersionInfo.URL := '';

  // Determine which file to query
  if AFilePath = '' then
    LFileName := ParamStr(0)
  else
    LFileName := AFilePath;

  // Get version info size
  LInfoSize := GetFileVersionInfoSize(PChar(LFileName), LHandle);
  if LInfoSize = 0 then
    Exit(False);

  // Allocate buffer and get version info
  GetMem(LBuffer, LInfoSize);
  try
    if not GetFileVersionInfo(PChar(LFileName), LHandle, LInfoSize, LBuffer) then
      Exit(False);

    // Query fixed file info
    if not VerQueryValue(LBuffer, '\', Pointer(LFileInfo), LLen) then
      Exit(False);

    // Extract version components
    AVersionInfo.Major := HiWord(LFileInfo.dwFileVersionMS);
    AVersionInfo.Minor := LoWord(LFileInfo.dwFileVersionMS);
    AVersionInfo.Patch := HiWord(LFileInfo.dwFileVersionLS);
    AVersionInfo.Build := LoWord(LFileInfo.dwFileVersionLS);

    // Detect language/codepage from translation table
    LCodePage := '040904B0'; // fallback
    if VerQueryValue(LBuffer, '\VarFileInfo\Translation', LTranslation, LTransLen) and
       (LTransLen >= 4) then
      LCodePage := Format('%.4x%.4x', [PWordArray(LTranslation)[0], PWordArray(LTranslation)[1]]);

    // Format version string (Major.Minor.Patch)
    AVersionInfo.VersionString := Format('%d.%d.%d', [AVersionInfo.Major, AVersionInfo.Minor, AVersionInfo.Patch]);

    // Read string table entries
    AVersionInfo.ProductName := ReadStringValue('ProductName');
    AVersionInfo.CompanyName := ReadStringValue('CompanyName');
    AVersionInfo.Copyright := ReadStringValue('LegalCopyright');
    AVersionInfo.Description := ReadStringValue('FileDescription');
    AVersionInfo.URL := ReadStringValue('Comments');

    Result := True;
  finally
    FreeMem(LBuffer);
  end;
end;

class function TUtils.GetModuleVersionString(const AModule: HMODULE): string;
var
  LPath: array[0..MAX_PATH] of Char;
  LInfo: TVersionInfo;
begin
  if (GetModuleFileName(AModule, LPath, MAX_PATH + 1) > 0) and
     GetVersionInfo(LInfo, LPath) then
    Result := LInfo.VersionString
  else
    Result := '0.0.0';
end;

class function TUtils.IsValidWin64PE(const AFilePath: string): Boolean;
var
  LFile: TFileStream;
  LDosHeader: TImageDosHeader;
  LPEHeaderOffset: DWORD;
  LPEHeaderSignature: DWORD;
  LFileHeader: TImageFileHeader;
begin
  Result := False;

  if not FileExists(AFilePath) then
    Exit;

  LFile := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyWrite);
  try
    // Check if file is large enough for DOS header
    if LFile.Size < SizeOf(TImageDosHeader) then
      Exit;

    // Read DOS header
    LFile.ReadBuffer(LDosHeader, SizeOf(TImageDosHeader));

    // Check DOS signature
    if LDosHeader.e_magic <> IMAGE_DOS_SIGNATURE then
      Exit;

    // Validate PE header offset
    LPEHeaderOffset := LDosHeader._lfanew;
    if LFile.Size < LPEHeaderOffset + SizeOf(DWORD) + SizeOf(TImageFileHeader) then
      Exit;

    // Seek to the PE header
    LFile.Position := LPEHeaderOffset;

    // Read and validate the PE signature
    LFile.ReadBuffer(LPEHeaderSignature, SizeOf(DWORD));
    if LPEHeaderSignature <> IMAGE_NT_SIGNATURE then
      Exit;

    // Read the file header
    LFile.ReadBuffer(LFileHeader, SizeOf(TImageFileHeader));

    // Check if it is a 64-bit executable
    if LFileHeader.Machine <> IMAGE_FILE_MACHINE_AMD64 then
      Exit;

    // All checks passed
    Result := True;
  finally
    LFile.Free();
  end;
end;

class procedure TUtils.UpdateIconResource(const AExeFilePath, AIconFilePath: string);
type
  TIconDir = packed record
    idReserved: Word;
    idType: Word;
    idCount: Word;
  end;
  PIconDir = ^TIconDir;

  TGroupIconDirEntry = packed record
    bWidth: Byte;
    bHeight: Byte;
    bColorCount: Byte;
    bReserved: Byte;
    wPlanes: Word;
    wBitCount: Word;
    dwBytesInRes: Cardinal;
    nID: Word;
  end;

  TIconResInfo = packed record
    bWidth: Byte;
    bHeight: Byte;
    bColorCount: Byte;
    bReserved: Byte;
    wPlanes: Word;
    wBitCount: Word;
    dwBytesInRes: Cardinal;
    dwImageOffset: Cardinal;
  end;
  PIconResInfo = ^TIconResInfo;

var
  LIconStream: TMemoryStream;
  LIconDir: PIconDir;
  LIconGroup: TMemoryStream;
  LIconRes: PByte;
  LI: Integer;
  LImageEnd: Int64;
begin
  if not FileExists(AExeFilePath) then
    raise Exception.Create('The specified executable file does not exist.');

  if not FileExists(AIconFilePath) then
    raise Exception.Create('The specified icon file does not exist.');

  LIconStream := TMemoryStream.Create();
  LIconGroup := TMemoryStream.Create();
  try
    // Load the icon file
    LIconStream.LoadFromFile(AIconFilePath);

    // Validate the whole .ico before the executable is touched: every read
    // below stays inside the loaded bytes
    if LIconStream.Size < SizeOf(TIconDir) then
      raise Exception.Create('Invalid icon file: too short for its header.');

    // Read the ICONDIR structure from the icon file (idType 1 = icon; 2 is a cursor)
    LIconDir := PIconDir(LIconStream.Memory);
    if (LIconDir^.idReserved <> 0) or (LIconDir^.idType <> 1) then
      raise Exception.Create('Invalid icon file: not an icon (.ico) file.');
    if LIconDir^.idCount = 0 then
      raise Exception.Create('Invalid icon file: it holds no images.');
    if LIconStream.Size < SizeOf(TIconDir) + Int64(LIconDir^.idCount) * SizeOf(TIconResInfo) then
      raise Exception.Create('Invalid icon file: its image directory is truncated.');

    // Every image must lie inside the file
    LIconRes := PByte(LIconStream.Memory) + SizeOf(TIconDir);
    for LI := 0 to LIconDir^.idCount - 1 do
    begin
      LImageEnd := Int64(PIconResInfo(LIconRes)^.dwImageOffset) +
        Int64(PIconResInfo(LIconRes)^.dwBytesInRes);
      if (PIconResInfo(LIconRes)^.dwBytesInRes = 0) or (LImageEnd > LIconStream.Size) then
        raise Exception.CreateFmt('Invalid icon file: image %d lies outside the file.', [LI]);
      Inc(LIconRes, SizeOf(TIconResInfo));
    end;

    // Update the executable's resources: DoUpdateResources hands over a path
    // the resource API takes (a temp copy past PATH_RESOURCE_MAX)
    DoUpdateResources(AExeFilePath,
      procedure(const AWorkPath: string)
      var
        LUpdateHandle: THandle;
        LRes: PByte;
        LIdx: Integer;
        LIconID: Word;
        LGroupEntry: TGroupIconDirEntry;
      begin
        LUpdateHandle := BeginUpdateResource(PChar(AWorkPath), False);
        if LUpdateHandle = 0 then
          RaiseLastOSError();

        try
          // Process each icon image in the .ico file
          LRes := PByte(LIconStream.Memory) + SizeOf(TIconDir);
          for LIdx := 0 to LIconDir^.idCount - 1 do
          begin
            // Assign a unique resource ID for the RT_ICON
            LIconID := LIdx + 1;

            // Add the icon image data as an RT_ICON resource
            if not UpdateResource(LUpdateHandle, RT_ICON, PChar(LIconID), LANG_NEUTRAL,
              Pointer(PByte(LIconStream.Memory) + PIconResInfo(LRes)^.dwImageOffset),
              PIconResInfo(LRes)^.dwBytesInRes) then
              raise Exception.CreateFmt('Failed to add RT_ICON resource for image %d: %s',
                [LIdx, SysErrorMessage(GetLastError())]);

            // Move to the next icon entry
            Inc(LRes, SizeOf(TIconResInfo));
          end;

          // Create the GROUP_ICON resource
          LIconGroup.Clear();
          LIconGroup.Write(LIconDir^, SizeOf(TIconDir));

          LRes := PByte(LIconStream.Memory) + SizeOf(TIconDir);
          // Write each GROUP_ICON entry
          for LIdx := 0 to LIconDir^.idCount - 1 do
          begin
            LGroupEntry.bWidth := PIconResInfo(LRes)^.bWidth;
            LGroupEntry.bHeight := PIconResInfo(LRes)^.bHeight;
            LGroupEntry.bColorCount := PIconResInfo(LRes)^.bColorCount;
            LGroupEntry.bReserved := 0;
            LGroupEntry.wPlanes := PIconResInfo(LRes)^.wPlanes;
            LGroupEntry.wBitCount := PIconResInfo(LRes)^.wBitCount;
            LGroupEntry.dwBytesInRes := PIconResInfo(LRes)^.dwBytesInRes;
            LGroupEntry.nID := LIdx + 1;

            LIconGroup.Write(LGroupEntry, SizeOf(TGroupIconDirEntry));

            Inc(LRes, SizeOf(TIconResInfo));
          end;

          // Add the GROUP_ICON resource to the executable
          if not UpdateResource(LUpdateHandle, RT_GROUP_ICON, 'MAINICON', LANG_NEUTRAL,
            LIconGroup.Memory, LIconGroup.Size) then
            raise Exception.CreateFmt('Failed to add RT_GROUP_ICON resource: %s',
              [SysErrorMessage(GetLastError())]);
        except
          EndUpdateResource(LUpdateHandle, True); // Discard changes on failure
          raise;
        end;

        // Commit the resource updates: the one EndUpdateResource for this
        // handle; the discard above runs only when the commit was never reached
        if not EndUpdateResource(LUpdateHandle, False) then
          RaiseLastOSError();
      end);
  finally
    LIconStream.Free();
    LIconGroup.Free();
  end;
end;

class procedure TUtils.UpdateVersionInfoResource(const APEFilePath: string; const AMajor, AMinor, APatch: Word; const AProductName, ADescription, AFilename, ACompanyName, ACopyright: string; const AURL: string);
type
  TVSFixedFileInfo = packed record
    dwSignature: DWORD;
    dwStrucVersion: DWORD;
    dwFileVersionMS: DWORD;
    dwFileVersionLS: DWORD;
    dwProductVersionMS: DWORD;
    dwProductVersionLS: DWORD;
    dwFileFlagsMask: DWORD;
    dwFileFlags: DWORD;
    dwFileOS: DWORD;
    dwFileType: DWORD;
    dwFileSubtype: DWORD;
    dwFileDateMS: DWORD;
    dwFileDateLS: DWORD;
  end;

  TCbrStringPair = record
    Key: string;
    Value: string;
  end;

var
  LVersionInfoStream: TMemoryStream;
  LFixedInfo: TVSFixedFileInfo;
  LDataPtr: Pointer;
  LDataSize: Integer;
  LStringFileInfoStart: Int64;
  LStringTableStart: Int64;
  LVarFileInfoStart: Int64;
  LStringPairs: array of TCbrStringPair;
  LVersion: string;
  LMajor: Word;
  LMinor: Word;
  LPatch: Word;
  LVSVersionInfoStart: Int64;
  LPair: TCbrStringPair;
  LStringInfoEnd: Int64;
  LStringStart: Int64;
  LStringEnd: Int64;
  LFinalPos: Int64;
  LTranslationStart: Int64;

  procedure AlignStream(const AStream: TMemoryStream; const AAlignment: Integer);
  var
    LPadding: Integer;
    LPadByte: Byte;
  begin
    LPadding := (AAlignment - (AStream.Position mod AAlignment)) mod AAlignment;
    LPadByte := 0;
    while LPadding > 0 do
    begin
      AStream.WriteBuffer(LPadByte, 1);
      Dec(LPadding);
    end;
  end;

  procedure WriteWideString(const AStream: TMemoryStream; const AText: string);
  var
    LWideText: WideString;
  begin
    LWideText := WideString(AText);
    AStream.WriteBuffer(PWideChar(LWideText)^, (Length(LWideText) + 1) * SizeOf(WideChar));
  end;

  procedure SetFileVersionFromString(const AVersion: string; out AFileVersionMS, AFileVersionLS: DWORD);
  var
    LVersionParts: TArray<string>;
    LVerMajor: Word;
    LVerMinor: Word;
    LVerBuild: Word;
    LVerRevision: Word;
  begin
    LVersionParts := AVersion.Split(['.']);
    if Length(LVersionParts) <> 4 then
      raise Exception.Create('Invalid version string format. Expected "Major.Minor.Build.Revision".');

    LVerMajor    := StrToIntDef(LVersionParts[0], 0);
    LVerMinor    := StrToIntDef(LVersionParts[1], 0);
    LVerBuild    := StrToIntDef(LVersionParts[2], 0);
    LVerRevision := StrToIntDef(LVersionParts[3], 0);

    AFileVersionMS := (DWORD(LVerMajor) shl 16) or DWORD(LVerMinor);
    AFileVersionLS := (DWORD(LVerBuild) shl 16) or DWORD(LVerRevision);
  end;

  function IsDllImage(const APath: string): Boolean;
  var
    LFile: TFileStream;
    LDosHeader: TImageDosHeader;
    LSignature: DWORD;
    LFileHeader: TImageFileHeader;
  begin
    // The file type comes from the image itself: IMAGE_FILE_DLL in the COFF
    // file header, never from the file name
    LFile := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
    try
      if LFile.Size < SizeOf(TImageDosHeader) then
        raise Exception.Create('Not a PE image: too short for its DOS header.');
      LFile.ReadBuffer(LDosHeader, SizeOf(TImageDosHeader));
      if LDosHeader.e_magic <> IMAGE_DOS_SIGNATURE then
        raise Exception.Create('Not a PE image: no DOS signature.');
      if (LDosHeader._lfanew < 0) or
        (LFile.Size < Int64(LDosHeader._lfanew) + SizeOf(DWORD) + SizeOf(TImageFileHeader)) then
        raise Exception.Create('Not a PE image: PE header out of range.');
      LFile.Position := LDosHeader._lfanew;
      LFile.ReadBuffer(LSignature, SizeOf(DWORD));
      if LSignature <> IMAGE_NT_SIGNATURE then
        raise Exception.Create('Not a PE image: no PE signature.');
      LFile.ReadBuffer(LFileHeader, SizeOf(TImageFileHeader));
      Result := (LFileHeader.Characteristics and IMAGE_FILE_DLL) <> 0;
    finally
      LFile.Free();
    end;
  end;

begin
  LMajor := EnsureRange(AMajor, 0, MaxWord);
  LMinor := EnsureRange(AMinor, 0, MaxWord);
  LPatch := EnsureRange(APatch, 0, MaxWord);
  LVersion := Format('%d.%d.%d.0', [LMajor, LMinor, LPatch]);

  SetLength(LStringPairs, 9);
  LStringPairs[0].Key := 'Comments';         LStringPairs[0].Value := AURL;
  LStringPairs[1].Key := 'CompanyName';      LStringPairs[1].Value := ACompanyName;
  LStringPairs[2].Key := 'FileDescription';  LStringPairs[2].Value := ADescription;
  LStringPairs[3].Key := 'FileVersion';      LStringPairs[3].Value := LVersion;
  // InternalName is the module name: the original filename without extension
  LStringPairs[4].Key := 'InternalName';     LStringPairs[4].Value := TPath.GetFileNameWithoutExtension(AFilename);
  LStringPairs[5].Key := 'LegalCopyright';   LStringPairs[5].Value := ACopyright;
  LStringPairs[6].Key := 'OriginalFilename'; LStringPairs[6].Value := AFilename;
  LStringPairs[7].Key := 'ProductName';      LStringPairs[7].Value := AProductName;
  LStringPairs[8].Key := 'ProductVersion';   LStringPairs[8].Value := LVersion;

  // Initialize fixed info structure
  FillChar(LFixedInfo, SizeOf(LFixedInfo), 0);
  LFixedInfo.dwSignature       := $FEEF04BD;
  LFixedInfo.dwStrucVersion    := $00010000;
  LFixedInfo.dwFileVersionMS   := $00010000;
  LFixedInfo.dwFileVersionLS   := $00000000;
  LFixedInfo.dwProductVersionMS:= $00010000;
  LFixedInfo.dwProductVersionLS:= $00000000;
  LFixedInfo.dwFileFlagsMask   := $3F;
  LFixedInfo.dwFileFlags       := 0;
  LFixedInfo.dwFileOS          := VOS_NT_WINDOWS32;
  if IsDllImage(APEFilePath) then
    LFixedInfo.dwFileType      := VFT_DLL
  else
    LFixedInfo.dwFileType      := VFT_APP;
  LFixedInfo.dwFileSubtype     := 0;
  LFixedInfo.dwFileDateMS      := 0;
  LFixedInfo.dwFileDateLS      := 0;

  SetFileVersionFromString(LVersion, LFixedInfo.dwFileVersionMS,    LFixedInfo.dwFileVersionLS);
  SetFileVersionFromString(LVersion, LFixedInfo.dwProductVersionMS, LFixedInfo.dwProductVersionLS);

  LVersionInfoStream := TMemoryStream.Create();
  try
    // VS_VERSION_INFO
    LVSVersionInfoStart := LVersionInfoStream.Position;

    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(SizeOf(TVSFixedFileInfo));
    LVersionInfoStream.WriteData<Word>(0);
    WriteWideString(LVersionInfoStream, 'VS_VERSION_INFO');
    AlignStream(LVersionInfoStream, 4);

    // VS_FIXEDFILEINFO
    LVersionInfoStream.WriteBuffer(LFixedInfo, SizeOf(TVSFixedFileInfo));
    AlignStream(LVersionInfoStream, 4);

    // StringFileInfo
    LStringFileInfoStart := LVersionInfoStream.Position;
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(1);
    WriteWideString(LVersionInfoStream, 'StringFileInfo');
    AlignStream(LVersionInfoStream, 4);

    // StringTable
    LStringTableStart := LVersionInfoStream.Position;
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(1);
    WriteWideString(LVersionInfoStream, '040904B0'); // Match Delphi's default code page
    AlignStream(LVersionInfoStream, 4);

    // Write string pairs
    for LPair in LStringPairs do
    begin
      LStringStart := LVersionInfoStream.Position;

      LVersionInfoStream.WriteData<Word>(0);
      // String.wValueLength counts WORDs (UTF-16 units incl. the null), not bytes
      LVersionInfoStream.WriteData<Word>(Length(LPair.Value) + 1);
      LVersionInfoStream.WriteData<Word>(1);
      WriteWideString(LVersionInfoStream, LPair.Key);
      AlignStream(LVersionInfoStream, 4);
      WriteWideString(LVersionInfoStream, LPair.Value);
      AlignStream(LVersionInfoStream, 4);

      LStringEnd := LVersionInfoStream.Position;
      LVersionInfoStream.Position := LStringStart;
      LVersionInfoStream.WriteData<Word>(LStringEnd - LStringStart);
      LVersionInfoStream.Position := LStringEnd;
    end;

    LStringInfoEnd := LVersionInfoStream.Position;

    // Write StringTable length
    LVersionInfoStream.Position := LStringTableStart;
    LVersionInfoStream.WriteData<Word>(LStringInfoEnd - LStringTableStart);

    // Write StringFileInfo length
    LVersionInfoStream.Position := LStringFileInfoStart;
    LVersionInfoStream.WriteData<Word>(LStringInfoEnd - LStringFileInfoStart);

    // Start VarFileInfo where StringFileInfo ended
    LVarFileInfoStart := LStringInfoEnd;
    LVersionInfoStream.Position := LVarFileInfoStart;

    // VarFileInfo header
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(1);
    WriteWideString(LVersionInfoStream, 'VarFileInfo');
    AlignStream(LVersionInfoStream, 4);

    // Translation value block
    LTranslationStart := LVersionInfoStream.Position;
    LVersionInfoStream.WriteData<Word>(0);
    LVersionInfoStream.WriteData<Word>(4);
    LVersionInfoStream.WriteData<Word>(0);
    WriteWideString(LVersionInfoStream, 'Translation');
    AlignStream(LVersionInfoStream, 4);

    // Write translation value
    LVersionInfoStream.WriteData<Word>($0409); // Language ID (US English)
    LVersionInfoStream.WriteData<Word>($04B0); // Unicode code page

    LFinalPos := LVersionInfoStream.Position;

    // Update VarFileInfo block length
    LVersionInfoStream.Position := LVarFileInfoStart;
    LVersionInfoStream.WriteData<Word>(LFinalPos - LVarFileInfoStart);

    // Update translation block length
    LVersionInfoStream.Position := LTranslationStart;
    LVersionInfoStream.WriteData<Word>(LFinalPos - LTranslationStart);

    // Update total version info length
    LVersionInfoStream.Position := LVSVersionInfoStart;
    LVersionInfoStream.WriteData<Word>(LFinalPos);

    LDataPtr := LVersionInfoStream.Memory;
    LDataSize := LVersionInfoStream.Size;

    // Update the resource: DoUpdateResources hands over a path the resource
    // API takes (a temp copy past PATH_RESOURCE_MAX)
    DoUpdateResources(APEFilePath,
      procedure(const AWorkPath: string)
      var
        LHandleUpdate: THandle;
      begin
        LHandleUpdate := BeginUpdateResource(PChar(AWorkPath), False);
        if LHandleUpdate = 0 then
          RaiseLastOSError();

        try
          if not UpdateResourceW(LHandleUpdate, RT_VERSION, MAKEINTRESOURCE(1),
             MAKELANGID(LANG_NEUTRAL, SUBLANG_NEUTRAL), LDataPtr, LDataSize) then
            RaiseLastOSError();
        except
          EndUpdateResource(LHandleUpdate, True);
          raise;
        end;

        // The one EndUpdateResource for this handle: commit
        if not EndUpdateResource(LHandleUpdate, False) then
          RaiseLastOSError();
      end);
  finally
    LVersionInfoStream.Free();
  end;
end;

class function TUtils.ResourceExist(const AResName: string): Boolean;
begin
  Result := Boolean((FindResource(HInstance, PChar(AResName), RT_RCDATA) <> 0));
end;

class function TUtils.AddResManifestFromResource(const AResName: string; const AModuleFile: string; const ALanguage: Integer): Boolean;
var
  LErrorMessage: string;
begin
  Result := AddResManifestFromResource(AResName, AModuleFile, LErrorMessage, ALanguage);
end;

class function TUtils.AddResManifestFromResource(const AResName: string; const AModuleFile: string; out AErrorMessage: string; const ALanguage: Integer): Boolean;
var
  LManifestStream: TResourceStream;
begin
  // Never raises: False with AErrorMessage set on any failure, including a
  // failed commit (the manifest is in the file only once EndUpdateResource succeeds)
  Result := False;
  AErrorMessage := '';
  LManifestStream := nil;
  try
    try
      if not ResourceExist(AResName) then
      begin
        AErrorMessage := Format('Resource %s not found.', [AResName]);
        Exit;
      end;
      if not TFile.Exists(AModuleFile) then
      begin
        AErrorMessage := Format('File not found: %s', [AModuleFile]);
        Exit;
      end;

      LManifestStream := TResourceStream.Create(HInstance, AResName, RT_RCDATA);

      // DoUpdateResources hands over a path the resource API takes (a temp
      // copy past PATH_RESOURCE_MAX); every failure in it raises its reason
      DoUpdateResources(AModuleFile,
        procedure(const AWorkPath: string)
        var
          LHandle: THandle;
          LCode: DWORD;
        begin
          LHandle := WinAPI.Windows.BeginUpdateResourceW(System.PWideChar(AWorkPath), LongBool(False));
          if LHandle = 0 then
            DoRaiseOSError(GetLastError());

          if not WinAPI.Windows.UpdateResourceW(LHandle, RT_MANIFEST, CREATEPROCESS_MANIFEST_RESOURCE_ID,
            ALanguage, LManifestStream.Memory, LManifestStream.Size) then
          begin
            // Read the reason before the discard call can overwrite it
            LCode := GetLastError();
            WinAPI.Windows.EndUpdateResourceW(LHandle, True);
            DoRaiseOSError(LCode);
          end;

          if not WinAPI.Windows.EndUpdateResourceW(LHandle, False) then
            DoRaiseOSError(GetLastError());
        end);

      Result := True;
    except
      on E: Exception do
        AErrorMessage := E.Message;
    end;
  finally
    LManifestStream.Free();
  end;
end;

class procedure TUtils.UpdateRCDataResource(const AExeFilePath: string;
  const AResourceName: string; const AData: TStream);
var
  LBuffer: TMemoryStream;
begin
  // Copy stream data to a memory buffer for UpdateResource
  LBuffer := TMemoryStream.Create();
  try
    AData.Position := 0;
    LBuffer.CopyFrom(AData, AData.Size);

    // DoUpdateResources hands over a path the resource API takes (a temp
    // copy past PATH_RESOURCE_MAX)
    DoUpdateResources(AExeFilePath,
      procedure(const AWorkPath: string)
      var
        LHandleUpdate: THandle;
      begin
        LHandleUpdate := BeginUpdateResource(PChar(AWorkPath), False);
        if LHandleUpdate = 0 then
          RaiseLastOSError();

        try
          if not UpdateResourceW(LHandleUpdate, RT_RCDATA,
             PChar(AResourceName), MAKELANGID(LANG_NEUTRAL, SUBLANG_NEUTRAL),
             LBuffer.Memory, LBuffer.Size) then
            RaiseLastOSError();
        except
          EndUpdateResource(LHandleUpdate, True);
          raise;
        end;

        // The one EndUpdateResource for this handle: commit
        if not EndUpdateResource(LHandleUpdate, False) then
          RaiseLastOSError();
      end);
  finally
    LBuffer.Free();
  end;
end;

class function TUtils.GetFileSHA256(const APath: string): string;
begin
  Result := THashSHA2.GetHashStringFromFile(APath).ToLower();
end;

class function TUtils.GetRelativePath(const ABasePath, AFullPath: string): string;
var
  LBasePath: string;
  LFullPath: string;
  LBaseLen: Integer;
begin
  LBasePath := ABasePath.Replace('\', '/');
  LFullPath := AFullPath.Replace('\', '/');

  // Ensure base path ends with /
  if (LBasePath <> '') and not LBasePath.EndsWith('/') then
    LBasePath := LBasePath + '/';

  // If paths share a common prefix, strip it
  if LFullPath.ToLower().StartsWith(LBasePath.ToLower()) then
  begin
    LBaseLen := Length(LBasePath);
    Result := Copy(LFullPath, LBaseLen + 1, Length(LFullPath) - LBaseLen);
  end
  else
    Result := LFullPath; // Can't make relative, return with forward slashes
end;

class function TUtils.NormalizePath(const APath: string): string;
begin
  // The long-path spelling only works with backslashes (R28: //?/ is not
  // honoured by Win32): it keeps them, whichever slash it came with
  if DoIsLongPathForm(APath) then
    Result := APath.Replace('/', '\')
  else
    Result := APath.Replace(PathDelim, '/');
end;

class function TUtils.StripLongPathPrefix(const APath: string): string;
var
  LPath: string;
begin
  if not DoIsLongPathForm(APath) then
    Exit(APath);

  LPath := APath.Replace('/', '\');
  if LPath.StartsWith(PATH_LONG_UNC_PREFIX, True) then
    Result := '\\' + LPath.Substring(Length(PATH_LONG_UNC_PREFIX))
  else
    Result := LPath.Substring(Length(PATH_LONG_PREFIX));
end;

class function TUtils.SamePath(const APath1: string; const APath2: string): Boolean;
var
  LPath1: string;
  LPath2: string;
begin
  // Compared in one spelling: no long-path prefix, backslashes, no
  // trailing delimiter
  LPath1 := ExcludeTrailingPathDelimiter(StripLongPathPrefix(APath1).Replace('/', '\'));
  LPath2 := ExcludeTrailingPathDelimiter(StripLongPathPrefix(APath2).Replace('/', '\'));
  Result := SameText(LPath1, LPath2);
end;

class function TUtils.FileExistsExactCase(const AFilename: string): Boolean;
var
  LPath: string;
  LSearch: TSearchRec;
begin
  // Backslashes only: the long-path prefix (\\?\) is valid only with them,
  // and FindFirst keeps it, so long paths are looked up as given
  LPath := AFilename.Replace('/', '\');
  if not FileExists(LPath) then
    Exit(False);
  // FindFirst reports the name as the file system stores it; FileExists
  // above already ignored case. FindFirst returns an error code, never raises
  if FindFirst(LPath, faAnyFile, LSearch) <> 0 then
    Exit(False);
  try
    Result := LSearch.Name = ExtractFileName(LPath);
  finally
    FindClose(LSearch);
  end;
end;

class function TUtils.MatchFileNameCase(const AFilename: string; out AError: string): Boolean;
var
  LPath: string;
begin
  // FileExists ignores case; FileExistsExactCase and MoveFile (a case-only
  // rename of one file) report by result, so nothing here raises
  AError := '';
  LPath := AFilename.Replace('/', '\');
  if (not FileExists(LPath)) or FileExistsExactCase(LPath) then
    Exit(True);
  Result := MoveFile(PChar(LPath), PChar(LPath));
  if not Result then
    AError := SysErrorMessage(GetLastError());
end;

class function TUtils.JoinResolvedPath(const AResolvedDir: string;
  const ARelPath: string): string;
var
  LDir: string;
begin
  // Joined in backslashes, then given ResolvePath's one output form. No
  // GetFullPath: nothing here can raise or touch the file system.
  LDir := ExcludeTrailingPathDelimiter(AResolvedDir.Replace('/', '\'));
  Result := DoFinishResolvedPath(LDir + '\' + ARelPath.Replace('/', '\'));
end;

class function TUtils.QuoteCommandArg(const AArg: string): string;
var
  LI: Integer;
  LSlashes: Integer;
  LBuilder: TStringBuilder;
begin
  // Nothing that splits or quotes: as is (an empty argument still needs "")
  if (AArg <> '') and (AArg.IndexOfAny([' ', #9, #10, #11, '"']) < 0) then
    Exit(AArg);

  LBuilder := TStringBuilder.Create();
  try
    LBuilder.Append('"');
    LSlashes := 0;
    for LI := 0 to AArg.Length - 1 do
    begin
      // A run of backslashes counts only before a '"'
      if AArg.Chars[LI] = '\' then
      begin
        Inc(LSlashes);
        Continue;
      end;
      if AArg.Chars[LI] = '"' then
      begin
        // The backslashes before a quote doubled, the quote itself escaped
        LBuilder.Append('\', LSlashes * 2 + 1);
        LBuilder.Append('"');
      end
      else
      begin
        LBuilder.Append('\', LSlashes);
        LBuilder.Append(AArg.Chars[LI]);
      end;
      LSlashes := 0;
    end;
    // The backslashes before the closing quote doubled, so it stays a quote
    LBuilder.Append('\', LSlashes * 2);
    LBuilder.Append('"');
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

class function TUtils.CommandLineTail(const ACommandLine: string;
  const AIndex: Integer): string;
var
  LLen: Integer;
  LPos: Integer;
  LArg: Integer;
begin
  Result := '';
  LLen := ACommandLine.Length;
  LPos := 1;

  // Skip arguments 0..AIndex exactly as GetParamStr reads them
  for LArg := 0 to AIndex do
  begin
    // Blanks, and empty "" pairs, before an argument
    while True do
    begin
      while (LPos <= LLen) and (ACommandLine[LPos] <= ' ') do
        Inc(LPos);
      if (LPos < LLen) and (ACommandLine[LPos] = '"') and (ACommandLine[LPos + 1] = '"') then
        Inc(LPos, 2)
      else
        Break;
    end;
    if LPos > LLen then
      Exit;

    // One argument: characters above a blank; '"' opens a run that may hold
    // blanks and ends at the next '"' (or the end of the line)
    while (LPos <= LLen) and (ACommandLine[LPos] > ' ') do
    begin
      if ACommandLine[LPos] = '"' then
      begin
        Inc(LPos);
        while (LPos <= LLen) and (ACommandLine[LPos] <> '"') do
          Inc(LPos);
        if LPos <= LLen then
          Inc(LPos);
      end
      else
        Inc(LPos);
    end;
  end;

  // The tail as written, its leading blanks dropped
  while (LPos <= LLen) and (ACommandLine[LPos] <= ' ') do
    Inc(LPos);
  Result := ACommandLine.Substring(LPos - 1);
end;

class function TUtils.DisplayPath(const APath: string): string;
begin
  Result := TPath.GetFullPath(APath).Replace('\', '/');
end;

{ ResolvePath }
class function TUtils.ResolvePath(const APath: string;
  const ABaseDir: string): string;
var
  LPath: string;
  LBase: string;
begin
  LPath := APath.Trim();
  if LPath.IsEmpty() then
    Exit('');

  LBase := ABaseDir;

  // An explicit prefix overrides the caller-supplied contextual base.
  // Matched at position 1 only, so a path merely containing '$P:' further
  // along is left alone.
  if LPath.StartsWith(PATH_PREFIX_PROCESS, True) then
  begin
    LPath := LPath.Substring(Length(PATH_PREFIX_PROCESS));
    LBase := TPath.GetDirectoryName(ParamStr(0));
  end
  else if LPath.StartsWith(PATH_PREFIX_CURRENT, True) then
  begin
    LPath := LPath.Substring(Length(PATH_PREFIX_CURRENT));
    LBase := TDirectory.GetCurrentDirectory();
  end
  else if LPath.StartsWith(PATH_PREFIX_SOURCE, True) then
  begin
    // Explicit spelling of the default: keep the caller-supplied base.
    LPath := LPath.Substring(Length(PATH_PREFIX_SOURCE));
  end;

  LPath := LPath.Trim();
  if LPath.IsEmpty() then
    Exit('');

  // The long-path spelling takes backslashes only: one typed with forward
  // slashes is read as the same path (the base too)
  if DoIsLongPathForm(LPath) then
    LPath := LPath.Replace('/', '\');
  if DoIsLongPathForm(LBase) then
    LBase := LBase.Replace('/', '\');

  // Already absolute after the prefix strip. This is what makes the
  // routine idempotent and safe to call on an already-resolved path: both
  // output forms (DoFinishResolvedPath) come back unchanged.
  if TPath.IsPathRooted(LPath) then
    Exit(DoFinishResolvedPath(TPath.GetFullPath(LPath)));

  if LBase.IsEmpty() then
    LBase := TDirectory.GetCurrentDirectory();

  Result := DoFinishResolvedPath(TPath.GetFullPath(TPath.Combine(LBase, LPath)));
end;

class function TUtils.GetEnv(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
end;

class procedure TUtils.SetEnv(const AName: string; const AValue: string);
begin
  SetEnvironmentVariable(PChar(AName), PChar(AValue));
end;

class function TUtils.HasEnv(const AName: string): Boolean;
begin
  Result := not GetEnv(AName).IsEmpty();
end;

class procedure TUtils.AddToEnvPath(const APath: string);
var
  LPath: string;
begin
  LPath := GetEnv('PATH');
  LPath := LPath + ResolvePath(APath);
  LPath := LPath.Replace('/', '\');
  SetEnv('PATH', LPath);
end;

class function TUtils.RunFromIDE(): Boolean;
begin
  Result := HasEnv('BDS');
end;

class function TUtils.CountLines(
  const APath, APattern: string;
  const ARecursive: Boolean): Int64;
var
  LFiles: TArray<string>;
  LLines: TArray<string>;
  LSearchOpt: TSearchOption;
  LI: Integer;
begin
  Result := 0;
  if not TDirectory.Exists(APath) then
    Exit;
  if ARecursive then
    LSearchOpt := TSearchOption.soAllDirectories
  else
    LSearchOpt := TSearchOption.soTopDirectoryOnly;
  LFiles := TDirectory.GetFiles(APath, APattern, LSearchOpt);
  for LI := 0 to High(LFiles) do
  begin
    LLines := TFile.ReadAllLines(LFiles[LI]);
    Result := Result + Length(LLines);
  end;
end;

class function TUtils.GetAppType(): TAppType;
var
  LBase: PByte;
  LDosHeader: PImageDosHeader;
  LNtHeaders: PImageNtHeaders;
begin
  Result := atUnknown;
  try
    LBase := PByte(GetModuleHandle(nil));
    if LBase = nil then
      Exit;
    LDosHeader := PImageDosHeader(LBase);
    LNtHeaders := PImageNtHeaders(LBase + LDosHeader._lfanew);
    if LNtHeaders.OptionalHeader.Subsystem = IMAGE_SUBSYSTEM_WINDOWS_CUI then
      Result := atConsole
    else if LNtHeaders.OptionalHeader.Subsystem = IMAGE_SUBSYSTEM_WINDOWS_GUI then
      Result := atGUI;
  except
    // PE header read failed — return matUnknown
  end;
end;


class procedure TUtils.CopyDirectory(const ASrcDir: string;
  const ADestDir: string);
var
  LFiles: TArray<string>;
  LI: Integer;
  LSrcFull: string;
  LRelPath: string;
  LDestFile: string;
  LDestSubDir: string;
begin
  if not TDirectory.Exists(ASrcDir) then
    raise Exception.CreateFmt('Source directory not found: %s', [ASrcDir]);

  if not TDirectory.Exists(ADestDir) then
    ForceDirectories(ADestDir);

  LSrcFull := TPath.GetFullPath(ASrcDir);
  LFiles := TDirectory.GetFiles(ASrcDir, '*',
    TSearchOption.soAllDirectories);
  for LI := 0 to Length(LFiles) - 1 do
  begin
    LRelPath := LFiles[LI].Substring(Length(LSrcFull) + 1);
    LDestFile := TPath.Combine(ADestDir, LRelPath);

    LDestSubDir := TPath.GetDirectoryName(LDestFile);
    if not TDirectory.Exists(LDestSubDir) then
      ForceDirectories(LDestSubDir);

    TFile.Copy(LFiles[LI], LDestFile);
  end;
end;

{ TCbrCommandBuilder }

constructor TCommandBuilder.Create();
begin
  inherited;

  FParams := TStringList.Create();
  FParams.Delimiter := ' ';
  FParams.StrictDelimiter := True;
end;

destructor TCommandBuilder.Destroy();
begin
  FreeAndNil(FParams);

  inherited;
end;

procedure TCommandBuilder.Clear();
begin
  FParams.Clear();
end;

procedure TCommandBuilder.AddParam(const AParam: string);
begin
  if AParam <> '' then
    FParams.Add(AParam);
end;

procedure TCommandBuilder.AddParam(const AFlag, AValue: string);
begin
  if AFlag <> '' then
  begin
    if AValue <> '' then
      FParams.Add(AFlag + AValue)
    else
      FParams.Add(AFlag);
  end
  else if AValue <> '' then
    FParams.Add(AValue);
end;

procedure TCommandBuilder.AddQuotedParam(const AFlag, AValue: string);
begin
  if AValue = '' then
    Exit;

  if AFlag <> '' then
    FParams.Add(AFlag + ' "' + AValue + '"')
  else
    FParams.Add('"' + AValue + '"');
end;

procedure TCommandBuilder.AddQuotedParam(const AValue: string);
begin
  AddQuotedParam('', AValue);
end;

procedure TCommandBuilder.AddFlag(const AFlag: string);
begin
  if AFlag <> '' then
    FParams.Add(AFlag);
end;

function TCommandBuilder.Dump(const AId: Integer): string;
var
  LI: Integer;
begin
  if FParams.Count = 0 then
  begin
    Result := '';
    Exit;
  end;

  // Manually join with spaces to avoid TStringList.DelimitedText auto-quoting
  Result := FParams[0];
  for LI := 1 to FParams.Count - 1 do
    Result := Result + ' ' + FParams[LI];
end;

function TCommandBuilder.GetParamCount(): Integer;
begin
  Result := FParams.Count;
end;

// ===========================================================================

procedure Startup();
begin
  ReportMemoryLeaksOnShutdown := True;
  TUtils.InitConsole();
end;

procedure Shutdown();
begin
end;

initialization
begin
  Startup();
end;

finalization
begin
  Shutdown();
end;

end.
