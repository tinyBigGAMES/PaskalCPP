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
  PaskalCPP.Debug.Symbols - the source map of a PE program under the debugger

  DbgHelp over the PDB zig writes beside a debug build: address <-> .pcpp
  line (every address of a line), the function at an address, a frame's
  locals and parameters, globals by name, type layouts, and the stack walk
  (each frame with its own unwound registers). API and the reference
  defects it does not port (P1-P6, R6): research\editor\debugger-api.md
  (PLAN-EDITOR E3 e2); what the PDB holds: research\editor\debugger-pdb.md.

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Resources,
    PaskalCPP.Common (PC_SRC_EXT), PaskalCPP.Debug.Target (TPCDebugContext)
  Notes:
    - dbghelp.dll is loaded from the system folder, the W entry points only
      (P1). DbgHelp is single-threaded for the whole process: every call,
      of every instance, runs under one unit-wide lock (P6).
    - A module is checked when it is added: an image that must have line
      numbers and has none is DB0006 (P5). Every module the process loads
      is added (the stack walk unwinds through system frames too).
    - A frame above the top is looked up at its return address - 1 (the
      call's own line and scope, not the next one's): TPCDebugFrame.
      LookupAddress.
    - A miss (no line, no symbol at an address) is a False result, never a
      report: the caller decides what a miss means.
===============================================================================}

unit PaskalCPP.Debug.Symbols;

interface

uses
  WinApi.Windows,
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.Debug.Target;

const
  { PC_ERR_DBG_005 }
  PC_ERR_DBG_005 = 'DB0005';   // the symbol handler cannot start
  { PC_ERR_DBG_006 }
  PC_ERR_DBG_006 = 'DB0006';   // an image that must have line numbers has none
  { PC_ERR_DBG_010 }
  PC_ERR_DBG_010 = 'DB0010';   // a symbol call failed with an OS reason

  { PC_DBG_CV_AMD64_RBP }
  // CodeView register numbers of a register-relative symbol (x1 probed 334)
  PC_DBG_CV_AMD64_RBP = 334;
  { PC_DBG_CV_AMD64_RSP }
  PC_DBG_CV_AMD64_RSP = 335;
  { PC_DBG_STACK_MAX }
  // The deepest stack walked (frames)
  PC_DBG_STACK_MAX = 256;

type
  { TPCDebugLine }
  // One line-table entry: the source file (TUtils.ResolvePath spelling),
  // its line, the address the entry starts at
  TPCDebugLine = record
    FileName: string;
    Line: Integer;
    Address: UInt64;
    IsPcpp: Boolean;          // the file is a .pcpp (not the runtime, not C/C++)
  end;

  { TPCDebugFrame }
  // One frame of a walk: the registers as unwound to it, the address its
  // lookups use (RIP for the top frame, RIP - 1 above it: inside the call)
  TPCDebugFrame = record
    Context: TPCDebugContext;
    LookupAddress: UInt64;
    HasLine: Boolean;
    Line: TPCDebugLine;
    FunctionName: string;     // the C++ name ('' = none known)
    FunctionStart: UInt64;
  end;

  { TPCDebugSymbol }
  // A local, a parameter or a global, as the PDB names it
  TPCDebugSymbol = record
    CppName: string;
    IsParam: Boolean;
    IsRegRel: Boolean;        // its place is Register + Offset in a frame
    Register: Cardinal;       // PC_DBG_CV_AMD64_RBP / _RSP
    Offset: Int64;            // register-relative (SYMBOL_INFOW.Address, signed, x1)
    Address: UInt64;          // a global: its absolute address
    TypeIndex: Cardinal;
    ModuleBase: UInt64;
    // Where the value lives in AFrame: register-relative = that register of
    // the frame + Offset, otherwise Address; False for any other register
    function ValueAddress(const AFrame: TPCDebugFrame; out AAddress: UInt64): Boolean;
  end;

  { TPCDebugTypeTag }
  TPCDebugTypeTag = (
    dttBase,
    dttPointer,
    dttUdt,
    dttEnum,
    dttArray,
    dttTypedef,
    dttFunction,
    dttOther
  );

  { TPCDebugField }
  // A data member, or a parent type's part (IsBase: CppName = the parent's
  // type name, its own fields under TypeIndex)
  TPCDebugField = record
    CppName: string;
    Offset: Cardinal;
    TypeIndex: Cardinal;
    IsBase: Boolean;
    // A bitfield: its bits BitPosition .. + BitWidth - 1 of the storage unit
    // (TypeIndex's size) at Offset
    IsBitfield: Boolean;
    BitPosition: Cardinal;
    BitWidth: Cardinal;
  end;

  { TPCDebugEnumerator }
  TPCDebugEnumerator = record
    CppName: string;
    Value: Int64;
  end;

  { TPCDebugType }
  // One type as the PDB lays it out. ElementType: a pointer's target, an
  // array's element, a typedef's type, an enum's underlying type
  TPCDebugType = record
    Tag: TPCDebugTypeTag;
    CppName: string;          // UDT, enum, typedef ('' for the others)
    Length: UInt64;           // bytes (TI_GET_LENGTH)
    BaseType: Cardinal;       // dttBase: the PDB's basic type number
    ElementType: Cardinal;
    Count: Cardinal;          // dttArray: elements
    Fields: TArray<TPCDebugField>;
    Enumerators: TArray<TPCDebugEnumerator>;
  end;

  { TPCDebugReadMemory }
  // How the stack walk reads the program (the target's ReadMemory: patches
  // read as the program's own bytes)
  TPCDebugReadMemory = reference to function(const AAddress: UInt64; const ASize: NativeUInt;
    out ABytes: TBytes): Boolean;

  { TPCDebugSymbols }
  // The source map of one debugged process. Open with its handle, add every
  // module it loads, then ask while the process is stopped
  TPCDebugSymbols = class(TBaseObject)
  private
    FProcess: THandle;
    FOpen: Boolean;
    FModules: TList<UInt64>;
    // Each added image's folder: DbgHelp finds a PDB beside its image only
    // through the search path (zig writes <name>.pdb next to the binary)
    FSearchFolders: TList<string>;
    function DoCheckOpen(): Boolean;
    function DoLineOf(const AFileName: PWideChar; const ALine: Cardinal;
      const AAddress: UInt64): TPCDebugLine;
    function DoTypeDword(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
      const AInfo: DWORD; out AValue: DWORD): Boolean;
    function DoTypeName(const AModuleBase: UInt64; const ATypeIndex: Cardinal): string;
    function DoChildren(const AModuleBase: UInt64; const ATypeIndex: Cardinal): TArray<Cardinal>;
    procedure DoFields(const AModuleBase: UInt64; const ATypeIndex: Cardinal; var AType: TPCDebugType);
    procedure DoEnumerators(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
      var AType: TPCDebugType);
    // ResolveLine's addresses through PastPrologue; ALine = the line they
    // land on when every one of them moved
    function DoPastPrologues(const AAddresses: TList<UInt64>; var ALine: Integer): TArray<UInt64>;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // SymInitializeW on the process (no invade); DB0005
    function Open(const AProcess: THandle): Boolean;
    procedure Close();
    function IsOpen(): Boolean;

    // Loads an image at its base; ARequireLines = the program (or the dll
    // debugged): no line numbers there is DB0006. A load failure is DB0010
    function AddModule(const AImagePath: string; const ABase: UInt64;
      const ARequireLines: Boolean): Boolean;
    procedure RemoveModule(const ABase: UInt64);

    function LineAt(const AAddress: UInt64; out ALine: TPCDebugLine): Boolean;
    // The line DbgHelp places a breakpoint on for AFile:ALine (the verified
    // line, AActualLine) and EVERY address of it in every module (P4); a
    // prologue address moves past it (PastPrologue), a header line to the
    // line its routine's code starts on
    function ResolveLine(const AFile: string; const ALine: Integer; out AActualLine: Integer;
      out AAddresses: TArray<UInt64>): Boolean;
    function FunctionAt(const AAddress: UInt64; out AName: string; out AStart: UInt64;
      out ASize: Cardinal): Boolean;
    // A function's first instruction is its prologue (frame not set up,
    // params not stored yet: e5b probe): its next line-table entry, the first
    // address a stop may land on. Any other address comes back as is
    function PastPrologue(const AAddress: UInt64): UInt64;
    // The frame's locals and parameters (scope at LookupAddress; P2). False
    // + DB0010 when DbgHelp fails; an empty scope is True with none
    function FrameSymbols(const AFrame: TPCDebugFrame; out ASymbols: TArray<TPCDebugSymbol>): Boolean;
    function GlobalSymbol(const ACppName: string; out ASymbol: TPCDebugSymbol): Boolean;
    function DescribeType(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
      out AType: TPCDebugType): Boolean;
    // From the stopped thread's registers outwards: the top frame first,
    // ends at RIP 0, no progress or PC_DBG_STACK_MAX frames (R6)
    function WalkStack(const ATop: TPCDebugContext; const AReader: TPCDebugReadMemory): TArray<TPCDebugFrame>;
  end;

