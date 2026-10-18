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
  UTestCase.Emitter - emitter tests (PLAN-EMITTER A4 MODULE)

  TTestCase suite for TPCEmitter (PaskalCPP.Emitter). Each fixture folder
  tests\probe\emit\module\<test>\ (scripts\zb_emit\gen_module.py) holds the
  main file <test>.pcpp, its imported units, and the expected
  <Module>.h.txt / <Module>.cpp.txt of every module (derived from the
  contract, <SRC> = the module's SourceFile with forward slashes). Every
  module of the analyzed AST is emitted and compared. WriteFiles writes the
  same bytes (no BOM, LF only); a folder that cannot be created is EM0001.
  A mismatch keeps the actual text in %TEMP%\pcpp-emit-actual\.

  Dependencies: StdApp.TestCase, StdApp.Base, PaskalCPP.AST,
    PaskalCPP.Emitter, UTestFrontend
===============================================================================}

unit UTestCase.Emitter;

interface

uses
  StdApp.TestCase;

type

  { TPCEmitterTests }
  TPCEmitterTests = class(TTestCase)
  private
    // Emits every module of tests\probe\emit\<AArea>\<ATest>\<AMain>.pcpp
    // (AMain '' = ATest: the main file's stem is its module name)
    // ACodes: the reports analysis must give (warnings; '' = none)
    procedure DoCheckDir(const ATest: string; const AMain: string = ''; const AArea: string = 'module';
      const ACodes: string = '');
    procedure DoCheckTypes(const ATest: string);
    procedure DoCheckDecls(const ATest: string; const ACodes: string = '');
    procedure DoTestDeclsVars();
    procedure DoTestDeclsConsts();
    procedure DoTestDeclsConstsReach();
    procedure DoTestDeclsRoutines();
    procedure DoTestDeclsExterns();
    procedure DoTestDeclsForward();
    procedure DoTestDeclsDllExports();
    procedure DoTestDeclsClinkDemoted();
    procedure DoTestDeclsMethods();
    procedure DoTestDeclsLocals();
    procedure DoTestDeclsVariadics();
    procedure DoTestDeclsRuns();
    procedure DoTestDeclsIncludeAfter();
    procedure DoTestDeclsPlacement();
    procedure DoCheckStmts(const ATest: string);
    procedure DoTestStmtsIfs();
    procedure DoTestStmtsLoops();
    procedure DoTestStmtsForInt();
    procedure DoTestStmtsForChoices();
    procedure DoTestStmtsMatch();
    procedure DoTestStmtsJumps();
    procedure DoTestStmtsGuards();
    procedure DoTestStmtsReturnBody();
    procedure DoTestStmtsBareImport();
    procedure DoTestStmtsForCpp();
    procedure DoCheckExprs(const ATest: string);
    procedure DoTestExprsOps();
    procedure DoTestExprsNames();
    procedure DoTestExprsStrings();
    procedure DoTestExprsSets();
    procedure DoTestExprsRecords();
    procedure DoTestExprsRecordExtensions();
    procedure DoTestExprsCpp();
    procedure DoTestExprsSpans();
    procedure DoTestExprsSpanMap();
    procedure DoTestExprsCppForms();
    procedure DoTestExprsMethods();
    procedure DoTestExprsVarargs();
    procedure DoTestExprsVarargsLocal();
    procedure DoTestExprsOverloadPick();
    procedure DoTestExprsConversions();
    procedure DoTestExprsClinkPointer();
    procedure DoTestIntrinsics();
    procedure DoTestIntrinsicsInTest();
    procedure DoTestIntrinsicsWide();
    procedure DoTestIntrinsicsPrint();
    procedure DoTestIntrinsicsCreate();
    procedure DoTestCover();
    function DoEmitTo(const APath: string; const AOutDir: string): Boolean;
    function DoCompileTu(const AZig: string; const ARuntime: string; const ATu: string; const ATarget: string;
      out AOutput: string; out ARaised: string): Cardinal;
    procedure DoCompileWitness(const AZig: string; const ARuntime: string; const ATu: string; const ATarget: string);
    procedure DoTestSyntaxWitness();
    procedure DoCheckV1Map(const ATest: string; const ANeedle: string; const ALine: Integer;
      const AAlignName: string; const AMarker: string);
    procedure DoTestV1LocationMap();
    procedure DoTestTypesBuiltins();
    procedure DoTestTypesPointers();
    procedure DoTestTypesArrays();
    procedure DoTestTypesRoutineTypes();
    procedure DoTestTypesCppTypes();
    procedure DoTestTypesNamed();
    procedure DoTestTypesSets();
    procedure DoTestTypesChoices();
    procedure DoTestTypesForward();
    procedure DoTestTypesRecords();
    procedure DoTestTypesRecordConsts();
    procedure DoTestTypesRecordAlign();
    procedure DoTestTypesRecordAlignValue();
    procedure DoTestTypesRecordPacked();
    procedure DoTestTypesOverlayFit();
    procedure DoTestTypesOverlayZero();
    procedure DoTestTypesChoicesBits();
    procedure DoTestTypesRecordMisaligned();
    procedure DoTestTypesLocal();
    procedure DoTestTypesSpans();
    procedure DoTestExeBody();
    procedure DoTestEmptyUnit();
    procedure DoTestImportInclude();
    procedure DoTestInitFinalOrder();
    procedure DoTestTestModeOn();
    procedure DoTestTestModeOff();
    procedure DoTestImportedTestsRegistered();
    procedure DoTestDllHooks();
    procedure DoTestLibHooks();
    procedure DoTestModuleNamedMath();
    procedure DoTestModuleNamedIndex();
    procedure DoTestHeaderCppstart();
    procedure DoTestPreprocHeader();
    procedure DoTestPreprocSource();
    procedure DoTestBodyPreprocLast();
    procedure DoTestWriteFiles();
    procedure DoTestWriteFilesFail();
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  WinAPI.Windows,
  System.SysUtils,
  System.IOUtils,
  StdApp.Base,
  StdApp.Utils,
  PaskalCPP.Common,
  PaskalCPP.AST,
  PaskalCPP.Emitter,
  UTestFrontend;

const
  { PC_TEST_EMIT_AREAS }
  // Every fixture area under tests\probe\emit\ the syntax witness compiles;
  // depth\ holds the F-J5 bracket-depth nests (V2, scripts\zb_emit\gen_depth.py);
  // cover\ the bnf-map.md checklist rows (scripts\zb_emit\gen_cover.py)
  PC_TEST_EMIT_AREAS: array[0..7] of string = ('module', 'types', 'decls', 'stmts', 'exprs', 'intr', 'depth',
    'cover');
  { PC_TEST_EMIT_CODES_FILE }
  // A cover row's expected analysis reports (codes, comma separated); absent = none
  PC_TEST_EMIT_CODES_FILE = 'codes.txt';
  { PC_TEST_EMIT_TARGETS }
  // The official targets (DESIGN sec 7)
  PC_TEST_EMIT_TARGETS: array[0..1] of string = ('x86_64-windows-gnu', 'x86_64-linux-gnu');
  { PC_TEST_EMIT_ENTRY_CALLS }
  // The runtime calls of the main module's entry (main, dll / lib hooks): the
  // trailer is not a module fact (TPCModule.ResolvedUsesRuntime excludes it)
  PC_TEST_EMIT_ENTRY_CALLS: array[0..1] of string = ('::pcpp::init(', '::pcpp::enter(');
  { PC_TEST_EMIT_TEST_RUNNER }
  // Only a test mode main calls it: test blocks are compiled in, which the
  // runtime fact (a lib's, never in test mode) leaves out
  PC_TEST_EMIT_TEST_RUNNER = '::pcpp::run_tests(';
  { PC_TEST_EMIT_LIB_HOOK }
  PC_TEST_EMIT_LIB_HOOK = 'pcpp_lib_startup';

