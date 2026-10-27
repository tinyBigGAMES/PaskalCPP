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
  PaskalCPP.TestSuite.Spec - a .pcpp test's own description, and its markers

  A .pcpp test describes itself in one spec, inside a /* */ block comment
  anywhere in the file:

    /*
      @@test
        kind run                    -- run build error tests dep unit cli
        deps lib_math               -- stems built first, in this cell
        targets x86_64-windows-gnu x86_64-linux-gnu
        opt debug fast
        subsystem console
        define TRACE LEVEL=2
        args "one \"two\""
        stdin "fixtures/input.txt"  -- the program's standard input
        exitcode 0
        warnings allow
        expect
        | hello
        expect x86_64-linux-gnu
        | hello from linux
        expectfile "lib_math.expected"
      @@end
    */

  Whitespace, newlines and indentation do not matter; `--` starts a note to
  the end of its line; `| text` is one expected output line (one blank after
  the bar dropped, trailing blanks dropped; `<DIR>` in it is the test file's
  folder in '/' form); a quoted value takes \" and \\ only. expect /
  expectfile take an optional target first (that target's output; without
  one, every target's). stdin and expectfile paths are relative to the test
  file's folder. A cli test runs pcpp itself with args (pcpp's arguments,
  <DIR> in them as in expect lines; pcpp runs in the suite's output root,
  so what it writes never lands beside the test), once, on this machine:
  it takes args, exitcode, expect and expectfile only. The comment is
  found with the real lexer's comment spans, never a text search. Strict:
  an unknown key or value, a key twice, a missing @@end, a marker in a //
  comment, a spec in a conditional region or a cppstart block, a second
  spec in one file are each a discovery error (TS0001+, file:line:col),
  reported once, at the mistake: a key takes its value whatever its form (a
  wrong one is reported at the value), an unknown key takes the values
  after it, so no value is read again as a key and no key reports a value
  already reported.

  The scanner also reads a file's report markers (`// ERROR SM0118@5: text`,
  TPCTestMarker) from the lexer's // comment spans, from /* */ comments
  whose text begins with // (the form for a line no // comment can end: one
  that ends in a line splice), from the first line of each span the lexer
  could not close (an unterminated comment, string or raw string: one
  reported tkUnknown span, read like a // comment from its first //), from
  the /* */ comments inside a # line (one token, no comment spans; by the
  same block-comment rule), and from the comments between the C++ elements
  of each cppstart block.

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Resources (RSTst*),
    PaskalCPP.Common (token kinds, PC_DATA_MODELS), PaskalCPP.SourceText,
    PaskalCPP.TokenStream, PaskalCPP.Lexer, PaskalCPP.Conditionals
    (NestingOf), PaskalCPP.ZigBuild, PaskalCPP.Compiler (the optimize /
    subsystem spellings), PaskalCPP.TestSuite.Types
  Notes: The lexer's own reports never reach the suite (its own TErrors):
    an error test's file lexes with errors on purpose. A file the lexer
    gives no text for (unreadable, invalid UTF-8) is TS0001: such input is a
    code test's (TestSuite.CodeTest).
===============================================================================}

unit PaskalCPP.TestSuite.Spec;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.Common,
  PaskalCPP.ZigBuild,
  PaskalCPP.TokenStream,
  PaskalCPP.Lexer,
  PaskalCPP.TestSuite.Types;

const
  { PC_ERR_TS_001 }
  PC_ERR_TS_001 = 'TS0001';   // the file cannot be read, or has no text the lexer accepts
  { PC_ERR_TS_002 }
  PC_ERR_TS_002 = 'TS0002';   // @@test / @@end in a // comment
  { PC_ERR_TS_003 }
  PC_ERR_TS_003 = 'TS0003';   // a second spec in one file
  { PC_ERR_TS_004 }
  PC_ERR_TS_004 = 'TS0004';   // no @@end before the comment ends
  { PC_ERR_TS_005 }
  PC_ERR_TS_005 = 'TS0005';   // an unknown key
  { PC_ERR_TS_006 }
  PC_ERR_TS_006 = 'TS0006';   // a key given twice
  { PC_ERR_TS_007 }
  PC_ERR_TS_007 = 'TS0007';   // a value the key does not take
  { PC_ERR_TS_008 }
  PC_ERR_TS_008 = 'TS0008';   // a key without its value
  { PC_ERR_TS_009 }
  PC_ERR_TS_009 = 'TS0009';   // a malformed quoted value
  { PC_ERR_TS_010 }
  PC_ERR_TS_010 = 'TS0010';   // a spec inside a conditional region
  { PC_ERR_TS_011 }
  PC_ERR_TS_011 = 'TS0011';   // a spec inside a cppstart block
  { PC_ERR_TS_012 }
  PC_ERR_TS_012 = 'TS0012';   // no kind
  { PC_ERR_TS_013 }
  PC_ERR_TS_013 = 'TS0013';   // a key the kind does not take
  { PC_ERR_TS_014 }
  PC_ERR_TS_014 = 'TS0014';   // an output line not under expect
  { PC_ERR_TS_015 }
  PC_ERR_TS_015 = 'TS0015';   // an expectfile that does not exist
  { PC_ERR_TS_016 }
  PC_ERR_TS_016 = 'TS0016';   // a malformed report marker
  { PC_ERR_TS_017 }
  PC_ERR_TS_017 = 'TS0017';   // a stdin file that does not exist

  { PC_TS_SPEC_OPEN }
  PC_TS_SPEC_OPEN = '@@test';
  { PC_TS_SPEC_CLOSE }
  PC_TS_SPEC_CLOSE = '@@end';

  { PC_TS_KEY_KIND }
  PC_TS_KEY_KIND = 'kind';
  { PC_TS_KEY_DEPS }
  PC_TS_KEY_DEPS = 'deps';
  { PC_TS_KEY_TARGETS }
  PC_TS_KEY_TARGETS = 'targets';
  { PC_TS_KEY_OPT }
  PC_TS_KEY_OPT = 'opt';
  { PC_TS_KEY_SUBSYSTEM }
  PC_TS_KEY_SUBSYSTEM = 'subsystem';
  { PC_TS_KEY_DEFINE }
  PC_TS_KEY_DEFINE = 'define';
  { PC_TS_KEY_ARGS }
  PC_TS_KEY_ARGS = 'args';
  { PC_TS_KEY_EXITCODE }
  PC_TS_KEY_EXITCODE = 'exitcode';
  { PC_TS_KEY_WARNINGS }
  PC_TS_KEY_WARNINGS = 'warnings';
  { PC_TS_KEY_EXPECTFILE }
  PC_TS_KEY_EXPECTFILE = 'expectfile';
  { PC_TS_KEY_EXPECT }
  PC_TS_KEY_EXPECT = 'expect';
  { PC_TS_KEY_STDIN }
  PC_TS_KEY_STDIN = 'stdin';

  { PC_TS_KEYS }
  // Every spec key (the plan's set; a new key needs the user's OK)
  PC_TS_KEYS: array[0..11] of string = (
    PC_TS_KEY_KIND,
    PC_TS_KEY_DEPS,
    PC_TS_KEY_TARGETS,
    PC_TS_KEY_OPT,
    PC_TS_KEY_SUBSYSTEM,
    PC_TS_KEY_DEFINE,
    PC_TS_KEY_ARGS,
    PC_TS_KEY_EXITCODE,
    PC_TS_KEY_WARNINGS,
    PC_TS_KEY_EXPECTFILE,
    PC_TS_KEY_EXPECT,
    PC_TS_KEY_STDIN
  );

  { PC_TS_KIND_TEXT }
  // A kind as a spec spells it (skCode has no spelling: code tests have no spec)
  PC_TS_KIND_TEXT: array[TPCTestKind] of string = (
    'run',
    'build',
    'error',
    'tests',
    'dep',
    'unit',
    'cli',
    'manual',
    'code'
  );

  { PC_TS_WARNINGS_ALLOW }
  // warnings allow: a hint or warning no marker takes does not fail the test
  PC_TS_WARNINGS_ALLOW = 'allow';

