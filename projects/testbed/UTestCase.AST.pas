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
  UTestCase.AST - AST atom tests

  TTestCase suite for PaskalCPP.AST in isolation: hand-built trees in, node
  fields, Dump text, errors and translated locations out. Covers the arena
  (ownership, NewNode, synthesized types), node kinds, modules, the child walk,
  Dump and TranslateLocation.

  Dependencies: StdApp.TestCase, StdApp.Base, PaskalCPP.Common, PaskalCPP.AST,
    PaskalCPP.ZigBuild (TPCLocationTranslator signature check only)
===============================================================================}

unit UTestCase.AST;

interface

uses
  StdApp.TestCase;

type

  { TPCASTTests }
  TPCASTTests = class(TTestCase)
  private
    // One test per concern; Create registers each under its CLI name
    procedure DoTestArena();
    procedure DoTestNodeKinds();
    procedure DoTestModules();
    procedure DoTestChildren();
    procedure DoTestDump();
    procedure DoTestTranslate();
    procedure DoTestNodeKindsAll();
    procedure DoTestDecls();
    procedure DoTestTypes();
    procedure DoTestStmts();
    procedure DoTestExprs();
    procedure DoTestResolvedRefs();
    procedure DoTestTypeText();
    procedure DoTestSignature();
    procedure DoTestExprText();
    procedure DoTestFloatText();
    procedure DoTestCanon();
    procedure DoTestHoldsString();
    procedure DoTestBuiltinCache();
    procedure DoTestJumpFields();
    procedure DoTestFactDumps();
    procedure DoTestIntrinsicNames();
    procedure DoTestLiteralValue();
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.Math,
  StdApp.Base,
  PaskalCPP.Common,
  PaskalCPP.AST,
  PaskalCPP.ZigBuild;

const
  { TEST_AST_CORE_CLASSES }
  // Every concrete class this plan adds, paired with TEST_AST_CORE_KINDS
  TEST_AST_CORE_CLASSES: array[0..13] of TPCNodeClass = (
    TPCModule, TPCImport, TPCDirective, TPCDirectiveArg, TPCTest,
    TPCVerbatimStmt, TPCVerbatimExpr, TPCBlock, TPCLiteral, TPCOpaqueType,
    TPCErrorType, TPCNilType, TPCVoidType, TPCStringLiteralType
  );

  { TEST_AST_CORE_KINDS }
  TEST_AST_CORE_KINDS: array[0..13] of TPCNodeKind = (
    nkModule, nkImport, nkDirective, nkDirectiveArg, nkTest,
    nkVerbatimStmt, nkVerbatimExpr, nkBlock, nkLiteral, nkOpaqueType,
    nkErrorType, nkNilType, nkVoidType, nkStringLiteralType
  );

  { TEST_AST_DUMP_DEMO }
  // Expected Dump of the tree DoTestDump builds; the imported module Lib is
  // named on the Import line but never walked
  TEST_AST_DUMP_DEMO =
    'Module "Demo" mkExe' + sLineBreak +
    '  Directive "target"' + sLineBreak +
    '    DirectiveArg daCString "\"x86_64-windows-gnu\"" resolved="x86_64-windows-gnu"' + sLineBreak +
    '  Import "Lib" -> "Lib"' + sLineBreak +
    '  VerbatimStmt vkCppDecl etSource "int g_x = 1;"' + sLineBreak +
    '  Block' + sLineBreak +
    '    VerbatimStmt vkCppBlock etInPlace "a();\r\nb();"' + sLineBreak +
    '  Test' + sLineBreak +
    '    Literal lkString "\"t1\"" type="string literal"' + sLineBreak +
    '    Block' + sLineBreak;

  { TEST_AST_DUMP_LIB }
  TEST_AST_DUMP_LIB =
    'Module "Lib" mkUnit' + sLineBreak +
    '  VerbatimStmt vkCppDecl etSource "int lib_y;"' + sLineBreak;

  { TEST_AST_DUMP_LIB_TARGET }
  // TEST_AST_DUMP_LIB once ResolvedTarget is set (DefaultTriple keeps the vendor)
  TEST_AST_DUMP_LIB_TARGET =
    'Module "Lib" mkUnit target="x86_64-pc-windows-gnu"' + sLineBreak +
    '  VerbatimStmt vkCppDecl etSource "int lib_y;"' + sLineBreak;

  { TEST_AST_NODES_CLASSES }
  // Every concrete class PLAN-CPPMIX-AST-NODES adds, paired with TEST_AST_NODES_KINDS:
  // 5 declarations + 24 types + 13 statements + 21 expressions = 64 (TPCTypeTest: O12; TPCOperatorItem: O11;
  // TPCDerivedType: SEM-PREREQ-A; TPCErrorMember / TPCErrorStmt / TPCErrorExpr: PLAN-RECOVERY; TPCInitItem /
  // TPCDoneItem: PLAN-OBJECT O4; TPCCopyItem: O5; TPCOwnerType / TPCOwnerNew: O6; TPCPropertyItem / TPCAccessorItem: O9)
  TEST_AST_NODES_CLASSES: array[0..63] of TPCNodeClass = (
    TPCVarDecl, TPCConstDecl, TPCTypeDecl, TPCRoutine, TPCParam,
    TPCBuiltinType, TPCNamedType, TPCPointerType, TPCOwnerType, TPCArrayType, TPCCppType,
    TPCRecordType, TPCOverlayType, TPCField, TPCAnonAggregate, TPCMethodItem, TPCInitItem, TPCDoneItem,
    TPCCopyItem, TPCPropertyItem, TPCAccessorItem, TPCOperatorItem, TPCErrorMember,
    TPCChoicesType, TPCChoiceValue, TPCSetType, TPCRoutineType, TPCDerivedType, TPCTemplateArg,
    TPCNamePart,
    TPCIf, TPCWhile, TPCFor, TPCRepeat, TPCMatch, TPCMatchArm,
    TPCMatchLabel, TPCGuard, TPCReturn, TPCLeave, TPCSkip, TPCExprStmt, TPCErrorStmt,
    TPCAssign, TPCTernary, TPCBinary, TPCUnary, TPCCall, TPCIndex, TPCMember,
    TPCName, TPCSpecial, TPCCast, TPCNew, TPCDelete, TPCOwnerNew, TPCTypeTest, TPCBracedInit,
    TPCSetLiteral, TPCSetElement, TPCRecordLiteral, TPCFieldInit, TPCVarargs, TPCErrorExpr
  );

  { TEST_AST_NODES_KINDS }
  TEST_AST_NODES_KINDS: array[0..63] of TPCNodeKind = (
    nkVarDecl, nkConstDecl, nkTypeDecl, nkRoutine, nkParam,
    nkBuiltinType, nkNamedType, nkPointerType, nkOwnerType, nkArrayType, nkCppType,
    nkRecordType, nkOverlayType, nkField, nkAnonAggregate, nkMethodItem, nkInitItem, nkDoneItem,
    nkCopyItem, nkPropertyItem, nkAccessorItem, nkOperatorItem, nkErrorMember,
    nkChoicesType, nkChoiceValue, nkSetType, nkRoutineType, nkDerivedType, nkTemplateArg,
    nkNamePart,
    nkIf, nkWhile, nkFor, nkRepeat, nkMatch, nkMatchArm,
    nkMatchLabel, nkGuard, nkReturn, nkLeave, nkSkip, nkExprStmt, nkErrorStmt,
    nkAssign, nkTernary, nkBinary, nkUnary, nkCall, nkIndex, nkMember,
    nkName, nkSpecial, nkCast, nkNew, nkDelete, nkOwnerNew, nkTypeTest, nkBracedInit,
    nkSetLiteral, nkSetElement, nkRecordLiteral, nkFieldInit, nkVarargs, nkErrorExpr
  );

  { TEST_AST_DUMP_ROUTINE }
  // Params, return type, declaration blocks, body: source order. The full
  // declaration of the forward type is named, never walked
  TEST_AST_DUMP_ROUTINE =
    'Routine "Add" exported rnRoutine lnC variadic linkage=lnCpp' + sLineBreak +
    '  Param "AX" pmConst' + sLineBreak +
    '    BuiltinType tkKwInt32' + sLineBreak +
    '  Param "AY"' + sLineBreak +
    '    BuiltinType tkKwInt32' + sLineBreak +
    '  BuiltinType tkKwInt64' + sLineBreak +
    '  VarDecl "LT"' + sLineBreak +
    '    BuiltinType tkKwInt64' + sLineBreak +
    '    Literal lkInteger "0" value=0' + sLineBreak +
    '  ConstDecl "CK"' + sLineBreak +
    '    BuiltinType tkKwInt32' + sLineBreak +
    '    Literal lkInteger "1" value=1' + sLineBreak +
    '  TypeDecl "TNode" forward full=TypeDecl "TNode"' + sLineBreak +
    '  Block' + sLineBreak;

  { TEST_AST_DUMP_EXTVAR }
  TEST_AST_DUMP_EXTVAR =
    'VarDecl "gLib" external "kernel32" lib="kernel32"' + sLineBreak +
    '  PointerType' + sLineBreak;

  { TEST_AST_DUMP_EXTVAR_NAME }
  TEST_AST_DUMP_EXTVAR_NAME =
    'VarDecl "gLibK" external LIBK32 lib="kernel32"' + sLineBreak +
    '  PointerType' + sLineBreak;

  { TEST_AST_DUMP_RECORD }
  TEST_AST_DUMP_RECORD =
    'TypeDecl "TPoint"' + sLineBreak +
    '  RecordType record packed' + sLineBreak +
    '    NamedType "Base.TShape" kind=rkType decl=TypeDecl "TShape"' + sLineBreak +
    '    Literal lkInteger "8" value=8' + sLineBreak +
    '    Field "X"' + sLineBreak +
    '      BuiltinType tkKwInt32' + sLineBreak +
    '    Field "F"' + sLineBreak +
    '      BuiltinType tkKwUint8' + sLineBreak +
    '      Literal lkInteger "3" value=3' + sLineBreak +
    '    AnonAggregate overlay' + sLineBreak +
    '      Field "A"' + sLineBreak +
    '        BuiltinType tkKwInt64' + sLineBreak +
    '      Field "B"' + sLineBreak +
    '        BuiltinType tkKwFloat64' + sLineBreak;

  { TEST_AST_DUMP_OBJECT }
  TEST_AST_DUMP_OBJECT =
    'RecordType object' + sLineBreak +
    '  MethodItem' + sLineBreak +
    '    Routine "Run" rnMethod' + sLineBreak +
    '      Block' + sLineBreak;

  { TEST_AST_DUMP_CHOICES }
  TEST_AST_DUMP_CHOICES =
    'ChoicesType' + sLineBreak +
    '  ChoiceValue "cRed" ordinal=0' + sLineBreak +
    '  ChoiceValue "cBlue" ordinal=5' + sLineBreak +
    '    Literal lkInteger "5" value=5' + sLineBreak;

  { TEST_AST_DUMP_ROUTINE_TYPE }
  TEST_AST_DUMP_ROUTINE_TYPE =
    'RoutineType lnC variadic' + sLineBreak +
    '  Param "AS" pmVar' + sLineBreak +
    '    SetType range' + sLineBreak +
    '      Literal lkInteger "0" value=0' + sLineBreak +
    '      Literal lkInteger "31" value=31' + sLineBreak +
    '  Param "AA"' + sLineBreak +
    '    ArrayType' + sLineBreak +
    '      Literal lkInteger "0" value=0' + sLineBreak +
    '      Literal lkInteger "9" value=9' + sLineBreak +
    '      PointerType const' + sLineBreak +
    '        BuiltinType tkKwChar' + sLineBreak +
    '  Param "AD" pmConst' + sLineBreak +
    '    ArrayType dynamic' + sLineBreak +
    '      BuiltinType tkKwString' + sLineBreak +
    '  CppType lead=const *const &' + sLineBreak +
    '    NamePart "std"' + sLineBreak +
    '    NamePart "vector" targs' + sLineBreak +
    '      TemplateArg' + sLineBreak +
    '        NamedType "int32_t" kind=rkOpaque' + sLineBreak;

  { TEST_AST_DUMP_STMTS }
  // Branch counts tell then / else and guard / finally statements apart
  TEST_AST_DUMP_STMTS =
    'Block' + sLineBreak +
    '  If then=1 else=1' + sLineBreak +
    '    Name' + sLineBreak +
    '      NamePart "LOk"' + sLineBreak +
    '    Return' + sLineBreak +
    '      Literal lkInteger "1" value=1' + sLineBreak +
    '    Return' + sLineBreak +
    '  While' + sLineBreak +
    '    Literal lkBool "true"' + sLineBreak +
    '    Leave' + sLineBreak +
    '  For "LI" downto iter=VarDecl "LI"' + sLineBreak +
    '    Literal lkInteger "9" value=9' + sLineBreak +
    '    Literal lkInteger "0" value=0' + sLineBreak +
    '    Skip' + sLineBreak +
    '  Repeat' + sLineBreak +
    '    ExprStmt' + sLineBreak +
    '      Call' + sLineBreak +
    '        Name' + sLineBreak +
    '          NamePart "Tick"' + sLineBreak +
    '    Literal lkBool "false"' + sLineBreak +
    '  Match else=1' + sLineBreak +
    '    Name' + sLineBreak +
    '      NamePart "LK"' + sLineBreak +
    '    MatchArm' + sLineBreak +
    '      MatchLabel' + sLineBreak +
    '        Literal lkInteger "1" value=1' + sLineBreak +
    '      MatchLabel' + sLineBreak +
    '        Literal lkInteger "3" value=3' + sLineBreak +
    '        Literal lkInteger "5" value=5' + sLineBreak +
    '      Leave' + sLineBreak +
    '    Skip' + sLineBreak +
    '  Guard guard=1 finally=1' + sLineBreak +
    '    Skip' + sLineBreak +
    '    Leave' + sLineBreak;

  { TEST_AST_DUMP_ASSIGN }
  TEST_AST_DUMP_ASSIGN =
    'Assign aoAddAssign' + sLineBreak +
    '  Name' + sLineBreak +
    '    NamePart "LX"' + sLineBreak +
    '  Binary boMul' + sLineBreak +
    '    Unary uoNegate' + sLineBreak +
    '      Name' + sLineBreak +
    '        NamePart "LA"' + sLineBreak +
    '    Literal lkInteger "2" value=2' + sLineBreak;

  { TEST_AST_DUMP_CALLS }
  // A unit-test intrinsic inside a test, size(T) with its type slot, and a
  // scoped C++ name with template args
  TEST_AST_DUMP_CALLS =
    'Block' + sLineBreak +
    '  ExprStmt' + sLineBreak +
    '    Call type="void" kind=rkIntrinsic intrinsic=ikTestAssertEqualInt intest' + sLineBreak +
    '      Name' + sLineBreak +
    '        NamePart "testAssertEqualInt"' + sLineBreak +
    '      Literal lkInteger "1" value=1' + sLineBreak +
    '      Literal lkInteger "1" value=1' + sLineBreak +
    '  ExprStmt' + sLineBreak +
    '    Call const=8 kind=rkIntrinsic intrinsic=ikSize' + sLineBreak +
    '      Name' + sLineBreak +
    '        NamePart "size"' + sLineBreak +
    '      BuiltinType tkKwInt64' + sLineBreak +
    '  ExprStmt' + sLineBreak +
    '    Call type="opaque" kind=rkOpaque' + sLineBreak +
    '      Name scoped' + sLineBreak +
    '        NamePart "std"' + sLineBreak +
    '        NamePart "max" targs' + sLineBreak +
    '          TemplateArg' + sLineBreak +
    '            CppType tkKwInt' + sLineBreak +
    '      Name' + sLineBreak +
    '        NamePart "LA"' + sLineBreak +
    '      Name' + sLineBreak +
    '        NamePart "LB"' + sLineBreak;

  { TEST_AST_DUMP_CPP }
  TEST_AST_DUMP_CPP =
    'Block' + sLineBreak +
    '  ExprStmt' + sLineBreak +
    '    Ternary' + sLineBreak +
    '      Index' + sLineBreak +
    '        Member maArrow kind=rkField decl=Field "X"' + sLineBreak +
    '          Name' + sLineBreak +
    '            NamePart "LP"' + sLineBreak +
    '          NamePart "X"' + sLineBreak +
    '        Literal lkInteger "0" value=0' + sLineBreak +
    '      Special skNullptr' + sLineBreak +
    '      Special skThis' + sLineBreak +
    '  ExprStmt' + sLineBreak +
    '    Cast ckStatic' + sLineBreak +
    '      CppType tkKwInt' + sLineBreak +
    '      Name' + sLineBreak +
    '        NamePart "LD"' + sLineBreak +
    '  ExprStmt' + sLineBreak +
    '    New niArraySize' + sLineBreak +
    '      CppType tkKwInt' + sLineBreak +
    '      Literal lkInteger "10" value=10' + sLineBreak +
    '  ExprStmt' + sLineBreak +
    '    Delete array' + sLineBreak +
    '      Name' + sLineBreak +
    '        NamePart "LP"' + sLineBreak +
    '  ExprStmt' + sLineBreak +
    '    Call' + sLineBreak +
    '      Member maDot' + sLineBreak +
    '        Name' + sLineBreak +
    '          NamePart "LV"' + sLineBreak +
    '        NamePart "push_back"' + sLineBreak +
    '      BracedInit bare' + sLineBreak +
    '        Literal lkInteger "1" value=1' + sLineBreak +
    '        Literal lkInteger "2" value=2' + sLineBreak +
    '  ExprStmt' + sLineBreak +
    '    BracedInit' + sLineBreak +
    '      Name' + sLineBreak +
    '        NamePart "T"' + sLineBreak +
    '      Literal lkInteger "3" value=3' + sLineBreak +
    '  ExprStmt' + sLineBreak +
    '    SetLiteral' + sLineBreak +
    '      SetElement' + sLineBreak +
    '        Literal lkInteger "1" value=1' + sLineBreak +
    '      SetElement' + sLineBreak +
    '        Literal lkInteger "3" value=3' + sLineBreak +
    '        Literal lkInteger "5" value=5' + sLineBreak +
    '  ExprStmt' + sLineBreak +
    '    RecordLiteral' + sLineBreak +
    '      NamedType "TPoint"' + sLineBreak +
    '      FieldInit "x" field=Field "x"' + sLineBreak +
    '        Literal lkInteger "10" value=10' + sLineBreak +
    '  ExprStmt' + sLineBreak +
    '    Varargs vaNext' + sLineBreak +
    '      BuiltinType tkKwInt32' + sLineBreak;

  { TEST_AST_DUMP_REFS }
  // Each reference is named on its node's line; none of them is walked
  TEST_AST_DUMP_REFS =
    'Block' + sLineBreak +
    '  For "LI" to iter=VarDecl "LI"' + sLineBreak +
    '    Literal lkInteger "0" value=0' + sLineBreak +
    '    Literal lkInteger "3" value=3' + sLineBreak +
    '    ExprStmt' + sLineBreak +
    '      Call kind=rkRoutine decl=Routine "Tick"' + sLineBreak +
    '        Name' + sLineBreak +
    '          NamePart "Tick"' + sLineBreak +
    '        Literal lkInteger "1" value=1' + sLineBreak +
    '  TypeDecl "TNode" forward full=TypeDecl "TNode"' + sLineBreak;

