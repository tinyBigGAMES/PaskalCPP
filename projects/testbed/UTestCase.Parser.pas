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
  UTestCase.Parser - Parser atom tests (PARSER-CORE-A, CORE-B, PARSER-EXPR-A, -B, -C)

  TTestCase suite for TPCParser / ParseModuleFile (PaskalCPP.Parser): header,
  build-directive prologue, module paths, import clause and identity, module
  end, ranges (CORE-A); C++ spans, F1 blanking, inside lines, # lines, cpp
  placement, cppstart blocks, sections, body, test blocks, recovery (CORE-B).
  Declarations and types (PARSER-EXPR-A): fixtures in tests\probe\par\expr, written
  by scripts\zb_pxa\gen_fixtures.py (pxa*).
  Expressions and template-argument attempts (PARSER-EXPR-B): pxb* fixtures,
  written by scripts\zb_pxb\gen_fixtures.py.
  Verbatim expression forms, C-style cast, size(T) (PARSER-EXPR-C): pxc* fixtures,
  written by scripts\zb_pxc\gen_fixtures.py.
  Fixtures are real files in tests\probe\par\core, written with exact bytes
  by scripts\zb_pa\gen_fixtures.py (pa*) and scripts\zb_pb\gen_fixtures.py
  (pb*), never an editor.

  Dependencies: StdApp.TestCase, StdApp.Base, StdApp.Utils, StdApp.Resources,
    PaskalCPP.Common, PaskalCPP.Lexer, PaskalCPP.Conditionals, PaskalCPP.AST,
    PaskalCPP.Parser, UTestFrontend
===============================================================================}

unit UTestCase.Parser;

interface

uses
  StdApp.TestCase,
  PaskalCPP.AST;

type

  { TPCParserTests }
  TPCParserTests = class(TTestCase)
  private
    // One test per concern; Create registers each under its CLI name
    procedure DoTestHeaderKinds();
    procedure DoTestHeaderErrors();
    procedure DoTestSemicolonAt();
    procedure DoTestPrologueShapes();
    procedure DoTestPrologueErrors();
    procedure DoTestDirectivePlace();
    procedure DoTestTarget();
    procedure DoTestImport();
    procedure DoTestImportGraph();
    procedure DoTestImportErrors();
    procedure DoTestModulePaths();
    procedure DoTestIdentity();
    procedure DoTestModuleEnd();
    procedure DoTestRanges();
    procedure DoTestSpans();
    procedure DoTestPlacement();
    procedure DoTestCppBlock();
    procedure DoTestCppJumps();
    procedure DoTestCppErrors();
    procedure DoTestDigraphs();
    procedure DoTestSections();
    procedure DoTestSectionErrors();
    procedure DoTestBody();
    procedure DoTestTestBlocks();
    procedure DoTestRecovery();
    procedure DoTestRecoveryNodes();
    procedure DoTestRecoveryRows();
    procedure DoTestOperandStarts();
    procedure DoTestF1();
    procedure DoTestInsideLines();
    procedure DoTestPaskalTypes();
    procedure DoTestCppTypes();
    procedure DoTestTemplateArgs();
    procedure DoTestTypeDefs();
    procedure DoTestRoutineTypePositions();
    procedure DoTestDecls();
    procedure DoTestDeclErrors();
    procedure DoTestDeclRecovery();
    procedure DoTestExprPrecedence();
    procedure DoTestExprPostfix();
    procedure DoTestExprPrimary();
    procedure DoTestExprTemplateArgs();
    procedure DoTestExprStrings();
    procedure DoTestExprStringValues();
    procedure DoTestExprStringPositions();
    procedure DoTestExprLiteralFacts();
    procedure DoTestExprCharValues();
    procedure DoTestExprErrors();
    procedure DoTestExprRecovery();
    procedure DoTestVerbatimLambda();
    procedure DoTestVerbatimOpaque();
    procedure DoTestVerbatimCpp();
    procedure DoTestCStyleCast();
    procedure DoTestSizeArg();
    procedure DoTestVarargsForms();
    procedure DoTestVarargsErrors();
    procedure DoTestVerbatimErrors();
    procedure DoTestStmtSimple();
    procedure DoTestStmtFlow();
    procedure DoTestStmtMatch();
    procedure DoTestStmtGuard();
    procedure DoTestStmtBodyForms();
    procedure DoTestStmtTestBody();
    procedure DoTestStmtErrors();
    procedure DoTestStmtRecovery();
    procedure DoTestStmtRanges();
    procedure DoTestDeclModule();
    procedure DoTestKeywordRanges();
    procedure DoTestNameRanges();
    procedure DoTestDocComments();
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

// A recovery row's tree as one line (PLAN-RECOVERY A11, scripts\zb_ed\gen_recovery.py
// states the format): statements, members, tests, params, match arms, choice
// values, error expressions and every node marked recovered, each as its kind
// name, ' ' + its name (declaration, field, param, choice value), its part count
// (error expression), '!' when marked, then its printed descendants in '(' ')';
// ANode's printed descendants joined by ','
function DoRecoveryOutline(const ANode: TPCNode): string;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.TypInfo,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.Common,
  PaskalCPP.Lexer,
  PaskalCPP.TokenStream,
  PaskalCPP.Conditionals,
  PaskalCPP.Parser,
  UTestFrontend;

type

  { TPCCodeCase }
  // One fixture and the codes its parse reports
  TPCCodeCase = record
    FileName: string;
    Codes: string;
  end;

  { TPCStrPosCase }
  // One literal of a P-STRPOS fixture: the module declaration that holds it and
  // every part's full value map as the dump prints it ('' = no part has one)
  TPCStrPosCase = record
    FileName: string;
    DeclIndex: Integer;
    Maps: string;
  end;

const
  { PC_TEST_CRLF }
  PC_TEST_CRLF = #13#10;
  { PC_TEST_DECL_ERRORS }
  // One diagnostic per fixture (PARSER-EXPR-A step 13)
  PC_TEST_DECL_ERRORS: array[0..18] of TPCCodeCase = (
    (FileName: 'pxa10_exported.pcpp'; Codes: PC_ERR_PAR_024),
    (FileName: 'pxa30_exportlocal.pcpp'; Codes: PC_ERR_PAR_057),
    (FileName: 'pxa11_mblocks.pcpp'; Codes: PC_ERR_PAR_025),
    (FileName: 'pxa12_tblocks.pcpp'; Codes: PC_ERR_PAR_025),
    (FileName: 'pxa13_declare.pcpp'; Codes: PC_ERR_PAR_026),
    (FileName: 'pxa14_primsuffix.pcpp'; Codes: PC_ERR_PAR_027),
    (FileName: 'pxa15_qualsuffix.pcpp'; Codes: PC_ERR_PAR_028),
    (FileName: 'pxa16_cv.pcpp'; Codes: PC_ERR_PAR_029),
    (FileName: 'pxa17_ref.pcpp'; Codes: PC_ERR_PAR_030),
    (FileName: 'pxa18_targsopen.pcpp'; Codes: PC_ERR_PAR_031),
    (FileName: 'pxa19_prefix.pcpp'; Codes: PC_ERR_PAR_032),
    (FileName: 'pxa20_objpacked.pcpp'; Codes: PC_ERR_PAR_033),
    (FileName: 'pxa21_member.pcpp'; Codes: PC_ERR_PAR_034),
    (FileName: 'pxa22_choices.pcpp'; Codes: PC_ERR_PAR_035),
    (FileName: 'pxa23_elab.pcpp'; Codes: PC_ERR_PAR_036),
    (FileName: 'pxa24_decltype.pcpp'; Codes: PC_ERR_PAR_037),
    (FileName: 'pxa28_libfile.pcpp'; Codes: PC_ERR_PAR_055),
    (FileName: 'pxa29_extfile.pcpp'; Codes: PC_ERR_PAR_055),
    // PLAN-RECORDS M6: a routine-typed field takes no bitfield width
    (FileName: 'pxa32_rtypewidth.pcpp'; Codes: PC_ERR_PAR_001)
  );

  { PC_TEST_LIB_NAMES }
  // TPCLibraryName.IsName: a library NAME (BNF.md sec 2, sem\decls.md Q25a)
  PC_TEST_LIB_NAMES: array[0..5] of string = ('m', 'user32', 'c', 'libd', 'z.1', 'SDL2-2.0');
  { PC_TEST_LIB_FILES }
  // Not names: a file, a path, blank or empty
  PC_TEST_LIB_FILES: array[0..8] of string = ('', 'libm.a', 'user32.LIB', 'libfoo.so',
    'x.dll', 'lib/m', 'C:m', 'my lib', 'a\b');

  { PC_TEST_EXPR_ERRORS }
  // One diagnostic per fixture (PARSER-EXPR-B step 11)
  PC_TEST_EXPR_ERRORS: array[0..17] of TPCCodeCase = (
    (FileName: 'pxb10_chain.pcpp'; Codes: PC_ERR_PAR_038),
    (FileName: 'pxb11_eqeq.pcpp'; Codes: PC_ERR_PAR_039),
    (FileName: 'pxb12_noteq.pcpp'; Codes: PC_ERR_PAR_039),
    (FileName: 'pxb13_bitand.pcpp'; Codes: PC_ERR_PAR_040),
    (FileName: 'pxb14_xoreq.pcpp'; Codes: PC_ERR_PAR_040),
    (FileName: 'pxb15_compl.pcpp'; Codes: PC_ERR_PAR_040),
    (FileName: 'pxb16_castargs.pcpp'; Codes: PC_ERR_PAR_041),
    (FileName: 'pxb17_namednolt.pcpp'; Codes: PC_ERR_PAR_043),
    (FileName: 'pxb18_namedtwo.pcpp'; Codes: PC_ERR_PAR_043),
    (FileName: 'pxb19_noexpr.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pxb20_strwarn.pcpp'; Codes: PC_ERR_PAR_021),
    (FileName: 'pxb21_newprim.pcpp'; Codes: PC_ERR_PAR_027),
    (FileName: 'pxb22_eof.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pxb24_depthbad.pcpp'; Codes: PC_ERR_PAR_042),
    (FileName: 'pxb25_typedepth.pcpp'; Codes: PC_ERR_PAR_042),
    (FileName: 'pxb27_attemptwarn.pcpp'; Codes: PC_ERR_PAR_021),
    (FileName: 'pxb28_attempteof.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pxb29_memo.pcpp'; Codes: PC_ERR_PAR_038)
  );

  { PC_TEST_EXPR_PREC }
  // pxb01 items A..P, as DoExprText prints them
  PC_TEST_EXPR_PREC: array[0..15] of string = (
    '(a boAdd (b boMul c))',
    '((uoNegate a) boMul b)',
    '((FLAG_A boBitOr FLAG_B) boEq LMask)',
    '(a boLogOr (b boLogAnd c))',
    '((x boShl 2) boAdd 1)',
    '(a aoAssign (b aoAssign c))',
    '(c ? x : (d ? y : z))',
    '((a boSub b) boSub c)',
    '((uoLogNot a) boEq b)',
    '((x boBitAnd 1) boEq 0)',
    '(a boIn b)',
    '(a boThreeWay b)',
    '((a boMod b) boIntDiv c)',
    '(a aoAddAssign b)',
    '((a boBitXor b) boLogOr c)',
    '((x boShl 1) boAdd 2)'
  );

  { PC_TEST_EXPR_POSTFIX }
  // pxb02 items A..L
  PC_TEST_EXPR_POSTFIX: array[0..11] of string = (
    '(uoDeref p).x[1].f(2)',
    'LV.push_back({1, 2})',
    '(uoPostInc LX)',
    '(uoAddressOf x)',
    'p->next->value',
    '(uoPreDec LX)',
    '(uoDeref (uoDeref LPP))',
    'f()(1)',
    '(uoAddressOf LBuf[0])',
    'T{1, 2}',
    '(uoLogNot (uoLogNot LB))',
    '(uoNegate LA.B)'
  );

  { PC_TEST_EXPR_PRIMARY }
  // pxb03 items A..Z
  PC_TEST_EXPR_PRIMARY: array[0..25] of string = (
    '42',
    '1.5',
    '''x''',
    'true',
    'nil',
    'skSelf',
    'skThis',
    'skNullptr',
    '::g_count',
    'std::ios::end',
    '((a boAdd b) boMul c)',
    '(ckBuiltin B:tkKwInt32 LD)',
    '(ckPointer P:B:tkKwChar LP)',
    '((ckStatic N:int32_t LD) boLess 10)',
    'varargs.count',
    'varargs.next(B:tkKwInt32)',
    'varargs',
    'new C:TFoo(1, 2)',
    'new C:tkKwInt[n]',
    'new C:std::vector{1, 2}',
    'delete[] p',
    'delete p',
    '[1, 3..5, LX]',
    'TPoint(x: 1, y: 2)',
    'Geo.TPoint(x: 1)',
    'P(x)'
  );

  { PC_TEST_EXPR_TARGS }
  // pxb04 items A..P
  PC_TEST_EXPR_TARGS: array[0..15] of string = (
    '(std::numeric_limits<C:tkKwInt>::max() boSub 1)',
    'std::max<C:tkKwInt>(LA, LB)',
    'std::vector<C:tkKwInt>{1, 2}',
    'std::less<>()',
    '(std::ios::beg boNotEq LDir)',
    '(std::ios::beg boLess LSeekDir)',
    'LV.get<N:int32_t>()',
    '((LR.A boLess LB) boLogAnd (LR.C boGreater LD))',
    'std::array<C:tkKwInt, (3 boGreater 2)>{}',
    '(std::numbers::pi_v<B:tkKwFloat64> boMul LR)',
    '(std::is_same_v<T, C:tkKwInt> boLogAnd LOk)',
    '(std::ios::beg boNotEq (uoNegate 1))',
    'std::vector<int32_t>::size_type(0)',
    'std::map<std::string, C:std::vector>::npos',
    '::X<C:std::less>::v',
    'std::function<"void(std::vector<int>)">::x'
  );

  { PC_TEST_VERBATIM_ERRORS }
  // One diagnostic per fixture (PARSER-EXPR-C step 9)
  PC_TEST_VERBATIM_ERRORS: array[0..7] of TPCCodeCase = (
    (FileName: 'pxc10_lambdanobody.pcpp'; Codes: PC_ERR_PAR_044),
    (FileName: 'pxc11_sizeofnoparen.pcpp'; Codes: PC_ERR_PAR_045),
    (FileName: 'pxc12_cppnewline.pcpp'; Codes: PC_ERR_PAR_046),
    (FileName: 'pxc13_castop.pcpp'; Codes: PC_ERR_PAR_047),
    (FileName: 'pxc14_cppprefixed.pcpp'; Codes: PC_ERR_PAR_009),
    (FileName: 'pxc15_cppwarn.pcpp'; Codes: PC_ERR_PAR_021),
    (FileName: 'pxc16_cpptwo.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pxc17_cppnostr.pcpp'; Codes: PC_ERR_PAR_001)
  );

  { PC_TEST_LAMBDA }
  // pxc01 items A..F, as DoExprText prints them
  PC_TEST_LAMBDA: array[0..5] of string = (
    'vkLambda"[](int x) { return x * 2; }"',
    'vkLambda"[&]{ return LN == 1; }"',
    'vkLambda"[=, &LT](auto& v) mutable -> int { return v; }"',
    'vkLambda"[&](int x) { return x; }"(5)',
    '[1, 2]',
    'LA[1]'
  );

  { PC_TEST_OPAQUE }
  // pxc02 items A..F
  PC_TEST_OPAQUE: array[0..5] of string = (
    'vkOpaqueGroup"sizeof(LX)"',
    'vkOpaqueGroup"alignof(std::max_align_t)"',
    'vkOpaqueGroup"typeid(T)".name()',
    'vkOpaqueGroup"noexcept(f())"',
    'vkOpaqueGroup"decltype(LX)"',
    '(vkOpaqueGroup"sizeof(LX)" boMul 2)'
  );

  { PC_TEST_CPPEXPR }
  // pxc03 items A..C
  PC_TEST_CPPEXPR: array[0..2] of string = (
    'vkCppExpr"a + b"',
    'vkCppExpr"x == y"',
    '(vkCppExpr"LV.size()" boAdd 1)'
  );

  { PC_TEST_CSTYLE }
  // pxc04 items A..N
  PC_TEST_CSTYLE: array[0..13] of string = (
    '(ckCStyle N:int32_t LD)',
    '(ckCStyle C:tkKwChar (uoAddressOf LB[0]))',
    'f(x)',
    '(a boSub b)',
    '(uoPostInc x)',
    '(ckCStyle N:TFoo LX)',
    '(ckCStyle C:tkKwInt (uoNegate 1))',
    '(ckCStyle C:tkKwDouble (uoNegate LX))',
    '(ckCStyle C:tkKwChar (uoDeref LPP))',
    '(ckCStyle C:tkKwInt (uoPreInc LI))',
    '(ckCStyle B:tkKwInt32 LX)',
    '(ckBuiltin B:tkKwInt32 LX)',
    '((a boAdd b) boMul c)',
    '(ckCStyle N:Geo.TPoint LP)'
  );

  { PC_TEST_SIZE }
  // pxc05 items A..G
  PC_TEST_SIZE: array[0..6] of string = (
    'size(B:tkKwInt64)',
    'size(P:B:tkKwChar)',
    'size(C:std::vector)',
    'size(TPoint)',
    'size((ckBuiltin B:tkKwInt32 x))',
    'std::size(LV)',
    'size(std::string)'
  );

  { PC_TEST_VARARGS }
  // pva01_forms items, as DoExprText prints them (gen_varargs.py)
  PC_TEST_VARARGS: array[0..24] of string = (
    'nil',
    'varargs.get(0, B:tkKwInt32)',
    'varargs.get((i boAdd 1), B:tkKwString)',
    'varargs.reset()',
    'varargs.copy()',
    'varargs.reset',
    'varargs.foo(1)',
    'varargs.next(B:tkKwInt32)',
    'L.next(B:tkKwInt32)',
    'L.next(P:nil)',
    'L.next(P:B:tkKwChar)',
    'L.next(TPoint)',
    'L.next(C:std::vector)',
    'L.get(0, B:tkKwString)',
    'L.get((i boAdd 1), ?)',
    'L.count',
    'L.reset()',
    'L.copy()',
    'X.get(0, y)',
    'L.next((ckBuiltin B:tkKwInt32 x))',
    'size(B:tkKwInt64)',
    'it.next(5)',
    'p->get()',
    'obj.get<N:int32_t>(t)',
    'LP->next(B:tkKwInt32)'
  );
  { PC_TEST_VA_TYPE }
  PC_TEST_VA_TYPE = 0;
  { PC_TEST_VA_GET }
  PC_TEST_VA_GET = 2;
  { PC_TEST_VA_NAMEARG }
  PC_TEST_VA_NAMEARG = 11;
  { PC_TEST_VA_LOCALGET }
  PC_TEST_VA_LOCALGET = 13;
  { PC_TEST_VA_ARRAYARG }
  PC_TEST_VA_ARRAYARG = 14;
  { PC_TEST_VA_SIZE }
  PC_TEST_VA_SIZE = 20;
  { PC_TEST_VARARGS_ERRORS }
  // One diagnostic per fixture (PREREQ-B R4g4c, gen_varargs.py)
  PC_TEST_VARARGS_ERRORS: array[0..8] of TPCCodeCase = (
    (FileName: 'pva10_ptrsuffix.pcpp'; Codes: PC_ERR_PAR_027),
    (FileName: 'pva11_refsuffix.pcpp'; Codes: PC_ERR_PAR_027),
    (FileName: 'pva12_cvlead.pcpp'; Codes: PC_ERR_PAR_027),
    (FileName: 'pva13_new.pcpp'; Codes: PC_ERR_PAR_027),
    (FileName: 'pva14_getcomma.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pva15_gettype.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pva16_getparen.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pva17_resetarg.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pva18_copyarg.pcpp'; Codes: PC_ERR_PAR_001)
  );

  { PC_TEST_STMT_DIGRAPHS }
  // pdg02_body: one string per body statement (DoStmtText)
  PC_TEST_STMT_DIGRAPHS: array[0..3] of string = (
    'vkPreproc etInPlace',
    '(LX aoAssign LA[0])',
    '(LB aoAssign {1, 2})',
    '(LC aoAssign LS[LI][1])'
  );

  { PC_TEST_STMT_SIMPLE }
  // pst01_simple: one string per body statement (DoStmtText)
  PC_TEST_STMT_SIMPLE: array[0..7] of string = (
    '(LX aoAssign 1)',
    'Foo(LX, 2)',
    '(uoPostInc LX)',
    'return',
    'return (LX boAdd 1)',
    'leave',
    'skip',
    'begin (LX aoAssign 2); end'
  );

  { PC_TEST_STMT_FLOW }
  PC_TEST_STMT_FLOW: array[0..5] of string = (
    'if (LX boLess 1) then Foo(); end',
    'if (LX boLess 1) then Foo(); else Bar(); Baz(); end',
    'while (LX boGreater 0) do (LX aoAssign (LX boSub 1)); end',
    'for LI := 1 to 10 do Foo(LI); end',
    'for LI := 10 downto 1 do end',
    'repeat (LX aoAssign (LX boAdd 1)); until (LX boGreaterEq 5)'
  );

  { PC_TEST_STMT_MATCH }
  // The third and fourth: declaration blocks directly in arms (user 2026-10-06, Q1)
  PC_TEST_STMT_MATCH: array[0..3] of string = (
    'match LX of [1, 2] Foo(); [3..5] Bar(); Baz(); [cRed] Qux(); else Foo(); end',
    'match LX of end',
    'match LX of [1] var LY; [cRed] Foo(); [2] var LZ; (LZ aoAssign LX); end',
    'match LX of [1] var LY; var LW; [2] type TA; type TB; end'
  );

  { PC_TEST_STMT_GUARD }
  PC_TEST_STMT_GUARD: array[0..2] of string = (
    'guard Foo(); except Bar(); end',
    'guard Foo(); finally Bar(); end',
    'guard Foo(); except Bar(); finally Baz(); end'
  );

  { PC_TEST_STMT_BODY_FORMS }
  // Declaration blocks, # line, cppstart source, cpp(...), directives (user
  // 2026-10-06, Q2), C++ expressions
  PC_TEST_STMT_BODY_FORMS: array[0..10] of string = (
    'var LX',
    'const cN',
    'type TP',
    'vkPreproc etInPlace',
    'vkCppBlock etInPlace',
    'vkCppExpr"b()"',
    '@breakpoint/0',
    '@message/2',
    'LV.push_back(1)',
    'delete LP',
    'if (LX boGreater 0) then @breakpoint/0; end'
  );

  { PC_TEST_STMT_ERRORS }
  // One diagnostic per fixture, nothing cascades (PARSER-STMT)
  PC_TEST_STMT_ERRORS: array[0..14] of TPCCodeCase = (
    (FileName: 'pst10_eqstmt.pcpp'; Codes: PC_ERR_PAR_048),
    (FileName: 'pst11_break.pcpp'; Codes: PC_ERR_PAR_049),
    (FileName: 'pst12_switch.pcpp'; Codes: PC_ERR_PAR_049),
    (FileName: 'pst13_trycatch.pcpp'; Codes: PC_ERR_PAR_049),
    (FileName: 'pst14_place.pcpp'; Codes: PC_ERR_PAR_050),
    (FileName: 'pst15_cppheader.pcpp'; Codes: PC_ERR_PAR_051),
    (FileName: 'pst16_guardempty.pcpp'; Codes: PC_ERR_PAR_052),
    (FileName: 'pst17_lonesemi.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pst18_stray.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pst19_nosemi.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pst20_trunc.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pst21_nocond.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pst22_forname.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pst23_armcolon.pcpp'; Codes: PC_ERR_PAR_001),
    (FileName: 'pst24_directive.pcpp'; Codes: PC_ERR_PAR_008)
  );

  { PC_TEST_STRPOS_FILES }
  // One P-STRPOS fixture and the codes its parse reports (scripts\zb_sem\pb\gen_strpos.py)
  PC_TEST_STRPOS_FILES: array[0..5] of TPCCodeCase = (
    (FileName: 'ps01_map.pcpp'; Codes: ''),
    (FileName: 'ps02_map_lf.pcpp'; Codes: ''),
    (FileName: 'ps03_wsplice.pcpp'; Codes: PC_WARN_LEX_001),
    (FileName: 'ps04_wsplice_lf.pcpp'; Codes: PC_WARN_LEX_001),
    (FileName: 'ps05_status.pcpp'; Codes: PC_ERR_PAR_021 + ',' + PC_ERR_PAR_009),
    (FileName: 'ps06_rawsplice.pcpp'; Codes: '')
  );

  { PC_TEST_STRPOS }
  // Every literal of the P-STRPOS fixtures with the full value map of each part
  // (the mapN dump text; scripts\zb_sem\pb\gen_strpos.py, steps-parser.md P10)
  PC_TEST_STRPOS: array[0..54] of TPCStrPosCase = (
    (FileName: 'ps01_map.pcpp'; DeclIndex: 0; Maps: 'map0=[c0@3:15]'),  // plain
    (FileName: 'ps01_map.pcpp'; DeclIndex: 1; Maps: 'map0=[e0@4:15 c1@4:17]'),  // esc_simple
    (FileName: 'ps01_map.pcpp'; DeclIndex: 2; Maps: 'map0=[e0@5:15 c1@5:17]'),  // esc_gnu_e
    (FileName: 'ps01_map.pcpp'; DeclIndex: 3; Maps: 'map0=[e0@6:15 c1@6:19]'),  // esc_hex
    (FileName: 'ps01_map.pcpp'; DeclIndex: 4; Maps: 'map0=[e0@7:15 c1@7:19]'),  // esc_oct
    (FileName: 'ps01_map.pcpp'; DeclIndex: 5; Maps: 'map0=[e0@8:15 c2@8:21]'),  // esc_u
    (FileName: 'ps01_map.pcpp'; DeclIndex: 6; Maps: 'map0=[e0@9:15 c4@9:25]'),  // esc_U
    (FileName: 'ps01_map.pcpp'; DeclIndex: 7; Maps: 'map0=[e0@10:15 c2@10:50]'),  // esc_N
    (FileName: 'ps01_map.pcpp'; DeclIndex: 8; Maps: 'map0=[e0@11:15 c1@11:21]'),  // esc_xdelim
    (FileName: 'ps01_map.pcpp'; DeclIndex: 9; Maps: 'map0=[e0@12:15 c1@12:22]'),  // esc_odelim
    (FileName: 'ps01_map.pcpp'; DeclIndex: 10; Maps: 'map0=[e0@13:15 c2@13:21]'),  // esc_udelim
    (FileName: 'ps01_map.pcpp'; DeclIndex: 11; Maps: 'map0=[e0@14:15 c1@14:19]'),  // pct_hex
    (FileName: 'ps01_map.pcpp'; DeclIndex: 12; Maps: 'map0=[e0@15:15 c1@15:19]'),  // pct_oct
    (FileName: 'ps01_map.pcpp'; DeclIndex: 13; Maps: 'map0=[e0@16:15 c1@16:21]'),  // pct_u
    (FileName: 'ps01_map.pcpp'; DeclIndex: 14; Maps: 'map0=[c0@17:15 e1@17:16]'),  // y_hex
    (FileName: 'ps01_map.pcpp'; DeclIndex: 15; Maps: 'map0=[c0@18:15 e1@18:16]'),  // y_hex_splice
    (FileName: 'ps01_map.pcpp'; DeclIndex: 16; Maps: 'map0=[c0@20:15 e1@20:16]'),  // y_u
    (FileName: 'ps01_map.pcpp'; DeclIndex: 17; Maps: 'map0=[c0@21:17 c1@21:19 c2@22:1] map1=[c0@22:6]'),  // y_after_crlf_raw
    (FileName: 'ps01_map.pcpp'; DeclIndex: 18; Maps: 'map0=[c0@23:15]'),  // utf8_2
    (FileName: 'ps01_map.pcpp'; DeclIndex: 19; Maps: 'map0=[c0@24:15]'),  // utf8_3
    (FileName: 'ps01_map.pcpp'; DeclIndex: 20; Maps: 'map0=[c0@25:15]'),  // utf8_4
    (FileName: 'ps01_map.pcpp'; DeclIndex: 21; Maps: 'map0=[c0@26:15]'),  // tab
    (FileName: 'ps01_map.pcpp'; DeclIndex: 22; Maps: 'map0=[c0@27:15 c2@28:1]'),  // splice_before
    (FileName: 'ps01_map.pcpp'; DeclIndex: 23; Maps: 'map0=[c0@29:15 c1@30:1]'),  // splice_between
    (FileName: 'ps01_map.pcpp'; DeclIndex: 24; Maps: 'map0=[e0@31:15 c1@32:2]'),  // splice_in_esc
    (FileName: 'ps01_map.pcpp'; DeclIndex: 25; Maps: 'map0=[e0@33:15 c1@34:2]'),  // splice_in_pct_esc
    (FileName: 'ps01_map.pcpp'; DeclIndex: 26; Maps: 'map0=[c0@35:15 c1@37:1]'),  // splice_two
    (FileName: 'ps01_map.pcpp'; DeclIndex: 27; Maps: 'map0=[c0@38:15] map1=[c0@38:20]'),  // joined
    (FileName: 'ps01_map.pcpp'; DeclIndex: 28; Maps: 'map0=[c0@39:15] map1=[c0@40:6]'),  // joined_lines
    (FileName: 'ps01_map.pcpp'; DeclIndex: 29; Maps: 'map0=[c0@41:15] map1=[c0@41:21]'),  // joined_split
    (FileName: 'ps01_map.pcpp'; DeclIndex: 30; Maps: 'map0=[e0@42:15] map1=[c0@42:22]'),  // joined_esc
    (FileName: 'ps01_map.pcpp'; DeclIndex: 31; Maps: 'map0=[c0@43:17]'),  // raw
    (FileName: 'ps01_map.pcpp'; DeclIndex: 32; Maps: 'map0=[c0@44:17 c2@44:20 c3@45:1]'),  // raw_lines
    (FileName: 'ps01_map.pcpp'; DeclIndex: 33; Maps: 'map0=[c0@46:18]'),  // raw_delim
    (FileName: 'ps01_map.pcpp'; DeclIndex: 34; Maps: 'map0=[c0@47:17 c2@47:20 c3@48:1]'),  // raw_bsnl
    (FileName: 'ps01_map.pcpp'; DeclIndex: 35; Maps: 'map0=[c0@49:17] map1=[c0@49:23]'),  // raw_joined
    (FileName: 'ps01_map.pcpp'; DeclIndex: 36; Maps: 'map0=[c0@50:15] map1=[c0@50:22]'),  // plain_then_raw
    (FileName: 'ps01_map.pcpp'; DeclIndex: 37; Maps: 'map0=[c0@51:15 e2@51:17 c3@51:19]'),  // copy_esc_copy
    (FileName: 'ps01_map.pcpp'; DeclIndex: 38; Maps: ''),  // empty
    (FileName: 'ps02_map_lf.pcpp'; DeclIndex: 0; Maps: 'map0=[c0@3:15 e1@3:16]'),  // y_hex_splice
    (FileName: 'ps02_map_lf.pcpp'; DeclIndex: 1; Maps: 'map0=[c0@5:17 c2@6:1] map1=[c0@6:6]'),  // y_after_crlf_raw
    (FileName: 'ps02_map_lf.pcpp'; DeclIndex: 2; Maps: 'map0=[c0@7:15 c2@8:1]'),  // splice_before
    (FileName: 'ps02_map_lf.pcpp'; DeclIndex: 3; Maps: 'map0=[c0@9:15 c1@10:1]'),  // splice_between
    (FileName: 'ps02_map_lf.pcpp'; DeclIndex: 4; Maps: 'map0=[e0@11:15 c1@12:2]'),  // splice_in_esc
    (FileName: 'ps02_map_lf.pcpp'; DeclIndex: 5; Maps: 'map0=[e0@13:15 c1@14:2]'),  // splice_in_pct_esc
    (FileName: 'ps02_map_lf.pcpp'; DeclIndex: 6; Maps: 'map0=[c0@15:15 c1@17:1]'),  // splice_two
    (FileName: 'ps02_map_lf.pcpp'; DeclIndex: 7; Maps: 'map0=[c0@18:15] map1=[c0@19:6]'),  // joined_lines
    (FileName: 'ps02_map_lf.pcpp'; DeclIndex: 8; Maps: 'map0=[c0@20:17 c3@21:1]'),  // raw_lines
    (FileName: 'ps02_map_lf.pcpp'; DeclIndex: 9; Maps: 'map0=[c0@22:17 c3@23:1]'),  // raw_bsnl
    (FileName: 'ps03_wsplice.pcpp'; DeclIndex: 0; Maps: 'map0=[c0@3:15 c2@4:1]'),  // splice_ws
    (FileName: 'ps04_wsplice_lf.pcpp'; DeclIndex: 0; Maps: 'map0=[c0@3:15 c2@4:1]'),  // splice_ws
    (FileName: 'ps05_status.pcpp'; DeclIndex: 0; Maps: 'map0=[e0@3:15 c1@3:17]'),  // warning_keeps_map
    (FileName: 'ps05_status.pcpp'; DeclIndex: 1; Maps: 'map1=[c0@4:23]'),  // error_part_none
    (FileName: 'ps05_status.pcpp'; DeclIndex: 2; Maps: 'map1=[c0@5:22]'),  // prefixed_part_none
    (FileName: 'ps06_rawsplice.pcpp'; DeclIndex: 0; Maps: 'map0=[c0@4:3]')  // raw_prefix_splice
  );

