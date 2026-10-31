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
  UTestCase.Vendor - vendor\StdApp units no compiler phase uses

  TPCTestCase suite for StdApp.Packer (AppPacker's core, which checkpoint.yml
  and every backup run through): a manifest over res\tests\vnd\fixtures\pack
  packs every included file under its path relative to the root (a rooted
  root and one relative to the manifest's folder alike), excludes apply, a
  manifest path no resolver takes is PAK008, and the sign: guard refuses an
  archive that would hold the secret key (PAK004).
  A code test because no .pcpp reaches the packer and nothing in
  PaskalCPP.groupproj uses it (user OK 2026-10-29). StdApp.CImporter is not
  tested here: its StdApp.LibTCC loads TCC and changes the process's FPU
  exception mask at unit initialization, which would change every test.

  Dependencies: PaskalCPP.TestSuite.CodeTest, StdApp.Packer
===============================================================================}

unit UTestCase.Vendor;

interface

uses
  StdApp.Base,
  PaskalCPP.TestSuite.Types,
  PaskalCPP.TestSuite.CodeTest;

type

  { TPCVendorTests }
  TPCVendorTests = class(TPCTestCase)
  private
    function DoNewErrors(): TErrors;
    function DoCodes(const AErrors: TErrors): string;
    function DoPlain(const APath: string): string;
    function DoWriteManifest(const AName: string; const ARoot: string;
      const AOutput: string; const AExtra: string): string;
    function DoZipNames(const AZip: string): string;
    procedure DoCheckPack(const ALabel: string; const AManifest: string;
      const AZip: string);
    procedure DoTestPackRooted(const ACell: TPCTestCell);
    procedure DoTestPackRelative(const ACell: TPCTestCell);
    procedure DoTestPackPathRefused(const ACell: TPCTestCell);
    procedure DoTestPackSecretKey(const ACell: TPCTestCell);
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Zip,
  System.Generics.Collections,
  StdApp.Utils,
  StdApp.Packer;

const
  { PC_TEST_VND_MAX_ERRORS }
  // Every report a check makes is seen (TErrors stops at one by default)
  PC_TEST_VND_MAX_ERRORS = 100;

  { PC_TEST_VND_MANIFEST }
  // The legacy flat form checkpoint.yml uses: root, output, extra lines
  PC_TEST_VND_MANIFEST = '''
name: vndpack
version: 1.0
root: %s
output: %s
include:
  - **
exclude:
  - **/*.log
%s
''';

  { PC_TEST_VND_SIGN }
  // A sign: block naming a secret key the include rules also match
  PC_TEST_VND_SIGN = '''
sign:
  seckey: %s
''';

  { PC_TEST_VND_ENTRIES }
  // Every file under fixtures\pack but the two .log files (exclude
  // **/*.log: sub\skip.log, and top.log at the root, '**/' being zero or
  // more folders), relative, '/' separated, sorted as the names compare
  PC_TEST_VND_ENTRIES = 'a.txt key.txt sub/b.txt sub/deep/c.txt';

  { PC_TEST_VND_ENTRY_COUNT }
  PC_TEST_VND_ENTRY_COUNT = 4;

{ TPCVendorTests }

constructor TPCVendorTests.Create();
begin
  inherited;

  AreaName := 'vnd';
  RegisterTest('pack_rooted', DoTestPackRooted);
  RegisterTest('pack_relative', DoTestPackRelative);
  RegisterTest('pack_path_refused', DoTestPackPathRefused);
  RegisterTest('pack_secret_key', DoTestPackSecretKey);
end;

function TPCVendorTests.DoNewErrors(): TErrors;
begin
  Result := TErrors.Create();
  Result.SetMaxErrors(PC_TEST_VND_MAX_ERRORS);
end;

function TPCVendorTests.DoCodes(const AErrors: TErrors): string;
var
  LCodes: TList<string>;
  LError: TError;
begin
  // Every report's code, sorted (the packer's reports carry no location, so
  // CheckErrors' '<line> <marker>' form does not apply)
  LCodes := TList<string>.Create();
  try
    for LError in AErrors.GetItems() do
      LCodes.Add(LError.Code);
    LCodes.Sort();
    Result := string.Join(' ', LCodes.ToArray());
  finally
    LCodes.Free();
  end;
end;

