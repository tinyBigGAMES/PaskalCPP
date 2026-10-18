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
  UTestCase.Scopes - The scope rule (PaskalCPP.Scopes) on an analyzed module

  TTestCase suite for TPCScopes: VisibleCount, Collect against CollectAll on
  every frame kind, FindMember / AllMembers (parent level hidden by the
  child's name, anonymous overlay hoisted, object method), ModuleMember(s)
  (exported only) and CollapseForwards. The fixture is analyzed by the real
  parser + semantics (UTestFrontend.DoWithSem): parents resolve, forwards
  pair. Fixtures: tests\probe\lsp\scopes, written by scripts\zb_ed\gen_scopes.py.

  Dependencies: StdApp.TestCase, StdApp.Base, PaskalCPP.AST, PaskalCPP.Scopes,
    UTestFrontend
===============================================================================}

unit UTestCase.Scopes;

interface

uses
  System.Generics.Collections,
  StdApp.TestCase,
  PaskalCPP.AST;

type

  { TPCScopesTests }
  TPCScopesTests = class(TTestCase)
  private
    // One test per concern; Create registers each under its CLI name
    procedure DoTestVisibleCount();
    procedure DoTestCollectAllModule();
    procedure DoTestCollectPartial();
    procedure DoTestCollectForward();
    procedure DoTestMembers();
    procedure DoTestHidden();
    procedure DoTestHops();
    procedure DoCheckFind(const AType: TPCTypeExpr; const AName: string; const AFound: TList<TPCNode>;
      const ACount: Integer; const AHops: Integer; const ALabel: string);
    procedure DoTestModuleMembers();
    procedure DoTestImported();
    procedure DoTestChoicesRoutine();
    procedure DoTestSystem();
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  StdApp.Base,
  PaskalCPP.Scopes,
  UTestFrontend;

const
  { SCOPES_MAX_ERRORS }
  SCOPES_MAX_ERRORS = 100;

type
  { TPCImportRow }
  // One FindImported lookup over sk04_imp and what it must give: the holders'
  // module names and the found declarations' names, space separated
  TPCImportRow = record
    LookupName: string;
    HolderNames: string;
    FoundNames: string;
  end;

const
  { IMPORT_ROWS }
  IMPORT_ROWS: array[0..8] of TPCImportRow = (
    (LookupName: 'OnlyA'; HolderNames: 'sk04_a'; FoundNames: 'OnlyA'),
    (LookupName: 'OnlyB'; HolderNames: 'sk04_b'; FoundNames: 'OnlyB'),
    // Two units export it: both are holders, nothing decides between them
    (LookupName: 'Both'; HolderNames: 'sk04_a sk04_b'; FoundNames: 'Both Both'),
    // Other parameter types in each unit: still two holders (no merging)
    (LookupName: 'Two'; HolderNames: 'sk04_a sk04_b'; FoundNames: 'Two Two'),
    // One unit's overload set: one holder, the whole set
    (LookupName: 'Over'; HolderNames: 'sk04_a'; FoundNames: 'Over Over'),
    // Declared but not exported; a unit's own import; the lib's own name; none
    (LookupName: 'Hid'; HolderNames: ''; FoundNames: ''),
    (LookupName: 'Deep'; HolderNames: ''; FoundNames: ''),
    (LookupName: 'KA'; HolderNames: ''; FoundNames: ''),
    (LookupName: 'Nope'; HolderNames: ''; FoundNames: '')
  );

function DoHoldersText(const AHolders: TList<TPCImport>): string;
var
  LHolder: TPCImport;
begin
  // The holders' module names in order, space separated
  Result := '';
  for LHolder in AHolders do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + LHolder.ModuleName;
  end;
end;

function DoFixture(): string;
begin
  Result := TPath.Combine(DoProbeDir('lsp\scopes'), 'sk01_scopes.pcpp');
end;

function DoNameOf(const ANode: TPCNode): string;
begin
  // The name a collected node declares, by its class
  Result := '?';
  if ANode is TPCDecl then
    Result := TPCDecl(ANode).DeclName
  else if ANode is TPCParam then
    Result := TPCParam(ANode).ParamName
  else if ANode is TPCField then
    Result := TPCField(ANode).FieldName
  else if ANode is TPCChoiceValue then
    Result := TPCChoiceValue(ANode).ValueName
  else if ANode is TPCImport then
    Result := TPCImport(ANode).ModuleName;