function DoIsOutlined(const ANode: TPCNode): Boolean;
begin
  // The nodes a recovery outline prints; every other node is walked through
  Result := (ANode is TPCStmt) or (ANode is TPCMemberItem) or (ANode is TPCTest) or
    (ANode is TPCErrorExpr) or (ANode is TPCParam) or (ANode is TPCMatchArm) or
    (ANode is TPCChoiceValue) or ANode.IsRecovered;
end;

function DoOutlineItem(const ANode: TPCNode): string; forward;

procedure DoOutlineInto(const ANode: TPCNode; const AItems: TList<string>);
var
  LItems: TList<string>;
begin
  // ANode's printed descendants, in source order (the one tree walk)
  LItems := AItems;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      if DoIsOutlined(AChild) then
        LItems.Add(DoOutlineItem(AChild))
      else
        DoOutlineInto(AChild, LItems);
    end);
end;

function DoOutlineItem(const ANode: TPCNode): string;
var
  LChildren: TList<string>;
begin
  Result := ANode.KindName();
  if ANode is TPCDecl then
    Result := Result + ' ' + TPCDecl(ANode).DeclName
  else if ANode is TPCField then
    Result := Result + ' ' + TPCField(ANode).FieldName
  else if ANode is TPCParam then
    Result := Result + ' ' + TPCParam(ANode).ParamName
  else if ANode is TPCChoiceValue then
    Result := Result + ' ' + TPCChoiceValue(ANode).ValueName
  else if ANode is TPCErrorExpr then
    Result := Result + IntToStr(TPCErrorExpr(ANode).Parts.Count);
  if ANode.IsRecovered then
    Result := Result + '!';
  LChildren := TList<string>.Create();
  try
    DoOutlineInto(ANode, LChildren);
    if LChildren.Count > 0 then
      Result := Result + '(' + string.Join(',', LChildren.ToArray()) + ')';
  finally
    LChildren.Free();
  end;
end;

function DoRecoveryOutline(const ANode: TPCNode): string;
var
  LItems: TList<string>;
begin
  Result := '';
  if ANode = nil then
    Exit;
  LItems := TList<string>.Create();
  try
    DoOutlineInto(ANode, LItems);
    Result := string.Join(',', LItems.ToArray());
  finally
    LItems.Free();
  end;
end;

function DoParDir(): string;
begin
  // The exe sits two levels below the project root (repo\bin)
  Result := DoProbeDir('par\core');
end;

function DoFirstMessage(const AErrors: TErrors): string;
begin
  Result := '';
  if AErrors.Count() > 0 then
    Result := AErrors.GetItems()[0].Message;
end;

function DoFirstAt(const AErrors: TErrors): string;
begin
  // The first report's position for a failure message; '' when none
  Result := '';
  if AErrors.Count() > 0 then
    Result := AErrors.GetItems()[0].Range.ToPointString();
end;

procedure DoWith(const AName: string; const ACheck: TPCParseCheck);
begin
  DoWithIn(DoParDir(), AName, ACheck);
end;

function DoCodesOf(const AName: string): string;
var
  LCodes: string;
begin
  LCodes := '';
  DoWith(AName,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      LCodes := DoCodes(AErrors);
    end);
  Result := LCodes;
end;

procedure DoWithParser(const AName: string; const AModulePaths: TArray<string>;
  const ACheck: TPCParseCheck);
var
  LErrors: TErrors;
  LAst: TPCAst;
  LParser: TPCParser;
  LModule: TPCModule;
  LPath: string;
begin
  // A TPCParser driven by itself (no ParseModuleFile, no compiler): its own
  // AddModulePath is how it learns where modules live. The paths go in
  // before Init, which must keep them.
  LErrors := TErrors.Create();
  LAst := TPCAst.Create();
  LParser := TPCParser.Create();
  try
    LErrors.SetMaxErrors(100);
    LAst.SetErrors(LErrors);
    LParser.SetErrors(LErrors);
    for LPath in AModulePaths do
      LParser.AddModulePath(LPath);
    LParser.Init(LAst, TPath.Combine(DoParDir(), AName), nil, Default(TPCTargetTriple),
      Default(TPCTargetTriple), Default(TPCTargetTriple));
    LModule := LParser.Parse();
    LAst.AddModule(LModule);
    ACheck(LModule, LAst, LErrors);
  finally
    LParser.Free();
    LAst.Free();
    LErrors.Free();
  end;
end;

function DoImported(const AModule: TPCModule; const AIndex: Integer): TPCModule;
begin
  // The module behind the AIndex-th import; nil when there is none
  Result := nil;
  if (AModule <> nil) and (AIndex < AModule.Imports.Count) then
    Result := AModule.Imports[AIndex].ImportedModule;
end;

function DoVerbatimAt(const AModule: TPCModule; const AIndex: Integer): TPCVerbatimStmt;
begin
  // The AIndex-th module declaration when it is a verbatim node; nil otherwise
  Result := nil;
  if (AIndex < AModule.Decls.Count) and (AModule.Decls[AIndex] is TPCVerbatimStmt) then
    Result := TPCVerbatimStmt(AModule.Decls[AIndex]);
end;

function DoLinesText(const ALines: TArray<UInt64>): string;
var
  LLine: UInt64;
begin
  // '3,4': the lines in order, for one comparison
  Result := '';
  for LLine in ALines do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + UIntToStr(LLine);
  end;
end;

function DoExprDir(): string;
begin
  // The PARSER-EXPR fixtures sit beside the core ones
  Result := DoProbeDir('par\expr');
end;

procedure DoWithExpr(const AName: string; const ACheck: TPCParseCheck);
begin
  DoWithPath(TPath.Combine(DoExprDir(), AName), ACheck);
end;

function DoCodesOfExpr(const AName: string): string;
var
  LCodes: string;
begin
  LCodes := '';
  DoWithExpr(AName,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      LCodes := DoCodes(AErrors);
    end);
  Result := LCodes;
end;

function DoDeclAt(const AModule: TPCModule; const AIndex: Integer): TPCStmt;
begin
  // The AIndex-th module declaration; nil when there is none
  Result := nil;
  if (AModule <> nil) and (AIndex < AModule.Decls.Count) then
    Result := AModule.Decls[AIndex];
end;

function DoVarAt(const AModule: TPCModule; const AIndex: Integer): TPCVarDecl;
begin
  Result := nil;
  if DoDeclAt(AModule, AIndex) is TPCVarDecl then
    Result := TPCVarDecl(DoDeclAt(AModule, AIndex));
end;

function DoRoutineAt(const AModule: TPCModule; const AIndex: Integer): TPCRoutine;
begin
  Result := nil;
  if DoDeclAt(AModule, AIndex) is TPCRoutine then
    Result := TPCRoutine(DoDeclAt(AModule, AIndex));
end;

function DoTypeDeclAt(const AModule: TPCModule; const AIndex: Integer): TPCTypeDecl;
begin
  Result := nil;
  if DoDeclAt(AModule, AIndex) is TPCTypeDecl then
    Result := TPCTypeDecl(DoDeclAt(AModule, AIndex));
end;

function DoVarTypeAt(const AModule: TPCModule; const AIndex: Integer): TPCTypeExpr;
begin
  // The type of the AIndex-th module declaration when it is a var; nil otherwise
  Result := nil;
  if DoVarAt(AModule, AIndex) <> nil then
    Result := DoVarAt(AModule, AIndex).TypeExpr;
end;

function DoTypeDefAt(const AModule: TPCModule; const AIndex: Integer): TPCTypeExpr;
begin
  Result := nil;
  if DoTypeDeclAt(AModule, AIndex) <> nil then
    Result := DoTypeDeclAt(AModule, AIndex).TypeDef;
end;

function DoCppAt(const AModule: TPCModule; const AIndex: Integer): TPCCppType;
begin
  Result := nil;
  if DoVarTypeAt(AModule, AIndex) is TPCCppType then
    Result := TPCCppType(DoVarTypeAt(AModule, AIndex));
end;

function DoPartsText(const AType: TPCCppType): string;
var
  LPart: TPCNamePart;
begin
  // 'std::string', '::set': the parts joined by '::'; '' for nil
  Result := '';
  if AType = nil then
    Exit;
  if AType.HasLeadingScope then
    Result := '::';
  for LPart in AType.NameParts do
  begin
    if (Result <> '') and (Result <> '::') then
      Result := Result + '::';
    Result := Result + LPart.PartText;
  end;
end;

function DoArgAt(const AType: TPCCppType; const APart: Integer;
  const AArg: Integer): TPCTemplateArg;
begin
  // Template argument AArg of name part APart; nil when there is none
  Result := nil;
  if (AType = nil) or (APart >= AType.NameParts.Count) then
    Exit;
  if AArg < AType.NameParts[APart].TemplateArgs.Count then
    Result := AType.NameParts[APart].TemplateArgs[AArg];
end;

function DoInitAt(const AModule: TPCModule; const AIndex: Integer): TPCExpr;
begin
  // The initializer of the AIndex-th module declaration when it is a var
  Result := nil;
  if DoVarAt(AModule, AIndex) <> nil then
    Result := DoVarAt(AModule, AIndex).InitExpr;
end;

function DoLiteralAt(const AModule: TPCModule; const AIndex: Integer): TPCLiteral;
begin
  // The initializer of the AIndex-th module declaration when it is a literal
  Result := nil;
  if DoInitAt(AModule, AIndex) is TPCLiteral then
    Result := TPCLiteral(DoInitAt(AModule, AIndex));
end;

function DoTypeText(const AType: TPCTypeExpr): string;
var
  LCpp: TPCCppType;
  LKind: TPCTokenKind;
begin
  // A type in one word: B:<builtin token>, N:<dotted name>, P:<target>,
  // C:<fundamentals joined by +, or the :: parts>; '?' for anything else
  if AType = nil then
    Exit('nil');
  if AType is TPCBuiltinType then
    Exit('B:' + GetEnumName(TypeInfo(TPCTokenKind), Ord(TPCBuiltinType(AType).BuiltinToken)));
  if AType is TPCNamedType then
    Exit('N:' + string.Join('.', TPCNamedType(AType).Parts));
  if AType is TPCPointerType then
    Exit('P:' + DoTypeText(TPCPointerType(AType).TargetType));
  if AType is TPCCppType then
  begin
    LCpp := TPCCppType(AType);
    if Length(LCpp.Fundamentals) = 0 then
      Exit('C:' + DoPartsText(LCpp));
    Result := 'C:';
    for LKind in LCpp.Fundamentals do
    begin
      if Result <> 'C:' then
        Result := Result + '+';
      Result := Result + GetEnumName(TypeInfo(TPCTokenKind), Ord(LKind));
    end;
    Exit;
  end;
  Result := '?';
end;

function DoExprText(const AExpr: TPCExpr): string; forward;

function DoListText(const AList: TList<TPCExpr>): string;
var
  LItem: TPCExpr;
begin
  // 'a, b': the expressions joined by ', '
  Result := '';
  for LItem in AList do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + DoExprText(LItem);
  end;
end;

function DoArgText(const AArg: TPCTemplateArg): string;
begin
  // A verbatim cpp type id in double quotes, a type by DoTypeText, else the
  // expression
  if AArg.HasVerbatim then
    Exit('"' + AArg.Verbatim.Text + '"');
  if AArg.TypeArg <> nil then
    Exit(DoTypeText(AArg.TypeArg));
  Result := DoExprText(AArg.ExprArg);
end;

function DoNamePartText(const APart: TPCNamePart): string;
var
  LArg: TPCTemplateArg;
  LArgs: string;
begin
  // 'vector<C:tkKwInt>': the part and its template args; '<>' for an empty list
  Result := APart.PartText;
  if not APart.HasTemplateArgs then
    Exit;
  LArgs := '';
  for LArg in APart.TemplateArgs do
  begin
    if LArgs <> '' then
      LArgs := LArgs + ', ';
    LArgs := LArgs + DoArgText(LArg);
  end;
  Result := Result + '<' + LArgs + '>';
end;

function DoCallArgsText(const ACall: TPCCall): string;
var
  LI: Integer;
begin
  // A call's arguments in written order, the type argument at TypeArgIndex
  // (size(T): 0, get(I, T): 1); slot Args.Count is the place after the last
  // expression. 'L.get(0, B:tkKwString)'
  Result := '';
  for LI := 0 to ACall.Args.Count do
  begin
    if (ACall.TypeArg <> nil) and (LI = ACall.TypeArgIndex) then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + DoTypeText(ACall.TypeArg);
    end;
    if LI < ACall.Args.Count then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + DoExprText(ACall.Args[LI]);
    end;
  end;
end;

function DoExprText(const AExpr: TPCExpr): string;
var
  LPart: TPCNamePart;
  LElement: TPCSetElement;
  LInit: TPCFieldInit;
begin
  // An expression as one string, every operator node in parentheses with its
  // enum name: a + b * c -> (a boAdd (b boMul c)). The expr tests compare these
  if AExpr = nil then
    Exit('nil');
  if AExpr is TPCLiteral then
    Exit(TPCLiteral(AExpr).Text);
  if AExpr is TPCName then
  begin
    Result := '';
    if TPCName(AExpr).HasLeadingScope then
      Result := '::';
    for LPart in TPCName(AExpr).Parts do
    begin
      if (Result <> '') and (Result <> '::') then
        Result := Result + '::';
      Result := Result + DoNamePartText(LPart);
    end;
    Exit;
  end;
  if AExpr is TPCSpecial then
    Exit(GetEnumName(TypeInfo(TPCSpecialKind), Ord(TPCSpecial(AExpr).SpecialKind)));
  if AExpr is TPCBinary then
    Exit('(' + DoExprText(TPCBinary(AExpr).Left) + ' ' +
      GetEnumName(TypeInfo(TPCBinaryOp), Ord(TPCBinary(AExpr).Op)) + ' ' +
      DoExprText(TPCBinary(AExpr).Right) + ')');
  if AExpr is TPCAssign then
    Exit('(' + DoExprText(TPCAssign(AExpr).Target) + ' ' +
      GetEnumName(TypeInfo(TPCAssignOp), Ord(TPCAssign(AExpr).Op)) + ' ' +
      DoExprText(TPCAssign(AExpr).ValueExpr) + ')');
  if AExpr is TPCTernary then
    Exit('(' + DoExprText(TPCTernary(AExpr).Condition) + ' ? ' +
      DoExprText(TPCTernary(AExpr).ThenExpr) + ' : ' +
      DoExprText(TPCTernary(AExpr).ElseExpr) + ')');
  if AExpr is TPCUnary then
    Exit('(' + GetEnumName(TypeInfo(TPCUnaryOp), Ord(TPCUnary(AExpr).Op)) + ' ' +
      DoExprText(TPCUnary(AExpr).Operand) + ')');
  if AExpr is TPCCall then
    Exit(DoExprText(TPCCall(AExpr).Callee) + '(' + DoCallArgsText(TPCCall(AExpr)) + ')');
  if AExpr is TPCIndex then
    Exit(DoExprText(TPCIndex(AExpr).Base) + '[' + DoExprText(TPCIndex(AExpr).IndexExpr) + ']');
  if AExpr is TPCMember then
  begin
    if TPCMember(AExpr).Access = maDot then
      Exit(DoExprText(TPCMember(AExpr).Base) + '.' + DoNamePartText(TPCMember(AExpr).Member));
    Exit(DoExprText(TPCMember(AExpr).Base) + '->' + DoNamePartText(TPCMember(AExpr).Member));
  end;
  if AExpr is TPCBracedInit then
  begin
    Result := '';
    if TPCBracedInit(AExpr).Base <> nil then
      Result := DoExprText(TPCBracedInit(AExpr).Base);
    Exit(Result + '{' + DoListText(TPCBracedInit(AExpr).Args) + '}');
  end;
  if AExpr is TPCCast then
    Exit('(' + GetEnumName(TypeInfo(TPCCastKind), Ord(TPCCast(AExpr).CastKind)) + ' ' +
      DoTypeText(TPCCast(AExpr).TargetType) + ' ' + DoExprText(TPCCast(AExpr).Operand) + ')');
  if AExpr is TPCNew then
  begin
    Result := 'new ' + DoTypeText(TPCNew(AExpr).TargetType);
    if TPCNew(AExpr).InitKind = niArgs then
      Result := Result + '(' + DoListText(TPCNew(AExpr).Args) + ')'
    else if TPCNew(AExpr).InitKind = niArraySize then
      Result := Result + '[' + DoExprText(TPCNew(AExpr).SizeExpr) + ']'
    else if TPCNew(AExpr).InitKind = niBraced then
      Result := Result + '{' + DoListText(TPCNew(AExpr).Args) + '}';
    Exit;
  end;
  if AExpr is TPCDelete then
  begin
    if TPCDelete(AExpr).IsArray then
      Exit('delete[] ' + DoExprText(TPCDelete(AExpr).Operand));
    Exit('delete ' + DoExprText(TPCDelete(AExpr).Operand));
  end;
  if AExpr is TPCSetLiteral then
  begin
    Result := '';
    for LElement in TPCSetLiteral(AExpr).Elements do
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + DoExprText(LElement.LowExpr);
      if LElement.HighExpr <> nil then
        Result := Result + '..' + DoExprText(LElement.HighExpr);
    end;
    Exit('[' + Result + ']');
  end;
  if AExpr is TPCRecordLiteral then
  begin
    Result := '';
    for LInit in TPCRecordLiteral(AExpr).Inits do
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + LInit.FieldName + ': ' + DoExprText(LInit.ValueExpr);
    end;
    Exit(string.Join('.', TPCRecordLiteral(AExpr).RecordType.Parts) + '(' + Result + ')');
  end;
  if AExpr is TPCVarargs then
  begin
    case TPCVarargs(AExpr).VarargsKind of
      vaCount:
        Exit('varargs.count');
      vaNext:
        Exit('varargs.next(' + DoTypeText(TPCVarargs(AExpr).ReadType) + ')');
      vaGet:
        Exit('varargs.get(' + DoExprText(TPCVarargs(AExpr).IndexExpr) + ', ' +
          DoTypeText(TPCVarargs(AExpr).ReadType) + ')');
      vaReset:
        Exit('varargs.reset()');
      vaCopy:
        Exit('varargs.copy()');
    end;
    Exit('varargs');
  end;
  if AExpr is TPCVerbatimExpr then
    Exit(GetEnumName(TypeInfo(TPCVerbatimKind), Ord(TPCVerbatimExpr(AExpr).Verbatim.VerbatimKind)) +
      '"' + TPCVerbatimExpr(AExpr).Verbatim.Text + '"');
  Result := '?';
