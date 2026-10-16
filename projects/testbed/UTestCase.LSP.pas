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
  UTestCase.LSP - language server tests (pcpp --lsp)

  TTestCase suite for the LSP units: transport framing
  (PaskalCPP.LSP.Transport), document positions (PaskalCPP.LSP.Document),
  file URIs (PaskalCPP.LSP.Uri) and scripted sessions of TPCLspServer: the
  messages a client sends are framed into an input stream, the server's
  frames are read back from its output. The documents are editor buffers of
  files that do not exist on disk, so every text the frontend checks comes
  through the source provider (plans\done\PLAN-EDITOR.md E2.1h).

  Dependencies: StdApp.TestCase, StdApp.Base, PaskalCPP.LSP.*
===============================================================================}

unit UTestCase.LSP;

interface

uses
  StdApp.TestCase;

type

  { TPCLspTests }
  TPCLspTests = class(TTestCase)
  private
    procedure DoTestTransport();
    procedure DoTestDocument();
    procedure DoTestUri();
    procedure DoTestLifecycle();
    procedure DoTestDiagnostics();
    procedure DoTestWatchedFiles();
    procedure DoTestWatchRegister();
    procedure DoTestWatchedImport();
    procedure DoTestOpenImport();
    procedure DoTestUnitAlone();
    procedure DoTestColouring();
    procedure DoTestHover();
    procedure DoTestDefinition();
    procedure DoTestInlayHints();
    procedure DoTestRoutineFields();
    procedure DoTestDocumentSymbols();
    procedure DoTestWorkspaceSymbols();
    procedure DoTestCallHierarchy();
    procedure DoTestObjectMembers();
    procedure DoTestObjectUnary();
    procedure DoTestHoverDocs();
    procedure DoTestRecovery();
    procedure DoTestRecoveredTrees();
    procedure DoTestRecoveryInvariant();
    procedure DoTestRecoveryAnswers();
    procedure DoTestCompletion();
    procedure DoTestFormattingCore();
    procedure DoTestFormatting();
    procedure DoTestFormattingServer();
    procedure DoTestJsonReads();
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.Common,
  PaskalCPP.TokenStream,
  PaskalCPP.Lexer,
  PaskalCPP.AST,
  PaskalCPP.Parser,
  PaskalCPP.Compiler,
  PaskalCPP.LSP.Transport,
  PaskalCPP.LSP.Document,
  PaskalCPP.LSP.Uri,
  PaskalCPP.LSP.Server,
  PaskalCPP.LSP.Symbols,
  PaskalCPP.LSP.Formatter,
  UTestFrontend;

const
  { PC_LSPT_DIR }
  // The folder the test documents claim to live in; nothing is written there
  PC_LSPT_DIR = 'pcpp-lsp-test-nofiles';

type
  { TLspPipeInput }
  // An input stream the transport cannot see ahead in (no seek, no pipe
  // peek), as stdin from a console: the server flushes its diagnostics after
  // every message instead of waiting for the end of the input
  TLspPipeInput = class(TStream)
  private
    FBytes: TBytes;
    FPos: Integer;
    FActionAt: Integer;   // byte offset of the message AAction runs before; -1 = none
    FAction: TProc;
  public
    constructor Create(const ABytes: TBytes);
    // AAction runs once, when the server first reads at AAt (a message's
    // first byte): every message before it was read, handled and checked
    procedure SetAction(const AAt: Integer; const AAction: TProc);
    function Read(var ABuffer; ACount: Longint): Longint; override;
    function Write(const ABuffer; ACount: Longint): Longint; override;
    function Seek(const AOffset: Int64; AOrigin: TSeekOrigin): Int64; override;
  end;

  { TLspSession }
  // One scripted session: the messages, the server's replies
  TLspSession = record
    Input: TStringList;          // JSON bodies, in order
    Output: TList<TJSONObject>;  // what the server sent, parsed; owned
    ExitCode: Integer;
  end;

{ TLspPipeInput }

constructor TLspPipeInput.Create(const ABytes: TBytes);
begin
  inherited Create();
  FBytes := ABytes;
  FPos := 0;
  FActionAt := -1;
  FAction := nil;
end;

procedure TLspPipeInput.SetAction(const AAt: Integer; const AAction: TProc);
begin
  FActionAt := AAt;
  FAction := AAction;
end;

function TLspPipeInput.Read(var ABuffer; ACount: Longint): Longint;
var
  LAction: TProc;
begin
  // At the action's message: the server asks for it only after the ones
  // before were handled (a pipe: a check after each), so the action runs now
  if Assigned(FAction) and (FPos >= FActionAt) then
  begin
    LAction := FAction;
    FAction := nil;
    LAction();
  end;
  Result := Length(FBytes) - FPos;
  if Result > ACount then
    Result := ACount;
  // Never read past the action's message in one go: it must run between
  if Assigned(FAction) and (FPos + Result > FActionAt) then
    Result := FActionAt - FPos;
  if Result > 0 then
  begin
    Move(FBytes[FPos], ABuffer, Result);
    Inc(FPos, Result);
  end
  else
    Result := 0;
end;

function TLspPipeInput.Write(const ABuffer; ACount: Longint): Longint;
begin
  raise EStreamError.Create('read only');
end;

function TLspPipeInput.Seek(const AOffset: Int64; AOrigin: TSeekOrigin): Int64;
begin
  raise EStreamError.Create('not seekable');
end;

{ Frame }
function Frame(const ABody: string): TBytes;
var
  LBody: TBytes;
begin
  LBody := TEncoding.UTF8.GetBytes(ABody);
  Result := TEncoding.ASCII.GetBytes(Format('Content-Length: %d'#13#10#13#10,
    [Length(LBody)])) + LBody;
end;

{ JsonText }
function JsonText(const AText: string): string;
var
  LValue: TJSONString;
begin
  // AText as a JSON string literal (quotes and escapes)
  LValue := TJSONString.Create(AText);
  try
    Result := LValue.ToJSON();
  finally
    LValue.Free();
  end;
end;

{ TestFile }
function TestFile(const AName: string): string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetTempPath(), PC_LSPT_DIR), AName);
end;

{ OpenMessage }
function OpenMessage(const AFilename: string; const AText: string): string;
begin
  Result := Format('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":' +
    '{"textDocument":{"uri":%s,"languageId":"pcpp","version":1,"text":%s}}}',
    [JsonText(TPCLspUri.FromFilename(AFilename)), JsonText(AText)]);
end;

{ ChangeMessage }
function ChangeMessage(const AFilename: string; const AVersion: Integer;
  const AText: string): string;
begin
  // Full sync, as the editor sends (renderer.js scheduleLspChange)
  Result := Format('{"jsonrpc":"2.0","method":"textDocument/didChange","params":' +
    '{"textDocument":{"uri":%s,"version":%d},"contentChanges":[{"text":%s}]}}',
    [JsonText(TPCLspUri.FromFilename(AFilename)), AVersion, JsonText(AText)]);
end;

const
  { PC_LSPT_INITIALIZE }
  PC_LSPT_INITIALIZE = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}';
  { PC_LSPT_INITIALIZED }
  PC_LSPT_INITIALIZED = '{"jsonrpc":"2.0","method":"initialized","params":{}}';
  { PC_LSPT_SHUTDOWN }
  PC_LSPT_SHUTDOWN = '{"jsonrpc":"2.0","id":99,"method":"shutdown"}';
  { PC_LSPT_EXIT }
  PC_LSPT_EXIT = '{"jsonrpc":"2.0","method":"exit"}';

{ RunSession }
// Feeds ABodies to a fresh server; its replies, parsed, in ASession.Output.
// AAllAtOnce: the input is a memory stream the transport sees ahead in, so
// every message is read before the first diagnostics check (an editor's
// burst: a change and a request before the server is idle); otherwise a
// pipe-like stream (a check after every message). AAction (pipe only) runs
// once before the server reads message AActionBefore (0-based): what happens
// on disk between two messages (a build writing a file)
procedure RunSession(const ABodies: array of string; var ASession: TLspSession;
  const AAllAtOnce: Boolean = False; const AActionBefore: Integer = -1;
  const AAction: TProc = nil);
var
  LBytes: TBytes;
  LBody: string;
  LActionAt: Integer;
  LIndex: Integer;
  LInput: TStream;
  LOutput: TMemoryStream;
  LTransport: TPCLspTransport;
  LReader: TPCLspTransport;
  LServer: TPCLspServer;
  LText: string;
  LValue: TJSONValue;
begin
  LBytes := nil;
  LActionAt := -1;
  LIndex := 0;
  for LBody in ABodies do
  begin
    if LIndex = AActionBefore then
      LActionAt := Length(LBytes);
    LBytes := LBytes + Frame(LBody);
    Inc(LIndex);
  end;

  if AAllAtOnce then
  begin
    LInput := TMemoryStream.Create();
    if Length(LBytes) > 0 then
      LInput.WriteBuffer(LBytes[0], Length(LBytes));
    LInput.Position := 0;
  end
  else
  begin
    LInput := TLspPipeInput.Create(LBytes);
    if Assigned(AAction) and (LActionAt >= 0) then
      TLspPipeInput(LInput).SetAction(LActionAt, AAction);
  end;
  LOutput := TMemoryStream.Create();
  LTransport := TPCLspTransport.Create();
  LReader := TPCLspTransport.Create();
  LServer := TPCLspServer.Create();
  try
    LTransport.Init(LInput, LOutput);
    ASession.ExitCode := LServer.Run(LTransport);

    // Read the server's frames back
    LOutput.Position := 0;
    LReader.Init(LOutput, nil);
    while LReader.ReadMessage(LText) = rrMessage do
    begin
      LValue := TJSONObject.ParseJSONValue(LText);
      if LValue is TJSONObject then
        ASession.Output.Add(TJSONObject(LValue))
      else
        LValue.Free();
    end;
  finally
    LServer.Free();
    LReader.Free();
    LTransport.Free();
    LOutput.Free();
    LInput.Free();
  end;
end;

{ NewSession }
function NewSession(): TLspSession;
begin
  Result.Input := nil;
  Result.Output := TList<TJSONObject>.Create();
  Result.ExitCode := -1;
end;

{ FreeSession }
procedure FreeSession(var ASession: TLspSession);
var
  LItem: TJSONObject;
begin
  for LItem in ASession.Output do
    LItem.Free();
  ASession.Output.Free();
  ASession.Input.Free();
end;

{ Publishes }
// The publishDiagnostics params of AFilename's URI, in the order sent
function Publishes(const ASession: TLspSession; const AFilename: string): TArray<TJSONObject>;
var
  LItem: TJSONObject;
  LMethod: string;
  LUri: string;
begin
  Result := nil;
  for LItem in ASession.Output do
  begin
    if not (LItem.TryGetValue<string>('method', LMethod) and
      (LMethod = 'textDocument/publishDiagnostics')) then
      Continue;
    if LItem.TryGetValue<string>('params.uri', LUri) and
      (LUri = TPCLspUri.FromFilename(AFilename)) then
      Result := Result + [LItem.GetValue('params') as TJSONObject];
  end;
end;

{ BytesHex }
function BytesHex(const ABytes: TBytes): string;
var
  LByte: Byte;
begin
  Result := '';
  for LByte in ABytes do
    Result := Result + IntToHex(LByte, 2);
end;

{ IntAt }
function IntAt(const AValue: TJSONValue; const APath: string): Integer;
begin
  if not AValue.TryGetValue<Integer>(APath, Result) then
    Result := -1;
end;

{ HoverMessage }
function HoverMessage(const AId: Integer; const AFilename: string; const ALine: Integer;
  const ACharacter: Integer): string;
begin
  Result := Format('{"jsonrpc":"2.0","id":%d,"method":"textDocument/hover","params":' +
    '{"textDocument":{"uri":%s},"position":{"line":%d,"character":%d}}}',
    [AId, JsonText(TPCLspUri.FromFilename(AFilename)), ALine, ACharacter]);
end;

{ HoverValue }
// The markdown of the reply to request AId; '<null>' for a null result,
// '<none>' when no reply carries that id
function HoverValue(const ASession: TLspSession; const AId: Integer): string;
var
  LItem: TJSONObject;
  LResult: TJSONValue;
begin
  Result := '<none>';
  for LItem in ASession.Output do
  begin
    if IntAt(LItem, 'id') <> AId then
      Continue;
    LResult := LItem.GetValue('result');
    if (LResult = nil) or (LResult is TJSONNull) then
      Exit('<null>');
    if not LResult.TryGetValue<string>('contents.value', Result) then
      Result := '<no contents>';
    Exit;
  end;
end;

{ Fenced }
function Fenced(const ALines: string): string;
begin
  Result := '```pcpp'#10 + ALines + #10'```';
end;

{ DefinitionMessage }
function DefinitionMessage(const AId: Integer; const AFilename: string; const ALine: Integer;
  const ACharacter: Integer): string;
begin
  Result := Format('{"jsonrpc":"2.0","id":%d,"method":"textDocument/definition","params":' +
    '{"textDocument":{"uri":%s},"position":{"line":%d,"character":%d}}}',
    [AId, JsonText(TPCLspUri.FromFilename(AFilename)), ALine, ACharacter]);
end;

{ DefinitionText }
// The Location[] replying to request AId as 'file:line:char-line:char' items
// joined by ';' (the file = the uri's last segment); '<null>' for a null
// result, '<none>' when no reply carries that id
function DefinitionText(const ASession: TLspSession; const AId: Integer): string;
var
  LItem: TJSONObject;
  LResult: TJSONValue;
  LLocation: TJSONValue;
  LUri: string;
  LParts: TList<string>;
begin
  Result := '<none>';
  for LItem in ASession.Output do
  begin
    if IntAt(LItem, 'id') <> AId then
      Continue;
    LResult := LItem.GetValue('result');
    if (LResult = nil) or (LResult is TJSONNull) then
      Exit('<null>');
    if not (LResult is TJSONArray) then
      Exit('<not an array>');
    LParts := TList<string>.Create();
    try
      for LLocation in TJSONArray(LResult) do
      begin
        if not LLocation.TryGetValue<string>('uri', LUri) then
          LUri := '?';
        LParts.Add(Format('%s:%d:%d-%d:%d', [Copy(LUri, LastDelimiter('/', LUri) + 1, MaxInt),
          IntAt(LLocation, 'range.start.line'), IntAt(LLocation, 'range.start.character'),
          IntAt(LLocation, 'range.end.line'), IntAt(LLocation, 'range.end.character')]));
      end;
      Result := string.Join(';', LParts.ToArray());
    finally
      LParts.Free();
    end;
    Exit;
  end;
end;

{ InlayMessage }
function InlayMessage(const AId: Integer; const AFilename: string; const AStartLine: Integer;
  const AStartCharacter: Integer; const AEndLine: Integer; const AEndCharacter: Integer): string;
begin
  Result := Format('{"jsonrpc":"2.0","id":%d,"method":"textDocument/inlayHint","params":' +
    '{"textDocument":{"uri":%s},"range":{"start":{"line":%d,"character":%d},' +
    '"end":{"line":%d,"character":%d}}}}',
    [AId, JsonText(TPCLspUri.FromFilename(AFilename)), AStartLine, AStartCharacter,
     AEndLine, AEndCharacter]);
end;

{ InlayText }
// The InlayHint[] replying to request AId as 'line:character:label' items
// joined by ';'; an item whose kind is not 2 (Parameter) or that has no
// paddingRight ends in '!'. '<null>' for a null result, '<none>' when no
// reply carries that id
function InlayText(const ASession: TLspSession; const AId: Integer): string;
var
  LItem: TJSONObject;
  LResult: TJSONValue;
  LHint: TJSONValue;
  LLabel: string;
  LPadding: Boolean;
  LText: string;
  LParts: TList<string>;
begin
  Result := '<none>';
  for LItem in ASession.Output do
  begin
    if IntAt(LItem, 'id') <> AId then
      Continue;
    LResult := LItem.GetValue('result');
    if (LResult = nil) or (LResult is TJSONNull) then
      Exit('<null>');
    if not (LResult is TJSONArray) then
      Exit('<not an array>');
    LParts := TList<string>.Create();
    try
      for LHint in TJSONArray(LResult) do
      begin
        if not LHint.TryGetValue<string>('label', LLabel) then
          LLabel := '?';
        if not LHint.TryGetValue<Boolean>('paddingRight', LPadding) then
          LPadding := False;
        LText := Format('%d:%d:%s', [IntAt(LHint, 'position.line'),
          IntAt(LHint, 'position.character'), LLabel]);
        if (IntAt(LHint, 'kind') <> 2) or not LPadding then
          LText := LText + '!';
        LParts.Add(LText);
      end;
      Result := string.Join(';', LParts.ToArray());
    finally
      LParts.Free();
    end;
    Exit;
  end;
end;

{ CompletionMessage }
// A completion request; ATrigger <> '' sends it as typed (triggerKind 2)
function CompletionMessage(const AId: Integer; const AFilename: string; const ALine: Integer;
  const ACharacter: Integer; const ATrigger: string): string;
begin
  if ATrigger = '' then
    Result := Format('{"jsonrpc":"2.0","id":%d,"method":"textDocument/completion","params":' +
      '{"textDocument":{"uri":%s},"position":{"line":%d,"character":%d}}}',
      [AId, JsonText(TPCLspUri.FromFilename(AFilename)), ALine, ACharacter])
  else
    Result := Format('{"jsonrpc":"2.0","id":%d,"method":"textDocument/completion","params":' +
      '{"textDocument":{"uri":%s},"position":{"line":%d,"character":%d},' +
      '"context":{"triggerKind":2,"triggerCharacter":%s}}}',
      [AId, JsonText(TPCLspUri.FromFilename(AFilename)), ALine, ACharacter, JsonText(ATrigger)]);
end;

{ CompletionList }
// The items of the CompletionList replying to request AId; nil with ANull
// True for a null result (or no reply)
function CompletionList(const ASession: TLspSession; const AId: Integer;
  out ANull: Boolean): TJSONArray;
var
  LItem: TJSONObject;
  LResult: TJSONValue;
begin
  Result := nil;
  ANull := True;
  for LItem in ASession.Output do
  begin
    if IntAt(LItem, 'id') <> AId then
      Continue;
    LResult := LItem.GetValue('result');
    if (LResult = nil) or (LResult is TJSONNull) then
      Exit;
    ANull := False;
    if not LResult.TryGetValue<TJSONArray>('items', Result) then
      Result := nil;
    Exit;
  end;
end;

{ CompletionLabels }
// The labels of the reply to AId in reply order, joined by ','; '<null>'
// for a null result
function CompletionLabels(const ASession: TLspSession; const AId: Integer): string;
var
  LItems: TJSONArray;
  LNull: Boolean;
  LValue: TJSONValue;
  LLabel: string;
  LParts: TList<string>;
begin
  LItems := CompletionList(ASession, AId, LNull);
  if LNull then
    Exit('<null>');
  if LItems = nil then
    Exit('<no items>');
  LParts := TList<string>.Create();
  try
    for LValue in LItems do
    begin
      if not LValue.TryGetValue<string>('label', LLabel) then
        LLabel := '?';
      LParts.Add(LLabel);
    end;
    Result := string.Join(',', LParts.ToArray());
  finally
    LParts.Free();
  end;
end;

{ CompletionItem }
// The item labelled ALabel in the reply to AId as
// 'kind|group|detail|insertText|insertTextFormat' ('' for an absent
// field); '<missing>' when no item has that label. sortText must be the
// group + the item's 5-digit position in the reply (the server's rank);
// otherwise the whole sortText is reported with '!rank' (a failed check)
function CompletionItem(const ASession: TLspSession; const AId: Integer; const ALabel: string): string;
var
  LItems: TJSONArray;
  LNull: Boolean;
  LValue: TJSONValue;
  LText: string;
  LSort: string;
  LDetail: string;
  LInsert: string;
  LFormat: string;
  LIndex: Integer;
begin
  Result := '<missing>';
  LItems := CompletionList(ASession, AId, LNull);
  if LItems = nil then
    Exit;
  LIndex := -1;
  for LValue in LItems do
  begin
    Inc(LIndex);
    if (not LValue.TryGetValue<string>('label', LText)) or (LText <> ALabel) then
      Continue;
    if not LValue.TryGetValue<string>('sortText', LSort) then
      LSort := '';
    if (LSort.Length = 6) and (LSort.Substring(1) = Format('%.5d', [LIndex])) then
      LSort := LSort.Substring(0, 1)
    else
      LSort := LSort + '!rank';
    if not LValue.TryGetValue<string>('detail', LDetail) then
      LDetail := '';
    if not LValue.TryGetValue<string>('insertText', LInsert) then
      LInsert := '';
    LFormat := '';
    if IntAt(LValue, 'insertTextFormat') >= 0 then
      LFormat := IntToStr(IntAt(LValue, 'insertTextFormat'));
    Exit(Format('%d|%s|%s|%s|%s', [IntAt(LValue, 'kind'), LSort, LDetail, LInsert, LFormat]));
  end;
end;

{ SymbolsMessage }
function SymbolsMessage(const AId: Integer; const AFilename: string): string;
begin
  Result := Format('{"jsonrpc":"2.0","id":%d,"method":"textDocument/documentSymbol","params":' +
    '{"textDocument":{"uri":%s}}}', [AId, JsonText(TPCLspUri.FromFilename(AFilename))]);
end;

{ SymbolText }
// One DocumentSymbol as 'name/kind/detail/selection line:start-end/range
// start line-end line', its children in [ ] joined by ','
function SymbolText(const ASymbol: TJSONValue): string;
var
  LName: string;
  LDetail: string;
  LChildren: TJSONValue;
  LChild: TJSONValue;
  LParts: TList<string>;
begin
  if not ASymbol.TryGetValue<string>('name', LName) then
    LName := '?';
  if not ASymbol.TryGetValue<string>('detail', LDetail) then
    LDetail := '';
  Result := Format('%s/%d/%s/%d:%d-%d/%d-%d', [LName, IntAt(ASymbol, 'kind'), LDetail,
    IntAt(ASymbol, 'selectionRange.start.line'), IntAt(ASymbol, 'selectionRange.start.character'),
    IntAt(ASymbol, 'selectionRange.end.character'),
    IntAt(ASymbol, 'range.start.line'), IntAt(ASymbol, 'range.end.line')]);
  // A selection on another line than its start is shown in full
  if IntAt(ASymbol, 'selectionRange.end.line') <> IntAt(ASymbol, 'selectionRange.start.line') then
    Result := Result + '!sel-end-line=' + IntToStr(IntAt(ASymbol, 'selectionRange.end.line'));

  LChildren := (ASymbol as TJSONObject).GetValue('children');
  if LChildren is TJSONArray then
  begin
    LParts := TList<string>.Create();
    try
      for LChild in TJSONArray(LChildren) do
        LParts.Add(SymbolText(LChild));
      Result := Result + '[' + string.Join(',', LParts.ToArray()) + ']';
    finally
      LParts.Free();
    end;
  end;
end;

{ SymbolKindText }
// One DocumentSymbol as 'name/kind/detail', its children in [ ] joined by
// ',' (PLAN-OBJECT O14: what a member kind lists as, without ranges)
function SymbolKindText(const ASymbol: TJSONValue): string;
var
  LName: string;
  LDetail: string;
  LChildren: TJSONValue;
  LChild: TJSONValue;
  LParts: TList<string>;
begin
  if not ASymbol.TryGetValue<string>('name', LName) then
    LName := '?';
  if not ASymbol.TryGetValue<string>('detail', LDetail) then
    LDetail := '';
  Result := Format('%s/%d/%s', [LName, IntAt(ASymbol, 'kind'), LDetail]);
  LChildren := (ASymbol as TJSONObject).GetValue('children');
  if LChildren is TJSONArray then
  begin
    LParts := TList<string>.Create();
    try
      for LChild in TJSONArray(LChildren) do
        LParts.Add(SymbolKindText(LChild));
      Result := Result + '[' + string.Join(',', LParts.ToArray()) + ']';
    finally
      LParts.Free();
    end;
  end;
end;

{ SymbolKindsText }
// SymbolsText with SymbolKindText per entry
function SymbolKindsText(const ASession: TLspSession; const AId: Integer): string;
var
  LItem: TJSONObject;
  LResult: TJSONValue;
  LSymbol: TJSONValue;
  LParts: TList<string>;
