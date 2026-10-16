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
  UTestCase.SerializedDiag - Serialized diagnostics reader tests

  TTestCase suite for TPCSerializedDiagReader (PaskalCPP.SerializedDiag).
  Every fixture in tests\probe\zb14 is decoded and rendered in the python
  oracle's line format, then compared with tests\probe\zb14\expected\<name>.txt
  (written from the oracle by scripts\zb_e\a1\a1_fixtures.py). Covers real
  clang .dia files, generated and malformed files with their exact reasons,
  the note depth cap, a truncation sweep, reader reuse and a missing file.

  Dependencies: StdApp.TestCase, StdApp.Utils, StdApp.Resources,
  PaskalCPP.SerializedDiag
===============================================================================}

unit UTestCase.SerializedDiag;

interface

uses
  StdApp.TestCase;

type

  { TPCSdgFixtureKind }
  // What a fixture's expected text must say: a decode, a rejection, or
  // whatever the oracle decided (truncation sweep)
  TPCSdgFixtureKind = (fkDecodes, fkRejected, fkAny);

  { TPCSerializedDiagTests }
  TPCSerializedDiagTests = class(TTestCase)
  private
    // Shared checks
    function DoCheckFixture(const AName: string;
      const AKind: TPCSdgFixtureKind): string;
    procedure DoCheckFixtures(const ANames: array of string;
      const AKind: TPCSdgFixtureKind);
    procedure DoCheckRejected(const AName: string; const AReason: string);
    // One test per concern; Create registers each under its CLI name
    procedure DoTestReal();
    procedure DoTestGenerated();
    procedure DoTestMalformed();
    procedure DoTestDepthCap();
    procedure DoTestTruncation();
    procedure DoTestReuse();
    procedure DoTestMissingFile();
    procedure DoTestCoverage();
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.SerializedDiag;

const
  { PC_SDGT_LEVEL_TEXT }
  // clang's level spelling, as the oracle (scripts\zb_e\p_dia.py) prints it
  PC_SDGT_LEVEL_TEXT: array[TPCSerializedLevel] of string = (
    'ignored',
    'note',
    'warning',
    'error',
    'fatal error',
    'remark'
  );

  { PC_SDGT_MALFORMED_TEXT }
  // The oracle's whole text for a rejected file
  PC_SDGT_MALFORMED_TEXT = 'MALFORMED' + #10;

  { PC_SDGT_REAL }
  // .dia files clang wrote (scripts\zb_e\incl probes)
  PC_SDGT_REAL: array[0..3] of string = (
    'combo',
    'line',
    'two_a',
    'two_b'
  );

  { PC_SDGT_GENERATED }
  // Generated files that decode: the smallest file, and a note with its own
  // include chain (the chain note comes first in text order)
  PC_SDGT_GENERATED: array[0..1] of string = (
    'minimal_ok',
    'nested_chain'
  );

  { PC_SDGT_MALFORMED }
  // Rejected files, each checked for its exact reason in DoTestMalformed
  PC_SDGT_MALFORMED: array[0..8] of string = (
    'badsig',
    'trunc',
    'empty',
    'sig_only',
    'version3',
    'diag_no_record',
    'no_meta',
    'unknown_file',
    'two_records'
  );

  { PC_SDGT_DEPTH }
  // Depth-cap boundary: deepest note at 256 (kept), 257 and 300 (rejected)
  PC_SDGT_DEPTH: array[0..2] of string = (
    'deep256',
    'deep257',
    'deep300'
  );

  { PC_SDGT_CUT_PREFIX }
  // combo.dia cut every 7 bytes (scripts\zb_e\a1\a1_fixtures.py)
  PC_SDGT_CUT_PREFIX = 'combo_cut';

  { PC_SDGT_CUT_COUNT }
  // Cuts at 0, 7, .. 595
  PC_SDGT_CUT_COUNT = 86;

  { PC_SDGT_CUT_DECODED }
  // Cuts that end exactly on a top-level block boundary are complete files
  // with fewer diagnostics (the format has no end marker): 0217 and 0525
  PC_SDGT_CUT_DECODED = 2;

  { PC_SDGT_FIXTURE_COUNT }
  // Every group above plus the cuts
  PC_SDGT_FIXTURE_COUNT = 104;

function DoFixtureDir(): string;
begin
  // tests\probe\zb14; the exe sits two levels below the project root
  Result := TUtils.ResolvePath('..\..\tests\probe\zb14',
    TPath.GetDirectoryName(ParamStr(0)));
end;

function DoFixturePath(const AName: string): string;
begin
  Result := TPath.Combine(DoFixtureDir(), AName + '.dia');
end;

function DoExpectedPath(const AName: string): string;
begin
  Result := TPath.Combine(TPath.Combine(DoFixtureDir(), 'expected'), AName + '.txt');
