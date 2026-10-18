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
  PaskalCPP.AST - Abstract syntax tree: nodes and arena

  The AST is the single source of truth between phases. TPCAst is the arena:
  it owns every node ever created, the module list and the synthesized types.
  TPCNode is the base of every node; its public fields ARE the contract
  between phases: the parser writes structure and Range, semantics writes the
  Resolved* fields, the emitter writes EmitSpans through AddEmitSpan only.
  EnumChildren is the one tree walk; Dump and TranslateLocation both use it.

  Dependencies: StdApp.Base, PaskalCPP.Common (TPCTokenKind), StdApp.Resources (RSAst*)
  Notes: research\cppmix\ast.md is the specification. PLAN-CPPMIX-AST-CORE
    built the base, the arena and the module-level, verbatim, block, literal
    and synthesized type nodes; PLAN-CPPMIX-AST-NODES adds the rest.
===============================================================================}

unit PaskalCPP.AST;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.Common;

const
  { PC_ERR_AST_001 }
  // A second module with the same name (AddModule); the first is kept
  PC_ERR_AST_001 = 'AS0001';

type

  { TPCNodeKind }
  // One value per concrete node class: nk + the class name without TPC.
  // nkNone is carried only by the abstract bases; no concrete class sets it.
  TPCNodeKind = (
    nkNone,
    // module level
    nkModule, nkImport, nkDirective, nkDirectiveArg, nkTest,
    // verbatim C++
    nkVerbatimStmt, nkVerbatimExpr,
    // declarations
    nkVarDecl, nkConstDecl, nkTypeDecl, nkRoutine, nkParam,
    // types
    nkBuiltinType, nkNamedType, nkPointerType, nkOwnerType, nkArrayType, nkCppType,
    nkRecordType, nkOverlayType, nkField, nkAnonAggregate, nkMethodItem, nkInitItem, nkDoneItem,
    nkCopyItem, nkPropertyItem, nkAccessorItem, nkOperatorItem, nkErrorMember, nkChoicesType, nkChoiceValue,
    nkSetType, nkRoutineType, nkOpaqueType,
    nkErrorType, nkNilType, nkVoidType, nkStringLiteralType, nkDerivedType, nkTemplateArg,
    nkNamePart,
    // statements
    nkBlock, nkIf, nkWhile, nkFor, nkRepeat, nkMatch, nkMatchArm,
    nkMatchLabel, nkGuard, nkReturn, nkLeave, nkSkip, nkExprStmt, nkErrorStmt,
    // expressions
    nkAssign, nkTernary, nkBinary, nkUnary, nkCall, nkIndex, nkMember,
    nkName, nkLiteral, nkSpecial, nkCast, nkNew, nkDelete, nkOwnerNew, nkTypeTest, nkBracedInit,
    nkSetLiteral, nkSetElement, nkRecordLiteral, nkFieldInit, nkVarargs, nkErrorExpr
  );

  { TPCModuleKind }
  TPCModuleKind = (mkExe, mkDll, mkLib, mkUnit);

  { TPCLinkage }
  // lnNone = not written; the default linkage is cpplink (BNF.md sec 3)
  TPCLinkage = (lnNone, lnC, lnCpp);

  { TPCParamMode }
  TPCParamMode = (pmNone, pmVar, pmConst);

  { TPCOwnerKind }
  // PLAN-OBJECT O6 (D4): how an owner type holds its object on the heap:
  // okOwn the sole owner, okRef a shared owner, okWeak a non-owning watcher
  TPCOwnerKind = (okOwn, okRef, okWeak);

  { TPCRoutineKind }
  // rnInit / rnDone: an object's init / done (PLAN-OBJECT D3), never called by name;
  // rnCopy: its copy (PLAN-OBJECT O5, D5), never called by name either;
  // rnRead / rnWrite: a property's inline accessor (PLAN-OBJECT O9, D12),
  // run by reading / assigning the property, never called by name;
  // rnOperator: a record's / object's operator (PLAN-OBJECT O11, D13), run
  // by the operator it declares, never called by name, no self
  TPCRoutineKind = (rnRoutine, rnMethod, rnInit, rnDone, rnCopy, rnRead, rnWrite, rnOperator);

  { TPCRoutineValueKind }
  // What a name or member names when it is a routine used as a value
  // (TPCExpr.RoutineValueOf, PLAN-RECORDS R5): rvRoutine one routine,
  // rvSet an overload set no position has bound yet, rvMethod a method (or
  // a set of them), rvNone not a routine value
  TPCRoutineValueKind = (rvNone, rvRoutine, rvSet, rvMethod);

  { TPCEmitTarget }
  TPCEmitTarget = (etHeader, etSource, etInPlace);

  { TPCOutFile }
  TPCOutFile = (ofHeader, ofSource);

  { TPCVerbatimKind }
  // vkCppTypeId: a template argument PaskalCPP does not model (BNF.md sec 4)
  TPCVerbatimKind = (vkCppDecl, vkCppBlock, vkCppExpr, vkPreproc, vkLambda,
    vkOpaqueGroup, vkCppTypeId);

  { TPCResolvedKind }
  // rkOpaque: a C/C++ name whose type PaskalCPP does not know; clang judges it;
  // rkProperty: an object's property (PLAN-OBJECT O9): read through its read,
  // assigned through its write, never storage (ResolvedDecl = TPCPropertyItem)
  TPCResolvedKind = (rkNone, rkVar, rkConst, rkType, rkRoutine, rkParam,
    rkField, rkChoiceValue, rkModule, rkIntrinsic, rkOpaque, rkProperty);

  { TPCAssignOp }
  TPCAssignOp = (aoAssign, aoAddAssign, aoSubAssign, aoMulAssign, aoDivAssign,
    aoModAssign, aoBitAndAssign, aoBitOrAssign, aoShlAssign, aoShrAssign);

  { TPCBinaryOp }
  // By meaning, not spelling: the token is in the node's Range
  TPCBinaryOp = (boLogOr, boLogAnd, boEq, boNotEq, boLess, boGreater,
    boLessEq, boGreaterEq, boThreeWay, boIn, boAdd, boSub, boBitOr, boBitXor,
    boShl, boShr, boMul, boDiv, boIntDiv, boMod, boBitAnd);

  { TPCUnaryOp }
  // uoDeref covers prefix * and postfix ^ (same meaning)
  TPCUnaryOp = (uoLogNot, uoBitNot, uoNegate, uoPlus, uoAddressOf, uoDeref,
    uoPreInc, uoPreDec, uoPostInc, uoPostDec);

  { TPCCastKind }
  TPCCastKind = (ckBuiltin, ckPointer, ckCStyle, ckStatic, ckReinterpret,
    ckConst, ckDynamic);

  { TPCMemberAccess }
  TPCMemberAccess = (maDot, maArrow);

  { TPCLiteralKind }
  TPCLiteralKind = (lkInteger, lkFloat, lkString, lkChar, lkBool, lkNil);

  { TPCSpecialKind }
  TPCSpecialKind = (skSelf, skParent, skThis, skNullptr);

  { TPCVarargsKind }
  // vaPlain: the bare word; the others: varargs.count, .next(T), .get(I, T),
  // .reset(), .copy() (research\cppmix\sem\varargs.md Q30)
  TPCVarargsKind = (vaPlain, vaCount, vaNext, vaGet, vaReset, vaCopy);

  { TPCNewInit }
  TPCNewInit = (niNone, niArgs, niArraySize, niBraced);

  { TPCRefKind }
  TPCRefKind = (rfNone, rfLValue, rfRValue);

  { TPCDirectiveArgKind }
  TPCDirectiveArgKind = (daIdentifier, daCString, daInteger);

  { TPCCvQualifier }
  TPCCvQualifier = (cqConst, cqVolatile);

  { TPCCvFlags }
  TPCCvFlags = set of TPCCvQualifier;

  { TPCDerivedKind }
  // A type SEM builds (research\cppmix\sem\types.md :25-30)
  TPCDerivedKind = (dkPointerTo, dkSetOf);

  { TPCGuardEscape }
  // A flow that leaves a guard body through its hidden function (statements.md :155-159)
  TPCGuardEscape = (geReturn, geLeave, geSkip);

  { TPCGuardEscapes }
  TPCGuardEscapes = set of TPCGuardEscape;

  { TPCIntrinsicKind }
  TPCIntrinsicKind = (ikNone, ikLen, ikSize, ikUtf8, ikParamCount, ikParamStr,
    ikGetMem, ikFreeMem, ikResizeMem, ikSetLength, ikCreate, ikDestroy,
    ikRaise, ikRaiseCode, ikExcCode, ikExcMsg, ikPrint, ikPrintLn,
    ikTestAssert, ikTestAssertTrue, ikTestAssertFalse, ikTestAssertNil,
    ikTestAssertNotNil, ikTestFail, ikTestAssertEqualInt,
    ikTestAssertEqualUInt, ikTestAssertEqualFloat, ikTestAssertEqualStr,
    ikTestAssertEqualBool, ikTestAssertEqualPtr, ikAlive, ikLock);

  { TPCIntrinsicKinds }
  TPCIntrinsicKinds = set of TPCIntrinsicKind;

  { TPCIntrinsicArg }
  // What one intrinsic argument must be (semantics.md :194-209): iaLength
  // string / wstring / array; iaInt32 / iaInt64 / iaUInt64 / iaFloat64 /
  // iaString / iaWString / iaBool converts implicitly to that type, the
  // runtime parameter's exact type (PLAN-INTRINSICS I1: no wider integer is
  // narrowed on the way in); iaPointer converts implicitly to untyped ptr; iaResizable a
  // string or dynamic array variable; iaHeapPtrVar / iaHeapPtr a pointer
  // TPCTypeExpr.HeapTargetOf does not call htNone: a record, an overlay, an
  // object (then SM0361) or opaque C/C++ (a variable / any value;
  // PLAN-RECORDS M1, PLAN-COMPLIANCE F36); iaWeak a weak T (PLAN-OBJECT O6, Q3)
  TPCIntrinsicArg = (iaNone, iaLength, iaWString, iaString, iaBool, iaInt32, iaInt64, iaUInt64,
    iaFloat64, iaPointer, iaResizable, iaHeapPtrVar, iaHeapPtr, iaWeak);

  { TPCIntrinsicValue }
  // The type an intrinsic call has: ivStatement = statement-only (VoidType);
  // ivLocked = ref T of the weak T argument (lock, PLAN-OBJECT O6)
  TPCIntrinsicValue = (ivNone, ivStatement, ivInt32, ivInt64, ivString, ivPointer, ivBool, ivLocked);

  { TPCIntrinsicSig }
  // One intrinsic's signature row (PC_INTRINSIC_SIGS)
  TPCIntrinsicSig = record
    ArgCount: Integer;
    Args: array[0..1] of TPCIntrinsicArg;
    Value: TPCIntrinsicValue;
  end;

const
  { PC_VARARGS_WORDS }
  // The PaskalCPP word of each varargs form (BNF.md sec 6): vaPlain the bare
  // word, the others its member words (varargs.count, .next(T), .get(I, T),
  // .reset(), .copy(); a varargs local's members alike), matched by
  // spelling. The one table of the parser, SEM, ExprText and completion
  PC_VARARGS_WORDS: array[TPCVarargsKind] of string = (
    'varargs', 'count', 'next', 'get', 'reset', 'copy'
  );

  { PC_OWNER_WORDS }
  // PLAN-OBJECT O6: the context word of each owner kind (own / ref / weak),
  // the one table of the parser, TypeText and the emitter
  PC_OWNER_WORDS: array[TPCOwnerKind] of TPCContextWord = (cwOwn, cwRef, cwWeak);

  { PC_INTRINSIC_NAMES }
  // The system scope (scopes.md :152-158): the one compiler-built name table,
  // BNF.md sec 7 / sec 8 spellings, exact case. Indexed by the enum, so a new
  // kind without a spelling does not compile
  PC_INTRINSIC_NAMES: array[TPCIntrinsicKind] of string = (
    '', 'len', 'size', 'utf8', 'paramcount', 'paramstr',
    'getmem', 'freemem', 'resizemem', 'setlength', 'create', 'destroy',
    'raise', 'raisecode', 'exccode', 'excmsg', 'print', 'println',
    'testAssert', 'testAssertTrue', 'testAssertFalse', 'testAssertNil',
    'testAssertNotNil', 'testFail', 'testAssertEqualInt',
    'testAssertEqualUInt', 'testAssertEqualFloat', 'testAssertEqualStr',
    'testAssertEqualBool', 'testAssertEqualPtr', 'alive', 'lock'
  );

  { PC_RUNTIME_INTRINSICS }
  // The intrinsics the emitter always writes as a call into the runtime
  // (::pcpp::utf8 ... ::pcpp::exc_msg, the test family's test_* / assert_*);
  // print / println only with a ptr to char argument (TPCAst.ModuleNamesRuntime)
  PC_RUNTIME_INTRINSICS: TPCIntrinsicKinds = [ikUtf8, ikParamCount, ikParamStr, ikGetMem, ikFreeMem,
    ikResizeMem, ikSetLength, ikCreate, ikDestroy, ikRaise, ikRaiseCode, ikExcCode, ikExcMsg, ikTestAssert..ikTestAssertEqualPtr, ikAlive, ikLock];

  { PC_RUNTIME_SPELLING }
  // The runtime's C++ scope as C++ text spells it (TPCAst.TextNamesRuntime)
  PC_RUNTIME_SPELLING = 'pcpp::';

  { PC_INTRINSIC_SIGS }
  // Each intrinsic's argument classes and value type (semantics.md :194-209,
  // BNF.md sec 7 / 8). size, print and println have rules of their own
  // (DoSizeCall; A7 PRINT): of their rows only Value is read
  PC_INTRINSIC_SIGS: array[TPCIntrinsicKind] of TPCIntrinsicSig = (
    (ArgCount: 0; Args: (iaNone, iaNone); Value: ivNone),              // ikNone
    (ArgCount: 1; Args: (iaLength, iaNone); Value: ivInt64),           // ikLen
    (ArgCount: 1; Args: (iaNone, iaNone); Value: ivInt64),             // ikSize
    (ArgCount: 1; Args: (iaWString, iaNone); Value: ivString),         // ikUtf8
    (ArgCount: 0; Args: (iaNone, iaNone); Value: ivInt32),             // ikParamCount
    (ArgCount: 1; Args: (iaInt32, iaNone); Value: ivString),           // ikParamStr
    (ArgCount: 1; Args: (iaInt64, iaNone); Value: ivPointer),          // ikGetMem
    (ArgCount: 1; Args: (iaPointer, iaNone); Value: ivStatement),      // ikFreeMem
    (ArgCount: 2; Args: (iaPointer, iaInt64); Value: ivPointer),       // ikResizeMem
    (ArgCount: 2; Args: (iaResizable, iaInt64); Value: ivStatement),   // ikSetLength
    (ArgCount: 1; Args: (iaHeapPtrVar, iaNone); Value: ivStatement), // ikCreate
    (ArgCount: 1; Args: (iaHeapPtr, iaNone); Value: ivStatement),    // ikDestroy
    (ArgCount: 1; Args: (iaString, iaNone); Value: ivStatement),       // ikRaise
    (ArgCount: 2; Args: (iaInt32, iaString); Value: ivStatement),      // ikRaiseCode
    (ArgCount: 0; Args: (iaNone, iaNone); Value: ivInt32),             // ikExcCode
    (ArgCount: 0; Args: (iaNone, iaNone); Value: ivString),            // ikExcMsg
    (ArgCount: 0; Args: (iaNone, iaNone); Value: ivStatement),         // ikPrint
    (ArgCount: 0; Args: (iaNone, iaNone); Value: ivStatement),         // ikPrintLn
    (ArgCount: 1; Args: (iaBool, iaNone); Value: ivStatement),         // ikTestAssert
    (ArgCount: 1; Args: (iaBool, iaNone); Value: ivStatement),         // ikTestAssertTrue
    (ArgCount: 1; Args: (iaBool, iaNone); Value: ivStatement),         // ikTestAssertFalse
    (ArgCount: 1; Args: (iaPointer, iaNone); Value: ivStatement),      // ikTestAssertNil
    (ArgCount: 1; Args: (iaPointer, iaNone); Value: ivStatement),      // ikTestAssertNotNil
    (ArgCount: 1; Args: (iaString, iaNone); Value: ivStatement),       // ikTestFail
    (ArgCount: 2; Args: (iaInt64, iaInt64); Value: ivStatement),       // ikTestAssertEqualInt
    (ArgCount: 2; Args: (iaUInt64, iaUInt64); Value: ivStatement),     // ikTestAssertEqualUInt
    (ArgCount: 2; Args: (iaFloat64, iaFloat64); Value: ivStatement),   // ikTestAssertEqualFloat
    (ArgCount: 2; Args: (iaString, iaString); Value: ivStatement),     // ikTestAssertEqualStr
    (ArgCount: 2; Args: (iaBool, iaBool); Value: ivStatement),         // ikTestAssertEqualBool
    (ArgCount: 2; Args: (iaPointer, iaPointer); Value: ivStatement),   // ikTestAssertEqualPtr
    (ArgCount: 1; Args: (iaWeak, iaNone); Value: ivBool),              // ikAlive
    (ArgCount: 1; Args: (iaWeak, iaNone); Value: ivLocked)             // ikLock
  );

