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
  PaskalCPP.LSP.Server - the PaskalCPP language server

  JSON-RPC 2.0 over an LSP transport: the lifecycle (initialize,
  initialized, shutdown, exit), open-document sync (didOpen / didChange /
  didClose, full or incremental) and textDocument/publishDiagnostics.
  A document is checked by the build's own frontend (TPCCompiler.Analyze:
  the same module paths and target rules as a build), with every open
  buffer standing in for its file on disk. Adopted from
  FreeStrike.LSP.Server (plans\done\PLAN-EDITOR.md E2.1f).

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Resources, PaskalCPP.Parser,
    PaskalCPP.Compiler, PaskalCPP.LSP.Transport, PaskalCPP.LSP.Document,
    PaskalCPP.LSP.Diagnostics, PaskalCPP.LSP.Symbols, PaskalCPP.LSP.Hints,
    PaskalCPP.LSP.Outline, PaskalCPP.LSP.Uri, StdApp.JSON (reads; replies
    are built with System.JSON)
  Notes:
    - One message at a time on the calling thread; every request gets
      exactly one response. $/cancelRequest therefore has nothing to cancel.
    - Before initialize: requests -> ServerNotInitialized, notifications
      dropped (except exit). After shutdown: requests -> InvalidRequest.
      Exit code 0 when shutdown came before exit (or before the input
      ended), else 1.
    - Diagnostics run once the input is idle: changes that arrive while a
      check runs are coalesced into the next one.
    - Each changed open document is checked as a main file. It owns what the
      check reports for its own file and for the imported files that are not
      open (errors only); an open import speaks for itself.
===============================================================================}

unit PaskalCPP.LSP.Server;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.JSON,
  PaskalCPP.AST,
  PaskalCPP.Compiler,
  PaskalCPP.LSP.Transport,
  PaskalCPP.LSP.Document,
  PaskalCPP.LSP.Symbols,
  PaskalCPP.LSP.Completion,
  PaskalCPP.LSP.Formatter;

const
  // JSON-RPC and LSP error codes
  { PC_LSP_ERR_PARSE }
  PC_LSP_ERR_PARSE = -32700;
  { PC_LSP_ERR_INVALID_REQUEST }
  PC_LSP_ERR_INVALID_REQUEST = -32600;
  { PC_LSP_ERR_METHOD_NOT_FOUND }
  PC_LSP_ERR_METHOD_NOT_FOUND = -32601;
  { PC_LSP_ERR_INVALID_PARAMS }
  PC_LSP_ERR_INVALID_PARAMS = -32602;
  { PC_LSP_ERR_INTERNAL }
  PC_LSP_ERR_INTERNAL = -32603;
  { PC_LSP_ERR_NOT_INITIALIZED }
  PC_LSP_ERR_NOT_INITIALIZED = -32002;

  { PC_LSP_SERVER_NAME }
  PC_LSP_SERVER_NAME = 'PaskalCPP LSP';

  { PC_LSP_MAX_ERRORS }
  // Reports kept per check (the parser recovers and goes on)
  PC_LSP_MAX_ERRORS = 100;

type
  { TPCLspServerState }
  TPCLspServerState = (
    ssUninitialized,   // waiting for initialize
    ssRunning,         // initialize answered
    ssShutdown         // shutdown answered, waiting for exit
  );

  { TPCLspRequestId }
  // A request's id as JSON-RPC 2.0 / LSP send it: an integer or a string.
  // Default() = no id (a response then carries id null)
  TPCLspRequestId = record
    IsSet: Boolean;
    IsText: Boolean;
    Number: Int64;
    Text: string;
    // AId := the "id" of AMessage; False when it is absent or neither an
    // integer nor a string (AId is then Default())
    class function FromMessage(const AMessage: TJSON; out AId: TPCLspRequestId): Boolean; static;
    // A new JSON value for a response's "id" (null when not set)
    function ToJson(): TJSONValue;
  end;

  { TPCLspServer }
  TPCLspServer = class(TBaseObject)
  private
    FTransport: TPCLspTransport;
    FState: TPCLspServerState;
    FEncoding: TPCPositionEncoding;
    FDocuments: TObjectDictionary<string, TPCLspDocument>;   // by uri
    FDiskDocuments: TObjectDictionary<string, TPCLspDocument>; // one check's disk texts, by file
    FCompiler: TPCCompiler;
    FDirty: TList<string>;                                     // uris changed since the last check
    FPublished: TDictionary<string, string>;                   // uri -> owner (uri) of its diagnostics
    // Disk watching: each open document's paths from its last check (the
    // directive paths SEM tested, the imported files), registered with the
    // client as file watchers when it can take them; FWatchText = the
    // registered set (sorted, one per line; '' = none), FWatchSerial its id
    FWatchPaths: TDictionary<string, TArray<string>>;          // uri -> paths
    FWatchCanRegister: Boolean;
    FWatchText: string;
    FWatchSerial: Integer;
    FExitCode: Integer;
    FExitRequested: Boolean;
    // The document FCompiler's AST was last analysed from, and its version:
    // a request that reads the AST analyses again when they differ
    FAnalysedUri: string;
    FAnalysedVersion: Integer;
    FFormatter: TPCLspFormatter;

    // documents
    function DoOpenDocument(const AFilename: string): TPCLspDocument;
    function DoDiskDocument(const AFilename: string): TPCLspDocument;
    function DoDocumentFor(const AFilename: string): TPCLspDocument;
    function DoProvide(const AFilename: string; out ABytes: TBytes): Boolean;

    // diagnostics
    procedure DoMarkDirty(const AUri: string);
    procedure DoFlushDiagnostics();
    procedure DoCheckRun(const ADocument: TPCLspDocument);
    procedure DoClearOwned(const AOwner: string; const ASeen: TDictionary<string, Boolean>);
    procedure SendDiagnostics(const AUri: string; const AVersion: Integer;
      const ADiagnostics: TJSONArray);

    // messages
    procedure DoHandleMessage(const ABody: string);
    procedure DoHandleRequest(const AId: TPCLspRequestId; const AMethod: string;
      const AParams: TJSON);
    procedure DoHandleNotification(const AMethod: string; const AParams: TJSON);
    procedure DoRequestExit();

    // handlers
    function DoInitialize(const AParams: TJSON): TJSONObject;
    function DoNegotiateEncoding(const AParams: TJSON): TPCPositionEncoding;
    procedure DoDidOpen(const AParams: TJSON);
    procedure DoDidChange(const AParams: TJSON);
    procedure DoDidClose(const AParams: TJSON);
    // workspace/didChangeWatchedFiles: every open buffer checked again
    procedure DoDidChangeWatched();
    // The watched set from FWatchPaths (open files left out: their buffers
    // speak); a changed set unregisters the old watchers and registers the new
    procedure DoUpdateWatchers();
    // A request of the server's own (the client's response is not read)
    procedure SendRequest(const AId: string; const AMethod: string; const AParams: TJSONObject);
    // The Position {line, character} at APath of AValue as a UTF-16 offset
    // of ADocument; False when either part is not an integer
    function DoOffsetAt(const ADocument: TPCLspDocument; const AValue: TJSON;
      const APath: string; out AOffset: Integer): Boolean;

    // colouring (E2.2a)
    function DoWordLists(): TJSONObject;
    function DoSemanticData(const ADocument: TPCLspDocument): TJSONArray;
    procedure DoSemanticTokens(const AId: TPCLspRequestId; const AParams: TJSON);

    // AST requests (E2.2)
    procedure DoAnalyse(const ADocument: TPCLspDocument);
    // Analyses ADocument when FCompiler's AST is not its current version
    procedure DoAnalyseIfStale(const ADocument: TPCLspDocument);
    // A buffer opened, changed or closed: the AST no longer stands for its
    // texts (it holds the open buffers of its imports too), whatever the
    // versions say, so the next request analyses again
    procedure DoBufferChanged();
    // A request on a position (hover, definition): its document and
    // position. False = already answered (bad params: error; no file: null)
    function DoPositionRequest(const AId: TPCLspRequestId; const AParams: TJSON;
      const AMethod: string; out ADocument: TPCLspDocument; out ALine: Integer;
      out ACharacter: Integer): Boolean;
    // The declaration at a client position of ADocument (analysed again when
    // the AST is not this document's version), with the use found there
    function DoTargetAt(const ADocument: TPCLspDocument; const ALine: Integer;
      const ACharacter: Integer; out AUse: TPCLspUse): TPCNode;
    // A declaration's Location: its name token (a headerless module: the top
    // of its file); the caller owns the result
    function DoLocation(const ATarget: TPCNode): TJSONObject;
    procedure DoDefinition(const AId: TPCLspRequestId; const AParams: TJSON);
    function DoHoverText(const ADocument: TPCLspDocument; const ALine: Integer;
      const ACharacter: Integer): string;
    procedure DoHover(const AId: TPCLspRequestId; const AParams: TJSON);

    // inlay hints (E2.4)
    procedure DoInlayHint(const AId: TPCLspRequestId; const AParams: TJSON);

    // document symbols (E2.5)
    // One DocumentSymbol (its children included) of an outline entry of
    // ADocument; the caller owns the result
    function DoSymbolJson(const ADocument: TPCLspDocument; const ANode: TPCNode): TJSONObject;
    procedure DoDocumentSymbol(const AId: TPCLspRequestId; const AParams: TJSON);

    // workspace symbols + call hierarchy (the editor's E9)
    // The open documents that are files, by uri: what the workspace requests
    // read (each one analysed in turn)
    function DoOpenFileDocuments(): TArray<TPCLspDocument>;
    // The SymbolInformation of ANode and of every outline child below it
    // whose name holds AQuery (lower case; '' = all), into AResult
    procedure DoAddWorkspaceSymbols(const ADocument: TPCLspDocument; const ANode: TPCNode;
      const AContainer: string; const AQuery: string; const AResult: TJSONArray);
    procedure DoWorkspaceSymbol(const AId: TPCLspRequestId; const AParams: TJSON);
    // The CallHierarchyItem of a routine or, for a caller outside every
    // routine, of its module (kind Module); the caller owns the result
    function DoCallItem(const ANode: TPCNode): TJSONObject;
    procedure DoPrepareCallHierarchy(const AId: TPCLspRequestId; const AParams: TJSON);
    // The routine key (TPCLspCalls.KeyAt) of the request's item; False =
    // already answered (bad params: error; a module item or no file: [])
    function DoCallItemKey(const AId: TPCLspRequestId; const AParams: TJSON;
      const AMethod: string; out AKey: string): Boolean;
    // callHierarchy/incomingCalls (AIncoming) or /outgoingCalls
    procedure DoCalls(const AId: TPCLspRequestId; const AParams: TJSON;
      const AIncoming: Boolean);

    // completion (E2.9)
    // The completion context at a client position of ADocument: the real
    // lexer on the buffer (its tokens and comment spans)
    function DoCompletionContext(const ADocument: TPCLspDocument; const ALine: Integer;
      const ACharacter: Integer): TPCLspCompletionContext;
    procedure DoCompletion(const AId: TPCLspRequestId; const AParams: TJSON);

    // formatting (E2.10)
    // FormattingOptions (spec keys + pcpp.* keys) over the defaults, clamped
    function DoFormatOptions(const AParams: TJSON): TPCLspFormatOptions;
    // One TextEdit of ADocument's buffer; the caller owns the result
    function DoTextEditJson(const ADocument: TPCLspDocument;
      const AEdit: TPCLspFormatEdit): TJSONObject;
    // textDocument/formatting, or /rangeFormatting when ARange
    procedure DoFormatting(const AId: TPCLspRequestId; const AParams: TJSON;
      const ARange: Boolean);

    // output
    procedure SendResult(const AId: TPCLspRequestId; const AResult: TJSONValue);
    procedure SendError(const AId: TPCLspRequestId; const ACode: Integer; const AMessage: string);
    procedure SendLog(const AMessage: string);
    // window/showMessage: AMessage shown to the user, AType a MessageType
    procedure SendShowMessage(const AType: Integer; const AMessage: string);
    procedure DoWindowMessage(const AMethod: string; const AType: Integer;
      const AMessage: string);
    procedure DoSend(const AMessage: TJSONObject);
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Serves ATransport until exit or the end of its input; the exit code.
    function Run(const ATransport: TPCLspTransport): Integer;

    property State: TPCLspServerState read FState;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.Common,
  PaskalCPP.TokenStream,
  PaskalCPP.Lexer,
  PaskalCPP.LSP.Calls,
  PaskalCPP.LSP.Diagnostics,
  PaskalCPP.LSP.Docs,
  PaskalCPP.LSP.Hints,
  PaskalCPP.LSP.Outline,
  PaskalCPP.LSP.Uri;

