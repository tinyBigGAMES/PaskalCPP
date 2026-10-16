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
  PaskalCPP.SerializedDiag - clang serialized diagnostics (.dia) reader

  TPCSerializedDiagReader decodes the file clang writes for
  -serialize-diagnostic-file: the signature 'DIAG', then an LLVM bitstream
  (BLOCKINFO, BLOCK_META with the format version, one BLOCK_DIAG per
  diagnostic with its notes as nested BLOCK_DIAG children). Layout verified
  against clang 22.1.8 (research\zigbuild-followup\r5-dia-reader.md).

  Dependencies: StdApp.Base (TBaseObject), StdApp.Resources (RSSdg*)
  Notes: A pure parser: it reports nothing through TErrors. A malformed file
    is rejected whole (False + FailureText, no partial results); the caller
    reports it. Notes are flattened in clang's text order: a diagnostic's
    include chain first, then its attached notes; a note's own chain before it.
===============================================================================}

unit PaskalCPP.SerializedDiag;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  StdApp.Base;

const
  { PC_SDG_MAX_DEPTH }
  // Deepest note nesting accepted (clang nests one level per include, a
  // file nesting deeper than this is not one clang wrote)
  PC_SDG_MAX_DEPTH = 256;

type
  { TPCSerializedLevel }
  // clang's stable level numbering: 0 ignored .. 5 remark
  TPCSerializedLevel = (slIgnored, slNote, slWarning, slError, slFatal, slRemark);

  { TPCSerializedNote }
  // One note of a diagnostic. FilePath = '' means no location.
  TPCSerializedNote = record
    FilePath: string;
    Line: UInt64;
    Column: UInt64;
    MessageText: string;
  end;

  { TPCSerializedDiag }
  // One top-level diagnostic. FilePath is spelled as clang spelled it ('' =
  // no location); Notes in text order (see the unit notes).
  TPCSerializedDiag = record
    Level: TPCSerializedLevel;
    FilePath: string;
    Line: UInt64;
    Column: UInt64;
    CategoryText: string;
    FlagText: string;
    MessageText: string;
    Notes: TArray<TPCSerializedNote>;
  end;

  { TPCSerializedDiagReader }
  TPCSerializedDiagReader = class(TBaseObject)
  private type
    { TOp }
    // One abbreviation operand: Kind = SDG_OP_*, Value = literal or width
    TOp = record
      Kind: Byte;
      Value: UInt64;
    end;

    { TAbbrev }
    TAbbrev = TArray<TOp>;

    { TBlock }
    // A decoded BLOCK_DIAG: its own diagnostic (Diag.Notes unused) and the
    // flattened notes of the nested blocks read before / after its record
    TBlock = record
      HasDiag: Boolean;
      Diag: TPCSerializedDiag;
      Before: TArray<TPCSerializedNote>;
      After: TArray<TPCSerializedNote>;
    end;

  private
    FData: TBytes;
    FBitPos: UInt64;
    FBitCount: UInt64;
    FFailed: Boolean;
    FFailureText: string;
    FVersion: Int64;
    FBlockInfo: TDictionary<UInt64, TArray<TAbbrev>>;
    FFiles: TDictionary<UInt64, string>;
    FCategories: TDictionary<UInt64, string>;
    FFlags: TDictionary<UInt64, string>;
    FDiags: TList<TPCSerializedDiag>;

    procedure DoReset();
    procedure DoFail(const AText: string); overload;
    procedure DoFail(const AFormat: string; const AArgs: array of const); overload;
    function DoRead(const AWidth: UInt64; out AValue: UInt64): Boolean;
    function DoReadVBR(const AWidth: UInt64; out AValue: UInt64): Boolean;
    procedure DoAlign32();
    function DoReadBytes(const ACount: UInt64; out ABytes: TBytes): Boolean;
    function DoReadAbbrev(out AAbbrev: TAbbrev): Boolean;
    function DoReadScalar(const AOp: TOp; out AValue: UInt64): Boolean;
    function DoReadRecord(const AAbbrevId: UInt64; const AAbbrevs: TArray<TAbbrev>;
      out ACode: UInt64; out AFields: TArray<UInt64>; out ABlob: TBytes): Boolean;
    function DoReadBlockHeader(out ABlockId: UInt64; out AWidth: UInt64): Boolean;
    function DoBlockInfo(const AWidth: UInt64): Boolean;
    function DoBlock(const AWidth: UInt64; const ABlockId: UInt64;
      const ADepth: Integer; out ABlock: TBlock): Boolean;
    function DoRecord(const ABlockId: UInt64; const ACode: UInt64;
      const AFields: TArray<UInt64>; const ABlob: TBytes; var ABlock: TBlock): Boolean;
    function DoDiagRecord(const AFields: TArray<UInt64>; const ABlob: TBytes;
      var ABlock: TBlock): Boolean;
    function DoLookup(const ATable: TDictionary<UInt64, string>; const AId: UInt64;
      const AWhat: string; out AText: string): Boolean;
    function DoText(const ABytes: TBytes; out AText: string): Boolean;
    function DoTopLevel(): Boolean;

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Decode AData (a whole .dia file). False = malformed: FailureText()
    // says why and no diagnostic is kept.
    function LoadFromBytes(const AData: TBytes): Boolean;

    // Read and decode AFilename. False = unreadable or malformed.
    function LoadFromFile(const AFilename: string): Boolean;

    function DiagCount(): Integer;
    function GetDiag(const AIndex: Integer): TPCSerializedDiag;
    function FailureText(): string;
  end;