type

  { TPCIntrinsicSigs }
  // The intrinsic signature table read by name: the argument list text
  // SM0409 prints and the LSP shows (one routine, SEM and the LSP share it)
  TPCIntrinsicSigs = record
    class function SigText(const AKind: TPCIntrinsicKind): string; static;
  end;

  { TPCEmitSpan }
  // Where a node landed in the generated C++: one span per emitted line
  TPCEmitSpan = record
    OutFile: TPCOutFile;
    CppLine: UInt64;      // line in the generated file
    SourceLine: UInt64;   // the #line value written before CppLine
    StartCol: UInt64;     // C++ byte column, inclusive
    EndCol: UInt64;       // C++ byte column, exclusive
  end;

  { TPCValueRun }
  // One run of a string part's value map (P-STRPOS, research\cppmix\sem\
  // prereq-b\strpos.md): value bytes from ValueOffset on came from (Line,
  // Column) of the .pcpp file. IsCopy: copied source, byte ValueOffset + N sits
  // at Column + N; otherwise an escape, every byte of it maps to its '\'
  TPCValueRun = record
    ValueOffset: Integer;   // byte offset in the part's value as UTF-8
    Line: UInt64;           // .pcpp line of the run's first source byte
    Column: UInt64;         // its 1-based byte column (SourceText FillRange's)
    IsCopy: Boolean;
  end;

  { TPCVerbatim }
  // Verbatim C++: Text is the exact source slice, never trimmed (vkCppExpr:
  // the decoded string value); bytes the conditional filter dropped are
  // spaces, CR and LF kept (F1). Range is its byte range in the source file.
  // InsideLines: the source lines (Range numbering, ascending) that start
  // inside a C++ token or comment of Text; the emitter writes no #line
  // before them (PROJECT.md Emitter Contracts, R23). EscapingJumps: every C++
  // return / break / continue of a cppstart block in a body that leaves the
  // block, in source order (TPCCppJumpFinder, O-S6b); nil = none, and nil for
  // every other verbatim. ValueMap (vkCppExpr only, parser): the decoded
  // value's map back to the string's source bytes, as a literal part's
  // (P-STRPOS), so a C++ location inside the value maps to the character it
  // came from (TranslateLocation, DESIGN.md sec 5); nil for every other verbatim
  TPCVerbatim = record
    Text: string;
    Range: TSourceRange;
    VerbatimKind: TPCVerbatimKind;
    EmitTarget: TPCEmitTarget;
    InsideLines: TArray<UInt64>;
    EscapingJumps: TArray<TPCCppJump>;
    ValueMap: TArray<TPCValueRun>;
  end;

  { TPCExternalLibKind }
  // How an external clause names its library (research\cppmix\sem\decls.md
  // F-D1): elNone = no library; elCString = a "..." library name, LibText its
  // decoded value; elIdentifier = a const string SEM resolves, LibText its spelling
  TPCExternalLibKind = (elNone, elCString, elIdentifier);

  { TPCExternal }
  TPCExternal = record
    IsExternal: Boolean;
    LibKind: TPCExternalLibKind;
    LibText: string;
    // parser: the library's token (the cstring or the identifier); empty
    // with elNone. Where a library zig cannot find is reported (LocateLibrary)
    LibRange: TSourceRange;
    ResolvedLib: string;
  end;

  { TPCLiteralPart }
  // One string token of a literal (adjacent string tokens are joined), with
  // the token's literal facts: semantics types the literal from them, never
  // by re-reading Text (research\cppmix\sem\inputs.md F1)
  TPCLiteralPart = record
    Text: string;
    // What the emitter writes (parser, F65): a plain part's Text with every
    // unknown escape's '\' dropped (TPCCString.CppSpelling: PR0021 reported
    // it, so clang never judges it again); a prefixed / raw part = Text
    CppText: string;
    Range: TSourceRange;
    LiteralPrefix: TPCLiteralPrefix;  // u8 / u / U / L; lpNone = plain
    IsRawString: Boolean;             // R"d(...)d"
    Suffix: string;                   // '' = none
    IsUserDefined: Boolean;           // the suffix is a C++ user-defined one
    // A plain part's decoded text (TPCCString.Decode; a warning keeps the
    // value): the parser decodes, nobody re-reads Text (sem\module.md F-M1)
    HasValue: Boolean;
    Value: string;
    // HasValue only (nil otherwise): decoded byte -> .pcpp position. Byte N =
    // the run with the greatest ValueOffset <= N (strpos.md :82-83)
    ValueMap: TArray<TPCValueRun>;
  end;

  { TPCNode }
  // Forward declarations: the full declarations follow below
  TPCNode = class;
  { TPCTypeExpr }
  TPCTypeExpr = class;
  { TPCModule }
  TPCModule = class;
  { TPCRoutine }
  TPCRoutine = class;
  { TPCNamedType }
  TPCNamedType = class;
  { TPCExpr }
  TPCExpr = class;
  { TPCInitItem }
  TPCInitItem = class;
  { TPCPropertyItem }
  TPCPropertyItem = class;
  { TPCRoutineMember }
  TPCRoutineMember = class;
  { TPCCall }
  TPCCall = class;

  { TPCNodeClass }
  TPCNodeClass = class of TPCNode;

  { TPCNodeVisitor }
  TPCNodeVisitor = reference to procedure(const ANode: TPCNode);

  { TPCNode }
  TPCNode = class(TBaseObject)
  private
    FEmitSpans: TArray<TPCEmitSpan>;
    procedure DoDumpTree(const ABuilder: TStringBuilder; const ADepth: Integer);
  protected
    FNodeKind: TPCNodeKind;
    // This node's own line text (after the kind name); '' = none
    function DoDumpText(): string; virtual;
    // Resolved* facts, each with a leading space; '' = none set
    function DoDumpResolved(): string; virtual;
    class procedure VisitNode(const ANode: TPCNode; const AVisit: TPCNodeVisitor); static;
    class procedure VisitList<T: TPCNode>(const AList: TList<T>; const AVisit: TPCNodeVisitor); static;
    class function QuoteText(const AText: string): string; static;
  public
    Range: TSourceRange;
    // Parser: an error was reported inside this node and the node was kept
    // with what parsed (PLAN-RECOVERY); SEM reports nothing inside it
    IsRecovered: Boolean;
    constructor Create(); override;
    function Dump(const AId: Integer = 0): string; override;
    // Visits the OWNED children in source order, skipping nil; never the
    // Resolved* references or TPCImport.ImportedModule
    procedure EnumChildren(const AVisit: TPCNodeVisitor); virtual;
    // The emitter's only write (PROJECT.md: the one emitter write)
    procedure AddEmitSpan(const ASpan: TPCEmitSpan);
    function KindName(): string;
    class function NodeClass(): TPCNodeClass;
    // Exact text of a double (D-PA2): inf / -inf / nan / -0 spelled; else the
    // shortest of 15..17 digits that decodes (TPCFloatDecoder) to the same
    // bits; none -> 17 digits + '#' + the 16 hex digits of the bits
    class function FloatText(const AValue: Double): string; static;
    property NodeKind: TPCNodeKind read FNodeKind;
    property EmitSpans: TArray<TPCEmitSpan> read FEmitSpans;
  end;

  { TPCStmt }
  // Statements and declarations (declaration blocks appear in bodies)
  TPCStmt = class(TPCNode)
  end;

  { TPCPrintForm }
  // How print / println hands an argument (after the format) to std::format
  // (PLAN-PASKAL-ERRORS E4): pfAsIs as written; pfCStr a ptr to [const] char
  // (::pcpp::CStr, nil prints nil); pfWCStr a ptr to [const] wchar
  // (::pcpp::WCStr); pfWideChar a wchar (::pcpp::utf8 of one character);
  // pfWideText a wstring (::pcpp::utf8). Wide text reaches the format as UTF-8.
  // E7 (F29): pfTypedAddress a pointer to any other type (its address, as an
  // untyped ptr prints); pfRoutineAddress a routine value (its address);
  // pfElements an array whose element has a form of its own (each element
  // through ::pcpp::print_map); pfUnprintable a record, object or overlay, or
  // an array of one (SEM reports SM0425: nothing is emitted for it);
  // pfNoAddress a routine name that has no single plain address (an
  // overload set, a method: SM0425 too); pfCppChecked a C/C++ type (the
  // opaque tier) or an array of one: only clang knows whether std::format
  // takes it, so the emitter writes the formatter check (SM0425 at the
  // argument) and passes it through ::pcpp::print_arg
  TPCPrintForm = (
    pfAsIs,
    pfCStr,
    pfWCStr,
    pfWideChar,
    pfWideText,
    pfTypedAddress,
    pfRoutineAddress,
    pfElements,
    pfUnprintable,
    pfNoAddress,
    pfCppChecked
  );

  { TPCPolyCheck }
  // PLAN-OBJECT O13b: which rule a polymorphism only clang knows decides
  // (TPCExpr.ResolvedPolyCheck). pcIsPolymorphic: is / as needs a
  // polymorphic operand (SM0271); pcSlice: a value converted to an ancestor
  // must not be polymorphic (SM0428); pcSliceHeld: a copy from where a
  // descendant may be, the same (SM0428); pcSliceAssign: := into where a
  // descendant may be (SM0429); pcOwnUpcast: an own handed to an own of an
  // ancestor needs that ancestor polymorphic (SM0200)
  TPCPolyCheck = (pcNone, pcIsPolymorphic, pcSlice, pcSliceHeld, pcSliceAssign, pcOwnUpcast);

  { TPCFieldPacking }
  // Whether a field of this type packs inside a packed record (PLAN-RECORDS
  // M9: clang packs plain data only, research\drop-object\r4b-misaligned.md):
  // fpPacks every leaf is plain data PaskalCPP lays out (a scalar, pointer,
  // routine type, choices, set, static array, record with a member parent,
  // overlay); fpNeverPacks a string, wstring or dynamic array is held by value
  // (SEM's SM0331); fpClangDecides a leaf only clang lays out (a C/C++ type, a
  // C/C++ parent, an object), so the emitter asserts ::pcpp::packs_as_field
  // and its failure is SM0331 too. fpNeverPacks outranks fpClangDecides
  TPCFieldPacking = (
    fpPacks,
    fpClangDecides,
    fpNeverPacks
  );

  { TPCOverlayFit }
  // Whether a field of this type may share an overlay's storage (a C++ union
  // member: PLAN-COMPLIANCE F34): its C++ form must be trivial data (trivially
  // default-constructible and copyable), or the union's own special members
  // are deleted. ofFits every leaf is trivial data PaskalCPP lays out (a
  // scalar, pointer, routine type, choices, set, static array, record, and an
  // overlay: judged at its own declaration); ofNeverFits a string, wstring,
  // dynamic array, object or own / ref / weak is held by value (SEM's SM0313;
  // an object or owner is SM0357's); ofClangDecides a leaf only clang knows
  // (a C/C++ type, a C/C++ parent), so the emitter asserts
  // ::pcpp::fits_overlay and its failure is SM0313 too. ofNeverFits outranks
  // ofClangDecides
  TPCOverlayFit = (
    ofFits,
    ofClangDecides,
    ofNeverFits
  );

  { TPCHeapTarget }
  // What a pointer's target is for create / destroy (PLAN-COMPLIANCE F36):
  // htNone not a typed pointer to one of the kinds below (SM0409); htData a
  // record or an overlay, plain data PaskalCPP lays out (built `new T{}`,
  // zeroed as every value-initialized site); htObject an object (SM0361: an
  // own / ref holds one); htOpaque a C/C++ type (clang's)
  TPCHeapTarget = (
    htNone,
    htData,
    htObject,
    htOpaque
  );

  { TPCTypeExpr }
  // Every type form and type definition
  TPCTypeExpr = class(TPCNode)
  public
    // The PaskalCPP / C++ spelling of the type, as a message prints it
    // (`int32`, `ptr to const char`, `Geo.TPoint`, `const std::string&`)
    function TypeText(): string; virtual;
    // Follows TPCNamedType rkType through its declaration (a forward through
    // ResolvedFull) to the type definition, repeatedly (types.md :54-55);
    // every other node is its own Canon. Reads Resolved* fields only
    function Canon(): TPCTypeExpr;
    // True when the type holds a string, wstring or dynamic array by value,
    // through aliases, records (parent included), overlays and static arrays
    // (decls.md :80-88: EMIT's constexpr / inline const choice)
    function HoldsStringOrDynamicArray(): Boolean;
    // How a field of this type packs inside a packed record (TPCFieldPacking,
    // PLAN-RECORDS M9): the one rule of SEM's SM0331 and the emitter's
    // packed-field check. Reads Resolved* fields only (Canon)
    function FieldPacking(): TPCFieldPacking;
    // How a field of this type fits in an overlay (TPCOverlayFit, F34): the
    // one rule of SEM's SM0313 and the emitter's overlay-field check. Reads
    // Resolved* fields only (Canon)
    function OverlayFit(): TPCOverlayFit;
    // True when the type is a scalar (integer, float, bool, char, wchar,
    // choices) or a pointer (ptr, routine type): a `const` parameter of it is
    // `const T` by value, the same signature as a plain one (emitter.md E10,
    // calls.md R-DECL F14). Strings, aggregates, arrays, sets, C types and
    // error types are not
    function IsScalarOrPointer(): Boolean;
    // A pointer type, tree or derived (types.md G8: treated alike): ATarget
    // its target (nil = untyped ptr), AIsConst its const target; False for
    // nil and every other type. The one pointer rule of SEM and the LSP
    class function PointerOf(const AType: TPCTypeExpr; out ATarget: TPCTypeExpr;
      out AIsConst: Boolean): Boolean; static;
    // What AType points to for create / destroy (TPCHeapTarget, F36);
    // ATarget = the pointer's target (nil for htNone). The one rule of SEM's
    // create / destroy checks (SM0409 / SM0361) and the emitter's create
    class function HeapTargetOf(const AType: TPCTypeExpr; out ATarget: TPCTypeExpr): TPCHeapTarget; static;
    // How print / println writes an argument of this type (TPCPrintForm;
    // a pointer is a PaskalCPP pointer type or the type of @c); pfAsIs for
    // nil. The one rule of SEM's print check (pfUnprintable = SM0425), the
    // emitter's DoWritePrint and TPCAst.ModuleNamesRuntime (replaces
    // IsCharPointer, E4; recursive on an array's element type, E7)
    class function PrintForm(const AType: TPCTypeExpr): TPCPrintForm; static;
    // The print form of one print / println argument (E7): a routine named as
    // a value has no type, only its kind, so the name decides (a routine
    // pfRoutineAddress; an overload set or a method pfNoAddress); every other
    // argument by PrintForm of its ResolvedType. The one rule SEM, the
    // emitter and TPCAst.ModuleNamesRuntime call
    class function PrintFormOfArg(const AArg: TPCExpr): TPCPrintForm; static;
    // The opaque tier (types.md "Two tiers", G3): a C/C++ type whose meaning
    // is clang's (an opaque, a cpp type, a name resolved rkOpaque), through
    // aliases; False for nil. The one rule of SEM and TPCScopes
    class function IsOpaqueTier(const AType: TPCTypeExpr): Boolean; static;
    // PLAN-OBJECT O5 / D5: why a value of AType cannot be copied
    // (TPCRecordType.MoveOnlyReason of the object it is, or holds as an
    // array's element: a copy of the array copies each one), nil = it can
    // (every type that is no object, a pointer, C/C++: clang's)
    class function MoveOnlyReasonOf(const AType: TPCTypeExpr): TPCNode; static;
  end;

  { TPCExpr }
  TPCExpr = class(TPCNode)
  protected
    function DoDumpResolved(): string; override;
  public
    ResolvedType: TPCTypeExpr;   // non-owning, written by semantics
    HasConstValue: Boolean;      // constant folding result (semantics)
    ConstIsUnsigned: Boolean;
    ConstInt: Int64;
    ConstUInt: UInt64;
    HasConstFloat: Boolean;      // float constant folding result (semantics, folding.md Q7)
    ConstFloat: Double;
    // semantics: a constant expression, folded or not (a string literal, a
    // string const): what a "must be a constant" position checks (SM0202)
    IsConstExpr: Boolean;
    // semantics (PLAN-RECORDS R4 / M10): this value, a pointer to a record
    // extension, converts implicitly to a pointer to the record this many
    // parent levels up (TPCScopes.Extends' AHops); the emitter writes the
    // upcast. 0 = no upcast (value / const / var upcasts need none: the
    // record's conversion operators)
    ResolvedUpcastHops: Integer;
    // semantics (PLAN-RECORDS M8): this value may sit misaligned (a field
    // reached through a packed record, OnPackedPath) and goes where C++ would
    // bind a reference to it (a const aggregate parameter, a const C++
    // reference, print / println, a variadic slot, the ranked overloads
    // form): the emitter writes a copy, auto(x), so the reference binds an
    // aligned temporary. Same meaning: nothing writes through those
    ResolvedIsCopied: Boolean;
    // semantics (PLAN-OBJECT O5, D5): this value is a local variable or a
    // value parameter of the routine, returned (`return LV;`): it ends there,
    // so it is moved, never copied (a type that cannot be copied is returned
    // too); the emitter writes std::move(x) in every return form
    ResolvedIsMoved: Boolean;
    // Semantics (PLAN-OBJECT O13b): a rule here depends on whether an object
    // is polymorphic, and only clang knows (its polymorphism comes from a
    // C/C++ base: TPCRecordType.PolymorphismIsClangs). The emitter writes
    // the check around the expression (once), naming ResolvedPolyType
    // (non-owning, as written); the Compiler reports a failed one with the
    // code of ResolvedPolyCheck and ResolvedPolyText, SEM's finished message
    ResolvedPolyCheck: TPCPolyCheck;
    ResolvedPolyType: TPCTypeExpr;
    ResolvedPolyText: string;
    // The PaskalCPP spelling of the expression (D-PA13); ExprPower is its
    // binding power (BNF.md sec 6), used to parenthesise operands
    function ExprText(): string; virtual;
    function ExprPower(): Integer; virtual;
    // An array / set bound as a message prints it (F44 / F46): an integer's
    // folded value, a char or choices bound as written; the one rule TypeText
    // and SEM's bound reports read
    function BoundText(): string;
    // A routine named as a value (rkRoutine on a TPCName / TPCMember; SEM
    // types it with no ResolvedType: its type is its signature). ARoutine =
    // the routine (rvRoutine, rvMethod) or one member of the set (a name's
    // ResolvedSetMember; nil for a module's set reached by a member). The one
    // rule of PrintFormOfArg and SEM's routine value check (PLAN-RECORDS R5)
    class function RoutineValueOf(const AValue: TPCExpr; out ARoutine: TPCRoutine): TPCRoutineValueKind; static;
    // PLAN-RECORDS M8 / R4b: where this value lives may be below its type's
    // alignment: a field placed by a packed level (its record packed, a
    // packed level between the base's record and the level declaring it,
    // a packed anonymous aggregate holding it), or a field / static array
    // element of a value that is itself on such a path ('.', index). A deref
    // ('^', '->') starts over: a pointer to T points to an aligned T. Reads
    // Resolved* only. SEM adds the type's alignment (above 1, or unknown) to
    // judge "may be misaligned"; the one placement rule
    function OnPackedPath(): Boolean;
  end;

  { TPCDecl }
  // Abstract base of the four declarations (var, const, type, routine)
  TPCDecl = class(TPCStmt)
  private
    // The one name predicate of both walks below
    class function DoIsNamed(const AStmt: TPCStmt; const ADeclName: string): Boolean; static;
  protected
    function DoDumpText(): string; override;
  public
    DeclName: string;
    NameRange: TSourceRange;        // parser: the name token (a section: its keyword)
    DocText: string;                // parser: its /// doc comment, raw ('' = none; PLAN-EDITOR E2.6)
    IsExported: Boolean;
    // Parser: the module whose Decls hold this declaration; nil = a local
    // declaration (routine, test, section or body). Non-owning; read by the
    // emitter for ::Module::Name (PLAN-EMITTER H1)
    DeclModule: TPCModule;
    // Every declaration named ADeclName among the first ACount items of a
    // declaration or statement list, in list order (exact case, BNF.md sec 9);
    // items that are not declarations (verbatim C++) are skipped. The one
    // name walk of every scope over a TList<TPCStmt> (sem\scopes.md F3)
    class procedure CollectNamed(const AItems: TList<TPCStmt>; const ACount: Integer;
      const ADeclName: string; const AFound: TList<TPCDecl>); static;
    // Every declaration named ADeclName among the items AFTER AIndex
    // (AIndex + 1 .. Count - 1), list order; AIndex < -1 is taken as -1 (all
    // items). The used-before scan's walk (sem\scopes.md F3)
    class procedure CollectNamedAfter(const AItems: TList<TPCStmt>; const AIndex: Integer;
      const ADeclName: string; const AFound: TList<TPCDecl>); static;
  end;

  { TPCDirectiveArg }
  TPCDirectiveArg = class(TPCNode)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    ArgKind: TPCDirectiveArgKind;
    Text: string;          // exact source text
    ResolvedText: string;  // parser: decoded cstring value, else Text; path directives resolved through TUtils.ResolvePath
    // parser: daInteger = the lexer computed the token's value (IntValue);
    // daCString = decoded and, for a path, resolved: ResolvedText is the value
    // ('' a real empty text); daIdentifier = False (ResolvedText is the spelling)
    HasValue: Boolean;
    IntValue: UInt64;      // the token's value when HasValue (inputs.md F2)
    constructor Create(); override;
  end;

  { TPCDirective }
  // A build directive: in the prologue, or a statement in a body (@breakpoint,
  // @message; BNF.md sec 5), so it is a TPCStmt (TPCStmt has no fields)
  TPCDirective = class(TPCStmt)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    DirectiveName: string;  // without the @
    DirectiveKind: TPCBuildDirective;  // parser: its PC_BUILD_DIRECTIVES row (D-A2-1)
    // SEM: a report says it is not applied (SM0102 SM0103 SM0104 SM0109 SM0110):
    // the Compiler sets nothing from it
    ResolvedNoEffect: Boolean;
    Args: TList<TPCDirectiveArg>;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCImport }
  TPCImport = class(TPCNode)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    ModuleName: string;
    ImportedModule: TPCModule;  // non-owning branch, written by the parser
    constructor Create(); override;
  end;

  { TPCBlock }
  // begin..end; module body, routine body, test body
  TPCBlock = class(TPCStmt)
  public
    Stmts: TList<TPCStmt>;
    EndRange: TSourceRange;         // parser: the closing end keyword; StartLine 0 = not there yet
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCLiteral }
  TPCLiteral = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
  public
    LiteralKind: TPCLiteralKind;
    Text: string;                    // exact source text
    // What the emitter writes for a number, char or bool (parser, F65): a plain
    // or L char's Text with an unknown escape's '\' dropped (PR0064 reported
    // it), else Text. A string writes its Parts' CppText
    CppText: string;
    Parts: TArray<TPCLiteralPart>;   // one per joined string token, each with its facts
    // The token's literal facts for a number or char (a string keeps them per
    // part): semantics types the literal from them (inputs.md F1)
    LiteralBase: TPCLiteralBase;     // numbers; lbNone otherwise
    LiteralPrefix: TPCLiteralPrefix; // chars; lpNone otherwise
    Suffix: string;                  // '' = none
    IsUserDefined: Boolean;          // the suffix is a C++ user-defined one
    HasValue: Boolean;               // IntValue / FloatValue copied from the token
    IntValue: UInt64;                // a plain / L char: the parser's TPCCString.DecodeChar value (P-CHAR)
    FloatValue: Double;
    IsMultiChar: Boolean;            // a plain char literal of several elements ('ab'): C++ int
    // Semantics (PLAN-VENDOR 1e): this string literal becomes a string /
    // wstring object (a conversion SEM accepted: :=, an initializer, an
    // argument, a return; an operand of + or a comparison beside a string).
    // With HoldsNul the emitter writes it at its full length (C++ builds a
    // std::string from a char pointer: it stopped at the first NUL)
    ResolvedToString: Boolean;
    constructor Create(); override;
    function ExprText(): string; override;
    // A string literal holds an element of value 0 (PLAN-VENDOR 1e): a plain
    // part's decoded value has a #0; an L part (no decoded value) a zero
    // escape (\0, \x0, \u0000, \U00000000, \o{0}, \x{0}); a raw part none
    function HoldsNul(): Boolean;
    // A plain string literal's value: its parts' Values joined (C++ phase 6)
    // when it has a part and every part HasValue; else False and ''
    // (sem\module.md :80, D-A2-10)
    function DecodedValue(out AValue: string): Boolean;
  end;

  { TPCTest }
  TPCTest = class(TPCNode)
  public
    TestName: TPCLiteral;   // the cstring literal
    Decls: TList<TPCStmt>;  // the var block
    Body: TPCBlock;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCVerbatimStmt }
  // Module-level cpp span, cppstart block, # line
  TPCVerbatimStmt = class(TPCStmt)
  protected
    function DoDumpText(): string; override;
  public
    Verbatim: TPCVerbatim;
    constructor Create(); override;
  end;

  { TPCErrorStmt }
  // Tokens the parser skipped after a report, in a statement or declaration
  // list (PLAN-RECOVERY); Range = the skipped tokens. Fragment: a parsed node
  // that has no slot (a repeated section, PR0018); nil = none
  TPCErrorStmt = class(TPCStmt)
  public
    Fragment: TPCNode;
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCVerbatimExpr }
  // Lambda, opaque group (sizeof ...), cpp("...")
  TPCVerbatimExpr = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
  public
    Verbatim: TPCVerbatim;
    constructor Create(); override;
    function ExprText(): string; override;
  end;

  { TPCErrorExpr }
  // An expression that failed after consuming tokens (PLAN-RECOVERY); Range =
  // its tokens. Parts: the sub-expressions parsed before the failure, in
  // source order (one that failed is itself a TPCErrorExpr), so their names
  // still resolve; SEM types it ErrorType
  TPCErrorExpr = class(TPCExpr)
  public
    Parts: TList<TPCExpr>;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
    function ExprText(): string; override;
  end;

  { TPCModule }
  TPCModule = class(TPCNode)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    ModuleName: string;
    NameRange: TSourceRange;        // parser: the header's name token; empty = no header (assumed kind)
    EndRange: TSourceRange;         // parser: the closing 'end' keyword (BNF sec 1); empty = not consumed
    ModuleKind: TPCModuleKind;
    SourceFile: string;   // resolved absolute path
    ResolvedTarget: TPCTargetTriple;  // parser, from the conditional filter (Q2); empty = not set
    // Parser: the range of every token the conditional filter did not keep
    // (inactive branches and the conditional directives themselves), in
    // source order; no node holds them (PLAN-EDITOR E2.10: the formatter
    // keeps the text around them as written)
    DroppedTokens: TArray<TSourceRange>;
    Directives: TList<TPCDirective>;
    Imports: TList<TPCImport>;
    Decls: TList<TPCStmt>;
    InitRoutine: TPCRoutine;   // initialize section (a routine, BNF sec 1); nil when absent
    FinalRoutine: TPCRoutine;  // finalize section (a routine); nil when absent
    HasBody: Boolean;
    Body: TPCBlock;       // nil when not HasBody
    Tests: TList<TPCTest>;
    // Semantics: the C++ emitted for this module's own constructs names the
    // runtime (test blocks and the main module's entry excluded;
    // TPCAst.ModuleNamesRuntime). The aggregate is TPCAst.UsesRuntime
    ResolvedUsesRuntime: Boolean;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCOpaqueType }
  // Any C/C++ type PaskalCPP does not model
  TPCOpaqueType = class(TPCTypeExpr)
  public
    constructor Create(); override;
    function TypeText(): string; override;
  end;

  { TPCErrorType }
  // Poison after a reported error; suppresses cascades
  TPCErrorType = class(TPCTypeExpr)
  public
    constructor Create(); override;
    function TypeText(): string; override;
  end;

  { TPCNilType }
  TPCNilType = class(TPCTypeExpr)
  public
    constructor Create(); override;
    function TypeText(): string; override;
  end;

  { TPCVoidType }
  // Result of a procedure call
  TPCVoidType = class(TPCTypeExpr)
  public
    constructor Create(); override;
    function TypeText(): string; override;
  end;

  { TPCStringLiteralType }
  // "..." / L"..." before conversion
  TPCStringLiteralType = class(TPCTypeExpr)
  protected
    function DoDumpText(): string; override;
  public
    IsWide: Boolean;
    constructor Create(); override;
    function TypeText(): string; override;
  end;

  { TPCDerivedType }
  // A type SEM builds (types.md :25-30, G8): address of, `new` of a PaskalCPP
  // type, a set literal. Target is NON-owning, so EnumChildren visits nothing
  // and a derived node never claims a tree node as its child
  TPCDerivedType = class(TPCTypeExpr)
  protected
    function DoDumpText(): string; override;
  public
    DerivedKind: TPCDerivedKind;
    Target: TPCTypeExpr;            // non-owning; nil = untyped ptr (dkPointerTo)
    IsConstTarget: Boolean;         // dkPointerTo only
    constructor Create(); override;
    function TypeText(): string; override;
  end;

  { TPCParam }
  TPCParam = class(TPCNode)
  protected
    function DoDumpText(): string; override;
  public
    ParamName: string;
    NameRange: TSourceRange;        // parser: the name token
    ParamMode: TPCParamMode;
    TypeExpr: TPCTypeExpr;
    // PLAN-OBJECT O9: a property's write(AValue) takes the property's type:
    // TypeExpr is then the property's own node, NON-owning (not a child: the
    // property holds it, SEM resolves it there once, the emitter borrows it)
    IsTypeBorrowed: Boolean;
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCSignature }
  // A routine's or a routine type's signature, one view of either (PLAN-RECORDS
  // R5): the meant linkage (lnC or lnCpp, never lnNone: M7 / F-R3b), the
  // owner's parameter list (non-owning), varargs and the result. Built on
  // demand by TPCRoutine.Signature / TPCRoutineType.Signature; a record, never
  // a node (nothing for a walker to visit twice)
  TPCSignature = record
    Linkage: TPCLinkage;
    Params: TList<TPCParam>;
    IsVariadic: Boolean;
    ReturnType: TPCTypeExpr;        // nil = procedure
    // routine clink(AN: int32; var AS: string; ...): bool; the linkage word
    // only for clink (cpplink is the default, BNF.md sec 3)
    function Text(): string;
  end;

  { TPCVarDecl }
  TPCVarDecl = class(TPCDecl)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    TypeExpr: TPCTypeExpr;
    InitExpr: TPCExpr;              // nil = no initializer
    ExternalClause: TPCExternal;    // `external` is a directive, not a field name
    // PLAN-OBJECT D3 / Q1 (parser): `LV: TFoo(1, 2);` builds the object with
    // the init that takes the arguments: the parenthesized list as a call
    // with no callee (Range = '(' .. ')'; `LV: TFoo();` too), so every
    // argument rule a call has applies; nil = no list written. SEM writes
    // the init it runs on the call (TPCCall.ResolvedInit)
    InitCall: TPCCall;
    // Semantics: the init a variable of an object type is built with when no
    // list is written (its init without parameters); nil = the type declares
    // no init (C++'s implicit default) or the variable is no object. Non-owning
    ResolvedInit: TPCInitItem;
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCConstDecl }
  TPCConstDecl = class(TPCDecl)
  public
    TypeExpr: TPCTypeExpr;          // always present: no inferred types
    ValueExpr: TPCExpr;
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
    // PLAN-VENDOR 1e: a string const whose value is a plain string literal
    // (a wstring const: an L literal; no prefix, no suffix on any part) also
    // exists as constant text in C++ (::pcpp::ConstText / ConstWText,
    // pcpp_text_<name>): a std::string is never a C++ constant, so the
    // emitter reads the twin where C++ may need one (print / println's
    // format, a C/C++ call's argument) and builds the object from it (an
    // embedded NUL is kept). AWide = the wstring form
    function HasConstText(out AWide: Boolean): Boolean;
  end;

  { TPCTypeDecl }
  TPCTypeDecl = class(TPCDecl)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    TypeDef: TPCTypeExpr;           // nil when IsForward
    IsForward: Boolean;
    ResolvedFull: TPCTypeDecl;      // semantics: the full declaration a forward resolves to
    ResolvedNamedType: TPCNamedType;  // semantics: the one TPCNamedType SEM builds naming this declaration (a choice value's or self's type); non-owning, never a child
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCRoutine }
  TPCRoutine = class(TPCDecl)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    RoutineKind: TPCRoutineKind;
    Linkage: TPCLinkage;            // as written; lnNone = not written
    ResolvedLinkage: TPCLinkage;    // semantics: after overload demotion
    Params: TList<TPCParam>;
    IsVariadic: Boolean;
    VariadicRange: TSourceRange;    // parser: the '...' token (IsVariadic)
    ReturnType: TPCTypeExpr;        // nil = procedure; rnRead: its property's type, NON-owning (O9)
    ExternalClause: TPCExternal;
    Decls: TList<TPCStmt>;          // declaration blocks before begin
    Body: TPCBlock;                 // nil when external or IsForward
    IsForward: Boolean;
    ResolvedFull: TPCRoutine;       // semantics: the full routine a forward resolves to
    // Parser (PLAN-OBJECT O13b (3), user 2026-10-14 "(a)"): `const method`:
    // the method changes nothing of self (emitted as a C++ const member
    // function, so it overrides a C++ const virtual); ConstRange = the word.
    // Only on an rnMethod routine
    IsConst: Boolean;
    ConstRange: TSourceRange;
    // PLAN-OBJECT O14: the member item holding this routine (a method, init,
    // done, copy, operator or an inline accessor), written by
    // TPCRoutineMember.Routine's setter; nil = not a member's routine.
    // Non-owning: the words written before the routine (virtual, override,
    // final, abstract, hidden) live on the member, the tools read them here
    OwnerMember: TPCRoutineMember;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
    // The linkage the routine has: SEM's ResolvedLinkage once written (an
    // overload set's demotion included), before that the written word (none
    // = cpplink, BNF.md sec 3)
    function MeantLinkage(): TPCLinkage;
    function Signature(): TPCSignature;
  end;

  { TPCTemplateArg }
  // Exactly one of TypeArg / ExprArg / Verbatim is set (BNF.md sec 4):
  // HasVerbatim = a cpp type id copied verbatim (vkCppTypeId, in place)
  TPCTemplateArg = class(TPCNode)
  protected
    function DoDumpText(): string; override;
  public
    TypeArg: TPCTypeExpr;
    ExprArg: TPCExpr;
    HasVerbatim: Boolean;
    Verbatim: TPCVerbatim;
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCNamePart }
  // One identifier of a C++ or qualified name with its template args;
  // HasTemplateArgs separates an empty list (std::less<>) from no list
  TPCNamePart = class(TPCNode)
  protected
    function DoDumpText(): string; override;
  public
    PartText: string;
    HasTemplateArgs: Boolean;
    TemplateArgs: TList<TPCTemplateArg>;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCBuiltinType }
  // A PaskalCPP primitive (int8 .. wstring). Bare ptr / set are
  // TPCPointerType / TPCSetType, never a builtin token
  TPCBuiltinType = class(TPCTypeExpr)
  protected
    function DoDumpText(): string; override;
  public
    BuiltinToken: TPCTokenKind;
    constructor Create(); override;
    function TypeText(): string; override;
  end;

  { TPCNamedType }
  // A bare or dotted name; one PaskalCPP cannot resolve is an opaque C++ type
  TPCNamedType = class(TPCTypeExpr)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    Parts: TArray<string>;
    ResolvedDecl: TPCTypeDecl;      // semantics; nil for rkOpaque
    ResolvedKind: TPCResolvedKind;  // semantics: rkType or rkOpaque
    constructor Create(); override;
    function TypeText(): string; override;
  end;

  { TPCPointerType }
  TPCPointerType = class(TPCTypeExpr)
  protected
    function DoDumpText(): string; override;
  public
    TargetType: TPCTypeExpr;        // nil = untyped ptr
    IsConstTarget: Boolean;
    constructor Create(); override;
    function TypeText(): string; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCOwnerType }
  // PLAN-OBJECT O6 (D4): `own T` / `ref T` / `weak T`, an object on the heap
  // held by its sole owner, a shared owner or a watcher; the words are
  // context words (PC_CONTEXT_WORDS), a type only before a type name
  TPCOwnerType = class(TPCTypeExpr)
  protected
    function DoDumpText(): string; override;
  public
    OwnerKind: TPCOwnerKind;
    TargetType: TPCTypeExpr;        // the object type held (SEM: an object)
    constructor Create(); override;
    function TypeText(): string; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCArrayType }
  TPCArrayType = class(TPCTypeExpr)
  protected
    function DoDumpText(): string; override;
  public
    IsDynamic: Boolean;
    LowExpr: TPCExpr;               // nil when IsDynamic; semantics folds both bounds
    HighExpr: TPCExpr;
    ElementType: TPCTypeExpr;
    constructor Create(); override;
    function TypeText(): string; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCCppType }
  // A C/C++ type as C++ spells it: Fundamentals (unsigned long), NameParts
  // (std::vector<T>, after an elaborated key: struct stat) or a decltype head,
  // then cv, one cv set per pointer level, one reference
  TPCCppType = class(TPCTypeExpr)
  protected
    function DoDumpText(): string; override;
  public
    LeadCv: TPCCvFlags;
    HasElaborated: Boolean;         // struct / class / union / enum before the name (T14)
    ElaboratedKey: TPCTokenKind;
    HasDecltype: Boolean;           // decltype( ... ) head, verbatim (T15)
    Decltype: TPCVerbatim;
    Fundamentals: TArray<TPCTokenKind>;
    HasLeadingScope: Boolean;       // leading ::
    NameParts: TList<TPCNamePart>;
    TrailCv: TPCCvFlags;
    PointerLevels: TArray<TPCCvFlags>;  // one entry per *, the cv after it
    RefKind: TPCRefKind;
    constructor Create(); override;
    function TypeText(): string; override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCMemberItem }
  // Abstract base of a record, object or overlay member (nkNone)
  TPCMemberItem = class(TPCNode)
  public
    // PLAN-OBJECT D10: `hidden` before an object's field or method (parser):
    // reached only by the methods of its type and of its descendants
    // (TPCScopes.ReachesHidden); HiddenRange = the word ('hidden' elsewhere is
    // PR0034, kept)
    IsHidden: Boolean;
    HiddenRange: TSourceRange;
    // Parser (PLAN-OBJECT O14): a method or property of an interface: its
    // dispatch facts (virtual, abstract) are the grammar's, never written,
    // so a tool that shows the declaration as written leaves them out
    IsInterfaceMember: Boolean;
  end;

  { TPCErrorMember }
  // Tokens the parser skipped after a report in a member list
  // (PLAN-RECOVERY); Range = the skipped tokens
  TPCErrorMember = class(TPCMemberItem)
  public
    constructor Create(); override;
  end;

  { TPCField }
  TPCField = class(TPCMemberItem)
  protected
    function DoDumpText(): string; override;
  public
    FieldName: string;
    NameRange: TSourceRange;        // parser: the name token
    DocText: string;                // parser: its /// doc comment, raw ('' = none)
    TypeExpr: TPCTypeExpr;
    BitWidthExpr: TPCExpr;          // nil = not a bitfield
    // PLAN-OBJECT D2 / O8 (parser): `embed F: T;` in an object: a field (it
    // is one: layout, init, copy, done follow the field rules) whose type's
    // members are reached on the owner too (TPCScopes.FindPromoted).
    // EmbedRange = the word; Range starts there
    IsEmbed: Boolean;
    EmbedRange: TSourceRange;
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
    // A bitfield of wchar (or of an alias of wchar): the emitter writes it
    // char16_t on every target (F25), so SEM lays it out as char16_t too
    // (natural alignment, PLAN-PASKAL-ERRORS E3). The one rule both read
    function IsWCharBitfield(): Boolean;
    // A bitfield of a choices type (or of an alias of one): the emitter
    // stores it as the type's underlying integer and casts at every read and
    // store (F37: clang's constant-store check reads a scoped-enum bitfield
    // as unsigned and reports a value change that does not happen). The
    // layout is the same; SEM keeps the field's PaskalCPP type
    function IsChoicesBitfield(): Boolean;
  end;

  { TPCAnonAggregate }
  // Anonymous record inside an overlay, or anonymous overlay inside a record
  TPCAnonAggregate = class(TPCMemberItem)
  protected
    function DoDumpText(): string; override;
  public
    IsOverlay: Boolean;
    IsPacked: Boolean;
    Members: TList<TPCMemberItem>;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCRoutineMember }
  // Abstract base of a member that holds a routine (nkNone): a method, an
  // init, a done, a copy, an operator or a property's accessor. A walk that
  // needs a member's body (scopes, the semantic walk, layout, the formatter)
  // asks for this class; name lookup and dispatch ask for TPCMethodItem:
  // init / done have no name to look up (PLAN-OBJECT D3)
  TPCRoutineMember = class(TPCMemberItem)
  private
    FRoutine: TPCRoutine;
    procedure SetRoutine(const ARoutine: TPCRoutine);
  public
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
    // Setting it also writes the routine's OwnerMember (O14): every member
    // kind gets the link, none can forget it
    property Routine: TPCRoutine read FRoutine write SetRoutine;
  end;

  { TPCMethodItem }
  TPCMethodItem = class(TPCRoutineMember)
  public
    // Routine.RoutineKind = rnMethod
    // PLAN-OBJECT D7 (parser): the words before 'method' and the body slot.
    // virtual opens dispatch, override continues a parent's, final closes it,
    // abstract (`; abstract;`) replaces the body (Routine.Body = nil). Each
    // range is its word (SEM reports a rule about it there)
    IsVirtual: Boolean;
    IsOverride: Boolean;
    IsFinal: Boolean;
    IsAbstract: Boolean;
    VirtualRange: TSourceRange;
    OverrideRange: TSourceRange;
    FinalRange: TSourceRange;
    AbstractRange: TSourceRange;
    // Semantics: the parent level's method this one overrides (the nearest
    // level declaring the name); nil = it overrides nothing. Non-owning
    ResolvedOverrides: TPCMethodItem;
    // Semantics (PLAN-OBJECT O7): the interface method this one implements
    // (its object lists that interface, or a parent of it does): the emitter
    // writes C++'s override on it. nil = none. Non-owning
    ResolvedImplements: TPCMethodItem;
    constructor Create(); override;
    // virtual or override: the method is called through the object's vtable
    function IsDispatched(): Boolean;
  end;

  { TPCInitItem }
  // PLAN-OBJECT D3: `init(params); [var block] block;` in an object, its own
  // member kind (Routine.RoutineKind = rnInit, DeclName 'init', no result).
  // It runs when an object is built and is never called by name, except as
  // a leading statement of another init: `parent.init(...)` first, then
  // `self.F.init(...)` for the type's own object fields (TPCCall.ResolvedInit)
  TPCInitItem = class(TPCRoutineMember)
  public
    WordRange: TSourceRange;        // parser: the word init
    // Semantics: how many of Routine.Body.Stmts, from the first, are leading
    // init calls; the emitter writes them into the C++ member-init list and
    // the rest as the constructor's body
    ResolvedLeadCount: Integer;
    constructor Create(); override;
  end;

  { TPCDoneItem }
  // PLAN-OBJECT D3: `done; [var block] block;` in an object, its own member
  // kind (Routine.RoutineKind = rnDone, DeclName 'done'): runs when the
  // object ends, never called by name; one per type
  TPCDoneItem = class(TPCRoutineMember)
  public
    WordRange: TSourceRange;        // parser: the word done
    constructor Create(); override;
  end;

  { TPCCopyItem }
  // PLAN-OBJECT O5 / D5: `copy(const ASource: T); [var block] block;` in an
  // object (Routine.RoutineKind = rnCopy, DeclName 'copy'): it builds the
  // object as a copy of ASource, as an init builds one (its fields start
  // empty, its leading `self.F.init(...)` calls build fields that need
  // arguments, the body fills the rest); the parent part is copied by the
  // parent's own copy. Runs for `LA := LB`, a value argument, a returned
  // copy; never called by name. A TPCInitItem for the leading-call rules
  // and the constructor's shape; never one of the type's inits (SEM's
  // DoOwnInits, the emitter's init tags leave it out)
  TPCCopyItem = class(TPCInitItem)
  public
    constructor Create(); override;
  end;

  { TPCAccessorItem }
  // PLAN-OBJECT O9 / D12: a property's read or write (IsWrite), held by its
  // TPCPropertyItem, never in a member list. A field binding (`read F;` /
  // `write F;`) has FieldName / FieldRange and no Routine; an inline one
  // (`read [var block] block;` / `write(AValue) [var block] block;`) has
  // Routine (rnRead: ReturnType = the property's type; rnWrite: one value
  // parameter of it, both NON-owning). IsHidden: a hidden property hides
  // both, `hidden write` its write only. A TPCRoutineMember so a walk that
  // needs a member's body (scopes, SEM, the formatter) takes it as a method's
  TPCAccessorItem = class(TPCRoutineMember)
  protected
    function DoDumpText(): string; override;
  public
    IsWrite: Boolean;
    WordRange: TSourceRange;        // parser: the word read / write
    FieldName: string;              // a field binding; '' = inline (Routine)
    FieldRange: TSourceRange;
    PropertyItem: TPCPropertyItem;  // non-owning: the property holding it
    ResolvedField: TPCField;        // semantics: the bound field (non-owning)
    // O10: `read abstract;` / `write abstract;` (an interface's accessors are
    // abstract by the grammar): Routine kept, Body nil; AbstractRange = the word
    IsAbstract: Boolean;
    AbstractRange: TSourceRange;
    constructor Create(); override;
    // A field binding (`read F;` / `write F;`)
    function IsBinding(): Boolean;
  end;

  { TPCOperatorItem }
  // PLAN-OBJECT O11 / D13: `operator OP(params): T; [var block] block;` in a
  // record or an object (Routine.RoutineKind = rnOperator, DeclName
  // 'operator OP', NameRange = the symbol). It has no self: a static routine
  // of the type, run by `a OP b` (or `-a`) when SEM picks it, never called by
  // name. Op is the binary operator the symbol spells; '-' with one parameter
  // is the unary minus (IsUnary)
  TPCOperatorItem = class(TPCRoutineMember)
  protected
    function DoDumpText(): string; override;
  public
    WordRange: TSourceRange;        // parser: the word operator
    Op: TPCBinaryOp;
    OpText: string;                 // the symbol as written: + div <>
    // Semantics: the declaring type's own name (its declaration's named
    // type), the emitter's qualifier T::; nil = not judged. Non-owning
    ResolvedOwner: TPCTypeExpr;
    constructor Create(); override;
    // '-' with one parameter: the unary minus
    function IsUnary(): Boolean;
  end;

  { TPCPropertyItem }
  // PLAN-OBJECT O9 / D12: `property X: T read ...; [[hidden] write ...;]` in
  // an object. Not storage: a read runs ReadItem (the emitter's pcpp_get_X(),
  // const), an assignment runs WriteItem (pcpp_set_X(v)); a write-less
  // property is read-only. NameRange = the name; Range starts at the word
  // (or at 'hidden' before it)
  TPCPropertyItem = class(TPCMemberItem)
  protected
    function DoDumpText(): string; override;
  public
    PropName: string;
    NameRange: TSourceRange;        // parser: the name token
    WordRange: TSourceRange;        // parser: the word property
    DocText: string;                // parser: its /// doc comment, raw ('' = none)
    TypeExpr: TPCTypeExpr;
    ReadItem: TPCAccessorItem;      // nil only on a recovered property
    WriteItem: TPCAccessorItem;     // nil = read-only (or, on an override, the parent's write)
    // O10 (D12): the dispatch words before 'property', as a method's (D7):
    // they apply to both accessors; an interface's property is virtual by
    // the grammar (its ranges the word property)
    IsVirtual: Boolean;
    IsOverride: Boolean;
    IsFinal: Boolean;
    VirtualRange: TSourceRange;
    OverrideRange: TSourceRange;
    FinalRange: TSourceRange;
    // O10: `property Items[const AIndex: T]: U ...` holds one index parameter
    // (owned; each inline accessor's routine has its own TPCParam of it, its
    // type borrowed); `default;` after the accessors makes LO[i] mean it
    IndexParam: TPCParam;           // nil = not indexed
    IsDefault: Boolean;
    DefaultRange: TSourceRange;
    // Semantics: the parent level's property this one overrides; the
    // interface property this one implements (non-owning; nil = none)
    ResolvedOverrides: TPCPropertyItem;
    ResolvedImplements: TPCPropertyItem;
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
    // virtual or override: its accessors are called through the vtable
    function IsDispatched(): Boolean;
    // The read gives its bound field by const reference (zero cost, D12): a
    // binding of a property that is not dispatched (a virtual read returns a
    // value, so every override can return one). SEM's copy / const rules and
    // the emitter's getter read this one rule
    function ReadsByReference(): Boolean;
  end;

  { TPCEmbedForward }
  // Semantics (PLAN-OBJECT O8, D2): an interface method of an object that an
  // embedded type's method provides: the emitter writes a forwarding override
  // `R M(params) override { return this->F.G.M(args); }`. Path = the embeds
  // walked from the object to the type that declares Method, outermost first
  TPCEmbedForward = record
    Method: TPCMethodItem;
    Path: TArray<TPCField>;
  end;

  { TPCRecordType }
  // record, or object when IsObject; an interface when IsInterface (IsObject
  // too: an interface is an abstract object of virtual abstract methods only,
  // PLAN-OBJECT D8 / O7)
  TPCRecordType = class(TPCTypeExpr)
  protected
    function DoDumpText(): string; override;
  public
    IsObject: Boolean;
    IsInterface: Boolean;
    ParentName: TPCNamedType;       // nil = no parent (an interface's: its parent interface)
    // PLAN-OBJECT O7 (parser): `object ... implements I1, I2`, in order; empty
    // = none. Owned by the arena, like ParentName
    Implements: TList<TPCNamedType>;
    // Semantics (O7): the methods of a level above that implement a method
    // of an interface this object names while their own level does not
    // derive from that interface. C++ would leave that interface method pure:
    // the emitter writes a forwarding override for each. Non-owning, in order
    ResolvedForwards: TList<TPCMethodItem>;
    // Semantics (O8): the interface methods an embed provides, in order
    ResolvedEmbedForwards: TList<TPCEmbedForward>;
    // Semantics (O10): the properties of a level above that implement an
    // interface property while their level does not derive from that
    // interface: the emitter forwards their accessors (as ResolvedForwards)
    ResolvedPropertyForwards: TList<TPCPropertyItem>;
    IsPacked: Boolean;
    AlignExpr: TPCExpr;             // nil = default alignment
    Members: TList<TPCMemberItem>;
    // Semantics (PLAN-PASKAL-ERRORS E2, r-b-align.md): the record's natural
    // alignment in bytes on the module's target, as clang lays it out
    // (packed = 1); 0 = not known (a C/C++ leaf: clang's). IsNaturalAlignComputed
    // = SEM computed it (a record asked again as a field type reads the memo)
    ResolvedNaturalAlign: UInt64;
    IsNaturalAlignComputed: Boolean;
    // PLAN-OBJECT D7 (parser): `final object(...)`: no type may name it as its
    // parent; FinalRange = the word
    IsFinal: Boolean;
    FinalRange: TSourceRange;
    // Semantics (D7): the object has a vtable (a dispatched method of its own
    // or of a level above it); ResolvedAbstract = a method of it or above it
    // that is abstract and no level down to it overrides, nil = concrete (it
    // may be created). Non-owning
    ResolvedIsPolymorphic: Boolean;
    ResolvedAbstract: TPCRoutineMember;     // an abstract method, or an abstract accessor (O10)
    // Semantics (PLAN-OBJECT O13b): an object whose parent chain reaches a
    // C/C++ class (TPCScopes.ReachesOpaque). That class's virtual methods are
    // clang's to know: the emitter makes clang report a method that overrides
    // one without `override` (D7), which the Compiler maps to SM0332
    ResolvedDerivesFromCpp: Boolean;
    // Semantics (PLAN-OBJECT D3): the object declares inits and none takes no
    // argument, so nothing builds it without arguments (C++ has no default
    // constructor): a field of it is written with no `{}` (the inits' member
    // initializers build it)
    ResolvedNeedsInitArgs: Boolean;
    // PLAN-RECORDS M10: the parent is a PaskalCPP record (not an object, not
    // C/C++, not a forward with no full): the emitter writes it as the hidden
    // first member pcpp_parent, never as a C++ base class
    function HasParentMember(): Boolean;
    // PLAN-OBJECT O13b: an object no PaskalCPP level makes polymorphic whose
    // chain reaches a C/C++ class: whether it is polymorphic is clang's
    // (the C++ class may have virtuals). The rules that depend on it are
    // judged by an emitted check (TPCExpr.ResolvedPolyCheck)
    function PolymorphismIsClangs(): Boolean;
    // The parent's record when HasParentMember (its full record), else nil
    function ParentRecord(): TPCRecordType;
    // PLAN-RECORDS M12 (4) / F-R4f: the record AHops member-parent levels up
    // may sit misaligned inside this one (a packed level on the way, and it
    // does not align to 1): its part is copied out, never referenced. The
    // emitter's conversion operators and A8's SM0270 read this one rule
    function ParentPartMayBeMisaligned(const AHops: Integer): Boolean;
    // PLAN-OBJECT O5 / D5: the done / copy this object declares itself
    // (the first one: SEM reports a second), nil = none
    function OwnDone(): TPCDoneItem;
    function OwnCopy(): TPCCopyItem;
    // D5, the one copy rule (SEM's copy check, the emitter's members): why a
    // value of this type cannot be copied, nil = it can. An object that
    // declares copy can; otherwise its own done (TPCDoneItem), a parent that
    // cannot be copied (the ParentName node) or a field whose type cannot be
    // (the TPCField), the first in that order. A record never: it holds no
    // object (H3, SEM's SM0357)
    function MoveOnlyReason(): TPCNode;
    constructor Create(); override;
    function TypeText(): string; override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCOverlayType }
  TPCOverlayType = class(TPCTypeExpr)
  public
    Members: TList<TPCMemberItem>;
    constructor Create(); override;
    function TypeText(): string; override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCChoiceValue }
  TPCChoiceValue = class(TPCNode)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    ValueName: string;
    NameRange: TSourceRange;        // parser: the name token
    DocText: string;                // parser: its /// doc comment, raw ('' = none)
    ValueExpr: TPCExpr;             // nil = previous + 1, from 0
    HasResolvedOrdinal: Boolean;    // semantics: ResolvedOrdinal is set (0 is valid)
    ResolvedOrdinal: Int64;
    ResolvedChoices: TPCTypeExpr;   // semantics: the value's type: its declaration's ResolvedNamedType, or the TPCChoicesType when anonymous; non-owning
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCChoicesType }
  TPCChoicesType = class(TPCTypeExpr)
  public
    Values: TList<TPCChoiceValue>;
    constructor Create(); override;
    function TypeText(): string; override;
    // The bits of its underlying signed integer, the one rule: 32 unless a
    // resolved ordinal needs 64 (the emitter's std::int32_t / int64_t, SEM's
    // bitfield limit)
    function UnderlyingBits(): Integer;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCSetType }
  TPCSetType = class(TPCTypeExpr)
  protected
    function DoDumpText(): string; override;
  public
    ElementType: TPCTypeExpr;       // nil = the range form (a bare set is PR0053, never built)
    IsRangeForm: Boolean;           // set of low..high
    LowExpr: TPCExpr;
    HighExpr: TPCExpr;
    // Semantics: the member range when PaskalCPP knows it (element form:
    // choices min / max ordinal, bool 0..1, char 0..255; range form: both
    // bounds folded into Int64). False = an opaque C++ bound: clang's
    // (PLAN-EMITTER A2b)
    HasResolvedBounds: Boolean;
    ResolvedLow: Int64;
    ResolvedHigh: Int64;
    constructor Create(); override;
    function TypeText(): string; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCRoutineType }
  TPCRoutineType = class(TPCTypeExpr)
  protected
    function DoDumpText(): string; override;
  public
    Linkage: TPCLinkage;
    Params: TList<TPCParam>;
    IsVariadic: Boolean;
    VariadicRange: TSourceRange;    // parser: the '...' token (IsVariadic)
    ReturnType: TPCTypeExpr;        // nil = procedure
    // The linkage the type means: lnC when written clink, else lnCpp (no word
    // = cpplink, BNF.md sec 3; F-R3b: routine() and routine cpplink() are one type)
    function MeantLinkage(): TPCLinkage;
    function Signature(): TPCSignature;
    constructor Create(); override;
    function TypeText(): string; override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCIf }
  TPCIf = class(TPCStmt)
  protected
    function DoDumpText(): string; override;
  public
    Condition: TPCExpr;
    ThenStmts: TList<TPCStmt>;
    HasElse: Boolean;
    ElseRange: TSourceRange;        // parser: the else keyword (HasElse); emitter: where `} else {` goes
    ElseStmts: TList<TPCStmt>;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCWhile }
  TPCWhile = class(TPCStmt)
  public
    Condition: TPCExpr;
    Stmts: TList<TPCStmt>;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCFor }
  TPCFor = class(TPCStmt)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    IteratorName: string;
    IteratorRange: TSourceRange;    // parser: the iterator name token (a use, not a declaration)
    ResolvedIterator: TPCNode;      // semantics: the var or param the name binds to
    // semantics: no PaskalCPP name binds it, so it is a C/C++ variable (BNF
    // sec 5: its type is clang's); ResolvedIterator stays nil
    ResolvedIteratorOpaque: Boolean;
    StartExpr: TPCExpr;
    EndExpr: TPCExpr;
    IsDownTo: Boolean;
    Stmts: TList<TPCStmt>;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCRepeat }
  TPCRepeat = class(TPCStmt)
  public
    Stmts: TList<TPCStmt>;
    UntilRange: TSourceRange;       // parser: the until keyword; emitter: where `} while` goes
    Condition: TPCExpr;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCMatchLabel }
  TPCMatchLabel = class(TPCNode)
  public
    LowExpr: TPCExpr;
    HighExpr: TPCExpr;              // nil = single value
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCMatchArm }
  TPCMatchArm = class(TPCNode)
  public
    Labels: TList<TPCMatchLabel>;
    Stmts: TList<TPCStmt>;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCMatch }
  TPCMatch = class(TPCStmt)
  protected
    function DoDumpText(): string; override;
  public
    Subject: TPCExpr;
    Arms: TList<TPCMatchArm>;
    HasElse: Boolean;
    ElseRange: TSourceRange;        // parser: the else keyword (HasElse); emitter: where `default:` goes
    ElseStmts: TList<TPCStmt>;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCGuard }
  // The parser rejects a guard with neither except nor finally (BNF.md sec 5)
  TPCGuard = class(TPCStmt)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    GuardStmts: TList<TPCStmt>;
    HasExcept: Boolean;
    ExceptRange: TSourceRange;         // parser: the except keyword (HasExcept)
    ExceptStmts: TList<TPCStmt>;
    HasFinally: Boolean;
    FinallyRange: TSourceRange;        // parser: the finally keyword (HasFinally)
    FinallyStmts: TList<TPCStmt>;
    ResolvedEscapes: TPCGuardEscapes;  // semantics: flows leaving the guard body (geReturn ...)
    // semantics: flows leaving the except list (it runs in a lambda when the
    // guard has a finally, so the emitter dispatches them like the body's)
    ResolvedExceptEscapes: TPCGuardEscapes;
    constructor Create(); override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCReturn }
  TPCReturn = class(TPCStmt)
  protected
    function DoDumpResolved(): string; override;
  public
    ValueExpr: TPCExpr;             // nil = no value
    ResolvedRoutine: TPCRoutine;    // semantics, non-owning; nil = module / test body
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCLeave }
  TPCLeave = class(TPCStmt)
  protected
    function DoDumpResolved(): string; override;
  public
    ResolvedJumpTarget: TPCStmt;    // semantics, non-owning: the loop or match it leaves
    constructor Create(); override;
  end;

  { TPCSkip }
  TPCSkip = class(TPCStmt)
  protected
    function DoDumpResolved(): string; override;
  public
    ResolvedJumpTarget: TPCStmt;    // semantics, non-owning: the loop it continues
    constructor Create(); override;
  end;

  { TPCExprStmt }
  // Assignment, call (intrinsics included) or C++ expression as a statement
  TPCExprStmt = class(TPCStmt)
  public
    Expr: TPCExpr;
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCAssign }
  // Assignment is an expression (BNF.md sec 6)
  TPCAssign = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
  public
    Target: TPCExpr;
    Op: TPCAssignOp;
    ValueExpr: TPCExpr;
    constructor Create(); override;
    function ExprText(): string; override;
    function ExprPower(): Integer; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
    // The operator as written (':=', '+=' ...; BNF.md sec 6): ExprText and
    // SEM's messages print the same spelling
    function OpText(): string;
  end;

  { TPCTernary }
  TPCTernary = class(TPCExpr)
  public
    Condition: TPCExpr;
    ThenExpr: TPCExpr;
    ElseExpr: TPCExpr;
    constructor Create(); override;
    function ExprText(): string; override;
    function ExprPower(): Integer; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCBinary }
  TPCBinary = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
  public
    Left: TPCExpr;
    Op: TPCBinaryOp;
    Right: TPCExpr;
    // Parser (PLAN-OBJECT O14): the operator token (`div` / `<>`: its word or
    // symbol), where the editor finds a declared operator's use
    OpRange: TSourceRange;
    // Semantics (PLAN-OBJECT O11): the declared operator this node runs (an
    // operand's record / object declares it); nil = the built-in operator.
    // Non-owning
    ResolvedOperator: TPCOperatorItem;
    constructor Create(); override;
    function ExprText(): string; override;
    function ExprPower(): Integer; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCUnary }
  TPCUnary = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
  public
    Op: TPCUnaryOp;
    Operand: TPCExpr;
    // Parser (PLAN-OBJECT O14): the operator token (`address of`: the word
    // address; a postfix one: its token), where the editor finds a declared
    // operator's use
    OpRange: TSourceRange;
    // Semantics (PLAN-OBJECT O11): the declared unary minus this node runs;
    // nil = the built-in operator. Non-owning
    ResolvedOperator: TPCOperatorItem;
    constructor Create(); override;
    function ExprText(): string; override;
    function ExprPower(): Integer; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCCall }
  // Every call, intrinsics included (IntrinsicKind <> ikNone only when
  // ResolvedKind = rkIntrinsic). TypeArg holds a type argument (size(T),
  // next(T) / get(I, T) on a varargs local); TypeArgIndex is its written
  // position among the arguments, Args holds the others in order (F-R3)
  TPCCall = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    Callee: TPCExpr;
    TypeArg: TPCTypeExpr;           // nil unless the argument is unmistakably a type (parser.md)
    TypeArgIndex: Integer;          // TypeArg's written position (size(T): 0); meaningless without TypeArg
    Args: TList<TPCExpr>;
    ResolvedDecl: TPCNode;          // semantics; nil for an opaque C/C++ callee
    ResolvedKind: TPCResolvedKind;
    IntrinsicKind: TPCIntrinsicKind;
    ResolvedInTest: Boolean;        // semantics: the call lies inside a TPCTest body
    // semantics (F18, user 2026-10-12): a call to an overload set whose
    // arguments only SOME members take by PaskalCPP's conversions holds those
    // members, in declaration order; the emitter calls through exactly them
    // (::pcpp::overloads), so clang ranks them and never the others. Empty =
    // no limit: every member takes the arguments (or the call was not judged)
    ResolvedCandidates: TList<TPCRoutine>;
    // semantics (PLAN-RECORDS M12 (2) / M13): an accepted member takes an
    // argument at a level above its record (a record of any mode, or a
    // pointer to a record): C++ ranks that only through the overloads form's
    // ranking tags (M10: no C++ inheritance), so ResolvedCandidates then holds
    // EVERY accepted member and no upcast is written on the arguments
    ResolvedRanksExtensions: Boolean;
    // semantics (PLAN-OBJECT D3): a leading statement of an init,
    // `parent.init(...)` or `self.F.init(...)`: the init it runs
    // (non-owning; nil = the part has no init of its own: C++'s implicit
    // default) and the field F it builds (nil = the parent part). IsLeadInit
    // = SEM took the call as one (the emitter writes it into the C++
    // member-init list)
    IsLeadInit: Boolean;
    ResolvedInit: TPCInitItem;
    ResolvedInitField: TPCField;
    constructor Create(); override;
    // The PaskalCPP routine the call names: its declaration, else the member
    // of the overload set SEM recorded (TPCName.ResolvedSetMember); nil = a
    // C/C++ callee. The one rule of the emitter and TPCAst.ModuleNamesRuntime
    function TargetRoutine(): TPCRoutine;
    function ExprText(): string; override;
    function ExprPower(): Integer; override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCIndex }
  TPCIndex = class(TPCExpr)
  public
    Base: TPCExpr;
    IndexExpr: TPCExpr;
    // Parser (PLAN-OBJECT O14): the '[' token, where the editor finds a
    // default property's use (`LO[i]` names no member)
    OpenRange: TSourceRange;
    // Semantics (PLAN-OBJECT O10): the indexed property this index reads or
    // writes: `LO.Items[i]` (Base = the property member) or, through a
    // default property, `LO[i]` (Base = the object). nil = a plain index.
    // Non-owning
    ResolvedProperty: TPCPropertyItem;
    constructor Create(); override;
    function ExprText(): string; override;
    function ExprPower(): Integer; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCMember }
  // Base.Member / Base->Member; any keyword is a member name (BNF.md sec 6)
  TPCMember = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    Base: TPCExpr;
    Access: TPCMemberAccess;
    Member: TPCNamePart;
    ResolvedDecl: TPCNode;          // semantics
    ResolvedKind: TPCResolvedKind;
    // semantics: the varargs member a varargs local's '.' names (BNF.md sec
    // 6: count, next, get, reset, copy), lowered by the emitter as the same
    // member of varargs; vaPlain = not a varargs local's member
    ResolvedVarargs: TPCVarargsKind;
    // semantics (PLAN-RECORDS M10): the parent levels between Base's record
    // and the level that declares Member (TPCScopes.FindMember's AHops); the
    // emitter writes pcpp_parent. that many times. 0 = Base's own level, an
    // object's member (C++ base lookup), or no record
    ResolvedParentHops: Integer;
    // semantics (PLAN-OBJECT O8, D2): Member is an embedded type's member,
    // reached through these embeds of Base's object, outermost first
    // (TPCScopes.FindPromoted); the emitter writes F.G. before it, then the
    // ResolvedParentHops of the last embedded type. Empty = Base's own chain
    ResolvedEmbedPath: TArray<TPCField>;
    constructor Create(); override;
    function ExprText(): string; override;
    function ExprPower(): Integer; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
    // PLAN-OBJECT O6 (Q2): `LO.X` whose base is an own / ref (SEM's types):
    // the member of the object it holds. The one rule of the emitter's
    // ::pcpp::deref and TPCAst.ModuleNamesRuntime
    class function ReadsOwner(const AMember: TPCMember): Boolean; static;
  end;

  { TPCName }
  // An identifier or a C++ :: name; rkOpaque for C/C++ names (BNF.md sec 10)
  TPCName = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    HasLeadingScope: Boolean;       // leading ::
    Parts: TList<TPCNamePart>;
    ResolvedDecl: TPCNode;          // semantics
    ResolvedKind: TPCResolvedKind;
    // Semantics: one routine of the overload set the name denotes (ResolvedKind
    // rkRoutine, ResolvedDecl nil: clang picks). Every member is in one frame,
    // so its DeclModule / RoutineKind spell the set (PLAN-EMITTER H2); nil
    // otherwise. Non-owning
    ResolvedSetMember: TPCRoutine;
    constructor Create(); override;
    function ExprText(): string; override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCSpecial }
  // self, parent, this, nullptr; true / false / nil are TPCLiteral
  TPCSpecial = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
  public
    SpecialKind: TPCSpecialKind;
    constructor Create(); override;
    function ExprText(): string; override;
  end;

  { TPCCast }
  // Every cast form; a named cast's single <T> is TargetType (stored once)
  TPCCast = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
  public
    CastKind: TPCCastKind;
    TargetType: TPCTypeExpr;
    Operand: TPCExpr;
    // semantics (PLAN-RECORDS F-A6a): a ptr to T / C-style / static cast from
    // a pointer to a record (or to its C/C++ base) down to a pointer to an
    // extension this many member parents below it (the upcast's hops in
    // reverse); the emitter writes the runtime downcast. 0 = none (C++
    // inheritance or no record chain: written as before)
    ResolvedDowncastHops: Integer;
    constructor Create(); override;
    function ExprText(): string; override;
    function ExprPower(): Integer; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCNew }
  TPCNew = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
  public
    TargetType: TPCCppType;         // a cpp type name: no cv, pointers or reference
    InitKind: TPCNewInit;
    Args: TList<TPCExpr>;           // niArgs and niBraced
    SizeExpr: TPCExpr;              // niArraySize
    constructor Create(); override;
    function ExprText(): string; override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCDelete }
  TPCDelete = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
  public
    IsArray: Boolean;               // delete []
    Operand: TPCExpr;
    constructor Create(); override;
    function ExprText(): string; override;
    function ExprPower(): Integer; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCOwnerNew }
  // PLAN-OBJECT O6 (D4, Q1): `own TFoo(1, 2)` / `ref TFoo` builds an object
  // on the heap. OwnerType is the type as written (own / ref + the object
  // type: the expression's type, SEM's ResolvedType); InitCall the argument
  // list, a TPCCall with no callee (empty when no parentheses were written),
  // so every argument rule runs on it as on TPCVarDecl.InitCall
  TPCOwnerNew = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
  public
    OwnerType: TPCOwnerType;
    InitCall: TPCCall;
    HasArgList: Boolean;            // '(' ... ')' written
    // semantics: the init that builds the object (InitCall.ResolvedInit with
    // arguments; else the init taking none, nil = C++'s default). Non-owning
    ResolvedInit: TPCInitItem;
    constructor Create(); override;
    function ExprText(): string; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCTypeTest }
  // PLAN-OBJECT O12 (D15): `X is T` (IsCast False: the object X denotes is
  // a T or a descendant of one; nil is never one) and `X as T` (IsCast True:
  // the checked cast, raising when the object is not a T). X is a
  // polymorphic object, or a ptr to / own / ref of one; T is an object or an
  // interface type. The result of `as` keeps the operand's kind (SEM's
  // ResolvedType): an object -> the object as T (an lvalue, const when X is),
  // a ptr to S -> a ptr to T, a ref S -> a ref T (nil stays nil), an own S
  // -> the object it holds as T (an own has one owner). WordRange = the
  // `is` / `as` word
  TPCTypeTest = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
  public
    Operand: TPCExpr;
    TargetType: TPCTypeExpr;
    IsCast: Boolean;
    WordRange: TSourceRange;
    constructor Create(); override;
    function ExprText(): string; override;
    function ExprPower(): Integer; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
    // The operator's word as written: 'is' / 'as'
    function WordText(): string;
  end;

  { TPCBracedInit }
  // T{...} or a bare {...} (parser.md:154); contents are PaskalCPP expressions
  TPCBracedInit = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
  public
    Base: TPCExpr;                  // nil = bare {...}
    Args: TList<TPCExpr>;
    constructor Create(); override;
    function ExprText(): string; override;
    function ExprPower(): Integer; override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCSetElement }
  TPCSetElement = class(TPCNode)
  public
    LowExpr: TPCExpr;
    HighExpr: TPCExpr;              // nil = single value
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCSetLiteral }
  TPCSetLiteral = class(TPCExpr)
  public
    Elements: TList<TPCSetElement>;
    constructor Create(); override;
    function ExprText(): string; override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCFieldInit }
  TPCFieldInit = class(TPCNode)
  protected
    function DoDumpText(): string; override;
    function DoDumpResolved(): string; override;
  public
    FieldName: string;
    ValueExpr: TPCExpr;
    ResolvedField: TPCField;        // semantics: checks declaration order
    // semantics (PLAN-RECORDS M14): the member-parent levels between the
    // literal's record and the level that declares ResolvedField (an
    // extension's literal names inherited fields); the emitter nests the
    // init in that many pcpp_parent braces. 0 = the literal's own record
    ResolvedParentHops: Integer;
    constructor Create(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCRecordLiteral }
  // TPoint(x: 10, y: 20)
  TPCRecordLiteral = class(TPCExpr)
  public
    RecordType: TPCNamedType;
    Inits: TList<TPCFieldInit>;
    constructor Create(); override;
    function ExprText(): string; override;
    destructor Destroy(); override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCVarargs }
  TPCVarargs = class(TPCExpr)
  protected
    function DoDumpText(): string; override;
  public
    VarargsKind: TPCVarargsKind;
    IndexExpr: TPCExpr;             // vaGet only: the argument index
    ReadType: TPCTypeExpr;          // vaNext / vaGet only: the type read
    constructor Create(); override;
    function ExprText(): string; override;
    procedure EnumChildren(const AVisit: TPCNodeVisitor); override;
  end;

  { TPCAst }
  // The arena: owns every node (including orphans from abandoned parses),
  // the module list (completed modules, dependency order) and one instance
  // of each synthesized type
  TPCAst = class(TBaseObject)
  private
    FNodes: TObjectList<TPCNode>;
    FModules: TList<TPCModule>;
    FRejectedModules: TList<TPCModule>;  // AddModule's rejected duplicates: found by file only
    FLookupPaths: TArray<string>;        // every unit file an import lookup tried, once (AddLookupPath)
    FOpaqueType: TPCOpaqueType;
    FErrorType: TPCErrorType;
    FNilType: TPCNilType;
    FVoidType: TPCVoidType;
    FUntypedPointerType: TPCPointerType;
    FStringLiteralType: TPCStringLiteralType;
    FWideStringLiteralType: TPCStringLiteralType;
    FBuiltinTypes: array[TPCTokenKind] of TPCBuiltinType;  // BuiltinType's cache, nil until first use
    class function DoIsByteCopy(const ANode: TPCNode): Boolean; static;
    class function DoCppExprOf(const ANode: TPCNode; out AVerbatim: TPCVerbatim): Boolean; static;
    class function DoMapValueColumn(const AVerbatim: TPCVerbatim; const ALine: UInt64;
      const AColumn: UInt64; const ASpan: TPCEmitSpan; const AStartColumn: UInt64): UInt64; static;
    class function DoMapColumn(const ANode: TPCNode; const ALine: UInt64;
      const AColumn: UInt64; const ASpan: TPCEmitSpan): UInt64; static;
    class function DoNodeNamesRuntime(const ANode: TPCNode): Boolean; static;
    class function DoMembersNeedPackedCheck(const AMembers: TList<TPCMemberItem>;
      const AInPacked: Boolean): Boolean; static;
    class function DoMembersNeedOverlayCheck(const AMembers: TList<TPCMemberItem>;
      const AInUnion: Boolean): Boolean; static;
    class function DoCallNamesRuntime(const ACall: TPCCall): Boolean; static;
    class function DoExternalLibRange(const ANode: TPCNode;
      const ALibrary: string): TSourceRange; static;
    class function DoNarrowestAt(const AModule: TPCModule; const ALine: UInt64;
      const AColumn: UInt64; out ANode: TPCNode; out ASpan: TPCEmitSpan): Boolean; static;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    // The only ways to create a node; the arena owns the result
    function NewNodeOf(const AClass: TPCNodeClass): TPCNode;
    function NewNode<T: TPCNode>(): T;
    function NodeCount(): Integer;
    // A second module with the same name -> PC_ERR_AST_001, first kept (the rejected one is
    // still found by FindModuleByFile, never re-parsed); a nameless module (broken header,
    // already reported) is added without the check
    procedure AddModule(const AModule: TPCModule);
    function FindModule(const AModuleName: string): TPCModule;
    // The module (registered or rejected) whose SourceFile is AFilename, compared with
    // TUtils.SamePath; nil = none. Import identity (research\cppmix\parser-core.md)
    function FindModuleByFile(const AFilename: string): TPCModule;
    function ModuleCount(): Integer;
    function ModuleAt(const AIndex: Integer): TPCModule;
    // The unit files the parse's import lookups tried, found or not (the
    // parser adds each candidate; a file appearing at one changes what an
    // import resolves to: the LSP server watches them)
    procedure AddLookupPath(const APath: string);
    function LookupPaths(): TArray<string>;
    // C++ text spells the runtime's scope (PC_RUNTIME_SPELLING not after an
    // identifier character): verbatim C++ that names the runtime, and the
    // emitter witness's text
    class function TextNamesRuntime(const AText: string): Boolean; static;
    // Some construct of the module's own (its test blocks skipped: test mode
    // is the exe's, BNF sec 8) is one the emitter writes as runtime C++
    // (research\compiler\r10-runtime-use.md); SEM stores it in
    // TPCModule.ResolvedUsesRuntime
    class function ModuleNamesRuntime(const AModule: TPCModule): Boolean; static;
    // The name a declaring node declares and the parser's name token: a
    // declaration (DeclName), param, field, choice value or module header;
    // False for any other node (PLAN-RECORDS A9: SEM's reserved-name rule and
    // the LSP's NameRangeOf read this one rule)
    class function DeclaredName(const ANode: TPCNode; out AName: string; out ARange: TSourceRange): Boolean; static;
    // An integer SEM folded, as a decimal; False when it did not fold (the
    // emitter's spelling of a folded value)
    class function FoldedText(const AExpr: TPCExpr; out AText: string): Boolean; static;
    // A static array's element count from its folded bounds; False = a bound
    // PaskalCPP did not fold, or a width past Int64 (clang computes it)
    class function FoldedCount(const ALow: TPCExpr; const AHigh: TPCExpr; out ACount: string): Boolean; static;
    // A type another node's spelling may borrow by name: a builtin or a
    // declared PaskalCPP type
    class function IsNamedPaskalType(const AType: TPCTypeExpr): Boolean; static;
    // ANode's children whose text the emitter writes: a type's constant slot
    // written as its folded value names nothing (an array's bounds when
    // FoldedCount holds, a set's bounds when SEM resolved them, the range
    // form's low bound kept when it is spelled in decltype, align(n) and a
    // bitfield width when folded); every other node: EnumChildren. The one
    // rule of ModuleNamesRuntime and the emitter's header walk (F22)
    class procedure EnumWrittenChildren(const ANode: TPCNode; const AVisit: TPCNodeVisitor); static;
    // The program needs the runtime library: a module's ResolvedUsesRuntime,
    // or an initialize / finalize section (a lib's hook runs them inside the
    // out-of-line ::pcpp::enter). The one aggregate of the emitter's lib hook
    // and the Compiler's runtime publish (r10 D-R10-2 / D-R10-3)
    function UsesRuntime(): Boolean;
    function OpaqueType(): TPCOpaqueType;
    function ErrorType(): TPCErrorType;
    function NilType(): TPCNilType;
    function VoidType(): TPCVoidType;
    // The one untyped `ptr` the pass types a value with (getmem, resizemem);
    // a written `ptr` is its own TPCPointerType node
    function UntypedPointerType(): TPCPointerType;
    function StringLiteralType(const AIsWide: Boolean): TPCStringLiteralType;
    // One shared TPCBuiltinType per builtin token (types.md :21-24), made on
    // first use; a token that is not a builtin type word (a primitive or
    // `varargs`: TPCVocabulary.IsBuiltinTypeWord) raises (caller defect)
    function BuiltinType(const AToken: TPCTokenKind): TPCBuiltinType;
    // TPCLocationTranslator's signature (PaskalCPP.ZigBuild): True = the
    // location is this AST's and AOut* hold the mapped .pcpp location;
    // False = not mine, AOut* mirror the inputs
    function TranslateLocation(const AFilename: string; const ALine: UInt64;
      const AColumn: UInt64; out AOutFilename: string; out AOutLine: UInt64;
      out AOutColumn: UInt64): Boolean;
    // TPCLibraryLocator's signature (PaskalCPP.BuildOutput): True = a module
    // names ALibrary (a @linklibrary value SEM did not set aside, an external
    // clause's ResolvedLib) and AOut* hold its first naming, in the order the
    // Compiler hands libraries to the build (TPCCompiler.DoConfigureBuild:
    // module order; per module its @linklibrary directives, then its external
    // clauses in tree order); False = no module names it
    function LocateLibrary(const ALibrary: string; out AOutFilename: string;
      out AOutLine: UInt64; out AOutColumn: UInt64): Boolean;
    // The record whose align value holds the narrowest emitted span at a
    // location clang reported (the search TranslateLocation makes): the
    // frontend check the emitter writes is a span of the value
    // (PLAN-PASKAL-ERRORS E3). ATypeName = the type declaration's name, else
    // the record's PaskalCPP spelling. False = no record's align value there
    function AlignRecordAt(const AFilename: string; const ALine: UInt64;
      const AColumn: UInt64; out ARecord: TPCRecordType; out ATypeName: string): Boolean;
    // The print / println argument (after the format) whose emitted span is
    // the narrowest at a location clang reported: the emitter's formatter
    // check is a span of the argument (PLAN-PASKAL-ERRORS E7). False = no
    // print argument there
    function PrintArgAt(const AFilename: string; const ALine: UInt64;
      const AColumn: UInt64; out AArg: TPCExpr): Boolean;
    // PLAN-VENDOR 1e: the innermost call (a routine's, an intrinsic's, a
    // C/C++ one's) holding the node whose emitted span is the narrowest at a
    // location clang reported: AArgIndex = the argument that node lies in,
    // -1 = the callee or the call itself (a template's substitution note is
    // at the callee). False = no call there
    function CallAt(const AFilename: string; const ALine: UInt64;
      const AColumn: UInt64; out ACall: TPCCall; out AArgIndex: Integer): Boolean;
    // The field, or a packed record's parent type, whose emitted span is the
    // narrowest at a location clang reported: the emitter's packed-field check
    // (PLAN-RECORDS M9) and overlay-field check (F34) are spans of it. AOwner = the
    // TPCField or the parent's type expr, ARecordName the record or overlay
    // declaring it, AFieldName '' for the parent, ATypeText the type's
    // PaskalCPP spelling. False = none there
    function FieldCheckAt(const AFilename: string; const ALine: UInt64; const AColumn: UInt64;
      out AOwner: TPCNode; out ARecordName: string; out AFieldName: string;
      out ATypeText: string): Boolean;
    // F47: where a type too large to exist was written, at a location clang
    // reported (the search TranslateLocation makes). ARecordText = clang's own
    // record text (at a struct's name): a record, overlay or object type
    // declaration's name, or an anonymous aggregate (named by the type
    // holding it). Else the runtime's Array check at the use clang's
    // instantiation note names: a variable, constant, field, parameter or
    // routine holding the array by value (its type as written), or an
    // expression (its resolved type). ARange / ATypeText = where SM0277 is
    // reported and the type's PaskalCPP spelling. False = none there
    function SizeCheckAt(const AFilename: string; const ALine: UInt64; const AColumn: UInt64;
      const ARecordText: Boolean; out ARange: TSourceRange; out ATypeText: string): Boolean;
    // PLAN-OBJECT O13b: the method whose emitted declaration is the narrowest
    // span at a location clang reported (clang's -Wsuggest-override is at the
    // method's name), with the object declaring it and the C/C++ class its
    // chain reaches (ACppParent, its PaskalCPP spelling). False = none there
    // ARecordName = the type declaration naming the object (O13b (4))
    function CppOverrideAt(const AFilename: string; const ALine: UInt64; const AColumn: UInt64;
      out AItem: TPCMethodItem; out ACppParent: string; out ARecordName: string): Boolean;
    // PLAN-OBJECT O13b: the expression carrying a polymorphism check
    // (ResolvedPolyCheck) whose emitted span is the narrowest at a location
    // clang reported (the check is written inside the expression's span).
    // False = none there
    function PolyCheckAt(const AFilename: string; const ALine: UInt64; const AColumn: UInt64;
      out AExpr: TPCExpr): Boolean;
  end;

