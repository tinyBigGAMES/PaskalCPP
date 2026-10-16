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
  UTestCase.SourceText - Source text atom tests

  TTestCase suite for TPCSourceText (PaskalCPP.SourceText): newline and
  splice lengths, logical bytes, UTF-8 lead lengths, splice-free spelling
  (raw-string exception), the line table and byte ranges. Inputs are
  literal text encoded to exact UTF-8 bytes (research\cppmix\
  lexer-splice-tests.md), or byte arrays where no text can hold the bytes.

  Dependencies: StdApp.TestCase, StdApp.Base, PaskalCPP.SourceText
===============================================================================}

unit UTestCase.SourceText;

interface

uses
  StdApp.TestCase;

type

  { TPCSourceTextTests }
  TPCSourceTextTests = class(TTestCase)
  private
    // One test per concern; Create registers each under its CLI name
    procedure DoTestNewlineLength();
    procedure DoTestSpliceLength();
    procedure DoTestLogical();
    procedure DoTestUtf8Length();
    procedure DoTestSpelling();
    procedure DoTestLineOf();
    procedure DoTestFillRange();
    procedure DoTestReinit();
    procedure DoTestUtf16Column();
    procedure DoTestErrorsDisplayRange();
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  StdApp.Base,
  PaskalCPP.SourceText;

function DoText(const AText: string): TPCSourceText;
begin
  // A source text over the exact UTF-8 bytes of AText
  Result := TPCSourceText.Create();
  Result.Init(TEncoding.UTF8.GetBytes(AText), 'mem.pcpp');
end;

function DoSpliceLengthOf(const AText: string; const AOffset: Int64): Int64;
var
  LText: TPCSourceText;
begin
  LText := DoText(AText);
  try
    Result := LText.SpliceLength(AOffset);
  finally
    LText.Free();
  end;
end;

function DoSpellingOf(const AText: string; const ARawQuoteAt: Int64): string;
var
  LText: TPCSourceText;
begin
  // The spelling of the whole text
  LText := DoText(AText);
  try
    Result := LText.Spelling(0, LText.ByteCount(), ARawQuoteAt);
  finally
    LText.Free();
  end;
end;

const
  { TEST_SRC_UTF8_CUT }
  // 'a', then a 4-byte lead with one continuation byte: cut by the end
  TEST_SRC_UTF8_CUT: array[0..2] of Byte = ($61, $F0, $9F);

  { TEST_SRC_UTF8_LAST }
  // 'a', then a 3-byte lead as the last byte
  TEST_SRC_UTF8_LAST: array[0..1] of Byte = ($61, $E2);

  { TEST_SRC_BOM_LINE }
  // UTF-8 BOM, then 'é' 'z': line 1 starts after the BOM
  TEST_SRC_BOM_LINE: array[0..5] of Byte = ($EF, $BB, $BF, $C3, $A9, $7A);

function DoSourceBytes(const ABytes: array of Byte): TPCSourceText;
var
  LBytes: TBytes;
  LIndex: Integer;
begin
  // A source text over exactly ABytes (sequences no string can hold)
  SetLength(LBytes, Length(ABytes));
  for LIndex := 0 to High(ABytes) do
    LBytes[LIndex] := ABytes[LIndex];
  Result := TPCSourceText.Create();
  Result.Init(LBytes, 'mem.pcpp');
end;

{ TPCSourceTextTests }

constructor TPCSourceTextTests.Create();
begin
  inherited;

  Title := 'SourceText';
  RegisterTest('newline_length', DoTestNewlineLength);
  RegisterTest('splice_length', DoTestSpliceLength);
  RegisterTest('logical', DoTestLogical);
  RegisterTest('utf8_length', DoTestUtf8Length);
  RegisterTest('spelling', DoTestSpelling);
  RegisterTest('line_of', DoTestLineOf);
  RegisterTest('fill_range', DoTestFillRange);
  RegisterTest('reinit', DoTestReinit);
  RegisterTest('utf16_column', DoTestUtf16Column);
  RegisterTest('errors_display_range', DoTestErrorsDisplayRange);
end;

procedure TPCSourceTextTests.Run();
begin
  inherited;
end;

procedure TPCSourceTextTests.DoTestNewlineLength();
var
  LText: TPCSourceText;