implementation

uses
  StdApp.Resources;

const
  { SDG_ABBREV_* }
  // Fixed abbreviation ids of the LLVM bitstream
  SDG_ABBREV_END_BLOCK = 0;
  SDG_ABBREV_ENTER_SUBBLOCK = 1;
  SDG_ABBREV_DEFINE = 2;
  SDG_ABBREV_UNABBREV_RECORD = 3;
  SDG_ABBREV_FIRST_APP = 4;

  { SDG_BLOCK_* }
  SDG_BLOCK_BLOCKINFO = 0;
  SDG_BLOCK_META = 8;
  SDG_BLOCK_DIAG = 9;

  { SDG_BLOCKINFO_SETBID }
  SDG_BLOCKINFO_SETBID = 1;

  { SDG_RECORD_* }
  SDG_RECORD_VERSION = 1;
  SDG_RECORD_DIAG = 2;
  SDG_RECORD_SOURCE_RANGE = 3;
  SDG_RECORD_DIAG_FLAG = 4;
  SDG_RECORD_CATEGORY = 5;
  SDG_RECORD_FILENAME = 6;
  SDG_RECORD_FIXIT = 7;

  { SDG_OP_* }
  SDG_OP_LITERAL = 0;
  SDG_OP_FIXED = 1;
  SDG_OP_VBR = 2;
  SDG_OP_ARRAY = 3;
  SDG_OP_CHAR6 = 4;
  SDG_OP_BLOB = 5;

  { SDG_MAX_VERSION }
  SDG_MAX_VERSION = 2;

  { SDG_TOP_WIDTH }
  // Abbreviation id width at the top level of the stream
  SDG_TOP_WIDTH = 2;

  { SDG_MAX_OPS }
  // More operands than any abbreviation clang defines; guards the allocation
  SDG_MAX_OPS = 64;

  { SDG_CHAR6 }
  SDG_CHAR6: string = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._';

{ TPCSerializedDiagReader }

constructor TPCSerializedDiagReader.Create();
begin
  inherited;

  FBlockInfo := TDictionary<UInt64, TArray<TAbbrev>>.Create();
  FFiles := TDictionary<UInt64, string>.Create();
  FCategories := TDictionary<UInt64, string>.Create();
  FFlags := TDictionary<UInt64, string>.Create();
  FDiags := TList<TPCSerializedDiag>.Create();
  DoReset();
end;

destructor TPCSerializedDiagReader.Destroy();
begin
  FreeAndNil(FDiags);
  FreeAndNil(FFlags);
  FreeAndNil(FCategories);
  FreeAndNil(FFiles);
  FreeAndNil(FBlockInfo);

  inherited;
end;

