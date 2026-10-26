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
  PaskalCPP.BuildOutput - zig build output -> build diagnostics.

  TPCBuildOutputFilter reads zig build's output one line at a time and keeps
  what it recognises as captures (clang diagnostics with their notes, linker
  errors, the lines of zig's raw clang blocks) and everything else as
  unrecognised lines. It reports nothing: no zig, no TErrors.

  TPCBuildOutputCommit reports a finished build: every entry of each TU's
  clang serialized diagnostics (.dia) with its true level and notes, then
  every capture no entry claimed, once per diagnostic per build, locations
  mapped back through the frontend's location translator.

  The build driver (PaskalCPP.ZigBuild) feeds the lines, runs the commit and
  reports the safety net (UnreportedFailure) under its own code.

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Resources,
    PaskalCPP.SerializedDiag
===============================================================================}

unit PaskalCPP.BuildOutput;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.SerializedDiag;

const
  { PC_ERR_BUILDOUTPUT_TOOLDIAG }
  // A diagnostic clang or a linker reported (warning or error): the
  // toolchain's own finding about the source, not a failure of the driver
  PC_ERR_BUILDOUTPUT_TOOLDIAG = 'ZB0016';

  { PC_ERR_BUILDOUTPUT_WRNDIAGFILE }
  // A TU's .dia exists but is not a complete clang file: the lines zig
  // printed for that TU stand in for it
  PC_ERR_BUILDOUTPUT_WRNDIAGFILE = 'ZB0011';

  { PC_FRONTEND_LEXICAL_WARNINGS }
  // clang's lexical warnings that the frontend's lexer reports itself
  // (LX0201-LX0203). One of these at a location the location translator
  // claims is the frontend's own report seen a second time: the commit drops
  // it, whatever its label. Anywhere else (an included header, the runtime, a
  // user source) it is clang's and stands. The whole message is matched, so
  // other diagnostics of the same warning group stay with clang
  // (research\cppmix\lexer-splice-c.md).
  PC_FRONTEND_LEXICAL_WARNINGS: array[0..2] of string = (
    'backslash and newline separated by space',
    'escaped newline between */ characters at block comment end',
    #39'/*'#39' within block comment'
  );

  { PC_CLANG_STOP_MARKER }
  // The location-less entry clang writes when -ferror-limit stops it. Not a
  // diagnostic of its own: the errors before it already failed the build.
  PC_CLANG_STOP_MARKER = 'too many errors emitted, stopping now';

  { PC_CLANG_INCLUDED_FROM }
  // clang's stderr spelling of one include-chain step in zig's raw block
  PC_CLANG_INCLUDED_FROM = 'In file included from ';

  { PC_CLANG_INCLUDED_FROM_NOTE }
  // The same step as clang's .dia spells it (the note kept for it)
  PC_CLANG_INCLUDED_FROM_NOTE = 'in file included from ';

  { PC_CLANG_EVALUATES_NOTE }
  // clang's note on a failed static_assert whose condition is a comparison:
  // the values it compared, quoted ("expression evaluates to '4 >= 8'")
  PC_CLANG_EVALUATES_NOTE = 'expression evaluates to ';

  { PC_CLANG_INSTANTIATION_NOTE }
  // clang's note naming where a template was instantiated ("in instantiation
  // of template class 'X' requested here"), innermost first. A frontend check
  // that fires inside a template (the runtime's ::pcpp::Array, F47) belongs to
  // the first of them the frontend claims: the use in its source
  PC_CLANG_INSTANTIATION_NOTE = 'in instantiation of ';

  { PC_CLANG_SUBSTITUTION_NOTE }
  // clang's note naming the call whose template arguments were being
  // substituted ("while substituting deduced template arguments into function
  // template 'F'"), asked as an instantiation note is: a check that fires
  // while a C++ routine's parameter types are formed (the runtime's
  // format_arg, PLAN-VENDOR 1e) is at the call only there
  PC_CLANG_SUBSTITUTION_NOTE = 'while substituting ';

  { PC_ZIG_CLANG_EXITED }
  // zig's line for a TU whose clang failed: '<tu>:1:1: error: clang exited
  // with code <n>'. Not a diagnostic: the TU's .dia (or raw block) says why.
  PC_ZIG_CLANG_EXITED = ': error: clang exited with code ';

  { PC_ZIG_FALLBACK_HEADER }
  // Opens a block of a failed TU's raw clang stderr; one of the markers
  // below follows it, then the first raw line on the same line
  // (probed, research\zigbuild-followup\r4-include-chain.md, tests\probe\bo\)
  PC_ZIG_FALLBACK_HEADER = 'error(compilation): ';

  { PC_ZIG_FALLBACK_MARKER }
  // A C / C++ / .ll TU: our .dia flag replaced zig's own, so zig cannot read it
  PC_ZIG_FALLBACK_MARKER = 'failed to parse clang diagnostics: ';

  { PC_ZIG_STDERR_MARKER }
  // A .S TU (zig reads no .dia for assembly): clang's stderr as it printed
  // it. The assembler's lines spell a path's backslashes doubled ('.\\b.S'),
  // the preprocessor's lines do not ('.\b.S')
  PC_ZIG_STDERR_MARKER = 'clang failed with stderr: ';

  { PC_ZIG_FALLBACK_INDENT }
  // Every further raw line of a block is indented by exactly this
  PC_ZIG_FALLBACK_INDENT = '       ';

  { PC_ZIG_ERROR_LABEL }
  // zig's own top-level error label; lld's errors carry their linker's name
  // after it, zig's own linker (Mach-O) none
  PC_ZIG_ERROR_LABEL = 'error: ';

  { PC_LINKER_LABELS }
  // The linker names lld puts after zig's error label (COFF, ELF)
  PC_LINKER_LABELS: array[0..1] of string = (
    'lld-link: ',
    'ld.lld: '
  );

  { PC_ZIG_PROCESS_EXITED }
  // After zig's error label: the build runner's summary of a step whose child
  // process failed ('error: process exited with code <n>'). Not a diagnostic:
  // the child's stderr, re-printed above it, says why (probed 2026-10-11,
  // scripts\zb_cmpl\f2a\raw.txt)
  PC_ZIG_PROCESS_EXITED = 'process exited with code ';

  { PC_ZIG_MISSING_LIB_PREFIX }
  // zig's own error for a link library no search folder holds, one per
  // library, in the child stderr of the compile step (probed 2026-10-11:
  // scripts\zb_cmpl\f2a\probe.txt both targets, raw.txt zig's lines): "unable to find
  // <dynamic|static> system library '<name>' using strategy '<strategy>'.
  // searched paths: <folders | none>", with no location
  PC_ZIG_MISSING_LIB_PREFIX = 'unable to find ';

  { PC_ZIG_MISSING_LIB_KIND }
  // What follows the kind word (dynamic, static) in that error, before the quoted name.
  // zig 0.16 quotes the name with ', zig 0.17.0 with " (probed 2026-10-17:
  // 'unable to find dynamic system library "x" using strategy paths_first. searched
  // paths: none'): either is taken, closed by the same character.
  PC_ZIG_MISSING_LIB_KIND = ' system library ';

  { PC_LINKER_DUPLICATE_SYMBOL }
  // lld's error for a symbol two linked inputs define, after its linker label,
  // the same on COFF and ELF (probed 2026-10-19, zig 0.17.0: scripts\vendor\
  // resdata_a4b\raw_win.txt / raw_linux.txt): 'duplicate symbol: <name>', no
  // location; each holder follows as a note (PC_LINKER_DEFINED_AT)
  PC_LINKER_DUPLICATE_SYMBOL = 'duplicate symbol: ';

  { PC_LINKER_DEFINED_AT }
  // A duplicate symbol's note that starts a holder. lld-link: 'defined at
  // <object>' or 'defined at <archive>(<member>)'; ld.lld: 'defined at
  // <file>:<line> (<path>:<line>)' when the object has line info, then a
  // further note '<object>:(<section>)[ in archive <path>]'
  PC_LINKER_DEFINED_AT = 'defined at ';

  { PC_LINKER_IN_ARCHIVE }
  // ld.lld's holder note: the archive the object came from
  PC_LINKER_IN_ARCHIVE = ' in archive ';

