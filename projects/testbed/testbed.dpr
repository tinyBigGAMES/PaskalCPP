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
===============================================================================}

program testbed;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  UTestbed in 'UTestbed.pas',
  UTestCase.AST in 'UTestCase.AST.pas',
  UTestCase.BuildOutput in 'UTestCase.BuildOutput.pas',
  UTestCase.Compiler in 'UTestCase.Compiler.pas',
  UTestCase.Compliance in 'UTestCase.Compliance.pas',
  UTestCase.Conditionals in 'UTestCase.Conditionals.pas',
  UTestCase.CppJumps in 'UTestCase.CppJumps.pas',
  UTestCase.CppWriter in 'UTestCase.CppWriter.pas',
  UTestCase.CString in 'UTestCase.CString.pas',
  UTestCase.Debug in 'UTestCase.Debug.pas',
  UTestCase.Emitter in 'UTestCase.Emitter.pas',
  UTestCase.Errors in 'UTestCase.Errors.pas',
  UTestCase.JSON in 'UTestCase.JSON.pas',
  UTestCase.Lexer in 'UTestCase.Lexer.pas',
  UTestCase.LSP in 'UTestCase.LSP.pas',
  UTestCase.Parser in 'UTestCase.Parser.pas',
  UTestCase.Run in 'UTestCase.Run.pas',
  UTestCase.Scopes in 'UTestCase.Scopes.pas',
  UTestCase.Semantics in 'UTestCase.Semantics.pas',
  UTestCase.SerializedDiag in 'UTestCase.SerializedDiag.pas',
  UTestCase.SourceText in 'UTestCase.SourceText.pas',
  UTestCase.Utils in 'UTestCase.Utils.pas',
  UTestCase.ZigBuild in 'UTestCase.ZigBuild.pas',
  UTestCase.ZigBuildPaths in 'UTestCase.ZigBuildPaths.pas',
  UTestCompliance in 'UTestCompliance.pas',
  UTestFrontend in 'UTestFrontend.pas';

begin
  RunTestbed();
end.