end;

function DoReadExpected(const AName: string; out AText: string): Boolean;
begin
  // The oracle's text for fixture AName; on failure AText holds the reason
  try
    AText := TFile.ReadAllText(DoExpectedPath(AName), TEncoding.UTF8);
    Result := True;
  except
    on E: Exception do
    begin
      AText := E.Message;
      Result := False;
    end;
  end;
end;

function DoRender(const AReader: TPCSerializedDiagReader;
  const ALoaded: Boolean): string;
var
  LBuilder: TStringBuilder;
  LI: Integer;
  LJ: Integer;
  LDiag: TPCSerializedDiag;
  LNote: TPCSerializedNote;
begin
  // The oracle's line format: a D line per diagnostic, an N line per note in
  // text order, then OK; a rejected file is the single line MALFORMED
  if not ALoaded then
    Exit(PC_SDGT_MALFORMED_TEXT);

  LBuilder := TStringBuilder.Create();
  try
    for LI := 0 to AReader.DiagCount() - 1 do
    begin
      LDiag := AReader.GetDiag(LI);
      LBuilder.Append(Format('D %s %s:%s:%s [%s] {%s} %s',
        [PC_SDGT_LEVEL_TEXT[LDiag.Level], LDiag.FilePath, UIntToStr(LDiag.Line),
        UIntToStr(LDiag.Column), LDiag.FlagText, LDiag.CategoryText,
        LDiag.MessageText]));
      LBuilder.Append(#10);
      for LJ := 0 to High(LDiag.Notes) do
      begin
        LNote := LDiag.Notes[LJ];
        LBuilder.Append(Format('  N %s:%s:%s %s', [LNote.FilePath,
          UIntToStr(LNote.Line), UIntToStr(LNote.Column), LNote.MessageText]));
        LBuilder.Append(#10);
      end;
    end;
    LBuilder.Append('OK');
    LBuilder.Append(#10);
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

function DoDecode(const AName: string; out ALoaded: Boolean;
  out AFailure: string): string;
var
  LReader: TPCSerializedDiagReader;
begin
  // Fixture AName decoded by a fresh reader, rendered in the oracle's format
  LReader := TPCSerializedDiagReader.Create();
  try
    ALoaded := LReader.LoadFromFile(DoFixturePath(AName));
    AFailure := LReader.FailureText();
    Result := DoRender(LReader, ALoaded);
  finally
    LReader.Free();
  end;
end;

function DoInGroup(const AName: string; const AGroup: array of string): Boolean;
var
  LItem: string;
begin
  Result := False;
  for LItem in AGroup do
  begin
    if LItem = AName then
      Exit(True);
  end;
end;

function DoIsGrouped(const AName: string): Boolean;
begin
  // Checked by a named group or by the truncation sweep
  Result := DoInGroup(AName, PC_SDGT_REAL) or
    DoInGroup(AName, PC_SDGT_GENERATED) or
    DoInGroup(AName, PC_SDGT_MALFORMED) or
    DoInGroup(AName, PC_SDGT_DEPTH) or
    AName.StartsWith(PC_SDGT_CUT_PREFIX);
end;

{ TPCSerializedDiagTests }

constructor TPCSerializedDiagTests.Create();
begin
  inherited;

  Title := 'SerializedDiag';
  RegisterTest('real', DoTestReal);
  RegisterTest('generated', DoTestGenerated);
  RegisterTest('malformed', DoTestMalformed);
  RegisterTest('depth_cap', DoTestDepthCap);
  RegisterTest('truncation', DoTestTruncation);
  RegisterTest('reuse', DoTestReuse);
  RegisterTest('missing_file', DoTestMissingFile);
  RegisterTest('coverage', DoTestCoverage);
end;

procedure TPCSerializedDiagTests.Run();
begin
  inherited;
end;

function TPCSerializedDiagTests.DoCheckFixture(const AName: string;
  const AKind: TPCSdgFixtureKind): string;
var
  LWant: string;
  LGot: string;
  LLoaded: Boolean;
begin
  // Decodes AName and compares with the oracle; returns the failure text
  Result := '';
  if not DoReadExpected(AName, LWant) then
  begin
    Check(False, '%s: expected text unreadable: %s', [AName, LWant]);
    Exit;
  end;

  // The fixture itself must say what its group claims
  case AKind of
    fkDecodes:
      Check(LWant <> PC_SDGT_MALFORMED_TEXT, '%s: fixture expects a decode', [AName]);
    fkRejected:
      Check(LWant = PC_SDGT_MALFORMED_TEXT, '%s: fixture expects a rejection', [AName]);
    fkAny:
      ; // the truncation sweep takes whatever the oracle decided
  end;

  LGot := DoDecode(AName, LLoaded, Result);
  Check(LGot = LWant, '%s: decodes as the oracle (%d chars, want %d)',
    [AName, Length(LGot), Length(LWant)]);

  // A rejected file says why; an accepted one carries no failure text
  if LLoaded then
    Check(Result = '', '%s: no failure text ("%s")', [AName, Result])
  else
    Check(Result <> '', '%s: has a failure text', [AName]);
end;

procedure TPCSerializedDiagTests.DoCheckFixtures(const ANames: array of string;
  const AKind: TPCSdgFixtureKind);
var
  LName: string;
begin
  for LName in ANames do
    DoCheckFixture(LName, AKind);
end;

procedure TPCSerializedDiagTests.DoCheckRejected(const AName: string;
  const AReason: string);
var
  LText: string;
begin
  // Rejected, and for the reason the fixture was built to trigger
  LText := DoCheckFixture(AName, fkRejected);
  Check(LText = AReason, '%s: rejected for "%s" (got "%s")', [AName, AReason, LText]);
end;

procedure TPCSerializedDiagTests.DoTestReal();
begin
  DoCheckFixtures(PC_SDGT_REAL, fkDecodes);
end;

procedure TPCSerializedDiagTests.DoTestGenerated();
begin
  DoCheckFixtures(PC_SDGT_GENERATED, fkDecodes);
end;

procedure TPCSerializedDiagTests.DoTestMalformed();
begin
  // Bit positions are fixed by the fixtures (a1_fixtures.py, scripts\zb_e\incl)
  DoCheckRejected('badsig', RSSdgBadSignature);
  DoCheckRejected('trunc', Format(RSSdgTruncated, [2336]));
  DoCheckRejected('empty', RSSdgBadSignature);
  DoCheckRejected('sig_only', RSSdgNoVersion);
  DoCheckRejected('version3', Format(RSSdgVersion, [3]));
  DoCheckRejected('diag_no_record', Format(RSSdgNoDiagRecord, [128]));
  DoCheckRejected('no_meta', RSSdgNoVersion);
  DoCheckRejected('unknown_file', Format(RSSdgUnknownId, ['FILENAME', 7, 256]));
  DoCheckRejected('two_records', Format(RSSdgSecondDiagRecord, [320]));
end;

procedure TPCSerializedDiagTests.DoTestDepthCap();
begin
  // The deepest accepted note sits at PC_SDG_MAX_DEPTH; one deeper is rejected
  DoCheckFixture('deep256', fkDecodes);
  DoCheckRejected('deep257', Format(RSSdgTooDeep, [PC_SDG_MAX_DEPTH, 16640]));
  DoCheckRejected('deep300', Format(RSSdgTooDeep, [PC_SDG_MAX_DEPTH, 16640]));
end;

procedure TPCSerializedDiagTests.DoTestTruncation();
var
  LFiles: TArray<string>;
  LFile: string;
  LName: string;
  LWant: string;
  LGot: string;
  LLoaded: Boolean;
  LFailure: string;
  LDecoded: Integer;
  LMismatch: Integer;
  LBadReason: Integer;
  LFirstMismatch: string;
  LFirstBadReason: string;
begin
  // Every cut of combo.dia decodes exactly as the oracle says. One Check per
  // property over the whole sweep, naming the first offender.
  try
    LFiles := TDirectory.GetFiles(DoFixtureDir(), PC_SDGT_CUT_PREFIX + '*.dia');
  except
    on E: Exception do
    begin
      Check(False, 'truncation: cannot list the fixtures: %s', [E.Message]);
      Exit;
    end;
  end;
  Check(Length(LFiles) = PC_SDGT_CUT_COUNT, 'truncation: %d cuts, want %d',
    [Length(LFiles), PC_SDGT_CUT_COUNT]);

  LDecoded := 0;
  LMismatch := 0;
  LBadReason := 0;
  LFirstMismatch := '';
  LFirstBadReason := '';
  for LFile in LFiles do
  begin
    LName := TPath.GetFileNameWithoutExtension(LFile);
    if not DoReadExpected(LName, LWant) then
      LWant := '<unreadable: ' + LWant + '>';
    LGot := DoDecode(LName, LLoaded, LFailure);

    if LLoaded then
      Inc(LDecoded);

    if LGot <> LWant then
    begin
      Inc(LMismatch);
      if LFirstMismatch = '' then
        LFirstMismatch := LName;
    end;

    // Loaded = no failure text; rejected = a failure text
    if LLoaded <> (LFailure = '') then
    begin
      Inc(LBadReason);
      if LFirstBadReason = '' then
        LFirstBadReason := LName;
    end;
  end;

  Check(LMismatch = 0, 'truncation: %d cuts decode unlike the oracle (first %s)',
    [LMismatch, LFirstMismatch]);
  Check(LBadReason = 0, 'truncation: %d cuts with a wrong failure text (first %s)',
    [LBadReason, LFirstBadReason]);
  Check(LDecoded = PC_SDGT_CUT_DECODED, 'truncation: %d cuts decode, want %d',
    [LDecoded, PC_SDGT_CUT_DECODED]);
end;

procedure TPCSerializedDiagTests.DoTestReuse();
var
  LReader: TPCSerializedDiagReader;
  LCombo: string;
  LLine: string;
begin
  // One reader across loads: a rejected file in between leaves nothing behind
  if (not DoReadExpected('combo', LCombo)) or (not DoReadExpected('line', LLine)) then
  begin
    Check(False, 'reuse: expected texts unreadable');
    Exit;
  end;

  LReader := TPCSerializedDiagReader.Create();
  try
    Check(LReader.LoadFromFile(DoFixturePath('combo')), 'reuse: combo loads');
    Check(DoRender(LReader, True) = LCombo, 'reuse: combo decodes as the oracle');

    Check(not LReader.LoadFromFile(DoFixturePath('trunc')), 'reuse: trunc rejected');
    Check(LReader.DiagCount() = 0, 'reuse: rejected file keeps no diagnostics (%d)',
      [LReader.DiagCount()]);

    Check(LReader.LoadFromFile(DoFixturePath('line')), 'reuse: line loads after a rejection');
    Check(LReader.FailureText() = '', 'reuse: failure text cleared ("%s")',
      [LReader.FailureText()]);
    Check(DoRender(LReader, True) = LLine, 'reuse: line decodes as the oracle');

    Check(LReader.LoadFromFile(DoFixturePath('combo')), 'reuse: combo loads again');
    Check(DoRender(LReader, True) = LCombo, 'reuse: combo decodes the same the second time');
  finally
    LReader.Free();
  end;
end;

procedure TPCSerializedDiagTests.DoTestMissingFile();
var
  LReader: TPCSerializedDiagReader;
  LPath: string;
  LPrefix: string;
begin
  // An unreadable path is a rejection that names the file, not an exception
  LPath := DoFixturePath('no_such_fixture');
  Check(not TFile.Exists(LPath), 'missing file: fixture absent');
  LPrefix := Format(RSSdgFileRead, [LPath, '']);

  LReader := TPCSerializedDiagReader.Create();
  try
    Check(not LReader.LoadFromFile(LPath), 'missing file: rejected');
    Check(LReader.FailureText().StartsWith(LPrefix), 'missing file: failure "%s"',
      [LReader.FailureText()]);
    Check(LReader.DiagCount() = 0, 'missing file: no diagnostics (%d)',
      [LReader.DiagCount()]);
  finally
    LReader.Free();
  end;
end;

procedure TPCSerializedDiagTests.DoTestCoverage();
var
  LFixtures: TArray<string>;
  LExpected: TArray<string>;
  LFile: string;
  LName: string;
  LUngrouped: Integer;
  LNoExpected: Integer;
  LFirstUngrouped: string;
  LFirstNoExpected: string;
begin
  // Every fixture is checked by a test and has its expected text; no strays
  try
    LFixtures := TDirectory.GetFiles(DoFixtureDir(), '*.dia');
    LExpected := TDirectory.GetFiles(TPath.Combine(DoFixtureDir(), 'expected'), '*.txt');
  except
    on E: Exception do
    begin
      Check(False, 'coverage: cannot list the fixtures: %s', [E.Message]);
      Exit;
    end;
  end;
  Check(Length(LFixtures) = PC_SDGT_FIXTURE_COUNT, 'coverage: %d fixtures, want %d',
    [Length(LFixtures), PC_SDGT_FIXTURE_COUNT]);
  Check(Length(LExpected) = PC_SDGT_FIXTURE_COUNT, 'coverage: %d expected texts, want %d',
    [Length(LExpected), PC_SDGT_FIXTURE_COUNT]);

  LUngrouped := 0;
  LNoExpected := 0;
  LFirstUngrouped := '';
  LFirstNoExpected := '';
  for LFile in LFixtures do
  begin
    LName := TPath.GetFileNameWithoutExtension(LFile);
    if not DoIsGrouped(LName) then
    begin
      Inc(LUngrouped);
      if LFirstUngrouped = '' then
        LFirstUngrouped := LName;
    end;
    if not TFile.Exists(DoExpectedPath(LName)) then
    begin
      Inc(LNoExpected);
      if LFirstNoExpected = '' then
        LFirstNoExpected := LName;
    end;
  end;

  Check(LUngrouped = 0, 'coverage: %d fixtures no test checks (first %s)',
    [LUngrouped, LFirstUngrouped]);
  Check(LNoExpected = 0, 'coverage: %d fixtures without expected text (first %s)',
    [LNoExpected, LFirstNoExpected]);
end;

end.
