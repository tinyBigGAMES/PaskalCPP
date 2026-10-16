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
  UTestbed - Test harness entry point

  RunTestbed (called from the .dpr) runs Menu: RegisterMenuItems wires the
  TTestCase classes (UTestCase.*) into the console menu. No params = the
  interactive menu; with params it runs headless (testbed -h for the
  selectors: -all, -list, CaseName, CaseName.TestName). The tests live in
  the UTestCase.* units; this unit only wires them in.

  Dependencies: StdApp.Utils, StdApp.Console, StdApp.Console.Menu,
  UTestCase.ZigBuild, UTestCase.Lexer, UTestCase.AST, UTestCase.Conditionals,
  UTestCase.CString, UTestCase.Parser, UTestCase.SourceText, UTestCase.Utils,
  UTestCase.JSON, UTestCase.Errors, UTestCase.SerializedDiag, UTestCase.BuildOutput, UTestCase.ZigBuildPaths,
  UTestCase.CppJumps, UTestCase.Scopes, UTestCase.Semantics, UTestCase.CppWriter,
  UTestCase.Emitter, UTestCase.Run, UTestCase.Compiler, UTestCase.LSP,
  UTestCase.Debug, UTestCase.Compliance (UTestFrontend: shared harness;
  UTestCompliance: the compliance tester's engine)
===============================================================================}

unit UTestbed;

interface

procedure RunTestbed();

implementation

uses
  System.SysUtils,
  StdApp.Utils,
  StdApp.Console,
  StdApp.Console.Menu,
  UTestCase.ZigBuild,
  UTestCase.Lexer,
  UTestCase.AST,
  UTestCase.Conditionals,
  UTestCase.CString,
  UTestCase.Parser,
  UTestCase.SourceText,
  UTestCase.Utils,
  UTestCase.JSON,
  UTestCase.Errors,
  UTestCase.SerializedDiag,
  UTestCase.BuildOutput,
  UTestCase.ZigBuildPaths,
  UTestCase.CppJumps,
  UTestCase.Scopes,
  UTestCase.Semantics,
  UTestCase.CppWriter,
  UTestCase.Emitter,
  UTestCase.Run,
  UTestCase.Compiler,
  UTestCase.LSP,
  UTestCase.Debug,
  UTestCase.Compliance;

procedure RegisterMenuItems(const AMenu: TConsoleMenu);
begin
  // ZigBuild and Compliance run by name only (TTestCase.InRunAll False):
  // registered, never part of -all
  AMenu.SetCategory('ZigBuild');
  AMenu.AddTestCase(TPCZigBuildTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('SourceText');
  AMenu.AddTestCase(TPCSourceTextTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('Lexer');
  AMenu.AddTestCase(TPCLexerTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('CppJumps');
  AMenu.AddTestCase(TPCCppJumpsTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('AST');
  AMenu.AddTestCase(TPCASTTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('Conditionals');
  AMenu.AddTestCase(TPCConditionalTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('CString');
  AMenu.AddTestCase(TPCCStringTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('Parser');
  AMenu.AddTestCase(TPCParserTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('Utils');
  AMenu.AddTestCase(TPCUtilsTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('JSON');
  AMenu.AddTestCase(TPCJsonTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('Errors');
  AMenu.AddTestCase(TPCErrorsTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('SerializedDiag');
  AMenu.AddTestCase(TPCSerializedDiagTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('BuildOutput');
  AMenu.AddTestCase(TPCBuildOutputTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('ZigBuildPaths');
  AMenu.AddTestCase(TPCZigBuildPathTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('Scopes');
  AMenu.AddTestCase(TPCScopesTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('Semantics');
  AMenu.AddTestCase(TPCSemanticsTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('CppWriter');
  AMenu.AddTestCase(TPCCppWriterTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('Emitter');
  AMenu.AddTestCase(TPCEmitterTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('Run');
  AMenu.AddTestCase(TPCRunTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('Compiler');
  AMenu.AddTestCase(TPCCompilerTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('LSP');
  AMenu.AddTestCase(TPCLspTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('Debug');
  AMenu.AddTestCase(TPCDebugTests);
  AMenu.ClearCategory();

  AMenu.SetCategory('Compliance');
  AMenu.AddTestCase(TPCComplianceTests);
  AMenu.ClearCategory();
end;

procedure Menu();
var
  LMenu: TConsoleMenu;
begin
  LMenu := TConsoleMenu.Create();
  try
    LMenu.Title('PaskalCPP Testbed');
    RegisterMenuItems(LMenu);
    LMenu.Run();
  finally
    LMenu.Free();
  end;
end;

procedure RunTestbed();
begin
  try
    Menu();
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + 'EXCEPTION: %s', [E.Message]);

    end;
  end;

  if TUtils.RunFromIDE() then
    TConsole.Pause();

end;

end.
