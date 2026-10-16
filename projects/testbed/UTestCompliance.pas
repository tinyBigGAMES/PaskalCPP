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
  UTestCompliance - the compliance tester's engine

  PLAN-COMPLIANCE T1 (D5, D7-D11). Pure reads for UTestCase.Compliance: a
  res\tests file's header directives (EXPECT: / EXPECT windows: / EXPECT
  linux: / EXITCODE:), the `// ERROR|WARN|HINT|FATAL <code>[@col][: text]`
  markers of a file (outside its leading header comment), and the files a
  build read, from the AST (the main file, every module the parser loaded
  through the imports, every @addsourcefile of those modules). No Check, no
  compiler run here.

  Dependencies: StdApp.Base, StdApp.Utils, PaskalCPP.Common, PaskalCPP.AST
===============================================================================}

unit UTestCompliance;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.AST;

const
  { PC_CMPL_TARGET_WINDOWS }
  PC_CMPL_TARGET_WINDOWS = 'x86_64-windows-gnu';

  { PC_CMPL_TARGET_LINUX }
  PC_CMPL_TARGET_LINUX = 'x86_64-linux-gnu';

  { PC_CMPL_TARGETS }
  // The official targets in run order (DESIGN.md sec 7); a registration's
  // OutputDirs follow this order
  PC_CMPL_TARGETS: array[0..1] of string = (PC_CMPL_TARGET_WINDOWS, PC_CMPL_TARGET_LINUX);

  { PC_CMPL_SOURCE_EXT }
  PC_CMPL_SOURCE_EXT = '.pcpp';

  { PC_CMPL_DIR_TOKEN }
  // In an EXPECT block: the folder of the files under test (res\tests) as the
  // compiler spells it (TUtils.ResolvePath), so a line naming a source path (a
  // test runner failure: '<DIR>/test_asserts.pcpp:12: ...') is exact on every
  // machine and target (PLAN-COMPLIANCE F8)
  PC_CMPL_DIR_TOKEN = '<DIR>';

  { PC_CMPL_CODEPAGE_UTF8 }
  // Windows' UTF-8 code page (CP_UTF8): DoReadLines' lenient decoder
  PC_CMPL_CODEPAGE_UTF8 = 65001;

  { PC_CMPL_PCPP_EXE }
  // cmCli runs this program, beside testbed.exe (repo\bin)
  PC_CMPL_PCPP_EXE = 'pcpp.exe';

  { PC_CMPL_VERSION_TOKEN }
  // In a cmCli EXPECT block: the compiler's version, major.minor.patch
  // (PaskalCPP.Common PC_*_VERSION), the one banner text a release changes
  PC_CMPL_VERSION_TOKEN = '<VERSION>';

