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
  PaskalCPP.LSP.Completion - completion items at a position

  The context (the word being typed, a '.' / '->' before it) comes from the
  lexer's tokens and comment spans on the buffer, never from source text.
  The names come from the analysed AST through the one scope rule
  (TPCScopes): the frames SEM pushes at that place, innermost first, one
  entry per name (an inner name hides an outer one), then the system scope
  (intrinsics), the builtin types and the keywords. After '.' / '->' the left
  side's members as SEM resolved it: a module's exports, a choices type's
  values, a record / object / overlay's fields and methods (parents too),
  the varargs words. Concept adopted from FreeStrike.LSP.Resolver
  (CompleteAt) and PIXELS.LSP (DoCompletion: kinds, sortText, call
  snippets); plans\done\PLAN-EDITOR.md E2.9.

  Dependencies: StdApp.Base, StdApp.Utils, PaskalCPP.Common,
    PaskalCPP.TokenStream, PaskalCPP.AST, PaskalCPP.Scopes,
    PaskalCPP.LSP.Symbols
  Notes:
    - Offsets are 0-based byte offsets into the buffer the lexer and the
      parser read (TPCLspDocument.ByteOffsetAt); AST and token ranges end
      exclusive (EndByteOffset).
    - PaskalCPP names only: an opaque C/C++ left side lists nothing.
===============================================================================}

unit PaskalCPP.LSP.Completion;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.Common,
  PaskalCPP.TokenStream,
  PaskalCPP.AST,
  PaskalCPP.Scopes;

const
  { PC_LSP_COMPLETION_METHOD }
  // LSP CompletionItemKind values (the ones PaskalCPP names use)
  PC_LSP_COMPLETION_METHOD = 2;
  { PC_LSP_COMPLETION_FUNCTION }
  PC_LSP_COMPLETION_FUNCTION = 3;
  { PC_LSP_COMPLETION_FIELD }
  PC_LSP_COMPLETION_FIELD = 5;
  { PC_LSP_COMPLETION_VARIABLE }
  PC_LSP_COMPLETION_VARIABLE = 6;
  { PC_LSP_COMPLETION_CLASS }
  PC_LSP_COMPLETION_CLASS = 7;
  { PC_LSP_COMPLETION_INTERFACE }
  PC_LSP_COMPLETION_INTERFACE = 8;
  { PC_LSP_COMPLETION_PROPERTY }
  PC_LSP_COMPLETION_PROPERTY = 10;
  { PC_LSP_COMPLETION_MODULE }
  PC_LSP_COMPLETION_MODULE = 9;
  { PC_LSP_COMPLETION_ENUM }
  PC_LSP_COMPLETION_ENUM = 13;
  { PC_LSP_COMPLETION_KEYWORD }
  PC_LSP_COMPLETION_KEYWORD = 14;
  { PC_LSP_COMPLETION_ENUM_MEMBER }
  PC_LSP_COMPLETION_ENUM_MEMBER = 20;
  { PC_LSP_COMPLETION_CONSTANT }
  PC_LSP_COMPLETION_CONSTANT = 21;
  { PC_LSP_COMPLETION_STRUCT }
  PC_LSP_COMPLETION_STRUCT = 22;
  { PC_LSP_COMPLETION_TYPE_PARAMETER }
  PC_LSP_COMPLETION_TYPE_PARAMETER = 25;

  { PC_LSP_COMPLETION_SORT_DECL }
  // sortText: declarations and intrinsics, then builtin types, then keywords;
  // Items appends each item's position (PC_LSP_COMPLETION_RANK_FORMAT), so
  // the client keeps the list's order (inner scope first, own members before
  // a parent's) instead of sorting a group by label
  PC_LSP_COMPLETION_SORT_DECL = '1';
  { PC_LSP_COMPLETION_SORT_TYPE }
  PC_LSP_COMPLETION_SORT_TYPE = '8';
  { PC_LSP_COMPLETION_SORT_KEYWORD }
  PC_LSP_COMPLETION_SORT_KEYWORD = '9';
  { PC_LSP_COMPLETION_RANK_FORMAT }
  // An item's position in the list, after its group: '1' + '00003'
  PC_LSP_COMPLETION_RANK_FORMAT = '%s%.5d';

