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
  PaskalCPP.Emitter - analyzed AST -> <Module>.pcpp.h + <Module>.pcpp.cpp

  TPCEmitter walks the AST the semantic pass analyzed and writes, per
  module, a C++23 header and source through two TPCCppWriter instances
  (PLAN-EMITTER A4: files, preambles, namespace runs, item order, sections,
  test blocks, the trailer). It reads only AST fields and writes only
  EmitSpans (through the writer). Items are written in source order (a
  cursor over the module's lists, H10); PaskalCPP parts stand in
  namespace <M> runs (opened and closed by the emitter), verbatim C++ at
  global scope; a run closes on the last line of its last part, found by
  looking ahead over the same cursor. Imports and synthesized prototypes
  are header preamble lines (H8); the trailer (main / registration / dll and lib hooks) is written
  on the module's last .pcpp line (H9). Types (A5, E5): an exported
  module-level type, and a private one the header's own text names (one
  walk with the private consts it names, DoCollectHeaderDecls), goes to the
  header; any other module-level type to the source at its own place (its
  methods defined in the class there); local ones in place; every node writes
  its own text on its own .pcpp line with a span on itself (Mark /
  CloseSpan); const follows the type (east const); a local choices type is
  hoisted to the namespace with its formatter (H3).

  Dependencies: StdApp.Base (TBaseObject, TErrors), StdApp.Utils (paths),
    StdApp.Resources (RSEmt*), PaskalCPP.Common (TPCBuildDirective),
    PaskalCPP.AST, PaskalCPP.CppWriter
  Notes: EmitModule is pure (no file I/O, H7); WriteFiles writes UTF-8 with
    no BOM, LF only (H13). A broken invariant (the writer's, or a node with
    no C++ rule) is EM0003.
===============================================================================}

unit PaskalCPP.Emitter;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.Common,
  PaskalCPP.AST,
  PaskalCPP.CppWriter;

const
  { PC_ERR_EMT_001 }
  PC_ERR_EMT_001 = 'EM0001';   // the output folder cannot be created
  { PC_ERR_EMT_002 }
  PC_ERR_EMT_002 = 'EM0002';   // an output file cannot be written
  { PC_ERR_EMT_003 }
  PC_ERR_EMT_003 = 'EM0003';   // internal error while emitting a module (an invariant)
  { PC_EMT_PARENT_MEMBER }
  // PLAN-RECORDS M10: an extension's parent, its hidden first member (the
  // debugger finds a record's parent part by this name)
  PC_EMT_PARENT_MEMBER = 'pcpp_parent';
  { PC_EMT_INIT_TAG }
  // PLAN-OBJECT D3: an init with parameters is a C++ constructor taking its
  // own empty tag type first, pcpp_init_<n> (n = its place among the type's
  // inits, 1-based), so a construction names exactly the init SEM picked
  PC_EMT_INIT_TAG = 'pcpp_init_';
  { PC_EMT_OVERRIDE_CHECK_OPEN }
  // PLAN-OBJECT O13b (D7 across D14): around the class of an object whose
  // chain reaches C/C++ (ResolvedDerivesFromCpp), clang's
  // -Wsuggest-override is an error, so a method that overrides a C++
  // virtual without `override` fails there (the Compiler reports SM0332).
  // _Pragma, not #pragma: it sits on the class's own line. Every override
  // the emitter writes carries `override`, and the person's mixed C++ is
  // outside the region, so nothing else can raise it
  PC_EMT_OVERRIDE_CHECK_OPEN = '_Pragma("clang diagnostic push") _Pragma("clang diagnostic error \"-W' +
    PC_FRONTEND_FLAG_OVERRIDE + '\"") ';
  { PC_EMT_OVERRIDE_CHECK_CLOSE }
  PC_EMT_OVERRIDE_CHECK_CLOSE = ' _Pragma("clang diagnostic pop")';
  { PC_EMT_OVERLAY_CHECK_OPEN }
  // PLAN-COMPLIANCE F34: the overlay-field check names
  // ::pcpp::overlay_check<fits>, deprecated "pcpp:SM0313" when the member does
  // not fit, inside a region that makes that one warning FATAL: clang stops
  // the TU there, so the union's deleted special members (a C++ member with a
  // destructor, a copy) never follow in C++ words (probe
  // scripts\zb_cmpl\f4\overlay\p5_fatal.cpp). Only the check is in the region
  PC_EMT_OVERLAY_CHECK_OPEN = '_Pragma("clang diagnostic push") ' +
    '_Pragma("clang diagnostic fatal \"-Wdeprecated-declarations\"") ';
  { PC_EMT_OVERLAY_CHECK_CLOSE }
  PC_EMT_OVERLAY_CHECK_CLOSE = ' _Pragma("clang diagnostic pop")';
  { PC_EMT_OVERLAY_LAYOUT }
  // PLAN-COMPLIANCE F35: an overlay starts zeroed in every byte. Each union
  // (a named overlay, an anonymous one) gets the FIRST member
  // `unsigned char pcpp_zero_<k>[sizeof(pcpp_overlay_<k>)]`; every creation
  // site value-initializes (`T N{}`, `new T{}`, a vector's resize), which
  // zeroes the first member, so every byte any member reaches. The union
  // stays trivial, an aggregate and standard layout (packs as before:
  // scripts\zb_cmpl\f4\overlay\p6_out.txt). pcpp_overlay_<k> is the union's
  // layout twin (the same members, no checks, no zero member: the same size),
  // a nested type of the named type that holds the union, since an anonymous
  // aggregate can declare no type. k counts the unions of one named type in
  // preorder (DoWriteOverlayLayouts and the emission number them alike)
  PC_EMT_OVERLAY_LAYOUT = 'pcpp_overlay_';
  { PC_EMT_OVERLAY_ZERO }
  PC_EMT_OVERLAY_ZERO = 'pcpp_zero_';
  { PC_EMT_LIVE_MEMBER }
  // PLAN-OBJECT O5 (D5): the ::pcpp::Live member of an object that declares
  // a done; its done skips when the object was moved out (runtime api.md)
  PC_EMT_LIVE_MEMBER = 'pcpp_live';
  { PC_EMT_PROP_GET }
  // PLAN-OBJECT O9 (D12): a property X is two member functions, its read
  // pcpp_get_X() const and its write pcpp_set_X(T v) (no proxy object; the
  // names are the compiler's, M11); a bound write's value is pcpp_pv, a
  // compound assignment's object / value / current value pcpp_po / pcpp_pv /
  // pcpp_pc (lambda locals)
  PC_EMT_PROP_GET = 'pcpp_get_';
  { PC_EMT_PROP_SET }
  PC_EMT_PROP_SET = 'pcpp_set_';
  { PC_EMT_OP_PREFIX }
  // PLAN-OBJECT O11 (D13): a declared operator is the static member
  // pcpp_op_<name> of its type, called T::pcpp_op_<name>(a, b) (C++'s own
  // operator lookup never decides; div / mod / in have no C++ operator)
  PC_EMT_OP_PREFIX = 'pcpp_op_';
  { PC_EMT_PROP_VALUE }
  PC_EMT_PROP_VALUE = 'pcpp_pv';
  { PC_EMT_PROP_OBJECT }
  PC_EMT_PROP_OBJECT = 'pcpp_po';
  { PC_EMT_PROP_CURRENT }
  PC_EMT_PROP_CURRENT = 'pcpp_pc';
  { PC_EMT_PROP_INDEX }
  // O10: an indexed property's compound assignment: the index, once
  PC_EMT_PROP_INDEX = 'pcpp_pi';
  { PC_EMT_OWNER_TEMPLATES }
  // PLAN-OBJECT O6 (D4): the runtime template each owner kind is written as
  PC_EMT_OWNER_TEMPLATES: array[TPCOwnerKind] of string = ('::pcpp::Own', '::pcpp::Ref', '::pcpp::Weak');
  { PC_EMT_MOVE_SOURCE }
  // O5: the parameter / temporary names of the synthesized copy and move
  // assignments (reserved by M11: no PaskalCPP name starts pcpp_)
  PC_EMT_MOVE_SOURCE = 'pcpp_s';
  { PC_EMT_MOVE_TEMP }
  PC_EMT_MOVE_TEMP = 'pcpp_t';

  { PC_EMT_HEADER_EXT }
  PC_EMT_HEADER_EXT = '.pcpp.h';
  { PC_EMT_SOURCE_EXT }
  PC_EMT_SOURCE_EXT = '.pcpp.cpp';

type

  { TPCEmitPart }
  // What one item writes into one file: nothing, PaskalCPP text (inside the
  // module's namespace run) or C++ at global scope
  TPCEmitPart = (epNone, epNamespace, epGlobal);

  { TPCModuleItemKind }
  TPCModuleItemKind = (miDecl, miTest, miInit, miFinal, miBody, miTrailer);

  { TPCModuleItem }
  // One module-level item: a node of the module's lists, or the trailer
  // (Node nil), written on the module's last line (H9)
  TPCModuleItem = record
    ItemKind: TPCModuleItemKind;
    Node: TPCNode;
  end;

  { TPCItemCursor }
  // Source order over Decls, Tests, InitRoutine, FinalRoutine and Body,
  // merged by Range.StartByteOffset, then the trailer (H10): no list built
  TPCItemCursor = record
    DeclIndex: Integer;
    TestIndex: Integer;
    InitTaken: Boolean;
    FinalTaken: Boolean;
    BodyTaken: Boolean;
    TrailerTaken: Boolean;
  end;

  { TPCOpenStmt }
  // One entry of the walk context while a body is written (A7): a loop or
  // match a leave / skip may target, a guard lambda (the guard's body, or
  // its except list when it has a finally) a jump escapes from, or a body
  // barrier (Stmt nil). Walk state only, never a program fact
  TPCOpenStmt = record
    Stmt: TPCStmt;
    IsLambda: Boolean;
  end;

  { TPCEmitter }
  TPCEmitter = class(TBaseObject)
  private
    FAst: TPCAst;
    FMainModule: TPCModule;
    FTestMode: Boolean;                          // @unitTestMode on in an exe main module
    FModule: TPCModule;                          // the module being emitted
    FWriters: array[TPCOutFile] of TPCCppWriter;
    FRunOpen: array[TPCOutFile] of Boolean;      // a namespace run is open in the file
    FRoutine: TPCRoutine;                        // the routine whose body is written; nil = module / test body
    FOpen: TList<TPCOpenStmt>;                   // the walk context (A7), innermost last
    FRecord: TPCRecordType;                      // the object whose methods are written (parent.M, H6); nil = none
    FRecordName: string;                         // FRecord's struct name (an init's / done's C++ name); '' = none
    FSetterTarget: TPCMember;                    // O9: the property member being written as pcpp_set_X( (nil = none)
    FOpenGetTarget: TPCMember;                   // O10: the indexed property member written as pcpp_get_X( (nil = none)
    FStoreTarget: TPCExpr;                       // F37: the assignment target written now (a choices bitfield there is stored, not read)
    FInPacked: Boolean;                          // the fields written now are packed (M9: the packed-field check)
    FOverlayCount: Integer;                      // F35: the unions of the named type written now, so far (PC_EMT_OVERLAY_LAYOUT)
    FHeaderDecls: TList<TPCDecl>;                // F22 / E5: the module's private consts and types the header's text names (DoCollectHeaderDecls)

    class procedure DoPick(const ANode: TPCNode; const AKind: TPCModuleItemKind; var ABest: TPCNode;
      var ABestKind: TPCModuleItemKind); static;
    class function DoBuiltinText(const AKind: TPCTokenKind): string; static;
    class function DoTokenText(const AKind: TPCTokenKind): string; static;
    class function DoCvText(const AFlags: TPCCvFlags): string; static;
    class function DoIsNamedPaskalType(const AType: TPCTypeExpr): Boolean; static;
    class function DoOrdinal(const AValue: TPCChoiceValue): Int64; static;
    class function DoChoicesUnderlying(const AChoices: TPCChoicesType): string; static;
    class function DoFormatterText(const AEnumName: string; const ADisplayName: string;
      const AChoices: TPCChoicesType): string; static;
    class function DoFoldedCount(const ALow: TPCExpr; const AHigh: TPCExpr; out ACount: string): Boolean; static;
    class function DoLocalChoicesName(const AChoices: TPCChoicesType): string; static;
    class function DoIsIntegerType(const AType: TPCTypeExpr): Boolean; static;
    class function DoIsBoolType(const AType: TPCTypeExpr): Boolean; static;
    class function DoIsSetType(const AType: TPCTypeExpr): Boolean; static;
    class function DoIsStringType(const AType: TPCTypeExpr): Boolean; static;
    class function DoIsPointerType(const AType: TPCTypeExpr): Boolean; static;
    class function DoIsUntypedPointer(const AType: TPCTypeExpr): Boolean; static;
    class function DoIsEnclosed(const AExpr: TPCExpr): Boolean; static;
    class function DoBinaryOpText(const AOp: TPCBinaryOp; const AIsSet: Boolean): string; static;
    class function DoAssignOpText(const AOp: TPCAssignOp; const AIsSet: Boolean): string; static;
    class function DoFoldedText(const AExpr: TPCExpr; out AText: string): Boolean; static;
    class function DoTestKindName(const AKind: TPCIntrinsicKind): string; static;
    class function DoBitField(const AExpr: TPCExpr): TPCField; static;
    class function DoChoicesBitField(const AExpr: TPCExpr): TPCField; static;
    class function DoTextNamesWord(const AText: string; const AWord: string): Boolean; static;
    procedure DoNoRule(const ANode: TPCNode);
    procedure DoMissing(const AFile: TPCOutFile; const AWhat: string);
    function DoNextItem(var ACursor: TPCItemCursor; out AItem: TPCModuleItem): Boolean;
    function DoItemLine(const AItem: TPCModuleItem): UInt64;
    function DoDeclPart(const AStmt: TPCStmt; const AFile: TPCOutFile): TPCEmitPart;
    function DoDeclInFile(const AStmt: TPCStmt; const AFile: TPCOutFile): Boolean;
    procedure DoCollectHeaderDecls();
    procedure DoJoinHeaderType(const ADecl: TPCTypeDecl; const APending: TList<TPCNode>);
    procedure DoJoinTypePartners(const ADecl: TPCTypeDecl; const APending: TList<TPCNode>);
    function DoTrailerPart(const AFile: TPCOutFile): TPCEmitPart;
    function DoPartKind(const AItem: TPCModuleItem; const AFile: TPCOutFile): TPCEmitPart;
    function DoNextPartKind(const ACursor: TPCItemCursor; const AFile: TPCOutFile): TPCEmitPart;
    function DoHasRegistration(): Boolean;
    function DoHasEntry(): Boolean;
    procedure DoAt(const AFile: TPCOutFile; const ALine: UInt64);
    function DoHasText(const AFile: TPCOutFile): Boolean;
    procedure DoBeginItem(const AFile: TPCOutFile; const ALine: UInt64);
    procedure DoPut(const AFile: TPCOutFile; const ALine: UInt64; const AText: string);
    procedure DoText(const AFile: TPCOutFile; const AText: string);
    procedure DoPutVerbatim(const AFile: TPCOutFile; const AStmt: TPCVerbatimStmt);
    procedure DoWriteType(const AFile: TPCOutFile; const AType: TPCTypeExpr);
    function DoTypeName(const AType: TPCTypeExpr): string;
    procedure DoWritePointerType(const AFile: TPCOutFile; const AType: TPCPointerType);
    procedure DoWriteOwnerType(const AFile: TPCOutFile; const AType: TPCOwnerType);
    procedure DoWriteArrayType(const AFile: TPCOutFile; const AType: TPCArrayType);
    procedure DoWriteSetType(const AFile: TPCOutFile; const AType: TPCSetType);
    procedure DoWriteRoutineType(const AFile: TPCOutFile; const AType: TPCRoutineType);
    procedure DoWriteParam(const AFile: TPCOutFile; const AParam: TPCParam; const AWithName: Boolean);
    procedure DoWriteParams(const AFile: TPCOutFile; const AParams: TList<TPCParam>; const AIsVariadic: Boolean;
      const ALinkage: TPCLinkage; const AWithNames: Boolean);
    procedure DoWriteSignature(const AFile: TPCOutFile; const ARoutine: TPCRoutine; const AStatic: Boolean;
      const AOwner: string);
    procedure DoEmitRoutineBody(const ARoutine: TPCRoutine);
    procedure DoEmitRoutine(const AFile: TPCOutFile; const ARoutine: TPCRoutine);
    procedure DoEmitVar(const AFile: TPCOutFile; const AVar: TPCVarDecl; const AModuleLevel: Boolean);
    procedure DoEmitConst(const AFile: TPCOutFile; const AConst: TPCConstDecl; const AModuleLevel: Boolean);
    procedure DoEmitMethodItem(const AFile: TPCOutFile; const AItem: TPCMethodItem; const AInClass: Boolean);
    // PLAN-OBJECT O9: properties (two accessor member functions each)
    procedure DoEmitProperty(const AFile: TPCOutFile; const AProperty: TPCPropertyItem; const AInClass: Boolean;
      var AHidden: Boolean);
    procedure DoEmitAccessor(const AFile: TPCOutFile; const AProperty: TPCPropertyItem;
      const AAccessor: TPCAccessorItem; const AInClass: Boolean);
    procedure DoCloseAccessorSpan(const AFile: TPCOutFile; const AMark: TPCWriterMark;
      const AAccessor: TPCAccessorItem);
    procedure DoWriteAccessorHead(const AFile: TPCOutFile; const AProperty: TPCPropertyItem;
      const AAccessor: TPCAccessorItem; const AOwner: string);
    procedure DoEmitAccessorDef(const AProperty: TPCPropertyItem; const AAccessor: TPCAccessorItem;
      const AOwner: string);
    procedure DoEmitAccessorBody(const AProperty: TPCPropertyItem; const AAccessor: TPCAccessorItem);
    procedure DoWriteMemberName(const AFile: TPCOutFile; const AMember: TPCMember);
    procedure DoWritePropertyAssign(const AFile: TPCOutFile; const AAssign: TPCAssign);
    procedure DoWritePropertyCallHead(const AFile: TPCOutFile; const AMember: TPCMember; const AIndex: TPCIndex;
      const AProperty: TPCPropertyItem; const ASet: Boolean);
    procedure DoWriteDefaultObject(const AFile: TPCOutFile; const AIndex: TPCIndex);
    procedure DoWritePropertyForwards(const AFile: TPCOutFile; const ARecord: TPCRecordType);
    function DoPropertyQualifier(const AMember: TPCMember): string;
    procedure DoWritePropertyObject(const AFile: TPCOutFile; const AMember: TPCMember);
    // PLAN-OBJECT D3: init / done as constructors / a destructor
    class function DoInitTagName(const ARecord: TPCRecordType; const AInit: TPCInitItem): string; static;
    class function DoHasDone(const ARecord: TPCRecordType): Boolean; static;
    class function DoHasInits(const ARecord: TPCRecordType): Boolean; static;
    class function DoChainHasValueOps(const ARecord: TPCRecordType): Boolean; static;
    procedure DoWriteForwards(const AFile: TPCOutFile; const ARecord: TPCRecordType);
    procedure DoWriteForward(const AFile: TPCOutFile; const AItem: TPCMethodItem; const ATarget: string);
    class function DoForwardArgs(const ARoutine: TPCRoutine): string; static;
    procedure DoWriteEmbedPath(const AFile: TPCOutFile; const AMember: TPCMember);
    procedure DoWriteValueMembers(const AFile: TPCOutFile; const ADecl: TPCTypeDecl; const ARecord: TPCRecordType);
    procedure DoWriteInitHead(const AFile: TPCOutFile; const AItem: TPCInitItem; const AOwner: string);
    procedure DoWriteDoneHead(const AFile: TPCOutFile; const AOwner: string);
    procedure DoEmitInitItem(const AFile: TPCOutFile; const AItem: TPCInitItem; const AInClass: Boolean);
    procedure DoWritePlainInit(const AFile: TPCOutFile; const AItem: TPCInitItem);
    procedure DoEmitDoneItem(const AFile: TPCOutFile; const AItem: TPCDoneItem; const AInClass: Boolean);
    procedure DoEmitInitBody(const AItem: TPCInitItem);
    procedure DoWriteLeadInit(const ACall: TPCCall; const AFirst: Boolean);
    procedure DoWriteInitArgs(const AFile: TPCOutFile; const AType: TPCTypeExpr; const ACall: TPCCall);
    procedure DoEmitMethodDefs(const ADecl: TPCTypeDecl);
    // PLAN-OBJECT O11 (D13)
    class function DoOperatorName(const AItem: TPCOperatorItem): string; static;
    procedure DoWriteOperatorHead(const AFile: TPCOutFile; const AItem: TPCOperatorItem; const AOwner: string);
    procedure DoEmitOperatorItem(const AFile: TPCOutFile; const AItem: TPCOperatorItem; const AInClass: Boolean);
    procedure DoWriteOperatorCall(const AFile: TPCOutFile; const AItem: TPCOperatorItem;
      const AOperands: array of TPCExpr);
    class function DoHasMethods(const ADecl: TPCTypeDecl): Boolean; static;
    class function DoIsPolymorphicRoot(const ARecord: TPCRecordType): Boolean; static;
    class function DoIsDllExport(const ADecl: TPCDecl): Boolean; static;
    procedure DoWriteCppType(const AFile: TPCOutFile; const AType: TPCCppType);
    procedure DoWord(const AFile: TPCOutFile; const AText: string; var ASpace: Boolean);
    procedure DoWriteNamePart(const AFile: TPCOutFile; const APart: TPCNamePart);
    procedure DoWriteTemplateArg(const AFile: TPCOutFile; const AArg: TPCTemplateArg);
    procedure DoWriteExpr(const AFile: TPCOutFile; const AExpr: TPCExpr);
    procedure DoWriteTypeConstant(const AFile: TPCOutFile; const AExpr: TPCExpr);
    procedure DoWriteExprAs(const AFile: TPCOutFile; const AExpr: TPCExpr; const AIsStmt: Boolean);
    procedure DoWriteOperand(const AFile: TPCOutFile; const AExpr: TPCExpr);
    procedure DoWriteBorrowedExpr(const AFile: TPCOutFile; const AExpr: TPCExpr);
    procedure DoWriteLiteral(const AFile: TPCOutFile; const ALiteral: TPCLiteral);
    function DoPartsRespelled(const ALiteral: TPCLiteral): Boolean;
    function DoLiteralCppText(const ALiteral: TPCLiteral): string;
    procedure DoWriteLiteralToken(const AFile: TPCOutFile; const AText: string;
      const ARange: TSourceRange; const ALiteral: TPCLiteral);
    procedure DoWriteVerbatimExpr(const AFile: TPCOutFile; const AExpr: TPCVerbatimExpr);
    procedure DoWriteMember(const AFile: TPCOutFile; const AMember: TPCMember);
    procedure DoWriteBinary(const AFile: TPCOutFile; const ABinary: TPCBinary);
    procedure DoWriteUnary(const AFile: TPCOutFile; const AUnary: TPCUnary);
    procedure DoWriteTernary(const AFile: TPCOutFile; const ATernary: TPCTernary);
    procedure DoWriteAssign(const AFile: TPCOutFile; const AAssign: TPCAssign; const AIsStmt: Boolean);
    procedure DoWriteChoicesStore(const AFile: TPCOutFile; const AField: TPCField; const AValue: TPCExpr);
    procedure DoWriteCall(const AFile: TPCOutFile; const ACall: TPCCall);
    procedure DoWriteCandidates(const AFile: TPCOutFile; const ACall: TPCCall);
    procedure DoWriteArgs(const AFile: TPCOutFile; const AArgs: TList<TPCExpr>; const AFirst: Integer;
      const ALast: Integer);
    function DoRankWrapper(const ACall: TPCCall; const AIndex: Integer): string;
    procedure DoWriteRankedArgs(const AFile: TPCOutFile; const ACall: TPCCall);
    procedure DoWritePack(const AFile: TPCOutFile; const ACall: TPCCall; const AFirst: Integer);
    procedure DoWriteSlot(const AFile: TPCOutFile; const AArg: TPCExpr);
    procedure DoWriteConversion(const AFile: TPCOutFile; const ACall: TPCCall);
    procedure DoWriteIntrinsic(const AFile: TPCOutFile; const ACall: TPCCall);
    procedure DoWriteRuntimeArgs(const AFile: TPCOutFile; const ACall: TPCCall);
    procedure DoWriteRuntimeCall(const AFile: TPCOutFile; const AName: string; const ACall: TPCCall);
    procedure DoWritePrintElement(const AFile: TPCOutFile; const AArrayType: TPCTypeExpr;
      const ADepth: Integer);
    procedure DoWritePrintCheck(const AFile: TPCOutFile; const AArg: TPCExpr);
    procedure DoWritePrintArg(const AFile: TPCOutFile; const AArg: TPCExpr);
    procedure DoWritePrint(const AFile: TPCOutFile; const ACall: TPCCall);
    procedure DoWriteTestCall(const AFile: TPCOutFile; const ACall: TPCCall);
    function DoCreationSiteText(const ANode: TPCNode): string;
    procedure DoWriteOwnerNew(const AFile: TPCOutFile; const ANew: TPCOwnerNew);
    procedure DoWriteTypeTest(const AFile: TPCOutFile; const ATest: TPCTypeTest);
    procedure DoWriteIndex(const AFile: TPCOutFile; const AIndex: TPCIndex);
    procedure DoWriteCast(const AFile: TPCOutFile; const ACast: TPCCast);
    procedure DoWriteNew(const AFile: TPCOutFile; const ANew: TPCNew);
    procedure DoWriteDelete(const AFile: TPCOutFile; const ADelete: TPCDelete);
    procedure DoWriteBracedInit(const AFile: TPCOutFile; const AInit: TPCBracedInit);
    procedure DoWriteSetLiteral(const AFile: TPCOutFile; const ASet: TPCSetLiteral);
    procedure DoWriteRecordLiteral(const AFile: TPCOutFile; const ARecord: TPCRecordLiteral);
    procedure DoWriteLiteralLevel(const AFile: TPCOutFile; const ARecord: TPCRecordLiteral;
      const ALevel: Integer; var AIndex: Integer);
    procedure DoWriteVarargs(const AFile: TPCOutFile; const AVarargs: TPCVarargs);
    procedure DoWriteVarargsLocalCall(const AFile: TPCOutFile; const ACall: TPCCall);
    procedure DoWriteVarargsReadType(const AFile: TPCOutFile; const ACall: TPCCall; const ASlot: Integer);
    procedure DoWriteSpecial(const AFile: TPCOutFile; const ASpecial: TPCSpecial);
    procedure DoWriteName(const AFile: TPCOutFile; const AName: TPCName);
    procedure DoWriteBound(const AFile: TPCOutFile; const AExpr: TPCExpr);
    procedure DoEmitTypeDecl(const AFile: TPCOutFile; const ADecl: TPCTypeDecl; const AModuleLevel: Boolean);
    procedure DoEmitRecord(const AFile: TPCOutFile; const ADecl: TPCTypeDecl; const ARecord: TPCRecordType);
    procedure DoWriteRecordMarkers(const AFile: TPCOutFile; const ARecord: TPCRecordType);
    procedure DoWriteParentConversions(const AFile: TPCOutFile; const ARecord: TPCRecordType);
    function DoNeedsAlignCheck(const ARecord: TPCRecordType): Boolean;
    function DoNeedsValueCheck(const ARecord: TPCRecordType): Boolean;
    procedure DoWriteAlignValue(const AFile: TPCOutFile; const ARecord: TPCRecordType);
    procedure DoWriteAlignValuePower(const AFile: TPCOutFile; const ARecord: TPCRecordType);
    procedure DoWriteAlignValueOk(const AFile: TPCOutFile; const ARecord: TPCRecordType);
    procedure DoWriteAlignLeaf(const AFile: TPCOutFile; const AType: TPCTypeExpr; const AWChar16: Boolean;
      const AAsAlignas: Boolean; var AFirst: Boolean);
    procedure DoWriteAlignMembers(const AFile: TPCOutFile; const AMembers: TList<TPCMemberItem>;
      const AAsAlignas: Boolean; var AFirst: Boolean);
    procedure DoWriteAlignLeaves(const AFile: TPCOutFile; const ARecord: TPCRecordType; const AAsAlignas: Boolean);
    procedure DoWriteAlignCheck(const AFile: TPCOutFile; const ARecord: TPCRecordType);
    procedure DoEmitMembers(const AFile: TPCOutFile; const AMembers: TList<TPCMemberItem>; const AInUnion: Boolean;
      const AInClass: Boolean);
    procedure DoEmitField(const AFile: TPCOutFile; const AField: TPCField; const AInUnion: Boolean);
    procedure DoWritePackedCheck(const AFile: TPCOutFile; const AType: TPCTypeExpr; const AOwner: TPCNode);
    procedure DoWriteOverlayCheck(const AFile: TPCOutFile; const AField: TPCField);
    procedure DoWriteOverlayLayouts(const AFile: TPCOutFile; const AMembers: TList<TPCMemberItem>;
      const AIsOverlay: Boolean; var ANext: Integer);
    procedure DoWriteLayoutMembers(const AFile: TPCOutFile; const AMembers: TList<TPCMemberItem>);
    procedure DoWriteOverlayZero(const AFile: TPCOutFile);
    procedure DoEmitAnonAggregate(const AFile: TPCOutFile; const AAggregate: TPCAnonAggregate;
      const AInUnion: Boolean; const AInClass: Boolean);
    procedure DoEmitChoices(const AFile: TPCOutFile; const ADecl: TPCTypeDecl; const AChoices: TPCChoicesType);
    procedure DoHoistLocalChoices(const ARoutine: TPCRoutine; const ALine: UInt64);
    procedure DoOpenRun(const AFile: TPCOutFile; const ALine: UInt64);
    procedure DoCloseRun(const AFile: TPCOutFile);
    procedure DoWriteHeaderPreamble();
    procedure DoWriteSourcePreamble();
    procedure DoEmitFile(const AFile: TPCOutFile);
    procedure DoEmitItem(const AItem: TPCModuleItem; const AFile: TPCOutFile);
    procedure DoEmitDecl(const AStmt: TPCStmt; const AFile: TPCOutFile);
    procedure DoEmitStmts(const AStmts: TList<TPCStmt>);
    procedure DoEmitStmt(const AStmt: TPCStmt);
    procedure DoEnterBody(const ARoutine: TPCRoutine; out ASaved: TPCRoutine);
    procedure DoLeaveBody(const ASaved: TPCRoutine);
    procedure DoPush(const AStmt: TPCStmt; const AIsLambda: Boolean);
    procedure DoPop();
    function DoEscapeLambda(const ATarget: TPCStmt): TPCGuard;
    function DoDispatchLambda(const ALoopsOnly: Boolean): TPCGuard;
    function DoHasResult(): Boolean;
    function DoDispatchSet(const AGuard: TPCGuard): TPCGuardEscapes;
    procedure DoPutClose(const ALine: UInt64; const AText: string);
    procedure DoWriteBorrowedType(const AFile: TPCOutFile; const AType: TPCTypeExpr);
    procedure DoEmitBlock(const ABlock: TPCBlock);
    procedure DoEmitIf(const AIf: TPCIf);
    procedure DoEmitWhile(const AWhile: TPCWhile);
    procedure DoEmitRepeat(const ARepeat: TPCRepeat);
    procedure DoEmitFor(const AFor: TPCFor);
    procedure DoEmitMatch(const AMatch: TPCMatch);
    procedure DoEmitMatchLabel(const ALabel: TPCMatchLabel);
    procedure DoEmitGuard(const AGuard: TPCGuard);
    procedure DoEmitDispatch(const AGuard: TPCGuard);
    procedure DoEmitReturn(const AReturn: TPCReturn);
    procedure DoEmitJump(const AStmt: TPCStmt; const ATarget: TPCStmt; const AEscape: TPCGuardEscape);
    procedure DoEmitExprStmt(const AStmt: TPCExprStmt);
    procedure DoWriteChoiceValue(const AFile: TPCOutFile; const AValue: TPCNode);
    procedure DoEmitTest(const ATest: TPCTest);
    procedure DoEmitSection(const ARoutine: TPCRoutine; const AFunctionName: string);
    procedure DoEmitBody();
    procedure DoEmitTrailer();
    function DoInitChain(): string;
    function DoFinalChain(): string;
    function DoRegisterChain(): string;
    // The ONE way an entry into PaskalCPP code from outside is written:
    // AStatements run inside ::pcpp::enter, which returns AResult (an
    // unhandled raise is reported by the runtime, debugged or not)
    function DoEntryText(const AStatements: string; const AResult: string): string;
    function DoMainText(): string;
    function DoDllText(): string;
    function DoLibText(): string;
    function DoWriteFile(const APath: string; const ABytes: TBytes): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetErrors(const AErrors: TErrors); override;

    // The C++ spelling of a module's namespace and of a declaration: the one
    // naming rule, public so the debugger matches PDB symbols by it (E3 x2)
    class function DoNamespaceName(const AModule: TPCModule): string; static;
    class function DoDeclName(const ADecl: TPCDecl): string; static;
    // The linkage rule, once: a signature is extern "C" by ResolvedLinkage
    // when it is not static and has no owner; a module-level definition is
    // static unless exported. DoSymbolIsC = the definition this module emits
    // for ARoutine has C linkage, so its toolchain symbol is the bare
    // DeclName, outside the module's namespace (the debugger matches PDB
    // functions by it)
    class function DoHasCLinkage(const ARoutine: TPCRoutine; const AStatic: Boolean;
      const AOwner: string): Boolean; static;
    class function DoIsStaticDefinition(const ARoutine: TPCRoutine): Boolean; static;
    class function DoSymbolIsC(const ARoutine: TPCRoutine): Boolean; static;

    // Reads the program facts once. Test mode = @unitTestMode on in an exe
    // main module (BNF sec 8). AMainModule is the file handed to the compiler
    procedure Init(const AAst: TPCAst; const AMainModule: TPCModule);
    // The module's two files as UTF-8 bytes; pure. False = EM0003 reported
    function EmitModule(const AModule: TPCModule; out AHeader: TBytes; out ASource: TBytes): Boolean;
    // Every module of the AST into AOutputDir as <ModuleName>.pcpp.h / .pcpp.cpp
    function WriteFiles(const AOutputDir: string): Boolean;
  end;

implementation

uses
  System.TypInfo,
  System.IOUtils,
  StdApp.Utils,
  StdApp.Resources;