implementation

uses
  System.SyncObjs,
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.Common;

const
  { PC_DBG_DBGHELP_DLL }
  // Loaded from the system folder only (x1: C:\Windows\System32\dbghelp.dll)
  PC_DBG_DBGHELP_DLL = 'dbghelp.dll';

  { PC_DBG_SYMOPT_UNDNAME }
  PC_DBG_SYMOPT_UNDNAME = $00000002;
  { PC_DBG_SYMOPT_LOAD_LINES }
  PC_DBG_SYMOPT_LOAD_LINES = $00000010;
  { PC_DBG_SYMOPT_FAIL_CRITICAL_ERRORS }
  PC_DBG_SYMOPT_FAIL_CRITICAL_ERRORS = $00000200;
  { PC_DBG_SYMOPT_NO_PROMPTS }
  PC_DBG_SYMOPT_NO_PROMPTS = $00080000;

  { PC_DBG_SYMFLAG_REGREL }
  PC_DBG_SYMFLAG_REGREL = $00000010;
  { PC_DBG_SYMFLAG_PARAMETER }
  PC_DBG_SYMFLAG_PARAMETER = $00000040;

  { PC_DBG_MAX_SYM_NAME }
  // Characters of a symbol name read back (DbgHelp's MAX_SYM_NAME)
  PC_DBG_MAX_SYM_NAME = 2000;

  // IMAGEHLP_SYMBOL_TYPE_INFO values (x1 probed 0 1 2 3 5)
  { PC_DBG_TI_GET_SYMTAG }
  PC_DBG_TI_GET_SYMTAG = 0;
  { PC_DBG_TI_GET_SYMNAME }
  PC_DBG_TI_GET_SYMNAME = 1;
  { PC_DBG_TI_GET_LENGTH }
  PC_DBG_TI_GET_LENGTH = 2;
  { PC_DBG_TI_GET_TYPEID }
  PC_DBG_TI_GET_TYPEID = 4;
  { PC_DBG_TI_GET_BASETYPE }
  PC_DBG_TI_GET_BASETYPE = 5;
  { PC_DBG_TI_FINDCHILDREN }
  PC_DBG_TI_FINDCHILDREN = 7;
  { PC_DBG_TI_GET_DATAKIND }
  PC_DBG_TI_GET_DATAKIND = 8;
  { PC_DBG_TI_GET_OFFSET }
  PC_DBG_TI_GET_OFFSET = 10;
  { PC_DBG_TI_GET_VALUE }
  PC_DBG_TI_GET_VALUE = 11;
  { PC_DBG_TI_GET_COUNT }
  PC_DBG_TI_GET_COUNT = 12;
  { PC_DBG_TI_GET_CHILDRENCOUNT }
  PC_DBG_TI_GET_CHILDRENCOUNT = 13;
  { PC_DBG_TI_GET_BITPOSITION }
  // A bitfield member's first bit in its storage unit; fails for any other member
  PC_DBG_TI_GET_BITPOSITION = 14;

  // SymTagEnum values (x1 probed 5 7 14; the others: e2 tests)
  { PC_DBG_TAG_DATA }
  PC_DBG_TAG_DATA = 7;
  { PC_DBG_TAG_UDT }
  PC_DBG_TAG_UDT = 11;
  { PC_DBG_TAG_ENUM }
  PC_DBG_TAG_ENUM = 12;
  { PC_DBG_TAG_FUNCTION_TYPE }
  PC_DBG_TAG_FUNCTION_TYPE = 13;
  { PC_DBG_TAG_POINTER }
  PC_DBG_TAG_POINTER = 14;
  { PC_DBG_TAG_ARRAY }
  PC_DBG_TAG_ARRAY = 15;
  { PC_DBG_TAG_BASE_TYPE }
  PC_DBG_TAG_BASE_TYPE = 16;
  { PC_DBG_TAG_TYPEDEF }
  PC_DBG_TAG_TYPEDEF = 17;
  { PC_DBG_TAG_BASE_CLASS }
  PC_DBG_TAG_BASE_CLASS = 18;

  // DataKind values of a UDT's / enum's data children
  { PC_DBG_DATA_IS_MEMBER }
  PC_DBG_DATA_IS_MEMBER = 7;
  { PC_DBG_DATA_IS_CONSTANT }
  PC_DBG_DATA_IS_CONSTANT = 9;

  { PC_DBG_MACHINE_AMD64 }
  PC_DBG_MACHINE_AMD64 = $8664;
  { PC_DBG_ADDR_MODE_FLAT }
  PC_DBG_ADDR_MODE_FLAT = 3;

  // VARIANT value kinds TI_GET_VALUE gives an enumerator
  { PC_DBG_VT_I2 }
  PC_DBG_VT_I2 = 2;
  { PC_DBG_VT_I4 }
  PC_DBG_VT_I4 = 3;
  { PC_DBG_VT_I1 }
  PC_DBG_VT_I1 = 16;
  { PC_DBG_VT_UI1 }
  PC_DBG_VT_UI1 = 17;
  { PC_DBG_VT_UI2 }
  PC_DBG_VT_UI2 = 18;
  { PC_DBG_VT_UI4 }
  PC_DBG_VT_UI4 = 19;
  { PC_DBG_VT_I8 }
  PC_DBG_VT_I8 = 20;
  { PC_DBG_VT_UI8 }
  PC_DBG_VT_UI8 = 21;
  { PC_DBG_VT_INT }
  PC_DBG_VT_INT = 22;
  { PC_DBG_VT_UINT }
  PC_DBG_VT_UINT = 23;
  { PC_DBG_VARIANT_SIZE }
  // A Win64 VARIANT: the kind at 0, the value at 8
  PC_DBG_VARIANT_SIZE = 24;
  { PC_DBG_VARIANT_VALUE_OFFSET }
  PC_DBG_VARIANT_VALUE_OFFSET = 8;

