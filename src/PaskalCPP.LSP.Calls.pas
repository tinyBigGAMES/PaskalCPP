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
  PaskalCPP.LSP.Calls - the call sites of a module, for the call hierarchy

  Reads the analysed AST only: a call's routine is TPCCall.TargetRoutine (the
  emitter's rule: its declaration, else the overload member SEM recorded); a
  forward is taken to its full routine (TPCRoutine.ResolvedFull). Nothing here
  resolves a name again. Concept from reference\cpaskal Myrissa.LSP
  (PrepareCallHierarchy / GetOutgoingCalls); its by-name lookup is not ported:
  a routine is named by its file and its name's position (KeyOf), so two
  routines of one name (an overload set, two modules) stay apart and a key
  outlives the analysis it came from.

  Dependencies: StdApp.Base, StdApp.Utils, PaskalCPP.AST, PaskalCPP.LSP.Symbols
  Notes:
    - Positions are the frontend's: 1-based line, 1-based UTF-8 byte column.
    - The caller of a call is the innermost routine around it; a call in the
      module's body, its initialize / finalize, a test or a declaration's
      value has the module itself as its caller.
    - A C/C++ callee and an intrinsic have no routine: no site.
===============================================================================}

unit PaskalCPP.LSP.Calls;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.AST;

type
  { TPCLspCallSite }
  // One call of a PaskalCPP routine: Target = the routine it calls (a
  // forward taken to its full routine), Caller = the innermost routine around
  // the call, or the module (a TPCModule) for a call outside every routine
  TPCLspCallSite = record
    Caller: TPCNode;
    Call: TPCCall;
    Target: TPCRoutine;
  end;

  { TPCLspCalls }
  TPCLspCalls = record
  public
    // The routine ANode is for the call hierarchy: a forward is its full
    // routine; nil when ANode is no routine
    class function RoutineOf(const ANode: TPCNode): TPCRoutine; static;
    // Every call site in AModule's own nodes, in walk order (the modules it
    // imports are not entered)
    class function Sites(const AModule: TPCModule): TArray<TPCLspCallSite>; static;
    // AModule and every module it imports, directly or not, each once
    class function ModulesOf(const AModule: TPCModule): TArray<TPCModule>; static;
    // The name of a caller or a routine that holds across analyses: a
    // routine by its file and its name's start, a module by its file
    class function KeyOf(const ANode: TPCNode): string; static;
    // The key of the routine whose name starts at (ALine, AColumn) of
    // AFilename (a client's item, its position made a byte column)
    class function KeyAt(const AFilename: string; const ALine: UInt64;
      const AColumn: UInt64): string; static;
    // The part of a call the hierarchy marks: the callee as written (the
    // whole call when it has none)
    class function SiteRange(const ACall: TPCCall): TSourceRange; static;
  end;

implementation

uses
  StdApp.Utils,
  PaskalCPP.LSP.Symbols;

const
  { PC_LSP_CALLS_MODULE_KEY }
  // The prefix of a module's key (a routine's key starts with its file)
  PC_LSP_CALLS_MODULE_KEY = 'module|';

type
  { TPCLspSiteFinder }
  // The EnumChildren walk of Sites: every call under a module, with the
  // routine around it
  TPCLspSiteFinder = class(TBaseObject)
  private
    FModule: TPCModule;
    FCaller: TPCNode;
    FSites: TList<TPCLspCallSite>;
    FVisitor: TPCNodeVisitor;
    procedure DoVisit(const ANode: TPCNode);
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Find(const AModule: TPCModule);
    property Sites: TList<TPCLspCallSite> read FSites;
  end;

