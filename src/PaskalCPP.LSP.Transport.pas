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
  PaskalCPP.LSP.Transport - LSP base protocol framing

  Reads and writes LSP messages on a pair of streams: a header block
  (Content-Length, optional Content-Type), an empty line, then the JSON
  body in UTF-8. Adopted from FreeStrike.LSP.Transport (prior art,
  plans\done\PLAN-EDITOR.md E2.1c).

  Dependencies: StdApp.Base
  Notes:
    - The streams are not owned. Stdio, pipes and memory streams all work:
      a short Read is retried until the body is complete.
    - A message with a bad header is skipped (its body read when the
      length is known) and reported as rrMalformed: it has no readable id,
      so it cannot be answered.
===============================================================================}

unit PaskalCPP.LSP.Transport;

interface

uses
  System.SysUtils,
  System.Classes,
  StdApp.Base;

const
  { PC_LSP_HEADER_LIMIT }
  // A header block longer than this (bytes) without its empty line is
  // malformed.
  PC_LSP_HEADER_LIMIT = 8192;

type
  { TPCLspReadResult }
  TPCLspReadResult = (
    rrMessage,        // ABody holds one message
    rrEndOfStream,    // the input ended, before or inside a message
    rrMalformed       // a message with a bad header, skipped
  );

  { TPCLspTransport }
  TPCLspTransport = class(TBaseObject)
  private
    FInput: TStream;
    FOutput: TStream;
    function DoReadByte(out AByte: Byte): Boolean;
    function DoReadChunk(var ABuffer; const ACount: Integer): Integer;
    function DoReadHeader(out AHeader: string): TPCLspReadResult;
    function DoReadBody(const ALength: Integer; out ABytes: TBytes): Boolean;
    procedure DoParseHeader(const AHeader: string; out ALength: Int64;
      out ACharsetOk: Boolean);
  public
    // AInput is read, AOutput written; either may be nil when unused.
    procedure Init(const AInput: TStream; const AOutput: TStream);

    function ReadMessage(out ABody: string): TPCLspReadResult;
    // False when the output cannot be written (the client is gone).
    function WriteMessage(const ABody: string): Boolean;
    // True when input bytes are already waiting, so a ReadMessage would not
    // block: a memory stream with bytes left, a pipe with bytes in it, a
    // file not at its end. Any other stream (a console) answers False.
    function HasPendingInput(): Boolean;
  end;

implementation

uses
  WinApi.Windows;

const
  { PC_LSP_HEADER_LENGTH }
  PC_LSP_HEADER_LENGTH = 'content-length';
  { PC_LSP_HEADER_TYPE }
  PC_LSP_HEADER_TYPE = 'content-type';
  { PC_LSP_CHARSET }
  PC_LSP_CHARSET = 'charset=';

{ TPCLspTransport }

procedure TPCLspTransport.Init(const AInput: TStream; const AOutput: TStream);
begin
  FInput := AInput;
  FOutput := AOutput;
end;

function TPCLspTransport.HasPendingInput(): Boolean;
var
  LAvailable: DWORD;
begin
  // The transport reads straight from the stream (no buffer of its own),
  // so the stream's state is the whole answer
  if FInput = nil then
    Exit(False);

  if FInput is TCustomMemoryStream then
    Exit(FInput.Position < FInput.Size);

  if FInput is THandleStream then
  begin
    LAvailable := 0;
    if PeekNamedPipe(THandleStream(FInput).Handle, nil, 0, nil, @LAvailable, nil) then
      Exit(LAvailable > 0);
  end;

  // A seekable stream (a file): bytes left before its end
  try
    Result := (FInput.Size > 0) and (FInput.Position < FInput.Size);
  except
    // Not seekable: nothing can be known without blocking
    on Exception do
      Result := False;
  end;
end;

function TPCLspTransport.DoReadByte(out AByte: Byte): Boolean;
begin
  AByte := 0;
  Result := DoReadChunk(AByte, 1) = 1;
end;

function TPCLspTransport.DoReadChunk(var ABuffer; const ACount: Integer): Integer;
begin
  // Up to ACount bytes; 0 at the end of the input
  if FInput = nil then
    Exit(0);
  try
    Result := FInput.Read(ABuffer, ACount);
  except
    // A broken pipe reads as the end of the input
    on Exception do
      Result := 0;
  end;
end;

function TPCLspTransport.DoReadHeader(out AHeader: string): TPCLspReadResult;
var
  LBytes: TBytes;
  LCount: Integer;
  LByte: Byte;