function DoInt(const AAst: TPCAst; const AValue: UInt64): TPCLiteral;
begin
  Result := AAst.NewNode<TPCLiteral>();
  Result.LiteralKind := lkInteger;
  Result.Text := UIntToStr(AValue);
  Result.HasValue := True;
  Result.IntValue := AValue;
end;

function DoBool(const AAst: TPCAst; const AValue: Boolean): TPCLiteral;
begin
  Result := AAst.NewNode<TPCLiteral>();
  Result.LiteralKind := lkBool;
  if AValue then
    Result.Text := 'true'
  else
    Result.Text := 'false';
end;

function DoBuiltin(const AAst: TPCAst; const AToken: TPCTokenKind): TPCBuiltinType;
begin
  Result := AAst.NewNode<TPCBuiltinType>();
  Result.BuiltinToken := AToken;
end;

function DoCppInt(const AAst: TPCAst): TPCCppType;
begin
  // The C++ fundamental int; SetLength + index, never an enum array literal
  Result := AAst.NewNode<TPCCppType>();
  SetLength(Result.Fundamentals, 1);
  Result.Fundamentals[0] := tkKwInt;
end;

function DoPart(const AAst: TPCAst; const AText: string): TPCNamePart;
begin
  Result := AAst.NewNode<TPCNamePart>();
  Result.PartText := AText;
end;

function DoName(const AAst: TPCAst; const AText: string): TPCName;
begin
  Result := AAst.NewNode<TPCName>();
  Result.Parts.Add(DoPart(AAst, AText));
end;

function DoField(const AAst: TPCAst; const AName: string; const AType: TPCTypeExpr): TPCField;
begin
  Result := AAst.NewNode<TPCField>();
  Result.FieldName := AName;
  Result.TypeExpr := AType;
end;

function DoParam(const AAst: TPCAst; const AName: string; const AMode: TPCParamMode;
  const AType: TPCTypeExpr): TPCParam;
begin
  Result := AAst.NewNode<TPCParam>();
  Result.ParamName := AName;
  Result.ParamMode := AMode;
  Result.TypeExpr := AType;
end;

function DoSpecial(const AAst: TPCAst; const AKind: TPCSpecialKind): TPCSpecial;
begin
  Result := AAst.NewNode<TPCSpecial>();
  Result.SpecialKind := AKind;
end;

function DoStmt(const AAst: TPCAst; const AExpr: TPCExpr): TPCExprStmt;
begin
  Result := AAst.NewNode<TPCExprStmt>();
  Result.Expr := AExpr;
end;

function DoAstFile(): string;
begin
  // The exe sits two levels below the project root (repo\bin)
  Result := TPath.GetFullPath(TPath.Combine(
    TPath.GetDirectoryName(ParamStr(0)), '..\..\tests\probe\ast\demo.pcpp'));
end;

function DoSpan(const ALine: UInt64; const AStartCol: UInt64; const AEndCol: UInt64): TPCEmitSpan;
begin
  Result := Default(TPCEmitSpan);
  Result.OutFile := ofSource;
  Result.CppLine := ALine + 100;
  Result.SourceLine := ALine;
  Result.StartCol := AStartCol;
  Result.EndCol := AEndCol;
end;

function DoVerbatim(const AAst: TPCAst; const AKind: TPCVerbatimKind;
  const ATarget: TPCEmitTarget; const AText: string): TPCVerbatimStmt;
begin
  Result := AAst.NewNode<TPCVerbatimStmt>();
  Result.Verbatim.VerbatimKind := AKind;
  Result.Verbatim.EmitTarget := ATarget;
  Result.Verbatim.Text := AText;
end;

function DoValueRun(const AValueOffset: Integer; const ALine: UInt64; const AColumn: UInt64;
  const AIsCopy: Boolean): TPCValueRun;
begin
  Result := Default(TPCValueRun);
  Result.ValueOffset := AValueOffset;
  Result.Line := ALine;
  Result.Column := AColumn;
  Result.IsCopy := AIsCopy;
end;

function DoJump(const AKind: TPCCppJumpKind; const ALine: UInt64; const AColumn: UInt64): TPCCppJump;
begin
  // Only the start of the jump word is dumped (DoJumpsText)
  Result := Default(TPCCppJump);
  Result.Kind := AKind;
  Result.Range.StartLine := ALine;
  Result.Range.StartColumn := AColumn;
end;

function DoCppName(const AAst: TPCAst; const AParts: array of string): TPCCppType;
var
  LText: string;
begin
  Result := AAst.NewNode<TPCCppType>();
  for LText in AParts do
    Result.NameParts.Add(DoPart(AAst, LText));
end;

function DoNamed(const AAst: TPCAst; const AText: string; const ADecl: TPCTypeDecl): TPCNamedType;
begin
  // ADecl <> nil: resolved to it (rkType), as SEM writes it
  Result := AAst.NewNode<TPCNamedType>();
  Result.Parts := [AText];
  if ADecl <> nil then
  begin
    Result.ResolvedKind := rkType;
    Result.ResolvedDecl := ADecl;
  end;
end;

function DoTypeDecl(const AAst: TPCAst; const AName: string; const ADef: TPCTypeExpr): TPCTypeDecl;
begin
  Result := AAst.NewNode<TPCTypeDecl>();
  Result.DeclName := AName;
  Result.TypeDef := ADef;
end;

function DoBinary(const AAst: TPCAst; const ALeft: TPCExpr; const AOp: TPCBinaryOp;
  const ARight: TPCExpr): TPCBinary;
begin
  Result := AAst.NewNode<TPCBinary>();
  Result.Left := ALeft;
  Result.Op := AOp;
  Result.Right := ARight;
end;

function DoUnary(const AAst: TPCAst; const AOp: TPCUnaryOp; const AOperand: TPCExpr): TPCUnary;
begin
  Result := AAst.NewNode<TPCUnary>();
  Result.Op := AOp;
  Result.Operand := AOperand;
end;

function DoTypeArg(const AAst: TPCAst; const AType: TPCTypeExpr): TPCTemplateArg;
begin
  Result := AAst.NewNode<TPCTemplateArg>();
  Result.TypeArg := AType;
end;

function DoExprArg(const AAst: TPCAst; const AExpr: TPCExpr): TPCTemplateArg;
begin
  Result := AAst.NewNode<TPCTemplateArg>();
  Result.ExprArg := AExpr;
end;

function DoRecordWith(const AAst: TPCAst; const AType: TPCTypeExpr): TPCRecordType;
begin
  // A record of one field 'F' of AType
  Result := AAst.NewNode<TPCRecordType>();
  Result.Members.Add(DoField(AAst, 'F', AType));
end;

function DoDecodesTo(const AText: string; const AValue: Double): Boolean;
var
  LNumeric: string;
  LNegative: Boolean;
  LDecoded: Double;
  LBits: UInt64;
  LWant: UInt64;
begin
  // FloatText's contract, checked independently: '#' carries the bits, else
  // the text decodes exactly (TPCFloatDecoder) to the same bits
  Move(AValue, LWant, SizeOf(LWant));
  if AText.IndexOf('#') >= 0 then
  begin
    if not TryStrToUInt64('$' + AText.Substring(AText.IndexOf('#') + 1), LBits) then
      Exit(False);
    Exit(LBits = LWant);
  end;
  LNegative := AText.StartsWith('-');
  if LNegative then
    LNumeric := AText.Substring(1)
  else
    LNumeric := AText;
  if (LNumeric.IndexOf('.') < 0) and (LNumeric.IndexOf('E') < 0) then
    LNumeric := LNumeric + '.';
  if TPCFloatDecoder.Decode(LNumeric, ffBinary64, LDecoded) <> fsOk then
    Exit(False);
  if LNegative then
    LDecoded := -LDecoded;
  Move(LDecoded, LBits, SizeOf(LBits));
  Result := LBits = LWant;
end;

{ TPCASTTests }

constructor TPCASTTests.Create();
begin
  inherited;

  Title := 'AST';
  RegisterTest('arena', DoTestArena);
  RegisterTest('node_kinds', DoTestNodeKinds);
  RegisterTest('modules', DoTestModules);
  RegisterTest('children', DoTestChildren);
  RegisterTest('dump', DoTestDump);
  RegisterTest('translate', DoTestTranslate);
  RegisterTest('node_kinds_all', DoTestNodeKindsAll);
  RegisterTest('decls', DoTestDecls);
  RegisterTest('types', DoTestTypes);
  RegisterTest('stmts', DoTestStmts);
  RegisterTest('exprs', DoTestExprs);
  RegisterTest('resolved_refs', DoTestResolvedRefs);
  RegisterTest('type_text', DoTestTypeText);
  RegisterTest('signature', DoTestSignature);
  RegisterTest('expr_text', DoTestExprText);
  RegisterTest('float_text', DoTestFloatText);
  RegisterTest('canon', DoTestCanon);
  RegisterTest('holds_string', DoTestHoldsString);
  RegisterTest('builtin_cache', DoTestBuiltinCache);
  RegisterTest('jump_fields', DoTestJumpFields);
  RegisterTest('fact_dumps', DoTestFactDumps);
  RegisterTest('intrinsic_names', DoTestIntrinsicNames);
  RegisterTest('literal_value', DoTestLiteralValue);
end;

procedure TPCASTTests.Run();
begin
  inherited;
end;

procedure TPCASTTests.DoTestArena();
var
  LAst: TPCAst;
  LModule: TPCModule;
  LLiteral: TPCLiteral;
begin
  LAst := TPCAst.Create();
  try
    Check(LAst.NodeCount() = 7, 'arena: Create registers the seven synthesized types');
    LModule := LAst.NewNode<TPCModule>();
    // An orphan: no parent refers to it; the arena still frees it (a miss
    // shows as a leak report at testbed exit)
    LLiteral := LAst.NewNode<TPCLiteral>();
    LAst.NewNodeOf(TPCBlock);
    Check(LAst.NodeCount() = 10, 'arena: every NewNode / NewNodeOf is registered, orphans included');
    Check((LModule.NodeKind = nkModule) and (LModule.Decls <> nil) and (LModule.Tests <> nil),
      'arena: NewNode runs the class''s own virtual Create');
    Check(LLiteral.NodeKind = nkLiteral, 'arena: NewNode returns the requested class');
    Check((LAst.OpaqueType() = LAst.OpaqueType()) and (LAst.OpaqueType().NodeKind = nkOpaqueType),
      'synthesized: one opaque type instance');
    Check((LAst.ErrorType().NodeKind = nkErrorType) and (LAst.NilType().NodeKind = nkNilType) and
      (LAst.VoidType().NodeKind = nkVoidType), 'synthesized: error, nil and void types');
    Check((LAst.UntypedPointerType() = LAst.UntypedPointerType()) and
      (LAst.UntypedPointerType().TargetType = nil) and (LAst.UntypedPointerType().TypeText() = 'ptr'),
      'synthesized: one untyped ptr, spelled ptr');
    Check(LAst.StringLiteralType(True).IsWide and (not LAst.StringLiteralType(False).IsWide) and
      (LAst.StringLiteralType(True) <> LAst.StringLiteralType(False)),
      'synthesized: narrow and wide string literal types are distinct');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestNodeKinds();
var
  LAst: TPCAst;
  LNode: TPCNode;
  LI: Integer;
  LOk: Boolean;