type
  { TPCLspCompletionContext }
  // What the cursor is in, read from the tokens. HasList False = no list
  // here (inside a comment, a literal, a directive, a # line or a cppstart
  // block's text)
  TPCLspCompletionContext = record
    HasList: Boolean;
    CursorOffset: UInt64;
    Prefix: string;            // the word before the cursor, cut at it ('' = none)
    PrefixStart: UInt64;       // the word's first byte; CursorOffset when none
    HasQualifier: Boolean;     // a '.' / '->' token right before the word (or the cursor)
    Access: TPCMemberAccess;
    QualifierOffset: UInt64;   // the qualifier token's first byte
    LeftIsVarargs: Boolean;    // the token left of the qualifier is the varargs word
  end;

  { TPCLspCompletionItem }
  TPCLspCompletionItem = record
    ItemLabel: string;
    ItemKind: Integer;         // LSP CompletionItemKind
    Detail: string;
    SortText: string;
    InsertText: string;        // '' = insert the label
    IsSnippet: Boolean;        // InsertText is an LSP snippet (insertTextFormat 2)
  end;

  { TPCLspCompletion }
  TPCLspCompletion = record
  private
    class function DoKindOf(const ANode: TPCNode): Integer; static;
    class function DoDetailOf(const ANode: TPCNode): string; static;
    class function DoSameParams(const AFirst: TPCRoutine; const ASecond: TPCRoutine): Boolean; static;
    class procedure DoSnippet(const AName: string; const AGroup: TList<TPCNode>;
      var AItem: TPCLspCompletionItem); static;
    class function DoItemOf(const AName: string; const AGroup: TList<TPCNode>): TPCLspCompletionItem; static;
    class procedure DoAddGroup(const ANodes: TList<TPCNode>; const AHidden: TDictionary<string, Boolean>;
      const APrefix: string; const AItems: TList<TPCLspCompletionItem>); static;
    class procedure DoAddWord(const AItems: TList<TPCLspCompletionItem>; const APrefix: string;
      const AWord: string; const AKind: Integer; const ADetail: string; const ASortText: string;
      const AInsertText: string); static;
    class procedure DoScopeItems(const AModule: TPCModule; const AContext: TPCLspCompletionContext;
      const AItems: TList<TPCLspCompletionItem>); static;
    // The names the module's own imports export (PLAN-IMPORT-RESOLUTION), in
    // SEM's order: after the frames and the intrinsics, whose names hide
    // them. One unit = offered bare (an overload set one entry); several
    // units = one entry per unit, inserted qualified (the bare name is
    // SM0020), its unit.Name the detail. TPCScopes.FindImported decides
    class procedure DoImportItems(const AFrames: TList<TPCScopeFrame>; const AHidden: TDictionary<string, Boolean>;
      const APrefix: string; const AItems: TList<TPCLspCompletionItem>); static;
    class procedure DoVarargsItems(const APrefix: string; const AItems: TList<TPCLspCompletionItem>); static;
    class procedure DoMemberItems(const AModule: TPCModule; const AContext: TPCLspCompletionContext;
      const AItems: TList<TPCLspCompletionItem>); static;
    // PLAN-OBJECT D10: drop from AFound the hidden members SEM's rule
    // (TPCScopes.HiddenReach) rejects at AAnchor; ARecord = what ALeft's
    // '.' / '->' searches
    class procedure DoDropHidden(const AModule: TPCModule; const AAnchor: UInt64; const ALeft: TPCExpr;
      const ARecord: TPCTypeExpr; const AFound: TList<TPCNode>); static;
    // The type whose method holds AAnchor (the innermost members frame, SEM's
    // DoMethodOwner); nil outside a method
    class function DoMethodOwner(const AModule: TPCModule; const AAnchor: UInt64): TPCTypeExpr; static;
    // PLAN-OBJECT O14: add to AFound the members ARecord's embeds promote
    // (TPCScopes.AllPromoted) that SEM's use would reach at AAnchor: no hidden
    // embed on the path, the member itself judged in the last embedded type
    class procedure DoAddPromoted(const AModule: TPCModule; const AAnchor: UInt64; const ALeft: TPCExpr;
      const ARecord: TPCTypeExpr; const AFound: TList<TPCNode>); static;
  public
    // The context at byte AOffset of the buffer AStream was lexed from
    class function ContextAt(const AStream: TPCTokenStream; const AOffset: UInt64): TPCLspCompletionContext; static;
    // The left side of the '.' / '->' token at AQualifierOffset: a member's
    // base, or the last part an error expression parsed before it; nil = none
    class function LeftOf(const AModule: TPCModule; const AQualifierOffset: UInt64): TPCExpr; static;
    // The completion list for AContext (empty when it has no list)
    class function Items(const AModule: TPCModule; const AContext: TPCLspCompletionContext): TArray<TPCLspCompletionItem>; static;
  end;

implementation

uses
  StdApp.Utils,
  PaskalCPP.LSP.Symbols;

type
  { TPCLspLeftFinder }
  // The walk LeftOf runs: the innermost member or error expression of the
  // module's own file that holds the qualifier token (children are visited
  // after their parent, so the last match is the innermost)
  TPCLspLeftFinder = class(TBaseObject)
  private
    FVisitor: TPCNodeVisitor;
    FFilename: string;
    FOffset: UInt64;
    FLeft: TPCExpr;
    FFound: Boolean;
    function DoInFile(const ARange: TSourceRange): Boolean;
    procedure DoVisit(const ANode: TPCNode);
  public
    constructor Create(); override;
    function Find(const AModule: TPCModule; const AOffset: UInt64): TPCExpr;
  end;