type

  { TPCBuildNote }
  // One note of a build diagnostic. Filename is resolved and absolute ('' =
  // no location); the location is as clang / the linker reported it.
  TPCBuildNote = record
    Filename: string;
    Line: UInt64;
    Column: UInt64;
    MessageText: string;
  end;

  { TPCBuildDiag }
  // One build diagnostic, captured from zig's output or read from a clang
  // serialized diagnostics file. Filename and location as in TPCBuildNote.
  TPCBuildDiag = record
    Filename: string;
    Line: UInt64;
    Column: UInt64;
    Severity: TErrorSeverity;
    MessageText: string;
    Notes: TArray<TPCBuildNote>;
    // A location-less zig error for a library no search folder holds
    // (PC_ZIG_MISSING_LIB_PREFIX), or a location-less linker message that
    // opens with the file of a library this build links (TPCLinkedFile: the
    // linker cannot use it): the library's name, which the frontend locates
    // (TPCLibraryLocator); '' for any other diagnostic
    LibraryName: string;
    // A diagnostic read from a TU's .dia: that TU's source file (resolved
    // and absolute, TPCDiagUnit.SourceFile). One with no location of its own
    // (a .ll's target triple overridden) is about that file: the frontend
    // locates where its source names it (TPCSourceFileLocator). '' = read
    // from zig's lines
    UnitSource: string;
    // A location-less duplicate-symbol linker error (PC_LINKER_DUPLICATE_SYMBOL):
    // the symbol, and per holder the archive file name it came from, bare ('' =
    // an object of this build), in the linker's order; '' / nil otherwise
    DuplicateSymbol: string;
    DuplicateArchives: TArray<string>;
    // clang's warning group as the .dia names it (DIAG_FLAG, no -W); ''
    // = none or a diagnostic read from zig's lines (O13b)
    FlagText: string;
  end;

  { TPCLinkedFile }
  // A library this build links, as the linker finds it: its file (resolved
  // and absolute) and the name the build links it by (@linklibrary, an
  // external clause, the API). Handed to the filter before the build
  // (TPCBuildOutputFilter.SetLinkedFiles)
  TPCLinkedFile = record
    FilePath: string;
    LibraryName: string;
  end;

  { TPCLocationTranslator }
  // Maps a diagnostic location reported by clang / a linker onto the
  // frontend's own source (the frontend looks it up in its AST; the build
  // never sees the AST). True = the location was the frontend's: AOut* hold
  // the mapped location. False = not the frontend's (user C++, system
  // headers): left as reported. AFilename is always resolved and absolute;
  // AColumn is 0 for linker errors.
  TPCLocationTranslator = reference to function(const AFilename: string;
    const ALine: UInt64; const AColumn: UInt64; out AOutFilename: string;
    out AOutLine: UInt64; out AOutColumn: UInt64): Boolean;

  { TPCLibraryLocator }
  // Where the frontend's source names a link library (the frontend looks it
  // up in its AST; the build never sees the AST). True = the source names
  // ALibrary: AOut* hold the .pcpp location of its first naming. False = no
  // module names it (a library set through the API): no location
  TPCLibraryLocator = reference to function(const ALibrary: string;
    out AOutFilename: string; out AOutLine: UInt64;
    out AOutColumn: UInt64): Boolean;

  { TPCSourceFileLocator }
  // Where the frontend's source names a build source file (an @addsourcefile;
  // the frontend looks it up in its AST; the build never sees the AST). True =
  // the source names ASourceFile (resolved and absolute): AOut* hold the
  // .pcpp location of its first naming. False = no module names it (a
  // generated module TU, the runtime, a file set through the API): no location
  TPCSourceFileLocator = reference to function(const ASourceFile: string;
    out AOutFilename: string; out AOutLine: UInt64;
    out AOutColumn: UInt64): Boolean;

  { TPCDiagUnit }
  // One TU of a finished build as the commit reads it: its .dia path and its
  // source file (both resolved and absolute)
  TPCDiagUnit = record
    DiagFile: string;
    SourceFile: string;
  end;

  { TPCGeneratedFileTest }
  // Whether the frontend wrote AFilename for this build (its generated C++:
  // the frontend knows those files, the build does not). An include-chain step
  // in such a file at a location the translator does not claim is the
  // frontend's own #include (a module header, on a generated preamble line):
  // it has no place in the frontend's source and is not shown (DESIGN.md sec
  // 5, F13). AFilename is resolved and absolute, as reported
  TPCGeneratedFileTest = reference to function(const AFilename: string): Boolean;

  { TPCFrontendCheck }
  // A check the frontend wrote into its generated C++ that clang judges (an
  // align below a record's natural alignment SEM could not compute: a C/C++
  // leaf). Offered every located ERROR before it is reported: AFilename /
  // ALine / AColumn and AMessage as clang reported them, AEvaluated = the
  // quoted text of its PC_CLANG_EVALUATES_NOTE note ('' = none). True = the
  // frontend's own check: report ACode / AText at AOut* (the frontend reads
  // them from its AST), its notes not shown (they spell the check's C++).
  // AFlag = clang's warning group of the diagnostic as its .dia names it
  // ('' = none, or a diagnostic read from zig's lines): a check the frontend
  // made clang raise as an error by group (O13b, PC_FRONTEND_FLAG_OVERRIDE).
  // False = not the frontend's: reported as clang's (DESIGN.md sec 5)
  TPCFrontendCheck = reference to function(const AFilename: string;
    const ALine: UInt64; const AColumn: UInt64; const AMessage: string;
    const AEvaluated: string; const AFlag: string; out ACode: string; out AText: string;
    out AOutFilename: string; out AOutLine: UInt64; out AOutColumn: UInt64): Boolean;

  { TPCDuplicateSymbolCheck }
  // A duplicate symbol the frontend defined on purpose (PLAN-RESDATA A4b: a
  // built-in data key's symbol, which a separately built library holds too).
  // ASymbol and AArchives as TPCBuildDiag holds them. True = the frontend's:
  // report ACode / AText at AOut* ('' = no location) with ANotes, the linker's
  // notes not shown (they name object files). False = reported as the linker's
  TPCDuplicateSymbolCheck = reference to function(const ASymbol: string;
    const AArchives: TArray<string>; out ACode: string; out AText: string;
    out AOutFilename: string; out AOutLine: UInt64; out AOutColumn: UInt64;
    out ANotes: TArray<TPCBuildNote>): Boolean;

  { TPCBuildOutputFilter }
  // zig build output lines -> captures + unrecognised lines. Pure: reports
  // nothing. Init before every build; Finish after its last line.
  TPCBuildOutputFilter = class(TBaseObject)
  private
    // Build root that zig's relative paths are relative to (resolved)
    FBuildRoot: string;

    // The line after zig's 'the following build command' header is skipped
    FSkipNext: Boolean;

    // A linker error waiting for its 'referenced by' location; once located,
    // its further notes (object-file references) still belong to it
    FLinkerPending: Boolean;
    FLinkerMsg: string;
    FLinkerTail: Boolean;
    // A pending duplicate-symbol error's holders, one per 'defined at' note
    // (TPCBuildDiag.DuplicateArchives)
    FLinkerArchives: TArray<string>;

    // Inside a step's child stderr the build runner re-printed ('error: error:
    // ...'): its further lines come indented by PC_ZIG_FALLBACK_INDENT
    FInChildStderr: Boolean;

    // Captures in the order zig printed them; unrecognised lines likewise
    FCaptures: TList<TPCBuildDiag>;
    FUnknown: TStringList;

    // Inside a raw clang block: its kind, and the include chain read for
    // the diagnostic that follows
    FInBlock: Boolean;
    FBlockStderr: Boolean;
    FChain: TArray<TPCBuildNote>;

    // The libraries this build links, by file (SetLinkedFiles)
    FLinkedFiles: TArray<TPCLinkedFile>;

    function DoResolve(const AText: string): string;
    function DoLinkedFileLibrary(const AMessage: string): string;
    function DoWithoutLineSuffix(const APath: string): string;
    function DoWrapperLine(const ALine: string): Boolean;
    function DoErrorLine(const ALine: string): Boolean;
    function DoChildLine(const ALine: string): Boolean;
    function DoClangLine(const ALine: string): Boolean;
    function DoLinkerNote(const ALine: string): Boolean;
    procedure DoDuplicateHolderNote(const AText: string);
    procedure DoLinkerCommit(const AFilename: string; const ALine: UInt64);
    procedure DoCapture(const AFilename: string; const ALine: UInt64;
      const AColumn: UInt64; const ASeverity: TErrorSeverity;
      const AMessage: string);
    procedure DoCaptureNote(const AFilename: string; const ALine: UInt64;
      const AColumn: UInt64; const AMessage: string);
    function DoBlockStart(const AText: string; const AMarker: string;
      const AStderr: Boolean): Boolean;
    function DoBlockLine(const ALine: string): Boolean;
    function DoRawPlain(const ALine: string; const ALabel: string;
      const ASeverity: TErrorSeverity): Boolean;
    function DoRawChain(const ALine: string): Boolean;
    procedure DoRawLine(const ALine: string);
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Starts a build: forgets the last one. ABuildRoot = zig's working
    // directory, resolved and absolute.
    procedure Init(const ABuildRoot: string);

    // After Init: the libraries this build links, by file. A location-less
    // linker message that opens with one of these files ('<file>: ...', the
    // linker cannot use it) is that library's (TPCBuildDiag.LibraryName)
    procedure SetLinkedFiles(const AFiles: TArray<TPCLinkedFile>);

    // One line of zig's output, as captured (no line terminator)
    procedure AddLine(const ALine: string);

    // After the last line: a pending linker error is kept without a location
    procedure Finish();

    function CaptureCount(): Integer;
    function GetCapture(const AIndex: Integer): TPCBuildDiag;
    function UnknownCount(): Integer;
    function GetUnknown(const AIndex: Integer): string;
  end;

  { TPCBuildOutputCommit }
  // Reports a finished build into FErrors (wire SetErrors first): every .dia
  // entry, TU by TU in file order, each claiming the capture that repeats it,
  // then every capture no entry claimed. One report per diagnostic per build.
  TPCBuildOutputCommit = class(TBaseObject)
  private
    FTranslator: TPCLocationTranslator;
    FLocator: TPCLibraryLocator;
    FGeneratedFileTest: TPCGeneratedFileTest;
    FFrontendCheck: TPCFrontendCheck;
    FDuplicateSymbolCheck: TPCDuplicateSymbolCheck;
    FSourceFileLocator: TPCSourceFileLocator;
    FCommitted: TList<TPCBuildDiag>;
    FErrorsReported: Integer;

    function DoReadDiagFile(const APath: string; const ABuildRoot: string;
      const AEntries: TList<TPCBuildDiag>; out AReason: string): Boolean;
    procedure DoClaim(const AFilter: TPCBuildOutputFilter;
      var AClaimed: TArray<Boolean>; const AEntry: TPCBuildDiag);
    procedure DoTranslate(var AFilename: string; var ALine: UInt64;
      var AColumn: UInt64);
    procedure DoLocateLibrary(const ALibrary: string; var AFilename: string;
      var ALine: UInt64; var AColumn: UInt64);
    procedure DoLocateSourceFile(const ASourceFile: string; var AFilename: string;
      var ALine: UInt64; var AColumn: UInt64);
    function DoFrontendOwned(const ADiag: TPCBuildDiag): Boolean;
    function DoFrontendIncludeStep(const ANote: TPCBuildNote): Boolean;
    class function DoEvaluatedText(const ADiag: TPCBuildDiag): string; static;
    // A note's text as reported: an include-chain step's from its location
    class function DoNoteText(const ANote: TPCBuildNote; const AFilename: string;
      const ALine: UInt64): string; static;
    function DoFrontendCheck(const ADiag: TPCBuildDiag; var AKey: TPCBuildDiag;
      out ACode: string): Boolean;
    function DoDuplicateCheck(const ADiag: TPCBuildDiag; var AKey: TPCBuildDiag;
      out ACode: string; out ANotes: TArray<TPCBuildNote>): Boolean;
    function DoFirstReport(const AKey: TPCBuildDiag): Boolean;
    procedure DoReport(const ADiag: TPCBuildDiag);
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // AUnits = every TU (its .dia path and source file), in source order. A
    // .dia that is absent is a TU zig served from its cache: nothing to
    // report. ATranslator, ALocator, AGeneratedFileTest and AFrontendCheck
    // may be nil (no frontend ran).
    procedure Commit(const AFilter: TPCBuildOutputFilter;
      const AUnits: TArray<TPCDiagUnit>; const ABuildRoot: string;
      const ATranslator: TPCLocationTranslator;
      const ALocator: TPCLibraryLocator;
      const AGeneratedFileTest: TPCGeneratedFileTest;
      const AFrontendCheck: TPCFrontendCheck);

    // Kept across commits; nil = no frontend owns a duplicate symbol
    procedure SetDuplicateSymbolCheck(const ACheck: TPCDuplicateSymbolCheck);
    // Kept across commits; nil = no frontend names build source files
    procedure SetSourceFileLocator(const ALocator: TPCSourceFileLocator);

    // Errors (not warnings) the last Commit reported
    function ErrorsReported(): Integer;

    // Safety net: the lines to show when the build failed and no reported
    // error explains it (AErrorsReported = 0); otherwise none
    class function UnreportedFailure(const AFilter: TPCBuildOutputFilter;
      const ABuildFailed: Boolean;
      const AErrorsReported: Integer): TArray<string>;
  end;

