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
  PaskalCPP.LSP.Formatter - document formatting for the language server

  Gap model adopted from FreeStrike.LSP.Formatter (plans\done\PLAN-EDITOR.md
  E2.10, research\editor\formatting.md): a gap is the text between two
  tokens (whitespace and comments); the formatter writes gaps only, never a
  token's text, and keeps every comment's text. The layout comes from the
  analysed TPCModule; nothing here parses again.

  Dependencies: StdApp.Base, StdApp.Resources, PaskalCPP.Common,
    PaskalCPP.TokenStream, PaskalCPP.Lexer, PaskalCPP.AST
  Notes:
    - Offsets are UTF-8 byte offsets into the buffer (tokens, comments,
      edits); the server turns them into client positions.
    - A file with any lexer / parser report is refused (no edits); so is a
      result that does not lex back to the same tokens and comments.
    - A gap no rule decides is written as it stands; every gap inside a
      verbatim C++ node is (Q5).
===============================================================================}

unit PaskalCPP.LSP.Formatter;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Math,
  StdApp.Base,
  PaskalCPP.Common,
  PaskalCPP.SourceText,
  PaskalCPP.TokenStream,
  PaskalCPP.Lexer,
  PaskalCPP.AST;

const
  { PC_ERR_FMT_001 }
  // An exception inside a formatting run: the run is refused, no edits
  PC_ERR_FMT_001 = 'FM0001';

type
  { TPCLspFormatOptions }
  // formatting.md Options (user ok 2026-10-09: Q1)
  TPCLspFormatOptions = record
    IndentSize: Integer;
    UseTabs: Boolean;
    SpaceAroundAssign: Boolean;
    SpaceAroundOperators: Boolean;
    SpaceAfterComma: Boolean;
    SpaceBeforeColon: Boolean;
    SpaceAfterColon: Boolean;
    MaxBlankLines: Integer;
    TrimTrailingWhitespace: Boolean;
    FinalNewline: Boolean;
    MaxLineLength: Integer;
    class function Defaults(): TPCLspFormatOptions; static;
    // Numbers into their ranges (a client may send anything)
    procedure Clamp();
  end;

  { TPCLspFormatEdit }
  // Replace the buffer's bytes [StartOffset, EndOffset) with NewText
  TPCLspFormatEdit = record
    StartOffset: Int64;
    EndOffset: Int64;
    NewText: string;
  end;

  { TPCLspFormatEdits }
  TPCLspFormatEdits = TArray<TPCLspFormatEdit>;

  { TPCLspFormatRefusal }
  // frSyntax: the file has a lexer / parser report; frVerify: the result
  // would not lex back to the same tokens and comments; frInternal: an
  // exception inside the run
  TPCLspFormatRefusal = (frNone, frSyntax, frVerify, frInternal);

  { TPCLspGapKind }
  // gkKeep: the gap is written as it stands; gkHard: the token after it
  // starts a line at Level (R1 / R2); gkSpace: R3 decided its Text
  TPCLspGapKind = (gkKeep, gkHard, gkSpace);

  { TPCLspTokenRole }
  // What the tree says a token is (R3): trOperator = a binary / assignment /
  // ternary operator (a bitfield's ':' too), trPrefix / trPostfix = a unary
  // operator before / after its operand, trCallOpen = the '(' / '[' of a
  // call, an index or a routine heading
  TPCLspTokenRole = (trNone, trOperator, trPrefix, trPostfix, trCallOpen);

  { TPCLspSpaceWant }
  // R3 for one gap on a line: swKeep = as written, swNone = nothing,
  // swOne = one space (several written ones are kept: alignment, Q4)
  TPCLspSpaceWant = (swKeep, swNone, swOne);

  { TPCLspGap }
  // The bytes [StartOffset, EndOffset) before a token (gap I is before token
  // I; the last gap is after the last token, to the end of the buffer).
  // Original = its text, Comments = the comments inside it, Text = what the
  // render writes
  TPCLspGap = record
    StartOffset: Int64;
    EndOffset: Int64;
    Original: string;
    Comments: TArray<TPCCommentSpan>;
    Kind: TPCLspGapKind;
    Level: Integer;
    Locked: Boolean;
    Text: string;
    // R5: IsContinue = a gkHard continuation line (the statement's base
    // level is not changed by it); Broken = made by DoFit (one line ending
    // + indent); Table = inside a constant value written over several
    // lines (its lines kept, TableLevel = their level)
    IsContinue: Boolean;
    Broken: Boolean;
    Table: Boolean;
    TableLevel: Integer;
  end;

  { TPCLspFitCandidate }
  // R5: a gap a long line may break at, ranked like FS TFsFitCandidate:
  // lower is better in the order RankAssign (':=' last), Depth (bracket
  // depth), RankKind (',' / ';' before an operator), RankPrec (the
  // operator's binary nesting: the outermost, lowest precedence first)
  TPCLspFitCandidate = record
    Gap: Integer;
    Column: Integer;
    RankAssign: Integer;
    Depth: Integer;
    RankKind: Integer;
    RankPrec: Integer;
  end;

  { TPCLspFormatter }
  // Owns its TErrors (a formatting run never reports into the server's);
  // Refusal / RefusalReason tell why FormatSource returned False
  TPCLspFormatter = class(TBaseObject)
  private
    FOwnErrors: TErrors;
    FCheckErrors: TErrors;
    FStream: TPCTokenStream;
    FTokens: TArray<TPCToken>;
    FFilename: string;
    FModule: TPCModule;
    FOptions: TPCLspFormatOptions;
    FGaps: TArray<TPCLspGap>;
    FRoles: TArray<TPCLspTokenRole>;
    // A binary / ternary operator token's nesting in its operator chain
    // (0 = outermost); -1 = not such an operator (R5 ranks)
    FOpDepth: TArray<Integer>;
    FCandidates: TList<TPCLspFitCandidate>;
    FDropped: TArray<Boolean>;
    FEol: string;
    FRefusal: TPCLspFormatRefusal;
    FRefusalReason: string;
    procedure DoReset();
    procedure DoRefuse(const ARefusal: TPCLspFormatRefusal; const AReason: string);
    function DoFormat(const ABytes: TBytes; out AEdits: TPCLspFormatEdits): Boolean;
    function DoLex(const ABytes: TBytes): Boolean;
    procedure DoInitGaps();
    function DoFindEol(): string;

    // Tokens of the tree
    function DoTokenAt(const AOffset: Int64): Integer;
    function DoFirstToken(const ANode: TPCNode): Integer;
    function DoLastToken(const ANode: TPCNode): Integer;
    function DoLastEndToken(const ANode: TPCNode): Integer;
    function DoRangeToken(const ARange: TSourceRange): Integer;
    function DoKindAt(const AIndex: Integer): TPCTokenKind;

    // Layout (R1 / R2): which tokens start a line, at which level
    procedure DoHard(const AIndex: Integer; const ALevel: Integer);
    procedure DoHardItem(const AIndex: Integer; const ALevel: Integer);
    procedure DoLayoutModule(const AModule: TPCModule);
    procedure DoLayoutImports(const AModule: TPCModule);
    procedure DoLayoutList(const AItems: TList<TPCStmt>; const ALevel: Integer);
    procedure DoLayoutStmt(const AStmt: TPCStmt; const ALevel: Integer);
    procedure DoLayoutDecl(const ADecl: TPCDecl; const ALevel: Integer);
    procedure DoLayoutRoutine(const ARoutine: TPCRoutine; const ALevel: Integer);
    procedure DoLayoutBlock(const ABlock: TPCBlock; const ALevel: Integer);
    procedure DoLayoutTest(const ATest: TPCTest; const ALevel: Integer);
    procedure DoLayoutType(const AType: TPCTypeExpr; const ALevel: Integer);
    procedure DoLayoutMembers(const AMembers: TList<TPCMemberItem>; const ALevel: Integer);
    // PLAN-OBJECT O14: a property's line, then its inline accessors' bodies
    // one in (AAfterBody: a body was laid out, so the next accessor word or
    // `default` starts its own line one in)
    procedure DoLayoutProperty(const AProperty: TPCPropertyItem; const ALevel: Integer);
    procedure DoLayoutAccessor(const AAccessor: TPCAccessorItem; const ALevel: Integer;
      var AAfterBody: Boolean);
    procedure DoLayoutIf(const AIf: TPCIf; const ALevel: Integer);
    procedure DoLayoutMatch(const AMatch: TPCMatch; const ALevel: Integer);
    procedure DoLayoutGuard(const AGuard: TPCGuard; const ALevel: Integer);
    procedure DoLockVerbatim(const ANode: TPCNode);
    procedure DoLockRange(const ANode: TPCNode);

    // Spacing (R3)
    procedure DoMarkDropped();
    procedure DoMarkRoles(const ANode: TPCNode; const AOpDepth: Integer);
    procedure DoMarkRole(const AIndex: Integer; const ARole: TPCLspTokenRole);
    procedure DoMarkOperator(const AIndex: Integer; const AOpDepth: Integer);
    function DoOpBetween(const ALeft: TPCNode; const ARight: TPCNode): Integer;
    procedure DoSpacing();
    function DoWant(const ALeft: Integer; const ARight: Integer): TPCLspSpaceWant;
    function DoWouldFuse(const ALeft: Integer; const ARight: Integer): Boolean;

    // Long lines (R5)
    procedure DoMarkTable(const AValue: TPCExpr; const ALevel: Integer);
    function DoIsOwnedGap(const AIndex: Integer): Boolean;
    function DoJoinText(const AIndex: Integer): string;
    procedure DoJoinLines();
    function DoIsLineStart(const AIndex: Integer): Boolean;
    function DoLineBase(const AStart: Integer; const ABase: Integer): Integer;
    function DoLineEnd(const AStart: Integer): Integer;
    function DoIndentWidth(const ALevel: Integer): Integer;
    function DoStartColumn(const AStart: Integer): Integer;
    function DoCandidate(const AIndex: Integer; const AColumn: Integer; const ADepth: Integer;
      out ACandidate: TPCLspFitCandidate): Boolean;
    function DoFitLine(const AStart: Integer; const AEnd: Integer): Integer;
    procedure DoFit();

    // Output
    function DoIndentText(const ALevel: Integer): string;
    function DoPrevEndsLine(const AIndex: Integer): Boolean;
    function DoEolRun(const ARun: string; const AMin: Integer): string;
    function DoBreakText(const AIndex: Integer): string;
    function DoCommentLevel(const AIndex: Integer): Integer;
    function DoCommentGapText(const AIndex: Integer; const AIsEnd: Boolean): string;
    function DoEndText(const AIndex: Integer): string;
    procedure DoGapTexts();
    function DoRender(out AEdits: TPCLspFormatEdits): string;
    function DoVerify(const AText: string): Boolean;
    function DoCommentText(const AStream: TPCTokenStream; const ASpan: TPCCommentSpan): string;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    // ABytes = the buffer (UTF-8), AModule = the analysed module of the same
    // text, ASyntaxClean = the analysis reported no lexer / conditional /
    // parser error for this file. True = AEdits (empty when nothing changes)
    function FormatSource(const ABytes: TBytes; const AFilename: string;
      const AModule: TPCModule; const ASyntaxClean: Boolean;
      const AOptions: TPCLspFormatOptions; out AEdits: TPCLspFormatEdits): Boolean;
    property Refusal: TPCLspFormatRefusal read FRefusal;
    property RefusalReason: string read FRefusalReason;
  end;

