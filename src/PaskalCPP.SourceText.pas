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
  PaskalCPP.SourceText - Source bytes, line table, newline and splice services

  TPCSourceText owns the bytes of one source file and answers every question
  about their physical layout: where lines start (LF, CR LF and a lone CR are
  newlines, as clang counts), where a line splice (backslash, optional
  horizontal whitespace, newline) begins and ends, which byte is the next
  LOGICAL byte (splices removed), the splice-free spelling of a byte range,
  and the line / column range of a byte range. It reports nothing.

  Dependencies: StdApp.Base (TBaseObject, TSourceRange)
  Notes: research\cppmix\lexer-splice.md (contract) and
    lexer-splice-spelling.md (API). Lines and columns stay PHYSICAL: a
    splice still counts its newline.
===============================================================================}

unit PaskalCPP.SourceText;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base;

type

  { TPCSourceText }
  TPCSourceText = class(TBaseObject)
  private
    FBytes: TBytes;
    FFilename: string;
    FSize: Int64;
    FLineStarts: TList<Int64>;    // offset of each line's first byte; [0] = line 1

    procedure DoBuildLineTable();
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Filling: takes the bytes and builds the line table
    procedure Init(const ABytes: TBytes; const AFilename: string);

    // Whole-text access
    function SourceBytes(): TBytes;
    function SourceFilename(): string;
    function ByteCount(): Int64;
    function LineCount(): Integer;
    function FirstLineStart(): Int64;

    // Physical bytes
    function ByteAt(const AOffset: Int64): Integer;
    function Slice(const AStart: Int64; const AEnd: Int64): string;
    // Length of the UTF-8 sequence whose lead byte sits at AOffset, cut at the
    // end of the bytes; 0 past either end. The ONE lead-byte rule on source
    // bytes (lexer and parser); the lexer validated the input
    function Utf8Length(const AOffset: Int64): Int64;

    // Newlines and splices: the ONLY newline / splice tests of the compiler
    function NewlineLength(const AOffset: Int64): Int64;
    function SpliceNewlineOffset(const AOffset: Int64): Int64;
    function SpliceLength(const AOffset: Int64): Int64;
    function Logical(const AOffset: Int64): Int64;
    function NextLogical(const AOffset: Int64): Int64;
    function Spelling(const AStart: Int64; const AEnd: Int64;
      const ARawQuoteAt: Int64): string;

    // Positions
    function LineOf(const AOffset: Int64): Integer;
    procedure FillRange(var ARange: TSourceRange; const AStart: Int64; const AEnd: Int64);
    // The column a person and an editor count (UTF-16 code units, 1-based,
    // as Monaco / VS Code / LSP) of byte column AByteColumn on line ALine.
    // Columns past the line's end count one unit per byte; a line or column
    // the text does not have comes back unchanged. Presentation only: every
    // stored column stays a byte column (clang's unit)
    function Utf16Column(const ALine: UInt64; const AByteColumn: UInt64): UInt64;
  end;

implementation

uses
  System.Math;

{ TPCSourceText }

constructor TPCSourceText.Create();
begin
  inherited;

  FLineStarts := TList<Int64>.Create();
  FBytes := nil;
  FFilename := '';
  FSize := 0;

  // An empty text still has line 1, so LineOf / FillRange work before Init
  FLineStarts.Add(0);
end;

destructor TPCSourceText.Destroy();
begin
  FLineStarts.Free();

  inherited;
end;

procedure TPCSourceText.Init(const ABytes: TBytes; const AFilename: string);
begin
  FBytes := ABytes;
  FFilename := AFilename;
  FSize := Length(ABytes);
  DoBuildLineTable();
end;

procedure TPCSourceText.DoBuildLineTable();
var
  LI: Int64;
  LNewline: Int64;
begin
  FLineStarts.Clear();

  // Line 1 starts after a UTF-8 BOM (clang ignores it); offsets still index
  // the file bytes
  if (FSize >= 3) and (FBytes[0] = $EF) and (FBytes[1] = $BB) and (FBytes[2] = $BF) then
    FLineStarts.Add(3)
  else
    FLineStarts.Add(0);

  // Every newline starts the next line: LF, CR LF (one newline) or a lone CR.
  // A splice's newline counts too: lines stay physical.
  LI := 0;
  while LI < FSize do
  begin
    LNewline := NewlineLength(LI);
    if LNewline > 0 then
    begin
      LI := LI + LNewline;
      FLineStarts.Add(LI);
    end
    else
      Inc(LI);
  end;
end;

