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
  UTestCase.Semantics - semantic pass tests (plans\PLAN-SEMANTICS.md)

  TTestCase suite for TPCSemantics (PaskalCPP.Semantics). Fixtures are real
  files under tests\probe\sem\<area>, written by scripts\zb_sem\gen_<area>.py
  (core: gen_core.py). Each test parses + analyzes a fixture (UTestFrontend
  DoWithSem) and checks the reported codes in order (C1), positions (C4) and
  the resolved AST fields (C3) through a text of every name / type / call.

  Dependencies: StdApp.TestCase, StdApp.Base, StdApp.Resources (RSSemMod*),
    PaskalCPP.Common (bd*, PC_INT_SUFFIXES), PaskalCPP.AST, PaskalCPP.Semantics, UTestFrontend
===============================================================================}

unit UTestCase.Semantics;

interface

uses
  StdApp.TestCase,
  PaskalCPP.Semantics,
  UTestFrontend;

type

  { TPCSemanticsTests }
  TPCSemanticsTests = class(TTestCase)
  private
    procedure DoTestAnalyzeClean();
    procedure DoTestAnalyzePartial();
    procedure DoTestRecoveryRows();
    procedure DoTestOrder();
    procedure DoTestScopes();
    procedure DoTestRecursion();
    procedure DoTestArrow();
    procedure DoTestCascade();
    procedure DoTestBudget();
    procedure DoTestQualified();
    procedure DoTestTransitive();
    procedure DoTestDuplicates();
    procedure DoTestMembers();
    procedure DoTestParent();
    procedure DoTestReserved();
    procedure DoTestBareMember();
    procedure DoTestHidden();
    procedure DoTestImportBare();
    procedure DoTestImportExternal();
    procedure DoTestChoices();
    procedure DoTestTemplates();
    procedure DoTestSystem();
    procedure DoWithCwd(const AName: string; const AClass: TPCSemanticsClass;
      const ACheck: TPCParseCheck);
    procedure DoTestModValues();
    procedure DoTestModBad();
    procedure DoTestModDll();
    procedure DoTestModLib();
    procedure DoTestModLinux();
    procedure DoTestModNoVerInfo();
    procedure DoTestModMessage();
    procedure DoTestModTests();
    procedure DoTestModUnit();
    procedure DoTestModPathFailure();
    procedure DoTestModSourceFile();
    procedure DoTestModCppDefine();
    procedure DoTestTypesLiterals();
    procedure DoTestTypesLiteralsLinux();
    procedure DoTestTypesNames();
    procedure DoTestTypesIntSuffixes();
    procedure DoTestTypesConvert();
    procedure DoTestTypesExprs();
    procedure DoTestFoldWitness();
    procedure DoTestTypesOpaque();
    procedure DoTestDeclsForwards();
    procedure DoTestDeclsLayout();
    procedure DoTestDeclsLayoutLinux();
    procedure DoTestDeclsValues();
    procedure DoTestDeclsRoutines();
    procedure DoTestDeclsDispatch();
    procedure DoTestDeclsLifecycle();
    procedure DoTestDeclsCopy();
    procedure DoTestDeclsOwners();
    procedure DoTestCallsRank();
    procedure DoTestCallsIntrinsics();
    procedure DoTestCallsUpcast();
    procedure DoTestCallsValues();
    procedure DoTestCallsMisaligned();
    procedure DoTestStmtRules();
    procedure DoTestCallsRecords();
    procedure DoTestCallsVarargs();
    procedure DoTestOverloadSetMember();
    procedure DoTestSetBounds();
    procedure DoTestExceptEscapes();
    procedure DoTestCppJumpExcept();
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.TypInfo,
  System.Generics.Collections,
  Winapi.Windows,
  StdApp.Base,
  StdApp.Resources,
  StdApp.Utils,
  PaskalCPP.Common,
  PaskalCPP.AST;

type
  { TPCRaisingSemantics }
  // Drives SM0107: every existence check raises (F-A2-5)
  TPCRaisingSemantics = class(TPCSemantics)
  protected
    function DoPathExists(const APath: string; const ADirectory: Boolean): Boolean; override;
  end;

{ TPCRaisingSemantics }

function TPCRaisingSemantics.DoPathExists(const APath: string; const ADirectory: Boolean): Boolean;
begin
  raise Exception.Create('probe failure');
end;

function DoKindText(const AKind: TPCResolvedKind): string;
begin
  Result := GetEnumName(TypeInfo(TPCResolvedKind), Ord(AKind));
end;

function DoDeclLine(const ADecl: TPCNode): string;
begin
  Result := '';
  if ADecl <> nil then
    Result := '@' + UIntToStr(ADecl.Range.StartLine);
end;

procedure DoNamesWalk(const ANode: TPCNode; const AParts: TStringBuilder);
var
  LText: string;
begin
  // Tree order, methods included: one entry per resolved name form
  if ANode = nil then
    Exit;
  LText := '';
  if (ANode is TPCName) and (TPCName(ANode).Parts.Count = 1) and (TPCName(ANode).Parts[0] <> nil) then
    LText := TPCName(ANode).Parts[0].PartText + '@' + UIntToStr(ANode.Range.StartLine) + ':' +
      UIntToStr(ANode.Range.StartColumn) + '=' + DoKindText(TPCName(ANode).ResolvedKind) +
      DoDeclLine(TPCName(ANode).ResolvedDecl)
  else if ANode is TPCNamedType then
    LText := TPCNamedType(ANode).TypeText() + '@' + UIntToStr(ANode.Range.StartLine) + ':' +
      UIntToStr(ANode.Range.StartColumn) + '=' + DoKindText(TPCNamedType(ANode).ResolvedKind) +
      DoDeclLine(TPCNamedType(ANode).ResolvedDecl)
  else if (ANode is TPCMember) and (TPCMember(ANode).Member <> nil) then
    LText := '.' + TPCMember(ANode).Member.PartText + '@' + UIntToStr(ANode.Range.StartLine) + ':' +
      UIntToStr(ANode.Range.StartColumn) + '=' + DoKindText(TPCMember(ANode).ResolvedKind) +
      DoDeclLine(TPCMember(ANode).ResolvedDecl)
  else if ANode is TPCCall then
  begin
    LText := 'call@' + UIntToStr(ANode.Range.StartLine) + ':' + UIntToStr(ANode.Range.StartColumn) + '=' +
      DoKindText(TPCCall(ANode).ResolvedKind);
    if TPCCall(ANode).IntrinsicKind <> ikNone then
      LText := LText + '/' + GetEnumName(TypeInfo(TPCIntrinsicKind), Ord(TPCCall(ANode).IntrinsicKind));
    LText := LText + DoDeclLine(TPCCall(ANode).ResolvedDecl);
  end;
  if LText <> '' then
  begin
    if AParts.Length > 0 then
      AParts.Append(' ');
    AParts.Append(LText);
  end;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      DoNamesWalk(AChild, AParts);
    end);
end;

function DoNamesText(const AModule: TPCModule): string;
var
  LParts: TStringBuilder;
begin
  LParts := TStringBuilder.Create();
  try
    DoNamesWalk(AModule, LParts);
    Result := LParts.ToString();
  finally
    LParts.Free();
  end;
end;

function DoFirstForLoop(const ANode: TPCNode): TPCFor;
var
  LFound: TPCFor;
begin
  // The first for statement in tree order, nil if none
  if ANode = nil then
    Exit(nil);
  if ANode is TPCFor then
    Exit(TPCFor(ANode));
  LFound := nil;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      if LFound = nil then
        LFound := DoFirstForLoop(AChild);
    end);
  Result := LFound;
end;

function DoNotesText(const AErrors: TErrors): string;
var
  LError: TError;
  LRelated: TErrorRelated;
begin
  // <Code>@<line> + ^<line> per related note (C4 for notes)
  Result := '';
  for LError in AErrors.GetItems() do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + LError.Code + '@' + UIntToStr(LError.Range.StartLine);
    for LRelated in LError.Related do
      Result := Result + '^' + UIntToStr(LRelated.Range.StartLine);
  end;
end;

function DoCoreDir(): string;
begin
  Result := DoProbeDir('sem\core');
end;

function DoReportsText(const AErrors: TErrors): string;
var
  LError: TError;
begin
  // <Code>/<severity>@<line>:<column>, space-joined (C4 + the severity of each)
  Result := '';
  for LError in AErrors.GetItems() do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + LError.Code + '/' +
      GetEnumName(TypeInfo(TErrorSeverity), Ord(LError.Severity)) + '@' +
      UIntToStr(LError.Range.StartLine) + ':' + UIntToStr(LError.Range.StartColumn);
  end;
end;

function DoNoEffectText(const AModule: TPCModule): string;
var
  LDirective: TPCDirective;
begin
  // Every prologue directive's name, '!' when SEM marked it not applied
  Result := '';
  for LDirective in AModule.Directives do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + LDirective.DirectiveName;
    if LDirective.ResolvedNoEffect then
      Result := Result + '!';
  end;
end;

procedure DoTypesWalk(const ANode: TPCNode; const AParts: TStringBuilder);
var
  LExpr: TPCExpr;
  LText: string;
begin
  // Tree order, methods included (the DoNamesWalk walk): every literal, name,
  // member, verbatim expression and special as
  // <ExprText>@<line>=<TypeText or ->[=<value>][~<float>] (C3)
  if ANode = nil then
    Exit;
  if (ANode is TPCLiteral) or (ANode is TPCName) or (ANode is TPCMember) or
    (ANode is TPCVerbatimExpr) or (ANode is TPCSpecial) then
  begin
    LExpr := TPCExpr(ANode);
    LText := LExpr.ExprText() + '@' + UIntToStr(LExpr.Range.StartLine) + '=';
    if LExpr.ResolvedType = nil then
      LText := LText + '-'
    else
      LText := LText + LExpr.ResolvedType.TypeText();
    if LExpr.HasConstValue then
    begin
      if LExpr.ConstIsUnsigned then
        LText := LText + '=' + UIntToStr(LExpr.ConstUInt)
      else
        LText := LText + '=' + IntToStr(LExpr.ConstInt);
    end;
    if LExpr.HasConstFloat then
      LText := LText + '~' + TPCNode.FloatText(LExpr.ConstFloat);
    // a string literal's text holds spaces: ' | ' joins the entries
    if AParts.Length > 0 then
      AParts.Append(' | ');
    AParts.Append(LText);
  end;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      DoTypesWalk(AChild, AParts);
    end);
end;

function DoTypesText(const AModule: TPCModule): string;
var
  LParts: TStringBuilder;
begin
  LParts := TStringBuilder.Create();
  try
    DoTypesWalk(AModule, LParts);
    Result := LParts.ToString();
  finally
    LParts.Free();
  end;
end;

function DoTypesDir(): string;
begin
  Result := DoProbeDir('sem\types');
end;

function DoMessagesText(const AErrors: TErrors): string;
var
  LError: TError;
begin
  // Every report's message in report order, ' | '-joined (a message holds spaces)
  Result := '';
  for LError in AErrors.GetItems() do
  begin
    if Result <> '' then
      Result := Result + ' | ';
    Result := Result + LError.Message;
  end;
end;

function DoNoteTextsText(const AErrors: TErrors): string;
var
  LError: TError;
  LRelated: TErrorRelated;
begin
  // Every note's text, report order then note order, ' | '-joined (the
  // notes' lines are DoNotesText's; PLAN-RECORDS A5)
  Result := '';
  for LError in AErrors.GetItems() do
  begin
    for LRelated in LError.Related do
    begin
      if Result <> '' then
        Result := Result + ' | ';
      Result := Result + LRelated.Msg;
    end;
  end;
end;

function DoInitsText(const AModule: TPCModule): string;
var
  LItem: TPCStmt;
  LExpr: TPCExpr;
  LText: string;
begin
  // Every module var named E<nn>: its initializer's type and folded value, ' | '-joined
  Result := '';
  for LItem in AModule.Decls do
  begin
    if not (LItem is TPCVarDecl) or not TPCVarDecl(LItem).DeclName.StartsWith('E') then
      Continue;
    LExpr := TPCVarDecl(LItem).InitExpr;
    LText := TPCVarDecl(LItem).DeclName + '=';
    if (LExpr = nil) or (LExpr.ResolvedType = nil) then
      LText := LText + '-'
    else
      LText := LText + LExpr.ResolvedType.TypeText();
    if (LExpr <> nil) and LExpr.HasConstValue then
    begin
      if LExpr.ConstIsUnsigned then
        LText := LText + '=' + UIntToStr(LExpr.ConstUInt)
      else
        LText := LText + '=' + IntToStr(LExpr.ConstInt);
    end;
    if (LExpr <> nil) and LExpr.HasConstFloat then
      LText := LText + '~' + TPCNode.FloatText(LExpr.ConstFloat);
    if Result <> '' then
      Result := Result + ' | ';
    Result := Result + LText;
  end;
end;

function DoDeclsDir(): string;
begin
  Result := DoProbeDir('sem\decls');
end;

function DoCallsDir(): string;
begin
  Result := DoProbeDir('sem\calls');
end;

function DoStmtDir(): string;
begin
  Result := DoProbeDir('sem\stmt');
end;

function DoFlowRef(const ANode: TPCNode): string;
begin
  // @<line> of what a statement resolved to; '-' = nothing
  if ANode = nil then
    Result := '-'
  else
    Result := '@' + UIntToStr(ANode.Range.StartLine);
end;

function DoEscapesText(const AEscapes: TPCGuardEscapes): string;
begin
  // A guard's ResolvedEscapes as r / l / s, in that order
  Result := '';
  if geReturn in AEscapes then
    Result := Result + 'r';
  if geLeave in AEscapes then
    Result := Result + 'l';
  if geSkip in AEscapes then
    Result := Result + 's';
end;

procedure DoFlowsWalk(const ANode: TPCNode; const AParts: TStringBuilder);
var
  LText: string;
  LLine: string;
begin
  // Tree order: every for (its iterator), leave / skip (its jump target),
  // return (its routine) and guard (its escapes), as SEM resolved them
  if ANode = nil then
    Exit;
  LText := '';
  LLine := UIntToStr(ANode.Range.StartLine);
  if ANode is TPCFor then
    LText := 'F' + LLine + DoFlowRef(TPCFor(ANode).ResolvedIterator)
  else if ANode is TPCLeave then
    LText := 'J' + LLine + DoFlowRef(TPCLeave(ANode).ResolvedJumpTarget)
  else if ANode is TPCSkip then
    LText := 'J' + LLine + DoFlowRef(TPCSkip(ANode).ResolvedJumpTarget)
  else if ANode is TPCReturn then
    LText := 'R' + LLine + DoFlowRef(TPCReturn(ANode).ResolvedRoutine)
  else if ANode is TPCGuard then
    LText := 'G' + LLine + '=' + DoEscapesText(TPCGuard(ANode).ResolvedEscapes);
  if LText <> '' then
  begin
    if AParts.Length > 0 then
      AParts.Append(' ');
    AParts.Append(LText);
  end;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      DoFlowsWalk(AChild, AParts);
    end);
end;

function DoFlowsText(const AModule: TPCModule): string;
var
  LParts: TStringBuilder;
begin
  LParts := TStringBuilder.Create();
  try
    DoFlowsWalk(AModule, LParts);
    Result := LParts.ToString();
  finally
    LParts.Free();
  end;
end;

procedure DoFieldInitsWalk(const ANode: TPCNode; const AParts: TStringBuilder);
begin
  // Tree order: I<line>@<field line> per record literal field init (its
  // ResolvedField); '-' = none
  if ANode = nil then
    Exit;
  if ANode is TPCFieldInit then
  begin
    if AParts.Length > 0 then
      AParts.Append(' ');
    AParts.Append('I' + UIntToStr(ANode.Range.StartLine) + DoFlowRef(TPCFieldInit(ANode).ResolvedField));
  end;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      DoFieldInitsWalk(AChild, AParts);
    end);
end;

procedure DoVarargsWalk(const ANode: TPCNode; const AParts: TStringBuilder);
var
  LText: string;
begin
  // Tree order: V<line>:<type> per varargs expression; '!' = poisoned,
  // 'void' = reset(), '-' = untyped
  if ANode = nil then
    Exit;
  if ANode is TPCVarargs then
  begin
    LText := 'V' + UIntToStr(ANode.Range.StartLine) + ':';
    if TPCVarargs(ANode).ResolvedType = nil then
      LText := LText + '-'
    else if TPCVarargs(ANode).ResolvedType is TPCErrorType then
      LText := LText + '!'
    else if TPCVarargs(ANode).ResolvedType is TPCVoidType then
      LText := LText + 'void'
    else
      LText := LText + TPCVarargs(ANode).ResolvedType.TypeText();
    if AParts.Length > 0 then
      AParts.Append(' ');
    AParts.Append(LText);
  end;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      DoVarargsWalk(AChild, AParts);
    end);
end;

function DoVarargsText(const AModule: TPCModule): string;
var
  LParts: TStringBuilder;
begin
  LParts := TStringBuilder.Create();
  try
    DoVarargsWalk(AModule, LParts);
    Result := LParts.ToString();
  finally
    LParts.Free();
  end;
end;

function DoFieldInitsText(const AModule: TPCModule): string;
var
  LParts: TStringBuilder;
begin
  LParts := TStringBuilder.Create();
  try
    DoFieldInitsWalk(AModule, LParts);
    Result := LParts.ToString();
  finally
    LParts.Free();
  end;
end;

procedure DoPicksWalk(const ANode: TPCNode; const AParts: TStringBuilder);
var
  LCall: TPCCall;
  LText: string;
begin
  // Tree order (outer call first): L<line>[@<decl line>]:<type> per call;
  // '!' = poisoned, 'void' = a procedure, '-' = untyped (CALLS picks, C3)
  if ANode = nil then
    Exit;
  if ANode is TPCCall then
  begin
    LCall := TPCCall(ANode);
    LText := 'L' + UIntToStr(LCall.Range.StartLine) + DoDeclLine(LCall.ResolvedDecl) + ':';
    if LCall.ResolvedType = nil then
      LText := LText + '-'
    else if LCall.ResolvedType is TPCErrorType then
      LText := LText + '!'
    else if LCall.ResolvedType is TPCVoidType then
      LText := LText + 'void'
    else
      LText := LText + LCall.ResolvedType.TypeText();
    if AParts.Length > 0 then
      AParts.Append(' ');
    AParts.Append(LText);
  end;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      DoPicksWalk(AChild, AParts);
    end);
end;

function DoPicksText(const AModule: TPCModule): string;
var
  LParts: TStringBuilder;
begin
  LParts := TStringBuilder.Create();
  try
    DoPicksWalk(AModule, LParts);
    Result := LParts.ToString();
  finally
    LParts.Free();
  end;
end;

procedure DoSizesWalk(const ANode: TPCNode; const AParts: TStringBuilder);
var
  LCall: TPCCall;
  LText: string;
