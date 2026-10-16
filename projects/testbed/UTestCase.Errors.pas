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
  UTestCase.Errors - StdApp.Base TErrors status tests

  TTestCase suite for what TErrors sends its status listener (PLAN-COMPLIANCE
  F14): a hint / warning goes out once complete, with the notes AddRelated
  attaches after Add, in the form PrintErrors prints them; reports and status
  lines keep the order they were made in; errors stay for PrintErrors; a
  rollback (TruncateTo) withdraws a held report; Clear and a listener switch
  send it first. Each test captures the listener's lines in order.

  Dependencies: StdApp.TestCase, StdApp.Base
===============================================================================}

unit UTestCase.Errors;

interface

uses
  StdApp.TestCase;

type

  { TPCErrorsTests }
  TPCErrorsTests = class(TTestCase)
  private
    // One test per concern; Create registers each under its CLI name
    procedure DoTestNotes();
    procedure DoTestOrder();
    procedure DoTestRollback();
    procedure DoTestListener();
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base;

const
  { TEST_ERR_FILE }
  // A located report's file, as TErrors stores it (forward slashes)
  TEST_ERR_FILE = 'c:/t/f.pcpp';

{ DoCapture }
// A status listener that keeps every line it is sent, in order
function DoCapture(const ALines: TList<string>): TStatusCallback;
var
  LLines: TList<string>;
begin
  LLines := ALines;
  Result :=
    procedure(const AText: string; const AUserData: Pointer)
    begin
      LLines.Add(AText);
    end;
end;

{ DoLocated }
// A point range in TEST_ERR_FILE
function DoLocated(const ALine: UInt64; const AColumn: UInt64): TSourceRange;
begin
  Result.Clear();
  Result.Filename := TEST_ERR_FILE;
  Result.StartLine := ALine;
  Result.StartColumn := AColumn;
  Result.EndLine := ALine;
  Result.EndColumn := AColumn;
end;

{ TPCErrorsTests }

constructor TPCErrorsTests.Create();
begin
  inherited;

  Title := 'Errors';
  RegisterTest('notes', DoTestNotes);
  RegisterTest('order', DoTestOrder);
  RegisterTest('rollback', DoTestRollback);
  RegisterTest('listener', DoTestListener);
end;

procedure TPCErrorsTests.Run();
begin
  inherited;
end;

procedure TPCErrorsTests.DoTestNotes();
var
  LLines: TList<string>;
  LErrors: TErrors;
  LRange: TSourceRange;
begin
  LLines := TList<string>.Create();
  LErrors := TErrors.Create();
  try
    LErrors.SetStatusCallback(DoCapture(LLines));

    // A warning with a located and a plain note: nothing goes out until
    // it is complete, then the warning and its notes, under it, in order
    LErrors.Add(TEST_ERR_FILE, 2, 5, esWarning, 'XX0001', 'the warning');
    Check(LLines.Count = 0, 'notes: a warning is held until complete (sent %d lines)', [LLines.Count]);
    LErrors.AddRelated(DoLocated(3, 7), 'the located note');
    LRange.Clear();
    LErrors.AddRelated(LRange, 'the plain note');
    LErrors.Flush();

    Check(LLines.Count = 3, 'notes: the warning and its 2 notes are sent (got %d lines)', [LLines.Count]);
    if LLines.Count <> 3 then
      Exit;
    Check(LLines[0].Contains('XX0001') and LLines[0].Contains('the warning'),
      'notes: the warning first [%s]', [LLines[0]]);
    Check(LLines[1].Contains(TEST_ERR_FILE + '(3,7)') and LLines[1].Contains('the located note'),
      'notes: the located note under it, with its place [%s]', [LLines[1]]);
    Check(LLines[2].Contains('the plain note'), 'notes: the plain note last [%s]', [LLines[2]]);

    // Sent once: a second flush has nothing held
    LErrors.Flush();
    Check(LLines.Count = 3, 'notes: sent once (got %d lines)', [LLines.Count]);
  finally
    LErrors.Free();
    LLines.Free();
  end;
end;

