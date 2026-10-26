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
  PaskalCPP.TestSuite.Types - the test suite's shared vocabulary

  The words every part of the suite speaks: what kind a test is, the cell it
  runs in (target x optimize level x subsystem), the outcome of one (test,
  cell) and its checks, the report marker a test expects (`// ERROR SM0118`)
  and how test output is compared. TPCTestSpecScanner (TestSuite.Spec) reads
  specs and markers into these, TPCTestCase (TestSuite.CodeTest) reports its
  checks in them, TPCTestSuite (TestSuite) runs and prints them.

  Dependencies: StdApp.Base (TErrors, TError), StdApp.Utils (SamePath),
    StdApp.Resources (RSTst*), PaskalCPP.ZigBuild (TPCOptimizeLevel,
    TPCSubsystemType), PaskalCPP.Compiler (the optimize / subsystem
    spellings, PC_CMP_OPTIMIZE_TEXT / PC_CMP_SUBSYSTEM_TEXT)
  Notes: Records and pure functions only: nothing here reports or prints.
    A unit of its own so TestSuite.Spec, TestSuite.CodeTest and TestSuite all
    depend down on it (no sideways reference between the three).
===============================================================================}

unit PaskalCPP.TestSuite.Types;

interface

uses
  System.SysUtils,
  StdApp.Base,
  PaskalCPP.ZigBuild;

const
  { PC_TS_ID_SEPARATOR }
  // Between a test's area and its name: <area>.<name>
  PC_TS_ID_SEPARATOR = '.';

  { PC_TS_CELL_SEPARATOR }
  // Between a cell's target, optimize level and subsystem as printed
  PC_TS_CELL_SEPARATOR = '/';

type
  { TPCTestKind }
  // skRun: built, then run, its output and exit code compared. skBuild:
  // built, never run (a dll, a lib, a gui exe). skError: its markers say
  // which reports it gets and whether it builds. skTests: an exe in unit test
  // mode, run, its Results: line read. skDep: built only as another test's
  // dependency, in that test's cell, never tallied. skUnit: analyzed only (a
  // unit is never built). skCli: pcpp itself run with the spec's arguments,
  // its output and exit code compared. skManual: a file a person checks by
  // hand (the editor's LSP features, the debugger): discovered and listed,
  // never selected for a run (user 2026-10-25). skCode: a Delphi code test
  // (TPCTestCase). Every kind before skCode has a spec spelling
  TPCTestKind = (skRun, skBuild, skError, skTests, skDep, skUnit, skCli, skManual, skCode);

  { TPCTestKinds }
  TPCTestKinds = set of TPCTestKind;

const
  { PC_TS_LAST_SPEC_KIND }
  // The last kind a spec can name: loops over spec kinds run skRun to this,
  // so a new spec kind is placed before skCode and needs no loop edited
  PC_TS_LAST_SPEC_KIND = Pred(skCode);

  { PC_TS_FIXTURES_FOLDER }
  // A folder of test inputs: discovery never looks inside one, so files
  // that are no tests (imported modules, broken specs) can ship there
  PC_TS_FIXTURES_FOLDER = 'fixtures';

  { PC_TS_DIR_MARK }
  // In expect lines: the test file's folder, in '/' form
  PC_TS_DIR_MARK = '<DIR>';

  { PC_TS_OUT_MARK }
  // In expect lines: the suite's output root, in '/' form (pcpp's own build
  // lines name what it writes there: "Output: <OUT>/bin/x.exe")
  PC_TS_OUT_MARK = '<OUT>';