begin
  // Tree order: S<line>:<column>=<value> per size(T) call; '?' = not folded,
  // '!' = poisoned (CALLS A6b)
  if ANode = nil then
    Exit;
  if (ANode is TPCCall) and (TPCCall(ANode).IntrinsicKind = ikSize) then
  begin
    LCall := TPCCall(ANode);
    LText := 'S' + UIntToStr(LCall.Range.StartLine) + ':' + UIntToStr(LCall.Range.StartColumn) + '=';
    if LCall.ResolvedType is TPCErrorType then
      LText := LText + '!'
    else if LCall.HasConstValue then
      LText := LText + IntToStr(LCall.ConstInt)
    else
      LText := LText + '?';
    if AParts.Length > 0 then
      AParts.Append(' ');
    AParts.Append(LText);
  end;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      DoSizesWalk(AChild, AParts);
    end);
end;

function DoSizesText(const AModule: TPCModule): string;
var
  LParts: TStringBuilder;
begin
  LParts := TStringBuilder.Create();
  try
    DoSizesWalk(AModule, LParts);
    Result := LParts.ToString();
  finally
    LParts.Free();
  end;
end;

procedure DoAddMark(const AParts: TStringBuilder; const ATag: string; const ANode: TPCNode; const AValue: Integer);
begin
  // One mark: <tag><line>:<column>=<value>, space separated
  if AParts.Length > 0 then
    AParts.Append(' ');
  AParts.Append(ATag + UIntToStr(ANode.Range.StartLine) + ':' + UIntToStr(ANode.Range.StartColumn) + '=' +
    IntToStr(AValue));
end;

procedure DoUpcastsWalk(const ANode: TPCNode; const AParts: TStringBuilder);
begin
  // Tree order (PLAN-RECORDS A4): U per TPCExpr.ResolvedUpcastHops > 0, P per
  // TPCMember.ResolvedParentHops > 0, R per call with ResolvedRanksExtensions
  // (value = its candidates), D per TPCCast.ResolvedDowncastHops > 0 (F-A6a)
  if ANode = nil then
    Exit;
  if (ANode is TPCExpr) and (TPCExpr(ANode).ResolvedUpcastHops > 0) then
    DoAddMark(AParts, 'U', ANode, TPCExpr(ANode).ResolvedUpcastHops);
  if (ANode is TPCMember) and (TPCMember(ANode).ResolvedParentHops > 0) then
    DoAddMark(AParts, 'P', ANode, TPCMember(ANode).ResolvedParentHops);
  if (ANode is TPCCall) and TPCCall(ANode).ResolvedRanksExtensions then
    DoAddMark(AParts, 'R', ANode, TPCCall(ANode).ResolvedCandidates.Count);
  if (ANode is TPCCast) and (TPCCast(ANode).ResolvedDowncastHops > 0) then
    DoAddMark(AParts, 'D', ANode, TPCCast(ANode).ResolvedDowncastHops);
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      DoUpcastsWalk(AChild, AParts);
    end);
end;

function DoUpcastsText(const AModule: TPCModule): string;
var
  LParts: TStringBuilder;
begin
  LParts := TStringBuilder.Create();
  try
    DoUpcastsWalk(AModule, LParts);
    Result := LParts.ToString();
  finally
    LParts.Free();
  end;
end;

procedure DoBindsWalk(const ANode: TPCNode; const AParts: TStringBuilder);
begin
  // Tree order (PLAN-RECORDS A5): B per set value SEM bound to one member
  // (ResolvedSetMember set, ResolvedDecl that member): <line>:<col>=<its line>.
  // A call's own callee name is the call's pick (DoBindTarget), not a value:
  // skipped
  if ANode = nil then
    Exit;
  if (ANode is TPCName) and (TPCName(ANode).ResolvedSetMember <> nil) and (TPCName(ANode).ResolvedDecl is TPCRoutine) then
  begin
    if AParts.Length > 0 then
      AParts.Append(' ');
    AParts.Append('B' + UIntToStr(ANode.Range.StartLine) + ':' + UIntToStr(ANode.Range.StartColumn) + '=' +
      UIntToStr(TPCName(ANode).ResolvedDecl.Range.StartLine));
  end;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      if (ANode is TPCCall) and (AChild = TPCCall(ANode).Callee) and (AChild is TPCName) then
        Exit;
      DoBindsWalk(AChild, AParts);
    end);
end;

function DoBindsText(const AModule: TPCModule): string;
var
  LParts: TStringBuilder;
begin
  LParts := TStringBuilder.Create();
  try
    DoBindsWalk(AModule, LParts);
    Result := LParts.ToString();
  finally
    LParts.Free();
  end;
end;

procedure DoCopiesWalk(const ANode: TPCNode; const AParts: TStringBuilder);
begin
  // Tree order (PLAN-RECORDS A8): C<line>:<col> per TPCExpr.ResolvedIsCopied
  if ANode = nil then
    Exit;
  if (ANode is TPCExpr) and TPCExpr(ANode).ResolvedIsCopied then
  begin
    if AParts.Length > 0 then
      AParts.Append(' ');
    AParts.Append('C' + UIntToStr(ANode.Range.StartLine) + ':' + UIntToStr(ANode.Range.StartColumn));
  end;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      DoCopiesWalk(AChild, AParts);
    end);
end;

function DoCopiesText(const AModule: TPCModule): string;
var
  LParts: TStringBuilder;
begin
  LParts := TStringBuilder.Create();
  try
    DoCopiesWalk(AModule, LParts);
    Result := LParts.ToString();
  finally
    LParts.Free();
  end;
end;

function DoOwnerOfMember(const AModule: TPCModule; const AItem: TPCMemberItem): string;
var
  LItem: TPCStmt;
begin
  // The module-level type declaration whose members hold AItem, '?' = none
  Result := '?';
  for LItem in AModule.Decls do
  begin
    if (LItem is TPCTypeDecl) and (TPCTypeDecl(LItem).TypeDef is TPCRecordType) and
      TPCRecordType(TPCTypeDecl(LItem).TypeDef).Members.Contains(AItem) then
      Exit(TPCTypeDecl(LItem).DeclName);
  end;
end;

function DoDispatchFactsText(const AModule: TPCModule): string;
var
  LItem: TPCStmt;
  LRecord: TPCRecordType;
  LText: string;
begin
  // PLAN-OBJECT O3: every module-level object type, declaration order:
  // <name>=P (ResolvedIsPolymorphic) and A:<method> (ResolvedAbstract),
  // comma-joined, '-' for neither; space-joined
  Result := '';
  for LItem in AModule.Decls do
  begin
    if not (LItem is TPCTypeDecl) or not (TPCTypeDecl(LItem).TypeDef is TPCRecordType) then
      Continue;
    LRecord := TPCRecordType(TPCTypeDecl(LItem).TypeDef);
    if not LRecord.IsObject then
      Continue;
    LText := '';
    if LRecord.ResolvedIsPolymorphic then
      LText := 'P';
    if (LRecord.ResolvedAbstract <> nil) and (LRecord.ResolvedAbstract.Routine <> nil) then
    begin
      if LText <> '' then
        LText := LText + ',';
      LText := LText + 'A:' + LRecord.ResolvedAbstract.Routine.DeclName;
    end;
    if LText = '' then
      LText := '-';
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + TPCTypeDecl(LItem).DeclName + '=' + LText;
  end;
end;

function DoOverridesText(const AModule: TPCModule): string;
var
  LItem: TPCStmt;
  LMember: TPCMemberItem;
  LMethod: TPCMethodItem;
begin
  // PLAN-OBJECT O3: every method with ResolvedOverrides, declaration order,
  // as <type>.<method>><the type whose member it overrides>; space-joined
  Result := '';
  for LItem in AModule.Decls do
  begin
    if not (LItem is TPCTypeDecl) or not (TPCTypeDecl(LItem).TypeDef is TPCRecordType) then
      Continue;
    for LMember in TPCRecordType(TPCTypeDecl(LItem).TypeDef).Members do
    begin
      if not (LMember is TPCMethodItem) then
        Continue;
      LMethod := TPCMethodItem(LMember);
      if (LMethod.ResolvedOverrides = nil) or (LMethod.Routine = nil) then
        Continue;
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + TPCTypeDecl(LItem).DeclName + '.' + LMethod.Routine.DeclName + '>' +
        DoOwnerOfMember(AModule, LMethod.ResolvedOverrides);
    end;
  end;
end;

function DoVarInitText(const ADecl: TPCVarDecl): string;
var
  LInit: TPCInitItem;
begin
  // PLAN-OBJECT O4: the init a variable is built with, as <name>><its
  // line> (TPCVarDecl.InitCall.ResolvedInit, else ResolvedInit); '' = none
  Result := '';
  LInit := ADecl.ResolvedInit;
  if ADecl.InitCall <> nil then
    LInit := ADecl.InitCall.ResolvedInit;
  if (LInit <> nil) and (LInit.Routine <> nil) then
    Result := ADecl.DeclName + '>' + UIntToStr(LInit.Routine.Range.StartLine);
end;

function DoLifecycleVarsText(const AModule: TPCModule): string;
var
  LItem: TPCStmt;
  LLocal: TPCStmt;
  LText: string;
begin
  // Module variables, then each module routine's locals, in order
  // (DoVarInitText); space-joined
  Result := '';
  for LItem in AModule.Decls do
  begin
    if not (LItem is TPCVarDecl) then
      Continue;
    LText := DoVarInitText(TPCVarDecl(LItem));
    if LText = '' then
      Continue;
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + LText;
  end;
  for LItem in AModule.Decls do
  begin
    if not (LItem is TPCRoutine) then
      Continue;
    for LLocal in TPCRoutine(LItem).Decls do
    begin
      if not (LLocal is TPCVarDecl) then
        Continue;
      LText := DoVarInitText(TPCVarDecl(LLocal));
      if LText = '' then
        Continue;
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + LText;
    end;
  end;
end;

function DoLeadsText(const AModule: TPCModule): string;
var
  LItem: TPCStmt;
  LMember: TPCMemberItem;
  LInit: TPCInitItem;
begin
  // PLAN-OBJECT O4: every init with leading calls, declaration order, as
  // L<its line>:<TPCInitItem.ResolvedLeadCount>; space-joined
  Result := '';
  for LItem in AModule.Decls do
  begin
    if not (LItem is TPCTypeDecl) or not (TPCTypeDecl(LItem).TypeDef is TPCRecordType) then
      Continue;
    for LMember in TPCRecordType(TPCTypeDecl(LItem).TypeDef).Members do
    begin
      if not (LMember is TPCInitItem) then
        Continue;
      LInit := TPCInitItem(LMember);
      if (LInit.ResolvedLeadCount = 0) or (LInit.Routine = nil) then
        Continue;
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + 'L' + UIntToStr(LInit.Routine.Range.StartLine) + ':' + IntToStr(LInit.ResolvedLeadCount);
    end;
  end;
end;

function DoOrdinalsText(const AModule: TPCModule): string;
var
  LItem: TPCStmt;
  LValue: TPCChoiceValue;
  LText: string;
begin
  // Every choice value of every module-level choices type, declaration order:
  // <name>=<ResolvedOrdinal>, '-' when HasResolvedOrdinal is False; space-joined
  Result := '';
  for LItem in AModule.Decls do
  begin
    if not (LItem is TPCTypeDecl) or not (TPCTypeDecl(LItem).TypeDef is TPCChoicesType) then
      Continue;
    for LValue in TPCChoicesType(TPCTypeDecl(LItem).TypeDef).Values do
    begin
      if LValue = nil then
        Continue;
      LText := LValue.ValueName + '=';
      if LValue.HasResolvedOrdinal then
        LText := LText + IntToStr(LValue.ResolvedOrdinal)
      else
        LText := LText + '-';
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + LText;
    end;
  end;
end;

{ TPCSemanticsTests }

constructor TPCSemanticsTests.Create();
begin
  inherited;

  Title := 'Semantics';
  RegisterTest('core.analyze_clean', DoTestAnalyzeClean);
  RegisterTest('core.analyze_partial', DoTestAnalyzePartial);
  RegisterTest('core.recovery_rows', DoTestRecoveryRows);
  RegisterTest('core.order', DoTestOrder);
  RegisterTest('core.scopes', DoTestScopes);
  RegisterTest('core.recursion', DoTestRecursion);
  RegisterTest('core.arrow', DoTestArrow);
  RegisterTest('core.cascade', DoTestCascade);
  RegisterTest('core.budget', DoTestBudget);
  RegisterTest('core.qualified', DoTestQualified);
  RegisterTest('core.transitive', DoTestTransitive);
  RegisterTest('core.duplicates', DoTestDuplicates);
  RegisterTest('core.members', DoTestMembers);
  RegisterTest('core.parent', DoTestParent);
  RegisterTest('core.reserved', DoTestReserved);
  RegisterTest('core.bare_member', DoTestBareMember);
  RegisterTest('core.hidden', DoTestHidden);
  RegisterTest('core.import_bare', DoTestImportBare);
  RegisterTest('core.import_external', DoTestImportExternal);
  RegisterTest('core.choices', DoTestChoices);
  RegisterTest('core.templates', DoTestTemplates);
  RegisterTest('core.system', DoTestSystem);
  RegisterTest('mod.values', DoTestModValues);
  RegisterTest('mod.bad', DoTestModBad);
  RegisterTest('mod.dll', DoTestModDll);
  RegisterTest('mod.lib', DoTestModLib);
  RegisterTest('mod.linux', DoTestModLinux);
  RegisterTest('mod.noverinfo', DoTestModNoVerInfo);
  RegisterTest('mod.message', DoTestModMessage);
  RegisterTest('mod.tests', DoTestModTests);
  RegisterTest('mod.unit', DoTestModUnit);
  RegisterTest('mod.path_failure', DoTestModPathFailure);
  RegisterTest('mod.sourcefile', DoTestModSourceFile);
  RegisterTest('mod.cppdefine', DoTestModCppDefine);
  RegisterTest('types.literals', DoTestTypesLiterals);
  RegisterTest('types.literals_linux', DoTestTypesLiteralsLinux);
  RegisterTest('types.names', DoTestTypesNames);
  RegisterTest('types.int_suffixes', DoTestTypesIntSuffixes);
  RegisterTest('types.convert', DoTestTypesConvert);
  RegisterTest('types.exprs', DoTestTypesExprs);
  RegisterTest('types.fold_witness', DoTestFoldWitness);
  RegisterTest('types.opaque_nested', DoTestTypesOpaque);
  RegisterTest('decls.forwards', DoTestDeclsForwards);
  RegisterTest('decls.layout', DoTestDeclsLayout);
  RegisterTest('decls.layout_linux', DoTestDeclsLayoutLinux);
  RegisterTest('decls.values', DoTestDeclsValues);
  RegisterTest('decls.routines', DoTestDeclsRoutines);
  RegisterTest('decls.dispatch', DoTestDeclsDispatch);
  RegisterTest('decls.lifecycle', DoTestDeclsLifecycle);
  RegisterTest('decls.copy', DoTestDeclsCopy);
  RegisterTest('decls.owners', DoTestDeclsOwners);
  RegisterTest('calls.rank', DoTestCallsRank);
  RegisterTest('calls.intrinsics', DoTestCallsIntrinsics);
  RegisterTest('calls.upcast', DoTestCallsUpcast);
  RegisterTest('calls.values', DoTestCallsValues);
  RegisterTest('calls.misaligned', DoTestCallsMisaligned);
  RegisterTest('stmt.rules', DoTestStmtRules);
  RegisterTest('calls.records', DoTestCallsRecords);
  RegisterTest('calls.varargs', DoTestCallsVarargs);
  RegisterTest('emit.overload_set_member', DoTestOverloadSetMember);
  RegisterTest('emit.set_bounds', DoTestSetBounds);
  RegisterTest('emit.except_escapes', DoTestExceptEscapes);
  RegisterTest('emit.cpp_jump_except', DoTestCppJumpExcept);
end;

procedure TPCSemanticsTests.Run();
begin
  inherited;
end;

procedure TPCSemanticsTests.DoTestAnalyzeClean();
begin
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc01_main.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = '', 'analyze_clean: codes ' + DoCodes(AErrors));
      Check((AAst.ModuleCount() = 2) and (AAst.ModuleAt(0).ModuleName = 'sc_u1'),
        'analyze_clean: the import is analyzed first (dependency order)');
    end);
end;

procedure TPCSemanticsTests.DoTestAnalyzePartial();
begin
  // A recovered tree: every parser error once, nothing added, no raise
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc02_partial.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'PR0001,PR0001', 'analyze_partial: codes ' + DoCodes(AErrors));
    end);
  // The default budget (1, the CLI sets none): SEM runs on the recovered tree
  // (no phase gate, PLAN-RECOVERY A10) yet the build prints exactly the
  // parser's report (A11 T4, D-R5-2)
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc02_partial.pcpp'), 1,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'PR0001',
        'analyze_partial: the default budget prints the parser''s report alone (got ' +
        DoCodes(AErrors) + ')');
    end);
end;

procedure DoCollectResolved(const ANode: TPCNode; const ANames: TList<string>);
var
  LNames: TList<string>;
  LText: string;
begin
  // Every name / member use SEM resolved to a node, by its last part
  if ANode = nil then
    Exit;
  LText := '';
  if (ANode is TPCName) and (TPCName(ANode).ResolvedDecl <> nil) and
    (TPCName(ANode).Parts.Count > 0) then
    LText := TPCName(ANode).Parts[TPCName(ANode).Parts.Count - 1].PartText
  else if (ANode is TPCMember) and (TPCMember(ANode).ResolvedDecl <> nil) and
    (TPCMember(ANode).Member <> nil) then
    LText := TPCMember(ANode).Member.PartText;
  if (LText <> '') and (not ANames.Contains(LText)) then
    ANames.Add(LText);
  LNames := ANames;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      DoCollectResolved(AChild, LNames);
    end);
end;

function DoResolvedNames(const AModule: TPCModule): string;
var
  LNames: TList<string>;
begin
  // The names a recovery row expects resolved, sorted, comma joined
  LNames := TList<string>.Create();
  try
    DoCollectResolved(AModule, LNames);
    LNames.Sort();
    Result := string.Join(',', LNames.ToArray());
  finally
    LNames.Free();
  end;
end;

procedure TPCSemanticsTests.DoTestRecoveryRows();
var
  LDir: string;
  LLines: TArray<string>;
  LLine: string;
  LParts: TArray<string>;
  LCodes: string;
  LNames: string;
  LReports: string;
begin
  // The PLAN-RECOVERY semantics rows (scripts\zb_ed\gen_recovery.py): parse
  // and analyze; the codes exactly as stated (the parser's report alone: SEM
  // is silent on recovered nodes) and every use the row names resolved
  LDir := DoProbeDir('sem\recovery');
  try
    LLines := TFile.ReadAllLines(TPath.Combine(LDir, 'expected.txt'), TEncoding.UTF8);
  except
    on E: Exception do
    begin
      Check(False, 'recovery_rows: expected.txt cannot be read: ' + E.Message);
      Exit;
    end;
  end;
  for LLine in LLines do
  begin
    if LLine = '' then
      Continue;
    LParts := LLine.Split(['|']);
    if Length(LParts) <> 3 then
    begin
      Check(False, 'recovery_rows: a malformed row: ' + LLine);
      Continue;
    end;
    LCodes := '';
    LNames := '';
    LReports := '';
    DoWithSem(TPath.Combine(LDir, LParts[0] + '.pcpp'), 100,
      procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
      begin
        LCodes := DoCodes(AErrors);
        LReports := DoReports(AErrors);
        LNames := DoResolvedNames(AModule);
      end);
    Check((LCodes = LParts[1]) and (LNames = LParts[2]),
      'recovery_rows: ' + LParts[0] + ' gives ' + LParts[1] + ' | ' + LParts[2] +
      ' (got ' + LCodes + ' | ' + LNames + '; reports: ' + LReports + ')');
  end;
