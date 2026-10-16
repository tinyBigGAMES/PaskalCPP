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
  PaskalCPP.LSP.Uri - file URIs of the LSP server

  file:///C:/dir/a%20b.pcpp <-> C:\dir\a b.pcpp, file://host/share/x <->
  \\host\share\x. A URI of another scheme (untitled:) names no file.
  Adopted from FreeStrike.LSP.Server UriToFilename / FilenameToUri /
  PercentDecode (plans\done\PLAN-EDITOR.md E2.1f).

  Dependencies: none (RTL)
  Notes:
    - Percent escapes are bytes of UTF-8 (RFC 3986); FilenameToUri encodes
      every byte outside the unreserved set, '/' and ':'.
===============================================================================}

unit PaskalCPP.LSP.Uri;

interface

uses
  System.SysUtils;

const
  { PC_LSP_FILE_SCHEME }
  PC_LSP_FILE_SCHEME = 'file://';

type
  { TPCLspUri }
  // Static routines only: a record, so nothing descends from TObject
  TPCLspUri = record
    // The path a file URI names; False (AFilename = '') for any other URI
    class function ToFilename(const AUri: string; out AFilename: string): Boolean; static;
    // ToFilename reversed
    class function FromFilename(const AFilename: string): string; static;
    class function PercentDecode(const AText: string): string; static;
  end;

implementation

{ AppendBytes }
procedure AppendBytes(var ADest: TBytes; const ASource: TBytes);
var
  LAt: Integer;
begin
  if Length(ASource) = 0 then
    Exit;
  LAt := Length(ADest);
  SetLength(ADest, LAt + Length(ASource));
  Move(ASource[0], ADest[LAt], Length(ASource));
end;

{ TPCLspUri }

class function TPCLspUri.PercentDecode(const AText: string): string;
var
  LBytes: TBytes;
  LPending: string;
  LI: Integer;
  LHex: Integer;
begin
  // RFC 3986: %XX are bytes of UTF-8; other chars stand for themselves
  LBytes := nil;
  LPending := '';
  LI := 1;
  while LI <= Length(AText) do
  begin
    if (AText[LI] = '%') and (LI + 2 <= Length(AText)) and
      TryStrToInt('$' + Copy(AText, LI + 1, 2), LHex) then
    begin
      AppendBytes(LBytes, TEncoding.UTF8.GetBytes(LPending));
      LPending := '';
      AppendBytes(LBytes, TBytes.Create(Byte(LHex)));
      Inc(LI, 3);
    end
    else
    begin
      LPending := LPending + AText[LI];
      Inc(LI);
    end;
  end;
  AppendBytes(LBytes, TEncoding.UTF8.GetBytes(LPending));
  Result := TEncoding.UTF8.GetString(LBytes);
end;

class function TPCLspUri.ToFilename(const AUri: string; out AFilename: string): Boolean;
var
  LPath: string;
begin
  AFilename := '';
  if not AUri.StartsWith(PC_LSP_FILE_SCHEME, True) then
    Exit(False);

  LPath := PercentDecode(AUri.Substring(Length(PC_LSP_FILE_SCHEME)));
  if LPath.StartsWith('/') then
  begin
    // The slash before a drive letter: /C:/dir
    if (LPath.Length >= 3) and (LPath.Chars[2] = ':') then
      LPath := LPath.Substring(1);
  end
  else
    // An authority (host) part: a UNC path
    LPath := '//' + LPath;
  AFilename := LPath.Replace('/', PathDelim);
  Result := AFilename <> '';
end;

class function TPCLspUri.FromFilename(const AFilename: string): string;
var
  LPath: string;
  LBytes: TBytes;
  LByte: Byte;
  LBuilder: TStringBuilder;
begin
  // C:\dir\a b.pcpp -> file:///C:/dir/a%20b.pcpp, \\host\share\x ->
  // file://host/share/x; UTF-8 bytes outside the unreserved set (and '/'
  // ':') are percent-encoded
  LPath := AFilename.Replace(PathDelim, '/');
  if LPath.StartsWith('//') then
    LPath := LPath.Substring(2)
  else
    LPath := '/' + LPath;

  LBytes := TEncoding.UTF8.GetBytes(LPath);
  LBuilder := TStringBuilder.Create();
  try
    LBuilder.Append(PC_LSP_FILE_SCHEME);
    for LByte in LBytes do
    begin
      if AnsiChar(LByte) in ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~', '/', ':'] then
        LBuilder.Append(Char(LByte))
      else
        LBuilder.Append('%').Append(IntToHex(LByte, 2));
    end;
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

end.
