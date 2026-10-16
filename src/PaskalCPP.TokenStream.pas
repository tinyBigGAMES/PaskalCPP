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
  PaskalCPP.TokenStream - Token storage and cursor

  TPCTokenStream holds a token sequence plus the source text it was cut
  from (a TPCSourceText it owns: the bytes, the line table and the splice
  services), and owns the cursor API the parser uses: current / peek / next /
  match, parser-split of >> >= >>= <> inside template arguments, save and
  restore for backtracking, exact source slices and the lossless round trip.
  The lexer fills one stream and reads the source through it; the
  conditional filter reads it and appends the active tokens to a second
  stream; the parser cursors that one.
  It also keeps the lexer's inside-line marks (R23): the start of every line
  that begins inside a token or comment. The parser reads them from the
  lexer's stream onto verbatim nodes; a filter's output stream has none.
  It also keeps the C++ elements of every cppstart block (O-S6b): the lexer
  records them while it captures a block (# lines contribute none); the
  parser hands a body block's elements to TPCCppJumpFinder
  (PaskalCPP.CppJumps). A filter's output stream has none either.

  Dependencies: StdApp.Base (TBaseObject), StdApp.Resources (RSTks*),
    PaskalCPP.Common (TPCToken, TPCVocabulary split table),
    PaskalCPP.SourceText (TPCSourceText)
  Notes: Splits never mutate the token list. The position record carries
    them, so RestorePosition() undoes every split made after the save.
    Split pieces count LOGICAL bytes (line splices skipped), so a spliced
    >> (> \ newline >) splits like >>.
===============================================================================}

unit PaskalCPP.TokenStream;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.Common,
  PaskalCPP.SourceText;

