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
  PaskalCPP.Scopes - The scope rule: frames, visible counts, name collection

  The one place PaskalCPP's scope rule lives (research\cppmix\sem\scopes.md).
  A frame holds no names: it points at the AST lists of its owner and says
  how many items of each are visible. Semantics pushes these frames while it
  walks; the LSP builds the same frames at a cursor. Both collect through
  Collect / CollectAll, so a name SEM resolves and a name completion offers
  come from one rule.

  Dependencies: StdApp.Base, PaskalCPP.AST
===============================================================================}

unit PaskalCPP.Scopes;

interface

uses
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.AST;

type

  { TPCFrameKind }
  // One scope frame kind (research\cppmix\sem\scopes.md frame table)
  TPCFrameKind = (fkSystem, fkModule, fkMembers, fkRoutine, fkTest, fkChoices, fkList);

  { TPCHiddenReach }
  // TPCScopes.HiddenReach: whether a member access may name a hidden member
  // (PLAN-OBJECT D10); hrVisible also for a member that is not hidden
  TPCHiddenReach = (hrVisible, hrOutside, hrThrough);

  { TPCPromotedHit }
  // TPCScopes.FindPromoted (PLAN-OBJECT O8, D2): one embed path a name
  // reaches. Member = the field, or the method's routine; Path = the embeds
  // walked from the searched type, outermost first; Hops = the member parents
  // stepped through inside the last embedded type (FindMember's AHops)
  TPCPromotedHit = record
    Member: TPCNode;
    Path: TArray<TPCField>;
    Hops: Integer;
  end;

  { TPCScopeFrame }
  // One frame of a scope chain. It holds no name: every lookup walks the AST
  // lists it points at, up to the visible counts
  TPCScopeFrame = record
    FrameKind: TPCFrameKind;
    Owner: TPCNode;               // module, routine, test, record type, choices type, list owner
    TypeDecl: TPCTypeDecl;        // fkMembers: the declaration whose TypeDef is Owner (nil = anonymous)
    Imports: TList<TPCImport>;    // fkModule
    Params: TList<TPCParam>;      // fkRoutine
    First: TList<TPCStmt>;        // module / routine / test Decls, or the fkList list
    FirstCount: Integer;          // visible items of First (fkChoices: the value being analyzed)
    Second: TList<TPCStmt>;       // routine / test Body.Stmts
    SecondCount: Integer;
    Current: TPCStmt;             // the item being analyzed; nil between items
  end;

  { TPCScopes }
  // The scope rule as static routines over frames and AST nodes. A new frame
  // shows nothing of its lists (counts 0) until its owner says how far it
  // reaches (VisibleCount, or the list's full count once walked)
  TPCScopes = record
  private
    class procedure DoCollectDecls(const AItems: TList<TPCStmt>; const ACount: Integer;
      const AFound: TList<TPCNode>); static;
    class procedure DoCollectMembersAll(const AMembers: TList<TPCMemberItem>;
      const AHidden: TDictionary<string, Boolean>; const ALevel: TDictionary<string, Boolean>;
      const AFound: TList<TPCNode>); static;
    class function DoMemberName(const AItem: TPCMemberItem): string; static;
    class function DoAccessorOf(const AAccessor: TPCAccessorItem; const AMember: TPCNode): TPCMemberItem; static;
    class function DoParentLevel(const AType: TPCTypeExpr): TPCTypeExpr; static;
    class procedure DoChainEmbeds(const AType: TPCTypeExpr; const AEmbeds: TList<TPCField>); static;
    class function DoImplementsBase(const ALevel: TPCRecordType; const ABase: TPCTypeExpr): Boolean; static;
    class function DoHolds(const ARange: TSourceRange; const AAnchor: UInt64): Boolean; static;
    class function DoPick(const AParts: TList<TPCNode>; const AAnchor: UInt64): Integer; static;
    class function DoIsOpen(const ANode: TPCNode): Boolean; static;
    class function DoPickList(const AList: TList<TPCStmt>; const AAnchor: UInt64): Integer; static;
    class function DoEndingBefore(const AList: TList<TPCStmt>; const AAnchor: UInt64): Integer; static;
    class procedure DoList(const AFrames: TList<TPCScopeFrame>; const ATop: Integer;
      const AList: TList<TPCStmt>; const AFirst: Boolean; const AAnchor: UInt64); static;
    class procedure DoNested(const AFrames: TList<TPCScopeFrame>; const AOwner: TPCStmt;
      const AList: TList<TPCStmt>; const AAnchor: UInt64); static;
    class procedure DoItem(const AFrames: TList<TPCScopeFrame>; const AStmt: TPCStmt;
      const AAnchor: UInt64); static;
    class procedure DoRoutine(const AFrames: TList<TPCScopeFrame>; const ARoutine: TPCRoutine;
      const AAnchor: UInt64); static;
    class procedure DoTest(const AFrames: TList<TPCScopeFrame>; const ATest: TPCTest;
      const AAnchor: UInt64); static;
    class procedure DoTypeExpr(const AFrames: TList<TPCScopeFrame>; const AType: TPCTypeExpr;
      const ATypeDecl: TPCTypeDecl; const AAnchor: UInt64); static;
    class procedure DoMembers(const AFrames: TList<TPCScopeFrame>; const AOwner: TPCTypeExpr;
      const ATypeDecl: TPCTypeDecl; const AMembers: TList<TPCMemberItem>; const AAnchor: UInt64); static;
    class procedure DoProperty(const AFrames: TList<TPCScopeFrame>; const AOwner: TPCTypeExpr;
      const ATypeDecl: TPCTypeDecl; const AProperty: TPCPropertyItem; const AAnchor: UInt64); static;
  public
    // A frame of AKind owned by AOwner, every list empty
    class function MakeFrame(const AKind: TPCFrameKind; const AOwner: TPCNode): TPCScopeFrame; static;
    // The frame of each owner, as Semantics pushes it
    class function SystemFrame(): TPCScopeFrame; static;
    class function ModuleFrame(const AModule: TPCModule): TPCScopeFrame; static;
    class function RoutineFrame(const ARoutine: TPCRoutine): TPCScopeFrame; static;
    class function TestFrame(const ATest: TPCTest): TPCScopeFrame; static;
    // A method's view of its object's members; ATypeDecl = the declaration
    // whose TypeDef is AType (nil = anonymous)
    class function MembersFrame(const AType: TPCTypeExpr; const ATypeDecl: TPCTypeDecl): TPCScopeFrame; static;
    // A nested statement list (a block, then / else, a match arm ...): the
    // owner alone does not say which of its lists it is
    class function ListFrame(const AOwner: TPCStmt; const AList: TList<TPCStmt>): TPCScopeFrame; static;
    class function ChoicesFrame(const AChoices: TPCChoicesType): TPCScopeFrame; static;

    // The items of AList visible to its item at AIndex: the items before it;
    // a routine also sees itself (its params, return type, body: recursion)
    class function VisibleCount(const AList: TList<TPCStmt>; const AIndex: Integer): Integer; static;

    // Every visible name AName declares in AFrame, list order
    class procedure Collect(const AFrame: TPCScopeFrame; const AName: string;
      const AFound: TList<TPCNode>); static;
    // Every declaration Collect could return for AFrame, for any name, list
    // order (members: the nearest level that names it, as FindMember)
    class procedure CollectAll(const AFrame: TPCScopeFrame; const AFound: TList<TPCNode>); static;

    // The members named AName of ONE type level (fields, methods' routines),
    // anonymous aggregates hoisted; no parents
    class procedure CollectMembersNamed(const AMembers: TList<TPCMemberItem>; const AName: string;
      const AFound: TList<TPCNode>); static;
    // The members named AName of a record / overlay type: its own level, then
    // its parents; the nearest level with a match hides the rest
    class procedure FindMember(const AType: TPCTypeExpr; const AName: string;
      const AFound: TList<TPCNode>); overload; static;
    // FindMember; AHops = the member parents (TPCRecordType.HasParentMember)
    // stepped through to the level that matched (PLAN-RECORDS M10); 0 = none matched
    class procedure FindMember(const AType: TPCTypeExpr; const AName: string;
      const AFound: TList<TPCNode>; out AHops: Integer); overload; static;
    // PLAN-OBJECT O8 (D2): the members AName reaches through the embeds of
    // AType's chain, for a name the chain itself does not declare (FindMember
    // first: own and inherited members win). Depth by depth, Go's rule: each
    // embed of a level of the chain is searched with FindMember; the nearest
    // depth with a hit ends the walk and every hit of it is returned (two =
    // a name two embeds share: the use reports it). Hidden members and embeds
    // are returned too: whether the use may reach them is the use's check
    class procedure FindPromoted(const AType: TPCTypeExpr; const AName: string;
      const AHits: TList<TPCPromotedHit>); static;
    // PLAN-OBJECT O14: FindPromoted for every name at once (the editor's
    // member list after '.'): for each name, the hit FindPromoted would give
    // it; a name the chain declares, or that two embed paths of its nearest
    // depth reach (the use's SM0370), is left out. Every member of a name
    // in one embedded type is kept (overloads). Hidden members and embeds
    // are returned: the caller asks HiddenReach
    class procedure AllPromoted(const AType: TPCTypeExpr; const AHits: TList<TPCPromotedHit>); static;
    // FindMember's walk ends at a C/C++ parent (record(CPoint), at any level):
    // a name no PaskalCPP level declares may be that parent's, so it is
    // clang's to judge (F20)
    class function ReachesOpaque(const AType: TPCTypeExpr): Boolean; overload; static;
    // ReachesOpaque; AHops = the member parents stepped through to the record
    // whose parent is C/C++ (that record derives from it in C++)
    class function ReachesOpaque(const AType: TPCTypeExpr; out AHops: Integer): Boolean; overload; static;
    // Every member FindMember could return, nearest level first, one level per name
    class procedure AllMembers(const AType: TPCTypeExpr; const AFound: TList<TPCNode>); static;
    // PLAN-RECORDS R4: AType is a record extension of ABase: ABase's record is
    // a level ABOVE AType's on the member-parent walk (records are nominal: Canon
    // node identity). False for AType = ABase, an object (PLAN-OBJECT owns its
    // upcast), a C/C++ level (the opaque tier takes those), nil. AHops = the
    // levels between them (0 when False)
    class function Extends(const AType: TPCTypeExpr; const ABase: TPCTypeExpr): Boolean; overload; static;
    class function Extends(const AType: TPCTypeExpr; const ABase: TPCTypeExpr;
      out AHops: Integer): Boolean; overload; static;
    // PLAN-OBJECT D6 / D7: AType is an object whose PaskalCPP object chain
    // reaches ABase's object ABOVE it (a C++ base class: C++ converts a
    // pointer and binds a reference by itself). False for AType = ABase, a
    // record (Extends), a C/C++ level, nil
    class function Derives(const AType: TPCTypeExpr; const ABase: TPCTypeExpr): Boolean; static;

    // ALevel is AType itself or a level up its parent chain (FindMember's
    // walk: objects and records alike); both canonical record types
    class function ReachesLevel(const AType: TPCTypeExpr; const ALevel: TPCTypeExpr): Boolean; static;
    // The member item that declares AMember (a TPCField, or a method's
    // TPCRoutine) at ALevel's own members, anonymous aggregates searched; nil
    // when that level does not declare it
    class function MemberItemOf(const ALevel: TPCTypeExpr; const AMember: TPCNode): TPCMemberItem; static;
    // The level of AType's chain that declares AMember, nil = none
    class function DeclaringLevel(const AType: TPCTypeExpr; const AMember: TPCNode): TPCTypeExpr; static;
    // PLAN-OBJECT D10, the one hidden rule (C++'s protected rule, so clang
    // never judges one first): AMember, found by searching ASearched (the
    // record a '.' / '->' searches; self's type for self. and parent.), is
    // reached from a method of AOwner (nil = outside every method). hrOutside:
    // AOwner is not the declaring level nor below it; hrThrough: it is, but
    // ASearched is not AOwner nor below it. ALevel = the declaring level
    class function HiddenReach(const AMember: TPCNode; const ASearched: TPCTypeExpr;
      const AOwner: TPCTypeExpr; out ALevel: TPCTypeExpr): TPCHiddenReach; static;

    // A forward whose full declaration is also in AFound drops out
    class procedure CollapseForwards(const AFound: TList<TPCNode>); static;

    // M.AName: AFound gets the exported declarations; Result = AModule
    // declares the name at all (exported or not)
    class function ModuleMember(const AModule: TPCModule; const AName: string;
      const AFound: TList<TPCNode>): Boolean; static;
    // Every exported declaration of AModule, list order, forwards collapsed
    class procedure ModuleMembers(const AModule: TPCModule; const AFound: TList<TPCNode>); static;

    // What the head of a qualified name (ABase '.' Name) names, as SEM
    // resolved ABase: the import a one-part name resolved to (a module head),
    // else nil
    class function HeadImport(const ABase: TPCExpr): TPCImport; static;
    // The type declaration a name or member resolved to (a type head), as
    // resolved (a forward stays a forward), else nil
    class function HeadTypeDecl(const ABase: TPCExpr): TPCTypeDecl; static;
    // The choices type a type declaration defines, a forward through its full
    // declaration; nil for anything else (only a choices type has names
    // reached with '.')
    class function ChoicesOf(const ATypeDecl: TPCTypeDecl): TPCChoicesType; static;

    // The record / overlay a member access on a value of ABaseType searches:
    // '.' the type itself, '->' its pointer's target; nil for anything else
    // (a '.' on a pointer, an untyped ptr, opaque C/C++, no type)
    class function MemberRecord(const ABaseType: TPCTypeExpr; const AAccess: TPCMemberAccess): TPCTypeExpr; static;

    // The frames SEM has pushed when it reaches byte AAnchor of AModule's
    // file (system and module first, innermost last), each with the counts
    // of the items it sees there (VisibleCount): LSP completion and the
    // debugger's variables read one rule
    class procedure FramesAt(const AModule: TPCModule; const AAnchor: UInt64;
      const AFrames: TList<TPCScopeFrame>); static;
  end;

