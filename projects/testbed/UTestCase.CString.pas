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
  UTestCase.CString - TPCCString.Decode and DecodeChar tests

  TTestCase suite for the plain narrow string decoder (TPCCString, Common)
  and the generated \N name table (TPCUnicodeNames). Every literal is lexed
  from literal text via TokenizeBytes (exact CR / LF bytes), then decoded.
  Expected values are the bytes clang stores, as probed
  (research\cppmix\cstring-decode.md, cstring-names.md). The byte-for-byte
  comparison against clang itself is ZigBuild.zb25_cstring_parity.
  decode_runs checks the spell runs of the 4-arg Decode (P-STRPOS); its
  expected runs are printed by scripts\zb_sem\pb\r4g2_runs.py.

  Dependencies: StdApp.TestCase, StdApp.Base, StdApp.Resources,
    PaskalCPP.Common, PaskalCPP.TokenStream, PaskalCPP.Lexer,
    PaskalCPP.UnicodeNames
===============================================================================}

unit UTestCase.CString;

interface

uses
  StdApp.TestCase,
  PaskalCPP.Common;

type

  { TPCCStringTests }
  TPCCStringTests = class(TTestCase)
  private
    // One test per concern; Create registers each under its CLI name
    procedure DoTestSimple();
    procedure DoTestOctal();
    procedure DoTestOctalBrace();
    procedure DoTestHex();
    procedure DoTestHexBrace();
    procedure DoTestUcn();
    procedure DoTestNames();
    procedure DoTestNamesGenerated();
    procedure DoTestHangul();
    procedure DoTestUnknownEscape();
    procedure DoSpellingCase(const ALabel: string; const AText: string;
      const AExpected: string);
    procedure DoTestCppSpelling();
    procedure DoTestEscapeStartParity();
    procedure DoTestRaw();
    procedure DoTestSplices();
    procedure DoTestUtf8();
    procedure DoTestGuards();
    procedure DoTestVersion();
    procedure DoTestDecodeRuns();
    procedure DoTestCharNarrow();
    procedure DoTestCharMulti();
    procedure DoTestCharWide();
    procedure DoTestCharErrors();
    procedure DoTestCharGuards();

    // Decodes ASource (one literal) and checks status, value and reason
    procedure DoCase(const ALabel: string; const ASource: string;
      const AStatus: TPCCStringStatus; const AValue: string; const AReason: string);
    // 4-arg Decode on ASource (one literal): status and the runs as text
    // (DoRunsText); the 3-arg Decode must answer the same status, value, reason
    procedure DoRunsCase(const ALabel: string; const ASource: string;
      const AStatus: TPCCStringStatus; const ARuns: string);
    // DecodeChar on ASource (one char literal): status, value, multi-char, reason
    procedure DoCharCase(const ALabel: string; const ASource: string;
      const AStatus: TPCCStringStatus; const AValue: UInt64; const AIsMultiChar: Boolean;
      const AReason: string);
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

// Lexes ASource (exactly one token + EOF) and decodes that token. False when
// the source does not lex cleanly to one token (AReason says why); lexer
// warnings (LX0201) are allowed. Shared with ZigBuild.zb25_cstring_parity.
function DecodeCSource(const ASource: string; out AStatus: TPCCStringStatus;
  out AValue: string; out AReason: string): Boolean;

// The UTF-16 text of one code point (surrogate pair past U+FFFF)
function CodePointText(const ACodePoint: Cardinal): string;

implementation

uses
  System.SysUtils,
  StdApp.Base,
  StdApp.Resources,
  PaskalCPP.TokenStream,
  PaskalCPP.Lexer,
  PaskalCPP.UnicodeNames;

function DoLexOne(const ASource: string; out AToken: TPCToken; out AReason: string): Boolean;
var
  LErrors: TErrors;
  LStream: TPCTokenStream;
  LLexer: TPCLexer;
begin
  // Lexes ASource to exactly one token + EOF (lexer warnings allowed) and
  // hands that token out: the one lexing step of every decode test
  Result := False;
  AToken := Default(TPCToken);
  AReason := '';
  LErrors := TErrors.Create();
  LStream := TPCTokenStream.Create();
  LLexer := TPCLexer.Create();
  try
    LLexer.SetErrors(LErrors);
    LLexer.TokenizeBytes(TEncoding.UTF8.GetBytes(ASource), 'inline.pcpp', LStream);
    if LErrors.ErrorCount() > 0 then
    begin
      AReason := 'the lexer reported an error';
      Exit;
    end;
    if LStream.Count() <> 2 then
    begin
      AReason := Format('lexed to %d tokens, expected one literal + EOF', [LStream.Count()]);
      Exit;
    end;
    AToken := LStream.TokenAt(0);
    Result := True;
  finally
    LLexer.Free();
    LStream.Free();
    LErrors.Free();
  end;
end;

function DecodeCSource(const ASource: string; out AStatus: TPCCStringStatus;
  out AValue: string; out AReason: string): Boolean;
var
  LToken: TPCToken;
