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
  PaskalCPP.Conditionals - Conditional-directive filter

  TPCConditionalFilter sits between the lexer and the parser. It reads the
  lexer's token stream once and appends the active tokens, unchanged, to a
  second stream that the parser cursors. It consumes @define @undef @ifdef
  @ifndef @elseif @else @endif, keeps the per-file define set (PASKALCPP,
  BUILD_<kind>, TARGET_<ARCH>, TARGET_<OS>, TARGET_<ABI>, the whole triple
  TARGET_<ARCH>_<OS>_<ABI>, TARGET_64BIT, plus @define), and
  reads the module's @target from the directive prologue
  (research\cppmix\filter.md, BNF.md sec 2).

  Dependencies: StdApp.Base (TBaseObject, TErrors), StdApp.Resources (RSCnd*),
    PaskalCPP.Common (TPCToken, TPCTargetTriple),
    PaskalCPP.TokenStream (TPCTokenStream)
  Notes: One linear pass with an explicit frame stack. Every output stream
    ends with exactly one EOF, on every path.
===============================================================================}

unit PaskalCPP.Conditionals;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.Common,
  PaskalCPP.TokenStream;

const
  { PC_ERR_CND_001 }
  PC_ERR_CND_001 = 'CD0001';   // conditional directive needs an identifier
  { PC_ERR_CND_002 }
  PC_ERR_CND_002 = 'CD0002';   // @elseif / @else / @endif without @ifdef / @ifndef
  { PC_ERR_CND_003 }
  PC_ERR_CND_003 = 'CD0003';   // @elseif or @else after @else
  { PC_ERR_CND_004 }
  PC_ERR_CND_004 = 'CD0004';   // @ifdef / @ifndef not closed at EOF
  { PC_ERR_CND_005 }
  PC_ERR_CND_005 = 'CD0005';   // @target outside the directive prologue
  { PC_ERR_CND_006 }
  PC_ERR_CND_006 = 'CD0006';   // @target inside a conditional branch
  { PC_ERR_CND_007 }
  PC_ERR_CND_007 = 'CD0007';   // @target after a conditional directive
  { PC_ERR_CND_008 }
  PC_ERR_CND_008 = 'CD0008';   // duplicate @target
  { PC_ERR_CND_009 }
  PC_ERR_CND_009 = 'CD0009';   // @target needs a plain string literal
  { PC_ERR_CND_010 }
  PC_ERR_CND_010 = 'CD0010';   // malformed triple
  { PC_ERR_CND_011 }
  PC_ERR_CND_011 = 'CD0011';   // not a supported target (BNF.md sec 2)
  { PC_ERR_CND_012 }
  PC_ERR_CND_012 = 'CD0012';   // imported module @target differs from the main module's