// A path the toolchain reported, resolved against ABase, in the plain
// spelling with forward slashes at any length: it is text for the person and
// for the location translator, never a path ZigBuild opens (R45). clang's own
// buffers ('<scratch space>', '<built-in>') and a spelling no path can take (a
// user '#line "<any text>"') come back as reported: the text is data.
function ResolveReportedPath(const AText: string; const ABase: string): string;

implementation

uses
  System.IOUtils;

function ResolveReportedPath(const AText: string; const ABase: string): string;
begin
  if AText.StartsWith('<') and AText.EndsWith('>') then
    Exit(AText);
  try
    Result := TUtils.NormalizePath(TUtils.StripLongPathPrefix(
      TUtils.ResolvePath(AText, ABase)));
  except
    on Exception do
      Result := AText;
  end;
end;

function DoStripClangFlag(const AMessage: string): string;
var
  LPos: Integer;
begin
  // clang's stderr ends a message with the option that controls it
  // (' [-W#warnings]', ' [-Werror,-Wunused-variable]'); the .dia and zig's
  // own lines carry the message without it
  Result := AMessage;
  if not AMessage.EndsWith(']') then
    Exit;
  LPos := AMessage.LastIndexOf(' [-W');
  if LPos < 0 then
    Exit;

  // The tag is the last bracket pair: no ']' before the final one
  if AMessage.IndexOf(']', LPos) <> AMessage.Length - 1 then
    Exit;
  Result := AMessage.Substring(0, LPos);
end;

function DoDuplicateSymbolName(const AMessage: string): string;
begin
  // The symbol lld's duplicate-symbol error names; '' for any other message
  Result := '';
  if AMessage.StartsWith(PC_LINKER_DUPLICATE_SYMBOL) then
    Result := AMessage.Substring(Length(PC_LINKER_DUPLICATE_SYMBOL)).Trim();
end;

function DoBareFileName(const APath: string): string;
var
  LCut: Integer;