begin
  LAst := TPCAst.Create();
  try
    LOk := True;
    for LI := Low(TEST_AST_CORE_CLASSES) to High(TEST_AST_CORE_CLASSES) do
    begin
      LNode := LAst.NewNodeOf(TEST_AST_CORE_CLASSES[LI]);
      if (LNode.NodeKind <> TEST_AST_CORE_KINDS[LI]) or (LNode.Dump() = '') then
        LOk := False;
    end;
    Check(LOk, 'kinds: every CORE class sets its own NodeKind and dumps');
    Check((LAst.NewNodeOf(TPCStmt).NodeKind = nkNone) and (LAst.NewNodeOf(TPCDecl).NodeKind = nkNone),
      'kinds: abstract bases carry nkNone');
    Check(LAst.NewNode<TPCBlock>().KindName() = 'Block', 'kinds: KindName drops the nk prefix');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestModules();
var
  LErrors: TErrors;
  LAst: TPCAst;
  LAlpha: TPCModule;
  LBeta: TPCModule;
  LDup: TPCModule;
  LNameless1: TPCModule;
  LNameless2: TPCModule;
  LDecl: TPCDecl;
  LDecl2: TPCDecl;
  LFound: TList<TPCDecl>;
begin
  LErrors := TErrors.Create();
  LAst := TPCAst.Create();
  try
    LErrors.SetMaxErrors(100);
    LAst.SetErrors(LErrors);

    LAlpha := LAst.NewNode<TPCModule>();
    LAlpha.ModuleName := 'Alpha';
    LBeta := LAst.NewNode<TPCModule>();
    LBeta.ModuleName := 'Beta';
    LDup := LAst.NewNode<TPCModule>();
    LDup.ModuleName := 'Alpha';

    LAst.AddModule(LAlpha);
    LAst.AddModule(LBeta);
    Check((LAst.FindModule('Beta') = LBeta) and (LAst.FindModule('Alpha') = LAlpha),
      'modules: FindModule hit');
    Check(LAst.FindModule('Gamma') = nil, 'modules: FindModule miss is nil');
    Check(LAst.FindModule('alpha') = nil, 'modules: names are case-sensitive (BNF.md:10)');
    Check(LErrors.Count() = 0, 'modules: distinct names report nothing');

    LAst.AddModule(LDup);
    Check((LErrors.Count() = 1) and (LErrors.GetItems()[0].Code = PC_ERR_AST_001),
      'modules: a duplicate name is exactly one AS0001');
    Check((LAst.ModuleCount() = 2) and (LAst.ModuleAt(0) = LAlpha) and (LAst.ModuleAt(1) = LBeta),
      'modules: the first is kept, order is add order');

    // CollectNamed walks a list, skips statements that are not declarations
    // and yields EVERY decl of the name in order (an overload set, F3)
    LAlpha.Decls.Add(DoVerbatim(LAst, vkCppDecl, etSource, 'int z;'));
    LDecl := TPCDecl(LAst.NewNodeOf(TPCDecl));
    LDecl.DeclName := 'gX';
    LAlpha.Decls.Add(LDecl);
    LDecl2 := TPCDecl(LAst.NewNodeOf(TPCDecl));
    LDecl2.DeclName := 'gX';
    LAlpha.Decls.Add(LDecl2);
    LFound := TList<TPCDecl>.Create();
    try
      TPCDecl.CollectNamed(LAlpha.Decls, LAlpha.Decls.Count, 'gX', LFound);
      Check((LFound.Count = 2) and (LFound[0] = LDecl) and (LFound[1] = LDecl2),
        'modules: CollectNamed yields every decl of the name, in order (got ' +
        IntToStr(LFound.Count) + ')');
      LFound.Clear();
      TPCDecl.CollectNamed(LAlpha.Decls, 2, 'gX', LFound);
      Check((LFound.Count = 1) and (LFound[0] = LDecl),
        'modules: CollectNamed sees only the first ACount items (got ' +
        IntToStr(LFound.Count) + ')');
      LFound.Clear();
      TPCDecl.CollectNamed(LAlpha.Decls, LAlpha.Decls.Count, 'GX', LFound);
      TPCDecl.CollectNamed(LAlpha.Decls, LAlpha.Decls.Count, 'none', LFound);
      TPCDecl.CollectNamed(LAlpha.Decls, LAlpha.Decls.Count, 'z', LFound);
      Check(LFound.Count = 0,
        'modules: CollectNamed is exact-case, empty on a miss, skips verbatim C++');
      TPCDecl.CollectNamed(LAlpha.Decls, MaxInt, 'gX', LFound);
      TPCDecl.CollectNamed(LAlpha.Decls, 0, 'gX', LFound);
      Check(LFound.Count = 2,
        'modules: CollectNamed clamps a count past the end, 0 collects nothing (got ' +
        IntToStr(LFound.Count) + ')');

      // CollectNamedAfter walks the items AFTER AIndex (the used-before scan, F-A1b-1)
      LFound.Clear();
      TPCDecl.CollectNamedAfter(LAlpha.Decls, 0, 'gX', LFound);
      Check((LFound.Count = 2) and (LFound[0] = LDecl) and (LFound[1] = LDecl2),
        'modules: CollectNamedAfter(0) yields the later decls of the name, in order (got ' +
        IntToStr(LFound.Count) + ')');
      LFound.Clear();
      TPCDecl.CollectNamedAfter(LAlpha.Decls, 1, 'gX', LFound);
      Check((LFound.Count = 1) and (LFound[0] = LDecl2),
        'modules: CollectNamedAfter(1) skips the item at the index (got ' +
        IntToStr(LFound.Count) + ')');
      LFound.Clear();
      TPCDecl.CollectNamedAfter(LAlpha.Decls, LAlpha.Decls.Count - 1, 'gX', LFound);
      Check(LFound.Count = 0,
        'modules: CollectNamedAfter of the last index collects nothing (got ' +
        IntToStr(LFound.Count) + ')');
      LFound.Clear();
      TPCDecl.CollectNamedAfter(LAlpha.Decls, -1, 'gX', LFound);
      Check(LFound.Count = 2,
        'modules: CollectNamedAfter(-1) walks every item (got ' +
        IntToStr(LFound.Count) + ')');
      LFound.Clear();
      TPCDecl.CollectNamedAfter(LAlpha.Decls, -5, 'gX', LFound);
      Check(LFound.Count = 2,
        'modules: CollectNamedAfter takes an index below -1 as -1 (got ' +
        IntToStr(LFound.Count) + ')');
      LFound.Clear();
      TPCDecl.CollectNamedAfter(nil, -1, 'gX', LFound);
      Check(LFound.Count = 0, 'modules: CollectNamedAfter of a nil list collects nothing');
    finally
      LFound.Free();
    end;

    // Import identity is the file: slash-normalized, case-insensitive
    LAlpha.SourceFile := 'C:\proj\src\Alpha.pcpp';
    LBeta.SourceFile := 'C:\proj\lib\Beta.pcpp';
    Check(LAst.FindModuleByFile('C:\proj\lib\Beta.pcpp') = LBeta,
      'modules: FindModuleByFile hit');
    Check(LAst.FindModuleByFile('c:/PROJ/src/alpha.pcpp') = LAlpha,
      'modules: FindModuleByFile ignores slash direction and case');
    Check(LAst.FindModuleByFile('C:\proj\src\Gamma.pcpp') = nil,
      'modules: FindModuleByFile miss is nil');
    Check(LAst.FindModuleByFile('\\?\C:\proj\lib\Beta.pcpp') = LBeta,
      'modules: FindModuleByFile takes the long-path spelling');
    // The rejected duplicate is still found by its file, so it is never parsed twice
    LDup.SourceFile := 'C:\proj\other\Alpha.pcpp';
    Check((LAst.FindModuleByFile('C:\proj\other\Alpha.pcpp') = LDup) and
      (LAst.FindModule('Alpha') = LAlpha) and (LAst.ModuleCount() = 2),
      'modules: a rejected duplicate is found by file only');

    // Nameless modules (broken header) are registered without the duplicate check
    LNameless1 := LAst.NewNode<TPCModule>();
    LNameless1.SourceFile := 'C:\proj\src\Broken1.pcpp';
    LNameless2 := LAst.NewNode<TPCModule>();
    LNameless2.SourceFile := 'C:\proj\src\Broken2.pcpp';
    LAst.AddModule(LNameless1);
    LAst.AddModule(LNameless2);
    Check((LErrors.Count() = 1) and (LAst.ModuleCount() = 4),
      'modules: two nameless modules add without AS0001');
    Check(LAst.FindModuleByFile('C:\proj\src\Broken2.pcpp') = LNameless2,
      'modules: a nameless module is found by its file');
  finally
    LAst.Free();
    LErrors.Free();
  end;
end;

procedure TPCASTTests.DoTestChildren();
var
  LAst: TPCAst;
  LModule: TPCModule;
  LTest: TPCTest;
  LOrder: string;
  LCount: Integer;
  LFirstRoutine: TPCRoutine;
begin
  LAst := TPCAst.Create();
  try
    LModule := LAst.NewNode<TPCModule>();
    LCount := 0;
    LModule.EnumChildren(
      procedure(const ANode: TPCNode)
      begin
        Inc(LCount);
      end);
    Check(LCount = 0, 'children: a fresh module has none (nil Body skipped)');

    // One of each, added out of order: the walk order is fixed by the class
    LTest := LAst.NewNode<TPCTest>();
    LModule.Tests.Add(LTest);
    LModule.Body := LAst.NewNode<TPCBlock>();
    LModule.HasBody := True;
    LModule.Decls.Add(DoVerbatim(LAst, vkCppDecl, etSource, 'int a;'));
    LModule.Imports.Add(LAst.NewNode<TPCImport>());
    LModule.Directives.Add(LAst.NewNode<TPCDirective>());
    LModule.FinalRoutine := LAst.NewNode<TPCRoutine>();
    LModule.InitRoutine := LAst.NewNode<TPCRoutine>();

    LOrder := '';
    LFirstRoutine := nil;
    LModule.EnumChildren(
      procedure(const ANode: TPCNode)
      begin
        LOrder := LOrder + ANode.KindName() + ' ';
        if (ANode is TPCRoutine) and (LFirstRoutine = nil) then
          LFirstRoutine := TPCRoutine(ANode);
      end);
    Check(LOrder = 'Directive Import VerbatimStmt Routine Routine Block Test ',
      'children: module order is directives, imports, decls, initialize, finalize, body, tests');
    Check(LFirstRoutine = LModule.InitRoutine,
      'children: initialize is visited before finalize');

    LCount := 0;
    LTest.EnumChildren(
      procedure(const ANode: TPCNode)
      begin
        Inc(LCount);
      end);
    Check(LCount = 0, 'children: a test with nil name and body has none');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestDump();
var
  LAst: TPCAst;
  LDemo: TPCModule;
  LLib: TPCModule;
  LDirective: TPCDirective;
  LArg: TPCDirectiveArg;
  LImport: TPCImport;
  LTest: TPCTest;
  LName: TPCLiteral;
  LInt: TPCLiteral;
  LFloat: TPCLiteral;