{ TPCLspLeftFinder }

constructor TPCLspLeftFinder.Create();
begin
  inherited;

  FVisitor := DoVisit;
  FLeft := nil;
  FFound := False;
end;

function TPCLspLeftFinder.DoInFile(const ARange: TSourceRange): Boolean;
begin
  Result := (ARange.Filename <> '') and (FFilename <> '') and
    TUtils.SamePath(ARange.Filename, FFilename);
end;

procedure TPCLspLeftFinder.DoVisit(const ANode: TPCNode);
var
  LMember: TPCMember;
  LError: TPCErrorExpr;
  LPart: TPCExpr;
begin
  if ANode is TPCMember then
  begin
    // A member's own access token is the one between its base and its name
    LMember := TPCMember(ANode);
    if (LMember.Base <> nil) and (LMember.Base.Range.EndByteOffset <= FOffset) and
       (FOffset < LMember.Range.EndByteOffset) and DoInFile(LMember.Range) then
    begin
      FLeft := LMember.Base;
      FFound := True;
    end;
  end
  else if ANode is TPCErrorExpr then
  begin
    // `a.` with no name yet: the parser kept what it parsed (PLAN-RECOVERY);
    // the left side is the last part that ends before the qualifier
    LError := TPCErrorExpr(ANode);
    if (LError.Range.StartByteOffset <= FOffset) and (FOffset < LError.Range.EndByteOffset) and
       DoInFile(LError.Range) then
    begin
      FLeft := nil;
      FFound := True;
      for LPart in LError.Parts do
      begin
        if (LPart <> nil) and (LPart.Range.EndByteOffset <= FOffset) then
          FLeft := LPart;
      end;
    end;
  end;

  ANode.EnumChildren(FVisitor);
end;

function TPCLspLeftFinder.Find(const AModule: TPCModule; const AOffset: UInt64): TPCExpr;
begin
  FFilename := AModule.SourceFile;
  FOffset := AOffset;
  FLeft := nil;
  FFound := False;
  DoVisit(AModule);
  Result := FLeft;
end;

{ TPCLspCompletion }

class function TPCLspCompletion.LeftOf(const AModule: TPCModule; const AQualifierOffset: UInt64): TPCExpr;
var
  LFinder: TPCLspLeftFinder;
begin
  Result := nil;
  if AModule = nil then
    Exit;
  LFinder := TPCLspLeftFinder.Create();
  try
    Result := LFinder.Find(AModule, AQualifierOffset);
  finally
    LFinder.Free();
  end;
end;

class function TPCLspCompletion.DoKindOf(const ANode: TPCNode): Integer;
var
  LDecl: TPCTypeDecl;
  LTypeDef: TPCTypeExpr;
begin
  if ANode is TPCRoutine then
  begin
    if TPCRoutine(ANode).RoutineKind = rnMethod then
      Result := PC_LSP_COMPLETION_METHOD
    else
      Result := PC_LSP_COMPLETION_FUNCTION;
  end
  else if ANode is TPCConstDecl then
    Result := PC_LSP_COMPLETION_CONSTANT
  else if ANode is TPCField then
    Result := PC_LSP_COMPLETION_FIELD
  else if ANode is TPCPropertyItem then
    Result := PC_LSP_COMPLETION_PROPERTY
  else if ANode is TPCChoiceValue then
    Result := PC_LSP_COMPLETION_ENUM_MEMBER
  else if (ANode is TPCImport) or (ANode is TPCModule) then
    Result := PC_LSP_COMPLETION_MODULE
  else if ANode is TPCTypeDecl then
  begin
    // A forward is the kind of what it declares
    LDecl := TPCTypeDecl(ANode);
    if LDecl.IsForward and (LDecl.ResolvedFull <> nil) then
      LDecl := LDecl.ResolvedFull;
    LTypeDef := LDecl.TypeDef;
    if (LTypeDef is TPCRecordType) and TPCRecordType(LTypeDef).IsInterface then
      Result := PC_LSP_COMPLETION_INTERFACE
    else if (LTypeDef is TPCRecordType) and TPCRecordType(LTypeDef).IsObject then
      Result := PC_LSP_COMPLETION_CLASS
    else if LTypeDef is TPCChoicesType then
      Result := PC_LSP_COMPLETION_ENUM
    else
      Result := PC_LSP_COMPLETION_STRUCT;
  end
  else
    Result := PC_LSP_COMPLETION_VARIABLE;
end;

class function TPCLspCompletion.DoDetailOf(const ANode: TPCNode): string;
begin
  // Hover's one line (an import: the module it names), on one line
  if (ANode is TPCImport) and (TPCImport(ANode).ImportedModule <> nil) then
    Result := TPCLspSymbols.DeclText(TPCImport(ANode).ImportedModule)
  else
    Result := TPCLspSymbols.DeclText(ANode);
  Result := Result.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' ');
