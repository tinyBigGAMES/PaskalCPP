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
  UTestCase.Compiler - compiler reports whose condition no .pcpp sets up

  TPCTestCase suite for TPCCompiler reports that need a state of the
  machine a .pcpp input cannot make. library_locked: a static library the
  program links is held open with nothing shared while the compiler reads
  the build's libraries for their data keys (TPCCompiler.DoLinkedResDataKeys),
  so it cannot be opened: CMP0007, at the @linklibrary value naming it. The
  same program with the file free is the negative: the file opens, holds no
  symbol index and gives no CMP0007 (dir_linklibrary_err_unreadable's case).
  A code test because a .pcpp cannot hold a file open (user 2026-10-26).

  Dependencies: PaskalCPP.TestSuite.CodeTest, PaskalCPP.Compiler,
    PaskalCPP.ZigBuild
===============================================================================}

unit UTestCase.Compiler;

interface

uses
  PaskalCPP.TestSuite.Types,
  PaskalCPP.TestSuite.CodeTest;

type

  { TPCCompilerTests }
  TPCCompilerTests = class(TPCTestCase)
  private
    function DoWriteLockedProgram(out ASource: string; out ALibrary: string): Boolean;
    procedure DoCheckPrepare(const ASource: string; const AExpected: array of string;
      const ALabel: string);
    procedure DoTestLibraryLocked(const ACell: TPCTestCell);
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  PaskalCPP.ZigBuild,
  PaskalCPP.Compiler;

const
  { PC_TEST_CMP_LOCKED_LIB }
  // The library the program links; on Windows its file is <name>.lib
  PC_TEST_CMP_LOCKED_LIB = 'cmp_locked';

  { PC_TEST_CMP_LOCKED_SOURCE }
  // The program; %s = its library folder, forward slashes. A data key no
  // @addresdata of the build adds (SM0122, line 9) makes SEM ask for the
  // linked libraries' keys; the library is named on line 4
  PC_TEST_CMP_LOCKED_SOURCE = '''
module exe cmp_library_locked;

@addlibrarypath "%s";
@linklibrary "cmp_locked";

import ResData;

begin
  println("{}", HasResData("cmp_library_none"));
end.
''';

{ TPCCompilerTests }

constructor TPCCompilerTests.Create();
begin
  inherited;

  AreaName := 'cmp';
  RegisterTest('library_locked', DoTestLibraryLocked);
end;

function TPCCompilerTests.DoWriteLockedProgram(out ASource: string;
  out ALibrary: string): Boolean;
var
  LFolder: string;
  LText: string;
begin
  // The library (its bytes are never read: any text does) and the program,
  // flat in the output folder
  ASource := '';
  ALibrary := WriteScratch(PC_TEST_CMP_LOCKED_LIB + '.lib',
    TEncoding.UTF8.GetBytes('Not a library: UTestCase.Compiler locks this file.'));
  if ALibrary = '' then
    Exit(False);

  LFolder := ScratchFolder().Replace('\', '/');
  LText := Format(PC_TEST_CMP_LOCKED_SOURCE, [LFolder]);
  ASource := WriteScratch('cmp_library_locked.pcpp', TEncoding.UTF8.GetBytes(LText));
  Result := ASource <> '';
end;

procedure TPCCompilerTests.DoCheckPrepare(const ASource: string;
  const AExpected: array of string; const ALabel: string);
var
  LCompiler: TPCCompiler;
begin
  // Prepare only: SEM asks for the libraries' keys there. Nothing is built
  // (the linker would reject the file too: not this test's report)
  LCompiler := TPCCompiler.Create();
  try
    LCompiler.SetOptimizeLevel(olDebug);
    Check(LCompiler.Prepare(ASource, ScratchFolder()), '%s: prepared', [ALabel]);
    CheckErrors(LCompiler.GetErrors(), AExpected, ALabel);
  finally
    LCompiler.Free();
  end;
end;

procedure TPCCompilerTests.DoTestLibraryLocked(const ACell: TPCTestCell);
var
  LSource: string;
  LLibrary: string;
  LLock: TFileStream;
begin
  if not DoWriteLockedProgram(LSource, LLibrary) then
    Exit;

  // Free: the file opens and holds no symbol index, so no CMP0007
  Section('free');
  DoCheckPrepare(LSource, ['9 WARN SM0122@28'], 'free library');

  // Held open by a handle that shares nothing: the compiler cannot open it
  Section('locked');
  try
    LLock := TFileStream.Create(LLibrary, fmOpenRead or fmShareExclusive);
  except
    on E: Exception do
    begin
      Fail(Format('%s cannot be locked: %s', [LLibrary, E.Message]));
      Exit;
    end;
  end;
  try
    DoCheckPrepare(LSource, ['4 WARN CMP0007@14', '9 WARN SM0122@28'], 'locked library');
  finally
    LLock.Free();
  end;
end;

end.