end;

procedure TPCSemanticsTests.DoTestOrder();
begin
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc03_order.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LForward: TPCTypeDecl;
    begin
      Check(DoCodes(AErrors) = 'SM0002,SM0002,SM0002,SM0003,SM0001,SM0002,SM0013',
        'order: codes ' + DoCodes(AErrors));
      Check(DoNamesText(AModule) = 'B@3:14=rkNone D@6:14=rkNone TB@9:8=rkNone TC@12:8=rkNone TD@17:15=rkType@14 E@20:14=rkNone call@23:10=rkNone H@23:10=rkNone AX@23:12=rkParam@21 AX@27:' +
        '10=rkParam@25 call@32:10=rkRoutine@29 K@32:10=rkRoutine@29 AX@32:12=rkParam@30 Q@32:18=rkOpaque call@32:22=rkOpaque strlen@32:22=rkOpaque AX@36:10=rkP' +
        'aram@34 G@39:6=rkNone', 'order: names ' + DoNamesText(AModule));
      LForward := TPCTypeDecl(AModule.Decls[7]);
      Check(LForward.IsForward and (LForward.ResolvedFull = AModule.Decls[8]),
        'order: the forward TD links the full TD');
      Check((AErrors.GetItems()[0].Range.StartLine = 3) and (AErrors.GetItems()[0].Range.StartColumn = 14),
        'order: the first SM0002 sits on B (C4)');
    end);
end;

procedure TPCSemanticsTests.DoTestScopes();
begin
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc04_scopes.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = '', 'scopes: codes ' + DoCodes(AErrors));
      Check(DoNamesText(AModule) = 'AX@8:3=rkParam@4 N@8:9=rkOpaque AX@9:6=rkParam@4 AX@12:5=rkParam@4 X@12:11=rkVar@10 R@16:9=rkOpaque AX@17:9=rkParam@4 AX@20:3=rkParam@4 M@20:9=rkOpaqu' +
        'e X@21:10=rkVar@6 X@24:3=rkVar@3', 'scopes: names ' + DoNamesText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestRecursion();
begin
  // A routine is visible inside its own body (its item counts itself), at the
  // body's top level and inside a nested statement list
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc13_recurse.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = '', 'recursion: codes ' + DoCodes(AErrors));
      Check(DoNamesText(AModule) = 'AN@4:6=rkParam@2 call@5:12=rkRoutine@2 R@5:12=rkRoutine@2 AN@5:14=rkParam@2 ' +
        'call@7:10=rkRoutine@2 R@7:10=rkRoutine@2', 'recursion: names ' + DoNamesText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestArrow();
begin
  // A field through '->' on a typed pointer: the record MemberRecord gives
  // (TPCScopes, shared with completion)
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc14_arrow.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = '', 'arrow: codes ' + DoCodes(AErrors));
      Check(DoNamesText(AModule) = 'TPoint@6:28=rkType@3 .X@8:10=rkField@4 AP@8:10=rkParam@6',
        'arrow: names ' + DoNamesText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestCascade();
begin
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc05_cascade.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'SM0002', 'cascade: one report for one broken thing: ' + DoCodes(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestBudget();
begin
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc03_order.pcpp'), 1,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'SM0002', 'budget: the walk stops at the budget: ' + DoCodes(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestQualified();
begin
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc06_qual.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'SM0006,SM0005,SM0008,SM0007,SM0013,SM0010,SM0014,SM0007',
        'qualified: codes ' + DoCodes(AErrors));
      Check(DoNamesText(AModule) = '.G@4:14=rkVar@7 sc_u2@4:14=rkModule@2 .H@5:14=rkNone sc_u2@5:14=rkModule@2 .Nope@6:14=rkNone sc_u2@6:14=rkModule@2 sc_u2.TPt@7:6=rkType@3 sc_u2.TPt.X@' +
        '8:6=rkNone Zed.TPt@9:7=rkNone call@10:15=rkRoutine@10 .F@10:15=rkRoutine@10 sc_u2@10:15=rkModule@2 sc_u2.G@11:7=rkNone sc_u2.TCol@12:7=rkType@15 .Gree' +
        'n@12:20=rkChoiceValue@15 .TCol@12:20=rkType@15 sc_u2@12:20=rkModule@2 sc_u2.TCol@13:7=rkType@15 .Blue@13:20=rkNone .TCol@13:20=rkType@15 sc_u2@13:20=r' +
        'kModule@2 .G@14:15=rkNone sc_u2@14:15=rkModule@2 sc_u2.TPt@18:6=rkNone', 'qualified: names ' + DoNamesText(AModule));
      Check((AErrors.GetItems()[0].Range.StartLine = 5) and (AErrors.GetItems()[0].Range.StartColumn = 14),
        'qualified: the SM0006 sits on sc_u2.H (C4)');
    end);
end;

procedure TPCSemanticsTests.DoTestTransitive();
begin
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc07_trans.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'SM0007', 'transitive: codes ' + DoCodes(AErrors));
      Check(DoNamesText(AModule) = '.G@4:14=rkNone sc_u2@4:14=rkOpaque sc_u2.TPt@5:6=rkNone', 'transitive: names ' + DoNamesText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestDuplicates();
begin
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc08_dup.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'SM0004,SM0004,SM0004,SM0004,SM0004,SM0004,SM0004,SM0004,SM0004,SM0004',
        'duplicates: codes ' + DoCodes(AErrors));
      Check(DoNotesText(AErrors) = 'SM0004@4^2 SM0004@6^5 SM0004@7^5 SM0004@16^15 SM0004@17^17 SM0004@20^17 SM0004@22^19 SM0004@35^34 SM0004@42^40 SM0004@45^45', 'duplicates: notes ' + DoNotesText(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestMembers();
begin
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc09_members.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'SM0012,SM0011', 'members: codes ' + DoCodes(AErrors));
      // PLAN-OBJECT D9: members through self. (15-16), as parent. (21)
      Check(DoNamesText(AModule) = 'TBase@11:17=rkType@5 call@15:7=rkRoutine@7 .Show@15:7=rkRoutine@7 .N@16:14=rkField@12 .B@16:23=rkField@6 .N@20:7=rkField@12 N@20:17=rkParam@18 call@21:7=rkRo' +
        'utine@7 .Show@21:7=rkRoutine@7 TObj@23:21=rkType@11 TObj@25:10=rkType@11 L@27:14=rkVar@25 call@33:7=rkNone .P@33:7=rkNone .N@38:3=rkNone', 'members: names ' + DoNamesText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestParent();
begin
  // parent is a member qualifier (type_object): parent.Z is the inherited field
  // itself, assigned and addressed as self.Z is (lines 15-17 report nothing);
  // parent as a value (21), its address (25) or through '->' (29) is SM0016
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc15_parent.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) = 'SM0016/esError@21:14 SM0016/esError@25:25 SM0016/esError@29:14',
        'parent: reports ' + DoReportsText(AErrors));
      Check(DoReports(AErrors) = 'SM0016 21: ''parent'' reaches the parent''s members: write parent.<member>; ' +
        'SM0016 25: ''parent'' reaches the parent''s members: write parent.<member>; ' +
        'SM0016 29: ''parent'' reaches the parent''s members: write parent.<member>',
        'parent: messages ' + DoReports(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestReserved();
begin
  // PLAN-RECORDS A9 (M11): every PaskalCPP declaration named pcpp_... is
  // SM0017 at its name, in source order (a routine before its parameter and
  // local); Pcpp_G (line 9) is free, the C++ struct (line 2) is clang's, a
  // use of a reported name resolves (line 18)
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc16_reserved.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) = 'SM0017/esError@4:3 SM0017/esError@6:3 SM0017/esError@8:5 ' +
        'SM0017/esError@11:16 SM0017/esError@13:3 SM0017/esError@14:9 SM0017/esError@14:22 SM0017/esError@16:3',
        'reserved: reports ' + DoReportsText(AErrors));
      Check(DoReports(AErrors) =
        'SM0017 4: ''pcpp_K'': names starting with pcpp_ are reserved for the compiler; ' +
        'SM0017 6: ''pcpp_T'': names starting with pcpp_ are reserved for the compiler; ' +
        'SM0017 8: ''pcpp_F'': names starting with pcpp_ are reserved for the compiler; ' +
        'SM0017 11: ''pcpp_cA'': names starting with pcpp_ are reserved for the compiler; ' +
        'SM0017 13: ''pcpp_V'': names starting with pcpp_ are reserved for the compiler; ' +
        'SM0017 14: ''pcpp_R'': names starting with pcpp_ are reserved for the compiler; ' +
        'SM0017 14: ''pcpp_A'': names starting with pcpp_ are reserved for the compiler; ' +
        'SM0017 16: ''pcpp_L'': names starting with pcpp_ are reserved for the compiler',
        'reserved: messages ' + DoReports(AErrors));
    end);
  DoWithSem(TPath.Combine(DoCoreDir(), 'pcpp_sc16m.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) = 'SM0017/esError@1:12', 'reserved: a module name ' + DoReportsText(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestBareMember();
begin
  // PLAN-OBJECT D9: a member named bare in a method is SM0018 at the name:
  // an own field the module also declares (18), a parent method (19) and
  // field (20), a for iterator (21), the method itself (24); a module var,
  // self.X (23) and a parameter named like a field (28) report nothing
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc17_bare.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) = 'SM0018/esError@18:7 SM0018/esError@19:7 SM0018/esError@20:13 ' +
        'SM0018/esError@21:7 SM0018/esError@24:14', 'bare member: reports ' + DoReportsText(AErrors));
      Check(DoReports(AErrors) = 'SM0018 18: ''X'' is a member of ''TObj'': write self.X; ' +
        'SM0018 19: ''BM'' is a member of ''TObj'': write self.BM; ' +
        'SM0018 20: ''BF'' is a member of ''TObj'': write self.BF; ' +
        'SM0018 21: ''X'' is a member of ''TObj'': write self.X; ' +
        'SM0018 24: ''M'' is a member of ''TObj'': write self.M',
        'bare member: messages ' + DoReports(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestHidden();
begin
  // PLAN-OBJECT D10, C++'s protected rule: TBase's methods reach a hidden
  // member through any TBase value (12); TObj's through self, parent. and a
  // TObj value (18), not through a TBase value (18:59); a routine never (23:
  // '.' on a field and a method, '->' on a field)
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc18_hidden.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) = 'SM0019/esError@18:59 SM0019/esError@23:13 SM0019/esError@23:21 ' +
        'SM0019/esError@23:41', 'hidden: reports ' + DoReportsText(AErrors));
      Check(DoReports(AErrors) =
        'SM0019 18: ''HF'' is hidden in ''TBase'': a method of ''TObj'' reaches it only through self or a ''TObj'' value; ' +
        'SM0019 23: ''HF'' is hidden in ''TBase'': only the methods of ''TBase'' and of its descendants reach it; ' +
        'SM0019 23: ''HM'' is hidden in ''TBase'': only the methods of ''TBase'' and of its descendants reach it; ' +
        'SM0019 23: ''HF'' is hidden in ''TBase'': only the methods of ''TBase'' and of its descendants reach it',
        'hidden: messages ' + DoReports(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestImportBare();
begin
  // PLAN-IMPORT-RESOLUTION: a bare name through sc19's own imports. KOne /
  // TIb / Lone / Over / GI: one unit (sc_ib1). KBoth (7) and TSame (9): two
  // units, SM0020 at the use, a note at each unit's declaration (sc_ib1 4 /
  // 13, sc_ib2 4 / 6). KOwn: the module's own const (4); KLocal: R's local
  // (20); len: the intrinsic, not sc_ib1's routine; G (sc_ib2's own import's)
  // and CppOnly: opaque; sc_ib1.KBoth: qualified, as before
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc19_bare.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LFor: TPCFor;
    begin
      Check(DoReportsText(AErrors) = 'SM0020/esError@7:14 SM0020/esError@9:6',
        'import bare: reports ' + DoReportsText(AErrors));
      Check(DoReports(AErrors) =
        'SM0020 7: ''KBoth'' is in ''sc_ib1'' and ''sc_ib2'': write sc_ib1.KBoth or sc_ib2.KBoth; ' +
        'SM0020 9: ''TSame'' is in ''sc_ib1'' and ''sc_ib2'': write sc_ib1.TSame or sc_ib2.TSame',
        'import bare: messages ' + DoReports(AErrors));
      Check(DoNotesText(AErrors) = 'SM0020@7^4^4 SM0020@9^13^6', 'import bare: notes ' + DoNotesText(AErrors));
      Check(DoNamesText(AModule) =
        'KOne@6:14=rkConst@3 KBoth@7:14=rkNone TIb@8:6=rkType@10 TSame@9:6=rkNone ' +
        // Over(true): only Over(bool) (24) takes it, so the set binds as that lone routine
        'call@10:14=rkRoutine@16 Lone@10:14=rkRoutine@16 call@11:14=rkRoutine@24 Over@11:14=rkRoutine@24 ' +
        'KOwn@12:14=rkConst@4 G@13:14=rkOpaque CppOnly@14:14=rkOpaque ' +
        'call@16:14=rkIntrinsic/ikLen len@16:14=rkIntrinsic L@16:18=rkVar@15 ' +
        '.KBoth@17:14=rkConst@4 sc_ib1@17:14=rkModule@2 KLocal@22:10=rkVar@20',
        'import bare: names ' + DoNamesText(AModule));
      // The for iterator binds to sc_ib1's exported var (declared on its line 8)
      LFor := DoFirstForLoop(AModule);
      Check((LFor <> nil) and (LFor.ResolvedIterator is TPCVarDecl) and
        (TPCVarDecl(LFor.ResolvedIterator).DeclName = 'GI') and (LFor.ResolvedIterator.Range.StartLine = 8),
        'import bare: for GI binds to sc_ib1.GI');
    end);
end;

procedure TPCSemanticsTests.DoTestImportExternal();
begin
  // PLAN-IMPORT-RESOLUTION, the external clause: KLib (one unit, sc_ib1)
  // names the library "m"; KBoth (two units) is SM0020 at the library's name
  // (4:39) and nothing more (no SM0326 after it)
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc20_extlib.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LStmt: TPCStmt;
      LLib: string;
    begin
      Check(DoReportsText(AErrors) = 'SM0020/esError@4:39', 'import external: reports ' + DoReportsText(AErrors));
      LLib := '?';
      for LStmt in AModule.Decls do
      begin
        if (LStmt is TPCRoutine) and (TPCRoutine(LStmt).DeclName = 'ExtA') then
          LLib := TPCRoutine(LStmt).ExternalClause.ResolvedLib;
      end;
      Check(LLib = 'm', 'import external: ExtA''s library is sc_ib1.KLib''s "m" (got "' + LLib + '")');
    end);
end;

