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
  UTestCase.CppWriter - C++ writer atom tests (PLAN-EMITTER A3)

  TTestCase suite for TPCCppWriter (PaskalCPP.CppWriter): #line on every
  .pcpp line, preamble lines, byte-column EmitSpans (single and multi-line),
  verbatim line-for-line copy (splice continuations and inside lines get no
  #line, CR / CRLF become LF), # lines close their C++ line, the #line path,
  and every invariant raise. Expected texts are written from the contract
  (PROJECT.md Emitter Contracts), never pasted from the writer's output.

  Dependencies: StdApp.TestCase, PaskalCPP.AST, PaskalCPP.CppWriter
===============================================================================}

unit UTestCase.CppWriter;

interface

uses
  StdApp.TestCase;

type

  { TPCCppWriterTests }
  TPCCppWriterTests = class(TTestCase)
  private
    // One test per concern; Create registers each under its CLI name
    procedure DoTestLineDirective();
    procedure DoTestNewLinePerSourceLine();
    procedure DoTestPreamble();
    procedure DoTestInvariants();
    procedure DoTestEmptyText();
    procedure DoTestSpanColumns();
    procedure DoTestBorrowedNoSpan();
    procedure DoTestSpanUtf8();
    procedure DoTestCloseSpan();
    procedure DoTestVerbatimLines();
    procedure DoTestVerbatimAfterText();
    procedure DoTestVerbatimSplice();
    procedure DoTestVerbatimInside();
    procedure DoTestVerbatimNewlines();
    procedure DoTestPreproc();
    procedure DoTestPath();
    procedure DoTestPeerColumns();
    procedure DoTestPeerNoPadLines();
    procedure DoTestReturnToLine();
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  PaskalCPP.AST,
  PaskalCPP.CppWriter;

const
  { TEST_CWR_PATH }
  TEST_CWR_PATH = 'C:\x\m.pcpp';

function DoLine(const ALine: Integer): string;
begin
  // The #line the writer puts before a C++ line of .pcpp line ALine
  Result := Format('#line %d "C:/x/m.pcpp"', [ALine]) + #10;
end;

function DoVerbatim(const AText: string; const AStartLine: UInt64; const AKind: TPCVerbatimKind;
  const AInside: TArray<UInt64>): TPCVerbatim;
begin
  Result := Default(TPCVerbatim);
  Result.Text := AText;
  Result.Range.StartLine := AStartLine;
  Result.VerbatimKind := AKind;
  Result.EmitTarget := etSource;
  Result.InsideLines := AInside;
end;

function DoSpans(const ANode: TPCNode): string;
var
  LSpan: TPCEmitSpan;
begin
  // 'cppline:sourceline:start-end' per span, space-separated
  Result := '';
  for LSpan in ANode.EmitSpans do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Format('%d:%d:%d-%d', [LSpan.CppLine, LSpan.SourceLine, LSpan.StartCol, LSpan.EndCol]);
  end;
end;

function DoRaises(const AProc: TProc): Boolean;
begin
  // True when AProc raises the writer's invariant exception
  try
    AProc();
    Result := False;
  except
    on EInvalidOpException do
      Result := True;
  end;
end;

{ TPCCppWriterTests }

constructor TPCCppWriterTests.Create();
begin
  inherited;

  Title := 'CppWriter';
  RegisterTest('line_directive', DoTestLineDirective);
  RegisterTest('new_line_per_source_line', DoTestNewLinePerSourceLine);
  RegisterTest('preamble', DoTestPreamble);
  RegisterTest('invariants', DoTestInvariants);
  RegisterTest('empty_text', DoTestEmptyText);
  RegisterTest('span_columns', DoTestSpanColumns);
  RegisterTest('borrowed_no_span', DoTestBorrowedNoSpan);
  RegisterTest('span_utf8', DoTestSpanUtf8);
  RegisterTest('close_span', DoTestCloseSpan);
  RegisterTest('verbatim_lines', DoTestVerbatimLines);
  RegisterTest('verbatim_after_text', DoTestVerbatimAfterText);
  RegisterTest('verbatim_splice', DoTestVerbatimSplice);
  RegisterTest('verbatim_inside', DoTestVerbatimInside);
  RegisterTest('verbatim_newlines', DoTestVerbatimNewlines);
  RegisterTest('preproc', DoTestPreproc);
  RegisterTest('path', DoTestPath);
  RegisterTest('peer_columns', DoTestPeerColumns);
  RegisterTest('peer_no_pad_lines', DoTestPeerNoPadLines);
  RegisterTest('return_to_line', DoTestReturnToLine);
