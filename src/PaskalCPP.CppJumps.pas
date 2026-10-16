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
  PaskalCPP.CppJumps - Escaping jumps of a cppstart block in a body

  TPCCppJumpFinder walks the C++ elements of one cppstart block in a body
  (the lexer's DoCapture, TPCTokenStream.CppElementsIn) and returns every
  return / break / continue that leaves the block (O-S6b,
  research\cppmix\sem\prereq-b\jump.md). It ports the probed reference
  walker (scripts\zb_sem\pb\jump_probe.py, 110/110 three-way).

  Dependencies: PaskalCPP.Common (TPCTokenKind, TPCCppJump),
    PaskalCPP.TokenStream (TPCCppElement)
  Notes: Pure: no errors, no I/O. Iterative: the reference's recursive
    routines are states of one loop over an explicit frame stack, so nesting
    costs heap, never stack (D-J5: clang accepts 20000 brace-less ifs; any
    cap would reject valid C++). Punctuators are compared by vocabulary kind,
    words by spelling: a digraph walks as its canonical spelling (F-L3).
===============================================================================}

unit PaskalCPP.CppJumps;

interface

uses
  PaskalCPP.Common,
  PaskalCPP.TokenStream;

const
  { PC_CPP_JUMP_FRAME_CAPACITY }
  PC_CPP_JUMP_FRAME_CAPACITY = 64;   // first size of the frame stack / jump list; doubles as needed

type

  { TPCCppWalkState }
  // Where a frame of the jump walk resumes. An entry state per reference
  // routine that recurses (jwStmt, jwExprStmt, jwParen, jwAtom) and a resume
  // state per call site that returns into its caller (jump_probe.py Walker)
  TPCCppWalkState = (
    jwBlockBody,         // block_body: the statement list of the whole block
    jwStmt,              // stmt: dispatch on the statement's first element
    jwBraceList,         // stmt '{': its statement list, up to '}'
    jwDoAfterBody,       // stmt 'do': body walked; 'while' ( ... ) next
    jwDoAfterCond,       // stmt 'do': condition walked; ';' next
    jwIfAfterCond,       // stmt 'if': condition walked; the then-statement next
    jwIfAfterThen,       // stmt 'if': then-statement walked; 'else' next
    jwTryAfterBody,      // stmt 'try': block or a handler walked; 'catch' next
    jwCatchAfterParen,   // stmt 'catch': ( ... ) walked; the handler next
    jwCaseLabel,         // stmt 'case': the label expression, up to ':'
    jwExprStmt,          // expr_stmt: atoms up to ';' or a closer
    jwParen,             // paren: entry, at '('
    jwParenList,         // paren: atoms up to ')'
    jwAtom,              // atom: dispatch on the atom's first element
    jwSubscriptList,     // atom '[' subscript: atoms up to ']'
    jwInitList           // atom '{' braced init: atoms up to '}'
  );

  { TPCCppJumpFrame }
  // One pending routine of the walk: where it resumes, and the loops /
  // switches around it inside the block (a break leaves the block only with
  // neither, a continue only with no loop)
  TPCCppJumpFrame = record
    State: TPCCppWalkState;
    LoopDepth: Int64;
    SwitchDepth: Int64;
  end;

  { TPCCppJumpFinder }
  // Find is the whole API: the escaping jumps of one block in element order
  // (nil = none). The walk state below is private to one Find call
  TPCCppJumpFinder = record
  private
    FElements: TArray<TPCCppElement>;
    FIndex: NativeInt;
    FFrames: TArray<TPCCppJumpFrame>;
    FFrameCount: NativeInt;
    FJumps: TArray<TPCCppJump>;
    FJumpCount: NativeInt;
    class function DoGrownLength(const ALength: NativeInt): NativeInt; static;
    class function DoCloserOf(const AKind: TPCTokenKind): TPCTokenKind; static;
    class function DoIsNotExprEndWord(const ASpelling: string): Boolean; static;
    function DoEof(): Boolean;
    function DoIsPunct(const AOffset: NativeInt; const AKind: TPCTokenKind): Boolean;
    function DoIsWordAt(const AOffset: NativeInt): Boolean;
    function DoIsWord(const AOffset: NativeInt; const ASpelling: string): Boolean;
    function DoIsCloser(): Boolean;
    function DoPrevIsExprEnd(): Boolean;
    function DoLoopDepth(): Int64;
    function DoSwitchDepth(): Int64;
    procedure DoPush(const AState: TPCCppWalkState; const ALoopDepth: Int64;
      const ASwitchDepth: Int64);
    procedure DoPop();
    procedure DoSetState(const AState: TPCCppWalkState);
    procedure DoRecordJump(const AKind: TPCCppJumpKind);
    procedure DoSkipAttribute();
    procedure DoSkipBalanced();
    procedure DoSkipLambdaRest();
    procedure DoSkipClassSpecifier();
    function DoStmtLoopForm(): Boolean;
    function DoStmtIf(): Boolean;
    function DoStmtTry(): Boolean;
    function DoStmtLabel(): Boolean;
    function DoStmtJump(): Boolean;
    procedure DoStepBlockBody();
    procedure DoStepStmt();
    procedure DoStepBraceList();
    procedure DoStepDoAfterBody();
    procedure DoStepDoAfterCond();
    procedure DoStepIfAfterCond();
    procedure DoStepIfAfterThen();
    procedure DoStepTryAfterBody();
    procedure DoStepCatchAfterParen();
    procedure DoStepCaseLabel();
    procedure DoStepExprStmt();
    procedure DoStepParen();
    procedure DoStepParenList();
    procedure DoStepAtom();
    procedure DoStepSubscriptList();
    procedure DoStepInitList();
    procedure DoWalk();
  public
    class function Find(const AElements: TArray<TPCCppElement>): TArray<TPCCppJump>; static;
  end;

