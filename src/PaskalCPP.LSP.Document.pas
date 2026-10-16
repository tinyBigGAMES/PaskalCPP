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
  PaskalCPP.LSP.Document - one open text document of the LSP server

  The client's buffer is the truth for an open document (didOpen,
  didChange). The text is kept with its line starts; positions inside are
  UTF-16. A client position is converted at the boundary, in the negotiated
  encoding. The frontend reads the buffer as UTF-8 bytes (GetBytes), and its
  byte columns become UTF-16 columns through TPCSourceText.Utf16Column, the
  routine the build output prints with (PROJECT.md "Printed columns").
  Adopted from FreeStrike.LSP.Document (plans\done\PLAN-EDITOR.md E2.1d).

  Dependencies: StdApp.Base, PaskalCPP.SourceText
  Notes:
    - Offsets are 0-based UTF-16 indexes into Text, end exclusive.
    - Line breaks: LF, CR LF, CR (the lexer's and the LSP's rule).
    - A client position past the end of its line means the line end; a
      line past the last line means the end of the text (LSP rule).
===============================================================================}

unit PaskalCPP.LSP.Document;

interface

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  System.JSON,
  StdApp.Base,
  PaskalCPP.SourceText;

type
  { TPCPositionEncoding }
  // LSP PositionEncodingKind: the unit of Position.character
  TPCPositionEncoding = (
    peUtf16,
    peUtf8,
    peUtf32
  );

  { TPCLspDocument }
  TPCLspDocument = class(TBaseObject)
  private
    FUri: string;
    FFilename: string;
    FLanguageId: string;
    FVersion: Integer;
    FText: string;
    FLineStarts: TList<Integer>;   // 0-based index of each line's first char
    FBytes: TBytes;                // FText in UTF-8; built on first use after a change
    FHaveBytes: Boolean;
    FSource: TPCSourceText;        // FBytes' line table; nil until a column is mapped
    procedure DoIndexLines();
    procedure DoTextChanged();
    // FBytes' line table, built on first use after a change
    function DoSource(): TPCSourceText;
    function DoLineContentEnd(const ALine: Integer): Integer;
    function DoCharAt(const AIndex: Integer; const ALimit: Integer;
      const AEncoding: TPCPositionEncoding; out AWidth16: Integer): Integer;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // AFilename is the resolved path the frontend reads the document as
    // (empty for a document that is no file: untitled:...).
    procedure Init(const AUri: string; const AFilename: string;
      const ALanguageId: string; const AVersion: Integer; const AText: string);

    // didChange: the whole text, or the UTF-16 span AStart..AEnd (end exclusive)
    procedure ReplaceAll(const AText: string);
    procedure Replace(const AStart: Integer; const AEnd: Integer; const AText: string);

    function LineCount(): Integer;
    // Client position (line, character in AEncoding) -> UTF-16 offset
    function OffsetAt(const ALine: Integer; const ACharacter: Integer;
      const AEncoding: TPCPositionEncoding): Integer;
    // UTF-16 column on ALine (both 0-based) -> character in AEncoding
    function ClientCharacter(const ALine: Integer; const AColumn: Integer;
      const AEncoding: TPCPositionEncoding): Integer;

    // The text as the frontend reads it: UTF-8, no BOM
    function GetBytes(): TBytes;
    // A frontend location (1-based line, 1-based UTF-8 byte column) as a
    // 0-based UTF-16 column on the 0-based line ALine - 1
    function ByteColumnToColumn(const ALine: UInt64; const AByteColumn: UInt64): Integer;
    // A client position (0-based line, character in AEncoding) as the
    // frontend's 1-based UTF-8 byte column on line ALine + 1; the inverse of
    // ByteColumnToColumn. A position inside a character is that character's
    // first byte; past the line's end, the byte after its last character
    function ByteColumnAt(const ALine: Integer; const ACharacter: Integer;
      const AEncoding: TPCPositionEncoding): UInt64;
    // The same position as a 0-based offset into GetBytes() (the frontend's
    // byte offsets: tokens, AST ranges, comment spans); a line the text does
    // not have is the offset past the last byte
    function ByteOffsetAt(const ALine: Integer; const ACharacter: Integer;
      const AEncoding: TPCPositionEncoding): UInt64;
    // A 0-based offset into GetBytes() as a client position (0-based line,
    // character in AEncoding): the inverse of ByteOffsetAt (formatting edits).
    // An offset past the text is the position after its last character
    procedure PositionAtByte(const AOffset: UInt64; const AEncoding: TPCPositionEncoding;
      out ALine: Integer; out ACharacter: Integer);

    property Uri: string read FUri;
    property Filename: string read FFilename;
    property LanguageId: string read FLanguageId;
    property Version: Integer read FVersion write FVersion;
    property Text: string read FText;
  end;

  { TPCLspRange }
  // A frontend range (1-based lines, 1-based UTF-8 byte columns, the end
  // naming the range's LAST byte) as an LSP Range (0-based, end exclusive, in
  // the client's encoding). ADocument holds the text the range refers to;
  // nil = the columns are taken as they are. No line (0) = an empty range at
  // the top of the file. One conversion for every range the server sends
  // (diagnostics, related locations, definitions)
  TPCLspRange = record
  private
    class function DoClampLine(const ADocument: TPCLspDocument; const ALine: UInt64): Integer; static;
    class function DoPosition(const ADocument: TPCLspDocument; const ALine: Integer;
      const AColumn16: Integer; const AEncoding: TPCPositionEncoding): TJSONObject; static;
  public
    // The caller owns the result
    class function ToJson(const ADocument: TPCLspDocument; const ARange: TSourceRange;
      const AEncoding: TPCPositionEncoding): TJSONObject; static;
  end;