begin
  Result := '<none>';
  for LItem in ASession.Output do
  begin
    if IntAt(LItem, 'id') <> AId then
      Continue;
    LResult := LItem.GetValue('result');
    if not (LResult is TJSONArray) then
      Exit('<not an array>');
    LParts := TList<string>.Create();
    try
      for LSymbol in TJSONArray(LResult) do
        LParts.Add(SymbolKindText(LSymbol));
      Result := string.Join(';', LParts.ToArray());
    finally
      LParts.Free();
    end;
    Exit;
  end;
end;

{ SymbolsText }
// The DocumentSymbol[] replying to request AId, top-level entries joined by
// ';'; '<null>' for a null result, '<none>' when no reply carries that id
function SymbolsText(const ASession: TLspSession; const AId: Integer): string;
var
  LItem: TJSONObject;
  LResult: TJSONValue;
  LSymbol: TJSONValue;
  LParts: TList<string>;
begin
  Result := '<none>';
  for LItem in ASession.Output do
  begin
    if IntAt(LItem, 'id') <> AId then
      Continue;
    LResult := LItem.GetValue('result');
    if (LResult = nil) or (LResult is TJSONNull) then
      Exit('<null>');
    if not (LResult is TJSONArray) then
      Exit('<not an array>');
    LParts := TList<string>.Create();
    try
      for LSymbol in TJSONArray(LResult) do
        LParts.Add(SymbolText(LSymbol));
      Result := string.Join(';', LParts.ToArray());
    finally
      LParts.Free();
    end;
    Exit;
  end;
end;

{ WorkspaceSymbolMessage }
function WorkspaceSymbolMessage(const AId: Integer; const AQuery: string): string;
begin
  Result := Format('{"jsonrpc":"2.0","id":%d,"method":"workspace/symbol","params":{"query":%s}}',
    [AId, JsonText(AQuery)]);
end;

{ UriName }
// A uri's last segment (the file name)
function UriName(const AUri: string): string;
begin
  Result := Copy(AUri, LastDelimiter('/', AUri) + 1, MaxInt);
end;

{ WorkspaceSymbolsText }
// The SymbolInformation[] replying to request AId as
// 'name/kind/container@file:line:start-end' items joined by ';' (UTF-16,
// end exclusive); '<null>' for a null result, '<error>' for an error reply,
// '<none>' when no reply carries that id
function WorkspaceSymbolsText(const ASession: TLspSession; const AId: Integer): string;
var
  LItem: TJSONObject;
  LResult: TJSONValue;
  LSymbol: TJSONValue;
  LName: string;
  LContainer: string;
  LUri: string;
  LParts: TList<string>;
begin
  Result := '<none>';
  for LItem in ASession.Output do
  begin
    if IntAt(LItem, 'id') <> AId then
      Continue;
    if LItem.GetValue('error') <> nil then
      Exit('<error>');
    LResult := LItem.GetValue('result');
    if (LResult = nil) or (LResult is TJSONNull) then
      Exit('<null>');
    if not (LResult is TJSONArray) then
      Exit('<not an array>');
    LParts := TList<string>.Create();
    try
      for LSymbol in TJSONArray(LResult) do
      begin
        if not LSymbol.TryGetValue<string>('name', LName) then
          LName := '?';
        if not LSymbol.TryGetValue<string>('containerName', LContainer) then
          LContainer := '';
        if not LSymbol.TryGetValue<string>('location.uri', LUri) then
          LUri := '?';
        LParts.Add(Format('%s/%d/%s@%s:%d:%d-%d', [LName, IntAt(LSymbol, 'kind'), LContainer,
          UriName(LUri), IntAt(LSymbol, 'location.range.start.line'),
          IntAt(LSymbol, 'location.range.start.character'),
          IntAt(LSymbol, 'location.range.end.character')]));
      end;
      Result := string.Join(';', LParts.ToArray());
    finally
      LParts.Free();
    end;
    Exit;
  end;
end;

{ PrepareCallsMessage }
function PrepareCallsMessage(const AId: Integer; const AFilename: string; const ALine: Integer;
  const ACharacter: Integer): string;
begin
  Result := Format('{"jsonrpc":"2.0","id":%d,"method":"textDocument/prepareCallHierarchy",' +
    '"params":{"textDocument":{"uri":%s},"position":{"line":%d,"character":%d}}}',
    [AId, JsonText(TPCLspUri.FromFilename(AFilename)), ALine, ACharacter]);
end;

{ CallItemJson }
// A CallHierarchyItem as a client sends it back (the fields the server
// reads: uri, kind, selectionRange.start); its name's start at (ALine,
// ACharacter)
function CallItemJson(const AFilename: string; const AKind: Integer; const ALine: Integer;
  const ACharacter: Integer): string;
var
  LRange: string;
begin
  LRange := Format('{"start":{"line":%d,"character":%d},"end":{"line":%d,"character":%d}}',
    [ALine, ACharacter, ALine, ACharacter]);
  Result := Format('{"name":"x","kind":%d,"uri":%s,"range":%s,"selectionRange":%s}',
    [AKind, JsonText(TPCLspUri.FromFilename(AFilename)), LRange, LRange]);
end;

{ CallsMessage }
function CallsMessage(const AId: Integer; const AMethod: string; const AItem: string): string;
begin
  Result := Format('{"jsonrpc":"2.0","id":%d,"method":%s,"params":{"item":%s}}',
    [AId, JsonText(AMethod), AItem]);
end;

{ CallItemText }
// One CallHierarchyItem as 'name/kind/detail@file:selection line:start-end/
// range start line-end line'
function CallItemText(const AItem: TJSONValue): string;
var
  LName: string;
  LDetail: string;
  LUri: string;
begin
  if AItem = nil then
    Exit('<no item>');
  if not AItem.TryGetValue<string>('name', LName) then
    LName := '?';
  if not AItem.TryGetValue<string>('detail', LDetail) then
    LDetail := '';
  if not AItem.TryGetValue<string>('uri', LUri) then
    LUri := '?';
  Result := Format('%s/%d/%s@%s:%d:%d-%d/%d-%d', [LName, IntAt(AItem, 'kind'), LDetail,
    UriName(LUri), IntAt(AItem, 'selectionRange.start.line'),
    IntAt(AItem, 'selectionRange.start.character'), IntAt(AItem, 'selectionRange.end.character'),
    IntAt(AItem, 'range.start.line'), IntAt(AItem, 'range.end.line')]);
end;

{ PrepareCallsText }
// The CallHierarchyItem[] replying to request AId joined by ';'; '<null>'
// for a null result, '<none>' when no reply carries that id
function PrepareCallsText(const ASession: TLspSession; const AId: Integer): string;
var
  LItem: TJSONObject;
  LResult: TJSONValue;
  LEntry: TJSONValue;
  LParts: TList<string>;
begin
  Result := '<none>';
  for LItem in ASession.Output do
  begin
    if IntAt(LItem, 'id') <> AId then
      Continue;
    LResult := LItem.GetValue('result');
    if (LResult = nil) or (LResult is TJSONNull) then
      Exit('<null>');
    if not (LResult is TJSONArray) then
      Exit('<not an array>');
    LParts := TList<string>.Create();
    try
      for LEntry in TJSONArray(LResult) do
        LParts.Add(CallItemText(LEntry));
      Result := string.Join(';', LParts.ToArray());
    finally
      LParts.Free();
    end;
    Exit;
  end;
end;

{ CallsText }
// The CallHierarchyIncomingCall[] / OutgoingCall[] replying to request AId:
// each call's AEnd item ('from' / 'to', CallItemText) then its fromRanges as
// <line:start-end,...>, joined by ';'; '<null>' / '<none>' as above,
// '<error>' for an error reply
function CallsText(const ASession: TLspSession; const AId: Integer; const AEnd: string): string;
var
  LItem: TJSONObject;
  LResult: TJSONValue;
  LCall: TJSONValue;
  LRanges: TJSONValue;
  LRange: TJSONValue;
  LParts: TList<string>;
  LSites: TList<string>;
begin
  Result := '<none>';
  for LItem in ASession.Output do
  begin
    if IntAt(LItem, 'id') <> AId then
      Continue;
    if LItem.GetValue('error') <> nil then
      Exit('<error>');
    LResult := LItem.GetValue('result');
    if (LResult = nil) or (LResult is TJSONNull) then
      Exit('<null>');
    if not (LResult is TJSONArray) then
      Exit('<not an array>');
    LParts := TList<string>.Create();
    LSites := TList<string>.Create();
    try
      for LCall in TJSONArray(LResult) do
      begin
        LSites.Clear();
        LRanges := (LCall as TJSONObject).GetValue('fromRanges');
        if LRanges is TJSONArray then
          for LRange in TJSONArray(LRanges) do
            LSites.Add(Format('%d:%d-%d', [IntAt(LRange, 'start.line'),
              IntAt(LRange, 'start.character'), IntAt(LRange, 'end.character')]));
        LParts.Add(CallItemText((LCall as TJSONObject).GetValue(AEnd)) + '<' +
          string.Join(',', LSites.ToArray()) + '>');
      end;
      Result := string.Join(';', LParts.ToArray());
    finally
      LSites.Free();
      LParts.Free();
    end;
    Exit;
  end;
end;

{ AnalyseRun }
// Analyses AFilename in check mode (the editor's way; its text is ABytes
// when AHasBytes, else the disk's) with the LSP's budget (100). The caller
// owns the compiler (its main module and reports) and frees it with FreeRun
function AnalyseRun(const AFilename: string; const AHasBytes: Boolean;
  const ABytes: TBytes): TPCCompiler;
var
  LPath: string;
  LText: TBytes;
begin
  LPath := AFilename;
  LText := ABytes;
  Result := TPCCompiler.Create();
  Result.SetMaxErrors(100);
  if AHasBytes then
    Result.SetSourceProvider(
      function(const AName: string; out AOut: TBytes): Boolean
      begin
        Result := TUtils.SamePath(AName, LPath);
        if Result then
          AOut := LText;
      end);
  Result.Analyze(LPath);
end;

{ FreeRun }
procedure FreeRun(const ACompiler: TPCCompiler);
begin
  ACompiler.SetSourceProvider(nil);
  ACompiler.Free();
end;

{ InternalErrors }
// The internal-error reports of a run ('; ' joined, '' = none): a crash in
// a phase surfaces as one
function InternalErrors(const AFilename: string; const AHasBytes: Boolean;
  const ABytes: TBytes): string;
var
  LCompiler: TPCCompiler;
  LError: TError;
begin
  Result := '';
  LCompiler := AnalyseRun(AFilename, AHasBytes, ABytes);
  try
    for LError in LCompiler.GetErrors().GetItems() do
      if LError.Code = PC_ERR_CMP_003 then
        Result := Result + LError.Message + '; ';
  finally
    FreeRun(LCompiler);
  end;
end;

type
  { TRecoveryRunVisitor }
  // One run of the recovery corpus: AFilename analysed as ABytes when
  // AHasBytes (a cut), else as the file on disk; ALabel names it in a failure
  TRecoveryRunVisitor = reference to procedure(const AFilename: string;
    const AHasBytes: Boolean; const ABytes: TBytes; const ALabel: string);

{ RecoveryCutFiles }
// The intact files of the corpus: every semantics fixture and every lsp_*
// compliance file
function RecoveryCutFiles(): TArray<string>;
var
  LFiles: TList<string>;
begin
  LFiles := TList<string>.Create();
  try
    LFiles.AddRange(TDirectory.GetFiles(DoProbeDir('sem'), '*.pcpp', TSearchOption.soAllDirectories));
    LFiles.AddRange(TDirectory.GetFiles(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'res\tests'),
      'lsp_*.pcpp'));
    Result := LFiles.ToArray();
  finally
    LFiles.Free();
  end;
end;

{ ForEachRecoveryRun }
// The corpus of recovered_trees and recovery_invariant (PLAN-RECOVERY A11):
// every parser fixture whole (many broken on purpose), and every intact file
// (RecoveryCutFiles) cut at 1/9 .. 8/9 of its bytes, the text while it is
// typed. Returns the number of runs
function ForEachRecoveryRun(const AVisit: TRecoveryRunVisitor): Integer;
const
  // Cuts per intact file
  CCuts = 8;
var
  LFile: string;
  LBytes: TBytes;
  LCut: Integer;
  LLength: Integer;
begin
  Result := 0;
  for LFile in TDirectory.GetFiles(DoProbeDir('par'), '*.pcpp', TSearchOption.soAllDirectories) do
  begin
    Inc(Result);
    AVisit(LFile, False, nil, ExtractFileName(LFile));
  end;
  for LFile in RecoveryCutFiles() do
  begin
    LBytes := TFile.ReadAllBytes(LFile);
    for LCut := 1 to CCuts do
    begin
      LLength := (Length(LBytes) * LCut) div (CCuts + 1);
      Inc(Result);
      AVisit(LFile, True, Copy(LBytes, 0, LLength),
        ExtractFileName(LFile) + ' cut at ' + IntToStr(LLength));
    end;
  end;
end;

{ LexRun }
// The lexer's own tokens of a run's text (no conditional filter), EOF
// excluded, in source order
function LexRun(const ABytes: TBytes; const AFilename: string): TArray<TPCToken>;
var
  LErrors: TErrors;
  LStream: TPCTokenStream;
  LLexer: TPCLexer;
  LTokens: TList<TPCToken>;
  LIndex: Integer;
begin
  LErrors := TErrors.Create();
  LStream := TPCTokenStream.Create();
  LLexer := TPCLexer.Create();
  LTokens := TList<TPCToken>.Create();
  try
    LErrors.SetMaxErrors(1000);
    LLexer.SetErrors(LErrors);
    LLexer.TokenizeBytes(ABytes, AFilename, LStream);
    for LIndex := 0 to LStream.Count() - 1 do
    begin
      if LStream.TokenAt(LIndex).Kind <> tkEOF then
        LTokens.Add(LStream.TokenAt(LIndex));
    end;
    Result := LTokens.ToArray();
  finally
    LTokens.Free();
    LLexer.Free();
    LStream.Free();
    LErrors.Free();
  end;
end;

{ HoldsConditional }
// True when the text holds a conditional directive: the filter removes
// tokens the parser never sees there, so the list-gap rule cannot apply.
// The spellings are PaskalCPP.Conditionals' (PC_CND_*, implementation
// constants there; @target included: the filter takes it too)
function HoldsConditional(const ATokens: TArray<TPCToken>): Boolean;
const
  CSpellings: array[0..7] of string = (
    '@define', '@undef', '@ifdef', '@ifndef', '@elseif', '@else', '@endif', '@target'
  );
var
  LToken: TPCToken;
  LSpelling: string;
begin
  for LToken in ATokens do
  begin
    if LToken.Kind <> tkDirective then
      Continue;
    for LSpelling in CSpellings do
    begin
      if LToken.Spelling = LSpelling then
        Exit(True);
    end;
  end;
  Result := False;
end;

{ FirstTokenFrom }
// Index of the first token starting at or after AOffset (Length = none)
function FirstTokenFrom(const ATokens: TArray<TPCToken>; const AOffset: UInt64): Integer;
var
  LLow: Integer;
  LHigh: Integer;
  LMid: Integer;
begin
  // Binary search: the tokens are in source order
  LLow := 0;
  LHigh := Length(ATokens);
  while LLow < LHigh do
  begin
    LMid := (LLow + LHigh) div 2;
    if ATokens[LMid].Range.StartByteOffset < AOffset then
      LLow := LMid + 1
    else
      LHigh := LMid;
  end;
  Result := LLow;
end;