implementation

uses
  StdApp.Resources;

{ CountEols }
// The line endings in AText (CR LF, LF and a lone CR count once each)
function CountEols(const AText: string): Integer;
var
  LI: Integer;
begin
  Result := 0;
  LI := 1;
  while LI <= Length(AText) do
  begin
    if AText[LI] = #13 then
    begin
      Inc(Result);
      if (LI < Length(AText)) and (AText[LI + 1] = #10) then
        Inc(LI);
    end
    else if AText[LI] = #10 then
      Inc(Result);
    Inc(LI);
  end;
end;

{ SplitLines }
// AText cut at its line endings: one more part than CountEols
function SplitLines(const AText: string): TArray<string>;
var
  LParts: TList<string>;
  LStart: Integer;
  LI: Integer;
begin
  LParts := TList<string>.Create();
  try
    LStart := 1;
    LI := 1;
    while LI <= Length(AText) do
    begin
      if (AText[LI] = #13) or (AText[LI] = #10) then
      begin
        LParts.Add(Copy(AText, LStart, LI - LStart));
        if (AText[LI] = #13) and (LI < Length(AText)) and (AText[LI + 1] = #10) then
          Inc(LI);
        LStart := LI + 1;
      end;
      Inc(LI);
    end;
    LParts.Add(Copy(AText, LStart, Length(AText) - LStart + 1));
    Result := LParts.ToArray();
  finally
    LParts.Free();
  end;
end;

{ IsWordChar }
// A character of an identifier, keyword or number
function IsWordChar(const AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

const
  { PC_FMT_ASSIGN_KINDS }
  // The assignment spellings: SpaceAroundAssign's (R3) and R5's last resort
  PC_FMT_ASSIGN_KINDS: set of TPCTokenKind = [tkColonEqual, tkPlusEqual, tkMinusEqual,
    tkStarEqual, tkSlashEqual, tkPercentEqual, tkAmpEqual, tkPipeEqual, tkLessLessEqual,
    tkGreaterGreaterEqual];

{ FirstLineWidth }
// The characters of AText before its first line ending
function FirstLineWidth(const AText: string): Integer;
var
  LI: Integer;
begin
  Result := Length(AText);
  for LI := 1 to Length(AText) do
  begin
    if (AText[LI] = #13) or (AText[LI] = #10) then
      Exit(LI - 1);
  end;
end;

{ LastLinePart }
// The text of AText after its last line ending (all of it when it has none)
function LastLinePart(const AText: string): string;
var
  LI: Integer;
begin
  for LI := Length(AText) downto 1 do
  begin
    if (AText[LI] = #13) or (AText[LI] = #10) then
      Exit(Copy(AText, LI + 1, Length(AText) - LI));
  end;
  Result := AText;
end;

{ IsBetterCandidate }
// ALeft ranks strictly better than ARight (FS IsBetterCandidate; a tie is
// not better)
function IsBetterCandidate(const ALeft: TPCLspFitCandidate;
  const ARight: TPCLspFitCandidate): Boolean;
begin
  if ALeft.RankAssign <> ARight.RankAssign then
    Exit(ALeft.RankAssign < ARight.RankAssign);
  if ALeft.Depth <> ARight.Depth then
    Exit(ALeft.Depth < ARight.Depth);
  if ALeft.RankKind <> ARight.RankKind then
    Exit(ALeft.RankKind < ARight.RankKind);
  Result := ALeft.RankPrec < ARight.RankPrec;
end;

{ TPCLspFormatOptions }

class function TPCLspFormatOptions.Defaults(): TPCLspFormatOptions;
begin
  // formatting.md Options (FS F4 defaults, user ok for PaskalCPP: Q1)
  Result.IndentSize := 2;
  Result.UseTabs := False;
  Result.SpaceAroundAssign := True;
  Result.SpaceAroundOperators := True;
  Result.SpaceAfterComma := True;
  Result.SpaceBeforeColon := False;
  Result.SpaceAfterColon := True;
  Result.MaxBlankLines := 1;
  Result.TrimTrailingWhitespace := True;
  Result.FinalNewline := True;
  // The traditional 80 columns (user 2026-10-10; was 100)
  Result.MaxLineLength := 80;
end;

procedure TPCLspFormatOptions.Clamp();
begin
  IndentSize := EnsureRange(IndentSize, 1, 8);
  MaxBlankLines := EnsureRange(MaxBlankLines, 0, 9);
  MaxLineLength := EnsureRange(MaxLineLength, 60, 200);
end;

{ TPCLspFormatter }

constructor TPCLspFormatter.Create();
begin
  inherited;

  FOwnErrors := TErrors.Create();
  FOwnErrors.SetMaxErrors(1000);
  FCheckErrors := TErrors.Create();
  FCheckErrors.SetMaxErrors(1000);
  FStream := nil;
  FModule := nil;
  FCandidates := TList<TPCLspFitCandidate>.Create();
  FRefusal := frNone;
end;

destructor TPCLspFormatter.Destroy();
begin
  DoReset();
  FCandidates.Free();
  FCheckErrors.Free();
  FOwnErrors.Free();

  inherited;
end;

procedure TPCLspFormatter.DoReset();
begin
  FStream.Free();
  FStream := nil;
  FTokens := nil;
  FModule := nil;
  FGaps := nil;
  FRoles := nil;
  FOpDepth := nil;
  FCandidates.Clear();
  FDropped := nil;
end;

procedure TPCLspFormatter.DoRefuse(const ARefusal: TPCLspFormatRefusal; const AReason: string);
begin
  FRefusal := ARefusal;
  FRefusalReason := AReason;
end;

function TPCLspFormatter.FormatSource(const ABytes: TBytes; const AFilename: string;
  const AModule: TPCModule; const ASyntaxClean: Boolean;
  const AOptions: TPCLspFormatOptions; out AEdits: TPCLspFormatEdits): Boolean;
begin
  // The whole run is guarded: an exception leaves no half-made edits
  AEdits := nil;
  FRefusal := frNone;
  FRefusalReason := '';
  FFilename := AFilename;
  FModule := AModule;
  FOptions := AOptions;
  FOptions.Clamp();

  // A recovered tree is a guessed layout (Q6): refuse
  if not ASyntaxClean then
  begin
    DoRefuse(frSyntax, RSLspFmtRefuseSyntax);
    Exit(False);
  end;

  try
    try
      Result := DoFormat(ABytes, AEdits);
    except
      on E: Exception do
      begin
        AEdits := nil;
        DoRefuse(frInternal, Format(RSLspFmtInternal, [E.Message]));
        FOwnErrors.Add(esError, PC_ERR_FMT_001, RSLspFmtInternal, [E.Message]);
        Result := False;
      end;
    end;
  finally
    DoReset();
  end;
end;

function TPCLspFormatter.DoFormat(const ABytes: TBytes; out AEdits: TPCLspFormatEdits): Boolean;
var
  LText: string;
  LEdits: TPCLspFormatEdits;
begin
  AEdits := nil;
  // An empty or all-blank buffer stays as it is (inside FormatSource's guard:
  // the RTL decode may raise)
  if TEncoding.UTF8.GetString(ABytes).Trim() = '' then
    Exit(True);
  if (FModule = nil) or not DoLex(ABytes) then
  begin
    DoRefuse(frSyntax, RSLspFmtRefuseSyntax);
    Exit(False);
  end;
  DoInitGaps();
  FEol := DoFindEol();
  DoLayoutModule(FModule);
  DoLockVerbatim(FModule);
  DoMarkDropped();
  DoSpacing();
  DoJoinLines();
  DoFit();
  DoGapTexts();
  LText := DoRender(LEdits);
  if not DoVerify(LText) then
  begin
    DoRefuse(frVerify, RSLspFmtRefuseVerify);
    Exit(False);
  end;
  AEdits := LEdits;
  Result := True;
end;

function TPCLspFormatter.DoLex(const ABytes: TBytes): Boolean;
var
  LLexer: TPCLexer;
  LI: Integer;
begin
  // The raw token stream of the buffer (inactive @if regions included: the
  // conditional filter runs in the parser, not here); any lexer report or a
  // tkUnknown token refuses
  FOwnErrors.Clear();
  FStream := TPCTokenStream.Create();
  FStream.SetErrors(FOwnErrors);
  LLexer := TPCLexer.Create();
  try
    LLexer.SetErrors(FOwnErrors);
    Result := LLexer.TokenizeBytes(ABytes, FFilename, FStream);
  finally
    LLexer.Free();
  end;
  if (not Result) or FOwnErrors.HasErrors() then
    Exit(False);
  SetLength(FTokens, FStream.Count());
  for LI := 0 to FStream.Count() - 1 do
  begin
    FTokens[LI] := FStream.TokenAt(LI);
    if FTokens[LI].Kind = tkUnknown then
      Exit(False);
  end;
  Result := Length(FTokens) > 0;
end;

procedure TPCLspFormatter.DoInitGaps();
var
  LCount: Integer;
  LI: Integer;
  LStart: Int64;
  LEnd: Int64;
begin
  // One gap before each token (EOF included) and one after the last token
  // to the end of the buffer; every gap starts kept as written
  LCount := Length(FTokens);
  SetLength(FGaps, LCount + 1);
  for LI := 0 to LCount do
  begin
    if LI = 0 then
      LStart := 0
    else
      LStart := Int64(FTokens[LI - 1].Range.EndByteOffset);
    if LI < LCount then
      LEnd := Int64(FTokens[LI].Range.StartByteOffset)
    else
      LEnd := FStream.SourceText().ByteCount();
    // The gaps and tokens tile the buffer: a token starting before the one
    // before it ends is a broken stream (invariant, FormatSource refuses)
    if LEnd < LStart then
      raise Exception.CreateFmt(RSLspFmtGapInvariant, [LStart]);
    FGaps[LI] := Default(TPCLspGap);
    FGaps[LI].StartOffset := LStart;
    FGaps[LI].EndOffset := LEnd;
    FGaps[LI].Original := FStream.SourceText().Slice(LStart, LEnd);
    FGaps[LI].Comments := FStream.CommentsIn(LStart, LEnd);
    FGaps[LI].Kind := gkKeep;
    FGaps[LI].Text := FGaps[LI].Original;
  end;
end;

function TPCLspFormatter.DoFindEol(): string;
var
  LBytes: TBytes;
  LI: Integer;
begin
  // The file's first line ending, else LF (F3 C11)
  LBytes := FStream.SourceBytes();
  for LI := 0 to High(LBytes) do
  begin
    if LBytes[LI] = 13 then
    begin
      if (LI < High(LBytes)) and (LBytes[LI + 1] = 10) then
        Exit(#13#10);
      Exit(#13);
    end;
    if LBytes[LI] = 10 then
      Exit(#10);
  end;
  Result := #10;
end;

{ TPCLspFormatter - tokens of the tree }

function TPCLspFormatter.DoTokenAt(const AOffset: Int64): Integer;
var
  LLow: Integer;
  LHigh: Integer;
  LMid: Integer;
begin
  // The token starting at byte AOffset, -1 for none (binary search: token
  // starts ascend)
  LLow := 0;
  LHigh := High(FTokens);
  while LLow <= LHigh do
  begin
    LMid := (LLow + LHigh) div 2;
    if Int64(FTokens[LMid].Range.StartByteOffset) = AOffset then
      Exit(LMid);
    if Int64(FTokens[LMid].Range.StartByteOffset) < AOffset then
      LLow := LMid + 1
    else
      LHigh := LMid - 1;
  end;
  Result := -1;
end;

function TPCLspFormatter.DoFirstToken(const ANode: TPCNode): Integer;
begin
  if (ANode = nil) or (ANode.Range.StartLine = 0) then
    Exit(-1);
  Result := DoTokenAt(Int64(ANode.Range.StartByteOffset));
end;

function TPCLspFormatter.DoLastToken(const ANode: TPCNode): Integer;
var
  LLow: Integer;
  LHigh: Integer;
  LMid: Integer;
  LEnd: Int64;
begin
  // The last token starting before the node's end, -1 for none
  if (ANode = nil) or (ANode.Range.StartLine = 0) then
    Exit(-1);
  LEnd := Int64(ANode.Range.EndByteOffset);
  LLow := 0;
  LHigh := High(FTokens);
  Result := -1;
  while LLow <= LHigh do
  begin
    LMid := (LLow + LHigh) div 2;
    if Int64(FTokens[LMid].Range.StartByteOffset) < LEnd then
    begin
      Result := LMid;
      LLow := LMid + 1;
    end
    else
      LHigh := LMid - 1;
  end;
end;

function TPCLspFormatter.DoLastEndToken(const ANode: TPCNode): Integer;
var
  LFirst: Integer;
  LI: Integer;
begin
  // A construct's closing `end` (if / while / for / match / guard / record /
  // overlay: no field holds it): the last `end` token inside its range; its
  // own `end` follows every statement it holds, so the last one is its own
  LFirst := DoFirstToken(ANode);
  if LFirst < 0 then
    Exit(-1);
  for LI := DoLastToken(ANode) downto LFirst do
  begin
    if FTokens[LI].Kind = tkKwEnd then
      Exit(LI);
  end;
  Result := -1;
end;

function TPCLspFormatter.DoRangeToken(const ARange: TSourceRange): Integer;
begin
  // The token a keyword range names (ElseRange, UntilRange, EndRange ...)
  if ARange.StartLine = 0 then
    Exit(-1);
  Result := DoTokenAt(Int64(ARange.StartByteOffset));
end;

function TPCLspFormatter.DoKindAt(const AIndex: Integer): TPCTokenKind;
begin
  if (AIndex < 0) or (AIndex > High(FTokens)) then
    Exit(tkUnknown);
  Result := FTokens[AIndex].Kind;
end;

{ TPCLspFormatter - layout }

procedure TPCLspFormatter.DoHard(const AIndex: Integer; const ALevel: Integer);
begin
  // The token at AIndex starts a line at ALevel; the first token starts the
  // file and EOF never moves
  if (AIndex <= 0) or (AIndex > High(FTokens)) or (FTokens[AIndex].Kind = tkEOF) then
    Exit;
  FGaps[AIndex].Kind := gkHard;
  FGaps[AIndex].Level := ALevel;
end;

procedure TPCLspFormatter.DoHardItem(const AIndex: Integer; const ALevel: Integer);
var
  LI: Integer;
begin
  // An item's line starts at its `exported` / `forward` words when it has
  // any (BNF sec 3: they come before the declaration)
  if AIndex < 0 then
    Exit;
  LI := AIndex;
  while (LI > 0) and (FTokens[LI - 1].Kind in [tkKwExported, tkKwForward]) do
    Dec(LI);
  DoHard(LI, ALevel);
end;

procedure TPCLspFormatter.DoLayoutModule(const AModule: TPCModule);
var
  LDirective: TPCDirective;
  LTest: TPCTest;
begin
  // R1 module level: everything at column 0, block entries one in
  for LDirective in AModule.Directives do
    DoHard(DoFirstToken(LDirective), 0);
  DoLayoutImports(AModule);
  DoLayoutList(AModule.Decls, 0);
  if AModule.InitRoutine <> nil then
    DoLayoutRoutine(AModule.InitRoutine, 0);
  if AModule.FinalRoutine <> nil then
    DoLayoutRoutine(AModule.FinalRoutine, 0);
  if AModule.HasBody and (AModule.Body <> nil) then
    DoLayoutBlock(AModule.Body, 0);
  DoHard(DoRangeToken(AModule.EndRange), 0);
  for LTest in AModule.Tests do
    DoLayoutTest(LTest, 0);
end;

procedure TPCLspFormatter.DoLayoutImports(const AModule: TPCModule);
var
  LImport: TPCImport;
  LFirst: Integer;
begin
  // R1 import: the word alone at column 0, one module per line one in
  // (BasicWindow.pcpp :14-15)
  for LImport in AModule.Imports do
  begin
    LFirst := DoFirstToken(LImport);
    if LFirst < 0 then
      Continue;
    if DoKindAt(LFirst - 1) = tkKwImport then
      DoHard(LFirst - 1, 0);
    DoHard(LFirst, 1);
  end;
end;

procedure TPCLspFormatter.DoLayoutList(const AItems: TList<TPCStmt>; const ALevel: Integer);
var
  LItem: TPCStmt;
begin
  // R2: one item per line
  for LItem in AItems do
    DoLayoutStmt(LItem, ALevel);
end;

procedure TPCLspFormatter.DoLayoutStmt(const AStmt: TPCStmt; const ALevel: Integer);
var
  LFirst: Integer;
begin
  if AStmt = nil then
    Exit;
  if AStmt is TPCDecl then
  begin
    DoLayoutDecl(TPCDecl(AStmt), ALevel);
    Exit;
  end;
  LFirst := DoFirstToken(AStmt);
  if AStmt is TPCBlock then
    DoLayoutBlock(TPCBlock(AStmt), ALevel)
  else if AStmt is TPCIf then
    DoLayoutIf(TPCIf(AStmt), ALevel)
  else if AStmt is TPCWhile then
  begin
    DoHard(LFirst, ALevel);
    DoLayoutList(TPCWhile(AStmt).Stmts, ALevel + 1);
    DoHard(DoLastEndToken(AStmt), ALevel);
  end
  else if AStmt is TPCFor then
  begin
    DoHard(LFirst, ALevel);
    DoLayoutList(TPCFor(AStmt).Stmts, ALevel + 1);
    DoHard(DoLastEndToken(AStmt), ALevel);
  end
  else if AStmt is TPCRepeat then
  begin
    DoHard(LFirst, ALevel);
    DoLayoutList(TPCRepeat(AStmt).Stmts, ALevel + 1);
    DoHard(DoRangeToken(TPCRepeat(AStmt).UntilRange), ALevel);
  end
  else if AStmt is TPCMatch then
    DoLayoutMatch(TPCMatch(AStmt), ALevel)
  else if AStmt is TPCGuard then
    DoLayoutGuard(TPCGuard(AStmt), ALevel)
  else if (AStmt is TPCVerbatimStmt) and (LFirst >= 0) and
    (FTokens[LFirst].Category = tcPreprocessor) then
    // A # line keeps its place: it is C++ text (Q5)
  else
    DoHard(LFirst, ALevel);
end;

procedure TPCLspFormatter.DoLayoutDecl(const ADecl: TPCDecl; const ALevel: Integer);
var
  LFirst: Integer;
begin
  // A var / const / type entry: its block word at ALevel, the entry one in;
  // a routine or a forward: an item at ALevel
  LFirst := DoFirstToken(ADecl);
  if LFirst < 0 then
    Exit;
  if ADecl is TPCRoutine then
  begin
    DoLayoutRoutine(TPCRoutine(ADecl), ALevel);
    Exit;
  end;
  // A forward type (`forward type T;`): one line at ALevel
  if (DoKindAt(LFirst) = tkKwForward) or
    ((DoKindAt(LFirst - 1) = tkKwType) and (DoKindAt(LFirst - 2) = tkKwForward)) then
  begin
    if DoKindAt(LFirst) = tkKwForward then
      DoHardItem(LFirst, ALevel)
    else
      DoHardItem(LFirst - 2, ALevel);
    Exit;
  end;
  // A range that starts at the block word itself
  if DoKindAt(LFirst) in [tkKwVar, tkKwConst, tkKwType] then
  begin
    DoHardItem(LFirst, ALevel);
    Inc(LFirst);
  end
  else if DoKindAt(LFirst - 1) in [tkKwVar, tkKwConst, tkKwType] then
    DoHardItem(LFirst - 1, ALevel);
  DoHard(LFirst, ALevel + 1);
  // R5: a constant value written over several lines keeps its lines (a
  // record / object / overlay body exists only in a type entry: BNF sec 3
  // type expr names none)
  if (ADecl is TPCTypeDecl) and (TPCTypeDecl(ADecl).TypeDef <> nil) then
    DoLayoutType(TPCTypeDecl(ADecl).TypeDef, ALevel + 1)
  else if ADecl is TPCConstDecl then
    DoMarkTable(TPCConstDecl(ADecl).ValueExpr, ALevel + 2);
end;

procedure TPCLspFormatter.DoLayoutRoutine(const ARoutine: TPCRoutine; const ALevel: Integer);
begin
  // R1 routine / method / section: heading at ALevel (its parameters stay
  // on the heading's line), local blocks at ALevel, entries one in, the
  // body's begin / end at ALevel
  DoHardItem(DoFirstToken(ARoutine), ALevel);
  DoLayoutList(ARoutine.Decls, ALevel);
  if ARoutine.Body <> nil then
    DoLayoutBlock(ARoutine.Body, ALevel);
end;

procedure TPCLspFormatter.DoLayoutBlock(const ABlock: TPCBlock; const ALevel: Integer);
begin
  DoHard(DoFirstToken(ABlock), ALevel);
  DoLayoutList(ABlock.Stmts, ALevel + 1);
  DoHard(DoRangeToken(ABlock.EndRange), ALevel);
end;

procedure TPCLspFormatter.DoLayoutTest(const ATest: TPCTest; const ALevel: Integer);
begin
  DoHard(DoFirstToken(ATest), ALevel);
  DoLayoutList(ATest.Decls, ALevel);
  if ATest.Body <> nil then
    DoLayoutBlock(ATest.Body, ALevel);
end;

procedure TPCLspFormatter.DoLayoutType(const AType: TPCTypeExpr; const ALevel: Integer);
begin
  // R1 types: a record / object / overlay body member by member one in, its
  // end at the entry's level; every other type stays on its line
  if AType is TPCRecordType then
  begin
    DoLayoutMembers(TPCRecordType(AType).Members, ALevel + 1);
    DoHard(DoLastEndToken(AType), ALevel);
  end
  else if AType is TPCOverlayType then
  begin
    DoLayoutMembers(TPCOverlayType(AType).Members, ALevel + 1);
    DoHard(DoLastEndToken(AType), ALevel);
  end;
end;

procedure TPCLspFormatter.DoLayoutMembers(const AMembers: TList<TPCMemberItem>;
  const ALevel: Integer);
var
  LMember: TPCMemberItem;
begin
  for LMember in AMembers do
  begin
    // A method, init, done, copy or operator (PLAN-OBJECT D3, O5, O11) lays
    // out as a routine; a property holds its accessors (O14)
    if LMember is TPCRoutineMember then
      DoLayoutRoutine(TPCRoutineMember(LMember).Routine, ALevel)
    else if LMember is TPCPropertyItem then
      DoLayoutProperty(TPCPropertyItem(LMember), ALevel)
    else if LMember is TPCAnonAggregate then
    begin
      DoHard(DoFirstToken(LMember), ALevel);
      DoLayoutMembers(TPCAnonAggregate(LMember).Members, ALevel + 1);
      DoHard(DoLastEndToken(LMember), ALevel);
    end
    else
      DoHard(DoFirstToken(LMember), ALevel);
  end;
end;

procedure TPCLspFormatter.DoLayoutProperty(const AProperty: TPCPropertyItem; const ALevel: Integer);
var
  LAfterBody: Boolean;
begin
  // `property X: T read FX; write FX;` stays one line; an inline accessor's
  // word ends the property's line, its body goes one in, and after a body
  // each later accessor and `default;` starts its own line one in (the
  // shipped files' layout: type_object_property_virtual)
  DoHard(DoFirstToken(AProperty), ALevel);
  LAfterBody := False;
  DoLayoutAccessor(AProperty.ReadItem, ALevel, LAfterBody);
  DoLayoutAccessor(AProperty.WriteItem, ALevel, LAfterBody);
  if AProperty.IsDefault and LAfterBody then
    DoHard(DoRangeToken(AProperty.DefaultRange), ALevel + 1);
end;

procedure TPCLspFormatter.DoLayoutAccessor(const AAccessor: TPCAccessorItem; const ALevel: Integer;
  var AAfterBody: Boolean);
var
  LWordRange: TSourceRange;
begin
  if AAccessor = nil then
    Exit;
  if AAfterBody then
  begin
    // Its own `hidden` comes first (`hidden write`); a hidden property's
    // accessors are hidden by the property's word, not their own
    LWordRange := AAccessor.WordRange;
    if AAccessor.IsHidden and (AAccessor.PropertyItem <> nil) and (not AAccessor.PropertyItem.IsHidden) then
      LWordRange := AAccessor.HiddenRange;
    DoHard(DoRangeToken(LWordRange), ALevel + 1);
  end;
  if (AAccessor.Routine <> nil) and (AAccessor.Routine.Body <> nil) then
  begin
    DoLayoutList(AAccessor.Routine.Decls, ALevel + 1);
    DoLayoutBlock(AAccessor.Routine.Body, ALevel + 1);
    AAfterBody := True;
  end;
end;

procedure TPCLspFormatter.DoLayoutIf(const AIf: TPCIf; const ALevel: Integer);
begin
  // R2: then's statements one in; else at the if's level, its statements
  // one in; end at the if's level
  DoHard(DoFirstToken(AIf), ALevel);
  DoLayoutList(AIf.ThenStmts, ALevel + 1);
  if AIf.HasElse then
  begin
    DoHard(DoRangeToken(AIf.ElseRange), ALevel);
    DoLayoutList(AIf.ElseStmts, ALevel + 1);
  end;
  DoHard(DoLastEndToken(AIf), ALevel);
end;

procedure TPCLspFormatter.DoLayoutMatch(const AMatch: TPCMatch; const ALevel: Integer);
var
  LArm: TPCMatchArm;
begin
  // R2: arms one in, an arm's statements two in; else at the match's
  // level, its statements one in; end at the match's level
  DoHard(DoFirstToken(AMatch), ALevel);
  for LArm in AMatch.Arms do
  begin
    DoHard(DoFirstToken(LArm), ALevel + 1);
    DoLayoutList(LArm.Stmts, ALevel + 2);
  end;
  if AMatch.HasElse then
  begin
    DoHard(DoRangeToken(AMatch.ElseRange), ALevel);
    DoLayoutList(AMatch.ElseStmts, ALevel + 1);
  end;
  DoHard(DoLastEndToken(AMatch), ALevel);
end;

procedure TPCLspFormatter.DoLayoutGuard(const AGuard: TPCGuard; const ALevel: Integer);
begin
  // R2: the guarded statements one in; except / finally at the guard's
  // level, their statements one in; end at the guard's level
  DoHard(DoFirstToken(AGuard), ALevel);
  DoLayoutList(AGuard.GuardStmts, ALevel + 1);
  if AGuard.HasExcept then
  begin
    DoHard(DoRangeToken(AGuard.ExceptRange), ALevel);
    DoLayoutList(AGuard.ExceptStmts, ALevel + 1);
  end;
  if AGuard.HasFinally then
  begin
    DoHard(DoRangeToken(AGuard.FinallyRange), ALevel);
    DoLayoutList(AGuard.FinallyStmts, ALevel + 1);
  end;
  DoHard(DoLastEndToken(AGuard), ALevel);
end;

procedure TPCLspFormatter.DoLockVerbatim(const ANode: TPCNode);
begin
  // Q5: every gap inside a verbatim C++ node is written as it stands
  if ANode = nil then
    Exit;
  if (ANode is TPCVerbatimStmt) or (ANode is TPCVerbatimExpr) or (ANode is TPCCppType) or
    ((ANode is TPCTemplateArg) and TPCTemplateArg(ANode).HasVerbatim) then
  begin
    DoLockRange(ANode);
    Exit;
  end;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      DoLockVerbatim(AChild);
    end);
end;

procedure TPCLspFormatter.DoLockRange(const ANode: TPCNode);
var
  LFirst: Integer;
  LLast: Integer;
  LI: Integer;
begin
  // The gaps after the node's first token up to its last token
  LFirst := DoFirstToken(ANode);
  LLast := DoLastToken(ANode);
  if (LFirst < 0) or (LLast < LFirst) then
    Exit;
  for LI := LFirst + 1 to LLast do
    FGaps[LI].Locked := True;
end;

{ TPCLspFormatter - spacing }

procedure TPCLspFormatter.DoMarkDropped();
var
  LRange: TSourceRange;
  LIndex: Integer;
begin
  // Tokens the conditional filter dropped (inactive branches, the
  // conditional directives): no node holds them, so nothing decides their
  // spacing; the gaps beside them are written as they stand
  SetLength(FDropped, Length(FTokens));
  for LRange in FModule.DroppedTokens do
  begin
    LIndex := DoTokenAt(Int64(LRange.StartByteOffset));
    if LIndex >= 0 then
      FDropped[LIndex] := True;
  end;
end;

procedure TPCLspFormatter.DoMarkRole(const AIndex: Integer; const ARole: TPCLspTokenRole);
begin
  if (AIndex >= 0) and (AIndex <= High(FTokens)) then
    FRoles[AIndex] := ARole;
end;

function TPCLspFormatter.DoOpBetween(const ALeft: TPCNode; const ARight: TPCNode): Integer;
var
  LFrom: Integer;
  LTo: Integer;
  LI: Integer;
begin
  // The operator token of a binary node: the one token between its operands
  // that is not a parenthesis (an operand's range may leave out the
  // parentheses around it); none or several: -1 (nothing is decided)
  Result := -1;
  LFrom := DoLastToken(ALeft);
  LTo := DoFirstToken(ARight);
  if (LFrom < 0) or (LTo < 0) then
    Exit;
  for LI := LFrom + 1 to LTo - 1 do
  begin
    if FTokens[LI].Kind in [tkLParen, tkRParen] then
      Continue;
    if Result >= 0 then
      Exit(-1);
    Result := LI;
  end;
end;

procedure TPCLspFormatter.DoMarkOperator(const AIndex: Integer; const AOpDepth: Integer);
begin
  // A binary / ternary operator: its spacing role and its R5 rank
  DoMarkRole(AIndex, trOperator);
  if (AIndex >= 0) and (AIndex <= High(FTokens)) then
    FOpDepth[AIndex] := AOpDepth;
end;

procedure TPCLspFormatter.DoMarkRoles(const ANode: TPCNode; const AOpDepth: Integer);
var
  LFirst: Integer;
  LNext: Integer;
  LChildDepth: Integer;
begin
  // The tokens whose spacing the tree decides, over the whole tree.
  // AOpDepth = how many binary / ternary nodes this one sits in without
  // another node kind between (R5: the outermost operator of a chain is
  // the lowest precedence one, the tree says so)
  if ANode = nil then
    Exit;
  if ANode is TPCBinary then
    DoMarkOperator(DoOpBetween(TPCBinary(ANode).Left, TPCBinary(ANode).Right), AOpDepth)
  else if ANode is TPCAssign then
    DoMarkRole(DoOpBetween(TPCAssign(ANode).Target, TPCAssign(ANode).ValueExpr), trOperator)
  else if ANode is TPCTernary then
  begin
    DoMarkOperator(DoOpBetween(TPCTernary(ANode).Condition, TPCTernary(ANode).ThenExpr),
      AOpDepth);
    DoMarkOperator(DoOpBetween(TPCTernary(ANode).ThenExpr, TPCTernary(ANode).ElseExpr),
      AOpDepth);
  end
  else if ANode is TPCUnary then
  begin
    // Prefix: the node starts at its operator; postfix (p^, i++): the node
    // ends past its operand
    LFirst := DoFirstToken(ANode);
    if (LFirst >= 0) and (LFirst <> DoFirstToken(TPCUnary(ANode).Operand)) and
      (FTokens[LFirst].Kind <> tkLParen) then
      DoMarkRole(LFirst, trPrefix)
    else if DoLastToken(ANode) > DoLastToken(TPCUnary(ANode).Operand) then
      DoMarkRole(DoLastToken(ANode), trPostfix);
  end
  else if ANode is TPCCall then
  begin
    // A construction's argument list has no callee (TPCVarDecl.InitCall):
    // its '(' is the call's own first token, right after the type
    if TPCCall(ANode).Callee = nil then
      LNext := DoFirstToken(ANode)
    else
      LNext := DoLastToken(TPCCall(ANode).Callee) + 1;
    if DoKindAt(LNext) = tkLParen then
      DoMarkRole(LNext, trCallOpen);
  end
  else if ANode is TPCIndex then
  begin
    LNext := DoLastToken(TPCIndex(ANode).Base) + 1;
    if DoKindAt(LNext) = tkLBracket then
      DoMarkRole(LNext, trCallOpen);
  end
  else if ANode is TPCRoutine then
  begin
    LNext := DoRangeToken(TPCRoutine(ANode).NameRange);
    if (LNext >= 0) and (DoKindAt(LNext + 1) = tkLParen) then
      DoMarkRole(LNext + 1, trCallOpen);
  end
  else if (ANode is TPCField) and (TPCField(ANode).BitWidthExpr <> nil) then
    DoMarkRole(DoOpBetween(TPCField(ANode).TypeExpr, TPCField(ANode).BitWidthExpr), trOperator);

  if (ANode is TPCBinary) or (ANode is TPCTernary) then
    LChildDepth := AOpDepth + 1
  else
    LChildDepth := 0;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      DoMarkRoles(AChild, LChildDepth);
    end);
end;

procedure TPCLspFormatter.DoSpacing();
var
  LI: Integer;
  LWant: TPCLspSpaceWant;
begin
  // R3 for every gap inside a line that no other rule owns: not a line
  // start, not locked, no comment, no line ending (a continuation line is
  // f6's), not before EOF
  SetLength(FRoles, Length(FTokens));
  SetLength(FOpDepth, Length(FTokens));
  for LI := 0 to High(FOpDepth) do
    FOpDepth[LI] := -1;
  DoMarkRoles(FModule, 0);
  for LI := 1 to High(FTokens) do
  begin
    if (FGaps[LI].Kind <> gkKeep) or FGaps[LI].Locked or (Length(FGaps[LI].Comments) > 0) or
      (CountEols(FGaps[LI].Original) > 0) or (FTokens[LI].Kind = tkEOF) then
      Continue;
    LWant := DoWant(LI - 1, LI);
    if (LWant = swNone) and (FGaps[LI].Original <> '') and not DoWouldFuse(LI - 1, LI) then
    begin
      FGaps[LI].Kind := gkSpace;
      FGaps[LI].Text := '';
    end
    else if (LWant = swOne) and (FGaps[LI].Original = '') then
    begin
      FGaps[LI].Kind := gkSpace;
      FGaps[LI].Text := ' ';
    end;
  end;
end;

function TPCLspFormatter.DoWant(const ALeft: Integer; const ARight: Integer): TPCLspSpaceWant;
var
  LLeft: TPCToken;
  LRight: TPCToken;
  LOption: Boolean;
begin
  LLeft := FTokens[ALeft];
  LRight := FTokens[ARight];

  // Text no node holds (inactive branches, conditional directives) and C++
  // text (# lines, cppstart text, directives' own words) stay as written
  if FDropped[ALeft] or FDropped[ARight] then
    Exit(swKeep);
  if (LLeft.Category in [tcPreprocessor, tcVerbatim, tcDirective]) or
    (LRight.Category in [tcPreprocessor, tcVerbatim, tcDirective]) then
    Exit(swKeep);

  // Closers and separators hug what is before them, openers what is after
  if LRight.Kind in [tkComma, tkSemicolon, tkRParen, tkRBracket] then
    Exit(swNone);
  if LLeft.Kind in [tkLParen, tkLBracket] then
    Exit(swNone);

  // Unary operators hug their operand (a word operator, not, keeps its gap)
  if FRoles[ALeft] = trPrefix then
  begin
    if LLeft.Category = tcKeyword then
      Exit(swKeep);
    Exit(swNone);
  end;
  if FRoles[ARight] in [trPostfix, trCallOpen] then
    Exit(swNone);

  // Member access and scope: no spaces (a '.' after a number would make a
  // real number: only after a name or a closer)
  if LRight.Kind in [tkDot, tkMinusGreater] then
  begin
    if LLeft.Kind in [tkIdentifier, tkRParen, tkRBracket, tkKwSelf, tkKwParent, tkKwThis] then
      Exit(swNone);
    Exit(swKeep);
  end;
  if LLeft.Kind in [tkDot, tkMinusGreater, tkColonColon] then
    Exit(swNone);
  if LRight.Kind = tkColonColon then
  begin
    if LLeft.Kind in [tkIdentifier, tkGreater] then
      Exit(swNone);
    Exit(swKeep);
  end;
  if (LLeft.Kind = tkDotDot) or (LRight.Kind = tkDotDot) then
    Exit(swNone);

  // Operators the tree names: one space each side (the options)
  if (FRoles[ALeft] = trOperator) or (FRoles[ARight] = trOperator) then
  begin
    // The assignment spellings are SpaceAroundAssign's, every other
    // operator SpaceAroundOperators'
    if (LLeft.Kind in PC_FMT_ASSIGN_KINDS) or (LRight.Kind in PC_FMT_ASSIGN_KINDS) then
      LOption := FOptions.SpaceAroundAssign
    else
      LOption := FOptions.SpaceAroundOperators;
    if LOption then
      Exit(swOne);
    Exit(swNone);
  end;

  // Colons, separators, a declaration's '='
  if LRight.Kind = tkColon then
  begin
    if FOptions.SpaceBeforeColon then
      Exit(swOne);
    Exit(swNone);
  end;
  if LLeft.Kind = tkColon then
  begin
    if FOptions.SpaceAfterColon then
      Exit(swOne);
    Exit(swNone);
  end;
  if LLeft.Kind = tkComma then
  begin
    if FOptions.SpaceAfterComma then
      Exit(swOne);
    Exit(swNone);
  end;
  if LLeft.Kind = tkSemicolon then
    Exit(swOne);
  if (LLeft.Kind = tkEqual) or (LRight.Kind = tkEqual) then
    Exit(swOne);

  // Nothing decides it
  Result := swKeep;
end;

function TPCLspFormatter.DoWouldFuse(const ALeft: Integer; const ARight: Integer): Boolean;
const
  // Characters that join into longer operators ('.' is not one here: the
  // number case is checked on its own)
  COperatorChars: TSysCharSet = ['+', '-', '*', '/', '%', '=', '<', '>', '!', '&', '|',
    '^', '~', ':', '?'];
var
  LLeft: string;
  LRight: string;
  LLast: Char;
  LFirst: Char;
begin
  // Removing the gap would lex differently (F3 C7): two words glued, a
  // number swallowing a '.', or two operator spellings forming another
  LLeft := FTokens[ALeft].Text;
  LRight := FTokens[ARight].Text;
  if (LLeft = '') or (LRight = '') then
    Exit(False);
  LLast := LLeft[Length(LLeft)];
  LFirst := LRight[1];
  if IsWordChar(LLast) and IsWordChar(LFirst) then
    Exit(True);
  if (FTokens[ALeft].Kind in [tkIntLiteral, tkFloatLiteral]) and (LFirst = '.') then
    Exit(True);
  Result := CharInSet(LLast, COperatorChars) and CharInSet(LFirst, COperatorChars);
end;

{ TPCLspFormatter - long lines }

procedure TPCLspFormatter.DoMarkTable(const AValue: TPCExpr; const ALevel: Integer);
var
  LFirst: Integer;
  LLast: Integer;
  LSpread: Boolean;
  LI: Integer;
begin
  // R5: a constant value the user wrote over several lines (a table) keeps
  // its lines, each at ALevel; one written on one line is an ordinary line
  if AValue = nil then
    Exit;
  LFirst := DoFirstToken(AValue);
  LLast := DoLastToken(AValue);
  if (LFirst < 0) or (LLast < LFirst) then
    Exit;
  LSpread := False;
  for LI := LFirst to LLast do
  begin
    if CountEols(FGaps[LI].Original) > 0 then
    begin
      LSpread := True;
      Break;
    end;
  end;
  if not LSpread then
    Exit;
  for LI := LFirst to LLast do
  begin
    FGaps[LI].Table := True;
    FGaps[LI].TableLevel := ALevel;
  end;
end;

function TPCLspFormatter.DoIsOwnedGap(const AIndex: Integer): Boolean;
var
  LLeft: TPCToken;
  LRight: TPCToken;
begin
  // A gap between two tokens whose line the formatter decides: inside the
  // file, before a real token, outside verbatim C++, no comment in it
  // (nothing is joined after a // comment, R4), not beside text no node
  // holds or C++ / directive text, not after a token that ends its own line
  Result := False;
  if (AIndex <= 0) or (AIndex > High(FTokens)) then
    Exit;
  LLeft := FTokens[AIndex - 1];
  LRight := FTokens[AIndex];
  if LRight.Kind = tkEOF then
    Exit;
  if FGaps[AIndex].Locked or (Length(FGaps[AIndex].Comments) > 0) then
    Exit;
  if FDropped[AIndex - 1] or FDropped[AIndex] then
    Exit;
  if (LLeft.Category in [tcPreprocessor, tcVerbatim, tcDirective]) or
    (LRight.Category in [tcPreprocessor, tcVerbatim, tcDirective]) then
    Exit;
  if DoPrevEndsLine(AIndex) then
    Exit;
  Result := True;
end;

function TPCLspFormatter.DoJoinText(const AIndex: Integer): string;
begin
  // A joined line ending becomes R3's want; a gap R3 leaves to the writer
  // becomes one space (the written gap was whitespace: a space lexes the
  // same)
  if (DoWant(AIndex - 1, AIndex) = swNone) and not DoWouldFuse(AIndex - 1, AIndex) then
    Result := ''
  else
    Result := ' ';
end;

procedure TPCLspFormatter.DoJoinLines();
var
  LI: Integer;
begin
  // R5 / Q2: every line ending inside a statement or declaration is joined
  // (DoFit breaks what is then too long); inside a constant table each
  // written line is kept, at the table's level
  for LI := 1 to High(FTokens) do
  begin
    if (FGaps[LI].Kind <> gkKeep) or (CountEols(FGaps[LI].Original) = 0) or
      not DoIsOwnedGap(LI) then
      Continue;
    if FGaps[LI].Table then
    begin
      FGaps[LI].Kind := gkHard;
      FGaps[LI].Level := FGaps[LI].TableLevel;
      FGaps[LI].IsContinue := True;
    end
    else
    begin
      FGaps[LI].Kind := gkSpace;
      FGaps[LI].Text := DoJoinText(LI);
    end;
  end;
end;

function TPCLspFormatter.DoIsLineStart(const AIndex: Integer): Boolean;
begin
  // A line starts at gap AIndex: a layout break, or a line ending no rule
  // joined (kept as written); EOF ends every line
  if (AIndex > High(FTokens)) or (FTokens[AIndex].Kind = tkEOF) then
    Exit(True);
  if FGaps[AIndex].Kind = gkHard then
    Exit(True);
  Result := (FGaps[AIndex].Kind = gkKeep) and (CountEols(FGaps[AIndex].Original) > 0);
end;

function TPCLspFormatter.DoLineBase(const AStart: Integer; const ABase: Integer): Integer;
begin
  // The statement level a line belongs to (FS DoLineBase): a layout break
  // sets it; a continuation, table or kept line keeps the one before
  Result := ABase;
  if AStart = 0 then
    Exit(0);
  if (FGaps[AStart].Kind = gkHard) and not FGaps[AStart].IsContinue then
    Result := FGaps[AStart].Level;
end;

function TPCLspFormatter.DoLineEnd(const AStart: Integer): Integer;
begin
  // The last token of the line from AStart (a token holding a line ending
  // ends it: a raw string)
  Result := AStart;
  while (Result < High(FTokens)) and not DoIsLineStart(Result + 1) and
    (CountEols(FTokens[Result].Text) = 0) do
    Inc(Result);
end;

function TPCLspFormatter.DoIndentWidth(const ALevel: Integer): Integer;
begin
  // A level's width in columns (a tab counts IndentSize)
  Result := Max(ALevel, 0) * FOptions.IndentSize;
end;

function TPCLspFormatter.DoStartColumn(const AStart: Integer): Integer;
begin
  // Where the line's first token starts: a break's indent; after a token
  // holding a line ending, that token's last line and the gap; a kept line,
  // the text after the gap's last line ending
  if AStart = 0 then
    Exit(0);
  if FGaps[AStart].Kind = gkHard then
    Exit(DoIndentWidth(FGaps[AStart].Level));
  if CountEols(FTokens[AStart - 1].Text) > 0 then
    Exit(Length(LastLinePart(FTokens[AStart - 1].Text)) + Length(FGaps[AStart].Text));
  Result := Length(LastLinePart(FGaps[AStart].Original));
end;

function TPCLspFormatter.DoCandidate(const AIndex: Integer; const AColumn: Integer;
  const ADepth: Integer; out ACandidate: TPCLspFitCandidate): Boolean;
var
  LLeft: Integer;
begin
  // R5 break points, after the token (FS DoCandidates): ',' / ';' first,
  // then a binary / ternary operator (not between two operator tokens),
  // ':=' and the compound assigns last; never inside a table or a gap the
  // formatter does not own (a break there would be kept as written by the
  // next run, never joined: not idempotent)
  ACandidate := Default(TPCLspFitCandidate);
  Result := False;
  if (not (FGaps[AIndex].Kind in [gkKeep, gkSpace])) or FGaps[AIndex].Table or
    not DoIsOwnedGap(AIndex) then
    Exit;
  LLeft := AIndex - 1;
  ACandidate.Gap := AIndex;
  ACandidate.Column := AColumn;
  ACandidate.Depth := ADepth;
  if FTokens[LLeft].Kind in [tkComma, tkSemicolon] then
  begin
    ACandidate.RankKind := 0;
    Result := True;
  end
  else if (FOpDepth[LLeft] >= 0) and (FOpDepth[AIndex] < 0) then
  begin
    ACandidate.RankKind := 1;
    ACandidate.RankPrec := FOpDepth[LLeft];
    Result := True;
  end
  else if (FRoles[LLeft] = trOperator) and (FTokens[LLeft].Kind in PC_FMT_ASSIGN_KINDS) then
  begin
    ACandidate.RankAssign := 1;
    Result := True;
  end;
end;

function TPCLspFormatter.DoFitLine(const AStart: Integer; const AEnd: Integer): Integer;
var
  LCol: Integer;
  LDepth: Integer;
  LI: Integer;
  LCandidate: TPCLspFitCandidate;
  LBest: TPCLspFitCandidate;
  LHaveBest: Boolean;
  LFits: Boolean;
begin
  // The gap to break the line AStart..AEnd at, or -1 when it fits or has no
  // break point (FS DoFitLine): the best ranked candidate, the rightmost of
  // those that still fit, else the leftmost (a token longer than the limit
  // stays whole)
  FCandidates.Clear();
  LCol := DoStartColumn(AStart);
  LDepth := 0;
  for LI := AStart to AEnd do
  begin
    if LI > AStart then
    begin
      if DoCandidate(LI, LCol, LDepth, LCandidate) then
        FCandidates.Add(LCandidate);
      if FGaps[LI].Kind = gkSpace then
        Inc(LCol, Length(FGaps[LI].Text))
      else
        Inc(LCol, Length(FGaps[LI].Original));
    end;
    Inc(LCol, FirstLineWidth(FTokens[LI].Text));
    if FTokens[LI].Kind in [tkLParen, tkLBracket] then
      Inc(LDepth)
    else if FTokens[LI].Kind in [tkRParen, tkRBracket] then
      Dec(LDepth);
  end;
  if (LCol <= FOptions.MaxLineLength) or (FCandidates.Count = 0) then
    Exit(-1);

  LBest := Default(TPCLspFitCandidate);
  LHaveBest := False;
  LFits := False;
  for LCandidate in FCandidates do
  begin
    if LCandidate.Column <= FOptions.MaxLineLength then
    begin
      // The rightmost of the best that fit: a later equal one wins
      if (not LFits) or IsBetterCandidate(LCandidate, LBest) or
        not IsBetterCandidate(LBest, LCandidate) then
      begin
        LBest := LCandidate;
        LFits := True;
        LHaveBest := True;
      end;
    end
    else if (not LFits) and ((not LHaveBest) or IsBetterCandidate(LCandidate, LBest)) then
    begin
      // None fits yet: the leftmost of the best
      LBest := LCandidate;
      LHaveBest := True;
    end;
  end;
  Result := LBest.Gap;
end;

procedure TPCLspFormatter.DoFit();
var
  LStart: Integer;
  LEnd: Integer;
  LBase: Integer;
  LBreak: Integer;
begin
  // R5 (FS DoFit): a line over MaxLineLength breaks at its best candidate,
  // again until it fits or has none left; every continuation line sits one
  // level in from its statement's base
  LStart := 0;
  LBase := 0;
  while LStart <= High(FTokens) do
  begin
    LBase := DoLineBase(LStart, LBase);
    LEnd := DoLineEnd(LStart);
    LBreak := DoFitLine(LStart, LEnd);
    if LBreak > 0 then
    begin
      FGaps[LBreak].Kind := gkHard;
      FGaps[LBreak].Level := LBase + 1;
      FGaps[LBreak].IsContinue := True;
      FGaps[LBreak].Broken := True;
      LEnd := LBreak - 1;
    end;
    LStart := LEnd + 1;
  end;
end;

{ TPCLspFormatter - output }

function TPCLspFormatter.DoIndentText(const ALevel: Integer): string;
begin
  // F3 C12: a tab per level, else IndentSize spaces per level
  if FOptions.UseTabs then
    Result := StringOfChar(#9, Max(ALevel, 0))
  else
    Result := StringOfChar(' ', Max(ALevel, 0) * FOptions.IndentSize);
end;

function TPCLspFormatter.DoPrevEndsLine(const AIndex: Integer): Boolean;
var
  LPrev: string;
begin
  // The token before gap AIndex already ends its line (its text holds a
  // line ending at its end: a raw string, a spliced token)
  if AIndex <= 0 then
    Exit(False);
  LPrev := FTokens[AIndex - 1].Text;
  Result := LPrev.EndsWith(#10) or LPrev.EndsWith(#13);
end;

function TPCLspFormatter.DoEolRun(const ARun: string; const AMin: Integer): string;
var
  LParts: TArray<string>;
  LCount: Integer;
  LI: Integer;
begin
  // R6: the run's line endings, at least AMin, at most MaxBlankLines blank
  // lines; each in the file's own line ending (F3 C11); trailing whitespace
  // only when TrimTrailingWhitespace is off (F3 S4)
  LParts := SplitLines(ARun);
  LCount := Min(Max(CountEols(ARun), AMin), FOptions.MaxBlankLines + 1);
  Result := '';
  for LI := 0 to LCount - 1 do
  begin
    if (not FOptions.TrimTrailingWhitespace) and (LI < High(LParts)) then
      Result := Result + LParts[LI];
    Result := Result + FEol;
  end;
end;

function TPCLspFormatter.DoBreakText(const AIndex: Integer): string;
var
  LMin: Integer;
begin
  // The line endings as written (at least one, unless the token before
  // already ends its line), then the indent
  LMin := 1;
  if DoPrevEndsLine(AIndex) then
    LMin := 0;
  Result := DoEolRun(FGaps[AIndex].Original, LMin) + DoIndentText(FGaps[AIndex].Level);
end;

function TPCLspFormatter.DoCommentLevel(const AIndex: Integer): Integer;
begin
  // F3 C9 / R4: an own-line comment takes the level of the code line after
  // it; before end / else / until / except / finally the body's level (one
  // in), except the end of a module with no body (nothing is inside it)
  Result := FGaps[AIndex].Level;
  if (AIndex > High(FTokens)) or (FTokens[AIndex].Kind = tkEOF) then
    Exit(0);
  if not (FTokens[AIndex].Kind in [tkKwEnd, tkKwElse, tkKwUntil, tkKwExcept, tkKwFinally]) then
    Exit;
  if (AIndex = DoRangeToken(FModule.EndRange)) and not FModule.HasBody then
    Exit;
  Inc(Result);
end;

function TPCLspFormatter.DoCommentGapText(const AIndex: Integer; const AIsEnd: Boolean): string;
var
  LGap: TPCLspGap;
  LSource: TPCSourceText;
  LCommentLevel: Integer;
  LPos: Int64;
  LRun: string;
  LI: Integer;
begin
  // R4: only the whitespace runs between the comments change, never a
  // comment's text (a block comment's inner lines included). A run on one
  // line (a trailing comment, two comments on a line) stays as written; a
  // run holding a line ending starts the comment on its own line at the
  // comment level. The file starts with its first comment (R6: no leading
  // blank lines); the run after the last comment starts the token's line,
  // or at the file's end is its one final line ending
  LGap := FGaps[AIndex];
  LSource := FStream.SourceText();
  LCommentLevel := DoCommentLevel(AIndex);
  LPos := LGap.StartOffset;
  Result := '';
  for LI := 0 to High(LGap.Comments) do
  begin
    LRun := LSource.Slice(LPos, LGap.Comments[LI].StartOffset);
    // Before the file's first comment nothing is written: the file starts
    // with it
    if not ((LI = 0) and (AIndex = 0)) then
    begin
      if CountEols(LRun) = 0 then
        Result := Result + LRun
      else
        Result := Result + DoEolRun(LRun, 1) + DoIndentText(LCommentLevel);
    end;
    Result := Result + LSource.Slice(LGap.Comments[LI].StartOffset, LGap.Comments[LI].EndOffset);
    LPos := LGap.Comments[LI].EndOffset;
  end;

  LRun := LSource.Slice(LPos, LGap.EndOffset);
  if AIsEnd then
  begin
    if FOptions.FinalNewline then
      Result := Result + FEol
    else
      Result := Result + LRun;
  end
  else
    Result := Result + DoEolRun(LRun, 1) + DoIndentText(LGap.Level);
end;

function TPCLspFormatter.DoEndText(const AIndex: Integer): string;
begin
  // R6: the file ends with exactly one line ending (FinalNewline; none more
  // when the last token already ends its line); off: as written
  if not FOptions.FinalNewline then
    Exit(FGaps[AIndex].Original);
  if DoPrevEndsLine(AIndex) then
    Exit('');
  Result := FEol;
end;

procedure TPCLspFormatter.DoGapTexts();
var
  LI: Integer;
  LIsEnd: Boolean;
  LHasComment: Boolean;
begin
  // Each gap's text: the file's start and end (R6), a line start (with its
  // comments, R4), a spaced gap (DoSpacing's text); everything else, locked
  // gaps included, as it stands
  for LI := 0 to High(FGaps) do
  begin
    if FGaps[LI].Kind = gkSpace then
      Continue;
    if FGaps[LI].Locked or (LI > High(FTokens)) then
    begin
      FGaps[LI].Text := FGaps[LI].Original;
      Continue;
    end;
    LIsEnd := FTokens[LI].Kind = tkEOF;
    LHasComment := Length(FGaps[LI].Comments) > 0;
    if LHasComment and ((LI = 0) or LIsEnd or (FGaps[LI].Kind = gkHard)) then
      FGaps[LI].Text := DoCommentGapText(LI, LIsEnd)
    else if LIsEnd then
      FGaps[LI].Text := DoEndText(LI)
    else if LI = 0 then
      FGaps[LI].Text := ''
    else if FGaps[LI].Broken then
      // R5: a break DoFit made is one line ending and the indent (never a
      // blank line: the next run joins and breaks it the same)
      FGaps[LI].Text := FEol + DoIndentText(FGaps[LI].Level)
    else if FGaps[LI].Kind = gkHard then
      FGaps[LI].Text := DoBreakText(LI)
    else
      FGaps[LI].Text := FGaps[LI].Original;
  end;
end;

function TPCLspFormatter.DoRender(out AEdits: TPCLspFormatEdits): string;
var
  LBuilder: TStringBuilder;
  LEdits: TList<TPCLspFormatEdit>;
  LEdit: TPCLspFormatEdit;
  LI: Integer;
begin
  // Gaps and token texts in order; one edit per gap whose text changed, on
  // the original buffer's offsets
  LBuilder := TStringBuilder.Create();
  LEdits := TList<TPCLspFormatEdit>.Create();
  try
    for LI := 0 to High(FGaps) do
    begin
      LBuilder.Append(FGaps[LI].Text);
      if FGaps[LI].Text <> FGaps[LI].Original then
      begin
        LEdit.StartOffset := FGaps[LI].StartOffset;
        LEdit.EndOffset := FGaps[LI].EndOffset;
        LEdit.NewText := FGaps[LI].Text;
        LEdits.Add(LEdit);
      end;
      if LI <= High(FTokens) then
        LBuilder.Append(FTokens[LI].Text);
    end;
    Result := LBuilder.ToString();
    AEdits := LEdits.ToArray();
  finally
    LEdits.Free();
    LBuilder.Free();
  end;
end;

function TPCLspFormatter.DoCommentText(const AStream: TPCTokenStream;
  const ASpan: TPCCommentSpan): string;
begin
  Result := AStream.SourceText().Slice(ASpan.StartOffset, ASpan.EndOffset);
end;

function TPCLspFormatter.DoVerify(const AText: string): Boolean;
var
  LBytes: TBytes;
  LCheck: TPCTokenStream;
  LLexer: TPCLexer;
  LOld: TArray<TPCCommentSpan>;
  LNew: TArray<TPCCommentSpan>;
  LI: Integer;
begin
  // F3 C5: the result lexes back to the same token kinds and texts and the
  // same comment texts, with no report
  LBytes := TEncoding.UTF8.GetBytes(AText);
  FCheckErrors.Clear();
  LCheck := TPCTokenStream.Create();
  LLexer := TPCLexer.Create();
  try
    LCheck.SetErrors(FCheckErrors);
    LLexer.SetErrors(FCheckErrors);
    if (not LLexer.TokenizeBytes(LBytes, FFilename, LCheck)) or FCheckErrors.HasErrors() then
      Exit(False);
    if LCheck.Count() <> Length(FTokens) then
      Exit(False);
    for LI := 0 to High(FTokens) do
    begin
      if (LCheck.TokenAt(LI).Kind <> FTokens[LI].Kind) or
        (LCheck.TokenAt(LI).Text <> FTokens[LI].Text) then
        Exit(False);
    end;
    LOld := FStream.CommentsIn(0, High(Int64));
    LNew := LCheck.CommentsIn(0, High(Int64));
    if Length(LOld) <> Length(LNew) then
      Exit(False);
    for LI := 0 to High(LOld) do
    begin
      if DoCommentText(FStream, LOld[LI]) <> DoCommentText(LCheck, LNew[LI]) then
        Exit(False);
    end;
    Result := True;
  finally
    LLexer.Free();
    LCheck.Free();
  end;
end;

end.
