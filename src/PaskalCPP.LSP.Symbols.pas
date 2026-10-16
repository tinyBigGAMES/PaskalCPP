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
  PaskalCPP.LSP.Symbols - the use under a position and its declaration

  Reads the analysed AST only: the semantic pass already resolved every
  PaskalCPP use (ResolvedDecl / ResolvedSetMember), so nothing here resolves
  a name again, and a declaration is printed from the AST's own spellings
  (TypeText / ExprText), never from source text (plans\done\PLAN-EDITOR.md E2.2).
  Concept adopted from FreeStrike.LSP.Resolver (ResolveAt, DeclarationText)
  and PIXELS.LSP (DoNodeAt, DoTargetAt).

  Dependencies: StdApp.Base, StdApp.Utils, PaskalCPP.AST
  Notes:
    - Positions are the frontend's: 1-based line, 1-based UTF-8 byte column.
    - A C/C++ name (rkOpaque) has no PaskalCPP declaration: no target.
    - Uses only: a declaration's own name is not a use (its Range is the
      whole declaration).
===============================================================================}

unit PaskalCPP.LSP.Symbols;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.AST;

type
  { TPCLspUse }
  // A use found at a position: the node and, for a TPCName, the index of the
  // part the position lies in (-1 otherwise)
  TPCLspUse = record
    Node: TPCNode;
    PartIndex: Integer;
  end;

  { TPCLspSymbols }
  TPCLspSymbols = record
  private
    class function DoHolds(const ARange: TSourceRange; const ALine: UInt64;
      const AColumn: UInt64): Boolean; static;
    class function DoNormalize(const ANode: TPCNode): TPCNode; static;
    class function DoTypeText(const AType: TPCTypeExpr): string; static;
    // PLAN-OBJECT O14: the words written before a member's declaration
    // (hidden; virtual / override, final; an interface member's are the
    // grammar's and are left out), each followed by a space
    class function DoMemberWords(const AMember: TPCMemberItem; const AIsVirtual: Boolean;
      const AIsOverride: Boolean; const AIsFinal: Boolean): string; static;
    class function DoRoutineText(const ARoutine: TPCRoutine): string; static;
    class function DoAccessorText(const AAccessor: TPCAccessorItem): string; static;
    class function DoPropertyText(const AProperty: TPCPropertyItem): string; static;
    class function DoFieldText(const AField: TPCField): string; static;
  public
    // The innermost use (TPCName part, TPCMember member, TPCNamedType, an
    // import's name, a for's iterator, a declared operator's token, a
    // default property's '[') or declaration name (a declaration,
    // param, field, choice value or module header: its NameRange) in
    // AModule's own file whose range holds the position; Node nil = none
    class function UseAt(const AModule: TPCModule; const ALine: UInt64;
      const AColumn: UInt64): TPCLspUse; static;
    // The declaration a use denotes (a module for a module qualifier or an
    // import, a forward's full declaration, a declaration itself when the
    // position is on its name); nil for a C/C++ name or an unresolved one
    class function TargetOf(const AUse: TPCLspUse): TPCNode; static;
    // The parser's name token of a declaration, param, field, choice value
    // or module (StartLine 0 = none: a module without a header, a node that
    // is not named)
    class function NameRangeOf(const ANode: TPCNode): TSourceRange; static;
    // The name a declaring node declares: an import's module name, else
    // TPCAst.DeclaredName's (a declaration, property, param, field, choice
    // value, module); '' for any other node
    class function NameOf(const ANode: TPCNode): string; static;
    // One line of PaskalCPP for a declaration; '' for a node that is none
    class function DeclText(const ADecl: TPCNode): string; static;
    // A routine's parameter list and return type: `(const a: T; ...): R`
    class function SignatureText(const ARoutine: TPCRoutine): string; static;
    // One parameter as written: `[var | const] AName: T`
    class function ParamText(const AParam: TPCParam): string; static;
    // The raw /// doc comment the parser gave a declaration, field,
    // property or choice value ('' for none or another node)
    class function DocTextOf(const ANode: TPCNode): string; static;
    // Every routine of ARoutine's overload set in its module frame, list
    // order, a forward as its full routine, each once; ARoutine alone in a
    // local frame
    class function SetMembers(const ARoutine: TPCRoutine): TArray<TPCRoutine>; static;
    // The members when AUse names an overload set (ATarget = TargetOf(AUse));
    // empty for every other use
    class function SetOf(const AUse: TPCLspUse; const ATarget: TPCNode): TArray<TPCRoutine>; static;
  end;

