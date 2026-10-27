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
  PaskalCPP.Icon - an .ico file's largest frame as RGBA (the Linux exe icon)

  TPCIconImage decodes an .ico with the Windows Imaging Component, the
  compiler's host decoder (BMP frames with their AND mask and PNG frames
  alike), picks the frame with the most pixels (the first of equal ones) and
  hands it out as 8-bit RGBA, not premultiplied, rows top to bottom.
  WriteEntryFile writes the built-in data entry a non-Windows exe carries
  under PC_RESDATA_EXEICON_KEY (PLAN-RESDATA A6): width and height as
  little-endian 32-bit integers, then the pixels.

  Dependencies: RTL + Winapi + StdApp.Resources (its failure texts)
  Notes: A pure routine: it reports nothing, a failure is returned as text
    (the OS / WIC reason). COM is initialized for the call when the thread
    has not done it, and released again.
===============================================================================}

unit PaskalCPP.Icon;

interface

uses
  System.SysUtils,
  System.Classes;

const
  { PC_ICON_HEADER_SIZE }
  // The entry's header: width, height (uint32 each, little-endian)
  PC_ICON_HEADER_SIZE = 8;
  { PC_ICON_PIXEL_SIZE }
  // One RGBA pixel
  PC_ICON_PIXEL_SIZE = 4;

type
  { TPCIconImage }
  TPCIconImage = record
  strict private
    class function DoDecode(const APath: string; out AWidth: Cardinal;
      out AHeight: Cardinal; out APixels: TBytes): string; static;
  public
    // The largest frame of the .ico at APath. False = it could not be read
    // or decoded (AFailure = the reason)
    class function DecodeLargest(const APath: string; out AWidth: Cardinal;
      out AHeight: Cardinal; out APixels: TBytes; out AFailure: string): Boolean; static;
    // The entry's bytes for a decoded frame: the header, then the pixels
    class function EntryBytes(const AWidth: Cardinal; const AHeight: Cardinal;
      const APixels: TBytes): TBytes; static;
    // Decode the .ico at AIconPath and write its entry to AEntryPath. False =
    // the icon could not be decoded or the file not written (AFailure)
    class function WriteEntryFile(const AIconPath: string; const AEntryPath: string;
      out AFailure: string): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ActiveX,
  Winapi.Wincodec,
  System.IOUtils,
  StdApp.Utils,
  StdApp.Resources;

const
  { PC_ICON_NO_VENDOR }
  // No preferred decoder vendor: WIC picks the one for the file
  PC_ICON_NO_VENDOR: TGUID = '{00000000-0000-0000-0000-000000000000}';

{ TPCIconImage }

class function TPCIconImage.DoDecode(const APath: string; out AWidth: Cardinal;
  out AHeight: Cardinal; out APixels: TBytes): string;
var
  LFactory: IWICImagingFactory;
  LDecoder: IWICBitmapDecoder;
  LFrame: IWICBitmapFrameDecode;
  LBest: IWICBitmapFrameDecode;
  LConverted: IWICBitmapSource;
  LCount: UINT;
  LIndex: Integer;
  LWidth: UINT;
  LHeight: UINT;
  LBestCount: UInt64;
  LHr: HRESULT;
