{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  SPDX-License-Identifier: MPL-2.0

  This Source Code Form is subject to the terms of the
  Mozilla Public License, v. 2.0. If a copy of the MPL
  was not distributed with this file, You can obtain one
  at https://mozilla.org/MPL/2.0/.

 -------------------------------------------------------------------------------

  StdApp.Base - Foundation types and base class

  Defines the core abstractions that every StdApp unit builds on: the
  shared error system (TErrors), source location tracking (TSourceRange),
  the generic callback wrapper (TCallback<T>), and TBaseObject -- the
  mandatory base class for all StdApp and project classes.

  Key types:
  - TCallback<T>: Generic record wrapping a callback reference + user data
  - TSourceRange: File/line/column range for error locations
  - TError / TErrorSeverity: Structured error record with severity levels
  - TErrors: Accumulating error collection with max-error cutoff and
    optional raise-on-error behavior
  - EStdAppException: Exception class carrying a TError payload
  - TBaseObject: Base class providing shared FErrors, FStatusCallback,
    virtual Dump/InitConfig/LoadConfig/SaveConfig hooks

  Dependencies: StdApp.Resources
  Notes: Every class in the library descends from TBaseObject, never TObject.
===============================================================================}

unit StdApp.Base;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  StdApp.Resources;

const
  DEFAULT_MAX_ERRORS = 1;