type

  { TPCCondFrame }
  // One open @ifdef / @ifndef. ParentActive = the enclosing region emits.
  // HadTrue = a branch was taken, or the parent is inactive: no later branch opens.
  TPCCondFrame = record
    Opener: TPCToken;
    ParentActive: Boolean;
    Active: Boolean;
    HadTrue: Boolean;
    HadElse: Boolean;
  end;

  { TPCConditionalFilter }
  // Filter(): input stream (lexer) -> output stream (active tokens, then EOF).
  // AMainTarget empty = this is the main module; otherwise the main module's
  // triple, which an imported module's @target must equal. AOverrideTarget
  // (empty = none) is the build's target (CLI -t): command line first, then
  // the @directives, so it wins over every @target of the build, the main
  // module's and each imported module's alike (no CD0012 under an override;
  // a @target is still checked for its form). ADefaultTarget (main module
  // only, empty = none; CLI --defaults, the editor) stands in for a missing
  // @target, before the language default.
  // Wire SetErrors() first.
  TPCConditionalFilter = class(TBaseObject)
  private
    FDefines: TDictionary<string, Boolean>;
    FFrames: TList<TPCCondFrame>;
    FInput: TPCTokenStream;          // non-owning, only during Filter
    FOutput: TPCTokenStream;         // non-owning, only during Filter
    FIndex: Integer;                 // current input token
    FPrologueStart: Integer;         // first token after the header; -1 = no header
    FInPrologue: Boolean;
    FInBuildDirective: Boolean;      // inside a build directive, up to its ;
    FEvaluated: Boolean;             // a conditional directive was processed
    FSawTarget: Boolean;             // an @target was seen, valid or not
    FHasTarget: Boolean;             // FParsedTarget holds a valid triple
    FParsedTarget: TPCTargetTriple;
    FMainTarget: TPCTargetTriple;
    FOverrideTarget: TPCTargetTriple; // the build's target (CLI -t), every module of the build
    FDefaultTarget: TPCTargetTriple;  // stands in for a missing @target (editor -t), main only
    FTarget: TPCTargetTriple;
    FCommitted: Boolean;             // target defines are in FDefines
    FHadError: Boolean;

    function DoIsActive(): Boolean;
    function DoIsConditional(const ASpelling: string): Boolean;
    procedure DoError(const AToken: TPCToken; const ACode: string;
      const AMessage: string; const AArgs: array of const);
    procedure DoDefine(const ASymbol: string);
    procedure DoReadHeader();
    procedure DoTrackPrologue(const AToken: TPCToken);
    procedure DoCommitTarget();
    function DoReadSymbol(const ADirective: TPCToken; out ASymbol: string): Boolean;
    procedure DoOpen(const ADirective: TPCToken; const ACondition: Boolean);
    procedure DoElseIf(const ADirective: TPCToken; const ACondition: Boolean);
    procedure DoElse(const ADirective: TPCToken);
    procedure DoEndIf(const ADirective: TPCToken);
    procedure DoConditional(const ADirective: TPCToken);
    procedure DoTarget(const ADirective: TPCToken);
    procedure DoFinish(const AEof: TPCToken);
  public
    constructor Create(); override;
    destructor Destroy(); override;

    function Filter(const AInput: TPCTokenStream; const AOutput: TPCTokenStream;
      const AMainTarget: TPCTargetTriple; const AOverrideTarget: TPCTargetTriple;
      const ADefaultTarget: TPCTargetTriple): Boolean;
    function Target(): TPCTargetTriple;
    function IsDefined(const ASymbol: string): Boolean;
  end;

implementation

uses
  StdApp.Resources;

const
  { PC_CND_DEFINE }
  PC_CND_DEFINE = '@define';
  { PC_CND_UNDEF }
  PC_CND_UNDEF = '@undef';
  { PC_CND_IFDEF }
  PC_CND_IFDEF = '@ifdef';
  { PC_CND_IFNDEF }
  PC_CND_IFNDEF = '@ifndef';
  { PC_CND_ELSEIF }
  PC_CND_ELSEIF = '@elseif';
  { PC_CND_ELSE }
  PC_CND_ELSE = '@else';
  { PC_CND_ENDIF }
  PC_CND_ENDIF = '@endif';
  { PC_CND_TARGET }
  PC_CND_TARGET = '@target';

{ TPCConditionalFilter }

constructor TPCConditionalFilter.Create();
begin
  inherited;

  FDefines := TDictionary<string, Boolean>.Create();
  FFrames := TList<TPCCondFrame>.Create();
  FInput := nil;
  FOutput := nil;
  FPrologueStart := -1;
end;

destructor TPCConditionalFilter.Destroy();
begin
  FFrames.Free();
  FDefines.Free();

  inherited;
end;

function TPCConditionalFilter.DoIsActive(): Boolean;
begin
  if FFrames.Count = 0 then
    Exit(True);
  Result := FFrames[FFrames.Count - 1].Active;
end;

function TPCConditionalFilter.DoIsConditional(const ASpelling: string): Boolean;
begin
  Result := (ASpelling = PC_CND_DEFINE) or (ASpelling = PC_CND_UNDEF) or
    (ASpelling = PC_CND_IFDEF) or (ASpelling = PC_CND_IFNDEF) or
    (ASpelling = PC_CND_ELSEIF) or (ASpelling = PC_CND_ELSE) or
    (ASpelling = PC_CND_ENDIF);
end;

procedure TPCConditionalFilter.DoError(const AToken: TPCToken; const ACode: string;
  const AMessage: string; const AArgs: array of const);
begin
  FHadError := True;
  FErrors.Add(AToken.Range, esError, ACode, AMessage, AArgs);
end;

procedure TPCConditionalFilter.DoDefine(const ASymbol: string);
begin
  FDefines.AddOrSetValue(ASymbol, True);
end;

procedure TPCConditionalFilter.DoReadHeader();
var
  LKind: TPCTokenKind;