implementation

const
  { PC_SCOPES_EMBED_DEPTH_MAX }
  // FindPromoted's walk stops after this many embed depths: a bound for a
  // walk over a tree a broken program may make deep, far past any real one
  PC_SCOPES_EMBED_DEPTH_MAX = 64;

{ TPCScopes }

class function TPCScopes.MakeFrame(const AKind: TPCFrameKind; const AOwner: TPCNode): TPCScopeFrame;
begin
  Result := Default(TPCScopeFrame);
  Result.FrameKind := AKind;
  Result.Owner := AOwner;
end;

class function TPCScopes.SystemFrame(): TPCScopeFrame;
begin
  Result := MakeFrame(fkSystem, nil);
end;

class function TPCScopes.ModuleFrame(const AModule: TPCModule): TPCScopeFrame;
begin
  Result := MakeFrame(fkModule, AModule);
  if AModule = nil then
    Exit;
  Result.Imports := AModule.Imports;
  Result.First := AModule.Decls;
end;

class function TPCScopes.RoutineFrame(const ARoutine: TPCRoutine): TPCScopeFrame;
begin
  Result := MakeFrame(fkRoutine, ARoutine);
  if ARoutine = nil then
    Exit;
  Result.Params := ARoutine.Params;
  Result.First := ARoutine.Decls;
  if ARoutine.Body <> nil then
    Result.Second := ARoutine.Body.Stmts;
end;

class function TPCScopes.TestFrame(const ATest: TPCTest): TPCScopeFrame;
begin
  Result := MakeFrame(fkTest, ATest);
  if ATest = nil then
    Exit;
  Result.First := ATest.Decls;
  if ATest.Body <> nil then
    Result.Second := ATest.Body.Stmts;
end;

class function TPCScopes.MembersFrame(const AType: TPCTypeExpr; const ATypeDecl: TPCTypeDecl): TPCScopeFrame;
begin
  Result := MakeFrame(fkMembers, AType);
  Result.TypeDecl := ATypeDecl;
end;

class function TPCScopes.ListFrame(const AOwner: TPCStmt; const AList: TList<TPCStmt>): TPCScopeFrame;
begin
  Result := MakeFrame(fkList, AOwner);
  Result.First := AList;
end;

class function TPCScopes.ChoicesFrame(const AChoices: TPCChoicesType): TPCScopeFrame;
begin
  Result := MakeFrame(fkChoices, AChoices);
end;

class function TPCScopes.VisibleCount(const AList: TList<TPCStmt>; const AIndex: Integer): Integer;
begin
  Result := AIndex;
  if (AList = nil) or (AIndex < 0) or (AIndex >= AList.Count) then
    Exit;
  if AList[AIndex] is TPCRoutine then
    Result := AIndex + 1;
end;

class procedure TPCScopes.Collect(const AFrame: TPCScopeFrame; const AName: string;
  const AFound: TList<TPCNode>);
var
  LDecls: TList<TPCDecl>;
  LDecl: TPCDecl;
  LImport: TPCImport;
  LParam: TPCParam;
  LChoices: TPCChoicesType;
  LIndex: Integer;
  LBefore: Integer;
  LHits: TList<TPCPromotedHit>;
  LHit: TPCPromotedHit;