begin
  AStatus := csError;
  AValue := '';
  Result := DoLexOne(ASource, LToken, AReason);
  if Result then
    AStatus := TPCCString.Decode(LToken, AValue, AReason);
end;

function CodePointText(const ACodePoint: Cardinal): string;
begin
  if ACodePoint < $10000 then
    Result := Char(ACodePoint)
  else
    Result := Char($D800 + ((ACodePoint - $10000) shr 10)) +
      Char($DC00 + ((ACodePoint - $10000) and $3FF));
end;

function DoReasonOf(const ATemplate: string; const AArg: string): string;
begin
  // The reason Decode builds for a one-%s template
  Result := ATemplate.Replace('%s', AArg);
end;

function DoRunsText(const ARuns: TArray<TPCSpellRun>): string;
var
  LIndex: Integer;
  LKind: string;
begin
  // 'c<ValueOffset>@<SpellIndex>' (copy) or 'e<ValueOffset>@<SpellIndex>'
  // (escape), space-separated; '' for no runs. The AST's mapN spelling with
  // the spelling index where mapN has line:column
  Result := '';
  for LIndex := 0 to High(ARuns) do
  begin
    if ARuns[LIndex].IsCopy then
      LKind := 'c'
    else
      LKind := 'e';
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Format('%s%d@%d',
      [LKind, ARuns[LIndex].ValueOffset, ARuns[LIndex].SpellIndex]);
  end;
end;

{ TPCCStringTests }

constructor TPCCStringTests.Create();
begin
  inherited;

  Title := 'CString';
  RegisterTest('simple', DoTestSimple);
  RegisterTest('octal', DoTestOctal);
  RegisterTest('octal_brace', DoTestOctalBrace);
  RegisterTest('hex', DoTestHex);
  RegisterTest('hex_brace', DoTestHexBrace);
  RegisterTest('ucn', DoTestUcn);
  RegisterTest('names', DoTestNames);
  RegisterTest('names_generated', DoTestNamesGenerated);
  RegisterTest('hangul', DoTestHangul);
  RegisterTest('unknown_escape', DoTestUnknownEscape);
  RegisterTest('cpp_spelling', DoTestCppSpelling);
  RegisterTest('escape_start_parity', DoTestEscapeStartParity);
  RegisterTest('raw', DoTestRaw);
  RegisterTest('splices', DoTestSplices);
  RegisterTest('utf8', DoTestUtf8);
  RegisterTest('guards', DoTestGuards);
  RegisterTest('version', DoTestVersion);
  RegisterTest('decode_runs', DoTestDecodeRuns);
  RegisterTest('char_narrow', DoTestCharNarrow);
  RegisterTest('char_multi', DoTestCharMulti);
  RegisterTest('char_wide', DoTestCharWide);
  RegisterTest('char_errors', DoTestCharErrors);
  RegisterTest('char_guards', DoTestCharGuards);
end;

procedure TPCCStringTests.Run();
begin
  inherited;
end;

procedure TPCCStringTests.DoCase(const ALabel: string; const ASource: string;
  const AStatus: TPCCStringStatus; const AValue: string; const AReason: string);
var
  LStatus: TPCCStringStatus;
  LValue: string;
  LReason: string;
begin
  if not DecodeCSource(ASource, LStatus, LValue, LReason) then
  begin
    Check(False, '%s: lexed: %s', [ALabel, LReason]);
    Exit;
  end;
  Check((LStatus = AStatus) and (LValue = AValue) and (LReason = AReason),
    '%s: status %d, %d chars, reason [%s]', [ALabel, Ord(LStatus), Length(LValue), LReason]);
end;

procedure TPCCStringTests.DoRunsCase(const ALabel: string; const ASource: string;
  const AStatus: TPCCStringStatus; const ARuns: string);
var
  LToken: TPCToken;
  LStatus: TPCCStringStatus;
  LValue: string;
  LReason: string;
  LRuns: TArray<TPCSpellRun>;
  LText: string;
  LPlainStatus: TPCCStringStatus;
  LPlainValue: string;
  LPlainReason: string;
begin
  if not DoLexOne(ASource, LToken, LReason) then
  begin
    Check(False, '%s: lexed: %s', [ALabel, LReason]);
    Exit;
  end;
  LStatus := TPCCString.Decode(LToken, LValue, LReason, LRuns);
  LText := DoRunsText(LRuns);
  Check((LStatus = AStatus) and (LText = ARuns),
    '%s: status %d, runs [%s]', [ALabel, Ord(LStatus), LText]);

  // One walk, one decoder: the 3-arg form answers what the 4-arg form does
  LPlainStatus := TPCCString.Decode(LToken, LPlainValue, LPlainReason);
  Check((LPlainStatus = LStatus) and (LPlainValue = LValue) and (LPlainReason = LReason),
    '%s: 3-arg Decode status %d, reason [%s]', [ALabel, Ord(LPlainStatus), LPlainReason]);
end;