implementation

const
  { PC_CPP_NOT_EXPR_END }
  // Words after which '[' starts a lambda, not a subscript (jump_probe.py NOT_EXPR_END)
  PC_CPP_NOT_EXPR_END: array[0..16] of string = (
    'return',
    'co_return',
    'co_yield',
    'co_await',
    'throw',
    'case',
    'else',
    'do',
    'new',
    'delete',
    'and',
    'or',
    'not',
    'xor',
    'bitand',
    'bitor',
    'compl'
  );

{ TPCCppJumpFinder }

class function TPCCppJumpFinder.DoGrownLength(const ALength: NativeInt): NativeInt;
begin
  if ALength < PC_CPP_JUMP_FRAME_CAPACITY then
    Result := PC_CPP_JUMP_FRAME_CAPACITY
  else
    Result := ALength * 2;
end;

class function TPCCppJumpFinder.DoCloserOf(const AKind: TPCTokenKind): TPCTokenKind;
begin
  // the closer an opener waits for; tkUnknown when AKind opens nothing
  case AKind of
    tkLParen:
      Result := tkRParen;
    tkLBracket:
      Result := tkRBracket;
    tkLBrace:
      Result := tkRBrace;
  else
    Result := tkUnknown;
  end;
end;

class function TPCCppJumpFinder.DoIsNotExprEndWord(const ASpelling: string): Boolean;
var
  LI: Integer;
begin
  Result := False;
  for LI := Low(PC_CPP_NOT_EXPR_END) to High(PC_CPP_NOT_EXPR_END) do
  begin
    if PC_CPP_NOT_EXPR_END[LI] = ASpelling then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function TPCCppJumpFinder.DoEof(): Boolean;
begin
  Result := FIndex >= Length(FElements);
end;

function TPCCppJumpFinder.DoIsPunct(const AOffset: NativeInt; const AKind: TPCTokenKind): Boolean;
var
  LIndex: NativeInt;