begin
  // module <kind> <name> ; read positionally; the parser reports a malformed header
  if FInput.TokenAt(0).Kind <> tkKwModule then
    Exit;
  if FInput.TokenAt(3).Kind <> tkSemicolon then
    Exit;

  LKind := FInput.TokenAt(1).Kind;
  if LKind = tkKwExe then
    DoDefine('BUILD_EXE')
  else if LKind = tkKwDll then
    DoDefine('BUILD_DLL')
  else if LKind = tkKwLib then
    DoDefine('BUILD_LIB')
  else if LKind = tkKwUnit then
    DoDefine('BUILD_UNIT')
  else
    Exit;
  FPrologueStart := 4;
end;

procedure TPCConditionalFilter.DoTrackPrologue(const AToken: TPCToken);
begin
  // The prologue runs from just after the header while the tokens are
  // directives; a build directive runs to its ';', a conditional takes none.
  // It is structural: an inactive branch does not change it.
  if FIndex = FPrologueStart then
    FInPrologue := True;
  if not FInPrologue then
    Exit;

  if AToken.Kind = tkDirective then
  begin
    if not DoIsConditional(AToken.Spelling) then
      FInBuildDirective := True;
    Exit;
  end;

  if FInBuildDirective then
  begin
    if AToken.Kind = tkSemicolon then
      FInBuildDirective := False;
    Exit;
  end;

  FInPrologue := False;
end;

procedure TPCConditionalFilter.DoCommitTarget();
begin
  // Once per file: the triple handed down to an imported module, else the
  // build's override, else the main module's own triple, else the build's
  // default, else the language default
  if FCommitted then
    Exit;
  FCommitted := True;

  if not FMainTarget.IsEmpty() then
    FTarget := FMainTarget
  else if not FOverrideTarget.IsEmpty() then
    FTarget := FOverrideTarget
  else if FHasTarget then
    FTarget := FParsedTarget
  else if not FDefaultTarget.IsEmpty() then
    FTarget := FDefaultTarget
  else
    FTarget := TPCTargetTriple.DefaultTriple();

  DoDefine('TARGET_' + FTarget.Arch.ToUpper());
  DoDefine('TARGET_' + FTarget.OS.ToUpper());
  // The ABI alone, and the whole triple as zig spells it with '-' -> '_'
  // (TARGET_X86_64_LINUX_GNU), so an @ifdef can name exactly one target
  if FTarget.Env <> '' then
    DoDefine('TARGET_' + FTarget.Env.ToUpper());
  DoDefine('TARGET_' + FTarget.ToZig().ToUpper().Replace('-', '_'));
  if FTarget.PointerBits() = 64 then
    DoDefine('TARGET_64BIT');
end;

function TPCConditionalFilter.DoReadSymbol(const ADirective: TPCToken;
  out ASymbol: string): Boolean;
var
  LToken: TPCToken;
begin
  // The symbol is the next token when it is an identifier
  LToken := FInput.TokenAt(FIndex);
  if LToken.Kind = tkIdentifier then
  begin
    ASymbol := LToken.Spelling;
    Inc(FIndex);
    Exit(True);
  end;

  ASymbol := '';
  DoError(ADirective, PC_ERR_CND_001, RSCndNeedSymbol, [ADirective.Spelling]);

  // The token in the symbol's place is the symbol written wrong (`@define 1`):
  // it is dropped with the directive, as a symbol is, so the one mistake is
  // reported once (left in place it would start a C++ span at module level
  // that runs to the end of the file). A token that begins the next
  // construct (a keyword, a directive, a # line, a cppstart block, EOF, a
  // lexer-reported span) is the symbol MISSING: it stays
  if LToken.Category in [tcLiteral, tcOperator, tcDelimiter, tcPrimitive] then
    Inc(FIndex);
  Result := False;
end;

procedure TPCConditionalFilter.DoOpen(const ADirective: TPCToken; const ACondition: Boolean);
var
  LFrame: TPCCondFrame;
begin
  LFrame.Opener := ADirective;
  LFrame.ParentActive := DoIsActive();
  LFrame.Active := LFrame.ParentActive and ACondition;
  // An inactive parent counts as a taken branch, so no later branch opens
  LFrame.HadTrue := LFrame.Active or (not LFrame.ParentActive);
  LFrame.HadElse := False;
  FFrames.Add(LFrame);
end;

