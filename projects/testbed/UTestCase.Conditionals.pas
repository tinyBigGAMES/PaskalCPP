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
  UTestCase.Conditionals - Conditional filter and target triple atom tests

  TTestCase suite for TPCConditionalFilter (PaskalCPP.Conditionals) and
  TPCTargetTriple (PaskalCPP.Common). Fixtures are real files in
  tests\probe\cnd, lexed with TPCLexer and filtered (research\cppmix\filter.md).
  The cn1x_splice fixtures hold exact line-splice bytes, written by
  scripts\zb_c\gen_fixtures.py (never an editor).

  datamodel_witness runs the bundled zig (c++ -dM -E) for every PC_DATA_MODELS
  row and checks the row against clang's predefines (sem\datamodel.md Q3).
  align_witness compiles one static_assert per TPCAlignKind for every
  PC_ALIGN_MODELS row against the real runtime header (PLAN-PASKAL-ERRORS E2).

  Dependencies: StdApp.TestCase, StdApp.Base, StdApp.Utils, StdApp.Resources,
    PaskalCPP.Common, PaskalCPP.TokenStream, PaskalCPP.Lexer, PaskalCPP.Conditionals,
    PaskalCPP.ZigBuild.Targets
===============================================================================}

unit UTestCase.Conditionals;

interface

uses
  StdApp.TestCase;

type

  { TPCConditionalTests }
  TPCConditionalTests = class(TTestCase)
  private
    // One test per concern; Create registers each under its CLI name
    procedure DoTestBasic();
    procedure DoTestNested();
    procedure DoTestErrors();
    procedure DoTestSymbolSlot();
    procedure DoTestInactive();
    procedure DoTestTargetDefault();
    procedure DoTestTargetSet();
    procedure DoTestTargetErrors();
    procedure DoTestInvariant();
    procedure DoTestTriple();
    procedure DoTestDataModelWitness();
    procedure DoTestAlignWitness();
    procedure DoTestSizeWitness();
    procedure DoTestBuildUnit();
    procedure DoTestSpliceNames();
    procedure DoTestSpliceErrors();
    procedure DoTestSpliceTarget();
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
  StdApp.Resources,
  System.TypInfo,
  PaskalCPP.Common,
  PaskalCPP.TokenStream,
  PaskalCPP.Lexer,
  PaskalCPP.Conditionals,
  PaskalCPP.ZigBuild.Targets;

type

  { TPCCndCase }
  // One fixture that must report exactly one error, with Code
  TPCCndCase = record
    FileName: string;
    Code: string;
  end;

const
  { TEST_CND_TARGET_ERRORS }
  TEST_CND_TARGET_ERRORS: array[0..8] of TPCCndCase = (
    (FileName: 'cn08a_noheader.pcpp'; Code: PC_ERR_CND_005),
    (FileName: 'cn08b_branch.pcpp';   Code: PC_ERR_CND_006),
    (FileName: 'cn08c_late.pcpp';     Code: PC_ERR_CND_007),
    (FileName: 'cn08d_body.pcpp';     Code: PC_ERR_CND_005),
    (FileName: 'cn08e_dup.pcpp';      Code: PC_ERR_CND_008),
    (FileName: 'cn08f_ident.pcpp';    Code: PC_ERR_CND_009),
    (FileName: 'cn08g_raw.pcpp';      Code: PC_ERR_CND_009),
    (FileName: 'cn08h_shape.pcpp';    Code: PC_ERR_CND_010),
    (FileName: 'cn08i_arch.pcpp';     Code: PC_ERR_CND_011)
  );

  { TEST_CND_FIXTURES }
  // Every fixture, for the output invariant
  TEST_CND_FIXTURES: array[0..19] of string = (
    'cn01_basic.pcpp', 'cn02_nested.pcpp', 'cn03_errors.pcpp', 'cn04_inactive.pcpp',
    'cn05_target_default.pcpp', 'cn06_target_linux.pcpp', 'cn07_target_3part.pcpp',
    'cn08a_noheader.pcpp', 'cn08b_branch.pcpp', 'cn08c_late.pcpp', 'cn08d_body.pcpp',
    'cn08e_dup.pcpp', 'cn08f_ident.pcpp', 'cn08g_raw.pcpp', 'cn08h_shape.pcpp',
    'cn08i_arch.pcpp', 'cn09_unit.pcpp', 'cn10_splice.pcpp', 'cn11_splice_errors.pcpp',
    'cn12_splice_target.pcpp'
  );

function DoCndDir(): string;
begin
  // The exe sits two levels below the project root (repo\bin)
  Result := TPath.GetFullPath(TPath.Combine(
    TPath.GetDirectoryName(ParamStr(0)), '..\..\tests\probe\cnd'));
end;

function DoPredefinedValue(const AOutput: string; const AName: string;
  out AValue: string): Boolean;
var
  LLine: string;
  LPrefix: string;
  LTrimmed: string;