begin
  LIndex := FIndex + AOffset;
  Result := (LIndex >= 0) and (LIndex < Length(FElements)) and
    (FElements[LIndex].Kind = cePunct) and (FElements[LIndex].TokenKind = AKind);
end;

function TPCCppJumpFinder.DoIsWordAt(const AOffset: NativeInt): Boolean;
var
  LIndex: NativeInt;
begin
  LIndex := FIndex + AOffset;
  Result := (LIndex >= 0) and (LIndex < Length(FElements)) and
    (FElements[LIndex].Kind = ceWord);
end;

function TPCCppJumpFinder.DoIsWord(const AOffset: NativeInt; const ASpelling: string): Boolean;
begin
  Result := DoIsWordAt(AOffset) and (FElements[FIndex + AOffset].Spelling = ASpelling);
end;

function TPCCppJumpFinder.DoIsCloser(): Boolean;
begin
  Result := DoIsPunct(0, tkRBrace) or DoIsPunct(0, tkRParen) or DoIsPunct(0, tkRBracket);
end;

function TPCCppJumpFinder.DoPrevIsExprEnd(): Boolean;
var
  LPrev: NativeInt;
begin
  // '[' after an expression end is a subscript; anywhere else it starts a lambda
  Result := False;
  if FIndex = 0 then
    Exit;
  LPrev := FIndex - 1;
  case FElements[LPrev].Kind of
    ceLiteral:
      Result := True;
    cePunct:
      Result := (FElements[LPrev].TokenKind = tkRParen) or
        (FElements[LPrev].TokenKind = tkRBracket);
    ceWord:
      Result := not DoIsNotExprEndWord(FElements[LPrev].Spelling);
  else
    Result := False;
  end;
end;

function TPCCppJumpFinder.DoLoopDepth(): Int64;
begin
  Result := FFrames[FFrameCount - 1].LoopDepth;
end;

function TPCCppJumpFinder.DoSwitchDepth(): Int64;
begin
  Result := FFrames[FFrameCount - 1].SwitchDepth;
end;

procedure TPCCppJumpFinder.DoPush(const AState: TPCCppWalkState; const ALoopDepth: Int64;
  const ASwitchDepth: Int64);
begin
  if FFrameCount = Length(FFrames) then
    SetLength(FFrames, DoGrownLength(FFrameCount));
  FFrames[FFrameCount].State := AState;
  FFrames[FFrameCount].LoopDepth := ALoopDepth;
  FFrames[FFrameCount].SwitchDepth := ASwitchDepth;
  Inc(FFrameCount);
end;

procedure TPCCppJumpFinder.DoPop();
begin
  Dec(FFrameCount);
end;

procedure TPCCppJumpFinder.DoSetState(const AState: TPCCppWalkState);
begin
  FFrames[FFrameCount - 1].State := AState;
end;

procedure TPCCppJumpFinder.DoRecordJump(const AKind: TPCCppJumpKind);
var
  LJump: TPCCppJump;
begin
  LJump := Default(TPCCppJump);
  LJump.Kind := AKind;
  LJump.Range := FElements[FIndex].Range;
  if FJumpCount = Length(FJumps) then
    SetLength(FJumps, DoGrownLength(FJumpCount));
  FJumps[FJumpCount] := LJump;
  Inc(FJumpCount);
end;

procedure TPCCppJumpFinder.DoSkipAttribute();
var
  LDepth: Int64;
  LIsOpen: Boolean;
  LIsClose: Boolean;
begin
  // '[' '[' ... ']' ']': nothing in an attribute leaves the block
  LDepth := 0;
  while not DoEof() do
  begin
    LIsOpen := DoIsPunct(0, tkLBracket);
    LIsClose := DoIsPunct(0, tkRBracket);
    Inc(FIndex);
    if LIsOpen then
      Inc(LDepth)
    else if LIsClose then
    begin
      Dec(LDepth);
      if LDepth = 0 then
        Exit;
    end;
  end;
end;