begin
  // The names one frame declares that are visible now; CollectNamed takes a
  // TList<TPCDecl> (generics are invariant), so a local list carries them
  if AFrame.FrameKind = fkSystem then
    Exit;
  if AFrame.FrameKind = fkMembers then
  begin
    if AFrame.Owner is TPCTypeExpr then
    begin
      LBefore := AFound.Count;
      FindMember(TPCTypeExpr(AFrame.Owner), AName, AFound);
      // PLAN-OBJECT O8: a name an embed provides is the object's member too
      // (a bare use of it is SM0018, as of any member)
      if AFound.Count = LBefore then
      begin
        LHits := TList<TPCPromotedHit>.Create();
        try
          FindPromoted(TPCTypeExpr(AFrame.Owner), AName, LHits);
          for LHit in LHits do
            AFound.Add(LHit.Member);
        finally
          LHits.Free();
        end;
      end;
    end;
    Exit;
  end;
  if AFrame.FrameKind = fkChoices then
  begin
    LChoices := TPCChoicesType(AFrame.Owner);
    for LIndex := 0 to LChoices.Values.Count - 1 do
    begin
      if LIndex >= AFrame.FirstCount then
        Break;
      if (LChoices.Values[LIndex] <> nil) and (LChoices.Values[LIndex].ValueName = AName) then
        AFound.Add(LChoices.Values[LIndex]);
    end;
    Exit;
  end;

  if AFrame.Imports <> nil then
  begin
    for LImport in AFrame.Imports do
    begin
      if (LImport <> nil) and (LImport.ModuleName = AName) then
        AFound.Add(LImport);
    end;
  end;
  if AFrame.Params <> nil then
  begin
    for LParam in AFrame.Params do
    begin
      if (LParam <> nil) and (LParam.ParamName = AName) then
        AFound.Add(LParam);
    end;
  end;
  LDecls := TList<TPCDecl>.Create();
  try
    TPCDecl.CollectNamed(AFrame.First, AFrame.FirstCount, AName, LDecls);
    TPCDecl.CollectNamed(AFrame.Second, AFrame.SecondCount, AName, LDecls);
    for LDecl in LDecls do
      AFound.Add(LDecl);
  finally
    LDecls.Free();
  end;
end;

class procedure TPCScopes.DoCollectDecls(const AItems: TList<TPCStmt>; const ACount: Integer;
  const AFound: TList<TPCNode>);
var
  LIndex: Integer;
  LLast: Integer;
  LStmt: TPCStmt;
begin
  // The same items CollectNamed walks (count clamped, verbatim skipped), any
  // name; a declaration with no name is one no Collect can return
  if AItems = nil then
    Exit;
  LLast := ACount;
  if LLast > AItems.Count then
    LLast := AItems.Count;
  for LIndex := 0 to LLast - 1 do
  begin
    LStmt := AItems[LIndex];
    if (LStmt is TPCDecl) and (TPCDecl(LStmt).DeclName <> '') then
      AFound.Add(LStmt);
  end;
end;

class procedure TPCScopes.CollectAll(const AFrame: TPCScopeFrame; const AFound: TList<TPCNode>);
var
  LImport: TPCImport;
  LParam: TPCParam;
  LChoices: TPCChoicesType;
  LIndex: Integer;
begin
  // Collect's walk with the name test dropped, frame for frame
  if AFrame.FrameKind = fkSystem then
    Exit;
  if AFrame.FrameKind = fkMembers then
  begin
    if AFrame.Owner is TPCTypeExpr then
      AllMembers(TPCTypeExpr(AFrame.Owner), AFound);
    Exit;
  end;
  if AFrame.FrameKind = fkChoices then
  begin
    LChoices := TPCChoicesType(AFrame.Owner);
    for LIndex := 0 to LChoices.Values.Count - 1 do
    begin
      if LIndex >= AFrame.FirstCount then
        Break;
      if (LChoices.Values[LIndex] <> nil) and (LChoices.Values[LIndex].ValueName <> '') then
        AFound.Add(LChoices.Values[LIndex]);
    end;
    Exit;
  end;

  if AFrame.Imports <> nil then
  begin
    for LImport in AFrame.Imports do
    begin
      if (LImport <> nil) and (LImport.ModuleName <> '') then
        AFound.Add(LImport);
    end;
  end;
  if AFrame.Params <> nil then
  begin
    for LParam in AFrame.Params do
    begin
      if (LParam <> nil) and (LParam.ParamName <> '') then
        AFound.Add(LParam);
    end;
  end;
  DoCollectDecls(AFrame.First, AFrame.FirstCount, AFound);
  DoCollectDecls(AFrame.Second, AFrame.SecondCount, AFound);
end;

class procedure TPCScopes.CollectMembersNamed(const AMembers: TList<TPCMemberItem>; const AName: string;
  const AFound: TList<TPCNode>);
var
  LItem: TPCMemberItem;
begin
  // Fields and methods of one type level, anonymous aggregates hoisted (S21)
  if AMembers = nil then
    Exit;
  for LItem in AMembers do
  begin
    if (LItem is TPCField) and (TPCField(LItem).FieldName = AName) then
      AFound.Add(LItem)
    else if (LItem is TPCMethodItem) and (TPCMethodItem(LItem).Routine <> nil) and
      (TPCMethodItem(LItem).Routine.DeclName = AName) then
      AFound.Add(TPCMethodItem(LItem).Routine)
    // PLAN-OBJECT O9: a property is found as itself (its accessors have no name)
    else if (LItem is TPCPropertyItem) and (TPCPropertyItem(LItem).PropName = AName) then
      AFound.Add(LItem)
    else if LItem is TPCAnonAggregate then
      CollectMembersNamed(TPCAnonAggregate(LItem).Members, AName, AFound);
  end;
end;

class function TPCScopes.DoMemberName(const AItem: TPCMemberItem): string;
begin
  // The name a member item declares at its level; '' = none (an anonymous
  // aggregate declares its members, not itself)
  Result := '';
  if AItem is TPCField then
    Result := TPCField(AItem).FieldName
  else if (AItem is TPCMethodItem) and (TPCMethodItem(AItem).Routine <> nil) then
    Result := TPCMethodItem(AItem).Routine.DeclName
  else if AItem is TPCPropertyItem then
    Result := TPCPropertyItem(AItem).PropName;
end;

class function TPCScopes.DoAccessorOf(const AAccessor: TPCAccessorItem; const AMember: TPCNode): TPCMemberItem;
begin
  // AAccessor when AMember is it or its inline routine; nil otherwise
  Result := nil;
  if AAccessor = nil then
    Exit;
  if (AMember = AAccessor) or ((AAccessor.Routine <> nil) and (AAccessor.Routine = AMember)) then
    Result := AAccessor;
end;

class procedure TPCScopes.DoCollectMembersAll(const AMembers: TList<TPCMemberItem>;
  const AHidden: TDictionary<string, Boolean>; const ALevel: TDictionary<string, Boolean>;
  const AFound: TList<TPCNode>);
var
  LItem: TPCMemberItem;
  LName: string;
begin
  // One level, aggregates hoisted; a name a nearer level declared is hidden
  // (AHidden), every name of this level is noted for the levels after it (ALevel)
  if AMembers = nil then
    Exit;
  for LItem in AMembers do
  begin
    if LItem is TPCAnonAggregate then
    begin
      DoCollectMembersAll(TPCAnonAggregate(LItem).Members, AHidden, ALevel, AFound);
      Continue;
    end;
    LName := DoMemberName(LItem);
    if (LName = '') or AHidden.ContainsKey(LName) then
      Continue;
    if LItem is TPCMethodItem then
      AFound.Add(TPCMethodItem(LItem).Routine)
    else
      AFound.Add(LItem);
    ALevel.AddOrSetValue(LName, True);
  end;
end;

class function TPCScopes.DoParentLevel(const AType: TPCTypeExpr): TPCTypeExpr;
begin
  // The next level up: a record's parent; nil when there is none
  Result := nil;
  if (AType is TPCRecordType) and (TPCRecordType(AType).ParentName <> nil) then
    Result := TPCRecordType(AType).ParentName.Canon();
end;

class procedure TPCScopes.FindMember(const AType: TPCTypeExpr; const AName: string;
  const AFound: TList<TPCNode>);
var
  LHops: Integer;
begin
  FindMember(AType, AName, AFound, LHops);
end;

class procedure TPCScopes.FindMember(const AType: TPCTypeExpr; const AName: string;
  const AFound: TList<TPCNode>; out AHops: Integer);
var
  LType: TPCTypeExpr;
  LVisited: TList<TPCTypeExpr>;
  LHops: Integer;
begin
  // The type's own level, then its parents; the nearest level hides the rest
  // (C++ name hiding); a parent that is no record ends the walk silently.
  // A step up from a record whose parent is a member (M10) is one hop
  AHops := 0;
  LHops := 0;
  LVisited := TList<TPCTypeExpr>.Create();
  try
    LType := AType;
    while ((LType is TPCRecordType) or (LType is TPCOverlayType)) and (not LVisited.Contains(LType)) do
    begin
      LVisited.Add(LType);
      if LType is TPCRecordType then
        CollectMembersNamed(TPCRecordType(LType).Members, AName, AFound)
      else
        CollectMembersNamed(TPCOverlayType(LType).Members, AName, AFound);
      if AFound.Count > 0 then
      begin
        AHops := LHops;
        Break;
      end;
      if (LType is TPCRecordType) and TPCRecordType(LType).HasParentMember() then
        Inc(LHops);
      LType := DoParentLevel(LType);
    end;
  finally
    LVisited.Free();
  end;