{ FileKey }
// One spelling of a file for a key: the AST's resolved path and a uri's path
// differ in slashes, case and the long-path prefix only
function FileKey(const AFilename: string): string;
begin
  Result := TUtils.StripLongPathPrefix(AFilename).Replace('/', '\').ToLower();
end;

{ TPCLspSiteFinder }

constructor TPCLspSiteFinder.Create();
begin
  inherited;

  FSites := TList<TPCLspCallSite>.Create();
  FVisitor := DoVisit;
end;

destructor TPCLspSiteFinder.Destroy();
begin
  FSites.Free();

  inherited;
end;

procedure TPCLspSiteFinder.DoVisit(const ANode: TPCNode);
var
  LSite: TPCLspCallSite;
  LTarget: TPCRoutine;
  LOuter: TPCNode;
begin
  if ANode is TPCCall then
  begin
    LTarget := TPCLspCalls.RoutineOf(TPCCall(ANode).TargetRoutine());
    if LTarget <> nil then
    begin
      LSite.Caller := FCaller;
      LSite.Call := TPCCall(ANode);
      LSite.Target := LTarget;
      FSites.Add(LSite);
    end;
  end;

  // A routine is the caller of the calls inside it; initialize and finalize
  // are the module's own blocks
  if (ANode is TPCRoutine) and (ANode <> FModule.InitRoutine) and
     (ANode <> FModule.FinalRoutine) then
  begin
    LOuter := FCaller;
    FCaller := ANode;
    try
      ANode.EnumChildren(FVisitor);
    finally
      FCaller := LOuter;
    end;
  end
  else
    ANode.EnumChildren(FVisitor);
end;

procedure TPCLspSiteFinder.Find(const AModule: TPCModule);
begin
  FSites.Clear();
  FModule := AModule;
  FCaller := AModule;
  DoVisit(AModule);
end;

{ TPCLspCalls }

class function TPCLspCalls.RoutineOf(const ANode: TPCNode): TPCRoutine;
begin
  Result := nil;
  if not (ANode is TPCRoutine) then
    Exit;
  Result := TPCRoutine(ANode);
  if Result.IsForward and (Result.ResolvedFull <> nil) then
    Result := Result.ResolvedFull;
end;

class function TPCLspCalls.Sites(const AModule: TPCModule): TArray<TPCLspCallSite>;
var
  LFinder: TPCLspSiteFinder;
begin
  Result := nil;
  if AModule = nil then
    Exit;
  LFinder := TPCLspSiteFinder.Create();
  try
    LFinder.Find(AModule);
    Result := LFinder.Sites.ToArray();
  finally
    LFinder.Free();
  end;
end;

class function TPCLspCalls.ModulesOf(const AModule: TPCModule): TArray<TPCModule>;
var
  LList: TList<TPCModule>;
  LIndex: Integer;
  LImport: TPCImport;
begin
  Result := nil;
  if AModule = nil then
    Exit;
  LList := TList<TPCModule>.Create();
  try
    // Breadth first; a module two imports reach is listed once
    LList.Add(AModule);
    LIndex := 0;
    while LIndex < LList.Count do
    begin
      for LImport in LList[LIndex].Imports do
        if (LImport.ImportedModule <> nil) and not LList.Contains(LImport.ImportedModule) then
          LList.Add(LImport.ImportedModule);
      Inc(LIndex);
    end;
    Result := LList.ToArray();
  finally
    LList.Free();
  end;
end;

class function TPCLspCalls.KeyOf(const ANode: TPCNode): string;
var
  LRange: TSourceRange;
begin
  if ANode is TPCModule then
    Exit(PC_LSP_CALLS_MODULE_KEY + FileKey(TPCModule(ANode).SourceFile));
  LRange := TPCLspSymbols.NameRangeOf(ANode);
  Result := KeyAt(LRange.Filename, LRange.StartLine, LRange.StartColumn);
end;

class function TPCLspCalls.KeyAt(const AFilename: string; const ALine: UInt64;
  const AColumn: UInt64): string;
begin
  Result := FileKey(AFilename) + '|' + UIntToStr(ALine) + ':' + UIntToStr(AColumn);
end;

class function TPCLspCalls.SiteRange(const ACall: TPCCall): TSourceRange;
begin
  if ACall.Callee <> nil then
    Result := ACall.Callee.Range
  else
    Result := ACall.Range;
end;

end.