end;

function DoNamesText(const AFound: TList<TPCNode>): string;
var
  LNode: TPCNode;
begin
  // Every collected name in order, space separated: a failure shows the list
  Result := '';
  for LNode in AFound do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + DoNameOf(LNode);
  end;
end;

function DoItemsText(const AList: TList<TPCStmt>): string;
var
  LStmt: TPCStmt;
begin
  // Every item's class and name: a failure shows what the list really holds
  Result := '';
  for LStmt in AList do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + LStmt.ClassName();
    if LStmt is TPCDecl then
      Result := Result + ':' + TPCDecl(LStmt).DeclName;
  end;
end;

function DoDeclIndex(const AList: TList<TPCStmt>; const ADeclName: string): Integer;
var
  LIndex: Integer;
begin
  // The first item of AList declaring ADeclName; -1 = none
  Result := -1;
  for LIndex := 0 to AList.Count - 1 do
  begin
    if (AList[LIndex] is TPCDecl) and (TPCDecl(AList[LIndex]).DeclName = ADeclName) then
      Exit(LIndex);
  end;
end;

function DoTypeDefOf(const AModule: TPCModule; const ADeclName: string): TPCTypeExpr;
var
  LIndex: Integer;
begin
  Result := nil;
  LIndex := DoDeclIndex(AModule.Decls, ADeclName);
  if (LIndex >= 0) and (AModule.Decls[LIndex] is TPCTypeDecl) then
    Result := TPCTypeDecl(AModule.Decls[LIndex]).TypeDef;
end;

function DoRoutineOf(const AModule: TPCModule; const ADeclName: string): TPCRoutine;
var
  LIndex: Integer;
begin
  Result := nil;
  LIndex := DoDeclIndex(AModule.Decls, ADeclName);
  if (LIndex >= 0) and (AModule.Decls[LIndex] is TPCRoutine) then
    Result := TPCRoutine(AModule.Decls[LIndex]);
end;

{ TPCScopesTests }

constructor TPCScopesTests.Create();
begin
  inherited;

  Title := 'Scopes';
  RegisterTest('visible_count', DoTestVisibleCount);
  RegisterTest('collect_all_module', DoTestCollectAllModule);
  RegisterTest('collect_partial', DoTestCollectPartial);
  RegisterTest('collect_forward', DoTestCollectForward);
  RegisterTest('members', DoTestMembers);
  RegisterTest('hidden', DoTestHidden);
  RegisterTest('hops', DoTestHops);
  RegisterTest('module_members', DoTestModuleMembers);
  RegisterTest('imported', DoTestImported);
  RegisterTest('choices_routine', DoTestChoicesRoutine);
  RegisterTest('system', DoTestSystem);
end;

procedure TPCScopesTests.Run();
begin
  inherited;
end;

procedure TPCScopesTests.DoTestVisibleCount();
begin
  DoWithSem(DoFixture(), SCOPES_MAX_ERRORS,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LVar: Integer;
      LRoutine: Integer;
    begin
      Check(not AErrors.HasErrors(), 'fixture analyzes clean: %s', [DoReports(AErrors)]);
      LVar := DoDeclIndex(AModule.Decls, 'V1');
      LRoutine := DoDeclIndex(AModule.Decls, 'R');
      // A var sees the items before it; a routine also itself (recursion)
      Check(TPCScopes.VisibleCount(AModule.Decls, LVar) = LVar, 'var V1 at %d: %d',
        [LVar, TPCScopes.VisibleCount(AModule.Decls, LVar)]);
      Check(TPCScopes.VisibleCount(AModule.Decls, LRoutine) = LRoutine + 1, 'routine R at %d: %d',
        [LRoutine, TPCScopes.VisibleCount(AModule.Decls, LRoutine)]);
      // Out of the list: the index itself, never an item read past the end
      Check(TPCScopes.VisibleCount(AModule.Decls, AModule.Decls.Count) = AModule.Decls.Count,
        'index past the end: %d', [TPCScopes.VisibleCount(AModule.Decls, AModule.Decls.Count)]);
      Check(TPCScopes.VisibleCount(nil, 3) = 3, 'nil list: %d', [TPCScopes.VisibleCount(nil, 3)]);
    end);