end;

class procedure TPCScopes.DoChainEmbeds(const AType: TPCTypeExpr; const AEmbeds: TList<TPCField>);
var
  LType: TPCTypeExpr;
  LVisited: TList<TPCTypeExpr>;
  LItem: TPCMemberItem;
begin
  // The embeds every level of AType's chain declares, nearest level first
  // (FindMember's walk and cycle guard; an object holds no anonymous
  // aggregate, so its own member list is the whole level)
  LVisited := TList<TPCTypeExpr>.Create();
  try
    LType := AType;
    while (LType is TPCRecordType) and (not LVisited.Contains(LType)) do
    begin
      LVisited.Add(LType);
      for LItem in TPCRecordType(LType).Members do
      begin
        if (LItem is TPCField) and TPCField(LItem).IsEmbed then
          AEmbeds.Add(TPCField(LItem));
      end;
      LType := DoParentLevel(LType);
    end;
  finally
    LVisited.Free();
  end;
end;

class procedure TPCScopes.FindPromoted(const AType: TPCTypeExpr; const AName: string;
  const AHits: TList<TPCPromotedHit>);
var
  LFrontier: TList<TPCTypeExpr>;
  LPaths: TList<TArray<TPCField>>;
  LNextTypes: TList<TPCTypeExpr>;
  LNextPaths: TList<TArray<TPCField>>;
  LEmbeds: TList<TPCField>;
  LFound: TList<TPCNode>;
  LEmbed: TPCField;
  LTarget: TPCTypeExpr;
  LPath: TArray<TPCField>;
  LHit: TPCPromotedHit;
  LIndex: Integer;
  LStep: Integer;
  LDepth: Integer;
  LHops: Integer;
  LCycle: Boolean;
begin
  // Breadth first, one depth per round: the frontier holds the types the
  // previous depth reached without a hit (with the path to each). A path
  // that would enter a type it already holds is a cycle (a type that holds
  // itself by value: SEM's report) and is not followed
  if (AType = nil) or (AName = '') then
    Exit;
  LFrontier := TList<TPCTypeExpr>.Create();
  LPaths := TList<TArray<TPCField>>.Create();
  LNextTypes := TList<TPCTypeExpr>.Create();
  LNextPaths := TList<TArray<TPCField>>.Create();
  LEmbeds := TList<TPCField>.Create();
  LFound := TList<TPCNode>.Create();
  try
    LFrontier.Add(AType);
    LPaths.Add(nil);
    LDepth := 0;
    while (LFrontier.Count > 0) and (AHits.Count = 0) and (LDepth < PC_SCOPES_EMBED_DEPTH_MAX) do
    begin
      Inc(LDepth);
      LNextTypes.Clear();
      LNextPaths.Clear();
      for LIndex := 0 to LFrontier.Count - 1 do
      begin
        LEmbeds.Clear();
        DoChainEmbeds(LFrontier[LIndex], LEmbeds);
        for LEmbed in LEmbeds do
        begin
          if LEmbed.TypeExpr = nil then
            Continue;
          LTarget := LEmbed.TypeExpr.Canon();
          if not ((LTarget is TPCRecordType) or (LTarget is TPCOverlayType)) then
            Continue;
          LCycle := LTarget = AType;
          for LStep := 0 to High(LPaths[LIndex]) do
          begin
            if (LPaths[LIndex][LStep].TypeExpr <> nil) and (LPaths[LIndex][LStep].TypeExpr.Canon() = LTarget) then
              LCycle := True;
          end;
          if LCycle then
            Continue;
          LPath := Copy(LPaths[LIndex], 0, Length(LPaths[LIndex]));
          SetLength(LPath, Length(LPath) + 1);
          LPath[High(LPath)] := LEmbed;
          LFound.Clear();
          FindMember(LTarget, AName, LFound, LHops);
          if LFound.Count > 0 then
          begin
            LHit.Member := LFound[0];
            LHit.Path := LPath;
            LHit.Hops := LHops;
            AHits.Add(LHit);
          end
          else
          begin
            LNextTypes.Add(LTarget);
            LNextPaths.Add(LPath);
          end;
        end;
      end;
      LFrontier.Clear();
      LFrontier.AddRange(LNextTypes);
      LPaths.Clear();
      LPaths.AddRange(LNextPaths);
    end;
  finally
    LFound.Free();
    LEmbeds.Free();
    LNextPaths.Free();
    LNextTypes.Free();
    LPaths.Free();
    LFrontier.Free();
  end;
end;

class procedure TPCScopes.AllPromoted(const AType: TPCTypeExpr; const AHits: TList<TPCPromotedHit>);
var
  LTaken: TDictionary<string, Boolean>;
  LNamePath: TDictionary<string, Integer>;
  LAmbiguous: TDictionary<string, Boolean>;
  LRound: TList<TPCPromotedHit>;
  LFrontier: TList<TPCTypeExpr>;
  LPaths: TList<TArray<TPCField>>;
  LNextTypes: TList<TPCTypeExpr>;
  LNextPaths: TList<TArray<TPCField>>;
  LEmbeds: TList<TPCField>;
  LFound: TList<TPCNode>;
  LNamed: TList<TPCNode>;
  LNode: TPCNode;
  LEmbed: TPCField;
  LTarget: TPCTypeExpr;
  LPath: TArray<TPCField>;
  LHit: TPCPromotedHit;
  LName: string;
  LRange: TSourceRange;
  LIndex: Integer;
  LStep: Integer;
  LDepth: Integer;
  LPathIndex: Integer;
  LHops: Integer;
  LCycle: Boolean;
begin
  // FindPromoted's breadth-first walk (same frontier, cycle guard and depth
  // bound), every name at once: LTaken holds the names the chain declares
  // and the names a nearer depth settled; within one depth LNamePath notes
  // the first embed path a name came from, and a second path makes the
  // name ambiguous (FindPromoted would return both hits: the use reports
  // SM0370), so it is left out. Unlike FindPromoted every embed is followed
  // to the next depth: names it did not settle may lie further down
  if AType = nil then
    Exit;
  LTaken := TDictionary<string, Boolean>.Create();
  LNamePath := TDictionary<string, Integer>.Create();
  LAmbiguous := TDictionary<string, Boolean>.Create();
  LRound := TList<TPCPromotedHit>.Create();
  LFrontier := TList<TPCTypeExpr>.Create();
  LPaths := TList<TArray<TPCField>>.Create();
  LNextTypes := TList<TPCTypeExpr>.Create();
  LNextPaths := TList<TArray<TPCField>>.Create();
  LEmbeds := TList<TPCField>.Create();
  LFound := TList<TPCNode>.Create();
  LNamed := TList<TPCNode>.Create();
  try
    // Own and inherited members win (FindMember first)
    AllMembers(AType, LFound);
    for LNode in LFound do
    begin
      if TPCAst.DeclaredName(LNode, LName, LRange) then
        LTaken.AddOrSetValue(LName, True);
    end;

    LFrontier.Add(AType);
    LPaths.Add(nil);
    LDepth := 0;
    LPathIndex := 0;
    while (LFrontier.Count > 0) and (LDepth < PC_SCOPES_EMBED_DEPTH_MAX) do
    begin
      Inc(LDepth);
      LNextTypes.Clear();
      LNextPaths.Clear();
      LRound.Clear();
      LNamePath.Clear();
      LAmbiguous.Clear();
      for LIndex := 0 to LFrontier.Count - 1 do
      begin
        LEmbeds.Clear();
        DoChainEmbeds(LFrontier[LIndex], LEmbeds);
        for LEmbed in LEmbeds do
        begin
          if LEmbed.TypeExpr = nil then
            Continue;
          LTarget := LEmbed.TypeExpr.Canon();
          if not ((LTarget is TPCRecordType) or (LTarget is TPCOverlayType)) then
            Continue;
          LCycle := LTarget = AType;
          for LStep := 0 to High(LPaths[LIndex]) do
          begin
            if (LPaths[LIndex][LStep].TypeExpr <> nil) and (LPaths[LIndex][LStep].TypeExpr.Canon() = LTarget) then
              LCycle := True;
          end;
          if LCycle then
            Continue;
          LPath := Copy(LPaths[LIndex], 0, Length(LPaths[LIndex]));
          SetLength(LPath, Length(LPath) + 1);
          LPath[High(LPath)] := LEmbed;
          Inc(LPathIndex);

          LFound.Clear();
          AllMembers(LTarget, LFound);
          for LNode in LFound do
          begin
            if (not TPCAst.DeclaredName(LNode, LName, LRange)) or LTaken.ContainsKey(LName) then
              Continue;
            if LNamePath.ContainsKey(LName) and (LNamePath[LName] <> LPathIndex) then
              LAmbiguous.AddOrSetValue(LName, True)
            else
              LNamePath.AddOrSetValue(LName, LPathIndex);
            // The hops FindMember counts for the name inside the embedded type
            LNamed.Clear();
            FindMember(LTarget, LName, LNamed, LHops);
            LHit.Member := LNode;
            LHit.Path := LPath;
            LHit.Hops := LHops;
            LRound.Add(LHit);
          end;
          LNextTypes.Add(LTarget);
          LNextPaths.Add(LPath);
        end;
      end;

      for LHit in LRound do
      begin
        if TPCAst.DeclaredName(LHit.Member, LName, LRange) and (not LAmbiguous.ContainsKey(LName)) then
          AHits.Add(LHit);
      end;
      // This depth's names (ambiguous ones too) hide the same names deeper
      for LName in LNamePath.Keys do
        LTaken.AddOrSetValue(LName, True);
      LFrontier.Clear();
      LFrontier.AddRange(LNextTypes);
      LPaths.Clear();
      LPaths.AddRange(LNextPaths);
    end;
  finally
    LNamed.Free();
    LFound.Free();
    LEmbeds.Free();
    LNextPaths.Free();
    LNextTypes.Free();
    LPaths.Free();
    LFrontier.Free();
    LRound.Free();
    LAmbiguous.Free();
    LNamePath.Free();
    LTaken.Free();
  end;