procedure TPCSerializedDiagReader.DoReset();
begin
  FData := nil;
  FBitPos := 0;
  FBitCount := 0;
  FFailed := False;
  FFailureText := '';
  FVersion := -1;
  FBlockInfo.Clear();
  FFiles.Clear();
  FCategories.Clear();
  FFlags.Clear();
  FDiags.Clear();
end;

procedure TPCSerializedDiagReader.DoFail(const AText: string);
begin
  // The first failure is the cause; later ones are its consequences
  if FFailed then
    Exit;
  FFailed := True;
  FFailureText := AText;
end;

procedure TPCSerializedDiagReader.DoFail(const AFormat: string;
  const AArgs: array of const);
begin
  DoFail(Format(AFormat, AArgs));
end;

function TPCSerializedDiagReader.DoRead(const AWidth: UInt64;
  out AValue: UInt64): Boolean;
var
  LI: UInt64;
  LBit: UInt64;
begin
  AValue := 0;
  Result := False;

  if AWidth > 64 then
  begin
    DoFail(RSSdgBadWidth, [Int64(AWidth), Int64(FBitPos)]);
    Exit;
  end;

  if FBitPos + AWidth > FBitCount then
  begin
    DoFail(RSSdgTruncated, [Int64(FBitPos)]);
    Exit;
  end;

  // Bits are LSB-first within little-endian bytes
  LI := 0;
  while LI < AWidth do
  begin
    LBit := FBitPos + LI;
    if (FData[LBit shr 3] and (1 shl (LBit and 7))) <> 0 then
      AValue := AValue or (UInt64(1) shl LI);
    Inc(LI);
  end;
  Inc(FBitPos, AWidth);
  Result := True;
end;

function TPCSerializedDiagReader.DoReadVBR(const AWidth: UInt64;
  out AValue: UInt64): Boolean;
var
  LPiece: UInt64;
  LHigh: UInt64;
  LShift: UInt64;
begin
  AValue := 0;
  Result := False;

  // A VBR chunk needs a continuation bit plus at least one payload bit
  if (AWidth < 2) or (AWidth > 32) then
  begin
    DoFail(RSSdgBadWidth, [Int64(AWidth), Int64(FBitPos)]);
    Exit;
  end;

  LHigh := UInt64(1) shl (AWidth - 1);
  LShift := 0;
  while True do
  begin
    if not DoRead(AWidth, LPiece) then
      Exit;

    AValue := AValue or ((LPiece and (LHigh - 1)) shl LShift);
    if (LPiece and LHigh) = 0 then
      Break;

    // The next chunk would start past bit 63: not a value clang writes
    Inc(LShift, AWidth - 1);
    if LShift > 63 then
    begin
      DoFail(RSSdgBadVbr, [Int64(FBitPos)]);
      Exit;
    end;
  end;
  Result := True;
end;

procedure TPCSerializedDiagReader.DoAlign32();
begin
  FBitPos := (FBitPos + 31) and not UInt64(31);
end;

function TPCSerializedDiagReader.DoReadBytes(const ACount: UInt64;
  out ABytes: TBytes): Boolean;
var
  LStart: UInt64;
begin
  ABytes := nil;
  Result := False;

  if (FBitPos and 7) <> 0 then
  begin
    DoFail(RSSdgTruncated, [Int64(FBitPos)]);
    Exit;
  end;

  LStart := FBitPos shr 3;
  if (FBitPos > FBitCount) or (ACount > UInt64(Length(FData)) - LStart) then
  begin
    DoFail(RSSdgTruncated, [Int64(FBitPos)]);
    Exit;
  end;

  SetLength(ABytes, ACount);
  if ACount > 0 then
    Move(FData[LStart], ABytes[0], ACount);
  Inc(FBitPos, ACount * 8);
  Result := True;
end;

function TPCSerializedDiagReader.DoReadAbbrev(out AAbbrev: TAbbrev): Boolean;
var
  LCount: UInt64;
  LI: Integer;
  LIsLiteral: UInt64;
  LEncoding: UInt64;
