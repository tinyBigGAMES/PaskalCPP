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
  PaskalCPP.LSP.Outline - a document's symbol tree (textDocument/documentSymbol)

  Reads the AST's declarations as the parser wrote them (plans\done\PLAN-EDITOR.md
  E2.5): the module's imports, declarations, sections and tests of its own
  file, a type's fields / properties / methods / init / done / copy /
  operators / choice values (PLAN-OBJECT O14), a routine's local routines
  and types. Concept adopted from PIXELS.LSP DoSymbolOf / DoDocumentSymbol.

  Dependencies: StdApp.Base, StdApp.Utils, PaskalCPP.AST, PaskalCPP.LSP.Symbols
  Notes:
    - Kinds are LSP SymbolKind values.
    - selectionRange is the name token (NameRange); range is the whole
      declaration (Range).
===============================================================================}

unit PaskalCPP.LSP.Outline;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.AST;

const
  // LSP SymbolKind values used by the outline
  { PC_LSP_SYMBOL_MODULE }
  PC_LSP_SYMBOL_MODULE = 2;
  { PC_LSP_SYMBOL_CLASS }
  PC_LSP_SYMBOL_CLASS = 5;
  { PC_LSP_SYMBOL_METHOD }
  PC_LSP_SYMBOL_METHOD = 6;
  { PC_LSP_SYMBOL_PROPERTY }
  PC_LSP_SYMBOL_PROPERTY = 7;
  { PC_LSP_SYMBOL_FIELD }
  PC_LSP_SYMBOL_FIELD = 8;
  { PC_LSP_SYMBOL_CONSTRUCTOR }
  PC_LSP_SYMBOL_CONSTRUCTOR = 9;
  { PC_LSP_SYMBOL_ENUM }
  PC_LSP_SYMBOL_ENUM = 10;
  { PC_LSP_SYMBOL_INTERFACE }
  PC_LSP_SYMBOL_INTERFACE = 11;
  { PC_LSP_SYMBOL_FUNCTION }
  PC_LSP_SYMBOL_FUNCTION = 12;
  { PC_LSP_SYMBOL_VARIABLE }
  PC_LSP_SYMBOL_VARIABLE = 13;
  { PC_LSP_SYMBOL_CONSTANT }
  PC_LSP_SYMBOL_CONSTANT = 14;
  { PC_LSP_SYMBOL_ENUM_MEMBER }
  PC_LSP_SYMBOL_ENUM_MEMBER = 22;
  { PC_LSP_SYMBOL_STRUCT }
  PC_LSP_SYMBOL_STRUCT = 23;
  { PC_LSP_SYMBOL_EVENT }
  PC_LSP_SYMBOL_EVENT = 24;
  { PC_LSP_SYMBOL_OPERATOR }
  PC_LSP_SYMBOL_OPERATOR = 25;
  { PC_LSP_SYMBOL_TYPE_PARAMETER }
  PC_LSP_SYMBOL_TYPE_PARAMETER = 26;

  { PC_LSP_SYMBOL_UNNAMED }
  // LSP requires a non-empty name
  PC_LSP_SYMBOL_UNNAMED = '(unnamed)';

type
  { TPCLspOutline }
  TPCLspOutline = record
  private
    class function DoInFile(const ARange: TSourceRange; const AFilename: string): Boolean; static;
    class procedure DoAddMembers(const AMembers: TList<TPCMemberItem>;
      const AOut: TList<TPCNode>); static;
    class procedure DoSortByPosition(const AList: TList<TPCNode>); static;
  public
    // The top-level entries of AModule's own file by position: imports,
    // declarations, the initialize / finalize sections, tests
    class function Items(const AModule: TPCModule): TArray<TPCNode>; static;
    // An entry's children, list order: a record / object / interface /
    // overlay's fields, properties and routine members (methods, init,
    // done, copy, operators; an anonymous aggregate's members in its
    // place), a choices type's values, a routine's local routines and
    // types; empty otherwise
    class function ChildrenOf(const ANode: TPCNode): TArray<TPCNode>; static;
    // The entry's LSP SymbolKind
    class function KindOf(const ANode: TPCNode): Integer; static;
    // The entry's name (never empty)
    class function NameOf(const ANode: TPCNode): string; static;
    // A var / const / field's type, a property's index and type, a
    // routine's signature (done: none); '' otherwise
    class function DetailOf(const ANode: TPCNode): string; static;
    // The name token (an import: its range; a test: its name literal); the
    // whole range when the node has none
    class function SelectionOf(const ANode: TPCNode): TSourceRange; static;
  end;

implementation