type
  // DbgHelp's records, as dbghelp.h lays them out on x64 (natural alignment)

  { TPCDbgLineW64 }
  // IMAGEHLP_LINEW64
  TPCDbgLineW64 = record
    SizeOfStruct: DWORD;
    Key: Pointer;
    LineNumber: DWORD;
    FileName: PWideChar;
    Address: UInt64;
  end;

  { TPCDbgSrcCodeInfoW }
  // SRCCODEINFOW
  TPCDbgSrcCodeInfoW = record
    SizeOfStruct: DWORD;
    Key: Pointer;
    ModBase: UInt64;
    Obj: array[0..MAX_PATH] of WideChar;
    FileName: array[0..MAX_PATH] of WideChar;
    LineNumber: DWORD;
    Address: UInt64;
  end;
  { PPCDbgSrcCodeInfoW }
  PPCDbgSrcCodeInfoW = ^TPCDbgSrcCodeInfoW;

  { TPCDbgModuleW64 }
  // IMAGEHLP_MODULEW64 (the current layout, MachineType + Reserved last)
  TPCDbgModuleW64 = record
    SizeOfStruct: DWORD;
    BaseOfImage: UInt64;
    ImageSize: DWORD;
    TimeDateStamp: DWORD;
    CheckSum: DWORD;
    NumSyms: DWORD;
    SymType: DWORD;
    ModuleName: array[0..31] of WideChar;
    ImageName: array[0..255] of WideChar;
    LoadedImageName: array[0..255] of WideChar;
    LoadedPdbName: array[0..255] of WideChar;
    CVSig: DWORD;
    CVData: array[0..MAX_PATH * 3 - 1] of WideChar;
    PdbSig: DWORD;
    PdbSig70: TGUID;
    PdbAge: DWORD;
    PdbUnmatched: BOOL;
    DbgUnmatched: BOOL;
    HasLineNumbers: BOOL;
    HasGlobalSymbols: BOOL;
    HasTypeInfo: BOOL;
    IsSourceIndexed: BOOL;
    HasPublics: BOOL;
    MachineType: DWORD;
    Reserved: DWORD;
  end;

  { TPCDbgSymbolInfoW }
  // SYMBOL_INFOW (Name: the first character; the buffer holds the rest)
  TPCDbgSymbolInfoW = record
    SizeOfStruct: ULONG;
    TypeIndex: ULONG;
    Reserved: array[0..1] of UInt64;
    Index: ULONG;
    Size: ULONG;
    ModBase: UInt64;
    Flags: ULONG;
    Value: UInt64;
    Address: UInt64;
    Register: ULONG;
    Scope: ULONG;
    Tag: ULONG;
    NameLen: ULONG;
    MaxNameLen: ULONG;
    Name: array[0..0] of WideChar;
  end;
  { PPCDbgSymbolInfoW }
  PPCDbgSymbolInfoW = ^TPCDbgSymbolInfoW;

  { TPCDbgScopeFrame }
  // IMAGEHLP_STACK_FRAME (SymSetContext)
  TPCDbgScopeFrame = record
    InstructionOffset: UInt64;
    ReturnOffset: UInt64;
    FrameOffset: UInt64;
    StackOffset: UInt64;
    BackingStoreOffset: UInt64;
    FuncTableEntry: UInt64;
    Params: array[0..3] of UInt64;
    Reserved: array[0..4] of UInt64;
    IsVirtual: BOOL;
    Reserved2: ULONG;
  end;

  { TPCDbgAddress64 }
  // ADDRESS64
  TPCDbgAddress64 = record
    Offset: UInt64;
    Segment: Word;
    Mode: DWORD;
  end;

  { TPCDbgKdHelp64 }
  // KDHELP64 (the current layout; StackWalk64 fills it for kernel frames only)
  TPCDbgKdHelp64 = record
    Thread: UInt64;
    ThCallbackStack: DWORD;
    ThCallbackBStore: DWORD;
    NextCallback: DWORD;
    FramePointer: DWORD;
    KiCallUserMode: UInt64;
    KeUserCallbackDispatcher: UInt64;
    SystemRangeStart: UInt64;
    KiUserExceptionDispatcher: UInt64;
    StackBase: UInt64;
    StackLimit: UInt64;
    BuildVersion: DWORD;
    RetpolineStubFunctionTableSize: DWORD;
    RetpolineStubFunctionTable: UInt64;
    RetpolineStubOffset: DWORD;
    RetpolineStubSize: DWORD;
    Reserved0: array[0..1] of UInt64;
  end;

  { TPCDbgStackFrame64 }
  // STACKFRAME64
  TPCDbgStackFrame64 = record
    AddrPC: TPCDbgAddress64;
    AddrReturn: TPCDbgAddress64;
    AddrFrame: TPCDbgAddress64;
    AddrStack: TPCDbgAddress64;
    AddrBStore: TPCDbgAddress64;
    FuncTableEntry: Pointer;
    Params: array[0..3] of UInt64;
    IsFar: BOOL;
    IsVirtual: BOOL;
    Reserved: array[0..2] of UInt64;
    KdHelp: TPCDbgKdHelp64;
  end;

  { TPCDbgLineQuery }
  // SymEnumLinesW's context: the file (backslashes, no long-path prefix) and
  // the line asked for; the result is the first line at or after it that
  // has code (Line, 0 = none) with every address of it
  TPCDbgLineQuery = record
    FileName: string;
    FromLine: Cardinal;
    Line: Cardinal;
    Addresses: TList<UInt64>;
    FailText: string;         // '' = the walk went through; else why it stopped
  end;
  { PPCDbgLineQuery }
  PPCDbgLineQuery = ^TPCDbgLineQuery;

  { TPCDbgRangeQuery }
  // SymEnumLinesW's context for PastPrologue: the smallest line-table entry
  // address in [Low, High) (First, 0 = none)
  TPCDbgRangeQuery = record
    Low: UInt64;
    High: UInt64;
    First: UInt64;
    FailText: string;         // '' = the walk went through; else why it stopped
  end;
  { PPCDbgRangeQuery }
  PPCDbgRangeQuery = ^TPCDbgRangeQuery;

  // DbgHelp entry points (stdcall, W forms only: P1)
  { TPCDbgSymInitializeW }
  TPCDbgSymInitializeW = function(AProcess: THandle; ASearchPath: PWideChar;
    AInvade: BOOL): BOOL; stdcall;
  { TPCDbgSymCleanup }
  TPCDbgSymCleanup = function(AProcess: THandle): BOOL; stdcall;
  { TPCDbgSymSetSearchPathW }
  TPCDbgSymSetSearchPathW = function(AProcess: THandle; ASearchPath: PWideChar): BOOL; stdcall;
  { TPCDbgSymSetOptions }
  TPCDbgSymSetOptions = function(AOptions: DWORD): DWORD; stdcall;
  { TPCDbgSymLoadModuleExW }
  TPCDbgSymLoadModuleExW = function(AProcess: THandle; AFile: THandle; AImageName: PWideChar;
    AModuleName: PWideChar; ABase: UInt64; ASize: DWORD; AData: Pointer; AFlags: DWORD): UInt64; stdcall;
  { TPCDbgSymUnloadModule64 }
  TPCDbgSymUnloadModule64 = function(AProcess: THandle; ABase: UInt64): BOOL; stdcall;
  { TPCDbgSymGetModuleInfoW64 }
  TPCDbgSymGetModuleInfoW64 = function(AProcess: THandle; AAddress: UInt64;
    AInfo: Pointer): BOOL; stdcall;
  { TPCDbgSymGetLineFromAddrW64 }
  TPCDbgSymGetLineFromAddrW64 = function(AProcess: THandle; AAddress: UInt64;
    ADisplacement: PDWORD; ALine: Pointer): BOOL; stdcall;
  { TPCDbgSymEnumLinesW }
  TPCDbgSymEnumLinesW = function(AProcess: THandle; ABase: UInt64; AObj: PWideChar;
    AFile: PWideChar; ACallback: Pointer; AContext: Pointer): BOOL; stdcall;
  { TPCDbgSymFromAddrW }
  TPCDbgSymFromAddrW = function(AProcess: THandle; AAddress: UInt64; ADisplacement: PUInt64;
    ASymbol: Pointer): BOOL; stdcall;
  { TPCDbgSymFromNameW }
  TPCDbgSymFromNameW = function(AProcess: THandle; ANameText: PWideChar;
    ASymbol: Pointer): BOOL; stdcall;
  { TPCDbgSymSetContext }
  TPCDbgSymSetContext = function(AProcess: THandle; AFrame: Pointer;
    AContext: Pointer): BOOL; stdcall;
  { TPCDbgSymEnumSymbolsW }
  TPCDbgSymEnumSymbolsW = function(AProcess: THandle; ABase: UInt64; AMask: PWideChar;
    ACallback: Pointer; AContext: Pointer): BOOL; stdcall;
  { TPCDbgSymGetTypeInfo }
  TPCDbgSymGetTypeInfo = function(AProcess: THandle; ABase: UInt64; ATypeId: ULONG;
    AInfo: DWORD; AValue: Pointer): BOOL; stdcall;
  { TPCDbgStackWalk64 }
  TPCDbgStackWalk64 = function(AMachine: DWORD; AProcess: THandle; AThread: THandle;
    AFrame: Pointer; AContext: Pointer; AReadMemory: Pointer; AFunctionTable: Pointer;
    AModuleBase: Pointer; ATranslate: Pointer): BOOL; stdcall;