begin
  LAst := TPCAst.Create();
  try
    LLib := LAst.NewNode<TPCModule>();
    LLib.ModuleName := 'Lib';
    LLib.ModuleKind := mkUnit;
    LLib.Decls.Add(DoVerbatim(LAst, vkCppDecl, etSource, 'int lib_y;'));

    LDemo := LAst.NewNode<TPCModule>();
    LDemo.ModuleName := 'Demo';
    LDemo.ModuleKind := mkExe;

    LDirective := LAst.NewNode<TPCDirective>();
    LDirective.DirectiveName := 'target';
    LArg := LAst.NewNode<TPCDirectiveArg>();
    LArg.ArgKind := daCString;
    LArg.Text := '"x86_64-windows-gnu"';
    LArg.ResolvedText := 'x86_64-windows-gnu';
    LDirective.Args.Add(LArg);
    LDemo.Directives.Add(LDirective);

    LImport := LAst.NewNode<TPCImport>();
    LImport.ModuleName := 'Lib';
    LImport.ImportedModule := LLib;
    LDemo.Imports.Add(LImport);

    LDemo.Decls.Add(DoVerbatim(LAst, vkCppDecl, etSource, 'int g_x = 1;'));

    LDemo.HasBody := True;
    LDemo.Body := LAst.NewNode<TPCBlock>();
    LDemo.Body.Stmts.Add(DoVerbatim(LAst, vkCppBlock, etInPlace, 'a();' + #13#10 + 'b();'));

    LTest := LAst.NewNode<TPCTest>();
    LName := LAst.NewNode<TPCLiteral>();
    LName.LiteralKind := lkString;
    LName.Text := '"t1"';
    LName.ResolvedType := LAst.StringLiteralType(False);
    LTest.TestName := LName;
    LTest.Body := LAst.NewNode<TPCBlock>();
    LDemo.Tests.Add(LTest);

    Check(LDemo.Dump() = TEST_AST_DUMP_DEMO,
      'dump: the demo tree matches line for line; the import is named, not walked');
    Check(LLib.Dump() = TEST_AST_DUMP_LIB, 'dump: the imported module dumps as its own tree');
    LLib.ResolvedTarget := TPCTargetTriple.DefaultTriple();
    Check(LLib.Dump() = TEST_AST_DUMP_LIB_TARGET, 'dump: a set target shows on the module line');

    LInt := LAst.NewNode<TPCLiteral>();
    LInt.LiteralKind := lkInteger;
    LInt.Text := '42';
    LInt.HasValue := True;
    LInt.IntValue := 42;
    LInt.HasConstValue := True;
    LInt.ConstInt := 42;
    Check(LInt.Dump() = 'Literal lkInteger "42" value=42 const=42' + sLineBreak,
      'dump: integer literal shows its value and folded constant');

    LFloat := LAst.NewNode<TPCLiteral>();
    LFloat.LiteralKind := lkFloat;
    LFloat.Text := '2.5';
    LFloat.HasValue := True;
    LFloat.FloatValue := 2.5;
    Check(LFloat.Dump() = 'Literal lkFloat "2.5" value=2.5' + sLineBreak,
      'dump: float literal value uses the invariant format');

    Check(LAst.StringLiteralType(True).Dump() = 'StringLiteralType wide' + sLineBreak,
      'dump: wide string literal type');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestTranslate();
var
  LErrors: TErrors;
  LAst: TPCAst;
  LModule: TPCModule;
  LBlock: TPCBlock;
  LCopy: TPCVerbatimStmt;
  LDecoded: TPCVerbatimStmt;
  LTie: TPCVerbatimStmt;
  LMapped: TPCVerbatimStmt;
  LRaw: TPCVerbatimStmt;
  LFile: string;
  LClangFile: string;
  LOutFile: string;
  LOutLine: UInt64;
  LOutColumn: UInt64;
  LOk: Boolean;
  LTranslator: TPCLocationTranslator;
begin
  LErrors := TErrors.Create();
  LAst := TPCAst.Create();
  try
    LAst.SetErrors(LErrors);
    LFile := DoAstFile();
    // How clang reports the same file after #line: forward slashes, any case
    LClangFile := LFile.Replace('\', '/').ToUpper();

    LModule := LAst.NewNode<TPCModule>();
    LModule.ModuleName := 'Demo';
    LModule.SourceFile := LFile;
    LAst.AddModule(LModule);

    // Block: .pcpp lines 5..8, starts at column 2
    LBlock := LAst.NewNode<TPCBlock>();
    LBlock.Range.StartLine := 5;
    LBlock.Range.StartColumn := 2;
    LBlock.AddEmitSpan(DoSpan(5, 1, 30));
    LBlock.AddEmitSpan(DoSpan(8, 1, 10));
    LModule.HasBody := True;
    LModule.Body := LBlock;

    // Byte-copied block over lines 5..6, starting at column 3
    LCopy := DoVerbatim(LAst, vkCppBlock, etInPlace, 'x();' + #13#10 + 'y();');
    LCopy.Range.StartLine := 5;
    LCopy.Range.StartColumn := 3;
    LCopy.AddEmitSpan(DoSpan(5, 5, 20));
    LCopy.AddEmitSpan(DoSpan(6, 1, 10));
    LBlock.Stmts.Add(LCopy);

    // Decoded cpp("...") text: maps to its start column, never by offset
    LDecoded := DoVerbatim(LAst, vkCppExpr, etInPlace, 'f(1)');
    LDecoded.Range.StartLine := 7;
    LDecoded.Range.StartColumn := 9;
    LDecoded.AddEmitSpan(DoSpan(7, 4, 12));
    LBlock.Stmts.Add(LDecoded);

    // Same width as the block's line-8 span: the deeper node must win
    LTie := DoVerbatim(LAst, vkPreproc, etInPlace, '#define Q 1');
    LTie.Range.StartLine := 8;
    LTie.Range.StartColumn := 1;
    LTie.AddEmitSpan(DoSpan(8, 1, 10));
    LBlock.Stmts.Add(LTie);

    // cpp("ab\x41c") at column 3 of line 9: the value 'abAc' came from a
    // (col 8), b (9), the escape \x41 (10..13), c (14). The emitter writes
    // (abAc) at C++ columns 20..25: the value's own span 21..24, the node's
    // whole span 20..25 (DoWriteVerbatimExpr)
    LMapped := DoVerbatim(LAst, vkCppExpr, etInPlace, 'abAc');
    LMapped.Range.StartLine := 9;
    LMapped.Range.StartColumn := 3;
    LMapped.Verbatim.Range.StartLine := 9;
    LMapped.Verbatim.ValueMap := [DoValueRun(0, 9, 8, True), DoValueRun(2, 9, 10, False),
      DoValueRun(3, 9, 14, True)];
    LMapped.AddEmitSpan(DoSpan(9, 21, 25));
    LMapped.AddEmitSpan(DoSpan(9, 20, 26));
    LBlock.Stmts.Add(LMapped);

    // cpp(R"(q<LF>rs)") at column 3 of line 10: value 'q' + LF + 'rs', q at
    // column 10; the raw string's second line is the source line, from column 1
    LRaw := DoVerbatim(LAst, vkCppExpr, etInPlace, 'q' + #10 + 'rs');
    LRaw.Range.StartLine := 10;
    LRaw.Range.StartColumn := 3;
    LRaw.Verbatim.Range.StartLine := 10;
    LRaw.Verbatim.ValueMap := [DoValueRun(0, 10, 10, True)];
    LRaw.AddEmitSpan(DoSpan(10, 6, 7));
    LRaw.AddEmitSpan(DoSpan(11, 1, 3));
    LBlock.Stmts.Add(LRaw);

    LOk := LAst.TranslateLocation(LClangFile, 5, 7, LOutFile, LOutLine, LOutColumn);
    Check(LOk and (LOutFile = LFile) and (LOutLine = 5) and (LOutColumn = 5),
      'translate: narrowest node wins; byte copy maps by offset (3 + 7 - 5)');

    LOk := LAst.TranslateLocation(LFile, 5, 25, LOutFile, LOutLine, LOutColumn);
    Check(LOk and (LOutColumn = 2), 'translate: only the block covers column 25: its start column');

    LOk := LAst.TranslateLocation(LFile, 6, 4, LOutFile, LOutLine, LOutColumn);
    Check(LOk and (LOutLine = 6) and (LOutColumn = 4),
      'translate: a continuation line of a byte copy maps from column 1');

    LOk := LAst.TranslateLocation(LFile, 7, 6, LOutFile, LOutLine, LOutColumn);
    Check(LOk and (LOutColumn = 9), 'translate: vkCppExpr without a value map maps to its start column');

    LOk := LAst.TranslateLocation(LFile, 8, 3, LOutFile, LOutLine, LOutColumn);
    Check(LOk and (LOutColumn = 3), 'translate: equal widths: the deeper node wins');

    LOk := LAst.TranslateLocation(LFile, 9, 22, LOutFile, LOutLine, LOutColumn);
    Check(LOk and (LOutLine = 9) and (LOutColumn = 9),
      'translate: cpp("...") value byte 1 (b, copied) maps to its column 9 (got %d)', [LOutColumn]);

    LOk := LAst.TranslateLocation(LFile, 9, 23, LOutFile, LOutLine, LOutColumn);
    Check(LOk and (LOutColumn = 10),
      'translate: cpp("...") value byte 2 (an escape) maps to its backslash, column 10 (got %d)', [LOutColumn]);

    LOk := LAst.TranslateLocation(LFile, 9, 24, LOutFile, LOutLine, LOutColumn);
    Check(LOk and (LOutColumn = 14),
      'translate: cpp("...") value byte 3 (c, after the escape) maps to column 14 (got %d)', [LOutColumn]);

    LOk := LAst.TranslateLocation(LFile, 9, 20, LOutFile, LOutLine, LOutColumn);
    Check(LOk and (LOutColumn = 3),
      'translate: the ( the emitter writes around cpp("...") maps to the node start, 3 (got %d)', [LOutColumn]);

    LOk := LAst.TranslateLocation(LFile, 10, 6, LOutFile, LOutLine, LOutColumn);
    Check(LOk and (LOutColumn = 10),
      'translate: a raw cpp("...") first value byte maps through its map, column 10 (got %d)', [LOutColumn]);

    LOk := LAst.TranslateLocation(LFile, 11, 2, LOutFile, LOutLine, LOutColumn);
    Check(LOk and (LOutLine = 11) and (LOutColumn = 2),
      'translate: a raw cpp("...") later line maps as copied, column 2 (got %d)', [LOutColumn]);

    LOk := LAst.TranslateLocation(LClangFile, 5, 40, LOutFile, LOutLine, LOutColumn);
    Check((not LOk) and (LOutFile = LClangFile) and (LOutLine = 5) and (LOutColumn = 40),
      'translate: no span covers the column: not mine, location unchanged');

    LOk := LAst.TranslateLocation(LFile, 5, 0, LOutFile, LOutLine, LOutColumn);
    Check(not LOk, 'translate: column 0 (linker error) is not mine');

    LOk := LAst.TranslateLocation('C:\elsewhere\other.pcpp', 5, 7, LOutFile, LOutLine, LOutColumn);
    Check(not LOk, 'translate: a file no module owns is not mine');

    // The method IS a TPCLocationTranslator: the Compiler passes it directly
    LTranslator := LAst.TranslateLocation;
    LOk := LTranslator(LClangFile, 5, 7, LOutFile, LOutLine, LOutColumn);
    Check(LOk and (LOutColumn = 5), 'translate: assignable to TPCLocationTranslator unchanged');
  finally
    LAst.Free();
    LErrors.Free();
  end;
end;

procedure TPCASTTests.DoTestNodeKindsAll();
var
  LAst: TPCAst;
  LNode: TPCNode;
  LDump: string;
  LKind: TPCNodeKind;
  LI: Integer;
  LUses: Integer;
  LOk: Boolean;
begin
  LAst := TPCAst.Create();
  try
    LOk := True;
    for LI := Low(TEST_AST_NODES_CLASSES) to High(TEST_AST_NODES_CLASSES) do
    begin
      LNode := LAst.NewNodeOf(TEST_AST_NODES_CLASSES[LI]);
      LDump := LNode.Dump();
      // A fresh node owns no children, so its dump is exactly one line
      if (LNode.NodeKind <> TEST_AST_NODES_KINDS[LI]) or
        (LDump.IndexOf(sLineBreak) <> LDump.Length - Length(sLineBreak)) then
        LOk := False;
    end;
    Check(LOk, 'kinds: every NODES class sets its own NodeKind; a fresh node dumps one line');

    // CORE + NODES together name every concrete kind exactly once
    LOk := True;
    for LKind := Succ(nkNone) to High(TPCNodeKind) do
    begin
      LUses := 0;
      for LI := Low(TEST_AST_CORE_KINDS) to High(TEST_AST_CORE_KINDS) do
      begin
        if TEST_AST_CORE_KINDS[LI] = LKind then
          Inc(LUses);
      end;
      for LI := Low(TEST_AST_NODES_KINDS) to High(TEST_AST_NODES_KINDS) do
      begin
        if TEST_AST_NODES_KINDS[LI] = LKind then
          Inc(LUses);
      end;
      if LUses <> 1 then
        LOk := False;
    end;
    Check(LOk, 'kinds: CORE + NODES cover every TPCNodeKind but nkNone exactly once');
    Check(LAst.NewNodeOf(TPCMemberItem).NodeKind = nkNone, 'kinds: TPCMemberItem is abstract (nkNone)');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestDecls();
var
  LAst: TPCAst;
  LRoutine: TPCRoutine;
  LVar: TPCVarDecl;
  LConst: TPCConstDecl;
  LFull: TPCTypeDecl;
  LFwd: TPCTypeDecl;
  LExtVar: TPCVarDecl;
  LSleep: TPCRoutine;
  LFwdRoutine: TPCRoutine;
begin
  LAst := TPCAst.Create();
  try
    LRoutine := LAst.NewNode<TPCRoutine>();
    LRoutine.DeclName := 'Add';
    LRoutine.IsExported := True;
    LRoutine.Linkage := lnC;
    LRoutine.ResolvedLinkage := lnCpp;
    LRoutine.IsVariadic := True;
    LRoutine.Params.Add(DoParam(LAst, 'AX', pmConst, DoBuiltin(LAst, tkKwInt32)));
    LRoutine.Params.Add(DoParam(LAst, 'AY', pmNone, DoBuiltin(LAst, tkKwInt32)));
    LRoutine.ReturnType := DoBuiltin(LAst, tkKwInt64);

    LVar := LAst.NewNode<TPCVarDecl>();
    LVar.DeclName := 'LT';
    LVar.TypeExpr := DoBuiltin(LAst, tkKwInt64);
    LVar.InitExpr := DoInt(LAst, 0);
    LRoutine.Decls.Add(LVar);

    LConst := LAst.NewNode<TPCConstDecl>();
    LConst.DeclName := 'CK';
    LConst.TypeExpr := DoBuiltin(LAst, tkKwInt32);
    LConst.ValueExpr := DoInt(LAst, 1);
    LRoutine.Decls.Add(LConst);

    // The full declaration is only referenced: named on the line, never walked
    LFull := LAst.NewNode<TPCTypeDecl>();
    LFull.DeclName := 'TNode';
    LFull.TypeDef := DoBuiltin(LAst, tkKwInt32);
    LFwd := LAst.NewNode<TPCTypeDecl>();
    LFwd.DeclName := 'TNode';
    LFwd.IsForward := True;
    LFwd.ResolvedFull := LFull;
    LRoutine.Decls.Add(LFwd);

    LRoutine.Body := LAst.NewNode<TPCBlock>();
    Check(LRoutine.Dump() = TEST_AST_DUMP_ROUTINE,
      'decls: routine params, return type, decl blocks and body in source order');

    LExtVar := LAst.NewNode<TPCVarDecl>();
    LExtVar.DeclName := 'gLib';
    LExtVar.TypeExpr := LAst.NewNode<TPCPointerType>();
    LExtVar.ExternalClause.IsExternal := True;
    LExtVar.ExternalClause.LibKind := elCString;
    LExtVar.ExternalClause.LibText := 'kernel32';
    LExtVar.ExternalClause.ResolvedLib := 'kernel32';
    Check(LExtVar.Dump() = TEST_AST_DUMP_EXTVAR,
      'decls: external var with a library name dumps it quoted; untyped ptr is a PointerType');

    // The const-name form dumps bare, so the two forms never look alike (decls.md F-D1)
    LExtVar := LAst.NewNode<TPCVarDecl>();
    LExtVar.DeclName := 'gLibK';
    LExtVar.TypeExpr := LAst.NewNode<TPCPointerType>();
    LExtVar.ExternalClause.IsExternal := True;
    LExtVar.ExternalClause.LibKind := elIdentifier;
    LExtVar.ExternalClause.LibText := 'LIBK32';
    LExtVar.ExternalClause.ResolvedLib := 'kernel32';
    Check(LExtVar.Dump() = TEST_AST_DUMP_EXTVAR_NAME,
      'decls: external var with a const name dumps the name bare');

    LSleep := LAst.NewNode<TPCRoutine>();
    LSleep.DeclName := 'Sleep';
    LSleep.ExternalClause.IsExternal := True;
    Check(LSleep.Dump() = 'Routine "Sleep" rnRoutine external' + sLineBreak,
      'decls: external routine without a library text');

    LFwdRoutine := LAst.NewNode<TPCRoutine>();
    LFwdRoutine.DeclName := 'Fwd';
    LFwdRoutine.IsForward := True;
    LFwdRoutine.ResolvedFull := LRoutine;
    Check(LFwdRoutine.Dump() = 'Routine "Fwd" rnRoutine forward full=Routine "Add"' + sLineBreak,
      'decls: forward routine names its full declaration');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestTypes();
var
  LAst: TPCAst;
  LShape: TPCTypeDecl;
  LParent: TPCNamedType;
  LRecord: TPCRecordType;
  LBits: TPCField;
  LOverlay: TPCAnonAggregate;
  LDecl: TPCTypeDecl;
  LObject: TPCRecordType;
  LMethod: TPCMethodItem;
  LChoices: TPCChoicesType;
  LRed: TPCChoiceValue;
  LBlue: TPCChoiceValue;
  LSet: TPCSetType;
  LPointer: TPCPointerType;
  LArray: TPCArrayType;
  LDynamic: TPCArrayType;
  LOpaque: TPCNamedType;
  LArg: TPCTemplateArg;
  LVector: TPCNamePart;
  LCpp: TPCCppType;
  LRoutineType: TPCRoutineType;
  LFundamental: TPCCppType;
begin
  LAst := TPCAst.Create();
  try
    LShape := LAst.NewNode<TPCTypeDecl>();
    LShape.DeclName := 'TShape';
    LParent := LAst.NewNode<TPCNamedType>();
    LParent.Parts := ['Base', 'TShape'];
    LParent.ResolvedKind := rkType;
    LParent.ResolvedDecl := LShape;

    LRecord := LAst.NewNode<TPCRecordType>();
    LRecord.IsPacked := True;
    LRecord.ParentName := LParent;
    LRecord.AlignExpr := DoInt(LAst, 8);
    LRecord.Members.Add(DoField(LAst, 'X', DoBuiltin(LAst, tkKwInt32)));
    LBits := DoField(LAst, 'F', DoBuiltin(LAst, tkKwUint8));
    LBits.BitWidthExpr := DoInt(LAst, 3);
    LRecord.Members.Add(LBits);
    LOverlay := LAst.NewNode<TPCAnonAggregate>();
    LOverlay.IsOverlay := True;
    LOverlay.Members.Add(DoField(LAst, 'A', DoBuiltin(LAst, tkKwInt64)));
    LOverlay.Members.Add(DoField(LAst, 'B', DoBuiltin(LAst, tkKwFloat64)));
    LRecord.Members.Add(LOverlay);

    LDecl := LAst.NewNode<TPCTypeDecl>();
    LDecl.DeclName := 'TPoint';
    LDecl.TypeDef := LRecord;
    Check(LDecl.Dump() = TEST_AST_DUMP_RECORD,
      'types: packed record with parent, align, bitfield and anonymous overlay');

    LObject := LAst.NewNode<TPCRecordType>();
    LObject.IsObject := True;
    LMethod := LAst.NewNode<TPCMethodItem>();
    LMethod.Routine := LAst.NewNode<TPCRoutine>();
    LMethod.Routine.DeclName := 'Run';
    LMethod.Routine.RoutineKind := rnMethod;
    LMethod.Routine.Body := LAst.NewNode<TPCBlock>();
    LObject.Members.Add(LMethod);
    Check(LObject.Dump() = TEST_AST_DUMP_OBJECT, 'types: object owns its method routine');

    LChoices := LAst.NewNode<TPCChoicesType>();
    LRed := LAst.NewNode<TPCChoiceValue>();
    LRed.ValueName := 'cRed';
    LRed.HasResolvedOrdinal := True;
    LRed.ResolvedOrdinal := 0;
    LChoices.Values.Add(LRed);
    LBlue := LAst.NewNode<TPCChoiceValue>();
    LBlue.ValueName := 'cBlue';
    LBlue.ValueExpr := DoInt(LAst, 5);
    LBlue.HasResolvedOrdinal := True;
    LBlue.ResolvedOrdinal := 5;
    LChoices.Values.Add(LBlue);
    Check(LChoices.Dump() = TEST_AST_DUMP_CHOICES,
      'types: a resolved ordinal of 0 shows (HasResolvedOrdinal)');

    LSet := LAst.NewNode<TPCSetType>();
    LSet.IsRangeForm := True;
    LSet.LowExpr := DoInt(LAst, 0);
    LSet.HighExpr := DoInt(LAst, 31);
    LPointer := LAst.NewNode<TPCPointerType>();
    LPointer.IsConstTarget := True;
    LPointer.TargetType := DoBuiltin(LAst, tkKwChar);
    LArray := LAst.NewNode<TPCArrayType>();
    LArray.LowExpr := DoInt(LAst, 0);
    LArray.HighExpr := DoInt(LAst, 9);
    LArray.ElementType := LPointer;
    LDynamic := LAst.NewNode<TPCArrayType>();
    LDynamic.IsDynamic := True;
    LDynamic.ElementType := DoBuiltin(LAst, tkKwString);

    // const std::vector<int32_t>* const&
    LOpaque := LAst.NewNode<TPCNamedType>();
    LOpaque.Parts := ['int32_t'];
    LOpaque.ResolvedKind := rkOpaque;
    LArg := LAst.NewNode<TPCTemplateArg>();
    LArg.TypeArg := LOpaque;
    LVector := DoPart(LAst, 'vector');
    LVector.HasTemplateArgs := True;
    LVector.TemplateArgs.Add(LArg);
    LCpp := LAst.NewNode<TPCCppType>();
    LCpp.LeadCv := [cqConst];
    LCpp.NameParts.Add(DoPart(LAst, 'std'));
    LCpp.NameParts.Add(LVector);
    SetLength(LCpp.PointerLevels, 1);
    LCpp.PointerLevels[0] := [cqConst];
    LCpp.RefKind := rfLValue;

    LRoutineType := LAst.NewNode<TPCRoutineType>();
    LRoutineType.Linkage := lnC;
    LRoutineType.IsVariadic := True;
    LRoutineType.Params.Add(DoParam(LAst, 'AS', pmVar, LSet));
    LRoutineType.Params.Add(DoParam(LAst, 'AA', pmNone, LArray));
    LRoutineType.Params.Add(DoParam(LAst, 'AD', pmConst, LDynamic));
    LRoutineType.ReturnType := LCpp;
    Check(LRoutineType.Dump() = TEST_AST_DUMP_ROUTINE_TYPE,
      'types: routine type over set, array, dynamic array and a C++ return type');

    // unsigned long long const volatile * * volatile &&
    LFundamental := LAst.NewNode<TPCCppType>();
    SetLength(LFundamental.Fundamentals, 3);
    LFundamental.Fundamentals[0] := tkKwUnsigned;
    LFundamental.Fundamentals[1] := tkKwLong;
    LFundamental.Fundamentals[2] := tkKwLong;
    LFundamental.TrailCv := [cqConst, cqVolatile];
    SetLength(LFundamental.PointerLevels, 2);
    LFundamental.PointerLevels[0] := [];
    LFundamental.PointerLevels[1] := [cqVolatile];
    LFundamental.RefKind := rfRValue;
    Check(LFundamental.Dump() =
      'CppType tkKwUnsigned tkKwLong tkKwLong trail=const+volatile * *volatile &&' + sLineBreak,
      'types: C++ fundamentals, trailing cv, cv per pointer level, rvalue reference');
    Check(LAst.NewNode<TPCSetType>().Dump() = 'SetType' + sLineBreak, 'types: bare set');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestStmts();
var
  LAst: TPCAst;
  LBlock: TPCBlock;
  LIf: TPCIf;
  LReturn: TPCReturn;
  LWhile: TPCWhile;
  LIter: TPCVarDecl;
  LFor: TPCFor;
  LCall: TPCCall;
  LRepeat: TPCRepeat;
  LMatch: TPCMatch;
  LArm: TPCMatchArm;
  LLabel: TPCMatchLabel;
  LGuard: TPCGuard;
begin
  LAst := TPCAst.Create();
  try
    LBlock := LAst.NewNode<TPCBlock>();

    LIf := LAst.NewNode<TPCIf>();
    LIf.Condition := DoName(LAst, 'LOk');
    LReturn := LAst.NewNode<TPCReturn>();
    LReturn.ValueExpr := DoInt(LAst, 1);
    LIf.ThenStmts.Add(LReturn);
    LIf.HasElse := True;
    LIf.ElseStmts.Add(LAst.NewNode<TPCReturn>());
    LBlock.Stmts.Add(LIf);

    LWhile := LAst.NewNode<TPCWhile>();
    LWhile.Condition := DoBool(LAst, True);
    LWhile.Stmts.Add(LAst.NewNode<TPCLeave>());
    LBlock.Stmts.Add(LWhile);

    LIter := LAst.NewNode<TPCVarDecl>();
    LIter.DeclName := 'LI';
    LFor := LAst.NewNode<TPCFor>();
    LFor.IteratorName := 'LI';
    LFor.ResolvedIterator := LIter;
    LFor.StartExpr := DoInt(LAst, 9);
    LFor.EndExpr := DoInt(LAst, 0);
    LFor.IsDownTo := True;
    LFor.Stmts.Add(LAst.NewNode<TPCSkip>());
    LBlock.Stmts.Add(LFor);

    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := DoName(LAst, 'Tick');
    LRepeat := LAst.NewNode<TPCRepeat>();
    LRepeat.Stmts.Add(DoStmt(LAst, LCall));
    LRepeat.Condition := DoBool(LAst, False);
    LBlock.Stmts.Add(LRepeat);

    LMatch := LAst.NewNode<TPCMatch>();
    LMatch.Subject := DoName(LAst, 'LK');
    LArm := LAst.NewNode<TPCMatchArm>();
    LLabel := LAst.NewNode<TPCMatchLabel>();
    LLabel.LowExpr := DoInt(LAst, 1);
    LArm.Labels.Add(LLabel);
    LLabel := LAst.NewNode<TPCMatchLabel>();
    LLabel.LowExpr := DoInt(LAst, 3);
    LLabel.HighExpr := DoInt(LAst, 5);
    LArm.Labels.Add(LLabel);
    LArm.Stmts.Add(LAst.NewNode<TPCLeave>());
    LMatch.Arms.Add(LArm);
    LMatch.HasElse := True;
    LMatch.ElseStmts.Add(LAst.NewNode<TPCSkip>());
    LBlock.Stmts.Add(LMatch);

    LGuard := LAst.NewNode<TPCGuard>();
    LGuard.GuardStmts.Add(LAst.NewNode<TPCSkip>());
    LGuard.HasFinally := True;
    LGuard.FinallyStmts.Add(LAst.NewNode<TPCLeave>());
    LBlock.Stmts.Add(LGuard);

    Check(LBlock.Dump() = TEST_AST_DUMP_STMTS,
      'stmts: every statement form; counts separate then / else and guard / finally');

    LGuard := LAst.NewNode<TPCGuard>();
    LGuard.HasExcept := True;
    LGuard.HasFinally := True;
    Check(LGuard.Dump() = 'Guard guard=0 except=0 finally=0' + sLineBreak,
      'stmts: except and finally counts show when present, even empty');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestExprs();
var
  LAst: TPCAst;
  LUnary: TPCUnary;
  LBinary: TPCBinary;
  LAssign: TPCAssign;
  LBlock: TPCBlock;
  LCall: TPCCall;
  LArg: TPCTemplateArg;
  LMax: TPCNamePart;
  LName: TPCName;
  LField: TPCField;
  LMember: TPCMember;
  LIndex: TPCIndex;
  LTernary: TPCTernary;
  LCast: TPCCast;
  LNew: TPCNew;
  LDelete: TPCDelete;
  LBraced: TPCBracedInit;
  LSet: TPCSetLiteral;
  LElement: TPCSetElement;
  LRecord: TPCRecordLiteral;
  LInit: TPCFieldInit;
  LVarargs: TPCVarargs;
begin
  LAst := TPCAst.Create();
  try
    // LX += -LA * 2
    LUnary := LAst.NewNode<TPCUnary>();
    LUnary.Op := uoNegate;
    LUnary.Operand := DoName(LAst, 'LA');
    LBinary := LAst.NewNode<TPCBinary>();
    LBinary.Op := boMul;
    LBinary.Left := LUnary;
    LBinary.Right := DoInt(LAst, 2);
    LAssign := LAst.NewNode<TPCAssign>();
    LAssign.Op := aoAddAssign;
    LAssign.Target := DoName(LAst, 'LX');
    LAssign.ValueExpr := LBinary;
    Check(LAssign.Dump() = TEST_AST_DUMP_ASSIGN, 'exprs: assignment, binary and unary by meaning');

    LBlock := LAst.NewNode<TPCBlock>();
    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := DoName(LAst, 'testAssertEqualInt');
    LCall.Args.Add(DoInt(LAst, 1));
    LCall.Args.Add(DoInt(LAst, 1));
    LCall.ResolvedType := LAst.VoidType();
    LCall.ResolvedKind := rkIntrinsic;
    LCall.IntrinsicKind := ikTestAssertEqualInt;
    LCall.ResolvedInTest := True;
    LBlock.Stmts.Add(DoStmt(LAst, LCall));

    // size(int64): an unmistakable type has its own slot (parser.md "size(T) argument")
    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := DoName(LAst, 'size');
    LCall.TypeArg := DoBuiltin(LAst, tkKwInt64);
    LCall.HasConstValue := True;
    LCall.ConstInt := 8;
    LCall.ResolvedKind := rkIntrinsic;
    LCall.IntrinsicKind := ikSize;
    LBlock.Stmts.Add(DoStmt(LAst, LCall));

    // ::std::max<int>(LA, LB)
    LArg := LAst.NewNode<TPCTemplateArg>();
    LArg.TypeArg := DoCppInt(LAst);
    LMax := DoPart(LAst, 'max');
    LMax.HasTemplateArgs := True;
    LMax.TemplateArgs.Add(LArg);
    LName := LAst.NewNode<TPCName>();
    LName.HasLeadingScope := True;
    LName.Parts.Add(DoPart(LAst, 'std'));
    LName.Parts.Add(LMax);
    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := LName;
    LCall.Args.Add(DoName(LAst, 'LA'));
    LCall.Args.Add(DoName(LAst, 'LB'));
    LCall.ResolvedType := LAst.OpaqueType();
    LCall.ResolvedKind := rkOpaque;
    LBlock.Stmts.Add(DoStmt(LAst, LCall));
    Check(LBlock.Dump() = TEST_AST_DUMP_CALLS,
      'exprs: intrinsic in a test, size(T) type slot, scoped C++ name with template args');

    LBlock := LAst.NewNode<TPCBlock>();

    // LP->X[0] ? nullptr : this
    LField := DoField(LAst, 'X', DoBuiltin(LAst, tkKwInt32));
    LMember := LAst.NewNode<TPCMember>();
    LMember.Base := DoName(LAst, 'LP');
    LMember.Access := maArrow;
    LMember.Member := DoPart(LAst, 'X');
    LMember.ResolvedKind := rkField;
    LMember.ResolvedDecl := LField;
    LIndex := LAst.NewNode<TPCIndex>();
    LIndex.Base := LMember;
    LIndex.IndexExpr := DoInt(LAst, 0);
    LTernary := LAst.NewNode<TPCTernary>();
    LTernary.Condition := LIndex;
    LTernary.ThenExpr := DoSpecial(LAst, skNullptr);
    LTernary.ElseExpr := DoSpecial(LAst, skThis);
    LBlock.Stmts.Add(DoStmt(LAst, LTernary));

    LCast := LAst.NewNode<TPCCast>();
    LCast.CastKind := ckStatic;
    LCast.TargetType := DoCppInt(LAst);
    LCast.Operand := DoName(LAst, 'LD');
    LBlock.Stmts.Add(DoStmt(LAst, LCast));

    LNew := LAst.NewNode<TPCNew>();
    LNew.TargetType := DoCppInt(LAst);
    LNew.InitKind := niArraySize;
    LNew.SizeExpr := DoInt(LAst, 10);
    LBlock.Stmts.Add(DoStmt(LAst, LNew));

    LDelete := LAst.NewNode<TPCDelete>();
    LDelete.IsArray := True;
    LDelete.Operand := DoName(LAst, 'LP');
    LBlock.Stmts.Add(DoStmt(LAst, LDelete));

    // LV.push_back({1, 2}): a bare braced init as an argument
    LMember := LAst.NewNode<TPCMember>();
    LMember.Base := DoName(LAst, 'LV');
    LMember.Member := DoPart(LAst, 'push_back');
    LBraced := LAst.NewNode<TPCBracedInit>();
    LBraced.Args.Add(DoInt(LAst, 1));
    LBraced.Args.Add(DoInt(LAst, 2));
    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := LMember;
    LCall.Args.Add(LBraced);
    LBlock.Stmts.Add(DoStmt(LAst, LCall));

    LBraced := LAst.NewNode<TPCBracedInit>();
    LBraced.Base := DoName(LAst, 'T');
    LBraced.Args.Add(DoInt(LAst, 3));
    LBlock.Stmts.Add(DoStmt(LAst, LBraced));

    // [1, 3..5]
    LSet := LAst.NewNode<TPCSetLiteral>();
    LElement := LAst.NewNode<TPCSetElement>();
    LElement.LowExpr := DoInt(LAst, 1);
    LSet.Elements.Add(LElement);
    LElement := LAst.NewNode<TPCSetElement>();
    LElement.LowExpr := DoInt(LAst, 3);
    LElement.HighExpr := DoInt(LAst, 5);
    LSet.Elements.Add(LElement);
    LBlock.Stmts.Add(DoStmt(LAst, LSet));

    // TPoint(x: 10)
    LRecord := LAst.NewNode<TPCRecordLiteral>();
    LRecord.RecordType := LAst.NewNode<TPCNamedType>();
    LRecord.RecordType.Parts := ['TPoint'];
    LInit := LAst.NewNode<TPCFieldInit>();
    LInit.FieldName := 'x';
    LInit.ValueExpr := DoInt(LAst, 10);
    LInit.ResolvedField := DoField(LAst, 'x', DoBuiltin(LAst, tkKwInt32));
    LRecord.Inits.Add(LInit);
    LBlock.Stmts.Add(DoStmt(LAst, LRecord));

    LVarargs := LAst.NewNode<TPCVarargs>();
    LVarargs.VarargsKind := vaNext;
    LVarargs.ReadType := DoBuiltin(LAst, tkKwInt32);
    LBlock.Stmts.Add(DoStmt(LAst, LVarargs));
    Check(LBlock.Dump() = TEST_AST_DUMP_CPP,
      'exprs: member, index, ternary, specials, cast, new, delete, braced, set, record literal, varargs');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestResolvedRefs();
var
  LAst: TPCAst;
  LTarget: TPCRoutine;
  LIter: TPCVarDecl;
  LFull: TPCTypeDecl;
  LCall: TPCCall;
  LFor: TPCFor;
  LFwd: TPCTypeDecl;
  LBlock: TPCBlock;
  LCount: Integer;
  LForeign: Boolean;
  LWalk: TPCNodeVisitor;
begin
  LAst := TPCAst.Create();
  try
    // Foreign nodes: reachable from the tree only through Resolved* fields
    LTarget := LAst.NewNode<TPCRoutine>();
    LTarget.DeclName := 'Tick';
    LTarget.Params.Add(DoParam(LAst, 'AN', pmNone, DoBuiltin(LAst, tkKwInt32)));
    LTarget.Body := LAst.NewNode<TPCBlock>();
    LIter := LAst.NewNode<TPCVarDecl>();
    LIter.DeclName := 'LI';
    LIter.TypeExpr := DoBuiltin(LAst, tkKwInt32);
    LFull := LAst.NewNode<TPCTypeDecl>();
    LFull.DeclName := 'TNode';
    LFull.TypeDef := DoBuiltin(LAst, tkKwInt32);

    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := DoName(LAst, 'Tick');
    LCall.Args.Add(DoInt(LAst, 1));
    LCall.ResolvedKind := rkRoutine;
    LCall.ResolvedDecl := LTarget;
    LFor := LAst.NewNode<TPCFor>();
    LFor.IteratorName := 'LI';
    LFor.ResolvedIterator := LIter;
    LFor.StartExpr := DoInt(LAst, 0);
    LFor.EndExpr := DoInt(LAst, 3);
    LFor.Stmts.Add(DoStmt(LAst, LCall));
    LFwd := LAst.NewNode<TPCTypeDecl>();
    LFwd.DeclName := 'TNode';
    LFwd.IsForward := True;
    LFwd.ResolvedFull := LFull;
    LBlock := LAst.NewNode<TPCBlock>();
    LBlock.Stmts.Add(LFor);
    LBlock.Stmts.Add(LFwd);

    // Owned nodes: Block, For, 0, 3, ExprStmt, Call, Name, NamePart, 1, TypeDecl
    LCount := 0;
    LForeign := False;
    LWalk :=
      procedure(const ANode: TPCNode)
      begin
        Inc(LCount);
        if (ANode = LTarget) or (ANode = LIter) or (ANode = LFull) then
          LForeign := True;
        ANode.EnumChildren(LWalk);
      end;
    try
      LWalk(LBlock);
    finally
      // The visitor captures itself: clear it to break the reference cycle
      LWalk := nil;
    end;
    Check(LCount = 10, 'refs: the walk visits the 10 owned nodes and nothing else');
    Check(not LForeign, 'refs: Resolved* targets (decl, iterator, full) are never walked');
    Check(LBlock.Dump() = TEST_AST_DUMP_REFS, 'refs: each reference is named on its node''s line');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestTypeText();
var
  LAst: TPCAst;
  LPtr: TPCPointerType;
  LNamed: TPCNamedType;
  LArray: TPCArrayType;
  LBound: TPCName;
  LSet: TPCSetType;
  LRoutine: TPCRoutineType;
  LCpp: TPCCppType;
  LInner: TPCCppType;
  LRecord: TPCRecordType;
  LDerived: TPCDerivedType;
  LLit: TPCLiteral;
begin
  LAst := TPCAst.Create();
  try
    Check((DoBuiltin(LAst, tkKwInt32).TypeText() = 'int32') and
      (DoBuiltin(LAst, tkKwWstring).TypeText() = 'wstring'), 'types: a builtin spells its keyword');
    LPtr := LAst.NewNode<TPCPointerType>();
    Check(LPtr.TypeText() = 'ptr', 'types: an untyped pointer is ptr');
    LPtr.TargetType := DoBuiltin(LAst, tkKwChar);
    LPtr.IsConstTarget := True;
    Check(LPtr.TypeText() = 'ptr to const char', 'types: ptr to const char');
    LNamed := LAst.NewNode<TPCNamedType>();
    LNamed.Parts := ['Geo', 'TPoint'];
    Check(LNamed.TypeText() = 'Geo.TPoint', 'types: a qualified name joins with .');

    LArray := LAst.NewNode<TPCArrayType>();
    LArray.IsDynamic := True;
    LArray.ElementType := DoBuiltin(LAst, tkKwInt32);
    Check(LArray.TypeText() = 'array of int32', 'types: a dynamic array');
    LArray := LAst.NewNode<TPCArrayType>();
    LArray.LowExpr := DoInt(LAst, 0);
    LArray.HighExpr := DoInt(LAst, 9);
    LArray.ElementType := DoBuiltin(LAst, tkKwInt32);
    Check(LArray.TypeText() = 'array[0..9] of int32', 'types: a static array spells its bounds');
    LBound := DoName(LAst, 'N');
    LBound.HasConstValue := True;
    LBound.ConstInt := 9;
    LArray.LowExpr := DoInt(LAst, 1);
    LArray.HighExpr := LBound;
    Check(LArray.TypeText() = 'array[1..9] of int32', 'types: a folded bound prints its value');
    LArray.HighExpr := DoName(LAst, 'M');
    Check(LArray.TypeText() = 'array[1..M] of int32', 'types: an unfolded bound prints its expression');

    LSet := LAst.NewNode<TPCSetType>();
    LSet.ElementType := DoNamed(LAst, 'TColor', nil);
    Check(LSet.TypeText() = 'set of TColor', 'types: a set of an element type');
    LSet := LAst.NewNode<TPCSetType>();
    LSet.IsRangeForm := True;
    LSet.LowExpr := DoInt(LAst, 0);
    LSet.HighExpr := DoInt(LAst, 63);
    Check(LSet.TypeText() = 'set of 0..63', 'types: a range set');

    LRoutine := LAst.NewNode<TPCRoutineType>();
    Check(LRoutine.TypeText() = 'routine()', 'types: a bare routine type');
    LRoutine.Linkage := lnC;
    LRoutine.Params.Add(DoParam(LAst, 'AN', pmNone, DoBuiltin(LAst, tkKwInt32)));
    LRoutine.Params.Add(DoParam(LAst, 'AS', pmVar, DoBuiltin(LAst, tkKwString)));
    LRoutine.IsVariadic := True;
    LRoutine.ReturnType := DoBuiltin(LAst, tkKwBool);
    Check(LRoutine.TypeText() = 'routine clink(AN: int32; var AS: string; ...): bool',
      'types: a routine type with linkage, modes, varargs and a result');

    LCpp := DoCppName(LAst, ['std', 'string']);
    LCpp.LeadCv := [cqConst];
    LCpp.RefKind := rfLValue;
    Check(LCpp.TypeText() = 'const std::string&', 'cpp types: lead cv and a reference');
    LCpp := LAst.NewNode<TPCCppType>();
    SetLength(LCpp.Fundamentals, 1);
    LCpp.Fundamentals[0] := tkKwChar;
    LCpp.TrailCv := [cqConst];
    SetLength(LCpp.PointerLevels, 1);
    LCpp.PointerLevels[0] := [cqConst];
    Check(LCpp.TypeText() = 'char const* const', 'cpp types: trail cv and a const pointer level');
    LInner := DoCppName(LAst, ['std', 'vector']);
    LInner.NameParts[1].HasTemplateArgs := True;
    LInner.NameParts[1].TemplateArgs.Add(DoTypeArg(LAst, DoCppInt(LAst)));
    LCpp := DoCppName(LAst, ['std', 'vector']);
    LCpp.NameParts[1].HasTemplateArgs := True;
    LCpp.NameParts[1].TemplateArgs.Add(DoTypeArg(LAst, LInner));
    Check(LCpp.TypeText() = 'std::vector<std::vector<int>>', 'cpp types: nested template arguments');
    LCpp := DoCppName(LAst, ['std', 'array']);
    LCpp.NameParts[1].HasTemplateArgs := True;
    LCpp.NameParts[1].TemplateArgs.Add(DoTypeArg(LAst, DoCppInt(LAst)));
    LCpp.NameParts[1].TemplateArgs.Add(DoExprArg(LAst,
      DoBinary(LAst, DoName(LAst, 'FOO'), boAdd, DoInt(LAst, 1))));
    Check(LCpp.TypeText() = 'std::array<int, FOO + 1>',
      'cpp types: an unfolded expression argument is spelled (Q-PA1)');
    LCpp := DoCppName(LAst, ['stat']);
    LCpp.HasElaborated := True;
    LCpp.ElaboratedKey := tkKwStruct;
    Check(LCpp.TypeText() = 'struct stat', 'cpp types: an elaborated key');

    LRecord := LAst.NewNode<TPCRecordType>();
    Check(LRecord.TypeText() = 'record', 'types: an anonymous record definition');
    LRecord.IsObject := True;
    Check((LRecord.TypeText() = 'object') and
      (LAst.NewNode<TPCOverlayType>().TypeText() = 'overlay') and
      (LAst.NewNode<TPCChoicesType>().TypeText() = 'choices'), 'types: object, overlay, choices');
    Check((LAst.OpaqueType().TypeText() = 'opaque') and (LAst.ErrorType().TypeText() = 'error') and
      (LAst.NilType().TypeText() = 'nil') and (LAst.VoidType().TypeText() = 'void') and
      (LAst.StringLiteralType(False).TypeText() = 'string literal') and
      (LAst.StringLiteralType(True).TypeText() = 'wide string literal'),
      'types: the shared synthesized types');

    LDerived := LAst.NewNode<TPCDerivedType>();
    Check(LDerived.TypeText() = 'ptr', 'derived: a pointer with no target is ptr');
    LDerived.Target := LAst.BuiltinType(tkKwInt32);
    LDerived.IsConstTarget := True;
    Check(LDerived.TypeText() = 'ptr to const int32', 'derived: ptr to const int32');
    Check(LDerived.Dump() = 'DerivedType dkPointerTo const target="int32"' + sLineBreak,
      'derived: the target is named on its line, never walked');
    LDerived := LAst.NewNode<TPCDerivedType>();
    LDerived.DerivedKind := dkSetOf;
    LDerived.Target := DoNamed(LAst, 'TColor', nil);
    Check(LDerived.TypeText() = 'set of TColor', 'derived: a set of the element type');

    LLit := DoInt(LAst, 1);
    LLit.ResolvedType := LAst.BuiltinType(tkKwInt32);
    LLit.HasConstValue := True;
    LLit.ConstInt := 1;
    Check(LLit.Dump() = 'Literal lkInteger "1" value=1 type="int32" const=1' + sLineBreak,
      'dump: type= is the quoted TypeText');
    LLit := LAst.NewNode<TPCLiteral>();
    LLit.LiteralKind := lkFloat;
    LLit.Text := '0.5';
    LLit.HasValue := True;
    LLit.FloatValue := 0.5;
    LLit.HasConstFloat := True;
    LLit.ConstFloat := 0.5;
    Check(LLit.Dump() = 'Literal lkFloat "0.5" value=0.5 constf=0.5' + sLineBreak,
      'dump: a folded float shows constf=');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestSignature();
var
  LAst: TPCAst;
  LType: TPCRoutineType;
  LRoutine: TPCRoutine;
  LSig: TPCSignature;
begin
  // PLAN-RECORDS R5 / M7 / F-R3b: one signature view, the meant linkage
  LAst := TPCAst.Create();
  try
    LType := LAst.NewNode<TPCRoutineType>();
    Check(LType.MeantLinkage() = lnCpp, 'signature: no linkage word means cpplink');
    LType.Linkage := lnCpp;
    LType.Params.Add(DoParam(LAst, 'AN', pmConst, DoBuiltin(LAst, tkKwInt32)));
    LType.ReturnType := DoBuiltin(LAst, tkKwInt32);
    Check((LType.MeantLinkage() = lnCpp) and (LType.TypeText() = 'routine(const AN: int32): int32'),
      'signature: a written cpplink is the default and spells as it (got ' + LType.TypeText() + ')');
    LType.Linkage := lnC;
    LSig := LType.Signature();
    Check((LSig.Linkage = lnC) and (LSig.Params = LType.Params) and (LSig.ReturnType = LType.ReturnType) and
      (not LSig.IsVariadic) and (LSig.Text() = 'routine clink(const AN: int32): int32'),
      'signature: a routine type''s view (got ' + LSig.Text() + ')');
    LRoutine := LAst.NewNode<TPCRoutine>();
    LRoutine.Params.Add(DoParam(LAst, 'AS', pmVar, DoBuiltin(LAst, tkKwString)));
    LRoutine.IsVariadic := True;
    LSig := LRoutine.Signature();
    Check((LRoutine.MeantLinkage() = lnCpp) and (LSig.Text() = 'routine(var AS: string; ...)'),
      'signature: a routine with no word, before SEM (got ' + LSig.Text() + ')');
    LRoutine.Linkage := lnC;
    Check(LRoutine.MeantLinkage() = lnC, 'signature: a written clink, before SEM');
    LRoutine.ResolvedLinkage := lnCpp;
    Check((LRoutine.MeantLinkage() = lnCpp) and (LRoutine.Signature().Linkage = lnCpp),
      'signature: SEM''s linkage wins (an overload set''s demotion)');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestExprText();
var
  LAst: TPCAst;
  LMember: TPCMember;
  LCall: TPCCall;
  LCast: TPCCast;
  LIndex: TPCIndex;
  LAssign: TPCAssign;
  LTernary: TPCTernary;
  LSet: TPCSetLiteral;
  LElement: TPCSetElement;
  LRecord: TPCRecordLiteral;
  LInit: TPCFieldInit;
  LVarargs: TPCVarargs;
  LNew: TPCNew;
  LDelete: TPCDelete;
  LVerbatim: TPCVerbatimExpr;
  LName: TPCName;
  LBraced: TPCBracedInit;
  LArray: TPCArrayType;
begin
  LAst := TPCAst.Create();
  try
    Check(DoBinary(LAst, DoBinary(LAst, DoName(LAst, 'a'), boAdd, DoName(LAst, 'b')), boMul,
      DoName(LAst, 'c')).ExprText() = '(a + b) * c', 'exprs: a looser operand gets its parentheses back');
    Check(DoBinary(LAst, DoName(LAst, 'a'), boSub, DoBinary(LAst, DoName(LAst, 'b'), boSub,
      DoName(LAst, 'c'))).ExprText() = 'a - (b - c)', 'exprs: left associative: a right operand of equal power');
    Check(DoBinary(LAst, DoBinary(LAst, DoName(LAst, 'a'), boSub, DoName(LAst, 'b')), boSub,
      DoName(LAst, 'c')).ExprText() = 'a - b - c', 'exprs: left associative: no parentheses on the left');
    Check(DoBinary(LAst, DoBinary(LAst, DoName(LAst, 'a'), boEq, DoName(LAst, 'b')), boEq,
      DoName(LAst, 'c')).ExprText() = '(a = b) = c', 'exprs: relational operators do not chain');
    Check(DoBinary(LAst, DoUnary(LAst, uoLogNot, DoName(LAst, 'done')), boLogAnd,
      DoName(LAst, 'ok')).ExprText() = 'not done and ok', 'exprs: not binds tighter than and');
    Check(DoUnary(LAst, uoLogNot, DoBinary(LAst, DoName(LAst, 'a'), boLogAnd,
      DoName(LAst, 'b'))).ExprText() = 'not (a and b)', 'exprs: a binary operand of not');
    Check(DoUnary(LAst, uoNegate, DoUnary(LAst, uoNegate, DoInt(LAst, 1))).ExprText() = '- -1',
      'exprs: - - is spaced, never --');
    // F-R4a: address of and & are spelled address of (BNF prefix op), as a message prints them
    Check(DoUnary(LAst, uoAddressOf, DoUnary(LAst, uoAddressOf, DoName(LAst, 'x'))).ExprText() =
      'address of address of x', 'exprs: address of is spelled address of, never &: ' +
      DoUnary(LAst, uoAddressOf, DoUnary(LAst, uoAddressOf, DoName(LAst, 'x'))).ExprText());
    Check(DoUnary(LAst, uoPostInc, DoName(LAst, 'x')).ExprText() = 'x++', 'exprs: postfix ++');

    LMember := LAst.NewNode<TPCMember>();
    LMember.Base := DoUnary(LAst, uoDeref, DoName(LAst, 'P'));
    LMember.Access := maDot;
    LMember.Member := DoPart(LAst, 'X');
    Check(LMember.ExprText() = 'P^.X', 'exprs: deref is postfix ^');
    LMember := LAst.NewNode<TPCMember>();
    LMember.Base := DoName(LAst, 'p');
    LMember.Access := maArrow;
    LMember.Member := DoPart(LAst, 'next');
    Check(LMember.ExprText() = 'p->next', 'exprs: ->');

    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := DoName(LAst, 'F');
    LCall.Args.Add(DoInt(LAst, 1));
    LCall.Args.Add(DoName(LAst, 'a'));
    Check(LCall.ExprText() = 'F(1, a)', 'exprs: a call');
    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := DoName(LAst, 'size');
    LCall.TypeArg := DoBuiltin(LAst, tkKwInt64);
    Check(LCall.ExprText() = 'size(int64)', 'exprs: a type argument');
    // Written order (F-R3): TypeArg sits at TypeArgIndex among the arguments
    LMember := LAst.NewNode<TPCMember>();
    LMember.Base := DoName(LAst, 'L');
    LMember.Access := maDot;
    LMember.Member := DoPart(LAst, 'get');
    LArray := LAst.NewNode<TPCArrayType>();
    LArray.IsDynamic := True;
    LArray.ElementType := DoBuiltin(LAst, tkKwInt32);
    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := LMember;
    LCall.Args.Add(DoBinary(LAst, DoName(LAst, 'i'), boAdd, DoInt(LAst, 1)));
    LCall.TypeArg := LArray;
    LCall.TypeArgIndex := 1;
    Check(LCall.ExprText() = 'L.get(i + 1, array of int32)',
      'exprs: get(I, T) prints the type argument after the index');
    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := DoName(LAst, 'f');
    LCall.Args.Add(DoName(LAst, 'a'));
    LCall.Args.Add(DoName(LAst, 'b'));
    LCall.TypeArg := DoBuiltin(LAst, tkKwInt32);
    LCall.TypeArgIndex := 1;
    Check(LCall.ExprText() = 'f(a, int32, b)', 'exprs: a type argument between two expressions');
    LMember := LAst.NewNode<TPCMember>();
    LMember.Base := DoName(LAst, 'L');
    LMember.Access := maDot;
    LMember.Member := DoPart(LAst, 'next');
    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := LMember;
    LCall.TypeArg := DoNamed(LAst, 'TPoint', nil);
    Check(LCall.ExprText() = 'L.next(TPoint)', 'exprs: next(T) on a local: the type is the only argument');

    LCast := LAst.NewNode<TPCCast>();
    LCast.CastKind := ckBuiltin;
    LCast.TargetType := DoBuiltin(LAst, tkKwInt64);
    LCast.Operand := DoName(LAst, 'a');
    Check(LCast.ExprText() = 'int64(a)', 'exprs: a builtin cast');
    LCast := LAst.NewNode<TPCCast>();
    LCast.CastKind := ckStatic;
    LCast.TargetType := DoCppInt(LAst);
    LCast.Operand := DoName(LAst, 'a');
    Check(LCast.ExprText() = 'static_cast<int>(a)', 'exprs: a named cast');
    LCast := LAst.NewNode<TPCCast>();
    LCast.CastKind := ckCStyle;
    LCast.TargetType := DoCppInt(LAst);
    LCast.Operand := DoBinary(LAst, DoName(LAst, 'a'), boAdd, DoName(LAst, 'b'));
    Check(LCast.ExprText() = '(int)(a + b)', 'exprs: a C-style cast binds as a prefix');

    LIndex := LAst.NewNode<TPCIndex>();
    LIndex.Base := DoName(LAst, 'A');
    LIndex.IndexExpr := DoInt(LAst, 0);
    Check(LIndex.ExprText() = 'A[0]', 'exprs: an index');
    LAssign := LAst.NewNode<TPCAssign>();
    LAssign.Target := DoName(LAst, 'a');
    LAssign.Op := aoAddAssign;
    LAssign.ValueExpr := DoInt(LAst, 1);
    Check(LAssign.ExprText() = 'a += 1', 'exprs: a compound assignment');
    LTernary := LAst.NewNode<TPCTernary>();
    LTernary.Condition := DoName(LAst, 'c');
    LTernary.ThenExpr := DoInt(LAst, 1);
    LTernary.ElseExpr := DoInt(LAst, 2);
    Check(LTernary.ExprText() = 'c ? 1 : 2', 'exprs: a ternary');

    LSet := LAst.NewNode<TPCSetLiteral>();
    LElement := LAst.NewNode<TPCSetElement>();
    LElement.LowExpr := DoInt(LAst, 1);
    LSet.Elements.Add(LElement);
    LElement := LAst.NewNode<TPCSetElement>();
    LElement.LowExpr := DoInt(LAst, 3);
    LElement.HighExpr := DoInt(LAst, 5);
    LSet.Elements.Add(LElement);
    Check(LSet.ExprText() = '[1, 3..5]', 'exprs: a set literal with a range');
    LRecord := LAst.NewNode<TPCRecordLiteral>();
    LRecord.RecordType := DoNamed(LAst, 'TPoint', nil);
    LInit := LAst.NewNode<TPCFieldInit>();
    LInit.FieldName := 'x';
    LInit.ValueExpr := DoInt(LAst, 10);
    LRecord.Inits.Add(LInit);
    LInit := LAst.NewNode<TPCFieldInit>();
    LInit.FieldName := 'y';
    LInit.ValueExpr := DoInt(LAst, 20);
    LRecord.Inits.Add(LInit);
    Check(LRecord.ExprText() = 'TPoint(x: 10, y: 20)', 'exprs: a record literal');

    LVarargs := LAst.NewNode<TPCVarargs>();
    LVarargs.VarargsKind := vaNext;
    LVarargs.ReadType := DoBuiltin(LAst, tkKwInt32);
    Check(LVarargs.ExprText() = 'varargs.next(int32)', 'exprs: varargs.next');
    LVarargs := LAst.NewNode<TPCVarargs>();
    LVarargs.VarargsKind := vaGet;
    LVarargs.IndexExpr := DoBinary(LAst, DoName(LAst, 'i'), boAdd, DoInt(LAst, 1));
    LArray := LAst.NewNode<TPCArrayType>();
    LArray.IsDynamic := True;
    LArray.ElementType := DoBuiltin(LAst, tkKwInt32);
    LVarargs.ReadType := LArray;
    Check(LVarargs.ExprText() = 'varargs.get(i + 1, array of int32)', 'exprs: varargs.get');
    LVarargs := LAst.NewNode<TPCVarargs>();
    LVarargs.VarargsKind := vaGet;
    Check(LVarargs.ExprText() = 'varargs.get(error, error)',
      'exprs: varargs.get with no index and no type prints error for each');
    LVarargs := LAst.NewNode<TPCVarargs>();
    LVarargs.VarargsKind := vaReset;
    Check(LVarargs.ExprText() = 'varargs.reset()', 'exprs: varargs.reset');
    LVarargs := LAst.NewNode<TPCVarargs>();
    LVarargs.VarargsKind := vaCopy;
    Check(LVarargs.ExprText() = 'varargs.copy()', 'exprs: varargs.copy');
    LVarargs := LAst.NewNode<TPCVarargs>();
    LVarargs.VarargsKind := vaCount;
    Check(LVarargs.ExprText() = 'varargs.count', 'exprs: varargs.count');
    LNew := LAst.NewNode<TPCNew>();
    LNew.TargetType := DoCppInt(LAst);
    LNew.InitKind := niArgs;
    LNew.Args.Add(DoInt(LAst, 5));
    Check(LNew.ExprText() = 'new int(5)', 'exprs: new with arguments');
    LDelete := LAst.NewNode<TPCDelete>();
    LDelete.IsArray := True;
    LDelete.Operand := DoName(LAst, 'p');
    Check(LDelete.ExprText() = 'delete [] p', 'exprs: delete []');
    Check(DoSpecial(LAst, skSelf).ExprText() = 'self', 'exprs: self');
    LVerbatim := LAst.NewNode<TPCVerbatimExpr>();
    LVerbatim.Verbatim.Text := 'sizeof(int)';
    Check(LVerbatim.ExprText() = 'sizeof(int)', 'exprs: verbatim C++ as copied');
    LName := LAst.NewNode<TPCName>();
    LName.HasLeadingScope := True;
    LName.Parts.Add(DoPart(LAst, 'std'));
    LName.Parts.Add(DoPart(LAst, 'max'));
    LName.Parts[1].HasTemplateArgs := True;
    LName.Parts[1].TemplateArgs.Add(DoTypeArg(LAst, DoCppInt(LAst)));
    Check(LName.ExprText() = '::std::max<int>', 'exprs: a scoped C++ name with template args');
    LBraced := LAst.NewNode<TPCBracedInit>();
    LBraced.Base := DoName(LAst, 'T');
    LBraced.Args.Add(DoInt(LAst, 1));
    LBraced.Args.Add(DoInt(LAst, 2));
    Check(LBraced.ExprText() = 'T{1, 2}', 'exprs: a braced init');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestFloatText();
var
  LSingle: Single;
  LWide: Double;
  LBits: UInt64;
  LNegZero: Double;
  LAst: TPCAst;
  LLit: TPCLiteral;
begin
  Check((TPCNode.FloatText(0.5) = '0.5') and (TPCNode.FloatText(2.5) = '2.5') and
    (TPCNode.FloatText(0.1) = '0.1') and (TPCNode.FloatText(2.0) = '2') and
    (TPCNode.FloatText(-1.5) = '-1.5'), 'floats: short values print short');
  Check((TPCNode.FloatText(Infinity) = 'inf') and (TPCNode.FloatText(NegInfinity) = '-inf') and
    (TPCNode.FloatText(NaN) = 'nan') and (TPCNode.FloatText(0.0) = '0'),
    'floats: inf, -inf, nan and 0 are spelled');
  LBits := UInt64($8000000000000000);
  Move(LBits, LNegZero, SizeOf(LNegZero));
  Check(TPCNode.FloatText(LNegZero) = '-0', 'floats: -0 keeps its sign');
  // 0.1f widened is not 0.1: the two must never print one text (Q7 exactness)
  LSingle := 0.1;
  LWide := LSingle;
  Check((TPCNode.FloatText(LWide) <> '0.1') and DoDecodesTo(TPCNode.FloatText(LWide), LWide),
    'floats: a binary32 value widened prints its own exact text');
  Check(DoDecodesTo(TPCNode.FloatText(1E23), 1E23) and
    DoDecodesTo(TPCNode.FloatText(5E-324), 5E-324) and
    DoDecodesTo(TPCNode.FloatText(MaxDouble), MaxDouble),
    'floats: hard cases read back to the same bits');
  LAst := TPCAst.Create();
  try
    LLit := LAst.NewNode<TPCLiteral>();
    LLit.LiteralKind := lkFloat;
    LLit.Text := '0.1f';
    LLit.HasValue := True;
    LLit.FloatValue := LWide;
    Check(LLit.Dump() = 'Literal lkFloat "0.1f" value=' + TPCNode.FloatText(LWide) + sLineBreak,
      'floats: the literal dump uses the exact text (F-PA4)');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestCanon();
var
  LAst: TPCAst;
  LInt: TPCBuiltinType;
  LA: TPCTypeDecl;
  LB: TPCTypeDecl;
  LRecord: TPCRecordType;
  LFull: TPCTypeDecl;
  LFwd: TPCTypeDecl;
  LNamed: TPCNamedType;
  LCycle: TPCTypeDecl;
  LRaised: Boolean;
begin
  LAst := TPCAst.Create();
  try
    LInt := DoBuiltin(LAst, tkKwInt32);
    LA := DoTypeDecl(LAst, 'TA', LInt);
    Check(DoNamed(LAst, 'TA', LA).Canon() = LInt, 'canon: an alias reaches its definition');
    LB := DoTypeDecl(LAst, 'TB', DoNamed(LAst, 'TA', LA));
    Check(DoNamed(LAst, 'TB', LB).Canon() = LInt, 'canon: an alias chain is followed');
    LRecord := LAst.NewNode<TPCRecordType>();
    LFull := DoTypeDecl(LAst, 'TN', LRecord);
    LFwd := DoTypeDecl(LAst, 'TN', nil);
    LFwd.IsForward := True;
    LFwd.ResolvedFull := LFull;
    Check(DoNamed(LAst, 'TN', LFwd).Canon() = LRecord, 'canon: a forward goes through its full');
    LFwd := DoTypeDecl(LAst, 'TM', nil);
    LFwd.IsForward := True;
    LNamed := DoNamed(LAst, 'TM', LFwd);
    Check(LNamed.Canon() = LNamed, 'canon: a forward with no full stops at the name');
    LNamed := DoNamed(LAst, 'size_t', nil);
    LNamed.ResolvedKind := rkOpaque;
    Check((LNamed.Canon() = LNamed) and (LInt.Canon() = LInt),
      'canon: an opaque name and a builtin are their own Canon');

    // A cycle no SEM can write: a defect upstream, raised, never looped
    LCycle := DoTypeDecl(LAst, 'TX', nil);
    LNamed := DoNamed(LAst, 'TX', LCycle);
    LCycle.TypeDef := LNamed;
    LRaised := False;
    try
      LNamed.Canon();
    except
      on EInvalidOpException do
        LRaised := True;
    end;
    Check(LRaised, 'canon: a cycle raises');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestHoldsString();
var
  LAst: TPCAst;
  LArray: TPCArrayType;
  LPtr: TPCPointerType;
  LRecord: TPCRecordType;
  LAnon: TPCAnonAggregate;
  LBaseDecl: TPCTypeDecl;
  LOverlay: TPCOverlayType;
  LFwd: TPCTypeDecl;
  LCycleDecl: TPCTypeDecl;
begin
  LAst := TPCAst.Create();
  try
    Check(DoBuiltin(LAst, tkKwString).HoldsStringOrDynamicArray() and
      DoBuiltin(LAst, tkKwWstring).HoldsStringOrDynamicArray() and
      (not DoBuiltin(LAst, tkKwInt32).HoldsStringOrDynamicArray()), 'holds: builtins');
    LArray := LAst.NewNode<TPCArrayType>();
    LArray.IsDynamic := True;
    LArray.ElementType := DoBuiltin(LAst, tkKwInt32);
    Check(LArray.HoldsStringOrDynamicArray(), 'holds: a dynamic array');
    LArray := LAst.NewNode<TPCArrayType>();
    LArray.LowExpr := DoInt(LAst, 0);
    LArray.HighExpr := DoInt(LAst, 3);
    LArray.ElementType := DoBuiltin(LAst, tkKwString);
    Check(LArray.HoldsStringOrDynamicArray(), 'holds: a static array of string');
    LArray.ElementType := DoBuiltin(LAst, tkKwInt32);
    Check(not LArray.HoldsStringOrDynamicArray(), 'holds: a static array of int32 does not');

    Check(DoRecordWith(LAst, DoBuiltin(LAst, tkKwString)).HoldsStringOrDynamicArray(),
      'holds: a record with a string field');
    LPtr := LAst.NewNode<TPCPointerType>();
    LPtr.TargetType := DoBuiltin(LAst, tkKwString);
    Check(not DoRecordWith(LAst, LPtr).HoldsStringOrDynamicArray(),
      'holds: a pointer to string is a plain pointer');
    LRecord := LAst.NewNode<TPCRecordType>();
    LAnon := LAst.NewNode<TPCAnonAggregate>();
    LAnon.IsOverlay := True;
    LAnon.Members.Add(DoField(LAst, 'W', DoBuiltin(LAst, tkKwWstring)));
    LRecord.Members.Add(LAnon);
    Check(LRecord.HoldsStringOrDynamicArray(), 'holds: through an anonymous overlay');
    LRecord := LAst.NewNode<TPCRecordType>();
    LRecord.Members.Add(LAst.NewNode<TPCMethodItem>());
    Check(not LRecord.HoldsStringOrDynamicArray(), 'holds: a method holds no data');
    LBaseDecl := DoTypeDecl(LAst, 'TBase', DoRecordWith(LAst, DoBuiltin(LAst, tkKwString)));
    LRecord := DoRecordWith(LAst, DoBuiltin(LAst, tkKwInt32));
    LRecord.ParentName := DoNamed(LAst, 'TBase', LBaseDecl);
    Check(LRecord.HoldsStringOrDynamicArray(), 'holds: through the parent record');
    Check(DoNamed(LAst, 'TBase', LBaseDecl).HoldsStringOrDynamicArray(), 'holds: through an alias name');
    LOverlay := LAst.NewNode<TPCOverlayType>();
    LOverlay.Members.Add(DoField(LAst, 'I', DoBuiltin(LAst, tkKwInt32)));
    Check(not LOverlay.HoldsStringOrDynamicArray(), 'holds: an overlay of int32');

    // forward TC; TC = record Self: TC; end; (a reported by-value cycle) ends
    LFwd := DoTypeDecl(LAst, 'TC', nil);
    LFwd.IsForward := True;
    LRecord := LAst.NewNode<TPCRecordType>();
    LCycleDecl := DoTypeDecl(LAst, 'TC', LRecord);
    LFwd.ResolvedFull := LCycleDecl;
    LRecord.Members.Add(DoField(LAst, 'Self', DoNamed(LAst, 'TC', LFwd)));
    Check(not LRecord.HoldsStringOrDynamicArray(), 'holds: a by-value cycle terminates');
    LRecord.Members.Add(DoField(LAst, 'S', DoBuiltin(LAst, tkKwString)));
    Check(LRecord.HoldsStringOrDynamicArray(), 'holds: a cycle does not hide a later string field');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestBuiltinCache();
var
  LAst: TPCAst;
  LInt: TPCBuiltinType;
  LVarargsType: TPCBuiltinType;
  LRaised: Boolean;
begin
  LAst := TPCAst.Create();
  try
    LInt := LAst.BuiltinType(tkKwInt32);
    Check((LAst.NodeCount() = 8) and (LInt.BuiltinToken = tkKwInt32),
      'builtins: made on first use, one node');
    Check((LAst.BuiltinType(tkKwInt32) = LInt) and (LAst.NodeCount() = 8),
      'builtins: the same instance afterwards');
    Check((LAst.BuiltinType(tkKwString) <> LInt) and (LAst.NodeCount() = 9),
      'builtins: one instance per token');
    LRaised := False;
    try
      LAst.BuiltinType(tkKwPtr);
    except
      on EArgumentException do
        LRaised := True;
    end;
    Check(LRaised and (LAst.NodeCount() = 9), 'builtins: ptr is not a builtin token (raises, no node)');
    LRaised := False;
    try
      LAst.BuiltinType(tkIdentifier);
    except
      on EArgumentException do
        LRaised := True;
    end;
    Check(LRaised, 'builtins: a kind with no vocabulary row raises');
    LVarargsType := LAst.BuiltinType(tkKwVarargs);
    Check((LVarargsType.BuiltinToken = tkKwVarargs) and (LVarargsType.TypeText() = 'varargs') and
      (LAst.BuiltinType(tkKwVarargs) = LVarargsType) and (LAst.NodeCount() = 10),
      'builtins: varargs is a builtin type word (one shared node, spelled varargs)');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestJumpFields();
var
  LAst: TPCAst;
  LWhile: TPCWhile;
  LLeave: TPCLeave;
  LSkip: TPCSkip;
  LReturn: TPCReturn;
  LRoutine: TPCRoutine;
  LGuard: TPCGuard;
  LBlock: TPCBlock;
begin
  LAst := TPCAst.Create();
  try
    LWhile := LAst.NewNode<TPCWhile>();
    LLeave := LAst.NewNode<TPCLeave>();
    Check(LLeave.Dump() = 'Leave' + sLineBreak, 'jumps: nothing resolved, nothing dumped');
    LLeave.ResolvedJumpTarget := LWhile;
    LBlock := LAst.NewNode<TPCBlock>();
    LBlock.Stmts.Add(LLeave);
    Check(LBlock.Dump() = 'Block' + sLineBreak + '  Leave jump=While' + sLineBreak,
      'jumps: leave names its target, the target is never walked');
    LSkip := LAst.NewNode<TPCSkip>();
    LSkip.ResolvedJumpTarget := LAst.NewNode<TPCFor>();
    Check(LSkip.Dump() = 'Skip jump=For' + sLineBreak, 'jumps: skip names its loop');
    LRoutine := LAst.NewNode<TPCRoutine>();
    LRoutine.DeclName := 'F';
    LReturn := LAst.NewNode<TPCReturn>();
    LReturn.ResolvedRoutine := LRoutine;
    Check(LReturn.Dump() = 'Return routine=Routine "F"' + sLineBreak, 'jumps: return names its routine');
    LGuard := LAst.NewNode<TPCGuard>();
    Check(LGuard.Dump() = 'Guard guard=0' + sLineBreak, 'jumps: a guard with no escapes');
    LGuard.ResolvedEscapes := [geReturn, geSkip];
    Check(LGuard.Dump() = 'Guard guard=0 escapes=geReturn,geSkip' + sLineBreak,
      'jumps: a guard lists its escaping flows in enum order');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestFactDumps();
var
  LAst: TPCAst;
  LLit: TPCLiteral;
  LStmt: TPCVerbatimStmt;
  LMember: TPCMember;
  LCall: TPCCall;
  LVarargs: TPCVarargs;
begin
  // Parser facts SEM reads (PREREQ-B): each dumps only when present, so no
  // existing expectation changes
  LAst := TPCAst.Create();
  try
    // "n%d\x41" at 4:12: n%d copied from column 13, the escape's bytes map to its '\'
    LLit := LAst.NewNode<TPCLiteral>();
    LLit.LiteralKind := lkString;
    LLit.Text := '"n%d\x41"';
    SetLength(LLit.Parts, 1);
    LLit.Parts[0].Text := LLit.Text;
    LLit.Parts[0].HasValue := True;
    LLit.Parts[0].Value := 'n%dA';
    LLit.Parts[0].ValueMap := [DoValueRun(0, 4, 13, True), DoValueRun(3, 4, 16, False)];
    Check(LLit.Dump() = 'Literal lkString "\"n%d\\x41\"" part0=[value="n%dA"] map0=[c0@4:13 e3@4:16]' +
      sLineBreak, 'facts: a value map dumps after the parts, copy and escape runs');

    // u8"a" "b%s": the prefixed part has no map, the plain one keeps its own index
    LLit := LAst.NewNode<TPCLiteral>();
    LLit.LiteralKind := lkString;
    LLit.Text := 'u8"a" "b%s"';
    SetLength(LLit.Parts, 2);
    LLit.Parts[0].Text := 'u8"a"';
    LLit.Parts[0].LiteralPrefix := lpU8;
    LLit.Parts[1].Text := '"b%s"';
    LLit.Parts[1].HasValue := True;
    LLit.Parts[1].Value := 'b%s';
    LLit.Parts[1].ValueMap := [DoValueRun(0, 4, 19, True)];
    Check(LLit.Dump() = 'Literal lkString "u8\"a\" \"b%s\"" part0=[prefix=lpU8] part1=[value="b%s"] map1=[c0@4:19]' +
      sLineBreak, 'facts: mapN names its part; a part without a map dumps none');

    LLit := LAst.NewNode<TPCLiteral>();
    LLit.LiteralKind := lkString;
    LLit.Text := '"ab"';
    SetLength(LLit.Parts, 1);
    LLit.Parts[0].Text := LLit.Text;
    LLit.Parts[0].HasValue := True;
    LLit.Parts[0].Value := 'ab';
    Check(LLit.Dump() = 'Literal lkString "\"ab\"" part0=[value="ab"]' + sLineBreak,
      'facts: an empty value map dumps nothing');

    // A body block on line 7 at column 3: each jump word, every kind
    LStmt := DoVerbatim(LAst, vkCppBlock, etInPlace, 'return; break; continue;');
    LStmt.Verbatim.EscapingJumps := [DoJump(cjReturn, 7, 3), DoJump(cjBreak, 7, 11),
      DoJump(cjContinue, 7, 18)];
    Check(LStmt.Dump() = 'VerbatimStmt vkCppBlock etInPlace "return; break; continue;" ' +
      'jumps=[return@7:3 break@7:11 continue@7:18]' + sLineBreak,
      'facts: a block lists its escaping jumps in source order');

    // L.get(0, string): Args = [0], the type written second
    LMember := LAst.NewNode<TPCMember>();
    LMember.Base := DoName(LAst, 'L');
    LMember.Access := maDot;
    LMember.Member := DoPart(LAst, 'get');
    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := LMember;
    LCall.Args.Add(DoInt(LAst, 0));
    LCall.TypeArg := DoBuiltin(LAst, tkKwString);
    LCall.TypeArgIndex := 1;
    Check(LCall.Dump() =
      'Call typearg@1' + sLineBreak +
      '  Member maDot' + sLineBreak +
      '    Name' + sLineBreak +
      '      NamePart "L"' + sLineBreak +
      '    NamePart "get"' + sLineBreak +
      '  BuiltinType tkKwString' + sLineBreak +
      '  Literal lkInteger "0" value=0' + sLineBreak,
      'facts: a type argument after an expression names its position');
    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := DoName(LAst, 'size');
    LCall.TypeArg := DoBuiltin(LAst, tkKwInt64);
    Check(LCall.Dump() =
      'Call' + sLineBreak +
      '  Name' + sLineBreak +
      '    NamePart "size"' + sLineBreak +
      '  BuiltinType tkKwInt64' + sLineBreak,
      'facts: size(T) dumps unchanged (index 0)');
    LCall := LAst.NewNode<TPCCall>();
    LCall.Callee := DoName(LAst, 'f');
    LCall.TypeArgIndex := 2;
    Check(LCall.Dump() =
      'Call' + sLineBreak +
      '  Name' + sLineBreak +
      '    NamePart "f"' + sLineBreak,
      'facts: TypeArgIndex without a TypeArg dumps nothing');

    // varargs.get(0, int32): the index, then the type (written order)
    LVarargs := LAst.NewNode<TPCVarargs>();
    LVarargs.VarargsKind := vaGet;
    LVarargs.IndexExpr := DoInt(LAst, 0);
    LVarargs.ReadType := DoBuiltin(LAst, tkKwInt32);
    Check(LVarargs.Dump() =
      'Varargs vaGet' + sLineBreak +
      '  Literal lkInteger "0" value=0' + sLineBreak +
      '  BuiltinType tkKwInt32' + sLineBreak,
      'facts: varargs.get walks its index before its type');
  finally
    LAst.Free();
  end;
end;

procedure TPCASTTests.DoTestIntrinsicNames();
var
  LKind: TPCIntrinsicKind;
  LOther: TPCIntrinsicKind;
  LOk: Boolean;
begin
  LOk := PC_INTRINSIC_NAMES[ikNone] = '';
  for LKind := Succ(ikNone) to High(TPCIntrinsicKind) do
  begin
    if PC_INTRINSIC_NAMES[LKind] = '' then
      LOk := False;
    // Every other kind (Succ of the last value would leave the enum)
    for LOther := Low(TPCIntrinsicKind) to High(TPCIntrinsicKind) do
    begin
      if (LOther <> LKind) and (PC_INTRINSIC_NAMES[LOther] = PC_INTRINSIC_NAMES[LKind]) then
        LOk := False;
    end;
  end;
  Check(LOk, 'intrinsics: every kind but ikNone has its own name');
  Check((PC_INTRINSIC_NAMES[ikParamCount] = 'paramcount') and
    (PC_INTRINSIC_NAMES[ikPrintLn] = 'println') and
    (PC_INTRINSIC_NAMES[ikRaiseCode] = 'raisecode') and
    (PC_INTRINSIC_NAMES[ikTestAssertEqualPtr] = 'testAssertEqualPtr'),
    'intrinsics: BNF sec 7 / 8 spellings, exact case');
end;

procedure TPCASTTests.DoTestLiteralValue();
var
  LAst: TPCAst;
  LLit: TPCLiteral;
  LValue: string;
  LOk: Boolean;
begin
  // TPCLiteral.DecodedValue: the one "a literal's value" routine (D-A2-10)
  LAst := TPCAst.Create();
  try
    LLit := LAst.NewNode<TPCLiteral>();
    LLit.LiteralKind := lkString;
    SetLength(LLit.Parts, 2);
    LLit.Parts[0].HasValue := True;
    LLit.Parts[0].Value := 'a'#9'b';
    LLit.Parts[1].HasValue := True;
    LLit.Parts[1].Value := 'c';
    LOk := LLit.DecodedValue(LValue);
    Check(LOk and (LValue = 'a'#9'bc'),
      'literal_value: every part has a value: the parts joined (got "' + LValue + '")');

    LLit.Parts[1].HasValue := False;
    LOk := LLit.DecodedValue(LValue);
    Check((not LOk) and (LValue = ''),
      'literal_value: one part without a value: False and '''' (got "' + LValue + '")');

    LLit := LAst.NewNode<TPCLiteral>();
    LLit.LiteralKind := lkString;
    LOk := LLit.DecodedValue(LValue);
    Check((not LOk) and (LValue = ''), 'literal_value: no parts: False and ''''');
  finally
    LAst.Free();
  end;
end;

end.