begin
  // The value of '#define AName <value>' in clang's -dM -E output; False when absent
  Result := False;
  AValue := '';
  LPrefix := '#define ' + AName + ' ';
  for LLine in AOutput.Split([#10]) do
  begin
    LTrimmed := LLine.Trim();
    if LTrimmed.StartsWith(LPrefix) then
    begin
      AValue := LTrimmed.Substring(Length(LPrefix)).Trim();
      Exit(True);
    end;
  end;
end;

function DoBitsMatch(const AOutput: string; const AName: string; const ABits: Integer): Boolean;
var
  LValue: string;
  LBytes: Integer;
begin
  // clang's __SIZEOF_<X>__ is in bytes; the row holds bits
  Result := DoPredefinedValue(AOutput, AName, LValue) and TryStrToInt(LValue, LBytes) and
    (LBytes * 8 = ABits);
end;

procedure DoFilterFileWith(const AName: string; const AMainTarget: TPCTargetTriple;
  const AOverrideTarget: TPCTargetTriple; const AErrors: TErrors;
  const AFilter: TPCConditionalFilter; const AOutput: TPCTokenStream);
var
  LLexer: TPCLexer;
  LInput: TPCTokenStream;
begin
  // Lex a fixture and filter it into AOutput with the build's override
  // (CLI -t; empty = none); AFilter keeps its defines and Target()
  LLexer := TPCLexer.Create();
  LInput := TPCTokenStream.Create();
  try
    LLexer.SetErrors(AErrors);
    LLexer.TokenizeFile(TPath.Combine(DoCndDir(), AName), LInput);
    AFilter.SetErrors(AErrors);
    AFilter.Filter(LInput, AOutput, AMainTarget, AOverrideTarget, Default(TPCTargetTriple));
  finally
    LInput.Free();
    LLexer.Free();
  end;
end;

procedure DoFilterFile(const AName: string; const AMainTarget: TPCTargetTriple;
  const AErrors: TErrors; const AFilter: TPCConditionalFilter; const AOutput: TPCTokenStream);
begin
  // No override
  DoFilterFileWith(AName, AMainTarget, Default(TPCTargetTriple), AErrors, AFilter, AOutput);
end;

function DoCountCode(const AErrors: TErrors; const ACode: string): Integer;
var
  LError: TError;
begin
  Result := 0;
  for LError in AErrors.GetItems() do
  begin
    if LError.Code = ACode then
      Inc(Result);
  end;
end;

function DoCodeLines(const AErrors: TErrors; const ACode: string): string;
var
  LError: TError;
begin
  // Start lines of every ACode item, in report order: '10,11'
  Result := '';
  for LError in AErrors.GetItems() do
  begin
    if LError.Code = ACode then
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + UIntToStr(LError.Range.StartLine);
    end;
  end;
end;

function DoTexts(const AStream: TPCTokenStream; const AExpected: array of string): Boolean;
var
  LI: Integer;
begin
  // Every token but the final EOF, in order
  Result := AStream.Count() - 1 = Length(AExpected);
  if not Result then
    Exit;
  for LI := 0 to High(AExpected) do
  begin
    if AStream.TokenAt(LI).Text <> AExpected[LI] then
      Exit(False);
  end;
end;

function DoIsFaithful(const AInput: TPCTokenStream; const AOutput: TPCTokenStream): Boolean;
var
  LI: Integer;
  LJ: Integer;
  LEofCount: Integer;
  LOut: TPCToken;
  LIn: TPCToken;
begin
  // Every output token but the EOF is an input token, unchanged, in input
  // order; exactly one EOF, last; the output's file and SourceSlice work
  Result := False;
  if AOutput.Count() = 0 then
    Exit;
  if AOutput.TokenAt(AOutput.Count() - 1).Kind <> tkEOF then
    Exit;
  if AOutput.SourceFilename() <> AInput.SourceFilename() then
    Exit;

  LEofCount := 0;
  LJ := 0;
  for LI := 0 to AOutput.Count() - 1 do
  begin
    LOut := AOutput.TokenAt(LI);
    if LOut.Kind = tkEOF then
    begin
      Inc(LEofCount);
      Continue;
    end;

    // Walk the input forward to the same token
    while (LJ < AInput.Count()) and
      (AInput.TokenAt(LJ).Range.StartByteOffset <> LOut.Range.StartByteOffset) do
      Inc(LJ);
    if LJ >= AInput.Count() then
      Exit;

    LIn := AInput.TokenAt(LJ);
    if (LIn.Kind <> LOut.Kind) or (LIn.Text <> LOut.Text) or
      (LIn.TriviaStart <> LOut.TriviaStart) or
      (LIn.Range.EndByteOffset <> LOut.Range.EndByteOffset) then
      Exit;
    if AOutput.SourceSlice(LOut.Range.StartByteOffset, LOut.Range.EndByteOffset) <> LOut.Text then
      Exit;
    Inc(LJ);
  end;

  Result := LEofCount = 1;
end;

{ TPCConditionalTests }

constructor TPCConditionalTests.Create();
begin
  inherited;

  Title := 'Conditionals';
  RegisterTest('basic', DoTestBasic);
  RegisterTest('nested', DoTestNested);
  RegisterTest('errors', DoTestErrors);
  RegisterTest('symbol_slot', DoTestSymbolSlot);
  RegisterTest('inactive', DoTestInactive);
  RegisterTest('target_default', DoTestTargetDefault);
  RegisterTest('target_set', DoTestTargetSet);
  RegisterTest('target_errors', DoTestTargetErrors);
  RegisterTest('invariant', DoTestInvariant);
  RegisterTest('triple', DoTestTriple);
  RegisterTest('datamodel_witness', DoTestDataModelWitness);
  RegisterTest('align_witness', DoTestAlignWitness);
  RegisterTest('size_witness', DoTestSizeWitness);
  RegisterTest('build_unit', DoTestBuildUnit);
  RegisterTest('splice_names', DoTestSpliceNames);
  RegisterTest('splice_errors', DoTestSpliceErrors);
  RegisterTest('splice_target', DoTestSpliceTarget);
end;

procedure TPCConditionalTests.Run();
begin
  inherited;
end;

procedure TPCConditionalTests.DoTestBasic();
var
  LErrors: TErrors;
  LFilter: TPCConditionalFilter;
  LOutput: TPCTokenStream;
begin
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn01_basic.pcpp', Default(TPCTargetTriple), LErrors, LFilter, LOutput);
    Check(LErrors.Count() = 0, 'basic: no errors');
    Check(DoTexts(LOutput, ['module', 'exe', 'cn01', ';', 'a1', 'b2', 'c2', 'end', '.']),
      'basic: ifdef / ifndef / else, first true elseif only');
    Check(LFilter.IsDefined('A') and LFilter.IsDefined('PASKALCPP') and
      LFilter.IsDefined('BUILD_EXE'), 'basic: @define and the predefined defines');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;
end;

procedure TPCConditionalTests.DoTestNested();
var
  LErrors: TErrors;
  LFilter: TPCConditionalFilter;
  LOutput: TPCTokenStream;
begin
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn02_nested.pcpp', Default(TPCTargetTriple), LErrors, LFilter, LOutput);
    Check((LErrors.Count() = 0) and
      DoTexts(LOutput, ['module', 'lib', 'cn02', ';', 'y1', 'y2', 'end', '.']),
      'nested: an inactive parent keeps a defined inner branch inactive');
    Check(LFilter.IsDefined('BUILD_LIB') and (not LFilter.IsDefined('BUILD_EXE')) and
      (not LFilter.IsDefined('BUILD_DLL')), 'nested: BUILD_LIB from the lib header only');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;
end;

procedure TPCConditionalTests.DoTestBuildUnit();
var
  LErrors: TErrors;
  LFilter: TPCConditionalFilter;
  LOutput: TPCTokenStream;
begin
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn09_unit.pcpp', Default(TPCTargetTriple), LErrors, LFilter, LOutput);
    Check((LErrors.Count() = 0) and
      DoTexts(LOutput, ['module', 'unit', 'cn09', ';', 'u1', 'end', '.']),
      'build_unit: the unit header defines BUILD_UNIT');
    Check(LFilter.IsDefined('BUILD_UNIT') and (not LFilter.IsDefined('BUILD_EXE')) and
      (not LFilter.IsDefined('BUILD_DLL')) and (not LFilter.IsDefined('BUILD_LIB')),
      'build_unit: BUILD_UNIT from the unit header only');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;
end;

procedure TPCConditionalTests.DoTestErrors();
var
  LErrors: TErrors;
  LFilter: TPCConditionalFilter;
  LOutput: TPCTokenStream;
begin
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn03_errors.pcpp', Default(TPCTargetTriple), LErrors, LFilter, LOutput);
    Check(DoCountCode(LErrors, PC_ERR_CND_002) = 1, 'errors: stray @endif is one CD0002');
    Check(DoCountCode(LErrors, PC_ERR_CND_003) = 2,
      'errors: @else after @else and @elseif after @else are two CD0003');
    Check(DoCountCode(LErrors, PC_ERR_CND_001) = 1, 'errors: @define 5 is one CD0001');
    Check((DoCountCode(LErrors, PC_ERR_CND_004) = 2) and
      (DoCodeLines(LErrors, PC_ERR_CND_004) = '10,11'),
      'errors: two open frames at EOF are two CD0004 at their openers');
    Check(LErrors.Count() = 6, 'errors: exactly six errors');
    Check(DoTexts(LOutput, ['module', 'exe', 'cn03', ';', 'z1']),
      'errors: the literal in @define''s symbol slot is dropped with it; inactive tail dropped');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;
end;

procedure TPCConditionalTests.DoTestSymbolSlot();
var
  LErrors: TErrors;
  LFilter: TPCConditionalFilter;
  LOutput: TPCTokenStream;
begin
  // A token in a conditional directive's symbol slot that is no identifier:
  // CD0001 once; a literal / operator / delimiter / primitive is the symbol
  // written wrong and is dropped with the directive, anything that begins the
  // next construct (keyword, directive, C++ keyword, EOF) stays
  // (scripts\zb_cmpl\gen_cn10.py writes the fixture, one row per category)
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn10_slot.pcpp', Default(TPCTargetTriple), LErrors, LFilter, LOutput);
    Check((LErrors.Count() = 7) and (DoCountCode(LErrors, PC_ERR_CND_001) = 7),
      'symbol_slot: seven symbol-less directives are seven CD0001, nothing else (got %d errors)',
      [LErrors.Count()]);
    Check(DoCodeLines(LErrors, PC_ERR_CND_001) = '2,4,6,8,9,10,12',
      'symbol_slot: CD0001 at each directive''s line (got %s)',
      [DoCodeLines(LErrors, PC_ERR_CND_001)]);
    Check(DoTexts(LOutput, ['module', 'exe', 'cn10', ';', 'a1', 'a2', 'a3', 'begin', 'struct', 'a4']),
      'symbol_slot: 1 + int32 dropped; begin, @undef (consumed as a directive), struct, EOF kept');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;
end;

procedure TPCConditionalTests.DoTestInactive();
var
  LErrors: TErrors;
  LFilter: TPCConditionalFilter;
  LOutput: TPCTokenStream;
begin
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn04_inactive.pcpp', Default(TPCTargetTriple), LErrors, LFilter, LOutput);
    Check((LErrors.Count() = 1) and (DoCountCode(LErrors, PC_ERR_CND_001) = 1),
      'inactive: a symbol-less @ifdef in an inactive branch is still CD0001');
    Check((not LFilter.IsDefined('B')) and LFilter.IsDefined('PASKALCPP'),
      'inactive: @define / @undef in an inactive branch change nothing');
    Check(DoTexts(LOutput, ['module', 'exe', 'cn04', ';', 'p', 'end', '.']),
      'inactive: output');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;
end;

procedure TPCConditionalTests.DoTestTargetDefault();
var
  LErrors: TErrors;
  LFilter: TPCConditionalFilter;
  LOutput: TPCTokenStream;
begin
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn05_target_default.pcpp', Default(TPCTargetTriple), LErrors, LFilter, LOutput);
    Check((LErrors.Count() = 0) and
      DoTexts(LOutput, ['module', 'exe', 'cn05', ';', 'a', 'w', 's', 'end', '.']),
      'target_default: TARGET_X86_64, TARGET_WINDOWS, TARGET_64BIT; not TARGET_LINUX');
    Check(LFilter.Target().ToLLVM() = 'x86_64-pc-windows-gnu',
      'target_default: no @target = x86_64-pc-windows-gnu');
    Check(LFilter.IsDefined('TARGET_X86_64_WINDOWS_GNU') and LFilter.IsDefined('TARGET_GNU') and
      (not LFilter.IsDefined('TARGET_X86_64_LINUX_GNU')),
      'target_default: triple TARGET_X86_64_WINDOWS_GNU + ABI TARGET_GNU; not the Linux triple');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;
end;

procedure TPCConditionalTests.DoTestTargetSet();
var
  LErrors: TErrors;
  LFilter: TPCConditionalFilter;
  LOutput: TPCTokenStream;
begin
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn06_target_linux.pcpp', Default(TPCTargetTriple), LErrors, LFilter, LOutput);
    Check((LErrors.Count() = 0) and DoTexts(LOutput, ['module', 'exe', 'cn06', ';', '@target',
      '"x86_64-unknown-linux-gnu"', ';', 'a', 'l', 'end', '.']),
      'target_set: @target picks TARGET_X86_64 / TARGET_LINUX, not TARGET_WINDOWS; its tokens pass through');
    Check(LFilter.Target().ToLLVM() = 'x86_64-unknown-linux-gnu', 'target_set: Target()');
    Check(LFilter.IsDefined('TARGET_X86_64_LINUX_GNU') and LFilter.IsDefined('TARGET_GNU') and
      (not LFilter.IsDefined('TARGET_X86_64_WINDOWS_GNU')),
      'target_set: triple TARGET_X86_64_LINUX_GNU (no vendor) + ABI TARGET_GNU; not the Windows triple');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;

  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn07_target_3part.pcpp', Default(TPCTargetTriple), LErrors, LFilter, LOutput);
    Check((LErrors.Count() = 0) and (LFilter.Target().ToLLVM() = 'x86_64-pc-windows-gnu') and
      (LFilter.Target().ToZig() = 'x86_64-windows-gnu'),
      'target_set: three-part triple normalized to four, ToZig drops the vendor');
    Check(LFilter.IsDefined('BUILD_DLL'), 'target_set: BUILD_DLL from the dll header');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;
end;

procedure TPCConditionalTests.DoTestTargetErrors();
var
  LI: Integer;
  LErrors: TErrors;
  LFilter: TPCConditionalFilter;
  LOutput: TPCTokenStream;
begin
  for LI := Low(TEST_CND_TARGET_ERRORS) to High(TEST_CND_TARGET_ERRORS) do
  begin
    LErrors := TErrors.Create();
    LFilter := TPCConditionalFilter.Create();
    LOutput := TPCTokenStream.Create();
    try
      LErrors.SetMaxErrors(100);
      DoFilterFile(TEST_CND_TARGET_ERRORS[LI].FileName, Default(TPCTargetTriple), LErrors,
        LFilter, LOutput);
      Check((LErrors.Count() = 1) and
        (DoCountCode(LErrors, TEST_CND_TARGET_ERRORS[LI].Code) = 1),
        'target_errors: ' + TEST_CND_TARGET_ERRORS[LI].FileName + ' is exactly one ' +
        TEST_CND_TARGET_ERRORS[LI].Code);
    finally
      LOutput.Free();
      LFilter.Free();
      LErrors.Free();
    end;
  end;

  // Imported module whose @target differs from the main triple: CD0012, and
  // the defines follow the main triple
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn06_target_linux.pcpp', TPCTargetTriple.DefaultTriple(), LErrors, LFilter,
      LOutput);
    Check((LErrors.Count() = 1) and (DoCountCode(LErrors, PC_ERR_CND_012) = 1),
      'target_errors: imported module with a different @target is one CD0012');
    Check((LFilter.Target().ToLLVM() = 'x86_64-pc-windows-gnu') and
      LFilter.IsDefined('TARGET_WINDOWS') and (not LFilter.IsDefined('TARGET_LINUX')) and
      DoTexts(LOutput, ['module', 'exe', 'cn06', ';', '@target', '"x86_64-unknown-linux-gnu"',
      ';', 'a', 'w', 'end', '.']),
      'target_errors: an imported module uses the main triple');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;

  // Imported module whose @target equals the main triple (after normalizing)
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn07_target_3part.pcpp', TPCTargetTriple.DefaultTriple(), LErrors, LFilter,
      LOutput);
    Check(LErrors.Count() = 0, 'target_errors: imported module with an equal @target is fine');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;

  // The build's override (CLI -t) wins over an imported module's @target too:
  // a Linux @target under a Windows -t is no CD0012, the defines follow -t
  // (command line first, then the @directives)
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFileWith('cn06_target_linux.pcpp', TPCTargetTriple.DefaultTriple(),
      TPCTargetTriple.DefaultTriple(), LErrors, LFilter, LOutput);
    Check((LErrors.Count() = 0) and (LFilter.Target().ToLLVM() = 'x86_64-pc-windows-gnu') and
      LFilter.IsDefined('TARGET_WINDOWS') and (not LFilter.IsDefined('TARGET_LINUX')),
      'target_errors: under -t an imported module''s other @target is no CD0012 (got %d reports)',
      [LErrors.Count()]);
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;

  // Under an override an imported @target is still checked for its form
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFileWith('cn08h_shape.pcpp', TPCTargetTriple.DefaultTriple(),
      TPCTargetTriple.DefaultTriple(), LErrors, LFilter, LOutput);
    Check((LErrors.Count() = 1) and (DoCountCode(LErrors, PC_ERR_CND_010) = 1),
      'target_errors: under -t a malformed imported @target is still one CD0010 (got %d reports)',
      [LErrors.Count()]);
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;
end;