type
  { TPCTestStatus }
  // trSkip always carries its reason: a cell that could not run is never a pass
  TPCTestStatus = (trPass, trFail, trSkip);

  { TPCTestCell }
  // Where one run of a test happens. Passed to every call that runs or
  // builds: there is no current cell anywhere
  TPCTestCell = record
    Target: string;                 // a supported zig triple (PC_DATA_MODELS)
    OptLevel: TPCOptimizeLevel;
    Subsystem: TPCSubsystemType;

    // target/opt/subsystem, as -t / -opt / -gui spell them
    function ToText(): string;
    function SameAs(const AOther: TPCTestCell): Boolean;
    class function Make(const ATarget: string; const AOptLevel: TPCOptimizeLevel;
      const ASubsystem: TPCSubsystemType): TPCTestCell; static;
    // ToText's inverse; False = not three known parts
    class function FromText(const AText: string; out ACell: TPCTestCell): Boolean; static;
  end;

  { TPCTestCells }
  TPCTestCells = TArray<TPCTestCell>;

  { TPCTestCheck }
  // One check of one run: what was checked, whether it held, and (failed)
  // what was wanted against what came
  TPCTestCheck = record
    Passed: Boolean;
    SectionTitle: string;           // TPCTestCase.Section's title ('' = none)
    Text: string;                   // may hold several lines (#10)
  end;

  { TPCTestResult }
  // The outcome of one (test, cell)
  TPCTestResult = record
    Id: string;
    Kind: TPCTestKind;
    Cell: TPCTestCell;
    Status: TPCTestStatus;
    Reason: string;                 // trSkip: why it did not run
    DurationMs: Int64;
    Checks: TArray<TPCTestCheck>;

    procedure Clear();
    procedure AddCheck(const APassed: Boolean; const AText: string;
      const ASectionTitle: string = '');
    function FailedCount(): Integer;
    // trFail when any check failed, else trSkip when a reason is set, else trPass
    procedure Settle();
  end;

  { TPCTestMarker }
  // One report a test expects: `// ERROR SM0118`, `// WARN SM0104@12`,
  // `// HINT LX0101: text` on the line it is reported at. Form: WORD
  // CODE[@COL][: TEXT]; WORD = HINT WARN ERROR FATAL; CODE = 2 or 3 capitals
  // and 4 digits; COL = the printed (UTF-16) column; TEXT = a part of the
  // message
  TPCTestMarker = record
    Filename: string;               // resolved; '' = any file
    Line: Integer;                  // 1-based
    Severity: TErrorSeverity;
    Code: string;
    Column: Integer;                // 0 = any
    Text: string;                   // '' = any
    Hit: Boolean;

    // AErrors prints AError at the marker's place: file, line, severity,
    // code, the column (as printed, AErrors.DisplayRange) and the text
    function Matches(const AErrors: TErrors; const AError: TError): Boolean;
    function ToText(): string;
    // AText = one // comment's text, trimmed. AIsMarker False = prose (no
    // severity word then a blank); Result False = a severity word with a
    // malformed rest. Filename and Line are left for the caller
    class function Parse(const AText: string; out AIsMarker: Boolean;
      out AMarker: TPCTestMarker): Boolean; static;
    // `<line> <marker>` (TPCTestCase.CheckErrors: '12 ERROR SM0118@5'),
    // any file. False = malformed
    class function ParseExpected(const AText: string; out AMarker: TPCTestMarker): Boolean; static;
    // A diagnostic code as PaskalCPP's units spell them: 2 or 3 capitals
    // (the owning unit's family: LX PR CD SM EM ZB DB TS, the Compiler's
    // CMP), then 4 digits
    class function IsDiagnosticCode(const ACode: string): Boolean; static;
  end;

  { TPCTestReports }
  // A run's reports against the markers it expects (the // ERROR semantics):
  // each report takes the first unhit marker it matches; a report no marker
  // takes and a marker no report hits are each listed, one line each
  TPCTestReports = record
    // file(line,col) CODE message, the column as printed
    class function ReportText(const AErrors: TErrors; const AError: TError): string; static;
    // AIgnoreUnmarked: a hint or warning no marker takes is not listed (the
    // spec's `warnings allow`); an error or fatal always is
    class procedure Match(const AErrors: TErrors; var AMarkers: TArray<TPCTestMarker>;
      const AIgnoreUnmarked: Boolean; out AUnexpected: TArray<string>;
      out AMissing: TArray<string>); static;
  end;

  { TPCTestText }
  // Output comparison: line ends as #10, each line's trailing blanks
  // dropped, trailing empty lines dropped. Applied to what a test wants and
  // to what came, so neither side's trailing whitespace counts
  TPCTestText = record
    class function Normalize(const AText: string): string; static;
    // '' = equal; else the first differing line, 1-based, both sides shown.
    // Both texts already normalized
    class function FirstDifference(const AExpected: string; const AActual: string): string; static;
    // AText without terminal control sequences (CSI: ESC [ parameters
    // intermediates final, e.g. the colours ESC[31m; OSC: ESC ] text BEL or
    // ST, the window title a run program leaves). For pcpp's own output
    // (cli tests) only: a program's output is compared as it came
    class function StripTerminalCodes(const AText: string): string; static;
    // AText (lines ending in #10) without pcpp's build progress lines
    // (RSPcCliBuildProgress: 'Building <name>... <N>s', printed every few
    // seconds zig is quiet, so their count depends on the machine and the
    // zig cache). For pcpp's own output (cli tests) only
    class function DropBuildProgress(const AText: string): string; static;
  end;