{ TokenPlace }
function TokenPlace(const AToken: TPCToken): string;
begin
  Result := IntToStr(AToken.Range.StartLine) + ':' + IntToStr(AToken.Range.StartColumn) +
    ' ''' + AToken.Spelling + '''';
end;

{ PlacementLength }
// 3 when a cpp placement starts at ATokens[AIndex] ('cpp' header|source ';',
// BNF.md :802: a module item that sets where C++ goes and has no node of its
// own), else 0
function PlacementLength(const ATokens: TArray<TPCToken>; const AIndex: Integer): Integer;
begin
  Result := 0;
  if AIndex + 2 >= Length(ATokens) then
    Exit;
  if (ATokens[AIndex].Kind = tkKwCpp) and
    ((ATokens[AIndex + 1].Spelling = 'header') or (ATokens[AIndex + 1].Spelling = 'source')) and
    (ATokens[AIndex + 2].Kind = tkSemicolon) then
    Result := 3;
end;

{ AddListGaps }
// PLAN-RECOVERY A11 T1(b): between two consecutive elements of AItems no
// token but a word that opens a declaration block between items ('var',
// 'const', 'type': BNF.md sec 3; 'exported': sec 3 :213, before a
// declaration). Any other token there was dropped without a node: added to
// AGaps as 'AWhere line:col spelling'
procedure AddListGaps(const AItems: TArray<TPCNode>; const ATokens: TArray<TPCToken>;
  const AWhere: string; const AGaps: TList<string>);
var
  LIndex: Integer;
  LToken: Integer;
  LEnd: UInt64;
  LNext: UInt64;
begin
  for LIndex := 0 to Length(AItems) - 2 do
  begin
    LEnd := AItems[LIndex].Range.EndByteOffset;
    LNext := AItems[LIndex + 1].Range.StartByteOffset;
    if LNext < LEnd then
    begin
      AGaps.Add(AWhere + ' order: ' + AItems[LIndex].KindName() + ' ends past the next ' +
        AItems[LIndex + 1].KindName() + ' (' + IntToStr(LEnd) + ' > ' + IntToStr(LNext) + ')');
      Continue;
    end;
    LToken := FirstTokenFrom(ATokens, LEnd);
    while (LToken < Length(ATokens)) and (ATokens[LToken].Range.EndByteOffset <= LNext) do
    begin
      if not (ATokens[LToken].Kind in [tkKwVar, tkKwConst, tkKwType, tkKwExported]) then
        AGaps.Add(AWhere + ' ' + TokenPlace(ATokens[LToken]));
      Inc(LToken);
    end;
  end;
end;

{ StmtNodes }
function StmtNodes(const AList: TList<TPCStmt>): TArray<TPCNode>;
var
  LIndex: Integer;
begin
  SetLength(Result, AList.Count);
  for LIndex := 0 to AList.Count - 1 do
    Result[LIndex] := AList[LIndex];
end;

{ MemberNodes }
function MemberNodes(const AList: TList<TPCMemberItem>): TArray<TPCNode>;
var
  LIndex: Integer;
begin
  SetLength(Result, AList.Count);
  for LIndex := 0 to AList.Count - 1 do
    Result[LIndex] := AList[LIndex];
end;

{ CollectNodes }
// Every node of the tree under ARoot (EnumChildren: owned children only),
// breadth first
procedure CollectNodes(const ARoot: TPCNode; const ANodes: TList<TPCNode>);
var
  LList: TList<TPCNode>;
  LIndex: Integer;
begin
  LList := ANodes;
  LList.Add(ARoot);
  LIndex := 0;
  while LIndex < LList.Count do
  begin
    LList[LIndex].EnumChildren(
      procedure(const AChild: TPCNode)
      begin
        LList.Add(AChild);
      end);
    Inc(LIndex);
  end;
end;

{ KindIn }
function KindIn(const AKind: TPCTokenKind; const AKinds: array of TPCTokenKind): Boolean;
var
  LKind: TPCTokenKind;
begin
  for LKind in AKinds do
  begin
    if LKind = AKind then
      Exit(True);
  end;
  Result := False;
end;

{ AddFrameGaps }
// PLAN-RECOVERY A11 T1(b), frame form: every token inside AOwner's range
// lies inside one of its children's ranges, or is one of AWords (the
// construct's own grammar words, the BNF production cited by the caller),
// or starts one of AExtra (a name token the owner holds as a range). With
// AModule (the owner is the module) also a cpp placement (BNF.md :210 /
// :802, no node). Any other token was dropped without a node. Covers the
// span before the first and after the last element, which the
// between-items form cannot see
procedure AddFrameGaps(const AOwner: TPCNode; const AWords: array of TPCTokenKind;
  const AExtra: array of TSourceRange; const AModule: TPCModule;
  const ATokens: TArray<TPCToken>; const AWhere: string; const AGaps: TList<string>);
var
  LChildren: TList<TPCNode>;
  LList: TList<TPCNode>;
  LChild: Integer;
  LCoverEnd: UInt64;
  LToken: Integer;
  LSkip: Integer;
  LExtra: TSourceRange;
  LAllowed: Boolean;
begin
  LChildren := TList<TPCNode>.Create();
  try
    LList := LChildren;
    AOwner.EnumChildren(
      procedure(const AChild: TPCNode)
      begin
        LList.Add(AChild);
      end);
    // EnumChildren visits list by list (the module: directives, imports,
    // declarations, sections), not in source order: a late import or a
    // repeated section sits elsewhere in the text
    LChildren.Sort(TComparer<TPCNode>.Construct(
      function(const ALeft: TPCNode; const ARight: TPCNode): Integer
      begin
        if ALeft.Range.StartByteOffset < ARight.Range.StartByteOffset then
          Result := -1
        else if ALeft.Range.StartByteOffset > ARight.Range.StartByteOffset then
          Result := 1
        else
          Result := 0;
      end));
    LChild := 0;
    LCoverEnd := 0;
    LToken := FirstTokenFrom(ATokens, AOwner.Range.StartByteOffset);
    while (LToken < Length(ATokens)) and
      (ATokens[LToken].Range.StartByteOffset < AOwner.Range.EndByteOffset) do
    begin
      // The furthest end of every child starting at or before this token
      while (LChild < LChildren.Count) and
        (LChildren[LChild].Range.StartByteOffset <= ATokens[LToken].Range.StartByteOffset) do
      begin
        if LChildren[LChild].Range.EndByteOffset > LCoverEnd then
          LCoverEnd := LChildren[LChild].Range.EndByteOffset;
        Inc(LChild);
      end;
      if ATokens[LToken].Range.StartByteOffset < LCoverEnd then
      begin
        Inc(LToken);
        Continue;
      end;
      if AModule <> nil then
      begin
        LSkip := PlacementLength(ATokens, LToken);
        if LSkip > 0 then
        begin
          Inc(LToken, LSkip);
          Continue;
        end;
      end;
      LAllowed := KindIn(ATokens[LToken].Kind, AWords);
      for LExtra in AExtra do
      begin
        if (not LExtra.IsEmpty()) and
          (LExtra.StartByteOffset = ATokens[LToken].Range.StartByteOffset) then
          LAllowed := True;
      end;
      if not LAllowed then
        AGaps.Add(AWhere + ' ' + TokenPlace(ATokens[LToken]));
      Inc(LToken);
    end;
  finally
    LChildren.Free();
  end;
end;

{ AddMarkedGaps }
procedure AddMarkedGaps(const ANode: TPCNode; const ATokens: TArray<TPCToken>;
  const AGaps: TList<string>);
begin
  // A statement owner the parser reported inside: its range holds what it
  // skipped by design (PLAN-RECOVERY A3, "its Range over everything it
  // consumed"), so only the between-items form applies to its lists
  if ANode is TPCModule then
    AddListGaps(StmtNodes(TPCModule(ANode).Decls), ATokens, 'Module.Decls', AGaps)
  else if ANode is TPCTest then
    AddListGaps(StmtNodes(TPCTest(ANode).Decls), ATokens, 'Test.Decls', AGaps)
  else if ANode is TPCBlock then
    AddListGaps(StmtNodes(TPCBlock(ANode).Stmts), ATokens, 'Block.Stmts', AGaps)
  else if ANode is TPCIf then
  begin
    AddListGaps(StmtNodes(TPCIf(ANode).ThenStmts), ATokens, 'If.ThenStmts', AGaps);
    AddListGaps(StmtNodes(TPCIf(ANode).ElseStmts), ATokens, 'If.ElseStmts', AGaps);
  end
  else if ANode is TPCWhile then
    AddListGaps(StmtNodes(TPCWhile(ANode).Stmts), ATokens, 'While.Stmts', AGaps)
  else if ANode is TPCFor then
    AddListGaps(StmtNodes(TPCFor(ANode).Stmts), ATokens, 'For.Stmts', AGaps)
  else if ANode is TPCRepeat then
    AddListGaps(StmtNodes(TPCRepeat(ANode).Stmts), ATokens, 'Repeat.Stmts', AGaps)
  else if ANode is TPCMatchArm then
    AddListGaps(StmtNodes(TPCMatchArm(ANode).Stmts), ATokens, 'MatchArm.Stmts', AGaps)
  else if ANode is TPCMatch then
    AddListGaps(StmtNodes(TPCMatch(ANode).ElseStmts), ATokens, 'Match.ElseStmts', AGaps)
  else if ANode is TPCGuard then
  begin
    AddListGaps(StmtNodes(TPCGuard(ANode).GuardStmts), ATokens, 'Guard.GuardStmts', AGaps);
    AddListGaps(StmtNodes(TPCGuard(ANode).ExceptStmts), ATokens, 'Guard.ExceptStmts', AGaps);
    AddListGaps(StmtNodes(TPCGuard(ANode).FinallyStmts), ATokens, 'Guard.FinallyStmts', AGaps);
  end;
end;

{ AddNodeGaps }
// T1(b) for ANode. The module, a test and every statement owner (block,
// if, while, for, repeat, match, arm, guard): the frame form, with the
// words of its BNF.md production (sec 1 :47-63, sec 5 :389-420, sec 8 :689;
// var / const / type: a declaration block is a statement, :397, and a
// module item, :208); a marked one: AddMarkedGaps. A routine's declaration
// blocks and the members of a record, an overlay and an anonymous
// aggregate: the between-items form
procedure AddNodeGaps(const ANode: TPCNode; const ATokens: TArray<TPCToken>;
  const AGaps: TList<string>);
begin
  if ANode.IsRecovered and (not (ANode is TPCRoutine)) and (not (ANode is TPCRecordType)) and
    (not (ANode is TPCOverlayType)) and (not (ANode is TPCAnonAggregate)) then
    AddMarkedGaps(ANode, ATokens, AGaps)
  else if ANode is TPCModule then
    AddFrameGaps(ANode, [tkKwModule, tkKwExe, tkKwDll, tkKwLib, tkKwUnit, tkSemicolon,
      tkKwImport, tkComma, tkKwVar, tkKwConst, tkKwType, tkKwExported, tkKwInitialize,
      tkKwFinalize, tkDot], [TPCModule(ANode).NameRange, TPCModule(ANode).EndRange],
      TPCModule(ANode), ATokens, 'Module', AGaps)
  else if ANode is TPCTest then
    // const / type: a block the test may not hold is reported and its items
    // kept (B3), the word is its opener
    AddFrameGaps(ANode, [tkKwTest, tkKwVar, tkKwConst, tkKwType, tkSemicolon], [], nil, ATokens,
      'Test', AGaps)
  else if ANode is TPCBlock then
    AddFrameGaps(ANode, [tkKwBegin, tkKwEnd, tkSemicolon, tkKwVar, tkKwConst, tkKwType], [], nil,
      ATokens, 'Block', AGaps)
  else if ANode is TPCRoutine then
    AddListGaps(StmtNodes(TPCRoutine(ANode).Decls), ATokens, 'Routine.Decls', AGaps)
  else if ANode is TPCIf then
    AddFrameGaps(ANode, [tkKwIf, tkKwThen, tkKwElse, tkKwEnd, tkSemicolon, tkKwVar, tkKwConst,
      tkKwType], [], nil, ATokens, 'If', AGaps)
  else if ANode is TPCWhile then
    AddFrameGaps(ANode, [tkKwWhile, tkKwDo, tkKwEnd, tkSemicolon, tkKwVar, tkKwConst, tkKwType],
      [], nil, ATokens, 'While', AGaps)
  else if ANode is TPCFor then
    AddFrameGaps(ANode, [tkKwFor, tkColonEqual, tkKwTo, tkKwDownto, tkKwDo, tkKwEnd, tkSemicolon,
      tkKwVar, tkKwConst, tkKwType], [TPCFor(ANode).IteratorRange], nil, ATokens, 'For', AGaps)
  else if ANode is TPCRepeat then
    AddFrameGaps(ANode, [tkKwRepeat, tkKwUntil, tkSemicolon, tkKwVar, tkKwConst, tkKwType], [], nil,
      ATokens, 'Repeat', AGaps)
  else if ANode is TPCMatchArm then
    AddFrameGaps(ANode, [tkComma, tkColon, tkKwVar, tkKwConst, tkKwType], [], nil, ATokens,
      'MatchArm', AGaps)
  else if ANode is TPCMatch then
    AddFrameGaps(ANode, [tkKwMatch, tkKwOf, tkKwElse, tkKwEnd, tkSemicolon, tkKwVar, tkKwConst,
      tkKwType], [], nil, ATokens, 'Match', AGaps)
  else if ANode is TPCGuard then
    AddFrameGaps(ANode, [tkKwGuard, tkKwExcept, tkKwFinally, tkKwEnd, tkSemicolon, tkKwVar,
      tkKwConst, tkKwType], [], nil, ATokens, 'Guard', AGaps)
  else if ANode is TPCRecordType then
    AddListGaps(MemberNodes(TPCRecordType(ANode).Members), ATokens, 'Record.Members', AGaps)
  else if ANode is TPCOverlayType then
    AddListGaps(MemberNodes(TPCOverlayType(ANode).Members), ATokens, 'Overlay.Members', AGaps)
  else if ANode is TPCAnonAggregate then
    AddListGaps(MemberNodes(TPCAnonAggregate(ANode).Members), ATokens, 'AnonAggregate.Members', AGaps);
end;

{ NodeHoldsReport }
// PLAN-RECOVERY A11 T1(c): a recovered or error node holds a syntax report
// of its file: inside its range, at the first token after it, or between
// the token before it and its start. AStarts are the reports' start bytes
function NodeHoldsReport(const ANode: TPCNode; const ATokens: TArray<TPCToken>;
  const AStarts: TList<UInt64>): Boolean;
var
  LBefore: Integer;
  LAfter: Integer;
  LLow: UInt64;
  LHigh: UInt64;
  LStart: UInt64;
begin
  // Low bound: the end of the last token before the node
  LBefore := FirstTokenFrom(ATokens, ANode.Range.StartByteOffset) - 1;
  if LBefore >= 0 then
    LLow := ATokens[LBefore].Range.EndByteOffset
  else
    LLow := 0;
  if LLow > ANode.Range.StartByteOffset then
    LLow := ANode.Range.StartByteOffset;
  // High bound: the end of the first token after the node
  LAfter := FirstTokenFrom(ATokens, ANode.Range.EndByteOffset);
  if LAfter < Length(ATokens) then
    LHigh := ATokens[LAfter].Range.EndByteOffset
  else
    LHigh := High(UInt64);
  for LStart in AStarts do
  begin
    if (LStart >= LLow) and (LStart <= LHigh) then
      Exit(True);
  end;
  Result := False;
end;

{ IsRecoveryNode }
function IsRecoveryNode(const ANode: TPCNode): Boolean;
begin
  Result := ANode.IsRecovered or (ANode is TPCErrorStmt) or (ANode is TPCErrorExpr) or
    (ANode is TPCErrorMember);
end;

{ CheckRecoveryRun }
// T1 on one analysed run: AGaps gets the list gaps (b) unless the text holds
// a conditional directive or ACheckGaps is False; AOrphans gets every
// recovered / error node holding no syntax report (c). Neither when the
// budget was reached: the parser stops building and reporting there, by
// design (PLAN-RECOVERY target 3)
procedure CheckRecoveryRun(const ACompiler: TPCCompiler; const AFilename: string;
  const ABytes: TBytes; const ACheckGaps: Boolean; const AGaps: TList<string>;
  const AOrphans: TList<string>);
var
  LModule: TPCModule;
  LTokens: TArray<TPCToken>;
  LNodes: TList<TPCNode>;
  LNode: TPCNode;
  LStarts: TList<UInt64>;
  LError: TError;
begin
  LModule := ACompiler.GetMainModule();
  if LModule = nil then
    Exit;
  LTokens := LexRun(ABytes, AFilename);
  LNodes := TList<TPCNode>.Create();
  LStarts := TList<UInt64>.Create();
  try
    if ACompiler.GetErrors().ReachedMaxErrors() then
      Exit;
    CollectNodes(LModule, LNodes);
    if ACheckGaps and (not HoldsConditional(LTokens)) then
    begin
      for LNode in LNodes do
        AddNodeGaps(LNode, LTokens, AGaps);
    end;
    for LError in ACompiler.GetErrors().GetItems() do
    begin
      if TPCCompiler.IsSyntaxReport(LError) and
        TUtils.SamePath(LError.Range.Filename, AFilename) then
        LStarts.Add(LError.Range.StartByteOffset);
    end;
    for LNode in LNodes do
    begin
      if IsRecoveryNode(LNode) and (not NodeHoldsReport(LNode, LTokens, LStarts)) then
        AOrphans.Add(LNode.KindName() + ' at ' + IntToStr(LNode.Range.StartLine) + ':' +
          IntToStr(LNode.Range.StartColumn));
    end;
  finally
    LStarts.Free();
    LNodes.Free();
  end;
end;

type
  { TTextEdit }
  // The one edit between an intact and a broken text (PLAN-RECOVERY A11 T2):
  // the intact bytes [Start, IntactEnd) became the broken bytes
  // [Start, BrokenEnd); everything else is the same text
  TTextEdit = record
    Start: UInt64;
    IntactEnd: UInt64;
    BrokenEnd: UInt64;
    // An intact offset in the broken text; False = inside the edit
    function MapOffset(const AOffset: UInt64; out AMapped: UInt64): Boolean;
  end;

{ TTextEdit }

function TTextEdit.MapOffset(const AOffset: UInt64; out AMapped: UInt64): Boolean;
begin
  AMapped := 0;
  if AOffset < Start then
  begin
    AMapped := AOffset;
    Exit(True);
  end;
  if AOffset < IntactEnd then
    Exit(False);
  // After the edit: shifted by its length change (either sign)
  AMapped := UInt64(Int64(AOffset) + Int64(BrokenEnd) - Int64(IntactEnd));
  Result := True;
end;

{ FindEdit }
// The longest common prefix and suffix of the two texts leave the edit
function FindEdit(const AIntact: TBytes; const ABroken: TBytes): TTextEdit;
var
  LPrefix: Integer;
  LSuffix: Integer;
  LShorter: Integer;
begin
  LShorter := Length(AIntact);
  if Length(ABroken) < LShorter then
    LShorter := Length(ABroken);
  LPrefix := 0;
  while (LPrefix < LShorter) and (AIntact[LPrefix] = ABroken[LPrefix]) do
    Inc(LPrefix);
  LSuffix := 0;
  while (LSuffix < LShorter - LPrefix) and
    (AIntact[Length(AIntact) - 1 - LSuffix] = ABroken[Length(ABroken) - 1 - LSuffix]) do
    Inc(LSuffix);
  Result.Start := UInt64(LPrefix);
  Result.IntactEnd := UInt64(Length(AIntact) - LSuffix);
  Result.BrokenEnd := UInt64(Length(ABroken) - LSuffix);
end;

{ LineOfOffset }
// The 1-based line of a byte offset (LF ends a line, CRLF included)
function LineOfOffset(const ABytes: TBytes; const AOffset: UInt64): UInt64;
var
  LIndex: Integer;
begin
  Result := 1;
  LIndex := 0;
  while (LIndex < Length(ABytes)) and (UInt64(LIndex) < AOffset) do
  begin
    if ABytes[LIndex] = 10 then
      Inc(Result);
    Inc(LIndex);
  end;
end;

{ RecoveredRanges }
// The ranges of every recovered and error node of AModule's tree
procedure RecoveredRanges(const AModule: TPCModule; const ARanges: TList<TSourceRange>);
var
  LNodes: TList<TPCNode>;
  LNode: TPCNode;
begin
  if AModule = nil then
    Exit;
  LNodes := TList<TPCNode>.Create();
  try
    CollectNodes(AModule, LNodes);
    for LNode in LNodes do
    begin
      if IsRecoveryNode(LNode) then
        ARanges.Add(LNode.Range);
    end;
  finally
    LNodes.Free();
  end;
end;

{ InsideAny }
function InsideAny(const ARanges: TList<TSourceRange>; const AOffset: UInt64): Boolean;
var
  LRange: TSourceRange;
begin
  for LRange in ARanges do
  begin
    if (AOffset >= LRange.StartByteOffset) and (AOffset < LRange.EndByteOffset) then
      Exit(True);
  end;
  Result := False;
end;

{ AnswerHover }
// The hover's declaration lines of a use (as TPCLspServer.DoHoverText: an
// overload set's members once each, else the target's line), ' ; ' joined
function AnswerHover(const AUse: TPCLspUse; const ATarget: TPCNode): string;
var
  LRoutines: TArray<TPCRoutine>;
  LRoutine: TPCRoutine;
  LLines: TList<string>;
  LLine: string;
begin
  Result := '';
  if ATarget = nil then
    Exit;
  LLines := TList<string>.Create();
  try
    LRoutines := TPCLspSymbols.SetOf(AUse, ATarget);
    if Length(LRoutines) > 0 then
    begin
      for LRoutine in LRoutines do
      begin
        LLine := TPCLspSymbols.DeclText(LRoutine);
        if (LLine <> '') and (not LLines.Contains(LLine)) then
          LLines.Add(LLine);
      end;
    end
    else
      LLines.Add(TPCLspSymbols.DeclText(ATarget));
    Result := string.Join(' ; ', LLines.ToArray());
  finally
    LLines.Free();
  end;
end;

{ AnswerDefinition }
// Where a definition request lands (as TPCLspServer.DoLocation: the name
// token, else the node's range), in the broken text's offsets: 'main:N'
// for AFilename (an intact offset mapped through AEdit when AIntact; '' =
// the declaration's name lies in the edit), 'file:N' for another file,
// 'none' for no target
function AnswerDefinition(const ATarget: TPCNode; const AFilename: string;
  const AIntact: Boolean; const AEdit: TTextEdit): string;
var
  LRange: TSourceRange;
  LMapped: UInt64;
begin
  if ATarget = nil then
    Exit('none');
  LRange := TPCLspSymbols.NameRangeOf(ATarget);
  if LRange.StartLine < 1 then
    LRange := ATarget.Range;
  if not TUtils.SamePath(LRange.Filename, AFilename) then
    Exit(LRange.Filename + ':' + IntToStr(LRange.StartByteOffset));
  LMapped := LRange.StartByteOffset;
  if AIntact and (not AEdit.MapOffset(LRange.StartByteOffset, LMapped)) then
    Exit('');
  Result := 'main:' + IntToStr(LMapped);
end;

{ TPCLspTests }

constructor TPCLspTests.Create();
begin
  inherited;

  Title := 'LSP';
  RegisterTest('transport', DoTestTransport);
  RegisterTest('document', DoTestDocument);
  RegisterTest('uri', DoTestUri);
  RegisterTest('lifecycle', DoTestLifecycle);
  RegisterTest('diagnostics', DoTestDiagnostics);
  RegisterTest('watched_files', DoTestWatchedFiles);
  RegisterTest('watch_register', DoTestWatchRegister);
  RegisterTest('watched_import', DoTestWatchedImport);
  RegisterTest('open_import', DoTestOpenImport);
  RegisterTest('unit_alone', DoTestUnitAlone);
  RegisterTest('colouring', DoTestColouring);
  RegisterTest('hover', DoTestHover);
  RegisterTest('definition', DoTestDefinition);
  RegisterTest('inlay_hints', DoTestInlayHints);
  RegisterTest('routine_fields', DoTestRoutineFields);
  RegisterTest('document_symbols', DoTestDocumentSymbols);
  RegisterTest('workspace_symbols', DoTestWorkspaceSymbols);
  RegisterTest('call_hierarchy', DoTestCallHierarchy);
  RegisterTest('object_members', DoTestObjectMembers);
  RegisterTest('object_unary', DoTestObjectUnary);
  RegisterTest('hover_docs', DoTestHoverDocs);
  RegisterTest('recovery', DoTestRecovery);
  RegisterTest('recovered_trees', DoTestRecoveredTrees);
  RegisterTest('recovery_invariant', DoTestRecoveryInvariant);
  RegisterTest('recovery_answers', DoTestRecoveryAnswers);
  RegisterTest('completion', DoTestCompletion);
  RegisterTest('formatting_core', DoTestFormattingCore);
  RegisterTest('formatting', DoTestFormatting);
  RegisterTest('formatting_server', DoTestFormattingServer);
  RegisterTest('json_reads', DoTestJsonReads);
end;

procedure TPCLspTests.Run();
begin
  inherited;
end;

procedure TPCLspTests.DoTestTransport();
var
  LStream: TMemoryStream;
  LTransport: TPCLspTransport;
  LBody: string;
  LBytes: TBytes;
begin
  // Two messages back to back (one with a non-ASCII body), then a frame
  // whose header has no Content-Length, then a body cut short
  LBytes := Frame('{"a":1}') + Frame('{"t":"' + #$00E9#$D83D#$DE00 + '"}') +
    TEncoding.ASCII.GetBytes('X-Other: 1'#13#10#13#10) +
    TEncoding.ASCII.GetBytes('Content-Length: 50'#13#10#13#10'{"cut"');
  LStream := TMemoryStream.Create();
  LTransport := TPCLspTransport.Create();
  try
    LStream.WriteBuffer(LBytes, Length(LBytes));
    LStream.Position := 0;
    LTransport.Init(LStream, nil);
    Check(LTransport.HasPendingInput(), 'pending before the first read');
    Check(LTransport.ReadMessage(LBody) = rrMessage, 'message 1 read');
    Check(LBody = '{"a":1}', 'message 1 body');
    Check(LTransport.ReadMessage(LBody) = rrMessage, 'message 2 read');
    Check(LBody = '{"t":"' + #$00E9#$D83D#$DE00 + '"}', 'message 2 body decoded from UTF-8');
    Check(LTransport.ReadMessage(LBody) = rrMalformed, 'no Content-Length: malformed');
    Check(LTransport.ReadMessage(LBody) = rrEndOfStream, 'body cut short: end of stream');
    Check(not LTransport.HasPendingInput(), 'nothing pending at the end');
  finally
    LTransport.Free();
    LStream.Free();
  end;

  // Written frames: the byte length of the UTF-8 body
  LStream := TMemoryStream.Create();
  LTransport := TPCLspTransport.Create();
  try
    LTransport.Init(nil, LStream);
    Check(LTransport.WriteMessage('"' + #$00E9 + '"'), 'write ok');
    SetLength(LBytes, LStream.Size);
    LStream.Position := 0;
    LStream.ReadBuffer(LBytes, Length(LBytes));
    // Compared as bytes: the header, then '"' C3 A9 '"'
    Check(BytesHex(LBytes) = BytesHex(TEncoding.ASCII.GetBytes('Content-Length: 4'#13#10#13#10) +
      [$22, $C3, $A9, $22]), 'header counts 4 UTF-8 bytes, body as UTF-8 (got ' +
      BytesHex(LBytes) + ')');
  finally
    LTransport.Free();
    LStream.Free();
  end;
end;

procedure TPCLspTests.DoTestDocument();
var
  LDocument: TPCLspDocument;
  LBytes: TBytes;
begin
  // Line 1 = a | e-acute | emoji (2 UTF-16 units) | b, CR LF; line 2 = c
  //   UTF-16 columns (0-based): a 0, e 1, emoji 2, b 4
  //   UTF-8 byte columns (1-based): a 1, e 2, emoji 4, b 8
  LDocument := TPCLspDocument.Create();
  try
    LDocument.Init('file:///x.pcpp', 'x.pcpp', 'pcpp', 1,
      'a' + #$00E9#$D83D#$DE00 + 'b'#13#10'c');
    Check(LDocument.LineCount() = 2, 'two lines');
    Check(LDocument.OffsetAt(0, 4, peUtf16) = 4, 'b at UTF-16 4');
    Check(LDocument.OffsetAt(0, 7, peUtf8) = 4, 'b at UTF-8 7');
    Check(LDocument.OffsetAt(0, 3, peUtf32) = 4, 'b at UTF-32 3');
    Check(LDocument.OffsetAt(0, 3, peUtf16) = 2, 'inside the emoji stays before it');
    Check(LDocument.OffsetAt(0, 99, peUtf16) = 5, 'past the line end: the line end');
    Check(LDocument.OffsetAt(1, 0, peUtf16) = 7, 'line 2 after CR LF');
    Check(LDocument.OffsetAt(5, 0, peUtf16) = 8, 'past the last line: the text end');
    Check(LDocument.ClientCharacter(0, 4, peUtf8) = 7, 'UTF-16 4 -> UTF-8 7');
    Check(LDocument.ByteColumnToColumn(1, 8) = 4, 'byte column 8 -> UTF-16 4');
    Check(LDocument.ByteColumnToColumn(1, 4) = 2, 'byte column 4 -> UTF-16 2');
    Check(LDocument.ByteColumnToColumn(2, 1) = 0, 'line 2 byte 1 -> 0');
    // ByteColumnAt: the inverse (client position -> 1-based byte column)
    Check(LDocument.ByteColumnAt(0, 4, peUtf16) = 8, 'UTF-16 4 (b) -> byte 8');
    Check(LDocument.ByteColumnAt(0, 2, peUtf16) = 4, 'UTF-16 2 (emoji) -> byte 4');
    Check(LDocument.ByteColumnAt(0, 3, peUtf16) = 4, 'inside the emoji -> its first byte 4');
    Check(LDocument.ByteColumnAt(0, 7, peUtf8) = 8, 'UTF-8 7 (b) -> byte 8');
    Check(LDocument.ByteColumnAt(0, 3, peUtf32) = 8, 'UTF-32 3 (b) -> byte 8');
    Check(LDocument.ByteColumnAt(0, 99, peUtf16) = 9, 'past the line end -> after its last byte');
    Check(LDocument.ByteColumnAt(1, 0, peUtf16) = 1, 'line 2 start -> byte 1');

    // The edit invalidates the derived bytes and columns
    LDocument.Replace(0, 1, 'zz');
    Check(LDocument.Text = 'zz' + #$00E9#$D83D#$DE00 + 'b'#13#10'c', 'replaced');
    Check(LDocument.ByteColumnToColumn(1, 9) = 5, 'b moved: byte 9 -> UTF-16 5');

    // A lone surrogate in a buffer reaches the frontend as U+FFFD
    LDocument.ReplaceAll(#$D83D);
    LBytes := LDocument.GetBytes();
    Check((Length(LBytes) = 3) and (LBytes[0] = $EF) and (LBytes[1] = $BF) and
      (LBytes[2] = $BD), 'lone surrogate -> EF BF BD');
  finally
    LDocument.Free();
  end;
end;

procedure TPCLspTests.DoTestUri();
var
  LPath: string;
begin
  Check(TPCLspUri.ToFilename('file:///C:/dir/a%20b.pcpp', LPath), 'file uri');
  Check(LPath = 'C:\dir\a b.pcpp', 'drive path decoded');
  Check(TPCLspUri.ToFilename('file://host/share/x.pcpp', LPath), 'unc uri');
  Check(LPath = '\\host\share\x.pcpp', 'UNC path');
  Check(not TPCLspUri.ToFilename('untitled:Untitled-1', LPath), 'untitled names no file');
  Check(TPCLspUri.FromFilename('C:\dir\a b' + #$00E9 + '.pcpp') =
    'file:///C:/dir/a%20b%C3%A9.pcpp', 'encoded back, UTF-8 escapes');
  Check(TPCLspUri.ToFilename(TPCLspUri.FromFilename('C:\d\' + #$00E9 + '.pcpp'), LPath) and
    (LPath = 'C:\d\' + #$00E9 + '.pcpp'), 'round trip');
end;

procedure TPCLspTests.DoTestLifecycle();
var
  LSession: TLspSession;
  LItem: TJSONObject;
  LText: string;
begin
  // A request before initialize fails; initialize answers the capabilities;
  // an unknown request fails; shutdown then exit = exit code 0
  LSession := NewSession();
  try
    RunSession(['{"jsonrpc":"2.0","id":7,"method":"textDocument/hover","params":{}}',
      PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      '{"jsonrpc":"2.0","id":8,"method":"textDocument/nothing","params":{}}',
      'not json', PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);
    Check(LSession.ExitCode = 0, 'shutdown before exit: 0');
    Check(LSession.Output.Count = 5, 'five replies');
    if LSession.Output.Count = 5 then
    begin
      LItem := LSession.Output[0];
      Check(IntAt(LItem, 'error.code') = -32002, 'before initialize: not initialized');
      LItem := LSession.Output[1];
      Check(LItem.TryGetValue<string>('result.capabilities.positionEncoding', LText) and
        (LText = 'utf-16'), 'utf-16 without a client list');
      Check(IntAt(LItem, 'result.capabilities.textDocumentSync.change') = 2, 'incremental sync');
      Check(IntAt(LSession.Output[2], 'error.code') = -32601, 'unknown method');
      Check(IntAt(LSession.Output[3], 'error.code') = -32700, 'parse error');
      Check(LSession.Output[4].GetValue('result') is TJSONNull, 'shutdown result null');
    end;
  finally
    FreeSession(LSession);
  end;

  // The input ends without shutdown: exit code 1
  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE], LSession);
    Check(LSession.ExitCode = 1, 'no shutdown: 1');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestDiagnostics();
var
  LSession: TLspSession;
  LFile: string;
  LBad: string;
  LGood: string;
  LPublishes: TArray<TJSONObject>;
  LDiagnostics: TJSONArray;
  LFirst: TJSONValue;
begin
  // Line 4 declares X a second time after a comment holding a 2-byte and a
  // 4-byte character: X is byte column 14, UTF-16 column 11 (0-based 10)
  LFile := TestFile('lspt_dup.pcpp');
  LBad := 'module lib lspt_dup;'#10'var'#10'  X: int32 = 1;'#10 +
    '  /*' + #$00E9#$D83D#$DE00 + '*/ X: int32 = 2;'#10'end.'#10;
  LGood := 'module lib lspt_dup;'#10'var'#10'  X: int32 = 1;'#10'end.'#10;

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED, OpenMessage(LFile, LBad),
      ChangeMessage(LFile, 2, LGood), PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);
    Check(LSession.ExitCode = 0, 'exit 0');
    LPublishes := Publishes(LSession, LFile);
    Check(Length(LPublishes) = 2, 'one publish per change');
    if Length(LPublishes) <> 2 then
      Exit;

    // The duplicate X, at its UTF-16 position, with its version
    Check(IntAt(LPublishes[0], 'version') = 1, 'first publish: version 1');
    LDiagnostics := LPublishes[0].GetValue('diagnostics') as TJSONArray;
    Check(LDiagnostics.Count >= 1, 'the duplicate is reported');
    if LDiagnostics.Count >= 1 then
    begin
      LFirst := LDiagnostics.Items[0];
      Check(IntAt(LFirst, 'severity') = 1, 'an error');
      Check(IntAt(LFirst, 'range.start.line') = 3, 'line 4 (0-based 3)');
      Check(IntAt(LFirst, 'range.start.character') = 10, 'X at UTF-16 10, not byte 13');
      Check(IntAt(LFirst, 'range.end.line') = 3, 'ends on line 4');
      // SM0004 spans the declaration 'X: int32 = 2;': 13 UTF-16 units, so
      // the exclusive end is 10 + 13 = 23 (the end converts past the
      // non-ASCII comment as the start does)
      Check(IntAt(LFirst, 'range.end.character') = 23, Format('declaration end 23 (got %d)',
        [IntAt(LFirst, 'range.end.character')]));
      Check(LFirst.GetValue<string>('source') = 'PaskalCPP', 'source PaskalCPP');
      Check(LFirst.GetValue<string>('code') = 'SM0004', 'code SM0004');
      // The first declaration, line 3 '  X: int32 = 1;': 2 .. 15, same document
      Check(IntAt(LFirst, 'relatedInformation[0].location.range.start.line') = 2, 'related: line 3');
      Check(IntAt(LFirst, 'relatedInformation[0].location.range.start.character') = 2, 'related: start 2');
      Check(IntAt(LFirst, 'relatedInformation[0].location.range.end.character') = 15, 'related: end 15');
      Check(LFirst.GetValue<string>('relatedInformation[0].location.uri') =
        TPCLspUri.FromFilename(LFile), 'related: the same document');
    end;

    // Fixed: an empty list at version 2
    Check(IntAt(LPublishes[1], 'version') = 2, 'second publish: version 2');
    LDiagnostics := LPublishes[1].GetValue('diagnostics') as TJSONArray;
    Check(LDiagnostics.Count = 0, 'fixed: no diagnostics');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestWatchedFiles();
const
  { LWatched }
  LWatched = '{"jsonrpc":"2.0","method":"workspace/didChangeWatchedFiles","params":{"changes":[]}}';
var
  LSession: TLspSession;
  LDir: string;
  LFile: string;
  LDll: string;
  LText: string;
  LPublishes: TArray<TJSONObject>;
  LDiagnostics: TJSONArray;
begin
  // A @copydll names a file a build has not written yet: SM0105. The file
  // appears between two messages (as a build writes it); the editor then
  // sends workspace/didChangeWatchedFiles and the open buffer, unchanged, is
  // checked again: its report goes (it stayed until the buffer was edited)
  LDir := TPath.Combine(TPath.GetTempPath(), 'pcpp-lsp-test-watch');
  TDirectory.CreateDirectory(LDir);
  LFile := TPath.Combine(LDir, 'lspt_watch.pcpp');
  LDll := TPath.Combine(LDir, 'lspt_watch_lib.dll');
  if TFile.Exists(LDll) then
    TFile.Delete(LDll);
  LText := 'module exe lspt_watch;'#10'@copydll "' + LDll.Replace('\', '/') + '";'#10 +
    'begin'#10'end.'#10;

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED, OpenMessage(LFile, LText), LWatched,
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession, False, 3,
      procedure()
      begin
        TFile.WriteAllText(LDll, 'built');
      end);
    Check(LSession.ExitCode = 0, 'exit 0');
    LPublishes := Publishes(LSession, LFile);
    Check(Length(LPublishes) = 2, Format('published at open and after the disk changed (got %d)',
      [Length(LPublishes)]));
    if Length(LPublishes) <> 2 then
      Exit;
    LDiagnostics := LPublishes[0].GetValue('diagnostics') as TJSONArray;
    Check((LDiagnostics.Count = 1) and
      (LDiagnostics.Items[0].GetValue<string>('code') = 'SM0105'), 'before the build: SM0105');
    LDiagnostics := LPublishes[1].GetValue('diagnostics') as TJSONArray;
    Check(LDiagnostics.Count = 0, Format('after the build: no report (got %d)', [LDiagnostics.Count]));
  finally
    FreeSession(LSession);
    if TFile.Exists(LDll) then
      TFile.Delete(LDll);
  end;
end;

procedure TPCLspTests.DoTestWatchRegister();
const
  { LInitWatch }
  // initialize from a client that takes the server's file watchers
  LInitWatch = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":' +
    '{"workspace":{"didChangeWatchedFiles":{"dynamicRegistration":true}}}}}';
var
  LSession: TLspSession;
  LFile: string;
  LDll: string;
  LText: string;
  LItem: TJSONObject;
  LMethod: string;
  LRegisters: Integer;
  LUnregisters: Integer;
  LPattern: string;
  LRegId: string;
  LUnregId: string;
begin
  // A @copydll path that does not exist: the server registers it as a
  // watcher (the client polls it), and unregisters it when the file closes.
  // A client without the capability is sent neither
  LFile := TestFile('lspt_watchreg.pcpp');
  LDll := TestFile('lspt_watchreg_lib.dll');
  LText := 'module exe lspt_watchreg;'#10'@copydll "' + LDll.Replace('\', '/') + '";'#10 +
    'begin'#10'end.'#10;

  LSession := NewSession();
  try
    RunSession([LInitWatch, PC_LSPT_INITIALIZED, OpenMessage(LFile, LText),
      '{"jsonrpc":"2.0","method":"textDocument/didClose","params":{"textDocument":{"uri":' +
      JsonText(TPCLspUri.FromFilename(LFile)) + '}}}', PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);
    LRegisters := 0;
    LUnregisters := 0;
    LPattern := '';
    LRegId := '';
    LUnregId := '';
    for LItem in LSession.Output do
    begin
      if not LItem.TryGetValue<string>('method', LMethod) then
        Continue;
      if LMethod = 'client/registerCapability' then
      begin
        Inc(LRegisters);
        LRegId := LItem.GetValue<string>('params.registrations[0].id');
        LPattern := LItem.GetValue<string>('params.registrations[0].registerOptions.watchers[0].globPattern');
        Check(LItem.GetValue<string>('params.registrations[0].method') = 'workspace/didChangeWatchedFiles',
          'registers didChangeWatchedFiles');
      end
      else if LMethod = 'client/unregisterCapability' then
      begin
        Inc(LUnregisters);
        LUnregId := LItem.GetValue<string>('params.unregisterations[0].id');
      end;
    end;
    Check(LRegisters = 1, Format('one registration (got %d)', [LRegisters]));
    Check(SameText(LPattern, LDll.Replace('\', '/')), 'the watcher is the dll path, with ''/'': ' + LPattern);
    Check(LUnregisters = 1, Format('closed: one unregistration (got %d)', [LUnregisters]));
    Check((LRegId <> '') and (LUnregId = LRegId), 'the unregistration names the registration');
  finally
    FreeSession(LSession);
  end;

  // The plain initialize (no capability): no watcher requests at all
  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED, OpenMessage(LFile, LText),
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);
    LRegisters := 0;
    for LItem in LSession.Output do
    begin
      if LItem.TryGetValue<string>('method', LMethod) and LMethod.StartsWith('client/') then
        Inc(LRegisters);
    end;
    Check(LRegisters = 0, Format('without the capability: no requests (got %d)', [LRegisters]));
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestWatchedImport();
const
  { LInitWatch }
  LInitWatch = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":' +
    '{"workspace":{"didChangeWatchedFiles":{"dynamicRegistration":true}}}}}';
  { LWatched }
  LWatched = '{"jsonrpc":"2.0","method":"workspace/didChangeWatchedFiles","params":{"changes":[]}}';
var
  LSession: TLspSession;
  LDir: string;
  LFile: string;
  LUnit: string;
  LPublishes: TArray<TJSONObject>;
  LDiagnostics: TJSONArray;
  LItem: TJSONObject;
  LMethod: string;
  LWatchers: TJSONArray;
  LWatcher: TJSONValue;
  LFound: Boolean;
begin
  // An import of a unit no folder holds yet: PR0012, and the file the lookup
  // tried (the importer's folder + name.pcpp) is registered as a watcher.
  // The unit file appears; the watched notification re-checks: no report
  LDir := TPath.Combine(TPath.GetTempPath(), 'pcpp-lsp-test-watch');
  TDirectory.CreateDirectory(LDir);
  LFile := TPath.Combine(LDir, 'lspt_wimp.pcpp');
  LUnit := TPath.Combine(LDir, 'lspt_wimp_unit.pcpp');
  if TFile.Exists(LUnit) then
    TFile.Delete(LUnit);

  LSession := NewSession();
  try
    RunSession([LInitWatch, PC_LSPT_INITIALIZED,
      OpenMessage(LFile, 'module exe lspt_wimp;'#10'import lspt_wimp_unit;'#10'begin'#10'end.'#10),
      LWatched, PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession, False, 3,
      procedure()
      begin
        TFile.WriteAllText(LUnit, 'module unit lspt_wimp_unit;'#10'end.'#10);
      end);
    Check(LSession.ExitCode = 0, 'exit 0');

    // The FIRST registration (made while the unit did not exist) holds the
    // tried unit file; a later one holds it anyway, as a found module's file
    LFound := False;
    for LItem in LSession.Output do
    begin
      if not (LItem.TryGetValue<string>('method', LMethod) and
        (LMethod = 'client/registerCapability')) then
        Continue;
      LWatchers := LItem.GetValue<TJSONArray>('params.registrations[0].registerOptions.watchers');
      for LWatcher in LWatchers do
      begin
        if SameText(LWatcher.GetValue<string>('globPattern'), LUnit.Replace('\', '/')) then
          LFound := True;
      end;
      Break;
    end;
    Check(LFound, 'the tried unit file is watched: ' + LUnit.Replace('\', '/'));

    LPublishes := Publishes(LSession, LFile);
    Check(Length(LPublishes) = 2, Format('published at open and after the unit appeared (got %d)',
      [Length(LPublishes)]));
    if Length(LPublishes) <> 2 then
      Exit;
    LDiagnostics := LPublishes[0].GetValue('diagnostics') as TJSONArray;
    Check((LDiagnostics.Count = 1) and
      (LDiagnostics.Items[0].GetValue<string>('code') = 'PR0012'), 'before: PR0012 (unit not found)');
    LDiagnostics := LPublishes[1].GetValue('diagnostics') as TJSONArray;
    Check(LDiagnostics.Count = 0, Format('after the unit appeared: no report (got %d)', [LDiagnostics.Count]));
  finally
    FreeSession(LSession);
    if TFile.Exists(LUnit) then
      TFile.Delete(LUnit);
  end;
end;

procedure TPCLspTests.DoTestOpenImport();
var
  LSession: TLspSession;
  LMain: string;
  LUnit: string;
  LPublishes: TArray<TJSONObject>;
  LDiagnostics: TJSONArray;
begin
  // Neither file exists on disk: the import is found in the open buffers
  // (the parser's lookup asks the source provider), and its text is read
  // from there
  LMain := TestFile('lspt_main.pcpp');
  LUnit := TestFile('lspt_unit.pcpp');

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LUnit, 'module unit lspt_unit;'#10'end.'#10),
      OpenMessage(LMain, 'module exe lspt_main;'#10'import lspt_unit;'#10'begin'#10'end.'#10),
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);
    LPublishes := Publishes(LSession, LMain);
    Check(Length(LPublishes) = 1, 'main published once');
    if Length(LPublishes) = 1 then
    begin
      LDiagnostics := LPublishes[0].GetValue('diagnostics') as TJSONArray;
      Check(LDiagnostics.Count = 0, 'the open, unsaved import is found');
    end;
    LPublishes := Publishes(LSession, LUnit);
    Check(Length(LPublishes) = 1, 'unit published once (its own check)');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestUnitAlone();
var
  LSession: TLspSession;
  LUnit: string;
  LPublishes: TArray<TJSONObject>;
  LDiagnostics: TJSONArray;
  LCodes: string;
  LI: Integer;
begin
  // A unit open on its own is checked, not built: "a unit cannot be the main
  // module" (PR0004) is a build rule and must not show. Its own mistakes
  // still do: version 2 declares Y twice (SM0004), proving SEM ran
  LUnit := TestFile('lspt_alone.pcpp');

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LUnit, 'module unit lspt_alone;'#10'var'#10'  Y: int32 = 1;'#10'end.'#10),
      ChangeMessage(LUnit, 2, 'module unit lspt_alone;'#10'var'#10'  Y: int32 = 1;'#10 +
        '  Y: int32 = 2;'#10'end.'#10),
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);
    LPublishes := Publishes(LSession, LUnit);
    Check(Length(LPublishes) = 2, 'one publish per change');
    if Length(LPublishes) <> 2 then
      Exit;

    LDiagnostics := LPublishes[0].GetValue('diagnostics') as TJSONArray;
    LCodes := '';
    for LI := 0 to LDiagnostics.Count - 1 do
      LCodes := LCodes + LDiagnostics.Items[LI].GetValue<string>('code') + ' ';
    Check(LDiagnostics.Count = 0, 'a clean unit alone: nothing, no PR0004 (got ' + LCodes + ')');

    LDiagnostics := LPublishes[1].GetValue('diagnostics') as TJSONArray;
    Check((LDiagnostics.Count = 1) and
      (LDiagnostics.Items[0].GetValue<string>('code') = 'SM0004'),
      'the unit''s own mistake still shows (SM0004)');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestColouring();
var
  LSession: TLspSession;
  LFile: string;
  LText: string;
  LItem: TJSONObject;
  LInit: TJSONObject;
  LData: TJSONArray;
  LRow: TPCTokenRow;
  LKeywords: Integer;
  LTypes: Integer;
  LI: Integer;
  LLine: Integer;
  LStart: Integer;
  LDecoded: string;
  LLegend: string;
begin
  // Expected, hand-derived (0-based line, UTF-16 start, length, type 0
  // keyword / 1 type):
  //   0 'module exe lspt_sem;'   module 0:0:6:0, exe 0:7:3:0
  //   1 '/*e-acute emoji*/ var'  var after 7 UTF-16 units + space: 1:8:3:0
  //                               (11 bytes before it: byte columns would give 11)
  //   2 '  a: int32;'            int32 2:5:5:1
  //   3 '  b: int;'              'int' is C++'s (tcCppKeyword): nothing
  //   4 'cppstart source'        cppstart 4:0:8:0
  //   5 'int begin = 0;'         the block's text is verbatim: nothing
  //   6 'cppend;'                cppend 6:0:6:0
  LFile := TestFile('lspt_sem.pcpp');
  LText := 'module exe lspt_sem;'#10'/*' + #$00E9#$D83D#$DE00 + '*/ var'#10 +
    '  a: int32;'#10'  b: int;'#10'cppstart source'#10'int begin = 0;'#10'cppend;'#10;

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED, OpenMessage(LFile, LText),
      Format('{"jsonrpc":"2.0","id":5,"method":"textDocument/semanticTokens/full",' +
        '"params":{"textDocument":{"uri":%s}}}', [JsonText(TPCLspUri.FromFilename(LFile))]),
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);

    // initialize: the legend and the word lists, counted from the lexer's table
    LInit := nil;
    LData := nil;
    for LItem in LSession.Output do
    begin
      if IntAt(LItem, 'id') = 1 then
        LInit := LItem
      else if IntAt(LItem, 'id') = 5 then
        LData := LItem.FindValue('result.data') as TJSONArray;
    end;
    Check(LInit <> nil, 'initialize answered');
    if LInit = nil then
      Exit;
    LLegend := '';
    if LInit.FindValue('result.capabilities.semanticTokensProvider.legend.tokenTypes') <> nil then
      LLegend := LInit.FindValue('result.capabilities.semanticTokensProvider.legend.tokenTypes').ToJSON();
    Check(LLegend = '["keyword","type"]', 'legend keyword, type (got ' + LLegend + ')');

    LKeywords := 0;
    LTypes := 0;
    for LRow in PC_PASKAL_TOKENS do
    begin
      if LRow.Category = tcKeyword then
        Inc(LKeywords)
      else if LRow.Category = tcPrimitive then
        Inc(LTypes);
    end;
    Check(TJSONArray(LInit.FindValue('result.capabilities.experimental.pcppWords.keywords')).Count =
      LKeywords, Format('every PaskalCPP keyword sent (%d)', [LKeywords]));
    Check(TJSONArray(LInit.FindValue('result.capabilities.experimental.pcppWords.types')).Count =
      LTypes, Format('every builtin type sent (%d)', [LTypes]));
    Check(LInit.FindValue('result.capabilities.experimental.pcppWords.keywords').ToJSON().Contains('"module"'),
      'module is a keyword');

    // The tokens, decoded from the relative encoding
    Check(LData <> nil, 'semantic tokens answered');
    if LData = nil then
      Exit;
    LDecoded := '';
    LLine := 0;
    LStart := 0;
    LI := 0;
    while LI + 4 < LData.Count do
    begin
      if LData.Items[LI].AsType<Integer> > 0 then
        LStart := 0;
      Inc(LLine, LData.Items[LI].AsType<Integer>);
      Inc(LStart, LData.Items[LI + 1].AsType<Integer>);
      LDecoded := LDecoded + Format('%d:%d:%d:%d ', [LLine, LStart,
        LData.Items[LI + 2].AsType<Integer>, LData.Items[LI + 3].AsType<Integer>]);
      Inc(LI, 5);
    end;
    Check(LDecoded.Trim() = '0:0:6:0 0:7:3:0 1:8:3:0 2:5:5:1 4:0:8:0 6:0:6:0',
      'tokens (got ' + LDecoded.Trim() + ')');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestHover();
const
  // 0-based lines of the main buffer below, as the client counts them
  CLineCall = 21;      // '  GR.X := Add(K, lspt_hunit.F(2));'
  CLineSet = 22;       // '  Ov(1);'
  CLineWide = 23;      // '  puts("<e-acute>"); Ov(cpp("2"));'
var
  LSession: TLspSession;
  LMain: string;
  LUnit: string;
  LInit: TJSONObject;
  LHasHover: Boolean;
  LItem: TJSONObject;
  LSet: string;
  LUnitTag: string;

  procedure DoExpect(const AId: Integer; const AExpected: string; const ALabel: string);
  var
    LGot: string;
  begin
    LGot := HoverValue(LSession, AId);
    Check(LGot = AExpected, ALabel + ' (got ' + LGot + ')');
  end;

begin
  // Neither file exists: both are open buffers. Every expected text below is
  // written by hand from the declarations in the buffers
  LMain := TestFile('lspt_hover.pcpp');
  LUnit := TestFile('lspt_hunit.pcpp');

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LUnit,
        'module unit lspt_hunit;'#10 +
        'exported routine F(const AX: int32): int32;'#10 +
        'begin'#10 +
        '  return AX;'#10 +
        'end;'#10 +
        'end.'#10),
      OpenMessage(LMain,
        'module exe lspt_hover;'#10 +                               // 0
        'import lspt_hunit;'#10 +                                   // 1
        'type'#10 +                                                 // 2
        '  TRec = record'#10 +                                      // 3
        '    X: int32;'#10 +                                        // 4
        '  end;'#10 +                                               // 5
        'const'#10 +                                                // 6
        '  K: int32 = 1;'#10 +                                      // 7
        'var'#10 +                                                  // 8
        '  GR: TRec;'#10 +                                          // 9
        'routine Add(const AA: int32; const AB: int32): int32;'#10 + // 10
        'begin'#10 +                                                // 11
        '  return AA + AB;'#10 +                                    // 12
        'end;'#10 +                                                 // 13
        'routine Ov(const AN: int32);'#10 +                         // 14
        'begin'#10 +                                                // 15
        'end;'#10 +                                                 // 16
        'routine Ov(const AS: string);'#10 +                        // 17
        'begin'#10 +                                                // 18
        'end;'#10 +                                                 // 19
        'begin'#10 +                                                // 20
        '  GR.X := Add(K, lspt_hunit.F(2));'#10 +                   // 21
        '  Ov(1);'#10 +                                             // 22
        '  puts("' + #$00E9 + '"); Ov(cpp("2"));'#10 +              // 23
        'end.'#10),
      HoverMessage(10, LMain, CLineCall, 2),     // GR
      HoverMessage(11, LMain, CLineCall, 5),     // X (member)
      HoverMessage(12, LMain, CLineCall, 11),    // Add (inside the name)
      HoverMessage(13, LMain, CLineCall, 14),    // K
      HoverMessage(14, LMain, CLineCall, 17),    // lspt_hunit (module qualifier)
      HoverMessage(15, LMain, CLineCall, 28),    // F (imported)
      HoverMessage(16, LMain, 12, 9),            // AA (param)
      HoverMessage(17, LMain, 9, 6),             // TRec (type use)
      HoverMessage(18, LMain, CLineSet, 2),      // Ov (overload set)
      HoverMessage(19, LMain, CLineWide, 13),    // Ov after a 2-byte char (byte column 15)
      HoverMessage(20, LMain, CLineWide, 2),     // puts: C/C++, no hover
      HoverMessage(21, LMain, 20, 0),            // begin: a keyword, no use
      HoverMessage(22, LMain, 9, 3),             // GR: a declaration's own name (W1)
      HoverMessage(23, LMain, 1, 9),             // lspt_hunit: an import's name
      HoverMessage(24, LMain, 14, 9),            // Ov: one member's own name, not the set
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);

    // initialize advertises hover
    LHasHover := False;
    for LItem in LSession.Output do
      if IntAt(LItem, 'id') = 1 then
      begin
        LInit := LItem.GetValue('result') as TJSONObject;
        if not LInit.TryGetValue<Boolean>('capabilities.hoverProvider', LHasHover) then
          LHasHover := False;
      end;
    Check(LHasHover, 'initialize: hoverProvider true');

    LUnitTag := #10#10'*lspt_hunit.pcpp*';
    LSet := Fenced('routine Ov(const AN: int32)'#10'routine Ov(const AS: string)');

    DoExpect(10, Fenced('var GR: TRec'), 'var use');
    DoExpect(11, Fenced('X: int32'), 'record field through a member');
    DoExpect(12, Fenced('routine Add(const AA: int32; const AB: int32): int32'), 'routine call');
    DoExpect(13, Fenced('const K: int32 = 1'), 'const use');
    DoExpect(14, Fenced('module lspt_hunit') + LUnitTag, 'module qualifier');
    DoExpect(15, Fenced('routine F(const AX: int32): int32') + LUnitTag, 'imported routine');
    DoExpect(16, Fenced('const AA: int32'), 'param use');
    DoExpect(17, Fenced('type TRec = record'), 'type use');
    // F18: Ov(1) is taken by Ov(int32) only (SEM binds it); an opaque
    // argument is taken by every member, so that call shows the whole set
    DoExpect(18, Fenced('routine Ov(const AN: int32)'), 'overload set: the one member that takes the arguments');
    DoExpect(19, LSet, 'overload set: every member once, after a non-ASCII char on its line');
    DoExpect(20, '<null>', 'a C/C++ name has no hover');
    DoExpect(21, '<null>', 'a keyword has no hover');
    DoExpect(22, Fenced('var GR: TRec'), 'a declaration''s own name');
    DoExpect(23, Fenced('module lspt_hunit') + LUnitTag, 'an import''s name');
    DoExpect(24, Fenced('routine Ov(const AN: int32)'), 'a set member''s own name: that member only');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestDefinition();
const
  // 0-based lines of the main buffer below, as the client counts them
  CLineFor = 19;       // '  for LI := 1 to 2 do Ov(LI); end; Ov(cpp("0"));'
  CLineChoice = 20;    // '  LC := TCol.cGreen;'
  CLineCall = 21;      // '  LI := Fw(lspt_dunit.D(1));'
var
  LSession: TLspSession;
  LDir: string;
  LMain: string;
  LUnit: string;
  LInit: TJSONObject;
  LHasDefinition: Boolean;
  LItem: TJSONObject;
  LPublishes: TArray<TJSONObject>;
  LDiagnostics: TJSONArray;
  LSet: string;
  LUnitHeader: string;

  procedure DoExpect(const AId: Integer; const AExpected: string; const ALabel: string);
  var
    LGot: string;
  begin
    LGot := DefinitionText(LSession, AId);
    Check(LGot = AExpected, ALabel + ' (got ' + LGot + ')');
  end;

begin
  // The main module is an open buffer (not on disk) beside the fixture
  // lspt_dunit.pcpp, which stays closed: its location's columns convert over
  // its disk text. Expected locations are counted by hand from the texts;
  // characters are UTF-16, end exclusive
  LDir := DoProbeDir('lsp\def');
  LMain := TPath.Combine(LDir, 'lspt_def.pcpp');
  LUnit := TPath.Combine(LDir, 'lspt_dunit.pcpp');
  Check(TFile.Exists(LUnit) and not TFile.Exists(LMain),
    'fixture: lspt_dunit.pcpp on disk, lspt_def.pcpp not (scripts\zb_ed\gen_lsp_def.py)');

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LMain,
        'module exe lspt_def;'#10 +                                 // 0
        'import lspt_dunit;'#10 +                                   // 1
        'type'#10 +                                                 // 2
        '  TCol = choices(cRed, cGreen);'#10 +                      // 3
        'forward routine Fw(const AA: int32): int32;'#10 +          // 4
        'routine Ov(const AN: int32);'#10 +                         // 5
        'begin'#10 +                                                // 6
        'end;'#10 +                                                 // 7
        'routine Ov(const AS: string);'#10 +                        // 8
        'begin'#10 +                                                // 9
        'end;'#10 +                                                 // 10
        'routine Fw(const AA: int32): int32;'#10 +                  // 11
        'begin'#10 +                                                // 12
        '  return AA;'#10 +                                         // 13
        'end;'#10 +                                                 // 14
        'var'#10 +                                                  // 15
        '  /*' + #$00E9 + '*/LI: int32;'#10 +                       // 16
        '  LC: TCol;'#10 +                                          // 17
        'begin'#10 +                                                // 18
        '  for LI := 1 to 2 do Ov(LI); end; Ov(cpp("0"));'#10 +     // 19
        '  LC := TCol.cGreen;'#10 +                                 // 20
        '  LI := Fw(lspt_dunit.D(1));'#10 +                         // 21
        'end.'#10),                                                 // 22
      DefinitionMessage(30, LMain, CLineFor, 22),     // Ov(LI): the one member taking an int32
      DefinitionMessage(41, LMain, CLineFor, 35),     // Ov(cpp("0")): every member takes it
      DefinitionMessage(31, LMain, CLineFor, 6),      // LI: the for's iterator
      DefinitionMessage(32, LMain, CLineChoice, 14),  // cGreen through TCol.
      DefinitionMessage(33, LMain, CLineCall, 8),     // Fw: forward + full
      DefinitionMessage(34, LMain, CLineCall, 22),    // D: in the closed import
      DefinitionMessage(35, LMain, CLineCall, 12),    // lspt_dunit: module qualifier
      DefinitionMessage(36, LMain, 1, 8),             // lspt_dunit: the import's name
      DefinitionMessage(37, LMain, 5, 9),             // Ov: a member's own name
      DefinitionMessage(38, LMain, 17, 7),            // TCol: a type use
      DefinitionMessage(39, LMain, 4, 17),            // Fw: the forward's own name
      DefinitionMessage(40, LMain, 18, 0),            // begin: a keyword
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);

    // initialize advertises definition
    LHasDefinition := False;
    for LItem in LSession.Output do
      if IntAt(LItem, 'id') = 1 then
      begin
        LInit := LItem.GetValue('result') as TJSONObject;
        if not LInit.TryGetValue<Boolean>('capabilities.definitionProvider', LHasDefinition) then
          LHasDefinition := False;
      end;
    Check(LHasDefinition, 'initialize: definitionProvider true');

    // The buffer is a valid program: every location below is SEM's resolution
    LPublishes := Publishes(LSession, LMain);
    Check(Length(LPublishes) >= 1, 'main published');
    if Length(LPublishes) >= 1 then
    begin
      LDiagnostics := LPublishes[High(LPublishes)].GetValue('diagnostics') as TJSONArray;
      Check(LDiagnostics.Count = 0, 'main has no diagnostics (got ' + LDiagnostics.ToJSON() + ')');
    end;

    LSet := 'lspt_def.pcpp:5:8-5:10;lspt_def.pcpp:8:8-8:10';
    LUnitHeader := 'lspt_dunit.pcpp:0:12-0:22';

    // F18: Ov(LI) binds the one member that takes an int32; an opaque argument
    // is taken by every member: the whole set
    DoExpect(30, 'lspt_def.pcpp:5:8-5:10', 'overload set: the one member that takes the arguments');
    DoExpect(41, LSet, 'overload set: every member');
    DoExpect(31, 'lspt_def.pcpp:16:7-16:9', 'for iterator -> var after a 2-byte char (UTF-16 7, byte 9)');
    DoExpect(32, 'lspt_def.pcpp:3:23-3:29', 'choice value through its type');
    DoExpect(33, 'lspt_def.pcpp:11:8-11:10', 'call of a forward routine -> its full routine');
    DoExpect(34, 'lspt_dunit.pcpp:1:22-1:23', 'routine in a closed import, after a 2-byte char (UTF-16 22, byte 24)');
    DoExpect(35, LUnitHeader, 'module qualifier -> the module header name');
    DoExpect(36, LUnitHeader, 'import name -> the module header name');
    DoExpect(37, 'lspt_def.pcpp:5:8-5:10', 'a set member''s own name: that member only');
    DoExpect(38, 'lspt_def.pcpp:3:2-3:6', 'type use');
    DoExpect(39, 'lspt_def.pcpp:11:8-11:10', 'a forward''s own name -> its full routine');
    DoExpect(40, '<null>', 'a keyword has no definition');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestInlayHints();
var
  LSession: TLspSession;
  LMain: string;
  LInit: TJSONObject;
  LHasHints: Boolean;
  LItem: TJSONObject;
  LPublishes: TArray<TJSONObject>;
  LDiagnostics: TJSONArray;

  procedure DoExpect(const AId: Integer; const AExpected: string; const ALabel: string);
  var
    LGot: string;
  begin
    LGot := InlayText(LSession, AId);
    Check(LGot = AExpected, ALabel + ' (got ' + LGot + ')');
  end;

begin
  // The main module is an open buffer, not on disk. Every expected hint is
  // counted by hand from the text: 0-based line, UTF-16 character, label
  LMain := TestFile('lspt_hints.pcpp');

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LMain,
        'module exe lspt_hints;'#10 +                               // 0
        'type'#10 +                                                 // 1
        '  TFn = routine(const AP: int32; const AQ: int32): int32;'#10 + // 2
        '  TObj = object'#10 +                                      // 3
        '    F: int32;'#10 +                                        // 4
        '    method Put(const AV: int32);'#10 +                     // 5
        '    begin'#10 +                                            // 6
        '    end;'#10 +                                             // 7
        '  end;'#10 +                                               // 8
        'forward routine Fw(const AA: int32): int32;'#10 +          // 9
        'routine Add(const AA: int32; var AB: int32): int32;'#10 +  // 10
        'begin'#10 +                                                // 11
        '  return AA + AB;'#10 +                                    // 12
        'end;'#10 +                                                 // 13
        'routine Ov(const AN: int32; const AK: int32);'#10 +        // 14
        'begin'#10 +                                                // 15
        'end;'#10 +                                                 // 16
        'routine Ov(const AN: string);'#10 +                        // 17
        'begin'#10 +                                                // 18
        'end;'#10 +                                                 // 19
        'routine Dz(const AU: int32);'#10 +                         // 20
        'begin'#10 +                                                // 21
        'end;'#10 +                                                 // 22
        'routine Dz(const AW: string);'#10 +                        // 23
        'begin'#10 +                                                // 24
        'end;'#10 +                                                 // 25
        'routine V(const AN: int32; ...);'#10 +                     // 26
        'begin'#10 +                                                // 27
        'end;'#10 +                                                 // 28
        'routine Fw(const AA: int32): int32;'#10 +                  // 29
        'begin'#10 +                                                // 30
        '  return AA;'#10 +                                         // 31
        'end;'#10 +                                                 // 32
        'var'#10 +                                                  // 33
        '  AB: int32;'#10 +                                         // 34
        '  LB: int32;'#10 +                                         // 35
        '  LF: TFn;'#10 +                                           // 36
        '  LO: TObj;'#10 +                                          // 37
        'routine Ag(const AN: int32);'#10 +                         // 38
        'begin'#10 +                                                // 39
        'end;'#10 +                                                 // 40
        'routine Ag(const AN: int64);'#10 +                         // 41
        'begin'#10 +                                                // 42
        'end;'#10 +                                                 // 43
        'begin'#10 +                                                // 44
        '  AB := Add(1 + 2, AB);'#10 +                              // 45
        '  Ov(1, 2); Ov("s");'#10 +                                 // 46
        '  V(1, 2, 3);'#10 +                                        // 47
        '  AB := LF(4, 5);'#10 +                                    // 48
        '  LO.Put(6);'#10 +                                         // 49
        '  AB := Fw(Add(7, AB));'#10 +                              // 50
        '  puts("' + #$00E9 + '"); AB := Add(8, LB);'#10 +          // 51
        '  Dz(cpp("1")); Ag(LB);'#10 +                              // 52
        '  AB := Add(9, AB);'#10 +                                  // 53
        'end.'#10),                                                 // 54
      InlayMessage(50, LMain, 0, 0, 55, 0),       // the whole buffer
      InlayMessage(51, LMain, 53, 0, 53, 40),     // line 53 only
      InlayMessage(52, LMain, 52, 0, 53, 0),      // line 52 only (the end is exclusive)
      InlayMessage(53, TestFile('lspt_nohints.pcpp'), 0, 0, 9, 0),  // a document not open
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);

    // initialize advertises inlay hints
    LHasHints := False;
    for LItem in LSession.Output do
      if IntAt(LItem, 'id') = 1 then
      begin
        LInit := LItem.GetValue('result') as TJSONObject;
        if not LInit.TryGetValue<Boolean>('capabilities.inlayHintProvider', LHasHints) then
          LHasHints := False;
      end;
    Check(LHasHints, 'initialize: inlayHintProvider true');

    // The buffer is a valid program: every hint below is SEM's resolution
    LPublishes := Publishes(LSession, LMain);
    Check(Length(LPublishes) >= 1, 'main published');
    if Length(LPublishes) >= 1 then
    begin
      LDiagnostics := LPublishes[High(LPublishes)].GetValue('diagnostics') as TJSONArray;
      Check(LDiagnostics.Count = 0, 'main has no diagnostics (got ' + LDiagnostics.ToJSON() + ')');
    end;

    // 45: AB spelled as its parameter: none. 46: each Ov call is taken by one
    // member only (F18: SEM binds it), so its own names: AN AK, then AN.
    // 47: the variadic tail: none. 48: a routine value's type. 49: a method.
    // 50: nested, by position; Fw is forward. 51: after a 2-byte char
    // (UTF-16 23 / 26, bytes 25 / 28), a var parameter. 52: an opaque
    // argument is taken by both Dz members, which disagree (AU / AW): none;
    // both Ag members take an int32 and agree: AN
    DoExpect(50,
      '45:12:AA:;' +
      '46:5:AN:;46:8:AK:;46:15:AN:;' +
      '47:4:AN:;' +
      '48:11:AP:;48:14:AQ:;' +
      '49:9:AV:;' +
      '50:11:AA:;50:15:AA:;' +
      '51:23:AA:;51:26:AB:;' +
      '52:19:AN:;' +
      '53:12:AA:', 'every call of the buffer');
    DoExpect(51, '53:12:AA:', 'range filter: one line');
    DoExpect(52, '52:19:AN:', 'range end at a line''s start excludes that line');
    DoExpect(53, '', 'a document not open: no hints');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestRoutineFields();
var
  LSession: TLspSession;
  LMain: string;
  LPublishes: TArray<TJSONObject>;
  LDiagnostics: TJSONArray;
  LSig: string;
begin
  // PLAN-RECORDS A10 (r3): a field of an inline routine type: hover prints
  // the inline spelling (the field's own name, a use through a member), a
  // call through the field names its parameters. 0-based lines, UTF-16
  // characters counted by hand from the text
  LMain := TestFile('lspt_rfields.pcpp');
  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LMain,
        'module exe lspt_rfields;'#10 +                                  // 0
        'type'#10 +                                                      // 1
        '  TR = record'#10 +                                             // 2
        '    F: routine(const AP: int32; const AQ: int32): int32;'#10 +  // 3
        '  end;'#10 +                                                    // 4
        'routine Add(const AA: int32; const AB: int32): int32;'#10 +     // 5
        'begin'#10 +                                                     // 6
        '  return AA + AB;'#10 +                                         // 7
        'end;'#10 +                                                      // 8
        'var'#10 +                                                       // 9
        '  LR: TR;'#10 +                                                 // 10
        '  LN: int32;'#10 +                                              // 11
        'begin'#10 +                                                     // 12
        '  LR.F := Add;'#10 +                                            // 13
        '  LN := LR.F(1, 2);'#10 +                                       // 14
        'end.'#10),                                                      // 15
      HoverMessage(90, LMain, 3, 4),       // F: the field's own name
      HoverMessage(91, LMain, 14, 11),     // F through LR.
      InlayMessage(92, LMain, 0, 0, 16, 0),
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);

    LPublishes := Publishes(LSession, LMain);
    Check(Length(LPublishes) >= 1, 'rfields: main published');
    if Length(LPublishes) >= 1 then
    begin
      LDiagnostics := LPublishes[High(LPublishes)].GetValue('diagnostics') as TJSONArray;
      Check(LDiagnostics.Count = 0, 'rfields: no diagnostics (got ' + LDiagnostics.ToJSON() + ')');
    end;
    LSig := Fenced('F: routine(const AP: int32; const AQ: int32): int32');
    Check(HoverValue(LSession, 90) = LSig, 'rfields: the field''s own name (got ' + HoverValue(LSession, 90) + ')');
    Check(HoverValue(LSession, 91) = LSig, 'rfields: a use through a member (got ' + HoverValue(LSession, 91) + ')');
    // 14: '1' at 13, '2' at 16; line 13 assigns the routine value: no call
    Check(InlayText(LSession, 92) = '14:13:AP:;14:16:AQ:',
      'rfields: a call through the field names its parameters (got ' + InlayText(LSession, 92) + ')');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestObjectMembers();
var
  LSession: TLspSession;
  LMain: string;
  LGot: string;

  procedure DoExpectHover(const AId: Integer; const AExpected: string; const ALabel: string);
  begin
    LGot := HoverValue(LSession, AId);
    Check(LGot = Fenced(AExpected), 'object_members: hover ' + ALabel + ' (got ' + LGot + ')');
  end;

  procedure DoExpectDefinition(const AId: Integer; const AExpected: string; const ALabel: string);
  begin
    LGot := DefinitionText(LSession, AId);
    Check(LGot = AExpected, 'object_members: definition ' + ALabel + ' (got ' + LGot + ')');
  end;

begin
  // PLAN-OBJECT O14: every object member kind in the editor. One open
  // buffer (not on disk); every expected text is written by hand from the
  // declarations below, columns 0-based as the client counts them
  LMain := TestFile('lspt_obj.pcpp');

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LMain,
        'module exe lspt_obj;'#10 +                                       // 0
        'type'#10 +                                                       // 1
        '  IShape = interface'#10 +                                       // 2
        '    method Area(): int32;'#10 +                                  // 3
        '    property Title: string read;'#10 +                           // 4
        '  end;'#10 +                                                     // 5
        '  TCount = object'#10 +                                          // 6
        '    FN: int32;'#10 +                                             // 7
        '    property N: int32 read FN; write FN;'#10 +                   // 8
        '  end;'#10 +                                                     // 9
        '  TShape = object implements IShape'#10 +                        // 10
        '    FName: string;'#10 +                                         // 11
        '    hidden FSize: int32;'#10 +                                   // 12
        '    embed C: TCount;'#10 +                                       // 13
        '    init(const AName: string);'#10 +                             // 14
        '    begin'#10 +                                                  // 15
        '      self.FName := AName;'#10 +                                 // 16
        '    end;'#10 +                                                   // 17
        '    done;'#10 +                                                  // 18
        '    begin'#10 +                                                  // 19
        '    end;'#10 +                                                   // 20
        '    virtual method Area(): int32;'#10 +                          // 21
        '    begin'#10 +                                                  // 22
        '      return self.FSize;'#10 +                                   // 23
        '    end;'#10 +                                                   // 24
        '    virtual property Title: string read FName;'#10 +             // 25
        '    property Size[const AK: int32]: int32 read'#10 +             // 26
        '      begin'#10 +                                                // 27
        '        return self.FSize * AK;'#10 +                            // 28
        '      end;'#10 +                                                 // 29
        '      default;'#10 +                                             // 30
        '    operator =(const A: TShape; const B: TShape): bool;'#10 +    // 31
        '    begin'#10 +                                                  // 32
        '      return A.FSize = B.FSize;'#10 +                            // 33
        '    end;'#10 +                                                   // 34
        '    operator <>(const A: TShape; const B: TShape): bool;'#10 +   // 35
        '    begin'#10 +                                                  // 36
        '      return A.FSize <> B.FSize;'#10 +                           // 37
        '    end;'#10 +                                                   // 38
        '  end;'#10 +                                                     // 39
        'var'#10 +                                                        // 40
        '  LS: TShape("a");'#10 +                                         // 41
        '  LT: TShape("b");'#10 +                                         // 42
        '  LB: bool;'#10 +                                                // 43
        '  LI: int32;'#10 +                                               // 44
        'begin'#10 +                                                      // 45
        '  LB := LS = LT;'#10 +                                           // 46
        '  LI := LS[2];'#10 +                                             // 47
        '  LS.N := 1;'#10 +                                               // 48
        'end.'#10),
      SymbolsMessage(2, LMain),
      HoverMessage(3, LMain, 14, 4),       // init
      HoverMessage(4, LMain, 18, 5),       // done
      HoverMessage(5, LMain, 21, 20),      // virtual method Area
      HoverMessage(6, LMain, 3, 11),       // the interface's method
      HoverMessage(7, LMain, 4, 13),       // the interface's property
      HoverMessage(8, LMain, 12, 11),      // hidden field
      HoverMessage(9, LMain, 13, 10),      // embed
      HoverMessage(10, LMain, 46, 11),     // LS = LT: the declared operator
      DefinitionMessage(11, LMain, 46, 11),
      HoverMessage(12, LMain, 47, 10),     // LS[2]: the default property
      DefinitionMessage(13, LMain, 47, 10),
      HoverMessage(14, LMain, 48, 5),      // LS.N: a property an embed promotes
      DefinitionMessage(15, LMain, 48, 5),
      CompletionMessage(16, LMain, 48, 5, ''),
      HoverMessage(17, LMain, 26, 13)],    // the default property's own name
      LSession);

    Check(SymbolKindsText(LSession, 2) =
      'IShape/11/[Area/6/(): int32,Title/7/string];' +
      'TCount/5/[FN/8/int32,N/7/int32];' +
      'TShape/5/[FName/8/string,FSize/8/int32,C/8/TCount,init/9/(const AName: string),done/6/,' +
      'Area/6/(): int32,Title/7/string,Size/7/[const AK: int32]: int32,' +
      'operator =/25/(const A: TShape; const B: TShape): bool,' +
      'operator <>/25/(const A: TShape; const B: TShape): bool];' +
      'LS/13/TShape;LT/13/TShape;LB/13/bool;LI/13/int32',
      'object_members: the outline lists every member kind (got ' + SymbolKindsText(LSession, 2) + ')');

    DoExpectHover(3, 'init(const AName: string)', 'init');
    DoExpectHover(4, 'done', 'done');
    DoExpectHover(5, 'virtual method Area(): int32', 'a virtual method');
    DoExpectHover(6, 'method Area(): int32', 'an interface method (no grammar words)');
    DoExpectHover(7, 'property Title: string read', 'an interface property');
    DoExpectHover(8, 'hidden FSize: int32', 'a hidden field');
    DoExpectHover(9, 'embed C: TCount', 'an embed');
    DoExpectHover(10, 'operator =(const A: TShape; const B: TShape): bool', 'a declared operator''s use');
    DoExpectDefinition(11, 'lspt_obj.pcpp:31:13-31:14', 'a declared operator''s use');
    DoExpectHover(12, 'property Size[const AK: int32]: int32 read; default', 'a default property''s use');
    DoExpectDefinition(13, 'lspt_obj.pcpp:26:13-26:17', 'a default property''s use');
    DoExpectHover(14, 'property N: int32 read FN; write FN', 'a promoted property');
    DoExpectDefinition(15, 'lspt_obj.pcpp:8:13-8:14', 'a promoted property');
    DoExpectHover(17, 'property Size[const AK: int32]: int32 read; default', 'a property''s own name');

    // After LS.: own and inherited members, then what the embed promotes;
    // the hidden field is not reached from the module body
    LGot := CompletionLabels(LSession, 16);
    Check(LGot = 'FName,C,Area,Title,Size,FN,N',
      'object_members: completion after LS. (got ' + LGot + ')');
    LGot := CompletionItem(LSession, 16, 'N');
    Check(LGot.StartsWith('10|1|'), 'object_members: N is a property (got ' + LGot + ')');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestObjectUnary();
var
  LSession: TLspSession;
  LMain: string;
  LGot: string;
begin
  // PLAN-OBJECT O14 (deferred test pass): a declared unary minus's use
  // (TPCUnary.OpRange -> ResolvedOperator) hovers as its declaration and
  // defines at its symbol; the built-in minus on an int32 is no operator's.
  // Columns 0-based as the client counts them
  LMain := TestFile('lspt_neg.pcpp');

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LMain,
        'module exe lspt_neg;'#10 +                                       // 0
        'type'#10 +                                                       // 1
        '  TV = record'#10 +                                              // 2
        '    X: int32;'#10 +                                              // 3
        '    operator -(const A: TV): TV;'#10 +                           // 4
        '    var'#10 +                                                    // 5
        '      LR: TV;'#10 +                                              // 6
        '    begin'#10 +                                                  // 7
        '      LR.X := -A.X;'#10 +                                        // 8
        '      return LR;'#10 +                                           // 9
        '    end;'#10 +                                                   // 10
        '  end;'#10 +                                                     // 11
        'var'#10 +                                                        // 12
        '  LA: TV;'#10 +                                                  // 13
        '  LB: TV;'#10 +                                                  // 14
        'begin'#10 +                                                      // 15
        '  LB := -LA;'#10 +                                               // 16
        'end.'#10),
      HoverMessage(2, LMain, 16, 8),       // -LA: the declared unary minus
      DefinitionMessage(3, LMain, 16, 8),
      HoverMessage(4, LMain, 8, 14)],      // -A.X: the built-in minus on int32
      LSession);

    LGot := HoverValue(LSession, 2);
    Check(LGot = Fenced('operator -(const A: TV): TV'),
      'object_unary: hover of a declared unary minus''s use (got ' + LGot + ')');
    LGot := DefinitionText(LSession, 3);
    Check(LGot = 'lspt_neg.pcpp:4:13-4:14',
      'object_unary: definition of a declared unary minus''s use (got ' + LGot + ')');
    LGot := HoverValue(LSession, 4);
    Check(not LGot.Contains('operator'),
      'object_unary: the built-in minus on an int32 is no declared operator (got ' + LGot + ')');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestDocumentSymbols();
var
  LSession: TLspSession;
  LMain: string;
  LUnit: string;
  LInit: TJSONObject;
  LHasSymbols: Boolean;
  LItem: TJSONObject;
  LPublishes: TArray<TJSONObject>;
  LDiagnostics: TJSONArray;

  procedure DoExpect(const AId: Integer; const AExpected: string; const ALabel: string);
  var
    LGot: string;
  begin
    LGot := SymbolsText(LSession, AId);
    Check(LGot = AExpected, ALabel + ' (got ' + LGot + ')');
  end;

begin
  // Both files are open buffers, not on disk. Every expected entry is
  // counted by hand: name/kind/detail/selection line:start-end (UTF-16, end
  // exclusive)/range start line-end line, children in [ ]
  LMain := TestFile('lspt_syms.pcpp');
  LUnit := TestFile('lspt_sunit.pcpp');

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LUnit,
        'module unit lspt_sunit;'#10 +
        'exported routine G();'#10 +
        'begin'#10 +
        'end;'#10 +
        'end.'#10),
      OpenMessage(LMain,
        'module exe lspt_syms;'#10 +                                // 0
        'import lspt_sunit;'#10 +                                   // 1
        'const'#10 +                                                // 2
        '  KMax: int32 = 10;'#10 +                                  // 3
        'type'#10 +                                                 // 4
        '  TRec = record'#10 +                                      // 5
        '    A: int32;'#10 +                                        // 6
        '    overlay'#10 +                                          // 7
        '      B: int32;'#10 +                                      // 8
        '      C: uint8;'#10 +                                      // 9
        '    end;'#10 +                                             // 10
        '  end;'#10 +                                               // 11
        '  TObj = object'#10 +                                      // 12
        '    F: int32;'#10 +                                        // 13
        '    method Put(const AV: int32);'#10 +                     // 14
        '    begin'#10 +                                            // 15
        '    end;'#10 +                                             // 16
        '  end;'#10 +                                               // 17
        '  TCol = choices(cRed, cGreen);'#10 +                      // 18
        '  TAlias = int32;'#10 +                                    // 19
        'forward routine Fw(const AA: int32): int32;'#10 +          // 20
        'routine Outer(): int32;'#10 +                              // 21
        'var'#10 +                                                  // 22
        '  LX: int32;'#10 +                                         // 23
        'type'#10 +                                                 // 24
        '  TLoc = int32;'#10 +                                      // 25
        'begin'#10 +                                                // 26
        '  return 0;'#10 +                                          // 27
        'end;'#10 +                                                 // 28
        'routine Fw(const AA: int32): int32;'#10 +                  // 29
        'begin'#10 +                                                // 30
        '  return AA;'#10 +                                         // 31
        'end;'#10 +                                                 // 32
        'var'#10 +                                                  // 33
        '  /*' + #$00E9 + '*/GV: int32;'#10 +                       // 34
        'initialize'#10 +                                           // 35
        'begin'#10 +                                                // 36
        'end;'#10 +                                                 // 37
        'begin'#10 +                                                // 38
        'end.'#10 +                                                 // 39
        'test "first"'#10 +                                         // 40
        'begin'#10 +                                                // 41
        'end;'#10),                                                 // 42
      SymbolsMessage(60, LMain),
      SymbolsMessage(61, TestFile('lspt_nosyms.pcpp')),             // a document not open
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);

    // initialize advertises document symbols
    LHasSymbols := False;
    for LItem in LSession.Output do
      if IntAt(LItem, 'id') = 1 then
      begin
        LInit := LItem.GetValue('result') as TJSONObject;
        if not LInit.TryGetValue<Boolean>('capabilities.documentSymbolProvider', LHasSymbols) then
          LHasSymbols := False;
      end;
    Check(LHasSymbols, 'initialize: documentSymbolProvider true');

    // The buffer is a valid program: no report hides a missing entry
    LPublishes := Publishes(LSession, LMain);
    Check(Length(LPublishes) >= 1, 'main published');
    if Length(LPublishes) >= 1 then
    begin
      LDiagnostics := LPublishes[High(LPublishes)].GetValue('diagnostics') as TJSONArray;
      Check(LDiagnostics.Count = 0, 'main has no diagnostics (got ' + LDiagnostics.ToJSON() + ')');
    end;

    // The anonymous overlay's B and C are TRec's own; Outer lists its local
    // type, not its var; GV's name follows a 2-byte char (UTF-16 7, byte 8)
    DoExpect(60,
      'lspt_sunit/2//1:7-17/1-1;' +
      'KMax/14/int32/3:2-6/3-3;' +
      'TRec/23//5:2-6/5-11[A/8/int32/6:4-5/6-6,B/8/int32/8:6-7/8-8,C/8/uint8/9:6-7/9-9];' +
      'TObj/5//12:2-6/12-17[F/8/int32/13:4-5/13-13,Put/6/(const AV: int32)/14:11-14/14-16];' +
      'TCol/10//18:2-6/18-18[cRed/22//18:17-21/18-18,cGreen/22//18:23-29/18-18];' +
      'TAlias/26//19:2-8/19-19;' +
      'Fw/12/(const AA: int32): int32/20:16-18/20-20;' +
      'Outer/12/(): int32/21:8-13/21-28[TLoc/26//25:2-6/25-25];' +
      'Fw/12/(const AA: int32): int32/29:8-10/29-32;' +
      'GV/13/int32/34:7-9/34-34;' +
      'initialize/12/()/35:0-10/35-37;' +
      'first/24//40:5-12/40-42', 'the document''s outline');
    DoExpect(61, '', 'a document not open: no symbols');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestWorkspaceSymbols();
var
  LSession: TLspSession;
  LMain: string;
  LUnit: string;
  LInit: TJSONObject;
  LHas: Boolean;
  LItem: TJSONObject;

  procedure DoExpect(const AId: Integer; const AExpected: string; const ALabel: string);
  var
    LGot: string;
  begin
    LGot := WorkspaceSymbolsText(LSession, AId);
    Check(LGot = AExpected, ALabel + ' (got ' + LGot + ')');
  end;

begin
  // The editor's Go to Symbol in Workspace: every open document's own
  // declarations (documentSymbol's outline), name/kind/container@file:
  // line:start-end, counted by hand. Documents by uri: lspt_ws before
  // lspt_wsunit ('.' sorts before 'u')
  LMain := TestFile('lspt_ws.pcpp');
  LUnit := TestFile('lspt_wsunit.pcpp');

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LUnit,
        'module unit lspt_wsunit;'#10 +                             // 0
        'exported routine Helper();'#10 +                           // 1
        'begin'#10 +                                                // 2
        'end;'#10 +                                                 // 3
        'end.'#10),                                                 // 4
      OpenMessage(LMain,
        'module exe lspt_ws;'#10 +                                  // 0
        'import lspt_wsunit;'#10 +                                  // 1
        'type'#10 +                                                 // 2
        '  TPoint = record'#10 +                                    // 3
        '    X: int32;'#10 +                                        // 4
        '  end;'#10 +                                               // 5
        'routine Help(): int32;'#10 +                               // 6
        'begin'#10 +                                                // 7
        '  return 0;'#10 +                                          // 8
        'end;'#10 +                                                 // 9
        'begin'#10 +                                                // 10
        '  lspt_wsunit.Helper();'#10 +                              // 11
        'end.'#10),                                                 // 12
      WorkspaceSymbolMessage(80, ''),
      WorkspaceSymbolMessage(81, 'HELP'),
      WorkspaceSymbolMessage(82, 'zzz'),
      '{"jsonrpc":"2.0","id":83,"method":"workspace/symbol","params":{}}',
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);

    LHas := False;
    for LItem in LSession.Output do
      if IntAt(LItem, 'id') = 1 then
      begin
        LInit := LItem.GetValue('result') as TJSONObject;
        if not LInit.TryGetValue<Boolean>('capabilities.workspaceSymbolProvider', LHas) then
          LHas := False;
      end;
    Check(LHas, 'initialize: workspaceSymbolProvider true');

    // The import is no declaration; X is TPoint's member
    DoExpect(80,
      'TPoint/23/@lspt_ws.pcpp:3:2-8;' +
      'X/8/TPoint@lspt_ws.pcpp:4:4-5;' +
      'Help/12/@lspt_ws.pcpp:6:8-12;' +
      'Helper/12/@lspt_wsunit.pcpp:1:17-23', 'every symbol of the open documents');
    DoExpect(81,
      'Help/12/@lspt_ws.pcpp:6:8-12;' +
      'Helper/12/@lspt_wsunit.pcpp:1:17-23', 'a case-insensitive substring');
    DoExpect(82, '', 'no match: an empty list');
    DoExpect(83, '<error>', 'no query: invalid params');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestCallHierarchy();
var
  LSession: TLspSession;
  LMain: string;
  LUnit: string;
  LInit: TJSONObject;
  LHas: Boolean;
  LItem: TJSONObject;

  procedure DoExpect(const AGot: string; const AExpected: string; const ALabel: string);
  begin
    Check(AGot = AExpected, ALabel + ' (got ' + AGot + ')');
  end;

begin
  // The editor's Show Call Hierarchy. An item prints as name/kind/detail@
  // file:selection line:start-end/range lines, a call's sites after it in
  // < > (line:start-end, UTF-16, end exclusive, the callee as written); all
  // counted by hand. The item a client sends back carries only what the
  // server reads (uri, kind, the name's start). Documents by uri: lspt_ch
  // before lspt_chunit, whose file its analysis already walked
  LMain := TestFile('lspt_ch.pcpp');
  LUnit := TestFile('lspt_chunit.pcpp');

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LUnit,
        'module unit lspt_chunit;'#10 +                             // 0
        'exported routine Twice(const AN: int32): int32;'#10 +      // 1
        'begin'#10 +                                                // 2
        '  return AN * 2;'#10 +                                     // 3
        'end;'#10 +                                                 // 4
        'end.'#10),                                                 // 5
      OpenMessage(LMain,
        'module exe lspt_ch;'#10 +                                  // 0
        'import lspt_chunit;'#10 +                                  // 1
        'forward routine Leaf(): int32;'#10 +                       // 2
        'routine Mid(): int32;'#10 +                                // 3
        'begin'#10 +                                                // 4
        '  return Leaf() + lspt_chunit.Twice(1);'#10 +              // 5
        'end;'#10 +                                                 // 6
        'routine Top(): int32;'#10 +                                // 7
        'begin'#10 +                                                // 8
        '  return Mid() + Mid();'#10 +                              // 9
        'end;'#10 +                                                 // 10
        'routine Leaf(): int32;'#10 +                               // 11
        'begin'#10 +                                                // 12
        '  return 1;'#10 +                                          // 13
        'end;'#10 +                                                 // 14
        'var'#10 +                                                  // 15
        '  GV: int32;'#10 +                                         // 16
        'begin'#10 +                                                // 17
        '  GV := Top() + Leaf();'#10 +                              // 18
        'end.'#10),                                                 // 19
      PrepareCallsMessage(70, LMain, 9, 10),
      PrepareCallsMessage(71, LMain, 2, 17),
      PrepareCallsMessage(72, LMain, 16, 3),
      CallsMessage(73, 'callHierarchy/incomingCalls', CallItemJson(LMain, 12, 11, 8)),
      CallsMessage(74, 'callHierarchy/incomingCalls', CallItemJson(LMain, 12, 3, 8)),
      CallsMessage(75, 'callHierarchy/outgoingCalls', CallItemJson(LMain, 12, 3, 8)),
      CallsMessage(76, 'callHierarchy/incomingCalls', CallItemJson(LUnit, 12, 1, 17)),
      CallsMessage(77, 'callHierarchy/outgoingCalls', CallItemJson(LMain, 2, 0, 11)),
      '{"jsonrpc":"2.0","id":78,"method":"callHierarchy/incomingCalls","params":{}}',
      CallsMessage(79, 'callHierarchy/outgoingCalls', CallItemJson(LMain, 12, 7, 8)),
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);

    LHas := False;
    for LItem in LSession.Output do
      if IntAt(LItem, 'id') = 1 then
      begin
        LInit := LItem.GetValue('result') as TJSONObject;
        if not LInit.TryGetValue<Boolean>('capabilities.callHierarchyProvider', LHas) then
          LHas := False;
      end;
    Check(LHas, 'initialize: callHierarchyProvider true');

    // prepare: a call names its routine; a forward is its full routine; a
    // variable is no routine
    DoExpect(PrepareCallsText(LSession, 70),
      'Mid/12/(): int32@lspt_ch.pcpp:3:8-11/3-6', 'prepare at a call of Mid');
    DoExpect(PrepareCallsText(LSession, 71),
      'Leaf/12/(): int32@lspt_ch.pcpp:11:8-12/11-14', 'prepare at a forward: the full Leaf');
    DoExpect(PrepareCallsText(LSession, 72), '<null>', 'prepare at a variable');

    // incoming: by caller; the module body is the module (kind 2)
    DoExpect(CallsText(LSession, 73, 'from'),
      'Mid/12/(): int32@lspt_ch.pcpp:3:8-11/3-6<5:9-13>;' +
      'lspt_ch/2/@lspt_ch.pcpp:0:11-18/0-19<18:16-20>', 'Leaf''s callers');
    DoExpect(CallsText(LSession, 74, 'from'),
      'Top/12/(): int32@lspt_ch.pcpp:7:8-11/7-10<9:9-12,9:17-20>', 'Mid''s caller, two sites');
    // outgoing: by the routine called, into another module too
    DoExpect(CallsText(LSession, 75, 'to'),
      'Leaf/12/(): int32@lspt_ch.pcpp:11:8-12/11-14<5:9-13>;' +
      'Twice/12/(const AN: int32): int32@lspt_chunit.pcpp:1:17-22/1-4<5:18-35>', 'Mid''s calls');
    // A unit's routine called from the program; the unit's file is walked
    // once although both documents reach it
    DoExpect(CallsText(LSession, 76, 'from'),
      'Mid/12/(): int32@lspt_ch.pcpp:3:8-11/3-6<5:18-35>', 'Twice''s caller, across modules');
    DoExpect(CallsText(LSession, 77, 'to'), '', 'a module item: a leaf');
    DoExpect(CallsText(LSession, 78, 'from'), '<error>', 'no item: invalid params');
    DoExpect(CallsText(LSession, 79, 'to'),
      'Mid/12/(): int32@lspt_ch.pcpp:3:8-11/3-6<9:9-12,9:17-20>', 'Top''s calls, one group');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestHoverDocs();
var
  LSession: TLspSession;
  LMain: string;
  LGot: string;
  LExpected: string;
begin
  // E2.6: a /// doc comment shows after the declaration, Markdown with its
  // tags rendered. The expected text is written by hand from the tag rules:
  // @custom is unknown (text, ends the run), @example's lines lose their
  // shared 2-space indent, deprecation comes first
  LMain := TestFile('lspt_docs.pcpp');

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LMain,
        'module exe lspt_docs;'#10 +                                // 0
        '/// Clamps a value.'#10 +                                  // 1
        '///'#10 +                                                  // 2
        '/// Below `AMin` gives **AMin**.'#10 +                     // 3
        '/// @param AV the value'#10 +                              // 4
        '/// @param AMin lower'#10 +                                // 5
        '///   bound'#10 +                                          // 6
        '/// @returns the result'#10 +                              // 7
        '/// @raises nothing'#10 +                                  // 8
        '/// @since 1.0'#10 +                                       // 9
        '/// @see Lerp'#10 +                                        // 10
        '/// @deprecated use Clamp2'#10 +                           // 11
        '/// @custom kept'#10 +                                     // 12
        '/// @example'#10 +                                         // 13
        '///   LX := Clamp(1, 0);'#10 +                             // 14
        '///     // nested'#10 +                                    // 15
        'routine Clamp(const AV: int32; const AMin: int32): int32;'#10 + // 16
        'begin'#10 +                                                // 17
        '  return AV;'#10 +                                         // 18
        'end;'#10 +                                                 // 19
        'var'#10 +                                                  // 20
        '  /// One line.'#10 +                                      // 21
        '  LX: int32;'#10 +                                         // 22
        '  LY: int32;'#10 +                                         // 23
        'begin'#10 +                                                // 24
        '  LX := Clamp(1, 0);'#10 +                                 // 25
        '  LY := LX;'#10 +                                          // 26
        'end.'#10),                                                 // 27
      HoverMessage(70, LMain, 25, 8),             // Clamp
      HoverMessage(71, LMain, 26, 8),             // LX: one plain line
      HoverMessage(72, LMain, 26, 2),             // LY: no doc
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);

    LExpected := Fenced('routine Clamp(const AV: int32; const AMin: int32): int32') + #10#10 +
      '**Deprecated:** use Clamp2' + #10#10 +
      'Clamps a value.'#10#10'Below `AMin` gives **AMin**.'#10'@custom kept' + #10#10 +
      '**Parameters**'#10'- `AV`: the value'#10'- `AMin`: lower bound' + #10#10 +
      '**Returns:** the result' + #10#10 +
      '**Raises:** nothing' + #10#10 +
      '**Since:** 1.0' + #10#10 +
      '**See also:** `Lerp`' + #10#10 +
      '**Example**'#10'```pcpp'#10'LX := Clamp(1, 0);'#10'  // nested'#10'```';
    LGot := HoverValue(LSession, 70);
    Check(LGot = LExpected, 'every tag rendered (got ' + LGot + ')');

    LGot := HoverValue(LSession, 71);
    Check(LGot = Fenced('var LX: int32') + #10#10'One line.', 'a single /// line (got ' + LGot + ')');

    LGot := HoverValue(LSession, 72);
    Check(LGot = Fenced('var LY: int32'), 'no doc: the declaration alone (got ' + LGot + ')');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestRecovery();
var
  LSession: TLspSession;
  LMain: string;
  LPublishes: TArray<TJSONObject>;
  LDiagnostics: TJSONArray;
  LItem: TJSONValue;
  LCodes: string;
  LCode: string;
  LGot: string;
begin
  // E2.7: a syntax error does not switch off the rest. The buffer has a
  // missing ';' (PR0001), a duplicate (SM0004) and a bad argument (SM0404):
  // all three are reported, and hover and hints still work around them
  LMain := TestFile('lspt_recovery.pcpp');

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LMain,
        'module exe lspt_recovery;'#10 +                            // 0
        'routine Add(const AA: int32; const AB: int32): int32;'#10 + // 1
        'begin'#10 +                                                // 2
        '  return AA + AB;'#10 +                                    // 3
        'end;'#10 +                                                 // 4
        'var'#10 +                                                  // 5
        '  GCount: int32;'#10 +                                     // 6
        '  GCount: int32;'#10 +                                     // 7
        'begin'#10 +                                                // 8
        '  GCount := 1'#10 +                                        // 9  no ';'
        '  GCount := 2;'#10 +                                       // 10 taken by the recovery
        '  Add("x", 2);'#10 +                                       // 11
        '  GCount := Add(3, 4);'#10 +                               // 12
        'end.'#10),                                                 // 13
      HoverMessage(80, LMain, 12, 12),            // Add after the error
      InlayMessage(81, LMain, 12, 0, 13, 0),      // line 12's hints
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);

    LPublishes := Publishes(LSession, LMain);
    LCodes := '';
    if Length(LPublishes) >= 1 then
    begin
      LDiagnostics := LPublishes[High(LPublishes)].GetValue('diagnostics') as TJSONArray;
      for LItem in LDiagnostics do
      begin
        if not LItem.TryGetValue<string>('code', LCode) then
          LCode := '?';
        LCodes := LCodes + LCode + '@' + IntToStr(IntAt(LItem, 'range.start.line')) + ' ';
      end;
    end;
    // Order: the parser's report first, then the semantic pass's. The
    // missing ';' on line 9 is inserted, so line 10 parses (PLAN-RECOVERY)
    Check(LCodes.Trim() = 'PR0001@9 SM0004@7 SM0404@11',
      'syntax and semantic reports together (got ' + LCodes + ')');

    LGot := HoverValue(LSession, 80);
    Check(LGot = Fenced('routine Add(const AA: int32; const AB: int32): int32'),
      'hover after a syntax error (got ' + LGot + ')');
    LGot := InlayText(LSession, 81);
    Check(LGot = '12:16:AA:;12:19:AB:', 'hints after a syntax error (got ' + LGot + ')');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestRecoveredTrees();
var
  LFailures: TList<string>;
  LList: TList<string>;
  LRuns: Integer;
begin
  // E2.7: the semantic pass runs on every tree the parser recovered, so it
  // must never fail on one (a crash would surface as CMP0003 and hide every
  // report). The recovery corpus (ForEachRecoveryRun) in check mode
  LFailures := TList<string>.Create();
  try
    LList := LFailures;
    LRuns := ForEachRecoveryRun(
      procedure(const AFilename: string; const AHasBytes: Boolean; const ABytes: TBytes;
        const ALabel: string)
      var
        LFound: string;
      begin
        LFound := InternalErrors(AFilename, AHasBytes, ABytes);
        if LFound <> '' then
          LList.Add(ALabel + ': ' + LFound);
      end);

    Check(LRuns > 500, 'recovered_trees: the fixtures were found (' + IntToStr(LRuns) + ' runs)');
    Check(LFailures.Count = 0, 'recovered_trees: no internal error in ' + IntToStr(LRuns) +
      ' runs (got ' + IntToStr(LFailures.Count) + ': ' +
      string.Join(' | ', Copy(LFailures.ToArray(), 0, 5)) + ')');
  finally
    LFailures.Free();
  end;
end;

procedure TPCLspTests.DoTestRecoveryInvariant();
var
  LGaps: TList<string>;
  LOrphans: TList<string>;
  LControl: TList<string>;
  LGapList: TList<string>;
  LOrphanList: TList<string>;
  LFile: string;
  LBytes: TBytes;
  LCompiler: TPCCompiler;
  LBefore: Integer;
  LIntact: Integer;
  LRuns: Integer;
begin
  // PLAN-RECOVERY A11 T1: on every recovered tree (b) no token between two
  // consecutive elements of a list but a declaration block word: anything
  // else was dropped without a node; (c) every recovered or error node holds
  // a syntax report (LX / CD / PR) of its file
  LGaps := TList<string>.Create();
  LOrphans := TList<string>.Create();
  LControl := TList<string>.Create();
  try
    // Positive control first: the intact files (no syntax report) hold no
    // gap, so a gap on a broken run is the recovery's, never the rule's
    LIntact := 0;
    for LFile in RecoveryCutFiles() do
    begin
      LBytes := TFile.ReadAllBytes(LFile);
      LCompiler := AnalyseRun(LFile, True, LBytes);
      try
        if LCompiler.HasSyntaxReport('') then
          Continue;
        Inc(LIntact);
        LBefore := LControl.Count;
        CheckRecoveryRun(LCompiler, LFile, LBytes, True, LControl, LControl);
        if LControl.Count > LBefore then
          LControl[LBefore] := ExtractFileName(LFile) + ': ' + LControl[LBefore];
      finally
        FreeRun(LCompiler);
      end;
    end;
    // 44 today (2026-10-09): every sem fixture with no syntax report + lsp_*
    Check(LIntact > 40, 'recovery_invariant: intact files found (' + IntToStr(LIntact) + ')');
    Check(LControl.Count = 0, 'recovery_invariant: the intact files hold no gap (got ' +
      IntToStr(LControl.Count) + ': ' + string.Join(' | ', Copy(LControl.ToArray(), 0, 8)) + ')');

    LGapList := LGaps;
    LOrphanList := LOrphans;
    LRuns := ForEachRecoveryRun(
      procedure(const AFilename: string; const AHasBytes: Boolean; const ABytes: TBytes;
        const ALabel: string)
      var
        LRunBytes: TBytes;
        LRun: TPCCompiler;
        LGapCount: Integer;
        LOrphanCount: Integer;
      begin
        if AHasBytes then
          LRunBytes := ABytes
        else
          LRunBytes := TFile.ReadAllBytes(AFilename);
        LGapCount := LGapList.Count;
        LOrphanCount := LOrphanList.Count;
        LRun := AnalyseRun(AFilename, True, LRunBytes);
        try
          CheckRecoveryRun(LRun, AFilename, LRunBytes, True, LGapList, LOrphanList);
        finally
          FreeRun(LRun);
        end;
        // The run names its first failure of each kind
        if LGapList.Count > LGapCount then
          LGapList[LGapCount] := ALabel + ': ' + LGapList[LGapCount];
        if LOrphanList.Count > LOrphanCount then
          LOrphanList[LOrphanCount] := ALabel + ': ' + LOrphanList[LOrphanCount];
      end);

    Check(LRuns > 500, 'recovery_invariant: the corpus was found (' + IntToStr(LRuns) + ' runs)');
    Check(LGaps.Count = 0, 'recovery_invariant: (b) no token dropped without a node in ' +
      IntToStr(LRuns) + ' runs (got ' + IntToStr(LGaps.Count) + ': ' +
      string.Join(' | ', Copy(LGaps.ToArray(), 0, 8)) + ')');
    Check(LOrphans.Count = 0, 'recovery_invariant: (c) every recovered node holds a report (got ' +
      IntToStr(LOrphans.Count) + ': ' + string.Join(' | ', Copy(LOrphans.ToArray(), 0, 8)) + ')');
  finally
    LControl.Free();
    LOrphans.Free();
    LGaps.Free();
  end;
end;

procedure TPCLspTests.DoTestRecoveryAnswers();
var
  LDir: string;
  LLine: string;
  LParts: TArray<string>;
  LRowName: string;
  LIntactPath: string;
  LBrokenPath: string;
  LIntactBytes: TBytes;
  LBrokenBytes: TBytes;
  LEdit: TTextEdit;
  LIntact: TPCCompiler;
  LBroken: TPCCompiler;
  LRanges: TList<TSourceRange>;
  LExpected: TList<string>;
  LActual: TList<string>;
  LMismatches: TList<string>;
  LError: TError;
  LMapped: UInt64;
  LBrokenTokens: TArray<TPCToken>;
  LToken: TPCToken;
  LIndex: Integer;
  LUseIntact: TPCLspUse;
  LUseBroken: TPCLspUse;
  LTargetIntact: TPCNode;
  LTargetBroken: TPCNode;
  LDefIntact: string;
  LDefBroken: string;
  LHoverIntact: string;
  LHoverBroken: string;
  LCompared: Integer;
  LRows: Integer;
begin
  // PLAN-RECOVERY A11 T2: a valid file broken one way gives no wrong answer.
  // Its reports are the break's own (the row's codes) plus every report the
  // intact file gives outside the broken file's recovered nodes; hover and
  // definition at every identifier outside them equal the intact file's (a
  // use of a declaration the parser kept marked: definition only, its name).
  // Rows: scripts\zb_ed\gen_recovery_answers.py
  LDir := TPath.Combine(DoProbeDir('lsp'), 'answers');
  LRows := 0;
  LRanges := TList<TSourceRange>.Create();
  LExpected := TList<string>.Create();
  LActual := TList<string>.Create();
  LMismatches := TList<string>.Create();
  try
    for LLine in TFile.ReadAllLines(TPath.Combine(LDir, 'expected.txt'), TEncoding.UTF8) do
    begin
      if LLine.Trim() = '' then
        Continue;
      LParts := LLine.Split(['|']);
      LRowName := LParts[0];
      LIntactPath := TPath.Combine(TPath.Combine(LDir, 'intact'), LRowName + '.pcpp');
      LBrokenPath := TPath.Combine(TPath.Combine(LDir, 'broken'), LRowName + '.pcpp');
      LIntactBytes := TFile.ReadAllBytes(LIntactPath);
      LBrokenBytes := TFile.ReadAllBytes(LBrokenPath);
      LEdit := FindEdit(LIntactBytes, LBrokenBytes);
      Inc(LRows);

      LIntact := AnalyseRun(LIntactPath, True, LIntactBytes);
      LBroken := AnalyseRun(LBrokenPath, True, LBrokenBytes);
      try
        LRanges.Clear();
        RecoveredRanges(LBroken.GetMainModule(), LRanges);

        // Reports: the break's own, then the intact file's untouched ones
        LExpected.Clear();
        LActual.Clear();
        if (Length(LParts) > 1) and (LParts[1] <> '') then
          LExpected.AddRange(LParts[1].Split([',']));
        for LError in LIntact.GetErrors().GetItems() do
        begin
          if not TUtils.SamePath(LError.Range.Filename, LIntactPath) then
            Continue;
          if not LEdit.MapOffset(LError.Range.StartByteOffset, LMapped) then
            Continue;
          if InsideAny(LRanges, LMapped) then
            Continue;
          LExpected.Add(LError.Code + '@' + IntToStr(LineOfOffset(LBrokenBytes, LMapped)));
        end;
        for LError in LBroken.GetErrors().GetItems() do
        begin
          if TUtils.SamePath(LError.Range.Filename, LBrokenPath) then
            LActual.Add(LError.Code + '@' + IntToStr(LError.Range.StartLine));
        end;
        LExpected.Sort();
        LActual.Sort();
        Check(string.Join(',', LExpected.ToArray()) = string.Join(',', LActual.ToArray()),
          'recovery_answers: ' + LRowName + ' reports ' + string.Join(',', LExpected.ToArray()) +
          ' (got ' + string.Join(',', LActual.ToArray()) + ')');

        // Hover and definition at every identifier outside the recovered nodes
        LMismatches.Clear();
        LCompared := 0;
        LBrokenTokens := LexRun(LBrokenBytes, LBrokenPath);
        for LToken in LexRun(LIntactBytes, LIntactPath) do
        begin
          if LToken.Kind <> tkIdentifier then
            Continue;
          if (not LEdit.MapOffset(LToken.Range.StartByteOffset, LMapped)) or
            InsideAny(LRanges, LMapped) then
            Continue;
          LIndex := FirstTokenFrom(LBrokenTokens, LMapped);
          if (LIndex >= Length(LBrokenTokens)) or
            (LBrokenTokens[LIndex].Range.StartByteOffset <> LMapped) then
          begin
            LMismatches.Add(TokenPlace(LToken) + ': no token there in the broken file');
            Continue;
          end;
          LUseIntact := TPCLspSymbols.UseAt(LIntact.GetMainModule(), LToken.Range.StartLine,
            LToken.Range.StartColumn);
          LUseBroken := TPCLspSymbols.UseAt(LBroken.GetMainModule(),
            LBrokenTokens[LIndex].Range.StartLine, LBrokenTokens[LIndex].Range.StartColumn);
          LTargetIntact := TPCLspSymbols.TargetOf(LUseIntact);
          LTargetBroken := TPCLspSymbols.TargetOf(LUseBroken);
          LDefIntact := AnswerDefinition(LTargetIntact, LIntactPath, True, LEdit);
          // The declaration's own name was edited: nothing to compare with
          if LDefIntact = '' then
            Continue;
          LDefBroken := AnswerDefinition(LTargetBroken, LBrokenPath, False, LEdit);
          Inc(LCompared);
          if LDefIntact <> LDefBroken then
            LMismatches.Add(TokenPlace(LToken) + ': definition ' + LDefIntact + ' (got ' +
              LDefBroken + ')');
          if (LTargetBroken <> nil) and (not LTargetBroken.IsRecovered) then
          begin
            LHoverIntact := AnswerHover(LUseIntact, LTargetIntact);
            LHoverBroken := AnswerHover(LUseBroken, LTargetBroken);
            if LHoverIntact <> LHoverBroken then
              LMismatches.Add(TokenPlace(LToken) + ': hover ''' + LHoverIntact + ''' (got ''' +
                LHoverBroken + ''')');
          end;
        end;
        Check((LCompared > 0) and (LMismatches.Count = 0), 'recovery_answers: ' + LRowName +
          ' answers as intact at ' + IntToStr(LCompared) + ' uses (got ' +
          IntToStr(LMismatches.Count) + ': ' +
          string.Join(' | ', Copy(LMismatches.ToArray(), 0, 6)) + ')');
      finally
        FreeRun(LBroken);
        FreeRun(LIntact);
      end;
    end;
    Check(LRows >= 7, 'recovery_answers: the rows were found (' + IntToStr(LRows) + ')');
  finally
    LMismatches.Free();
    LActual.Free();
    LExpected.Free();
    LRanges.Free();
  end;
end;

procedure TPCLspTests.DoTestCompletion();
var
  LSession: TLspSession;
  LMain: string;
  LUnit: string;
  LBroken: string;
  LBroken2: string;
  LBroken3: string;
  LOpen: string;
  LInit: TJSONObject;
  LItem: TJSONObject;
  LTriggers: TJSONArray;
  LTriggerText: string;
  LLabels: string;
  LPublishes: TArray<TJSONObject>;
  LDiagnostics: TJSONArray;
  LIncomplete: Boolean;
  LNull: Boolean;

  procedure DoLabels(const AId: Integer; const AExpected: string; const ALabel: string);
  var
    LGot: string;
  begin
    LGot := CompletionLabels(LSession, AId);
    Check(LGot = AExpected, ALabel + ' (got ' + LGot + ')');
  end;

  procedure DoItem(const AId: Integer; const AName: string; const AExpected: string;
    const ALabel: string);
  var
    LGot: string;
  begin
    LGot := CompletionItem(LSession, AId, AName);
    Check(LGot = AExpected, ALabel + ' (got ' + LGot + ')');
  end;

  function DoBroken(const ALine: string): string;
  begin
    // A valid prefix, then one unfinished line before the module's end
    Result :=
      'module exe lspt_complete_b;'#10 +                            // 0
      'import lspt_cunit;'#10 +                                     // 1
      'type'#10 +                                                   // 2
      '  TRec = record'#10 +                                        // 3
      '    RA: int32;'#10 +                                         // 4
      '  end;'#10 +                                                 // 5
      'var'#10 +                                                    // 6
      '  GR: TRec;'#10 +                                            // 7
      '  GP: ptr to TRec;'#10 +                                     // 8
      'begin'#10 +                                                  // 9
      ALine + #10 +                                                 // 10
      'end.'#10;                                                    // 11
  end;

begin
  // Every file is an open buffer. Positions are 0-based line, UTF-16
  // character, as the client sends them; every expected list is written by
  // hand from the buffers (scope order: innermost frame first, list order)
  LMain := TestFile('lspt_complete.pcpp');
  LUnit := TestFile('lspt_cunit.pcpp');
  LBroken := TestFile('lspt_complete_b.pcpp');
  LBroken2 := TestFile('lspt_complete_b2.pcpp');
  LBroken3 := TestFile('lspt_complete_b3.pcpp');
  LOpen := TestFile('lspt_complete_c.pcpp');

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LUnit,
        'module unit lspt_cunit;'#10 +
        'exported routine UPub(const AX: int32): int32;'#10 +
        'begin'#10 +
        '  return AX;'#10 +
        'end;'#10 +
        'routine UHid();'#10 +
        'begin'#10 +
        'end;'#10 +
        'end.'#10),
      OpenMessage(LMain,
        'module exe lspt_complete;'#10 +                            // 0
        'import lspt_cunit;'#10 +                                   // 1
        'type'#10 +                                                 // 2
        '  TCol = choices(CRed, CGreen);'#10 +                      // 3
        '  TBase = object'#10 +                                     // 4
        '    BF: int32;'#10 +                                       // 5
        '    hidden method BM();'#10 +                              // 6
        '    begin'#10 +                                            // 7
        '    end;'#10 +                                             // 8
        '  end;'#10 +                                               // 9
        '  TObj = object(TBase)'#10 +                               // 10
        '    OF1: int32;'#10 +                                      // 11
        '    method OM(const AP: int32);'#10 +                      // 12
        '    begin'#10 +                                            // 13
        '      self.OF1 := AP + self.BF;'#10 +                      // 14
        '    end;'#10 +                                             // 15
        '  end;'#10 +                                               // 16
        '  TRec = record'#10 +                                      // 17
        '    RA: int32;'#10 +                                       // 18
        '    overlay'#10 +                                          // 19
        '      RB: int32;'#10 +                                     // 20
        '      RC: float64;'#10 +                                   // 21
        '    end;'#10 +                                             // 22
        '  end;'#10 +                                               // 23
        'var'#10 +                                                  // 24
        '  GR: TRec;'#10 +                                          // 25
        '  GP: ptr to TRec;'#10 +                                   // 26
        '  GO: TObj;'#10 +                                          // 27
        '  GC: TCol;'#10 +                                          // 28
        '  GS: int32;'#10 +                                         // 29
        '  GSt: string;'#10 +                                       // 30
        'forward routine Fw(const AA: int32): int32;'#10 +          // 31
        'routine Sum(const AA: int32; const AB: int32): int32;'#10 + // 32
        'var'#10 +                                                  // 33
        '  GS: int64;'#10 +                                         // 34
        '  GT: int32;'#10 +                                         // 35
        'begin'#10 +                                                // 36
        '  GT := AA + AB;'#10 +                                     // 37
        '  GS := GT;'#10 +                                          // 38
        '  return GT;'#10 +                                         // 39
        'end;'#10 +                                                 // 40
        'routine Zero(): int32;'#10 +                               // 41
        'begin'#10 +                                                // 42
        '  return 0;'#10 +                                          // 43
        'end;'#10 +                                                 // 44
        'routine Fw(const AA: int32): int32;'#10 +                  // 45
        'begin'#10 +                                                // 46
        '  return Sum(AA, Zero());'#10 +                            // 47
        'end;'#10 +                                                 // 48
        'routine V(const AN: int32; ...);'#10 +                     // 49
        'var'#10 +                                                  // 50
        '  LV: varargs = varargs.copy();'#10 +                      // 51
        'begin'#10 +                                                // 52
        '  GS := varargs.next(int32);'#10 +                         // 53
        '  LV.reset();'#10 +                                        // 54
        'end;'#10 +                                                 // 55
        'begin'#10 +                                                // 56
        '  GS := Fw(1);'#10 +                                       // 57
        '  GR.RA := GR.RB;'#10 +                                    // 58
        '  GP->RA := lspt_cunit.UPub(2);'#10 +                      // 59
        '  GC := TCol.CGreen;'#10 +                                 // 60
        '  GO.OM(3);'#10 +                                          // 61
        '  puts("' + #$00E9 + '"); GS := GS + 1;'#10 +              // 62
        '  GS := int32(len(GSt));'#10 +                             // 63
        '  puts(GSt.c_str());'#10 +                                 // 64
        '  // GS in a comment'#10 +                                 // 65
        '  puts("GS");'#10 +                                        // 66
        'end.'#10),                                                 // 67
      // Each unfinished access alone (on adjacent lines `GR.` and the next
      // line's name would read as one access)
      OpenMessage(LBroken, DoBroken('  GR.')),
      OpenMessage(LBroken2, DoBroken('  GP->')),
      OpenMessage(LBroken3, DoBroken('  lspt_cunit.')),
      OpenMessage(LOpen,
        'module exe lspt_complete_c;'#10 +                          // 0
        'routine R(const AQ: int32);'#10 +                          // 1
        'begin'#10 +                                                // 2
        '  '),                                                      // 3: no end yet
      CompletionMessage(10, LMain, 57, 3, ''),      // G| in the module body
      CompletionMessage(11, LMain, 37, 3, ''),      // G| in Sum's body
      CompletionMessage(12, LMain, 35, 3, ''),      // G| on Sum's local GT's own name
      CompletionMessage(13, LMain, 37, 9, ''),      // A| in Sum's body
      CompletionMessage(14, LMain, 57, 9, ''),      // F| forward + full
      CompletionMessage(15, LMain, 47, 10, ''),     // S| Sum (a call snippet)
      CompletionMessage(16, LMain, 47, 18, ''),     // Z| Zero (no parameters)
      CompletionMessage(17, LMain, 62, 14, ''),     // G| after a 2-byte char
      CompletionMessage(18, LMain, 58, 5, '.'),     // GR.| record + anonymous overlay
      CompletionMessage(19, LMain, 58, 6, ''),      // GR.R| with a prefix
      CompletionMessage(20, LMain, 61, 5, '.'),     // GO.| object + parent
      CompletionMessage(21, LMain, 14, 12, ''),     // self.O| in a method: its members
      CompletionMessage(22, LMain, 14, 29, ''),     // self.B| the parent's, hidden too
      CompletionMessage(23, LMain, 59, 23, '.'),    // lspt_cunit.| exported only
      CompletionMessage(24, LMain, 59, 6, '>'),     // GP->| typed as '>'
      CompletionMessage(25, LMain, 58, 5, '>'),     // a '>' trigger after '.': null
      CompletionMessage(26, LMain, 60, 13, '.'),    // TCol.| choice values
      CompletionMessage(27, LMain, 64, 11, '.'),    // GSt.| a string: opaque, empty
      CompletionMessage(28, LMain, 65, 8, ''),      // in a comment: null
      CompletionMessage(29, LMain, 66, 9, ''),      // in a string: null
      CompletionMessage(30, LMain, 63, 16, ''),     // le| intrinsic + keyword
      CompletionMessage(31, LMain, 29, 7, ''),      // i| types + keywords
      CompletionMessage(32, LMain, 53, 16, '.'),    // varargs.| words
      CompletionMessage(33, LMain, 54, 5, '.'),     // LV.| a varargs local's words
      CompletionMessage(34, LBroken, 10, 5, '.'),   // GR.| no name yet
      CompletionMessage(35, LBroken2, 10, 6, '>'),  // GP->| no name yet
      CompletionMessage(36, LBroken3, 10, 13, '.'), // lspt_cunit.| no name yet
      CompletionMessage(37, LOpen, 3, 2, ''),       // a routine with no end yet
      CompletionMessage(38, TestFile('lspt_nocomplete.pcpp'), 0, 0, ''),  // not open
      CompletionMessage(39, LMain, 14, 6, ''),      // | a bare name in a method: no member
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);

    // initialize advertises completion, triggered by '.' and '>'
    LTriggerText := '';
    for LItem in LSession.Output do
      if IntAt(LItem, 'id') = 1 then
      begin
        LInit := LItem.GetValue('result') as TJSONObject;
        if LInit.TryGetValue<TJSONArray>('capabilities.completionProvider.triggerCharacters', LTriggers) then
          LTriggerText := LTriggers.ToJSON();
      end;
    Check(LTriggerText = '[".",">"]', 'initialize: completion triggers (got ' + LTriggerText + ')');

    // The main buffer is a valid program: every list is SEM's scope
    LPublishes := Publishes(LSession, LMain);
    Check(Length(LPublishes) >= 1, 'main published');
    if Length(LPublishes) >= 1 then
    begin
      LDiagnostics := LPublishes[High(LPublishes)].GetValue('diagnostics') as TJSONArray;
      Check(LDiagnostics.Count = 0, 'main has no diagnostics (got ' + LDiagnostics.ToJSON() + ')');
    end;
    for LItem in LSession.Output do
      if IntAt(LItem, 'id') = 10 then
      begin
        if not LItem.TryGetValue<Boolean>('result.isIncomplete', LIncomplete) then
          LIncomplete := True;
        Check(not LIncomplete, 'isIncomplete false');
      end;

    // Scope: the module's names (case-sensitive: no getmem for 'G')
    DoLabels(10, 'GR,GP,GO,GC,GS,GSt', 'module body');
    // Sum's frame first: its local GS hides the module's GS
    DoLabels(11, 'GS,GT,GR,GP,GO,GC,GSt', 'routine body: locals first, shadowing');
    DoItem(11, 'GS', '6|1|var GS: int64||', 'the inner GS');
    DoLabels(12, 'GS,GR,GP,GO,GC,GSt', 'a local sees only the items before it');
    DoLabels(13, 'AA,AB', 'parameters');
    DoLabels(14, 'Fw', 'a forward and its full routine: one entry');
    DoItem(14, 'Fw', '3|1|routine Fw(const AA: int32): int32|Fw(${1:AA})|2', 'Fw snippet');
    DoLabels(15, 'Sum', 'a routine before the current one');
    DoItem(15, 'Sum', '3|1|routine Sum(const AA: int32; const AB: int32): int32|Sum(${1:AA}, ${2:AB})|2',
      'Sum snippet');
    DoItem(16, 'Zero', '3|1|routine Zero(): int32||', 'no parameters: plain');
    DoLabels(17, 'GR,GP,GO,GC,GS,GSt', 'after a 2-byte char');

    // Members
    DoLabels(18, 'RA,RB,RC', 'record fields + anonymous overlay');
    DoItem(18, 'RC', '5|1|RC: float64||', 'field item');
    DoLabels(19, 'RA,RB,RC', 'member prefix');
    // PLAN-OBJECT D10: the hidden BM is not listed outside TBase's line
    DoLabels(20, 'OF1,OM,BF', 'object members, then the parent''s (not the hidden BM)');
    DoItem(20, 'OM', '2|1|method OM(const AP: int32)|OM(${1:AP})|2', 'method item');
    // PLAN-OBJECT D9: a method reaches its members through self.
    DoLabels(21, 'OF1,OM', 'self. lists its members');
    DoLabels(22, 'BF,BM', 'self. lists its parent''s members, the hidden BM too');
    DoLabels(23, 'UPub', 'a module''s exported names only');
    DoLabels(24, 'RA,RB,RC', '''->'' on a typed pointer');
    DoLabels(25, '<null>', 'a ''>'' that ends no ''->'': no list');
    DoLabels(26, 'CRed,CGreen', 'choice values');
    DoItem(26, 'CRed', '20|1|CRed: TCol = 0||', 'choice value item');
    DoLabels(27, '', 'opaque left side: empty');
    CompletionList(LSession, 27, LNull);
    Check(not LNull, 'opaque left side: a list, not null');
    DoLabels(28, '<null>', 'inside a comment');
    DoLabels(29, '<null>', 'inside a string');

    // The system scope and the lexer's words, ranked after declarations
    DoItem(30, 'len', '3|1|len(string, wstring or array)||', 'intrinsic');
    DoItem(30, 'leave', '14|9|||', 'keyword');
    DoItem(31, 'int32', '25|8|||', 'builtin type');
    DoItem(31, 'import', '14|9|||', 'keyword after types');

    // varargs words (one table)
    DoLabels(32, 'count,next,get,reset,copy', 'varargs.');
    DoItem(32, 'next', '2|1|varargs.next(T)|next($0)|2', 'varargs.next item');
    DoLabels(33, 'count,next,get,reset,copy', 'a varargs local');

    // Recovery: the parser kept the left side
    DoLabels(34, 'RA', 'a. with no name yet');
    DoLabels(35, 'RA', 'p-> with no name yet');
    DoLabels(36, 'UPub', 'M. with no name yet');
    Check((',' + CompletionLabels(LSession, 37) + ',').Contains(',AQ,'),
      'a routine with no end yet: its parameters (got ' + CompletionLabels(LSession, 37) + ')');
    DoLabels(38, '<null>', 'a document not open');
    // PLAN-OBJECT D9: no member is a bare name (SM0018); the parameter and the
    // module's names declared before it are
    LLabels := ',' + CompletionLabels(LSession, 39) + ',';
    Check(LLabels.Contains(',AP,') and LLabels.Contains(',TBase,') and (not LLabels.Contains(',OF1,')) and
      (not LLabels.Contains(',BF,')) and (not LLabels.Contains(',OM,')),
      'a bare name in a method: no member (got ' + LLabels + ')');
  finally
    FreeSession(LSession);
  end;