implementation

uses
  System.TypInfo,
  System.Math,
  StdApp.Utils,
  StdApp.Resources;

{ TPCIntrinsicSigs }

class function TPCIntrinsicSigs.SigText(const AKind: TPCIntrinsicKind): string;
begin
  // The argument list SM0409 prints, one resource string per list
  case AKind of
    ikLen:
      Result := RSAstSigLength;
    ikSize:
      Result := RSAstSigType;
    ikUtf8:
      Result := RSAstSigWString;
    ikParamCount, ikExcCode, ikExcMsg:
      Result := RSAstSigNone;
    ikParamStr:
      Result := RSAstSigInt32;
    ikGetMem:
      Result := RSAstSigInt64;
    ikFreeMem, ikTestAssertNil, ikTestAssertNotNil:
      Result := RSAstSigPointer;
    ikResizeMem:
      Result := RSAstSigPointerInt64;
    ikSetLength:
      Result := RSAstSigResize;
    ikCreate:
      Result := RSAstSigHeapPtrVar;
    ikDestroy:
      Result := RSAstSigHeapPtr;
    ikRaise, ikTestFail:
      Result := RSAstSigString;
    ikRaiseCode:
      Result := RSAstSigInt32String;
    ikTestAssert, ikTestAssertTrue, ikTestAssertFalse:
      Result := RSAstSigBool;
    ikTestAssertEqualInt:
      Result := RSAstSigInt64Pair;
    ikTestAssertEqualUInt:
      Result := RSAstSigUInt64Pair;
    ikTestAssertEqualFloat:
      Result := RSAstSigFloat64Pair;
    ikTestAssertEqualStr:
      Result := RSAstSigStringPair;
    ikTestAssertEqualBool:
      Result := RSAstSigBoolPair;
    ikTestAssertEqualPtr:
      Result := RSAstSigPointerPair;
    ikAlive, ikLock:
      Result := RSAstSigWeak;
  else
    Result := '';
  end;