begin
  AAbbrev := nil;
  Result := False;

  if not DoReadVBR(5, LCount) then
    Exit;
  if (LCount = 0) or (LCount > SDG_MAX_OPS) then
  begin
    DoFail(RSSdgBadAbbrev, [Int64(FBitPos)]);
    Exit;
  end;

  SetLength(AAbbrev, LCount);
  for LI := 0 to Integer(LCount) - 1 do
  begin
    if not DoRead(1, LIsLiteral) then
      Exit;

    if LIsLiteral <> 0 then
    begin
      AAbbrev[LI].Kind := SDG_OP_LITERAL;
      if not DoReadVBR(8, AAbbrev[LI].Value) then
        Exit;
      Continue;
    end;

    if not DoRead(3, LEncoding) then
      Exit;
    AAbbrev[LI].Kind := Byte(LEncoding);
    AAbbrev[LI].Value := 0;
    if (LEncoding = SDG_OP_FIXED) or (LEncoding = SDG_OP_VBR) then
    begin
      if not DoReadVBR(5, AAbbrev[LI].Value) then
        Exit;
    end
    else if (LEncoding <> SDG_OP_ARRAY) and (LEncoding <> SDG_OP_CHAR6) and
      (LEncoding <> SDG_OP_BLOB) then
    begin
      DoFail(RSSdgBadAbbrevEncoding, [Int64(LEncoding), Int64(FBitPos)]);
      Exit;
    end;
  end;

  // An array is the second-to-last operand, followed by its scalar element
  // type; a blob is the last operand
  for LI := 0 to High(AAbbrev) do
  begin
    if AAbbrev[LI].Kind = SDG_OP_ARRAY then
    begin
      if (LI <> High(AAbbrev) - 1) or
        not (AAbbrev[LI + 1].Kind in [SDG_OP_LITERAL, SDG_OP_FIXED, SDG_OP_VBR, SDG_OP_CHAR6]) then
      begin
        DoFail(RSSdgBadAbbrev, [Int64(FBitPos)]);
        Exit;
      end;
    end
    else if (AAbbrev[LI].Kind = SDG_OP_BLOB) and (LI <> High(AAbbrev)) then
    begin
      DoFail(RSSdgBadAbbrev, [Int64(FBitPos)]);
      Exit;
    end;
  end;
  Result := True;
end;

function TPCSerializedDiagReader.DoReadScalar(const AOp: TOp;
  out AValue: UInt64): Boolean;
var
  LIndex: UInt64;
begin
  AValue := 0;
  Result := False;

  if AOp.Kind = SDG_OP_LITERAL then
  begin
    AValue := AOp.Value;
    Result := True;
  end
  else if AOp.Kind = SDG_OP_FIXED then
    Result := DoRead(AOp.Value, AValue)
  else if AOp.Kind = SDG_OP_VBR then
    Result := DoReadVBR(AOp.Value, AValue)
  else if AOp.Kind = SDG_OP_CHAR6 then
  begin
    if not DoRead(6, LIndex) then
      Exit;
    AValue := Ord(SDG_CHAR6[Integer(LIndex) + 1]);
    Result := True;
  end
  else
    DoFail(RSSdgBadAbbrev, [Int64(FBitPos)]);
end;

function TPCSerializedDiagReader.DoReadRecord(const AAbbrevId: UInt64;
  const AAbbrevs: TArray<TAbbrev>; out ACode: UInt64;
  out AFields: TArray<UInt64>; out ABlob: TBytes): Boolean;
var
  LValues: TList<UInt64>;
  LOps: TAbbrev;
  LCount: UInt64;
  LValue: UInt64;
  LI: Integer;
  LJ: UInt64;