type

  { TPCStreamPosition }
  // Index = current token; Skip = logical bytes of that token already passed
  // by splits; PieceLen = logical length of the current split piece (0 = the
  // rest of the token from Skip on).
  TPCStreamPosition = record
    Index: Integer;
    Skip: Integer;
    PieceLen: Integer;
  end;

  { TPCCppElementKind }
  // ceWord: an identifier or keyword spelling; ceLiteral: a string / char /
  // raw string / pp-number; cePunct: an operator or punctuator (longest match,
  // the lexer's table); ceOther: one byte sequence no rule takes (capture
  // accepts every byte)
  TPCCppElementKind = (ceWord, ceLiteral, cePunct, ceOther);

  { TPCCppElement }
  // One C++ element of a cppstart block (the lexer's DoCapture). Spelling is
  // splice-free; '' for ceLiteral (no rule reads a literal's text). TokenKind
  // is the vocabulary kind of a cePunct (tkUnknown otherwise): punctuators are
  // compared by kind, so every spelling of one kind (a digraph) reads the
  // same. Range is its .pcpp range (exclusive EndByteOffset, as tokens)
  TPCCppElement = record
    Kind: TPCCppElementKind;
    TokenKind: TPCTokenKind;
    Spelling: string;
    Range: TSourceRange;
  end;

  { TPCCommentSpan }
  // One comment the lexer skipped as trivia (PLAN-EDITOR E2.9 k4): byte
  // offsets, EndOffset exclusive; IsLine = a // comment (it runs to its line's
  // end, so a cursor at EndOffset is still in it)
  TPCCommentSpan = record
    StartOffset: Int64;
    EndOffset: Int64;
    IsLine: Boolean;
  end;

  { TPCTokenStream }
  TPCTokenStream = class(TBaseObject)
  private
    FTokens: TList<TPCToken>;
    FSourceText: TPCSourceText;
    FPos: TPCStreamPosition;
    FInsideStarts: TList<Int64>;  // line starts inside a token or comment, ascending (R23)
    FCppElements: TList<TPCCppElement>;  // cppstart blocks' C++ elements, ascending start (O-S6b)
    FDocLines: TDictionary<Integer, string>;  // source line -> its /// doc text (E2.6)
    FComments: TList<TPCCommentSpan>;  // skipped comments, ascending start (E2.9)

    function DoLogicalLength(const AToken: TPCToken): Integer;
    function DoLogicalAt(const AToken: TPCToken; const AIndex: Integer): Int64;
    function DoMaterialize(const APos: TPCStreamPosition): TPCToken;
    procedure DoAdvance(var APos: TPCStreamPosition);
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetErrors(const AErrors: TErrors); override;

    // Filling
    procedure Init(const ASource: TBytes; const AFilename: string);
    procedure Append(const AToken: TPCToken);

    // Lines that start inside a token or comment (R23): the lexer marks them
    // while it scans; InsideLines answers, as source line numbers
    procedure MarkInside(const AStart: Int64; const AEnd: Int64);
    function InsideLines(const AFrom: Int64; const AEnd: Int64): TArray<UInt64>;

    // C++ elements of cppstart blocks (O-S6b): the lexer adds them in byte
    // order while it captures a block; CppElementsIn answers the elements
    // starting in [AFrom, AEnd), ascending
    procedure AddCppElement(const AElement: TPCCppElement);
    function CppElementsIn(const AFrom: Int64; const AEnd: Int64): TArray<TPCCppElement>;

    // Doc comments (plans\done\PLAN-EDITOR.md E2.6): the lexer adds each `///`
    // line that is first on its line; DocAbove answers the contiguous block
    // of them ending on ALine - 1, top-down, joined by #10 ('' = none)
    procedure AddDocLine(const ALine: Integer; const AText: string);
    function DocAbove(const ALine: Integer): string;

    // Comments (PLAN-EDITOR E2.9): the lexer adds every comment it skips, in
    // byte order; InComment answers whether a cursor before byte AOffset is
    // inside one (after its opener; a // comment up to its line's end)
    procedure AddComment(const AStart: Int64; const AEnd: Int64; const AIsLine: Boolean);
    function InComment(const AOffset: Int64): Boolean;
    // The comments starting in [AFrom, AEnd), in byte order (PLAN-EDITOR
    // E2.10 f1: the formatter keeps each comment of a gap)
    function CommentsIn(const AFrom: Int64; const AEnd: Int64): TArray<TPCCommentSpan>;

    // Whole-stream access (copies only)
    function Count(): Integer;
    function TokenAt(const AIndex: Integer): TPCToken;
    function SourceBytes(): TBytes;
    function SourceFilename(): string;
    function SourceText(): TPCSourceText;

    // Cursor
    function CurrentToken(): TPCToken;
    function PeekToken(const AOffset: Integer): TPCToken;
    procedure NextToken();
    function Match(const AKind: TPCTokenKind): Boolean;
    function IsAtEnd(): Boolean;
    function SplitCurrent(): Boolean;
    function SavePosition(): TPCStreamPosition;
    procedure RestorePosition(const APosition: TPCStreamPosition);

    // Source
    function SourceSlice(const AStart: UInt64; const AEnd: UInt64): string;
    function ToSource(): string;
  end;

implementation

uses
  StdApp.Resources;

{ TPCTokenStream }

constructor TPCTokenStream.Create();
begin
  inherited;

  FTokens := TList<TPCToken>.Create();
  FSourceText := TPCSourceText.Create();
  FInsideStarts := TList<Int64>.Create();
  FCppElements := TList<TPCCppElement>.Create();
  FDocLines := TDictionary<Integer, string>.Create();
  FComments := TList<TPCCommentSpan>.Create();
  FPos.Index := 0;
  FPos.Skip := 0;
  FPos.PieceLen := 0;
end;

destructor TPCTokenStream.Destroy();
begin
  FComments.Free();
  FDocLines.Free();
  FCppElements.Free();
  FInsideStarts.Free();
  FSourceText.Free();
  FTokens.Free();

  inherited;
end;

procedure TPCTokenStream.SetErrors(const AErrors: TErrors);
begin
  inherited;

  FSourceText.SetErrors(AErrors);
end;

procedure TPCTokenStream.Init(const ASource: TBytes; const AFilename: string);
begin
  FTokens.Clear();
  FInsideStarts.Clear();
  FCppElements.Clear();
  FDocLines.Clear();
  FComments.Clear();
  FSourceText.Init(ASource, AFilename);
  FPos.Index := 0;
  FPos.Skip := 0;
  FPos.PieceLen := 0;
end;

procedure TPCTokenStream.Append(const AToken: TPCToken);
begin
  FTokens.Add(AToken);
end;