begin
  // '' = decoded. The interfaces are released when this routine returns,
  // before the caller releases COM
  AWidth := 0;
  AHeight := 0;
  APixels := nil;
  LHr := CoCreateInstance(CLSID_WICImagingFactory, nil, CLSCTX_INPROC_SERVER,
    IID_IWICImagingFactory, LFactory);
  if Failed(LHr) then
    Exit(Format(RSIcoWicFailed, ['CoCreateInstance', Cardinal(LHr), SysErrorMessage(Cardinal(LHr))]));
  LHr := LFactory.CreateDecoderFromFilename(PChar(APath), PC_ICON_NO_VENDOR, GENERIC_READ,
    WICDecodeMetadataCacheOnDemand, LDecoder);
  if Failed(LHr) then
    Exit(Format(RSIcoWicFailed, ['CreateDecoderFromFilename', Cardinal(LHr), SysErrorMessage(Cardinal(LHr))]));
  LCount := 0;
  LHr := LDecoder.GetFrameCount(LCount);
  if Failed(LHr) then
    Exit(Format(RSIcoWicFailed, ['GetFrameCount', Cardinal(LHr), SysErrorMessage(Cardinal(LHr))]));

  // The frame with the most pixels; the first of equal ones wins
  LBest := nil;
  LBestCount := 0;
  for LIndex := 0 to Integer(LCount) - 1 do
  begin
    LHr := LDecoder.GetFrame(UINT(LIndex), LFrame);
    if Failed(LHr) then
      Exit(Format(RSIcoWicFailed, ['GetFrame', Cardinal(LHr), SysErrorMessage(Cardinal(LHr))]));
    LWidth := 0;
    LHeight := 0;
    LHr := LFrame.GetSize(LWidth, LHeight);
    if Failed(LHr) then
      Exit(Format(RSIcoWicFailed, ['GetSize', Cardinal(LHr), SysErrorMessage(Cardinal(LHr))]));
    if UInt64(LWidth) * UInt64(LHeight) > LBestCount then
    begin
      LBestCount := UInt64(LWidth) * UInt64(LHeight);
      LBest := LFrame;
      AWidth := LWidth;
      AHeight := LHeight;
    end;
  end;
  if LBest = nil then
    Exit(RSIcoNoFrame);

  // 8-bit RGBA, not premultiplied: the converter swaps or expands channels
  // only, so a PNG / 32-bit frame keeps its exact bytes
  LHr := WICConvertBitmapSource(GUID_WICPixelFormat32bppRGBA, LBest, LConverted);
  if Failed(LHr) then
    Exit(Format(RSIcoWicFailed, ['WICConvertBitmapSource', Cardinal(LHr), SysErrorMessage(Cardinal(LHr))]));
  SetLength(APixels, LBestCount * PC_ICON_PIXEL_SIZE);
  LHr := LConverted.CopyPixels(nil, AWidth * PC_ICON_PIXEL_SIZE, Length(APixels), @APixels[0]);
  if Failed(LHr) then
  begin
    APixels := nil;
    Exit(Format(RSIcoWicFailed, ['CopyPixels', Cardinal(LHr), SysErrorMessage(Cardinal(LHr))]));
  end;
  Result := '';
end;

class function TPCIconImage.DecodeLargest(const APath: string; out AWidth: Cardinal;
  out AHeight: Cardinal; out APixels: TBytes; out AFailure: string): Boolean;
var
  LInit: HRESULT;
begin
  AWidth := 0;
  AHeight := 0;
  APixels := nil;
  // COM for this call: S_OK / S_FALSE are released again; a thread already
  // in another mode (RPC_E_CHANGED_MODE) keeps its own, which WIC can use
  LInit := CoInitializeEx(nil, COINIT_MULTITHREADED);
  try
    try
      AFailure := DoDecode(APath, AWidth, AHeight, APixels);
    except
      on E: Exception do
        AFailure := E.Message;
    end;
  finally
    if Succeeded(LInit) then
      CoUninitialize();
  end;
  Result := AFailure = '';
  if not Result then
  begin
    AWidth := 0;
    AHeight := 0;
    APixels := nil;
  end;
end;

class function TPCIconImage.EntryBytes(const AWidth: Cardinal; const AHeight: Cardinal;
  const APixels: TBytes): TBytes;
var
  LShift: Integer;
begin
  // Little-endian on every target: written byte by byte, not from memory
  SetLength(Result, PC_ICON_HEADER_SIZE + Length(APixels));
  for LShift := 0 to 3 do
  begin
    Result[LShift] := Byte(AWidth shr (8 * LShift));
    Result[4 + LShift] := Byte(AHeight shr (8 * LShift));
  end;
  if Length(APixels) > 0 then
    Move(APixels[0], Result[PC_ICON_HEADER_SIZE], Length(APixels));
end;

class function TPCIconImage.WriteEntryFile(const AIconPath: string; const AEntryPath: string;
  out AFailure: string): Boolean;
var
  LWidth: Cardinal;
  LHeight: Cardinal;
  LPixels: TBytes;
begin
  Result := DecodeLargest(AIconPath, LWidth, LHeight, LPixels, AFailure);
  if not Result then
    Exit;
  // The entry is compiled into the program: written only when its bytes
  // changed, so zig's cache (time stamps) keeps that TU's object
  Result := TUtils.WriteBytesIfChanged(AEntryPath, EntryBytes(LWidth, LHeight, LPixels), AFailure);
end;

end.
