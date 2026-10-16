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
  PaskalCPP.Asar - Asar archive writer (the editor's app.asar, packed by pcppdev)

  Packs files into Electron's .asar format: an uncompressed archive with a
  JSON index header serialized using Chromium's Pickle binary format.
  Electron reads files directly from the archive at runtime via random
  access. An entry name is a relative '/'-separated path: 'src/a.js' is file
  a.js in folder src (a nested "files" object in the header).
  Taken as-is from PIXELS.Asar.pas (renames only).

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.JSON
===============================================================================}

unit PaskalCPP.Asar;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Utils,
  StdApp.JSON;

type
  { TPCAsarEntry }
  TPCAsarEntry = record
    EntryName: string;
    FilePath: string;
    FileSize: Int64;
  end;

  { TPCAsar }
  TPCAsar = class(TBaseObject)
  private
    FEntries: TList<TPCAsarEntry>;

    // Pickle serialization helpers
    procedure DoWriteUInt32LE(const AStream: TStream; const AValue: UInt32);
    function DoAlignUp(const AValue: Int64; const AAlignment: Integer): Int64;
    procedure DoWritePickleUInt32(const AStream: TStream; const AValue: UInt32);
    procedure DoWritePickleString(const AStream: TStream; const AValue: string);

    // Header builder
    function DoBuildHeaderJson(): string;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Add a file to the archive by name ('/'-separated relative path) and
    // source path. A bad, duplicate or folder-clashing name is a caller bug
    // and raises.
    procedure AddFile(const AName: string; const AFilePath: string);

    // Write the archive to disk
    procedure SaveToFile(const AOutputPath: string);

    // Clear all entries
    procedure Clear();
  end;

implementation

type
  { TPCAsarNode }
  // One name of the header tree: a file (EntryIndex = its entry) or a
  // folder (EntryIndex = -1). Children keep first-added order, so a flat
  // archive's header lists the entries in add order.
  TPCAsarNode = class(TBaseObject)
  public
    NodeName: string;
    EntryIndex: Integer;
    Children: TObjectList<TPCAsarNode>;
    constructor Create(); override;
    destructor Destroy(); override;
    function FindChild(const ANodeName: string): TPCAsarNode;
  end;

{ TPCAsarNode }
constructor TPCAsarNode.Create();
begin
  inherited;

  NodeName := '';
  EntryIndex := -1;
  Children := TObjectList<TPCAsarNode>.Create(True);
end;

destructor TPCAsarNode.Destroy();
begin
  Children.Free();

  inherited;
end;

function TPCAsarNode.FindChild(const ANodeName: string): TPCAsarNode;
var
  LIdx: Integer;
begin
  Result := nil;
  for LIdx := 0 to Children.Count - 1 do
  begin
    if Children[LIdx].NodeName = ANodeName then
    begin
      Result := Children[LIdx];
      Exit;
    end;
  end;
end;

{ AsarNameIsValid }
// A relative '/'-separated path: no leading or trailing '/', no empty, '.'
// or '..' segment, no '\'
function AsarNameIsValid(const AName: string): Boolean;
var
  LSegments: TArray<string>;
  LIdx: Integer;