implementation

uses
  StdApp.Utils;

type
  { TPCLspUseFinder }
  // The EnumChildren walk of UseAt: a later match is deeper (a child is
  // visited after its parent; siblings do not overlap), so the last one wins
  TPCLspUseFinder = class(TBaseObject)
  private
    FFilename: string;
    FLine: UInt64;
    FColumn: UInt64;
    FFound: TPCLspUse;
    FVisitor: TPCNodeVisitor;
    function DoInFile(const ARange: TSourceRange): Boolean;
    procedure DoVisit(const ANode: TPCNode);
  public
    constructor Create(); override;
    procedure Find(const AModule: TPCModule; const ALine: UInt64; const AColumn: UInt64);
    property Found: TPCLspUse read FFound;
  end;

{ TPCLspUseFinder }

constructor TPCLspUseFinder.Create();
begin
  inherited;

  FVisitor := DoVisit;
  FFound.Node := nil;
  FFound.PartIndex := -1;
end;

function TPCLspUseFinder.DoInFile(const ARange: TSourceRange): Boolean;
begin
  Result := (ARange.Filename <> '') and (FFilename <> '') and
    TUtils.SamePath(ARange.Filename, FFilename);
end;

procedure TPCLspUseFinder.DoVisit(const ANode: TPCNode);
var
  LName: TPCName;
  LMember: TPCMember;
  LIndex: Integer;
  LRange: TSourceRange;
begin
  if ANode is TPCName then
  begin
    LName := TPCName(ANode);
    for LIndex := 0 to LName.Parts.Count - 1 do
      if TPCLspSymbols.DoHolds(LName.Parts[LIndex].Range, FLine, FColumn) and
         DoInFile(LName.Parts[LIndex].Range) then
      begin
        FFound.Node := ANode;
        FFound.PartIndex := LIndex;
        Break;
      end;
  end
  else if ANode is TPCMember then
  begin
    LMember := TPCMember(ANode);
    if (LMember.Member <> nil) and
       TPCLspSymbols.DoHolds(LMember.Member.Range, FLine, FColumn) and
       DoInFile(LMember.Member.Range) then
    begin
      FFound.Node := ANode;
      FFound.PartIndex := -1;
    end;
  end
  else if (ANode is TPCNamedType) or (ANode is TPCImport) then
  begin
    // A named type's range is its name; an import's range is the module name
    if TPCLspSymbols.DoHolds(ANode.Range, FLine, FColumn) and DoInFile(ANode.Range) then
    begin
      FFound.Node := ANode;
      FFound.PartIndex := -1;
    end;
  end
  else if ((ANode is TPCBinary) and (TPCBinary(ANode).ResolvedOperator <> nil)) or
          ((ANode is TPCUnary) and (TPCUnary(ANode).ResolvedOperator <> nil)) then
  begin
    // PLAN-OBJECT O14: a declared operator's use is its operator token
    if ANode is TPCBinary then
      LRange := TPCBinary(ANode).OpRange
    else
      LRange := TPCUnary(ANode).OpRange;
    if TPCLspSymbols.DoHolds(LRange, FLine, FColumn) and DoInFile(LRange) then
    begin
      FFound.Node := ANode;
      FFound.PartIndex := -1;
    end;
  end
  else if (ANode is TPCIndex) and (TPCIndex(ANode).ResolvedProperty <> nil) then
  begin
    // O14: `LO[i]` through a default property names no member: its '['
    LRange := TPCIndex(ANode).OpenRange;
    if TPCLspSymbols.DoHolds(LRange, FLine, FColumn) and DoInFile(LRange) then
    begin
      FFound.Node := ANode;
      FFound.PartIndex := -1;
    end;
  end
  else if ANode is TPCFor then
  begin
    // The iterator is a name token, not a TPCName (it binds ResolvedIterator)
    LRange := TPCFor(ANode).IteratorRange;
    if TPCLspSymbols.DoHolds(LRange, FLine, FColumn) and DoInFile(LRange) then
    begin
      FFound.Node := ANode;
      FFound.PartIndex := -1;
    end;
  end
  else
  begin
    // A declaration's own name (empty for a node that is none)
    LRange := TPCLspSymbols.NameRangeOf(ANode);
    if TPCLspSymbols.DoHolds(LRange, FLine, FColumn) and DoInFile(LRange) then
    begin
      FFound.Node := ANode;
      FFound.PartIndex := -1;
    end;
  end;

  ANode.EnumChildren(FVisitor);