end;

procedure TPCScopesTests.DoTestCollectAllModule();
begin
  DoWithSem(DoFixture(), SCOPES_MAX_ERRORS,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LFrame: TPCScopeFrame;
      LAll: TList<TPCNode>;
      LNamed: TList<TPCNode>;
      LNode: TPCNode;
    begin
      Check(not AErrors.HasErrors(), 'fixture analyzes clean: %s', [DoReports(AErrors)]);
      LFrame := TPCScopes.ModuleFrame(AModule);
      LFrame.FirstCount := AModule.Decls.Count;
      LAll := TList<TPCNode>.Create();
      LNamed := TList<TPCNode>.Create();
      try
        TPCScopes.CollectAll(LFrame, LAll);
        Check(DoNamesText(LAll) = 'C1 V1 K TBase TDer TO1 TCol R K E1', 'module names: [%s] of {%s}',
          [DoNamesText(LAll), DoItemsText(AModule.Decls)]);
        // CollectAll is Collect for every name: each node it lists, Collect
        // by that node's name returns too
        for LNode in LAll do
        begin
          LNamed.Clear();
          TPCScopes.Collect(LFrame, DoNameOf(LNode), LNamed);
          Check(LNamed.Contains(LNode), 'Collect(%s) holds the node: [%s]',
            [DoNameOf(LNode), DoNamesText(LNamed)]);
        end;
      finally
        LNamed.Free();
        LAll.Free();
      end;
    end);
end;

procedure TPCScopesTests.DoTestCollectPartial();
begin
  DoWithSem(DoFixture(), SCOPES_MAX_ERRORS,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LFrame: TPCScopeFrame;
      LAll: TList<TPCNode>;
    begin
      LFrame := TPCScopes.ModuleFrame(AModule);
      LAll := TList<TPCNode>.Create();
      try
        // TDer's declaration sees the items before it, not itself
        LFrame.FirstCount := TPCScopes.VisibleCount(AModule.Decls, DoDeclIndex(AModule.Decls, 'TDer'));
        TPCScopes.CollectAll(LFrame, LAll);
        Check(DoNamesText(LAll) = 'C1 V1 K TBase', 'before TDer: [%s]', [DoNamesText(LAll)]);
        // R sees itself
        LAll.Clear();
        LFrame.FirstCount := TPCScopes.VisibleCount(AModule.Decls, DoDeclIndex(AModule.Decls, 'R'));
        TPCScopes.CollectAll(LFrame, LAll);
        Check(DoNamesText(LAll) = 'C1 V1 K TBase TDer TO1 TCol R', 'at R: [%s]', [DoNamesText(LAll)]);
        // A new frame shows nothing until its count is set
        LAll.Clear();
        TPCScopes.CollectAll(TPCScopes.ModuleFrame(AModule), LAll);
        Check(LAll.Count = 0, 'count 0: [%s]', [DoNamesText(LAll)]);
      finally
        LAll.Free();
      end;
    end);
end;

procedure TPCScopesTests.DoTestCollectForward();
begin
  DoWithSem(DoFixture(), SCOPES_MAX_ERRORS,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LFrame: TPCScopeFrame;
      LFound: TList<TPCNode>;
    begin
      LFrame := TPCScopes.ModuleFrame(AModule);
      LFrame.FirstCount := AModule.Decls.Count;
      LFound := TList<TPCNode>.Create();
      try
        TPCScopes.Collect(LFrame, 'K', LFound);
        Check(LFound.Count = 2, 'K forward + full: %d', [LFound.Count]);
        TPCScopes.CollapseForwards(LFound);
        Check((LFound.Count = 1) and (LFound[0] is TPCRoutine) and (not TPCRoutine(LFound[0]).IsForward),
          'K collapsed to the full routine: %d', [LFound.Count]);
        // Case matters: 'k' is no name of the module
        LFound.Clear();
        TPCScopes.Collect(LFrame, 'k', LFound);
        Check(LFound.Count = 0, 'k (case): %d', [LFound.Count]);
      finally
        LFound.Free();
      end;
    end);
end;