implementation

{ TPCLspDocument }

constructor TPCLspDocument.Create();
begin
  inherited;

  FLineStarts := TList<Integer>.Create();
  FSource := nil;
  FHaveBytes := False;
end;

destructor TPCLspDocument.Destroy();
begin
  FSource.Free();
  FLineStarts.Free();

  inherited;
end;

procedure TPCLspDocument.Init(const AUri: string; const AFilename: string;
  const ALanguageId: string; const AVersion: Integer; const AText: string);
begin
  FUri := AUri;
  FFilename := AFilename;
  FLanguageId := ALanguageId;
  FVersion := AVersion;
  ReplaceAll(AText);
end;

procedure TPCLspDocument.DoIndexLines();
var
  LI: Integer;
begin
  // FText is 1-based: after a break ending at FText[LI], the next line
  // starts at 0-based index LI
  FLineStarts.Clear();
  FLineStarts.Add(0);
  LI := 1;
  while LI <= Length(FText) do
  begin
    if FText[LI] = #13 then
    begin
      if (LI < Length(FText)) and (FText[LI + 1] = #10) then
        Inc(LI);
      FLineStarts.Add(LI);
    end
    else if FText[LI] = #10 then
      FLineStarts.Add(LI);
    Inc(LI);
  end;
end;

procedure TPCLspDocument.DoTextChanged();
begin
  // Everything derived from the text is rebuilt on its next use
  DoIndexLines();
  FBytes := nil;
  FHaveBytes := False;
  FreeAndNil(FSource);
end;

function TPCLspDocument.DoSource(): TPCSourceText;
begin
  if FSource = nil then
  begin
    FSource := TPCSourceText.Create();
    FSource.Init(GetBytes(), FFilename);
  end;
  Result := FSource;
end;

function TPCLspDocument.DoLineContentEnd(const ALine: Integer): Integer;
begin
  // The offset just past the line's last char, before its line break
  if ALine >= FLineStarts.Count - 1 then
    Exit(Length(FText));

  Result := FLineStarts[ALine + 1];
  // FText[Result] is the last char before the next line (1-based)
  if (Result > FLineStarts[ALine]) and (FText[Result] = #10) then
    Dec(Result);
  if (Result > FLineStarts[ALine]) and (FText[Result] = #13) then
    Dec(Result);
end;

function TPCLspDocument.DoCharAt(const AIndex: Integer; const ALimit: Integer;
  const AEncoding: TPCPositionEncoding; out AWidth16: Integer): Integer;
var
  LCode: Cardinal;
  LLow: Cardinal;
begin
  // The code point at 0-based AIndex: its width in UTF-16 units
  // (AWidth16) and in AEncoding units (Result). A surrogate pair counts
  // only when both halves lie before ALimit; a lone surrogate is one
  // UTF-16 unit and three UTF-8 bytes
  LCode := Ord(FText[AIndex + 1]);
  AWidth16 := 1;
  if (LCode >= $D800) and (LCode <= $DBFF) and (AIndex + 1 < ALimit) then
  begin
    LLow := Ord(FText[AIndex + 2]);
    if (LLow >= $DC00) and (LLow <= $DFFF) then
    begin
      AWidth16 := 2;
      LCode := $10000 + ((LCode - $D800) shl 10) + (LLow - $DC00);
    end;
  end;

  case AEncoding of
    peUtf16:
      Result := AWidth16;
    peUtf32:
      Result := 1;
  else
    // UTF-8 byte count of the code point
    if LCode < $80 then
      Result := 1
    else if LCode < $800 then
      Result := 2
    else if LCode < $10000 then
      Result := 3
    else
      Result := 4;
  end;
end;

procedure TPCLspDocument.ReplaceAll(const AText: string);
begin
  FText := AText;
  DoTextChanged();
end;

procedure TPCLspDocument.Replace(const AStart: Integer; const AEnd: Integer;
  const AText: string);
var
  LStart: Integer;
  LEnd: Integer;
begin
  LStart := EnsureRange(AStart, 0, Length(FText));
  LEnd := EnsureRange(AEnd, LStart, Length(FText));
  FText := Copy(FText, 1, LStart) + AText + Copy(FText, LEnd + 1, MaxInt);
  DoTextChanged();
end;

function TPCLspDocument.LineCount(): Integer;
begin
  Result := FLineStarts.Count;
end;

function TPCLspDocument.OffsetAt(const ALine: Integer; const ACharacter: Integer;
  const AEncoding: TPCPositionEncoding): Integer;
var
  LPos: Integer;
  LEnd: Integer;
  LUnits: Integer;
  LStep: Integer;
  LWidth: Integer;
begin
  if ALine < 0 then
    Exit(0);
  if ALine >= LineCount() then
    Exit(Length(FText));

  LPos := FLineStarts[ALine];
  LEnd := DoLineContentEnd(ALine);
  LUnits := 0;
  while (LPos < LEnd) and (LUnits < ACharacter) do
  begin
    LStep := DoCharAt(LPos, LEnd, AEncoding, LWidth);
    // A position inside a character stays before it
    if LUnits + LStep > ACharacter then
      Break;
    Inc(LUnits, LStep);
    Inc(LPos, LWidth);
  end;
  Result := LPos;
end;

function TPCLspDocument.ClientCharacter(const ALine: Integer;
  const AColumn: Integer; const AEncoding: TPCPositionEncoding): Integer;
var
  LPos: Integer;
  LTarget: Integer;
  LWidth: Integer;
begin
  if (AEncoding = peUtf16) or (ALine < 0) or (ALine >= LineCount()) then
    Exit(AColumn);

  LPos := FLineStarts[ALine];
  LTarget := Min(LPos + AColumn, Length(FText));
  Result := 0;
  while LPos < LTarget do
  begin
    Inc(Result, DoCharAt(LPos, Length(FText), AEncoding, LWidth));
    Inc(LPos, LWidth);
  end;
end;

function TPCLspDocument.GetBytes(): TBytes;
begin
  // A lone surrogate in the buffer becomes U+FFFD (TEncoding.UTF8 replaces
  // it): the lexer then reports what it reads, never invalid UTF-8
  if not FHaveBytes then
  begin
    FBytes := TEncoding.UTF8.GetBytes(FText);
    FHaveBytes := True;
  end;
  Result := FBytes;
end;

function TPCLspDocument.ByteColumnToColumn(const ALine: UInt64;
  const AByteColumn: UInt64): Integer;
var
  LColumn: UInt64;
begin
  // The same mapping the build output prints with; a location the text does
  // not have comes back unchanged from Utf16Column, then clamps at 0
  LColumn := DoSource().Utf16Column(ALine, AByteColumn);
  if LColumn < 1 then
    Exit(0);
  Result := Integer(LColumn - 1);
end;

function TPCLspDocument.ByteColumnAt(const ALine: Integer; const ACharacter: Integer;
  const AEncoding: TPCPositionEncoding): UInt64;
var
  LStart: Integer;
  LOffset: Integer;
  LPrefix: string;
begin
  if (ALine < 0) or (ALine >= LineCount()) then
    Exit(1);

  // OffsetAt walks whole characters (a position inside one stays before it);
  // the UTF-8 length of the line's text before that offset is the column - 1.
  // A lone surrogate counts 3 bytes here as in GetBytes (both encode U+FFFD)
  LStart := FLineStarts[ALine];
  LOffset := OffsetAt(ALine, ACharacter, AEncoding);
  LPrefix := Copy(FText, LStart + 1, LOffset - LStart);
  Result := UInt64(TEncoding.UTF8.GetByteCount(LPrefix)) + 1;
end;

function TPCLspDocument.ByteOffsetAt(const ALine: Integer; const ACharacter: Integer;
  const AEncoding: TPCPositionEncoding): UInt64;
var
  LOffset: Integer;
  LPrefix: string;
begin
  if ALine < 0 then
    Exit(0);
  if ALine >= LineCount() then
    Exit(UInt64(Length(GetBytes())));

  // ByteColumnAt's rule over the whole text before the position: the UTF-8
  // length of everything before it, as GetBytes encodes it
  LOffset := OffsetAt(ALine, ACharacter, AEncoding);
  LPrefix := Copy(FText, 1, LOffset);
  Result := UInt64(TEncoding.UTF8.GetByteCount(LPrefix));
end;

procedure TPCLspDocument.PositionAtByte(const AOffset: UInt64;
  const AEncoding: TPCPositionEncoding; out ALine: Integer; out ACharacter: Integer);
var
  LOffset: Int64;
  LRange: TSourceRange;
  LColumn16: Integer;
begin
  // The byte offset's line and 1-based byte column from the bytes' own line
  // table, then the same column mapping every server range uses
  // (ByteColumnToColumn, then the client's encoding)
  LOffset := Int64(Min(AOffset, UInt64(Length(GetBytes()))));
  LRange := Default(TSourceRange);
  DoSource().FillRange(LRange, LOffset, LOffset);
  ALine := Integer(LRange.StartLine) - 1;
  LColumn16 := ByteColumnToColumn(LRange.StartLine, LRange.StartColumn);
  ACharacter := ClientCharacter(ALine, LColumn16, AEncoding);
end;

{ TPCLspRange }

class function TPCLspRange.DoClampLine(const ADocument: TPCLspDocument;
  const ALine: UInt64): Integer;
begin
  // 1-based frontend line -> 0-based line the document has
  if ALine < 1 then
    Exit(0);
  Result := Integer(ALine - 1);
  if (ADocument <> nil) and (Result >= ADocument.LineCount()) then
    Result := ADocument.LineCount() - 1;
  if Result < 0 then
    Result := 0;
end;

class function TPCLspRange.DoPosition(const ADocument: TPCLspDocument;
  const ALine: Integer; const AColumn16: Integer; const AEncoding: TPCPositionEncoding): TJSONObject;
var
  LCharacter: Integer;
begin
  LCharacter := AColumn16;
  if ADocument <> nil then
    LCharacter := ADocument.ClientCharacter(ALine, AColumn16, AEncoding);
  Result := TJSONObject.Create();
  Result.AddPair('line', TJSONNumber.Create(ALine));
  Result.AddPair('character', TJSONNumber.Create(LCharacter));
end;

class function TPCLspRange.ToJson(const ADocument: TPCLspDocument;
  const ARange: TSourceRange; const AEncoding: TPCPositionEncoding): TJSONObject;
var
  LStartLine: Integer;
  LStartColumn: Integer;
  LEndLine: Integer;
  LEndColumn: Integer;
begin
  // No line: an empty range at the top of the file
  if ARange.StartLine < 1 then
  begin
    Result := TJSONObject.Create();
    Result.AddPair('start', DoPosition(ADocument, 0, 0, AEncoding));
    Result.AddPair('end', DoPosition(ADocument, 0, 0, AEncoding));
    Exit;
  end;

  LStartLine := DoClampLine(ADocument, ARange.StartLine);
  LStartColumn := Integer(ARange.StartColumn) - 1;
  if ADocument <> nil then
    LStartColumn := ADocument.ByteColumnToColumn(ARange.StartLine, ARange.StartColumn);

  // The end names the last byte: the exclusive end is the byte after it. An
  // empty range (end offset = start offset) ends where it starts
  if (ARange.EndLine < 1) or (ARange.EndByteOffset <= ARange.StartByteOffset) then
  begin
    LEndLine := LStartLine;
    LEndColumn := LStartColumn;
  end
  else
  begin
    LEndLine := DoClampLine(ADocument, ARange.EndLine);
    LEndColumn := Integer(ARange.EndColumn);
    if ADocument <> nil then
      LEndColumn := ADocument.ByteColumnToColumn(ARange.EndLine, ARange.EndColumn + 1);
  end;

  if LStartColumn < 0 then
    LStartColumn := 0;
  Result := TJSONObject.Create();
  Result.AddPair('start', DoPosition(ADocument, LStartLine, LStartColumn, AEncoding));
  Result.AddPair('end', DoPosition(ADocument, LEndLine, LEndColumn, AEncoding));
end;

end.
