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
  PaskalCPP.LSP.Hints - parameter-name inlay hints at call sites

  Reads the analysed AST only (plans\done\PLAN-EDITOR.md E2.4): a call's callee
  is the semantic pass's resolution (TPCCall.ResolvedDecl for one routine,
  TPCName.ResolvedSetMember for an overload set, the callee's ResolvedType
  for a routine value); nothing here resolves a name again. Concept adopted
  from PIXELS.LSP DoInlayHint.

  Dependencies: StdApp.Base, StdApp.Utils, PaskalCPP.AST, PaskalCPP.LSP.Symbols
  Notes:
    - Positions are the frontend's: 1-based line, 1-based UTF-8 byte column.
    - A hint is true whichever routine clang picks: an overload set names a
      position only when every member names it alike (clang picks, not SEM).
    - No hint for a C/C++ callee (rkOpaque), an intrinsic, the variadic
      tail, or an argument already spelled as its parameter.
===============================================================================}

unit PaskalCPP.LSP.Hints;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.AST;

type
  { TPCLspHint }
  // One parameter-name hint: shown before the argument starting at
  // (Line, ByteColumn); HintText is the label ('name:')
  TPCLspHint = record
    Line: UInt64;
    ByteColumn: UInt64;
    HintText: string;
  end;

  { TPCLspHints }
  TPCLspHints = record
  private
    class function DoListNames(const AParams: TList<TPCParam>;
      const ACount: Integer): TArray<string>; static;
    class function DoSetNames(const AMembers: TArray<TPCRoutine>;
      const ACount: Integer): TArray<string>; static;
    class function DoSpelledAs(const AArg: TPCExpr; const AParamName: string): Boolean; static;
  public
    // The parameter name each argument of ACall binds to ('' = no hint);
    // one entry per ACall.Args item
    class function ParamNames(const ACall: TPCCall): TArray<string>; static;
    // Every hint for the calls in AModule's own file whose argument starts
    // on a line in AFirstLine..ALastLine (1-based), by position
    class function CallHints(const AModule: TPCModule; const AFirstLine: UInt64;
      const ALastLine: UInt64): TArray<TPCLspHint>; static;
  end;

implementation

uses
  System.Generics.Defaults,
  StdApp.Utils,
  PaskalCPP.LSP.Symbols;

type
  { TPCLspCallFinder }
  // The EnumChildren walk of CallHints: every TPCCall under a module
  TPCLspCallFinder = class(TBaseObject)
  private
    FCalls: TList<TPCCall>;
    FVisitor: TPCNodeVisitor;
    procedure DoVisit(const ANode: TPCNode);
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Find(const AModule: TPCModule);
    property Calls: TList<TPCCall> read FCalls;
  end;

{ TPCLspCallFinder }

constructor TPCLspCallFinder.Create();
begin
  inherited;

  FCalls := TList<TPCCall>.Create();
  FVisitor := DoVisit;
end;

destructor TPCLspCallFinder.Destroy();
begin
  FCalls.Free();

  inherited;
end;

procedure TPCLspCallFinder.DoVisit(const ANode: TPCNode);
begin
  if ANode is TPCCall then
    FCalls.Add(TPCCall(ANode));
  ANode.EnumChildren(FVisitor);
end;

procedure TPCLspCallFinder.Find(const AModule: TPCModule);
begin
  FCalls.Clear();
  DoVisit(AModule);
end;

{ TPCLspHints }

class function TPCLspHints.DoListNames(const AParams: TList<TPCParam>;
  const ACount: Integer): TArray<string>;
var
  LIndex: Integer;
begin
  // Past the last parameter (a variadic tail, or too many arguments: SEM's
  // report) an argument binds to no name
  SetLength(Result, ACount);
  for LIndex := 0 to ACount - 1 do
  begin
    if (AParams <> nil) and (LIndex < AParams.Count) and (AParams[LIndex] <> nil) then
      Result[LIndex] := AParams[LIndex].ParamName
    else
      Result[LIndex] := '';
  end;
end;

class function TPCLspHints.DoSetNames(const AMembers: TArray<TPCRoutine>;
  const ACount: Integer): TArray<string>;
var
  LIndex: Integer;
  LMember: TPCRoutine;
  LName: string;
  LFirst: Boolean;
  LAgree: Boolean;
begin
  // A position is named only when every member has a parameter there, all
  // spelled alike: then the name is right whichever member clang picks
  SetLength(Result, ACount);
  for LIndex := 0 to ACount - 1 do
  begin
    LName := '';
    LFirst := True;
    LAgree := True;
    for LMember in AMembers do
    begin
      if (LIndex >= LMember.Params.Count) or (LMember.Params[LIndex] = nil) then
      begin
        LAgree := False;
        Break;
      end;
      if LFirst then
      begin
        LName := LMember.Params[LIndex].ParamName;
        LFirst := False;
      end
      else if LMember.Params[LIndex].ParamName <> LName then
      begin
        LAgree := False;
        Break;
      end;
    end;
    if LAgree then
      Result[LIndex] := LName
    else
      Result[LIndex] := '';
  end;
