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

program pcpp;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  UPCPP in 'UPCPP.pas',
  PaskalCPP.Asar in '..\..\src\PaskalCPP.Asar.pas',
  PaskalCPP.AST in '..\..\src\PaskalCPP.AST.pas',
  PaskalCPP.BuildOutput in '..\..\src\PaskalCPP.BuildOutput.pas',
  PaskalCPP.CLI in '..\..\src\PaskalCPP.CLI.pas',
  PaskalCPP.Common in '..\..\src\PaskalCPP.Common.pas',
  PaskalCPP.Compiler in '..\..\src\PaskalCPP.Compiler.pas',
  PaskalCPP.Conditionals in '..\..\src\PaskalCPP.Conditionals.pas',
  PaskalCPP.CppJumps in '..\..\src\PaskalCPP.CppJumps.pas',
  PaskalCPP.CppWriter in '..\..\src\PaskalCPP.CppWriter.pas',
  PaskalCPP.Debug.DAP in '..\..\src\PaskalCPP.Debug.DAP.pas',
  PaskalCPP.Debug.REPL in '..\..\src\PaskalCPP.Debug.REPL.pas',
  PaskalCPP.Debug.Runtime in '..\..\src\PaskalCPP.Debug.Runtime.pas',
  PaskalCPP.Debug.Symbols in '..\..\src\PaskalCPP.Debug.Symbols.pas',
  PaskalCPP.Debug.Target in '..\..\src\PaskalCPP.Debug.Target.pas',
  PaskalCPP.Emitter in '..\..\src\PaskalCPP.Emitter.pas',
  PaskalCPP.Lexer in '..\..\src\PaskalCPP.Lexer.pas',
  PaskalCPP.LSP.Completion in '..\..\src\PaskalCPP.LSP.Completion.pas',
  PaskalCPP.LSP.Diagnostics in '..\..\src\PaskalCPP.LSP.Diagnostics.pas',
  PaskalCPP.LSP.Docs in '..\..\src\PaskalCPP.LSP.Docs.pas',
  PaskalCPP.LSP.Document in '..\..\src\PaskalCPP.LSP.Document.pas',
  PaskalCPP.LSP.Formatter in '..\..\src\PaskalCPP.LSP.Formatter.pas',
  PaskalCPP.LSP.Hints in '..\..\src\PaskalCPP.LSP.Hints.pas',
  PaskalCPP.LSP.Outline in '..\..\src\PaskalCPP.LSP.Outline.pas',
  PaskalCPP.LSP.Server in '..\..\src\PaskalCPP.LSP.Server.pas',
  PaskalCPP.LSP.Symbols in '..\..\src\PaskalCPP.LSP.Symbols.pas',
  PaskalCPP.LSP.Transport in '..\..\src\PaskalCPP.LSP.Transport.pas',
  PaskalCPP.LSP.Uri in '..\..\src\PaskalCPP.LSP.Uri.pas',
  PaskalCPP.Parser in '..\..\src\PaskalCPP.Parser.pas',
  PaskalCPP.Scopes in '..\..\src\PaskalCPP.Scopes.pas',
  PaskalCPP.Semantics in '..\..\src\PaskalCPP.Semantics.pas',
  PaskalCPP.SerializedDiag in '..\..\src\PaskalCPP.SerializedDiag.pas',
  PaskalCPP.SourceText in '..\..\src\PaskalCPP.SourceText.pas',
  PaskalCPP.TokenStream in '..\..\src\PaskalCPP.TokenStream.pas',
  PaskalCPP.UnicodeNames in '..\..\src\PaskalCPP.UnicodeNames.pas',
  PaskalCPP.ZigBuild in '..\..\src\PaskalCPP.ZigBuild.pas',
  PaskalCPP.ZigBuild.Targets in '..\..\src\PaskalCPP.ZigBuild.Targets.pas',
  StdApp.Resources in '..\..\src\StdApp.Resources.pas';

begin
  ReportMemoryLeaksOnShutdown := True;
  RunCLI();
end.