end;

procedure TPCCppWriterTests.Run();
begin
  inherited;
end;

procedure TPCCppWriterTests.DoTestReturnToLine();
var
  LWriter: TPCCppWriter;
  LA: TPCNode;
  LB: TPCNode;
  LC: TPCNode;
  LD: TPCNode;
begin
  // PLAN-OBJECT D3: ReturnToSourceLine goes back to an earlier .pcpp line;
  // writes go forward from there; a line that already holds text resumes on
  // a new C++ line (its own #line) past that text, so a (line, column) lies
  // in one text only; it raises when the line is not before the current one
  LWriter := TPCCppWriter.Create();
  LA := TPCNode.Create();
  LB := TPCNode.Create();
  LC := TPCNode.Create();
  LD := TPCNode.Create();
  try
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.SetSourceLine(1);
    LWriter.WriteText('A', LA);
    LWriter.SetSourceLine(4);
    LWriter.WriteText('BB', LB);
    LWriter.ReturnToSourceLine(2);
    LWriter.WriteText('C', LC);
    LWriter.SetSourceLine(4);
    LWriter.WriteText('D', LD);
    Check(LWriter.GetText() = DoLine(1) + 'A' + #10 + DoLine(4) + 'BB' + #10 + DoLine(2) + 'C' + #10 + DoLine(4) +
      '  D' + #10, 'return_to_line: back to line 2, line 4 resumed past its text (got ' + LWriter.GetText() + ')');
    Check((DoSpans(LA) = '2:1:1-2') and (DoSpans(LB) = '4:4:1-3') and (DoSpans(LC) = '6:2:1-2') and
      (DoSpans(LD) = '8:4:3-4'), 'return_to_line: spans on their own lines, line 4''s on disjoint columns (got ' +
      DoSpans(LA) + ' / ' + DoSpans(LB) + ' / ' + DoSpans(LC) + ' / ' + DoSpans(LD) + ')');
    Check(LWriter.LineEnd(4) = 4, 'return_to_line: line 4 ends past both its texts (got ' +
      UIntToStr(LWriter.LineEnd(4)) + ')');
    Check(DoRaises(
      procedure
      begin
        LWriter.ReturnToSourceLine(4);
      end), 'return_to_line: the current line is not back: raises');
    Check(DoRaises(
      procedure
      begin
        LWriter.ReturnToSourceLine(0);
      end), 'return_to_line: line 0 raises');
  finally
    LD.Free();
    LC.Free();
    LB.Free();
    LA.Free();
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestPeerColumns();
var
  LHeader: TPCCppWriter;
  LSource: TPCCppWriter;
  LFirst: TPCNode;
  LSecond: TPCNode;
  LThird: TPCNode;
begin
  // V1: two peered writers share one column space per .pcpp line: each
  // write starts past the peer's text on its line (spaces, no span); a line
  // only one file writes is untouched; Init keeps the peer, clears the ends
  LHeader := TPCCppWriter.Create();
  LSource := TPCCppWriter.Create();
  LFirst := TPCNode.Create();
  LSecond := TPCNode.Create();
  LThird := TPCNode.Create();
  try
    LHeader.Init(ofHeader, TEST_CWR_PATH);
    LSource.Init(ofSource, TEST_CWR_PATH);
    LHeader.SetPeer(LSource);
    LSource.SetPeer(LHeader);
    LHeader.SetSourceLine(1);
    LHeader.WriteText('AB', LFirst);
    LSource.SetSourceLine(1);
    LSource.WriteText('CD', LSecond);
    LHeader.WriteText('E', LThird);
    LSource.SetSourceLine(2);
    LSource.WriteText('F', nil);
    Check(LHeader.GetText() = DoLine(1) + 'AB  E' + #10,
      'peer_columns: the header''s second write moves past the source''s text (got ' + LHeader.GetText() + ')');
    Check(LSource.GetText() = DoLine(1) + '  CD' + #10 + DoLine(2) + 'F' + #10,
      'peer_columns: the source starts past the header''s text; line 2 untouched (got ' + LSource.GetText() + ')');
    Check((DoSpans(LFirst) = '2:1:1-3') and (DoSpans(LSecond) = '2:1:3-5') and (DoSpans(LThird) = '2:1:5-6'),
      'peer_columns: spans on disjoint columns (got ' + DoSpans(LFirst) + ' / ' + DoSpans(LSecond) + ' / ' +
      DoSpans(LThird) + ')');
    Check((LHeader.LineEnd(1) = 6) and (LSource.LineEnd(1) = 5) and (LSource.LineEnd(3) = 1),
      'peer_columns: LineEnd = the column after the file''s text, 1 for none');
    LSource.Init(ofSource, TEST_CWR_PATH);
    Check(LSource.LineEnd(1) = 1, 'peer_columns: Init clears the line ends');
  finally
    LThird.Free();
    LSecond.Free();
    LFirst.Free();
    LSource.Free();
    LHeader.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestPeerNoPadLines();
var
  LHeader: TPCCppWriter;
  LSource: TPCCppWriter;
begin
  // V1: a line that must start at column 1 (a # line, a splice
  // continuation) never meets peer text: if it does, the writer raises
  LHeader := TPCCppWriter.Create();
  LSource := TPCCppWriter.Create();
  try
    LHeader.Init(ofHeader, TEST_CWR_PATH);
    LSource.Init(ofSource, TEST_CWR_PATH);
    LHeader.SetPeer(LSource);
    LSource.SetPeer(LHeader);
    LHeader.SetSourceLine(2);
    LHeader.WriteText('x;', nil);
    Check(DoRaises(
      procedure
      begin
        LSource.WriteVerbatim(DoVerbatim('#define A', 2, vkPreproc, []), nil);
      end), 'peer_no_pad_lines: a # line on a line the peer wrote raises');
    LSource.Init(ofSource, TEST_CWR_PATH);
    Check(DoRaises(
      procedure
      begin
        LSource.WriteVerbatim(DoVerbatim('int a = \' + #10 + '1;', 1, vkCppDecl, []), nil);
      end), 'peer_no_pad_lines: a splice continuation on a line the peer wrote raises');
    LSource.Init(ofSource, TEST_CWR_PATH);
    LSource.WriteVerbatim(DoVerbatim('int a =' + #10 + '1;', 1, vkCppDecl, []), nil);
    Check(LSource.GetText() = DoLine(1) + 'int a =' + #10 + DoLine(2) + '  1;' + #10,
      'peer_no_pad_lines: a verbatim line with its own #line moves past the peer (got ' + LSource.GetText() + ')');
  finally
    LSource.Free();
    LHeader.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestLineDirective();
var
  LWriter: TPCCppWriter;
begin
  LWriter := TPCCppWriter.Create();
  try
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.SetSourceLine(3);
    LWriter.WriteText('int a;', nil);
    LWriter.WriteText(' int b;', nil);
    Check(LWriter.GetText() = DoLine(3) + 'int a; int b;' + #10,
      'line_directive: two writes on line 3 = one C++ line after #line 3');
  finally
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestNewLinePerSourceLine();
var
  LWriter: TPCCppWriter;
begin
  LWriter := TPCCppWriter.Create();
  try
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.SetSourceLine(3);
    LWriter.WriteText('a;', nil);
    LWriter.SetSourceLine(3);
    LWriter.WriteText(' c;', nil);
    LWriter.SetSourceLine(5);
    LWriter.WriteText('b;', nil);
    Check(LWriter.SourceLine() = 5, 'new_line_per_source_line: SourceLine is the last set');
    Check(LWriter.GetText() = DoLine(3) + 'a; c;' + #10 + DoLine(5) + 'b;' + #10,
      'new_line_per_source_line: each .pcpp line its own C++ line and #line; same line stays');
  finally
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestPreamble();
var
  LWriter: TPCCppWriter;
begin
  LWriter := TPCCppWriter.Create();
  try
    LWriter.Init(ofHeader, TEST_CWR_PATH);
    LWriter.WritePreamble('#pragma once');
    LWriter.WritePreamble('#include "pcpp_runtime.h"');
    LWriter.SetSourceLine(1);
    LWriter.WriteText('x;', nil);
    Check(LWriter.GetText() = '#pragma once' + #10 + '#include "pcpp_runtime.h"' + #10 + DoLine(1) + 'x;' + #10,
      'preamble: whole lines without #line before the first .pcpp line');
    LWriter.Init(ofHeader, TEST_CWR_PATH);
    Check(LWriter.GetText() = '', 'preamble: Init starts an empty file');
  finally
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestInvariants();
var
  LWriter: TPCCppWriter;
begin
  LWriter := TPCCppWriter.Create();
  try
    LWriter.Init(ofSource, TEST_CWR_PATH);
    Check(DoRaises(
      procedure
      begin
        LWriter.WriteText('x;', nil);
      end), 'invariants: text before any .pcpp line raises');
    Check(DoRaises(
      procedure
      begin
        LWriter.SetSourceLine(0);
      end), 'invariants: .pcpp line 0 raises');
    Check(DoRaises(
      procedure
      begin
        LWriter.WritePreamble('a' + #10 + 'b');
      end), 'invariants: a preamble line with a line break raises');
    LWriter.SetSourceLine(5);
    Check(DoRaises(
      procedure
      begin
        LWriter.WritePreamble('#pragma once');
      end), 'invariants: a preamble line after the first .pcpp line raises');
    Check(DoRaises(
      procedure
      begin
        LWriter.SetSourceLine(4);
      end), 'invariants: a .pcpp line before the current one raises');
    Check(DoRaises(
      procedure
      begin
        LWriter.WriteText('a' + #10 + 'b', nil);
      end), 'invariants: text with LF raises');
    Check(DoRaises(
      procedure
      begin
        LWriter.WriteText('a' + #13 + 'b', nil);
      end), 'invariants: text with CR raises');
  finally
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestEmptyText();
var
  LWriter: TPCCppWriter;
  LNode: TPCNode;
begin
  LWriter := TPCCppWriter.Create();
  LNode := TPCNode.Create();
  try
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.SetSourceLine(1);
    LWriter.WriteText('', LNode);
    Check((LWriter.GetText() = '') and (Length(LNode.EmitSpans) = 0),
      'empty_text: '''' opens no line and records no span');
  finally
    LNode.Free();
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestSpanColumns();
var
  LWriter: TPCCppWriter;
  LNode: TPCNode;
begin
  LWriter := TPCCppWriter.Create();
  LNode := TPCNode.Create();
  try
    LWriter.Init(ofHeader, TEST_CWR_PATH);
    LWriter.SetSourceLine(1);
    LWriter.WriteText('LY = (', nil);
    LWriter.WriteText('LX', LNode);
    LWriter.WriteText(');', nil);
    Check(DoSpans(LNode) = '2:1:7-9', 'span_columns: LX after ''LY = ('' = C++ line 2, cols 7 .. 9 (got ' +
      DoSpans(LNode) + ')');
    Check((Length(LNode.EmitSpans) = 1) and (LNode.EmitSpans[0].OutFile = ofHeader),
      'span_columns: the span names the writer''s file');
  finally
    LNode.Free();
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestBorrowedNoSpan();
var
  LWriter: TPCCppWriter;
  LNode: TPCNode;
  LMark: TPCWriterMark;
begin
  // A7: a borrowed spelling (the same text a second time) records no span,
  // nested pairs included; the text is still written; spans resume after;
  // an unpaired EndBorrowed is an invariant
  LWriter := TPCCppWriter.Create();
  LNode := TPCNode.Create();
  try
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.SetSourceLine(1);
    LWriter.BeginBorrowed();
    LWriter.BeginBorrowed();
    LWriter.WriteText('AA', LNode);
    LWriter.EndBorrowed();
    LMark := LWriter.Mark();
    LWriter.WriteText('BB', nil);
    LWriter.CloseSpan(LMark, LNode);
    LWriter.EndBorrowed();
    Check(Length(LNode.EmitSpans) = 0, 'borrowed_no_span: no span inside BeginBorrowed / EndBorrowed (got ' +
      DoSpans(LNode) + ')');
    LWriter.WriteText('CC', LNode);
    Check(DoSpans(LNode) = '2:1:5-7', 'borrowed_no_span: spans resume after the last EndBorrowed (got ' +
      DoSpans(LNode) + ')');
    Check(LWriter.GetText().EndsWith('AABBCC' + #10), 'borrowed_no_span: the borrowed text is written');
    Check(DoRaises(
      procedure
      begin
        LWriter.EndBorrowed();
      end), 'borrowed_no_span: EndBorrowed without BeginBorrowed raises');
  finally
    LNode.Free();
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestSpanUtf8();
var
  LWriter: TPCCppWriter;
  LNode: TPCNode;
begin
  LWriter := TPCCppWriter.Create();
  LNode := TPCNode.Create();
  try
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.SetSourceLine(1);
    LWriter.WriteText(#$00E9, nil);
    LWriter.WriteText('x', LNode);
    Check(DoSpans(LNode) = '2:1:3-4', 'span_utf8: a 2-byte character shifts the column by 2 (got ' +
      DoSpans(LNode) + ')');
  finally
    LNode.Free();
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestCloseSpan();
var
  LWriter: TPCCppWriter;
  LCall: TPCNode;
  LNext: TPCNode;
  LMark: TPCWriterMark;
begin
  LWriter := TPCCppWriter.Create();
  LCall := TPCNode.Create();
  LNext := TPCNode.Create();
  try
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.SetSourceLine(1);
    LWriter.WriteText('x = ', nil);
    LMark := LWriter.Mark();
    LWriter.WriteText('f(', nil);
    LWriter.SetSourceLine(2);
    LWriter.WriteText('y)', nil);
    LWriter.CloseSpan(LMark, LCall);
    Check(DoSpans(LCall) = '2:1:5-7 4:2:1-3',
      'close_span: a 2-line call = its part of C++ line 2 and all of line 4 (got ' + DoSpans(LCall) + ')');
    // A mark taken before its line opens starts at column 1 of that line
    LWriter.SetSourceLine(3);
    LMark := LWriter.Mark();
    LWriter.WriteText('z;', nil);
    LWriter.CloseSpan(LMark, LNext);
    Check(DoSpans(LNext) = '6:3:1-3', 'close_span: a mark before its line opens (got ' + DoSpans(LNext) + ')');
  finally
    LNext.Free();
    LCall.Free();
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestVerbatimLines();
var
  LWriter: TPCCppWriter;
  LNode: TPCNode;
begin
  LWriter := TPCCppWriter.Create();
  LNode := TPCNode.Create();
  try
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.WriteVerbatim(DoVerbatim('int a;' + #10 + '  int b;' + #10 + 'int c;', 4, vkCppDecl, nil), LNode);
    Check(LWriter.GetText() = DoLine(4) + 'int a;' + #10 + DoLine(5) + '  int b;' + #10 + DoLine(6) + 'int c;' + #10,
      'verbatim_lines: 3 lines in place, each with its #line, whitespace kept');
    Check(DoSpans(LNode) = '2:4:1-7 4:5:1-9 6:6:1-7',
      'verbatim_lines: one span per line, columns of the copied bytes (got ' + DoSpans(LNode) + ')');
  finally
    LNode.Free();
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestVerbatimAfterText();
var
  LWriter: TPCCppWriter;
  LNode: TPCNode;
begin
  LWriter := TPCCppWriter.Create();
  LNode := TPCNode.Create();
  try
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.SetSourceLine(4);
    LWriter.WriteText('} ', nil);
    LWriter.WriteVerbatim(DoVerbatim('int a;', 4, vkCppDecl, nil), LNode);
    LWriter.WriteText(' namespace M {', nil);
    Check(LWriter.GetText() = DoLine(4) + '} int a; namespace M {' + #10,
      'verbatim_after_text: line 0 continues the current C++ line');
    Check(DoSpans(LNode) = '2:4:3-9', 'verbatim_after_text: span starts where its first byte lands (got ' +
      DoSpans(LNode) + ')');
  finally
    LNode.Free();
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestVerbatimSplice();
var
  LWriter: TPCCppWriter;
  LNode: TPCNode;
begin
  LWriter := TPCCppWriter.Create();
  LNode := TPCNode.Create();
  try
    // '\' + space + newline: a whitespace splice; its continuation has no #line
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.WriteVerbatim(DoVerbatim('int a = 1 + \ ' + #10 + '2;', 1, vkCppDecl, nil), LNode);
    Check(LWriter.GetText() = DoLine(1) + 'int a = 1 + \ ' + #10 + '2;' + #10,
      'verbatim_splice: no #line on the continuation line');
    Check(DoSpans(LNode) = '2:1:1-15 3:2:1-3',
      'verbatim_splice: the counted line keeps its .pcpp line (got ' + DoSpans(LNode) + ')');
    // A '\' followed by code is no splice: the next line gets its #line
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.WriteVerbatim(DoVerbatim('a = 1; // x \ y' + #10 + 'b;', 1, vkCppDecl, nil), nil);
    Check(LWriter.GetText() = DoLine(1) + 'a = 1; // x \ y' + #10 + DoLine(2) + 'b;' + #10,
      'verbatim_splice: a backslash before code is not a splice');
  finally
    LNode.Free();
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestVerbatimInside();
var
  LWriter: TPCCppWriter;
begin
  LWriter := TPCCppWriter.Create();
  try
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.WriteVerbatim(DoVerbatim('auto s = R"(a' + #10 + 'b)";', 7, vkCppDecl, [8]), nil);
    Check(LWriter.GetText() = DoLine(7) + 'auto s = R"(a' + #10 + 'b)";' + #10,
      'verbatim_inside: a line in InsideLines (inside a raw string) gets no #line');
  finally
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestVerbatimNewlines();
var
  LWriter: TPCCppWriter;
begin
  LWriter := TPCCppWriter.Create();
  try
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.WriteVerbatim(DoVerbatim('int a;' + #13#10 + 'int b;', 1, vkCppDecl, nil), nil);
    Check(LWriter.GetText() = DoLine(1) + 'int a;' + #10 + DoLine(2) + 'int b;' + #10,
      'verbatim_newlines: CRLF becomes LF');
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.WriteVerbatim(DoVerbatim('a;' + #13 + 'b;', 1, vkCppDecl, nil), nil);
    Check(LWriter.GetText() = DoLine(1) + 'a;' + #10 + DoLine(2) + 'b;' + #10,
      'verbatim_newlines: a lone CR is a newline (clang''s set) and becomes LF');
    // A trailing newline ends the last line; the next .pcpp line starts fresh
    LWriter.Init(ofSource, TEST_CWR_PATH);
    LWriter.WriteVerbatim(DoVerbatim('int a;' + #10, 1, vkCppDecl, nil), nil);
    LWriter.SetSourceLine(2);
    LWriter.WriteText('b;', nil);
    Check(LWriter.GetText() = DoLine(1) + 'int a;' + #10 + DoLine(2) + 'b;' + #10,
      'verbatim_newlines: a trailing newline adds no empty line');
  finally
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestPreproc();
var
  LWriter: TPCCppWriter;
begin
  LWriter := TPCCppWriter.Create();
  try
    LWriter.Init(ofHeader, TEST_CWR_PATH);
    LWriter.WriteVerbatim(DoVerbatim('#include <x>', 2, vkPreproc, nil), nil);
    Check(DoRaises(
      procedure
      begin
        LWriter.WriteText('y', nil);
      end), 'preproc: text after a # line on its .pcpp line raises');
    LWriter.SetSourceLine(3);
    LWriter.WriteText('z;', nil);
    Check(LWriter.GetText() = DoLine(2) + '#include <x>' + #10 + DoLine(3) + 'z;' + #10,
      'preproc: the # line is closed by a newline; the next .pcpp line follows');
    LWriter.Init(ofHeader, TEST_CWR_PATH);
    LWriter.SetSourceLine(2);
    LWriter.WriteText('} ', nil);
    Check(DoRaises(
      procedure
      begin
        LWriter.WriteVerbatim(DoVerbatim('#include <x>', 2, vkPreproc, nil), nil);
      end), 'preproc: a # line that does not start its C++ line raises');
  finally
    LWriter.Free();
  end;
end;

procedure TPCCppWriterTests.DoTestPath();
var
  LWriter: TPCCppWriter;
begin
  LWriter := TPCCppWriter.Create();
  try
    LWriter.Init(ofSource, 'C:\a b\m.pcpp');
    LWriter.SetSourceLine(1);
    LWriter.WriteText('x;', nil);
    Check(LWriter.GetText() = '#line 1 "C:/a b/m.pcpp"' + #10 + 'x;' + #10,
      'path: backslashes become forward slashes, spaces kept');
    LWriter.Init(ofSource, '/tmp/q"m.pcpp');
    LWriter.SetSourceLine(1);
    LWriter.WriteText('x;', nil);
    Check(LWriter.GetText() = '#line 1 "/tmp/q\"m.pcpp"' + #10 + 'x;' + #10,
      'path: a quote in the path is escaped');
  finally
    LWriter.Free();
  end;
end;

end.
