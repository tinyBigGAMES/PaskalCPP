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
 UTestFrontend - shared parse / semantics harness for the testbed

  One harness, never copied: the probe fixture folders (DoProbeDir), the
  parse of a fixture as the main file under an error budget (DoWithPathMax,
  DoWithPath, DoWithIn) and parse + semantic analysis (DoWithSem,
  DoWithSemAs: a testbed subclass of TPCSemantics runs the same way), and
  parse + analysis + emission (DoWithEmit, DoEmitOne: PLAN-EMITTER H7).

  Dependencies: StdApp.Base, StdApp.Utils, PaskalCPP.Common, PaskalCPP.AST,
    PaskalCPP.Parser, PaskalCPP.Semantics, PaskalCPP.Emitter
===============================================================================}

unit UTestFrontend;

interface

uses
  StdApp.Base,
  PaskalCPP.AST,
  PaskalCPP.Semantics;

type
  { TPCParseCheck }
  // The checks one fixture runs against its parse
  TPCParseCheck = reference to procedure(const AModule: TPCModule; const AAst: TPCAst;
    const AErrors: TErrors);

  { TPCEmitCheck }
  // The checks one fixture runs against its emitted main module (AHeader /
  // ASource '' when analysis reported an error or emission failed)
  TPCEmitCheck = reference to procedure(const AModule: TPCModule; const AAst: TPCAst;
    const AErrors: TErrors; const AHeader: string; const ASource: string);

// tests\probe\<AArea> (AArea like 'par\core', 'sem\core'); the exe sits in repo\bin
function DoProbeDir(const AArea: string): string;
// Every reported code, warnings included, in report order: 'PR0005,PR0006'
function DoCodes(const AErrors: TErrors): string;
// Every report as 'CODE line: message', '; ' separated: a failure says why
function DoReports(const AErrors: TErrors): string;
procedure DoWithPathMax(const APath: string; const AMaxErrors: Integer; const ACheck: TPCParseCheck);
procedure DoWithPath(const APath: string; const ACheck: TPCParseCheck);
procedure DoWithIn(const ADir: string; const AName: string; const ACheck: TPCParseCheck);
// Parse, then analyze (also a tree the parser reported errors on)
procedure DoWithSemAs(const AClass: TPCSemanticsClass; const APath: string; const AMaxErrors: Integer;
  const ACheck: TPCParseCheck);
procedure DoWithSem(const APath: string; const AMaxErrors: Integer; const ACheck: TPCParseCheck);
// AModule of an analyzed AST (AMain = the main module) as text; False = the
// emitter reported (EM0003)
function DoEmitOne(const AAst: TPCAst; const AMain: TPCModule; const AModule: TPCModule;
  const AErrors: TErrors; out AHeader: string; out ASource: string): Boolean;
// Parse, analyze, then emit the main module when analysis reported no error
procedure DoWithEmit(const APath: string; const ACheck: TPCEmitCheck);

implementation

uses
  System.SysUtils,
  System.IOUtils,
  StdApp.Utils,
  PaskalCPP.Common,
  PaskalCPP.Parser,
  PaskalCPP.Emitter;

function DoProbeDir(const AArea: string): string;
begin
  Result := TUtils.ResolvePath('..\..\tests\probe\' + AArea, TPath.GetDirectoryName(ParamStr(0)));
end;

function DoCodes(const AErrors: TErrors): string;
var
  LError: TError;
begin
  Result := '';
  for LError in AErrors.GetItems() do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + LError.Code;
  end;
end;

function DoReports(const AErrors: TErrors): string;
var
  LError: TError;
begin
  Result := '';
  for LError in AErrors.GetItems() do
  begin
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + Format('%s %d: %s', [LError.Code, LError.Range.StartLine, LError.Message]);
  end;
end;

procedure DoWithPathMax(const APath: string; const AMaxErrors: Integer; const ACheck: TPCParseCheck);
var
  LErrors: TErrors;
  LAst: TPCAst;
  LModule: TPCModule;
begin
  // Parse a fixture as the main file (no importers, no target, no paths)
  // under an error budget of AMaxErrors
  LErrors := TErrors.Create();
  LAst := TPCAst.Create();
  try
    LErrors.SetMaxErrors(AMaxErrors);
    LAst.SetErrors(LErrors);
    LModule := ParseModuleFile(LAst, LErrors, APath, nil, Default(TPCTargetTriple), Default(TPCTargetTriple), Default(TPCTargetTriple), nil);
    ACheck(LModule, LAst, LErrors);
  finally
    LAst.Free();
    LErrors.Free();
  end;
end;

procedure DoWithPath(const APath: string; const ACheck: TPCParseCheck);
begin
  DoWithPathMax(APath, 100, ACheck);
end;

procedure DoWithIn(const ADir: string; const AName: string; const ACheck: TPCParseCheck);
begin
  DoWithPath(TPath.Combine(ADir, AName), ACheck);
end;

procedure DoWithSemAs(const AClass: TPCSemanticsClass; const APath: string; const AMaxErrors: Integer;
  const ACheck: TPCParseCheck);
var
  LErrors: TErrors;
  LAst: TPCAst;
  LModule: TPCModule;
  LSemantics: TPCSemantics;
begin
  LErrors := TErrors.Create();
  LAst := TPCAst.Create();
  LSemantics := nil;
  try
    LErrors.SetMaxErrors(AMaxErrors);
    LAst.SetErrors(LErrors);
    LModule := ParseModuleFile(LAst, LErrors, APath, nil, Default(TPCTargetTriple), Default(TPCTargetTriple), Default(TPCTargetTriple), nil);
    LSemantics := AClass.Create();
    LSemantics.SetErrors(LErrors);
    LSemantics.Analyze(LAst);
    ACheck(LModule, LAst, LErrors);
  finally
    LSemantics.Free();
    LAst.Free();
    LErrors.Free();
  end;
end;

procedure DoWithSem(const APath: string; const AMaxErrors: Integer; const ACheck: TPCParseCheck);
begin
  DoWithSemAs(TPCSemantics, APath, AMaxErrors, ACheck);
end;

function DoEmitOne(const AAst: TPCAst; const AMain: TPCModule; const AModule: TPCModule;
  const AErrors: TErrors; out AHeader: string; out ASource: string): Boolean;
var
  LEmitter: TPCEmitter;
  LHeader: TBytes;
  LSource: TBytes;
begin
  AHeader := '';
  ASource := '';
  LEmitter := TPCEmitter.Create();
  try
    LEmitter.SetErrors(AErrors);
    LEmitter.Init(AAst, AMain);
    Result := LEmitter.EmitModule(AModule, LHeader, LSource);
    if Result then
    begin
      AHeader := TEncoding.UTF8.GetString(LHeader);
      ASource := TEncoding.UTF8.GetString(LSource);
    end;
  finally
    LEmitter.Free();
  end;
end;

procedure DoWithEmit(const APath: string; const ACheck: TPCEmitCheck);
begin
  DoWithSemAs(TPCSemantics, APath, 100,
    procedure(const AModule: TPCModule; const AAst: TPCAst; const AErrors: TErrors)
    var
      LHeader: string;
      LSource: string;
    begin
      // The emitter never runs on an AST with errors (PLAN-EMITTER A2)
      LHeader := '';
      LSource := '';
      if not AErrors.HasErrors() then
        DoEmitOne(AAst, AModule, AModule, AErrors, LHeader, LSource);
      ACheck(AModule, AAst, AErrors, LHeader, LSource);
    end);
end;

end.