end;

{ TPCNode }

constructor TPCNode.Create();
begin
  inherited;

  FNodeKind := nkNone;
  Range.Clear();
  IsRecovered := False;
  FEmitSpans := nil;
end;

function TPCNode.Dump(const AId: Integer): string;
var
  LBuilder: TStringBuilder;
begin
  // AId is an identifier, not a depth (StdApp.Base): DoDumpTree carries depth
  LBuilder := TStringBuilder.Create();
  try
    DoDumpTree(LBuilder, 0);
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

procedure TPCNode.DoDumpTree(const ABuilder: TStringBuilder; const ADepth: Integer);
var
  LText: string;
begin
  ABuilder.Append(StringOfChar(' ', ADepth * 2));
  ABuilder.Append(KindName());
  LText := DoDumpText();
  if LText <> '' then
  begin
    ABuilder.Append(' ');
    ABuilder.Append(LText);
  end;
  ABuilder.Append(DoDumpResolved());
  if IsRecovered then
    ABuilder.Append(' recovered');
  ABuilder.Append(sLineBreak);

  // Children one level deeper, through the one tree walk
  EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      AChild.DoDumpTree(ABuilder, ADepth + 1);
    end);
end;

function TPCNode.DoDumpText(): string;
begin
  Result := '';
end;

function TPCNode.DoDumpResolved(): string;
begin
  Result := '';
end;

class procedure TPCNode.VisitNode(const ANode: TPCNode; const AVisit: TPCNodeVisitor);
begin
  if ANode <> nil then
    AVisit(ANode);
end;

class procedure TPCNode.VisitList<T>(const AList: TList<T>; const AVisit: TPCNodeVisitor);
var
  LItem: T;
begin
  if AList = nil then
    Exit;
  for LItem in AList do
    VisitNode(LItem, AVisit);
end;

class function TPCNode.QuoteText(const AText: string): string;
var
  LBuilder: TStringBuilder;
  LChar: Char;
begin
  // One node is always one dump line: escape what would break or blur it
  LBuilder := TStringBuilder.Create();
  try
    LBuilder.Append('"');
    for LChar in AText do
    begin
      case LChar of
        '\': LBuilder.Append('\\');
        '"': LBuilder.Append('\"');
        #13: LBuilder.Append('\r');
        #10: LBuilder.Append('\n');
        #9:  LBuilder.Append('\t');
      else
        LBuilder.Append(LChar);
      end;
    end;
    LBuilder.Append('"');
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

procedure TPCNode.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  // Leaf by default
end;

procedure TPCNode.AddEmitSpan(const ASpan: TPCEmitSpan);
begin
  FEmitSpans := FEmitSpans + [ASpan];
end;

function TPCNode.KindName(): string;
begin
  // 'nkModule' -> 'Module'
  Result := GetEnumName(TypeInfo(TPCNodeKind), Ord(FNodeKind)).Substring(2);
end;

class function TPCNode.NodeClass(): TPCNodeClass;
begin
  // Self in a class method is the class the call was made on
  Result := Self;
end;

class function TPCNode.FloatText(const AValue: Double): string;
var
  LBits: UInt64;
  LPrecision: Integer;
  LText: string;
  LNumeric: string;
  LNegative: Boolean;
  LDecoded: Double;
  LDecodedBits: UInt64;
begin
  Move(AValue, LBits, SizeOf(LBits));
  if IsNan(AValue) then
    Exit('nan');
  if IsInfinite(AValue) then
  begin
    if AValue > 0 then
      Exit('inf');
    Exit('-inf');
  end;
  if AValue = 0 then
  begin
    // -0 and +0 compare equal: the sign bit tells them apart
    if (LBits shr 63) = 1 then
      Exit('-0');
    Exit('0');
  end;
  // The shortest RTL text that reads back to the same bits, judged by the
  // exact decoder (D-PA14): two values can never print one text
  for LPrecision := 15 to 17 do
  begin
    LText := FloatToStrF(AValue, ffGeneral, LPrecision, 0, TFormatSettings.Invariant);
    LNegative := LText.StartsWith('-');
    if LNegative then
      LNumeric := LText.Substring(1)
    else
      LNumeric := LText;
    // '2' is not a floating literal's numeric part; '2.' is (same value)
    if (LNumeric.IndexOf('.') < 0) and (LNumeric.IndexOf('E') < 0) then
      LNumeric := LNumeric + '.';
    if TPCFloatDecoder.Decode(LNumeric, ffBinary64, LDecoded) = fsOk then
    begin
      if LNegative then
        LDecoded := -LDecoded;
      Move(LDecoded, LDecodedBits, SizeOf(LDecodedBits));
      if LDecodedBits = LBits then
        Exit(LText);
    end;
  end;
  Result := FloatToStrF(AValue, ffGeneral, 17, 0, TFormatSettings.Invariant) + '#' +
    IntToHex(LBits, 16);
end;

{ Holds walk }
// HoldsStringOrDynamicArray's walk: AVisited holds the records / overlays on
// the current path; a by-value cycle (a forward + SM0300, already reported)
// adds no member, so a revisit is False

function DoMembersHold(const AMembers: TList<TPCMemberItem>;
  const AVisited: TList<TPCTypeExpr>): Boolean; forward;

function DoHoldsIn(const AType: TPCTypeExpr; const AVisited: TList<TPCTypeExpr>): Boolean;
var
  LCanon: TPCTypeExpr;
  LArray: TPCArrayType;
  LRecord: TPCRecordType;
begin
  Result := False;
  if AType = nil then
    Exit;
  LCanon := AType.Canon();
  if LCanon is TPCBuiltinType then
    Exit((TPCBuiltinType(LCanon).BuiltinToken = tkKwString) or
      (TPCBuiltinType(LCanon).BuiltinToken = tkKwWstring));
  if LCanon is TPCArrayType then
  begin
    LArray := TPCArrayType(LCanon);
    if LArray.IsDynamic then
      Exit(True);
    Exit(DoHoldsIn(LArray.ElementType, AVisited));
  end;
  if not ((LCanon is TPCRecordType) or (LCanon is TPCOverlayType)) then
    Exit;
  if AVisited.Contains(LCanon) then
    Exit;
  AVisited.Add(LCanon);
  try
    if LCanon is TPCRecordType then
    begin
      LRecord := TPCRecordType(LCanon);
      // A C++ base holding a std::string is not a literal type either
      if DoHoldsIn(LRecord.ParentName, AVisited) then
        Exit(True);
      Exit(DoMembersHold(LRecord.Members, AVisited));
    end;
    Result := DoMembersHold(TPCOverlayType(LCanon).Members, AVisited);
  finally
    AVisited.Remove(LCanon);
  end;
end;

function DoMembersHold(const AMembers: TList<TPCMemberItem>;
  const AVisited: TList<TPCTypeExpr>): Boolean;
var
  LMember: TPCMemberItem;
begin
  // Fields and anonymous aggregates hold data; methods do not
  Result := False;
  if AMembers = nil then
    Exit;
  for LMember in AMembers do
  begin
    if (LMember is TPCField) and DoHoldsIn(TPCField(LMember).TypeExpr, AVisited) then
      Exit(True);
    if (LMember is TPCAnonAggregate) and
      DoMembersHold(TPCAnonAggregate(LMember).Members, AVisited) then
      Exit(True);
  end;
end;

{ Packing walk }
// FieldPacking's walk (PLAN-RECORDS M9), shaped as the Holds walk: AVisited
// holds the records / overlays on the current path (a by-value cycle is
// SM0300, already reported: a revisit adds nothing). The answer is the worst
// leaf (TPCFieldPacking is ordered: fpPacks < fpClangDecides < fpNeverPacks)

function DoMembersPacking(const AMembers: TList<TPCMemberItem>;
  const AVisited: TList<TPCTypeExpr>): TPCFieldPacking; forward;

function DoWorsePacking(const AFirst: TPCFieldPacking; const ASecond: TPCFieldPacking): TPCFieldPacking;
begin
  if Ord(ASecond) > Ord(AFirst) then
    Result := ASecond
  else
    Result := AFirst;
end;

function DoPackingIn(const AType: TPCTypeExpr; const AVisited: TList<TPCTypeExpr>): TPCFieldPacking;
var
  LCanon: TPCTypeExpr;
  LArray: TPCArrayType;
  LRecord: TPCRecordType;
begin
  Result := fpPacks;
  if AType = nil then
    Exit;
  // A C/C++ type: only clang knows its layout (a C struct packs, a C++ class
  // with a constructor does not, r4b pk_layout)
  if TPCTypeExpr.IsOpaqueTier(AType) then
    Exit(fpClangDecides);
  LCanon := AType.Canon();
  if LCanon is TPCBuiltinType then
  begin
    if (TPCBuiltinType(LCanon).BuiltinToken = tkKwString) or
      (TPCBuiltinType(LCanon).BuiltinToken = tkKwWstring) then
      Exit(fpNeverPacks);
    Exit(fpPacks);
  end;
  if LCanon is TPCArrayType then
  begin
    // std::vector is a class; ::pcpp::Array of plain data packs (pk_layout;
    // A8b: plain data itself, a C array member)
    LArray := TPCArrayType(LCanon);
    if LArray.IsDynamic then
      Exit(fpNeverPacks);
    Exit(DoPackingIn(LArray.ElementType, AVisited));
  end;
  // Scalars, pointers, routine types, choices, sets (an aggregate since M9)
  // and anything SEM reported (an unresolved name) are plain data
  if not ((LCanon is TPCRecordType) or (LCanon is TPCOverlayType)) then
    Exit;
  if AVisited.Contains(LCanon) then
    Exit;
  AVisited.Add(LCanon);
  try
    if LCanon is TPCOverlayType then
      Exit(DoMembersPacking(TPCOverlayType(LCanon).Members, AVisited));
    LRecord := TPCRecordType(LCanon);
    Result := DoMembersPacking(LRecord.Members, AVisited);
    if LRecord.ParentName <> nil then
    begin
      Result := DoWorsePacking(Result, DoPackingIn(LRecord.ParentName, AVisited));
      // A parent that is no member (M10) is a C++ base class: a struct with a
      // base never packs, clang judges it
      if not LRecord.HasParentMember() then
        Result := DoWorsePacking(Result, fpClangDecides);
    end;
    // An object keeps its C++ form (member initializers, PLAN-OBJECT)
    if LRecord.IsObject then
      Result := DoWorsePacking(Result, fpClangDecides);
  finally
    AVisited.Remove(LCanon);
  end;
end;

function DoMembersPacking(const AMembers: TList<TPCMemberItem>;
  const AVisited: TList<TPCTypeExpr>): TPCFieldPacking;
var
  LMember: TPCMemberItem;
begin
  // Fields and anonymous aggregates hold data; methods do not
  Result := fpPacks;
  if AMembers = nil then
    Exit;
  for LMember in AMembers do
  begin
    if LMember is TPCField then
      Result := DoWorsePacking(Result, DoPackingIn(TPCField(LMember).TypeExpr, AVisited))
    else if LMember is TPCAnonAggregate then
      Result := DoWorsePacking(Result, DoMembersPacking(TPCAnonAggregate(LMember).Members, AVisited));
    if Result = fpNeverPacks then
      Exit;
  end;
end;

{ Overlay fit walk }
// OverlayFit's walk (PLAN-COMPLIANCE F34), shaped as the packing walk:
// AVisited holds the records on the current path (a by-value cycle is
// SM0300, already reported: a revisit adds nothing). The answer is the worst
// leaf (TPCOverlayFit is ordered: ofFits < ofClangDecides < ofNeverFits). An
// overlay, named or anonymous, is not entered: SEM judges its fields at its
// own declaration, so a mistake inside one is reported once, there

function DoMembersFit(const AMembers: TList<TPCMemberItem>;
  const AVisited: TList<TPCTypeExpr>): TPCOverlayFit; forward;

function DoWorseFit(const AFirst: TPCOverlayFit; const ASecond: TPCOverlayFit): TPCOverlayFit;
begin
  if Ord(ASecond) > Ord(AFirst) then
    Result := ASecond
  else
    Result := AFirst;
end;

function DoFitIn(const AType: TPCTypeExpr; const AVisited: TList<TPCTypeExpr>): TPCOverlayFit;
var
  LCanon: TPCTypeExpr;
  LArray: TPCArrayType;
  LRecord: TPCRecordType;
begin
  Result := ofFits;
  if AType = nil then
    Exit;
  // A C/C++ type: only clang knows whether its special members are trivial
  if TPCTypeExpr.IsOpaqueTier(AType) then
    Exit(ofClangDecides);
  LCanon := AType.Canon();
  if LCanon is TPCBuiltinType then
  begin
    if (TPCBuiltinType(LCanon).BuiltinToken = tkKwString) or
      (TPCBuiltinType(LCanon).BuiltinToken = tkKwWstring) then
      Exit(ofNeverFits);
    Exit(ofFits);
  end;
  if LCanon is TPCArrayType then
  begin
    // std::vector owns its storage; ::pcpp::Array is plain data (A8b)
    LArray := TPCArrayType(LCanon);
    if LArray.IsDynamic then
      Exit(ofNeverFits);
    Exit(DoFitIn(LArray.ElementType, AVisited));
  end;
  // own / ref / weak own an object (SM0357 reports one in an overlay)
  if LCanon is TPCOwnerType then
    Exit(ofNeverFits);
  // Scalars, pointers, routine types, choices, sets (trivial aggregates,
  // runtime fits_overlay asserts) and anything SEM reported are trivial data;
  // an overlay is judged at its own declaration
  if not (LCanon is TPCRecordType) then
    Exit;
  LRecord := TPCRecordType(LCanon);
  // An object keeps member initializers and may have a done (SM0357's)
  if LRecord.IsObject then
    Exit(ofNeverFits);
  if AVisited.Contains(LCanon) then
    Exit;
  AVisited.Add(LCanon);
  try
    // A record is plain data (M9: no member initializers); a C/C++ parent is
    // clang's (IsOpaqueTier), a PaskalCPP parent (a member, M10) is walked
    Result := DoMembersFit(LRecord.Members, AVisited);
    if LRecord.ParentName <> nil then
      Result := DoWorseFit(Result, DoFitIn(LRecord.ParentName, AVisited));
  finally
    AVisited.Remove(LCanon);
  end;
end;

function DoMembersFit(const AMembers: TList<TPCMemberItem>;
  const AVisited: TList<TPCTypeExpr>): TPCOverlayFit;
var
  LMember: TPCMemberItem;
begin
  // Fields and anonymous records hold data; methods do not. An anonymous
  // overlay is judged where it is declared (the walk's header)
  Result := ofFits;
  if AMembers = nil then
    Exit;
  for LMember in AMembers do
  begin
    if LMember is TPCField then
      Result := DoWorseFit(Result, DoFitIn(TPCField(LMember).TypeExpr, AVisited))
    else if (LMember is TPCAnonAggregate) and not TPCAnonAggregate(LMember).IsOverlay then
      Result := DoWorseFit(Result, DoMembersFit(TPCAnonAggregate(LMember).Members, AVisited));
    if Result = ofNeverFits then
      Exit;
  end;
end;

{ TPCTypeExpr }

function TPCTypeExpr.TypeText(): string;
begin
  // Every concrete type class overrides it; the abstract base names its kind
  Result := KindName();
end;

function TPCTypeExpr.Canon(): TPCTypeExpr;
var
  LVisited: TList<TPCTypeDecl>;
  LDecl: TPCTypeDecl;
begin
  Result := Self;
  LVisited := TList<TPCTypeDecl>.Create();
  try
    while (Result is TPCNamedType) and (TPCNamedType(Result).ResolvedKind = rkType) and
      (TPCNamedType(Result).ResolvedDecl <> nil) do
    begin
      LDecl := TPCNamedType(Result).ResolvedDecl;
      if LDecl.IsForward then
      begin
        // No full yet: the named type is as far as Canon goes (SEM's
        // DoCheckComplete judges whether that is legal where it stands)
        if LDecl.ResolvedFull = nil then
          Exit;
        LDecl := LDecl.ResolvedFull;
      end;
      // A forward's full is a record / object / overlay (decls.md :95) and an
      // alias names only earlier declarations: a revisit is a defect upstream
      if LVisited.Contains(LDecl) then
        raise EInvalidOpException.CreateFmt(RSAstCanonCycle, [LDecl.DeclName]);
      LVisited.Add(LDecl);
      if LDecl.TypeDef = nil then
        Exit;
      Result := LDecl.TypeDef;
    end;
  finally
    LVisited.Free();
  end;
end;

function TPCTypeExpr.HoldsStringOrDynamicArray(): Boolean;
var
  LVisited: TList<TPCTypeExpr>;
begin
  LVisited := TList<TPCTypeExpr>.Create();
  try
    Result := DoHoldsIn(Self, LVisited);
  finally
    LVisited.Free();
  end;
end;

function TPCTypeExpr.FieldPacking(): TPCFieldPacking;
var
  LVisited: TList<TPCTypeExpr>;
begin
  LVisited := TList<TPCTypeExpr>.Create();
  try
    Result := DoPackingIn(Self, LVisited);
  finally
    LVisited.Free();
  end;
end;

function TPCTypeExpr.OverlayFit(): TPCOverlayFit;
var
  LVisited: TList<TPCTypeExpr>;
begin
  LVisited := TList<TPCTypeExpr>.Create();
  try
    Result := DoFitIn(Self, LVisited);
  finally
    LVisited.Free();
  end;
end;

class function TPCTypeExpr.PointerOf(const AType: TPCTypeExpr; out ATarget: TPCTypeExpr;
  out AIsConst: Boolean): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // Moved verbatim from TPCSemantics.DoPointerOf (PLAN-EDITOR E2.9 k4)
  ATarget := nil;
  AIsConst := False;
  if AType = nil then
    Exit(False);
  LCanon := AType.Canon();
  if LCanon is TPCPointerType then
  begin
    ATarget := TPCPointerType(LCanon).TargetType;
    AIsConst := TPCPointerType(LCanon).IsConstTarget;
    Exit(True);
  end;
  if (LCanon is TPCDerivedType) and (TPCDerivedType(LCanon).DerivedKind = dkPointerTo) then
  begin
    ATarget := TPCDerivedType(LCanon).Target;
    AIsConst := TPCDerivedType(LCanon).IsConstTarget;
    Exit(True);
  end;
  Result := False;
end;

class function TPCTypeExpr.HeapTargetOf(const AType: TPCTypeExpr; out ATarget: TPCTypeExpr): TPCHeapTarget;
var
  LIsConst: Boolean;
  LCanon: TPCTypeExpr;
begin
  // A typed pointer only (an untyped ptr has no type to build); a C/C++
  // target is clang's; a record and an overlay are the same plain data
  // (F34 / F35: value-initialized, zeroed); an object is an own's / ref's
  Result := htNone;
  if not PointerOf(AType, ATarget, LIsConst) or (ATarget = nil) then
  begin
    ATarget := nil;
    Exit;
  end;
  if IsOpaqueTier(ATarget) then
    Exit(htOpaque);
  LCanon := ATarget.Canon();
  if LCanon is TPCOverlayType then
    Exit(htData);
  if LCanon is TPCRecordType then
  begin
    if TPCRecordType(LCanon).IsObject then
      Exit(htObject);
    Exit(htData);
  end;
  ATarget := nil;
end;

class function TPCTypeExpr.PrintForm(const AType: TPCTypeExpr): TPCPrintForm;
var
  LCanon: TPCTypeExpr;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
  LElementForm: TPCPrintForm;
begin
  // A pointer prints by its target through aliases (char -> CStr, wchar ->
  // WCStr; an untyped ptr as written; any other target its address, E7);
  // a wchar / wstring through aliases prints as UTF-8. A wchar bitfield
  // reads as wchar here: its field type is wchar (F25 only changes its
  // storage), the emitter casts it before utf8. E7: a routine value prints
  // its address; a record / object / overlay is unprintable; an array takes
  // its element's form (as is when the element prints as is)
  Result := pfAsIs;
  if AType = nil then
    Exit;
  if IsOpaqueTier(AType) then
    Exit(pfCppChecked);
  if PointerOf(AType, LTarget, LIsConst) then
  begin
    if LTarget = nil then
      Exit;
    LTarget := LTarget.Canon();
    Result := pfTypedAddress;
    if LTarget is TPCBuiltinType then
    begin
      if TPCBuiltinType(LTarget).BuiltinToken = tkKwChar then
        Result := pfCStr
      else if TPCBuiltinType(LTarget).BuiltinToken = tkKwWchar then
        Result := pfWCStr;
    end;
    Exit;
  end;
  LCanon := AType.Canon();
  if LCanon is TPCBuiltinType then
  begin
    if TPCBuiltinType(LCanon).BuiltinToken = tkKwWchar then
      Result := pfWideChar
    else if TPCBuiltinType(LCanon).BuiltinToken = tkKwWstring then
      Result := pfWideText;
  end
  // F62 (lex_strings): an L"..." literal is wide text as a wstring is; it
  // printed as written and failed inside libc++ (no formatter for wchar_t[N])
  else if (LCanon is TPCStringLiteralType) and TPCStringLiteralType(LCanon).IsWide then
    Result := pfWideText
  else if LCanon is TPCRoutineType then
    Result := pfRoutineAddress
  else if (LCanon is TPCRecordType) or (LCanon is TPCOverlayType) or (LCanon is TPCOwnerType) then
    Result := pfUnprintable    // PLAN-OBJECT O6: own / ref / weak hold an object: print its fields
  else if LCanon is TPCArrayType then
  begin
    LElementForm := PrintForm(TPCArrayType(LCanon).ElementType);
    if (LElementForm = pfUnprintable) or (LElementForm = pfCppChecked) then
      Result := LElementForm
    else if LElementForm <> pfAsIs then
      Result := pfElements;
  end;
end;

class function TPCTypeExpr.PrintFormOfArg(const AArg: TPCExpr): TPCPrintForm;
var
  LRoutine: TPCRoutine;
begin
  // A routine named as a value (rkRoutine on a name or a member, never
  // typed by SEM): one routine prints its address; an overload set (rvSet,
  // TPCExpr.RoutineValueOf) or a method has none.
  // Every other argument: its type's form
  if AArg = nil then
    Exit(pfAsIs);
  case TPCExpr.RoutineValueOf(AArg, LRoutine) of
    rvRoutine:
      Result := pfRoutineAddress;
    rvSet, rvMethod:
      Result := pfNoAddress;
  else
    Result := PrintForm(AArg.ResolvedType);
  end;
end;

class function TPCTypeExpr.IsOpaqueTier(const AType: TPCTypeExpr): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // Moved from TPCSemantics.DoIsOpaqueTier (F20: TPCScopes reads it too)
  if AType = nil then
    Exit(False);
  LCanon := AType.Canon();
  Result := (LCanon is TPCOpaqueType) or (LCanon is TPCCppType) or
    ((LCanon is TPCNamedType) and (TPCNamedType(LCanon).ResolvedKind = rkOpaque));
end;

function TPCTypeExpr.IsScalarOrPointer(): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  LCanon := Canon();
  if LCanon is TPCBuiltinType then
    Exit((TPCBuiltinType(LCanon).BuiltinToken <> tkKwString) and
      (TPCBuiltinType(LCanon).BuiltinToken <> tkKwWstring));
  if LCanon is TPCDerivedType then
    Exit(TPCDerivedType(LCanon).DerivedKind = dkPointerTo);
  Result := (LCanon is TPCPointerType) or (LCanon is TPCRoutineType) or (LCanon is TPCChoicesType);
end;

{ TPCExpr }

function TPCExpr.DoDumpResolved(): string;
begin
  Result := '';
  // TypeText has spaces (ptr to const char): quoted, one node one line
  if ResolvedType <> nil then
    Result := Result + ' type=' + QuoteText(ResolvedType.TypeText());
  if HasConstValue then
  begin
    if ConstIsUnsigned then
      Result := Result + ' const=' + UIntToStr(ConstUInt)
    else
      Result := Result + ' const=' + IntToStr(ConstInt);
  end;
  if HasConstFloat then
    Result := Result + ' constf=' + FloatText(ConstFloat);
end;

function TPCExpr.BoundText(): string;
var
  LCanon: TPCTypeExpr;
begin
  // An integer's value once folded (KLast prints 3). A char or choices bound
  // folds to its ordinal, which is no PaskalCPP spelling of it: it prints as
  // written ('A', TColor.cRed), so a message names it as the person wrote it
  if ResolvedType <> nil then
  begin
    LCanon := ResolvedType.Canon();
    if (LCanon is TPCChoicesType) or ((LCanon is TPCBuiltinType) and
      (TPCBuiltinType(LCanon).BuiltinToken in [tkKwChar, tkKwWchar])) then
      Exit(ExprText());
  end;
  Result := '';
  if HasConstFloat then
    Result := FloatText(ConstFloat)
  else if HasConstValue then
  begin
    if ConstIsUnsigned then
      Result := UIntToStr(ConstUInt)
    else
      Result := IntToStr(ConstInt);
  end;
  if Result = '' then
    Result := ExprText();
end;

function TPCExpr.ExprText(): string;
begin
  // Every concrete expression class overrides it
  Result := KindName();
end;

function TPCExpr.ExprPower(): Integer;
begin
  // A primary expression: never parenthesised
  Result := 60;
end;

class function TPCExpr.RoutineValueOf(const AValue: TPCExpr; out ARoutine: TPCRoutine): TPCRoutineValueKind;
var
  LDecl: TPCNode;
begin
  // A name: its declaration once bound (a lone routine, or the set member
  // a position chose: SEM's DoBindRoutineValue), else its set; a member: a
  // module's routine or set, or a method (a record base). The order keeps
  // PrintFormOfArg's results (E7): a set prints no address, nor a method
  ARoutine := nil;
  if AValue is TPCName then
  begin
    if TPCName(AValue).ResolvedKind <> rkRoutine then
      Exit(rvNone);
    LDecl := TPCName(AValue).ResolvedDecl;
    if LDecl is TPCRoutine then
      ARoutine := TPCRoutine(LDecl)
    else
      ARoutine := TPCName(AValue).ResolvedSetMember;
    if ARoutine = nil then
      Exit(rvNone);
    if ARoutine.RoutineKind = rnMethod then
      Exit(rvMethod);
    if LDecl is TPCRoutine then
      Exit(rvRoutine);
    Exit(rvSet);
  end;
  if AValue is TPCMember then
  begin
    if TPCMember(AValue).ResolvedKind <> rkRoutine then
      Exit(rvNone);
    LDecl := TPCMember(AValue).ResolvedDecl;
    if LDecl is TPCRoutine then
    begin
      ARoutine := TPCRoutine(LDecl);
      if ARoutine.RoutineKind = rnMethod then
        Exit(rvMethod);
      Exit(rvRoutine);
    end;
    // No declaration: an overload set, a module's (M.F) or a method set
    if (TPCMember(AValue).Base is TPCName) and (TPCName(TPCMember(AValue).Base).ResolvedKind = rkModule) then
      Exit(rvSet);
    Exit(rvMethod);
  end;
  Result := rvNone;
end;

function DoMembersPackField(const AMembers: TList<TPCMemberItem>; const AField: TPCNode;
  const APacked: Boolean; out AFound: Boolean): Boolean;
var
  LItem: TPCMemberItem;
  LAggregate: TPCAnonAggregate;
begin
  // AField found in AMembers or an anonymous aggregate below them (AFound);
  // Result = a packed anonymous aggregate on the way holds it (APacked =
  // one above already does)
  AFound := False;
  Result := False;
  if AMembers = nil then
    Exit;
  for LItem in AMembers do
  begin
    if LItem = AField then
    begin
      AFound := True;
      Exit(APacked);
    end;
    if LItem is TPCAnonAggregate then
    begin
      LAggregate := TPCAnonAggregate(LItem);
      Result := DoMembersPackField(LAggregate.Members, AField, APacked or LAggregate.IsPacked, AFound);
      if AFound then
        Exit;
    end;
  end;
  Result := False;
end;

function TPCExpr.OnPackedPath(): Boolean;
var
  LIndex: TPCIndex;
  LMember: TPCMember;
  LBaseType: TPCTypeExpr;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
  LLevel: TPCRecordType;
  LHop: Integer;
  LFound: Boolean;
  LEmbed: TPCField;
  LSteps: Integer;
begin
  Result := False;
  // PLAN-RECORDS A8c: C++'s ?: of two lvalues of one type is an lvalue, the
  // one either branch names: it sits where a branch sits (with a prvalue
  // branch the result is a copy already; a copy made again costs nothing)
  if Self is TPCTernary then
    Exit(((TPCTernary(Self).ThenExpr <> nil) and TPCTernary(Self).ThenExpr.OnPackedPath()) or
      ((TPCTernary(Self).ElseExpr <> nil) and TPCTernary(Self).ElseExpr.OnPackedPath()));
  // A static array's element sits where its array sits; a dynamic array's,
  // a string's and a pointer's live elsewhere (aligned)
  if Self is TPCIndex then
  begin
    LIndex := TPCIndex(Self);
    if (LIndex.Base = nil) or (LIndex.Base.ResolvedType = nil) then
      Exit;
    LBaseType := LIndex.Base.ResolvedType.Canon();
    if (LBaseType is TPCArrayType) and not TPCArrayType(LBaseType).IsDynamic then
      Exit(LIndex.Base.OnPackedPath());
    Exit;
  end;
  if not (Self is TPCMember) then
    Exit;
  LMember := TPCMember(Self);
  if (LMember.ResolvedKind <> rkField) or (LMember.Base = nil) or (LMember.Base.ResolvedType = nil) then
    Exit;
  LBaseType := LMember.Base.ResolvedType.Canon();
  if LMember.Access = maArrow then
  begin
    // '->': the record the pointer points to is aligned; only the field's
    // own placement inside it counts
    if not TPCTypeExpr.PointerOf(LBaseType, LTarget, LIsConst) or (LTarget = nil) then
      Exit;
    LBaseType := LTarget.Canon();
  end
  else if LMember.Base.OnPackedPath() then
    Exit(True);
  // PLAN-OBJECT O8: a promoted member lies inside the embeds SEM walked: a
  // packed level of the chain holding an embed may misplace it; the walk
  // then goes on inside the last embedded type (a bounded walk: a parent
  // cycle is SEM's report, never a hang here)
  for LEmbed in LMember.ResolvedEmbedPath do
  begin
    if not (LBaseType is TPCRecordType) then
      Exit;
    LLevel := TPCRecordType(LBaseType);
    LSteps := 0;
    while (LLevel <> nil) and (LSteps < 256) do
    begin
      if LLevel.IsPacked then
        Exit(True);
      // Every parent kind (an object's C++ base too): the embed may be an
      // ancestor level's
      if (LLevel.ParentName <> nil) and (LLevel.ParentName.Canon() is TPCRecordType) then
        LLevel := TPCRecordType(LLevel.ParentName.Canon())
      else
        LLevel := nil;
      Inc(LSteps);
    end;
    if LEmbed.TypeExpr = nil then
      Exit;
    LBaseType := LEmbed.TypeExpr.Canon();
  end;
  if LBaseType is TPCRecordType then
  begin
    // Every member parent sits at offset 0 of its level (M10): a packed
    // level on the way to the declaring level places it (ResolvedParentHops)
    LLevel := TPCRecordType(LBaseType);
    for LHop := 1 to LMember.ResolvedParentHops do
    begin
      if LLevel.IsPacked then
        Exit(True);
      LLevel := LLevel.ParentRecord();
      if LLevel = nil then
        Exit;
    end;
    if LLevel.IsPacked then
      Exit(True);
    Exit(DoMembersPackField(LLevel.Members, LMember.ResolvedDecl, False, LFound));
  end;
  if LBaseType is TPCOverlayType then
    Exit(DoMembersPackField(TPCOverlayType(LBaseType).Members, LMember.ResolvedDecl, False, LFound));
