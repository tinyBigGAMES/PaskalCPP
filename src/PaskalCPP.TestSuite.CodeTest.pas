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
  PaskalCPP.TestSuite.CodeTest - TPCTestCase, the base of every Delphi code test

  A code test checks one atom on its own, with input no .pcpp file produces
  (a byte sequence the lexer must refuse, a driver setting no directive
  reaches). A class of them names its area (AreaName) and registers its
  tests in its constructor (RegisterTest); TPCTestSuite.RegisterCase takes
  the class and makes every test a suite item <area>.<name>, filtered, run
  per cell and reported like a .pcpp test.

  Inside a test: Section, Check / CheckEqual / CheckText / CheckErrors /
  CheckRaises, Fail, Skip; Fixture(name) is a file in the area's fixture
  folder, Scratch(name) a file in the output folder, AreaFolder() the area's
  own folder (its .pcpp tests), each proven inside the repo. Every check
  goes into the run's TPCTestResult: a test never writes to the console,
  the suite's reporter prints.

  Dependencies: StdApp.Base (TBaseObject, TErrors), StdApp.Utils
    (ResolvePath), StdApp.Resources (RSTst*), PaskalCPP.TestSuite.Types
  Notes: Skip and Fail record, they do not leave the test: a test calls
    Exit after Skip when nothing more applies. A test that checks nothing
    and skips nothing fails (a vacuous pass hides a broken test). An
    exception out of Setup, the test or Teardown is a failed check naming
    the phase; the next test runs as normal.
===============================================================================}

unit PaskalCPP.TestSuite.CodeTest;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.TestSuite.Types;