end;

class function TPCLspHints.DoSpelledAs(const AArg: TPCExpr; const AParamName: string): Boolean;
var
  LName: TPCName;
begin
  // `R(a)` for parameter a: the hint would only repeat the argument
  Result := False;
  if (AParamName = '') or not (AArg is TPCName) then
    Exit;
  LName := TPCName(AArg);
  Result := (not LName.HasLeadingScope) and (LName.Parts.Count = 1) and
    (LName.Parts[0].PartText = AParamName);
end;

class function TPCLspHints.ParamNames(const ACall: TPCCall): TArray<string>;
var
  LCount: Integer;
  LIndex: Integer;
  LRoutine: TPCRoutine;
  LCallee: TPCName;
  LMembers: TArray<TPCRoutine>;
  LCanon: TPCTypeExpr;
begin
  LCount := ACall.Args.Count;
  SetLength(Result, LCount);
  for LIndex := 0 to LCount - 1 do
    Result[LIndex] := '';

  // A type argument (size(T), next(T) ...) is an intrinsic's; C/C++ is clang's
  if (ACall.TypeArg <> nil) or (ACall.ResolvedKind = rkOpaque) or
     (ACall.ResolvedKind = rkIntrinsic) then
    Exit;

  if ACall.ResolvedDecl is TPCRoutine then
  begin
    // One routine (SEM bound it); a forward's names are its full routine's
    LRoutine := TPCRoutine(ACall.ResolvedDecl);
    if LRoutine.IsForward and (LRoutine.ResolvedFull <> nil) then
      LRoutine := LRoutine.ResolvedFull;
    Result := DoListNames(LRoutine.Params, LCount);
  end
  else if (ACall.ResolvedDecl = nil) and (ACall.ResolvedKind = rkRoutine) then
  begin
    // An overload set: clang picks. Only a set listed whole (a module
    // frame, at least two members) can tell which names every member shares
    if not (ACall.Callee is TPCName) then
      Exit;
    LCallee := TPCName(ACall.Callee);
    if LCallee.ResolvedSetMember = nil then
      Exit;
    LMembers := TPCLspSymbols.SetMembers(LCallee.ResolvedSetMember);
    if Length(LMembers) < 2 then
      Exit;
    Result := DoSetNames(LMembers, LCount);
  end
  else if (ACall.Callee <> nil) and (ACall.Callee.ResolvedType <> nil) then
  begin
    // A routine value: its routine type's parameter names
    LCanon := ACall.Callee.ResolvedType.Canon();
    if LCanon is TPCRoutineType then
      Result := DoListNames(TPCRoutineType(LCanon).Params, LCount);
  end;

  for LIndex := 0 to LCount - 1 do
  begin
    if DoSpelledAs(ACall.Args[LIndex], Result[LIndex]) then
      Result[LIndex] := '';
  end;
end;

class function TPCLspHints.CallHints(const AModule: TPCModule; const AFirstLine: UInt64;
  const ALastLine: UInt64): TArray<TPCLspHint>;
var
  LFinder: TPCLspCallFinder;
  LHints: TList<TPCLspHint>;
  LCall: TPCCall;
  LNames: TArray<string>;
  LIndex: Integer;
  LArg: TPCExpr;
  LHint: TPCLspHint;
begin
  Result := nil;
  if AModule = nil then
    Exit;

  LFinder := TPCLspCallFinder.Create();
  LHints := TList<TPCLspHint>.Create();
  try
    LFinder.Find(AModule);
    for LCall in LFinder.Calls do
    begin
      LNames := ParamNames(LCall);
      for LIndex := 0 to LCall.Args.Count - 1 do
      begin
        LArg := LCall.Args[LIndex];
        if (LArg = nil) or (LNames[LIndex] = '') then
          Continue;
        // The argument's own file only (an imported module's calls are not
        // this document's), on the requested lines
        if (LArg.Range.StartLine < 1) or (LArg.Range.Filename = '') or
           not TUtils.SamePath(LArg.Range.Filename, AModule.SourceFile) then
          Continue;
        if (LArg.Range.StartLine < AFirstLine) or (LArg.Range.StartLine > ALastLine) then
          Continue;
        LHint.Line := LArg.Range.StartLine;
        LHint.ByteColumn := LArg.Range.StartColumn;
        LHint.HintText := LNames[LIndex] + ':';
        LHints.Add(LHint);
      end;
    end;

    // By position: a nested call's hints lie between its caller's
    LHints.Sort(TComparer<TPCLspHint>.Construct(
      function(const ALeft: TPCLspHint; const ARight: TPCLspHint): Integer
      begin
        if ALeft.Line <> ARight.Line then
        begin
          if ALeft.Line < ARight.Line then
            Result := -1
          else
            Result := 1;
        end
        else if ALeft.ByteColumn < ARight.ByteColumn then
          Result := -1
        else if ALeft.ByteColumn > ARight.ByteColumn then
          Result := 1
        else
          Result := 0;
      end));
    Result := LHints.ToArray();
  finally
    LHints.Free();
    LFinder.Free();
  end;
end;

end.
