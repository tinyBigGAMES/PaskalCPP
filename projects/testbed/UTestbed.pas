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

===============================================================================}

unit UTestbed;

interface

procedure RunTestbed();

implementation

uses
  System.SysUtils,
  StdApp.Utils,
  StdApp.Console,
  PaskalCPP.TestSuite,
  UTestCase.LSP,
  UTestCase.Debug,
  UTestCase.Compiler,
  UTestCase.Lex;

procedure RunTestbed();
var
  LSuite: TPCTestSuite;
begin
  try
    LSuite := TPCTestSuite.Create();
    try
      // Source tests: every .pcpp under res\tests (area = first folder
      // under the root, or the stem prefix before '_')
      LSuite.AddSourceRoot('$P:res/tests');

      // Examples gate: every .pcpp under res\examples builds clean on both
      // targets (area examples, id examples.<folder>.<stem>)
      LSuite.AddExampleRoot('$P:res/examples');

      // Code-test fixtures: <fixture root>\<area>\fixtures\<file>
      LSuite.SetFixtureRoot('$P:res/tests');

      // Code tests: only what no .pcpp can reach (user 2026-10-25)
      LSuite.RegisterCase(TPCLspTests);
      LSuite.RegisterCase(TPCDebugTests);
      LSuite.RegisterCase(TPCCompilerTests);
      LSuite.RegisterCase(TPCLexTests);

      ExitCode := LSuite.RunCommandLine();
    finally
      LSuite.Free();
    end;
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + 'EXCEPTION: %s', [E.Message]);
      ExitCode := 1;
    end;
  end;

end;

end.