const
  // method names
  { PC_LSP_INITIALIZE }
  PC_LSP_INITIALIZE = 'initialize';
  { PC_LSP_SHUTDOWN }
  PC_LSP_SHUTDOWN = 'shutdown';
  { PC_LSP_EXIT }
  PC_LSP_EXIT = 'exit';
  { PC_LSP_DID_OPEN }
  PC_LSP_DID_OPEN = 'textDocument/didOpen';
  { PC_LSP_DID_CHANGE }
  PC_LSP_DID_CHANGE = 'textDocument/didChange';
  { PC_LSP_DID_CLOSE }
  PC_LSP_DID_CLOSE = 'textDocument/didClose';
  { PC_LSP_DID_CHANGE_WATCHED }
  // Files changed on disk (a build wrote its output): every open buffer is
  // checked again, since a directive's path or an import may now exist
  PC_LSP_DID_CHANGE_WATCHED = 'workspace/didChangeWatchedFiles';
  { PC_LSP_REGISTER_CAPABILITY }
  PC_LSP_REGISTER_CAPABILITY = 'client/registerCapability';
  { PC_LSP_UNREGISTER_CAPABILITY }
  PC_LSP_UNREGISTER_CAPABILITY = 'client/unregisterCapability';
  { PC_LSP_WATCH_ID }
  // The registration's id is this + the serial; a request's id this +
  // 'reg-' / 'unreg-' + the serial (the client's own ids are integers)
  PC_LSP_WATCH_ID = 'pcpp-watch-';
  { PC_LSP_WATCH_CAPABILITY }
  // The client's capability for watchers the server registers
  PC_LSP_WATCH_CAPABILITY = 'capabilities.workspace.didChangeWatchedFiles.dynamicRegistration';
  { PC_LSP_LOG_MESSAGE }
  PC_LSP_LOG_MESSAGE = 'window/logMessage';
  { PC_LSP_PUBLISH_DIAGNOSTICS }
  PC_LSP_PUBLISH_DIAGNOSTICS = 'textDocument/publishDiagnostics';
  { PC_LSP_SEMANTIC_FULL }
  PC_LSP_SEMANTIC_FULL = 'textDocument/semanticTokens/full';
  { PC_LSP_HOVER }
  PC_LSP_HOVER = 'textDocument/hover';
  { PC_LSP_DEFINITION }
  PC_LSP_DEFINITION = 'textDocument/definition';
  { PC_LSP_INLAY_HINT }
  PC_LSP_INLAY_HINT = 'textDocument/inlayHint';
  { PC_LSP_DOCUMENT_SYMBOL }
  PC_LSP_DOCUMENT_SYMBOL = 'textDocument/documentSymbol';
  { PC_LSP_COMPLETION }
  PC_LSP_COMPLETION = 'textDocument/completion';
  { PC_LSP_FORMATTING }
  PC_LSP_FORMATTING = 'textDocument/formatting';
  { PC_LSP_RANGE_FORMATTING }
  PC_LSP_RANGE_FORMATTING = 'textDocument/rangeFormatting';
  { PC_LSP_WORKSPACE_SYMBOL }
  PC_LSP_WORKSPACE_SYMBOL = 'workspace/symbol';
  { PC_LSP_PREPARE_CALLS }
  PC_LSP_PREPARE_CALLS = 'textDocument/prepareCallHierarchy';
  { PC_LSP_INCOMING_CALLS }
  PC_LSP_INCOMING_CALLS = 'callHierarchy/incomingCalls';
  { PC_LSP_OUTGOING_CALLS }
  PC_LSP_OUTGOING_CALLS = 'callHierarchy/outgoingCalls';
  { PC_LSP_SHOW_MESSAGE }
  PC_LSP_SHOW_MESSAGE = 'window/showMessage';

  { PC_LSP_INSERT_SNIPPET }
  // InsertTextFormat.Snippet
  PC_LSP_INSERT_SNIPPET = 2;
  { PC_LSP_TRIGGER_DOT }
  // Completion trigger characters: '.' and the '>' of '->'
  PC_LSP_TRIGGER_DOT = '.';
  { PC_LSP_TRIGGER_ARROW }
  PC_LSP_TRIGGER_ARROW = '>';

  { PC_LSP_HINT_PARAMETER }
  // InlayHintKind.Parameter
  PC_LSP_HINT_PARAMETER = 2;

  // Hover markdown: the declaration in a PaskalCPP code block
  { PC_LSP_HOVER_FENCE }
  PC_LSP_HOVER_FENCE = '```';
  { PC_LSP_HOVER_LANGUAGE }
  PC_LSP_HOVER_LANGUAGE = 'pcpp';

  // Semantic token legend: the index of each type in tokenTypes
  { PC_LSP_TOKEN_KEYWORD }
  PC_LSP_TOKEN_KEYWORD = 0;
  { PC_LSP_TOKEN_TYPE }
  PC_LSP_TOKEN_TYPE = 1;
  { PC_LSP_WORDS_KEY }
  // capabilities.experimental.<this>: PaskalCPP's keywords and builtin types,
  // for the editor's instant (Monarch) colouring
  PC_LSP_WORDS_KEY = 'pcppWords';

  { PC_LSP_JSONRPC_VERSION }
  PC_LSP_JSONRPC_VERSION = '2.0';
  { PC_LSP_MESSAGE_ERROR }
  // MessageType.Error
  PC_LSP_MESSAGE_ERROR = 1;
  { PC_LSP_MESSAGE_WARNING }
  // MessageType.Warning
  PC_LSP_MESSAGE_WARNING = 2;
  { PC_LSP_SYNC_INCREMENTAL }
  // TextDocumentSyncKind.Incremental (a change without a range is the whole text)
  PC_LSP_SYNC_INCREMENTAL = 2;

  // PositionEncodingKind values
  { PC_LSP_ENCODING_UTF8 }
  PC_LSP_ENCODING_UTF8 = 'utf-8';
  { PC_LSP_ENCODING_UTF16 }
  PC_LSP_ENCODING_UTF16 = 'utf-16';
  { PC_LSP_ENCODING_UTF32 }
  PC_LSP_ENCODING_UTF32 = 'utf-32';

{ SamePathSafe }
function SamePathSafe(const APath1: string; const APath2: string): Boolean;
begin
  // A document that is no file (untitled:) has no path and matches nothing
  Result := (APath1 <> '') and (APath2 <> '') and TUtils.SamePath(APath1, APath2);
end;

{ OptionBoolean }
// AFlag := the boolean FormattingOptions entry AKey; False (AFlag kept) when
// absent or not a boolean. The key is literal: the editor's keys hold a '.'
// (pcpp.spaceAfterComma) that a path would split (FS)
function OptionBoolean(const AOptions: TJSON; const AKey: string;
  var AFlag: Boolean): Boolean;
var
  LValue: Boolean;
begin
  Result := AOptions.TryGetBoolean(AKey, LValue, True);
  if Result then
    AFlag := LValue;
end;

{ OptionInteger }
// ANumber := the integer FormattingOptions entry AKey (literal, as
// OptionBoolean); False (ANumber kept) when absent or no Integer (1.5, 1e40)
function OptionInteger(const AOptions: TJSON; const AKey: string;
  var ANumber: Integer): Boolean;
var
  LValue: Integer;
begin
  Result := AOptions.TryGetInt32(AKey, LValue, True);
  if Result then
    ANumber := LValue;
end;

{ TPCLspRequestId }

class function TPCLspRequestId.FromMessage(const AMessage: TJSON;
  out AId: TPCLspRequestId): Boolean;
begin
  AId := Default(TPCLspRequestId);
  // JSON-RPC: an integer or a string; LSP: integer | string
  if AMessage.TryGetInt64('id', AId.Number, True) then
    AId.IsSet := True
  else if AMessage.TryGetString('id', AId.Text, True) then
  begin
    AId.IsSet := True;
    AId.IsText := True;
  end;
  Result := AId.IsSet;
end;

function TPCLspRequestId.ToJson(): TJSONValue;
begin
  if not IsSet then
    Result := TJSONNull.Create()
  else if IsText then
    Result := TJSONString.Create(Text)
  else
    Result := TJSONNumber.Create(Number);
end;

{ TPCLspServer }

constructor TPCLspServer.Create();
begin
  inherited;

  FDocuments := TObjectDictionary<string, TPCLspDocument>.Create([doOwnsValues]);
  FDiskDocuments := TObjectDictionary<string, TPCLspDocument>.Create([doOwnsValues]);
  FCompiler := TPCCompiler.Create();
  FCompiler.SetMaxErrors(PC_LSP_MAX_ERRORS);
  // Every file the frontend reads comes from an open buffer when there is one
  FCompiler.SetSourceProvider(DoProvide);
  FDirty := TList<string>.Create();
  FPublished := TDictionary<string, string>.Create();
  FWatchPaths := TDictionary<string, TArray<string>>.Create();
  FWatchCanRegister := False;
  FWatchText := '';
  FWatchSerial := 0;
  FState := ssUninitialized;
  FEncoding := peUtf16;
  FExitCode := 1;
  FAnalysedUri := '';
  FAnalysedVersion := 0;
  FFormatter := TPCLspFormatter.Create();
end;

destructor TPCLspServer.Destroy();
begin
  FFormatter.Free();
  // The provider refers to FDocuments: unhook it before either goes
  FCompiler.SetSourceProvider(nil);
  FCompiler.Free();
  FWatchPaths.Free();
  FPublished.Free();
  FDirty.Free();
  FDiskDocuments.Free();
  FDocuments.Free();

  inherited;
end;

function TPCLspServer.Run(const ATransport: TPCLspTransport): Integer;
var
  LBody: string;
  LRead: TPCLspReadResult;