type
  { TPCComplianceMode }
  TPCComplianceMode = (
    cmCheck,   // Prepare only: parse, analyse, emit, configure; zig never runs
    cmBuild,   // Prepare + Build: the toolchain's reports count too
    cmRun,     // + the artifact runs over pipes: output and exit code compared
    cmCli      // repo\bin\pcpp.exe itself runs with Args (cwd repo\bin), once: its
               // output (colour codes stripped, <VERSION> / <DIR> tokens) and exit code
  );

  { TPCComplianceEntry }
  // One registered res\tests file (UTestCase.Compliance registers them in code:
  // the one list, no file scan, no tests.json)
  TPCComplianceEntry = record
    Stem: string;                 // file name without .pcpp = the test's name
    Category: string;             // its prefix area (mod, dir, ..., exe)
    Mode: TPCComplianceMode;
    Deps: TArray<string>;         // stems built first, same target, own folders
    Targets: TArray<string>;      // [] = both official targets
    OutputDirs: TArray<string>;   // [] = %TEMP%\pcpp-cmpl\<stem>\<target>; else one
                                  // per PC_CMPL_TARGETS row, relative to repo\bin
    Args: string;                 // the program's arguments, raw (D4); cmCli: pcpp's
    Stdin: string;                // cmRun: a file in res\tests that is the program's
                                  // standard input ('' = none: NUL), as '< file'
  end;

  { TPCComplianceMarker }
  // `// ERROR SM0118`, `// WARN SM0104@12`, `// HINT LX0101: text`: one report
  // expected on the marker's own line
  TPCComplianceMarker = record
    Filename: string;             // resolved (TUtils.ResolvePath)
    Line: Integer;                // 1-based, the marker's own line
    Severity: TErrorSeverity;
    Code: string;
    Column: Integer;              // 0 = any; else the printed (UTF-16) column
    Text: string;                 // '' = any; else a part of the message
    Hit: Boolean;
  end;

  { TPCComplianceSpec }
  // A header's directives (tester.md "Directive syntax", D10)
  TPCComplianceSpec = record
    HasExpect: Boolean;
    Expect: string;               // lines joined with #10, no trailing #10
    HasExpectWindows: Boolean;
    ExpectWindows: string;
    HasExpectLinux: Boolean;
    ExpectLinux: string;
    ExitCode: Integer;            // 0 when EXITCODE is absent
    // The block for ATarget: its own block, else the shared one; False = none
    function ExpectFor(const ATarget: string; out AText: string): Boolean;
    function HasAnyExpect(): Boolean;
  end;

  { TPCCompliance }
  TPCCompliance = record
  public
    // repo\bin\res\tests (testbed.exe lives in repo\bin)
    class function TestsDir(): string; static;
    // The header's EXPECT / EXITCODE directives; False + AReason when malformed
    class function ReadSpec(const AFile: string; out ASpec: TPCComplianceSpec;
      out AReason: string): Boolean; static;
    // Every marker of AFile into AMarkers; False + AReason when one is malformed
    class function ReadMarkers(const AFile: string;
      const AMarkers: TList<TPCComplianceMarker>; out AReason: string): Boolean; static;
    // The files a build read (D7): AMainFile, every module the parser loaded,
    // every @addsourcefile of those modules; each once (TUtils.SamePath)
    class function BuildFiles(const AMainFile: string; const AMain: TPCModule): TArray<string>; static;
    // CRLF / CR -> LF, trailing line ends dropped
    class function NormalizeOutput(const AText: string): string; static;
  end;

implementation

uses
  System.IOUtils,
  StdApp.Utils,
  PaskalCPP.Common;

const
  { PC_CMPL_EXPECT }
  PC_CMPL_EXPECT = 'EXPECT:';
  { PC_CMPL_EXPECT_WINDOWS }
  PC_CMPL_EXPECT_WINDOWS = 'EXPECT windows:';
  { PC_CMPL_EXPECT_LINUX }
  PC_CMPL_EXPECT_LINUX = 'EXPECT linux:';
  { PC_CMPL_EXPECT_WORD }
  PC_CMPL_EXPECT_WORD = 'EXPECT';
  { PC_CMPL_EXITCODE }
  PC_CMPL_EXITCODE = 'EXITCODE:';
  { PC_CMPL_EXITCODE_WORD }
  PC_CMPL_EXITCODE_WORD = 'EXITCODE';
  { PC_CMPL_HEADER_OPEN }
  PC_CMPL_HEADER_OPEN = '/*';
  { PC_CMPL_HEADER_CLOSE }
  PC_CMPL_HEADER_CLOSE = '*/';
  { PC_CMPL_COMMENT }
  PC_CMPL_COMMENT = '//';

type
  { TPCCmplSeverityWord }
  TPCCmplSeverityWord = record
    Spelling: string;
    Severity: TErrorSeverity;
  end;

const
  { PC_CMPL_SEVERITY_WORDS }
  // The marker words, as @message's severities (BNF sec 2)
  PC_CMPL_SEVERITY_WORDS: array[0..3] of TPCCmplSeverityWord = (
    (Spelling: 'HINT';  Severity: esHint),
    (Spelling: 'WARN';  Severity: esWarning),
    (Spelling: 'ERROR'; Severity: esError),
    (Spelling: 'FATAL'; Severity: esFatal)
  );

{ TPCComplianceSpec }

function TPCComplianceSpec.ExpectFor(const ATarget: string; out AText: string): Boolean;
begin
  AText := '';
  Result := True;
  if (ATarget = PC_CMPL_TARGET_WINDOWS) and HasExpectWindows then
    AText := ExpectWindows
  else if (ATarget = PC_CMPL_TARGET_LINUX) and HasExpectLinux then
    AText := ExpectLinux
  else if HasExpect then
    AText := Expect
  else
    Result := False;
end;

function TPCComplianceSpec.HasAnyExpect(): Boolean;
begin
  Result := HasExpect or HasExpectWindows or HasExpectLinux;