end;

class function TPCScopes.ReachesOpaque(const AType: TPCTypeExpr): Boolean;
var
  LHops: Integer;
begin
  Result := ReachesOpaque(AType, LHops);
end;

class function TPCScopes.ReachesOpaque(const AType: TPCTypeExpr; out AHops: Integer): Boolean;
var
  LType: TPCTypeExpr;
  LVisited: TList<TPCTypeExpr>;
  LHops: Integer;
begin
  // FindMember's walk (same levels, same cycle guard); True at the first
  // record level whose parent is of the opaque tier; AHops = the member
  // parents stepped through to that level. AType may be a name for the
  // record (a pointer's target): its Canon is walked, as Extends does
  Result := False;
  AHops := 0;
  LHops := 0;
  if AType = nil then
    Exit;
  LVisited := TList<TPCTypeExpr>.Create();
  try
    LType := AType.Canon();
    while (LType is TPCRecordType) and (not LVisited.Contains(LType)) do
    begin
      LVisited.Add(LType);
      if TPCTypeExpr.IsOpaqueTier(TPCRecordType(LType).ParentName) then
      begin
        AHops := LHops;
        Exit(True);
      end;
      if TPCRecordType(LType).HasParentMember() then
        Inc(LHops);
      LType := DoParentLevel(LType);
    end;
  finally
    LVisited.Free();
  end;
end;

class procedure TPCScopes.AllMembers(const AType: TPCTypeExpr; const AFound: TList<TPCNode>);
var
  LType: TPCTypeExpr;
  LVisited: TList<TPCTypeExpr>;
  LHidden: TDictionary<string, Boolean>;
  LLevel: TDictionary<string, Boolean>;
  LName: string;
begin
  // FindMember's walk for every name at once: a name stops at the first
  // level that declares it, so a level adds only names no nearer level had
  LVisited := TList<TPCTypeExpr>.Create();
  LHidden := TDictionary<string, Boolean>.Create();
  LLevel := TDictionary<string, Boolean>.Create();
  try
    LType := AType;
    while ((LType is TPCRecordType) or (LType is TPCOverlayType)) and (not LVisited.Contains(LType)) do
    begin
      LVisited.Add(LType);
      LLevel.Clear();
      if LType is TPCRecordType then
        DoCollectMembersAll(TPCRecordType(LType).Members, LHidden, LLevel, AFound)
      else
        DoCollectMembersAll(TPCOverlayType(LType).Members, LHidden, LLevel, AFound);
      // This level's names hide the same names further up; within one level
      // every member of a name is kept (overloads), as FindMember keeps them
      for LName in LLevel.Keys do
        LHidden.AddOrSetValue(LName, True);
      LType := DoParentLevel(LType);
    end;
  finally
    LLevel.Free();
    LHidden.Free();
    LVisited.Free();
  end;
end;

class function TPCScopes.Extends(const AType: TPCTypeExpr; const ABase: TPCTypeExpr): Boolean;
var
  LHops: Integer;
begin
  Result := Extends(AType, ABase, LHops);
end;

class function TPCScopes.Extends(const AType: TPCTypeExpr; const ABase: TPCTypeExpr;
  out AHops: Integer): Boolean;
var
  LType: TPCTypeExpr;
  LBase: TPCTypeExpr;
  LVisited: TList<TPCTypeExpr>;
begin
  // FindMember's walk (same levels, same cycle guard) through member parents
  // only: one hop per level; the first level that IS ABase's record answers
  Result := False;
  AHops := 0;
  if (AType = nil) or (ABase = nil) then
    Exit;
  LBase := ABase.Canon();
  LType := AType.Canon();
  LVisited := TList<TPCTypeExpr>.Create();
  try
    while (LType is TPCRecordType) and TPCRecordType(LType).HasParentMember() and
      (not LVisited.Contains(LType)) do
    begin
      LVisited.Add(LType);
      Inc(AHops);
      LType := DoParentLevel(LType);
      if LType = LBase then
        Exit(True);
    end;
  finally
    LVisited.Free();
  end;
  AHops := 0;
end;

class function TPCScopes.DoImplementsBase(const ALevel: TPCRecordType; const ABase: TPCTypeExpr): Boolean;
var
  LName: TPCNamedType;
  LFace: TPCTypeExpr;
  LVisited: TList<TPCTypeExpr>;
begin
  // PLAN-OBJECT O7: one of ALevel's implements names, or a parent interface
  // of it, is ABase (canon). The walk climbs interfaces only (never back into
  // an object: a mistaken chain cannot recurse), each level once
  Result := False;
  LVisited := TList<TPCTypeExpr>.Create();
  try
    for LName in ALevel.Implements do
    begin
      LFace := LName.Canon();
      while (LFace is TPCRecordType) and TPCRecordType(LFace).IsInterface and (not LVisited.Contains(LFace)) do
      begin
        if LFace = ABase then
          Exit(True);
        LVisited.Add(LFace);
        LFace := DoParentLevel(LFace);
      end;
    end;
  finally
    LVisited.Free();
  end;
end;

class function TPCScopes.Derives(const AType: TPCTypeExpr; const ABase: TPCTypeExpr): Boolean;
var
  LType: TPCTypeExpr;
  LBase: TPCTypeExpr;
  LVisited: TList<TPCTypeExpr>;
begin
  // FindMember's walk (same levels, same cycle guard) through object parents
  // only: the first level above AType that IS ABase's object answers. An
  // interface counts too (PLAN-OBJECT O7): one a level implements, or a parent
  // interface of one (an interface's parent is its ParentName level)
  Result := False;
  if (AType = nil) or (ABase = nil) then
    Exit;
  LBase := ABase.Canon();
  LType := AType.Canon();
  if not ((LBase is TPCRecordType) and TPCRecordType(LBase).IsObject) then
    Exit;
  LVisited := TList<TPCTypeExpr>.Create();
  try
    while (LType is TPCRecordType) and TPCRecordType(LType).IsObject and (not LVisited.Contains(LType)) do
    begin
      LVisited.Add(LType);
      if DoImplementsBase(TPCRecordType(LType), LBase) then
        Exit(True);
      LType := DoParentLevel(LType);
      if LType = LBase then
        Exit(True);
    end;
  finally
    LVisited.Free();
  end;
end;

class function TPCScopes.ReachesLevel(const AType: TPCTypeExpr; const ALevel: TPCTypeExpr): Boolean;
var
  LType: TPCTypeExpr;
  LVisited: TList<TPCTypeExpr>;
begin
  // FindMember's walk (same levels, same cycle guard), every parent kind
  Result := False;
  if (AType = nil) or (ALevel = nil) then
    Exit;
  LVisited := TList<TPCTypeExpr>.Create();
  try
    LType := AType;
    while ((LType is TPCRecordType) or (LType is TPCOverlayType)) and (not LVisited.Contains(LType)) do
    begin
      if LType = ALevel then
        Exit(True);
      LVisited.Add(LType);
      LType := DoParentLevel(LType);
    end;
  finally
    LVisited.Free();
  end;
end;

class function TPCScopes.MemberItemOf(const ALevel: TPCTypeExpr; const AMember: TPCNode): TPCMemberItem;
var
  LStack: TList<TList<TPCMemberItem>>;
  LMembers: TList<TPCMemberItem>;
  LItem: TPCMemberItem;
