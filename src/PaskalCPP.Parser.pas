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
  PaskalCPP.Parser - Tokens to AST

  TPCParser parses ONE .pcpp file into a TPCModule: the lexer fills a raw
  stream, the conditional filter keeps the active tokens, the parser cursors
  them. ParseModuleFile owns one parser per file, so an import recurses on
  the call stack and its module registers when its parse returns (dependency
  order). Import identity is the resolved source file.
  Module level (CORE-A, CORE-B): header, build-directive prologue, module
  search paths, import clause, the declaration loop (C++ spans with F1
  blanking and inside lines, # lines, cpp placement, cppstart blocks),
  initialize / finalize, the exe body, end, test blocks, EOF
  (research\cppmix\parser-core.md). Declarations and types (PARSER-EXPR-A:
  research\cppmix\parser-expr\decls.md, types.md). Expressions and
  expression-side template arguments (PARSER-EXPR-B: expr.md, templates.md).
  The verbatim expression forms, the C-style cast and size(T) (PARSER-EXPR-C:
  verbatim-expr.md). Statements (PARSER-STMT: research\cppmix\parser-stmt\stmt.md).

  Dependencies: StdApp.Base (TBaseObject, TErrors), StdApp.Utils (ResolvePath,
    JoinResolvedPath, SamePath), StdApp.Resources (RSPar*), PaskalCPP.Common,
    PaskalCPP.TokenStream, PaskalCPP.Lexer, PaskalCPP.Conditionals,
    PaskalCPP.AST, PaskalCPP.SourceText (verbatim bytes, string value maps),
    PaskalCPP.CppJumps (a body cppstart block's escaping jumps)
  Notes: DoAdvance is the only way a token is consumed, so FLastToken ends
    every node's range. Names match on token Spelling, never Text.
===============================================================================}

unit PaskalCPP.Parser;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.Common,
  PaskalCPP.TokenStream,
  PaskalCPP.Lexer,
  PaskalCPP.Conditionals,
  PaskalCPP.AST;

const
  { PC_ERR_PAR_001 }
  PC_ERR_PAR_001 = 'PR0001';   // expected X, found Y
  { PC_ERR_PAR_002 }
  PC_ERR_PAR_002 = 'PR0002';   // expected a module kind
  { PC_ERR_PAR_003 }
  PC_ERR_PAR_003 = 'PR0003';   // module name differs from the file name
  { PC_ERR_PAR_004 }
  PC_ERR_PAR_004 = 'PR0004';   // a unit as the main module
  { PC_ERR_PAR_005 }
  PC_ERR_PAR_005 = 'PR0005';   // unknown build directive
  { PC_ERR_PAR_006 }
  PC_ERR_PAR_006 = 'PR0006';   // build directive argument does not fit its shape
  { PC_ERR_PAR_007 }
  PC_ERR_PAR_007 = 'PR0007';   // @message severity
  { PC_ERR_PAR_008 }
  PC_ERR_PAR_008 = 'PR0008';   // build directive outside the directive prologue
  { PC_ERR_PAR_009 }
  PC_ERR_PAR_009 = 'PR0009';   // invalid string literal (prefix, suffix, decode error)
  { PC_ERR_PAR_010 }
  PC_ERR_PAR_010 = 'PR0010';   // import outside the one import clause
  { PC_ERR_PAR_011 }
  PC_ERR_PAR_011 = 'PR0011';   // import cycle
  { PC_ERR_PAR_012 }
  PC_ERR_PAR_012 = 'PR0012';   // unit file not found
  { PC_ERR_PAR_013 }
  PC_ERR_PAR_013 = 'PR0013';   // imported module is not a unit
  { PC_ERR_PAR_014 }
  PC_ERR_PAR_014 = 'PR0014';   // duplicate import in the clause
  { PC_ERR_PAR_015 }
  PC_ERR_PAR_015 = 'PR0015';   // expected header or source after cpp / cppstart
  { PC_ERR_PAR_016 }
  PC_ERR_PAR_016 = 'PR0016';   // begin body in a module that is not an exe
  { PC_ERR_PAR_017 }
  PC_ERR_PAR_017 = 'PR0017';   // an exe without a begin body
  { PC_ERR_PAR_018 }
  PC_ERR_PAR_018 = 'PR0018';   // initialize / finalize repeated or out of order
  { PC_ERR_PAR_019 }
  PC_ERR_PAR_019 = 'PR0019';   // test block before the module's end
  { PC_ERR_PAR_020 }
  PC_ERR_PAR_020 = 'PR0020';   // tokens after the module's end
  { PC_ERR_PAR_021 }
  PC_ERR_PAR_021 = 'PR0021';   // string literal warning (esWarning), value kept
  { PC_ERR_PAR_022 }
  PC_ERR_PAR_022 = 'PR0022';   // path directive value cannot be resolved
  { PC_ERR_PAR_023 }
  PC_ERR_PAR_023 = 'PR0023';   // main-module-only build directive in a unit (BNF.md sec 2)
  { PC_ERR_PAR_024 }
  PC_ERR_PAR_024 = 'PR0024';   // exported before a non-PaskalCPP declaration (X3)
  { PC_ERR_PAR_025 }
  PC_ERR_PAR_025 = 'PR0025';   // declaration block not allowed before a method's / test's begin
  { PC_ERR_PAR_026 }
  PC_ERR_PAR_026 = 'PR0026';   // record / object / overlay / choices / routine / set of in a type expr
  { PC_ERR_PAR_027 }
  PC_ERR_PAR_027 = 'PR0027';   // PaskalCPP primitive with a C++ suffix (T5)
  { PC_ERR_PAR_028 }
  PC_ERR_PAR_028 = 'PR0028';   // qualified (dotted) name with a C++ suffix (T3)
  { PC_ERR_PAR_029 }
  PC_ERR_PAR_029 = 'PR0029';   // cv qualifier repeated in one slot
  { PC_ERR_PAR_030 }
  PC_ERR_PAR_030 = 'PR0030';   // reference not last, or a second one
  { PC_ERR_PAR_031 }
  PC_ERR_PAR_031 = 'PR0031';   // template arguments not closed (tmType)
  { PC_ERR_PAR_032 }
  PC_ERR_PAR_032 = 'PR0032';   // record prefix out of order or repeated
  { PC_ERR_PAR_033 }
  PC_ERR_PAR_033 = 'PR0033';   // packed / align not allowed on this aggregate
  { PC_ERR_PAR_034 }
  PC_ERR_PAR_034 = 'PR0034';   // member not allowed in this aggregate
  { PC_ERR_PAR_035 }
  PC_ERR_PAR_035 = 'PR0035';   // empty choices
  { PC_ERR_PAR_036 }
  PC_ERR_PAR_036 = 'PR0036';   // elaborated key not followed by a name (T14)
  { PC_ERR_PAR_037 }
  PC_ERR_PAR_037 = 'PR0037';   // decltype without a balanced ( ... ) (T15)
  { PC_ERR_PAR_038 }
  PC_ERR_PAR_038 = 'PR0038';   // comparisons do not chain (EX2)
  { PC_ERR_PAR_039 }
  PC_ERR_PAR_039 = 'PR0039';   // == / != (EX3)
  { PC_ERR_PAR_040 }
  PC_ERR_PAR_040 = 'PR0040';   // C++ word operator: bitand bitor compl not_eq and_eq or_eq xor_eq (EX4)
  { PC_ERR_PAR_041 }
  PC_ERR_PAR_041 = 'PR0041';   // builtin type cast with more than one argument (EX6)
  { PC_ERR_PAR_042 }
  PC_ERR_PAR_042 = 'PR0042';   // nested too deeply (EX7)
  { PC_ERR_PAR_043 }
  PC_ERR_PAR_043 = 'PR0043';   // named cast: not exactly one type in < > (EX8)
  { PC_ERR_PAR_044 }
  PC_ERR_PAR_044 = 'PR0044';   // lambda without a { } body (EV1)
  { PC_ERR_PAR_045 }
  PC_ERR_PAR_045 = 'PR0045';   // sizeof / alignof / decltype / noexcept / typeid without ( ) (EV2)
  { PC_ERR_PAR_046 }
  PC_ERR_PAR_046 = 'PR0046';   // line break in a non-raw cpp("...") (EV3)
  { PC_ERR_PAR_047 }
  PC_ERR_PAR_047 = 'PR0047';   // expected an expression after a C-style cast (EV4)
  { PC_PAR_NEST_MAX }
  PC_PAR_NEST_MAX = 256;       // nesting levels one parse may enter: the parser's stack bound (bundled clang allows 2048 brackets; EMIT keeps emitted depth within it)
  { PC_ERR_PAR_048 }
  PC_ERR_PAR_048 = 'PR0048';   // expression statement whose top-level operator is '='
  { PC_ERR_PAR_049 }
  PC_ERR_PAR_049 = 'PR0049';   // C++ statement keyword in a body (switch try break ...)
  { PC_ERR_PAR_050 }
  PC_ERR_PAR_050 = 'PR0050';   // cpp header|source placement in a body
  { PC_ERR_PAR_051 }
  PC_ERR_PAR_051 = 'PR0051';   // cppstart header in a body
  { PC_ERR_PAR_052 }
  PC_ERR_PAR_052 = 'PR0052';   // guard with neither except nor finally
  { PC_ERR_PAR_053 }
  PC_ERR_PAR_053 = 'PR0053';   // bare set (no range, no element type)
  { PC_ERR_PAR_054 }
  PC_ERR_PAR_054 = 'PR0054';   // char literal clang rejects (empty, too large, bad escape)
  { PC_ERR_PAR_055 }
  PC_ERR_PAR_055 = 'PR0055';   // @linklibrary / external "..." names a file, not a library
  { PC_ERR_PAR_056 }
  PC_ERR_PAR_056 = 'PR0056';   // a folder given to AddModulePath cannot be resolved
  { PC_ERR_PAR_057 }
  PC_ERR_PAR_057 = 'PR0057';   // exported before a block among a body's declarations (module level only)
  { PC_ERR_PAR_058 }
  PC_ERR_PAR_058 = 'PR0058';   // hidden / virtual / override / final before an init or a done (PLAN-OBJECT D3)
  { PC_ERR_PAR_059 }
  PC_ERR_PAR_059 = 'PR0059';   // an init with a result type or '...'; a done with parameters or a result type
  { PC_ERR_PAR_060 }
  PC_ERR_PAR_060 = 'PR0060';   // an interface method with a body or 'abstract' (PLAN-OBJECT O7)
  { PC_ERR_PAR_061 }
  PC_ERR_PAR_061 = 'PR0061';   // a property without read, or an accessor of another shape (PLAN-OBJECT O9)
  { PC_ERR_PAR_062 }
  PC_ERR_PAR_062 = 'PR0062';   // an operator symbol a type cannot declare, or '...' on an operator (PLAN-OBJECT O11)
  { PC_ERR_PAR_063 }
  PC_ERR_PAR_063 = 'PR0063';   // a balanced group's opener never closed before EOF, reported at the opener (PLAN-COMPLIANCE F56)
  { PC_ERR_PAR_064 }
  PC_ERR_PAR_064 = 'PR0064';   // char literal warning (esWarning), value kept (F65)

type

  { TPCArgOutcome }
  // arOk = the argument(s) were read; arShapeMiss = the current token does not
  // fit the shape (the caller reports PR0006); arReported = reported here
  TPCArgOutcome = (arOk, arShapeMiss, arReported);

  { TPCExprContext }
  // ecTemplateArg: the '>' family ends the expression (a template argument's
  // top level, research parser-expr\expr.md); everywhere else ecNormal
  TPCExprContext = (ecNormal, ecTemplateArg);

  { TPCTemplateMode }
  // tmType: a type position, always parsed and reported (BNF.md sec 4);
  // tmQualified / tmMember: the expression-side attempts (PARSER-EXPR-B)
  TPCTemplateMode = (tmType, tmQualified, tmMember);

  { TPCBlockAllow }
  // The declaration blocks before a body's begin (BNF.md sec 3, sec 8): a
  // routine any, a method var blocks only, a test at most one var block
  TPCBlockAllow = (baRoutine, baMethod, baTest);

  { TPCAggKind }
  // The aggregate whose members are parsed (BNF.md sec 4)
  TPCAggKind = (agRecord, agObject, agOverlay, agAnonRecord, agAnonOverlay, agInterface);

  { TPCAttempt }
  // Everything a backtracking try restores (templates.md A1): the cursor
  // (splits included), the report count (warnings too), the end-of-file flag
  // and the last consumed token. Saved and restored ONLY by DoSaveAttempt /
  // DoRestoreAttempt
  TPCAttempt = record
    Position: TPCStreamPosition;
    ReportCount: Integer;
    EofReported: Boolean;
    EndReported: Boolean;
    EndReportedAt: UInt64;
    LastToken: TPCToken;
    HasLast: Boolean;
  end;

  { TPCSkipMark }
  // Where a recovery skip started (PLAN-RECOVERY): the cursor index and the
  // range of the token there. DoAddSkipped / DoAddSkippedMember turn the
  // tokens consumed since into one error node; nothing consumed = no node
  TPCSkipMark = record
    TokenIndex: Integer;
    Range: TSourceRange;
  end;

  { TPCFollowContext }
  // What may follow a construct whose ';' is missing (DoExpectTerminator):
  // fcModule anything (every module-level token starts an item or C++),
  // fcStatement a statement or a token that closes the statement list,
  // fcVarItem / fcConstItem / fcTypeItem an item of that block inside a
  // routine (its declaration blocks or body), fcSignature a routine body or
  // external clause, fcMember the next member or the aggregate's end
  TPCFollowContext = (fcModule, fcStatement, fcVarItem, fcConstItem, fcTypeItem, fcSignature,
    fcMember);

  { TPCTerminatorOutcome }
  // toConsumed: the ';' was there. toInserted: missing and reported, the
  // next token starts what may follow, nothing skipped. toMissing: reported,
  // the caller skips into an error node
  TPCTerminatorOutcome = (toConsumed, toInserted, toMissing);

  { TPCInfixShape }
  // How an infix row builds its node (BNF.md sec 6 binding table)
  TPCInfixShape = (ixBinary, ixRelational, ixAssign, ixTernary);

  { TPCInfixRow }
  // One binding-table row: the token, its power, its shape and the operator it
  // builds. IsCppForm: a C++ spelling of a PaskalCPP operator, reported
  // (PR0039 / PR0040) and parsed as that operator; CppHint is the PaskalCPP
  // spelling ('' = xor_eq, hinted by RSParXorEqHint)
  TPCInfixRow = record
    Kind: TPCTokenKind;
    Power: Integer;
    Shape: TPCInfixShape;
    BinOp: TPCBinaryOp;
    AssignOp: TPCAssignOp;
    IsCppForm: Boolean;
    CppHint: string;
  end;

  { TPCCppStmtHint }
  // A C++ statement keyword and the PaskalCPP form PR0049 names (BNF.md sec 5)
  TPCCppStmtHint = record
    Kind: TPCTokenKind;
    Hint: string;
  end;

  { TPCSourceProvider }
  // The text of AFilename (a resolved path) when the caller has it, e.g. an
  // editor buffer that differs from the disk: True = parse ABytes (UTF-8),
  // False = read the file. Must not raise
  TPCSourceProvider = reference to function(const AFilename: string; out ABytes: TBytes): Boolean;

  { TPCParser }
  // Parses ONE file into a TPCModule (never nil). Wire SetErrors() and call
  // Init() before Parse(); ParseModuleFile does all three.
  TPCParser = class(TBaseObject)
  private
    FAst: TPCAst;                    // non-owning
    FLexer: TPCLexer;
    FFilter: TPCConditionalFilter;
    FRawStream: TPCTokenStream;      // the lexer's tokens
    FStream: TPCTokenStream;         // the filter's active tokens
    FCursor: TPCTokenStream;         // FStream, or FRawStream after a lexer failure
    FFilename: string;
    FImportChain: TArray<string>;    // resolved source files of the importers
    FMainTarget: TPCTargetTriple;    // empty in the main file
    FOverrideTarget: TPCTargetTriple; // the build's target (CLI -t), every file of the build; empty = none
    FDefaultTarget: TPCTargetTriple;  // stands in for a missing @target (editor -t), main only
    FModulePaths: TArray<string>;    // module search folders, resolved, in the order added, no duplicates (AddModulePath)
    FSourceProvider: TPCSourceProvider; // texts that win over the disk (nil = disk only); every import gets it
    FUnitMainAllowed: Boolean;       // the main file is checked, not built: a unit is fine (no PR0004)
    FModule: TPCModule;
    FKindAssumed: Boolean;           // the header gave no kind: DoAssumedKind() stands in
    FLastToken: TPCToken;            // the last token DoAdvance consumed
    FHasLast: Boolean;
    FPlacement: TPCEmitTarget;       // where the next C++ span goes (cpp header|source)
    FEofReported: Boolean;           // the end of file is reported once (B4)
    FEndReported: Boolean;           // a missing 'end' was reported at FEndReportedAt (F1)
    FEndReportedAt: UInt64;          // that token's start byte offset
    FExprDepth: Integer;             // nesting levels entered (DoEnterNested)
    FStmtDepth: Integer;             // statements entered (DoParseStatement): DoSkipItem's mode
    FTemplateFails: TDictionary<string, Boolean>;  // failed template-arg attempts (A4)

    // Cursor, ranges, reports
    function DoIsMain(): Boolean;
    function DoAssumedKind(): TPCModuleKind;
    function DoCurrent(): TPCToken;
    function DoPeek(const AOffset: Integer): TPCToken;
    // The current token is the context word AWord (PLAN-OBJECT H1: the
    // caller is at a position the grammar expects it in)
    function DoIsWord(const AWord: TPCContextWord): Boolean;
    function DoIsWordAt(const AWord: TPCContextWord; const AOffset: Integer): Boolean;
    procedure DoAdvance();
    function DoCheck(const AKind: TPCTokenKind): Boolean;
    function DoMatch(const AKind: TPCTokenKind): Boolean;
    function DoExpect(const AKind: TPCTokenKind; const AWhat: string): Boolean;
    function DoAfterLast(const AFound: TPCToken): TPCToken;
    function DoStartRange(): TSourceRange;
    procedure DoFinishRange(var ARange: TSourceRange);
    procedure DoError(const AToken: TPCToken; const ACode: string; const AMessage: string;
      const AArgs: array of const);
    procedure DoErrorAt(const ARange: TSourceRange; const ACode: string; const AMessage: string;
      const AArgs: array of const);
    procedure DoWarning(const AToken: TPCToken; const ACode: string; const AMessage: string;
      const AArgs: array of const);
    function DoStopped(): Boolean;
    procedure DoSkipFrame();
    function DoIsFrameStop(): Boolean;
    function DoIsModuleEnd(): Boolean;
    function DoHasModuleEndAhead(): Boolean;
    function DoMarkSkip(): TPCSkipMark;
    function DoAddSkipped(const AOwner: TList<TPCStmt>; const AMark: TPCSkipMark): TPCErrorStmt;
    function DoAddSkippedMember(const AOwner: TList<TPCMemberItem>;
      const AMark: TPCSkipMark): TPCErrorMember;
    class function DoFailed(const AExpr: TPCExpr): Boolean; static;
    function DoExpectTerminator(const AFollow: TPCFollowContext): TPCTerminatorOutcome;
    function DoCanFollow(const AFollow: TPCFollowContext): Boolean;
    function DoCanFollowItem(const ABlockKind: TPCTokenKind): Boolean;
    function DoCanFollowMember(): Boolean;
    function DoCanStartStatement(): Boolean;
    class function DoTokenText(const AToken: TPCToken): string; static;
    class function DoSpelled(const AText: string): string; static;
    class function DoKindOf(const AKind: TPCTokenKind; out AModuleKind: TPCModuleKind): Boolean; static;
    class function DoFileStem(const APath: string): string; static;
    class function DoFileDir(const APath: string): string; static;
    class function DoShapeText(const AShape: TPCDirectiveShape): string; static;
    class function DoIsOneOf(const AKind: TPCTokenKind;
      const AKinds: array of TPCTokenKind): Boolean; static;
    class function DoIsPlainString(const AToken: TPCToken): Boolean; static;
    class function DoIsCppTarget(const AToken: TPCToken;
      out ATarget: TPCEmitTarget): Boolean; static;

    // Header and prologue
    procedure DoReadHeaderQuiet();
    procedure DoParseHeader();
    procedure DoParsePrologue();
    procedure DoParseBuildDirective();
    function DoParseDirectiveNode(const AOwner: TList<TPCStmt>;
      const AInBody: Boolean): TPCDirective;
    procedure DoSkipDirective(const AInBody: Boolean);
    function DoParseDirectiveArgs(const ARow: TPCDirectiveRow;
      const ADirective: TPCDirective): TPCArgOutcome;
    function DoParseIdentifierArg(const ADirective: TPCDirective): TPCArgOutcome;
    function DoParseIntegerArg(const ADirective: TPCDirective): TPCArgOutcome;
    function DoParseSeverityArg(const ADirective: TPCDirective): TPCArgOutcome;
    function DoParseCStringArg(const ARow: TPCDirectiveRow;
      const ADirective: TPCDirective): TPCArgOutcome;
    function DoDecodeCString(const AToken: TPCToken; const AReport: Boolean;
      out AValue: string): Boolean; overload;
    function DoDecodeCString(const AToken: TPCToken; const AReport: Boolean;
      out AValue: string; out ARuns: TArray<TPCSpellRun>): Boolean; overload;
    function DoNewArg(const AToken: TPCToken; const AArgKind: TPCDirectiveArgKind;
      const AResolvedText: string): TPCDirectiveArg;
    function DoResolveDirectivePath(const ADirectiveName: string; const AToken: TPCToken;
      const AValue: string; out APath: string): Boolean;
    procedure DoCheckLibName(const AToken: TPCToken; const AValue: string; const AWhere: string);
    procedure DoCollectModulePaths();
    procedure DoAddSearchPath(const AResolvedPath: string);
    function DoParseImportFile(const AFile: string; const ATarget: TPCTargetTriple): TPCModule;
    function DoTokenizeSource(): Boolean;
    function DoEndsInReportedSpan(): Boolean;
    procedure DoRecordDropped();
    function DoSourceExists(const AFilename: string): Boolean;

    // Imports
    procedure DoParseImportClause();
    procedure DoParseImport(const ANameToken: TPCToken);
    function DoFindUnitFile(const AUnitName: string; out ASearched: string): string;
    function DoInChain(const AFile: string): Boolean;
    function DoCycleText(const AUnitName: string): string;

    // Module region (CORE-B)
    function DoCurrentIndex(): Integer;
    function DoIsDeclStart(): Boolean;
    function DoIsStarter(): Boolean;
    function DoScanSpan(): Integer;
    procedure DoFillVerbatim(const AFirst: Integer; const ALast: Integer;
      var AVerbatim: TPCVerbatim);
    function DoNewVerbatim(const AFirst: Integer; const ALast: Integer;
      const AKind: TPCVerbatimKind; const ATarget: TPCEmitTarget): TPCVerbatimStmt;
    procedure DoParseModuleDecls();
    procedure DoParseModuleDecl();
    procedure DoParsePreprocessor(const AOwner: TList<TPCStmt>; const ATarget: TPCEmitTarget);
    procedure DoParsePlacement();
    procedure DoParseCppBlock(const AOwner: TList<TPCStmt>; const AInBody: Boolean);
    procedure DoParseCppSpan();
    procedure DoReportMisplacedDirective();
    procedure DoSkipCppBlock();
    procedure DoSkipStatement();
    procedure DoSkipRefusedStatement();

    // Sections, bodies, end, tests
    procedure DoParseSections();
    function DoParseSection(): TPCRoutine;
    procedure DoParseRoutineBody(const ARoutine: TPCRoutine; const AAllow: TPCBlockAllow);
    procedure DoParseDeclBlocks(const ADecls: TList<TPCStmt>; const AAllow: TPCBlockAllow);
    function DoParseBlock(): TPCBlock;
    procedure DoParseStatementList(const AOwner: TList<TPCStmt>;
      const ATerminators: array of TPCTokenKind);
    procedure DoParseStatement(const AOwner: TList<TPCStmt>; const AInArm: Boolean);
    procedure DoParseModuleBody();
    function DoParseModuleEnd(): Boolean;
    procedure DoParseTests();
    procedure DoParseTest();
    function DoNewStringLiteral(const AToken: TPCToken): TPCLiteral;
    function DoLiteralPartOf(const AToken: TPCToken): TPCLiteralPart;
    // A decoded part's value map (P-STRPOS, research\cppmix\sem\prereq-b\strpos.md)
    function DoSpellOffsets(const AToken: TPCToken): TArray<Int64>;
    function DoSpellOffsetAt(const AOffsets: TArray<Int64>; const AIndex: Integer): Int64;
    function DoValueMapOf(const AToken: TPCToken; const AValue: string;
      const ARuns: TArray<TPCSpellRun>): TArray<TPCValueRun>;
    procedure DoAddValueRun(var ARuns: TArray<TPCValueRun>; var ACount: Integer;
      const AValueOffset: Integer; const AOffset: Int64; const AIsCopy: Boolean);
    procedure DoExpectEOF();

    // Statements (PARSER-STMT, BNF.md sec 5)
    procedure DoDispatchStatement(const AOwner: TList<TPCStmt>; const AInArm: Boolean);
    function DoParseFlowStatement(const AOwner: TList<TPCStmt>): Boolean;
    procedure DoParseBlockStatement(const AOwner: TList<TPCStmt>);
    procedure DoParseIf(const AOwner: TList<TPCStmt>);
    procedure DoParseWhile(const AOwner: TList<TPCStmt>);
    procedure DoParseFor(const AOwner: TList<TPCStmt>);
    function DoParseForHeader(const ANode: TPCFor): Boolean;
    procedure DoParseRepeat(const AOwner: TList<TPCStmt>);
    procedure DoParseMatch(const AOwner: TList<TPCStmt>);
    procedure DoParseMatchArm(const AMatch: TPCMatch);
    function DoParseMatchLabels(const AArm: TPCMatchArm): Boolean;
    procedure DoParseArmStatements(const AOwner: TList<TPCStmt>);
    function DoIsArmStart(): Boolean;
    procedure DoParseGuard(const AOwner: TList<TPCStmt>);
    procedure DoParseReturn(const AOwner: TList<TPCStmt>);
    procedure DoParseKeywordOnly(const AOwner: TList<TPCStmt>; const ANode: TPCStmt);
    procedure DoParseExprStatement(const AOwner: TList<TPCStmt>);
    procedure DoParseDirectiveStatement(const AOwner: TList<TPCStmt>);
    function DoParseHeaderEnd(const AHeaderOk: Boolean; const AKeyword: TPCTokenKind;
      const AWhat: string): Boolean;
    procedure DoParseCompoundEnd();
    function DoIsModuleItemStart(): Boolean;
    function DoExpectEnd(): Boolean;
    procedure DoFinishSimple(const AOwner: TList<TPCStmt>; const ANode: TPCStmt;
      var ARange: TSourceRange);
    procedure DoKeepRecovered(const AOwner: TList<TPCStmt>; const ANode: TPCStmt;
      var ARange: TSourceRange);
    procedure DoReportPlacementInBody(const AOwner: TList<TPCStmt>);
    procedure DoReportCppStatement(const AOwner: TList<TPCStmt>; const AHint: string);
    procedure DoReportStrayCloser(const AOwner: TList<TPCStmt>);
    procedure DoSkipLeadingSpan(const AOwner: TList<TPCStmt>);
    procedure DoSkipCppStatement();
    class function DoFindCppStmtHint(const AKind: TPCTokenKind; out AHint: string): Boolean; static;

    // Attempts, balanced scans, recovery (PARSER-EXPR-A)
    function DoSaveAttempt(): TPCAttempt;
    procedure DoRestoreAttempt(const AAttempt: TPCAttempt);
    function DoAttemptClean(const AAttempt: TPCAttempt): Boolean;
    function DoScanBalanced(out ALast: Integer): Boolean;
    procedure DoReportNeverClosed(const AOpen: TPCToken);
    procedure DoSkipBalancedTo(const AStops: array of TPCTokenKind);
    procedure DoSkipPastParen(const AStops: array of TPCTokenKind);
    procedure DoFillVerbatimUpTo(const AFirst: Integer; const ALast: Integer;
      const ALastToken: TPCToken; var AVerbatim: TPCVerbatim);
    function DoIsRecoveryStop(): Boolean;
    procedure DoSkipItem();
    procedure DoRecoverItem(const ADecl: TPCDecl; var ARange: TSourceRange);
    procedure DoSkipMember();

    // Expressions (PARSER-EXPR-B replaces the stub)
    function DoParseExpression(const AContext: TPCExprContext): TPCExpr;
    function DoParseConstExprIn(const AStops: array of TPCTokenKind): TPCExpr;
    function DoParseRange(out ALow: TPCExpr; out AHigh: TPCExpr;
      const ACloser: TPCTokenKind): Boolean;

    // Declarations (PARSER-EXPR-A, BNF.md sec 3)
    procedure DoParseDeclaration(const AOwner: TList<TPCStmt>; const AExported: Boolean);
    procedure DoParseDeclBlock(const AOwner: TList<TPCStmt>; const ABlockKind: TPCTokenKind;
      const AExported: Boolean; const AInArm: Boolean);
    function DoIsItemStart(const ABlockKind: TPCTokenKind): Boolean;
    function DoIsItemShape(): Boolean;
    function DoIsBodyStart(): Boolean;
    function DoParseVarDecl(const AExported: Boolean; const AFollow: TPCFollowContext): TPCVarDecl;
    function DoParseConstDecl(const AExported: Boolean;
      const AFollow: TPCFollowContext): TPCConstDecl;
    function DoParseTypeDecl(const AExported: Boolean; const AFollow: TPCFollowContext): TPCTypeDecl;
    function DoParseRoutineDecl(const AExported: Boolean): TPCRoutine;
    function DoParseForward(const AExported: Boolean): TPCDecl;
    function DoParseLinkage(): TPCLinkage;
    function DoParseSignature(const ARoutine: TPCRoutine; const AFollow: TPCFollowContext): Boolean;
    function DoParseParamList(const AParams: TList<TPCParam>;
      out AIsVariadic: Boolean; out AVariadicRange: TSourceRange): Boolean;
    function DoParseParam(): TPCParam;
    function DoParseExternalClause(var AExternal: TPCExternal;
      const AFollow: TPCFollowContext): Boolean;

    // Types (PARSER-EXPR-A, BNF.md sec 4)
    class function DoTypeFailed(const AType: TPCTypeExpr): Boolean; static;
    function DoRecoverType(const AType: TPCTypeExpr; var ARange: TSourceRange): TPCTypeExpr;
    procedure DoRecoverMember(const AItem: TPCMemberItem; var ARange: TSourceRange);
    function DoParseTypeExpr(): TPCTypeExpr;
    function DoParseTypeForm(): TPCTypeExpr;
    function DoParseTypeDef(): TPCTypeExpr;
    function DoNewBuiltin(): TPCTypeExpr;
    function DoParseQualifiedType(): TPCNamedType;
    procedure DoReportPrimitiveSuffix(const AType: TPCToken; const ASuffix: TPCToken);
    function DoParseCppType(): TPCTypeExpr;
    function DoParseCv(var AFlags: TPCCvFlags): Boolean;
    function DoParseNameParts(const AType: TPCCppType): Boolean;
    function DoParseNamePart(const AAfterScope: Boolean;
      const AMode: TPCTemplateMode): TPCNamePart;
    function DoParseDecltypeHead(const AType: TPCCppType): Boolean;
    function DoParseTemplateArgs(const APart: TPCNamePart;
      const AMode: TPCTemplateMode): Boolean;
    function DoParseTemplateArg(const AMode: TPCTemplateMode): TPCTemplateArg;
    function DoParseCppTypeId(const AMode: TPCTemplateMode): TPCTemplateArg;
    procedure DoReportArgsOpen(const AMode: TPCTemplateMode);
    function DoSplitIfGreaterFamily(): Boolean;
    function DoIsTemplateArgEnd(): Boolean;
    function DoParsePointerType(): TPCTypeExpr;
    function DoIsOwnerTypeAt(const AOffset: Integer; out AKind: TPCOwnerKind): Boolean;
    function DoParseOwnerType(const AKind: TPCOwnerKind): TPCTypeExpr;
    function DoParseOwnerNew(const AKind: TPCOwnerKind): TPCExpr;
    function DoParseArrayType(): TPCTypeExpr;
    function DoParseSetType(): TPCTypeExpr;
    function DoParseRoutineType(): TPCTypeExpr;
    function DoParseRecordType(const AIsObject: Boolean): TPCTypeExpr;
    function DoParseInterfaceType(): TPCTypeExpr;
    function DoParseImplements(const ARec: TPCRecordType): Boolean;
    function DoParseRecordPrefix(const ARec: TPCRecordType; const AStore: Boolean): Boolean;
    function DoParseOverlayType(): TPCTypeExpr;
    procedure DoParseMembers(const AMembers: TList<TPCMemberItem>; const AKind: TPCAggKind);
    procedure DoParseMember(const AMembers: TList<TPCMemberItem>; const AKind: TPCAggKind);
    procedure DoSetHidden(const AItem: TPCMemberItem; const AHidden: Boolean;
      const AHiddenRange: TSourceRange; const AKind: TPCAggKind);
    function DoIsHiddenWord(): Boolean;
    function DoIsDispatchWordAt(const AOffset: Integer): Boolean;
    function DoDispatchRun(const AOffset: Integer): Integer;
    procedure DoParseDispatchWords(const AItem: TPCMethodItem);
    function DoParseAbstractBody(const AItem: TPCMethodItem): Boolean;
    function DoParseField(): TPCField;
    function DoIsEmbedAt(const AOffset: Integer): Boolean;
    function DoParseEmbed(): TPCField;
    function DoIsPropertyAt(const AOffset: Integer): Boolean;
    function DoPropertyRun(const AOffset: Integer): Integer;
    function DoIsWriteAt(const AOffset: Integer): Boolean;
    function DoParseProperty(const AInInterface: Boolean): TPCPropertyItem;
    procedure DoParsePropertyWords(const AProperty: TPCPropertyItem);
    function DoParseIndexParam(const AProperty: TPCPropertyItem): Boolean;
    function DoParseAccessor(const AProperty: TPCPropertyItem; const AIsWrite: Boolean;
      const AInInterface: Boolean): TPCAccessorItem;
    function DoBorrowedParam(const AParam: TPCParam): TPCParam;
    procedure DoRecoverAccessor(const AAccessor: TPCAccessorItem; var ARange: TSourceRange);
    function DoParseAnonAggregate(const AIsOverlay: Boolean): TPCAnonAggregate;
    function DoParseAnonBody(const AIsOverlay: Boolean): TPCAnonAggregate;
    function DoParseMethodItem(const AInInterface: Boolean): TPCMethodItem;
    function DoParseInterfaceMethod(): TPCMethodItem;
    function DoIsLifecycleAt(const AOffset: Integer): Boolean;
    function DoLifecycleRun(const AOffset: Integer): Integer;
    function DoParseLifecycle(const AReported: Boolean): TPCRoutineMember;
    // PLAN-OBJECT O11 (D13)
    class function DoOperatorOf(const AKind: TPCTokenKind; out AOp: TPCBinaryOp): Boolean; static;
    function DoParseOperator(): TPCOperatorItem;
    function DoParseOperatorSignature(const ARoutine: TPCRoutine): Boolean;
    function DoParseChoicesType(): TPCTypeExpr;
    function DoParseChoiceValue(): TPCChoiceValue;
    class function DoIsUnmistakableType(const AType: TPCTypeExpr): Boolean; static;
    class function DoIsCppFundamental(const AKind: TPCTokenKind): Boolean; static;
    class function DoIsCppSuffix(const AKind: TPCTokenKind): Boolean; static;
    class function DoIsCppContinuation(const AKind: TPCTokenKind): Boolean; static;
    class function DoCvWord(const AFlags: TPCCvFlags): string; static;
    class function DoAggText(const AKind: TPCAggKind): string; static;

    // Expressions (PARSER-EXPR-B, BNF.md sec 6)
    function DoEnterNested(): Boolean;
    procedure DoLeaveNested();
    function DoParseBinary(const AMinPower: Integer; const AContext: TPCExprContext): TPCExpr;
    function DoParseBinaryLoop(const AMinPower: Integer; const AContext: TPCExprContext): TPCExpr;
    function DoCanStartTypeAt(const AOffset: Integer): Boolean;
    function DoTypeTestAt(const AOffset: Integer; out AIsCast: Boolean): Boolean;
    function DoIsRelationalAt(const AContext: TPCExprContext): Boolean;
    function DoParseTypeTest(const AOperand: TPCExpr; const AStart: TSourceRange; const AIsCast: Boolean): TPCExpr;
    procedure DoReportCppOperator(const AToken: TPCToken; const AHint: string);
    function DoParseUnary(): TPCExpr;
    function DoParsePostfix(): TPCExpr;
    function DoNewPostfixUnary(const AOperand: TPCExpr; const AOp: TPCUnaryOp): TPCExpr;
    function DoErrorExpr(const ARange: TSourceRange; const AParts: array of TPCExpr): TPCErrorExpr;
    function DoParseCall(const ACallee: TPCExpr): TPCExpr;
    function DoParseIndex(const ABase: TPCExpr): TPCExpr;
    function DoParseMemberAccess(const ABase: TPCExpr): TPCExpr;
    function DoParseBracedInit(const ABase: TPCExpr): TPCExpr;
    function DoParseArgList(const AArgs: TList<TPCExpr>; const ACloser: TPCTokenKind;
      const ACloserText: string): Boolean;
    function DoParsePrimary(): TPCExpr;
    function DoParseLiteral(const AKind: TPCLiteralKind): TPCExpr;
    function DoParseStringLiteral(): TPCExpr;
    function DoParseSpecial(const AKind: TPCSpecialKind): TPCExpr;
    function DoParseName(): TPCExpr;
    function DoIsRecordLiteral(): Boolean;
    function DoParseRecordLiteral(): TPCExpr;
    function DoRecordLiteralError(const ALiteral: TPCRecordLiteral; const ARange: TSourceRange;
      const AFailed: TPCExpr): TPCExpr;
    function DoParseTypeCast(): TPCExpr;
    function DoParsePointerCast(): TPCExpr;
    function DoParseSetLiteral(): TPCExpr;
    function DoSetLiteralError(const ASet: TPCSetLiteral; const ARange: TSourceRange;
      const ALow: TPCExpr; const AHigh: TPCExpr): TPCExpr;
    function DoParseVarargs(): TPCExpr;
    class function DoVarargsCallKind(const AWord: string;
      out AKind: TPCVarargsKind): Boolean; static;
    function DoParseVarargsArgs(const AVarargs: TPCVarargs): Boolean;
    function DoParseNew(): TPCExpr;
    function DoParseDelete(): TPCExpr;
    function DoParseNamedCast(): TPCExpr;
    function DoParseParenExpr(): TPCExpr;
    function DoParseOpaqueGroup(): TPCExpr;
    function DoParseCppExpr(): TPCExpr;
    function DoTryTemplateArgs(const APart: TPCNamePart; const AMode: TPCTemplateMode): Boolean;
    class function DoTemplateFailKey(const AAttempt: TPCAttempt;
      const AMode: TPCTemplateMode): string; static;
    class function DoInfixInfo(const AToken: TPCToken; const AContext: TPCExprContext;
      out ARow: TPCInfixRow): Boolean; static;
    class function DoPrefixInfo(const AKind: TPCTokenKind; out AOp: TPCUnaryOp;
      out AHint: string): Boolean; static;
    class function DoStartsOperandOnly(const AToken: TPCToken): Boolean; static;
    class function DoIsTemplateFollow(const AToken: TPCToken): Boolean; static;
    class function DoIsEmptyListFollow(const AKind: TPCTokenKind): Boolean; static;
    class function DoNamedCastKind(const AKind: TPCTokenKind): TPCCastKind; static;

    // Verbatim expression forms and the two tries (PARSER-EXPR-C, verbatim-expr.md)
    function DoNewVerbatimExpr(const AFirst: Integer; const ALast: Integer;
      const AKind: TPCVerbatimKind): TPCVerbatimExpr;
    function DoIsLambdaStart(): Boolean;
    function DoParseLambda(): TPCExpr;
    function DoTryCStyleCast(out AResult: TPCExpr): Boolean;
    function DoTryTypeArgAt(const ACall: TPCCall; const AIndex: Integer): Boolean;
    class function DoTypeArgSlot(const ACallee: TPCExpr; out AIndex: Integer): Boolean; static;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetErrors(const AErrors: TErrors); override;

    procedure Init(const AAst: TPCAst; const AFilename: string;
      const AImportChain: TArray<string>; const AMainTarget: TPCTargetTriple;
      const AOverrideTarget: TPCTargetTriple; const ADefaultTarget: TPCTargetTriple);
    // Adds a folder an import is searched in. An import is looked up in the
    // importing file's own folder first, then in these folders in the order
    // they were added; a folder already added is not added again. The main
    // module's @addmodulepath folders are added after the ones given here, and
    // every import's parser gets this parser's list. SetErrors first: a path
    // that cannot be resolved is PR0056, not added.
    procedure AddModulePath(const APath: string);
    // Texts that win over the disk for this file and every import (nil =
    // the disk only); the import lookup finds a file the provider has
    procedure SetSourceProvider(const AProvider: TPCSourceProvider);
    // True when the main file is only checked (the editor's LSP), never
    // built: "a unit cannot be the main module" (PR0004) is a build rule.
    // Imports are not main files; this parser alone is affected
    procedure SetUnitMainAllowed(const AAllowed: Boolean);
    function Parse(): TPCModule;
    // True when AToken can begin an operand: a prefix operator, a primary
    // form's first token, a primitive (a type cast when '(' follows). Pure;
    // the agreement test (A11 T3) keeps it equal to what DoParseUnary takes
    class function StartsOperand(const AToken: TPCToken): Boolean; static;
  end;

// Parses AFilename into AAst and registers the module (AAst.AddModule) on
// return: never nil. Main file: AImportChain nil, AMainTarget empty.
// AModulePaths: the folders added with AddModulePath before the parse, in
// order (the compiler's module paths; nil = none). AOverrideTarget: the
// build's target (CLI -t: wins over every @target of the build, the main
// file's and each import's; handed to the imports; empty = none);
// ADefaultTarget: stands in for the main file's missing @target (empty =
// none). Imports are parsed by the parser itself (DoParseImportFile).
// ASourceProvider: texts that win over the disk (nil = disk only).
// AUnitMainAllowed: the main file is checked, not built (SetUnitMainAllowed).
function ParseModuleFile(const AAst: TPCAst; const AErrors: TErrors; const AFilename: string;
  const AImportChain: TArray<string>; const AMainTarget: TPCTargetTriple;
  const AOverrideTarget: TPCTargetTriple; const ADefaultTarget: TPCTargetTriple; const AModulePaths: TArray<string>;
  const ASourceProvider: TPCSourceProvider = nil; const AUnitMainAllowed: Boolean = False): TPCModule;

implementation

uses
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.SourceText,
  PaskalCPP.CppJumps;

type
  { TPCDocAttacher }
  // Gives each declaration, field and choice value the /// block directly
  // above the line it starts on (plans\done\PLAN-EDITOR.md E2.6). The walk visits
  // a parent before its children and siblings in source order, so the FIRST
  // node starting on a line takes that line's doc (`TCol = choices(cRed)`:
  // TCol, not cRed); a node of another file (none today) is skipped
  TPCDocAttacher = class(TBaseObject)
  private
    FStream: TPCTokenStream;
    FFilename: string;
    FClaimed: TDictionary<Integer, Boolean>;
    FVisitor: TPCNodeVisitor;
    procedure DoVisit(const ANode: TPCNode);
    function DoTake(const ARange: TSourceRange): string;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    class procedure Attach(const AModule: TPCModule; const AStream: TPCTokenStream); static;
  end;

{ TPCDocAttacher }

constructor TPCDocAttacher.Create();
begin
  inherited;

  FClaimed := TDictionary<Integer, Boolean>.Create();
  FVisitor := DoVisit;
end;

destructor TPCDocAttacher.Destroy();
begin
  FClaimed.Free();

  inherited;
end;

function TPCDocAttacher.DoTake(const ARange: TSourceRange): string;
var
  LLine: Integer;
begin
  // The doc of the line ARange starts on, once per line
  Result := '';
  if (ARange.StartLine < 1) or (ARange.Filename = '') or
     not TUtils.SamePath(ARange.Filename, FFilename) then
    Exit;
  LLine := Integer(ARange.StartLine);
  if FClaimed.ContainsKey(LLine) then
    Exit;
  FClaimed.Add(LLine, True);
  Result := FStream.DocAbove(LLine);
end;

procedure TPCDocAttacher.DoVisit(const ANode: TPCNode);
begin
  if ANode is TPCDecl then
    TPCDecl(ANode).DocText := DoTake(ANode.Range)
  else if ANode is TPCField then
    TPCField(ANode).DocText := DoTake(ANode.Range)
  else if ANode is TPCChoiceValue then
    TPCChoiceValue(ANode).DocText := DoTake(ANode.Range)
  // PLAN-OBJECT O9: a property claims its line before its accessors' routines
  else if ANode is TPCPropertyItem then
    TPCPropertyItem(ANode).DocText := DoTake(ANode.Range);
  // Only those claim a line: a wrapper (a method item) starts where
  // its routine does and must not take the routine's doc
  ANode.EnumChildren(FVisitor);
end;

class procedure TPCDocAttacher.Attach(const AModule: TPCModule; const AStream: TPCTokenStream);
var
  LAttacher: TPCDocAttacher;
begin
  if (AModule = nil) or (AStream = nil) then
    Exit;
  LAttacher := TPCDocAttacher.Create();
  try
    LAttacher.FStream := AStream;
    LAttacher.FFilename := AModule.SourceFile;
    LAttacher.DoVisit(AModule);
  finally
    LAttacher.Free();
  end;
end;

const
  { PC_INFIX_ROWS }
  // BNF.md sec 6 binding table (research parser-expr\expr.md), one row per
  // token kind. Power: higher binds tighter; assign (2) and ternary (4) are
  // right associative, the rest left. Comparisons (10) do not chain
  PC_INFIX_ROWS: array[0..44] of TPCInfixRow = (
    (Kind: tkColonEqual;          Power: 2;  Shape: ixAssign;     BinOp: boAdd;       AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkPlusEqual;           Power: 2;  Shape: ixAssign;     BinOp: boAdd;       AssignOp: aoAddAssign;    IsCppForm: False; CppHint: ''),
    (Kind: tkMinusEqual;          Power: 2;  Shape: ixAssign;     BinOp: boAdd;       AssignOp: aoSubAssign;    IsCppForm: False; CppHint: ''),
    (Kind: tkStarEqual;           Power: 2;  Shape: ixAssign;     BinOp: boAdd;       AssignOp: aoMulAssign;    IsCppForm: False; CppHint: ''),
    (Kind: tkSlashEqual;          Power: 2;  Shape: ixAssign;     BinOp: boAdd;       AssignOp: aoDivAssign;    IsCppForm: False; CppHint: ''),
    (Kind: tkPercentEqual;        Power: 2;  Shape: ixAssign;     BinOp: boAdd;       AssignOp: aoModAssign;    IsCppForm: False; CppHint: ''),
    (Kind: tkAmpEqual;            Power: 2;  Shape: ixAssign;     BinOp: boAdd;       AssignOp: aoBitAndAssign; IsCppForm: False; CppHint: ''),
    (Kind: tkPipeEqual;           Power: 2;  Shape: ixAssign;     BinOp: boAdd;       AssignOp: aoBitOrAssign;  IsCppForm: False; CppHint: ''),
    (Kind: tkLessLessEqual;       Power: 2;  Shape: ixAssign;     BinOp: boAdd;       AssignOp: aoShlAssign;    IsCppForm: False; CppHint: ''),
    (Kind: tkGreaterGreaterEqual; Power: 2;  Shape: ixAssign;     BinOp: boAdd;       AssignOp: aoShrAssign;    IsCppForm: False; CppHint: ''),
    (Kind: tkKwAnd_eq;            Power: 2;  Shape: ixAssign;     BinOp: boAdd;       AssignOp: aoBitAndAssign; IsCppForm: True;  CppHint: '&='),
    (Kind: tkKwOr_eq;             Power: 2;  Shape: ixAssign;     BinOp: boAdd;       AssignOp: aoBitOrAssign;  IsCppForm: True;  CppHint: '|='),
    (Kind: tkQuestion;            Power: 4;  Shape: ixTernary;    BinOp: boAdd;       AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkKwOr;                Power: 6;  Shape: ixBinary;     BinOp: boLogOr;     AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkPipePipe;            Power: 6;  Shape: ixBinary;     BinOp: boLogOr;     AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkKwAnd;               Power: 8;  Shape: ixBinary;     BinOp: boLogAnd;    AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkAmpAmp;              Power: 8;  Shape: ixBinary;     BinOp: boLogAnd;    AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkEqual;               Power: 10; Shape: ixRelational; BinOp: boEq;        AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkLessGreater;         Power: 10; Shape: ixRelational; BinOp: boNotEq;     AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkLess;                Power: 10; Shape: ixRelational; BinOp: boLess;      AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkGreater;             Power: 10; Shape: ixRelational; BinOp: boGreater;   AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkLessEqual;           Power: 10; Shape: ixRelational; BinOp: boLessEq;    AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkGreaterEqual;        Power: 10; Shape: ixRelational; BinOp: boGreaterEq; AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkLessEqualGreater;    Power: 10; Shape: ixRelational; BinOp: boThreeWay;  AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkKwIn;                Power: 10; Shape: ixRelational; BinOp: boIn;        AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkEqualEqual;          Power: 10; Shape: ixRelational; BinOp: boEq;        AssignOp: aoAssign;       IsCppForm: True;  CppHint: '='),
    (Kind: tkBangEqual;           Power: 10; Shape: ixRelational; BinOp: boNotEq;     AssignOp: aoAssign;       IsCppForm: True;  CppHint: '<>'),
    (Kind: tkKwNot_eq;            Power: 10; Shape: ixRelational; BinOp: boNotEq;     AssignOp: aoAssign;       IsCppForm: True;  CppHint: '<>'),
    (Kind: tkPlus;                Power: 20; Shape: ixBinary;     BinOp: boAdd;       AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkMinus;               Power: 20; Shape: ixBinary;     BinOp: boSub;       AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkPipe;                Power: 20; Shape: ixBinary;     BinOp: boBitOr;     AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkKwXor;               Power: 20; Shape: ixBinary;     BinOp: boBitXor;    AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkKwBitor;             Power: 20; Shape: ixBinary;     BinOp: boBitOr;     AssignOp: aoAssign;       IsCppForm: True;  CppHint: '|'),
    (Kind: tkKwXor_eq;            Power: 20; Shape: ixBinary;     BinOp: boBitXor;    AssignOp: aoAssign;       IsCppForm: True;  CppHint: ''),
    (Kind: tkKwShl;               Power: 25; Shape: ixBinary;     BinOp: boShl;       AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkLessLess;            Power: 25; Shape: ixBinary;     BinOp: boShl;       AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkKwShr;               Power: 25; Shape: ixBinary;     BinOp: boShr;       AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkGreaterGreater;      Power: 25; Shape: ixBinary;     BinOp: boShr;       AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkStar;                Power: 30; Shape: ixBinary;     BinOp: boMul;       AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkSlash;               Power: 30; Shape: ixBinary;     BinOp: boDiv;       AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkKwDiv;               Power: 30; Shape: ixBinary;     BinOp: boIntDiv;    AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkKwMod;               Power: 30; Shape: ixBinary;     BinOp: boMod;       AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkPercent;             Power: 30; Shape: ixBinary;     BinOp: boMod;       AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkAmp;                 Power: 30; Shape: ixBinary;     BinOp: boBitAnd;    AssignOp: aoAssign;       IsCppForm: False; CppHint: ''),
    (Kind: tkKwBitand;            Power: 30; Shape: ixBinary;     BinOp: boBitAnd;    AssignOp: aoAssign;       IsCppForm: True;  CppHint: '&')
  );

  { PC_PAR_TYPE_TEST_POWER }
  // PLAN-OBJECT O12 (BNF.md sec 6): `is` binds as a rel op (10, no chain),
  // `as` as a mul op (30, left associative); indexed by IsCast. The context
  // words are identifiers, so they are no PC_INFIX_ROWS row
  PC_PAR_TYPE_TEST_POWER: array[Boolean] of Integer = (10, 30);

  { PC_PAR_CPP_STMT_HINTS }
  // C++ statement keywords in a body and the PaskalCPP form PR0049 names
  // (BNF.md sec 5, parser.md "Statements"); C++ kept as C++ goes in cppstart
  PC_PAR_CPP_STMT_HINTS: array[0..9] of TPCCppStmtHint = (
    (Kind: tkKwSwitch;        Hint: '''match'''),
    (Kind: tkKwCase;          Hint: '''match'' labels'),
    (Kind: tkKwDefault;       Hint: '''match ... else'''),
    (Kind: tkKwTry;           Hint: '''guard'''),
    (Kind: tkKwCatch;         Hint: '''guard ... except'''),
    (Kind: tkKwThrow;         Hint: '''raise(...)'''),
    (Kind: tkKwBreak;         Hint: '''leave'''),
    (Kind: tkKwContinue;      Hint: '''skip'''),
    (Kind: tkKwGoto;          Hint: '''cppstart source ... cppend;'''),
    (Kind: tkKwStatic_assert; Hint: '''cppstart source ... cppend;''')
  );

  { PC_PAR_STMT_STARTERS }
  // Tokens that start a statement and never an expression: in a match arm they
  // are never tried as the next arm's labels (DoParseArmStatements)
  PC_PAR_STMT_STARTERS: array[0..15] of TPCTokenKind = (
    tkKwBegin, tkKwIf, tkKwWhile, tkKwFor, tkKwRepeat, tkKwMatch, tkKwGuard,
    tkKwReturn, tkKwLeave, tkKwSkip, tkKwVar, tkKwConst, tkKwType, tkKwCppstart,
    tkCppPreprocessor, tkDirective
  );

  { PC_PAR_STRAY_CLOSERS }
  // ';' alone and words that only close or continue another construct: in
  // statement position each is "expected a statement" (DoReportStrayCloser)
  PC_PAR_STRAY_CLOSERS: array[0..9] of TPCTokenKind = (
    tkSemicolon, tkKwElse, tkKwUntil, tkKwExcept, tkKwFinally, tkKwThen, tkKwDo,
    tkKwOf, tkKwTo, tkKwDownto
  );

  { PC_PAR_END_OPENERS }
  // Words whose construct closes with its own 'end' (a repeat closes with
  // 'until'): a skip over a statement nobody parsed counts them, so the
  // statement's 'end' is never taken for the enclosing list's
  // (DoSkipRefusedStatement)
  PC_PAR_END_OPENERS: array[0..8] of TPCTokenKind = (
    tkKwBegin, tkKwIf, tkKwWhile, tkKwFor, tkKwMatch, tkKwGuard, tkKwRecord, tkKwObject,
    tkKwOverlay
  );

  { PC_PAR_MODULE_ITEM_STARTS }
  // Words that only start a module-level item: no statement starts with one
  // (DoParseDeclBlocks), so an open statement list ends before it
  PC_PAR_MODULE_ITEM_STARTS: array[0..6] of TPCTokenKind = (
    tkKwRoutine, tkKwForward, tkKwExported, tkKwTest, tkKwInitialize, tkKwFinalize,
    tkKwImport
  );

  { PC_PAR_KIND_NAMES }
  // The keyword of each module kind, for messages (a spelling, not prose)
  PC_PAR_KIND_NAMES: array[TPCModuleKind] of string = ('exe', 'dll', 'lib', 'unit');

  { PC_PAR_CPP_HEADER }
  // The target words after cpp / cppstart (BNF.md sec 10), matched by Spelling
  PC_PAR_CPP_HEADER = 'header';
  { PC_PAR_CPP_SOURCE }
  PC_PAR_CPP_SOURCE = 'source';
  { PC_PAR_SIZE_NAME }
  // The intrinsic whose argument may be a type (BNF.md sec 7), matched by Spelling
  PC_PAR_SIZE_NAME = 'size';

{ ParseModuleFile }

function ParseModuleFile(const AAst: TPCAst; const AErrors: TErrors; const AFilename: string;
  const AImportChain: TArray<string>; const AMainTarget: TPCTargetTriple;
  const AOverrideTarget: TPCTargetTriple; const ADefaultTarget: TPCTargetTriple; const AModulePaths: TArray<string>;
  const ASourceProvider: TPCSourceProvider; const AUnitMainAllowed: Boolean): TPCModule;
var
  LParser: TPCParser;
  LPath: string;
begin
  LParser := TPCParser.Create();
  try
    LParser.SetErrors(AErrors);
    LParser.Init(AAst, AFilename, AImportChain, AMainTarget, AOverrideTarget, ADefaultTarget);
    for LPath in AModulePaths do
      LParser.AddModulePath(LPath);
    LParser.SetSourceProvider(ASourceProvider);
    LParser.SetUnitMainAllowed(AUnitMainAllowed);
    Result := LParser.Parse();
  finally
    LParser.Free();
  end;

  // Registered on return: completion order = dependency order (research\cppmix\ast.md)
  AAst.AddModule(Result);
end;

{ TPCParser }

constructor TPCParser.Create();
begin
  inherited;

  FLexer := TPCLexer.Create();
  FFilter := TPCConditionalFilter.Create();
  FRawStream := TPCTokenStream.Create();
  FStream := TPCTokenStream.Create();
  FCursor := FStream;
  FAst := nil;
  FModule := nil;
  FSourceProvider := nil;
  FUnitMainAllowed := False;
  FLastToken.Clear();
  FTemplateFails := TDictionary<string, Boolean>.Create();
end;

destructor TPCParser.Destroy();
begin
  FTemplateFails.Free();
  FStream.Free();
  FRawStream.Free();
  FFilter.Free();
  FLexer.Free();

  inherited;
end;

procedure TPCParser.SetErrors(const AErrors: TErrors);
begin
  inherited;

  FLexer.SetErrors(AErrors);
  FFilter.SetErrors(AErrors);
  FRawStream.SetErrors(AErrors);
  FStream.SetErrors(AErrors);
end;

procedure TPCParser.Init(const AAst: TPCAst; const AFilename: string;
  const AImportChain: TArray<string>; const AMainTarget: TPCTargetTriple;
  const AOverrideTarget: TPCTargetTriple; const ADefaultTarget: TPCTargetTriple);
begin
  // The module paths are not touched: AddModulePath may come before or after
  FAst := AAst;
  FFilename := AFilename;
  FImportChain := AImportChain;
  FMainTarget := AMainTarget;
  FOverrideTarget := AOverrideTarget;
  FDefaultTarget := ADefaultTarget;
end;

procedure TPCParser.AddModulePath(const APath: string);
var
  LResolved: string;
begin
  // Resolved once here; everything later compares and searches the resolved
  // spelling (PROJECT.md: every path through TUtils.ResolvePath)
  try
    LResolved := TUtils.ResolvePath(APath);
  except
    on E: Exception do
    begin
      FErrors.Add(esError, PC_ERR_PAR_056, RSParModulePathResolve, [APath, E.Message]);
      Exit;
    end;
  end;
  DoAddSearchPath(LResolved);
end;

function TPCParser.Parse(): TPCModule;
var
  LRange: TSourceRange;
  LEndOk: Boolean;
  LMark: TPCSkipMark;
begin
  FModule := FAst.NewNode<TPCModule>();
  FKindAssumed := False;
  FHasLast := False;
  FLastToken.Clear();
  FPlacement := etSource;
  FEofReported := False;
  FEndReported := False;
  FEndReportedAt := 0;
  FExprDepth := 0;
  FStmtDepth := 0;
  FTemplateFails.Clear();

  // No text (TokenizeBytes / TokenizeFile False: an unreadable file, invalid
  // UTF-8): the module is still built, from its header read quietly (nothing
  // to read), so an importer finds it by file
  if not DoTokenizeSource() then
  begin
    FCursor := FRawStream;
    FModule.SourceFile := FRawStream.SourceFilename();
    // The filter never ran, so the target is the one the context gives: an
    // imported file takes the main module's triple, the main file the build's
    // override when set, else the build's default, else the language default
    // (no @target was read)
    if DoIsMain() and not FOverrideTarget.IsEmpty() then
      FModule.ResolvedTarget := FOverrideTarget
    else if DoIsMain() and not FDefaultTarget.IsEmpty() then
      FModule.ResolvedTarget := FDefaultTarget
    else if DoIsMain() then
      FModule.ResolvedTarget := TPCTargetTriple.DefaultTriple()
    else
      FModule.ResolvedTarget := FMainTarget;
    LRange := DoStartRange();
    DoReadHeaderQuiet();
    DoFinishRange(LRange);
    FModule.Range := LRange;
    Exit(FModule);
  end;

  // The filter reports its own errors; its output always ends with EOF
  FFilter.Filter(FRawStream, FStream, FMainTarget, FOverrideTarget, FDefaultTarget);
  DoRecordDropped();
  FCursor := FStream;
  // A lexer span that runs to the end of the file (an unterminated comment,
  // raw string or cppstart) is the root cause of everything still open
  // there: the end of file counts as reported (R7)
  FEofReported := DoEndsInReportedSpan();
  FModule.SourceFile := FStream.SourceFilename();
  FModule.ResolvedTarget := FFilter.Target();

  LRange := DoStartRange();
  DoParseHeader();
  DoParsePrologue();
  DoCollectModulePaths();
  DoParseImportClause();
  DoParseModuleDecls();
  DoParseSections();
  DoParseModuleBody();
  // A broken end is reported once; the tests after it are still parsed (a
  // test is unmistakable), and whatever else follows is one error node: no
  // second report for the same root cause (PLAN-RECOVERY)
  LEndOk := DoParseModuleEnd();
  DoParseTests();
  if LEndOk then
    DoExpectEOF()
  else if not DoCheck(tkEOF) then
  begin
    LMark := DoMarkSkip();
    while not DoCheck(tkEOF) do
      DoAdvance();
    DoAddSkipped(FModule.Decls, LMark);
  end;
  DoFinishRange(LRange);
  FModule.Range := LRange;
  // Doc comments: the lexer's stream holds the /// lines (E2.6)
  TPCDocAttacher.Attach(FModule, FRawStream);
  Result := FModule;
end;

function TPCParser.DoIsMain(): Boolean;
begin
  Result := Length(FImportChain) = 0;
end;

function TPCParser.DoAssumedKind(): TPCModuleKind;
begin
  // The kind the context requires, so nothing downstream cascades: an imported
  // file must be a unit (no PR0013), the main file an exe
  if DoIsMain() then
    Result := mkExe
  else
    Result := mkUnit;
end;

function TPCParser.DoCurrent(): TPCToken;
begin
  Result := FCursor.CurrentToken();
end;

function TPCParser.DoPeek(const AOffset: Integer): TPCToken;
begin
  Result := FCursor.PeekToken(AOffset);
end;

function TPCParser.DoIsWord(const AWord: TPCContextWord): Boolean;
begin
  // The one table (PC_CONTEXT_WORDS): a word never reserved, read here only
  Result := PC_CONTEXT_WORDS[AWord].Matches(DoCurrent());
end;

function TPCParser.DoIsWordAt(const AWord: TPCContextWord; const AOffset: Integer): Boolean;
begin
  // DoIsWord at the token AOffset ahead (0 = the current one)
  Result := PC_CONTEXT_WORDS[AWord].Matches(DoPeek(AOffset));
end;

procedure TPCParser.DoAdvance();
var
  LToken: TPCToken;
begin
  // The only way the parser consumes a token, so FLastToken is always the
  // last one consumed. EOF is never consumed.
  LToken := FCursor.CurrentToken();
  if LToken.Kind = tkEOF then
    Exit;
  FLastToken := LToken;
  FHasLast := True;
  FCursor.NextToken();
end;

function TPCParser.DoCheck(const AKind: TPCTokenKind): Boolean;
begin
  Result := DoCurrent().Kind = AKind;
end;

function TPCParser.DoMatch(const AKind: TPCTokenKind): Boolean;
begin
  Result := DoCheck(AKind);
  if Result then
    DoAdvance();
end;

function TPCParser.DoExpect(const AKind: TPCTokenKind; const AWhat: string): Boolean;
var
  LToken: TPCToken;
begin
  // Hit: consumed. Miss: PR0001, nothing consumed. A missing ';' is reported
  // just after the token it should follow (as clang does): the fix goes
  // there, while the token that came next may be lines later. Any other
  // missing token is reported at the token found in its place
  LToken := DoCurrent();
  if LToken.Kind = AKind then
  begin
    DoAdvance();
    Exit(True);
  end;
  if AKind = tkSemicolon then
    DoError(DoAfterLast(LToken), PC_ERR_PAR_001, RSParExpected, [AWhat, DoTokenText(LToken)])
  else
    DoError(LToken, PC_ERR_PAR_001, RSParExpected, [AWhat, DoTokenText(LToken)]);
  Result := False;
end;

function TPCParser.DoAfterLast(const AFound: TPCToken): TPCToken;
begin
  // AFound placed at the position just after the last consumed token (one
  // byte past its inclusive end, TPCToken.Range); its kind is kept, so the
  // end of file is still reported once (DoError). Nothing consumed yet:
  // AFound itself
  Result := AFound;
  if not FHasLast then
    Exit;
  Result.Range.Filename := FLastToken.Range.Filename;
  Result.Range.StartLine := FLastToken.Range.EndLine;
  Result.Range.StartColumn := FLastToken.Range.EndColumn + 1;
  Result.Range.StartByteOffset := FLastToken.Range.EndByteOffset + 1;
  Result.Range.EndLine := Result.Range.StartLine;
  Result.Range.EndColumn := Result.Range.StartColumn;
  Result.Range.EndByteOffset := Result.Range.StartByteOffset;
end;

function TPCParser.DoStartRange(): TSourceRange;
var
  LToken: TPCToken;
begin
  // Starts at the current token; until DoFinishRange it is that token's own
  LToken := DoCurrent();
  Result.Clear();
  Result.Filename := LToken.Range.Filename;
  Result.StartLine := LToken.Range.StartLine;
  Result.StartColumn := LToken.Range.StartColumn;
  Result.StartByteOffset := LToken.Range.StartByteOffset;
  Result.EndLine := LToken.Range.EndLine;
  Result.EndColumn := LToken.Range.EndColumn;
  Result.EndByteOffset := LToken.Range.EndByteOffset;
end;

procedure TPCParser.DoFinishRange(var ARange: TSourceRange);
begin
  // Ends at the last consumed token; nothing consumed since the start keeps
  // the start token's own end
  if not FHasLast then
    Exit;
  if FLastToken.Range.EndByteOffset <= ARange.StartByteOffset then
    Exit;
  ARange.EndLine := FLastToken.Range.EndLine;
  ARange.EndColumn := FLastToken.Range.EndColumn;
  ARange.EndByteOffset := FLastToken.Range.EndByteOffset;
end;

procedure TPCParser.DoError(const AToken: TPCToken; const ACode: string;
  const AMessage: string; const AArgs: array of const);
begin
  // A tkUnknown is a span the lexer reported: its report is the one report
  // (D1); recovery around it still leaves its node (PLAN-RECOVERY, R7)
  if AToken.Kind = tkUnknown then
    Exit;
  // The end of file is reported once: everything still open there (a block,
  // its ';', the module's end) has that one root cause
  if AToken.Kind = tkEOF then
  begin
    if FEofReported then
      Exit;
    FEofReported := True;
  end;
  FErrors.Add(AToken.Range, esError, ACode, AMessage, AArgs);
end;

procedure TPCParser.DoErrorAt(const ARange: TSourceRange; const ACode: string;
  const AMessage: string; const AArgs: array of const);
begin
  // A report at a part the parser already read (a node's range): no lexer
  // span or end of file can be one, so DoError's token rules do not apply
  FErrors.Add(ARange, esError, ACode, AMessage, AArgs);
end;

procedure TPCParser.DoWarning(const AToken: TPCToken; const ACode: string;
  const AMessage: string; const AArgs: array of const);
begin
  FErrors.Add(AToken.Range, esWarning, ACode, AMessage, AArgs);
end;

function TPCParser.DoStopped(): Boolean;
begin
  // The error budget bounds every loop (parser.md P3)
  Result := FErrors.ReachedMaxErrors();
end;

function TPCParser.DoIsFrameStop(): Boolean;
begin
  // A token a module-level recovery skip never passes (PLAN-RECOVERY): the
  // start of a module-level item, a declaration, a body or section, the
  // module's end. 'routine(' is a routine type, no stop (DoIsModuleItemStart)
  if DoCheck(tkKwRoutine) then
    Exit(DoIsModuleItemStart());
  Result := DoIsModuleItemStart() or DoIsRecoveryStop();
end;

procedure TPCParser.DoSkipFrame();
begin
  // Recovery outside a statement list: through the next ';', never past a
  // frame stop (not consumed) or EOF. Nothing is consumed when the current
  // token is a stop: what failed ends there
  while (not DoCheck(tkEOF)) and (not DoIsFrameStop()) do
  begin
    if DoCheck(tkSemicolon) then
    begin
      DoAdvance();
      Exit;
    end;
    DoAdvance();
  end;
end;

function TPCParser.DoIsModuleEnd(): Boolean;
begin
  Result := DoCheck(tkKwEnd) and (DoPeek(1).Kind = tkDot);
end;

function TPCParser.DoHasModuleEndAhead(): Boolean;
var
  LOffset: Integer;
  LKind: TPCTokenKind;
begin
  // Peek only: an 'end' followed by '.' at or after the current token
  LOffset := 0;
  repeat
    LKind := DoPeek(LOffset).Kind;
    if (LKind = tkKwEnd) and (DoPeek(LOffset + 1).Kind = tkDot) then
      Exit(True);
    Inc(LOffset);
  until LKind = tkEOF;
  Result := False;
end;

function TPCParser.DoMarkSkip(): TPCSkipMark;
begin
  // Taken before a recovery skip: where it starts
  Result.TokenIndex := DoCurrentIndex();
  Result.Range := DoStartRange();
end;

function TPCParser.DoAddSkipped(const AOwner: TList<TPCStmt>;
  const AMark: TPCSkipMark): TPCErrorStmt;
var
  LRange: TSourceRange;
begin
  // The tokens a recovery skip consumed since AMark become one error node in
  // AOwner, so no source is dropped silently (PLAN-RECOVERY target 1). nil =
  // nothing was consumed
  Result := nil;
  if DoCurrentIndex() = AMark.TokenIndex then
    Exit;
  LRange := AMark.Range;
  DoFinishRange(LRange);
  Result := FAst.NewNode<TPCErrorStmt>();
  Result.Range := LRange;
  AOwner.Add(Result);
end;

function TPCParser.DoAddSkippedMember(const AOwner: TList<TPCMemberItem>;
  const AMark: TPCSkipMark): TPCErrorMember;
var
  LRange: TSourceRange;
begin
  // DoAddSkipped for a member list (a generic list is invariant)
  Result := nil;
  if DoCurrentIndex() = AMark.TokenIndex then
    Exit;
  LRange := AMark.Range;
  DoFinishRange(LRange);
  Result := FAst.NewNode<TPCErrorMember>();
  Result.Range := LRange;
  AOwner.Add(Result);
end;

class function TPCParser.DoFailed(const AExpr: TPCExpr): Boolean;
begin
  // An expression that reported: nothing (nil) or what parsed before the
  // failure (TPCErrorExpr, PLAN-RECOVERY)
  Result := (AExpr = nil) or (AExpr is TPCErrorExpr);
end;

function TPCParser.DoExpectTerminator(const AFollow: TPCFollowContext): TPCTerminatorOutcome;
begin
  // The ';' after a complete construct (PLAN-RECOVERY target 4, r4): a miss
  // is PR0001 just after the last token (DoExpect); nothing is skipped when
  // the current token can start what may follow in AFollow (the grammar's
  // FIRST set, never the layout)
  if DoExpect(tkSemicolon, DoSpelled(';')) then
    Exit(toConsumed);
  if DoCanFollow(AFollow) then
    Result := toInserted
  else
    Result := toMissing;
end;

function TPCParser.DoCanFollow(const AFollow: TPCFollowContext): Boolean;
begin
  case AFollow of
    fcModule:
      Result := True;
    fcStatement:
      Result := DoCanStartStatement();
    fcVarItem:
      Result := DoCanFollowItem(tkKwVar);
    fcConstItem:
      Result := DoCanFollowItem(tkKwConst);
    fcTypeItem:
      Result := DoCanFollowItem(tkKwType);
    fcSignature:
      Result := DoIsBodyStart() or DoCheck(tkKwExternal);
    fcMember:
      Result := DoCanFollowMember();
  else
    Result := False;
  end;
end;

function TPCParser.DoCanFollowMember(): Boolean;
var
  LKind: TPCTokenKind;
begin
  // DoParseMember's starts, the aggregate's end, or a token the member loop
  // stops at (DoParseMembers: EOF, a recovery stop)
  LKind := DoCurrent().Kind;
  if (LKind = tkIdentifier) and (DoPeek(1).Kind = tkColon) then
    Exit(True);
  // PLAN-OBJECT D7 / D10: a method's words ([virtual | override] [final]
  // method) and 'hidden' before a field or a method start a member too
  if DoDispatchRun(0) >= 0 then
    Exit(True);
  // PLAN-OBJECT D3: an init or a done (after any word wrongly put before it)
  if DoLifecycleRun(0) >= 0 then
    Exit(True);
  // PLAN-OBJECT O8: an embed
  if DoIsEmbedAt(0) then
    Exit(True);
  // PLAN-OBJECT O9 / O10: a property (after its words), and a property's
  // write or default after its read
  if (DoPropertyRun(0) >= 0) or DoIsWriteAt(0) or DoIsWord(cwDefault) then
    Exit(True);
  if DoIsHiddenWord() then
    Exit(True);
  // PLAN-OBJECT O11: an operator
  Result := DoIsOneOf(LKind, [tkKwOverlay, tkKwRecord, tkKwOperator, tkKwEnd, tkEOF]) or
    DoIsRecoveryStop();
end;

function TPCParser.DoCanFollowItem(const ABlockKind: TPCTokenKind): Boolean;
begin
  // Inside a routine: the next item of the block (DoIsItemStart), a recovery
  // stop (another block, begin, a declaration: DoIsRecoveryStop), and in a
  // body also any statement (the block is one statement of the list)
  Result := DoIsItemStart(ABlockKind) or DoIsRecoveryStop() or
    ((FStmtDepth > 0) and DoCanStartStatement());
end;

function TPCParser.DoCanStartStatement(): Boolean;
var
  LKind: TPCTokenKind;
  LHint: string;
begin
  // DoDispatchStatement's branches as a predicate. A token that closes a
  // statement list ends the list here (DoSkipStatement stops before the same
  // tokens); a stray closer starts nothing; anything else that is no
  // statement keyword must start an expression
  LKind := DoCurrent().Kind;
  if DoIsOneOf(LKind, [tkEOF, tkKwEnd, tkKwElse, tkKwUntil, tkKwExcept, tkKwFinally]) then
    Exit(True);
  // A module-level item start also ends the list (A3 step 18, F1)
  if DoIsModuleItemStart() then
    Exit(True);
  if DoIsOneOf(LKind, PC_PAR_STRAY_CLOSERS) then
    Exit(False);
  if DoIsOneOf(LKind, PC_PAR_STMT_STARTERS) or (LKind = tkKwCpp) then
    Exit(True);
  if DoFindCppStmtHint(LKind, LHint) then
    Exit(True);
  Result := StartsOperand(DoCurrent());
end;

class function TPCParser.DoTokenText(const AToken: TPCToken): string;
begin
  if AToken.Kind = tkEOF then
    Result := RSParEndOfFile
  else
    Result := AToken.Spelling;
end;

class function TPCParser.DoSpelled(const AText: string): string;
begin
  // A spelling in a message: 'end'
  Result := '''' + AText + '''';
end;

class function TPCParser.DoKindOf(const AKind: TPCTokenKind;
  out AModuleKind: TPCModuleKind): Boolean;
begin
  Result := True;
  if AKind = tkKwExe then
    AModuleKind := mkExe
  else if AKind = tkKwDll then
    AModuleKind := mkDll
  else if AKind = tkKwLib then
    AModuleKind := mkLib
  else if AKind = tkKwUnit then
    AModuleKind := mkUnit
  else
  begin
    AModuleKind := mkExe;
    Result := False;
  end;
end;

class function TPCParser.DoFileStem(const APath: string): string;
var
  LStart: Integer;
  LDot: Integer;
begin
  // The file name without its extension, cut as text (no RTL call that raises)
  LStart := APath.LastIndexOf('/');
  if APath.LastIndexOf('\') > LStart then
    LStart := APath.LastIndexOf('\');
  Result := APath.Substring(LStart + 1);
  LDot := Result.LastIndexOf('.');
  if LDot > 0 then
    Result := Result.Substring(0, LDot);
end;

class function TPCParser.DoFileDir(const APath: string): string;
var
  LEnd: Integer;
begin
  // The directory part, cut as text; '' when there is none
  LEnd := APath.LastIndexOf('/');
  if APath.LastIndexOf('\') > LEnd then
    LEnd := APath.LastIndexOf('\');
  if LEnd < 0 then
    Exit('');
  Result := APath.Substring(0, LEnd);
end;

class function TPCParser.DoShapeText(const AShape: TPCDirectiveShape): string;
begin
  if AShape = dsIdentifier then
    Result := RSParShapeIdentifier
  else if AShape = dsInteger then
    Result := RSParShapeInteger
  else if AShape = dsCString then
    Result := RSParShapeCString
  else if AShape = dsOneOrTwoCStrings then
    Result := RSParShapeCStrings
  else if AShape = dsSeverityText then
    Result := RSParShapeSeverity
  else if AShape = dsKeyAndPath then
    Result := RSParShapeKeyPath
  else
    Result := RSParShapeNone;
end;

class function TPCParser.DoIsOneOf(const AKind: TPCTokenKind;
  const AKinds: array of TPCTokenKind): Boolean;
var
  LI: Integer;
begin
  for LI := Low(AKinds) to High(AKinds) do
  begin
    if AKinds[LI] = AKind then
      Exit(True);
  end;
  Result := False;
end;

class function TPCParser.DoIsPlainString(const AToken: TPCToken): Boolean;
begin
  // cstring = a plain narrow string literal, raw allowed (BNF.md sec 2)
  Result := (AToken.Kind = tkStringLiteral) and (AToken.LiteralPrefix = lpNone) and
    (AToken.Suffix = '');
end;

class function TPCParser.DoIsCppTarget(const AToken: TPCToken;
  out ATarget: TPCEmitTarget): Boolean;
begin
  // 'header' / 'source' after cpp or cppstart: a plain name, matched by Spelling
  ATarget := etSource;
  if AToken.Kind <> tkIdentifier then
    Exit(False);
  if AToken.Spelling = PC_PAR_CPP_HEADER then
  begin
    ATarget := etHeader;
    Exit(True);
  end;
  Result := AToken.Spelling = PC_PAR_CPP_SOURCE;
end;

procedure TPCParser.DoReadHeaderQuiet();
var
  LKind: TPCModuleKind;
begin
  // module <kind> <ident> ; read positionally with no report (D1), like the
  // filter's header read; anything else leaves a nameless module of the
  // assumed kind
  FKindAssumed := True;
  FModule.ModuleKind := DoAssumedKind();
  if (FCursor.TokenAt(0).Kind <> tkKwModule) or (FCursor.TokenAt(2).Kind <> tkIdentifier) or
    (FCursor.TokenAt(3).Kind <> tkSemicolon) then
    Exit;
  if not DoKindOf(FCursor.TokenAt(1).Kind, LKind) then
    Exit;

  FKindAssumed := False;
  FModule.ModuleKind := LKind;
  FModule.ModuleName := FCursor.TokenAt(2).Spelling;
  FModule.NameRange := FCursor.TokenAt(2).Range;
  // The module's range ends at the header's ';'
  FLastToken := FCursor.TokenAt(3);
  FHasLast := True;
end;

procedure TPCParser.DoParseHeader();
var
  LKindToken: TPCToken;
  LNameToken: TPCToken;
  LStem: string;
  LKind: TPCModuleKind;
  LMark: TPCSkipMark;
begin
  // module <kind> <name> ;  (BNF.md sec 1)
  if not DoExpect(tkKwModule, DoSpelled('module')) then
  begin
    FKindAssumed := True;
    FModule.ModuleKind := DoAssumedKind();
    // A header written without its keyword ('exe Foo;') becomes an error
    // node; any other token starts the module's items (PLAN-RECOVERY)
    if DoKindOf(DoCurrent().Kind, LKind) then
    begin
      LMark := DoMarkSkip();
      DoSkipFrame();
      DoAddSkipped(FModule.Decls, LMark);
    end;
    Exit;
  end;

  // A missing kind is not consumed: the token may be the name
  LKindToken := DoCurrent();
  if DoKindOf(LKindToken.Kind, FModule.ModuleKind) then
    DoAdvance()
  else
  begin
    DoError(LKindToken, PC_ERR_PAR_002, RSParNeedKind, [DoTokenText(LKindToken)]);
    FKindAssumed := True;
    FModule.ModuleKind := DoAssumedKind();
  end;

  // A build rule: a file that is only checked (SetUnitMainAllowed) may be a unit
  if DoIsMain() and (not FUnitMainAllowed) and (not FKindAssumed) and
    (FModule.ModuleKind = mkUnit) then
    DoError(LKindToken, PC_ERR_PAR_004, RSParUnitMain, []);

  LNameToken := DoCurrent();
  if not DoExpect(tkIdentifier, RSParWhatModuleName) then
  begin
    // ';' right here ends the header; any other rest is an error node
    if not DoMatch(tkSemicolon) then
    begin
      LMark := DoMarkSkip();
      DoSkipFrame();
      DoAddSkipped(FModule.Decls, LMark);
    end;
    Exit;
  end;

  // Module name = file name without .pcpp, exact case (BNF.md sec 1)
  FModule.ModuleName := LNameToken.Spelling;
  FModule.NameRange := LNameToken.Range;
  LStem := DoFileStem(FModule.SourceFile);
  if FModule.ModuleName <> LStem then
    DoError(LNameToken, PC_ERR_PAR_003, RSParNameMismatch, [FModule.ModuleName, LStem]);

  // The header is complete: a missing ';' is inserted, nothing skipped (r4)
  DoExpectTerminator(fcModule);
end;

procedure TPCParser.DoParsePrologue();
begin
  // Every directive right after the header; conditionals never reach the parser
  while DoCheck(tkDirective) and (not DoStopped()) do
    DoParseBuildDirective();
end;

procedure TPCParser.DoParseBuildDirective();
var
  LDirective: TPCDirective;
begin
  // One directive of the prologue (BNF.md sec 2); a failed one is an error
  // node in Decls
  LDirective := DoParseDirectiveNode(FModule.Decls, False);
  if LDirective <> nil then
    FModule.Directives.Add(LDirective);
end;

function TPCParser.DoParseDirectiveNode(const AOwner: TList<TPCStmt>;
  const AInBody: Boolean): TPCDirective;
var
  LToken: TPCToken;
  LDirectiveName: string;
  LKind: TPCBuildDirective;
  LRow: TPCDirectiveRow;
  LDirective: TPCDirective;
  LRange: TSourceRange;
  LOutcome: TPCArgOutcome;
  LMark: TPCSkipMark;
  LFollow: TPCFollowContext;
begin
  // A build directive and its ';' (BNF.md sec 2): in the prologue, or a
  // statement directive in a body (sec 5). A directive token's Spelling
  // includes the '@'. nil = reported; its tokens are an error node in AOwner
  // (PLAN-RECOVERY)
  Result := nil;
  LMark := DoMarkSkip();
  LToken := DoCurrent();
  LDirectiveName := LToken.Spelling.Substring(1);
  if not TPCVocabulary.FindDirective(LDirectiveName, LKind) then
  begin
    DoError(LToken, PC_ERR_PAR_005, RSParUnknownDirective, [LDirectiveName]);
    DoSkipDirective(AInBody);
    DoAddSkipped(AOwner, LMark);
    Exit;
  end;
  LRow := PC_BUILD_DIRECTIVES[LKind];

  LRange := DoStartRange();
  DoAdvance();

  // A unit adds to the main module's build but cannot set its options (D2)
  if LRow.IsMainOnly and (FModule.ModuleKind = mkUnit) and (not FKindAssumed) then
    DoError(LToken, PC_ERR_PAR_023, RSParMainOnly, [LDirectiveName]);

  LDirective := FAst.NewNode<TPCDirective>();
  LDirective.DirectiveName := LDirectiveName;
  LDirective.DirectiveKind := LKind;
  LOutcome := DoParseDirectiveArgs(LRow, LDirective);
  if LOutcome = arShapeMiss then
  begin
    // @target's argument errors are the filter's (one rule, one reporter)
    if not LRow.IsFilterChecked then
      DoError(DoCurrent(), PC_ERR_PAR_006, RSParDirectiveShape,
        [LDirectiveName, DoShapeText(LRow.Shape)]);
    DoSkipDirective(AInBody);
    DoAddSkipped(AOwner, LMark);
    Exit;
  end;
  if LOutcome = arReported then
  begin
    DoSkipDirective(AInBody);
    DoAddSkipped(AOwner, LMark);
    Exit;
  end;
  if AInBody then
    LFollow := fcStatement
  else
    LFollow := fcModule;
  // Complete: a missing ';' is inserted when the next token can follow
  // (r4); otherwise the directive and the rest are one error node
  if DoExpectTerminator(LFollow) = toMissing then
  begin
    DoSkipDirective(AInBody);
    DoAddSkipped(AOwner, LMark);
    Exit;
  end;

  DoFinishRange(LRange);
  LDirective.Range := LRange;
  Result := LDirective;
end;

procedure TPCParser.DoSkipDirective(const AInBody: Boolean);
begin
  // Recovery after a failed directive; in a body never past a token that
  // closes the enclosing statement list (DoSkipStatement)
  if AInBody then
    DoSkipStatement()
  else
    DoSkipFrame();
end;

function TPCParser.DoParseDirectiveArgs(const ARow: TPCDirectiveRow;
  const ADirective: TPCDirective): TPCArgOutcome;
var
  LKeyRow: TPCDirectiveRow;
begin
  if ARow.Shape = dsNone then
    Result := arOk
  else if ARow.Shape = dsKeyAndPath then
  begin
    // @addresdata "KEY" "PATH": both required. The key is text, never a
    // path, so it is read through a copy of the row without IsPath; the
    // path is read through the row itself (resolved once, BNF.md sec 2)
    LKeyRow := ARow;
    LKeyRow.IsPath := False;
    Result := DoParseCStringArg(LKeyRow, ADirective);
    if Result = arOk then
      Result := DoParseCStringArg(ARow, ADirective);
  end
  else if ARow.Shape = dsIdentifier then
    Result := DoParseIdentifierArg(ADirective)
  else if ARow.Shape = dsInteger then
    Result := DoParseIntegerArg(ADirective)
  else if ARow.Shape = dsCString then
    Result := DoParseCStringArg(ARow, ADirective)
  else if ARow.Shape = dsOneOrTwoCStrings then
  begin
    // @cppdefine "NAME" [ "VALUE" ]: the second is there when a string follows
    Result := DoParseCStringArg(ARow, ADirective);
    if (Result = arOk) and (DoCurrent().Kind = tkStringLiteral) then
      Result := DoParseCStringArg(ARow, ADirective);
  end
  else
  begin
    // dsSeverityText: severity, then the text
    Result := DoParseSeverityArg(ADirective);
    if Result = arOk then
      Result := DoParseCStringArg(ARow, ADirective);
  end;
end;

function TPCParser.DoParseIdentifierArg(const ADirective: TPCDirective): TPCArgOutcome;
var
  LToken: TPCToken;
begin
  LToken := DoCurrent();
  if LToken.Kind <> tkIdentifier then
    Exit(arShapeMiss);
  ADirective.Args.Add(DoNewArg(LToken, daIdentifier, LToken.Spelling));
  DoAdvance();
  Result := arOk;
end;

function TPCParser.DoParseIntegerArg(const ADirective: TPCDirective): TPCArgOutcome;
var
  LToken: TPCToken;
begin
  // A plain integer: no suffix (SEM validates the value)
  LToken := DoCurrent();
  if (LToken.Kind <> tkIntLiteral) or (LToken.Suffix <> '') then
    Exit(arShapeMiss);
  ADirective.Args.Add(DoNewArg(LToken, daInteger, LToken.Spelling));
  DoAdvance();
  Result := arOk;
end;

function TPCParser.DoParseSeverityArg(const ADirective: TPCDirective): TPCArgOutcome;
var
  LToken: TPCToken;
  LSeverity: TErrorSeverity;
begin
  LToken := DoCurrent();
  if LToken.Kind <> tkIdentifier then
    Exit(arShapeMiss);
  for LSeverity := Low(TErrorSeverity) to High(TErrorSeverity) do
  begin
    if LToken.Spelling = PC_MESSAGE_SEVERITIES[LSeverity] then
    begin
      ADirective.Args.Add(DoNewArg(LToken, daIdentifier, LToken.Spelling));
      DoAdvance();
      Exit(arOk);
    end;
  end;
  DoError(LToken, PC_ERR_PAR_007, RSParSeverity, [LToken.Spelling]);
  Result := arReported;
end;

function TPCParser.DoParseCStringArg(const ARow: TPCDirectiveRow;
  const ADirective: TPCDirective): TPCArgOutcome;
var
  LToken: TPCToken;
  LValue: string;
  LHasValue: Boolean;
  LPath: string;
  LArg: TPCDirectiveArg;
begin
  LToken := DoCurrent();
  if LToken.Kind <> tkStringLiteral then
    Exit(arShapeMiss);
  if not DoIsPlainString(LToken) then
  begin
    if not ARow.IsFilterChecked then
      DoError(LToken, PC_ERR_PAR_009, RSParBadString, [RSParNotPlainString]);
    Exit(arReported);
  end;

  // A bad value still builds the argument, HasValue False and ResolvedText ''
  // ('' with HasValue is a real empty text, F-A2-1). A library name is never
  // resolved (BNF.md sec 2): a file there is PR0055, the argument kept
  LHasValue := DoDecodeCString(LToken, not ARow.IsFilterChecked, LValue);
  if LHasValue then
  begin
    if ARow.IsPath then
    begin
      // A separate LPath: a const and an out parameter on one string alias
      LHasValue := DoResolveDirectivePath(ADirective.DirectiveName, LToken, LValue, LPath);
      LValue := LPath;
    end
    else if ARow.IsLibName then
      DoCheckLibName(LToken, LValue, '@' + ADirective.DirectiveName);
  end;

  LArg := DoNewArg(LToken, daCString, LValue);
  LArg.HasValue := LHasValue;
  ADirective.Args.Add(LArg);
  DoAdvance();
  Result := arOk;
end;

function TPCParser.DoDecodeCString(const AToken: TPCToken; const AReport: Boolean;
  out AValue: string): Boolean;
var
  LRuns: TArray<TPCSpellRun>;
begin
  // A directive argument: the value, no positions (its runs are not needed)
  Result := DoDecodeCString(AToken, AReport, AValue, LRuns);
end;

function TPCParser.DoDecodeCString(const AToken: TPCToken; const AReport: Boolean;
  out AValue: string; out ARuns: TArray<TPCSpellRun>): Boolean;
var
  LReason: string;
  LStatus: TPCCStringStatus;
begin
  // The one cstring value check (directive arguments, string literal parts): an error
  // is PR0009, no value and no runs; a warning PR0021 with the value and its spell
  // runs kept (P-STRPOS). AReport False: the filter owns the reports (@target)
  LStatus := TPCCString.Decode(AToken, AValue, LReason, ARuns);
  if LStatus = csError then
  begin
    if AReport then
      DoError(AToken, PC_ERR_PAR_009, RSParBadString, [LReason]);
    AValue := '';
    ARuns := nil;
    Exit(False);
  end;
  if (LStatus = csWarning) and AReport then
    DoWarning(AToken, PC_ERR_PAR_021, RSParStringWarning, [LReason]);
  Result := True;
end;

function TPCParser.DoNewArg(const AToken: TPCToken; const AArgKind: TPCDirectiveArgKind;
  const AResolvedText: string): TPCDirectiveArg;
begin
  Result := FAst.NewNode<TPCDirectiveArg>();
  Result.ArgKind := AArgKind;
  Result.Text := AToken.Text;
  Result.ResolvedText := AResolvedText;
  // An integer argument keeps the token's value: semantics validates it and
  // the compiler hands it on, neither re-parses Text (inputs.md F2)
  Result.HasValue := (AArgKind = daInteger) and AToken.HasValue;
  if Result.HasValue then
    Result.IntValue := AToken.IntValue;
  Result.Range := AToken.Range;
end;

procedure TPCParser.DoCheckLibName(const AToken: TPCToken; const AValue: string;
  const AWhere: string);
begin
  // One rule for @linklibrary and an external clause's "..." library: a NAME
  // the system linker finds, never a file (BNF.md sec 2, sem\decls.md Q25a)
  if not TPCLibraryName.IsName(AValue) then
    DoError(AToken, PC_ERR_PAR_055, RSParLibName, [AValue, AWhere]);
end;

function TPCParser.DoResolveDirectivePath(const ADirectiveName: string;
  const AToken: TPCToken; const AValue: string; out APath: string): Boolean;
begin
  // Every path directive resolves here, once, no base (an unprefixed relative
  // path resolves against the CWD); nothing resolves it again (PROJECT.md).
  // False = PR0022 reported, APath ''
  try
    APath := TUtils.ResolvePath(AValue);
    Result := True;
  except
    on E: Exception do
    begin
      DoError(AToken, PC_ERR_PAR_022, RSParPathResolve, [ADirectiveName, AValue, E.Message]);
      APath := '';
      Result := False;
    end;
  end;
end;

procedure TPCParser.DoCollectModulePaths();
var
  LDirective: TPCDirective;
begin
  // The main module's @modulepath folders, in order, after the ones added
  // before the parse (AddModulePath); imports get the whole list
  if not DoIsMain() then
    Exit;
  for LDirective in FModule.Directives do
  begin
    // The directive's path is already resolved (ResolvedText): added as is
    if (LDirective.DirectiveKind = bdAddModulePath) and (LDirective.Args.Count > 0) and
      LDirective.Args[0].HasValue then
      DoAddSearchPath(LDirective.Args[0].ResolvedText);
  end;
end;

procedure TPCParser.DoAddSearchPath(const AResolvedPath: string);
var
  LPath: string;
begin
  // The one place a folder joins the search list: a folder already in it
  // (any spelling of it) is not added again
  for LPath in FModulePaths do
  begin
    if TUtils.SamePath(LPath, AResolvedPath) then
      Exit;
  end;
  FModulePaths := FModulePaths + [AResolvedPath];
end;

function TPCParser.DoParseImportFile(const AFile: string;
  const ATarget: TPCTargetTriple): TPCModule;
var
  LParser: TPCParser;
  LPath: string;
begin
  // An import's own parser: this parser's search list goes to it unchanged
  // (already resolved, so through DoAddSearchPath, not AddModulePath)
  LParser := TPCParser.Create();
  try
    LParser.SetErrors(FErrors);
    // The build's override goes down too: it wins over the import's own
    // @target (no CD0012 under -t); the default is the main file's only
    LParser.Init(FAst, AFile, FImportChain + [FModule.SourceFile], ATarget,
      FOverrideTarget, Default(TPCTargetTriple));
    for LPath in FModulePaths do
      LParser.DoAddSearchPath(LPath);
    LParser.SetSourceProvider(FSourceProvider);
    Result := LParser.Parse();
  finally
    LParser.Free();
  end;

  // Registered on return, as ParseModuleFile: completion order = dependency order
  FAst.AddModule(Result);
end;

procedure TPCParser.SetSourceProvider(const AProvider: TPCSourceProvider);
begin
  FSourceProvider := AProvider;
end;

procedure TPCParser.SetUnitMainAllowed(const AAllowed: Boolean);
begin
  FUnitMainAllowed := AAllowed;
end;

function TPCParser.DoTokenizeSource(): Boolean;
var
  LPath: string;
  LBytes: TBytes;
begin
  // The provider's text wins over the disk (an editor buffer). It is asked
  // with the resolved path; a name no file routine can take goes to
  // TokenizeFile, which reports it (LX0012)
  if Assigned(FSourceProvider) then
  begin
    LPath := '';
    try
      LPath := TUtils.ResolvePath(FFilename);
    except
      on E: Exception do
        LPath := '';
    end;
    if (LPath <> '') and FSourceProvider(LPath, LBytes) then
      Exit(FLexer.TokenizeBytes(LBytes, LPath, FRawStream));
  end;
  Result := FLexer.TokenizeFile(FFilename, FRawStream);
end;

procedure TPCParser.DoRecordDropped();
var
  LDropped: TList<TSourceRange>;
  LRaw: Integer;
  LKept: Integer;
  LToken: TPCToken;
begin
  // TPCModule.DroppedTokens: the kept tokens are a subsequence of the raw
  // ones and both ascend by offset, so one walk pairs them; a raw token the
  // kept stream does not hold next was dropped
  LDropped := TList<TSourceRange>.Create();
  try
    LKept := 0;
    for LRaw := 0 to FRawStream.Count() - 1 do
    begin
      LToken := FRawStream.TokenAt(LRaw);
      if LToken.Kind = tkEOF then
        Break;
      if (LKept < FStream.Count()) and
        (FStream.TokenAt(LKept).Range.StartByteOffset = LToken.Range.StartByteOffset) then
        Inc(LKept)
      else
        LDropped.Add(LToken.Range);
    end;
    FModule.DroppedTokens := LDropped.ToArray();
  finally
    LDropped.Free();
  end;
end;

function TPCParser.DoEndsInReportedSpan(): Boolean;
var
  LCount: Integer;
  LLast: TPCToken;
begin
  // The lexer's own stream (the filter may drop tokens): its last token
  // before EOF is a reported span reaching the end of the file
  LCount := FRawStream.Count();
  if LCount < 2 then
    Exit(False);
  LLast := FRawStream.TokenAt(LCount - 2);
  Result := (LLast.Kind = tkUnknown) and
    (LLast.Range.EndByteOffset >= FRawStream.TokenAt(LCount - 1).Range.StartByteOffset);
end;

function TPCParser.DoSourceExists(const AFilename: string): Boolean;
var
  LBytes: TBytes;
begin
  // An import the provider has is found even when the disk has no file yet
  if Assigned(FSourceProvider) and FSourceProvider(AFilename, LBytes) then
    Exit(True);
  // PaskalCPP is case-sensitive: `import math` takes math.pcpp only, never
  // Math.pcpp, on every target (Windows' own lookup ignores case)
  Result := TUtils.FileExistsExactCase(AFilename);
end;

procedure TPCParser.DoParseImportClause();
var
  LNameToken: TPCToken;
  LMark: TPCSkipMark;
begin
  // import <ident> { , <ident> } ;  right after the prologue (BNF.md sec 1)
  if not DoMatch(tkKwImport) then
    Exit;
  repeat
    if DoStopped() then
      Exit;
    LNameToken := DoCurrent();
    if not DoExpect(tkIdentifier, RSParWhatUnitName) then
    begin
      // The names before it are imported (DoParseImport ran for each); ';'
      // right here ends the clause, any other rest is an error node
      if not DoMatch(tkSemicolon) then
      begin
        LMark := DoMarkSkip();
        DoSkipFrame();
        DoAddSkipped(FModule.Decls, LMark);
      end;
      Exit;
    end;
    DoParseImport(LNameToken);
  until not DoMatch(tkComma);

  // Complete: a missing ';' is inserted, nothing skipped (r4)
  DoExpectTerminator(fcModule);
end;

procedure TPCParser.DoParseImport(const ANameToken: TPCToken);
var
  LUnitName: string;
  LFile: string;
  LSearched: string;
  LExisting: TPCImport;
  LImport: TPCImport;
  LTarget: TPCTargetTriple;
  LError: TPCErrorStmt;
begin
  LUnitName := ANameToken.Spelling;
  for LExisting in FModule.Imports do
  begin
    if LExisting.ModuleName = LUnitName then
    begin
      // Not a second import of the unit (a name resolves to one): the
      // repeated name is an error node in Decls, as every prologue drop
      // (PLAN-RECOVERY A7)
      DoError(ANameToken, PC_ERR_PAR_014, RSParDuplicateImport, [LUnitName]);
      LError := FAst.NewNode<TPCErrorStmt>();
      LError.Range := ANameToken.Range;
      FModule.Decls.Add(LError);
      Exit;
    end;
  end;

  // The import states what was written; ImportedModule stays nil on an error
  LImport := FAst.NewNode<TPCImport>();
  LImport.ModuleName := LUnitName;
  LImport.Range := ANameToken.Range;
  FModule.Imports.Add(LImport);

  LFile := DoFindUnitFile(LUnitName, LSearched);
  if LFile = '' then
  begin
    DoError(ANameToken, PC_ERR_PAR_012, RSParUnitNotFound, [LUnitName, LSearched]);
    Exit;
  end;

  // Identity is the resolved file, never the declared name (parser-core.md)
  if DoInChain(LFile) then
  begin
    DoError(ANameToken, PC_ERR_PAR_011, RSParImportCycle, [DoCycleText(LUnitName)]);
    Exit;
  end;

  // Parsed once: a diamond links the module already in the AST
  LImport.ImportedModule := FAst.FindModuleByFile(LFile);
  if LImport.ImportedModule = nil then
  begin
    // The main module's triple goes down unchanged (Q2)
    if DoIsMain() then
      LTarget := FFilter.Target()
    else
      LTarget := FMainTarget;
    LImport.ImportedModule := DoParseImportFile(LFile, LTarget);
  end;

  if LImport.ImportedModule.ModuleKind <> mkUnit then
    DoError(ANameToken, PC_ERR_PAR_013, RSParImportKind,
      [LUnitName, PC_PAR_KIND_NAMES[LImport.ImportedModule.ModuleKind]]);
end;

function TPCParser.DoFindUnitFile(const AUnitName: string; out ASearched: string): string;
var
  LFileName: string;
  LDirs: TArray<string>;
  LDir: string;
  LCandidate: string;
begin
  // The importing file's directory, then the module paths in the order added.
  // JoinResolvedPath and FileExists cannot raise (D3); a file the source
  // provider has counts as found (DoSourceExists).
  LFileName := AUnitName + '.' + PC_SRC_EXT;
  LDirs := [DoFileDir(FModule.SourceFile)] + FModulePaths;
  ASearched := '';
  for LDir in LDirs do
  begin
    if ASearched <> '' then
      ASearched := ASearched + ', ';
    ASearched := ASearched + LDir;
    LCandidate := TUtils.JoinResolvedPath(LDir, LFileName);
    // Every candidate tried, found or not: a unit file created at one (or
    // an earlier one) changes what this import resolves to (LSP watching)
    FAst.AddLookupPath(TUtils.StripLongPathPrefix(LCandidate));
    if DoSourceExists(LCandidate) then
      Exit(LCandidate);
  end;
  Result := '';
end;

function TPCParser.DoInChain(const AFile: string): Boolean;
var
  LEntry: string;
begin
  // A file that is being parsed further up the import stack, or this one
  if TUtils.SamePath(AFile, FModule.SourceFile) then
    Exit(True);
  for LEntry in FImportChain do
  begin
    if TUtils.SamePath(AFile, LEntry) then
      Exit(True);
  end;
  Result := False;
end;

function TPCParser.DoCycleText(const AUnitName: string): string;
var
  LEntry: string;
begin
  // a -> b -> a: the importers' file stems, this file's stem, the import
  Result := '';
  for LEntry in FImportChain do
    Result := Result + DoFileStem(LEntry) + ' -> ';
  Result := Result + DoFileStem(FModule.SourceFile) + ' -> ' + AUnitName;
end;

function TPCParser.DoCurrentIndex(): Integer;
begin
  // The current token's index; a split piece reports its token's index (a copy
  // that ends on a piece takes the piece itself: DoFillVerbatimUpTo)
  Result := FCursor.SavePosition().Index;
end;

function TPCParser.DoIsDeclStart(): Boolean;
var
  LKind: TPCTokenKind;
begin
  // A PaskalCPP declaration at module level (BNF.md sec 10 starter): var /
  // const / type only in PaskalCPP shape (keyword, identifier, ':' or '='),
  // so C++ 'const int X = 5;' and 'using type = int;' stay C++
  LKind := DoCurrent().Kind;
  if (LKind = tkKwRoutine) or (LKind = tkKwForward) or (LKind = tkKwExported) then
    Exit(True);
  if (LKind <> tkKwVar) and (LKind <> tkKwConst) and (LKind <> tkKwType) then
    Exit(False);
  Result := (DoPeek(1).Kind = tkIdentifier) and
    ((DoPeek(2).Kind = tkColon) or (DoPeek(2).Kind = tkEqual));
end;

function TPCParser.DoIsStarter(): Boolean;
begin
  // Every token that ends a C++ span at a declaration boundary (BNF.md sec 10)
  Result := DoIsDeclStart() or DoIsOneOf(DoCurrent().Kind, [tkKwCpp, tkKwCppstart,
    tkKwBegin, tkKwEnd, tkKwTest, tkKwImport, tkKwInitialize, tkKwFinalize,
    tkDirective, tkCppPreprocessor]);
end;

function TPCParser.DoScanSpan(): Integer;
var
  LToken: TPCToken;
  LDepth: Integer;
  LBoundary: Boolean;
begin
  // The C++ span rule (BNF.md sec 10): from the current token up to a
  // depth-0 # line, or a starter right after a depth-0 ';' or '}'. Angle
  // brackets never count; strings and comments are whole tokens / trivia.
  // Result = index of the last token consumed; -1 only at EOF
  Result := -1;
  LDepth := 0;
  LBoundary := False;
  while not DoCheck(tkEOF) do
  begin
    if (Result >= 0) and (LDepth = 0) then
    begin
      if DoCheck(tkCppPreprocessor) then
        Break;
      if LBoundary and DoIsStarter() then
        Break;
    end;
    LToken := DoCurrent();
    Result := DoCurrentIndex();
    DoAdvance();
    if DoIsOneOf(LToken.Kind, [tkLParen, tkLBracket, tkLBrace]) then
      Inc(LDepth)
    else if DoIsOneOf(LToken.Kind, [tkRParen, tkRBracket, tkRBrace]) and (LDepth > 0) then
      // An unbalanced closer is clang's to report: the depth never goes below 0
      Dec(LDepth);
    // A reported lexer span (tkUnknown) is a boundary too: what follows bytes
    // the lexer rejected is not trusted to continue one declaration, so the
    // next starter ends the span (PLAN-RECOVERY A8: one report per root cause)
    LBoundary := (LDepth = 0) and DoIsOneOf(LToken.Kind, [tkSemicolon, tkRBrace, tkUnknown]);
  end;
end;

procedure TPCParser.DoFillVerbatim(const AFirst: Integer; const ALast: Integer;
  var AVerbatim: TPCVerbatim);
begin
  // Whole tokens AFirst..ALast (spans, cppstart blocks, # lines, decltype heads)
  DoFillVerbatimUpTo(AFirst, ALast, FCursor.TokenAt(ALast), AVerbatim);
end;

function TPCParser.DoNewVerbatim(const AFirst: Integer; const ALast: Integer;
  const AKind: TPCVerbatimKind; const ATarget: TPCEmitTarget): TPCVerbatimStmt;
begin
  Result := FAst.NewNode<TPCVerbatimStmt>();
  Result.Verbatim.VerbatimKind := AKind;
  Result.Verbatim.EmitTarget := ATarget;
  DoFillVerbatim(AFirst, ALast, Result.Verbatim);
  Result.Range := Result.Verbatim.Range;
end;

procedure TPCParser.DoParseModuleDecls();
var
  LToken: TPCToken;
begin
  // { declaration } (BNF.md sec 1, sec 3): up to the sections, the body,
  // any 'end' (the module's, or a stray one DoParseModuleEnd reports) or EOF
  while not DoStopped() do
  begin
    LToken := DoCurrent();
    if DoIsOneOf(LToken.Kind, [tkEOF, tkKwInitialize, tkKwFinalize, tkKwBegin, tkKwEnd]) then
      Exit;
    if LToken.Kind = tkCppPreprocessor then
      DoParsePreprocessor(FModule.Decls, FPlacement)
    else if LToken.Kind = tkKwCpp then
      DoParsePlacement()
    else if LToken.Kind = tkKwCppstart then
      DoParseCppBlock(FModule.Decls, False)
    else if LToken.Kind = tkDirective then
      DoReportMisplacedDirective()
    else if LToken.Kind = tkKwImport then
    begin
      // Parsed as the clause it is, so its names resolve (PLAN-RECOVERY)
      DoError(LToken, PC_ERR_PAR_010, RSParImportPlace, []);
      DoParseImportClause();
    end
    else if LToken.Kind = tkKwTest then
    begin
      // No module end anywhere after it: the 'end .' is what is missing, so
      // the declarations end here; the end is reported once and the tests are
      // parsed after it (PLAN-RECOVERY A7). Otherwise the test is misplaced:
      // parsed anyway, so its body never cascades into C++ spans (B2)
      if not DoHasModuleEndAhead() then
        Exit;
      DoError(LToken, PC_ERR_PAR_019, RSParTestPlace, []);
      DoParseTest();
    end
    else if DoIsDeclStart() then
      DoParseModuleDecl()
    else
      DoParseCppSpan();
  end;
end;

procedure TPCParser.DoParseModuleDecl();
var
  LToken: TPCToken;
  LExported: Boolean;
  LFirst: Integer;
  LIndex: Integer;
begin
  // A PaskalCPP declaration at module level (DoIsDeclStart said so).
  // exported decl = "exported" , declaration (BNF.md sec 3): it covers the one
  // declaration that follows, a whole block included (X2). Before anything
  // that is not a PaskalCPP declaration it is PR0024 and only 'exported' is
  // consumed (X3): what follows parses as it would without it
  LExported := DoMatch(tkKwExported);
  if LExported and (DoCheck(tkKwExported) or (not DoIsDeclStart())) then
  begin
    LToken := DoCurrent();
    DoError(LToken, PC_ERR_PAR_024, RSParExportedTarget, [DoTokenText(LToken)]);
    Exit;
  end;
  LFirst := FModule.Decls.Count;
  DoParseDeclaration(FModule.Decls, LExported);
  // Every declaration this call appended is module level: record its owner
  // (PLAN-EMITTER H1). Locals are parsed into other lists and stay nil
  for LIndex := LFirst to FModule.Decls.Count - 1 do
  begin
    if FModule.Decls[LIndex] is TPCDecl then
      TPCDecl(FModule.Decls[LIndex]).DeclModule := FModule;
  end;
end;

procedure TPCParser.DoParsePreprocessor(const AOwner: TList<TPCStmt>; const ATarget: TPCEmitTarget);
var
  LIndex: Integer;
begin
  // A # line: at module level where cpp header|source puts the plain C++
  // around it (user 2026-10-17; it went to the header always), in a body in
  // place (BNF.md sec 10, parser.md "Statements")
  LIndex := DoCurrentIndex();
  DoAdvance();
  AOwner.Add(DoNewVerbatim(LIndex, LIndex, vkPreproc, ATarget));
end;

procedure TPCParser.DoParsePlacement();
var
  LKeyword: TPCToken;
  LWord: TPCToken;
  LTarget: TPCEmitTarget;
  LMark: TPCSkipMark;
begin
  // cpp header|source ;  sets where the following C++ spans go; no node.
  // cpp(...) is an expression, never a module-level declaration. A bad
  // target is an error node (PLAN-RECOVERY)
  LMark := DoMarkSkip();
  LKeyword := DoCurrent();
  DoAdvance();
  LWord := DoCurrent();
  if not DoIsCppTarget(LWord, LTarget) then
  begin
    DoError(LWord, PC_ERR_PAR_015, RSParCppTarget, [LKeyword.Spelling, DoTokenText(LWord)]);
    DoSkipFrame();
    DoAddSkipped(FModule.Decls, LMark);
    Exit;
  end;
  DoAdvance();
  FPlacement := LTarget;
  // Complete: a missing ';' is inserted, nothing skipped (r4)
  DoExpectTerminator(fcModule);
end;

procedure TPCParser.DoParseCppBlock(const AOwner: TList<TPCStmt>; const AInBody: Boolean);
var
  LRange: TSourceRange;
  LKeyword: TPCToken;
  LWord: TPCToken;
  LTarget: TPCEmitTarget;
  LIndex: Integer;
  LNode: TPCVerbatimStmt;
  LKeep: Boolean;
  LBlock: TPCToken;
  LMark: TPCSkipMark;
  LError: TPCErrorStmt;
begin
  // cppstart header|source <text> cppend ;  at module level the text goes to
  // the named target whatever the placement (BNF.md sec 10); in a body it
  // stays in place, so 'header' there is PR0051 (parsed, kept as an error
  // node's fragment). The lexer made the text ONE tkRawBlock token, untrimmed:
  // Verbatim is that token's (B9)
  LRange := DoStartRange();
  LMark := DoMarkSkip();
  LKeyword := DoCurrent();
  DoAdvance();
  LWord := DoCurrent();
  if not DoIsCppTarget(LWord, LTarget) then
  begin
    DoError(LWord, PC_ERR_PAR_015, RSParCppTarget, [LKeyword.Spelling, DoTokenText(LWord)]);
    DoSkipCppBlock();
    DoAddSkipped(AOwner, LMark);
    Exit;
  end;
  DoAdvance();
  LKeep := True;
  if AInBody then
  begin
    if LTarget = etHeader then
    begin
      DoError(LWord, PC_ERR_PAR_051, RSParCppBlockHeaderInBody, []);
      LKeep := False;
    end;
    LTarget := etInPlace;
  end;
  if not DoCheck(tkRawBlock) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_001, RSParExpected,
      [RSParWhatCppBlock, DoTokenText(DoCurrent())]);
    DoSkipCppBlock();
    DoAddSkipped(AOwner, LMark);
    Exit;
  end;
  LIndex := DoCurrentIndex();
  DoAdvance();
  LNode := DoNewVerbatim(LIndex, LIndex, vkCppBlock, LTarget);
  // A kept block in a body records every C++ return / break / continue that
  // leaves it (O-S6b, prereq-b\jump.md): SEM's return-path rule and Q17 read
  // them. The elements are the lexer's (FRawStream; the filter copies tokens
  // only). A module-level block has no enclosing routine; a dropped header
  // block (PR0051) is never added
  if AInBody and LKeep then
  begin
    LBlock := FCursor.TokenAt(LIndex);
    LNode.Verbatim.EscapingJumps := TPCCppJumpFinder.Find(FRawStream.CppElementsIn(
      Int64(LBlock.Range.StartByteOffset), Int64(LBlock.Range.EndByteOffset)));
  end;

  // The block is complete at cppend: a missing ';' is reported, nothing skipped
  if DoExpect(tkKwCppend, DoSpelled('cppend')) then
    DoExpect(tkSemicolon, DoSpelled(';'));
  DoFinishRange(LRange);
  LNode.Range := LRange;
  if LKeep then
    AOwner.Add(LNode)
  else
  begin
    // PR0051: parsed, no place in a body: the fragment of an error node
    LError := FAst.NewNode<TPCErrorStmt>();
    LError.Fragment := LNode;
    LError.Range := LRange;
    AOwner.Add(LError);
  end;
end;

procedure TPCParser.DoParseCppSpan();
var
  LFirst: Integer;
  LLast: Integer;
  LNode: TPCVerbatimStmt;
  LIndex: Integer;
begin
  // Plain mixed C++: one node for every declaration up to the next starter,
  // stamped with the current placement (BNF.md sec 10). The current token
  // is never EOF here, so the scan consumes at least it. A span holding a
  // reported lexer span (tkUnknown) is marked (R7)
  LFirst := DoCurrentIndex();
  LLast := DoScanSpan();
  LNode := DoNewVerbatim(LFirst, LLast, vkCppDecl, FPlacement);
  for LIndex := LFirst to LLast do
  begin
    if FCursor.TokenAt(LIndex).Kind = tkUnknown then
      LNode.IsRecovered := True;
  end;
  FModule.Decls.Add(LNode);
end;

procedure TPCParser.DoReportMisplacedDirective();
var
  LToken: TPCToken;
  LKind: TPCBuildDirective;
  LMark: TPCSkipMark;
begin
  // A build directive after the prologue (BNF.md sec 1). @target's placement
  // is the filter's to report (CD0005), so the parser skips it without a
  // report; either way its tokens are an error node (PLAN-RECOVERY)
  LToken := DoCurrent();
  if not (TPCVocabulary.FindDirective(LToken.Spelling.Substring(1), LKind) and
    PC_BUILD_DIRECTIVES[LKind].IsFilterChecked) then
    DoError(LToken, PC_ERR_PAR_008, RSParDirectivePlace, []);
  LMark := DoMarkSkip();
  DoSkipFrame();
  DoAddSkipped(FModule.Decls, LMark);
end;

procedure TPCParser.DoSkipCppBlock();
begin
  // Recovery after a bad cppstart: through cppend and its ';'
  while (not DoCheck(tkEOF)) and (not DoCheck(tkKwCppend)) do
    DoAdvance();
  if DoMatch(tkKwCppend) then
    DoMatch(tkSemicolon);
end;

procedure TPCParser.DoSkipStatement();
var
  LAfterUnknown: Boolean;
  LUnknownEndLine: Integer;
begin
  // Statement recovery (parser.md P3): through the next ';', or up to a token
  // that closes the enclosing statement list (not consumed), and never past
  // the start of a module-level item (A7). A reported lexer span (tkUnknown)
  // that runs to its line's end (an unterminated string eats that line's
  // ';') ends the statement there, as an inserted ';' would: a token that
  // can start a statement on a LATER line ends the skip (A3, A8). A span
  // that ends mid-line (a stray character) eats nothing, so the rest of its
  // line is still this statement: the skip goes on to its ';', one error
  // node, no second report from what follows the stray character
  LAfterUnknown := False;
  LUnknownEndLine := 0;
  while not (DoIsOneOf(DoCurrent().Kind, [tkEOF, tkKwEnd, tkKwElse, tkKwUntil, tkKwExcept,
    tkKwFinally]) or DoIsModuleItemStart()) do
  begin
    if DoCheck(tkSemicolon) then
    begin
      DoAdvance();
      Exit;
    end;
    if LAfterUnknown and (DoCurrent().Range.StartLine > LUnknownEndLine) and
      DoCanStartStatement() then
      Exit;
    if DoCheck(tkUnknown) then
    begin
      LAfterUnknown := True;
      LUnknownEndLine := DoCurrent().Range.EndLine;
    end;
    DoAdvance();
  end;
end;

procedure TPCParser.DoSkipRefusedStatement();
var
  LBlocks: Integer;
  LBrackets: Integer;
  LKind: TPCTokenKind;
  LFirst: Boolean;
begin
  // Recovery for a statement the nesting guard refused (PR0042): nothing of
  // it was parsed, so its own constructs are counted while it is skipped: a
  // word of PC_PAR_END_OPENERS through its 'end', a repeat through its
  // 'until', ( ) [ ] { } likewise. The skip ends after the statement's
  // depth-0 ';', or before a depth-0 token that closes the enclosing list
  // (not consumed), a module item start, EOF or the module's 'end .'. The
  // first token is always consumed (progress). One mistake, one report: the
  // refused statement's own 'end' never closes the enclosing list
  LBlocks := 0;
  LBrackets := 0;
  LFirst := True;
  while (not DoCheck(tkEOF)) and (not DoIsModuleEnd()) do
  begin
    LKind := DoCurrent().Kind;
    if (not LFirst) and (LBlocks = 0) and (LBrackets = 0) then
    begin
      if LKind = tkSemicolon then
      begin
        DoAdvance();
        Exit;
      end;
      if DoIsOneOf(LKind, [tkKwEnd, tkKwElse, tkKwUntil, tkKwExcept, tkKwFinally]) or
        DoIsModuleItemStart() then
        Exit;
    end;
    LFirst := False;
    if DoIsOneOf(LKind, PC_PAR_END_OPENERS) or (LKind = tkKwRepeat) then
      Inc(LBlocks)
    else if DoIsOneOf(LKind, [tkKwEnd, tkKwUntil]) and (LBlocks > 0) then
      Dec(LBlocks)
    else if DoIsOneOf(LKind, [tkLParen, tkLBracket, tkLBrace]) then
      Inc(LBrackets)
    else if DoIsOneOf(LKind, [tkRParen, tkRBracket, tkRBrace]) and (LBrackets > 0) then
      Dec(LBrackets);
    DoAdvance();
  end;
end;

procedure TPCParser.DoParseSections();
var
  LToken: TPCToken;
  LSection: TPCRoutine;
  LError: TPCErrorStmt;
begin
  // [ initialize section ] [ finalize section ], each at most once, in that
  // order (BNF.md sec 1). A repeated or out-of-order one is PR0018: parsed,
  // kept as an error node's fragment, the first one kept (B7)
  while (DoCheck(tkKwInitialize) or DoCheck(tkKwFinalize)) and (not DoStopped()) do
  begin
    LToken := DoCurrent();
    if ((LToken.Kind = tkKwInitialize) and
      ((FModule.InitRoutine <> nil) or (FModule.FinalRoutine <> nil))) or
      ((LToken.Kind = tkKwFinalize) and (FModule.FinalRoutine <> nil)) then
    begin
      DoError(LToken, PC_ERR_PAR_018, RSParSectionOrder, []);
      // Parsed, no slot (B7): kept, marked, as the fragment of an error node
      // (PLAN-RECOVERY), so nothing in it cascades
      LSection := DoParseSection();
      LSection.IsRecovered := True;
      LError := FAst.NewNode<TPCErrorStmt>();
      LError.Fragment := LSection;
      LError.Range := LSection.Range;
      FModule.Decls.Add(LError);
    end
    else if LToken.Kind = tkKwInitialize then
      FModule.InitRoutine := DoParseSection()
    else
      FModule.FinalRoutine := DoParseSection();
  end;
end;

function TPCParser.DoParseSection(): TPCRoutine;
var
  LRange: TSourceRange;
begin
  // A section IS a routine (BNF.md sec 1): no parameters, no return type,
  // named by its keyword; Range = keyword .. ';'
  LRange := DoStartRange();
  Result := FAst.NewNode<TPCRoutine>();
  Result.RoutineKind := rnRoutine;
  Result.DeclName := DoCurrent().Spelling;
  Result.NameRange := DoCurrent().Range;
  DoAdvance();
  DoParseRoutineBody(Result, baRoutine);
  DoFinishRange(LRange);
  Result.Range := LRange;
end;

procedure TPCParser.DoParseRoutineBody(const ARoutine: TPCRoutine; const AAllow: TPCBlockAllow);
begin
  // routine body = { var | const | type block } , block , ";"  (BNF.md sec 3);
  // a method's takes var blocks only (AAllow baMethod, T13). Shared by
  // sections, routines and methods
  DoParseDeclBlocks(ARoutine.Decls, AAllow);
  ARoutine.Body := DoParseBlock();
  if ARoutine.Body = nil then
  begin
    // A routine without its body is marked (PLAN-RECOVERY)
    ARoutine.IsRecovered := True;
    DoSkipFrame();
    Exit;
  end;
  // Complete: a missing ';' is reported, nothing skipped. A block whose
  // end is missing has reported that already (one root cause)
  if FLastToken.Kind = tkKwEnd then
    DoExpect(tkSemicolon, DoSpelled(';'));
end;

procedure TPCParser.DoParseDeclBlocks(const ADecls: TList<TPCStmt>; const AAllow: TPCBlockAllow);
var
  LToken: TPCToken;
  LVarBlocks: Integer;
begin
  // { var block | const block | type block } before a body's begin (BNF.md
  // sec 3). A method takes var blocks only, a test at most one var block
  // (sec 8): any other block is PR0025 and still parsed, so its items never
  // cascade (T13). 'exported' before a block is PR0057 by the same rule: only
  // 'exported' is dropped and the block is the body's own (exported decl is
  // module level, BNF.md sec 3); left in place it ended the body and its own
  // begin became the module's. 'routine' / 'forward' (and an 'exported' before
  // anything else) are not starters here: the body's begin check reports them
  LVarBlocks := 0;
  while not DoStopped() do
  begin
    if DoCheck(tkKwExported) and DoIsOneOf(DoPeek(1).Kind, [tkKwVar, tkKwConst, tkKwType]) then
    begin
      DoError(DoCurrent(), PC_ERR_PAR_057, RSParExportedLocal, [DoPeek(1).Spelling]);
      DoAdvance();
    end;
    if not DoIsOneOf(DoCurrent().Kind, [tkKwVar, tkKwConst, tkKwType]) then
      Break;
    LToken := DoCurrent();
    if LToken.Kind = tkKwVar then
      Inc(LVarBlocks);
    if (AAllow = baMethod) and (LToken.Kind <> tkKwVar) then
      DoError(LToken, PC_ERR_PAR_025, RSParMethodBlocks, [LToken.Spelling])
    else if (AAllow = baTest) and ((LToken.Kind <> tkKwVar) or (LVarBlocks > 1)) then
      DoError(LToken, PC_ERR_PAR_025, RSParTestBlocks, [LToken.Spelling]);
    DoParseDeclBlock(ADecls, LToken.Kind, False, False);
  end;
end;

function TPCParser.DoParseBlock(): TPCBlock;
var
  LRange: TSourceRange;
begin
  // block = "begin" , { statement } , "end"  (BNF.md sec 5); nil and PR0001
  // when there is no begin
  if not DoCheck(tkKwBegin) then
  begin
    DoExpect(tkKwBegin, DoSpelled('begin'));
    Exit(nil);
  end;
  LRange := DoStartRange();
  Result := FAst.NewNode<TPCBlock>();
  DoAdvance();
  DoParseStatementList(Result.Stmts, [tkKwEnd]);
  // The end consumed is recorded (a block still being typed has none: the
  // LSP reads it, PLAN-EDITOR E2.9)
  if DoExpectEnd() then
    Result.EndRange := FLastToken.Range;
  DoFinishRange(LRange);
  Result.Range := LRange;
end;

procedure TPCParser.DoParseStatementList(const AOwner: TList<TPCStmt>;
  const ATerminators: array of TPCTokenKind);
begin
  // { statement } up to a terminator (not consumed) or EOF; a token that only
  // starts a module-level item ends the list too (F1, PLAN-RECOVERY)
  while (not DoCheck(tkEOF)) and (not DoIsOneOf(DoCurrent().Kind, ATerminators)) and
    (not DoStopped()) and (not DoIsModuleItemStart()) do
    DoParseStatement(AOwner, False);
end;

procedure TPCParser.DoParseStatement(const AOwner: TList<TPCStmt>; const AInArm: Boolean);
var
  LStart: Integer;
  LMark: TPCSkipMark;
begin
  // statement (BNF.md sec 5) inside the nesting guard: statements nest
  // through their lists, so no input overflows the stack (past it PR0042 and
  // the whole statement is skipped, DoSkipRefusedStatement). Whatever a
  // branch does, at least one token is consumed, so every statement list
  // progresses. FStmtDepth tells a failed declaration item it sits in a body
  // (DoSkipItem)
  LStart := DoCurrentIndex();
  if not DoEnterNested() then
  begin
    LMark := DoMarkSkip();
    DoSkipRefusedStatement();
    DoAddSkipped(AOwner, LMark);
    Exit;
  end;
  Inc(FStmtDepth);
  try
    DoDispatchStatement(AOwner, AInArm);
  finally
    Dec(FStmtDepth);
    DoLeaveNested();
  end;
  if DoCurrentIndex() = LStart then
  begin
    LMark := DoMarkSkip();
    DoAdvance();
    DoAddSkipped(AOwner, LMark);
  end;
end;

procedure TPCParser.DoDispatchStatement(const AOwner: TList<TPCStmt>; const AInArm: Boolean);
var
  LKind: TPCTokenKind;
  LHint: string;
begin
  // By the leading token (research parser-stmt\stmt.md "Dispatch"): anything
  // that starts no other form is an expression statement
  if DoParseFlowStatement(AOwner) then
    Exit;
  LKind := DoCurrent().Kind;
  if DoIsOneOf(LKind, [tkKwVar, tkKwConst, tkKwType]) then
    DoParseDeclBlock(AOwner, LKind, False, AInArm)
  else if LKind = tkCppPreprocessor then
    DoParsePreprocessor(AOwner, etInPlace)
  else if LKind = tkKwCppstart then
    DoParseCppBlock(AOwner, True)
  else if (LKind = tkKwCpp) and (DoPeek(1).Kind <> tkLParen) then
    DoReportPlacementInBody(AOwner)
  else if LKind = tkDirective then
    DoParseDirectiveStatement(AOwner)
  else if DoFindCppStmtHint(LKind, LHint) then
    DoReportCppStatement(AOwner, LHint)
  else if DoIsOneOf(LKind, PC_PAR_STRAY_CLOSERS) then
    DoReportStrayCloser(AOwner)
  else if LKind = tkUnknown then
    DoSkipLeadingSpan(AOwner)
  else
    DoParseExprStatement(AOwner);
end;

procedure TPCParser.DoSkipLeadingSpan(const AOwner: TList<TPCStmt>);
var
  LMark: TPCSkipMark;
begin
  // A statement that starts with a reported lexer span (a stray character
  // between two statements, or a string cut off at its line's end): the
  // lexer's report is the one report, so only that span (and a ';' right
  // after it) goes into an error node, and the statement after it parses on
  // its own. A span in the middle of a statement is DoSkipStatement's
  // (PLAN-RECOVERY A3, A8)
  LMark := DoMarkSkip();
  DoAdvance();
  DoMatch(tkSemicolon);
  DoAddSkipped(AOwner, LMark);
end;

function TPCParser.DoParseFlowStatement(const AOwner: TList<TPCStmt>): Boolean;
begin
  // The PaskalCPP statement keywords (BNF.md sec 5). False = the current
  // token starts none of them
  Result := True;
  case DoCurrent().Kind of
    tkKwBegin:
      DoParseBlockStatement(AOwner);
    tkKwIf:
      DoParseIf(AOwner);
    tkKwWhile:
      DoParseWhile(AOwner);
    tkKwFor:
      DoParseFor(AOwner);
    tkKwRepeat:
      DoParseRepeat(AOwner);
    tkKwMatch:
      DoParseMatch(AOwner);
    tkKwGuard:
      DoParseGuard(AOwner);
    tkKwReturn:
      DoParseReturn(AOwner);
    tkKwLeave:
      DoParseKeywordOnly(AOwner, FAst.NewNode<TPCLeave>());
    tkKwSkip:
      DoParseKeywordOnly(AOwner, FAst.NewNode<TPCSkip>());
  else
    Result := False;
  end;
end;

procedure TPCParser.DoParseBlockStatement(const AOwner: TList<TPCStmt>);
var
  LBlock: TPCBlock;
begin
  // block , ";" (BNF.md sec 5). The current token is 'begin', so the block is
  // never nil; complete at its end, a missing ';' is reported, nothing skipped
  LBlock := DoParseBlock();
  AOwner.Add(LBlock);
  // Complete: a missing ';' is reported, nothing skipped. A block whose
  // end is missing has reported that already (one root cause)
  if FLastToken.Kind = tkKwEnd then
    DoExpect(tkSemicolon, DoSpelled(';'));
end;

procedure TPCParser.DoParseIf(const AOwner: TList<TPCStmt>);
var
  LRange: TSourceRange;
  LNode: TPCIf;
  LComplete: Boolean;
begin
  // if stmt = "if" expression "then" {statement} ["else" {statement}] "end" ";"
  // A header that failed keeps the node, marked (PLAN-RECOVERY)
  LRange := DoStartRange();
  LNode := FAst.NewNode<TPCIf>();
  DoAdvance();
  LNode.Condition := DoParseExpression(ecNormal);
  LComplete := DoParseHeaderEnd(not DoFailed(LNode.Condition), tkKwThen, DoSpelled('then'));
  DoParseStatementList(LNode.ThenStmts, [tkKwElse, tkKwEnd]);
  if DoMatch(tkKwElse) then
  begin
    LNode.HasElse := True;
    LNode.ElseRange := FLastToken.Range;
    DoParseStatementList(LNode.ElseStmts, [tkKwEnd]);
  end;
  DoParseCompoundEnd();
  DoFinishRange(LRange);
  LNode.Range := LRange;
  LNode.IsRecovered := not LComplete;
  AOwner.Add(LNode);
end;

procedure TPCParser.DoParseWhile(const AOwner: TList<TPCStmt>);
var
  LRange: TSourceRange;
  LNode: TPCWhile;
  LComplete: Boolean;
begin
  // while stmt = "while" expression "do" {statement} "end" ";"
  LRange := DoStartRange();
  LNode := FAst.NewNode<TPCWhile>();
  DoAdvance();
  LNode.Condition := DoParseExpression(ecNormal);
  LComplete := DoParseHeaderEnd(not DoFailed(LNode.Condition), tkKwDo, DoSpelled('do'));
  DoParseStatementList(LNode.Stmts, [tkKwEnd]);
  DoParseCompoundEnd();
  DoFinishRange(LRange);
  LNode.Range := LRange;
  LNode.IsRecovered := not LComplete;
  AOwner.Add(LNode);
end;

procedure TPCParser.DoParseFor(const AOwner: TList<TPCStmt>);
var
  LRange: TSourceRange;
  LNode: TPCFor;
  LHeaderOk: Boolean;
  LComplete: Boolean;
begin
  // for stmt = "for" identifier ":=" expression ("to" | "downto") expression
  // "do" {statement} "end" ";" (BNF.md sec 5)
  LRange := DoStartRange();
  LNode := FAst.NewNode<TPCFor>();
  DoAdvance();
  LHeaderOk := DoParseForHeader(LNode);
  LComplete := DoParseHeaderEnd(LHeaderOk, tkKwDo, DoSpelled('do'));
  DoParseStatementList(LNode.Stmts, [tkKwEnd]);
  DoParseCompoundEnd();
  DoFinishRange(LRange);
  LNode.Range := LRange;
  LNode.IsRecovered := not LComplete;
  AOwner.Add(LNode);
end;

function TPCParser.DoParseForHeader(const ANode: TPCFor): Boolean;
var
  LToken: TPCToken;
begin
  // identifier ":=" expression ("to" | "downto") expression. The identifier
  // names a variable declared before the loop: a token, never an expression
  // (an expression would take ':=' as an assignment). False = reported once,
  // at the first part that does not fit
  LToken := DoCurrent();
  if LToken.Kind <> tkIdentifier then
  begin
    DoError(LToken, PC_ERR_PAR_001, RSParExpected, [RSParShapeIdentifier, DoTokenText(LToken)]);
    Exit(False);
  end;
  ANode.IteratorName := LToken.Spelling;
  ANode.IteratorRange := LToken.Range;
  DoAdvance();
  if not DoExpect(tkColonEqual, DoSpelled(':=')) then
    Exit(False);
  ANode.StartExpr := DoParseExpression(ecNormal);
  if DoFailed(ANode.StartExpr) then
    Exit(False);
  if DoCheck(tkKwDownto) then
    ANode.IsDownTo := True
  else if not DoCheck(tkKwTo) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_001, RSParExpected,
      [RSParShapeToDownto, DoTokenText(DoCurrent())]);
    Exit(False);
  end;
  DoAdvance();
  ANode.EndExpr := DoParseExpression(ecNormal);
  Result := not DoFailed(ANode.EndExpr);
end;

procedure TPCParser.DoParseRepeat(const AOwner: TList<TPCStmt>);
var
  LRange: TSourceRange;
  LNode: TPCRepeat;
begin
  // repeat stmt = "repeat" {statement} "until" expression ";". 'end' also
  // ends the list, so a missing until never takes an enclosing end; a missing
  // until or condition keeps the node, marked (PLAN-RECOVERY)
  LRange := DoStartRange();
  LNode := FAst.NewNode<TPCRepeat>();
  DoAdvance();
  DoParseStatementList(LNode.Stmts, [tkKwUntil, tkKwEnd]);
  if not DoExpect(tkKwUntil, DoSpelled('until')) then
  begin
    DoKeepRecovered(AOwner, LNode, LRange);
    Exit;
  end;
  LNode.UntilRange := FLastToken.Range;
  LNode.Condition := DoParseExpression(ecNormal);
  if DoFailed(LNode.Condition) then
  begin
    DoSkipStatement();
    DoKeepRecovered(AOwner, LNode, LRange);
    Exit;
  end;
  DoFinishSimple(AOwner, LNode, LRange);
end;

procedure TPCParser.DoParseMatch(const AOwner: TList<TPCStmt>);
var
  LRange: TSourceRange;
  LNode: TPCMatch;
  LComplete: Boolean;
  LStart: Integer;
begin
  // match stmt = "match" expression "of" {match arm} ["else" {statement}]
  // "end" ";" (BNF.md sec 5)
  LRange := DoStartRange();
  LNode := FAst.NewNode<TPCMatch>();
  DoAdvance();
  LNode.Subject := DoParseExpression(ecNormal);
  LComplete := DoParseHeaderEnd(not DoFailed(LNode.Subject), tkKwOf, DoSpelled('of'));
  while (not DoIsOneOf(DoCurrent().Kind, [tkKwElse, tkKwEnd, tkEOF])) and (not DoStopped()) and
    (not DoIsModuleItemStart()) do
  begin
    // An arm always consumes its first token; the guard keeps that a fact
    LStart := DoCurrentIndex();
    DoParseMatchArm(LNode);
    if DoCurrentIndex() = LStart then
    begin
      // Never taken (an arm consumes its first token); if it is, the arm
      // reported and the skipped token stays inside the marked match
      DoAdvance();
      LNode.IsRecovered := True;
    end;
  end;
  if DoMatch(tkKwElse) then
  begin
    LNode.HasElse := True;
    LNode.ElseRange := FLastToken.Range;
    DoParseStatementList(LNode.ElseStmts, [tkKwEnd]);
  end;
  DoParseCompoundEnd();
  DoFinishRange(LRange);
  LNode.Range := LRange;
  if not LComplete then
    LNode.IsRecovered := True;
  AOwner.Add(LNode);
end;

procedure TPCParser.DoParseMatchArm(const AMatch: TPCMatch);
var
  LRange: TSourceRange;
  LArm: TPCMatchArm;
  LLabelsOk: Boolean;
begin
  // match arm = match label {"," match label} ":" {statement}. A label list
  // that fails or lacks its ':' is reported once and skipped at depth 0 to its
  // ':' (the arm's statements still parse, so nothing cascades) or through a
  // ';'; the arm is kept, marked (PLAN-RECOVERY)
  LRange := DoStartRange();
  LArm := FAst.NewNode<TPCMatchArm>();
  LLabelsOk := DoParseMatchLabels(LArm);
  if LLabelsOk and (not DoCheck(tkColon)) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_001, RSParExpected, [DoSpelled(':'), DoTokenText(DoCurrent())]);
    LLabelsOk := False;
  end;
  if not LLabelsOk then
    DoSkipBalancedTo([tkColon, tkSemicolon, tkKwElse, tkKwEnd]);
  if not DoMatch(tkColon) then
  begin
    DoMatch(tkSemicolon);
    DoFinishRange(LRange);
    LArm.Range := LRange;
    LArm.IsRecovered := True;
    AMatch.Arms.Add(LArm);
    Exit;
  end;
  DoParseArmStatements(LArm.Stmts);
  DoFinishRange(LRange);
  LArm.Range := LRange;
  LArm.IsRecovered := not LLabelsOk;
  AMatch.Arms.Add(LArm);
end;

function TPCParser.DoParseMatchLabels(const AArm: TPCMatchArm): Boolean;
var
  LRange: TSourceRange;
  LLabel: TPCMatchLabel;
begin
  // match label {"," match label}, match label = expression [".." expression]
  // ('..' is no operator, so the low expression stops there). False =
  // reported once, nothing more parsed
  repeat
    LRange := DoStartRange();
    LLabel := FAst.NewNode<TPCMatchLabel>();
    LLabel.LowExpr := DoParseExpression(ecNormal);
    if DoFailed(LLabel.LowExpr) then
    begin
      DoFinishRange(LRange);
      LLabel.Range := LRange;
      LLabel.IsRecovered := True;
      AArm.Labels.Add(LLabel);
      Exit(False);
    end;
    if DoMatch(tkDotDot) then
    begin
      LLabel.HighExpr := DoParseExpression(ecNormal);
      if DoFailed(LLabel.HighExpr) then
      begin
        DoFinishRange(LRange);
        LLabel.Range := LRange;
        LLabel.IsRecovered := True;
        AArm.Labels.Add(LLabel);
        Exit(False);
      end;
    end;
    DoFinishRange(LRange);
    LLabel.Range := LRange;
    AArm.Labels.Add(LLabel);
  until not DoMatch(tkComma);
  Result := True;
end;

procedure TPCParser.DoParseArmStatements(const AOwner: TList<TPCStmt>);
begin
  // An arm's {statement}: up to else, end, EOF or the next arm's labels. A
  // token of PC_PAR_STMT_STARTERS never starts a label, so only other tokens
  // are tried as one (DoIsArmStart)
  while (not DoIsOneOf(DoCurrent().Kind, [tkKwElse, tkKwEnd, tkEOF])) and (not DoStopped()) and
    (not DoIsModuleItemStart()) do
  begin
    if (not DoIsOneOf(DoCurrent().Kind, PC_PAR_STMT_STARTERS)) and DoIsArmStart() then
      Exit;
    DoParseStatement(AOwner, True);
  end;
end;

function TPCParser.DoIsArmStart(): Boolean;
var
  LAttempt: TPCAttempt;
  LArm: TPCMatchArm;
begin
  // Pure look-ahead (templates.md A1): a label list that parses cleanly and is
  // followed by ':' starts the next arm. Never a statement: an expression
  // statement's expression is followed by ';', never ':'. Always restored;
  // the scratch arm stays an orphan in the arena
  LAttempt := DoSaveAttempt();
  LArm := FAst.NewNode<TPCMatchArm>();
  Result := DoParseMatchLabels(LArm) and DoCheck(tkColon) and DoAttemptClean(LAttempt);
  DoRestoreAttempt(LAttempt);
end;

procedure TPCParser.DoParseGuard(const AOwner: TList<TPCStmt>);
var
  LRange: TSourceRange;
  LNode: TPCGuard;
begin
  // guard stmt = "guard" {statement} ["except" {statement}]
  // ["finally" {statement}] "end" ";". Neither except nor finally is PR0052
  // at the token that ends the guard (BNF.md sec 5); that node is kept, marked
  LRange := DoStartRange();
  LNode := FAst.NewNode<TPCGuard>();
  DoAdvance();
  DoParseStatementList(LNode.GuardStmts, [tkKwExcept, tkKwFinally, tkKwEnd]);
  if DoMatch(tkKwExcept) then
  begin
    LNode.HasExcept := True;
    LNode.ExceptRange := FLastToken.Range;
    DoParseStatementList(LNode.ExceptStmts, [tkKwFinally, tkKwEnd]);
  end;
  if DoMatch(tkKwFinally) then
  begin
    LNode.HasFinally := True;
    LNode.FinallyRange := FLastToken.Range;
    DoParseStatementList(LNode.FinallyStmts, [tkKwEnd]);
  end;
  if not (LNode.HasExcept or LNode.HasFinally) then
    DoError(DoCurrent(), PC_ERR_PAR_052, RSParGuardEmpty, []);
  DoParseCompoundEnd();
  DoFinishRange(LRange);
  LNode.Range := LRange;
  LNode.IsRecovered := not (LNode.HasExcept or LNode.HasFinally);
  AOwner.Add(LNode);
end;

procedure TPCParser.DoParseReturn(const AOwner: TList<TPCStmt>);
var
  LRange: TSourceRange;
  LNode: TPCReturn;
begin
  // return stmt = "return" [expression] ";": no value when ';' or a token
  // that closes the statement list follows (a missing ';' is then reported)
  LRange := DoStartRange();
  LNode := FAst.NewNode<TPCReturn>();
  DoAdvance();
  if not DoIsOneOf(DoCurrent().Kind, [tkSemicolon, tkKwEnd, tkKwElse, tkKwUntil, tkKwExcept,
    tkKwFinally, tkEOF]) then
  begin
    LNode.ValueExpr := DoParseExpression(ecNormal);
    if DoFailed(LNode.ValueExpr) then
    begin
      DoSkipStatement();
      DoKeepRecovered(AOwner, LNode, LRange);
      Exit;
    end;
  end;
  DoFinishSimple(AOwner, LNode, LRange);
end;

procedure TPCParser.DoParseKeywordOnly(const AOwner: TList<TPCStmt>; const ANode: TPCStmt);
var
  LRange: TSourceRange;
begin
  // leave stmt / skip stmt = keyword ";" (BNF.md sec 5)
  LRange := DoStartRange();
  DoAdvance();
  DoFinishSimple(AOwner, ANode, LRange);
end;

procedure TPCParser.DoParseExprStatement(const AOwner: TList<TPCStmt>);
var
  LRange: TSourceRange;
  LFirst: TPCToken;
  LExpr: TPCExpr;
  LNode: TPCExprStmt;
  LMark: TPCSkipMark;
begin
  // expression statement = expression ";" (BNF.md sec 5): assignment, calls
  // (intrinsics included), C++ expressions. A top-level '=' compares, never
  // assigns (BNF.md sec 6): PR0048 at the statement's first token, node kept
  LRange := DoStartRange();
  LMark := DoMarkSkip();
  LFirst := DoCurrent();
  LExpr := DoParseExpression(ecNormal);
  if LExpr = nil then
  begin
    // Nothing consumed (DoParsePrimary reported at this token): the
    // statement's tokens become an error node
    DoSkipStatement();
    DoAddSkipped(AOwner, LMark);
    Exit;
  end;
  if LExpr is TPCErrorExpr then
  begin
    LNode := FAst.NewNode<TPCExprStmt>();
    LNode.Expr := LExpr;
    DoSkipStatement();
    DoKeepRecovered(AOwner, LNode, LRange);
    Exit;
  end;
  LNode := FAst.NewNode<TPCExprStmt>();
  LNode.Expr := LExpr;
  // F52: the statement the parser reported inside is kept recovered, so SEM
  // adds no second report for the same mistake (SM0613: '=' has no effect)
  if (LExpr is TPCBinary) and (TPCBinary(LExpr).Op = boEq) then
  begin
    DoError(LFirst, PC_ERR_PAR_048, RSParEqStatement, []);
    LNode.IsRecovered := True;
  end;
  DoFinishSimple(AOwner, LNode, LRange);
end;

procedure TPCParser.DoParseDirectiveStatement(const AOwner: TList<TPCStmt>);
var
  LToken: TPCToken;
  LKind: TPCBuildDirective;
  LDirective: TPCDirective;
  LMark: TPCSkipMark;
begin
  // @breakpoint / @message stand wherever a statement can (BNF.md sec 5, user
  // 2026-10-06): the breakpoint marks its own line for the debugger. Any other
  // build directive is PR0008 (@target is the filter's to report: skipped
  // silently, as at module level); an unknown one is PR0005 (DoParseDirectiveNode)
  LToken := DoCurrent();
  if TPCVocabulary.FindDirective(LToken.Spelling.Substring(1), LKind) and
    (not PC_BUILD_DIRECTIVES[LKind].IsStatement) then
  begin
    if not PC_BUILD_DIRECTIVES[LKind].IsFilterChecked then
      DoError(LToken, PC_ERR_PAR_008, RSParDirectivePlace, []);
    LMark := DoMarkSkip();
    DoAdvance();
    DoSkipStatement();
    DoAddSkipped(AOwner, LMark);
    Exit;
  end;
  LDirective := DoParseDirectiveNode(AOwner, True);
  if LDirective <> nil then
    AOwner.Add(LDirective);
end;

function TPCParser.DoParseHeaderEnd(const AHeaderOk: Boolean; const AKeyword: TPCTokenKind;
  const AWhat: string): Boolean;
begin
  // A statement header (condition, for range, match subject) ends at its
  // keyword (then, do, of). True = parsed and the keyword consumed. False =
  // reported once: a missing keyword after a parsed header is PR0001 and
  // nothing is skipped; a header that already reported is skipped at depth 0
  // to its keyword (consumed), or to ';' (consumed) or 'end'. Either way the
  // body parses next, so it never cascades, and the caller keeps the node,
  // marked (PLAN-RECOVERY)
  if AHeaderOk and DoMatch(AKeyword) then
    Exit(True);
  if AHeaderOk then
    DoError(DoCurrent(), PC_ERR_PAR_001, RSParExpected, [AWhat, DoTokenText(DoCurrent())])
  else
  begin
    DoSkipBalancedTo([AKeyword, tkSemicolon, tkKwEnd]);
    if not DoMatch(AKeyword) then
      DoMatch(tkSemicolon);
  end;
  Result := False;
end;

procedure TPCParser.DoParseCompoundEnd();
begin
  // "end" ";" closing a compound statement. Its lists stop at their
  // terminators, EOF or a module-level item start (F1), so a missing end is
  // reported once at that token (DoExpectEnd, B4); a missing ';' after a
  // present end is reported, nothing skipped
  if DoExpectEnd() then
    DoExpect(tkSemicolon, DoSpelled(';'));
end;

function TPCParser.DoIsModuleItemStart(): Boolean;
var
  LAt: Integer;
begin
  // An open statement list ends before this token (F1) and no recovery
  // skip passes it (A7). 'routine' starts an item only before its name,
  // after an optional linkage word (routine decl = "routine" [ linkage ]
  // identifier, BNF.md sec 3; DoParseLinkage's words): in 'routine(' or
  // 'routine clink(' it is a routine type inside the construct being
  // parsed or skipped (ptr to routine(...) in a cast, a var's type)
  if DoCheck(tkKwRoutine) then
  begin
    LAt := 1;
    if DoIsOneOf(DoPeek(1).Kind, [tkKwClink, tkKwCpplink]) then
      LAt := 2;
    Exit(DoPeek(LAt).Kind = tkIdentifier);
  end;
  Result := DoIsOneOf(DoCurrent().Kind, PC_PAR_MODULE_ITEM_STARTS);
end;

function TPCParser.DoExpectEnd(): Boolean;
var
  LToken: TPCToken;
begin
  // 'end' closing a block or a compound statement. Every construct still
  // open at one token has that one root cause (as the end of file, B4):
  // the missing end is reported once per token. True = consumed
  if DoMatch(tkKwEnd) then
    Exit(True);
  LToken := DoCurrent();
  if (not FEndReported) or (FEndReportedAt <> LToken.Range.StartByteOffset) then
  begin
    DoExpect(tkKwEnd, DoSpelled('end'));
    FEndReported := True;
    FEndReportedAt := LToken.Range.StartByteOffset;
  end;
  Result := False;
end;

procedure TPCParser.DoFinishSimple(const AOwner: TList<TPCStmt>; const ANode: TPCStmt;
  var ARange: TSourceRange);
var
  LOutcome: TPCTerminatorOutcome;
  LMark: TPCSkipMark;
begin
  // ";" ends a simple statement; the node is complete and kept either way. A
  // missing ';' is PR0001 just after it. When the next token starts a
  // statement or closes the list nothing is skipped (PLAN-RECOVERY target 4):
  // `a b;` is that one report and a second statement, so juxtaposition stays
  // an error (BNF.md sec 5). Otherwise the rest is skipped into an error node
  LOutcome := DoExpectTerminator(fcStatement);
  DoFinishRange(ARange);
  ANode.Range := ARange;
  AOwner.Add(ANode);
  if LOutcome = toMissing then
  begin
    LMark := DoMarkSkip();
    DoSkipStatement();
    DoAddSkipped(AOwner, LMark);
  end;
end;

procedure TPCParser.DoKeepRecovered(const AOwner: TList<TPCStmt>; const ANode: TPCStmt;
  var ARange: TSourceRange);
begin
  // A statement or declaration the parser reported inside: kept and marked,
  // its range over everything it consumed, skipped tokens included
  DoFinishRange(ARange);
  ANode.Range := ARange;
  ANode.IsRecovered := True;
  AOwner.Add(ANode);
end;

procedure TPCParser.DoReportPlacementInBody(const AOwner: TList<TPCStmt>);
var
  LMark: TPCSkipMark;
begin
  // cpp header|source sets the module-level placement; a body has none
  // (parser.md "Statements"): reported, skipped as a statement into an error
  // node (PLAN-RECOVERY)
  DoError(DoCurrent(), PC_ERR_PAR_050, RSParPlacementInBody, []);
  LMark := DoMarkSkip();
  DoAdvance();
  DoSkipStatement();
  DoAddSkipped(AOwner, LMark);
end;

procedure TPCParser.DoReportCppStatement(const AOwner: TList<TPCStmt>; const AHint: string);
var
  LMark: TPCSkipMark;
begin
  // A C++ statement keyword in a body (BNF.md sec 5): reported with the
  // PaskalCPP form, skipped as C++ delimits the statement (DoSkipCppStatement)
  // into an error node (PLAN-RECOVERY)
  DoError(DoCurrent(), PC_ERR_PAR_049, RSParCppStatement, [DoCurrent().Spelling, AHint]);
  LMark := DoMarkSkip();
  DoSkipCppStatement();
  DoAddSkipped(AOwner, LMark);
end;

procedure TPCParser.DoReportStrayCloser(const AOwner: TList<TPCStmt>);
var
  LMark: TPCSkipMark;
begin
  // ';' alone (there is no empty statement) or a word that only closes or
  // continues another construct (PC_PAR_STRAY_CLOSERS): consumed into an
  // error node (PLAN-RECOVERY)
  DoError(DoCurrent(), PC_ERR_PAR_001, RSParExpected,
    [RSParShapeStatement, DoTokenText(DoCurrent())]);
  LMark := DoMarkSkip();
  DoAdvance();
  DoAddSkipped(AOwner, LMark);
end;

procedure TPCParser.DoSkipCppStatement();
var
  LDepth: Integer;
  LKind: TPCTokenKind;
begin
  // Recovery after a C++ statement keyword (PR0049), the statement as C++
  // delimits it: through a depth-0 ';' or the '}' that closes its body (a
  // 'catch' after it continues a try), never past a depth-0 token that
  // closes the enclosing statement list, EOF or the module's 'end .'. The
  // keyword itself is the first token consumed
  LDepth := 0;
  while (not DoCheck(tkEOF)) and (not DoIsModuleEnd()) do
  begin
    LKind := DoCurrent().Kind;
    if (LDepth = 0) and DoIsOneOf(LKind, [tkKwEnd, tkKwElse, tkKwUntil, tkKwExcept,
      tkKwFinally]) then
      Exit;
    DoAdvance();
    if (LDepth = 0) and (LKind = tkSemicolon) then
      Exit;
    if DoIsOneOf(LKind, [tkLParen, tkLBracket, tkLBrace]) then
      Inc(LDepth)
    else if DoIsOneOf(LKind, [tkRParen, tkRBracket, tkRBrace]) and (LDepth > 0) then
    begin
      Dec(LDepth);
      if (LDepth = 0) and (LKind = tkRBrace) and (not DoCheck(tkKwCatch)) then
        Exit;
    end;
  end;
end;

class function TPCParser.DoFindCppStmtHint(const AKind: TPCTokenKind;
  out AHint: string): Boolean;
var
  LI: Integer;
begin
  // The PR0049 row of a C++ statement keyword (PC_PAR_CPP_STMT_HINTS)
  for LI := Low(PC_PAR_CPP_STMT_HINTS) to High(PC_PAR_CPP_STMT_HINTS) do
  begin
    if PC_PAR_CPP_STMT_HINTS[LI].Kind = AKind then
    begin
      AHint := PC_PAR_CPP_STMT_HINTS[LI].Hint;
      Exit(True);
    end;
  end;
  AHint := '';
  Result := False;
end;

procedure TPCParser.DoParseModuleBody();
var
  LRange: TSourceRange;
  LBlock: TPCBlock;
begin
  // module body = "begin" , { statement }; the module's 'end .' closes it.
  // Only an exe has one, and an exe must (BNF.md sec 1). An assumed kind
  // (PR0002 reported) is never checked; PR0017 stands at the module's end (B6)
  if not DoCheck(tkKwBegin) then
  begin
    if (FModule.ModuleKind = mkExe) and (not FKindAssumed) and DoIsModuleEnd() then
      DoError(DoCurrent(), PC_ERR_PAR_017, RSParNeedBody, []);
    Exit;
  end;
  if (FModule.ModuleKind <> mkExe) and (not FKindAssumed) then
    DoError(DoCurrent(), PC_ERR_PAR_016, RSParNoBody, [PC_PAR_KIND_NAMES[FModule.ModuleKind]]);

  // Parsed anyway: the AST states what was written
  LRange := DoStartRange();
  LBlock := FAst.NewNode<TPCBlock>();
  DoAdvance();
  DoParseStatementList(LBlock.Stmts, [tkKwEnd]);
  DoFinishRange(LRange);
  LBlock.Range := LRange;
  FModule.HasBody := True;
  FModule.Body := LBlock;
end;

function TPCParser.DoParseModuleEnd(): Boolean;
begin
  // end .  (BNF.md sec 1). A missing 'end' is reported once with whatever
  // else is open at that token (DoExpectEnd, F1). False = reported. The
  // 'end' consumed is the module's frame (TPCModule.EndRange), even when the
  // '.' is missing and the rest of the file becomes an error node
  if not DoExpectEnd() then
    Exit(False);
  FModule.EndRange := FLastToken.Range;
  Result := DoExpect(tkDot, DoSpelled('.'));
end;

procedure TPCParser.DoParseTests();
begin
  // { test block } after the module's end (BNF.md sec 1)
  while DoCheck(tkKwTest) and (not DoStopped()) do
    DoParseTest();
end;

procedure TPCParser.DoParseTest();
var
  LRange: TSourceRange;
  LTest: TPCTest;
  LName: TPCToken;
begin
  // test block = "test" , cstring , [ var block ] , block , ";"  (BNF.md sec 8).
  // The name is checked by the cstring rule (B3) and kept as written
  LRange := DoStartRange();
  LTest := FAst.NewNode<TPCTest>();
  DoAdvance();
  LName := DoCurrent();
  if LName.Kind <> tkStringLiteral then
  begin
    // Kept with no name, marked (PLAN-RECOVERY); a tkUnknown (a cut string)
    // carries the lexer's report
    DoError(LName, PC_ERR_PAR_001, RSParExpected, [RSParShapeCString, DoTokenText(LName)]);
    LTest.IsRecovered := True;
  end
  else
  begin
    // A plain name is decoded (and its errors reported) where its part is built
    if not DoIsPlainString(LName) then
      DoError(LName, PC_ERR_PAR_009, RSParBadString, [RSParNotPlainString]);
    LTest.TestName := DoNewStringLiteral(LName);
    DoAdvance();
  end;

  DoParseDeclBlocks(LTest.Decls, baTest);
  LTest.Body := DoParseBlock();
  if LTest.Body = nil then
  begin
    // A test without its body is marked (PLAN-RECOVERY)
    LTest.IsRecovered := True;
    DoSkipFrame();
  end
  else if FLastToken.Kind = tkKwEnd then
  begin
    // Complete: a missing ';' is reported, nothing skipped. A block whose
    // end is missing has reported that already (one root cause)
    DoExpect(tkSemicolon, DoSpelled(';'));
  end;
  DoFinishRange(LRange);
  LTest.Range := LRange;
  FModule.Tests.Add(LTest);
end;

function TPCParser.DoNewStringLiteral(const AToken: TPCToken): TPCLiteral;
var
  LParts: TArray<TPCLiteralPart>;
begin
  // One string token as written (PARSER-EXPR joins adjacent ones)
  Result := FAst.NewNode<TPCLiteral>();
  Result.LiteralKind := lkString;
  Result.Text := AToken.Text;
  SetLength(LParts, 1);
  LParts[0] := DoLiteralPartOf(AToken);
  Result.Parts := LParts;
  Result.Range := AToken.Range;
end;

function TPCParser.DoLiteralPartOf(const AToken: TPCToken): TPCLiteralPart;
var
  LRuns: TArray<TPCSpellRun>;
begin
  // One string token as a literal part with every literal fact the token
  // carries: the one place a part is built (inputs.md F1). A plain part is
  // decoded here, once, by the one cstring rule (PR0009 / PR0021), and keeps
  // its value and its value map (decoded byte -> .pcpp position, P-STRPOS);
  // a prefixed / raw / suffixed part is C++, clang judges it (sem\module.md F-M1)
  Result.Text := AToken.Text;
  Result.CppText := AToken.Text;
  Result.Range := AToken.Range;
  Result.LiteralPrefix := AToken.LiteralPrefix;
  Result.IsRawString := AToken.IsRawString;
  Result.Suffix := AToken.Suffix;
  Result.IsUserDefined := AToken.IsUserDefined;
  Result.HasValue := False;
  Result.Value := '';
  Result.ValueMap := nil;
  if DoIsPlainString(AToken) then
  begin
    Result.HasValue := DoDecodeCString(AToken, True, Result.Value, LRuns);
    if Result.HasValue then
      Result.ValueMap := DoValueMapOf(AToken, Result.Value, LRuns);
    // F65: the decoder judged every escape (PR0009 / PR0021); C++ is given
    // the value's spelling, so clang has nothing to say again. A raw part
    // holds no escapes
    if not AToken.IsRawString then
      Result.CppText := TPCCString.CppSpelling(AToken.Text);
  end;
end;

function TPCParser.DoSpellOffsets(const AToken: TPCToken): TArray<Int64>;
var
  LSource: TPCSourceText;
  LOffsets: TArray<Int64>;
  LLength: Integer;
  LIndex: Integer;
  LP: Int64;
  LEnd: Int64;
  LByte: Integer;
  LStep: Int64;
  LPhysical: Boolean;
begin
  // P-STRPOS (strpos.md Key Details): the physical offset of every UTF-16
  // index of AToken.Spelling (1-based; both units of a surrogate pair get
  // their code point's offset; -1 = not reached). Spelling dropped every
  // splice before a raw string's opening quote and none after it
  // (TPCSourceText.Spelling), so the walk steps logically up to and
  // including the first '"', then physically for a raw string (a raw body's
  // '\'+newline is content, never a splice) and logically for a plain one.
  // A multi-byte code point is contiguous (a splice never cuts one): step
  // its length, then Logical
  LSource := FCursor.SourceText();
  LLength := Length(AToken.Spelling);
  SetLength(LOffsets, LLength + 1);
  for LIndex := 0 to LLength do
    LOffsets[LIndex] := -1;
  LEnd := Int64(AToken.Range.EndByteOffset);
  LP := LSource.Logical(Int64(AToken.Range.StartByteOffset));
  LPhysical := False;
  LIndex := 1;
  while (LIndex <= LLength) and (LP < LEnd) do
  begin
    LByte := LSource.ByteAt(LP);
    LStep := LSource.Utf8Length(LP);
    LOffsets[LIndex] := LP;
    // A 4-byte sequence is a surrogate pair in the spelling: two indices
    if (LStep = 4) and (LIndex < LLength) then
    begin
      Inc(LIndex);
      LOffsets[LIndex] := LP;
    end;
    Inc(LIndex);
    // A raw string's opening quote is its last logical byte
    if AToken.IsRawString and (not LPhysical) and (LByte = Ord('"')) then
      LPhysical := True;
    if LPhysical then
      LP := LP + LStep
    else
      LP := LSource.Logical(LP + LStep);
  end;
  Result := LOffsets;
end;

function TPCParser.DoSpellOffsetAt(const AOffsets: TArray<Int64>;
  const AIndex: Integer): Int64;
begin
  // F-P2: a spell index the walk did not reach means Decode's runs and the
  // token's Spelling disagree: a compiler defect, never a short map
  if (AIndex < 1) or (AIndex > High(AOffsets)) or (AOffsets[AIndex] < 0) then
    raise EArgumentException.CreateFmt(RSParValueMapSpellIndex, [AIndex, High(AOffsets)]);
  Result := AOffsets[AIndex];
end;

function TPCParser.DoValueMapOf(const AToken: TPCToken; const AValue: string;
  const ARuns: TArray<TPCSpellRun>): TArray<TPCValueRun>;
var
  LSource: TPCSourceText;
  LOffsets: TArray<Int64>;
  LMap: TArray<TPCValueRun>;
  LCount: Integer;
  LTotal: Integer;
  LK: Integer;
  LRunEnd: Integer;
  LValueAt: Integer;
  LIndex: Integer;
  LOffset: Int64;
  LStep: Int64;
  LNextOffset: Int64;
begin
  // P-STRPOS (strpos.md Key Details): spell runs (value order) -> value runs
  // at .pcpp positions. An escape run is one value run at its '\'. A copy run
  // walks its code points and is split where one's offset is not the
  // previous one's offset + its UTF-8 length (a splice sat between them): the
  // split run starts at the value offset of the bytes copied so far. A copy
  // run ends at the next run's ValueOffset, the last one at the value's UTF-8
  // byte count (Decode returns only valid UTF-8, so the count is exact)
  LSource := FCursor.SourceText();
  LOffsets := DoSpellOffsets(AToken);
  LTotal := TEncoding.UTF8.GetByteCount(AValue);
  LMap := nil;
  LCount := 0;
  for LK := 0 to High(ARuns) do
  begin
    if not ARuns[LK].IsCopy then
    begin
      DoAddValueRun(LMap, LCount, ARuns[LK].ValueOffset,
        DoSpellOffsetAt(LOffsets, ARuns[LK].SpellIndex), False);
      Continue;
    end;
    if LK < High(ARuns) then
      LRunEnd := ARuns[LK + 1].ValueOffset
    else
      LRunEnd := LTotal;
    LValueAt := ARuns[LK].ValueOffset;
    LIndex := ARuns[LK].SpellIndex;
    LNextOffset := -1;
    while LValueAt < LRunEnd do
    begin
      LOffset := DoSpellOffsetAt(LOffsets, LIndex);
      LStep := LSource.Utf8Length(LOffset);
      // The run's first code point, or one a splice separates from the last
      if LOffset <> LNextOffset then
        DoAddValueRun(LMap, LCount, LValueAt, LOffset, True);
      LNextOffset := LOffset + LStep;
      LValueAt := LValueAt + Integer(LStep);
      // A 4-byte code point is two UTF-16 units of the spelling
      if LStep = 4 then
        Inc(LIndex, 2)
      else
        Inc(LIndex);
    end;
  end;
  SetLength(LMap, LCount);
  Result := LMap;
end;

procedure TPCParser.DoAddValueRun(var ARuns: TArray<TPCValueRun>; var ACount: Integer;
  const AValueOffset: Integer; const AOffset: Int64; const AIsCopy: Boolean);
var
  LRange: TSourceRange;
begin
  // One value run at the .pcpp position of the byte at AOffset: FillRange's
  // line and column, the one position rule (no second column count)
  if ACount = Length(ARuns) then
  begin
    if ACount = 0 then
      SetLength(ARuns, 8)
    else
      SetLength(ARuns, ACount * 2);
  end;
  FCursor.SourceText().FillRange(LRange, AOffset, AOffset + 1);
  ARuns[ACount].ValueOffset := AValueOffset;
  ARuns[ACount].Line := LRange.StartLine;
  ARuns[ACount].Column := LRange.StartColumn;
  ARuns[ACount].IsCopy := AIsCopy;
  Inc(ACount);
end;

procedure TPCParser.DoExpectEOF();
var
  LToken: TPCToken;
begin
  // After the test blocks only EOF; anything else is PR0020, once
  LToken := DoCurrent();
  if LToken.Kind <> tkEOF then
    DoError(LToken, PC_ERR_PAR_020, RSParAfterEnd, [LToken.Spelling]);
end;

function TPCParser.DoSaveAttempt(): TPCAttempt;
begin
  // The one record every backtracking try saves (templates.md A1)
  Result.Position := FCursor.SavePosition();
  Result.ReportCount := FErrors.Count();
  Result.EofReported := FEofReported;
  Result.EndReported := FEndReported;
  Result.EndReportedAt := FEndReportedAt;
  Result.LastToken := FLastToken;
  Result.HasLast := FHasLast;
end;

procedure TPCParser.DoRestoreAttempt(const AAttempt: TPCAttempt);
begin
  // Undo a try: the cursor (and every split made after the save), every
  // report it added (warnings too), the EOF flag, the missing-end mark, the
  // last consumed token. Nodes it built stay orphans in the arena; nothing
  // references them
  FCursor.RestorePosition(AAttempt.Position);
  FErrors.TruncateTo(AAttempt.ReportCount);
  FEofReported := AAttempt.EofReported;
  FEndReported := AAttempt.EndReported;
  FEndReportedAt := AAttempt.EndReportedAt;
  FLastToken := AAttempt.LastToken;
  FHasLast := AAttempt.HasLast;
end;

function TPCParser.DoAttemptClean(const AAttempt: TPCAttempt): Boolean;
begin
  // Nothing reported since the save, no warning either (A2): an accepted try
  // reports exactly what a direct parse would. TErrors.Add drops errors past
  // the budget, so under a full budget no try is clean
  Result := (FErrors.Count() = AAttempt.ReportCount) and (not DoStopped());
end;

function TPCParser.DoScanBalanced(out ALast: Integer): Boolean;
var
  LDepth: Integer;
  LKind: TPCTokenKind;
begin
  // The one balanced walker (verbatim-expr.md V1). Current is ( [ or {; walks
  // through the closer that brings the depth back to 0, counting ( ) [ ] { }
  // together (a mismatched closer is clang's to report). Strings and comments
  // are whole tokens or trivia. ALast = index of that closer, consumed.
  // False = EOF first, nothing reported here, ALast -1
  ALast := -1;
  LDepth := 0;
  while not DoCheck(tkEOF) do
  begin
    LKind := DoCurrent().Kind;
    if DoIsOneOf(LKind, [tkLParen, tkLBracket, tkLBrace]) then
      Inc(LDepth)
    else if DoIsOneOf(LKind, [tkRParen, tkRBracket, tkRBrace]) then
      Dec(LDepth);
    if LDepth = 0 then
    begin
      ALast := DoCurrentIndex();
      DoAdvance();
      Exit(True);
    end;
    DoAdvance();
  end;
  Result := False;
end;

procedure TPCParser.DoReportNeverClosed(const AOpen: TPCToken);
var
  LCloser: string;
begin
  // F56: DoScanBalanced ran to EOF from AOpen. The mistake is the opener, so
  // the report goes there (it went to EOF, past 'end.', far from its cause)
  if AOpen.Kind = tkLBracket then
    LCloser := ']'
  else if AOpen.Kind = tkLBrace then
    LCloser := '}'
  else
    LCloser := ')';
  DoError(AOpen, PC_ERR_PAR_063, RSParNeverClosed, [AOpen.Spelling, LCloser]);
  // The scan ate the file: this group is the root cause of everything still
  // open at EOF, so the end of file counts as reported (R7, as a reported span
  // that runs to EOF: DoEndsInReportedSpan)
  FEofReported := True;
end;

procedure TPCParser.DoSkipBalancedTo(const AStops: array of TPCTokenKind);
var
  LDepth: Integer;
  LKind: TPCTokenKind;
begin
  // Local recovery inside a construct: up to (not through) the first depth-0
  // token of AStops, counting ( ) [ ] { } opened during the skip; never past
  // EOF or the module's 'end .'
  LDepth := 0;
  while (not DoCheck(tkEOF)) and (not DoIsModuleEnd()) do
  begin
    LKind := DoCurrent().Kind;
    if (LDepth = 0) and DoIsOneOf(LKind, AStops) then
      Exit;
    if DoIsOneOf(LKind, [tkLParen, tkLBracket, tkLBrace]) then
      Inc(LDepth)
    else if DoIsOneOf(LKind, [tkRParen, tkRBracket, tkRBrace]) and (LDepth > 0) then
      Dec(LDepth);
    DoAdvance();
  end;
end;

procedure TPCParser.DoSkipPastParen(const AStops: array of TPCTokenKind);
begin
  // Recovery inside ( ... ): up to the first depth-0 stop, then the ')' when it
  // is the one found
  DoSkipBalancedTo(AStops);
  DoMatch(tkRParen);
end;

procedure TPCParser.DoFillVerbatimUpTo(const AFirst: Integer; const ALast: Integer;
  const ALastToken: TPCToken; var AVerbatim: TPCVerbatim);
var
  LFirstToken: TPCToken;
  LToken: TPCToken;
  LSource: TPCSourceText;
  LBuilder: TStringBuilder;
  LPos: Int64;
  LFrom: Int64;
  LEnd: Int64;
  LByte: Integer;
  LI: Integer;
begin
  // F1 (BNF.md sec 10): the bytes [first start, last end) of tokens
  // AFirst..ALast. Each token's [TriviaStart, end) is copied (the first one
  // from its own start); every byte the conditional filter dropped between
  // two of them becomes a space, CR and LF kept, so lines and byte columns
  // match the source. A token's TriviaStart is the end of the token the lexer
  // emitted before it, so it never lies before the previous active token's end.
  // The lines that start inside a copied C++ token or comment come from the
  // lexer's marks in the same walk (R23): Text and InsideLines cannot disagree.
  // ALastToken is token ALast as the cursor presents it: the whole token or a
  // split piece (the '>' of a '>>' that ends a cpp type id, types.md T17); its
  // end ends the copy. AFirst is always a whole token (or a first piece, which
  // starts where its token starts)
  LFirstToken := FCursor.TokenAt(AFirst);
  LSource := FCursor.SourceText();
  AVerbatim.InsideLines := nil;
  LBuilder := TStringBuilder.Create();
  try
    LPos := Int64(LFirstToken.Range.StartByteOffset);
    for LI := AFirst to ALast do
    begin
      LToken := FCursor.TokenAt(LI);
      if LI = AFirst then
        LFrom := Int64(LToken.Range.StartByteOffset)
      else
        LFrom := Int64(LToken.TriviaStart);
      if LI = ALast then
        LEnd := Int64(ALastToken.Range.EndByteOffset)
      else
        LEnd := Int64(LToken.Range.EndByteOffset);
      while LPos < LFrom do
      begin
        LByte := LSource.ByteAt(LPos);
        if (LByte = 13) or (LByte = 10) then
          LBuilder.Append(Char(LByte))
        else
          LBuilder.Append(' ');
        Inc(LPos);
      end;
      LBuilder.Append(FCursor.SourceSlice(UInt64(LFrom), UInt64(LEnd)));
      AVerbatim.InsideLines := AVerbatim.InsideLines + FRawStream.InsideLines(LFrom, LEnd);
      LPos := LEnd;
    end;
    AVerbatim.Text := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;

  AVerbatim.Range.Clear();
  AVerbatim.Range.Filename := LFirstToken.Range.Filename;
  AVerbatim.Range.StartLine := LFirstToken.Range.StartLine;
  AVerbatim.Range.StartColumn := LFirstToken.Range.StartColumn;
  AVerbatim.Range.StartByteOffset := LFirstToken.Range.StartByteOffset;
  AVerbatim.Range.EndLine := ALastToken.Range.EndLine;
  AVerbatim.Range.EndColumn := ALastToken.Range.EndColumn;
  AVerbatim.Range.EndByteOffset := ALastToken.Range.EndByteOffset;
end;

function TPCParser.DoIsRecoveryStop(): Boolean;
begin
  // A token a recovery skip never passes: the next declaration, a body, a
  // section, the module's end
  Result := DoIsDeclStart() or DoIsOneOf(DoCurrent().Kind, [tkKwBegin, tkKwInitialize,
    tkKwFinalize]) or DoIsModuleEnd();
end;

procedure TPCParser.DoSkipItem();
begin
  // Recovery after a failed declaration item: through its ';', unless the
  // failure stopped at a recovery stop (nothing of that is skipped). Inside a
  // statement (a body's declaration block) never past a token that closes
  // the enclosing statement list
  if DoIsRecoveryStop() then
    Exit;
  if FStmtDepth > 0 then
    DoSkipStatement()
  else
    DoSkipFrame();
end;

procedure TPCParser.DoRecoverItem(const ADecl: TPCDecl; var ARange: TSourceRange);
begin
  // A declaration item the parser reported inside: the rest of it is skipped
  // (DoSkipItem) and the item kept, marked, with its name (PLAN-RECOVERY)
  DoSkipItem();
  DoFinishRange(ARange);
  ADecl.Range := ARange;
  ADecl.IsRecovered := True;
end;

procedure TPCParser.DoSkipMember();
begin
  // Recovery inside an aggregate: through the member's ';', never past the
  // aggregate's 'end'
  DoSkipBalancedTo([tkSemicolon, tkKwEnd]);
  DoMatch(tkSemicolon);
end;

function TPCParser.DoParseExpression(const AContext: TPCExprContext): TPCExpr;
begin
  // expression = assign expr (BNF.md sec 6): the Pratt loop from the lowest
  // power. ecTemplateArg: the '>' family ends it (expr.md). nil = reported
  // with nothing consumed; a TPCErrorExpr = reported after consuming
  // (PLAN-RECOVERY)
  Result := DoParseBinary(0, AContext);
end;

function TPCParser.DoParseConstExprIn(const AStops: array of TPCTokenKind): TPCExpr;
begin
  // A constant expression inside a construct (align, bitfield width, choice
  // value; BNF.md sec 4, T9). DoFailed = reported once, skipped up to a
  // depth-0 stop (not consumed); the owner covers the skip
  Result := DoParseExpression(ecNormal);
  if DoFailed(Result) then
    DoSkipBalancedTo(AStops);
end;

function TPCParser.DoParseRange(out ALow: TPCExpr; out AHigh: TPCExpr;
  const ACloser: TPCTokenKind): Boolean;
begin
  // expression ".." expression (array bounds): '..' is no operator, so the low
  // expression stops there. False = reported once, skipped up to ACloser or
  // ';' (not consumed)
  AHigh := nil;
  ALow := DoParseExpression(ecNormal);
  if not DoFailed(ALow) then
  begin
    if DoExpect(tkDotDot, DoSpelled('..')) then
      AHigh := DoParseExpression(ecNormal);
  end;
  Result := (not DoFailed(ALow)) and (not DoFailed(AHigh));
  if not Result then
    DoSkipBalancedTo([ACloser, tkSemicolon]);
end;

procedure TPCParser.DoParseDeclaration(const AOwner: TList<TPCStmt>; const AExported: Boolean);
var
  LKind: TPCTokenKind;
  LDecl: TPCDecl;
  LMark: TPCSkipMark;
begin
  // declaration (BNF.md sec 3), the PaskalCPP forms: a var / const / type
  // block, or one routine / forward. The caller checked the starter
  LKind := DoCurrent().Kind;
  if (LKind = tkKwVar) or (LKind = tkKwConst) or (LKind = tkKwType) then
  begin
    DoParseDeclBlock(AOwner, LKind, AExported, False);
    Exit;
  end;
  if LKind = tkKwRoutine then
  begin
    AOwner.Add(DoParseRoutineDecl(AExported));
    Exit;
  end;
  // A forward that names neither a routine nor a type keeps nothing of its
  // own: its tokens become an error node
  LMark := DoMarkSkip();
  LDecl := DoParseForward(AExported);
  if LDecl <> nil then
    AOwner.Add(LDecl)
  else
    DoAddSkipped(AOwner, LMark);
end;

procedure TPCParser.DoParseDeclBlock(const AOwner: TList<TPCStmt>;
  const ABlockKind: TPCTokenKind; const AExported: Boolean; const AInArm: Boolean);
var
  LDecl: TPCDecl;
  LItems: Integer;
  LFollow: TPCFollowContext;
begin
  // var | const | type block = keyword , { item } (BNF.md sec 3, sec 4): one
  // node per item, no block node (X4); every item carries AExported (X2). The
  // block ends at the first token that is not an item start (X1), so C++ after
  // a module-level block ('int x;') stays C++. A failed item reports once and
  // is kept, marked (PLAN-RECOVERY). Directly in a match arm (AInArm) only the
  // first item is certain: before every later one, labels followed by ':'
  // start the next arm and end the block (BNF.md sec 5, user 2026-10-06).
  // The keyword commits the first item: in declaration shape with the other
  // separator ('const C = 1;') it is still an item, reported at the
  // separator and kept, never left to the C++ span (DESIGN sec 5). At module
  // level every item in that shape is one ('B = 2;' after a valid item):
  // 'name =' / 'name :' never starts a C++ declaration there. In a body a
  // later 'B = 2' is a statement ('=' is equality), so only the first counts
  if AOwner = FModule.Decls then
    LFollow := fcModule
  else if ABlockKind = tkKwVar then
    LFollow := fcVarItem
  else if ABlockKind = tkKwConst then
    LFollow := fcConstItem
  else
    LFollow := fcTypeItem;
  DoAdvance();
  LItems := 0;
  while (DoIsItemStart(ABlockKind) or (((LItems = 0) or (LFollow = fcModule)) and DoIsItemShape())) and
    (not DoStopped()) do
  begin
    if AInArm and (LItems > 0) and DoIsArmStart() then
      Exit;
    Inc(LItems);
    if ABlockKind = tkKwVar then
      LDecl := DoParseVarDecl(AExported, LFollow)
    else if ABlockKind = tkKwConst then
      LDecl := DoParseConstDecl(AExported, LFollow)
    else
      LDecl := DoParseTypeDecl(AExported, LFollow);
    AOwner.Add(LDecl);
  end;
end;

function TPCParser.DoIsItemStart(const ABlockKind: TPCTokenKind): Boolean;
begin
  // The item shape by 2-token lookahead (X1): var / const item = identifier
  // ':', type item = identifier '='
  if DoCurrent().Kind <> tkIdentifier then
    Exit(False);
  if ABlockKind = tkKwType then
    Result := DoPeek(1).Kind = tkEqual
  else
    Result := DoPeek(1).Kind = tkColon;
end;

function TPCParser.DoIsItemShape(): Boolean;
begin
  // Any declaration item's shape, whichever block: identifier ':' or '='
  // (the shape DoIsDeclStart commits a module-level block on)
  Result := (DoCurrent().Kind = tkIdentifier) and
    ((DoPeek(1).Kind = tkColon) or (DoPeek(1).Kind = tkEqual));
end;

function TPCParser.DoIsBodyStart(): Boolean;
begin
  // A routine or method body follows: its declaration blocks or its begin
  Result := DoIsOneOf(DoCurrent().Kind, [tkKwVar, tkKwConst, tkKwType, tkKwBegin]);
end;

function TPCParser.DoParseVarDecl(const AExported: Boolean;
  const AFollow: TPCFollowContext): TPCVarDecl;
var
  LRange: TSourceRange;
  LDecl: TPCVarDecl;
  LArgsRange: TSourceRange;
begin
  // var decl = identifier ":" type expr [ "(" [ arg list ] ")" | "=" expression ] ";"
  // [ external clause ]
  // (BNF.md sec 3); the clause follows the decl's own ';'. Range = identifier
  // .. the last ';'. Never nil: an item reported inside is kept, marked, its
  // name declared (PLAN-RECOVERY)
  LRange := DoStartRange();
  LDecl := FAst.NewNode<TPCVarDecl>();
  LDecl.DeclName := DoCurrent().Spelling;
  LDecl.NameRange := DoCurrent().Range;
  LDecl.IsExported := AExported;
  DoAdvance();
  Result := LDecl;
  // ':' is certain for an item DoIsItemStart took; a block's first item may
  // spell '=' (DoIsItemShape): reported there, kept, its name declared
  if not DoExpect(tkColon, DoSpelled(':')) then
  begin
    DoRecoverItem(LDecl, LRange);
    Exit;
  end;
  LDecl.TypeExpr := DoParseTypeExpr();
  if DoTypeFailed(LDecl.TypeExpr) then
  begin
    DoRecoverItem(LDecl, LRange);
    Exit;
  end;
  // PLAN-OBJECT D3 / Q1: `LV: TFoo(1, 2);` builds the object with the init
  // that takes the arguments (SEM judges the type and picks the init); the
  // list replaces '= value'
  if DoCheck(tkLParen) then
  begin
    LArgsRange := DoStartRange();
    LDecl.InitCall := FAst.NewNode<TPCCall>();
    if not DoParseArgList(LDecl.InitCall.Args, tkRParen, DoSpelled(')')) then
    begin
      DoFinishRange(LArgsRange);
      LDecl.InitCall.Range := LArgsRange;
      LDecl.InitCall.IsRecovered := True;
      DoRecoverItem(LDecl, LRange);
      Exit;
    end;
    DoFinishRange(LArgsRange);
    LDecl.InitCall.Range := LArgsRange;
  end
  else if DoMatch(tkEqual) then
  begin
    LDecl.InitExpr := DoParseExpression(ecNormal);
    if DoFailed(LDecl.InitExpr) then
    begin
      DoRecoverItem(LDecl, LRange);
      Exit;
    end;
  end;
  if DoExpectTerminator(AFollow) = toMissing then
  begin
    DoRecoverItem(LDecl, LRange);
    Exit;
  end;
  if DoCheck(tkKwExternal) and (not DoParseExternalClause(LDecl.ExternalClause, AFollow)) then
    LDecl.IsRecovered := True;
  DoFinishRange(LRange);
  LDecl.Range := LRange;
end;

function TPCParser.DoParseConstDecl(const AExported: Boolean;
  const AFollow: TPCFollowContext): TPCConstDecl;
var
  LRange: TSourceRange;
  LDecl: TPCConstDecl;
begin
  // const decl = identifier ":" type expr "=" expression ";" (BNF.md sec 3;
  // the type is required). Never nil: an item reported inside is kept,
  // marked, its name declared (PLAN-RECOVERY)
  LRange := DoStartRange();
  LDecl := FAst.NewNode<TPCConstDecl>();
  LDecl.DeclName := DoCurrent().Spelling;
  LDecl.NameRange := DoCurrent().Range;
  LDecl.IsExported := AExported;
  DoAdvance();
  Result := LDecl;
  // ':' as DoParseVarDecl: an untyped 'C = 1' is reported at its '='
  if not DoExpect(tkColon, DoSpelled(':')) then
  begin
    DoRecoverItem(LDecl, LRange);
    Exit;
  end;
  LDecl.TypeExpr := DoParseTypeExpr();
  if DoTypeFailed(LDecl.TypeExpr) or (not DoExpect(tkEqual, DoSpelled('='))) then
  begin
    DoRecoverItem(LDecl, LRange);
    Exit;
  end;
  LDecl.ValueExpr := DoParseExpression(ecNormal);
  // Short-circuit: the terminator is only expected after a value parsed
  if DoFailed(LDecl.ValueExpr) or (DoExpectTerminator(AFollow) = toMissing) then
  begin
    DoRecoverItem(LDecl, LRange);
    Exit;
  end;
  DoFinishRange(LRange);
  LDecl.Range := LRange;
end;

function TPCParser.DoParseTypeDecl(const AExported: Boolean;
  const AFollow: TPCFollowContext): TPCTypeDecl;
var
  LRange: TSourceRange;
  LDecl: TPCTypeDecl;
begin
  // type decl = identifier "=" type def ";" (BNF.md sec 4). Never nil: an item
  // reported inside is kept, marked, its name declared (PLAN-RECOVERY)
  LRange := DoStartRange();
  LDecl := FAst.NewNode<TPCTypeDecl>();
  LDecl.DeclName := DoCurrent().Spelling;
  LDecl.NameRange := DoCurrent().Range;
  LDecl.IsExported := AExported;
  DoAdvance();
  Result := LDecl;
  // '=' as DoParseVarDecl's ':': a 'T: int32' type item is reported at its ':'
  if not DoExpect(tkEqual, DoSpelled('=')) then
  begin
    DoRecoverItem(LDecl, LRange);
    Exit;
  end;
  LDecl.TypeDef := DoParseTypeDef();
  // A type definition kept marked (A5) marks its declaration too: uses of
  // the name resolve to it and are poisoned silently (r3)
  if DoTypeFailed(LDecl.TypeDef) or (DoExpectTerminator(AFollow) = toMissing) then
  begin
    DoRecoverItem(LDecl, LRange);
    Exit;
  end;
  DoFinishRange(LRange);
  LDecl.Range := LRange;
end;

function TPCParser.DoParseRoutineDecl(const AExported: Boolean): TPCRoutine;
var
  LRange: TSourceRange;
  LRoutine: TPCRoutine;
begin
  // routine decl = "routine" [ linkage ] identifier [ param list ] [ ":" type expr ]
  //   ";" ( external clause | routine body ) (BNF.md sec 3). Linkage as written
  // (lnNone when absent: the cpplink default and overload demotion are SEM's).
  // A header error still parses a following body (X6); the routine is kept,
  // marked (PLAN-RECOVERY)
  LRange := DoStartRange();
  LRoutine := FAst.NewNode<TPCRoutine>();
  LRoutine.RoutineKind := rnRoutine;
  LRoutine.IsExported := AExported;
  DoAdvance();
  LRoutine.Linkage := DoParseLinkage();
  Result := LRoutine;
  if not DoParseSignature(LRoutine, fcSignature) then
  begin
    if not DoIsBodyStart() then
      DoSkipItem();
    if DoIsBodyStart() then
      DoParseRoutineBody(LRoutine, baRoutine);
    DoFinishRange(LRange);
    LRoutine.Range := LRange;
    LRoutine.IsRecovered := True;
    Exit;
  end;
  if DoCheck(tkKwExternal) then
  begin
    if not DoParseExternalClause(LRoutine.ExternalClause, fcModule) then
      LRoutine.IsRecovered := True;
  end
  else
    DoParseRoutineBody(LRoutine, baRoutine);
  DoFinishRange(LRange);
  LRoutine.Range := LRange;
end;

function TPCParser.DoParseForward(const AExported: Boolean): TPCDecl;
var
  LRange: TSourceRange;
  LRoutine: TPCRoutine;
  LType: TPCTypeDecl;
  LToken: TPCToken;
begin
  // forward decl = "forward" ( "routine" [ linkage ] identifier [ param list ]
  //   [ ":" type expr ] | "type" identifier ) ";" (BNF.md sec 3): a TPCRoutine or
  // a TPCTypeDecl with IsForward, no body / TypeDef. Matching is SEM's. nil =
  // neither routine nor type: the caller keeps the tokens as an error node
  Result := nil;
  LRange := DoStartRange();
  DoAdvance();
  if DoMatch(tkKwRoutine) then
  begin
    LRoutine := FAst.NewNode<TPCRoutine>();
    LRoutine.RoutineKind := rnRoutine;
    LRoutine.IsForward := True;
    LRoutine.IsExported := AExported;
    LRoutine.Linkage := DoParseLinkage();
    if not DoParseSignature(LRoutine, fcModule) then
    begin
      DoSkipItem();
      DoFinishRange(LRange);
      LRoutine.Range := LRange;
      LRoutine.IsRecovered := True;
      Exit(LRoutine);
    end;
    DoFinishRange(LRange);
    LRoutine.Range := LRange;
    Exit(LRoutine);
  end;
  LToken := DoCurrent();
  if not DoMatch(tkKwType) then
  begin
    DoError(LToken, PC_ERR_PAR_001, RSParExpected, [RSParShapeForward, DoTokenText(LToken)]);
    DoSkipItem();
    Exit;
  end;
  LToken := DoCurrent();
  if LToken.Kind <> tkIdentifier then
  begin
    DoError(LToken, PC_ERR_PAR_001, RSParExpected, [RSParShapeName, DoTokenText(LToken)]);
    DoSkipItem();
    Exit;
  end;
  LType := FAst.NewNode<TPCTypeDecl>();
  LType.DeclName := LToken.Spelling;
  LType.NameRange := LToken.Range;
  LType.IsForward := True;
  LType.IsExported := AExported;
  DoAdvance();
  // A forward is module level: a missing ';' is inserted, nothing skipped
  DoExpectTerminator(fcModule);
  DoFinishRange(LRange);
  LType.Range := LRange;
  Result := LType;
end;

function TPCParser.DoParseLinkage(): TPCLinkage;
begin
  // linkage = "clink" | "cpplink" (BNF.md sec 3); lnNone = not written
  if DoMatch(tkKwClink) then
    Result := lnC
  else if DoMatch(tkKwCpplink) then
    Result := lnCpp
  else
    Result := lnNone;
end;

function TPCParser.DoParseSignature(const ARoutine: TPCRoutine;
  const AFollow: TPCFollowContext): Boolean;
var
  LToken: TPCToken;
  LVariadic: Boolean;
  LVariadicRange: TSourceRange;
begin
  // identifier [ param list ] [ ":" type expr ] ";" - the part routine,
  // forward routine and method headers share (BNF.md sec 3). False = reported;
  // a missing ';' is inserted when AFollow can follow (PLAN-RECOVERY)
  LToken := DoCurrent();
  if LToken.Kind <> tkIdentifier then
  begin
    DoError(LToken, PC_ERR_PAR_001, RSParExpected, [RSParShapeName, DoTokenText(LToken)]);
    Exit(False);
  end;
  ARoutine.DeclName := LToken.Spelling;
  ARoutine.NameRange := LToken.Range;
  DoAdvance();
  if DoCheck(tkLParen) then
  begin
    if not DoParseParamList(ARoutine.Params, LVariadic, LVariadicRange) then
      Exit(False);
    ARoutine.IsVariadic := LVariadic;
    ARoutine.VariadicRange := LVariadicRange;
  end;
  if DoMatch(tkColon) then
  begin
    ARoutine.ReturnType := DoParseTypeExpr();
    if DoTypeFailed(ARoutine.ReturnType) then
      Exit(False);
  end;
  Result := DoExpectTerminator(AFollow) <> toMissing;
end;

function TPCParser.DoParseParamList(const AParams: TList<TPCParam>;
  out AIsVariadic: Boolean; out AVariadicRange: TSourceRange): Boolean;
var
  LParam: TPCParam;
begin
  // param list = "(" [ params ] ")"; params = "..." | param { ";" param }
  // [ ";" "..." ] (BNF.md sec 3). Shared by routines, forwards, methods and
  // routine types (T12); a trailing '...' sets AIsVariadic and AVariadicRange
  // (its token: SEM reports a rule about it there), no param node.
  // Current '('. False = reported, skipped past the list's ')' when found
  AIsVariadic := False;
  AVariadicRange := Default(TSourceRange);
  DoAdvance();
  if DoMatch(tkRParen) then
    Exit(True);
  if DoCheck(tkDotDotDot) then
  begin
    AVariadicRange := DoCurrent().Range;
    DoAdvance();
    AIsVariadic := True;
  end
  else
  begin
    while not DoStopped() do
    begin
      LParam := DoParseParam();
      if (LParam = nil) or LParam.IsRecovered then
      begin
        // A marked param is kept: its name still resolves in the body
        if LParam <> nil then
          AParams.Add(LParam);
        DoSkipPastParen([tkRParen, tkKwBegin, tkKwEnd, tkKwRoutine]);
        Exit(False);
      end;
      AParams.Add(LParam);
      if not DoMatch(tkSemicolon) then
        Break;
      if DoCheck(tkDotDotDot) then
      begin
        AVariadicRange := DoCurrent().Range;
        DoAdvance();
        AIsVariadic := True;
        Break;
      end;
    end;
  end;
  if not DoExpect(tkRParen, DoSpelled(')')) then
  begin
    DoSkipPastParen([tkRParen, tkKwBegin, tkKwEnd, tkKwRoutine]);
    Exit(False);
  end;
  Result := True;
end;

function TPCParser.DoParseParam(): TPCParam;
var
  LRange: TSourceRange;
  LParam: TPCParam;
begin
  // param = [ "var" | "const" ] identifier ":" type expr (BNF.md sec 3: one
  // identifier per param). nil = no name (nothing to keep); a param whose
  // name parsed is returned, marked when its ':' or type failed
  Result := nil;
  LRange := DoStartRange();
  LParam := FAst.NewNode<TPCParam>();
  if DoMatch(tkKwVar) then
    LParam.ParamMode := pmVar
  else if DoMatch(tkKwConst) then
    LParam.ParamMode := pmConst;
  if not DoCheck(tkIdentifier) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_001, RSParExpected, [RSParShapeParam, DoTokenText(DoCurrent())]);
    Exit;
  end;
  LParam.ParamName := DoCurrent().Spelling;
  LParam.NameRange := DoCurrent().Range;
  DoAdvance();
  if DoExpect(tkColon, DoSpelled(':')) then
    LParam.TypeExpr := DoParseTypeExpr();
  LParam.IsRecovered := DoTypeFailed(LParam.TypeExpr);
  DoFinishRange(LRange);
  LParam.Range := LRange;
  Result := LParam;
end;

function TPCParser.DoParseExternalClause(var AExternal: TPCExternal;
  const AFollow: TPCFollowContext): Boolean;
var
  LToken: TPCToken;
  LValue: string;
begin
  // external clause = "external" [ cstring | identifier ] ";" (BNF.md sec 3).
  // LibText = the decoded cstring value (the one cstring check, B3) or the
  // identifier's spelling (a const string SEM resolves, X5); LibKind says which
  // (sem\decls.md F-D1). A cstring is a library name (PR0055 otherwise, the
  // clause kept). False = reported, skipped (DoSkipItem)
  DoAdvance();
  AExternal.IsExternal := True;
  AExternal.LibKind := elNone;
  LToken := DoCurrent();
  if LToken.Kind = tkStringLiteral then
  begin
    if not DoIsPlainString(LToken) then
    begin
      DoError(LToken, PC_ERR_PAR_009, RSParBadString, [RSParNotPlainString]);
      DoSkipItem();
      Exit(False);
    end;
    if not DoDecodeCString(LToken, True, LValue) then
    begin
      DoSkipItem();
      Exit(False);
    end;
    AExternal.LibKind := elCString;
    AExternal.LibText := LValue;
    AExternal.LibRange := LToken.Range;
    DoCheckLibName(LToken, LValue, 'external');
    DoAdvance();
  end
  else if LToken.Kind = tkIdentifier then
  begin
    AExternal.LibKind := elIdentifier;
    AExternal.LibText := LToken.Spelling;
    AExternal.LibRange := LToken.Range;
    DoAdvance();
  end;
  if DoExpectTerminator(AFollow) = toMissing then
  begin
    DoSkipItem();
    Exit(False);
  end;
  Result := True;
end;

function TPCParser.DoParseTypeExpr(): TPCTypeExpr;
begin
  // type expr (BNF.md sec 4) inside the nesting guard: 'ptr to ptr to ...'
  // and element types recurse through here (F4). nil = reported
  if not DoEnterNested() then
    Exit(nil);
  try
    Result := DoParseTypeForm();
  finally
    DoLeaveNested();
  end;
end;

function TPCParser.DoParseTypeForm(): TPCTypeExpr;
var
  LToken: TPCToken;
  LNext: TPCToken;
  LOffset: Integer;
  LI: Integer;
  LName: string;
  LDef: TPCTypeExpr;
  LOwner: TPCOwnerKind;
begin
  // type expr = builtin | qualified | pointer | array | routine | cpp type (BNF.md
  // sec 4), classified on the head token (types.md "Head classification"). A
  // routine type is a type expr, written wherever a type goes (PLAN-RECORDS M2).
  // nil = reported
  LToken := DoCurrent();
  if LToken.Kind = tkKwPtr then
    Exit(DoParsePointerType());
  if LToken.Kind = tkKwArray then
    Exit(DoParseArrayType());
  if LToken.Kind = tkKwRoutine then
    Exit(DoParseRoutineType());
  if LToken.Kind = tkKwSet then
  begin
    // 'set of' is a type definition: parsed and kept, marked (PLAN-RECOVERY).
    // A bare set names no range and no element type (BNF.md sec 4): reported
    if DoPeek(1).Kind = tkKwOf then
    begin
      DoError(LToken, PC_ERR_PAR_026, RSParDeclareAsType, ['set of']);
      LDef := DoParseSetType();
      if LDef <> nil then
        LDef.IsRecovered := True;
      Exit(LDef);
    end;
    DoError(LToken, PC_ERR_PAR_053, RSParBareSet, []);
    DoAdvance();
    Exit(nil);
  end;
  if (LToken.Kind = tkKwBool) or (LToken.Kind = tkKwChar) then
  begin
    // One token, one meaning (T4): alone the builtin, in a C++ run a fundamental
    if DoIsCppSuffix(DoPeek(1).Kind) or DoIsCppFundamental(DoPeek(1).Kind) then
      Exit(DoParseCppType());
    Exit(DoNewBuiltin());
  end;
  if TPCVocabulary.IsBuiltinTypeWord(LToken.Kind) then
  begin
    // T5: a PaskalCPP builtin type word (a primitive or varargs) takes no C++
    // suffix (the hint names the form: 'ptr to varargs' is valid BNF)
    if DoIsCppSuffix(DoPeek(1).Kind) then
    begin
      DoReportPrimitiveSuffix(LToken, DoPeek(1));
      Exit(nil);
    end;
    Exit(DoNewBuiltin());
  end;
  if DoIsOneOf(LToken.Kind, [tkKwConst, tkKwVolatile, tkColonColon, tkKwStruct, tkKwClass,
    tkKwUnion, tkKwEnum, tkKwDecltype]) or DoIsCppFundamental(LToken.Kind) then
    Exit(DoParseCppType());
  // PLAN-OBJECT O6: `own T` / `ref T` / `weak T` (a context word before a type name)
  if DoIsOwnerTypeAt(0, LOwner) then
    Exit(DoParseOwnerType(LOwner));
  if LToken.Kind = tkIdentifier then
  begin
    // Dotted parts, then T3: no C++ continuation -> a qualified type; one part
    // and a continuation -> a cpp type; several parts and one -> PR0028
    LOffset := 1;
    while (DoPeek(LOffset).Kind = tkDot) and (DoPeek(LOffset + 1).Kind = tkIdentifier) do
      Inc(LOffset, 2);
    LNext := DoPeek(LOffset);
    if not DoIsCppContinuation(LNext.Kind) then
      Exit(DoParseQualifiedType());
    if LOffset = 1 then
      Exit(DoParseCppType());
    LName := LToken.Spelling;
    LI := 2;
    while LI < LOffset do
    begin
      LName := LName + '.' + DoPeek(LI).Spelling;
      Inc(LI, 2);
    end;
    if LNext.Kind = tkStar then
      DoError(LNext, PC_ERR_PAR_028, RSParQualifiedPtr, [LName, LName])
    else
      DoError(LNext, PC_ERR_PAR_028, RSParQualifiedSuffix, [LName, DoTokenText(LNext)]);
    Exit(nil);
  end;
  if DoIsOneOf(LToken.Kind, [tkKwRecord, tkKwObject, tkKwOverlay, tkKwChoices]) then
  begin
    // A type definition in a type expr position: reported, parsed and kept,
    // marked, so its members still resolve and never cascade
    DoError(LToken, PC_ERR_PAR_026, RSParDeclareAsType, [LToken.Spelling]);
    LDef := DoParseTypeDef();
    if LDef <> nil then
      LDef.IsRecovered := True;
    Exit(LDef);
  end;
  DoError(LToken, PC_ERR_PAR_001, RSParExpected, [RSParShapeType, DoTokenText(LToken)]);
  Result := nil;
end;

function TPCParser.DoParseTypeDef(): TPCTypeExpr;
var
  LKind: TPCTokenKind;
  LFinalRange: TSourceRange;
begin
  // type def (BNF.md sec 4): the definitions only a type block holds, else an
  // alias = type expr (T1; a routine type is one, PLAN-RECORDS M2).
  // PLAN-OBJECT D7: `final object` is an object no type may extend ('final'
  // a context word: only before 'object')
  if DoIsWord(cwFinal) and (DoPeek(1).Kind = tkKwObject) then
  begin
    LFinalRange := DoCurrent().Range;
    DoAdvance();
    Result := DoParseRecordType(True);
    if Result is TPCRecordType then
    begin
      TPCRecordType(Result).IsFinal := True;
      TPCRecordType(Result).FinalRange := LFinalRange;
      TPCRecordType(Result).Range.StartLine := LFinalRange.StartLine;
      TPCRecordType(Result).Range.StartColumn := LFinalRange.StartColumn;
      TPCRecordType(Result).Range.StartByteOffset := LFinalRange.StartByteOffset;
    end;
    Exit;
  end;
  // PLAN-OBJECT O7: 'interface' (a context word) starts an interface only
  // before its parent '(', its 'end' or what starts a member (a method or its
  // words, and the members an interface refuses: a field, 'hidden', an init,
  // a copy, a done or an embed: reported inside it, PR0034); `TA = interface;`
  // stays an alias of a C/C++ type named so
  if DoIsWord(cwInterface) and (DoIsOneOf(DoPeek(1).Kind, [tkLParen, tkKwEnd, tkKwMethod]) or
    (DoDispatchRun(1) >= 0) or ((DoPeek(1).Kind = tkIdentifier) and (DoPeek(2).Kind = tkColon)) or
    DoIsWordAt(cwHidden, 1) or (DoLifecycleRun(1) >= 0) or DoIsEmbedAt(1) or (DoPropertyRun(1) >= 0)) then
    Exit(DoParseInterfaceType());
  LKind := DoCurrent().Kind;
  if LKind = tkKwRecord then
    Result := DoParseRecordType(False)
  else if LKind = tkKwObject then
    Result := DoParseRecordType(True)
  else if LKind = tkKwOverlay then
    Result := DoParseOverlayType()
  else if LKind = tkKwChoices then
    Result := DoParseChoicesType()
  else if LKind = tkKwSet then
    Result := DoParseSetType()
  else
    Result := DoParseTypeExpr();
end;

class function TPCParser.DoTypeFailed(const AType: TPCTypeExpr): Boolean;
begin
  // A type that reported: nothing (nil) or a definition kept marked
  // (PLAN-RECOVERY)
  Result := (AType = nil) or AType.IsRecovered;
end;

function TPCParser.DoRecoverType(const AType: TPCTypeExpr;
  var ARange: TSourceRange): TPCTypeExpr;
begin
  // A type definition the parser reported inside: kept, marked, with every
  // member / value / param that parsed (PLAN-RECOVERY)
  DoFinishRange(ARange);
  AType.Range := ARange;
  AType.IsRecovered := True;
  Result := AType;
end;

procedure TPCParser.DoRecoverMember(const AItem: TPCMemberItem; var ARange: TSourceRange);
begin
  // A member the parser reported inside: the rest of it is skipped
  // (DoSkipMember) and the member kept, marked, with its name
  DoSkipMember();
  DoFinishRange(ARange);
  AItem.Range := ARange;
  AItem.IsRecovered := True;
end;

function TPCParser.DoNewBuiltin(): TPCTypeExpr;
var
  LType: TPCBuiltinType;
begin
  // The current builtin type word (TPCVocabulary.IsBuiltinTypeWord: a primitive
  // or varargs) as a TPCBuiltinType (never ptr or set: T2)
  LType := FAst.NewNode<TPCBuiltinType>();
  LType.BuiltinToken := DoCurrent().Kind;
  LType.Range := DoCurrent().Range;
  DoAdvance();
  Result := LType;
end;

function TPCParser.DoParseQualifiedType(): TPCNamedType;
var
  LRange: TSourceRange;
  LParts: TArray<string>;
begin
  // qualified type = identifier { "." identifier } (BNF.md sec 4): one
  // TPCNamedType, PaskalCPP or opaque (SEM decides). Current: the identifier
  LRange := DoStartRange();
  LParts := [DoCurrent().Spelling];
  DoAdvance();
  while DoCheck(tkDot) and (DoPeek(1).Kind = tkIdentifier) do
  begin
    DoAdvance();
    LParts := LParts + [DoCurrent().Spelling];
    DoAdvance();
  end;
  Result := FAst.NewNode<TPCNamedType>();
  Result.Parts := LParts;
  DoFinishRange(LRange);
  Result.Range := LRange;
end;

procedure TPCParser.DoReportPrimitiveSuffix(const AType: TPCToken; const ASuffix: TPCToken);
begin
  // PR0027 at the suffix, the hint naming the PaskalCPP form (T5)
  if ASuffix.Kind = tkStar then
    DoError(ASuffix, PC_ERR_PAR_027, RSParPrimitivePtr, [AType.Spelling, AType.Spelling])
  else if (ASuffix.Kind = tkAmp) or (ASuffix.Kind = tkAmpAmp) then
    DoError(ASuffix, PC_ERR_PAR_027, RSParPrimitiveRef, [AType.Spelling, ASuffix.Spelling])
  else
    DoError(ASuffix, PC_ERR_PAR_027, RSParPrimitiveCv, [AType.Spelling, ASuffix.Spelling]);
end;

function TPCParser.DoParseCppType(): TPCTypeExpr;
var
  LRange: TSourceRange;
  LType: TPCCppType;
  LToken: TPCToken;
  LLevel: TPCCvFlags;
  LCount: Integer;
begin
  // cpp type = [ cv ] cpp type name [ cv ] { "*" [ cv ] } [ "&" | "&&" ]
  // (BNF.md sec 4), in C++ order. The name: an elaborated key and a cpp
  // qualified name (T14), a decltype head (T15), a fundamentals run, or a cpp
  // qualified name. nil = reported
  Result := nil;
  LRange := DoStartRange();
  LType := FAst.NewNode<TPCCppType>();
  if not DoParseCv(LType.LeadCv) then
    Exit;
  LToken := DoCurrent();
  if DoIsOneOf(LToken.Kind, [tkKwStruct, tkKwClass, tkKwUnion, tkKwEnum]) then
  begin
    LType.HasElaborated := True;
    LType.ElaboratedKey := LToken.Kind;
    DoAdvance();
    if not (DoCheck(tkIdentifier) or DoCheck(tkColonColon)) then
    begin
      DoError(DoCurrent(), PC_ERR_PAR_036, RSParElaboratedName,
        [LToken.Spelling, DoTokenText(DoCurrent())]);
      Exit;
    end;
    if not DoParseNameParts(LType) then
      Exit;
  end
  else if LToken.Kind = tkKwDecltype then
  begin
    if not DoParseDecltypeHead(LType) then
      Exit;
  end
  else if DoIsCppFundamental(LToken.Kind) then
  begin
    while DoIsCppFundamental(DoCurrent().Kind) do
    begin
      LCount := Length(LType.Fundamentals);
      SetLength(LType.Fundamentals, LCount + 1);
      LType.Fundamentals[LCount] := DoCurrent().Kind;
      DoAdvance();
    end;
  end
  else if (LToken.Kind = tkIdentifier) or (LToken.Kind = tkColonColon) then
  begin
    if not DoParseNameParts(LType) then
      Exit;
  end
  else if TPCVocabulary.IsBuiltinTypeWord(LToken.Kind) then
  begin
    // T5 after a lead cv (bool / char are fundamentals, taken above; varargs too)
    DoError(LToken, PC_ERR_PAR_027, RSParPrimitiveCv, [LToken.Spelling, DoCvWord(LType.LeadCv)]);
    Exit;
  end
  else
  begin
    DoError(LToken, PC_ERR_PAR_001, RSParExpected, [RSParShapeType, DoTokenText(LToken)]);
    Exit;
  end;
  if not DoParseCv(LType.TrailCv) then
    Exit;
  while DoCheck(tkStar) do
  begin
    DoAdvance();
    LLevel := [];
    if not DoParseCv(LLevel) then
      Exit;
    LCount := Length(LType.PointerLevels);
    SetLength(LType.PointerLevels, LCount + 1);
    LType.PointerLevels[LCount] := LLevel;
  end;
  if DoMatch(tkAmp) then
    LType.RefKind := rfLValue
  else if DoMatch(tkAmpAmp) then
    LType.RefKind := rfRValue;
  // At most one reference, last (BNF.md sec 4): nothing of the type follows it
  if (LType.RefKind <> rfNone) and DoIsCppSuffix(DoCurrent().Kind) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_030, RSParRefNotLast, [DoCurrent().Spelling]);
    Exit;
  end;
  DoFinishRange(LRange);
  LType.Range := LRange;
  Result := LType;
end;

function TPCParser.DoParseCv(var AFlags: TPCCvFlags): Boolean;
var
  LToken: TPCToken;
  LQualifier: TPCCvQualifier;
begin
  // cv qualifier = ( const | volatile ) [ const | volatile ] (BNF.md sec 4):
  // each at most once in one slot, a repeat is PR0029. False = reported
  while DoCheck(tkKwConst) or DoCheck(tkKwVolatile) do
  begin
    LToken := DoCurrent();
    if LToken.Kind = tkKwConst then
      LQualifier := cqConst
    else
      LQualifier := cqVolatile;
    if LQualifier in AFlags then
    begin
      DoError(LToken, PC_ERR_PAR_029, RSParRepeatedCv, [LToken.Spelling]);
      Exit(False);
    end;
    Include(AFlags, LQualifier);
    DoAdvance();
  end;
  Result := True;
end;

function TPCParser.DoParseNameParts(const AType: TPCCppType): Boolean;
var
  LPart: TPCNamePart;
  LAfterScope: Boolean;
begin
  // cpp qualified name, template args per part (BNF.md sec 4): [ "::" ] part
  // { "::" part }. False = reported
  LAfterScope := DoMatch(tkColonColon);
  AType.HasLeadingScope := LAfterScope;
  while True do
  begin
    LPart := DoParseNamePart(LAfterScope, tmType);
    if LPart = nil then
      Exit(False);
    AType.NameParts.Add(LPart);
    if not DoCheck(tkColonColon) then
      Break;
    DoAdvance();
    LAfterScope := True;
  end;
  Result := True;
end;

function TPCParser.DoParseNamePart(const AAfterScope: Boolean;
  const AMode: TPCTemplateMode): TPCNamePart;
var
  LRange: TSourceRange;
  LToken: TPCToken;
  LPart: TPCNamePart;
  LAnyWord: Boolean;
begin
  // One part: an identifier; after '::' and as a member name any keyword too
  // (BNF.md sec 6 / sec 10: 'std::ios::end', '::set', LS.end), PartText =
  // its spelling. '<' after the part: tmType always parses template args (T6,
  // False = reported, nil); tmMember, and tmQualified after a '::', try them
  // (an attempt: False = restored, '<' is less-than, the part stands without
  // args). nil = reported
  Result := nil;
  LToken := DoCurrent();
  LAnyWord := AAfterScope or (AMode = tmMember);
  if not ((LToken.Kind = tkIdentifier) or (LAnyWord and
    (LToken.Category in [tcKeyword, tcCppKeyword, tcPrimitive]))) then
  begin
    DoError(LToken, PC_ERR_PAR_001, RSParExpected, [RSParShapeName, DoTokenText(LToken)]);
    Exit;
  end;
  LRange := DoStartRange();
  LPart := FAst.NewNode<TPCNamePart>();
  LPart.PartText := LToken.Spelling;
  DoAdvance();
  if DoCheck(tkLess) or DoCheck(tkLessGreater) then
  begin
    if AMode = tmType then
    begin
      if not DoParseTemplateArgs(LPart, tmType) then
        Exit;
    end
    else if (AMode = tmMember) or AAfterScope then
      DoParseTemplateArgs(LPart, AMode);
  end;
  DoFinishRange(LRange);
  LPart.Range := LRange;
  Result := LPart;
end;

function TPCParser.DoParseDecltypeHead(const AType: TPCCppType): Boolean;
var
  LFirst: Integer;
  LLast: Integer;
  LOpen: TPCToken;
begin
  // "decltype" "(" { character } ")" (BNF.md sec 4, T15): the keyword through
  // the matching ')' is verbatim (vkOpaqueGroup, in place); PaskalCPP has
  // nothing to say inside it. False = PR0037 (no '('), PR0063 at the '(' it
  // never closes (F56)
  LFirst := DoCurrentIndex();
  DoAdvance();
  if not DoCheck(tkLParen) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_037, RSParDecltypeGroup, [DoTokenText(DoCurrent())]);
    Exit(False);
  end;
  LOpen := DoCurrent();
  if not DoScanBalanced(LLast) then
  begin
    DoReportNeverClosed(LOpen);
    Exit(False);
  end;
  AType.HasDecltype := True;
  AType.Decltype.VerbatimKind := vkOpaqueGroup;
  AType.Decltype.EmitTarget := etInPlace;
  DoFillVerbatim(LFirst, LLast, AType.Decltype);
  Result := True;
end;

function TPCParser.DoParseTemplateArgs(const APart: TPCNamePart;
  const AMode: TPCTemplateMode): Boolean;
var
  LArg: TPCTemplateArg;
begin
  // template args = "<" [ template arg { "," template arg } ] ">" (BNF.md sec 4).
  // Current '<' or '<>'. tmType (a type position): always parsed, errors
  // reported (T6); '<>' and the '>' family are split (SplitCurrent):
  // 'std::less<>', 'std::vector<std::vector<int>>', 'X<int>= ...'.
  // tmQualified / tmMember are attempts (DoTryTemplateArgs). False = reported
  if AMode <> tmType then
    Exit(DoTryTemplateArgs(APart, AMode));
  APart.HasTemplateArgs := True;
  if DoCheck(tkLessGreater) then
  begin
    FCursor.SplitCurrent();
    DoAdvance();
    DoAdvance();
    Exit(True);
  end;
  DoAdvance();
  if DoSplitIfGreaterFamily() then
  begin
    // '< >' written apart: the empty list as well
    DoAdvance();
    Exit(True);
  end;
  while True do
  begin
    LArg := DoParseTemplateArg(AMode);
    if LArg = nil then
      Exit(False);
    APart.TemplateArgs.Add(LArg);
    if not DoMatch(tkComma) then
      Break;
  end;
  if not DoSplitIfGreaterFamily() then
  begin
    DoReportArgsOpen(AMode);
    Exit(False);
  end;
  DoAdvance();
  Result := True;
end;

function TPCParser.DoParseTemplateArg(const AMode: TPCTemplateMode): TPCTemplateArg;
var
  LRange: TSourceRange;
  LAttempt: TPCAttempt;
  LType: TPCTypeExpr;
  LExpr: TPCExpr;
begin
  // template arg = type expr | constant expression | cpp type id (BNF.md
  // sec 4), three tries in that order (T16), the first two attempts: accepted
  // when the node is set, the next token is ',' or the '>' family and nothing
  // was reported. A type only when DoIsUnmistakableType (T7: a plain name is
  // an expression, as in size(T)); else the expression; else the verbatim
  // cpp type id; tmMember: any type node, nothing else (F2). nil = reported
  // (tmType) or a failed try (attempt modes)
  LRange := DoStartRange();
  LAttempt := DoSaveAttempt();
  LType := DoParseTypeExpr();
  if (not DoTypeFailed(LType)) and ((AMode = tmMember) or DoIsUnmistakableType(LType)) and
    DoIsTemplateArgEnd() and DoAttemptClean(LAttempt) then
  begin
    Result := FAst.NewNode<TPCTemplateArg>();
    Result.TypeArg := LType;
    DoFinishRange(LRange);
    Result.Range := LRange;
    Exit;
  end;
  DoRestoreAttempt(LAttempt);
  // tmMember: every argument must parse as a type (BNF.md sec 6, F2): no
  // expression try, no verbatim walk (a walk would take 'LB and LR.C')
  if AMode = tmMember then
    Exit(nil);

  LExpr := DoParseExpression(ecTemplateArg);
  if (not DoFailed(LExpr)) and DoIsTemplateArgEnd() and DoAttemptClean(LAttempt) then
  begin
    Result := FAst.NewNode<TPCTemplateArg>();
    Result.ExprArg := LExpr;
    DoFinishRange(LRange);
    Result.Range := LRange;
    Exit;
  end;
  DoRestoreAttempt(LAttempt);

  Result := DoParseCppTypeId(AMode);
end;

function TPCParser.DoParseCppTypeId(const AMode: TPCTemplateMode): TPCTemplateArg;
var
  LFirst: Integer;
  LLast: Integer;
  LClose: Integer;
  LAngle: Integer;
  LToken: TPCToken;
  LLastToken: TPCToken;
begin
  // cpp type id (BNF.md sec 4, T16): any other C++ text up to the argument's
  // depth-0 ',' or '>' - C++'s own rule: ( ) [ ] { } groups are skipped whole
  // (angles inside them never end it); at depth 0 a '<' opens an angle level
  // and a '>' closes one; '>>' '>=' '>>=' '<>' are split and taken one piece
  // at a time. ';', EOF or a closer at depth 0 first: the list is not
  // closed, PR0031 in tmType (a silent failed try in an attempt mode, A3).
  // Copied through DoFillVerbatimUpTo: it can end on a split piece (T17)
  Result := nil;
  LFirst := DoCurrentIndex();
  LLast := -1;
  LAngle := 0;
  while True do
  begin
    LToken := DoCurrent();
    if DoIsOneOf(LToken.Kind, [tkLParen, tkLBracket, tkLBrace]) then
    begin
      if not DoScanBalanced(LClose) then
      begin
        // F56: the group inside the arguments never closes: reported at its
        // opener, in a type position only (an attempt mode stays silent, as
        // DoReportArgsOpen)
        if AMode = tmType then
          DoReportNeverClosed(LToken);
        Exit;
      end;
      LLast := LClose;
      LLastToken := FCursor.TokenAt(LClose);
      Continue;
    end;
    if DoIsOneOf(LToken.Kind, [tkRParen, tkRBracket, tkRBrace, tkSemicolon, tkEOF]) then
    begin
      DoReportArgsOpen(AMode);
      Exit;
    end;
    if (LAngle = 0) and DoIsOneOf(LToken.Kind, [tkComma, tkGreater, tkGreaterGreater,
      tkGreaterEqual, tkGreaterGreaterEqual]) then
      Break;
    if DoIsOneOf(LToken.Kind, [tkLessGreater, tkGreaterGreater, tkGreaterEqual,
      tkGreaterGreaterEqual]) then
    begin
      FCursor.SplitCurrent();
      LToken := DoCurrent();
    end;
    if LToken.Kind = tkLess then
      Inc(LAngle)
    else if LToken.Kind = tkGreater then
      Dec(LAngle);
    LLast := DoCurrentIndex();
    LLastToken := LToken;
    DoAdvance();
  end;
  if LLast < 0 then
  begin
    // An empty argument: 'X<, int>'
    if AMode = tmType then
      DoError(DoCurrent(), PC_ERR_PAR_001, RSParExpected,
        [RSParShapeTemplateArg, DoTokenText(DoCurrent())]);
    Exit;
  end;
  Result := FAst.NewNode<TPCTemplateArg>();
  Result.HasVerbatim := True;
  Result.Verbatim.VerbatimKind := vkCppTypeId;
  Result.Verbatim.EmitTarget := etInPlace;
  DoFillVerbatimUpTo(LFirst, LLast, LLastToken, Result.Verbatim);
  Result.Range := Result.Verbatim.Range;
end;

procedure TPCParser.DoReportArgsOpen(const AMode: TPCTemplateMode);
begin
  // PR0031 in a type position only; in an attempt mode a failed try is silent
  if AMode = tmType then
    DoError(DoCurrent(), PC_ERR_PAR_031, RSParTemplateArgsOpen, [DoTokenText(DoCurrent())]);
end;

function TPCParser.DoSplitIfGreaterFamily(): Boolean;
begin
  // '>>' '>=' '>>=' present their first '>' as its own token (SplitCurrent);
  // True when the current token is then '>'. Inside an attempt a restore
  // undoes the split
  if DoIsOneOf(DoCurrent().Kind, [tkGreaterGreater, tkGreaterEqual, tkGreaterGreaterEqual]) then
    FCursor.SplitCurrent();
  Result := DoCheck(tkGreater);
end;

function TPCParser.DoIsTemplateArgEnd(): Boolean;
begin
  // The follow test of one argument: ',' or the '>' family (split)
  Result := DoCheck(tkComma) or DoSplitIfGreaterFamily();
end;

class function TPCParser.DoIsUnmistakableType(const AType: TPCTypeExpr): Boolean;
var
  LCpp: TPCCppType;
  LPart: TPCNamePart;
begin
  // T8: a type node no expression can be, decided on the NODE (no token
  // re-scan): every PaskalCPP type form but a name, and a cpp type with
  // anything beyond a plain '::' name. Shared by template args (here), C-style
  // casts and size(T) (PARSER-EXPR-C): a new type form becomes unmistakable by
  // entering this one function (V5)
  if AType is TPCNamedType then
    Exit(False);
  if not (AType is TPCCppType) then
    Exit(True);
  LCpp := TPCCppType(AType);
  if (Length(LCpp.Fundamentals) > 0) or LCpp.HasElaborated or LCpp.HasDecltype or
    (LCpp.LeadCv <> []) or (LCpp.TrailCv <> []) or (Length(LCpp.PointerLevels) > 0) or
    (LCpp.RefKind <> rfNone) then
    Exit(True);
  for LPart in LCpp.NameParts do
  begin
    if LPart.HasTemplateArgs then
      Exit(True);
  end;
  Result := False;
end;

class function TPCParser.DoIsCppFundamental(const AKind: TPCTokenKind): Boolean;
begin
  // cpp fundamental (BNF.md sec 4); bool and char are shared tokens
  Result := DoIsOneOf(AKind, [tkKwVoid, tkKwBool, tkKwChar, tkKwShort, tkKwInt, tkKwLong,
    tkKwFloat, tkKwDouble, tkKwSigned, tkKwUnsigned, tkKwAuto, tkKwWchar_t, tkKwChar8_t,
    tkKwChar16_t, tkKwChar32_t]);
end;

class function TPCParser.DoIsCppSuffix(const AKind: TPCTokenKind): Boolean;
begin
  // What may follow a cpp type name: cv, '*', '&', '&&'
  Result := DoIsOneOf(AKind, [tkStar, tkAmp, tkAmpAmp, tkKwConst, tkKwVolatile]);
end;

class function TPCParser.DoIsCppContinuation(const AKind: TPCTokenKind): Boolean;
begin
  // After an identifier in a type position: what makes it a cpp type (T3)
  Result := DoIsCppSuffix(AKind) or DoIsOneOf(AKind, [tkColonColon, tkLess, tkLessGreater]);
end;

class function TPCParser.DoCvWord(const AFlags: TPCCvFlags): string;
begin
  if cqConst in AFlags then
    Result := 'const'
  else
    Result := 'volatile';
end;

class function TPCParser.DoAggText(const AKind: TPCAggKind): string;
begin
  if AKind = agRecord then
    Result := RSParAggRecord
  else if AKind = agObject then
    Result := RSParAggObject
  else if AKind = agOverlay then
    Result := RSParAggOverlay
  else if AKind = agAnonRecord then
    Result := RSParAggAnonRecord
  else if AKind = agInterface then
    Result := RSParAggInterface
  else
    Result := RSParAggAnonOverlay;
end;

function TPCParser.DoParsePointerType(): TPCTypeExpr;
var
  LRange: TSourceRange;
  LType: TPCPointerType;
begin
  // pointer type = "ptr" [ "to" [ "const" ] type expr ] (BNF.md sec 4); bare
  // ptr = TargetType nil (T2); 'const' right after 'to' is the const target
  Result := nil;
  LRange := DoStartRange();
  LType := FAst.NewNode<TPCPointerType>();
  DoAdvance();
  if DoMatch(tkKwTo) then
  begin
    LType.IsConstTarget := DoMatch(tkKwConst);
    LType.TargetType := DoParseTypeExpr();
    if LType.TargetType = nil then
      Exit;
  end;
  DoFinishRange(LRange);
  LType.Range := LRange;
  Result := LType;
end;

function TPCParser.DoIsOwnerTypeAt(const AOffset: Integer; out AKind: TPCOwnerKind): Boolean;
var
  LKind: TPCOwnerKind;
begin
  // PLAN-OBJECT O6 (H1): own / ref / weak are a type's head only when a type
  // name or a builtin type word follows (`own int32` is SM0358's, never a
  // syntax error); anywhere else they are plain identifiers (a variable
  // named ref, a C routine own())
  Result := False;
  AKind := okOwn;
  if (DoPeek(AOffset + 1).Kind <> tkIdentifier) and not TPCVocabulary.IsBuiltinTypeWord(DoPeek(AOffset + 1).Kind) then
    Exit;
  for LKind := Low(TPCOwnerKind) to High(TPCOwnerKind) do
  begin
    if DoIsWordAt(PC_OWNER_WORDS[LKind], AOffset) then
    begin
      AKind := LKind;
      Exit(True);
    end;
  end;
end;

function TPCParser.DoParseOwnerType(const AKind: TPCOwnerKind): TPCTypeExpr;
var
  LRange: TSourceRange;
  LType: TPCOwnerType;
begin
  // owner type = ( "own" | "ref" | "weak" ) type expr (BNF.md sec 4, PLAN-OBJECT
  // O6); SEM judges that the type held is an object
  Result := nil;
  LRange := DoStartRange();
  LType := FAst.NewNode<TPCOwnerType>();
  LType.OwnerKind := AKind;
  DoAdvance();
  LType.TargetType := DoParseTypeExpr();
  if LType.TargetType = nil then
    Exit;
  DoFinishRange(LRange);
  LType.Range := LRange;
  Result := LType;
end;

function TPCParser.DoParseArrayType(): TPCTypeExpr;
var
  LRange: TSourceRange;
  LType: TPCArrayType;
  LFailed: Boolean;
begin
  // array type = "array" [ "[" [ expression ".." expression ] "]" ] "of" type expr
  // (BNF.md sec 4); no brackets or '[]' = dynamic, bounds nil. A failed bound
  // reports once and the rest is still parsed (nothing cascades); the type is
  // kept, marked (PLAN-RECOVERY)
  LRange := DoStartRange();
  LType := FAst.NewNode<TPCArrayType>();
  LFailed := False;
  DoAdvance();
  if DoMatch(tkLBracket) then
  begin
    if DoCheck(tkRBracket) then
      LType.IsDynamic := True
    else if not DoParseRange(LType.LowExpr, LType.HighExpr, tkRBracket) then
      LFailed := True;
    if not DoCheck(tkRBracket) then
    begin
      if not LFailed then
        DoExpect(tkRBracket, DoSpelled(']'));
      Exit(DoRecoverType(LType, LRange));
    end;
    DoAdvance();
  end
  else
    LType.IsDynamic := True;
  if not DoExpect(tkKwOf, DoSpelled('of')) then
    Exit(DoRecoverType(LType, LRange));
  LType.ElementType := DoParseTypeExpr();
  if DoTypeFailed(LType.ElementType) or LFailed then
    Exit(DoRecoverType(LType, LRange));
  DoFinishRange(LRange);
  LType.Range := LRange;
  Result := LType;
end;

function TPCParser.DoParseSetType(): TPCTypeExpr;
var
  LRange: TSourceRange;
  LType: TPCSetType;
  LAttempt: TPCAttempt;
  LLow: TPCExpr;
begin
  // set type = "set" "of" ( expression ".." expression | type expr )
  // (BNF.md sec 4). The range form is an attempt: an expression followed by
  // '..' (T9); otherwise the element type. A bare set is PR0053 at 'set'
  Result := nil;
  if DoPeek(1).Kind <> tkKwOf then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_053, RSParBareSet, []);
    DoAdvance();
    Exit;
  end;
  LRange := DoStartRange();
  LType := FAst.NewNode<TPCSetType>();
  // Past 'set', then past 'of' (checked above)
  DoAdvance();
  DoAdvance();
  LAttempt := DoSaveAttempt();
  LLow := DoParseExpression(ecNormal);
  if (not DoFailed(LLow)) and DoCheck(tkDotDot) and DoAttemptClean(LAttempt) then
  begin
    LType.IsRangeForm := True;
    LType.LowExpr := LLow;
    DoAdvance();
    LType.HighExpr := DoParseExpression(ecNormal);
    if DoFailed(LType.HighExpr) then
      Exit(DoRecoverType(LType, LRange));
  end
  else
  begin
    DoRestoreAttempt(LAttempt);
    LType.ElementType := DoParseTypeExpr();
    if DoTypeFailed(LType.ElementType) then
      Exit(DoRecoverType(LType, LRange));
  end;
  DoFinishRange(LRange);
  LType.Range := LRange;
  Result := LType;
end;

function TPCParser.DoParseRoutineType(): TPCTypeExpr;
var
  LRange: TSourceRange;
  LType: TPCRoutineType;
  LVariadic: Boolean;
  LVariadicRange: TSourceRange;
begin
  // routine type = "routine" [ linkage ] param list [ ":" type expr ]
  // (BNF.md sec 4); the param list is required. A failure keeps the type,
  // marked, with the params that parsed (PLAN-RECOVERY)
  LRange := DoStartRange();
  LType := FAst.NewNode<TPCRoutineType>();
  DoAdvance();
  LType.Linkage := DoParseLinkage();
  if not DoCheck(tkLParen) then
  begin
    DoExpect(tkLParen, DoSpelled('('));
    Exit(DoRecoverType(LType, LRange));
  end;
  if not DoParseParamList(LType.Params, LVariadic, LVariadicRange) then
    Exit(DoRecoverType(LType, LRange));
  LType.IsVariadic := LVariadic;
  LType.VariadicRange := LVariadicRange;
  if DoMatch(tkColon) then
  begin
    LType.ReturnType := DoParseTypeExpr();
    if DoTypeFailed(LType.ReturnType) then
      Exit(DoRecoverType(LType, LRange));
  end;
  DoFinishRange(LRange);
  LType.Range := LRange;
  Result := LType;
end;

function TPCParser.DoParseRecordType(const AIsObject: Boolean): TPCTypeExpr;
var
  LRange: TSourceRange;
  LRec: TPCRecordType;
  LToken: TPCToken;
  LOrder: Integer;
  LStage: Integer;
  LStore: Boolean;
  LFailed: Boolean;
  LKind: TPCAggKind;
begin
  // record type = "record" [ "(" qualified type ")" ] [ "packed" ]
  //   [ "align" "(" expression ")" ] { field decl | anon overlay } "end";
  // object type = "object" [ "(" qualified type ")" ] { field decl | method decl }
  //   "end" (BNF.md sec 4). The prefixes stand in that order, each once
  // (PR0032); packed / align on an object are PR0033. Either is still parsed,
  // never stored, so nothing cascades. A missing 'end': one PR0001; the type
  // is kept, marked (PLAN-RECOVERY)
  LRange := DoStartRange();
  LRec := FAst.NewNode<TPCRecordType>();
  LRec.IsObject := AIsObject;
  DoAdvance();
  LStage := 0;
  LFailed := False;
  while DoIsOneOf(DoCurrent().Kind, [tkLParen, tkKwPacked, tkKwAlign]) and (not DoStopped()) do
  begin
    LToken := DoCurrent();
    if LToken.Kind = tkLParen then
      LOrder := 1
    else if LToken.Kind = tkKwPacked then
      LOrder := 2
    else
      LOrder := 3;
    LStore := True;
    if LOrder <= LStage then
    begin
      DoError(LToken, PC_ERR_PAR_032, RSParRecordPrefix, [LToken.Spelling]);
      LStore := False;
    end
    else if AIsObject and (LOrder > 1) then
    begin
      DoError(LToken, PC_ERR_PAR_033, RSParNotOnAggregate, [LToken.Spelling, RSParAggObject]);
      LStore := False;
    end;
    if LOrder > LStage then
      LStage := LOrder;
    if not DoParseRecordPrefix(LRec, LStore) then
      LFailed := True;
  end;
  // PLAN-OBJECT O7: `implements I1, I2` after the prefixes (an object's
  // word; on a record PR0033, parsed and dropped). `implements: T;` stays a
  // field named implements
  if DoIsWord(cwImplements) and (DoPeek(1).Kind = tkIdentifier) and (DoPeek(2).Kind <> tkColon) then
  begin
    if not AIsObject then
      DoError(DoCurrent(), PC_ERR_PAR_033, RSParNotOnAggregate, [DoCurrent().Spelling, RSParAggRecord]);
    if not DoParseImplements(LRec) then
      LFailed := True;
    if not AIsObject then
      LRec.Implements.Clear();
  end;
  if AIsObject then
    LKind := agObject
  else
    LKind := agRecord;
  DoParseMembers(LRec.Members, LKind);
  if (not DoExpectEnd()) or LFailed then
    Exit(DoRecoverType(LRec, LRange));
  DoFinishRange(LRange);
  LRec.Range := LRange;
  Result := LRec;
end;

function TPCParser.DoParseImplements(const ARec: TPCRecordType): Boolean;
begin
  // "implements" qualified type { "," qualified type } (PLAN-OBJECT O7, BNF
  // sec 4). Current: the word. False = a name missing after a ',' (PR0001,
  // reported); the names read so far are kept
  DoAdvance();
  Result := True;
  repeat
    if not DoCheck(tkIdentifier) then
    begin
      DoError(DoCurrent(), PC_ERR_PAR_001, RSParExpected, [RSParShapeType, DoTokenText(DoCurrent())]);
      Exit(False);
    end;
    ARec.Implements.Add(DoParseQualifiedType());
  until not DoMatch(tkComma);
end;

function TPCParser.DoParseInterfaceType(): TPCTypeExpr;
var
  LRange: TSourceRange;
  LRec: TPCRecordType;
  LFailed: Boolean;
begin
  // interface type = "interface" [ "(" qualified type ")" ] { method decl }
  // "end" (BNF.md sec 4, PLAN-OBJECT O7, user 2026-10-13: one parent
  // interface). A TPCRecordType with IsObject and IsInterface; its methods
  // are virtual and abstract by the grammar (DoParseMethodItem). A missing
  // 'end': one PR0001, the type kept, marked
  LRange := DoStartRange();
  LRec := FAst.NewNode<TPCRecordType>();
  LRec.IsObject := True;
  LRec.IsInterface := True;
  DoAdvance();
  LFailed := False;
  if DoCheck(tkLParen) then
    LFailed := not DoParseRecordPrefix(LRec, True);
  DoParseMembers(LRec.Members, agInterface);
  if (not DoExpectEnd()) or LFailed then
    Exit(DoRecoverType(LRec, LRange));
  DoFinishRange(LRange);
  LRec.Range := LRange;
  Result := LRec;
end;

function TPCParser.DoParseRecordPrefix(const ARec: TPCRecordType; const AStore: Boolean): Boolean;
var
  LParent: TPCNamedType;
  LAlign: TPCExpr;
begin
  // One record / object prefix at the current token: "(" qualified type ")"
  // (T18), "packed", or "align" "(" expression ")". AStore False: parsed and
  // dropped (the caller reported why). False = reported, skipped past its ')'
  if DoMatch(tkKwPacked) then
  begin
    if AStore then
      ARec.IsPacked := True;
    Exit(True);
  end;
  if DoMatch(tkLParen) then
  begin
    if not DoCheck(tkIdentifier) then
    begin
      DoError(DoCurrent(), PC_ERR_PAR_001, RSParExpected, [RSParShapeType, DoTokenText(DoCurrent())]);
      DoSkipPastParen([tkRParen, tkSemicolon]);
      Exit(False);
    end;
    LParent := DoParseQualifiedType();
    if not DoExpect(tkRParen, DoSpelled(')')) then
    begin
      DoSkipPastParen([tkRParen, tkSemicolon]);
      Exit(False);
    end;
    if AStore then
      ARec.ParentName := LParent;
    Exit(True);
  end;
  // align
  DoAdvance();
  if not DoExpect(tkLParen, DoSpelled('(')) then
    Exit(False);
  LAlign := DoParseConstExprIn([tkRParen, tkSemicolon]);
  if DoFailed(LAlign) then
  begin
    DoMatch(tkRParen);
    Exit(False);
  end;
  if not DoExpect(tkRParen, DoSpelled(')')) then
  begin
    DoSkipPastParen([tkRParen, tkSemicolon]);
    Exit(False);
  end;
  if AStore then
    ARec.AlignExpr := LAlign;
  Result := True;
end;

function TPCParser.DoParseOverlayType(): TPCTypeExpr;
var
  LRange: TSourceRange;
  LType: TPCOverlayType;
begin
  // overlay type = "overlay" { field decl | anon record } "end" (BNF.md sec 4);
  // 'packed' here is PR0033, consumed. A missing 'end' keeps the type, marked
  LRange := DoStartRange();
  LType := FAst.NewNode<TPCOverlayType>();
  DoAdvance();
  if DoCheck(tkKwPacked) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_033, RSParNotOnAggregate, [DoCurrent().Spelling, RSParAggOverlay]);
    DoAdvance();
  end;
  DoParseMembers(LType.Members, agOverlay);
  if not DoExpectEnd() then
    Exit(DoRecoverType(LType, LRange));
  DoFinishRange(LRange);
  LType.Range := LRange;
  Result := LType;
end;

procedure TPCParser.DoParseMembers(const AMembers: TList<TPCMemberItem>; const AKind: TPCAggKind);
begin
  // Members up to 'end' (not consumed), EOF, or a recovery stop: the caller's
  // 'end' check reports a missing end once. Every member call consumes a token
  while (not DoCheck(tkKwEnd)) and (not DoCheck(tkEOF)) and (not DoIsRecoveryStop()) and
    (not DoStopped()) do
    DoParseMember(AMembers, AKind);
end;

procedure TPCParser.DoParseMember(const AMembers: TList<TPCMemberItem>; const AKind: TPCAggKind);
var
  LToken: TPCToken;
  LItem: TPCMemberItem;
  LAllowed: Boolean;
  LMark: TPCSkipMark;
  LHidden: Boolean;
  LHiddenRange: TSourceRange;
  LLifecycleReported: Boolean;
begin
  // One member (BNF.md sec 4): identifier ':' -> field (every aggregate);
  // 'overlay' -> anon overlay (record, anon record); 'record' -> anon record
  // (overlay, anon overlay); 'method' -> method (object). A member the
  // aggregate does not take is PR0034, parsed and kept, marked (PLAN-RECOVERY)
  LMark := DoMarkSkip();
  // PLAN-OBJECT D10 / H1: 'hidden' is the word before a field (identifier
  // ':') or a method; `hidden: T;` is a field named hidden. An aggregate
  // other than an object takes no hidden member: PR0034 at the word, the
  // member parsed and kept, marked (DoSetHidden)
  LHidden := False;
  LLifecycleReported := False;
  if DoIsHiddenWord() then
  begin
    LHidden := True;
    LHiddenRange := DoCurrent().Range;
    // PLAN-OBJECT D3: an init / done is never hidden: PR0058 at the word
    if DoLifecycleRun(1) >= 0 then
    begin
      DoError(DoCurrent(), PC_ERR_PAR_058, RSParLifecycleWord, [DoCurrent().Spelling]);
      LLifecycleReported := True;
    end
    else if AKind <> agObject then
      DoError(DoCurrent(), PC_ERR_PAR_034, RSParMemberNotAllowed, [DoCurrent().Spelling, DoAggText(AKind)]);
    DoAdvance();
  end;
  LToken := DoCurrent();
  if (LToken.Kind = tkIdentifier) and (DoPeek(1).Kind = tkColon) then
  begin
    // PLAN-OBJECT O7 / O10: an interface holds methods and properties only: a field there is
    // PR0034 at its name, parsed and kept, marked
    if AKind = agInterface then
      DoError(LToken, PC_ERR_PAR_034, RSParInterfaceField, [LToken.Spelling]);
    LItem := DoParseField();
    if AKind = agInterface then
      LItem.IsRecovered := True;
    DoSetHidden(LItem, LHidden, LHiddenRange, AKind);
    AMembers.Add(LItem);
    Exit;
  end;
  // PLAN-OBJECT D2 / O8: `embed F: T;` (`embed: T;` is a field named embed,
  // taken above); outside an object PR0034 at the word, parsed and kept,
  // marked. After a 'hidden' already reported there, one report is enough
  if DoIsEmbedAt(0) then
  begin
    if (AKind <> agObject) and not LHidden then
      DoError(LToken, PC_ERR_PAR_034, RSParMemberNotAllowed, [LToken.Spelling, DoAggText(AKind)]);
    LItem := DoParseEmbed();
    if AKind <> agObject then
      LItem.IsRecovered := True;
    DoSetHidden(LItem, LHidden, LHiddenRange, AKind);
    AMembers.Add(LItem);
    Exit;
  end;
  // PLAN-OBJECT O9 / O10 (D12): `[words] property X: T read ...;`
  // (`property: T;` is a field, taken above); an interface takes properties
  // too (DoParseProperty(True)); a record / overlay PR0034 at the first word,
  // parsed and kept, marked. A hidden property hides both accessors
  if DoPropertyRun(0) >= 0 then
  begin
    if not (AKind in [agObject, agInterface]) and not LHidden then
      DoError(LToken, PC_ERR_PAR_034, RSParMemberNotAllowed, [LToken.Spelling, DoAggText(AKind)]);
    LItem := DoParseProperty(AKind = agInterface);
    if not (AKind in [agObject, agInterface]) then
      LItem.IsRecovered := True;
    DoSetHidden(LItem, LHidden, LHiddenRange, AKind);
    if LHidden then
    begin
      if TPCPropertyItem(LItem).ReadItem <> nil then
        TPCPropertyItem(LItem).ReadItem.IsHidden := True;
      if TPCPropertyItem(LItem).WriteItem <> nil then
        TPCPropertyItem(LItem).WriteItem.IsHidden := True;
    end;
    AMembers.Add(LItem);
    Exit;
  end;
  // PLAN-OBJECT D3: an init or a done (its own member kind); outside an
  // object PR0034 at its word, parsed and kept, marked
  if DoLifecycleRun(0) >= 0 then
  begin
    if AKind <> agObject then
    begin
      LToken := DoPeek(DoLifecycleRun(0));
      DoError(LToken, PC_ERR_PAR_034, RSParMemberNotAllowed, [LToken.Spelling, DoAggText(AKind)]);
      LLifecycleReported := True;
    end;
    LItem := DoParseLifecycle(LLifecycleReported);
    // A 'hidden' before it (PR0058) is part of the member, as for a field or
    // a method (DoSetHidden): the report lies inside the recovered node
    if LHidden then
    begin
      LItem.Range.StartLine := LHiddenRange.StartLine;
      LItem.Range.StartColumn := LHiddenRange.StartColumn;
      LItem.Range.StartByteOffset := LHiddenRange.StartByteOffset;
      if TPCRoutineMember(LItem).Routine <> nil then
        TPCRoutineMember(LItem).Routine.Range := LItem.Range;
    end;
    AMembers.Add(LItem);
    Exit;
  end;
  // PLAN-OBJECT O11 (D13): `operator OP(params): T; [var block] block;` in a
  // record or an object; elsewhere PR0034 at the word, parsed and kept,
  // marked
  if LToken.Kind = tkKwOperator then
  begin
    LAllowed := AKind in [agRecord, agObject];
    if not LAllowed then
      DoError(LToken, PC_ERR_PAR_034, RSParMemberNotAllowed, [LToken.Spelling, DoAggText(AKind)]);
    LItem := DoParseOperator();
    if not LAllowed then
      LItem.IsRecovered := True;
    AMembers.Add(LItem);
    Exit;
  end;
  if LToken.Kind = tkKwOverlay then
    LAllowed := AKind in [agRecord, agAnonRecord]
  else if LToken.Kind = tkKwRecord then
    LAllowed := AKind in [agOverlay, agAnonOverlay]
  else if DoDispatchRun(0) >= 0 then
    // A method, after its words (PLAN-OBJECT D7): outside an object PR0034
    // at the first one; an interface takes them too (O7)
    LAllowed := AKind in [agObject, agInterface]
  else
  begin
    DoError(LToken, PC_ERR_PAR_001, RSParExpected, [RSParShapeMember, DoTokenText(LToken)]);
    DoSkipMember();
    DoAddSkippedMember(AMembers, LMark);
    Exit;
  end;
  if not LAllowed then
    DoError(LToken, PC_ERR_PAR_034, RSParMemberNotAllowed, [LToken.Spelling, DoAggText(AKind)]);
  if not DoIsOneOf(LToken.Kind, [tkKwOverlay, tkKwRecord]) then
    LItem := DoParseMethodItem(AKind = agInterface)
  else
    LItem := DoParseAnonAggregate(LToken.Kind = tkKwOverlay);
  if LItem = nil then
  begin
    // The nesting guard refused an anon aggregate (PR0042, nothing consumed):
    // without a skip the member loop would report it again at the same token
    DoSkipMember();
    DoAddSkippedMember(AMembers, LMark);
    Exit;
  end;
  if not LAllowed then
    LItem.IsRecovered := True;
  DoSetHidden(LItem, LHidden, LHiddenRange, AKind);
  AMembers.Add(LItem);
end;

procedure TPCParser.DoSetHidden(const AItem: TPCMemberItem; const AHidden: Boolean;
  const AHiddenRange: TSourceRange; const AKind: TPCAggKind);
begin
  // The member after 'hidden' carries it and starts at the word; outside an
  // object the word was PR0034: the member is marked (SEM silent on it)
  if (AItem = nil) or (not AHidden) then
    Exit;
  AItem.IsHidden := True;
  AItem.HiddenRange := AHiddenRange;
  AItem.Range.StartLine := AHiddenRange.StartLine;
  AItem.Range.StartColumn := AHiddenRange.StartColumn;
  AItem.Range.StartByteOffset := AHiddenRange.StartByteOffset;
  if AKind <> agObject then
    AItem.IsRecovered := True;
end;

function TPCParser.DoIsHiddenWord(): Boolean;
begin
  // 'hidden' before a field (identifier ':') or a method (its words, then
  // 'method'); `hidden: T;` is a field named hidden (PLAN-OBJECT D10, H1).
  // Before an init or a done it is the word too: reported there (PR0058)
  Result := DoIsWord(cwHidden) and
    (((DoPeek(1).Kind = tkIdentifier) and (DoPeek(2).Kind = tkColon)) or (DoDispatchRun(1) >= 0) or
    (DoLifecycleRun(1) >= 0) or DoIsEmbedAt(1) or (DoPropertyRun(1) >= 0));
end;

function TPCParser.DoIsPropertyAt(const AOffset: Integer): Boolean;
begin
  // PLAN-OBJECT O9 (H1): 'property' is the word only before identifier ':'
  // (or '[': an indexed property, O10); `property: T;` is a field named
  // property
  Result := DoIsWordAt(cwProperty, AOffset) and (DoPeek(AOffset + 1).Kind = tkIdentifier) and
    DoIsOneOf(DoPeek(AOffset + 2).Kind, [tkColon, tkLBracket]);
end;

function TPCParser.DoPropertyRun(const AOffset: Integer): Integer;
var
  LCount: Integer;
begin
  // O10: the dispatch words from AOffset that end at a property (as
  // DoDispatchRun's at 'method'): their count; -1 = no property starts there
  LCount := 0;
  while DoIsDispatchWordAt(AOffset + LCount) do
    Inc(LCount);
  if DoIsPropertyAt(AOffset + LCount) then
    Result := LCount
  else
    Result := -1;
end;

function TPCParser.DoIsWriteAt(const AOffset: Integer): Boolean;
var
  LAt: Integer;
begin
  // A property's write AOffset tokens ahead, `hidden` before it or not:
  // 'write' then a field name or '(' (`write: T;` stays a field)
  LAt := AOffset;
  if DoIsWordAt(cwHidden, LAt) and DoIsWordAt(cwWrite, LAt + 1) then
    Inc(LAt);
  Result := DoIsWordAt(cwWrite, LAt) and DoIsOneOf(DoPeek(LAt + 1).Kind, [tkIdentifier, tkLParen]);
end;

function TPCParser.DoIsDispatchWordAt(const AOffset: Integer): Boolean;
begin
  // One of a method's dispatch words (PLAN-OBJECT D7) AOffset tokens ahead
  Result := DoIsWordAt(cwVirtual, AOffset) or DoIsWordAt(cwOverride, AOffset) or DoIsWordAt(cwFinal, AOffset);
end;

function TPCParser.DoDispatchRun(const AOffset: Integer): Integer;
var
  LCount: Integer;
begin
  // The dispatch words from AOffset that end at 'method': their count (0 =
  // 'method' itself); -1 = the tokens there start no method. The words are
  // context words: `final: int32;` stays a field named final. O13b (3):
  // `const` (a keyword) may be the last word, right before 'method'
  LCount := 0;
  while DoIsDispatchWordAt(AOffset + LCount) do
    Inc(LCount);
  if (DoPeek(AOffset + LCount).Kind = tkKwConst) and (DoPeek(AOffset + LCount + 1).Kind = tkKwMethod) then
    Inc(LCount);
  if DoPeek(AOffset + LCount).Kind = tkKwMethod then
    Result := LCount
  else
    Result := -1;
end;

procedure TPCParser.DoParseDispatchWords(const AItem: TPCMethodItem);
begin
  // [ "virtual" | "override" ] [ "final" ] before 'method' (PLAN-OBJECT D7);
  // DoDispatchRun said the run ends at 'method'. A word out of that order or
  // repeated is PR0001 at the first such word, the rest of the run skipped,
  // the method kept, marked (PLAN-RECOVERY)
  if DoIsWord(cwVirtual) then
  begin
    AItem.IsVirtual := True;
    AItem.VirtualRange := DoCurrent().Range;
    DoAdvance();
  end
  else if DoIsWord(cwOverride) then
  begin
    AItem.IsOverride := True;
    AItem.OverrideRange := DoCurrent().Range;
    DoAdvance();
  end;
  if DoIsWord(cwFinal) then
  begin
    AItem.IsFinal := True;
    AItem.FinalRange := DoCurrent().Range;
    DoAdvance();
  end;
  if DoIsDispatchWordAt(0) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_001, RSParExpected, [RSParShapeMethod, DoTokenText(DoCurrent())]);
    AItem.IsRecovered := True;
    while DoIsDispatchWordAt(0) do
      DoAdvance();
  end;
  // O13b (3): [ "const" ] last, right before 'method' (DoDispatchRun)
  if (DoCurrent().Kind = tkKwConst) and (AItem.Routine <> nil) then
  begin
    AItem.Routine.IsConst := True;
    AItem.Routine.ConstRange := DoCurrent().Range;
    DoAdvance();
  end;
end;

function TPCParser.DoParseAbstractBody(const AItem: TPCMethodItem): Boolean;
begin
  // "abstract" ";" in a method's body slot (PLAN-OBJECT D7): no body
  // (Routine.Body stays nil). False = not there, the body follows. A missing
  // ';' is inserted when the next member can follow (PLAN-RECOVERY)
  if not DoIsWord(cwAbstract) then
    Exit(False);
  AItem.IsAbstract := True;
  AItem.AbstractRange := DoCurrent().Range;
  DoAdvance();
  if DoExpectTerminator(fcMember) = toMissing then
    AItem.IsRecovered := True;
  Result := True;
end;

function TPCParser.DoParseField(): TPCField;
var
  LRange: TSourceRange;
  LField: TPCField;
begin
  // field decl = identifier ":" type expr [ ":" expression ] ";" (BNF.md
  // sec 4; the expression is a bitfield width). Never nil: a field reported
  // inside is kept, marked, with its name (PLAN-RECOVERY)
  LRange := DoStartRange();
  LField := FAst.NewNode<TPCField>();
  LField.FieldName := DoCurrent().Spelling;
  LField.NameRange := DoCurrent().Range;
  DoAdvance();
  DoAdvance();
  Result := LField;
  LField.TypeExpr := DoParseTypeExpr();
  if DoTypeFailed(LField.TypeExpr) then
  begin
    DoRecoverMember(LField, LRange);
    Exit;
  end;
  if DoMatch(tkColon) then
  begin
    LField.BitWidthExpr := DoParseExpression(ecNormal);
    if DoFailed(LField.BitWidthExpr) then
    begin
      DoRecoverMember(LField, LRange);
      Exit;
    end;
  end;
  if DoExpectTerminator(fcMember) = toMissing then
  begin
    DoRecoverMember(LField, LRange);
    Exit;
  end;
  DoFinishRange(LRange);
  LField.Range := LRange;
end;

function TPCParser.DoIsEmbedAt(const AOffset: Integer): Boolean;
begin
  // PLAN-OBJECT O8 (H1): 'embed' is the word only before identifier ':'
  Result := DoIsWordAt(cwEmbed, AOffset) and (DoPeek(AOffset + 1).Kind = tkIdentifier) and
    (DoPeek(AOffset + 2).Kind = tkColon);
end;

function TPCParser.DoParseEmbed(): TPCField;
var
  LWord: TSourceRange;
begin
  // embed decl = "embed" , field decl (BNF.md sec 4): the field, marked,
  // starting at the word (a report on the word lies inside the node)
  LWord := DoCurrent().Range;
  DoAdvance();
  Result := DoParseField();
  Result.IsEmbed := True;
  Result.EmbedRange := LWord;
  Result.Range.StartLine := LWord.StartLine;
  Result.Range.StartColumn := LWord.StartColumn;
  Result.Range.StartByteOffset := LWord.StartByteOffset;
end;

function TPCParser.DoParseProperty(const AInInterface: Boolean): TPCPropertyItem;
var
  LRange: TSourceRange;
  LProperty: TPCPropertyItem;
begin
  // property decl = [ "virtual" | "override" ] [ "final" ] "property"
  //   identifier [ index ] ":" type expr read accessor [ write accessor ]
  //   [ "default" ";" ] (BNF.md sec 4, PLAN-OBJECT O9 / O10, D12): each
  // accessor ends with its own ';'. In an interface (AInInterface) the
  // property is virtual by the grammar (a word before it is PR0034) and its
  // accessors are `read;` / `write;`. No read is PR0061 where it belongs,
  // the rest of the member skipped. Never nil: a property reported inside is
  // kept, marked, with its name (PLAN-RECOVERY). Current: its first word
  LRange := DoStartRange();
  LProperty := FAst.NewNode<TPCPropertyItem>();
  Result := LProperty;
  if AInInterface then
  begin
    if DoIsDispatchWordAt(0) then
    begin
      DoError(DoCurrent(), PC_ERR_PAR_034, RSParMemberNotAllowed, [DoCurrent().Spelling, RSParAggInterface]);
      LProperty.IsRecovered := True;
      while DoIsDispatchWordAt(0) do
        DoAdvance();
    end;
    LProperty.IsVirtual := True;
    LProperty.VirtualRange := DoCurrent().Range;
    LProperty.IsInterfaceMember := True;
  end
  else
    DoParsePropertyWords(LProperty);
  LProperty.WordRange := DoCurrent().Range;
  DoAdvance();
  LProperty.PropName := DoCurrent().Spelling;
  LProperty.NameRange := DoCurrent().Range;
  DoAdvance();
  if DoCheck(tkLBracket) and not DoParseIndexParam(LProperty) then
  begin
    DoRecoverMember(LProperty, LRange);
    Exit;
  end;
  if not DoExpect(tkColon, DoSpelled(':')) then
  begin
    DoRecoverMember(LProperty, LRange);
    Exit;
  end;
  LProperty.TypeExpr := DoParseTypeExpr();
  if DoTypeFailed(LProperty.TypeExpr) then
  begin
    DoRecoverMember(LProperty, LRange);
    Exit;
  end;
  if not DoIsWord(cwRead) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_061, RSParPropertyNoRead, [LProperty.PropName, DoTokenText(DoCurrent())]);
    DoRecoverMember(LProperty, LRange);
    Exit;
  end;
  LProperty.ReadItem := DoParseAccessor(LProperty, False, AInInterface);
  if DoIsWriteAt(0) or (AInInterface and DoIsWord(cwWrite) and (DoPeek(1).Kind = tkSemicolon)) then
    LProperty.WriteItem := DoParseAccessor(LProperty, True, AInInterface);
  // O10: `default;` makes LO[i] mean this indexed property (SEM: SM0379)
  if DoIsWord(cwDefault) and (DoPeek(1).Kind = tkSemicolon) then
  begin
    LProperty.IsDefault := True;
    LProperty.DefaultRange := DoCurrent().Range;
    DoAdvance();
    DoAdvance();
  end;
  if LProperty.ReadItem.IsRecovered or ((LProperty.WriteItem <> nil) and LProperty.WriteItem.IsRecovered) then
    LProperty.IsRecovered := True;
  DoFinishRange(LRange);
  LProperty.Range := LRange;
end;

procedure TPCParser.DoParsePropertyWords(const AProperty: TPCPropertyItem);
begin
  // O10: [ "virtual" | "override" ] [ "final" ] before 'property', in a
  // method's order (DoParseDispatchWords); a word out of that order or
  // repeated is PR0001 at it, the rest of the run skipped, kept, marked
  if DoIsWord(cwVirtual) then
  begin
    AProperty.IsVirtual := True;
    AProperty.VirtualRange := DoCurrent().Range;
    DoAdvance();
  end
  else if DoIsWord(cwOverride) then
  begin
    AProperty.IsOverride := True;
    AProperty.OverrideRange := DoCurrent().Range;
    DoAdvance();
  end;
  if DoIsWord(cwFinal) then
  begin
    AProperty.IsFinal := True;
    AProperty.FinalRange := DoCurrent().Range;
    DoAdvance();
  end;
  if not DoIsDispatchWordAt(0) then
    Exit;
  DoError(DoCurrent(), PC_ERR_PAR_001, RSParExpected, [RSParShapeProperty, DoTokenText(DoCurrent())]);
  AProperty.IsRecovered := True;
  while DoIsDispatchWordAt(0) do
    DoAdvance();
end;

function TPCParser.DoParseIndexParam(const AProperty: TPCPropertyItem): Boolean;
var
  LParam: TPCParam;
begin
  // O10: index = "[" [ "const" ] identifier ":" type expr "]" -- one index
  // parameter, by value or const (a var index is PR0061). False = reported
  // (the caller skips the member). Current: '['
  DoAdvance();
  LParam := FAst.NewNode<TPCParam>();
  LParam.Range := DoCurrent().Range;
  if DoCheck(tkKwConst) then
  begin
    LParam.ParamMode := pmConst;
    DoAdvance();
  end;
  // A report skips through the ']' first, so the member's skip (DoSkipMember)
  // never stops at a ';' inside the brackets (one report)
  if not ((DoCurrent().Kind = tkIdentifier) and (DoPeek(1).Kind = tkColon)) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_061, RSParPropertyIndex, [AProperty.PropName, DoTokenText(DoCurrent())]);
    DoSkipBalancedTo([tkRBracket, tkKwEnd]);
    DoMatch(tkRBracket);
    Exit(False);
  end;
  LParam.ParamName := DoCurrent().Spelling;
  LParam.NameRange := DoCurrent().Range;
  DoAdvance();
  DoAdvance();
  LParam.TypeExpr := DoParseTypeExpr();
  AProperty.IndexParam := LParam;
  if DoTypeFailed(LParam.TypeExpr) then
  begin
    DoSkipBalancedTo([tkRBracket, tkKwEnd]);
    DoMatch(tkRBracket);
    Exit(False);
  end;
  if not DoCheck(tkRBracket) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_061, RSParPropertyIndex, [AProperty.PropName, DoTokenText(DoCurrent())]);
    DoSkipBalancedTo([tkRBracket, tkKwEnd]);
    DoMatch(tkRBracket);
    Exit(False);
  end;
  LParam.Range.EndLine := DoCurrent().Range.EndLine;
  LParam.Range.EndColumn := DoCurrent().Range.EndColumn;
  LParam.Range.EndByteOffset := DoCurrent().Range.EndByteOffset;
  DoAdvance();
  Result := True;
end;

function TPCParser.DoParseAccessor(const AProperty: TPCPropertyItem; const AIsWrite: Boolean;
  const AInInterface: Boolean): TPCAccessorItem;
var
  LRange: TSourceRange;
  LAccessor: TPCAccessorItem;
  LRoutine: TPCRoutine;
  LParam: TPCParam;
begin
  // read accessor = "read" ( identifier ";" | "abstract" ";" | { var block }
  // block ";" ); write accessor = [ "hidden" ] "write" ( identifier ";" |
  // "abstract" ";" | "(" identifier ")" { var block } block ";" ) (BNF.md
  // sec 4, PLAN-OBJECT O9 / O10). An identifier binds a field (not on an
  // indexed property: PR0061). An inline accessor is a TPCRoutine rnRead /
  // rnWrite named after its property, its body through
  // DoParseRoutineBody(baMethod) (var blocks, as a method's); its index
  // parameter and its result / value type are the property's nodes
  // (NON-owning: its own TPCParams, types borrowed). `abstract` (or, in an
  // interface, nothing before the ';') keeps the routine with no body.
  // Another shape is PR0061 at its first token, the rest of the member
  // skipped. Never nil: kept, marked (PLAN-RECOVERY). Current: 'hidden' or
  // the word
  LRange := DoStartRange();
  LAccessor := FAst.NewNode<TPCAccessorItem>();
  Result := LAccessor;
  LAccessor.IsWrite := AIsWrite;
  LAccessor.PropertyItem := AProperty;
  if AIsWrite and DoIsWord(cwHidden) then
  begin
    LAccessor.IsHidden := True;
    LAccessor.HiddenRange := DoCurrent().Range;
    DoAdvance();
  end;
  LAccessor.WordRange := DoCurrent().Range;
  DoAdvance();
  // A field binding; a missing ';' is inserted when the next member (or the
  // write) can follow (PLAN-RECOVERY)
  if (DoCurrent().Kind = tkIdentifier) and not DoIsWord(cwAbstract) and not AInInterface then
  begin
    if AProperty.IndexParam <> nil then
    begin
      DoError(DoCurrent(), PC_ERR_PAR_061, RSParPropertyIndexBinding, [AProperty.PropName]);
      DoRecoverAccessor(LAccessor, LRange);
      Exit;
    end;
    LAccessor.FieldName := DoCurrent().Spelling;
    LAccessor.FieldRange := DoCurrent().Range;
    DoAdvance();
    if DoExpectTerminator(fcMember) = toMissing then
      LAccessor.IsRecovered := True;
    DoFinishRange(LRange);
    LAccessor.Range := LRange;
    Exit;
  end;
  LRoutine := FAst.NewNode<TPCRoutine>();
  LRoutine.DeclName := AProperty.PropName;
  LRoutine.NameRange := AProperty.NameRange;
  LAccessor.Routine := LRoutine;
  // O10: the index parameter, the routine's own node of it (type borrowed)
  if AProperty.IndexParam <> nil then
    LRoutine.Params.Add(DoBorrowedParam(AProperty.IndexParam));
  if AIsWrite then
    LRoutine.RoutineKind := rnWrite
  else
  begin
    LRoutine.RoutineKind := rnRead;
    LRoutine.ReturnType := AProperty.TypeExpr;
  end;
  // O10: an abstract accessor (`abstract;`, an interface's `;`) has no body
  if DoIsWord(cwAbstract) or (AInInterface and DoCheck(tkSemicolon)) then
  begin
    LAccessor.IsAbstract := True;
    if DoIsWord(cwAbstract) then
    begin
      if AInInterface then
      begin
        DoError(DoCurrent(), PC_ERR_PAR_060, RSParInterfacePropertyBody, [AProperty.PropName]);
        LAccessor.IsRecovered := True;
      end;
      LAccessor.AbstractRange := DoCurrent().Range;
      DoAdvance();
    end
    else
      LAccessor.AbstractRange := LAccessor.WordRange;
    if DoExpectTerminator(fcMember) = toMissing then
      LAccessor.IsRecovered := True;
    DoFinishRange(LRange);
    LRoutine.Range := LRange;
    LAccessor.Range := LRange;
    if LAccessor.IsRecovered then
      LRoutine.IsRecovered := True;
    Exit;
  end;
  // In an interface an accessor has no body (PR0060): a body is parsed and
  // kept below (its names resolve), anything else skipped (one report)
  if AInInterface then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_060, RSParInterfacePropertyBody, [AProperty.PropName]);
    LAccessor.IsRecovered := True;
    if not (DoIsBodyStart() or (AIsWrite and DoCheck(tkLParen))) then
    begin
      DoRecoverAccessor(LAccessor, LRange);
      Exit;
    end;
  end;
  if AIsWrite then
  begin
    if (DoCurrent().Kind = tkLParen) and (DoPeek(1).Kind = tkIdentifier) and (DoPeek(2).Kind = tkRParen) then
    begin
      DoAdvance();
      LParam := FAst.NewNode<TPCParam>();
      LParam.ParamName := DoCurrent().Spelling;
      LParam.NameRange := DoCurrent().Range;
      LParam.Range := DoCurrent().Range;
      LParam.ParamMode := pmNone;
      LParam.TypeExpr := AProperty.TypeExpr;
      LParam.IsTypeBorrowed := True;
      LRoutine.Params.Add(LParam);
      DoAdvance();
      DoAdvance();
    end
    else
    begin
      DoError(DoCurrent(), PC_ERR_PAR_061, RSParPropertyWrite, [AProperty.PropName, DoTokenText(DoCurrent())]);
      DoRecoverAccessor(LAccessor, LRange);
      Exit;
    end;
  end;
  if not DoIsBodyStart() then
  begin
    if AIsWrite then
      DoError(DoCurrent(), PC_ERR_PAR_061, RSParPropertyWrite, [AProperty.PropName, DoTokenText(DoCurrent())])
    else
      DoError(DoCurrent(), PC_ERR_PAR_061, RSParPropertyRead, [AProperty.PropName, DoTokenText(DoCurrent())]);
    DoRecoverAccessor(LAccessor, LRange);
    Exit;
  end;
  DoParseRoutineBody(LRoutine, baMethod);
  if LRoutine.IsRecovered then
    LAccessor.IsRecovered := True;
  DoFinishRange(LRange);
  LRoutine.Range := LRange;
  LAccessor.Range := LRange;
end;

function TPCParser.DoBorrowedParam(const AParam: TPCParam): TPCParam;
begin
  // O10: an accessor routine's own node of the property's index parameter:
  // name, mode and ranges copied, the type borrowed (the property holds it)
  Result := FAst.NewNode<TPCParam>();
  Result.ParamName := AParam.ParamName;
  Result.NameRange := AParam.NameRange;
  Result.Range := AParam.Range;
  Result.ParamMode := AParam.ParamMode;
  Result.TypeExpr := AParam.TypeExpr;
  Result.IsTypeBorrowed := True;
end;

procedure TPCParser.DoRecoverAccessor(const AAccessor: TPCAccessorItem; var ARange: TSourceRange);
begin
  // An accessor reported inside: the member's rest skipped, it and its
  // routine kept, marked, over the same range (PLAN-RECOVERY)
  DoRecoverMember(AAccessor, ARange);
  if AAccessor.Routine <> nil then
  begin
    AAccessor.Routine.Range := AAccessor.Range;
    AAccessor.Routine.IsRecovered := True;
  end;
end;

function TPCParser.DoParseAnonAggregate(const AIsOverlay: Boolean): TPCAnonAggregate;
begin
  // An anonymous record / overlay inside the nesting guard: they nest
  // without a type expr in between (F4). nil = reported
  if not DoEnterNested() then
    Exit(nil);
  try
    Result := DoParseAnonBody(AIsOverlay);
  finally
    DoLeaveNested();
  end;
end;

function TPCParser.DoParseAnonBody(const AIsOverlay: Boolean): TPCAnonAggregate;
var
  LRange: TSourceRange;
  LAgg: TPCAnonAggregate;
  LKind: TPCAggKind;
begin
  // anon record = "record" [ "packed" ] { field decl | anon overlay } "end" ";"
  // anon overlay = "overlay" { field decl | anon record } "end" ";" (BNF.md
  // sec 4); 'packed' on an anon overlay is PR0033, consumed. Never nil: a
  // missing end or ';' keeps it, marked (PLAN-RECOVERY)
  LRange := DoStartRange();
  LAgg := FAst.NewNode<TPCAnonAggregate>();
  Result := LAgg;
  LAgg.IsOverlay := AIsOverlay;
  DoAdvance();
  if DoCheck(tkKwPacked) then
  begin
    if AIsOverlay then
      DoError(DoCurrent(), PC_ERR_PAR_033, RSParNotOnAggregate,
        [DoCurrent().Spelling, RSParAggAnonOverlay])
    else
      LAgg.IsPacked := True;
    DoAdvance();
  end;
  if AIsOverlay then
    LKind := agAnonOverlay
  else
    LKind := agAnonRecord;
  DoParseMembers(LAgg.Members, LKind);
  if not DoExpectEnd() then
  begin
    DoFinishRange(LRange);
    LAgg.Range := LRange;
    LAgg.IsRecovered := True;
    Exit;
  end;
  if DoExpectTerminator(fcMember) = toMissing then
  begin
    DoRecoverMember(LAgg, LRange);
    Exit;
  end;
  DoFinishRange(LRange);
  LAgg.Range := LRange;
end;

function TPCParser.DoParseMethodItem(const AInInterface: Boolean): TPCMethodItem;
var
  LRange: TSourceRange;
  LRoutine: TPCRoutine;
begin
  // AInInterface (PLAN-OBJECT O7): DoParseInterfaceMethod
  if AInInterface then
    Exit(DoParseInterfaceMethod());
  // method decl = [ "virtual" | "override" ] [ "final" ] "method" identifier
  //   [ param list ] [ ":" type expr ] ";" ( "abstract" ";" | { var block }
  //   block ";" ) (BNF.md sec 3, PLAN-OBJECT D7): a TPCRoutine rnMethod,
  // Linkage lnNone, the body through DoParseRoutineBody(baMethod) (T13);
  // abstract leaves Body nil. A header error still parses the body (X6); the
  // method is kept, marked (PLAN-RECOVERY). Current: its first word
  LRange := DoStartRange();
  LRoutine := FAst.NewNode<TPCRoutine>();
  LRoutine.RoutineKind := rnMethod;
  Result := FAst.NewNode<TPCMethodItem>();
  Result.Routine := LRoutine;
  DoParseDispatchWords(Result);
  DoAdvance();
  if not DoParseSignature(LRoutine, fcSignature) then
  begin
    if not DoIsBodyStart() then
      DoSkipMember();
    if DoIsBodyStart() then
      DoParseRoutineBody(LRoutine, baMethod);
    LRoutine.IsRecovered := True;
    Result.IsRecovered := True;
  end
  else if not DoParseAbstractBody(Result) then
    DoParseRoutineBody(LRoutine, baMethod);
  if Result.IsRecovered then
    LRoutine.IsRecovered := True;
  DoFinishRange(LRange);
  LRoutine.Range := LRange;
  Result.Range := LRange;
end;

function TPCParser.DoParseInterfaceMethod(): TPCMethodItem;
var
  LRange: TSourceRange;
  LRoutine: TPCRoutine;
  LBodyToken: TPCToken;
begin
  // An interface's method (PLAN-OBJECT O7, BNF.md sec 4): "method" identifier
  // [ param list ] [ ":" type expr ] ";". It is virtual and abstract by the
  // grammar: IsVirtual / IsAbstract set, their ranges the 'method' word, Body
  // nil. A dispatch word before it is PR0034 at the first word (skipped); a
  // body or 'abstract' after it is PR0060 at its first token, parsed and
  // kept: the method marked (PLAN-RECOVERY). Current: its first word
  LRange := DoStartRange();
  LRoutine := FAst.NewNode<TPCRoutine>();
  LRoutine.RoutineKind := rnMethod;
  Result := FAst.NewNode<TPCMethodItem>();
  Result.Routine := LRoutine;
  if DoIsDispatchWordAt(0) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_034, RSParMemberNotAllowed, [DoCurrent().Spelling, RSParAggInterface]);
    Result.IsRecovered := True;
    while DoIsDispatchWordAt(0) do
      DoAdvance();
  end;
  // O13b (3): an interface may require a const method
  if DoCurrent().Kind = tkKwConst then
  begin
    LRoutine.IsConst := True;
    LRoutine.ConstRange := DoCurrent().Range;
    DoAdvance();
  end;
  Result.IsVirtual := True;
  Result.VirtualRange := DoCurrent().Range;
  Result.IsAbstract := True;
  Result.AbstractRange := DoCurrent().Range;
  Result.IsInterfaceMember := True;
  DoAdvance();
  if not DoParseSignature(LRoutine, fcSignature) then
  begin
    if not DoIsBodyStart() and not DoIsWord(cwAbstract) then
      DoSkipMember();
    Result.IsRecovered := True;
  end;
  if DoIsWord(cwAbstract) or DoIsBodyStart() then
  begin
    LBodyToken := DoCurrent();
    DoError(LBodyToken, PC_ERR_PAR_060, RSParInterfaceBody, []);
    // Parsed and kept inside the marked method, so its tokens stay in a node
    // and its names resolve (PLAN-RECOVERY: SEM is silent on it)
    if DoIsWord(cwAbstract) then
    begin
      DoAdvance();
      DoExpectTerminator(fcMember);
    end
    else
      DoParseRoutineBody(LRoutine, baMethod);
    Result.IsRecovered := True;
  end;
  if Result.IsRecovered then
    LRoutine.IsRecovered := True;
  DoFinishRange(LRange);
  LRoutine.Range := LRange;
  Result.Range := LRange;
end;

function TPCParser.DoIsLifecycleAt(const AOffset: Integer): Boolean;
begin
  // An init, a copy or a done starts AOffset tokens ahead (PLAN-OBJECT D3,
  // O5, H1): 'init' '(' / 'copy' '(' or 'done' ';' ('done' '(' too:
  // DoParseLifecycle reports the parameters); `init: T;` / `copy: T;` /
  // `done: T;` stay fields named so
  Result := (DoIsWordAt(cwInit, AOffset) and (DoPeek(AOffset + 1).Kind = tkLParen)) or
    (DoIsWordAt(cwCopy, AOffset) and (DoPeek(AOffset + 1).Kind = tkLParen)) or
    (DoIsWordAt(cwDone, AOffset) and DoIsOneOf(DoPeek(AOffset + 1).Kind, [tkSemicolon, tkLParen]));
end;

function TPCParser.DoLifecycleRun(const AOffset: Integer): Integer;
var
  LCount: Integer;
begin
  // The dispatch words from AOffset that end at an init or a done: their
  // count (0 = the init / done itself); -1 = none starts there. The words
  // are an error there (PR0058) but still lead to the member they precede
  LCount := 0;
  while DoIsDispatchWordAt(AOffset + LCount) do
    Inc(LCount);
  if DoIsLifecycleAt(AOffset + LCount) then
    Result := LCount
  else
    Result := -1;
end;

function TPCParser.DoParseLifecycle(const AReported: Boolean): TPCRoutineMember;
var
  LRange: TSourceRange;
  LRoutine: TPCRoutine;
  LReported: Boolean;
  LIsInit: Boolean;
  LIsCopy: Boolean;
  LWordRange: TSourceRange;
begin
  // init decl = "init" param list ";" { var block } block ";", copy decl =
  // "copy" param list ";" { var block } block ";" (O5) and done decl
  // = "done" ";" { var block } block ";" (BNF.md sec 4, PLAN-OBJECT D3): a
  // TPCRoutine rnInit / rnCopy / rnDone named by its word, its body through
  // DoParseRoutineBody(baMethod). A dispatch word before it is PR0058 at the
  // first, the run skipped; a result type or '...' on an init, parameters or
  // a result type on a done are PR0059 at that part. Never nil: a member
  // reported inside (AReported: before it) is kept, marked (PLAN-RECOVERY).
  // Current: its first token
  LRange := DoStartRange();
  LReported := AReported;
  if DoIsDispatchWordAt(0) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_058, RSParLifecycleWord, [DoCurrent().Spelling]);
    LReported := True;
    while DoIsDispatchWordAt(0) do
      DoAdvance();
  end;
  // PLAN-OBJECT O5: a copy takes the init's shape (parameters, no result, no
  // '...'); its one const parameter of the own type is SEM's (SM0353)
  LIsCopy := DoIsWord(cwCopy);
  LIsInit := DoIsWord(cwInit) or LIsCopy;
  LWordRange := DoCurrent().Range;
  LRoutine := FAst.NewNode<TPCRoutine>();
  if LIsCopy then
  begin
    LRoutine.RoutineKind := rnCopy;
    Result := FAst.NewNode<TPCCopyItem>();
    TPCCopyItem(Result).WordRange := LWordRange;
  end
  else if LIsInit then
  begin
    LRoutine.RoutineKind := rnInit;
    Result := FAst.NewNode<TPCInitItem>();
    TPCInitItem(Result).WordRange := LWordRange;
  end
  else
  begin
    LRoutine.RoutineKind := rnDone;
    Result := FAst.NewNode<TPCDoneItem>();
    TPCDoneItem(Result).WordRange := LWordRange;
    if DoPeek(1).Kind = tkLParen then
    begin
      DoError(DoPeek(1), PC_ERR_PAR_059, RSParDoneShape, []);
      LReported := True;
    end;
  end;
  Result.Routine := LRoutine;
  if not DoParseSignature(LRoutine, fcSignature) then
  begin
    if not DoIsBodyStart() then
      DoSkipMember();
    if DoIsBodyStart() then
      DoParseRoutineBody(LRoutine, baMethod);
    LReported := True;
  end
  else
  begin
    // The shape BNF gives each: an init takes parameters, no result, no
    // '...'; a done takes nothing (its '(' was reported above)
    if LIsInit and LRoutine.IsVariadic then
    begin
      if LIsCopy then
        DoErrorAt(LRoutine.VariadicRange, PC_ERR_PAR_059, RSParCopyShape, [])
      else
        DoErrorAt(LRoutine.VariadicRange, PC_ERR_PAR_059, RSParInitShape, []);
      LReported := True;
    end;
    if LRoutine.ReturnType <> nil then
    begin
      if LIsCopy then
        DoErrorAt(LRoutine.ReturnType.Range, PC_ERR_PAR_059, RSParCopyShape, [])
      else if LIsInit then
        DoErrorAt(LRoutine.ReturnType.Range, PC_ERR_PAR_059, RSParInitShape, [])
      else
        DoErrorAt(LRoutine.ReturnType.Range, PC_ERR_PAR_059, RSParDoneShape, []);
      LReported := True;
    end;
    DoParseRoutineBody(LRoutine, baMethod);
  end;
  if LReported then
  begin
    Result.IsRecovered := True;
    LRoutine.IsRecovered := True;
  end;
  DoFinishRange(LRange);
  LRoutine.Range := LRange;
  Result.Range := LRange;
end;

class function TPCParser.DoOperatorOf(const AKind: TPCTokenKind; out AOp: TPCBinaryOp): Boolean;
begin
  // The symbols a record / object declares (PLAN-OBJECT D13): + - * / div
  // mod = <> < <= > >= in ('-' with one parameter is the unary minus). Never
  // := and / or / not, address of, nor a C++ spelling (== != %)
  Result := True;
  if AKind = tkPlus then
    AOp := boAdd
  else if AKind = tkMinus then
    AOp := boSub
  else if AKind = tkStar then
    AOp := boMul
  else if AKind = tkSlash then
    AOp := boDiv
  else if AKind = tkKwDiv then
    AOp := boIntDiv
  else if AKind = tkKwMod then
    AOp := boMod
  else if AKind = tkEqual then
    AOp := boEq
  else if AKind = tkLessGreater then
    AOp := boNotEq
  else if AKind = tkLess then
    AOp := boLess
  else if AKind = tkLessEqual then
    AOp := boLessEq
  else if AKind = tkGreater then
    AOp := boGreater
  else if AKind = tkGreaterEqual then
    AOp := boGreaterEq
  else if AKind = tkKwIn then
    AOp := boIn
  else
  begin
    AOp := boAdd;
    Result := False;
  end;
end;

function TPCParser.DoParseOperator(): TPCOperatorItem;
var
  LRange: TSourceRange;
  LRoutine: TPCRoutine;
  LSymbol: TPCToken;
  LOk: Boolean;
begin
  // operator decl = "operator" operator symbol param list ":" type expr ";"
  //   { var block } block ";" (BNF.md sec 4, PLAN-OBJECT O11 / D13): a
  // TPCRoutine rnOperator named `operator OP` (NameRange = the symbol), its
  // body through DoParseRoutineBody(baMethod). A symbol no type declares is
  // PR0062 at it. Never nil: a reported operator is kept, marked
  // (PLAN-RECOVERY). Current: the word
  LRange := DoStartRange();
  LRoutine := FAst.NewNode<TPCRoutine>();
  LRoutine.RoutineKind := rnOperator;
  LRoutine.DeclName := 'operator';
  Result := FAst.NewNode<TPCOperatorItem>();
  Result.Routine := LRoutine;
  Result.WordRange := DoCurrent().Range;
  DoAdvance();
  LSymbol := DoCurrent();
  LOk := DoOperatorOf(LSymbol.Kind, Result.Op);
  if LOk then
  begin
    Result.OpText := LSymbol.Spelling;
    LRoutine.DeclName := 'operator ' + LSymbol.Spelling;
    LRoutine.NameRange := LSymbol.Range;
    DoAdvance();
    LOk := DoParseOperatorSignature(LRoutine);
  end
  else
    DoError(LSymbol, PC_ERR_PAR_062, RSParOperatorSymbol, [DoTokenText(LSymbol)]);
  if LOk then
    DoParseRoutineBody(LRoutine, baMethod)
  else
  begin
    if not DoIsBodyStart() then
      DoSkipMember();
    if DoIsBodyStart() then
      DoParseRoutineBody(LRoutine, baMethod);
    LRoutine.IsRecovered := True;
  end;
  if LRoutine.IsRecovered then
    Result.IsRecovered := True;
  DoFinishRange(LRange);
  LRoutine.Range := LRange;
  Result.Range := LRange;
end;

function TPCParser.DoParseOperatorSignature(const ARoutine: TPCRoutine): Boolean;
var
  LVariadic: Boolean;
  LVariadicRange: TSourceRange;
begin
  // param list ":" type expr ";" after the symbol, both required. A '...' is
  // PR0062 (an operator takes its operands only): reported, the operator
  // marked, the rest parsed. False = a part missing (reported)
  if not DoCheck(tkLParen) then
    Exit(DoExpect(tkLParen, DoSpelled('(')));
  if not DoParseParamList(ARoutine.Params, LVariadic, LVariadicRange) then
    Exit(False);
  if LVariadic then
  begin
    DoErrorAt(LVariadicRange, PC_ERR_PAR_062, RSParOperatorShape, []);
    ARoutine.IsRecovered := True;
  end;
  if not DoExpect(tkColon, DoSpelled(':')) then
    Exit(False);
  ARoutine.ReturnType := DoParseTypeExpr();
  if DoTypeFailed(ARoutine.ReturnType) then
    Exit(False);
  Result := DoExpectTerminator(fcSignature) <> toMissing;
end;

function TPCParser.DoParseChoicesType(): TPCTypeExpr;
var
  LRange: TSourceRange;
  LType: TPCChoicesType;
  LValue: TPCChoiceValue;
  LFailed: Boolean;
begin
  // choices type = "choices" "(" choice value { "," choice value } ")"
  // (BNF.md sec 4); empty = PR0035. A failed value reports once, the list
  // goes on, the type is kept, marked (PLAN-RECOVERY)
  LRange := DoStartRange();
  LType := FAst.NewNode<TPCChoicesType>();
  DoAdvance();
  if not DoExpect(tkLParen, DoSpelled('(')) then
    Exit(DoRecoverType(LType, LRange));
  if DoCheck(tkRParen) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_035, RSParEmptyChoices, []);
    DoAdvance();
    Exit(DoRecoverType(LType, LRange));
  end;
  LFailed := False;
  while not DoStopped() do
  begin
    LValue := DoParseChoiceValue();
    if (LValue = nil) or LValue.IsRecovered then
      LFailed := True;
    if LValue <> nil then
      LType.Values.Add(LValue);
    if not DoMatch(tkComma) then
      Break;
  end;
  if not DoCheck(tkRParen) then
  begin
    if not LFailed then
      DoExpect(tkRParen, DoSpelled(')'));
    Exit(DoRecoverType(LType, LRange));
  end;
  DoAdvance();
  if LFailed then
    Exit(DoRecoverType(LType, LRange));
  DoFinishRange(LRange);
  LType.Range := LRange;
  Result := LType;
end;

function TPCParser.DoParseChoiceValue(): TPCChoiceValue;
var
  LRange: TSourceRange;
  LValue: TPCChoiceValue;
begin
  // choice value = identifier [ "=" expression ] (BNF.md sec 4). nil = no
  // name, skipped up to ',' or ')'; a value whose expression failed is kept,
  // marked (PLAN-RECOVERY)
  Result := nil;
  if not DoCheck(tkIdentifier) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_001, RSParExpected, [RSParShapeName, DoTokenText(DoCurrent())]);
    DoSkipBalancedTo([tkComma, tkRParen, tkSemicolon]);
    Exit;
  end;
  LRange := DoStartRange();
  LValue := FAst.NewNode<TPCChoiceValue>();
  LValue.ValueName := DoCurrent().Spelling;
  LValue.NameRange := DoCurrent().Range;
  DoAdvance();
  if DoMatch(tkEqual) then
  begin
    LValue.ValueExpr := DoParseConstExprIn([tkComma, tkRParen, tkSemicolon]);
    if DoFailed(LValue.ValueExpr) then
    begin
      DoFinishRange(LRange);
      LValue.Range := LRange;
      LValue.IsRecovered := True;
      Exit(LValue);
    end;
  end;
  DoFinishRange(LRange);
  LValue.Range := LRange;
  Result := LValue;
end;

function TPCParser.DoEnterNested(): Boolean;
begin
  // One counter bounds every recursive parse (binary operands, prefix and
  // delete operands, types, anonymous aggregates): past PC_PAR_NEST_MAX it is
  // PR0042 at the current token, the level is not entered and nothing is
  // consumed, so no input can overflow the stack. True = the caller pairs it
  // with DoLeaveNested (in a finally)
  Inc(FExprDepth);
  if FExprDepth <= PC_PAR_NEST_MAX then
    Exit(True);
  Dec(FExprDepth);
  DoError(DoCurrent(), PC_ERR_PAR_042, RSParNestedTooDeep, [PC_PAR_NEST_MAX]);
  Result := False;
end;

procedure TPCParser.DoLeaveNested();
begin
  Dec(FExprDepth);
end;

function TPCParser.DoParseBinary(const AMinPower: Integer; const AContext: TPCExprContext): TPCExpr;
begin
  // One Pratt level inside the nesting guard (DoParseBinaryLoop)
  if not DoEnterNested() then
    Exit(nil);
  try
    Result := DoParseBinaryLoop(AMinPower, AContext);
  finally
    DoLeaveNested();
  end;
end;

function TPCParser.DoParseBinaryLoop(const AMinPower: Integer;
  const AContext: TPCExprContext): TPCExpr;
var
  LLeft: TPCExpr;
  LRight: TPCExpr;
  LThen: TPCExpr;
  LRow: TPCInfixRow;
  LOpToken: TPCToken;
  LStart: TSourceRange;
  LRange: TSourceRange;
  LBinary: TPCBinary;
  LAssign: TPCAssign;
  LTernary: TPCTernary;
  LChainReported: Boolean;
  LIsCast: Boolean;
begin
  // The Pratt loop over PC_INFIX_ROWS (BNF.md sec 6). Right-associative rows
  // (assign, ternary) recurse at their own power, left-associative ones at
  // power + 1, so a row binds only at or above AMinPower. A second comparison
  // right after one is PR0038 once per chain, then parsed left-assoc so the
  // rest still parses (D6). A C++ spelling with a PaskalCPP form is reported
  // and parsed as that form (D4). nil = reported with nothing consumed (the
  // first operand); otherwise a failure is an error expression over the
  // operands parsed (PLAN-RECOVERY)
  LChainReported := False;
  // Every node this loop builds starts where its first operand is written:
  // a parenthesized operand's own range leaves its parentheses out, so the
  // node's range starts at this token, not at LLeft.Range (else the '(' of
  // `(A > 1) and B` lies in no node)
  LStart := DoStartRange();
  LLeft := DoParseUnary();
  if DoFailed(LLeft) then
    Exit(LLeft);
  while not DoStopped() do
  begin
    LOpToken := DoCurrent();
    // PLAN-OBJECT O12: `X is T` / `X as T` take a type on their right (the
    // words are identifiers: DoTypeTestAt); `is` is a comparison for the chain
    // rule, `as` binds as `*`
    if DoTypeTestAt(0, LIsCast) then
    begin
      if PC_PAR_TYPE_TEST_POWER[LIsCast] < AMinPower then
        Break;
      LLeft := DoParseTypeTest(LLeft, LStart, LIsCast);
      if LLeft is TPCErrorExpr then
        Exit(LLeft);
      if (not LIsCast) and (not LChainReported) and DoIsRelationalAt(AContext) then
      begin
        DoError(DoCurrent(), PC_ERR_PAR_038, RSParNoChain, [DoCurrent().Spelling]);
        LChainReported := True;
      end;
      Continue;
    end;
    if (not DoInfixInfo(LOpToken, AContext, LRow)) or (LRow.Power < AMinPower) then
      Break;
    if LRow.IsCppForm then
      DoReportCppOperator(LOpToken, LRow.CppHint);
    DoAdvance();
    LRange := LStart;
    if LRow.Shape = ixAssign then
    begin
      LRight := DoParseBinary(LRow.Power, AContext);
      if DoFailed(LRight) then
        Exit(DoErrorExpr(LRange, [LLeft, LRight]));
      LAssign := FAst.NewNode<TPCAssign>();
      LAssign.Target := LLeft;
      LAssign.Op := LRow.AssignOp;
      LAssign.ValueExpr := LRight;
      DoFinishRange(LRange);
      LAssign.Range := LRange;
      LLeft := LAssign;
    end
    else if LRow.Shape = ixTernary then
    begin
      // cond expr = or expr "?" expression ":" cond expr: the middle is a
      // whole expression (ecNormal), the else binds at the ternary's power
      LThen := DoParseExpression(ecNormal);
      if DoFailed(LThen) then
        Exit(DoErrorExpr(LRange, [LLeft, LThen]));
      if not DoExpect(tkColon, DoSpelled(':')) then
        Exit(DoErrorExpr(LRange, [LLeft, LThen]));
      LRight := DoParseBinary(LRow.Power, AContext);
      if DoFailed(LRight) then
        Exit(DoErrorExpr(LRange, [LLeft, LThen, LRight]));
      LTernary := FAst.NewNode<TPCTernary>();
      LTernary.Condition := LLeft;
      LTernary.ThenExpr := LThen;
      LTernary.ElseExpr := LRight;
      DoFinishRange(LRange);
      LTernary.Range := LRange;
      LLeft := LTernary;
    end
    else
    begin
      LRight := DoParseBinary(LRow.Power + 1, AContext);
      if DoFailed(LRight) then
        Exit(DoErrorExpr(LRange, [LLeft, LRight]));
      LBinary := FAst.NewNode<TPCBinary>();
      LBinary.Left := LLeft;
      LBinary.Op := LRow.BinOp;
      LBinary.OpRange := LOpToken.Range;
      LBinary.Right := LRight;
      DoFinishRange(LRange);
      LBinary.Range := LRange;
      LLeft := LBinary;
      // rel expr = add expr [ rel op add expr ]: a comparison right after a
      // comparison is the chain error, once per chain
      if (LRow.Shape = ixRelational) and (not LChainReported) and DoIsRelationalAt(AContext) then
      begin
        DoError(DoCurrent(), PC_ERR_PAR_038, RSParNoChain, [DoCurrent().Spelling]);
        LChainReported := True;
      end;
    end;
  end;
  Result := LLeft;
end;

function TPCParser.DoCanStartTypeAt(const AOffset: Integer): Boolean;
var
  LKind: TPCTokenKind;
begin
  // The head tokens DoParseTypeForm classifies a type expr on (BNF.md sec 4),
  // at the token AOffset ahead: what may follow `is` / `as` (an owner word
  // and a type name are identifiers)
  LKind := DoPeek(AOffset).Kind;
  Result := DoIsOneOf(LKind, [tkIdentifier, tkKwPtr, tkKwArray, tkKwRoutine, tkKwSet, tkKwBool,
    tkKwChar, tkKwConst, tkKwVolatile, tkColonColon, tkKwStruct, tkKwClass, tkKwUnion, tkKwEnum,
    tkKwDecltype]) or TPCVocabulary.IsBuiltinTypeWord(LKind) or DoIsCppFundamental(LKind);
end;

function TPCParser.DoTypeTestAt(const AOffset: Integer; out AIsCast: Boolean): Boolean;
begin
  // PLAN-OBJECT O12: the context word `is` / `as` after an operand, with a
  // type after it. Anything else after the word (`is := 1`: a variable named
  // is on the next line) is not a type test: the word stays an identifier
  AIsCast := DoIsWordAt(cwAs, AOffset);
  Result := (AIsCast or DoIsWordAt(cwIs, AOffset)) and DoCanStartTypeAt(AOffset + 1);
end;

function TPCParser.DoIsRelationalAt(const AContext: TPCExprContext): Boolean;
var
  LRow: TPCInfixRow;
  LIsCast: Boolean;
begin
  // The current token starts a comparison: a rel op row or `is` (the chain
  // rule, BNF.md sec 6: rel expr does not chain)
  if DoTypeTestAt(0, LIsCast) then
    Exit(not LIsCast);
  Result := DoInfixInfo(DoCurrent(), AContext, LRow) and (LRow.Shape = ixRelational);
end;

function TPCParser.DoParseTypeTest(const AOperand: TPCExpr; const AStart: TSourceRange;
  const AIsCast: Boolean): TPCExpr;
var
  LRange: TSourceRange;
  LWord: TSourceRange;
  LType: TPCTypeExpr;
  LTest: TPCTypeTest;
begin
  // operand ( "is" | "as" ) type expr (BNF.md sec 6, PLAN-OBJECT O12): the
  // word, then the type (DoTypeTestAt saw one start). SEM judges both sides.
  // A type that failed with nothing to keep is an error expression over the
  // operand; a type the parser kept marked keeps the node marked
  // (PLAN-RECOVERY)
  LRange := AStart;
  LWord := DoCurrent().Range;
  DoAdvance();
  LType := DoParseTypeExpr();
  if LType = nil then
    Exit(DoErrorExpr(LRange, [AOperand]));
  LTest := FAst.NewNode<TPCTypeTest>();
  LTest.Operand := AOperand;
  LTest.TargetType := LType;
  LTest.IsCast := AIsCast;
  LTest.WordRange := LWord;
  DoFinishRange(LRange);
  LTest.Range := LRange;
  LTest.IsRecovered := LType.IsRecovered;
  Result := LTest;
end;

procedure TPCParser.DoReportCppOperator(const AToken: TPCToken; const AHint: string);
begin
  // PR0039 for == / != (one spelling, BNF.md sec 6), PR0040 for a C++ word
  // operator (token-vocab.md :161); the hint names the PaskalCPP form. An
  // empty hint is xor_eq, which has no one-token form
  if (AToken.Kind = tkEqualEqual) or (AToken.Kind = tkBangEqual) then
    DoError(AToken, PC_ERR_PAR_039, RSParCppOperator, [AToken.Spelling, DoSpelled(AHint)])
  else if AHint = '' then
    DoError(AToken, PC_ERR_PAR_040, RSParCppOperator, [AToken.Spelling, RSParXorEqHint])
  else
    DoError(AToken, PC_ERR_PAR_040, RSParCppOperator, [AToken.Spelling, DoSpelled(AHint)]);
end;

function TPCParser.DoParseUnary(): TPCExpr;
var
  LToken: TPCToken;
  LOp: TPCUnaryOp;
  LHint: string;
  LRange: TSourceRange;
  LOperand: TPCExpr;
  LUnary: TPCUnary;
  LCast: TPCExpr;
begin
  // unary expr = prefix op unary expr | postfix expr (BNF.md sec 6, step 1):
  // prefix operators chain (not not x, **LPP) and bind below every postfix
  // operator. 'address of' is two words; compl / bitand are PR0040 and parse
  // as ~ / &. A '(' is first tried as a C-style cast (DoTryCStyleCast).
  // nil = reported with nothing consumed; after the operator a failure is an
  // error expression (PLAN-RECOVERY)
  LToken := DoCurrent();
  if not DoPrefixInfo(LToken.Kind, LOp, LHint) then
  begin
    // cpp cast , unary expr (BNF.md sec 6): a '(' is first tried as a
    // C-style cast (verbatim-expr.md, user Q-G); not a cast = untouched
    if DoCheck(tkLParen) and DoTryCStyleCast(LCast) then
      Exit(LCast);
    Exit(DoParsePostfix());
  end;
  LRange := DoStartRange();
  if LHint <> '' then
    DoReportCppOperator(LToken, LHint);
  DoAdvance();
  if (LToken.Kind = tkKwAddress) and (not DoExpect(tkKwOf, DoSpelled('of'))) then
    Exit(DoErrorExpr(LRange, []));
  if not DoEnterNested() then
    Exit(DoErrorExpr(LRange, []));
  try
    LOperand := DoParseUnary();
  finally
    DoLeaveNested();
  end;
  if DoFailed(LOperand) then
    Exit(DoErrorExpr(LRange, [LOperand]));
  LUnary := FAst.NewNode<TPCUnary>();
  LUnary.Op := LOp;
  LUnary.OpRange := LToken.Range;
  LUnary.Operand := LOperand;
  DoFinishRange(LRange);
  LUnary.Range := LRange;
  Result := LUnary;
end;

function TPCParser.DoParsePostfix(): TPCExpr;
var
  LKind: TPCTokenKind;
begin
  // postfix expr = primary expr { postfix op } (BNF.md sec 6). Every postfix
  // operator binds tighter than every prefix one and they apply left to
  // right, so one loop builds the chain (D1). nil = the primary reported with
  // nothing consumed; a postfix form that fails returns its error expression,
  // which ends the chain (PLAN-RECOVERY)
  Result := DoParsePrimary();
  while (not DoFailed(Result)) and (not DoStopped()) do
  begin
    LKind := DoCurrent().Kind;
    if LKind = tkLParen then
      Result := DoParseCall(Result)
    else if LKind = tkLBracket then
      Result := DoParseIndex(Result)
    else if (LKind = tkDot) or (LKind = tkMinusGreater) then
      Result := DoParseMemberAccess(Result)
    else if LKind = tkCaret then
      Result := DoNewPostfixUnary(Result, uoDeref)
    else if LKind = tkPlusPlus then
      Result := DoNewPostfixUnary(Result, uoPostInc)
    else if LKind = tkMinusMinus then
      Result := DoNewPostfixUnary(Result, uoPostDec)
    else if LKind = tkLBrace then
      Result := DoParseBracedInit(Result)
    else
      Break;
  end;
end;

function TPCParser.DoNewPostfixUnary(const AOperand: TPCExpr; const AOp: TPCUnaryOp): TPCExpr;
var
  LRange: TSourceRange;
  LOpRange: TSourceRange;
  LUnary: TPCUnary;
begin
  // '^' (deref), '++', '--' after an operand: one token, consumed here
  LRange := AOperand.Range;
  LOpRange := DoCurrent().Range;
  DoAdvance();
  LUnary := FAst.NewNode<TPCUnary>();
  LUnary.Op := AOp;
  LUnary.OpRange := LOpRange;
  LUnary.Operand := AOperand;
  DoFinishRange(LRange);
  LUnary.Range := LRange;
  Result := LUnary;
end;

function TPCParser.DoErrorExpr(const ARange: TSourceRange;
  const AParts: array of TPCExpr): TPCErrorExpr;
var
  LRange: TSourceRange;
  LPart: TPCExpr;
begin
  // An expression form that reported after consuming tokens (PLAN-RECOVERY,
  // r2 D-R2-3): one error node from ARange's start through the last consumed
  // token, holding what the form parsed (nil entries skipped) so its names
  // still resolve. Never called with nothing consumed
  LRange := ARange;
  DoFinishRange(LRange);
  Result := FAst.NewNode<TPCErrorExpr>();
  Result.Range := LRange;
  for LPart in AParts do
  begin
    if LPart <> nil then
      Result.Parts.Add(LPart);
  end;
end;

function TPCParser.DoParseCall(const ACallee: TPCExpr): TPCExpr;
var
  LRange: TSourceRange;
  LCall: TPCCall;
  LTypeArgIndex: Integer;
  LError: TPCErrorExpr;
begin
  // "(" [ arg list ] ")" after an operand: every call, intrinsics included
  // (SEM resolves them, BNF.md sec 7), size(T) and next(T) / get(I, T) on a
  // varargs local with a type argument. Never nil (the callee is a part of
  // the error expression a failure returns, PLAN-RECOVERY)
  LRange := ACallee.Range;
  LCall := FAst.NewNode<TPCCall>();
  LCall.Callee := ACallee;
  // A call with a slot whose argument may be a type (DoTypeArgSlot): an
  // argument there that is unmistakably a type is the TypeArg (BNF.md sec 7);
  // otherwise the arguments parse as expressions
  if not (DoTypeArgSlot(ACallee, LTypeArgIndex) and DoTryTypeArgAt(LCall, LTypeArgIndex)) then
  begin
    if not DoParseArgList(LCall.Args, tkRParen, DoSpelled(')')) then
    begin
      LError := DoErrorExpr(LRange, [ACallee]);
      LError.Parts.AddRange(LCall.Args);
      Exit(LError);
    end;
  end;
  DoFinishRange(LRange);
  LCall.Range := LRange;
  Result := LCall;
end;

function TPCParser.DoParseIndex(const ABase: TPCExpr): TPCExpr;
var
  LRange: TSourceRange;
  LOpenRange: TSourceRange;
  LIndex: TPCIndex;
begin
  // "[" expression "]" after an operand: one index (a[i, j] is PR0001 at ',').
  // A failure is an error expression holding the base and the index
  LRange := ABase.Range;
  LOpenRange := DoCurrent().Range;
  DoAdvance();
  LIndex := FAst.NewNode<TPCIndex>();
  LIndex.Base := ABase;
  LIndex.OpenRange := LOpenRange;
  LIndex.IndexExpr := DoParseExpression(ecNormal);
  if DoFailed(LIndex.IndexExpr) or (not DoExpect(tkRBracket, DoSpelled(']'))) then
    Exit(DoErrorExpr(LRange, [ABase, LIndex.IndexExpr]));
  DoFinishRange(LRange);
  LIndex.Range := LRange;
  Result := LIndex;
end;

function TPCParser.DoParseMemberAccess(const ABase: TPCExpr): TPCExpr;
var
  LRange: TSourceRange;
  LMember: TPCMember;
begin
  // "." / "->" member name (BNF.md sec 6): any keyword is a name there;
  // template args are an attempt whose arguments are types only (tmMember).
  // A dotted module name (Geo.TPoint) is this node too: SEM resolves it. A
  // missing name is an error expression holding the base
  LRange := ABase.Range;
  LMember := FAst.NewNode<TPCMember>();
  LMember.Base := ABase;
  if DoCheck(tkDot) then
    LMember.Access := maDot
  else
    LMember.Access := maArrow;
  DoAdvance();
  LMember.Member := DoParseNamePart(True, tmMember);
  if LMember.Member = nil then
    Exit(DoErrorExpr(LRange, [ABase]));
  DoFinishRange(LRange);
  LMember.Range := LRange;
  Result := LMember;
end;

function TPCParser.DoParseBracedInit(const ABase: TPCExpr): TPCExpr;
var
  LRange: TSourceRange;
  LInit: TPCBracedInit;
  LError: TPCErrorExpr;
begin
  // braced init = "{" [ arg list ] "}" (BNF.md sec 6): after an operand
  // (T{1, 2}, std::vector<int>{}) or bare (ABase nil: LV.push_back({1, 2})).
  // Never nil: '{' is consumed; a failure is an error expression holding the
  // base and the arguments parsed (PLAN-RECOVERY)
  if ABase <> nil then
    LRange := ABase.Range
  else
    LRange := DoStartRange();
  LInit := FAst.NewNode<TPCBracedInit>();
  LInit.Base := ABase;
  if not DoParseArgList(LInit.Args, tkRBrace, DoSpelled('}')) then
  begin
    LError := DoErrorExpr(LRange, [ABase]);
    LError.Parts.AddRange(LInit.Args);
    Exit(LError);
  end;
  DoFinishRange(LRange);
  LInit.Range := LRange;
  Result := LInit;
end;

function TPCParser.DoParseArgList(const AArgs: TList<TPCExpr>; const ACloser: TPCTokenKind;
  const ACloserText: string): Boolean;
var
  LArg: TPCExpr;
begin
  // opener [ expression { "," expression } ] closer; current = the opener.
  // Every argument is a whole expression (ecNormal: a '>' inside brackets is
  // a comparison, in a template argument too). False = reported once; AArgs
  // holds every argument parsed, a failed one included (PLAN-RECOVERY)
  DoAdvance();
  if DoMatch(ACloser) then
    Exit(True);
  while not DoStopped() do
  begin
    LArg := DoParseExpression(ecNormal);
    if DoFailed(LArg) then
    begin
      if LArg <> nil then
        AArgs.Add(LArg);
      Exit(False);
    end;
    AArgs.Add(LArg);
    if not DoMatch(tkComma) then
      Break;
  end;
  Result := DoExpect(ACloser, ACloserText);
end;

function TPCParser.DoParseOwnerNew(const AKind: TPCOwnerKind): TPCExpr;
var
  LRange: TSourceRange;
  LArgsRange: TSourceRange;
  LNew: TPCOwnerNew;
  LType: TPCTypeExpr;
begin
  // owner new = ( "own" | "ref" | "weak" ) type expr [ "(" [ args ] ")" ]
  // (BNF.md sec 6, PLAN-OBJECT O6 / Q1): the object built on the heap; SEM
  // judges the type and picks the init (a weak builds nothing: SEM). nil =
  // reported with nothing consumed past the type
  Result := nil;
  LRange := DoStartRange();
  LType := DoParseOwnerType(AKind);
  if not (LType is TPCOwnerType) then
    Exit;
  LNew := FAst.NewNode<TPCOwnerNew>();
  LNew.OwnerType := TPCOwnerType(LType);
  LNew.InitCall := FAst.NewNode<TPCCall>();
  if DoCheck(tkLParen) then
  begin
    LNew.HasArgList := True;
    LArgsRange := DoStartRange();
    if not DoParseArgList(LNew.InitCall.Args, tkRParen, DoSpelled(')')) then
    begin
      DoFinishRange(LArgsRange);
      LNew.InitCall.Range := LArgsRange;
      LNew.InitCall.IsRecovered := True;
      DoFinishRange(LRange);
      LNew.Range := LRange;
      LNew.IsRecovered := True;
      Exit(LNew);
    end;
    DoFinishRange(LArgsRange);
    LNew.InitCall.Range := LArgsRange;
  end
  else
    LNew.InitCall.Range := LType.Range;
  DoFinishRange(LRange);
  LNew.Range := LRange;
  Result := LNew;
end;

function TPCParser.DoParsePrimary(): TPCExpr;
var
  LToken: TPCToken;
  LOwner: TPCOwnerKind;
begin
  // primary expr (BNF.md sec 6), dispatched on the current token, one DoXxx
  // per form. A primitive followed by '(' is a type cast. Anything else is
  // PR0001 "expected an expression" with nothing consumed. nil = reported with
  // nothing consumed (here, or a form that reported at its first token); a
  // form that consumed returns its error expression (PLAN-RECOVERY)
  LToken := DoCurrent();
  case LToken.Kind of
    tkIntLiteral:
      Result := DoParseLiteral(lkInteger);
    tkFloatLiteral:
      Result := DoParseLiteral(lkFloat);
    tkCharLiteral:
      Result := DoParseLiteral(lkChar);
    tkKwTrue, tkKwFalse:
      Result := DoParseLiteral(lkBool);
    tkKwNil:
      Result := DoParseLiteral(lkNil);
    tkStringLiteral:
      Result := DoParseStringLiteral();
    tkKwSelf:
      Result := DoParseSpecial(skSelf);
    tkKwParent:
      Result := DoParseSpecial(skParent);
    tkKwThis:
      Result := DoParseSpecial(skThis);
    tkKwNullptr:
      Result := DoParseSpecial(skNullptr);
    tkIdentifier:
      begin
        if DoIsOwnerTypeAt(0, LOwner) then
          Result := DoParseOwnerNew(LOwner)
        else if DoIsRecordLiteral() then
          Result := DoParseRecordLiteral()
        else
          Result := DoParseName();
      end;
    tkColonColon:
      Result := DoParseName();
    tkKwPtr:
      Result := DoParsePointerCast();
    tkLBracket:
      begin
        if DoIsLambdaStart() then
          Result := DoParseLambda()
        else
          Result := DoParseSetLiteral();
      end;
    tkKwVarargs:
      Result := DoParseVarargs();
    tkKwNew:
      Result := DoParseNew();
    tkKwDelete:
      Result := DoParseDelete();
    tkKwStatic_cast, tkKwReinterpret_cast, tkKwConst_cast, tkKwDynamic_cast:
      Result := DoParseNamedCast();
    tkKwSizeof, tkKwAlignof, tkKwDecltype, tkKwNoexcept, tkKwTypeid:
      Result := DoParseOpaqueGroup();
    tkKwCpp:
      Result := DoParseCppExpr();
    tkLBrace:
      Result := DoParseBracedInit(nil);
    tkLParen:
      Result := DoParseParenExpr();
  else
    if (LToken.Category = tcPrimitive) and (DoPeek(1).Kind = tkLParen) then
      Result := DoParseTypeCast()
    else
    begin
      DoError(LToken, PC_ERR_PAR_001, RSParExpected, [RSParShapeExpression, DoTokenText(LToken)]);
      Result := nil;
    end;
  end;
end;

function TPCParser.DoParseLiteral(const AKind: TPCLiteralKind): TPCExpr;
var
  LToken: TPCToken;
  LLiteral: TPCLiteral;
  LStatus: TPCCStringStatus;
  LValue: UInt64;
  LIsMultiChar: Boolean;
  LReason: string;
begin
  // integer / float / char / true / false / nil: one token as written (Text),
  // its value copied when the lexer computed one (not for hex floats and
  // user-defined literals, ast.md :270-271), and every literal fact the token
  // carries: semantics types the literal from them (inputs.md F1); a bool
  // literal's value is set here. A plain or L char gets its value here (the
  // lexer never decodes, lexer.md): an error is PR0054 and no value; a warning
  // is PR0064, the value kept (P-CHAR; F65: C++ is given CppText)
  LToken := DoCurrent();
  LLiteral := FAst.NewNode<TPCLiteral>();
  LLiteral.LiteralKind := AKind;
  LLiteral.Text := LToken.Text;
  LLiteral.CppText := LToken.Text;
  LLiteral.LiteralBase := LToken.LiteralBase;
  LLiteral.LiteralPrefix := LToken.LiteralPrefix;
  LLiteral.Suffix := LToken.Suffix;
  LLiteral.IsUserDefined := LToken.IsUserDefined;
  LLiteral.HasValue := LToken.HasValue;
  LLiteral.IntValue := LToken.IntValue;
  LLiteral.FloatValue := LToken.FloatValue;
  LLiteral.Range := LToken.Range;
  if (AKind = lkChar) and (not LToken.IsUserDefined) and
    ((LToken.LiteralPrefix = lpNone) or (LToken.LiteralPrefix = lpUpperL)) then
  begin
    LStatus := TPCCString.DecodeChar(LToken, LValue, LIsMultiChar, LReason);
    if LStatus = csError then
      DoError(LToken, PC_ERR_PAR_054, RSParBadChar, [LReason])
    else
    begin
      // F65: a warning is PaskalCPP's (it was clang's, in C++ words), and
      // C++ is given the value's spelling, so clang has nothing to say again
      if LStatus = csWarning then
        DoWarning(LToken, PC_ERR_PAR_064, RSParCharWarning, [LReason]);
      LLiteral.HasValue := True;
      LLiteral.IntValue := LValue;
      LLiteral.IsMultiChar := LIsMultiChar;
      LLiteral.CppText := TPCCString.CppSpelling(LToken.Text);
    end;
  end;
  // true / false carry their value (1 / 0): SEM never reads Text
  if AKind = lkBool then
  begin
    LLiteral.HasValue := True;
    LLiteral.IntValue := Ord(LToken.Kind = tkKwTrue);
  end;
  DoAdvance();
  Result := LLiteral;
end;

function TPCParser.DoParseStringLiteral(): TPCExpr;
var
  LToken: TPCToken;
  LLiteral: TPCLiteral;
  LParts: TArray<TPCLiteralPart>;
  LCount: Integer;
  LRange: TSourceRange;
begin
  // cstring { cstring }: adjacent string tokens join into one literal, one
  // part per token. A plain part is checked by the one cstring rule (PR0009 /
  // PR0021) and keeps its value, both in DoLiteralPartOf; a prefixed or raw
  // part is C++ and clang judges it. Text = the exact source over the whole
  // range (token ends are exclusive); the emitter reads Parts (emitter.md :178, D3)
  LRange := DoStartRange();
  LLiteral := FAst.NewNode<TPCLiteral>();
  LLiteral.LiteralKind := lkString;
  LCount := 0;
  while DoCheck(tkStringLiteral) do
  begin
    LToken := DoCurrent();
    SetLength(LParts, LCount + 1);
    LParts[LCount] := DoLiteralPartOf(LToken);
    Inc(LCount);
    DoAdvance();
  end;
  DoFinishRange(LRange);
  LLiteral.Parts := LParts;
  LLiteral.Text := FCursor.SourceSlice(LRange.StartByteOffset, LRange.EndByteOffset);
  LLiteral.Range := LRange;
  Result := LLiteral;
end;

function TPCParser.DoParseSpecial(const AKind: TPCSpecialKind): TPCExpr;
var
  LSpecial: TPCSpecial;
begin
  // self / parent / this / nullptr: one keyword (BNF.md sec 6)
  LSpecial := FAst.NewNode<TPCSpecial>();
  LSpecial.SpecialKind := AKind;
  LSpecial.Range := DoCurrent().Range;
  DoAdvance();
  Result := LSpecial;
end;

function TPCParser.DoParseName(): TPCExpr;
var
  LRange: TSourceRange;
  LName: TPCName;
  LPart: TPCNamePart;
  LAfterScope: Boolean;
begin
  // identifier | cpp name (BNF.md sec 6): parts joined by '::'; after a '::'
  // any keyword is a name and '<' is a template-argument attempt
  // (tmQualified); an unqualified name never takes '<' (a comparison). A
  // dotted Mod.Name is a member access over this name. Error expression =
  // reported after '::' (a first identifier part never fails, PLAN-RECOVERY)
  LRange := DoStartRange();
  LName := FAst.NewNode<TPCName>();
  LAfterScope := DoMatch(tkColonColon);
  LName.HasLeadingScope := LAfterScope;
  while True do
  begin
    LPart := DoParseNamePart(LAfterScope, tmQualified);
    if LPart = nil then
      Exit(DoErrorExpr(LRange, []));
    LName.Parts.Add(LPart);
    if not DoCheck(tkColonColon) then
      Break;
    DoAdvance();
    LAfterScope := True;
  end;
  DoFinishRange(LRange);
  LName.Range := LRange;
  Result := LName;
end;

function TPCParser.DoIsRecordLiteral(): Boolean;
var
  LOffset: Integer;
begin
  // record literal = qualified type "(" identifier ":" ... (BNF.md sec 6):
  // peek over identifier { "." identifier }, then '(' identifier ':'. Peek
  // only: a miss parses as a name (P(x) is a call)
  LOffset := 1;
  while (DoPeek(LOffset).Kind = tkDot) and (DoPeek(LOffset + 1).Kind = tkIdentifier) do
    Inc(LOffset, 2);
  Result := (DoPeek(LOffset).Kind = tkLParen) and (DoPeek(LOffset + 1).Kind = tkIdentifier) and
    (DoPeek(LOffset + 2).Kind = tkColon);
end;

function TPCParser.DoParseRecordLiteral(): TPCExpr;
var
  LRange: TSourceRange;
  LLiteral: TPCRecordLiteral;
  LInit: TPCFieldInit;
  LInitRange: TSourceRange;
begin
  // record literal = qualified type "(" field init { "," field init } ")",
  // field init = identifier ":" expression (BNF.md sec 6); SEM checks the
  // fields and their order. Current: the identifier (DoIsRecordLiteral held).
  // A failure is an error expression holding the values parsed (PLAN-RECOVERY)
  LRange := DoStartRange();
  LLiteral := FAst.NewNode<TPCRecordLiteral>();
  LLiteral.RecordType := DoParseQualifiedType();
  DoAdvance();
  while not DoStopped() do
  begin
    if not DoCheck(tkIdentifier) then
    begin
      DoError(DoCurrent(), PC_ERR_PAR_001, RSParExpected,
        [RSParShapeIdentifier, DoTokenText(DoCurrent())]);
      Exit(DoRecordLiteralError(LLiteral, LRange, nil));
    end;
    LInitRange := DoStartRange();
    LInit := FAst.NewNode<TPCFieldInit>();
    LInit.FieldName := DoCurrent().Spelling;
    DoAdvance();
    if not DoExpect(tkColon, DoSpelled(':')) then
      Exit(DoRecordLiteralError(LLiteral, LRange, nil));
    LInit.ValueExpr := DoParseExpression(ecNormal);
    if DoFailed(LInit.ValueExpr) then
      Exit(DoRecordLiteralError(LLiteral, LRange, LInit.ValueExpr));
    DoFinishRange(LInitRange);
    LInit.Range := LInitRange;
    LLiteral.Inits.Add(LInit);
    if not DoMatch(tkComma) then
      Break;
  end;
  if not DoExpect(tkRParen, DoSpelled(')')) then
    Exit(DoRecordLiteralError(LLiteral, LRange, nil));
  DoFinishRange(LRange);
  LLiteral.Range := LRange;
  Result := LLiteral;
end;

function TPCParser.DoRecordLiteralError(const ALiteral: TPCRecordLiteral;
  const ARange: TSourceRange; const AFailed: TPCExpr): TPCExpr;
var
  LError: TPCErrorExpr;
  LInit: TPCFieldInit;
begin
  // A record literal that reported: the values of its complete inits, then
  // the value that failed (nil = none)
  LError := DoErrorExpr(ARange, []);
  for LInit in ALiteral.Inits do
    LError.Parts.Add(LInit.ValueExpr);
  if AFailed <> nil then
    LError.Parts.Add(AFailed);
  Result := LError;
end;

function TPCParser.DoParseTypeCast(): TPCExpr;
var
  LRange: TSourceRange;
  LCast: TPCCast;
  LKeyword: TPCToken;
begin
  // type cast = builtin type "(" expression ")" (BNF.md sec 6): exactly one
  // argument; a second one is PR0041 at its ','. Current: the primitive,
  // followed by '('. A failure is an error expression holding the operand
  // (PLAN-RECOVERY)
  LRange := DoStartRange();
  LKeyword := DoCurrent();
  LCast := FAst.NewNode<TPCCast>();
  LCast.CastKind := ckBuiltin;
  LCast.TargetType := DoNewBuiltin();
  DoAdvance();
  LCast.Operand := DoParseExpression(ecNormal);
  if DoFailed(LCast.Operand) then
    Exit(DoErrorExpr(LRange, [LCast.Operand]));
  if DoCheck(tkComma) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_041, RSParCastOneArg, [LKeyword.Spelling]);
    Exit(DoErrorExpr(LRange, [LCast.Operand]));
  end;
  if not DoExpect(tkRParen, DoSpelled(')')) then
    Exit(DoErrorExpr(LRange, [LCast.Operand]));
  DoFinishRange(LRange);
  LCast.Range := LRange;
  Result := LCast;
end;

function TPCParser.DoParsePointerCast(): TPCExpr;
var
  LRange: TSourceRange;
  LCast: TPCCast;
  LType: TPCTypeExpr;
begin
  // pointer cast = "ptr" "to" [ "const" ] type expr "(" expression ")"
  // (BNF.md sec 6): the type is A's pointer type, its target required here
  // (a bare ptr is PR0001 at the token after it). nil = nothing consumed (no
  // 'to'); any later failure is an error expression (PLAN-RECOVERY)
  Result := nil;
  LRange := DoStartRange();
  if DoPeek(1).Kind <> tkKwTo then
  begin
    DoError(DoPeek(1), PC_ERR_PAR_001, RSParExpected, [DoSpelled('to'), DoTokenText(DoPeek(1))]);
    Exit;
  end;
  LType := DoParseTypeExpr();
  if DoTypeFailed(LType) then
    Exit(DoErrorExpr(LRange, []));
  LCast := FAst.NewNode<TPCCast>();
  LCast.CastKind := ckPointer;
  LCast.TargetType := LType;
  if not DoExpect(tkLParen, DoSpelled('(')) then
    Exit(DoErrorExpr(LRange, []));
  LCast.Operand := DoParseExpression(ecNormal);
  if DoFailed(LCast.Operand) or (not DoExpect(tkRParen, DoSpelled(')'))) then
    Exit(DoErrorExpr(LRange, [LCast.Operand]));
  DoFinishRange(LRange);
  LCast.Range := LRange;
  Result := LCast;
end;

function TPCParser.DoParseSetLiteral(): TPCExpr;
var
  LRange: TSourceRange;
  LSet: TPCSetLiteral;
  LElement: TPCSetElement;
  LElementRange: TSourceRange;
begin
  // set literal = "[" [ set element { "," set element } ] "]", set element =
  // expression [ ".." expression ] (BNF.md sec 6; '..' is no operator, so the
  // low expression stops there). DoParsePrimary tried a lambda first. A
  // failure is an error expression holding the bounds parsed (PLAN-RECOVERY)
  LRange := DoStartRange();
  LSet := FAst.NewNode<TPCSetLiteral>();
  DoAdvance();
  if not DoCheck(tkRBracket) then
  begin
    while not DoStopped() do
    begin
      LElementRange := DoStartRange();
      LElement := FAst.NewNode<TPCSetElement>();
      LElement.LowExpr := DoParseExpression(ecNormal);
      if DoFailed(LElement.LowExpr) then
        Exit(DoSetLiteralError(LSet, LRange, LElement.LowExpr, nil));
      if DoMatch(tkDotDot) then
      begin
        LElement.HighExpr := DoParseExpression(ecNormal);
        if DoFailed(LElement.HighExpr) then
          Exit(DoSetLiteralError(LSet, LRange, LElement.LowExpr, LElement.HighExpr));
      end;
      DoFinishRange(LElementRange);
      LElement.Range := LElementRange;
      LSet.Elements.Add(LElement);
      if not DoMatch(tkComma) then
        Break;
    end;
  end;
  if not DoExpect(tkRBracket, DoSpelled(']')) then
    Exit(DoSetLiteralError(LSet, LRange, nil, nil));
  DoFinishRange(LRange);
  LSet.Range := LRange;
  Result := LSet;
end;

function TPCParser.DoSetLiteralError(const ASet: TPCSetLiteral; const ARange: TSourceRange;
  const ALow: TPCExpr; const AHigh: TPCExpr): TPCExpr;
var
  LError: TPCErrorExpr;
  LElement: TPCSetElement;
begin
  // A set literal that reported: the bounds of its complete elements, then
  // those of the element that failed (nil = none)
  LError := DoErrorExpr(ARange, []);
  for LElement in ASet.Elements do
  begin
    LError.Parts.Add(LElement.LowExpr);
    if LElement.HighExpr <> nil then
      LError.Parts.Add(LElement.HighExpr);
  end;
  if ALow <> nil then
    LError.Parts.Add(ALow);
  if AHigh <> nil then
    LError.Parts.Add(AHigh);
  Result := LError;
end;

function TPCParser.DoParseVarargs(): TPCExpr;
var
  LRange: TSourceRange;
  LVarargs: TPCVarargs;
  LKind: TPCVarargsKind;
begin
  // varargs expr = "varargs" [ "." "count" | "." "next" "(" type expr ")" |
  //   "." "get" "(" expression "," type expr ")" | "." "reset" "(" ")" |
  //   "." "copy" "(" ")" ] (BNF.md sec 6); the words are identifiers matched
  // on their spelling, a call word only with '('. Any other '.' after varargs
  // (varargs.reset without '(' too) is a member access (SEM reports it).
  // A failure is an error expression holding the index (PLAN-RECOVERY)
  LRange := DoStartRange();
  LVarargs := FAst.NewNode<TPCVarargs>();
  LVarargs.VarargsKind := vaPlain;
  DoAdvance();
  if DoCheck(tkDot) and (DoPeek(1).Kind = tkIdentifier) then
  begin
    if DoPeek(1).Spelling = PC_VARARGS_WORDS[vaCount] then
    begin
      DoAdvance();
      DoAdvance();
      LVarargs.VarargsKind := vaCount;
    end
    else if DoVarargsCallKind(DoPeek(1).Spelling, LKind) and (DoPeek(2).Kind = tkLParen) then
    begin
      DoAdvance();
      DoAdvance();
      DoAdvance();
      LVarargs.VarargsKind := LKind;
      if not DoParseVarargsArgs(LVarargs) then
        Exit(DoErrorExpr(LRange, [LVarargs.IndexExpr]));
    end;
  end;
  DoFinishRange(LRange);
  LVarargs.Range := LRange;
  Result := LVarargs;
end;

class function TPCParser.DoVarargsCallKind(const AWord: string;
  out AKind: TPCVarargsKind): Boolean;
var
  LKind: TPCVarargsKind;
begin
  // The varargs call words (BNF.md sec 6, PC_VARARGS_WORDS), matched by
  // spelling; count is no call. vaNext .. vaCopy are the call forms, in
  // TPCVarargsKind order
  for LKind := vaNext to vaCopy do
  begin
    if AWord = PC_VARARGS_WORDS[LKind] then
    begin
      AKind := LKind;
      Exit(True);
    end;
  end;
  AKind := vaPlain;
  Result := False;
end;

function TPCParser.DoParseVarargsArgs(const AVarargs: TPCVarargs): Boolean;
begin
  // A varargs call's arguments after its '(' through ')' by kind: next (a
  // type), get (the index expression ',' a type), reset / copy (none).
  // False = reported once, at the first failure; nothing skipped (the caller
  // turns it into an error expression, PLAN-RECOVERY)
  if AVarargs.VarargsKind = vaGet then
  begin
    AVarargs.IndexExpr := DoParseExpression(ecNormal);
    if DoFailed(AVarargs.IndexExpr) or (not DoExpect(tkComma, DoSpelled(','))) then
      Exit(False);
  end;
  if (AVarargs.VarargsKind = vaNext) or (AVarargs.VarargsKind = vaGet) then
  begin
    AVarargs.ReadType := DoParseTypeExpr();
    if DoTypeFailed(AVarargs.ReadType) then
      Exit(False);
  end;
  Result := DoExpect(tkRParen, DoSpelled(')'));
end;

function TPCParser.DoParseNew(): TPCExpr;
var
  LRange: TSourceRange;
  LTypeRange: TSourceRange;
  LNew: TPCNew;
  LType: TPCCppType;
  LToken: TPCToken;
  LCount: Integer;
  LError: TPCErrorExpr;
begin
  // "new" cpp type name [ "(" [ arg list ] ")" | "[" expression "]" |
  // braced init ] (BNF.md sec 6): the NAME only - a fundamentals run or a cpp
  // qualified name with template args (tmType) - no cv, '*' or reference, so
  // 'new T * 2' never reads a pointer type. A PaskalCPP primitive is PR0027.
  // Never nil: 'new' is consumed; a failure is an error expression holding
  // the arguments parsed (PLAN-RECOVERY)
  LRange := DoStartRange();
  DoAdvance();
  LToken := DoCurrent();
  LTypeRange := DoStartRange();
  LType := FAst.NewNode<TPCCppType>();
  if DoIsCppFundamental(LToken.Kind) then
  begin
    while DoIsCppFundamental(DoCurrent().Kind) do
    begin
      LCount := Length(LType.Fundamentals);
      SetLength(LType.Fundamentals, LCount + 1);
      LType.Fundamentals[LCount] := DoCurrent().Kind;
      DoAdvance();
    end;
  end
  else if (LToken.Kind = tkIdentifier) or (LToken.Kind = tkColonColon) then
  begin
    if not DoParseNameParts(LType) then
      Exit(DoErrorExpr(LRange, []));
  end
  else if TPCVocabulary.IsBuiltinTypeWord(LToken.Kind) then
  begin
    DoError(LToken, PC_ERR_PAR_027, RSParNewPrimitive, [LToken.Spelling]);
    Exit(DoErrorExpr(LRange, []));
  end
  else
  begin
    DoError(LToken, PC_ERR_PAR_001, RSParExpected, [RSParShapeCppTypeName, DoTokenText(LToken)]);
    Exit(DoErrorExpr(LRange, []));
  end;
  DoFinishRange(LTypeRange);
  LType.Range := LTypeRange;
  LNew := FAst.NewNode<TPCNew>();
  LNew.TargetType := LType;
  LNew.InitKind := niNone;
  if DoCheck(tkLParen) then
  begin
    LNew.InitKind := niArgs;
    if not DoParseArgList(LNew.Args, tkRParen, DoSpelled(')')) then
    begin
      LError := DoErrorExpr(LRange, []);
      LError.Parts.AddRange(LNew.Args);
      Exit(LError);
    end;
  end
  else if DoCheck(tkLBracket) then
  begin
    LNew.InitKind := niArraySize;
    DoAdvance();
    LNew.SizeExpr := DoParseExpression(ecNormal);
    if DoFailed(LNew.SizeExpr) or (not DoExpect(tkRBracket, DoSpelled(']'))) then
      Exit(DoErrorExpr(LRange, [LNew.SizeExpr]));
  end
  else if DoCheck(tkLBrace) then
  begin
    LNew.InitKind := niBraced;
    if not DoParseArgList(LNew.Args, tkRBrace, DoSpelled('}')) then
    begin
      LError := DoErrorExpr(LRange, []);
      LError.Parts.AddRange(LNew.Args);
      Exit(LError);
    end;
  end;
  DoFinishRange(LRange);
  LNew.Range := LRange;
  Result := LNew;
end;

function TPCParser.DoParseDelete(): TPCExpr;
var
  LRange: TSourceRange;
  LDelete: TPCDelete;
begin
  // "delete" [ "[" "]" ] unary expr (BNF.md sec 6); the operand recursion
  // sits inside the nesting guard (delete delete ...). Never nil: 'delete' is
  // consumed; a failure is an error expression (PLAN-RECOVERY)
  LRange := DoStartRange();
  LDelete := FAst.NewNode<TPCDelete>();
  DoAdvance();
  if DoCheck(tkLBracket) and (DoPeek(1).Kind = tkRBracket) then
  begin
    DoAdvance();
    DoAdvance();
    LDelete.IsArray := True;
  end;
  if not DoEnterNested() then
    Exit(DoErrorExpr(LRange, []));
  try
    LDelete.Operand := DoParseUnary();
  finally
    DoLeaveNested();
  end;
  if DoFailed(LDelete.Operand) then
    Exit(DoErrorExpr(LRange, [LDelete.Operand]));
  DoFinishRange(LRange);
  LDelete.Range := LRange;
  Result := LDelete;
end;

function TPCParser.DoParseNamedCast(): TPCExpr;
var
  LRange: TSourceRange;
  LKeyword: TPCToken;
  LCast: TPCCast;
begin
  // cpp named cast "<" type ">" "(" expression ")" (BNF.md sec 6): the one
  // argument is always parsed in a type position (T6) by DoParseTypeExpr (a
  // C function-pointer type is a routine type, types.md Q1). Missing '<',
  // '<>' or a second argument: PR0043; '>' missing: PR0031. Never nil: the
  // keyword is consumed; a failure is an error expression (PLAN-RECOVERY)
  LRange := DoStartRange();
  LKeyword := DoCurrent();
  DoAdvance();
  if not DoCheck(tkLess) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_043, RSParNamedCastArgs,
      [LKeyword.Spelling, DoTokenText(DoCurrent())]);
    Exit(DoErrorExpr(LRange, []));
  end;
  DoAdvance();
  LCast := FAst.NewNode<TPCCast>();
  LCast.CastKind := DoNamedCastKind(LKeyword.Kind);
  LCast.TargetType := DoParseTypeExpr();
  if DoTypeFailed(LCast.TargetType) then
    Exit(DoErrorExpr(LRange, []));
  if DoCheck(tkComma) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_043, RSParNamedCastArgs,
      [LKeyword.Spelling, DoTokenText(DoCurrent())]);
    Exit(DoErrorExpr(LRange, []));
  end;
  if not DoSplitIfGreaterFamily() then
  begin
    DoReportArgsOpen(tmType);
    Exit(DoErrorExpr(LRange, []));
  end;
  DoAdvance();
  if not DoExpect(tkLParen, DoSpelled('(')) then
    Exit(DoErrorExpr(LRange, []));
  LCast.Operand := DoParseExpression(ecNormal);
  if DoFailed(LCast.Operand) or (not DoExpect(tkRParen, DoSpelled(')'))) then
    Exit(DoErrorExpr(LRange, [LCast.Operand]));
  DoFinishRange(LRange);
  LCast.Range := LRange;
  Result := LCast;
end;

function TPCParser.DoParseParenExpr(): TPCExpr;
var
  LRange: TSourceRange;
begin
  // "(" expression ")": no node for the parentheses (ast.md :284); inside
  // them ecNormal ('>' is a comparison: std::array<int, (3 > 2)>).
  // DoParseUnary tried the C-style cast first. Never nil: '(' is consumed,
  // a failure is an error expression from '(' on (PLAN-RECOVERY)
  LRange := DoStartRange();
  DoAdvance();
  Result := DoParseExpression(ecNormal);
  if DoFailed(Result) then
    Exit(DoErrorExpr(LRange, [Result]));
  if not DoExpect(tkRParen, DoSpelled(')')) then
    Result := DoErrorExpr(LRange, [Result]);
end;

function TPCParser.DoParseOpaqueGroup(): TPCExpr;
var
  LFirst: Integer;
  LLast: Integer;
  LKeyword: TPCToken;
  LOpen: TPCToken;
  LRange: TSourceRange;
begin
  // opaque group = ( sizeof | alignof | decltype | noexcept | typeid ) "("
  // { character } ")" (BNF.md sec 6): the keyword through the matching ')'
  // is copied verbatim (vkOpaqueGroup, in place), nothing inside is parsed.
  // C++'s 'sizeof LX' is PR0045. Postfix operators follow normally
  // (typeid(T).name()). Never nil: the keyword is consumed; a failure is an
  // error expression (PLAN-RECOVERY)
  LRange := DoStartRange();
  LFirst := DoCurrentIndex();
  LKeyword := DoCurrent();
  DoAdvance();
  if not DoCheck(tkLParen) then
  begin
    DoError(DoCurrent(), PC_ERR_PAR_045, RSParOpaqueParens,
      [LKeyword.Spelling, LKeyword.Spelling, DoTokenText(DoCurrent())]);
    Exit(DoErrorExpr(LRange, []));
  end;
  // F56: a '(' that never closes is reported at it (PR0063), not at EOF
  LOpen := DoCurrent();
  if not DoScanBalanced(LLast) then
  begin
    DoReportNeverClosed(LOpen);
    Exit(DoErrorExpr(LRange, []));
  end;
  Result := DoNewVerbatimExpr(LFirst, LLast, vkOpaqueGroup);
end;

function TPCParser.DoParseCppExpr(): TPCExpr;
var
  LRange: TSourceRange;
  LToken: TPCToken;
  LValue: string;
  LRuns: TArray<TPCSpellRun>;
  LNode: TPCVerbatimExpr;
begin
  // cpp expression = "cpp" "(" cstring ")" (BNF.md sec 10): ONE plain string
  // (raw allowed; never joined), decoded by the one cstring rule; Text = the
  // value, emitted in place. A non-raw value with a line break is PR0046 (it
  // would break the one-line-per-line mapping); a raw string's lines are its
  // source lines, and the lines that start inside it are InsideLines (R23).
  // Never nil: 'cpp' is consumed; a failure is an error expression
  // (PLAN-RECOVERY)
  LRange := DoStartRange();
  DoAdvance();
  if not DoExpect(tkLParen, DoSpelled('(')) then
    Exit(DoErrorExpr(LRange, []));
  LToken := DoCurrent();
  if LToken.Kind <> tkStringLiteral then
  begin
    DoError(LToken, PC_ERR_PAR_001, RSParExpected, [RSParShapeCString, DoTokenText(LToken)]);
    Exit(DoErrorExpr(LRange, []));
  end;
  if not DoIsPlainString(LToken) then
  begin
    DoError(LToken, PC_ERR_PAR_009, RSParBadString, [RSParNotPlainString]);
    Exit(DoErrorExpr(LRange, []));
  end;
  if not DoDecodeCString(LToken, True, LValue, LRuns) then
    Exit(DoErrorExpr(LRange, []));
  if (not LToken.IsRawString) and (LValue.Contains(#13) or LValue.Contains(#10)) then
  begin
    DoError(LToken, PC_ERR_PAR_046, RSParCppExprLineBreak, []);
    Exit(DoErrorExpr(LRange, []));
  end;
  LNode := FAst.NewNode<TPCVerbatimExpr>();
  LNode.Verbatim.Text := LValue;
  // Where each value byte came from: a C++ location inside the value maps
  // back to its character (TPCAst.TranslateLocation, P-STRPOS)
  LNode.Verbatim.ValueMap := DoValueMapOf(LToken, LValue, LRuns);
  LNode.Verbatim.VerbatimKind := vkCppExpr;
  LNode.Verbatim.EmitTarget := etInPlace;
  LNode.Verbatim.Range := LToken.Range;
  LNode.Verbatim.InsideLines := FRawStream.InsideLines(Int64(LToken.Range.StartByteOffset),
    Int64(LToken.Range.EndByteOffset));
  DoAdvance();
  if not DoExpect(tkRParen, DoSpelled(')')) then
    Exit(DoErrorExpr(LRange, []));
  DoFinishRange(LRange);
  LNode.Range := LRange;
  Result := LNode;
end;

function TPCParser.DoTryTemplateArgs(const APart: TPCNamePart;
  const AMode: TPCTemplateMode): Boolean;
var
  LAttempt: TPCAttempt;
  LKey: string;
  LArg: TPCTemplateArg;
  LOk: Boolean;
begin
  // The expression-side list attempt (tmQualified, tmMember; templates.md
  // "The list attempt"). Accepted when the list closes, the token after it
  // passes the follow test and nothing was reported (A2); otherwise
  // everything is restored (A1) and '<' is less-than. The attempt reads only
  // tokens, so a position that failed once in a mode fails again: the memo
  // skips it (A4). The args go straight into APart, cleared on failure
  LAttempt := DoSaveAttempt();
  LKey := DoTemplateFailKey(LAttempt, AMode);
  if FTemplateFails.ContainsKey(LKey) then
    Exit(False);
  if DoCheck(tkLessGreater) then
  begin
    // '<>' is one token: an empty list only before a token that cannot
    // continue a not-equal (A5, F3)
    FCursor.SplitCurrent();
    DoAdvance();
    DoAdvance();
    LOk := DoIsEmptyListFollow(DoCurrent().Kind);
  end
  else
  begin
    DoAdvance();
    LOk := True;
    if not DoSplitIfGreaterFamily() then
    begin
      while LOk do
      begin
        LArg := DoParseTemplateArg(AMode);
        if LArg = nil then
          LOk := False
        else
        begin
          APart.TemplateArgs.Add(LArg);
          if not DoMatch(tkComma) then
            Break;
        end;
      end;
      LOk := LOk and DoSplitIfGreaterFamily();
    end;
    if LOk then
    begin
      DoAdvance();
      LOk := DoIsTemplateFollow(DoCurrent());
    end;
  end;
  if LOk and DoAttemptClean(LAttempt) then
  begin
    APart.HasTemplateArgs := True;
    Exit(True);
  end;
  DoRestoreAttempt(LAttempt);
  APart.TemplateArgs.Clear();
  APart.HasTemplateArgs := False;
  FTemplateFails.AddOrSetValue(LKey, True);
  Result := False;
end;

class function TPCParser.DoTemplateFailKey(const AAttempt: TPCAttempt;
  const AMode: TPCTemplateMode): string;
begin
  // The memo key: the stream position (a split piece included) and the mode
  Result := IntToStr(AAttempt.Position.Index) + ':' + IntToStr(AAttempt.Position.Skip) + ':' +
    IntToStr(AAttempt.Position.PieceLen) + ':' + IntToStr(Ord(AMode));
end;

class function TPCParser.DoStartsOperandOnly(const AToken: TPCToken): Boolean;
begin
  // A token that can only START an operand (BNF.md sec 6, template bullet):
  // an identifier, a literal, a primitive type keyword, a keyword that
  // begins a primary, a prefix-only operator. Shared with the C-style cast
  // rule (DoTryCStyleCast)
  Result := (AToken.Category = tcPrimitive) or DoIsOneOf(AToken.Kind, [tkIdentifier,
    tkIntLiteral, tkFloatLiteral, tkStringLiteral, tkCharLiteral, tkKwTrue, tkKwFalse,
    tkKwNil, tkKwSelf, tkKwParent, tkKwThis, tkKwNullptr, tkKwNew, tkKwDelete,
    tkKwVarargs, tkKwPtr, tkKwCpp, tkKwStatic_cast, tkKwReinterpret_cast, tkKwConst_cast,
    tkKwDynamic_cast, tkKwSizeof, tkKwAlignof, tkKwDecltype, tkKwNoexcept, tkKwTypeid,
    tkKwNot, tkBang, tkTilde, tkKwAddress]);
end;

class function TPCParser.DoIsTemplateFollow(const AToken: TPCToken): Boolean;
begin
  // A closed list is accepted unless the next token can only start an
  // operand ([DECIDED] user 2026-10-06, Q-F): X < Y > Z is never a valid
  // comparison, so no valid line changes meaning
  Result := not DoStartsOperandOnly(AToken);
end;

class function TPCParser.DoIsEmptyListFollow(const AKind: TPCTokenKind): Boolean;
begin
  // After an empty list written as the one token '<>' (A5): only what cannot
  // continue a not-equal - a call, braced init, scope, a closer, ',' ';' -
  // and the '>' family closing an enclosing list (X<Y<std::less<>>> lexes
  // '<>' '>>', F3)
  Result := DoIsOneOf(AKind, [tkLParen, tkLBrace, tkColonColon, tkComma, tkRParen,
    tkSemicolon, tkRBracket, tkGreater, tkGreaterGreater, tkGreaterEqual,
    tkGreaterGreaterEqual]);
end;

class function TPCParser.DoInfixInfo(const AToken: TPCToken; const AContext: TPCExprContext;
  out ARow: TPCInfixRow): Boolean;
var
  LI: Integer;
begin
  // The binding-table row of an infix operator token. In a template
  // argument's top level (ecTemplateArg) the '>' family and '<>' close the
  // list instead (expr.md "Template-arg context")
  ARow := Default(TPCInfixRow);
  if (AContext = ecTemplateArg) and DoIsOneOf(AToken.Kind, [tkGreater, tkGreaterEqual,
    tkGreaterGreater, tkGreaterGreaterEqual, tkLessGreater]) then
    Exit(False);
  for LI := Low(PC_INFIX_ROWS) to High(PC_INFIX_ROWS) do
  begin
    if PC_INFIX_ROWS[LI].Kind = AToken.Kind then
    begin
      ARow := PC_INFIX_ROWS[LI];
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TPCParser.DoPrefixInfo(const AKind: TPCTokenKind; out AOp: TPCUnaryOp;
  out AHint: string): Boolean;
begin
  // The prefix operators (BNF.md sec 6, power 35). AHint <> '' = a C++ word
  // operator (PR0040) and the PaskalCPP symbol it spells
  AHint := '';
  AOp := uoLogNot;
  Result := True;
  if (AKind = tkKwNot) or (AKind = tkBang) then
    AOp := uoLogNot
  else if AKind = tkTilde then
    AOp := uoBitNot
  else if AKind = tkMinus then
    AOp := uoNegate
  else if AKind = tkPlus then
    AOp := uoPlus
  else if (AKind = tkAmp) or (AKind = tkKwAddress) then
    AOp := uoAddressOf
  else if AKind = tkStar then
    AOp := uoDeref
  else if AKind = tkPlusPlus then
    AOp := uoPreInc
  else if AKind = tkMinusMinus then
    AOp := uoPreDec
  else if AKind = tkKwCompl then
  begin
    AOp := uoBitNot;
    AHint := '~';
  end
  else if AKind = tkKwBitand then
  begin
    AOp := uoAddressOf;
    AHint := '&';
  end
  else
    Result := False;
end;

class function TPCParser.DoNamedCastKind(const AKind: TPCTokenKind): TPCCastKind;
begin
  if AKind = tkKwStatic_cast then
    Result := ckStatic
  else if AKind = tkKwReinterpret_cast then
    Result := ckReinterpret
  else if AKind = tkKwConst_cast then
    Result := ckConst
  else
    Result := ckDynamic;
end;

function TPCParser.DoNewVerbatimExpr(const AFirst: Integer; const ALast: Integer;
  const AKind: TPCVerbatimKind): TPCVerbatimExpr;
begin
  // The expression twin of DoNewVerbatim: whole tokens AFirst..ALast copied
  // by the one F1 walk (DoFillVerbatim), emitted in place
  Result := FAst.NewNode<TPCVerbatimExpr>();
  Result.Verbatim.VerbatimKind := AKind;
  Result.Verbatim.EmitTarget := etInPlace;
  DoFillVerbatim(AFirst, ALast, Result.Verbatim);
  Result.Range := Result.Verbatim.Range;
end;

function TPCParser.DoIsLambdaStart(): Boolean;
var
  LAttempt: TPCAttempt;
  LLast: Integer;
begin
  // cpp lambda (BNF.md sec 6 lambda bullet): '[' whose matching ']' is
  // followed by '(' or '{'; otherwise '[' is a set literal. A peek: the scan
  // runs inside the attempt pair and is always restored (it reports nothing)
  LAttempt := DoSaveAttempt();
  Result := DoScanBalanced(LLast) and (DoCheck(tkLParen) or DoCheck(tkLBrace));
  DoRestoreAttempt(LAttempt);
end;

function TPCParser.DoParseLambda(): TPCExpr;
var
  LFirst: Integer;
  LLast: Integer;
  LKind: TPCTokenKind;
  LOpen: TPCToken;
  LRange: TSourceRange;
begin
  // cpp lambda = "[" ... "]" [ "(" ... ")" ] [ specifiers, "->" type ] "{" ... "}"
  // (BNF.md sec 6): captured verbatim (vkLambda, in place), nothing inside
  // parsed (== = ^ in the body are C++). Between the head and the body the
  // walk takes specifiers (mutable, constexpr, noexcept(...), -> type,
  // [[...]]) with brackets balanced; ';', EOF or a depth-0 closer first is
  // PR0044. DoIsLambdaStart held. Never nil: the head is consumed; a failure
  // is an error expression (PLAN-RECOVERY)
  LRange := DoStartRange();
  LFirst := DoCurrentIndex();
  DoScanBalanced(LLast);
  while not DoCheck(tkLBrace) do
  begin
    LKind := DoCurrent().Kind;
    if DoIsOneOf(LKind, [tkSemicolon, tkEOF, tkRParen, tkRBracket, tkRBrace]) then
    begin
      DoError(DoCurrent(), PC_ERR_PAR_044, RSParLambdaBody, [DoTokenText(DoCurrent())]);
      Exit(DoErrorExpr(LRange, []));
    end;
    if DoIsOneOf(LKind, [tkLParen, tkLBracket]) then
    begin
      // F56: a group that never closes is reported at its opener (PR0063)
      LOpen := DoCurrent();
      if not DoScanBalanced(LLast) then
      begin
        DoReportNeverClosed(LOpen);
        Exit(DoErrorExpr(LRange, []));
      end;
    end
    else
      DoAdvance();
  end;
  LOpen := DoCurrent();
  if not DoScanBalanced(LLast) then
  begin
    DoReportNeverClosed(LOpen);
    Exit(DoErrorExpr(LRange, []));
  end;
  Result := DoNewVerbatimExpr(LFirst, LLast, vkLambda);
end;

function TPCParser.DoTryCStyleCast(out AResult: TPCExpr): Boolean;
var
  LRange: TSourceRange;
  LAttempt: TPCAttempt;
  LType: TPCTypeExpr;
  LCast: TPCCast;
  LOperand: TPCExpr;
begin
  // cpp cast = "(" cpp type ")" unary expr ([DECIDED] user Q-G, BNF.md sec 6),
  // decided by what is INSIDE the parentheses: an unmistakable type
  // (DoIsUnmistakableType) is always a cast, and no operand after it is
  // PR0047; a type that is only a name ((TFoo), (std::string)) is a cast only
  // before a token that can only start an operand, else the parentheses are
  // an expression ((f)(x), (a) - b, (x)++). False = not a cast, everything
  // restored; True = a cast, AResult an error expression after a reported
  // error (PLAN-RECOVERY)
  AResult := nil;
  LRange := DoStartRange();
  LAttempt := DoSaveAttempt();
  DoAdvance();
  LType := DoParseTypeExpr();
  if DoTypeFailed(LType) or (not DoCheck(tkRParen)) or (not DoAttemptClean(LAttempt)) then
  begin
    DoRestoreAttempt(LAttempt);
    Exit(False);
  end;
  DoAdvance();
  if DoIsUnmistakableType(LType) then
  begin
    if not StartsOperand(DoCurrent()) then
    begin
      DoError(DoCurrent(), PC_ERR_PAR_047, RSParCastOperand, [DoTokenText(DoCurrent())]);
      AResult := DoErrorExpr(LRange, []);
      Exit(True);
    end;
  end
  else if not DoStartsOperandOnly(DoCurrent()) then
  begin
    DoRestoreAttempt(LAttempt);
    Exit(False);
  end;
  if not DoEnterNested() then
  begin
    AResult := DoErrorExpr(LRange, []);
    Exit(True);
  end;
  try
    LOperand := DoParseUnary();
  finally
    DoLeaveNested();
  end;
  if DoFailed(LOperand) then
  begin
    AResult := DoErrorExpr(LRange, [LOperand]);
    Exit(True);
  end;
  LCast := FAst.NewNode<TPCCast>();
  LCast.CastKind := ckCStyle;
  LCast.TargetType := LType;
  LCast.Operand := LOperand;
  DoFinishRange(LRange);
  LCast.Range := LRange;
  AResult := LCast;
  Result := True;
end;

function TPCParser.DoTryTypeArgAt(const ACall: TPCCall; const AIndex: Integer): Boolean;
var
  LAttempt: TPCAttempt;
  LArgs: TArray<TPCExpr>;
  LArg: TPCExpr;
  LType: TPCTypeExpr;
  LI: Integer;
begin
  // The one type-argument attempt (BNF.md sec 7, parser.md "size(T)
  // argument", prereq-b\varargs-forms.md D-R1): current '('. AIndex
  // expression arguments, each followed by ',', then a type: when it is
  // unmistakably a type and closes the call cleanly it is the TypeArg at
  // AIndex ('size(int64)', 'LCopy.next(ptr to char)', 'LCopy.get(0,
  // string)'); otherwise everything is restored and the arguments parse as
  // expressions ('size(TPoint)' is Args[0], SEM requires it to name a type;
  // 'size(int32(x))' is a builtin cast; 'R.get(0, x)'). True = the
  // expression arguments, TypeArg and TypeArgIndex set, ')' consumed
  LAttempt := DoSaveAttempt();
  DoAdvance();
  SetLength(LArgs, AIndex);
  for LI := 0 to AIndex - 1 do
  begin
    LArg := DoParseExpression(ecNormal);
    if DoFailed(LArg) or (not DoMatch(tkComma)) then
    begin
      DoRestoreAttempt(LAttempt);
      Exit(False);
    end;
    LArgs[LI] := LArg;
  end;
  LType := DoParseTypeExpr();
  if (not DoTypeFailed(LType)) and DoIsUnmistakableType(LType) and DoCheck(tkRParen) and
    DoAttemptClean(LAttempt) then
  begin
    for LArg in LArgs do
      ACall.Args.Add(LArg);
    ACall.TypeArg := LType;
    ACall.TypeArgIndex := AIndex;
    DoAdvance();
    Exit(True);
  end;
  DoRestoreAttempt(LAttempt);
  Result := False;
end;

class function TPCParser.StartsOperand(const AToken: TPCToken): Boolean;
begin
  // Every token DoParseUnary can begin with: the operand-only tokens, the
  // dual operators and bracket starts, the prefix C++ words (PR0040)
  Result := DoStartsOperandOnly(AToken) or DoIsOneOf(AToken.Kind, [tkPlus, tkMinus, tkStar,
    tkAmp, tkPlusPlus, tkMinusMinus, tkLParen, tkLBracket, tkLBrace, tkColonColon,
    tkKwCompl, tkKwBitand]);
end;

class function TPCParser.DoTypeArgSlot(const ACallee: TPCExpr; out AIndex: Integer): Boolean;
var
  LName: TPCName;
  LMember: TPCMember;
begin
  // A call with a slot whose argument may be a type (BNF.md sec 7,
  // varargs-forms.md form 3), AIndex = that slot. The intrinsic size: a
  // one-part unqualified name spelled PC_PAR_SIZE_NAME without template args
  // (a local 'size' shadows it in SEM; the parse is the same) -> 0. A member
  // spelled next (0) or get (1) without template args, after '.' or '->':
  // the parser cannot know the receiver's type, SEM checks it is varargs
  // (calls.md F-R2)
  AIndex := 0;
  if ACallee is TPCName then
  begin
    LName := TPCName(ACallee);
    Result := (not LName.HasLeadingScope) and (LName.Parts.Count = 1) and
      (LName.Parts[0].PartText = PC_PAR_SIZE_NAME) and (not LName.Parts[0].HasTemplateArgs);
    Exit;
  end;
  if not (ACallee is TPCMember) then
    Exit(False);
  LMember := TPCMember(ACallee);
  if LMember.Member.HasTemplateArgs then
    Exit(False);
  if LMember.Member.PartText = PC_VARARGS_WORDS[vaNext] then
    Exit(True);
  if LMember.Member.PartText = PC_VARARGS_WORDS[vaGet] then
  begin
    AIndex := 1;
    Exit(True);
  end;
  Result := False;
end;

end.
