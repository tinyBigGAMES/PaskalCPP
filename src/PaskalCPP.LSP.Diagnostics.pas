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
  PaskalCPP.LSP.Diagnostics - one document's LSP Diagnostic[]

  Turns what the frontend reported for one file (TError items) into the
  Diagnostic[] of textDocument/publishDiagnostics. Shape adopted from
  FreeStrike.LSP.Diagnostics (plans\done\PLAN-EDITOR.md E2.1e); PaskalCPP has one
  reporter, its own frontend, so nothing is merged.

  Dependencies: StdApp.Base, PaskalCPP.LSP.Document, PaskalCPP.LSP.Uri
  Notes:
    - Every range goes through TPCLspRange.ToJson (PaskalCPP.LSP.Document):
      the frontend's 1-based byte ranges as 0-based, end-exclusive LSP
      ranges in the client's encoding; no line (0) is the top of the file.
===============================================================================}

unit PaskalCPP.LSP.Diagnostics;

interface

uses
  System.SysUtils,
  System.JSON,
  StdApp.Base,
  PaskalCPP.LSP.Document;

const
  { PC_LSP_DIAG_SOURCE }
  PC_LSP_DIAG_SOURCE = 'PaskalCPP';

  // LSP DiagnosticSeverity
  { PC_LSP_SEVERITY_ERROR }
  PC_LSP_SEVERITY_ERROR = 1;
  { PC_LSP_SEVERITY_WARNING }
  PC_LSP_SEVERITY_WARNING = 2;
  { PC_LSP_SEVERITY_INFORMATION }
  PC_LSP_SEVERITY_INFORMATION = 3;
  { PC_LSP_SEVERITY_HINT }
  PC_LSP_SEVERITY_HINT = 4;

type
  { TPCLspDocumentLookup }
  // The document whose text a location in AFilename refers to (an open
  // buffer, or the file's disk text); nil when there is none
  TPCLspDocumentLookup = reference to function(const AFilename: string): TPCLspDocument;

  { TPCLspDiagnosticBuilder }
  TPCLspDiagnosticBuilder = class(TBaseObject)
  private
    FLookup: TPCLspDocumentLookup;
    FEncoding: TPCPositionEncoding;
    function DoSeverity(const ASeverity: TErrorSeverity): Integer;
    function DoRelated(const AError: TError): TJSONArray;
    function DoItem(const ADocument: TPCLspDocument; const AError: TError): TJSONObject;
  public
    constructor Create(); override;

    // ALookup finds the text of a related location's file.
    procedure Init(const ALookup: TPCLspDocumentLookup; const AEncoding: TPCPositionEncoding);

    // AErrors: what the frontend reported for ADocument's file, in report
    // order. The caller owns the result.
    function Build(const ADocument: TPCLspDocument; const AErrors: TArray<TError>): TJSONArray;
  end;

implementation

uses
  PaskalCPP.LSP.Uri;

{ TPCLspDiagnosticBuilder }

constructor TPCLspDiagnosticBuilder.Create();
begin
  inherited;

  FLookup := nil;
  FEncoding := peUtf16;
end;

procedure TPCLspDiagnosticBuilder.Init(const ALookup: TPCLspDocumentLookup;
  const AEncoding: TPCPositionEncoding);
begin
  FLookup := ALookup;
  FEncoding := AEncoding;
end;

function TPCLspDiagnosticBuilder.DoSeverity(const ASeverity: TErrorSeverity): Integer;
begin
  case ASeverity of
    esHint:
      Result := PC_LSP_SEVERITY_HINT;
    esWarning:
      Result := PC_LSP_SEVERITY_WARNING;
  else
    // esError, esFatal
    Result := PC_LSP_SEVERITY_ERROR;
  end;
end;

function TPCLspDiagnosticBuilder.DoRelated(const AError: TError): TJSONArray;
var
  LRelated: TErrorRelated;
  LDocument: TPCLspDocument;
  LUri: string;
  LInfo: TJSONObject;
  LLocation: TJSONObject;
begin
  // DiagnosticRelatedInformation: a location and its message; one without
  // a file has no location to give and is left out
  Result := TJSONArray.Create();
  for LRelated in AError.Related do
  begin
    if LRelated.Range.Filename = '' then
      Continue;
    LDocument := nil;
    if Assigned(FLookup) then
      LDocument := FLookup(LRelated.Range.Filename);
    if LDocument <> nil then
      LUri := LDocument.Uri
    else
      LUri := TPCLspUri.FromFilename(LRelated.Range.Filename);

    LInfo := TJSONObject.Create();
    Result.AddElement(LInfo);
    LLocation := TJSONObject.Create();
    LInfo.AddPair('location', LLocation);
    LLocation.AddPair('uri', LUri);
    LLocation.AddPair('range', TPCLspRange.ToJson(LDocument, LRelated.Range, FEncoding));
    LInfo.AddPair('message', LRelated.Msg);
  end;
end;

function TPCLspDiagnosticBuilder.DoItem(const ADocument: TPCLspDocument;
  const AError: TError): TJSONObject;
var
  LRelated: TJSONArray;
begin
  Result := TJSONObject.Create();
  Result.AddPair('range', TPCLspRange.ToJson(ADocument, AError.Range, FEncoding));
  Result.AddPair('severity', TJSONNumber.Create(DoSeverity(AError.Severity)));
  if AError.Code <> '' then
    Result.AddPair('code', AError.Code);
  Result.AddPair('source', PC_LSP_DIAG_SOURCE);
  Result.AddPair('message', AError.Message);

  LRelated := DoRelated(AError);
  if LRelated.Count > 0 then
    Result.AddPair('relatedInformation', LRelated)
  else
    LRelated.Free();
end;

function TPCLspDiagnosticBuilder.Build(const ADocument: TPCLspDocument;
  const AErrors: TArray<TError>): TJSONArray;
var
  LError: TError;
begin
  Result := TJSONArray.Create();
  try
    for LError in AErrors do
      Result.AddElement(DoItem(ADocument, LError));
  except
    Result.Free();
    raise;
  end;
end;

end.