begin
  Result := False;
  if (AName = '') or AName.Contains('\') or AName.StartsWith('/') or AName.EndsWith('/') then
    Exit;
  LSegments := AName.Split(['/']);
  for LIdx := 0 to High(LSegments) do
  begin
    if (LSegments[LIdx] = '') or (LSegments[LIdx] = '.') or (LSegments[LIdx] = '..') then
      Exit;
  end;
  Result := True;
end;

{ AsarBuildTree }
// The header tree of AEntries: every segment of a name but the last is a
// folder node, created on first use
function AsarBuildTree(const AEntries: TList<TPCAsarEntry>): TPCAsarNode;
var
  LIdx: Integer;
  LSeg: Integer;
  LSegments: TArray<string>;
  LFolder: TPCAsarNode;
  LChild: TPCAsarNode;
begin
  Result := TPCAsarNode.Create();
  try
    for LIdx := 0 to AEntries.Count - 1 do
    begin
      LSegments := AEntries[LIdx].EntryName.Split(['/']);
      LFolder := Result;
      for LSeg := 0 to High(LSegments) - 1 do
      begin
        LChild := LFolder.FindChild(LSegments[LSeg]);
        if LChild = nil then
        begin
          LChild := TPCAsarNode.Create();
          LChild.NodeName := LSegments[LSeg];
          LFolder.Children.Add(LChild);
        end;
        LFolder := LChild;
      end;
      LChild := TPCAsarNode.Create();
      LChild.NodeName := LSegments[High(LSegments)];
      LChild.EntryIndex := LIdx;
      LFolder.Children.Add(LChild);
    end;
  except
    Result.Free();
    raise;
  end;
end;

{ AsarEmitFolder }
// The members of AFolder into AJson's open "files" object. A file's offset
// is its data position (AOffsets, add order); a folder nests its own
// "files" object.
procedure AsarEmitFolder(const AJson: TJSON; const AFolder: TPCAsarNode;
  const AEntries: TList<TPCAsarEntry>; const AOffsets: TArray<Int64>);
var
  LIdx: Integer;
  LChild: TPCAsarNode;
begin
  for LIdx := 0 to AFolder.Children.Count - 1 do
  begin
    LChild := AFolder.Children[LIdx];
    AJson.BeginObject(LChild.NodeName);
    if LChild.EntryIndex >= 0 then
    begin
      AJson.Add('offset', IntToStr(AOffsets[LChild.EntryIndex]));  // offset is a string in asar
      AJson.Add('size', AEntries[LChild.EntryIndex].FileSize);     // size is an integer
    end
    else
    begin
      AJson.BeginObject('files');
      AsarEmitFolder(AJson, LChild, AEntries, AOffsets);
      AJson.EndObject();
    end;
    AJson.EndObject();
  end;
end;

{ TPCAsar }

constructor TPCAsar.Create();
begin
  inherited;

  FEntries := TList<TPCAsarEntry>.Create();
end;

destructor TPCAsar.Destroy();
begin
  FEntries.Free();

  inherited;
end;

procedure TPCAsar.DoWriteUInt32LE(const AStream: TStream; const AValue: UInt32);
var
  LValue: UInt32;
begin
  // Asar uses little-endian UInt32 throughout
  LValue := AValue;
  AStream.WriteBuffer(LValue, SizeOf(UInt32));
end;

function TPCAsar.DoAlignUp(const AValue: Int64; const AAlignment: Integer): Int64;
begin
  // Round up to next multiple of AAlignment
  Result := (AValue + AAlignment - 1) and not Int64(AAlignment - 1);
end;

procedure TPCAsar.DoWritePickleUInt32(const AStream: TStream; const AValue: UInt32);
begin
  // Pickle format: 4-byte header (payload_size) + 4-byte payload (the value)
  // Total: 8 bytes -- this is why the docs say "Pickle object is 8 bytes"
  DoWriteUInt32LE(AStream, SizeOf(UInt32));  // payload_size = 4
  DoWriteUInt32LE(AStream, AValue);          // the actual value
end;

procedure TPCAsar.DoWritePickleString(const AStream: TStream; const AValue: string);
var
  LBytes: TBytes;
  LByteLen: Integer;
  LPayloadSize: UInt32;
  LPadding: Integer;
  LZero: Byte;
  LIdx: Integer;
begin
  // Convert string to UTF-8 bytes
  LBytes := TEncoding.UTF8.GetBytes(AValue);
  LByteLen := Length(LBytes);

  // Pickle WriteString: WriteInt(length) + raw bytes + pad to 4-byte boundary
  // Payload = 4 (length int) + aligned(byte_length)
  LPayloadSize := SizeOf(UInt32) + UInt32(DoAlignUp(LByteLen, SizeOf(UInt32)));

  // Write pickle header (payload_size)
  DoWriteUInt32LE(AStream, LPayloadSize);

  // Write string length as int32
  DoWriteUInt32LE(AStream, UInt32(LByteLen));

  // Write raw string bytes
  if LByteLen > 0 then
    AStream.WriteBuffer(LBytes[0], LByteLen);

  // Pad to 4-byte alignment
  LPadding := Integer(DoAlignUp(LByteLen, SizeOf(UInt32))) - LByteLen;
  LZero := 0;
  for LIdx := 0 to LPadding - 1 do
    AStream.WriteBuffer(LZero, 1);
end;

function TPCAsar.DoBuildHeaderJson(): string;
var
  LJson: TJSON;
  LOffsets: TArray<Int64>;
  LOffset: Int64;
  LIdx: Integer;
  LRoot: TPCAsarNode;
begin
  // Data offsets follow add order: SaveToFile appends the files in it
  SetLength(LOffsets, FEntries.Count);
  LOffset := 0;
  for LIdx := 0 to FEntries.Count - 1 do
  begin
    LOffsets[LIdx] := LOffset;
    LOffset := LOffset + FEntries[LIdx].FileSize;
  end;

  // Format: {"files":{"name":{"offset":"N","size":N}, "dir":{"files":{...}}}}
  LRoot := AsarBuildTree(FEntries);
  try
    LJson := TJSON.Create();
    try
      LJson.BeginObject('files');
      AsarEmitFolder(LJson, LRoot, FEntries, LOffsets);
      LJson.EndObject();
      Result := LJson.ToString();
    finally
      LJson.Free();
    end;
  finally
    LRoot.Free();
  end;
end;

procedure TPCAsar.AddFile(const AName: string; const AFilePath: string);
var
  LEntry: TPCAsarEntry;
  LFileStream: TFileStream;
  LResolvedPath: string;
  LIdx: Integer;
  LOther: string;
begin
  if not AsarNameIsValid(AName) then
    raise Exception.CreateFmt('Asar: invalid entry name: %s', [AName]);

  // One name, one file; a file can never also be a folder of another name
  for LIdx := 0 to FEntries.Count - 1 do
  begin
    LOther := FEntries[LIdx].EntryName;
    if LOther = AName then
      raise Exception.CreateFmt('Asar: duplicate entry: %s', [AName]);
    if LOther.StartsWith(AName + '/') or AName.StartsWith(LOther + '/') then
      raise Exception.CreateFmt('Asar: entry %s clashes with entry %s', [AName, LOther]);
  end;

  LResolvedPath := TUtils.ResolvePath(AFilePath);

  if not FileExists(LResolvedPath) then
    raise Exception.CreateFmt('Asar: file not found: %s', [LResolvedPath]);

  LEntry.EntryName := AName;
  LEntry.FilePath := LResolvedPath;

  // Read file size at add time
  LFileStream := TFileStream.Create(LResolvedPath, fmOpenRead or fmShareDenyNone);
  try
    LEntry.FileSize := LFileStream.Size;
  finally
    LFileStream.Free();
  end;

  FEntries.Add(LEntry);
end;

procedure TPCAsar.SaveToFile(const AOutputPath: string);
var
  LOutput: TFileStream;
  LHeaderJson: string;
  LHeaderBytes: TBytes;
  LHeaderByteLen: Integer;
  LPickle2PayloadSize: UInt32;
  LPickle2TotalSize: UInt32;
  LIdx: Integer;
  LFileStream: TFileStream;
  LResolvedOutput: string;
begin
  LResolvedOutput := TUtils.ResolvePath(AOutputPath);

  LHeaderJson := DoBuildHeaderJson();
  LHeaderBytes := TEncoding.UTF8.GetBytes(LHeaderJson);
  LHeaderByteLen := Length(LHeaderBytes);

  // Pickle2 payload = 4 (string length int) + aligned(string bytes)
  LPickle2PayloadSize := SizeOf(UInt32) + UInt32(DoAlignUp(LHeaderByteLen, SizeOf(UInt32)));

  // Pickle2 total = 4 (its own header) + payload
  LPickle2TotalSize := SizeOf(UInt32) + LPickle2PayloadSize;

  LOutput := TFileStream.Create(LResolvedOutput, fmCreate);
  try
    // Pickle1: contains the size of Pickle2
    DoWritePickleUInt32(LOutput, LPickle2TotalSize);

    // Pickle2: contains the header JSON string
    DoWritePickleString(LOutput, LHeaderJson);

    // Append all file contents raw, no padding between files
    for LIdx := 0 to FEntries.Count - 1 do
    begin
      LFileStream := TFileStream.Create(FEntries[LIdx].FilePath, fmOpenRead or fmShareDenyNone);
      try
        LOutput.CopyFrom(LFileStream, 0);
      finally
        LFileStream.Free();
      end;
    end;
  finally
    LOutput.Free();
  end;
end;

procedure TPCAsar.Clear();
begin
  FEntries.Clear();
end;

end.