end;

{ TPCDecl }

function TPCDecl.DoDumpText(): string;
begin
  Result := QuoteText(DeclName);
  if IsExported then
    Result := Result + ' exported';
end;

class procedure TPCDecl.CollectNamed(const AItems: TList<TPCStmt>; const ACount: Integer;
  const ADeclName: string; const AFound: TList<TPCDecl>);
var
  LIndex: Integer;
  LLast: Integer;
  LStmt: TPCStmt;
begin
  // A count past the list end is clamped to the list (never an index past
  // it); a count <= 0 collects nothing. Nil lists collect nothing
  if (AItems = nil) or (AFound = nil) then
    Exit;
  LLast := ACount;
  if LLast > AItems.Count then
    LLast := AItems.Count;
  for LIndex := 0 to LLast - 1 do
  begin
    LStmt := AItems[LIndex];
    if DoIsNamed(LStmt, ADeclName) then
      AFound.Add(TPCDecl(LStmt));
  end;
end;

class function TPCDecl.DoIsNamed(const AStmt: TPCStmt; const ADeclName: string): Boolean;
begin
  // A declaration with exactly that name (exact case); verbatim items are not
  Result := (AStmt is TPCDecl) and (TPCDecl(AStmt).DeclName = ADeclName);
end;

class procedure TPCDecl.CollectNamedAfter(const AItems: TList<TPCStmt>; const AIndex: Integer;
  const ADeclName: string; const AFound: TList<TPCDecl>);
var
  LIndex: Integer;
  LFirst: Integer;
  LStmt: TPCStmt;
begin
  // Nil lists collect nothing; an index below -1 counts as -1 (every item)
  if (AItems = nil) or (AFound = nil) then
    Exit;
  LFirst := AIndex + 1;
  if LFirst < 0 then
    LFirst := 0;
  for LIndex := LFirst to AItems.Count - 1 do
  begin
    LStmt := AItems[LIndex];
    if DoIsNamed(LStmt, ADeclName) then
      AFound.Add(TPCDecl(LStmt));
  end;
end;

{ TPCDirectiveArg }

constructor TPCDirectiveArg.Create();
begin
  inherited;

  FNodeKind := nkDirectiveArg;
end;

function TPCDirectiveArg.DoDumpText(): string;
begin
  Result := GetEnumName(TypeInfo(TPCDirectiveArgKind), Ord(ArgKind)) + ' ' +
    QuoteText(Text);
  // A cstring's value is its dumped resolved= text: value= is an integer's only
  if (ArgKind = daInteger) and HasValue then
    Result := Result + ' value=' + UIntToStr(IntValue);
end;

function TPCDirectiveArg.DoDumpResolved(): string;
begin
  Result := '';
  if ResolvedText <> '' then
    Result := ' resolved=' + QuoteText(ResolvedText);
end;

{ TPCDirective }

constructor TPCDirective.Create();
begin
  inherited;

  FNodeKind := nkDirective;
  Args := TList<TPCDirectiveArg>.Create();
end;

destructor TPCDirective.Destroy();
begin
  Args.Free();

  inherited;
end;

function TPCDirective.DoDumpText(): string;
begin
  Result := QuoteText(DirectiveName);
end;

function TPCDirective.DoDumpResolved(): string;
begin
  Result := '';
  if ResolvedNoEffect then
    Result := ' noeffect';
end;

procedure TPCDirective.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCDirectiveArg>(Args, AVisit);
end;

{ TPCImport }

constructor TPCImport.Create();
begin
  inherited;

  FNodeKind := nkImport;
end;

function TPCImport.DoDumpText(): string;
begin
  Result := QuoteText(ModuleName);
end;

function TPCImport.DoDumpResolved(): string;
begin
  // The linked module is named, never walked: it is its own tree
  Result := '';
  if ImportedModule <> nil then
    Result := ' -> ' + QuoteText(ImportedModule.ModuleName);
end;

{ TPCBlock }

constructor TPCBlock.Create();
begin
  inherited;

  FNodeKind := nkBlock;
  Stmts := TList<TPCStmt>.Create();
end;

destructor TPCBlock.Destroy();
begin
  Stmts.Free();

  inherited;
end;

procedure TPCBlock.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCStmt>(Stmts, AVisit);
end;

function DoLiteralFactsText(const ABase: TPCLiteralBase; const APrefix: TPCLiteralPrefix;
  const AIsRawString: Boolean; const ASuffix: string; const AIsUserDefined: Boolean): string;
begin
  // A literal's token facts, each with a leading space; only those that differ
  // from the default (plain decimal / no prefix / not raw / no suffix), so a
  // plain literal dumps the same as before the facts existed
  Result := '';
  if (ABase <> lbNone) and (ABase <> lbDecimal) then
    Result := Result + ' base=' + GetEnumName(TypeInfo(TPCLiteralBase), Ord(ABase));
  if APrefix <> lpNone then
    Result := Result + ' prefix=' + GetEnumName(TypeInfo(TPCLiteralPrefix), Ord(APrefix));
  if AIsRawString then
    Result := Result + ' raw';
  if ASuffix <> '' then
    Result := Result + ' suffix=' + TPCNode.QuoteText(ASuffix);
  if AIsUserDefined then
    Result := Result + ' udl';
end;

function DoValueMapText(const ARuns: TArray<TPCValueRun>): string;
var
  LI: Integer;
begin
  // c<ValueOffset>@<Line>:<Column> for a copy run, e<...> for an escape (D-SP3)
  Result := '';
  for LI := 0 to Length(ARuns) - 1 do
  begin
    if LI > 0 then
      Result := Result + ' ';
    if ARuns[LI].IsCopy then
      Result := Result + 'c'
    else
      Result := Result + 'e';
    Result := Result + IntToStr(ARuns[LI].ValueOffset) + '@' + UIntToStr(ARuns[LI].Line) +
      ':' + UIntToStr(ARuns[LI].Column);
  end;
end;

function DoJumpsText(const AJumps: TArray<TPCCppJump>): string;
var
  LI: Integer;
begin
  // <kind>@<Line>:<Column> of each jump word, in source order (jump.md :126)
  Result := '';
  for LI := 0 to Length(AJumps) - 1 do
  begin
    if LI > 0 then
      Result := Result + ' ';
    case AJumps[LI].Kind of
      cjReturn:
        Result := Result + 'return';
      cjBreak:
        Result := Result + 'break';
      cjContinue:
        Result := Result + 'continue';
    end;
    Result := Result + '@' + UIntToStr(AJumps[LI].Range.StartLine) + ':' +
      UIntToStr(AJumps[LI].Range.StartColumn);
  end;
end;

{ TPCLiteral }

constructor TPCLiteral.Create();
begin
  inherited;

  FNodeKind := nkLiteral;
end;

function TPCLiteral.DoDumpText(): string;
var
  LI: Integer;
  LPartFacts: string;
begin
  Result := GetEnumName(TypeInfo(TPCLiteralKind), Ord(LiteralKind)) + ' ' +
    QuoteText(Text);
  Result := Result + DoLiteralFactsText(LiteralBase, LiteralPrefix, False, Suffix,
    IsUserDefined);
  // A string part shows its facts only when it has any: partN=[...]
  for LI := 0 to Length(Parts) - 1 do
  begin
    LPartFacts := DoLiteralFactsText(lbNone, Parts[LI].LiteralPrefix,
      Parts[LI].IsRawString, Parts[LI].Suffix, Parts[LI].IsUserDefined);
    if Parts[LI].HasValue then
      LPartFacts := LPartFacts + ' value=' + QuoteText(Parts[LI].Value);
    if LPartFacts <> '' then
      Result := Result + ' part' + IntToStr(LI) + '=[' + LPartFacts.Trim() + ']';
  end;
  // Value maps after every part (D-SP3: the partN expectations stay contiguous)
  for LI := 0 to Length(Parts) - 1 do
  begin
    if Length(Parts[LI].ValueMap) > 0 then
      Result := Result + ' map' + IntToStr(LI) + '=[' + DoValueMapText(Parts[LI].ValueMap) + ']';
  end;
  if IsMultiChar then
    Result := Result + ' multichar';
  if HasValue then
  begin
    if LiteralKind = lkFloat then
      Result := Result + ' value=' + FloatText(FloatValue)
    else
      Result := Result + ' value=' + UIntToStr(IntValue);
  end;
end;

function TPCLiteral.ExprText(): string;
begin
  Result := Text;
end;

function TPCLiteral.DecodedValue(out AValue: string): Boolean;
var
  LIndex: Integer;
  LValue: string;
begin
  // Adjacent plain parts concatenate (C++ phase 6); one part without a value
  // (a decode error, a prefix) leaves the whole literal without one
  AValue := '';
  if Length(Parts) = 0 then
    Exit(False);
  LValue := '';
  for LIndex := 0 to High(Parts) do
  begin
    if not Parts[LIndex].HasValue then
      Exit(False);
    LValue := LValue + Parts[LIndex].Value;
  end;
  AValue := LValue;
  Result := True;
end;

{ Zero escapes }
// HoldsNul's test for a part with no decoded value (an L part): an escape in
// its quoted text whose value is 0. C++'s escapes: \ooo (1-3 octal digits),
// \o{...}, \xhh..., \x{...}, \uhhhh, \Uhhhhhhhh; any other \c is one element

function DoTextHoldsZeroEscape(const AText: string): Boolean;
var
  LFirst: Integer;
  LLast: Integer;
  LIndex: Integer;
  LCount: Integer;
  LZero: Boolean;
  LChar: Char;

  // The digits from LIndex while ADigits holds them (at most AMax; 0 = any):
  // True when there is at least one and every one is '0'
  function DoZeroRun(const ADigits: TSysCharSet; const AMax: Integer): Boolean;
  begin
    LCount := 0;
    LZero := True;
    while (LIndex <= LLast) and CharInSet(AText[LIndex], ADigits) and ((AMax = 0) or (LCount < AMax)) do
    begin
      if AText[LIndex] <> '0' then
        LZero := False;
      Inc(LCount);
      Inc(LIndex);
    end;
    Result := (LCount > 0) and LZero;
  end;

begin
  Result := False;
  LFirst := Pos('"', AText);
  LLast := AText.LastIndexOf('"');
  if (LFirst = 0) or (LLast + 1 <= LFirst) then
    Exit;
  // AText is 1-based for the scan: the content is LFirst + 1 .. LLast
  LIndex := LFirst + 1;
  while LIndex <= LLast do
  begin
    if AText[LIndex] <> '\' then
    begin
      Inc(LIndex);
      Continue;
    end;
    Inc(LIndex);
    if LIndex > LLast then
      Exit;
    LChar := AText[LIndex];
    if CharInSet(LChar, ['0'..'7']) then
    begin
      if DoZeroRun(['0'..'7'], 3) then
        Exit(True);
      Continue;
    end;
    Inc(LIndex);
    if CharInSet(LChar, ['x', 'o']) and (LIndex <= LLast) and (AText[LIndex] = '{') then
    begin
      Inc(LIndex);
      if CharInSet(LChar, ['o']) then
      begin
        if DoZeroRun(['0'..'7'], 0) and (LIndex <= LLast) and (AText[LIndex] = '}') then
          Exit(True);
      end
      else if DoZeroRun(['0'..'9', 'a'..'f', 'A'..'F'], 0) and (LIndex <= LLast) and (AText[LIndex] = '}') then
        Exit(True);
    end
    else if LChar = 'x' then
    begin
      if DoZeroRun(['0'..'9', 'a'..'f', 'A'..'F'], 0) then
        Exit(True);
    end
    else if LChar = 'u' then
    begin
      if DoZeroRun(['0'..'9', 'a'..'f', 'A'..'F'], 4) and (LCount = 4) then
        Exit(True);
    end
    else if LChar = 'U' then
    begin
      if DoZeroRun(['0'..'9', 'a'..'f', 'A'..'F'], 8) and (LCount = 8) then
        Exit(True);
    end;
  end;
end;

function TPCLiteral.HoldsNul(): Boolean;
var
  LPart: TPCLiteralPart;
begin
  // Every part: a plain one by its decoded value, an L one by its escapes;
  // a raw part has no escapes (a NUL cannot be written in one)
  Result := False;
  if LiteralKind <> lkString then
    Exit;
  for LPart in Parts do
  begin
    if LPart.IsRawString then
      Continue;
    if LPart.HasValue then
    begin
      if Pos(#0, LPart.Value) > 0 then
        Exit(True);
    end
    else if DoTextHoldsZeroEscape(LPart.Text) then
      Exit(True);
  end;
end;

{ TPCTest }

constructor TPCTest.Create();
begin
  inherited;

  FNodeKind := nkTest;
  Decls := TList<TPCStmt>.Create();
end;

destructor TPCTest.Destroy();
begin
  Decls.Free();

  inherited;
end;

procedure TPCTest.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(TestName, AVisit);
  VisitList<TPCStmt>(Decls, AVisit);
  VisitNode(Body, AVisit);
end;

{ TPCVerbatimStmt }

constructor TPCVerbatimStmt.Create();
begin
  inherited;

  FNodeKind := nkVerbatimStmt;
end;

function TPCVerbatimStmt.DoDumpText(): string;
begin
  Result := GetEnumName(TypeInfo(TPCVerbatimKind), Ord(Verbatim.VerbatimKind)) + ' ' +
    GetEnumName(TypeInfo(TPCEmitTarget), Ord(Verbatim.EmitTarget)) + ' ' +
    QuoteText(Verbatim.Text);
  // only when the block has escaping jumps: no existing dump changes (jump.md :126-129)
  if Length(Verbatim.EscapingJumps) > 0 then
    Result := Result + ' jumps=[' + DoJumpsText(Verbatim.EscapingJumps) + ']';
end;

{ TPCVerbatimExpr }

constructor TPCVerbatimExpr.Create();
begin
  inherited;

  FNodeKind := nkVerbatimExpr;
end;

function TPCVerbatimExpr.DoDumpText(): string;
begin
  Result := GetEnumName(TypeInfo(TPCVerbatimKind), Ord(Verbatim.VerbatimKind)) + ' ' +
    GetEnumName(TypeInfo(TPCEmitTarget), Ord(Verbatim.EmitTarget)) + ' ' +
    QuoteText(Verbatim.Text);
end;

function TPCVerbatimExpr.ExprText(): string;
begin
  // Verbatim C++ (a lambda, sizeof(...), cpp("...")'s decoded text)
  Result := Verbatim.Text;
end;

{ TPCModule }

constructor TPCModule.Create();
begin
  inherited;

  FNodeKind := nkModule;
  Directives := TList<TPCDirective>.Create();
  Imports := TList<TPCImport>.Create();
  Decls := TList<TPCStmt>.Create();
  Tests := TList<TPCTest>.Create();
end;

destructor TPCModule.Destroy();
begin
  Tests.Free();
  Decls.Free();
  Imports.Free();
  Directives.Free();

  inherited;
end;

function TPCModule.DoDumpText(): string;
begin
  Result := QuoteText(ModuleName) + ' ' +
    GetEnumName(TypeInfo(TPCModuleKind), Ord(ModuleKind));
end;

function TPCModule.DoDumpResolved(): string;
begin
  Result := '';
  if not ResolvedTarget.IsEmpty() then
    Result := ' target=' + QuoteText(ResolvedTarget.ToLLVM());
end;

procedure TPCModule.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  // Source order: initialize and finalize stand after the declarations (BNF sec 1)
  VisitList<TPCDirective>(Directives, AVisit);
  VisitList<TPCImport>(Imports, AVisit);
  VisitList<TPCStmt>(Decls, AVisit);
  VisitNode(InitRoutine, AVisit);
  VisitNode(FinalRoutine, AVisit);
  VisitNode(Body, AVisit);
  VisitList<TPCTest>(Tests, AVisit);
end;

{ TPCOpaqueType }

constructor TPCOpaqueType.Create();
begin
  inherited;

  FNodeKind := nkOpaqueType;
end;

function TPCOpaqueType.TypeText(): string;
begin
  Result := 'opaque';
end;

{ TPCErrorType }

constructor TPCErrorType.Create();
begin
  inherited;

  FNodeKind := nkErrorType;
end;

function TPCErrorType.TypeText(): string;
begin
  Result := 'error';
end;

{ TPCErrorStmt }

constructor TPCErrorStmt.Create();
begin
  inherited;

  FNodeKind := nkErrorStmt;
  Fragment := nil;
end;

procedure TPCErrorStmt.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Fragment, AVisit);
end;

{ TPCErrorExpr }

constructor TPCErrorExpr.Create();
begin
  inherited;

  FNodeKind := nkErrorExpr;
  Parts := TList<TPCExpr>.Create();
end;

destructor TPCErrorExpr.Destroy();
begin
  Parts.Free();

  inherited;
end;

procedure TPCErrorExpr.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCExpr>(Parts, AVisit);
end;

function TPCErrorExpr.ExprText(): string;
begin
  Result := 'error';
end;

{ TPCErrorMember }

constructor TPCErrorMember.Create();
begin
  inherited;

  FNodeKind := nkErrorMember;
end;

{ TPCNilType }

constructor TPCNilType.Create();
begin
  inherited;

  FNodeKind := nkNilType;
end;

function TPCNilType.TypeText(): string;
begin
  Result := 'nil';
end;

{ TPCVoidType }

constructor TPCVoidType.Create();
begin
  inherited;

  FNodeKind := nkVoidType;
end;

function TPCVoidType.TypeText(): string;
begin
  Result := 'void';
end;

{ TPCStringLiteralType }

constructor TPCStringLiteralType.Create();
begin
  inherited;

  FNodeKind := nkStringLiteralType;
end;

function TPCStringLiteralType.DoDumpText(): string;
begin
  Result := '';
  if IsWide then
    Result := 'wide';
end;

function TPCStringLiteralType.TypeText(): string;
begin
  if IsWide then
    Result := 'wide string literal'
  else
    Result := 'string literal';
end;

{ Dump helpers }
// Implementation-only helpers shared by the DoDumpText / DoDumpResolved
// overrides below (PLAN-CPPMIX-AST-NODES N7, N8)

procedure DoAddWord(var AText: string; const AWord: string);
begin
  // Appends one space-separated word; an empty word adds nothing
  if AWord = '' then
    Exit;
  if AText <> '' then
    AText := AText + ' ';
  AText := AText + AWord;
end;

function DoFlagText(const AFlag: Boolean; const AWord: string): string;
begin
  if AFlag then
    Result := AWord
  else
    Result := '';
end;

function DoCountText(const AWord: string; const ACount: Integer): string;
begin
  Result := AWord + '=' + IntToStr(ACount);
end;

function DoCvText(const AFlags: TPCCvFlags): string;
begin
  // const+volatile is one word, so a cv set never splits across dump words
  Result := '';
  if cqConst in AFlags then
    Result := 'const';
  if cqVolatile in AFlags then
  begin
    if Result <> '' then
      Result := Result + '+';
    Result := Result + 'volatile';
  end;
end;

function DoLinkageText(const ALinkage: TPCLinkage): string;
begin
  Result := '';
  if ALinkage <> lnNone then
    Result := GetEnumName(TypeInfo(TPCLinkage), Ord(ALinkage));
end;

function DoExternalText(const AExternal: TPCExternal): string;
begin
  Result := '';
  if not AExternal.IsExternal then
    Exit;
  // A library name quoted, a const's name bare: the dump shows the form
  Result := 'external';
  if AExternal.LibKind = elCString then
    Result := Result + ' ' + TPCNode.QuoteText(AExternal.LibText)
  else if AExternal.LibKind = elIdentifier then
    Result := Result + ' ' + AExternal.LibText;
end;

function DoLibText(const AExternal: TPCExternal): string;
begin
  Result := '';
  if AExternal.ResolvedLib <> '' then
    Result := ' lib=' + TPCNode.QuoteText(AExternal.ResolvedLib);
end;

function DoRefText(const ANode: TPCNode): string;
var
  LName: string;
begin
  // A referenced node is named, never walked: its kind plus its name
  LName := '';
  if ANode is TPCDecl then
    LName := TPCDecl(ANode).DeclName
  else if ANode is TPCParam then
    LName := TPCParam(ANode).ParamName
  else if ANode is TPCField then
    LName := TPCField(ANode).FieldName
  else if ANode is TPCChoiceValue then
    LName := TPCChoiceValue(ANode).ValueName
  else if ANode is TPCModule then
    LName := TPCModule(ANode).ModuleName;
  Result := ANode.KindName();
  if LName <> '' then
    Result := Result + ' ' + TPCNode.QuoteText(LName);
end;

function DoResolvedText(const AKind: TPCResolvedKind; const ADecl: TPCNode): string;
begin
  Result := '';
  if AKind <> rkNone then
    Result := Result + ' kind=' + GetEnumName(TypeInfo(TPCResolvedKind), Ord(AKind));
  if ADecl <> nil then
    Result := Result + ' decl=' + DoRefText(ADecl);
end;

{ Spelling helpers }
// TypeText / ExprText helpers (research\cppmix\sem\prereq-a.md D-PA6, D-PA7, D-PA13)

const
  { EXPR_POWER_ASSIGN }
  // BNF.md sec 6 binding powers :566-579
  EXPR_POWER_ASSIGN = 2;
  { EXPR_POWER_TERNARY }
  EXPR_POWER_TERNARY = 4;
  { EXPR_POWER_PREFIX }
  EXPR_POWER_PREFIX = 35;
  { EXPR_POWER_CALL }
  EXPR_POWER_CALL = 40;
  { EXPR_POWER_POSTFIX }
  EXPR_POWER_POSTFIX = 45;
  { EXPR_POWER_DEREF }
  EXPR_POWER_DEREF = 50;
  { EXPR_POWER_IS }
  // PLAN-OBJECT O12: `is` binds as a relational operator, `as` as `*`
  EXPR_POWER_IS = 10;
  { EXPR_POWER_AS }
  EXPR_POWER_AS = 30;

  { BINARY_OP_POWER }
  // In TPCBinaryOp order; relational operators (10) do not chain
  BINARY_OP_POWER: array[TPCBinaryOp] of Integer = (
    6, 8, 10, 10, 10, 10, 10, 10, 10, 10,
    20, 20, 20, 20, 25, 25, 30, 30, 30, 30, 30
  );

  { BINARY_OP_TEXT }
  // The PaskalCPP spelling of each meaning (Parser.pas :581-612, first non-C++ row)
  BINARY_OP_TEXT: array[TPCBinaryOp] of string = (
    'or', 'and', '=', '<>', '<', '>', '<=', '>=', '<=>', 'in',
    '+', '-', '|', 'xor', 'shl', 'shr', '*', '/', 'div', 'mod', '&'
  );

  { ASSIGN_OP_TEXT }
  ASSIGN_OP_TEXT: array[TPCAssignOp] of string = (
    ':=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '<<=', '>>='
  );

  { NAMED_CAST_TEXT }
  // ckStatic .. ckDynamic; the other kinds have no keyword
  NAMED_CAST_TEXT: array[TPCCastKind] of string = (
    '', '', '', 'static_cast', 'reinterpret_cast', 'const_cast', 'dynamic_cast'
  );

  { SPECIAL_TEXT }
  SPECIAL_TEXT: array[TPCSpecialKind] of string = ('self', 'parent', 'this', 'nullptr');

function DoSpellingOf(const AKind: TPCTokenKind): string;
var
  LRow: TPCTokenRow;
begin
  // Only kinds with a registration row are spelled (fundamentals, keys, builtins)
  if not TPCVocabulary.FindKindRow(AKind, LRow) then
    raise EInvalidOpException.CreateFmt(RSAstNoSpelling,
      [GetEnumName(TypeInfo(TPCTokenKind), Ord(AKind))]);
  Result := LRow.Text;
end;

function DoCvSpelling(const AFlags: TPCCvFlags): string;
begin
  Result := '';
  if cqConst in AFlags then
    Result := 'const';
  if cqVolatile in AFlags then
    DoAddWord(Result, 'volatile');
end;

function DoTypeTextOf(const AType: TPCTypeExpr): string;
begin
  // A missing child was reported by the parser: it spells as the poison type
  if AType = nil then
    Exit('error');
  Result := AType.TypeText();
end;

function DoExprTextOf(const AExpr: TPCExpr): string;
begin
  if AExpr = nil then
    Exit('error');
  Result := AExpr.ExprText();
end;

function DoBoundText(const AExpr: TPCExpr): string;
begin
  // An array / set bound or a template expression (TPCExpr.BoundText, F44)
  if AExpr = nil then
    Exit('error');
  Result := AExpr.BoundText();
end;

function DoTemplateArgText(const AArg: TPCTemplateArg): string;
begin
  if AArg.HasVerbatim then
    Result := AArg.Verbatim.Text
  else if AArg.TypeArg <> nil then
    Result := AArg.TypeArg.TypeText()
  else
    Result := DoBoundText(AArg.ExprArg);
end;

function DoNamePartText(const APart: TPCNamePart): string;
var
  LI: Integer;
begin
  if APart = nil then
    Exit('error');
  Result := APart.PartText;
  if not APart.HasTemplateArgs then
    Exit;
  // std::vector<std::vector<int>>: '>>' closes two lists, as C++23 reads it
  Result := Result + '<';
  for LI := 0 to APart.TemplateArgs.Count - 1 do
  begin
    if LI > 0 then
      Result := Result + ', ';
    Result := Result + DoTemplateArgText(APart.TemplateArgs[LI]);
  end;
  Result := Result + '>';
end;

function DoNamePartsText(const AHasLeadingScope: Boolean;
  const AParts: TList<TPCNamePart>): string;
var
  LI: Integer;
begin
  Result := '';
  if AHasLeadingScope then
    Result := '::';
  for LI := 0 to AParts.Count - 1 do
  begin
    if LI > 0 then
      Result := Result + '::';
    Result := Result + DoNamePartText(AParts[LI]);
  end;
end;

function DoExprListText(const AExprs: TList<TPCExpr>): string;
var
  LI: Integer;
begin
  Result := '';
  for LI := 0 to AExprs.Count - 1 do
  begin
    if LI > 0 then
      Result := Result + ', ';
    Result := Result + DoExprTextOf(AExprs[LI]);
  end;
end;

function DoOperandText(const AExpr: TPCExpr; const AMinPower: Integer): string;
begin
  // The AST keeps no parentheses: an operand binding looser than its slot
  // needs them back, so the text means what the tree means
  if AExpr = nil then
    Exit('error');
  Result := AExpr.ExprText();
  if AExpr.ExprPower() < AMinPower then
    Result := '(' + Result + ')';
end;

function DoPrefixText(const AOp: string; const AOperand: string): string;
begin
  // '- -1', '& &x': a symbol is spaced from an operand that starts with its
  // own last character, which would otherwise read as one token
  if (AOperand <> '') and (AOp <> '') and (AOperand[1] = AOp[Length(AOp)]) then
    Result := AOp + ' ' + AOperand
  else
    Result := AOp + AOperand;
end;

{ TPCDerivedType }

constructor TPCDerivedType.Create();
begin
  inherited;

  FNodeKind := nkDerivedType;
end;

function TPCDerivedType.DoDumpText(): string;
begin
  Result := GetEnumName(TypeInfo(TPCDerivedKind), Ord(DerivedKind));
  DoAddWord(Result, DoFlagText(IsConstTarget, 'const'));
  // Target is a reference, named on this line, never walked
  if Target <> nil then
    DoAddWord(Result, 'target=' + QuoteText(Target.TypeText()));
end;

function TPCDerivedType.TypeText(): string;
begin
  if DerivedKind = dkSetOf then
    Exit('set of ' + DoTypeTextOf(Target));
  if Target = nil then
    Exit('ptr');
  Result := 'ptr to ';
  if IsConstTarget then
    Result := Result + 'const ';
  Result := Result + Target.TypeText();
end;

{ TPCParam }

constructor TPCParam.Create();
begin
  inherited;

  FNodeKind := nkParam;
end;

function TPCParam.DoDumpText(): string;
begin
  Result := QuoteText(ParamName);
  if ParamMode <> pmNone then
    DoAddWord(Result, GetEnumName(TypeInfo(TPCParamMode), Ord(ParamMode)));
end;

procedure TPCParam.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  // PLAN-OBJECT O9: a write's parameter type is its property's node
  if not IsTypeBorrowed then
    VisitNode(TypeExpr, AVisit);
end;

{ TPCVarDecl }

constructor TPCVarDecl.Create();
begin
  inherited;

  FNodeKind := nkVarDecl;
end;

function TPCVarDecl.DoDumpText(): string;
begin
  Result := inherited DoDumpText();
  DoAddWord(Result, DoExternalText(ExternalClause));
end;

function TPCVarDecl.DoDumpResolved(): string;
begin
  Result := inherited DoDumpResolved() + DoLibText(ExternalClause);
end;

procedure TPCVarDecl.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(TypeExpr, AVisit);
  VisitNode(InitExpr, AVisit);
  VisitNode(InitCall, AVisit);
end;

{ TPCConstDecl }

constructor TPCConstDecl.Create();
begin
  inherited;

  FNodeKind := nkConstDecl;
end;

procedure TPCConstDecl.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(TypeExpr, AVisit);
  VisitNode(ValueExpr, AVisit);
end;

function TPCConstDecl.HasConstText(out AWide: Boolean): Boolean;
var
  LCanon: TPCTypeExpr;
  LLiteral: TPCLiteral;
  LPrefix: TPCLiteralPrefix;
  LPart: TPCLiteralPart;
begin
  // The const's type decides the form (string or wstring); every part of the
  // literal must be that form's array (no u8 / u / U part: another character
  // type; no suffix: "x"s is already a std::string)
  Result := False;
  AWide := False;
  if (TypeExpr = nil) or not (ValueExpr is TPCLiteral) then
    Exit;
  LLiteral := TPCLiteral(ValueExpr);
  if (LLiteral.LiteralKind <> lkString) or (Length(LLiteral.Parts) = 0) then
    Exit;
  LCanon := TypeExpr.Canon();
  if not (LCanon is TPCBuiltinType) then
    Exit;
  if TPCBuiltinType(LCanon).BuiltinToken = tkKwString then
    LPrefix := lpNone
  else if TPCBuiltinType(LCanon).BuiltinToken = tkKwWstring then
    LPrefix := lpUpperL
  else
    Exit;
  for LPart in LLiteral.Parts do
  begin
    if (LPart.LiteralPrefix <> LPrefix) or (LPart.Suffix <> '') then
      Exit;
  end;
  AWide := LPrefix = lpUpperL;
  Result := True;
end;

{ TPCTypeDecl }

constructor TPCTypeDecl.Create();
begin
  inherited;

  FNodeKind := nkTypeDecl;
end;

function TPCTypeDecl.DoDumpText(): string;
begin
  Result := inherited DoDumpText();
  DoAddWord(Result, DoFlagText(IsForward, 'forward'));
end;

function TPCTypeDecl.DoDumpResolved(): string;
begin
  Result := inherited DoDumpResolved();
  if ResolvedFull <> nil then
    Result := Result + ' full=' + DoRefText(ResolvedFull);
end;

procedure TPCTypeDecl.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(TypeDef, AVisit);
end;

{ TPCSignature }

function TPCSignature.Text(): string;
var
  LI: Integer;
  LParam: TPCParam;
  LParams: string;
begin
  // routine clink(AN: int32; var AS: string; ...): bool (BNF.md :234-236, :304);
  // the meant linkage prints only as clink: cpplink is the default (F-R3b)
  Result := 'routine';
  if Linkage = lnC then
    Result := Result + ' clink';
  LParams := '';
  for LI := 0 to Params.Count - 1 do
  begin
    LParam := Params[LI];
    if LI > 0 then
      LParams := LParams + '; ';
    if LParam.ParamMode = pmVar then
      LParams := LParams + 'var '
    else if LParam.ParamMode = pmConst then
      LParams := LParams + 'const ';
    LParams := LParams + LParam.ParamName + ': ' + DoTypeTextOf(LParam.TypeExpr);
  end;
  if IsVariadic then
  begin
    if LParams <> '' then
      LParams := LParams + '; ';
    LParams := LParams + '...';
  end;
  Result := Result + '(' + LParams + ')';
  if ReturnType <> nil then
    Result := Result + ': ' + ReturnType.TypeText();
end;

{ TPCRoutine }

constructor TPCRoutine.Create();
begin
  inherited;

  FNodeKind := nkRoutine;
  Params := TList<TPCParam>.Create();
  Decls := TList<TPCStmt>.Create();
end;

destructor TPCRoutine.Destroy();
begin
  Decls.Free();
  Params.Free();

  inherited;
end;