begin
  // One level's members, anonymous aggregates walked (an explicit stack: the
  // parser bounds their nesting, the walk needs no recursion)
  Result := nil;
  if (AMember = nil) or not ((ALevel is TPCRecordType) or (ALevel is TPCOverlayType)) then
    Exit;
  LStack := TList<TList<TPCMemberItem>>.Create();
  try
    if ALevel is TPCRecordType then
      LStack.Add(TPCRecordType(ALevel).Members)
    else
      LStack.Add(TPCOverlayType(ALevel).Members);
    while LStack.Count > 0 do
    begin
      LMembers := LStack[LStack.Count - 1];
      LStack.Delete(LStack.Count - 1);
      if LMembers = nil then
        Continue;
      for LItem in LMembers do
      begin
        if LItem = AMember then
          Exit(LItem);
        // A method's, an init's or a done's routine is held by its member item
        if (LItem is TPCRoutineMember) and (TPCRoutineMember(LItem).Routine = AMember) then
          Exit(LItem);
        // PLAN-OBJECT O9: a property's accessor (or its routine) is that
        // accessor item: its own hidden (`hidden write`) is judged on it
        if LItem is TPCPropertyItem then
        begin
          Result := DoAccessorOf(TPCPropertyItem(LItem).ReadItem, AMember);
          if Result = nil then
            Result := DoAccessorOf(TPCPropertyItem(LItem).WriteItem, AMember);
          if Result <> nil then
            Exit;
        end;
        if LItem is TPCAnonAggregate then
          LStack.Add(TPCAnonAggregate(LItem).Members);
      end;
    end;
  finally
    LStack.Free();
  end;
end;

class function TPCScopes.DeclaringLevel(const AType: TPCTypeExpr; const AMember: TPCNode): TPCTypeExpr;
var
  LType: TPCTypeExpr;
  LVisited: TList<TPCTypeExpr>;
begin
  // FindMember's walk; the first level whose own members hold AMember
  Result := nil;
  LVisited := TList<TPCTypeExpr>.Create();
  try
    LType := AType;
    while ((LType is TPCRecordType) or (LType is TPCOverlayType)) and (not LVisited.Contains(LType)) do
    begin
      if MemberItemOf(LType, AMember) <> nil then
        Exit(LType);
      LVisited.Add(LType);
      LType := DoParentLevel(LType);
    end;
  finally
    LVisited.Free();
  end;
end;

class function TPCScopes.HiddenReach(const AMember: TPCNode; const ASearched: TPCTypeExpr;
  const AOwner: TPCTypeExpr; out ALevel: TPCTypeExpr): TPCHiddenReach;
var
  LItem: TPCMemberItem;
begin
  // C++ protected: a method of the declaring type reaches it through any
  // value of a type at or below it (that holds it already: it was found
  // there); a descendant's method only through a value of its own type or
  // below (self, parent., a value of the descendant's type)
  Result := hrVisible;
  ALevel := DeclaringLevel(ASearched, AMember);
  LItem := MemberItemOf(ALevel, AMember);
  if (LItem = nil) or (not LItem.IsHidden) then
    Exit;
  if not ReachesLevel(AOwner, ALevel) then
    Exit(hrOutside);
  if not ReachesLevel(ASearched, AOwner) then
    Exit(hrThrough);
end;

class procedure TPCScopes.CollapseForwards(const AFound: TList<TPCNode>);
var
  LIndex: Integer;
  LNode: TPCNode;
  LFull: TPCNode;
begin
  for LIndex := AFound.Count - 1 downto 0 do
  begin
    LNode := AFound[LIndex];
    LFull := nil;
    if (LNode is TPCTypeDecl) and TPCTypeDecl(LNode).IsForward then
      LFull := TPCTypeDecl(LNode).ResolvedFull
    else if (LNode is TPCRoutine) and TPCRoutine(LNode).IsForward then
      LFull := TPCRoutine(LNode).ResolvedFull;
    if (LFull <> nil) and AFound.Contains(LFull) then
      AFound.Delete(LIndex);
  end;
end;

class function TPCScopes.ModuleMember(const AModule: TPCModule; const AName: string;
  const AFound: TList<TPCNode>): Boolean;
var
  LDecls: TList<TPCDecl>;
  LDecl: TPCDecl;
begin
  // The imported module is complete (analyzed first): every decl; AFound gets
  // the exported ones; Result = the module declares the name at all
  LDecls := TList<TPCDecl>.Create();
  try
    TPCDecl.CollectNamed(AModule.Decls, AModule.Decls.Count, AName, LDecls);
    Result := LDecls.Count > 0;
    for LDecl in LDecls do
    begin
      if LDecl.IsExported then
        AFound.Add(LDecl);
    end;
  finally
    LDecls.Free();
  end;
  CollapseForwards(AFound);
end;

class procedure TPCScopes.ModuleMembers(const AModule: TPCModule; const AFound: TList<TPCNode>);
var
  LStmt: TPCStmt;
begin
  // ModuleMember's rule for every name: the exported declarations only
  if (AModule = nil) or (AModule.Decls = nil) then
    Exit;
  for LStmt in AModule.Decls do
  begin
    if (LStmt is TPCDecl) and (TPCDecl(LStmt).DeclName <> '') and TPCDecl(LStmt).IsExported then
      AFound.Add(LStmt);
  end;
  CollapseForwards(AFound);
end;

class function TPCScopes.HeadImport(const ABase: TPCExpr): TPCImport;
begin
  // Was Semantics DoResolveMember (1)'s test: only a plain name is a module
  // head (a member never names a module)
  Result := nil;
  if (ABase is TPCName) and (TPCName(ABase).ResolvedKind = rkModule) and
     (TPCName(ABase).ResolvedDecl is TPCImport) then
    Result := TPCImport(TPCName(ABase).ResolvedDecl);
end;

class function TPCScopes.HeadTypeDecl(const ABase: TPCExpr): TPCTypeDecl;
var
  LDecl: TPCNode;
  LKind: TPCResolvedKind;
begin
  // Was Semantics DoResolveMember (2)'s test: a name or a member (M.T)
  // resolved to a type declaration
  Result := nil;
  LDecl := nil;
  LKind := rkNone;
  if ABase is TPCName then
  begin
    LDecl := TPCName(ABase).ResolvedDecl;
    LKind := TPCName(ABase).ResolvedKind;
  end
  else if ABase is TPCMember then
  begin
    LDecl := TPCMember(ABase).ResolvedDecl;
    LKind := TPCMember(ABase).ResolvedKind;
  end;
  if (LKind = rkType) and (LDecl is TPCTypeDecl) then
    Result := TPCTypeDecl(LDecl);
end;

class function TPCScopes.ChoicesOf(const ATypeDecl: TPCTypeDecl): TPCChoicesType;
var
  LDecl: TPCTypeDecl;
  LCanon: TPCTypeExpr;
begin
  Result := nil;
  LDecl := ATypeDecl;
  if (LDecl <> nil) and LDecl.IsForward then
    LDecl := LDecl.ResolvedFull;
  if (LDecl = nil) or (LDecl.TypeDef = nil) then
    Exit;
  LCanon := LDecl.TypeDef.Canon();
  if LCanon is TPCChoicesType then
    Result := TPCChoicesType(LCanon);
end;

class function TPCScopes.MemberRecord(const ABaseType: TPCTypeExpr;
  const AAccess: TPCMemberAccess): TPCTypeExpr;
var
  LCanon: TPCTypeExpr;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
begin
  // Was TPCSemantics.DoMemberRecord + DoValueMember's own test (one rule)
  Result := nil;
  if ABaseType = nil then
    Exit;
  LCanon := ABaseType.Canon();
  if AAccess = maArrow then
  begin
    if not TPCTypeExpr.PointerOf(LCanon, LTarget, LIsConst) or (LTarget = nil) then
      Exit;
    LCanon := LTarget.Canon();
  end
  else if (LCanon is TPCOwnerType) and (TPCOwnerType(LCanon).OwnerKind <> okWeak) and
    (TPCOwnerType(LCanon).TargetType <> nil) then
    // PLAN-OBJECT O6 (Q2): `LO.X` on an own / ref reads its object
    LCanon := TPCOwnerType(LCanon).TargetType.Canon();
  if (LCanon is TPCRecordType) or (LCanon is TPCOverlayType) then
    Result := LCanon;
end;

class function TPCScopes.DoHolds(const ARange: TSourceRange; const AAnchor: UInt64): Boolean;
begin
  // Half open: text typed at a node's first byte belongs to it, text typed
  // right after its last byte (after a closing ';') does not
  Result := (ARange.EndByteOffset > ARange.StartByteOffset) and
    (ARange.StartByteOffset <= AAnchor) and (AAnchor < ARange.EndByteOffset);
end;

class function TPCScopes.DoPick(const AParts: TList<TPCNode>; const AAnchor: UInt64): Integer;
var
  LIndex: Integer;
  LLast: Integer;