function TPCSourceText.SourceBytes(): TBytes;
begin
  Result := FBytes;
end;

function TPCSourceText.SourceFilename(): string;
begin
  Result := FFilename;
end;

function TPCSourceText.ByteCount(): Int64;
begin
  Result := FSize;
end;

function TPCSourceText.LineCount(): Integer;
begin
  Result := FLineStarts.Count;
end;

function TPCSourceText.FirstLineStart(): Int64;
begin
  // Offset of line 1's first byte: 3 after a UTF-8 BOM, else 0
  Result := FLineStarts[0];
end;

function TPCSourceText.ByteAt(const AOffset: Int64): Integer;
begin
  // -1 past either end, so look-ahead never needs its own bounds check
  if (AOffset >= 0) and (AOffset < FSize) then
    Result := FBytes[AOffset]
  else
    Result := -1;
end;

function TPCSourceText.Slice(const AStart: Int64; const AEnd: Int64): string;
var
  LStart: Int64;
  LEnd: Int64;
begin
  // The exact physical bytes [AStart, AEnd) as UTF-8 text, clamped to the
  // text so the RTL call never sees an out-of-range index
  LStart := Max(AStart, Int64(0));
  LEnd := Min(AEnd, FSize);
  if LEnd <= LStart then
    Exit('');

  // TEncoding.GetString takes an Integer index and count (RTL limit, inherent)
  Result := TEncoding.UTF8.GetString(FBytes, Integer(LStart), Integer(LEnd - LStart));
end;

function TPCSourceText.Utf8Length(const AOffset: Int64): Int64;
var
  LByte: Integer;
begin
  // A splice never sits inside a sequence ('\' is ASCII): a caller steps the
  // length, then Logical (NextLogical's comment)
  LByte := ByteAt(AOffset);
  if LByte < 0 then
    Exit(0);
  if LByte >= $F0 then
    Result := 4
  else if LByte >= $E0 then
    Result := 3
  else if LByte >= $C0 then
    Result := 2
  else
    Result := 1;
  Result := Min(Result, FSize - AOffset);
end;

function TPCSourceText.NewlineLength(const AOffset: Int64): Int64;
var
  LByte: Integer;
begin
  // clang's newline set: LF (1), CR LF (2), or a lone CR (1); 0 = no newline
  LByte := ByteAt(AOffset);
  if LByte = 10 then
    Result := 1
  else if LByte = 13 then
  begin
    if ByteAt(AOffset + 1) = 10 then
      Result := 2
    else
      Result := 1;
  end
  else
    Result := 0;
end;

function TPCSourceText.SpliceNewlineOffset(const AOffset: Int64): Int64;
var
  LP: Int64;