procedure TPCCppJumpFinder.DoSkipBalanced();
var
  LClosers: TArray<TPCTokenKind>;
  LCount: NativeInt;
  LIsPunct: Boolean;
  LKind: TPCTokenKind;
  LCloser: TPCTokenKind;
begin
  // At an opener: skip to its matching closer (jumps inside never leave the
  // block). A closer that is not the awaited one is skipped, as the reference
  LCount := 0;
  while not DoEof() do
  begin
    LIsPunct := FElements[FIndex].Kind = cePunct;
    LKind := FElements[FIndex].TokenKind;
    Inc(FIndex);
    if not LIsPunct then
      Continue;
    LCloser := DoCloserOf(LKind);
    if LCloser <> tkUnknown then
    begin
      if LCount = Length(LClosers) then
        SetLength(LClosers, DoGrownLength(LCount));
      LClosers[LCount] := LCloser;
      Inc(LCount);
    end
    else if (LCount > 0) and (LKind = LClosers[LCount - 1]) then
    begin
      Dec(LCount);
      if LCount = 0 then
        Exit;
    end;
  end;
end;

procedure TPCCppJumpFinder.DoSkipLambdaRest();
begin
  // After the introducer: the declarator up to the body '{' (or stop at ; , ) } ])
  while not DoEof() do
  begin
    if DoIsPunct(0, tkLBrace) then
    begin
      DoSkipBalanced();    // the lambda body: nothing in it leaves the block
      Exit;
    end;
    if DoIsPunct(0, tkSemicolon) or DoIsPunct(0, tkComma) or DoIsPunct(0, tkRParen) or
      DoIsPunct(0, tkRBrace) or DoIsPunct(0, tkRBracket) then
      Exit;
    if DoIsWord(0, 'requires') then
    begin
      Inc(FIndex);
      if DoIsPunct(0, tkLParen) then
        DoSkipBalanced();
      if DoIsPunct(0, tkLBrace) then
        DoSkipBalanced();  // a requires-expression body, not the lambda body
      Continue;
    end;
    if DoIsPunct(0, tkLParen) or DoIsPunct(0, tkLBracket) then
    begin
      DoSkipBalanced();
      Continue;
    end;
    Inc(FIndex);
  end;
end;

procedure TPCCppJumpFinder.DoSkipClassSpecifier();
var
  LOffset: NativeInt;
begin
  // At class / struct / union: a body before ; ) , = is skipped whole (member
  // bodies never leave the block); otherwise only the word is consumed
  LOffset := 1;
  while (FIndex + LOffset < Length(FElements)) and not (DoIsPunct(LOffset, tkLBrace) or
    DoIsPunct(LOffset, tkSemicolon) or DoIsPunct(LOffset, tkRParen) or
    DoIsPunct(LOffset, tkComma) or DoIsPunct(LOffset, tkEqual)) do
    Inc(LOffset);
  if DoIsPunct(LOffset, tkLBrace) then
  begin
    Inc(FIndex, LOffset);
    DoSkipBalanced();
  end
  else
    Inc(FIndex);
end;

function TPCCppJumpFinder.DoStmtLoopForm(): Boolean;
var
  LTop: NativeInt;
  LLoop: Int64;
  LSwitch: Int64;
begin
  Result := True;
  LTop := FFrameCount - 1;
  LLoop := FFrames[LTop].LoopDepth;
  LSwitch := FFrames[LTop].SwitchDepth;
  if DoIsWord(0, 'for') or DoIsWord(0, 'while') then
  begin
    // the body is this frame one loop deeper; the head is walked first at the current depth
    Inc(FIndex);
    FFrames[LTop].LoopDepth := LLoop + 1;
    DoPush(jwParen, LLoop, LSwitch);
    Exit;
  end;
  if DoIsWord(0, 'switch') then
  begin
    Inc(FIndex);
    FFrames[LTop].SwitchDepth := LSwitch + 1;
    DoPush(jwParen, LLoop, LSwitch);
    Exit;
  end;
  if DoIsWord(0, 'do') then
  begin
    Inc(FIndex);
    DoSetState(jwDoAfterBody);
    DoPush(jwStmt, LLoop + 1, LSwitch);
    Exit;
  end;
  Result := False;