end;

class function TPCLspCompletion.DoSameParams(const AFirst: TPCRoutine; const ASecond: TPCRoutine): Boolean;
var
  LIndex: Integer;
begin
  Result := AFirst.Params.Count = ASecond.Params.Count;
  if not Result then
    Exit;
  for LIndex := 0 to AFirst.Params.Count - 1 do
  begin
    if (AFirst.Params[LIndex] = nil) or (ASecond.Params[LIndex] = nil) or
       (AFirst.Params[LIndex].ParamName <> ASecond.Params[LIndex].ParamName) then
      Exit(False);
  end;
end;

class procedure TPCLspCompletion.DoSnippet(const AName: string; const AGroup: TList<TPCNode>;
  var AItem: TPCLspCompletionItem);
var
  LNode: TPCNode;
  LRoutine: TPCRoutine;
  LFirst: TPCRoutine;
  LAgree: Boolean;
  LIndex: Integer;
  LText: string;
  LParamName: string;
begin
  // A call snippet, one tab stop per parameter, true whichever member clang
  // picks (the inlay hints' rule): an overload set whose members name their
  // parameters differently gets the parentheses only. A forward names its
  // parameters as its full routine does
  LFirst := nil;
  LAgree := True;
  for LNode in AGroup do
  begin
    if not (LNode is TPCRoutine) then
      Exit;
    LRoutine := TPCRoutine(LNode);
    if LRoutine.IsForward and (LRoutine.ResolvedFull <> nil) then
      LRoutine := LRoutine.ResolvedFull;
    if LFirst = nil then
      LFirst := LRoutine
    else if not DoSameParams(LFirst, LRoutine) then
      LAgree := False;
  end;
  if LFirst = nil then
    Exit;
  if not LAgree then
  begin
    AItem.InsertText := AName + '($0)';
    AItem.IsSnippet := True;
    Exit;
  end;
  // No parameters: the name is inserted as it stands
  if LFirst.Params.Count = 0 then
    Exit;

  LText := AName + '(';
  for LIndex := 0 to LFirst.Params.Count - 1 do
  begin
    if LIndex > 0 then
      LText := LText + ', ';
    LParamName := '';
    if LFirst.Params[LIndex] <> nil then
      LParamName := LFirst.Params[LIndex].ParamName;
    if LParamName = '' then
      LText := LText + '${' + IntToStr(LIndex + 1) + '}'
    else
      LText := LText + '${' + IntToStr(LIndex + 1) + ':' + LParamName + '}';
  end;
  AItem.InsertText := LText + ')';
  AItem.IsSnippet := True;
end;

class function TPCLspCompletion.DoItemOf(const AName: string; const AGroup: TList<TPCNode>): TPCLspCompletionItem;
begin
  // The name's first declaration describes the entry
  Result := Default(TPCLspCompletionItem);
  Result.ItemLabel := AName;
  Result.ItemKind := DoKindOf(AGroup[0]);
  Result.Detail := DoDetailOf(AGroup[0]);
  Result.SortText := PC_LSP_COMPLETION_SORT_DECL;
  if AGroup[0] is TPCRoutine then
    DoSnippet(AName, AGroup, Result);
end;

class procedure TPCLspCompletion.DoAddGroup(const ANodes: TList<TPCNode>;
  const AHidden: TDictionary<string, Boolean>; const APrefix: string;
  const AItems: TList<TPCLspCompletionItem>);
var
  LNames: TList<string>;
  LByName: TObjectDictionary<string, TList<TPCNode>>;
  LNode: TPCNode;
  LName: string;
  LGroup: TList<TPCNode>;
begin
  // One entry per name, in the frame's order. The frame's names hide the
  // same names in the frames further out (the innermost frame with a name
  // wins: TPCScopes.Collect); they are noted after the whole frame, so an
  // overload set in one frame stays one entry
  LNames := TList<string>.Create();
  LByName := TObjectDictionary<string, TList<TPCNode>>.Create([doOwnsValues]);
  try
    for LNode in ANodes do
    begin
      LName := TPCLspSymbols.NameOf(LNode);
      if (LName = '') or AHidden.ContainsKey(LName) then
        Continue;
      if not LByName.TryGetValue(LName, LGroup) then
      begin
        LGroup := TList<TPCNode>.Create();
        LByName.Add(LName, LGroup);
        LNames.Add(LName);
      end;
      LGroup.Add(LNode);
    end;
    for LName in LNames do
    begin
      AHidden.AddOrSetValue(LName, True);
      if LName.StartsWith(APrefix) then
        AItems.Add(DoItemOf(LName, LByName[LName]));
    end;
  finally
    LByName.Free();
    LNames.Free();
  end;