{ PCTestFolderOf }
// The folder APath sits in, in '/' form, without a trailing separator; ''
// when APath has no separator. Cuts at the last '/' or '\': suite paths come
// from TUtils.ResolvePath ('/') or from RTL folder walks (joined with '\'),
// and every place the suite takes a folder (a spec's relative paths, <DIR>,
// a program's run folder) uses this one rule
function PCTestFolderOf(const APath: string): string;

implementation

uses
  System.Math,
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.Compiler;

type
  { TPCTestSeverityWord }
  TPCTestSeverityWord = record
    Spelling: string;
    Severity: TErrorSeverity;
  end;

const
  { PC_TS_SEVERITY_WORDS }
  // The marker words, as @message's severities (BNF sec 2)
  PC_TS_SEVERITY_WORDS: array[0..3] of TPCTestSeverityWord = (
    (Spelling: 'HINT';  Severity: esHint),
    (Spelling: 'WARN';  Severity: esWarning),
    (Spelling: 'ERROR'; Severity: esError),
    (Spelling: 'FATAL'; Severity: esFatal)
  );

  { PC_TS_COLUMN_MARK }
  PC_TS_COLUMN_MARK = '@';

  { PC_TS_TEXT_MARK }
  PC_TS_TEXT_MARK = ':';

{ DoIsDigits }
function DoIsDigits(const AText: string): Boolean;
var
  LC: Char;
begin
  Result := AText <> '';
  for LC in AText do
  begin
    if not CharInSet(LC, ['0'..'9']) then
      Exit(False);
  end;
end;

{ DoSkipCsi }
// AIndex at the ESC of an ESC '[': moves AIndex past the whole sequence and
// returns ''. Without a final byte (the text ends, or another character
// comes) it is no control sequence: its text so far is returned as is and
// AIndex stops at the character after it, read again as ordinary text
function DoSkipCsi(const AText: string; var AIndex: Integer): string;
var
  LStart: Integer;
  LLength: Integer;