procedure TPCSemanticsTests.DoTestChoices();
begin
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc10_choices.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      // Line 9: a bare choice value is a PaskalCPP error (SM0015), not a C++ name;
      // line 11: as a type it is not a type (SM0013), not an opaque C++ type
      Check(DoCodes(AErrors) = 'SM0002,SM0001,SM0003,SM0010,SM0015,SM0014,SM0013', 'choices: codes ' + DoCodes(AErrors));
      Check(DoNamesText(AModule) = 'A@3:31=rkChoiceValue@3 D@3:42=rkNone E@3:56=rkNone .P@4:27=rkNone TG@4:27=rkNone TColor@7:6=rkType@5 .Green@7:15=rkChoiceValue@5 TColor@7:15=rkType@5 ' +
        'TColor@8:6=rkType@5 .Blue@8:15=rkNone TColor@8:15=rkType@5 TColor@9:6=rkType@5 Red@9:15=rkNone TColor@10:6=rkType@5 .Red@10:15=rkNone TColor@10:15=r' +
        'kType@5 Red@11:6=rkNone', 'choices: names ' + DoNamesText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestTemplates();
begin
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc11_tmpl.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'SM0002', 'templates: codes ' + DoCodes(AErrors));
      Check(DoNamesText(AModule) = 'TPoint@7:18=rkType@3 TLater@8:18=rkNone', 'templates: names ' + DoNamesText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestSystem();
begin
  DoWithSem(TPath.Combine(DoCoreDir(), 'sc12_system.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = '', 'system: codes ' + DoCodes(AErrors));
      Check(DoNamesText(AModule) = 'AX@4:10=rkParam@2 call@7:3=rkIntrinsic/ikPrintLn println@7:3=rkIntrinsic call@8:3=rkRoutine@2 size@8:3=rkRoutine@2 call@9:3=rkIntrinsic/ikParamCount p' +
        'aramcount@9:3=rkIntrinsic', 'system: names ' + DoNamesText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoWithCwd(const AName: string; const AClass: TPCSemanticsClass;
  const ACheck: TPCParseCheck);
var
  LDir: string;
  LOld: string;
begin
  // The path fixtures are relative: the parser resolves a path directive
  // against the CWD, so the parse and the analysis run inside sem\mod
  LDir := DoProbeDir('sem\mod');
  LOld := GetCurrentDir();
  if not SetCurrentDir(LDir) then
  begin
    Check(False, 'cwd: ' + LDir);
    Exit;
  end;
  try
    DoWithSemAs(AClass, TPath.Combine(LDir, AName), 100, ACheck);
  finally
    SetCurrentDir(LOld);
  end;
end;

procedure TPCSemanticsTests.DoTestModValues();
begin
  DoWithCwd('sm01_values.pcpp', TPCSemantics,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LArg: TPCDirectiveArg;
    begin
      Check(DoCodes(AErrors) = '', 'mod.values: codes ' + DoCodes(AErrors));
      Check(not DoNoEffectText(AModule).Contains('!'),
        'mod.values: every directive applies: ' + DoNoEffectText(AModule));
      LArg := AModule.Directives[7].Args[0];
      Check((AModule.Directives[7].DirectiveKind = bdVIProductName) and LArg.HasValue and
        (LArg.ResolvedText = ''), 'mod.values: an empty @viproductname is a value (F-A2-1)');
    end);
end;

procedure TPCSemanticsTests.DoTestModBad();
begin
  DoWithCwd('sm02_bad.pcpp', TPCSemantics,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) =
        'PR0022,SM0100,SM0100,SM0100,SM0100,SM0101,SM0102,SM0105,SM0105,SM0106,SM0106,SM0109',
        'mod.bad: codes ' + DoCodes(AErrors));
      Check(DoNoEffectText(AModule) = 'optimize subsystem addverinfo unitTestMode vimajor ' +
        'optimize! exeicon copydll addlibrarypath addincludepath addincludepath breakpoint!',
        'mod.bad: no effect ' + DoNoEffectText(AModule));
      if AErrors.GetItems().Count < 7 then
        Exit;
      Check((AErrors.GetItems()[1].Range.StartLine = 2) and
        (AErrors.GetItems()[1].Range.StartColumn = 11),
        'mod.bad: the first SM0100 sits on speed (C4, D-A2-6)');
      Check((AErrors.GetItems()[6].Range.StartLine = 7) and
        (AErrors.GetItems()[6].Range.StartColumn = 1),
        'mod.bad: the SM0102 sits on the second @optimize (C4, D-A2-6)');
    end);
end;

procedure TPCSemanticsTests.DoTestModDll();
begin
  DoWithCwd('sm03_dll.pcpp', TPCSemantics,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) = 'SM0103/esWarning@2:1 SM0103/esWarning@5:1 ' +
        'SM0110/esError@6:1 SM0113/esWarning@8:1', 'mod.dll: reports ' + DoReportsText(AErrors));
      Check(DoNoEffectText(AModule) = 'subsystem! addverinfo vimajor exeicon! unitTestMode!',
        'mod.dll: no effect ' + DoNoEffectText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestModLib();
begin
  DoWithCwd('sm04_lib.pcpp', TPCSemantics,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'SM0103,SM0110', 'mod.lib: codes ' + DoCodes(AErrors));
      Check(DoNoEffectText(AModule) = 'addverinfo! viproductname! vicopyright! unitTestMode!',
        'mod.lib: no effect ' + DoNoEffectText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestModLinux();
begin
  DoWithCwd('sm05_linux.pcpp', TPCSemantics,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'SM0103,SM0103,SM0103,SM0102', 'mod.linux: codes ' + DoCodes(AErrors));
      Check(DoNoEffectText(AModule) = 'target subsystem! exeicon! addverinfo! vimajor! subsystem!',
        'mod.linux: no effect ' + DoNoEffectText(AModule));
      if AErrors.GetItems().Count < 3 then
        Exit;
      Check(AErrors.GetItems()[2].Message =
        Format(RSSemModNotApplied, ['addverinfo', RSSemModWhereNotWindows]),
        'mod.linux: the third SM0103 names the target: ' + AErrors.GetItems()[2].Message);
    end);
end;

procedure TPCSemanticsTests.DoTestModNoVerInfo();
begin
  DoWithCwd('sm06_noverinfo.pcpp', TPCSemantics,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'SM0104,SM0104', 'mod.noverinfo: codes ' + DoCodes(AErrors));
      Check(DoNoEffectText(AModule) = 'vimajor! vifilename! addverinfo',
        'mod.noverinfo: no effect ' + DoNoEffectText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestModMessage();
begin
  DoWithCwd('sm07_message.pcpp', TPCSemantics,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LError: TError;
      LTexts: string;
    begin
      Check(DoReportsText(AErrors) = 'PR0009/esError@4:15 SM0108/esHint@2:1 ' +
        'SM0108/esWarning@3:1 SM0108/esFatal@7:3 SM0108/esError@11:3',
        'mod.message: reports ' + DoReportsText(AErrors));
      LTexts := '';
      for LError in AErrors.GetItems() do
      begin
        if LError.Code = PC_ERR_SEM_108 then
          LTexts := LTexts + '[' + LError.Message + ']';
      end;
      Check(LTexts = '[h %d][w][f][e]', 'mod.message: the texts verbatim, in order: ' + LTexts);
    end);
end;

procedure TPCSemanticsTests.DoTestModTests();
begin
  DoWithCwd('sm08_tests.pcpp', TPCSemantics,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'PR0009,PR0009,SM0111,SM0112', 'mod.tests: codes ' + DoCodes(AErrors));
      if AErrors.GetItems().Count < 4 then
        Exit;
      Check(AErrors.GetItems()[2].Range.StartLine = 5, 'mod.tests: the SM0111 sits on line 5');
      Check((AErrors.GetItems()[3].Range.StartLine = 6) and
        (AErrors.GetItems()[3].Message = Format(RSSemModTestDup, ['a', '4'])),
        'mod.tests: the SM0112 at line 6 names line 4: ' + AErrors.GetItems()[3].Message);
    end);
end;

procedure TPCSemanticsTests.DoTestModUnit();
begin
  DoWithCwd('sm09_main.pcpp', TPCSemantics,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'PR0023,PR0023,SM0105', 'mod.unit: codes ' + DoCodes(AErrors));
      if AErrors.GetItems().Count < 3 then
        Exit;
      Check(AErrors.GetItems()[2].Range.Filename.EndsWith('sm_u1.pcpp'),
        'mod.unit: the SM0105 is reported in the unit''s file (C4): ' +
        AErrors.GetItems()[2].Range.Filename);
    end);
end;

procedure TPCSemanticsTests.DoTestModSourceFile();
begin
  // @addsourcefile (BNF sec 2): .c and the same file named .C pass (exact
  // case: C and C++); a header and an extensionless name are SM0114 before any
  // existence check; a missing .cpp is SM0105; one report per directive
  DoWithCwd('sm10_source.pcpp', TPCSemantics,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'SM0114,SM0114,SM0105', 'mod.sourcefile: codes ' + DoCodes(AErrors));
      if AErrors.GetItems().Count < 3 then
        Exit;
      Check(AErrors.GetItems()[0].Range.StartLine = 4,
        'mod.sourcefile: the first SM0114 sits on the header''s line 4 (' +
        AErrors.GetItems()[0].Range.StartLine.ToString() + ')');
      Check(AErrors.GetItems()[2].Range.StartLine = 6,
        'mod.sourcefile: the SM0105 sits on the missing .cpp''s line 6 (' +
        AErrors.GetItems()[2].Range.StartLine.ToString() + ')');
    end);
end;

procedure TPCSemanticsTests.DoTestModCppDefine();
begin
  // @cppdefine / @cppundef (BNF sec 2): every report at its line, in report
  // order (the parser's PR0006 first, then SEM's in source order); the parser
  // keeps a second argument; a conflict names the earlier directive's file
  DoWithCwd('sm11_cppdefine.pcpp', TPCSemantics,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LItem: TError;
      LSeen: string;
    begin
      LSeen := '';
      for LItem in AErrors.GetItems() do
        LSeen := LSeen + Format('%s@%d ', [LItem.Code, LItem.Range.StartLine]);
      Check(LSeen = 'PR0006@12 SM0115@5 SM0116@6 SM0117@7 SM0118@8 SM0118@9 SM0118@11 ',
        'mod.cppdefine: reports ' + LSeen);
      Check((AModule.Directives.Count > 1) and (AModule.Directives[0].Args.Count = 1) and
        (AModule.Directives[1].Args.Count = 2) and (AModule.Directives[1].Args[1].ResolvedText = '42'),
        'mod.cppdefine: "GOOD" has one argument, "GOOD_V" "42" two');
      if AErrors.GetItems().Count < 7 then
        Exit;
      Check(AErrors.GetItems()[6].Message.Contains('sm_cu.pcpp'),
        'mod.cppdefine: the UNIT_V conflict names the unit''s directive: ' + AErrors.GetItems()[6].Message);
    end);
end;

procedure TPCSemanticsTests.DoTestModPathFailure();
begin
  DoWithCwd('sm01_values.pcpp', TPCRaisingSemantics,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = 'SM0107,SM0107,SM0107,SM0107,SM0107,SM0107',
        'mod.path_failure: codes ' + DoCodes(AErrors));
      if AErrors.GetItems().Count < 1 then
        Exit;
      Check(AErrors.GetItems()[0].Message.Contains('probe failure'),
        'mod.path_failure: the message carries the exception text: ' +
        AErrors.GetItems()[0].Message);
    end);
end;

function DoDeclNamed(const AModule: TPCModule; const ADeclName: string): TPCDecl;
var
  LItem: TPCStmt;
begin
  // The module-level declaration named ADeclName, nil = none
  Result := nil;
  for LItem in AModule.Decls do
  begin
    if (LItem is TPCDecl) and (TPCDecl(LItem).DeclName = ADeclName) then
      Exit(TPCDecl(LItem));
  end;
end;