end;

class procedure TPCLspCompletion.DoAddWord(const AItems: TList<TPCLspCompletionItem>;
  const APrefix: string; const AWord: string; const AKind: Integer; const ADetail: string;
  const ASortText: string; const AInsertText: string);
var
  LItem: TPCLspCompletionItem;
begin
  // The prefix match is case-sensitive: PaskalCPP is
  if (AWord = '') or not AWord.StartsWith(APrefix) then
    Exit;
  LItem := Default(TPCLspCompletionItem);
  LItem.ItemLabel := AWord;
  LItem.ItemKind := AKind;
  LItem.Detail := ADetail;
  LItem.SortText := ASortText;
  LItem.InsertText := AInsertText;
  LItem.IsSnippet := AInsertText.Contains('$');
  AItems.Add(LItem);
end;

class procedure TPCLspCompletion.DoScopeItems(const AModule: TPCModule;
  const AContext: TPCLspCompletionContext; const AItems: TList<TPCLspCompletionItem>);
var
  LFrames: TList<TPCScopeFrame>;
  LHidden: TDictionary<string, Boolean>;
  LFound: TList<TPCNode>;
  LIndex: Integer;
  LKind: TPCIntrinsicKind;
  LRow: TPCTokenRow;
  LNode: TPCNode;
begin
  LFrames := TList<TPCScopeFrame>.Create();
  LHidden := TDictionary<string, Boolean>.Create();
  LFound := TList<TPCNode>.Create();
  try
    // The frames at the word's start, innermost first (SEM's lookup order)
    TPCScopes.FramesAt(AModule, AContext.PrefixStart, LFrames);
    for LIndex := LFrames.Count - 1 downto 0 do
    begin
      LFound.Clear();
      TPCScopes.CollectAll(LFrames[LIndex], LFound);
      TPCScopes.CollapseForwards(LFound);
      // PLAN-OBJECT D9: a method's members are reached through self., never
      // bare (SM0018): not offered, yet they hide the same names further out,
      // as SEM's lookup stops at them
      if LFrames[LIndex].FrameKind = fkMembers then
      begin
        for LNode in LFound do
        begin
          if TPCLspSymbols.NameOf(LNode) <> '' then
            LHidden.AddOrSetValue(TPCLspSymbols.NameOf(LNode), True);
        end;
        Continue;
      end;
      DoAddGroup(LFound, LHidden, AContext.Prefix, AItems);
    end;

    // The system scope: the intrinsics every frame sees, unless a
    // declaration of the same name is nearer
    for LKind := Low(TPCIntrinsicKind) to High(TPCIntrinsicKind) do
    begin
      if PC_INTRINSIC_NAMES[LKind] = '' then
        Continue;
      if not LHidden.ContainsKey(PC_INTRINSIC_NAMES[LKind]) then
        DoAddWord(AItems, AContext.Prefix, PC_INTRINSIC_NAMES[LKind], PC_LSP_COMPLETION_FUNCTION,
          PC_INTRINSIC_NAMES[LKind] + TPCIntrinsicSigs.SigText(LKind), PC_LSP_COMPLETION_SORT_DECL, '');
      // An intrinsic hides an imported unit's export of its name (SEM's order)
      LHidden.AddOrSetValue(PC_INTRINSIC_NAMES[LKind], True);
    end;

    // The module's own imports: after the frames and the intrinsics
    DoImportItems(LFrames, LHidden, AContext.Prefix, AItems);

    // The words the lexer registers: builtin types, then keywords
    for LRow in PC_PASKAL_TOKENS do
    begin
      if LRow.Category = tcPrimitive then
        DoAddWord(AItems, AContext.Prefix, LRow.Text, PC_LSP_COMPLETION_TYPE_PARAMETER, '',
          PC_LSP_COMPLETION_SORT_TYPE, '');
    end;
    for LRow in PC_PASKAL_TOKENS do
    begin
      if LRow.Category = tcKeyword then
        DoAddWord(AItems, AContext.Prefix, LRow.Text, PC_LSP_COMPLETION_KEYWORD, '',
          PC_LSP_COMPLETION_SORT_KEYWORD, '');
    end;
  finally
    LFound.Free();
    LHidden.Free();
    LFrames.Free();
  end;
end;

class procedure TPCLspCompletion.DoImportItems(const AFrames: TList<TPCScopeFrame>;
  const AHidden: TDictionary<string, Boolean>; const APrefix: string; const AItems: TList<TPCLspCompletionItem>);
var
  LFrame: TPCScopeFrame;
  LImports: TList<TPCImport>;
  LImport: TPCImport;
  LExports: TList<TPCNode>;
  LNode: TPCNode;
  LNames: TList<string>;
  LName: string;
  LFound: TList<TPCNode>;
  LHolders: TList<TPCImport>;
  LOfHolder: TList<TPCNode>;
  LHolder: TPCImport;
  LItem: TPCLspCompletionItem;
  LQualified: string;