type
  { TPCTestProc }
  // One code test's body; ACell = the cell this run is for
  TPCTestProc = reference to procedure(const ACell: TPCTestCell);

  { TPCCodeTest }
  // One registered code test
  TPCCodeTest = record
    TestName: string;
    Proc: TPCTestProc;
    Deps: TArray<string>;           // stems of .pcpp tests built first, in this run's cell
    Cells: TPCTestCells;            // [] = the suite's default cells
  end;

  { TPCTestCase }
  TPCTestCase = class(TBaseObject)
  private
    FAreaName: string;
    FTests: TList<TPCCodeTest>;
    FRepoRoot: string;
    FFixtureRoot: string;
    FScratchRoot: string;
    // The run in progress (RunTest): every check lands here
    FResult: TPCTestResult;
    FSectionTitle: string;
    FRunning: Boolean;

    procedure DoRecord(const APassed: Boolean; const AText: string);
    function DoGuard(const APhase: string; const AProc: TProc): Boolean;
    function DoInside(const APath: string; const ARoot: string): Boolean;
    function DoPathIn(const AFolder: string; const AFileName: string;
      const ALimit: string): string;
    function DoUnescapeBundleText(const AText: string; out AOut: string): Boolean;
    procedure DoRegister(const ATestName: string; const AProc: TPCTestProc;
      const ADeps: array of string; const ACells: array of TPCTestCell);
  protected
    // Registration (the subclass's constructor)
    procedure RegisterTest(const ATestName: string; const AProc: TPCTestProc); overload;
    procedure RegisterTest(const ATestName: string; const AProc: TPCTestProc;
      const ADeps: array of string); overload;
    procedure RegisterTest(const ATestName: string; const AProc: TPCTestProc;
      const ADeps: array of string; const ACells: array of TPCTestCell); overload;

    // Inside a test
    procedure Section(const ATitle: string);
    procedure Check(const ACondition: Boolean; const ALabel: string); overload;
    procedure Check(const ACondition: Boolean; const ALabel: string;
      const AArgs: array of const); overload;
    procedure CheckEqual(const AExpected: Int64; const AActual: Int64;
      const ALabel: string); overload;
    procedure CheckEqual(const AExpected: UInt64; const AActual: UInt64;
      const ALabel: string); overload;
    procedure CheckEqual(const AExpected: string; const AActual: string;
      const ALabel: string); overload;
    procedure CheckEqual(const AExpected: Boolean; const AActual: Boolean;
      const ALabel: string); overload;
    procedure CheckEqual(const AExpected: Double; const AActual: Double;
      const ATolerance: Double; const ALabel: string); overload;
    // Multi-line: compared as TPCTestText.Normalize'd, the first differing
    // line shown
    procedure CheckText(const AExpected: string; const AActual: string;
      const ALabel: string);
    // AErrors holds exactly the reports AExpected names, each as
    // TPCTestMarker.ParseExpected's `<line> <marker>` ('12 ERROR SM0118@5')
    procedure CheckErrors(const AErrors: TErrors; const AExpected: array of string;
      const ALabel: string);
    procedure CheckRaises(const AProc: TProc; const AClass: ExceptClass;
      const ALabel: string);
    // The test cannot run here; AReason is printed. Call Exit after it
    procedure Skip(const AReason: string);
    procedure Fail(const AMessage: string);
    // A file in <fixture root>\<area>\fixtures\ / in the output folder, resolved and
    // proven inside the repo; '' (and a failed check) when it is not
    function Fixture(const AFileName: string): string;
    function Scratch(const AFileName: string): string;
    // A fixture bundle, <area>\fixtures\<ABundle>.txt (written by
    // scripts\testsuite\pack_probe.py): every file it holds, byte for byte,
    // into AFiles as packed path ('/' separated, e.g. 'fmt/f01_a.pcpp') ->
    // bytes. Inputs whose bytes must not move ship this way (a .pcpp under
    // repo\ carries the MPL header). False (and a failed check) when the
    // bundle cannot be read or a row is malformed
    function FixtureBundle(const ABundle: string;
      const AFiles: TDictionary<string, TBytes>): Boolean;
    // ABytes written to Scratch(AFileName), the output folder itself (no
    // subfolder): the path, or '' (and a failed check) when it cannot be
    function WriteScratch(const AFileName: string; const ABytes: TBytes): string;
    // The output folder itself (what Scratch names files in): the folder a
    // test's own build writes into, as every build does
    function ScratchFolder(): string;
    // The area's own folder (<fixture root>\<area>\, the folder that holds
    // its fixtures folder and its .pcpp tests), proven inside the repo; ''
    // (and a failed check) when it is not. For a test over the area's inputs
    function AreaFolder(): string;

    // Once around the class's tests in a run / around each test
    procedure SetupClass(); virtual;
    procedure TeardownClass(); virtual;
    procedure Setup(); virtual;
    procedure Teardown(); virtual;

    property AreaName: string read FAreaName write FAreaName;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // The suite's side
    procedure SetRoots(const ARepoRoot: string; const AFixtureRoot: string;
      const AScratchRoot: string);
    function GetAreaName(): string;
    function TestCount(): Integer;
    function TestAt(const AIndex: Integer): TPCCodeTest;
    // False = SetupClass / TeardownClass raised; AError says how
    function RunSetupClass(out AError: string): Boolean;
    function RunTeardownClass(out AError: string): Boolean;
    // Runs test AIndex for ACell; its checks and skip reason go into
    // AResult (Id, Kind and Cell are the caller's), settled
    procedure RunTest(const AIndex: Integer; const ACell: TPCTestCell;
      var AResult: TPCTestResult);
  end;

  { TPCTestCaseClass }
  TPCTestCaseClass = class of TPCTestCase;

implementation

uses
  System.StrUtils,
  System.IOUtils,
  System.NetEncoding,
  StdApp.Utils,
  StdApp.Resources;

const
  { PC_TS_BUNDLE_EXT }
  // A fixture bundle's file extension (pack_probe.py)
  PC_TS_BUNDLE_EXT = '.txt';

  { PC_TS_BUNDLE_TEXT }
  // A bundle row's kinds: escaped UTF-8 text, base64 bytes, an empty folder
  PC_TS_BUNDLE_TEXT = 't';

  { PC_TS_BUNDLE_BINARY }
  PC_TS_BUNDLE_BINARY = 'b';

  { PC_TS_BUNDLE_FOLDER }
  PC_TS_BUNDLE_FOLDER = 'd';

  { PC_TS_BUNDLE_FIELDS }
  // A row: path TAB kind TAB data
  PC_TS_BUNDLE_FIELDS = 3;

{ TPCTestCase }

constructor TPCTestCase.Create();
begin
  inherited;

  FAreaName := '';
  FTests := TList<TPCCodeTest>.Create();
  FRepoRoot := '';
  FFixtureRoot := '';
  FScratchRoot := '';
  FResult.Clear();
  FSectionTitle := '';
  FRunning := False;