end;

{ ApplyFormatEdits }
// The buffer with AEdits applied (ascending, never overlapping: one per gap)
function ApplyFormatEdits(const ABytes: TBytes; const AEdits: TPCLspFormatEdits): TBytes;
var
  LStream: TMemoryStream;
  LPos: Int64;
  LEdit: TPCLspFormatEdit;
  LText: TBytes;
  LResult: TBytes;
begin
  LStream := TMemoryStream.Create();
  try
    LPos := 0;
    for LEdit in AEdits do
    begin
      if LEdit.StartOffset > LPos then
        LStream.WriteBuffer(ABytes[LPos], LEdit.StartOffset - LPos);
      LText := TEncoding.UTF8.GetBytes(LEdit.NewText);
      if Length(LText) > 0 then
        LStream.WriteBuffer(LText[0], Length(LText));
      LPos := LEdit.EndOffset;
    end;
    if Length(ABytes) > LPos then
      LStream.WriteBuffer(ABytes[LPos], Length(ABytes) - LPos);
    SetLength(LResult, LStream.Size);
    if LStream.Size > 0 then
      Move(LStream.Memory^, LResult[0], LStream.Size);
  finally
    LStream.Free();
  end;
  Result := LResult;
end;

{ FormatsToNothing }
// ABytes, analysed as AFilename (the editor's way), has no syntax report and
// formats to no edits
function FormatsToNothing(const AFormatter: TPCLspFormatter; const AFilename: string;
  const ABytes: TBytes): Boolean;