procedure TPCConditionalTests.DoTestInvariant();
var
  LI: Integer;
  LErrors: TErrors;
  LLexer: TPCLexer;
  LFilter: TPCConditionalFilter;
  LInput: TPCTokenStream;
  LOutput: TPCTokenStream;
begin
  for LI := Low(TEST_CND_FIXTURES) to High(TEST_CND_FIXTURES) do
  begin
    LErrors := TErrors.Create();
    LLexer := TPCLexer.Create();
    LFilter := TPCConditionalFilter.Create();
    LInput := TPCTokenStream.Create();
    LOutput := TPCTokenStream.Create();
    try
      LErrors.SetMaxErrors(100);
      LLexer.SetErrors(LErrors);
      LFilter.SetErrors(LErrors);
      LLexer.TokenizeFile(TPath.Combine(DoCndDir(), TEST_CND_FIXTURES[LI]), LInput);
      LFilter.Filter(LInput, LOutput, Default(TPCTargetTriple), Default(TPCTargetTriple), Default(TPCTargetTriple));
      Check(DoIsFaithful(LInput, LOutput), 'invariant: ' + TEST_CND_FIXTURES[LI] +
        ' output = active input tokens unchanged, one EOF last');
    finally
      LOutput.Free();
      LInput.Free();
      LFilter.Free();
      LLexer.Free();
      LErrors.Free();
    end;
  end;