begin
  // The module frame holds the module's own import clause (never a unit's)
  LImports := nil;
  for LFrame in AFrames do
  begin
    if LFrame.FrameKind = fkModule then
      LImports := LFrame.Imports;
  end;
  if LImports = nil then
    Exit;
  LExports := TList<TPCNode>.Create();
  LNames := TList<string>.Create();
  LFound := TList<TPCNode>.Create();
  LHolders := TList<TPCImport>.Create();
  LOfHolder := TList<TPCNode>.Create();
  try
    // Every exported name once, in the clause's order, then each unit's
    for LImport in LImports do
    begin
      if (LImport = nil) or (LImport.ImportedModule = nil) then
        Continue;
      LExports.Clear();
      TPCScopes.ModuleMembers(LImport.ImportedModule, LExports);
      for LNode in LExports do
      begin
        LName := TPCLspSymbols.NameOf(LNode);
        if (LName <> '') and not LNames.Contains(LName) then
          LNames.Add(LName);
      end;
    end;
    for LName in LNames do
    begin
      // An own name, a local or an intrinsic of this spelling wins, and so
      // does an own name declared later (SEM: SM0002, never the import)
      if AHidden.ContainsKey(LName) or not LName.StartsWith(APrefix) then
        Continue;
      if TPCScopes.DeclaredLater(AFrames, LName) <> nil then
        Continue;
      LFound.Clear();
      LHolders.Clear();
      TPCScopes.FindImported(LImports, LName, LFound, LHolders);
      if LHolders.Count = 1 then
      begin
        AItems.Add(DoItemOf(LName, LFound));
        Continue;
      end;
      // Several units: each entry writes its own qualified form
      for LHolder in LHolders do
      begin
        LOfHolder.Clear();
        TPCScopes.ModuleMember(LHolder.ImportedModule, LName, LOfHolder);
        if LOfHolder.Count = 0 then
          Continue;
        LQualified := LHolder.ModuleName + '.' + LName;
        LItem := DoItemOf(LQualified, LOfHolder);
        LItem.ItemLabel := LName;
        LItem.Detail := LQualified;
        if LItem.InsertText = '' then
          LItem.InsertText := LQualified;
        AItems.Add(LItem);
      end;
    end;
  finally
    LOfHolder.Free();
    LHolders.Free();
    LFound.Free();
    LNames.Free();
    LExports.Free();
  end;
end;

class procedure TPCLspCompletion.DoVarargsItems(const APrefix: string;
  const AItems: TList<TPCLspCompletionItem>);
var
  LKind: TPCVarargsKind;
  LWord: string;
  LHead: string;
begin
  // The member words of varargs and of a varargs local (BNF.md sec 6), from
  // the one table (PC_VARARGS_WORDS)
  LHead := PC_VARARGS_WORDS[vaPlain] + '.';
  for LKind := vaCount to vaCopy do
  begin
    LWord := PC_VARARGS_WORDS[LKind];
    case LKind of
      vaCount:
        DoAddWord(AItems, APrefix, LWord, PC_LSP_COMPLETION_FIELD, LHead + LWord,
          PC_LSP_COMPLETION_SORT_DECL, '');
      vaNext:
        DoAddWord(AItems, APrefix, LWord, PC_LSP_COMPLETION_METHOD, LHead + LWord + '(T)',
          PC_LSP_COMPLETION_SORT_DECL, LWord + '($0)');
      vaGet:
        DoAddWord(AItems, APrefix, LWord, PC_LSP_COMPLETION_METHOD, LHead + LWord + '(I, T)',
          PC_LSP_COMPLETION_SORT_DECL, LWord + '($0)');
    else
      DoAddWord(AItems, APrefix, LWord, PC_LSP_COMPLETION_METHOD, LHead + LWord + '()',
        PC_LSP_COMPLETION_SORT_DECL, LWord + '()');
    end;
  end;
end;

class function TPCLspCompletion.DoMethodOwner(const AModule: TPCModule; const AAnchor: UInt64): TPCTypeExpr;
var
  LFrames: TList<TPCScopeFrame>;
  LIndex: Integer;
begin
  // The method around the cursor = the innermost members frame (SEM's
  // DoMethodOwner)
  Result := nil;
  LFrames := TList<TPCScopeFrame>.Create();
  try
    TPCScopes.FramesAt(AModule, AAnchor, LFrames);
    for LIndex := LFrames.Count - 1 downto 0 do
    begin
      if (LFrames[LIndex].FrameKind = fkMembers) and (LFrames[LIndex].Owner is TPCTypeExpr) then
      begin
        Result := TPCTypeExpr(LFrames[LIndex].Owner);
        Break;
      end;
    end;
  finally
    LFrames.Free();
  end;