uses
  System.Generics.Defaults,
  StdApp.Utils,
  PaskalCPP.LSP.Symbols;

{ TPCLspOutline }

class function TPCLspOutline.DoInFile(const ARange: TSourceRange; const AFilename: string): Boolean;
begin
  Result := (ARange.StartLine >= 1) and (ARange.Filename <> '') and (AFilename <> '') and
    TUtils.SamePath(ARange.Filename, AFilename);
end;

class procedure TPCLspOutline.DoAddMembers(const AMembers: TList<TPCMemberItem>;
  const AOut: TList<TPCNode>);
var
  LMember: TPCMemberItem;
begin
  // An anonymous aggregate has no name of its own: its members stand in its
  // place, so a record's outline lists every field it holds. Every member
  // that holds a routine (method, init, done, copy, operator: PLAN-OBJECT
  // O14) is listed as its routine; a property as itself (its accessors are
  // its own, never in a member list)
  for LMember in AMembers do
  begin
    if (LMember is TPCField) or (LMember is TPCPropertyItem) then
      AOut.Add(LMember)
    else if (LMember is TPCRoutineMember) and (TPCRoutineMember(LMember).Routine <> nil) then
      AOut.Add(TPCRoutineMember(LMember).Routine)
    else if LMember is TPCAnonAggregate then
      DoAddMembers(TPCAnonAggregate(LMember).Members, AOut);
  end;
end;

class procedure TPCLspOutline.DoSortByPosition(const AList: TList<TPCNode>);
begin
  AList.Sort(TComparer<TPCNode>.Construct(
    function(const ALeft: TPCNode; const ARight: TPCNode): Integer
    begin
      if ALeft.Range.StartLine < ARight.Range.StartLine then
        Result := -1
      else if ALeft.Range.StartLine > ARight.Range.StartLine then
        Result := 1
      else if ALeft.Range.StartColumn < ARight.Range.StartColumn then
        Result := -1
      else if ALeft.Range.StartColumn > ARight.Range.StartColumn then
        Result := 1
      else
        Result := 0;
    end));
end;

class function TPCLspOutline.Items(const AModule: TPCModule): TArray<TPCNode>;
var
  LList: TList<TPCNode>;
  LImport: TPCImport;
  LStmt: TPCStmt;
  LTest: TPCTest;
begin
  Result := nil;
  if AModule = nil then
    Exit;

  LList := TList<TPCNode>.Create();
  try
    for LImport in AModule.Imports do
      if DoInFile(LImport.Range, AModule.SourceFile) then
        LList.Add(LImport);
    // Directives and verbatim C++ are not declarations
    for LStmt in AModule.Decls do
      if (LStmt is TPCDecl) and DoInFile(LStmt.Range, AModule.SourceFile) then
        LList.Add(LStmt);
    if (AModule.InitRoutine <> nil) and DoInFile(AModule.InitRoutine.Range, AModule.SourceFile) then
      LList.Add(AModule.InitRoutine);
    if (AModule.FinalRoutine <> nil) and DoInFile(AModule.FinalRoutine.Range, AModule.SourceFile) then
      LList.Add(AModule.FinalRoutine);
    for LTest in AModule.Tests do
      if DoInFile(LTest.Range, AModule.SourceFile) then
        LList.Add(LTest);

    DoSortByPosition(LList);
    Result := LList.ToArray();
  finally
    LList.Free();
  end;
end;

class function TPCLspOutline.ChildrenOf(const ANode: TPCNode): TArray<TPCNode>;
var
  LList: TList<TPCNode>;
  LTypeDef: TPCTypeExpr;
  LValue: TPCChoiceValue;
  LStmt: TPCStmt;
begin
  LList := TList<TPCNode>.Create();
  try
    if ANode is TPCTypeDecl then
    begin
      LTypeDef := TPCTypeDecl(ANode).TypeDef;
      if LTypeDef is TPCRecordType then
        DoAddMembers(TPCRecordType(LTypeDef).Members, LList)
      else if LTypeDef is TPCOverlayType then
        DoAddMembers(TPCOverlayType(LTypeDef).Members, LList)
      else if LTypeDef is TPCChoicesType then
      begin
        for LValue in TPCChoicesType(LTypeDef).Values do
          LList.Add(LValue);
      end;
    end
    else if ANode is TPCRoutine then
    begin
      // Local routines and types are places to go; local vars are not
      for LStmt in TPCRoutine(ANode).Decls do
        if (LStmt is TPCRoutine) or (LStmt is TPCTypeDecl) then
          LList.Add(LStmt);
    end;
    Result := LList.ToArray();
  finally
    LList.Free();
  end;
end;