begin
  FTransport := ATransport;
  FState := ssUninitialized;
  FEncoding := peUtf16;
  FDocuments.Clear();
  FDirty.Clear();
  FPublished.Clear();
  FWatchPaths.Clear();
  FWatchCanRegister := False;
  FWatchText := '';
  FWatchSerial := 0;
  FExitRequested := False;
  FExitCode := 1;

  while not FExitRequested do
  begin
    LRead := FTransport.ReadMessage(LBody);
    if LRead = rrMessage then
      DoHandleMessage(LBody)
    else if LRead = rrMalformed then
      SendLog(RSLspMalformed)
    else
      // The input ended without "exit": the client is gone
      DoRequestExit();

    if (not FExitRequested) and (FState = ssRunning) and (FDirty.Count > 0) and
      (not FTransport.HasPendingInput()) then
      DoFlushDiagnostics();
  end;
  Result := FExitCode;
end;

procedure TPCLspServer.DoRequestExit();
begin
  FExitRequested := True;
  if FState = ssShutdown then
    FExitCode := 0
  else
    FExitCode := 1;
end;

function TPCLspServer.DoOpenDocument(const AFilename: string): TPCLspDocument;
var
  LDocument: TPCLspDocument;
begin
  // The open buffer of the file AFilename names; nil when it is not open
  for LDocument in FDocuments.Values do
    if SamePathSafe(LDocument.Filename, AFilename) then
      Exit(LDocument);
  Result := nil;
end;

function TPCLspServer.DoDiskDocument(const AFilename: string): TPCLspDocument;
var
  LKey: string;
  LText: string;