type

  { TCallback }
  TCallback<T> = record
    Callback: T;
    UserData: Pointer;
    function IsAssigned(): Boolean;
  end;

  { TErrorSeverity }
  TErrorSeverity = (
    esHint,
    esWarning,
    esError,
    esFatal
  );

  { TErrorSeverities }
  TErrorSeverities = set of TErrorSeverity;

  { TSourceRange }
  TSourceRange = record
    Filename: string;
    StartLine: UInt64;
    StartColumn: UInt64;
    EndLine: UInt64;
    EndColumn: UInt64;
    StartByteOffset: UInt64;
    EndByteOffset: UInt64;

    procedure Clear();
    function IsEmpty(): Boolean;
    function ToPointString(): string;
    function ToRangeString(): string;
  end;

  { TErrorRelated }
  TErrorRelated = record
    Range: TSourceRange;
    Msg: string;
  end;

  { TError }
  TError = record
    Range: TSourceRange;
    Severity: TErrorSeverity;
    Code: string;
    Message: string;
    Related: TArray<TErrorRelated>;

    function GetSeverityString(): string;
    function ToIDEString(): string;
    function ToFullString(): string;
  end;

  { EStdAppException }
  EStdAppException = class(Exception)
    ErrorInfo: TError;
    constructor Create(const AError: TError); reintroduce;
  end;

  { TStatusCallback }
  TStatusCallback = reference to procedure(const AText: string; const AUserData: Pointer);

  { TColumnMapper }
  // Maps a stored column of AFilename's line ALine to the column a location
  // is printed with (e.g. byte columns -> the editor's UTF-16 columns)
  TColumnMapper = reference to function(const AFilename: string;
    const ALine: UInt64; const AColumn: UInt64): UInt64;

  { TErrors }
  TErrors = class
  private
    FItems: TList<TError>;
    FMaxErrors: Integer;
    FRaiseOnError: Boolean;
    FStatusCallback: TCallback<TStatusCallback>;
    FColumnMapper: TColumnMapper;
    // The hint / warning Add holds back from the status listener until it is
    // complete (its notes come by AddRelated after Add); -1 = none
    FPendingIndex: Integer;

    function CountErrors(): Integer;
    // One colored console line for AError (used by the status and PrintErrors)
    function FormatError(const AError: TError): string;
    // One colored note line under an item (the status and PrintErrors alike)
    function FormatNote(const ARelated: TErrorRelated): string;
    // AText to the status listener as is
    procedure SendStatus(const AText: string);
    // The held hint / warning, then its notes, to the status listener
    procedure SendPending();

  public
    constructor Create(); virtual;
    destructor Destroy(); override;

    // Full location with range
    procedure Add(
      const ARange: TSourceRange;
      const ASeverity: TErrorSeverity;
      const ACode: string;
      const AMessage: string;
      const AUserData: Pointer=nil
    ); overload;

    procedure Add(
      const ARange: TSourceRange;
      const ASeverity: TErrorSeverity;
      const ACode: string;
      const AMessage: string;
      const AArgs: array of const;
      const AUserData: Pointer=nil
    ); overload;

    // Point location (start = end)
    procedure Add(
      const AFilename: string;
      const ALine: UInt64;
      const AColumn: UInt64;
      const ASeverity: TErrorSeverity;
      const ACode: string;
      const AMessage: string;
      const AUserData: Pointer=nil
    ); overload;

    procedure Add(
      const AFilename: string;
      const ALine: UInt64;
      const AColumn: UInt64;
      const ASeverity: TErrorSeverity;
      const ACode: string;
      const AMessage: string;
      const AArgs: array of const;
      const AUserData: Pointer=nil
    ); overload;

    // No location
    procedure Add(
      const ASeverity: TErrorSeverity;
      const ACode: string;
      const AMessage: string;
      const AUserData: Pointer=nil
    ); overload;

    procedure Add(
      const ASeverity: TErrorSeverity;
      const ACode: string;
      const AMessage: string;
      const AArgs: array of const;
      const AUserData: Pointer=nil
    ); overload;

    // Add related info to most recent error
    procedure AddRelated(
      const ARange: TSourceRange;
      const AMessage: string
    ); overload;

    procedure AddRelated(
      const ARange: TSourceRange;
      const AMessage: string;
      const AArgs: array of const
    ); overload;

    function HasHints(): Boolean;
    function HasWarnings(): Boolean;
    function HasErrors(): Boolean;
    function HasFatal(): Boolean;
    function Count(): Integer;
    function ErrorCount(): Integer;
    function WarningCount(): Integer;
    function ReachedMaxErrors(): Boolean;
    procedure Clear();
    procedure TruncateTo(const ACount: Integer);

    function GetItems(): TList<TError>;
    function GetMaxErrors(): Integer;
    procedure SetMaxErrors(const AMaxErrors: Integer);

    procedure Status(const AText: string); overload;
    procedure Status(const AText: string; const AArgs: array of const); overload;
    procedure Status(const AEnabled: Boolean; const AText: string; const AArgs: array of const); overload;
    // Printing only: stored ranges keep their columns; FormatError and
    // PrintErrors render every location through DisplayRange. nil = as stored
    procedure SetColumnMapper(const AMapper: TColumnMapper);
    function GetColumnMapper(): TColumnMapper;
    function DisplayRange(const ARange: TSourceRange): TSourceRange;

    function  GetStatusCallback(): TStatusCallback;
    procedure SetStatusCallback(const ACallback: TStatusCallback; const AUserData: Pointer = nil); virtual;
    // Prints the items whose severity is in ASeverities (default: all)
    procedure PrintErrors(const ASeverities: TErrorSeverities = [esHint, esWarning, esError, esFatal]);
    // Sends a held hint / warning with its notes now. A hint / warning goes
    // to the status listener once complete: at the next Add, Status line,
    // PrintErrors, Clear or SetStatusCallback, or here (the end of a phase)
    procedure Flush();

    property RaiseOnError: Boolean read FRaiseOnError write FRaiseOnError;
  end;

  { TBaseObject }
  TBaseObject = class
  protected
    FErrors: TErrors;
  public
    constructor Create(); virtual;
    destructor Destroy(); override;
    function Dump(const AId: Integer = 0): string; virtual;
    procedure InitConfig(); virtual;
    procedure LoadConfig(const AFilename: string); virtual;
    procedure SaveConfig(const AFilename: string); virtual;
    procedure SetErrors(const AErrors: TErrors); virtual;
    procedure Status(const AText: string); overload;
    procedure Status(const AText: string; const AArgs: array of const); overload;
    procedure Status(const AEnabled: Boolean; const AText: string; const AArgs: array of const); overload;

  end;

implementation

uses
  StdApp.Utils,
  StdApp.Console;

{ TCallback<T> }

function TCallback<T>.IsAssigned(): Boolean;
begin
  Result := PPointer(@Callback)^ <> nil;
end;