var
  // DbgHelp is single-threaded for the whole process (P6): one lock for every
  // call of every TPCDebugSymbols, and for the loader below
  GDbgLock: TCriticalSection;
  GDbgLibrary: HMODULE;
  GSymInitializeW: TPCDbgSymInitializeW;
  GSymCleanup: TPCDbgSymCleanup;
  GSymSetSearchPathW: TPCDbgSymSetSearchPathW;
  GSymSetOptions: TPCDbgSymSetOptions;
  GSymLoadModuleExW: TPCDbgSymLoadModuleExW;
  GSymUnloadModule64: TPCDbgSymUnloadModule64;
  GSymGetModuleInfoW64: TPCDbgSymGetModuleInfoW64;
  GSymGetLineFromAddrW64: TPCDbgSymGetLineFromAddrW64;
  GSymEnumLinesW: TPCDbgSymEnumLinesW;
  GSymFromAddrW: TPCDbgSymFromAddrW;
  GSymFromNameW: TPCDbgSymFromNameW;
  GSymSetContext: TPCDbgSymSetContext;
  GSymEnumSymbolsW: TPCDbgSymEnumSymbolsW;
  GSymGetTypeInfo: TPCDbgSymGetTypeInfo;
  GStackWalk64: TPCDbgStackWalk64;
  // Passed to StackWalk64 as they are (DbgHelp's own unwind helpers)
  GSymFunctionTableAccess64: Pointer;
  GSymGetModuleBase64: Pointer;
  // The reader of the walk in progress (set and cleared under GDbgLock)
  GWalkReader: TPCDebugReadMemory;

{ DoBindEntry }
function DoBindEntry(const AEntryName: string; out AProc: Pointer; var AReason: string): Boolean;
begin
  // One DbgHelp entry point by name; a missing one is the reason the
  // handler cannot start
  AProc := GetProcAddress(GDbgLibrary, PAnsiChar(AnsiString(AEntryName)));
  Result := AProc <> nil;
  if (not Result) and (AReason = '') then
    AReason := Format(RSDbgDbgHelpEntryMissing, [PC_DBG_DBGHELP_DLL, AEntryName]);
end;

{ DoLoadDbgHelp }
function DoLoadDbgHelp(out AReason: string): Boolean;
var
  LFolder: array[0..MAX_PATH] of WideChar;
  LLength: UINT;
  LPath: string;
  LProc: Pointer;
begin
  // Called under GDbgLock. Loaded once per process, from the system folder
  AReason := '';
  if GDbgLibrary <> 0 then
    Exit(True);
  LLength := GetSystemDirectoryW(@LFolder[0], MAX_PATH + 1);
  if (LLength = 0) or (LLength > MAX_PATH) then
  begin
    AReason := SysErrorMessage(GetLastError());
    Exit(False);
  end;
  SetString(LPath, PWideChar(@LFolder[0]), LLength);
  LPath := IncludeTrailingPathDelimiter(LPath) + PC_DBG_DBGHELP_DLL;
  GDbgLibrary := LoadLibraryW(PWideChar(LPath));
  if GDbgLibrary = 0 then
  begin
    AReason := LPath + ': ' + SysErrorMessage(GetLastError());
    Exit(False);
  end;

  // Every entry point, or none of them (a partial set is never used)
  Result := True;
  Result := DoBindEntry('SymInitializeW', LProc, AReason) and Result;
  @GSymInitializeW := LProc;
  Result := DoBindEntry('SymCleanup', LProc, AReason) and Result;
  @GSymCleanup := LProc;
  Result := DoBindEntry('SymSetSearchPathW', LProc, AReason) and Result;
  @GSymSetSearchPathW := LProc;
  Result := DoBindEntry('SymSetOptions', LProc, AReason) and Result;
  @GSymSetOptions := LProc;
  Result := DoBindEntry('SymLoadModuleExW', LProc, AReason) and Result;
  @GSymLoadModuleExW := LProc;
  Result := DoBindEntry('SymUnloadModule64', LProc, AReason) and Result;
  @GSymUnloadModule64 := LProc;
  Result := DoBindEntry('SymGetModuleInfoW64', LProc, AReason) and Result;
  @GSymGetModuleInfoW64 := LProc;
  Result := DoBindEntry('SymGetLineFromAddrW64', LProc, AReason) and Result;
  @GSymGetLineFromAddrW64 := LProc;
  Result := DoBindEntry('SymEnumLinesW', LProc, AReason) and Result;
  @GSymEnumLinesW := LProc;
  Result := DoBindEntry('SymFromAddrW', LProc, AReason) and Result;
  @GSymFromAddrW := LProc;
  Result := DoBindEntry('SymFromNameW', LProc, AReason) and Result;
  @GSymFromNameW := LProc;
  Result := DoBindEntry('SymSetContext', LProc, AReason) and Result;
  @GSymSetContext := LProc;
  Result := DoBindEntry('SymEnumSymbolsW', LProc, AReason) and Result;
  @GSymEnumSymbolsW := LProc;
  Result := DoBindEntry('SymGetTypeInfo', LProc, AReason) and Result;
  @GSymGetTypeInfo := LProc;
  Result := DoBindEntry('StackWalk64', LProc, AReason) and Result;
  @GStackWalk64 := LProc;
  Result := DoBindEntry('SymFunctionTableAccess64', GSymFunctionTableAccess64, AReason) and Result;
  Result := DoBindEntry('SymGetModuleBase64', GSymGetModuleBase64, AReason) and Result;
  if not Result then
  begin
    FreeLibrary(GDbgLibrary);
    GDbgLibrary := 0;
  end;
end;

{ DoEnumLinesCallback }
function DoEnumLinesCallback(const ALineInfo: PPCDbgSrcCodeInfoW; const AContext: Pointer): BOOL; stdcall;
var
  LQuery: PPCDbgLineQuery;
  LFileName: string;