function TPCRoutine.DoDumpText(): string;
begin
  Result := inherited DoDumpText();
  DoAddWord(Result, GetEnumName(TypeInfo(TPCRoutineKind), Ord(RoutineKind)));
  DoAddWord(Result, DoLinkageText(Linkage));
  DoAddWord(Result, DoFlagText(IsVariadic, 'variadic'));
  DoAddWord(Result, DoFlagText(IsForward, 'forward'));
  DoAddWord(Result, DoFlagText(IsConst, 'const'));
  DoAddWord(Result, DoExternalText(ExternalClause));
end;

function TPCRoutine.DoDumpResolved(): string;
begin
  Result := inherited DoDumpResolved();
  if ResolvedLinkage <> lnNone then
    Result := Result + ' linkage=' + DoLinkageText(ResolvedLinkage);
  Result := Result + DoLibText(ExternalClause);
  if ResolvedFull <> nil then
    Result := Result + ' full=' + DoRefText(ResolvedFull);
end;

procedure TPCRoutine.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCParam>(Params, AVisit);
  // PLAN-OBJECT O9: a read's result type is its property's node (not a child)
  if RoutineKind <> rnRead then
    VisitNode(ReturnType, AVisit);
  VisitList<TPCStmt>(Decls, AVisit);
  VisitNode(Body, AVisit);
end;

function TPCRoutine.MeantLinkage(): TPCLinkage;
begin
  if ResolvedLinkage <> lnNone then
    Exit(ResolvedLinkage);
  if Linkage = lnC then
    Result := lnC
  else
    Result := lnCpp;
end;

function TPCRoutine.Signature(): TPCSignature;
begin
  Result.Linkage := MeantLinkage();
  Result.Params := Params;
  Result.IsVariadic := IsVariadic;
  Result.ReturnType := ReturnType;
end;

{ TPCTemplateArg }

constructor TPCTemplateArg.Create();
begin
  inherited;

  FNodeKind := nkTemplateArg;
end;

function TPCTemplateArg.DoDumpText(): string;
begin
  // A cpp type id prints its text; a type or expression arg is its child line
  Result := '';
  if HasVerbatim then
    Result := GetEnumName(TypeInfo(TPCVerbatimKind), Ord(Verbatim.VerbatimKind)) + ' ' +
      QuoteText(Verbatim.Text);
end;

procedure TPCTemplateArg.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(TypeArg, AVisit);
  VisitNode(ExprArg, AVisit);
end;

{ TPCNamePart }

constructor TPCNamePart.Create();
begin
  inherited;

  FNodeKind := nkNamePart;
  TemplateArgs := TList<TPCTemplateArg>.Create();
end;

destructor TPCNamePart.Destroy();
begin
  TemplateArgs.Free();

  inherited;
end;

function TPCNamePart.DoDumpText(): string;
begin
  Result := QuoteText(PartText);
  DoAddWord(Result, DoFlagText(HasTemplateArgs, 'targs'));
end;

procedure TPCNamePart.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCTemplateArg>(TemplateArgs, AVisit);
end;

{ TPCBuiltinType }

constructor TPCBuiltinType.Create();
begin
  inherited;

  FNodeKind := nkBuiltinType;
end;

function TPCBuiltinType.DoDumpText(): string;
begin
  Result := GetEnumName(TypeInfo(TPCTokenKind), Ord(BuiltinToken));
end;

function TPCBuiltinType.TypeText(): string;
begin
  Result := DoSpellingOf(BuiltinToken);
end;

{ TPCNamedType }

constructor TPCNamedType.Create();
begin
  inherited;

  FNodeKind := nkNamedType;
end;

function TPCNamedType.DoDumpText(): string;
begin
  Result := QuoteText(string.Join('.', Parts));
end;

function TPCNamedType.TypeText(): string;
begin
  Result := string.Join('.', Parts);
end;

function TPCNamedType.DoDumpResolved(): string;
begin
  Result := inherited DoDumpResolved() + DoResolvedText(ResolvedKind, ResolvedDecl);
end;

{ TPCPointerType }

constructor TPCPointerType.Create();
begin
  inherited;

  FNodeKind := nkPointerType;
end;

function TPCPointerType.DoDumpText(): string;
begin
  Result := DoFlagText(IsConstTarget, 'const');
end;

function TPCPointerType.TypeText(): string;
begin
  if TargetType = nil then
    Exit('ptr');
  Result := 'ptr to ';
  if IsConstTarget then
    Result := Result + 'const ';
  Result := Result + TargetType.TypeText();
end;

procedure TPCPointerType.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(TargetType, AVisit);
end;

{ TPCOwnerType }

constructor TPCOwnerType.Create();
begin
  inherited;

  FNodeKind := nkOwnerType;
end;

function TPCOwnerType.DoDumpText(): string;
begin
  Result := PC_CONTEXT_WORDS[PC_OWNER_WORDS[OwnerKind]].WordText;
end;

function TPCOwnerType.TypeText(): string;
begin
  Result := PC_CONTEXT_WORDS[PC_OWNER_WORDS[OwnerKind]].WordText + ' ';
  if TargetType <> nil then
    Result := Result + TargetType.TypeText();
end;

procedure TPCOwnerType.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(TargetType, AVisit);
end;

{ TPCArrayType }

constructor TPCArrayType.Create();
begin
  inherited;

  FNodeKind := nkArrayType;
end;

function TPCArrayType.DoDumpText(): string;
begin
  Result := DoFlagText(IsDynamic, 'dynamic');
end;

function TPCArrayType.TypeText(): string;
begin
  if IsDynamic then
    Exit('array of ' + DoTypeTextOf(ElementType));
  Result := 'array[' + DoBoundText(LowExpr) + '..' + DoBoundText(HighExpr) + '] of ' +
    DoTypeTextOf(ElementType);
end;

procedure TPCArrayType.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(LowExpr, AVisit);
  VisitNode(HighExpr, AVisit);
  VisitNode(ElementType, AVisit);
end;

{ TPCCppType }

constructor TPCCppType.Create();
begin
  inherited;

  FNodeKind := nkCppType;
  NameParts := TList<TPCNamePart>.Create();
end;

destructor TPCCppType.Destroy();
begin
  NameParts.Free();

  inherited;
end;

function TPCCppType.DoDumpText(): string;
var
  LKind: TPCTokenKind;
  LLevel: TPCCvFlags;
begin
  // One word per element in C++ order: lead cv, elaborated key, decltype,
  // fundamentals, leading ::,
  // trailing cv, one word per pointer level (with its cv), the reference.
  // The name parts follow as child lines.
  Result := '';
  if LeadCv <> [] then
    DoAddWord(Result, 'lead=' + DoCvText(LeadCv));
  if HasElaborated then
    DoAddWord(Result, GetEnumName(TypeInfo(TPCTokenKind), Ord(ElaboratedKey)));
  if HasDecltype then
    DoAddWord(Result, QuoteText(Decltype.Text));
  for LKind in Fundamentals do
    DoAddWord(Result, GetEnumName(TypeInfo(TPCTokenKind), Ord(LKind)));
  DoAddWord(Result, DoFlagText(HasLeadingScope, 'scoped'));
  if TrailCv <> [] then
    DoAddWord(Result, 'trail=' + DoCvText(TrailCv));
  for LLevel in PointerLevels do
    DoAddWord(Result, '*' + DoCvText(LLevel));
  if RefKind = rfLValue then
    DoAddWord(Result, '&')
  else if RefKind = rfRValue then
    DoAddWord(Result, '&&');
end;

function TPCCppType.TypeText(): string;
var
  LKind: TPCTokenKind;
  LLevel: TPCCvFlags;
begin
  // C++ order (BNF.md sec 4): lead cv, elaborated key, decltype, fundamentals,
  // name, trail cv; then the pointer levels and the reference, attached:
  // const std::string&, char const* const
  Result := '';
  DoAddWord(Result, DoCvSpelling(LeadCv));
  if HasElaborated then
    DoAddWord(Result, DoSpellingOf(ElaboratedKey));
  if HasDecltype then
    DoAddWord(Result, Decltype.Text);
  for LKind in Fundamentals do
    DoAddWord(Result, DoSpellingOf(LKind));
  if NameParts.Count > 0 then
    DoAddWord(Result, DoNamePartsText(HasLeadingScope, NameParts));
  DoAddWord(Result, DoCvSpelling(TrailCv));
  for LLevel in PointerLevels do
  begin
    Result := Result + '*';
    if LLevel <> [] then
      Result := Result + ' ' + DoCvSpelling(LLevel);
  end;
  if RefKind = rfLValue then
    Result := Result + '&'
  else if RefKind = rfRValue then
    Result := Result + '&&';
end;

procedure TPCCppType.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCNamePart>(NameParts, AVisit);
end;

{ TPCField }

constructor TPCField.Create();
begin
  inherited;

  FNodeKind := nkField;
end;

function TPCField.DoDumpText(): string;
begin
  Result := QuoteText(FieldName);
  if IsEmbed then
    Result := 'embed ' + Result;
end;

procedure TPCField.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(TypeExpr, AVisit);
  VisitNode(BitWidthExpr, AVisit);
end;

function TPCField.IsWCharBitfield(): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // Moved from the emitter's DoEmitField (F25): the field's type through
  // its aliases is the builtin wchar
  Result := False;
  if (BitWidthExpr = nil) or (TypeExpr = nil) then
    Exit;
  LCanon := TypeExpr.Canon();
  Result := (LCanon is TPCBuiltinType) and (TPCBuiltinType(LCanon).BuiltinToken = tkKwWchar);
end;

function TPCField.IsChoicesBitfield(): Boolean;
begin
  // The field's type through its aliases is a choices type (F37)
  Result := False;
  if (BitWidthExpr = nil) or (TypeExpr = nil) then
    Exit;
  Result := TypeExpr.Canon() is TPCChoicesType;
end;

{ TPCAnonAggregate }

constructor TPCAnonAggregate.Create();
begin
  inherited;

  FNodeKind := nkAnonAggregate;
  Members := TList<TPCMemberItem>.Create();
end;

destructor TPCAnonAggregate.Destroy();
begin
  Members.Free();

  inherited;
end;

function TPCAnonAggregate.DoDumpText(): string;
begin
  if IsOverlay then
    Result := 'overlay'
  else
    Result := 'record';
  DoAddWord(Result, DoFlagText(IsPacked, 'packed'));
end;

procedure TPCAnonAggregate.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCMemberItem>(Members, AVisit);
end;

{ TPCRoutineMember }

procedure TPCRoutineMember.SetRoutine(const ARoutine: TPCRoutine);
begin
  FRoutine := ARoutine;
  if FRoutine <> nil then
    FRoutine.OwnerMember := Self;
end;

procedure TPCRoutineMember.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Routine, AVisit);
end;

{ TPCMethodItem }

constructor TPCMethodItem.Create();
begin
  inherited;

  FNodeKind := nkMethodItem;
end;

function TPCMethodItem.IsDispatched(): Boolean;
begin
  Result := IsVirtual or IsOverride;
end;

{ TPCInitItem }

constructor TPCInitItem.Create();
begin
  inherited;

  FNodeKind := nkInitItem;
end;

{ TPCDoneItem }

constructor TPCDoneItem.Create();
begin
  inherited;

  FNodeKind := nkDoneItem;
end;

{ TPCCopyItem }

constructor TPCCopyItem.Create();
begin
  inherited;

  FNodeKind := nkCopyItem;
end;

{ TPCAccessorItem }

constructor TPCAccessorItem.Create();
begin
  inherited;

  FNodeKind := nkAccessorItem;
end;

function TPCAccessorItem.DoDumpText(): string;
begin
  // `read` / `write`, then the bound field's name for a binding
  if IsWrite then
    Result := 'write'
  else
    Result := 'read';
  if IsBinding() then
    DoAddWord(Result, QuoteText(FieldName));
  DoAddWord(Result, DoFlagText(IsHidden, 'hidden'));
end;

function TPCAccessorItem.IsBinding(): Boolean;
begin
  Result := FieldName <> '';
end;

{ TPCOperatorItem }

constructor TPCOperatorItem.Create();
begin
  inherited;

  FNodeKind := nkOperatorItem;
end;

function TPCOperatorItem.DoDumpText(): string;
begin
  // `operator +`, `operator - unary`
  Result := 'operator ' + OpText;
  DoAddWord(Result, DoFlagText(IsUnary(), 'unary'));
end;

function TPCOperatorItem.IsUnary(): Boolean;
begin
  Result := (Op = boSub) and (Routine <> nil) and (Routine.Params.Count = 1);
end;

{ TPCPropertyItem }

constructor TPCPropertyItem.Create();
begin
  inherited;

  FNodeKind := nkPropertyItem;
end;

function TPCPropertyItem.DoDumpText(): string;
begin
  Result := QuoteText(PropName);
  DoAddWord(Result, DoFlagText(IsHidden, 'hidden'));
  DoAddWord(Result, DoFlagText(IsVirtual, 'virtual'));
  DoAddWord(Result, DoFlagText(IsOverride, 'override'));
  DoAddWord(Result, DoFlagText(IsFinal, 'final'));
  DoAddWord(Result, DoFlagText(IsDefault, 'default'));
end;

procedure TPCPropertyItem.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  // In source order: the index parameter, the type (the accessors'
  // signatures borrow both), then read, write
  VisitNode(IndexParam, AVisit);
  VisitNode(TypeExpr, AVisit);
  VisitNode(ReadItem, AVisit);
  VisitNode(WriteItem, AVisit);
end;

function TPCPropertyItem.IsDispatched(): Boolean;
begin
  Result := IsVirtual or IsOverride;
end;

function TPCPropertyItem.ReadsByReference(): Boolean;
begin
  Result := (ReadItem <> nil) and ReadItem.IsBinding() and not IsDispatched();
end;

{ TPCRecordType }

constructor TPCRecordType.Create();
begin
  inherited;

  FNodeKind := nkRecordType;
  Members := TList<TPCMemberItem>.Create();
  Implements := TList<TPCNamedType>.Create();
  ResolvedForwards := TList<TPCMethodItem>.Create();
  ResolvedEmbedForwards := TList<TPCEmbedForward>.Create();
  ResolvedPropertyForwards := TList<TPCPropertyItem>.Create();
end;

destructor TPCRecordType.Destroy();
begin
  ResolvedPropertyForwards.Free();
  ResolvedEmbedForwards.Free();
  ResolvedForwards.Free();
  Implements.Free();
  Members.Free();

  inherited;
end;

function TPCRecordType.DoDumpText(): string;
begin
  if IsInterface then
    Result := 'interface'
  else if IsObject then
    Result := 'object'
  else
    Result := 'record';
  DoAddWord(Result, DoFlagText(IsPacked, 'packed'));
end;

function TPCRecordType.TypeText(): string;
begin
  // An anonymous definition: a message names the user's type, never its Canon
  if IsInterface then
    Result := 'interface'
  else if IsObject then
    Result := 'object'
  else
    Result := 'record';
end;

function TPCRecordType.PolymorphismIsClangs(): Boolean;
begin
  // SEM's facts (DoResolveDispatch): a PaskalCPP vtable is known; one a
  // C/C++ base may bring is not
  Result := IsObject and ResolvedDerivesFromCpp and not ResolvedIsPolymorphic;
end;

function TPCRecordType.HasParentMember(): Boolean;
var
  LParent: TPCTypeExpr;
begin
  // A record's parent is a record (SM0308 otherwise); an object keeps its
  // C++ base class, a C/C++ parent stays a base class (F20: its members are
  // clang's), a forward with no full stops at its name (Canon)
  Result := False;
  if IsObject or (ParentName = nil) then
    Exit;
  LParent := ParentName.Canon();
  Result := (LParent is TPCRecordType) and not TPCRecordType(LParent).IsObject;
end;

function TPCRecordType.ParentRecord(): TPCRecordType;
begin
  if HasParentMember() then
    Result := TPCRecordType(ParentName.Canon())
  else
    Result := nil;
end;

function TPCRecordType.ParentPartMayBeMisaligned(const AHops: Integer): Boolean;
var
  LLevel: TPCRecordType;
  LHop: Integer;
  LPacked: Boolean;
begin
  // Every level's parent sits at offset 0 of it (M10), so the part AHops up
  // starts at this record's address: it is aligned unless a level on the
  // way is packed (that level aligns to 1) and the part needs more than 1.
  // A part aligns to 1 when it is packed with no align clause (PaskalCPP's
  // packed rule, M9) or SEM knows its natural alignment is 1. A chain
  // shorter than AHops: False (no such part)
  Result := False;
  LPacked := False;
  LLevel := Self;
  for LHop := 1 to AHops do
  begin
    if LLevel = nil then
      Exit;
    if LLevel.IsPacked then
      LPacked := True;
    LLevel := LLevel.ParentRecord();
  end;
  if (LLevel = nil) or not LPacked then
    Exit;
  if LLevel.AlignExpr <> nil then
    Exit(True);
  if LLevel.IsPacked then
    Exit(False);
  Result := not (LLevel.IsNaturalAlignComputed and (LLevel.ResolvedNaturalAlign = 1));
end;

function TPCRecordType.OwnDone(): TPCDoneItem;
var
  LItem: TPCMemberItem;
begin
  Result := nil;
  for LItem in Members do
  begin
    if LItem is TPCDoneItem then
      Exit(TPCDoneItem(LItem));
  end;
end;

function TPCRecordType.OwnCopy(): TPCCopyItem;
var
  LItem: TPCMemberItem;
begin
  Result := nil;
  for LItem in Members do
  begin
    if LItem is TPCCopyItem then
      Exit(TPCCopyItem(LItem));
  end;
end;

{ MoveOnlyReasonIn }
// TPCRecordType.MoveOnlyReason / TPCTypeExpr.MoveOnlyReasonOf with the
// records being asked (a dynamic array field may hold its own type: the
// outer level decides, a level asked again answers nil)
function MoveOnlyReasonIn(const AType: TPCTypeExpr; const AVisiting: TList<TPCRecordType>): TPCNode;
var
  LCanon: TPCTypeExpr;
  LRecord: TPCRecordType;
  LItem: TPCMemberItem;
  LDone: TPCDoneItem;
begin
  Result := nil;
  if (AType = nil) or TPCTypeExpr.IsOpaqueTier(AType) then
    Exit;
  LCanon := AType.Canon();
  if LCanon is TPCArrayType then
    Exit(MoveOnlyReasonIn(TPCArrayType(LCanon).ElementType, AVisiting));
  // PLAN-OBJECT O6 (D5): an own is the sole owner of its object: it moves,
  // never copies (ref copies, weak copies)
  if LCanon is TPCOwnerType then
  begin
    if TPCOwnerType(LCanon).OwnerKind = okOwn then
      Exit(LCanon);
    Exit;
  end;
  if not (LCanon is TPCRecordType) then
    Exit;
  LRecord := TPCRecordType(LCanon);
  if not LRecord.IsObject or AVisiting.Contains(LRecord) then
    Exit;
  // A copy of its own builds every part: the type can be copied (a parent
  // that cannot be copied is SEM's SM0355 there)
  if LRecord.OwnCopy() <> nil then
    Exit;
  LDone := LRecord.OwnDone();
  if LDone <> nil then
    Exit(LDone);
  AVisiting.Add(LRecord);
  try
    if (LRecord.ParentName <> nil) and (MoveOnlyReasonIn(LRecord.ParentName, AVisiting) <> nil) then
      Exit(LRecord.ParentName);
    for LItem in LRecord.Members do
    begin
      if (LItem is TPCField) and (MoveOnlyReasonIn(TPCField(LItem).TypeExpr, AVisiting) <> nil) then
        Exit(LItem);
    end;
  finally
    AVisiting.Remove(LRecord);
  end;
end;

function TPCRecordType.MoveOnlyReason(): TPCNode;
var
  LVisiting: TList<TPCRecordType>;
begin
  LVisiting := TList<TPCRecordType>.Create();
  try
    Result := MoveOnlyReasonIn(Self, LVisiting);
  finally
    LVisiting.Free();
  end;
end;

procedure TPCRecordType.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(ParentName, AVisit);
  VisitList<TPCNamedType>(Implements, AVisit);
  VisitNode(AlignExpr, AVisit);
  VisitList<TPCMemberItem>(Members, AVisit);
end;

{ TPCTypeExpr }

class function TPCTypeExpr.MoveOnlyReasonOf(const AType: TPCTypeExpr): TPCNode;
var
  LVisiting: TList<TPCRecordType>;
begin
  LVisiting := TList<TPCRecordType>.Create();
  try
    Result := MoveOnlyReasonIn(AType, LVisiting);
  finally
    LVisiting.Free();
  end;
end;

{ TPCOverlayType }

constructor TPCOverlayType.Create();
begin
  inherited;

  FNodeKind := nkOverlayType;
  Members := TList<TPCMemberItem>.Create();
end;

destructor TPCOverlayType.Destroy();
begin
  Members.Free();

  inherited;
end;

procedure TPCOverlayType.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCMemberItem>(Members, AVisit);
end;

function TPCOverlayType.TypeText(): string;
begin
  Result := 'overlay';
end;

{ TPCChoiceValue }

constructor TPCChoiceValue.Create();
begin
  inherited;

  FNodeKind := nkChoiceValue;
end;

function TPCChoiceValue.DoDumpText(): string;
begin
  Result := QuoteText(ValueName);
end;

function TPCChoiceValue.DoDumpResolved(): string;
begin
  Result := inherited DoDumpResolved();
  if HasResolvedOrdinal then
    Result := Result + ' ordinal=' + IntToStr(ResolvedOrdinal);
end;

procedure TPCChoiceValue.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(ValueExpr, AVisit);
end;

{ TPCChoicesType }

constructor TPCChoicesType.Create();
begin
  inherited;

  FNodeKind := nkChoicesType;
  Values := TList<TPCChoiceValue>.Create();
end;

destructor TPCChoicesType.Destroy();
begin
  Values.Free();

  inherited;
end;

procedure TPCChoicesType.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCChoiceValue>(Values, AVisit);
end;

function TPCChoicesType.TypeText(): string;
begin
  Result := 'choices';
end;

function TPCChoicesType.UnderlyingBits(): Integer;
var
  LValue: TPCChoiceValue;
begin
  // A value without a resolved ordinal (a reported one) claims nothing
  Result := 32;
  for LValue in Values do
  begin
    if (LValue <> nil) and LValue.HasResolvedOrdinal and
      ((LValue.ResolvedOrdinal < Low(Int32)) or (LValue.ResolvedOrdinal > High(Int32))) then
      Exit(64);
  end;
end;

{ TPCSetType }

constructor TPCSetType.Create();
begin
  inherited;

  FNodeKind := nkSetType;
end;

function TPCSetType.DoDumpText(): string;
begin
  Result := DoFlagText(IsRangeForm, 'range');
end;

function TPCSetType.TypeText(): string;
begin
  if IsRangeForm then
    Result := 'set of ' + DoBoundText(LowExpr) + '..' + DoBoundText(HighExpr)
  else
    Result := 'set of ' + DoTypeTextOf(ElementType);
end;

procedure TPCSetType.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(ElementType, AVisit);
  VisitNode(LowExpr, AVisit);
  VisitNode(HighExpr, AVisit);
end;

{ TPCRoutineType }

constructor TPCRoutineType.Create();
begin
  inherited;

  FNodeKind := nkRoutineType;
  Params := TList<TPCParam>.Create();
end;

destructor TPCRoutineType.Destroy();
begin
  Params.Free();

  inherited;
end;

function TPCRoutineType.DoDumpText(): string;
begin
  Result := DoLinkageText(Linkage);
  DoAddWord(Result, DoFlagText(IsVariadic, 'variadic'));
end;

function TPCRoutineType.TypeText(): string;
begin
  // One spelling rule for a routine type and a routine's signature
  // (TPCSignature.Text, PLAN-RECORDS R5)
  Result := Signature().Text();
end;

function TPCRoutineType.MeantLinkage(): TPCLinkage;
begin
  if Linkage = lnC then
    Result := lnC
  else
    Result := lnCpp;
end;

function TPCRoutineType.Signature(): TPCSignature;
begin
  Result.Linkage := MeantLinkage();
  Result.Params := Params;
  Result.IsVariadic := IsVariadic;
  Result.ReturnType := ReturnType;
end;

procedure TPCRoutineType.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCParam>(Params, AVisit);
  VisitNode(ReturnType, AVisit);
end;

{ TPCIf }

constructor TPCIf.Create();
begin
  inherited;

  FNodeKind := nkIf;
  ThenStmts := TList<TPCStmt>.Create();
  ElseStmts := TList<TPCStmt>.Create();
end;

destructor TPCIf.Destroy();
begin
  ElseStmts.Free();
  ThenStmts.Free();

  inherited;
end;

function TPCIf.DoDumpText(): string;
begin
  // Counts: the then and else statements are otherwise indistinguishable
  Result := DoCountText('then', ThenStmts.Count);
  if HasElse then
    DoAddWord(Result, DoCountText('else', ElseStmts.Count));
end;

procedure TPCIf.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Condition, AVisit);
  VisitList<TPCStmt>(ThenStmts, AVisit);
  VisitList<TPCStmt>(ElseStmts, AVisit);
end;

{ TPCWhile }

constructor TPCWhile.Create();
begin
  inherited;

  FNodeKind := nkWhile;
  Stmts := TList<TPCStmt>.Create();
end;

destructor TPCWhile.Destroy();
begin
  Stmts.Free();

  inherited;
end;

procedure TPCWhile.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Condition, AVisit);
  VisitList<TPCStmt>(Stmts, AVisit);
end;

{ TPCFor }

constructor TPCFor.Create();
begin
  inherited;

  FNodeKind := nkFor;
  Stmts := TList<TPCStmt>.Create();
end;

destructor TPCFor.Destroy();
begin
  Stmts.Free();

  inherited;
end;

function TPCFor.DoDumpText(): string;
begin
  Result := QuoteText(IteratorName);
  if IsDownTo then
    DoAddWord(Result, 'downto')
  else
    DoAddWord(Result, 'to');
end;

function TPCFor.DoDumpResolved(): string;
begin
  Result := inherited DoDumpResolved();
  if ResolvedIterator <> nil then
    Result := Result + ' iter=' + DoRefText(ResolvedIterator);
end;

procedure TPCFor.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(StartExpr, AVisit);
  VisitNode(EndExpr, AVisit);
  VisitList<TPCStmt>(Stmts, AVisit);
end;

{ TPCRepeat }

constructor TPCRepeat.Create();
begin
  inherited;

  FNodeKind := nkRepeat;
  Stmts := TList<TPCStmt>.Create();
end;

destructor TPCRepeat.Destroy();
begin
  Stmts.Free();

  inherited;
end;

procedure TPCRepeat.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCStmt>(Stmts, AVisit);
  VisitNode(Condition, AVisit);
end;

{ TPCMatchLabel }

constructor TPCMatchLabel.Create();
begin
  inherited;

  FNodeKind := nkMatchLabel;
end;

procedure TPCMatchLabel.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(LowExpr, AVisit);
  VisitNode(HighExpr, AVisit);
end;

{ TPCMatchArm }

constructor TPCMatchArm.Create();
begin
  inherited;

  FNodeKind := nkMatchArm;
  Labels := TList<TPCMatchLabel>.Create();
  Stmts := TList<TPCStmt>.Create();
end;

destructor TPCMatchArm.Destroy();
begin
  Stmts.Free();
  Labels.Free();

  inherited;
end;

procedure TPCMatchArm.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCMatchLabel>(Labels, AVisit);
  VisitList<TPCStmt>(Stmts, AVisit);
end;

{ TPCMatch }

constructor TPCMatch.Create();
begin
  inherited;

  FNodeKind := nkMatch;
  Arms := TList<TPCMatchArm>.Create();
  ElseStmts := TList<TPCStmt>.Create();
end;

destructor TPCMatch.Destroy();
begin
  ElseStmts.Free();
  Arms.Free();

  inherited;
end;

function TPCMatch.DoDumpText(): string;
begin
  Result := '';
  if HasElse then
    Result := DoCountText('else', ElseStmts.Count);
end;

procedure TPCMatch.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Subject, AVisit);
  VisitList<TPCMatchArm>(Arms, AVisit);
  VisitList<TPCStmt>(ElseStmts, AVisit);
end;

{ TPCGuard }

constructor TPCGuard.Create();
begin
  inherited;

  FNodeKind := nkGuard;
  GuardStmts := TList<TPCStmt>.Create();
  ExceptStmts := TList<TPCStmt>.Create();
  FinallyStmts := TList<TPCStmt>.Create();
end;

destructor TPCGuard.Destroy();
begin
  FinallyStmts.Free();
  ExceptStmts.Free();
  GuardStmts.Free();

  inherited;
end;

function TPCGuard.DoDumpText(): string;
begin
  Result := DoCountText('guard', GuardStmts.Count);
  if HasExcept then
    DoAddWord(Result, DoCountText('except', ExceptStmts.Count));
  if HasFinally then
    DoAddWord(Result, DoCountText('finally', FinallyStmts.Count));
end;

function TPCGuard.DoDumpResolved(): string;
var
  LEscape: TPCGuardEscape;
  LNames: string;
begin
  Result := inherited DoDumpResolved();
  if ResolvedEscapes = [] then
    Exit;
  LNames := '';
  for LEscape := Low(TPCGuardEscape) to High(TPCGuardEscape) do
  begin
    if not (LEscape in ResolvedEscapes) then
      Continue;
    if LNames <> '' then
      LNames := LNames + ',';
    LNames := LNames + GetEnumName(TypeInfo(TPCGuardEscape), Ord(LEscape));
  end;
  Result := Result + ' escapes=' + LNames;
end;

procedure TPCGuard.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCStmt>(GuardStmts, AVisit);
  VisitList<TPCStmt>(ExceptStmts, AVisit);
  VisitList<TPCStmt>(FinallyStmts, AVisit);
end;

{ TPCReturn }

constructor TPCReturn.Create();
begin
  inherited;

  FNodeKind := nkReturn;
end;

procedure TPCReturn.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(ValueExpr, AVisit);
end;

function TPCReturn.DoDumpResolved(): string;
begin
  Result := inherited DoDumpResolved();
  if ResolvedRoutine <> nil then
    Result := Result + ' routine=' + DoRefText(ResolvedRoutine);
end;

{ TPCLeave }

constructor TPCLeave.Create();
begin
  inherited;

  FNodeKind := nkLeave;
end;

function TPCLeave.DoDumpResolved(): string;
begin
  Result := inherited DoDumpResolved();
  if ResolvedJumpTarget <> nil then
    Result := Result + ' jump=' + DoRefText(ResolvedJumpTarget);
end;

{ TPCSkip }

constructor TPCSkip.Create();
begin
  inherited;

  FNodeKind := nkSkip;
end;

function TPCSkip.DoDumpResolved(): string;
begin
  Result := inherited DoDumpResolved();
  if ResolvedJumpTarget <> nil then
    Result := Result + ' jump=' + DoRefText(ResolvedJumpTarget);
end;

{ TPCExprStmt }

constructor TPCExprStmt.Create();
begin
  inherited;

  FNodeKind := nkExprStmt;
end;

procedure TPCExprStmt.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Expr, AVisit);
end;

{ TPCAssign }

constructor TPCAssign.Create();
begin
  inherited;

  FNodeKind := nkAssign;
end;

function TPCAssign.DoDumpText(): string;
begin
  Result := GetEnumName(TypeInfo(TPCAssignOp), Ord(Op));
end;

procedure TPCAssign.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Target, AVisit);
  VisitNode(ValueExpr, AVisit);
end;

function TPCAssign.ExprText(): string;
begin
  // Right associative: the target binds tighter than the assignment
  Result := DoOperandText(Target, EXPR_POWER_ASSIGN + 1) + ' ' + OpText() + ' ' +
    DoOperandText(ValueExpr, EXPR_POWER_ASSIGN);
end;

function TPCAssign.ExprPower(): Integer;
begin
  Result := EXPR_POWER_ASSIGN;
end;

function TPCAssign.OpText(): string;
begin
  Result := ASSIGN_OP_TEXT[Op];
end;

{ TPCTernary }

constructor TPCTernary.Create();
begin
  inherited;

  FNodeKind := nkTernary;
end;

procedure TPCTernary.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Condition, AVisit);
  VisitNode(ThenExpr, AVisit);
  VisitNode(ElseExpr, AVisit);
end;

function TPCTernary.ExprText(): string;
begin
  Result := DoOperandText(Condition, EXPR_POWER_TERNARY + 1) + ' ? ' +
    DoOperandText(ThenExpr, EXPR_POWER_ASSIGN) + ' : ' +
    DoOperandText(ElseExpr, EXPR_POWER_TERNARY);
end;

function TPCTernary.ExprPower(): Integer;
begin
  Result := EXPR_POWER_TERNARY;
end;

{ TPCBinary }

constructor TPCBinary.Create();
begin
  inherited;

  FNodeKind := nkBinary;
end;

function TPCBinary.DoDumpText(): string;
begin
  Result := GetEnumName(TypeInfo(TPCBinaryOp), Ord(Op));
end;

procedure TPCBinary.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Left, AVisit);
  VisitNode(Right, AVisit);
end;

function TPCBinary.ExprText(): string;
var
  LPower: Integer;
  LLeftMin: Integer;
begin
  // Left associative; a relational operator does not chain, so its left
  // operand needs a tighter power too (a = b) = c
  LPower := BINARY_OP_POWER[Op];
  LLeftMin := LPower;
  if LPower = 10 then
    LLeftMin := LPower + 1;
  Result := DoOperandText(Left, LLeftMin) + ' ' + BINARY_OP_TEXT[Op] + ' ' +
    DoOperandText(Right, LPower + 1);
end;

