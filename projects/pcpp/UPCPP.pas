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
  UPCPP - pcpp command-line entry point

  RunCLI is called by pcpp.dpr: it runs TPCCLI.Execute (PaskalCPP.CLI) and
  reports an exception that escaped it (exit code 1).

  Dependencies: StdApp.Console, StdApp.Resources, PaskalCPP.CLI
===============================================================================}

unit UPCPP;

{$I StdApp.Defines.inc}

interface

procedure RunCLI();

implementation

uses
  System.SysUtils,
  StdApp.Console,
  StdApp.Resources,
  PaskalCPP.CLI;

procedure RunCLI();
var
  LCLI: TPCCLI;
begin
  try
    ExitCode := 0;
    LCLI := TPCCLI.Create();
    try
      LCLI.Execute();
    finally
      LCLI.Free();
    end;
  except
    on E: Exception do
    begin
      // An exception that escaped the CLI is a failure, never exit code 0
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + RSPcCliException, [E.Message]);
      ExitCode := PC_CLI_EXIT_FAILED;
    end;
  end;
end;

end.