var
  LCompiler: TPCCompiler;
  LEdits: TPCLspFormatEdits;
begin
  LCompiler := AnalyseRun(AFilename, True, ABytes);
  try
    Result := (not LCompiler.HasSyntaxReport('')) and
      AFormatter.FormatSource(ABytes, AFilename, LCompiler.GetMainModule(), True,
      TPCLspFormatOptions.Defaults(), LEdits) and (Length(LEdits) = 0);
  finally
    FreeRun(LCompiler);
  end;
end;

{ FormatMessage }
function FormatMessage(const AId: Integer; const AFilename: string; const AOptions: string): string;
begin
  Result := Format('{"jsonrpc":"2.0","id":%d,"method":"textDocument/formatting","params":' +
    '{"textDocument":{"uri":%s},"options":%s}}',
    [AId, JsonText(TPCLspUri.FromFilename(AFilename)), AOptions]);
end;

{ RangeFormatMessage }
function RangeFormatMessage(const AId: Integer; const AFilename: string; const AOptions: string;
  const AStartLine: Integer; const AStartCharacter: Integer; const AEndLine: Integer;
  const AEndCharacter: Integer): string;
begin
  Result := Format('{"jsonrpc":"2.0","id":%d,"method":"textDocument/rangeFormatting","params":' +
    '{"textDocument":{"uri":%s},"range":{"start":{"line":%d,"character":%d},' +
    '"end":{"line":%d,"character":%d}},"options":%s}}',
    [AId, JsonText(TPCLspUri.FromFilename(AFilename)), AStartLine, AStartCharacter, AEndLine,
    AEndCharacter, AOptions]);