procedure TPCScopesTests.DoTestMembers();
begin
  DoWithSem(DoFixture(), SCOPES_MAX_ERRORS,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LDer: TPCTypeExpr;
      LAll: TList<TPCNode>;
      LOne: TList<TPCNode>;
    begin
      LDer := DoTypeDefOf(AModule, 'TDer');
      LAll := TList<TPCNode>.Create();
      LOne := TList<TPCNode>.Create();
      try
        // Nearest level first, the overlay hoisted, then the parent's level
        TPCScopes.AllMembers(LDer, LAll);
        Check(DoNamesText(LAll) = 'C U1 U2 D A B', 'TDer members: [%s]', [DoNamesText(LAll)]);
        TPCScopes.FindMember(LDer, 'A', LOne);
        Check((LOne.Count = 1) and LAll.Contains(LOne[0]), 'A through the parent: %d', [LOne.Count]);
        // A method lists as its routine
        LAll.Clear();
        TPCScopes.AllMembers(DoTypeDefOf(AModule, 'TO1'), LAll);
        Check((DoNamesText(LAll) = 'F M') and (LAll.Count = 2) and (LAll[1] is TPCRoutine),
          'TO1 members: [%s]', [DoNamesText(LAll)]);
        // A type that is no record / overlay has no members
        LAll.Clear();
        TPCScopes.AllMembers(DoTypeDefOf(AModule, 'TCol'), LAll);
        Check(LAll.Count = 0, 'choices members: [%s]', [DoNamesText(LAll)]);
      finally
        LOne.Free();
        LAll.Free();
      end;
    end);
end;

procedure TPCScopesTests.DoTestHidden();
begin
  DoWithSem(TPath.Combine(DoProbeDir('lsp\scopes'), 'sk02_hide.pcpp'), SCOPES_MAX_ERRORS,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LDer: TPCTypeExpr;
      LBase: TPCTypeExpr;
      LAll: TList<TPCNode>;
      LOne: TList<TPCNode>;
    begin
      // The tree SEM reported on keeps both levels (SM0309, the child's line)
      Check(DoReports(AErrors) = 'SM0309 8: ''Shared'' reuses a name of the parent chain',
        'exactly SM0309: %s', [DoReports(AErrors)]);
      LDer := DoTypeDefOf(AModule, 'TDer');
      LBase := DoTypeDefOf(AModule, 'TBase');
      LAll := TList<TPCNode>.Create();
      LOne := TList<TPCNode>.Create();
      try
        // TDer's Shared hides TBase's: one Shared, the child's
        TPCScopes.AllMembers(LDer, LAll);
        Check(DoNamesText(LAll) = 'Shared D A', 'TDer members: [%s]', [DoNamesText(LAll)]);
        TPCScopes.FindMember(LDer, 'Shared', LOne);
        Check((LOne.Count = 1) and (LAll.Count > 0) and (LOne[0] = LAll[0]),
          'Shared is TDer''s own: %d', [LOne.Count]);
        LOne.Clear();
        TPCScopes.FindMember(LBase, 'Shared', LOne);
        Check((LOne.Count = 1) and (not LAll.Contains(LOne[0])), 'TBase.Shared is hidden: %d',
          [LOne.Count]);
      finally
        LOne.Free();
        LAll.Free();
      end;
    end);
end;

procedure TPCScopesTests.DoCheckFind(const AType: TPCTypeExpr; const AName: string;
  const AFound: TList<TPCNode>; const ACount: Integer; const AHops: Integer; const ALabel: string);
var
  LHops: Integer;
begin
  // One FindMember call with its hops (PLAN-RECORDS M10): the count found and
  // the member parents stepped through
  AFound.Clear();
  TPCScopes.FindMember(AType, AName, AFound, LHops);
  Check((AFound.Count = ACount) and (LHops = AHops), '%s (got %d found, %d hops)',
    [ALabel, AFound.Count, LHops]);
end;