end;

procedure TPCLspUseFinder.Find(const AModule: TPCModule; const ALine: UInt64;
  const AColumn: UInt64);
begin
  FFilename := AModule.SourceFile;
  FLine := ALine;
  FColumn := AColumn;
  FFound.Node := nil;
  FFound.PartIndex := -1;
  DoVisit(AModule);
end;

{ TPCLspSymbols }

class function TPCLspSymbols.DoHolds(const ARange: TSourceRange; const ALine: UInt64;
  const AColumn: UInt64): Boolean;
begin
  // EndColumn names the range's last byte (LSP.Diagnostics reads it so)
  if (ARange.StartLine < 1) or (ARange.EndLine < ARange.StartLine) then
    Exit(False);
  if (ALine < ARange.StartLine) or
     ((ALine = ARange.StartLine) and (AColumn < ARange.StartColumn)) then
    Exit(False);
  if (ALine > ARange.EndLine) or
     ((ALine = ARange.EndLine) and (AColumn > ARange.EndColumn)) then
    Exit(False);
  Result := True;
end;

class function TPCLspSymbols.DoNormalize(const ANode: TPCNode): TPCNode;
begin
  // An import names its module; a forward resolves to its full declaration
  Result := ANode;
  if (ANode is TPCImport) and (TPCImport(ANode).ImportedModule <> nil) then
    Result := TPCImport(ANode).ImportedModule
  else if (ANode is TPCTypeDecl) and TPCTypeDecl(ANode).IsForward and
          (TPCTypeDecl(ANode).ResolvedFull <> nil) then
    Result := TPCTypeDecl(ANode).ResolvedFull
  else if (ANode is TPCRoutine) and TPCRoutine(ANode).IsForward and
          (TPCRoutine(ANode).ResolvedFull <> nil) then
    Result := TPCRoutine(ANode).ResolvedFull;
end;

class function TPCLspSymbols.DoTypeText(const AType: TPCTypeExpr): string;
begin
  if AType = nil then
    Result := ''
  else
    Result := AType.TypeText();
end;

class function TPCLspSymbols.ParamText(const AParam: TPCParam): string;
begin
  case AParam.ParamMode of
    pmVar:
      Result := 'var ';
    pmConst:
      Result := 'const ';
  else
    Result := '';
  end;
  Result := Result + AParam.ParamName + ': ' + DoTypeText(AParam.TypeExpr);
end;

class function TPCLspSymbols.DoMemberWords(const AMember: TPCMemberItem; const AIsVirtual: Boolean;
  const AIsOverride: Boolean; const AIsFinal: Boolean): string;
begin
  Result := '';
  if AMember = nil then
    Exit;
  if AMember.IsHidden then
    Result := 'hidden ';
  // An interface member is virtual (and its methods abstract) by the
  // grammar: a dispatch word written there is PR0034, so none is shown
  if AMember.IsInterfaceMember then
    Exit;
  if AIsVirtual then
    Result := Result + 'virtual '
  else if AIsOverride then
    Result := Result + 'override ';
  if AIsFinal then
    Result := Result + 'final ';
end;

class function TPCLspSymbols.DoRoutineText(const ARoutine: TPCRoutine): string;
var
  LMethod: TPCMethodItem;