end;

class procedure TPCLspCompletion.DoAddPromoted(const AModule: TPCModule; const AAnchor: UInt64;
  const ALeft: TPCExpr; const ARecord: TPCTypeExpr; const AFound: TList<TPCNode>);
var
  LHits: TList<TPCPromotedHit>;
  LHit: TPCPromotedHit;
  LEmbed: TPCField;
  LOwner: TPCTypeExpr;
  LSearched: TPCTypeExpr;
  LLevel: TPCTypeExpr;
  LVisible: Boolean;
begin
  // SEM's DoPromote order: each embed on the path is a member of the type
  // searched so far (the record first; parent. searches through self), then
  // the member is judged in the last embedded type
  LOwner := DoMethodOwner(AModule, AAnchor);
  LHits := TList<TPCPromotedHit>.Create();
  try
    TPCScopes.AllPromoted(ARecord, LHits);
    for LHit in LHits do
    begin
      LSearched := ARecord;
      if (ALeft is TPCSpecial) and (TPCSpecial(ALeft).SpecialKind = skParent) then
        LSearched := LOwner;
      LVisible := True;
      for LEmbed in LHit.Path do
      begin
        if (LEmbed.TypeExpr = nil) or
           (TPCScopes.HiddenReach(LEmbed, LSearched, LOwner, LLevel) <> hrVisible) then
        begin
          LVisible := False;
          Break;
        end;
        LSearched := LEmbed.TypeExpr.Canon();
      end;
      if LVisible and (TPCScopes.HiddenReach(LHit.Member, LSearched, LOwner, LLevel) = hrVisible) then
        AFound.Add(LHit.Member);
    end;
  finally
    LHits.Free();
  end;
end;

class procedure TPCLspCompletion.DoDropHidden(const AModule: TPCModule; const AAnchor: UInt64;
  const ALeft: TPCExpr; const ARecord: TPCTypeExpr; const AFound: TList<TPCNode>);
var
  LOwner: TPCTypeExpr;
  LSearched: TPCTypeExpr;
  LLevel: TPCTypeExpr;
  LIndex: Integer;
begin
  // parent.<member> searches through self, as SEM does
  LOwner := DoMethodOwner(AModule, AAnchor);
  LSearched := ARecord;
  if (ALeft is TPCSpecial) and (TPCSpecial(ALeft).SpecialKind = skParent) then
    LSearched := LOwner;
  for LIndex := AFound.Count - 1 downto 0 do
  begin
    if TPCScopes.HiddenReach(AFound[LIndex], LSearched, LOwner, LLevel) <> hrVisible then
      AFound.Delete(LIndex);
  end;
end;

class procedure TPCLspCompletion.DoMemberItems(const AModule: TPCModule;
  const AContext: TPCLspCompletionContext; const AItems: TList<TPCLspCompletionItem>);
var
  LLeft: TPCExpr;
  LImport: TPCImport;
  LTypeDecl: TPCTypeDecl;
  LChoices: TPCChoicesType;
  LValue: TPCChoiceValue;
  LType: TPCTypeExpr;
  LCanon: TPCTypeExpr;
  LRecord: TPCTypeExpr;
  LFound: TList<TPCNode>;
  LHidden: TDictionary<string, Boolean>;
begin
  // varargs.<word> is told by its token (the parser has no node for an
  // unfinished one)
  if AContext.LeftIsVarargs then
  begin
    if AContext.Access = maDot then
      DoVarargsItems(AContext.Prefix, AItems);
    Exit;
  end;
  LLeft := LeftOf(AModule, AContext.QualifierOffset);
  if LLeft = nil then
    Exit;

  LFound := TList<TPCNode>.Create();
  LHidden := TDictionary<string, Boolean>.Create();
  try
    // What the left side names is SEM's resolution, read through the one
    // rule (TPCScopes.HeadImport / HeadTypeDecl / ChoicesOf / MemberRecord);
    // '->' never follows a module or a type (SM0014)
    LImport := TPCScopes.HeadImport(LLeft);
    LTypeDecl := TPCScopes.HeadTypeDecl(LLeft);
    if LImport <> nil then
    begin
      if (AContext.Access = maDot) and (LImport.ImportedModule <> nil) then
        TPCScopes.ModuleMembers(LImport.ImportedModule, LFound);
    end
    else if LTypeDecl <> nil then
    begin
      LChoices := TPCScopes.ChoicesOf(LTypeDecl);
      if (AContext.Access = maDot) and (LChoices <> nil) then
      begin
        for LValue in LChoices.Values do
        begin
          if LValue <> nil then
            LFound.Add(LValue);
        end;
      end;
    end
    else
    begin
      // A value: a varargs local's words, else its record's members (an
      // opaque C/C++ value, a string or a pointer with '.' has none)
      LType := LLeft.ResolvedType;
      if LType = nil then
        Exit;
      LCanon := LType.Canon();
      if (LCanon is TPCBuiltinType) and (TPCBuiltinType(LCanon).BuiltinToken = tkKwVarargs) then
      begin
        if AContext.Access = maDot then
          DoVarargsItems(AContext.Prefix, AItems);
        Exit;
      end;
      LRecord := TPCScopes.MemberRecord(LType, AContext.Access);
      if LRecord <> nil then
      begin
        TPCScopes.AllMembers(LRecord, LFound);
        DoDropHidden(AModule, AContext.QualifierOffset, LLeft, LRecord, LFound);
        DoAddPromoted(AModule, AContext.QualifierOffset, LLeft, LRecord, LFound);
      end;
    end;
    DoAddGroup(LFound, LHidden, AContext.Prefix, AItems);
  finally
    LHidden.Free();
    LFound.Free();
  end;
