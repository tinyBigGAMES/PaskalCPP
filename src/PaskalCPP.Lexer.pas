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
  PaskalCPP.Lexer - Source bytes to tokens

  TPCLexer turns the UTF-8 bytes of a .pcpp file into TPCToken records with
  exact byte offsets, byte columns (as clang counts) and leading trivia, and
  appends them to a TPCTokenStream. It knows PaskalCPP and C++ spellings from
  TPCVocabulary. Literals are recognized by SHAPE only; clang validates and
  evaluates them. A cppstart block is captured as one tkRawBlock token.
  Every line that starts inside a token or comment is marked on the stream
  (TPCTokenStream.MarkInside, R23); inside a cppstart block the C++ elements
  it holds are marked, never the block token itself, and recorded on the
  stream as C++ elements (TPCTokenStream.AddCppElement, O-S6b): words,
  literals, operators and any other byte sequence, # lines excluded; the
  parser walks a body block's elements for its escaping jumps.
  The source is read through the stream's TPCSourceText: scanners walk
  LOGICAL bytes (line splices skipped), Text and Range stay physical, and
  every token carries its splice-free Spelling.

  Dependencies: StdApp.Base, StdApp.Utils (TUtils.ResolvePath),
    StdApp.Resources (RSLex*), PaskalCPP.Common, PaskalCPP.SourceText,
    PaskalCPP.TokenStream
  Notes: research\cppmix\lexer.md is the specification (its "Line splices"
    section: logical-byte cursor, token extent rule, report on commit).
===============================================================================}

unit PaskalCPP.Lexer;

interface

uses
  System.SysUtils,
  StdApp.Base,
  PaskalCPP.Common,
  PaskalCPP.SourceText,
  PaskalCPP.TokenStream;

const
  { PC_ERR_LEX_001 }
  PC_ERR_LEX_001 = 'LX0001';   // unterminated string or char literal
  { PC_ERR_LEX_002 }
  PC_ERR_LEX_002 = 'LX0002';   // unterminated raw string
  { PC_ERR_LEX_003 }
  PC_ERR_LEX_003 = 'LX0003';   // unterminated block comment
  { PC_ERR_LEX_004 }
  PC_ERR_LEX_004 = 'LX0004';   // invalid character / no token matches
  { PC_ERR_LEX_005 }
  PC_ERR_LEX_005 = 'LX0005';   // malformed number
  { PC_ERR_LEX_006 }
  PC_ERR_LEX_006 = 'LX0006';   // numeric literal overflow
  { PC_ERR_LEX_007 }
  PC_ERR_LEX_007 = 'LX0007';   // invalid octal digit
  { PC_ERR_LEX_008 }
  PC_ERR_LEX_008 = 'LX0008';   // # or %: not at line start
  { PC_ERR_LEX_009 }
  PC_ERR_LEX_009 = 'LX0009';   // @ without a directive name
  { PC_ERR_LEX_010 }
  PC_ERR_LEX_010 = 'LX0010';   // raw string delimiter invalid or longer than 16 bytes
  { PC_ERR_LEX_011 }
  PC_ERR_LEX_011 = 'LX0011';   // invalid UTF-8
  { PC_ERR_LEX_012 }
  PC_ERR_LEX_012 = 'LX0012';   // file not found / read error
  { PC_ERR_LEX_013 }
  PC_ERR_LEX_013 = 'LX0013';   // cppstart without cppend
  { PC_ERR_LEX_014 }
  PC_ERR_LEX_014 = 'LX0014';   // cppstart block ends in a line splice
  { PC_HINT_LEX_001 }
  PC_HINT_LEX_001 = 'LX0101';  // leading-zero octal literal
  { PC_WARN_LEX_001 }
  PC_WARN_LEX_001 = 'LX0201';  // backslash and newline separated by space
  { PC_WARN_LEX_002 }
  PC_WARN_LEX_002 = 'LX0202';  // escaped newline between */ characters
  { PC_WARN_LEX_003 }
  PC_WARN_LEX_003 = 'LX0203';  // '/*' within block comment

  { PC_MAX_RAW_DELIMITER }
  PC_MAX_RAW_DELIMITER = 16;

  { PC_FLOAT_SUFFIXES }
  // The standard floating suffixes the bundled clang takes (BNF.md sec 9).
  // Witness: Lexer.float_suffix_witness compiles every row of this table and
  // of PC_FLOAT_SUFFIXES_REFUSED with the bundled clang on every supported
  // target, so a toolchain that changes its answer fails there
  PC_FLOAT_SUFFIXES: array[0..5] of string = (
    'f', 'F', 'l', 'L',
    'f16', 'F16'
  );

  { PC_FLOAT_SUFFIXES_REFUSED }
  // Standard C++23 floating suffixes the bundled clang refuses ("invalid
  // suffix on floating constant"). Taken as a user-defined literal, they
  // would reach clang in C++ words; the lexer reports them as LX0005 at the
  // literal instead (DESIGN.md sec 5)
  PC_FLOAT_SUFFIXES_REFUSED: array[0..7] of string = (
    'f32', 'f64', 'f128',
    'F32', 'F64', 'F128',
    'bf16', 'BF16'
  );

type

  { TPCLexer }
  TPCLexer = class(TBaseObject)
  private
    FVocabulary: TPCVocabulary;
    FStream: TPCTokenStream;
    FSource: TPCSourceText;       // the stream's source text (not owned): bytes, lines, splices
    FLength: Int64;               // FSource.ByteCount(), fixed for one run
    FPos: Int64;                  // physical offset; after trivia always a logical byte
    FTriviaStart: Int64;          // where the next token's leading trivia begins
    FAtLineStart: Boolean;        // only trivia since the last newline; a splice changes nothing
    FStopped: Boolean;            // error budget reached or the input is unusable
    FCaptureNext: Boolean;        // the last token was cppstart
    FCppstartToken: TPCToken;     // that cppstart, for the EOF-inside-block error

    // Byte helpers
    function DoIsIdentStart(const AByte: Integer): Boolean;
    function DoIsIdentChar(const AByte: Integer): Boolean;
    function DoIsDigit(const AByte: Integer): Boolean;
    procedure DoWarnSplices(const AStart: Int64; const AEnd: Int64);
    function DoStepLogical(const AOffset: Int64): Int64;
    function DoScanIdentEnd(const AStart: Int64): Int64;
    function DoSuffixEnd(const AFrom: Int64): Int64;

    // Positions, tokens, errors
    procedure DoReset(const AStream: TPCTokenStream);
    procedure DoSetSpelling(var AToken: TPCToken; const ASpelling: string);
    function DoMakeToken(const AKind: TPCTokenKind; const ACategory: TPCTokenCategory;
      const AStart: Int64; const AEnd: Int64): TPCToken;
    procedure DoEmit(const AToken: TPCToken);
    procedure DoEmitEof();
    procedure DoError(const AStart: Int64; const AEnd: Int64;
      const ASeverity: TErrorSeverity; const ACode: string;
      const AMessage: string; const AArgs: array of const);

    // Input check and trivia
    function DoValidateUtf8(): Boolean;
    function DoSkipLineComment(const AStart: Int64): Int64;
    // A `///` comment first on its line (AStart .. AEnd: DoSkipLineComment's
    // span) is a doc line (plans\done\PLAN-EDITOR.md E2.6): its text goes to the
    // token stream; `////`, a spliced one, or one after a token is not
    procedure DoNoteDocLine(const AStart: Int64; const AEnd: Int64);
    function DoSkipBlockComment(const AStart: Int64; out AEnd: Int64): Boolean;
    procedure DoSkipTrivia();

    // Literal bodies, shared by tokens, # lines and cppstart capture
    function DoLiteralPrefix(const AText: string; out APrefix: TPCLiteralPrefix;
      out AIsRaw: Boolean): Boolean;
    function DoSkipQuotedBody(const AQuoteAt: Int64; out AEnd: Int64): Boolean;
    function DoSkipRawBody(const AQuoteAt: Int64; out AEnd: Int64;
      out ADelimiterOk: Boolean): Boolean;
    function DoScanPpNumberEnd(const AStart: Int64): Int64;

    // Number classification
    function DoIsRadixDigit(const AChar: Char; const ARadix: Integer): Boolean;
    function DoCountDigits(const AText: string; var AIndex: Integer;
      const ARadix: Integer): Integer;
    function DoParseUInt(const ADigits: string; const ARadix: Integer;
      out AValue: UInt64): Boolean;
    function DoFloatFormat(const ASuffix: string; out AFormat: TPCFloatFormat): Boolean;
    function DoIsIntSuffix(const ASuffix: string; out ARow: TPCIntSuffixRow): Boolean;
    function DoIsFloatSuffix(const ASuffix: string): Boolean;
    function DoIsRefusedFloatSuffix(const ASuffix: string): Boolean;
    function DoIsSuffixShape(const ASuffix: string): Boolean;
    function DoFailNumber(var AToken: TPCToken; const ACode: string;
      const AMessage: string): Boolean; overload;
    function DoFailNumber(var AToken: TPCToken; const ACode: string;
      const AMessage: string; const AArgs: array of const): Boolean; overload;
    function DoClassifyNumber(var AToken: TPCToken): Boolean;

    // Token scanners
    procedure DoScanToken();
    function DoMatchHash(const AStart: Int64; out AEnd: Int64): Boolean;
    procedure DoScanHash(const AHashEnd: Int64);
    procedure DoScanPreprocessor(const AHashEnd: Int64);
    procedure DoScanDirective();
    procedure DoScanWord();
    procedure DoScanNumber();
    procedure DoScanQuoted(const AStart: Int64; const APrefix: TPCLiteralPrefix;
      const AQuoteAt: Int64);
    procedure DoScanRaw(const AStart: Int64; const APrefix: TPCLiteralPrefix;
      const AQuoteAt: Int64);
    function DoIsLessColonColon(const AStart: Int64): Boolean;
    function DoMatchOperator(const AStart: Int64; out AEnd: Int64;
      out AEntry: TPCVocabEntry): Boolean;
    procedure DoScanOperator();
    procedure DoTrackSplices(const AStart: Int64; const AEnd: Int64;
      const ASplices: Boolean; var ALastSpliceAt: Int64; var ANewlineAfter: Boolean);
    procedure DoAddCppElement(const AKind: TPCCppElementKind;
      const ATokenKind: TPCTokenKind; const AStart: Int64; const AEnd: Int64);
    procedure DoCapture();
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetErrors(const AErrors: TErrors); override;

    // True = the stream holds the file's tokens, lexer errors included (a
    // reported span is one tkUnknown). False = no text: unreadable (LX0012),
    // invalid UTF-8 (LX0011) or a broken vocabulary; the stream is EOF only
    function TokenizeFile(const AFilename: string; const AStream: TPCTokenStream): Boolean;
    function TokenizeBytes(const ABytes: TBytes; const AFilename: string;
      const AStream: TPCTokenStream): Boolean;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  StdApp.Utils,
  StdApp.Resources;