procedure TPCConditionalFilter.DoElseIf(const ADirective: TPCToken; const ACondition: Boolean);
var
  LFrame: TPCCondFrame;
begin
  if FFrames.Count = 0 then
  begin
    DoError(ADirective, PC_ERR_CND_002, RSCndNoOpener, [ADirective.Spelling]);
    Exit;
  end;

  LFrame := FFrames[FFrames.Count - 1];
  if LFrame.HadElse then
  begin
    DoError(ADirective, PC_ERR_CND_003, RSCndAfterElse, [ADirective.Spelling]);
    Exit;
  end;

  LFrame.Active := LFrame.ParentActive and (not LFrame.HadTrue) and ACondition;
  LFrame.HadTrue := LFrame.HadTrue or LFrame.Active;
  FFrames[FFrames.Count - 1] := LFrame;
end;

procedure TPCConditionalFilter.DoElse(const ADirective: TPCToken);
var
  LFrame: TPCCondFrame;
begin
  if FFrames.Count = 0 then
  begin
    DoError(ADirective, PC_ERR_CND_002, RSCndNoOpener, [ADirective.Spelling]);
    Exit;
  end;

  LFrame := FFrames[FFrames.Count - 1];
  if LFrame.HadElse then
  begin
    DoError(ADirective, PC_ERR_CND_003, RSCndAfterElse, [ADirective.Spelling]);
    Exit;
  end;

  LFrame.Active := LFrame.ParentActive and (not LFrame.HadTrue);
  LFrame.HadTrue := True;
  LFrame.HadElse := True;
  FFrames[FFrames.Count - 1] := LFrame;
end;

procedure TPCConditionalFilter.DoEndIf(const ADirective: TPCToken);
begin
  if FFrames.Count = 0 then
  begin
    DoError(ADirective, PC_ERR_CND_002, RSCndNoOpener, [ADirective.Spelling]);
    Exit;
  end;
  FFrames.Delete(FFrames.Count - 1);
end;

procedure TPCConditionalFilter.DoConditional(const ADirective: TPCToken);
var
  LName: string;
  LSymbol: string;
  LHasSymbol: Boolean;
  LDefined: Boolean;
begin
  LName := ADirective.Spelling;
  Inc(FIndex);   // past the directive; it never reaches the output

  // Every conditional directive fixes the target defines first (BNF.md sec 2:
  // @target comes before the first conditional directive)
  DoCommitTarget();
  FEvaluated := True;

  if LName = PC_CND_ELSE then
  begin
    DoElse(ADirective);
    Exit;
  end;
  if LName = PC_CND_ENDIF then
  begin
    DoEndIf(ADirective);
    Exit;
  end;

  // The other five take a symbol; a missing one makes the condition false
  LHasSymbol := DoReadSymbol(ADirective, LSymbol);
  LDefined := LHasSymbol and FDefines.ContainsKey(LSymbol);

  if LName = PC_CND_DEFINE then
  begin
    if LHasSymbol and DoIsActive() then
      DoDefine(LSymbol);
  end
  else if LName = PC_CND_UNDEF then
  begin
    if LHasSymbol and DoIsActive() then
      FDefines.Remove(LSymbol);
  end
  else if LName = PC_CND_IFDEF then
    DoOpen(ADirective, LDefined)
  else if LName = PC_CND_IFNDEF then
    DoOpen(ADirective, LHasSymbol and (not LDefined))
  else
    // PC_CND_ELSEIF: DoIsConditional admits only the seven names
    DoElseIf(ADirective, LDefined);
end;

procedure TPCConditionalFilter.DoTarget(const ADirective: TPCToken);
var
  LArg: TPCToken;
  LText: string;
  LTriple: TPCTargetTriple;
  LStatus: TPCTripleStatus;
