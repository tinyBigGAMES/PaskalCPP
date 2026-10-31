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

  StdApp.Packer.CLI - AppPacker command-line front-end

  Subcommands:
    AppPacker <manifest.yml>          pack (legacy invocation, kept working)
    AppPacker pack <manifest.yml>     pack
    AppPacker keygen <basepath>       write <basepath>.key + <basepath>.pub
    AppPacker verify <file> <pubkey>  verify <file>.minisig (pubkey = file or string)

  Exit codes: 0 ok, 1 usage/manifest error, 2 discovery error, 3 build/sign
  error (matches the original TigerPack).

  Dependencies: StdApp.Base, StdApp.Console, StdApp.Utils, StdApp.Packer,
  StdApp.Crypto, StdApp.Resources
===============================================================================}

unit StdApp.Packer.CLI;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.IOUtils,
  StdApp.Base,
  StdApp.Console,
  StdApp.Utils,
  StdApp.Crypto,
  StdApp.Packer,
  StdApp.Resources;

type
  { TPackerCLI }
  TPackerCLI = class(TBaseObject)
  private
    procedure DoBanner();
    procedure DoUsage();
    // The command's error owner (PROJECT.md error handling): status lines
    // print to the console; the caller wires it, prints it, frees it
    function DoNewErrors(): TErrors;
    function DoPack(const AManifest: string): Integer;
    function DoKeygen(const ABasePath: string): Integer;
    function DoVerify(const AFilename, APublicKey: string): Integer;
  public
    function Run(): Integer;
  end;

{ RunPackerCLI }
// One-line program body entry point
procedure RunPackerCLI();

implementation

{ TPackerCLI }

procedure TPackerCLI.DoBanner();
var
  LInfo: TVersionInfo;
begin
  if TUtils.GetVersionInfo(LInfo) then
    TConsole.PrintLn(RSCliBanner, [LInfo.VersionString])
  else
    TConsole.PrintLn(RSCliBanner, ['dev']);
  TConsole.PrintLn();
end;

procedure TPackerCLI.DoUsage();
begin
  TConsole.PrintLn(RSCliUsage);
end;

function TPackerCLI.DoNewErrors(): TErrors;
begin
  Result := TErrors.Create();
  Result.SetStatusCallback(
    procedure(const AText: string; const AUserData: Pointer)
    begin
      TConsole.PrintLn(AText);
    end);
end;

function TPackerCLI.DoPack(const AManifest: string): Integer;
var
  LErrors: TErrors;
  LPacker: TPacker;
begin
  LErrors := DoNewErrors();
  LPacker := TPacker.Create();
  try
    LPacker.SetErrors(LErrors);
    if not LPacker.LoadManifest(AManifest) then
    begin
      LErrors.PrintErrors();
      Exit(1);
    end;
    TConsole.PrintLn(RSCliPacking, [LPacker.PackName, LPacker.Version]);
    if not LPacker.DiscoverFiles() then
    begin
      LErrors.PrintErrors();
      Exit(2);
    end;
    if not LPacker.Build() then
    begin
      LErrors.PrintErrors();
      Exit(3);
    end;
    Result := 0;
  finally
    LPacker.Free();
    LErrors.Free();
  end;
end;

function TPackerCLI.DoKeygen(const ABasePath: string): Integer;
var
  LErrors: TErrors;
  LMini: TMinisign;
  LPair: TMiniKeyPair;
  LKeyFile: string;
  LPubFile: string;
begin
  Result := 1;
  if ABasePath = '' then
  begin
    DoUsage();
    Exit;
  end;
  LKeyFile := ABasePath + '.key';
  LPubFile := ABasePath + '.pub';
  // NEVER overwrite an existing secret key
  if TFile.Exists(LKeyFile) then
  begin
    TConsole.PrintLn(RSCliKeyExists, [LKeyFile]);
    Exit;
  end;
  LErrors := DoNewErrors();
  LMini := TMinisign.Create();
  try
    LMini.SetErrors(LErrors);
    if not LMini.GenerateKeyPair(LPair) then
    begin
      LErrors.PrintErrors();
      Exit;
    end;
    TUtils.CreateDirInPath(LKeyFile);
    if (not LMini.SaveSecretKey(LKeyFile, LPair)) or
       (not LMini.SavePublicKey(LPubFile, LPair)) then
    begin
      LErrors.PrintErrors();
      Exit;
    end;
    TConsole.PrintLn(RSCliKeygenDone, [LKeyFile, LPubFile]);
    TConsole.PrintLn(RSCliKeyId, [LMini.KeyIdString(LPair)]);
    TConsole.PrintLn(RSCliPubKey, [LMini.PublicKeyString(LPair)]);
    TConsole.PrintLn(RSCliKeyBackupHint);
    Result := 0;
  finally
    LMini.Free();
    LErrors.Free();
  end;
end;

function TPackerCLI.DoVerify(const AFilename, APublicKey: string): Integer;
var
  LErrors: TErrors;
  LMini: TMinisign;
  LPair: TMiniKeyPair;
  LLoaded: Boolean;
begin
  Result := 1;
  if (AFilename = '') or (APublicKey = '') then
  begin
    DoUsage();
    Exit;
  end;
  LErrors := DoNewErrors();
  LMini := TMinisign.Create();
  try
    LMini.SetErrors(LErrors);
    // Public key argument: a key file path, or the raw base64 key string
    if TFile.Exists(APublicKey) then
      LLoaded := LMini.LoadPublicKey(APublicKey, LPair)
    else
      LLoaded := LMini.LoadPublicKeyString(APublicKey, LPair);
    if not LLoaded then
    begin
      LErrors.PrintErrors();
      Exit;
    end;
    if LMini.VerifyFile(AFilename, LPair) then
    begin
      TConsole.PrintLn(RSCliVerifyOk, [AFilename]);
      Result := 0;
    end
    else
    begin
      LErrors.PrintErrors();
      Result := 3;
    end;
  finally
    LMini.Free();
    LErrors.Free();
  end;
end;

function TPackerCLI.Run(): Integer;
var
  LFirst: string;
  LLower: string;
begin
  DoBanner();
  if ParamCount() < 1 then
  begin
    DoUsage();
    Exit(1);
  end;
  LFirst := ParamStr(1);
  LLower := LFirst.ToLower();
  if LLower = 'pack' then
    Result := DoPack(ParamStr(2))
  else if LLower = 'keygen' then
    Result := DoKeygen(ParamStr(2))
  else if LLower = 'verify' then
    Result := DoVerify(ParamStr(2), ParamStr(3))
  else if LLower.EndsWith('.yml') or LLower.EndsWith('.yaml') then
    Result := DoPack(LFirst)
  else
  begin
    DoUsage();
    Result := 1;
  end;
end;

{ RunPackerCLI }

procedure RunPackerCLI();
var
  LCli: TPackerCLI;
begin
  try
    LCli := TPackerCLI.Create();
    try
      ExitCode := LCli.Run();
    finally
      LCli.Free();
    end;  
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + 'EXCEPTION: %s', [E.Message]);
    end;
  end;
end;

end.