end;

{ ResultArray }
// The result array of the reply to request AId; nil when there is none
function ResultArray(const ASession: TLspSession; const AId: Integer): TJSONArray;
var
  LItem: TJSONObject;
  LValue: TJSONValue;
begin
  Result := nil;
  for LItem in ASession.Output do
  begin
    if IntAt(LItem, 'id') <> AId then
      Continue;
    LValue := LItem.GetValue('result');
    if LValue is TJSONArray then
      Exit(TJSONArray(LValue));
  end;
end;

{ ShownMessages }
// Every window/showMessage the server sent, as 'type:message' lines
function ShownMessages(const ASession: TLspSession): string;
var
  LItem: TJSONObject;
  LMethod: string;
  LText: string;
begin
  Result := '';
  for LItem in ASession.Output do
  begin
    if not (LItem.TryGetValue<string>('method', LMethod) and (LMethod = 'window/showMessage')) then
      Continue;
    if not LItem.TryGetValue<string>('params.message', LText) then
      LText := '';
    Result := Result + IntToStr(IntAt(LItem, 'params.type')) + ':' + LText + #10;
  end;
end;

{ OffsetOfPosition }
// A 0-based line and UTF-16 character of AText (LF lines) as a 0-based
// index into it
function OffsetOfPosition(const AText: string; const ALine: Integer;
  const ACharacter: Integer): Integer;
