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
  PaskalCPP.DiagCache - a TU's clang diagnostics kept for zig's cache

  zig reuses a TU's object when its source, headers and flags are unchanged;
  clang does not run, so it writes no .dia and the build would report none of
  that TU's warnings. TPCDiagCache keeps every .dia a compile wrote, keyed by
  the state that produced it: the TU's flag text (with target and optimize
  level) and the bytes of its source and of every header it included (clang's
  cc1 -header-include-file list, written beside the .dia). After a build, a TU
  whose .dia is absent was served from zig's cache: the kept .dia whose state
  matches the files as they are now is copied back to the TU's .dia path, so
  the build reports it exactly as if clang had run.

  A cached TU with no matching entry (a save that failed, a build cut off
  after zig compiled) is MISSED: its diagnostics are unknown. The header
  list's path names the store's generation and the TU's own salt, and that
  path is one of the TU's flags, so part of zig's cache key: a missed TU gets
  a new salt (RenewUnit) and the caller builds again, and zig compiles that
  TU alone. A store lost whole gets a new generation: every TU compiles.

  Dependencies: RTL + StdApp.Base + StdApp.Utils + PaskalCPP.Common
  Notes: Reports nothing: a failure is returned as text (AFailure) and the
    caller reports it. Only states it saw compile are ever replayed.
===============================================================================}

unit PaskalCPP.DiagCache;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.Common;

const
  { PC_DIAG_STORE_DIR }
  // The store, under the build's diagnostics folder
  PC_DIAG_STORE_DIR = 'store';
  { PC_DIAG_STORE_ID_FILE }
  // The store's generation id (a GUID, one line)
  PC_DIAG_STORE_ID_FILE = 'generation.txt';
  { PC_DIAG_STORE_ENTRIES_DIR }
  // One folder per TU (its .dia file name), one entry per state seen
  PC_DIAG_STORE_ENTRIES_DIR = 'entries';
  { PC_DIAG_STORE_SALTS_DIR }
  // One file per TU that was renewed (its .dia file name + .txt): its salt
  PC_DIAG_STORE_SALTS_DIR = 'salts';
  { PC_DIAG_SALT_EXT }
  // A salt file
  PC_DIAG_SALT_EXT = '.txt';
  { PC_DIAG_RUN_MARKER }
  // Written before zig runs, deleted once every .dia of the run is kept
  // (BeginRun / EndRun): still there at the next Open = that run was cut off
  PC_DIAG_RUN_MARKER = 'run.pending';
  { PC_DIAG_SALT_NONE }
  // The salt of a TU never renewed
  PC_DIAG_SALT_NONE = '0';
  { PC_DIAG_HEADERS_EXT }
  // A header list: clang's, and a kept entry's (resolved paths, one per line)
  PC_DIAG_HEADERS_EXT = '.hdrs';
  { PC_DIAG_ENTRY_DIA_EXT }
  // A kept entry's .dia
  PC_DIAG_ENTRY_DIA_EXT = '.dia';