end;

procedure TPCConditionalTests.DoTestSpliceNames();
var
  LErrors: TErrors;
  LFilter: TPCConditionalFilter;
  LOutput: TPCTokenStream;
begin
  // A line splice inside a directive name or a symbol is gone from its
  // spelling: @def\<LF>ine is @define, C\<LF>D is the symbol CD
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn10_splice.pcpp', Default(TPCTargetTriple), LErrors, LFilter, LOutput);
    Check(LErrors.Count() = 0, 'splice_names: no errors');
    Check(DoTexts(LOutput, ['module', 'exe', 'cn10', ';', 'a1', 'cd', 'end', '.']),
      'splice_names: spliced @define / @ifdef / @else and a spliced symbol');
    Check(LFilter.IsDefined('A') and LFilter.IsDefined('CD') and (not LFilter.IsDefined('C')),
      'splice_names: the spliced symbol is defined by its spelling');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;
end;

procedure TPCConditionalTests.DoTestSpliceErrors();
var
  LErrors: TErrors;
  LFilter: TPCConditionalFilter;
  LOutput: TPCTokenStream;
  LItems: TArray<TError>;
begin
  // Messages name a spliced directive by its spelling: stray @end\<LF>if,
  // then @if\<LF>def 5 (no symbol, opens an inactive frame never closed)
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn11_splice_errors.pcpp', Default(TPCTargetTriple), LErrors, LFilter,
      LOutput);
    LItems := LErrors.GetItems().ToArray();
    Check(Length(LItems) = 3, 'splice_errors: exactly three errors');
    if Length(LItems) <> 3 then
      Exit;
    Check((LItems[0].Code = PC_ERR_CND_002) and (LItems[0].Range.StartLine = 2) and
      (LItems[0].Message = Format(RSCndNoOpener, ['@endif'])),
      'splice_errors: CD0002 at line 2 names @endif');
    Check((LItems[1].Code = PC_ERR_CND_001) and (LItems[1].Range.StartLine = 4) and
      (LItems[1].Message = Format(RSCndNeedSymbol, ['@ifdef'])),
      'splice_errors: CD0001 at line 4 names @ifdef');
    Check((LItems[2].Code = PC_ERR_CND_004) and (LItems[2].Range.StartLine = 4) and
      (LItems[2].Message = Format(RSCndUnterminated, ['@ifdef'])),
      'splice_errors: CD0004 at line 4 names @ifdef');
    Check(DoTexts(LOutput, ['module', 'exe', 'cn11', ';']),
      'splice_errors: the inactive tail is dropped');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;