begin
  LText := DoText('a'#10'b'#13#10'c'#13'd'#13#13#10);
  try
    Check(LText.ByteCount() = 11, 'byte count 11');
    Check(LText.NewlineLength(0) = 0, 'a: no newline');
    Check(LText.NewlineLength(1) = 1, 'LF: 1');
    Check(LText.NewlineLength(3) = 2, 'CR LF: 2');
    Check(LText.NewlineLength(6) = 1, 'lone CR: 1');
    Check(LText.NewlineLength(8) = 1, 'CR before CR LF: 1');
    Check(LText.NewlineLength(9) = 2, 'CR LF after a CR: 2');
    Check(LText.NewlineLength(11) = 0, 'past EOF: 0');
    Check(LText.NewlineLength(-1) = 0, 'before start: 0');
  finally
    LText.Free();
  end;
end;

procedure TPCSourceTextTests.DoTestSpliceLength();
var
  LText: TPCSourceText;
begin
  Check(DoSpliceLengthOf('\'#10, 0) = 2, 'backslash LF: 2');
  Check(DoSpliceLengthOf('\'#13#10, 0) = 3, 'backslash CR LF: 3');
  Check(DoSpliceLengthOf('\'#13, 0) = 2, 'backslash lone CR: 2');
  Check(DoSpliceLengthOf('\'#32#9#10, 0) = 4, 'backslash space tab LF: 4');
  Check(DoSpliceLengthOf('\'#11#12#10, 0) = 4, 'backslash VT FF LF: 4');
  Check(DoSpliceLengthOf('\', 0) = 0, 'backslash at EOF: 0');
  Check(DoSpliceLengthOf('\'#32, 0) = 0, 'backslash space EOF: 0');
  Check(DoSpliceLengthOf('\x', 0) = 0, 'backslash x: 0');
  Check(DoSpliceLengthOf('\'#32'x', 0) = 0, 'backslash space x: 0');
  Check(DoSpliceLengthOf('a'#10, 0) = 0, 'no backslash: 0');

  // The newline offset tells a plain splice from a whitespace splice
  LText := DoText('\'#32#10'\'#10);
  try
    Check(LText.SpliceNewlineOffset(0) = 2, 'whitespace splice: newline at 2');
    Check(LText.SpliceNewlineOffset(3) = 4, 'plain splice: newline right after the backslash');
    Check(LText.SpliceNewlineOffset(1) = -1, 'space: no splice');
  finally
    LText.Free();
  end;
end;

procedure TPCSourceTextTests.DoTestLogical();
var
  LText: TPCSourceText;
begin
  LText := DoText('a\'#10'\'#10'b');
  try
    Check(LText.Logical(0) = 0, 'a is logical');
    Check(LText.Logical(1) = 5, 'two splices skipped: b at 5');
    Check(LText.NextLogical(0) = 5, 'after a comes b');
    Check(LText.Logical(5) = 5, 'b is logical');
    Check(LText.Logical(6) = 6, 'EOF stays EOF');
  finally
    LText.Free();
  end;

  LText := DoText('a\'#10);
  try
    Check(LText.Logical(1) = 3, 'trailing splice: logical EOF');
  finally
    LText.Free();
  end;
end;

procedure TPCSourceTextTests.DoTestUtf16Column();
var
  LText: TPCSourceText;
begin
  // Line 2 = a | C3 A9 | E2 82 AC | F0 9F 98 80 | b, then CR LF
  //   byte columns  a=1 e=2 euro=4 emoji=7 b=11 CR=12
  //   UTF-16        a=1 e=2 euro=3 emoji=4 b=6  CR=7 (the emoji is 2 units)
  LText := DoText('x'#10'a'#$00E9#$20AC#$D83D#$DE00'b'#13#10'c');
  try
    Check(LText.Utf16Column(1, 1) = 1, 'line 1 ASCII: 1');
    Check(LText.Utf16Column(1, 2) = 2, 'line 1 past its end: 2');
    Check(LText.Utf16Column(2, 1) = 1, 'a: 1');
    Check(LText.Utf16Column(2, 2) = 2, '2-byte e: 2');
    Check(LText.Utf16Column(2, 4) = 3, '3-byte euro: 3');
    Check(LText.Utf16Column(2, 7) = 4, '4-byte emoji: 4');
    Check(LText.Utf16Column(2, 11) = 6, 'b after the emoji (2 units): 6');
    Check(LText.Utf16Column(2, 12) = 7, 'at the CR: 7');
    Check(LText.Utf16Column(2, 14) = 9, 'past the line end: one unit per byte');
    Check(LText.Utf16Column(3, 1) = 1, 'line 3: 1');
    Check(LText.Utf16Column(9, 5) = 5, 'no such line: unchanged');
    Check(LText.Utf16Column(2, 0) = 0, 'column 0: unchanged');
  finally
    LText.Free();
  end;

  // The editor's case: the column after ')' is byte 47, Monaco's 41
  LText := DoText('  println("Hello, {}! '#$D83D#$DE80#$D83D#$DD25#$2728'", "CPaskal")');
  try
    Check(LText.Utf16Column(1, 47) = 41, 'emoji line: byte 47 -> 41');
  finally
    LText.Free();
  end;

  // A BOM is not on line 1: columns count from the first byte after it
  LText := DoSourceBytes(TEST_SRC_BOM_LINE);
  try
    Check(LText.Utf16Column(1, 1) = 1, 'BOM: e at 1');
    Check(LText.Utf16Column(1, 3) = 2, 'BOM: z at 2');
  finally
    LText.Free();
  end;
end;

procedure TPCSourceTextTests.DoTestErrorsDisplayRange();
var
  LErrors: TErrors;
  LRange: TSourceRange;
  LShown: TSourceRange;
begin
  LErrors := TErrors.Create();
  try
    LRange.Clear();
    LRange.Filename := 'f.pcpp';
    LRange.StartLine := 2;
    LRange.StartColumn := 7;
    LRange.EndLine := 3;
    LRange.EndColumn := 9;

    // No mapper: as stored
    LShown := LErrors.DisplayRange(LRange);
    Check((LShown.StartColumn = 7) and (LShown.EndColumn = 9), 'no mapper: stored columns');

    // A mapper maps both ends with their own line; the stored range is untouched
    LErrors.SetColumnMapper(
      function(const AFilename: string; const ALine: UInt64; const AColumn: UInt64): UInt64
      begin
        Result := AColumn * 10 + ALine;
      end);
    LShown := LErrors.DisplayRange(LRange);
    Check(LShown.StartColumn = 72, 'start mapped with line 2: 72');
    Check(LShown.EndColumn = 93, 'end mapped with line 3: 93');
    Check((LShown.StartLine = 2) and (LShown.Filename = 'f.pcpp'), 'line and file unchanged');
    Check(LRange.StartColumn = 7, 'stored range unchanged');

    // Column 0 = no column: stays 0
    LRange.StartColumn := 0;
    LShown := LErrors.DisplayRange(LRange);
    Check(LShown.StartColumn = 0, 'column 0 stays 0');

    LErrors.SetColumnMapper(nil);
  finally
    LErrors.Free();
  end;
end;

procedure TPCSourceTextTests.DoTestUtf8Length();
var
  LText: TPCSourceText;
begin
  // a | C3 A9 | E2 82 AC | F0 9F 98 80: leads at 0, 1, 3, 6; 10 bytes
  LText := DoText('a'#$00E9#$20AC#$D83D#$DE00);
  try
    Check(LText.ByteCount() = 10, 'byte count 10');
    Check(LText.Utf8Length(0) = 1, 'ASCII: 1');
    Check(LText.Utf8Length(1) = 2, '2-byte lead: 2');
    Check(LText.Utf8Length(2) = 1, 'continuation byte: 1');
    Check(LText.Utf8Length(3) = 3, '3-byte lead: 3');
    Check(LText.Utf8Length(6) = 4, '4-byte lead: 4');
    Check(LText.Utf8Length(10) = 0, 'past EOF: 0');
    Check(LText.Utf8Length(-1) = 0, 'before start: 0');
  finally
    LText.Free();
  end;

  // A sequence cut by the end of the bytes: the bytes that are there
  LText := DoSourceBytes(TEST_SRC_UTF8_CUT);
  try
    Check(LText.Utf8Length(1) = 2, 'cut 4-byte lead: 2');
  finally
    LText.Free();
  end;
  LText := DoSourceBytes(TEST_SRC_UTF8_LAST);
  try
    Check(LText.Utf8Length(1) = 1, '3-byte lead as the last byte: 1');
  finally
    LText.Free();
  end;
end;

procedure TPCSourceTextTests.DoTestSpelling();
var
  LText: TPCSourceText;
begin
  Check(DoSpellingOf('ab\'#10'cd', -1) = 'abcd', 'splice removed');
  Check(DoSpellingOf('a\'#10'\'#13#10'b', -1) = 'ab', 'double splice removed');
  Check(DoSpellingOf('a\'#9#10'b', -1) = 'ab', 'whitespace splice removed');
  Check(DoSpellingOf('xyz', -1) = 'xyz', 'no splice: unchanged');
  Check(DoSpellingOf(#$00E9'\'#10'x', -1) = #$00E9'x', 'UTF-8 sequence kept whole');
  Check(DoSpellingOf('R\'#10'"(a\'#10'b)"', 3) = 'R"(a\'#10'b)"',
    'raw: prefix spliced, body physical');
  Check(DoSpellingOf('R\'#10'"(a\'#10'b)"', -1) = 'R"(ab)"', 'not raw: all splices removed');

  LText := DoText('ab\'#10'cd');
  try
    Check(LText.Spelling(3, 3, -1) = '', 'empty range');
    Check(LText.Spelling(1, 5, -1) = 'bc', 'sub-range');
    Check(LText.Slice(0, 6) = 'ab\'#10'cd', 'Slice stays physical');
  finally
    LText.Free();
  end;
end;

procedure TPCSourceTextTests.DoTestLineOf();
var
  LText: TPCSourceText;
begin
  LText := DoText('a'#13'b'#13#10'c'#10'd');
  try
    Check(LText.LineCount() = 4, 'four lines');
    Check(LText.LineOf(0) = 1, 'a on line 1');
    Check(LText.LineOf(1) = 1, 'lone CR ends line 1');
    Check(LText.LineOf(2) = 2, 'b on line 2 (after lone CR)');
    Check(LText.LineOf(4) = 2, 'LF of CR LF on line 2');
    Check(LText.LineOf(5) = 3, 'c on line 3 (after CR LF)');
    Check(LText.LineOf(7) = 4, 'd on line 4');
  finally
    LText.Free();
  end;

  LText := DoText('a'#13#13#10'b');
  try
    Check(LText.LineOf(4) = 3, 'CR CR LF is two newlines');
  finally
    LText.Free();
  end;
end;

procedure TPCSourceTextTests.DoTestFillRange();
var
  LText: TPCSourceText;
  LRange: TSourceRange;
begin
  LText := DoText('a'#13'b'#13#10'c'#10'd');
  try
    LText.FillRange(LRange, 5, 6);
    Check(LRange.Filename = 'mem.pcpp', 'filename');
    Check((LRange.StartLine = 3) and (LRange.StartColumn = 1), 'c starts at 3:1');
    Check((LRange.EndLine = 3) and (LRange.EndColumn = 1), 'c ends at 3:1');
    Check((LRange.StartByteOffset = 5) and (LRange.EndByteOffset = 6), 'byte offsets');

    LText.FillRange(LRange, 2, 2);
    Check((LRange.StartLine = 2) and (LRange.StartColumn = 1) and
      (LRange.EndLine = 2) and (LRange.EndColumn = 1), 'empty range ends where it starts');
  finally
    LText.Free();
  end;

  LText := DoText('ab\'#10'cd');
  try
    LText.FillRange(LRange, 0, 6);
    Check((LRange.StartLine = 1) and (LRange.StartColumn = 1), 'spliced range starts 1:1');
    Check((LRange.EndLine = 2) and (LRange.EndColumn = 2), 'spliced range ends 2:2');
  finally
    LText.Free();
  end;

  LText := DoText(#$FEFF'x');
  try
    Check(LText.ByteCount() = 4, 'BOM is 3 bytes');
    Check(LText.FirstLineStart() = 3, 'BOM: line 1 starts after it');
    LText.FillRange(LRange, 3, 4);
    Check((LRange.StartLine = 1) and (LRange.StartColumn = 1), 'BOM: x at 1:1');
  finally
    LText.Free();
  end;
end;

procedure TPCSourceTextTests.DoTestReinit();
var
  LText: TPCSourceText;
begin
  LText := TPCSourceText.Create();
  try
    Check(LText.LineCount() = 1, 'empty text has line 1');
    Check(LText.LineOf(0) = 1, 'LineOf before Init');
    LText.Init(TEncoding.UTF8.GetBytes('a'#10'b'), 'one.pcpp');
    Check(LText.LineCount() = 2, 'first init: 2 lines');
    LText.Init(TEncoding.UTF8.GetBytes('x'), 'two.pcpp');
    Check(LText.LineCount() = 1, 'second init rebuilds the table');
    Check(LText.FirstLineStart() = 0, 'no BOM: line 1 starts at 0');
    Check(LText.SourceFilename() = 'two.pcpp', 'second init filename');
  finally
    LText.Free();
  end;
end;

end.
