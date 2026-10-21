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
  PaskalCPP.Archive - an ar archive's symbol index (a static library's names)

  TPCArchiveIndex reads the symbol index a static library carries as its
  first member: the "!<arch>" magic, then a 60-byte member header named "/"
  (32-bit) or "/SYM64/" (64-bit), whose body is the symbol count, one offset
  per symbol (all big-endian, 4 or 8 bytes) and the symbols' names, each
  ending in a zero byte. zig writes this index on both official targets (a
  COFF .lib adds a second "/" member after it, which is not read). Layout
  checked on zig 0.17.0's archives (scripts\vendor\resdata_a5b\ar_peek.py).

  Dependencies: RTL only
  Notes: A pure reader: it reports nothing. Anything that is not an archive
    with a whole index (an ELF .so, a truncated file, no index) holds no
    symbols. A name's bytes are taken one byte to one character, so an ASCII
    name reads exactly and nothing can fail to decode.
===============================================================================}

unit PaskalCPP.Archive;

interface

uses
  System.SysUtils,
  System.Classes;

const
  { PC_AR_MAGIC }
  // The archive's first 8 bytes
  PC_AR_MAGIC = '!<arch>'#10;
  { PC_AR_MAGIC_SIZE }
  PC_AR_MAGIC_SIZE = 8;
  { PC_AR_HEADER_SIZE }
  // A member header: name 16, date 12, uid 6, gid 6, mode 8, size 10, "`\n" 2
  PC_AR_HEADER_SIZE = 60;
  { PC_AR_SIZE_OFFSET }
  PC_AR_SIZE_OFFSET = 48;
  { PC_AR_SIZE_WIDTH }
  PC_AR_SIZE_WIDTH = 10;
  { PC_AR_NAME_WIDTH }
  PC_AR_NAME_WIDTH = 16;
  { PC_AR_INDEX_32 }
  // The symbol index member's names: 4-byte and 8-byte counts and offsets
  PC_AR_INDEX_32 = '/';
  { PC_AR_INDEX_64 }
  PC_AR_INDEX_64 = '/SYM64/';

type
  { TPCArchiveIndex }
  TPCArchiveIndex = record
  strict private
    class function DoText(const ABytes: TBytes; const AOffset: Int64;
      const ACount: Int64): string; static;
    class function DoBigEndian(const ABytes: TBytes; const AOffset: Int64;
      const AWidth: Integer): UInt64; static;
    class function DoMemberSize(const ABytes: TBytes; out ASize: Int64): Boolean; static;
  public
    // The symbols of the index in ABytes (the archive's start: the magic, the
    // first member's header and its whole body). False = no archive or no
    // whole index; ASymbols is then empty
    class function ReadSymbols(const ABytes: TBytes;
      out ASymbols: TArray<string>): Boolean; static;
    // The same, read from a file: only the magic and the first member are
    // read. False = the file could not be read (AFailure = the OS reason);
    // True with no symbols = not an archive or no index
    class function ReadFileSymbols(const AFilename: string;
      out ASymbols: TArray<string>; out AFailure: string): Boolean; static;
  end;

implementation

{ TPCArchiveIndex }

class function TPCArchiveIndex.DoText(const ABytes: TBytes; const AOffset: Int64;
  const ACount: Int64): string;
var
  LI: Int64;
begin
  // One byte, one character (see the unit notes)
  SetLength(Result, ACount);
  for LI := 0 to ACount - 1 do
    Result[LI + 1] := Char(ABytes[AOffset + LI]);
end;

class function TPCArchiveIndex.DoBigEndian(const ABytes: TBytes; const AOffset: Int64;
  const AWidth: Integer): UInt64;
var
  LI: Integer;
begin
  Result := 0;
  for LI := 0 to AWidth - 1 do
    Result := (Result shl 8) or ABytes[AOffset + LI];
end;

class function TPCArchiveIndex.DoMemberSize(const ABytes: TBytes; out ASize: Int64): Boolean;
var
  LText: string;