type
  { TPCTestExpect }
  // One expected output: lines in the spec, or a file beside the test
  TPCTestExpect = record
    Target: string;                 // '' = every target without its own
    IsFile: Boolean;
    Text: string;                   // the lines, joined by #10 (IsFile: '')
    FilePath: string;               // IsFile: resolved beside the test file
  end;

  { TPCTestSpec }
  // A .pcpp test's spec, defaults applied (targets: both official, opt:
  // debug, subsystem: console)
  TPCTestSpec = record
    Filename: string;               // resolved
    Stem: string;
    SpecRange: TSourceRange;        // the @@test marker (messages)
    Kind: TPCTestKind;
    Deps: TArray<string>;
    Targets: TArray<string>;
    OptLevels: TArray<TPCOptimizeLevel>;
    // True when the spec names no opt (OptLevels is then the default
    // [debug]): a run that asks for -opt levels runs it at those instead
    OptDefault: Boolean;
    Subsystems: TArray<TPCSubsystemType>;
    Defines: TArray<string>;        // NAME or NAME=VALUE
    Args: string;                   // the program's arguments (cli: pcpp's), as one command line tail
    Stdin: string;                  // resolved beside the test file; '' = none (NUL)
    ExitCode: Integer;              // 0 unless given
    AllowWarnings: Boolean;
    Expects: TArray<TPCTestExpect>;

    // Targets x OptLevels x Subsystems, in that order
    function Cells(): TPCTestCells;
    // ATarget's own expect, else the every-target one; False = none (the
    // program prints nothing)
    function ExpectFor(const ATarget: string; out AExpect: TPCTestExpect): Boolean;
  end;

  { TPCSpecTokenKind }
  // spWord: a bare word; spQuoted: a "..." value; spLine: a | output line;
  // spClose: @@end; spBad: a malformed quoted value, already reported (the
  // key it belongs to passes over it: one report per mistake)
  TPCSpecTokenKind = (spWord, spQuoted, spLine, spClose, spBad);

  { TPCSpecTokenKinds }
  TPCSpecTokenKinds = set of TPCSpecTokenKind;

  { TPCSpecToken }
  TPCSpecToken = record
    Kind: TPCSpecTokenKind;
    Text: string;
    StartOffset: Int64;
    EndOffset: Int64;               // exclusive
  end;

  { TPCSpecKeyUse }
  // A key as given: its identity for the twice rule (expect / expectfile
  // count per target) and where it stands
  TPCSpecKeyUse = record
    Key: string;
    UseId: string;
    StartOffset: Int64;
    EndOffset: Int64;
  end;

  { TPCTestSpecScanner }
  TPCTestSpecScanner = class(TBaseObject)
  private
    FLexErrors: TErrors;            // the lexer's own reports: never the suite's
    FLexer: TPCLexer;
    FStream: TPCTokenStream;
    FBytes: TBytes;
    FFilename: string;
    FHadError: Boolean;
    // The spec being read
    FSpec: TPCTestSpec;
    FHasKind: Boolean;
    FSpecStart: Int64;
    FKeyUses: TList<TPCSpecKeyUse>;

    function DoLex(const AFilename: string): Boolean;
    procedure DoError(const AStart: Int64; const AEnd: Int64; const ACode: string;
      const AMessage: string; const AArgs: array of const);
    procedure DoErrorAt(const AToken: TPCSpecToken; const ACode: string;
      const AMessage: string; const AArgs: array of const);
    function DoIsBlank(const AOffset: Int64): Boolean;
    function DoLineEnd(const AFrom: Int64; const ATo: Int64): Int64;
    function DoFindMarker(const AText: string; const AFrom: Int64; const ATo: Int64): Int64;
    function DoDepthAt(const AOffset: Int64): Integer;
    function DoKeysText(): string;
    function DoKindsText(): string;
    function DoTargetsText(): string;

    // Discovery
    procedure DoCheckLineComment(const AComment: TPCCommentSpan);
    procedure DoCheckCppBlocks();
    function DoReadSpec(const AAt: Int64; const ABodyEnd: Int64): Int64;
    function DoTokenize(const AFrom: Int64; const ATo: Int64;
      const ATokens: TList<TPCSpecToken>): Int64;
    function DoReadQuoted(var AOffset: Int64; const ATo: Int64;
      out AToken: TPCSpecToken): Boolean;
    procedure DoParse(const ATokens: TList<TPCSpecToken>);
    procedure DoParseKey(const AKey: TPCSpecToken; const ATokens: TList<TPCSpecToken>;
      var AIndex: Integer);
    procedure DoUseKey(const AKey: TPCSpecToken; const AUseId: string);
    function DoTakeValue(const AKey: TPCSpecToken; const ATokens: TList<TPCSpecToken>;
      var AIndex: Integer; const AKinds: TPCSpecTokenKinds; const AWant: string;
      out AValue: TPCSpecToken): Boolean;
    function DoTakeWords(const AKey: TPCSpecToken; const ATokens: TList<TPCSpecToken>;
      var AIndex: Integer; out AWords: TArray<TPCSpecToken>): Boolean;
    function DoIsValueWord(const ATokens: TList<TPCSpecToken>; const AIndex: Integer): Boolean;
    function DoIsValue(const ATokens: TList<TPCSpecToken>; const AIndex: Integer): Boolean;
    function DoKeyGiven(const AKey: string): Boolean;
    procedure DoParseKind(const AKey: TPCSpecToken; const ATokens: TList<TPCSpecToken>;
      var AIndex: Integer);
    procedure DoParseList(const AKey: TPCSpecToken; const ATokens: TList<TPCSpecToken>;
      var AIndex: Integer);
    procedure DoParseExpect(const AKey: TPCSpecToken; const ATokens: TList<TPCSpecToken>;
      var AIndex: Integer);
    procedure DoParseExpectFile(const AKey: TPCSpecToken; const ATokens: TList<TPCSpecToken>;
      var AIndex: Integer);
    procedure DoParseStdin(const AKey: TPCSpecToken; const ATokens: TList<TPCSpecToken>;
      var AIndex: Integer);
    // AValue resolved against the test file's folder; False = reported at
    // AValue with ACode / AMessage (the path, why) and APath unusable
    function DoResolveBeside(const AValue: TPCSpecToken; const ACode: string;
      const AMessage: string; out APath: string): Boolean;
    procedure DoFinish();

    // Markers
    function DoMarkersOf(const AStart: Int64; const AEnd: Int64;
      var AMarkers: TArray<TPCTestMarker>): Boolean;
    // [AStart, AEnd) = one /* */ comment, read only when its text begins
    // with // (a marker on a line no // comment can end: one ending in a
    // line splice). Each // up to the next //, its line end or the comment's
    // end is one marker or prose, on that //'s line
    function DoBlockCommentMarkers(const AStart: Int64; const AEnd: Int64;
      var AMarkers: TArray<TPCTestMarker>): Boolean;
    // A tkUnknown span (what the lexer could not close): its first line's
    // markers, read like a // comment from the first //
    function DoOpenSpanMarkers(const AToken: TPCToken; var AMarkers: TArray<TPCTestMarker>): Boolean;
    // A # line (one tkCppPreprocessor token: its comments are not comment
    // spans): its /* */ comments, by the block-comment rule, so a # line
    // ending in a splice can carry a marker. Quoted text is skipped (an
    // #include path or a string is no comment)
    function DoPreprocMarkers(const AToken: TPCToken; var AMarkers: TArray<TPCTestMarker>): Boolean;
    function DoBlockMarkers(const AToken: TPCToken; var AMarkers: TArray<TPCTestMarker>): Boolean;
    function DoGapMarkers(const AFrom: Int64; const ATo: Int64;
      var AMarkers: TArray<TPCTestMarker>): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // The spec of AFilename. AHasSpec False = the file has none (a support
    // file a test imports). False = discovery errors reported (FErrors)
    function Scan(const AFilename: string; out ASpec: TPCTestSpec;
      out AHasSpec: Boolean): Boolean;
    // The spec of an example program (an example root's file): its own spec
    // when it has one, else the implied one, a build test in the default
    // cells whose range is the file's first byte. False = discovery errors
    // reported (FErrors)
    function ScanExample(const AFilename: string; out ASpec: TPCTestSpec): Boolean;
    // AFilename's report markers, appended to AMarkers. False = a malformed
    // marker or no text (reported)
    function ScanMarkers(const AFilename: string; var AMarkers: TArray<TPCTestMarker>): Boolean;
    // A supported target triple (a PC_DATA_MODELS row)
    class function IsTarget(const AText: string): Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.SourceText,
  PaskalCPP.Conditionals,
  PaskalCPP.Compiler;