procedure TPCTokenStream.MarkInside(const AStart: Int64; const AEnd: Int64);
var
  LP: Int64;
  LNewline: Int64;
begin
  // Every line that starts strictly inside [AStart, AEnd). The lexer marks in
  // byte order, so a start not past the last one is already marked
  LP := AStart;
  while LP < AEnd do
  begin
    LNewline := FSourceText.NewlineLength(LP);
    if LNewline = 0 then
    begin
      Inc(LP);
      Continue;
    end;
    LP := LP + LNewline;
    if (LP < AEnd) and ((FInsideStarts.Count = 0) or
      (FInsideStarts[FInsideStarts.Count - 1] < LP)) then
      FInsideStarts.Add(LP);
  end;
end;

procedure TPCTokenStream.AddDocLine(const ALine: Integer; const AText: string);
begin
  FDocLines.AddOrSetValue(ALine, AText);
end;

function TPCTokenStream.DocAbove(const ALine: Integer): string;
var
  LLine: Integer;
  LText: string;
  LLines: TList<string>;
begin
  // Walk up from the line above while every line is a doc line; the block
  // reads top-down
  Result := '';
  LLines := TList<string>.Create();
  try
    LLine := ALine - 1;
    while (LLine >= 1) and FDocLines.TryGetValue(LLine, LText) do
    begin
      LLines.Insert(0, LText);
      Dec(LLine);
    end;
    if LLines.Count > 0 then
      Result := string.Join(#10, LLines.ToArray());
  finally
    LLines.Free();
  end;
end;

procedure TPCTokenStream.AddComment(const AStart: Int64; const AEnd: Int64; const AIsLine: Boolean);
var
  LSpan: TPCCommentSpan;
begin
  LSpan.StartOffset := AStart;
  LSpan.EndOffset := AEnd;
  LSpan.IsLine := AIsLine;
  FComments.Add(LSpan);
end;

function TPCTokenStream.InComment(const AOffset: Int64): Boolean;
var
  LLow: Integer;
  LHigh: Integer;
  LMid: Integer;
  LSpan: TPCCommentSpan;
begin
  // The last comment starting before AOffset (spans ascend and never
  // overlap); a cursor at its start is before the opener, not in it
  Result := False;
  LLow := 0;
  LHigh := FComments.Count;
  while LLow < LHigh do
  begin
    LMid := (LLow + LHigh) div 2;
    if FComments[LMid].StartOffset < AOffset then
      LLow := LMid + 1
    else
      LHigh := LMid;
  end;
  if LLow = 0 then
    Exit;
  LSpan := FComments[LLow - 1];
  if LSpan.IsLine then
    Result := AOffset <= LSpan.EndOffset
  else
    Result := AOffset < LSpan.EndOffset;
end;

function TPCTokenStream.CommentsIn(const AFrom: Int64;
  const AEnd: Int64): TArray<TPCCommentSpan>;
var
  LLow: Integer;
  LHigh: Integer;
  LMid: Integer;
  LLast: Integer;
  LI: Integer;
  LSpans: TArray<TPCCommentSpan>;
begin
  // Binary search for the first comment starting at or after AFrom: the
  // starts ascend (the lexer adds in byte order). Built in a local,
  // assigned last
  LLow := 0;
  LHigh := FComments.Count;
  while LLow < LHigh do
  begin
    LMid := (LLow + LHigh) div 2;
    if FComments[LMid].StartOffset < AFrom then
      LLow := LMid + 1
    else
      LHigh := LMid;
  end;

  LLast := LLow;
  while (LLast < FComments.Count) and (FComments[LLast].StartOffset < AEnd) do
    Inc(LLast);

  SetLength(LSpans, LLast - LLow);
  for LI := LLow to LLast - 1 do
    LSpans[LI - LLow] := FComments[LI];
  Result := LSpans;
end;

function TPCTokenStream.InsideLines(const AFrom: Int64; const AEnd: Int64): TArray<UInt64>;
var
  LLow: Integer;
  LHigh: Integer;
  LMid: Integer;
  LI: Integer;
begin
  // The lines of the marks strictly between AFrom and AEnd, ascending.
  // Binary search for the first mark past AFrom: the marks are ascending
  LLow := 0;
  LHigh := FInsideStarts.Count;
  while LLow < LHigh do
  begin
    LMid := (LLow + LHigh) div 2;
    if FInsideStarts[LMid] <= AFrom then
      LLow := LMid + 1
    else
      LHigh := LMid;
  end;

  Result := nil;
  LI := LLow;
  while (LI < FInsideStarts.Count) and (FInsideStarts[LI] < AEnd) do
  begin
    Result := Result + [UInt64(FSourceText.LineOf(FInsideStarts[LI]))];
    Inc(LI);
  end;
end;

procedure TPCTokenStream.AddCppElement(const AElement: TPCCppElement);
begin
  // The lexer records in byte order (one capture walk per block, blocks in
  // source order), so the list stays ascending without a sort
  FCppElements.Add(AElement);
end;

function TPCTokenStream.CppElementsIn(const AFrom: Int64;
  const AEnd: Int64): TArray<TPCCppElement>;
var
  LLow: Integer;
  LHigh: Integer;
  LMid: Integer;
  LLast: Integer;
  LI: Integer;
  LElements: TArray<TPCCppElement>;
begin
  // Binary search for the first element starting at or after AFrom: the
  // starts are ascending. Built in a local, assigned last
  LLow := 0;
  LHigh := FCppElements.Count;
  while LLow < LHigh do
  begin
    LMid := (LLow + LHigh) div 2;
    if Int64(FCppElements[LMid].Range.StartByteOffset) < AFrom then
      LLow := LMid + 1
    else
      LHigh := LMid;
  end;

  LLast := LLow;
  while (LLast < FCppElements.Count) and
    (Int64(FCppElements[LLast].Range.StartByteOffset) < AEnd) do
    Inc(LLast);

  SetLength(LElements, LLast - LLow);
  for LI := LLow to LLast - 1 do
    LElements[LI - LLow] := FCppElements[LI];
  Result := LElements;
end;

function TPCTokenStream.Count(): Integer;
begin
  Result := FTokens.Count;
end;

function TPCTokenStream.TokenAt(const AIndex: Integer): TPCToken;
begin
  if (AIndex < 0) or (AIndex >= FTokens.Count) then
  begin
    Result.Clear();
    Result.Kind := tkEOF;
    Exit;
  end;

  Result := FTokens[AIndex];
end;

function TPCTokenStream.SourceBytes(): TBytes;
begin
  Result := FSourceText.SourceBytes();
end;

function TPCTokenStream.SourceFilename(): string;
begin
  Result := FSourceText.SourceFilename();
end;

function TPCTokenStream.SourceText(): TPCSourceText;
begin
  // The one owner of the source bytes and the line table; the lexer reads
  // through it. Owned by the stream: callers never free it.
  Result := FSourceText;
end;

function TPCTokenStream.DoLogicalLength(const AToken: TPCToken): Integer;
var
  LP: Int64;
  LEnd: Int64;
begin
  // Logical bytes of the token: its physical bytes minus every line splice
  // inside it. A token starts on a logical byte, so the walk starts there.
  Result := 0;
  LP := Int64(AToken.Range.StartByteOffset);
  LEnd := Int64(AToken.Range.EndByteOffset);
  while LP < LEnd do
  begin
    Inc(Result);
    LP := FSourceText.NextLogical(LP);
  end;
end;

function TPCTokenStream.DoLogicalAt(const AToken: TPCToken; const AIndex: Integer): Int64;
var
  LI: Integer;
begin
  // Physical offset of the token's logical byte number AIndex (0-based)
  Result := Int64(AToken.Range.StartByteOffset);
  for LI := 1 to AIndex do
    Result := FSourceText.NextLogical(Result);
end;

function TPCTokenStream.DoMaterialize(const APos: TPCStreamPosition): TPCToken;
var
  LToken: TPCToken;
  LTotal: Integer;
  LLen: Integer;
  LStart: Int64;
  LEnd: Int64;
  LKind: TPCTokenKind;
begin
  if (APos.Index < 0) or (APos.Index >= FTokens.Count) then
  begin
    Result.Clear();
    Result.Kind := tkEOF;
    Exit;
  end;

  LToken := FTokens[APos.Index];
  if (APos.Skip = 0) and (APos.PieceLen = 0) then
    Exit(LToken);

  // A split piece: the logical bytes [Skip, Skip + piece length) of the
  // token. A piece starts on its first logical byte and ends right after
  // its last one; a splice between two pieces is the second piece's trivia.
  LTotal := DoLogicalLength(LToken);
  if APos.PieceLen > 0 then
    LLen := APos.PieceLen
  else
    LLen := LTotal - APos.Skip;
  LStart := DoLogicalAt(LToken, APos.Skip);
  LEnd := DoLogicalAt(LToken, APos.Skip + LLen - 1) + 1;

  Result := LToken;
  if APos.Skip > 0 then
    Result.TriviaStart := UInt64(DoLogicalAt(LToken, APos.Skip - 1) + 1);
  Result.Text := FSourceText.Slice(LStart, LEnd);
  Result.Spelling := FSourceText.Spelling(LStart, LEnd, -1);
  FSourceText.FillRange(Result.Range, LStart, LEnd);
  Result.Category := tcOperator;
  Result.Origin := toShared;

  // Every piece a split can produce is in PC_SPLIT_PIECES; a miss means the
  // split table and IsSplittable() disagree, an invariant violation
  if not TPCVocabulary.FindSplitPiece(Result.Spelling, LKind) then
    raise Exception.CreateFmt(RSTksSplitPiece, [Result.Spelling]);
  Result.Kind := LKind;
end;

procedure TPCTokenStream.DoAdvance(var APos: TPCStreamPosition);
var
  LTotal: Integer;
begin
  if FTokens.Count = 0 then
    Exit;

  // Inside a split token: move to the rest of it
  if APos.PieceLen > 0 then
  begin
    LTotal := DoLogicalLength(FTokens[APos.Index]);
    if APos.Skip + APos.PieceLen < LTotal then
    begin
      APos.Skip := APos.Skip + APos.PieceLen;
      APos.PieceLen := 0;
      Exit;
    end;
  end;

  // Next token; the last token (EOF) is never passed
  if APos.Index < FTokens.Count - 1 then
    Inc(APos.Index);
  APos.Skip := 0;
  APos.PieceLen := 0;
end;

function TPCTokenStream.CurrentToken(): TPCToken;
begin
  Result := DoMaterialize(FPos);
end;

function TPCTokenStream.PeekToken(const AOffset: Integer): TPCToken;
var
  LPos: TPCStreamPosition;
  LI: Integer;
begin
  LPos := FPos;
  for LI := 1 to AOffset do
    DoAdvance(LPos);
  Result := DoMaterialize(LPos);
end;

procedure TPCTokenStream.NextToken();
begin
  DoAdvance(FPos);
end;

function TPCTokenStream.Match(const AKind: TPCTokenKind): Boolean;
begin
  Result := CurrentToken().Kind = AKind;
  if Result then
    NextToken();
end;

function TPCTokenStream.IsAtEnd(): Boolean;
begin
  Result := CurrentToken().Kind = tkEOF;
end;

function TPCTokenStream.SplitCurrent(): Boolean;
begin
  // Present the first logical byte of the current >> >= >>= <> as its own
  // token; NextToken() then presents the rest
  Result := TPCVocabulary.IsSplittable(CurrentToken().Kind);
  if Result then
    FPos.PieceLen := 1;
end;

function TPCTokenStream.SavePosition(): TPCStreamPosition;
begin
  Result := FPos;
end;

procedure TPCTokenStream.RestorePosition(const APosition: TPCStreamPosition);
begin
  FPos := APosition;
end;

function TPCTokenStream.SourceSlice(const AStart: UInt64; const AEnd: UInt64): string;
begin
  if (AEnd <= AStart) or (AEnd > UInt64(FSourceText.ByteCount())) then
    Exit('');

  Result := FSourceText.Slice(Int64(AStart), Int64(AEnd));
end;

function TPCTokenStream.ToSource(): string;
var
  LBuilder: TStringBuilder;
  LI: Integer;
begin
  // Each token's trivia + text; for a lexer stream these tile the file
  LBuilder := TStringBuilder.Create();
  try
    for LI := 0 to FTokens.Count - 1 do
      LBuilder.Append(SourceSlice(FTokens[LI].TriviaStart, FTokens[LI].Range.EndByteOffset));
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

end.