begin
  ACode := 0;
  AFields := nil;
  ABlob := nil;
  Result := False;

  LValues := TList<UInt64>.Create();
  try
    if AAbbrevId = SDG_ABBREV_UNABBREV_RECORD then
    begin
      // code, operand count, operands: all VBR6
      if not DoReadVBR(6, LValue) then
        Exit;
      LValues.Add(LValue);
      if not DoReadVBR(6, LCount) then
        Exit;
      // Every operand takes at least 6 bits: a larger count is truncated
      if LCount > (FBitCount - FBitPos) div 6 then
      begin
        DoFail(RSSdgTruncated, [Int64(FBitPos)]);
        Exit;
      end;
      LJ := 0;
      while LJ < LCount do
      begin
        if not DoReadVBR(6, LValue) then
          Exit;
        LValues.Add(LValue);
        Inc(LJ);
      end;
    end
    else
    begin
      if (AAbbrevId < SDG_ABBREV_FIRST_APP) or
        (AAbbrevId - SDG_ABBREV_FIRST_APP >= UInt64(Length(AAbbrevs))) then
      begin
        DoFail(RSSdgUnknownAbbrev, [Int64(AAbbrevId), Int64(FBitPos)]);
        Exit;
      end;

      LOps := AAbbrevs[AAbbrevId - SDG_ABBREV_FIRST_APP];
      LI := 0;
      while LI <= High(LOps) do
      begin
        if LOps[LI].Kind = SDG_OP_ARRAY then
        begin
          if not DoReadVBR(6, LCount) then
            Exit;
          if LCount > FBitCount - FBitPos then
          begin
            DoFail(RSSdgTruncated, [Int64(FBitPos)]);
            Exit;
          end;
          LJ := 0;
          while LJ < LCount do
          begin
            if not DoReadScalar(LOps[LI + 1], LValue) then
              Exit;
            LValues.Add(LValue);
            Inc(LJ);
          end;
          // the element operand was consumed with the array
          Inc(LI, 2);
          Continue;
        end;

        if LOps[LI].Kind = SDG_OP_BLOB then
        begin
          // length, align, bytes, align
          if not DoReadVBR(6, LCount) then
            Exit;
          DoAlign32();
          if not DoReadBytes(LCount, ABlob) then
            Exit;
          DoAlign32();
        end
        else
        begin
          if not DoReadScalar(LOps[LI], LValue) then
            Exit;
          LValues.Add(LValue);
        end;
        Inc(LI);
      end;
    end;

    if LValues.Count = 0 then
    begin
      DoFail(RSSdgBadRecord, ['?', Int64(FBitPos)]);
      Exit;
    end;

    ACode := LValues[0];
    AFields := Copy(LValues.ToArray(), 1, LValues.Count - 1);
    Result := True;
  finally
    LValues.Free();
  end;
end;

function TPCSerializedDiagReader.DoReadBlockHeader(out ABlockId: UInt64;
  out AWidth: UInt64): Boolean;
var
  LLength: UInt64;
begin
  AWidth := 0;
  Result := False;

  // ENTER_SUBBLOCK: block id VBR8, abbrev width VBR4, align, length word
  if not DoReadVBR(8, ABlockId) then
    Exit;
  if not DoReadVBR(4, AWidth) then
    Exit;
  if (AWidth < 2) or (AWidth > 32) then
  begin
    DoFail(RSSdgBadWidth, [Int64(AWidth), Int64(FBitPos)]);
    Exit;
  end;
  DoAlign32();
  Result := DoRead(32, LLength);
end;

function TPCSerializedDiagReader.DoBlockInfo(const AWidth: UInt64): Boolean;
var
  LAbbrevId: UInt64;
  LHasBlock: Boolean;
  LBlockId: UInt64;
  LAbbrev: TAbbrev;
  LList: TArray<TAbbrev>;
  LCode: UInt64;
  LFields: TArray<UInt64>;
  LBlob: TBytes;
begin
  Result := False;
  LHasBlock := False;
  LBlockId := 0;

  while True do
  begin
    if not DoRead(AWidth, LAbbrevId) then
      Exit;

    if LAbbrevId = SDG_ABBREV_END_BLOCK then
    begin
      DoAlign32();
      Result := True;
      Exit;
    end;

    if LAbbrevId = SDG_ABBREV_DEFINE then
    begin
      // An abbreviation belongs to the block SETBID selected last
      if not LHasBlock then
      begin
        DoFail(RSSdgBadAbbrev, [Int64(FBitPos)]);
        Exit;
      end;
      if not DoReadAbbrev(LAbbrev) then
        Exit;
      if not FBlockInfo.TryGetValue(LBlockId, LList) then
        LList := nil;
      SetLength(LList, Length(LList) + 1);
      LList[High(LList)] := LAbbrev;
      FBlockInfo.AddOrSetValue(LBlockId, LList);
    end
    else if LAbbrevId = SDG_ABBREV_UNABBREV_RECORD then
    begin
      if not DoReadRecord(LAbbrevId, nil, LCode, LFields, LBlob) then
        Exit;
      // BLOCKNAME / SETRECORDNAME carry names only: skipped
      if LCode = SDG_BLOCKINFO_SETBID then
      begin
        if Length(LFields) < 1 then
        begin
          DoFail(RSSdgBadRecord, ['SETBID', Int64(FBitPos)]);
          Exit;
        end;
        LBlockId := LFields[0];
        LHasBlock := True;
      end;
    end
    else
    begin
      DoFail(RSSdgUnknownAbbrev, [Int64(LAbbrevId), Int64(FBitPos)]);
      Exit;
    end;
  end;