end;

procedure DoCheckItemsAt(const ATest: TTestCase; const AName: string; const APath: string;
  const AExpected: array of string);
var
  LExpected: TArray<string>;
  LI: Integer;
begin
  // Parse APath: no report, one var item per expected string, each item's
  // initializer printed by DoExprText equals it
  SetLength(LExpected, Length(AExpected));
  for LI := 0 to High(AExpected) do
    LExpected[LI] := AExpected[LI];
  DoWithPath(APath,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LJ: Integer;
    begin
      ATest.Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = Length(LExpected)),
        AName + ': ' + IntToStr(Length(LExpected)) + ' items, no report (got ' +
        IntToStr(AModule.Decls.Count) + ', ''' + DoCodes(AErrors) + ''')');
      if AModule.Decls.Count <> Length(LExpected) then
        Exit;
      for LJ := 0 to High(LExpected) do
        ATest.Check(DoExprText(DoInitAt(AModule, LJ)) = LExpected[LJ],
          AName + ': item ' + IntToStr(LJ) + ' is ' + LExpected[LJ] + ' (got ' +
          DoExprText(DoInitAt(AModule, LJ)) + ')');
    end);
end;

procedure DoCheckItems(const ATest: TTestCase; const AName: string; const AFile: string;
  const AExpected: array of string);
begin
  // A PARSER-EXPR fixture (par\expr) through DoCheckItemsAt
  DoCheckItemsAt(ATest, AName, TPath.Combine(DoExprDir(), AFile), AExpected);
end;

function DoStmtDir(): string;
begin
  // The PARSER-STMT fixtures sit beside the core ones
  Result := DoProbeDir('par\stmt');
end;

procedure DoWithStmt(const AName: string; const ACheck: TPCParseCheck);
begin
  DoWithPath(TPath.Combine(DoStmtDir(), AName), ACheck);
end;

function DoStrPosDir(): string;
begin
  // The P-STRPOS fixtures (PREREQ-B) sit beside the core ones
  Result := DoProbeDir('par\strpos');
end;

function DoJumpsDir(): string;
begin
  // The escaping-jump fixtures (PREREQ-B: pj* here, cj* for UTestCase.CppJumps)
  Result := DoProbeDir('par\jumps');
end;

function DoVarargsDir(): string;
begin
  // The varargs form fixtures (PREREQ-B, scripts\zb_sem\pb\gen_varargs.py)
  Result := DoProbeDir('par\varargs');
end;

function DoCodesOfVarargs(const AName: string): string;
var
  LCodes: string;
begin
  LCodes := '';
  DoWithPath(TPath.Combine(DoVarargsDir(), AName),
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      LCodes := DoCodes(AErrors);
    end);
  Result := LCodes;
end;

function DoMapsText(const ALiteral: TPCLiteral): string;
var
  LI: Integer;
  LJ: Integer;
  LRun: TPCValueRun;
  LText: string;
begin
  // Every part's value map as 'map<I>=[c<V>@<L>:<C> e<V>@<L>:<C> ...]', space-
  // joined, parts without a map left out: built from the fields, apart from
  // the AST dump, so the fields and the dump are checked one against the other
  Result := '';
  for LI := 0 to High(ALiteral.Parts) do
  begin
    if Length(ALiteral.Parts[LI].ValueMap) = 0 then
      Continue;
    LText := '';
    for LJ := 0 to High(ALiteral.Parts[LI].ValueMap) do
    begin
      LRun := ALiteral.Parts[LI].ValueMap[LJ];
      if LJ > 0 then
        LText := LText + ' ';
      if LRun.IsCopy then
        LText := LText + 'c'
      else
        LText := LText + 'e';
      LText := LText + IntToStr(LRun.ValueOffset) + '@' + UIntToStr(LRun.Line) + ':' +
        UIntToStr(LRun.Column);
    end;
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + 'map' + IntToStr(LI) + '=[' + LText + ']';
  end;
end;

procedure DoCheckStrPos(const ATest: TTestCase; const AFile: string; const ACodes: string);
var
  LCount: Integer;
  LI: Integer;
begin
  // Parse one P-STRPOS fixture: exactly ACodes reported, one item per
  // PC_TEST_STRPOS row of AFile, each literal's fields carry the row's full
  // value maps, and the dump prints them after the parts (D-SP3), nothing else
  LCount := 0;
  for LI := 0 to High(PC_TEST_STRPOS) do
  begin
    if PC_TEST_STRPOS[LI].FileName = AFile then
      Inc(LCount);
  end;
  DoWithPath(TPath.Combine(DoStrPosDir(), AFile),
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LJ: Integer;
      LLit: TPCLiteral;
      LMaps: string;
      LDump: string;
      LDumpOk: Boolean;
    begin
      ATest.Check((DoCodes(AErrors) = ACodes) and (AModule.Decls.Count = LCount),
        'expr_string_positions: ' + AFile + ' has ' + IntToStr(LCount) + ' items, codes ''' +
        ACodes + ''' (got ' + IntToStr(AModule.Decls.Count) + ', ''' + DoCodes(AErrors) + ''')');
      if AModule.Decls.Count <> LCount then
        Exit;
      for LJ := 0 to High(PC_TEST_STRPOS) do
      begin
        if PC_TEST_STRPOS[LJ].FileName <> AFile then
          Continue;
        LLit := DoLiteralAt(AModule, PC_TEST_STRPOS[LJ].DeclIndex);
        LMaps := '';
        LDump := '';
        if LLit <> nil then
        begin
          LMaps := DoMapsText(LLit);
          LDump := LLit.Dump();
        end;
        // The dump's first ' map' is where the expected maps start: no map
        // printed for a part that has none, none before them
        if PC_TEST_STRPOS[LJ].Maps = '' then
          LDumpOk := not LDump.Contains(' map')
        else
          LDumpOk := LDump.Contains(' ' + PC_TEST_STRPOS[LJ].Maps) and
            (Pos(' map', LDump) = Pos(' ' + PC_TEST_STRPOS[LJ].Maps, LDump));
        ATest.Check((LLit <> nil) and (LMaps = PC_TEST_STRPOS[LJ].Maps) and LDumpOk,
          'expr_string_positions: ' + AFile + ' item ' +
          IntToStr(PC_TEST_STRPOS[LJ].DeclIndex) + ' maps ''' + PC_TEST_STRPOS[LJ].Maps +
          ''' (got ''' + LMaps + ''', dump ok ' + BoolToStr(LDumpOk, True) + ')');
      end;
    end);
end;

function DoCodesOfStmt(const AName: string): string;
var
  LCodes: string;
begin
  LCodes := '';
  DoWithStmt(AName,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      LCodes := DoCodes(AErrors);
    end);
  Result := LCodes;
end;

function DoStmtText(const AStmt: TPCStmt): string; forward;

function DoStmtListText(const AList: TList<TPCStmt>): string;
var
  LStmt: TPCStmt;
begin
  // ' a; b;': every statement with its ';', each after one space
  Result := '';
  for LStmt in AList do
    Result := Result + ' ' + DoStmtText(LStmt) + ';';
end;

function DoArmText(const AArm: TPCMatchArm): string;
var
  LLabel: TPCMatchLabel;
  LLabels: string;
begin
  // ' [1, 3..5] a;': the labels in brackets, then the arm's statements
  LLabels := '';
  for LLabel in AArm.Labels do
  begin
    if LLabels <> '' then
      LLabels := LLabels + ', ';
    LLabels := LLabels + DoExprText(LLabel.LowExpr);
    if LLabel.HighExpr <> nil then
      LLabels := LLabels + '..' + DoExprText(LLabel.HighExpr);
  end;
  Result := ' [' + LLabels + ']' + DoStmtListText(AArm.Stmts);
end;

function DoCompoundText(const AStmt: TPCStmt): string;
var
  LArm: TPCMatchArm;
begin
  // The statements with a body (DoStmtText); '' for any other
  Result := '';
  if AStmt is TPCBlock then
    Exit('begin' + DoStmtListText(TPCBlock(AStmt).Stmts) + ' end');
  if AStmt is TPCIf then
  begin
    Result := 'if ' + DoExprText(TPCIf(AStmt).Condition) + ' then' +
      DoStmtListText(TPCIf(AStmt).ThenStmts);
    if TPCIf(AStmt).HasElse then
      Result := Result + ' else' + DoStmtListText(TPCIf(AStmt).ElseStmts);
    Exit(Result + ' end');
  end;
  if AStmt is TPCWhile then
    Exit('while ' + DoExprText(TPCWhile(AStmt).Condition) + ' do' +
      DoStmtListText(TPCWhile(AStmt).Stmts) + ' end');
  if AStmt is TPCFor then
  begin
    Result := 'for ' + TPCFor(AStmt).IteratorName + ' := ' + DoExprText(TPCFor(AStmt).StartExpr);
    if TPCFor(AStmt).IsDownTo then
      Result := Result + ' downto '
    else
      Result := Result + ' to ';
    Exit(Result + DoExprText(TPCFor(AStmt).EndExpr) + ' do' +
      DoStmtListText(TPCFor(AStmt).Stmts) + ' end');
  end;
  if AStmt is TPCRepeat then
    Exit('repeat' + DoStmtListText(TPCRepeat(AStmt).Stmts) + ' until ' +
      DoExprText(TPCRepeat(AStmt).Condition));
  if AStmt is TPCMatch then
  begin
    Result := 'match ' + DoExprText(TPCMatch(AStmt).Subject) + ' of';
    for LArm in TPCMatch(AStmt).Arms do
      Result := Result + DoArmText(LArm);
    if TPCMatch(AStmt).HasElse then
      Result := Result + ' else' + DoStmtListText(TPCMatch(AStmt).ElseStmts);
    Exit(Result + ' end');
  end;
  if AStmt is TPCGuard then
  begin
    Result := 'guard' + DoStmtListText(TPCGuard(AStmt).GuardStmts);
    if TPCGuard(AStmt).HasExcept then
      Result := Result + ' except' + DoStmtListText(TPCGuard(AStmt).ExceptStmts);
    if TPCGuard(AStmt).HasFinally then
      Result := Result + ' finally' + DoStmtListText(TPCGuard(AStmt).FinallyStmts);
    Exit(Result + ' end');
  end;
end;

function DoStmtText(const AStmt: TPCStmt): string;
begin
  // A statement as one line (the statement tests compare these):
  // if (LX boLess 1) then Foo(); else Bar(); end
  if AStmt = nil then
    Exit('nil');
  Result := DoCompoundText(AStmt);
  if Result <> '' then
    Exit;
  if AStmt is TPCExprStmt then
    Exit(DoExprText(TPCExprStmt(AStmt).Expr));
  if AStmt is TPCReturn then
  begin
    if TPCReturn(AStmt).ValueExpr = nil then
      Exit('return');
    Exit('return ' + DoExprText(TPCReturn(AStmt).ValueExpr));
  end;
  if AStmt is TPCLeave then
    Exit('leave');
  if AStmt is TPCSkip then
    Exit('skip');
  if AStmt is TPCVarDecl then
    Exit('var ' + TPCVarDecl(AStmt).DeclName);
  if AStmt is TPCConstDecl then
    Exit('const ' + TPCConstDecl(AStmt).DeclName);
  if AStmt is TPCTypeDecl then
    Exit('type ' + TPCTypeDecl(AStmt).DeclName);
  if AStmt is TPCVerbatimStmt then
    Exit(GetEnumName(TypeInfo(TPCVerbatimKind), Ord(TPCVerbatimStmt(AStmt).Verbatim.VerbatimKind)) +
      ' ' + GetEnumName(TypeInfo(TPCEmitTarget), Ord(TPCVerbatimStmt(AStmt).Verbatim.EmitTarget)));
  if AStmt is TPCDirective then
    Exit('@' + TPCDirective(AStmt).DirectiveName + '/' + IntToStr(TPCDirective(AStmt).Args.Count));
  Result := '?';
end;

procedure DoCheckStmts(const ATest: TTestCase; const AName: string; const AFile: string;
  const AExpected: array of string);
var
  LExpected: TArray<string>;
  LI: Integer;
begin
  // Parse AFile: no report, one exe body statement per expected string, each
  // printed by DoStmtText equals it
  SetLength(LExpected, Length(AExpected));
  for LI := 0 to High(AExpected) do
    LExpected[LI] := AExpected[LI];
  DoWithStmt(AFile,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LJ: Integer;
      LCount: Integer;
    begin
      LCount := -1;
      if AModule.Body <> nil then
        LCount := AModule.Body.Stmts.Count;
      ATest.Check((DoCodes(AErrors) = '') and (LCount = Length(LExpected)),
        AName + ': ' + IntToStr(Length(LExpected)) + ' statements, no report (got ' +
        IntToStr(LCount) + ', ''' + DoCodes(AErrors) + ''')');
      if LCount <> Length(LExpected) then
        Exit;
      for LJ := 0 to High(LExpected) do
        ATest.Check(DoStmtText(AModule.Body.Stmts[LJ]) = LExpected[LJ],
          AName + ': statement ' + IntToStr(LJ) + ' is ' + LExpected[LJ] + ' (got ' +
          DoStmtText(AModule.Body.Stmts[LJ]) + ')');
    end);
end;

{ TPCParserTests }

constructor TPCParserTests.Create();
begin
  inherited;

  Title := 'Parser';
  RegisterTest('header_kinds', DoTestHeaderKinds);
  RegisterTest('header_errors', DoTestHeaderErrors);
  RegisterTest('semicolon_at', DoTestSemicolonAt);
  RegisterTest('prologue_shapes', DoTestPrologueShapes);
  RegisterTest('prologue_errors', DoTestPrologueErrors);
  RegisterTest('directive_place', DoTestDirectivePlace);
  RegisterTest('target', DoTestTarget);
  RegisterTest('import', DoTestImport);
  RegisterTest('import_graph', DoTestImportGraph);
  RegisterTest('import_errors', DoTestImportErrors);
  RegisterTest('module_paths', DoTestModulePaths);
  RegisterTest('identity', DoTestIdentity);
  RegisterTest('module_end', DoTestModuleEnd);
  RegisterTest('ranges', DoTestRanges);
  RegisterTest('spans', DoTestSpans);
  RegisterTest('placement', DoTestPlacement);
  RegisterTest('cpp_block', DoTestCppBlock);
  RegisterTest('cpp_jumps', DoTestCppJumps);
  RegisterTest('cpp_errors', DoTestCppErrors);
  RegisterTest('digraphs', DoTestDigraphs);
  RegisterTest('sections', DoTestSections);
  RegisterTest('section_errors', DoTestSectionErrors);
  RegisterTest('body', DoTestBody);
  RegisterTest('test_blocks', DoTestTestBlocks);
  RegisterTest('recovery', DoTestRecovery);
  RegisterTest('recovery_nodes', DoTestRecoveryNodes);
  RegisterTest('recovery_rows', DoTestRecoveryRows);
  RegisterTest('operand_starts', DoTestOperandStarts);
  RegisterTest('f1', DoTestF1);
  RegisterTest('inside_lines', DoTestInsideLines);
  RegisterTest('ptypes', DoTestPaskalTypes);
  RegisterTest('ctypes', DoTestCppTypes);
  RegisterTest('targs', DoTestTemplateArgs);
  RegisterTest('typedefs', DoTestTypeDefs);
  RegisterTest('rtype_positions', DoTestRoutineTypePositions);
  RegisterTest('decls', DoTestDecls);
  RegisterTest('decl_errors', DoTestDeclErrors);
  RegisterTest('decl_recovery', DoTestDeclRecovery);
  RegisterTest('expr_prec', DoTestExprPrecedence);
  RegisterTest('expr_postfix', DoTestExprPostfix);
  RegisterTest('expr_primary', DoTestExprPrimary);
  RegisterTest('expr_targs', DoTestExprTemplateArgs);
  RegisterTest('expr_strings', DoTestExprStrings);
  RegisterTest('expr_string_values', DoTestExprStringValues);
  RegisterTest('expr_string_positions', DoTestExprStringPositions);
  RegisterTest('expr_literal_facts', DoTestExprLiteralFacts);
  RegisterTest('expr_char_values', DoTestExprCharValues);
  RegisterTest('expr_errors', DoTestExprErrors);
  RegisterTest('expr_recovery', DoTestExprRecovery);
  RegisterTest('verbatim_lambda', DoTestVerbatimLambda);
  RegisterTest('verbatim_opaque', DoTestVerbatimOpaque);
  RegisterTest('verbatim_cpp', DoTestVerbatimCpp);
  RegisterTest('cstyle_cast', DoTestCStyleCast);
  RegisterTest('size_arg', DoTestSizeArg);
  RegisterTest('varargs_forms', DoTestVarargsForms);
  RegisterTest('varargs_errors', DoTestVarargsErrors);
  RegisterTest('verbatim_errors', DoTestVerbatimErrors);
  RegisterTest('stmt_simple', DoTestStmtSimple);
  RegisterTest('stmt_flow', DoTestStmtFlow);
  RegisterTest('stmt_match', DoTestStmtMatch);
  RegisterTest('stmt_guard', DoTestStmtGuard);
  RegisterTest('stmt_body_forms', DoTestStmtBodyForms);
  RegisterTest('stmt_test_body', DoTestStmtTestBody);
  RegisterTest('stmt_errors', DoTestStmtErrors);
  RegisterTest('stmt_recovery', DoTestStmtRecovery);
  RegisterTest('stmt_ranges', DoTestStmtRanges);
  RegisterTest('decl_module', DoTestDeclModule);
  RegisterTest('keyword_ranges', DoTestKeywordRanges);
  RegisterTest('name_ranges', DoTestNameRanges);
  RegisterTest('doc_comments', DoTestDocComments);
end;

procedure TPCParserTests.Run();
begin
  inherited;
end;

procedure TPCParserTests.DoTestHeaderKinds();
begin
  DoWith('pa01_lib.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = '') and (AModule.ModuleKind = mkLib) and
        (AModule.ModuleName = 'pa01_lib') and (AAst.ModuleCount() = 1) and
        (AAst.ModuleAt(0) = AModule), 'header_kinds: a lib parses and registers');
      Check(TUtils.SamePath(AModule.SourceFile, TPath.Combine(DoParDir(), 'pa01_lib.pcpp')),
        'header_kinds: SourceFile is the resolved file');
    end);
  DoWith('pa01_dll.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = '') and (AModule.ModuleKind = mkDll),
        'header_kinds: a dll parses');
    end);
  DoWith('pa01_exe.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      // The header only; the body test parses this fixture whole
      Check((AModule.ModuleKind = mkExe) and (Pos(PC_ERR_PAR_002, DoCodes(AErrors)) = 0) and
        (Pos(PC_ERR_PAR_004, DoCodes(AErrors)) = 0), 'header_kinds: exe');
    end);
  Check(DoCodesOf('pa02_unitmain.pcpp') = PC_ERR_PAR_004,
    'header_kinds: a unit as the main module is PR0004');
end;

procedure TPCParserTests.DoTestHeaderErrors();
begin
  DoWith('pa03_name.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_003) and (AModule.ModuleName = 'PA03_Name') and
        DoFirstMessage(AErrors).Contains('PA03_Name') and
        DoFirstMessage(AErrors).Contains('pa03_name'),
        'header_errors: a case-only name mismatch is PR0003, the name kept as written');
    end);
  DoWith('pa04_nokind.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_002) and (AModule.ModuleKind = mkExe) and
        (AModule.ModuleName = 'pa04_nokind'),
        'header_errors: no kind is PR0002 only, the main file assumed exe, the name read');
    end);
  Check(DoCodesOf('pa05_nomodule.pcpp') = PC_ERR_PAR_001,
    'header_errors: no module keyword is one PR0001');
  DoWith('pa05b_noname.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_001) and (AModule.ModuleName = '') and
        (AAst.ModuleCount() = 1),
        'header_errors: no name is one PR0001; the nameless module still registers');
    end);
end;

procedure TPCParserTests.DoTestSemicolonAt();
begin
  // A missing ';' is reported just after the token it should follow (as
  // clang), not at the token found next; any other missing token is still
  // reported at the token found in its place (scripts\zb_ed\gen_semi.py)
  DoWith('pa70_semi_nextline.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((AErrors.Count() > 0) and (AErrors.GetItems()[0].Code = PC_ERR_PAR_001) and
        (AErrors.GetItems()[0].Range.StartLine = 3) and
        (AErrors.GetItems()[0].Range.StartColumn = 6) and
        DoFirstMessage(AErrors).Contains('println'),
        'semicolon_at: next line: PR0001 at (3,6) just after dfd, found println (got %s)',
        [DoFirstAt(AErrors)]);
    end);
  DoWith('pa71_semi_sameline.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((AErrors.Count() > 0) and (AErrors.GetItems()[0].Code = PC_ERR_PAR_001) and
        (AErrors.GetItems()[0].Range.StartLine = 3) and
        (AErrors.GetItems()[0].Range.StartColumn = 9),
        'semicolon_at: same line: PR0001 at (3,9) just after 1 (got %s)',
        [DoFirstAt(AErrors)]);
    end);
  DoWith('pa72_paren.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((AErrors.Count() > 0) and (AErrors.GetItems()[0].Code = PC_ERR_PAR_001) and
        (AErrors.GetItems()[0].Range.StartLine = 3) and
        (AErrors.GetItems()[0].Range.StartColumn = 6),
        'semicolon_at: a missing ) stays at the ; found in its place, (3,6) (got %s)',
        [DoFirstAt(AErrors)]);
    end);
end;

procedure TPCParserTests.DoTestPrologueShapes();
begin
  DoWith('pa06_shapes.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LDirs: TList<TPCDirective>;
    begin
      LDirs := AModule.Directives;
      Check((DoCodes(AErrors) = '') and (LDirs.Count = 6), 'prologue_shapes: six directives');
      if LDirs.Count <> 6 then
        Exit;
      Check((LDirs[0].DirectiveName = 'optimize') and (LDirs[0].Args.Count = 1) and
        (LDirs[0].Args[0].ArgKind = daIdentifier) and (LDirs[0].Args[0].Text = 'speed') and
        (LDirs[0].Args[0].ResolvedText = 'speed'), 'prologue_shapes: identifier');
      Check((LDirs[1].DirectiveName = 'vimajor') and (LDirs[1].Args.Count = 1) and
        (LDirs[1].Args[0].ArgKind = daInteger) and (LDirs[1].Args[0].ResolvedText = '2'),
        'prologue_shapes: integer');
      Check(LDirs[1].Args[0].HasValue and (LDirs[1].Args[0].IntValue = 2) and
        (LDirs[1].Args[0].Dump() = 'DirectiveArg daInteger "2" value=2 resolved="2"' + sLineBreak) and
        (not LDirs[0].Args[0].HasValue),
        'prologue_shapes: an integer argument keeps its value, dumped; an identifier has none');
      Check((LDirs[2].DirectiveName = 'vicompanyname') and (LDirs[2].Args.Count = 1) and
        (LDirs[2].Args[0].ArgKind = daCString) and (LDirs[2].Args[0].Text = '"Acme\x41"') and
        (LDirs[2].Args[0].ResolvedText = 'AcmeA'),
        'prologue_shapes: cstring, Text exact, ResolvedText decoded');
      Check((LDirs[3].DirectiveName = 'breakpoint') and (LDirs[3].Args.Count = 0),
        'prologue_shapes: no argument');
      Check((LDirs[4].DirectiveName = 'message') and (LDirs[4].Args.Count = 2) and
        (LDirs[4].Args[0].ArgKind = daIdentifier) and (LDirs[4].Args[0].ResolvedText = 'warn') and
        (LDirs[4].Args[1].ArgKind = daCString) and (LDirs[4].Args[1].ResolvedText = 'hi'),
        'prologue_shapes: severity and text');
      Check((LDirs[5].DirectiveName = 'addincludepath') and (LDirs[5].Args.Count = 1) and
        (LDirs[5].Args[0].ResolvedText = TUtils.ResolvePath('inc')),
        'prologue_shapes: a path resolves through ResolvePath, no base (CWD)');
      Check((LDirs[0].DirectiveKind = bdOptimize) and (LDirs[1].DirectiveKind = bdVIMajor) and
        (LDirs[2].DirectiveKind = bdVICompanyName) and (LDirs[3].DirectiveKind = bdBreakpoint) and
        (LDirs[4].DirectiveKind = bdMessage) and (LDirs[5].DirectiveKind = bdAddIncludePath),
        'prologue_shapes: each directive carries its PC_BUILD_DIRECTIVES kind');
      Check(LDirs[2].Args[0].HasValue and LDirs[4].Args[1].HasValue and
        LDirs[5].Args[0].HasValue,
        'prologue_shapes: a decoded / resolved cstring argument HasValue');
    end);
end;

procedure TPCParserTests.DoTestPrologueErrors();
begin
  Check(DoCodesOf('pa07a_unknown.pcpp') = PC_ERR_PAR_005, 'prologue_errors: unknown is PR0005');
  Check(DoCodesOf('pa07b_shape.pcpp') = PC_ERR_PAR_006, 'prologue_errors: shape miss is PR0006');
  Check(DoCodesOf('pa07g_suffix.pcpp') = PC_ERR_PAR_006,
    'prologue_errors: an integer with a suffix is PR0006');
  Check(DoCodesOf('pa07c_severity.pcpp') = PC_ERR_PAR_007,
    'prologue_errors: bad severity is PR0007');
  Check(DoCodesOf('pa07d_prefix.pcpp') = PC_ERR_PAR_009,
    'prologue_errors: a prefixed string is PR0009');
  Check(DoCodesOf('pa07e_utf8.pcpp') = PC_ERR_PAR_009,
    'prologue_errors: a value that is not UTF-8 is PR0009');
  DoWith('pa07f_warn.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_021) and (AErrors.ErrorCount() = 0) and
        (AModule.Directives.Count = 1) and (AModule.Directives[0].Args.Count = 1) and
        (AModule.Directives[0].Args[0].ResolvedText = 'q') and
        AModule.Directives[0].Args[0].HasValue,
        'prologue_errors: an unknown escape is one PR0021 warning, the value kept');
    end);
  Check(DoCodesOf('pa07h_target.pcpp') = PC_ERR_CND_009,
    'prologue_errors: @target argument errors are the filter''s alone');
  DoWith('pa07i_path.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_022) and (AModule.Directives.Count = 1) and
        (AModule.Directives[0].Args.Count = 1) and
        (AModule.Directives[0].Args[0].ResolvedText = '') and
        (not AModule.Directives[0].Args[0].HasValue),
        'prologue_errors: a path ResolvePath rejects is PR0022, no value');
    end);
  DoWith('pa07j_empty.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = '') and (AModule.Directives.Count = 1) and
        (AModule.Directives[0].Args.Count = 1) and AModule.Directives[0].Args[0].HasValue and
        (AModule.Directives[0].Args[0].ResolvedText = ''),
        'prologue_errors: an empty text is a value (HasValue, ResolvedText '''')');
    end);