end;

function TPCCppJumpFinder.DoStmtIf(): Boolean;
begin
  Result := DoIsWord(0, 'if');
  if not Result then
    Exit;
  Inc(FIndex);
  if DoIsWord(0, 'constexpr') then
    Inc(FIndex);
  if DoIsPunct(0, tkBang) then
    Inc(FIndex);
  DoSetState(jwIfAfterCond);
  if DoIsWord(0, 'consteval') then
    Inc(FIndex)            // `if consteval` / `if !consteval`: no condition
  else
    DoPush(jwParen, DoLoopDepth(), DoSwitchDepth());
end;

function TPCCppJumpFinder.DoStmtTry(): Boolean;
begin
  Result := DoIsWord(0, 'try');
  if not Result then
    Exit;
  Inc(FIndex);
  DoSetState(jwTryAfterBody);
  DoPush(jwStmt, DoLoopDepth(), DoSwitchDepth());
end;

function TPCCppJumpFinder.DoStmtLabel(): Boolean;
begin
  Result := True;
  if DoIsWord(0, 'case') then
  begin
    Inc(FIndex);
    DoSetState(jwCaseLabel);
    Exit;
  end;
  // `default :` and an identifier label (':' is never '::': tkColonColon is its own kind)
  if DoIsWordAt(0) and DoIsPunct(1, tkColon) then
  begin
    Inc(FIndex, 2);
    DoPop();
    Exit;
  end;
  Result := False;
end;

function TPCCppJumpFinder.DoStmtJump(): Boolean;
var
  LKind: TPCCppJumpKind;
  LEscapes: Boolean;
begin
  Result := True;
  if DoIsWord(0, 'return') then
    LKind := cjReturn
  else if DoIsWord(0, 'break') then
    LKind := cjBreak
  else if DoIsWord(0, 'continue') then
    LKind := cjContinue
  else
  begin
    Result := False;
    Exit;
  end;
  // a return always leaves the block; a break only with no loop and no
  // switch around it inside the block; a continue only with no loop
  case LKind of
    cjBreak:
      LEscapes := (DoLoopDepth() = 0) and (DoSwitchDepth() = 0);
    cjContinue:
      LEscapes := DoLoopDepth() = 0;
  else
    LEscapes := True;
  end;
  if LEscapes then
    DoRecordJump(LKind);
  Inc(FIndex);
  DoSetState(jwExprStmt);   // the operand, up to ';'
end;

procedure TPCCppJumpFinder.DoStepBlockBody();
begin
  if DoEof() then
  begin
    DoPop();
    Exit;
  end;
  if DoIsCloser() then
  begin
    Inc(FIndex);           // stray closer: skip (broken C++ is clang's)
    Exit;
  end;
  DoPush(jwStmt, 0, 0);
end;

procedure TPCCppJumpFinder.DoStepStmt();
begin
  if DoEof() then
  begin
    DoPop();
    Exit;
  end;
  if DoIsPunct(0, tkLBrace) then
  begin
    Inc(FIndex);
    DoSetState(jwBraceList);
    Exit;
  end;
  if DoIsPunct(0, tkSemicolon) then
  begin
    Inc(FIndex);
    DoPop();
    Exit;
  end;
  if DoStmtLoopForm() then
    Exit;
  if DoStmtIf() then
    Exit;
  if DoStmtTry() then
    Exit;
  if DoStmtLabel() then
    Exit;
  if DoStmtJump() then
    Exit;
  if DoIsPunct(0, tkLBracket) and DoIsPunct(1, tkLBracket) then
  begin
    DoSkipAttribute();     // the attributed statement follows, in this frame
    Exit;
  end;
  DoSetState(jwExprStmt);