end;

procedure TPCConditionalTests.DoTestSpliceTarget();
var
  LErrors: TErrors;
  LFilter: TPCConditionalFilter;
  LOutput: TPCTokenStream;
begin
  // CR LF splices in the @target name and inside its string: the triple is
  // read from the spelling; the tokens pass through with their exact text
  LErrors := TErrors.Create();
  LFilter := TPCConditionalFilter.Create();
  LOutput := TPCTokenStream.Create();
  try
    LErrors.SetMaxErrors(100);
    DoFilterFile('cn12_splice_target.pcpp', Default(TPCTargetTriple), LErrors, LFilter,
      LOutput);
    Check((LErrors.Count() = 0) and (LFilter.Target().ToLLVM() = 'x86_64-unknown-linux-gnu'),
      'splice_target: spliced @target name and string');
    Check(DoTexts(LOutput, ['module', 'exe', 'cn12', ';', '@tar\'#13#10'get',
      '"x86_64-unknown-\'#13#10'linux-gnu"', ';', 'l', 'end', '.']),
      'splice_target: tokens keep their exact text');
  finally
    LOutput.Free();
    LFilter.Free();
    LErrors.Free();
  end;
end;

procedure TPCConditionalTests.DoTestTriple();
var
  LTriple: TPCTargetTriple;
begin
  Check(TPCTargetTriple.Parse('x86_64-gnu', LTriple) = tsBadShape, 'triple: two parts');
  Check(TPCTargetTriple.Parse('a-b-c-d-e', LTriple) = tsBadShape, 'triple: five parts');
  Check(TPCTargetTriple.Parse('x86_64--windows-gnu', LTriple) = tsBadShape, 'triple: empty part');
  Check(TPCTargetTriple.Parse('', LTriple) = tsBadShape, 'triple: empty text');
  Check(TPCTargetTriple.Parse('x86_64-windows-gnu-', LTriple) = tsBadShape,
    'triple: trailing dash is an empty last part');
  Check(TPCTargetTriple.Parse('-x86_64-windows-gnu', LTriple) = tsBadShape,
    'triple: leading dash is an empty first part');
  // Only the supported targets (BNF.md sec 2): everything else is rejected and cleared
  Check((TPCTargetTriple.Parse('alpha-unknown-linux-gnu', LTriple) = tsUnsupported) and
    LTriple.IsEmpty(), 'triple: an unknown arch is unsupported and cleared');
  Check(TPCTargetTriple.Parse('X86_64-pc-windows-gnu', LTriple) = tsUnsupported,
    'triple: exact case');
  Check(TPCTargetTriple.Parse('aarch64-linux-gnu', LTriple) = tsUnsupported,
    'triple: a real LLVM target that is not a supported one');
  Check(TPCTargetTriple.Parse('x86_64-pc-windows-msvc', LTriple) = tsUnsupported,
    'triple: another env of a supported arch / os');
  Check(TPCTargetTriple.Parse('x86_64-w64-windows-gnu', LTriple) = tsUnsupported,
    'triple: a non-canonical vendor (one target, one spelling)');
  Check(TPCTargetTriple.Parse('x86_64-pc-linux-gnu', LTriple) = tsUnsupported,
    'triple: the windows vendor on linux');
  Check((TPCTargetTriple.Parse('x86_64-pc-windows-gnu', LTriple) = tsOk) and
    LTriple.IsWindows() and (LTriple.IntBits() = 32) and (LTriple.LongBits() = 32) and
    (LTriple.LongLongBits() = 64) and (LTriple.PointerBits() = 64) and
    (LTriple.SizeTBits() = 64) and (LTriple.WCharBits() = 16) and (LTriple.FloatBits() = 32) and
    (LTriple.DoubleBits() = 64) and LTriple.IsCharSigned() and (not LTriple.IsWCharSigned()),
    'triple: x86_64 windows model (int 32, long 32, wchar_t 16 unsigned, char signed)');
  Check((TPCTargetTriple.Parse('x86_64-unknown-linux-gnu', LTriple) = tsOk) and
    (not LTriple.IsWindows()) and (LTriple.IntBits() = 32) and (LTriple.LongBits() = 64) and
    (LTriple.LongLongBits() = 64) and (LTriple.PointerBits() = 64) and
    (LTriple.SizeTBits() = 64) and (LTriple.WCharBits() = 32) and (LTriple.FloatBits() = 32) and
    (LTriple.DoubleBits() = 64) and LTriple.IsCharSigned() and LTriple.IsWCharSigned(),
    'triple: x86_64 linux model (int 32, long 64, wchar_t 32 signed, char signed)');
  Check((TPCTargetTriple.Parse(PC_TARGET_X86_64_LINUX_GNU, LTriple) = tsOk) and
    (LTriple.Vendor = 'unknown') and (LTriple.ToLLVM() = 'x86_64-unknown-linux-gnu'),
    'triple: three parts on linux get vendor unknown');
  Check((Default(TPCTargetTriple).PointerBits() = 0) and
    (not Default(TPCTargetTriple).IsCharSigned()) and
    (not Default(TPCTargetTriple).IsWCharSigned()), 'triple: an empty triple has no model');
  Check((TPCTargetTriple.DefaultTriple().ToLLVM() = 'x86_64-pc-windows-gnu') and
    (TPCTargetTriple.DefaultTriple().ToZig() = PC_TARGET_X86_64_WINDOWS_GNU), 'triple: default');
  Check((Length(PC_DATA_MODELS) = 2) and
    (TPCTargetTriple.SupportedTargetsText() = 'x86_64-windows-gnu, x86_64-linux-gnu'),
    'triple: two supported targets, listed for CD0011');
end;

procedure TPCConditionalTests.DoTestDataModelWitness();
var
  LI: Integer;
  LRow: TPCDataModelRow;
  LZig: string;
  LSource: string;
  LParams: string;
  LOutput: string;
  LExitCode: DWORD;
  LRaised: string;
  LParts: TArray<string>;
  LValue: string;
begin
  // The bundled clang is the witness, not the source (sem\datamodel.md Q3): each
  // row must equal its predefines, so a toolchain update that moves a fact fails
  // here instead of changing PaskalCPP's types
  LZig := TUtils.ResolvePath('$P:res\zig\zig.exe');
  LSource := TPath.Combine(DoCndDir(), 'dm_empty.cpp');
  Check(TFile.Exists(LZig) and TFile.Exists(LSource),
    'datamodel_witness: the bundled zig and the empty TU exist');
  for LI := Low(PC_DATA_MODELS) to High(PC_DATA_MODELS) do
  begin
    LRow := PC_DATA_MODELS[LI];
    LParts := LRow.Target.Split(['-']);
    Check((Length(LParts) = 3) and IsZigArch(LParts[0]) and IsZigOS(LParts[1]) and
      IsZigAbi(LParts[2]), Format('datamodel_witness: %s is a zig triple', [LRow.Target]));

    LParams := 'c++ -target ' + LRow.Target + ' -dM -E -x c++ ' +
      TUtils.QuoteCommandArg(LSource);
    LOutput := '';
    LExitCode := 42;
    LRaised := '';
    try
      TUtils.CaptureConsoleOutput('', PChar(LZig), PChar(LParams), DoCndDir(), LExitCode, nil,
        procedure(const ALine: string; const AData: Pointer)
        begin
          LOutput := LOutput + ALine + #10;
        end);
    except
      on E: Exception do
        LRaised := E.Message;
    end;
    Check((LRaised = '') and (LExitCode = 0),
      Format('datamodel_witness: zig ran for %s (exit %d%s)', [LRow.Target, LExitCode, LRaised]));

    Check(DoBitsMatch(LOutput, '__SIZEOF_INT__', LRow.IntBits) and
      DoBitsMatch(LOutput, '__SIZEOF_LONG__', LRow.LongBits) and
      DoBitsMatch(LOutput, '__SIZEOF_LONG_LONG__', LRow.LongLongBits) and
      DoBitsMatch(LOutput, '__SIZEOF_POINTER__', LRow.PointerBits) and
      DoBitsMatch(LOutput, '__SIZEOF_SIZE_T__', LRow.SizeTBits) and
      DoBitsMatch(LOutput, '__SIZEOF_WCHAR_T__', LRow.WCharBits) and
      DoBitsMatch(LOutput, '__SIZEOF_FLOAT__', LRow.FloatBits) and
      DoBitsMatch(LOutput, '__SIZEOF_DOUBLE__', LRow.DoubleBits),
      Format('datamodel_witness: %s sizes equal clang''s', [LRow.Target]));
    // char is unsigned exactly when clang predefines __CHAR_UNSIGNED__
    Check(DoPredefinedValue(LOutput, '__CHAR_UNSIGNED__', LValue) = (not LRow.IsCharSigned),
      Format('datamodel_witness: %s char signedness equals clang''s', [LRow.Target]));
    // wchar_t is unsigned exactly when clang predefines __WCHAR_UNSIGNED__
    Check(DoPredefinedValue(LOutput, '__WCHAR_UNSIGNED__', LValue) = (not LRow.IsWCharSigned),
      Format('datamodel_witness: %s wchar_t signedness equals clang''s', [LRow.Target]));
  end;
end;

function DoAlignTuText(const ARow: TPCAlignModelRow; const ABreak: Boolean): string;
var
  LKind: TPCAlignKind;
  LAlign: Integer;
begin
  // One static_assert per kind: alignof of the emitter's spelling
  // (PC_ALIGN_CPP_TEXT) equals the row; each message names its kind.
  // ABreak = the harness's own control: the int32 row off by one, which
  // clang must refuse
  Result := '#include <cstdint>' + #10 + '#include <string>' + #10 + '#include <vector>' + #10 +
    '#include <type_traits>' + #10 + '#include "pcpp_runtime.h"' + #10;
  for LKind := Low(TPCAlignKind) to High(TPCAlignKind) do
  begin
    LAlign := ARow.Aligns[LKind];
    if ABreak and (LKind = akInt32) then
      LAlign := LAlign + 1;
    Result := Result + Format('static_assert(alignof(%s) == %d, "%s");',
      [PC_ALIGN_CPP_TEXT[LKind], LAlign, GetEnumName(TypeInfo(TPCAlignKind), Ord(LKind))]) + #10;
  end;
end;

function DoCompileAlignTu(const AZig: string; const ARuntime: string; const ATarget: string;
  const AText: string; const ATag: string; out AOutput: string; out AObjectMade: Boolean): DWORD;
var
  LSource: string;
  LObject: string;
  LParams: string;
  LOutput: string;
  LExitCode: DWORD;
begin
  // Writes AText to a temp TU and compiles it for ATarget against the real
  // runtime header; the exit code (42 = not run), the first 1500 characters
  // of the output (or the reason it could not run) and whether the object
  // file appeared (a run that compiled nothing is no pass)
  LSource := TPath.Combine(TPath.GetTempPath(), 'pcpp-align-' + ATag + '.cpp');
  LObject := LSource + '.o';
  LOutput := '';
  LExitCode := 42;
  AObjectMade := False;
  try
    if TFile.Exists(LObject) then
      TFile.Delete(LObject);
    TFile.WriteAllText(LSource, AText, TEncoding.ASCII);
    LParams := 'c++ -c -std=gnu++23 -target ' + ATarget + ' -I ' + TUtils.QuoteCommandArg(ARuntime) +
      ' -o ' + TUtils.QuoteCommandArg(LObject) + ' ' + TUtils.QuoteCommandArg(LSource);
    TUtils.CaptureConsoleOutput('', PChar(AZig), PChar(LParams), TPath.GetTempPath(), LExitCode, nil,
      procedure(const ALine: string; const AData: Pointer)
      begin
        if Length(LOutput) < 1500 then
          LOutput := LOutput + ALine + #10;
      end);
    AObjectMade := TFile.Exists(LObject);
  except
    on E: Exception do
      LOutput := LOutput + 'raised: ' + E.Message;
  end;
  AOutput := LOutput;
  Result := LExitCode;
end;

procedure TPCConditionalTests.DoTestAlignWitness();
var
  LI: Integer;
  LK: Integer;
  LRow: TPCAlignModelRow;
  LFound: Boolean;
  LZig: string;
  LRuntime: string;
  LOutput: string;
  LMade: Boolean;
  LExitCode: DWORD;
  LTriple: TPCTargetTriple;
begin
  // PLAN-PASKAL-ERRORS E2 (r-b-align.md D3): PC_ALIGN_MODELS is the one copy
  // of P7 and the bundled clang with the real runtime header is its witness,
  // so a toolchain or runtime change that moves an alignment fails here.
  // Every supported target has exactly one row; each row's asserts build
  // for its target; the same row broken on purpose is refused (a passing
  // build is the asserts holding, never the harness skipping them)
  LZig := TUtils.ResolvePath('$P:res\zig\zig.exe');
  LRuntime := TUtils.ResolvePath('$P:res\runtime');
  Check(TFile.Exists(LZig) and TFile.Exists(TPath.Combine(LRuntime, 'pcpp_runtime.h')),
    'align_witness: the bundled zig and the runtime header exist');
  Check(Length(PC_ALIGN_MODELS) = Length(PC_DATA_MODELS),
    Format('align_witness: %d alignment rows for %d supported targets',
    [Length(PC_ALIGN_MODELS), Length(PC_DATA_MODELS)]));
  for LI := Low(PC_DATA_MODELS) to High(PC_DATA_MODELS) do
  begin
    LFound := False;
    for LK := Low(PC_ALIGN_MODELS) to High(PC_ALIGN_MODELS) do
    begin
      if PC_ALIGN_MODELS[LK].Target = PC_DATA_MODELS[LI].Target then
        LFound := True;
    end;
    Check(LFound, Format('align_witness: %s has an alignment row', [PC_DATA_MODELS[LI].Target]));
  end;

  // AlignOf reads the row of the triple's target; an empty triple has none
  Check((TPCTargetTriple.Parse(PC_TARGET_X86_64_WINDOWS_GNU, LTriple) = tsOk) and
    (LTriple.AlignOf(akWChar) = 2) and (LTriple.AlignOf(akInt64) = 8),
    'align_witness: AlignOf on windows-gnu (wchar 2, int64 8)');
  Check((TPCTargetTriple.Parse(PC_TARGET_X86_64_LINUX_GNU, LTriple) = tsOk) and
    (LTriple.AlignOf(akWChar) = 4) and (LTriple.AlignOf(akSet) = 8),
    'align_witness: AlignOf on linux-gnu (wchar 4, set 8)');
  Check(Default(TPCTargetTriple).AlignOf(akInt32) = 0, 'align_witness: an empty triple aligns nothing');

  for LI := Low(PC_ALIGN_MODELS) to High(PC_ALIGN_MODELS) do
  begin
    LRow := PC_ALIGN_MODELS[LI];
    LExitCode := DoCompileAlignTu(LZig, LRuntime, LRow.Target, DoAlignTuText(LRow, False),
      'ok' + IntToStr(LI), LOutput, LMade);
    Check((LExitCode = 0) and LMade, Format('align_witness: %s alignments equal clang''s (exit %d, object %s) %s',
      [LRow.Target, LExitCode, BoolToStr(LMade, True), LOutput]));
    LExitCode := DoCompileAlignTu(LZig, LRuntime, LRow.Target, DoAlignTuText(LRow, True),
      'neg' + IntToStr(LI), LOutput, LMade);
    Check((LExitCode <> 0) and (LExitCode <> 42) and LOutput.Contains('akInt32'),
      Format('align_witness: %s refuses the int32 row off by one (exit %d) %s', [LRow.Target, LExitCode, LOutput]));
  end;
end;

procedure TPCConditionalTests.DoTestSizeWitness();
var
  LI: Integer;
  LZig: string;
  LRuntime: string;
  LTarget: string;
  LCap: string;
  LHead: string;
  LOutput: string;
  LMade: Boolean;
  LExitCode: DWORD;
begin
  // F47: PC_MAX_OBJECT_SIZE (SEM's count rule), the runtime's
  // ::pcpp::max_object_size (its Array check) and PC_CLANG_RECORD_TOO_LARGE
  // (the Compiler owns clang's record text) are three spellings of clang's
  // one cap; the bundled clang with the real runtime header is their witness
  // on every supported target, so a toolchain or runtime change that moves
  // the cap or rewords the error fails here. A struct and an Array of exactly
  // the cap build; one byte more is refused in clang's text (the record) and
  // at the runtime's fatal check (the Array), nothing else said
  LZig := TUtils.ResolvePath('$P:res\zig\zig.exe');
  LRuntime := TUtils.ResolvePath('$P:res\runtime');
  Check(TFile.Exists(LZig) and TFile.Exists(TPath.Combine(LRuntime, 'pcpp_runtime.h')),
    'size_witness: the bundled zig and the runtime header exist');
  LCap := UIntToStr(PC_MAX_OBJECT_SIZE);
  LHead := '#include <cstddef>' + #10 + '#include "pcpp_runtime.h"' + #10;
  for LI := Low(PC_DATA_MODELS) to High(PC_DATA_MODELS) do
  begin
    LTarget := PC_DATA_MODELS[LI].Target;

    // The cap itself: both spellings agree, and a type of exactly that size
    // is laid out (a variable makes clang lay each one out)
    LExitCode := DoCompileAlignTu(LZig, LRuntime, LTarget,
      LHead + 'static_assert(::pcpp::max_object_size == ' + LCap + 'ull, "runtime cap");' + #10 +
      'struct S { char B[' + LCap + 'ull]; };' + #10 + 'S V{};' + #10 +
      '::pcpp::Array<char, ' + LCap + 'ull> A{};' + #10,
      'size_ok' + IntToStr(LI), LOutput, LMade);
    Check((LExitCode = 0) and LMade, Format('size_witness: %s lays out a struct and an Array of %s bytes (exit %d, object %s) %s',
      [LTarget, LCap, LExitCode, BoolToStr(LMade, True), LOutput]));

    // One byte more in a struct: clang's own record text
    LExitCode := DoCompileAlignTu(LZig, LRuntime, LTarget,
      LHead + 'struct S { char B[' + LCap + 'ull]; char C; };' + #10 + 'S V{};' + #10,
      'size_rec' + IntToStr(LI), LOutput, LMade);
    Check((LExitCode <> 0) and (LExitCode <> 42) and LOutput.Contains(PC_CLANG_RECORD_TOO_LARGE),
      Format('size_witness: %s refuses a struct one byte past the cap in its record text (exit %d) %s',
      [LTarget, LExitCode, LOutput]));

    // One element more in an Array: the runtime's check, fatal, alone
    LExitCode := DoCompileAlignTu(LZig, LRuntime, LTarget,
      LHead + '::pcpp::Array<char, ' + LCap + 'ull + 1> A{};' + #10,
      'size_arr' + IntToStr(LI), LOutput, LMade);
    Check((LExitCode <> 0) and (LExitCode <> 42) and LOutput.Contains(PC_FRONTEND_CHECK_SIZE) and
      LOutput.Contains('fatal error') and LOutput.Contains('1 error generated'),
      Format('size_witness: %s stops an Array one element past the cap at the runtime''s check (exit %d) %s',
      [LTarget, LExitCode, LOutput]));
  end;
end;

end.