end;

procedure TPCParserTests.DoTestDirectivePlace();
begin
  Check(DoCodesOf('pa08a_late.pcpp') = PC_ERR_PAR_008,
    'directive_place: a build directive after the import clause is PR0008');
  Check(DoCodesOf('pa08b_target.pcpp') = PC_ERR_CND_005,
    'directive_place: a late @target is the filter''s CD0005 alone');
  DoWith('pa24_mainonly.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LUnit: TPCModule;
    begin
      LUnit := DoImported(AModule, 0);
      Check((DoCodes(AErrors) = PC_ERR_PAR_023) and (LUnit <> nil) and
        (LUnit.Directives.Count = 2),
        'directive_place: a main-only directive in a unit is PR0023, still built');
      if (LUnit = nil) or (LUnit.Directives.Count <> 2) then
        Exit;
      Check((LUnit.Directives[1].DirectiveName = 'linklibrary') and
        (LUnit.Directives[1].Args[0].ResolvedText = 'm'),
        'directive_place: a unit may add to the build (@linklibrary, a library name, never resolved)');
    end);
end;

procedure TPCParserTests.DoTestTarget();
begin
  DoWith('pa27_target.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LUnit: TPCModule;
    begin
      LUnit := DoImported(AModule, 0);
      Check((DoCodes(AErrors) = '') and
        (AModule.ResolvedTarget.ToLLVM() = 'x86_64-unknown-linux-gnu'),
        'target: the main module takes its @target');
      Check((AModule.Directives.Count = 1) and (AModule.Directives[0].DirectiveName = 'target') and
        (AModule.Directives[0].Args[0].ResolvedText = 'x86_64-unknown-linux-gnu'),
        'target: the @target directive is built from a valid argument');
      Check((LUnit <> nil) and (LUnit.ResolvedTarget.ToLLVM() = 'x86_64-unknown-linux-gnu'),
        'target: an imported module receives the main module''s triple');
    end);
  DoWith('pa11_import.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LUnit: TPCModule;
    begin
      LUnit := DoImported(AModule, 0);
      Check((AModule.ResolvedTarget.ToLLVM() = TPCTargetTriple.DefaultTriple().ToLLVM()) and
        (LUnit <> nil) and (LUnit.ResolvedTarget.ToLLVM() = AModule.ResolvedTarget.ToLLVM()),
        'target: no @target = the default triple, handed down');
    end);
end;

procedure TPCParserTests.DoTestImport();
begin
  DoWith('pa11_import.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LUnit: TPCModule;
    begin
      LUnit := DoImported(AModule, 0);
      Check((DoCodes(AErrors) = '') and (AModule.Imports.Count = 1) and
        (AModule.Imports[0].ModuleName = 'pa_u1') and (LUnit <> nil) and
        (LUnit.ModuleName = 'pa_u1') and (LUnit.ModuleKind = mkUnit),
        'import: the unit is parsed and linked');
      Check((AAst.ModuleCount() = 2) and (AAst.ModuleAt(0) = LUnit) and (AAst.ModuleAt(1) = AModule),
        'import: registered in dependency order');
    end);
  DoWith('pa17_modpath.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LUnit: TPCModule;
    begin
      LUnit := DoImported(AModule, 0);
      Check((DoCodes(AErrors) = '') and (LUnit <> nil) and
        TUtils.SamePath(LUnit.SourceFile, TPath.Combine(DoParDir(), 'mp\pa_mu.pcpp')),
        'import: @addmodulepath finds a unit in another directory');
    end);
end;

procedure TPCParserTests.DoTestImportGraph();
begin
  DoWith('pa12_diamond.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LB: TPCModule;
      LC: TPCModule;
    begin
      LB := DoImported(AModule, 0);
      LC := DoImported(AModule, 1);
      Check((DoCodes(AErrors) = '') and (AAst.ModuleCount() = 4),
        'import_graph: a diamond registers four modules');
      Check((DoImported(LB, 0) <> nil) and (DoImported(LB, 0) = DoImported(LC, 0)),
        'import_graph: the shared unit is parsed once and linked twice');
    end);
  DoWith('pa13_cycle.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_011) and
        DoFirstMessage(AErrors).Contains('pa13_cycle -> pa_ca -> pa_cb -> pa_ca'),
        'import_graph: A -> B -> A is one PR0011 naming the chain');
    end);
  Check(DoCodesOf('pa14_self.pcpp') = PC_ERR_PAR_011,
    'import_graph: a unit importing itself is PR0011, no recursion');
end;

procedure TPCParserTests.DoTestModulePaths();
var
  LMp: string;
  LTwin: string;
begin
  // TPCParser.AddModulePath on a parser created directly (DoWithParser)
  LMp := TPath.Combine(DoParDir(), 'mp');
  LTwin := TPath.Combine(DoParDir(), 'twin');
  DoWithParser('pa28_addpath.pcpp', nil,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = PC_ERR_PAR_012,
        'module_paths: with no module path a unit outside the own folder is PR0012 (' + DoCodes(AErrors) + ')');
    end);
  DoWithParser('pa28_addpath.pcpp', [LMp],
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = '') and (DoImported(AModule, 0) <> nil) and
        TUtils.SamePath(DoImported(AModule, 0).SourceFile, TPath.Combine(LMp, 'pa_mu.pcpp')),
        'module_paths: AddModulePath finds a unit in that folder (' + DoCodes(AErrors) + ')');
    end);
  DoWithParser('pa15_missing.pcpp', [LMp, LMp.Replace('\', '/'), LMp],
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LMessage: string;
      LResolved: string;
    begin
      LMessage := DoFirstMessage(AErrors);
      LResolved := TUtils.ResolvePath(LMp);
      Check((DoCodes(AErrors) = PC_ERR_PAR_012) and LMessage.Contains(LResolved) and
        (LMessage.IndexOf(LResolved) = LMessage.LastIndexOf(LResolved)),
        'module_paths: one folder added three times (two spellings) is searched once (' + LMessage + ')');
    end);
  DoWithParser('pa29_order.pcpp', [LTwin],
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LMessage: string;
      LTwinAt: Integer;
      LMpAt: Integer;
    begin
      // searched: <own folder>, <twin (AddModulePath)>, <mp (@addmodulepath)>
      LMessage := DoFirstMessage(AErrors);
      LTwinAt := LMessage.IndexOf(', ' + TUtils.ResolvePath(LTwin) + ',');
      LMpAt := LMessage.IndexOf(', ' + TUtils.ResolvePath(LMp) + ')');
      Check((DoCodes(AErrors) = PC_ERR_PAR_012) and (LTwinAt > 0) and (LMpAt > LTwinAt),
        'module_paths: own folder, then AddModulePath folders, then @addmodulepath folders (' + LMessage + ')');
    end);
  DoWithParser('pa30_chain.pcpp', [LMp, LTwin],
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LUnit: TPCModule;
    begin
      LUnit := DoImported(AModule, 0);
      Check((DoCodes(AErrors) = '') and (LUnit <> nil) and (DoImported(LUnit, 0) <> nil) and
        TUtils.SamePath(DoImported(LUnit, 0).SourceFile, TPath.Combine(LTwin, 'pa_t2.pcpp')),
        'module_paths: an import''s parser searches the main parser''s folders (' + DoCodes(AErrors) + ')');
    end);
  DoWithParser('pa28_addpath.pcpp', ['in<valid'],
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = PC_ERR_PAR_056 + ',' + PC_ERR_PAR_012,
        'module_paths: a path that cannot be resolved is PR0056 and not added (' + DoCodes(AErrors) + ')');
    end);
  // ParseModuleFile adds its AModulePaths the same way (the compiler's path)
  DoWithPath(TPath.Combine(DoParDir(), 'pa28_addpath.pcpp'),
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = PC_ERR_PAR_012,
        'module_paths: ParseModuleFile with no paths adds none');
    end);
end;

procedure TPCParserTests.DoTestImportErrors();
begin
  DoWith('pa15_missing.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_012) and DoFirstMessage(AErrors).Contains('pa_nothere') and
        (AModule.Imports.Count = 1) and (AModule.Imports[0].ImportedModule = nil),
        'import_errors: a missing unit is PR0012, the import kept unlinked');
    end);
  Check(DoCodesOf('pa16_implib.pcpp') = PC_ERR_PAR_013,
    'import_errors: importing a lib is PR0013');
  DoWith('pa18_dup.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_014) and (AModule.Imports.Count = 1),
        'import_errors: a duplicate name in the clause is PR0014, skipped');
    end);
  // A late clause is PR0010 and parsed as the clause it is (PLAN-RECOVERY A7
  // step 7): its name, already imported, is the duplicate PR0014
  Check(DoCodesOf('pa19_late.pcpp') = PC_ERR_PAR_010 + ',' + PC_ERR_PAR_014,
    'import_errors: a second import clause is PR0010, parsed (got ' +
    DoCodesOf('pa19_late.pcpp') + ')');
  Check(DoCodesOf('pa22_kind.pcpp') = PC_ERR_PAR_002,
    'import_errors: an imported file with no kind is PR0002 only, no PR0013');
end;

procedure TPCParserTests.DoTestIdentity();
begin
  DoWith('pa20_ident.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LShared: TPCModule;
    begin
      LShared := DoImported(DoImported(AModule, 0), 0);
      Check((DoCodes(AErrors) = PC_ERR_PAR_003) and (AAst.ModuleCount() = 4),
        'identity: a unit whose name differs from its file is PR0003 once, no AS0001');
      Check((LShared <> nil) and (LShared.ModuleName = 'bb') and
        (LShared = DoImported(DoImported(AModule, 1), 0)),
        'identity: found by its file, parsed once');
    end);
  DoWith('pa21_lexer.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LShared: TPCModule;
    begin
      LShared := DoImported(DoImported(AModule, 0), 0);
      Check((DoCodes(AErrors) = PC_ERR_LEX_004) and (AAst.ModuleCount() = 4),
        'identity: a unit with a lexer error reports it once, registered once (got ' +
        DoReports(AErrors) + '; modules ' + IntToStr(AAst.ModuleCount()) + ')');
      Check((LShared <> nil) and (LShared.ModuleName = 'pa_lx') and
        (LShared = DoImported(DoImported(AModule, 1), 0)),
        'identity: the lexer-failed unit keeps its header and is linked twice');
      Check((LShared <> nil) and (not LShared.ResolvedTarget.IsEmpty()) and
        (LShared.ResolvedTarget.ToLLVM() = AModule.ResolvedTarget.ToLLVM()),
        'identity: the lexer-failed unit still takes the main module''s triple');
    end);
  DoWith('pa23_twin.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LCore: TPCModule;
      LTwin: TPCModule;
    begin
      LCore := DoImported(DoImported(AModule, 0), 0);
      LTwin := DoImported(DoImported(AModule, 1), 0);
      Check((DoCodes(AErrors) = PC_ERR_AST_001) and (AAst.ModuleCount() = 5),
        'identity: two files with one module name: one AS0001');
      Check((LCore <> nil) and (LTwin <> nil) and (LCore <> LTwin) and
        (LTwin = DoImported(DoImported(AModule, 2), 0)),
        'identity: the rejected file is found by file, never parsed twice');
    end);
end;

procedure TPCParserTests.DoTestModuleEnd();
begin
  Check(DoCodesOf('pa25_after.pcpp') = PC_ERR_PAR_020,
    'module_end: a token after end. is PR0020');
  DoWith('pa26_noend.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_001) and DoFirstMessage(AErrors).Contains(RSParEndOfFile),
        'module_end: a missing end is one PR0001 at the end of file');
    end);
end;

procedure TPCParserTests.DoTestRanges();
begin
  // pa10_ranges.pcpp: 'module lib pa10_ranges;' CRLF '@optimize speed;' CRLF 'end.'
  // = bytes 0..23, 25..41, 43..47 (end offsets exclusive)
  DoWith('pa10_ranges.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = '') and (AModule.Range.StartByteOffset = 0) and
        (AModule.Range.EndByteOffset = 47) and (AModule.Range.StartLine = 1) and
        (AModule.Range.EndLine = 3), 'ranges: module = module .. end.');
      if AModule.Directives.Count <> 1 then
        Exit;
      Check((AModule.Directives[0].Range.StartByteOffset = 25) and
        (AModule.Directives[0].Range.EndByteOffset = 41) and
        (AModule.Directives[0].Range.StartLine = 2) and (AModule.Directives[0].Range.EndLine = 2),
        'ranges: directive = @ .. ;');
      Check((AModule.Directives[0].Args[0].Range.StartByteOffset = 35) and
        (AModule.Directives[0].Args[0].Range.EndByteOffset = 40),
        'ranges: argument = its token');
    end);
end;

procedure TPCParserTests.DoTestSpans();
begin
  // pb01_spans: line 2 starts at byte 24 ('module lib pb01_spans;' + CR LF)
  DoWith('pb01_spans.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LSpan: TPCVerbatimStmt;
      LHash: TPCVerbatimStmt;
      LLast: TPCVerbatimStmt;
      LText: string;
    begin
      LSpan := DoVerbatimAt(AModule, 0);
      LHash := DoVerbatimAt(AModule, 1);
      LLast := DoVerbatimAt(AModule, 2);
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 3) and (LSpan <> nil) and
        (LHash <> nil) and (LLast <> nil), 'spans: span, # line, span');
      if (AModule.Decls.Count <> 3) or (LSpan = nil) or (LHash = nil) or (LLast = nil) then
        Exit;
      // Two functions, a struct, a C++ const and a using: ONE span
      LText := 'int f() { return 1; }' + PC_TEST_CRLF + 'struct S { int a; };' + PC_TEST_CRLF +
        'const int X = 5;' + PC_TEST_CRLF + 'using type = int;';
      Check((LSpan.Verbatim.VerbatimKind = vkCppDecl) and (LSpan.Verbatim.EmitTarget = etSource) and
        (LSpan.Verbatim.Text = LText), 'spans: one vkCppDecl span, placement source, exact text');
      Check((LSpan.Range.StartByteOffset = 24) and (LSpan.Range.StartLine = 2) and
        (LSpan.Range.EndLine = 5) and
        (LSpan.Range.EndByteOffset = 24 + UInt64(TEncoding.UTF8.GetByteCount(LText))) and
        (LSpan.Verbatim.Range.StartByteOffset = LSpan.Range.StartByteOffset) and
        (LSpan.Verbatim.Range.EndByteOffset = LSpan.Range.EndByteOffset),
        'spans: node and verbatim range = first token .. last token');
      // No cpp header; before it: the default placement, source (preproc_placement
      // checks the switch)
      Check((LHash.Verbatim.VerbatimKind = vkPreproc) and (LHash.Verbatim.EmitTarget = etSource) and
        (LHash.Verbatim.Text = '#include <cstdio>') and (LHash.Range.StartLine = 6),
        'spans: a depth-0 # line is its own node, placement source');
      Check((LLast.Verbatim.VerbatimKind = vkCppDecl) and (LLast.Verbatim.Text = 'int g();'),
        'spans: C++ after the # line opens a new span that ends before end');
    end);
end;