begin
  // As the declaration is written: a method with its words, init / copy /
  // operator OP by their DeclName (the word, or 'operator' and the symbol),
  // done without a parameter list (`done;`)
  case ARoutine.RoutineKind of
    rnMethod:
      begin
        if ARoutine.OwnerMember is TPCMethodItem then
        begin
          LMethod := TPCMethodItem(ARoutine.OwnerMember);
          Result := DoMemberWords(LMethod, LMethod.IsVirtual, LMethod.IsOverride, LMethod.IsFinal);
        end
        else
        begin
          LMethod := nil;
          Result := '';
        end;
        if ARoutine.IsConst then
          Result := Result + 'const ';
        Result := Result + 'method ' + ARoutine.DeclName + SignatureText(ARoutine);
        if (LMethod <> nil) and LMethod.IsAbstract and (not LMethod.IsInterfaceMember) then
          Result := Result + '; abstract';
      end;
    rnInit, rnCopy, rnOperator:
      Result := DoMemberWords(ARoutine.OwnerMember, False, False, False) +
        ARoutine.DeclName + SignatureText(ARoutine);
    rnDone:
      Result := DoMemberWords(ARoutine.OwnerMember, False, False, False) + ARoutine.DeclName;
  else
    Result := 'routine ' + ARoutine.DeclName + SignatureText(ARoutine);
  end;
end;

class function TPCLspSymbols.DoAccessorText(const AAccessor: TPCAccessorItem): string;
begin
  // `read FName`, `read` (an inline body: not shown), `hidden write`,
  // `read abstract` (an interface's accessors are abstract by the grammar)
  Result := '';
  if AAccessor.IsHidden and not ((AAccessor.PropertyItem <> nil) and AAccessor.PropertyItem.IsHidden) then
    Result := 'hidden ';
  if AAccessor.IsWrite then
    Result := Result + 'write'
  else
    Result := Result + 'read';
  if AAccessor.IsBinding() then
    Result := Result + ' ' + AAccessor.FieldName
  else if AAccessor.IsAbstract and not ((AAccessor.PropertyItem <> nil) and AAccessor.PropertyItem.IsInterfaceMember) then
    Result := Result + ' abstract';
end;

class function TPCLspSymbols.DoPropertyText(const AProperty: TPCPropertyItem): string;
var
  LParts: TList<string>;
begin
  Result := DoMemberWords(AProperty, AProperty.IsVirtual, AProperty.IsOverride, AProperty.IsFinal) +
    'property ' + AProperty.PropName;
  if AProperty.IndexParam <> nil then
    Result := Result + '[' + ParamText(AProperty.IndexParam) + ']';
  Result := Result + ': ' + DoTypeText(AProperty.TypeExpr);

  LParts := TList<string>.Create();
  try
    if AProperty.ReadItem <> nil then
      LParts.Add(DoAccessorText(AProperty.ReadItem));
    if AProperty.WriteItem <> nil then
      LParts.Add(DoAccessorText(AProperty.WriteItem));
    if AProperty.IsDefault then
      LParts.Add('default');
    if LParts.Count > 0 then
      Result := Result + ' ' + string.Join('; ', LParts.ToArray());
  finally
    LParts.Free();
  end;
end;

class function TPCLspSymbols.DoFieldText(const AField: TPCField): string;
begin
  Result := '';
  if AField.IsHidden then
    Result := 'hidden ';
  if AField.IsEmbed then
    Result := Result + 'embed ';
  Result := Result + AField.FieldName + ': ' + DoTypeText(AField.TypeExpr);
end;

class function TPCLspSymbols.SignatureText(const ARoutine: TPCRoutine): string;
var
  LParts: TList<string>;
  LParam: TPCParam;
begin
  LParts := TList<string>.Create();
  try
    for LParam in ARoutine.Params do
      LParts.Add(ParamText(LParam));
    if ARoutine.IsVariadic then
      LParts.Add('...');
    Result := '(' + string.Join('; ', LParts.ToArray()) + ')';
  finally
    LParts.Free();
  end;

  if ARoutine.ReturnType <> nil then
    Result := Result + ': ' + DoTypeText(ARoutine.ReturnType);
end;