end;

{ DoIndent }
// Leading blanks (space or tab, one each)
function DoIndent(const ALine: string): Integer;
begin
  Result := 0;
  while (Result < ALine.Length) and CharInSet(ALine.Chars[Result], [' ', #9]) do
    Inc(Result);
end;

{ DoHeaderEnd }
// Lines [0..Result) are the leading header comment: the file starts with /*
// and the comment closes on line Result - 1; 0 = no header
function DoHeaderEnd(const ALines: TArray<string>): Integer;
var
  LI: Integer;
begin
  Result := 0;
  if (Length(ALines) = 0) or (not ALines[0].TrimLeft().StartsWith(PC_CMPL_HEADER_OPEN)) then
    Exit;
  for LI := 0 to High(ALines) do
  begin
    if ALines[LI].Contains(PC_CMPL_HEADER_CLOSE) then
      Exit(LI + 1);
  end;
  // An unclosed header is the lexer's error (LX0003); the whole file is header
  Result := Length(ALines);
end;

{ DoReadLines }
function DoReadLines(const AFile: string; out ALines: TArray<string>; out AReason: string): Boolean;
var
  LEncoding: TEncoding;
begin
  Result := False;
  AReason := '';
  // UTF-8 that never refuses a byte (MultiByteToWideChar flags 0: an invalid
  // byte reads as U+FFFD, one column, as the compiler prints it): a file whose
  // point is a byte that is no UTF-8 (lex_identifiers_err_utf8, LX0011) is
  // still read for its header and markers (F9; TEncoding.UTF8 raised)
  LEncoding := TMBCSEncoding.Create(PC_CMPL_CODEPAGE_UTF8, 0, 0);
  try
    try
      ALines := TFile.ReadAllLines(AFile, LEncoding);
      Result := True;
    except
      on E: Exception do
        AReason := Format('%s cannot be read: %s', [AFile, E.Message]);
    end;
  finally
    LEncoding.Free();
  end;
end;

{ DoReadBlock }
// The lines after AIndex indented deeper than ADirectiveIndent, up to AEnd:
// the block indent is the first such line's; an empty line inside is kept,
// empty lines at the end dropped. AIndex ends on the last line read
function DoReadBlock(const ALines: TArray<string>; var AIndex: Integer;
  const AEnd: Integer; const ADirectiveIndent: Integer; out AText: string): Boolean;
var
  LBlockIndent: Integer;
  LLine: string;
  LParts: TList<string>;
begin
  Result := False;
  AText := '';
  LBlockIndent := -1;
  LParts := TList<string>.Create();
  try
    while AIndex + 1 < AEnd do
    begin
      LLine := ALines[AIndex + 1];
      if LLine.Contains(PC_CMPL_HEADER_CLOSE) then
        Break;
      if LLine.Trim() = '' then
      begin
        // Kept only when a block line follows (trailing ones dropped below)
        if LBlockIndent >= 0 then
          LParts.Add('');
        Inc(AIndex);
        Continue;
      end;
      if LBlockIndent < 0 then
      begin
        if DoIndent(LLine) <= ADirectiveIndent then
          Break;
        LBlockIndent := DoIndent(LLine);
      end
      else if DoIndent(LLine) < LBlockIndent then
        Break;
      LParts.Add(LLine.Substring(LBlockIndent));
      Inc(AIndex);
    end;

    while (LParts.Count > 0) and (LParts[LParts.Count - 1] = '') do
      LParts.Delete(LParts.Count - 1);
    // An EXPECT with no lines under it is malformed (an empty output has no block)
    if LParts.Count = 0 then
      Exit;
    AText := string.Join(#10, LParts.ToArray());
    Result := True;
  finally
    LParts.Free();
  end;
end;

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

{ DoParseMarker }
// AText = one // comment's text, trimmed. AIsMarker False = prose (not a
// severity word followed by a blank); Result False = a severity word with a
// malformed rest (D10). Form: WORD CODE[@COL][: TEXT], CODE = 2 capitals + 4 digits
function DoParseMarker(const AText: string; out AIsMarker: Boolean;
  out AMarker: TPCComplianceMarker): Boolean;
var
  LI: Integer;
  LRest: string;
  LEnd: Integer;
  LCol: string;
begin
  Result := True;
  AIsMarker := False;
  AMarker := Default(TPCComplianceMarker);

  LRest := '';
  for LI := Low(PC_CMPL_SEVERITY_WORDS) to High(PC_CMPL_SEVERITY_WORDS) do
  begin
    if AText.StartsWith(PC_CMPL_SEVERITY_WORDS[LI].Spelling + ' ') then
    begin
      AIsMarker := True;
      AMarker.Severity := PC_CMPL_SEVERITY_WORDS[LI].Severity;
      LRest := AText.Substring(PC_CMPL_SEVERITY_WORDS[LI].Spelling.Length).Trim();
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
  if (AMarker.Code.Length <> 6) or
     (not CharInSet(AMarker.Code.Chars[0], ['A'..'Z'])) or
     (not CharInSet(AMarker.Code.Chars[1], ['A'..'Z'])) or
     (not DoIsDigits(AMarker.Code.Substring(2))) then
    Exit(False);
  LRest := LRest.Substring(LEnd);

  // Optional @column (as printed: UTF-16)
  if LRest.StartsWith('@') then
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
  if LRest.StartsWith(':') then
  begin
    AMarker.Text := LRest.Substring(1).Trim();
    if AMarker.Text = '' then
      Exit(False);
  end
  else if LRest <> '' then
    Exit(False);
end;

{ DoAddFile }
// A file that does not exist was never read (a break step naming a missing
// or wrong file): it holds no markers. FileExists does not raise
procedure DoAddFile(const AFiles: TList<string>; const AFile: string);
var
  LFile: string;
begin
  if (AFile = '') or (not FileExists(AFile)) then
    Exit;
  for LFile in AFiles do
  begin
    if TUtils.SamePath(LFile, AFile) then
      Exit;
  end;
  AFiles.Add(AFile);
end;

{ TPCCompliance }

class function TPCCompliance.TestsDir(): string;
begin
  Result := TUtils.ResolvePath('res\tests', TPath.GetDirectoryName(ParamStr(0)));
end;

class function TPCCompliance.ReadSpec(const AFile: string; out ASpec: TPCComplianceSpec;
  out AReason: string): Boolean;
var
  LLines: TArray<string>;
  LEnd: Integer;
  LI: Integer;
  LTrim: string;
  LIndent: Integer;
  LValue: string;
  LHasExit: Boolean;
begin
  Result := False;
  ASpec := Default(TPCComplianceSpec);
  if not DoReadLines(AFile, LLines, AReason) then
    Exit;

  LHasExit := False;
  LEnd := DoHeaderEnd(LLines);
  LI := 0;
  while LI < LEnd do
  begin
    LTrim := LLines[LI].Trim();
    LIndent := DoIndent(LLines[LI]);

    if LTrim = PC_CMPL_EXPECT then
    begin
      if ASpec.HasExpect or (not DoReadBlock(LLines, LI, LEnd, LIndent, ASpec.Expect)) then
      begin
        AReason := Format('%s(%d): a second or empty EXPECT:', [AFile, LI + 1]);
        Exit;
      end;
      ASpec.HasExpect := True;
    end
    else if LTrim = PC_CMPL_EXPECT_WINDOWS then
    begin
      if ASpec.HasExpectWindows or (not DoReadBlock(LLines, LI, LEnd, LIndent, ASpec.ExpectWindows)) then
      begin
        AReason := Format('%s(%d): a second or empty EXPECT windows:', [AFile, LI + 1]);
        Exit;
      end;
      ASpec.HasExpectWindows := True;
    end
    else if LTrim = PC_CMPL_EXPECT_LINUX then
    begin
      if ASpec.HasExpectLinux or (not DoReadBlock(LLines, LI, LEnd, LIndent, ASpec.ExpectLinux)) then
      begin
        AReason := Format('%s(%d): a second or empty EXPECT linux:', [AFile, LI + 1]);
        Exit;
      end;
      ASpec.HasExpectLinux := True;
    end
    else if LTrim.StartsWith(PC_CMPL_EXITCODE) then
    begin
      // Digits only: no StrToIntDef (a typo is never 0), no sign, no $hex
      LValue := LTrim.Substring(PC_CMPL_EXITCODE.Length).Trim();
      if LHasExit or (not DoIsDigits(LValue)) or (not TryStrToInt(LValue, ASpec.ExitCode)) then
      begin
        AReason := Format('%s(%d): a second or malformed EXITCODE: [%s]', [AFile, LI + 1, LTrim]);
        Exit;
      end;
      LHasExit := True;
    end
    else if LTrim.StartsWith(PC_CMPL_EXPECT_WORD) or LTrim.StartsWith(PC_CMPL_EXITCODE_WORD) then
    begin
      // D10: a directive-looking line that is no directive (a stale header)
      AReason := Format('%s(%d): not a directive form: [%s]', [AFile, LI + 1, LTrim]);
      Exit;
    end;
    Inc(LI);
  end;
  Result := True;
end;

class function TPCCompliance.ReadMarkers(const AFile: string;
  const AMarkers: TList<TPCComplianceMarker>; out AReason: string): Boolean;
var
  LLines: TArray<string>;
  LFile: string;
  LI: Integer;
  LPos: Integer;
  LNext: Integer;
  LText: string;
  LIsMarker: Boolean;
  LMarker: TPCComplianceMarker;
begin
  Result := False;
  if not DoReadLines(AFile, LLines, AReason) then
    Exit;
  try
    LFile := TUtils.ResolvePath(AFile);
  except
    on E: Exception do
    begin
      AReason := Format('%s cannot be resolved: %s', [AFile, E.Message]);
      Exit;
    end;
  end;

  // The leading header comment is prose for the person: no markers there
  for LI := DoHeaderEnd(LLines) to High(LLines) do
  begin
    LPos := LLines[LI].IndexOf(PC_CMPL_COMMENT);
    while LPos >= 0 do
    begin
      // One marker per //, up to the next // on the line
      LNext := LLines[LI].IndexOf(PC_CMPL_COMMENT, LPos + PC_CMPL_COMMENT.Length);
      if LNext < 0 then
        LText := LLines[LI].Substring(LPos + PC_CMPL_COMMENT.Length)
      else
        LText := LLines[LI].Substring(LPos + PC_CMPL_COMMENT.Length,
          LNext - LPos - PC_CMPL_COMMENT.Length);
      if not DoParseMarker(LText.Trim(), LIsMarker, LMarker) then
      begin
        AReason := Format('%s(%d): malformed marker [%s]', [AFile, LI + 1, LText.Trim()]);
        Exit;
      end;
      if LIsMarker then
      begin
        LMarker.Filename := LFile;
        LMarker.Line := LI + 1;
        AMarkers.Add(LMarker);
      end;
      LPos := LNext;
    end;
  end;
  Result := True;
end;

class function TPCCompliance.BuildFiles(const AMainFile: string; const AMain: TPCModule): TArray<string>;
var
  LFiles: TList<string>;
  LPending: TList<TPCModule>;
  LSeen: TList<TPCModule>;
  LModule: TPCModule;
  LImport: TPCImport;
  LDirective: TPCDirective;
begin
  LFiles := TList<string>.Create();
  LPending := TList<TPCModule>.Create();
  LSeen := TList<TPCModule>.Create();
  try
    DoAddFile(LFiles, AMainFile);
    if AMain <> nil then
      LPending.Add(AMain);
    // Every module the parser loaded, through the imports (AST.pas TPCImport.ImportedModule)
    while LPending.Count > 0 do
    begin
      LModule := LPending[LPending.Count - 1];
      LPending.Delete(LPending.Count - 1);
      if LSeen.Contains(LModule) then
        Continue;
      LSeen.Add(LModule);
      DoAddFile(LFiles, LModule.SourceFile);
      for LDirective in LModule.Directives do
      begin
        if (LDirective.DirectiveKind = bdAddSourceFile) and (LDirective.Args.Count > 0) and
           LDirective.Args[0].HasValue then
          DoAddFile(LFiles, LDirective.Args[0].ResolvedText);
      end;
      for LImport in LModule.Imports do
      begin
        if LImport.ImportedModule <> nil then
          LPending.Add(LImport.ImportedModule);
      end;
    end;
    Result := LFiles.ToArray();
  finally
    LSeen.Free();
    LPending.Free();
    LFiles.Free();
  end;
end;

class function TPCCompliance.NormalizeOutput(const AText: string): string;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10);
  while Result.EndsWith(#10) do
    Result := Result.Substring(0, Result.Length - 1);
end;

end.
