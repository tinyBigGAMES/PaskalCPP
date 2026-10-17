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
  PaskalCPP.ZigBuild.Targets - Supported target architectures, OSes, and ABIs.

  String constants for every architecture, operating system, and ABI that the
  bundled Zig/Clang toolchain supports, the same names as tables, and exact
  (case-sensitive) checks against them: IsZigArch / IsZigOS / IsZigAbi.
  SetTarget takes a triple only when each part is one of these names, so a
  typo is an error instead of a build for another target (R31). Compose a
  triple with the constants, e.g. SetTarget(ARCH_X86_64, OS_WINDOWS, ABI_MSVC).

  GENERATED FILE - DO NOT EDIT BY HAND.
  Regenerate with: python scripts\gen_targets.py (runs the bundled
  `zig targets` and re-emits this unit), after a zig update.

  Dependencies: none
===============================================================================}

unit PaskalCPP.ZigBuild.Targets;

interface

const
  { Architectures }
  ARCH_AARCH64      = 'aarch64';
  ARCH_AARCH64_BE   = 'aarch64_be';
  ARCH_ALPHA        = 'alpha';
  ARCH_AMDGCN       = 'amdgcn';
  ARCH_ARC          = 'arc';
  ARCH_ARCEB        = 'arceb';
  ARCH_ARM          = 'arm';
  ARCH_ARMEB        = 'armeb';
  ARCH_AVR          = 'avr';
  ARCH_BPFEB        = 'bpfeb';
  ARCH_BPFEL        = 'bpfel';
  ARCH_CSKY         = 'csky';
  ARCH_EZ80         = 'ez80';
  ARCH_HEXAGON      = 'hexagon';
  ARCH_HPPA         = 'hppa';
  ARCH_HPPA64       = 'hppa64';
  ARCH_KALIMBA      = 'kalimba';
  ARCH_KVX          = 'kvx';
  ARCH_LANAI        = 'lanai';
  ARCH_LOONGARCH32  = 'loongarch32';
  ARCH_LOONGARCH64  = 'loongarch64';
  ARCH_M68K         = 'm68k';
  ARCH_M88K         = 'm88k';
  ARCH_MICROBLAZE   = 'microblaze';
  ARCH_MICROBLAZEEL = 'microblazeel';
  ARCH_MIPS         = 'mips';
  ARCH_MIPSEL       = 'mipsel';
  ARCH_MIPS64       = 'mips64';
  ARCH_MIPS64EL     = 'mips64el';
  ARCH_MSP430       = 'msp430';
  ARCH_NVPTX        = 'nvptx';
  ARCH_NVPTX64      = 'nvptx64';
  ARCH_OR1K         = 'or1k';
  ARCH_POWERPC      = 'powerpc';
  ARCH_POWERPCLE    = 'powerpcle';
  ARCH_POWERPC64    = 'powerpc64';
  ARCH_POWERPC64LE  = 'powerpc64le';
  ARCH_PROPELLER    = 'propeller';
  ARCH_RISCV32      = 'riscv32';
  ARCH_RISCV32BE    = 'riscv32be';
  ARCH_RISCV64      = 'riscv64';
  ARCH_RISCV64BE    = 'riscv64be';
  ARCH_S390X        = 's390x';
  ARCH_SH           = 'sh';
  ARCH_SHEB         = 'sheb';
  ARCH_SPARC        = 'sparc';
  ARCH_SPARC64      = 'sparc64';
  ARCH_SPORK8       = 'spork8';
  ARCH_SPIRV32      = 'spirv32';
  ARCH_SPIRV64      = 'spirv64';
  ARCH_THUMB        = 'thumb';
  ARCH_THUMBEB      = 'thumbeb';
  ARCH_VE           = 've';
  ARCH_WASM32       = 'wasm32';
  ARCH_WASM64       = 'wasm64';
  ARCH_X86_16       = 'x86_16';
  ARCH_X86          = 'x86';
  ARCH_X86_64       = 'x86_64';
  ARCH_XCORE        = 'xcore';
  ARCH_XTENSA       = 'xtensa';
  ARCH_XTENSAEB     = 'xtensaeb';

  { Operating Systems }
  OS_FREESTANDING = 'freestanding';
  OS_OTHER        = 'other';
  OS_CONTIKI      = 'contiki';
  OS_FUCHSIA      = 'fuchsia';
  OS_HERMIT       = 'hermit';
  OS_MANAGARM     = 'managarm';
  OS_HAIKU        = 'haiku';
  OS_HURD         = 'hurd';
  OS_ILLUMOS      = 'illumos';
  OS_LINUX        = 'linux';
  OS_PLAN9        = 'plan9';
  OS_RTEMS        = 'rtems';
  OS_SERENITY     = 'serenity';
  OS_DRAGONFLY    = 'dragonfly';
  OS_FREEBSD      = 'freebsd';
  OS_NETBSD       = 'netbsd';
  OS_OPENBSD      = 'openbsd';
  OS_DRIVERKIT    = 'driverkit';
  OS_IOS          = 'ios';
  OS_MACCATALYST  = 'maccatalyst';
  OS_MACOS        = 'macos';
  OS_TVOS         = 'tvos';
  OS_VISIONOS     = 'visionos';
  OS_WATCHOS      = 'watchos';
  OS_WINDOWS      = 'windows';
  OS_UEFI         = 'uefi';
  OS_3DS          = '3ds';
  OS_WIIU         = 'wiiu';
  OS_SWITCH       = 'switch';
  OS_GBA          = 'gba';
  OS_PSX          = 'psx';
  OS_PS3          = 'ps3';
  OS_PS4          = 'ps4';
  OS_PS5          = 'ps5';
  OS_PSP          = 'psp';
  OS_VITA         = 'vita';
  OS_EMSCRIPTEN   = 'emscripten';
  OS_WASI         = 'wasi';
  OS_AMDHSA       = 'amdhsa';
  OS_AMDPAL       = 'amdpal';
  OS_CUDA         = 'cuda';
  OS_MESA3D       = 'mesa3d';
  OS_NVCL         = 'nvcl';
  OS_OPENCL       = 'opencl';
  OS_OPENGL       = 'opengl';
  OS_VULKAN       = 'vulkan';
  OS_TIOS         = 'tios';
  OS_ASHETOS      = 'ashetos';

  { ABIs }
  ABI_NONE        = 'none';
  ABI_GNU         = 'gnu';
  ABI_GNUABIN32   = 'gnuabin32';
  ABI_GNUABI64    = 'gnuabi64';
  ABI_GNUEABI     = 'gnueabi';
  ABI_GNUEABIHF   = 'gnueabihf';
  ABI_GNUF32      = 'gnuf32';
  ABI_GNUSF       = 'gnusf';
  ABI_GNUX32      = 'gnux32';
  ABI_EABI        = 'eabi';
  ABI_EABIHF      = 'eabihf';
  ABI_ABIN32      = 'abin32';
  ABI_X32         = 'x32';
  ABI_ILP32       = 'ilp32';
  ABI_ANDROID     = 'android';
  ABI_ANDROIDEABI = 'androideabi';
  ABI_MUSL        = 'musl';
  ABI_MUSLABIN32  = 'muslabin32';
  ABI_MUSLABI64   = 'muslabi64';
  ABI_MUSLEABI    = 'musleabi';
  ABI_MUSLEABIHF  = 'musleabihf';
  ABI_MUSLF32     = 'muslf32';
  ABI_MUSLSF      = 'muslsf';
  ABI_MUSLX32     = 'muslx32';
  ABI_MSVC        = 'msvc';
  ABI_ITANIUM     = 'itanium';
  ABI_SIMULATOR   = 'simulator';
  ABI_OHOS        = 'ohos';
  ABI_OHOSEABI    = 'ohoseabi';
  ABI_CALL0       = 'call0';

  { PC_ZIG_ARCHS }
  // Every architecture name above, for the exact checks below
  PC_ZIG_ARCHS: array[0..60] of string = (
    ARCH_AARCH64,
    ARCH_AARCH64_BE,
    ARCH_ALPHA,
    ARCH_AMDGCN,
    ARCH_ARC,
    ARCH_ARCEB,
    ARCH_ARM,
    ARCH_ARMEB,
    ARCH_AVR,
    ARCH_BPFEB,
    ARCH_BPFEL,
    ARCH_CSKY,
    ARCH_EZ80,
    ARCH_HEXAGON,
    ARCH_HPPA,
    ARCH_HPPA64,
    ARCH_KALIMBA,
    ARCH_KVX,
    ARCH_LANAI,
    ARCH_LOONGARCH32,
    ARCH_LOONGARCH64,
    ARCH_M68K,
    ARCH_M88K,
    ARCH_MICROBLAZE,
    ARCH_MICROBLAZEEL,
    ARCH_MIPS,
    ARCH_MIPSEL,
    ARCH_MIPS64,
    ARCH_MIPS64EL,
    ARCH_MSP430,
    ARCH_NVPTX,
    ARCH_NVPTX64,
    ARCH_OR1K,
    ARCH_POWERPC,
    ARCH_POWERPCLE,
    ARCH_POWERPC64,
    ARCH_POWERPC64LE,
    ARCH_PROPELLER,
    ARCH_RISCV32,
    ARCH_RISCV32BE,
    ARCH_RISCV64,
    ARCH_RISCV64BE,
    ARCH_S390X,
    ARCH_SH,
    ARCH_SHEB,
    ARCH_SPARC,
    ARCH_SPARC64,
    ARCH_SPORK8,
    ARCH_SPIRV32,
    ARCH_SPIRV64,
    ARCH_THUMB,
    ARCH_THUMBEB,
    ARCH_VE,
    ARCH_WASM32,
    ARCH_WASM64,
    ARCH_X86_16,
    ARCH_X86,
    ARCH_X86_64,
    ARCH_XCORE,
    ARCH_XTENSA,
    ARCH_XTENSAEB
  );

  { PC_ZIG_OSES }
  // Every operating system name above, for the exact checks below
  PC_ZIG_OSES: array[0..47] of string = (
    OS_FREESTANDING,
    OS_OTHER,
    OS_CONTIKI,
    OS_FUCHSIA,
    OS_HERMIT,
    OS_MANAGARM,
    OS_HAIKU,
    OS_HURD,
    OS_ILLUMOS,
    OS_LINUX,
    OS_PLAN9,
    OS_RTEMS,
    OS_SERENITY,
    OS_DRAGONFLY,
    OS_FREEBSD,
    OS_NETBSD,
    OS_OPENBSD,
    OS_DRIVERKIT,
    OS_IOS,
    OS_MACCATALYST,
    OS_MACOS,
    OS_TVOS,
    OS_VISIONOS,
    OS_WATCHOS,
    OS_WINDOWS,
    OS_UEFI,
    OS_3DS,
    OS_WIIU,
    OS_SWITCH,
    OS_GBA,
    OS_PSX,
    OS_PS3,
    OS_PS4,
    OS_PS5,
    OS_PSP,
    OS_VITA,
    OS_EMSCRIPTEN,
    OS_WASI,
    OS_AMDHSA,
    OS_AMDPAL,
    OS_CUDA,
    OS_MESA3D,
    OS_NVCL,
    OS_OPENCL,
    OS_OPENGL,
    OS_VULKAN,
    OS_TIOS,
    OS_ASHETOS
  );

  { PC_ZIG_ABIS }
  // Every ABI name above, for the exact checks below
  PC_ZIG_ABIS: array[0..29] of string = (
    ABI_NONE,
    ABI_GNU,
    ABI_GNUABIN32,
    ABI_GNUABI64,
    ABI_GNUEABI,
    ABI_GNUEABIHF,
    ABI_GNUF32,
    ABI_GNUSF,
    ABI_GNUX32,
    ABI_EABI,
    ABI_EABIHF,
    ABI_ABIN32,
    ABI_X32,
    ABI_ILP32,
    ABI_ANDROID,
    ABI_ANDROIDEABI,
    ABI_MUSL,
    ABI_MUSLABIN32,
    ABI_MUSLABI64,
    ABI_MUSLEABI,
    ABI_MUSLEABIHF,
    ABI_MUSLF32,
    ABI_MUSLSF,
    ABI_MUSLX32,
    ABI_MSVC,
    ABI_ITANIUM,
    ABI_SIMULATOR,
    ABI_OHOS,
    ABI_OHOSEABI,
    ABI_CALL0
  );

// True when AName is exactly one of zig's architecture names (case-sensitive)
function IsZigArch(const AName: string): Boolean;

// True when AName is exactly one of zig's operating system names (case-sensitive)
function IsZigOS(const AName: string): Boolean;

// True when AName is exactly one of zig's ABI names (case-sensitive)
function IsZigAbi(const AName: string): Boolean;

implementation

function DoIsOneOf(const AName: string; const ANames: array of string): Boolean;
var
  LI: Integer;
begin
  Result := False;
  for LI := Low(ANames) to High(ANames) do
  begin
    if ANames[LI] = AName then
      Exit(True);
  end;
end;

function IsZigArch(const AName: string): Boolean;
begin
  Result := DoIsOneOf(AName, PC_ZIG_ARCHS);
end;

function IsZigOS(const AName: string): Boolean;
begin
  Result := DoIsOneOf(AName, PC_ZIG_OSES);
end;

function IsZigAbi(const AName: string): Boolean;
begin
  Result := DoIsOneOf(AName, PC_ZIG_ABIS);
end;

end.