function TPCBinary.ExprPower(): Integer;
begin
  Result := BINARY_OP_POWER[Op];
end;

{ TPCUnary }

constructor TPCUnary.Create();
begin
  inherited;

  FNodeKind := nkUnary;
end;

function TPCUnary.DoDumpText(): string;
begin
  Result := GetEnumName(TypeInfo(TPCUnaryOp), Ord(Op));
end;

procedure TPCUnary.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Operand, AVisit);
end;

function TPCUnary.ExprText(): string;
begin
  // uoDeref covers prefix * and postfix ^: spelled ^ (BNF.md :485)
  if Op = uoDeref then
    Exit(DoOperandText(Operand, EXPR_POWER_DEREF) + '^');
  if Op = uoPostInc then
    Exit(DoOperandText(Operand, EXPR_POWER_POSTFIX) + '++');
  if Op = uoPostDec then
    Exit(DoOperandText(Operand, EXPR_POWER_POSTFIX) + '--');
  if Op = uoLogNot then
    Exit('not ' + DoOperandText(Operand, EXPR_POWER_PREFIX));
  if Op = uoBitNot then
    Exit(DoPrefixText('~', DoOperandText(Operand, EXPR_POWER_PREFIX)));
  if Op = uoNegate then
    Exit(DoPrefixText('-', DoOperandText(Operand, EXPR_POWER_PREFIX)));
  if Op = uoPlus then
    Exit(DoPrefixText('+', DoOperandText(Operand, EXPR_POWER_PREFIX)));
  // address of and & are one operator: spelled address of, the PaskalCPP
  // form (BNF.md prefix op), as not and ^ are (F-R4a: a hint printed &GE)
  if Op = uoAddressOf then
    Exit('address of ' + DoOperandText(Operand, EXPR_POWER_PREFIX));
  if Op = uoPreInc then
    Exit(DoPrefixText('++', DoOperandText(Operand, EXPR_POWER_PREFIX)));
  Result := DoPrefixText('--', DoOperandText(Operand, EXPR_POWER_PREFIX));
end;

function TPCUnary.ExprPower(): Integer;
begin
  if Op = uoDeref then
    Result := EXPR_POWER_DEREF
  else if (Op = uoPostInc) or (Op = uoPostDec) then
    Result := EXPR_POWER_POSTFIX
  else
    Result := EXPR_POWER_PREFIX;
end;

{ TPCCall }

constructor TPCCall.Create();
begin
  inherited;

  FNodeKind := nkCall;
  Args := TList<TPCExpr>.Create();
  ResolvedCandidates := TList<TPCRoutine>.Create();
end;

destructor TPCCall.Destroy();
begin
  ResolvedCandidates.Free();
  Args.Free();

  inherited;
end;

function TPCCall.DoDumpText(): string;
begin
  // typearg@N only when the type argument is not first: size(T) dumps unchanged
  Result := '';
  if (TypeArg <> nil) and (TypeArgIndex > 0) then
    Result := 'typearg@' + IntToStr(TypeArgIndex);
end;

function TPCCall.DoDumpResolved(): string;
begin
  Result := inherited DoDumpResolved() + DoResolvedText(ResolvedKind, ResolvedDecl);
  if IntrinsicKind <> ikNone then
    Result := Result + ' intrinsic=' + GetEnumName(TypeInfo(TPCIntrinsicKind), Ord(IntrinsicKind));
  if ResolvedInTest then
    Result := Result + ' intest';
  if ResolvedCandidates.Count > 0 then
    Result := Result + ' candidates=' + IntToStr(ResolvedCandidates.Count);
end;

procedure TPCCall.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Callee, AVisit);
  VisitNode(TypeArg, AVisit);
  VisitList<TPCExpr>(Args, AVisit);
end;

function TPCCall.TargetRoutine(): TPCRoutine;
begin
  // Moved from TPCEmitter.DoCallTarget (H2: the members of an overload set
  // share their variadic linkage facts, so any member answers for the set)
  if ResolvedDecl is TPCRoutine then
    Result := TPCRoutine(ResolvedDecl)
  else if (Callee is TPCName) and (TPCName(Callee).ResolvedSetMember <> nil) then
    Result := TPCName(Callee).ResolvedSetMember
  else
    Result := nil;
end;

function TPCCall.ExprText(): string;
var
  LArgs: string;
  LCount: Integer;
  LI: Integer;
begin
  // The arguments in written order, TypeArg at TypeArgIndex (size(T): 0,
  // get(I, T): 1); slot Args.Count is the place after the last expression
  LArgs := '';
  LCount := 0;
  for LI := 0 to Args.Count do
  begin
    if (TypeArg <> nil) and (LI = TypeArgIndex) then
    begin
      if LCount > 0 then
        LArgs := LArgs + ', ';
      LArgs := LArgs + TypeArg.TypeText();
      Inc(LCount);
    end;
    if LI < Args.Count then
    begin
      if LCount > 0 then
        LArgs := LArgs + ', ';
      LArgs := LArgs + DoExprTextOf(Args[LI]);
      Inc(LCount);
    end;
  end;
  // A construction's argument list has no callee (TPCVarDecl.InitCall)
  if Callee = nil then
    Result := '(' + LArgs + ')'
  else
    Result := DoOperandText(Callee, EXPR_POWER_CALL) + '(' + LArgs + ')';
end;

function TPCCall.ExprPower(): Integer;
begin
  Result := EXPR_POWER_CALL;
end;

{ TPCIndex }

constructor TPCIndex.Create();
begin
  inherited;

  FNodeKind := nkIndex;
end;

procedure TPCIndex.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Base, AVisit);
  VisitNode(IndexExpr, AVisit);
end;

function TPCIndex.ExprText(): string;
begin
  Result := DoOperandText(Base, EXPR_POWER_POSTFIX) + '[' + DoExprTextOf(IndexExpr) + ']';
end;

function TPCIndex.ExprPower(): Integer;
begin
  Result := EXPR_POWER_POSTFIX;
end;

{ TPCMember }

constructor TPCMember.Create();
begin
  inherited;

  FNodeKind := nkMember;
  ResolvedVarargs := vaPlain;
end;

function TPCMember.DoDumpText(): string;
begin
  Result := GetEnumName(TypeInfo(TPCMemberAccess), Ord(Access));
end;

function TPCMember.DoDumpResolved(): string;
var
  LEmbed: TPCField;
  LPath: string;
begin
  Result := inherited DoDumpResolved() + DoResolvedText(ResolvedKind, ResolvedDecl);
  // PLAN-OBJECT O8: the embeds a promoted member is reached through
  if Length(ResolvedEmbedPath) = 0 then
    Exit;
  LPath := '';
  for LEmbed in ResolvedEmbedPath do
  begin
    if LPath <> '' then
      LPath := LPath + '.';
    LPath := LPath + LEmbed.FieldName;
  end;
  Result := Result + ' via ' + LPath;
end;

procedure TPCMember.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Base, AVisit);
  VisitNode(Member, AVisit);
end;

function TPCMember.ExprText(): string;
begin
  Result := DoOperandText(Base, EXPR_POWER_POSTFIX);
  if Access = maArrow then
    Result := Result + '->'
  else
    Result := Result + '.';
  Result := Result + DoNamePartText(Member);
end;

function TPCMember.ExprPower(): Integer;
begin
  Result := EXPR_POWER_POSTFIX;
end;

class function TPCMember.ReadsOwner(const AMember: TPCMember): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  Result := False;
  if (AMember = nil) or (AMember.Access <> maDot) or (AMember.Base = nil) or
    (AMember.Base.ResolvedType = nil) then
    Exit;
  LCanon := AMember.Base.ResolvedType.Canon();
  Result := (LCanon is TPCOwnerType) and (TPCOwnerType(LCanon).OwnerKind <> okWeak);
end;

{ TPCName }

constructor TPCName.Create();
begin
  inherited;

  FNodeKind := nkName;
  Parts := TList<TPCNamePart>.Create();
end;

destructor TPCName.Destroy();
begin
  Parts.Free();

  inherited;
end;

function TPCName.DoDumpText(): string;
begin
  Result := DoFlagText(HasLeadingScope, 'scoped');
end;

function TPCName.DoDumpResolved(): string;
begin
  Result := inherited DoDumpResolved() + DoResolvedText(ResolvedKind, ResolvedDecl);
end;

procedure TPCName.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCNamePart>(Parts, AVisit);
end;

function TPCName.ExprText(): string;
begin
  Result := DoNamePartsText(HasLeadingScope, Parts);
end;

{ TPCSpecial }

constructor TPCSpecial.Create();
begin
  inherited;

  FNodeKind := nkSpecial;
end;

function TPCSpecial.DoDumpText(): string;
begin
  Result := GetEnumName(TypeInfo(TPCSpecialKind), Ord(SpecialKind));
end;

function TPCSpecial.ExprText(): string;
begin
  Result := SPECIAL_TEXT[SpecialKind];
end;

{ TPCCast }

constructor TPCCast.Create();
begin
  inherited;

  FNodeKind := nkCast;
end;

function TPCCast.DoDumpText(): string;
begin
  Result := GetEnumName(TypeInfo(TPCCastKind), Ord(CastKind));
end;

procedure TPCCast.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(TargetType, AVisit);
  VisitNode(Operand, AVisit);
end;

function TPCCast.ExprText(): string;
begin
  // int32(x) / ptr to T(x); (T)x; static_cast<T>(x) (BNF.md :508-511, :550-557)
  if CastKind = ckCStyle then
    Exit('(' + DoTypeTextOf(TargetType) + ')' + DoOperandText(Operand, EXPR_POWER_PREFIX));
  if (CastKind = ckBuiltin) or (CastKind = ckPointer) then
    Exit(DoTypeTextOf(TargetType) + '(' + DoExprTextOf(Operand) + ')');
  Result := NAMED_CAST_TEXT[CastKind] + '<' + DoTypeTextOf(TargetType) + '>(' +
    DoExprTextOf(Operand) + ')';
end;

function TPCCast.ExprPower(): Integer;
begin
  if CastKind = ckCStyle then
    Result := EXPR_POWER_PREFIX
  else
    Result := inherited ExprPower();
end;

{ TPCNew }

constructor TPCNew.Create();
begin
  inherited;

  FNodeKind := nkNew;
  Args := TList<TPCExpr>.Create();
end;

destructor TPCNew.Destroy();
begin
  Args.Free();

  inherited;
end;

function TPCNew.DoDumpText(): string;
begin
  Result := GetEnumName(TypeInfo(TPCNewInit), Ord(InitKind));
end;

procedure TPCNew.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(TargetType, AVisit);
  VisitList<TPCExpr>(Args, AVisit);
  VisitNode(SizeExpr, AVisit);
end;

function TPCNew.ExprText(): string;
begin
  Result := 'new ' + DoTypeTextOf(TargetType);
  if InitKind = niArgs then
    Result := Result + '(' + DoExprListText(Args) + ')'
  else if InitKind = niArraySize then
    Result := Result + '[' + DoExprTextOf(SizeExpr) + ']'
  else if InitKind = niBraced then
    Result := Result + '{' + DoExprListText(Args) + '}';
end;

{ TPCOwnerNew }

constructor TPCOwnerNew.Create();
begin
  inherited;

  FNodeKind := nkOwnerNew;
end;

function TPCOwnerNew.DoDumpText(): string;
begin
  Result := DoFlagText(HasArgList, 'args');
end;

procedure TPCOwnerNew.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(OwnerType, AVisit);
  VisitNode(InitCall, AVisit);
end;

function TPCOwnerNew.ExprText(): string;
begin
  Result := DoTypeTextOf(OwnerType);
  if HasArgList and (InitCall <> nil) then
    Result := Result + InitCall.ExprText();
end;

{ TPCTypeTest }

constructor TPCTypeTest.Create();
begin
  inherited;

  FNodeKind := nkTypeTest;
end;

function TPCTypeTest.DoDumpText(): string;
begin
  Result := WordText();
end;

procedure TPCTypeTest.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Operand, AVisit);
  VisitNode(TargetType, AVisit);
end;

function TPCTypeTest.WordText(): string;
begin
  if IsCast then
    Result := 'as'
  else
    Result := 'is';
end;

function TPCTypeTest.ExprText(): string;
var
  LLeftMin: Integer;
begin
  // `is` is relational and does not chain: its operand needs a tighter power
  // (as a comparison's left operand); `as` is left associative at its power
  LLeftMin := ExprPower();
  if not IsCast then
    LLeftMin := LLeftMin + 1;
  Result := DoOperandText(Operand, LLeftMin) + ' ' + WordText() + ' ' + DoTypeTextOf(TargetType);
end;

function TPCTypeTest.ExprPower(): Integer;
begin
  // BNF.md sec 6: `is` at the rel op level, `as` at the mul op level (the
  // parser's PC_INFIX_ROWS powers 10 / 30)
  if IsCast then
    Result := EXPR_POWER_AS
  else
    Result := EXPR_POWER_IS;
end;

{ TPCDelete }

constructor TPCDelete.Create();
begin
  inherited;

  FNodeKind := nkDelete;
end;

function TPCDelete.DoDumpText(): string;
begin
  Result := DoFlagText(IsArray, 'array');
end;

procedure TPCDelete.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Operand, AVisit);
end;

function TPCDelete.ExprText(): string;
begin
  Result := 'delete ';
  if IsArray then
    Result := Result + '[] ';
  Result := Result + DoOperandText(Operand, EXPR_POWER_PREFIX);
end;

function TPCDelete.ExprPower(): Integer;
begin
  Result := EXPR_POWER_PREFIX;
end;

{ TPCBracedInit }

constructor TPCBracedInit.Create();
begin
  inherited;

  FNodeKind := nkBracedInit;
  Args := TList<TPCExpr>.Create();
end;

destructor TPCBracedInit.Destroy();
begin
  Args.Free();

  inherited;
end;

function TPCBracedInit.DoDumpText(): string;
begin
  // Base and Args are both expressions: say when there is no Base
  Result := DoFlagText(Base = nil, 'bare');
end;

procedure TPCBracedInit.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(Base, AVisit);
  VisitList<TPCExpr>(Args, AVisit);
end;

function TPCBracedInit.ExprText(): string;
begin
  Result := '';
  if Base <> nil then
    Result := DoOperandText(Base, EXPR_POWER_POSTFIX);
  Result := Result + '{' + DoExprListText(Args) + '}';
end;

function TPCBracedInit.ExprPower(): Integer;
begin
  if Base <> nil then
    Result := EXPR_POWER_POSTFIX
  else
    Result := inherited ExprPower();
end;

{ TPCSetElement }

constructor TPCSetElement.Create();
begin
  inherited;

  FNodeKind := nkSetElement;
end;

procedure TPCSetElement.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(LowExpr, AVisit);
  VisitNode(HighExpr, AVisit);
end;

{ TPCSetLiteral }

constructor TPCSetLiteral.Create();
begin
  inherited;

  FNodeKind := nkSetLiteral;
  Elements := TList<TPCSetElement>.Create();
end;

destructor TPCSetLiteral.Destroy();
begin
  Elements.Free();

  inherited;
end;

procedure TPCSetLiteral.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitList<TPCSetElement>(Elements, AVisit);
end;

function TPCSetLiteral.ExprText(): string;
var
  LI: Integer;
  LElement: TPCSetElement;
begin
  Result := '[';
  for LI := 0 to Elements.Count - 1 do
  begin
    LElement := Elements[LI];
    if LI > 0 then
      Result := Result + ', ';
    Result := Result + DoExprTextOf(LElement.LowExpr);
    if LElement.HighExpr <> nil then
      Result := Result + '..' + DoExprTextOf(LElement.HighExpr);
  end;
  Result := Result + ']';
end;

{ TPCFieldInit }

constructor TPCFieldInit.Create();
begin
  inherited;

  FNodeKind := nkFieldInit;
end;

function TPCFieldInit.DoDumpText(): string;
begin
  Result := QuoteText(FieldName);
end;

function TPCFieldInit.DoDumpResolved(): string;
begin
  Result := inherited DoDumpResolved();
  if ResolvedField <> nil then
    Result := Result + ' field=' + DoRefText(ResolvedField);
end;

procedure TPCFieldInit.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(ValueExpr, AVisit);
end;

{ TPCRecordLiteral }

constructor TPCRecordLiteral.Create();
begin
  inherited;

  FNodeKind := nkRecordLiteral;
  Inits := TList<TPCFieldInit>.Create();
end;

destructor TPCRecordLiteral.Destroy();
begin
  Inits.Free();

  inherited;
end;

procedure TPCRecordLiteral.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  VisitNode(RecordType, AVisit);
  VisitList<TPCFieldInit>(Inits, AVisit);
end;

function TPCRecordLiteral.ExprText(): string;
var
  LI: Integer;
begin
  Result := DoTypeTextOf(RecordType) + '(';
  for LI := 0 to Inits.Count - 1 do
  begin
    if LI > 0 then
      Result := Result + ', ';
    Result := Result + Inits[LI].FieldName + ': ' + DoExprTextOf(Inits[LI].ValueExpr);
  end;
  Result := Result + ')';
end;

{ TPCVarargs }

constructor TPCVarargs.Create();
begin
  inherited;

  FNodeKind := nkVarargs;
end;

function TPCVarargs.DoDumpText(): string;
begin
  Result := GetEnumName(TypeInfo(TPCVarargsKind), Ord(VarargsKind));
end;

procedure TPCVarargs.EnumChildren(const AVisit: TPCNodeVisitor);
begin
  // written order: get(I, T) visits the index, then the type
  VisitNode(IndexExpr, AVisit);
  VisitNode(ReadType, AVisit);
end;

function TPCVarargs.ExprText(): string;
begin
  case VarargsKind of
    vaCount:
      Result := PC_VARARGS_WORDS[vaPlain] + '.' + PC_VARARGS_WORDS[vaCount];
    vaNext:
      Result := PC_VARARGS_WORDS[vaPlain] + '.' + PC_VARARGS_WORDS[vaNext] + '(' +
        DoTypeTextOf(ReadType) + ')';
    vaGet:
      Result := PC_VARARGS_WORDS[vaPlain] + '.' + PC_VARARGS_WORDS[vaGet] + '(' +
        DoExprTextOf(IndexExpr) + ', ' + DoTypeTextOf(ReadType) + ')';
    vaReset:
      Result := PC_VARARGS_WORDS[vaPlain] + '.' + PC_VARARGS_WORDS[vaReset] + '()';
    vaCopy:
      Result := PC_VARARGS_WORDS[vaPlain] + '.' + PC_VARARGS_WORDS[vaCopy] + '()';
  else
    Result := PC_VARARGS_WORDS[vaPlain];
  end;
end;

{ TPCAst }

constructor TPCAst.Create();
begin
  inherited;

  FNodes := TObjectList<TPCNode>.Create(True);
  FModules := TList<TPCModule>.Create();
  FRejectedModules := TList<TPCModule>.Create();
  FOpaqueType := NewNode<TPCOpaqueType>();
  FErrorType := NewNode<TPCErrorType>();
  FNilType := NewNode<TPCNilType>();
  FVoidType := NewNode<TPCVoidType>();
  FUntypedPointerType := NewNode<TPCPointerType>();
  FStringLiteralType := NewNode<TPCStringLiteralType>();
  FWideStringLiteralType := NewNode<TPCStringLiteralType>();
  FWideStringLiteralType.IsWide := True;
end;

destructor TPCAst.Destroy();
begin
  // FModules holds no ownership; FNodes frees every node, orphans included
  FModules.Free();
  FRejectedModules.Free();
  FNodes.Free();

  inherited;
end;

function TPCAst.NewNodeOf(const AClass: TPCNodeClass): TPCNode;
begin
  // Virtual constructor through the class reference: the class's own Create
  Result := AClass.Create();
  FNodes.Add(Result);
end;

function TPCAst.NewNode<T>(): T;
begin
  // as T: the checked downcast Delphi accepts for a class-constrained T
  Result := NewNodeOf(T.NodeClass()) as T;
end;

function TPCAst.NodeCount(): Integer;
begin
  Result := FNodes.Count;
end;

procedure TPCAst.AddModule(const AModule: TPCModule);
begin
  // The rejected module stays owned by the arena like any other node. A nameless
  // module is never a duplicate: its header error is already reported, and it must
  // still be registered so FindModuleByFile finds it (no re-parse)
  if (AModule.ModuleName <> '') and (FindModule(AModule.ModuleName) <> nil) then
  begin
    FErrors.Add(AModule.Range, esError, PC_ERR_AST_001, RSAstDuplicateModule,
      [AModule.ModuleName]);
    FRejectedModules.Add(AModule);
    Exit;
  end;
  FModules.Add(AModule);
end;

function TPCAst.FindModule(const AModuleName: string): TPCModule;
var
  LModule: TPCModule;
begin
  // Linear walk, exact case (BNF.md:10); no dictionary
  Result := nil;
  for LModule in FModules do
  begin
    if LModule.ModuleName = AModuleName then
      Exit(LModule);
  end;
end;

function TPCAst.ModuleCount(): Integer;
begin
  Result := FModules.Count;
end;

function TPCAst.ModuleAt(const AIndex: Integer): TPCModule;
begin
  Result := FModules[AIndex];
end;

procedure TPCAst.AddLookupPath(const APath: string);
var
  LPath: string;
begin
  // Each path once (TUtils.SamePath: the platform's own case rule)
  if APath = '' then
    Exit;
  for LPath in FLookupPaths do
  begin
    if TUtils.SamePath(LPath, APath) then
      Exit;
  end;
  FLookupPaths := FLookupPaths + [APath];
end;

function TPCAst.LookupPaths(): TArray<string>;
begin
  Result := FLookupPaths;
end;

class function TPCAst.TextNamesRuntime(const AText: string): Boolean;
var
  LPos: Integer;