begin
  // Every line-table entry of the module: of the file's entries at or after
  // the line asked for, the smallest line wins and all its addresses are
  // kept. Never an earlier line: DbgHelp's own nearest-line pick
  // (SymGetLineFromName) can go back to the routine's start. The table
  // spells the file as #line did (forward slashes): compared without the
  // slash kind, case-insensitive (Windows file names)
  // No exception crosses back into DbgHelp: a failure stops the walk and
  // ResolveLine reports it
  LQuery := PPCDbgLineQuery(AContext);
  Result := True;
  try
    if ALineInfo^.LineNumber >= LQuery^.FromLine then
    begin
      LFileName := string(PWideChar(@ALineInfo^.FileName[0])).Replace('/', '\');
      if SameText(LFileName, LQuery^.FileName) then
      begin
        if (LQuery^.Line = 0) or (ALineInfo^.LineNumber < LQuery^.Line) then
        begin
          LQuery^.Line := ALineInfo^.LineNumber;
          LQuery^.Addresses.Clear();
        end;
        if (ALineInfo^.LineNumber = LQuery^.Line) and (not LQuery^.Addresses.Contains(ALineInfo^.Address)) then
          LQuery^.Addresses.Add(ALineInfo^.Address);
      end;
    end;
  except
    on E: Exception do
    begin
      LQuery^.FailText := E.Message;
      Result := False;
    end;
  end;
end;

{ DoEnumRangeCallback }
function DoEnumRangeCallback(const ALineInfo: PPCDbgSrcCodeInfoW; const AContext: Pointer): BOOL; stdcall;
var
  LQuery: PPCDbgRangeQuery;
begin
  // Every line-table entry of the module: the smallest address inside the
  // range wins. No exception crosses back into DbgHelp
  LQuery := PPCDbgRangeQuery(AContext);
  Result := True;
  try
    if (ALineInfo^.Address >= LQuery^.Low) and (ALineInfo^.Address < LQuery^.High) then
      if (LQuery^.First = 0) or (ALineInfo^.Address < LQuery^.First) then
        LQuery^.First := ALineInfo^.Address;
  except
    on E: Exception do
    begin
      LQuery^.FailText := E.Message;
      Result := False;
    end;
  end;
end;

{ DoSymbolName }
function DoSymbolName(const AInfo: PPCDbgSymbolInfoW): string;
var
  LEnd: Integer;
begin
  // At most NameLen characters, cut at the first NUL: SymEnumSymbolsW counts
  // the terminator in NameLen, SymFromAddrW does not (e2 probe)
  SetString(Result, PWideChar(@AInfo^.Name[0]), AInfo^.NameLen);
  LEnd := Result.IndexOf(#0);
  if LEnd >= 0 then
    Result := Result.Substring(0, LEnd);
end;

{ DoSymbolOf }
function DoSymbolOf(const AInfo: PPCDbgSymbolInfoW): TPCDebugSymbol;
begin
  Result := Default(TPCDebugSymbol);
  Result.CppName := DoSymbolName(AInfo);
  Result.IsParam := (AInfo^.Flags and PC_DBG_SYMFLAG_PARAMETER) <> 0;
  Result.IsRegRel := (AInfo^.Flags and PC_DBG_SYMFLAG_REGREL) <> 0;
  Result.Register := AInfo^.Register;
  Result.TypeIndex := AInfo^.TypeIndex;
  Result.ModuleBase := AInfo^.ModBase;
  // A register-relative symbol's offset is in Address, signed (x1)
  if Result.IsRegRel then
    Result.Offset := Int64(AInfo^.Address)
  else
    Result.Address := AInfo^.Address;
end;

{ DoEnumSymbolsCallback }
function DoEnumSymbolsCallback(const AInfo: PPCDbgSymbolInfoW; const ASymbolSize: ULONG;
  const AContext: Pointer): BOOL; stdcall;
begin
  // Every symbol of the scope SymSetContext set
  TList<TPCDebugSymbol>(AContext).Add(DoSymbolOf(AInfo));
  Result := True;
end;

{ DoWalkReadCallback }
function DoWalkReadCallback(const AProcess: THandle; const AAddress: UInt64; const ABuffer: Pointer;
  const ASize: DWORD; const ABytesRead: PDWORD): BOOL; stdcall;
var
  LBytes: TBytes;
  LRead: NativeUInt;
  LOk: Boolean;
begin
  // StackWalk64's reads go through the walk's reader (patches read as the
  // program's bytes: the unwinder decodes epilogues from code). An exception
  // must not unwind through DbgHelp's frames: a failed read is a False
  // answer, and the walk ends at the frame it could not unwind
  if Assigned(GWalkReader) then
  begin
    try
      LOk := GWalkReader(AAddress, ASize, LBytes) and (NativeUInt(Length(LBytes)) = ASize);
    except
      on E: Exception do
        LOk := False;
    end;
    Result := LOk;
    if Result and (ASize > 0) then
      Move(LBytes[0], ABuffer^, ASize);
  end
  else
  begin
    LRead := 0;
    Result := ReadProcessMemory(AProcess, Pointer(AAddress), ABuffer, ASize, LRead);
  end;
  if ABytesRead <> nil then
  begin
    if Result then
      ABytesRead^ := ASize
    else
      ABytesRead^ := 0;
  end;
end;

{ DoDecodeVariant }
function DoDecodeVariant(const ABuffer: TBytes; out AValue: Int64): Boolean;
var
  LKind: Word;
  LValue: PByte;
begin
  // The integer kinds an enumerator's value comes in; anything else is not
  // an integer value
  Move(ABuffer[0], LKind, SizeOf(LKind));
  LValue := @ABuffer[PC_DBG_VARIANT_VALUE_OFFSET];
  Result := True;
  if LKind = PC_DBG_VT_I1 then
    AValue := PShortInt(LValue)^
  else if LKind = PC_DBG_VT_UI1 then
    AValue := PByte(LValue)^
  else if LKind = PC_DBG_VT_I2 then
    AValue := PSmallInt(LValue)^
  else if LKind = PC_DBG_VT_UI2 then
    AValue := PWord(LValue)^
  else if (LKind = PC_DBG_VT_I4) or (LKind = PC_DBG_VT_INT) then
    AValue := PInteger(LValue)^
  else if (LKind = PC_DBG_VT_UI4) or (LKind = PC_DBG_VT_UINT) then
    AValue := PCardinal(LValue)^
  else if (LKind = PC_DBG_VT_I8) or (LKind = PC_DBG_VT_UI8) then
    AValue := PInt64(LValue)^
  else
  begin
    AValue := 0;
    Result := False;
  end;
end;

{ DoSymbolBuffer }
function DoSymbolBuffer(out AInfo: PPCDbgSymbolInfoW): TBytes;
begin
  // A SYMBOL_INFOW with room for PC_DBG_MAX_SYM_NAME characters of name
  SetLength(Result, SizeOf(TPCDbgSymbolInfoW) + PC_DBG_MAX_SYM_NAME * SizeOf(WideChar));
  FillChar(Result[0], Length(Result), 0);
  AInfo := PPCDbgSymbolInfoW(@Result[0]);
  AInfo^.SizeOfStruct := SizeOf(TPCDbgSymbolInfoW);
  AInfo^.MaxNameLen := PC_DBG_MAX_SYM_NAME;
end;

{ DoDbgHelpPath }
function DoDbgHelpPath(const APath: string): string;
begin
  // The plain Windows spelling DbgHelp matches file names in
  Result := TUtils.StripLongPathPrefix(APath).Replace('/', '\');
end;

{ TPCDebugSymbol }

function TPCDebugSymbol.ValueAddress(const AFrame: TPCDebugFrame; out AAddress: UInt64): Boolean;
begin
  AAddress := 0;
  if not IsRegRel then
  begin
    AAddress := Address;
    Exit(Address <> 0);
  end;
  // The frame's own (unwound) register, never the top frame's (R6)
  if Register = PC_DBG_CV_AMD64_RBP then
    AAddress := UInt64(Int64(AFrame.Context.Regs.Rbp) + Offset)
  else if Register = PC_DBG_CV_AMD64_RSP then
    AAddress := UInt64(Int64(AFrame.Context.Regs.Rsp) + Offset)
  else
    Exit(False);
  Result := True;
end;

{ TPCDebugSymbols }

constructor TPCDebugSymbols.Create();
begin
  inherited;

  FModules := TList<UInt64>.Create();
  FSearchFolders := TList<string>.Create();
end;

destructor TPCDebugSymbols.Destroy();
begin
  Close();
  FSearchFolders.Free();
  FModules.Free();

  inherited;
end;

function TPCDebugSymbols.DoCheckOpen(): Boolean;
begin
  // Every query needs Open first (the caller's contract)
  Result := FOpen;
  if not Result then
    FErrors.Add(esError, PC_ERR_DBG_005, RSDbgSymNotOpen, []);
end;

function TPCDebugSymbols.Open(const AProcess: THandle): Boolean;
var
  LReason: string;
begin
  Close();
  LReason := '';
  GDbgLock.Enter();
  try
    Result := DoLoadDbgHelp(LReason);
    if Result then
    begin
      // Process-wide options: no deferred loads, so a module is checked
      // when it is added (P5)
      GSymSetOptions(PC_DBG_SYMOPT_UNDNAME or PC_DBG_SYMOPT_LOAD_LINES or
        PC_DBG_SYMOPT_FAIL_CRITICAL_ERRORS or PC_DBG_SYMOPT_NO_PROMPTS);
      // The handle at full width (x1: a truncated one fails silently later)
      Result := GSymInitializeW(AProcess, nil, False);
      if not Result then
        LReason := SysErrorMessage(GetLastError());
    end;
  finally
    GDbgLock.Leave();
  end;
  if not Result then
  begin
    FErrors.Add(esError, PC_ERR_DBG_005, RSDbgSymInitFailed, [LReason]);
    Exit;
  end;
  FProcess := AProcess;
  FOpen := True;
end;

procedure TPCDebugSymbols.Close();
begin
  if not FOpen then
    Exit;
  GDbgLock.Enter();
  try
    GSymCleanup(FProcess);
  finally
    GDbgLock.Leave();
  end;
  FModules.Clear();
  FSearchFolders.Clear();
  FProcess := 0;
  FOpen := False;
end;

function TPCDebugSymbols.IsOpen(): Boolean;
begin
  Result := FOpen;
end;

function TPCDebugSymbols.AddModule(const AImagePath: string; const ABase: UInt64;
  const ARequireLines: Boolean): Boolean;
var
  LPath: string;
  LBase: UInt64;
  LError: DWORD;
  LInfo: TPCDbgModuleW64;
  LInfoOk: Boolean;
  LFolder: string;
  LSearchOk: Boolean;
begin
  Result := False;
  if not DoCheckOpen() then
    Exit;
  LPath := DoDbgHelpPath(AImagePath);
  LFolder := ExtractFileDir(LPath);
  LSearchOk := True;
  LInfoOk := False;
  LError := ERROR_SUCCESS;
  FillChar(LInfo, SizeOf(LInfo), 0);
  LInfo.SizeOfStruct := SizeOf(LInfo);
  GDbgLock.Enter();
  try
    // The image's folder joins the search path first, so its PDB is found
    if (LFolder <> '') and (not FSearchFolders.Contains(LFolder)) then
    begin
      FSearchFolders.Add(LFolder);
      LSearchOk := GSymSetSearchPathW(FProcess, PWideChar(string.Join(';', FSearchFolders.ToArray())));
      if not LSearchOk then
        LError := GetLastError();
    end;
    if LSearchOk then
    begin
      SetLastError(ERROR_SUCCESS);
      LBase := GSymLoadModuleExW(FProcess, 0, PWideChar(LPath), nil, ABase, 0, nil, 0);
      LError := GetLastError();
      // 0 with no error = the module is already loaded at that base
      if (LBase <> 0) or (LError = ERROR_SUCCESS) then
      begin
        LInfoOk := GSymGetModuleInfoW64(FProcess, ABase, @LInfo);
        if not LInfoOk then
        begin
          LError := GetLastError();
          GSymUnloadModule64(FProcess, ABase);
        end;
      end;
    end;
    // The image a breakpoint needs has no line table: unload it, so no
    // query answers from it as if it were mapped (P5)
    if LInfoOk and ARequireLines and (not LInfo.HasLineNumbers) then
      GSymUnloadModule64(FProcess, ABase);
  finally
    GDbgLock.Leave();
  end;

  if not LInfoOk then
  begin
    FErrors.Add(esError, PC_ERR_DBG_010, RSDbgSymLoadFailed, [AImagePath, SysErrorMessage(LError)]);
    Exit;
  end;
  if ARequireLines and (not LInfo.HasLineNumbers) then
  begin
    FErrors.Add(esError, PC_ERR_DBG_006, RSDbgNoDebugInfo, [AImagePath]);
    Exit;
  end;
  if not FModules.Contains(ABase) then
    FModules.Add(ABase);
  Result := True;
end;

procedure TPCDebugSymbols.RemoveModule(const ABase: UInt64);
begin
  if (not FOpen) or (not FModules.Contains(ABase)) then
    Exit;
  GDbgLock.Enter();
  try
    GSymUnloadModule64(FProcess, ABase);
  finally
    GDbgLock.Leave();
  end;
  FModules.Remove(ABase);
end;

function TPCDebugSymbols.DoLineOf(const AFileName: PWideChar; const ALine: Cardinal;
  const AAddress: UInt64): TPCDebugLine;
var
  LName: string;
begin
  // A line-table entry as the API gives it: the file in ResolvePath's
  // spelling (a spelling no path routine takes stays as DbgHelp gave it,
  // as ZigBuild's ResolveReportedPath)
  LName := AFileName;
  Result := Default(TPCDebugLine);
  try
    Result.FileName := TUtils.ResolvePath(LName);
  except
    on E: Exception do
      Result.FileName := LName;
  end;
  Result.Line := Integer(ALine);
  Result.Address := AAddress;
  Result.IsPcpp := SameText(ExtractFileExt(LName), '.' + PC_SRC_EXT);
end;

function TPCDebugSymbols.LineAt(const AAddress: UInt64; out ALine: TPCDebugLine): Boolean;
var
  LLine: TPCDbgLineW64;
  LDisplacement: DWORD;
begin
  ALine := Default(TPCDebugLine);
  Result := False;
  if not DoCheckOpen() then
    Exit;
  FillChar(LLine, SizeOf(LLine), 0);
  LLine.SizeOfStruct := SizeOf(LLine);
  LDisplacement := 0;
  GDbgLock.Enter();
  try
    Result := GSymGetLineFromAddrW64(FProcess, AAddress, @LDisplacement, @LLine);
    // The file name is DbgHelp's buffer: copied before the lock is left
    if Result then
      ALine := DoLineOf(LLine.FileName, LLine.LineNumber, LLine.Address);
  finally
    GDbgLock.Leave();
  end;
end;

function TPCDebugSymbols.ResolveLine(const AFile: string; const ALine: Integer;
  out AActualLine: Integer; out AAddresses: TArray<UInt64>): Boolean;
var
  LQuery: TPCDbgLineQuery;
  LBase: UInt64;
begin
  AActualLine := 0;
  AAddresses := [];
  Result := False;
  if (not DoCheckOpen()) or (ALine < 1) then
    Exit;
  LQuery := Default(TPCDbgLineQuery);
  LQuery.FileName := DoDbgHelpPath(AFile);
  LQuery.FromLine := Cardinal(ALine);
  LQuery.Line := 0;
  LQuery.Addresses := TList<UInt64>.Create();
  try
    GDbgLock.Enter();
    try
      // The verified line: ALine when it has code, else the next line of the
      // file that does (a comment, a blank line, a @breakpoint, a var
      // section moves forward); every entry of it in every module (a line
      // can have several code ranges: P4)
      for LBase in FModules do
        if LQuery.FailText = '' then
          GSymEnumLinesW(FProcess, LBase, nil, nil, @DoEnumLinesCallback, @LQuery);
    finally
      GDbgLock.Leave();
    end;
    if LQuery.FailText <> '' then
    begin
      FErrors.Add(esError, PC_ERR_DBG_010, RSDbgSymLookupFailed,
        [Format('%s:%d', [AFile, ALine]), LQuery.FailText]);
      Exit;
    end;
    if (LQuery.Line > 0) and (LQuery.Addresses.Count > 0) then
    begin
      AActualLine := Integer(LQuery.Line);
      AAddresses := DoPastPrologues(LQuery.Addresses, AActualLine);
      Result := True;
    end;
  finally
    LQuery.Addresses.Free();
  end;
end;

function TPCDebugSymbols.FunctionAt(const AAddress: UInt64; out AName: string; out AStart: UInt64;
  out ASize: Cardinal): Boolean;
var
  LBuffer: TBytes;
  LInfo: PPCDbgSymbolInfoW;
  LDisplacement: UInt64;
begin
  AName := '';
  AStart := 0;
  ASize := 0;
  Result := False;
  if not DoCheckOpen() then
    Exit;
  LBuffer := DoSymbolBuffer(LInfo);
  LDisplacement := 0;
  GDbgLock.Enter();
  try
    Result := GSymFromAddrW(FProcess, AAddress, @LDisplacement, LInfo);
  finally
    GDbgLock.Leave();
  end;
  if Result then
  begin
    AName := DoSymbolName(LInfo);
    AStart := LInfo^.Address;
    ASize := LInfo^.Size;
  end;
end;

function TPCDebugSymbols.PastPrologue(const AAddress: UInt64): UInt64;
var
  LName: string;
  LStart: UInt64;
  LSize: Cardinal;
  LQuery: TPCDbgRangeQuery;
  LBase: UInt64;
begin
  Result := AAddress;
  if not FunctionAt(AAddress, LName, LStart, LSize) then
    Exit;
  if (LStart <> AAddress) or (LSize = 0) then
    Exit;
  // The function's own entries past its first instruction: the smallest one
  // ends the prologue (clang -O0: header line at the start, the first
  // statement's line once the frame is set up and the params stored)
  LQuery := Default(TPCDbgRangeQuery);
  LQuery.Low := LStart + 1;
  LQuery.High := LStart + LSize;
  LQuery.First := 0;
  GDbgLock.Enter();
  try
    for LBase in FModules do
      if LQuery.FailText = '' then
        GSymEnumLinesW(FProcess, LBase, nil, nil, @DoEnumRangeCallback, @LQuery);
  finally
    GDbgLock.Leave();
  end;
  if LQuery.FailText <> '' then
  begin
    FErrors.Add(esError, PC_ERR_DBG_010, RSDbgSymLookupFailed,
      [Format('$%x', [AAddress]), LQuery.FailText]);
    Exit;
  end;
  // A function with no entry past its start keeps it
  if LQuery.First <> 0 then
    Result := LQuery.First;
end;

function TPCDebugSymbols.DoPastPrologues(const AAddresses: TList<UInt64>; var ALine: Integer): TArray<UInt64>;
var
  LAddress: UInt64;
  LMoved: UInt64;
  LList: TList<UInt64>;
  LAllMoved: Boolean;
  LLine: TPCDebugLine;
begin
  // A line whose code is a prologue (a routine's header) stops where the
  // prologue ends; when every address of it moved, the verified line is the
  // line the stop lands on (e5b). Sorted, each address once
  LAllMoved := True;
  LList := TList<UInt64>.Create();
  try
    for LAddress in AAddresses do
    begin
      LMoved := PastPrologue(LAddress);
      if LMoved = LAddress then
        LAllMoved := False;
      if not LList.Contains(LMoved) then
        LList.Add(LMoved);
    end;
    LList.Sort();
    if LAllMoved and (LList.Count > 0) and LineAt(LList[0], LLine) then
      ALine := LLine.Line;
    Result := LList.ToArray();
  finally
    LList.Free();
  end;
end;

function TPCDebugSymbols.FrameSymbols(const AFrame: TPCDebugFrame;
  out ASymbols: TArray<TPCDebugSymbol>): Boolean;
var
  LScope: TPCDbgScopeFrame;
  LList: TList<TPCDebugSymbol>;
  LError: DWORD;
  LWhat: string;
begin
  ASymbols := [];
  Result := False;
  if not DoCheckOpen() then
    Exit;
  // The scope at the frame's lookup address, with the frame's own frame and
  // stack registers (P2: locals need FrameOffset = rbp, StackOffset = rsp)
  FillChar(LScope, SizeOf(LScope), 0);
  LScope.InstructionOffset := AFrame.LookupAddress;
  LScope.FrameOffset := AFrame.Context.Regs.Rbp;
  LScope.StackOffset := AFrame.Context.Regs.Rsp;
  LError := ERROR_SUCCESS;
  LWhat := '';
  LList := TList<TPCDebugSymbol>.Create();
  try
    GDbgLock.Enter();
    try
      SetLastError(ERROR_SUCCESS);
      Result := GSymSetContext(FProcess, @LScope, nil);
      // FALSE with no error = the context is the one already set (documented
      // DbgHelp behaviour): the scope stands
      if not Result then
      begin
        LError := GetLastError();
        Result := LError = ERROR_SUCCESS;
        LWhat := 'SymSetContext';
      end;
      if Result then
      begin
        Result := GSymEnumSymbolsW(FProcess, 0, '*', @DoEnumSymbolsCallback, LList);
        if not Result then
        begin
          LError := GetLastError();
          LWhat := 'SymEnumSymbolsW';
        end;
      end;
    finally
      GDbgLock.Leave();
    end;
    if Result then
      ASymbols := LList.ToArray()
    else
      FErrors.Add(esError, PC_ERR_DBG_010, RSDbgSymLookupFailed,
        [Format('%s $%x', [LWhat, AFrame.LookupAddress]), SysErrorMessage(LError)]);
  finally
    LList.Free();
  end;
end;

function TPCDebugSymbols.GlobalSymbol(const ACppName: string; out ASymbol: TPCDebugSymbol): Boolean;
var
  LBuffer: TBytes;
  LInfo: PPCDbgSymbolInfoW;
begin
  ASymbol := Default(TPCDebugSymbol);
  Result := False;
  if (not DoCheckOpen()) or (ACppName = '') then
    Exit;
  LBuffer := DoSymbolBuffer(LInfo);
  GDbgLock.Enter();
  try
    Result := GSymFromNameW(FProcess, PWideChar(ACppName), LInfo);
  finally
    GDbgLock.Leave();
  end;
  if Result then
    ASymbol := DoSymbolOf(LInfo);
end;

function TPCDebugSymbols.DoTypeDword(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
  const AInfo: DWORD; out AValue: DWORD): Boolean;
begin
  // Called under GDbgLock: one DWORD-valued type property
  AValue := 0;
  Result := GSymGetTypeInfo(FProcess, AModuleBase, ATypeIndex, AInfo, @AValue);
end;

function TPCDebugSymbols.DoTypeName(const AModuleBase: UInt64; const ATypeIndex: Cardinal): string;
var
  LName: PWideChar;
begin
  // Called under GDbgLock, for named tags only (x1: another tag's answer is
  // garbage). The text is DbgHelp's LocalAlloc'd buffer: copied, then freed
  Result := '';
  LName := nil;
  if GSymGetTypeInfo(FProcess, AModuleBase, ATypeIndex, PC_DBG_TI_GET_SYMNAME, @LName) and
    (LName <> nil) then
  begin
    Result := LName;
    LocalFree(HLOCAL(LName));
  end;
end;

function TPCDebugSymbols.DoChildren(const AModuleBase: UInt64; const ATypeIndex: Cardinal): TArray<Cardinal>;
var
  LCount: DWORD;
  LParams: TArray<Cardinal>;
  LIndex: Integer;
begin
  // Called under GDbgLock. TI_FINDCHILDREN_PARAMS = Count, Start, then the
  // child ids
  Result := [];
  if (not DoTypeDword(AModuleBase, ATypeIndex, PC_DBG_TI_GET_CHILDRENCOUNT, LCount)) or (LCount = 0) then
    Exit;
  SetLength(LParams, 2 + LCount);
  FillChar(LParams[0], Length(LParams) * SizeOf(Cardinal), 0);
  LParams[0] := LCount;
  LParams[1] := 0;
  if not GSymGetTypeInfo(FProcess, AModuleBase, ATypeIndex, PC_DBG_TI_FINDCHILDREN, @LParams[0]) then
    Exit;
  SetLength(Result, LCount);
  for LIndex := 0 to Integer(LCount) - 1 do
    Result[LIndex] := LParams[2 + LIndex];
end;

procedure TPCDebugSymbols.DoFields(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
  var AType: TPCDebugType);
var
  LChild: Cardinal;
  LTag: DWORD;
  LKind: DWORD;
  LField: TPCDebugField;
  LOffset: DWORD;
  LTypeId: DWORD;
  LBitPosition: DWORD;
  LBitWidth: UInt64;
begin
  // Called under GDbgLock: a UDT's data members and parent parts, in the
  // PDB's order; methods, nested types and statics are not part of a value
  for LChild in DoChildren(AModuleBase, ATypeIndex) do
  begin
    if not DoTypeDword(AModuleBase, LChild, PC_DBG_TI_GET_SYMTAG, LTag) then
      Continue;
    LField := Default(TPCDebugField);
    if LTag = PC_DBG_TAG_DATA then
    begin
      if (not DoTypeDword(AModuleBase, LChild, PC_DBG_TI_GET_DATAKIND, LKind)) or
        (LKind <> PC_DBG_DATA_IS_MEMBER) then
        Continue;
      LField.CppName := DoTypeName(AModuleBase, LChild);
      // A bitfield member answers its bit position; its own length is its
      // width in bits (TI_GET_LENGTH is a ULONG64)
      if DoTypeDword(AModuleBase, LChild, PC_DBG_TI_GET_BITPOSITION, LBitPosition) then
      begin
        LBitWidth := 0;
        if GSymGetTypeInfo(FProcess, AModuleBase, LChild, PC_DBG_TI_GET_LENGTH, @LBitWidth) and (LBitWidth > 0) then
        begin
          LField.IsBitfield := True;
          LField.BitPosition := LBitPosition;
          LField.BitWidth := Cardinal(LBitWidth);
        end;
      end;
    end
    else if LTag = PC_DBG_TAG_BASE_CLASS then
      LField.IsBase := True
    else
      Continue;
    if (not DoTypeDword(AModuleBase, LChild, PC_DBG_TI_GET_OFFSET, LOffset)) or
      (not DoTypeDword(AModuleBase, LChild, PC_DBG_TI_GET_TYPEID, LTypeId)) then
      Continue;
    LField.Offset := LOffset;
    LField.TypeIndex := LTypeId;
    // A parent part is named by its type (a base class child has no name)
    if LField.IsBase then
      LField.CppName := DoTypeName(AModuleBase, LTypeId);
    AType.Fields := AType.Fields + [LField];
  end;
end;

procedure TPCDebugSymbols.DoEnumerators(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
  var AType: TPCDebugType);
var
  LChild: Cardinal;
  LTag: DWORD;
  LVariant: TBytes;
  LItem: TPCDebugEnumerator;
begin
  // Called under GDbgLock: an enum's constants with their values
  SetLength(LVariant, PC_DBG_VARIANT_SIZE);
  for LChild in DoChildren(AModuleBase, ATypeIndex) do
  begin
    if (not DoTypeDword(AModuleBase, LChild, PC_DBG_TI_GET_SYMTAG, LTag)) or (LTag <> PC_DBG_TAG_DATA) then
      Continue;
    FillChar(LVariant[0], Length(LVariant), 0);
    if not GSymGetTypeInfo(FProcess, AModuleBase, LChild, PC_DBG_TI_GET_VALUE, @LVariant[0]) then
      Continue;
    LItem := Default(TPCDebugEnumerator);
    if not DoDecodeVariant(LVariant, LItem.Value) then
      Continue;
    LItem.CppName := DoTypeName(AModuleBase, LChild);
    AType.Enumerators := AType.Enumerators + [LItem];
  end;
end;

function TPCDebugSymbols.DescribeType(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
  out AType: TPCDebugType): Boolean;
var
  LTag: DWORD;
  LLength: UInt64;
  LValue: DWORD;
begin
  AType := Default(TPCDebugType);
  Result := False;
  if not DoCheckOpen() then
    Exit;
  GDbgLock.Enter();
  try
    if not DoTypeDword(AModuleBase, ATypeIndex, PC_DBG_TI_GET_SYMTAG, LTag) then
      Exit;
    LLength := 0;
    if GSymGetTypeInfo(FProcess, AModuleBase, ATypeIndex, PC_DBG_TI_GET_LENGTH, @LLength) then
      AType.Length := LLength;

    if LTag = PC_DBG_TAG_BASE_TYPE then
    begin
      AType.Tag := dttBase;
      if DoTypeDword(AModuleBase, ATypeIndex, PC_DBG_TI_GET_BASETYPE, LValue) then
        AType.BaseType := LValue;
    end
    else if LTag = PC_DBG_TAG_POINTER then
      AType.Tag := dttPointer
    else if LTag = PC_DBG_TAG_UDT then
    begin
      AType.Tag := dttUdt;
      AType.CppName := DoTypeName(AModuleBase, ATypeIndex);
      DoFields(AModuleBase, ATypeIndex, AType);
    end
    else if LTag = PC_DBG_TAG_ENUM then
    begin
      AType.Tag := dttEnum;
      AType.CppName := DoTypeName(AModuleBase, ATypeIndex);
      DoEnumerators(AModuleBase, ATypeIndex, AType);
    end
    else if LTag = PC_DBG_TAG_ARRAY then
    begin
      AType.Tag := dttArray;
      if DoTypeDword(AModuleBase, ATypeIndex, PC_DBG_TI_GET_COUNT, LValue) then
        AType.Count := LValue;
    end
    else if LTag = PC_DBG_TAG_TYPEDEF then
    begin
      AType.Tag := dttTypedef;
      AType.CppName := DoTypeName(AModuleBase, ATypeIndex);
    end
    else if LTag = PC_DBG_TAG_FUNCTION_TYPE then
      AType.Tag := dttFunction
    else
      AType.Tag := dttOther;

    // The type a pointer / array / typedef / enum is made of
    if AType.Tag in [dttPointer, dttArray, dttTypedef, dttEnum] then
      if DoTypeDword(AModuleBase, ATypeIndex, PC_DBG_TI_GET_TYPEID, LValue) then
        AType.ElementType := LValue;
    Result := True;
  finally
    GDbgLock.Leave();
  end;
end;

function TPCDebugSymbols.WalkStack(const ATop: TPCDebugContext;
  const AReader: TPCDebugReadMemory): TArray<TPCDebugFrame>;
var
  LBuffer: TBytes;
  LContext: PContext;
  LWalk: TPCDbgStackFrame64;
  LFrames: TList<TPCDebugFrame>;
  LFrame: TPCDebugFrame;
  LLastPc: UInt64;
  LLastStack: UInt64;
  LIndex: Integer;
  LSize: Cardinal;
begin
  Result := [];
  if not DoCheckOpen() then
    Exit;
  // StackWalk64 unwinds the CONTEXT in place: a 16-byte aligned copy of the
  // top frame's registers, read back after every step (each frame keeps its
  // own unwound registers: R6)
  SetLength(LBuffer, SizeOf(TContext) + PC_DBG_CONTEXT_ALIGN);
  LContext := PContext((NativeUInt(@LBuffer[0]) + PC_DBG_CONTEXT_ALIGN - 1) and
    not NativeUInt(PC_DBG_CONTEXT_ALIGN - 1));
  LContext^ := ATop.Regs;
  FillChar(LWalk, SizeOf(LWalk), 0);
  LWalk.AddrPC.Offset := ATop.Regs.Rip;
  LWalk.AddrPC.Mode := PC_DBG_ADDR_MODE_FLAT;
  LWalk.AddrFrame.Offset := ATop.Regs.Rbp;
  LWalk.AddrFrame.Mode := PC_DBG_ADDR_MODE_FLAT;
  LWalk.AddrStack.Offset := ATop.Regs.Rsp;
  LWalk.AddrStack.Mode := PC_DBG_ADDR_MODE_FLAT;
  LLastPc := 0;
  LLastStack := 0;
  LFrames := TList<TPCDebugFrame>.Create();
  try
    GDbgLock.Enter();
    try
      GWalkReader := AReader;
      try
        while LFrames.Count < PC_DBG_STACK_MAX do
        begin
          // A thread handle is not needed: the reads go through our routine
          if not GStackWalk64(PC_DBG_MACHINE_AMD64, FProcess, 0, @LWalk, LContext,
            @DoWalkReadCallback, GSymFunctionTableAccess64, GSymGetModuleBase64, nil) then
            Break;
          if LWalk.AddrPC.Offset = 0 then
            Break;
          // No progress (same place, same stack) = the walk is lost
          if (LFrames.Count > 0) and (LWalk.AddrPC.Offset = LLastPc) and
            (LWalk.AddrStack.Offset = LLastStack) then
            Break;
          LLastPc := LWalk.AddrPC.Offset;
          LLastStack := LWalk.AddrStack.Offset;
          LFrame := Default(TPCDebugFrame);
          LFrame.Context.Regs := LContext^;
          LFrame.Context.Regs.Rip := LWalk.AddrPC.Offset;
          // Above the top, RIP is the return address: the call itself is
          // one byte before it
          if LFrames.Count = 0 then
            LFrame.LookupAddress := LWalk.AddrPC.Offset
          else
            LFrame.LookupAddress := LWalk.AddrPC.Offset - 1;
          LFrames.Add(LFrame);
        end;
      finally
        GWalkReader := nil;
      end;
    finally
      GDbgLock.Leave();
    end;

    // Each frame's line and function (their own lookups, each locked)
    for LIndex := 0 to LFrames.Count - 1 do
    begin
      LFrame := LFrames[LIndex];
      LFrame.HasLine := LineAt(LFrame.LookupAddress, LFrame.Line);
      FunctionAt(LFrame.LookupAddress, LFrame.FunctionName, LFrame.FunctionStart, LSize);
      LFrames[LIndex] := LFrame;
    end;
    Result := LFrames.ToArray();
  finally
    LFrames.Free();
  end;
end;

initialization
  GDbgLock := TCriticalSection.Create();

finalization
  if GDbgLibrary <> 0 then
    FreeLibrary(GDbgLibrary);
  GDbgLock.Free();

end.