end;

function TPCSerializedDiagReader.DoBlock(const AWidth: UInt64;
  const ABlockId: UInt64; const ADepth: Integer; out ABlock: TBlock): Boolean;
var
  LAbbrevs: TArray<TAbbrev>;
  LAbbrev: TAbbrev;
  LAbbrevId: UInt64;
  LSubId: UInt64;
  LSubWidth: UInt64;
  LChild: TBlock;
  LNote: TPCSerializedNote;
  LSequence: TArray<TPCSerializedNote>;
  LCode: UInt64;
  LFields: TArray<UInt64>;
  LBlob: TBytes;
begin
  ABlock := Default(TBlock);
  Result := False;

  if ADepth > PC_SDG_MAX_DEPTH then
  begin
    DoFail(RSSdgTooDeep, [PC_SDG_MAX_DEPTH, Int64(FBitPos)]);
    Exit;
  end;

  // Abbreviations from BLOCKINFO first, then the block's own, in order
  if not FBlockInfo.TryGetValue(ABlockId, LAbbrevs) then
    LAbbrevs := nil;
  LAbbrevs := Copy(LAbbrevs);

  while True do
  begin
    if not DoRead(AWidth, LAbbrevId) then
      Exit;

    if LAbbrevId = SDG_ABBREV_END_BLOCK then
    begin
      DoAlign32();
      if (ABlockId = SDG_BLOCK_DIAG) and (not ABlock.HasDiag) then
      begin
        DoFail(RSSdgNoDiagRecord, [Int64(FBitPos)]);
        Exit;
      end;
      Result := True;
      Exit;
    end;

    if LAbbrevId = SDG_ABBREV_ENTER_SUBBLOCK then
    begin
      if not DoReadBlockHeader(LSubId, LSubWidth) then
        Exit;
      // Only a diagnostic nests, and only notes (diagnostic blocks) in it
      if (LSubId <> SDG_BLOCK_DIAG) or (ABlockId <> SDG_BLOCK_DIAG) then
      begin
        DoFail(RSSdgUnexpectedBlock, [Int64(LSubId), Int64(FBitPos)]);
        Exit;
      end;
      if not DoBlock(LSubWidth, SDG_BLOCK_DIAG, ADepth + 1, LChild) then
        Exit;

      // The note in text order: its own chain, the note, its attached notes
      LNote.FilePath := LChild.Diag.FilePath;
      LNote.Line := LChild.Diag.Line;
      LNote.Column := LChild.Diag.Column;
      LNote.MessageText := LChild.Diag.MessageText;
      LSequence := LChild.Before;
      SetLength(LSequence, Length(LSequence) + 1);
      LSequence[High(LSequence)] := LNote;
      LSequence := LSequence + LChild.After;

      // Notes written before this block's own record are its include chain
      if ABlock.HasDiag then
        ABlock.After := ABlock.After + LSequence
      else
        ABlock.Before := ABlock.Before + LSequence;
      Continue;
    end;

    if LAbbrevId = SDG_ABBREV_DEFINE then
    begin
      if not DoReadAbbrev(LAbbrev) then
        Exit;
      SetLength(LAbbrevs, Length(LAbbrevs) + 1);
      LAbbrevs[High(LAbbrevs)] := LAbbrev;
      Continue;
    end;

    if not DoReadRecord(LAbbrevId, LAbbrevs, LCode, LFields, LBlob) then
      Exit;
    if not DoRecord(ABlockId, LCode, LFields, LBlob, ABlock) then
      Exit;
  end;
end;