begin
  // A splice is '\', zero or more horizontal whitespace (tab 9, VT 11,
  // FF 12, space 32), then a newline. Result = the offset of that newline;
  // -1 = no splice here (no '\', EOF after it, or code after '\' + spaces).
  // A whitespace splice is one whose newline is not right after the '\'.
  Result := -1;
  if ByteAt(AOffset) <> Ord('\') then
    Exit;

  LP := AOffset + 1;
  while (ByteAt(LP) = 9) or (ByteAt(LP) = 11) or (ByteAt(LP) = 12) or (ByteAt(LP) = 32) do
    Inc(LP);

  if NewlineLength(LP) > 0 then
    Result := LP;
end;

function TPCSourceText.SpliceLength(const AOffset: Int64): Int64;
var
  LNewlineAt: Int64;
begin
  // Total bytes of the splice that starts at AOffset ('\' through its
  // newline); 0 = no splice here
  LNewlineAt := SpliceNewlineOffset(AOffset);
  if LNewlineAt < 0 then
    Result := 0
  else
    Result := LNewlineAt + NewlineLength(LNewlineAt) - AOffset;
end;

function TPCSourceText.Logical(const AOffset: Int64): Int64;
var
  LLength: Int64;
begin
  // The first byte at or after AOffset that does not begin a splice;
  // consecutive splices are all skipped. Pure: reports nothing.
  Result := AOffset;
  LLength := SpliceLength(Result);
  while LLength > 0 do
  begin
    Result := Result + LLength;
    LLength := SpliceLength(Result);
  end;
end;

function TPCSourceText.NextLogical(const AOffset: Int64): Int64;
begin
  // The logical byte after the (logical, single) byte at AOffset. A splice
  // never sits inside a UTF-8 sequence ('\' is ASCII), so a caller stepping
  // a multi-byte character steps its length and then calls Logical.
  Result := Logical(AOffset + 1);
end;

function TPCSourceText.Spelling(const AStart: Int64; const AEnd: Int64;
  const ARawQuoteAt: Int64): string;
var
  LStart: Int64;
  LEnd: Int64;
  LLimit: Int64;
  LBuffer: TBytes;
  LCount: Int64;
  LP: Int64;
begin
  // The text of [AStart, AEnd) with every splice removed. For a raw string
  // (ARawQuoteAt = offset of its opening quote, inside the range) splices
  // are removed only BEFORE the quote; delimiter, body and closer stay
  // physical (clang reverts splices in a raw body). ARawQuoteAt < 0 = no raw.
  LStart := Max(AStart, Int64(0));
  LEnd := Min(AEnd, FSize);
  if LEnd <= LStart then
    Exit('');

  if (ARawQuoteAt >= LStart) and (ARawQuoteAt < LEnd) then
    LLimit := ARawQuoteAt
  else
    LLimit := LEnd;

  // Logical bytes never outnumber physical ones
  SetLength(LBuffer, LEnd - LStart);
  LCount := 0;

  // Spliced part: copy logical bytes one at a time ('\' is ASCII, so a
  // splice never cuts a UTF-8 sequence and byte copies keep them whole)
  LP := Logical(LStart);
  while LP < LLimit do
  begin
    LBuffer[LCount] := FBytes[LP];
    Inc(LCount);
    LP := NextLogical(LP);
  end;

  // Raw part: the physical bytes from the opening quote to the end
  if LLimit < LEnd then
  begin
    Move(FBytes[LLimit], LBuffer[LCount], LEnd - LLimit);
    LCount := LCount + (LEnd - LLimit);
  end;

  // TEncoding.GetString takes an Integer index and count (RTL limit, inherent)
  Result := TEncoding.UTF8.GetString(LBuffer, 0, Integer(LCount));
end;

function TPCSourceText.LineOf(const AOffset: Int64): Integer;
var
  LLow: Integer;
  LHigh: Integer;
  LMid: Integer;
begin
  // Binary search: the last line whose start is <= AOffset
  LLow := 0;
  LHigh := FLineStarts.Count - 1;
  while LLow < LHigh do
  begin
    LMid := (LLow + LHigh + 1) div 2;
    if FLineStarts[LMid] <= AOffset then
      LLow := LMid
    else
      LHigh := LMid - 1;
  end;
  Result := LLow + 1;
end;

procedure TPCSourceText.FillRange(var ARange: TSourceRange; const AStart: Int64;
  const AEnd: Int64);
var
  LLine: Integer;
  LLast: Int64;
begin
  ARange.Filename := FFilename;
  ARange.StartByteOffset := UInt64(AStart);
  ARange.EndByteOffset := UInt64(AEnd);

  // Columns are 1-based byte counts from the line start, as clang counts
  LLine := LineOf(AStart);
  ARange.StartLine := UInt64(LLine);
  ARange.StartColumn := UInt64(Max(Int64(1), AStart - FLineStarts[LLine - 1] + 1));

  // The end names the LAST byte; an empty range ends where it starts
  if AEnd > AStart then
    LLast := AEnd - 1
  else
    LLast := AStart;
  LLine := LineOf(LLast);
  ARange.EndLine := UInt64(LLine);
  ARange.EndColumn := UInt64(Max(Int64(1), LLast - FLineStarts[LLine - 1] + 1));
end;

function TPCSourceText.Utf16Column(const ALine: UInt64; const AByteColumn: UInt64): UInt64;
var
  LOffset: Int64;
  LTarget: Int64;
  LLength: Int64;
  LUnits: UInt64;
begin
  if (ALine < 1) or (ALine > UInt64(FLineStarts.Count)) or (AByteColumn < 1) then
    Exit(AByteColumn);

  // Walk the line's code points up to the byte of the column: a 4-byte
  // sequence (past U+FFFF) is 2 UTF-16 units, every other one 1
  LOffset := FLineStarts[Integer(ALine) - 1];
  LTarget := LOffset + Int64(AByteColumn) - 1;
  LUnits := 1;
  while LOffset < LTarget do
  begin
    // At the line's end (or the text's): the rest counts one unit per byte
    if (NewlineLength(LOffset) > 0) or (LOffset >= FSize) then
    begin
      Inc(LUnits, UInt64(LTarget - LOffset));
      Break;
    end;
    LLength := Utf8Length(LOffset);
    if LLength = 4 then
      Inc(LUnits, 2)
    else
      Inc(LUnits);
    Inc(LOffset, LLength);
  end;
  Result := LUnits;
end;

end.