const
  { PC_TS_LEX_MAX_ERRORS }
  // The lexer never stops early: every comment of the file is wanted
  PC_TS_LEX_MAX_ERRORS = MaxInt;

  { PC_TS_NOTE }
  // A note to the end of its line
  PC_TS_NOTE = '--';

  { PC_TS_LINE_BAR }
  PC_TS_LINE_BAR = Ord('|');

  { PC_TS_QUOTE }
  PC_TS_QUOTE = Ord('"');

  { PC_TS_BACKSLASH }
  PC_TS_BACKSLASH = Ord('\');

  { PC_TS_LINE_COMMENT }
  PC_TS_LINE_COMMENT = '//';

  { PC_TS_USE_EXPECT }
  // expect and expectfile share one identity per target: one output each
  PC_TS_USE_EXPECT = 'expect:';

{ TPCTestSpec }

function TPCTestSpec.Cells(): TPCTestCells;
var
  LTarget: string;
  LOpt: TPCOptimizeLevel;
  LSubsystem: TPCSubsystemType;
begin
  Result := [];
  for LTarget in Targets do
  begin
    for LOpt in OptLevels do
    begin
      for LSubsystem in Subsystems do
        Result := Result + [TPCTestCell.Make(LTarget, LOpt, LSubsystem)];
    end;
  end;
end;

function TPCTestSpec.ExpectFor(const ATarget: string; out AExpect: TPCTestExpect): Boolean;
var
  LExpect: TPCTestExpect;
begin
  AExpect := Default(TPCTestExpect);
  Result := False;
  for LExpect in Expects do
  begin
    if LExpect.Target = ATarget then
    begin
      AExpect := LExpect;
      Exit(True);
    end;
    if LExpect.Target = '' then
    begin
      AExpect := LExpect;
      Result := True;
    end;
  end;
end;

{ TPCTestSpecScanner }

constructor TPCTestSpecScanner.Create();
begin
  inherited;

  FLexErrors := TErrors.Create();
  FLexErrors.SetMaxErrors(PC_TS_LEX_MAX_ERRORS);
  FLexer := TPCLexer.Create();
  FStream := TPCTokenStream.Create();
  FLexer.SetErrors(FLexErrors);
  FStream.SetErrors(FLexErrors);
  FKeyUses := TList<TPCSpecKeyUse>.Create();
  FBytes := nil;
  FFilename := '';
  FHadError := False;
end;

destructor TPCTestSpecScanner.Destroy();
begin
  FKeyUses.Free();
  FStream.Free();
  FLexer.Free();
  FLexErrors.Free();

  inherited;
end;

class function TPCTestSpecScanner.IsTarget(const AText: string): Boolean;
var
  LI: Integer;
begin
  for LI := Low(PC_DATA_MODELS) to High(PC_DATA_MODELS) do
  begin
    if PC_DATA_MODELS[LI].Target = AText then
      Exit(True);
  end;
  Result := False;
end;

function TPCTestSpecScanner.DoLex(const AFilename: string): Boolean;
var
  LReason: string;
begin
  FLexErrors.Clear();
  FBytes := nil;
  FFilename := AFilename;
  if not FLexer.TokenizeFile(AFilename, FStream) then
  begin
    // The lexer's own words say why there is no text
    LReason := '';
    if FLexErrors.Count() > 0 then
      LReason := FLexErrors.GetItems()[0].Message;
    FErrors.Add(AFilename, 0, 0, esError, PC_ERR_TS_001, RSTstFileUnreadable,
      [AFilename, LReason]);
    FHadError := True;
    Exit(False);
  end;
  FFilename := FStream.SourceFilename();
  FBytes := FStream.SourceBytes();
  Result := True;
end;

procedure TPCTestSpecScanner.DoError(const AStart: Int64; const AEnd: Int64;
  const ACode: string; const AMessage: string; const AArgs: array of const);
var
  LRange: TSourceRange;
begin
  FHadError := True;
  LRange.Clear();
  FStream.SourceText().FillRange(LRange, AStart, AEnd);
  FErrors.Add(LRange, esError, ACode, AMessage, AArgs);
end;

procedure TPCTestSpecScanner.DoErrorAt(const AToken: TPCSpecToken; const ACode: string;
  const AMessage: string; const AArgs: array of const);
begin
  DoError(AToken.StartOffset, AToken.EndOffset, ACode, AMessage, AArgs);
end;

function TPCTestSpecScanner.DoIsBlank(const AOffset: Int64): Boolean;
begin
  Result := (AOffset >= 0) and (AOffset < Length(FBytes)) and
    (FBytes[AOffset] in [9, 10, 13, 32]);
end;

function TPCTestSpecScanner.DoLineEnd(const AFrom: Int64; const ATo: Int64): Int64;
begin
  // The first CR or LF at or after AFrom, else ATo
  Result := AFrom;
  while (Result < ATo) and (not (FBytes[Result] in [10, 13])) do
    Inc(Result);
end;

function TPCTestSpecScanner.DoFindMarker(const AText: string; const AFrom: Int64;
  const ATo: Int64): Int64;
var
  LP: Int64;
  LI: Integer;
  LLength: Integer;
  LSame: Boolean;
begin
  // AText (ASCII) as a word of its own in [AFrom, ATo): a blank or the
  // range's edge on both sides; -1 = none
  LLength := AText.Length;
  LP := AFrom;
  while LP + LLength <= ATo do
  begin
    LSame := True;
    for LI := 0 to LLength - 1 do
    begin
      if FBytes[LP + LI] <> Ord(AText.Chars[LI]) then
      begin
        LSame := False;
        Break;
      end;
    end;
    if LSame and ((LP = AFrom) or DoIsBlank(LP - 1)) and
       ((LP + LLength = ATo) or DoIsBlank(LP + LLength)) then
      Exit(LP);
    Inc(LP);
  end;
  Result := -1;
end;

function TPCTestSpecScanner.DoDepthAt(const AOffset: Int64): Integer;
var
  LI: Integer;
  LToken: TPCToken;
begin
  // The conditional nesting before AOffset, from the lexer's directive
  // tokens (the filter's own rule, TPCConditionalFilter.NestingOf)
  Result := 0;
  for LI := 0 to FStream.Count() - 1 do
  begin
    LToken := FStream.TokenAt(LI);
    if Int64(LToken.Range.StartByteOffset) >= AOffset then
      Break;
    if LToken.Kind = tkDirective then
      Result := Result + TPCConditionalFilter.NestingOf(LToken.Spelling);
  end;
end;

function TPCTestSpecScanner.DoKeysText(): string;
begin
  Result := string.Join(', ', PC_TS_KEYS);
end;

function TPCTestSpecScanner.DoKindsText(): string;
var
  LKind: TPCTestKind;
begin
  Result := '';
  for LKind := skRun to PC_TS_LAST_SPEC_KIND do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + PC_TS_KIND_TEXT[LKind];
  end;
end;

function TPCTestSpecScanner.DoTargetsText(): string;
var
  LI: Integer;
begin
  Result := '';
  for LI := Low(PC_DATA_MODELS) to High(PC_DATA_MODELS) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + PC_DATA_MODELS[LI].Target;
  end;
end;

procedure TPCTestSpecScanner.DoCheckLineComment(const AComment: TPCCommentSpan);
var
  LAt: Int64;
begin
  // A spec lives in a block comment only: a marker in a // comment is
  // reported, never read
  LAt := DoFindMarker(PC_TS_SPEC_OPEN, AComment.StartOffset + 2, AComment.EndOffset);
  if LAt >= 0 then
    DoError(LAt, LAt + PC_TS_SPEC_OPEN.Length, PC_ERR_TS_002, RSTstMarkerInLineComment,
      [PC_TS_SPEC_OPEN]);
  LAt := DoFindMarker(PC_TS_SPEC_CLOSE, AComment.StartOffset + 2, AComment.EndOffset);
  if LAt >= 0 then
    DoError(LAt, LAt + PC_TS_SPEC_CLOSE.Length, PC_ERR_TS_002, RSTstMarkerInLineComment,
      [PC_TS_SPEC_CLOSE]);
end;

procedure TPCTestSpecScanner.DoCheckCppBlocks();
var
  LI: Integer;
  LToken: TPCToken;
  LAt: Int64;
begin
  // A cppstart block is C++ the lexer captures whole (its comments are not
  // comment spans): a spec there is reported, never read
  for LI := 0 to FStream.Count() - 1 do
  begin
    LToken := FStream.TokenAt(LI);
    if LToken.Kind <> tkRawBlock then
      Continue;
    LAt := DoFindMarker(PC_TS_SPEC_OPEN, Int64(LToken.Range.StartByteOffset),
      Int64(LToken.Range.EndByteOffset));
    if LAt >= 0 then
      DoError(LAt, LAt + PC_TS_SPEC_OPEN.Length, PC_ERR_TS_011, RSTstSpecInCppBlock, []);
  end;
end;

function TPCTestSpecScanner.DoReadQuoted(var AOffset: Int64; const ATo: Int64;
  out AToken: TPCSpecToken): Boolean;
var
  LBuffer: TBytes;
  LCount: Integer;
  LByte: Byte;
begin
  // AOffset at the opening quote; on return past the closing one. \" and
  // \\ are the only escapes; a line end before the close is unterminated
  AToken := Default(TPCSpecToken);
  AToken.Kind := spQuoted;
  AToken.StartOffset := AOffset;
  SetLength(LBuffer, ATo - AOffset);
  LCount := 0;
  Inc(AOffset);
  while True do
  begin
    if (AOffset >= ATo) or (FBytes[AOffset] in [10, 13]) then
    begin
      AToken.EndOffset := AOffset;
      DoErrorAt(AToken, PC_ERR_TS_009, RSTstUnterminated, []);
      Exit(False);
    end;
    LByte := FBytes[AOffset];
    if LByte = PC_TS_QUOTE then
    begin
      Inc(AOffset);
      Break;
    end;
    if LByte = PC_TS_BACKSLASH then
    begin
      if (AOffset + 1 < ATo) and (FBytes[AOffset + 1] in [PC_TS_QUOTE, PC_TS_BACKSLASH]) then
      begin
        LBuffer[LCount] := FBytes[AOffset + 1];
        Inc(LCount);
        Inc(AOffset, 2);
        Continue;
      end;
      AToken.EndOffset := AOffset + 1;
      DoError(AOffset, AOffset + 1, PC_ERR_TS_009, RSTstBadEscape, []);
      Exit(False);
    end;
    LBuffer[LCount] := LByte;
    Inc(LCount);
    Inc(AOffset);
  end;

  AToken.EndOffset := AOffset;
  AToken.Text := TEncoding.UTF8.GetString(LBuffer, 0, LCount);
  Result := True;
end;

function TPCTestSpecScanner.DoTokenize(const AFrom: Int64; const ATo: Int64;
  const ATokens: TList<TPCSpecToken>): Int64;
var
  LP: Int64;
  LStart: Int64;
  LEnd: Int64;
  LToken: TPCSpecToken;
begin
  // The spec's tokens from AFrom up to @@end; Result = the offset just past
  // @@end, -1 when the body ends first
  Result := -1;
  LP := AFrom;
  while LP < ATo do
  begin
    if DoIsBlank(LP) then
    begin
      Inc(LP);
      Continue;
    end;

    // -- note: to the end of its line
    if (LP + 1 < ATo) and (FBytes[LP] = Ord(PC_TS_NOTE.Chars[0])) and
       (FBytes[LP + 1] = Ord(PC_TS_NOTE.Chars[1])) then
    begin
      LP := DoLineEnd(LP, ATo);
      Continue;
    end;

    // "quoted"
    if FBytes[LP] = PC_TS_QUOTE then
    begin
      if DoReadQuoted(LP, ATo, LToken) then
        ATokens.Add(LToken)
      else
      begin
        // Reported already: kept as a bad value its key passes over, so
        // the key does not report it missing a second time
        LToken.Kind := spBad;
        ATokens.Add(LToken);
        LP := DoLineEnd(LP, ATo);
      end;
      Continue;
    end;

    // | output line: one blank after the bar dropped, trailing blanks dropped
    if FBytes[LP] = PC_TS_LINE_BAR then
    begin
      LEnd := DoLineEnd(LP, ATo);
      LToken := Default(TPCSpecToken);
      LToken.Kind := spLine;
      LToken.StartOffset := LP;
      LToken.EndOffset := LEnd;
      LStart := LP + 1;
      if (LStart < LEnd) and (FBytes[LStart] = 32) then
        Inc(LStart);
      LToken.Text := FStream.SourceText().Slice(LStart, LEnd).TrimRight();
      ATokens.Add(LToken);
      LP := LEnd;
      Continue;
    end;

    // A word: up to the next blank
    LStart := LP;
    while (LP < ATo) and (not DoIsBlank(LP)) do
      Inc(LP);
    LToken := Default(TPCSpecToken);
    LToken.Kind := spWord;
    LToken.StartOffset := LStart;
    LToken.EndOffset := LP;
    LToken.Text := FStream.SourceText().Slice(LStart, LP);
    if LToken.Text = PC_TS_SPEC_CLOSE then
      Exit(LP);
    if LToken.Text = PC_TS_SPEC_OPEN then
    begin
      DoErrorAt(LToken, PC_ERR_TS_003, RSTstSecondSpec,
        [FStream.SourceText().LineOf(FSpecStart)]);
      Continue;
    end;
    ATokens.Add(LToken);
  end;
end;

function TPCTestSpecScanner.DoReadSpec(const AAt: Int64; const ABodyEnd: Int64): Int64;
var
  LTokens: TList<TPCSpecToken>;
  LClose: Int64;
begin
  // AAt = the @@test marker; Result = where the spec ended (past @@end, or
  // the comment's end when it has none)
  FSpecStart := AAt;
  FSpec.SpecRange.Clear();
  FStream.SourceText().FillRange(FSpec.SpecRange, AAt, AAt + PC_TS_SPEC_OPEN.Length);
  if DoDepthAt(AAt) > 0 then
    DoError(AAt, AAt + PC_TS_SPEC_OPEN.Length, PC_ERR_TS_010, RSTstSpecInConditional, []);

  LTokens := TList<TPCSpecToken>.Create();
  try
    LClose := DoTokenize(AAt + PC_TS_SPEC_OPEN.Length, ABodyEnd, LTokens);
    if LClose < 0 then
    begin
      DoError(AAt, AAt + PC_TS_SPEC_OPEN.Length, PC_ERR_TS_004, RSTstNoSpecEnd,
        [PC_TS_SPEC_CLOSE]);
      Result := ABodyEnd;
    end
    else
      Result := LClose;
    DoParse(LTokens);
  finally
    LTokens.Free();
  end;
end;

function TPCTestSpecScanner.DoIsValueWord(const ATokens: TList<TPCSpecToken>;
  const AIndex: Integer): Boolean;
var
  LKey: string;
begin
  // A word that is not a key: a key word always starts the next entry
  Result := False;
  if (AIndex >= ATokens.Count) or (ATokens[AIndex].Kind <> spWord) then
    Exit;
  for LKey in PC_TS_KEYS do
  begin
    if ATokens[AIndex].Text = LKey then
      Exit;
  end;
  Result := True;
end;

function TPCTestSpecScanner.DoIsValue(const ATokens: TList<TPCSpecToken>;
  const AIndex: Integer): Boolean;
begin
  // Anything a key can take as its value: a quoted value (a bad one too)
  // or a word that is not a key. A key, an output line or the end is not
  Result := (AIndex < ATokens.Count) and
    ((ATokens[AIndex].Kind in [spQuoted, spBad]) or DoIsValueWord(ATokens, AIndex));
end;

function TPCTestSpecScanner.DoKeyGiven(const AKey: string): Boolean;
var
  LUse: TPCSpecKeyUse;
begin
  for LUse in FKeyUses do
  begin
    if LUse.Key = AKey then
      Exit(True);
  end;
  Result := False;
end;

procedure TPCTestSpecScanner.DoParse(const ATokens: TList<TPCSpecToken>);
var
  LI: Integer;
  LToken: TPCSpecToken;
begin
  LI := 0;
  while LI < ATokens.Count do
  begin
    LToken := ATokens[LI];
    Inc(LI);
    if LToken.Kind = spLine then
    begin
      DoErrorAt(LToken, PC_ERR_TS_014, RSTstLineOutsideExpect, []);
      Continue;
    end;
    // A bad value is reported where it was read
    if LToken.Kind = spBad then
      Continue;
    // Where a key goes, anything that is not one is an unknown key. It
    // takes the values and output lines after it, up to the next key: one
    // report for the mistake, not one per word
    if (LToken.Kind <> spWord) or DoIsValueWord(ATokens, LI - 1) then
    begin
      DoErrorAt(LToken, PC_ERR_TS_005, RSTstUnknownKey, [LToken.Text, DoKeysText()]);
      while (LI < ATokens.Count) and (DoIsValue(ATokens, LI) or (ATokens[LI].Kind = spLine)) do
        Inc(LI);
      Continue;
    end;
    DoParseKey(LToken, ATokens, LI);
  end;
end;

procedure TPCTestSpecScanner.DoUseKey(const AKey: TPCSpecToken; const AUseId: string);
var
  LUse: TPCSpecKeyUse;
  LNew: TPCSpecKeyUse;
begin
  for LUse in FKeyUses do
  begin
    if LUse.UseId = AUseId then
    begin
      DoErrorAt(AKey, PC_ERR_TS_006, RSTstDuplicateKey, [AKey.Text]);
      Exit;
    end;
  end;
  LNew.Key := AKey.Text;
  LNew.UseId := AUseId;
  LNew.StartOffset := AKey.StartOffset;
  LNew.EndOffset := AKey.EndOffset;
  FKeyUses.Add(LNew);
end;

function TPCTestSpecScanner.DoTakeValue(const AKey: TPCSpecToken;
  const ATokens: TList<TPCSpecToken>; var AIndex: Integer; const AKinds: TPCSpecTokenKinds;
  const AWant: string; out AValue: TPCSpecToken): Boolean;
var
  LWant: string;
begin
  AValue := Default(TPCSpecToken);
  Result := False;

  // No value at all: the next token is a key, an output line or the end
  if not DoIsValue(ATokens, AIndex) then
  begin
    DoErrorAt(AKey, PC_ERR_TS_008, RSTstMissingValue, [AKey.Text, AWant]);
    Exit;
  end;

  // A value is taken whatever its form, so it is never read again as a key:
  // a bad one is reported already, one of the wrong form is reported here
  AValue := ATokens[AIndex];
  Inc(AIndex);
  if AValue.Kind = spBad then
    Exit;
  if not (AValue.Kind in AKinds) then
  begin
    LWant := AWant;
    if AValue.Kind = spQuoted then
      LWant := RSTstValueBareWord;
    DoErrorAt(AValue, PC_ERR_TS_007, RSTstBadValue, [AKey.Text, AValue.Text, LWant]);
    Exit;
  end;
  Result := True;
end;

function TPCTestSpecScanner.DoTakeWords(const AKey: TPCSpecToken;
  const ATokens: TList<TPCSpecToken>; var AIndex: Integer;
  out AWords: TArray<TPCSpecToken>): Boolean;
var
  LToken: TPCSpecToken;
  LGiven: Boolean;
begin
  // Every value up to the next key: bare words are the list, a quoted one
  // is reported at itself, a bad one is reported already
  AWords := [];
  LGiven := False;
  while DoIsValue(ATokens, AIndex) do
  begin
    LGiven := True;
    LToken := ATokens[AIndex];
    Inc(AIndex);
    if LToken.Kind = spWord then
      AWords := AWords + [LToken]
    else if LToken.Kind = spQuoted then
      DoErrorAt(LToken, PC_ERR_TS_007, RSTstBadValue, [AKey.Text, LToken.Text, RSTstValueBareWord]);
  end;
  if not LGiven then
    DoErrorAt(AKey, PC_ERR_TS_008, RSTstMissingValue, [AKey.Text, RSTstValueList]);
  Result := Length(AWords) > 0;
end;

procedure TPCTestSpecScanner.DoParseKind(const AKey: TPCSpecToken;
  const ATokens: TList<TPCSpecToken>; var AIndex: Integer);
var
  LValue: TPCSpecToken;
  LKind: TPCTestKind;
begin
  DoUseKey(AKey, AKey.Text);
  if not DoTakeValue(AKey, ATokens, AIndex, [spWord], Format(RSTstValueOneOf, [DoKindsText()]),
    LValue) then
    Exit;
  for LKind := skRun to PC_TS_LAST_SPEC_KIND do
  begin
    if PC_TS_KIND_TEXT[LKind] = LValue.Text then
    begin
      FSpec.Kind := LKind;
      FHasKind := True;
      Exit;
    end;
  end;
  DoErrorAt(LValue, PC_ERR_TS_007, RSTstBadValue, [AKey.Text, LValue.Text,
    Format(RSTstValueOneOf, [DoKindsText()])]);
end;

procedure TPCTestSpecScanner.DoParseList(const AKey: TPCSpecToken;
  const ATokens: TList<TPCSpecToken>; var AIndex: Integer);
var
  LWords: TArray<TPCSpecToken>;
  LWord: TPCSpecToken;
  LSeen: TList<string>;
  LOpt: TPCOptimizeLevel;
  LSubsystem: TPCSubsystemType;
  LName: string;
  LValue: string;
begin
  // deps targets opt subsystem define: one or more words, each checked,
  // none twice
  DoUseKey(AKey, AKey.Text);
  if not DoTakeWords(AKey, ATokens, AIndex, LWords) then
    Exit;

  LSeen := TList<string>.Create();
  try
    for LWord in LWords do
    begin
      if LSeen.Contains(LWord.Text) then
      begin
        DoErrorAt(LWord, PC_ERR_TS_007, RSTstBadValue, [AKey.Text, LWord.Text, RSTstValueTwice]);
        Continue;
      end;
      LSeen.Add(LWord.Text);

      if AKey.Text = PC_TS_KEY_DEPS then
        FSpec.Deps := FSpec.Deps + [LWord.Text]
      else if AKey.Text = PC_TS_KEY_TARGETS then
      begin
        if IsTarget(LWord.Text) then
          FSpec.Targets := FSpec.Targets + [LWord.Text]
        else
          DoErrorAt(LWord, PC_ERR_TS_007, RSTstBadValue, [AKey.Text, LWord.Text,
            Format(RSTstValueOneOf, [DoTargetsText()])]);
      end
      else if AKey.Text = PC_TS_KEY_OPT then
      begin
        if TPCCompiler.FindOptimizeLevel(LWord.Text, LOpt) then
          FSpec.OptLevels := FSpec.OptLevels + [LOpt]
        else
          DoErrorAt(LWord, PC_ERR_TS_007, RSTstBadValue, [AKey.Text, LWord.Text,
            Format(RSTstValueOneOf, [string.Join(', ', PC_CMP_OPTIMIZE_TEXT)])]);
      end
      else if AKey.Text = PC_TS_KEY_SUBSYSTEM then
      begin
        if TPCCompiler.FindSubsystem(LWord.Text, LSubsystem) then
          FSpec.Subsystems := FSpec.Subsystems + [LSubsystem]
        else
          DoErrorAt(LWord, PC_ERR_TS_007, RSTstBadValue, [AKey.Text, LWord.Text,
            Format(RSTstValueOneOf, [string.Join(', ', PC_CMP_SUBSYSTEM_TEXT)])]);
      end
      else if AKey.Text = PC_TS_KEY_DEFINE then
      begin
        // NAME or NAME=VALUE; NAME an identifier
        LName := LWord.Text;
        LValue := '';
        if LName.Contains('=') then
        begin
          LValue := LName.Substring(LName.IndexOf('=') + 1);
          LName := LName.Substring(0, LName.IndexOf('='));
        end;
        if IsValidIdent(LName) and (not LValue.Contains('=')) then
          FSpec.Defines := FSpec.Defines + [LWord.Text]
        else
          DoErrorAt(LWord, PC_ERR_TS_007, RSTstBadValue, [AKey.Text, LWord.Text, RSTstValueDefine]);
      end;
    end;
  finally
    LSeen.Free();
  end;
end;

procedure TPCTestSpecScanner.DoParseExpect(const AKey: TPCSpecToken;
  const ATokens: TList<TPCSpecToken>; var AIndex: Integer);
var
  LExpect: TPCTestExpect;
  LLines: TArray<string>;
  LBadTarget: Boolean;
begin
  // expect [target] then its | lines
  LExpect := Default(TPCTestExpect);
  LBadTarget := False;
  if DoIsValueWord(ATokens, AIndex) and IsTarget(ATokens[AIndex].Text) then
  begin
    LExpect.Target := ATokens[AIndex].Text;
    Inc(AIndex);
  end
  else if DoIsValue(ATokens, AIndex) then
  begin
    // A value that is no target: reported at the value (a bad one is
    // already); the lines after it still belong to this expect
    LBadTarget := True;
    if ATokens[AIndex].Kind <> spBad then
      DoErrorAt(ATokens[AIndex], PC_ERR_TS_007, RSTstBadValue, [AKey.Text, ATokens[AIndex].Text,
        Format(RSTstValueOneOf, [DoTargetsText()])]);
    Inc(AIndex);
  end;
  DoUseKey(AKey, PC_TS_USE_EXPECT + LExpect.Target);

  LLines := [];
  while (AIndex < ATokens.Count) and (ATokens[AIndex].Kind = spLine) do
  begin
    LLines := LLines + [ATokens[AIndex].Text];
    Inc(AIndex);
  end;
  if LBadTarget then
    Exit;
  if Length(LLines) = 0 then
  begin
    DoErrorAt(AKey, PC_ERR_TS_008, RSTstMissingValue, [AKey.Text, RSTstValueLines]);
    Exit;
  end;
  LExpect.Text := string.Join(#10, LLines);
  FSpec.Expects := FSpec.Expects + [LExpect];
end;

procedure TPCTestSpecScanner.DoParseExpectFile(const AKey: TPCSpecToken;
  const ATokens: TList<TPCSpecToken>; var AIndex: Integer);
var
  LExpect: TPCTestExpect;
  LValue: TPCSpecToken;
begin
  // expectfile [target] path: a target word counts as the qualifier only
  // when a path still follows it
  LExpect := Default(TPCTestExpect);
  LExpect.IsFile := True;
  if DoIsValueWord(ATokens, AIndex) and IsTarget(ATokens[AIndex].Text) and
     DoIsValue(ATokens, AIndex + 1) then
  begin
    LExpect.Target := ATokens[AIndex].Text;
    Inc(AIndex);
  end;
  DoUseKey(AKey, PC_TS_USE_EXPECT + LExpect.Target);
  if not DoTakeValue(AKey, ATokens, AIndex, [spWord, spQuoted], RSTstValuePath, LValue) then
    Exit;
  if not DoResolveBeside(LValue, PC_ERR_TS_015, RSTstExpectFileMissing, LExpect.FilePath) then
    Exit;
  FSpec.Expects := FSpec.Expects + [LExpect];
end;

procedure TPCTestSpecScanner.DoParseStdin(const AKey: TPCSpecToken;
  const ATokens: TList<TPCSpecToken>; var AIndex: Integer);
var
  LValue: TPCSpecToken;
  LPath: string;
begin
  // stdin path: the file the program reads as its standard input
  DoUseKey(AKey, AKey.Text);
  if not DoTakeValue(AKey, ATokens, AIndex, [spWord, spQuoted], RSTstValuePath, LValue) then
    Exit;
  if DoResolveBeside(LValue, PC_ERR_TS_017, RSTstStdinMissing, LPath) then
    FSpec.Stdin := LPath;
end;

function TPCTestSpecScanner.DoResolveBeside(const AValue: TPCSpecToken; const ACode: string;
  const AMessage: string; out APath: string): Boolean;
begin
  // The base is the test file's folder (the suite's one folder rule,
  // PCTestFolderOf, shared with <DIR> and a program's run folder)
  APath := '';
  try
    APath := TUtils.ResolvePath(AValue.Text, PCTestFolderOf(FFilename));
  except
    on E: Exception do
    begin
      DoErrorAt(AValue, ACode, AMessage, [AValue.Text + ' (' + E.Message + ')']);
      Exit(False);
    end;
  end;
  if not FileExists(APath) then
  begin
    DoErrorAt(AValue, ACode, AMessage, [APath]);
    Exit(False);
  end;
  Result := True;
end;

procedure TPCTestSpecScanner.DoParseKey(const AKey: TPCSpecToken;
  const ATokens: TList<TPCSpecToken>; var AIndex: Integer);
var
  LValue: TPCSpecToken;
  LCode: Integer;
begin
  if AKey.Text = PC_TS_KEY_KIND then
    DoParseKind(AKey, ATokens, AIndex)
  else if (AKey.Text = PC_TS_KEY_DEPS) or (AKey.Text = PC_TS_KEY_TARGETS) or
          (AKey.Text = PC_TS_KEY_OPT) or (AKey.Text = PC_TS_KEY_SUBSYSTEM) or
          (AKey.Text = PC_TS_KEY_DEFINE) then
    DoParseList(AKey, ATokens, AIndex)
  else if AKey.Text = PC_TS_KEY_ARGS then
  begin
    DoUseKey(AKey, AKey.Text);
    if DoTakeValue(AKey, ATokens, AIndex, [spQuoted], RSTstValueQuoted, LValue) then
      FSpec.Args := LValue.Text;
  end
  else if AKey.Text = PC_TS_KEY_EXITCODE then
  begin
    DoUseKey(AKey, AKey.Text);
    if not DoTakeValue(AKey, ATokens, AIndex, [spWord], RSTstValueInteger, LValue) then
      Exit;
    if TryStrToInt(LValue.Text, LCode) and (LCode >= 0) then
      FSpec.ExitCode := LCode
    else
      DoErrorAt(LValue, PC_ERR_TS_007, RSTstBadValue, [AKey.Text, LValue.Text, RSTstValueInteger]);
  end
  else if AKey.Text = PC_TS_KEY_WARNINGS then
  begin
    DoUseKey(AKey, AKey.Text);
    if not DoTakeValue(AKey, ATokens, AIndex, [spWord],
      Format(RSTstValueOneOf, [PC_TS_WARNINGS_ALLOW]), LValue) then
      Exit;
    if LValue.Text = PC_TS_WARNINGS_ALLOW then
      FSpec.AllowWarnings := True
    else
      DoErrorAt(LValue, PC_ERR_TS_007, RSTstBadValue, [AKey.Text, LValue.Text,
        Format(RSTstValueOneOf, [PC_TS_WARNINGS_ALLOW])]);
  end
  else if AKey.Text = PC_TS_KEY_EXPECT then
    DoParseExpect(AKey, ATokens, AIndex)
  else if AKey.Text = PC_TS_KEY_EXPECTFILE then
    DoParseExpectFile(AKey, ATokens, AIndex)
  else if AKey.Text = PC_TS_KEY_STDIN then
    DoParseStdin(AKey, ATokens, AIndex);
end;

procedure TPCTestSpecScanner.DoFinish();
var
  LUse: TPCSpecKeyUse;
  LApplies: Boolean;
begin
  if not FHasKind then
  begin
    // A kind given with a bad value is reported at that value already
    if not DoKeyGiven(PC_TS_KEY_KIND) then
      DoError(FSpecStart, FSpecStart + PC_TS_SPEC_OPEN.Length, PC_ERR_TS_012, RSTstNoKind,
        [DoKindsText()]);
  end
  else
  begin
    // args belong to what runs; stdin to a program the suite builds;
    // exitcode and expected output to what is compared by its output. A
    // cli test is pcpp run on this machine: its own arguments say what is
    // built where, so it takes no cell, dependency or define keys
    for LUse in FKeyUses do
    begin
      if LUse.Key = PC_TS_KEY_ARGS then
        LApplies := FSpec.Kind in [skRun, skTests, skCli]
      else if LUse.Key = PC_TS_KEY_STDIN then
        LApplies := FSpec.Kind in [skRun, skTests]
      else if (LUse.Key = PC_TS_KEY_EXITCODE) or (LUse.Key = PC_TS_KEY_EXPECT) or
              (LUse.Key = PC_TS_KEY_EXPECTFILE) then
        LApplies := FSpec.Kind in [skRun, skCli]
      else if (LUse.Key = PC_TS_KEY_DEPS) or (LUse.Key = PC_TS_KEY_TARGETS) or
              (LUse.Key = PC_TS_KEY_OPT) or (LUse.Key = PC_TS_KEY_SUBSYSTEM) or
              (LUse.Key = PC_TS_KEY_DEFINE) or (LUse.Key = PC_TS_KEY_WARNINGS) then
        LApplies := FSpec.Kind <> skCli
      else
        LApplies := True;
      if not LApplies then
        DoError(LUse.StartOffset, LUse.EndOffset, PC_ERR_TS_013, RSTstKeyNotForKind,
          [LUse.Key, PC_TS_KIND_TEXT[FSpec.Kind]]);
    end;
  end;

  // Defaults: both official targets, debug, console. A cli test has one
  // cell, this machine's: pcpp runs once, as a user runs it
  if FHasKind and (FSpec.Kind = skCli) then
  begin
    FSpec.Targets := [PC_TARGET_X86_64_WINDOWS_GNU];
    FSpec.OptLevels := [olDebug];
    FSpec.Subsystems := [stConsole];
  end;
  if Length(FSpec.Targets) = 0 then
    FSpec.Targets := [PC_TARGET_X86_64_WINDOWS_GNU, PC_TARGET_X86_64_LINUX_GNU];
  if Length(FSpec.OptLevels) = 0 then
  begin
    FSpec.OptLevels := [olDebug];
    FSpec.OptDefault := True;
  end;
  if Length(FSpec.Subsystems) = 0 then
    FSpec.Subsystems := [stConsole];
end;

function TPCTestSpecScanner.Scan(const AFilename: string; out ASpec: TPCTestSpec;
  out AHasSpec: Boolean): Boolean;
var
  LComments: TArray<TPCCommentSpan>;
  LComment: TPCCommentSpan;
  LBodyStart: Int64;
  LBodyEnd: Int64;
  LAt: Int64;
begin
  ASpec := Default(TPCTestSpec);
  AHasSpec := False;
  FHadError := False;
  FSpec := Default(TPCTestSpec);
  FHasKind := False;
  FSpecStart := 0;
  FKeyUses.Clear();

  if not DoLex(AFilename) then
    Exit(False);
  FSpec.Filename := FFilename;
  FSpec.Stem := TPath.GetFileNameWithoutExtension(FFilename);

  LComments := FStream.CommentsIn(0, Length(FBytes) + 1);
  for LComment in LComments do
  begin
    if LComment.IsLine then
    begin
      DoCheckLineComment(LComment);
      Continue;
    end;

    // The body: after /*, before */ when the comment is closed
    LBodyStart := LComment.StartOffset + 2;
    LBodyEnd := LComment.EndOffset;
    if (LBodyEnd - LBodyStart >= 2) and (FBytes[LBodyEnd - 2] = Ord('*')) and
       (FBytes[LBodyEnd - 1] = Ord('/')) then
      Dec(LBodyEnd, 2);

    LAt := DoFindMarker(PC_TS_SPEC_OPEN, LBodyStart, LBodyEnd);
    while LAt >= 0 do
    begin
      if AHasSpec then
      begin
        DoError(LAt, LAt + PC_TS_SPEC_OPEN.Length, PC_ERR_TS_003, RSTstSecondSpec,
          [FStream.SourceText().LineOf(FSpecStart)]);
        LAt := LAt + PC_TS_SPEC_OPEN.Length;
      end
      else
      begin
        AHasSpec := True;
        LAt := DoReadSpec(LAt, LBodyEnd);
      end;
      LAt := DoFindMarker(PC_TS_SPEC_OPEN, LAt, LBodyEnd);
    end;
  end;

  DoCheckCppBlocks();
  if AHasSpec then
    DoFinish();
  ASpec := FSpec;
  Result := not FHadError;
end;

function TPCTestSpecScanner.ScanExample(const AFilename: string;
  out ASpec: TPCTestSpec): Boolean;
var
  LHasSpec: Boolean;
begin
  Result := Scan(AFilename, ASpec, LHasSpec);
  if (not Result) or LHasSpec then
    Exit;

  // No spec: the example must build, clean, in the default cells. The
  // file's state from Scan is still loaded, so DoFinish applies the same
  // defaults a written "kind build" spec gets
  FSpec.Kind := skBuild;
  FHasKind := True;
  FSpec.SpecRange.Clear();
  FStream.SourceText().FillRange(FSpec.SpecRange, 0, 0);
  DoFinish();
  ASpec := FSpec;
  Result := not FHadError;
end;

function TPCTestSpecScanner.DoMarkersOf(const AStart: Int64; const AEnd: Int64;
  var AMarkers: TArray<TPCTestMarker>): Boolean;
var
  LPieces: TArray<string>;
  LPiece: string;
  LLine: Integer;
  LIsMarker: Boolean;
  LMarker: TPCTestMarker;
begin
  // [AStart, AEnd) = one // comment: one marker per //, up to the next //
  Result := True;
  LLine := FStream.SourceText().LineOf(AStart);
  LPieces := FStream.SourceText().Slice(AStart + 2, AEnd).Split([PC_TS_LINE_COMMENT]);
  for LPiece in LPieces do
  begin
    if not TPCTestMarker.Parse(LPiece.Trim(), LIsMarker, LMarker) then
    begin
      DoError(AStart, AEnd, PC_ERR_TS_016, RSTstBadMarker, [LPiece.Trim()]);
      Result := False;
      Continue;
    end;
    if LIsMarker then
    begin
      LMarker.Filename := FFilename;
      LMarker.Line := LLine;
      AMarkers := AMarkers + [LMarker];
    end;
  end;
end;

function TPCTestSpecScanner.DoBlockCommentMarkers(const AStart: Int64; const AEnd: Int64;
  var AMarkers: TArray<TPCTestMarker>): Boolean;
var
  LTextEnd: Int64;
  LP: Int64;
  LLine: Integer;
  LPieceStart: Int64;
  LPieceEnd: Int64;
  LLineEnd: Int64;
  LPiece: string;
  LIsMarker: Boolean;
  LMarker: TPCTestMarker;
begin
  Result := True;

  // The comment's text: between /* and */ (an unterminated comment, or one
  // whose closer is spliced, keeps its last bytes; they are prose)
  LTextEnd := AEnd;
  if (AEnd - AStart >= 4) and (FBytes[AEnd - 2] = Ord('*')) and (FBytes[AEnd - 1] = Ord('/')) then
    LTextEnd := AEnd - 2;
  LP := AStart + 2;
  while (LP < LTextEnd) and DoIsBlank(LP) do
    Inc(LP);

  // Only a comment whose text begins with // holds markers: prose that only
  // shows a marker (a header's `// ERROR` example) is never read
  if not ((LP + 1 < LTextEnd) and (FBytes[LP] = Ord('/')) and (FBytes[LP + 1] = Ord('/'))) then
    Exit;

  while True do
  begin
    // LP stands on a //: its piece runs to the next // on the same line, else
    // to the line end (or the text end)
    LLine := FStream.SourceText().LineOf(LP);
    LPieceStart := LP + 2;
    LLineEnd := DoLineEnd(LPieceStart, LTextEnd);
    LPieceEnd := LPieceStart;
    while (LPieceEnd + 1 < LLineEnd) and
      (not ((FBytes[LPieceEnd] = Ord('/')) and (FBytes[LPieceEnd + 1] = Ord('/')))) do
      Inc(LPieceEnd);
    if LPieceEnd + 1 >= LLineEnd then
      LPieceEnd := LLineEnd;

    LPiece := FStream.SourceText().Slice(LPieceStart, LPieceEnd).Trim();
    if not TPCTestMarker.Parse(LPiece, LIsMarker, LMarker) then
    begin
      DoError(AStart, AEnd, PC_ERR_TS_016, RSTstBadMarker, [LPiece]);
      Result := False;
    end
    else if LIsMarker then
    begin
      LMarker.Filename := FFilename;
      LMarker.Line := LLine;
      AMarkers := AMarkers + [LMarker];
    end;

    // The next piece: a // later on this line, else a later line of the
    // comment that begins with //; anything else ends the markers
    LP := LPieceEnd;
    if LP >= LLineEnd then
    begin
      while (LP < LTextEnd) and DoIsBlank(LP) do
        Inc(LP);
    end;
    if not ((LP + 1 < LTextEnd) and (FBytes[LP] = Ord('/')) and (FBytes[LP + 1] = Ord('/'))) then
      Break;
  end;
end;

function TPCTestSpecScanner.DoGapMarkers(const AFrom: Int64; const ATo: Int64;
  var AMarkers: TArray<TPCTestMarker>): Boolean;
var
  LP: Int64;
  LEnd: Int64;
  LLineStart: Int64;
  LCommentStart: Int64;
begin
  // [AFrom, ATo) holds no C++ element of a cppstart block: only blanks,
  // comments and # lines (which contribute no elements). Its // comments
  // that are not on a # line are read for markers, and its /* */ ones by
  // the block-comment rule (DoBlockCommentMarkers)
  Result := True;
  LP := AFrom;
  while LP + 1 < ATo do
  begin
    if (FBytes[LP] = Ord('/')) and (FBytes[LP + 1] = Ord('*')) then
    begin
      LCommentStart := LP;
      LP := LP + 2;
      while (LP + 1 < ATo) and not ((FBytes[LP] = Ord('*')) and (FBytes[LP + 1] = Ord('/'))) do
        Inc(LP);
      LP := LP + 2;
      // An unclosed comment runs to the gap's end
      if LP > ATo then
        LEnd := ATo
      else
        LEnd := LP;
      if not DoBlockCommentMarkers(LCommentStart, LEnd, AMarkers) then
        Result := False;
      Continue;
    end;
    if (FBytes[LP] = Ord('/')) and (FBytes[LP + 1] = Ord('/')) then
    begin
      LEnd := DoLineEnd(LP, ATo);
      // A # line's text (an #include path) is not a comment
      LLineStart := LP;
      while (LLineStart > 0) and (not (FBytes[LLineStart - 1] in [10, 13])) do
        Dec(LLineStart);
      while (LLineStart < LP) and (FBytes[LLineStart] in [9, 32]) do
        Inc(LLineStart);
      if FBytes[LLineStart] <> Ord('#') then
      begin
        if not DoMarkersOf(LP, LEnd, AMarkers) then
          Result := False;
      end;
      LP := LEnd;
      Continue;
    end;
    Inc(LP);
  end;
end;

function TPCTestSpecScanner.DoBlockMarkers(const AToken: TPCToken;
  var AMarkers: TArray<TPCTestMarker>): Boolean;
var
  LElements: TArray<TPCCppElement>;
  LFrom: Int64;
  LElement: TPCCppElement;
begin
  // The gaps between the block's C++ elements (the lexer's capture)
  Result := True;
  LElements := FStream.CppElementsIn(Int64(AToken.Range.StartByteOffset),
    Int64(AToken.Range.EndByteOffset));
  LFrom := Int64(AToken.Range.StartByteOffset);
  for LElement in LElements do
  begin
    if not DoGapMarkers(LFrom, Int64(LElement.Range.StartByteOffset), AMarkers) then
      Result := False;
    LFrom := Int64(LElement.Range.EndByteOffset);
  end;
  if not DoGapMarkers(LFrom, Int64(AToken.Range.EndByteOffset), AMarkers) then
    Result := False;
end;

function TPCTestSpecScanner.ScanMarkers(const AFilename: string;
  var AMarkers: TArray<TPCTestMarker>): Boolean;
var
  LComment: TPCCommentSpan;
  LI: Integer;
  LToken: TPCToken;
begin
  FHadError := False;
  if not DoLex(AFilename) then
    Exit(False);

  Result := True;
  for LComment in FStream.CommentsIn(0, Length(FBytes) + 1) do
  begin
    if LComment.IsLine then
    begin
      if not DoMarkersOf(LComment.StartOffset, LComment.EndOffset, AMarkers) then
        Result := False;
    end
    else if not DoBlockCommentMarkers(LComment.StartOffset, LComment.EndOffset, AMarkers) then
      Result := False;
  end;
  for LI := 0 to FStream.Count() - 1 do
  begin
    LToken := FStream.TokenAt(LI);
    if (LToken.Kind = tkRawBlock) and (not DoBlockMarkers(LToken, AMarkers)) then
      Result := False;
    if (LToken.Kind = tkUnknown) and (not DoOpenSpanMarkers(LToken, AMarkers)) then
      Result := False;
    if (LToken.Kind = tkCppPreprocessor) and (not DoPreprocMarkers(LToken, AMarkers)) then
      Result := False;
  end;
end;

function TPCTestSpecScanner.DoPreprocMarkers(const AToken: TPCToken;
  var AMarkers: TArray<TPCTestMarker>): Boolean;
var
  LP: Int64;
  LEnd: Int64;
  LQuote: Byte;
  LCommentStart: Int64;
  LCommentEnd: Int64;
begin
  Result := True;
  LP := Int64(AToken.Range.StartByteOffset);
  LEnd := Int64(AToken.Range.EndByteOffset);
  while LP + 1 < LEnd do
  begin
    // A quote runs to its closing quote (a backslash escapes the byte after
    // it) or, unclosed, to its line's end
    if FBytes[LP] in [Ord('"'), Ord('''')] then
    begin
      LQuote := FBytes[LP];
      Inc(LP);
      while (LP < LEnd) and (FBytes[LP] <> LQuote) and (not (FBytes[LP] in [10, 13])) do
      begin
        if (FBytes[LP] = Ord('\')) and (LP + 1 < LEnd) then
          Inc(LP);
        Inc(LP);
      end;
      Inc(LP);
      Continue;
    end;
    if (FBytes[LP] = Ord('/')) and (FBytes[LP + 1] = Ord('*')) then
    begin
      LCommentStart := LP;
      LP := LP + 2;
      while (LP + 1 < LEnd) and not ((FBytes[LP] = Ord('*')) and (FBytes[LP + 1] = Ord('/'))) do
        Inc(LP);
      LP := LP + 2;
      // An unclosed comment runs to the # line's end
      if LP > LEnd then
        LCommentEnd := LEnd
      else
        LCommentEnd := LP;
      if not DoBlockCommentMarkers(LCommentStart, LCommentEnd, AMarkers) then
        Result := False;
      Continue;
    end;
    Inc(LP);
  end;
end;

function TPCTestSpecScanner.DoOpenSpanMarkers(const AToken: TPCToken;
  var AMarkers: TArray<TPCTestMarker>): Boolean;
var
  LStart: Int64;
  LLineEnd: Int64;
  LP: Int64;
begin
  // What the lexer could not close (a block comment, a string, a raw
  // string) is no comment span: it reports it and keeps it as one tkUnknown
  // span (the rest of the line, or of the file). A marker written on that
  // line is inside the span: its first line is read like a // comment, from
  // the first // to the line's end
  Result := True;
  LStart := Int64(AToken.Range.StartByteOffset);
  LLineEnd := DoLineEnd(LStart, Int64(AToken.Range.EndByteOffset));
  LP := LStart;
  while (LP + 1 < LLineEnd) and (not ((FBytes[LP] = Ord('/')) and (FBytes[LP + 1] = Ord('/')))) do
    Inc(LP);
  if LP + 1 < LLineEnd then
    Result := DoMarkersOf(LP, LLineEnd, AMarkers);
end;

end.