function DoEmittedNamesRuntime(const AHeader: string; const ASource: string): Boolean;
var
  LSource: string;
  LCall: string;
begin
  // The witness's side of the r10 rule: the module's emitted C++, the entry's
  // runtime calls removed, names the runtime
  LSource := ASource;
  for LCall in PC_TEST_EMIT_ENTRY_CALLS do
    LSource := LSource.Replace(LCall, '(');
  Result := TPCAst.TextNamesRuntime(AHeader) or TPCAst.TextNamesRuntime(LSource);
end;

function DoExpected(const ADir: string; const AModule: TPCModule; const AExt: string): string;
begin
  // The expected text with <SRC> = the module's own SourceFile, '/' slashes
  try
    Result := TEncoding.UTF8.GetString(TFile.ReadAllBytes(TPath.Combine(ADir, AModule.ModuleName + AExt)));
  except
    on E: Exception do
      Exit('<cannot read the expected file: ' + E.Message + '>');
  end;
  Result := Result.Replace('<SRC>', AModule.SourceFile.Replace('\', '/'));
end;

procedure DoKeepActual(const ATest: string; const AName: string; const AText: string);
var
  LDir: string;
begin
  // A mismatch keeps the actual text for the diff (never under tests\)
  try
    LDir := TPath.Combine(TPath.GetTempPath(), 'pcpp-emit-actual');
    TDirectory.CreateDirectory(LDir);
    TFile.WriteAllBytes(TPath.Combine(LDir, ATest + '.' + AName), TEncoding.UTF8.GetBytes(AText));
  except
    on E: Exception do
      Exit;
  end;
end;

function DoSameBytes(const AFirst: TBytes; const ASecond: TBytes): Boolean;
var
  LIndex: Integer;
begin
  Result := Length(AFirst) = Length(ASecond);
  if not Result then
    Exit;
  for LIndex := 0 to High(AFirst) do
  begin
    if AFirst[LIndex] <> ASecond[LIndex] then
      Exit(False);
  end;
end;

function DoPlainBytes(const ABytes: TBytes): Boolean;
var
  LIndex: Integer;
begin
  // H13: no UTF-8 BOM, no CR
  Result := not ((Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF));
  for LIndex := 0 to High(ABytes) do
  begin
    if ABytes[LIndex] = 13 then
      Exit(False);
  end;
end;

{ TPCEmitterTests }

constructor TPCEmitterTests.Create();
begin
  inherited;

  Title := 'Emitter';
  RegisterTest('exe_body', DoTestExeBody);
  RegisterTest('empty_unit', DoTestEmptyUnit);
  RegisterTest('import_include', DoTestImportInclude);
  RegisterTest('init_final_order', DoTestInitFinalOrder);
  RegisterTest('test_mode_on', DoTestTestModeOn);
  RegisterTest('test_mode_off', DoTestTestModeOff);
  RegisterTest('imported_tests_registered', DoTestImportedTestsRegistered);
  RegisterTest('dll_hooks', DoTestDllHooks);
  RegisterTest('lib_hooks', DoTestLibHooks);
  RegisterTest('module_named_math', DoTestModuleNamedMath);
  RegisterTest('module_named_index', DoTestModuleNamedIndex);
  RegisterTest('header_cppstart', DoTestHeaderCppstart);
  RegisterTest('preproc_header', DoTestPreprocHeader);
  RegisterTest('preproc_source', DoTestPreprocSource);
  RegisterTest('body_preproc_last', DoTestBodyPreprocLast);
  RegisterTest('write_files', DoTestWriteFiles);
  RegisterTest('write_files_fail', DoTestWriteFilesFail);
  RegisterTest('types_builtins', DoTestTypesBuiltins);
  RegisterTest('types_pointers', DoTestTypesPointers);
  RegisterTest('types_arrays', DoTestTypesArrays);
  RegisterTest('types_routine_types', DoTestTypesRoutineTypes);
  RegisterTest('types_cpp_types', DoTestTypesCppTypes);
  RegisterTest('types_named', DoTestTypesNamed);
  RegisterTest('types_sets', DoTestTypesSets);
  RegisterTest('types_choices', DoTestTypesChoices);
  RegisterTest('types_forward', DoTestTypesForward);
  RegisterTest('types_records', DoTestTypesRecords);
  RegisterTest('types_record_consts', DoTestTypesRecordConsts);
  RegisterTest('types_record_align', DoTestTypesRecordAlign);
  RegisterTest('types_record_align_value', DoTestTypesRecordAlignValue);
  RegisterTest('types_record_packed', DoTestTypesRecordPacked);
  RegisterTest('types_overlay_fit', DoTestTypesOverlayFit);
  RegisterTest('types_overlay_zero', DoTestTypesOverlayZero);
  RegisterTest('types_choices_bits', DoTestTypesChoicesBits);
  RegisterTest('types_record_misaligned', DoTestTypesRecordMisaligned);
  RegisterTest('types_local', DoTestTypesLocal);
  RegisterTest('types_spans', DoTestTypesSpans);
  RegisterTest('decls_vars', DoTestDeclsVars);
  RegisterTest('decls_consts', DoTestDeclsConsts);
  RegisterTest('decls_consts_reach', DoTestDeclsConstsReach);
  RegisterTest('decls_routines', DoTestDeclsRoutines);
  RegisterTest('decls_externs', DoTestDeclsExterns);
  RegisterTest('decls_forward', DoTestDeclsForward);
  RegisterTest('decls_dll_exports', DoTestDeclsDllExports);
  RegisterTest('decls_clink_demoted', DoTestDeclsClinkDemoted);
  RegisterTest('decls_methods', DoTestDeclsMethods);
  RegisterTest('decls_locals', DoTestDeclsLocals);
  RegisterTest('decls_variadics', DoTestDeclsVariadics);
  RegisterTest('decls_runs', DoTestDeclsRuns);
  RegisterTest('decls_include_after', DoTestDeclsIncludeAfter);
  RegisterTest('decls_placement', DoTestDeclsPlacement);
  RegisterTest('stmts_ifs', DoTestStmtsIfs);
  RegisterTest('stmts_loops', DoTestStmtsLoops);
  RegisterTest('stmts_for_int', DoTestStmtsForInt);
  RegisterTest('stmts_for_choices', DoTestStmtsForChoices);
  RegisterTest('stmts_match', DoTestStmtsMatch);
  RegisterTest('stmts_jumps', DoTestStmtsJumps);
  RegisterTest('stmts_guards', DoTestStmtsGuards);
  RegisterTest('stmts_return_body', DoTestStmtsReturnBody);
  RegisterTest('stmts_bare_import', DoTestStmtsBareImport);
  RegisterTest('stmts_for_cpp', DoTestStmtsForCpp);
  RegisterTest('exprs_ops', DoTestExprsOps);
  RegisterTest('exprs_names', DoTestExprsNames);
  RegisterTest('exprs_strings', DoTestExprsStrings);
  RegisterTest('exprs_sets', DoTestExprsSets);
  RegisterTest('exprs_records', DoTestExprsRecords);
  RegisterTest('exprs_record_ext', DoTestExprsRecordExtensions);
  RegisterTest('exprs_cpp', DoTestExprsCpp);
  RegisterTest('exprs_spans', DoTestExprsSpans);
  RegisterTest('exprs_span_map', DoTestExprsSpanMap);
  RegisterTest('exprs_cpp_forms', DoTestExprsCppForms);
  RegisterTest('exprs_methods', DoTestExprsMethods);
  RegisterTest('exprs_varargs', DoTestExprsVarargs);
  RegisterTest('exprs_varargs_local', DoTestExprsVarargsLocal);
  RegisterTest('exprs_overload_pick', DoTestExprsOverloadPick);
  RegisterTest('exprs_conversions', DoTestExprsConversions);
  RegisterTest('exprs_clink_pointer', DoTestExprsClinkPointer);
  RegisterTest('intrinsics', DoTestIntrinsics);
  RegisterTest('intrinsics_in_test', DoTestIntrinsicsInTest);
  RegisterTest('intrinsics_wide', DoTestIntrinsicsWide);
  RegisterTest('intrinsics_print', DoTestIntrinsicsPrint);
  RegisterTest('intrinsics_create', DoTestIntrinsicsCreate);
  RegisterTest('cover', DoTestCover);
  RegisterTest('syntax_witness', DoTestSyntaxWitness);
  RegisterTest('v1_location_map', DoTestV1LocationMap);
end;

procedure TPCEmitterTests.Run();
begin
  inherited;
end;

procedure TPCEmitterTests.DoCheckDir(const ATest: string; const AMain: string; const AArea: string;
  const ACodes: string);
var
  LDir: string;
  LMain: string;
begin
  LDir := DoProbeDir('emit\' + AArea + '\' + ATest);
  LMain := AMain;
  if LMain = '' then
    LMain := ATest;
  DoWithEmit(TPath.Combine(LDir, LMain + '.pcpp'),
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors; const AHeader: string;
      const ASource: string)
    var
      LIndex: Integer;
      LModule: TPCModule;
      LHeader: string;
      LSource: string;
      LExpected: string;
      LTestMode: Boolean;
    begin
      Check(DoCodes(AErrors) = ACodes, ATest + ': analyzed and emitted with the reports [' + ACodes + '] (' +
        DoReports(AErrors) + ')');
      if AErrors.HasErrors() then
        Exit;
      LTestMode := ASource.Contains(PC_TEST_EMIT_TEST_RUNNER);
      // r10 D-R10-2: a lib's hooks exist exactly when the program uses the runtime
      if AModule.ModuleKind = mkLib then
        Check(ASource.Contains(PC_TEST_EMIT_LIB_HOOK) = AAst.UsesRuntime(),
          ATest + ': lib hooks present = UsesRuntime (' + BoolToStr(AAst.UsesRuntime(), True) + ')');
      // Every module of the AST has its expected pair, and no other one
      Check(AAst.ModuleCount() = Length(TDirectory.GetFiles(LDir, '*.h.txt')),
        ATest + ': one expected header per module');
      for LIndex := 0 to AAst.ModuleCount() - 1 do
      begin
        LModule := AAst.ModuleAt(LIndex);
        if LModule = AModule then
        begin
          LHeader := AHeader;
          LSource := ASource;
        end
        else if not DoEmitOne(AAst, AModule, LModule, AErrors, LHeader, LSource) then
        begin
          Check(False, ATest + ': ' + LModule.ModuleName + ' emitted (' + DoCodes(AErrors) + ')');
          Continue;
        end;
        LExpected := DoExpected(LDir, LModule, '.h.txt');
        if LHeader <> LExpected then
          DoKeepActual(ATest, LModule.ModuleName + '.h.txt', LHeader);
        Check(LHeader = LExpected, ATest + ': ' + LModule.ModuleName + PC_EMT_HEADER_EXT);
        LExpected := DoExpected(LDir, LModule, '.cpp.txt');
        if LSource <> LExpected then
          DoKeepActual(ATest, LModule.ModuleName + '.cpp.txt', LSource);
        Check(LSource = LExpected, ATest + ': ' + LModule.ModuleName + PC_EMT_SOURCE_EXT);
        // r10 D-R10-4, the hooked witness: SEM's fact against the real text,
        // both ways (a new emitter site SEM does not know, a dead SEM row)
        if not LTestMode then
          Check(LModule.ResolvedUsesRuntime = DoEmittedNamesRuntime(LHeader, LSource),
            ATest + ': ' + LModule.ModuleName + ' ResolvedUsesRuntime = ' +
            BoolToStr(LModule.ResolvedUsesRuntime, True) + ' matches its C++');
      end;
    end);
end;

procedure TPCEmitterTests.DoTestExeBody();
begin
  DoCheckDir('exe_body');
end;

procedure TPCEmitterTests.DoTestEmptyUnit();
begin
  DoCheckDir('empty_unit');
end;

procedure TPCEmitterTests.DoTestImportInclude();
begin
  DoCheckDir('import_include');
end;

procedure TPCEmitterTests.DoTestInitFinalOrder();
begin
  DoCheckDir('init_final_order');
end;

procedure TPCEmitterTests.DoTestTestModeOn();
begin
  DoCheckDir('test_mode_on');
end;

procedure TPCEmitterTests.DoTestTestModeOff();
begin
  DoCheckDir('test_mode_off');
end;

procedure TPCEmitterTests.DoTestImportedTestsRegistered();
begin
  DoCheckDir('imported_tests_registered');
end;

procedure TPCEmitterTests.DoTestDllHooks();
begin
  DoCheckDir('dll_hooks');
end;

procedure TPCEmitterTests.DoTestLibHooks();
begin
  DoCheckDir('lib_hooks');
end;

procedure TPCEmitterTests.DoTestModuleNamedMath();
begin
  DoCheckDir('module_named_math', 'math');
end;

procedure TPCEmitterTests.DoTestModuleNamedIndex();
begin
  DoCheckDir('module_named_index', 'index');
end;

procedure TPCEmitterTests.DoTestHeaderCppstart();
begin
  DoCheckDir('header_cppstart');
end;

procedure TPCEmitterTests.DoTestPreprocHeader();
begin
  DoCheckDir('preproc_header');
end;

procedure TPCEmitterTests.DoTestPreprocSource();
begin
  DoCheckDir('preproc_source');
end;

procedure TPCEmitterTests.DoTestBodyPreprocLast();
begin
  DoCheckDir('body_preproc_last');
end;

procedure TPCEmitterTests.DoTestWriteFiles();
var
  LDir: string;
begin
  LDir := DoProbeDir('emit\module\exe_body');
  DoWithSem(TPath.Combine(LDir, 'exe_body.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LEmitter: TPCEmitter;
      LOut: string;
      LHeader: TBytes;
      LSource: TBytes;
      LFile: TBytes;
    begin
      Check(DoCodes(AErrors) = '', 'write_files: analyzed with no report');
      LOut := TPath.Combine(TPath.GetTempPath(), 'pcpp-emit-write');
      if TDirectory.Exists(LOut) then
        TDirectory.Delete(LOut, True);
      LEmitter := TPCEmitter.Create();
      try
        LEmitter.SetErrors(AErrors);
        LEmitter.Init(AAst, AModule);
        Check(LEmitter.WriteFiles(LOut), 'write_files: WriteFiles succeeds');
        Check(LEmitter.EmitModule(AModule, LHeader, LSource), 'write_files: EmitModule succeeds');
        LFile := TFile.ReadAllBytes(TPath.Combine(LOut, 'exe_body' + PC_EMT_HEADER_EXT));
        Check(DoSameBytes(LFile, LHeader), 'write_files: the header file holds the emitted bytes');
        Check(DoPlainBytes(LFile), 'write_files: header without BOM or CR');
        LFile := TFile.ReadAllBytes(TPath.Combine(LOut, 'exe_body' + PC_EMT_SOURCE_EXT));
        Check(DoSameBytes(LFile, LSource), 'write_files: the source file holds the emitted bytes');
        Check(DoPlainBytes(LFile), 'write_files: source without BOM or CR');
      finally
        LEmitter.Free();
      end;
      TDirectory.Delete(LOut, True);
    end);
end;

procedure TPCEmitterTests.DoTestWriteFilesFail();
var
  LDir: string;
begin
  LDir := DoProbeDir('emit\module\exe_body');
  DoWithSem(TPath.Combine(LDir, 'exe_body.pcpp'), 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LEmitter: TPCEmitter;
      LFile: string;
    begin
      // An output folder path that is a file: the folder cannot be created
      LFile := TPath.Combine(TPath.GetTempPath(), 'pcpp-emit-notadir.txt');
      TFile.WriteAllText(LFile, 'x');
      LEmitter := TPCEmitter.Create();
      try
        LEmitter.SetErrors(AErrors);
        LEmitter.Init(AAst, AModule);
        Check(not LEmitter.WriteFiles(LFile), 'write_files_fail: WriteFiles fails');
        Check(DoCodes(AErrors) = PC_ERR_EMT_001, 'write_files_fail: EM0001 reported (' + DoCodes(AErrors) + ')');
      finally
        LEmitter.Free();
      end;
      TFile.Delete(LFile);
    end);
end;

procedure TPCEmitterTests.DoCheckTypes(const ATest: string);
begin
  // tests\probe\emit\types\<ATest>\ (scripts\zb_emit\gen_types.py, A5)
  DoCheckDir(ATest, '', 'types');
end;

procedure TPCEmitterTests.DoTestTypesBuiltins();
begin
  DoCheckTypes('builtins');
end;

procedure TPCEmitterTests.DoTestTypesPointers();
begin
  DoCheckTypes('pointers');
end;

procedure TPCEmitterTests.DoTestTypesArrays();
begin
  DoCheckTypes('arrays');
end;

procedure TPCEmitterTests.DoTestTypesRoutineTypes();
begin
  DoCheckTypes('routine_types');
end;

procedure TPCEmitterTests.DoTestTypesCppTypes();
begin
  DoCheckTypes('cpp_types');
end;

procedure TPCEmitterTests.DoTestTypesNamed();
begin
  DoCheckTypes('named');
end;

procedure TPCEmitterTests.DoTestTypesSets();
begin
  DoCheckTypes('sets');
end;

procedure TPCEmitterTests.DoTestTypesChoices();
begin
  DoCheckTypes('choices_fmt');
end;

procedure TPCEmitterTests.DoTestTypesForward();
begin
  DoCheckTypes('fwd');
end;

procedure TPCEmitterTests.DoTestTypesRecords();
begin
  DoCheckTypes('records');
end;

procedure TPCEmitterTests.DoTestTypesRecordConsts();
begin
  // F22: align(KA) and a width : KW written folded in the header, the
  // private consts KA / KW in the source (syntax_witness compiles it)
  DoCheckTypes('recconst');
end;

procedure TPCEmitterTests.DoTestTypesRecordAlign();
begin
  // PLAN-PASKAL-ERRORS E3: a record with a C/C++ field gets every leaf type
  // in its alignas pack and the align check as its first member
  // (syntax_witness compiles it: align(8) passes)
  DoCheckTypes('recalign');
end;

procedure TPCEmitterTests.DoTestTypesRecordAlignValue();
begin
  // F31: a C++ align value is taken guarded in the clause and judged by the
  // power, max and natural checks (syntax_witness compiles it: 8 passes)
  DoCheckTypes('recval');
end;

procedure TPCEmitterTests.DoTestTypesRecordPacked();
begin
  // PLAN-RECORDS M9: records are plain data; a packed field or parent of a
  // type only clang lays out gets the packs_as_field check, a PaskalCPP one
  // none; a packed record with a member parent aligns 1 (syntax_witness
  // compiles it: every check passes)
  DoCheckTypes('recpack');
end;

procedure TPCEmitterTests.DoTestTypesOverlayFit();
begin
  // PLAN-COMPLIANCE F34: a union member of a type only clang knows gets the
  // fits_overlay check, a PaskalCPP-only one none (syntax_witness compiles
  // it: every check passes, inside anonymous structs and unions too)
  DoCheckTypes('recovl');
end;

procedure TPCEmitterTests.DoTestTypesOverlayZero();
begin
  // PLAN-COMPLIANCE F35: every union starts with a zero member as large as
  // its layout twin (a nested type of the named type, numbered in preorder):
  // nested unions, two anonymous overlays in one record, a wchar bitfield
  // (syntax_witness compiles it)
  DoCheckTypes('ovzero');
end;

procedure TPCEmitterTests.DoTestTypesChoicesBits();
begin
  // PLAN-COMPLIANCE F37: a choices bitfield is stored as the type's underlying
  // integer: a store casts its value to the integer (an assignment, a record
  // literal's field), a read casts back to the choices type (syntax_witness
  // compiles it: no constant-store warning)
  DoCheckTypes('choicebits');
end;

procedure TPCEmitterTests.DoTestTypesRecordMisaligned();
begin
  // PLAN-RECORDS M8: a field a packed record may misalign goes to a const
  // aggregate parameter and to println as a copy, auto(x) (syntax_witness
  // compiles it)
  DoCheckTypes('recmis');
end;

procedure TPCEmitterTests.DoTestTypesLocal();
begin
  DoCheckTypes('local_types');
end;

procedure TPCEmitterTests.DoTestTypesSpans();
var
  LDir: string;
begin
  // `using TQ = ::pcpp_m_geo::TPt;` is source C++ line 8 (pcpp line 6; a
  // private type the header does not name is the source's, E5): the
  // declaration spans the whole text (cols 1..30), the named type exactly
  // its own bytes (cols 12..29)
  LDir := DoProbeDir('emit\types\named');
  DoWithEmit(TPath.Combine(LDir, 'named.pcpp'),
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors; const AHeader: string;
      const ASource: string)
    var
      LStmt: TPCStmt;
      LDecl: TPCTypeDecl;
      LSpans: TArray<TPCEmitSpan>;
    begin
      Check(DoCodes(AErrors) = '', 'types_spans: analyzed and emitted with no report (' + DoCodes(AErrors) + ')');
      LDecl := nil;
      for LStmt in AModule.Decls do
      begin
        if (LStmt is TPCTypeDecl) and (TPCTypeDecl(LStmt).DeclName = 'TQ') then
          LDecl := TPCTypeDecl(LStmt);
      end;
      Check(LDecl <> nil, 'types_spans: TQ found');
      if LDecl = nil then
        Exit;
      LSpans := LDecl.EmitSpans;
      Check(Length(LSpans) = 1, 'types_spans: one span on the declaration');
      if Length(LSpans) = 1 then
        Check((LSpans[0].OutFile = ofSource) and (LSpans[0].CppLine = 8) and (LSpans[0].SourceLine = 6) and
          (LSpans[0].StartCol = 1) and (LSpans[0].EndCol = 30), 'types_spans: declaration span source 8, cols 1..30');
      LSpans := LDecl.TypeDef.EmitSpans;
      Check(Length(LSpans) = 1, 'types_spans: one span on the named type');
      if Length(LSpans) = 1 then
        Check((LSpans[0].OutFile = ofSource) and (LSpans[0].CppLine = 8) and (LSpans[0].SourceLine = 6) and
          (LSpans[0].StartCol = 12) and (LSpans[0].EndCol = 29), 'types_spans: named type span source 8, cols 12..29');
    end);
end;

procedure TPCEmitterTests.DoCheckDecls(const ATest: string; const ACodes: string);
begin
  // tests\probe\emit\decls\<ATest>\ (scripts\zb_emit\gen_decls.py, A6)
  DoCheckDir(ATest, '', 'decls', ACodes);
end;

procedure TPCEmitterTests.DoTestDeclsVars();
begin
  DoCheckDecls('vars');
end;

procedure TPCEmitterTests.DoTestDeclsConsts();
begin
  DoCheckDecls('consts');
end;

procedure TPCEmitterTests.DoTestDeclsConstsReach();
begin
  // F22: private consts an exported const's value reaches go to the header
  // (syntax_witness compiles it on both targets); KP stays in the source
  DoCheckDecls('consts_reach');
end;

procedure TPCEmitterTests.DoTestDeclsRoutines();
begin
  DoCheckDecls('routines');
end;

procedure TPCEmitterTests.DoTestDeclsExterns();
begin
  DoCheckDecls('externs');
end;

procedure TPCEmitterTests.DoTestDeclsForward();
begin
  DoCheckDecls('fwdr');
end;

procedure TPCEmitterTests.DoTestDeclsDllExports();
begin
  DoCheckDecls('dlle');
end;

procedure TPCEmitterTests.DoTestDeclsClinkDemoted();
begin
  // Both clink members are demoted, one SM0323 each (SEM R-LINK)
  DoCheckDecls('demote', 'SM0323,SM0323');
end;

procedure TPCEmitterTests.DoTestDeclsMethods();
begin
  DoCheckDecls('meths');
end;

procedure TPCEmitterTests.DoTestDeclsLocals();
begin
  DoCheckDecls('locals');
end;

procedure TPCEmitterTests.DoTestDeclsVariadics();
begin
  DoCheckDecls('variad');
end;

procedure TPCEmitterTests.DoTestDeclsRuns();
begin
  DoCheckDecls('runs');
end;

procedure TPCEmitterTests.DoTestDeclsIncludeAfter();
begin
  DoCheckDecls('incafter');
end;

procedure TPCEmitterTests.DoTestDeclsPlacement();
begin
  // PLAN-PASKAL-ERRORS E5: a private module-level type is the header's only
  // when the header's own text names it (gen_decls.py place_*)
  DoCheckDecls('place_reach');
  DoCheckDecls('place_fwd');
  DoCheckDecls('place_obj');
  DoCheckDecls('place_verb');
  DoCheckDecls('place_const');
  DoCheckDecls('place_var');
end;

procedure TPCEmitterTests.DoCheckStmts(const ATest: string);
begin
  // A7: tests\probe\emit\stmts\ (scripts\zb_emit\gen_stmts.py)
  DoCheckDir(ATest, '', 'stmts');
end;

procedure TPCEmitterTests.DoTestStmtsIfs();
begin
  DoCheckStmts('ifs');
end;

procedure TPCEmitterTests.DoTestStmtsLoops();
begin
  DoCheckStmts('loops');
end;

procedure TPCEmitterTests.DoTestStmtsForInt();
begin
  DoCheckStmts('forint');
end;

procedure TPCEmitterTests.DoTestStmtsBareImport();
begin
  // PLAN-IMPORT-RESOLUTION: bare names an import exports (a lone routine,
  // one unit's set, a var, a for iterator) written as their qualified forms
  DoCheckStmts('barepick');
end;

procedure TPCEmitterTests.DoTestStmtsForCpp();
begin
  // A C/C++ variable as the for iterator (BNF sec 5): written as named, the
  // end's type from decltype (TPCFor.ResolvedIteratorOpaque)
  DoCheckStmts('forcpp');
end;

procedure TPCEmitterTests.DoTestStmtsForChoices();
begin
  DoCheckStmts('forch');
end;

procedure TPCEmitterTests.DoTestStmtsMatch();
begin
  DoCheckStmts('matchs');
end;

procedure TPCEmitterTests.DoTestStmtsJumps();
begin
  DoCheckStmts('jumps');
end;

procedure TPCEmitterTests.DoTestStmtsGuards();
begin
  DoCheckStmts('guards');
end;

procedure TPCEmitterTests.DoTestStmtsReturnBody();
begin
  DoCheckStmts('retbody');
end;

procedure TPCEmitterTests.DoCheckExprs(const ATest: string);
begin
  // A8: tests\probe\emit\exprs\ (scripts\zb_emit\gen_exprs.py)
  DoCheckDir(ATest, '', 'exprs');
end;

procedure TPCEmitterTests.DoTestExprsOps();
begin
  DoCheckExprs('ops');
end;

procedure TPCEmitterTests.DoTestExprsNames();
begin
  DoCheckExprs('names');
end;

procedure TPCEmitterTests.DoTestExprsStrings();
begin
  DoCheckExprs('strs');
end;

procedure TPCEmitterTests.DoTestExprsSets();
begin
  DoCheckExprs('sets');
end;

procedure TPCEmitterTests.DoTestExprsRecords();
begin
  DoCheckExprs('recs');
end;

procedure TPCEmitterTests.DoTestExprsRecordExtensions();
begin
  // PLAN-RECORDS A6 (M10 / M12 / M14): the parent as a member, a pointer
  // upcast, an inherited member, a downcast, a literal on an extension, a
  // ranked overloads call (syntax_witness compiles it on both targets)
  DoCheckExprs('recx');
end;

procedure TPCEmitterTests.DoTestExprsCpp();
begin
  DoCheckExprs('cppx');
end;

procedure TPCEmitterTests.DoTestExprsSpans();
begin
  DoCheckExprs('spans');
end;

procedure TPCEmitterTests.DoTestExprsCppForms();
begin
  DoCheckExprs('cppforms');
end;

procedure TPCEmitterTests.DoTestExprsMethods();
begin
  DoCheckExprs('meth2');
  // PLAN-OBJECT D10: hidden members as C++ protected
  DoCheckExprs('hidden');
  // PLAN-OBJECT D7: virtual / override / final / abstract, final object
  DoCheckExprs('disp');
  // PLAN-OBJECT D3: init / done (constructors, the member-init list, the
  // writer's return to an init's local), constructions
  DoCheckExprs('life');
  // PLAN-OBJECT O5: copy / move members (deleted copies, ::pcpp::Live, the
  // copy constructor, copy-and-swap, a swap move assignment), a moved return
  DoCheckExprs('copyv');
  // PLAN-OBJECT deferred test pass: interfaces, implements, const methods
  // and interface properties (O7 / O10 / O13b); properties, embeds and
  // default / indexed / abstract accessors (O8-O10); operators (O11); own /
  // ref / weak, is / as, alive / lock (O6 / O12)
  DoCheckExprs('objface');
  DoCheckExprs('objprop');
  DoCheckExprs('objops');
  DoCheckExprs('objown');
end;

procedure TPCEmitterTests.DoTestExprsVarargs();
begin
  DoCheckExprs('varpack');
end;

procedure TPCEmitterTests.DoTestExprsVarargsLocal();
begin
  // A varargs local's members lower as varargs' own (SEM's TPCMember.ResolvedVarargs)
  DoCheckExprs('varlocal');
end;

procedure TPCEmitterTests.DoTestExprsOverloadPick();
begin
  // F18: a call SEM limited to some overload members goes through
  // ::pcpp::overloads of exactly those (TPCCall.ResolvedCandidates); an
  // imported member's types are borrowed on the caller's line
  DoCheckExprs('ovpick');
end;

procedure TPCEmitterTests.DoTestExprsConversions();
begin
  DoCheckExprs('conv');
end;

procedure TPCEmitterTests.DoTestExprsClinkPointer();
begin
  DoCheckExprs('v3link');
end;

procedure TPCEmitterTests.DoTestIntrinsics();
begin
  // A9: tests\probe\emit\intr\ (scripts\zb_emit\gen_intrinsics.py)
  DoCheckDir('intr', '', 'intr');
end;

procedure TPCEmitterTests.DoTestIntrinsicsInTest();
begin
  DoCheckDir('intrtest', '', 'intr');
end;

procedure TPCEmitterTests.DoTestIntrinsicsWide();
begin
  // PLAN-PASKAL-ERRORS E4: print / println of wide text by TPCTypeExpr.PrintForm
  // (utf8 / WCStr / CStr, a wchar bitfield; syntax_witness compiles it)
  DoCheckDir('intrwide', '', 'intr');
end;

procedure TPCEmitterTests.DoTestIntrinsicsPrint();
begin
  // PLAN-PASKAL-ERRORS E7: every print argument by TPCTypeExpr.PrintFormOfArg
  // (typed pointer, the C/C++ formatter check, arrays through print_map;
  // syntax_witness compiles it)
  DoCheckDir('intrprint', '', 'intr');
end;

procedure TPCEmitterTests.DoTestIntrinsicsCreate();
begin
  // PLAN-RECORDS M1: create / destroy on a pointer to a record, the object
  // lowering (syntax_witness compiles it)
  DoCheckDir('intrcreate', '', 'intr');
end;

procedure TPCEmitterTests.DoTestCover();
var
  LRoot: string;
  LDirs: TArray<string>;
  LDir: string;
  LTest: string;
  LCodesFile: string;
  LCodes: string;
begin
  // Every row of tests\probe\emit\cover\ (scripts\zb_emit\gen_cover.py: the
  // bnf-map.md checklist); a row's expected reports are its codes.txt
  LRoot := DoProbeDir('emit\cover');
  try
    LDirs := TDirectory.GetDirectories(LRoot);
  except
    on E: Exception do
    begin
      Check(False, 'cover: cannot list ' + LRoot + ': ' + E.Message);
      Exit;
    end;
  end;
  Check(Length(LDirs) > 0, 'cover: rows exist in ' + LRoot);
  for LDir in LDirs do
  begin
    LTest := TPath.GetFileName(LDir);
    LCodes := '';
    LCodesFile := TPath.Combine(LDir, PC_TEST_EMIT_CODES_FILE);
    try
      if TFile.Exists(LCodesFile) then
        LCodes := TEncoding.UTF8.GetString(TFile.ReadAllBytes(LCodesFile)).Trim();
    except
      on E: Exception do
      begin
        Check(False, 'cover: cannot read ' + LCodesFile + ': ' + E.Message);
        Continue;
      end;
    end;
    DoCheckDir(LTest, '', 'cover', LCodes);
  end;
end;

function DoMainFile(const ATestDir: string; const ATest: string): string;
var
  LFiles: TArray<string>;
begin
  // A fixture's main file: <test>.pcpp, else its only .pcpp ('' = unknown)
  Result := TPath.Combine(ATestDir, ATest + '.pcpp');
  if TFile.Exists(Result) then
    Exit;
  LFiles := TDirectory.GetFiles(ATestDir, '*.pcpp');
  if Length(LFiles) = 1 then
    Result := LFiles[0]
  else
    Result := '';
end;

function TPCEmitterTests.DoEmitTo(const APath: string; const AOutDir: string): Boolean;
var
  LOutDir: string;
  LName: string;
  LOk: Boolean;
begin
  // Every module of the fixture through WriteFiles (the files the build
  // gets), analysis first; False = reported
  LOutDir := AOutDir;
  LName := APath;
  LOk := False;
  DoWithEmit(APath,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors; const AHeader: string;
      const ASource: string)
    var
      LEmitter: TPCEmitter;
    begin
      if AErrors.HasErrors() then
      begin
        Check(False, 'syntax_witness: ' + LName + ' analyzed (' + DoReports(AErrors) + ')');
        Exit;
      end;
      LEmitter := TPCEmitter.Create();
      try
        LEmitter.SetErrors(AErrors);
        LEmitter.Init(AAst, AModule);
        LOk := LEmitter.WriteFiles(LOutDir);
      finally
        LEmitter.Free();
      end;
      Check(LOk, 'syntax_witness: ' + LName + ' written (' + DoReports(AErrors) + ')');
    end);
  Result := LOk;
end;

function TPCEmitterTests.DoCompileTu(const AZig: string; const ARuntime: string; const ATu: string;
  const ATarget: string; out AOutput: string; out ARaised: string): Cardinal;
var
  LParams: string;
  LOutput: string;
  LExitCode: DWORD;
begin
  // clang (through zig c++, which takes no -fsyntax-only) compiles the TU
  // against the real runtime header (ARuntime), the fixtures' C/C++ names
  // (tests\probe\emit\names\fixture_names.h) force-included; the exit code,
  // the first 1500 characters of the output, a launch failure
  LParams := 'c++ -c -o ' + TUtils.QuoteCommandArg(ATu + '.' + ATarget + '.o') + ' -std=gnu++23 -target ' +
    ATarget + ' -I ' + TUtils.QuoteCommandArg(ARuntime) + ' -include ' +
    TUtils.QuoteCommandArg(TPath.Combine(DoProbeDir('emit\names'), 'fixture_names.h')) + ' ' +
    TUtils.QuoteCommandArg(ATu);
  LOutput := '';
  LExitCode := 42;
  ARaised := '';
  try
    TUtils.CaptureConsoleOutput('', PChar(AZig), PChar(LParams), TPath.GetDirectoryName(ATu), LExitCode, nil,
      procedure(const ALine: string; const AData: Pointer)
      begin
        if Length(LOutput) < 1500 then
          LOutput := LOutput + ALine + #10;
      end);
  except
    on E: Exception do
      ARaised := E.Message;
  end;
  AOutput := LOutput;
  Result := LExitCode;
end;

procedure TPCEmitterTests.DoCompileWitness(const AZig: string; const ARuntime: string; const ATu: string;
  const ATarget: string);
var
  LOutput: string;
  LExitCode: DWORD;
  LRaised: string;
begin
  LExitCode := DoCompileTu(AZig, ARuntime, ATu, ATarget, LOutput, LRaised);
  Check((LRaised = '') and (LExitCode = 0), Format('syntax_witness: %s compiles for %s (exit %d%s)%s%s',
    [TPath.GetFileName(ATu), ATarget, LExitCode, LRaised, #10, LOutput]));
end;

function DoFirstError(const AOutput: string; out AFile: string; out ALine: UInt64; out ACol: UInt64): Boolean;
var
  LLine: string;
  LAt: Integer;
  LHead: string;
  LColon: Integer;
begin
  // The first clang 'path:line:col: error:' line of AOutput; the path may hold
  // a drive colon, so line and column are taken from the right
  Result := False;
  AFile := '';
  ALine := 0;
  ACol := 0;
  for LLine in AOutput.Split([#10]) do
  begin
    LAt := Pos(': error: ', LLine);
    if LAt = 0 then
      Continue;
    LHead := Copy(LLine, 1, LAt - 1);
    LColon := LHead.LastIndexOf(':');
    if LColon < 0 then
      Continue;
    ACol := StrToUInt64Def(LHead.Substring(LColon + 1), 0);
    LHead := LHead.Substring(0, LColon);
    LColon := LHead.LastIndexOf(':');
    if LColon < 0 then
      Continue;
    ALine := StrToUInt64Def(LHead.Substring(LColon + 1), 0);
    AFile := LHead.Substring(0, LColon);
    Exit((ALine > 0) and (ACol > 0));
  end;
end;

{ TestFirstErrorMarker }
function TestFirstErrorMarker(const AOutput: string): string;
var
  LStart: Integer;
  LNext: Integer;
  LText: string;
  LAt: Integer;
begin
  // The 'pcpp:SM03xx' marker inside clang's FIRST error (its text runs to
  // the next 'error: ': a static_assert requirement spans several lines);
  // '' = none there
  Result := '';
  LStart := AOutput.IndexOf('error: ');
  if LStart < 0 then
    Exit;
  LNext := AOutput.IndexOf('error: ', LStart + 1);
  if LNext < 0 then
    LNext := AOutput.Length;
  LText := AOutput.Substring(LStart, LNext - LStart);
  LAt := LText.IndexOf('pcpp:SM0');
  if LAt < 0 then
    Exit;
  Result := LText.Substring(LAt, Length(PC_FRONTEND_CHECK_NATURAL));
end;

procedure TPCEmitterTests.DoCheckV1Map(const ATest: string; const ANeedle: string; const ALine: Integer;
  const AAlignName: string; const AMarker: string);
var
  LTest: string;
  LNeedle: string;
  LLineNo: Integer;
  LAlignName: string;
  LMarker: string;
  LDir: string;
begin
  // V1 (hooked): the fixture's one C++ error sits on .pcpp line ALine (2:
  // where the header and the source both write); clang's location through
  // #line must map back to the .pcpp column of the node holding the error
  // (ANeedle's column in that line), on both targets. AAlignName <> '' = the
  // error is one of the emitter's align checks (PLAN-PASKAL-ERRORS E3 / F31):
  // it carries AMarker and TPCAst.AlignRecordAt names that record
  LTest := ATest;
  LNeedle := ANeedle;
  LLineNo := ALine;
  LAlignName := AAlignName;
  LMarker := AMarker;
  LDir := DoProbeDir('emit\v1\' + ATest);
  DoWithEmit(TPath.Combine(LDir, ATest + '.pcpp'),
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors; const AHeader: string;
      const ASource: string)
    var
      LEmitter: TPCEmitter;
      LOutDir: string;
      LZig: string;
      LTarget: string;
      LOutput: string;
      LRaised: string;
      LExitCode: DWORD;
      LFile: string;
      LLine: UInt64;
      LCol: UInt64;
      LOutFile: string;
      LOutLine: UInt64;
      LOutCol: UInt64;
      LWant: Integer;
      LOk: Boolean;
      LRecord: TPCRecordType;
      LRecordName: string;
    begin
      if AErrors.HasErrors() then
      begin
        Check(False, 'v1_location_map: ' + LTest + ' analyzed (' + DoReports(AErrors) + ')');
        Exit;
      end;
      LOutDir := TPath.Combine(TPath.Combine(TPath.GetTempPath(), 'pcpp-emit-v1'), LTest);
      LEmitter := TPCEmitter.Create();
      try
        LEmitter.SetErrors(AErrors);
        LEmitter.Init(AAst, AModule);
        LOk := LEmitter.WriteFiles(LOutDir);
      finally
        LEmitter.Free();
      end;
      if not LOk then
      begin
        Check(False, 'v1_location_map: ' + LTest + ' written (' + DoReports(AErrors) + ')');
        Exit;
      end;
      // The fixture is ASCII: the character position is the byte column
      LWant := Pos(LNeedle, TFile.ReadAllLines(AModule.SourceFile)[LLineNo - 1]);
      LZig := TUtils.ResolvePath('$P:res\zig\zig.exe');
      for LTarget in PC_TEST_EMIT_TARGETS do
      begin
        LExitCode := DoCompileTu(LZig, TUtils.ResolvePath('$P:res\runtime'), TPath.Combine(LOutDir, LTest + '.pcpp.cpp'), LTarget,
          LOutput, LRaised);
        if not ((LRaised = '') and (LExitCode <> 0) and DoFirstError(LOutput, LFile, LLine, LCol)) then
        begin
          Check(False, Format('v1_location_map: %s fails to compile for %s with an error line (exit %d%s)%s%s',
            [LTest, LTarget, LExitCode, LRaised, #10, LOutput]));
          Continue;
        end;
        Check(AAst.TranslateLocation(LFile, LLine, LCol, LOutFile, LOutLine, LOutCol) and
          (LOutLine = UInt64(LLineNo)) and (LOutCol = UInt64(LWant)),
          Format('v1_location_map: %s %s: clang (%d, %d) -> .pcpp (%d, %d) (got %d, %d)%s%s',
          [LTest, LTarget, LLine, LCol, LLineNo, LWant, LOutLine, LOutCol, #10, LOutput]));
        if LAlignName = '' then
          Continue;
        // The FIRST error is that check: its marker is in the first error's text
        Check((TestFirstErrorMarker(LOutput) = LMarker) and
          AAst.AlignRecordAt(LFile, LLine, LCol, LRecord, LRecordName) and (LRecordName = LAlignName),
          Format('v1_location_map: %s %s: the align check failed (%s) at the align value of %s (got %s)%s%s',
          [LTest, LTarget, LMarker, LAlignName, LRecordName, #10, LOutput]));
      end;
    end);
end;

procedure TPCEmitterTests.DoTestV1LocationMap();
begin
  // An error in the header prototype (the source TU includes the header
  // first) and one in the source body behind a longer header line, at the
  // name clang reports inside the cpp("...") value (TPCVerbatim.ValueMap)
  DoCheckV1Map('v1hdr', 'pcpp_v1_no_such_type', 2, '', '');
  DoCheckV1Map('v1src', 'pcpp_v1_undeclared', 2, '', '');
  // F21 + E3: the align check of a record with a C/C++ field fails at the
  // align value, not the record's name, and names the record
  DoCheckV1Map('v1align', '2) G', 2, 'TR', PC_FRONTEND_CHECK_NATURAL);
  // F28 + F31: a C++ value 3 on the line after `record`: the clause takes
  // it guarded (clang cannot refuse it), the power check fails first, at the
  // value's start on the value's line
  DoCheckV1Map('v1next', 'cpp("3")', 3, 'TR', PC_FRONTEND_CHECK_POWER);
  // F31: a C++ value above PC_ALIGN_MAX (a power of two): the max check
  DoCheckV1Map('v1max', 'cpp("16384")', 2, 'TR', PC_FRONTEND_CHECK_MAX);
end;

procedure TPCEmitterTests.DoTestSyntaxWitness();
var
  LZig: string;
  LRuntime: string;
  LOutRoot: string;
  LArea: string;
  LTestDir: string;
  LTest: string;
  LMain: string;
  LOutDir: string;
  LTu: string;
  LTarget: string;
begin
  // PLAN-EMITTER V5 / PLAN-RUNTIME V1 (hooked, as Conditionals.datamodel_witness):
  // every emit fixture's modules, written by the emitter, compile with the
  // bundled clang on both official targets against the real runtime header
  // (res\runtime: the emitter's names are its contract; zig caches unchanged TUs)
  LZig := TUtils.ResolvePath('$P:res\zig\zig.exe');
  LRuntime := TUtils.ResolvePath('$P:res\runtime');
  Check(TFile.Exists(LZig) and TFile.Exists(TPath.Combine(LRuntime, 'pcpp_runtime.h')) and
    TFile.Exists(TPath.Combine(DoProbeDir('emit\names'), 'fixture_names.h')),
    'syntax_witness: the bundled zig, the runtime header and the fixtures'' C/C++ names exist');
  LOutRoot := TPath.Combine(TPath.GetTempPath(), 'pcpp-emit-syntax');
  try
    if TDirectory.Exists(LOutRoot) then
      TDirectory.Delete(LOutRoot, True);
  except
    on E: Exception do
      Check(False, 'syntax_witness: cannot clear ' + LOutRoot + ': ' + E.Message);
  end;
  for LArea in PC_TEST_EMIT_AREAS do
  begin
    for LTestDir in TDirectory.GetDirectories(DoProbeDir('emit\' + LArea)) do
    begin
      LTest := TPath.GetFileName(LTestDir);
      LMain := DoMainFile(LTestDir, LTest);
      if LMain = '' then
      begin
        Check(False, 'syntax_witness: ' + LArea + '\' + LTest + ' has a main file');
        Continue;
      end;
      LOutDir := TPath.Combine(LOutRoot, LArea + '\' + LTest);
      if not DoEmitTo(LMain, LOutDir) then
        Continue;
      for LTu in TDirectory.GetFiles(LOutDir, '*.pcpp.cpp') do
      begin
        for LTarget in PC_TEST_EMIT_TARGETS do
          DoCompileWitness(LZig, LRuntime, LTu, LTarget);
      end;
    end;
  end;
end;

procedure TPCEmitterTests.DoTestExprsSpanMap();
var
  LDir: string;
begin
  // `LY := LX + 1;` (.pcpp line 6) is `LY = ((LX) + (1));` on source C++
  // line 8: LX's span is exactly its bytes (cols 8 .. 10), and a C++ column
  // inside the literal 1 (col 15) maps back to the 1's .pcpp column (14)
  LDir := DoProbeDir('emit\exprs\spans');
  DoWithEmit(TPath.Combine(LDir, 'spans.pcpp'),
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors; const AHeader: string;
      const ASource: string)
    var
      LRoutine: TPCRoutine;
      LAssign: TPCAssign;
      LName: TPCExpr;
      LSpans: TArray<TPCEmitSpan>;
      LFile: string;
      LLine: UInt64;
      LCol: UInt64;
    begin
      Check(DoCodes(AErrors) = '', 'exprs_span_map: analyzed and emitted with no report (' + DoReports(AErrors) + ')');
      LRoutine := nil;
      if (AModule.Decls.Count > 0) and (AModule.Decls[0] is TPCRoutine) then
        LRoutine := TPCRoutine(AModule.Decls[0]);
      if (LRoutine = nil) or (LRoutine.Body = nil) or (LRoutine.Body.Stmts.Count <> 1) or
        not (LRoutine.Body.Stmts[0] is TPCExprStmt) or
        not (TPCExprStmt(LRoutine.Body.Stmts[0]).Expr is TPCAssign) then
      begin
        Check(False, 'exprs_span_map: R holds one assignment statement');
        Exit;
      end;
      LAssign := TPCAssign(TPCExprStmt(LRoutine.Body.Stmts[0]).Expr);
      if not (LAssign.ValueExpr is TPCBinary) then
      begin
        Check(False, 'exprs_span_map: the value is LX + 1');
        Exit;
      end;
      LName := TPCBinary(LAssign.ValueExpr).Left;
      LSpans := LName.EmitSpans;
      Check((Length(LSpans) = 1) and (LSpans[0].OutFile = ofSource) and (LSpans[0].CppLine = 8) and
        (LSpans[0].SourceLine = 6) and (LSpans[0].StartCol = 8) and (LSpans[0].EndCol = 10),
        'exprs_span_map: LX = source C++ line 8, cols 8 .. 10');
      Check(AAst.TranslateLocation(AModule.SourceFile, 6, 15, LFile, LLine, LCol) and (LLine = 6) and (LCol = 14),
        Format('exprs_span_map: C++ (6, 15) -> .pcpp (6, 14) (got %d, %d)', [LLine, LCol]));
    end);
end;

end.