procedure TPCScopesTests.DoTestHops();
begin
  // PLAN-RECORDS M10 / R4: a record's PaskalCPP parent is a member; hops are
  // the levels stepped through such parents; an object keeps its C++ base
  DoWithSem(TPath.Combine(DoProbeDir('lsp\scopes'), 'sk03_hops.pcpp'), SCOPES_MAX_ERRORS,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LTA: TPCTypeExpr;
      LTB: TPCTypeExpr;
      LTC: TPCTypeExpr;
      LTOA: TPCTypeExpr;
      LTOB: TPCTypeExpr;
      LTQ: TPCTypeExpr;
      LTR: TPCTypeExpr;
      LTU: TPCTypeExpr;
      LFound: TList<TPCNode>;
      LHops: Integer;
      LOk: Boolean;
    begin
      Check(DoReports(AErrors) = '', 'sk03 analyzes clean: %s', [DoReports(AErrors)]);
      LTA := DoTypeDefOf(AModule, 'TA');
      LTB := DoTypeDefOf(AModule, 'TB');
      LTC := DoTypeDefOf(AModule, 'TC');
      LTOA := DoTypeDefOf(AModule, 'TOA');
      LTOB := DoTypeDefOf(AModule, 'TOB');
      LTQ := DoTypeDefOf(AModule, 'TQ');
      LTR := DoTypeDefOf(AModule, 'TR');
      LTU := DoTypeDefOf(AModule, 'TU');
      Check((LTA is TPCRecordType) and (LTB is TPCRecordType) and (LTC is TPCRecordType) and
        (LTOB is TPCRecordType) and (LTQ is TPCRecordType) and (LTR is TPCRecordType),
        'sk03: the record and object types are found');
      if not ((LTA is TPCRecordType) and (LTB is TPCRecordType) and (LTC is TPCRecordType) and
        (LTOB is TPCRecordType) and (LTQ is TPCRecordType) and (LTR is TPCRecordType)) then
        Exit;
      Check((not TPCRecordType(LTA).HasParentMember()) and TPCRecordType(LTB).HasParentMember() and
        TPCRecordType(LTC).HasParentMember() and (not TPCRecordType(LTOB).HasParentMember()) and
        (not TPCRecordType(LTQ).HasParentMember()) and TPCRecordType(LTR).HasParentMember(),
        'HasParentMember: a record''s record parent only (not an object, not C/C++)');
      LFound := TList<TPCNode>.Create();
      try
        DoCheckFind(LTC, 'A', LFound, 1, 2, 'TC.A: two hops');
        DoCheckFind(LTC, 'B', LFound, 1, 1, 'TC.B: one hop');
        DoCheckFind(LTC, 'C', LFound, 1, 0, 'TC.C: its own level');
        DoCheckFind(LTC, 'Nope', LFound, 0, 0, 'TC.Nope: none, no hops');
        DoCheckFind(LTOB, 'OA', LFound, 1, 0, 'TOB.OA: an object''s base stays C++''s');
        DoCheckFind(LTR, 'Q', LFound, 1, 1, 'TR.Q: one hop');
        DoCheckFind(LTR, 'x', LFound, 0, 0, 'TR.x: CPt''s member, no PaskalCPP level names it');
      finally
        LFound.Free();
      end;
      LOk := TPCScopes.ReachesOpaque(LTR, LHops);
      Check(LOk and (LHops = 1), 'ReachesOpaque TR: one hop to TQ, which derives from CPt (got %d)', [LHops]);
      LOk := TPCScopes.ReachesOpaque(LTQ, LHops);
      Check(LOk and (LHops = 0), 'ReachesOpaque TQ: its own parent (got %d)', [LHops]);
      LOk := TPCScopes.ReachesOpaque(LTC, LHops);
      Check((not LOk) and (LHops = 0), 'ReachesOpaque TC: never (got %d)', [LHops]);
      LOk := TPCScopes.Extends(LTC, LTA, LHops);
      Check(LOk and (LHops = 2), 'TC extends TA: two hops (got %d)', [LHops]);
      LOk := TPCScopes.Extends(LTC, LTB, LHops);
      Check(LOk and (LHops = 1), 'TC extends TB: one hop (got %d)', [LHops]);
      LOk := TPCScopes.Extends(LTR, LTQ, LHops);
      Check(LOk and (LHops = 1), 'TR extends TQ (got %d)', [LHops]);
      Check((not TPCScopes.Extends(LTC, LTC)) and (not TPCScopes.Extends(LTA, LTC)) and
        (not TPCScopes.Extends(LTC, LTU)) and (not TPCScopes.Extends(nil, LTA)) and
        (not TPCScopes.Extends(LTC, nil)), 'Extends: not itself, not downward, not unrelated, not nil');
      LOk := TPCScopes.Extends(LTOB, LTOA, LHops);
      Check((not LOk) and (LHops = 0), 'Extends: an object never extends (PLAN-OBJECT) (got %d)', [LHops]);
    end);