{ TSourceRange }
procedure TSourceRange.Clear();
begin
  Filename := '';
  StartLine := 0;
  StartColumn := 0;
  EndLine := 0;
  EndColumn := 0;
  StartByteOffset := 0;
  EndByteOffset := 0;
end;

function TSourceRange.IsEmpty(): Boolean;
begin
  Result := (Filename = '') and (StartLine = 0) and (StartColumn = 0);
end;

function TSourceRange.ToPointString(): string;
begin
  if IsEmpty() then
    Result := ''
  else if (StartLine = 0) and (StartColumn = 0) then
    Result := Filename
  else
    Result := Format('%s(%d,%d)', [Filename, StartLine, StartColumn]);
end;

function TSourceRange.ToRangeString(): string;
begin
  if IsEmpty() then
    Result := ''
  else if (StartLine = EndLine) and (StartColumn = EndColumn) then
    Result := Format('%s(%d,%d)', [Filename, StartLine, StartColumn])
  else if StartLine = EndLine then
    Result := Format('%s(%d,%d-%d)', [Filename, StartLine, StartColumn, EndColumn])
  else
    Result := Format('%s(%d,%d)-(%d,%d)', [Filename, StartLine, StartColumn, EndLine, EndColumn]);
end;

{ TError }

function TError.GetSeverityString(): string;
begin
  case Severity of
    esHint:    Result := RSSeverityHint;
    esWarning: Result := RSSeverityWarning;
    esError:   Result := RSSeverityError;
    esFatal:   Result := RSSeverityFatal;
  else
    Result := RSSeverityUnknown;
  end;
end;

function TError.ToIDEString(): string;
begin
  // No code (a user @message, L16): no empty code slot in the text
  if Code = '' then
  begin
    if Range.IsEmpty() then
      Result := Format(RSErrorFormatSimpleNoCode, [GetSeverityString(), Message])
    else
      Result := Format(RSErrorFormatWithLocationNoCode,
        [Range.ToPointString(), GetSeverityString(), Message]);
    Exit;
  end;
  if Range.IsEmpty() then
    Result := Format(RSErrorFormatSimple, [GetSeverityString(), Code, Message])
  else
    Result := Format(RSErrorFormatWithLocation, [Range.ToPointString(), GetSeverityString(), Code, Message]);
end;

function TError.ToFullString(): string;
var
  LBuilder: TStringBuilder;
  LI: Integer;
begin
  LBuilder := TStringBuilder.Create();
  try
    LBuilder.AppendLine(ToIDEString());

    for LI := 0 to High(Related) do
    begin
      if Related[LI].Range.IsEmpty() then
        LBuilder.AppendFormat(RSErrorFormatRelatedSimple, [RSSeverityNote, Related[LI].Msg])
      else
        LBuilder.AppendFormat(RSErrorFormatRelatedWithLocation, [Related[LI].Range.ToPointString(), RSSeverityNote, Related[LI].Msg]);
      LBuilder.AppendLine();
    end;

    Result := LBuilder.ToString().TrimRight();
  finally
    LBuilder.Free();
  end;
end;

{ EStdAppException }

constructor EStdAppException.Create(const AError: TError);
begin
  inherited Create(AError.ToFullString());
  ErrorInfo := AError;
end;

{ TErrors }

constructor TErrors.Create();
begin
  inherited;

  FItems := TList<TError>.Create();
  FMaxErrors := DEFAULT_MAX_ERRORS;
  FRaiseOnError := False;
  FPendingIndex := -1;
end;

destructor TErrors.Destroy();
begin
  FItems.Free();

  inherited;
end;

function TErrors.CountErrors(): Integer;
var
  LError: TError;
begin
  Result := 0;
  for LError in FItems do
  begin
    if LError.Severity in [esError, esFatal] then
      Inc(Result);
  end;
end;

procedure TErrors.Add(
  const ARange: TSourceRange;
  const ASeverity: TErrorSeverity;
  const ACode: string;
  const AMessage: string;
  const AUserData: Pointer
);
var
  LError: TError;
  LRange: TSourceRange;