end;

destructor TPCTestCase.Destroy();
begin
  FTests.Free();

  inherited;
end;

procedure TPCTestCase.DoRecord(const APassed: Boolean; const AText: string);
begin
  // A check outside RunTest has no run to land in: a broken test class
  if not FRunning then
    raise EInvalidOpException.CreateFmt(RSTstCheckOutsideRun, [FAreaName, AText]);
  FResult.AddCheck(APassed, AText, FSectionTitle);
end;

function TPCTestCase.DoGuard(const APhase: string; const AProc: TProc): Boolean;
begin
  // An exception is the phase's failed check, never the end of the run
  Result := True;
  try
    AProc();
  except
    on E: Exception do
    begin
      FResult.AddCheck(False, Format(RSTstPhaseRaised, [APhase, E.ClassName, E.Message]),
        FSectionTitle);
      Result := False;
    end;
  end;
end;

function TPCTestCase.DoInside(const APath: string; const ARoot: string): Boolean;
var
  LRoot: string;
begin
  Result := False;
  if (APath = '') or (ARoot = '') then
    Exit;
  // A root that cannot be resolved holds nothing: the caller's failed
  // check names the path
  try
    LRoot := TUtils.NormalizePath(TUtils.ResolvePath(ARoot));
  except
    on Exception do
      Exit(False);
  end;

  // Both sides in the one normalized spelling ('/', as ResolvePath gives):
  // an RTL '\' helper on a '/' path never matches. The root ends in '/' so
  // C:/a/res is not inside C:/a/re
  if not LRoot.EndsWith('/') then
    LRoot := LRoot + '/';
  Result := StartsText(LRoot, TUtils.NormalizePath(APath));
end;

function TPCTestCase.DoPathIn(const AFolder: string; const AFileName: string;
  const ALimit: string): string;
var
  LPath: string;
begin
  // AFileName resolved in AFolder; it must stay inside ALimit and the repo
  // (a '..' or a rooted name that leaves them is a failed check)
  Result := '';
  if AFolder = '' then
  begin
    DoRecord(False, Format(RSTstNoFolder, [AFileName]));
    Exit;
  end;
  try
    LPath := TUtils.ResolvePath(AFileName, AFolder);
  except
    on E: Exception do
    begin
      DoRecord(False, Format(RSTstPathFailed, [AFileName, E.Message]));
      Exit;
    end;
  end;
  if not (DoInside(LPath, ALimit) and DoInside(LPath, FRepoRoot)) then
  begin
    DoRecord(False, Format(RSTstPathOutside, [LPath, ALimit]));
    Exit;
  end;
  Result := LPath;
end;

procedure TPCTestCase.DoRegister(const ATestName: string; const AProc: TPCTestProc;
  const ADeps: array of string; const ACells: array of TPCTestCell);
var
  LTest: TPCCodeTest;
  LI: Integer;
begin
  LTest := Default(TPCCodeTest);
  LTest.TestName := ATestName;
  LTest.Proc := AProc;
  SetLength(LTest.Deps, Length(ADeps));
  for LI := 0 to High(ADeps) do
    LTest.Deps[LI] := ADeps[LI];
  SetLength(LTest.Cells, Length(ACells));
  for LI := 0 to High(ACells) do
    LTest.Cells[LI] := ACells[LI];
  FTests.Add(LTest);
end;

procedure TPCTestCase.RegisterTest(const ATestName: string; const AProc: TPCTestProc);
begin
  DoRegister(ATestName, AProc, [], []);
end;

procedure TPCTestCase.RegisterTest(const ATestName: string; const AProc: TPCTestProc;
  const ADeps: array of string);
begin
  DoRegister(ATestName, AProc, ADeps, []);
end;

procedure TPCTestCase.RegisterTest(const ATestName: string; const AProc: TPCTestProc;
  const ADeps: array of string; const ACells: array of TPCTestCell);
begin
  DoRegister(ATestName, AProc, ADeps, ACells);
end;

procedure TPCTestCase.Section(const ATitle: string);
begin
  FSectionTitle := ATitle;
end;

procedure TPCTestCase.Check(const ACondition: Boolean; const ALabel: string);
begin
  DoRecord(ACondition, ALabel);