begin
  // A linker's file text after its last folder separator, either slash (text
  // only: it names a file the linker read, never one opened here)
  LCut := APath.LastIndexOfAny(['\', '/']);
  Result := APath.Substring(LCut + 1).Trim();
end;

function DoMissingLibraryName(const AMessage: string): string;
var
  LKindEnd: Integer;
  LStart: Integer;
  LEnd: Integer;
  LQuote: Char;
begin
  // The library zig's "unable to find <kind> system library '<name>' ..."
  // error names; '' for any other message. The kind is one word (dynamic,
  // static) between the prefix and PC_ZIG_MISSING_LIB_KIND; the name is quoted
  // with ' (zig 0.16) or " (zig 0.17.0)
  Result := '';
  if not AMessage.StartsWith(PC_ZIG_MISSING_LIB_PREFIX) then
    Exit;
  LKindEnd := AMessage.IndexOf(PC_ZIG_MISSING_LIB_KIND, Length(PC_ZIG_MISSING_LIB_PREFIX));
  if LKindEnd <= Length(PC_ZIG_MISSING_LIB_PREFIX) then
    Exit;
  if AMessage.Substring(Length(PC_ZIG_MISSING_LIB_PREFIX),
    LKindEnd - Length(PC_ZIG_MISSING_LIB_PREFIX)).Contains(' ') then
    Exit;

  // The name opens with a quote and runs to the same quote character
  LStart := LKindEnd + Length(PC_ZIG_MISSING_LIB_KIND);
  if LStart >= AMessage.Length then
    Exit;
  LQuote := AMessage.Chars[LStart];
  if (LQuote <> '''') and (LQuote <> '"') then
    Exit;
  LStart := LStart + 1;
  LEnd := AMessage.IndexOf(LQuote, LStart);
  if LEnd <= LStart then
    Exit;
  Result := AMessage.Substring(LStart, LEnd - LStart);
end;

function DoIsDoubledSpelling(const APath: string): Boolean;
var
  LI: Integer;
  LRun: Integer;
begin
  // The assembler doubles every backslash, so a doubled spelling has
  // backslashes only in runs of even length. A path spelled as is always has
  // a single one somewhere ('.\b.S', '\\srv\share\b.S', '\\?\C:\b.S'); a
  // path without any reads the same either way.
  Result := False;
  LRun := 0;
  for LI := 0 to APath.Length do
  begin
    // One past the end closes a trailing run
    if (LI < APath.Length) and (APath.Chars[LI] = '\') then
    begin
      Inc(LRun);
      Continue;
    end;
    if Odd(LRun) then
      Exit(False);
    if LRun > 0 then
      Result := True;
    LRun := 0;
  end;
end;

function DoDiagFromSerialized(const ADiag: TPCSerializedDiag;
  const ABase: string; out AEntry: TPCBuildDiag): Boolean;
var
  LI: Integer;
  LNote: TPCBuildNote;
begin
  // False = a level that is not reported (ignored, note, remark)
  Result := False;
  AEntry := Default(TPCBuildDiag);
  case ADiag.Level of
    slWarning:
      AEntry.Severity := esWarning;
    slError, slFatal:
      AEntry.Severity := esError;
  else
    Exit;
  end;

  // Spelled as clang spells it: relative to the build root, or absolute (a
  // #line path); '' = no location. Same rule as zig's lines.
  if ADiag.FilePath <> '' then
  begin
    AEntry.Filename := ResolveReportedPath(ADiag.FilePath, ABase);
    AEntry.Line := ADiag.Line;
    AEntry.Column := ADiag.Column;
  end;
  AEntry.MessageText := ADiag.MessageText;
  AEntry.FlagText := ADiag.FlagText;

  SetLength(AEntry.Notes, Length(ADiag.Notes));
  for LI := 0 to High(ADiag.Notes) do
  begin
    LNote := Default(TPCBuildNote);
    if ADiag.Notes[LI].FilePath <> '' then
    begin
      LNote.Filename := ResolveReportedPath(ADiag.Notes[LI].FilePath, ABase);
      LNote.Line := ADiag.Notes[LI].Line;
      LNote.Column := ADiag.Notes[LI].Column;
    end;
    LNote.MessageText := ADiag.Notes[LI].MessageText;
    AEntry.Notes[LI] := LNote;
  end;
  Result := True;
end;

{ TPCBuildOutputFilter }

// Line shapes (zig build --color off, captured over plain pipes):
//   <path>:<line>:<col>: error|fatal error|warning: <msg>  -> captured
//   <path>:<line>:<col>: note: <msg>                       -> its note
//   error: lld-link|ld.lld: <msg> / error: <msg>           -> linker / zig error
//       note: referenced by <path>:<line>                  -> its location
//       note: referenced by <name>:<line> (<path>:<line>)  -> (ELF form)
//   error: error: <msg>                                    -> a step child's error
//          error: <msg>                                    -> its next error
//   error: process exited with code <n>                    -> unrecognised
//   <tu>:1:1: error: clang exited with code <n>            -> unrecognised
//   [error: ]error(compilation): failed to parse clang diagnostics: <raw>
//   [error: ]error(compilation): clang failed with stderr: <raw>
//          <raw>                                           -> raw clang lines
// zig's wrapper text and clang's snippet / caret lines are not diagnostics:
// the wrapper is dropped, snippets are kept as unrecognised lines.

constructor TPCBuildOutputFilter.Create();
begin
  inherited;

  FCaptures := TList<TPCBuildDiag>.Create();
  FUnknown := TStringList.Create();
  Init('');
end;

destructor TPCBuildOutputFilter.Destroy();
begin
  FreeAndNil(FUnknown);
  FreeAndNil(FCaptures);

  inherited;
end;

procedure TPCBuildOutputFilter.Init(const ABuildRoot: string);
begin
  FBuildRoot := ABuildRoot;
  FSkipNext := False;
  FLinkerPending := False;
  FLinkerMsg := '';
  FLinkerTail := False;
  FLinkerArchives := nil;
  FInChildStderr := False;
  FCaptures.Clear();
  FUnknown.Clear();
  FInBlock := False;
  FBlockStderr := False;
  FChain := nil;
  FLinkedFiles := nil;
end;

procedure TPCBuildOutputFilter.SetLinkedFiles(const AFiles: TArray<TPCLinkedFile>);
begin
  FLinkedFiles := AFiles;
end;

function TPCBuildOutputFilter.DoLinkedFileLibrary(const AMessage: string): string;
var
  LCut: Integer;
  LPath: string;
  LFile: TPCLinkedFile;
begin
  // The library whose file a location-less linker message opens with
  // ('<file>: unknown file type', the linker cannot use it; on ELF lld
  // reads a file that is no archive as a linker script and says
  // '<file>:<line>: unknown directive: ...'); '' when none.
  // The text before the first ': ' is compared as a path spelling only
  // (TUtils.SamePath), never resolved: most messages open with no path
  Result := '';
  if Length(FLinkedFiles) = 0 then
    Exit;
  LCut := AMessage.IndexOf(': ');
  if LCut <= 0 then
    Exit;
  LPath := DoWithoutLineSuffix(AMessage.Substring(0, LCut).Trim());
  for LFile in FLinkedFiles do
  begin
    if TUtils.SamePath(LPath, LFile.FilePath) then
      Exit(LFile.LibraryName);
  end;
end;

function TPCBuildOutputFilter.DoWithoutLineSuffix(const APath: string): string;
var
  LColon: Integer;
  LI: Integer;
begin
  // APath without a trailing ':<digits>' (the line a linker message names
  // inside the file); APath itself when it has none
  Result := APath;
  LColon := APath.LastIndexOf(':');
  if (LColon <= 0) or (LColon = APath.Length - 1) then
    Exit;
  for LI := LColon + 1 to APath.Length - 1 do
  begin
    if not CharInSet(APath.Chars[LI], ['0'..'9']) then
      Exit;
  end;
  Result := APath.Substring(0, LColon);
end;

function TPCBuildOutputFilter.DoResolve(const AText: string): string;
var
  LText: string;
begin
  // zig prints paths relative to the build root (its working directory),
  // headers outside it absolute. In a raw stderr block the assembler's lines
  // spell every backslash of a path doubled ('.\\b.S'), the preprocessor's
  // lines do not ('.\b.S', '\\srv\share\b.S'): each path is read by its own
  // spelling (R38e).
  LText := AText;
  if FBlockStderr and DoIsDoubledSpelling(LText) then
    LText := LText.Replace('\\', '\');
  Result := ResolveReportedPath(LText, FBuildRoot);
end;

function TPCBuildOutputFilter.DoWrapperLine(const ALine: string): Boolean;
var
  LTrimmed: string;
begin
  LTrimmed := ALine.Trim();
  Result := True;

  // Step tree zig prints for the failed step
  if (LTrimmed = 'install') or LTrimmed.StartsWith('+- ') then
    Exit;

  // zig's summary of the failed step and the compiler command it ran
  if LTrimmed.StartsWith(PC_ZIG_ERROR_LABEL) and
    LTrimmed.Contains(' compilation error') then
    Exit;
  if LTrimmed.StartsWith('failed command: ') then
    Exit;

  // The summary of a step whose child failed: the child's stderr above it
  // says why; kept for the safety net only (a child that printed nothing)
  if LTrimmed.StartsWith(PC_ZIG_ERROR_LABEL + PC_ZIG_PROCESS_EXITED) then
  begin
    FUnknown.Add(ALine);
    Exit;
  end;

  // Header line; the line after it is the build runner's command line
  if LTrimmed.StartsWith('error: the following build command') then
  begin
    FSkipNext := True;
    Exit;
  end;

  // clang's own stop marker under -ferror-limit (no location)
  if LTrimmed.StartsWith('fatal error: ' + PC_CLANG_STOP_MARKER) then
    Exit;

  Result := False;
end;

function TPCBuildOutputFilter.DoErrorLine(const ALine: string): Boolean;
var
  LI: Integer;
  LText: string;
begin
  // A top-level error zig printed that is not its wrapper text: a linker
  // error (lld's carry the linker's name, zig's own linker none) or any
  // other reason zig gives for the failure. Never only a safety-net line:
  // it waits for 'referenced by' notes that may locate it.
  Result := ALine.StartsWith(PC_ZIG_ERROR_LABEL);
  if not Result then
    Exit;

  LText := ALine.Substring(Length(PC_ZIG_ERROR_LABEL));

  // A step's child stderr, re-printed by the build runner after its own label:
  // the child's first error carries the child's label too; its further lines
  // follow indented (DoChildLine)
  FInChildStderr := LText.StartsWith(PC_ZIG_ERROR_LABEL);
  if FInChildStderr then
    LText := LText.Substring(Length(PC_ZIG_ERROR_LABEL));

  for LI := Low(PC_LINKER_LABELS) to High(PC_LINKER_LABELS) do
  begin
    if LText.StartsWith(PC_LINKER_LABELS[LI]) then
    begin
      LText := LText.Substring(Length(PC_LINKER_LABELS[LI]));
      Break;
    end;
  end;

  FLinkerPending := True;
  FLinkerMsg := LText.Trim();
end;

function TPCBuildOutputFilter.DoChildLine(const ALine: string): Boolean;
var
  LText: string;
begin
  // A further line of a step's re-printed child stderr: indented by exactly
  // PC_ZIG_FALLBACK_INDENT. One that carries the child's error label is the
  // child's next error, waiting like any top-level one; any other line of it
  // falls through (unrecognised). A line not indented so ends the stderr
  Result := False;
  if not FInChildStderr then
    Exit;
  if (not ALine.StartsWith(PC_ZIG_FALLBACK_INDENT)) or
    (ALine.Length <= Length(PC_ZIG_FALLBACK_INDENT)) or
    (ALine.Chars[Length(PC_ZIG_FALLBACK_INDENT)] = ' ') then
  begin
    FInChildStderr := False;
    Exit;
  end;

  LText := ALine.Substring(Length(PC_ZIG_FALLBACK_INDENT));
  if not LText.StartsWith(PC_ZIG_ERROR_LABEL) then
    Exit;

  FLinkerPending := True;
  FLinkerMsg := LText.Substring(Length(PC_ZIG_ERROR_LABEL)).Trim();
  Result := True;
end;

function TPCBuildOutputFilter.DoClangLine(const ALine: string): Boolean;
var
  LPos1: Integer;
  LPos2: Integer;
  LPos3: Integer;
  LLineNum: Integer;
  LColNum: Integer;
  LFilePath: string;
  LRest: string;
  LMessage: string;
  LSeverity: TErrorSeverity;
begin
  Result := False;

  // A diagnostic header never starts with whitespace (snippets/carets do)
  if (ALine = '') or (ALine[1] = ' ') or (ALine[1] = #9) then
    Exit;

  // <path>:<line>:<col>: ... - skip a drive-letter colon (C:/...)
  if (ALine.Length > 2) and (ALine[2] = ':') then
    LPos1 := ALine.IndexOf(':', 2)
  else
    LPos1 := ALine.IndexOf(':');
  if LPos1 < 1 then
    Exit;

  LPos2 := ALine.IndexOf(':', LPos1 + 1);
  if LPos2 < 0 then
    Exit;

  LPos3 := ALine.IndexOf(':', LPos2 + 1);
  if LPos3 < 0 then
    Exit;

  if not TryStrToInt(ALine.Substring(LPos1 + 1, LPos2 - LPos1 - 1).Trim(),
    LLineNum) or (LLineNum < 0) then
    Exit;
  if not TryStrToInt(ALine.Substring(LPos2 + 1, LPos3 - LPos2 - 1).Trim(),
    LColNum) or (LColNum < 0) then
    Exit;

  LFilePath := ALine.Substring(0, LPos1);
  LRest := ALine.Substring(LPos3 + 1).TrimLeft();

  // A note is context for the diagnostic just captured, never its own error
  if LRest.StartsWith('note:') then
  begin
    DoCaptureNote(LFilePath, LLineNum, LColNum, LRest.Substring(5).Trim());
    Exit(True);
  end;

  // 'fatal error' (-Wfatal-errors, a missing include) is still one error
  if LRest.StartsWith('fatal error:') then
  begin
    LSeverity := esError;
    LMessage := LRest.Substring(12);
  end
  else if LRest.StartsWith('error:') then
  begin
    LSeverity := esError;
    LMessage := LRest.Substring(6);
  end
  else if LRest.StartsWith('warning:') then
  begin
    LSeverity := esWarning;
    LMessage := LRest.Substring(8);
  end
  else
    Exit;

  DoCapture(LFilePath, LLineNum, LColNum, LSeverity,
    DoStripClangFlag(LMessage.Trim()));
  Result := True;
end;

function TPCBuildOutputFilter.DoLinkerNote(const ALine: string): Boolean;
var
  LRef: string;
  LPos: Integer;
  LLineNum: Integer;
begin
  Result := False;
  if not (FLinkerPending or FLinkerTail) then
    Exit;

  LRef := ALine.Trim();
  if not LRef.StartsWith('note:') then
    Exit;

  // Every note here belongs to the linker error; a located one keeps its
  // further notes and needs no other location
  Result := True;
  if not FLinkerPending then
    Exit;

  // A duplicate symbol's notes name its holders, never a source line
  if FLinkerMsg.StartsWith(PC_LINKER_DUPLICATE_SYMBOL) then
  begin
    DoDuplicateHolderNote(LRef.Substring(5).Trim());
    Exit;
  end;

  // 'referenced by <path>:<line>' locates it; an object-file reference
  // ('...a.obj:(main)', '...a.o:_main') carries no source line, skipped
  LRef := LRef.Substring(5).Trim();
  if not LRef.StartsWith('referenced by ') then
    Exit;
  LRef := LRef.Substring(14).Trim();

  // ld.lld: 'a.cpp:5 (./a.cpp:5)' - the parenthesised spelling is the path
  if LRef.EndsWith(')') and LRef.Contains(' (') then
    LRef := LRef.Substring(LRef.LastIndexOf(' (') + 2,
      LRef.Length - LRef.LastIndexOf(' (') - 3);

  LPos := LRef.LastIndexOf(':');
  if LPos < 2 then
    Exit;
  if not TryStrToInt(LRef.Substring(LPos + 1), LLineNum) or (LLineNum < 0) then
    Exit;

  DoLinkerCommit(LRef.Substring(0, LPos), LLineNum);
  FLinkerTail := True;
end;

procedure TPCBuildOutputFilter.DoLinkerCommit(const AFilename: string;
  const ALine: UInt64);
var
  LMessage: string;
  LArchives: TArray<string>;
  LDiag: TPCBuildDiag;
begin
  // Cleared first: the capture below must not see a pending linker error
  LMessage := FLinkerMsg;
  LArchives := FLinkerArchives;
  FLinkerPending := False;
  FLinkerMsg := '';
  FLinkerArchives := nil;
  DoCapture(AFilename, ALine, 0, esError, LMessage);

  // A duplicate symbol keeps the holders its notes named
  LDiag := FCaptures.Last;
  if LDiag.DuplicateSymbol <> '' then
  begin
    LDiag.DuplicateArchives := LArchives;
    FCaptures[FCaptures.Count - 1] := LDiag;
  end;
end;

procedure TPCBuildOutputFilter.DoDuplicateHolderNote(const AText: string);
var
  LRest: string;
  LOpen: Integer;
  LArchive: string;
  LIndex: Integer;
begin
  // One holder per 'defined at' note. lld-link names an archive member
  // '<archive>(<member>)' with no blank before the '(' (an object of this
  // build: no archive); ld.lld's 'defined at <file>:<line> (<path>:<line>)'
  // has one, and names the archive in a further note (PC_LINKER_IN_ARCHIVE)
  if AText.StartsWith(PC_LINKER_DEFINED_AT) then
  begin
    LRest := AText.Substring(Length(PC_LINKER_DEFINED_AT)).Trim();
    LArchive := '';
    LOpen := LRest.LastIndexOf('(');
    if LRest.EndsWith(')') and (LOpen > 0) and (LRest.Chars[LOpen - 1] <> ' ') then
      LArchive := DoBareFileName(LRest.Substring(0, LOpen));
    FLinkerArchives := FLinkerArchives + [LArchive];
    Exit;
  end;

  LIndex := AText.IndexOf(PC_LINKER_IN_ARCHIVE);
  if (LIndex < 0) or (Length(FLinkerArchives) = 0) then
    Exit;
  FLinkerArchives[High(FLinkerArchives)] :=
    DoBareFileName(AText.Substring(LIndex + Length(PC_LINKER_IN_ARCHIVE)).Trim());
end;

procedure TPCBuildOutputFilter.DoCapture(const AFilename: string;
  const ALine: UInt64; const AColumn: UInt64;
  const ASeverity: TErrorSeverity; const AMessage: string);
var
  LDiag: TPCBuildDiag;
begin
  LDiag := Default(TPCBuildDiag);
  if AFilename <> '' then
  begin
    LDiag.Filename := DoResolve(AFilename);
    LDiag.Line := ALine;
    LDiag.Column := AColumn;
  end;
  LDiag.Severity := ASeverity;
  LDiag.MessageText := AMessage;
  // Only a location-less error can be zig's missing-library one, or the
  // linker's about a linked library's file: the frontend gives it the
  // location of the library's naming at the commit
  if AFilename = '' then
  begin
    LDiag.LibraryName := DoMissingLibraryName(AMessage);
    if LDiag.LibraryName = '' then
      LDiag.LibraryName := DoLinkedFileLibrary(AMessage);
    LDiag.DuplicateSymbol := DoDuplicateSymbolName(AMessage);
  end;
  FCaptures.Add(LDiag);
end;

procedure TPCBuildOutputFilter.DoCaptureNote(const AFilename: string;
  const ALine: UInt64; const AColumn: UInt64; const AMessage: string);
var
  LDiag: TPCBuildDiag;
  LNote: TPCBuildNote;
begin
  // A note belongs to the diagnostic captured just before it; with nothing
  // before it, it has nothing to belong to
  if FCaptures.Count = 0 then
    Exit;

  LNote := Default(TPCBuildNote);
  LNote.Filename := DoResolve(AFilename);
  LNote.Line := ALine;
  LNote.Column := AColumn;
  LNote.MessageText := AMessage;

  LDiag := FCaptures.Last;
  LDiag.Notes := LDiag.Notes + [LNote];
  FCaptures[FCaptures.Count - 1] := LDiag;
end;

function TPCBuildOutputFilter.DoBlockStart(const AText: string;
  const AMarker: string; const AStderr: Boolean): Boolean;
var
  LPos: Integer;
begin
  // '<header>[error.Name: ]<marker><first raw line>'
  LPos := AText.IndexOf(AMarker);
  Result := LPos >= 0;
  if not Result then
    Exit;

  FInBlock := True;
  FBlockStderr := AStderr;
  FChain := nil;
  DoRawLine(AText.Substring(LPos + Length(AMarker)));
end;

function TPCBuildOutputFilter.DoBlockLine(const ALine: string): Boolean;
var
  LText: string;
begin
  // A block header: the first one carries zig's 'error: ' label, the next
  // ones the raw lines' indent
  LText := ALine.TrimLeft();
  if LText.StartsWith(PC_ZIG_ERROR_LABEL + PC_ZIG_FALLBACK_HEADER) then
    LText := LText.Substring(Length(PC_ZIG_ERROR_LABEL));
  if LText.StartsWith(PC_ZIG_FALLBACK_HEADER) then
  begin
    if DoBlockStart(LText, PC_ZIG_FALLBACK_MARKER, False) then
      Exit(True);
    if DoBlockStart(LText, PC_ZIG_STDERR_MARKER, True) then
      Exit(True);
  end;

  Result := False;
  if not FInBlock then
    Exit;

  // Blank lines separate the blocks; an indented line is the block's next
  // raw line; anything else ends the block
  if ALine.Trim() = '' then
    Exit(True);
  if ALine.StartsWith(PC_ZIG_FALLBACK_INDENT) then
  begin
    DoRawLine(ALine.Substring(Length(PC_ZIG_FALLBACK_INDENT)));
    Exit(True);
  end;

  FInBlock := False;
  FBlockStderr := False;
  FChain := nil;
end;

function TPCBuildOutputFilter.DoRawPlain(const ALine: string;
  const ALabel: string; const ASeverity: TErrorSeverity): Boolean;
begin
  // ALabel opens a diagnostic clang printed without a location
  Result := ALine.StartsWith(ALabel);
  if Result then
    DoCapture('', 0, 0, ASeverity,
      DoStripClangFlag(ALine.Substring(Length(ALabel)).Trim()));
end;

function TPCBuildOutputFilter.DoRawChain(const ALine: string): Boolean;
var
  LRest: string;
  LPos: Integer;
  LLineNum: Integer;
  LNote: TPCBuildNote;
begin
  // 'In file included from <path>:<line>:' is one step of the include chain
  // of the diagnostic that follows; the .dia spells the same note in lower
  // case, and so does the note kept here
  Result := False;
  if not ALine.StartsWith(PC_CLANG_INCLUDED_FROM) then
    Exit;

  LRest := ALine.Substring(Length(PC_CLANG_INCLUDED_FROM)).Trim();
  if LRest.EndsWith(':') then
    LRest := LRest.Substring(0, LRest.Length - 1);

  // The last colon splits off the line; one at index 1 is a drive letter
  LPos := LRest.LastIndexOf(':');
  if (LPos <= 1) or (not TryStrToInt(LRest.Substring(LPos + 1), LLineNum)) or
    (LLineNum < 0) then
    Exit;

  LNote := Default(TPCBuildNote);
  LNote.Filename := DoResolve(LRest.Substring(0, LPos));
  LNote.Line := LLineNum;
  LNote.MessageText := PC_CLANG_INCLUDED_FROM_NOTE + LRest + ':';
  FChain := FChain + [LNote];
  Result := True;
end;

procedure TPCBuildOutputFilter.DoRawLine(const ALine: string);
var
  LCount: Integer;
  LDiag: TPCBuildDiag;
begin
  if DoRawChain(ALine) then
    Exit;

  // clang's own stop marker under -ferror-limit (no location)
  if ALine.StartsWith('fatal error: ' + PC_CLANG_STOP_MARKER) then
    Exit;

  // A location-less diagnostic ('warning: unable to open file ... for
  // serializing diagnostics'): captured without a location, true level kept
  if DoRawPlain(ALine, 'fatal error: ', esError) or
    DoRawPlain(ALine, 'error: ', esError) or
    DoRawPlain(ALine, 'warning: ', esWarning) then
    Exit;

  LCount := FCaptures.Count;
  if DoClangLine(ALine) then
  begin
    // A diagnostic just captured takes the include chain read before it
    if FCaptures.Count > LCount then
    begin
      if Length(FChain) > 0 then
      begin
        LDiag := FCaptures.Last;
        LDiag.Notes := FChain + LDiag.Notes;
        FCaptures[FCaptures.Count - 1] := LDiag;
      end;
      FChain := nil;
    end;
    Exit;
  end;

  // A snippet or caret line, or a shape not recognised
  if ALine.Trim() <> '' then
    FUnknown.Add(ALine);
end;

procedure TPCBuildOutputFilter.AddLine(const ALine: string);
var
  LLine: string;
begin
  // --color off means no escape codes; stripping is only a guard
  LLine := TUtils.StripAnsi(ALine);

  if FSkipNext then
  begin
    FSkipNext := False;
    Exit;
  end;

  // A failed TU's raw clang stderr (zig's fallback blocks)
  if DoBlockLine(LLine) then
    Exit;

  if DoLinkerNote(LLine) then
    Exit;

  // Any other line ends the linker error's notes: a pending one keeps no location
  FLinkerTail := False;
  if FLinkerPending then
    DoLinkerCommit('', 0);

  // The next error of a step's re-printed child stderr
  if DoChildLine(LLine) then
    Exit;

  if DoWrapperLine(LLine) then
    Exit;
  if DoErrorLine(LLine) then
    Exit;

  // zig's '<tu>:1:1: error: clang exited with code <n>' says only that the
  // TU failed; its .dia (or its raw block) says why
  if (LLine <> '') and (LLine[1] <> ' ') and LLine.Contains(PC_ZIG_CLANG_EXITED) then
  begin
    FUnknown.Add(LLine);
    Exit;
  end;

  if DoClangLine(LLine) then
    Exit;

  // Snippet, caret or unrecognised
  if LLine.Trim() <> '' then
    FUnknown.Add(LLine);
end;

procedure TPCBuildOutputFilter.Finish();
begin
  if FLinkerPending then
    DoLinkerCommit('', 0);
  FLinkerTail := False;
  FInChildStderr := False;
  FInBlock := False;
  FBlockStderr := False;
  FChain := nil;
end;

function TPCBuildOutputFilter.CaptureCount(): Integer;
begin
  Result := FCaptures.Count;
end;

function TPCBuildOutputFilter.GetCapture(const AIndex: Integer): TPCBuildDiag;
begin
  Result := FCaptures[AIndex];
end;

function TPCBuildOutputFilter.UnknownCount(): Integer;
begin
  Result := FUnknown.Count;
end;

function TPCBuildOutputFilter.GetUnknown(const AIndex: Integer): string;
begin
  Result := FUnknown[AIndex];
end;

{ TPCBuildOutputCommit }

constructor TPCBuildOutputCommit.Create();
begin
  inherited;

  FCommitted := TList<TPCBuildDiag>.Create();
  FTranslator := nil;
  FFrontendCheck := nil;
  FDuplicateSymbolCheck := nil;
  FSourceFileLocator := nil;
  FErrorsReported := 0;
end;

destructor TPCBuildOutputCommit.Destroy();
begin
  FreeAndNil(FCommitted);

  inherited;
end;

function TPCBuildOutputCommit.DoReadDiagFile(const APath: string;
  const ABuildRoot: string; const AEntries: TList<TPCBuildDiag>;
  out AReason: string): Boolean;
var
  LReader: TPCSerializedDiagReader;
  LI: Integer;
  LEntry: TPCBuildDiag;
begin
  // The TU's diagnostics in file order, levels mapped. False + AReason when
  // the file is not a complete clang .dia: nothing partial is kept.
  AEntries.Clear();
  AReason := '';
  LReader := TPCSerializedDiagReader.Create();
  try
    Result := LReader.LoadFromFile(APath);
    if not Result then
    begin
      AReason := LReader.FailureText();
      Exit;
    end;

    for LI := 0 to LReader.DiagCount() - 1 do
    begin
      if DoDiagFromSerialized(LReader.GetDiag(LI), ABuildRoot, LEntry) then
        AEntries.Add(LEntry);
    end;
  finally
    LReader.Free();
  end;
end;

procedure TPCBuildOutputCommit.DoClaim(const AFilter: TPCBuildOutputFilter;
  var AClaimed: TArray<Boolean>; const AEntry: TPCBuildDiag);
var
  LI: Integer;
  LCapture: TPCBuildDiag;
  LFirstLine: string;
  LBreak: Integer;
begin
  // The first unclaimed capture at the same location with the same message
  // repeats this .dia entry (zig's line for it, or its raw clang line): it
  // is claimed, so it is not reported a second time. The entry's own notes
  // are complete, the include chain included: nothing is taken from it.
  // clang's message can span lines (a static_assert requirement it prints
  // over several, PLAN-PASKAL-ERRORS E6); a line of zig's carries only the
  // first of them, so that first line is the same message too.
  LFirstLine := AEntry.MessageText;
  LBreak := LFirstLine.IndexOfAny([#13, #10]);
  if LBreak >= 0 then
    LFirstLine := LFirstLine.Substring(0, LBreak);

  for LI := 0 to AFilter.CaptureCount() - 1 do
  begin
    if AClaimed[LI] then
      Continue;
    LCapture := AFilter.GetCapture(LI);
    if not SameText(LCapture.Filename, AEntry.Filename) then
      Continue;
    if (LCapture.Line <> AEntry.Line) or (LCapture.Column <> AEntry.Column) then
      Continue;
    if (LCapture.MessageText <> AEntry.MessageText) and
      (LCapture.MessageText <> LFirstLine) then
      Continue;

    AClaimed[LI] := True;
    Exit;
  end;
end;

procedure TPCBuildOutputCommit.DoTranslate(var AFilename: string;
  var ALine: UInt64; var AColumn: UInt64);
var
  LOutFilename: string;
  LOutLine: UInt64;
  LOutColumn: UInt64;
begin
  // No translator, or a location the frontend does not own: as reported
  if not Assigned(FTranslator) then
    Exit;
  if not FTranslator(AFilename, ALine, AColumn, LOutFilename, LOutLine,
    LOutColumn) then
    Exit;

  AFilename := LOutFilename;
  ALine := LOutLine;
  AColumn := LOutColumn;
end;

procedure TPCBuildOutputCommit.DoLocateLibrary(const ALibrary: string;
  var AFilename: string; var ALine: UInt64; var AColumn: UInt64);
var
  LOutFilename: string;
  LOutLine: UInt64;
  LOutColumn: UInt64;
begin
  // No locator, or a library no module names: left without a location
  if not Assigned(FLocator) then
    Exit;
  if not FLocator(ALibrary, LOutFilename, LOutLine, LOutColumn) then
    Exit;

  AFilename := LOutFilename;
  ALine := LOutLine;
  AColumn := LOutColumn;
end;

procedure TPCBuildOutputCommit.DoLocateSourceFile(const ASourceFile: string;
  var AFilename: string; var ALine: UInt64; var AColumn: UInt64);
var
  LOutFilename: string;
  LOutLine: UInt64;
  LOutColumn: UInt64;
begin
  // No locator, or a TU no module names: left without a location
  if not Assigned(FSourceFileLocator) then
    Exit;
  if not FSourceFileLocator(ASourceFile, LOutFilename, LOutLine, LOutColumn) then
    Exit;

  AFilename := LOutFilename;
  ALine := LOutLine;
  AColumn := LOutColumn;
end;

function TPCBuildOutputCommit.DoFrontendOwned(const ADiag: TPCBuildDiag): Boolean;
var
  LI: Integer;
  LKnown: Boolean;
  LOutFilename: string;
  LOutLine: UInt64;
  LOutColumn: UInt64;
begin
  // Without a translator no frontend ran: every warning is clang's own
  Result := False;
  if (not Assigned(FTranslator)) or (ADiag.Filename = '') then
    Exit;

  LKnown := False;
  for LI := Low(PC_FRONTEND_LEXICAL_WARNINGS) to High(PC_FRONTEND_LEXICAL_WARNINGS) do
  begin
    if ADiag.MessageText = PC_FRONTEND_LEXICAL_WARNINGS[LI] then
    begin
      LKnown := True;
      Break;
    end;
  end;
  if not LKnown then
    Exit;

  // The translator claims exactly the frontend's own locations
  Result := FTranslator(ADiag.Filename, ADiag.Line, ADiag.Column,
    LOutFilename, LOutLine, LOutColumn);
end;

function TPCBuildOutputCommit.DoFrontendIncludeStep(const ANote: TPCBuildNote): Boolean;
var
  LOutFilename: string;
  LOutLine: UInt64;
  LOutColumn: UInt64;
begin
  // True = an include-chain step at a generated file's own line: the
  // frontend's #include of a module header (preamble lines carry no #line).
  // A step the translator claims is the person's #include, mapped to .pcpp:
  // it stays; so does every note that is no chain step
  Result := False;
  if (not Assigned(FGeneratedFileTest)) or (ANote.Filename = '') then
    Exit;
  if not ANote.MessageText.StartsWith(PC_CLANG_INCLUDED_FROM_NOTE) then
    Exit;
  if Assigned(FTranslator) and FTranslator(ANote.Filename, ANote.Line,
    ANote.Column, LOutFilename, LOutLine, LOutColumn) then
    Exit;

  Result := FGeneratedFileTest(ANote.Filename);
end;

class function TPCBuildOutputCommit.DoEvaluatedText(const ADiag: TPCBuildDiag): string;
var
  LI: Integer;
  LText: string;
begin
  // The values a failed static_assert compared, from clang's note, without
  // its quotes ('4 >= 8' -> 4 >= 8); '' = no such note
  Result := '';
  for LI := 0 to High(ADiag.Notes) do
  begin
    LText := ADiag.Notes[LI].MessageText;
    if not LText.StartsWith(PC_CLANG_EVALUATES_NOTE) then
      Continue;
    LText := LText.Substring(Length(PC_CLANG_EVALUATES_NOTE));
    if (LText.Length >= 2) and LText.StartsWith('''') and LText.EndsWith('''') then
      LText := LText.Substring(1, LText.Length - 2);
    Exit(LText);
  end;
end;

function TPCBuildOutputCommit.DoFrontendCheck(const ADiag: TPCBuildDiag;
  var AKey: TPCBuildDiag; out ACode: string): Boolean;
var
  LCode: string;
  LText: string;
  LOutFilename: string;
  LOutLine: UInt64;
  LOutColumn: UInt64;
  LNote: TPCBuildNote;
  LOwned: Boolean;
begin
  // True = a located error the frontend wrote the check for: AKey takes its
  // location and message, ACode its code. The untranslated location goes
  // to the frontend, which finds its own node there; a check that fired
  // inside a template (F47: the runtime's Array; PLAN-VENDOR 1e: its
  // format_arg) is asked again at each instantiation or substitution note's
  // location, innermost first, until the frontend claims one (the use in its
  // source)
  Result := False;
  ACode := PC_ERR_BUILDOUTPUT_TOOLDIAG;
  if (not Assigned(FFrontendCheck)) or (ADiag.Severity <> esError) or
    (ADiag.Filename = '') then
    Exit;
  LOwned := FFrontendCheck(ADiag.Filename, ADiag.Line, ADiag.Column,
    ADiag.MessageText, DoEvaluatedText(ADiag), ADiag.FlagText, LCode, LText, LOutFilename,
    LOutLine, LOutColumn);
  if not LOwned then
  begin
    for LNote in ADiag.Notes do
    begin
      if (LNote.Filename = '') or not (LNote.MessageText.StartsWith(PC_CLANG_INSTANTIATION_NOTE) or
        LNote.MessageText.StartsWith(PC_CLANG_SUBSTITUTION_NOTE)) then
        Continue;
      LOwned := FFrontendCheck(LNote.Filename, LNote.Line, LNote.Column,
        ADiag.MessageText, DoEvaluatedText(ADiag), ADiag.FlagText, LCode, LText, LOutFilename,
        LOutLine, LOutColumn);
      if LOwned then
        Break;
    end;
  end;
  if not LOwned then
    Exit;

  AKey.Filename := LOutFilename;
  AKey.Line := LOutLine;
  AKey.Column := LOutColumn;
  AKey.MessageText := LText;
  ACode := LCode;
  Result := True;
end;

procedure TPCBuildOutputCommit.SetSourceFileLocator(const ALocator: TPCSourceFileLocator);
begin
  FSourceFileLocator := ALocator;
end;

procedure TPCBuildOutputCommit.SetDuplicateSymbolCheck(const ACheck: TPCDuplicateSymbolCheck);
begin
  FDuplicateSymbolCheck := ACheck;
end;

function TPCBuildOutputCommit.DoDuplicateCheck(const ADiag: TPCBuildDiag;
  var AKey: TPCBuildDiag; out ACode: string; out ANotes: TArray<TPCBuildNote>): Boolean;
var
  LCode: string;
  LText: string;
  LOutFilename: string;
  LOutLine: UInt64;
  LOutColumn: UInt64;
begin
  // True = a duplicate symbol the frontend defined (A4b): AKey takes its
  // location ('' = none) and message, ACode its code, ANotes its notes
  Result := False;
  ACode := PC_ERR_BUILDOUTPUT_TOOLDIAG;
  ANotes := nil;
  if (not Assigned(FDuplicateSymbolCheck)) or (ADiag.DuplicateSymbol = '') then
    Exit;
  if not FDuplicateSymbolCheck(ADiag.DuplicateSymbol, ADiag.DuplicateArchives, LCode,
    LText, LOutFilename, LOutLine, LOutColumn, ANotes) then
  begin
    ANotes := nil;
    Exit;
  end;

  AKey.Filename := LOutFilename;
  AKey.Line := LOutLine;
  AKey.Column := LOutColumn;
  AKey.MessageText := LText;
  ACode := LCode;
  Result := True;
end;

function TPCBuildOutputCommit.DoFirstReport(const AKey: TPCBuildDiag): Boolean;
var
  LI: Integer;
  LSeen: TPCBuildDiag;
begin
  // True = no earlier report had this key, which is recorded now. Filenames
  // are resolved and absolute, so SameText folds only case, as a Windows
  // host does (the same rule as DoClaim).
  for LI := 0 to FCommitted.Count - 1 do
  begin
    LSeen := FCommitted[LI];
    if SameText(LSeen.Filename, AKey.Filename) and
      (LSeen.Line = AKey.Line) and
      (LSeen.Column = AKey.Column) and
      (LSeen.Severity = AKey.Severity) and
      (LSeen.MessageText = AKey.MessageText) then
      Exit(False);
  end;

  FCommitted.Add(AKey);
  Result := True;
end;

procedure TPCBuildOutputCommit.DoReport(const ADiag: TPCBuildDiag);
var
  LI: Integer;
  LCount: Integer;
  LKey: TPCBuildDiag;
  LFilename: string;
  LLine: UInt64;
  LColumn: UInt64;
  LRange: TSourceRange;
  LCode: string;
  LIsCheck: Boolean;
  LIsDuplicate: Boolean;
  LDuplicateNotes: TArray<TPCBuildNote>;
begin
  // clang's stop marker under -ferror-limit (no location): not a diagnostic
  if (ADiag.Filename = '') and (ADiag.MessageText = PC_CLANG_STOP_MARKER) then
    Exit;

  // A lexical warning the frontend already reported (any label): dropped
  // with its notes, and not counted as an error reported
  if DoFrontendOwned(ADiag) then
    Exit;

  // What the user sees: the translated location, the level and the message.
  // Notes stay out of the key: they are the TU's own include chain. A check
  // the frontend wrote is its own report: its code, text and location
  LKey := Default(TPCBuildDiag);
  LKey.Filename := ADiag.Filename;
  LKey.Line := ADiag.Line;
  LKey.Column := ADiag.Column;
  LKey.Severity := ADiag.Severity;
  LKey.MessageText := ADiag.MessageText;
  LIsCheck := DoFrontendCheck(ADiag, LKey, LCode);
  // A built-in data key's symbol a separately built library holds too: the
  // frontend's report and notes (PLAN-RESDATA A4b)
  LIsDuplicate := (not LIsCheck) and DoDuplicateCheck(ADiag, LKey, LCode, LDuplicateNotes);
  // A frontend check's location is already the frontend's
  if not (LIsCheck or LIsDuplicate) then
  begin
    if LKey.Filename <> '' then
      DoTranslate(LKey.Filename, LKey.Line, LKey.Column)
    else if ADiag.LibraryName <> '' then
      // A library no search folder holds: where the source names it
      DoLocateLibrary(ADiag.LibraryName, LKey.Filename, LKey.Line, LKey.Column)
    else if ADiag.UnitSource <> '' then
      // A TU's own diagnostic with no location: where the source names the TU
      DoLocateSourceFile(ADiag.UnitSource, LKey.Filename, LKey.Line, LKey.Column);
  end;

  // One report per diagnostic per build: a header's diagnostic arrives once
  // per TU that includes it, and only the first TU's copy is reported, with
  // that TU's notes. A duplicate never spends TErrors' budget.
  if not DoFirstReport(LKey) then
    Exit;

  if LKey.Severity = esError then
    Inc(FErrorsReported);

  LCount := FErrors.Count();
  if LKey.Filename <> '' then
    FErrors.Add(LKey.Filename, LKey.Line, LKey.Column, LKey.Severity,
      LCode, LKey.MessageText)
  else
    FErrors.Add(LKey.Severity, LCode, LKey.MessageText);

  // TErrors drops errors past its budget. A note may only attach to a
  // diagnostic that was stored, never to the unrelated one before it. A
  // frontend check's notes spell its C++: not shown
  if FErrors.Count() <= LCount then
    Exit;
  if LIsCheck then
    Exit;
  // The frontend's notes are its own locations already
  if LIsDuplicate then
  begin
    for LI := 0 to High(LDuplicateNotes) do
    begin
      LRange.Clear();
      LRange.Filename := LDuplicateNotes[LI].Filename;
      LRange.StartLine := LDuplicateNotes[LI].Line;
      LRange.StartColumn := LDuplicateNotes[LI].Column;
      LRange.EndLine := LDuplicateNotes[LI].Line;
      LRange.EndColumn := LDuplicateNotes[LI].Column;
      FErrors.AddRelated(LRange, LDuplicateNotes[LI].MessageText);
    end;
    Exit;
  end;

  // Notes map back to the frontend's source like the diagnostic does
  for LI := 0 to High(ADiag.Notes) do
  begin
    // The frontend's own include of a generated header: no .pcpp place (F13)
    if DoFrontendIncludeStep(ADiag.Notes[LI]) then
      Continue;

    LFilename := ADiag.Notes[LI].Filename;
    LLine := ADiag.Notes[LI].Line;
    LColumn := ADiag.Notes[LI].Column;
    if LFilename <> '' then
      DoTranslate(LFilename, LLine, LColumn);

    LRange.Clear();
    LRange.Filename := LFilename;
    LRange.StartLine := LLine;
    LRange.StartColumn := LColumn;
    LRange.EndLine := LLine;
    LRange.EndColumn := LColumn;
    FErrors.AddRelated(LRange, DoNoteText(ADiag.Notes[LI], LFilename, LLine));
  end;
end;

class function TPCBuildOutputCommit.DoNoteText(const ANote: TPCBuildNote;
  const AFilename: string; const ALine: UInt64): string;
begin
  // An include-chain step names its file in its text as clang spelled it
  // (a separator mixed, or a generated C++ file the location maps to its
  // .pcpp): its text is written from the step's reported location, so text
  // and location name one place one way. Every other note is clang's text
  Result := ANote.MessageText;
  if (AFilename = '') or (not ANote.MessageText.StartsWith(PC_CLANG_INCLUDED_FROM_NOTE)) then
    Exit;
  Result := PC_CLANG_INCLUDED_FROM_NOTE + AFilename + ':' + UIntToStr(ALine) + ':';
end;

procedure TPCBuildOutputCommit.Commit(const AFilter: TPCBuildOutputFilter;
  const AUnits: TArray<TPCDiagUnit>; const ABuildRoot: string;
  const ATranslator: TPCLocationTranslator; const ALocator: TPCLibraryLocator;
  const AGeneratedFileTest: TPCGeneratedFileTest; const AFrontendCheck: TPCFrontendCheck);
var
  LI: Integer;
  LJ: Integer;
  LReason: string;
  LEntries: TList<TPCBuildDiag>;
  LEntry: TPCBuildDiag;
  LClaimed: TArray<Boolean>;
begin
  FCommitted.Clear();
  FErrorsReported := 0;
  FTranslator := ATranslator;
  FLocator := ALocator;
  FGeneratedFileTest := AGeneratedFileTest;
  FFrontendCheck := AFrontendCheck;
  if not Assigned(FErrors) then
    Exit;

  SetLength(LClaimed, AFilter.CaptureCount());
  for LI := 0 to High(LClaimed) do
    LClaimed[LI] := False;

  // .dia entries first, TU by TU, in file order: they carry clang's true
  // level and complete notes. An unreadable file is reported, and the lines
  // zig printed for its TU (the raw block) stay unclaimed below.
  LEntries := TList<TPCBuildDiag>.Create();
  try
    for LI := 0 to High(AUnits) do
    begin
      if not FileExists(AUnits[LI].DiagFile) then
        Continue;

      if not DoReadDiagFile(AUnits[LI].DiagFile, ABuildRoot, LEntries, LReason) then
      begin
        FErrors.Add(esWarning, PC_ERR_BUILDOUTPUT_WRNDIAGFILE,
          RSBdoDiagFileUnreadable, [AUnits[LI].DiagFile, LReason]);
        Continue;
      end;

      for LJ := 0 to LEntries.Count - 1 do
      begin
        // Every entry knows its TU: one with no location is about that file
        LEntry := LEntries[LJ];
        LEntry.UnitSource := AUnits[LI].SourceFile;
        DoClaim(AFilter, LClaimed, LEntry);
        DoReport(LEntry);
      end;
    end;
  finally
    LEntries.Free();
  end;

  // Then every capture no entry claimed, in the order zig printed it:
  // linker and zig errors, a .S's assembler diagnostics, the raw lines of a TU
  // without a readable .dia
  for LI := 0 to AFilter.CaptureCount() - 1 do
  begin
    if not LClaimed[LI] then
      DoReport(AFilter.GetCapture(LI));
  end;
end;

function TPCBuildOutputCommit.ErrorsReported(): Integer;
begin
  Result := FErrorsReported;
end;

class function TPCBuildOutputCommit.UnreportedFailure(
  const AFilter: TPCBuildOutputFilter; const ABuildFailed: Boolean;
  const AErrorsReported: Integer): TArray<string>;
var
  LI: Integer;
begin
  // A warning never explains a failed build: only a reported error does
  Result := nil;
  if (not ABuildFailed) or (AErrorsReported > 0) then
    Exit;

  SetLength(Result, AFilter.UnknownCount());
  for LI := 0 to AFilter.UnknownCount() - 1 do
    Result[LI] := AFilter.GetUnknown(LI);
end;

end.
