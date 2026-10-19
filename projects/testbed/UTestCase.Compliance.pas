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
  UTestCase.Compliance - every registered res\tests file, checked

  PLAN-COMPLIANCE T2 (D5-D11). One test per registered file (its stem), on
  both official targets: built in-process (TPCCompiler, the target as a
  default so the file's own @target wins), every report matched against the
  markers of the files the build read, the build's success against its ERROR
  markers, and a cmRun file run over pipes in its own folder (stdout and
  stderr in written order) against its EXPECT block and EXITCODE.
  Dependencies are built first, where their own commands put them. Not in
  -all (InRunAll False): `testbed.exe Compliance` at a plan's end,
  `testbed.exe Compliance.<stem>` per atom. dbg_ / lsp_ files are a person's
  checks and are never registered.

  Dependencies: StdApp.TestCase, StdApp.Base, StdApp.Utils, PaskalCPP.Compiler,
    UTestCompliance, UTestFrontend
===============================================================================}

unit UTestCase.Compliance;

interface

uses
  System.Generics.Collections,
  StdApp.Base,
  StdApp.TestCase,
  UTestCompliance;

type
  { TPCComplianceTests }
  TPCComplianceTests = class(TTestCase)
  private
    FEntries: TList<TPCComplianceEntry>;
    procedure DoAdd(const AStem: string; const ACategory: string;
      const AMode: TPCComplianceMode; const ADeps: array of string;
      const ATargets: array of string; const AOutputDirs: array of string;
      const AArgs: string);
    // The last DoAdd's program stdin: a file in res\tests (cmRun)
    procedure DoSetStdin(const AFileName: string);
    procedure DoRegister(const AIndex: Integer);
    function DoFind(const AStem: string; out AEntry: TPCComplianceEntry): Boolean;
    function DoOutputDir(const AEntry: TPCComplianceEntry; const ATarget: string): string;
    function DoRunsOn(const AEntry: TPCComplianceEntry; const ATarget: string): Boolean;
    function DoBuildDep(const AStem: string; const ATarget: string): Boolean;
    procedure DoCheckReports(const AStem: string; const ATarget: string;
      const AErrors: TErrors; const AMarkers: TList<TPCComplianceMarker>);
    procedure DoCheckRun(const AEntry: TPCComplianceEntry; const ATarget: string;
      const AArtifact: string; const ASpec: TPCComplianceSpec);
    procedure DoRunTarget(const AEntry: TPCComplianceEntry; const ATarget: string);
    procedure DoRunCli(const AEntry: TPCComplianceEntry);
    procedure DoRunEntry(const AIndex: Integer);
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Run(); override;
    class function InRunAll(): Boolean; override;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  StdApp.Utils,
  PaskalCPP.Common,
  PaskalCPP.Compiler,
  UTestFrontend;

const
  { PC_CMPL_MAX_ERRORS }
  // Every expected marker must be reportable: the budget a build stops at
  PC_CMPL_MAX_ERRORS = 100;

  { PC_CMPL_NO_EXIT }
  // An exit code no program returns: the run did not set it
  PC_CMPL_NO_EXIT = 4242;

{ DoReportText }
function DoReportText(const AErrors: TErrors; const AError: TError): string;
var
  LRange: TSourceRange;
begin
  LRange := AErrors.DisplayRange(AError.Range);
  Result := Format('%s(%d,%d) %s %s', [LRange.Filename, LRange.StartLine, LRange.StartColumn,
    AError.Code, AError.Message]);
end;

{ DoMatches }
function DoMatches(const AMarker: TPCComplianceMarker; const AErrors: TErrors;
  const AError: TError): Boolean;
var
  LRange: TSourceRange;
begin
  LRange := AErrors.DisplayRange(AError.Range);
  Result := TUtils.SamePath(AMarker.Filename, AError.Range.Filename) and
    (UInt64(AMarker.Line) = AError.Range.StartLine) and
    (AMarker.Severity = AError.Severity) and
    (AMarker.Code = AError.Code) and
    ((AMarker.Column = 0) or (UInt64(AMarker.Column) = LRange.StartColumn)) and
    ((AMarker.Text = '') or AError.Message.Contains(AMarker.Text));
end;

{ TPCComplianceTests }

constructor TPCComplianceTests.Create();
var
  LI: Integer;