begin
  // pcpp:: at the text's start or after a character no identifier holds
  // (my_pcpp:: names another scope); conservative on purpose: a false hit
  // ships the runtime library once too often, a miss fails the consumer's link
  LPos := AText.IndexOf(PC_RUNTIME_SPELLING);
  while LPos >= 0 do
  begin
    if LPos = 0 then
      Exit(True);
    if not CharInSet(AText.Chars[LPos - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Exit(True);
    LPos := AText.IndexOf(PC_RUNTIME_SPELLING, LPos + 1);
  end;
  Result := False;
end;

class function TPCAst.DoCallNamesRuntime(const ACall: TPCCall): Boolean;
var
  LIndex: Integer;
  LTarget: TPCRoutine;
begin
  // A runtime intrinsic; print / println with an argument after the format
  // that names the runtime (TPCTypeExpr.PrintForm: ::pcpp::CStr / WCStr /
  // utf8 / print_map; Q11, E4, E7; an address form is a plain cast, an
  // unprintable one is never emitted); a cpplink variadic's packed arguments
  // (::pcpp::Pack / Slot). A conversion (rkType) and every other intrinsic
  // write plain C++
  if ACall.IntrinsicKind in PC_RUNTIME_INTRINSICS then
    Exit(True);
  if (ACall.IntrinsicKind = ikPrint) or (ACall.IntrinsicKind = ikPrintLn) then
  begin
    for LIndex := 1 to ACall.Args.Count - 1 do
    begin
      if TPCTypeExpr.PrintFormOfArg(ACall.Args[LIndex]) in
        [pfCStr, pfWCStr, pfWideChar, pfWideText, pfElements, pfCppChecked] then
        Exit(True);
    end;
    Exit(False);
  end;
  if (ACall.IntrinsicKind <> ikNone) or (ACall.ResolvedKind = rkType) then
    Exit(False);
  // F18: a call limited to some overload members (::pcpp::overloads)
  if ACall.ResolvedCandidates.Count > 0 then
    Exit(True);
  LTarget := ACall.TargetRoutine();
  Result := (LTarget <> nil) and LTarget.IsVariadic and (LTarget.ResolvedLinkage <> lnC);
end;

class function TPCAst.DoMembersNeedPackedCheck(const AMembers: TList<TPCMemberItem>;
  const AInPacked: Boolean): Boolean;
var
  LMember: TPCMemberItem;
  LField: TPCField;
  LAggregate: TPCAnonAggregate;
begin
  // The emitter's DoWritePackedCheck sites, walked as it writes them: a
  // field (no bitfield) packed where it stands whose type is fpClangDecides;
  // an anonymous aggregate inside a packed one, or packed itself, packs too
  Result := False;
  if AMembers = nil then
    Exit;
  for LMember in AMembers do
  begin
    if LMember is TPCField then
    begin
      LField := TPCField(LMember);
      if AInPacked and (LField.BitWidthExpr = nil) and (LField.TypeExpr <> nil) and
        (LField.TypeExpr.FieldPacking() = fpClangDecides) then
        Exit(True);
    end
    else if LMember is TPCAnonAggregate then
    begin
      LAggregate := TPCAnonAggregate(LMember);
      if DoMembersNeedPackedCheck(LAggregate.Members, AInPacked or LAggregate.IsPacked) then
        Exit(True);
    end;
  end;
end;

class function TPCAst.DoMembersNeedOverlayCheck(const AMembers: TList<TPCMemberItem>;
  const AInUnion: Boolean): Boolean;
var
  LMember: TPCMemberItem;
  LField: TPCField;
  LAggregate: TPCAnonAggregate;
begin
  // The emitter's DoWriteOverlayCheck sites (F34), walked as it writes
  // them: a union member field (no bitfield) whose type is ofClangDecides;
  // an anonymous aggregate inside a union, or an overlay itself, is one
  Result := False;
  if AMembers = nil then
    Exit;
  for LMember in AMembers do
  begin
    if LMember is TPCField then
    begin
      LField := TPCField(LMember);
      if AInUnion and (LField.BitWidthExpr = nil) and (LField.TypeExpr <> nil) and
        (LField.TypeExpr.OverlayFit() = ofClangDecides) then
        Exit(True);
    end
    else if LMember is TPCAnonAggregate then
    begin
      LAggregate := TPCAnonAggregate(LMember);
      if DoMembersNeedOverlayCheck(LAggregate.Members, AInUnion or LAggregate.IsOverlay) then
        Exit(True);
    end;
  end;
end;

class function TPCAst.DoNodeNamesRuntime(const ANode: TPCNode): Boolean;
var
  LRoutine: TPCRoutine;
  LWide: Boolean;
begin
  // One row per emitter site that writes ::pcpp:: for the node itself
  // (r10-runtime-use.md); the hooked witness (UTestCase.Emitter DoCheckDir)
  // compares every fixture module with its emitted text, both ways.
  // PLAN-RECORDS M12 (1) / F-A4b: a pointer upcast on any expression
  // (::pcpp::upcast), a downcast (::pcpp::downcast); a ranked call is an
  // overloads call (ResolvedCandidates, DoCallNamesRuntime)
  if (ANode is TPCExpr) and (TPCExpr(ANode).ResolvedUpcastHops > 0) then
    Exit(True);
  if (ANode is TPCCast) and (TPCCast(ANode).ResolvedDowncastHops > 0) then
    Exit(True);
  // PLAN-RECORDS M9: a packed field (or parent) whose type only clang lays
  // out gets the ::pcpp::packs_as_field check (DoWritePackedCheck)
  if (ANode is TPCRecordType) and TPCRecordType(ANode).IsPacked and TPCRecordType(ANode).HasParentMember() and
    (TPCRecordType(ANode).ParentName.FieldPacking() = fpClangDecides) then
    Exit(True);
  if (ANode is TPCRecordType) and DoMembersNeedPackedCheck(TPCRecordType(ANode).Members,
    TPCRecordType(ANode).IsPacked) then
    Exit(True);
  if (ANode is TPCOverlayType) and DoMembersNeedPackedCheck(TPCOverlayType(ANode).Members, False) then
    Exit(True);
  // F34: a union member whose type only clang knows gets the
  // ::pcpp::fits_overlay check (DoWriteOverlayCheck)
  if (ANode is TPCRecordType) and DoMembersNeedOverlayCheck(TPCRecordType(ANode).Members, False) then
    Exit(True);
  if (ANode is TPCOverlayType) and DoMembersNeedOverlayCheck(TPCOverlayType(ANode).Members, True) then
    Exit(True);
  // PLAN-OBJECT O5: an object that declares a done holds ::pcpp::Live
  if (ANode is TPCRecordType) and TPCRecordType(ANode).IsObject and (TPCRecordType(ANode).OwnDone() <> nil) then
    Exit(True);
  if ANode is TPCCall then
    Result := DoCallNamesRuntime(TPCCall(ANode))
  else if ANode is TPCBinary then
    // Div / Mod; a declared operator (PLAN-OBJECT O11) is a plain call
    Result := (TPCBinary(ANode).ResolvedOperator = nil) and
      ((TPCBinary(ANode).Op = boIntDiv) or (TPCBinary(ANode).Op = boMod))
  else if ANode is TPCAssign then
    Result := TPCAssign(ANode).Op = aoModAssign                                   // ModAssign
  else if (ANode is TPCSetType) or (ANode is TPCSetLiteral) or (ANode is TPCGuard) then
    Result := True                    // Set; make_set / EmptySet; guard / Caught / Flow
  else if (ANode is TPCOwnerType) or (ANode is TPCOwnerNew) then
    Result := True                    // PLAN-OBJECT O6: Own / Ref / Weak; make_own / make_ref
  else if ANode is TPCTypeTest then
    Result := True                    // PLAN-OBJECT O12: is_a / as_a
  else if ANode is TPCConstDecl then
    Result := TPCConstDecl(ANode).HasConstText(LWide)                             // ConstText (PLAN-VENDOR 1e)
  else if ANode is TPCLiteral then
    Result := TPCLiteral(ANode).ResolvedToString and TPCLiteral(ANode).HoldsNul() // ConstText, whole length (1e)
  else if ANode is TPCMember then
    Result := TPCMember.ReadsOwner(TPCMember(ANode))                              // deref (O6)
  else if ANode is TPCArrayType then
    Result := not TPCArrayType(ANode).IsDynamic                                   // Array (A8b)
  else if ANode is TPCBuiltinType then
    Result := TPCBuiltinType(ANode).BuiltinToken = tkKwVarargs                    // VarArgs
  else if ANode is TPCRoutine then
  begin
    // cpplink variadic: the VarArgs pack; clink variadic with a body: the
    // Finally that closes its va_list (an external one writes C's ...)
    LRoutine := TPCRoutine(ANode);
    Result := LRoutine.IsVariadic and ((LRoutine.MeantLinkage() <> lnC) or (LRoutine.Body <> nil));
  end
  else if ANode is TPCRoutineType then
    Result := TPCRoutineType(ANode).IsVariadic and (TPCRoutineType(ANode).MeantLinkage() <> lnC)
  else if ANode is TPCVerbatimStmt then
    Result := TextNamesRuntime(TPCVerbatimStmt(ANode).Verbatim.Text)
  else if ANode is TPCVerbatimExpr then
    Result := TextNamesRuntime(TPCVerbatimExpr(ANode).Verbatim.Text)
  else if ANode is TPCTemplateArg then
    Result := TPCTemplateArg(ANode).HasVerbatim and TextNamesRuntime(TPCTemplateArg(ANode).Verbatim.Text)
  else if ANode is TPCCppType then
    Result := TPCCppType(ANode).HasDecltype and TextNamesRuntime(TPCCppType(ANode).Decltype.Text)
  else
    Result := False;
end;

class function TPCAst.DeclaredName(const ANode: TPCNode; out AName: string; out ARange: TSourceRange): Boolean;
begin
  Result := True;
  // PLAN-OBJECT O9: an inline accessor's routine carries its property's name
  // and range; the property declares it (once), the routine declares nothing
  if (ANode is TPCRoutine) and (TPCRoutine(ANode).RoutineKind in [rnRead, rnWrite]) then
  begin
    AName := '';
    ARange := Default(TSourceRange);
    Result := False;
  end
  else if ANode is TPCDecl then
  begin
    AName := TPCDecl(ANode).DeclName;
    ARange := TPCDecl(ANode).NameRange;
  end
  else if ANode is TPCPropertyItem then
  begin
    AName := TPCPropertyItem(ANode).PropName;
    ARange := TPCPropertyItem(ANode).NameRange;
  end
  else if ANode is TPCParam then
  begin
    AName := TPCParam(ANode).ParamName;
    ARange := TPCParam(ANode).NameRange;
  end
  else if ANode is TPCField then
  begin
    AName := TPCField(ANode).FieldName;
    ARange := TPCField(ANode).NameRange;
  end
  else if ANode is TPCChoiceValue then
  begin
    AName := TPCChoiceValue(ANode).ValueName;
    ARange := TPCChoiceValue(ANode).NameRange;
  end
  else if ANode is TPCModule then
  begin
    AName := TPCModule(ANode).ModuleName;
    ARange := TPCModule(ANode).NameRange;
  end
  else
  begin
    AName := '';
    ARange := Default(TSourceRange);
    Result := False;
  end;
end;

class function TPCAst.ModuleNamesRuntime(const AModule: TPCModule): Boolean;
var
  LPending: TList<TPCNode>;
  LNode: TPCNode;
begin
  // A work list, not a self-calling visitor: a reference to procedure that
  // calls itself through a captured variable never frees its frame
  Result := False;
  if AModule = nil then
    Exit;
  LPending := TList<TPCNode>.Create();
  try
    LPending.Add(AModule);
    while LPending.Count > 0 do
    begin
      LNode := LPending[LPending.Count - 1];
      LPending.Delete(LPending.Count - 1);
      // Test mode is the exe's (BNF sec 8): a test block is never compiled
      // into a lib, so it never decides the lib's runtime
      if LNode is TPCTest then
        Continue;
      if DoNodeNamesRuntime(LNode) then
        Exit(True);
      // Only what the emitter writes: a folded type slot is a number there
      EnumWrittenChildren(LNode,
        procedure(const AChild: TPCNode)
        begin
          LPending.Add(AChild);
        end);
    end;
  finally
    LPending.Free();
  end;
end;

class function TPCAst.FoldedText(const AExpr: TPCExpr; out AText: string): Boolean;
begin
  // Moved from TPCEmitter.DoFoldedText (one rule: the emitter and the walks)
  Result := (AExpr <> nil) and AExpr.HasConstValue;
  if not Result then
    AText := ''
  else if AExpr.ConstIsUnsigned then
    AText := UIntToStr(AExpr.ConstUInt)
  else
    AText := IntToStr(AExpr.ConstInt);
end;

class function TPCAst.FoldedCount(const ALow: TPCExpr; const AHigh: TPCExpr; out ACount: string): Boolean;
var
  LLow: Int64;
  LHigh: Int64;
begin
  // Moved from TPCEmitter.DoFoldedCount
  ACount := '';
  if (ALow = nil) or (AHigh = nil) or (not ALow.HasConstValue) or (not AHigh.HasConstValue) then
    Exit(False);
  if ALow.ConstIsUnsigned then
  begin
    if ALow.ConstUInt > UInt64(High(Int64)) then
      Exit(False);
    LLow := Int64(ALow.ConstUInt);
  end
  else
    LLow := ALow.ConstInt;
  if AHigh.ConstIsUnsigned then
  begin
    if AHigh.ConstUInt > UInt64(High(Int64)) then
      Exit(False);
    LHigh := Int64(AHigh.ConstUInt);
  end
  else
    LHigh := AHigh.ConstInt;
  // SEM checked High >= Low; a range whose width does not fit Int64 is left
  // to clang (LLow < 0 keeps High(Int64) + LLow from overflowing)
  if LHigh < LLow then
    Exit(False);
  if (LLow < 0) and (LHigh > High(Int64) + LLow) then
    Exit(False);
  ACount := UIntToStr(UInt64(LHigh - LLow) + 1);
  Result := True;
end;

class function TPCAst.IsNamedPaskalType(const AType: TPCTypeExpr): Boolean;
begin
  // Moved from TPCEmitter.DoIsNamedPaskalType
  Result := (AType is TPCBuiltinType) or
    ((AType is TPCNamedType) and (TPCNamedType(AType).ResolvedKind = rkType) and
    (TPCNamedType(AType).ResolvedDecl <> nil));
end;

class procedure TPCAst.EnumWrittenChildren(const ANode: TPCNode; const AVisit: TPCNodeVisitor);
var
  LText: string;
  LMember: TPCMemberItem;
  LArray: TPCArrayType;
  LSet: TPCSetType;
  LRecord: TPCRecordType;
  LField: TPCField;
  LFace: TPCNamedType;
begin
  if ANode = nil then
    Exit;
  if ANode is TPCArrayType then
  begin
    LArray := TPCArrayType(ANode);
    if (not LArray.IsDynamic) and FoldedCount(LArray.LowExpr, LArray.HighExpr, LText) then
    begin
      TPCNode.VisitNode(LArray.ElementType, AVisit);
      Exit;
    end;
  end
  else if ANode is TPCSetType then
  begin
    LSet := TPCSetType(ANode);
    if LSet.HasResolvedBounds then
    begin
      // The element form writes its element type; the range form its low
      // bound's type by name (that type node, SEM's: the text names it,
      // E5), else decltype of the low bound
      if not LSet.IsRangeForm then
        TPCNode.VisitNode(LSet.ElementType, AVisit)
      else if LSet.LowExpr <> nil then
      begin
        if IsNamedPaskalType(LSet.LowExpr.ResolvedType) then
          TPCNode.VisitNode(LSet.LowExpr.ResolvedType, AVisit)
        else
          TPCNode.VisitNode(LSet.LowExpr, AVisit);
      end;
      Exit;
    end;
  end
  else if ANode is TPCRecordType then
  begin
    LRecord := TPCRecordType(ANode);
    TPCNode.VisitNode(LRecord.ParentName, AVisit);
    // PLAN-OBJECT O7: the bases after implements are written by name
    for LFace in LRecord.Implements do
      TPCNode.VisitNode(LFace, AVisit);
    if not FoldedText(LRecord.AlignExpr, LText) then
      TPCNode.VisitNode(LRecord.AlignExpr, AVisit);
    for LMember in LRecord.Members do
      TPCNode.VisitNode(LMember, AVisit);
    Exit;
  end
  else if ANode is TPCField then
  begin
    LField := TPCField(ANode);
    TPCNode.VisitNode(LField.TypeExpr, AVisit);
    if not FoldedText(LField.BitWidthExpr, LText) then
      TPCNode.VisitNode(LField.BitWidthExpr, AVisit);
    Exit;
  end;
  ANode.EnumChildren(AVisit);
end;

function TPCAst.UsesRuntime(): Boolean;
var
  LModule: TPCModule;
begin
  for LModule in FModules do
  begin
    if LModule.ResolvedUsesRuntime or (LModule.InitRoutine <> nil) or (LModule.FinalRoutine <> nil) then
      Exit(True);
  end;
  Result := False;
end;

function TPCAst.OpaqueType(): TPCOpaqueType;
begin
  Result := FOpaqueType;
end;

function TPCAst.ErrorType(): TPCErrorType;
begin
  Result := FErrorType;
end;

function TPCAst.NilType(): TPCNilType;
begin
  Result := FNilType;
end;

function TPCAst.VoidType(): TPCVoidType;
begin
  Result := FVoidType;
end;

function TPCAst.UntypedPointerType(): TPCPointerType;
begin
  Result := FUntypedPointerType;
end;

function TPCAst.StringLiteralType(const AIsWide: Boolean): TPCStringLiteralType;
begin
  if AIsWide then
    Result := FWideStringLiteralType
  else
    Result := FStringLiteralType;
end;

function TPCAst.BuiltinType(const AToken: TPCTokenKind): TPCBuiltinType;
begin
  if FBuiltinTypes[AToken] = nil then
  begin
    // A builtin is a builtin type word (BNF.md sec 4: a primitive or
    // `varargs`, the one predicate TPCVocabulary.IsBuiltinTypeWord, C9):
    // anything else is a caller defect, not a program error
    if not TPCVocabulary.IsBuiltinTypeWord(AToken) then
      raise EArgumentException.CreateFmt(RSAstNotBuiltinToken,
        [GetEnumName(TypeInfo(TPCTokenKind), Ord(AToken))]);
    FBuiltinTypes[AToken] := NewNode<TPCBuiltinType>();
    FBuiltinTypes[AToken].BuiltinToken := AToken;
  end;
  Result := FBuiltinTypes[AToken];
end;

function TPCAst.FindModuleByFile(const AFilename: string): TPCModule;
var
  LModule: TPCModule;
begin
  // Windows paths: one path in any spelling (slash, case, long-path prefix)
  Result := nil;
  for LModule in FModules do
  begin
    if TUtils.SamePath(LModule.SourceFile, AFilename) then
      Exit(LModule);
  end;
  for LModule in FRejectedModules do
  begin
    if TUtils.SamePath(LModule.SourceFile, AFilename) then
      Exit(LModule);
  end;
end;

class function TPCAst.DoIsByteCopy(const ANode: TPCNode): Boolean;
begin
  // Only verbatim C++ copied byte for byte maps by column offset; vkCppExpr
  // emits its DECODED string, so offsets into it are not source offsets
  Result := False;
  if ANode is TPCVerbatimStmt then
    Result := TPCVerbatimStmt(ANode).Verbatim.VerbatimKind <> vkCppExpr
  else if ANode is TPCVerbatimExpr then
    Result := TPCVerbatimExpr(ANode).Verbatim.VerbatimKind <> vkCppExpr;
end;

class function TPCAst.DoCppExprOf(const ANode: TPCNode; out AVerbatim: TPCVerbatim): Boolean;
begin
  // A cpp("...") node's verbatim, statement or expression form alike
  Result := False;
  AVerbatim := Default(TPCVerbatim);
  if ANode is TPCVerbatimStmt then
    AVerbatim := TPCVerbatimStmt(ANode).Verbatim
  else if ANode is TPCVerbatimExpr then
    AVerbatim := TPCVerbatimExpr(ANode).Verbatim
  else
    Exit;
  Result := AVerbatim.VerbatimKind = vkCppExpr;
end;

class function TPCAst.DoMapValueColumn(const AVerbatim: TPCVerbatim; const ALine: UInt64;
  const AColumn: UInt64; const ASpan: TPCEmitSpan; const AStartColumn: UInt64): UInt64;
var
  LFirstLine: string;
  LBreak: Integer;
  LOffset: Integer;
  LRun: Integer;
  LK: Integer;
begin
  // The emitted value is the decoded string, written by WriteVerbatim with a
  // span of its own (TPCEmitter.DoWriteVerbatimExpr). A later line exists only
  // for a raw string: its bytes are the source line's own (raw: no escapes),
  // written from column 1, so it maps as copied C++ does
  if ALine <> AVerbatim.Range.StartLine then
    Exit(1 + (AColumn - ASpan.StartCol));

  // On the string's own line the narrowest span is the value's unless the
  // column sits on the '(' / ')' the emitter writes around it (the node's
  // whole span): those are not the value's, they map to the node's start
  LFirstLine := AVerbatim.Text;
  LBreak := LFirstLine.IndexOfAny([#13, #10]);
  if LBreak >= 0 then
    LFirstLine := LFirstLine.Substring(0, LBreak);
  if (ASpan.EndCol - ASpan.StartCol) <> UInt64(TEncoding.UTF8.GetByteCount(LFirstLine)) then
    Exit(AStartColumn);

  // The value byte at the column, then the last run that starts at or before
  // it: a copied run maps byte for byte, an escape to its '\' (P-STRPOS)
  LOffset := Integer(AColumn - ASpan.StartCol);
  LRun := 0;
  for LK := 0 to High(AVerbatim.ValueMap) do
  begin
    if AVerbatim.ValueMap[LK].ValueOffset <= LOffset then
      LRun := LK
    else
      Break;
  end;
  if AVerbatim.ValueMap[LRun].IsCopy then
    Result := AVerbatim.ValueMap[LRun].Column + UInt64(LOffset - AVerbatim.ValueMap[LRun].ValueOffset)
  else
    Result := AVerbatim.ValueMap[LRun].Column;
end;

class function TPCAst.DoMapColumn(const ANode: TPCNode; const ALine: UInt64;
  const AColumn: UInt64; const ASpan: TPCEmitSpan): UInt64;
var
  LBase: UInt64;
  LVerbatim: TPCVerbatim;
begin
  // cpp("..."): through the value map, back to the character the C++ came
  // from; without one (an empty value) at the node's start
  if DoCppExprOf(ANode, LVerbatim) then
  begin
    if Length(LVerbatim.ValueMap) = 0 then
      Exit(ANode.Range.StartColumn);
    Exit(DoMapValueColumn(LVerbatim, ALine, AColumn, ASpan, ANode.Range.StartColumn));
  end;
  if not DoIsByteCopy(ANode) then
    Exit(ANode.Range.StartColumn);

  // Copied line for line with whitespace intact: the first line starts at the
  // node's start column, every later line at column 1
  if ALine = ANode.Range.StartLine then
    LBase := ANode.Range.StartColumn
  else
    LBase := 1;
  Result := LBase + (AColumn - ASpan.StartCol);
end;

function TPCAst.TranslateLocation(const AFilename: string; const ALine: UInt64;
  const AColumn: UInt64; out AOutFilename: string; out AOutLine: UInt64;
  out AOutColumn: UInt64): Boolean;
var
  LModule: TPCModule;
  LBest: TPCNode;
  LBestSpan: TPCEmitSpan;
begin
  // Not mine unless a span matches: the outputs mirror the inputs
  Result := False;
  AOutFilename := AFilename;
  AOutLine := ALine;
  AOutColumn := AColumn;

  LModule := FindModuleByFile(AFilename);
  if LModule = nil then
    Exit;
  if not DoNarrowestAt(LModule, ALine, AColumn, LBest, LBestSpan) then
    Exit;

  AOutFilename := LModule.SourceFile;
  AOutLine := ALine;
  AOutColumn := DoMapColumn(LBest, ALine, AColumn, LBestSpan);
  Result := True;
end;

class function TPCAst.DoNarrowestAt(const AModule: TPCModule; const ALine: UInt64;
  const AColumn: UInt64; out ANode: TPCNode; out ASpan: TPCEmitSpan): Boolean;
var
  LBest: TPCNode;
  LBestSpan: TPCEmitSpan;
  LBestWidth: UInt64;
  LSearch: TPCNodeVisitor;
begin
  // The node whose emitted span on this line covers the column, the
  // narrowest one; on equal width the later-visited (deeper) node wins.
  // Column 0 (linker) never matches since columns are 1-based. One search
  // for TranslateLocation and AlignRecordAt
  LBest := nil;
  LBestSpan := Default(TPCEmitSpan);
  LBestWidth := High(UInt64);

  LSearch :=
    procedure(const ANode: TPCNode)
    var
      LSpan: TPCEmitSpan;
    begin
      for LSpan in ANode.EmitSpans do
      begin
        if (LSpan.SourceLine = ALine) and (LSpan.StartCol <= AColumn) and
          (AColumn < LSpan.EndCol) and ((LSpan.EndCol - LSpan.StartCol) <= LBestWidth) then
        begin
          LBest := ANode;
          LBestSpan := LSpan;
          LBestWidth := LSpan.EndCol - LSpan.StartCol;
        end;
      end;
      ANode.EnumChildren(LSearch);
    end;
  try
    LSearch(AModule);
  finally
    // The visitor captures itself: clear it to break the reference cycle
    LSearch := nil;
  end;

  ANode := LBest;
  ASpan := LBestSpan;
  Result := LBest <> nil;
end;

function TPCAst.AlignRecordAt(const AFilename: string; const ALine: UInt64;
  const AColumn: UInt64; out ARecord: TPCRecordType; out ATypeName: string): Boolean;
var
  LModule: TPCModule;
  LBest: TPCNode;
  LBestSpan: TPCEmitSpan;
  LFound: TPCRecordType;
  LName: string;
  LSearch: TPCNodeVisitor;
begin
  // The node clang's location falls in must be a record's align value (the
  // check's span); its type declaration names it. A record is always a type
  // declaration's TypeDef (BNF sec 4), local ones included
  Result := False;
  ARecord := nil;
  ATypeName := '';
  LModule := FindModuleByFile(AFilename);
  if LModule = nil then
    Exit;
  if not DoNarrowestAt(LModule, ALine, AColumn, LBest, LBestSpan) then
    Exit;
  if not (LBest is TPCExpr) then
    Exit;

  LFound := nil;
  LName := '';
  LSearch :=
    procedure(const ANode: TPCNode)
    begin
      if LFound <> nil then
        Exit;
      if (ANode is TPCTypeDecl) and (TPCTypeDecl(ANode).TypeDef is TPCRecordType) and
        (TPCRecordType(TPCTypeDecl(ANode).TypeDef).AlignExpr = LBest) then
      begin
        LFound := TPCRecordType(TPCTypeDecl(ANode).TypeDef);
        LName := TPCTypeDecl(ANode).DeclName;
        Exit;
      end;
      if (ANode is TPCRecordType) and (TPCRecordType(ANode).AlignExpr = LBest) then
      begin
        LFound := TPCRecordType(ANode);
        LName := LFound.TypeText();
        Exit;
      end;
      ANode.EnumChildren(LSearch);
    end;
  try
    LSearch(LModule);
  finally
    // The visitor captures itself: clear it to break the reference cycle
    LSearch := nil;
  end;

  if LFound = nil then
    Exit;
  ARecord := LFound;
  ATypeName := LName;
  Result := True;
end;

function TPCAst.PrintArgAt(const AFilename: string; const ALine: UInt64;
  const AColumn: UInt64; out AArg: TPCExpr): Boolean;
var
  LModule: TPCModule;
  LBest: TPCNode;
  LBestSpan: TPCEmitSpan;
  LFound: Boolean;
  LSearch: TPCNodeVisitor;
begin
  // The node clang's location falls in must be an argument after the format
  // of a print / println call (the check's span is the argument's)
  Result := False;
  AArg := nil;
  LModule := FindModuleByFile(AFilename);
  if LModule = nil then
    Exit;
  if not DoNarrowestAt(LModule, ALine, AColumn, LBest, LBestSpan) then
    Exit;
  if not (LBest is TPCExpr) then
    Exit;

  LFound := False;
  LSearch :=
    procedure(const ANode: TPCNode)
    var
      LIndex: Integer;
    begin
      if LFound then
        Exit;
      if (ANode is TPCCall) and ((TPCCall(ANode).IntrinsicKind = ikPrint) or
        (TPCCall(ANode).IntrinsicKind = ikPrintLn)) then
      begin
        for LIndex := 1 to TPCCall(ANode).Args.Count - 1 do
        begin
          if TPCCall(ANode).Args[LIndex] = LBest then
          begin
            LFound := True;
            Exit;
          end;
        end;
      end;
      ANode.EnumChildren(LSearch);
    end;
  try
    LSearch(LModule);
  finally
    // The visitor captures itself: clear it to break the reference cycle
    LSearch := nil;
  end;

  if not LFound then
    Exit;
  AArg := TPCExpr(LBest);
  Result := True;
end;

{ Call lookup }
// CallAt's containment test: ANode is ARoot or lies anywhere below it

function DoNodeWithin(const ARoot: TPCNode; const ANode: TPCNode): Boolean;
var
  LFound: Boolean;
  LSearch: TPCNodeVisitor;
begin
  Result := False;
  if ARoot = nil then
    Exit;
  if ARoot = ANode then
    Exit(True);
  LFound := False;
  LSearch :=
    procedure(const AChild: TPCNode)
    begin
      if LFound then
        Exit;
      if AChild = ANode then
      begin
        LFound := True;
        Exit;
      end;
      AChild.EnumChildren(LSearch);
    end;
  try
    ARoot.EnumChildren(LSearch);
  finally
    // The visitor captures itself: clear it to break the reference cycle
    LSearch := nil;
  end;
  Result := LFound;
end;

function TPCAst.CallAt(const AFilename: string; const ALine: UInt64;
  const AColumn: UInt64; out ACall: TPCCall; out AArgIndex: Integer): Boolean;
var
  LModule: TPCModule;
  LBest: TPCNode;
  LBestSpan: TPCEmitSpan;
  LCall: TPCCall;
  LIndex: Integer;
  LSearch: TPCNodeVisitor;
begin
  // Every call holding the narrowest node is visited, an outer one before
  // the calls in its arguments (preorder), so the last one taken is the
  // innermost: println("{}", F(X)) at X is F's argument, not println's
  Result := False;
  ACall := nil;
  AArgIndex := -1;
  LModule := FindModuleByFile(AFilename);
  if LModule = nil then
    Exit;
  // Any node: at a callee the narrowest is a part of its name
  // (TPCNamePart), which lies within the callee all the same
  if not DoNarrowestAt(LModule, ALine, AColumn, LBest, LBestSpan) then
    Exit;

  LCall := nil;
  LSearch :=
    procedure(const ANode: TPCNode)
    var
      LArg: Integer;
    begin
      if ANode is TPCCall then
      begin
        if (ANode = LBest) or DoNodeWithin(TPCCall(ANode).Callee, LBest) then
        begin
          LCall := TPCCall(ANode);
          LIndex := -1;
        end
        else
        begin
          for LArg := 0 to TPCCall(ANode).Args.Count - 1 do
          begin
            if DoNodeWithin(TPCCall(ANode).Args[LArg], LBest) then
            begin
              LCall := TPCCall(ANode);
              LIndex := LArg;
              Break;
            end;
          end;
        end;
      end;
      ANode.EnumChildren(LSearch);
    end;
  try
    LSearch(LModule);
  finally
    // The visitor captures itself: clear it to break the reference cycle
    LSearch := nil;
  end;

  if LCall = nil then
    Exit;
  ACall := LCall;
  AArgIndex := LIndex;
  Result := True;
end;

{ Packed field lookup }
// FieldCheckAt's member test: AField is a field of the list or of an
// anonymous aggregate inside it

function DoMembersHaveField(const AMembers: TList<TPCMemberItem>; const AField: TPCNode): Boolean;
var
  LMember: TPCMemberItem;
begin
  Result := False;
  if AMembers = nil then
    Exit;
  for LMember in AMembers do
  begin
    if LMember = AField then
      Exit(True);
    if (LMember is TPCAnonAggregate) and DoMembersHaveField(TPCAnonAggregate(LMember).Members, AField) then
      Exit(True);
  end;
end;

function TPCAst.FieldCheckAt(const AFilename: string; const ALine: UInt64; const AColumn: UInt64;
  out AOwner: TPCNode; out ARecordName: string; out AFieldName: string;
  out ATypeText: string): Boolean;
var
  LModule: TPCModule;
  LBest: TPCNode;
  LBestSpan: TPCEmitSpan;
  LName: string;
  LFound: Boolean;
  LSearch: TPCNodeVisitor;
begin
  // The node clang's location falls in must be a field, or a type expr that
  // is a record's parent (the check's span is theirs); the type declaration
  // holding it names the record (a record / overlay is always one's TypeDef)
  Result := False;
  AOwner := nil;
  ARecordName := '';
  AFieldName := '';
  ATypeText := '';
  LModule := FindModuleByFile(AFilename);
  if LModule = nil then
    Exit;
  if not DoNarrowestAt(LModule, ALine, AColumn, LBest, LBestSpan) then
    Exit;
  if not ((LBest is TPCField) or (LBest is TPCTypeExpr)) then
    Exit;

  LFound := False;
  LName := '';
  LSearch :=
    procedure(const ANode: TPCNode)
    var
      LDef: TPCTypeExpr;
    begin
      if LFound then
        Exit;
      if ANode is TPCTypeDecl then
      begin
        LDef := TPCTypeDecl(ANode).TypeDef;
        if (LDef is TPCRecordType) and ((TPCRecordType(LDef).ParentName = LBest) or
          DoMembersHaveField(TPCRecordType(LDef).Members, LBest)) then
          LFound := True
        else if (LDef is TPCOverlayType) and DoMembersHaveField(TPCOverlayType(LDef).Members, LBest) then
          LFound := True;
        if LFound then
        begin
          LName := TPCTypeDecl(ANode).DeclName;
          Exit;
        end;
      end;
      ANode.EnumChildren(LSearch);
    end;
  try
    LSearch(LModule);
  finally
    // The visitor captures itself: clear it to break the reference cycle
    LSearch := nil;
  end;

  if not LFound then
    Exit;
  AOwner := LBest;
  ARecordName := LName;
  if LBest is TPCField then
  begin
    AFieldName := TPCField(LBest).FieldName;
    if TPCField(LBest).TypeExpr <> nil then
      ATypeText := TPCField(LBest).TypeExpr.TypeText();
  end
  else
    ATypeText := TPCTypeExpr(LBest).TypeText();
  Result := True;
end;

function TPCAst.SizeCheckAt(const AFilename: string; const ALine: UInt64; const AColumn: UInt64;
  const ARecordText: Boolean; out ARange: TSourceRange; out ATypeText: string): Boolean;
var
  LModule: TPCModule;
  LBest: TPCNode;
  LBestSpan: TPCEmitSpan;
  LType: TPCTypeExpr;
  LDecl: TPCTypeDecl;
  LFoundExpr: TPCExpr;
  LSearch: TPCNodeVisitor;
begin
  // F47: the node whose emitted span is the narrowest at clang's location
  Result := False;
  ARange := Default(TSourceRange);
  ATypeText := '';
  LModule := FindModuleByFile(AFilename);
  if LModule = nil then
    Exit;
  if not DoNarrowestAt(LModule, ALine, AColumn, LBest, LBestSpan) then
    Exit;

  if ARecordText then
  begin
    // clang names the struct / union at its name: the type declaration
    // holding that record, overlay or anonymous aggregate. An anonymous one
    // too large makes its holder too large: both are reported at the
    // holder's name, the same report (BuildOutput keeps one)
    LDecl := nil;
    if LBest is TPCTypeDecl then
      LDecl := TPCTypeDecl(LBest)
    else if (LBest is TPCRecordType) or (LBest is TPCOverlayType) or (LBest is TPCAnonAggregate) then
    begin
      LSearch :=
        procedure(const ANode: TPCNode)
        var
          LDef: TPCTypeExpr;
        begin
          if LDecl <> nil then
            Exit;
          if ANode is TPCTypeDecl then
          begin
            LDef := TPCTypeDecl(ANode).TypeDef;
            if (LDef = LBest) or
              ((LDef is TPCRecordType) and DoMembersHaveField(TPCRecordType(LDef).Members, LBest)) or
              ((LDef is TPCOverlayType) and DoMembersHaveField(TPCOverlayType(LDef).Members, LBest)) then
            begin
              LDecl := TPCTypeDecl(ANode);
              Exit;
            end;
          end;
          ANode.EnumChildren(LSearch);
        end;
      try
        LSearch(LModule);
      finally
        // The visitor captures itself: clear it to break the reference cycle
        LSearch := nil;
      end;
    end;
    if LDecl = nil then
      Exit;
    ARange := LDecl.NameRange;
    ATypeText := LDecl.DeclName;
    Exit(True);
  end;

  // The runtime's Array check, at the use that instantiated the array: a
  // declaration holding it by value names its type as written; an
  // expression (a deref, a call's result) the outermost part of it whose
  // resolved type is a static array (clang's column may fall on an index of
  // it: `LP^[0]` reports at `LP^`, typed TBig, not the int32 element)
  if LBest is TPCExpr then
  begin
    LFoundExpr := nil;
    LSearch :=
      procedure(const ANode: TPCNode)
      var
        LCanon: TPCTypeExpr;
      begin
        if LFoundExpr <> nil then
          Exit;
        if (ANode is TPCExpr) and (TPCExpr(ANode).ResolvedType <> nil) then
        begin
          LCanon := TPCExpr(ANode).ResolvedType.Canon();
          if (LCanon is TPCArrayType) and not TPCArrayType(LCanon).IsDynamic then
          begin
            LFoundExpr := TPCExpr(ANode);
            Exit;
          end;
        end;
        ANode.EnumChildren(LSearch);
      end;
    try
      LSearch(LBest);
    finally
      // The visitor captures itself: clear it to break the reference cycle
      LSearch := nil;
    end;
    if LFoundExpr = nil then
      Exit;
    ARange := LFoundExpr.Range;
    ATypeText := LFoundExpr.ResolvedType.TypeText();
    Exit(True);
  end;
  if LBest is TPCVarDecl then
    LType := TPCVarDecl(LBest).TypeExpr
  else if LBest is TPCConstDecl then
    LType := TPCConstDecl(LBest).TypeExpr
  else if LBest is TPCField then
    LType := TPCField(LBest).TypeExpr
  else if LBest is TPCParam then
    LType := TPCParam(LBest).TypeExpr
  else if LBest is TPCRoutine then
    LType := TPCRoutine(LBest).ReturnType
  else if LBest is TPCTypeExpr then
    LType := TPCTypeExpr(LBest)
  else
    Exit;
  if LType = nil then
    Exit;
  ARange := LType.Range;
  ATypeText := LType.TypeText();
  Result := True;
end;

function TPCAst.CppOverrideAt(const AFilename: string; const ALine: UInt64; const AColumn: UInt64;
  out AItem: TPCMethodItem; out ACppParent: string; out ARecordName: string): Boolean;
var
  LModule: TPCModule;
  LBest: TPCNode;
  LBestSpan: TPCEmitSpan;
  LFound: TPCMethodItem;
  LRecord: TPCRecordType;
  LName: string;
  LLevel: TPCRecordType;
  LCanon: TPCTypeExpr;
  LDepth: Integer;
  LSearch: TPCNodeVisitor;
begin
  // The node clang's location falls in must be a method's routine (its
  // declaration's span; clang reports at the name), declared by an object
  // whose chain reaches a C/C++ class (ResolvedDerivesFromCpp). That class
  // is the first C/C++ parent going up the chain. An object is always a type
  // declaration's TypeDef (BNF sec 4), local ones included
  Result := False;
  AItem := nil;
  ACppParent := '';
  ARecordName := '';
  LModule := FindModuleByFile(AFilename);
  if LModule = nil then
    Exit;
  if not DoNarrowestAt(LModule, ALine, AColumn, LBest, LBestSpan) then
    Exit;
  if not (LBest is TPCRoutine) then
    Exit;

  LFound := nil;
  LRecord := nil;
  LName := '';
  LSearch :=
    procedure(const ANode: TPCNode)
    var
      LMember: TPCMemberItem;
      LDef: TPCTypeExpr;
    begin
      if LFound <> nil then
        Exit;
      if ANode is TPCTypeDecl then
      begin
        LDef := TPCTypeDecl(ANode).TypeDef;
        if (LDef is TPCRecordType) and TPCRecordType(LDef).IsObject then
        begin
          for LMember in TPCRecordType(LDef).Members do
          begin
            if (LMember is TPCMethodItem) and (TPCMethodItem(LMember).Routine = LBest) then
            begin
              LFound := TPCMethodItem(LMember);
              LRecord := TPCRecordType(LDef);
              LName := TPCTypeDecl(ANode).DeclName;
              Exit;
            end;
          end;
        end;
      end;
      ANode.EnumChildren(LSearch);
    end;
  try
    LSearch(LModule);
  finally
    // The visitor captures itself: clear it to break the reference cycle
    LSearch := nil;
  end;

  if (LFound = nil) or not LRecord.ResolvedDerivesFromCpp then
    Exit;
  // Up the PaskalCPP object levels to the first C/C++ parent (bounded: SEM
  // rejected a cycle)
  LLevel := LRecord;
  LDepth := 0;
  while (LLevel <> nil) and (LLevel.ParentName <> nil) and (LDepth < 256) do
  begin
    if TPCTypeExpr.IsOpaqueTier(LLevel.ParentName) then
    begin
      ACppParent := LLevel.ParentName.TypeText();
      Break;
    end;
    LCanon := LLevel.ParentName.Canon();
    if LCanon is TPCRecordType then
      LLevel := TPCRecordType(LCanon)
    else
      LLevel := nil;
    Inc(LDepth);
  end;
  if ACppParent = '' then
    Exit;
  AItem := LFound;
  ARecordName := LName;
  Result := True;
end;

function TPCAst.PolyCheckAt(const AFilename: string; const ALine: UInt64; const AColumn: UInt64;
  out AExpr: TPCExpr): Boolean;
var
  LModule: TPCModule;
  LBest: TPCNode;
  LBestSpan: TPCEmitSpan;
begin
  // The check is text of the expression's own span, before its operands:
  // clang's location (the static_assert) falls in no narrower node
  Result := False;
  AExpr := nil;
  LModule := FindModuleByFile(AFilename);
  if LModule = nil then
    Exit;
  if not DoNarrowestAt(LModule, ALine, AColumn, LBest, LBestSpan) then
    Exit;
  if not (LBest is TPCExpr) or (TPCExpr(LBest).ResolvedPolyCheck = pcNone) then
    Exit;
  AExpr := TPCExpr(LBest);
  Result := True;
end;

class function TPCAst.DoExternalLibRange(const ANode: TPCNode;
  const ALibrary: string): TSourceRange;
var
  LFound: TSourceRange;
begin
  // The first external clause in tree order whose library SEM resolved to
  // ALibrary (TPCCompiler.DoCollectLinks' walk); an empty range = none
  LFound.Clear();
  if ANode = nil then
    Exit(LFound);

  if (ANode is TPCVarDecl) and (TPCVarDecl(ANode).ExternalClause.ResolvedLib = ALibrary) then
    Exit(TPCVarDecl(ANode).ExternalClause.LibRange);
  if (ANode is TPCRoutine) and (TPCRoutine(ANode).ExternalClause.ResolvedLib = ALibrary) then
    Exit(TPCRoutine(ANode).ExternalClause.LibRange);

  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      if LFound.Filename = '' then
        LFound := DoExternalLibRange(AChild, ALibrary);
    end);
  Result := LFound;
end;

function TPCAst.LocateLibrary(const ALibrary: string; out AOutFilename: string;
  out AOutLine: UInt64; out AOutColumn: UInt64): Boolean;
var
  LIndex: Integer;
  LModule: TPCModule;
  LDirective: TPCDirective;
  LRange: TSourceRange;
begin
  AOutFilename := '';
  AOutLine := 0;
  AOutColumn := 0;
  Result := False;
  if ALibrary = '' then
    Exit;

  for LIndex := 0 to ModuleCount() - 1 do
  begin
    LModule := ModuleAt(LIndex);
    LRange.Clear();

    // Its @linklibrary directives first, in source order; one SEM set aside
    // links nothing (TPCCompiler.DoApplyDirectives)
    for LDirective in LModule.Directives do
    begin
      if (LDirective.DirectiveKind = bdLinkLibrary) and (not LDirective.ResolvedNoEffect) and
        (LDirective.Args.Count > 0) and (LDirective.Args[0].ResolvedText = ALibrary) then
      begin
        LRange := LDirective.Args[0].Range;
        Break;
      end;
    end;

    // Then its external clauses
    if LRange.Filename = '' then
      LRange := DoExternalLibRange(LModule, ALibrary);

    if LRange.Filename <> '' then
    begin
      AOutFilename := LRange.Filename;
      AOutLine := LRange.StartLine;
      AOutColumn := LRange.StartColumn;
      Exit(True);
    end;
  end;
end;

end.