function TPCSerializedDiagReader.DoRecord(const ABlockId: UInt64;
  const ACode: UInt64; const AFields: TArray<UInt64>; const ABlob: TBytes;
  var ABlock: TBlock): Boolean;
var
  LText: string;
begin
  Result := False;

  if ABlockId = SDG_BLOCK_META then
  begin
    if ACode = SDG_RECORD_VERSION then
    begin
      if Length(AFields) <> 1 then
      begin
        DoFail(RSSdgBadRecord, ['VERSION', Int64(FBitPos)]);
        Exit;
      end;
      if AFields[0] > SDG_MAX_VERSION then
      begin
        DoFail(RSSdgVersion, [Int64(AFields[0])]);
        Exit;
      end;
      FVersion := Int64(AFields[0]);
    end;
    Result := True;
    Exit;
  end;

  // BLOCK_DIAG. Field counts are exact, as clang's own reader requires;
  // unknown record codes are skipped, as clang's reader does.
  if ACode = SDG_RECORD_DIAG then
    Exit(DoDiagRecord(AFields, ABlob, ABlock));

  if (ACode = SDG_RECORD_FILENAME) or (ACode = SDG_RECORD_CATEGORY) or
    (ACode = SDG_RECORD_DIAG_FLAG) then
  begin
    if ((ACode = SDG_RECORD_FILENAME) and (Length(AFields) <> 4)) or
      ((ACode <> SDG_RECORD_FILENAME) and (Length(AFields) <> 2)) then
    begin
      DoFail(RSSdgBadRecord, [IntToStr(ACode), Int64(FBitPos)]);
      Exit;
    end;
    if not DoText(ABlob, LText) then
      Exit;
    // Ids are file-wide: emitted lazily inside whichever block needs one first
    if ACode = SDG_RECORD_FILENAME then
      FFiles.AddOrSetValue(AFields[0], LText)
    else if ACode = SDG_RECORD_CATEGORY then
      FCategories.AddOrSetValue(AFields[0], LText)
    else
      FFlags.AddOrSetValue(AFields[0], LText);
  end
  else if (ACode = SDG_RECORD_SOURCE_RANGE) and (Length(AFields) <> 8) then
  begin
    DoFail(RSSdgBadRecord, ['SOURCE_RANGE', Int64(FBitPos)]);
    Exit;
  end
  else if (ACode = SDG_RECORD_FIXIT) and (Length(AFields) <> 9) then
  begin
    DoFail(RSSdgBadRecord, ['FIXIT', Int64(FBitPos)]);
    Exit;
  end;
  Result := True;
end;

function TPCSerializedDiagReader.DoDiagRecord(const AFields: TArray<UInt64>;
  const ABlob: TBytes; var ABlock: TBlock): Boolean;
begin
  Result := False;

  // level, file id, line, column, offset, category id, flag id, message size
  if Length(AFields) <> 8 then
  begin
    DoFail(RSSdgBadRecord, ['DIAG', Int64(FBitPos)]);
    Exit;
  end;
  if ABlock.HasDiag then
  begin
    DoFail(RSSdgSecondDiagRecord, [Int64(FBitPos)]);
    Exit;
  end;
  if AFields[0] > UInt64(Ord(High(TPCSerializedLevel))) then
  begin
    DoFail(RSSdgUnknownLevel, [Int64(AFields[0]), Int64(FBitPos)]);
    Exit;
  end;

  ABlock.Diag.Level := TPCSerializedLevel(AFields[0]);
  ABlock.Diag.Line := AFields[2];
  ABlock.Diag.Column := AFields[3];

  // File id 0 = no location; category / flag id 0 = none
  if AFields[1] <> 0 then
  begin
    if not DoLookup(FFiles, AFields[1], 'FILENAME', ABlock.Diag.FilePath) then
      Exit;
  end;
  if AFields[5] <> 0 then
  begin
    if not DoLookup(FCategories, AFields[5], 'CATEGORY', ABlock.Diag.CategoryText) then
      Exit;
  end;
  if AFields[6] <> 0 then
  begin
    if not DoLookup(FFlags, AFields[6], 'DIAG_FLAG', ABlock.Diag.FlagText) then
      Exit;
  end;
  if not DoText(ABlob, ABlock.Diag.MessageText) then
    Exit;

  ABlock.HasDiag := True;
  Result := True;
