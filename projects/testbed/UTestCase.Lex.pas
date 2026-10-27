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
  UTestCase.Lex - lexer reports whose input no .pcpp test can be

  TPCTestCase suite for the lex area. utf8_invalid: a source that is not
  well-formed UTF-8 (RFC 3629) is refused whole, LX0011 at the first bad
  byte: TokenizeBytes gives False, the one report, and a stream that is EOF
  only. One row per form the lexer rejects: a lone continuation byte, the
  overlong leads C0 / C1, an overlong three-byte form (E0 under A0), a
  surrogate (ED over 9F), a code point above U+10FFFF (F4 over 8F), a lead
  F5, a bad second continuation byte, a sequence cut off at the end of the
  file, and a bad byte after a valid character (its column counts the
  character's two bytes). The negative: the same source with valid two-,
  three- and four-byte characters (U+10FFFF included) lexes with no report.
  A code test because a test file must be UTF-8 to be scanned for its spec
  (ref\testsuite.md; lex_identifiers_err_char names it); the bytes are
  built here, so no file holds them.

  Dependencies: PaskalCPP.TestSuite.CodeTest, PaskalCPP.Lexer,
    PaskalCPP.TokenStream, PaskalCPP.Common
===============================================================================}

unit UTestCase.Lex;

interface

uses
  System.SysUtils,
  PaskalCPP.TestSuite.Types,
  PaskalCPP.TestSuite.CodeTest;

type

  { TPCLexUtf8Case }
  // One source for utf8_invalid: line 2 is '// ' + the bytes of Hex, then
  // more source unless AtEnd (the bytes end the file); Column = the bad
  // byte's (UTF-8 byte) column on line 2, 0 = valid input
  TPCLexUtf8Case = record
    Title: string;
    Hex: string;
    AtEnd: Boolean;
    Column: Integer;
  end;

  { TPCLexTests }
  TPCLexTests = class(TPCTestCase)
  private
    function DoHexBytes(const AHex: string): TBytes;
    function DoSource(const ACase: TPCLexUtf8Case): TBytes;
    procedure DoCheckCase(const ACase: TPCLexUtf8Case);
    procedure DoTestUtf8Invalid(const ACell: TPCTestCell);
  public
    constructor Create(); override;
  end;

implementation

uses
  StdApp.Base,
  PaskalCPP.Common,
  PaskalCPP.TokenStream,
  PaskalCPP.Lexer;

const
  { PC_TEST_LEX_UTF8_HEAD }
  // Line 1 and the start of line 2: the bytes under test are at column 4
  PC_TEST_LEX_UTF8_HEAD = 'module exe lex_utf8_invalid;' + #10 + '// ';

  { PC_TEST_LEX_UTF8_TAIL }
  // The rest of the file after the bytes (a row with AtEnd has none)
  PC_TEST_LEX_UTF8_TAIL = ' tail' + #10 + 'begin' + #10 + 'end.' + #10;

  { PC_TEST_LEX_UTF8_CASES }
  PC_TEST_LEX_UTF8_CASES: array[0..10] of TPCLexUtf8Case = (
    (Title: 'lone continuation byte'; Hex: '80'; AtEnd: False; Column: 4),
    (Title: 'overlong lead C0'; Hex: 'C0AF'; AtEnd: False; Column: 4),
    (Title: 'overlong lead C1'; Hex: 'C1BF'; AtEnd: False; Column: 4),
    (Title: 'overlong three-byte form'; Hex: 'E080AF'; AtEnd: False; Column: 4),
    (Title: 'surrogate'; Hex: 'EDA080'; AtEnd: False; Column: 4),
    (Title: 'above U+10FFFF'; Hex: 'F4908080'; AtEnd: False; Column: 4),
    (Title: 'lead F5'; Hex: 'F5808080'; AtEnd: False; Column: 4),
    (Title: 'bad second continuation'; Hex: 'E228A1'; AtEnd: False; Column: 4),
    (Title: 'cut off at the end of the file'; Hex: 'E282'; AtEnd: True; Column: 4),
    (Title: 'after a valid character'; Hex: 'C3A980'; AtEnd: False; Column: 6),
    // The negative: e acute, the euro sign, an emoji, U+10FFFF
    (Title: 'valid multi-byte'; Hex: 'C3A9E282ACF09F9880F48FBFBF'; AtEnd: False; Column: 0)
  );

{ TPCLexTests }

constructor TPCLexTests.Create();
begin
  inherited;

  AreaName := 'lex';
  RegisterTest('utf8_invalid', DoTestUtf8Invalid);
end;

function TPCLexTests.DoHexBytes(const AHex: string): TBytes;
var
  LI: Integer;
begin
  // Two hex digits per byte, as the table writes them
  SetLength(Result, Length(AHex) div 2);
  for LI := 0 to High(Result) do
    Result[LI] := Byte(StrToInt('$' + Copy(AHex, LI * 2 + 1, 2)));
end;

function TPCLexTests.DoSource(const ACase: TPCLexUtf8Case): TBytes;
var
  LResult: TBytes;
begin
  LResult := TEncoding.UTF8.GetBytes(PC_TEST_LEX_UTF8_HEAD) + DoHexBytes(ACase.Hex);
  if not ACase.AtEnd then
    LResult := LResult + TEncoding.UTF8.GetBytes(PC_TEST_LEX_UTF8_TAIL);
  Result := LResult;
end;

procedure TPCLexTests.DoCheckCase(const ACase: TPCLexUtf8Case);
var
  LErrors: TErrors;
  LStream: TPCTokenStream;
  LLexer: TPCLexer;
  LLexed: Boolean;
begin
  LErrors := TErrors.Create();
  LStream := TPCTokenStream.Create();
  LLexer := TPCLexer.Create();
  try
    LStream.SetErrors(LErrors);
    LLexer.SetErrors(LErrors);
    LLexed := LLexer.TokenizeBytes(DoSource(ACase), 'lex_utf8_invalid.pcpp', LStream);

    if ACase.Column = 0 then
    begin
      CheckEqual(True, LLexed, ACase.Title + ': lexed');
      CheckErrors(LErrors, [], ACase.Title + ': no report');
      Check(LStream.Count() > 1, ACase.Title + ': tokens');
      Exit;
    end;

    // Refused whole: one LX0011 at the first bad byte, nothing but EOF
    CheckEqual(False, LLexed, ACase.Title + ': refused');
    CheckErrors(LErrors, [Format('2 ERROR LX0011@%d', [ACase.Column])], ACase.Title + ': LX0011');
    Check((LStream.Count() = 1) and (LStream.TokenAt(0).Kind = tkEOF), ACase.Title + ': EOF only');
  finally
    LLexer.Free();
    LStream.Free();
    LErrors.Free();
  end;
end;

procedure TPCLexTests.DoTestUtf8Invalid(const ACell: TPCTestCell);
var
  LCase: TPCLexUtf8Case;
begin
  for LCase in PC_TEST_LEX_UTF8_CASES do
  begin
    Section(LCase.Title);
    DoCheckCase(LCase);
  end;
end;

end.