begin
  // A new report means the held one is complete: it goes out first, so the
  // status listener sees reports in the order they were made
  SendPending();

  // Stop adding errors after limit reached (except fatal)
  if (ASeverity = esError) and (CountErrors() >= FMaxErrors) then
    Exit;

  // Keep filename as provided -- caller is responsible for full paths
  LRange := ARange;
  if LRange.Filename <> '' then
    LRange.Filename := LRange.Filename.Replace('\', '/');

  LError.Range := LRange;
  LError.Severity := ASeverity;
  LError.Code := ACode;
  LError.Message := AMessage;
  SetLength(LError.Related, 0);

  FItems.Add(LError);

  // Notify listener: hints and warnings go out through the status listener,
  // each once complete with its notes (AddRelated comes after Add), so it is
  // held here and sent by SendPending; errors and fatals are left for
  // PrintErrors at the end
  if ASeverity in [esHint, esWarning] then
    FPendingIndex := FItems.Count - 1;

  // Raise on error or fatal (unless suppressed). The exception's text is
  // printed as is, so it carries the printed columns (DisplayRange); the
  // stored item keeps its own
  if FRaiseOnError and (ASeverity in [esError, esFatal]) then
  begin
    LError.Range := DisplayRange(LError.Range);
    raise EStdAppException.Create(LError);
  end;
end;

procedure TErrors.Add(
  const ARange: TSourceRange;
  const ASeverity: TErrorSeverity;
  const ACode: string;
  const AMessage: string;
  const AArgs: array of const;
  const AUserData: Pointer
);
begin
  Add(ARange, ASeverity, ACode, Format(AMessage, AArgs), AUserData);
end;

procedure TErrors.Add(
  const AFilename: string;
  const ALine: UInt64;
  const AColumn: UInt64;
  const ASeverity: TErrorSeverity;
  const ACode: string;
  const AMessage: string;
  const AUserData: Pointer
);
var
  LRange: TSourceRange;
begin
  // Clear first: the byte offsets are not set below and must not carry
  // whatever was on the stack
  LRange.Clear();
  LRange.Filename := AFilename;
  LRange.StartLine := ALine;
  LRange.StartColumn := AColumn;
  LRange.EndLine := ALine;
  LRange.EndColumn := AColumn;

  Add(LRange, ASeverity, ACode, AMessage, AUserData);
end;

procedure TErrors.Add(
  const AFilename: string;
  const ALine: UInt64;
  const AColumn: UInt64;
  const ASeverity: TErrorSeverity;
  const ACode: string;
  const AMessage: string;
  const AArgs: array of const;
  const AUserData: Pointer
);
begin
  Add(AFilename, ALine, AColumn, ASeverity, ACode, Format(AMessage, AArgs), AUserData);
end;

procedure TErrors.Add(
  const ASeverity: TErrorSeverity;
  const ACode: string;
  const AMessage: string;
  const AUserData: Pointer
);
var
  LRange: TSourceRange;
begin
  LRange.Clear();
  Add(LRange, ASeverity, ACode, AMessage, AUserData);
end;

procedure TErrors.Add(
  const ASeverity: TErrorSeverity;
  const ACode: string;
  const AMessage: string;
  const AArgs: array of const;
  const AUserData: Pointer
);
begin
  Add(ASeverity, ACode, Format(AMessage, AArgs), AUserData);
end;

procedure TErrors.AddRelated(
  const ARange: TSourceRange;
  const AMessage: string
);
var
  LError: TError;
  LRelated: TErrorRelated;
  LLen: Integer;
begin
  if FItems.Count = 0 then
    Exit;

  LError := FItems[FItems.Count - 1];

  LRelated.Range := ARange;
  LRelated.Msg := AMessage;

  LLen := Length(LError.Related);
  SetLength(LError.Related, LLen + 1);
  LError.Related[LLen] := LRelated;

  FItems[FItems.Count - 1] := LError;
end;

procedure TErrors.AddRelated(
  const ARange: TSourceRange;
  const AMessage: string;
  const AArgs: array of const
);
begin
  AddRelated(ARange, Format(AMessage, AArgs));
end;

function TErrors.HasHints(): Boolean;
var
  LError: TError;
begin
  Result := False;
  for LError in FItems do
  begin
    if LError.Severity = esHint then
      Exit(True);
  end;
end;

function TErrors.HasWarnings(): Boolean;
var
  LError: TError;
begin
  Result := False;
  for LError in FItems do
  begin
    if LError.Severity = esWarning then
      Exit(True);
  end;
end;

function TErrors.HasErrors(): Boolean;
var
  LError: TError;
begin
  Result := False;
  for LError in FItems do
  begin
    if LError.Severity in [esError, esFatal] then
      Exit(True);
  end;
end;

function TErrors.HasFatal(): Boolean;
var
  LError: TError;
begin
  Result := False;
  for LError in FItems do
  begin
    if LError.Severity = esFatal then
      Exit(True);
  end;
end;

function TErrors.Count(): Integer;
begin
  Result := FItems.Count;
end;

function TErrors.ErrorCount(): Integer;
begin
  Result := CountErrors();
end;

function TErrors.WarningCount(): Integer;
var
  LError: TError;
begin
  Result := 0;
  for LError in FItems do
  begin
    if LError.Severity = esWarning then
      Inc(Result);
  end;
end;

function TErrors.ReachedMaxErrors(): Boolean;
begin
  Result := CountErrors() >= FMaxErrors;
end;

procedure TErrors.Clear();
begin
  // A held report was made and kept until now: it is shown before it goes
  SendPending();
  FItems.Clear();
end;

procedure TErrors.TruncateTo(const ACount: Integer);
begin
  while FItems.Count > ACount do
    FItems.Delete(FItems.Count - 1);
  // A rollback (the parser's speculative attempt) withdraws its reports: a
  // held one among them is never shown
  if FPendingIndex >= FItems.Count then
    FPendingIndex := -1;
end;

function TErrors.GetItems(): TList<TError>;
begin
  Result := FItems;
end;

function TErrors.GetMaxErrors(): Integer;
begin
  Result := FMaxErrors;
end;

procedure TErrors.SetMaxErrors(const AMaxErrors: Integer);
begin
  FMaxErrors := AMaxErrors;
end;

procedure TErrors.Status(const AText: string);
begin
  // A status line follows the reports made before it
  SendPending();
  SendStatus(AText);
end;

procedure TErrors.Status(const AText: string; const AArgs: array of const);
begin
  Status(Format(AText, AArgs));
end;

procedure TErrors.Status(const AEnabled: Boolean; const AText: string; const AArgs: array of const);
begin
  if AEnabled then
    Status(Format(AText, AArgs));
end;

function TErrors.GetStatusCallback(): TStatusCallback;
begin
  Result := FStatusCallback.Callback;
end;

procedure TErrors.SetStatusCallback(const ACallback: TStatusCallback; const AUserData: Pointer);
begin
  // A held report belongs to the listener it was made under
  SendPending();
  FStatusCallback.Callback := ACallback;
  FStatusCallback.UserData := AUserData;
end;

procedure TErrors.SetColumnMapper(const AMapper: TColumnMapper);
begin
  FColumnMapper := AMapper;
end;

function TErrors.GetColumnMapper(): TColumnMapper;
begin
  Result := FColumnMapper;
end;

function TErrors.DisplayRange(const ARange: TSourceRange): TSourceRange;
begin
  Result := ARange;
  if (not Assigned(FColumnMapper)) or ARange.IsEmpty() or (ARange.Filename = '') then
    Exit;

  // A column 0 means "no column": it stays 0
  if (ARange.StartLine > 0) and (ARange.StartColumn > 0) then
    Result.StartColumn := FColumnMapper(ARange.Filename, ARange.StartLine, ARange.StartColumn);
  if (ARange.EndLine > 0) and (ARange.EndColumn > 0) then
    Result.EndColumn := FColumnMapper(ARange.Filename, ARange.EndLine, ARange.EndColumn);
end;

function TErrors.FormatError(const AError: TError): string;
var
  LColor: string;
  LLabel: string;
begin
  case AError.Severity of
    esHint:
    begin
      LColor := COLOR_CYAN;
      LLabel := 'HINT';
    end;
    esWarning:
    begin
      LColor := COLOR_YELLOW;
      LLabel := 'WARN';
    end;
    esError:
    begin
      LColor := COLOR_RED;
      LLabel := 'ERROR';
    end;
    esFatal:
    begin
      LColor := COLOR_MAGENTA;
      LLabel := 'FATAL';
    end;
  else
    LColor := COLOR_WHITE;
    LLabel := '?';
  end;

  if AError.Code <> '' then
  begin
    if not AError.Range.IsEmpty() then
      Result := Format(LColor + '[%s] %s %s: %s',
        [LLabel, DisplayRange(AError.Range).ToPointString(), AError.Code, AError.Message])
    else
      Result := Format(LColor + '[%s] %s: %s',
        [LLabel, AError.Code, AError.Message]);
  end
  else
  begin
    if not AError.Range.IsEmpty() then
      Result := Format(LColor + '[%s] %s: %s',
        [LLabel, DisplayRange(AError.Range).ToPointString(), AError.Message])
    else
      Result := Format(LColor + '[%s] %s', [LLabel, AError.Message]);
  end;
end;

function TErrors.FormatNote(const ARelated: TErrorRelated): string;
begin
  // Indented under its item, in the same form ToFullString renders it
  if ARelated.Range.IsEmpty() then
    Result := Format(COLOR_WHITE + RSErrorFormatRelatedSimple, [RSSeverityNote, ARelated.Msg])
  else
    Result := Format(COLOR_WHITE + RSErrorFormatRelatedWithLocation,
      [DisplayRange(ARelated.Range).ToPointString(), RSSeverityNote, ARelated.Msg]);
end;

procedure TErrors.SendStatus(const AText: string);
begin
  if FStatusCallback.IsAssigned() then
    FStatusCallback.Callback(AText, FStatusCallback.UserData);
end;

procedure TErrors.SendPending();
var
  LIndex: Integer;
  LError: TError;
  LI: Integer;
begin
  if FPendingIndex < 0 then
    Exit;

  // Taken before sending: a listener that reports again finds nothing held
  LIndex := FPendingIndex;
  FPendingIndex := -1;
  if LIndex >= FItems.Count then
    Exit;

  LError := FItems[LIndex];
  SendStatus(FormatError(LError));
  for LI := 0 to High(LError.Related) do
    SendStatus(FormatNote(LError.Related[LI]));
end;

procedure TErrors.Flush();
begin
  SendPending();
end;

procedure TErrors.PrintErrors(const ASeverities: TErrorSeverities);
var
  LI: Integer;
  LErr: TError;
  LJ: Integer;
begin
  // The held hint / warning first: it was reported before what prints here
  SendPending();

  if FItems.Count = 0 then
    Exit;

  for LI := 0 to FItems.Count - 1 do
  begin
    LErr := FItems[LI];

    // Skip severities the caller did not ask for (their related notes too)
    if not (LErr.Severity in ASeverities) then
      Continue;

    TConsole.PrintLn(FormatError(LErr));

    // Related notes (AddRelated) explain the item above them
    for LJ := 0 to High(LErr.Related) do
      TConsole.PrintLn(FormatNote(LErr.Related[LJ]));
  end;
end;

{ TBaseObject }

constructor TBaseObject.Create();
begin
  inherited;
  FErrors := nil;
end;

destructor TBaseObject.Destroy();
begin
  inherited;
  FErrors := nil;
end;

function TBaseObject.Dump(const AId: Integer): string;
begin
  Result := '';
end;

procedure TBaseObject.InitConfig();
begin
end;

procedure TBaseObject.LoadConfig(const AFilename: string);
begin
end;

procedure TBaseObject.SaveConfig(const AFilename: string);
begin
end;

procedure TBaseObject.SetErrors(const AErrors: TErrors);
begin
  FErrors := AErrors;
end;

procedure TBaseObject.Status(const AText: string);
begin
  if Assigned(FErrors) then
    FErrors.Status(AText);
end;

procedure TBaseObject.Status(const AText: string; const AArgs: array of const);
begin
  if Assigned(FErrors) then
    FErrors.Status(AText, AArgs);
end;

procedure TBaseObject.Status(const AEnabled: Boolean; const AText: string; const AArgs: array of const);
begin
  if Assigned(FErrors) then
    FErrors.Status(AEnabled, AText, AArgs);
end;


end.