function TPCVendorTests.DoPlain(const APath: string): string;
begin
  // A path in backslashes without the long-path prefix: the spelling
  // ExtractRelativePath compares
  Result := TUtils.StripLongPathPrefix(TUtils.ResolvePath(APath)).Replace('/', '\');
end;

function TPCVendorTests.DoWriteManifest(const AName: string; const ARoot: string;
  const AOutput: string; const AExtra: string): string;
begin
  // The manifest in the output folder: a relative root resolves against it
  Result := WriteScratch(AName,
    TEncoding.UTF8.GetBytes(Format(PC_TEST_VND_MANIFEST, [ARoot, AOutput, AExtra])));
end;

function TPCVendorTests.DoZipNames(const AZip: string): string;
var
  LZip: TZipFile;
  LNames: TList<string>;
  LName: string;
begin
  // The archive's entry names, sorted, one blank between ('' = unreadable,
  // a failed check)
  Result := '';
  LNames := TList<string>.Create();
  try
    LZip := TZipFile.Create();
    try
      try
        LZip.Open(AZip, zmRead);
        for LName in LZip.FileNames do
          LNames.Add(LName);
        LZip.Close();
      except
        on E: Exception do
        begin
          Fail(Format('%s cannot be read: %s', [AZip, E.Message]));
          Exit;
        end;
      end;
    finally
      LZip.Free();
    end;
    LNames.Sort();
    Result := string.Join(' ', LNames.ToArray());
  finally
    LNames.Free();
  end;
end;

procedure TPCVendorTests.DoCheckPack(const ALabel: string; const AManifest: string;
  const AZip: string);
var
  LErrors: TErrors;
  LPacker: TPacker;
begin
  // Load, discover, build: no report, every file once under its relative
  // path (a file DoRelativePath could not place would be dropped)
  if AManifest = '' then
    Exit;
  LErrors := DoNewErrors();
  LPacker := TPacker.Create();
  try
    LPacker.SetErrors(LErrors);
    Check(LPacker.LoadManifest(AManifest), '%s: manifest loaded', [ALabel]);
    Check(LPacker.DiscoverFiles(), '%s: files discovered', [ALabel]);
    CheckEqual(Int64(PC_TEST_VND_ENTRY_COUNT), Int64(LPacker.FileCount()), ALabel + ': file count');
    Check(LPacker.Build(), '%s: archive built', [ALabel]);
    CheckEqual('', DoCodes(LErrors), ALabel + ': no reports');
    Check(TUtils.SamePath(AZip, LPacker.Output), '%s: output %s (got ''%s'')',
      [ALabel, AZip, LPacker.Output]);
  finally
    LPacker.Free();
    LErrors.Free();
  end;
  CheckEqual(PC_TEST_VND_ENTRIES, DoZipNames(AZip), ALabel + ': archive names');
end;

procedure TPCVendorTests.DoTestPackRooted(const ACell: TPCTestCell);
var
  LZip: string;
begin
  // A rooted root, a rooted output
  LZip := Scratch('vnd_pack_rooted.zip');
  DoCheckPack('rooted', DoWriteManifest('vnd_pack_rooted.yml', Fixture('pack'), LZip, ''), LZip);
end;

procedure TPCVendorTests.DoTestPackRelative(const ACell: TPCTestCell);
var
  LRoot: string;
  LZip: string;
begin
  // The root relative to the manifest's folder (the output folder), the
  // output a bare name there: both resolve against the manifest
  LRoot := ExtractRelativePath(IncludeTrailingPathDelimiter(DoPlain(ScratchFolder())),
    DoPlain(Fixture('pack')));
  Check(not TPath.IsPathRooted(LRoot), 'the root is relative (got ''%s'')', [LRoot]);
  LZip := Scratch('vnd_pack_relative.zip');
  DoCheckPack('relative', DoWriteManifest('vnd_pack_relative.yml', LRoot,
    'vnd_pack_relative.zip', ''), LZip);
end;

procedure TPCVendorTests.DoTestPackPathRefused(const ACell: TPCTestCell);
var
  LErrors: TErrors;
  LPacker: TPacker;
  LManifest: string;
begin
  // $R: names a project root a manifest never has: PAK008, reported, never
  // raised out of the packer
  LManifest := DoWriteManifest('vnd_pack_refused.yml', Fixture('pack'), '$R:vnd.zip', '');
  if LManifest = '' then
    Exit;
  LErrors := DoNewErrors();
  LPacker := TPacker.Create();
  try
    LPacker.SetErrors(LErrors);
    Check(not LPacker.LoadManifest(LManifest), 'manifest refused');
    CheckEqual(ERR_PAK_PATH, DoCodes(LErrors), 'reports');
  finally
    LPacker.Free();
    LErrors.Free();
  end;
end;

procedure TPCVendorTests.DoTestPackSecretKey(const ACell: TPCTestCell);
var
  LErrors: TErrors;
  LPacker: TPacker;
  LManifest: string;
begin
  // The secret key sits under the root and include ** matches it: the
  // guard compares the listed entry and the resolved key as paths (they
  // differ in their slashes), so discovery is refused with PAK004
  LManifest := DoWriteManifest('vnd_pack_seckey.yml', Fixture('pack'),
    Scratch('vnd_pack_seckey.zip'), Format(PC_TEST_VND_SIGN, [Fixture('pack/key.txt')]));
  if LManifest = '' then
    Exit;
  LErrors := DoNewErrors();
  LPacker := TPacker.Create();
  try
    LPacker.SetErrors(LErrors);
    Check(LPacker.LoadManifest(LManifest), 'manifest loaded');
    Check(not LPacker.DiscoverFiles(), 'discovery refused');
    CheckEqual(ERR_PAK_SECKEY, DoCodes(LErrors), 'reports');
  finally
    LPacker.Free();
    LErrors.Free();
  end;
end;

end.