var
  LLine: Integer;
  LI: Integer;
begin
  LLine := 0;
  LI := 1;
  while (LLine < ALine) and (LI <= Length(AText)) do
  begin
    if AText[LI] = #10 then
      Inc(LLine);
    Inc(LI);
  end;
  Result := LI - 1 + ACharacter;
end;

{ ApplyLspEdits }
// AText with the TextEdits of AEdits applied, as a client applies them
// (UTF-16 positions in the text before any edit; the server's edits are
// ascending and never overlap, so applying from the last keeps the others'
// positions)
function ApplyLspEdits(const AText: string; const AEdits: TJSONArray): string;
var
  LI: Integer;
  LEdit: TJSONValue;
  LStart: Integer;
  LEnd: Integer;
  LNewText: string;
begin
  Result := AText;
  for LI := AEdits.Count - 1 downto 0 do
  begin
    LEdit := AEdits.Items[LI];
    LStart := OffsetOfPosition(AText, IntAt(LEdit, 'range.start.line'),
      IntAt(LEdit, 'range.start.character'));
    LEnd := OffsetOfPosition(AText, IntAt(LEdit, 'range.end.line'),
      IntAt(LEdit, 'range.end.character'));
    if not LEdit.TryGetValue<string>('newText', LNewText) then
      LNewText := '';
    Result := Copy(Result, 1, LStart) + LNewText + Copy(Result, LEnd + 1, MaxInt);
  end;
