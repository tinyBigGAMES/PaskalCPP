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
  PaskalCPP.CppWriter - One generated C++ file: text, #line and EmitSpans

  TPCCppWriter is the only writer of C++ text (PLAN-EMITTER A3, H14). It
  owns the PROJECT.md Emitter Contracts at the byte level: everything for
  one .pcpp line goes on one C++ line preceded by its own `#line N "path"`;
  verbatim C++ is copied line for line (no #line on a splice continuation or
  on a line in InsideLines); a `#` line is always followed by a newline. Text
  and positions come from the same call, so they cannot disagree: every
  write that names a node records its TPCEmitSpan on it (AddEmitSpan, the
  emitter's only AST write). Columns are 1-based UTF-8 byte columns, as
  clang counts.

  Dependencies: StdApp.Base (TBaseObject), StdApp.Utils
    (StripLongPathPrefix), StdApp.Resources (RSCwr*), PaskalCPP.SourceText
    (the one newline / splice test), PaskalCPP.AST (TPCNode, TPCEmitSpan,
    TPCVerbatim, TPCOutFile)
  Notes: Pure: no file I/O. A broken call is an invariant (raise
    EInvalidOpException): the emitter builds every call from the AST.
===============================================================================}

unit PaskalCPP.CppWriter;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.SourceText,
  PaskalCPP.AST;

type

  { TPCWriterMark }
  // A position CloseSpan records from: LineIndex = the index of the C++ line
  // (0-based, every physical line counted) the next byte lands on, Col its
  // 1-based byte column there
  TPCWriterMark = record
    LineIndex: Integer;
    Col: UInt64;
  end;

  { TPCWriterLine }
  // One physical C++ line written so far: its .pcpp line (0 for preamble and
  // #line lines), its byte count, and whether it holds emitted text
  TPCWriterLine = record
    SourceLine: UInt64;
    Bytes: UInt64;
    IsText: Boolean;
  end;

  { TPCCppWriter }
  TPCCppWriter = class(TBaseObject)
  private
    FOutFile: TPCOutFile;
    FPathText: string;              // the #line path: forward slashes, C-escaped
    FStream: TMemoryStream;
    FLines: TList<TPCWriterLine>;
    FSourceLine: UInt64;            // the current .pcpp line; 0 = none yet
    FLineOpen: Boolean;             // a text line for FSourceLine is open
    FLineClosed: Boolean;           // FSourceLine's C++ line was closed (a # line)
    FAtLineStart: Boolean;          // the stream is empty or ends with LF
    FBorrowed: Integer;             // > 0: inside BeginBorrowed / EndBorrowed, no span is recorded
    FPeer: TPCCppWriter;            // the module's other file (not owned); nil = no shared columns
    FLineEnd: TDictionary<UInt64, UInt64>;  // .pcpp line -> the column after this file's text on it
    FResumeCol: UInt64;             // the open C++ line's text starts past this column: this file's
                                    // own earlier text on the same .pcpp line (ReturnToSourceLine); 1 = none

    class function DoUtf8(const AText: string): TBytes; static;
    class function DoIsInsideLine(const AVerbatim: TPCVerbatim; const ALine: UInt64): Boolean; static;
    class function DoEndsInSplice(const AText: TPCSourceText; const AStart: Int64; const AEnd: Int64): Boolean; static;
    procedure DoAppend(const ABytes: TBytes);
    procedure DoEndPhysicalLine();
    procedure DoStartLine(const AWithDirective: Boolean);
    procedure DoEnsureLine();
    procedure DoPadToPeer(const AMayPad: Boolean);
    procedure DoAppendText(const ABytes: TBytes; const ANode: TPCNode; const AMayPad: Boolean);
    procedure DoRecordSpan(const ANode: TPCNode; const ALineIndex: Integer; const AStartCol: UInt64;
      const AEndCol: UInt64);
    function DoCurrentCol(): UInt64;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Starts a new, empty file for AOutFile; ASourcePath is the module's
    // SourceFile (TPCModule.SourceFile), written in every #line
    procedure Init(const AOutFile: TPCOutFile; const ASourcePath: string);

    // V1: the module's header and source share one column space per .pcpp
    // line. With a peer, every text written on a .pcpp line starts past the
    // peer's text on that line (spaces, no span), so a (.pcpp line, C++
    // column) clang reports through #line lies in one file's text only and
    // TranslateLocation finds that file's node. Not owned; kept by Init
    procedure SetPeer(const APeer: TPCCppWriter);
    // The column after this file's text on .pcpp line ALine; 1 = none
    function LineEnd(const ALine: UInt64): UInt64;

    // A whole C++ line with no #line; only before the first SetSourceLine
    procedure WritePreamble(const ALine: string);

    // Selects the .pcpp line later writes belong to; never backwards. It
    // opens nothing: the first write for the line starts its C++ line
    procedure SetSourceLine(const ALine: UInt64);
    // PLAN-OBJECT D3: back to an earlier .pcpp line (an init's locals are
    // written after its member-init list, which holds later lines). Writes go
    // forward from there as usual; a .pcpp line that already holds text in
    // this file resumes on a new C++ line (its own #line) past that text, so
    // a (.pcpp line, column) still lies in one text only (V1's rule)
    procedure ReturnToSourceLine(const ALine: UInt64);

    // Appends text without a line break to the current C++ line; ANode <> nil
    // records the span of exactly these bytes on it. '' writes nothing
    procedure WriteText(const AText: string; const ANode: TPCNode);

    // Mark + CloseSpan: one span on ANode per C++ text line from the mark to
    // the current position (a composite node covers its children)
    function Mark(): TPCWriterMark;
    procedure CloseSpan(const AMark: TPCWriterMark; const ANode: TPCNode);

    // Copies AVerbatim.Text line for line, line k on .pcpp line
    // Range.StartLine + k, one span per non-empty line on ANode
    procedure WriteVerbatim(const AVerbatim: TPCVerbatim; const ANode: TPCNode);

    // A borrowed spelling: text another node's spelling already owns (the
    // routine's return type in a guard's std::optional, a for iterator's
    // type). Between the two calls nothing records a span; they nest
    procedure BeginBorrowed();
    procedure EndBorrowed();
    // Inside BeginBorrowed / EndBorrowed: the text belongs to a node written
    // elsewhere, so it also goes on the current line (TPCEmitter.DoAt)
    function IsBorrowed(): Boolean;

    function SourceLine(): UInt64;
    // True when SourceLine's C++ line was closed (a # line, or a verbatim that
    // ended in its newline): nothing more can be written for that .pcpp line
    function LineClosed(): Boolean;
    // APath as the text inside a C string literal: the plain spelling with
    // forward slashes, '\' and '"' escaped (the #line path; the emitter uses
    // it for every other path it writes into C++)
    class function EscapePath(const APath: string): string; static;
    // The finished file (a final LF added when the last line has none)
    function GetBytes(): TBytes;
    function GetText(): string;
  end;