end;

procedure TPCScopesTests.DoTestModuleMembers();
begin
  DoWithSem(DoFixture(), SCOPES_MAX_ERRORS,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LFound: TList<TPCNode>;
    begin
      LFound := TList<TPCNode>.Create();
      try
        TPCScopes.ModuleMembers(AModule, LFound);
        Check(DoNamesText(LFound) = 'E1', 'exported: [%s]', [DoNamesText(LFound)]);
        LFound.Clear();
        Check(TPCScopes.ModuleMember(AModule, 'V1', LFound) and (LFound.Count = 0),
          'V1 declared, not exported: %d', [LFound.Count]);
        Check(not TPCScopes.ModuleMember(AModule, 'Nope', LFound), 'Nope is not declared');
      finally
        LFound.Free();
      end;
    end);
end;

procedure TPCScopesTests.DoTestImported();
begin
  // PLAN-IMPORT-RESOLUTION atom 1: FindImported over sk04_imp's own imports
  // (sk04_a, sk04_b; sk04_a's own import sk04_c is not followed)
  DoWithSem(TPath.Combine(DoProbeDir('lsp\scopes'), 'sk04_imp.pcpp'), SCOPES_MAX_ERRORS,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LFound: TList<TPCNode>;
      LHolders: TList<TPCImport>;
      LRow: TPCImportRow;
    begin
      Check(not AErrors.HasErrors(), 'sk04 analyzes clean: %d errors', [AErrors.ErrorCount()]);
      LFound := TList<TPCNode>.Create();
      LHolders := TList<TPCImport>.Create();
      try
        for LRow in IMPORT_ROWS do
        begin
          LFound.Clear();
          LHolders.Clear();
          TPCScopes.FindImported(AModule.Imports, LRow.LookupName, LFound, LHolders);
          Check((DoHoldersText(LHolders) = LRow.HolderNames) and (DoNamesText(LFound) = LRow.FoundNames),
            '%s: holders [%s] found [%s], expected [%s] [%s]',
            [LRow.LookupName, DoHoldersText(LHolders), DoNamesText(LFound), LRow.HolderNames, LRow.FoundNames]);
        end;
        LFound.Clear();
        LHolders.Clear();
        TPCScopes.FindImported(nil, 'OnlyA', LFound, LHolders);
        Check((LFound.Count = 0) and (LHolders.Count = 0), 'nil imports: found %d holders %d',
          [LFound.Count, LHolders.Count]);
      finally
        LHolders.Free();
        LFound.Free();
      end;
    end);
end;

procedure TPCScopesTests.DoTestChoicesRoutine();
begin
  DoWithSem(DoFixture(), SCOPES_MAX_ERRORS,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LFrame: TPCScopeFrame;
      LRoutine: TPCRoutine;
      LAll: TList<TPCNode>;
    begin
      LAll := TList<TPCNode>.Create();
      try
        // A choices value sees the values before it
        LFrame := TPCScopes.ChoicesFrame(TPCChoicesType(DoTypeDefOf(AModule, 'TCol')));
        LFrame.FirstCount := 1;
        TPCScopes.CollectAll(LFrame, LAll);
        Check(DoNamesText(LAll) = 'Red', 'choices at Green: [%s]', [DoNamesText(LAll)]);
        // A routine: its params, then its locals
        LAll.Clear();
        LRoutine := DoRoutineOf(AModule, 'R');
        LFrame := TPCScopes.RoutineFrame(LRoutine);
        LFrame.FirstCount := LRoutine.Decls.Count;
        TPCScopes.CollectAll(LFrame, LAll);
        Check(DoNamesText(LAll) = 'AP LR', 'routine R: [%s]', [DoNamesText(LAll)]);
      finally
        LAll.Free();
      end;
    end);
end;

procedure TPCScopesTests.DoTestSystem();
var
  LAll: TList<TPCNode>;
begin
  // The system frame declares no AST name (intrinsics are not nodes)
  LAll := TList<TPCNode>.Create();
  try
    TPCScopes.CollectAll(TPCScopes.SystemFrame(), LAll);
    Check(LAll.Count = 0, 'system frame: %d', [LAll.Count]);
  finally
    LAll.Free();
  end;
end;

end.