procedure TPCErrorsTests.DoTestOrder();
var
  LLines: TList<string>;
  LErrors: TErrors;
begin
  LLines := TList<string>.Create();
  LErrors := TErrors.Create();
  try
    LErrors.SetMaxErrors(10);
    LErrors.SetStatusCallback(DoCapture(LLines));

    // A hint with its note, a status line, a warning, an error with a note:
    // the listener sees them in that order; the error is PrintErrors' only.
    // PrintErrors([]) prints nothing and sends the held warning first
    LErrors.Add(TEST_ERR_FILE, 1, 1, esHint, 'XX0002', 'the hint');
    LErrors.AddRelated(DoLocated(1, 2), 'the hint note');
    LErrors.Status('the status line');
    LErrors.Add(TEST_ERR_FILE, 4, 1, esWarning, 'XX0003', 'the second warning');
    LErrors.Add(TEST_ERR_FILE, 5, 1, esError, 'XX0004', 'the error');
    LErrors.AddRelated(DoLocated(5, 2), 'the error note');
    LErrors.PrintErrors([]);

    Check(LLines.Count = 4, 'order: hint, its note, status, warning (got %d lines)', [LLines.Count]);
    if LLines.Count <> 4 then
      Exit;
    Check(LLines[0].Contains('XX0002'), 'order: the hint first [%s]', [LLines[0]]);
    Check(LLines[1].Contains('the hint note'), 'order: its note second [%s]', [LLines[1]]);
    Check(LLines[2] = 'the status line', 'order: the status line third [%s]', [LLines[2]]);
    Check(LLines[3].Contains('XX0003'), 'order: the warning last, the error never [%s]', [LLines[3]]);
  finally
    LErrors.Free();
    LLines.Free();
  end;
end;

procedure TPCErrorsTests.DoTestRollback();
var
  LLines: TList<string>;
  LErrors: TErrors;
begin
  LLines := TList<string>.Create();
  LErrors := TErrors.Create();
  try
    LErrors.SetStatusCallback(DoCapture(LLines));

    // A warning a rollback withdraws is never sent
    LErrors.Add(TEST_ERR_FILE, 1, 1, esWarning, 'XX0005', 'withdrawn');
    LErrors.TruncateTo(0);
    LErrors.Flush();
    Check(LLines.Count = 0, 'rollback: a withdrawn warning is never sent (got %d lines)', [LLines.Count]);

    // A rollback that keeps it: still sent
    LErrors.Add(TEST_ERR_FILE, 2, 1, esWarning, 'XX0006', 'kept by the rollback');
    LErrors.TruncateTo(1);
    LErrors.Flush();
    Check((LLines.Count = 1) and LLines[LLines.Count - 1].Contains('XX0006'),
      'rollback: a warning the rollback keeps is sent (got %d lines)', [LLines.Count]);

    // Clear sends the held one before it goes
    LErrors.Add(TEST_ERR_FILE, 3, 1, esWarning, 'XX0007', 'cleared');
    LErrors.Clear();
    Check((LLines.Count = 2) and LLines[LLines.Count - 1].Contains('XX0007'),
      'rollback: Clear sends the held warning first (got %d lines)', [LLines.Count]);
  finally
    LErrors.Free();
    LLines.Free();
  end;
end;

procedure TPCErrorsTests.DoTestListener();
var
  LFirst: TList<string>;
  LSecond: TList<string>;
  LErrors: TErrors;
begin
  LFirst := TList<string>.Create();
  LSecond := TList<string>.Create();
  LErrors := TErrors.Create();
  try
    // A held warning goes to the listener it was reported under
    LErrors.SetStatusCallback(DoCapture(LFirst));
    LErrors.Add(TEST_ERR_FILE, 1, 1, esWarning, 'XX0008', 'first listener');
    LErrors.SetStatusCallback(DoCapture(LSecond));
    LErrors.Flush();
    Check((LFirst.Count = 1) and (LSecond.Count = 0),
      'listener: the first listener gets it (first %d, second %d lines)', [LFirst.Count, LSecond.Count]);
  finally
    LErrors.Free();
    LSecond.Free();
    LFirst.Free();
  end;
end;

end.