begin
  inherited;

  Title := 'Compliance';
  FEntries := TList<TPCComplianceEntry>.Create();

  // The registered res\tests files, in category order (T4 and every F atom
  // add their rows here). A file only a person can check (dbg_, lsp_, a gui
  // window) is registered cmBuild: it must build, it is never run (D13)
  DoAdd('mod_kinds', 'mod', cmRun, [], [], [], '');
  DoAdd('mod_kinds_dll', 'mod', cmBuild, [], [], [], '');
  DoAdd('mod_kinds_lib', 'mod', cmBuild, [], [], [], '');
  DoAdd('mod_kinds_err_kind', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_kinds_err_unitmain', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_kinds_err_body', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_kinds_err_nobody', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_kinds_err_afterend', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_import', 'mod', cmRun, [], [], [], '');
  DoAdd('mod_import_err_place', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_import_err_cycle', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_import_err_missing', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_import_err_kind', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_import_err_duplicate', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_import_err_noname', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_import_err_notexported', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_import_err_transitive', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_import_err_case', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_import_err_own_module', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_import_bare', 'mod', cmRun, [], [], [], '');
  DoAdd('mod_import_bare_err_ambiguous', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_import_cpp_type', 'mod', cmRun, [], [], [], '');
  DoAdd('mod_initfinal', 'mod', cmRun, [], [], [], '');
  DoAdd('mod_initfinal_err_twice', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_initfinal_err_order', 'mod', cmCheck, [], [], [], '');
  DoAdd('mod_initfinal_err_returnvalue', 'mod', cmCheck, [], [], [], '');
  DoAdd('dir_conditional', 'dir', cmRun, [], [], [], '');
  DoAdd('dir_conditional_err_symbol', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_conditional_err_noopener', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_conditional_err_afterelse', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_conditional_err_unclosed', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_predefined', 'dir', cmRun, [], [], [], '');
  DoAdd('dir_prologue', 'dir', cmRun, [], [], [], '');
  DoAdd('dir_prologue_err_unknown', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_prologue_err_shape', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_prologue_err_place', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_prologue_err_twice', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_prologue_err_mainonly', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_prologue_err_breakpoint', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_optimize', 'dir', cmRun, [], [], [], '');
  DoAdd('dir_optimize_debug', 'dir', cmRun, [], [], [], '');
  DoAdd('dir_optimize_safe', 'dir', cmRun, [], [], [], '');
  DoAdd('dir_optimize_fast', 'dir', cmRun, [], [], [], '');
  DoAdd('dir_optimize_err_value', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_optimize_err_case', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_optimize_err_retired', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_subsystem', 'dir', cmRun, [], [], [], '');
  // A person checks the window; the tester builds it (user 2026-10-11)
  DoAdd('dir_subsystem_gui', 'dir', cmBuild, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dir_subsystem_err_value', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_subsystem_err_linux', 'dir', cmCheck, [], [PC_CMPL_TARGET_LINUX], [], '');
  DoAdd('dir_subsystem_err_dll', 'dir', cmCheck, [], [], [], '');
  // D8: a file whose own @target applies is registered for that target only
  DoAdd('dir_target', 'dir', cmRun, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dir_target_linux', 'dir', cmRun, [], [PC_CMPL_TARGET_LINUX], [], '');
  DoAdd('dir_target_err_place', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_target_err_branch', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_target_err_late', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_target_err_duplicate', 'dir', cmCheck, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dir_target_err_string', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_target_err_shape', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_target_err_unsupported', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_target_err_mismatch', 'dir', cmCheck, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  // Version info is a Windows resource: on Linux @addverinfo on is its own break
  DoAdd('dir_verinfo', 'dir', cmRun, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dir_verinfo_err_value', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_verinfo_err_range', 'dir', cmCheck, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dir_verinfo_err_noverinfo', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_verinfo_err_off', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_verinfo_err_lib', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_verinfo_err_linux', 'dir', cmCheck, [], [PC_CMPL_TARGET_LINUX], [], '');
  // An icon is a Windows resource: on Linux @exeicon is its own break
  DoAdd('dir_exeicon', 'dir', cmRun, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dir_exeicon_err_missing', 'dir', cmCheck, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dir_exeicon_err_path', 'dir', cmCheck, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dir_exeicon_err_dll', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_exeicon_err_linux', 'dir', cmCheck, [], [PC_CMPL_TARGET_LINUX], [], '');
  // dir_copydll names the dll's folders: it is built where its own command puts it (D9)
  DoAdd('dir_copydll_dll', 'dir', cmBuild, [], [],
    ['', ''], '');
  DoAdd('dir_copydll', 'dir', cmRun, ['dir_copydll_dll'], [], [], '');
  DoAdd('dir_copydll_err_missing', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_copydll_err_path', 'dir', cmCheck, [], [], [], '');
  // dir_linklibrary's unit links lib_plain from lib_plain's own folders (D9)
  DoAdd('dir_linklibrary', 'dir', cmRun, ['lib_plain'], [], [], '');
  DoAdd('dir_linklibrary_err_path', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_linklibrary_err_file', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_linklibrary_err_nolink', 'dir', cmBuild, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  // dir_addlibrarypath searches lib_plain's and lib_runtime's own folders (D9)
  DoAdd('dir_addlibrarypath', 'dir', cmRun, ['lib_plain', 'lib_runtime'], [], [], '');
  DoAdd('dir_addlibrarypath_err_missing', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_addlibrarypath_err_file', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_addlibrarypath_err_path', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_addlibrarypath_err_nopath', 'dir', cmBuild, [], [], [], '');
  // dir_addmodulepath's units live in res\tests\libs (user 2026-10-11: one level)
  DoAdd('dir_addmodulepath', 'dir', cmRun, [], [], [], '');
  DoAdd('dir_addmodulepath_err_missing', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_addmodulepath_err_file', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_addmodulepath_err_path', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_addmodulepath_err_unit', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_addmodulepath_err_nopath', 'dir', cmCheck, [], [], [], '');
  // dir_addincludepath's header lives in res\tests\libs; _byunit: a unit's path
  // adds to the one build
  DoAdd('dir_addincludepath', 'dir', cmRun, [], [], [], '');
  DoAdd('dir_addincludepath_byunit', 'dir', cmRun, [], [], [], '');
  DoAdd('dir_addincludepath_err_missing', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_addincludepath_err_file', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_addincludepath_err_path', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_addincludepath_err_nopath', 'dir', cmBuild, [], [], [], '');
  // dir_message's unit (dir_message_unit) reports two of its seven: its markers
  // are read because the build read it (D7)
  DoAdd('dir_message', 'dir', cmRun, [], [], [], '');
  DoAdd('dir_message_err_error', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_message_err_fatal', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_message_err_severity', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_message_err_text', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_message_err_string', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_addsourcefile', 'dir', cmRun, [], [], [], '');
  DoAdd('dir_addsourcefile_err_language', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_addsourcefile_err_missing', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_addsourcefile_err_clang', 'dir', cmBuild, [], [], [], '');
  DoAdd('dir_cppdefine', 'dir', cmRun, [], [], [], '');
  DoAdd('dir_cppdefine_err_conflict', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_cppdefine_err_undef', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_cppdefine_err_reserved', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_cppdefine_err_name', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_cppdefine_err_notdefined', 'dir', cmBuild, [], [], [], '');
  DoAdd('decl_scope', 'decl', cmRun, [], [], [], '');
  DoAdd('decl_scope_err_own', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_scope_err_before_var', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_scope_err_before_type', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_scope_err_before_routine', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_scope_err_before_local', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_scope_err_dup_module', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_scope_err_dup_param', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_scope_err_dup_local', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_scope_err_dup_body', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_var', 'decl', cmRun, [], [], [], '');
  DoAdd('decl_var_err_narrow', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_var_err_fit', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_var_err_external_init', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_var_err_external_local', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_var_err_external_body', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_const', 'decl', cmRun, [], [], [], '');
  DoAdd('decl_const_err_notype', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_const_err_var', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_const_err_call', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_const_err_fit', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_const_err_negative', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_const_err_float', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_routine', 'decl', cmRun, [], [], [], '');
  DoAdd('decl_routine_err_var_literal', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_routine_err_var_type', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_routine_err_arg_fit', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_routine_err_novalue', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_routine_err_return_value', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_routine_err_missing_return', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_routine_err_method_blocks', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_linkage', 'decl', cmRun, [], [], [], '');
  DoAdd('decl_linkage_err_overload', 'decl', cmBuild, [], [], [], '');
  // decl_external links lib_plain's and lib_runtime's libraries by its clauses (D9 folders)
  DoAdd('decl_external', 'decl', cmRun, ['lib_plain', 'lib_runtime'], [], [], '');
  DoAdd('decl_external_err_lib_file', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_external_err_lib_const', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_external_err_lib_name', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_external_err_lib_unknown', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_external_err_nolib', 'decl', cmBuild, [], [], [], '');
  DoAdd('decl_variadic', 'decl', cmRun, [], [], [], '');
  DoAdd('decl_variadic_err_clink_nofixed', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_variadic_err_overload', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_variadic_err_outside', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_variadic_err_clink_count', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_forward', 'decl', cmRun, [], [], [], '');
  DoAdd('decl_forward_err_only', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_forward_err_type_nofull', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_forward_err_after_full', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_forward_err_kind', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_forward_err_type_exported', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_forward_err_linkage', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_forward_err_exported', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_forward_err_variadic', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_forward_err_param_name', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_forward_err_param_mode', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_forward_err_return', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_forward_err_routine_nofull', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_forward_err_routine_types', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_exported', 'decl', cmRun, [], [], [], '');
  DoAdd('decl_exported_err_cpp_decl', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_exported_err_twice', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_exported_err_placement', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_exported_err_begin', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_exported_err_local', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_exported_err_var_block', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_exported_err_const_own', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_exported_err_type', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_exported_err_cpp_hidden', 'decl', cmBuild, [], [], [], '');
  DoAdd('decl_overload', 'decl', cmRun, [], [], [], '');
  DoAdd('decl_overload_err_same_types', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_overload_err_names', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_overload_err_return', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_overload_err_var', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_overload_err_const', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_overload_err_none', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_overload_err_not_routine', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_overload_err_unqualified', 'decl', cmCheck, [], [], [], '');
  // PLAN-RECORDS A11 (M11): reserved names, scripts\zb_cmpl\f4\gen_recext.py
  DoAdd('decl_reserved', 'decl', cmRun, [], [], [], '');
  DoAdd('decl_reserved_err_const', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_reserved_err_type', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_reserved_err_field', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_reserved_err_choice', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_reserved_err_var', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_reserved_err_routine', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_reserved_err_param', 'decl', cmCheck, [], [], [], '');
  DoAdd('decl_reserved_err_local', 'decl', cmCheck, [], [], [], '');
  DoAdd('type_builtin', 'type', cmRun, [], [], [], '');
  DoAdd('type_builtin_err_star', 'type', cmCheck, [], [], [], '');
  DoAdd('type_builtin_err_ref', 'type', cmCheck, [], [], [], '');
  DoAdd('type_builtin_err_rref', 'type', cmCheck, [], [], [], '');
  DoAdd('type_builtin_err_const_after', 'type', cmCheck, [], [], [], '');
  DoAdd('type_builtin_err_const_before', 'type', cmCheck, [], [], [], '');
  DoAdd('type_builtin_err_volatile', 'type', cmCheck, [], [], [], '');
  DoAdd('type_alias', 'type', cmRun, [], [], [], '');
  DoAdd('type_alias_err_self', 'type', cmCheck, [], [], [], '');
  DoAdd('type_alias_err_self_ptr', 'type', cmCheck, [], [], [], '');
  DoAdd('type_alias_err_self_array', 'type', cmCheck, [], [], [], '');
  DoAdd('type_alias_err_var', 'type', cmCheck, [], [], [], '');
  DoAdd('type_alias_err_const', 'type', cmCheck, [], [], [], '');
  DoAdd('type_alias_err_routine', 'type', cmCheck, [], [], [], '');
  DoAdd('type_alias_err_overloads', 'type', cmCheck, [], [], [], '');
  DoAdd('type_alias_err_module', 'type', cmCheck, [], [], [], '');
  DoAdd('type_alias_err_unit_var', 'type', cmCheck, [], [], [], '');
  DoAdd('type_alias_err_choice_value', 'type', cmCheck, [], [], [], '');
  DoAdd('type_alias_err_unknown', 'type', cmBuild, [], [], [], '');
  DoAdd('type_record', 'type', cmRun, [], [], [], '');
  DoAdd('type_record_err_prefix_parent', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_prefix_packed', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_prefix_twice', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_object_packed', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_object_align', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_overlay_packed', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_anon_overlay_packed', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_method', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_anon_record', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_parent_object', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_parent_choices', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_parent_alias', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_reuse', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_reuse_anon', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_compare', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_compare_overlay', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_compare_array', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_align_power', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_align_zero', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_align_negative', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_align_max', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_align_below', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_align_below_cpp_field', 'type', cmBuild, [], [], [], '');
  DoAdd('type_record_err_align_below_cpp_value', 'type', cmBuild, [], [], [], '');
  DoAdd('type_record_err_align_cpp_power', 'type', cmBuild, [], [], [], '');
  DoAdd('type_record_err_align_cpp_max', 'type', cmBuild, [], [], [], '');
  DoAdd('type_record_err_align_cpp_packed', 'type', cmBuild, [], [], [], '');
  DoAdd('type_record_err_bit_type', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_bit_width', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_bit_wchar', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_bit_zero', 'type', cmCheck, [], [], [], '');
  // F38: a constant stored into a bitfield is held by its width (SM0200)
  DoAdd('type_record_err_bit_store', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_bit_store_unsigned', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_err_bit_store_literal', 'type', cmCheck, [], [], [], '');
  // F47: clang's record text, owned at the record's name
  DoAdd('type_record_err_too_large', 'type', cmBuild, [], [], [], '');
  // PLAN-RECORDS A11: record extensions, packed records, routine types and
  // set compound assignment, scripts\zb_cmpl\f4\gen_recext.py
  DoAdd('type_record_ext', 'type', cmRun, [], [], [], '');
  DoAdd('type_record_ext_err_downcast', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_ext_err_value_down', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_ext_err_var_down', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_ext_err_unrelated', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_ext_err_literal_field', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_ext_err_create', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_ext_err_self', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_packed', 'type', cmRun, [], [], [], '');
  DoAdd('type_record_packed_err_string', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_packed_err_dynarray', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_packed_err_nested', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_packed_err_var', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_packed_err_address', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_packed_err_compound', 'type', cmCheck, [], [], [], '');
  DoAdd('type_record_packed_err_upcast', 'type', cmCheck, [], [], [], '');
  DoAdd('type_routine', 'type', cmRun, [], [], [], '');
  DoAdd('type_routine_err_signature', 'type', cmCheck, [], [], [], '');
  DoAdd('type_routine_err_linkage', 'type', cmCheck, [], [], [], '');
  DoAdd('type_routine_err_argument', 'type', cmCheck, [], [], [], '');
  DoAdd('type_routine_err_width', 'type', cmCheck, [], [], [], '');
  DoAdd('type_routine_err_count', 'type', cmCheck, [], [], [], '');
  DoAdd('type_routine_err_count_variadic', 'type', cmCheck, [], [], [], '');
  DoAdd('type_routine_err_duplicate_param', 'type', cmCheck, [], [], [], '');
  DoAdd('type_routine_err_set', 'type', cmCheck, [], [], [], '');
  DoAdd('type_routine_err_procedure_value', 'type', cmCheck, [], [], [], '');
  // PLAN-COMPLIANCE F4 type_cpp (scripts\zb_cmpl\f4\gen_cpp_type.py)
  DoAdd('type_cpp', 'type', cmRun, [], [], [], '');
  DoAdd('type_cpp_err_cv_repeated', 'type', cmCheck, [], [], [], '');
  DoAdd('type_cpp_err_ref_not_last', 'type', cmCheck, [], [], [], '');
  DoAdd('type_cpp_err_template_open', 'type', cmCheck, [], [], [], '');
  DoAdd('type_cpp_err_elaborated', 'type', cmCheck, [], [], [], '');
  DoAdd('type_cpp_err_decltype', 'type', cmCheck, [], [], [], '');
  DoAdd('type_cpp_err_decltype_open', 'type', cmCheck, [], [], [], '');
  DoAdd('type_cpp_err_template_group_open', 'type', cmCheck, [], [], [], '');
  DoAdd('type_set', 'type', cmRun, [], [], [], '');
  DoAdd('type_set_err_div_assign', 'type', cmCheck, [], [], [], '');
  DoAdd('type_set_err_divide', 'type', cmCheck, [], [], [], '');
  // PLAN-COMPLIANCE F4 type_set (scripts\zb_cmpl\f4\gen_recext.py, its type_set section)
  DoAdd('type_set_err_bare', 'type', cmCheck, [], [], [], '');
  DoAdd('type_set_err_inline', 'type', cmCheck, [], [], [], '');
  DoAdd('type_set_err_integers', 'type', cmCheck, [], [], [], '');
  DoAdd('type_set_err_wchar', 'type', cmCheck, [], [], [], '');
  DoAdd('type_set_err_element', 'type', cmCheck, [], [], [], '');
  DoAdd('type_set_err_family', 'type', cmCheck, [], [], [], '');
  DoAdd('type_set_err_order', 'type', cmCheck, [], [], [], '');
  DoAdd('type_set_err_count', 'type', cmCheck, [], [], [], '');
  DoAdd('type_set_err_literal_range', 'type', cmCheck, [], [], [], '');
  DoAdd('type_set_err_other_set', 'type', cmCheck, [], [], [], '');
  DoAdd('type_set_err_in_element', 'type', cmCheck, [], [], [], '');
  // PLAN-COMPLIANCE F5 stmt_ (scripts\zb_cmpl\f4\gen_stmt.py)
  DoAdd('stmt_rules', 'stmt', cmRun, [], [], [], '');
  DoAdd('stmt_rules_err_cpp_switch', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_rules_err_semicolon', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_rules_err_no_effect', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_if', 'stmt', cmRun, [], [], [], '');
  DoAdd('stmt_if_err_condition', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_while', 'stmt', cmRun, [], [], [], '');
  DoAdd('stmt_while_err_condition', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_for', 'stmt', cmRun, [], [], [], '');
  DoAdd('stmt_for_err_constant', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_for_err_float', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_for_err_write', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_repeat', 'stmt', cmRun, [], [], [], '');
  DoAdd('stmt_repeat_err_condition', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_match', 'stmt', cmRun, [], [], [], '');
  DoAdd('stmt_match_err_subject', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_match_err_label_range', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_match_err_label_repeat', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_match_err_not_covered', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_match_err_label_constant', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_match_err_label_reversed', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_guard', 'stmt', cmRun, [], [], [], '');
  DoAdd('stmt_guard_err_empty', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_guard_err_cpp_jump', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_guard_err_cpp_jump_finally', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_guard_err_cpp_jump_except', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_guard_err_exccode', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_return', 'stmt', cmRun, [], [], [], '');
  DoAdd('stmt_return_err_needs_value', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_return_err_value', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_return_err_missing', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_return_err_finally', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_leave_skip', 'stmt', cmRun, [], [], [], '');
  DoAdd('stmt_leave_skip_err_leave', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_leave_skip_err_skip', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_leave_skip_err_leave_finally', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_leave_skip_err_skip_finally', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_local_decls', 'stmt', cmRun, [], [], [], '');
  DoAdd('stmt_local_decls_err_duplicate', 'stmt', cmCheck, [], [], [], '');
  DoAdd('stmt_local_decls_err_no_type', 'stmt', cmCheck, [], [], [], '');
  // PLAN-COMPLIANCE F6 expr_, part 1 (scripts\zb_cmpl\f4\gen_expr1.py)
  DoAdd('expr_assign', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_assign_err_equals', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_assign_err_constant', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_assign_err_convert', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_conditional', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_conditional_err_condition', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_logical', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_logical_err_int_operands', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_logical_err_cpp_word', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_relational', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_relational_err_chain', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_relational_err_cpp_equal', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_relational_err_operands', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_relational_err_record', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_relational_err_mixed_sign', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_arithmetic', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_arithmetic_err_operands', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_arithmetic_err_overflow', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_arithmetic_err_div_zero', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_arithmetic_err_min_div', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_arithmetic_err_into_narrow', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_arithmetic_err_mixed_sign', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_arithmetic_err_div_int64', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_arithmetic_err_compound', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_arithmetic_err_div_assign', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_arithmetic_err_char', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_float_const', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_float_const_err_inexact', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_float_const_err_lost_bit', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_bitwise', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_bitwise_err_float', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_bitwise_err_shift_count', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_bitwise_err_cpp_word', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_bitwise_err_into_bool', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_bitwise_err_bool_and', 'expr', cmCheck, [], [], [], '');
  // PLAN-COMPLIANCE F6 expr_, part 2 (scripts\zb_cmpl\f4\gen_expr2.py)
  DoAdd('expr_unary_postfix', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_unary_postfix_err_no_member', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_unary_postfix_err_not_int', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_unary_postfix_err_negate_string', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_unary_postfix_err_negate_min', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_unary_postfix_err_address_value', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_call_member', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_call_member_err_no_member', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_call_member_err_arrow_type', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_call_member_err_not_callable', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_casts', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_casts_err_one_arg', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_casts_err_named_args', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_casts_err_operand', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_casts_err_alias_args', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_casts_err_type_value', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_set_literal', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_set_literal_err_not_ordinal', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_set_literal_err_mixed', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_set_literal_err_low_high', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_set_literal_err_in_element', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_record_literal', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_record_literal_err_cpp_parent', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_record_literal_err_no_field', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_record_literal_err_twice', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_record_literal_err_order', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_varargs', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_varargs_err_value', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_varargs_err_type_module', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_varargs_err_local_assign', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_varargs_err_local_shape', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_varargs_err_count_call', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_varargs_err_local_count_call', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_conversion', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_conversion_err_narrow', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_conversion_err_argument', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_primary', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_primary_err_self_main', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_primary_err_parent_none', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_cpp', 'expr', cmRun, [], [], [], '');
  DoAdd('expr_cpp_err_sizeof_open', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_cpp_err_lambda_open', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_cpp_err_lambda_body', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_cpp_err_sizeof_parens', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_cpp_err_cast_open', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_cpp_err_new_primitive', 'expr', cmCheck, [], [], [], '');
  DoAdd('expr_cpp_err_clang', 'expr', cmBuild, [], [], [], '');
  // PLAN-COMPLIANCE F7 intr_ (scripts\zb_cmpl\f4\gen_intr.py)
  DoAdd('intr_len', 'intr', cmRun, [], [], [], '');
  DoAdd('intr_len_err_int', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_len_err_value', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_size', 'intr', cmRun, [], [], [], '');
  DoAdd('intr_size_err_value', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_size_err_args', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_utf8', 'intr', cmRun, [], [], [], '');
  DoAdd('intr_utf8_err_narrow', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_param', 'intr', cmRun, [], [], [], 'one two');
  DoAdd('intr_param_err_string', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_param_err_value', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_param_err_wide', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_memory', 'intr', cmRun, [], [], [], '');
  DoAdd('intr_memory_err_statement', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_memory_err_string', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_memory_err_unsigned', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_object', 'intr', cmRun, [], [], [], '');
  DoAdd('intr_object_err_int', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_object_err_object', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_weak', 'intr', cmRun, [], [], [], '');
  DoAdd('intr_weak_err_ref', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_setlength', 'intr', cmRun, [], [], [], '');
  DoAdd('intr_setlength_err_int', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_setlength_err_value', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_setlength_err_unsigned', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_exceptions', 'intr', cmRun, [], [], [], '');
  DoAdd('intr_exceptions_err_outside', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_exceptions_err_int', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_exceptions_err_wide', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_exceptions_unhandled', 'intr', cmRun, [], [], [], '');
  DoAdd('intr_print', 'intr', cmRun, [], [], [], '');
  DoAdd('intr_print_err_record', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_print_err_overload', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_print_err_value', 'intr', cmCheck, [], [], [], '');
  DoAdd('intr_print_err_cpp_value', 'intr', cmBuild, [], [], [], '');
  DoAdd('intr_print_err_format', 'intr', cmBuild, [], [], [], '');
  DoAdd('intr_print_err_format_not_literal', 'intr', cmBuild, [], [], [], '');
  DoAdd('intr_shadow', 'intr', cmRun, [], [], [], '');
  DoAdd('intr_shadow_err_type_arg', 'intr', cmCheck, [], [], [], '');
  // PLAN-COMPLIANCE F8 test_ (scripts\zb_cmpl\f4\gen_test.py)
  DoAdd('test_block', 'test', cmRun, [], [], [], '');
  DoAdd('test_block_err_place', 'test', cmCheck, [], [], [], '');
  DoAdd('test_block_err_const', 'test', cmCheck, [], [], [], '');
  DoAdd('test_block_err_two_var', 'test', cmCheck, [], [], [], '');
  DoAdd('test_block_err_empty', 'test', cmCheck, [], [], [], '');
  DoAdd('test_block_err_duplicate', 'test', cmCheck, [], [], [], '');
  DoAdd('test_asserts', 'test', cmRun, [], [], [], '');
  DoAdd('test_asserts_err_type', 'test', cmCheck, [], [], [], '');
  DoAdd('test_asserts_err_count', 'test', cmCheck, [], [], [], '');
  DoAdd('test_asserts_outside', 'test', cmRun, [], [], [], '');
  DoAdd('test_mode', 'test', cmRun, [], [], [], '');
  DoAdd('test_mode_err_value', 'test', cmCheck, [], [], [], '');
  DoAdd('test_mode_err_lib', 'test', cmCheck, [], [], [], '');
  DoAdd('test_mode_err_lib_tests', 'test', cmCheck, [], [], [], '');
  DoAdd('test_mode_off', 'test', cmRun, [], [], [], '');
  // PLAN-COMPLIANCE F9 lex_ (scripts\zb_cmpl\f4\gen_lex.py)
  DoAdd('lex_identifiers', 'lex', cmRun, [], [], [], '');
  DoAdd('lex_identifiers_err_char', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_identifiers_err_utf8', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_identifiers_err_at', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_integers', 'lex', cmRun, [], [], [], '');
  DoAdd('lex_integers_err_octal', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_integers_err_shape', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_integers_err_overflow', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_integers_err_signed', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_integers_err_signed_l', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_integers_err_signed_z', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_floats', 'lex', cmRun, [], [], [], '');
  DoAdd('lex_floats_err_exponent', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_floats_err_overflow', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_floats_err_suffix', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_strings', 'lex', cmRun, [], [], [], '');
  DoAdd('lex_strings_nul', 'lex', cmRun, [], [], [], '');
  DoAdd('lex_strings_err_unterminated', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_strings_err_raw', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_strings_err_delimiter', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_strings_err_escape', 'lex', cmCheck, [], [], [], '');
  // F65: built and run, so a second report of the same escape (clang's) fails
  DoAdd('lex_strings_err_unknown_escape', 'lex', cmRun, [], [], [], '');
  DoAdd('lex_strings_err_unknown_escape_char', 'lex', cmRun, [], [], [], '');
  // F66: a multi-char literal is PaskalCPP's warning only (it was clang's)
  DoAdd('lex_strings_err_multichar', 'lex', cmRun, [], [], [], '');
  DoAdd('lex_strings_err_char', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_strings_err_print_prefix', 'lex', cmBuild, [], [], [], '');
  DoAdd('lex_comments', 'lex', cmRun, [], [], [], '');
  DoAdd('lex_comments_err_unterminated', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_comments_err_nested', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_comments_err_escaped_end', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_splices', 'lex', cmRun, [], [], [], '');
  DoAdd('lex_splices_err_space', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_splices_err_space_comment', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_splices_err_cppstart', 'lex', cmCheck, [], [], [], '');
  DoAdd('lex_digraphs', 'lex', cmRun, [], [], [], '');
  DoAdd('lex_digraphs_err_hash', 'lex', cmCheck, [], [], [], '');
  // PLAN-COMPLIANCE F10 cpp_ (scripts\zb_cmpl\f4\gen_cpp.py)
  DoAdd('cpp_preprocessor', 'cpp', cmRun, [], [], [], '');
  DoAdd('cpp_preprocessor_err_hash', 'cpp', cmCheck, [], [], [], '');
  DoAdd('cpp_placement', 'cpp', cmRun, [], [], [], '');
  DoAdd('cpp_placement_err_target', 'cpp', cmCheck, [], [], [], '');
  DoAdd('cpp_placement_err_body', 'cpp', cmCheck, [], [], [], '');
  DoAdd('cpp_block', 'cpp', cmRun, [], [], [], '');
  DoAdd('cpp_block_err_target', 'cpp', cmCheck, [], [], [], '');
  DoAdd('cpp_block_err_header_body', 'cpp', cmCheck, [], [], [], '');
  DoAdd('cpp_block_err_no_end', 'cpp', cmCheck, [], [], [], '');
  DoAdd('cpp_expression', 'cpp', cmRun, [], [], [], '');
  DoAdd('cpp_expression_err_line_break', 'cpp', cmCheck, [], [], [], '');
  DoAdd('cpp_expression_err_prefix', 'cpp', cmCheck, [], [], [], '');
  DoAdd('cpp_declaration', 'cpp', cmRun, [], [], [], '');
  DoAdd('cpp_namespace', 'cpp', cmRun, [], [], [], '');
  DoAdd('cpp_keyword_names', 'cpp', cmRun, [], [], [], '');
  DoAdd('cpp_errors', 'cpp', cmBuild, [], [], [], '');
  // PLAN-COMPLIANCE F11 exe_ / dll_ (scripts\zb_cmpl\f4\gen_exe.py)
  DoAdd('exe_build_run', 'exe', cmRun, [], [], [], '');
  DoAdd('exe_args', 'exe', cmRun, [], [], [], 'one "two words" "a\"b" -o --lsp');
  DoAdd('exe_gui', 'exe', cmBuild, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('exe_stamps', 'exe', cmBuild, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dll_build_dll', 'dll', cmBuild, [], [], ['', ''], '');
  DoAdd('dll_build', 'dll', cmRun, ['dll_build_dll'], [], [], '');
  DoAdd('exe_build_errors', 'exe', cmBuild, [], [], [], '');
  DoAdd('exe_runtime_faults', 'exe', cmRun, [], [], [], '');
  DoAdd('exe_debug_heap', 'exe', cmRun, [], [], [], '');
  DoAdd('exe_debug_heap_release', 'exe', cmRun, [], [], [], '');
  DoAdd('exe_release_guards', 'exe', cmRun, [], [], [], '');
  DoAdd('exe_release_guards_safe', 'exe', cmRun, [], [], [], '');
  DoAdd('dir_outputpath', 'dir', cmRun, [], [], ['', ''], '');
  DoAdd('dir_outputpath_err_twice', 'dir', cmCheck, [], [], [], '');
  DoAdd('dir_outputpath_err_shape', 'dir', cmCheck, [], [], [], '');
  // F11, the two tester shapes (scripts\zb_cmpl\f4\gen_cli.py): a stdin file, pcpp itself
  DoAdd('exe_stdin', 'exe', cmRun, [], [], [], '');
  DoSetStdin('exe_stdin_input.txt');
  DoAdd('exe_cli_options', 'exe', cmCli, [], [], [], '-h');
  DoAdd('exe_cli_errors', 'exe', cmCli, [], [], [], '--bogus');
  DoAdd('exe_cli_errors_value', 'exe', cmCli, [], [], [], '-o');
  DoAdd('exe_cli_errors_args', 'exe', cmCli, [], [], [], 'res\tests\exe_build_run.pcpp -- x');
  DoAdd('exe_cli_errors_source', 'exe', cmCli, [], [], [], 'res\tests\exe_cli_missing.pcpp');
  // PLAN-COMPLIANCE F4 type_overlay: scripts\zb_cmpl\f4\gen_overlay.py
  DoAdd('type_overlay', 'type', cmRun, [], [], [], '');
  DoAdd('type_overlay_err_method', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_hidden', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_embed', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_property', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_init', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_operator', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_anon_overlay', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_nested_record', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_duplicate', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_object', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_own', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_packed_string', 'type', cmCheck, [], [], [], '');
  // F34: an overlay member is trivial data (SM0313); a C/C++ one is judged in
  // the emitted C++ (cmBuild)
  DoAdd('type_overlay_err_string', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_dynarray', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_record_string', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_anon_wstring', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_record_overlay', 'type', cmCheck, [], [], [], '');
  DoAdd('type_overlay_err_cpp_ctor', 'type', cmBuild, [], [], [], '');
  DoAdd('type_overlay_err_cpp_dtor', 'type', cmBuild, [], [], [], '');
  // F47: clang's record text, owned at the overlay's name
  DoAdd('type_overlay_err_too_large', 'type', cmBuild, [], [], [], '');
  // PLAN-COMPLIANCE F4 type_choices: scripts\zb_cmpl\f4\gen_choices.py
  DoAdd('type_choices', 'type', cmRun, [], [], [], '');
  DoAdd('type_choices_err_empty', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_duplicate', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_not_constant', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_float', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_no_value', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_arrow', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_bare', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_bare_unit', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_int_to_choices', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_choices_to_int', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_bit_ordinals', 'type', cmCheck, [], [], [], '');
  // F38 / F39: a constant into a choices bitfield; no arithmetic on a choice
  DoAdd('type_choices_err_bit_store', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_compound', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_increment', 'type', cmCheck, [], [], [], '');
  // F40 - F42: no binary arithmetic; every value numbered by PaskalCPP
  DoAdd('type_choices_err_arithmetic', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_cpp_value', 'type', cmCheck, [], [], [], '');
  DoAdd('type_choices_err_past_max', 'type', cmCheck, [], [], [], '');
  // PLAN-COMPLIANCE F4 type_array: scripts\zb_cmpl\f4\gen_array.py
  DoAdd('type_array', 'type', cmRun, [], [], [], '');
  DoAdd('type_array_err_bounds_family', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_bounds_float', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_bounds_bool', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_bound_order', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_bound_variable', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_single_bound', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_no_of', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_index_float', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_index_char', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_index_choices', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_not_indexable', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_dynamic_to_static', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_length', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_element', 'type', cmCheck, [], [], [], '');
  // F45 / F46: a constant index inside the bounds; a bound spelled as written
  DoAdd('type_array_err_bound_order_char', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_index_outside', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_index_below', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_index_outside_char', 'type', cmCheck, [], [], [], '');
  // F47: a type too large to exist (SEM's count; the runtime's Array check)
  DoAdd('type_array_err_too_large', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_too_large_range', 'type', cmCheck, [], [], [], '');
  DoAdd('type_array_err_too_large_element', 'type', cmBuild, [], [], [], '');
  DoAdd('type_array_err_too_large_param', 'type', cmBuild, [], [], [], '');
  DoAdd('type_array_err_too_large_deref', 'type', cmBuild, [], [], [], '');
  // PLAN-COMPLIANCE F4 type_pointer: scripts\zb_cmpl\f4\gen_pointer.py
  DoAdd('type_pointer', 'type', cmRun, [], [], [], '');
  DoAdd('type_pointer_err_no_target', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_deref_value', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_arrow_value', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_arrow_untyped', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_dot_pointer', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_const_write', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_const_drop', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_target', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_untyped', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_integer', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_to_integer', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_cast_no_to', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_cast_no_paren', 'type', cmCheck, [], [], [], '');
  // F48: a pointer cast's own rule (SEM DoPointerCastTakes, SM0265)
  DoAdd('type_pointer_err_cast_const', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_cast_float', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_cast_narrow', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_cast_nil', 'type', cmCheck, [], [], [], '');
  // F49: an untyped ptr points at no type (SM0253)
  DoAdd('type_pointer_err_untyped_deref', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_untyped_index', 'type', cmCheck, [], [], [], '');
  DoAdd('type_pointer_err_qualified_star', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object', 'type', cmRun, [], [], [], '');
  DoAdd('type_object_words', 'type', cmRun, [], [], [], '');
  DoAdd('type_object_err_self_routine', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_parent_main', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_parent_none', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_parent_value', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_parent_address', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_parent_arrow', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_parent_record', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_parent_choices', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_parent_int', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_field_field', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_field_method', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_method_field', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_method_grand_field', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_hidden_overload', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_method_dup', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_method_field_dup', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_bare_field', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_bare_method', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_hidden_outside', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_hidden_through', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_hidden_record', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_err_const_method', 'type', cmCheck, [], [], [], '');
  // PLAN-OBJECT O3 (D7): dispatch
  DoAdd('type_object_virtual', 'type', cmRun, [], [], [], '');
  DoAdd('type_object_virtual_err_needs_override', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_virtual_err_overrides_nothing', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_virtual_err_override_signature', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_virtual_err_override_final', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_virtual_err_final_not_virtual', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_virtual_err_abstract_not_virtual', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_virtual_err_abstract_value', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_virtual_err_final_parent', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_virtual_err_abstract_call', 'type', cmCheck, [], [], [], '');
  // PLAN-OBJECT O4 (D3): init / done
  DoAdd('type_object_init', 'type', cmRun, [], [], [], '');
  DoAdd('type_object_init_err_two_done', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_init_by_name', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_done_by_name', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_parent_init_late', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_field_init_order', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_lead_arg_local', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_parent_needs_init', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_virtual_call', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_no_default', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_args_not_object', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_no_init_takes', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_ambiguous', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_same_params', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_hidden_init', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_init_result', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_init_err_init_in_record', 'type', cmCheck, [], [], [], '');
  // PLAN-OBJECT O5: copy, move, slicing, a record holds no object
  DoAdd('type_object_copy', 'type', cmRun, [], [], [], '');
  DoAdd('type_object_copy_err_assign', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_argument', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_array', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_parent', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_return_var', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_shape', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_two_copy', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_copy_parent', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_parent_init', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_by_name', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_result', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_slice', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_slice_var', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_slice_deref', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_slice_self', 'type', cmCheck, [], [], [], '');
  // D6 by the dynamic type (2026-10-14, found in O12): a copy of what may be a descendant
  DoAdd('type_object_copy_err_slice_copy_param', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_slice_copy_deref', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_slice_copy_as', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_record', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_copy_err_overlay', 'type', cmCheck, [], [], [], '');
  // PLAN-OBJECT O6: own / ref / weak, construction, alive / lock, the leak sites
  DoAdd('type_object_own', 'type', cmRun, [], [], [], '');
  DoAdd('type_object_own_err_target', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_own_err_record', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_own_err_copy', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_own_err_to_ref', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_own_err_upcast', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_own_err_weak_new', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_own_err_weak_member', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_own_err_weak_to_ref', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_own_err_create', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_own_err_destroy', 'type', cmCheck, [], [], [], '');
  // PLAN-OBJECT O7: interfaces, implements, an inherited implementation
  DoAdd('type_object_iface', 'type', cmRun, [], [], [], '');
  DoAdd('type_object_iface_err_field', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_iface_err_body', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_iface_err_word', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_iface_err_value', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_iface_err_parent', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_iface_err_not_interface', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_iface_err_twice', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_iface_err_missing', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_iface_err_plain', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_iface_err_signature', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_iface_err_hidden', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_iface_err_repeat', 'type', cmCheck, [], [], [], '');
  // PLAN-OBJECT O8: embed (promotion by depth, an interface through an embed)
  DoAdd('type_object_embed', 'type', cmRun, [], [], [], '');
  DoAdd('type_object_embed_err_type', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_embed_err_record', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_embed_err_shared', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_embed_err_shared_iface', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_embed_err_hidden', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_embed_err_hidden_embed', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_embed_err_bare', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_embed_err_iface_hidden', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_embed_err_iface_signature', 'type', cmCheck, [], [], [], '');
  // PLAN-OBJECT O9: properties (bound and inline accessors, hidden write, not storage)
  DoAdd('type_object_property', 'type', cmRun, [], [], [], '');
  DoAdd('type_object_property_err_no_read', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_write_shape', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_no_field', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_field_type', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_read_change', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_read_call', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_read_increment', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_own_read', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_own_write', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_no_write', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_hidden_write', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_const', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_value', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_address', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_increment', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_var_arg', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_bare', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_err_record', 'type', cmCheck, [], [], [], '');
  // PLAN-OBJECT O10: dispatched / interface / indexed / default / promoted properties
  DoAdd('type_object_property_virtual', 'type', cmRun, [], [], [], '');
  DoAdd('type_object_property_virtual_err_needs_override', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_overrides_nothing', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_override_final', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_override_type', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_override_write', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_final_plain', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_abstract_plain', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_abstract_value', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_iface_missing', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_iface_plain', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_iface_shape', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_iface_hidden', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_iface_body', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_needs_index', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_default_plain', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_default_twice', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_index_binding', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_index_shape', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_property_virtual_err_parent_name', 'type', cmCheck, [], [], [], '');
  // PLAN-OBJECT O11 (D13): operators (scripts\zb_obj\o11\gen_o11.py)
  DoAdd('type_object_operator', 'type', cmRun, [], [], [], '');
  DoAdd('type_object_operator_err_symbol', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_variadic', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_overlay', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_arity', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_own', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_bool', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_twice', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_var', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_pair', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_self', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_none', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_ambiguous', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_anonymous', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_compare', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_compare_array', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_operator_err_compare_less', 'type', cmCheck, [], [], [], '');
  // PLAN-OBJECT O12 (D15): is / as (scripts\zb_obj\o12\gen_o12.py)
  DoAdd('type_object_is', 'type', cmRun, [], [], [], '');
  DoAdd('type_object_is_err_operand', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_is_err_target', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_is_err_never', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_is_err_exact', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_is_err_weak', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_is_err_chain', 'type', cmCheck, [], [], [], '');
  // PLAN-OBJECT O13 (D14, F-A5a): the C++ boundary (scripts\zb_obj\o13\gen_o13.py)
  DoAdd('type_object_cpp', 'type', cmRun, [], [], [], '');
  DoAdd('type_object_cpp_err_method_value', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_cpp_err_method_arg', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_cpp_err_method_address', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_cpp_err_method_parent', 'type', cmCheck, [], [], [], '');
  // O13b (3): const methods
  DoAdd('type_object_cpp_err_const_change', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_cpp_err_const_call', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_cpp_err_const_override', 'type', cmCheck, [], [], [], '');
  DoAdd('type_object_cpp_err_const_implements', 'type', cmCheck, [], [], [], '');
  // O13b: a C++ parent's virtual is clang's to see: these are built
  DoAdd('type_object_cpp_err_missing_override', 'type', cmBuild, [], [], [], '');
  DoAdd('type_object_cpp_err_virtual_override', 'type', cmBuild, [], [], [], '');
  DoAdd('type_object_cpp_err_override_const', 'type', cmBuild, [], [], [], '');
  DoAdd('type_object_cpp_err_override_nothing', 'type', cmBuild, [], [], [], '');
  DoAdd('type_object_cpp_err_override_plain', 'type', cmBuild, [], [], [], '');
  DoAdd('type_object_cpp_err_poly_is', 'type', cmBuild, [], [], [], '');
  DoAdd('type_object_cpp_err_poly_slice', 'type', cmBuild, [], [], [], '');
  DoAdd('type_object_cpp_err_poly_held', 'type', cmBuild, [], [], [], '');
  DoAdd('type_object_cpp_err_poly_assign', 'type', cmBuild, [], [], [], '');
  DoAdd('type_object_cpp_err_poly_own', 'type', cmBuild, [], [], [], '');
  DoAdd('lib_plain', 'lib', cmBuild, [], [],
    ['', ''], '');
  DoAdd('lib_plain_host', 'lib', cmRun, ['lib_plain'], [],
    ['', ''], '');
  DoAdd('lib_plain_host_err_nolink', 'lib', cmBuild, ['lib_plain'], [], [], '');
  DoAdd('lib_runtime', 'lib', cmBuild, [], [],
    ['', ''], '');
  DoAdd('lib_runtime_host', 'lib', cmRun, ['lib_runtime'], [],
    ['', ''], '');
  // lsp_: a person checks them in the editor (lsp_unit is the unit the other
  // lsp_ files import: not a main module)
  DoAdd('lsp_call_hierarchy', 'lsp', cmBuild, [], [], [], '');
  DoAdd('lsp_colouring', 'lsp', cmBuild, [], [], [], '');
  DoAdd('lsp_completion', 'lsp', cmBuild, [], [], [], '');
  DoAdd('lsp_definition', 'lsp', cmBuild, [], [], [], '');
  DoAdd('lsp_diagnostics', 'lsp', cmBuild, [], [], [], '');
  DoAdd('lsp_diagnostics_syntax', 'lsp', cmBuild, [], [], [], '');
  DoAdd('lsp_doc_comments', 'lsp', cmBuild, [], [], [], '');
  DoAdd('lsp_document_symbols', 'lsp', cmBuild, [], [], [], '');
  DoAdd('lsp_formatting', 'lsp', cmBuild, [], [], [], '');
  DoAdd('lsp_hover', 'lsp', cmBuild, [], [], [], '');
  DoAdd('lsp_inlay_hints', 'lsp', cmBuild, [], [], [], '');
  DoAdd('lsp_workspace_symbols', 'lsp', cmBuild, [], [], [], '');
  // dbg_: a person checks them in the debugger, x86_64-windows-gnu only. The
  // host loads dbg_dll by LoadLibrary at run time: its build needs no dep
  DoAdd('dbg_dll', 'dbg', cmBuild, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dbg_dll_host', 'dbg', cmBuild, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dbg_input', 'dbg', cmBuild, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dbg_pause', 'dbg', cmBuild, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dbg_stepping', 'dbg', cmBuild, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dbg_stops', 'dbg', cmBuild, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dbg_variables', 'dbg', cmBuild, [], [PC_CMPL_TARGET_WINDOWS], [], '');
  DoAdd('dbg_watch', 'dbg', cmBuild, [], [PC_CMPL_TARGET_WINDOWS], [], '');

  // std_: the std library units (res\libs\std), one file per unit
  DoAdd('std_sysutils', 'std', cmRun, [], [], [], '');
  DoAdd('std_sysutils_format', 'std', cmRun, [], [], [], '');
  DoAdd('std_sysutils_format_err_count', 'std', cmBuild, [], [], [], '');
  DoAdd('std_sysutils_format_err_const_count', 'std', cmBuild, [], [], [], '');
  DoAdd('std_sysutils_format_err_not_literal', 'std', cmBuild, [], [], [], '');
  DoAdd('std_sysutils_format_err_record', 'std', cmBuild, [], [], [], '');
  DoAdd('std_sysutils_format_err_cpp_value', 'std', cmBuild, [], [], [], '');
  DoAdd('std_sysutils_format_err_cpp_values', 'std', cmBuild, [], [], [], '');

  // hello: the first end-to-end program (an exe built at @optimize small)
  DoAdd('hello', 'exe', cmRun, [], [], [], '');

  for LI := 0 to FEntries.Count - 1 do
    DoRegister(LI);
end;

destructor TPCComplianceTests.Destroy();
begin
  FEntries.Free();

  inherited;
end;

procedure TPCComplianceTests.Run();
begin
  inherited;
end;

class function TPCComplianceTests.InRunAll(): Boolean;
begin
  // D6 (the user 2026-10-11): every res\tests file on both targets is a
  // plan's-end run, by name; never part of -all
  Result := False;
end;

procedure TPCComplianceTests.DoAdd(const AStem: string; const ACategory: string;
  const AMode: TPCComplianceMode; const ADeps: array of string;
  const ATargets: array of string; const AOutputDirs: array of string;
  const AArgs: string);
var
  LEntry: TPCComplianceEntry;
  LI: Integer;
begin
  LEntry := Default(TPCComplianceEntry);
  LEntry.Stem := AStem;
  LEntry.Category := ACategory;
  LEntry.Mode := AMode;
  SetLength(LEntry.Deps, Length(ADeps));
  for LI := 0 to High(ADeps) do
    LEntry.Deps[LI] := ADeps[LI];
  SetLength(LEntry.Targets, Length(ATargets));
  for LI := 0 to High(ATargets) do
    LEntry.Targets[LI] := ATargets[LI];
  SetLength(LEntry.OutputDirs, Length(AOutputDirs));
  for LI := 0 to High(AOutputDirs) do
    LEntry.OutputDirs[LI] := AOutputDirs[LI];
  LEntry.Args := AArgs;
  FEntries.Add(LEntry);
end;

procedure TPCComplianceTests.DoSetStdin(const AFileName: string);
var
  LEntry: TPCComplianceEntry;
begin
  // A record in a list: taken, changed, put back
  LEntry := FEntries[FEntries.Count - 1];
  LEntry.Stdin := AFileName;
  FEntries[FEntries.Count - 1] := LEntry;
end;

procedure TPCComplianceTests.DoRegister(const AIndex: Integer);
begin
  // A routine of its own: the closure captures this call's AIndex, never a
  // loop variable (anonymous methods capture variables, not values)
  RegisterTest(FEntries[AIndex].Stem,
    procedure()
    begin
      DoRunEntry(AIndex);
    end);
end;

function TPCComplianceTests.DoFind(const AStem: string; out AEntry: TPCComplianceEntry): Boolean;
var
  LEntry: TPCComplianceEntry;
begin
  for LEntry in FEntries do
  begin
    if LEntry.Stem = AStem then
    begin
      AEntry := LEntry;
      Exit(True);
    end;
  end;
  AEntry := Default(TPCComplianceEntry);
  Result := False;
end;

function TPCComplianceTests.DoRunsOn(const AEntry: TPCComplianceEntry; const ATarget: string): Boolean;
var
  LTarget: string;
begin
  if Length(AEntry.Targets) = 0 then
    Exit(True);
  for LTarget in AEntry.Targets do
  begin
    if LTarget = ATarget then
      Exit(True);
  end;
  Result := False;
end;

function TPCComplianceTests.DoOutputDir(const AEntry: TPCComplianceEntry; const ATarget: string): string;
var
  LI: Integer;
begin
  // D9: the folder of the file's own command when registered, else a temp one
  if Length(AEntry.OutputDirs) = Length(PC_CMPL_TARGETS) then
  begin
    for LI := Low(PC_CMPL_TARGETS) to High(PC_CMPL_TARGETS) do
    begin
      // '' = no -o: the file's own @outputpath decides, as from the CLI
      // and the editor (else 'output' under repo\bin, the CLI's default)
      if (PC_CMPL_TARGETS[LI] = ATarget) and (AEntry.OutputDirs[LI] = '') then
        Exit('');
      if PC_CMPL_TARGETS[LI] = ATarget then
        Exit(TUtils.ResolvePath(AEntry.OutputDirs[LI], TPath.GetDirectoryName(ParamStr(0))));
    end;
  end;
  Result := TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetTempPath(), 'pcpp-cmpl'),
    AEntry.Stem), ATarget);
end;

function TPCComplianceTests.DoBuildDep(const AStem: string; const ATarget: string): Boolean;
var
  LEntry: TPCComplianceEntry;
  LCompiler: TPCCompiler;
begin
  Result := False;
  if not DoFind(AStem, LEntry) then
  begin
    Check(False, 'dependency %s is registered', [AStem]);
    Exit;
  end;

  // Built where its own command puts it (D9): the dependent names that folder
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetMaxErrors(PC_CMPL_MAX_ERRORS);
    LCompiler.SetKeyDefault(PC_CMP_KEY_TARGET, ATarget);
    Result := LCompiler.Prepare(TPath.Combine(TPCCompliance.TestsDir(), AStem + PC_CMPL_SOURCE_EXT),
      DoOutputDir(LEntry, ATarget)) and LCompiler.Build(False);
    Check(Result, 'dependency %s builds for %s (%s)', [AStem, ATarget, DoReports(LCompiler.GetErrors())]);
  finally
    LCompiler.Free();
  end;
end;

procedure TPCComplianceTests.DoCheckReports(const AStem: string; const ATarget: string;
  const AErrors: TErrors; const AMarkers: TList<TPCComplianceMarker>);
var
  LError: TError;
  LI: Integer;
  LFound: Integer;
  LMarker: TPCComplianceMarker;
  LUnexpected: string;
  LMissing: string;
begin
  // Each report takes the first unmatched marker it matches; a report with no
  // marker and a marker with no report each fail, listed
  LUnexpected := '';
  for LError in AErrors.GetItems() do
  begin
    LFound := -1;
    for LI := 0 to AMarkers.Count - 1 do
    begin
      if (not AMarkers[LI].Hit) and DoMatches(AMarkers[LI], AErrors, LError) then
      begin
        LFound := LI;
        Break;
      end;
    end;
    if LFound < 0 then
      LUnexpected := LUnexpected + sLineBreak + '    ' + DoReportText(AErrors, LError)
    else
    begin
      LMarker := AMarkers[LFound];
      LMarker.Hit := True;
      AMarkers[LFound] := LMarker;
    end;
  end;

  LMissing := '';
  for LMarker in AMarkers do
  begin
    if not LMarker.Hit then
      LMissing := LMissing + sLineBreak + Format('    %s(%d) %s', [LMarker.Filename, LMarker.Line,
        LMarker.Code]);
  end;

  Check(LUnexpected = '', '%s on %s: every report has its marker%s', [AStem, ATarget, LUnexpected]);
  Check(LMissing = '', '%s on %s: every marker is reported%s', [AStem, ATarget, LMissing]);
end;

procedure TPCComplianceTests.DoCheckRun(const AEntry: TPCComplianceEntry; const ATarget: string;
  const AArtifact: string; const ASpec: TPCComplianceSpec);
var
  LDir: string;
  LExitCode: DWORD;
  LRaised: string;
  LOutput: TStringBuilder;
  LGot: string;
  LWant: string;
  LStdinFile: string;
  LStdinHandle: THandle;
  LHost: TPtyStreamHost;
begin
  // As pcpp -r: in the program's own folder, the registration's arguments;
  // over pipes, stdout and stderr in written order (UTestCase.Run's run).
  // A registered stdin file (in res\tests, the one a person redirects with <)
  // is the program's stdin (a TPtyStreamHost: as 'prog < file', it ends where
  // the file ends)
  LDir := TPath.GetDirectoryName(AArtifact);
  LExitCode := PC_CMPL_NO_EXIT;
  LRaised := '';
  LStdinFile := '';
  LStdinHandle := INVALID_HANDLE_VALUE;
  LHost := nil;
  LOutput := TStringBuilder.Create();
  try
    try
      if AEntry.Stdin <> '' then
      begin
        LStdinFile := TPath.Combine(TPCCompliance.TestsDir(), AEntry.Stdin);
        LStdinHandle := CreateFile(PChar(LStdinFile), GENERIC_READ, FILE_SHARE_READ, nil,
          OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
        if LStdinHandle = INVALID_HANDLE_VALUE then
          RaiseLastOSError();
        LHost := TPtyStreamHost.Create();
        LHost.Init(LStdinHandle);
      end;
      if ATarget = PC_CMPL_TARGET_LINUX then
        TUtils.RunElf(AArtifact, AEntry.Args, LDir, LExitCode, nil,
          procedure(const ALine: string; const AData: Pointer)
          begin
            LOutput.Append(ALine).Append(#10);
          end, True, LHost)
      else
        TUtils.RunPE(AArtifact, AEntry.Args, LDir, LExitCode, nil,
          procedure(const ALine: string; const AData: Pointer)
          begin
            LOutput.Append(ALine).Append(#10);
          end, True, LHost);
    except
      on E: Exception do
        LRaised := E.Message;
    end;
    LGot := TPCCompliance.NormalizeOutput(LOutput.ToString());
  finally
    LOutput.Free();
    LHost.Free();
    if LStdinHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(LStdinHandle);
  end;

  // No EXPECT for this target = the program prints nothing
  if not ASpec.ExpectFor(ATarget, LWant) then
    LWant := '';
  // F8: a source path the program prints is spelled <DIR>/<file> in EXPECT
  LWant := LWant.Replace(PC_CMPL_DIR_TOKEN, TPCCompliance.TestsDir());
  Check(LRaised = '', '%s on %s: runs (%s)', [AEntry.Stem, ATarget, LRaised]);
  Check(Integer(LExitCode) = ASpec.ExitCode, '%s on %s: exit code %d (got %d)%s%s',
    [AEntry.Stem, ATarget, ASpec.ExitCode, Integer(LExitCode), sLineBreak, LGot]);
  Check(LGot = LWant, '%s on %s: output as EXPECT%s--- got%s%s%s--- want%s%s',
    [AEntry.Stem, ATarget, sLineBreak, sLineBreak, LGot, sLineBreak, sLineBreak, LWant]);
end;

procedure TPCComplianceTests.DoRunTarget(const AEntry: TPCComplianceEntry; const ATarget: string);
var
  LSource: string;
  LSpec: TPCComplianceSpec;
  LReason: string;
  LDep: string;
  LCompiler: TPCCompiler;
  LMarkers: TList<TPCComplianceMarker>;
  LFile: string;
  LOk: Boolean;
  LWantsError: Boolean;
  LMarker: TPCComplianceMarker;
begin
  LSource := TPath.Combine(TPCCompliance.TestsDir(), AEntry.Stem + PC_CMPL_SOURCE_EXT);
  if not TPCCompliance.ReadSpec(LSource, LSpec, LReason) then
  begin
    Check(False, '%s: header directives (%s)', [AEntry.Stem, LReason]);
    Exit;
  end;
  // D10: EXPECT / EXITCODE belong to a file that runs
  if (AEntry.Mode <> cmRun) and (LSpec.HasAnyExpect() or (LSpec.ExitCode <> 0)) then
  begin
    Check(False, '%s: EXPECT / EXITCODE on a file registered without a run', [AEntry.Stem]);
    Exit;
  end;

  for LDep in AEntry.Deps do
  begin
    if not DoBuildDep(LDep, ATarget) then
      Exit;
  end;

  LMarkers := TList<TPCComplianceMarker>.Create();
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetMaxErrors(PC_CMPL_MAX_ERRORS);
    // D8: a default, so the file's own @target still wins
    LCompiler.SetKeyDefault(PC_CMP_KEY_TARGET, ATarget);
    LOk := LCompiler.Prepare(LSource, DoOutputDir(AEntry, ATarget));
    if LOk and (AEntry.Mode <> cmCheck) then
      LOk := LCompiler.Build(False);

    // D7: the markers of exactly the files this build read
    for LFile in TPCCompliance.BuildFiles(LSource, LCompiler.GetMainModule()) do
    begin
      if not TPCCompliance.ReadMarkers(LFile, LMarkers, LReason) then
      begin
        Check(False, '%s on %s: markers (%s)', [AEntry.Stem, ATarget, LReason]);
        Exit;
      end;
    end;
    DoCheckReports(AEntry.Stem, ATarget, LCompiler.GetErrors(), LMarkers);

    // D11: the build succeeds exactly when no ERROR / FATAL marker exists
    LWantsError := False;
    for LMarker in LMarkers do
    begin
      if LMarker.Severity in [esError, esFatal] then
        LWantsError := True;
    end;
    Check(LOk = not LWantsError, '%s on %s: build %s as its markers say (%s)',
      [AEntry.Stem, ATarget, BoolToStr(LOk, True), DoReports(LCompiler.GetErrors())]);

    if (AEntry.Mode = cmRun) and LOk then
      DoCheckRun(AEntry, ATarget, LCompiler.GetArtifactPath(), LSpec);
  finally
    LCompiler.Free();
    LMarkers.Free();
  end;
end;

{ DoStripSgr }
// The CLI's colour codes (ESC '[' params 'm') are not text: removed
function DoStripSgr(const AText: string): string;
var
  LI: Integer;
  LJ: Integer;
  LOut: TStringBuilder;
begin
  LOut := TStringBuilder.Create();
  try
    LI := 1;
    while LI <= Length(AText) do
    begin
      if (AText[LI] = #27) and (LI < Length(AText)) and (AText[LI + 1] = '[') then
      begin
        LJ := LI + 2;
        while (LJ <= Length(AText)) and CharInSet(AText[LJ], ['0'..'9', ';']) do
          Inc(LJ);
        if (LJ <= Length(AText)) and (AText[LJ] = 'm') then
        begin
          LI := LJ + 1;
          Continue;
        end;
      end;
      LOut.Append(AText[LI]);
      Inc(LI);
    end;
    Result := LOut.ToString();
  finally
    LOut.Free();
  end;
end;

procedure TPCComplianceTests.DoRunCli(const AEntry: TPCComplianceEntry);
var
  LSource: string;
  LSpec: TPCComplianceSpec;
  LReason: string;
  LBin: string;
  LExitCode: DWORD;
  LRaised: string;
  LOutput: TStringBuilder;
  LGot: string;
  LWant: string;
begin
  // pcpp.exe beside testbed.exe, from repo\bin as a person runs it, over
  // pipes, once: the CLI's text is the same for every target. EXPECT spells
  // the version <VERSION> (the one line that changes per release) and a
  // res\tests path <DIR>
  LSource := TPath.Combine(TPCCompliance.TestsDir(), AEntry.Stem + PC_CMPL_SOURCE_EXT);
  if not TPCCompliance.ReadSpec(LSource, LSpec, LReason) then
  begin
    Check(False, '%s: header directives (%s)', [AEntry.Stem, LReason]);
    Exit;
  end;
  LBin := TPath.GetDirectoryName(ParamStr(0));
  LExitCode := PC_CMPL_NO_EXIT;
  LRaised := '';
  LOutput := TStringBuilder.Create();
  try
    try
      TUtils.RunPE(TPath.Combine(LBin, PC_CMPL_PCPP_EXE), AEntry.Args, LBin, LExitCode, nil,
        procedure(const ALine: string; const AData: Pointer)
        begin
          LOutput.Append(ALine).Append(#10);
        end, True);
    except
      on E: Exception do
        LRaised := E.Message;
    end;
    LGot := TPCCompliance.NormalizeOutput(DoStripSgr(LOutput.ToString()));
  finally
    LOutput.Free();
  end;

  if not LSpec.ExpectFor(PC_CMPL_TARGET_WINDOWS, LWant) then
    LWant := '';
  LWant := LWant.Replace(PC_CMPL_DIR_TOKEN, TPCCompliance.TestsDir()).Replace(PC_CMPL_VERSION_TOKEN,
    Format('%d.%d.%d', [PC_MAJOR_VERSION, PC_MINOR_VERSION, PC_PATCH_VERSION]));
  Check(LRaised = '', '%s: pcpp runs (%s)', [AEntry.Stem, LRaised]);
  Check(Integer(LExitCode) = LSpec.ExitCode, '%s: exit code %d (got %d)%s%s',
    [AEntry.Stem, LSpec.ExitCode, Integer(LExitCode), sLineBreak, LGot]);
  Check(LGot = LWant, '%s: output as EXPECT%s--- got%s%s%s--- want%s%s',
    [AEntry.Stem, sLineBreak, sLineBreak, LGot, sLineBreak, sLineBreak, LWant]);
end;

procedure TPCComplianceTests.DoRunEntry(const AIndex: Integer);
var
  LEntry: TPCComplianceEntry;
  LTarget: string;
begin
  LEntry := FEntries[AIndex];
  if LEntry.Mode = cmCli then
  begin
    DoRunCli(LEntry);
    Exit;
  end;
  if not (Length(LEntry.OutputDirs) in [0, Length(PC_CMPL_TARGETS)]) then
  begin
    Check(False, '%s: OutputDirs names none or one folder per official target', [LEntry.Stem]);
    Exit;
  end;
  // Both official targets; a target the file is not registered for is skipped
  for LTarget in PC_CMPL_TARGETS do
  begin
    if DoRunsOn(LEntry, LTarget) then
      DoRunTarget(LEntry, LTarget)
    else
      Section(Format('%s: not registered for %s (skipped)', [LEntry.Stem, LTarget]));
  end;
end;

end.