const
  { PC_EMT_TEST_MODE_ON }
  // The @unitTestMode value that turns test mode on (PC_DIRECTIVE_VALUES, Common)
  PC_EMT_TEST_MODE_ON = 'on';
  { PC_EMT_INIT_NAME }
  PC_EMT_INIT_NAME = 'pcpp_initialize';
  { PC_EMT_FINAL_NAME }
  PC_EMT_FINAL_NAME = 'pcpp_finalize';
  { PC_EMT_REGISTER_NAME }
  PC_EMT_REGISTER_NAME = 'pcpp_register_tests';
  { PC_EMT_BODY_NAME }
  PC_EMT_BODY_NAME = 'pcpp_main_body';
  { PC_EMT_ENTER_NAME }
  // The runtime routine every entry runs through (research\runtime\api.md)
  PC_EMT_ENTER_NAME = '::pcpp::enter';
  { PC_EMT_TEST_PREFIX }
  // A test block's function: the prefix + the test's Range.StartByteOffset
  PC_EMT_TEST_PREFIX = 'pcpp_test_';
  { PC_EMT_LOCAL_CHOICES_PREFIX }
  // A local choices type hoisted into the module's namespace (H3): the prefix
  // + the TPCChoicesType's Range.StartByteOffset (unique in the module)
  PC_EMT_LOCAL_CHOICES_PREFIX = 'pcpp_choices_';
  { PC_EMT_MODULE_NS_PREFIX }
  // A module's C++ namespace is pcpp_m_<ModuleName> (DoNamespaceName)
  PC_EMT_MODULE_NS_PREFIX = 'pcpp_m_';
  { PC_EMT_VARARGS_NAME }
  // A variadic routine's pack (cpplink, O-V1) or va_list (clink, H5)
  PC_EMT_VARARGS_NAME = 'pcpp_va';
  { PC_EMT_RECORD_MARKER }
  // PLAN-RECORDS M12 (3): every PaskalCPP record (runtime concept record)
  PC_EMT_RECORD_MARKER = 'using pcpp_record = void;';
  { PC_EMT_PARENT_TYPE_MARKER }
  // An extension's parent record (runtime parent_t)
  PC_EMT_PARENT_TYPE_MARKER = 'pcpp_parent_t';
  { PC_EMT_CPP_BASE_MARKER }
  // The C/C++ base of a record (runtime cpp_base_t)
  PC_EMT_CPP_BASE_MARKER = 'pcpp_cpp_base_t';
  { PC_EMT_PARENT_COPY }
  // The local a by-value conversion copies a parent part into (F-R4f)
  PC_EMT_PARENT_COPY = 'pcpp_v';
  { PC_EMT_ALIGN_CHECK_FOLD }
  // The record's natural alignment as ONE value clang computes from the
  // leaf types (the lambda's template arguments follow it): a fold linear in
  // the type count, needing no header, so the failed check's note carries the
  // number ('4 >= 8'; r-b-align.md P5, probed both targets)
  PC_EMT_ALIGN_CHECK_FOLD = ') >= []<class... T>() { decltype(sizeof(0)) M = 1; ' +
    '((M = alignof(T) > M ? alignof(T) : M), ...); return M; }.template operator()<';

{ TPCEmitter }

constructor TPCEmitter.Create();
var
  LFile: TPCOutFile;
begin
  inherited;

  for LFile := Low(TPCOutFile) to High(TPCOutFile) do
    FWriters[LFile] := TPCCppWriter.Create();
  // V1: header and source share one column space per .pcpp line
  FWriters[ofHeader].SetPeer(FWriters[ofSource]);
  FWriters[ofSource].SetPeer(FWriters[ofHeader]);
  FOpen := TList<TPCOpenStmt>.Create();
  FHeaderDecls := TList<TPCDecl>.Create();
end;

destructor TPCEmitter.Destroy();
var
  LFile: TPCOutFile;
begin
  for LFile := Low(TPCOutFile) to High(TPCOutFile) do
    FWriters[LFile].Free();
  FOpen.Free();
  FHeaderDecls.Free();

  inherited;
end;

procedure TPCEmitter.SetErrors(const AErrors: TErrors);
var
  LFile: TPCOutFile;
begin
  inherited;

  for LFile := Low(TPCOutFile) to High(TPCOutFile) do
    FWriters[LFile].SetErrors(AErrors);
end;

procedure TPCEmitter.Init(const AAst: TPCAst; const AMainModule: TPCModule);
var
  LDirective: TPCDirective;
begin
  FAst := AAst;
  FMainModule := AMainModule;
  FModule := nil;
  // Test mode is the exe's (BNF sec 8): test blocks of a main dll / lib
  // never run, so they are not compiled in either
  FTestMode := False;
  if AMainModule.ModuleKind <> mkExe then
    Exit;
  for LDirective in AMainModule.Directives do
  begin
    if (LDirective.DirectiveKind = bdUnitTestMode) and (LDirective.Args.Count > 0) then
      FTestMode := LDirective.Args[0].Text = PC_EMT_TEST_MODE_ON;
  end;
end;

class procedure TPCEmitter.DoPick(const ANode: TPCNode; const AKind: TPCModuleItemKind; var ABest: TPCNode;
  var ABestKind: TPCModuleItemKind);
begin
  // The candidate that starts first in the source wins
  if (ABest = nil) or (ANode.Range.StartByteOffset < ABest.Range.StartByteOffset) then
  begin
    ABest := ANode;
    ABestKind := AKind;
  end;
end;

procedure TPCEmitter.DoNoRule(const ANode: TPCNode);
begin
  // Every node of an analyzed AST has a C++ rule; one without is an invariant
  raise EInvalidOpException.CreateFmt(RSEmtNoRule,
    [GetEnumName(TypeInfo(TPCNodeKind), Ord(ANode.NodeKind)), ANode.Range.StartLine]);
end;

procedure TPCEmitter.DoMissing(const AFile: TPCOutFile; const AWhat: string);
begin
  // A child the analyzed AST must have (the parser reported every missing one)
  raise EInvalidOpException.CreateFmt(RSEmtMissingNode, [AWhat, FWriters[AFile].SourceLine()]);
end;

class function TPCEmitter.DoBuiltinText(const AKind: TPCTokenKind): string;
begin
  // A5: the C++ type of each PaskalCPP builtin (same on every target, BNF sec 2)
  case AKind of
    tkKwInt8:
      Result := 'std::int8_t';
    tkKwInt16:
      Result := 'std::int16_t';
    tkKwInt32:
      Result := 'std::int32_t';
    tkKwInt64:
      Result := 'std::int64_t';
    tkKwUint8:
      Result := 'std::uint8_t';
    tkKwUint16:
      Result := 'std::uint16_t';
    tkKwUint32:
      Result := 'std::uint32_t';
    tkKwUint64:
      Result := 'std::uint64_t';
    tkKwFloat32:
      Result := 'float';
    tkKwFloat64:
      Result := 'double';
    tkKwBool:
      Result := 'bool';
    tkKwChar:
      Result := 'char';
    tkKwWchar:
      Result := 'wchar_t';
    tkKwString:
      Result := 'std::string';
    tkKwWstring:
      Result := 'std::wstring';
    tkKwPtr:
      Result := 'void*';
    tkKwVarargs:
      Result := '::pcpp::VarArgs';
  else
    raise EInvalidOpException.CreateFmt(RSEmtNoTokenRule, [GetEnumName(TypeInfo(TPCTokenKind), Ord(AKind))]);
  end;
end;

class function TPCEmitter.DoTokenText(const AKind: TPCTokenKind): string;
var
  LRow: TPCTokenRow;
begin
  // A C++ fundamental or elaborated key as the vocabulary spells it
  if not TPCVocabulary.FindKindRow(AKind, LRow) then
    raise EInvalidOpException.CreateFmt(RSEmtNoTokenRule, [GetEnumName(TypeInfo(TPCTokenKind), Ord(AKind))]);
  Result := LRow.Text;
end;

class function TPCEmitter.DoCvText(const AFlags: TPCCvFlags): string;
begin
  Result := '';
  if cqConst in AFlags then
    Result := 'const';
  if cqVolatile in AFlags then
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + 'volatile';
  end;
end;

class function TPCEmitter.DoNamespaceName(const AModule: TPCModule): string;
begin
  // A module's C++ namespace: pcpp_m_<M>. A reserved prefix cannot collide
  // with a C/C++ global of any target (glibc declares index, time, stat ...
  // at global scope) nor hide one from the module's own code, which a
  // namespace named M would (cross-target parity, DESIGN sec 7)
  Result := PC_EMT_MODULE_NS_PREFIX + AModule.ModuleName;
end;

class function TPCEmitter.DoDeclName(const ADecl: TPCDecl): string;
begin
  // A module-level declaration is named from the global scope (E19, H1); a
  // local one by its plain name
  if ADecl.DeclModule <> nil then
    Result := '::' + DoNamespaceName(ADecl.DeclModule) + '::' + ADecl.DeclName
  else
    Result := ADecl.DeclName;
end;

class function TPCEmitter.DoHasCLinkage(const ARoutine: TPCRoutine; const AStatic: Boolean;
  const AOwner: string): Boolean;
begin
  // ResolvedLinkage (after demotion, never Linkage); a declaration in a
  // linkage spec takes no storage class, and a static routine or a member
  // has no symbol whose language could be seen
  Result := (ARoutine.ResolvedLinkage = lnC) and (not AStatic) and (AOwner = '');
end;

class function TPCEmitter.DoIsStaticDefinition(const ARoutine: TPCRoutine): Boolean;
begin
  // A module-level definition is private to its TU unless exported
  Result := not ARoutine.IsExported;
end;

class function TPCEmitter.DoSymbolIsC(const ARoutine: TPCRoutine): Boolean;
begin
  // Only a definition this module emits has a symbol here: an external
  // routine's code is another image's, a forward's is its full routine's
  Result := (not ARoutine.ExternalClause.IsExternal) and (not ARoutine.IsForward) and
    DoHasCLinkage(ARoutine, DoIsStaticDefinition(ARoutine), '');
end;

class function TPCEmitter.DoIsNamedPaskalType(const AType: TPCTypeExpr): Boolean;
begin
  // A type another node's spelling may borrow by name: a builtin or a
  // declared PaskalCPP type (no spans: the node lives elsewhere); the AST's
  // one rule (TPCAst.IsNamedPaskalType)
  Result := TPCAst.IsNamedPaskalType(AType);
end;

class function TPCEmitter.DoOrdinal(const AValue: TPCChoiceValue): Int64;
begin
  // SEM resolved every ordinal of an analyzed AST (0 is a valid one)
  if not AValue.HasResolvedOrdinal then
    raise EInvalidOpException.CreateFmt(RSEmtMissingNode, ['choice ordinal', AValue.Range.StartLine]);
  Result := AValue.ResolvedOrdinal;
end;

class function TPCEmitter.DoChoicesUnderlying(const AChoices: TPCChoicesType): string;
var
  LValue: TPCChoiceValue;
begin
  // TPCChoicesType.UnderlyingBits (the one rule); every value must carry its
  // ordinal by now (DoOrdinal raises on the invariant: called for it alone)
  for LValue in AChoices.Values do
    DoOrdinal(LValue);
  if AChoices.UnderlyingBits() = 64 then
    Result := 'std::int64_t'
  else
    Result := 'std::int32_t';
end;

class function TPCEmitter.DoFormatterText(const AEnumName: string; const ADisplayName: string;
  const AChoices: TPCChoicesType): string;
var
  LValue: TPCChoiceValue;
begin
  // O7: print / println show a choices value by name. An if chain, not a
  // switch: two values with one ordinal compile, the first one prints. A
  // value outside the list prints as <type name>(<ordinal>)
  Result := 'template <> struct std::formatter<' + AEnumName + '> { std::formatter<std::string_view> pcpp_fmt;' +
    ' template <class C> constexpr auto parse(C& pcpp_ctx) { return pcpp_fmt.parse(pcpp_ctx); }' +
    ' template <class C> auto format(const ' + AEnumName + ' pcpp_value, C& pcpp_ctx) const {';
  for LValue in AChoices.Values do
    Result := Result + ' if (pcpp_value == ' + AEnumName + '::' + LValue.ValueName + ') return pcpp_fmt.format("' +
      LValue.ValueName + '", pcpp_ctx);';
  Result := Result + ' const std::string pcpp_text = std::format("' + ADisplayName +
    '({})", static_cast<std::int64_t>(pcpp_value)); return pcpp_fmt.format(pcpp_text, pcpp_ctx); } };';
end;

class function TPCEmitter.DoFoldedCount(const ALow: TPCExpr; const AHigh: TPCExpr; out ACount: string): Boolean;
begin
  // A static array's element count from its folded bounds: the AST's one
  // rule (TPCAst.FoldedCount)
  Result := TPCAst.FoldedCount(ALow, AHigh, ACount);
end;

class function TPCEmitter.DoLocalChoicesName(const AChoices: TPCChoicesType): string;
begin
  Result := PC_EMT_LOCAL_CHOICES_PREFIX + UIntToStr(UInt64(AChoices.Range.StartByteOffset));
end;

function TPCEmitter.DoNextItem(var ACursor: TPCItemCursor; out AItem: TPCModuleItem): Boolean;
var
  LBest: TPCNode;
  LKind: TPCModuleItemKind;
begin
  // The next item in source order: the head of each list is a candidate
  LBest := nil;
  LKind := miTrailer;
  if ACursor.DeclIndex < FModule.Decls.Count then
    DoPick(FModule.Decls[ACursor.DeclIndex], miDecl, LBest, LKind);
  if ACursor.TestIndex < FModule.Tests.Count then
    DoPick(FModule.Tests[ACursor.TestIndex], miTest, LBest, LKind);
  if (not ACursor.InitTaken) and (FModule.InitRoutine <> nil) then
    DoPick(FModule.InitRoutine, miInit, LBest, LKind);
  if (not ACursor.FinalTaken) and (FModule.FinalRoutine <> nil) then
    DoPick(FModule.FinalRoutine, miFinal, LBest, LKind);
  if (not ACursor.BodyTaken) and FModule.HasBody and (FModule.Body <> nil) then
    DoPick(FModule.Body, miBody, LBest, LKind);

  // Every list done: the trailer, once
  if LBest = nil then
  begin
    if ACursor.TrailerTaken then
      Exit(False);
    ACursor.TrailerTaken := True;
    AItem.ItemKind := miTrailer;
    AItem.Node := nil;
    Exit(True);
  end;

  case LKind of
    miDecl:
      Inc(ACursor.DeclIndex);
    miTest:
      Inc(ACursor.TestIndex);
    miInit:
      ACursor.InitTaken := True;
    miFinal:
      ACursor.FinalTaken := True;
    miBody:
      ACursor.BodyTaken := True;
  end;
  AItem.ItemKind := LKind;
  AItem.Node := LBest;
  Result := True;
end;

function TPCEmitter.DoItemLine(const AItem: TPCModuleItem): UInt64;
begin
  // Where an item's first part starts: the trailer on the module's last line
  if AItem.ItemKind = miTrailer then
    Result := FModule.Range.EndLine
  else
    Result := AItem.Node.Range.StartLine;
end;

function TPCEmitter.DoDeclPart(const AStmt: TPCStmt; const AFile: TPCOutFile): TPCEmitPart;
var
  LTarget: TPCEmitTarget;
begin
  // Directives write nothing (bnf-map sec 2)
  if AStmt is TPCDirective then
    Exit(epNone);

  // Module-level verbatim goes to its target file (the parser stamps a # line
  // with the current cpp header|source placement, BNF sec 10); etInPlace
  // exists only in bodies
  if AStmt is TPCVerbatimStmt then
  begin
    LTarget := TPCVerbatimStmt(AStmt).Verbatim.EmitTarget;
    if LTarget = etInPlace then
      raise EInvalidOpException.CreateFmt(RSEmtModuleTarget, [AStmt.Range.StartLine]);
    if ((LTarget = etHeader) and (AFile = ofHeader)) or ((LTarget = etSource) and (AFile = ofSource)) then
      Exit(epGlobal);
    Exit(epNone);
  end;

  // Every PaskalCPP declaration stands in the namespace run; which file(s)
  // it writes into is DoDeclInFile's rule
  if DoDeclInFile(AStmt, AFile) then
    Result := epNamespace
  else
    Result := epNone;
end;

function TPCEmitter.DoDeclInFile(const AStmt: TPCStmt; const AFile: TPCOutFile): Boolean;
var
  LRoutine: TPCRoutine;
begin
  // A5 / A6 placement of a module-level declaration:
  // - type: exported, or private and named by the header's own text
  //   (FHeaderDecls, E5) = the header (an object's method definitions also
  //   the source, H4); else the source, at its own place, beside the C++ it
  //   may name (its methods defined in the class there)
  // - var: exported = header extern + source definition; private = source;
  //   external = header when exported, else source (no definition)
  // - const: exported = header (inline), private = source; a private one the
  //   header's own text names (FHeaderDecls, F22) = header (inline) too
  // - routine: exported = header prototype + source definition, private =
  //   source; external like a var; forward = source, only when its full
  //   routine is private (an exported one's header prototype precedes it)
  if AStmt is TPCTypeDecl then
  begin
    if TPCTypeDecl(AStmt).IsExported or FHeaderDecls.Contains(TPCTypeDecl(AStmt)) then
    begin
      if AFile = ofHeader then
        Exit(True);
      Exit(DoHasMethods(TPCTypeDecl(AStmt)));
    end;
    Exit(AFile = ofSource);
  end;
  if AStmt is TPCVarDecl then
  begin
    if TPCVarDecl(AStmt).ExternalClause.IsExternal then
      Exit(TPCVarDecl(AStmt).IsExported = (AFile = ofHeader));
    Exit((AFile = ofSource) or TPCVarDecl(AStmt).IsExported);
  end;
  if AStmt is TPCConstDecl then
    Exit((TPCConstDecl(AStmt).IsExported or FHeaderDecls.Contains(TPCConstDecl(AStmt))) =
      (AFile = ofHeader));
  if AStmt is TPCRoutine then
  begin
    LRoutine := TPCRoutine(AStmt);
    if LRoutine.IsForward then
    begin
      if LRoutine.ResolvedFull = nil then
        DoNoRule(LRoutine);
      Exit((AFile = ofSource) and (not LRoutine.ResolvedFull.IsExported));
    end;
    if LRoutine.ExternalClause.IsExternal then
      Exit(LRoutine.IsExported = (AFile = ofHeader));
    Exit((AFile = ofSource) or LRoutine.IsExported);
  end;
  // Nothing else stands at module level in an analyzed AST
  DoNoRule(AStmt);
  Result := False;
end;

procedure TPCEmitter.DoCollectHeaderDecls();
var
  LPending: TList<TPCNode>;
  LNode: TPCNode;
  LStmt: TPCStmt;
  LOther: TPCStmt;
  LRoutine: TPCRoutine;
  LParam: TPCParam;
  LTarget: TPCNode;
  LConst: TPCConstDecl;
  LText: string;
begin
  // F22 / E5: an exported const, var, type or routine must build whatever
  // private const or type its header text names. The roots are the module's
  // items the placement rule writes into the header by being exported
  // (DoDeclPart, the one rule: FHeaderDecls is empty here, so it answers for
  // the exported ones only), plus every private module-level type a header
  // verbatim item names by its emitted name (conservative, as
  // TPCAst.TextNamesRuntime: a false hit keeps the type in the header, a
  // miss would fail the header's C++). From each root, the parts the header
  // holds are walked: a routine's (or method's) signature, never its body; a
  // var's type, never its initializer; everything of a const and a type
  // definition. A private module-level const or type reached there joins
  // FHeaderDecls and is walked in turn (its own definition may name
  // another); a type takes its forward / full partners with it. Only the
  // AST's resolved references are read; the list is the emitter's own
  // placement, rebuilt for every module
  FHeaderDecls.Clear();
  LPending := TList<TPCNode>.Create();
  try
    for LStmt in FModule.Decls do
    begin
      if LStmt is TPCTypeDecl then
      begin
        // An exported type is a root; a private partner of it joins
        if TPCTypeDecl(LStmt).IsExported then
        begin
          LPending.Add(LStmt);
          DoJoinTypePartners(TPCTypeDecl(LStmt), LPending);
        end;
        Continue;
      end;
      if DoDeclPart(LStmt, ofHeader) = epNamespace then
        LPending.Add(LStmt)
      else if (LStmt is TPCVerbatimStmt) and (DoDeclPart(LStmt, ofHeader) = epGlobal) then
      begin
        // Header C++ (cpp header; a cppstart header block, a # line) that
        // names a private type needs that type before it
        LText := TPCVerbatimStmt(LStmt).Verbatim.Text;
        for LOther in FModule.Decls do
        begin
          if (LOther is TPCTypeDecl) and (not TPCTypeDecl(LOther).IsExported) and
            DoTextNamesWord(LText, TPCTypeDecl(LOther).DeclName) then
            DoJoinHeaderType(TPCTypeDecl(LOther), LPending);
        end;
      end;
    end;
    // A work list, not a self-calling visitor (TPCAst.ModuleNamesRuntime)
    while LPending.Count > 0 do
    begin
      LNode := LPending[LPending.Count - 1];
      LPending.Delete(LPending.Count - 1);
      if LNode = nil then
        Continue;
      if LNode is TPCRoutine then
      begin
        LRoutine := TPCRoutine(LNode);
        for LParam in LRoutine.Params do
          LPending.Add(LParam);
        LPending.Add(LRoutine.ReturnType);
        Continue;
      end;
      if LNode is TPCVarDecl then
      begin
        LPending.Add(TPCVarDecl(LNode).TypeExpr);
        Continue;
      end;
      LTarget := nil;
      if LNode is TPCName then
        LTarget := TPCName(LNode).ResolvedDecl
      else if LNode is TPCMember then
        LTarget := TPCMember(LNode).ResolvedDecl
      else if LNode is TPCNamedType then
        LTarget := TPCNamedType(LNode).ResolvedDecl;
      if LTarget is TPCConstDecl then
      begin
        LConst := TPCConstDecl(LTarget);
        if (not LConst.IsExported) and (not FHeaderDecls.Contains(LConst)) and
          FModule.Decls.Contains(LConst) then
        begin
          FHeaderDecls.Add(LConst);
          LPending.Add(LConst);
        end;
      end
      else if LTarget is TPCTypeDecl then
        DoJoinHeaderType(TPCTypeDecl(LTarget), LPending)
      else if (LTarget is TPCChoiceValue) and (TPCChoiceValue(LTarget).ResolvedChoices is TPCNamedType) then
        // A choice value is written qualified by its type's name; an
        // anonymous one's type is written with the node that declares it
        LPending.Add(TPCChoiceValue(LTarget).ResolvedChoices);
      // Only what the header text holds: a type's folded slot is a number
      // there (TPCAst.EnumWrittenChildren, ModuleNamesRuntime's rule too)
      TPCAst.EnumWrittenChildren(LNode,
        procedure(const AChild: TPCNode)
        begin
          LPending.Add(AChild);
        end);
    end;
  finally
    LPending.Free();
  end;
end;

procedure TPCEmitter.DoJoinHeaderType(const ADecl: TPCTypeDecl; const APending: TList<TPCNode>);
begin
  // A private module-level type the header's text names joins the header
  // once, is walked in turn, and takes its partners with it. An exported one
  // is a root already; a local one or another module's is written elsewhere
  if (ADecl = nil) or ADecl.IsExported or FHeaderDecls.Contains(ADecl) then
    Exit;
  if not FModule.Decls.Contains(ADecl) then
    Exit;
  FHeaderDecls.Add(ADecl);
  APending.Add(ADecl);
  DoJoinTypePartners(ADecl, APending);
end;

procedure TPCEmitter.DoJoinTypePartners(const ADecl: TPCTypeDecl; const APending: TList<TPCNode>);
var
  LStmt: TPCStmt;
begin
  // A forward type and its full declaration stand in one file, so the
  // forward precedes the full there (a header pointer to the type needs at
  // least the forward; the full completes it): a forward takes its full, a
  // full every forward that resolves to it
  if ADecl.IsForward then
  begin
    DoJoinHeaderType(ADecl.ResolvedFull, APending);
    Exit;
  end;
  for LStmt in FModule.Decls do
  begin
    if (LStmt is TPCTypeDecl) and TPCTypeDecl(LStmt).IsForward and (TPCTypeDecl(LStmt).ResolvedFull = ADecl) then
      DoJoinHeaderType(TPCTypeDecl(LStmt), APending);
  end;
end;

class function TPCEmitter.DoTextNamesWord(const AText: string; const AWord: string): Boolean;
var
  LPos: Integer;
  LEnd: Integer;
  LBefore: Boolean;
  LAfter: Boolean;