end;

procedure TPCLspTests.DoTestFormattingServer();
const
  // The editor's FormattingOptions (renderer.js): the defaults, then a tab
  // size and a pcpp.* key the defaults do not have
  CDefaults = '{"tabSize":2,"insertSpaces":true}';
  CWide = '{"tabSize":4,"insertSpaces":true,"pcpp.spaceAroundAssign":false}';
  CTabs = '{"tabSize":4,"insertSpaces":false}';
  CNarrow = '{"tabSize":2,"insertSpaces":true,"pcpp.maxLineLength":60}';
var
  LSession: TLspSession;
  LMain: string;
  LBad: string;
  LLong: string;
  LText: string;
  LLongText: string;
  LExpected: string;
  LWide: string;
  LTabbed: string;
  LNarrow: string;
  LRanged: string;
  LEdits: TJSONArray;
  LItem: TJSONObject;
  LHasFormat: Boolean;
  LHasRange: Boolean;
begin
  // E2.10 f8: the server's two requests over a session. Line 6 holds a
  // 2-byte character before the edits on it (UTF-16 1 unit): a byte column
  // taken as a character lands one place off. Every expected text by hand
  LMain := TestFile('lspt_fmt.pcpp');
  LBad := TestFile('lspt_fmtbad.pcpp');
  LText :=
    'module exe lspt_fmt;'#10 +                                    // 0
    'var'#10 +                                                     // 1
    'A: int32;'#10 +                                               // 2
    'B: int32;'#10 +                                               // 3
    'begin'#10 +                                                   // 4
    'A:=1;   B :=  2;'#10 +                                        // 5
    'B := /*' + #$00E9 + '*/ A+1; // ' + #$00E9 + #10 +            // 6
    'end.'#10;                                                     // 7
  LExpected :=
    'module exe lspt_fmt;'#10 +
    'var'#10 +
    '  A: int32;'#10 +
    '  B: int32;'#10 +
    'begin'#10 +
    '  A := 1;'#10 +
    '  B :=  2;'#10 +
    '  B := /*' + #$00E9 + '*/ A + 1; // ' + #$00E9 + #10 +
    'end.'#10;
  // tabSize 4, pcpp.spaceAroundAssign off: ':=' hugs; the gap holding the
  // comment stays as written
  LWide :=
    'module exe lspt_fmt;'#10 +
    'var'#10 +
    '    A: int32;'#10 +
    '    B: int32;'#10 +
    'begin'#10 +
    '    A:=1;'#10 +
    '    B:=2;'#10 +
    '    B:= /*' + #$00E9 + '*/ A + 1; // ' + #$00E9 + #10 +
    'end.'#10;
  // insertSpaces false: a tab per level
  LTabbed :=
    'module exe lspt_fmt;'#10 +
    'var'#10 +
    #9'A: int32;'#10 +
    #9'B: int32;'#10 +
    'begin'#10 +
    #9'A := 1;'#10 +
    #9'B :=  2;'#10 +
    #9'B := /*' + #$00E9 + '*/ A + 1; // ' + #$00E9 + #10 +
    'end.'#10;
  // 65 columns: fits the default 80; pcpp.maxLineLength 60 breaks it after
  // the outermost '+' (column 56)
  LLong := TestFile('lspt_fmtlong.pcpp');
  LLongText :=
    'module exe lspt_fmtlong;'#10 +
    'var'#10 +
    '  A: int32;'#10 +
    'begin'#10 +
    '  A := 1000000 + 2000000 + 3000000 + 4000000 + 5000000 + 6000000;'#10 +
    'end.'#10;
  LNarrow :=
    'module exe lspt_fmtlong;'#10 +
    'var'#10 +
    '  A: int32;'#10 +
    'begin'#10 +
    '  A := 1000000 + 2000000 + 3000000 + 4000000 + 5000000 +'#10 +
    '    6000000;'#10 +
    'end.'#10;
  // Line 6 alone: its line start belongs to the gap that starts on line 5
  LRanged :=
    'module exe lspt_fmt;'#10 +
    'var'#10 +
    'A: int32;'#10 +
    'B: int32;'#10 +
    'begin'#10 +
    'A:=1;   B :=  2;'#10 +
    'B := /*' + #$00E9 + '*/ A + 1; // ' + #$00E9 + #10 +
    'end.'#10;

  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LMain, LText),
      OpenMessage(LBad, 'module exe lspt_fmtbad;'#10'begin'#10'  A := ;'#10'end.'#10),
      OpenMessage(LLong, LLongText),
      FormatMessage(70, LMain, CDefaults),
      FormatMessage(71, LMain, CWide),
      RangeFormatMessage(72, LMain, CDefaults, 6, 0, 6, 20),
      FormatMessage(73, LBad, CDefaults),
      FormatMessage(74, LMain, CTabs),
      FormatMessage(75, LLong, CDefaults),
      FormatMessage(76, LLong, CNarrow),
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);

    // initialize advertises both requests
    LHasFormat := False;
    LHasRange := False;
    for LItem in LSession.Output do
      if IntAt(LItem, 'id') = 1 then
      begin
        if not LItem.TryGetValue<Boolean>('result.capabilities.documentFormattingProvider',
          LHasFormat) then
          LHasFormat := False;
        if not LItem.TryGetValue<Boolean>('result.capabilities.documentRangeFormattingProvider',
          LHasRange) then
          LHasRange := False;
      end;
    Check(LHasFormat, 'initialize: documentFormattingProvider true');
    Check(LHasRange, 'initialize: documentRangeFormattingProvider true');

    LEdits := ResultArray(LSession, 70);
    Check(LEdits <> nil, 'formatting: an edit array');
    if LEdits <> nil then
      Check(ApplyLspEdits(LText, LEdits) = LExpected,
        'formatting: the edits give the expected text (got:' + #10 +
        ApplyLspEdits(LText, LEdits) + ')');

    LEdits := ResultArray(LSession, 71);
    Check(LEdits <> nil, 'formatting options: an edit array');
    if LEdits <> nil then
      Check(ApplyLspEdits(LText, LEdits) = LWide,
        'formatting options: tabSize + pcpp.spaceAroundAssign read (got:' + #10 +
        ApplyLspEdits(LText, LEdits) + ')');

    LEdits := ResultArray(LSession, 72);
    Check(LEdits <> nil, 'rangeFormatting: an edit array');
    if LEdits <> nil then
      Check(ApplyLspEdits(LText, LEdits) = LRanged,
        'rangeFormatting: only the edits starting in the range (got:' + #10 +
        ApplyLspEdits(LText, LEdits) + ')');

    LEdits := ResultArray(LSession, 74);
    Check(LEdits <> nil, 'formatting with tabs: an edit array');
    if LEdits <> nil then
      Check(ApplyLspEdits(LText, LEdits) = LTabbed,
        'formatting with tabs: insertSpaces false indents with tabs (got:' + #10 +
        ApplyLspEdits(LText, LEdits) + ')');

    LEdits := ResultArray(LSession, 75);
    Check((LEdits <> nil) and (LEdits.Count = 0),
      'formatting a 65-column line: no edits at the default 80');
    LEdits := ResultArray(LSession, 76);
    Check(LEdits <> nil, 'formatting at 60: an edit array');
    if LEdits <> nil then
      Check(ApplyLspEdits(LLongText, LEdits) = LNarrow,
        'formatting at 60: pcpp.maxLineLength read (got:' + #10 +
        ApplyLspEdits(LLongText, LEdits) + ')');

    // A syntax error refuses: no edits, a warning the user sees (Q6)
    LEdits := ResultArray(LSession, 73);
    Check((LEdits <> nil) and (LEdits.Count = 0), 'formatting a broken file: []');
    Check(ShownMessages(LSession) = '2:' + RSLspFmtRefuseSyntax + #10,
      'formatting a broken file: one warning (got ' + ShownMessages(LSession) + ')');
  finally
    FreeSession(LSession);
  end;
end;

procedure TPCLspTests.DoTestFormattingCore();
var
  LFormatter: TPCLspFormatter;
  LCompiler: TPCCompiler;
  LFile: string;
  LBytes: TBytes;
  LAgain: TBytes;
  LEdits: TPCLspFormatEdits;
  LIntact: Integer;
  LBad: TList<string>;
  LHover: string;
begin
  // E2.10 f2: every intact file of the corpus (RecoveryCutFiles, no syntax
  // report) formats without a refusal, and its result, analysed again,
  // formats to no edits (idempotence: the first run's tree holds the old
  // text's offsets, so it is never reused)
  LFormatter := TPCLspFormatter.Create();
  LBad := TList<string>.Create();
  try
    LIntact := 0;
    for LFile in RecoveryCutFiles() do
    begin
      LBytes := TFile.ReadAllBytes(LFile);
      LCompiler := AnalyseRun(LFile, True, LBytes);
      try
        if LCompiler.HasSyntaxReport('') then
          Continue;
        Inc(LIntact);
        if not LFormatter.FormatSource(LBytes, LFile, LCompiler.GetMainModule(), True,
          TPCLspFormatOptions.Defaults(), LEdits) then
        begin
          LBad.Add(ExtractFileName(LFile) + ' refused: ' + LFormatter.RefusalReason);
          Continue;
        end;
        LAgain := ApplyFormatEdits(LBytes, LEdits);
        if not FormatsToNothing(LFormatter, LFile, LAgain) then
          LBad.Add(ExtractFileName(LFile) + ': not idempotent');
      finally
        FreeRun(LCompiler);
      end;
    end;
    Check(LIntact > 40, 'formatting_core: intact files found (' + IntToStr(LIntact) + ')');
    Check(LBad.Count = 0, 'formatting_core: every intact file formats and is idempotent (got ' +
      IntToStr(LBad.Count) + ': ' + string.Join(' | ', Copy(LBad.ToArray(), 0, 6)) + ')');

    // Refusals and the blank buffer, on a real analysed module
    LHover := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'res\tests\lsp_hover.pcpp');
    LBytes := TFile.ReadAllBytes(LHover);
    LCompiler := AnalyseRun(LHover, True, LBytes);
    try
      Check(not LFormatter.FormatSource(LBytes, LHover, LCompiler.GetMainModule(), False,
        TPCLspFormatOptions.Defaults(), LEdits) and (LFormatter.Refusal = frSyntax) and
        (Length(LEdits) = 0), 'formatting_core: a file with a syntax report is refused');
      Check(not LFormatter.FormatSource(LBytes, LHover, nil, True,
        TPCLspFormatOptions.Defaults(), LEdits) and (LFormatter.Refusal = frSyntax),
        'formatting_core: no module is refused');
      LBytes := TEncoding.UTF8.GetBytes('module exe m;' + #10 + 'var A: string = "x' + #10);
      Check(not LFormatter.FormatSource(LBytes, LHover, LCompiler.GetMainModule(), True,
        TPCLspFormatOptions.Defaults(), LEdits) and (LFormatter.Refusal = frSyntax),
        'formatting_core: the formatter''s own lexer report refuses');
      LBytes := TEncoding.UTF8.GetBytes('   ' + #10 + #10);
      Check(LFormatter.FormatSource(LBytes, LHover, LCompiler.GetMainModule(), True,
        TPCLspFormatOptions.Defaults(), LEdits) and (Length(LEdits) = 0),
        'formatting_core: a blank buffer stays as it is');
    finally
      FreeRun(LCompiler);
    end;
  finally
    LBad.Free();
    LFormatter.Free();
  end;
end;

procedure TPCLspTests.DoTestFormatting();
var
  LFormatter: TPCLspFormatter;
  LCompiler: TPCCompiler;
  LDir: string;
  LFile: string;
  LBytes: TBytes;
  LExpected: TBytes;
  LActual: TBytes;
  LEdits: TPCLspFormatEdits;
  LRows: Integer;
  LName: string;
begin
  // E2.10 golden pairs (scripts\zb_ed\gen_fmt.py, expected by hand): each
  // row's input formats to its .expected bytes, and the expected text
  // formats to no edits
  LFormatter := TPCLspFormatter.Create();
  try
    LDir := DoProbeDir('lsp\fmt');
    LRows := 0;
    for LFile in TDirectory.GetFiles(LDir, 'f*.pcpp') do
    begin
      LName := TPath.GetFileNameWithoutExtension(LFile);
      if not TFile.Exists(TPath.ChangeExtension(LFile, '.expected')) then
        Continue;
      Inc(LRows);
      LBytes := TFile.ReadAllBytes(LFile);
      LExpected := TFile.ReadAllBytes(TPath.ChangeExtension(LFile, '.expected'));
      LCompiler := AnalyseRun(LFile, True, LBytes);
      try
        if LCompiler.HasSyntaxReport('') then
        begin
          Check(False, LName + ': the input has a syntax report');
          Continue;
        end;
        if not LFormatter.FormatSource(LBytes, LFile, LCompiler.GetMainModule(), True,
          TPCLspFormatOptions.Defaults(), LEdits) then
        begin
          Check(False, LName + ': refused (' + LFormatter.RefusalReason + ')');
          Continue;
        end;
        LActual := ApplyFormatEdits(LBytes, LEdits);
        Check(TEncoding.UTF8.GetString(LActual) = TEncoding.UTF8.GetString(LExpected),
          LName + ': formats to the expected text (got:' + #10 +
          TEncoding.UTF8.GetString(LActual) + ')');
        Check(FormatsToNothing(LFormatter, LFile, LExpected),
          LName + ': the expected text formats to no edits');
      finally
        FreeRun(LCompiler);
      end;
    end;
    Check(LRows >= 10, 'formatting: rows found (' + IntToStr(LRows) + ')');
  finally
    LFormatter.Free();
  end;
end;

procedure TPCLspTests.DoTestJsonReads();
var
  LSession: TLspSession;
  LFile: string;
  LUri: string;
  LGood: string;
  LBad: string;
  LText: string;
  LItem: TJSONObject;
  LPublishes: TArray<TJSONObject>;
  LLast: TJSONObject;
  LLogged: Boolean;
begin
  // Ids: a string comes back as that string; one that is neither an integer
  // nor a string (1.5, null) is InvalidRequest with id null; the text null is
  // JSON (InvalidRequest), not a parse error
  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      '{"jsonrpc":"2.0","id":"abc","method":"textDocument/nothing","params":{}}',
      '{"jsonrpc":"2.0","id":1.5,"method":"textDocument/nothing","params":{}}',
      '{"jsonrpc":"2.0","id":null,"method":"textDocument/nothing","params":{}}',
      'null', PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);
    Check(LSession.Output.Count = 6, 'json_reads ids: six replies (%d)', [LSession.Output.Count]);
    if LSession.Output.Count = 6 then
    begin
      LItem := LSession.Output[1];
      Check(LItem.TryGetValue<string>('id', LText) and (LText = 'abc') and
        (IntAt(LItem, 'error.code') = -32601), 'json_reads ids: a string id is echoed');
      LItem := LSession.Output[2];
      Check((LItem.GetValue('id') is TJSONNull) and (IntAt(LItem, 'error.code') = -32600),
        'json_reads ids: 1.5 is no id: InvalidRequest, id null');
      LItem := LSession.Output[3];
      Check((LItem.GetValue('id') is TJSONNull) and (IntAt(LItem, 'error.code') = -32600),
        'json_reads ids: null is no id: InvalidRequest, id null');
      LItem := LSession.Output[4];
      Check((LItem.GetValue('id') is TJSONNull) and (IntAt(LItem, 'error.code') = -32600),
        'json_reads ids: the text null is InvalidRequest, not a parse error');
    end;
  finally
    FreeSession(LSession);
  end;

  // A change list with an unreadable entry: the changes before it apply,
  // the entry and the ones after it do not, the version is not taken, and
  // the client is told (window/logMessage)
  LFile := TestFile('lspt_jreads.pcpp');
  LUri := JsonText(TPCLspUri.FromFilename(LFile));
  LGood := 'module lib lspt_jreads;'#10'var'#10'  X: int32 = 1;'#10'end.'#10;
  LBad := 'module lib lspt_jreads;'#10'var'#10'  X: int32 = 1;'#10'  X: int32 = 2;'#10'end.'#10;
  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED, OpenMessage(LFile, LGood),
      Format('{"jsonrpc":"2.0","method":"textDocument/didChange","params":' +
        '{"textDocument":{"uri":%s,"version":5},"contentChanges":[{"text":%s},' +
        '{"range":{"start":{"line":"x","character":0},"end":{"line":0,"character":0}},' +
        '"text":"junk"},{"text":%s}]}}', [LUri, JsonText(LGood), JsonText(LBad)]),
      PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession);
    LPublishes := Publishes(LSession, LFile);
    Check(Length(LPublishes) >= 1, 'json_reads change: published');
    if Length(LPublishes) >= 1 then
    begin
      LLast := LPublishes[High(LPublishes)];
      Check(IntAt(LLast, 'version') = 1, 'json_reads change: version 5 not taken (%d)',
        [IntAt(LLast, 'version')]);
      Check((LLast.GetValue('diagnostics') is TJSONArray) and
        (TJSONArray(LLast.GetValue('diagnostics')).Count = 0),
        'json_reads change: the entries after the bad one are not applied');
    end;
    LLogged := False;
    for LItem in LSession.Output do
      if LItem.TryGetValue<string>('method', LText) and (LText = 'window/logMessage') and
        LItem.TryGetValue<string>('params.message', LText) and
        (LText = Format(RSLspBadParams, ['textDocument/didChange'])) then
        LLogged := True;
    Check(LLogged, 'json_reads change: the bad entry is logged');
  finally
    FreeSession(LSession);
  end;

  // A didChange without a version still changes what a request reads: the
  // AST analysed for the old text is not reused. All at once: no
  // diagnostics check runs between the change and the hover (it would
  // analyse the new text itself and hide a stale AST)
  LFile := TestFile('lspt_jreads2.pcpp');
  LUri := JsonText(TPCLspUri.FromFilename(LFile));
  LSession := NewSession();
  try
    RunSession([PC_LSPT_INITIALIZE, PC_LSPT_INITIALIZED,
      OpenMessage(LFile, 'module lib lspt_jreads2;'#10'const'#10'  K: int32 = 1;'#10'end.'#10),
      HoverMessage(21, LFile, 2, 2),
      Format('{"jsonrpc":"2.0","method":"textDocument/didChange","params":' +
        '{"textDocument":{"uri":%s},"contentChanges":[{"text":%s}]}}',
        [LUri, JsonText('module lib lspt_jreads2;'#10'const'#10'  K: int32 = 2;'#10'end.'#10)]),
      HoverMessage(22, LFile, 2, 2), PC_LSPT_SHUTDOWN, PC_LSPT_EXIT], LSession, True);
    LText := HoverValue(LSession, 21);
    Check(LText = Fenced('const K: int32 = 1'), 'json_reads stale: hover before the change (%s)', [LText]);
    LText := HoverValue(LSession, 22);
    Check(LText = Fenced('const K: int32 = 2'), 'json_reads stale: hover after a change with no version (%s)',
      [LText]);
  finally
    FreeSession(LSession);
  end;
end;

end.