begin
  // Checks only: the directive's tokens still pass to the parser
  if not FInPrologue then
  begin
    DoError(ADirective, PC_ERR_CND_005, RSCndTargetPlace, []);
    Exit;
  end;
  if FFrames.Count > 0 then
  begin
    DoError(ADirective, PC_ERR_CND_006, RSCndTargetInBranch, []);
    Exit;
  end;
  if FEvaluated then
  begin
    DoError(ADirective, PC_ERR_CND_007, RSCndTargetLate, []);
    Exit;
  end;
  if FSawTarget then
  begin
    DoError(ADirective, PC_ERR_CND_008, RSCndTargetDuplicate, []);
    Exit;
  end;
  FSawTarget := True;

  LArg := FInput.TokenAt(FIndex + 1);
  if (LArg.Kind <> tkStringLiteral) or (LArg.LiteralPrefix <> lpNone) or
    LArg.IsRawString or (LArg.Suffix <> '') then
  begin
    DoError(ADirective, PC_ERR_CND_009, RSCndTargetNeedString, []);
    Exit;
  end;

  // Spelling is the literal with its line splices removed: strip the quotes
  // (a triple has no escapes)
  LText := LArg.Spelling.Substring(1, LArg.Spelling.Length - 2);
  LStatus := TPCTargetTriple.Parse(LText, LTriple);
  if LStatus = tsBadShape then
  begin
    DoError(LArg, PC_ERR_CND_010, RSCndTargetShape, [LText]);
    Exit;
  end;
  if LStatus = tsUnsupported then
  begin
    DoError(LArg, PC_ERR_CND_011, RSCndTargetUnsupported,
      [LText, TPCTargetTriple.SupportedTargetsText()]);
    Exit;
  end;
  // An imported module's @target must equal the main module's, unless the
  // build's override (CLI -t) is set: it wins over every @target, this one too
  if FOverrideTarget.IsEmpty() and (not FMainTarget.IsEmpty()) and
    (LTriple.ToLLVM() <> FMainTarget.ToLLVM()) then
  begin
    DoError(LArg, PC_ERR_CND_012, RSCndTargetMismatch,
      [LTriple.ToLLVM(), FMainTarget.ToLLVM()]);
    Exit;
  end;

  FParsedTarget := LTriple;
  FHasTarget := True;
end;

procedure TPCConditionalFilter.DoFinish(const AEof: TPCToken);
var
  LI: Integer;
begin
  // Every frame still open is reported at its opener, outermost first
  for LI := 0 to FFrames.Count - 1 do
    DoError(FFrames[LI].Opener, PC_ERR_CND_004, RSCndUnterminated, [FFrames[LI].Opener.Spelling]);
  FFrames.Clear();

  DoCommitTarget();
  FOutput.Append(AEof);
end;

function TPCConditionalFilter.Filter(const AInput: TPCTokenStream;
  const AOutput: TPCTokenStream; const AMainTarget: TPCTargetTriple;
  const AOverrideTarget: TPCTargetTriple; const ADefaultTarget: TPCTargetTriple): Boolean;
var
  LToken: TPCToken;
begin
  FDefines.Clear();
  FFrames.Clear();
  FInput := AInput;
  FOutput := AOutput;
  FIndex := 0;
  FPrologueStart := -1;
  FInPrologue := False;
  FInBuildDirective := False;
  FEvaluated := False;
  FSawTarget := False;
  FHasTarget := False;
  FCommitted := False;
  FHadError := False;
  FParsedTarget := Default(TPCTargetTriple);
  FMainTarget := AMainTarget;
  FOverrideTarget := AOverrideTarget;
  FDefaultTarget := ADefaultTarget;
  FTarget := Default(TPCTargetTriple);

  // The output shares the input's bytes and file, so SourceSlice works on it
  FOutput.Init(FInput.SourceBytes(), FInput.SourceFilename());
  DoDefine('PASKALCPP');
  DoReadHeader();

  try
    while True do
    begin
      // TokenAt past the end yields EOF, so this always terminates
      LToken := FInput.TokenAt(FIndex);
      if LToken.Kind = tkEOF then
      begin
        DoFinish(LToken);
        Break;
      end;

      DoTrackPrologue(LToken);
      if (LToken.Kind = tkDirective) and DoIsConditional(LToken.Spelling) then
      begin
        // Consumes the directive and its symbol
        DoConditional(LToken);
        Continue;
      end;
      if (LToken.Kind = tkDirective) and (LToken.Spelling = PC_CND_TARGET) then
        DoTarget(LToken);

      if DoIsActive() then
        FOutput.Append(LToken);
      Inc(FIndex);
    end;
  finally
    FInput := nil;
    FOutput := nil;
  end;

  Result := not FHadError;
end;

function TPCConditionalFilter.Target(): TPCTargetTriple;
begin
  Result := FTarget;
end;

function TPCConditionalFilter.IsDefined(const ASymbol: string): Boolean;
begin
  Result := FDefines.ContainsKey(ASymbol);
end;

end.