begin
  // The part that holds the anchor; else the last part starting before it
  // when the parser did not finish it (a routine missing its end while the
  // rest of the file is still being typed reaches up to the next part)
  for LIndex := 0 to AParts.Count - 1 do
  begin
    if (AParts[LIndex] <> nil) and DoHolds(AParts[LIndex].Range, AAnchor) then
      Exit(LIndex);
  end;
  LLast := -1;
  for LIndex := 0 to AParts.Count - 1 do
  begin
    if (AParts[LIndex] <> nil) and (AParts[LIndex].Range.StartByteOffset <= AAnchor) then
      LLast := LIndex;
  end;
  if (LLast >= 0) and (AParts[LLast].IsRecovered or DoIsOpen(AParts[LLast])) then
    Exit(LLast);
  Result := -1;
end;

class function TPCScopes.DoIsOpen(const ANode: TPCNode): Boolean;
var
  LBody: TPCBlock;
begin
  // A block whose end is not typed yet (TPCBlock.EndRange, parser), or a
  // routine / test whose body is one: what follows it is still inside it
  LBody := nil;
  if ANode is TPCBlock then
    LBody := TPCBlock(ANode)
  else if ANode is TPCRoutine then
    LBody := TPCRoutine(ANode).Body
  else if ANode is TPCTest then
    LBody := TPCTest(ANode).Body;
  Result := (LBody <> nil) and (LBody.EndRange.StartLine = 0);
end;

class function TPCScopes.DoPickList(const AList: TList<TPCStmt>; const AAnchor: UInt64): Integer;
var
  LParts: TList<TPCNode>;
  LStmt: TPCStmt;
begin
  // DoPick takes nodes (generics are invariant)
  Result := -1;
  if AList = nil then
    Exit;
  LParts := TList<TPCNode>.Create();
  try
    for LStmt in AList do
      LParts.Add(LStmt);
    Result := DoPick(LParts, AAnchor);
  finally
    LParts.Free();
  end;
end;

class function TPCScopes.DoEndingBefore(const AList: TList<TPCStmt>; const AAnchor: UInt64): Integer;
var
  LIndex: Integer;
begin
  // Between items: SEM has finished every item that ends before the anchor
  Result := 0;
  if AList = nil then
    Exit;
  for LIndex := 0 to AList.Count - 1 do
  begin
    if (AList[LIndex] <> nil) and (AList[LIndex].Range.EndByteOffset > AAnchor) then
      Exit(LIndex);
  end;
  Result := AList.Count;
end;

class procedure TPCScopes.DoList(const AFrames: TList<TPCScopeFrame>; const ATop: Integer;
  const AList: TList<TPCStmt>; const AFirst: Boolean; const AAnchor: UInt64);
var
  LIndex: Integer;
  LCount: Integer;
begin
  // SEM's DoItemList at the anchor: the item holding it sees the items
  // before it (a routine itself too); between items, the items ending before
  if AList = nil then
    Exit;
  LIndex := DoPickList(AList, AAnchor);
  if LIndex >= 0 then
    LCount := TPCScopes.VisibleCount(AList, LIndex)
  else
    LCount := DoEndingBefore(AList, AAnchor);
  if AFirst then
    AFrames.List[ATop].FirstCount := LCount
  else
    AFrames.List[ATop].SecondCount := LCount;
  if LIndex >= 0 then
    DoItem(AFrames, AList[LIndex], AAnchor);
end;

class procedure TPCScopes.DoNested(const AFrames: TList<TPCScopeFrame>; const AOwner: TPCStmt;
  const AList: TList<TPCStmt>; const AAnchor: UInt64);
begin
  // SEM's DoNestedList: one frame over the construct's own list
  if AList = nil then
    Exit;
  AFrames.Add(TPCScopes.ListFrame(AOwner, AList));
  DoList(AFrames, AFrames.Count - 1, AList, True, AAnchor);
end;

class procedure TPCScopes.DoItem(const AFrames: TList<TPCScopeFrame>; const AStmt: TPCStmt;
  const AAnchor: UInt64);
var
  LIf: TPCIf;
  LMatch: TPCMatch;
  LGuard: TPCGuard;
  LRepeat: TPCRepeat;
  LArm: TPCMatchArm;
begin
  // SEM's DoStmt: the constructs that open a frame (Semantics DoStmt,
  // DoForStmt, DoMatchStmt, DoGuardStmt); a list is the one the anchor is in
  if AStmt = nil then
    Exit;
  if AStmt is TPCRoutine then
    DoRoutine(AFrames, TPCRoutine(AStmt), AAnchor)
  else if AStmt is TPCTypeDecl then
    DoTypeExpr(AFrames, TPCTypeDecl(AStmt).TypeDef, TPCTypeDecl(AStmt), AAnchor)
  else if AStmt is TPCBlock then
    DoNested(AFrames, AStmt, TPCBlock(AStmt).Stmts, AAnchor)
  else if AStmt is TPCIf then
  begin
    LIf := TPCIf(AStmt);
    if LIf.HasElse and (LIf.ElseRange.StartByteOffset <= AAnchor) then
      DoNested(AFrames, AStmt, LIf.ElseStmts, AAnchor)
    else
      DoNested(AFrames, AStmt, LIf.ThenStmts, AAnchor);
  end
  else if AStmt is TPCWhile then
    DoNested(AFrames, AStmt, TPCWhile(AStmt).Stmts, AAnchor)
  else if AStmt is TPCFor then
    DoNested(AFrames, AStmt, TPCFor(AStmt).Stmts, AAnchor)
  else if AStmt is TPCRepeat then
  begin
    // The until condition is in the enclosing frame (scopes.md)
    LRepeat := TPCRepeat(AStmt);
    if (LRepeat.UntilRange.StartLine = 0) or (AAnchor < LRepeat.UntilRange.StartByteOffset) then
      DoNested(AFrames, AStmt, LRepeat.Stmts, AAnchor);
  end
  else if AStmt is TPCMatch then
  begin
    LMatch := TPCMatch(AStmt);
    if LMatch.HasElse and (LMatch.ElseRange.StartByteOffset <= AAnchor) then
      DoNested(AFrames, AStmt, LMatch.ElseStmts, AAnchor)
    else
    begin
      for LArm in LMatch.Arms do
      begin
        if (LArm <> nil) and DoHolds(LArm.Range, AAnchor) then
        begin
          DoNested(AFrames, AStmt, LArm.Stmts, AAnchor);
          Break;
        end;
      end;
    end;
  end
  else if AStmt is TPCGuard then
  begin
    LGuard := TPCGuard(AStmt);
    if LGuard.HasFinally and (LGuard.FinallyRange.StartByteOffset <= AAnchor) then
      DoNested(AFrames, AStmt, LGuard.FinallyStmts, AAnchor)
    else if LGuard.HasExcept and (LGuard.ExceptRange.StartByteOffset <= AAnchor) then
      DoNested(AFrames, AStmt, LGuard.ExceptStmts, AAnchor)
    else
      DoNested(AFrames, AStmt, LGuard.GuardStmts, AAnchor);
  end
  else if (AStmt is TPCErrorStmt) and (TPCErrorStmt(AStmt).Fragment is TPCStmt) then
    // A fragment the parser kept is walked as SEM walks it
    DoItem(AFrames, TPCStmt(TPCErrorStmt(AStmt).Fragment), AAnchor);
end;

class procedure TPCScopes.DoRoutine(const AFrames: TList<TPCScopeFrame>; const ARoutine: TPCRoutine;
  const AAnchor: UInt64);
var
  LInside: Boolean;
  LDecl: TPCStmt;
  LParts: TList<TPCNode>;
  LIndex: Integer;
  LTop: Integer;
begin
  if ARoutine = nil then
    Exit;
  // The header (params, return type) resolves in the enclosing frames: SEM
  // pushes the routine's own frame after it (Semantics DoRoutine)
  LInside := (ARoutine.Body <> nil) and (ARoutine.Body.Range.StartByteOffset <= AAnchor);
  if not LInside then
  begin
    for LDecl in ARoutine.Decls do
    begin
      if LDecl <> nil then
      begin
        LInside := LDecl.Range.StartByteOffset <= AAnchor;
        Break;
      end;
    end;
  end;
  if not LInside then
    Exit;

  AFrames.Add(TPCScopes.RoutineFrame(ARoutine));
  LTop := AFrames.Count - 1;
  LParts := TList<TPCNode>.Create();
  try
    for LDecl in ARoutine.Decls do
      LParts.Add(LDecl);
    if ARoutine.Body <> nil then
      LParts.Add(ARoutine.Body);
    LIndex := DoPick(LParts, AAnchor);
  finally
    LParts.Free();
  end;

  if (LIndex >= 0) and (LIndex < ARoutine.Decls.Count) then
  begin
    AFrames.List[LTop].FirstCount := TPCScopes.VisibleCount(ARoutine.Decls, LIndex);
    DoItem(AFrames, ARoutine.Decls[LIndex], AAnchor);
  end
  else if LIndex >= 0 then
  begin
    // The body: every declaration block was analysed before it
    AFrames.List[LTop].FirstCount := ARoutine.Decls.Count;
    DoList(AFrames, LTop, ARoutine.Body.Stmts, False, AAnchor);
  end
  else
    AFrames.List[LTop].FirstCount := DoEndingBefore(ARoutine.Decls, AAnchor);