end;

function TPCSerializedDiagReader.DoLookup(const ATable: TDictionary<UInt64, string>;
  const AId: UInt64; const AWhat: string; out AText: string): Boolean;
begin
  // clang emits a lazy record before the first record that uses its id
  Result := ATable.TryGetValue(AId, AText);
  if not Result then
    DoFail(RSSdgUnknownId, [AWhat, Int64(AId), Int64(FBitPos)]);
end;

function TPCSerializedDiagReader.DoText(const ABytes: TBytes;
  out AText: string): Boolean;
begin
  AText := '';
  Result := False;
  try
    AText := TEncoding.UTF8.GetString(ABytes);
    Result := True;
  except
    on E: Exception do
      DoFail(RSSdgBadText, [E.Message]);
  end;
end;

function TPCSerializedDiagReader.DoTopLevel(): Boolean;
var
  LAbbrevId: UInt64;
  LBlockId: UInt64;
  LWidth: UInt64;
  LBlock: TBlock;
  LDiag: TPCSerializedDiag;
begin
  Result := False;

  while FBitPos < FBitCount do
  begin
    if not DoRead(SDG_TOP_WIDTH, LAbbrevId) then
      Exit;
    if LAbbrevId <> SDG_ABBREV_ENTER_SUBBLOCK then
    begin
      DoFail(RSSdgUnknownAbbrev, [Int64(LAbbrevId), Int64(FBitPos)]);
      Exit;
    end;
    if not DoReadBlockHeader(LBlockId, LWidth) then
      Exit;

    if LBlockId = SDG_BLOCK_BLOCKINFO then
    begin
      if not DoBlockInfo(LWidth) then
        Exit;
    end
    else if LBlockId = SDG_BLOCK_META then
    begin
      if not DoBlock(LWidth, SDG_BLOCK_META, 0, LBlock) then
        Exit;
    end
    else if LBlockId = SDG_BLOCK_DIAG then
    begin
      if not DoBlock(LWidth, SDG_BLOCK_DIAG, 0, LBlock) then
        Exit;
      // A top-level diagnostic's notes: its include chain, then attached ones
      LDiag := LBlock.Diag;
      LDiag.Notes := LBlock.Before + LBlock.After;
      FDiags.Add(LDiag);
    end
    else
    begin
      DoFail(RSSdgUnexpectedBlock, [Int64(LBlockId), Int64(FBitPos)]);
      Exit;
    end;
  end;

  if FVersion < 0 then
  begin
    DoFail(RSSdgNoVersion);
    Exit;
  end;
  Result := True;
end;

function TPCSerializedDiagReader.LoadFromBytes(const AData: TBytes): Boolean;
begin
  DoReset();
  FData := AData;

  if (Length(FData) < 4) or (FData[0] <> Ord('D')) or (FData[1] <> Ord('I')) or
    (FData[2] <> Ord('A')) or (FData[3] <> Ord('G')) then
    DoFail(RSSdgBadSignature)
  else
  begin
    FBitPos := 32;
    FBitCount := UInt64(Length(FData)) * 8;
    DoTopLevel();
  end;

  // Nothing partial is kept from a malformed file
  if FFailed then
    FDiags.Clear();
  FData := nil;
  Result := not FFailed;
end;

function TPCSerializedDiagReader.LoadFromFile(const AFilename: string): Boolean;
var
  LBytes: TBytes;
begin
  try
    LBytes := TFile.ReadAllBytes(AFilename);
  except
    on E: Exception do
    begin
      DoReset();
      DoFail(RSSdgFileRead, [AFilename, E.Message]);
      Exit(False);
    end;
  end;
  Result := LoadFromBytes(LBytes);
end;

function TPCSerializedDiagReader.DiagCount(): Integer;
begin
  Result := FDiags.Count;
end;

function TPCSerializedDiagReader.GetDiag(const AIndex: Integer): TPCSerializedDiag;
begin
  Result := FDiags[AIndex];
end;

function TPCSerializedDiagReader.FailureText(): string;
begin
  Result := FFailureText;
end;

end.