begin
  // AWord as a whole C++ identifier in AText: neither neighbour is a
  // character an identifier holds (conservative: a hit in a comment or a
  // string counts too)
  Result := False;
  if AWord = '' then
    Exit;
  LPos := AText.IndexOf(AWord);
  while LPos >= 0 do
  begin
    LEnd := LPos + AWord.Length;
    LBefore := (LPos = 0) or not CharInSet(AText.Chars[LPos - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']);
    LAfter := (LEnd >= AText.Length) or not CharInSet(AText.Chars[LEnd], ['A'..'Z', 'a'..'z', '0'..'9', '_']);
    if LBefore and LAfter then
      Exit(True);
    LPos := AText.IndexOf(AWord, LPos + 1);
  end;
end;

function TPCEmitter.DoHasRegistration(): Boolean;
begin
  // pcpp_register_tests exists in test mode for a module with test blocks
  Result := FTestMode and (FModule.Tests.Count > 0);
end;

function TPCEmitter.DoHasEntry(): Boolean;
begin
  // The main module's entry text: an exe's main and a dll's hooks always
  // (the runtime TU is linked into both); a lib's hooks only when the
  // program uses the runtime (TPCAst.UsesRuntime, r10 D-R10-2): a lib that
  // does not ships alone, with no ::pcpp::init to resolve
  if FModule <> FMainModule then
    Exit(False);
  if FModule.ModuleKind = mkLib then
    Exit(FAst.UsesRuntime());
  Result := (FModule.ModuleKind = mkExe) or (FModule.ModuleKind = mkDll);
end;

function TPCEmitter.DoTrailerPart(const AFile: TPCOutFile): TPCEmitPart;
begin
  // The trailer's first part: the registration (in the run), else the main
  // module's entry text (global); a unit has none
  if AFile <> ofSource then
    Exit(epNone);
  if DoHasRegistration() then
    Exit(epNamespace);
  if DoHasEntry() then
    Exit(epGlobal);
  Result := epNone;
end;

function TPCEmitter.DoPartKind(const AItem: TPCModuleItem; const AFile: TPCOutFile): TPCEmitPart;
begin
  case AItem.ItemKind of
    miDecl:
      Result := DoDeclPart(TPCStmt(AItem.Node), AFile);
    miTest:
      begin
        // Test mode off: test blocks are checked, not compiled in (BNF sec 8)
        if FTestMode and (AFile = ofSource) then
          Result := epNamespace
        else
          Result := epNone;
      end;
    miInit, miFinal, miBody:
      begin
        if AFile = ofSource then
          Result := epNamespace
        else
          Result := epNone;
      end;
  else
    Result := DoTrailerPart(AFile);
  end;
end;

function TPCEmitter.DoNextPartKind(const ACursor: TPCItemCursor; const AFile: TPCOutFile): TPCEmitPart;
var
  LCursor: TPCItemCursor;
  LItem: TPCModuleItem;
  LPart: TPCEmitPart;
begin
  // Lookahead over a copy of the cursor: the next item with a part in AFile
  LCursor := ACursor;
  while DoNextItem(LCursor, LItem) do
  begin
    LPart := DoPartKind(LItem, AFile);
    if LPart <> epNone then
      Exit(LPart);
  end;
  Result := epNone;
end;

procedure TPCEmitter.DoAt(const AFile: TPCOutFile; const ALine: UInt64);
begin
  // Text goes on its node's .pcpp line. Lines only go forward: a node with
  // no line (SEM-built) or one before the writer's line (text after a
  // multi-line verbatim of the same construct) stays on the current line.
  // Neither does a borrowed spelling: its node is written elsewhere, maybe in
  // another module's file (F18: an imported overload's parameter types)
  if FWriters[AFile].IsBorrowed() then
    Exit;
  if ALine > FWriters[AFile].SourceLine() then
    FWriters[AFile].SetSourceLine(ALine);
end;

function TPCEmitter.DoHasText(const AFile: TPCOutFile): Boolean;
begin
  // The open C++ line already holds text (column past 1)
  Result := FWriters[AFile].Mark().Col > 1;
end;

procedure TPCEmitter.DoBeginItem(const AFile: TPCOutFile; const ALine: UInt64);
begin
  // A new construct on .pcpp line ALine: one space after text already on
  // its C++ line (the emitter writes no other layout)
  DoAt(AFile, ALine);
  if DoHasText(AFile) then
    FWriters[AFile].WriteText(' ', nil);
end;

procedure TPCEmitter.DoPut(const AFile: TPCOutFile; const ALine: UInt64; const AText: string);
begin
  DoBeginItem(AFile, ALine);
  FWriters[AFile].WriteText(AText, nil);
end;

procedure TPCEmitter.DoText(const AFile: TPCOutFile; const AText: string);
begin
  // Continues the construct on the current C++ line, no separator
  FWriters[AFile].WriteText(AText, nil);
end;

procedure TPCEmitter.DoPutVerbatim(const AFile: TPCOutFile; const AStmt: TPCVerbatimStmt);
begin
  // Copied line for line, its spans on the statement (TranslateLocation)
  FWriters[AFile].WriteVerbatim(AStmt.Verbatim, AStmt);
end;

procedure TPCEmitter.DoWriteType(const AFile: TPCOutFile; const AType: TPCTypeExpr);
var
  LMark: TPCWriterMark;
begin
  // A type node of the tree, written where it stands: its text on its own
  // line, one span on it covering everything it wrote (TranslateLocation
  // picks the narrowest node)
  if AType = nil then
    DoMissing(AFile, 'type');
  DoAt(AFile, AType.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  if (AType is TPCBuiltinType) or (AType is TPCNamedType) then
    DoText(AFile, DoTypeName(AType))
  else if AType is TPCPointerType then
    DoWritePointerType(AFile, TPCPointerType(AType))
  else if AType is TPCOwnerType then
    DoWriteOwnerType(AFile, TPCOwnerType(AType))
  else if AType is TPCArrayType then
    DoWriteArrayType(AFile, TPCArrayType(AType))
  else if AType is TPCSetType then
    DoWriteSetType(AFile, TPCSetType(AType))
  else if AType is TPCRoutineType then
    DoWriteRoutineType(AFile, TPCRoutineType(AType))
  else if AType is TPCCppType then
    DoWriteCppType(AFile, TPCCppType(AType))
  else
    DoNoRule(AType);
  FWriters[AFile].CloseSpan(LMark, AType);
end;

function TPCEmitter.DoTypeName(const AType: TPCTypeExpr): string;
var
  LNamed: TPCNamedType;
begin
  // The spelling of a builtin or a named type (DoIsNamedPaskalType's set
  // plus an opaque C++ name), from Resolved* fields only
  if AType is TPCBuiltinType then
    Exit(DoBuiltinText(TPCBuiltinType(AType).BuiltinToken));
  if not (AType is TPCNamedType) then
    DoNoRule(AType);
  LNamed := TPCNamedType(AType);
  if (LNamed.ResolvedKind = rkType) and (LNamed.ResolvedDecl <> nil) then
    Result := DoDeclName(LNamed.ResolvedDecl)
  else if LNamed.ResolvedKind = rkOpaque then
    Result := string.Join('::', LNamed.Parts)
  else
    DoNoRule(AType);
end;

procedure TPCEmitter.DoWritePointerType(const AFile: TPCOutFile; const AType: TPCPointerType);
begin
  // ptr / ptr to [const] T. const follows the target (east const) so that a
  // compound target binds it: ptr to const ptr to char is char* const*
  if AType.TargetType = nil then
  begin
    if AType.IsConstTarget then
      DoText(AFile, 'const void*')
    else
      DoText(AFile, 'void*');
    Exit;
  end;
  DoWriteType(AFile, AType.TargetType);
  if AType.IsConstTarget then
    DoText(AFile, ' const*')
  else
    DoText(AFile, '*');
end;

procedure TPCEmitter.DoWriteOwnerType(const AFile: TPCOutFile; const AType: TPCOwnerType);
begin
  // PLAN-OBJECT O6 (D4): own T / ref T / weak T are the runtime's
  // ::pcpp::Own<T> / Ref<T> / Weak<T> (unique_ptr / shared_ptr / weak_ptr;
  // runtime api.md "Owners")
  DoText(AFile, PC_EMT_OWNER_TEMPLATES[AType.OwnerKind] + '<');
  DoWriteType(AFile, AType.TargetType);
  DoText(AFile, '>');
end;

procedure TPCEmitter.DoWriteArrayType(const AFile: TPCOutFile; const AType: TPCArrayType);
var
  LCount: string;
begin
  if AType.IsDynamic then
  begin
    DoText(AFile, 'std::vector<');
    DoWriteType(AFile, AType.ElementType);
    DoText(AFile, '>');
    Exit;
  end;
  if (AType.LowExpr = nil) or (AType.HighExpr = nil) then
    DoMissing(AFile, 'array bound');
  // ::pcpp::Array<T, N> (PLAN-RECORDS A8b, F-A8a: plain data holding a C
  // array, indexed with the built-in [], DoWriteIndex): N folded by SEM,
  // else computed by clang from the bounds as written
  DoText(AFile, '::pcpp::Array<');
  DoWriteType(AFile, AType.ElementType);
  DoText(AFile, ', ');
  if DoFoldedCount(AType.LowExpr, AType.HighExpr, LCount) then
    DoText(AFile, LCount)
  else
  begin
    DoText(AFile, '((');
    DoWriteExpr(AFile, AType.HighExpr);
    DoText(AFile, ') - (');
    DoWriteExpr(AFile, AType.LowExpr);
    DoText(AFile, ') + 1)');
  end;
  DoText(AFile, '>');
end;

procedure TPCEmitter.DoWriteSetType(const AFile: TPCOutFile; const AType: TPCSetType);
begin
  // ::pcpp::Set<T, LOW, HIGH>; LOW / HIGH are SEM's (A2b) when it knows them
  DoText(AFile, '::pcpp::Set<');
  if not AType.IsRangeForm then
  begin
    // An element form always has PaskalCPP bounds (choices, bool, char)
    if not AType.HasResolvedBounds then
      DoNoRule(AType);
    DoWriteType(AFile, AType.ElementType);
  end
  else
  begin
    if (AType.LowExpr = nil) or (AType.HighExpr = nil) then
      DoMissing(AFile, 'set bound');
    // The member type: the low bound's PaskalCPP type, else C++'s
    if DoIsNamedPaskalType(AType.LowExpr.ResolvedType) then
      DoText(AFile, DoTypeName(AType.LowExpr.ResolvedType))
    else
    begin
      DoText(AFile, 'std::decay_t<decltype((');
      DoWriteExpr(AFile, AType.LowExpr);
      DoText(AFile, '))>');
    end;
  end;
  DoText(AFile, ', ');
  if AType.HasResolvedBounds then
    DoText(AFile, IntToStr(AType.ResolvedLow) + ', ' + IntToStr(AType.ResolvedHigh))
  else
  begin
    DoWriteBound(AFile, AType.LowExpr);
    DoText(AFile, ', ');
    DoWriteBound(AFile, AType.HighExpr);
  end;
  DoText(AFile, '>');
end;

procedure TPCEmitter.DoWriteRoutineType(const AFile: TPCOutFile; const AType: TPCRoutineType);
begin
  // std::add_pointer_t<R(params)>; the parameter names are dropped
  DoText(AFile, 'std::add_pointer_t<');
  if AType.ReturnType = nil then
    DoText(AFile, 'void')
  else
    DoWriteType(AFile, AType.ReturnType);
  DoText(AFile, '(');
  DoWriteParams(AFile, AType.Params, AType.IsVariadic, AType.Linkage, False);
  DoText(AFile, ')>');
end;

procedure TPCEmitter.DoWriteParam(const AFile: TPCOutFile; const AParam: TPCParam; const AWithName: Boolean);
var
  LMark: TPCWriterMark;
begin
  // E10: var T&; const: a scalar / pointer by value, anything else by const
  // reference. const follows the type (east const): a pointer parameter is
  // char* const, never const char*
  DoAt(AFile, AParam.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  if AParam.TypeExpr = nil then
    DoMissing(AFile, 'parameter type');
  DoWriteType(AFile, AParam.TypeExpr);
  case AParam.ParamMode of
    pmVar:
      DoText(AFile, '&');
    pmConst:
      begin
        if AParam.TypeExpr.IsScalarOrPointer() then
          DoText(AFile, ' const')
        else
          DoText(AFile, ' const&');
      end;
  end;
  if AWithName then
    DoText(AFile, ' ' + AParam.ParamName);
  FWriters[AFile].CloseSpan(LMark, AParam);
end;

procedure TPCEmitter.DoWriteParams(const AFile: TPCOutFile; const AParams: TList<TPCParam>;
  const AIsVariadic: Boolean; const ALinkage: TPCLinkage; const AWithNames: Boolean);
var
  LIndex: Integer;
begin
  // The parameter list; a C linkage variadic ends in C's '...', any other
  // in the typed pack (O-V1), named pcpp_va in a routine
  for LIndex := 0 to AParams.Count - 1 do
  begin
    if LIndex > 0 then
      DoText(AFile, ', ');
    DoWriteParam(AFile, AParams[LIndex], AWithNames);
  end;
  if not AIsVariadic then
    Exit;
  if AParams.Count > 0 then
    DoText(AFile, ', ');
  if ALinkage = lnC then
    DoText(AFile, '...')
  else if AWithNames then
    DoText(AFile, '::pcpp::VarArgs ' + PC_EMT_VARARGS_NAME)
  else
    DoText(AFile, '::pcpp::VarArgs');
end;

class function TPCEmitter.DoIsDllExport(const ADecl: TPCDecl): Boolean;
begin
  // An exported module-level declaration of a dll module
  Result := ADecl.IsExported and (ADecl.DeclModule <> nil) and (ADecl.DeclModule.ModuleKind = mkDll);
end;

class function TPCEmitter.DoHasMethods(const ADecl: TPCTypeDecl): Boolean;
var
  LMember: TPCMemberItem;
begin
  // An object type with at least one method (an init, a done): its
  // definitions are a source part
  Result := False;
  if ADecl.IsForward or not (ADecl.TypeDef is TPCRecordType) then
    Exit;
  for LMember in TPCRecordType(ADecl.TypeDef).Members do
  begin
    // PLAN-OBJECT O9: a property's accessors are defined there too
    if (LMember is TPCRoutineMember) or (LMember is TPCPropertyItem) then
      Exit(True);
  end;
end;

procedure TPCEmitter.DoWriteSignature(const AFile: TPCOutFile; const ARoutine: TPCRoutine; const AStatic: Boolean;
  const AOwner: string);
begin
  // [extern "C" ][PCPP_EXPORT ][static ]R [Owner::]N(params). extern "C" by
  // DoHasCLinkage (the one linkage rule). PCPP_EXPORT after it: a linkage
  // spec starts its declaration
  if DoHasCLinkage(ARoutine, AStatic, AOwner) then
    DoText(AFile, 'extern "C" ');
  if (AOwner = '') and DoIsDllExport(ARoutine) then
    DoText(AFile, 'PCPP_EXPORT ');
  if AStatic then
    DoText(AFile, 'static ');
  if ARoutine.ReturnType = nil then
    DoText(AFile, 'void')
  else
    DoWriteType(AFile, ARoutine.ReturnType);
  DoText(AFile, ' ');
  if AOwner <> '' then
    DoText(AFile, AOwner + '::');
  DoText(AFile, ARoutine.DeclName + '(');
  DoWriteParams(AFile, ARoutine.Params, ARoutine.IsVariadic, ARoutine.ResolvedLinkage, True);
  DoText(AFile, ')');
  // O13b (3): a const method is a C++ const member function (declaration,
  // definition and a forwarding override alike: all write it here)
  if ARoutine.IsConst then
    DoText(AFile, ' const');
end;

procedure TPCEmitter.DoEmitRoutineBody(const ARoutine: TPCRoutine);
var
  LSaved: TPCRoutine;
begin
  // '{' ends the signature's last line; a C linkage variadic opens its
  // va_list there and closes it on every exit (H5); the local blocks in
  // place, the body's begin writes nothing, '}' on the routine's last line
  DoEnterBody(ARoutine, LSaved);
  DoText(ofSource, ' {');
  // PLAN-OBJECT O5: a done does not run on an object that moved out
  // (::pcpp::Live; its members still end as C++ ends them)
  if ARoutine.RoutineKind = rnDone then
    DoText(ofSource, ' if (!this->' + PC_EMT_LIVE_MEMBER + ') return;');
  if ARoutine.IsVariadic and (ARoutine.ResolvedLinkage = lnC) then
  begin
    if ARoutine.Params.Count = 0 then
      DoMissing(ofSource, 'fixed parameter before ...');
    DoText(ofSource, ' std::va_list ' + PC_EMT_VARARGS_NAME + '; va_start(' + PC_EMT_VARARGS_NAME + ', ' +
      ARoutine.Params[ARoutine.Params.Count - 1].ParamName + '); ::pcpp::Finally pcpp_va_end([&]() { va_end(' +
      PC_EMT_VARARGS_NAME + '); });');
  end;
  DoEmitStmts(ARoutine.Decls);
  if ARoutine.Body <> nil then
    DoEmitStmts(ARoutine.Body.Stmts);
  DoPutClose(ARoutine.Range.EndLine, '}');
  DoLeaveBody(LSaved);
end;

procedure TPCEmitter.DoEmitRoutine(const AFile: TPCOutFile; const ARoutine: TPCRoutine);
var
  LMark: TPCWriterMark;
begin
  // A6, module level. A forward is a static prototype in the source (an
  // exported routine's header prototype already precedes every use); an
  // external one binds its symbol by name; an exported one has its
  // prototype in the header; a definition is static unless exported
  if ARoutine.ExternalClause.IsExternal or ARoutine.IsForward or (AFile = ofHeader) then
  begin
    DoBeginItem(AFile, ARoutine.Range.StartLine);
    LMark := FWriters[AFile].Mark();
    DoWriteSignature(AFile, ARoutine, ARoutine.IsForward, '');
    if ARoutine.ExternalClause.IsExternal then
      DoText(AFile, ' __asm__("' + ARoutine.DeclName + '");')
    else
      DoText(AFile, ';');
    FWriters[AFile].CloseSpan(LMark, ARoutine);
    Exit;
  end;
  DoHoistLocalChoices(ARoutine, ARoutine.Range.StartLine);
  DoBeginItem(ofSource, ARoutine.Range.StartLine);
  LMark := FWriters[ofSource].Mark();
  DoWriteSignature(ofSource, ARoutine, DoIsStaticDefinition(ARoutine), '');
  DoEmitRoutineBody(ARoutine);
  FWriters[ofSource].CloseSpan(LMark, ARoutine);
end;

procedure TPCEmitter.DoEmitVar(const AFile: TPCOutFile; const AVar: TPCVarDecl; const AModuleLevel: Boolean);
var
  LMark: TPCWriterMark;
  LListMark: TPCWriterMark;
begin
  // A6: T N{}; / T N = (init); (static when private at module level). An
  // exported one is declared extern in the header; an external one binds
  // its C symbol by name and has no definition
  DoBeginItem(AFile, AVar.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  if AVar.ExternalClause.IsExternal then
  begin
    DoText(AFile, 'extern "C" ');
    DoWriteType(AFile, AVar.TypeExpr);
    DoText(AFile, ' ' + AVar.DeclName + ' __asm__("' + AVar.DeclName + '");');
  end
  else if AModuleLevel and (AFile = ofHeader) then
  begin
    if DoIsDllExport(AVar) then
      DoText(AFile, 'PCPP_EXPORT ');
    DoText(AFile, 'extern ');
    DoWriteType(AFile, AVar.TypeExpr);
    DoText(AFile, ' ' + AVar.DeclName + ';');
  end
  else
  begin
    if AModuleLevel and (not AVar.IsExported) then
      DoText(AFile, 'static ');
    DoWriteType(AFile, AVar.TypeExpr);
    DoText(AFile, ' ' + AVar.DeclName);
    if AVar.InitExpr <> nil then
    begin
      DoText(AFile, ' = (');
      DoWriteExpr(AFile, AVar.InitExpr);
      DoText(AFile, ');');
    end
    else if (AVar.InitCall <> nil) and (AVar.InitCall.Args.Count > 0) then
    begin
      // PLAN-OBJECT D3 / Q1: `LV: TFoo(1, 2);` = T N(T::pcpp_init_<n>{}, args);
      // a C/C++ type's list goes to its constructor as written, T N(args)
      // (SEM picked no init: DoWriteInitArgs writes no tag); the list's own
      // span covers it (an error there maps to the list)
      DoText(AFile, '(');
      LListMark := FWriters[AFile].Mark();
      DoWriteInitArgs(AFile, AVar.TypeExpr, AVar.InitCall);
      FWriters[AFile].CloseSpan(LListMark, AVar.InitCall);
      DoText(AFile, ');');
    end
    else
      // No list, `()`, an init without parameters or no init: value-init
      // (an object's init without parameters is its default constructor)
      DoText(AFile, '{};');
  end;
  FWriters[AFile].CloseSpan(LMark, AVar);
end;

procedure TPCEmitter.DoEmitConst(const AFile: TPCOutFile; const AConst: TPCConstDecl; const AModuleLevel: Boolean);
var
  LMark: TPCWriterMark;
begin
  // A6: constexpr T N = (v); const for a type holding a string or a dynamic
  // array (no constexpr std::string object); an exported one lives in the
  // header only, inline (one object for every module)
  DoBeginItem(AFile, AConst.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  if AModuleLevel and (AFile = ofHeader) then
    DoText(AFile, 'inline ');
  if AConst.TypeExpr = nil then
    DoMissing(AFile, 'const type');
  if AConst.TypeExpr.HoldsStringOrDynamicArray() then
    DoText(AFile, 'const ')
  else
    DoText(AFile, 'constexpr ');
  DoWriteType(AFile, AConst.TypeExpr);
  DoText(AFile, ' ' + AConst.DeclName + ' = (');
  DoWriteExpr(AFile, AConst.ValueExpr);
  DoText(AFile, ');');
  FWriters[AFile].CloseSpan(LMark, AConst);
end;

procedure TPCEmitter.DoEmitMethodItem(const AFile: TPCOutFile; const AItem: TPCMethodItem; const AInClass: Boolean);
var
  LMark: TPCWriterMark;
begin
  // H4: an object in the header declares its methods in the struct (defined
  // in the source); one written in the source (local, or placed there, E5)
  // defines them in the class, in place
  if AItem.Routine = nil then
    DoMissing(AFile, 'method');
  DoBeginItem(AFile, AItem.Routine.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  // PLAN-OBJECT D7: the dispatch words exist only in the class (C++ takes
  // virtual / override / final / = 0 on the declaration alone)
  if AItem.IsVirtual then
    DoText(AFile, 'virtual ');
  DoWriteSignature(AFile, AItem.Routine, False, '');
  // O7: a virtual method that implements an interface's overrides it in C++
  if AItem.IsOverride or (AItem.ResolvedImplements <> nil) then
    DoText(AFile, ' override');
  if AItem.IsFinal then
    DoText(AFile, ' final');
  if AItem.IsAbstract then
    DoText(AFile, ' = 0;')
  else if AInClass then
    DoEmitRoutineBody(AItem.Routine)
  else
    DoText(AFile, ';');
  FWriters[AFile].CloseSpan(LMark, AItem.Routine);
end;

class function TPCEmitter.DoInitTagName(const ARecord: TPCRecordType; const AInit: TPCInitItem): string;
var
  LMember: TPCMemberItem;
  LIndex: Integer;
begin
  // PLAN-OBJECT D3 (PC_EMT_INIT_TAG): the tag of an init with parameters,
  // pcpp_init_<its place among the type's inits>; '' = not one of them
  Result := '';
  LIndex := 0;
  if ARecord = nil then
    Exit;
  for LMember in ARecord.Members do
  begin
    // O5: a copy is no init (it takes no tag)
    if not (LMember is TPCInitItem) or (LMember is TPCCopyItem) then
      Continue;
    Inc(LIndex);
    if LMember = AInit then
      Exit(PC_EMT_INIT_TAG + IntToStr(LIndex));
  end;
end;

class function TPCEmitter.DoHasInits(const ARecord: TPCRecordType): Boolean;
var
  LMember: TPCMemberItem;
begin
  // The object declares an init (a copy is none): C++ then has no implicit
  // default constructor to lose (O5's synthesized members keep it otherwise)
  Result := False;
  for LMember in ARecord.Members do
  begin
    if (LMember is TPCInitItem) and not (LMember is TPCCopyItem) then
      Exit(True);
  end;
end;

class function TPCEmitter.DoHasDone(const ARecord: TPCRecordType): Boolean;
var
  LMember: TPCMemberItem;
begin
  // The object declares its done (it takes over the root's virtual
  // destructor, D7)
  Result := False;
  for LMember in ARecord.Members do
  begin
    if LMember is TPCDoneItem then
      Exit(True);
  end;
end;

procedure TPCEmitter.DoWriteInitHead(const AFile: TPCOutFile; const AItem: TPCInitItem; const AOwner: string);
var
  LTag: string;
begin
  // PLAN-OBJECT D3: `T()` for an init without parameters (C++'s default
  // constructor: what builds a value with no arguments); otherwise its tag
  // type in the class and `explicit T(pcpp_init_<n>, params)` (no implicit
  // conversion), out of the class `T::T(pcpp_init_<n>, params)`. O5: a copy
  // is C++'s copy constructor `T(T const& ASource)`, untagged and not
  // explicit (C++ copies through it)
  if AItem is TPCCopyItem then
  begin
    if AOwner <> '' then
      DoText(AFile, AOwner + '::');
    DoText(AFile, FRecordName + '(');
    DoWriteParams(AFile, AItem.Routine.Params, False, lnCpp, True);
    DoText(AFile, ')');
    Exit;
  end;
  LTag := '';
  if AItem.Routine.Params.Count > 0 then
  begin
    LTag := DoInitTagName(FRecord, AItem);
    if LTag = '' then
      DoMissing(AFile, 'init tag');
    if AOwner = '' then
      DoText(AFile, 'struct ' + LTag + ' {}; explicit ');
  end;
  if AOwner <> '' then
    DoText(AFile, AOwner + '::');
  DoText(AFile, FRecordName + '(');
  if AItem.Routine.Params.Count > 0 then
  begin
    DoText(AFile, LTag + ', ');
    DoWriteParams(AFile, AItem.Routine.Params, False, lnCpp, True);
  end;
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteDoneHead(const AFile: TPCOutFile; const AOwner: string);
begin
  // PLAN-OBJECT D3: `~T()`; the root of a polymorphic chain destroys
  // virtually (`virtual` in the class), every level below overrides it
  if AOwner <> '' then
  begin
    DoText(AFile, AOwner + '::~' + FRecordName + '()');
    Exit;
  end;
  if DoIsPolymorphicRoot(FRecord) then
    DoText(AFile, 'virtual ');
  DoText(AFile, '~' + FRecordName + '()');
  if FRecord.ResolvedIsPolymorphic and not DoIsPolymorphicRoot(FRecord) then
    DoText(AFile, ' override');
end;

procedure TPCEmitter.DoEmitInitItem(const AFile: TPCOutFile; const AItem: TPCInitItem; const AInClass: Boolean);
var
  LMark: TPCWriterMark;
begin
  // H4 as a method: declared in the struct (defined in the source), or
  // defined in the class for a type written in the source
  if (AItem.Routine = nil) or (FRecord = nil) or (FRecordName = '') then
    DoMissing(AFile, 'init');
  DoBeginItem(AFile, AItem.Routine.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  DoWriteInitHead(AFile, AItem, '');
  if AInClass then
    DoEmitInitBody(AItem)
  else
    DoText(AFile, ';');
  FWriters[AFile].CloseSpan(LMark, AItem.Routine);
  // O13 (D14): the plain constructor C++ code builds it with
  DoWritePlainInit(AFile, AItem);
end;

procedure TPCEmitter.DoWritePlainInit(const AFile: TPCOutFile; const AItem: TPCInitItem);
var
  LTag: string;
  LParam: TPCParam;
begin
  // PLAN-OBJECT O13 (D14): an init with parameters also gets a plain
  // `explicit T(params) : T(pcpp_init_<n>{}, args) {}` in the class, so C++
  // code builds the object (and a C++ class derived from it its base part)
  // without the hidden tag; C++ then ranks the inits by its own rules (SM0324
  // keeps their parameter types distinct). PaskalCPP code always names the
  // tag (DoWriteInitArgs), so SEM's pick stands. Not for a copy (already
  // C++'s copy constructor), an init without parameters (already T()), nor a
  // lone parameter of the object's own type (C++ reads that shape as a copy
  // constructor; the tagged init stays). Value parameters move on, as a
  // forwarding override's do. A borrowed spelling: the init keeps its spans
  if (AItem is TPCCopyItem) or (AItem.Routine.Params.Count = 0) then
    Exit;
  if AItem.Routine.Params.Count = 1 then
  begin
    LParam := AItem.Routine.Params[0];
    if (LParam.TypeExpr <> nil) and (LParam.TypeExpr.Canon() = FRecord) then
      Exit;
  end;
  LTag := DoInitTagName(FRecord, AItem);
  if LTag = '' then
    DoMissing(AFile, 'init tag');
  DoText(AFile, ' explicit ' + FRecordName + '(');
  FWriters[AFile].BeginBorrowed();
  try
    DoWriteParams(AFile, AItem.Routine.Params, False, lnCpp, True);
  finally
    FWriters[AFile].EndBorrowed();
  end;
  DoText(AFile, ') : ' + FRecordName + '(' + LTag + '{}, ' + DoForwardArgs(AItem.Routine) + ') {}');
end;

procedure TPCEmitter.DoEmitDoneItem(const AFile: TPCOutFile; const AItem: TPCDoneItem; const AInClass: Boolean);
var
  LMark: TPCWriterMark;
begin
  // H4 as a method (DoEmitInitItem)
  if (AItem.Routine = nil) or (FRecord = nil) or (FRecordName = '') then
    DoMissing(AFile, 'done');
  DoBeginItem(AFile, AItem.Routine.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  DoWriteDoneHead(AFile, '');
  if AInClass then
    DoEmitRoutineBody(AItem.Routine)
  else
    DoText(AFile, ';');
  FWriters[AFile].CloseSpan(LMark, AItem.Routine);
end;

procedure TPCEmitter.DoEmitInitBody(const AItem: TPCInitItem);
var
  LRoutine: TPCRoutine;
  LSaved: TPCRoutine;
  LIndex: Integer;
  LFirstLocal: UInt64;
  LParentCopy: Boolean;
begin
  // PLAN-OBJECT D3: the constructor's member-init list and body. The leading
  // init calls (TPCInitItem.ResolvedLeadCount) are its member initializers,
  // each on its own line, then '{'. The locals come from lines before the
  // leading calls: the writer returns to the first of them
  // (TPCCppWriter.ReturnToSourceLine; a line that holds text already resumes
  // past it), so every node keeps its own .pcpp line. Then the rest of the
  // body; '}' on the init's last line
  LRoutine := AItem.Routine;
  DoEnterBody(LRoutine, LSaved);
  if (LRoutine.Body <> nil) and (AItem.ResolvedLeadCount > LRoutine.Body.Stmts.Count) then
    DoMissing(ofSource, 'leading init call');
  // O5: a copy copies its parent part first, by the parent's copy (`:
  // Base(ASource)`, on the copy's line: its head's construct; the type is
  // borrowed, the struct line owns its span), then its leading calls
  LParentCopy := (AItem is TPCCopyItem) and (FRecord <> nil) and (FRecord.ParentName <> nil);
  if LParentCopy then
  begin
    if LRoutine.Params.Count <> 1 then
      DoMissing(ofSource, 'copy source');
    DoText(ofSource, ' : ');
    DoWriteBorrowedType(ofSource, FRecord.ParentName);
    DoText(ofSource, '(' + LRoutine.Params[0].ParamName + ')');
  end;
  for LIndex := 0 to AItem.ResolvedLeadCount - 1 do
  begin
    if not (LRoutine.Body.Stmts[LIndex] is TPCExprStmt) or
      not (TPCExprStmt(LRoutine.Body.Stmts[LIndex]).Expr is TPCCall) then
      DoMissing(ofSource, 'leading init call');
    DoWriteLeadInit(TPCCall(TPCExprStmt(LRoutine.Body.Stmts[LIndex]).Expr), (LIndex = 0) and not LParentCopy);
  end;
  DoText(ofSource, ' {');
  if (AItem.ResolvedLeadCount > 0) and (LRoutine.Decls.Count > 0) then
  begin
    LFirstLocal := LRoutine.Decls[0].Range.StartLine;
    if (LFirstLocal > 0) and (LFirstLocal < FWriters[ofSource].SourceLine()) then
      FWriters[ofSource].ReturnToSourceLine(LFirstLocal);
  end;
  DoEmitStmts(LRoutine.Decls);
  if LRoutine.Body <> nil then
  begin
    for LIndex := AItem.ResolvedLeadCount to LRoutine.Body.Stmts.Count - 1 do
      DoEmitStmt(LRoutine.Body.Stmts[LIndex]);
  end;
  DoPutClose(LRoutine.Range.EndLine, '}');
  DoLeaveBody(LSaved);
end;

procedure TPCEmitter.DoWriteLeadInit(const ACall: TPCCall; const AFirst: Boolean);
var
  LMark: TPCWriterMark;
  LPartType: TPCTypeExpr;
begin
  // `: Part(args)` / `, Part(args)` on the call's own line: the parent class
  // (its type, borrowed: the struct line owns its span) or the field's name
  // (TPCCall.ResolvedInitField); the arguments as DoWriteInitArgs
  DoBeginItem(ofSource, ACall.Range.StartLine);
  if AFirst then
    DoText(ofSource, ': ')
  else
    DoText(ofSource, ', ');
  LMark := FWriters[ofSource].Mark();
  if ACall.ResolvedInitField = nil then
  begin
    if (FRecord = nil) or (FRecord.ParentName = nil) then
      DoMissing(ofSource, 'parent of parent.init');
    LPartType := FRecord.ParentName;
    DoWriteBorrowedType(ofSource, LPartType);
  end
  else
  begin
    LPartType := ACall.ResolvedInitField.TypeExpr;
    DoText(ofSource, ACall.ResolvedInitField.FieldName);
  end;
  DoText(ofSource, '(');
  DoWriteInitArgs(ofSource, LPartType, ACall);
  DoText(ofSource, ')');
  FWriters[ofSource].CloseSpan(LMark, ACall);
end;

procedure TPCEmitter.DoWriteInitArgs(const AFile: TPCOutFile; const AType: TPCTypeExpr; const ACall: TPCCall);
var
  LCanon: TPCTypeExpr;
begin
  // The arguments of a construction or a leading init call, after the tag
  // of the init SEM picked (TPCCall.ResolvedInit) when it takes parameters:
  // `Type::pcpp_init_<n>{}, args` (the type borrowed: its node is written
  // elsewhere); no tag for an init without parameters or a type with no init
  if (ACall.ResolvedInit <> nil) and (ACall.ResolvedInit.Routine <> nil) and
    (ACall.ResolvedInit.Routine.Params.Count > 0) then
  begin
    LCanon := AType.Canon();
    if not (LCanon is TPCRecordType) then
      DoMissing(AFile, 'init owner');
    DoWriteBorrowedType(AFile, AType);
    DoText(AFile, '::' + DoInitTagName(TPCRecordType(LCanon), ACall.ResolvedInit) + '{}');
    if ACall.Args.Count > 0 then
      DoText(AFile, ', ');
  end;
  if ACall.Args.Count > 0 then
    DoWriteArgs(AFile, ACall.Args, 0, ACall.Args.Count - 1);
end;

procedure TPCEmitter.DoEmitMethodDefs(const ADecl: TPCTypeDecl);
var
  LMember: TPCMemberItem;
  LRoutine: TPCRoutine;
  LMark: TPCWriterMark;
  LSavedRecord: TPCRecordType;
  LSavedName: string;
begin
  // H4: R T::Meth(params) { ... } on each method's lines, in the run;
  // parent.M names this record's parent in them (H6)
  LSavedRecord := FRecord;
  LSavedName := FRecordName;
  FRecord := TPCRecordType(ADecl.TypeDef);
  FRecordName := ADecl.DeclName;
  for LMember in TPCRecordType(ADecl.TypeDef).Members do
  begin
    // PLAN-OBJECT D3: T::T(...) : member inits { ... } / T::~T() { ... }
    if (LMember is TPCInitItem) or (LMember is TPCDoneItem) then
    begin
      LRoutine := TPCRoutineMember(LMember).Routine;
      if LRoutine = nil then
        DoMissing(ofSource, 'init / done');
      DoBeginItem(ofSource, LRoutine.Range.StartLine);
      LMark := FWriters[ofSource].Mark();
      if LMember is TPCInitItem then
      begin
        DoWriteInitHead(ofSource, TPCInitItem(LMember), ADecl.DeclName);
        DoEmitInitBody(TPCInitItem(LMember));
      end
      else
      begin
        DoWriteDoneHead(ofSource, ADecl.DeclName);
        DoEmitRoutineBody(LRoutine);
      end;
      FWriters[ofSource].CloseSpan(LMark, LRoutine);
      Continue;
    end;
    // PLAN-OBJECT O9: R T::pcpp_get_X() const { ... } / void T::pcpp_set_X(...)
    if LMember is TPCPropertyItem then
    begin
      DoEmitAccessorDef(TPCPropertyItem(LMember), TPCPropertyItem(LMember).ReadItem, ADecl.DeclName);
      DoEmitAccessorDef(TPCPropertyItem(LMember), TPCPropertyItem(LMember).WriteItem, ADecl.DeclName);
      Continue;
    end;
    // PLAN-OBJECT O11: R T::pcpp_op_<name>(params) { ... }
    if LMember is TPCOperatorItem then
    begin
      LRoutine := TPCOperatorItem(LMember).Routine;
      if LRoutine = nil then
        DoMissing(ofSource, 'operator');
      DoBeginItem(ofSource, LRoutine.Range.StartLine);
      LMark := FWriters[ofSource].Mark();
      DoWriteOperatorHead(ofSource, TPCOperatorItem(LMember), ADecl.DeclName);
      DoEmitRoutineBody(LRoutine);
      FWriters[ofSource].CloseSpan(LMark, LRoutine);
      Continue;
    end;
    // An abstract method has no body to define (PLAN-OBJECT D7)
    if not (LMember is TPCMethodItem) or TPCMethodItem(LMember).IsAbstract then
      Continue;
    LRoutine := TPCMethodItem(LMember).Routine;
    if LRoutine = nil then
      DoMissing(ofSource, 'method');
    DoBeginItem(ofSource, LRoutine.Range.StartLine);
    LMark := FWriters[ofSource].Mark();
    DoWriteSignature(ofSource, LRoutine, False, ADecl.DeclName);
    DoEmitRoutineBody(LRoutine);
    FWriters[ofSource].CloseSpan(LMark, LRoutine);
  end;
  FRecord := LSavedRecord;
  FRecordName := LSavedName;
end;

class function TPCEmitter.DoOperatorName(const AItem: TPCOperatorItem): string;
begin
  // pcpp_op_<name>: one name per symbol (and the unary minus), so several
  // operators of one symbol are C++ overloads of one static member that the
  // call names with SEM's pick's exact parameter types (a static_cast)
  if AItem.IsUnary() then
    Exit(PC_EMT_OP_PREFIX + 'neg');
  case AItem.Op of
    boAdd:
      Result := 'add';
    boSub:
      Result := 'sub';
    boMul:
      Result := 'mul';
    boDiv:
      Result := 'div';
    boIntDiv:
      Result := 'intdiv';
    boMod:
      Result := 'mod';
    boEq:
      Result := 'eq';
    boNotEq:
      Result := 'ne';
    boLess:
      Result := 'lt';
    boLessEq:
      Result := 'le';
    boGreater:
      Result := 'gt';
    boGreaterEq:
      Result := 'ge';
    boIn:
      Result := 'in';
  else
    Result := 'unknown';
  end;
  Result := PC_EMT_OP_PREFIX + Result;
end;

procedure TPCEmitter.DoWriteOperatorHead(const AFile: TPCOutFile; const AItem: TPCOperatorItem; const AOwner: string);
begin
  // In the class `static R pcpp_op_<name>(params)`, out of it
  // `R T::pcpp_op_<name>(params)` (H4, as a method's signature)
  if AItem.Routine.ReturnType = nil then
    DoMissing(AFile, 'operator result');
  if AOwner = '' then
    DoText(AFile, 'static ');
  DoWriteType(AFile, AItem.Routine.ReturnType);
  DoText(AFile, ' ');
  if AOwner <> '' then
    DoText(AFile, AOwner + '::');
  DoText(AFile, DoOperatorName(AItem) + '(');
  DoWriteParams(AFile, AItem.Routine.Params, False, lnCpp, True);
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoEmitOperatorItem(const AFile: TPCOutFile; const AItem: TPCOperatorItem; const AInClass: Boolean);
var
  LMark: TPCWriterMark;
begin
  // H4 as a method: declared in the struct (defined in the source), or
  // defined in the class for a type written in the source
  if AItem.Routine = nil then
    DoMissing(AFile, 'operator');
  DoBeginItem(AFile, AItem.Routine.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  DoWriteOperatorHead(AFile, AItem, '');
  if AInClass then
    DoEmitRoutineBody(AItem.Routine)
  else
    DoText(AFile, ';');
  FWriters[AFile].CloseSpan(LMark, AItem.Routine);
end;

procedure TPCEmitter.DoWriteOperatorCall(const AFile: TPCOutFile; const AItem: TPCOperatorItem;
  const AOperands: array of TPCExpr);
var
  LIndex: Integer;
  LParam: TPCParam;
begin
  // (static_cast<R(*)(P...)>(&T::pcpp_op_<name>)((a), (b))): SEM's pick, by
  // the exact parameter types (several operators of one symbol are C++
  // overloads, as F18's ::pcpp::overloads members are named). T, R and P are
  // borrowed spellings (their nodes live in the type)
  if AItem.ResolvedOwner = nil then
    DoMissing(AFile, 'operator owner');
  FWriters[AFile].BeginBorrowed();
  try
    DoText(AFile, '(static_cast<std::add_pointer_t<');
    DoWriteType(AFile, AItem.Routine.ReturnType);
    DoText(AFile, '(');
    DoWriteParams(AFile, AItem.Routine.Params, False, lnCpp, False);
    DoText(AFile, ')>>(&');
    DoWriteType(AFile, AItem.ResolvedOwner);
    DoText(AFile, '::' + DoOperatorName(AItem) + ')(');
  finally
    FWriters[AFile].EndBorrowed();
  end;
  for LIndex := 0 to High(AOperands) do
  begin
    if LIndex > 0 then
      DoText(AFile, ', ');
    LParam := AItem.Routine.Params[LIndex];
    if LParam = nil then
      DoMissing(AFile, 'operator operand');
    DoWriteExpr(AFile, AOperands[LIndex]);
  end;
  DoText(AFile, '))');
end;

procedure TPCEmitter.DoWord(const AFile: TPCOutFile; const AText: string; var ASpace: Boolean);
begin
  // One word of a C++ type: a space before every word but the first
  if ASpace then
    DoText(AFile, ' ');
  DoText(AFile, AText);
  ASpace := True;
end;

procedure TPCEmitter.DoWriteCppType(const AFile: TPCOutFile; const AType: TPCCppType);
var
  LSpace: Boolean;
  LKind: TPCTokenKind;
  LIndex: Integer;
  LLevel: TPCCvFlags;
begin
  // As C++ spells it (BNF sec 4, the order of TPCCppType.TypeText): lead cv,
  // elaborated key, decltype head, fundamentals, name, trail cv, then the
  // pointer levels and the reference attached
  LSpace := False;
  if AType.LeadCv <> [] then
    DoWord(AFile, DoCvText(AType.LeadCv), LSpace);
  if AType.HasElaborated then
    DoWord(AFile, DoTokenText(AType.ElaboratedKey), LSpace);
  if AType.HasDecltype then
  begin
    // Decltype.Text is `decltype( ... )` as written, copied line for line
    if LSpace then
      DoText(AFile, ' ');
    FWriters[AFile].WriteVerbatim(AType.Decltype, nil);
    LSpace := True;
  end;
  for LKind in AType.Fundamentals do
    DoWord(AFile, DoTokenText(LKind), LSpace);
  if AType.NameParts.Count > 0 then
  begin
    if LSpace then
      DoText(AFile, ' ');
    if AType.HasLeadingScope then
      DoText(AFile, '::');
    for LIndex := 0 to AType.NameParts.Count - 1 do
    begin
      if LIndex > 0 then
        DoText(AFile, '::');
      DoWriteNamePart(AFile, AType.NameParts[LIndex]);
    end;
    LSpace := True;
  end;
  if AType.TrailCv <> [] then
    DoWord(AFile, DoCvText(AType.TrailCv), LSpace);
  for LLevel in AType.PointerLevels do
  begin
    DoText(AFile, '*');
    if LLevel <> [] then
      DoText(AFile, ' ' + DoCvText(LLevel));
  end;
  if AType.RefKind = rfLValue then
    DoText(AFile, '&')
  else if AType.RefKind = rfRValue then
    DoText(AFile, '&&');
end;

procedure TPCEmitter.DoWriteNamePart(const AFile: TPCOutFile; const APart: TPCNamePart);
var
  LMark: TPCWriterMark;
  LIndex: Integer;
begin
  // An identifier with its template args (an empty list stays `<>`); '>>'
  // closing two lists is C++23's own reading
  DoAt(AFile, APart.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  DoText(AFile, APart.PartText);
  if APart.HasTemplateArgs then
  begin
    DoText(AFile, '<');
    for LIndex := 0 to APart.TemplateArgs.Count - 1 do
    begin
      if LIndex > 0 then
        DoText(AFile, ', ');
      DoWriteTemplateArg(AFile, APart.TemplateArgs[LIndex]);
    end;
    DoText(AFile, '>');
  end;
  FWriters[AFile].CloseSpan(LMark, APart);
end;

procedure TPCEmitter.DoWriteTemplateArg(const AFile: TPCOutFile; const AArg: TPCTemplateArg);
var
  LMark: TPCWriterMark;
begin
  // A PaskalCPP type, an expression, or a cpp type id copied as written
  DoAt(AFile, AArg.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  if AArg.HasVerbatim then
    FWriters[AFile].WriteVerbatim(AArg.Verbatim, nil)
  else if AArg.TypeArg <> nil then
    DoWriteType(AFile, AArg.TypeArg)
  else if AArg.ExprArg <> nil then
    DoWriteExpr(AFile, AArg.ExprArg)
  else
    DoMissing(AFile, 'template argument');
  FWriters[AFile].CloseSpan(LMark, AArg);
end;

class function TPCEmitter.DoIsIntegerType(const AType: TPCTypeExpr): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // A PaskalCPP integer type (int8 .. uint64), from Resolved* fields only
  Result := False;
  if AType = nil then
    Exit;
  LCanon := AType.Canon();
  Result := (LCanon is TPCBuiltinType) and (TPCBuiltinType(LCanon).BuiltinToken in [tkKwInt8, tkKwInt16,
    tkKwInt32, tkKwInt64, tkKwUint8, tkKwUint16, tkKwUint32, tkKwUint64]);
end;

class function TPCEmitter.DoIsBoolType(const AType: TPCTypeExpr): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // PaskalCPP's bool, from Resolved* fields only
  Result := False;
  if AType = nil then
    Exit;
  LCanon := AType.Canon();
  Result := (LCanon is TPCBuiltinType) and (TPCBuiltinType(LCanon).BuiltinToken = tkKwBool);
end;

class function TPCEmitter.DoIsSetType(const AType: TPCTypeExpr): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // A PaskalCPP set: a declared set type or a set literal's dkSetOf
  Result := False;
  if AType = nil then
    Exit;
  LCanon := AType.Canon();
  Result := (LCanon is TPCSetType) or
    ((LCanon is TPCDerivedType) and (TPCDerivedType(LCanon).DerivedKind = dkSetOf));
end;

class function TPCEmitter.DoIsStringType(const AType: TPCTypeExpr): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // A string literal's type, string or wstring
  Result := False;
  if AType = nil then
    Exit;
  LCanon := AType.Canon();
  Result := (LCanon is TPCStringLiteralType) or
    ((LCanon is TPCBuiltinType) and (TPCBuiltinType(LCanon).BuiltinToken in [tkKwString, tkKwWstring]));
end;

class function TPCEmitter.DoIsPointerType(const AType: TPCTypeExpr): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // ptr, ptr to T, the type of @x
  Result := False;
  if AType = nil then
    Exit;
  LCanon := AType.Canon();
  Result := (LCanon is TPCPointerType) or
    ((LCanon is TPCBuiltinType) and (TPCBuiltinType(LCanon).BuiltinToken = tkKwPtr)) or
    ((LCanon is TPCDerivedType) and (TPCDerivedType(LCanon).DerivedKind = dkPointerTo));
end;

class function TPCEmitter.DoIsUntypedPointer(const AType: TPCTypeExpr): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // void* in C++: a bare ptr (nil is nullptr, not a pointer type)
  Result := False;
  if AType = nil then
    Exit;
  LCanon := AType.Canon();
  Result := ((LCanon is TPCPointerType) and (TPCPointerType(LCanon).TargetType = nil)) or
    ((LCanon is TPCBuiltinType) and (TPCBuiltinType(LCanon).BuiltinToken = tkKwPtr)) or
    ((LCanon is TPCDerivedType) and (TPCDerivedType(LCanon).DerivedKind = dkPointerTo) and
    (TPCDerivedType(LCanon).Target = nil));
end;

class function TPCEmitter.DoIsEnclosed(const AExpr: TPCExpr): Boolean;
begin
  // E18: the nodes whose own text is one parenthesized group; every other
  // operand is wrapped in ( ) by DoWriteOperand
  Result := (AExpr is TPCBinary) or (AExpr is TPCUnary) or (AExpr is TPCTernary) or (AExpr is TPCAssign) or
    (AExpr is TPCVerbatimExpr) or (AExpr is TPCNew) or
    ((AExpr is TPCCast) and (TPCCast(AExpr).CastKind = ckCStyle));
end;

class function TPCEmitter.DoBinaryOpText(const AOp: TPCBinaryOp; const AIsSet: Boolean): string;
begin
  // The C++ operator of a binary node written as (a OP b); div / mod / in
  // and real / have their own forms (DoWriteBinary). A set's + - * are
  // ::pcpp::Set's | - &
  case AOp of
    boLogOr:
      Result := '||';
    boLogAnd:
      Result := '&&';
    boEq:
      Result := '==';
    boNotEq:
      Result := '!=';
    boLess:
      Result := '<';
    boGreater:
      Result := '>';
    boLessEq:
      Result := '<=';
    boGreaterEq:
      Result := '>=';
    boThreeWay:
      Result := '<=>';
    boBitOr:
      Result := '|';
    boBitXor:
      Result := '^';
    boShl:
      Result := '<<';
    boShr:
      Result := '>>';
    boBitAnd:
      Result := '&';
    boDiv:
      Result := '/';
    boSub:
      Result := '-';
    boAdd:
      begin
        if AIsSet then
          Result := '|'
        else
          Result := '+';
      end;
    boMul:
      begin
        if AIsSet then
          Result := '&'
        else
          Result := '*';
      end;
  else
    Result := '';
  end;
end;

class function TPCEmitter.DoAssignOpText(const AOp: TPCAssignOp; const AIsSet: Boolean): string;
begin
  // := and the compound forms (%= is ::pcpp::ModAssign, DoWriteAssign). A
  // set's += -= *= are ::pcpp::Set's |= -= &= (as its + - * are | - &;
  // PLAN-RECORDS F-A8c)
  case AOp of
    aoAssign:
      Result := '=';
    aoAddAssign:
      begin
        if AIsSet then
          Result := '|='
        else
          Result := '+=';
      end;
    aoSubAssign:
      Result := '-=';
    aoMulAssign:
      begin
        if AIsSet then
          Result := '&='
        else
          Result := '*=';
      end;
    aoDivAssign:
      Result := '/=';
    aoBitAndAssign:
      Result := '&=';
    aoBitOrAssign:
      Result := '|=';
    aoShlAssign:
      Result := '<<=';
    aoShrAssign:
      Result := '>>=';
  else
    Result := '';
  end;
end;

class function TPCEmitter.DoFoldedText(const AExpr: TPCExpr; out AText: string): Boolean;
begin
  // An integer SEM folded, as a decimal: the AST's one rule (the header walk
  // and ModuleNamesRuntime read it too)
  Result := TPCAst.FoldedText(AExpr, AText);
end;

procedure TPCEmitter.DoWriteExpr(const AFile: TPCOutFile; const AExpr: TPCExpr);
begin
  DoWriteExprAs(AFile, AExpr, False);
end;

procedure TPCEmitter.DoWriteTypeConstant(const AFile: TPCOutFile; const AExpr: TPCExpr);
var
  LText: string;
  LMark: TPCWriterMark;
begin
  // A constant a type holds (align(n), a bitfield width): SEM's folded value,
  // as the array count and the set bounds are written, so a type (header)
  // never names a private const (source) (F22); a C/C++ constant SEM did not
  // fold is written as written (clang's)
  if not DoFoldedText(AExpr, LText) then
  begin
    DoWriteExpr(AFile, AExpr);
    Exit;
  end;
  DoAt(AFile, AExpr.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  DoText(AFile, LText);
  FWriters[AFile].CloseSpan(LMark, AExpr);
end;

procedure TPCEmitter.DoWriteExprAs(const AFile: TPCOutFile; const AExpr: TPCExpr; const AIsStmt: Boolean);
var
  LMark: TPCWriterMark;
  LChoiceRead: TPCField;
begin
  // A8: every expression node writes itself on its own line with a span on
  // itself (a composite span covers its children). AIsStmt: the expression
  // of an expression statement (an assignment there takes no outer ( ))
  if AExpr = nil then
    DoMissing(AFile, 'expression');
  DoAt(AFile, AExpr.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  // PLAN-OBJECT O13b: a rule that depends on a polymorphism only clang knows
  // (SEM's TPCExpr.ResolvedPolyCheck): `((void)[]{ static_assert(<test>,
  // "pcpp:poly"); }, (x))`, outermost in the expression's own span, so the
  // value is written once and keeps its value category; a failed check is
  // reported by the Compiler in SEM's words at this expression
  if AExpr.ResolvedPolyCheck <> pcNone then
  begin
    if AExpr.ResolvedPolyType = nil then
      DoMissing(AFile, 'polymorphism check type');
    if AExpr.ResolvedPolyCheck in [pcIsPolymorphic, pcOwnUpcast] then
      DoText(AFile, '((void)[]{ static_assert(std::is_polymorphic_v<')
    else
      DoText(AFile, '((void)[]{ static_assert(!std::is_polymorphic_v<');
    DoWriteBorrowedType(AFile, AExpr.ResolvedPolyType);
    DoText(AFile, '>, "' + PC_FRONTEND_CHECK_POLY + '"); }, ');
  end;
  // PLAN-RECORDS M12 (1): a pointer to an extension used as a pointer to a
  // level above it (SEM's TPCExpr.ResolvedUpcastHops; M10: no C++
  // inheritance relates them): ::pcpp::upcast<N>(x), nil-safe, x read once,
  // inside the expression's own span
  if AExpr.ResolvedUpcastHops > 0 then
    DoText(AFile, '::pcpp::upcast<' + IntToStr(AExpr.ResolvedUpcastHops) + '>(');
  // PLAN-RECORDS M8: a value that may sit misaligned, going where C++ binds
  // a reference (SEM's TPCExpr.ResolvedIsCopied): a C++23 decay copy, so the
  // reference binds an aligned temporary; innermost, inside the upcast
  if AExpr.ResolvedIsCopied then
    DoText(AFile, 'auto(');
  // PLAN-OBJECT O5: a returned local that cannot be copied is moved (SEM's
  // TPCExpr.ResolvedIsMoved), in every return form (a guard's result too)
  if AExpr.ResolvedIsMoved then
    DoText(AFile, 'std::move(');
  // F37: a choices bit field is stored as its underlying integer: a read is
  // the choices value again, innermost; the assignment target is a store
  // (DoWriteAssign casts the value instead)
  if AExpr = FStoreTarget then
    LChoiceRead := nil
  else
    LChoiceRead := DoChoicesBitField(AExpr);
  if LChoiceRead <> nil then
  begin
    DoText(AFile, 'static_cast<');
    DoWriteBorrowedType(AFile, LChoiceRead.TypeExpr);
    DoText(AFile, '>(');
  end;
  if AExpr is TPCName then
    DoWriteName(AFile, TPCName(AExpr))
  else if AExpr is TPCMember then
    DoWriteMember(AFile, TPCMember(AExpr))
  else if AExpr is TPCLiteral then
    DoWriteLiteral(AFile, TPCLiteral(AExpr))
  else if AExpr is TPCVerbatimExpr then
    DoWriteVerbatimExpr(AFile, TPCVerbatimExpr(AExpr))
  else if AExpr is TPCBinary then
    DoWriteBinary(AFile, TPCBinary(AExpr))
  else if AExpr is TPCUnary then
    DoWriteUnary(AFile, TPCUnary(AExpr))
  else if AExpr is TPCTernary then
    DoWriteTernary(AFile, TPCTernary(AExpr))
  else if AExpr is TPCAssign then
    DoWriteAssign(AFile, TPCAssign(AExpr), AIsStmt)
  else if AExpr is TPCCall then
    DoWriteCall(AFile, TPCCall(AExpr))
  else if AExpr is TPCIndex then
    DoWriteIndex(AFile, TPCIndex(AExpr))
  else if AExpr is TPCCast then
    DoWriteCast(AFile, TPCCast(AExpr))
  else if AExpr is TPCNew then
    DoWriteNew(AFile, TPCNew(AExpr))
  else if AExpr is TPCDelete then
    DoWriteDelete(AFile, TPCDelete(AExpr))
  else if AExpr is TPCOwnerNew then
    DoWriteOwnerNew(AFile, TPCOwnerNew(AExpr))
  else if AExpr is TPCTypeTest then
    DoWriteTypeTest(AFile, TPCTypeTest(AExpr))
  else if AExpr is TPCBracedInit then
    DoWriteBracedInit(AFile, TPCBracedInit(AExpr))
  else if AExpr is TPCSetLiteral then
    DoWriteSetLiteral(AFile, TPCSetLiteral(AExpr))
  else if AExpr is TPCRecordLiteral then
    DoWriteRecordLiteral(AFile, TPCRecordLiteral(AExpr))
  else if AExpr is TPCVarargs then
    DoWriteVarargs(AFile, TPCVarargs(AExpr))
  else if AExpr is TPCSpecial then
    DoWriteSpecial(AFile, TPCSpecial(AExpr))
  else
    DoNoRule(AExpr);
  if LChoiceRead <> nil then
    DoText(AFile, ')');
  if AExpr.ResolvedIsMoved then
    DoText(AFile, ')');
  if AExpr.ResolvedIsCopied then
    DoText(AFile, ')');
  if AExpr.ResolvedUpcastHops > 0 then
    DoText(AFile, ')');
  if AExpr.ResolvedPolyCheck <> pcNone then
    DoText(AFile, ')');
  FWriters[AFile].CloseSpan(LMark, AExpr);
end;

procedure TPCEmitter.DoWriteOperand(const AFile: TPCOutFile; const AExpr: TPCExpr);
begin
  // E18: an operand is one parenthesized group: a composite node is one
  // already, any other is wrapped (`- -x` -> (-(-(x))))
  if DoIsEnclosed(AExpr) then
    DoWriteExpr(AFile, AExpr)
  else
  begin
    DoText(AFile, '(');
    DoWriteExpr(AFile, AExpr);
    DoText(AFile, ')');
  end;
end;

procedure TPCEmitter.DoWriteBorrowedExpr(const AFile: TPCOutFile; const AExpr: TPCExpr);
begin
  // An expression written a second time (decltype of a VarStore argument,
  // an array's low bound in an index): the same text, no span
  FWriters[AFile].BeginBorrowed();
  try
    DoWriteOperand(AFile, AExpr);
  finally
    FWriters[AFile].EndBorrowed();
  end;
end;

procedure TPCEmitter.DoWriteLiteral(const AFile: TPCOutFile; const ALiteral: TPCLiteral);
var
  LIndex: Integer;
  LPart: TPCLiteralPart;
begin
  // CppText (F65: the parser's spelling for C++, E17, no O1 wrap); nil =
  // nullptr. A string on one line whose parts all keep their text is its
  // Text (the gaps between parts as written); otherwise each part on its own
  // line (one space between parts). A token that spans lines (a raw string,
  // a splice) is copied line for line with no #line on its later lines:
  // every one of them starts inside the token (R23)
  if ALiteral.LiteralKind = lkNil then
    DoText(AFile, 'nullptr')
  else if (ALiteral.LiteralKind = lkChar) and ALiteral.IsMultiChar and ALiteral.HasValue then
    // F66: a multi-char literal is its value, the int clang gives it (32 bits
    // kept, read as int), so clang never warns on it again (PR0064 did)
    DoText(AFile, 'static_cast<int>(' + UIntToStr(ALiteral.IntValue) + 'u)')
  else if ALiteral.LiteralKind <> lkString then
    DoWriteLiteralToken(AFile, ALiteral.CppText, ALiteral.Range, ALiteral)
  else if not (ALiteral.Text.Contains(#10) or ALiteral.Text.Contains(#13) or
    DoPartsRespelled(ALiteral)) then
    DoText(AFile, ALiteral.Text)
  else
  begin
    for LIndex := 0 to High(ALiteral.Parts) do
    begin
      LPart := ALiteral.Parts[LIndex];
      DoAt(AFile, LPart.Range.StartLine);
      if (LIndex > 0) and DoHasText(AFile) then
        DoText(AFile, ' ');
      DoWriteLiteralToken(AFile, LPart.CppText, LPart.Range, ALiteral);
    end;
  end;
end;

function TPCEmitter.DoLiteralCppText(const ALiteral: TPCLiteral): string;
var
  LIndex: Integer;
begin
  // A string literal's C++ text as one piece (a test's name in the
  // registration line): its Text, or its parts' CppText one space apart
  if not DoPartsRespelled(ALiteral) then
    Exit(ALiteral.Text);
  Result := '';
  for LIndex := 0 to High(ALiteral.Parts) do
  begin
    if LIndex > 0 then
      Result := Result + ' ';
    Result := Result + ALiteral.Parts[LIndex].CppText;
  end;
end;

function TPCEmitter.DoPartsRespelled(const ALiteral: TPCLiteral): Boolean;
var
  LIndex: Integer;
begin
  // A part whose C++ spelling differs from its text (F65): the literal is
  // written part by part
  for LIndex := 0 to High(ALiteral.Parts) do
  begin
    if ALiteral.Parts[LIndex].CppText <> ALiteral.Parts[LIndex].Text then
      Exit(True);
  end;
  Result := False;
end;

procedure TPCEmitter.DoWriteLiteralToken(const AFile: TPCOutFile; const AText: string;
  const ARange: TSourceRange; const ALiteral: TPCLiteral);
var
  LLine: Integer;
  LCount: Integer;
  LVerbatim: TPCVerbatim;
begin
  // One literal token's C++ text: on one line as text, over several lines
  // copied line for line (its later lines start inside the token, R23)
  if not (AText.Contains(#10) or AText.Contains(#13)) then
  begin
    DoText(AFile, AText);
    Exit;
  end;
  LVerbatim := Default(TPCVerbatim);
  LVerbatim.Text := AText;
  LVerbatim.Range := ARange;
  LVerbatim.VerbatimKind := vkCppExpr;
  LVerbatim.EmitTarget := etInPlace;
  LCount := Integer(ARange.EndLine - ARange.StartLine);
  SetLength(LVerbatim.InsideLines, LCount);
  for LLine := 1 to LCount do
    LVerbatim.InsideLines[LLine - 1] := ARange.StartLine + UInt64(LLine);
  FWriters[AFile].WriteVerbatim(LVerbatim, ALiteral);
end;

procedure TPCEmitter.DoWriteVerbatimExpr(const AFile: TPCOutFile; const AExpr: TPCVerbatimExpr);
begin
  // cpp("...") / an opaque group / a lambda: ( Text ). A multi-line Text (a
  // raw string) is copied line for line, a #line only before the first
  // (its later lines are InsideLines, R23). cpp("...") always goes through
  // WriteVerbatim: its value gets a span of its own, so a C++ location inside
  // the value maps back through TPCVerbatim.ValueMap (TPCAst.TranslateLocation)
  if (AExpr.Verbatim.VerbatimKind = vkCppExpr) or AExpr.Verbatim.Text.Contains(#10) or
    AExpr.Verbatim.Text.Contains(#13) then
  begin
    DoText(AFile, '(');
    FWriters[AFile].WriteVerbatim(AExpr.Verbatim, AExpr);
    DoText(AFile, ')');
  end
  else
    DoText(AFile, '(' + AExpr.Verbatim.Text + ')');
end;

procedure TPCEmitter.DoWriteName(const AFile: TPCOutFile; const AName: TPCName);
var
  LIndex: Integer;
  LMember: TPCRoutine;
begin
  // A declaration's name from the AST (H1, never the source text): module
  // level ::M::N (E19), local / param plain; an overload set by one of its
  // members (H2); a choice value <E>::<V>; a C/C++ name as written, its
  // template args included. A member is never a bare name (PLAN-OBJECT D9:
  // SEM reports it, SM0018): one resolved so is an invariant (DoNoRule)
  if (AName.ResolvedDecl is TPCField) or
    ((AName.ResolvedDecl is TPCRoutine) and (TPCRoutine(AName.ResolvedDecl).RoutineKind = rnMethod)) or
    ((AName.ResolvedSetMember <> nil) and (AName.ResolvedSetMember.RoutineKind = rnMethod)) then
    DoNoRule(AName)
  else if AName.ResolvedDecl is TPCDecl then
    DoText(AFile, DoDeclName(TPCDecl(AName.ResolvedDecl)))
  else if AName.ResolvedDecl is TPCParam then
    DoText(AFile, TPCParam(AName.ResolvedDecl).ParamName)
  else if AName.ResolvedKind = rkChoiceValue then
    DoWriteChoiceValue(AFile, AName.ResolvedDecl)
  else if (AName.ResolvedKind = rkRoutine) and (AName.ResolvedSetMember <> nil) then
  begin
    LMember := AName.ResolvedSetMember;
    DoText(AFile, DoDeclName(LMember));
  end
  else if AName.ResolvedKind = rkOpaque then
  begin
    if AName.HasLeadingScope then
      DoText(AFile, '::');
    for LIndex := 0 to AName.Parts.Count - 1 do
    begin
      if LIndex > 0 then
        DoText(AFile, '::');
      DoWriteNamePart(AFile, AName.Parts[LIndex]);
    end;
  end
  else
    DoNoRule(AName);
end;

procedure TPCEmitter.DoWriteMember(const AFile: TPCOutFile; const AMember: TPCMember);
var
  LBase: TPCExpr;
  LModuleName: string;
  LHop: Integer;
begin
  // M.N (a module member) -> ::M::N; E.V -> <E>::<V>; parent.M ->
  // <ParentType>::M (H6); else (b).m / (b)->m (C++ member lookup)
  LBase := AMember.Base;
  if LBase = nil then
    DoMissing(AFile, 'member base');
  // A varargs local's count -> (L).Count(); its call words are written by
  // DoWriteVarargsLocalCall (SEM reports one that is not called: SM0409)
  if AMember.ResolvedVarargs = vaCount then
  begin
    DoWriteOperand(AFile, LBase);
    if AMember.Access = maArrow then
      DoText(AFile, '->Count()')
    else
      DoText(AFile, '.Count()');
    Exit;
  end;
  if AMember.ResolvedVarargs <> vaPlain then
    DoNoRule(AMember);
  if AMember.ResolvedKind = rkChoiceValue then
    DoWriteChoiceValue(AFile, AMember.ResolvedDecl)
  else if (LBase is TPCName) and (TPCName(LBase).ResolvedKind = rkModule) then
  begin
    if AMember.ResolvedDecl is TPCDecl then
      DoText(AFile, DoDeclName(TPCDecl(AMember.ResolvedDecl)))
    else
    begin
      // An overload set or a C++ name of the module: ::M:: + the name
      if TPCName(LBase).ResolvedDecl is TPCImport then
        LModuleName := DoNamespaceName(TPCImport(TPCName(LBase).ResolvedDecl).ImportedModule)
      else if TPCName(LBase).ResolvedDecl is TPCModule then
        LModuleName := DoNamespaceName(TPCModule(TPCName(LBase).ResolvedDecl))
      else
      begin
        DoMissing(AFile, 'module');
        Exit;
      end;
      DoText(AFile, '::' + LModuleName + '::');
      DoWriteNamePart(AFile, AMember.Member);
    end;
  end
  else if (LBase is TPCSpecial) and (TPCSpecial(LBase).SpecialKind = skParent) then
  begin
    if (FRecord = nil) or (FRecord.ParentName = nil) then
      DoMissing(AFile, 'parent type');
    DoText(AFile, DoTypeName(FRecord.ParentName) + '::');
    // PLAN-OBJECT O8: parent.X of an embed's X = Parent::F.X
    if Length(AMember.ResolvedEmbedPath) > 0 then
    begin
      DoWriteEmbedPath(AFile, AMember);
      for LHop := 1 to AMember.ResolvedParentHops do
        DoText(AFile, PC_EMT_PARENT_MEMBER + '.');
    end;
    DoWriteMemberName(AFile, AMember);
  end
  else if TPCMember.ReadsOwner(AMember) then
  begin
    // PLAN-OBJECT O6 (Q2): `LO.X` on an own / ref reads its object, nil
    // raising (::pcpp::deref; C++ looks the member up)
    DoText(AFile, '::pcpp::deref(');
    DoWriteExpr(AFile, LBase);
    DoText(AFile, ').');
    DoWriteEmbedPath(AFile, AMember);
    for LHop := 1 to AMember.ResolvedParentHops do
      DoText(AFile, PC_EMT_PARENT_MEMBER + '.');
    DoWriteMemberName(AFile, AMember);
  end
  else
  begin
    DoWriteOperand(AFile, LBase);
    if AMember.Access = maArrow then
      DoText(AFile, '->')
    else
      DoText(AFile, '.');
    // PLAN-OBJECT O8: an embed's member through its embeds first
    DoWriteEmbedPath(AFile, AMember);
    // PLAN-RECORDS M10: an inherited member is reached through the parent
    // members SEM stepped through (TPCMember.ResolvedParentHops)
    for LHop := 1 to AMember.ResolvedParentHops do
      DoText(AFile, PC_EMT_PARENT_MEMBER + '.');
    DoWriteMemberName(AFile, AMember);
  end;
end;

procedure TPCEmitter.DoWriteMemberName(const AFile: TPCOutFile; const AMember: TPCMember);
begin
  // The member's name; a property's read is pcpp_get_X(), the target of its
  // write (DoWriteAssign: FSetterTarget) pcpp_set_X( with the value after it
  // (PLAN-OBJECT O9). The name keeps its span either way
  if AMember.ResolvedKind <> rkProperty then
  begin
    DoWriteNamePart(AFile, AMember.Member);
    Exit;
  end;
  if AMember = FSetterTarget then
  begin
    DoText(AFile, PC_EMT_PROP_SET);
    DoWriteNamePart(AFile, AMember.Member);
    DoText(AFile, '(');
    Exit;
  end;
  // O10: an indexed property's read, its index after the '('
  if AMember = FOpenGetTarget then
  begin
    DoText(AFile, PC_EMT_PROP_GET);
    DoWriteNamePart(AFile, AMember.Member);
    DoText(AFile, '(');
    Exit;
  end;
  DoText(AFile, PC_EMT_PROP_GET);
  DoWriteNamePart(AFile, AMember.Member);
  DoText(AFile, '()');
end;

procedure TPCEmitter.DoWriteBinary(const AFile: TPCOutFile; const ABinary: TPCBinary);
var
  LIsSet: Boolean;
begin
  // (a OP b); `e in S` -> ((S).contains((e))); div / mod -> the runtime's
  // truncating, zero-checked helpers; real / of two integers -> double; a
  // string literal on the left of + a string -> std::string("a")
  // PLAN-OBJECT O11: a declared operator is its type's static member
  if ABinary.ResolvedOperator <> nil then
  begin
    DoWriteOperatorCall(AFile, ABinary.ResolvedOperator, [ABinary.Left, ABinary.Right]);
    Exit;
  end;
  LIsSet := DoIsSetType(ABinary.Left.ResolvedType) or DoIsSetType(ABinary.Right.ResolvedType);
  DoText(AFile, '(');
  if ABinary.Op = boIn then
  begin
    DoWriteOperand(AFile, ABinary.Right);
    DoText(AFile, '.contains(');
    DoWriteOperand(AFile, ABinary.Left);
    DoText(AFile, '))');
    Exit;
  end;
  // PLAN-INTRINSICS I5: xor of two bools is logical and SEM typed the node
  // bool (DoBinaryType); C++'s ^ promotes both to int, so the result is cast
  // back: (static_cast<bool>((a) ^ (b))), a bool in C++ as in the AST. Not
  // written != : clang reads `X xor X` then as a self-comparison and warns in
  // words the person never wrote. An integer xor keeps plain ^
  if (ABinary.Op = boBitXor) and DoIsBoolType(ABinary.ResolvedType) then
  begin
    DoText(AFile, 'static_cast<bool>(');
    DoWriteOperand(AFile, ABinary.Left);
    DoText(AFile, ' ^ ');
    DoWriteOperand(AFile, ABinary.Right);
    DoText(AFile, '))');
    Exit;
  end;
  if (ABinary.Op = boIntDiv) or (ABinary.Op = boMod) then
  begin
    if ABinary.Op = boIntDiv then
      DoText(AFile, '::pcpp::Div(')
    else
      DoText(AFile, '::pcpp::Mod(');
    DoWriteOperand(AFile, ABinary.Left);
    DoText(AFile, ', ');
    DoWriteOperand(AFile, ABinary.Right);
    DoText(AFile, '))');
    Exit;
  end;

  if (ABinary.Op = boDiv) and DoIsIntegerType(ABinary.Left.ResolvedType) and
    DoIsIntegerType(ABinary.Right.ResolvedType) then
  begin
    DoText(AFile, 'static_cast<double>');
    DoWriteOperand(AFile, ABinary.Left);
  end
  else if (ABinary.Op = boAdd) and (ABinary.Left is TPCLiteral) and
    (TPCLiteral(ABinary.Left).LiteralKind = lkString) and DoIsStringType(ABinary.Right.ResolvedType) then
  begin
    if (ABinary.Left.ResolvedType is TPCStringLiteralType) and TPCStringLiteralType(ABinary.Left.ResolvedType).IsWide then
      DoText(AFile, 'std::wstring(')
    else
      DoText(AFile, 'std::string(');
    DoWriteExpr(AFile, ABinary.Left);
    DoText(AFile, ')');
  end
  else
    DoWriteOperand(AFile, ABinary.Left);
  DoText(AFile, ' ' + DoBinaryOpText(ABinary.Op, LIsSet) + ' ');
  DoWriteOperand(AFile, ABinary.Right);
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteUnary(const AFile: TPCOutFile; const AUnary: TPCUnary);
begin
  // (OP (x)) / ((x) OP) for the postfix ++ --; ^ and prefix * are (*(p)),
  // @ and prefix & (&(x))
  // PLAN-OBJECT O11: a declared unary minus is its type's static member
  if AUnary.ResolvedOperator <> nil then
  begin
    DoWriteOperatorCall(AFile, AUnary.ResolvedOperator, [AUnary.Operand]);
    Exit;
  end;
  DoText(AFile, '(');
  case AUnary.Op of
    uoLogNot:
      DoText(AFile, '!');
    uoBitNot:
      DoText(AFile, '~');
    uoNegate:
      DoText(AFile, '-');
    uoPlus:
      DoText(AFile, '+');
    uoAddressOf:
      DoText(AFile, '&');
    uoDeref:
      DoText(AFile, '*');
    uoPreInc:
      DoText(AFile, '++');
    uoPreDec:
      DoText(AFile, '--');
  end;
  DoWriteOperand(AFile, AUnary.Operand);
  if AUnary.Op = uoPostInc then
    DoText(AFile, '++')
  else if AUnary.Op = uoPostDec then
    DoText(AFile, '--');
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteTernary(const AFile: TPCOutFile; const ATernary: TPCTernary);
begin
  DoText(AFile, '(');
  DoWriteOperand(AFile, ATernary.Condition);
  DoText(AFile, ' ? ');
  DoWriteOperand(AFile, ATernary.ThenExpr);
  DoText(AFile, ' : ');
  DoWriteOperand(AFile, ATernary.ElseExpr);
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteAssign(const AFile: TPCOutFile; const AAssign: TPCAssign; const AIsStmt: Boolean);
var
  LField: TPCField;
  LSavedStore: TPCExpr;
begin
  // t = (v) as a statement, ((t) = (v)) inside an expression; %= is the
  // runtime's ModAssign (target evaluated once, zero-checked like mod).
  // PLAN-OBJECT O9: a property's write (a statement only: SM0377)
  if ((AAssign.Target is TPCMember) and (TPCMember(AAssign.Target).ResolvedKind = rkProperty)) or
    ((AAssign.Target is TPCIndex) and (TPCIndex(AAssign.Target).ResolvedProperty <> nil)) then
  begin
    if not AIsStmt then
      DoNoRule(AAssign);
    DoWritePropertyAssign(AFile, AAssign);
    Exit;
  end;
  if not AIsStmt then
    DoText(AFile, '(');
  if AAssign.Op = aoModAssign then
  begin
    DoText(AFile, '::pcpp::ModAssign(');
    DoWriteOperand(AFile, AAssign.Target);
    DoText(AFile, ', ');
    DoWriteOperand(AFile, AAssign.ValueExpr);
    DoText(AFile, ')');
  end
  else
  begin
    // F37: a choices bit field is stored as its underlying integer: the
    // target is a store (no read cast), the value is cast to the integer (a
    // choices value takes no compound assignment: SEM's F39)
    LField := DoChoicesBitField(AAssign.Target);
    LSavedStore := FStoreTarget;
    if LField <> nil then
      FStoreTarget := AAssign.Target;
    try
      if AIsStmt then
        DoWriteExpr(AFile, AAssign.Target)
      else
        DoWriteOperand(AFile, AAssign.Target);
    finally
      FStoreTarget := LSavedStore;
    end;
    DoText(AFile, ' ' + DoAssignOpText(AAssign.Op, DoIsSetType(AAssign.Target.ResolvedType)) + ' ');
    if LField <> nil then
      DoWriteChoicesStore(AFile, LField, AAssign.ValueExpr)
    else
      DoWriteOperand(AFile, AAssign.ValueExpr);
  end;
  if not AIsStmt then
    DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteChoicesStore(const AFile: TPCOutFile; const AField: TPCField; const AValue: TPCExpr);
begin
  // F37: a value stored into a choices bit field, as its underlying integer:
  // static_cast<std::int32_t>((v)) (the type's DoChoicesUnderlying)
  DoText(AFile, 'static_cast<' + DoChoicesUnderlying(TPCChoicesType(AField.TypeExpr.Canon())) + '>(');
  DoWriteOperand(AFile, AValue);
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWritePropertyAssign(const AFile: TPCOutFile; const AAssign: TPCAssign);
var
  LMember: TPCMember;
  LIndex: TPCIndex;
  LProperty: TPCPropertyItem;
  LObject: string;
  LName: string;
  LQualifier: string;
  LIndexArg: string;
begin
  // PLAN-OBJECT O9 / O10 (D12). The target is a property member (`LO.X`), an
  // indexed property (`LO.Items[i]`, its base the member) or a default
  // property (`LO[i]`). `X := v` is (o).pcpp_set_X([i, ]v): C++17 evaluates
  // the object, then the arguments in order (the index before the value).
  // `X OP= v` takes the object once, then the index, the value, the current
  // value, the write (the order D12 defines):
  //   [&](auto&& pcpp_po) { [auto&& pcpp_pi = (i); ]auto&& pcpp_pv = (v);
  //   auto pcpp_pc = pcpp_po.Q pcpp_get_X([pcpp_pi]); pcpp_pc OP pcpp_pv;
  //   pcpp_po.Q pcpp_set_X([pcpp_pi, ]std::move(pcpp_pc)); }(object)
  // with the operator the emitter writes for the value's type (a set's own,
  // %= the runtime's ModAssign)
  LIndex := nil;
  LMember := nil;
  if AAssign.Target is TPCIndex then
  begin
    LIndex := TPCIndex(AAssign.Target);
    LProperty := LIndex.ResolvedProperty;
    if (LIndex.Base is TPCMember) and (TPCMember(LIndex.Base).ResolvedKind = rkProperty) then
      LMember := TPCMember(LIndex.Base);
  end
  else
  begin
    LMember := TPCMember(AAssign.Target);
    LProperty := TPCPropertyItem(LMember.ResolvedDecl);
  end;
  if LProperty = nil then
    DoMissing(AFile, 'property');
  LName := LProperty.PropName;
  if AAssign.Op = aoAssign then
  begin
    DoWritePropertyCallHead(AFile, LMember, LIndex, LProperty, True);
    if LIndex <> nil then
    begin
      DoWriteExpr(AFile, LIndex.IndexExpr);
      DoText(AFile, ', ');
    end;
    DoWriteExpr(AFile, AAssign.ValueExpr);
    DoText(AFile, ')');
    Exit;
  end;
  if LMember <> nil then
    LQualifier := DoPropertyQualifier(LMember)
  else
    LQualifier := '';
  LObject := PC_EMT_PROP_OBJECT + '.' + LQualifier;
  DoText(AFile, '[&](auto&& ' + PC_EMT_PROP_OBJECT + ') { ');
  LIndexArg := '';
  if LIndex <> nil then
  begin
    DoText(AFile, 'auto&& ' + PC_EMT_PROP_INDEX + ' = ');
    DoWriteOperand(AFile, LIndex.IndexExpr);
    DoText(AFile, '; ');
    LIndexArg := PC_EMT_PROP_INDEX;
  end;
  DoText(AFile, 'auto&& ' + PC_EMT_PROP_VALUE + ' = ');
  DoWriteOperand(AFile, AAssign.ValueExpr);
  DoText(AFile, '; auto ' + PC_EMT_PROP_CURRENT + ' = ' + LObject + PC_EMT_PROP_GET + LName + '(' + LIndexArg + '); ');
  if AAssign.Op = aoModAssign then
    DoText(AFile, '::pcpp::ModAssign(' + PC_EMT_PROP_CURRENT + ', ' + PC_EMT_PROP_VALUE + ');')
  else
    DoText(AFile, PC_EMT_PROP_CURRENT + ' ' + DoAssignOpText(AAssign.Op, DoIsSetType(AAssign.Target.ResolvedType)) +
      ' ' + PC_EMT_PROP_VALUE + ';');
  if LIndexArg <> '' then
    LIndexArg := LIndexArg + ', ';
  DoText(AFile, ' ' + LObject + PC_EMT_PROP_SET + LName + '(' + LIndexArg + 'std::move(' + PC_EMT_PROP_CURRENT +
    ')); }(');
  if LMember <> nil then
    DoWritePropertyObject(AFile, LMember)
  else
    DoWriteDefaultObject(AFile, LIndex);
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWritePropertyCallHead(const AFile: TPCOutFile; const AMember: TPCMember;
  const AIndex: TPCIndex; const AProperty: TPCPropertyItem; const ASet: Boolean);
var
  LSavedSet: TPCMember;
  LSavedGet: TPCMember;
begin
  // O10: the object, the accessor's name and its '(' (the arguments follow):
  // through the property member (`(o).Q pcpp_get_X(`: DoWriteMember with
  // FSetterTarget / FOpenGetTarget), or for a default property on the index's
  // object (`(o).pcpp_get_X(`)
  if AMember <> nil then
  begin
    LSavedSet := FSetterTarget;
    LSavedGet := FOpenGetTarget;
    if ASet then
      FSetterTarget := AMember
    else
      FOpenGetTarget := AMember;
    try
      DoWriteExpr(AFile, AMember);
    finally
      FSetterTarget := LSavedSet;
      FOpenGetTarget := LSavedGet;
    end;
    Exit;
  end;
  DoWriteDefaultObject(AFile, AIndex);
  if ASet then
    DoText(AFile, '.' + PC_EMT_PROP_SET + AProperty.PropName + '(')
  else
    DoText(AFile, '.' + PC_EMT_PROP_GET + AProperty.PropName + '(');
end;

procedure TPCEmitter.DoWriteDefaultObject(const AFile: TPCOutFile; const AIndex: TPCIndex);
begin
  // O10: the object a default property is reached on: an own / ref's object
  // through ::pcpp::deref (nil raises), else the base itself
  if (AIndex.Base.ResolvedType <> nil) and (AIndex.Base.ResolvedType.Canon() is TPCOwnerType) then
  begin
    DoText(AFile, '::pcpp::deref(');
    DoWriteExpr(AFile, AIndex.Base);
    DoText(AFile, ')');
  end
  else
    DoWriteOperand(AFile, AIndex.Base);
end;

function TPCEmitter.DoPropertyQualifier(const AMember: TPCMember): string;
var
  LEmbed: TPCField;
  LHop: Integer;
begin
  // What stands between the object and the accessor's name, as DoWriteMember
  // writes it: Parent:: for parent.X, the embeds walked, the parent members
  Result := '';
  if (AMember.Base is TPCSpecial) and (TPCSpecial(AMember.Base).SpecialKind = skParent) then
  begin
    if (FRecord = nil) or (FRecord.ParentName = nil) then
      DoMissing(ofSource, 'parent type');
    Result := DoTypeName(FRecord.ParentName) + '::';
  end;
  for LEmbed in AMember.ResolvedEmbedPath do
    Result := Result + LEmbed.FieldName + '.';
  for LHop := 1 to AMember.ResolvedParentHops do
    Result := Result + PC_EMT_PARENT_MEMBER + '.';
end;

procedure TPCEmitter.DoWritePropertyObject(const AFile: TPCOutFile; const AMember: TPCMember);
begin
  // The object a property member is reached on, as one C++ object: parent.X
  // is self's (*this); an own / ref's object through ::pcpp::deref (nil
  // raises); '->' the object pointed to; '.' the base itself
  if (AMember.Base is TPCSpecial) and (TPCSpecial(AMember.Base).SpecialKind = skParent) then
    DoText(AFile, '(*this)')
  else if TPCMember.ReadsOwner(AMember) then
  begin
    DoText(AFile, '::pcpp::deref(');
    DoWriteExpr(AFile, AMember.Base);
    DoText(AFile, ')');
  end
  else if AMember.Access = maArrow then
  begin
    DoText(AFile, '(*');
    DoWriteOperand(AFile, AMember.Base);
    DoText(AFile, ')');
  end
  else
    DoWriteOperand(AFile, AMember.Base);
end;

procedure TPCEmitter.DoWriteArgs(const AFile: TPCOutFile; const AArgs: TList<TPCExpr>; const AFirst: Integer;
  const ALast: Integer);
var
  LIndex: Integer;
begin
  // Arguments AFirst .. ALast, ', ' separated (each one group already: a
  // composite is parenthesized, so a C++ comma never splits one)
  for LIndex := AFirst to ALast do
  begin
    if LIndex > AFirst then
      DoText(AFile, ', ');
    DoWriteExpr(AFile, AArgs[LIndex]);
  end;
end;

function TPCEmitter.DoRankWrapper(const ACall: TPCCall; const AIndex: Integer): string;
var
  LCanon: TPCTypeExpr;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
  LRoutine: TPCRoutine;
begin
  // The runtime rank an argument of a ranked call is passed as (runtime
  // "Record extensions"): a record (any mode) rank_value; a pointer to a
  // record rank_ptr, or rank_ptr_var when a member takes it as a var
  // parameter (SEM accepts such a member only for a variable: DoVarTakes);
  // '' = the argument as written (an object, C/C++, any other type)
  Result := '';
  if ACall.Args[AIndex].ResolvedType = nil then
    Exit;
  LCanon := ACall.Args[AIndex].ResolvedType.Canon();
  if (LCanon is TPCRecordType) and not TPCRecordType(LCanon).IsObject then
    Exit('::pcpp::rank_value');
  if not TPCTypeExpr.PointerOf(LCanon, LTarget, LIsConst) or (LTarget = nil) then
    Exit;
  LTarget := LTarget.Canon();
  if not (LTarget is TPCRecordType) or TPCRecordType(LTarget).IsObject then
    Exit;
  Result := '::pcpp::rank_ptr';
  for LRoutine in ACall.ResolvedCandidates do
  begin
    if (AIndex < LRoutine.Params.Count) and (LRoutine.Params[AIndex] <> nil) and
      (LRoutine.Params[AIndex].ParamMode = pmVar) then
      Exit('::pcpp::rank_ptr_var');
  end;
end;

procedure TPCEmitter.DoWriteRankedArgs(const AFile: TPCOutFile; const ACall: TPCCall);
var
  LIndex: Integer;
  LArg: TPCExpr;
  LMark: TPCWriterMark;
  LWrapper: string;
begin
  // PLAN-RECORDS M12 (2) / M13: the arguments of a ranked overloads call,
  // each in its rank (DoRankWrapper) so clang ranks the members as C++
  // inheritance did; nil is ::pcpp::nil (a plain nullptr would rank a raw
  // pointer parameter above a record pointer's rank), in nil's own span
  for LIndex := 0 to ACall.Args.Count - 1 do
  begin
    if LIndex > 0 then
      DoText(AFile, ', ');
    LArg := ACall.Args[LIndex];
    if (LArg is TPCLiteral) and (TPCLiteral(LArg).LiteralKind = lkNil) then
    begin
      DoAt(AFile, LArg.Range.StartLine);
      LMark := FWriters[AFile].Mark();
      DoText(AFile, '::pcpp::nil');
      FWriters[AFile].CloseSpan(LMark, LArg);
      Continue;
    end;
    // The wrapper goes on the argument's line (F28: text before a child's
    // DoAt would stay on the line before)
    LWrapper := DoRankWrapper(ACall, LIndex);
    DoAt(AFile, LArg.Range.StartLine);
    if LWrapper <> '' then
      DoText(AFile, LWrapper + '(');
    DoWriteExpr(AFile, LArg);
    if LWrapper <> '' then
      DoText(AFile, ')');
  end;
end;

procedure TPCEmitter.DoWriteSlot(const AFile: TPCOutFile; const AArg: TPCExpr);
begin
  // One slot of a cpplink variadic's pack, the argument written ONCE (V2: a
  // decltype copy of it doubled the text per nested call): a string literal
  // ::pcpp::Slot<std::string>((e)) (std::wstring when wide), nil
  // ::pcpp::Slot<void*>((e)), a named PaskalCPP type ::pcpp::Slot<T>((e));
  // any other literal and any C/C++ value ::pcpp::slot((e)), which deduces
  // its C++ type exactly as std::decay_t<decltype((e))>
  if (AArg is TPCLiteral) and (TPCLiteral(AArg).LiteralKind = lkNil) then
    DoText(AFile, '::pcpp::Slot<void*>(')
  else if (AArg is TPCLiteral) and (TPCLiteral(AArg).LiteralKind = lkString) then
  begin
    if (AArg.ResolvedType is TPCStringLiteralType) and TPCStringLiteralType(AArg.ResolvedType).IsWide then
      DoText(AFile, '::pcpp::Slot<std::wstring>(')
    else
      DoText(AFile, '::pcpp::Slot<std::string>(');
  end
  else if (not (AArg is TPCLiteral)) and (AArg.ResolvedType <> nil) and DoIsNamedPaskalType(AArg.ResolvedType) then
    DoText(AFile, '::pcpp::Slot<' + DoTypeName(AArg.ResolvedType) + '>(')
  else
    DoText(AFile, '::pcpp::slot(');
  DoWriteOperand(AFile, AArg);
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWritePack(const AFile: TPCOutFile; const ACall: TPCCall; const AFirst: Integer);
var
  LIndex: Integer;
begin
  // A cpplink variadic's extra arguments, packed (O-V1):
  // ::pcpp::Pack(<slot 1>, ..., <slot n>) -> ::pcpp::VarStore<T1, ..., Tn>
  DoText(AFile, '::pcpp::Pack(');
  for LIndex := AFirst to ACall.Args.Count - 1 do
  begin
    if LIndex > AFirst then
      DoText(AFile, ', ');
    DoWriteSlot(AFile, ACall.Args[LIndex]);
  end;
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteConversion(const AFile: TPCOutFile; const ACall: TPCCall);
var
  LTarget: TPCTypeExpr;
begin
  // T(x) with T a declared type (Q9): static_cast<T>((x)); a pointer from or
  // to an integer reinterpret_cast
  if ACall.Args.Count <> 1 then
    DoMissing(AFile, 'conversion argument');
  LTarget := nil;
  if ACall.ResolvedDecl is TPCTypeDecl then
    LTarget := TPCTypeDecl(ACall.ResolvedDecl).TypeDef;
  if (LTarget <> nil) and
    ((DoIsPointerType(LTarget) and DoIsIntegerType(ACall.Args[0].ResolvedType)) or
    (DoIsIntegerType(LTarget) and DoIsPointerType(ACall.Args[0].ResolvedType))) then
    DoText(AFile, 'reinterpret_cast<')
  else
    DoText(AFile, 'static_cast<');
  if ACall.ResolvedDecl is TPCTypeDecl then
    DoText(AFile, DoDeclName(TPCTypeDecl(ACall.ResolvedDecl)))
  else
    DoWriteExpr(AFile, ACall.Callee);
  DoText(AFile, '>(');
  DoWriteOperand(AFile, ACall.Args[0]);
  DoText(AFile, ')');
end;

class function TPCEmitter.DoTestKindName(const AKind: TPCIntrinsicKind): string;
begin
  // The runtime's test family kind (runtime-contract.md): the PaskalCPP name
  // without `test`, snake case; '' = not a test intrinsic
  case AKind of
    ikTestAssert:
      Result := 'assert';
    ikTestAssertTrue:
      Result := 'assert_true';
    ikTestAssertFalse:
      Result := 'assert_false';
    ikTestAssertNil:
      Result := 'assert_nil';
    ikTestAssertNotNil:
      Result := 'assert_not_nil';
    ikTestFail:
      Result := 'fail';
    ikTestAssertEqualInt:
      Result := 'assert_equal_int';
    ikTestAssertEqualUInt:
      Result := 'assert_equal_uint';
    ikTestAssertEqualFloat:
      Result := 'assert_equal_float';
    ikTestAssertEqualStr:
      Result := 'assert_equal_str';
    ikTestAssertEqualBool:
      Result := 'assert_equal_bool';
    ikTestAssertEqualPtr:
      Result := 'assert_equal_ptr';
  else
    Result := '';
  end;
end;

class function TPCEmitter.DoBitField(const AExpr: TPCExpr): TPCField;
begin
  // The bit field an argument reads (x.f, or f in a method body); nil = none
  Result := nil;
  if (AExpr is TPCMember) and (TPCMember(AExpr).ResolvedDecl is TPCField) then
    Result := TPCField(TPCMember(AExpr).ResolvedDecl)
  else if (AExpr is TPCName) and (TPCName(AExpr).ResolvedDecl is TPCField) then
    Result := TPCField(TPCName(AExpr).ResolvedDecl);
  if (Result <> nil) and (Result.BitWidthExpr = nil) then
    Result := nil;
end;

class function TPCEmitter.DoChoicesBitField(const AExpr: TPCExpr): TPCField;
begin
  // F37: the choices bit field an expression names (TPCField.IsChoicesBitfield);
  // nil = none. Its storage is the underlying integer: a read is cast to the
  // choices type, a store's value to the integer
  Result := DoBitField(AExpr);
  if (Result <> nil) and not Result.IsChoicesBitfield() then
    Result := nil;
end;

procedure TPCEmitter.DoWriteRuntimeArgs(const AFile: TPCOutFile; const ACall: TPCCall);
var
  LIndex: Integer;
begin
  // (a), (b), ...: every argument of a runtime call is one group (A9), so a
  // runtime entry that is a macro still sees one argument per PaskalCPP one
  for LIndex := 0 to ACall.Args.Count - 1 do
  begin
    if LIndex > 0 then
      DoText(AFile, ', ');
    DoWriteOperand(AFile, ACall.Args[LIndex]);
  end;
end;

procedure TPCEmitter.DoWriteRuntimeCall(const AFile: TPCOutFile; const AName: string; const ACall: TPCCall);
begin
  // ::pcpp::name((a), (b), ...)
  DoText(AFile, AName + '(');
  DoWriteRuntimeArgs(AFile, ACall);
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWritePrintElement(const AFile: TPCOutFile;
  const AArrayType: TPCTypeExpr; const ADepth: Integer);
var
  LElementType: TPCTypeExpr;
  LName: string;
begin
  // The lambda ::pcpp::print_map hands each element of an array to (E7):
  // `[](const auto& eN) { return <the element's form of eN>; }`, the form
  // read from the element type's TPCTypeExpr.PrintForm, an array element a
  // print_map of its own (one level deeper). Inside a range the text forms
  // are the runtime's Print* wrappers: quoted as a char / string element is,
  // a nil pointer `nil` unquoted. The element type is only read, never
  // written: no span
  LElementType := TPCArrayType(AArrayType.Canon()).ElementType;
  LName := 'e' + IntToStr(ADepth);
  DoText(AFile, '[](const auto& ' + LName + ') { return ');
  case TPCTypeExpr.PrintForm(LElementType) of
    pfCStr:
      DoText(AFile, '::pcpp::PrintCStr{' + LName + '}');
    pfWCStr:
      DoText(AFile, '::pcpp::PrintWCStr{' + LName + '}');
    pfWideChar:
      DoText(AFile, '::pcpp::PrintWChar{' + LName + '}');
    pfWideText:
      DoText(AFile, '::pcpp::utf8(' + LName + ')');
    pfTypedAddress:
      DoText(AFile, 'static_cast<const void*>(' + LName + ')');
    pfRoutineAddress:
      DoText(AFile, 'reinterpret_cast<const void*>(' + LName + ')');
    pfElements:
      begin
        DoText(AFile, '::pcpp::print_map(' + LName + ', ');
        DoWritePrintElement(AFile, LElementType, ADepth + 1);
        DoText(AFile, ')');
      end;
  else
    // pfAsIs (pfUnprintable never reaches the emitter: SEM's SM0425)
    DoText(AFile, LName);
  end;
  DoText(AFile, '; }');
end;

procedure TPCEmitter.DoWritePrintCheck(const AFile: TPCOutFile; const AArg: TPCExpr);
var
  LMark: TPCWriterMark;
begin
  // A print argument of a C/C++ type (pfCppChecked, E7, as E3's align
  // checks): the argument, written ONCE, is handed to a generic lambda
  // `[](const auto& pcpp_v) -> decltype(auto) { static_assert(
  // ::pcpp::printable<T>, "pcpp:SM0425"); return ::pcpp::print_arg(pcpp_v); }`
  // (written twice, a C++ mistake inside it would be reported twice).
  // The whole call is a second span of the argument around its own one, so
  // the static_assert's location falls in that span alone: the frontend
  // finds the argument (TPCAst.PrintArgAt) and reports SM0425 there in
  // PaskalCPP words; print_arg hands std::format a placeholder for a type it
  // cannot take (no second report)
  LMark := FWriters[AFile].Mark();
  DoText(AFile, '[](const auto& pcpp_v) -> decltype(auto) { static_assert(::pcpp::printable<' +
    'std::remove_cvref_t<decltype(pcpp_v)>>, "' + PC_FRONTEND_CHECK_PRINT + '"); ' +
    'return ::pcpp::print_arg(pcpp_v); }(');
  DoWriteOperand(AFile, AArg);
  DoText(AFile, ')');
  FWriters[AFile].CloseSpan(LMark, AArg);
end;

procedure TPCEmitter.DoWritePrintArg(const AFile: TPCOutFile; const AArg: TPCExpr);
var
  LForm: TPCPrintForm;
  LField: TPCField;
begin
  // One argument after the format, by its TPCTypeExpr.PrintForm (the AST
  // rule TPCAst.ModuleNamesRuntime reads too): a ptr to [const] char
  // ::pcpp::CStr((x)) (nil prints `nil`, Q11); a ptr to [const] wchar
  // ::pcpp::WCStr((x)); a wchar / wstring ::pcpp::utf8((x)) (wide text
  // reaches std::format as UTF-8, E4); E7: a pointer to any other type
  // static_cast<const void*>((x)), a routine value
  // reinterpret_cast<const void*>((x)) (their address, as an untyped ptr
  // prints), an array whose elements have a form ::pcpp::print_map((x),
  // <element lambda>); a bit field static_cast<T>((x)) (a bit field binds no
  // reference; a wchar one inside utf8, so its char16_t storage, F25, reads
  // as the wchar it is); else as written. pfUnprintable is SEM's SM0425
  LForm := TPCTypeExpr.PrintFormOfArg(AArg);
  LField := DoBitField(AArg);
  if (LForm = pfUnprintable) or (LForm = pfNoAddress) then
  begin
    DoNoRule(AArg);
    Exit;
  end;
  if LForm = pfCStr then
    DoText(AFile, '::pcpp::CStr(')
  else if LForm = pfWCStr then
    DoText(AFile, '::pcpp::WCStr(')
  else if (LForm = pfWideChar) or (LForm = pfWideText) then
    DoText(AFile, '::pcpp::utf8(')
  else if LForm = pfTypedAddress then
    DoText(AFile, 'static_cast<const void*>(')
  else if LForm = pfRoutineAddress then
    DoText(AFile, 'reinterpret_cast<const void*>(')
  else if LForm = pfElements then
    DoText(AFile, '::pcpp::print_map(')
  else if LForm = pfCppChecked then
  begin
    DoWritePrintCheck(AFile, AArg);
    Exit;
  end
  else if LField = nil then
  begin
    DoWriteExpr(AFile, AArg);
    Exit;
  end;
  if LField <> nil then
  begin
    DoText(AFile, 'static_cast<');
    DoWriteBorrowedType(AFile, LField.TypeExpr);
    DoText(AFile, '>(');
    DoWriteOperand(AFile, AArg);
    DoText(AFile, ')');
  end
  else
    DoWriteOperand(AFile, AArg);
  if LForm = pfElements then
  begin
    DoText(AFile, ', ');
    DoWritePrintElement(AFile, AArg.ResolvedType, 0);
  end;
  if LForm <> pfAsIs then
    DoText(AFile, ')');
end;

procedure TPCEmitter.DoWritePrint(const AFile: TPCOutFile; const ACall: TPCCall);
var
  LIndex: Integer;
begin
  // std::print / std::println: the format is C++'s (clang checks it). The
  // first argument as written, every other one by DoWritePrintArg (its
  // type's print form, E7; an argument of a C/C++ type through its
  // formatter check, DoWritePrintCheck)
  if ACall.IntrinsicKind = ikPrintLn then
    DoText(AFile, 'std::println(')
  else
    DoText(AFile, 'std::print(');
  for LIndex := 0 to ACall.Args.Count - 1 do
  begin
    if LIndex > 0 then
      DoText(AFile, ', ');
    if LIndex = 0 then
      DoWriteExpr(AFile, ACall.Args[LIndex])
    else
      DoWritePrintArg(AFile, ACall.Args[LIndex]);
  end;
  DoText(AFile, ')');
end;

function TPCEmitter.DoCreationSiteText(const ANode: TPCNode): string;
var
  LFileName: string;
begin
  // `"<file>", <line>`: the creation site the debug leak report names, for
  // an owner new and create (PLAN-INTRINSICS I3); the .pcpp file's name, not
  // its folder, so the text is the same on every machine
  LFileName := FModule.SourceFile;
  LFileName := Copy(LFileName, LastDelimiter('\/:', LFileName) + 1, MaxInt);
  Result := '"' + TPCCppWriter.EscapePath(LFileName) + '", ' + UIntToStr(ANode.Range.StartLine);
end;

procedure TPCEmitter.DoWriteOwnerNew(const AFile: TPCOutFile; const ANew: TPCOwnerNew);
var
  LCall: TPCCall;
  LHasTag: Boolean;
begin
  // PLAN-OBJECT O6 (D4): own T(args) / ref T(args) is
  // ::pcpp::make_own<T>("<file>", <line>, [T::pcpp_init_<n>{},] args) (make_ref
  // for ref): the init SEM picked as a construction picks it
  // (DoWriteInitArgs); file and line are the creation site the debug leak
  // report names (the .pcpp file's name, not its folder: the same text on
  // every machine)
  if (ANew.OwnerType = nil) or (ANew.OwnerType.TargetType = nil) or (ANew.InitCall = nil) then
    DoMissing(AFile, 'owner new');
  if ANew.OwnerType.OwnerKind = okOwn then
    DoText(AFile, '::pcpp::make_own<')
  else if ANew.OwnerType.OwnerKind = okRef then
    DoText(AFile, '::pcpp::make_ref<')
  else
    DoNoRule(ANew);
  DoWriteType(AFile, ANew.OwnerType.TargetType);
  DoText(AFile, '>(' + DoCreationSiteText(ANew));
  LCall := ANew.InitCall;
  LHasTag := (LCall.ResolvedInit <> nil) and (LCall.ResolvedInit.Routine <> nil) and
    (LCall.ResolvedInit.Routine.Params.Count > 0);
  if LHasTag or (LCall.Args.Count > 0) then
  begin
    DoText(AFile, ', ');
    DoWriteInitArgs(AFile, ANew.OwnerType.TargetType, LCall);
  end;
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteTypeTest(const AFile: TPCOutFile; const ATest: TPCTypeTest);
var
  LName: string;
begin
  // PLAN-OBJECT O12 (D15): `X is T` is ::pcpp::is_a<T>(x), `X as T` is
  // ::pcpp::as_a<T>(x, "T"): the runtime raises EXC_INVALID_CAST naming T
  // in its PaskalCPP spelling. It takes the operand's C++ kind as SEM took
  // its PaskalCPP kind (runtime api.md "is / as"): a pointer gives a pointer,
  // a Ref a Ref, an Own and an object the object itself
  if (ATest.Operand = nil) or (ATest.TargetType = nil) then
    DoMissing(AFile, 'is / as');
  if ATest.IsCast then
    DoText(AFile, '::pcpp::as_a<')
  else
    DoText(AFile, '::pcpp::is_a<');
  DoWriteType(AFile, ATest.TargetType);
  DoText(AFile, '>(');
  DoWriteExpr(AFile, ATest.Operand);
  if ATest.IsCast then
  begin
    LName := ATest.TargetType.TypeText().Replace('\', '\\').Replace('"', '\"');
    DoText(AFile, ', "' + LName + '"');
  end;
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteTestCall(const AFile: TPCOutFile; const ACall: TPCCall);
var
  LKind: string;
begin
  // In a test block the runtime records the failure and the test goes on:
  // ::pcpp::test_<kind>(args, "<file>", <line>); outside one it reports and
  // aborts: ::pcpp::assert_<kind>(...). File and line are the .pcpp call's
  LKind := DoTestKindName(ACall.IntrinsicKind);
  if LKind = '' then
    DoNoRule(ACall);
  if ACall.ResolvedInTest then
    DoText(AFile, '::pcpp::test_' + LKind + '(')
  else
    DoText(AFile, '::pcpp::assert_' + LKind + '(');
  DoWriteRuntimeArgs(AFile, ACall);
  if ACall.Args.Count > 0 then
    DoText(AFile, ', ');
  DoText(AFile, Format('"%s", %d)', [TPCCppWriter.EscapePath(FModule.SourceFile), ACall.Range.StartLine]));
end;

procedure TPCEmitter.DoWriteIntrinsic(const AFile: TPCOutFile; const ACall: TPCCall);
var
  LTarget: TPCTypeExpr;
begin
  // A9: EM "Intrinsics"; every argument a group (E18) unless noted
  case ACall.IntrinsicKind of
    ikLen:
      begin
        // F60 (intr_len): a string literal is a C array holding its
        // terminator, so its length is the array's size less one (exact for
        // escapes, joined parts, raw and wide literals; len("four") gave 5,
        // len("") 1, both targets). Anything else is std::ssize as it is
        if (ACall.Args[0] is TPCLiteral) and (TPCLiteral(ACall.Args[0]).LiteralKind = lkString) then
        begin
          DoText(AFile, '(static_cast<std::int64_t>(std::ssize(');
          DoWriteOperand(AFile, ACall.Args[0]);
          DoText(AFile, ')) - 1)');
        end
        else
        begin
          DoText(AFile, 'static_cast<std::int64_t>(std::ssize(');
          DoWriteOperand(AFile, ACall.Args[0]);
          DoText(AFile, '))');
        end;
      end;
    ikSize:
      begin
        // size(T): a type argument, or a name the parser left an expression
        DoText(AFile, 'static_cast<std::int64_t>(sizeof(');
        if ACall.TypeArg <> nil then
          DoWriteType(AFile, ACall.TypeArg)
        else
          DoWriteExpr(AFile, ACall.Args[0]);
        DoText(AFile, '))');
      end;
    ikUtf8:
      DoWriteRuntimeCall(AFile, '::pcpp::utf8', ACall);
    ikParamCount:
      DoText(AFile, '::pcpp::param_count()');
    ikParamStr:
      DoWriteRuntimeCall(AFile, '::pcpp::param_str', ACall);
    ikGetMem:
      DoWriteRuntimeCall(AFile, '::pcpp::get_mem', ACall);
    ikResizeMem:
      DoWriteRuntimeCall(AFile, '::pcpp::resize_mem', ACall);
    ikFreeMem:
      DoWriteRuntimeCall(AFile, '::pcpp::free_mem', ACall);
    ikSetLength:
      // PLAN-INTRINSICS I2: a negative length raises EXC_MEMORY in the
      // runtime, never libc++'s length_error text
      DoWriteRuntimeCall(AFile, '::pcpp::set_length', ACall);
    ikCreate:
      begin
        // (p) = ::pcpp::create<T>("<file>", <line>), T = p's pointer target
        // (borrowed): new T{}, value-initialized, so a record's / overlay's
        // every byte starts zeroed (F35), and tracked by the debug heap
        // report at this site (PLAN-INTRINSICS I3). p is assigned, never
        // bound to a reference: a pointer field of a packed record takes it.
        // SEM let only htData / htOpaque through (TPCTypeExpr.HeapTargetOf, F36)
        if not (TPCTypeExpr.HeapTargetOf(ACall.Args[0].ResolvedType, LTarget) in [htData, htOpaque]) then
          DoMissing(AFile, 'create target type');
        DoWriteOperand(AFile, ACall.Args[0]);
        DoText(AFile, ' = ::pcpp::create<');
        DoWriteBorrowedType(AFile, LTarget);
        DoText(AFile, '>(' + DoCreationSiteText(ACall) + ')');
      end;
    ikDestroy:
      begin
        // ::pcpp::destroy((p)); (p) = nullptr (the second p borrowed): the
        // release is tracked (PLAN-INTRINSICS I3); p goes by value, for the
        // same packed-field reason as create
        DoText(AFile, '::pcpp::destroy(');
        DoWriteOperand(AFile, ACall.Args[0]);
        DoText(AFile, '); ');
        DoWriteBorrowedExpr(AFile, ACall.Args[0]);
        DoText(AFile, ' = nullptr');
      end;
    ikRaise:
      begin
        DoText(AFile, '::pcpp::raise(1, ');
        DoWriteOperand(AFile, ACall.Args[0]);
        DoText(AFile, ')');
      end;
    ikRaiseCode:
      DoWriteRuntimeCall(AFile, '::pcpp::raise', ACall);
    ikExcCode:
      DoText(AFile, '::pcpp::exc_code()');
    ikExcMsg:
      DoText(AFile, '::pcpp::exc_msg()');
    ikPrint, ikPrintLn:
      DoWritePrint(AFile, ACall);
    ikAlive:
      // PLAN-OBJECT O6 (Q3): the object a weak watches still exists
      DoWriteRuntimeCall(AFile, '::pcpp::alive', ACall);
    ikLock:
      // ... and a ref to it (nil when gone)
      DoWriteRuntimeCall(AFile, '::pcpp::lock', ACall);
  else
    DoWriteTestCall(AFile, ACall);
  end;
end;

procedure TPCEmitter.DoWriteCall(const AFile: TPCOutFile; const ACall: TPCCall);
var
  LTarget: TPCRoutine;
  LFixed: Integer;
begin
  // callee(args); a type conversion; an intrinsic (A9); a varargs local's
  // member call (DoWriteVarargsLocalCall); a cpplink variadic packs its extra
  // arguments in a VarStore
  if ACall.IntrinsicKind <> ikNone then
  begin
    DoWriteIntrinsic(AFile, ACall);
    Exit;
  end;
  if ACall.ResolvedKind = rkType then
  begin
    DoWriteConversion(AFile, ACall);
    Exit;
  end;
  if (ACall.Callee is TPCMember) and (TPCMember(ACall.Callee).ResolvedVarargs <> vaPlain) then
  begin
    DoWriteVarargsLocalCall(AFile, ACall);
    Exit;
  end;
  // F18: a call SEM limited to some members of an overload set goes through
  // exactly those (TPCCall.ResolvedCandidates); a set holds no variadic
  // member (SM0330), so the arguments are written plain
  if ACall.ResolvedCandidates.Count > 0 then
  begin
    DoWriteCandidates(AFile, ACall);
    DoText(AFile, '(');
    if ACall.ResolvedRanksExtensions then
      DoWriteRankedArgs(AFile, ACall)
    else
      DoWriteArgs(AFile, ACall.Args, 0, ACall.Args.Count - 1);
    DoText(AFile, ')');
    Exit;
  end;
  DoWriteExpr(AFile, ACall.Callee);
  DoText(AFile, '(');
  LTarget := ACall.TargetRoutine();
  if (LTarget <> nil) and LTarget.IsVariadic and (LTarget.ResolvedLinkage <> lnC) then
  begin
    LFixed := LTarget.Params.Count;
    if LFixed > ACall.Args.Count then
      DoMissing(AFile, 'fixed argument');
    DoWriteArgs(AFile, ACall.Args, 0, LFixed - 1);
    if LFixed > 0 then
      DoText(AFile, ', ');
    DoWritePack(AFile, ACall, LFixed);
  end
  else
    DoWriteArgs(AFile, ACall.Args, 0, ACall.Args.Count - 1);
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteCandidates(const AFile: TPCOutFile; const ACall: TPCCall);
var
  LIndex: Integer;
  LRoutine: TPCRoutine;
begin
  // F18: ::pcpp::overloads(static_cast<std::add_pointer_t<R(P...)>>(&callee), ...)
  // with the members SEM kept, in their order (runtime overloads: C++ ranks
  // exactly these). The callee is written once with its span; every later
  // spelling of it and each member's types are borrowed (their nodes live
  // in the routines, maybe in another module's file). PLAN-RECORDS M12 (2) /
  // M13: a call whose members take an argument at a level above its record
  // (ResolvedRanksExtensions) uses the ranked set (DoWriteRankedArgs)
  if ACall.ResolvedRanksExtensions then
    DoText(AFile, '::pcpp::ranked_overloads(')
  else
    DoText(AFile, '::pcpp::overloads(');
  for LIndex := 0 to ACall.ResolvedCandidates.Count - 1 do
  begin
    LRoutine := ACall.ResolvedCandidates[LIndex];
    // SEM keeps no variadic member in a set (SM0330): an invariant here
    if LRoutine.IsVariadic then
      DoMissing(AFile, 'non-variadic overload member');
    if LIndex > 0 then
      DoText(AFile, ', ');
    DoText(AFile, 'static_cast<std::add_pointer_t<');
    FWriters[AFile].BeginBorrowed();
    try
      if LRoutine.ReturnType = nil then
        DoText(AFile, 'void')
      else
        DoWriteType(AFile, LRoutine.ReturnType);
      DoText(AFile, '(');
      DoWriteParams(AFile, LRoutine.Params, False, LRoutine.ResolvedLinkage, False);
      DoText(AFile, ')');
    finally
      FWriters[AFile].EndBorrowed();
    end;
    DoText(AFile, '>>(&');
    // One spelling of the callee for every member: the first owns its span
    if LIndex = 0 then
      DoWriteExpr(AFile, ACall.Callee)
    else
    begin
      FWriters[AFile].BeginBorrowed();
      try
        DoWriteExpr(AFile, ACall.Callee);
      finally
        FWriters[AFile].EndBorrowed();
      end;
    end;
    DoText(AFile, ')');
  end;
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteIndex(const AFile: TPCOutFile; const AIndex: TPCIndex);
var
  LArray: TPCArrayType;
  LLow: string;
  LChoices: TPCChoicesType;
begin
  // (a)[(i)]; a static array is (a).pcpp_items[(i)], the built-in [] on its
  // C array (PLAN-RECORDS A8b, F-A8a: no member call, so an element of an
  // array a packed record misaligns is read and written as a packed field);
  // a static array whose low bound is not 0: [(i) - (L)] (E22), L folded (or
  // the bound written again, borrowed)
  // PLAN-OBJECT O10: an indexed or default property's read is
  // (o).pcpp_get_X((i)) (DoWritePropertyCallHead)
  if AIndex.ResolvedProperty <> nil then
  begin
    if (AIndex.Base is TPCMember) and (TPCMember(AIndex.Base).ResolvedKind = rkProperty) then
      DoWritePropertyCallHead(AFile, TPCMember(AIndex.Base), AIndex, AIndex.ResolvedProperty, False)
    else
      DoWritePropertyCallHead(AFile, nil, AIndex, AIndex.ResolvedProperty, False);
    DoWriteExpr(AFile, AIndex.IndexExpr);
    DoText(AFile, ')');
    Exit;
  end;
  LArray := nil;
  if (AIndex.Base.ResolvedType <> nil) and (AIndex.Base.ResolvedType.Canon() is TPCArrayType) then
    LArray := TPCArrayType(AIndex.Base.ResolvedType.Canon());
  DoWriteOperand(AFile, AIndex.Base);
  if (LArray <> nil) and (not LArray.IsDynamic) then
    DoText(AFile, '.pcpp_items');
  DoText(AFile, '[');
  // F43: an array bounded by choice values is indexed by a value (SEM's
  // SM0261), a scoped enum C++ takes as no subscript: written as its
  // underlying integer, as the bound is folded to its ordinal
  LChoices := nil;
  if (LArray <> nil) and (not LArray.IsDynamic) and (LArray.LowExpr <> nil) and
    (LArray.LowExpr.ResolvedType <> nil) and (LArray.LowExpr.ResolvedType.Canon() is TPCChoicesType) then
    LChoices := TPCChoicesType(LArray.LowExpr.ResolvedType.Canon());
  if LChoices <> nil then
    DoText(AFile, 'static_cast<' + DoChoicesUnderlying(LChoices) + '>(');
  DoWriteOperand(AFile, AIndex.IndexExpr);
  if LChoices <> nil then
    DoText(AFile, ')');
  if (LArray <> nil) and (not LArray.IsDynamic) and (LArray.LowExpr <> nil) then
  begin
    if DoFoldedText(LArray.LowExpr, LLow) then
    begin
      if LLow <> '0' then
        DoText(AFile, ' - (' + LLow + ')');
    end
    else
    begin
      DoText(AFile, ' - ');
      DoWriteBorrowedExpr(AFile, LArray.LowExpr);
    end;
  end;
  DoText(AFile, ']');
end;

procedure TPCEmitter.DoWriteCast(const AFile: TPCOutFile; const ACast: TPCCast);
begin
  // builtin T(x) static_cast<T>((x)) (pointer <-> integer reinterpret_cast);
  // ptr to T(x) static_cast<T*>((x)) from void*, else reinterpret_cast;
  // C-style ((T)(x)); named casts as written, the operand lowered.
  // PLAN-RECORDS F-A4b / F-A6a: a downcast between records of one member
  // chain (SEM's ResolvedDowncastHops; M10: no C++ inheritance relates them)
  // is ::pcpp::downcast<N, T*>((x)): the same address, nil stays nil
  if ACast.ResolvedDowncastHops > 0 then
  begin
    DoText(AFile, '::pcpp::downcast<' + IntToStr(ACast.ResolvedDowncastHops) + ', ');
    DoWriteType(AFile, ACast.TargetType);
    DoText(AFile, '>(');
    DoWriteOperand(AFile, ACast.Operand);
    DoText(AFile, ')');
    Exit;
  end;
  case ACast.CastKind of
    ckBuiltin:
      begin
        if (DoIsPointerType(ACast.TargetType) and DoIsIntegerType(ACast.Operand.ResolvedType)) or
          (DoIsIntegerType(ACast.TargetType) and DoIsPointerType(ACast.Operand.ResolvedType)) then
          DoText(AFile, 'reinterpret_cast<')
        else
          DoText(AFile, 'static_cast<');
      end;
    ckPointer:
      begin
        if DoIsUntypedPointer(ACast.Operand.ResolvedType) then
          DoText(AFile, 'static_cast<')
        else
          DoText(AFile, 'reinterpret_cast<');
      end;
    ckCStyle:
      begin
        DoText(AFile, '((');
        DoWriteType(AFile, ACast.TargetType);
        DoText(AFile, ')');
        DoWriteOperand(AFile, ACast.Operand);
        DoText(AFile, ')');
        Exit;
      end;
    ckStatic:
      DoText(AFile, 'static_cast<');
    ckReinterpret:
      DoText(AFile, 'reinterpret_cast<');
    ckConst:
      DoText(AFile, 'const_cast<');
    ckDynamic:
      DoText(AFile, 'dynamic_cast<');
  end;
  DoWriteType(AFile, ACast.TargetType);
  DoText(AFile, '>(');
  DoWriteOperand(AFile, ACast.Operand);
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteNew(const AFile: TPCOutFile; const ANew: TPCNew);
begin
  // (new T), (new T(args)), (new T[(n)]), (new T{args})
  DoText(AFile, '(new ');
  DoWriteType(AFile, ANew.TargetType);
  case ANew.InitKind of
    niArgs:
      begin
        DoText(AFile, '(');
        DoWriteArgs(AFile, ANew.Args, 0, ANew.Args.Count - 1);
        DoText(AFile, ')');
      end;
    niArraySize:
      begin
        DoText(AFile, '[');
        DoWriteOperand(AFile, ANew.SizeExpr);
        DoText(AFile, ']');
      end;
    niBraced:
      begin
        DoText(AFile, '{');
        DoWriteArgs(AFile, ANew.Args, 0, ANew.Args.Count - 1);
        DoText(AFile, '}');
      end;
  end;
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteDelete(const AFile: TPCOutFile; const ADelete: TPCDelete);
begin
  if ADelete.IsArray then
    DoText(AFile, 'delete[] ')
  else
    DoText(AFile, 'delete ');
  DoWriteOperand(AFile, ADelete.Operand);
end;

procedure TPCEmitter.DoWriteBracedInit(const AFile: TPCOutFile; const AInit: TPCBracedInit);
begin
  // T{args} / a bare {args}
  if AInit.Base <> nil then
    DoWriteExpr(AFile, AInit.Base);
  DoText(AFile, '{');
  DoWriteArgs(AFile, AInit.Args, 0, AInit.Args.Count - 1);
  DoText(AFile, '}');
end;

procedure TPCEmitter.DoWriteSetLiteral(const AFile: TPCOutFile; const ASet: TPCSetLiteral);
var
  LTarget: TPCTypeExpr;
  LIndex: Integer;
  LElement: TPCSetElement;
  LMark: TPCWriterMark;
begin
  // ::pcpp::make_set<T>((e), ::pcpp::SetSpan<T>{(lo), (hi)}, ...); T = the
  // dkSetOf Target (borrowed); [] with no context ::pcpp::EmptySet{}
  if not ((ASet.ResolvedType is TPCDerivedType) and (TPCDerivedType(ASet.ResolvedType).DerivedKind = dkSetOf)) then
    DoMissing(AFile, 'set literal type');
  LTarget := TPCDerivedType(ASet.ResolvedType).Target;
  if LTarget = nil then
  begin
    DoText(AFile, '::pcpp::EmptySet{}');
    Exit;
  end;
  DoText(AFile, '::pcpp::make_set<');
  DoWriteBorrowedType(AFile, LTarget);
  DoText(AFile, '>(');
  for LIndex := 0 to ASet.Elements.Count - 1 do
  begin
    LElement := ASet.Elements[LIndex];
    if LIndex > 0 then
      DoText(AFile, ', ');
    DoAt(AFile, LElement.Range.StartLine);
    LMark := FWriters[AFile].Mark();
    if LElement.HighExpr = nil then
      DoWriteOperand(AFile, LElement.LowExpr)
    else
    begin
      DoText(AFile, '::pcpp::SetSpan<');
      DoWriteBorrowedType(AFile, LTarget);
      DoText(AFile, '>{');
      DoWriteOperand(AFile, LElement.LowExpr);
      DoText(AFile, ', ');
      DoWriteOperand(AFile, LElement.HighExpr);
      DoText(AFile, '}');
    end;
    FWriters[AFile].CloseSpan(LMark, LElement);
  end;
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteRecordLiteral(const AFile: TPCOutFile; const ARecord: TPCRecordLiteral);
var
  LIndex: Integer;
begin
  // T{.f = (v), ...} in written order (C++'s order rule is clang's); an
  // inherited field (PLAN-RECORDS M14) goes inside its parent member's
  // braces, .pcpp_parent = {...}, one level per hop (SEM's order puts a
  // parent's fields first: TPCFieldInit.ResolvedParentHops never rises)
  DoWriteType(AFile, ARecord.RecordType);
  LIndex := 0;
  DoWriteLiteralLevel(AFile, ARecord, 0, LIndex);
  // SEM orders the inits root first; any other order was reported
  if LIndex <> ARecord.Inits.Count then
    DoMissing(AFile, 'record literal fields in declaration order');
end;

procedure TPCEmitter.DoWriteLiteralLevel(const AFile: TPCOutFile; const ARecord: TPCRecordLiteral;
  const ALevel: Integer; var AIndex: Integer);
var
  LInit: TPCFieldInit;
  LFirst: Boolean;
  LMark: TPCWriterMark;
begin
  // One level's braces: the levels above it first (its parent member, when
  // the next init lies there), then its own fields
  DoText(AFile, '{');
  LFirst := True;
  if (AIndex < ARecord.Inits.Count) and (ARecord.Inits[AIndex].ResolvedParentHops > ALevel) then
  begin
    DoAt(AFile, ARecord.Inits[AIndex].Range.StartLine);
    DoText(AFile, '.' + PC_EMT_PARENT_MEMBER + ' = ');
    DoWriteLiteralLevel(AFile, ARecord, ALevel + 1, AIndex);
    LFirst := False;
  end;
  while (AIndex < ARecord.Inits.Count) and (ARecord.Inits[AIndex].ResolvedParentHops = ALevel) do
  begin
    LInit := ARecord.Inits[AIndex];
    if not LFirst then
      DoText(AFile, ', ');
    LFirst := False;
    DoAt(AFile, LInit.Range.StartLine);
    LMark := FWriters[AFile].Mark();
    DoText(AFile, '.' + LInit.FieldName + ' = ');
    // F37: a choices bit field holds its underlying integer
    if (LInit.ResolvedField <> nil) and LInit.ResolvedField.IsChoicesBitfield() then
      DoWriteChoicesStore(AFile, LInit.ResolvedField, LInit.ValueExpr)
    else
      DoWriteOperand(AFile, LInit.ValueExpr);
    FWriters[AFile].CloseSpan(LMark, LInit);
    Inc(AIndex);
  end;
  DoText(AFile, '}');
end;

procedure TPCEmitter.DoWriteVarargs(const AFile: TPCOutFile; const AVarargs: TPCVarargs);
begin
  // The enclosing variadic's pack: cpplink pcpp_va (::pcpp::VarArgs) and its
  // members; clink only next(T) = va_arg(pcpp_va, T) (H5)
  if (FRoutine = nil) or (not FRoutine.IsVariadic) then
    DoMissing(AFile, 'variadic routine');
  if FRoutine.ResolvedLinkage = lnC then
  begin
    if AVarargs.VarargsKind <> vaNext then
      DoNoRule(AVarargs);
    DoText(AFile, 'va_arg(' + PC_EMT_VARARGS_NAME + ', ');
    DoWriteType(AFile, AVarargs.ReadType);
    DoText(AFile, ')');
    Exit;
  end;
  DoText(AFile, PC_EMT_VARARGS_NAME);
  case AVarargs.VarargsKind of
    vaCount:
      DoText(AFile, '.Count()');
    vaNext:
      begin
        DoText(AFile, '.Next<');
        DoWriteType(AFile, AVarargs.ReadType);
        DoText(AFile, '>()');
      end;
    vaGet:
      begin
        DoText(AFile, '.Get<');
        DoWriteType(AFile, AVarargs.ReadType);
        DoText(AFile, '>(');
        DoWriteOperand(AFile, AVarargs.IndexExpr);
        DoText(AFile, ')');
      end;
    vaReset:
      DoText(AFile, '.Reset()');
    vaCopy:
      DoText(AFile, '.Copy()');
  end;
end;

procedure TPCEmitter.DoWriteVarargsLocalCall(const AFile: TPCOutFile; const ACall: TPCCall);
var
  LMember: TPCMember;
begin
  // A member call on a varargs local (BNF.md sec 6; SEM wrote the member's
  // kind on TPCMember.ResolvedVarargs): the local is a ::pcpp::VarArgs, so
  // L.Next<T>(), L.Get<T>(i), L.Reset(), L.Copy(), as DoWriteVarargs writes
  // the routine's own pack
  LMember := TPCMember(ACall.Callee);
  if LMember.Base = nil then
    DoMissing(AFile, 'member base');
  DoWriteOperand(AFile, LMember.Base);
  if LMember.Access = maArrow then
    DoText(AFile, '->')
  else
    DoText(AFile, '.');
  case LMember.ResolvedVarargs of
    vaNext:
      begin
        DoText(AFile, 'Next<');
        DoWriteVarargsReadType(AFile, ACall, 0);
        DoText(AFile, '>()');
      end;
    vaGet:
      begin
        if ACall.Args.Count = 0 then
          DoMissing(AFile, 'varargs index');
        DoText(AFile, 'Get<');
        DoWriteVarargsReadType(AFile, ACall, 1);
        DoText(AFile, '>(');
        DoWriteOperand(AFile, ACall.Args[0]);
        DoText(AFile, ')');
      end;
    vaReset:
      DoText(AFile, 'Reset()');
    vaCopy:
      DoText(AFile, 'Copy()');
  else
    // count is no call: SEM reports L.count() (SM0424; an invariant here)
    DoNoRule(ACall);
  end;
end;

procedure TPCEmitter.DoWriteVarargsReadType(const AFile: TPCOutFile; const ACall: TPCCall;
  const ASlot: Integer);
begin
  // The type a varargs local's next / get reads: the TypeArg, else the
  // argument at ASlot that names it (as size(T) writes it)
  if ACall.TypeArg <> nil then
    DoWriteType(AFile, ACall.TypeArg)
  else
  begin
    if ACall.Args.Count <= ASlot then
      DoMissing(AFile, 'varargs type');
    DoWriteExpr(AFile, ACall.Args[ASlot]);
  end;
end;

procedure TPCEmitter.DoWriteSpecial(const AFile: TPCOutFile; const ASpecial: TPCSpecial);
begin
  // self (*this), this, nullptr; parent only as a '.' member base
  // (DoWriteMember): SEM reports every other parent (SM0016), so one here is
  // an invariant
  case ASpecial.SpecialKind of
    skSelf:
      DoText(AFile, '(*this)');
    skThis:
      DoText(AFile, 'this');
    skNullptr:
      DoText(AFile, 'nullptr');
  else
    DoNoRule(ASpecial);
  end;
end;

procedure TPCEmitter.DoWriteBound(const AFile: TPCOutFile; const AExpr: TPCExpr);
begin
  // A set bound PaskalCPP did not fold, as the Int64 template argument
  // (a choices bound converts only explicitly)
  DoText(AFile, 'static_cast<std::int64_t>((');
  DoWriteExpr(AFile, AExpr);
  DoText(AFile, '))');
end;

procedure TPCEmitter.DoEmitTypeDecl(const AFile: TPCOutFile; const ADecl: TPCTypeDecl; const AModuleLevel: Boolean);
var
  LMark: TPCWriterMark;
  LKey: string;
  LSavedPacked: Boolean;
  LSavedCount: Integer;
  LNext: Integer;
begin
  // A5 / E5: module level in the file DoDeclInFile places it in (run), local
  // in place in the source
  DoBeginItem(AFile, ADecl.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  if ADecl.IsForward then
  begin
    // Completed by a record / object (struct) or an overlay (union)
    if ADecl.ResolvedFull = nil then
      DoMissing(AFile, 'forward type completion');
    if ADecl.ResolvedFull.TypeDef is TPCOverlayType then
      LKey := 'union'
    else
      LKey := 'struct';
    DoText(AFile, LKey + ' ' + ADecl.DeclName + ';');
  end
  else if ADecl.TypeDef is TPCRecordType then
    DoEmitRecord(AFile, ADecl, TPCRecordType(ADecl.TypeDef))
  else if ADecl.TypeDef is TPCOverlayType then
  begin
    DoText(AFile, 'union ' + ADecl.DeclName + ' {');
    // F35: the layout twins of this union (1) and of the anonymous overlays
    // inside it, then its zero member; the numbering is this type's own
    LSavedCount := FOverlayCount;
    LNext := 1;
    DoWriteOverlayLayouts(AFile, TPCOverlayType(ADecl.TypeDef).Members, True, LNext);
    FOverlayCount := 1;
    DoWriteOverlayZero(AFile);
    // An overlay is never packed; a packed anonymous record inside is (M9)
    LSavedPacked := FInPacked;
    FInPacked := False;
    DoEmitMembers(AFile, TPCOverlayType(ADecl.TypeDef).Members, True, AFile = ofSource);
    FInPacked := LSavedPacked;
    FOverlayCount := LSavedCount;
    DoPut(AFile, ADecl.TypeDef.Range.EndLine, '};');
  end
  else if ADecl.TypeDef is TPCChoicesType then
  begin
    // A local one was hoisted to the module's namespace (H3)
    if AModuleLevel then
      DoEmitChoices(AFile, ADecl, TPCChoicesType(ADecl.TypeDef))
    else
      DoText(AFile, 'using ' + ADecl.DeclName + ' = ::' + DoNamespaceName(FModule) + '::' +
        DoLocalChoicesName(TPCChoicesType(ADecl.TypeDef)) + ';');
  end
  else
  begin
    if ADecl.TypeDef = nil then
      DoMissing(AFile, 'type definition');
    DoText(AFile, 'using ' + ADecl.DeclName + ' = ');
    DoWriteType(AFile, ADecl.TypeDef);
    DoText(AFile, ';');
  end;
  FWriters[AFile].CloseSpan(LMark, ADecl);
end;

procedure TPCEmitter.DoEmitRecord(const AFile: TPCOutFile; const ADecl: TPCTypeDecl; const ARecord: TPCRecordType);
var
  LSavedRecord: TPCRecordType;
  LSavedName: string;
  LSavedPacked: Boolean;
  LSavedCount: Integer;
  LNext: Integer;
  LMark: TPCWriterMark;
  LBases: Integer;
  LFace: TPCNamedType;
begin
  // record / object: struct [[gnu::packed]] alignas((a)) N : Parent { ... };
  // an interface: struct N : virtual Parent { virtual R M(...) = 0; ... }
  // O13b: an object on a chain reaching C/C++ inside the override check
  if ARecord.ResolvedDerivesFromCpp then
    DoText(AFile, PC_EMT_OVERRIDE_CHECK_OPEN);
  DoText(AFile, 'struct');
  if ARecord.IsPacked then
    DoText(AFile, ' [[gnu::packed]]');
  if ARecord.AlignExpr <> nil then
  begin
    DoText(AFile, ' ');
    // The whole clause is the align value's text: clang reports an alignment
    // at the alignas keyword, which then maps to the value, where SEM's
    // SM0310 / SM0312 report too (F21; the value keeps its own span inside).
    // It starts on the value's line, so a value on a later line than the
    // record's head maps to that line (F28)
    DoAt(AFile, ARecord.AlignExpr.Range.StartLine);
    LMark := FWriters[AFile].Mark();
    DoText(AFile, 'alignas((');
    if DoNeedsValueCheck(ARecord) then
    begin
      // F31: a C++ value SEM could not fold is used only when it is a valid
      // align (else 1), so clang never refuses the clause in C++ words; the
      // checks in the body report SM0310 / SM0312
      DoWriteAlignValueOk(AFile, ARecord);
      DoText(AFile, ' ? (');
      DoWriteTypeConstant(AFile, ARecord.AlignExpr);
      DoText(AFile, ') : 1');
    end
    else
      DoWriteTypeConstant(AFile, ARecord.AlignExpr);
    DoText(AFile, '))');
    FWriters[AFile].CloseSpan(LMark, ARecord.AlignExpr);
    // SEM could not judge align(n) against the natural alignment (a C/C++
    // leaf, a C++ value): every leaf type joins the alignment, so clang never
    // fails in C++ words ('requested alignment is less than minimum'); the
    // check in the body judges it (r-b-align.md P3)
    if DoNeedsAlignCheck(ARecord) then
      DoWriteAlignLeaves(AFile, ARecord, True);
  end;
  DoText(AFile, ' ' + ADecl.DeclName);
  // PLAN-OBJECT D7: `final object` (SEM: no type names it as a parent)
  if ARecord.IsFinal then
    DoText(AFile, ' final');
  // PLAN-RECORDS M10: a record's PaskalCPP parent is its first member
  // (DoWriteRecordMarkers), never a base class; an object and a C/C++ parent
  // stay C++ base classes
  // PLAN-OBJECT O7 (user 2026-10-13): an interface base is always a VIRTUAL
  // base (an interface's parent, an object's implements names), so two
  // interfaces sharing a parent, or one named by an object and its parent,
  // are one part: the conversion to it is never ambiguous
  LBases := 0;
  if (ARecord.ParentName <> nil) and not ARecord.HasParentMember() then
  begin
    DoText(AFile, ' : ');
    if ARecord.IsInterface then
      DoText(AFile, 'virtual ');
    DoWriteType(AFile, ARecord.ParentName);
    Inc(LBases);
  end;
  for LFace in ARecord.Implements do
  begin
    if LBases = 0 then
      DoText(AFile, ' : virtual ')
    else
      DoText(AFile, ', virtual ');
    DoWriteType(AFile, LFace);
    Inc(LBases);
  end;
  DoText(AFile, ' {');
  if DoNeedsAlignCheck(ARecord) or DoNeedsValueCheck(ARecord) then
    DoWriteAlignCheck(AFile, ARecord);
  if not ARecord.IsObject then
    DoWriteRecordMarkers(AFile, ARecord);
  // F35: the layout twins of the record's anonymous overlays (none: nothing
  // written; an object holds none, PR0034); the numbering is this type's own
  LSavedCount := FOverlayCount;
  LNext := 1;
  DoWriteOverlayLayouts(AFile, ARecord.Members, False, LNext);
  FOverlayCount := 0;
  // An object written in the source (a local one, or a module-level one
  // placed there, E5) defines its methods in the class, each on its own
  // lines (the writer's lines only go forward: definitions after the class
  // would land on its last line); parent.M names this record's parent there
  // (H6)
  LSavedRecord := FRecord;
  LSavedName := FRecordName;
  LSavedPacked := FInPacked;
  FRecord := ARecord;
  FRecordName := ADecl.DeclName;
  FInPacked := ARecord.IsPacked;
  DoEmitMembers(AFile, ARecord.Members, False, AFile = ofSource);
  FRecord := LSavedRecord;
  FRecordName := LSavedName;
  FInPacked := LSavedPacked;
  FOverlayCount := LSavedCount;
  if ARecord.HasParentMember() then
    DoWriteParentConversions(AFile, ARecord);
  // Synthesized on the line of its construct: the type's end
  DoBeginItem(AFile, ARecord.Range.EndLine);
  // PLAN-OBJECT O7: an inherited method that implements an interface this
  // object names, from a level that does not derive from it (DoWriteForwards)
  DoWriteForwards(AFile, ARecord);
  // ... and an inherited property (O10)
  DoWritePropertyForwards(AFile, ARecord);
  // PLAN-OBJECT O5: copy and move as D5 says (DoWriteValueMembers)
  if ARecord.IsObject then
    DoWriteValueMembers(AFile, ADecl, ARecord);
  // PLAN-OBJECT D7: the root of a polymorphic chain destroys through its
  // vtable, so a descendant is never half destroyed through a base pointer.
  // A done of its own takes it over (D3: DoWriteDoneHead writes it
  // virtual). Every level below inherits it virtual
  if DoIsPolymorphicRoot(ARecord) and not DoHasDone(ARecord) then
    DoText(AFile, 'virtual ~' + ADecl.DeclName + '() = default; };')
  else
    DoText(AFile, '};');
  if ARecord.ResolvedDerivesFromCpp then
    DoText(AFile, PC_EMT_OVERRIDE_CHECK_CLOSE);
end;

procedure TPCEmitter.DoWritePropertyForwards(const AFile: TPCOutFile; const ARecord: TPCRecordType);
var
  LProperty: TPCPropertyItem;
  LWriter: TPCPropertyItem;
  LParent: string;
  LIndexName: string;
  LDepth: Integer;
begin
  // O10 (SEM's TPCRecordType.ResolvedPropertyForwards): an inherited
  // property that implements an interface property this object names, from
  // a level that does not derive from that interface, forwarded on the
  // type's end line (as DoWriteForwards' methods):
  //   T pcpp_get_X([idx]) const override { return Parent::pcpp_get_X([idx]); }
  //   void pcpp_set_X([idx, ]T pcpp_pv) override { Parent::pcpp_set_X([idx, ]std::move(pcpp_pv)); }
  // the write when it has one (its own or the overridden one's: that level's
  // ResolvedOverrides is written). Borrowed spellings: the property's own
  // nodes keep their spans
  for LProperty in ARecord.ResolvedPropertyForwards do
  begin
    if ARecord.ParentName = nil then
      DoMissing(AFile, 'forwarded property');
    LParent := DoTypeName(ARecord.ParentName);
    LIndexName := '';
    if LProperty.IndexParam <> nil then
      LIndexName := LProperty.IndexParam.ParamName;
    FWriters[AFile].BeginBorrowed();
    try
      DoText(AFile, ' ');
      DoWriteType(AFile, LProperty.TypeExpr);
      DoText(AFile, ' ' + PC_EMT_PROP_GET + LProperty.PropName + '(');
      if LProperty.IndexParam <> nil then
        DoWriteParam(AFile, LProperty.IndexParam, True);
      DoText(AFile, ') const override { return ' + LParent + '::' + PC_EMT_PROP_GET + LProperty.PropName + '(' +
        LIndexName + '); }');
      LWriter := LProperty;
      LDepth := 0;
      while (LWriter <> nil) and (LWriter.WriteItem = nil) and (LDepth < 256) do
      begin
        LWriter := LWriter.ResolvedOverrides;
        Inc(LDepth);
      end;
      if (LWriter <> nil) and (LWriter.WriteItem <> nil) then
      begin
        DoText(AFile, ' void ' + PC_EMT_PROP_SET + LProperty.PropName + '(');
        if LProperty.IndexParam <> nil then
        begin
          DoWriteParam(AFile, LProperty.IndexParam, True);
          DoText(AFile, ', ');
          LIndexName := LIndexName + ', ';
        end;
        DoWriteType(AFile, LProperty.TypeExpr);
        DoText(AFile, ' ' + PC_EMT_PROP_VALUE + ') override { ' + LParent + '::' + PC_EMT_PROP_SET +
          LProperty.PropName + '(' + LIndexName + 'std::move(' + PC_EMT_PROP_VALUE + ')); }');
      end;
    finally
      FWriters[AFile].EndBorrowed();
    end;
  end;
end;

procedure TPCEmitter.DoWriteForwards(const AFile: TPCOutFile; const ARecord: TPCRecordType);
var
  LItem: TPCMethodItem;
  LForward: TPCEmbedForward;
  LEmbed: TPCField;
  LTarget: string;
begin
  // O7 (SEM's TPCRecordType.ResolvedForwards): `R M(params) override {
  // return Parent::M(args); }` on the type's end line. C++ makes a method an
  // interface's overrider only in a class that derives from the interface;
  // this one does, and calls the inherited method, so a call through the
  // interface runs what PaskalCPP named. A value parameter is moved on (a
  // move-only object may be one), var / const ones are passed as they are.
  // Borrowed spellings: the method's own node keeps its spans
  for LItem in ARecord.ResolvedForwards do
  begin
    if (LItem.Routine = nil) or (ARecord.ParentName = nil) then
      DoMissing(AFile, 'forwarded method');
    DoText(AFile, ' ');
    FWriters[AFile].BeginBorrowed();
    try
      DoWriteSignature(AFile, LItem.Routine, False, '');
    finally
      FWriters[AFile].EndBorrowed();
    end;
    DoText(AFile, ' override { return ');
    DoWriteBorrowedType(AFile, ARecord.ParentName);
    DoText(AFile, '::' + LItem.Routine.DeclName + '(' + DoForwardArgs(LItem.Routine) + '); }');
  end;
  // PLAN-OBJECT O8 (D2): an interface method an embed provides (SEM's
  // ResolvedEmbedForwards): `R M(params) override { return this->F.G.M(args);
  // }`; the embedded method needs no dispatch of its own
  for LForward in ARecord.ResolvedEmbedForwards do
  begin
    LTarget := 'this->';
    for LEmbed in LForward.Path do
      LTarget := LTarget + LEmbed.FieldName + '.';
    DoWriteForward(AFile, LForward.Method, LTarget);
  end;
end;

procedure TPCEmitter.DoWriteForward(const AFile: TPCOutFile; const AItem: TPCMethodItem; const ATarget: string);
begin
  // One forwarding override on the type's end line: ATarget + the method's
  // name; the signature is a borrowed spelling (the method keeps its spans)
  if (AItem = nil) or (AItem.Routine = nil) then
    DoMissing(AFile, 'forwarded method');
  DoText(AFile, ' ');
  FWriters[AFile].BeginBorrowed();
  try
    DoWriteSignature(AFile, AItem.Routine, False, '');
  finally
    FWriters[AFile].EndBorrowed();
  end;
  DoText(AFile, ' override { return ' + ATarget + AItem.Routine.DeclName + '(' +
    DoForwardArgs(AItem.Routine) + '); }');
end;

class function TPCEmitter.DoForwardArgs(const ARoutine: TPCRoutine): string;
var
  LParam: TPCParam;
begin
  // A forwarding override's arguments: a value parameter is moved on (a
  // move-only object may be one), var / const ones are passed as they are
  Result := '';
  for LParam in ARoutine.Params do
  begin
    if Result <> '' then
      Result := Result + ', ';
    if LParam.ParamMode in [pmVar, pmConst] then
      Result := Result + LParam.ParamName
    else
      Result := Result + 'std::move(' + LParam.ParamName + ')';
  end;
end;

procedure TPCEmitter.DoWriteEmbedPath(const AFile: TPCOutFile; const AMember: TPCMember);
var
  LEmbed: TPCField;
begin
  // PLAN-OBJECT O8 (D2): a promoted member is written through the embeds SEM
  // walked (TPCMember.ResolvedEmbedPath), `F.G.`, then the member parents of
  // the last embedded type (ResolvedParentHops). No span: no node owns them
  for LEmbed in AMember.ResolvedEmbedPath do
    DoText(AFile, LEmbed.FieldName + '.');
end;

class function TPCEmitter.DoChainHasValueOps(const ARecord: TPCRecordType): Boolean;
var
  LLevel: TPCTypeExpr;
  LVisited: TList<TPCTypeExpr>;
begin
  // O5: the object, or a PaskalCPP object level above it, declares a done or
  // a copy: its copy and move members are written (DoWriteValueMembers),
  // never left to C++'s implicit rules (which a done or a copy changes)
  Result := False;
  LVisited := TList<TPCTypeExpr>.Create();
  try
    LLevel := ARecord;
    while (LLevel is TPCRecordType) and TPCRecordType(LLevel).IsObject and not LVisited.Contains(LLevel) do
    begin
      LVisited.Add(LLevel);
      if (TPCRecordType(LLevel).OwnDone() <> nil) or (TPCRecordType(LLevel).OwnCopy() <> nil) then
        Exit(True);
      if (TPCRecordType(LLevel).ParentName = nil) or TPCTypeExpr.IsOpaqueTier(TPCRecordType(LLevel).ParentName) then
        Exit;
      LLevel := TPCRecordType(LLevel).ParentName.Canon();
    end;
  finally
    LVisited.Free();
  end;
end;

procedure TPCEmitter.DoWriteValueMembers(const AFile: TPCOutFile; const ADecl: TPCTypeDecl;
  const ARecord: TPCRecordType);
var
  LName: string;
  LDone: TPCDoneItem;
  LMoveOnly: Boolean;
  LMember: TPCMemberItem;
  LField: TPCField;
begin
  // PLAN-OBJECT O5 (D5), on the type's end line, for an object whose chain
  // declares a done or a copy (DoChainHasValueOps; every other object keeps
  // C++'s implicit members): its ::pcpp::Live (a done of its own); T() when
  // it declares no init (a written constructor would hide C++'s); the copy
  // constructor deleted when it cannot be copied (TPCRecordType.MoveOnlyReason,
  // SEM's one rule), the person's copy (a member item) or defaulted; the copy
  // assignment deleted (cannot be copied, or abstract: no temporary of it),
  // else copy-and-swap through the move assignment (exception-safe, self
  // safe); the move constructor defaulted (Live leaves the source not live);
  // the move assignment defaulted, or with a done of its own a swap of its
  // parts (the parent part by the parent's own move assignment): the old
  // value leaves in the source and its done runs when the source ends
  if not DoChainHasValueOps(ARecord) then
    Exit;
  LName := ADecl.DeclName;
  LDone := ARecord.OwnDone();
  LMoveOnly := ARecord.MoveOnlyReason() <> nil;
  if LDone <> nil then
    DoText(AFile, '::pcpp::Live ' + PC_EMT_LIVE_MEMBER + '; ');
  if not DoHasInits(ARecord) then
    DoText(AFile, LName + '() = default; ');
  if LMoveOnly then
    DoText(AFile, LName + '(const ' + LName + '&) = delete; ')
  else if ARecord.OwnCopy() = nil then
    DoText(AFile, LName + '(const ' + LName + '&) = default; ');
  if LMoveOnly or (ARecord.ResolvedAbstract <> nil) then
    DoText(AFile, LName + '& operator=(const ' + LName + '&) = delete; ')
  else
    DoText(AFile, LName + '& operator=(const ' + LName + '& ' + PC_EMT_MOVE_SOURCE + ') { if (this != &' +
      PC_EMT_MOVE_SOURCE + ') { ' + LName + ' ' + PC_EMT_MOVE_TEMP + '(' + PC_EMT_MOVE_SOURCE + '); *this = std::move(' +
      PC_EMT_MOVE_TEMP + '); } return *this; } ');
  DoText(AFile, LName + '(' + LName + '&&) = default; ');
  if LDone = nil then
  begin
    DoText(AFile, LName + '& operator=(' + LName + '&&) = default; ');
    Exit;
  end;
  DoText(AFile, LName + '& operator=(' + LName + '&& ' + PC_EMT_MOVE_SOURCE + ') { ');
  if ARecord.ParentName <> nil then
  begin
    DoWriteBorrowedType(AFile, ARecord.ParentName);
    DoText(AFile, '::operator=(std::move(' + PC_EMT_MOVE_SOURCE + ')); ');
  end;
  DoText(AFile, 'using std::swap; ');
  for LMember in ARecord.Members do
  begin
    if not (LMember is TPCField) then
      Continue;
    LField := TPCField(LMember);
    // A bitfield binds no reference: swapped through a copy
    if LField.BitWidthExpr <> nil then
      DoText(AFile, '{ auto pcpp_b = this->' + LField.FieldName + '; this->' + LField.FieldName + ' = ' +
        PC_EMT_MOVE_SOURCE + '.' + LField.FieldName + '; ' + PC_EMT_MOVE_SOURCE + '.' + LField.FieldName +
        ' = pcpp_b; } ')
    else
      DoText(AFile, 'swap(this->' + LField.FieldName + ', ' + PC_EMT_MOVE_SOURCE + '.' + LField.FieldName + '); ');
  end;
  DoText(AFile, 'swap(this->' + PC_EMT_LIVE_MEMBER + ', ' + PC_EMT_MOVE_SOURCE + '.' + PC_EMT_LIVE_MEMBER +
    '); return *this; } ');
end;

class function TPCEmitter.DoIsPolymorphicRoot(const ARecord: TPCRecordType): Boolean;
var
  LParent: TPCTypeExpr;
begin
  // SEM's ResolvedIsPolymorphic, at the level whose PaskalCPP parent is not
  // polymorphic (no parent, a C/C++ base, a parent without a vtable)
  Result := ARecord.IsObject and ARecord.ResolvedIsPolymorphic;
  if (not Result) or (ARecord.ParentName = nil) then
    Exit;
  LParent := ARecord.ParentName.Canon();
  if (LParent is TPCRecordType) and TPCRecordType(LParent).IsObject and TPCRecordType(LParent).ResolvedIsPolymorphic then
    Result := False;
end;

procedure TPCEmitter.DoWriteRecordMarkers(const AFile: TPCOutFile; const ARecord: TPCRecordType);
begin
  // PLAN-RECORDS M12 (3), runtime "Record extensions": every record says it
  // is one; an extension names its parent and holds it as the first member
  // pcpp_parent (M10: the parent type's own span is there); a record with a
  // C/C++ parent names that base (it stays a C++ base class)
  DoText(AFile, ' ' + PC_EMT_RECORD_MARKER);
  if ARecord.ParentName = nil then
    Exit;
  if ARecord.HasParentMember() then
  begin
    DoText(AFile, ' using ' + PC_EMT_PARENT_TYPE_MARKER + ' = ');
    DoWriteBorrowedType(AFile, ARecord.ParentName);
    DoText(AFile, '; ');
    DoWriteType(AFile, ARecord.ParentName);
    // Plain data (M9): no initializer, every creation site value-initializes
    DoText(AFile, ' ' + PC_EMT_PARENT_MEMBER + ';');
    if ARecord.IsPacked then
      DoWritePackedCheck(AFile, ARecord.ParentName, ARecord.ParentName);
  end
  else if TPCTypeExpr.IsOpaqueTier(ARecord.ParentName) then
  begin
    DoText(AFile, ' using ' + PC_EMT_CPP_BASE_MARKER + ' = ');
    DoWriteBorrowedType(AFile, ARecord.ParentName);
    DoText(AFile, ';');
  end;
end;

procedure TPCEmitter.DoWriteParentConversions(const AFile: TPCOutFile; const ARecord: TPCRecordType);
var
  LLevel: TPCRecordType;
  LParentName: TPCNamedType;
  LHops: Integer;
  LPath: string;
  LVisited: TList<TPCRecordType>;
begin
  // PLAN-RECORDS M10: what C++ inheritance gave a value / const / var upcast,
  // as conversion operators to every member-parent level, on the record's
  // last line (synthesized code goes on the line of its construct). A part
  // that may sit misaligned (a packed level on the way, F-R4f) converts by
  // value, copied out (every level's parent is at offset 0); any other by
  // reference
  LLevel := ARecord;
  LHops := 0;
  LPath := '';
  LVisited := TList<TPCRecordType>.Create();
  try
    while (LLevel <> nil) and LLevel.HasParentMember() and not LVisited.Contains(LLevel) do
    begin
      LVisited.Add(LLevel);
      LParentName := LLevel.ParentName;
      Inc(LHops);
      LPath := LPath + '.' + PC_EMT_PARENT_MEMBER;
      DoBeginItem(AFile, ARecord.Range.EndLine);
      if ARecord.ParentPartMayBeMisaligned(LHops) then
      begin
        DoText(AFile, 'operator ');
        DoWriteBorrowedType(AFile, LParentName);
        DoText(AFile, '() const noexcept { ');
        DoWriteBorrowedType(AFile, LParentName);
        DoText(AFile, ' ' + PC_EMT_PARENT_COPY + '; ::std::memcpy(static_cast<void*>(&' + PC_EMT_PARENT_COPY +
          '), this, sizeof ' + PC_EMT_PARENT_COPY + '); return ' + PC_EMT_PARENT_COPY + '; }');
      end
      else
      begin
        DoText(AFile, 'operator ');
        DoWriteBorrowedType(AFile, LParentName);
        DoText(AFile, '&() noexcept { return this->' + LPath.Substring(1) + '; } operator const ');
        DoWriteBorrowedType(AFile, LParentName);
        DoText(AFile, '&() const noexcept { return this->' + LPath.Substring(1) + '; }');
      end;
      LLevel := LLevel.ParentRecord();
    end;
  finally
    LVisited.Free();
  end;
end;

function TPCEmitter.DoNeedsAlignCheck(const ARecord: TPCRecordType): Boolean;
begin
  // The complement of what SEM judges (DoCheckNaturalAlign: a known natural
  // alignment and a folded value): an align clause on a record that is not
  // packed (packed takes any align, P2) whose natural alignment SEM did not
  // know (ResolvedNaturalAlign 0: a C/C++ leaf) or whose value it did not
  // fold (a C++ value). clang computes both; the check reports in PaskalCPP
  // words (PC_FRONTEND_CHECK_NATURAL)
  Result := (ARecord.AlignExpr <> nil) and (not ARecord.IsPacked) and
    ((ARecord.ResolvedNaturalAlign = 0) or (not ARecord.AlignExpr.HasConstValue));
end;

function TPCEmitter.DoNeedsValueCheck(const ARecord: TPCRecordType): Boolean;
begin
  // F31: an align value SEM did not fold (a C++ value) is judged by the
  // emitted checks, packed or not: a power of two (SM0310) at most
  // PC_ALIGN_MAX (SM0312), as SEM judges a folded one (DoCheckAlign)
  Result := (ARecord.AlignExpr <> nil) and (not ARecord.AlignExpr.HasConstValue);
end;

procedure TPCEmitter.DoWriteAlignValue(const AFile: TPCOutFile; const ARecord: TPCRecordType);
var
  LText: string;
begin
  // '(v)': the value again, a second spelling (no span): SEM's folded text,
  // else the C++ value as written
  DoText(AFile, '(');
  if TPCAst.FoldedText(ARecord.AlignExpr, LText) then
    DoText(AFile, LText)
  else
    DoWriteBorrowedExpr(AFile, ARecord.AlignExpr);
  DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteAlignValuePower(const AFile: TPCOutFile; const ARecord: TPCRecordType);
begin
  // (v) > 0 && ((v) & ((v) - 1)) == 0: exactly one bit set (SEM's rule);
  // && stops at a value at or below 0, so the bit test never sees one
  DoWriteAlignValue(AFile, ARecord);
  DoText(AFile, ' > 0 && (');
  DoWriteAlignValue(AFile, ARecord);
  DoText(AFile, ' & (');
  DoWriteAlignValue(AFile, ARecord);
  DoText(AFile, ' - 1)) == 0');
end;

procedure TPCEmitter.DoWriteAlignValueOk(const AFile: TPCOutFile; const ARecord: TPCRecordType);
begin
  // A valid align on every target: a power of two at most PC_ALIGN_MAX
  DoWriteAlignValuePower(AFile, ARecord);
  DoText(AFile, ' && ');
  DoWriteAlignValue(AFile, ARecord);
  DoText(AFile, ' <= ' + IntToStr(PC_ALIGN_MAX));
end;

procedure TPCEmitter.DoWriteAlignLeaf(const AFile: TPCOutFile; const AType: TPCTypeExpr; const AWChar16: Boolean;
  const AAsAlignas: Boolean; var AFirst: Boolean);
begin
  // One leaf type, a second spelling of a type the record already writes
  // (borrowed: no span): ' alignas(T)' in the head, 'T' in the check's list
  if AAsAlignas then
    DoText(AFile, ' alignas(')
  else if not AFirst then
    DoText(AFile, ', ');
  AFirst := False;
  if AWChar16 then
    DoText(AFile, 'char16_t')
  else
    DoWriteBorrowedType(AFile, AType);
  if AAsAlignas then
    DoText(AFile, ')');
end;

procedure TPCEmitter.DoWriteAlignMembers(const AFile: TPCOutFile; const AMembers: TList<TPCMemberItem>;
  const AAsAlignas: Boolean; var AFirst: Boolean);
var
  LMember: TPCMemberItem;
begin
  // The fields in order, an anonymous aggregate's members taken recursively
  // (a union's too, P3); a packed anonymous record counts 1, so it adds no
  // leaf; a method has no layout
  for LMember in AMembers do
  begin
    if LMember is TPCField then
      DoWriteAlignLeaf(AFile, TPCField(LMember).TypeExpr, TPCField(LMember).IsWCharBitfield(),
        AAsAlignas, AFirst)
    else if LMember is TPCAnonAggregate then
    begin
      if not TPCAnonAggregate(LMember).IsPacked then
        DoWriteAlignMembers(AFile, TPCAnonAggregate(LMember).Members, AAsAlignas, AFirst);
    end;
  end;
end;

procedure TPCEmitter.DoWriteAlignLeaves(const AFile: TPCOutFile; const ARecord: TPCRecordType;
  const AAsAlignas: Boolean);
var
  LFirst: Boolean;
begin
  // The record's leaf types, the r-b natural alignment rule's order: the
  // parent, then the members
  LFirst := True;
  if ARecord.ParentName <> nil then
    DoWriteAlignLeaf(AFile, ARecord.ParentName, False, AAsAlignas, LFirst);
  DoWriteAlignMembers(AFile, ARecord.Members, AAsAlignas, LFirst);
end;

procedure TPCEmitter.DoWriteAlignCheck(const AFile: TPCOutFile; const ARecord: TPCRecordType);
var
  LMark: TPCWriterMark;
  LText: string;
begin
  // The checks as the first members (r-b-align.md P4 / P5), in SEM's order:
  // a C++ value a power of two (SM0310), then at most PC_ALIGN_MAX (SM0312,
  // only for a power of two: one report per value, as DoCheckAlign), then
  // not below the natural alignment (SM0311, only for a valid value: an
  // invalid one compares as PC_ALIGN_MAX, which passes). All of it is a
  // second span of the align value: the frontend finds the record from where
  // clang reports a failure (TPCAst.AlignRecordAt) and reports at the value.
  // Its texts are second spellings (no span of their own)
  DoText(AFile, ' ');
  LMark := FWriters[AFile].Mark();
  if DoNeedsValueCheck(ARecord) then
  begin
    DoText(AFile, 'static_assert(');
    DoWriteAlignValuePower(AFile, ARecord);
    DoText(AFile, ', "' + PC_FRONTEND_CHECK_POWER + '"); static_assert(!(');
    DoWriteAlignValuePower(AFile, ARecord);
    DoText(AFile, ') || ');
    DoWriteAlignValue(AFile, ARecord);
    DoText(AFile, ' <= ' + IntToStr(PC_ALIGN_MAX) + ', "' + PC_FRONTEND_CHECK_MAX + '");');
  end;
  if DoNeedsAlignCheck(ARecord) then
  begin
    if TPCAst.FoldedText(ARecord.AlignExpr, LText) then
      // A folded value: 'static_assert((n' + ') >= ...' (the fold opens with
      // the parenthesis that closes the value); the span's first text
      DoText(AFile, 'static_assert((' + LText)
    else
    begin
      // A C++ value, guarded as the clause takes it, after the value checks
      DoText(AFile, ' static_assert((');
      DoWriteAlignValueOk(AFile, ARecord);
      DoText(AFile, ' ? ');
      DoWriteAlignValue(AFile, ARecord);
      DoText(AFile, ' : ' + IntToStr(PC_ALIGN_MAX));
    end;
    DoText(AFile, PC_EMT_ALIGN_CHECK_FOLD);
    DoWriteAlignLeaves(AFile, ARecord, False);
    DoText(AFile, '>(), "' + PC_FRONTEND_CHECK_NATURAL + '");');
  end;
  FWriters[AFile].CloseSpan(LMark, ARecord.AlignExpr);
end;

procedure TPCEmitter.DoEmitMembers(const AFile: TPCOutFile; const AMembers: TList<TPCMemberItem>;
  const AInUnion: Boolean; const AInClass: Boolean);
var
  LMember: TPCMemberItem;
  LHidden: Boolean;
begin
  // One member per line, each on its own .pcpp line; AInClass = a type
  // written in the source (local, or placed there, E5), whose methods are
  // defined in the class (H4). PLAN-OBJECT D10: a hidden member is C++
  // protected: a label on its line where the access changes (a struct starts
  // public), public again after the last one, so what the emitter adds after
  // the members (pcpp_record, conversions) stays public
  LHidden := False;
  for LMember in AMembers do
  begin
    if (not (LMember is TPCAnonAggregate)) and (LMember.IsHidden <> LHidden) then
    begin
      LHidden := LMember.IsHidden;
      DoBeginItem(AFile, LMember.Range.StartLine);
      if LHidden then
        DoText(AFile, 'protected:')
      else
        DoText(AFile, 'public:');
    end;
    if LMember is TPCField then
      DoEmitField(AFile, TPCField(LMember), AInUnion)
    else if LMember is TPCAnonAggregate then
      DoEmitAnonAggregate(AFile, TPCAnonAggregate(LMember), AInUnion, AInClass)
    else if LMember is TPCMethodItem then
      DoEmitMethodItem(AFile, TPCMethodItem(LMember), AInClass)
    else if LMember is TPCInitItem then
      DoEmitInitItem(AFile, TPCInitItem(LMember), AInClass)
    else if LMember is TPCDoneItem then
      DoEmitDoneItem(AFile, TPCDoneItem(LMember), AInClass)
    else if LMember is TPCPropertyItem then
      DoEmitProperty(AFile, TPCPropertyItem(LMember), AInClass, LHidden)
    else if LMember is TPCOperatorItem then
      DoEmitOperatorItem(AFile, TPCOperatorItem(LMember), AInClass)
    else
      DoNoRule(LMember);
  end;
  if LHidden then
    DoText(AFile, ' public:');
end;

procedure TPCEmitter.DoEmitProperty(const AFile: TPCOutFile; const AProperty: TPCPropertyItem;
  const AInClass: Boolean; var AHidden: Boolean);
begin
  // PLAN-OBJECT O9 / D12: the read, then the write, each on its own lines
  // (the label loop set the property's access: its read's); a `hidden
  // write` changes the access for the write alone
  if AProperty.ReadItem = nil then
    DoMissing(AFile, 'property read');
  DoEmitAccessor(AFile, AProperty, AProperty.ReadItem, AInClass);
  if AProperty.WriteItem = nil then
    Exit;
  if AProperty.WriteItem.IsHidden <> AHidden then
  begin
    AHidden := AProperty.WriteItem.IsHidden;
    DoBeginItem(AFile, AProperty.WriteItem.Range.StartLine);
    if AHidden then
      DoText(AFile, 'protected:')
    else
      DoText(AFile, 'public:');
  end;
  DoEmitAccessor(AFile, AProperty, AProperty.WriteItem, AInClass);
end;

procedure TPCEmitter.DoEmitAccessor(const AFile: TPCOutFile; const AProperty: TPCPropertyItem;
  const AAccessor: TPCAccessorItem; const AInClass: Boolean);
var
  LMark: TPCWriterMark;
begin
  // In the struct: its head, then `;` (defined in the source:
  // DoEmitMethodDefs) or, for a type written in the source, its body (H4)
  DoBeginItem(AFile, AAccessor.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  DoWriteAccessorHead(AFile, AProperty, AAccessor, '');
  // O10: an abstract accessor has no body to define (as a method's, D7)
  if AAccessor.IsAbstract then
    DoText(AFile, ' = 0;')
  else if AInClass then
    DoEmitAccessorBody(AProperty, AAccessor)
  else
    DoText(AFile, ';');
  DoCloseAccessorSpan(AFile, LMark, AAccessor);
end;

procedure TPCEmitter.DoCloseAccessorSpan(const AFile: TPCOutFile; const AMark: TPCWriterMark;
  const AAccessor: TPCAccessorItem);
begin
  // An inline accessor's text is its routine's (as a method's); a binding's
  // is the accessor item's
  if AAccessor.Routine <> nil then
    FWriters[AFile].CloseSpan(AMark, AAccessor.Routine)
  else
    FWriters[AFile].CloseSpan(AMark, AAccessor);
end;

procedure TPCEmitter.DoWriteAccessorHead(const AFile: TPCOutFile; const AProperty: TPCPropertyItem;
  const AAccessor: TPCAccessorItem; const AOwner: string);
begin
  // read:  T const& [Owner::]pcpp_get_X() const   (TPCPropertyItem.ReadsByReference:
  //                                                a binding not dispatched, zero cost)
  //        T [Owner::]pcpp_get_X([idx]) const     (every other read: the value)
  // write: void [Owner::]pcpp_set_X([idx, ]T v)   (v = the person's name, pcpp_pv
  //                                                for a binding or an abstract write)
  // In the class (AOwner = '') a dispatched property's accessors carry the
  // words (PLAN-OBJECT O10, as a method's D7): virtual, override (an override,
  // or the implementer of an interface property), final, = 0 (an abstract
  // accessor). The read owns the type's and the index's spans; the write
  // borrows them (one node, one span per file)
  if (AOwner = '') and AProperty.IsVirtual then
    DoText(AFile, 'virtual ');
  if AAccessor.IsWrite then
  begin
    DoText(AFile, 'void ');
    if AOwner <> '' then
      DoText(AFile, AOwner + '::');
    DoText(AFile, PC_EMT_PROP_SET + AProperty.PropName + '(');
    if AProperty.IndexParam <> nil then
    begin
      FWriters[AFile].BeginBorrowed();
      try
        DoWriteParam(AFile, AProperty.IndexParam, True);
      finally
        FWriters[AFile].EndBorrowed();
      end;
      DoText(AFile, ', ');
    end;
    DoWriteBorrowedType(AFile, AProperty.TypeExpr);
    if AAccessor.IsBinding() or AAccessor.IsAbstract then
      DoText(AFile, ' ' + PC_EMT_PROP_VALUE + ')')
    else
    begin
      if AAccessor.Routine.Params.Count < 1 then
        DoMissing(AFile, 'write value');
      DoText(AFile, ' ' + AAccessor.Routine.Params[AAccessor.Routine.Params.Count - 1].ParamName + ')');
    end;
  end
  else
  begin
    DoWriteType(AFile, AProperty.TypeExpr);
    if AProperty.ReadsByReference() then
      DoText(AFile, ' const&');
    DoText(AFile, ' ');
    if AOwner <> '' then
      DoText(AFile, AOwner + '::');
    DoText(AFile, PC_EMT_PROP_GET + AProperty.PropName + '(');
    if AProperty.IndexParam <> nil then
      DoWriteParam(AFile, AProperty.IndexParam, True);
    DoText(AFile, ') const');
  end;
  if AOwner <> '' then
    Exit;
  if AProperty.IsOverride or (AProperty.ResolvedImplements <> nil) then
    DoText(AFile, ' override');
  if AProperty.IsFinal then
    DoText(AFile, ' final');
end;

procedure TPCEmitter.DoEmitAccessorDef(const AProperty: TPCPropertyItem; const AAccessor: TPCAccessorItem;
  const AOwner: string);
var
  LMark: TPCWriterMark;
begin
  // An accessor's definition in the source, on its own lines (H4); nil = a
  // read-only property's absent write; an abstract one has none (O10)
  if (AAccessor = nil) or AAccessor.IsAbstract then
    Exit;
  DoBeginItem(ofSource, AAccessor.Range.StartLine);
  LMark := FWriters[ofSource].Mark();
  DoWriteAccessorHead(ofSource, AProperty, AAccessor, AOwner);
  DoEmitAccessorBody(AProperty, AAccessor);
  DoCloseAccessorSpan(ofSource, LMark, AAccessor);
end;

procedure TPCEmitter.DoEmitAccessorBody(const AProperty: TPCPropertyItem; const AAccessor: TPCAccessorItem);
begin
  // A binding reads / writes its field (SEM's ResolvedField); an inline one
  // is its routine's body (DoEmitRoutineBody: ' {' .. '}' on its last line)
  if not AAccessor.IsBinding() then
  begin
    DoEmitRoutineBody(AAccessor.Routine);
    Exit;
  end;
  if AAccessor.ResolvedField = nil then
    DoMissing(ofSource, 'bound field');
  if AAccessor.IsWrite then
    DoText(ofSource, ' { this->' + AAccessor.ResolvedField.FieldName + ' = std::move(' + PC_EMT_PROP_VALUE + '); }')
  else
    DoText(ofSource, ' { return this->' + AAccessor.ResolvedField.FieldName + '; }');
end;

procedure TPCEmitter.DoEmitField(const AFile: TPCOutFile; const AField: TPCField; const AInUnion: Boolean);
var
  LMark: TPCWriterMark;
  LTypeMark: TPCWriterMark;
begin
  // T F; or T F : (w). A record's field has no initializer (PLAN-RECORDS
  // M9: plain data, so it packs as written; every creation site
  // value-initializes, r4b). An object's keeps T F{} (zeroed; PLAN-OBJECT
  // owns its form), except in a union: a C++ union allows at most one member
  // with one, and an anonymous struct member with them would delete the
  // union's default constructor
  DoBeginItem(AFile, AField.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  if AField.IsWCharBitfield() then
  begin
    // F25: a wchar bitfield holds 0 .. 2^w - 1 on every target, as on the
    // reference target (wchar_t unsigned 16-bit); Linux's wchar_t is signed
    // 32-bit and would sign-extend the field. char16_t is unsigned 16-bit
    // everywhere, holds every width 1 .. 16 (SM0315) and converts to
    // wchar_t implicitly; an alias of wchar is the same field
    LTypeMark := FWriters[AFile].Mark();
    DoText(AFile, 'char16_t');
    FWriters[AFile].CloseSpan(LTypeMark, AField.TypeExpr);
  end
  else if AField.IsChoicesBitfield() then
  begin
    // F37: a choices bitfield is stored as the type's underlying integer
    // (same size, alignment and signedness, so the layout is the enum's):
    // clang's constant-store check reads a scoped-enum bitfield as unsigned
    // and reports a value change that does not happen. Reads and stores
    // cast (DoWriteExprAs, DoWriteChoicesStore)
    LTypeMark := FWriters[AFile].Mark();
    DoText(AFile, DoChoicesUnderlying(TPCChoicesType(AField.TypeExpr.Canon())));
    FWriters[AFile].CloseSpan(LTypeMark, AField.TypeExpr);
  end
  else
    DoWriteType(AFile, AField.TypeExpr);
  DoText(AFile, ' ' + AField.FieldName);
  if AField.BitWidthExpr <> nil then
  begin
    DoText(AFile, ' : (');
    DoWriteTypeConstant(AFile, AField.BitWidthExpr);
    DoText(AFile, ')');
  end
  else if (not AInUnion) and (FRecord <> nil) and FRecord.IsObject and
    not ((AField.TypeExpr <> nil) and (AField.TypeExpr.Canon() is TPCRecordType) and
    TPCRecordType(AField.TypeExpr.Canon()).ResolvedNeedsInitArgs) then
    // PLAN-OBJECT D3: a field whose object type takes init arguments gets no
    // `{}` (no constructor takes none): every init builds it in its member
    // initializers (SEM: SM0347)
    DoText(AFile, '{}');
  DoText(AFile, ';');
  FWriters[AFile].CloseSpan(LMark, AField);
  // A bitfield packs as bits: no layout question
  if FInPacked and (AField.BitWidthExpr = nil) then
    DoWritePackedCheck(AFile, AField.TypeExpr, AField);
  // A bitfield's type is an integer or choices: trivial data
  if AInUnion and (AField.BitWidthExpr = nil) then
    DoWriteOverlayCheck(AFile, AField);
end;

procedure TPCEmitter.DoWriteOverlayCheck(const AFile: TPCOutFile; const AField: TPCField);
var
  LMark: TPCWriterMark;
begin
  // PLAN-COMPLIANCE F34: a union member's type only clang knows (a C/C++
  // leaf, a C/C++ parent: TPCOverlayFit ofClangDecides) must be trivial
  // data, ::pcpp::fits_overlay: the check names ::pcpp::overlay_check of it
  // (deprecated "pcpp:SM0313" when it does not fit) in a fatal region
  // (PC_EMT_OVERLAY_CHECK_*), a second span of the field; the frontend
  // reports a failure as SM0313 there (TPCAst.FieldCheckAt) and clang stops
  // before the union's deleted members. A static_assert names it: the one
  // declaration an anonymous struct / union takes. SEM already judged every
  // other type (ofNeverFits = SM0313 / SM0357, so none reaches here)
  if (AField.TypeExpr = nil) or (AField.TypeExpr.OverlayFit() <> ofClangDecides) then
    Exit;
  DoText(AFile, ' ');
  LMark := FWriters[AFile].Mark();
  DoText(AFile, PC_EMT_OVERLAY_CHECK_OPEN + 'static_assert(sizeof(::pcpp::overlay_check<::pcpp::fits_overlay<');
  DoWriteBorrowedType(AFile, AField.TypeExpr);
  DoText(AFile, '>>) != 0);' + PC_EMT_OVERLAY_CHECK_CLOSE);
  FWriters[AFile].CloseSpan(LMark, AField);
end;

procedure TPCEmitter.DoWriteOverlayLayouts(const AFile: TPCOutFile; const AMembers: TList<TPCMemberItem>;
  const AIsOverlay: Boolean; var ANext: Integer);
var
  LMember: TPCMemberItem;
  LAggregate: TPCAnonAggregate;
begin
  // F35 (PC_EMT_OVERLAY_LAYOUT): the layout twin of every union of one named
  // type, in preorder: AMembers' own union first (AIsOverlay: the named
  // overlay, an anonymous one), then the anonymous overlays inside its
  // members, numbered as the emission meets them (DoEmitTypeDecl,
  // DoEmitAnonAggregate). Written on the type's head line as nested types of
  // the named type; none for a type that holds no union
  if AIsOverlay then
  begin
    DoText(AFile, ' union ' + PC_EMT_OVERLAY_LAYOUT + IntToStr(ANext) + ' {');
    Inc(ANext);
    DoWriteLayoutMembers(AFile, AMembers);
    DoText(AFile, ' };');
  end;
  for LMember in AMembers do
  begin
    if not (LMember is TPCAnonAggregate) then
      Continue;
    LAggregate := TPCAnonAggregate(LMember);
    DoWriteOverlayLayouts(AFile, LAggregate.Members, LAggregate.IsOverlay, ANext);
  end;
end;

procedure TPCEmitter.DoWriteLayoutMembers(const AFile: TPCOutFile; const AMembers: TList<TPCMemberItem>);
var
  LMember: TPCMemberItem;
  LField: TPCField;
  LAggregate: TPCAnonAggregate;
begin
  // F35: a union's members again, for its layout twin: each field's type (a
  // wchar bitfield as char16_t, as DoEmitField writes it), name and width,
  // each anonymous aggregate as written (packed kept); no checks and no zero
  // member (neither changes the size), no span (borrowed: the members' nodes
  // are written again with theirs). An overlay holds fields and anonymous
  // records, an anonymous record fields and anonymous overlays (BNF sec 4)
  FWriters[AFile].BeginBorrowed();
  try
    for LMember in AMembers do
    begin
      if LMember is TPCField then
      begin
        LField := TPCField(LMember);
        DoText(AFile, ' ');
        if LField.IsWCharBitfield() then
          DoText(AFile, 'char16_t')
        else if LField.IsChoicesBitfield() then
          DoText(AFile, DoChoicesUnderlying(TPCChoicesType(LField.TypeExpr.Canon())))
        else
          DoWriteType(AFile, LField.TypeExpr);
        DoText(AFile, ' ' + LField.FieldName);
        if LField.BitWidthExpr <> nil then
        begin
          DoText(AFile, ' : (');
          DoWriteTypeConstant(AFile, LField.BitWidthExpr);
          DoText(AFile, ')');
        end;
        DoText(AFile, ';');
      end
      else if LMember is TPCAnonAggregate then
      begin
        LAggregate := TPCAnonAggregate(LMember);
        if LAggregate.IsOverlay then
          DoText(AFile, ' union {')
        else if LAggregate.IsPacked then
          DoText(AFile, ' struct [[gnu::packed]] {')
        else
          DoText(AFile, ' struct {');
        DoWriteLayoutMembers(AFile, LAggregate.Members);
        DoText(AFile, ' };');
      end
      else
        DoNoRule(LMember);
    end;
  finally
    FWriters[AFile].EndBorrowed();
  end;
end;

procedure TPCEmitter.DoWriteOverlayZero(const AFile: TPCOutFile);
var
  LIndex: string;
begin
  // F35: the union's FIRST member, as large as its layout twin (number
  // FOverlayCount): value-initializing the union zeroes it, so every byte any
  // member reaches. No span: no PaskalCPP node writes it
  LIndex := IntToStr(FOverlayCount);
  DoText(AFile, ' unsigned char ' + PC_EMT_OVERLAY_ZERO + LIndex + '[sizeof(' + PC_EMT_OVERLAY_LAYOUT + LIndex +
    ')];');
end;

procedure TPCEmitter.DoWritePackedCheck(const AFile: TPCOutFile; const AType: TPCTypeExpr; const AOwner: TPCNode);
var
  LMark: TPCWriterMark;
begin
  // PLAN-RECORDS M9: a packed field's type only clang lays out (a C/C++
  // leaf, a C++ base class, an object: TPCFieldPacking fpClangDecides) is
  // asserted to pack, ::pcpp::packs_as_field, as a second span of AOwner
  // (the field, or the parent type); the frontend reports a failure as
  // SM0331 there (TPCAst.FieldCheckAt). SEM already judged every other
  // type (fpNeverPacks = SM0331, so none reaches here)
  if (AType = nil) or (AType.FieldPacking() <> fpClangDecides) then
    Exit;
  DoText(AFile, ' ');
  LMark := FWriters[AFile].Mark();
  DoText(AFile, 'static_assert(::pcpp::packs_as_field<');
  DoWriteBorrowedType(AFile, AType);
  DoText(AFile, '>, "' + PC_FRONTEND_CHECK_PACKED + '");');
  FWriters[AFile].CloseSpan(LMark, AOwner);
end;

procedure TPCEmitter.DoEmitAnonAggregate(const AFile: TPCOutFile; const AAggregate: TPCAnonAggregate;
  const AInUnion: Boolean; const AInClass: Boolean);
var
  LMark: TPCWriterMark;
  LSavedPacked: Boolean;
begin
  // An anonymous overlay (union { ... };) in a record, an anonymous record
  // (struct [[gnu::packed]] { ... };) in an overlay. Its fields are packed
  // inside a packed record and inside a packed anonymous record (M9: the
  // packed-field check, SEM's DoCheckPackedFields)
  DoBeginItem(AFile, AAggregate.Range.StartLine);
  LMark := FWriters[AFile].Mark();
  if AAggregate.IsOverlay then
  begin
    // F35: the next union of this named type (its layout twin was written
    // with the type's head, DoWriteOverlayLayouts)
    DoText(AFile, 'union {');
    Inc(FOverlayCount);
    DoWriteOverlayZero(AFile);
  end
  else if AAggregate.IsPacked then
    DoText(AFile, 'struct [[gnu::packed]] {')
  else
    DoText(AFile, 'struct {');
  LSavedPacked := FInPacked;
  FInPacked := FInPacked or AAggregate.IsPacked;
  DoEmitMembers(AFile, AAggregate.Members, AInUnion or AAggregate.IsOverlay, AInClass);
  FInPacked := LSavedPacked;
  DoPut(AFile, AAggregate.Range.EndLine, '};');
  FWriters[AFile].CloseSpan(LMark, AAggregate);
end;

procedure TPCEmitter.DoEmitChoices(const AFile: TPCOutFile; const ADecl: TPCTypeDecl; const AChoices: TPCChoicesType);
var
  LValue: TPCChoiceValue;
  LMark: TPCWriterMark;
begin
  // enum class N : U { V = ordinal, ... }; one value per line, then (global
  // scope, same line) its O7 formatter; the next PaskalCPP part reopens the run
  DoText(AFile, 'enum class ' + ADecl.DeclName + ' : ' + DoChoicesUnderlying(AChoices) + ' {');
  for LValue in AChoices.Values do
  begin
    DoBeginItem(AFile, LValue.Range.StartLine);
    LMark := FWriters[AFile].Mark();
    DoText(AFile, LValue.ValueName + ' = ' + IntToStr(DoOrdinal(LValue)) + ',');
    FWriters[AFile].CloseSpan(LMark, LValue);
  end;
  DoPut(AFile, AChoices.Range.EndLine, '};');
  if FRunOpen[AFile] then
    DoCloseRun(AFile);
  DoPut(AFile, FWriters[AFile].SourceLine(),
    DoFormatterText('::' + DoNamespaceName(FModule) + '::' + ADecl.DeclName, ADecl.DeclName, AChoices));
end;

procedure TPCEmitter.DoHoistLocalChoices(const ARoutine: TPCRoutine; const ALine: UInt64);
var
  LStmt: TPCStmt;
  LDecl: TPCTypeDecl;
  LChoices: TPCChoicesType;
  LValue: TPCChoiceValue;
  LName: string;
  LText: string;
begin
  // H3: every choices type of the routine's local type blocks becomes a
  // module-namespace enum on the routine's first line, before its text, so
  // its O7 formatter (global scope) exists; the local declaration aliases it
  for LStmt in ARoutine.Decls do
  begin
    if not (LStmt is TPCTypeDecl) then
      Continue;
    LDecl := TPCTypeDecl(LStmt);
    if LDecl.IsForward or not (LDecl.TypeDef is TPCChoicesType) then
      Continue;
    LChoices := TPCChoicesType(LDecl.TypeDef);
    LName := DoLocalChoicesName(LChoices);
    LText := 'enum class ' + LName + ' : ' + DoChoicesUnderlying(LChoices) + ' {';
    for LValue in LChoices.Values do
      LText := LText + ' ' + LValue.ValueName + ' = ' + IntToStr(DoOrdinal(LValue)) + ',';
    DoPut(ofSource, ALine, LText + ' };');
    DoCloseRun(ofSource);
    DoPut(ofSource, ALine, DoFormatterText('::' + DoNamespaceName(FModule) + '::' + LName, LDecl.DeclName, LChoices));
    DoOpenRun(ofSource, ALine);
  end;
end;

procedure TPCEmitter.DoOpenRun(const AFile: TPCOutFile; const ALine: UInt64);
begin
  DoPut(AFile, ALine, 'namespace ' + DoNamespaceName(FModule) + ' {');
  FRunOpen[AFile] := True;
end;

procedure TPCEmitter.DoCloseRun(const AFile: TPCOutFile);
begin
  // On the line of the run's last part
  DoPut(AFile, FWriters[AFile].SourceLine(), '}');
  FRunOpen[AFile] := False;
end;

procedure TPCEmitter.DoWriteHeaderPreamble();
var
  LWriter: TPCCppWriter;
  LImport: TPCImport;
  LProtos: string;
begin
  // H8: no #line here; every included header is generated by PaskalCPP
  LWriter := FWriters[ofHeader];
  LWriter.WritePreamble('#pragma once');
  LWriter.WritePreamble('#include "pcpp_runtime.h"');
  for LImport in FModule.Imports do
  begin
    if LImport.ImportedModule = nil then
      raise EInvalidOpException.CreateFmt(RSEmtNoImport, [LImport.ModuleName]);
    LWriter.WritePreamble('#include "' + LImport.ImportedModule.ModuleName + PC_EMT_HEADER_EXT + '"');
  end;

  // The synthesized functions another module's trailer calls
  LProtos := '';
  if DoHasRegistration() then
    LProtos := LProtos + ' void ' + PC_EMT_REGISTER_NAME + '();';
  if FModule.InitRoutine <> nil then
    LProtos := LProtos + ' void ' + PC_EMT_INIT_NAME + '();';
  if FModule.FinalRoutine <> nil then
    LProtos := LProtos + ' void ' + PC_EMT_FINAL_NAME + '();';
  if LProtos = '' then
    LWriter.WritePreamble('namespace ' + DoNamespaceName(FModule) + ' {}')
  else
    LWriter.WritePreamble('namespace ' + DoNamespaceName(FModule) + ' {' + LProtos + ' }');
end;

procedure TPCEmitter.DoWriteSourcePreamble();
var
  LWriter: TPCCppWriter;
begin
  LWriter := FWriters[ofSource];
  LWriter.WritePreamble('#include "' + FModule.ModuleName + PC_EMT_HEADER_EXT + '"');
  LWriter.WritePreamble('using namespace ::' + DoNamespaceName(FModule) + ';');
end;

procedure TPCEmitter.DoEmitFile(const AFile: TPCOutFile);
var
  LCursor: TPCItemCursor;
  LItem: TPCModuleItem;
  LPart: TPCEmitPart;
begin
  // Every item with a part in AFile, in source order. A run opens before
  // the first PaskalCPP part on its line and closes after the last one of
  // the run, on that part's last line (lookahead to the next part in AFile)
  LCursor := Default(TPCItemCursor);
  while DoNextItem(LCursor, LItem) do
  begin
    LPart := DoPartKind(LItem, AFile);
    if LPart = epNone then
      Continue;
    if (LPart = epNamespace) and (not FRunOpen[AFile]) then
      DoOpenRun(AFile, DoItemLine(LItem));
    if (LPart = epGlobal) and FRunOpen[AFile] then
      raise EInvalidOpException.CreateFmt(RSEmtRunOpen, [DoItemLine(LItem)]);
    DoEmitItem(LItem, AFile);
    if FRunOpen[AFile] and (DoNextPartKind(LCursor, AFile) <> epNamespace) then
      DoCloseRun(AFile);
  end;
end;

procedure TPCEmitter.DoEmitItem(const AItem: TPCModuleItem; const AFile: TPCOutFile);
begin
  case AItem.ItemKind of
    miDecl:
      DoEmitDecl(TPCStmt(AItem.Node), AFile);
    miTest:
      DoEmitTest(TPCTest(AItem.Node));
    miInit:
      DoEmitSection(FModule.InitRoutine, PC_EMT_INIT_NAME);
    miFinal:
      DoEmitSection(FModule.FinalRoutine, PC_EMT_FINAL_NAME);
    miBody:
      DoEmitBody();
    miTrailer:
      DoEmitTrailer();
  end;
end;

procedure TPCEmitter.DoEmitDecl(const AStmt: TPCStmt; const AFile: TPCOutFile);
begin
  if AStmt is TPCVerbatimStmt then
    DoPutVerbatim(AFile, TPCVerbatimStmt(AStmt))
  else if AStmt is TPCTypeDecl then
  begin
    // A type in the header has its method definitions in the source (H4);
    // a type placed in the source (DoDeclInFile, E5) is written there whole,
    // its methods defined in the class (DoEmitRecord)
    if AFile = ofHeader then
      DoEmitTypeDecl(AFile, TPCTypeDecl(AStmt), True)
    else if DoDeclInFile(AStmt, ofHeader) then
      DoEmitMethodDefs(TPCTypeDecl(AStmt))
    else
      DoEmitTypeDecl(AFile, TPCTypeDecl(AStmt), True);
  end
  else if AStmt is TPCVarDecl then
    DoEmitVar(AFile, TPCVarDecl(AStmt), True)
  else if AStmt is TPCConstDecl then
    DoEmitConst(AFile, TPCConstDecl(AStmt), True)
  else if AStmt is TPCRoutine then
    DoEmitRoutine(AFile, TPCRoutine(AStmt))
  else
    DoNoRule(AStmt);
end;

procedure TPCEmitter.DoEmitStmts(const AStmts: TList<TPCStmt>);
var
  LStmt: TPCStmt;
begin
  for LStmt in AStmts do
    DoEmitStmt(LStmt);
end;

procedure TPCEmitter.DoEmitStmt(const AStmt: TPCStmt);
begin
  // A body's statements and local blocks, in place in the source, each on
  // its own .pcpp lines (A7)
  if AStmt is TPCVerbatimStmt then
    DoPutVerbatim(ofSource, TPCVerbatimStmt(AStmt))
  else if AStmt is TPCDirective then
    Exit
  else if AStmt is TPCTypeDecl then
    DoEmitTypeDecl(ofSource, TPCTypeDecl(AStmt), False)
  else if AStmt is TPCVarDecl then
    DoEmitVar(ofSource, TPCVarDecl(AStmt), False)
  else if AStmt is TPCConstDecl then
    DoEmitConst(ofSource, TPCConstDecl(AStmt), False)
  else if AStmt is TPCBlock then
    DoEmitBlock(TPCBlock(AStmt))
  else if AStmt is TPCIf then
    DoEmitIf(TPCIf(AStmt))
  else if AStmt is TPCWhile then
    DoEmitWhile(TPCWhile(AStmt))
  else if AStmt is TPCRepeat then
    DoEmitRepeat(TPCRepeat(AStmt))
  else if AStmt is TPCFor then
    DoEmitFor(TPCFor(AStmt))
  else if AStmt is TPCMatch then
    DoEmitMatch(TPCMatch(AStmt))
  else if AStmt is TPCGuard then
    DoEmitGuard(TPCGuard(AStmt))
  else if AStmt is TPCReturn then
    DoEmitReturn(TPCReturn(AStmt))
  else if AStmt is TPCLeave then
    DoEmitJump(AStmt, TPCLeave(AStmt).ResolvedJumpTarget, geLeave)
  else if AStmt is TPCSkip then
    DoEmitJump(AStmt, TPCSkip(AStmt).ResolvedJumpTarget, geSkip)
  else if AStmt is TPCExprStmt then
    DoEmitExprStmt(TPCExprStmt(AStmt))
  else
    DoNoRule(AStmt);
end;

procedure TPCEmitter.DoEnterBody(const ARoutine: TPCRoutine; out ASaved: TPCRoutine);
begin
  // A body starts a fresh walk context: a barrier no jump scan passes (a
  // local object's method inside a guard body escapes nothing of it)
  ASaved := FRoutine;
  FRoutine := ARoutine;
  DoPush(nil, False);
end;

procedure TPCEmitter.DoLeaveBody(const ASaved: TPCRoutine);
begin
  DoPop();
  FRoutine := ASaved;
end;

procedure TPCEmitter.DoPush(const AStmt: TPCStmt; const AIsLambda: Boolean);
var
  LEntry: TPCOpenStmt;
begin
  LEntry.Stmt := AStmt;
  LEntry.IsLambda := AIsLambda;
  FOpen.Add(LEntry);
end;

procedure TPCEmitter.DoPop();
begin
  if FOpen.Count = 0 then
    DoMissing(ofSource, 'open statement');
  FOpen.Delete(FOpen.Count - 1);
end;

function TPCEmitter.DoEscapeLambda(const ATarget: TPCStmt): TPCGuard;
var
  LIndex: Integer;
  LEntry: TPCOpenStmt;
begin
  // The guard lambda a jump leaves on its way to ATarget (a loop or match;
  // nil = a return, which leaves the routine): nil when the target, or for
  // a return the body itself, comes first (a plain C++ jump). The target is
  // ResolvedJumpTarget, written by SEM; this only finds the lambdas in between
  for LIndex := FOpen.Count - 1 downto 0 do
  begin
    LEntry := FOpen[LIndex];
    if LEntry.Stmt = nil then
    begin
      // The body barrier: a return reached its routine; a loop target
      // outside the body is an invariant
      if ATarget <> nil then
        DoMissing(ofSource, 'jump target');
      Exit(nil);
    end;
    if LEntry.IsLambda then
      Exit(TPCGuard(LEntry.Stmt));
    if LEntry.Stmt = ATarget then
      Exit(nil);
  end;
  DoMissing(ofSource, 'body barrier');
  Result := nil;
end;

function TPCEmitter.DoDispatchLambda(const ALoopsOnly: Boolean): TPCGuard;
var
  LIndex: Integer;
  LEntry: TPCOpenStmt;
begin
  // Where a guard's leave (ALoopsOnly False) or skip (True) flow goes after
  // the guard: every such escape of one guard targets the innermost loop
  // (or match, for leave) around the guard. nil = that target is reached
  // first (a plain break / continue); else the enclosing lambda it
  // propagates through, one lambda at a time
  for LIndex := FOpen.Count - 1 downto 0 do
  begin
    LEntry := FOpen[LIndex];
    if LEntry.Stmt = nil then
      DoMissing(ofSource, 'jump target');
    if LEntry.IsLambda then
      Exit(TPCGuard(LEntry.Stmt));
    if (LEntry.Stmt is TPCWhile) or (LEntry.Stmt is TPCFor) or (LEntry.Stmt is TPCRepeat) then
      Exit(nil);
    if (not ALoopsOnly) and (LEntry.Stmt is TPCMatch) then
      Exit(nil);
  end;
  DoMissing(ofSource, 'body barrier');
  Result := nil;
end;

function TPCEmitter.DoHasResult(): Boolean;
begin
  // A return carries a value only in a routine with a return type (SEM)
  Result := (FRoutine <> nil) and (FRoutine.ReturnType <> nil);
end;

function TPCEmitter.DoDispatchSet(const AGuard: TPCGuard): TPCGuardEscapes;
begin
  // The flows a guard's lambdas can report: its body's, and its except
  // list's when the except runs in a lambda (the guard has a finally)
  Result := AGuard.ResolvedEscapes;
  if AGuard.HasExcept and AGuard.HasFinally then
    Result := Result + AGuard.ResolvedExceptEscapes;
end;

procedure TPCEmitter.DoPutClose(const ALine: UInt64; const AText: string);
var
  LLine: UInt64;
begin
  // A closer on ALine; after a # line that line is closed, so it goes on
  // the next one (the # line is always the last text of its .pcpp line)
  LLine := ALine;
  if FWriters[ofSource].LineClosed() and (FWriters[ofSource].SourceLine() >= LLine) then
    LLine := FWriters[ofSource].SourceLine() + 1;
  DoPut(ofSource, LLine, AText);
end;

procedure TPCEmitter.DoWriteBorrowedType(const AFile: TPCOutFile; const AType: TPCTypeExpr);
begin
  // A type spelled a second time (the routine's return type, a for
  // iterator's type, a set literal's element type): the same text, no span
  // (the node lives elsewhere)
  if AType = nil then
    DoMissing(AFile, 'type');
  FWriters[AFile].BeginBorrowed();
  try
    DoWriteType(AFile, AType);
  finally
    FWriters[AFile].EndBorrowed();
  end;
end;

procedure TPCEmitter.DoEmitBlock(const ABlock: TPCBlock);
var
  LMark: TPCWriterMark;
begin
  // begin ... end; -> { ... }
  DoBeginItem(ofSource, ABlock.Range.StartLine);
  LMark := FWriters[ofSource].Mark();
  DoText(ofSource, '{');
  DoEmitStmts(ABlock.Stmts);
  DoPutClose(ABlock.Range.EndLine, '}');
  FWriters[ofSource].CloseSpan(LMark, ABlock);
end;

procedure TPCEmitter.DoEmitIf(const AIf: TPCIf);
var
  LMark: TPCWriterMark;
begin
  // if ((c)) { ... } else { ... }: `} else {` on the else keyword's line
  DoBeginItem(ofSource, AIf.Range.StartLine);
  LMark := FWriters[ofSource].Mark();
  DoText(ofSource, 'if ((');
  DoWriteExpr(ofSource, AIf.Condition);
  DoText(ofSource, ')) {');
  DoEmitStmts(AIf.ThenStmts);
  if AIf.HasElse then
  begin
    DoPutClose(AIf.ElseRange.StartLine, '} else {');
    DoEmitStmts(AIf.ElseStmts);
  end;
  DoPutClose(AIf.Range.EndLine, '}');
  FWriters[ofSource].CloseSpan(LMark, AIf);
end;

procedure TPCEmitter.DoEmitWhile(const AWhile: TPCWhile);
var
  LMark: TPCWriterMark;
begin
  DoBeginItem(ofSource, AWhile.Range.StartLine);
  LMark := FWriters[ofSource].Mark();
  DoText(ofSource, 'while ((');
  DoWriteExpr(ofSource, AWhile.Condition);
  DoText(ofSource, ')) {');
  DoPush(AWhile, False);
  DoEmitStmts(AWhile.Stmts);
  DoPop();
  DoPutClose(AWhile.Range.EndLine, '}');
  FWriters[ofSource].CloseSpan(LMark, AWhile);
end;

procedure TPCEmitter.DoEmitRepeat(const ARepeat: TPCRepeat);
var
  LMark: TPCWriterMark;
begin
  // do { ... } while (!((c))); the closer on the until keyword's line
  DoBeginItem(ofSource, ARepeat.Range.StartLine);
  LMark := FWriters[ofSource].Mark();
  DoText(ofSource, 'do {');
  DoPush(ARepeat, False);
  DoEmitStmts(ARepeat.Stmts);
  DoPop();
  DoPutClose(ARepeat.UntilRange.StartLine, '} while (!((');
  DoWriteExpr(ofSource, ARepeat.Condition);
  DoText(ofSource, ')));');
  FWriters[ofSource].CloseSpan(LMark, ARepeat);
end;

procedure TPCEmitter.DoEmitFor(const AFor: TPCFor);
var
  LMark: TPCWriterMark;
  LName: string;
  LType: TPCTypeExpr;
  LEnd: string;
  LGo: string;
  LStep: string;
begin
  // EM "Statements": the end is evaluated once, the loop stops AT the end
  // (no overflow past the type's max), skip still advances (continue runs
  // the step). All on the for line; closer `} }` on the end line
  if AFor.ResolvedIterator is TPCVarDecl then
  begin
    LName := DoDeclName(TPCVarDecl(AFor.ResolvedIterator));
    LType := TPCVarDecl(AFor.ResolvedIterator).TypeExpr;
  end
  else if AFor.ResolvedIterator is TPCParam then
  begin
    LName := TPCParam(AFor.ResolvedIterator).ParamName;
    LType := TPCParam(AFor.ResolvedIterator).TypeExpr;
  end
  else if AFor.ResolvedIteratorOpaque then
  begin
    // A C/C++ variable (BNF sec 5): its name as written; its type is
    // clang's (no PaskalCPP type: the end's type is written from decltype)
    LName := AFor.IteratorName;
    LType := nil;
  end
  else
  begin
    DoMissing(ofSource, 'for iterator');
    Exit;
  end;
  LEnd := Format('pcpp_end_%d', [AFor.Range.StartByteOffset]);
  LGo := Format('pcpp_go_%d', [AFor.Range.StartByteOffset]);

  DoBeginItem(ofSource, AFor.Range.StartLine);
  LMark := FWriters[ofSource].Mark();
  DoText(ofSource, '{ ' + LName + ' = (');
  DoWriteExpr(ofSource, AFor.StartExpr);
  DoText(ofSource, '); const ');
  if LType <> nil then
    DoWriteBorrowedType(ofSource, LType)
  else
    DoText(ofSource, 'std::remove_cvref_t<decltype((' + LName + '))>');
  DoText(ofSource, ' ' + LEnd + ' = (');
  DoWriteExpr(ofSource, AFor.EndExpr);
  DoText(ofSource, '); if (' + LName);
  if AFor.IsDownTo then
    DoText(ofSource, ' >= ')
  else
    DoText(ofSource, ' <= ');
  DoText(ofSource, LEnd + ') for (bool ' + LGo + ' = true; ' + LGo + '; ' + LGo + ' = (' + LName + ' != ' +
    LEnd + ') ? (');

  // The step. A choices iterator steps through its ordinal (an enum class
  // has no ++ / --): I = static_cast<T>(static_cast<std::int64_t>(I) +- 1)
  if (LType <> nil) and (LType.Canon() is TPCChoicesType) then
  begin
    DoText(ofSource, LName + ' = static_cast<');
    DoWriteBorrowedType(ofSource, LType);
    if AFor.IsDownTo then
      LStep := ') - 1)'
    else
      LStep := ') + 1)';
    DoText(ofSource, '>(static_cast<std::int64_t>(' + LName + LStep);
  end
  else if AFor.IsDownTo then
    DoText(ofSource, '--' + LName)
  else
    DoText(ofSource, '++' + LName);
  DoText(ofSource, ', true) : false) {');

  DoPush(AFor, False);
  DoEmitStmts(AFor.Stmts);
  DoPop();
  DoPutClose(AFor.Range.EndLine, '} }');
  FWriters[ofSource].CloseSpan(LMark, AFor);
end;

procedure TPCEmitter.DoEmitMatchLabel(const ALabel: TPCMatchLabel);
var
  LMark: TPCWriterMark;
begin
  // case (L): or a clang case range case (L) ... (H): (gnu++23)
  DoBeginItem(ofSource, ALabel.Range.StartLine);
  LMark := FWriters[ofSource].Mark();
  DoText(ofSource, 'case (');
  DoWriteExpr(ofSource, ALabel.LowExpr);
  DoText(ofSource, ')');
  if ALabel.HighExpr <> nil then
  begin
    DoText(ofSource, ' ... (');
    DoWriteExpr(ofSource, ALabel.HighExpr);
    DoText(ofSource, ')');
  end;
  DoText(ofSource, ':');
  FWriters[ofSource].CloseSpan(LMark, ALabel);
end;

procedure TPCEmitter.DoEmitMatch(const AMatch: TPCMatch);
var
  LMark: TPCWriterMark;
  LArmMark: TPCWriterMark;
  LArm: TPCMatchArm;
  LLabel: TPCMatchLabel;
begin
  // switch ((s)) { case ...: { ... } break; default: ... }: break leaves the
  // match and continue reaches the enclosing loop, exactly leave / skip.
  // No else = `default: break;` (O-S6c: clang's -Wswitch never fires)
  DoBeginItem(ofSource, AMatch.Range.StartLine);
  LMark := FWriters[ofSource].Mark();
  DoText(ofSource, 'switch ((');
  DoWriteExpr(ofSource, AMatch.Subject);
  DoText(ofSource, ')) {');
  DoPush(AMatch, False);
  for LArm in AMatch.Arms do
  begin
    DoBeginItem(ofSource, LArm.Range.StartLine);
    LArmMark := FWriters[ofSource].Mark();
    for LLabel in LArm.Labels do
      DoEmitMatchLabel(LLabel);
    DoText(ofSource, ' {');
    DoEmitStmts(LArm.Stmts);
    DoPutClose(LArm.Range.EndLine, '} break;');
    FWriters[ofSource].CloseSpan(LArmMark, LArm);
  end;
  if AMatch.HasElse then
  begin
    DoPutClose(AMatch.ElseRange.StartLine, 'default: {');
    DoEmitStmts(AMatch.ElseStmts);
    DoPutClose(AMatch.Range.EndLine, '} break; }');
  end
  else
    DoPutClose(AMatch.Range.EndLine, 'default: break; }');
  DoPop();
  FWriters[ofSource].CloseSpan(LMark, AMatch);
end;

procedure TPCEmitter.DoEmitGuard(const AGuard: TPCGuard);
var
  LMark: TPCWriterMark;
  LId: UInt64;
  LEscapes: TPCGuardEscapes;
begin
  // Written in source order (A7; EM's form put the finally body before the
  // guard body, which the one-line-per-line rule cannot write):
  //   guard line:   { flow; ret; exc = ::pcpp::guard([&]() {      body
  //   except line:  }); if (exc != 0) {                            except (direct)
  //     or with a finally: }); ::pcpp::guard_finally([&]() { if (exc != 0) {
  //   finally line: } }, [&]() {                                   finally
  //     or with no except: }); Caught caught = Caught::take(exc); {
  //   end line:     }); / } / (no except) } caught.pass_on();  then the
  //                 flow dispatch and the closing }
  // The body runs in pcpp::guard's lambda, so nothing leaves it but a
  // lambda return: a finally after it needs no scope object. With an except
  // and a finally the except runs in a lambda too, and guard_finally runs
  // the finally after it on every path (a raise included)
  LId := AGuard.Range.StartByteOffset;
  LEscapes := DoDispatchSet(AGuard);
  DoBeginItem(ofSource, AGuard.Range.StartLine);
  LMark := FWriters[ofSource].Mark();
  DoText(ofSource, '{');
  if LEscapes <> [] then
    DoText(ofSource, Format(' ::pcpp::Flow pcpp_flow_%d = ::pcpp::Flow::None;', [LId]));
  if (geReturn in LEscapes) and DoHasResult() then
  begin
    DoText(ofSource, ' std::optional<');
    DoWriteBorrowedType(ofSource, FRoutine.ReturnType);
    DoText(ofSource, Format('> pcpp_ret_%d;', [LId]));
  end;
  // Every guard keeps what it caught: the except list tests it, a guard with
  // no except passes it on after its finally
  DoText(ofSource, Format(' std::int32_t pcpp_exc_%d = ::pcpp::guard([&]() {', [LId]));

  DoPush(AGuard, True);
  DoEmitStmts(AGuard.GuardStmts);
  DoPop();

  if AGuard.HasExcept then
  begin
    if AGuard.HasFinally then
    begin
      DoPutClose(AGuard.ExceptRange.StartLine,
        Format('}); ::pcpp::guard_finally([&]() { if (pcpp_exc_%d != 0) {', [LId]));
      DoPush(AGuard, True);
      DoEmitStmts(AGuard.ExceptStmts);
      DoPop();
    end
    else
    begin
      DoPutClose(AGuard.ExceptRange.StartLine, Format('}); if (pcpp_exc_%d != 0) {', [LId]));
      DoEmitStmts(AGuard.ExceptStmts);
    end;
  end;
  if AGuard.HasFinally then
  begin
    // No except: what the body raised is taken before the finally (a guard
    // inside it overwrites the last caught) and passed on after it
    if AGuard.HasExcept then
      DoPutClose(AGuard.FinallyRange.StartLine, '} }, [&]() {')
    else
      DoPutClose(AGuard.FinallyRange.StartLine,
        Format('}); ::pcpp::Caught pcpp_caught_%d = ::pcpp::Caught::take(pcpp_exc_%d); {', [LId, LId]));
    DoEmitStmts(AGuard.FinallyStmts);
  end;

  if AGuard.HasExcept and AGuard.HasFinally then
    DoPutClose(AGuard.Range.EndLine, '});')
  else if AGuard.HasFinally then
    DoPutClose(AGuard.Range.EndLine, Format('} pcpp_caught_%d.pass_on();', [LId]))
  else
    DoPutClose(AGuard.Range.EndLine, '}');
  DoEmitDispatch(AGuard);
  DoText(ofSource, ' }');
  FWriters[ofSource].CloseSpan(LMark, AGuard);
end;

procedure TPCEmitter.DoEmitDispatch(const AGuard: TPCGuard);
var
  LId: UInt64;
  LEscapes: TPCGuardEscapes;
  LOuter: TPCGuard;
  LHasRet: Boolean;
begin
  // After the guard: each flow its lambdas reported continues here. A flow
  // whose target lies outside the enclosing lambda as well is handed on
  // to that lambda (its flag, its result) and returns from it
  LId := AGuard.Range.StartByteOffset;
  LEscapes := DoDispatchSet(AGuard);
  LHasRet := DoHasResult();
  if geReturn in LEscapes then
  begin
    LOuter := DoEscapeLambda(nil);
    DoText(ofSource, Format(' if (pcpp_flow_%d == ::pcpp::Flow::Return)', [LId]));
    if LOuter <> nil then
    begin
      DoText(ofSource, ' {');
      if LHasRet then
        DoText(ofSource, Format(' pcpp_ret_%d = std::move(pcpp_ret_%d);', [LOuter.Range.StartByteOffset, LId]));
      DoText(ofSource, Format(' pcpp_flow_%d = ::pcpp::Flow::Return; return; }', [LOuter.Range.StartByteOffset]));
    end
    else if LHasRet then
      DoText(ofSource, Format(' return std::move(*pcpp_ret_%d);', [LId]))
    else
      DoText(ofSource, ' return;');
  end;
  if geLeave in LEscapes then
  begin
    LOuter := DoDispatchLambda(False);
    DoText(ofSource, Format(' if (pcpp_flow_%d == ::pcpp::Flow::Leave)', [LId]));
    if LOuter <> nil then
      DoText(ofSource, Format(' { pcpp_flow_%d = ::pcpp::Flow::Leave; return; }', [LOuter.Range.StartByteOffset]))
    else
      DoText(ofSource, ' break;');
  end;
  if geSkip in LEscapes then
  begin
    LOuter := DoDispatchLambda(True);
    DoText(ofSource, Format(' if (pcpp_flow_%d == ::pcpp::Flow::Skip)', [LId]));
    if LOuter <> nil then
      DoText(ofSource, Format(' { pcpp_flow_%d = ::pcpp::Flow::Skip; return; }', [LOuter.Range.StartByteOffset]))
    else
      DoText(ofSource, ' continue;');
  end;
end;

procedure TPCEmitter.DoEmitReturn(const AReturn: TPCReturn);
var
  LMark: TPCWriterMark;
  LGuard: TPCGuard;
begin
  // return (v); / return; -- inside a guard lambda the value and the flow
  // go to that guard and the lambda returns (its dispatch continues)
  DoBeginItem(ofSource, AReturn.Range.StartLine);
  LMark := FWriters[ofSource].Mark();
  LGuard := DoEscapeLambda(nil);
  if LGuard = nil then
  begin
    if AReturn.ValueExpr = nil then
      DoText(ofSource, 'return;')
    else
    begin
      DoText(ofSource, 'return (');
      DoWriteExpr(ofSource, AReturn.ValueExpr);
      DoText(ofSource, ');');
    end;
  end
  else
  begin
    DoText(ofSource, '{');
    if AReturn.ValueExpr <> nil then
    begin
      if not DoHasResult() then
        DoMissing(ofSource, 'return type');
      DoText(ofSource, Format(' pcpp_ret_%d = (', [LGuard.Range.StartByteOffset]));
      DoWriteExpr(ofSource, AReturn.ValueExpr);
      DoText(ofSource, ');');
    end;
    DoText(ofSource, Format(' pcpp_flow_%d = ::pcpp::Flow::Return; return; }', [LGuard.Range.StartByteOffset]));
  end;
  FWriters[ofSource].CloseSpan(LMark, AReturn);
end;

procedure TPCEmitter.DoEmitJump(const AStmt: TPCStmt; const ATarget: TPCStmt; const AEscape: TPCGuardEscape);
var
  LMark: TPCWriterMark;
  LGuard: TPCGuard;
begin
  // leave -> break; skip -> continue; out of a guard lambda the flow goes to
  // the guard and the lambda returns
  if ATarget = nil then
    DoMissing(ofSource, 'jump target');
  DoBeginItem(ofSource, AStmt.Range.StartLine);
  LMark := FWriters[ofSource].Mark();
  LGuard := DoEscapeLambda(ATarget);
  if LGuard = nil then
  begin
    if AEscape = geLeave then
      DoText(ofSource, 'break;')
    else
      DoText(ofSource, 'continue;');
  end
  else if AEscape = geLeave then
    DoText(ofSource, Format('{ pcpp_flow_%d = ::pcpp::Flow::Leave; return; }', [LGuard.Range.StartByteOffset]))
  else
    DoText(ofSource, Format('{ pcpp_flow_%d = ::pcpp::Flow::Skip; return; }', [LGuard.Range.StartByteOffset]));
  FWriters[ofSource].CloseSpan(LMark, AStmt);
end;

procedure TPCEmitter.DoEmitExprStmt(const AStmt: TPCExprStmt);
var
  LMark: TPCWriterMark;
begin
  // An assignment statement takes no outer ( ): t = (v);
  DoBeginItem(ofSource, AStmt.Range.StartLine);
  LMark := FWriters[ofSource].Mark();
  DoWriteExprAs(ofSource, AStmt.Expr, True);
  DoText(ofSource, ';');
  FWriters[ofSource].CloseSpan(LMark, AStmt);
end;

procedure TPCEmitter.DoWriteChoiceValue(const AFile: TPCOutFile; const AValue: TPCNode);
begin
  // <E>::<V>, E from the value's ResolvedChoices (A8 rule, pulled forward
  // for match labels and for bounds in A7)
  if not (AValue is TPCChoiceValue) then
    DoMissing(AFile, 'choice value');
  DoText(AFile, DoTypeName(TPCChoiceValue(AValue).ResolvedChoices) + '::' + TPCChoiceValue(AValue).ValueName);
end;

procedure TPCEmitter.DoEmitTest(const ATest: TPCTest);
var
  LSaved: TPCRoutine;
begin
  // test mode only (DoPartKind): its function on the test's first line, the
  // closer on its last
  DoEnterBody(nil, LSaved);
  DoPut(ofSource, ATest.Range.StartLine,
    Format('static void %s%d() {', [PC_EMT_TEST_PREFIX, ATest.Range.StartByteOffset]));
  DoEmitStmts(ATest.Decls);
  if ATest.Body <> nil then
    DoEmitStmts(ATest.Body.Stmts);
  DoPutClose(ATest.Range.EndLine, '}');
  DoLeaveBody(LSaved);
end;

procedure TPCEmitter.DoEmitSection(const ARoutine: TPCRoutine; const AFunctionName: string);
var
  LSaved: TPCRoutine;
begin
  // initialize / finalize: a routine (BNF sec 1) from its keyword's line to
  // its ';' line; its local choices types first (H3)
  DoHoistLocalChoices(ARoutine, ARoutine.Range.StartLine);
  DoEnterBody(ARoutine, LSaved);
  DoPut(ofSource, ARoutine.Range.StartLine, 'void ' + AFunctionName + '() {');
  DoEmitStmts(ARoutine.Decls);
  if ARoutine.Body <> nil then
    DoEmitStmts(ARoutine.Body.Stmts);
  DoPutClose(ARoutine.Range.EndLine, '}');
  DoLeaveBody(LSaved);
end;

procedure TPCEmitter.DoEmitBody();
var
  LText: string;
  LSaved: TPCRoutine;
begin
  // In test mode the body is compiled but never called (BNF sec 8)
  DoEnterBody(nil, LSaved);
  LText := 'static void ' + PC_EMT_BODY_NAME + '() {';
  if FTestMode then
    LText := '[[maybe_unused]] ' + LText;
  DoPut(ofSource, FModule.Body.Range.StartLine, LText);
  DoEmitStmts(FModule.Body.Stmts);

  // The body's Range ends at its last statement (the module's 'end .'
  // closes it): DoPutClose moves '}' past a closed # line
  DoPutClose(FModule.Body.Range.EndLine, '}');
  DoLeaveBody(LSaved);
end;

function TPCEmitter.DoInitChain(): string;
var
  LIndex: Integer;
  LModule: TPCModule;
begin
  // Q29 order = AST order (H11): every import before its importer, the main
  // module last
  Result := '';
  for LIndex := 0 to FAst.ModuleCount() - 1 do
  begin
    LModule := FAst.ModuleAt(LIndex);
    if LModule.InitRoutine <> nil then
      Result := Result + ' ::' + DoNamespaceName(LModule) + '::' + PC_EMT_INIT_NAME + '();';
  end;
end;

function TPCEmitter.DoFinalChain(): string;
var
  LIndex: Integer;
  LModule: TPCModule;
begin
  // The reverse of the initialize order (BNF sec 1)
  Result := '';
  for LIndex := FAst.ModuleCount() - 1 downto 0 do
  begin
    LModule := FAst.ModuleAt(LIndex);
    if LModule.FinalRoutine <> nil then
      Result := Result + ' ::' + DoNamespaceName(LModule) + '::' + PC_EMT_FINAL_NAME + '();';
  end;
end;

function TPCEmitter.DoRegisterChain(): string;
var
  LIndex: Integer;
  LModule: TPCModule;
begin
  // Test mode: the test blocks of the exe and of every unit it imports
  Result := '';
  for LIndex := 0 to FAst.ModuleCount() - 1 do
  begin
    LModule := FAst.ModuleAt(LIndex);
    if LModule.Tests.Count > 0 then
      Result := Result + ' ::' + DoNamespaceName(LModule) + '::' + PC_EMT_REGISTER_NAME + '();';
  end;
end;

function TPCEmitter.DoEntryText(const AStatements: string; const AResult: string): string;
begin
  // A captureless lambda: converts to the function pointer enter takes
  Result := PC_EMT_ENTER_NAME + '([]() -> std::int32_t {' + AStatements + ' return ' + AResult + '; })';
end;

function TPCEmitter.DoMainText(): string;
begin
  // exe: runtime startup, then inside enter the initialize chain, the body
  // or (test mode) the test runner, the finalize chain; the exit code is
  // the failed count
  if FTestMode then
    Result := 'int main(int argc, char** argv) { ::pcpp::init(argc, argv); return ' +
      DoEntryText(DoInitChain() + DoRegisterChain() + ' std::int32_t pcpp_failed = ::pcpp::run_tests();' +
      DoFinalChain(), 'pcpp_failed') + '; }'
  else
    Result := 'int main(int argc, char** argv) { ::pcpp::init(argc, argv); return ' +
      DoEntryText(DoInitChain() + ' ::' + DoNamespaceName(FModule) + '::' + PC_EMT_BODY_NAME + '();' +
      DoFinalChain(), '0') + '; }';
end;

function TPCEmitter.DoDllText(): string;
begin
  // H12: the runtime's DllMain / .so constructor-destructor calls these
  Result := 'extern "C" void pcpp_dll_initialize() { ::pcpp::init(0, nullptr); ' +
    DoEntryText(DoInitChain(), '0') + '; } extern "C" void pcpp_dll_finalize() { ' +
    DoEntryText(DoFinalChain(), '0') + '; }';
end;

function TPCEmitter.DoLibText(): string;
begin
  // H12 (W1 option 1): a static library starts and stops with the program
  Result := '__attribute__((constructor)) static void pcpp_lib_startup() { ::pcpp::init(0, nullptr); ' +
    DoEntryText(DoInitChain(), '0') + '; } __attribute__((destructor)) static void pcpp_lib_shutdown() { ' +
    DoEntryText(DoFinalChain(), '0') + '; }';
end;

procedure TPCEmitter.DoEmitTrailer();
var
  LLine: UInt64;
  LText: string;
  LTest: TPCTest;
begin
  // H9: on the module's last line, after everything else on it
  LLine := FModule.Range.EndLine;
  if DoHasRegistration() then
  begin
    LText := 'void ' + PC_EMT_REGISTER_NAME + '() {';
    for LTest in FModule.Tests do
      LText := LText + Format(' ::pcpp::register_test(%s, &%s%d, "%s", %d);',
        [DoLiteralCppText(LTest.TestName), PC_EMT_TEST_PREFIX, LTest.Range.StartByteOffset,
        TPCCppWriter.EscapePath(FModule.SourceFile), LTest.Range.StartLine]);
    DoPut(ofSource, LLine, LText + ' }');
  end;

  // The main module's entry, at global scope
  if not DoHasEntry() then
    Exit;
  if FModule.ModuleKind = mkExe then
    LText := DoMainText()
  else if FModule.ModuleKind = mkDll then
    LText := DoDllText()
  else if FModule.ModuleKind = mkLib then
    LText := DoLibText()
  else
    Exit;
  if FRunOpen[ofSource] then
    DoCloseRun(ofSource);
  DoPut(ofSource, LLine, LText);
end;

function TPCEmitter.EmitModule(const AModule: TPCModule; out AHeader: TBytes; out ASource: TBytes): Boolean;
var
  LFile: TPCOutFile;
begin
  AHeader := nil;
  ASource := nil;
  FModule := AModule;
  // A walk an invariant broke leaves its context behind: start clean
  FRoutine := nil;
  FRecord := nil;
  FInPacked := False;
  FOpen.Clear();
  FHeaderDecls.Clear();
  try
    // Before anything is written: the placement rule reads it (F22, E5)
    DoCollectHeaderDecls();
    for LFile := Low(TPCOutFile) to High(TPCOutFile) do
    begin
      FWriters[LFile].Init(LFile, AModule.SourceFile);
      FRunOpen[LFile] := False;
    end;
    DoWriteHeaderPreamble();
    DoWriteSourcePreamble();
    DoEmitFile(ofHeader);
    DoEmitFile(ofSource);
    AHeader := FWriters[ofHeader].GetBytes();
    ASource := FWriters[ofSource].GetBytes();
    Result := True;
  except
    on E: Exception do
    begin
      // An invariant (the writer's, or a node with no rule): every call is
      // built from an analyzed AST, so it is never the user's mistake
      AHeader := nil;
      ASource := nil;
      FErrors.Add(AModule.Range, esError, PC_ERR_EMT_003, RSEmtInternal, [AModule.ModuleName, E.Message]);
      Result := False;
    end;
  end;
end;

function TPCEmitter.DoWriteFile(const APath: string; const ABytes: TBytes): Boolean;
begin
  // H13: the bytes as built (UTF-8, no BOM, LF only)
  try
    TFile.WriteAllBytes(APath, ABytes);
    Result := True;
  except
    on E: Exception do
    begin
      FErrors.Add(esError, PC_ERR_EMT_002, RSEmtWriteFile, [APath, E.Message]);
      Result := False;
    end;
  end;
end;

function TPCEmitter.WriteFiles(const AOutputDir: string): Boolean;
var
  LDir: string;
  LIndex: Integer;
  LModule: TPCModule;
  LHeader: TBytes;
  LSource: TBytes;
begin
  Result := False;
  try
    LDir := TUtils.ResolvePath(AOutputDir);
    if not TUtils.EnsureDirectory(LDir) then
    begin
      FErrors.Add(esError, PC_ERR_EMT_001, RSEmtFolder, [AOutputDir, RSEmtEmptyPath]);
      Exit;
    end;
  except
    on E: Exception do
    begin
      FErrors.Add(esError, PC_ERR_EMT_001, RSEmtFolder, [AOutputDir, E.Message]);
      Exit;
    end;
  end;

  for LIndex := 0 to FAst.ModuleCount() - 1 do
  begin
    LModule := FAst.ModuleAt(LIndex);
    if not EmitModule(LModule, LHeader, LSource) then
      Exit;
    if not DoWriteFile(TUtils.JoinResolvedPath(LDir, LModule.ModuleName + PC_EMT_HEADER_EXT), LHeader) then
      Exit;
    if not DoWriteFile(TUtils.JoinResolvedPath(LDir, LModule.ModuleName + PC_EMT_SOURCE_EXT), LSource) then
      Exit;
  end;
  Result := True;
end;

end.