begin
  // Bytes up to and including the empty line (CR LF CR LF)
  AHeader := '';
  SetLength(LBytes, PC_LSP_HEADER_LIMIT);
  LCount := 0;
  while True do
  begin
    if not DoReadByte(LByte) then
      Exit(rrEndOfStream);
    if LCount = PC_LSP_HEADER_LIMIT then
      Exit(rrMalformed);
    LBytes[LCount] := LByte;
    Inc(LCount);
    if (LCount >= 4) and (LBytes[LCount - 4] = 13) and
      (LBytes[LCount - 3] = 10) and (LBytes[LCount - 2] = 13) and
      (LBytes[LCount - 1] = 10) then
      Break;
  end;

  // The header block is ASCII
  AHeader := TEncoding.ASCII.GetString(LBytes, 0, LCount - 4);
  Result := rrMessage;
end;

function TPCLspTransport.DoReadBody(const ALength: Integer;
  out ABytes: TBytes): Boolean;
var
  LDone: Integer;
  LRead: Integer;
begin
  // A pipe may return fewer bytes than asked: read until complete
  SetLength(ABytes, ALength);
  LDone := 0;
  while LDone < ALength do
  begin
    LRead := DoReadChunk(ABytes[LDone], ALength - LDone);
    if LRead <= 0 then
      Exit(False);
    Inc(LDone, LRead);
  end;
  Result := True;
end;

procedure TPCLspTransport.DoParseHeader(const AHeader: string;
  out ALength: Int64; out ACharsetOk: Boolean);
var
  LLines: TArray<string>;
  LLine: string;
  LColon: Integer;
  LFieldName: string;
  LValue: string;
  LAt: Integer;
  LCharset: string;
begin
  // Header fields: "Name: value", names case-insensitive. Content-Length
  // is required; a Content-Type charset must be utf-8 ("utf8" accepted)
  ALength := -1;
  ACharsetOk := True;
  LLines := AHeader.Split([#13#10]);
  for LLine in LLines do
  begin
    LColon := LLine.IndexOf(':');
    if LColon < 0 then
      Continue;
    LFieldName := LLine.Substring(0, LColon).Trim().ToLower();
    LValue := LLine.Substring(LColon + 1).Trim();

    if LFieldName = PC_LSP_HEADER_LENGTH then
    begin
      if not TryStrToInt64(LValue, ALength) then
        ALength := -1;
    end
    else if LFieldName = PC_LSP_HEADER_TYPE then
    begin
      LAt := LValue.ToLower().IndexOf(PC_LSP_CHARSET);
      if LAt >= 0 then
      begin
        LCharset := LValue.Substring(LAt + Length(PC_LSP_CHARSET));
        LColon := LCharset.IndexOf(';');
        if LColon >= 0 then
          LCharset := LCharset.Substring(0, LColon);
        LCharset := LCharset.Trim().DeQuotedString('"').ToLower();
        ACharsetOk := (LCharset = 'utf-8') or (LCharset = 'utf8');
      end;
    end;
  end;
end;

function TPCLspTransport.ReadMessage(out ABody: string): TPCLspReadResult;
var
  LHeader: string;
  LLength: Int64;
  LCharsetOk: Boolean;
  LBytes: TBytes;
begin
  ABody := '';
  Result := DoReadHeader(LHeader);
  if Result <> rrMessage then
    Exit;

  DoParseHeader(LHeader, LLength, LCharsetOk);
  if (LLength < 0) or (LLength > MaxInt) then
    Exit(rrMalformed);
  if not DoReadBody(Integer(LLength), LBytes) then
    Exit(rrEndOfStream);
  if not LCharsetOk then
    Exit(rrMalformed);

  try
    ABody := TEncoding.UTF8.GetString(LBytes);
  except
    on EEncodingError do
      Exit(rrMalformed);
  end;
end;

function TPCLspTransport.WriteMessage(const ABody: string): Boolean;
var
  LBody: TBytes;
  LHeader: TBytes;
begin
  if FOutput = nil then
    Exit(False);

  LBody := TEncoding.UTF8.GetBytes(ABody);
  LHeader := TEncoding.ASCII.GetBytes(Format('Content-Length: %d'#13#10#13#10,
    [Length(LBody)]));
  try
    FOutput.WriteBuffer(LHeader, Length(LHeader));
    if Length(LBody) > 0 then
      FOutput.WriteBuffer(LBody, Length(LBody));
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

end.