procedure TPCParserTests.DoTestDigraphs();
begin
  // A digraph is its canonical token in mixed C++ and in PaskalCPP code (user
  // 2026-10-07: accepted silently); %: first on its line is a # line
  // (research\cppmix\digraphs\)
  DoWith('pdg01_span.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LSpan: TPCVerbatimStmt;
      LHash: TPCVerbatimStmt;
      LLast: TPCVerbatimStmt;
      LVector: TPCCppType;
    begin
      LSpan := DoVerbatimAt(AModule, 0);
      LHash := DoVerbatimAt(AModule, 3);
      LLast := DoVerbatimAt(AModule, 4);
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 5) and (LSpan <> nil) and
        (DoVarAt(AModule, 1) <> nil) and (DoVarAt(AModule, 2) <> nil) and (LHash <> nil) and
        (LLast <> nil), 'digraphs: span, var, var, %: line, span (got ''' + DoCodes(AErrors) +
        ''', ' + IntToStr(AModule.Decls.Count) + ' decls)');
      if (AModule.Decls.Count <> 5) or (LSpan = nil) or (LHash = nil) or (LLast = nil) or
        (DoVarAt(AModule, 1) = nil) or (DoVarAt(AModule, 2) = nil) then
        Exit;
      Check((LSpan.Verbatim.VerbatimKind = vkCppDecl) and
        (LSpan.Verbatim.Text = 'int f() <% int a<:2:> = <%1, 2%>; return a<:0:>; %>'),
        'digraphs: %> at depth 0 ends the C++ span, text exact');
      Check(DoExprText(DoInitAt(AModule, 1)) = 'LA[0]', 'digraphs: LA<:0:> in PaskalCPP code is an index');
      LVector := DoCppAt(AModule, 2);
      Check((LVector <> nil) and (DoPartsText(LVector) = 'std::vector') and
        (DoArgAt(LVector, 1, 0) <> nil) and (DoArgAt(LVector, 1, 1) = nil),
        'digraphs: std::vector<::std::string> keeps < :: (C++11), one template argument');
      Check((LHash.Verbatim.VerbatimKind = vkPreproc) and (LHash.Verbatim.EmitTarget = etSource) and
        (LHash.Verbatim.Text = '%:include <cstdio>') and (LHash.Range.StartLine = 6),
        'digraphs: %: first on its line is its own # line node, placement source');
      Check((LLast.Verbatim.VerbatimKind = vkCppDecl) and (LLast.Verbatim.Text = 'int g();'),
        'digraphs: C++ after the %: line is a new span');
    end);
  DoCheckStmts(Self, 'digraphs', 'pdg02_body.pcpp', PC_TEST_STMT_DIGRAPHS);
end;

procedure TPCParserTests.DoTestPlacement();
begin
  DoWith('pb02_place.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LA: TPCVerbatimStmt;
      LB: TPCVerbatimStmt;
      LC: TPCVerbatimStmt;
    begin
      LA := DoVerbatimAt(AModule, 0);
      LB := DoVerbatimAt(AModule, 1);
      LC := DoVerbatimAt(AModule, 2);
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 3) and (LA <> nil) and
        (LB <> nil) and (LC <> nil), 'placement: three spans, no node for cpp header|source');
      if (AModule.Decls.Count <> 3) or (LA = nil) or (LB = nil) or (LC = nil) then
        Exit;
      Check((LA.Verbatim.EmitTarget = etSource) and (LB.Verbatim.EmitTarget = etHeader) and
        (LC.Verbatim.EmitTarget = etSource) and (LB.Verbatim.Text = 'int b;'),
        'placement: source by default, cpp header stamps the next span, cpp source back');
    end);
  // A module-level # line follows the same switch (user 2026-10-17)
  DoWith('pb02_place_preproc.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LA: TPCVerbatimStmt;
      LB: TPCVerbatimStmt;
      LC: TPCVerbatimStmt;
    begin
      LA := DoVerbatimAt(AModule, 0);
      LB := DoVerbatimAt(AModule, 1);
      LC := DoVerbatimAt(AModule, 2);
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 3) and (LA <> nil) and
        (LB <> nil) and (LC <> nil), 'placement: three # lines, no node for cpp header|source');
      if (AModule.Decls.Count <> 3) or (LA = nil) or (LB = nil) or (LC = nil) then
        Exit;
      Check((LA.Verbatim.VerbatimKind = vkPreproc) and (LA.Verbatim.EmitTarget = etSource) and
        (LB.Verbatim.VerbatimKind = vkPreproc) and (LB.Verbatim.EmitTarget = etHeader) and
        (LC.Verbatim.VerbatimKind = vkPreproc) and (LC.Verbatim.EmitTarget = etSource) and
        (LB.Verbatim.Text = '#include <cstdio>'),
        'placement: a # line is source by default, header after cpp header, source again');
    end);
end;

procedure TPCParserTests.DoTestCppBlock();
begin
  // pb03_block: line 3 'cppstart source' starts at byte 37, its text at 52
  DoWith('pb03_block.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LSource: TPCVerbatimStmt;
      LHeader: TPCVerbatimStmt;
    begin
      LSource := DoVerbatimAt(AModule, 0);
      LHeader := DoVerbatimAt(AModule, 1);
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 2) and (LSource <> nil) and
        (LHeader <> nil), 'cpp_block: two blocks');
      if (AModule.Decls.Count <> 2) or (LSource = nil) or (LHeader = nil) then
        Exit;
      Check((LSource.Verbatim.VerbatimKind = vkCppBlock) and
        (LSource.Verbatim.EmitTarget = etSource) and
        (LSource.Verbatim.Text = PC_TEST_CRLF + '  int q = 1;' + PC_TEST_CRLF),
        'cpp_block: its own word wins over cpp header; text untrimmed');
      Check((LSource.Range.StartByteOffset = 37) and (LSource.Range.StartLine = 3) and
        (LSource.Range.EndLine = 5) and (LSource.Verbatim.Range.StartByteOffset = 52) and
        (LSource.Verbatim.Range.EndByteOffset =
        52 + UInt64(TEncoding.UTF8.GetByteCount(LSource.Verbatim.Text))),
        'cpp_block: node = cppstart .. ;, verbatim = the text''s own range');
      Check((LHeader.Verbatim.EmitTarget = etHeader) and (LHeader.Verbatim.Text = PC_TEST_CRLF),
        'cpp_block: cppstart header');
    end);
end;

procedure TPCParserTests.DoTestCppJumps();
begin
  // O-S6b (research\cppmix\sem\prereq-b\jump.md Tests): a body block keeps its
  // escaping jumps and dumps them; a module-level block has none, even with a
  // jump word that would escape in a body; a header block in a body is PR0051
  // and dropped. Fixtures: scripts\zb_sem\pb\gen_pjumps.py (hand marks equal
  // jump_probe.py's reference walker)
  DoWithPath(TPath.Combine(DoJumpsDir(), 'pj01_body.pcpp'),
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LModuleBlock: TPCVerbatimStmt;
      LBodyBlock: TPCVerbatimStmt;
    begin
      LModuleBlock := DoVerbatimAt(AModule, 0);
      LBodyBlock := nil;
      if (AModule.Body <> nil) and (AModule.Body.Stmts.Count = 1) and
        (AModule.Body.Stmts[0] is TPCVerbatimStmt) then
        LBodyBlock := TPCVerbatimStmt(AModule.Body.Stmts[0]);
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 1) and (LModuleBlock <> nil) and
        (LBodyBlock <> nil),
        'cpp_jumps: one module-level block, one body block (got ''' + DoCodes(AErrors) + ''')');
      if (LModuleBlock = nil) or (LBodyBlock = nil) then
        Exit;
      Check((Length(LModuleBlock.Verbatim.EscapingJumps) = 0) and
        (not LModuleBlock.Dump().Contains(' jumps=')),
        'cpp_jumps: a module-level block has no escaping jumps (its return would escape in a body)');
      Check((Length(LBodyBlock.Verbatim.EscapingJumps) = 2) and
        (LBodyBlock.Verbatim.EscapingJumps[0].Kind = cjReturn) and
        (LBodyBlock.Verbatim.EscapingJumps[1].Kind = cjContinue) and
        LBodyBlock.Dump().Contains(' jumps=[return@7:10 continue@9:40]'),
        'cpp_jumps: a body block keeps return@7:10 continue@9:40, the breaks stay inside (got ' +
        LBodyBlock.Dump().Trim() + ')');
    end);
  DoWithPath(TPath.Combine(DoJumpsDir(), 'pj02_header.pcpp'),
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      // Kept as the fragment of an error node (PLAN-RECOVERY A7 step 9)
      Check((DoCodes(AErrors) = PC_ERR_PAR_051) and (AModule.Body <> nil) and
        (AModule.Body.Stmts.Count = 1) and (AModule.Body.Stmts[0] is TPCErrorStmt) and
        (TPCErrorStmt(AModule.Body.Stmts[0]).Fragment is TPCVerbatimStmt),
        'cpp_jumps: a header block in a body is PR0051, an error node''s fragment (got ''' +
        DoCodes(AErrors) + ''')');
    end);
end;

procedure TPCParserTests.DoTestCppErrors();
begin
  DoWith('pb04_cpperr.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      // Each skip is an error node (PLAN-RECOVERY A7 steps 8, 9)
      Check((DoCodes(AErrors) = PC_ERR_PAR_015 + ',' + PC_ERR_PAR_015 + ',' + PC_ERR_PAR_015) and
        (DoRecoveryOutline(AModule) = 'ErrorStmt,ErrorStmt,ErrorStmt'),
        'cpp_errors: cpp foo, cpp(...) and cppstart foo are one PR0015 each, an error node each (got ' +
        DoRecoveryOutline(AModule) + ')');
    end);
end;

procedure TPCParserTests.DoTestSections();
begin
  DoWith('pb05_sect.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LInit: TPCRoutine;
      LFinal: TPCRoutine;
    begin
      LInit := AModule.InitRoutine;
      LFinal := AModule.FinalRoutine;
      Check((DoCodes(AErrors) = '') and (LInit <> nil) and (LFinal <> nil),
        'sections: initialize and finalize parsed');
      if (LInit = nil) or (LFinal = nil) then
        Exit;
      Check((LInit.DeclName = 'initialize') and (LInit.RoutineKind = rnRoutine) and
        (LInit.Params.Count = 0) and (LInit.ReturnType = nil) and (LInit.Body <> nil) and
        (LInit.Range.StartLine = 2) and (LInit.Range.EndLine = 4) and
        (LFinal.DeclName = 'finalize') and (LFinal.Body <> nil) and
        (LFinal.Range.StartLine = 5) and (LFinal.Range.EndLine = 7),
        'sections: each a routine named by its keyword, range keyword .. ;');
      if LInit.Body = nil then
        Exit;
      Check((LInit.Body.Stmts.Count = 0) and (LInit.Body.Range.StartLine = 3) and
        (LInit.Body.Range.EndLine = 4), 'sections: the body block = begin .. end');
    end);
end;

procedure TPCParserTests.DoTestSectionErrors();
begin
  DoWith('pb06a_order.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_018) and (AModule.FinalRoutine <> nil) and
        (AModule.InitRoutine = nil),
        'section_errors: initialize after finalize is PR0018, not stored');
    end);
  DoWith('pb06b_twice.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_018) and (AModule.InitRoutine <> nil) and
        (AModule.InitRoutine.Range.StartLine = 2),
        'section_errors: a second initialize is PR0018, the first kept');
    end);
  DoWith('pb06c_nobegin.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_001) and DoFirstMessage(AErrors).Contains('''begin''') and
        (AModule.InitRoutine <> nil) and (AModule.InitRoutine.Body = nil),
        'section_errors: a section without begin is one PR0001');
    end);
end;

procedure TPCParserTests.DoTestBody();
begin
  DoWith('pb07a_body.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = '') and AModule.HasBody and (AModule.Body <> nil),
        'body: an exe body');
      if AModule.Body = nil then
        Exit;
      Check((AModule.Body.Stmts.Count = 0) and (AModule.Body.Range.StartLine = 2) and
        (AModule.Body.Range.EndLine = 2), 'body: range = begin .. its last statement (none)');
    end);
  DoWith('pb07b_libbody.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_016) and AModule.HasBody and
        DoFirstMessage(AErrors).Contains('lib'), 'body: begin in a lib is PR0016, parsed anyway');
    end);
  Check(DoCodesOf('pb07c_nobody.pcpp') = PC_ERR_PAR_017, 'body: an exe without begin is PR0017');
  Check(DoCodesOf('pa01_exe.pcpp') = '', 'body: the CORE-A exe fixture parses clean');
end;

procedure TPCParserTests.DoTestTestBlocks();
begin
  DoWith('pb08a_testplace.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_019) and (AModule.Tests.Count = 1),
        'test_blocks: a test before end. is PR0019, still parsed');
    end);
  DoWith('pb08b_test.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LTest: TPCTest;
    begin
      Check((DoCodes(AErrors) = '') and (AModule.Tests.Count = 1), 'test_blocks: one test after end.');
      if AModule.Tests.Count <> 1 then
        Exit;
      LTest := AModule.Tests[0];
      Check((LTest.TestName <> nil) and (LTest.Body <> nil) and (LTest.Range.StartLine = 3) and
        (LTest.Range.EndLine = 3), 'test_blocks: name, body, range test .. ;');
      if LTest.TestName = nil then
        Exit;
      Check((LTest.TestName.LiteralKind = lkString) and (LTest.TestName.Text = '"t"') and
        (Length(LTest.TestName.Parts) = 1), 'test_blocks: the name is the literal as written');
      if Length(LTest.TestName.Parts) <> 1 then
        Exit;
      Check(LTest.TestName.Parts[0].HasValue and (LTest.TestName.Parts[0].Value = 't'),
        'test_blocks: the name keeps its decoded value');
    end);
  Check(DoCodesOf('pb08c_testname.pcpp') = PC_ERR_PAR_009, 'test_blocks: a prefixed name is PR0009');
end;

procedure TPCParserTests.DoTestRecovery();
begin
  Check(DoCodesOf('pb09_recover.pcpp') = PC_ERR_PAR_005 + ',' + PC_ERR_PAR_015,
    'recovery: an unknown directive and cpp foo are reported, nothing else');
  Check(DoCodesOf('pb13_trunc.pcpp') = PC_ERR_PAR_001,
    'recovery: a file cut inside a section reports the end of file once');
end;

procedure TPCParserTests.DoTestRecoveryNodes();
var
  LAst: TPCAst;
  LStmt: TPCErrorStmt;
  LExpr: TPCErrorExpr;
  LMember: TPCErrorMember;
  LRoutine: TPCRoutine;
  LFirst: TPCName;
  LSecond: TPCName;
  LVar: TPCVarDecl;
  LSeen: TList<TPCNode>;
  LPlain: string;
begin
  // The three error nodes and the recovered mark (PLAN-RECOVERY A1); pure,
  // no fixture
  LAst := TPCAst.Create();
  LSeen := TList<TPCNode>.Create();
  try
    LStmt := LAst.NewNode<TPCErrorStmt>();
    LExpr := LAst.NewNode<TPCErrorExpr>();
    LMember := LAst.NewNode<TPCErrorMember>();
    Check((LStmt.NodeKind = nkErrorStmt) and (LStmt.KindName() = 'ErrorStmt'),
      'recovery_nodes: the error statement has its own kind');
    Check((LExpr.NodeKind = nkErrorExpr) and (LExpr.KindName() = 'ErrorExpr'),
      'recovery_nodes: the error expression has its own kind');
    Check((LMember.NodeKind = nkErrorMember) and (LMember.KindName() = 'ErrorMember'),
      'recovery_nodes: the error member has its own kind');

    // A fragment is the error statement's one child
    LRoutine := LAst.NewNode<TPCRoutine>();
    LRoutine.DeclName := 'F';
    LStmt.Fragment := LRoutine;
    Check(LStmt.Dump().StartsWith('ErrorStmt' + sLineBreak + '  Routine'),
      'recovery_nodes: an error statement dumps its fragment one level deeper');

    // Parts are enumerated in source order
    LFirst := LAst.NewNode<TPCName>();
    LSecond := LAst.NewNode<TPCName>();
    LExpr.Parts.Add(LFirst);
    LExpr.Parts.Add(LSecond);
    LExpr.EnumChildren(
      procedure(const AChild: TPCNode)
      begin
        LSeen.Add(AChild);
      end);
    Check((LSeen.Count = 2) and (LSeen[0] = LFirst) and (LSeen[1] = LSecond),
      'recovery_nodes: an error expression enumerates its parts in order');

    // The mark is the last thing on a node's dump line
    LVar := LAst.NewNode<TPCVarDecl>();
    LVar.DeclName := 'A';
    LPlain := LVar.Dump();
    LVar.IsRecovered := True;
    Check(LVar.Dump() = LPlain.Replace(sLineBreak, ' recovered' + sLineBreak),
      'recovery_nodes: a recovered node dumps its usual line + recovered');
  finally
    LSeen.Free();
    LAst.Free();
  end;
end;

procedure TPCParserTests.DoTestRecoveryRows();
var
  LDir: string;
  LLines: TArray<string>;
  LLine: string;
  LParts: TArray<string>;
  LCodes: string;
  LOutline: string;
  LReports: string;
begin
  // The PLAN-RECOVERY parser rows (scripts\zb_ed\gen_recovery.py, one table):
  // each fixture's codes and outline exactly as its row states; a failure
  // prints every report with its line
  LDir := DoProbeDir('par\recovery');
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
    LOutline := '';
    LReports := '';
    DoWithPath(TPath.Combine(LDir, LParts[0] + '.pcpp'),
      procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
      begin
        LCodes := DoCodes(AErrors);
        LReports := DoReports(AErrors);
        LOutline := DoRecoveryOutline(AModule);
      end);
    Check((LCodes = LParts[1]) and (LOutline = LParts[2]),
      'recovery_rows: ' + LParts[0] + ' gives ' + LParts[1] + ' | ' + LParts[2] +
      ' (got ' + LCodes + ' | ' + LOutline + '; reports: ' + LReports + ')');
  end;
end;

function DoSkipOperandRow(const ARow: TPCTokenRow): Boolean;
begin
  // Tokens with no mid-line form (the filter's and the lexer's line tokens)
  Result := (ARow.Text = '') or ARow.Text.StartsWith('@') or ARow.Text.StartsWith('#') or
    (ARow.Kind = tkDirective) or (ARow.Kind = tkCppPreprocessor) or
    (ARow.Kind = tkKwCppstart) or (ARow.Kind = tkRawBlock);
end;

function DoLexedAt(const ASource: string; const AOffset: UInt64; out AToken: TPCToken): Boolean;
var
  LErrors: TErrors;
  LStream: TPCTokenStream;
  LLexer: TPCLexer;
  LIndex: Integer;
begin
  // The token a plain lex of ASource starts at AOffset (False = none)
  Result := False;
  AToken.Clear();
  LErrors := TErrors.Create();
  LStream := TPCTokenStream.Create();
  LLexer := TPCLexer.Create();
  try
    LErrors.SetMaxErrors(100);
    LLexer.SetErrors(LErrors);
    LLexer.TokenizeBytes(TEncoding.UTF8.GetBytes(ASource), 'operand.pcpp', LStream);
    for LIndex := 0 to LStream.Count() - 1 do
    begin
      if LStream.TokenAt(LIndex).Range.StartByteOffset = AOffset then
      begin
        AToken := LStream.TokenAt(LIndex);
        Exit(True);
      end;
    end;
  finally
    LLexer.Free();
    LStream.Free();
    LErrors.Free();
  end;
end;

procedure TPCParserTests.DoTestOperandStarts();
const
  CSamples: array[0..4] of string = ('x', '1', '1.0', '''c''', '"s"');
var
  LTexts: TList<string>;
  LRow: TPCTokenRow;
  LText: string;
  LDir: string;
  LPath: string;
  LPrefix: string;
  LSource: string;
  LOffset: UInt64;
  LToken: TPCToken;
  LReported: Boolean;
  LMismatch: string;
  LChecked: Integer;
begin
  // PLAN-RECOVERY A11 T3: TPCParser.StartsOperand (the insertion rule's
  // operand test) agrees with what DoParseUnary takes: every spelling as S in
  // 'x := S (x);' starts an operand exactly when no report starts at S
  LDir := TPath.Combine(TPath.GetTempPath(), 'pcpp-operand');
  LPath := TPath.Combine(LDir, 't.pcpp');
  try
    TDirectory.CreateDirectory(LDir);
  except
    on E: Exception do
    begin
      Check(False, 'operand_starts: the temp folder cannot be made: ' + E.Message);
      Exit;
    end;
  end;
  LPrefix := 'module lib t;'#13#10'routine R();'#13#10'var x: int32;'#13#10'begin'#13#10'  x := ';
  LOffset := UInt64(TEncoding.UTF8.GetByteCount(LPrefix));
  LMismatch := '';
  LChecked := 0;
  LTexts := TList<string>.Create();
  try
    for LRow in PC_PASKAL_TOKENS do
    begin
      if not DoSkipOperandRow(LRow) then
        LTexts.Add(LRow.Text);
    end;
    for LRow in PC_CPP_TOKENS do
    begin
      if not DoSkipOperandRow(LRow) then
        LTexts.Add(LRow.Text);
    end;
    for LText in CSamples do
      LTexts.Add(LText);
    for LText in LTexts do
    begin
      LSource := LPrefix + LText + ' (x);'#13#10'end;'#13#10'end.';
      if not DoLexedAt(LSource, LOffset, LToken) then
        Continue;
      try
        // Bytes without a BOM: the offsets must equal the reference lex's
        TFile.WriteAllBytes(LPath, TEncoding.UTF8.GetBytes(LSource));
      except
        on E: Exception do
        begin
          Check(False, 'operand_starts: the fixture cannot be written: ' + E.Message);
          Exit;
        end;
      end;
      LReported := False;
      DoWithPath(LPath,
        procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
        var
          LError: TError;
        begin
          // "Expected an expression" at S: a hint such as PR0040 (compl /
          // bitand, parsed as ~ / &) stands at S on an operand too
          for LError in AErrors.GetItems() do
          begin
            if (LError.Range.StartByteOffset = LOffset) and (LError.Code = PC_ERR_PAR_001) then
              LReported := True;
          end;
        end);
      Inc(LChecked);
      if TPCParser.StartsOperand(LToken) = LReported then
        LMismatch := LMismatch + ' ' + LText;
    end;
  finally
    LTexts.Free();
  end;
  Check((LChecked > 200) and (LMismatch = ''),
    'operand_starts: StartsOperand agrees with the parser for ' + IntToStr(LChecked) +
    ' spellings (disagree:' + LMismatch + ')');
end;

procedure TPCParserTests.DoTestF1();
begin
  DoWith('pb10_f1.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LSpan: TPCVerbatimStmt;
      LText: string;
    begin
      LSpan := DoVerbatimAt(AModule, 0);
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 1) and (LSpan <> nil),
        'f1: one span across the @ifdef');
      if (AModule.Decls.Count <> 1) or (LSpan = nil) then
        Exit;
      // '@ifdef NOPE' and '  return 1;' are 11 bytes, '@endif' 6: all spaces
      LText := 'int f() {' + PC_TEST_CRLF + StringOfChar(' ', 11) + PC_TEST_CRLF +
        StringOfChar(' ', 11) + PC_TEST_CRLF + StringOfChar(' ', 6) + PC_TEST_CRLF +
        '  return 2;' + PC_TEST_CRLF + '}';
      Check(LSpan.Verbatim.Text = LText,
        'f1: dropped bytes are spaces, CR LF kept, active bytes unchanged');
      Check(UInt64(TEncoding.UTF8.GetByteCount(LSpan.Verbatim.Text)) =
        LSpan.Verbatim.Range.EndByteOffset - LSpan.Verbatim.Range.StartByteOffset,
        'f1: Text has exactly the range''s bytes');
    end);
end;

procedure TPCParserTests.DoTestInsideLines();
begin
  DoWith('pb11_inside.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LSpan: TPCVerbatimStmt;
      LHash: TPCVerbatimStmt;
      LBlock: TPCVerbatimStmt;
    begin
      LSpan := DoVerbatimAt(AModule, 0);
      LHash := DoVerbatimAt(AModule, 1);
      LBlock := DoVerbatimAt(AModule, 2);
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 3) and (LSpan <> nil) and
        (LHash <> nil) and (LBlock <> nil), 'inside_lines: span, # line, cppstart block');
      if (AModule.Decls.Count <> 3) or (LSpan = nil) or (LHash = nil) or (LBlock = nil) then
        Exit;
      Check(DoLinesText(LSpan.Verbatim.InsideLines) = '3,4',
        'inside_lines: a span marks the lines inside its raw string and its comment');
      Check(DoLinesText(LHash.Verbatim.InsideLines) = '6',
        'inside_lines: a # line continued by a block comment');
      Check(DoLinesText(LBlock.Verbatim.InsideLines) = '9,10',
        'inside_lines: a cppstart block marks only lines inside its C++ elements');
    end);
  DoWith('pb12_inside2.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LSpan: TPCVerbatimStmt;
    begin
      LSpan := DoVerbatimAt(AModule, 0);
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 1) and (LSpan <> nil) and
        (Length(LSpan.Verbatim.InsideLines) = 0),
        'inside_lines: a comment the filter dropped is blanked, its lines ordinary');
    end);
end;

procedure TPCParserTests.DoTestPaskalTypes();
begin
  DoWithExpr('pxa01_ptypes.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LType: TPCTypeExpr;
    begin
      // E: set; (line 7) is a bare set: PR0053 at 'set', the item kept,
      // marked, with no type (PLAN-RECOVERY A4)
      Check((DoCodes(AErrors) = 'PR0053') and (AModule.Decls.Count = 10),
        'ptypes: ten var items, the bare set reported (got ' + DoCodes(AErrors) + ')');
      Check((AErrors.Count() = 1) and (AErrors.GetItems()[0].Range.StartLine = 7) and
        (AErrors.GetItems()[0].Range.StartColumn = 6), 'ptypes: bare set is PR0053 at its set token');
      if AModule.Decls.Count <> 10 then
        Exit;
      LType := DoVarTypeAt(AModule, 0);
      Check((LType is TPCBuiltinType) and (TPCBuiltinType(LType).BuiltinToken = tkKwInt32),
        'ptypes: int32 is a builtin');
      LType := DoVarTypeAt(AModule, 1);
      Check((LType is TPCPointerType) and (TPCPointerType(LType).TargetType = nil),
        'ptypes: bare ptr has no target');
      LType := DoVarTypeAt(AModule, 2);
      Check((LType is TPCPointerType) and (TPCPointerType(LType).TargetType is TPCBuiltinType) and
        (not TPCPointerType(LType).IsConstTarget), 'ptypes: ptr to char');
      LType := DoVarTypeAt(AModule, 3);
      Check((LType is TPCPointerType) and TPCPointerType(LType).IsConstTarget and
        (TPCPointerType(LType).TargetType is TPCBuiltinType), 'ptypes: ptr to const char');
      // Index 4 is the bare set, kept marked with no type; F .. J follow
      Check((DoVarAt(AModule, 4) <> nil) and (DoVarAt(AModule, 4).DeclName = 'E') and
        DoVarAt(AModule, 4).IsRecovered and (DoVarAt(AModule, 4).TypeExpr = nil),
        'ptypes: the bare set item E is kept, marked, with no type');
      Check((DoVarAt(AModule, 5) <> nil) and (DoVarAt(AModule, 5).DeclName = 'F'),
        'ptypes: the item after the bare set is F');
      LType := DoVarTypeAt(AModule, 5);
      Check((LType is TPCArrayType) and TPCArrayType(LType).IsDynamic and
        (TPCArrayType(LType).ElementType is TPCBuiltinType), 'ptypes: array of int32 is dynamic');
      LType := DoVarTypeAt(AModule, 6);
      Check((LType is TPCArrayType) and TPCArrayType(LType).IsDynamic and
        (TPCArrayType(LType).ElementType is TPCNamedType), 'ptypes: array[] of TFoo is dynamic');
      LType := DoVarTypeAt(AModule, 7);
      Check((LType is TPCNamedType) and (string.Join('.', TPCNamedType(LType).Parts) = 'TFoo'),
        'ptypes: a bare name is a named type');
      LType := DoVarTypeAt(AModule, 8);
      Check((LType is TPCNamedType) and (string.Join('.', TPCNamedType(LType).Parts) = 'Geo.TFoo'),
        'ptypes: a dotted name is one qualified type');
      LType := DoVarTypeAt(AModule, 9);
      Check((LType is TPCBuiltinType) and (TPCBuiltinType(LType).BuiltinToken = tkKwBool),
        'ptypes: bool alone is the builtin');
      Check((DoVarAt(AModule, 0) <> nil) and (DoVarAt(AModule, 0).DeclName = 'A') and
        (DoVarAt(AModule, 0).Range.StartLine = 3) and (DoVarAt(AModule, 0).Range.EndLine = 3),
        'ptypes: an item ranges over identifier .. ;');
    end);
end;

procedure TPCParserTests.DoTestCppTypes();
begin
  DoWithExpr('pxa02_ctypes.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LCpp: TPCCppType;
    begin
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 16), 'ctypes: sixteen cpp types, no error');
      if AModule.Decls.Count <> 16 then
        Exit;
      LCpp := DoCppAt(AModule, 0);
      Check((LCpp <> nil) and (LCpp.LeadCv = [cqConst]) and (DoPartsText(LCpp) = 'std::string') and
        (LCpp.RefKind = rfLValue), 'ctypes: const std::string&');
      LCpp := DoCppAt(AModule, 1);
      Check((LCpp <> nil) and (LCpp.LeadCv = []) and (LCpp.TrailCv = [cqConst]) and
        (LCpp.RefKind = rfLValue), 'ctypes: std::string const&');
      LCpp := DoCppAt(AModule, 2);
      Check((LCpp <> nil) and (Length(LCpp.Fundamentals) = 1) and (LCpp.Fundamentals[0] = tkKwChar) and
        (LCpp.TrailCv = [cqConst]) and (Length(LCpp.PointerLevels) = 1) and
        (LCpp.PointerLevels[0] = [cqConst]), 'ctypes: char const* const');
      LCpp := DoCppAt(AModule, 3);
      Check((LCpp <> nil) and (LCpp.LeadCv = [cqVolatile]) and (DoPartsText(LCpp) = 'uint32_t') and
        (Length(LCpp.PointerLevels) = 1) and (LCpp.PointerLevels[0] = []), 'ctypes: volatile uint32_t*');
      LCpp := DoCppAt(AModule, 4);
      Check((LCpp <> nil) and (Length(LCpp.Fundamentals) = 3) and (LCpp.Fundamentals[0] = tkKwUnsigned) and
        (LCpp.Fundamentals[1] = tkKwLong) and (LCpp.Fundamentals[2] = tkKwLong), 'ctypes: unsigned long long');
      LCpp := DoCppAt(AModule, 5);
      Check((LCpp <> nil) and (Length(LCpp.Fundamentals) = 1) and (LCpp.Fundamentals[0] = tkKwInt) and
        (Length(LCpp.PointerLevels) = 2), 'ctypes: int**');
      LCpp := DoCppAt(AModule, 6);
      Check((LCpp <> nil) and LCpp.HasLeadingScope and (DoPartsText(LCpp) = '::set'),
        'ctypes: ::set, a keyword after :: is a name');
      LCpp := DoCppAt(AModule, 7);
      Check((LCpp <> nil) and (DoPartsText(LCpp) = 'std::ios::end'), 'ctypes: std::ios::end');
      LCpp := DoCppAt(AModule, 8);
      Check((LCpp <> nil) and LCpp.HasElaborated and (LCpp.ElaboratedKey = tkKwStruct) and
        (DoPartsText(LCpp) = 'stat'), 'ctypes: struct stat');
      LCpp := DoCppAt(AModule, 9);
      Check((LCpp <> nil) and (LCpp.LeadCv = [cqConst]) and LCpp.HasElaborated and
        (DoPartsText(LCpp) = 'sockaddr_in') and (Length(LCpp.PointerLevels) = 1),
        'ctypes: const struct sockaddr_in*');
      LCpp := DoCppAt(AModule, 10);
      Check((LCpp <> nil) and LCpp.HasElaborated and (LCpp.ElaboratedKey = tkKwEnum) and
        (DoPartsText(LCpp) = 'E'), 'ctypes: enum E');
      LCpp := DoCppAt(AModule, 11);
      Check((LCpp <> nil) and LCpp.HasDecltype and (LCpp.Decltype.Text = 'decltype(LX)') and
        (LCpp.Decltype.VerbatimKind = vkOpaqueGroup) and (LCpp.Decltype.EmitTarget = etInPlace) and
        (Length(LCpp.PointerLevels) = 1), 'ctypes: decltype(LX)* keeps the head verbatim');
      LCpp := DoCppAt(AModule, 12);
      Check((LCpp <> nil) and (Length(LCpp.Fundamentals) = 1) and (LCpp.Fundamentals[0] = tkKwWchar_t) and
        (Length(LCpp.PointerLevels) = 1), 'ctypes: wchar_t*');
      LCpp := DoCppAt(AModule, 13);
      Check((LCpp <> nil) and (Length(LCpp.Fundamentals) = 1) and (LCpp.Fundamentals[0] = tkKwChar8_t),
        'ctypes: char8_t');
      LCpp := DoCppAt(AModule, 14);
      Check((LCpp <> nil) and (Length(LCpp.Fundamentals) = 1) and (LCpp.Fundamentals[0] = tkKwBool) and
        (LCpp.RefKind = rfLValue), 'ctypes: bool& is the C++ fundamental');
      LCpp := DoCppAt(AModule, 15);
      Check((LCpp <> nil) and (DoPartsText(LCpp) = 'std::string') and (LCpp.RefKind = rfRValue),
        'ctypes: std::string&&');
    end);
end;

procedure TPCParserTests.DoTestTemplateArgs();
begin
  // A plain-name argument (int32_t, FILE) is an expression (T7): ExprArg TPCName
  DoWithExpr('pxa03_targs.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LCpp: TPCCppType;
      LArg: TPCTemplateArg;
      LInner: TPCTemplateArg;
    begin
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 8), 'targs: eight types, no error');
      if AModule.Decls.Count <> 8 then
        Exit;
      LCpp := DoCppAt(AModule, 0);
      LArg := DoArgAt(LCpp, 1, 0);
      Check((LCpp <> nil) and (Length(LCpp.PointerLevels) = 1) and (LArg <> nil) and
        (LArg.TypeArg is TPCCppType) and (DoPartsText(TPCCppType(LArg.TypeArg)) = 'std::vector') and
        (TPCCppType(LArg.TypeArg).NameParts.Count = 2) and
        TPCCppType(LArg.TypeArg).NameParts[1].HasTemplateArgs, 'targs: >> closes two lists, the * follows');
      LCpp := DoCppAt(AModule, 1);
      Check((LCpp <> nil) and (LCpp.NameParts.Count = 2) and LCpp.NameParts[1].HasTemplateArgs and
        (LCpp.NameParts[1].TemplateArgs.Count = 0), 'targs: std::less<> is an empty list');
      LArg := DoArgAt(DoCppAt(AModule, 2), 1, 0);
      Check((LArg <> nil) and (LArg.TypeArg is TPCPointerType), 'targs: ptr to char is a type arg');
      LCpp := DoCppAt(AModule, 3);
      LArg := DoArgAt(LCpp, 1, 1);
      Check((LCpp <> nil) and (LCpp.NameParts.Count = 2) and
        (LCpp.NameParts[1].TemplateArgs.Count = 2) and (LArg <> nil) and
        (LArg.TypeArg is TPCCppType) and TPCCppType(LArg.TypeArg).HasDecltype and
        (TPCCppType(LArg.TypeArg).Decltype.Text = 'decltype(&fclose)'), 'targs: decltype(&fclose) is a type arg');
      LArg := DoArgAt(DoCppAt(AModule, 4), 1, 0);
      Check((LArg <> nil) and LArg.HasVerbatim and (LArg.TypeArg = nil) and (LArg.ExprArg = nil) and
        (LArg.Verbatim.Text = 'int(int)') and (LArg.Verbatim.VerbatimKind = vkCppTypeId) and
        (LArg.Verbatim.EmitTarget = etInPlace), 'targs: int(int) is a verbatim cpp type id');
      LArg := DoArgAt(DoCppAt(AModule, 5), 0, 0);
      LInner := nil;
      if (LArg <> nil) and (LArg.TypeArg is TPCCppType) then
        LInner := DoArgAt(TPCCppType(LArg.TypeArg), 1, 0);
      Check((LInner <> nil) and LInner.HasVerbatim and (LInner.Verbatim.Text = 'int(int)'),
        'targs: X<std::function<int(int)>> splits the >>');
      LArg := DoArgAt(DoCppAt(AModule, 6), 0, 0);
      Check((LArg <> nil) and LArg.HasVerbatim and (LArg.Verbatim.Text = 'A<int>::template B<int>'),
        'targs: a cpp type id that ends on the first > of >> (T17)');
      LArg := DoArgAt(DoCppAt(AModule, 7), 1, 0);
      Check((LArg <> nil) and (LArg.TypeArg is TPCCppType) and
        (Length(TPCCppType(LArg.TypeArg).Fundamentals) = 1), 'targs: int is a type arg');
      LArg := DoArgAt(DoCppAt(AModule, 3), 1, 0);
      Check((LArg <> nil) and (LArg.ExprArg is TPCName) and (LArg.TypeArg = nil) and
        (not LArg.HasVerbatim), 'targs: FILE is an expression arg');
      LArg := DoArgAt(DoCppAt(AModule, 0), 1, 0);
      LInner := nil;
      if (LArg <> nil) and (LArg.TypeArg is TPCCppType) then
        LInner := DoArgAt(TPCCppType(LArg.TypeArg), 1, 0);
      Check((LInner <> nil) and (LInner.ExprArg is TPCName),
        'targs: int32_t in a nested list is an expression arg');
    end);
end;

procedure TPCParserTests.DoTestTypeDefs();
begin
  DoWithExpr('pxa04_typedefs.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LType: TPCTypeExpr;
      LRec: TPCRecordType;
      LMethod: TPCRoutine;
    begin
      // TG = set; (line 28) is a bare set: PR0053 at 'set', the decl kept,
      // marked, with no type definition (PLAN-RECOVERY A4)
      Check((DoCodes(AErrors) = 'PR0053') and (AModule.Decls.Count = 10),
        'typedefs: ten type decls, the bare set reported (got ' + DoCodes(AErrors) + ')');
      Check((AErrors.Count() = 1) and (AErrors.GetItems()[0].Range.StartLine = 28) and
        (AErrors.GetItems()[0].Range.StartColumn = 8), 'typedefs: bare set is PR0053 at its set token');
      if AModule.Decls.Count <> 10 then
        Exit;
      Check(DoTypeDefAt(AModule, 0) is TPCBuiltinType, 'typedefs: alias');
      LType := DoTypeDefAt(AModule, 1);
      Check((LType is TPCRecordType) and (not TPCRecordType(LType).IsObject) and
        TPCRecordType(LType).IsPacked and (TPCRecordType(LType).ParentName <> nil) and
        (string.Join('.', TPCRecordType(LType).ParentName.Parts) = 'Geo.TBase') and
        (TPCRecordType(LType).Members.Count = 2) and (TPCRecordType(LType).Members[0] is TPCField) and
        (TPCRecordType(LType).Members[1] is TPCAnonAggregate) and
        TPCAnonAggregate(TPCRecordType(LType).Members[1]).IsOverlay and
        (TPCAnonAggregate(TPCRecordType(LType).Members[1]).Members.Count = 2),
        'typedefs: record with an imported parent, packed, a field and an anon overlay');
      LType := DoTypeDefAt(AModule, 2);
      LMethod := nil;
      if (LType is TPCRecordType) and (TPCRecordType(LType).Members.Count = 2) and
        (TPCRecordType(LType).Members[1] is TPCMethodItem) then
        LMethod := TPCMethodItem(TPCRecordType(LType).Members[1]).Routine;
      Check((LType is TPCRecordType) and TPCRecordType(LType).IsObject and (LMethod <> nil) and
        (LMethod.RoutineKind = rnMethod) and (LMethod.DeclName = 'Get') and
        (LMethod.ReturnType is TPCBuiltinType) and (LMethod.Decls.Count = 1) and (LMethod.Body <> nil),
        'typedefs: object with a field and a method with a var block and a body');
      LType := DoTypeDefAt(AModule, 3);
      Check((LType is TPCOverlayType) and (TPCOverlayType(LType).Members.Count = 2) and
        (TPCOverlayType(LType).Members[1] is TPCAnonAggregate) and
        (not TPCAnonAggregate(TPCOverlayType(LType).Members[1]).IsOverlay) and
        TPCAnonAggregate(TPCOverlayType(LType).Members[1]).IsPacked and
        (TPCAnonAggregate(TPCOverlayType(LType).Members[1]).Members.Count = 2),
        'typedefs: overlay with a packed anon record');
      LType := DoTypeDefAt(AModule, 4);
      Check((LType is TPCChoicesType) and (TPCChoicesType(LType).Values.Count = 3) and
        (TPCChoicesType(LType).Values[2].ValueName = 'Blue') and
        (TPCChoicesType(LType).Values[0].ValueExpr = nil), 'typedefs: choices');
      LType := DoTypeDefAt(AModule, 5);
      Check((LType is TPCSetType) and (not TPCSetType(LType).IsRangeForm) and
        (TPCSetType(LType).ElementType is TPCNamedType), 'typedefs: set of TE');
      // Index 6 is the bare set TG, kept marked; TH .. TJ follow
      Check((AModule.Decls[6] is TPCTypeDecl) and (TPCTypeDecl(AModule.Decls[6]).DeclName = 'TG') and
        AModule.Decls[6].IsRecovered and (TPCTypeDecl(AModule.Decls[6]).TypeDef = nil),
        'typedefs: the bare set TG is kept, marked, with no type definition');
      Check((AModule.Decls[7] is TPCTypeDecl) and (TPCTypeDecl(AModule.Decls[7]).DeclName = 'TH'),
        'typedefs: the decl after the bare set is TH');
      LType := DoTypeDefAt(AModule, 7);
      Check((LType is TPCRoutineType) and (TPCRoutineType(LType).Linkage = lnC) and
        (TPCRoutineType(LType).Params.Count = 1) and TPCRoutineType(LType).IsVariadic and
        (TPCRoutineType(LType).ReturnType is TPCBuiltinType), 'typedefs: clink variadic routine type');
      LType := DoTypeDefAt(AModule, 8);
      Check((LType is TPCRoutineType) and (TPCRoutineType(LType).Params.Count = 2) and
        (TPCRoutineType(LType).Params[0].ParamMode = pmConst) and
        (TPCRoutineType(LType).Params[1].ParamMode = pmVar) and
        (TPCRoutineType(LType).Params[1].ParamName = 'B') and (TPCRoutineType(LType).ReturnType = nil),
        'typedefs: routine type with const and var params, no result');
      LType := DoTypeDefAt(AModule, 9);
      Check((LType is TPCPointerType) and (TPCPointerType(LType).TargetType is TPCNamedType),
        'typedefs: ptr to TB');
      LRec := nil;
      if DoTypeDefAt(AModule, 1) is TPCRecordType then
        LRec := TPCRecordType(DoTypeDefAt(AModule, 1));
      Check((LRec <> nil) and (LRec.Range.StartLine = 4) and (LRec.Range.EndLine = 10),
        'typedefs: a record ranges over record .. end');
    end);
end;

procedure TPCParserTests.DoTestRoutineTypePositions();
begin
  // PLAN-RECORDS M2: a routine type is a type expr, in every type position
  DoWithExpr('pxa31_rtypes.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LType: TPCTypeExpr;
      LInit: TPCExpr;
      LRoutine: TPCRoutine;
      LArg: TPCTemplateArg;
    begin
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 10),
        'rtype_positions: ten decls, no report (got ' + DoCodes(AErrors) + ')');
      if AModule.Decls.Count <> 10 then
        Exit;
      LType := DoTypeDefAt(AModule, 0);
      Check((LType is TPCRecordType) and (TPCRecordType(LType).Members.Count = 2) and
        (TPCRecordType(LType).Members[0] is TPCField) and
        (TPCField(TPCRecordType(LType).Members[0]).TypeExpr is TPCRoutineType) and
        (TPCRecordType(LType).Members[1] is TPCField) and
        (TPCField(TPCRecordType(LType).Members[1]).TypeExpr is TPCRoutineType) and
        (TPCRoutineType(TPCField(TPCRecordType(LType).Members[1]).TypeExpr).Linkage = lnC) and
        TPCRoutineType(TPCField(TPCRecordType(LType).Members[1]).TypeExpr).IsVariadic,
        'rtype_positions: two routine-typed fields, the second clink variadic');
      LType := DoTypeDefAt(AModule, 1);
      Check((LType is TPCArrayType) and (TPCArrayType(LType).ElementType is TPCRoutineType),
        'rtype_positions: array element');
      Check(DoVarTypeAt(AModule, 2) is TPCRoutineType, 'rtype_positions: var type');
      LType := DoVarTypeAt(AModule, 3);
      Check((LType is TPCPointerType) and (TPCPointerType(LType).TargetType is TPCRoutineType),
        'rtype_positions: ptr to');
      LArg := DoArgAt(DoCppAt(AModule, 4), 1, 0);
      Check((LArg <> nil) and (LArg.TypeArg is TPCRoutineType), 'rtype_positions: template argument');
      LType := DoVarTypeAt(AModule, 5);
      Check((LType is TPCRoutineType) and (TPCRoutineType(LType).ReturnType is TPCRoutineType),
        'rtype_positions: a routine type returning one');
      LInit := DoInitAt(AModule, 6);
      Check((LInit is TPCCast) and (TPCCast(LInit).CastKind = ckPointer) and
        (TPCCast(LInit).TargetType is TPCPointerType) and
        (TPCPointerType(TPCCast(LInit).TargetType).TargetType is TPCRoutineType),
        'rtype_positions: pointer cast');
      LInit := DoInitAt(AModule, 7);
      Check((LInit is TPCCall) and (TPCCall(LInit).TypeArg is TPCRoutineType), 'rtype_positions: size(T)');
      LInit := DoInitAt(AModule, 8);
      Check((LInit is TPCCast) and (TPCCast(LInit).CastKind = ckReinterpret) and
        (TPCCast(LInit).TargetType is TPCRoutineType), 'rtype_positions: named cast');
      LRoutine := DoRoutineAt(AModule, 9);
      Check((LRoutine <> nil) and (LRoutine.Params.Count = 1) and
        (LRoutine.Params[0].TypeExpr is TPCRoutineType) and (LRoutine.ReturnType is TPCRoutineType),
        'rtype_positions: parameter and return type');
    end);
end;

procedure TPCParserTests.DoTestDecls();
begin
  DoWithExpr('pxa05_decls.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LVar: TPCVarDecl;
      LRoutine: TPCRoutine;
      LType: TPCTypeDecl;
    begin
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 13), 'decls: thirteen declarations, no error');
      if AModule.Decls.Count <> 13 then
        Exit;
      LVar := DoVarAt(AModule, 0);
      Check((LVar <> nil) and LVar.IsExported and (LVar.DeclName = 'A') and (DoVarAt(AModule, 1) <> nil) and
        DoVarAt(AModule, 1).IsExported and (DoVarAt(AModule, 2) <> nil) and
        (not DoVarAt(AModule, 2).IsExported), 'decls: exported covers its whole block, not the next one');
      Check((LVar <> nil) and (LVar.Range.StartLine = 3), 'decls: exported is not in an item range');
      LVar := DoVarAt(AModule, 3);
      Check((LVar <> nil) and LVar.ExternalClause.IsExternal and (LVar.ExternalClause.LibText = 'libd') and
        (LVar.ExternalClause.LibKind = elCString) and
        (LVar.InitExpr = nil) and (LVar.Range.EndLine = 7), 'decls: external "libd" after the var''s ; (elCString)');
      LVar := DoVarAt(AModule, 4);
      Check((LVar <> nil) and LVar.ExternalClause.IsExternal and (LVar.ExternalClause.LibText = 'LIBNAME') and
        (LVar.ExternalClause.LibKind = elIdentifier),
        'decls: external with a name keeps its spelling (elIdentifier)');
      Check((DoVerbatimAt(AModule, 5) <> nil) and (DoVerbatimAt(AModule, 5).Verbatim.Text = 'int x;'),
        'decls: C++ after a block stays one C++ span');
      LRoutine := DoRoutineAt(AModule, 6);
      Check((LRoutine <> nil) and (LRoutine.DeclName = 'F') and (LRoutine.Linkage = lnNone) and
        (LRoutine.Params.Count = 2) and (LRoutine.Params[0].ParamMode = pmConst) and
        (LRoutine.Params[1].ParamMode = pmVar) and (LRoutine.Params[1].ParamName = 'AY') and
        (LRoutine.ReturnType is TPCBuiltinType) and (LRoutine.Decls.Count = 1) and
        (LRoutine.Body <> nil) and (not LRoutine.IsVariadic),
        'decls: routine with param modes, a return type, a var block and a body');
      Check((LRoutine <> nil) and (LRoutine.Range.StartLine = 10) and (LRoutine.Range.EndLine = 14),
        'decls: a routine ranges over routine .. its final ;');
      LRoutine := DoRoutineAt(AModule, 7);
      Check((LRoutine <> nil) and LRoutine.IsExported and (LRoutine.Linkage = lnC) and
        LRoutine.IsVariadic and (LRoutine.Params.Count = 1) and LRoutine.ExternalClause.IsExternal and
        (LRoutine.ExternalClause.LibText = 'c') and (LRoutine.Body = nil),
        'decls: exported clink variadic external routine');
      LRoutine := DoRoutineAt(AModule, 8);
      Check((LRoutine <> nil) and (LRoutine.Linkage = lnCpp) and LRoutine.IsVariadic and
        (LRoutine.Params.Count = 0) and LRoutine.ExternalClause.IsExternal and
        (LRoutine.ExternalClause.LibText = '') and (LRoutine.ExternalClause.LibKind = elNone),
        'decls: (...) alone, external without a library (elNone)');
      LRoutine := DoRoutineAt(AModule, 9);
      Check((LRoutine <> nil) and (LRoutine.Params.Count = 0) and (LRoutine.ReturnType = nil) and
        (LRoutine.Body <> nil), 'decls: empty params, no result, a body');
      LRoutine := DoRoutineAt(AModule, 10);
      Check((LRoutine <> nil) and LRoutine.IsForward and (LRoutine.Body = nil) and
        (LRoutine.Params.Count = 1) and (LRoutine.ReturnType <> nil), 'decls: forward routine');
      LType := DoTypeDeclAt(AModule, 11);
      Check((LType <> nil) and LType.IsForward and (LType.TypeDef = nil) and (LType.DeclName = 'TK'),
        'decls: forward type');
      LType := DoTypeDeclAt(AModule, 12);
      Check((LType <> nil) and LType.IsExported and (LType.TypeDef is TPCBuiltinType),
        'decls: exported type block');
    end);
end;

procedure TPCParserTests.DoTestDeclErrors();
var
  LCase: TPCCodeCase;
  LName: string;
begin
  // One diagnostic per fixture, nothing cascades
  for LCase in PC_TEST_DECL_ERRORS do
    Check(DoCodesOfExpr(LCase.FileName) = LCase.Codes,
      'decl_errors: ' + LCase.FileName + ' reports exactly ' + LCase.Codes);
  // The one library-name rule behind PR0055 (pxa28 / pxa29)
  for LName in PC_TEST_LIB_NAMES do
    Check(TPCLibraryName.IsName(LName), 'decl_errors: ''' + LName + ''' is a library name');
  for LName in PC_TEST_LIB_FILES do
    Check(not TPCLibraryName.IsName(LName), 'decl_errors: ''' + LName + ''' is not a library name');
  DoWithExpr('pxa14_primsuffix.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoFirstMessage(AErrors).Contains('ptr to int32'), 'decl_errors: the PR0027 hint names ptr to int32');
    end);
  DoWithExpr('pxa15_qualsuffix.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoFirstMessage(AErrors).Contains('ptr to Geo.TPoint'),
        'decl_errors: the PR0028 hint names ptr to Geo.TPoint');
    end);
end;

procedure TPCParserTests.DoTestDeclRecovery();
begin
  DoWithExpr('pxa10_exported.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((AModule.Decls.Count = 1) and (DoVerbatimAt(AModule, 0) <> nil) and
        (DoVerbatimAt(AModule, 0).Verbatim.Text = 'int x;'),
        'decl_recovery: a misplaced exported consumes only itself');
    end);
  DoWithExpr('pxa13_declare.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LType: TPCTypeExpr;
    begin
      // A kept, marked, its type a marked record holding X; B intact
      // (PLAN-RECOVERY A5 step 3, A4 step 5)
      LType := nil;
      if DoVarAt(AModule, 0) <> nil then
        LType := DoVarAt(AModule, 0).TypeExpr;
      Check((AModule.Decls.Count = 2) and (DoVarAt(AModule, 0) <> nil) and
        (DoVarAt(AModule, 0).DeclName = 'A') and
        DoVarAt(AModule, 0).IsRecovered and (LType is TPCRecordType) and LType.IsRecovered and
        (TPCRecordType(LType).Members.Count = 1) and
        (DoVarAt(AModule, 1) <> nil) and (DoVarAt(AModule, 1).DeclName = 'B') and
        (not DoVarAt(AModule, 1).IsRecovered),
        'decl_recovery: a record in a var is parsed and kept, marked');
    end);
  DoWithExpr('pxa21_member.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LType: TPCTypeExpr;
    begin
      // The method is kept, marked, the field after it intact (A5 step 9)
      LType := DoTypeDefAt(AModule, 0);
      Check((LType is TPCRecordType) and (TPCRecordType(LType).Members.Count = 2) and
        (TPCRecordType(LType).Members[0] is TPCMethodItem) and
        TPCRecordType(LType).Members[0].IsRecovered and
        (TPCRecordType(LType).Members[1] is TPCField),
        'decl_recovery: a method in a record is parsed and kept, marked, the field kept');
    end);
  DoWithExpr('pxa25_stub.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LInit: TPCExpr;
    begin
      // PARSER-EXPR-B: the former seam parses; '>=' after template args still
      // splits, so the '=' is the initializer and '{}' a bare braced init
      LInit := DoInitAt(AModule, 2);
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 3) and (LInit is TPCBracedInit) and
        (TPCBracedInit(LInit).Base = nil) and (TPCBracedInit(LInit).Args.Count = 0),
        'decl_recovery: the initializers parse; >= splits, {} is a bare braced init');
    end);
  DoWithExpr('pxa26_badfield.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LType: TPCTypeExpr;
    begin
      // Y: ; is kept, marked; X and Z intact (A5 step 10)
      LType := DoTypeDefAt(AModule, 0);
      Check((DoCodes(AErrors) = PC_ERR_PAR_001) and (LType is TPCRecordType) and
        (TPCRecordType(LType).Members.Count = 3) and TPCRecordType(LType).Members[1].IsRecovered and
        (not TPCRecordType(LType).Members[2].IsRecovered),
        'decl_recovery: a bad field mid-record is kept, marked, the rest intact');
    end);
  DoWithExpr('pxa27_badheader.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LRoutine: TPCRoutine;
    begin
      // F is kept, marked, its param A marked and its body parsed; then B
      // (PLAN-RECOVERY A4 steps 8, 12, 13)
      LRoutine := nil;
      if (AModule.Decls.Count = 2) and (AModule.Decls[0] is TPCRoutine) then
        LRoutine := TPCRoutine(AModule.Decls[0]);
      Check((DoCodes(AErrors) = PC_ERR_PAR_001) and (LRoutine <> nil) and LRoutine.IsRecovered and
        (LRoutine.Params.Count = 1) and LRoutine.Params[0].IsRecovered and
        (LRoutine.Params[0].ParamName = 'A') and (LRoutine.Body <> nil) and
        (DoVarAt(AModule, 1) <> nil) and (DoVarAt(AModule, 1).DeclName = 'B'),
        'decl_recovery: a header error keeps F marked, its param A, its body, no cascade');
    end);
end;

procedure TPCParserTests.DoTestExprPrecedence();
begin
  DoCheckItems(Self, 'expr_prec', 'pxb01_prec.pcpp', PC_TEST_EXPR_PREC);
  DoWithExpr('pxb01_prec.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LInit: TPCExpr;
    begin
      // A binary node ranges from its left operand's first byte to its right
      // operand's last (ends are exclusive byte offsets)
      LInit := DoInitAt(AModule, 0);
      Check((LInit is TPCBinary) and
        (LInit.Range.StartByteOffset = TPCBinary(LInit).Left.Range.StartByteOffset) and
        (LInit.Range.EndByteOffset = TPCBinary(LInit).Right.Range.EndByteOffset) and
        (LInit.Range.StartLine = 3) and (LInit.Range.EndLine = 3),
        'expr_prec: a + b * c ranges over a .. c');
    end);
end;

procedure TPCParserTests.DoTestExprPostfix();
begin
  DoCheckItems(Self, 'expr_postfix', 'pxb02_postfix.pcpp', PC_TEST_EXPR_POSTFIX);
end;

procedure TPCParserTests.DoTestExprPrimary();
begin
  DoCheckItems(Self, 'expr_primary', 'pxb03_primary.pcpp', PC_TEST_EXPR_PRIMARY);
  DoWithExpr('pxb03_primary.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LInit: TPCExpr;
    begin
      LInit := DoInitAt(AModule, 0);
      Check((LInit is TPCLiteral) and (TPCLiteral(LInit).LiteralKind = lkInteger) and
        TPCLiteral(LInit).HasValue and (TPCLiteral(LInit).IntValue = 42),
        'expr_primary: 42 is an integer literal with its value');
      LInit := DoInitAt(AModule, 2);
      Check((LInit is TPCLiteral) and (TPCLiteral(LInit).LiteralKind = lkChar),
        'expr_primary: ''x'' is a char literal');
      LInit := DoInitAt(AModule, 25);
      Check(LInit is TPCCall, 'expr_primary: P(x) is a call, not a record literal');
    end);
end;

procedure TPCParserTests.DoTestExprTemplateArgs();
begin
  DoCheckItems(Self, 'expr_targs', 'pxb04_targs.pcpp', PC_TEST_EXPR_TARGS);
end;

procedure TPCParserTests.DoTestExprStrings();
begin
  DoWithExpr('pxb05_strings.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LInit: TPCExpr;
      LLiteral: TPCLiteral;
    begin
      Check((DoCodes(AErrors) = '') and (AModule.Decls.Count = 3), 'expr_strings: three items, no report');
      if AModule.Decls.Count <> 3 then
        Exit;
      LInit := DoInitAt(AModule, 0);
      Check(LInit is TPCLiteral, 'expr_strings: "ab" "cd" is one literal');
      if not (LInit is TPCLiteral) then
        Exit;
      LLiteral := TPCLiteral(LInit);
      Check((LLiteral.LiteralKind = lkString) and (Length(LLiteral.Parts) = 2) and
        (LLiteral.Parts[0].Text = '"ab"') and (LLiteral.Parts[1].Text = '"cd"') and
        (LLiteral.Text = '"ab" "cd"'), 'expr_strings: two parts, Text is the exact source');
      Check(LLiteral.Parts[0].HasValue and (LLiteral.Parts[0].Value = 'ab') and
        LLiteral.Parts[1].HasValue and (LLiteral.Parts[1].Value = 'cd'),
        'expr_strings: each plain part keeps its decoded value');
      LInit := DoInitAt(AModule, 1);
      Check((LInit is TPCLiteral) and (Length(TPCLiteral(LInit).Parts) = 2),
        'expr_strings: a prefixed part joins too, unchecked');
      LInit := DoInitAt(AModule, 2);
      Check((LInit is TPCLiteral) and (Length(TPCLiteral(LInit).Parts) = 1) and
        (TPCLiteral(LInit).Text = '"one"'), 'expr_strings: a single string is one part');
    end);
end;

procedure TPCParserTests.DoTestExprStringValues();
begin
  // pstr01_values.pcpp (scripts\zb_sem\gen_pstr.py): a plain part keeps the
  // value the one cstring rule decoded; a warning keeps it; an error and a
  // prefixed / raw part have none (sem\module.md F-M1)
  DoWithExpr('pstr01_values.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LLit: TPCLiteral;
    begin
      Check((DoCodes(AErrors) = PC_ERR_PAR_021 + ',' + PC_ERR_PAR_009) and
        (AModule.Decls.Count = 4),
        'expr_string_values: four items, one warning, one error (got ' + DoCodes(AErrors) + ')');
      if AModule.Decls.Count <> 4 then
        Exit;
      LLit := DoLiteralAt(AModule, 0);
      Check((LLit <> nil) and (Length(LLit.Parts) = 2) and LLit.Parts[0].HasValue and
        (LLit.Parts[0].Value = 'a'#9'b') and LLit.Parts[1].HasValue and
        (LLit.Parts[1].Value = 'c') and
        LLit.Dump().Contains(' part0=[value="a\tb"] part1=[value="c"]'),
        'expr_string_values: escapes decoded per part, dumped');
      LLit := DoLiteralAt(AModule, 1);
      Check((LLit <> nil) and (Length(LLit.Parts) = 1) and LLit.Parts[0].HasValue and
        (LLit.Parts[0].Value = 'xqy'),
        'expr_string_values: an unknown escape warns and keeps the value');
      LLit := DoLiteralAt(AModule, 2);
      Check((LLit <> nil) and (Length(LLit.Parts) = 2) and (not LLit.Parts[0].HasValue) and
        (LLit.Parts[0].Value = '') and LLit.Parts[1].HasValue and (LLit.Parts[1].Value = 'ok'),
        'expr_string_values: a bad escape has no value, the next part keeps its own');
      LLit := DoLiteralAt(AModule, 3);
      // A raw string is a plain cstring (BNF.md sec 2: raw allowed): it has a value
      Check((LLit <> nil) and (Length(LLit.Parts) = 2) and (not LLit.Parts[0].HasValue) and
        LLit.Parts[1].HasValue and (LLit.Parts[1].Value = 'r') and
        LLit.Dump().Contains(' part0=[prefix=lpU8] part1=[raw value="r"]'),
        'expr_string_values: a prefixed part is C++ (no value), a raw part has its bytes');
    end);
end;

procedure TPCParserTests.DoTestExprStringPositions();
var
  LI: Integer;
begin
  // P-STRPOS (research\cppmix\sem\prereq-b\strpos.md): every decoded byte of a
  // plain part maps back to its .pcpp position. Fixtures and expectations from
  // scripts\zb_sem\pb\gen_strpos.py (a reference of the parser's map walk,
  // cross-checked against strpos_probe.txt's true positions)
  for LI := 0 to High(PC_TEST_STRPOS_FILES) do
    DoCheckStrPos(Self, PC_TEST_STRPOS_FILES[LI].FileName, PC_TEST_STRPOS_FILES[LI].Codes);
end;

procedure TPCParserTests.DoTestExprLiteralFacts();
begin
  // Every literal fact the token carries reaches the AST (inputs.md F1)
  DoWithExpr('lit01_facts.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LLit: TPCLiteral;
    begin
      // 017 is the only C++ octal spelling; the lexer hints on it (LX0101)
      Check((DoCodes(AErrors) = PC_HINT_LEX_001) and (AModule.Decls.Count = 9),
        'expr_literal_facts: nine items, only the octal hint (got ' + DoCodes(AErrors) + ')');
      if AModule.Decls.Count <> 9 then
        Exit;
      LLit := DoLiteralAt(AModule, 0);
      Check((LLit <> nil) and (LLit.LiteralBase = lbDecimal) and (LLit.Suffix = '') and
        (not LLit.IsUserDefined) and
        (LLit.Dump() = 'Literal lkInteger "42" value=42' + sLineBreak),
        'expr_literal_facts: a plain decimal is lbDecimal and dumps as before');
      LLit := DoLiteralAt(AModule, 1);
      Check((LLit <> nil) and (LLit.LiteralBase = lbHex) and (LLit.Suffix = 'u') and
        LLit.HasValue and (LLit.IntValue = 31) and
        (LLit.Dump() = 'Literal lkInteger "0x1Fu" base=lbHex suffix="u" value=31' + sLineBreak),
        'expr_literal_facts: hex with a suffix keeps base and suffix, dumped');
      LLit := DoLiteralAt(AModule, 2);
      Check((LLit <> nil) and (LLit.LiteralBase = lbBinary) and (LLit.IntValue = 5),
        'expr_literal_facts: binary base');
      LLit := DoLiteralAt(AModule, 3);
      Check((LLit <> nil) and (LLit.LiteralBase = lbOctal) and (LLit.IntValue = 15),
        'expr_literal_facts: octal base');
      LLit := DoLiteralAt(AModule, 4);
      Check((LLit <> nil) and (LLit.LiteralKind = lkFloat) and (LLit.Suffix = 'f'),
        'expr_literal_facts: a float keeps its suffix');
      LLit := DoLiteralAt(AModule, 5);
      Check((LLit <> nil) and (LLit.LiteralKind = lkChar) and
        (LLit.LiteralPrefix = lpUpperL),
        'expr_literal_facts: a char keeps its prefix');
      LLit := DoLiteralAt(AModule, 6);
      Check((LLit <> nil) and (Length(LLit.Parts) = 2) and
        (LLit.Parts[0].LiteralPrefix = lpU8) and (not LLit.Parts[0].IsRawString) and
        (LLit.Parts[1].LiteralPrefix = lpNone) and LLit.Parts[1].IsRawString and
        LLit.Dump().Contains(' part0=[prefix=lpU8] part1=[raw value="y"]'),
        'expr_literal_facts: each joined string part keeps its prefix and raw flag, dumped');
      LLit := DoLiteralAt(AModule, 7);
      Check((LLit <> nil) and (LLit.Suffix = '_km') and LLit.IsUserDefined and
        (not LLit.HasValue),
        'expr_literal_facts: a user-defined integer literal is flagged, no value');
      LLit := DoLiteralAt(AModule, 8);
      Check((LLit <> nil) and (Length(LLit.Parts) = 1) and (LLit.Parts[0].Suffix = '_sv') and
        LLit.Parts[0].IsUserDefined and LLit.Dump().Contains(' part0=[suffix="_sv" udl]'),
        'expr_literal_facts: a user-defined string part is flagged, dumped');
    end);
end;

procedure TPCParserTests.DoTestExprCharValues();
begin
  // chr01_values.pcpp (scripts\zb_sem\gen_chr.py): a plain / L char literal
  // carries the value clang gives it (P-CHAR); clang's rejections are PR0054
  DoWithExpr('chr01_values.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LLit: TPCLiteral;
    begin
      Check((DoCodes(AErrors) = 'PR0064,PR0054,PR0064') and (AModule.Decls.Count = 7),
        'char_values: seven items, ''ab'', the e-acute literal and ''\q'' reported (got ' + DoCodes(AErrors) + ')');
      // F66: a multi-char literal is PaskalCPP's warning (it was left to clang)
      Check((AErrors.Count() = 3) and (AErrors.GetItems()[0].Severity = esWarning) and
        (AErrors.GetItems()[0].Range.StartLine = 5) and
        (AErrors.GetItems()[0].Range.StartColumn = 14) and
        (AErrors.GetItems()[0].Message = Format(RSParCharWarning, [RSComCharMulti])),
        'char_values: ''ab'' is PR0064 at its quote, clang''s text');
      Check((AErrors.Count() = 3) and (AErrors.GetItems()[1].Range.StartLine = 7) and
        (AErrors.GetItems()[1].Range.StartColumn = 13) and
        AErrors.GetItems()[1].Message.Contains(RSComCharTooLarge),
        'char_values: e-acute is PR0054 at its quote, clang''s reason');
      // F65: an unknown escape is PaskalCPP's warning (it was left to clang)
      Check((AErrors.Count() = 3) and (AErrors.GetItems()[2].Severity = esWarning) and
        (AErrors.GetItems()[2].Range.StartLine = 9) and
        (AErrors.GetItems()[2].Range.StartColumn = 13) and
        (AErrors.GetItems()[2].Message = Format(RSParCharWarning,
        [RSComCStrUnknownEscape.Replace('%s', 'q')])),
        'char_values: ''\q'' is PR0064 at its quote, the decoder''s reason');
      if AModule.Decls.Count <> 7 then
        Exit;
      LLit := DoLiteralAt(AModule, 0);
      Check((LLit <> nil) and LLit.HasValue and (LLit.IntValue = 97) and (not LLit.IsMultiChar) and
        (LLit.Dump() = 'Literal lkChar "''a''" value=97' + sLineBreak),
        'char_values: ''a'' is 97, dumped');
      LLit := DoLiteralAt(AModule, 1);
      Check((LLit <> nil) and LLit.HasValue and (LLit.IntValue = 255),
        'char_values: ''\xFF'' is the byte 255');
      LLit := DoLiteralAt(AModule, 2);
      Check((LLit <> nil) and LLit.HasValue and LLit.IsMultiChar and (LLit.IntValue = $6162) and
        LLit.Dump().Contains(' multichar value=24930'),
        'char_values: ''ab'' is multi-char $6162, dumped');
      LLit := DoLiteralAt(AModule, 3);
      Check((LLit <> nil) and LLit.HasValue and (LLit.LiteralPrefix = lpUpperL) and
        (LLit.IntValue = $1234) and (not LLit.IsMultiChar),
        'char_values: L''\x1234'' is $1234');
      LLit := DoLiteralAt(AModule, 4);
      Check((LLit <> nil) and (not LLit.HasValue),
        'char_values: a rejected literal has no value');
      LLit := DoLiteralAt(AModule, 5);
      Check((LLit <> nil) and (LLit.LiteralPrefix = lpU8) and (not LLit.HasValue),
        'char_values: a u8 char stays opaque (no value)');
      LLit := DoLiteralAt(AModule, 6);
      Check((LLit <> nil) and LLit.HasValue and (LLit.IntValue = 113),
        'char_values: ''\q'' keeps clang''s value (q)');
      Check((LLit <> nil) and (LLit.CppText = '''q''') and (LLit.Text = '''\q'''),
        'char_values: ''\q'' is written to C++ as ''q'', its text kept (F65)');
    end);
end;

procedure TPCParserTests.DoTestExprErrors();
var
  LCase: TPCCodeCase;
begin
  // One diagnostic per fixture, nothing cascades
  for LCase in PC_TEST_EXPR_ERRORS do
    Check(DoCodesOfExpr(LCase.FileName) = LCase.Codes,
      'expr_errors: ' + LCase.FileName + ' reports exactly ' + LCase.Codes +
      ' (got ' + DoCodesOfExpr(LCase.FileName) + ')');
  DoWithExpr('pxb11_eqeq.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoFirstMessage(AErrors).Contains('''='''), 'expr_errors: the == hint names =');
    end);
  DoWithExpr('pxb12_noteq.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoFirstMessage(AErrors).Contains('''<>'''), 'expr_errors: the != hint names <>');
    end);
  DoWithExpr('pxb13_bitand.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoFirstMessage(AErrors).Contains('''&'''), 'expr_errors: the bitand hint names &');
      Check(DoExprText(DoInitAt(AModule, 0)) = '(a boBitAnd b)',
        'expr_errors: bitand is reported and parsed as & (the item is kept)');
    end);
  DoWithExpr('pxb14_xoreq.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoFirstMessage(AErrors).Contains('X := X xor Y'), 'expr_errors: the xor_eq hint is X := X xor Y');
    end);
  DoWithExpr('pxb19_noexpr.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoFirstMessage(AErrors).Contains(RSParShapeExpression),
        'expr_errors: a missing operand is expected an expression');
    end);
end;

procedure TPCParserTests.DoTestExprRecovery();
begin
  DoWithExpr('pxb16_castargs.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LInit: TPCExpr;
    begin
      // A kept, marked; its InitExpr an error expression holding a
      // (PLAN-RECOVERY A6 step 14, A4 step 5)
      LInit := nil;
      if DoVarAt(AModule, 0) <> nil then
        LInit := DoVarAt(AModule, 0).InitExpr;
      Check((AModule.Decls.Count = 1) and (DoVarAt(AModule, 0) <> nil) and
        DoVarAt(AModule, 0).IsRecovered and
        (LInit is TPCErrorExpr) and (TPCErrorExpr(LInit).Parts.Count = 1) and
        (TPCErrorExpr(LInit).Parts[0] is TPCName),
        'expr_recovery: a failed expression keeps its item, marked, the parsed operand inside');
    end);
  DoWithExpr('pxb23_depthok.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = '') and (DoInitAt(AModule, 0) is TPCName),
        'expr_recovery: 255 nested parentheses parse');
    end);
  DoWithExpr('pxb26_budget.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = PC_ERR_PAR_039 + ',' + PC_ERR_PAR_038 + ',' + PC_ERR_PAR_039,
        'expr_recovery: == == reports both hints and the chain once');
      Check(DoExprText(DoInitAt(AModule, 0)) = '((a boEq b) boEq c)',
        'expr_recovery: the reported forms still build the tree');
    end);
  DoWithPathMax(TPath.Combine(DoExprDir(), 'pxb26_budget.pcpp'), 1,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors) = PC_ERR_PAR_039, 'expr_recovery: a budget of one stops after the first');
    end);
  DoWithExpr('pxb30_anondepth.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors).StartsWith(PC_ERR_PAR_042) and (AModule <> nil),
        'expr_recovery: 257 nested anonymous aggregates report PR0042 first, no stack overflow');
    end);
end;

procedure TPCParserTests.DoTestVerbatimLambda();
begin
  DoCheckItems(Self, 'verbatim_lambda', 'pxc01_lambda.pcpp', PC_TEST_LAMBDA);
  DoWithExpr('pxc01_lambda.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LInit: TPCExpr;
    begin
      LInit := DoInitAt(AModule, 0);
      Check((LInit is TPCVerbatimExpr) and (TPCVerbatimExpr(LInit).Verbatim.EmitTarget = etInPlace) and
        (LInit.Range.StartByteOffset = TPCVerbatimExpr(LInit).Verbatim.Range.StartByteOffset),
        'verbatim_lambda: a lambda is a verbatim node emitted in place, ranged over its text');
    end);
end;

procedure TPCParserTests.DoTestVerbatimOpaque();
begin
  DoCheckItems(Self, 'verbatim_opaque', 'pxc02_opaque.pcpp', PC_TEST_OPAQUE);
end;

procedure TPCParserTests.DoTestVerbatimCpp();
begin
  DoCheckItems(Self, 'verbatim_cpp', 'pxc03_cppexpr.pcpp', PC_TEST_CPPEXPR);
  DoWithExpr('pxc06_cppraw.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LInit: TPCExpr;
      LVerbatim: TPCVerbatim;
    begin
      LInit := DoInitAt(AModule, 0);
      Check((DoCodes(AErrors) = '') and (LInit is TPCVerbatimExpr), 'verbatim_cpp: a two-line raw cpp() parses');
      if not (LInit is TPCVerbatimExpr) then
        Exit;
      LVerbatim := TPCVerbatimExpr(LInit).Verbatim;
      Check(LVerbatim.Text.StartsWith('a +') and LVerbatim.Text.EndsWith('b') and
        LVerbatim.Text.Contains(#10), 'verbatim_cpp: a raw value keeps its line break');
      Check(DoLinesText(LVerbatim.InsideLines) = '4',
        'verbatim_cpp: line 4 starts inside the raw string (no #line there, R23)');
      Check((LVerbatim.Range.StartLine = 3) and (LVerbatim.Range.EndLine = 4) and
        (LInit.Range.StartLine = 3), 'verbatim_cpp: Verbatim.Range is the string, the node cpp .. )');
    end);
end;

procedure TPCParserTests.DoTestCStyleCast();
begin
  // Every failed cast try leaves nothing behind: DoCheckItems also asserts no report
  DoCheckItems(Self, 'cstyle_cast', 'pxc04_cstyle.pcpp', PC_TEST_CSTYLE);
end;

procedure TPCParserTests.DoTestSizeArg();
begin
  DoCheckItems(Self, 'size_arg', 'pxc05_size.pcpp', PC_TEST_SIZE);
  DoWithExpr('pxc05_size.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LInit: TPCExpr;
    begin
      LInit := DoInitAt(AModule, 0);
      Check((LInit is TPCCall) and (TPCCall(LInit).TypeArg is TPCBuiltinType) and
        (TPCCall(LInit).Args.Count = 0), 'size_arg: size(int64) holds a TypeArg and no Args');
      LInit := DoInitAt(AModule, 3);
      Check((LInit is TPCCall) and (TPCCall(LInit).TypeArg = nil) and (TPCCall(LInit).Args.Count = 1) and
        (TPCCall(LInit).Args[0] is TPCName), 'size_arg: size(TPoint) is an ordinary argument (SEM decides)');
    end);
end;

procedure TPCParserTests.DoTestVarargsForms();
begin
  // PREREQ-B R3 forms (research\cppmix\sem\prereq-b\varargs-forms.md Tests):
  // varargs as a type, varargs.get / reset / copy, next / get with a type
  // argument on a varargs local (TypeArgIndex), and the forms that stay
  // ordinary members / arguments. Fixture + table: scripts\zb_sem\pb\gen_varargs.py
  DoCheckItemsAt(Self, 'varargs_forms', TPath.Combine(DoVarargsDir(), 'pva01_forms.pcpp'),
    PC_TEST_VARARGS);
  DoWithPath(TPath.Combine(DoVarargsDir(), 'pva01_forms.pcpp'),
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LInit: TPCExpr;
      LVarargs: TPCVarargs;
      LCall: TPCCall;
    begin
      Check(DoTypeText(DoVarTypeAt(AModule, PC_TEST_VA_TYPE)) = 'B:tkKwVarargs',
        'varargs_forms: varargs is a builtin type (got ' +
        DoTypeText(DoVarTypeAt(AModule, PC_TEST_VA_TYPE)) + ')');
      LInit := DoInitAt(AModule, PC_TEST_VA_GET);
      LVarargs := nil;
      if LInit is TPCVarargs then
        LVarargs := TPCVarargs(LInit);
      Check((LVarargs <> nil) and (LVarargs.VarargsKind = vaGet) and
        (LVarargs.IndexExpr is TPCBinary) and (LVarargs.ReadType is TPCBuiltinType),
        'varargs_forms: varargs.get holds its index expression and the type read');
      LInit := DoInitAt(AModule, PC_TEST_VA_NAMEARG);
      Check((LInit is TPCCall) and (TPCCall(LInit).TypeArg = nil) and
        (TPCCall(LInit).Args.Count = 1) and (TPCCall(LInit).Args[0] is TPCName),
        'varargs_forms: L.next(TPoint) is an ordinary argument (SEM reads the name as the type)');
      LInit := DoInitAt(AModule, PC_TEST_VA_LOCALGET);
      LCall := nil;
      if LInit is TPCCall then
        LCall := TPCCall(LInit);
      Check((LCall <> nil) and (LCall.TypeArg is TPCBuiltinType) and (LCall.TypeArgIndex = 1) and
        (LCall.Args.Count = 1) and LCall.Dump().Contains('typearg@1'),
        'varargs_forms: L.get(0, string) holds the type at index 1, dumped typearg@1');
      LInit := DoInitAt(AModule, PC_TEST_VA_ARRAYARG);
      Check((LInit is TPCCall) and (TPCCall(LInit).TypeArg is TPCArrayType) and
        (TPCCall(LInit).TypeArgIndex = 1) and (TPCCall(LInit).Args.Count = 1),
        'varargs_forms: L.get(i + 1, array of int32) holds an array type at index 1');
      LInit := DoInitAt(AModule, PC_TEST_VA_SIZE);
      LCall := nil;
      if LInit is TPCCall then
        LCall := TPCCall(LInit);
      Check((LCall <> nil) and (LCall.TypeArg is TPCBuiltinType) and (LCall.TypeArgIndex = 0) and
        (LCall.Args.Count = 0) and (not LCall.Dump().Contains('typearg@')),
        'varargs_forms: size(int64) keeps index 0 and dumps no typearg@');
    end);
end;

procedure TPCParserTests.DoTestVarargsErrors();
var
  LCase: TPCCodeCase;
begin
  // One diagnostic per fixture, nothing cascades: PR0027 for varargs with a
  // C++ suffix / lead cv / after new (as int32), PR0001 for a broken get /
  // reset / copy argument list (gen_varargs.py)
  for LCase in PC_TEST_VARARGS_ERRORS do
    Check(DoCodesOfVarargs(LCase.FileName) = LCase.Codes,
      'varargs_errors: ' + LCase.FileName + ' reports exactly ' + LCase.Codes +
      ' (got ' + DoCodesOfVarargs(LCase.FileName) + ')');
  DoWithPath(TPath.Combine(DoVarargsDir(), 'pva10_ptrsuffix.pcpp'),
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoFirstMessage(AErrors).Contains('write ptr to varargs'),
        'varargs_errors: the hint names ptr to varargs (got ' + DoFirstMessage(AErrors) + ')');
    end);
end;

procedure TPCParserTests.DoTestVerbatimErrors();
var
  LCase: TPCCodeCase;
begin
  // One diagnostic per fixture, nothing cascades
  for LCase in PC_TEST_VERBATIM_ERRORS do
    Check(DoCodesOfExpr(LCase.FileName) = LCase.Codes,
      'verbatim_errors: ' + LCase.FileName + ' reports exactly ' + LCase.Codes +
      ' (got ' + DoCodesOfExpr(LCase.FileName) + ')');
  DoWithExpr('pxc11_sizeofnoparen.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoFirstMessage(AErrors).Contains('sizeof(...)'), 'verbatim_errors: the hint names sizeof(...)');
    end);
  DoWithExpr('pxc15_cppwarn.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoInitAt(AModule, 0) is TPCVerbatimExpr, 'verbatim_errors: a string warning keeps the cpp() node');
    end);
  DoWithExpr('pxc13_castop.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      // The item kept, marked, its InitExpr an error expression (A6 step 24)
      Check((AModule.Decls.Count = 1) and (DoVarAt(AModule, 0) <> nil) and
        DoVarAt(AModule, 0).IsRecovered and (DoVarAt(AModule, 0).InitExpr is TPCErrorExpr),
        'verbatim_errors: a cast without an operand keeps its item, marked');
    end);
end;

procedure TPCParserTests.DoTestStmtSimple();
begin
  DoCheckStmts(Self, 'stmt_simple', 'pst01_simple.pcpp', PC_TEST_STMT_SIMPLE);
end;

procedure TPCParserTests.DoTestStmtFlow();
begin
  DoCheckStmts(Self, 'stmt_flow', 'pst02_flow.pcpp', PC_TEST_STMT_FLOW);
end;

procedure TPCParserTests.DoTestStmtMatch();
begin
  DoCheckStmts(Self, 'stmt_match', 'pst03_match.pcpp', PC_TEST_STMT_MATCH);
end;

procedure TPCParserTests.DoTestStmtGuard();
begin
  DoCheckStmts(Self, 'stmt_guard', 'pst04_guard.pcpp', PC_TEST_STMT_GUARD);
end;

procedure TPCParserTests.DoTestStmtBodyForms();
begin
  DoCheckStmts(Self, 'stmt_body_forms', 'pst05_forms.pcpp', PC_TEST_STMT_BODY_FORMS);
end;

procedure TPCParserTests.DoTestStmtTestBody();
begin
  // A test body goes through DoParseBlock (routine and section bodies too)
  DoWithStmt('pst06_testbody.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = '') and (AModule.Tests.Count = 1), 'stmt_test_body: one test, no report');
      if AModule.Tests.Count <> 1 then
        Exit;
      Check((AModule.Tests[0].Body <> nil) and (AModule.Tests[0].Body.Stmts.Count = 1),
        'stmt_test_body: the body holds its one statement');
      if (AModule.Tests[0].Body = nil) or (AModule.Tests[0].Body.Stmts.Count <> 1) then
        Exit;
      Check(DoStmtText(AModule.Tests[0].Body.Stmts[0]) = 'testAssert((1 boLess 2))',
        'stmt_test_body: testAssert(1 < 2) is a call statement');
    end);
end;

procedure TPCParserTests.DoTestStmtErrors();
var
  LCase: TPCCodeCase;
begin
  // One diagnostic per fixture, nothing cascades
  for LCase in PC_TEST_STMT_ERRORS do
    Check(DoCodesOfStmt(LCase.FileName) = LCase.Codes,
      'stmt_errors: ' + LCase.FileName + ' reports exactly ' + LCase.Codes +
      ' (got ' + DoCodesOfStmt(LCase.FileName) + ')');
  DoWithStmt('pst10_eqstmt.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoFirstMessage(AErrors).Contains(''':='''), 'stmt_errors: the = statement hints :=');
      Check((AModule.Body <> nil) and (AModule.Body.Stmts.Count = 1),
        'stmt_errors: the = statement is reported and kept');
    end);
  DoWithStmt('pst11_break.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoFirstMessage(AErrors).Contains('''leave'''), 'stmt_errors: break hints leave');
    end);
  DoWithStmt('pst16_guardempty.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoFirstMessage(AErrors).Contains('''except'''), 'stmt_errors: an empty guard names except');
    end);
end;

procedure TPCParserTests.DoTestStmtRecovery();
begin
  // The statement after a reported one parses (no cascade, nothing eaten); the
  // skipped tokens are an error node, a statement reported inside is kept,
  // marked (PLAN-RECOVERY A3)
  DoWithStmt('pst12_switch.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((AModule.Body <> nil) and (AModule.Body.Stmts.Count = 2) and
        (AModule.Body.Stmts[0] is TPCErrorStmt) and
        (DoStmtText(AModule.Body.Stmts[1]) = 'Bar()'),
        'stmt_recovery: a switch is an error node through its }, Bar(); still parses');
    end);
  DoWithStmt('pst13_trycatch.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((AModule.Body <> nil) and (AModule.Body.Stmts.Count = 2) and
        (AModule.Body.Stmts[0] is TPCErrorStmt) and
        (DoStmtText(AModule.Body.Stmts[1]) = 'Bar()'),
        'stmt_recovery: try { } catch (...) { } is one error node, Bar(); still parses');
    end);
  DoWithStmt('pst18_stray.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((AModule.Body <> nil) and (AModule.Body.Stmts.Count = 2) and
        (AModule.Body.Stmts[0] is TPCErrorStmt) and
        (DoStmtText(AModule.Body.Stmts[1]) = 'Foo()'),
        'stmt_recovery: a stray else is an error node, Foo(); still parses');
    end);
  DoWithStmt('pst21_nocond.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LIf: TPCIf;
    begin
      LIf := nil;
      if (AModule.Body <> nil) and (AModule.Body.Stmts.Count = 1) and
        (AModule.Body.Stmts[0] is TPCIf) then
        LIf := TPCIf(AModule.Body.Stmts[0]);
      Check((LIf <> nil) and LIf.IsRecovered and (LIf.Condition = nil) and
        (LIf.ThenStmts.Count = 1) and (DoStmtText(LIf.ThenStmts[0]) = 'Foo()'),
        'stmt_recovery: an if without its condition is reported once and kept, marked');
    end);
  DoWithStmt('pst25_depth.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check(DoCodes(AErrors).StartsWith(PC_ERR_PAR_042),
        'stmt_recovery: 257 nested blocks report PR0042 first, no stack overflow');
    end);
  DoWithStmt('pst26_depthok.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((DoCodes(AErrors) = '') and (AModule.Body <> nil) and (AModule.Body.Stmts.Count = 1),
        'stmt_recovery: 256 nested blocks (the limit) parse');
    end);
end;

procedure TPCParserTests.DoTestStmtRanges();
begin
  // A statement ranges from its first token through its ';'
  DoWithStmt('pst01_simple.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((AModule.Body <> nil) and (AModule.Body.Stmts.Count = 8), 'stmt_ranges: pst01 parses');
      if (AModule.Body = nil) or (AModule.Body.Stmts.Count <> 8) then
        Exit;
      Check((AModule.Body.Stmts[0].Range.StartLine = 3) and (AModule.Body.Stmts[0].Range.EndLine = 3),
        'stmt_ranges: LX := 1; is line 3');
      Check((AModule.Body.Stmts[7].Range.StartLine = 10) and (AModule.Body.Stmts[7].Range.EndLine = 10),
        'stmt_ranges: the block statement is line 10');
    end);
  DoWithStmt('pst03_match.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    begin
      Check((AModule.Body <> nil) and (AModule.Body.Stmts.Count = 4) and
        (AModule.Body.Stmts[0].Range.StartLine = 3) and (AModule.Body.Stmts[0].Range.EndLine = 9),
        'stmt_ranges: the first match spans lines 3 .. 9');
    end);
end;

procedure TPCParserTests.DoTestDeclModule();
begin
  // PLAN-EMITTER A1: every module-level declaration records its module;
  // a routine's local declarations stay nil
  DoWithIn(DoProbeDir('emit\own'), 'own1.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LCount: Integer;
      LStmt: TPCStmt;
      LAllOwned: Boolean;
      LPub: TPCRoutine;
      LLocalsNil: Boolean;
    begin
      Check(DoCodes(AErrors) = '', 'decl_module: own1 parses');
      LCount := 0;
      LAllOwned := True;
      LPub := nil;
      for LStmt in AModule.Decls do
      begin
        if LStmt is TPCDecl then
        begin
          Inc(LCount);
          if TPCDecl(LStmt).DeclModule <> AModule then
            LAllOwned := False;
          if (LStmt is TPCRoutine) and (TPCDecl(LStmt).DeclName = 'Pub') then
            LPub := TPCRoutine(LStmt);
        end;
      end;
      Check((LCount = 6) and LAllOwned, 'decl_module: GA GB GC TRec Pub Exp all own the module');
      Check(LPub <> nil, 'decl_module: Pub found');
      if LPub = nil then
        Exit;
      LLocalsNil := LPub.Decls.Count = 2;
      for LStmt in LPub.Decls do
      begin
        if (LStmt is TPCDecl) and (TPCDecl(LStmt).DeclModule <> nil) then
          LLocalsNil := False;
      end;
      Check(LLocalsNil, 'decl_module: the local var and type of Pub are nil');
    end);
end;

function DoFirstRoutineStmt(const AModule: TPCModule; const AIndex: Integer): TPCStmt;
var
  LStmt: TPCStmt;
begin
  // The AIndex-th statement of the module's first routine body (nil = none)
  Result := nil;
  for LStmt in AModule.Decls do
  begin
    if (LStmt is TPCRoutine) and (TPCRoutine(LStmt).Body <> nil) then
    begin
      if AIndex < TPCRoutine(LStmt).Body.Stmts.Count then
        Result := TPCRoutine(LStmt).Body.Stmts[AIndex];
      Exit;
    end;
  end;
end;

procedure TPCParserTests.DoTestKeywordRanges();
begin
  // PLAN-EMITTER A7: else / until / except / finally record their keyword
  // (the emitter writes `} else {` ... on that line), line AND column
  DoWithIn(DoProbeDir('emit\stmts\ifs'), 'ifs.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LIf: TPCStmt;
    begin
      LIf := DoFirstRoutineStmt(AModule, 0);
      Check((LIf is TPCIf) and TPCIf(LIf).HasElse and (TPCIf(LIf).ElseRange.StartLine = 6) and
        (TPCIf(LIf).ElseRange.StartColumn = 3) and (TPCIf(LIf).ElseRange.EndColumn = 6),
        'keyword_ranges: if else = line 6, cols 3 .. 6');
    end);
  DoWithIn(DoProbeDir('emit\stmts\loops'), 'loops.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LRepeat: TPCStmt;
    begin
      LRepeat := DoFirstRoutineStmt(AModule, 1);
      Check((LRepeat is TPCRepeat) and (TPCRepeat(LRepeat).UntilRange.StartLine = 12) and
        (TPCRepeat(LRepeat).UntilRange.StartColumn = 3), 'keyword_ranges: until = line 12, col 3');
    end);
  DoWithIn(DoProbeDir('emit\stmts\matchs'), 'matchs.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LMatch: TPCStmt;
    begin
      LMatch := DoFirstRoutineStmt(AModule, 0);
      Check((LMatch is TPCMatch) and TPCMatch(LMatch).HasElse and (TPCMatch(LMatch).ElseRange.StartLine = 10),
        'keyword_ranges: match else = line 10');
    end);
  DoWithIn(DoProbeDir('emit\stmts\guards'), 'guards.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LGuard: TPCStmt;
    begin
      LGuard := DoFirstRoutineStmt(AModule, 0);
      Check((LGuard is TPCGuard) and (TPCGuard(LGuard).ExceptRange.StartLine = 8) and
        (TPCGuard(LGuard).ExceptRange.StartColumn = 3) and (TPCGuard(LGuard).FinallyRange.StartLine = 10) and
        (TPCGuard(LGuard).FinallyRange.StartColumn = 3), 'keyword_ranges: except = line 8, finally = line 10, col 3');
    end);
end;

function DoRangeIs(const ARange: TSourceRange; const ALine: Integer; const AStart: Integer;
  const AEnd: Integer): Boolean;
begin
  // One line, UTF-8 byte columns AStart .. AEnd (the last byte, as Range)
  Result := (ARange.StartLine = ALine) and (ARange.EndLine = ALine) and
    (ARange.StartColumn = AStart) and (ARange.EndColumn = AEnd);
end;

function DoModuleDecl(const AModule: TPCModule; const ADeclName: string): TPCDecl;
var
  LStmt: TPCStmt;
begin
  // The module-level declaration named ADeclName (nil = none)
  Result := nil;
  for LStmt in AModule.Decls do
  begin
    if (LStmt is TPCDecl) and (TPCDecl(LStmt).DeclName = ADeclName) then
      Exit(TPCDecl(LStmt));
  end;
end;

procedure TPCParserTests.DoTestNameRanges();
begin
  // PLAN-EDITOR E2.3: every declaration records its name token (go to
  // definition lands there); a for's iterator records its use. Columns are
  // UTF-8 bytes: GB follows a 2-byte char, so a character column fails
  DoWithIn(DoProbeDir('par\names'), 'names.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LDecl: TPCDecl;
      LRoutine: TPCRoutine;
      LRecord: TPCTypeExpr;
      LChoices: TPCTypeExpr;
      LFor: TPCStmt;
    begin
      Check(DoCodes(AErrors) = '', 'name_ranges: names parses');
      Check(DoRangeIs(AModule.NameRange, 1, 12, 16), 'name_ranges: module names = 1:12-16');
      LDecl := DoModuleDecl(AModule, 'GA');
      Check((LDecl <> nil) and DoRangeIs(LDecl.NameRange, 3, 3, 4), 'name_ranges: var GA = 3:3-4');
      LDecl := DoModuleDecl(AModule, 'GB');
      Check((LDecl <> nil) and DoRangeIs(LDecl.NameRange, 4, 9, 10), 'name_ranges: var GB after a 2-byte char = 4:9-10');
      LDecl := DoModuleDecl(AModule, 'GC');
      Check((LDecl <> nil) and DoRangeIs(LDecl.NameRange, 6, 3, 4), 'name_ranges: const GC = 6:3-4');
      LDecl := DoModuleDecl(AModule, 'TRec');
      Check((LDecl <> nil) and DoRangeIs(LDecl.NameRange, 8, 3, 6), 'name_ranges: type TRec = 8:3-6');
      LRecord := nil;
      if LDecl is TPCTypeDecl then
        LRecord := TPCTypeDecl(LDecl).TypeDef;
      Check((LRecord is TPCRecordType) and (TPCRecordType(LRecord).Members.Count = 1) and
        (TPCRecordType(LRecord).Members[0] is TPCField) and
        DoRangeIs(TPCField(TPCRecordType(LRecord).Members[0]).NameRange, 9, 5, 7),
        'name_ranges: field Fld = 9:5-7');
      LDecl := DoModuleDecl(AModule, 'TCol');
      Check((LDecl <> nil) and DoRangeIs(LDecl.NameRange, 11, 3, 6), 'name_ranges: type TCol = 11:3-6');
      LChoices := nil;
      if LDecl is TPCTypeDecl then
        LChoices := TPCTypeDecl(LDecl).TypeDef;
      Check((LChoices is TPCChoicesType) and (TPCChoicesType(LChoices).Values.Count = 2) and
        DoRangeIs(TPCChoicesType(LChoices).Values[0].NameRange, 11, 18, 20) and
        DoRangeIs(TPCChoicesType(LChoices).Values[1].NameRange, 11, 23, 27),
        'name_ranges: choice values Red = 11:18-20, Green = 11:23-27');
      LDecl := DoModuleDecl(AModule, 'TFwd');
      Check((LDecl <> nil) and DoRangeIs(LDecl.NameRange, 12, 14, 17), 'name_ranges: forward type TFwd = 12:14-17');
      LDecl := DoModuleDecl(AModule, 'R');
      Check((LDecl is TPCRoutine) and DoRangeIs(LDecl.NameRange, 13, 9, 9), 'name_ranges: routine R = 13:9');
      if not (LDecl is TPCRoutine) then
        Exit;
      LRoutine := TPCRoutine(LDecl);
      Check((LRoutine.Params.Count = 2) and DoRangeIs(LRoutine.Params[0].NameRange, 13, 17, 18) and
        DoRangeIs(LRoutine.Params[1].NameRange, 13, 32, 33), 'name_ranges: params AP = 13:17-18, BQ = 13:32-33');
      Check((LRoutine.Decls.Count = 1) and (LRoutine.Decls[0] is TPCDecl) and
        DoRangeIs(TPCDecl(LRoutine.Decls[0]).NameRange, 15, 3, 4), 'name_ranges: local var LI = 15:3-4');
      LFor := nil;
      if (LRoutine.Body <> nil) and (LRoutine.Body.Stmts.Count > 0) then
        LFor := LRoutine.Body.Stmts[0];
      Check((LFor is TPCFor) and DoRangeIs(TPCFor(LFor).IteratorRange, 17, 7, 8), 'name_ranges: for iterator LI = 17:7-8');
      Check((AModule.InitRoutine <> nil) and DoRangeIs(AModule.InitRoutine.NameRange, 20, 1, 10),
        'name_ranges: initialize section = 20:1-10');
    end);
end;

{ DoDocOf }
// A module-level declaration's doc, or '<missing>' when there is none
function DoDocOf(const AModule: TPCModule; const ADeclName: string): string;
var
  LDecl: TPCDecl;
begin
  LDecl := DoModuleDecl(AModule, ADeclName);
  if LDecl = nil then
    Exit('<missing>');
  Result := LDecl.DocText;
end;

{ DoTypeDefOf }
// The TypeDef of a module-level type declaration (nil = none)
function DoTypeDefOf(const AModule: TPCModule; const ADeclName: string): TPCTypeExpr;
var
  LDecl: TPCDecl;
begin
  Result := nil;
  LDecl := DoModuleDecl(AModule, ADeclName);
  if LDecl is TPCTypeDecl then
    Result := TPCTypeDecl(LDecl).TypeDef;
end;

{ DoDocLabel }
// A doc_comments check message carrying the value got
function DoDocLabel(const ALabel: string; const AGot: string): string;
begin
  Result := 'doc_comments: ' + ALabel + ' (got "' + AGot + '")';
end;

procedure TPCParserTests.DoTestDocComments();
begin
  // PLAN-EDITOR E2.6: a /// block first on its lines, directly above the
  // line a declaration, field or choice value starts on, is its DocText
  // (fixture by scripts\zb_ed\gen_docs.py; expectations by hand from it)
  DoWithIn(DoProbeDir('par\docs'), 'docs.pcpp',
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LType: TPCTypeExpr;
      LMember: TPCMemberItem;
      LText: string;
    begin
      Check(DoCodes(AErrors) = '', 'doc_comments: docs parses (got ' + DoCodes(AErrors) + ')');
      LText := DoDocOf(AModule, 'GA');
      Check(LText = '', DoDocLabel('a doc above the var keyword is nobody''s', LText));
      LText := DoDocOf(AModule, 'GB');
      Check(LText = 'The second'#10'counter.', DoDocLabel('two lines, top-down', LText));
      LText := DoDocOf(AModule, 'GC');
      Check(LText = '', DoDocLabel('// is no doc', LText));
      LText := DoDocOf(AModule, 'GD');
      Check(LText = '', DoDocLabel('//// is no doc', LText));
      LText := DoDocOf(AModule, 'GE');
      Check(LText = '  indented keeps 2', DoDocLabel('one blank dropped, the rest kept', LText));
      LText := DoDocOf(AModule, 'GF');
      Check(LText = '', DoDocLabel('a blank line breaks the block', LText));
      LText := DoDocOf(AModule, 'GH');
      Check(LText = '', DoDocLabel('a /// after a token is no doc', LText));
      LText := DoDocOf(AModule, 'TRec');
      Check(LText = 'A record.', DoDocLabel('type', LText));
      LText := DoDocOf(AModule, 'R');
      Check(LText = 'Does R.'#10'@param AP the p', DoDocLabel('routine, raw (tags are the LSP''s)', LText));
      LText := DoDocOf(AModule, 'KX');
      Check(LText = #$00E9' text', DoDocLabel('const, UTF-8 text', LText));
      LText := DoDocOf(AModule, 'TCol');
      Check(LText = 'Colours.', DoDocLabel('the first node on a line takes its doc', LText));

      LType := DoTypeDefOf(AModule, 'TRec');
      LMember := nil;
      if (LType is TPCRecordType) and (TPCRecordType(LType).Members.Count > 0) then
        LMember := TPCRecordType(LType).Members[0];
      Check(LMember is TPCField, 'doc_comments: TRec has its field');
      if LMember is TPCField then
      begin
        LText := TPCField(LMember).DocText;
        Check(LText = 'The field.', DoDocLabel('field', LText));
      end;

      LType := DoTypeDefOf(AModule, 'TCol');
      Check((LType is TPCChoicesType) and (TPCChoicesType(LType).Values.Count = 2), 'doc_comments: TCol has 2 values');
      if (LType is TPCChoicesType) and (TPCChoicesType(LType).Values.Count = 2) then
      begin
        LText := TPCChoicesType(LType).Values[0].DocText;
        Check(LText = '', DoDocLabel('a value on its type''s line takes no doc', LText));
      end;

      LType := DoTypeDefOf(AModule, 'TCol2');
      Check((LType is TPCChoicesType) and (TPCChoicesType(LType).Values.Count = 2), 'doc_comments: TCol2 has 2 values');
      if (LType is TPCChoicesType) and (TPCChoicesType(LType).Values.Count = 2) then
      begin
        LText := TPCChoicesType(LType).Values[0].DocText;
        Check(LText = 'first value', DoDocLabel('choice value', LText));
        LText := TPCChoicesType(LType).Values[1].DocText;
        Check(LText = '', DoDocLabel('the next value has none', LText));
      end;

      LType := DoTypeDefOf(AModule, 'TObj');
      LMember := nil;
      if (LType is TPCRecordType) and (TPCRecordType(LType).Members.Count > 0) then
        LMember := TPCRecordType(LType).Members[0];
      Check((LMember is TPCMethodItem) and (TPCMethodItem(LMember).Routine <> nil), 'doc_comments: TObj has its method');
      if (LMember is TPCMethodItem) and (TPCMethodItem(LMember).Routine <> nil) then
      begin
        LText := TPCMethodItem(LMember).Routine.DocText;
        Check(LText = 'Puts.', DoDocLabel('method (not taken by its member item)', LText));
      end;
    end);
end;

end.