end;

class procedure TPCScopes.DoTest(const AFrames: TList<TPCScopeFrame>; const ATest: TPCTest;
  const AAnchor: UInt64);
var
  LDecl: TPCStmt;
  LParts: TList<TPCNode>;
  LIndex: Integer;
  LTop: Integer;
begin
  // A test's name is a string (no list there); everything else is in its frame
  if ATest = nil then
    Exit;
  AFrames.Add(TPCScopes.TestFrame(ATest));
  LTop := AFrames.Count - 1;
  LParts := TList<TPCNode>.Create();
  try
    for LDecl in ATest.Decls do
      LParts.Add(LDecl);
    if ATest.Body <> nil then
      LParts.Add(ATest.Body);
    LIndex := DoPick(LParts, AAnchor);
  finally
    LParts.Free();
  end;

  if (LIndex >= 0) and (LIndex < ATest.Decls.Count) then
  begin
    AFrames.List[LTop].FirstCount := TPCScopes.VisibleCount(ATest.Decls, LIndex);
    DoItem(AFrames, ATest.Decls[LIndex], AAnchor);
  end
  else if LIndex >= 0 then
  begin
    AFrames.List[LTop].FirstCount := ATest.Decls.Count;
    DoList(AFrames, LTop, ATest.Body.Stmts, False, AAnchor);
  end
  else
    AFrames.List[LTop].FirstCount := DoEndingBefore(ATest.Decls, AAnchor);
end;

class procedure TPCScopes.DoTypeExpr(const AFrames: TList<TPCScopeFrame>; const AType: TPCTypeExpr;
  const ATypeDecl: TPCTypeDecl; const AAnchor: UInt64);
var
  LChoices: TPCChoicesType;
  LIndex: Integer;
  LFrame: TPCScopeFrame;
  LChild: TPCTypeExpr;
begin
  // A type's own frames: a method sees its type's members (Semantics
  // DoMemberItem), a choice value's expression the values before it
  // (DoChoicesType); a type nested in another (an array of records) is
  // reached through its parent
  if AType = nil then
    Exit;
  if AType is TPCRecordType then
    DoMembers(AFrames, AType, ATypeDecl, TPCRecordType(AType).Members, AAnchor)
  else if AType is TPCOverlayType then
    DoMembers(AFrames, AType, ATypeDecl, TPCOverlayType(AType).Members, AAnchor)
  else if AType is TPCChoicesType then
  begin
    LChoices := TPCChoicesType(AType);
    for LIndex := 0 to LChoices.Values.Count - 1 do
    begin
      if (LChoices.Values[LIndex] <> nil) and DoHolds(LChoices.Values[LIndex].Range, AAnchor) then
      begin
        LFrame := TPCScopes.ChoicesFrame(LChoices);
        LFrame.FirstCount := LIndex;
        AFrames.Add(LFrame);
        Exit;
      end;
    end;
  end
  else
  begin
    LChild := nil;
    AType.EnumChildren(
      procedure(const ANode: TPCNode)
      begin
        if (ANode is TPCTypeExpr) and TPCScopes.DoHolds(ANode.Range, AAnchor) then
          LChild := TPCTypeExpr(ANode);
      end);
    if LChild <> nil then
      DoTypeExpr(AFrames, LChild, nil, AAnchor);
  end;
end;

class procedure TPCScopes.DoMembers(const AFrames: TList<TPCScopeFrame>; const AOwner: TPCTypeExpr;
  const ATypeDecl: TPCTypeDecl; const AMembers: TList<TPCMemberItem>; const AAnchor: UInt64);
var
  LParts: TList<TPCNode>;
  LItem: TPCMemberItem;
  LIndex: Integer;
begin
  if AMembers = nil then
    Exit;
  LParts := TList<TPCNode>.Create();
  try
    for LItem in AMembers do
      LParts.Add(LItem);
    LIndex := DoPick(LParts, AAnchor);
  finally
    LParts.Free();
  end;
  if LIndex < 0 then
    Exit;

  LItem := AMembers[LIndex];
  if LItem is TPCAnonAggregate then
    // An anonymous aggregate's members belong to the type that holds it
    DoMembers(AFrames, AOwner, ATypeDecl, TPCAnonAggregate(LItem).Members, AAnchor)
  else if (LItem is TPCRoutineMember) and (TPCRoutineMember(LItem).Routine <> nil) then
  begin
    // method (an init, a done) -> its type's members -> the enclosing frames
    // (Q1); the type's declaration only for a type item's own definition
    // (SEM's Current)
    AFrames.Add(TPCScopes.MembersFrame(AOwner, ATypeDecl));
    DoRoutine(AFrames, TPCRoutineMember(LItem).Routine, AAnchor);
  end
  else if LItem is TPCPropertyItem then
    // PLAN-OBJECT O9: inside an inline accessor, as inside a method
    DoProperty(AFrames, AOwner, ATypeDecl, TPCPropertyItem(LItem), AAnchor)
  else if LItem is TPCField then
    DoTypeExpr(AFrames, TPCField(LItem).TypeExpr, nil, AAnchor);
end;

class procedure TPCScopes.DoProperty(const AFrames: TList<TPCScopeFrame>; const AOwner: TPCTypeExpr;
  const ATypeDecl: TPCTypeDecl; const AProperty: TPCPropertyItem; const AAnchor: UInt64);
var
  LAccessor: TPCAccessorItem;
  LIndex: Integer;
begin
  // The inline accessor holding the anchor: its type's members, then its
  // routine; elsewhere in the property (its type) the type's frames
  for LIndex := 0 to 1 do
  begin
    if LIndex = 0 then
      LAccessor := AProperty.ReadItem
    else
      LAccessor := AProperty.WriteItem;
    if (LAccessor <> nil) and (LAccessor.Routine <> nil) and DoHolds(LAccessor.Range, AAnchor) then
    begin
      AFrames.Add(TPCScopes.MembersFrame(AOwner, ATypeDecl));
      DoRoutine(AFrames, LAccessor.Routine, AAnchor);
      Exit;
    end;
  end;
  DoTypeExpr(AFrames, AProperty.TypeExpr, nil, AAnchor);
end;

class procedure TPCScopes.FramesAt(const AModule: TPCModule; const AAnchor: UInt64;
  const AFrames: TList<TPCScopeFrame>);
var
  LParts: TList<TPCNode>;
  LDecl: TPCStmt;
  LTest: TPCTest;
  LIndex: Integer;
  LTop: Integer;
  LPart: TPCNode;
begin
  // Semantics DoAnalyzeModule's order: the module's items, initialize,
  // finalize, the body, the tests; every part after the items sees them all
  AFrames.Add(TPCScopes.SystemFrame());
  if AModule = nil then
    Exit;
  AFrames.Add(TPCScopes.ModuleFrame(AModule));
  LTop := AFrames.Count - 1;
  LParts := TList<TPCNode>.Create();
  try
    for LDecl in AModule.Decls do
      LParts.Add(LDecl);
    LParts.Add(AModule.InitRoutine);
    LParts.Add(AModule.FinalRoutine);
    if AModule.HasBody then
      LParts.Add(AModule.Body)
    else
      LParts.Add(nil);
    for LTest in AModule.Tests do
      LParts.Add(LTest);
    LIndex := DoPick(LParts, AAnchor);
    if LIndex >= 0 then
      LPart := LParts[LIndex]
    else
      LPart := nil;
  finally
    LParts.Free();
  end;

  if LIndex < 0 then
    AFrames.List[LTop].FirstCount := DoEndingBefore(AModule.Decls, AAnchor)
  else if LIndex < AModule.Decls.Count then
  begin
    AFrames.List[LTop].FirstCount := TPCScopes.VisibleCount(AModule.Decls, LIndex);
    DoItem(AFrames, AModule.Decls[LIndex], AAnchor);
  end
  else
  begin
    AFrames.List[LTop].FirstCount := AModule.Decls.Count;
    if LPart is TPCRoutine then
      DoRoutine(AFrames, TPCRoutine(LPart), AAnchor)
    else if LPart is TPCTest then
      DoTest(AFrames, TPCTest(LPart), AAnchor)
    else if LPart is TPCBlock then
      // The module body: one list over the module frame (Semantics DoBlock)
      DoNested(AFrames, TPCBlock(LPart), TPCBlock(LPart).Stmts, AAnchor);
  end;
end;

end.