type
  { TPCDiagSettled }
  // What SettleUnit did for one TU
  TPCDiagSettled = (
    dsNothing,    // no store, no key, or a compiled TU with no state to key by
    dsKept,       // compiled: its .dia is kept under its state
    dsRestored,   // served from zig's cache: the kept .dia is back
    dsMissed      // served from zig's cache with no kept .dia: unknown
  );

  { TPCDiagCache }
  TPCDiagCache = class(TBaseObject)
  strict private
    // The build's diagnostics folder (resolved) and the store's generation
    FDiagDir: string;
    FGeneration: string;
    FOpened: Boolean;
    // The run marker was there at Open: the last run was cut off before
    // its .dia files were kept
    FCutOff: Boolean;

    // Per TU (by its lower-cased .dia file name): its salt, read by Open
    FSalts: TDictionary<string, string>;

    // Per TU (by its lower-cased .dia path): its flag text, recorded as
    // build.zig is written (SetUnitKey)
    FUnitKeys: TDictionary<string, string>;

    // One build's file hashes, by lower-cased resolved path
    FFileHashes: TDictionary<string, string>;

    // The .dia paths (lower-cased) this build.zig's run put back: a later
    // settle of the same run sees them as restored, never as compiled
    FRestored: TDictionary<string, Boolean>;

    function DoStoreDir(): string;
    function DoEntriesDir(const ADiagPath: string): string;
    function DoSaltsDir(): string;
    function DoSaltOf(const ADiagPath: string): string;
    procedure DoReadSalts();
    function DoFileHash(const APath: string; out AHash: string;
      out AFailure: string): Boolean;
    function DoStateKey(const AUnitKey: string; const ASourceFile: string;
      const AHeaders: TArray<string>; out AKey: string;
      out AFailure: string): Boolean;
    function DoReadClangList(const AListPath: string; const ABuildRoot: string): TArray<string>;
    function DoReadKeptList(const AListPath: string): TArray<string>;
    function DoSave(const ADiagPath: string; const AKey: string;
      const AHeaders: TArray<string>; out AFailure: string): Boolean;
    function DoFindEntry(const ADiagPath: string; const AUnitKey: string;
      const ASourceFile: string; out AEntryDia: string;
      out AFailure: string): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // The build's diagnostics folder (resolved). Forgets the generation, the
    // salts, the unit keys and the file hashes of an earlier build
    procedure Init(const ADiagDir: string);

    // Reads the store's generation and the TUs' salts, or makes the store
    // with a new generation. False = it cannot be read or made (AFailure)
    function Open(out AFailure: string): Boolean;
    function IsOpen(): Boolean;

    // Where clang writes the header list of the TU whose .dia is ADiagPath:
    // named by the generation and the TU's salt (Open first)
    function HeaderListPath(const ADiagPath: string): string;

    // The TU's flag text: the flags build.zig gives it, its target and its
    // optimize level (all of zig's cache key but its files)
    procedure SetUnitKey(const ADiagPath: string; const AUnitKey: string);

    // Before the build: the TU's header list is deleted (a list left from an
    // earlier build would be read as this build's). False = it cannot be
    function PrepareUnit(const ADiagPath: string; out AFailure: string): Boolean;

    // After the build. The TU compiled (its .dia exists): its .dia is kept
    // under its state. It was served from zig's cache (no .dia): the kept .dia
    // of the state the files are in now is copied to ADiagPath, or the TU is
    // missed (ASettled). False = a file operation failed (AFailure)
    function SettleUnit(const ADiagPath: string; const ASourceFile: string;
      const ALanguage: TPCSourceLanguage; const ABuildRoot: string;
      out ASettled: TPCDiagSettled; out AFailure: string): Boolean;

    // A missed TU gets a new salt: its header list's path, so its flags and
    // zig's cache key, change, and the next build compiles it. Takes effect
    // in the next build.zig written. False = the salt cannot be written
    function RenewUnit(const ADiagPath: string; out AFailure: string): Boolean;

    // The last run was cut off (its marker survived): a TU zig compiled in
    // it may be cached with nothing kept. The caller renews every TU with
    // no kept .dia for its present state (NeedsRenew) before zig runs
    function WasCutOff(): Boolean;
    // True = the TU has a flag text and no kept .dia matches the files as
    // they are now. False with AFailure = a file could not be read
    function NeedsRenew(const ADiagPath: string; const ASourceFile: string;
      out AFailure: string): Boolean;

    // The run marker: written right before zig runs, deleted once the run's
    // .dia files are kept. False = it cannot be written / deleted
    function BeginRun(out AFailure: string): Boolean;
    function EndRun(out AFailure: string): Boolean;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Hash,
  StdApp.Utils;

{ TPCDiagCache }

constructor TPCDiagCache.Create();
begin
  inherited;

  FSalts := TDictionary<string, string>.Create();
  FUnitKeys := TDictionary<string, string>.Create();
  FFileHashes := TDictionary<string, string>.Create();
  FRestored := TDictionary<string, Boolean>.Create();
end;

destructor TPCDiagCache.Destroy();
begin
  FRestored.Free();
  FFileHashes.Free();
  FUnitKeys.Free();
  FSalts.Free();

  inherited;