implementation

uses
  StdApp.Utils,
  StdApp.Resources;

const
  { PC_CWR_LF }
  PC_CWR_LF: Byte = 10;

{ TPCCppWriter }

constructor TPCCppWriter.Create();
begin
  inherited;

  FStream := TMemoryStream.Create();
  FLines := TList<TPCWriterLine>.Create();
  FLineEnd := TDictionary<UInt64, UInt64>.Create();
  FPeer := nil;
  Init(ofSource, '');
end;

destructor TPCCppWriter.Destroy();
begin
  FLineEnd.Free();
  FLines.Free();
  FStream.Free();

  inherited;
end;

class function TPCCppWriter.DoUtf8(const AText: string): TBytes;
begin
  // Every text the emitter builds is valid UTF-16; a failure is an invariant
  try
    Result := TEncoding.UTF8.GetBytes(AText);
  except
    on E: Exception do
      raise EInvalidOpException.CreateFmt(RSCwrEncoding, [E.Message]);
  end;
end;

class function TPCCppWriter.EscapePath(const APath: string): string;
var
  LPlain: string;
begin
  // #line takes a C string literal: the plain spelling with forward slashes
  // (PROJECT.md: absolute, forward-slash paths), then '\' and '"' escaped
  LPlain := TUtils.StripLongPathPrefix(APath).Replace('\', '/');
  Result := LPlain.Replace('\', '\\').Replace('"', '\"');
end;

class function TPCCppWriter.DoIsInsideLine(const AVerbatim: TPCVerbatim; const ALine: UInt64): Boolean;
var
  LLine: UInt64;
begin
  // A line that starts inside a C++ token or comment of the verbatim (R23)
  Result := False;
  for LLine in AVerbatim.InsideLines do
  begin
    if LLine = ALine then
      Exit(True);
  end;
end;

class function TPCCppWriter.DoEndsInSplice(const AText: TPCSourceText; const AStart: Int64;
  const AEnd: Int64): Boolean;
var
  LP: Int64;
begin
  // The line [AStart, AEnd) ends in a splice when its last '\' starts one
  // whose newline is the line's own (SpliceNewlineOffset: the one splice test)
  LP := AEnd - 1;
  while (LP >= AStart) and (AText.ByteAt(LP) <> Ord('\')) do
    Dec(LP);
  Result := (LP >= AStart) and (AText.SpliceNewlineOffset(LP) = AEnd);
end;

procedure TPCCppWriter.Init(const AOutFile: TPCOutFile; const ASourcePath: string);
begin
  FOutFile := AOutFile;
  FPathText := EscapePath(ASourcePath);
  FStream.Clear();
  FLines.Clear();
  FSourceLine := 0;
  FLineOpen := False;
  FLineClosed := False;
  FAtLineStart := True;
  FBorrowed := 0;
  FLineEnd.Clear();
  FResumeCol := 1;
end;

procedure TPCCppWriter.SetPeer(const APeer: TPCCppWriter);
begin
  FPeer := APeer;
end;

function TPCCppWriter.LineEnd(const ALine: UInt64): UInt64;
begin
  if not FLineEnd.TryGetValue(ALine, Result) then
    Result := 1;
end;

procedure TPCCppWriter.DoAppend(const ABytes: TBytes);
begin
  if Length(ABytes) > 0 then
  begin
    FStream.WriteBuffer(ABytes[0], Length(ABytes));
    FAtLineStart := ABytes[High(ABytes)] = PC_CWR_LF;
  end;
end;

procedure TPCCppWriter.DoEndPhysicalLine();
begin
  // Terminates the last physical line if it has no LF yet
  if not FAtLineStart then
  begin
    FStream.WriteBuffer(PC_CWR_LF, 1);
    FAtLineStart := True;
  end;
end;

procedure TPCCppWriter.DoStartLine(const AWithDirective: Boolean);
var
  LLine: TPCWriterLine;
begin
  // A new C++ text line for FSourceLine, preceded by its #line unless the
  // caller counted it (a verbatim splice continuation or inside line)
  DoEndPhysicalLine();
  if AWithDirective then
  begin
    DoAppend(DoUtf8(Format('#line %d "%s"', [FSourceLine, FPathText])));
    DoEndPhysicalLine();
    LLine.SourceLine := 0;
    LLine.Bytes := 0;
    LLine.IsText := False;
    FLines.Add(LLine);
  end;
  // This file's own text already on the .pcpp line (a line resumed after
  // ReturnToSourceLine): the new C++ line's text starts past it
  FResumeCol := LineEnd(FSourceLine);
  LLine.SourceLine := FSourceLine;
  LLine.Bytes := 0;
  LLine.IsText := True;
  FLines.Add(LLine);
  FLineOpen := True;
  // An empty text line still exists: the next start writes its LF
  FAtLineStart := False;
end;

procedure TPCCppWriter.DoEnsureLine();
begin
  if FLineClosed then
    raise EInvalidOpException.CreateFmt(RSCwrLineClosed, [FSourceLine]);
  if FSourceLine = 0 then
    raise EInvalidOpException.Create(RSCwrLineZero);
  if not FLineOpen then
    DoStartLine(True);
end;

function TPCCppWriter.DoCurrentCol(): UInt64;
begin
  // The column of the next byte on the open line
  Result := FLines[FLines.Count - 1].Bytes + 1;
end;

procedure TPCCppWriter.DoRecordSpan(const ANode: TPCNode; const ALineIndex: Integer; const AStartCol: UInt64;
  const AEndCol: UInt64);
var
  LSpan: TPCEmitSpan;
begin
  if (ANode = nil) or (AEndCol <= AStartCol) or (FBorrowed > 0) then
    Exit;
  LSpan.OutFile := FOutFile;
  LSpan.CppLine := UInt64(ALineIndex) + 1;
  LSpan.SourceLine := FLines[ALineIndex].SourceLine;
  LSpan.StartCol := AStartCol;
  LSpan.EndCol := AEndCol;
  ANode.AddEmitSpan(LSpan);
end;

procedure TPCCppWriter.DoPadToPeer(const AMayPad: Boolean);
var
  LNeed: UInt64;
  LCol: UInt64;
  LPad: TBytes;
  LLine: TPCWriterLine;
begin
  // V1: text on this .pcpp line starts past the peer's text on it, and past
  // this file's own earlier text on it (a resumed line, FResumeCol). A line
  // that must start at column 1 (a # line, a splice continuation, a line
  // inside a raw string or comment: spaces there would change the C++) has
  // no such text by construction; text there is an invariant violation
  LNeed := FResumeCol;
  if (FPeer <> nil) and (FPeer.LineEnd(FLines[FLines.Count - 1].SourceLine) > LNeed) then
    LNeed := FPeer.LineEnd(FLines[FLines.Count - 1].SourceLine);
  LCol := DoCurrentCol();
  if LCol >= LNeed then
    Exit;
  if not AMayPad then
    raise EInvalidOpException.CreateFmt(RSCwrPeerColumns, [FLines[FLines.Count - 1].SourceLine]);
  SetLength(LPad, LNeed - LCol);
  FillChar(LPad[0], Length(LPad), Ord(' '));
  DoAppend(LPad);
  LLine := FLines[FLines.Count - 1];
  LLine.Bytes := LLine.Bytes + UInt64(Length(LPad));
  FLines[FLines.Count - 1] := LLine;
end;

procedure TPCCppWriter.DoAppendText(const ABytes: TBytes; const ANode: TPCNode; const AMayPad: Boolean);
var
  LLine: TPCWriterLine;
  LStartCol: UInt64;
begin
  // ABytes on the open line (past the peer's text on its .pcpp line): the
  // line's byte count, the node's span and the line's end for the peer
  if Length(ABytes) > 0 then
    DoPadToPeer(AMayPad);
  LStartCol := DoCurrentCol();
  DoAppend(ABytes);
  // ABytes never holds a newline: the open line stays open (also when empty)
  FAtLineStart := False;
  LLine := FLines[FLines.Count - 1];
  LLine.Bytes := LLine.Bytes + UInt64(Length(ABytes));
  FLines[FLines.Count - 1] := LLine;
  if Length(ABytes) > 0 then
    FLineEnd.AddOrSetValue(LLine.SourceLine, LLine.Bytes + 1);
  DoRecordSpan(ANode, FLines.Count - 1, LStartCol, LStartCol + UInt64(Length(ABytes)));
end;

procedure TPCCppWriter.WritePreamble(const ALine: string);
var
  LLine: TPCWriterLine;
  LBytes: TBytes;
begin
  if FSourceLine <> 0 then
    raise EInvalidOpException.Create(RSCwrPreambleLate);
  if ALine.Contains(#10) or ALine.Contains(#13) then
    raise EInvalidOpException.CreateFmt(RSCwrLineBreak, [FSourceLine]);
  LBytes := DoUtf8(ALine);
  DoEndPhysicalLine();
  DoAppend(LBytes);
  DoEndPhysicalLine();
  LLine.SourceLine := 0;
  LLine.Bytes := UInt64(Length(LBytes));
  LLine.IsText := False;
  FLines.Add(LLine);
end;

procedure TPCCppWriter.SetSourceLine(const ALine: UInt64);
begin
  if ALine = 0 then
    raise EInvalidOpException.Create(RSCwrLineZero);
  if ALine < FSourceLine then
    raise EInvalidOpException.CreateFmt(RSCwrLineBack, [ALine, FSourceLine]);
  if ALine = FSourceLine then
    Exit;
  FSourceLine := ALine;
  FLineOpen := False;
  FLineClosed := False;
end;

procedure TPCCppWriter.ReturnToSourceLine(const ALine: UInt64);
begin
  // Strictly back: going forward is SetSourceLine's. The line's next text
  // starts a new C++ line (DoStartLine pads it past any text it holds)
  if ALine = 0 then
    raise EInvalidOpException.Create(RSCwrLineZero);
  if ALine >= FSourceLine then
    raise EInvalidOpException.CreateFmt(RSCwrLineNotBack, [ALine, FSourceLine]);
  FSourceLine := ALine;
  FLineOpen := False;
  FLineClosed := False;
end;

procedure TPCCppWriter.WriteText(const AText: string; const ANode: TPCNode);
begin
  if AText = '' then
    Exit;
  if AText.Contains(#10) or AText.Contains(#13) then
    raise EInvalidOpException.CreateFmt(RSCwrLineBreak, [FSourceLine]);
  DoEnsureLine();
  DoAppendText(DoUtf8(AText), ANode, True);
end;

function TPCCppWriter.Mark(): TPCWriterMark;
begin
  // On an open line: the next byte there; otherwise the next line opened
  if FLineOpen then
  begin
    Result.LineIndex := FLines.Count - 1;
    Result.Col := DoCurrentCol();
  end
  else
  begin
    Result.LineIndex := FLines.Count;
    Result.Col := 1;
  end;
end;

procedure TPCCppWriter.CloseSpan(const AMark: TPCWriterMark; const ANode: TPCNode);
var
  LIndex: Integer;
  LStartCol: UInt64;
begin
  // First text line from the mark's column, every later one from column 1,
  // each up to its last byte (the current line: written so far)
  for LIndex := AMark.LineIndex to FLines.Count - 1 do
  begin
    if not FLines[LIndex].IsText then
      Continue;
    if LIndex = AMark.LineIndex then
      LStartCol := AMark.Col
    else
      LStartCol := 1;
    DoRecordSpan(ANode, LIndex, LStartCol, FLines[LIndex].Bytes + 1);
  end;
end;

procedure TPCCppWriter.WriteVerbatim(const AVerbatim: TPCVerbatim; const ANode: TPCNode);
var
  LBytes: TBytes;
  LText: TPCSourceText;
  LSize: Int64;
  LStart: Int64;
  LEnd: Int64;
  LIndex: UInt64;
  LSplice: Boolean;
  LMayPad: Boolean;
  LLineBytes: TBytes;
begin
  // Line k of Text is .pcpp line Range.StartLine + k, copied byte for byte.
  // Line 0 continues the current C++ line; a later line starts its own, with
  // a #line unless the line before ended in a splice or it is an inside line
  LBytes := DoUtf8(AVerbatim.Text);
  SetSourceLine(AVerbatim.Range.StartLine);
  if (AVerbatim.VerbatimKind = vkPreproc) and FLineOpen and (DoCurrentCol() > 1) then
    raise EInvalidOpException.CreateFmt(RSCwrPreprocMidLine, [FSourceLine]);
  LText := TPCSourceText.Create();
  try
    LText.Init(LBytes, '');
    LSize := Length(LBytes);
    LStart := 0;
    LIndex := 0;
    LSplice := False;
    while True do
    begin
      // The line's bytes: up to its newline (the one newline test, SourceText)
      LEnd := LStart;
      while (LEnd < LSize) and (LText.NewlineLength(LEnd) = 0) do
        Inc(LEnd);
      // A line may move right past the peer's text (V1) only where spaces
      // in front change nothing: not a # line's first line, not a line
      // counted without a #line (splice continuation, inside line)
      if LIndex = 0 then
      begin
        DoEnsureLine();
        LMayPad := AVerbatim.VerbatimKind <> vkPreproc;
      end
      else
      begin
        SetSourceLine(AVerbatim.Range.StartLine + LIndex);
        LMayPad := not (LSplice or DoIsInsideLine(AVerbatim, FSourceLine));
        DoStartLine(LMayPad);
      end;
      LLineBytes := Copy(LBytes, LStart, LEnd - LStart);
      DoAppendText(LLineBytes, ANode, LMayPad);
      if LEnd >= LSize then
        Break;
      LSplice := DoEndsInSplice(LText, LStart, LEnd);
      LStart := LEnd + LText.NewlineLength(LEnd);
      Inc(LIndex);
      // A trailing newline ends the last line: no empty line after it
      if LStart >= LSize then
      begin
        FLineOpen := False;
        FLineClosed := True;
        Break;
      end;
    end;
  finally
    LText.Free();
  end;
  // A # line is always followed by a newline before any other text
  if AVerbatim.VerbatimKind = vkPreproc then
  begin
    FLineOpen := False;
    FLineClosed := True;
  end;
end;

procedure TPCCppWriter.BeginBorrowed();
begin
  Inc(FBorrowed);
end;

procedure TPCCppWriter.EndBorrowed();
begin
  // Every EndBorrowed pairs with a BeginBorrowed (an invariant)
  if FBorrowed <= 0 then
    raise EInvalidOpException.Create(RSCwrBorrowUnbalanced);
  Dec(FBorrowed);
end;

function TPCCppWriter.IsBorrowed(): Boolean;
begin
  Result := FBorrowed > 0;
end;

function TPCCppWriter.SourceLine(): UInt64;
begin
  Result := FSourceLine;
end;

function TPCCppWriter.LineClosed(): Boolean;
begin
  Result := FLineClosed;
end;

function TPCCppWriter.GetBytes(): TBytes;
var
  LCount: Int64;
begin
  LCount := FStream.Size;
  if FAtLineStart then
    SetLength(Result, LCount)
  else
    SetLength(Result, LCount + 1);
  if LCount > 0 then
    Move(FStream.Memory^, Result[0], LCount);
  if not FAtLineStart then
    Result[LCount] := PC_CWR_LF;
end;

function TPCCppWriter.GetText(): string;
begin
  Result := TEncoding.UTF8.GetString(GetBytes());
end;

end.