procedure TPCSemanticsTests.DoTestTypesLiterals();
begin
  // Expected texts: python scripts\zb_sem\gen_types.py (from its ST01 table)
  DoWithSem(TPath.Combine(DoTypesDir(), 'st01_literals.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      // A literal is typed as C++23 types it (F30 (b), checked against clang by
      // scripts\zb_pe\e1\fold_rows.py); a wchar the target cannot hold is clang's to report.
      // F66: the multi-char 'ab' (line 32) is the parser's warning PR0064
      Check(DoCodes(AErrors) = 'PR0064', 'types.literals: codes ' + DoCodes(AErrors));
      Check(DoTypesText(AModule) =
        '1@3=int32=1 | 2147483647@4=int32=2147483647 | 2147483648@5=int64=2147483648 | 5000000000@6=int64=5000000000 | 0x7FFFFFFF@7=int32=2147483647 | ' +
        '0x80000000@8=uint32=2147483648 | 0xFFFFFFFF@9=uint32=4294967295 | 0x100000000@10=int64=4294967296 | ' +
        '0xFFFFFFFFFFFFFFFF@11=uint64=18446744073709551615 | 0b101@12=int32=5 | 1u@13=uint32=1 | 1l@14=int32=1 | 2147483648l@15=int64=2147483648 | ' +
        '1ul@16=uint32=1 | 1ll@17=int64=1 | 1ull@18=uint64=1 | 1z@19=int64=1 | 1uz@20=uint64=1 | 9223372036854775807@21=int64=9223372036854775807 | ' +
        '18446744073709551615u@22=uint64=18446744073709551615 | 18446744073709551615uz@23=uint64=18446744073709551615 | 2.5@24=float64~2.5 | ' +
        '2.5f@25=float32~2.5 | 0x1p-1@26=float64~0.5 | 1.5l@27=opaque | 1.0f16@28=opaque | 12_km@29=opaque | ''a''@30=char=97 | ''\xFF''@31=char=-1 | ' +
        '''ab''@32=opaque | L''x''@33=wchar=120 | L''\x10000''@34=opaque | L''\U0001F600''@35=opaque | u8''a''@36=opaque | true@37=bool=1 | false@38=bool=0 | ' +
        'nil@39=nil | "s"@40=string literal | L"w"@41=wide string literal | "a" L"b"@42=wide string literal | u8"x"@43=opaque | R"(r)"@44=string literal | ' +
        '"x"_s@45=opaque',
        'types.literals: types ' + DoTypesText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestTypesLiteralsLinux();
begin
  // Expected texts: python scripts\zb_sem\gen_types.py (from its ST02 table)
  DoWithSem(TPath.Combine(DoTypesDir(), 'st02_linux.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = '', 'types.literals_linux: codes ' + DoCodes(AErrors));
      Check(DoTypesText(AModule) =
        '1l@4=int64=1 | 1ul@5=uint64=1 | 2147483648l@6=int64=2147483648 | L''\x10000''@7=wchar=65536 | L''\xFFFFFFFF''@8=wchar=-1 | ''\xFF''@9=char=-1 | ' +
        '18446744073709551615ul@10=uint64=18446744073709551615',
        'types.literals_linux: types ' + DoTypesText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestTypesNames();
begin
  // Expected texts: python scripts\zb_sem\gen_types.py (from its ST03 table)
  DoWithSem(TPath.Combine(DoTypesDir(), 'st03_names.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LColor: TPCTypeDecl;
      LNamed: TPCNamedType;
      LChoices: TPCChoicesType;
      LValue: TPCChoiceValue;
      LV3: TPCVarDecl;
    begin
      Check(DoCodes(AErrors) = 'SM0002', 'types.names: codes ' + DoCodes(AErrors));
      Check(DoTypesText(AModule) =
        '5@4=int32=5 | Green@4=int32=5 | self.F@9=int64 | self@9=TObj | AP@10=uint8 | 7@15=int32=7 | 0@17=int32=0 | K@19=int16=7 | G@20=uint64 | TColor.Green@21=TColor=5 | ' +
        'TColor@21=- | st_u1.X@22=float32 | st_u1@22=- | errno@23=opaque | Z@24=error | 1 + 1@25=opaque | nullptr@26=opaque',
        'types.names: types ' + DoTypesText(AModule));
      // One SEM-built name node per type declaration (D-A3a-3)
      LColor := TPCTypeDecl(DoDeclNamed(AModule, 'TColor'));
      LV3 := TPCVarDecl(DoDeclNamed(AModule, 'V3'));
      if (LColor = nil) or (LV3 = nil) or (not (LColor.TypeDef is TPCChoicesType)) then
      begin
        Check(False, 'types.names: TColor (a choices type) and V3 are declared');
        Exit;
      end;
      LNamed := LColor.ResolvedNamedType;
      LChoices := TPCChoicesType(LColor.TypeDef);
      Check(LNamed <> nil, 'types.names: TColor has its ResolvedNamedType');
      Check((LV3.InitExpr <> nil) and (LV3.InitExpr.ResolvedType = LNamed),
        'types.names: V3''s TColor.Green is typed by the one TColor node');
      Check((LChoices.Values.Count = 3) and (LChoices.Values[2].ValueExpr <> nil) and
        (LChoices.Values[2].ValueExpr.ResolvedType = AAst.BuiltinType(tkKwInt32)),
        'types.names: Blue''s Green is its ordinal (int32) inside its own value list');
      for LValue in LChoices.Values do
        Check(LValue.ResolvedChoices = LNamed,
          'types.names: ' + LValue.ValueName + '''s ResolvedChoices is the one TColor node');
    end);
end;

procedure TPCSemanticsTests.DoTestTypesIntSuffixes();
var
  LI: Integer;
  LRow: TPCIntSuffixRow;
begin
  // Every standard suffix finds its own row; anything else is not a suffix
  for LI := Low(PC_INT_SUFFIXES) to High(PC_INT_SUFFIXES) do
  begin
    Check(TPCVocabulary.FindIntSuffix(PC_INT_SUFFIXES[LI].SuffixText, LRow) and
      (LRow.SuffixText = PC_INT_SUFFIXES[LI].SuffixText) and
      (LRow.IsUnsigned = PC_INT_SUFFIXES[LI].IsUnsigned) and
      (LRow.SuffixWidth = PC_INT_SUFFIXES[LI].SuffixWidth),
      'types.int_suffixes: ' + PC_INT_SUFFIXES[LI].SuffixText + ' finds its row');
  end;
  Check(not TPCVocabulary.FindIntSuffix('', LRow), 'types.int_suffixes: '''' is no suffix');
  Check(not TPCVocabulary.FindIntSuffix('_km', LRow), 'types.int_suffixes: _km is no suffix');
  Check(not TPCVocabulary.FindIntSuffix('lL', LRow), 'types.int_suffixes: lL is no suffix (mixed case)');
end;

procedure TPCSemanticsTests.DoTestTypesConvert();
begin
  // Expected texts: python scripts\zb_sem\gen_types.py (from its ST04 table)
  DoWithSem(TPath.Combine(DoTypesDir(), 'st04_convert.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LDecl: TPCDecl;
      LExpr: TPCExpr;
    begin
      Check(DoReportsText(AErrors) =
        'SM0202/esError@18:15 SM0200/esError@20:15 SM0200/esError@27:15 SM0200/esError@30:18 SM0200/esError@32:18 SM0200/esError@34:17 ' +
        'SM0200/esError@36:18 SM0200/esError@37:18 SM0200/esError@39:18 SM0200/esError@40:16 SM0200/esError@41:16 SM0200/esError@42:15 ' +
        'SM0200/esError@43:15 SM0200/esError@46:22 SM0200/esError@48:17 SM0200/esError@50:23 SM0200/esError@52:28 SM0200/esError@53:16 ' +
        'SM0200/esError@54:14 SM0200/esError@58:15 SM0200/esError@62:17 SM0200/esError@63:15 SM0200/esError@64:16 SM0200/esError@66:22 ' +
        'SM0202/esError@68:17 SM0202/esError@70:19 SM0202/esError@72:22 SM0202/esError@73:22 SM0202/esError@74:21 SM0202/esError@75:17 ' +
        'SM0202/esError@83:5',
        'types.convert: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        'a const value must be a constant | 300 does not fit in ''uint8'' (0..255) | ''int64'' does not convert implicitly to ''int8''; write int8(LBig) | ' +
        '''float64'' does not convert implicitly to ''float32''; write float32(LF64) | ' +
        '''float64'' does not convert implicitly to ''float32''; write float32(0.1) | ''int8'' does not convert implicitly to ''uint32''; write uint32(LI8) | ' +
        '''uint32'' does not convert implicitly to ''float32''; write float32(LU32) | ' +
        '''int64'' does not convert implicitly to ''float64''; write float64(LBig) | ' +
        '''int32'' does not convert implicitly to ''float32''; write float32(16777217) | ' +
        '''float64'' does not convert implicitly to ''int32''; write int32(2.0) | ''char'' does not convert implicitly to ''int32''; write int32(''a'') | ' +
        '''int32'' does not convert implicitly to ''char''; write char(65) | ''int32'' does not convert implicitly to ''bool''; write bool(1) | ' +
        '''string literal'' does not convert implicitly to ''ptr to char'' | ''wide string literal'' does not convert implicitly to ''string'' | ' +
        '''ptr'' does not convert implicitly to ''ptr to int32''; write ptr to int32(LV) | ' +
        '''string'' does not convert implicitly to ''ptr to const char''; write LS.c_str() | ''string'' does not convert implicitly to ''int32'' | ' +
        '''ptr to const char'' does not convert implicitly to ''ptr'' | 300 does not fit in ''int8'' (-128..127) | ' +
        '''int64'' does not convert implicitly to ''uint64''; write uint64(LBig) | ''int32'' does not convert implicitly to ''TCol''; write (TCol)1 | ' +
        '''int64'' does not convert implicitly to ''TByte''; write uint8(LBig) | ''ptr to const char'' does not convert implicitly to ''ptr to char'' | ' +
        'a static array bound must be a constant | a set range bound must be a constant | a choice value must be a constant | ' +
        'a choice value must be a constant | an align value must be a constant | a bitfield width must be a constant | a match label must be a constant',
        'types.convert: messages ' + DoMessagesText(AErrors));
      // A const leaf carries its value, converted to the const's type
      LDecl := DoDeclNamed(AModule, 'C31');
      LExpr := nil;
      if LDecl is TPCVarDecl then
        LExpr := TPCVarDecl(LDecl).InitExpr;
      Check((LExpr <> nil) and LExpr.HasConstValue and not LExpr.ConstIsUnsigned and (LExpr.ConstInt = 5),
        'types.convert: C31''s K1 folds to int32 5');
      LDecl := DoDeclNamed(AModule, 'C39');
      LExpr := nil;
      if LDecl is TPCVarDecl then
        LExpr := TPCVarDecl(LDecl).InitExpr;
      Check((LExpr <> nil) and LExpr.HasConstValue and LExpr.ConstIsUnsigned and (LExpr.ConstUInt = 7),
        'types.convert: C39''s K9 folds to uint16 7 (unsigned form)');
      LDecl := DoDeclNamed(AModule, 'C33');
      LExpr := nil;
      if LDecl is TPCVarDecl then
        LExpr := TPCVarDecl(LDecl).InitExpr;
      Check((LExpr <> nil) and LExpr.HasConstFloat and (LExpr.ConstFloat = 0.5),
        'types.convert: C33''s K7 folds to float32 0.5');
      // A string const is a constant without a folded value (no SM0202 at K8)
      LDecl := DoDeclNamed(AModule, 'K8');
      LExpr := nil;
      if LDecl is TPCConstDecl then
        LExpr := TPCConstDecl(LDecl).ValueExpr;
      Check((LExpr <> nil) and LExpr.IsConstExpr and not LExpr.HasConstValue,
        'types.convert: K8''s K3 is a constant, not folded');
      // A reported value keeps no folded value (K4's 300, C1)
      LDecl := DoDeclNamed(AModule, 'K4');
      LExpr := nil;
      if LDecl is TPCConstDecl then
        LExpr := TPCConstDecl(LDecl).ValueExpr;
      Check((LExpr <> nil) and (LExpr.ResolvedType is TPCErrorType) and not LExpr.HasConstValue,
        'types.convert: K4''s 300 is poisoned without a value');
    end);
end;

procedure TPCSemanticsTests.DoTestTypesExprs();
begin
  // Expected texts: python scripts\zb_sem\gen_exprs.py (from its EXPRS / STMTS tables)
  DoWithSem(TPath.Combine(DoTypesDir(), 'st05_exprs.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) =
        'SM0200,SM0200,SM0256,SM0258,SM0257,SM0259,SM0200,SM0253,SM0009,SM0200,SM0252,SM0250,SM0268,SM0267,SM0266,' +
        'SM0256,SM0256,SM0250,SM0250,SM0250,SM0250,SM0261,SM0261,SM0261,SM0261,SM0252,SM0252,SM0252,SM0252,SM0252,' +
        'SM0252,SM0252,SM0200,SM0200,SM0250,SM0250,SM0250,SM0250,SM0200,SM0200,SM0200,SM0200,SM0200,SM0200,SM0250,' +
        'SM0250,SM0250,SM0250,SM0250,SM0250,SM0250,SM0200,SM0250,SM0250,SM0255,SM0200,SM0200,SM0200,SM0200,SM0250,' +
        'SM0250,SM0250,SM0263,SM0263',
        'types.exprs: codes ' + DoCodes(AErrors));
      // PLAN-ARITH A1: numeric operator results typed as C++ types them (E02-E07, E32-E34, E53,
      // E74-E108); E93 / E94 / E99 and LB++ have no C++ operator (SM0250). A2: an operand that
      // would convert hiddenly is SM0200 (E05 E07 E21 E34 E75 E85 E109-E111 E113-E115), a bool /
      // char operand of arithmetic / bitwise SM0250 (E103 E120-E126)
      Check(DoInitsText(AModule) =
        'E01=int32=5 | E02=int32 | E03=int64 | E04=uint32 | E05=error | E06=float64~3.5 | E07=error | E08=int32=3' +
        ' | E09=int32=-1 | E10=error | E11=uint32=0 | E12=error | E13=error | E14=int32=-2147483648 | E15=error' +
        ' | E16=int32=-4 | E17=int8=44 | E18=uint8=255 | E19=bool=0 | E20=bool=1 | E21=error | E22=int32 | E23=int32=10' +
        ' | E24=int32 | E25=char | E26=int32 | E27=error | E28=ptr to int32 | E29=int32 | E30=error | E31=string' +
        ' | E32=float32 | E33=float64 | E34=error | E35=error | E36=error | E37=bool | E38=error | E39=set of int32' +
        ' | E40=error | E41=error | E42=float32 | E43=int32 | E44=int32=-1 | E45=error | E46=error | E47=bool' +
        ' | E48=int32=-5 | E49=error | E50=error | E51=error | E52=bool | E53=int32 | E54=TSet | E55=TSet | E56=error' +
        ' | E57=int32 | E58=error | E59=int32 | E60=error | E61=error | E62=error | E63=error | E64=error | E65=error' +
        ' | E66=error | E67=error | E68=error | E69=error | E70=bool | E71=bool | E72=bool | E73=bool | E74=int32' +
        ' | E75=error | E76=int64 | E77=uint32 | E78=uint64 | E79=int32 | E80=int32 | E81=int64 | E82=int32' +
        ' | E83=uint32 | E84=int64 | E85=error | E86=int32 | E87=int64 | E88=float64 | E89=float32 | E90=float64' +
        ' | E91=float64 | E92=float32 | E93=error | E94=error | E95=int32 | E96=uint32 | E97=float32 | E98=int32' +
        ' | E99=error | E100=int32 | E101=int8 | E102=float64 | E103=error | E104=float32 | E105=int32 | E106=int64' +
        ' | E107=opaque | E108=float64 | E109=error | E110=error | E111=error | E112=uint32 | E113=error | E114=error' +
        ' | E115=error | E116=bool | E117=bool | E118=float64 | E119=int32 | E120=error | E121=error | E122=error' +
        ' | E123=error | E124=error | E125=error | E126=error | E127=bool | E128=int32',
        'types.exprs: inits ' + DoInitsText(AModule));
      // The SM0250 texts name the operator and the PaskalCPP operand types
      Check(DoMessagesText(AErrors).Contains('operator ''&'' does not take ''float64'' and ''int32''') and
        DoMessagesText(AErrors).Contains('operator ''~'' does not take ''float64''') and
        DoMessagesText(AErrors).Contains('operator ''++'' does not take ''bool'''),
        'types.exprs: arith SM0250 messages ' + DoMessagesText(AErrors));
      // PLAN-ARITH A2: SM0200 at the operand that would convert (E05 LU + LI: LI at :44:19), with
      // the cast hint; & on bools, + on a char and /= on an integer are SM0250
      Check(DoReportsText(AErrors).Contains('SM0200/esError@44:19') and
        DoMessagesText(AErrors).Contains('''int32'' does not convert implicitly to ''uint32''; write uint32(LI)') and
        DoMessagesText(AErrors).Contains('''int64'' does not convert implicitly to ''float64''; write float64(LI64)') and
        DoMessagesText(AErrors).Contains('operator ''&'' does not take ''bool'' and ''bool''') and
        DoMessagesText(AErrors).Contains('operator ''+'' does not take ''char'' and ''int32''') and
        DoMessagesText(AErrors).Contains('operator ''/='' does not take ''int32'' and ''int32'''),
        'types.exprs: A2 reports ' + DoReportsText(AErrors) + ' / ' + DoMessagesText(AErrors));
      // F27 folding reports (PLAN-PASKAL-ERRORS E1 D6): overflow at the operator expression,
      // a zero divisor at the divisor, a shift count at the count (lines / columns of
      // st05_exprs.pcpp (E<n> on line n + 39): E10 :49, E12 :51, E13 :52, E15 :54, E45 :84, E46 :85;
      // each value at column 14; E12's operator expression starts at its '(', observed in the E1
      // negative run)
      Check(DoReportsText(AErrors).Contains('SM0256/esError@49:14') and
        DoReportsText(AErrors).Contains('SM0258/esError@51:14') and
        DoReportsText(AErrors).Contains('SM0257/esError@52:20') and
        DoReportsText(AErrors).Contains('SM0259/esError@54:20') and
        DoReportsText(AErrors).Contains('SM0256/esError@84:14') and
        DoReportsText(AErrors).Contains('SM0256/esError@85:14'),
        'types.exprs: fold reports ' + DoReportsText(AErrors));
      // SM0252 at the comparison (E35 :74 LR = LR, E67 :106 LRA = LRA, E69 :108 LRN = LRN),
      // naming the operand's type
      Check(DoReportsText(AErrors).Contains('SM0252/esError@74:14') and
        DoReportsText(AErrors).Contains('SM0252/esError@106:14') and
        DoReportsText(AErrors).Contains('SM0252/esError@108:14'),
        'types.exprs: SM0252 reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors).Contains('operator ''='' cannot compare ''TRec''') and
        DoMessagesText(AErrors).Contains('operator ''<=>'' cannot compare ''TRec''') and
        DoMessagesText(AErrors).Contains('operator ''='' cannot compare ''TOv''') and
        DoMessagesText(AErrors).Contains('operator ''='' cannot compare ''array[0..1] of TRec'''),
        'types.exprs: SM0252 messages ' + DoMessagesText(AErrors));
      Check(DoMessagesText(AErrors).Contains('constant overflows ''int32''') and
        DoMessagesText(AErrors).Contains('''-2147483648 div -1'' overflows ''int32''') and
        DoMessagesText(AErrors).Contains('''mod'' by zero') and
        DoMessagesText(AErrors).Contains('shift count 32 outside 0..31') and
        DoMessagesText(AErrors).Contains('constant overflows ''int64'''),
        'types.exprs: fold messages ' + DoMessagesText(AErrors));
      // A char / choices-bounded array names its index family; others an integer
      Check(DoMessagesText(AErrors).Contains('an index of ''TAC'' is a ''char'' value, got ''int32''') and
        DoMessagesText(AErrors).Contains('an index of ''TAH'' is a ''TCh'' value, got ''char''') and
        DoMessagesText(AErrors).Contains('an index is an integer, got ''char'''),
        'types.exprs: index messages ' + DoMessagesText(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestFoldWitness();
const
  { FOLD_TAGS }
  FOLD_TAGS: array[0..1] of string = ('win', 'lin');
  { FOLD_TARGETS }
  FOLD_TARGETS: array[0..1] of string = ('x86_64-windows-gnu', 'x86_64-linux-gnu');
var
  LI: Integer;
  LK: Integer;
  LDir: string;
  LZig: string;
  LTag: string;
  LExpect: TArray<string>;
  LParts: TArray<string>;
  LSource: string;
  LObject: string;
  LParams: string;
  LExitCode: DWORD;
  LRaised: string;
  LBuilt: Boolean;
begin
  // F27 + F30 (b) (PLAN-PASKAL-ERRORS E1 D7): ONE row table is the witness,
  // written by python scripts\zb_pe\e1\fold_rows.py --write. Per target, SEM
  // folds every row to the table's type / value / code (line 1 = the inits,
  // line 2 = the codes), and the bundled clang agrees on the same rows: the
  // value rows' static_asserts build, every error row is refused. A SEM or a
  // toolchain change that disagrees with the other fails here
  LDir := DoProbeDir('sem\fold');
  LZig := TUtils.ResolvePath('$P:res\zig\zig.exe');
  Check(TFile.Exists(LZig), 'types.fold_witness: the bundled zig exists');
  for LI := 0 to High(FOLD_TAGS) do
  begin
    LTag := FOLD_TAGS[LI];
    LExpect := TFile.ReadAllLines(TPath.Combine(LDir, 'fold_' + LTag + '.expect'), TEncoding.UTF8);
    Check(Length(LExpect) >= 3, Format('types.fold_witness: fold_%s.expect has its lines', [LTag]));
    if Length(LExpect) < 3 then
      Continue;
    DoWithSem(TPath.Combine(LDir, 'fold_' + LTag + '.pcpp'), 100,
      procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
      begin
        Check(DoInitsText(AModule) = LExpect[0],
          Format('types.fold_witness: %s inits %s', [LTag, DoInitsText(AModule)]));
        Check(DoCodes(AErrors) = LExpect[1],
          Format('types.fold_witness: %s codes %s', [LTag, DoCodes(AErrors)]));
      end);

    // Every C++ file of the manifest through the bundled clang for this target
    for LK := 2 to High(LExpect) do
    begin
      if LExpect[LK].Trim() = '' then
        Continue;
      LParts := LExpect[LK].Split([' ']);
      Check(Length(LParts) = 2, Format('types.fold_witness: manifest line "%s"', [LExpect[LK]]));
      if Length(LParts) <> 2 then
        Continue;
      LSource := TPath.Combine(LDir, LParts[1]);
      LObject := TPath.Combine(TPath.GetTempPath(), 'pcpp-fold-' + LParts[1] + '.o');
      LParams := 'c++ -target ' + FOLD_TARGETS[LI] + ' -std=gnu++23 -c ' + TUtils.QuoteCommandArg(LSource) +
        ' -o ' + TUtils.QuoteCommandArg(LObject);
      LExitCode := 42;
      LRaised := '';
      try
        TUtils.CaptureConsoleOutput('', PChar(LZig), PChar(LParams), LDir, LExitCode, nil,
          procedure(const ALine: string; const AData: Pointer)
          begin
          end);
      except
        on E: Exception do
          LRaised := E.Message;
      end;
      LBuilt := (LRaised = '') and (LExitCode = 0);
      if LParts[0] = 'ok' then
        Check(LBuilt, Format('types.fold_witness: clang builds %s for %s (exit %d%s)',
          [LParts[1], FOLD_TARGETS[LI], LExitCode, LRaised]))
      else
        Check((LRaised = '') and (LExitCode <> 0), Format('types.fold_witness: clang refuses %s for %s (exit %d%s)',
          [LParts[1], FOLD_TARGETS[LI], LExitCode, LRaised]));
    end;
  end;
end;

procedure TPCSemanticsTests.DoTestTypesOpaque();
begin
  // A C type under a pointer, array or routine type is clang's to judge: two
  // `ptr to size_t` nodes are one type. Expected texts: python
  // scripts\zb_sem\gen_types.py (from its ST06 table)
  DoWithSem(TPath.Combine(DoTypesDir(), 'st06_opaque.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) = 'SM0200/esError@16:22',
        'types.opaque_nested: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        '''ptr to int32'' does not convert implicitly to ''ptr to int64''; write ptr to int64(LH)',
        'types.opaque_nested: messages ' + DoMessagesText(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestDeclsDispatch();
begin
  // Expected texts: python scripts\zb_sem\gen_decls.py (from its SD05 table);
  // PLAN-OBJECT O3 (D7): virtual / override / final / abstract
  DoWithSem(TPath.Combine(DoDeclsDir(), 'sd05_dispatch.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) =
        'SM0332/esError@26:12 SM0332/esError@30:5 SM0333/esError@34:5 SM0333/esError@38:5 SM0336/esError@42:5 SM0337/esError@46:26 SM0335/esError@49:5 ' +
        'SM0334/esError@53:21 SM0339/esError@61:17 SM0340/esError@72:14 SM0338/esError@79:7 SM0338/esError@81:22 SM0338/esError@82:22 SM0426/esError@88:10 ' +
        'SM0426/esError@99:10 SM0426/esError@103:10 SM0426/esError@107:10',
        'decls.dispatch: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        '''Area'' is virtual in ''TShape'': write ''override method Area'' | ''Name'' is virtual in ''TShape'': write ''override method Name'' | ' +
        '''Plain'' overrides nothing: no level above ''TBad'' has a virtual method ''Plain'' | ' +
        '''Gone'' overrides nothing: no level above ''TBad'' has a virtual method ''Gone'' | ' +
        '''final'' closes a virtual method: write ''virtual final method'' or ''override final method'' | ' +
        'an abstract method is virtual: write ''virtual method Abs'' | ''TCircle.Name'' is final: it cannot be overridden | ' +
        '''Area'' must take the parameters and return the type of ''TCircle.Area'' it overrides | ''TSealed'' is final: no type may extend it | ' +
        '''TShape.Area'' is abstract: it has no body to call | ''TShape'' is abstract (''TShape.Area'' has no body): it cannot be held by value or created | ' +
        '''TShape'' is abstract (''TShape.Area'' has no body): it cannot be held by value or created | ' +
        '''TShape'' is abstract (''TShape.Area'' has no body): it cannot be held by value or created | ' +
        'method ''Area'' may change its object, which is const here: pass it var | method ''Area'' may change its object, which is const here: pass it var | ' +
        'method ''Area'' may change its object, which is const here: pass it var | method ''Area'' may change its object, which is const here: pass it var',
        'decls.dispatch: messages ' + DoMessagesText(AErrors));
      Check(DoNotesText(AErrors) =
        'SM0332@26^4 SM0332@30^5 SM0333@34^9 SM0333@38 SM0336@42 SM0337@46 SM0335@49^20 SM0334@53^16 SM0339@61 SM0340@72 SM0338@79^4 SM0338@81^4 SM0338@82^4 ' +
        'SM0426@88 SM0426@99 SM0426@103 SM0426@107',
        'decls.dispatch: notes ' + DoNotesText(AErrors));
      Check(DoDispatchFactsText(AModule) =
        'TShape=P,A:Area TCircle=P TBad=P,A:Abs TBad2=P TSealed=- TSub=- TC2=P TS2=P THold=-',
        'decls.dispatch: facts ' + DoDispatchFactsText(AModule));
      Check(DoOverridesText(AModule) =
        'TCircle.Area>TShape TCircle.Name>TShape TC2.Area>TCircle TS2.Area>TShape',
        'decls.dispatch: overrides ' + DoOverridesText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestDeclsOwners();
begin
  // Expected texts: python scripts\zb_sem\gen_decls.py (from its SD08 table);
  // PLAN-OBJECT O6 (D4, Q1-Q3): own / ref / weak
  DoWithSem(TPath.Combine(DoDeclsDir(), 'sd08_owners.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) =
        'SM0357/esError@43:8 SM0358/esError@57:11 SM0427/esError@64:11 SM0200/esError@68:14 SM0360/esError@71:3 SM0200/esError@73:16 SM0427/esError@76:14 ' +
        'SM0427/esError@77:12 SM0349/esError@78:17 SM0359/esError@80:13 SM0338/esError@81:18 SM0425/esError@82:17',
        'decls.owners: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        'field ''R'': a record or an overlay holds no object (''ref TPlain'' holds one): it is plain data, hold a ptr to the object | ' +
        '''own int32'': own, ref and weak hold an object, and ''int32'' is none | ' +
        '''LSrc'' would be copied here, and ''own TPlain'' cannot be copied (an own is the sole owner of its object): pass it var / const, return it from a local, or hold a ref | ' +
        '''weak TPlain'' does not convert implicitly to ''ref TPlain'' | ' +
        '''LWatch.X'': a weak may watch an object that is gone: read it through lock(LWatch), which is nil then | ' +
        '''own TPlainKid'' does not convert implicitly to ''own TPlain'' | ' +
        '''LSrc'' would be copied here, and ''own TPlain'' cannot be copied (an own is the sole owner of its object): pass it var / const, return it from a local, or hold a ref | ' +
        '''LHeld2'' would be copied here, and ''THoldsOwn'' cannot be copied: pass it var / const, return it from a local, or give ''THoldsOwn'' a copy | ' +
        '''TNeeds'' has no init without arguments: build it with arguments, TNeeds(...) | ' +
        '''weak TPlain'' builds nothing: a weak watches an object a ref holds (build it with ref TPlain(...)) | ' +
        '''TAbs'' is abstract (''TAbs.M'' has no body): it cannot be held by value or created | ' +
        '''ref TPlain'' cannot be printed: print the fields of a record, object or overlay',
        'decls.owners: messages ' + DoMessagesText(AErrors));
      Check(DoNotesText(AErrors) =
        'SM0357@43 SM0358@57 SM0427@64 SM0200@68 SM0360@71 SM0200@73 SM0427@76 SM0427@77^40 SM0349@78 SM0359@80 SM0338@81^37 SM0425@82',
        'decls.owners: notes ' + DoNotesText(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestDeclsCopy();
begin
  // Expected texts: python scripts\zb_sem\gen_decls.py (from its SD07 table);
  // PLAN-OBJECT O5 (D5 / D6 / H3): copy, move, slicing, a record holds no object
  DoWithSem(TPath.Combine(DoDeclsDir(), 'sd07_copy.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) =
        'SM0355/esError@25:19 SM0353/esError@31:10 SM0353/esError@36:10 SM0354/esError@44:5 SM0356/esError@51:7 SM0429/esError@60:7 SM0357/esError@83:8 ' +
        'SM0357/esError@87:8 SM0427/esError@108:10 SM0429/esError@118:3 SM0429/esError@122:3 SM0429/esError@123:3 SM0428/esError@140:9 SM0427/esError@158:9 ' +
        'SM0427/esError@161:11 SM0427/esError@164:9 SM0427/esError@165:9 SM0427/esError@166:11 SM0428/esError@167:12',
        'decls.copy: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        '''TKidCp'' cannot copy its parent part: ''TRes'' cannot be copied (give it a copy) | ' +
        'copy takes one const parameter of its own type: write copy(const ASource: TShapeV); | ' +
        'copy takes one const parameter of its own type: write copy(const ASource: TShapeT); | ''TTwo'' declares copy twice: an object has one copy | ' +
        'copy copies the parent part with the parent''s own copy: parent.init(...) is not written in a copy | ' +
        '''self'' may hold a descendant of ''TPoly'' (it is polymorphic): assigning to it would replace only its ''TPoly'' part; set its fields instead | ' +
        'field ''O'': a record or an overlay holds no object (''TPlain'' is one): it is plain data, hold a ptr to the object | ' +
        'field ''A'': a record or an overlay holds no object (''TPlain'' is one): it is plain data, hold a ptr to the object | ' +
        '''AR'' would be copied here, and ''TRes'' cannot be copied: pass it var / const, return it from a local, or give ''TRes'' a copy | ' +
        '''AP'' may hold a descendant of ''TPoly'' (it is polymorphic): assigning to it would replace only its ''TPoly'' part; set its fields instead | ' +
        '''AP^'' may hold a descendant of ''TPoly'' (it is polymorphic): assigning to it would replace only its ''TPoly'' part; set its fields instead | ' +
        '''AP[0]'' may hold a descendant of ''TPoly'' (it is polymorphic): assigning to it would replace only its ''TPoly'' part; set its fields instead | ' +
        '''AQ'' may hold a descendant of ''TPoly'' (it is polymorphic): a copy keeps only its ''TPoly'' part; pass it var / const, or through a pointer | ' +
        '''LB'' would be copied here, and ''TRes'' cannot be copied: pass it var / const, return it from a local, or give ''TRes'' a copy | ' +
        '''LA'' would be copied here, and ''TRes'' cannot be copied: pass it var / const, return it from a local, or give ''TRes'' a copy | ' +
        '''LK2'' would be copied here, and ''TKid'' cannot be copied: pass it var / const, return it from a local, or give ''TKid'' a copy | ' +
        '''LH2'' would be copied here, and ''THolds'' cannot be copied: pass it var / const, return it from a local, or give ''THolds'' a copy | ' +
        '''LArr2'' would be copied here, and ''array[0..1] of TRes'' cannot be copied: pass it var / const, return it from a local, or give ''TRes'' a copy | ' +
        '''TPolyKid'' would be cut down to its ''TPoly'' part here (it is polymorphic): pass it var / const, or through a pointer',
        'decls.copy: messages ' + DoMessagesText(AErrors));
      Check(DoNotesText(AErrors) =
        'SM0355@25^5 SM0353@31 SM0353@36 SM0354@44 SM0356@51 SM0429@60 SM0357@83 SM0357@87 SM0427@108^5 SM0429@118 SM0429@122 SM0429@123 SM0428@140 ' +
        'SM0427@158^5 SM0427@161^5 SM0427@164^22 SM0427@165^20 SM0427@166^5 SM0428@167',
        'decls.copy: notes ' + DoNotesText(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestDeclsLifecycle();
begin
  // Expected texts: python scripts\zb_sem\gen_decls.py (from its SD06 table);
  // PLAN-OBJECT O4 (D3): init / done and construction
  DoWithSem(TPath.Combine(DoDeclsDir(), 'sd06_lifecycle.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) =
        'PR0034/esError@5:5 PR0058/esError@10:5 PR0058/esError@15:5 PR0059/esError@20:13 PR0059/esError@25:9 SM0347/esError@85:5 SM0347/esError@89:20 ' +
        'SM0347/esError@93:5 SM0347/esError@97:5 SM0344/esError@106:7 SM0345/esError@115:7 SM0345/esError@123:7 SM0346/esError@131:19 SM0346/esError@137:19 ' +
        'SM0341/esError@144:5 SM0324/esError@154:5 SM0348/esError@163:17 SM0342/esError@169:12 SM0343/esError@175:12 SM0349/esError@206:9 ' +
        'SM0350/esError@207:15 SM0351/esError@208:17 SM0351/esError@209:15 SM0352/esError@210:13 SM0349/esError@211:24',
        'decls.lifecycle: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        '''init'' is not allowed in a record | ''hidden'' does not go before init, copy or done: they are never hidden, virtual, override or final | ' +
        '''virtual'' does not go before init, copy or done: they are never hidden, virtual, override or final | ' +
        'an init has no result type and no ''...'': write init(<parameters>); | a done has no parameters and no result type: write done; | ' +
        '''TBase'' has no init without arguments: begin every init of ''TNoLead'' with parent.init(...) | ' +
        '''TBase'' has no init without arguments: begin every init of ''TNoInit'' with parent.init(...) | ' +
        'field ''F'': ''TNeedK'' has no init without arguments: begin every init of ''TFieldNoInit'' with self.F.init(...) | ' +
        'field ''F'': ''TNeedK'' has no init without arguments: begin every init of ''TFieldNoLead'' with self.F.init(...) | ' +
        'parent.init(...) is the first statement of an init | self.A.init(...) comes after self.B.init(...): fields are built in declaration order | ' +
        'self.A.init(...) is written twice: a field is built once | ' +
        '''LX'' does not exist yet: the arguments of parent.init(...) run before the object is built | ' +
        '''self'' does not exist yet: the arguments of parent.init(...) run before the object is built | ' +
        '''TTwoDone'' declares done twice: an object has one done | ' +
        '''init'' is already declared with these parameter types: overloads differ in their parameter types | ' +
        '''Show'' is virtual: in an init or a done a call does not dispatch, call a plain method or parent.Show() | ' +
        'init runs when an object is built: it is never called (only parent.init(...) and self.<field>.init(...) begin an init) | ' +
        'done runs when an object ends: it is never called | ''TBase'' has no init without arguments: build it with arguments, TBase(...) | ' +
        '''int32'' takes no init arguments: only an object has an init | ''TNoInit'' declares no init: it is built without arguments | ' +
        'no init of ''TBase'' takes (float64) | the arguments (int16) fit more than one init of ''TAmb'': convert them to pick one | ' +
        '''TBase'' has no init without arguments: build it with arguments, TBase(...)',
        'decls.lifecycle: messages ' + DoMessagesText(AErrors));
      Check(DoNotesText(AErrors) =
        'PR0034@5 PR0058@10 PR0058@15 PR0059@20 PR0059@25 SM0347@85 SM0347@89 SM0347@93 SM0347@97 SM0344@106 SM0345@115 SM0345@123 SM0346@131 SM0346@137 ' +
        'SM0341@144 SM0324@154^150 SM0348@163 SM0342@169 SM0343@175 SM0349@206 SM0350@207 SM0351@208 SM0351@209^31 SM0352@210^180^184 SM0349@211',
        'decls.lifecycle: notes ' + DoNotesText(AErrors));
      Check(DoLifecycleVarsText(AModule) =
        'GB>31 GP>46 GP2>50 GD>65 GAmb2>184 LB>31 LD>65 LP>46',
        'decls.lifecycle: vars ' + DoLifecycleVarsText(AModule));
      Check(DoLeadsText(AModule) =
        'L65:3 L78:1 L103:1 L112:1 L120:1 L127:1 L135:1 L160:1 L191:1',
        'decls.lifecycle: leads ' + DoLeadsText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestDeclsRoutines();
begin
  // Expected texts: python scripts\zb_sem\gen_decls.py (from its SD04 table)
  DoWithSem(TPath.Combine(DoDeclsDir(), 'sd04_routines.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LItem: TPCStmt;
      LRoutine: TPCRoutine;
      LForwardA: TPCRoutine;
      LFullA: TPCRoutine;
      LLinkage: string;
      LLibs: string;
    begin
      Check(DoReportsText(AErrors) =
        'SM0306/esError@12:1 SM0306/esError@16:1 SM0306/esError@20:1 SM0306/esError@25:1 SM0306/esError@29:10 SM0327/esError@87:24 SM0326/esError@88:24 ' +
        'SM0326/esError@89:24 SM0327/esError@93:23 SM0004/esError@95:27 SM0307/esError@32:1 SM0324/esError@39:1 SM0324/esError@45:1 SM0324/esError@48:1 ' +
        'SM0323/esWarning@52:1 SM0323/esWarning@58:1 SM0330/esError@58:1 SM0325/esError@64:17 SM0330/esError@70:1 SM0330/esError@79:1',
        'decls.routines: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        'forward and full declaration of ''B'' differ: parameter 2 is ''Y'' in one and ''Z'' in the other | ' +
        'forward and full declaration of ''C'' differ: parameter ''X'' is passed differently (var / const) | ' +
        'forward and full declaration of ''D'' differ: their return types differ | ' +
        'forward and full declaration of ''E'' differ: one is clink, the other is not | ' +
        'forward and full declaration of ''F'' differ: one is exported, the other is not | ' +
        '''m.dll'' is not a library name: external takes a name such as m or user32, never a file or a path | ' +
        '''KNum'' must be a const string (external library) | ''KNope'' must be a const string (external library) | ' +
        '''m.dll'' is not a library name: external takes a name such as m or user32, never a file or a path | ''A'' is already declared in this scope | ' +
        'forward routine ''G'' has no matching full declaration | ' +
        '''H'' is already declared with these parameter types: overloads differ in their parameter types | ' +
        '''H'' is already declared with these parameter types: overloads differ in their parameter types | ' +
        '''H'' is already declared with these parameter types: overloads differ in their parameter types | ' +
        '''P'' is overloaded: C linkage dropped, it gets C++ linkage | ''W'' is overloaded: C linkage dropped, it gets C++ linkage | ' +
        '''W'' is variadic: a variadic routine cannot share its name with another routine | ' +
        '''Q'' has C linkage and a body: it needs a fixed parameter before ''...'' (C reads the extra arguments from the last fixed one) | ' +
        '''V'' is variadic: a variadic routine cannot share its name with another routine | ' +
        '''U'' is variadic: a variadic routine cannot share its name with another routine',
        'decls.routines: messages ' + DoMessagesText(AErrors));
      Check(DoNotesText(AErrors) =
        'SM0306@12^11 SM0306@16^15 SM0306@20^19 SM0306@25^24 SM0306@29^28 SM0327@87 SM0326@88 SM0326@89 SM0327@93 SM0004@95^95 SM0307@32^33 SM0324@39^36 ' +
        'SM0324@45^42 SM0324@48^36 SM0323@52^55 SM0323@58^61 SM0330@58^61 SM0325@64 SM0330@70^73 SM0330@79^76',
        'decls.routines: notes ' + DoNotesText(AErrors));
      // The forward A is completed by the full A; the overloaded clink sets are
      // C++ linkage, a single clink routine keeps C linkage; libraries resolve
      LForwardA := nil;
      LFullA := nil;
      LLinkage := '';
      LLibs := '';
      for LItem in AModule.Decls do
      begin
        if LItem is TPCRoutine then
        begin
          LRoutine := TPCRoutine(LItem);
          if LRoutine.DeclName = 'A' then
          begin
            if LRoutine.IsForward then
              LForwardA := LRoutine
            else
              LFullA := LRoutine;
          end;
          if (LRoutine.DeclName = 'P') or (LRoutine.DeclName = 'W') or (LRoutine.DeclName = 'Q') or
            (LRoutine.DeclName = 'Q2') then
            LLinkage := LLinkage + LRoutine.DeclName + '=' +
              GetEnumName(TypeInfo(TPCLinkage), Ord(LRoutine.ResolvedLinkage)) + ' ';
          if LRoutine.DeclName.StartsWith('R') then
            LLibs := LLibs + LRoutine.DeclName + '=' + LRoutine.ExternalClause.ResolvedLib + ' ';
        end
        else if LItem is TPCVarDecl then
          LLibs := LLibs + TPCVarDecl(LItem).DeclName + '=' + TPCVarDecl(LItem).ExternalClause.ResolvedLib + ' ';
      end;
      Check((LForwardA <> nil) and (LFullA <> nil) and (LForwardA.ResolvedFull = LFullA),
        'decls.routines: forward A resolves to the full A');
      Check(LLinkage = 'P=lnCpp P=lnCpp W=lnCpp W=lnCpp Q=lnC Q2=lnC ', 'decls.routines: linkage ' + LLinkage);
      Check(LLibs = 'R1=m R2= R3= R4= R5=user32 V1=m V2= ', 'decls.routines: libraries ' + LLibs);
    end);
end;

procedure TPCSemanticsTests.DoTestCallsRank();
begin
  // Expected texts: python scripts\zb_sem\gen_calls.py (from its SC01 table)
  DoWithSem(TPath.Combine(DoCallsDir(), 'sc01_calls.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      // An overload set call considers the members PaskalCPP's conversions
      // accept (F18: none = SM0402, one = bound), clang picks among them; the
      // arguments of the one routine SEM binds convert by the no-loss rule
      // (SM0404); a lone routine's argument count is PaskalCPP's (F51: SM0401);
      // a value whose type is no routine type is not callable (F58: SM0400)
      Check(DoReportsText(AErrors) =
        'SM0404/esError@47:6 SM0402/esError@56:3 SM0402/esError@57:3 SM0401/esError@58:3 SM0404/esError@59:5 SM0404/esError@60:5 SM0405/esError@62:5 ' +
        'SM0405/esError@63:5 SM0406/esError@64:9 SM0400/esError@65:3 SM0401/esError@67:3 SM0412/esError@69:3',
        'calls.rank: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        'argument 1 of ''A2'': ''array[0..4] of int32'' does not convert implicitly to ''array[0..3] of int32'' | no overload of ''F1'' takes (string) | ' +
        'no overload of ''G'' takes (int64) | ''H'' takes 1 argument(s), 2 given | ' +
        'argument 1 of ''H'': ''int64'' does not convert implicitly to ''int32''; write int32(LI64) | ' +
        'argument 1 of ''H'': ''string'' does not convert implicitly to ''int32'' | var parameter ''A'' needs a variable of type ''int32'' | ' +
        'var parameter ''A'' needs a variable of type ''int32'' | ''P()'' calls a procedure: it has no value | ' +
        '''LI32'' is not callable: its type ''int32'' is not a routine type | ''LFn'' takes 1 argument(s), 0 given | ' +
        'a cast ''TAlias(...)'' takes exactly one argument, given 2',
        'calls.rank: messages ' + DoMessagesText(AErrors));
      Check(DoNotesText(AErrors) =
        'SM0404@47 SM0402@56^15^16 SM0402@57^27^28 SM0401@58 SM0404@59 SM0404@60 SM0405@62 SM0405@63 SM0406@64 SM0400@65 SM0401@67 SM0412@69',
        'calls.rank: notes ' + DoNotesText(AErrors));
      Check(DoPicksText(AModule) =
        'L46@13:int32 L47@14:int32 L48:int32 L49@16:int32 L50:int32 L51:int32 L52@22:int32 L53:int32 L54@24:int32 L55:int32 L56:! L57:! L58@29:int32 ' +
        'L59@29:int32 L60@29:int32 L61@29:int32 L62@30:void L63@30:void L64@31:! L65@36:! L66@42:int32 L67@42:int32 L68@3:TAlias L69@3:! L70@3:TAlias ' +
        'L71:int32 L72@32:void L73@32:void',
        'calls.rank: picks ' + DoPicksText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestCallsIntrinsics();
begin
  // Expected texts: python scripts\zb_sem\gen_calls.py (from its SC02 table)
  DoWithSem(TPath.Combine(DoCallsDir(), 'sc02_intrinsics.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) =
        'SM0409/esError@32:15 SM0409/esError@34:14 SM0409/esError@36:11 SM0409/esError@38:18 SM0409/esError@41:16 SM0409/esError@44:23 SM0409/esError@46:11 ' +
        'SM0409/esError@50:17 SM0409/esError@51:13 SM0361/esError@52:10 SM0361/esError@54:11 SM0409/esError@56:10 SM0409/esError@57:11 SM0409/esError@61:13 ' +
        'SM0409/esError@62:13 SM0615/esError@63:11 SM0615/esError@64:9 SM0408/esError@65:11 SM0409/esError@69:22 SM0410/esError@75:16 SM0409/esError@76:11 ' +
        'SM0411/esError@77:19 SM0423/esError@78:11 SM0425/esError@80:17 SM0425/esError@81:17 SM0425/esError@82:15',
        'calls.intrinsics: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        '''len'' takes (string, wstring or array) | ''utf8'' takes (wstring) | ''paramcount'' takes () | ''paramstr'' takes (int32) | ' +
        '''getmem'' takes (int64) | ''resizemem'' takes (pointer, int64) | ''freemem'' takes (pointer) | ' +
        '''setlength'' takes (dynamic array or string variable, int64) | ''setlength'' takes (dynamic array or string variable, int64) | ' +
        'create does not build an object (''TObj'' is one): write own TObj(...) or ref TObj(...) | ' +
        'destroy does not free an object (''TObj'' is one): the own or ref that holds it frees it | ''create'' takes (record, overlay or C/C++ pointer variable) | ' +
        '''destroy'' takes (record, overlay or C/C++ pointer) | ''raisecode'' takes (int32, string) | ''raisecode'' takes (int32, string) | ' +
        '''exccode'' outside an except body | ''excmsg'' outside an except body | ''freemem'' is a statement, not a value | ' +
        '''testAssertEqualInt'' takes (int64, int64) | size needs a type, got the value ''LI32'' | ''size'' takes (a type) | ' +
        '''LQ.next'' takes no type argument: only size does | ''len'' is an intrinsic: it is called, never used as a value | ' +
        '''TRec'' cannot be printed: print the fields of a record, object or overlay | ' +
        '''TObj'' cannot be printed: print the fields of a record, object or overlay | ' +
        '''array[0..0] of TRec'' cannot be printed: print the fields of a record, object or overlay',
        'calls.intrinsics: messages ' + DoMessagesText(AErrors));
      Check(DoNotesText(AErrors) =
        'SM0409@32 SM0409@34 SM0409@36 SM0409@38 SM0409@41 SM0409@44 SM0409@46 SM0409@50 SM0409@51 SM0361@52 SM0361@54 SM0409@56 SM0409@57 SM0409@61 SM0409@62 ' +
        'SM0615@63 SM0615@64 SM0408@65 SM0409@69 SM0410@75 SM0409@76 SM0411@77 SM0423@78 SM0425@80 SM0425@81 SM0425@82',
        'calls.intrinsics: notes ' + DoNotesText(AErrors));
      Check(DoPicksText(AModule) =
        'L11:int64 L29:int64 L30:int64 L31:int64 L32:! L33:string L34:! L35:int32 L36:! L37:string L38:! L39:ptr L40:ptr L41:! L42:ptr L43:ptr L44:! L45:void ' +
        'L46:! L47:void L48:void L49:void L50:! L51:! L52:! L53:void L54:! L55:void L56:! L57:! L58:void L59:void L60:void L61:! L62:! L63:int32 L64:string ' +
        'L65:! L66:void L67:void L68:void L69:! L70:void L71:void L72:int64 L73:int64 L74:int64 L75:! L76:! L77@6:! L79:void L80:void L81:void L82:void',
        'calls.intrinsics: picks ' + DoPicksText(AModule));
      // sizeof is clang's: every size call is a constant without a PaskalCPP value
      Check(DoSizesText(AModule) = 'S11:19=? S72:11=? S73:11=? S74:11=? S75:11=! S76:11=!',
        'calls.intrinsics: sizes ' + DoSizesText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestCallsUpcast();
begin
  // Expected texts: python scripts\zb_sem\gen_calls.py (from its SC05 table)
  DoWithSem(TPath.Combine(DoCallsDir(), 'sc05_upcast.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      // PLAN-RECORDS A4: an extension converts to its base (value, const,
      // var, pointer); SEM writes every pointer upcast, inherited member,
      // downcast and tag-ranked overload call for the emitter (M10 / M12 / M13)
      Check(DoReportsText(AErrors) =
        'SM0200/esError@81:10 SM0200/esError@82:10 SM0405/esError@83:5',
        'calls.upcast: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        '''ptr to TBase'' does not convert implicitly to ''ptr to TExt''; write ptr to TExt(LPB) | ' +
        '''ptr to TOther'' does not convert implicitly to ''ptr to TBase''; write ptr to TBase(address of LO) | ' +
        'var parameter ''A'' needs a variable of type ''TExt''',
        'calls.upcast: messages ' + DoMessagesText(AErrors));
      Check(DoNotesText(AErrors) =
        'SM0200@81 SM0200@82 SM0405@83',
        'calls.upcast: notes ' + DoNotesText(AErrors));
      Check(DoPicksText(AModule) =
        'L60@22:int32 L61@23:void L62@25:int32 L63@26:int32 L76:int32 L77@27:int32 L78:int32 L79:int32 L80@31:int32 L83@24:void',
        'calls.upcast: picks ' + DoPicksText(AModule));
      Check(DoUpcastsText(AModule) =
        'U35:10=1 U55:10=1 U56:10=2 U57:10=2 U58:11=1 U60:11=1 U63:12=1 U64:9=1 U65:16=2 U66:15=1 U67:23=1 D68:11=2 D69:10=1 D70:10=1 P72:3=2 P73:3=1 P75:3=1 ' +
        'R76:9=2 R78:9=2 R79:9=2 U80:11=1 U84:10=2',
        'calls.upcast: upcasts ' + DoUpcastsText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestCallsValues();
begin
  // Expected texts: python scripts\zb_sem\gen_calls.py (from its SC06 table)
  DoWithSem(TPath.Combine(DoCallsDir(), 'sc06_values.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      // PLAN-RECORDS A5: a routine named as a value against the routine type it goes into (D1, R5)
      Check(DoReportsText(AErrors) =
        'SM0200/esError@40:9 SM0200/esError@41:9 SM0200/esError@42:9 SM0200/esError@43:9 SM0200/esError@44:9 SM0200/esError@45:9 SM0200/esError@46:9 ' +
        'SM0200/esError@47:9 SM0200/esError@48:9 SM0200/esError@49:9 SM0200/esError@50:9 SM0404/esError@51:14 SM0404/esError@52:14 SM0405/esError@53:9',
        'calls.values: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        '''routine(const AA: int32): int32'' does not convert implicitly to ''TFn'' | ' +
        '''routine(const AA: int64; const AB: int32): int32'' does not convert implicitly to ''TFn'' | ' +
        '''routine(var AA: int32; const AB: int32): int32'' does not convert implicitly to ''TFn'' | ' +
        '''routine(const AA: int32; const AB: int32): int64'' does not convert implicitly to ''TFn'' | ' +
        '''routine(const AA: int32; const AB: int32)'' does not convert implicitly to ''TFn'' | ' +
        '''routine(const AA: int32; const AB: int32; ...): int32'' does not convert implicitly to ''TFn'' | ' +
        '''routine clink(const AA: int32): int32'' does not convert implicitly to ''TFp'' | ' +
        '''routine(const AA: int32): int32'' does not convert implicitly to ''TFc'' | ''TFc'' does not convert implicitly to ''TFp'' | ' +
        'overload set ''Set1'' has no member of type ''TFn'' | ''routine(const AA: int32; const AB: int32): int32'' does not convert implicitly to ''int32'' | ' +
        'argument 1 of ''Take'': ''routine(const AA: int32): int32'' does not convert implicitly to ''TFn'' | ' +
        'argument 1 of ''Take'': overload set ''Set1'' has no member of type ''TFn'' | var parameter ''AF'' needs a variable of type ''TFn''',
        'calls.values: messages ' + DoMessagesText(AErrors));
      Check(DoNotesText(AErrors) =
        'SM0200@40^8 SM0200@41^9 SM0200@42^10 SM0200@43^11 SM0200@44^12 SM0200@45^13 SM0200@46^14 SM0200@47^8 SM0200@48 SM0200@49^15^16 SM0200@50 SM0404@51^8 ' +
        'SM0404@52^15^16 SM0405@53',
        'calls.values: notes ' + DoNotesText(AErrors));
      Check(DoPicksText(AModule) =
        'L36@17:int32 L37@18:int32 L38@20:int32 L39@21:int32 L51@17:int32 L52@17:int32 L53@19:void',
        'calls.values: picks ' + DoPicksText(AModule));
      Check(DoNoteTextsText(AErrors) =
        'parameter count 1 here, 2 in ''TFn'' | parameter 1 is ''const int64'' here, ''const int32'' in ''TFn'' | ' +
        'parameter 1 is ''var int32'' here, ''const int32'' in ''TFn'' | returns ''int64'' here, ''int32'' in ''TFn'' | ' +
        'returns no value here, ''int32'' in ''TFn'' | takes ''...'' here, not in ''TFn'' | clink here, cpplink in ''TFp'' | cpplink here, clink in ''TFc'' | ' +
        'an overload of ''Set1'': (const int32) | an overload of ''Set1'': (const string) | parameter count 1 here, 2 in ''TFn'' | ' +
        'an overload of ''Set1'': (const int32) | an overload of ''Set1'': (const string)',
        'calls.values: notetexts ' + DoNoteTextsText(AErrors));
      Check(DoBindsText(AModule) =
        'B35:9=15 B37:15=15',
        'calls.values: binds ' + DoBindsText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestCallsMisaligned();
begin
  // Expected texts: python scripts\zb_sem\gen_calls.py (from its SC07 table)
  DoWithSem(TPath.Combine(DoCallsDir(), 'sc07_misaligned.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      // PLAN-RECORDS A8: what a packed level may misalign never binds a writable
      // reference (SM0270, M8 + F-R4f); a const reference gets a copy
      Check(DoReportsText(AErrors) =
        'SM0270/esError@50:5 SM0270/esError@51:5 SM0270/esError@52:5 SM0270/esError@53:5 SM0270/esError@54:5 SM0270/esError@55:5 SM0270/esError@56:6 ' +
        'SM0270/esError@57:6 SM0270/esError@58:20 SM0270/esError@70:6 SM0270/esError@72:10 SM0270/esError@73:6 SM0270/esError@74:6 SM0270/esError@106:3 ' +
        'SM0270/esError@107:3 SM0200/esError@108:9 SM0250/esError@109:3 SM0250/esError@110:9 SM0270/esError@111:3',
        'calls.misaligned: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        'var parameter ''A'' cannot take ''LP.I'': a packed record holds it, it may be misaligned | ' +
        'var parameter ''A'' cannot take ''LP.Q[1]'': a packed record holds it, it may be misaligned | ' +
        'var parameter ''A'' cannot take ''LH.K.I'': a packed record holds it, it may be misaligned | ' +
        'var parameter ''A'' cannot take ''LH.K.R.A'': a packed record holds it, it may be misaligned | ' +
        'var parameter ''A'' cannot take ''LPP^.I'': a packed record holds it, it may be misaligned | ' +
        'var parameter ''A'' cannot take ''LPP->I'': a packed record holds it, it may be misaligned | ' +
        'var parameter ''A'' cannot take ''LP.R'': a packed record holds it, it may be misaligned | ' +
        'reference parameter ''AR'' cannot take ''LP.I'': a packed record holds it, it may be misaligned | ' +
        'cannot take the address of ''LP.I'': a packed record holds it, it may be misaligned | ' +
        '''LE'' cannot be used as ''TBase'': packed ''TPe'' holds that part, it may be misaligned | ' +
        '''address of LE'' cannot be used as ''ptr to TBase'': packed ''TPe'' holds that part, it may be misaligned | ' +
        '''LPE'' cannot be used as ''ptr to TBase'': packed ''TPe'' holds that part, it may be misaligned | ' +
        '''LPE'' cannot be used as ''ptr to TB0'': packed ''TPe'' holds that part, it may be misaligned | ' +
        '''+='' cannot write to ''LS.S'': a packed record holds it, it may be misaligned | ' +
        '''|='' cannot write to ''LS.S'': a packed record holds it, it may be misaligned | ''int32'' does not convert implicitly to ''TS'' | ' +
        'operator ''/='' does not take ''TS'' and ''TS'' | operator ''/'' does not take ''TS'' and ''TS'' | ' +
        '''+='' cannot write to ''LP.Q'': a packed record holds it, it may be misaligned',
        'calls.misaligned: messages ' + DoMessagesText(AErrors));
      Check(DoNotesText(AErrors) =
        'SM0270@50 SM0270@51 SM0270@52 SM0270@53 SM0270@54 SM0270@55 SM0270@56 SM0270@57 SM0270@58 SM0270@70 SM0270@72 SM0270@73 SM0270@74 SM0270@106 ' +
        'SM0270@107 SM0200@108 SM0250@109 SM0250@110 SM0270@111',
        'calls.misaligned: notes ' + DoNotesText(AErrors));
      Check(DoPicksText(AModule) =
        'L50@24:void L51@24:void L52@24:void L53@24:void L54@24:void L55@24:void L56@26:void L57@32:void L59@25:void L60@26:void L61@24:void L63@27:void ' +
        'L64@27:void L65@33:void L66@34:void L67:void L68@28:void L69@27:void L70@29:void L71@30:void L73@31:void L74:void L75:void L93:int64 L98:void ' +
        'L99:int64',
        'calls.misaligned: picks ' + DoPicksText(AModule));
      Check(DoCopiesText(AModule) =
        'C63:6 C64:6 C65:6 C66:9 C67:20 C93:13 C94:9 C95:16 C96:14 C97:10 C98:17 C105:9 C112:10',
        'calls.misaligned: copies ' + DoCopiesText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestStmtRules();
begin
  // Expected texts: python scripts\zb_sem\gen_stmts.py (from its SS01 table)
  DoWithSem(TPath.Combine(DoStmtDir(), 'ss01_stmts.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) =
        'SM0602/esError@20:5 SM0602/esError@21:5 SM0602/esError@22:7 SM0602/esError@24:5 SM0600/esError@29:3 SM0600/esError@31:3 SM0601/esError@33:3 ' +
        'SM0601/esError@39:3 SM0604/esError@47:5 SM0605/esError@48:5 SM0267/esError@49:5 SM0604/esError@50:5 SM0606/esWarning@52:3 SM0603/esError@63:9 ' +
        'SM0202/esError@67:5 SM0015/esError@73:5 SM0607/esError@80:3 SM0608/esError@81:3 SM0609/esError@92:7 SM0609/esError@106:5 SM0610/esError@111:3 ' +
        'SM0611/esError@115:10 SM0612/esError@122:1 SM0612/esError@152:1 SM0612/esError@161:1 SM0613/esError@166:3 SM0613/esError@167:3 SM0613/esError@173:3 ' +
        'SM0614/esError@181:13 SM0614/esError@189:7 SM0614/esError@208:5',
        'stmt.rules: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        '''LI'' is the for iterator: the loop body cannot write it | ''LI'' is the for iterator: the loop body cannot write it | ' +
        '''LI'' is the for iterator: the loop body cannot write it | ''LI'' is the for iterator: the loop body cannot write it | ' +
        'for needs a variable: ''AC'' is a const parameter | for needs a variable: ''CMax'' is a constant | ' +
        'a for iterator is an integer, char, wchar or a choice, got ''bool'' | a for iterator is an integer, char, wchar or a choice, got ''string'' | ' +
        'match label 300 is outside ''uint8'': it never matches | match label 4 repeats a label of the arm at line 46 | low bound 9 exceeds high bound 7 | ' +
        'match label -1 is outside ''uint8'': it never matches | match on ''TColor'' does not cover: cGreen, cBlue | ' +
        'a match subject is an integer, char, wchar or a choice, got ''string'' | a match label must be a constant | ' +
        '''cRed'' is a choice value: write TColor.cRed | leave outside a loop or match | skip outside a loop | skip cannot jump out of finally | ' +
        'return cannot jump out of finally | return needs a value of type ''int32'' | return takes no value here | ' +
        'missing return: ''R3'' can reach its end without returning a value | missing return: ''R7'' can reach its end without returning a value | ' +
        'missing return: ''R9'' can reach its end without returning a value | statement has no effect | statement has no effect | statement has no effect | ' +
        'C++ return in a guard body leaves only the guard''s hidden function | C++ break in a guard body leaves only the guard''s hidden function | ' +
        'C++ return in a finally body leaves only the finally''s hidden function',
        'stmt.rules: messages ' + DoMessagesText(AErrors));
      Check(DoNotesText(AErrors) =
        'SM0602@20 SM0602@21 SM0602@22 SM0602@24 SM0600@29 SM0600@31 SM0601@33 SM0601@39 SM0604@47 SM0605@48^46 SM0267@49 SM0604@50 SM0606@52 SM0603@63 ' +
        'SM0202@67 SM0015@73 SM0607@80 SM0608@81 SM0609@92 SM0609@106 SM0610@111 SM0611@115 SM0612@122 SM0612@152 SM0612@161 SM0613@166 SM0613@167 SM0613@173 ' +
        'SM0614@181 SM0614@189 SM0614@208',
        'stmt.rules: notes ' + DoNotesText(AErrors));
      // What SEM resolved (C3): iterators, jump targets, routines, guard escapes
      Check(DoFlowsText(AModule) =
        'F16@10 F19@10 F24@10 F27@8 F29- F31- F33@12 F35@14 F37- F39@13 J80- J81- J83@82 J84@82 J86@85 J87@82 G89=l J90@82 J92- G96=rs J97@95 R98@76 G103=r ' +
        'R104@76 R106@76 R111@109 R115@113 R120@117 R126@123 R134@131 R136@131 G141=r R142@139 R144@139 R150@147 G179= G187= G195= G204= R213-',
        'stmt.rules: flows ' + DoFlowsText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestCallsRecords();
begin
  // Expected texts: python scripts\zb_sem\gen_records.py (from its SC03 table)
  DoWithSem(TPath.Combine(DoCallsDir(), 'sc03_records.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) =
        'SM0416/esError@35:22 SM0415/esError@36:22 SM0414/esError@37:16 SM0200/esError@38:19 SM0416/esError@43:22 SM0414/esError@44:20 SM0413/esError@45:9 ' +
        'SM0413/esError@46:9 SM0413/esError@47:9',
        'calls.records: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        'record literal: ''x'' comes before ''y'' in ''TPoint'' | record literal: field ''x'' is given twice | record literal: ''TPoint'' has no field ''w'' | ' +
        '''string'' does not convert implicitly to ''int32'' | record literal: ''a'' comes before ''b'' in ''TDer2'' | ' +
        'record literal: ''TDer'' has no field ''c2'' | a record literal needs a record with no C/C++ parent: ''TQ'' is not one | ' +
        'a record literal needs a record with no C/C++ parent: ''TObj'' is not one | a record literal needs a record with no C/C++ parent: ''TNum'' is not one',
        'calls.records: messages ' + DoMessagesText(AErrors));
      Check(DoNotesText(AErrors) = 'SM0416@35 SM0415@36 SM0414@37 SM0200@38 SM0416@43 SM0414@44 SM0413@45 SM0413@46 SM0413@47',
        'calls.records: notes ' + DoNotesText(AErrors));
      // ResolvedField of every field init (C3)
      Check(DoFieldInitsText(AModule) =
        'I33@4 I33@5 I33@6 I34@4 I34@6 I35@5 I35@4 I36@4 I36@4 I37- I38@4 I39@4 I39@5 I40@9 I40@12 I41@9 I41@12 I41@15 I42@15 I43@12 I43@9 I44@9 I44- I45- ' +
        'I46- I47- I48-',
        'calls.records: field inits ' + DoFieldInitsText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestCallsVarargs();
begin
  // Expected texts: python scripts\zb_sem\gen_varargs.py (from its SC04 table)
  DoWithSem(TPath.Combine(DoCallsDir(), 'sc04_varargs.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) =
        'SM0422/esError@6:8 SM0422/esError@8:7 SM0422/esError@9:18 SM0422/esError@17:17 SM0200/esError@22:21 SM0422/esError@25:9 SM0409/esError@32:9 ' +
        'SM0409/esError@33:9 SM0009/esError@34:3 SM0409/esError@35:9 SM0424/esError@36:9 SM0424/esError@37:9 SM0421/esError@38:9 SM0421/esError@39:9 ' +
        'SM0418/esError@46:9 SM0418/esError@47:3 SM0422/esError@51:7 SM0417/esError@53:3',
        'calls.varargs: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        '''varargs'' is only the type of a variadic routine''s local, set from a copy() | ' +
        '''varargs'' is only the type of a variadic routine''s local, set from a copy() | ' +
        '''varargs'' is only the type of a variadic routine''s local, set from a copy() | ' +
        '''varargs'' is only the type of a variadic routine''s local, set from a copy() | ''string'' does not convert implicitly to ''int32'' | ' +
        '''varargs'' is only the type of a variadic routine''s local, set from a copy() | ''LC.next'' takes (a type) | ''LC.get'' takes (integer, a type) | ' +
        '''varargs'' has no member ''foo'' | ''LC.next'' takes (a type) | ''LC.count'' is a value, not a call: write it without () | ' +
        '''varargs.count'' is a value, not a call: write it without () | ''varargs'' is not a value: use varargs.count, next, get, reset or copy | ' +
        '''varargs'' is not a value: use varargs.count, next, get, reset or copy | ' +
        'varargs.count needs a cpplink variadic: a C caller passes no types or count | ' +
        'varargs.reset needs a cpplink variadic: a C caller passes no types or count | ' +
        '''varargs'' is only the type of a variadic routine''s local, set from a copy() | varargs outside a variadic routine',
        'calls.varargs: messages ' + DoMessagesText(AErrors));
      Check(DoNotesText(AErrors) =
        'SM0422@6 SM0422@8 SM0422@9 SM0422@17 SM0200@22 SM0422@25 SM0409@32 SM0409@33 SM0009@34 SM0409@35 SM0424@36 SM0424@37 SM0421@38 SM0421@39 SM0418@46 ' +
        'SM0418@47 SM0422@51 SM0417@53',
        'calls.varargs: notes ' + DoNotesText(AErrors));
      // The type of every varargs form and every call on a varargs local (C3)
      Check(DoVarargsText(AModule) =
        'V16:varargs V19:int32 V20:int32 V21:string V22:string V23:void V24:varargs V37:int32 V38:! V39:! V45:int32 V46:! V47:! V53:!',
        'calls.varargs: forms ' + DoVarargsText(AModule));
      Check(DoPicksText(AModule) = 'L26:varargs L28:int32 L29:TPoint L30:string L31:void L32:! L33:! L34:! L36:! L37:!',
        'calls.varargs: picks ' + DoPicksText(AModule));
    end);
end;

procedure TPCSemanticsTests.DoTestDeclsValues();
begin
  // Expected texts: python scripts\zb_sem\gen_decls.py (from its SD03 table)
  DoWithSem(TPath.Combine(DoDeclsDir(), 'sd03_values.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) =
        'SM0269/esError@8:14 SM0269/esError@9:14 SM0269/esError@11:17 SM0269/esError@12:14 SM0269/esError@13:15 SM0269/esError@14:14 SM0269/esError@17:3 ' +
        'SM0269/esError@18:8 SM0269/esError@19:8',
        'decls.values: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        '''TPoint'' is a type, not a value | ''sd_u1'' is a module, not a value | ''TPoint'' is a type, not a value | ''TPoint'' is a type, not a value | ' +
        '''TPoint'' is a type, not a value | ''TPoint'' is a type, not a value | ''TPoint'' is a type, not a value | ''TPoint'' is a type, not a value | ' +
        '''sd_u1'' is a module, not a value',
        'decls.values: messages ' + DoMessagesText(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestDeclsLayout();
begin
  // Expected texts: python scripts\zb_sem\gen_decls.py (from its SD02 table)
  DoWithSem(TPath.Combine(DoDeclsDir(), 'sd02_layout.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) =
        'SM0308/esError@16:16 SM0308/esError@19:16 SM0309/esError@23:5 SM0308/esError@31:16 SM0308/esError@34:16 SM0310/esError@40:22 SM0312/esError@43:22 ' +
        'SM0311/esError@46:22 SM0311/esError@55:22 SM0311/esError@58:27 SM0311/esError@61:22 SM0315/esError@72:17 SM0315/esError@73:17 SM0315/esError@75:16 ' +
        'SM0315/esError@76:17 SM0314/esError@77:5 SM0316/esError@78:15 SM0314/esError@80:5 SM0315/esError@82:17 SM0315/esError@83:15 SM0316/esError@84:16 ' +
        'SM0313/esError@89:5 SM0313/esError@92:7 SM0313/esError@99:7 SM0313/esError@103:5 SM0313/esError@104:5 SM0318/esError@110:16 SM0319/esError@111:16 ' +
        'SM0329/esError@112:16 SM0328/esError@115:16 SM0321/esError@116:9 SM0320/esError@118:9 SM0321/esError@120:9 SM0328/esError@122:16 ' +
        'SM0322/esError@123:10 SM0322/esError@125:10 SM0311/esError@139:22 SM0311/esError@142:22 SM0311/esError@145:22 SM0357/esError@151:8 ' +
        'SM0331/esError@152:5 SM0331/esError@153:5 SM0331/esError@154:5 SM0331/esError@155:5 SM0313/esError@161:7 SM0331/esError@165:17 SM0313/esError@170:7 ' +
        'SM0009/esError@193:3',
        'decls.layout: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        '''TOB'' cannot be the parent of a record | ''TBase'' cannot be the parent of an object | ''B'' reuses a name of the parent chain | ' +
        '''TCh'' cannot be the parent of a record | ''TFw'' cannot be the parent of a record | align 3 is not a power of two | align 16384 exceeds 8192 | ' +
        'align 2 is below the natural alignment 4 of ''TA3'', lower it with packed | ' +
        'align 1 is below the natural alignment 8 of ''TA6'', lower it with packed | ' +
        'align 2 is below the natural alignment 4 of ''TA7'', lower it with packed | ' +
        'align 4 is below the natural alignment 8 of ''TA8'', lower it with packed | bitfield width 33 outside 1..32 | bitfield width 0 outside 1..8 | ' +
        'bitfield width 9 outside 1..8 | bitfield width 17 outside 1..16 | a bitfield is an integer, bool, char, wchar or choices field | ' +
        'bitfield width 2 does not hold the ordinals of ''TCh'' as signed values | a bitfield is an integer, bool, char, wchar or choices field | ' +
        'bitfield width 65 outside 1..64 | bitfield width 33 outside 1..32 | bitfield width 3 does not hold the ordinals of ''TPal'' as signed values | ' +
        'field ''S'' of ''TOv'' cannot share an overlay''s storage: ''string'' holds a string or dynamic array, hold a ptr to it | ' +
        'field ''L'' of ''TOv'' cannot share an overlay''s storage: ''wstring'' holds a string or dynamic array, hold a ptr to it | ' +
        'field ''M2'' of ''TRo'' cannot share an overlay''s storage: ''array of int32'' holds a string or dynamic array, hold a ptr to it | ' +
        'field ''R'' of ''TOv3'' cannot share an overlay''s storage: ''TA6'' holds a string or dynamic array, hold a ptr to it | ' +
        'field ''RA'' of ''TOv3'' cannot share an overlay''s storage: ''array[0..1] of TA6'' holds a string or dynamic array, hold a ptr to it | ' +
        'a set of integers names its range: set of 0..255 | set of wchar: its size differs by target: write set of 0..65535 | ' +
        'a set element is char, bool or choices: ''float64'' is not | low bound 5 is above high bound 1 | a set has at most 65536 members, this one 65537 | ' +
        'set range bounds are of different ordinal families | a set has at most 65536 members, this one 18446744073709551617 | ' +
        'low bound 9 is above high bound 0 | array bounds are integer, char or choices of one family | ' +
        'array bounds are integer, char or choices of one family | align 2 is below the natural alignment 8 of ''TAF'', lower it with packed | ' +
        'align 1 is below the natural alignment 2 of ''TAG'', lower it with packed | ' +
        'align 4 is below the natural alignment 8 of ''TAH'', lower it with packed | ' +
        'field ''O'': a record or an overlay holds no object (''TOB'' is one): it is plain data, hold a ptr to the object | ' +
        'field ''S'' of packed record ''TPk1'' cannot be packed: ''string'' holds a string or dynamic array | ' +
        'field ''D'' of packed record ''TPk1'' cannot be packed: ''array of int32'' holds a string or dynamic array | ' +
        'field ''R'' of packed record ''TPk1'' cannot be packed: ''TA6'' holds a string or dynamic array | ' +
        'field ''A'' of packed record ''TPk1'' cannot be packed: ''array[0..1] of string'' holds a string or dynamic array | ' +
        'field ''W'' of ''TPk1'' cannot share an overlay''s storage: ''wstring'' holds a string or dynamic array, hold a ptr to it | ' +
        'the parent of packed record ''TPk2'' cannot be packed: ''TA6'' holds a string or dynamic array | ' +
        'field ''Q'' of ''TOv2'' cannot share an overlay''s storage: ''string'' holds a string or dynamic array, hold a ptr to it | ' +
        '''TR1'' has no member ''Nope''',
        'decls.layout: messages ' + DoMessagesText(AErrors));
      // The SM0309 report carries a note at the parent's field (TOB.B, line 8)
      Check(DoNotesText(AErrors).Contains('SM0309@23^8'),
        'decls.layout: the SM0309 note points at TOB.B: ' + DoNotesText(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestDeclsLayoutLinux();
begin
  // wchar is 4 on linux-gnu (PC_ALIGN_MODELS), so align(2) is below its natural alignment
  // there and not on windows-gnu (decls.layout TAB). Expected texts: python
  // scripts\zb_sem\gen_decls.py (from its SD02L table)
  DoWithSem(TPath.Combine(DoDeclsDir(), 'sd02_linux.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoReportsText(AErrors) =
        'SM0311/esError@4:22 SM0311/esError@13:22',
        'decls.layout_linux: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        'align 2 is below the natural alignment 4 of ''TW1'', lower it with packed | align 1 is below the natural alignment 2 of ''TW4'', lower it with packed',
        'decls.layout_linux: messages ' + DoMessagesText(AErrors));
    end);
end;

procedure TPCSemanticsTests.DoTestDeclsForwards();
begin
  // Expected texts: python scripts\zb_sem\gen_decls.py (from its SD01 / SD01_ORDINALS tables)
  DoWithSem(TPath.Combine(DoDeclsDir(), 'sd01_decls.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LForward: TPCDecl;
      LItem: TPCStmt;
      LFull: TPCTypeDecl;
    begin
      Check(DoReportsText(AErrors) =
        'SM0300/esError@6:8 SM0300/esError@7:23 SM0300/esError@10:8 SM0004/esError@23:1 SM0304/esError@28:1 SM0305/esError@31:3 SM0306/esError@34:3 ' +
        'SM0256/esError@39:67 SM0200/esError@39:80 SM0200/esError@41:21 SM0301/esError@44:15 SM0269/esError@45:15 SM0302/esError@48:3 SM0303/esError@37:1',
        'decls.forwards: reports ' + DoReportsText(AErrors));
      Check(DoMessagesText(AErrors) =
        '''TA'' is only forward-declared: use ptr to ''TA'' or declare it first | ''TA'' is only forward-declared: use ptr to ''TA'' or declare it first | ' +
        '''TA'' is only forward-declared: use ptr to ''TA'' or declare it first | ''TC'' is already declared in this scope | ' +
        '''TC'' is already declared: a forward after its full declaration declares nothing | a forward type is completed by a record, object or overlay | ' +
        'forward and full declaration of ''TE'' differ: one is exported, the other is not | constant overflows ''int64'' | ' +
        '18446744073709551615 does not fit in ''int64'' (-9223372036854775808..9223372036854775807) | ' +
        '''float64'' does not convert implicitly to ''int64''; write int64(2.5) | an external variable takes no initializer | ''TB'' is a type, not a value | ' +
        'an external variable is declared at module level only | forward type ''TF'' has no full declaration here',
        'decls.forwards: messages ' + DoMessagesText(AErrors));
      // B = A * 2 folds (F27): B = 6, the implicit C after it 7 (gen_decls.py SD01_ORDINALS)
      Check(DoOrdinalsText(AModule) =
        'Red=0 Green=5 Blue=6 Big=9223372036854775807 Over=- Huge=- After=- A=3 B=6 C=7 P=-',
        'decls.forwards: ordinals ' + DoOrdinalsText(AModule));
      // The forward TA is completed by the full TA (the record), before TA's
      // own fields were analyzed
      LForward := DoDeclNamed(AModule, 'TA');
      LFull := nil;
      for LItem in AModule.Decls do
      begin
        if (LItem is TPCTypeDecl) and (TPCTypeDecl(LItem).DeclName = 'TA') and not TPCTypeDecl(LItem).IsForward then
          LFull := TPCTypeDecl(LItem);
      end;
      Check((LForward is TPCTypeDecl) and TPCTypeDecl(LForward).IsForward and (LFull <> nil) and
        (TPCTypeDecl(LForward).ResolvedFull = LFull), 'decls.forwards: forward TA resolves to the full TA');
      // A forward after its full names that full (no SM0303 cascade); every
      // TC forward reaches the one full TC
      LFull := nil;
      for LItem in AModule.Decls do
      begin
        if (LItem is TPCTypeDecl) and (TPCTypeDecl(LItem).DeclName = 'TC') and not TPCTypeDecl(LItem).IsForward then
          LFull := TPCTypeDecl(LItem);
      end;
      for LItem in AModule.Decls do
      begin
        if (LItem is TPCTypeDecl) and (TPCTypeDecl(LItem).DeclName = 'TC') and TPCTypeDecl(LItem).IsForward then
          Check((LFull <> nil) and (TPCTypeDecl(LItem).ResolvedFull = LFull),
            'decls.forwards: forward TC at line ' + IntToStr(LItem.Range.StartLine) + ' resolves to the full TC');
      end;
    end);
end;

function DoCalleeOf(const ARoutine: TPCRoutine; const AIndex: Integer): TPCName;
var
  LStmt: TPCStmt;
  LExpr: TPCExpr;
begin
  // The callee name of `L := F(...);`, statement AIndex of ARoutine's body;
  // nil when the shape is not that
  Result := nil;
  if (ARoutine = nil) or (ARoutine.Body = nil) or (AIndex >= ARoutine.Body.Stmts.Count) then
    Exit;
  LStmt := ARoutine.Body.Stmts[AIndex];
  if not (LStmt is TPCExprStmt) then
    Exit;
  LExpr := TPCExprStmt(LStmt).Expr;
  if not (LExpr is TPCAssign) then
    Exit;
  LExpr := TPCAssign(LExpr).ValueExpr;
  if (LExpr is TPCCall) and (TPCCall(LExpr).Callee is TPCName) then
    Result := TPCName(TPCCall(LExpr).Callee);
end;

procedure TPCSemanticsTests.DoTestOverloadSetMember();
begin
  // PLAN-EMITTER A2: an overload-set callee carries one member of the set
  // (its DeclModule spells the qualification); a single routine carries none
  DoWithSem(TPath.Combine(DoProbeDir('emit\own'), 'own2.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LMain: TPCRoutine;
      LFoo: TPCName;
      LBar: TPCName;
    begin
      Check(DoCodes(AErrors) = '', 'emit.overload_set_member: codes ' + DoCodes(AErrors));
      LMain := nil;
      if (AModule.Decls.Count = 4) and (AModule.Decls[3] is TPCRoutine) then
        LMain := TPCRoutine(AModule.Decls[3]);
      LFoo := DoCalleeOf(LMain, 0);
      LBar := DoCalleeOf(LMain, 1);
      Check((LFoo <> nil) and (LFoo.ResolvedKind = rkRoutine) and (LFoo.ResolvedDecl = nil) and
        (LFoo.ResolvedSetMember <> nil) and (LFoo.ResolvedSetMember.DeclName = 'Foo') and
        (LFoo.ResolvedSetMember.DeclModule = AModule),
        'emit.overload_set_member: Foo(1) carries a Foo of this module');
      Check((LBar <> nil) and (LBar.ResolvedDecl <> nil) and (LBar.ResolvedSetMember = nil),
        'emit.overload_set_member: Bar() resolves alone, no set member');
    end);
end;

function DoSetTypeOf(const AModule: TPCModule; const ADeclName: string): TPCSetType;
var
  LItem: TPCStmt;
begin
  // The set type defined by the module-level type declaration ADeclName
  Result := nil;
  for LItem in AModule.Decls do
  begin
    if (LItem is TPCTypeDecl) and (TPCTypeDecl(LItem).DeclName = ADeclName) and
      (TPCTypeDecl(LItem).TypeDef is TPCSetType) then
      Result := TPCSetType(TPCTypeDecl(LItem).TypeDef);
  end;
end;

function DoHasSetBounds(const AModule: TPCModule; const ADeclName: string; const ALow: Int64;
  const AHigh: Int64): Boolean;
var
  LType: TPCSetType;
begin
  LType := DoSetTypeOf(AModule, ADeclName);
  Result := (LType <> nil) and LType.HasResolvedBounds and (LType.ResolvedLow = ALow) and
    (LType.ResolvedHigh = AHigh);
end;

procedure TPCSemanticsTests.DoTestSetBounds();
begin
  // PLAN-EMITTER A2b: element and folded range sets carry their bounds; an
  // opaque C++ bound carries none
  DoWithSem(TPath.Combine(DoProbeDir('emit\own'), 'own3.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LOpaque: TPCSetType;
    begin
      Check(DoCodes(AErrors) = '', 'emit.set_bounds: codes ' + DoCodes(AErrors));
      Check(DoHasSetBounds(AModule, 'TS1', 0, 5), 'emit.set_bounds: set of TC (ordinals 2, 0, 5) = 0 .. 5');
      Check(DoHasSetBounds(AModule, 'TS2', 0, 1), 'emit.set_bounds: set of bool = 0 .. 1');
      Check(DoHasSetBounds(AModule, 'TS3', 1, 63), 'emit.set_bounds: set of 1..63 = 1 .. 63');
      Check(DoHasSetBounds(AModule, 'TS4', 0, 255), 'emit.set_bounds: set of char = 0 .. 255 (W2)');
      LOpaque := DoSetTypeOf(AModule, 'TS5');
      Check((LOpaque <> nil) and (not LOpaque.HasResolvedBounds),
        'emit.set_bounds: an opaque C++ bound has no resolved bounds');
    end);
end;

procedure TPCSemanticsTests.DoTestExceptEscapes();
begin
  // PLAN-EMITTER A7: a jump leaving an except list is recorded on its guard
  // (ResolvedExceptEscapes), apart from the body's (ResolvedEscapes)
  DoWithSem(TPath.Combine(DoProbeDir('emit\own'), 'own4.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LRoutine: TPCRoutine;
      LWhile: TPCWhile;
      LFirst: TPCGuard;
      LSecond: TPCGuard;
    begin
      Check(DoCodes(AErrors) = '', 'emit.except_escapes: codes ' + DoReports(AErrors));
      LRoutine := nil;
      if (AModule.Decls.Count > 0) and (AModule.Decls[0] is TPCRoutine) then
        LRoutine := TPCRoutine(AModule.Decls[0]);
      Check((LRoutine <> nil) and (LRoutine.Body <> nil) and (LRoutine.Body.Stmts.Count = 2) and
        (LRoutine.Body.Stmts[0] is TPCWhile), 'emit.except_escapes: F = while + return');
      if not ((LRoutine <> nil) and (LRoutine.Body <> nil) and (LRoutine.Body.Stmts.Count = 2) and
        (LRoutine.Body.Stmts[0] is TPCWhile)) then
        Exit;
      LWhile := TPCWhile(LRoutine.Body.Stmts[0]);
      Check((LWhile.Stmts.Count = 2) and (LWhile.Stmts[0] is TPCGuard) and (LWhile.Stmts[1] is TPCGuard),
        'emit.except_escapes: two guards in the loop');
      if not ((LWhile.Stmts.Count = 2) and (LWhile.Stmts[0] is TPCGuard) and (LWhile.Stmts[1] is TPCGuard)) then
        Exit;
      LFirst := TPCGuard(LWhile.Stmts[0]);
      LSecond := TPCGuard(LWhile.Stmts[1]);
      Check((LFirst.ResolvedEscapes = [geSkip]) and (LFirst.ResolvedExceptEscapes = [geLeave]),
        'emit.except_escapes: body skip / except leave kept apart');
      Check((LSecond.ResolvedEscapes = []) and (LSecond.ResolvedExceptEscapes = [geReturn]),
        'emit.except_escapes: a return in the except list (no finally) is recorded too');
    end);
end;

procedure TPCSemanticsTests.DoTestCppJumpExcept();
begin
  // PLAN-EMITTER A7: with a finally the except list runs in a lambda, so a
  // C++ break there that leaves the guard is SM0614; without one it is a
  // plain break (the second guard): exactly one report, on line 9
  DoWithSem(TPath.Combine(DoProbeDir('emit\own'), 'own5.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = PC_ERR_SEM_614, 'emit.cpp_jump_except: one SM0614 (' + DoReports(AErrors) + ')');
      Check(DoReports(AErrors).StartsWith(PC_ERR_SEM_614 + ' 9: ') and
        DoReports(AErrors).Contains('except body of a guard with finally'),
        'emit.cpp_jump_except: on line 9, in PaskalCPP words (' + DoReports(AErrors) + ')');
    end);
end;

end.