end;

procedure TPCDiagCache.Init(const ADiagDir: string);
begin
  FDiagDir := ADiagDir;
  FGeneration := '';
  FOpened := False;
  FCutOff := False;
  FSalts.Clear();
  FUnitKeys.Clear();
  FFileHashes.Clear();
  FRestored.Clear();
end;

function TPCDiagCache.DoStoreDir(): string;
begin
  Result := TUtils.JoinResolvedPath(FDiagDir, PC_DIAG_STORE_DIR);
end;

function TPCDiagCache.DoEntriesDir(const ADiagPath: string): string;
begin
  Result := TUtils.JoinResolvedPath(DoStoreDir(), PC_DIAG_STORE_ENTRIES_DIR +
    '\' + TPath.GetFileName(ADiagPath));
end;

function TPCDiagCache.DoSaltsDir(): string;
begin
  Result := TUtils.JoinResolvedPath(DoStoreDir(), PC_DIAG_STORE_SALTS_DIR);
end;

function TPCDiagCache.DoSaltOf(const ADiagPath: string): string;
begin
  if not FSalts.TryGetValue(TPath.GetFileName(ADiagPath).ToLower(), Result) then
    Result := PC_DIAG_SALT_NONE;
end;

procedure TPCDiagCache.DoReadSalts();
var
  LDir: string;
  LPath: string;
  LSalt: string;
begin
  // Every renewed TU's salt, by its .dia file name. Raises on a read
  // failure (Open's try)
  LDir := DoSaltsDir();
  if not DirectoryExists(LDir) then
    Exit;
  for LPath in TDirectory.GetFiles(LDir, '*' + PC_DIAG_SALT_EXT) do
  begin
    LSalt := TFile.ReadAllText(LPath, TEncoding.UTF8).Trim();
    if LSalt <> '' then
      FSalts.AddOrSetValue(TPath.GetFileNameWithoutExtension(LPath).ToLower(), LSalt);
  end;
end;

function TPCDiagCache.Open(out AFailure: string): Boolean;
var
  LIdPath: string;
  LText: string;
begin
  Result := False;
  AFailure := '';
  LIdPath := TUtils.JoinResolvedPath(DoStoreDir(), PC_DIAG_STORE_ID_FILE);
  try
    if FileExists(LIdPath) then
      LText := TFile.ReadAllText(LIdPath, TEncoding.UTF8).Trim()
    else
      LText := '';
    // A missing or empty id is a new store: every TU's header list moves to
    // a new name, so zig compiles every TU again
    if LText = '' then
    begin
      LText := TGUID.NewGuid().ToString().Replace('{', '').Replace('}', '').ToLower();
      // TDirectory, not ForceDirectories: a resolved path is spelled with
      // '/', and ForceDirectories makes no missing parent of such a path (it
      // returns False, it does not raise)
      TDirectory.CreateDirectory(DoStoreDir());
      TFile.WriteAllText(LIdPath, LText, TEncoding.ASCII);
    end;
    DoReadSalts();
    FCutOff := FileExists(TUtils.JoinResolvedPath(DoStoreDir(), PC_DIAG_RUN_MARKER));
  except
    on E: Exception do
    begin
      AFailure := E.Message;
      FSalts.Clear();
      Exit;
    end;
  end;
  FGeneration := LText;
  FOpened := True;
  Result := True;
end;

function TPCDiagCache.IsOpen(): Boolean;
begin
  Result := FOpened;
end;

function TPCDiagCache.HeaderListPath(const ADiagPath: string): string;
begin
  Result := TUtils.JoinResolvedPath(DoStoreDir(),
    TPath.GetFileName(ADiagPath) + '.' + FGeneration + '.' + DoSaltOf(ADiagPath) +
    PC_DIAG_HEADERS_EXT);
end;

procedure TPCDiagCache.SetUnitKey(const ADiagPath: string; const AUnitKey: string);
begin
  FUnitKeys.AddOrSetValue(ADiagPath.ToLower(), AUnitKey);
end;

function TPCDiagCache.PrepareUnit(const ADiagPath: string; out AFailure: string): Boolean;
var
  LListPath: string;
begin
  Result := True;
  AFailure := '';
  if not FOpened then
    Exit;
  LListPath := HeaderListPath(ADiagPath);
  try
    if FileExists(LListPath) then
      TFile.Delete(LListPath);
  except
    on E: Exception do
    begin
      AFailure := E.Message;
      Result := False;
    end;
  end;
end;

function TPCDiagCache.DoFileHash(const APath: string; out AHash: string;
  out AFailure: string): Boolean;
var
  LKey: string;
begin
  // One build hashes each file once, however many TUs include it. False with
  // no AFailure = the file is gone: no state with it can match. False with
  // AFailure = it is there but cannot be read
  Result := False;
  AHash := '';
  AFailure := '';
  LKey := APath.ToLower();
  if FFileHashes.TryGetValue(LKey, AHash) then
    Exit(True);
  try
    if not FileExists(APath) then
      Exit;
    AHash := THashMD5.GetHashStringFromFile(APath);
  except
    on E: Exception do
    begin
      AFailure := E.Message;
      Exit;
    end;
  end;
  FFileHashes.Add(LKey, AHash);
  Result := True;
end;

function TPCDiagCache.DoStateKey(const AUnitKey: string; const ASourceFile: string;
  const AHeaders: TArray<string>; out AKey: string; out AFailure: string): Boolean;
var
  LBuilder: TStringBuilder;
  LPath: string;
  LHash: string;
begin
  // The flag text, then every file of the compile with its bytes' hash, in
  // the order clang read them. False = a file is gone (no AFailure) or
  // cannot be read (AFailure)
  Result := False;
  AKey := '';
  AFailure := '';
  LBuilder := TStringBuilder.Create();
  try
    LBuilder.Append(AUnitKey).Append(#10);
    if not DoFileHash(ASourceFile, LHash, AFailure) then
      Exit;
    LBuilder.Append(ASourceFile.ToLower()).Append(#0).Append(LHash).Append(#10);
    for LPath in AHeaders do
    begin
      if not DoFileHash(LPath, LHash, AFailure) then
        Exit;
      LBuilder.Append(LPath.ToLower()).Append(#0).Append(LHash).Append(#10);
    end;
    AKey := THashMD5.GetHashString(LBuilder.ToString());
    Result := True;
  finally
    LBuilder.Free();
  end;
end;

function TPCDiagCache.DoReadClangList(const AListPath: string;
  const ABuildRoot: string): TArray<string>;
var
  LLines: TArray<string>;
  LLine: string;
  LPath: TStringBuilder;
  LI: Integer;
begin
  // clang writes one header per line as a string literal's body: a
  // backslash escapes the next character ('C:\\x/y.h'). A relative path is
  // relative to clang's working directory, the build root. Raises on a
  // read failure (the caller's try)
  Result := nil;
  LLines := TFile.ReadAllLines(AListPath, TEncoding.UTF8);
  LPath := TStringBuilder.Create();
  try
    for LLine in LLines do
    begin
      if LLine.Trim() = '' then
        Continue;
      LPath.Clear();
      LI := 0;
      while LI < LLine.Length do
      begin
        if (LLine.Chars[LI] = '\') and (LI + 1 < LLine.Length) then
          Inc(LI);
        LPath.Append(LLine.Chars[LI]);
        Inc(LI);
      end;
      Result := Result + [TUtils.ResolvePath(LPath.ToString(), ABuildRoot)];
    end;
  finally
    LPath.Free();
  end;
end;

function TPCDiagCache.DoReadKeptList(const AListPath: string): TArray<string>;
var
  LLines: TArray<string>;
  LLine: string;
begin
  // A kept list holds resolved paths, one per line. Raises on a read
  // failure (the caller's try)
  Result := nil;
  LLines := TFile.ReadAllLines(AListPath, TEncoding.UTF8);
  for LLine in LLines do
  begin
    if LLine <> '' then
      Result := Result + [LLine];
  end;
end;

function TPCDiagCache.DoSave(const ADiagPath: string; const AKey: string;
  const AHeaders: TArray<string>; out AFailure: string): Boolean;
var
  LDir: string;
  LEntryBase: string;
  LText: string;
  LNoBom: TEncoding;
begin
  // The .dia first, the list last: an entry is complete once its list is
  // there (DoFindEntry reads only entries with both)
  Result := False;
  AFailure := '';
  LDir := DoEntriesDir(ADiagPath);
  LEntryBase := TUtils.JoinResolvedPath(LDir, AKey);
  LText := string.Join(#10, AHeaders);
  try
    TDirectory.CreateDirectory(LDir);
    TFile.Copy(ADiagPath, LEntryBase + PC_DIAG_ENTRY_DIA_EXT, True);
    // No BOM: the list's first line is a path, read back as it is
    LNoBom := TUTF8Encoding.Create(False);
    try
      TFile.WriteAllText(LEntryBase + PC_DIAG_HEADERS_EXT, LText, LNoBom);
    finally
      LNoBom.Free();
    end;
  except
    on E: Exception do
    begin
      AFailure := E.Message;
      Exit;
    end;
  end;
  Result := True;
end;

function TPCDiagCache.DoFindEntry(const ADiagPath: string; const AUnitKey: string;
  const ASourceFile: string; out AEntryDia: string; out AFailure: string): Boolean;
var
  LDir: string;
  LListPath: string;
  LKey: string;
  LDiaPath: string;
begin
  // The entry whose state the files are in now: its key, recomputed from its
  // own header list, is its name. zig served the TU from that same state.
  // False = none (AFailure '') or a file could not be read (AFailure)
  Result := False;
  AEntryDia := '';
  AFailure := '';
  LDir := DoEntriesDir(ADiagPath);
  try
    if not DirectoryExists(LDir) then
      Exit;
    for LListPath in TDirectory.GetFiles(LDir, '*' + PC_DIAG_HEADERS_EXT) do
    begin
      LDiaPath := TPath.ChangeExtension(LListPath, PC_DIAG_ENTRY_DIA_EXT);
      if not FileExists(LDiaPath) then
        Continue;
      if not DoStateKey(AUnitKey, ASourceFile, DoReadKeptList(LListPath), LKey,
        AFailure) then
      begin
        // A file of this entry is gone: another state. One that cannot be
        // read is a failure
        if AFailure <> '' then
          Exit;
        Continue;
      end;
      if SameText(LKey, TPath.GetFileNameWithoutExtension(LListPath)) then
      begin
        AEntryDia := LDiaPath;
        Exit(True);
      end;
    end;
  except
    on E: Exception do
      AFailure := E.Message;
  end;
end;

function TPCDiagCache.SettleUnit(const ADiagPath: string; const ASourceFile: string;
  const ALanguage: TPCSourceLanguage; const ABuildRoot: string;
  out ASettled: TPCDiagSettled; out AFailure: string): Boolean;
var
  LUnitKey: string;
  LListPath: string;
  LHeaders: TArray<string>;
  LKey: string;
  LEntryDia: string;
  LRenewFailure: string;
begin
  Result := True;
  ASettled := dsNothing;
  AFailure := '';
  if (not FOpened) or (not FUnitKeys.TryGetValue(ADiagPath.ToLower(), LUnitKey)) then
    Exit;

  // Put back by an earlier settle of this run: still the cached TU's .dia,
  // not a compile (it has no header list, and must not be renewed for it)
  if FRestored.ContainsKey(ADiagPath.ToLower()) and FileExists(ADiagPath) then
  begin
    ASettled := dsRestored;
    Exit;
  end;

  // Served from zig's cache: the kept .dia of the files' present state
  if not FileExists(ADiagPath) then
  begin
    if not DoFindEntry(ADiagPath, LUnitKey, ASourceFile, LEntryDia, AFailure) then
    begin
      ASettled := dsMissed;
      Exit(AFailure = '');
    end;
    try
      TFile.Copy(LEntryDia, ADiagPath, True);
    except
      on E: Exception do
      begin
        AFailure := E.Message;
        ASettled := dsMissed;
        Exit(False);
      end;
    end;
    FRestored.AddOrSetValue(ADiagPath.ToLower(), True);
    ASettled := dsRestored;
    Exit;
  end;

  // Compiled: kept under its state. IR has no preprocessor and clang writes
  // no list for it; any other TU without its list has no state to key by and
  // is not kept
  LListPath := HeaderListPath(ADiagPath);
  try
    if FileExists(LListPath) then
      LHeaders := DoReadClangList(LListPath, ABuildRoot)
    else if ALanguage = slLLVMIR then
      LHeaders := nil
    else
    begin
      // No state to key by, so not kept: like a failed save, the next
      // build must compile it rather than serve it with nothing kept
      if not RenewUnit(ADiagPath, AFailure) then
        Exit(False);
      Exit;
    end;
  except
    on E: Exception do
    begin
      AFailure := E.Message;
      Exit(False);
    end;
  end;
  if not DoStateKey(LUnitKey, ASourceFile, LHeaders, LKey, AFailure) then
    Exit(AFailure = '');
  Result := DoSave(ADiagPath, LKey, LHeaders, AFailure);
  if Result then
  begin
    ASettled := dsKept;
    Exit;
  end;
  // Not kept: zig has its object, so the next build would serve it with
  // nothing kept. A new salt makes that build compile it instead
  if not RenewUnit(ADiagPath, LRenewFailure) then
    AFailure := AFailure + '; ' + LRenewFailure;
end;

function TPCDiagCache.WasCutOff(): Boolean;
begin
  Result := FCutOff;
end;

function TPCDiagCache.NeedsRenew(const ADiagPath: string; const ASourceFile: string;
  out AFailure: string): Boolean;
var
  LUnitKey: string;
  LEntryDia: string;
begin
  AFailure := '';
  if (not FOpened) or (not FUnitKeys.TryGetValue(ADiagPath.ToLower(), LUnitKey)) then
    Exit(False);
  Result := not DoFindEntry(ADiagPath, LUnitKey, ASourceFile, LEntryDia, AFailure);
  if AFailure <> '' then
    Result := False;
end;

function TPCDiagCache.BeginRun(out AFailure: string): Boolean;
begin
  Result := False;
  AFailure := '';
  if not FOpened then
    Exit(True);
  try
    TFile.WriteAllText(TUtils.JoinResolvedPath(DoStoreDir(), PC_DIAG_RUN_MARKER),
      '', TEncoding.ASCII);
  except
    on E: Exception do
    begin
      AFailure := E.Message;
      Exit;
    end;
  end;
  Result := True;
end;

function TPCDiagCache.EndRun(out AFailure: string): Boolean;
var
  LPath: string;
begin
  Result := False;
  AFailure := '';
  if not FOpened then
    Exit(True);
  LPath := TUtils.JoinResolvedPath(DoStoreDir(), PC_DIAG_RUN_MARKER);
  try
    if FileExists(LPath) then
      TFile.Delete(LPath);
  except
    on E: Exception do
    begin
      AFailure := E.Message;
      Exit;
    end;
  end;
  FCutOff := False;
  Result := True;
end;

function TPCDiagCache.RenewUnit(const ADiagPath: string; out AFailure: string): Boolean;
var
  LName: string;
  LSalt: string;
begin
  Result := False;
  AFailure := '';
  LName := TPath.GetFileName(ADiagPath);
  LSalt := TGUID.NewGuid().ToString().Replace('{', '').Replace('}', '')
    .Replace('-', '').Substring(0, 12).ToLower();
  try
    TDirectory.CreateDirectory(DoSaltsDir());
    TFile.WriteAllText(TUtils.JoinResolvedPath(DoSaltsDir(), LName + PC_DIAG_SALT_EXT),
      LSalt, TEncoding.ASCII);
  except
    on E: Exception do
    begin
      AFailure := E.Message;
      Exit;
    end;
  end;
  FSalts.AddOrSetValue(LName.ToLower(), LSalt);
  Result := True;
end;

end.