end;

procedure TPCCppJumpFinder.DoStepBraceList();
begin
  if DoEof() or DoIsPunct(0, tkRBrace) then
  begin
    Inc(FIndex);
    DoPop();
    Exit;
  end;
  if DoIsPunct(0, tkRParen) or DoIsPunct(0, tkRBracket) then
  begin
    Inc(FIndex);
    Exit;
  end;
  DoPush(jwStmt, DoLoopDepth(), DoSwitchDepth());
end;

procedure TPCCppJumpFinder.DoStepDoAfterBody();
begin
  DoSetState(jwDoAfterCond);
  if DoIsWord(0, 'while') then
  begin
    Inc(FIndex);
    DoPush(jwParen, DoLoopDepth(), DoSwitchDepth());
  end;
end;

procedure TPCCppJumpFinder.DoStepDoAfterCond();
begin
  if DoIsPunct(0, tkSemicolon) then
    Inc(FIndex);
  DoPop();
end;

procedure TPCCppJumpFinder.DoStepIfAfterCond();
begin
  DoSetState(jwIfAfterThen);
  DoPush(jwStmt, DoLoopDepth(), DoSwitchDepth());
end;

procedure TPCCppJumpFinder.DoStepIfAfterThen();
begin
  if DoIsWord(0, 'else') then
  begin
    Inc(FIndex);
    DoSetState(jwStmt);    // tail call: an else-if chain keeps one frame
    Exit;
  end;
  DoPop();
end;

procedure TPCCppJumpFinder.DoStepTryAfterBody();
begin
  if DoIsWord(0, 'catch') then
  begin
    Inc(FIndex);
    DoSetState(jwCatchAfterParen);
    DoPush(jwParen, DoLoopDepth(), DoSwitchDepth());
    Exit;
  end;
  DoPop();
end;

procedure TPCCppJumpFinder.DoStepCatchAfterParen();
begin
  DoSetState(jwTryAfterBody);
  DoPush(jwStmt, DoLoopDepth(), DoSwitchDepth());
end;

procedure TPCCppJumpFinder.DoStepCaseLabel();
begin
  if DoEof() or DoIsPunct(0, tkColon) or DoIsPunct(0, tkSemicolon) or
    DoIsPunct(0, tkLBrace) or DoIsPunct(0, tkRBrace) then
  begin
    if DoIsPunct(0, tkColon) then
      Inc(FIndex);
    DoPop();
    Exit;
  end;
  DoPush(jwAtom, DoLoopDepth(), DoSwitchDepth());
end;

procedure TPCCppJumpFinder.DoStepExprStmt();
begin
  if DoEof() or DoIsCloser() then
  begin
    DoPop();
    Exit;
  end;
  if DoIsPunct(0, tkSemicolon) then
  begin
    Inc(FIndex);
    DoPop();
    Exit;
  end;
  DoPush(jwAtom, DoLoopDepth(), DoSwitchDepth());
end;

procedure TPCCppJumpFinder.DoStepParen();
begin
  if not DoIsPunct(0, tkLParen) then
  begin
    DoPop();
    Exit;
  end;
  Inc(FIndex);
  DoSetState(jwParenList);
  if DoIsPunct(0, tkLBrace) then
    DoPush(jwStmt, DoLoopDepth(), DoSwitchDepth());  // GNU ({ ... }): the enclosing function's statements
end;

procedure TPCCppJumpFinder.DoStepParenList();
begin
  if DoEof() or DoIsPunct(0, tkRParen) then
  begin
    Inc(FIndex);
    DoPop();
    Exit;
  end;
  if DoIsPunct(0, tkRBrace) or DoIsPunct(0, tkRBracket) then
  begin
    Inc(FIndex);
    Exit;
  end;
  DoPush(jwAtom, DoLoopDepth(), DoSwitchDepth());
end;