class function TPCLspOutline.KindOf(const ANode: TPCNode): Integer;
var
  LTypeDef: TPCTypeExpr;
begin
  if ANode is TPCImport then
    Result := PC_LSP_SYMBOL_MODULE
  else if ANode is TPCConstDecl then
    Result := PC_LSP_SYMBOL_CONSTANT
  else if ANode is TPCVarDecl then
    Result := PC_LSP_SYMBOL_VARIABLE
  else if ANode is TPCRoutine then
  begin
    // O14: init and copy build an object (LSP's constructor); done runs as
    // one ends (LSP has no destructor kind: a method)
    case TPCRoutine(ANode).RoutineKind of
      rnMethod, rnDone:
        Result := PC_LSP_SYMBOL_METHOD;
      rnInit, rnCopy:
        Result := PC_LSP_SYMBOL_CONSTRUCTOR;
      rnOperator:
        Result := PC_LSP_SYMBOL_OPERATOR;
    else
      Result := PC_LSP_SYMBOL_FUNCTION;
    end;
  end
  else if ANode is TPCField then
    Result := PC_LSP_SYMBOL_FIELD
  else if ANode is TPCPropertyItem then
    Result := PC_LSP_SYMBOL_PROPERTY
  else if ANode is TPCChoiceValue then
    Result := PC_LSP_SYMBOL_ENUM_MEMBER
  else if ANode is TPCTest then
    Result := PC_LSP_SYMBOL_EVENT
  else if ANode is TPCTypeDecl then
  begin
    LTypeDef := TPCTypeDecl(ANode).TypeDef;
    if (LTypeDef is TPCRecordType) and TPCRecordType(LTypeDef).IsInterface then
      Result := PC_LSP_SYMBOL_INTERFACE
    else if (LTypeDef is TPCRecordType) and TPCRecordType(LTypeDef).IsObject then
      Result := PC_LSP_SYMBOL_CLASS
    else if (LTypeDef is TPCRecordType) or (LTypeDef is TPCOverlayType) then
      Result := PC_LSP_SYMBOL_STRUCT
    else if LTypeDef is TPCChoicesType then
      Result := PC_LSP_SYMBOL_ENUM
    else
      Result := PC_LSP_SYMBOL_TYPE_PARAMETER;
  end
  else
    Result := PC_LSP_SYMBOL_VARIABLE;
end;

class function TPCLspOutline.NameOf(const ANode: TPCNode): string;
var
  LTest: TPCTest;
begin
  // A declaring node's name is the one rule (TPCLspSymbols.NameOf); a test
  // is named by its string
  Result := TPCLspSymbols.NameOf(ANode);
  if ANode is TPCTest then
  begin
    // The test's name as its string literal decodes; else as written
    LTest := TPCTest(ANode);
    if (LTest.TestName <> nil) and not LTest.TestName.DecodedValue(Result) then
      Result := LTest.TestName.Text;
  end;
  if Result = '' then
    Result := PC_LSP_SYMBOL_UNNAMED;
end;

class function TPCLspOutline.DetailOf(const ANode: TPCNode): string;
var
  LType: TPCTypeExpr;
begin
  Result := '';
  LType := nil;
  if ANode is TPCVarDecl then
    LType := TPCVarDecl(ANode).TypeExpr
  else if ANode is TPCConstDecl then
    LType := TPCConstDecl(ANode).TypeExpr
  else if ANode is TPCField then
    LType := TPCField(ANode).TypeExpr
  else if (ANode is TPCRoutine) and (TPCRoutine(ANode).RoutineKind = rnDone) then
    // `done;` has no parameter list
    Result := ''
  else if ANode is TPCRoutine then
    Result := TPCLspSymbols.SignatureText(TPCRoutine(ANode))
  else if ANode is TPCPropertyItem then
  begin
    // O14: its type, after its index when it has one (`[const AI: int32]: T`)
    if TPCPropertyItem(ANode).IndexParam <> nil then
      Result := '[' + TPCLspSymbols.ParamText(TPCPropertyItem(ANode).IndexParam) + ']: ';
    LType := TPCPropertyItem(ANode).TypeExpr;
  end;
  if LType <> nil then
    Result := Result + LType.TypeText();
end;

class function TPCLspOutline.SelectionOf(const ANode: TPCNode): TSourceRange;
begin
  if ANode is TPCImport then
    Result := ANode.Range
  else if (ANode is TPCTest) and (TPCTest(ANode).TestName <> nil) then
    Result := TPCTest(ANode).TestName.Range
  else
    Result := TPCLspSymbols.NameRangeOf(ANode);
  if Result.StartLine < 1 then
    Result := ANode.Range;
end;

end.