class function TPCLspSymbols.DocTextOf(const ANode: TPCNode): string;
begin
  if ANode is TPCDecl then
    Result := TPCDecl(ANode).DocText
  else if ANode is TPCField then
    Result := TPCField(ANode).DocText
  else if ANode is TPCChoiceValue then
    Result := TPCChoiceValue(ANode).DocText
  else if ANode is TPCPropertyItem then
    Result := TPCPropertyItem(ANode).DocText
  else
    Result := '';
end;

class function TPCLspSymbols.UseAt(const AModule: TPCModule; const ALine: UInt64;
  const AColumn: UInt64): TPCLspUse;
var
  LFinder: TPCLspUseFinder;
begin
  Result.Node := nil;
  Result.PartIndex := -1;
  if AModule = nil then
    Exit;

  LFinder := TPCLspUseFinder.Create();
  try
    LFinder.Find(AModule, ALine, AColumn);
    Result := LFinder.Found;
  finally
    LFinder.Free();
  end;
end;

class function TPCLspSymbols.TargetOf(const AUse: TPCLspUse): TPCNode;
var
  LName: TPCName;
  LDecl: TPCNode;
begin
  Result := nil;
  if AUse.Node is TPCName then
  begin
    LName := TPCName(AUse.Node);
    if LName.ResolvedKind = rkOpaque then
      Exit;
    // A set has no single declaration: one member stands for it
    LDecl := LName.ResolvedDecl;
    if LDecl = nil then
      LDecl := LName.ResolvedSetMember;
    if AUse.PartIndex = LName.Parts.Count - 1 then
      Result := LDecl
    else if (LDecl is TPCDecl) and (TPCDecl(LDecl).DeclModule <> nil) and
            (AUse.PartIndex >= 0) and
            (TPCDecl(LDecl).DeclModule.ModuleName = LName.Parts[AUse.PartIndex].PartText) then
      // Module.Name: the qualifier is the declaration's module
      Result := TPCDecl(LDecl).DeclModule;
  end
  else if AUse.Node is TPCMember then
  begin
    if TPCMember(AUse.Node).ResolvedKind <> rkOpaque then
      Result := TPCMember(AUse.Node).ResolvedDecl;
  end
  else if AUse.Node is TPCNamedType then
  begin
    if TPCNamedType(AUse.Node).ResolvedKind <> rkOpaque then
      Result := TPCNamedType(AUse.Node).ResolvedDecl;
  end
  else if AUse.Node is TPCFor then
    Result := TPCFor(AUse.Node).ResolvedIterator
  else if AUse.Node is TPCBinary then
  begin
    // O14: the declared operator's routine (its NameRange is the symbol)
    if TPCBinary(AUse.Node).ResolvedOperator <> nil then
      Result := TPCBinary(AUse.Node).ResolvedOperator.Routine;
  end
  else if AUse.Node is TPCUnary then
  begin
    if TPCUnary(AUse.Node).ResolvedOperator <> nil then
      Result := TPCUnary(AUse.Node).ResolvedOperator.Routine;
  end
  else if AUse.Node is TPCIndex then
    // O14: the indexed property the index reads or writes (nil = a plain index)
    Result := TPCIndex(AUse.Node).ResolvedProperty
  else if AUse.Node is TPCImport then
    // nil when the import's file was not found (reported by the parser)
    Result := TPCImport(AUse.Node).ImportedModule
  else if AUse.Node <> nil then
  begin
    // UseAt found a declaration by its own name: it denotes itself
    if NameRangeOf(AUse.Node).StartLine > 0 then
      Result := AUse.Node;
  end;

  if Result <> nil then
    Result := DoNormalize(Result);
end;

class function TPCLspSymbols.NameRangeOf(const ANode: TPCNode): TSourceRange;
var
  LName: string;
begin
  // The one declared-name rule (TPCAst.DeclaredName)
  TPCAst.DeclaredName(ANode, LName, Result);
end;

class function TPCLspSymbols.NameOf(const ANode: TPCNode): string;
var
  LRange: TSourceRange;