{ TPCLexer }

constructor TPCLexer.Create();
begin
  inherited;

  FVocabulary := TPCVocabulary.Create();
  FStream := nil;
  FSource := nil;
  FCppstartToken.Clear();
end;

destructor TPCLexer.Destroy();
begin
  FVocabulary.Free();

  inherited;
end;

procedure TPCLexer.SetErrors(const AErrors: TErrors);
begin
  inherited;

  FVocabulary.SetErrors(AErrors);
end;

function TPCLexer.DoIsIdentStart(const AByte: Integer): Boolean;
begin
  Result := ((AByte >= Ord('A')) and (AByte <= Ord('Z'))) or
    ((AByte >= Ord('a')) and (AByte <= Ord('z'))) or
    (AByte = Ord('_'));
end;

function TPCLexer.DoIsIdentChar(const AByte: Integer): Boolean;
begin
  Result := DoIsIdentStart(AByte) or DoIsDigit(AByte);
end;

function TPCLexer.DoIsDigit(const AByte: Integer): Boolean;
begin
  Result := (AByte >= Ord('0')) and (AByte <= Ord('9'));
end;

procedure TPCLexer.DoWarnSplices(const AStart: Int64; const AEnd: Int64);
var
  LP: Int64;
  LNewlineAt: Int64;
begin
  // Reports LX0201 for every whitespace splice that starts in [AStart, AEnd),
  // at its first whitespace byte (clang's position in tokens, strings and #
  // lines). Report on commit: called only for bytes that become part of a
  // committed token or trivia, never on look-ahead, and never for comment
  // bodies or raw string bodies (clang does not warn there), so each splice
  // is reported exactly once.
  LP := AStart;
  while LP < AEnd do
  begin
    LNewlineAt := FSource.SpliceNewlineOffset(LP);
    if LNewlineAt < 0 then
      Inc(LP)
    else
    begin
      if LNewlineAt > LP + 1 then
        DoError(LP + 1, LNewlineAt, esWarning, PC_WARN_LEX_001, RSLexSpliceWhitespace, []);
      LP := LNewlineAt + FSource.NewlineLength(LNewlineAt);
    end;
  end;
end;

function TPCLexer.DoStepLogical(const AOffset: Int64): Int64;
begin
  // The committed step from the logical byte at AOffset to the next one:
  // the splices crossed are reported
  Result := FSource.NextLogical(AOffset);
  DoWarnSplices(AOffset + 1, Result);
end;

function TPCLexer.DoScanIdentEnd(const AStart: Int64): Int64;
var
  LP: Int64;
  LNext: Int64;
begin
  // AStart is an identifier byte (the caller checked it). Walks LOGICAL
  // bytes, so a splice inside joins the identifier (ab \ newline cd is
  // abcd). Result = the physical offset right after the last identifier
  // byte: a splice after it is trivia (token extent rule).
  LP := AStart;
  LNext := FSource.Logical(LP + 1);
  while DoIsIdentChar(FSource.ByteAt(LNext)) do
  begin
    DoWarnSplices(LP + 1, LNext);
    LP := LNext;
    LNext := FSource.Logical(LP + 1);
  end;
  Result := LP + 1;
end;

function TPCLexer.DoSuffixEnd(const AFrom: Int64): Int64;
var
  LAt: Int64;
begin
  // An identifier touching a literal's closing quote is its UD suffix; a
  // splice between them joins it, as in C++ translation phase 2
  LAt := FSource.Logical(AFrom);
  if DoIsIdentStart(FSource.ByteAt(LAt)) then
  begin
    DoWarnSplices(AFrom, LAt);
    Result := DoScanIdentEnd(LAt);
  end
  else
    Result := AFrom;
end;

procedure TPCLexer.DoReset(const AStream: TPCTokenStream);
begin
  // The stream is already Init-ed: its source text holds the bytes and the
  // line table for this run
  FStream := AStream;
  FSource := AStream.SourceText();
  FLength := FSource.ByteCount();
  FPos := 0;
  FTriviaStart := 0;
  FAtLineStart := True;
  FStopped := False;
  FCaptureNext := False;
  FCppstartToken.Clear();
end;

procedure TPCLexer.DoSetSpelling(var AToken: TPCToken; const ASpelling: string);
begin
  // Spelling is always set; with no splice in the token it is the very
  // string Text holds (shared, no second copy)
  if ASpelling = AToken.Text then
    AToken.Spelling := AToken.Text
  else
    AToken.Spelling := ASpelling;
end;

function TPCLexer.DoMakeToken(const AKind: TPCTokenKind; const ACategory: TPCTokenCategory;
  const AStart: Int64; const AEnd: Int64): TPCToken;
begin
  Result.Clear();
  Result.Kind := AKind;
  Result.Category := ACategory;
  Result.Origin := toNone;
  Result.TriviaStart := UInt64(FTriviaStart);
  Result.Text := FSource.Slice(AStart, AEnd);
  DoSetSpelling(Result, FSource.Spelling(AStart, AEnd, -1));
  FSource.FillRange(Result.Range, AStart, AEnd);
end;

procedure TPCLexer.DoEmit(const AToken: TPCToken);
begin
  FStream.Append(AToken);
  FTriviaStart := Int64(AToken.Range.EndByteOffset);
  FAtLineStart := False;

  // A token over several lines (raw string, splices, a # line continued by a
  // comment) starts lines inside it (R23). A cppstart block is C++ text, not
  // one element: DoCapture marks the elements inside it instead
  if (AToken.Kind <> tkRawBlock) and (AToken.Range.EndLine > AToken.Range.StartLine) then
    FStream.MarkInside(Int64(AToken.Range.StartByteOffset), Int64(AToken.Range.EndByteOffset));

  // A cppstart arms block capture for the very next token only
  FCaptureNext := AToken.Kind = tkKwCppstart;
  if FCaptureNext then
    FCppstartToken := AToken;
end;

procedure TPCLexer.DoEmitEof();
var
  LToken: TPCToken;
begin
  // EOF is empty at the end of the file; its trivia is everything after the
  // last token (all unlexed bytes too, if lexing stopped early)
  LToken := DoMakeToken(tkEOF, tcSpecial, FLength, FLength);
  FStream.Append(LToken);
end;

procedure TPCLexer.DoError(const AStart: Int64; const AEnd: Int64;
  const ASeverity: TErrorSeverity; const ACode: string;
  const AMessage: string; const AArgs: array of const);
var
  LRange: TSourceRange;
begin
  LRange.Clear();
  FSource.FillRange(LRange, AStart, AEnd);
  FErrors.Add(LRange, ASeverity, ACode, AMessage, AArgs);

  if FErrors.ReachedMaxErrors() then
    FStopped := True;
end;

function TPCLexer.DoValidateUtf8(): Boolean;
var
  LP: Int64;
  LByte: Integer;
  LNeed: Integer;
  LLow: Integer;
  LHigh: Integer;
  LI: Integer;
  LNext: Integer;