begin
  // A file that is not open, as the disk has it (read once per check); an
  // unreadable one is an empty text, its locations clamped to its top
  LKey := AFilename.Replace('/', '\').ToLower();
  if FDiskDocuments.TryGetValue(LKey, Result) then
    Exit;
  try
    LText := TFile.ReadAllText(TUtils.ResolvePath(AFilename), TEncoding.UTF8);
  except
    on E: Exception do
      LText := '';
  end;
  Result := TPCLspDocument.Create();
  Result.Init(TPCLspUri.FromFilename(TUtils.StripLongPathPrefix(AFilename)),
    AFilename, '', -1, LText);
  FDiskDocuments.Add(LKey, Result);
end;

function TPCLspServer.DoDocumentFor(const AFilename: string): TPCLspDocument;
begin
  Result := DoOpenDocument(AFilename);
  if Result = nil then
    Result := DoDiskDocument(AFilename);
end;

function TPCLspServer.DoProvide(const AFilename: string; out ABytes: TBytes): Boolean;
var
  LDocument: TPCLspDocument;
begin
  // TPCSourceProvider: an open buffer wins over its file on disk
  ABytes := nil;
  LDocument := DoOpenDocument(AFilename);
  Result := LDocument <> nil;
  if Result then
    ABytes := LDocument.GetBytes();
end;

procedure TPCLspServer.DoHandleMessage(const ABody: string);
var
  LMessage: TJSON;
  LParams: TJSON;
  LVersion: string;
  LMethod: string;
  LHasId: Boolean;
  LId: TPCLspRequestId;
begin
  if not TJSON.TryFromString(ABody, LMessage) then
  begin
    SendError(Default(TPCLspRequestId), PC_LSP_ERR_PARSE, RSLspParseError);
    Exit;
  end;

  try
    // A batch (array) is not part of LSP
    if not LMessage.IsObject() then
    begin
      SendError(Default(TPCLspRequestId), PC_LSP_ERR_INVALID_REQUEST, RSLspInvalidRequest);
      Exit;
    end;
    // An id that is neither an integer nor a string is answered with id null
    LHasId := LMessage.Has('id', True);
    TPCLspRequestId.FromMessage(LMessage, LId);

    if not (LMessage.TryGetString('jsonrpc', LVersion, True) and
      (LVersion = PC_LSP_JSONRPC_VERSION)) then
    begin
      SendError(LId, PC_LSP_ERR_INVALID_REQUEST, RSLspInvalidRequest);
      Exit;
    end;

    if not LMessage.TryGetString('method', LMethod, True) then
    begin
      // A response to a request of ours: the server sends none
      if LHasId and (LMessage.Has('result', True) or LMessage.Has('error', True)) then
        Exit;
      SendError(LId, PC_LSP_ERR_INVALID_REQUEST, RSLspInvalidRequest);
      Exit;
    end;

    // Absent params read as a null view: every read of it answers False
    LParams := LMessage.Get('params', True);
    if not LHasId then
      DoHandleNotification(LMethod, LParams)
    else if LId.IsSet then
      DoHandleRequest(LId, LMethod, LParams)
    else
      SendError(LId, PC_LSP_ERR_INVALID_REQUEST, RSLspInvalidRequest);
  finally
    LMessage.Free();
  end;
end;

procedure TPCLspServer.DoHandleRequest(const AId: TPCLspRequestId;
  const AMethod: string; const AParams: TJSON);
begin
  // Lifecycle rules first
  if FState = ssShutdown then
  begin
    SendError(AId, PC_LSP_ERR_INVALID_REQUEST, RSLspShutDown);
    Exit;
  end;
  if (AMethod = PC_LSP_INITIALIZE) and (FState <> ssUninitialized) then
  begin
    SendError(AId, PC_LSP_ERR_INVALID_REQUEST, RSLspAlreadyInitialized);
    Exit;
  end;
  if (AMethod <> PC_LSP_INITIALIZE) and (FState = ssUninitialized) then
  begin
    SendError(AId, PC_LSP_ERR_NOT_INITIALIZED, RSLspNotInitialized);
    Exit;
  end;

  try
    if AMethod = PC_LSP_INITIALIZE then
    begin
      SendResult(AId, DoInitialize(AParams));
      FState := ssRunning;
    end
    else if AMethod = PC_LSP_SHUTDOWN then
    begin
      FState := ssShutdown;
      SendResult(AId, TJSONNull.Create());
    end
    else if AMethod = PC_LSP_SEMANTIC_FULL then
      DoSemanticTokens(AId, AParams)
    else if AMethod = PC_LSP_HOVER then
      DoHover(AId, AParams)
    else if AMethod = PC_LSP_DEFINITION then
      DoDefinition(AId, AParams)
    else if AMethod = PC_LSP_INLAY_HINT then
      DoInlayHint(AId, AParams)
    else if AMethod = PC_LSP_DOCUMENT_SYMBOL then
      DoDocumentSymbol(AId, AParams)
    else if AMethod = PC_LSP_COMPLETION then
      DoCompletion(AId, AParams)
    else if AMethod = PC_LSP_FORMATTING then
      DoFormatting(AId, AParams, False)
    else if AMethod = PC_LSP_RANGE_FORMATTING then
      DoFormatting(AId, AParams, True)
    else if AMethod = PC_LSP_WORKSPACE_SYMBOL then
      DoWorkspaceSymbol(AId, AParams)
    else if AMethod = PC_LSP_PREPARE_CALLS then
      DoPrepareCallHierarchy(AId, AParams)
    else if AMethod = PC_LSP_INCOMING_CALLS then
      DoCalls(AId, AParams, True)
    else if AMethod = PC_LSP_OUTGOING_CALLS then
      DoCalls(AId, AParams, False)
    else
      // Unknown requests, $/ requests included, must fail
      SendError(AId, PC_LSP_ERR_METHOD_NOT_FOUND, Format(RSLspMethodNotFound, [AMethod]));
  except
    on E: Exception do
      SendError(AId, PC_LSP_ERR_INTERNAL, Format(RSLspInternalError, [AMethod, E.Message]));
  end;
end;

procedure TPCLspServer.DoHandleNotification(const AMethod: string;
  const AParams: TJSON);
begin
  if AMethod = PC_LSP_EXIT then
  begin
    DoRequestExit();
    Exit;
  end;

  // Dropped before initialize and after shutdown
  if FState <> ssRunning then
    Exit;

  try
    if AMethod = PC_LSP_DID_OPEN then
      DoDidOpen(AParams)
    else if AMethod = PC_LSP_DID_CHANGE then
      DoDidChange(AParams)
    else if AMethod = PC_LSP_DID_CLOSE then
      DoDidClose(AParams)
    else if AMethod = PC_LSP_DID_CHANGE_WATCHED then
      DoDidChangeWatched();
    // "initialized", $/ notifications and unknown ones need nothing
  except
    // A notification has no response: the client gets a log message
    on E: Exception do
      SendLog(Format(RSLspInternalError, [AMethod, E.Message]));
  end;
end;

function TPCLspServer.DoInitialize(const AParams: TJSON): TJSONObject;
var
  LCapabilities: TJSONObject;
  LSync: TJSONObject;
  LSemantic: TJSONObject;
  LLegend: TJSONObject;
  LTypes: TJSONArray;
  LExperimental: TJSONObject;
  LInfo: TJSONObject;
  LCompletion: TJSONObject;
  LTriggers: TJSONArray;
  LEncoding: string;
begin
  FEncoding := DoNegotiateEncoding(AParams);
  // Watchers are registered only with a client that says it takes them
  // (an unreadable value reads as no)
  if not AParams.TryGetBoolean(PC_LSP_WATCH_CAPABILITY, FWatchCanRegister) then
    FWatchCanRegister := False;
  case FEncoding of
    peUtf8:
      LEncoding := PC_LSP_ENCODING_UTF8;
    peUtf32:
      LEncoding := PC_LSP_ENCODING_UTF32;
  else
    LEncoding := PC_LSP_ENCODING_UTF16;
  end;

  Result := TJSONObject.Create();
  LCapabilities := TJSONObject.Create();
  Result.AddPair('capabilities', LCapabilities);
  LCapabilities.AddPair('positionEncoding', LEncoding);

  LSync := TJSONObject.Create();
  LCapabilities.AddPair('textDocumentSync', LSync);
  LSync.AddPair('openClose', TJSONBool.Create(True));
  LSync.AddPair('change', TJSONNumber.Create(PC_LSP_SYNC_INCREMENTAL));

  // Keywords and builtin types, from the lexer's own table
  LSemantic := TJSONObject.Create();
  LCapabilities.AddPair('semanticTokensProvider', LSemantic);
  LLegend := TJSONObject.Create();
  LSemantic.AddPair('legend', LLegend);
  LTypes := TJSONArray.Create();
  LLegend.AddPair('tokenTypes', LTypes);
  LTypes.Add('keyword');
  LTypes.Add('type');
  LLegend.AddPair('tokenModifiers', TJSONArray.Create());
  LSemantic.AddPair('full', TJSONBool.Create(True));

  LCapabilities.AddPair('hoverProvider', TJSONBool.Create(True));
  LCapabilities.AddPair('definitionProvider', TJSONBool.Create(True));
  LCapabilities.AddPair('inlayHintProvider', TJSONBool.Create(True));
  LCapabilities.AddPair('documentSymbolProvider', TJSONBool.Create(True));
  LCapabilities.AddPair('documentFormattingProvider', TJSONBool.Create(True));
  LCapabilities.AddPair('documentRangeFormattingProvider', TJSONBool.Create(True));
  LCapabilities.AddPair('workspaceSymbolProvider', TJSONBool.Create(True));
  LCapabilities.AddPair('callHierarchyProvider', TJSONBool.Create(True));

  LCompletion := TJSONObject.Create();
  LCapabilities.AddPair('completionProvider', LCompletion);
  LTriggers := TJSONArray.Create();
  LCompletion.AddPair('triggerCharacters', LTriggers);
  LTriggers.Add(PC_LSP_TRIGGER_DOT);
  LTriggers.Add(PC_LSP_TRIGGER_ARROW);

  LExperimental := TJSONObject.Create();
  LCapabilities.AddPair('experimental', LExperimental);
  LExperimental.AddPair(PC_LSP_WORDS_KEY, DoWordLists());

  LInfo := TJSONObject.Create();
  Result.AddPair('serverInfo', LInfo);
  LInfo.AddPair('name', PC_LSP_SERVER_NAME);
end;

function TPCLspServer.DoNegotiateEncoding(const AParams: TJSON): TPCPositionEncoding;
var
  LEncodings: TJSON;
  LItem: TJSON;
  LEncodingName: string;
begin
  // The client lists encodings by preference: take the first one we
  // support; without a list UTF-16, which every client must support
  Result := peUtf16;
  if not AParams.TryGetArray('capabilities.general.positionEncodings', LEncodings) then
    Exit;
  for LItem in LEncodings.Items() do
  begin
    // An entry that is no string names no encoding
    if not LItem.TryGetString('', LEncodingName) then
      Continue;
    if LEncodingName = PC_LSP_ENCODING_UTF16 then
      Exit(peUtf16);
    if LEncodingName = PC_LSP_ENCODING_UTF8 then
      Exit(peUtf8);
    if LEncodingName = PC_LSP_ENCODING_UTF32 then
      Exit(peUtf32);
  end;
end;

procedure TPCLspServer.DoDidOpen(const AParams: TJSON);
var
  LUri: string;
  LText: string;
  LLanguageId: string;
  LVersion: Integer;
  LPath: string;
  LDocument: TPCLspDocument;
begin
  if not (AParams.TryGetString('textDocument.uri', LUri) and
    AParams.TryGetString('textDocument.text', LText)) then
  begin
    SendLog(Format(RSLspBadParams, [PC_LSP_DID_OPEN]));
    Exit;
  end;
  // Optional for this server: an unreadable one is '' / 0
  AParams.TryGetString('textDocument.languageId', LLanguageId);
  AParams.TryGetInt32('textDocument.version', LVersion);

  // The resolved path the frontend reads it as; a URI that names no file
  // (or a path no file routine takes) has none and is never checked
  LPath := '';
  if TPCLspUri.ToFilename(LUri, LPath) then
  begin
    try
      LPath := TUtils.ResolvePath(LPath);
    except
      on E: Exception do
        LPath := '';
    end;
  end;

  LDocument := TPCLspDocument.Create();
  LDocument.Init(LUri, LPath, LLanguageId, LVersion, LText);
  // A second didOpen of the same uri replaces (and frees) the old buffer
  FDocuments.AddOrSetValue(LUri, LDocument);
  DoBufferChanged();
  DoMarkDirty(LUri);
end;

procedure TPCLspServer.DoDidChangeWatched();
var
  LUri: string;
begin
  // Which files changed is not read: any change on disk (a build's output, a
  // library, an imported unit edited outside the editor) may move what a
  // buffer's directives and imports find, so the analysis goes and every open
  // buffer is checked again; each check replaces what it published before
  DoBufferChanged();
  for LUri in FDocuments.Keys do
    DoMarkDirty(LUri);
end;

procedure TPCLspServer.DoUpdateWatchers();
var
  LSet: TStringList;
  LPair: TPair<string, TArray<string>>;
  LPath: string;
  LText: string;
  LParams: TJSONObject;
  LList: TJSONArray;
  LItem: TJSONObject;
  LOptions: TJSONObject;
  LWatchers: TJSONArray;
  LWatcher: TJSONObject;
  LOldSerial: Integer;
  LHadOld: Boolean;
begin
  if not FWatchCanRegister then
    Exit;

  // The set: every document's paths once (case-insensitive, sorted, so the
  // same set always reads as the same text), its open files left out
  LSet := TStringList.Create();
  try
    LSet.CaseSensitive := False;
    LSet.Sorted := True;
    LSet.Duplicates := dupIgnore;
    for LPair in FWatchPaths do
    begin
      for LPath in LPair.Value do
      begin
        if DoOpenDocument(LPath) = nil then
          LSet.Add(LPath);
      end;
    end;
    LText := LSet.Text;
    if LText = FWatchText then
      Exit;

    // The new set is registered BEFORE the old one goes: a path in both keeps
    // its running watcher (dropped and started again, a change in between
    // would be missed: the new watcher's first look is its baseline)
    LOldSerial := FWatchSerial;
    LHadOld := FWatchText <> '';
    FWatchText := LText;

    // One watcher per path, spelled with '/' as a glob is; the path itself
    // (a file, or a folder and what is under it) is what the client watches
    if LSet.Count > 0 then
    begin
      Inc(FWatchSerial);
      LParams := TJSONObject.Create();
      LList := TJSONArray.Create();
      LParams.AddPair('registrations', LList);
      LItem := TJSONObject.Create();
      LList.AddElement(LItem);
      LItem.AddPair('id', PC_LSP_WATCH_ID + IntToStr(FWatchSerial));
      LItem.AddPair('method', PC_LSP_DID_CHANGE_WATCHED);
      LOptions := TJSONObject.Create();
      LItem.AddPair('registerOptions', LOptions);
      LWatchers := TJSONArray.Create();
      LOptions.AddPair('watchers', LWatchers);
      for LPath in LSet do
      begin
        LWatcher := TJSONObject.Create();
        LWatchers.AddElement(LWatcher);
        LWatcher.AddPair('globPattern', LPath.Replace('\', '/'));
      end;
      SendRequest(PC_LSP_WATCH_ID + 'reg-' + IntToStr(FWatchSerial),
        PC_LSP_REGISTER_CAPABILITY, LParams);
    end;

    if LHadOld then
    begin
      LParams := TJSONObject.Create();
      LList := TJSONArray.Create();
      // 'unregisterations' is the protocol's own spelling (LSP 3.17)
      LParams.AddPair('unregisterations', LList);
      LItem := TJSONObject.Create();
      LList.AddElement(LItem);
      LItem.AddPair('id', PC_LSP_WATCH_ID + IntToStr(LOldSerial));
      LItem.AddPair('method', PC_LSP_DID_CHANGE_WATCHED);
      SendRequest(PC_LSP_WATCH_ID + 'unreg-' + IntToStr(LOldSerial),
        PC_LSP_UNREGISTER_CAPABILITY, LParams);
    end;
  finally
    LSet.Free();
  end;
end;

function TPCLspServer.DoOffsetAt(const ADocument: TPCLspDocument;
  const AValue: TJSON; const APath: string; out AOffset: Integer): Boolean;
var
  LLine: Integer;
  LCharacter: Integer;
begin
  AOffset := 0;
  Result := AValue.TryGetInt32(APath + '.line', LLine) and
    AValue.TryGetInt32(APath + '.character', LCharacter);
  if Result then
    AOffset := ADocument.OffsetAt(LLine, LCharacter, FEncoding);
end;

procedure TPCLspServer.DoDidChange(const AParams: TJSON);
var
  LUri: string;
  LDocument: TPCLspDocument;
  LChanges: TJSON;
  LChange: TJSON;
  LRange: TJSON;
  LText: string;
  LStart: Integer;
  LEnd: Integer;
  LVersion: Integer;
  LBad: Boolean;
begin
  if not (AParams.TryGetString('textDocument.uri', LUri) and
    FDocuments.TryGetValue(LUri, LDocument)) then
  begin
    SendLog(Format(RSLspBadParams, [PC_LSP_DID_CHANGE]));
    Exit;
  end;

  // Changes apply in order, each to the text the previous one left. One that
  // cannot be read (no text, a range whose ends are no positions) stops the
  // list: the changes after it are relative to text this buffer no longer
  // holds, so neither they nor the new version are taken
  LBad := False;
  if AParams.TryGetArray('contentChanges', LChanges) then
  begin
    for LChange in LChanges.Items() do
    begin
      if not LChange.TryGetString('text', LText) then
      begin
        LBad := True;
        Break;
      end;
      if not LChange.TryGetObject('range', LRange) then
        LDocument.ReplaceAll(LText)
      else
      begin
        // Both ends from the text before this change
        if not (DoOffsetAt(LDocument, LRange, 'start', LStart) and
          DoOffsetAt(LDocument, LRange, 'end', LEnd)) then
        begin
          LBad := True;
          Break;
        end;
        LDocument.Replace(LStart, LEnd, LText);
      end;
    end;
  end;

  // The text changed, whatever the version says (a change list without a
  // readable version, or one stopped by a bad change, keeps the old one)
  DoBufferChanged();

  if LBad then
  begin
    SendLog(Format(RSLspBadParams, [PC_LSP_DID_CHANGE]));
    DoMarkDirty(LUri);
    Exit;
  end;

  if AParams.TryGetInt32('textDocument.version', LVersion) then
    LDocument.Version := LVersion;
  DoMarkDirty(LUri);
end;

procedure TPCLspServer.DoDidClose(const AParams: TJSON);
var
  LUri: string;
  LNone: TDictionary<string, Boolean>;
begin
  if not AParams.TryGetString('textDocument.uri', LUri) then
    Exit;
  FDocuments.Remove(LUri);
  FDirty.Remove(LUri);
  // Its paths are watched no more (and the file itself may now be: an open
  // file is left out of the watched set)
  FWatchPaths.Remove(LUri);
  DoUpdateWatchers();
  // An import that was this buffer is read from its file again
  DoBufferChanged();

  // What the closed document's checks published goes, its own uri too
  LNone := TDictionary<string, Boolean>.Create();
  try
    DoClearOwned(LUri, LNone);
  finally
    LNone.Free();
  end;
  if FPublished.ContainsKey(LUri) then
  begin
    SendDiagnostics(LUri, -1, TJSONArray.Create());
    FPublished.Remove(LUri);
  end;
end;

function TPCLspServer.DoWordLists(): TJSONObject;
var
  LRow: TPCTokenRow;
  LKeywords: TJSONArray;
  LTypes: TJSONArray;
begin
  // The lexer's own registration table: PaskalCPP's reserved words and
  // builtin type names (C++'s words are not PaskalCPP's)
  Result := TJSONObject.Create();
  LKeywords := TJSONArray.Create();
  Result.AddPair('keywords', LKeywords);
  LTypes := TJSONArray.Create();
  Result.AddPair('types', LTypes);
  for LRow in PC_PASKAL_TOKENS do
  begin
    if LRow.Category = tcKeyword then
      LKeywords.Add(LRow.Text)
    else if LRow.Category = tcPrimitive then
      LTypes.Add(LRow.Text);
  end;
end;

function TPCLspServer.DoSemanticData(const ADocument: TPCLspDocument): TJSONArray;
var
  LErrors: TErrors;
  LLexer: TPCLexer;
  LStream: TPCTokenStream;
  LToken: TPCToken;
  LI: Integer;
  LTokenType: Integer;
  LLine: Integer;
  LStart: Integer;
  LEnd: Integer;
  LPrevLine: Integer;
  LPrevStart: Integer;
begin
  // The real lexer on the buffer: a keyword / builtin type token is coloured
  // where the lexer made one (a cppstart block's text is one verbatim token;
  // C++'s own keywords are tcCppKeyword). The lexer's reports are the
  // diagnostics' business: its own TErrors, dropped
  Result := TJSONArray.Create();
  LErrors := TErrors.Create();
  LLexer := TPCLexer.Create();
  LStream := TPCTokenStream.Create();
  try
    LLexer.SetErrors(LErrors);
    LStream.SetErrors(LErrors);
    LLexer.TokenizeBytes(ADocument.GetBytes(), ADocument.Filename, LStream);

    // LSP relative encoding: per token deltaLine, deltaStart (from the
    // previous token's start when on the same line), length, type, modifiers
    LPrevLine := 0;
    LPrevStart := 0;
    for LI := 0 to LStream.Count() - 1 do
    begin
      LToken := LStream.TokenAt(LI);
      if LToken.Category = tcKeyword then
        LTokenType := PC_LSP_TOKEN_KEYWORD
      else if LToken.Category = tcPrimitive then
        LTokenType := PC_LSP_TOKEN_TYPE
      else
        Continue;
      // A token that spans lines (a line splice inside it) has no one-line range
      if (LToken.Range.StartLine < 1) or (LToken.Range.EndLine <> LToken.Range.StartLine) then
        Continue;

      LLine := Integer(LToken.Range.StartLine) - 1;
      LStart := ADocument.ClientCharacter(LLine,
        ADocument.ByteColumnToColumn(LToken.Range.StartLine, LToken.Range.StartColumn), FEncoding);
      // The range's end names its last byte: the token ends one byte later
      LEnd := ADocument.ClientCharacter(LLine,
        ADocument.ByteColumnToColumn(LToken.Range.StartLine, LToken.Range.EndColumn + 1), FEncoding);
      if LEnd <= LStart then
        Continue;

      Result.Add(LLine - LPrevLine);
      if LLine = LPrevLine then
        Result.Add(LStart - LPrevStart)
      else
        Result.Add(LStart);
      Result.Add(LEnd - LStart);
      Result.Add(LTokenType);
      Result.Add(0);
      LPrevLine := LLine;
      LPrevStart := LStart;
    end;
  finally
    LStream.Free();
    LLexer.Free();
    LErrors.Free();
  end;
end;

procedure TPCLspServer.DoSemanticTokens(const AId: TPCLspRequestId; const AParams: TJSON);
var
  LUri: string;
  LDocument: TPCLspDocument;
  LResult: TJSONObject;
begin
  if not AParams.TryGetString('textDocument.uri', LUri) then
  begin
    SendError(AId, PC_LSP_ERR_INVALID_PARAMS, Format(RSLspBadParams, [PC_LSP_SEMANTIC_FULL]));
    Exit;
  end;
  // A document the server does not hold has nothing to colour
  if not FDocuments.TryGetValue(LUri, LDocument) then
  begin
    SendResult(AId, TJSONNull.Create());
    Exit;
  end;

  LResult := TJSONObject.Create();
  LResult.AddPair('data', DoSemanticData(LDocument));
  SendResult(AId, LResult);
end;

procedure TPCLspServer.DoAnalyse(const ADocument: TPCLspDocument);
begin
  // Cleared first: an Analyze that raises leaves no AST worth reading
  FAnalysedUri := '';
  FCompiler.Analyze(ADocument.Filename);
  FAnalysedUri := ADocument.Uri;
  FAnalysedVersion := ADocument.Version;
end;

procedure TPCLspServer.DoAnalyseIfStale(const ADocument: TPCLspDocument);
begin
  // The AST must be this document's, at this version
  if (FAnalysedUri <> ADocument.Uri) or (FAnalysedVersion <> ADocument.Version) then
    DoAnalyse(ADocument);
end;

procedure TPCLspServer.DoBufferChanged();
begin
  // DoAnalyseIfStale then finds no AST for any uri
  FAnalysedUri := '';
end;

function TPCLspServer.DoPositionRequest(const AId: TPCLspRequestId; const AParams: TJSON;
  const AMethod: string; out ADocument: TPCLspDocument; out ALine: Integer;
  out ACharacter: Integer): Boolean;
var
  LUri: string;
begin
  Result := False;
  ADocument := nil;
  if (not AParams.TryGetString('textDocument.uri', LUri)) or
     (not AParams.TryGetInt32('position.line', ALine)) or
     (not AParams.TryGetInt32('position.character', ACharacter)) then
  begin
    SendError(AId, PC_LSP_ERR_INVALID_PARAMS, Format(RSLspBadParams, [AMethod]));
    Exit;
  end;
  // A document the server does not hold, or one that is no file, has no AST
  if (not FDocuments.TryGetValue(LUri, ADocument)) or (ADocument.Filename = '') then
  begin
    SendResult(AId, TJSONNull.Create());
    Exit;
  end;
  Result := True;
end;

function TPCLspServer.DoTargetAt(const ADocument: TPCLspDocument; const ALine: Integer;
  const ACharacter: Integer; out AUse: TPCLspUse): TPCNode;
begin
  DoAnalyseIfStale(ADocument);
  AUse := TPCLspSymbols.UseAt(FCompiler.GetMainModule(), UInt64(ALine) + 1,
    ADocument.ByteColumnAt(ALine, ACharacter, FEncoding));
  Result := TPCLspSymbols.TargetOf(AUse);
end;

function TPCLspServer.DoLocation(const ATarget: TPCNode): TJSONObject;
var
  LRange: TSourceRange;
  LFile: string;
  LDocument: TPCLspDocument;
begin
  // The name token; a module without a header names nothing: the top of
  // its file (an empty range); a node with no name range: its own range
  LRange := TPCLspSymbols.NameRangeOf(ATarget);
  if (LRange.StartLine < 1) and (ATarget is TPCModule) then
  begin
    LRange := Default(TSourceRange);
    LFile := TPCModule(ATarget).SourceFile;
  end
  else
  begin
    if LRange.StartLine < 1 then
      LRange := ATarget.Range;
    LFile := LRange.Filename;
  end;

  // The open buffer when the file is open, else its disk text: the byte
  // columns convert over the text they were counted on
  LDocument := DoDocumentFor(LFile);
  Result := TJSONObject.Create();
  Result.AddPair('uri', LDocument.Uri);
  Result.AddPair('range', TPCLspRange.ToJson(LDocument, LRange, FEncoding));
end;

procedure TPCLspServer.DoDefinition(const AId: TPCLspRequestId; const AParams: TJSON);
var
  LDocument: TPCLspDocument;
  LLine: Integer;
  LCharacter: Integer;
  LUse: TPCLspUse;
  LTarget: TPCNode;
  LRoutines: TArray<TPCRoutine>;
  LRoutine: TPCRoutine;
  LLocations: TJSONArray;
begin
  if not DoPositionRequest(AId, AParams, PC_LSP_DEFINITION, LDocument, LLine, LCharacter) then
    Exit;
  LTarget := DoTargetAt(LDocument, LLine, LCharacter, LUse);
  if LTarget = nil then
  begin
    SendResult(AId, TJSONNull.Create());
    Exit;
  end;

  // One Location per declaration: an overload set gives every member
  // (FreeStrike's DoDefinition); disk texts are read for this request only
  FDiskDocuments.Clear();
  LLocations := TJSONArray.Create();
  try
    try
      LRoutines := TPCLspSymbols.SetOf(LUse, LTarget);
      if Length(LRoutines) > 0 then
      begin
        for LRoutine in LRoutines do
          LLocations.AddElement(DoLocation(LRoutine));
      end
      else
        LLocations.AddElement(DoLocation(LTarget));
    except
      // DoHandleRequest answers the request with the error
      LLocations.Free();
      raise;
    end;
  finally
    FDiskDocuments.Clear();
  end;
  SendResult(AId, LLocations);
end;

function TPCLspServer.DoHoverText(const ADocument: TPCLspDocument; const ALine: Integer;
  const ACharacter: Integer): string;
var
  LUse: TPCLspUse;
  LTarget: TPCNode;
  LLines: TList<string>;
  LRoutines: TArray<TPCRoutine>;
  LRoutine: TPCRoutine;
  LLine: string;
  LFile: string;
  LSlash: Integer;
  LDoc: string;
begin
  Result := '';
  LTarget := DoTargetAt(ADocument, ALine, ACharacter, LUse);
  if LTarget = nil then
    Exit;

  LLines := TList<string>.Create();
  try
    // An overload set (a name with no single declaration): every member
    // once, as FreeStrike's hover
    LRoutines := TPCLspSymbols.SetOf(LUse, LTarget);
    if Length(LRoutines) > 0 then
    begin
      for LRoutine in LRoutines do
      begin
        LLine := TPCLspSymbols.DeclText(LRoutine);
        if (LLine <> '') and not LLines.Contains(LLine) then
          LLines.Add(LLine);
      end;
    end
    else
    begin
      LLine := TPCLspSymbols.DeclText(LTarget);
      if LLine <> '' then
        LLines.Add(LLine);
    end;
    if LLines.Count = 0 then
      Exit;
    Result := PC_LSP_HOVER_FENCE + PC_LSP_HOVER_LANGUAGE + #10 +
      string.Join(#10, LLines.ToArray()) + #10 + PC_LSP_HOVER_FENCE;
  finally
    LLines.Free();
  end;

  // Its /// doc comment, rendered (E2.6). An overload set has no single
  // doc: its members' docs differ
  if Length(LRoutines) = 0 then
  begin
    LDoc := TPCLspDocs.Markdown(TPCLspSymbols.DocTextOf(LTarget));
    if LDoc <> '' then
      Result := Result + #10#10 + LDoc;
  end;

  // Declared in another file: its file name (PIXELS' hover)
  if LTarget is TPCModule then
    LFile := TPCModule(LTarget).SourceFile
  else
    LFile := LTarget.Range.Filename;
  if (LFile <> '') and not SamePathSafe(LFile, ADocument.Filename) then
  begin
    LSlash := LastDelimiter('/\', LFile);
    Result := Result + #10#10 + '*' + Copy(LFile, LSlash + 1, MaxInt) + '*';
  end;
end;

procedure TPCLspServer.DoHover(const AId: TPCLspRequestId; const AParams: TJSON);
var
  LDocument: TPCLspDocument;
  LLine: Integer;
  LCharacter: Integer;
  LText: string;
  LResult: TJSONObject;
  LContents: TJSONObject;
begin
  if not DoPositionRequest(AId, AParams, PC_LSP_HOVER, LDocument, LLine, LCharacter) then
    Exit;

  LText := DoHoverText(LDocument, LLine, LCharacter);
  if LText = '' then
  begin
    SendResult(AId, TJSONNull.Create());
    Exit;
  end;

  LResult := TJSONObject.Create();
  LContents := TJSONObject.Create();
  LResult.AddPair('contents', LContents);
  LContents.AddPair('kind', 'markdown');
  LContents.AddPair('value', LText);
  SendResult(AId, LResult);
end;

procedure TPCLspServer.DoInlayHint(const AId: TPCLspRequestId; const AParams: TJSON);
var
  LUri: string;
  LFirst: Integer;
  LLast: Integer;
  LDocument: TPCLspDocument;
  LHints: TArray<TPCLspHint>;
  LHint: TPCLspHint;
  LResult: TJSONArray;
  LItem: TJSONObject;
  LPosition: TJSONObject;
  LLine: Integer;
  LCharacter: Integer;
  LEndCharacter: Integer;
begin
  if (not AParams.TryGetString('textDocument.uri', LUri)) or
     (not AParams.TryGetInt32('range.start.line', LFirst)) or
     (not AParams.TryGetInt32('range.end.line', LLast)) or
     (not AParams.TryGetInt32('range.end.character', LEndCharacter)) or
     (LFirst < 0) or (LLast < LFirst) then
  begin
    SendError(AId, PC_LSP_ERR_INVALID_PARAMS, Format(RSLspBadParams, [PC_LSP_INLAY_HINT]));
    Exit;
  end;
  // A range's end is exclusive: ending at a line's first character, the
  // range holds nothing of that line
  if (LEndCharacter = 0) and (LLast > LFirst) then
    Dec(LLast);
  // A document the server does not hold, or one that is no file, has no AST
  if (not FDocuments.TryGetValue(LUri, LDocument)) or (LDocument.Filename = '') then
  begin
    SendResult(AId, TJSONArray.Create());
    Exit;
  end;

  // The parameter names of the calls whose arguments start on the range's
  // lines (PIXELS' DoInlayHint): label 'name:' before the argument
  DoAnalyseIfStale(LDocument);
  LHints := TPCLspHints.CallHints(FCompiler.GetMainModule(), UInt64(LFirst) + 1,
    UInt64(LLast) + 1);
  LResult := TJSONArray.Create();
  try
    for LHint in LHints do
    begin
      LLine := Integer(LHint.Line) - 1;
      LCharacter := LDocument.ClientCharacter(LLine,
        LDocument.ByteColumnToColumn(LHint.Line, LHint.ByteColumn), FEncoding);

      LItem := TJSONObject.Create();
      LResult.AddElement(LItem);
      LPosition := TJSONObject.Create();
      LItem.AddPair('position', LPosition);
      LPosition.AddPair('line', TJSONNumber.Create(LLine));
      LPosition.AddPair('character', TJSONNumber.Create(LCharacter));
      LItem.AddPair('label', LHint.HintText);
      LItem.AddPair('kind', TJSONNumber.Create(PC_LSP_HINT_PARAMETER));
      LItem.AddPair('paddingRight', TJSONBool.Create(True));
    end;
  except
    // DoHandleRequest answers the request with the error
    LResult.Free();
    raise;
  end;
  SendResult(AId, LResult);
end;

function TPCLspServer.DoSymbolJson(const ADocument: TPCLspDocument; const ANode: TPCNode): TJSONObject;
var
  LDetail: string;
  LChildren: TArray<TPCNode>;
  LChild: TPCNode;
  LArray: TJSONArray;
begin
  Result := TJSONObject.Create();
  try
    Result.AddPair('name', TPCLspOutline.NameOf(ANode));
    LDetail := TPCLspOutline.DetailOf(ANode);
    if LDetail <> '' then
      Result.AddPair('detail', LDetail);
    Result.AddPair('kind', TJSONNumber.Create(TPCLspOutline.KindOf(ANode)));
    Result.AddPair('range', TPCLspRange.ToJson(ADocument, ANode.Range, FEncoding));
    Result.AddPair('selectionRange',
      TPCLspRange.ToJson(ADocument, TPCLspOutline.SelectionOf(ANode), FEncoding));

    LChildren := TPCLspOutline.ChildrenOf(ANode);
    if Length(LChildren) > 0 then
    begin
      LArray := TJSONArray.Create();
      Result.AddPair('children', LArray);
      for LChild in LChildren do
        LArray.AddElement(DoSymbolJson(ADocument, LChild));
    end;
  except
    Result.Free();
    raise;
  end;
end;

procedure TPCLspServer.DoDocumentSymbol(const AId: TPCLspRequestId; const AParams: TJSON);
var
  LUri: string;
  LDocument: TPCLspDocument;
  LItems: TArray<TPCNode>;
  LItem: TPCNode;
  LResult: TJSONArray;
begin
  if not AParams.TryGetString('textDocument.uri', LUri) then
  begin
    SendError(AId, PC_LSP_ERR_INVALID_PARAMS, Format(RSLspBadParams, [PC_LSP_DOCUMENT_SYMBOL]));
    Exit;
  end;
  // A document the server does not hold, or one that is no file, has no AST
  if (not FDocuments.TryGetValue(LUri, LDocument)) or (LDocument.Filename = '') then
  begin
    SendResult(AId, TJSONArray.Create());
    Exit;
  end;

  // The document's own declarations as the parser wrote them (PIXELS'
  // DoDocumentSymbol); every range is in this buffer
  DoAnalyseIfStale(LDocument);
  LItems := TPCLspOutline.Items(FCompiler.GetMainModule());
  LResult := TJSONArray.Create();
  try
    for LItem in LItems do
      LResult.AddElement(DoSymbolJson(LDocument, LItem));
  except
    // DoHandleRequest answers the request with the error
    LResult.Free();
    raise;
  end;
  SendResult(AId, LResult);
end;

function TPCLspServer.DoOpenFileDocuments(): TArray<TPCLspDocument>;
var
  LUris: TArray<string>;
  LUri: string;
  LList: TList<TPCLspDocument>;
begin
  // By uri: an answer does not depend on the dictionary's order
  LUris := FDocuments.Keys.ToArray();
  TArray.Sort<string>(LUris);
  LList := TList<TPCLspDocument>.Create();
  try
    for LUri in LUris do
      if FDocuments[LUri].Filename <> '' then
        LList.Add(FDocuments[LUri]);
    Result := LList.ToArray();
  finally
    LList.Free();
  end;
end;

procedure TPCLspServer.DoAddWorkspaceSymbols(const ADocument: TPCLspDocument; const ANode: TPCNode;
  const AContainer: string; const AQuery: string; const AResult: TJSONArray);
var
  LName: string;
  LItem: TJSONObject;
  LLocation: TJSONObject;
  LChild: TPCNode;
begin
  // An import is a place in the file, not a declaration of it
  if ANode is TPCImport then
    Exit;

  LName := TPCLspOutline.NameOf(ANode);
  if (AQuery = '') or LName.ToLower().Contains(AQuery) then
  begin
    LItem := TJSONObject.Create();
    AResult.AddElement(LItem);
    LItem.AddPair('name', LName);
    LItem.AddPair('kind', TJSONNumber.Create(TPCLspOutline.KindOf(ANode)));
    LLocation := TJSONObject.Create();
    LItem.AddPair('location', LLocation);
    LLocation.AddPair('uri', ADocument.Uri);
    // The name, where a pick lands (documentSymbol's selectionRange)
    LLocation.AddPair('range',
      TPCLspRange.ToJson(ADocument, TPCLspOutline.SelectionOf(ANode), FEncoding));
    if AContainer <> '' then
      LItem.AddPair('containerName', AContainer);
  end;

  // A type's members and a routine's local routines and types, as the outline
  for LChild in TPCLspOutline.ChildrenOf(ANode) do
    DoAddWorkspaceSymbols(ADocument, LChild, LName, AQuery, AResult);
end;

procedure TPCLspServer.DoWorkspaceSymbol(const AId: TPCLspRequestId; const AParams: TJSON);
var
  LQuery: string;
  LDocument: TPCLspDocument;
  LItem: TPCNode;
  LResult: TJSONArray;
begin
  if not AParams.TryGetString('query', LQuery) then
  begin
    SendError(AId, PC_LSP_ERR_INVALID_PARAMS, Format(RSLspBadParams, [PC_LSP_WORKSPACE_SYMBOL]));
    Exit;
  end;
  // A case-insensitive substring; the client ranks
  LQuery := LQuery.ToLower();

  LResult := TJSONArray.Create();
  try
    // Each open document's own declarations (documentSymbol's outline), its
    // ranges in its own buffer; an analysis replaces the AST, so each one is
    // read before the next
    for LDocument in DoOpenFileDocuments() do
    begin
      DoAnalyseIfStale(LDocument);
      for LItem in TPCLspOutline.Items(FCompiler.GetMainModule()) do
        DoAddWorkspaceSymbols(LDocument, LItem, '', LQuery, LResult);
    end;
  except
    // DoHandleRequest answers the request with the error
    LResult.Free();
    raise;
  end;
  SendResult(AId, LResult);
end;

function TPCLspServer.DoCallItem(const ANode: TPCNode): TJSONObject;
var
  LModule: TPCModule;
  LRange: TSourceRange;
  LSelection: TSourceRange;
  LFile: string;
  LName: string;
  LDetail: string;
  LKind: Integer;
  LDocument: TPCLspDocument;
begin
  if ANode is TPCModule then
  begin
    // A caller outside every routine: its module (a leaf in the editor)
    LModule := TPCModule(ANode);
    LFile := LModule.SourceFile;
    LName := LModule.ModuleName;
    if LName = '' then
      LName := TPath.GetFileNameWithoutExtension(LFile);
    LDetail := '';
    LKind := PC_LSP_SYMBOL_MODULE;
    LSelection := LModule.NameRange;
    // A module without a header names nothing: the top of its file
    if LSelection.StartLine < 1 then
      LSelection := Default(TSourceRange);
    LRange := LModule.Range;
    if LRange.StartLine < 1 then
      LRange := LSelection;
  end
  else
  begin
    LSelection := TPCLspOutline.SelectionOf(ANode);
    LRange := ANode.Range;
    LFile := LSelection.Filename;
    LName := TPCLspOutline.NameOf(ANode);
    LDetail := TPCLspOutline.DetailOf(ANode);
    LKind := TPCLspOutline.KindOf(ANode);
  end;

  // The open buffer when the file is open, else its disk text
  LDocument := DoDocumentFor(LFile);
  Result := TJSONObject.Create();
  try
    Result.AddPair('name', LName);
    Result.AddPair('kind', TJSONNumber.Create(LKind));
    if LDetail <> '' then
      Result.AddPair('detail', LDetail);
    Result.AddPair('uri', LDocument.Uri);
    Result.AddPair('range', TPCLspRange.ToJson(LDocument, LRange, FEncoding));
    Result.AddPair('selectionRange', TPCLspRange.ToJson(LDocument, LSelection, FEncoding));
  except
    Result.Free();
    raise;
  end;
end;

procedure TPCLspServer.DoPrepareCallHierarchy(const AId: TPCLspRequestId; const AParams: TJSON);
var
  LDocument: TPCLspDocument;
  LLine: Integer;
  LCharacter: Integer;
  LUse: TPCLspUse;
  LRoutine: TPCRoutine;
  LResult: TJSONArray;
begin
  if not DoPositionRequest(AId, AParams, PC_LSP_PREPARE_CALLS, LDocument, LLine, LCharacter) then
    Exit;
  // The routine declared or used at the position (definition's rule)
  LRoutine := TPCLspCalls.RoutineOf(DoTargetAt(LDocument, LLine, LCharacter, LUse));
  if LRoutine = nil then
  begin
    SendResult(AId, TJSONNull.Create());
    Exit;
  end;

  // Disk texts are read for this request only
  FDiskDocuments.Clear();
  LResult := TJSONArray.Create();
  try
    try
      LResult.AddElement(DoCallItem(LRoutine));
    except
      // DoHandleRequest answers the request with the error
      LResult.Free();
      raise;
    end;
  finally
    FDiskDocuments.Clear();
  end;
  SendResult(AId, LResult);
end;

function TPCLspServer.DoCallItemKey(const AId: TPCLspRequestId; const AParams: TJSON;
  const AMethod: string; out AKey: string): Boolean;
var
  LUri: string;
  LFilename: string;
  LKind: Integer;
  LLine: Integer;
  LCharacter: Integer;
  LDocument: TPCLspDocument;
begin
  Result := False;
  AKey := '';
  if (not AParams.TryGetString('item.uri', LUri)) or
     (not AParams.TryGetInt32('item.kind', LKind)) or
     (not AParams.TryGetInt32('item.selectionRange.start.line', LLine)) or
     (not AParams.TryGetInt32('item.selectionRange.start.character', LCharacter)) then
  begin
    SendError(AId, PC_LSP_ERR_INVALID_PARAMS, Format(RSLspBadParams, [AMethod]));
    Exit;
  end;
  // A module stands in for its top-level blocks (a leaf: no calls of its
  // own here); a uri that is no file has no AST
  if (LKind = PC_LSP_SYMBOL_MODULE) or not TPCLspUri.ToFilename(LUri, LFilename) then
  begin
    SendResult(AId, TJSONArray.Create());
    Exit;
  end;

  // The client's position over the text it counted it on: the open buffer,
  // else the disk text; the item is re-found by its name's position, which
  // outlives the analysis it came from
  LDocument := DoDocumentFor(LFilename);
  AKey := TPCLspCalls.KeyAt(LFilename, UInt64(LLine) + 1,
    LDocument.ByteColumnAt(LLine, LCharacter, FEncoding));
  Result := True;
end;

procedure TPCLspServer.DoCalls(const AId: TPCLspRequestId; const AParams: TJSON;
  const AIncoming: Boolean);
var
  LMethod: string;
  LKey: string;
  LResult: TJSONArray;
  LGroups: TDictionary<string, TJSONArray>;
  LSeenFiles: TDictionary<string, Boolean>;
  LDocument: TPCLspDocument;
  LModule: TPCModule;
  LSite: TPCLspCallSite;
  LEnd: TPCNode;
  LEndKey: string;
  LSiteRange: TSourceRange;
  LRanges: TJSONArray;
  LCall: TJSONObject;
begin
  if AIncoming then
    LMethod := PC_LSP_INCOMING_CALLS
  else
    LMethod := PC_LSP_OUTGOING_CALLS;

  // Disk texts are read for this request only
  FDiskDocuments.Clear();
  try
    if not DoCallItemKey(AId, AParams, LMethod, LKey) then
      Exit;

    LResult := TJSONArray.Create();
    // The other end's key -> its call's fromRanges (owned by LResult)
    LGroups := TDictionary<string, TJSONArray>.Create();
    LSeenFiles := TDictionary<string, Boolean>.Create();
    try
      try
        // Every module the open documents reach, each file once: two open
        // programs importing one unit walk it once. An analysis replaces the
        // AST, so its nodes are read before the next one
        for LDocument in DoOpenFileDocuments() do
        begin
          DoAnalyseIfStale(LDocument);
          for LModule in TPCLspCalls.ModulesOf(FCompiler.GetMainModule()) do
          begin
            if LSeenFiles.ContainsKey(TPCLspCalls.KeyOf(LModule)) then
              Continue;
            LSeenFiles.Add(TPCLspCalls.KeyOf(LModule), True);

            for LSite in TPCLspCalls.Sites(LModule) do
            begin
              // Incoming: the item's callers, grouped by caller; outgoing:
              // the item's own calls, grouped by the routine called
              if AIncoming then
              begin
                if TPCLspCalls.KeyOf(LSite.Target) <> LKey then
                  Continue;
                LEnd := LSite.Caller;
              end
              else
              begin
                if TPCLspCalls.KeyOf(LSite.Caller) <> LKey then
                  Continue;
                LEnd := LSite.Target;
              end;

              LEndKey := TPCLspCalls.KeyOf(LEnd);
              LSiteRange := TPCLspCalls.SiteRange(LSite.Call);

              if not LGroups.TryGetValue(LEndKey, LRanges) then
              begin
                LCall := TJSONObject.Create();
                LResult.AddElement(LCall);
                if AIncoming then
                  LCall.AddPair('from', DoCallItem(LEnd))
                else
                  LCall.AddPair('to', DoCallItem(LEnd));
                LRanges := TJSONArray.Create();
                LCall.AddPair('fromRanges', LRanges);
                LGroups.Add(LEndKey, LRanges);
              end;
              // In the caller's file, as the spec's fromRanges are
              LRanges.AddElement(TPCLspRange.ToJson(DoDocumentFor(LSiteRange.Filename),
                LSiteRange, FEncoding));
            end;
          end;
        end;
      except
        // DoHandleRequest answers the request with the error
        LResult.Free();
        raise;
      end;
    finally
      LGroups.Free();
      LSeenFiles.Free();
    end;
    SendResult(AId, LResult);
  finally
    FDiskDocuments.Clear();
  end;
end;

function TPCLspServer.DoCompletionContext(const ADocument: TPCLspDocument; const ALine: Integer;
  const ACharacter: Integer): TPCLspCompletionContext;
var
  LErrors: TErrors;
  LLexer: TPCLexer;
  LStream: TPCTokenStream;
begin
  // As DoSemanticData: the lexer's reports are the diagnostics' business
  LErrors := TErrors.Create();
  LLexer := TPCLexer.Create();
  LStream := TPCTokenStream.Create();
  try
    LLexer.SetErrors(LErrors);
    LStream.SetErrors(LErrors);
    LLexer.TokenizeBytes(ADocument.GetBytes(), ADocument.Filename, LStream);
    Result := TPCLspCompletion.ContextAt(LStream,
      ADocument.ByteOffsetAt(ALine, ACharacter, FEncoding));
  finally
    LStream.Free();
    LLexer.Free();
    LErrors.Free();
  end;
end;

procedure TPCLspServer.DoCompletion(const AId: TPCLspRequestId; const AParams: TJSON);
var
  LDocument: TPCLspDocument;
  LLine: Integer;
  LCharacter: Integer;
  LTrigger: string;
  LContext: TPCLspCompletionContext;
  LItems: TArray<TPCLspCompletionItem>;
  LItem: TPCLspCompletionItem;
  LResult: TJSONObject;
  LArray: TJSONArray;
  LJson: TJSONObject;
begin
  if not DoPositionRequest(AId, AParams, PC_LSP_COMPLETION, LDocument, LLine, LCharacter) then
    Exit;
  LContext := DoCompletionContext(LDocument, LLine, LCharacter);
  // '>' opens a list only as the end of '->' (a '>' alone is a comparison)
  if AParams.TryGetString('context.triggerCharacter', LTrigger) and (LTrigger = PC_LSP_TRIGGER_ARROW) and
     not (LContext.HasQualifier and (LContext.Access = maArrow)) then
    LContext.HasList := False;
  if not LContext.HasList then
  begin
    SendResult(AId, TJSONNull.Create());
    Exit;
  end;

  DoAnalyseIfStale(LDocument);
  LItems := TPCLspCompletion.Items(FCompiler.GetMainModule(), LContext);
  LResult := TJSONObject.Create();
  try
    LResult.AddPair('isIncomplete', TJSONBool.Create(False));
    LArray := TJSONArray.Create();
    LResult.AddPair('items', LArray);
    for LItem in LItems do
    begin
      LJson := TJSONObject.Create();
      LArray.AddElement(LJson);
      LJson.AddPair('label', LItem.ItemLabel);
      LJson.AddPair('kind', TJSONNumber.Create(LItem.ItemKind));
      if LItem.Detail <> '' then
        LJson.AddPair('detail', LItem.Detail);
      LJson.AddPair('sortText', LItem.SortText);
      if LItem.InsertText <> '' then
      begin
        LJson.AddPair('insertText', LItem.InsertText);
        if LItem.IsSnippet then
          LJson.AddPair('insertTextFormat', TJSONNumber.Create(PC_LSP_INSERT_SNIPPET));
      end;
    end;
  except
    // DoHandleRequest answers the request with the error
    LResult.Free();
    raise;
  end;
  SendResult(AId, LResult);
end;

function TPCLspServer.DoFormatOptions(const AParams: TJSON): TPCLspFormatOptions;
var
  LOptions: TJSON;
  LInsertSpaces: Boolean;
begin
  // FS DoFormatOptions: spec keys + pcpp.* keys (the editor's settings,
  // renderer.js) over the defaults; a missing or mistyped key keeps its
  // default, numbers are clamped
  Result := TPCLspFormatOptions.Defaults();
  if AParams.TryGetObject('options', LOptions) then
  begin
    OptionInteger(LOptions, 'tabSize', Result.IndentSize);
    LInsertSpaces := not Result.UseTabs;
    if OptionBoolean(LOptions, 'insertSpaces', LInsertSpaces) then
      Result.UseTabs := not LInsertSpaces;
    OptionBoolean(LOptions, 'trimTrailingWhitespace', Result.TrimTrailingWhitespace);
    OptionBoolean(LOptions, 'insertFinalNewline', Result.FinalNewline);
    OptionBoolean(LOptions, 'pcpp.spaceAroundAssign', Result.SpaceAroundAssign);
    OptionBoolean(LOptions, 'pcpp.spaceAroundOperators', Result.SpaceAroundOperators);
    OptionBoolean(LOptions, 'pcpp.spaceAfterComma', Result.SpaceAfterComma);
    OptionBoolean(LOptions, 'pcpp.spaceBeforeColon', Result.SpaceBeforeColon);
    OptionBoolean(LOptions, 'pcpp.spaceAfterColon', Result.SpaceAfterColon);
    OptionInteger(LOptions, 'pcpp.maxBlankLines', Result.MaxBlankLines);
    OptionInteger(LOptions, 'pcpp.maxLineLength', Result.MaxLineLength);
  end;
  Result.Clamp();
end;

function TPCLspServer.DoTextEditJson(const ADocument: TPCLspDocument;
  const AEdit: TPCLspFormatEdit): TJSONObject;
var
  LRange: TJSONObject;
  LPosition: TJSONObject;
  LLine: Integer;
  LCharacter: Integer;
begin
  // The edit's byte offsets in the buffer as client positions
  Result := TJSONObject.Create();
  try
    LRange := TJSONObject.Create();
    Result.AddPair('range', LRange);
    ADocument.PositionAtByte(UInt64(AEdit.StartOffset), FEncoding, LLine, LCharacter);
    LPosition := TJSONObject.Create();
    LRange.AddPair('start', LPosition);
    LPosition.AddPair('line', TJSONNumber.Create(LLine));
    LPosition.AddPair('character', TJSONNumber.Create(LCharacter));
    ADocument.PositionAtByte(UInt64(AEdit.EndOffset), FEncoding, LLine, LCharacter);
    LPosition := TJSONObject.Create();
    LRange.AddPair('end', LPosition);
    LPosition.AddPair('line', TJSONNumber.Create(LLine));
    LPosition.AddPair('character', TJSONNumber.Create(LCharacter));
    Result.AddPair('newText', AEdit.NewText);
  except
    Result.Free();
    raise;
  end;
end;

procedure TPCLspServer.DoFormatting(const AId: TPCLspRequestId; const AParams: TJSON;
  const ARange: Boolean);
var
  LMethod: string;
  LUri: string;
  LDocument: TPCLspDocument;
  LOptions: TPCLspFormatOptions;
  LEdits: TPCLspFormatEdits;
  LEdit: TPCLspFormatEdit;
  LFrom: UInt64;
  LTo: UInt64;
  LLine: Integer;
  LCharacter: Integer;
  LEndLine: Integer;
  LEndCharacter: Integer;
  LClean: Boolean;
  LResult: TJSONArray;
begin
  // FS DoFormatting (F5): both requests in one handler; a range keeps the
  // edits whose gap starts inside it (F3 S10); a refusal is an empty result
  // and a warning the user sees (Q6), not an error
  if ARange then
    LMethod := PC_LSP_RANGE_FORMATTING
  else
    LMethod := PC_LSP_FORMATTING;
  if not AParams.TryGetString('textDocument.uri', LUri) then
  begin
    SendError(AId, PC_LSP_ERR_INVALID_PARAMS, Format(RSLspBadParams, [LMethod]));
    Exit;
  end;
  LLine := 0;
  LCharacter := 0;
  LEndLine := 0;
  LEndCharacter := 0;
  if ARange and ((not AParams.TryGetInt32('range.start.line', LLine)) or
    (not AParams.TryGetInt32('range.start.character', LCharacter)) or
    (not AParams.TryGetInt32('range.end.line', LEndLine)) or
    (not AParams.TryGetInt32('range.end.character', LEndCharacter))) then
  begin
    SendError(AId, PC_LSP_ERR_INVALID_PARAMS, Format(RSLspBadParams, [LMethod]));
    Exit;
  end;
  // A document the server does not hold, or one that is no file, has no AST
  if (not FDocuments.TryGetValue(LUri, LDocument)) or (LDocument.Filename = '') then
  begin
    SendResult(AId, TJSONArray.Create());
    Exit;
  end;

  LOptions := DoFormatOptions(AParams);
  LFrom := 0;
  LTo := High(UInt64);
  if ARange then
  begin
    LFrom := LDocument.ByteOffsetAt(LLine, LCharacter, FEncoding);
    LTo := LDocument.ByteOffsetAt(LEndLine, LEndCharacter, FEncoding);
  end;

  // The tree of this buffer at this version; a lexer / conditional / parser
  // report of the file refuses (a SEM report does not: a type error is
  // formattable)
  DoAnalyseIfStale(LDocument);
  LClean := not FCompiler.HasSyntaxReport(LDocument.Filename);

  LResult := TJSONArray.Create();
  try
    if FFormatter.FormatSource(LDocument.GetBytes(), LDocument.Filename,
      FCompiler.GetMainModule(), LClean, LOptions, LEdits) then
    begin
      for LEdit in LEdits do
      begin
        if (UInt64(LEdit.StartOffset) >= LFrom) and (UInt64(LEdit.StartOffset) < LTo) then
          LResult.AddElement(DoTextEditJson(LDocument, LEdit));
      end;
    end
    else
    begin
      if FFormatter.Refusal = frInternal then
        SendLog(Format(RSLspInternalError, [LMethod, FFormatter.RefusalReason]));
      SendShowMessage(PC_LSP_MESSAGE_WARNING, FFormatter.RefusalReason);
    end;
  except
    // DoHandleRequest answers the request with the error
    LResult.Free();
    raise;
  end;
  SendResult(AId, LResult);
end;

procedure TPCLspServer.DoMarkDirty(const AUri: string);
begin
  if not FDirty.Contains(AUri) then
    FDirty.Add(AUri);
end;

procedure TPCLspServer.DoFlushDiagnostics();
var
  LUris: TArray<string>;
  LUri: string;
  LDocument: TPCLspDocument;
begin
  // Cleared first: a run never needs its own marks
  LUris := FDirty.ToArray();
  FDirty.Clear();
  try
    for LUri in LUris do
      if FDocuments.TryGetValue(LUri, LDocument) then
        DoCheckRun(LDocument);
    DoUpdateWatchers();
  except
    // A notification-driven run has no response: the client gets a log
    on E: Exception do
      SendLog(Format(RSLspInternalError, [PC_LSP_PUBLISH_DIAGNOSTICS, E.Message]));
  end;
end;

procedure TPCLspServer.DoCheckRun(const ADocument: TPCLspDocument);
var
  LFiles: TList<string>;
  LLists: TObjectList<TList<TError>>;
  LMain: TList<TError>;
  LError: TError;
  LIndex: Integer;
  LI: Integer;
  LFilename: string;
  LTarget: TPCLspDocument;
  LKept: TList<TError>;
  LSeen: TDictionary<string, Boolean>;
  LBuilder: TPCLspDiagnosticBuilder;
  LKey: string;
begin
  FDiskDocuments.Clear();
  LFiles := TList<string>.Create();
  LLists := TObjectList<TList<TError>>.Create(True);
  LMain := TList<TError>.Create();
  LSeen := TDictionary<string, Boolean>.Create();
  LBuilder := TPCLspDiagnosticBuilder.Create();
  try
    LBuilder.Init(DoDocumentFor, FEncoding);

    // 1 the build's frontend on the buffers; a document that is no file
    // has nothing to check
    if ADocument.Filename <> '' then
    begin
      DoAnalyse(ADocument);
      // What on disk this check's result rests on (DoUpdateWatchers)
      FWatchPaths.AddOrSetValue(ADocument.Uri, FCompiler.DiskPaths());

      // 2 the reports by file; one without a file belongs to the document
      for LError in FCompiler.GetErrors().GetItems() do
      begin
        LFilename := LError.Range.Filename;
        if (LFilename = '') or SamePathSafe(LFilename, ADocument.Filename) then
        begin
          LMain.Add(LError);
          Continue;
        end;
        LIndex := -1;
        for LI := 0 to LFiles.Count - 1 do
          if SamePathSafe(LFiles[LI], LFilename) then
          begin
            LIndex := LI;
            Break;
          end;
        if LIndex < 0 then
        begin
          LFiles.Add(LFilename);
          LIndex := LLists.Add(TList<TError>.Create());
        end;
        LLists[LIndex].Add(LError);
      end;
    end;

    // 3 the document itself
    SendDiagnostics(ADocument.Uri, ADocument.Version, LBuilder.Build(ADocument, LMain.ToArray()));
    LSeen.AddOrSetValue(ADocument.Uri, True);

    // 4 the imported files that are not open: their errors (a library
    // unit's hints and warnings are not the user's to act on). An open one
    // speaks for itself through its own check
    for LI := 0 to LFiles.Count - 1 do
    begin
      if DoOpenDocument(LFiles[LI]) <> nil then
        Continue;
      LKept := TList<TError>.Create();
      try
        for LError in LLists[LI] do
          if LError.Severity in [esError, esFatal] then
            LKept.Add(LError);
        if LKept.Count = 0 then
          Continue;
        LTarget := DoDiskDocument(LFiles[LI]);
        SendDiagnostics(LTarget.Uri, -1, LBuilder.Build(LTarget, LKept.ToArray()));
        LSeen.AddOrSetValue(LTarget.Uri, True);
      finally
        LKept.Free();
      end;
    end;

    // 5 what this owner published before and not now is cleared
    DoClearOwned(ADocument.Uri, LSeen);
    for LKey in LSeen.Keys do
      FPublished.AddOrSetValue(LKey, ADocument.Uri);
  finally
    LBuilder.Free();
    LSeen.Free();
    LMain.Free();
    LLists.Free();
    LFiles.Free();
    FDiskDocuments.Clear();
  end;
end;

procedure TPCLspServer.DoClearOwned(const AOwner: string;
  const ASeen: TDictionary<string, Boolean>);
var
  LPair: TPair<string, string>;
  LStale: TList<string>;
  LUri: string;
begin
  LStale := TList<string>.Create();
  try
    for LPair in FPublished do
      if (LPair.Value = AOwner) and (not ASeen.ContainsKey(LPair.Key)) then
        LStale.Add(LPair.Key);
    for LUri in LStale do
    begin
      SendDiagnostics(LUri, -1, TJSONArray.Create());
      FPublished.Remove(LUri);
    end;
  finally
    LStale.Free();
  end;
end;

procedure TPCLspServer.SendDiagnostics(const AUri: string; const AVersion: Integer;
  const ADiagnostics: TJSONArray);
var
  LMessage: TJSONObject;
  LParams: TJSONObject;
begin
  // Takes ownership of ADiagnostics; AVersion < 0 = no version (a file
  // that is not open, or a clear)
  LMessage := TJSONObject.Create();
  LMessage.AddPair('jsonrpc', PC_LSP_JSONRPC_VERSION);
  LMessage.AddPair('method', PC_LSP_PUBLISH_DIAGNOSTICS);
  LParams := TJSONObject.Create();
  LMessage.AddPair('params', LParams);
  LParams.AddPair('uri', AUri);
  if AVersion >= 0 then
    LParams.AddPair('version', TJSONNumber.Create(AVersion));
  LParams.AddPair('diagnostics', ADiagnostics);
  DoSend(LMessage);
end;

procedure TPCLspServer.SendRequest(const AId: string; const AMethod: string;
  const AParams: TJSONObject);
var
  LMessage: TJSONObject;
begin
  // Takes ownership of AParams
  LMessage := TJSONObject.Create();
  LMessage.AddPair('jsonrpc', PC_LSP_JSONRPC_VERSION);
  LMessage.AddPair('id', AId);
  LMessage.AddPair('method', AMethod);
  LMessage.AddPair('params', AParams);
  DoSend(LMessage);
end;

procedure TPCLspServer.SendResult(const AId: TPCLspRequestId; const AResult: TJSONValue);
var
  LMessage: TJSONObject;
begin
  // Takes ownership of AResult
  LMessage := TJSONObject.Create();
  LMessage.AddPair('jsonrpc', PC_LSP_JSONRPC_VERSION);
  LMessage.AddPair('id', AId.ToJson());
  LMessage.AddPair('result', AResult);
  DoSend(LMessage);
end;

procedure TPCLspServer.SendError(const AId: TPCLspRequestId; const ACode: Integer;
  const AMessage: string);
var
  LMessage: TJSONObject;
  LError: TJSONObject;
begin
  // A message whose id cannot be read is answered with id null
  LMessage := TJSONObject.Create();
  LMessage.AddPair('jsonrpc', PC_LSP_JSONRPC_VERSION);
  LMessage.AddPair('id', AId.ToJson());
  LError := TJSONObject.Create();
  LMessage.AddPair('error', LError);
  LError.AddPair('code', TJSONNumber.Create(ACode));
  LError.AddPair('message', AMessage);
  DoSend(LMessage);
end;

procedure TPCLspServer.SendLog(const AMessage: string);
begin
  DoWindowMessage(PC_LSP_LOG_MESSAGE, PC_LSP_MESSAGE_ERROR, AMessage);
end;

procedure TPCLspServer.SendShowMessage(const AType: Integer; const AMessage: string);
begin
  DoWindowMessage(PC_LSP_SHOW_MESSAGE, AType, AMessage);
end;

procedure TPCLspServer.DoWindowMessage(const AMethod: string; const AType: Integer;
  const AMessage: string);
var
  LMessage: TJSONObject;
  LParams: TJSONObject;
begin
  // A window/logMessage or window/showMessage notification
  LMessage := TJSONObject.Create();
  LMessage.AddPair('jsonrpc', PC_LSP_JSONRPC_VERSION);
  LMessage.AddPair('method', AMethod);
  LParams := TJSONObject.Create();
  LMessage.AddPair('params', LParams);
  LParams.AddPair('type', TJSONNumber.Create(AType));
  LParams.AddPair('message', AMessage);
  DoSend(LMessage);
end;

procedure TPCLspServer.DoSend(const AMessage: TJSONObject);
var
  LText: string;
begin
  // Takes ownership of AMessage
  try
    LText := AMessage.ToJSON();
  finally
    AMessage.Free();
  end;
  // The client cannot be reached any more: stop as if it had left
  if not FTransport.WriteMessage(LText) then
    DoRequestExit();
end;

end.