end;

class function TPCLspCompletion.ContextAt(const AStream: TPCTokenStream;
  const AOffset: UInt64): TPCLspCompletionContext;
var
  LLow: Integer;
  LHigh: Integer;
  LMid: Integer;
  LIndex: Integer;
  LQualifier: Integer;
  LToken: TPCToken;
  LLeft: TPCToken;
begin
  Result := Default(TPCLspCompletionContext);
  Result.HasList := True;
  Result.CursorOffset := AOffset;
  Result.PrefixStart := AOffset;
  // Comments are trivia, not tokens: the lexer kept their spans
  if AStream.InComment(Int64(AOffset)) then
  begin
    Result.HasList := False;
    Exit;
  end;

  // The last token starting before the cursor (tokens ascend; EOF is none)
  LLow := 0;
  LHigh := AStream.Count();
  if (LHigh > 0) and (AStream.TokenAt(LHigh - 1).Kind = tkEOF) then
    Dec(LHigh);
  while LLow < LHigh do
  begin
    LMid := (LLow + LHigh) div 2;
    if AStream.TokenAt(LMid).Range.StartByteOffset < AOffset then
      LLow := LMid + 1
    else
      LHigh := LMid;
  end;
  LIndex := LLow - 1;

  LQualifier := LIndex;
  if LIndex >= 0 then
  begin
    LToken := AStream.TokenAt(LIndex);
    if (LToken.Category in [tcIdentifier, tcKeyword, tcCppKeyword, tcPrimitive]) and
       (AOffset <= LToken.Range.EndByteOffset) then
    begin
      // A word the cursor is in or right after: the part before the cursor
      Result.Prefix := AStream.SourceSlice(LToken.Range.StartByteOffset, AOffset);
      Result.PrefixStart := LToken.Range.StartByteOffset;
      LQualifier := LIndex - 1;
    end
    else if AOffset < LToken.Range.EndByteOffset then
    begin
      // Inside any other token: a literal, an operator, a directive
      Result.HasList := False;
      Exit;
    end
    else if (LToken.Category in [tcPreprocessor, tcVerbatim, tcDirective]) and
            (AOffset = LToken.Range.EndByteOffset) then
    begin
      // A # line runs to its line's end and a cppstart block's text up to
      // cppend: right after them is still inside; so is a directive's word
      Result.HasList := False;
      Exit;
    end;
  end;

  if LQualifier >= 0 then
  begin
    LToken := AStream.TokenAt(LQualifier);
    if (LToken.Kind = tkDot) or (LToken.Kind = tkMinusGreater) then
    begin
      Result.HasQualifier := True;
      if LToken.Kind = tkDot then
        Result.Access := maDot
      else
        Result.Access := maArrow;
      Result.QualifierOffset := LToken.Range.StartByteOffset;
      LLeft := AStream.TokenAt(LQualifier - 1);
      Result.LeftIsVarargs := (LQualifier > 0) and (LLeft.Kind = tkKwVarargs);
    end;
  end;
end;

class function TPCLspCompletion.Items(const AModule: TPCModule;
  const AContext: TPCLspCompletionContext): TArray<TPCLspCompletionItem>;
var
  LItems: TList<TPCLspCompletionItem>;
  LList: TArray<TPCLspCompletionItem>;
  LIndex: Integer;
begin
  Result := nil;
  if (AModule = nil) or not AContext.HasList then
    Exit;
  LItems := TList<TPCLspCompletionItem>.Create();
  try
    if AContext.HasQualifier then
      DoMemberItems(AModule, AContext, LItems)
    else
      DoScopeItems(AModule, AContext, LItems);
    LList := LItems.ToArray();
    // The list is built in rank order: its position goes into sortText
    for LIndex := 0 to High(LList) do
      LList[LIndex].SortText := Format(PC_LSP_COMPLETION_RANK_FORMAT, [LList[LIndex].SortText, LIndex]);
    Result := LList;
  finally
    LItems.Free();
  end;
end;

end.