begin
  // The first member's size field: decimal digits, space padded. False =
  // no header, or a field that is no number
  ASize := 0;
  Result := False;
  if Length(ABytes) < PC_AR_MAGIC_SIZE + PC_AR_HEADER_SIZE then
    Exit;
  if DoText(ABytes, 0, PC_AR_MAGIC_SIZE) <> PC_AR_MAGIC then
    Exit;
  LText := DoText(ABytes, PC_AR_MAGIC_SIZE + PC_AR_SIZE_OFFSET, PC_AR_SIZE_WIDTH).Trim();
  Result := TryStrToInt64(LText, ASize) and (ASize >= 0);
end;

class function TPCArchiveIndex.ReadSymbols(const ABytes: TBytes;
  out ASymbols: TArray<string>): Boolean;
var
  LSize: Int64;
  LName: string;
  LWidth: Integer;
  LBody: Int64;
  LCount: UInt64;
  LPos: Int64;
  LEnd: Int64;
  LStart: Int64;
  LNames: Int64;
  LI: Int64;
begin
  ASymbols := nil;
  Result := False;
  if not DoMemberSize(ABytes, LSize) then
    Exit;

  // Only the index member's exact names: "/0", "//" are other members
  LName := DoText(ABytes, PC_AR_MAGIC_SIZE, PC_AR_NAME_WIDTH).TrimRight();
  if LName = PC_AR_INDEX_32 then
    LWidth := 4
  else if LName = PC_AR_INDEX_64 then
    LWidth := 8
  else
    Exit;

  LBody := PC_AR_MAGIC_SIZE + PC_AR_HEADER_SIZE;
  LEnd := LBody + LSize;
  if (LEnd > Length(ABytes)) or (LSize < LWidth) then
    Exit;

  // The count, the offsets (not needed), then the names; every bound is
  // checked against the member's own end before it is read
  LCount := DoBigEndian(ABytes, LBody, LWidth);
  if LCount > UInt64(LSize - LWidth) div UInt64(LWidth) then
    Exit;
  // Bounded by the member's size above: fits an Int64
  LNames := Int64(LCount);
  LPos := LBody + LWidth + LNames * LWidth;

  SetLength(ASymbols, LNames);
  LI := 0;
  while LI < LNames do
  begin
    LStart := LPos;
    while (LPos < LEnd) and (ABytes[LPos] <> 0) do
      Inc(LPos);
    // A name with no zero byte before the member ends: no whole index
    if LPos >= LEnd then
    begin
      ASymbols := nil;
      Exit;
    end;
    ASymbols[LI] := DoText(ABytes, LStart, LPos - LStart);
    Inc(LPos);
    Inc(LI);
  end;
  Result := True;
end;

class function TPCArchiveIndex.ReadFileSymbols(const AFilename: string;
  out ASymbols: TArray<string>; out AFailure: string): Boolean;
var
  LStream: TFileStream;
  LBytes: TBytes;
  LSize: Int64;
  LRead: Int64;
begin
  ASymbols := nil;
  AFailure := '';
  Result := False;
  try
    LStream := TFileStream.Create(AFilename, fmOpenRead or fmShareDenyWrite);
    try
      // The magic and the first header, then that member's body only
      SetLength(LBytes, PC_AR_MAGIC_SIZE + PC_AR_HEADER_SIZE);
      LRead := LStream.Read(LBytes, Length(LBytes));
      SetLength(LBytes, LRead);
      // An empty body holds no index: nothing more to read
      if DoMemberSize(LBytes, LSize) and (LSize > 0) and
        (LSize <= LStream.Size - LStream.Position) then
      begin
        SetLength(LBytes, Length(LBytes) + LSize);
        LStream.ReadBuffer(LBytes[PC_AR_MAGIC_SIZE + PC_AR_HEADER_SIZE], LSize);
        ReadSymbols(LBytes, ASymbols);
      end;
    finally
      LStream.Free();
    end;
    Result := True;
  except
    on E: Exception do
    begin
      ASymbols := nil;
      AFailure := E.Message;
    end;
  end;
end;

end.