procedure TPCCStringTests.DoTestSimple();
begin
  DoCase('simple set', '"\a\b\f\n\r\t\v\e\E\"\''\?\\"', csOk,
    #7 + #8 + #12 + #10 + #13 + #9 + #11 + #27 + #27 + '"''?\', '');
  DoCase('plain text', '"abc"', csOk, 'abc', '');
  DoCase('empty', '""', csOk, '', '');
  DoCase('no trigraphs', '"??="', csOk, '??=', '');
end;

procedure TPCCStringTests.DoTestOctal();
begin
  DoCase('\101', '"\101"', csOk, 'A', '');
  DoCase('\0', '"\0"', csOk, #0, '');
  DoCase('embedded NUL', '"a\0b"', csOk, 'a' + #0 + 'b', '');
  DoCase('greedy 3 (\1011)', '"\1011"', csOk, 'A1', '');
  DoCase('stops at 8 (\18)', '"\18"', csOk, #1 + '8', '');
  DoCase('\177', '"\177"', csOk, #$7F, '');
  DoCase('bytes C3 A9', '"\303\251"', csOk, #$E9, '');
  DoCase('\400 out of range', '"\400"', csError, '', RSComCStrOctalRange);
  DoCase('\377 alone is not UTF-8', '"\377"', csError, '', RSComCStrNotUtf8);
end;

procedure TPCCStringTests.DoTestOctalBrace();
begin
  DoCase('\o{101}', '"\o{101}"', csOk, 'A', '');
  DoCase('\o leading zeros', '"\o{0000000000101}"', csOk, 'A', '');
  DoCase('\o{} empty', '"\o{}"', csError, '', RSComCStrDelimEmpty);
  DoCase('\o{18} bad digit', '"\o{18}"', csError, '', DoReasonOf(RSComCStrInvalidDigit, '8'));
  DoCase('\o{401} out of range', '"\o{401}"', csError, '', RSComCStrOctalRange);
  DoCase('\o without brace', '"\o101"', csError, '', DoReasonOf(RSComCStrExpectedBrace, 'o'));
  DoCase('\o{ unclosed', '"\o{101"', csError, '', RSComCStrExpectedClose);
end;

procedure TPCCStringTests.DoTestHex();
begin
  DoCase('\x41', '"\x41"', csOk, 'A', '');
  DoCase('\x leading zeros', '"\x0000000000000041"', csOk, 'A', '');
  DoCase('\x lower case', '"\x4a"', csOk, 'J', '');
  DoCase('\x stops at G', '"\x41G"', csOk, 'AG', '');
  DoCase('\x no digits (end)', '"\x"', csError, '', DoReasonOf(RSComCStrNoHexDigits, 'x'));
  DoCase('\x no digits (g)', '"\xg"', csError, '', DoReasonOf(RSComCStrNoHexDigits, 'x'));
  DoCase('\x100 out of range', '"\x100"', csError, '', RSComCStrHexRange);
  DoCase('\x no wraparound', '"\x10000000000000041"', csError, '', RSComCStrHexRange);
  DoCase('\xC3\xA9', '"\xC3\xA9"', csOk, #$E9, '');
  DoCase('\xC3 alone is not UTF-8', '"\xC3"', csError, '', RSComCStrNotUtf8);
end;

procedure TPCCStringTests.DoTestHexBrace();
begin
  DoCase('\x{41}', '"\x{41}"', csOk, 'A', '');
  DoCase('\x{c3}\x{A9}', '"\x{c3}\x{A9}"', csOk, #$E9, '');
  DoCase('\x{} empty', '"\x{}"', csError, '', RSComCStrDelimEmpty);
  DoCase('\x{ unclosed', '"\x{41"', csError, '', RSComCStrExpectedClose);
  DoCase('\x{100} out of range', '"\x{100}"', csError, '', RSComCStrHexRange);
  DoCase('\x{4G} bad digit', '"\x{4G}"', csError, '', DoReasonOf(RSComCStrInvalidDigit, 'G'));
end;

procedure TPCCStringTests.DoTestUcn();
begin
  DoCase('\u00E9', '"\u00E9"', csOk, #$E9, '');
  DoCase('\u00e9', '"\u00e9"', csOk, #$E9, '');
  DoCase('\u exactly 4', '"\u00E9F"', csOk, #$E9 + 'F', '');
  DoCase('\U0001F600', '"\U0001F600"', csOk, CodePointText($1F600), '');
  DoCase('\u{1F600}', '"\u{1F600}"', csOk, CodePointText($1F600), '');
  DoCase('\u{e9}', '"\u{e9}"', csOk, #$E9, '');
  DoCase('\u0041 basic', '"\u0041"', csOk, 'A', '');
  DoCase('\u0001 control', '"\u0001"', csOk, #1, '');
  DoCase('\u no digits', '"\uZ"', csError, '', DoReasonOf(RSComCStrNoHexDigits, 'u'));
  DoCase('\U{ has no braced form', '"\U{41}"', csError, '', DoReasonOf(RSComCStrNoHexDigits, 'U'));
  DoCase('\u short', '"\u00Z"', csError, '', RSComCStrIncompleteUcn);
  DoCase('\U short', '"\U0001F60"', csError, '', RSComCStrIncompleteUcn);
  DoCase('\uD800 surrogate', '"\uD800"', csError, '', RSComCStrInvalidUcn);
  DoCase('\U00110000 too big', '"\U00110000"', csError, '', RSComCStrInvalidUcn);
  DoCase('\UFFFFFFFF too big', '"\UFFFFFFFF"', csError, '', RSComCStrInvalidUcn);
  DoCase('\u{110000} too big', '"\u{110000}"', csError, '', RSComCStrInvalidUcn);
  DoCase('\u{D800} surrogate', '"\u{D800}"', csError, '', RSComCStrInvalidUcn);
  DoCase('\u{} empty', '"\u{}"', csError, '', RSComCStrDelimEmpty);
  DoCase('\u{4 1} bad digit', '"\u{4 1}"', csError, '', DoReasonOf(RSComCStrInvalidDigit, ' '));
  DoCase('\u{ unclosed', '"\u{41"', csError, '', RSComCStrExpectedClose);
end;

procedure TPCCStringTests.DoTestNames();
begin
  DoCase('table name', '"\N{LATIN SMALL LETTER E WITH ACUTE}"', csOk, #$E9, '');
  DoCase('control alias NULL', '"\N{NULL}"', csOk, #0, '');
  DoCase('control alias LINE FEED', '"\N{LINE FEED}"', csOk, #10, '');
  DoCase('correction alias', '"\N{LATIN CAPITAL LETTER GHA}"', csOk, #$01A2, '');
  DoCase('corrected original stays', '"\N{LATIN CAPITAL LETTER OI}"', csOk, #$01A2, '');
  DoCase('alternate alias', '"\N{BYTE ORDER MARK}"', csOk, #$FEFF, '');
  DoCase('abbreviation rejected', '"\N{LF}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'LF'));
  DoCase('figment rejected', '"\N{HIGH OCTET PRESET}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'HIGH OCTET PRESET'));
  DoCase('exact case', '"\N{latin small letter e with acute}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'latin small letter e with acute'));
  DoCase('\N without brace', '"\N"', csError, '', DoReasonOf(RSComCStrExpectedBrace, 'N'));
  DoCase('\N{ unclosed', '"\N{LATIN"', csError, '', RSComCStrIncompleteUcn);
  DoCase('\N{} empty', '"\N{}"', csError, '', RSComCStrDelimEmpty);
  DoCase('Unicode 16.0 name unknown', '"\N{ALIEN CRAB STEPPING LEFT}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'ALIEN CRAB STEPPING LEFT'));
end;

procedure TPCCStringTests.DoTestNamesGenerated();
begin
  // Prefix + uppercase hex inside a range; any leading zeros; no wraparound
  DoCase('CJK 4E00', '"\N{CJK UNIFIED IDEOGRAPH-4E00}"', csOk, CodePointText($4E00), '');
  DoCase('CJK leading zero', '"\N{CJK UNIFIED IDEOGRAPH-04E00}"', csOk, CodePointText($4E00), '');
  DoCase('CJK many zeros', '"\N{CJK UNIFIED IDEOGRAPH-000004E00}"', csOk, CodePointText($4E00), '');
  DoCase('CJK Ext I 2EBF0', '"\N{CJK UNIFIED IDEOGRAPH-2EBF0}"', csOk, CodePointText($2EBF0), '');
  DoCase('CJK lower hex', '"\N{CJK UNIFIED IDEOGRAPH-4e00}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'CJK UNIFIED IDEOGRAPH-4e00'));
  DoCase('CJK outside range', '"\N{CJK UNIFIED IDEOGRAPH-A000}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'CJK UNIFIED IDEOGRAPH-A000'));
  DoCase('CJK no wraparound', '"\N{CJK UNIFIED IDEOGRAPH-100004E00}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'CJK UNIFIED IDEOGRAPH-100004E00'));
  DoCase('CJK no digits', '"\N{CJK UNIFIED IDEOGRAPH-}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'CJK UNIFIED IDEOGRAPH-'));
  DoCase('CJK trailing space', '"\N{CJK UNIFIED IDEOGRAPH-4E00 }"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'CJK UNIFIED IDEOGRAPH-4E00 '));
  DoCase('Tangut 17000', '"\N{TANGUT IDEOGRAPH-17000}"', csOk, CodePointText($17000), '');
  DoCase('Tangut outside', '"\N{TANGUT IDEOGRAPH-18D09}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'TANGUT IDEOGRAPH-18D09'));
  DoCase('Khitan 18B00', '"\N{KHITAN SMALL SCRIPT CHARACTER-18B00}"', csOk,
    CodePointText($18B00), '');
  DoCase('Khitan outside', '"\N{KHITAN SMALL SCRIPT CHARACTER-18CD6}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'KHITAN SMALL SCRIPT CHARACTER-18CD6'));
  DoCase('Nushu 1B170', '"\N{NUSHU CHARACTER-1B170}"', csOk, CodePointText($1B170), '');
  DoCase('Nushu outside', '"\N{NUSHU CHARACTER-1B2FC}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'NUSHU CHARACTER-1B2FC'));
  DoCase('compat F900', '"\N{CJK COMPATIBILITY IDEOGRAPH-F900}"', csOk, CodePointText($F900), '');
  DoCase('compat outside', '"\N{CJK COMPATIBILITY IDEOGRAPH-FA6E}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'CJK COMPATIBILITY IDEOGRAPH-FA6E'));
  // TANGUT COMPONENT-nnn is a table name: decimal, exact
  DoCase('Tangut component 001', '"\N{TANGUT COMPONENT-001}"', csOk, CodePointText($18800), '');
  DoCase('Tangut component 1', '"\N{TANGUT COMPONENT-1}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'TANGUT COMPONENT-1'));
  DoCase('Tangut component 0001', '"\N{TANGUT COMPONENT-0001}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'TANGUT COMPONENT-0001'));
end;

procedure TPCCStringTests.DoTestHangul();
begin
  DoCase('GA', '"\N{HANGUL SYLLABLE GA}"', csOk, CodePointText($AC00), '');
  DoCase('HIH', '"\N{HANGUL SYLLABLE HIH}"', csOk, CodePointText($D7A3), '');
  DoCase('lower case', '"\N{HANGUL SYLLABLE ga}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'HANGUL SYLLABLE ga'));
  DoCase('no space', '"\N{HANGUL SYLLABLEGA}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'HANGUL SYLLABLEGA'));
  DoCase('no jamo', '"\N{HANGUL SYLLABLE }"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'HANGUL SYLLABLE '));
  DoCase('bad jamo', '"\N{HANGUL SYLLABLE GX}"', csError, '',
    DoReasonOf(RSComCStrUnknownName, 'HANGUL SYLLABLE GX'));
end;

procedure TPCCStringTests.DoTestUnknownEscape();
begin
  DoCase('\q', '"\q"', csWarning, 'q', DoReasonOf(RSComCStrUnknownEscape, 'q'));
  DoCase('first warning named', '"\q\("', csWarning, 'q(', DoReasonOf(RSComCStrUnknownEscape, 'q'));
  DoCase('\8', '"\8"', csWarning, '8', DoReasonOf(RSComCStrUnknownEscape, '8'));
  DoCase('\ + multi-byte character', '"\' + #$E9 + '"', csWarning, #$E9,
    DoReasonOf(RSComCStrUnknownEscape, #$E9));
  DoCase('error after a warning', '"\q\x100"', csError, '', RSComCStrHexRange);
end;

procedure TPCCStringTests.DoSpellingCase(const ALabel: string; const AText: string;
  const AExpected: string);
var
  LActual: string;
begin
  LActual := TPCCString.CppSpelling(AText);
  Check(LActual = AExpected, '%s: [%s], expected [%s]', [ALabel, LActual, AExpected]);
end;

procedure TPCCStringTests.DoTestCppSpelling();
begin
  // F65: an unknown escape loses its '\' (the value C++ and Decode give it);
  // every known escape, splice and character stays as written
  DoSpellingCase('unknown', '"a\qb"', '"aqb"');
  DoSpellingCase('two unknown', '"\q\("', '"q("');
  DoSpellingCase('known kept', '"\n\t\x41\101\u0041\N{LATIN SMALL LETTER A}\o{7}\e\?"',
    '"\n\t\x41\101\u0041\N{LATIN SMALL LETTER A}\o{7}\e\?"');
  DoSpellingCase('\\ is one escape', '"\\q"', '"\\q"');
  DoSpellingCase('\\ then unknown', '"\\\q"', '"\\q"');
  DoSpellingCase('quote escapes', '"\"\''"', '"\"\''"');
  DoSpellingCase('\ + multi-byte character', '"\' + #$E9 + '"', '"' + #$E9 + '"');
  DoSpellingCase('\8 unknown', '"\8"', '"8"');
  DoSpellingCase('splice kept', '"s\' + #10 + 'q"', '"s\' + #10 + 'q"');
  DoSpellingCase('whitespace splice kept', '"s\ ' + #13#10 + 'q"', '"s\ ' + #13#10 + 'q"');
  DoSpellingCase('splice inside an unknown escape', '"s\\' + #10 + 'q"', '"s\' + #10 + 'q"');
  DoSpellingCase('splice inside a known escape', '"s\\' + #13#10 + 'n"', '"s\\' + #13#10 + 'n"');
  DoSpellingCase('two splices inside', '"\\' + #10 + '\' + #10 + 'q"', '"\' + #10 + '\' + #10 + 'q"');
  DoSpellingCase('char', '''\q''', '''q''');
  DoSpellingCase('trailing backslash kept', 'a\', 'a\');
end;

procedure TPCCStringTests.DoTestEscapeStartParity();
var
  LCode: Integer;
  LChar: Char;
  LStatus: TPCCStringStatus;
  LValue: string;
  LReason: string;
begin
  // IsEscapeStart is the decoder's own set: every printable ASCII character
  // and a multi-byte one after '\' warns exactly when IsEscapeStart says no
  for LCode := 32 to 127 do
  begin
    if LCode = 127 then
      LChar := #$E9
    else
      LChar := Char(LCode);
    if not DecodeCSource('"\' + LChar + '"', LStatus, LValue, LReason) then
    begin
      Check(False, '\%s: lexed: %s', [LChar, LReason]);
      Continue;
    end;
    Check((LStatus = csWarning) = (not TPCCString.IsEscapeStart(LChar)),
      '\%s: status %d, IsEscapeStart %s', [LChar, Ord(LStatus),
      BoolToStr(TPCCString.IsEscapeStart(LChar), True)]);
  end;
end;

procedure TPCCStringTests.DoTestRaw();
begin
  DoCase('body as written', 'R"(a\n"b)"', csOk, 'a\n"b', '');
  DoCase('delimiter', 'R"xy(a)"b)xy"', csOk, 'a)"b', '');
  DoCase('16-char delimiter', 'R"0123456789abcdef(x)0123456789abcdef"', csOk, 'x', '');
  DoCase('empty body', 'R"()"', csOk, '', '');
  DoCase('CR LF -> LF', 'R"(a' + #13#10 + 'b)"', csOk, 'a' + #10 + 'b', '');
  DoCase('lone CR kept', 'R"(a' + #13 + 'b)"', csOk, 'a' + #13 + 'b', '');
  DoCase('splice kept', 'R"(a\' + #10 + 'b)"', csOk, 'a\' + #10 + 'b', '');
  DoCase('splice CR LF kept as LF', 'R"(a\' + #13#10 + 'b)"', csOk, 'a\' + #10 + 'b', '');
  DoCase('prefix splice removed', 'R\' + #10 + '"(x)"', csOk, 'x', '');
end;

procedure TPCCStringTests.DoTestSplices();
begin
  // Spelling has every splice removed; the lexer (not Decode) warns LX0201
  DoCase('\ LF', '"ab\' + #10 + 'cd"', csOk, 'abcd', '');
  DoCase('\ CR LF', '"ab\' + #13#10 + 'cd"', csOk, 'abcd', '');
  DoCase('\ lone CR', '"ab\' + #13 + 'cd"', csOk, 'abcd', '');
  DoCase('whitespace splice, no decoder warning', '"a\ ' + #10 + 'b"', csOk, 'ab', '');
  DoCase('splice inside an escape', '"\\' + #10 + 'n"', csOk, #10, '');
  DoCase('splice inside hex digits', '"\x4\' + #10 + '1"', csOk, 'A', '');
end;

procedure TPCCStringTests.DoTestUtf8();
begin
  DoCase('direct UTF-8', '"' + #$E9 + CodePointText($1F600) + '"', csOk,
    #$E9 + CodePointText($1F600), '');
  DoCase('\x bytes of U+1F600', '"\xF0\x9F\x98\x80"', csOk, CodePointText($1F600), '');
  DoCase('overlong', '"\xC0\x80"', csError, '', RSComCStrNotUtf8);
  DoCase('surrogate bytes', '"\xED\xA0\x80"', csError, '', RSComCStrNotUtf8);
  DoCase('past U+10FFFF', '"\xF4\x90\x80\x80"', csError, '', RSComCStrNotUtf8);
  DoCase('truncated', '"\xE9"', csError, '', RSComCStrNotUtf8);
  DoCase('stray continuation', '"\x80"', csError, '', RSComCStrNotUtf8);
  DoCase('lead $F8', '"\xF8\x80\x80\x80\x80"', csError, '', RSComCStrNotUtf8);
end;

procedure TPCCStringTests.DoTestGuards();
begin
  // Callers report PR0009 first; Decode still refuses anything else
  DoCase('u8 prefix', 'u8"a"', csError, '', RSComCStrNotPlain);
  DoCase('u prefix', 'u"a"', csError, '', RSComCStrNotPlain);
  DoCase('U prefix', 'U"a"', csError, '', RSComCStrNotPlain);
  DoCase('L prefix', 'L"a"', csError, '', RSComCStrNotPlain);
  DoCase('suffix', '"a"_s', csError, '', RSComCStrNotPlain);
  DoCase('char literal', '''a''', csError, '', RSComCStrNotPlain);
  DoCase('identifier', 'abc', csError, '', RSComCStrNotPlain);
end;

procedure TPCCStringTests.DoTestVersion();
var
  LCodePoint: Cardinal;
begin
  // The table is Unicode 15.1, the bundled clang's version (zb25 pins clang)
  Check(PC_UNICODE_NAMES_VERSION = '15.1.0', 'names version 15.1.0');
  Check(TPCUnicodeNames.Lookup('LATIN SMALL LETTER E WITH ACUTE', LCodePoint) and
    (LCodePoint = $E9), 'Lookup table name');
  Check(not TPCUnicodeNames.Lookup('', LCodePoint), 'Lookup empty name');
end;

procedure TPCCStringTests.DoTestDecodeRuns();
begin
  // P-STRPOS spell runs. Expected texts are printed by
  // scripts\zb_sem\pb\r4g2_runs.py (C6 / C7 walked over each Spelling);
  // splices are gone from the Spelling, so a splice never splits a run here
  // (the parser splits it: UTestCase.Parser P-STRPOS group)
  DoRunsCase('plain', '"abc"', csOk, 'c0@2');
  DoRunsCase('empty', '""', csOk, '');
  DoRunsCase('simple escape', '"a\nb"', csOk, 'c0@2 e1@3 c2@5');
  DoRunsCase('\e', '"\e"', csOk, 'e0@2');
  DoRunsCase('two escapes', '"\t\t"', csOk, 'e0@2 e1@4');
  DoRunsCase('hex', '"x\x41y"', csOk, 'c0@2 e1@3 c2@7');
  DoRunsCase('octal', '"\101\0"', csOk, 'e0@2 e1@6');
  DoRunsCase('\u', '"\u00E9z"', csOk, 'e0@2 c2@8');
  DoRunsCase('\U', '"\U0001F600"', csOk, 'e0@2');
  DoRunsCase('\N', '"\N{LATIN SMALL LETTER E WITH ACUTE}!"', csOk, 'e0@2 c2@37');
  DoRunsCase('delimited x o u', '"\x{41}\o{101}\u{1F600}"', csOk, 'e0@2 e1@8 e2@15');
  DoRunsCase('% as escape', '"\x25y"', csOk, 'e0@2 c1@6');
  DoRunsCase('2-byte UTF-8', '"a' + #$00E9 + 'b"', csOk, 'c0@2');
  DoRunsCase('4-byte UTF-8', '"' + #$D83D + #$DE00 + 'x"', csOk, 'c0@2');
  DoRunsCase('escape then 2-byte', '"\n' + #$00E9 + '"', csOk, 'e0@2 c1@4');
  DoRunsCase('splice before an escape', '"a\' + #10 + '\n"', csOk, 'c0@2 e1@3');
  DoRunsCase('splice between', '"ab\' + #10 + 'cd"', csOk, 'c0@2');
  DoRunsCase('splice inside an escape', '"\\' + #10 + 'n"', csOk, 'e0@2');
  DoRunsCase('two splices in a row', '"a\' + #10 + '\' + #10 + 'b"', csOk, 'c0@2');
  DoRunsCase('whitespace splice', '"a\ ' + #10 + 'b"', csOk, 'c0@2');
  DoRunsCase('raw', 'R"(ab)"', csOk, 'c0@4');
  DoRunsCase('raw two lines LF', 'R"(a' + #10 + 'b)"', csOk, 'c0@4 c2@6');
  DoRunsCase('raw two lines CR LF', 'R"(a' + #13 + #10 + 'b)"', csOk, 'c0@4 c1@6 c2@7');
  DoRunsCase('raw lone CR', 'R"(a' + #13 + 'b)"', csOk, 'c0@4 c2@6');
  DoRunsCase('raw backslash newline', 'R"(a\' + #10 + 'b)"', csOk, 'c0@4 c3@7');
  DoRunsCase('raw delimiter', 'R"xy(a)"b)xy"', csOk, 'c0@6');
  DoRunsCase('raw empty', 'R"()"', csOk, '');
  DoRunsCase('raw prefix splice', 'R\' + #10 + '"(x)"', csOk, 'c0@4');
  DoRunsCase('warning keeps runs', '"\qa"', csWarning, 'e0@2 c1@4');
  DoRunsCase('warning multi-byte', '"\' + #$00E9 + '"', csWarning, 'e0@2');
  DoRunsCase('error has none', '"a\x100"', csError, '');
  DoRunsCase('prefixed has none', 'u8"a"', csError, '');
end;

procedure TPCCStringTests.DoCharCase(const ALabel: string; const ASource: string;
  const AStatus: TPCCStringStatus; const AValue: UInt64; const AIsMultiChar: Boolean;
  const AReason: string);
var
  LToken: TPCToken;
  LStatus: TPCCStringStatus;
  LValue: UInt64;
  LIsMultiChar: Boolean;
  LReason: string;
begin
  if not DoLexOne(ASource, LToken, LReason) then
  begin
    Check(False, '%s: lexed: %s', [ALabel, LReason]);
    Exit;
  end;
  LStatus := TPCCString.DecodeChar(LToken, LValue, LIsMultiChar, LReason);
  Check((LStatus = AStatus) and (LValue = AValue) and (LIsMultiChar = AIsMultiChar) and
    (LReason = AReason), '%s: status %d, value %d, multi %s, reason [%s]',
    [ALabel, Ord(LStatus), LValue, BoolToStr(LIsMultiChar, True), LReason]);
end;

procedure TPCCStringTests.DoTestCharNarrow();
begin
  // Values as clang computes them (scripts\zb_sem\char_probe.txt): one
  // element = its byte; the char's signedness is SEM's ('\xFF' is 255 here)
  DoCharCase('a', '''a''', csOk, 97, False, '');
  DoCharCase('\n', '''\n''', csOk, 10, False, '');
  DoCharCase('\''', '''\''''', csOk, 39, False, '');
  DoCharCase('\\', '''\\''', csOk, 92, False, '');
  DoCharCase('\e', '''\e''', csOk, 27, False, '');
  DoCharCase('"', '''"''', csOk, 34, False, '');
  DoCharCase('\x41', '''\x41''', csOk, 65, False, '');
  DoCharCase('\xFF', '''\xFF''', csOk, 255, False, '');
  DoCharCase('\x0041', '''\x0041''', csOk, 65, False, '');
  DoCharCase('\101', '''\101''', csOk, 65, False, '');
  DoCharCase('\0', '''\0''', csOk, 0, False, '');
  DoCharCase('\377', '''\377''', csOk, 255, False, '');
  DoCharCase('\x{41}', '''\x{41}''', csOk, 65, False, '');
  DoCharCase('\o{101}', '''\o{101}''', csOk, 65, False, '');
  DoCharCase('\u0041', '''\u0041''', csOk, 65, False, '');
  DoCharCase('\N{...A}', '''\N{LATIN SMALL LETTER A}''', csOk, 97, False, '');
  DoCharCase('\q warns', '''\q''', csWarning, 113, False,
    DoReasonOf(RSComCStrUnknownEscape, 'q'));
end;

procedure TPCCStringTests.DoTestCharMulti();
begin
  // Several elements: each byte shifted in, 32 bits kept (clang); each one
  // warns as clang does (F66), past 4 elements once, as too long
  DoCharCase('ab', '''ab''', csWarning, $6162, True, RSComCharMulti);
  DoCharCase('abcd', '''abcd''', csWarning, $61626364, True, RSComCharMulti);
  DoCharCase('abcde keeps the last 4', '''abcde''', csWarning, $62636465, True, RSComCharTooLong);
  DoCharCase('\xFF\x00\x00\x01', '''\xFF\x00\x00\x01''', csWarning, $FF000001, True, RSComCharMulti);
  DoCharCase('a\n', '''a\n''', csWarning, $610A, True, RSComCharMulti);
  DoCharCase('an unknown escape is named first', '''a\q''', csWarning, $6171, True,
    DoReasonOf(RSComCStrUnknownEscape, 'q'));
end;

procedure TPCCStringTests.DoTestCharWide();
begin
  // L: exactly one element, its code point or escape value; the fit to the
  // target's wchar_t (16 bits on windows) is SEM's
  DoCharCase('L a', 'L''a''', csOk, 97, False, '');
  DoCharCase('L e-acute', 'L''' + #$E9 + '''', csOk, $E9, False, '');
  DoCharCase('L \x1234', 'L''\x1234''', csOk, $1234, False, '');
  DoCharCase('L \xFFFF', 'L''\xFFFF''', csOk, $FFFF, False, '');
  DoCharCase('L \xFFFFFFFF', 'L''\xFFFFFFFF''', csOk, $FFFFFFFF, False, '');
  DoCharCase('L \U0001F600', 'L''\U0001F600''', csOk, $1F600, False, '');
  DoCharCase('L \x100000000', 'L''\x100000000''', csError, 0, False, RSComCStrHexRange);
  DoCharCase('L ab', 'L''ab''', csError, 0, False, RSComCharWideMulti);
end;

procedure TPCCStringTests.DoTestCharErrors();
begin
  // What clang rejects (char_probe.txt)
  DoCharCase('empty', '''''', csError, 0, False, RSComCharEmpty);
  DoCharCase('\x100', '''\x100''', csError, 0, False, RSComCStrHexRange);
  DoCharCase('\777', '''\777''', csError, 0, False, RSComCStrOctalRange);
  DoCharCase('e-acute source', '''' + #$E9 + '''', csError, 0, False, RSComCharTooLarge);
  DoCharCase('\u00E9', '''\u00E9''', csError, 0, False, RSComCharTooLarge);
  DoCharCase('\N{...E WITH ACUTE}', '''\N{LATIN SMALL LETTER E WITH ACUTE}''', csError, 0,
    False, RSComCharTooLarge);
  DoCharCase('a e-acute', '''a' + #$E9 + '''', csError, 0, False, RSComCharTooLarge);
  DoCharCase('\xFFa is greedy hex', '''\xFFa''', csError, 0, False, RSComCStrHexRange);
end;

procedure TPCCStringTests.DoTestCharGuards();
begin
  // The parser calls DecodeChar only for plain and L chars without a suffix
  DoCharCase('u8 char', 'u8''a''', csError, 0, False, RSComCharNotPlain);
  DoCharCase('u char', 'u''a''', csError, 0, False, RSComCharNotPlain);
  DoCharCase('U char', 'U''a''', csError, 0, False, RSComCharNotPlain);
  DoCharCase('suffix', '''a''_x', csError, 0, False, RSComCharNotPlain);
  DoCharCase('string', '"a"', csError, 0, False, RSComCharNotPlain);
end;

end.