begin
  // An import names its module; any other node the one declared-name rule
  // (TPCAst.DeclaredName: a second copy here lost the property, O14)
  if ANode is TPCImport then
    Result := TPCImport(ANode).ModuleName
  else if not TPCAst.DeclaredName(ANode, Result, LRange) then
    Result := '';
end;

class function TPCLspSymbols.DeclText(const ADecl: TPCNode): string;
var
  LConst: TPCConstDecl;
  LType: TPCTypeDecl;
  LValue: TPCChoiceValue;
begin
  Result := '';
  if ADecl is TPCVarDecl then
    Result := 'var ' + TPCVarDecl(ADecl).DeclName + ': ' + DoTypeText(TPCVarDecl(ADecl).TypeExpr)
  else if ADecl is TPCConstDecl then
  begin
    LConst := TPCConstDecl(ADecl);
    Result := 'const ' + LConst.DeclName + ': ' + DoTypeText(LConst.TypeExpr);
    if LConst.ValueExpr <> nil then
      Result := Result + ' = ' + LConst.ValueExpr.ExprText();
  end
  else if ADecl is TPCTypeDecl then
  begin
    LType := TPCTypeDecl(ADecl);
    Result := 'type ' + LType.DeclName;
    if LType.TypeDef <> nil then
      Result := Result + ' = ' + DoTypeText(LType.TypeDef);
  end
  else if ADecl is TPCRoutine then
    Result := DoRoutineText(TPCRoutine(ADecl))
  else if ADecl is TPCParam then
    Result := ParamText(TPCParam(ADecl))
  else if ADecl is TPCField then
    Result := DoFieldText(TPCField(ADecl))
  else if ADecl is TPCPropertyItem then
    Result := DoPropertyText(TPCPropertyItem(ADecl))
  else if ADecl is TPCChoiceValue then
  begin
    LValue := TPCChoiceValue(ADecl);
    Result := LValue.ValueName;
    if LValue.ResolvedChoices <> nil then
      Result := Result + ': ' + DoTypeText(LValue.ResolvedChoices);
    if LValue.HasResolvedOrdinal then
      Result := Result + ' = ' + IntToStr(LValue.ResolvedOrdinal);
  end
  else if ADecl is TPCModule then
    Result := 'module ' + TPCModule(ADecl).ModuleName;
end;

class function TPCLspSymbols.SetMembers(const ARoutine: TPCRoutine): TArray<TPCRoutine>;
var
  LFound: TList<TPCDecl>;
  LRoutines: TList<TPCRoutine>;
  LDecl: TPCDecl;
  LModule: TPCModule;
  LMember: TPCRoutine;
  LSelf: TPCRoutine;
begin
  // A forward stands for its full routine: each member once
  LSelf := TPCRoutine(DoNormalize(ARoutine));
  LModule := ARoutine.DeclModule;
  if LModule = nil then
    Exit(TArray<TPCRoutine>.Create(LSelf));

  LFound := TList<TPCDecl>.Create();
  LRoutines := TList<TPCRoutine>.Create();
  try
    TPCDecl.CollectNamed(LModule.Decls, LModule.Decls.Count, ARoutine.DeclName, LFound);
    for LDecl in LFound do
    begin
      if not (LDecl is TPCRoutine) then
        Continue;
      LMember := TPCRoutine(DoNormalize(LDecl));
      if not LRoutines.Contains(LMember) then
        LRoutines.Add(LMember);
    end;
    if not LRoutines.Contains(LSelf) then
      LRoutines.Add(LSelf);
    Result := LRoutines.ToArray();
  finally
    LRoutines.Free();
    LFound.Free();
  end;
end;

class function TPCLspSymbols.SetOf(const AUse: TPCLspUse; const ATarget: TPCNode): TArray<TPCRoutine>;
begin
  // A name resolved to an overload set has no single declaration
  // (ResolvedDecl nil, ResolvedSetMember set): every member; else none
  Result := nil;
  if (ATarget is TPCRoutine) and (AUse.Node is TPCName) and
     (TPCName(AUse.Node).ResolvedDecl = nil) then
    Result := SetMembers(TPCRoutine(ATarget));
end;

end.