begin
  LStart := AIndex;
  LLength := AText.Length;
  AIndex := AIndex + 2;
  while (AIndex <= LLength) and CharInSet(AText[AIndex], [#$30..#$3F]) do
    Inc(AIndex);
  while (AIndex <= LLength) and CharInSet(AText[AIndex], [#$20..#$2F]) do
    Inc(AIndex);
  if (AIndex <= LLength) and CharInSet(AText[AIndex], [#$40..#$7E]) then
  begin
    Inc(AIndex);
    Exit('');
  end;
  // No final byte: keep what was read; a non-final character after the
  // parameters is no CSI either and is read again as ordinary text
  Result := Copy(AText, LStart, AIndex - LStart);
end;

{ DoSkipOsc }
// AIndex at the ESC of an ESC ']' (ECMA-48 OSC: the window title a console
// program leaves): moves AIndex past the whole string through its BEL or ST
// (ESC '\') and returns ''. Without a terminator (the text ends, or another
// control character comes: a line break) it is no control string: its text
// so far is returned as is and AIndex stops at that character, read again
// as ordinary text
function DoSkipOsc(const AText: string; var AIndex: Integer): string;
var
  LStart: Integer;
  LLength: Integer;
begin
  LStart := AIndex;
  LLength := AText.Length;
  AIndex := AIndex + 2;
  while AIndex <= LLength do
  begin
    if AText[AIndex] = #7 then
    begin
      Inc(AIndex);
      Exit('');
    end;
    if (AText[AIndex] = #27) and (AIndex < LLength) and (AText[AIndex + 1] = '\') then
    begin
      AIndex := AIndex + 2;
      Exit('');
    end;
    if AText[AIndex] < #$20 then
      Break;
    Inc(AIndex);
  end;
  Result := Copy(AText, LStart, AIndex - LStart);
end;

{ DoIsBuildProgress }
// ALine is one of pcpp's build progress lines: RSPcCliBuildProgress with a
// project name and a whole number of seconds. The format is read at its
// '%s' and '%d', so a reworded message still matches; the name runs to the
// last text between them (a name may hold it too), the seconds are digits
function DoIsBuildProgress(const ALine: string): Boolean;
var
  LFormat: string;
  LNameAt: Integer;
  LSecondsAt: Integer;
  LHead: string;
  LMiddle: string;
  LTail: string;
  LRest: string;
  LCut: Integer;
  LDigits: string;
  LChar: Char;
begin
  Result := False;
  LFormat := RSPcCliBuildProgress;
  LNameAt := LFormat.IndexOf('%s');
  LSecondsAt := LFormat.IndexOf('%d');
  if (LNameAt < 0) or (LSecondsAt <= LNameAt) then
    Exit;
  LHead := LFormat.Substring(0, LNameAt);
  LMiddle := LFormat.Substring(LNameAt + 2, LSecondsAt - LNameAt - 2);
  LTail := LFormat.Substring(LSecondsAt + 2);
  if (ALine.Length < LHead.Length + LTail.Length) or (not ALine.StartsWith(LHead)) or
    (not ALine.EndsWith(LTail)) then
    Exit;
  LRest := ALine.Substring(LHead.Length, ALine.Length - LHead.Length - LTail.Length);
  LCut := LRest.LastIndexOf(LMiddle);
  // An empty name is no progress line
  if LCut < 1 then
    Exit;
  LDigits := LRest.Substring(LCut + LMiddle.Length);
  if LDigits = '' then
    Exit;
  for LChar in LDigits do
  begin
    if not CharInSet(LChar, ['0'..'9']) then
      Exit;
  end;
  Result := True;
end;

{ PCTestFolderOf }
function PCTestFolderOf(const APath: string): string;
var
  LSlash: Integer;
begin
  // string.LastDelimiter is 0-based, -1 = no separator
  LSlash := APath.LastDelimiter('/\');
  if LSlash < 0 then
    Exit('');
  Result := APath.Substring(0, LSlash).Replace('\', '/');
end;

{ TPCTestCell }

function TPCTestCell.ToText(): string;
begin
  Result := Target + PC_TS_CELL_SEPARATOR + PC_CMP_OPTIMIZE_TEXT[OptLevel] +
    PC_TS_CELL_SEPARATOR + PC_CMP_SUBSYSTEM_TEXT[Subsystem];
end;

function TPCTestCell.SameAs(const AOther: TPCTestCell): Boolean;
begin
  Result := (Target = AOther.Target) and (OptLevel = AOther.OptLevel) and
    (Subsystem = AOther.Subsystem);
end;

class function TPCTestCell.Make(const ATarget: string; const AOptLevel: TPCOptimizeLevel;
  const ASubsystem: TPCSubsystemType): TPCTestCell;
begin
  Result.Target := ATarget;
  Result.OptLevel := AOptLevel;
  Result.Subsystem := ASubsystem;
end;

class function TPCTestCell.FromText(const AText: string; out ACell: TPCTestCell): Boolean;
var
  LParts: TArray<string>;
begin
  ACell := Default(TPCTestCell);
  LParts := AText.Split([PC_TS_CELL_SEPARATOR]);
  if Length(LParts) <> 3 then
    Exit(False);
  ACell.Target := LParts[0];
  Result := (ACell.Target <> '') and
    TPCCompiler.FindOptimizeLevel(LParts[1], ACell.OptLevel) and
    TPCCompiler.FindSubsystem(LParts[2], ACell.Subsystem);
end;

{ TPCTestResult }

procedure TPCTestResult.Clear();
begin
  Self := Default(TPCTestResult);
end;

procedure TPCTestResult.AddCheck(const APassed: Boolean; const AText: string;
  const ASectionTitle: string);
var
  LCheck: TPCTestCheck;
begin
  LCheck.Passed := APassed;
  LCheck.SectionTitle := ASectionTitle;
  LCheck.Text := AText;
  Checks := Checks + [LCheck];
end;

function TPCTestResult.FailedCount(): Integer;
var
  LCheck: TPCTestCheck;
begin
  Result := 0;
  for LCheck in Checks do
  begin
    if not LCheck.Passed then
      Inc(Result);
  end;
end;

procedure TPCTestResult.Settle();
begin
  if FailedCount() > 0 then
    Status := trFail
  else if Reason <> '' then
    Status := trSkip
  else
    Status := trPass;
end;

{ TPCTestMarker }

function TPCTestMarker.Matches(const AErrors: TErrors; const AError: TError): Boolean;
var
  LRange: TSourceRange;
begin
  LRange := AErrors.DisplayRange(AError.Range);
  Result := ((Filename = '') or TUtils.SamePath(Filename, AError.Range.Filename)) and
    (UInt64(Line) = AError.Range.StartLine) and
    (Severity = AError.Severity) and
    (Code = AError.Code) and
    ((Column = 0) or (UInt64(Column) = LRange.StartColumn)) and
    ((Text = '') or AError.Message.Contains(Text));
end;

function TPCTestMarker.ToText(): string;
var
  LI: Integer;
  LWord: string;
begin
  LWord := '';
  for LI := Low(PC_TS_SEVERITY_WORDS) to High(PC_TS_SEVERITY_WORDS) do
  begin
    if PC_TS_SEVERITY_WORDS[LI].Severity = Severity then
      LWord := PC_TS_SEVERITY_WORDS[LI].Spelling;
  end;
  Result := Format(RSTstMarkerText, [Filename, Line, LWord, Code]);
  if Column > 0 then
    Result := Result + PC_TS_COLUMN_MARK + IntToStr(Column);
  if Text <> '' then
    Result := Result + PC_TS_TEXT_MARK + ' ' + Text;
end;

class function TPCTestMarker.IsDiagnosticCode(const ACode: string): Boolean;
var
  LLetters: Integer;
begin
  Result := False;
  LLetters := 0;
  while (LLetters < ACode.Length) and CharInSet(ACode.Chars[LLetters], ['A'..'Z']) do
    Inc(LLetters);
  if (LLetters < 2) or (LLetters > 3) then
    Exit;
  Result := (ACode.Length = LLetters + 4) and DoIsDigits(ACode.Substring(LLetters));
end;

class function TPCTestMarker.Parse(const AText: string; out AIsMarker: Boolean;
  out AMarker: TPCTestMarker): Boolean;
var
  LI: Integer;
  LRest: string;
  LEnd: Integer;
  LCol: string;
begin
  Result := True;
  AIsMarker := False;
  AMarker := Default(TPCTestMarker);

  LRest := '';
  for LI := Low(PC_TS_SEVERITY_WORDS) to High(PC_TS_SEVERITY_WORDS) do
  begin
    if AText.StartsWith(PC_TS_SEVERITY_WORDS[LI].Spelling + ' ') then
    begin
      AIsMarker := True;
      AMarker.Severity := PC_TS_SEVERITY_WORDS[LI].Severity;
      LRest := AText.Substring(PC_TS_SEVERITY_WORDS[LI].Spelling.Length).Trim();
      Break;
    end;
  end;
  if not AIsMarker then
    Exit;

  // The code: up to '@', ':' or a blank
  LEnd := 0;
  while (LEnd < LRest.Length) and (not CharInSet(LRest.Chars[LEnd], ['@', ':', ' '])) do
    Inc(LEnd);
  AMarker.Code := LRest.Substring(0, LEnd);
  if not IsDiagnosticCode(AMarker.Code) then
    Exit(False);
  LRest := LRest.Substring(LEnd);

  // Optional @column (as printed: UTF-16)
  if LRest.StartsWith(PC_TS_COLUMN_MARK) then
  begin
    LEnd := 1;
    while (LEnd < LRest.Length) and CharInSet(LRest.Chars[LEnd], ['0'..'9']) do
      Inc(LEnd);
    LCol := LRest.Substring(1, LEnd - 1);
    if (not DoIsDigits(LCol)) or (not TryStrToInt(LCol, AMarker.Column)) or (AMarker.Column < 1) then
      Exit(False);
    LRest := LRest.Substring(LEnd);
  end;

  // Optional ': text' (a part of the message); nothing else may follow
  LRest := LRest.Trim();
  if LRest.StartsWith(PC_TS_TEXT_MARK) then
  begin
    AMarker.Text := LRest.Substring(1).Trim();
    if AMarker.Text = '' then
      Exit(False);
  end
  else if LRest <> '' then
    Exit(False);
end;

class function TPCTestMarker.ParseExpected(const AText: string; out AMarker: TPCTestMarker): Boolean;
var
  LText: string;
  LEnd: Integer;
  LLine: Integer;
  LIsMarker: Boolean;
begin
  AMarker := Default(TPCTestMarker);
  LText := AText.Trim();

  // The line: digits, then one blank, then the marker
  LEnd := 0;
  while (LEnd < LText.Length) and CharInSet(LText.Chars[LEnd], ['0'..'9']) do
    Inc(LEnd);
  if (LEnd = 0) or (LEnd >= LText.Length) or (LText.Chars[LEnd] <> ' ') then
    Exit(False);
  if (not TryStrToInt(LText.Substring(0, LEnd), LLine)) or (LLine < 1) then
    Exit(False);

  Result := Parse(LText.Substring(LEnd).Trim(), LIsMarker, AMarker) and LIsMarker;
  AMarker.Filename := '';
  AMarker.Line := LLine;
end;

{ TPCTestReports }

class function TPCTestReports.ReportText(const AErrors: TErrors; const AError: TError): string;
var
  LRange: TSourceRange;
begin
  LRange := AErrors.DisplayRange(AError.Range);
  Result := Format(RSTstReportText, [LRange.Filename, LRange.StartLine, LRange.StartColumn,
    AError.Code, AError.Message]);
end;

class procedure TPCTestReports.Match(const AErrors: TErrors; var AMarkers: TArray<TPCTestMarker>;
  const AIgnoreUnmarked: Boolean; out AUnexpected: TArray<string>;
  out AMissing: TArray<string>);
var
  LError: TError;
  LI: Integer;
  LFound: Integer;
begin
  AUnexpected := [];
  AMissing := [];

  for LError in AErrors.GetItems() do
  begin
    LFound := -1;
    for LI := 0 to High(AMarkers) do
    begin
      if (not AMarkers[LI].Hit) and AMarkers[LI].Matches(AErrors, LError) then
      begin
        LFound := LI;
        Break;
      end;
    end;

    if LFound >= 0 then
      AMarkers[LFound].Hit := True
    else if not (AIgnoreUnmarked and (LError.Severity in [esHint, esWarning])) then
      AUnexpected := AUnexpected + [ReportText(AErrors, LError)];
  end;

  for LI := 0 to High(AMarkers) do
  begin
    if not AMarkers[LI].Hit then
      AMissing := AMissing + [AMarkers[LI].ToText()];
  end;
end;

{ TPCTestText }

class function TPCTestText.Normalize(const AText: string): string;
var
  LLines: TArray<string>;
  LI: Integer;
  LCount: Integer;
begin
  LLines := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  for LI := 0 to High(LLines) do
    LLines[LI] := LLines[LI].TrimRight();
  LCount := Length(LLines);
  while (LCount > 0) and (LLines[LCount - 1] = '') do
    Dec(LCount);
  Result := string.Join(#10, LLines, 0, LCount);
end;

class function TPCTestText.FirstDifference(const AExpected: string; const AActual: string): string;
var
  LWant: TArray<string>;
  LGot: TArray<string>;
  LI: Integer;
  LWantLine: string;
  LGotLine: string;
begin
  Result := '';
  if AExpected = AActual then
    Exit;

  LWant := AExpected.Split([#10]);
  LGot := AActual.Split([#10]);
  for LI := 0 to Max(High(LWant), High(LGot)) do
  begin
    // A side that has no line here shows as RSTstNoLine
    if LI <= High(LWant) then
      LWantLine := LWant[LI]
    else
      LWantLine := RSTstNoLine;
    if LI <= High(LGot) then
      LGotLine := LGot[LI]
    else
      LGotLine := RSTstNoLine;
    if (LI > High(LWant)) or (LI > High(LGot)) or (LWant[LI] <> LGot[LI]) then
      Exit(Format(RSTstLineDiffers, [LI + 1, LWantLine, LGotLine]));
  end;
end;

class function TPCTestText.StripTerminalCodes(const AText: string): string;
var
  LBuilder: TStringBuilder;
  LI: Integer;
  LLength: Integer;
begin
  // ECMA-48 CSI: ESC '[', parameter bytes $30-$3F, intermediate bytes
  // $20-$2F, one final byte $40-$7E; OSC: ESC ']', its text, BEL or ST
  // (DoSkipOsc). An ESC that starts neither is kept, as is a sequence cut
  // off at the end of the text (kept as it came)
  LLength := AText.Length;
  LBuilder := TStringBuilder.Create(LLength);
  try
    LI := 1;
    while LI <= LLength do
    begin
      if (AText[LI] = #27) and (LI < LLength) and (AText[LI + 1] = '[') then
      begin
        LBuilder.Append(DoSkipCsi(AText, LI));
        Continue;
      end;
      if (AText[LI] = #27) and (LI < LLength) and (AText[LI + 1] = ']') then
      begin
        LBuilder.Append(DoSkipOsc(AText, LI));
        Continue;
      end;
      LBuilder.Append(AText[LI]);
      Inc(LI);
    end;
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

class function TPCTestText.DropBuildProgress(const AText: string): string;
var
  LLines: TArray<string>;
  LKept: TArray<string>;
  LLine: string;
begin
  // Line by line (#10, a #13 before it ignored by the match): every other
  // line kept in its order
  LLines := AText.Split([#10]);
  LKept := nil;
  for LLine in LLines do
  begin
    if not DoIsBuildProgress(LLine.TrimRight([#13])) then
      LKept := LKept + [LLine];
  end;
  Result := string.Join(#10, LKept);
end;

end.