end;

procedure TPCTestCase.Check(const ACondition: Boolean; const ALabel: string;
  const AArgs: array of const);
begin
  DoRecord(ACondition, Format(ALabel, AArgs));
end;

procedure TPCTestCase.CheckEqual(const AExpected: Int64; const AActual: Int64;
  const ALabel: string);
begin
  if AExpected = AActual then
    DoRecord(True, ALabel)
  else
    DoRecord(False, Format(RSTstWantGot, [ALabel, IntToStr(AExpected), IntToStr(AActual)]));
end;

procedure TPCTestCase.CheckEqual(const AExpected: UInt64; const AActual: UInt64;
  const ALabel: string);
begin
  if AExpected = AActual then
    DoRecord(True, ALabel)
  else
    DoRecord(False, Format(RSTstWantGot, [ALabel, UIntToStr(AExpected), UIntToStr(AActual)]));
end;

procedure TPCTestCase.CheckEqual(const AExpected: string; const AActual: string;
  const ALabel: string);
begin
  if AExpected = AActual then
    DoRecord(True, ALabel)
  else
    DoRecord(False, Format(RSTstWantGotText, [ALabel, AExpected, AActual]));
end;

procedure TPCTestCase.CheckEqual(const AExpected: Boolean; const AActual: Boolean;
  const ALabel: string);
begin
  if AExpected = AActual then
    DoRecord(True, ALabel)
  else
    DoRecord(False, Format(RSTstWantGot, [ALabel, BoolToStr(AExpected, True),
      BoolToStr(AActual, True)]));
end;

procedure TPCTestCase.CheckEqual(const AExpected: Double; const AActual: Double;
  const ATolerance: Double; const ALabel: string);
begin
  if Abs(AExpected - AActual) <= ATolerance then
    DoRecord(True, ALabel)
  else
    DoRecord(False, Format(RSTstWantGotNear, [ALabel, FloatToStr(AExpected),
      FloatToStr(ATolerance), FloatToStr(AActual)]));
end;

procedure TPCTestCase.CheckText(const AExpected: string; const AActual: string;
  const ALabel: string);
var
  LDifference: string;