procedure TPCCppJumpFinder.DoStepAtom();
begin
  if DoEof() then
  begin
    DoPop();
    Exit;
  end;
  if DoIsPunct(0, tkLBracket) and DoIsPunct(1, tkLBracket) then
  begin
    DoSkipAttribute();
    DoPop();
    Exit;
  end;
  if DoIsPunct(0, tkLBracket) then
  begin
    if DoPrevIsExprEnd() then
    begin
      Inc(FIndex);
      DoSetState(jwSubscriptList);
      Exit;
    end;
    DoSkipBalanced();      // the lambda introducer
    DoSkipLambdaRest();
    DoPop();
    Exit;
  end;
  if DoIsPunct(0, tkLParen) then
  begin
    DoSetState(jwParen);   // tail call
    Exit;
  end;
  if DoIsPunct(0, tkLBrace) then
  begin
    Inc(FIndex);           // braced init: walked as atoms (a statement expression in it still counts)
    DoSetState(jwInitList);
    Exit;
  end;
  if DoIsWord(0, 'class') or DoIsWord(0, 'struct') or DoIsWord(0, 'union') then
  begin
    DoSkipClassSpecifier();
    DoPop();
    Exit;
  end;
  Inc(FIndex);
  DoPop();
end;

procedure TPCCppJumpFinder.DoStepSubscriptList();
begin
  if DoEof() or DoIsPunct(0, tkRBracket) then
  begin
    Inc(FIndex);
    DoPop();
    Exit;
  end;
  if DoIsPunct(0, tkRBrace) or DoIsPunct(0, tkRParen) then
  begin
    Inc(FIndex);
    Exit;
  end;
  DoPush(jwAtom, DoLoopDepth(), DoSwitchDepth());
end;

procedure TPCCppJumpFinder.DoStepInitList();
begin
  if DoEof() or DoIsPunct(0, tkRBrace) then
  begin
    Inc(FIndex);
    DoPop();
    Exit;
  end;
  if DoIsPunct(0, tkRParen) or DoIsPunct(0, tkRBracket) then
  begin
    Inc(FIndex);
    Exit;
  end;
  DoPush(jwAtom, DoLoopDepth(), DoSwitchDepth());
end;

procedure TPCCppJumpFinder.DoWalk();
begin
  // One step of the top frame per iteration. Every step consumes an element,
  // pushes, pops, or moves to a state that does, so the loop ends
  DoPush(jwBlockBody, 0, 0);
  while FFrameCount > 0 do
  begin
    case FFrames[FFrameCount - 1].State of
      jwBlockBody:
        DoStepBlockBody();
      jwStmt:
        DoStepStmt();
      jwBraceList:
        DoStepBraceList();
      jwDoAfterBody:
        DoStepDoAfterBody();
      jwDoAfterCond:
        DoStepDoAfterCond();
      jwIfAfterCond:
        DoStepIfAfterCond();
      jwIfAfterThen:
        DoStepIfAfterThen();
      jwTryAfterBody:
        DoStepTryAfterBody();
      jwCatchAfterParen:
        DoStepCatchAfterParen();
      jwCaseLabel:
        DoStepCaseLabel();
      jwExprStmt:
        DoStepExprStmt();
      jwParen:
        DoStepParen();
      jwParenList:
        DoStepParenList();
      jwAtom:
        DoStepAtom();
      jwSubscriptList:
        DoStepSubscriptList();
      jwInitList:
        DoStepInitList();
    end;
  end;
end;

class function TPCCppJumpFinder.Find(const AElements: TArray<TPCCppElement>): TArray<TPCCppJump>;
var
  LFinder: TPCCppJumpFinder;
  LJumps: TArray<TPCCppJump>;
begin
  LFinder := Default(TPCCppJumpFinder);
  LFinder.FElements := AElements;
  LFinder.DoWalk();
  // trimmed to the jumps found (nil when none); built in the walk, assigned last
  LJumps := LFinder.FJumps;
  SetLength(LJumps, LFinder.FJumpCount);
  Result := LJumps;
end;

end.