begin
  // The whole file must be well-formed UTF-8 (RFC 3629: no overlong forms,
  // no surrogates, nothing above U+10FFFF). clang expects UTF-8 input.
  Result := True;
  LP := 0;
  while LP < FLength do
  begin
    LByte := FSource.ByteAt(LP);
    LLow := $80;
    LHigh := $BF;
    if LByte < $80 then
      LNeed := 0
    else if (LByte >= $C2) and (LByte <= $DF) then
      LNeed := 1
    else if LByte = $E0 then
    begin
      LNeed := 2;
      LLow := $A0;
    end
    else if (LByte >= $E1) and (LByte <= $EC) then
      LNeed := 2
    else if LByte = $ED then
    begin
      LNeed := 2;
      LHigh := $9F;
    end
    else if (LByte >= $EE) and (LByte <= $EF) then
      LNeed := 2
    else if LByte = $F0 then
    begin
      LNeed := 3;
      LLow := $90;
    end
    else if (LByte >= $F1) and (LByte <= $F3) then
      LNeed := 3
    else if LByte = $F4 then
    begin
      LNeed := 3;
      LHigh := $8F;
    end
    else
      LNeed := -1;

    // The first continuation byte has the lead's own range; the rest 80..BF
    for LI := 1 to LNeed do
    begin
      LNext := FSource.ByteAt(LP + LI);
      if (LI > 1) then
      begin
        LLow := $80;
        LHigh := $BF;
      end;
      if (LNext < LLow) or (LNext > LHigh) then
      begin
        LNeed := -1;
        Break;
      end;
    end;

    if LNeed < 0 then
    begin
      DoError(LP, LP + 1, esError, PC_ERR_LEX_011, RSLexInvalidUtf8, []);
      FStopped := True;
      Exit(False);
    end;
    Inc(LP, LNeed + 1);
  end;
end;

function TPCLexer.DoSkipLineComment(const AStart: Int64): Int64;
var
  LSecond: Int64;
  LNewlineAt: Int64;
begin
  // From the '//' at AStart (a splice may sit between its two '/') to the
  // newline that ends the logical line (not included). A splice continues
  // the comment (C++ translation phase 2); a whitespace one warns at its
  // '\', which is where clang reports it inside a // comment.
  LSecond := FSource.Logical(AStart + 1);
  DoWarnSplices(AStart + 1, LSecond);
  Result := LSecond + 1;
  while (Result < FLength) and (FSource.NewlineLength(Result) = 0) do
  begin
    LNewlineAt := FSource.SpliceNewlineOffset(Result);
    if LNewlineAt < 0 then
      Inc(Result)
    else
    begin
      if LNewlineAt > Result + 1 then
        DoError(Result, Result + 1, esWarning, PC_WARN_LEX_001, RSLexSpliceWhitespace, []);
      Result := LNewlineAt + FSource.NewlineLength(LNewlineAt);
    end;
  end;
end;

procedure TPCLexer.DoNoteDocLine(const AStart: Int64; const AEnd: Int64);
var
  LText: string;
begin
  // Exactly three plain '/' (a fourth makes an ordinary comment, as Rust's
  // //// does), all on one physical line: a splice would join the next line
  if (FSource.ByteAt(AStart + 1) <> Ord('/')) or (FSource.ByteAt(AStart + 2) <> Ord('/')) or
     (FSource.ByteAt(AStart + 3) = Ord('/')) then
    Exit;
  if (AEnd > AStart + 3) and (FSource.LineOf(AEnd - 1) <> FSource.LineOf(AStart)) then
    Exit;

  // The text after '///', one separating blank dropped, trailing blanks too
  LText := FSource.Slice(AStart + 3, AEnd);
  if LText.StartsWith(' ') then
    LText := LText.Substring(1);
  FStream.AddDocLine(FSource.LineOf(AStart), LText.TrimRight());
end;

function TPCLexer.DoSkipBlockComment(const AStart: Int64; out AEnd: Int64): Boolean;
var
  LStar: Int64;
  LP: Int64;
  LAfter: Int64;
  LByte: Integer;
begin
  // From the '/*' at AStart (a splice may sit between its two bytes) to
  // just after the first '*/'; block comments do not nest. The body is
  // read physically: its splices never warn (as clang), except where one
  // joins '*' and '/' into the closer (LX0202 at the '\', plus LX0201 for
  // a whitespace splice there) or '/' and '*' into an inner opener (LX0203
  // at the '/'). Unterminated: AEnd = end of input.
  LStar := FSource.Logical(AStart + 1);
  DoWarnSplices(AStart + 1, LStar);
  LP := LStar + 1;
  while LP < FLength do
  begin
    LByte := FSource.ByteAt(LP);
    if LByte = Ord('*') then
    begin
      LAfter := FSource.Logical(LP + 1);
      if FSource.ByteAt(LAfter) = Ord('/') then
      begin
        if LAfter > LP + 1 then
        begin
          DoError(LP + 1, LP + 2, esWarning, PC_WARN_LEX_002, RSLexEscapedCommentEnd, []);
          DoWarnSplices(LP + 1, LAfter);
        end;
        AEnd := LAfter + 1;
        Exit(True);
      end;
    end
    else if (LByte = Ord('/')) and (FSource.ByteAt(FSource.Logical(LP + 1)) = Ord('*')) then
      DoError(LP, LP + 1, esWarning, PC_WARN_LEX_003, RSLexNestedCommentOpen, []);
    Inc(LP);
  end;
  AEnd := FLength;
  Result := False;
end;

procedure TPCLexer.DoSkipTrivia();
var
  LByte: Integer;
  LNewline: Int64;
  LSplice: Int64;
  LSecond: Int64;
  LEnd: Int64;
begin
  while FPos < FLength do
  begin
    // Every newline form (LF, CR LF, lone CR) starts a line
    LNewline := FSource.NewlineLength(FPos);
    if LNewline > 0 then
    begin
      FAtLineStart := True;
      FPos := FPos + LNewline;
      Continue;
    end;

    // A splice is neither a newline nor a token: FAtLineStart is unchanged
    LSplice := FSource.SpliceLength(FPos);
    if LSplice > 0 then
    begin
      DoWarnSplices(FPos, FPos + 1);
      FPos := FPos + LSplice;
      Continue;
    end;

    LByte := FSource.ByteAt(FPos);
    if (LByte = 9) or (LByte = 11) or (LByte = 12) or (LByte = 32) then
      Inc(FPos)
    else if LByte = Ord('/') then
    begin
      // A comment opener's two bytes are logical neighbours
      LSecond := FSource.Logical(FPos + 1);
      if FSource.ByteAt(LSecond) = Ord('/') then
      begin
        // A spliced // comment runs on: its next line starts inside it (R23)
        LEnd := DoSkipLineComment(FPos);
        if FAtLineStart then
          DoNoteDocLine(FPos, LEnd);
        FStream.MarkInside(FPos, LEnd);
        FStream.AddComment(FPos, LEnd, True);
        FPos := LEnd;
      end
      else if FSource.ByteAt(LSecond) = Ord('*') then
      begin
        // A comment counts as whitespace: a # after it still starts a line
        if not DoSkipBlockComment(FPos, LEnd) then
        begin
          DoError(FPos, LSecond + 1, esError, PC_ERR_LEX_003, RSLexUnterminatedComment, []);
          // The rest of the file is that one reported span (R7)
          DoEmit(DoMakeToken(tkUnknown, tcSpecial, FPos, FLength));
          FPos := FLength;
          Exit;
        end;
        // No line inside the comment can take a #line (R23)
        FStream.MarkInside(FPos, LEnd);
        FStream.AddComment(FPos, LEnd, False);
        FPos := LEnd;
      end
      else
        Break;
    end
    else
      Break;
  end;
end;

function TPCLexer.DoLiteralPrefix(const AText: string; out APrefix: TPCLiteralPrefix;
  out AIsRaw: Boolean): Boolean;
begin
  // Encoding prefixes (u8 u U L) and their raw forms (R u8R uR UR LR).
  // They join the literal only when they touch its quote (checked by caller).
  Result := True;
  APrefix := lpNone;
  AIsRaw := False;
  if AText = 'u8' then
    APrefix := lpU8
  else if AText = 'u' then
    APrefix := lpLowerU
  else if AText = 'U' then
    APrefix := lpUpperU
  else if AText = 'L' then
    APrefix := lpUpperL
  else if AText = 'R' then
    AIsRaw := True
  else if AText = 'u8R' then
  begin
    APrefix := lpU8;
    AIsRaw := True;
  end
  else if AText = 'uR' then
  begin
    APrefix := lpLowerU;
    AIsRaw := True;
  end
  else if AText = 'UR' then
  begin
    APrefix := lpUpperU;
    AIsRaw := True;
  end
  else if AText = 'LR' then
  begin
    APrefix := lpUpperL;
    AIsRaw := True;
  end
  else
    Result := False;
end;

function TPCLexer.DoSkipQuotedBody(const AQuoteAt: Int64; out AEnd: Int64): Boolean;
var
  LQuote: Integer;
  LByte: Integer;