begin
  LDifference := TPCTestText.FirstDifference(TPCTestText.Normalize(AExpected),
    TPCTestText.Normalize(AActual));
  if LDifference = '' then
    DoRecord(True, ALabel)
  else
    DoRecord(False, ALabel + #10 + LDifference);
end;

procedure TPCTestCase.CheckErrors(const AErrors: TErrors; const AExpected: array of string;
  const ALabel: string);
var
  LMarkers: TArray<TPCTestMarker>;
  LMarker: TPCTestMarker;
  LI: Integer;
  LUnexpected: TArray<string>;
  LMissing: TArray<string>;
  LText: string;
begin
  LMarkers := [];
  for LI := 0 to High(AExpected) do
  begin
    if not TPCTestMarker.ParseExpected(AExpected[LI], LMarker) then
    begin
      DoRecord(False, Format(RSTstBadExpected, [ALabel, AExpected[LI]]));
      Exit;
    end;
    LMarkers := LMarkers + [LMarker];
  end;

  TPCTestReports.Match(AErrors, LMarkers, False, LUnexpected, LMissing);
  if (Length(LUnexpected) = 0) and (Length(LMissing) = 0) then
  begin
    DoRecord(True, ALabel);
    Exit;
  end;

  LText := ALabel;
  if Length(LUnexpected) > 0 then
    LText := LText + #10 + RSTstUnexpectedReports + #10 + string.Join(#10, LUnexpected);
  if Length(LMissing) > 0 then
    LText := LText + #10 + RSTstMissingReports + #10 + string.Join(#10, LMissing);
  DoRecord(False, LText);
end;

procedure TPCTestCase.CheckRaises(const AProc: TProc; const AClass: ExceptClass;
  const ALabel: string);
var
  LRaised: Boolean;
  LOther: string;
begin
  LRaised := False;
  LOther := '';
  try
    AProc();
  except
    on E: Exception do
    begin
      if E is AClass then
        LRaised := True
      else
        LOther := E.ClassName + ': ' + E.Message;
    end;
  end;

  if LRaised then
    DoRecord(True, ALabel)
  else if LOther = '' then
    DoRecord(False, Format(RSTstNotRaised, [ALabel, AClass.ClassName]))
  else
    DoRecord(False, Format(RSTstRaisedOther, [ALabel, AClass.ClassName, LOther]));
end;

procedure TPCTestCase.Skip(const AReason: string);
begin
  if not FRunning then
    raise EInvalidOpException.CreateFmt(RSTstCheckOutsideRun, [FAreaName, AReason]);
  // The first reason stands
  if FResult.Reason = '' then
    FResult.Reason := AReason;
end;

procedure TPCTestCase.Fail(const AMessage: string);
begin
  DoRecord(False, AMessage);
end;

function TPCTestCase.Fixture(const AFileName: string): string;
var
  LFolder: string;
begin
  if FFixtureRoot = '' then
    Exit(DoPathIn('', AFileName, ''));

  // The area's fixtures folder (<root>/<area>/fixtures, the one folder
  // discovery never scans, so an input .pcpp there is never taken for a
  // test) in ResolvePath's '/' spelling, the one every path it is compared
  // with and printed beside uses (an RTL '\' join mixes the two)
  try
    LFolder := TUtils.ResolvePath(FAreaName + '/' + PC_TS_FIXTURES_FOLDER,
      FFixtureRoot);
  except
    on E: Exception do
    begin
      DoRecord(False, Format(RSTstPathFailed, [AFileName, E.Message]));
      Exit('');
    end;
  end;
  Result := DoPathIn(LFolder, AFileName, LFolder);
end;

function TPCTestCase.Scratch(const AFileName: string): string;
begin
  // The output folder itself, no subfolder (every test output goes there)
  Result := DoPathIn(FScratchRoot, AFileName, FScratchRoot);
end;

function TPCTestCase.DoUnescapeBundleText(const AText: string; out AOut: string): Boolean;
var
  LBuilder: TStringBuilder;
  LI: Integer;
  LNext: Char;
begin
  // pack_probe.py escapes exactly \\ \r \n \t; any other backslash pair is
  // a malformed row
  Result := True;
  LBuilder := TStringBuilder.Create();
  try
    LI := 1;
    while LI <= AText.Length do
    begin
      if AText[LI] <> '\' then
      begin
        LBuilder.Append(AText[LI]);
        Inc(LI);
        Continue;
      end;
      if LI = AText.Length then
        Exit(False);
      LNext := AText[LI + 1];
      if LNext = '\' then
        LBuilder.Append('\')
      else if LNext = 'r' then
        LBuilder.Append(#13)
      else if LNext = 'n' then
        LBuilder.Append(#10)
      else if LNext = 't' then
        LBuilder.Append(#9)
      else
        Exit(False);
      Inc(LI, 2);
    end;
    AOut := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

function TPCTestCase.FixtureBundle(const ABundle: string;
  const AFiles: TDictionary<string, TBytes>): Boolean;
var
  LPath: string;
  LText: string;
  LLines: TArray<string>;
  LLine: string;
  LIndex: Integer;
  LParts: TArray<string>;
  LDecoded: string;
  LBytes: TBytes;
begin
  Result := False;
  LPath := Fixture(ABundle + PC_TS_BUNDLE_EXT);
  if LPath = '' then
    Exit;
  try
    LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      DoRecord(False, Format(RSTstBundleUnread, [ABundle, E.Message]));
      Exit;
    end;
  end;

  // One row per file; the first line is a '#' comment
  LLines := LText.Split([#10]);
  for LIndex := 0 to High(LLines) do
  begin
    LLine := LLines[LIndex].TrimRight([#13]);
    if (LLine = '') or LLine.StartsWith('#') then
      Continue;
    LParts := LLine.Split([#9]);
    if Length(LParts) <> PC_TS_BUNDLE_FIELDS then
    begin
      DoRecord(False, Format(RSTstBundleRow, [ABundle, LIndex + 1]));
      Exit;
    end;
    if LParts[1] = PC_TS_BUNDLE_FOLDER then
      Continue;
    if LParts[1] = PC_TS_BUNDLE_TEXT then
    begin
      if not DoUnescapeBundleText(LParts[2], LDecoded) then
      begin
        DoRecord(False, Format(RSTstBundleRow, [ABundle, LIndex + 1]));
        Exit;
      end;
      AFiles.AddOrSetValue(LParts[0], TEncoding.UTF8.GetBytes(LDecoded));
    end
    else if LParts[1] = PC_TS_BUNDLE_BINARY then
    begin
      try
        LBytes := TNetEncoding.Base64.DecodeStringToBytes(LParts[2]);
      except
        on E: Exception do
        begin
          DoRecord(False, Format(RSTstBundleUnread, [ABundle, E.Message]));
          Exit;
        end;
      end;
      AFiles.AddOrSetValue(LParts[0], LBytes);
    end
    else
    begin
      DoRecord(False, Format(RSTstBundleRow, [ABundle, LIndex + 1]));
      Exit;
    end;
  end;
  Result := True;
end;

function TPCTestCase.WriteScratch(const AFileName: string; const ABytes: TBytes): string;
begin
  Result := Scratch(AFileName);
  if Result = '' then
    Exit;
  try
    TFile.WriteAllBytes(Result, ABytes);
  except
    on E: Exception do
    begin
      DoRecord(False, Format(RSTstScratchUnwritten, [AFileName, E.Message]));
      Result := '';
    end;
  end;
end;

function TPCTestCase.ScratchFolder(): string;
begin
  Result := FScratchRoot;
end;

function TPCTestCase.AreaFolder(): string;
begin
  // The area's name resolved in the fixture root, which must hold it: the
  // fixtures folder is <this>/fixtures by the suite's layout
  Result := DoPathIn(FFixtureRoot, FAreaName, FFixtureRoot);
end;

procedure TPCTestCase.SetupClass();
begin
  // Nothing by default
end;

procedure TPCTestCase.TeardownClass();
begin
  // Nothing by default
end;

procedure TPCTestCase.Setup();
begin
  // Nothing by default
end;

procedure TPCTestCase.Teardown();
begin
  // Nothing by default
end;

procedure TPCTestCase.SetRoots(const ARepoRoot: string; const AFixtureRoot: string;
  const AScratchRoot: string);
begin
  FRepoRoot := ARepoRoot;
  FFixtureRoot := AFixtureRoot;
  FScratchRoot := AScratchRoot;
end;

function TPCTestCase.GetAreaName(): string;
begin
  Result := FAreaName;
end;

function TPCTestCase.TestCount(): Integer;
begin
  Result := FTests.Count;
end;

function TPCTestCase.TestAt(const AIndex: Integer): TPCCodeTest;
begin
  Result := FTests[AIndex];
end;

function TPCTestCase.RunSetupClass(out AError: string): Boolean;
begin
  AError := '';
  Result := True;
  try
    SetupClass();
  except
    on E: Exception do
    begin
      AError := Format(RSTstPhaseRaised, [RSTstPhaseSetupClass, E.ClassName, E.Message]);
      Result := False;
    end;
  end;
end;

function TPCTestCase.RunTeardownClass(out AError: string): Boolean;
begin
  AError := '';
  Result := True;
  try
    TeardownClass();
  except
    on E: Exception do
    begin
      AError := Format(RSTstPhaseRaised, [RSTstPhaseTeardownClass, E.ClassName, E.Message]);
      Result := False;
    end;
  end;
end;

procedure TPCTestCase.RunTest(const AIndex: Integer; const ACell: TPCTestCell;
  var AResult: TPCTestResult);
var
  LTest: TPCCodeTest;
  LCell: TPCTestCell;
begin
  LTest := FTests[AIndex];
  LCell := ACell;
  FResult := AResult;
  FSectionTitle := '';
  FRunning := True;
  try
    // Setup, the test, Teardown: each guarded; Teardown only after a Setup
    // that finished
    if DoGuard(RSTstPhaseSetup,
      procedure()
      begin
        Setup();
      end) then
    begin
      DoGuard(RSTstPhaseTest,
        procedure()
        begin
          LTest.Proc(LCell);
        end);
      DoGuard(RSTstPhaseTeardown,
        procedure()
        begin
          Teardown();
        end);
    end;

    // A test that checked nothing and skipped nothing proved nothing
    if (Length(FResult.Checks) = 0) and (FResult.Reason = '') then
      FResult.AddCheck(False, RSTstNoChecks, '');
  finally
    FRunning := False;
  end;

  FResult.Settle();
  AResult := FResult;
end;

end.