begin
  // Shape only: from the opening quote at AQuoteAt (a logical byte) to the
  // next unescaped same quote on the same logical line. Walks LOGICAL bytes
  // (C++ translation phase 2): every splice continues the literal, and '\'
  // consumes the next logical byte, so \" and \\ work across a splice. A
  // newline (LF, CR LF, lone CR) ends it unterminated, also right after an
  // escape '\' (as clang); then AEnd = that newline, else the end of input.
  // Escapes are never decoded.
  LQuote := FSource.ByteAt(AQuoteAt);
  AEnd := DoStepLogical(AQuoteAt);
  while AEnd < FLength do
  begin
    if FSource.NewlineLength(AEnd) > 0 then
      Exit(False);
    LByte := FSource.ByteAt(AEnd);
    if LByte = Ord('\') then
    begin
      // The escaped byte: any byte but a newline (that ends the literal)
      AEnd := DoStepLogical(AEnd);
      if (AEnd >= FLength) or (FSource.NewlineLength(AEnd) > 0) then
        Break;
      AEnd := DoStepLogical(AEnd);
      Continue;
    end;
    if LByte = LQuote then
    begin
      // The literal ends right after its closing quote; a splice after it
      // is not part of it (token extent rule)
      AEnd := AEnd + 1;
      Exit(True);
    end;
    AEnd := DoStepLogical(AEnd);
  end;
  AEnd := Min(AEnd, FLength);
  Result := False;
end;

function TPCLexer.DoSkipRawBody(const AQuoteAt: Int64; out AEnd: Int64;
  out ADelimiterOk: Boolean): Boolean;
var
  LDelimStart: Int64;
  LDelimLen: Int64;
  LByte: Integer;
  LI: Int64;
  LMatch: Boolean;
begin
  // R"delim( ... )delim" -- AQuoteAt is the '"' after R. The delimiter is at
  // most 16 bytes, none of: space ( ) \ control characters, non-ASCII.
  // Delimiter, body and closer are read PHYSICALLY: clang never splices a
  // delimiter (a '\' in it is LX0010) and reverts splices in the body.
  ADelimiterOk := True;
  LDelimStart := AQuoteAt + 1;
  AEnd := LDelimStart;
  while (AEnd < FLength) and (FSource.ByteAt(AEnd) <> Ord('(')) do
  begin
    LByte := FSource.ByteAt(AEnd);
    if (LByte <= 32) or (LByte = Ord(')')) or (LByte = Ord('\')) or (LByte >= 127) or
      (AEnd - LDelimStart >= PC_MAX_RAW_DELIMITER) then
    begin
      ADelimiterOk := False;
      Exit(False);
    end;
    Inc(AEnd);
  end;
  if AEnd >= FLength then
    Exit(False);

  // Body: everything up to the first ) delim " -- may span lines
  LDelimLen := AEnd - LDelimStart;
  Inc(AEnd);
  while AEnd < FLength do
  begin
    if (FSource.ByteAt(AEnd) = Ord(')')) and (FSource.ByteAt(AEnd + 1 + LDelimLen) = Ord('"')) then
    begin
      LMatch := True;
      for LI := 0 to LDelimLen - 1 do
      begin
        if FSource.ByteAt(AEnd + 1 + LI) <> FSource.ByteAt(LDelimStart + LI) then
        begin
          LMatch := False;
          Break;
        end;
      end;
      if LMatch then
      begin
        AEnd := AEnd + 2 + LDelimLen;
        Exit(True);
      end;
    end;
    Inc(AEnd);
  end;
  Result := False;
end;

function TPCLexer.DoScanPpNumberEnd(const AStart: Int64): Int64;
var
  LP: Int64;
  LNext: Int64;
  LAfter: Int64;
  LByte: Integer;
begin
  // C++ pp-number, with the PaskalCPP range exception: a '.' followed by
  // another '.' ends the number, so 1..5 is 1 .. 5. AStart is its first
  // byte (logical). Walks LOGICAL bytes, so a splice inside joins it
  // (1 \ newline 2 is 12); look-ahead is pure, splices are reported only
  // once a byte joins. Result = physical end after the last number byte.
  LP := AStart;
  while True do
  begin
    LNext := FSource.Logical(LP + 1);
    LByte := FSource.ByteAt(LNext);
    LAfter := FSource.Logical(LNext + 1);
    if DoIsIdentChar(LByte) then
    begin
      DoWarnSplices(LP + 1, LNext);
      LP := LNext;
      // e+ e- E+ E- p+ p- P+ P-: the sign belongs to the number
      if ((LByte = Ord('e')) or (LByte = Ord('E')) or (LByte = Ord('p')) or (LByte = Ord('P'))) and
        ((FSource.ByteAt(LAfter) = Ord('+')) or (FSource.ByteAt(LAfter) = Ord('-'))) then
      begin
        DoWarnSplices(LP + 1, LAfter);
        LP := LAfter;
      end;
    end
    else if (LByte = Ord('''')) and DoIsIdentChar(FSource.ByteAt(LAfter)) then
    begin
      // A digit separator joins only with the character after it
      DoWarnSplices(LP + 1, LAfter);
      LP := LAfter;
    end
    else if (LByte = Ord('.')) and (FSource.ByteAt(LAfter) <> Ord('.')) then
    begin
      DoWarnSplices(LP + 1, LNext);
      LP := LNext;
    end
    else
      Break;
  end;
  Result := LP + 1;
end;

function TPCLexer.DoIsRadixDigit(const AChar: Char; const ARadix: Integer): Boolean;
begin
  if ARadix = 2 then
    Result := CharInSet(AChar, ['0', '1'])
  else if ARadix = 16 then
    Result := CharInSet(AChar, ['0'..'9', 'a'..'f', 'A'..'F'])
  else
    Result := CharInSet(AChar, ['0'..'9']);
end;

function TPCLexer.DoCountDigits(const AText: string; var AIndex: Integer;
  const ARadix: Integer): Integer;
begin
  // Counts radix digits from AIndex on (1-based) and advances past them. A
  // ' separator is passed only between two digits of the radix.
  Result := 0;
  while AIndex <= Length(AText) do
  begin
    if DoIsRadixDigit(AText[AIndex], ARadix) then
    begin
      Inc(Result);
      Inc(AIndex);
    end
    else if (AText[AIndex] = '''') and (Result > 0) and (AIndex < Length(AText)) and
      DoIsRadixDigit(AText[AIndex + 1], ARadix) then
      Inc(AIndex)
    else
      Break;
  end;
end;

function TPCLexer.DoParseUInt(const ADigits: string; const ARadix: Integer;
  out AValue: UInt64): Boolean;
var
  LI: Integer;
  LDigit: UInt64;
  LChar: Char;
begin
  // UInt64 accumulation with an exact overflow check before each step
  AValue := 0;
  for LI := 1 to Length(ADigits) do
  begin
    LChar := ADigits[LI];
    if CharInSet(LChar, ['0'..'9']) then
      LDigit := Ord(LChar) - Ord('0')
    else if CharInSet(LChar, ['a'..'f']) then
      LDigit := Ord(LChar) - Ord('a') + 10
    else
      LDigit := Ord(LChar) - Ord('A') + 10;

    if AValue > (High(UInt64) - LDigit) div UInt64(ARadix) then
      Exit(False);
    AValue := AValue * UInt64(ARadix) + LDigit;
  end;
  Result := True;
end;

function TPCLexer.DoFloatFormat(const ASuffix: string; out AFormat: TPCFloatFormat): Boolean;
begin
  // A float literal carries a value only in the formats semantics types
  // (sem\types.md): no suffix -> binary64 (double), f / F -> binary32
  // (float). Every other float suffix is opaque: no value (sem\pfloat.md)
  AFormat := ffBinary64;
  Result := True;
  if ASuffix = '' then
    Exit;
  if (ASuffix = 'f') or (ASuffix = 'F') then
  begin
    AFormat := ffBinary32;
    Exit;
  end;
  Result := False;
end;

function TPCLexer.DoIsIntSuffix(const ASuffix: string; out ARow: TPCIntSuffixRow): Boolean;
begin
  // The vocabulary is Common's: SEM reads the same rows
  Result := TPCVocabulary.FindIntSuffix(ASuffix, ARow);
end;

function TPCLexer.DoIsFloatSuffix(const ASuffix: string): Boolean;
var
  LI: Integer;
begin
  Result := False;
  for LI := Low(PC_FLOAT_SUFFIXES) to High(PC_FLOAT_SUFFIXES) do
  begin
    if PC_FLOAT_SUFFIXES[LI] = ASuffix then
      Exit(True);
  end;
end;

function TPCLexer.DoIsRefusedFloatSuffix(const ASuffix: string): Boolean;
var
  LI: Integer;
begin
  Result := False;
  for LI := Low(PC_FLOAT_SUFFIXES_REFUSED) to High(PC_FLOAT_SUFFIXES_REFUSED) do
  begin
    if PC_FLOAT_SUFFIXES_REFUSED[LI] = ASuffix then
      Exit(True);
  end;
end;

function TPCLexer.DoIsSuffixShape(const ASuffix: string): Boolean;
var
  LI: Integer;
begin
  // A suffix is an identifier: letter or '_' first, then letters, digits, '_'
  Result := (ASuffix <> '') and DoIsIdentStart(Ord(ASuffix[1]));
  if not Result then
    Exit;
  for LI := 2 to Length(ASuffix) do
  begin
    if not DoIsIdentChar(Ord(ASuffix[LI])) then
      Exit(False);
  end;
end;

function TPCLexer.DoFailNumber(var AToken: TPCToken; const ACode: string;
  const AMessage: string): Boolean;
begin
  // The message names the literal as spelled
  Result := DoFailNumber(AToken, ACode, AMessage, [AToken.Spelling]);
end;

function TPCLexer.DoFailNumber(var AToken: TPCToken; const ACode: string;
  const AMessage: string; const AArgs: array of const): Boolean;
begin
  // A bad number stays one token (kind unknown) so lexing continues
  DoError(Int64(AToken.Range.StartByteOffset), Int64(AToken.Range.EndByteOffset),
    esError, ACode, AMessage, AArgs);
  AToken.Kind := tkUnknown;
  AToken.Category := tcSpecial;
  AToken.HasValue := False;
  Result := False;
end;

function TPCLexer.DoClassifyNumber(var AToken: TPCToken): Boolean;
var
  LText: string;
  LLen: Integer;
  LP: Integer;
  LDigits: Integer;
  LFrac: Integer;
  LIsFloat: Boolean;
  LShapeOk: Boolean;
  LSuffix: string;
  LNumeric: string;
  LI: Integer;
  LRadix: Integer;
  LInt: UInt64;
  LFloat: Double;
  LFormat: TPCFloatFormat;
  LStatus: TPCFloatStatus;
  LRow: TPCIntSuffixRow;
begin
  // AToken.Spelling is one pp-number (ASCII, splices removed). Split it into
  // numeric part + suffix and classify; the value is computed where C++
  // defines one.
  LRow := Default(TPCIntSuffixRow);
  LText := AToken.Spelling;
  LLen := Length(LText);
  LP := 1;
  LFrac := 0;
  LIsFloat := False;
  LShapeOk := True;

  if (LLen >= 2) and (LText[1] = '0') and CharInSet(LText[2], ['x', 'X']) then
  begin
    // hex integer, or hex float when it has '.' or p
    AToken.LiteralBase := lbHex;
    LP := 3;
    LDigits := DoCountDigits(LText, LP, 16);
    if (LP <= LLen) and (LText[LP] = '.') then
    begin
      LIsFloat := True;
      Inc(LP);
      LFrac := DoCountDigits(LText, LP, 16);
    end;
    if (LP <= LLen) and CharInSet(LText[LP], ['p', 'P']) then
    begin
      LIsFloat := True;
      Inc(LP);
      if (LP <= LLen) and CharInSet(LText[LP], ['+', '-']) then
        Inc(LP);
      if DoCountDigits(LText, LP, 10) = 0 then
        LShapeOk := False;
    end
    else if LIsFloat then
      LShapeOk := False;   // a hex float needs its p exponent
    if LDigits + LFrac = 0 then
      LShapeOk := False;
  end
  else if (LLen >= 2) and (LText[1] = '0') and CharInSet(LText[2], ['b', 'B']) then
  begin
    AToken.LiteralBase := lbBinary;
    LP := 3;
    LDigits := DoCountDigits(LText, LP, 2);
    // 0b2: a decimal digit right after the binary digits is not a suffix
    if (LDigits = 0) or ((LP <= LLen) and CharInSet(LText[LP], ['0'..'9'])) then
      LShapeOk := False;
  end
  else
  begin
    AToken.LiteralBase := lbDecimal;
    LDigits := DoCountDigits(LText, LP, 10);
    if (LP <= LLen) and (LText[LP] = '.') then
    begin
      LIsFloat := True;
      Inc(LP);
      LFrac := DoCountDigits(LText, LP, 10);
    end;
    if LDigits + LFrac = 0 then
      LShapeOk := False;
    if LShapeOk and (LP <= LLen) and CharInSet(LText[LP], ['e', 'E']) then
    begin
      LIsFloat := True;
      Inc(LP);
      if (LP <= LLen) and CharInSet(LText[LP], ['+', '-']) then
        Inc(LP);
      if DoCountDigits(LText, LP, 10) = 0 then
        LShapeOk := False;
    end;
    // Leading 0 + more digits, no fraction or exponent: C++ octal
    if (not LIsFloat) and (LText[1] = '0') and (LDigits > 1) then
      AToken.LiteralBase := lbOctal;
  end;

  LSuffix := Copy(LText, LP, MaxInt);
  if (not LShapeOk) or ((LSuffix <> '') and (not DoIsSuffixShape(LSuffix))) then
    Exit(DoFailNumber(AToken, PC_ERR_LEX_005, RSLexMalformedNumber));

  if LIsFloat then
    AToken.Kind := tkFloatLiteral
  else
    AToken.Kind := tkIntLiteral;
  AToken.Category := tcLiteral;

  LNumeric := Copy(LText, 1, LP - 1).Replace('''', '');
  if AToken.LiteralBase = lbOctal then
  begin
    for LI := 2 to Length(LNumeric) do
    begin
      if CharInSet(LNumeric[LI], ['8', '9']) then
        Exit(DoFailNumber(AToken, PC_ERR_LEX_007, RSLexInvalidOctal));
    end;
  end;

  // A standard suffix the bundled clang refuses is the lexer's report, never
  // a user-defined literal clang would reject in C++ words (F63)
  if LIsFloat and DoIsRefusedFloatSuffix(LSuffix) then
    Exit(DoFailNumber(AToken, PC_ERR_LEX_005, RSLexMalformedNumber));

  // A non-standard suffix is an opaque C++ user-defined literal: no value
  if LSuffix <> '' then
  begin
    AToken.Suffix := LSuffix;
    if LIsFloat then
      AToken.IsUserDefined := not DoIsFloatSuffix(LSuffix)
    else
      AToken.IsUserDefined := not DoIsIntSuffix(LSuffix, LRow);
  end;
  if AToken.IsUserDefined then
    Exit(True);

  if LIsFloat then
  begin
    // Decimal and hex alike: the exact value rounded once to the suffix's
    // format (lexer.md Numbers, sem\pfloat.md); an opaque suffix: no value
    if not DoFloatFormat(LSuffix, LFormat) then
      Exit(True);
    LStatus := TPCFloatDecoder.Decode(LNumeric, LFormat, LFloat);
    if LStatus = fsMalformed then
      Exit(DoFailNumber(AToken, PC_ERR_LEX_005, RSLexMalformedNumber));
    if LStatus = fsOverflow then
      Exit(DoFailNumber(AToken, PC_ERR_LEX_006, RSLexNumberOverflow));
    AToken.FloatValue := LFloat;
    AToken.HasValue := True;
  end
  else
  begin
    if AToken.LiteralBase = lbHex then
      LNumeric := Copy(LNumeric, 3, MaxInt)
    else if AToken.LiteralBase = lbBinary then
      LNumeric := Copy(LNumeric, 3, MaxInt)
    else if AToken.LiteralBase = lbOctal then
      LNumeric := Copy(LNumeric, 2, MaxInt);

    if AToken.LiteralBase = lbHex then
      LRadix := 16
    else if AToken.LiteralBase = lbBinary then
      LRadix := 2
    else if AToken.LiteralBase = lbOctal then
      LRadix := 8
    else
      LRadix := 10;

    if not DoParseUInt(LNumeric, LRadix, LInt) then
      Exit(DoFailNumber(AToken, PC_ERR_LEX_006, RSLexNumberOverflow));
    // C++23 [lex.icon]: a decimal literal without a u suffix takes signed
    // types only, so above int64 no type holds it (clang takes it as unsigned
    // with a warning, C++23 makes it ill-formed): the same mistake as beyond
    // uint64, with the spelling that means the value (the digits as written)
    if (LInt > UInt64(High(Int64))) and
       (not LRow.MayBeUnsigned(AToken.LiteralBase = lbDecimal)) then
      Exit(DoFailNumber(AToken, PC_ERR_LEX_006, RSLexNumberSignedOverflow,
        [AToken.Spelling, Copy(LText, 1, LP - 1) + 'u' + LSuffix]));
    AToken.IntValue := LInt;
    AToken.HasValue := True;
  end;

  if AToken.LiteralBase = lbOctal then
    DoError(Int64(AToken.Range.StartByteOffset), Int64(AToken.Range.EndByteOffset),
      esHint, PC_HINT_LEX_001, RSLexOctalHint, [AToken.Spelling]);
  Result := True;
end;

procedure TPCLexer.DoScanToken();
var
  LByte: Integer;
  LHashEnd: Int64;
begin
  // Dispatch on the first byte after trivia (lexer.md "Dispatch"); FPos is a
  // logical byte here, and look-ahead reads the next logical one
  LByte := FSource.ByteAt(FPos);
  if DoMatchHash(FPos, LHashEnd) then
    DoScanHash(LHashEnd)
  else if LByte = Ord('@') then
    DoScanDirective()
  else if DoIsIdentStart(LByte) then
    DoScanWord()
  else if DoIsDigit(LByte) or ((LByte = Ord('.')) and DoIsDigit(FSource.ByteAt(FSource.Logical(FPos + 1)))) then
    DoScanNumber()
  else if (LByte = Ord('"')) or (LByte = Ord('''')) then
    DoScanQuoted(FPos, lpNone, FPos)
  else
    DoScanOperator();
end;

function TPCLexer.DoMatchHash(const AStart: Int64; out AEnd: Int64): Boolean;
var
  LSecond: Int64;
begin
  // The hash punctuator at the logical byte AStart: # or its digraph %:, the
  // colon read through splices as clang does (research\cppmix\digraphs\
  // d1-clang.md c14b). Pure look-ahead: the caller warns the splices of what it
  // commits. AEnd = the physical end. ## and %:%: are two of them: a # line is
  // one token whatever follows, and anywhere else each one is LX0008
  AEnd := AStart;
  if FSource.ByteAt(AStart) = Ord('#') then
  begin
    AEnd := AStart + 1;
    Exit(True);
  end;
  if FSource.ByteAt(AStart) <> Ord('%') then
    Exit(False);
  LSecond := FSource.NextLogical(AStart);
  if FSource.ByteAt(LSecond) <> Ord(':') then
    Exit(False);
  AEnd := LSecond + 1;
  Result := True;
end;

procedure TPCLexer.DoScanHash(const AHashEnd: Int64);
var
  LStart: Int64;
begin
  // # or %: at FPos, ending at AHashEnd (DoMatchHash)
  if FAtLineStart then
  begin
    DoScanPreprocessor(AHashEnd);
    Exit;
  end;

  // A hash anywhere but the start of a line is not a token
  LStart := FPos;
  FPos := AHashEnd;
  DoWarnSplices(LStart, FPos);
  DoError(LStart, FPos, esError, PC_ERR_LEX_008, RSLexHashNotAtLineStart,
    [FSource.Spelling(LStart, FPos, -1)]);
  DoEmit(DoMakeToken(tkUnknown, tcSpecial, LStart, FPos));
end;

procedure TPCLexer.DoScanPreprocessor(const AHashEnd: Int64);
var
  LStart: Int64;
  LEnd: Int64;
  LWordEnd: Int64;
  LQuoteAt: Int64;
  LSecond: Int64;
  LSplice: Int64;
  LByte: Integer;
  LPrefix: TPCLiteralPrefix;
  LIsRaw: Boolean;
  LDelimiterOk: Boolean;
begin
  // One token for the whole logical line (lexer.md "Preprocessor line
  // token"): every splice continues it (a whitespace one warns); literals
  // are skipped whole so their // and /* are text; a /* */ begun on the
  // line runs through its */; a // runs to the newline. The newline (LF,
  // CR LF or a lone CR) is not part of it.
  LStart := FPos;
  FPos := AHashEnd;
  DoWarnSplices(LStart, FPos);
  while FPos < FLength do
  begin
    if FSource.NewlineLength(FPos) > 0 then
      Break;

    LSplice := FSource.SpliceLength(FPos);
    if LSplice > 0 then
    begin
      DoWarnSplices(FPos, FPos + 1);
      FPos := FPos + LSplice;
      Continue;
    end;

    LByte := FSource.ByteAt(FPos);
    if LByte = Ord('/') then
    begin
      LSecond := FSource.Logical(FPos + 1);
      if FSource.ByteAt(LSecond) = Ord('/') then
      begin
        FPos := DoSkipLineComment(FPos);
        Continue;
      end;
      if FSource.ByteAt(LSecond) = Ord('*') then
      begin
        if not DoSkipBlockComment(FPos, LEnd) then
        begin
          DoError(FPos, LSecond + 1, esError, PC_ERR_LEX_003, RSLexUnterminatedComment, []);
          FPos := FLength;
          Break;
        end;
        FPos := LEnd;
        Continue;
      end;
    end;

    if (LByte = Ord('"')) or (LByte = Ord('''')) then
    begin
      // An unclosed quote (#error don't) runs to the end of the logical
      // line, as in C++: the rest of the line is its text, so a /* in it
      // never opens a comment
      DoSkipQuotedBody(FPos, LEnd);
      FPos := LEnd;
      Continue;
    end;

    if DoIsIdentStart(LByte) then
    begin
      // A raw string inside the line is one literal, whatever it contains
      LWordEnd := DoScanIdentEnd(FPos);
      LQuoteAt := FSource.Logical(LWordEnd);
      if DoLiteralPrefix(FSource.Spelling(FPos, LWordEnd, -1), LPrefix, LIsRaw) and LIsRaw and
        (FSource.ByteAt(LQuoteAt) = Ord('"')) and DoSkipRawBody(LQuoteAt, LEnd, LDelimiterOk) then
      begin
        DoWarnSplices(LWordEnd, LQuoteAt);
        FPos := LEnd;
      end
      else
        FPos := LWordEnd;
      Continue;
    end;

    if DoIsDigit(LByte) then
    begin
      // A pp-number, so a digit separator ' never opens a char literal
      FPos := DoScanPpNumberEnd(FPos);
      Continue;
    end;

    Inc(FPos);
  end;

  DoEmit(DoMakeToken(tkCppPreprocessor, tcPreprocessor, LStart, FPos));
end;

procedure TPCLexer.DoScanDirective();
var
  LStart: Int64;
  LNameAt: Int64;
begin
  // @ + identifier, exact case (@unitTestMode); splices follow the rule
  // everywhere, so @if \ newline def is @ifdef
  LStart := FPos;
  LNameAt := FSource.Logical(LStart + 1);
  if not DoIsIdentStart(FSource.ByteAt(LNameAt)) then
  begin
    FPos := LStart + 1;
    DoError(LStart, FPos, esError, PC_ERR_LEX_009, RSLexDirectiveNoName, []);
    DoEmit(DoMakeToken(tkUnknown, tcSpecial, LStart, FPos));
    Exit;
  end;

  DoWarnSplices(LStart + 1, LNameAt);
  FPos := DoScanIdentEnd(LNameAt);
  DoEmit(DoMakeToken(tkDirective, tcDirective, LStart, FPos));
end;

procedure TPCLexer.DoScanWord();
var
  LStart: Int64;
  LText: string;
  LPrefix: TPCLiteralPrefix;
  LIsRaw: Boolean;
  LQuoteAt: Int64;
  LNext: Integer;
  LEntry: TPCVocabEntry;
  LToken: TPCToken;
  LWasCppstart: Boolean;
begin
  // The word's spelling (splices removed) decides everything below
  LStart := FPos;
  FPos := DoScanIdentEnd(FPos);
  LText := FSource.Spelling(LStart, FPos, -1);

  // A literal prefix touching its quote is one token with the literal:
  // L"x" is one token, L "x" is an identifier then a string. A splice
  // between them still touches (phase 2 runs first).
  if DoLiteralPrefix(LText, LPrefix, LIsRaw) then
  begin
    LQuoteAt := FSource.Logical(FPos);
    LNext := FSource.ByteAt(LQuoteAt);
    if LIsRaw and (LNext = Ord('"')) then
    begin
      DoWarnSplices(FPos, LQuoteAt);
      DoScanRaw(LStart, LPrefix, LQuoteAt);
      Exit;
    end;
    if (not LIsRaw) and ((LNext = Ord('"')) or (LNext = Ord(''''))) then
    begin
      DoWarnSplices(FPos, LQuoteAt);
      DoScanQuoted(LStart, LPrefix, LQuoteAt);
      Exit;
    end;
  end;

  // Exact-case lookup on the spelling; no case folding anywhere
  LWasCppstart := FCaptureNext;
  if FVocabulary.FindWord(LText, LEntry) then
  begin
    LToken := DoMakeToken(LEntry.Kind, LEntry.Category, LStart, FPos);
    LToken.Origin := LEntry.Origin;
  end
  else
    LToken := DoMakeToken(tkIdentifier, tcIdentifier, LStart, FPos);
  DoEmit(LToken);

  // cppstart header|source: the bytes up to cppend are one verbatim token.
  // Any other target word lexes normally; the parser reports it.
  if LWasCppstart and (LToken.Kind = tkIdentifier) and
    ((LText = 'header') or (LText = 'source')) then
    DoCapture();
end;

procedure TPCLexer.DoScanNumber();
var
  LStart: Int64;
  LToken: TPCToken;
begin
  LStart := FPos;
  FPos := DoScanPpNumberEnd(LStart);
  LToken := DoMakeToken(tkIntLiteral, tcLiteral, LStart, FPos);
  DoClassifyNumber(LToken);
  DoEmit(LToken);
end;

procedure TPCLexer.DoScanQuoted(const AStart: Int64; const APrefix: TPCLiteralPrefix;
  const AQuoteAt: Int64);
var
  LBodyEnd: Int64;
  LEnd: Int64;
  LToken: TPCToken;
begin
  if not DoSkipQuotedBody(AQuoteAt, LBodyEnd) then
  begin
    // Unterminated: report at the literal's start, keep the line as one
    // unknown token, and continue after it
    DoError(AStart, AStart + 1, esError, PC_ERR_LEX_001, RSLexUnterminatedString, []);
    FPos := LBodyEnd;
    DoEmit(DoMakeToken(tkUnknown, tcSpecial, AStart, LBodyEnd));
    Exit;
  end;

  LEnd := DoSuffixEnd(LBodyEnd);
  if FSource.ByteAt(AQuoteAt) = Ord('''') then
    LToken := DoMakeToken(tkCharLiteral, tcLiteral, AStart, LEnd)
  else
    LToken := DoMakeToken(tkStringLiteral, tcLiteral, AStart, LEnd);
  LToken.LiteralPrefix := APrefix;
  if LEnd > LBodyEnd then
  begin
    LToken.Suffix := FSource.Spelling(LBodyEnd, LEnd, -1);
    LToken.IsUserDefined := True;
  end;
  FPos := LEnd;
  DoEmit(LToken);
end;

procedure TPCLexer.DoScanRaw(const AStart: Int64; const APrefix: TPCLiteralPrefix;
  const AQuoteAt: Int64);
var
  LBodyEnd: Int64;
  LEnd: Int64;
  LDelimiterOk: Boolean;
  LToken: TPCToken;
  LP: Int64;
begin
  if not DoSkipRawBody(AQuoteAt, LBodyEnd, LDelimiterOk) then
  begin
    // Unterminated: the literal runs to EOF. Bad delimiter: clang's recovery,
    // one unknown token up to the next '"' (included) or EOF, so the rest of
    // the literal is never lexed as more tokens (F61: it ended at the
    // offending byte, and the closing quote then began an unterminated
    // string: LX0001 + PR0001 after the LX0010)
    if LDelimiterOk then
      DoError(AStart, AStart + 1, esError, PC_ERR_LEX_002, RSLexUnterminatedRaw, [])
    else
    begin
      DoError(AStart, AStart + 1, esError, PC_ERR_LEX_010, RSLexRawDelimiter, []);
      LP := LBodyEnd;
      if LP <= AQuoteAt then
        LP := AQuoteAt + 1;
      while (LP < FLength) and (FSource.ByteAt(LP) <> Ord('"')) do
        Inc(LP);
      if LP < FLength then
        Inc(LP);
      LBodyEnd := LP;
    end;
    if LBodyEnd <= AQuoteAt then
      LBodyEnd := AQuoteAt + 1;
    FPos := LBodyEnd;
    DoEmit(DoMakeToken(tkUnknown, tcSpecial, AStart, LBodyEnd));
    Exit;
  end;

  LEnd := DoSuffixEnd(LBodyEnd);
  LToken := DoMakeToken(tkStringLiteral, tcLiteral, AStart, LEnd);
  LToken.LiteralPrefix := APrefix;
  LToken.IsRawString := True;

  // Raw spelling: splices removed in the prefix and the suffix only; the
  // delimiter, body and closer stay physical (clang reverts them)
  DoSetSpelling(LToken, FSource.Spelling(AStart, LBodyEnd, AQuoteAt) +
    FSource.Spelling(LBodyEnd, LEnd, -1));
  if LEnd > LBodyEnd then
  begin
    LToken.Suffix := FSource.Spelling(LBodyEnd, LEnd, -1);
    LToken.IsUserDefined := True;
  end;
  FPos := LEnd;
  DoEmit(LToken);
end;

function TPCLexer.DoIsLessColonColon(const AStart: Int64): Boolean;
var
  LThird: Int64;
  LFourth: Integer;
begin
  // C++11 [lex.pptoken]/3.2: when the next three characters are <:: and the
  // one after them is neither : nor >, the < is a token by itself, so A<::B>
  // is A < ::B. AStart holds '<' and its next logical byte is ':'. Every
  // character is read through splices, end of file counting as "neither", as
  // clang does (research\cppmix\digraphs\d1-clang.md c11 c12 c13 c13b-d)
  LThird := FSource.NextLogical(FSource.NextLogical(AStart));
  if FSource.ByteAt(LThird) <> Ord(':') then
    Exit(False);
  LFourth := FSource.ByteAt(FSource.NextLogical(LThird));
  Result := (LFourth <> Ord(':')) and (LFourth <> Ord('>'));
end;

function TPCLexer.DoMatchOperator(const AStart: Int64; out AEnd: Int64;
  out AEntry: TPCVocabEntry): Boolean;
var
  LEnds: array[1..PC_MAX_OPERATOR_LENGTH] of Int64;
  LP: Int64;
  LCount: Integer;
  LLen: Integer;
  LText: string;
begin
  // The lexer's one operator matcher (tokens and cppstart capture). Longest
  // match over every registered operator spelling, read over LOGICAL bytes
  // (a splice inside joins it: < \ newline < is <<). Absent spellings (^= ->*
  // .*) never match, so LP^=5 lexes ^ = 5. The digraphs <: :> <% %> are rows
  // like any other; <: is not taken where C++11 lexes < :: (DoIsLessColonColon).
  // Operators are ASCII: collect up to PC_MAX_OPERATOR_LENGTH logical ASCII
  // bytes, so a slice never cuts a UTF-8 sequence, and remember the physical
  // end after each one. Pure look-ahead: nothing is reported; the caller
  // warns the splices of a match it commits. AEnd = the physical end
  AEnd := AStart;
  LCount := 0;
  LP := AStart;
  while (LCount < PC_MAX_OPERATOR_LENGTH) and (LP < FLength) and (FSource.ByteAt(LP) < $80) do
  begin
    Inc(LCount);
    LEnds[LCount] := LP + 1;
    LP := FSource.Logical(LP + 1);
  end;

  for LLen := LCount downto 1 do
  begin
    LText := FSource.Spelling(AStart, LEnds[LLen], -1);
    // The <:: exception: <: is not taken there, so the match falls back to <
    if (LText = '<:') and DoIsLessColonColon(AStart) then
      Continue;
    if FVocabulary.FindOperator(LText, AEntry) then
    begin
      AEnd := LEnds[LLen];
      Exit(True);
    end;
  end;
  AEntry := Default(TPCVocabEntry);
  Result := False;
end;

procedure TPCLexer.DoScanOperator();
var
  LStart: Int64;
  LEnd: Int64;
  LEntry: TPCVocabEntry;
  LToken: TPCToken;
begin
  LStart := FPos;
  if DoMatchOperator(LStart, LEnd, LEntry) then
  begin
    FPos := LEnd;
    DoWarnSplices(LStart, FPos);
    LToken := DoMakeToken(LEntry.Kind, LEntry.Category, LStart, FPos);
    LToken.Origin := LEntry.Origin;
    DoEmit(LToken);
    Exit;
  end;

  // Nothing matches: one invalid character (a whole UTF-8 sequence)
  FPos := LStart + FSource.Utf8Length(LStart);
  DoError(LStart, FPos, esError, PC_ERR_LEX_004, RSLexInvalidChar, [FSource.Slice(LStart, FPos)]);
  DoEmit(DoMakeToken(tkUnknown, tcSpecial, LStart, FPos));
end;

procedure TPCLexer.DoTrackSplices(const AStart: Int64; const AEnd: Int64;
  const ASplices: Boolean; var ALastSpliceAt: Int64; var ANewlineAfter: Boolean);
var
  LP: Int64;
  LSplice: Int64;
  LNewline: Int64;
begin
  // LX0014's tracking over the bytes of one element DoCapture steps over
  // whole (F-L2). The decided rule (lexer-splice-trailing.md) is "after the
  // LAST splice in the block bytes no newline occurs", so inside an element
  // every splice is a candidate and every newline after it clears it, the
  // same as between elements (the loop top). ASplices False = a raw string
  // body: `\`+newline is content there, only its newlines count. A splice's
  // own newline is part of the splice, never a newline after it
  LP := AStart;
  while LP < AEnd do
  begin
    LNewline := FSource.NewlineLength(LP);
    if LNewline > 0 then
    begin
      ANewlineAfter := True;
      LP := LP + LNewline;
      Continue;
    end;
    if ASplices then
    begin
      LSplice := FSource.SpliceLength(LP);
      if LSplice > 0 then
      begin
        ALastSpliceAt := LP;
        ANewlineAfter := False;
        LP := LP + LSplice;
        Continue;
      end;
    end;
    Inc(LP);
  end;
end;

procedure TPCLexer.DoAddCppElement(const AKind: TPCCppElementKind;
  const ATokenKind: TPCTokenKind; const AStart: Int64; const AEnd: Int64);
var
  LElement: TPCCppElement;
begin
  // One C++ element of a cppstart block (O-S6b): spelling (splice-free; a
  // literal's text is not kept, no rule reads it), the vocabulary kind of a
  // punctuator (tkUnknown otherwise: the walker compares punctuators by kind,
  // so another spelling of one kind, a digraph, reads the same) and its
  // .pcpp range
  LElement := Default(TPCCppElement);
  LElement.Kind := AKind;
  LElement.TokenKind := ATokenKind;
  if AKind <> ceLiteral then
    LElement.Spelling := FSource.Spelling(AStart, AEnd, -1);
  FSource.FillRange(LElement.Range, AStart, AEnd);
  FStream.AddCppElement(LElement);
end;

procedure TPCLexer.DoCapture();
var
  LStart: Int64;
  LP: Int64;
  LEnd: Int64;
  LWordStart: Int64;
  LElementStart: Int64;
  LQuoteAt: Int64;
  LSecond: Int64;
  LNewline: Int64;
  LSplice: Int64;
  LLastSpliceAt: Int64;
  LNewlineAfterSplice: Boolean;
  LHashEnd: Int64;
  LAtLineStart: Boolean;
  LInDirective: Boolean;
  LByte: Integer;
  LPrefix: TPCLiteralPrefix;
  LIsRaw: Boolean;
  LDelimiterOk: Boolean;
  LKind: TPCCppElementKind;
  LEntry: TPCVocabEntry;
begin
  // cppstart header|source ... cppend (lexer.md "cppstart block capture").
  // Only C++ literals and comments are recognized, so a cppend inside them
  // never ends the block; every other byte is accepted (no lexical errors
  // but LX0014 below). Splices follow the lexer's rule: they continue
  // comments and literals, join words (cpp \ newline end is cppend), and a
  // whitespace one warns. The block is emitted byte-exact, so if no
  // newline follows its last splice that splice would join whatever is
  // emitted next: LX0014 (research\cppmix\lexer-splice-trailing.md).
  // The walk also records the block's C++ elements on the stream (O-S6b,
  // research\cppmix\sem\prereq-b\jump.md): words, literals, operators
  // (DoMatchOperator, the lexer's one longest match) and any other byte
  // sequence. Comments and whitespace are no elements. A # or %: first on its
  // line (comments do not count, as FAtLineStart) starts a # line: nothing
  // is recorded up to the next newline this loop meets (a block comment's
  // or a splice's newline never reaches it: the # line continues, as in
  // DoScanPreprocessor). The block starts after its target word, so its
  // first byte is not at a line start.
  LStart := FPos;
  LP := FPos;
  LLastSpliceAt := -1;
  LNewlineAfterSplice := False;
  LAtLineStart := False;
  LInDirective := False;
  while LP < FLength do
  begin
    LNewline := FSource.NewlineLength(LP);
    if LNewline > 0 then
    begin
      LNewlineAfterSplice := True;
      LAtLineStart := True;
      LInDirective := False;
      LP := LP + LNewline;
      Continue;
    end;

    LSplice := FSource.SpliceLength(LP);
    if LSplice > 0 then
    begin
      LLastSpliceAt := LP;
      LNewlineAfterSplice := False;
      DoWarnSplices(LP, LP + 1);
      LP := LP + LSplice;
      Continue;
    end;

    LByte := FSource.ByteAt(LP);
    // Blanks are no elements (F-L1); a newline was taken above
    if (LByte = Ord(' ')) or (LByte = 9) or (LByte = 11) or (LByte = 12) then
    begin
      Inc(LP);
      Continue;
    end;

    if LByte = Ord('/') then
    begin
      LSecond := FSource.Logical(LP + 1);
      if FSource.ByteAt(LSecond) = Ord('/') then
      begin
        // Each C++ element in the block marks the lines inside it (R23); a
        // comment is block bytes for LX0014 too (F-L2), never an element
        LEnd := DoSkipLineComment(LP);
        FStream.MarkInside(LP, LEnd);
        DoTrackSplices(LP, LEnd, True, LLastSpliceAt, LNewlineAfterSplice);
        LP := LEnd;
        Continue;
      end;
      if FSource.ByteAt(LSecond) = Ord('*') then
      begin
        // An unclosed comment swallows the rest; EOF is then reported below
        DoSkipBlockComment(LP, LEnd);
        FStream.MarkInside(LP, LEnd);
        DoTrackSplices(LP, LEnd, True, LLastSpliceAt, LNewlineAfterSplice);
        LP := LEnd;
        Continue;
      end;
    end;

    // A # or %: first on its line (DoMatchHash, the lexer's one hash rule):
    // a # line, none of its elements is recorded. A splice between % and :
    // is tracked like every other splice in the block bytes (F-L2)
    if LAtLineStart and DoMatchHash(LP, LHashEnd) then
    begin
      LInDirective := True;
      LAtLineStart := False;
      DoWarnSplices(LP, LHashEnd);
      DoTrackSplices(LP, LHashEnd, True, LLastSpliceAt, LNewlineAfterSplice);
      LP := LHashEnd;
      Continue;
    end;
    LAtLineStart := False;

    if (LByte = Ord('"')) or (LByte = Ord('''')) then
    begin
      // An unclosed quote runs to the end of its logical line, as in C++
      // (the same rule as on a # line)
      DoSkipQuotedBody(LP, LEnd);
      FStream.MarkInside(LP, LEnd);
      DoTrackSplices(LP, LEnd, True, LLastSpliceAt, LNewlineAfterSplice);
      if not LInDirective then
        DoAddCppElement(ceLiteral, tkUnknown, LP, LEnd);
      LP := LEnd;
      Continue;
    end;

    if DoIsDigit(LByte) or ((LByte = Ord('.')) and DoIsDigit(FSource.ByteAt(FSource.Logical(LP + 1)))) then
    begin
      // Whole pp-numbers, so 1cppend or 1'000 never look like the end word
      LElementStart := LP;
      LP := DoScanPpNumberEnd(LP);
      FStream.MarkInside(LElementStart, LP);
      DoTrackSplices(LElementStart, LP, True, LLastSpliceAt, LNewlineAfterSplice);
      if not LInDirective then
        DoAddCppElement(ceLiteral, tkUnknown, LElementStart, LP);
      Continue;
    end;

    if DoIsIdentStart(LByte) then
    begin
      // Whole identifiers, so cppend counts only at an identifier boundary;
      // it is matched by its spelling
      LWordStart := LP;
      LP := DoScanIdentEnd(LP);
      if FSource.Spelling(LWordStart, LP, -1) = 'cppend' then
      begin
        if (LLastSpliceAt >= 0) and (not LNewlineAfterSplice) then
          DoError(LLastSpliceAt, LLastSpliceAt + FSource.SpliceLength(LLastSpliceAt),
            esError, PC_ERR_LEX_014, RSLexCppstartTrailingSplice, []);

        // The block is every byte between the target word and cppend,
        // untrimmed, so lines and columns stay exact. cppend itself is
        // then lexed normally, with no trivia of its own.
        DoEmit(DoMakeToken(tkRawBlock, tcVerbatim, LStart, LWordStart));
        FPos := LWordStart;
        Exit;
      end;
      // The word's own bytes are block bytes (cppend's are not: checked above)
      DoTrackSplices(LWordStart, LP, True, LLastSpliceAt, LNewlineAfterSplice);
      // A raw string prefix touching its quote: skip the raw literal whole
      // (prefix + body = one literal element). Between prefix and quote a
      // splice is a splice; inside the body `\`+newline is content (F-L2)
      LKind := ceWord;
      LQuoteAt := FSource.Logical(LP);
      if DoLiteralPrefix(FSource.Spelling(LWordStart, LP, -1), LPrefix, LIsRaw) and LIsRaw and
        (FSource.ByteAt(LQuoteAt) = Ord('"')) and DoSkipRawBody(LQuoteAt, LEnd, LDelimiterOk) then
      begin
        DoWarnSplices(LP, LQuoteAt);
        DoTrackSplices(LP, LQuoteAt, True, LLastSpliceAt, LNewlineAfterSplice);
        DoTrackSplices(LQuoteAt, LEnd, False, LLastSpliceAt, LNewlineAfterSplice);
        LP := LEnd;
        LKind := ceLiteral;
      end;
      FStream.MarkInside(LWordStart, LP);
      if not LInDirective then
        DoAddCppElement(LKind, tkUnknown, LWordStart, LP);
      Continue;
    end;

    // A # or %: anywhere else is one element, as clang's one hash token (no
    // operator row holds it, so %: is never % then :)
    if DoMatchHash(LP, LHashEnd) then
    begin
      DoWarnSplices(LP, LHashEnd);
      DoTrackSplices(LP, LHashEnd, True, LLastSpliceAt, LNewlineAfterSplice);
      if not LInDirective then
        DoAddCppElement(ceOther, tkUnknown, LP, LHashEnd);
      LP := LHashEnd;
      Continue;
    end;

    // Any other byte: an operator by the lexer's longest match, else one
    // UTF-8 sequence (capture accepts every byte: no error). A match steps
    // over the splices inside it: they are warned on commit and tracked for
    // LX0014, as every element's are
    if DoMatchOperator(LP, LEnd, LEntry) then
    begin
      DoWarnSplices(LP, LEnd);
      DoTrackSplices(LP, LEnd, True, LLastSpliceAt, LNewlineAfterSplice);
      if not LInDirective then
        DoAddCppElement(cePunct, LEntry.Kind, LP, LEnd);
      LP := LEnd;
      Continue;
    end;

    LEnd := LP + FSource.Utf8Length(LP);
    if not LInDirective then
      DoAddCppElement(ceOther, tkUnknown, LP, LEnd);
    LP := LEnd;
  end;

  // EOF inside the block: report at the cppstart; the block's text is that
  // one reported span (R7)
  DoError(Int64(FCppstartToken.Range.StartByteOffset), Int64(FCppstartToken.Range.EndByteOffset),
    esError, PC_ERR_LEX_013, RSLexCppstartNoCppend, []);
  DoEmit(DoMakeToken(tkUnknown, tcSpecial, LStart, FLength));
  FPos := FLength;
end;

function TPCLexer.TokenizeFile(const AFilename: string; const AStream: TPCTokenStream): Boolean;
var
  LPath: string;
  LBytes: TBytes;
begin
  // Every path resolves through TUtils.ResolvePath (PROJECT.md ZigBuild
  // Driver), inside the guard: a name no file routine can take is reported
  // like a file that cannot be read
  LPath := AFilename;
  try
    LPath := TUtils.ResolvePath(AFilename);
    LBytes := TFile.ReadAllBytes(LPath);
  except
    on E: Exception do
    begin
      FErrors.Add(LPath, 0, 0, esError, PC_ERR_LEX_012, RSLexFileError, [LPath, E.Message]);
      // Every stream the lexer fills ends with exactly one EOF, this one too
      AStream.Init(nil, LPath);
      DoReset(AStream);
      DoEmitEof();
      Exit(False);
    end;
  end;

  Result := TokenizeBytes(LBytes, LPath, AStream);
end;

function TPCLexer.TokenizeBytes(const ABytes: TBytes; const AFilename: string;
  const AStream: TPCTokenStream): Boolean;
begin
  // The stream's source text takes the bytes and builds the line table;
  // the lexer reads through it
  AStream.Init(ABytes, AFilename);
  DoReset(AStream);

  // A broken vocabulary is reported (fatal) by Build itself
  if not FVocabulary.Build() then
  begin
    DoEmitEof();
    Exit(False);
  end;

  if not DoValidateUtf8() then
  begin
    DoEmitEof();
    Exit(False);
  end;

  // A UTF-8 BOM is trivia of the first token: offsets keep indexing the file
  FPos := FSource.FirstLineStart();
  FTriviaStart := 0;

  while not FStopped do
  begin
    DoSkipTrivia();
    if FStopped or (FPos >= FLength) then
      Break;
    DoScanToken();
  end;

  DoEmitEof();
  // A lexer error leaves its span as one tkUnknown token (reported once):
  // the stream still holds the file (PLAN-RECOVERY, R7)
  Result := True;
end;

end.
