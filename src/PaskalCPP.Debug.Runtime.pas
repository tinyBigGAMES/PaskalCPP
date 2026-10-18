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
  PaskalCPP.Debug.Runtime - the debugger engine

  One debug session as the front-ends see it (the REPL in-process, DAP over
  stdio): launch and hold at entry, breakpoints per file (pending until the
  image that has their lines loads), continue / step in / over / out, pause,
  the call stack, and the variables of a frame in PaskalCPP names and types
  (the analysed AST of the program: TPCScopes.FramesAt at the stop line, the
  emitter's own spelling to find each PDB symbol). Front-ends call only this
  class. API: research\editor\debugger-api.md (PLAN-EDITOR E3 e3).

  Dependencies: PaskalCPP.Debug.Target, PaskalCPP.Debug.Symbols,
    PaskalCPP.AST, PaskalCPP.Scopes, PaskalCPP.SourceText, PaskalCPP.Lexer,
    PaskalCPP.TokenStream, PaskalCPP.Emitter (DoDeclName / DoNamespaceName),
    StdApp.*
  Notes:
    - Every run-control call needs a stop (DB0016 otherwise); Pause and
      Terminate are the exceptions.
    - A step runs one instruction at a time (the trap flag) on the stopped
      thread. A call is run to its return address by a temporary patch
      whose frame condition (the stack pointer) makes a recursive hit of the
      same address pass silently. A step ends at the first instruction of a
      .pcpp line-table entry of another line, or of the same line in another
      frame (the frame's identity = its CFA: the caller's stack pointer).
      A user breakpoint, an exception, a pause or the exit ends it too; the
      temporary patches go then, whatever ended it.
    - Values are read while the process is stopped; a frame id or a children
      reference is valid until the next resume.
===============================================================================}

unit PaskalCPP.Debug.Runtime;

interface

uses
  WinApi.Windows,
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.AST,
  PaskalCPP.Scopes,
  PaskalCPP.SourceText,
  PaskalCPP.Debug.Target,
  PaskalCPP.Debug.Symbols;

const
  { PC_ERR_DBG_011 }
  PC_ERR_DBG_011 = 'DB0011';   // warning: no code at a breakpoint's line
  { PC_ERR_DBG_012 }
  PC_ERR_DBG_012 = 'DB0012';   // the target is not one this engine debugs (front-ends report it)
  { PC_ERR_DBG_015 }
  PC_ERR_DBG_015 = 'DB0015';   // hint: no sources, the C++ names are shown
  { PC_ERR_DBG_016 }
  PC_ERR_DBG_016 = 'DB0016';   // the program is running: the command needs a stop
  { PC_ERR_DBG_018 }
  PC_ERR_DBG_018 = 'DB0018';   // the program did not reach its entry stop
  { PC_ERR_DBG_019 }
  PC_ERR_DBG_019 = 'DB0019';   // warning: a source file cannot be read (names fall back to C++)

  { PC_DBG_TARGET }
  // The one target this engine debugs (W5: Linux through gdb is a later engine)
  PC_DBG_TARGET = 'x86_64-windows-gnu';
  { PC_DBG_LAUNCH_MS }
  // How long Launch waits for the loader's break (the entry stop)
  PC_DBG_LAUNCH_MS = 30000;
  { PC_DBG_POLL_MS }
  // One wait of the engine's own event loop (NextEvent splits its timeout)
  PC_DBG_POLL_MS = 100;
  { PC_DBG_INSTRUCTION_MAX }
  // The longest x64 instruction (bytes): a call's return address lies in
  // (call address, call address + this]
  PC_DBG_INSTRUCTION_MAX = 15;
  { PC_DBG_POINTER_SIZE }
  PC_DBG_POINTER_SIZE = 8;
  { PC_DBG_WCHAR_SIZE }
  // wchar_t on the debugged target (x86_64-windows-gnu, the only one: W5)
  PC_DBG_WCHAR_SIZE = 2;
  { PC_DBG_TYPEDEF_MAX }
  // The longest typedef chain followed to a type
  PC_DBG_TYPEDEF_MAX = 16;
  { PC_DBG_EVAL_FILENAME }
  // The name an evaluated text is lexed under (it is no file)
  PC_DBG_EVAL_FILENAME = '<evaluate>';

  { PC_DBG_BT_VOID }
  // DbgHelp's BasicType numbers (TI_GET_BASETYPE)
  PC_DBG_BT_VOID = 1;
  { PC_DBG_BT_CHAR }
  PC_DBG_BT_CHAR = 2;
  { PC_DBG_BT_WCHAR }
  PC_DBG_BT_WCHAR = 3;
  { PC_DBG_BT_INT }
  PC_DBG_BT_INT = 6;
  { PC_DBG_BT_UINT }
  PC_DBG_BT_UINT = 7;
  { PC_DBG_BT_FLOAT }
  PC_DBG_BT_FLOAT = 8;
  { PC_DBG_BT_BOOL }
  PC_DBG_BT_BOOL = 10;
  { PC_DBG_BT_LONG }
  PC_DBG_BT_LONG = 13;
  { PC_DBG_BT_ULONG }
  PC_DBG_BT_ULONG = 14;
  { PC_DBG_BT_CHAR16 }
  PC_DBG_BT_CHAR16 = 32;
  { PC_DBG_BT_CHAR32 }
  PC_DBG_BT_CHAR32 = 33;
  { PC_DBG_BT_CHAR8 }
  PC_DBG_BT_CHAR8 = 34;
  { PC_DBG_STRING_MAX }
  // The most characters of a string a value shows
  PC_DBG_STRING_MAX = 4096;
  { PC_DBG_SUMMARY_MAX }
  // The most items a record / array / set summary shows before '...'
  PC_DBG_SUMMARY_MAX = 8;
  { PC_DBG_CHILDREN_MAX }
  // The most elements an array's children list
  PC_DBG_CHILDREN_MAX = 1000;
  { PC_DBG_SET_WORDS_MAX }
  // ::pcpp::Set holds at most 65536 members (pcpp_runtime.h): 1024 words
  PC_DBG_SET_WORDS_MAX = 1024;
  { PC_DBG_SELF_NAME }
  PC_DBG_SELF_NAME = 'self';
  { PC_DBG_THIS_NAME }
  // The PDB's receiver of a method, and of a lambda (the guard body's closure)
  PC_DBG_THIS_NAME = 'this';
  { PC_DBG_CLOSURE_THIS_NAME }
  // A lambda closure's member holding the captured object pointer (clang's
  // name, probed e3); the routine's variables are members of their own names
  PC_DBG_CLOSURE_THIS_NAME = '__this';
  { PC_DBG_DEREF_NAME }
  // The child of a pointer: its target, named as PaskalCPP spells a deref
  PC_DBG_DEREF_NAME = '^';
  { PC_DBG_LIBCXX_SHARED_OWNERS }
  // PLAN-OBJECT O14: libc++'s control block member counting a ref's owners
  // less one (std::__shared_count); below 0 = the object is gone (a weak
  // that expired). Witnessed by Debug.runtime_owners
  PC_DBG_LIBCXX_SHARED_OWNERS = '__shared_owners_';
  { PC_DBG_OWNER_DEPTH_MAX }
  // How deep DoCollectPointers walks an owner's members (unique_ptr's
  // compressed pair, shared_ptr's members): a bound, never reached
  PC_DBG_OWNER_DEPTH_MAX = 4;
  { PC_DBG_LIBCXX_STRING }
  // libc++'s std::string / std::wstring as the PDB names them (debugger-pdb.md)
  PC_DBG_LIBCXX_STRING = 'std::__1::basic_string<char,';
  { PC_DBG_LIBCXX_WSTRING }
  PC_DBG_LIBCXX_WSTRING = 'std::__1::basic_string<wchar_t,';
  { PC_DBG_LIBCXX_VECTOR_BEGIN }
  // libc++ std::vector's members (a dynamic array)
  PC_DBG_LIBCXX_VECTOR_BEGIN = '__begin_';
  { PC_DBG_LIBCXX_VECTOR_END }
  PC_DBG_LIBCXX_VECTOR_END = '__end_';
  { PC_DBG_LIBCXX_LONG_FLAG }
  // libc++ string, little endian: bit 0 of the first byte = the long form
  PC_DBG_LIBCXX_LONG_FLAG = $01;
  { PC_DBG_LIBCXX_SIZE_OFFSET }
  // The long form: capacity word, size word, data pointer
  PC_DBG_LIBCXX_SIZE_OFFSET = 8;
  { PC_DBG_LIBCXX_DATA_OFFSET }
  PC_DBG_LIBCXX_DATA_OFFSET = 16;

  { PC_DBG_RAW_HIDDEN_PREFIXES }
  // A C++ local whose name starts so is the emitter's or the compiler's own
  // (pcpp_exc_1, __range1): never listed as a raw C++ variable
  PC_DBG_RAW_HIDDEN_PREFIXES: array[0..1] of string = (
    'pcpp_',
    '__'
  );

type
  { TPCBreakpointResult }
  // One requested breakpoint line as the session placed it
  TPCBreakpointResult = record
    Id: Integer;              // stable across re-sets of the same file + line
    FileName: string;
    RequestedLine: Integer;
    Verified: Boolean;
    ActualLine: Integer;      // DbgHelp's line (a line without code moves forward)
    MessageText: string;      // why it is not verified ('' when it is)
  end;

  { TPCDebugThread }
  TPCDebugThread = record
    ThreadId: Cardinal;
    IsMain: Boolean;
  end;

  { TPCDebugStackItem }
  TPCDebugStackItem = record
    FrameId: Integer;         // valid until the next resume
    RoutineName: string;      // PaskalCPP name (routine, Type.Method, test, module body); else C++
    FileName: string;         // '' = no line
    Line: Integer;
    Address: UInt64;
    IsPcpp: Boolean;          // False = runtime, C, C++ or system code
  end;

  { TPCDebugScopeKind }
  TPCDebugScopeKind = (
    dskParams,
    dskLocals,
    dskGlobals              // the module variables of the frame's module
  );

  { TPCDebugValue }
  TPCDebugValue = record
    DisplayName: string;      // the PaskalCPP name, or the C++ name raw
    TypeText: string;         // TPCTypeExpr.TypeText, or the PDB's type name
    ValueText: string;
    ChildrenRef: Integer;     // 0 = none; valid until the next resume
    IsReadable: Boolean;      // False = ValueText says why
  end;

  { TPCDebugSourceLine }
  // A line of a .pcpp file (a @breakpoint of the program)
  TPCDebugSourceLine = record
    FileName: string;         // the module's SourceFile
    Line: Integer;
  end;

  { TPCDebugStepKind }
  TPCDebugStepKind = (
    dstNone,
    dstIn,
    dstOver,
    dstOut
  );

  { TPCDebugTempPatch }
  // A patch a step placed: it counts only on the stepping thread, with its
  // stack pointer above Threshold (OrEqual: at or above). StopsStep = a
  // guard part's first statement (e7): a hit there ends the step when the
  // part runs for the step's frame or an outer one (Threshold unused)
  TPCDebugTempPatch = record
    Address: UInt64;
    Threshold: UInt64;
    OrEqual: Boolean;
    StopsStep: Boolean;
  end;

  { TPCDebugBreakpoint }
  // One requested line of a file
  TPCDebugBreakpoint = record
    Id: Integer;
    Line: Integer;
    Verified: Boolean;
    NoCode: Boolean;          // its image is loaded and it has no code
    ActualLine: Integer;
    Addresses: TArray<UInt64>;
  end;

  { TPCDebugBreakpointFile }
  TPCDebugBreakpointFile = record
    FileName: string;
    Items: TArray<TPCDebugBreakpoint>;
  end;

  { TPCDebugBreakpointId }
  // A file + line that once had an id: the same id when it is set again
  TPCDebugBreakpointId = record
    FileName: string;
    Line: Integer;
    Id: Integer;
  end;

  { TPCDebugSlot }
  // Where a value lives and what it is: the PaskalCPP type (nil = raw: the
  // PDB type alone) and the PDB type of the bytes at Address
  TPCDebugSlot = record
    DisplayName: string;
    AstType: TPCTypeExpr;
    ModuleBase: UInt64;
    TypeIndex: Cardinal;      // 0 = no PDB type
    Address: UInt64;
    HasAddress: Boolean;      // False = the value is not readable (ValueText says why)
    Problem: string;          // why HasAddress is False
    IsBasePart: Boolean;      // an object's parent part (its members are inherited)
    TypeName: string;         // the type as named when the AST type is its definition (self: TBox); '' = AstType.TypeText
    // A bitfield: bits BitPosition .. + BitWidth - 1 of the storage unit at
    // Address (TypeIndex's size)
    IsBitfield: Boolean;
    BitPosition: Cardinal;
    BitWidth: Cardinal;
    // PLAN-VENDOR 1e: a const the compiler kept no storage for shows the
    // value the AST holds (SEM's folded value, else the literal as written)
    HasConstValue: Boolean;
    ConstValue: string;
  end;

  { TPCDebugFrameInfo }
  // One frame of the last stack trace
  TPCDebugFrameInfo = record
    ThreadId: Cardinal;
    Frame: TPCDebugFrame;
    Module: TPCModule;        // nil = no sources for it
    Anchor: UInt64;           // byte offset of its line in Module's file
  end;

  { TPCDebugRuntime }
  // The engine of one session: configure, Launch (held at entry), set
  // breakpoints, ConfigurationDone, then NextEvent and the run-control /
  // inspection calls until dekExited
  TPCDebugRuntime = class(TBaseObject)
  private
    FTarget: TPCDebugTarget;
    FSymbols: TPCDebugSymbols;
    FProgram: TPCModule;
    FImagePath: string;           // the image with the program's lines (exe, or the dll)
    FImageLoaded: Boolean;
    FLaunched: Boolean;
    FAtEntry: Boolean;
    FStopThread: Cardinal;
    FOut: TQueue<TPCDebugEvent>;  // events the engine made (a step's stop)

    // Breakpoints
    FBpFiles: TList<TPCDebugBreakpointFile>;
    FBpIds: TList<TPCDebugBreakpointId>;
    FBpNextId: Integer;
    FBpChanges: TList<TPCBreakpointResult>;
    FUserAddresses: TDictionary<UInt64, Integer>;

    // The step in progress
    FStepKind: TPCDebugStepKind;
    FStepThread: Cardinal;
    FStepStartRip: UInt64;
    FStepHasLine: Boolean;
    FStepLine: TPCDebugLine;
    FStepCfa: UInt64;
    FStepPrevRip: UInt64;
    FStepPrevRsp: UInt64;
    FStepAwaitTemp: Boolean;      // running to a temporary patch
    FStepResync: Boolean;         // a hit of the awaited patch restarts the step there
                                  // (StepOut's return; a frame resumed after an unwind)
    FStepUnwound: Boolean;        // an exception unwound the step's frame: a guard's
                                  // except / finally line may be its stop (the handler runs)
    FBreakOnFirstChance: Boolean; // the user's first-chance setting (a step's own watch aside)
    FTemps: TList<TPCDebugTempPatch>;

    // Valid while stopped
    FFrames: TList<TPCDebugFrameInfo>;
    FRefs: TList<TPCDebugSlot>;

    // Names: each module's source text, read once; the module of each line
    // table file name (nil = not the program's), looked up once
    FSources: TObjectDictionary<TPCModule, TPCSourceText>;
    FSourceFailed: TList<TPCModule>;
    FFileModules: TDictionary<string, TPCModule>;
    FGuards: TDictionary<TPCModule, TArray<TPCGuard>>;  // each module's guards, collected once
    // Each C-linkage routine definition's symbol (TPCEmitter.DoSymbolIsC:
    // the bare DeclName, outside the namespace) -> its module, collected once
    FCSymbols: TDictionary<string, TPCModule>;
    FCSymbolsReady: Boolean;

    // Session
    function DoCheckStopped(): Boolean;
    procedure DoClearStop();
    function DoResume(const AKind: TPCResumeKind): Boolean;
    function DoReader(): TPCDebugReadMemory;
    function DoHandleEvent(const AEvent: TPCDebugEvent; out AOut: TPCDebugEvent): Boolean;
    procedure DoOnModule(const AEvent: TPCDebugEvent);

    // Breakpoints
    function DoBreakpointId(const AFile: string; const ALine: Integer): Integer;
    function DoFileIndex(const AFile: string): Integer;
    procedure DoResolve(var ABreakpoint: TPCDebugBreakpoint; const AFile: string);
    procedure DoUnpatch(const ABreakpoint: TPCDebugBreakpoint);
    procedure DoResolvePending();
    function DoResult(const AFile: string; const ABreakpoint: TPCDebugBreakpoint): TPCBreakpointResult;
    function DoIsUserAddress(const AAddress: UInt64): Boolean;

    // Stepping
    function DoStartStep(const AKind: TPCDebugStepKind): Boolean;
    procedure DoEndStep();
    procedure DoArmUnwind();
    function DoCfa(const AContext: TPCDebugContext): UInt64;
    function DoTempIndex(const AAddress: UInt64): Integer;
    procedure DoAddTemp(const AAddress: UInt64; const AThreshold: UInt64; const AOrEqual: Boolean);
    function DoStepEvent(const AEvent: TPCDebugEvent; out AOut: TPCDebugEvent): Boolean;
    function DoTempHit(const AEvent: TPCDebugEvent; out AOut: TPCDebugEvent): Boolean;
    function DoStepAt(const AContext: TPCDebugContext; out AOut: TPCDebugEvent): Boolean;
    function DoEnteredCall(const AContext: TPCDebugContext; out AReturn: UInt64): Boolean;
    function DoStopEvent(const AReason: TPCDebugStopReason; const AThreadId: Cardinal;
      const AAddress: UInt64): TPCDebugEvent;

    // Stepping through guards (e7): the AST says where a guard's parts are
    function DoGuardsOf(const AModule: TPCModule): TArray<TPCGuard>;
    function DoGuardsAt(const ALine: TPCDebugLine): TArray<TPCGuard>;
    function DoIsGuardGlue(const ALine: TPCDebugLine): Boolean;
    function DoIsGuardCaller(const ACaller: TPCDebugLine; const AInner: TPCDebugLine): Boolean;
    function DoIsProgramFrame(const AFrame: TPCDebugFrame; out ALine: TPCDebugLine): Boolean;
    procedure DoAddStopTemp(const AAddress: UInt64);
    procedure DoArmPart(const AFile: string; const AStmts: TList<TPCStmt>; const AHasFunction: Boolean;
      const AStart: UInt64; const ASize: Cardinal);
    procedure DoArmGuardParts();
    function DoCallerCfa(const AContext: TPCDebugContext; out ACfa: UInt64): Boolean;
    function DoGuardCallerIndex(const AFrames: TArray<TPCDebugFrame>; const AInner: Integer): Integer;
    function DoStepOutFrame(const AFrames: TArray<TPCDebugFrame>): Integer;

    // Names
    procedure DoCollectModules(const AModule: TPCModule; const AModules: TList<TPCModule>);
    function DoModuleOfFile(const AFile: string): TPCModule;
    function DoCSymbolModule(const AFunctionName: string): TPCModule;
    procedure DoClearProgramCaches();
    function DoIsModuleCode(const AModule: TPCModule; const AFunctionName: string): Boolean;
    function DoIsProgramLine(const ALine: TPCDebugLine; const AFunctionName: string; out AModule: TPCModule): Boolean;
    function DoIsProgramCode(const AAddress: UInt64; out ALine: TPCDebugLine): Boolean;
    function DoSourceOf(const AModule: TPCModule): TPCSourceText;
    function DoLineAnchor(const AModule: TPCModule; const ALine: Integer; out AAnchor: UInt64): Boolean;
    function DoCodeAnchor(const AModule: TPCModule; const AAnchor: UInt64): UInt64;
    function DoRoutineName(const AInfo: TPCDebugFrameInfo; const AFallback: string): string;
    procedure DoFrameChain(const AInfo: TPCDebugFrameInfo; const AFrames: TList<TPCScopeFrame>);
    function DoFrameValid(const AFrameId: Integer): Boolean;

    // Slots (where a variable lives)
    function DoFindSymbol(const ASymbols: TArray<TPCDebugSymbol>; const ACppName: string;
      out ASymbol: TPCDebugSymbol): Boolean;
    function DoSymbolSlot(const AInfo: TPCDebugFrameInfo; const ASymbol: TPCDebugSymbol;
      const ADisplayName: string; const AAstType: TPCTypeExpr; const AByReference: Boolean): TPCDebugSlot;
    function DoClosureSlot(const AInfo: TPCDebugFrameInfo; const ASymbols: TArray<TPCDebugSymbol>;
      const ACppName: string; const ADisplayName: string; const AAstType: TPCTypeExpr;
      out ASlot: TPCDebugSlot): Boolean;
    function DoLocalSlot(const AFrameId: Integer; const ASymbols: TArray<TPCDebugSymbol>;
      const ACppName: string; const ADisplayName: string; const AAstType: TPCTypeExpr;
      const AByReference: Boolean; out ASlot: TPCDebugSlot): Boolean;
    function DoSelfSlot(const AFrameId: Integer; const ASymbols: TArray<TPCDebugSymbol>;
      const ASelfType: TPCTypeExpr; out ASlot: TPCDebugSlot): Boolean;
    function DoGuardOwnerFrame(const AFrameId: Integer; out AOwnerSymbols: TArray<TPCDebugSymbol>): Integer;
    function DoParamSlots(const AFrameId: Integer): TArray<TPCDebugSlot>;
    function DoLocalSlots(const AFrameId: Integer): TArray<TPCDebugSlot>;
    function DoGlobalSlots(const AFrameId: Integer): TArray<TPCDebugSlot>;
    // PLAN-VENDOR 1e: a const with no storage, as the value the AST holds
    class function DoConstValueSlot(const ADecl: TPCConstDecl; out ASlot: TPCDebugSlot): Boolean; static;
    function DoRawSlots(const AFrameId: Integer; const AParams: Boolean;
      const AKnown: TList<string>): TArray<TPCDebugSlot>;
    function DoIsHiddenName(const ACppName: string): Boolean;
    function DoIsByReference(const AParam: TPCParam): Boolean;

    // Types and memory
    function DoPdbType(const AModuleBase: UInt64; const ATypeIndex: Cardinal; out AType: TPCDebugType): Boolean;
    function DoPdbTypeName(const AModuleBase: UInt64; const ATypeIndex: Cardinal): string;
    function DoFindField(const AModuleBase: UInt64; const ATypeIndex: Cardinal; const ACppName: string;
      out AField: TPCDebugField; out AOffset: UInt64): Boolean;
    function DoBaseField(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
      const ARecord: TPCRecordType; out AField: TPCDebugField): Boolean;
    // PLAN-OBJECT O14: the pointer members of an own / ref / weak's runtime
    // owner (::pcpp::Own / Ref / Weak = std::unique_ptr / shared_ptr /
    // weak_ptr), depth first, at most two: the object's, then the control
    // block's (ref / weak); Offset = from the owner's address
    procedure DoCollectPointers(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
      const AOffset: Cardinal; const ADepth: Integer; const AFound: TList<TPCDebugField>);
    // A data member by name in a UDT or any of its base classes (depth first)
    function DoFindDeepField(const AModuleBase: UInt64; const ATypeIndex: Cardinal; const ACppName: string;
      out AField: TPCDebugField; out AOffset: UInt64): Boolean;
    // The object an own / ref / weak holds: True = it can be shown (AAddress,
    // ATypeIndex = the PDB type of the object); False with AExpired = a weak
    // whose object is gone; False otherwise = nil or unreadable (AReadable)
    function DoOwnerTarget(const ASlot: TPCDebugSlot; const AOwner: TPCOwnerType; out AAddress: UInt64;
      out ATypeIndex: Cardinal; out AExpired: Boolean; out AReadable: Boolean): Boolean;
    function DoRead(const AAddress: UInt64; const ASize: NativeUInt; out ABytes: TBytes): Boolean;
    function DoReadUInt(const AAddress: UInt64; const ASize: Integer; out AValue: UInt64): Boolean;
    function DoChildSlot(const AParent: TPCDebugSlot; const ADisplayName: string; const AAstType: TPCTypeExpr;
      const ATypeIndex: Cardinal; const AAddress: UInt64): TPCDebugSlot;

    // Values
    function DoValue(const ASlot: TPCDebugSlot): TPCDebugValue;
    function DoValueText(const ASlot: TPCDebugSlot; const ASummary: Boolean; out AHasChildren: Boolean): string;
    procedure DoSetBits(var ASlot: TPCDebugSlot; const AField: TPCDebugField);
    function DoBitfieldText(const ASlot: TPCDebugSlot): string;
    function DoAstText(const ASlot: TPCDebugSlot; const AType: TPCTypeExpr; const ASummary: Boolean;
      out AHasChildren: Boolean; out AHandled: Boolean): string;
    function DoRawText(const ASlot: TPCDebugSlot; const ASummary: Boolean; out AHasChildren: Boolean): string;
    function DoBuiltinText(const ASlot: TPCDebugSlot; const AType: TPCBuiltinType): string;
    function DoIntText(const AAddress: UInt64; const ASize: Integer; const ASigned: Boolean): string;
    function DoSignExtend(const AValue: UInt64; const ASize: Integer): Int64;
    function DoFloatText(const AAddress: UInt64; const ASize: Integer): string;
    function DoEscaped(const ACode: Cardinal; const AQuote: Char; const AOneByte: Boolean): string;
    function DoCharPrefix(const ABaseType: Cardinal): string;
    function DoCharText(const ACode: UInt64; const APrefix: string; const AOneByte: Boolean): string;
    function DoQuoted(const AText: string; const APrefix: string; const ATruncated: Boolean): string;
    function DoShortName(const ACppName: string): string;
    function DoStringText(const AAddress: UInt64; const ACharSize: Integer): string;
    function DoChoiceText(const AChoices: TPCChoicesType; const AOrdinal: Int64): string;
    function DoSetText(const ASlot: TPCDebugSlot; const ASet: TPCSetType): string;
    function DoMemberText(const ASlot: TPCDebugSlot): string;
    function DoElementsText(const ASlot: TPCDebugSlot): string;
    function DoChildren(const ASlot: TPCDebugSlot): TArray<TPCDebugSlot>;
    procedure DoRecordChildren(const ASlot: TPCDebugSlot; const AMembers: TList<TPCMemberItem>;
      const AChildren: TList<TPCDebugSlot>);
    procedure DoArrayChildren(const ASlot: TPCDebugSlot; const AArray: TPCArrayType;
      const AChildren: TList<TPCDebugSlot>);
    procedure DoRawChildren(const ASlot: TPCDebugSlot; const AChildren: TList<TPCDebugSlot>);
    function DoArrayLayout(const ASlot: TPCDebugSlot; const AArray: TPCArrayType; out AFirst: UInt64;
      out ACount: Int64; out AElementType: Cardinal; out AElementSize: UInt64; out ALow: Int64): Boolean;
    function DoAddRef(const ASlot: TPCDebugSlot): Integer;

    // Evaluate
    function DoEvaluate(const AFrameId: Integer; const AText: string; out ASlot: TPCDebugSlot;
      out AProblem: string): Boolean;
    function DoNamedSlot(const AFrameId: Integer; const ADisplayName: string; out ASlot: TPCDebugSlot): Boolean;
    function DoMemberSlot(const ASlot: TPCDebugSlot; const AMemberName: string; out AChild: TPCDebugSlot): Boolean;
    function DoDerefSlot(const ASlot: TPCDebugSlot; out AChild: TPCDebugSlot): Boolean;
    function DoIndexSlot(const ASlot: TPCDebugSlot; const AIndex: Int64; out AChild: TPCDebugSlot): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetErrors(const AErrors: TErrors); override;

    // The analysed tree of the program (the build's TPCCompiler holds it and
    // outlives the session); nil = a prebuilt image without sources: C++
    // names and types (DB0015, said once at Launch)
    procedure SetProgram(const AMain: TPCModule);
    // The program's modules: the main one, then each import once (depth
    // first, in import order); empty without SetProgram
    function ProgramModules(): TArray<TPCModule>;
    // Every @breakpoint statement of the program, read from the AST (its
    // module's file, its line), per module in source order. A prologue
    // @breakpoint has no effect (SM0109, ResolvedNoEffect): not listed
    function SourceBreakpoints(): TArray<TPCDebugSourceLine>;
    // ATarget (a zig target, as TPCCompiler.GetTarget) is one this engine
    // debugs (PC_DBG_TARGET); a front-end reports DB0012 for any other
    class function SupportsTarget(const ATarget: string): Boolean; static;
    procedure SetTarget(const AExePath: string; const AArgs: string);
    // DLL mode: the dll debugged (its module tree is the program) and the
    // exe that loads it
    procedure SetHostTarget(const ADllPath: string; const AHostExePath: string; const AArgs: string);
    // Where the program's standard handles go (TPCDebugTarget.SetOutputMode)
    procedure SetOutputMode(const AMode: TPCDebugOutputMode);
    // domTerminal: the terminal's size at launch (TPCDebugTarget.SetTerminalSize)
    procedure SetTerminalSize(const ACols: Integer; const ARows: Integer);
    // domTerminal: keys into the program's terminal / its new size
    // (TPCDebugTarget.WriteInput / ResizeTerminal). False = no terminal
    function WriteInput(const AText: string): Boolean;
    function ResizeTerminal(const ACols: Integer; const ARows: Integer): Boolean;
    // DAP's "all" exception filter; a second chance always stops
    procedure SetBreakOnFirstChance(const AEnabled: Boolean);

    // Starts the process; returns at the entry stop, held (breakpoints go in
    // now). False = reported (DB0001-DB0006, DB0018)
    function Launch(): Boolean;
    // Lets the program run from the entry stop
    function ConfigurationDone(): Boolean;

    // Replaces AFile's breakpoints (DAP semantics); each line resolved to
    // every address of it. A line of an image not loaded yet stays pending
    function SetBreakpoints(const AFile: string; const ALines: TArray<Integer>): TArray<TPCBreakpointResult>;
    // Breakpoints whose state changed since the last call (a pending one
    // verified when its image loaded)
    function TakeBreakpointChanges(): TArray<TPCBreakpointResult>;

    // Run control (a stop is needed: DB0016)
    function ContinueExecution(): Boolean;
    function StepIn(): Boolean;
    function StepOver(): Boolean;
    function StepOut(): Boolean;
    // Breaks into the running program (dsrPause); True when already stopped
    function Pause(): Boolean;
    procedure Terminate();

    // The next event the front-end sees: stopped (breakpoint, step, pause,
    // exception), output, thread, exited; the engine's own (module loads,
    // a step's instructions, temporary patches) are consumed here
    function NextEvent(out AEvent: TPCDebugEvent; const ATimeoutMs: Cardinal): Boolean;
    function IsStopped(): Boolean;
    function IsRunning(): Boolean;
    // The thread the last reported stop happened on
    function StoppedThread(): Cardinal;

    function Threads(): TArray<TPCDebugThread>;
    function StackTrace(const AThreadId: Cardinal): TArray<TPCDebugStackItem>;
    // Only the scopes the frame's stop line can have (no Parameters outside
    // a routine, Locals in the module body only for verbatim C++ locals)
    function Scopes(const AFrameId: Integer): TArray<TPCDebugScopeKind>;
    function Variables(const AFrameId: Integer; const AScope: TPCDebugScopeKind): TArray<TPCDebugValue>;
    function Children(const ARef: Integer): TArray<TPCDebugValue>;
    // A designator (name or self, then '.' / '->' member, '[' integer ']',
    // '^'; BNF postfix expr :487-496 without calls). False = AValue.ValueText
    // says why (not a designator, an unknown name, unreadable memory)
    function Evaluate(const AFrameId: Integer; const AText: string; out AValue: TPCDebugValue): Boolean;
  end;

implementation

uses
  System.Math,
  System.IOUtils,
  StdApp.Utils,
  StdApp.Resources,
  PaskalCPP.Common,
  PaskalCPP.TokenStream,
  PaskalCPP.Lexer,
  PaskalCPP.Emitter;

{ TPCDebugRuntime }

constructor TPCDebugRuntime.Create();
begin
  inherited;

  FTarget := TPCDebugTarget.Create();
  FSymbols := TPCDebugSymbols.Create();
  FOut := TQueue<TPCDebugEvent>.Create();
  FBpFiles := TList<TPCDebugBreakpointFile>.Create();
  FBpIds := TList<TPCDebugBreakpointId>.Create();
  FBpChanges := TList<TPCBreakpointResult>.Create();
  FUserAddresses := TDictionary<UInt64, Integer>.Create();
  FTemps := TList<TPCDebugTempPatch>.Create();
  FFrames := TList<TPCDebugFrameInfo>.Create();
  FRefs := TList<TPCDebugSlot>.Create();
  FSources := TObjectDictionary<TPCModule, TPCSourceText>.Create([doOwnsValues]);
  FSourceFailed := TList<TPCModule>.Create();
  FFileModules := TDictionary<string, TPCModule>.Create();
  FGuards := TDictionary<TPCModule, TArray<TPCGuard>>.Create();
  FCSymbols := TDictionary<string, TPCModule>.Create();
end;

destructor TPCDebugRuntime.Destroy();
begin
  // A session still alive ends with the engine (the target waits for it)
  if FTarget.IsRunning() then
    FTarget.Terminate();
  FCSymbols.Free();
  FGuards.Free();
  FFileModules.Free();
  FSourceFailed.Free();
  FSources.Free();
  FRefs.Free();
  FFrames.Free();
  FTemps.Free();
  FUserAddresses.Free();
  FBpChanges.Free();
  FBpIds.Free();
  FBpFiles.Free();
  FOut.Free();
  FSymbols.Free();
  FTarget.Free();

  inherited;
end;

procedure TPCDebugRuntime.SetErrors(const AErrors: TErrors);
begin
  inherited;
  FTarget.SetErrors(AErrors);
  FSymbols.SetErrors(AErrors);
end;

procedure TPCDebugRuntime.SetProgram(const AMain: TPCModule);
begin
  // The names caches hold the tree's nodes: another tree starts them empty
  if AMain <> FProgram then
    DoClearProgramCaches();
  FProgram := AMain;
end;

procedure TPCDebugRuntime.SetTarget(const AExePath: string; const AArgs: string);
begin
  FImagePath := AExePath;
  FTarget.SetProgram(AExePath, AArgs);
  FTarget.SetHost('', '');
end;

procedure TPCDebugRuntime.SetHostTarget(const ADllPath: string; const AHostExePath: string;
  const AArgs: string);
begin
  // The dll is the image with the program's lines; the host only loads it
  FImagePath := ADllPath;
  FTarget.SetProgram(ADllPath, '');
  FTarget.SetHost(AHostExePath, AArgs);
end;

procedure TPCDebugRuntime.SetOutputMode(const AMode: TPCDebugOutputMode);
begin
  FTarget.SetOutputMode(AMode);
end;

procedure TPCDebugRuntime.SetTerminalSize(const ACols: Integer; const ARows: Integer);
begin
  FTarget.SetTerminalSize(ACols, ARows);
end;

function TPCDebugRuntime.WriteInput(const AText: string): Boolean;
begin
  Result := FTarget.WriteInput(AText);
end;

function TPCDebugRuntime.ResizeTerminal(const ACols: Integer; const ARows: Integer): Boolean;
begin
  Result := FTarget.ResizeTerminal(ACols, ARows);
end;

procedure TPCDebugRuntime.SetBreakOnFirstChance(const AEnabled: Boolean);
begin
  FBreakOnFirstChance := AEnabled;
  FTarget.SetBreakOnFirstChance(AEnabled);
end;

function TPCDebugRuntime.Launch(): Boolean;
var
  LEvent: TPCDebugEvent;
  LStart: UInt64;
begin
  Result := False;
  if FLaunched then
    Exit;
  if FProgram = nil then
    FErrors.Add(esHint, PC_ERR_DBG_015, RSDbgNoSources);
  if not FTarget.Start() then
    Exit;
  FLaunched := True;

  // The process handle is published by Start; every module load holds the
  // process, so the symbol handler sees each one before its code runs
  if not FSymbols.Open(FTarget.ProcessHandle()) then
  begin
    FTarget.Terminate();
    Exit;
  end;

  LStart := TUtils.GetTickCount64();
  while TUtils.GetTickCount64() - LStart < PC_DBG_LAUNCH_MS do
  begin
    if not FTarget.NextEvent(LEvent, PC_DBG_POLL_MS) then
      Continue;
    if LEvent.Kind = dekModuleLoaded then
    begin
      DoOnModule(LEvent);
      Continue;
    end;
    if (LEvent.Kind = dekStopped) and (LEvent.Reason = dsrEntry) then
    begin
      // Held here: breakpoints go in, ConfigurationDone lets it run
      FAtEntry := True;
      FStopThread := LEvent.ThreadId;
      Exit(True);
    end;
    // Output and threads before the entry stop reach the front-end later
    FOut.Enqueue(LEvent);
    if LEvent.Kind = dekExited then
      Break;
    if LEvent.Kind = dekStopped then
    begin
      // Any other stop before the loader's break: the front-end sees it
      FStopThread := LEvent.ThreadId;
      Exit(True);
    end;
  end;

  FErrors.Add(esError, PC_ERR_DBG_018, RSDbgNoEntry, [FImagePath]);
  if FTarget.IsRunning() then
    FTarget.Terminate();
end;

function TPCDebugRuntime.ConfigurationDone(): Boolean;
begin
  Result := False;
  if not DoCheckStopped() then
    Exit;
  FAtEntry := False;
  Result := DoResume(rkContinue);
end;

function TPCDebugRuntime.DoCheckStopped(): Boolean;
begin
  Result := FLaunched and FTarget.IsStopped();
  if not Result then
    FErrors.Add(esWarning, PC_ERR_DBG_016, RSDbgRunning);
end;

procedure TPCDebugRuntime.DoClearStop();
begin
  // Frame ids and children references die with the stop
  FFrames.Clear();
  FRefs.Clear();
end;

function TPCDebugRuntime.DoResume(const AKind: TPCResumeKind): Boolean;
begin
  DoClearStop();
  Result := FTarget.Resume(AKind);
end;

function TPCDebugRuntime.DoReader(): TPCDebugReadMemory;
var
  LTarget: TPCDebugTarget;
begin
  // The stack walk reads through the target: patches read as the program's
  // own bytes (a local copy: the method reference captures no Self field)
  LTarget := FTarget;
  Result :=
    function(const AAddress: UInt64; const ASize: NativeUInt; out ABytes: TBytes): Boolean
    begin
      Result := LTarget.ReadMemory(AAddress, ASize, ABytes);
    end;
end;

procedure TPCDebugRuntime.DoOnModule(const AEvent: TPCDebugEvent);
var
  LRequire: Boolean;
begin
  // Every module goes to the symbol handler (the stack walk unwinds system
  // code through it); the program's own image must have line numbers. The
  // target names it as it names the loads (ImagePath: an 8.3 spelling of
  // FImagePath would never compare equal)
  LRequire := (FTarget.ImagePath() <> '') and (AEvent.ModulePath <> '') and
    TUtils.SamePath(AEvent.ModulePath, FTarget.ImagePath());
  if AEvent.ModulePath <> '' then
    FSymbols.AddModule(AEvent.ModulePath, AEvent.Address, LRequire);
  if LRequire then
    FImageLoaded := True;
  // Breakpoints of a file this module has go in before its code runs
  DoResolvePending();
  FTarget.Resume(rkContinue);
end;

function TPCDebugRuntime.NextEvent(out AEvent: TPCDebugEvent; const ATimeoutMs: Cardinal): Boolean;
var
  LStart: UInt64;
  LEvent: TPCDebugEvent;
  LWait: Cardinal;
  LElapsed: UInt64;
begin
  AEvent := Default(TPCDebugEvent);
  if FOut.Count > 0 then
  begin
    AEvent := FOut.Dequeue();
    if AEvent.Kind = dekStopped then
      FStopThread := AEvent.ThreadId;
    Exit(True);
  end;
  if not FLaunched then
    Exit(False);

  // The engine's own events (module loads, a step's instructions, temporary
  // patches) are consumed here; the timeout is split so a long step still
  // answers in time
  LStart := TUtils.GetTickCount64();
  repeat
    LElapsed := TUtils.GetTickCount64() - LStart;
    if UInt64(ATimeoutMs) > LElapsed then
      LWait := Min(Cardinal(UInt64(ATimeoutMs) - LElapsed), Cardinal(PC_DBG_POLL_MS))
    else
      LWait := 0;
    if FTarget.NextEvent(LEvent, LWait) and DoHandleEvent(LEvent, AEvent) then
    begin
      if AEvent.Kind = dekStopped then
      begin
        FStopThread := AEvent.ThreadId;
        FAtEntry := AEvent.Reason = dsrEntry;
      end;
      Exit(True);
    end;
  until TUtils.GetTickCount64() - LStart >= UInt64(ATimeoutMs);
  Result := False;
end;

function TPCDebugRuntime.DoHandleEvent(const AEvent: TPCDebugEvent; out AOut: TPCDebugEvent): Boolean;
begin
  // True = AOut goes to the front-end
  AOut := AEvent;
  Result := True;
  case AEvent.Kind of
    dekModuleLoaded:
      begin
        DoOnModule(AEvent);
        Result := False;
      end;
    dekStopped:
      if FStepKind <> dstNone then
        Result := DoStepEvent(AEvent, AOut);
    dekExited:
      DoEndStep();
  end;
end;

function TPCDebugRuntime.IsStopped(): Boolean;
begin
  Result := FLaunched and FTarget.IsStopped();
end;

function TPCDebugRuntime.IsRunning(): Boolean;
begin
  Result := FTarget.IsRunning();
end;

function TPCDebugRuntime.StoppedThread(): Cardinal;
begin
  Result := FStopThread;
end;

function TPCDebugRuntime.ContinueExecution(): Boolean;
begin
  Result := False;
  if not DoCheckStopped() then
    Exit;
  DoEndStep();
  FAtEntry := False;
  Result := DoResume(rkContinue);
end;

function TPCDebugRuntime.StepIn(): Boolean;
begin
  Result := DoStartStep(dstIn);
end;

function TPCDebugRuntime.StepOver(): Boolean;
begin
  Result := DoStartStep(dstOver);
end;

function TPCDebugRuntime.StepOut(): Boolean;
begin
  Result := DoStartStep(dstOut);
end;

function TPCDebugRuntime.Pause(): Boolean;
begin
  if not FLaunched then
    Exit(False);
  if FTarget.IsStopped() then
    Exit(True);
  Result := FTarget.Pause();
end;

procedure TPCDebugRuntime.Terminate();
begin
  // The step ends with the process: its patches go with it
  FTemps.Clear();
  FStepKind := dstNone;
  DoClearStop();
  if FTarget.IsRunning() then
    FTarget.Terminate();
end;

function TPCDebugRuntime.Threads(): TArray<TPCDebugThread>;
var
  LId: Cardinal;
  LThread: TPCDebugThread;
begin
  Result := nil;
  if not FLaunched then
    Exit;
  for LId in FTarget.Threads() do
  begin
    LThread.ThreadId := LId;
    LThread.IsMain := LId = FTarget.MainThreadId();
    Result := Result + [LThread];
  end;
end;

{ TPCDebugRuntime: breakpoints }

function TPCDebugRuntime.DoBreakpointId(const AFile: string; const ALine: Integer): Integer;
var
  LIndex: Integer;
  LId: TPCDebugBreakpointId;
begin
  // The same file + line keeps its id across re-sets (DAP reuses it)
  for LIndex := 0 to FBpIds.Count - 1 do
    if (FBpIds[LIndex].Line = ALine) and TUtils.SamePath(FBpIds[LIndex].FileName, AFile) then
      Exit(FBpIds[LIndex].Id);
  Inc(FBpNextId);
  LId.FileName := AFile;
  LId.Line := ALine;
  LId.Id := FBpNextId;
  FBpIds.Add(LId);
  Result := LId.Id;
end;

function TPCDebugRuntime.DoFileIndex(const AFile: string): Integer;
var
  LIndex: Integer;
begin
  for LIndex := 0 to FBpFiles.Count - 1 do
    if TUtils.SamePath(FBpFiles[LIndex].FileName, AFile) then
      Exit(LIndex);
  Result := -1;
end;

function TPCDebugRuntime.DoIsUserAddress(const AAddress: UInt64): Boolean;
begin
  Result := FUserAddresses.ContainsKey(AAddress);
end;

procedure TPCDebugRuntime.DoResolve(var ABreakpoint: TPCDebugBreakpoint; const AFile: string);
var
  LActual: Integer;
  LAddresses: TArray<UInt64>;
  LAddress: UInt64;
  LCount: Integer;
begin
  ABreakpoint.Verified := False;
  ABreakpoint.NoCode := False;
  ABreakpoint.Addresses := nil;
  ABreakpoint.ActualLine := ABreakpoint.Line;
  // Before Launch nothing is loaded: pending
  if not FSymbols.IsOpen() then
    Exit;

  if FSymbols.ResolveLine(AFile, ABreakpoint.Line, LActual, LAddresses) and (Length(LAddresses) > 0) then
  begin
    // Every address of the line (P4): a for line has several
    for LAddress in LAddresses do
      if FTarget.AddPatch(LAddress) then
      begin
        ABreakpoint.Addresses := ABreakpoint.Addresses + [LAddress];
        LCount := 0;
        FUserAddresses.TryGetValue(LAddress, LCount);
        FUserAddresses.AddOrSetValue(LAddress, LCount + 1);
      end;
    ABreakpoint.Verified := Length(ABreakpoint.Addresses) > 0;
    ABreakpoint.ActualLine := LActual;
    Exit;
  end;

  // The image with the program's lines is loaded and has none here
  if FImageLoaded then
  begin
    ABreakpoint.NoCode := True;
    FErrors.Add(esWarning, PC_ERR_DBG_011, RSDbgNoCode, [AFile, ABreakpoint.Line]);
  end;
end;

procedure TPCDebugRuntime.DoUnpatch(const ABreakpoint: TPCDebugBreakpoint);
var
  LAddress: UInt64;
  LCount: Integer;
begin
  for LAddress in ABreakpoint.Addresses do
  begin
    if FTarget.IsRunning() then
      FTarget.RemovePatch(LAddress);
    if FUserAddresses.TryGetValue(LAddress, LCount) then
    begin
      if LCount <= 1 then
        FUserAddresses.Remove(LAddress)
      else
        FUserAddresses[LAddress] := LCount - 1;
    end;
  end;
end;

procedure TPCDebugRuntime.DoResolvePending();
var
  LFileIndex: Integer;
  LItemIndex: Integer;
  LFile: TPCDebugBreakpointFile;
  LChanged: Boolean;
begin
  for LFileIndex := 0 to FBpFiles.Count - 1 do
  begin
    LFile := FBpFiles[LFileIndex];
    LChanged := False;
    for LItemIndex := 0 to High(LFile.Items) do
    begin
      if LFile.Items[LItemIndex].Verified or LFile.Items[LItemIndex].NoCode then
        Continue;
      DoResolve(LFile.Items[LItemIndex], LFile.FileName);
      if LFile.Items[LItemIndex].Verified or LFile.Items[LItemIndex].NoCode then
      begin
        FBpChanges.Add(DoResult(LFile.FileName, LFile.Items[LItemIndex]));
        LChanged := True;
      end;
    end;
    if LChanged then
      FBpFiles[LFileIndex] := LFile;
  end;
end;

function TPCDebugRuntime.DoResult(const AFile: string; const ABreakpoint: TPCDebugBreakpoint): TPCBreakpointResult;
begin
  Result.Id := ABreakpoint.Id;
  Result.FileName := AFile;
  Result.RequestedLine := ABreakpoint.Line;
  Result.Verified := ABreakpoint.Verified;
  Result.ActualLine := ABreakpoint.ActualLine;
  Result.MessageText := '';
  if ABreakpoint.Verified then
    Exit;
  if ABreakpoint.NoCode then
    Result.MessageText := Format(RSDbgNoCode, [AFile, ABreakpoint.Line])
  else
    Result.MessageText := RSDbgBpPending;
end;

function TPCDebugRuntime.SetBreakpoints(const AFile: string;
  const ALines: TArray<Integer>): TArray<TPCBreakpointResult>;
var
  LIndex: Integer;
  LFile: TPCDebugBreakpointFile;
  LItem: TPCDebugBreakpoint;
  LLine: Integer;
  LItems: TArray<TPCDebugBreakpoint>;
begin
  // The file's whole set is replaced (DAP setBreakpoints)
  Result := nil;
  LIndex := DoFileIndex(AFile);
  if LIndex >= 0 then
  begin
    LFile := FBpFiles[LIndex];
    for LItem in LFile.Items do
      DoUnpatch(LItem);
  end
  else
    LFile.FileName := AFile;

  LItems := nil;
  for LLine in ALines do
  begin
    LItem := Default(TPCDebugBreakpoint);
    LItem.Id := DoBreakpointId(AFile, LLine);
    LItem.Line := LLine;
    DoResolve(LItem, AFile);
    LItems := LItems + [LItem];
    Result := Result + [DoResult(AFile, LItem)];
  end;
  LFile.Items := LItems;
  if LIndex >= 0 then
    FBpFiles[LIndex] := LFile
  else
    FBpFiles.Add(LFile);
end;

function TPCDebugRuntime.TakeBreakpointChanges(): TArray<TPCBreakpointResult>;
begin
  Result := FBpChanges.ToArray();
  FBpChanges.Clear();
end;

{ TPCDebugRuntime: stepping }

function TPCDebugRuntime.DoCfa(const AContext: TPCDebugContext): UInt64;
var
  LFrames: TArray<TPCDebugFrame>;
begin
  // A frame's identity: the stack pointer its caller has after the return
  // (frame 1's unwound Rsp). Not Rbp (set in the prologue), not Rsp (moves
  // in the prologue and around calls)
  LFrames := FSymbols.WalkStack(AContext, DoReader());
  if Length(LFrames) > 1 then
    Result := LFrames[1].Context.Regs.Rsp
  else
    Result := AContext.Regs.Rsp;
end;

function TPCDebugRuntime.DoTempIndex(const AAddress: UInt64): Integer;
var
  LIndex: Integer;
begin
  for LIndex := 0 to FTemps.Count - 1 do
    if FTemps[LIndex].Address = AAddress then
      Exit(LIndex);
  Result := -1;
end;

procedure TPCDebugRuntime.DoAddTemp(const AAddress: UInt64; const AThreshold: UInt64; const AOrEqual: Boolean);
var
  LTemp: TPCDebugTempPatch;
begin
  // The target's table is refcounted: a temporary patch on a user
  // breakpoint's address is one more reference, removed at the step's end
  if not FTarget.AddPatch(AAddress) then
    Exit;
  LTemp.Address := AAddress;
  LTemp.Threshold := AThreshold;
  LTemp.OrEqual := AOrEqual;
  LTemp.StopsStep := False;
  FTemps.Add(LTemp);
end;

procedure TPCDebugRuntime.DoEndStep();
var
  LTemp: TPCDebugTempPatch;
begin
  // Whatever ended the step, its temporary patches go (R7)
  if FTarget.IsRunning() then
    for LTemp in FTemps do
      FTarget.RemovePatch(LTemp.Address);
  FTemps.Clear();
  FStepKind := dstNone;
  FStepAwaitTemp := False;
  FStepResync := False;
  FStepUnwound := False;
  // The step's own first-chance watch ends with it
  FTarget.SetFirstChanceThread(0);
end;

procedure TPCDebugRuntime.DoArmUnwind();
var
  LContext: TPCDebugContext;
  LFrames: TArray<TPCDebugFrame>;
  LIndex: Integer;
begin
  // An exception on the stepping thread may unwind the step's frame past
  // every patch the step placed. Where the program goes on after the catch
  // is a frame above the throw: each return address from the step frame's
  // caller up gets a patch with that frame's stack pointer; the first hit
  // restarts the step there (a guard's runtime call returns into the
  // routine, whose except list runs next)
  if not FTarget.GetContext(FStepThread, LContext) then
    Exit;
  LFrames := FSymbols.WalkStack(LContext, DoReader());
  for LIndex := 1 to High(LFrames) do
    if (LFrames[LIndex].Context.Regs.Rsp >= FStepCfa) and (DoTempIndex(LFrames[LIndex].Context.Regs.Rip) < 0) then
      DoAddTemp(LFrames[LIndex].Context.Regs.Rip, LFrames[LIndex].Context.Regs.Rsp, True);
  FStepAwaitTemp := True;
  FStepResync := True;
  FStepUnwound := True;
end;

function TPCDebugRuntime.DoStopEvent(const AReason: TPCDebugStopReason; const AThreadId: Cardinal;
  const AAddress: UInt64): TPCDebugEvent;
begin
  Result := Default(TPCDebugEvent);
  Result.Kind := dekStopped;
  Result.Reason := AReason;
  Result.ThreadId := AThreadId;
  Result.Address := AAddress;
end;

function TPCDebugRuntime.DoStartStep(const AKind: TPCDebugStepKind): Boolean;
var
  LContext: TPCDebugContext;
  LFrames: TArray<TPCDebugFrame>;
  LTarget: Integer;
begin
  Result := False;
  if not DoCheckStopped() then
    Exit;
  DoEndStep();
  if not FTarget.GetContext(FStopThread, LContext) then
    Exit;

  FAtEntry := False;
  FStepKind := AKind;
  FStepThread := FStopThread;
  FStepStartRip := LContext.Regs.Rip;
  FStepHasLine := FSymbols.LineAt(LContext.Regs.Rip, FStepLine);
  FStepCfa := DoCfa(LContext);
  FStepPrevRip := LContext.Regs.Rip;
  FStepPrevRsp := LContext.Regs.Rsp;
  // An exception on this thread may unwind the step's frame: watch it
  FTarget.SetFirstChanceThread(FStepThread);

  if AKind = dstOut then
  begin
    // To the caller: its return address with the caller's stack pointer (the
    // unwind data, not opcode guesses); a recursive return to the same
    // address in a deeper frame has a lower stack pointer and passes. A
    // guard part's lambda is not a routine: out of it is out of the routine
    // that holds the guard (DoStepOutFrame)
    LFrames := FSymbols.WalkStack(LContext, DoReader());
    LTarget := DoStepOutFrame(LFrames);
    if LTarget > High(LFrames) then
    begin
      DoEndStep();
      Exit(DoResume(rkContinue));
    end;
    DoAddTemp(LFrames[LTarget].Context.Regs.Rip, LFrames[LTarget].Context.Regs.Rsp, True);
    FStepAwaitTemp := True;
    FStepResync := True;
    Result := DoResume(rkContinue);
  end
  else
    Result := DoResume(rkStep);
  if not Result then
    DoEndStep();
end;

function TPCDebugRuntime.DoEnteredCall(const AContext: TPCDebugContext; out AReturn: UInt64): Boolean;
var
  LName: string;
  LStart: UInt64;
  LSize: Cardinal;
begin
  // The instruction just run was a call: the stack grew by the return
  // address, which points just past that instruction. A jump inside the
  // function is no call; a recursive call lands on its own function's start
  Result := False;
  AReturn := 0;
  if AContext.Regs.Rsp <> FStepPrevRsp - PC_DBG_POINTER_SIZE then
    Exit;
  if not DoReadUInt(AContext.Regs.Rsp, PC_DBG_POINTER_SIZE, AReturn) then
    Exit;
  if (AReturn <= FStepPrevRip) or (AReturn > FStepPrevRip + PC_DBG_INSTRUCTION_MAX) then
    Exit;
  if FSymbols.FunctionAt(AContext.Regs.Rip, LName, LStart, LSize) then
  begin
    if LStart = AContext.Regs.Rip then
      Exit(True);
    if (FStepPrevRip >= LStart) and (FStepPrevRip < LStart + LSize) then
      Exit(False);
  end;
  Result := True;
end;

function TPCDebugRuntime.DoStepEvent(const AEvent: TPCDebugEvent; out AOut: TPCDebugEvent): Boolean;
var
  LContext: TPCDebugContext;
  LReturn: UInt64;
  LLine: TPCDebugLine;
  LIntoPcpp: Boolean;
begin
  // True = AOut goes to the front-end (the step ended)
  AOut := AEvent;
  if (AEvent.Reason = dsrStep) and (AEvent.ThreadId = FStepThread) and (not FStepAwaitTemp) then
  begin
    if not FTarget.GetContext(FStepThread, LContext) then
    begin
      DoEndStep();
      Exit(True);
    end;
    // (1) a call: StepOver runs it to its return; StepIn goes into .pcpp
    // code and runs anything else (runtime, C, C++, system) to its return
    if DoEnteredCall(LContext, LReturn) then
    begin
      LIntoPcpp := DoIsProgramCode(LContext.Regs.Rip, LLine);
      if (FStepKind = dstOver) or (not LIntoPcpp) then
      begin
        // The runtime may call a guard part of this line's guard (e7)
        if not LIntoPcpp then
          DoArmGuardParts();
        DoAddTemp(LReturn, LContext.Regs.Rsp, False);
        FStepAwaitTemp := True;
        FTarget.Resume(rkContinue);
        Exit(False);
      end;
    end;
    Exit(DoStepAt(LContext, AOut));
  end;

  if AEvent.Reason = dsrBreakpoint then
    if DoTempIndex(AEvent.Address) >= 0 then
      Exit(DoTempHit(AEvent, AOut));

  // A first chance on the stepping thread the user did not ask to see (the
  // step's own watch): the program's handlers take it; the frames it may
  // resume in get patches
  if (AEvent.Reason = dsrException) and AEvent.FirstChance and (AEvent.ThreadId = FStepThread) and
    (not FBreakOnFirstChance) then
  begin
    DoArmUnwind();
    FTarget.Resume(rkContinue);
    Exit(False);
  end;
  // The trap of a single step an exception took the place of, met later
  // while running to a patch: nothing to do
  if (AEvent.Reason = dsrStep) and (AEvent.ThreadId = FStepThread) and FStepAwaitTemp then
  begin
    FTarget.Resume(rkContinue);
    Exit(False);
  end;

  // Anything else ends the step: a user breakpoint, an exception, a pause
  DoEndStep();
  Result := True;
end;

function TPCDebugRuntime.DoTempHit(const AEvent: TPCDebugEvent; out AOut: TPCDebugEvent): Boolean;
var
  LTemp: TPCDebugTempPatch;
  LIsUser: Boolean;
  LContext: TPCDebugContext;
  LMet: Boolean;
  LLine: TPCDebugLine;
  LCfa: UInt64;
begin
  AOut := AEvent;
  LTemp := FTemps[DoTempIndex(AEvent.Address)];
  LIsUser := DoIsUserAddress(AEvent.Address);

  // Another thread at the patch: not the step's; a user breakpoint there is
  // a real hit
  if AEvent.ThreadId <> FStepThread then
  begin
    if LIsUser then
    begin
      DoEndStep();
      Exit(True);
    end;
    FTarget.Resume(rkContinue);
    Exit(False);
  end;

  if not FTarget.GetContext(FStepThread, LContext) then
  begin
    DoEndStep();
    Exit(True);
  end;
  LMet := (LContext.Regs.Rsp > LTemp.Threshold) or (LTemp.OrEqual and (LContext.Regs.Rsp = LTemp.Threshold));

  // A user breakpoint here ends the step, in this frame or a deeper one
  if LIsUser then
  begin
    DoEndStep();
    Exit(True);
  end;
  // A guard part's first statement: the step's stop when the part runs for
  // the step's frame or an outer one; for a deeper frame (recursion) it passes
  if LTemp.StopsStep then
  begin
    if DoCallerCfa(LContext, LCfa) and (LCfa >= FStepCfa) then
    begin
      DoEndStep();
      AOut := DoStopEvent(dsrStep, FStepThread, LContext.Regs.Rip);
      Exit(True);
    end;
    FTarget.Resume(rkContinue);
    Exit(False);
  end;
  // A deeper frame (recursion) passes silently
  if not LMet then
  begin
    FTarget.Resume(rkContinue);
    Exit(False);
  end;

  // Back in the step's frame: the temporary patches go, stepping goes on
  // from here
  for LTemp in FTemps do
    FTarget.RemovePatch(LTemp.Address);
  FTemps.Clear();
  FStepAwaitTemp := False;
  FStepPrevRip := LContext.Regs.Rip;
  FStepPrevRsp := LContext.Regs.Rsp;

  if FStepResync then
  begin
    // In the frame the program goes on in (StepOut's caller, or a frame an
    // unwind resumed): a line start right here is the stop; else StepOver
    // from here to the next line start (never mid-line)
    FStepResync := False;
    FStepKind := dstOver;
    if DoIsProgramCode(LContext.Regs.Rip, LLine) and (LLine.Address = LContext.Regs.Rip) then
    begin
      DoEndStep();
      AOut := DoStopEvent(dsrStep, FStepThread, LContext.Regs.Rip);
      Exit(True);
    end;
    FStepStartRip := LContext.Regs.Rip;
    FStepHasLine := FSymbols.LineAt(LContext.Regs.Rip, FStepLine);
    FStepCfa := DoCfa(LContext);
  end;
  Result := DoStepAt(LContext, AOut);
end;

function TPCDebugRuntime.DoStepAt(const AContext: TPCDebugContext; out AOut: TPCDebugEvent): Boolean;
var
  LRip: UInt64;
  LLine: TPCDebugLine;
  LHasLine: Boolean;
  LNew: Boolean;
  LFrames: TArray<TPCDebugFrame>;
begin
  // The step's rules at the instruction the thread is at (not a call: that
  // was decided before). True = the step ended, AOut is its stop
  AOut := Default(TPCDebugEvent);
  LRip := AContext.Regs.Rip;

  // (2) a user breakpoint the step reached (not the one it started on)
  if (LRip <> FStepStartRip) and DoIsUserAddress(LRip) then
  begin
    DoEndStep();
    AOut := DoStopEvent(dsrBreakpoint, FStepThread, LRip);
    Exit(True);
  end;

  // (3) the first instruction of a .pcpp line entry of another line, or of
  // the same line in another frame (a for line's own entries: go on). Never
  // a function's first instruction: that is its prologue (frame not set up,
  // params unreadable: e5b); stepping goes on to where it ends
  LHasLine := DoIsProgramCode(LRip, LLine);
  if LHasLine and (LLine.Address = LRip) and (FSymbols.PastPrologue(LRip) = LRip) then
  begin
    LNew := (not FStepHasLine) or (not FStepLine.IsPcpp) or (LLine.Line <> FStepLine.Line) or
      (not TUtils.SamePath(LLine.FileName, FStepLine.FileName));
    if not LNew then
      LNew := DoCfa(AContext) <> FStepCfa;
    // A guard's except / finally / end line holds the guard's own glue (a
    // part lambda's closing, the dispatch: emitter A7), no statement of the
    // program: never a step's stop, but right after an unwind (the handler
    // runs: the stop says so)
    if LNew and (not FStepUnwound) and DoIsGuardGlue(LLine) then
      LNew := False;
    if LNew then
    begin
      DoEndStep();
      AOut := DoStopEvent(dsrStep, FStepThread, LRip);
      Exit(True);
    end;
  end;

  // (4) out of .pcpp code without a call (returned into the runtime or the
  // CRT): run to where that code returns, in its caller's frame
  if not LHasLine then
  begin
    LFrames := FSymbols.WalkStack(AContext, DoReader());
    if Length(LFrames) > 1 then
    begin
      // A guard part's lambda returned into the runtime, which may call the
      // guard's next part before it returns (e7)
      DoArmGuardParts();
      DoAddTemp(LFrames[1].Context.Regs.Rip, LFrames[1].Context.Regs.Rsp, True);
      FStepAwaitTemp := True;
      FTarget.Resume(rkContinue);
      Exit(False);
    end;
    // Nowhere to return to: the program runs on (to a breakpoint or its end)
    DoEndStep();
    FTarget.Resume(rkContinue);
    Exit(False);
  end;

  // (5) the next instruction
  FStepPrevRip := LRip;
  FStepPrevRsp := AContext.Regs.Rsp;
  FTarget.Resume(rkStep);
  Result := False;
end;

{ TPCDebugRuntime: guards }

function TPCDebugRuntime.DoGuardsOf(const AModule: TPCModule): TArray<TPCGuard>;
var
  LGuards: TList<TPCGuard>;
  LVisit: TPCNodeVisitor;
  LResult: TArray<TPCGuard>;
begin
  // Every guard of a module, nested ones too, in source order: the tree is
  // walked once per module
  Result := nil;
  if AModule = nil then
    Exit;
  if FGuards.TryGetValue(AModule, LResult) then
    Exit(LResult);
  LGuards := TList<TPCGuard>.Create();
  try
    LVisit :=
      procedure(const ANode: TPCNode)
      begin
        if ANode is TPCGuard then
          LGuards.Add(TPCGuard(ANode));
        ANode.EnumChildren(LVisit);
      end;
    try
      AModule.EnumChildren(LVisit);
    finally
      // The visitor holds itself: release it so its frame is freed
      LVisit := nil;
    end;
    LResult := LGuards.ToArray();
  finally
    LGuards.Free();
  end;
  FGuards.Add(AModule, LResult);
  Result := LResult;
end;

function TPCDebugRuntime.DoGuardsAt(const ALine: TPCDebugLine): TArray<TPCGuard>;
var
  LList: TList<TPCGuard>;
  LGuard: TPCGuard;
begin
  // The guards whose lines hold ALine (outermost first), from the module
  // of ALine's file; none for a file that is not the program's
  Result := nil;
  if not ALine.IsPcpp then
    Exit;
  LList := TList<TPCGuard>.Create();
  try
    for LGuard in DoGuardsOf(DoModuleOfFile(ALine.FileName)) do
      if (UInt64(ALine.Line) >= LGuard.Range.StartLine) and (UInt64(ALine.Line) <= LGuard.Range.EndLine) then
        LList.Add(LGuard);
    Result := LList.ToArray();
  finally
    LList.Free();
  end;
end;

function TPCDebugRuntime.DoIsGuardGlue(const ALine: TPCDebugLine): Boolean;
var
  LGuard: TPCGuard;
  LLine: UInt64;
begin
  // A guard's except, finally or end line (TPCGuard.ExceptRange /
  // FinallyRange / Range, the parser's). Not its keyword line: the guard
  // statement itself (a one-line guard is its statements' line)
  Result := False;
  LLine := UInt64(ALine.Line);
  for LGuard in DoGuardsAt(ALine) do
  begin
    if LLine = LGuard.Range.StartLine then
      Continue;
    if LGuard.HasExcept and (LLine = LGuard.ExceptRange.StartLine) then
      Exit(True);
    if LGuard.HasFinally and (LLine = LGuard.FinallyRange.StartLine) then
      Exit(True);
    if LLine = LGuard.Range.EndLine then
      Exit(True);
  end;
end;

function TPCDebugRuntime.DoIsGuardCaller(const ACaller: TPCDebugLine; const AInner: TPCDebugLine): Boolean;
var
  LGuard: TPCGuard;
  LCaller: UInt64;
  LInner: UInt64;
begin
  // ACaller, a frame that called the runtime (its call's line: the frame's
  // LookupAddress), sits on a keyword line of a guard (guard, except,
  // finally) whose lines hold AInner: the runtime ran one of that guard's
  // parts in a lambda, for the routine ACaller is in
  Result := False;
  if not TUtils.SamePath(ACaller.FileName, AInner.FileName) then
    Exit;
  LCaller := UInt64(ACaller.Line);
  LInner := UInt64(AInner.Line);
  for LGuard in DoGuardsAt(ACaller) do
  begin
    if (LInner < LGuard.Range.StartLine) or (LInner > LGuard.Range.EndLine) then
      Continue;
    if LCaller = LGuard.Range.StartLine then
      Exit(True);
    if LGuard.HasExcept and (LCaller = LGuard.ExceptRange.StartLine) then
      Exit(True);
    if LGuard.HasFinally and (LCaller = LGuard.FinallyRange.StartLine) then
      Exit(True);
  end;
end;

function TPCDebugRuntime.DoIsProgramFrame(const AFrame: TPCDebugFrame; out ALine: TPCDebugLine): Boolean;
begin
  // A walked frame is the program's code by its LookupAddress: the address
  // itself for the top frame, the call instruction (return address - 1) for
  // a caller, whose return address may already be the next statement's
  Result := DoIsProgramCode(AFrame.LookupAddress, ALine);
end;

procedure TPCDebugRuntime.DoAddStopTemp(const AAddress: UInt64);
var
  LTemp: TPCDebugTempPatch;
begin
  // One patch per address (a part armed again by a later runtime call of
  // the same step is armed already)
  if DoTempIndex(AAddress) >= 0 then
    Exit;
  if not FTarget.AddPatch(AAddress) then
    Exit;
  LTemp.Address := AAddress;
  LTemp.Threshold := 0;
  LTemp.OrEqual := False;
  LTemp.StopsStep := True;
  FTemps.Add(LTemp);
end;

procedure TPCDebugRuntime.DoArmPart(const AFile: string; const AStmts: TList<TPCStmt>; const AHasFunction: Boolean;
  const AStart: UInt64; const ASize: Cardinal);
var
  LStmt: TPCStmt;
  LActual: Integer;
  LAddresses: TArray<UInt64>;
  LAddress: UInt64;
begin
  // The part's first statement, every address of its line, but none in the
  // function the step is in (that code is stepped through, not called). A
  // line DbgHelp moves out of the statement is not the statement's
  if (AStmts = nil) or (AStmts.Count = 0) then
    Exit;
  LStmt := AStmts[0];
  if not FSymbols.ResolveLine(AFile, Integer(LStmt.Range.StartLine), LActual, LAddresses) then
    Exit;
  if (UInt64(LActual) < LStmt.Range.StartLine) or (UInt64(LActual) > LStmt.Range.EndLine) then
    Exit;
  for LAddress in LAddresses do
  begin
    if AHasFunction and (LAddress >= AStart) and (LAddress < AStart + ASize) then
      Continue;
    DoAddStopTemp(LAddress);
  end;
end;

procedure TPCDebugRuntime.DoArmGuardParts();
var
  LLine: TPCDebugLine;
  LGuard: TPCGuard;
  LName: string;
  LStart: UInt64;
  LSize: Cardinal;
  LHasFunction: Boolean;
begin
  // The step runs code without a .pcpp line (the runtime) from a line on or
  // inside a guard. A guard's parts may run in lambdas the runtime calls
  // (the emitter's lowering, PROJECT.md "Guard lowering"), which running to
  // the return would pass over: each part of each enclosing guard gets a
  // stop-here patch on its first statement (DoTempHit decides the frame)
  if not DoIsProgramCode(FStepPrevRip, LLine) then
    Exit;
  LHasFunction := FSymbols.FunctionAt(FStepPrevRip, LName, LStart, LSize);
  for LGuard in DoGuardsAt(LLine) do
  begin
    DoArmPart(LLine.FileName, LGuard.GuardStmts, LHasFunction, LStart, LSize);
    if LGuard.HasExcept then
      DoArmPart(LLine.FileName, LGuard.ExceptStmts, LHasFunction, LStart, LSize);
    if LGuard.HasFinally then
      DoArmPart(LLine.FileName, LGuard.FinallyStmts, LHasFunction, LStart, LSize);
  end;
end;

function TPCDebugRuntime.DoCallerCfa(const AContext: TPCDebugContext; out ACfa: UInt64): Boolean;
var
  LFrames: TArray<TPCDebugFrame>;
  LIndex: Integer;
  LLine: TPCDebugLine;
begin
  // The CFA (DoCfa's identity) of the nearest program frame above the top
  // one: the routine (or enclosing part lambda) a guard part's lambda runs
  // for, reached through the runtime's frames
  Result := False;
  ACfa := 0;
  LFrames := FSymbols.WalkStack(AContext, DoReader());
  for LIndex := 1 to High(LFrames) do
    if DoIsProgramFrame(LFrames[LIndex], LLine) then
    begin
      if LIndex < High(LFrames) then
        ACfa := LFrames[LIndex + 1].Context.Regs.Rsp
      else
        ACfa := LFrames[LIndex].Context.Regs.Rsp;
      Exit(True);
    end;
end;

function TPCDebugRuntime.DoGuardCallerIndex(const AFrames: TArray<TPCDebugFrame>; const AInner: Integer): Integer;
var
  LNext: Integer;
  LInnerLine: TPCDebugLine;
  LCallerLine: TPCDebugLine;
begin
  // AFrames[AInner] is a guard part's lambda when the runtime called it
  // (frames without .pcpp code right above it) from a keyword line of a
  // guard holding its line: that caller is the routine (or the enclosing
  // part) the part runs for, its index the result. -1 = not a part: a
  // program frame called directly (recursion from a part) is a real caller
  Result := -1;
  if (AInner < 0) or (AInner > High(AFrames)) then
    Exit;
  LNext := AInner + 1;
  while (LNext <= High(AFrames)) and (not DoIsProgramFrame(AFrames[LNext], LCallerLine)) do
    Inc(LNext);
  if (LNext > High(AFrames)) or (LNext = AInner + 1) then
    Exit;
  if not DoIsProgramFrame(AFrames[AInner], LInnerLine) then
    Exit;
  if DoIsGuardCaller(LCallerLine, LInnerLine) then
    Result := LNext;
end;

function TPCDebugRuntime.DoStepOutFrame(const AFrames: TArray<TPCDebugFrame>): Integer;
var
  LInner: Integer;
  LCaller: Integer;
begin
  // The frame StepOut returns into: the caller of frame 0's routine. A
  // guard part's lambda is still its routine: the walk goes on from the
  // frame that holds the guard (nested guards: each one)
  LInner := 0;
  LCaller := DoGuardCallerIndex(AFrames, LInner);
  while LCaller >= 0 do
  begin
    LInner := LCaller;
    LCaller := DoGuardCallerIndex(AFrames, LInner);
  end;
  Result := LInner + 1;
end;

{ TPCDebugRuntime: names }

procedure TPCDebugRuntime.DoCollectModules(const AModule: TPCModule; const AModules: TList<TPCModule>);
var
  LImport: TPCImport;
begin
  // The one walk over the program's modules: preorder, each module once
  // (an import reached twice, or a cycle, is not walked again)
  if (AModule = nil) or AModules.Contains(AModule) then
    Exit;
  AModules.Add(AModule);
  for LImport in AModule.Imports do
    DoCollectModules(LImport.ImportedModule, AModules);
end;

function TPCDebugRuntime.ProgramModules(): TArray<TPCModule>;
var
  LModules: TList<TPCModule>;
begin
  Result := nil;
  if FProgram = nil then
    Exit;
  LModules := TList<TPCModule>.Create();
  try
    DoCollectModules(FProgram, LModules);
    Result := LModules.ToArray();
  finally
    LModules.Free();
  end;
end;

function TPCDebugRuntime.SourceBreakpoints(): TArray<TPCDebugSourceLine>;
var
  LLines: TList<TPCDebugSourceLine>;
  LModule: TPCModule;
  LFile: string;
  LVisit: TPCNodeVisitor;
begin
  // Every body @breakpoint is a TPCDirective in the tree (the parser's
  // node, its Range the line); a prologue one SEM marked ResolvedNoEffect
  LLines := TList<TPCDebugSourceLine>.Create();
  try
    LVisit :=
      procedure(const ANode: TPCNode)
      var
        LLine: TPCDebugSourceLine;
      begin
        if (ANode is TPCDirective) and (TPCDirective(ANode).DirectiveKind = bdBreakpoint) and
          (not TPCDirective(ANode).ResolvedNoEffect) then
        begin
          LLine.FileName := LFile;
          LLine.Line := Integer(ANode.Range.StartLine);
          LLines.Add(LLine);
        end;
        ANode.EnumChildren(LVisit);
      end;
    try
      for LModule in ProgramModules() do
      begin
        LFile := LModule.SourceFile;
        LModule.EnumChildren(LVisit);
      end;
    finally
      // The visitor holds itself: release it so its frame is freed
      LVisit := nil;
    end;
    Result := LLines.ToArray();
  finally
    LLines.Free();
  end;
end;

class function TPCDebugRuntime.SupportsTarget(const ATarget: string): Boolean;
begin
  Result := ATarget.Trim() = PC_DBG_TARGET;
end;

function TPCDebugRuntime.DoModuleOfFile(const AFile: string): TPCModule;
var
  LModule: TPCModule;
begin
  // The program's module (main or imported) whose source is AFile
  Result := nil;
  if FProgram = nil then
    Exit;
  if FFileModules.TryGetValue(AFile, Result) then
    Exit;
  for LModule in ProgramModules() do
    if TUtils.SamePath(LModule.SourceFile, AFile) then
    begin
      Result := LModule;
      Break;
    end;
  FFileModules.Add(AFile, Result);
end;

function TPCDebugRuntime.DoCSymbolModule(const AFunctionName: string): TPCModule;
var
  LModule: TPCModule;
  LStmt: TPCStmt;
begin
  // The module that defines a C-linkage routine of that symbol (nil =
  // none). Collected once from the tree, by the emitter's linkage rule
  if not FCSymbolsReady then
  begin
    FCSymbolsReady := True;
    if FProgram <> nil then
      for LModule in ProgramModules() do
        for LStmt in LModule.Decls do
          if (LStmt is TPCRoutine) and TPCEmitter.DoSymbolIsC(TPCRoutine(LStmt)) then
            FCSymbols.AddOrSetValue(TPCRoutine(LStmt).DeclName, LModule);
  end;
  if not FCSymbols.TryGetValue(AFunctionName, Result) then
    Result := nil;
end;

procedure TPCDebugRuntime.DoClearProgramCaches();
begin
  // Everything collected from a tree, keyed by or holding its nodes
  FSources.Clear();
  FSourceFailed.Clear();
  FFileModules.Clear();
  FGuards.Clear();
  FCSymbols.Clear();
  FCSymbolsReady := False;
end;

function TPCDebugRuntime.DoIsModuleCode(const AModule: TPCModule; const AFunctionName: string): Boolean;
begin
  // Every PaskalCPP item of a module lives in its namespace (the emitter's
  // own rule), except a C-linkage routine definition: its symbol is its bare
  // name. The trailer (main, the entry lambda, dll / lib hooks) sits on the
  // module's last line outside both: generated glue, not the program's
  Result := AFunctionName.StartsWith(TPCEmitter.DoNamespaceName(AModule) + '::') or
    (DoCSymbolModule(AFunctionName) = AModule);
end;

function TPCDebugRuntime.DoIsProgramLine(const ALine: TPCDebugLine; const AFunctionName: string;
  out AModule: TPCModule): Boolean;
begin
  // The one program-code rule (stepping, stops and the stack read it).
  // Without a program tree the .pcpp line alone decides (AModule nil).
  // With one, the line's file must be one of the tree's modules and its
  // function that module's code: a .pcpp line of any other image (a DLL
  // mode host, a lib built without its tree) is not the program's
  AModule := nil;
  Result := ALine.IsPcpp;
  if (not Result) or (FProgram = nil) then
    Exit;
  AModule := DoModuleOfFile(ALine.FileName);
  Result := (AModule <> nil) and DoIsModuleCode(AModule, AFunctionName);
  if not Result then
    AModule := nil;
end;

function TPCDebugRuntime.DoIsProgramCode(const AAddress: UInt64; out ALine: TPCDebugLine): Boolean;
var
  LModule: TPCModule;
  LName: string;
  LStart: UInt64;
  LSize: Cardinal;
begin
  // A .pcpp line of the program's own code (DoIsProgramLine)
  Result := FSymbols.LineAt(AAddress, ALine) and ALine.IsPcpp;
  if (not Result) or (FProgram = nil) then
    Exit;
  Result := FSymbols.FunctionAt(AAddress, LName, LStart, LSize) and DoIsProgramLine(ALine, LName, LModule);
end;

function TPCDebugRuntime.DoSourceOf(const AModule: TPCModule): TPCSourceText;
var
  LBytes: TBytes;
begin
  // The module's source bytes, read once (its line table turns a stop line
  // into the byte the scope rule needs)
  if FSources.TryGetValue(AModule, Result) then
    Exit;
  Result := nil;
  if FSourceFailed.Contains(AModule) then
    Exit;
  try
    LBytes := TFile.ReadAllBytes(AModule.SourceFile);
  except
    on E: Exception do
    begin
      FSourceFailed.Add(AModule);
      FErrors.Add(esWarning, PC_ERR_DBG_019, RSDbgSourceUnreadable, [AModule.SourceFile, E.Message]);
      Exit;
    end;
  end;
  Result := TPCSourceText.Create();
  Result.Init(LBytes, AModule.SourceFile);
  FSources.Add(AModule, Result);
end;

function TPCDebugRuntime.DoLineAnchor(const AModule: TPCModule; const ALine: Integer; out AAnchor: UInt64): Boolean;
var
  LSource: TPCSourceText;
  LLow: Int64;
  LHigh: Int64;
  LMid: Int64;
begin
  // The first token's byte of ALine: LineOf is monotonic over byte offsets,
  // so a binary search finds the line's first byte; its indentation skipped
  Result := False;
  AAnchor := 0;
  LSource := DoSourceOf(AModule);
  if (LSource = nil) or (ALine < 1) or (ALine > LSource.LineCount()) then
    Exit;
  LLow := 0;
  LHigh := LSource.ByteCount();
  while LLow < LHigh do
  begin
    LMid := LLow + (LHigh - LLow) div 2;
    if LSource.LineOf(LMid) < ALine then
      LLow := LMid + 1
    else
      LHigh := LMid;
  end;
  while (LLow < LSource.ByteCount()) and ((LSource.ByteAt(LLow) = Ord(' ')) or (LSource.ByteAt(LLow) = 9)) do
    Inc(LLow);
  AAnchor := UInt64(LLow);
  Result := True;
end;

function TPCDebugRuntime.DoCodeAnchor(const AModule: TPCModule; const AAnchor: UInt64): UInt64;
var
  LFrames: TList<TPCScopeFrame>;
  LFound: TList<TPCNode>;
  LNode: TPCNode;
  LRoutine: TPCRoutine;
  LIndex: Integer;
begin
  // A routine's header line is its prologue, and its var section's lines
  // initialize its locals: that code runs in the routine, but the scope rule
  // resolves a header in the enclosing frames and a local only after its
  // own declaration (SEM's order). The names of a stop there are the
  // routine's, all of them: its body's start
  Result := AAnchor;
  LFrames := TList<TPCScopeFrame>.Create();
  LFound := TList<TPCNode>.Create();
  try
    TPCScopes.FramesAt(AModule, AAnchor, LFrames);
    if LFrames.Count = 0 then
      Exit;
    // On a routine's header (first: a local routine's header lies in its
    // outer routine's declarations): the routine is declared in the
    // innermost frame
    TPCScopes.CollectAll(LFrames[LFrames.Count - 1], LFound);
    for LNode in LFound do
    begin
      if not (LNode is TPCRoutine) then
        Continue;
      LRoutine := TPCRoutine(LNode);
      if (LRoutine.Body <> nil) and (LRoutine.Range.StartByteOffset <= AAnchor) and
        (AAnchor < LRoutine.Body.Range.StartByteOffset) then
        Exit(LRoutine.Body.Range.StartByteOffset);
    end;
    // Inside a routine's declarations: the innermost routine frame is its
    // own (only that one: a local routine sits in its outer routine's
    // declarations, so a stop in the local routine lies before the outer
    // body too)
    for LIndex := LFrames.Count - 1 downto 0 do
      if (LFrames[LIndex].FrameKind = fkRoutine) and (LFrames[LIndex].Owner is TPCRoutine) then
      begin
        LRoutine := TPCRoutine(LFrames[LIndex].Owner);
        if (LRoutine.Body <> nil) and (AAnchor < LRoutine.Body.Range.StartByteOffset) then
          Exit(LRoutine.Body.Range.StartByteOffset);
        Break;
      end;
  finally
    LFound.Free();
    LFrames.Free();
  end;
end;

procedure TPCDebugRuntime.DoFrameChain(const AInfo: TPCDebugFrameInfo; const AFrames: TList<TPCScopeFrame>);
begin
  // The scope frames at the stop line: the rule LSP completion reads too
  AFrames.Clear();
  if AInfo.Module <> nil then
    TPCScopes.FramesAt(AInfo.Module, AInfo.Anchor, AFrames);
end;

function TPCDebugRuntime.DoRoutineName(const AInfo: TPCDebugFrameInfo; const AFallback: string): string;
var
  LFrames: TList<TPCScopeFrame>;
  LIndex: Integer;
  LFrame: TPCScopeFrame;
  LRoutine: TPCRoutine;
begin
  // The innermost routine / method / test whose range holds the line; the
  // module body otherwise; the C++ name for code without sources
  Result := AFallback;
  if AInfo.Module = nil then
    Exit;
  LFrames := TList<TPCScopeFrame>.Create();
  try
    DoFrameChain(AInfo, LFrames);
    for LIndex := LFrames.Count - 1 downto 0 do
    begin
      LFrame := LFrames[LIndex];
      if LFrame.FrameKind = fkRoutine then
      begin
        LRoutine := TPCRoutine(LFrame.Owner);
        // A method: its object's members frame comes right before it
        if (LIndex > 0) and (LFrames[LIndex - 1].FrameKind = fkMembers) and
          (LFrames[LIndex - 1].TypeDecl <> nil) then
          Exit(LFrames[LIndex - 1].TypeDecl.DeclName + '.' + LRoutine.DeclName);
        Exit(LRoutine.DeclName);
      end;
      if LFrame.FrameKind = fkTest then
        Exit('test ' + TPCTest(LFrame.Owner).TestName.ExprText());
    end;
    Result := AInfo.Module.ModuleName;
  finally
    LFrames.Free();
  end;
end;

function TPCDebugRuntime.DoFrameValid(const AFrameId: Integer): Boolean;
begin
  Result := (AFrameId >= 1) and (AFrameId <= FFrames.Count);
end;

function TPCDebugRuntime.StackTrace(const AThreadId: Cardinal): TArray<TPCDebugStackItem>;
var
  LContext: TPCDebugContext;
  LFrame: TPCDebugFrame;
  LInfo: TPCDebugFrameInfo;
  LItem: TPCDebugStackItem;
begin
  // Every frame, .pcpp or not (the front-ends dim or hide the others)
  Result := nil;
  if not DoCheckStopped() then
    Exit;
  if not FTarget.GetContext(AThreadId, LContext) then
    Exit;
  for LFrame in FSymbols.WalkStack(LContext, DoReader()) do
  begin
    LInfo := Default(TPCDebugFrameInfo);
    LInfo.ThreadId := AThreadId;
    LInfo.Frame := LFrame;
    LItem := Default(TPCDebugStackItem);
    // The program-code rule once (glue, a DLL mode host: not the program's)
    LItem.IsPcpp := LFrame.HasLine and DoIsProgramLine(LFrame.Line, LFrame.FunctionName, LInfo.Module);
    if LItem.IsPcpp then
    begin
      if (LInfo.Module <> nil) and (not DoLineAnchor(LInfo.Module, LFrame.Line.Line, LInfo.Anchor)) then
        LInfo.Module := nil;
      if LInfo.Module <> nil then
        LInfo.Anchor := DoCodeAnchor(LInfo.Module, LInfo.Anchor);
    end;
    FFrames.Add(LInfo);

    LItem.FrameId := FFrames.Count;
    LItem.RoutineName := DoRoutineName(LInfo, LFrame.FunctionName);
    LItem.Address := LFrame.Context.Regs.Rip;
    if LFrame.HasLine then
    begin
      LItem.FileName := LFrame.Line.FileName;
      LItem.Line := LFrame.Line.Line;
    end;
    Result := Result + [LItem];
  end;
end;

function TPCDebugRuntime.Scopes(const AFrameId: Integer): TArray<TPCDebugScopeKind>;
var
  LInfo: TPCDebugFrameInfo;
  LFrames: TList<TPCScopeFrame>;
  LFrame: TPCScopeFrame;
  LInRoutine: Boolean;
  LInTest: Boolean;
begin
  Result := nil;
  if not DoFrameValid(AFrameId) then
    Exit;
  LInfo := FFrames[AFrameId - 1];
  // A frame without sources has its C++ locals only
  if LInfo.Module = nil then
  begin
    Result := [dskLocals];
    Exit;
  end;

  // The scopes the stop line can have, from the AST's frame chain there:
  // parameters inside a routine (a method too), locals inside a routine or
  // a test. The module body declares no locals: only verbatim C++ can,
  // so there the scope is listed when DoLocalSlots finds any
  LInRoutine := False;
  LInTest := False;
  LFrames := TList<TPCScopeFrame>.Create();
  try
    DoFrameChain(LInfo, LFrames);
    for LFrame in LFrames do
    begin
      if LFrame.FrameKind = fkRoutine then
        LInRoutine := True
      else if LFrame.FrameKind = fkTest then
        LInTest := True;
    end;
  finally
    LFrames.Free();
  end;
  if LInRoutine then
    Result := Result + [dskParams];
  if LInRoutine or LInTest or (Length(DoLocalSlots(AFrameId)) > 0) then
    Result := Result + [dskLocals];
  Result := Result + [dskGlobals];
end;

function TPCDebugRuntime.Variables(const AFrameId: Integer;
  const AScope: TPCDebugScopeKind): TArray<TPCDebugValue>;
var
  LSlots: TArray<TPCDebugSlot>;
  LSlot: TPCDebugSlot;
begin
  Result := nil;
  if not DoFrameValid(AFrameId) then
    Exit;
  case AScope of
    dskParams:
      LSlots := DoParamSlots(AFrameId);
    dskLocals:
      LSlots := DoLocalSlots(AFrameId);
    dskGlobals:
      LSlots := DoGlobalSlots(AFrameId);
  end;
  for LSlot in LSlots do
    Result := Result + [DoValue(LSlot)];
end;

{ TPCDebugRuntime: slots }

function TPCDebugRuntime.DoFindSymbol(const ASymbols: TArray<TPCDebugSymbol>; const ACppName: string;
  out ASymbol: TPCDebugSymbol): Boolean;
var
  LSymbol: TPCDebugSymbol;
begin
  for LSymbol in ASymbols do
    if LSymbol.CppName = ACppName then
    begin
      ASymbol := LSymbol;
      Exit(True);
    end;
  ASymbol := Default(TPCDebugSymbol);
  Result := False;
end;

function TPCDebugRuntime.DoIsHiddenName(const ACppName: string): Boolean;
var
  LPrefix: string;
begin
  for LPrefix in PC_DBG_RAW_HIDDEN_PREFIXES do
    if ACppName.StartsWith(LPrefix) then
      Exit(True);
  Result := False;
end;

function TPCDebugRuntime.DoIsByReference(const AParam: TPCParam): Boolean;
begin
  // The emitter's passing (debugger-names.md): var = T&, const of a
  // non-scalar = T const&; the PDB symbol of a reference holds the address
  Result := (AParam.ParamMode = pmVar) or
    ((AParam.ParamMode = pmConst) and (AParam.TypeExpr <> nil) and (not AParam.TypeExpr.IsScalarOrPointer()));
end;

function TPCDebugRuntime.DoSymbolSlot(const AInfo: TPCDebugFrameInfo; const ASymbol: TPCDebugSymbol;
  const ADisplayName: string; const AAstType: TPCTypeExpr; const AByReference: Boolean): TPCDebugSlot;
var
  LAddress: UInt64;
  LTarget: UInt64;
  LType: TPCDebugType;
begin
  Result := Default(TPCDebugSlot);
  Result.DisplayName := ADisplayName;
  Result.AstType := AAstType;
  Result.ModuleBase := ASymbol.ModuleBase;
  Result.TypeIndex := ASymbol.TypeIndex;
  // A value held in a register (not frame-relative) has no address to read
  if not ASymbol.ValueAddress(AInfo.Frame, LAddress) then
  begin
    Result.Problem := RSDbgValueUnreadable;
    Exit;
  end;
  if AByReference then
  begin
    // The symbol holds the address of the value; its PDB type is the
    // reference / pointer, the value's type is its target
    if not DoReadUInt(LAddress, PC_DBG_POINTER_SIZE, LTarget) then
    begin
      Result.Problem := RSDbgValueUnreadable;
      Exit;
    end;
    LAddress := LTarget;
    if DoPdbType(ASymbol.ModuleBase, ASymbol.TypeIndex, LType) and (LType.Tag = dttPointer) then
      Result.TypeIndex := LType.ElementType;
  end;
  Result.Address := LAddress;
  Result.HasAddress := True;
end;

function TPCDebugRuntime.DoClosureSlot(const AInfo: TPCDebugFrameInfo; const ASymbols: TArray<TPCDebugSymbol>;
  const ACppName: string; const ADisplayName: string; const AAstType: TPCTypeExpr;
  out ASlot: TPCDebugSlot): Boolean;
var
  LThis: TPCDebugSymbol;
  LClosure: TPCDebugSlot;
  LField: TPCDebugField;
  LOffset: UInt64;
  LTarget: UInt64;
  LType: TPCDebugType;
begin
  // A guard body is a [&] lambda (the emitter's guard lowering): in its
  // frame the routine's variables are its closure's members, each a
  // reference to the variable. Only a lambda's call operator has one
  Result := False;
  ASlot := Default(TPCDebugSlot);
  if not AInfo.Frame.FunctionName.EndsWith('operator()') then
    Exit;
  if not DoFindSymbol(ASymbols, PC_DBG_THIS_NAME, LThis) then
    Exit;
  LClosure := DoSymbolSlot(AInfo, LThis, PC_DBG_THIS_NAME, nil, True);
  if not LClosure.HasAddress then
    Exit;
  if not DoFindField(LClosure.ModuleBase, LClosure.TypeIndex, ACppName, LField, LOffset) then
    Exit;
  if not DoReadUInt(LClosure.Address + LOffset, PC_DBG_POINTER_SIZE, LTarget) then
    Exit;
  ASlot.DisplayName := ADisplayName;
  ASlot.AstType := AAstType;
  ASlot.ModuleBase := LClosure.ModuleBase;
  ASlot.TypeIndex := LField.TypeIndex;
  if DoPdbType(LClosure.ModuleBase, LField.TypeIndex, LType) and (LType.Tag = dttPointer) then
    ASlot.TypeIndex := LType.ElementType;
  ASlot.Address := LTarget;
  ASlot.HasAddress := True;
  Result := True;
end;

function TPCDebugRuntime.DoGuardOwnerFrame(const AFrameId: Integer; out AOwnerSymbols: TArray<TPCDebugSymbol>): Integer;
var
  LFrames: TArray<TPCDebugFrame>;
  LIndex: Integer;
  LOwner: Integer;
begin
  // The frame id of the routine (or enclosing part) a guard part's lambda
  // frame runs for (DoGuardCallerIndex over the last stack trace), with its
  // symbols; 0 = AFrameId is no guard part
  Result := 0;
  AOwnerSymbols := nil;
  SetLength(LFrames, FFrames.Count);
  for LIndex := 0 to FFrames.Count - 1 do
    LFrames[LIndex] := FFrames[LIndex].Frame;
  LOwner := DoGuardCallerIndex(LFrames, AFrameId - 1);
  if LOwner < 0 then
    Exit;
  if not FSymbols.FrameSymbols(FFrames[LOwner].Frame, AOwnerSymbols) then
    Exit;
  Result := LOwner + 1;
end;

function TPCDebugRuntime.DoLocalSlot(const AFrameId: Integer; const ASymbols: TArray<TPCDebugSymbol>;
  const ACppName: string; const ADisplayName: string; const AAstType: TPCTypeExpr;
  const AByReference: Boolean; out ASlot: TPCDebugSlot): Boolean;
var
  LInfo: TPCDebugFrameInfo;
  LSymbol: TPCDebugSymbol;
  LOwner: Integer;
  LOwnerSymbols: TArray<TPCDebugSymbol>;
begin
  // The frame's own symbol, else its lambda closure's member, else (a guard
  // part's lambda captures only the names its part uses: [&]) the routine's
  // own frame, the one the part runs for (e7 G4)
  LInfo := FFrames[AFrameId - 1];
  if DoFindSymbol(ASymbols, ACppName, LSymbol) then
  begin
    ASlot := DoSymbolSlot(LInfo, LSymbol, ADisplayName, AAstType, AByReference);
    Exit(True);
  end;
  if DoClosureSlot(LInfo, ASymbols, ACppName, ADisplayName, AAstType, ASlot) then
    Exit(True);
  LOwner := DoGuardOwnerFrame(AFrameId, LOwnerSymbols);
  if LOwner = 0 then
    Exit(False);
  Result := DoLocalSlot(LOwner, LOwnerSymbols, ACppName, ADisplayName, AAstType, AByReference, ASlot);
end;

function TPCDebugRuntime.DoSelfSlot(const AFrameId: Integer; const ASymbols: TArray<TPCDebugSymbol>;
  const ASelfType: TPCTypeExpr; out ASlot: TPCDebugSlot): Boolean;
var
  LInfo: TPCDebugFrameInfo;
  LOwner: Integer;
  LOwnerSymbols: TArray<TPCDebugSymbol>;
begin
  // A method's self: the object the PDB's this points at. In a guard part's
  // lambda this is the closure: its captured object pointer is the member
  // __this (probed, e3); a part that does not use self captures none, then
  // the method's own frame has it (e7 G4)
  ASlot := Default(TPCDebugSlot);
  LInfo := FFrames[AFrameId - 1];
  if not LInfo.Frame.FunctionName.EndsWith('operator()') then
    Exit(DoLocalSlot(AFrameId, ASymbols, PC_DBG_THIS_NAME, PC_DBG_SELF_NAME, ASelfType, True, ASlot));
  if DoClosureSlot(LInfo, ASymbols, PC_DBG_CLOSURE_THIS_NAME, PC_DBG_SELF_NAME, ASelfType, ASlot) then
    Exit(True);
  LOwner := DoGuardOwnerFrame(AFrameId, LOwnerSymbols);
  if LOwner = 0 then
    Exit(False);
  Result := DoSelfSlot(LOwner, LOwnerSymbols, ASelfType, ASlot);
end;

function TPCDebugRuntime.DoParamSlots(const AFrameId: Integer): TArray<TPCDebugSlot>;
var
  LInfo: TPCDebugFrameInfo;
  LSymbols: TArray<TPCDebugSymbol>;
  LFrames: TList<TPCScopeFrame>;
  LIndex: Integer;
  LRoutineIndex: Integer;
  LRoutine: TPCRoutine;
  LTypeDecl: TPCTypeDecl;
  LSelfType: TPCTypeExpr;
  LParam: TPCParam;
  LSlot: TPCDebugSlot;
begin
  Result := nil;
  LInfo := FFrames[AFrameId - 1];
  if not FSymbols.FrameSymbols(LInfo.Frame, LSymbols) then
    Exit;
  if LInfo.Module = nil then
    Exit(DoRawSlots(AFrameId, True, nil));

  LFrames := TList<TPCScopeFrame>.Create();
  try
    DoFrameChain(LInfo, LFrames);
    LRoutineIndex := -1;
    for LIndex := LFrames.Count - 1 downto 0 do
      if LFrames[LIndex].FrameKind = fkRoutine then
      begin
        LRoutineIndex := LIndex;
        Break;
      end;
    // A test or the module body has no parameters
    if LRoutineIndex < 0 then
      Exit;
    LRoutine := TPCRoutine(LFrames[LRoutineIndex].Owner);

    // A method's receiver: self, the object the PDB's this points at
    if (LRoutineIndex > 0) and (LFrames[LRoutineIndex - 1].FrameKind = fkMembers) and
      (LFrames[LRoutineIndex - 1].TypeDecl <> nil) then
    begin
      LTypeDecl := LFrames[LRoutineIndex - 1].TypeDecl;
      LSelfType := LTypeDecl.TypeDef;
      if not DoSelfSlot(AFrameId, LSymbols, LSelfType, LSlot) then
      begin
        // The out slot came back empty: it is still self, unreadable
        LSlot := Default(TPCDebugSlot);
        LSlot.DisplayName := PC_DBG_SELF_NAME;
        LSlot.AstType := LSelfType;
      end;
      if not LSlot.HasAddress then
        LSlot.Problem := RSDbgValueUnreadable;
      // self prints as its type's name (TBox), not the definition (object)
      LSlot.TypeName := LTypeDecl.DeclName;
      Result := Result + [LSlot];
    end;

    for LParam in LRoutine.Params do
    begin
      if not DoLocalSlot(AFrameId, LSymbols, LParam.ParamName, LParam.ParamName, LParam.TypeExpr,
        DoIsByReference(LParam), LSlot) then
      begin
        LSlot := Default(TPCDebugSlot);
        LSlot.DisplayName := LParam.ParamName;
        LSlot.AstType := LParam.TypeExpr;
        LSlot.Problem := RSDbgValueUnreadable;
      end;
      Result := Result + [LSlot];
    end;
  finally
    LFrames.Free();
  end;
end;

function TPCDebugRuntime.DoLocalSlots(const AFrameId: Integer): TArray<TPCDebugSlot>;
var
  LInfo: TPCDebugFrameInfo;
  LSymbols: TArray<TPCDebugSymbol>;
  LFrames: TList<TPCScopeFrame>;
  LFound: TList<TPCNode>;
  LKnown: TList<string>;
  LIndex: Integer;
  LNode: TPCNode;
  LDecl: TPCDecl;
  LAstType: TPCTypeExpr;
  LSlot: TPCDebugSlot;
  LRoutine: TPCRoutine;
  LParam: TPCParam;
begin
  Result := nil;
  LInfo := FFrames[AFrameId - 1];
  if not FSymbols.FrameSymbols(LInfo.Frame, LSymbols) then
    Exit;
  if LInfo.Module = nil then
    Exit(DoRawSlots(AFrameId, False, nil));

  LFrames := TList<TPCScopeFrame>.Create();
  LFound := TList<TPCNode>.Create();
  LKnown := TList<string>.Create();
  try
    DoFrameChain(LInfo, LFrames);
    // Innermost first, one entry per name (an inner one hides an outer);
    // the locals end at the routine / test (members and the module are
    // self's and the globals' business)
    for LIndex := LFrames.Count - 1 downto 0 do
    begin
      if not (LFrames[LIndex].FrameKind in [fkList, fkRoutine, fkTest]) then
        Break;
      if LFrames[LIndex].FrameKind = fkRoutine then
      begin
        LRoutine := TPCRoutine(LFrames[LIndex].Owner);
        for LParam in LRoutine.Params do
          if not LKnown.Contains(LParam.ParamName) then
            LKnown.Add(LParam.ParamName);
      end;
      LFound.Clear();
      TPCScopes.CollectAll(LFrames[LIndex], LFound);
      for LNode in LFound do
      begin
        if LNode is TPCVarDecl then
          LAstType := TPCVarDecl(LNode).TypeExpr
        else if LNode is TPCConstDecl then
          LAstType := TPCConstDecl(LNode).TypeExpr
        else
          Continue;
        LDecl := TPCDecl(LNode);
        if LKnown.Contains(LDecl.DeclName) then
          Continue;
        LKnown.Add(LDecl.DeclName);
        if DoLocalSlot(AFrameId, LSymbols, TPCEmitter.DoDeclName(LDecl), LDecl.DeclName, LAstType, False, LSlot) then
          Result := Result + [LSlot]
        else if LNode is TPCVarDecl then
        begin
          // Declared and visible, but the PDB has no place for it
          LSlot := Default(TPCDebugSlot);
          LSlot.DisplayName := LDecl.DeclName;
          LSlot.AstType := LAstType;
          LSlot.Problem := RSDbgValueUnreadable;
          Result := Result + [LSlot];
        end
        // A const the compiler kept no storage for: the value the AST holds
        // (PLAN-VENDOR 1e; it was not listed); with none it is not listed
        else if DoConstValueSlot(TPCConstDecl(LNode), LSlot) then
          Result := Result + [LSlot];
      end;
    end;
    // C++ locals with no PaskalCPP declaration (verbatim C++), raw (W3)
    Result := Result + DoRawSlots(AFrameId, False, LKnown);
  finally
    LKnown.Free();
    LFound.Free();
    LFrames.Free();
  end;
end;

class function TPCDebugRuntime.DoConstValueSlot(const ADecl: TPCConstDecl; out ASlot: TPCDebugSlot): Boolean;
var
  LText: string;
begin
  // The value SEM folded (an integer constant, an expression of them), else
  // a literal as written (a string, a char, a float, a bool); anything else
  // (a C++ value) has no value the AST holds: False
  ASlot := Default(TPCDebugSlot);
  Result := False;
  if (ADecl = nil) or (ADecl.ValueExpr = nil) then
    Exit;
  if not TPCAst.FoldedText(ADecl.ValueExpr, LText) then
  begin
    if not (ADecl.ValueExpr is TPCLiteral) then
      Exit;
    LText := ADecl.ValueExpr.ExprText();
  end;
  ASlot.DisplayName := ADecl.DeclName;
  ASlot.AstType := ADecl.TypeExpr;
  ASlot.HasConstValue := True;
  ASlot.ConstValue := LText;
  Result := True;
end;

function TPCDebugRuntime.DoGlobalSlots(const AFrameId: Integer): TArray<TPCDebugSlot>;
var
  LInfo: TPCDebugFrameInfo;
  LStmt: TPCStmt;
  LDecl: TPCVarDecl;
  LCppName: string;
  LSymbol: TPCDebugSymbol;
  LSlot: TPCDebugSlot;
begin
  // The module variables of the frame's module, by the emitter's name
  // (pcpp_m_<M>::<N>; the PDB spells it without the leading ::)
  Result := nil;
  LInfo := FFrames[AFrameId - 1];
  if LInfo.Module = nil then
    Exit;
  for LStmt in LInfo.Module.Decls do
  begin
    // PLAN-VENDOR 1e: a module const too, from its storage when the PDB has
    // it, else the value the AST holds; one with neither is not listed
    if LStmt is TPCConstDecl then
    begin
      LCppName := TPCEmitter.DoDeclName(TPCConstDecl(LStmt));
      if LCppName.StartsWith('::') then
        LCppName := LCppName.Substring(2);
      if FSymbols.GlobalSymbol(LCppName, LSymbol) then
        Result := Result + [DoSymbolSlot(LInfo, LSymbol, TPCConstDecl(LStmt).DeclName,
          TPCConstDecl(LStmt).TypeExpr, False)]
      else if DoConstValueSlot(TPCConstDecl(LStmt), LSlot) then
        Result := Result + [LSlot];
      Continue;
    end;
    if not (LStmt is TPCVarDecl) then
      Continue;
    LDecl := TPCVarDecl(LStmt);
    LCppName := TPCEmitter.DoDeclName(LDecl);
    if LCppName.StartsWith('::') then
      LCppName := LCppName.Substring(2);
    if FSymbols.GlobalSymbol(LCppName, LSymbol) or FSymbols.GlobalSymbol(LDecl.DeclName, LSymbol) then
      LSlot := DoSymbolSlot(LInfo, LSymbol, LDecl.DeclName, LDecl.TypeExpr, False)
    else
    begin
      LSlot := Default(TPCDebugSlot);
      LSlot.DisplayName := LDecl.DeclName;
      LSlot.AstType := LDecl.TypeExpr;
      LSlot.Problem := RSDbgValueUnreadable;
    end;
    Result := Result + [LSlot];
  end;
end;

function TPCDebugRuntime.DoRawSlots(const AFrameId: Integer; const AParams: Boolean;
  const AKnown: TList<string>): TArray<TPCDebugSlot>;
var
  LInfo: TPCDebugFrameInfo;
  LSymbols: TArray<TPCDebugSymbol>;
  LSymbol: TPCDebugSymbol;
begin
  // The PDB's own names and types. With sources (AKnown given) only what
  // PaskalCPP does not declare, and never this or the compiler's own names
  Result := nil;
  LInfo := FFrames[AFrameId - 1];
  if not FSymbols.FrameSymbols(LInfo.Frame, LSymbols) then
    Exit;
  for LSymbol in LSymbols do
  begin
    if LSymbol.IsParam <> AParams then
      Continue;
    if AKnown <> nil then
    begin
      if AKnown.Contains(LSymbol.CppName) or (LSymbol.CppName = PC_DBG_THIS_NAME) or
        DoIsHiddenName(LSymbol.CppName) then
        Continue;
    end;
    Result := Result + [DoSymbolSlot(LInfo, LSymbol, LSymbol.CppName, nil, False)];
  end;
end;

{ TPCDebugRuntime: types and memory }

function TPCDebugRuntime.DoPdbType(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
  out AType: TPCDebugType): Boolean;
var
  LIndex: Cardinal;
  LDepth: Integer;
begin
  // The type as laid out, through its typedefs (DescribeType reports a
  // typedef and does not follow it)
  AType := Default(TPCDebugType);
  Result := False;
  if (AModuleBase = 0) or (ATypeIndex = 0) then
    Exit;
  LIndex := ATypeIndex;
  for LDepth := 1 to PC_DBG_TYPEDEF_MAX do
  begin
    if not FSymbols.DescribeType(AModuleBase, LIndex, AType) then
      Exit(False);
    if AType.Tag <> dttTypedef then
      Exit(True);
    LIndex := AType.ElementType;
  end;
end;

function TPCDebugRuntime.DoPdbTypeName(const AModuleBase: UInt64; const ATypeIndex: Cardinal): string;
var
  LType: TPCDebugType;
begin
  // The C++ spelling of a PDB type (a raw C++ variable's type text)
  Result := '';
  if not FSymbols.DescribeType(AModuleBase, ATypeIndex, LType) then
    Exit;
  case LType.Tag of
    dttBase:
      case LType.BaseType of
        PC_DBG_BT_VOID: Result := 'void';
        PC_DBG_BT_CHAR: Result := 'char';
        PC_DBG_BT_WCHAR: Result := 'wchar_t';
        PC_DBG_BT_BOOL: Result := 'bool';
        PC_DBG_BT_CHAR8: Result := 'char8_t';
        PC_DBG_BT_CHAR16: Result := 'char16_t';
        PC_DBG_BT_CHAR32: Result := 'char32_t';
        PC_DBG_BT_FLOAT:
          if LType.Length = 4 then
            Result := 'float'
          else
            Result := 'double';
        PC_DBG_BT_UINT, PC_DBG_BT_ULONG:
          case LType.Length of
            1: Result := 'unsigned char';
            2: Result := 'unsigned short';
            4: Result := 'unsigned int';
          else
            Result := 'unsigned long long';
          end;
      else
        case LType.Length of
          1: Result := 'signed char';
          2: Result := 'short';
          4: Result := 'int';
        else
          Result := 'long long';
        end;
      end;
    dttPointer:
      Result := DoPdbTypeName(AModuleBase, LType.ElementType) + '*';
    dttArray:
      Result := DoPdbTypeName(AModuleBase, LType.ElementType) + '[' + IntToStr(LType.Count) + ']';
    dttFunction:
      Result := 'function';
  else
    Result := LType.CppName;
  end;
end;

function TPCDebugRuntime.DoFindField(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
  const ACppName: string; out AField: TPCDebugField; out AOffset: UInt64): Boolean;
var
  LType: TPCDebugType;
  LField: TPCDebugField;
  LInner: TPCDebugField;
  LInnerOffset: UInt64;
begin
  // A data member of a UDT by name; an anonymous union / struct's members
  // are the parent's own (PaskalCPP's anonymous aggregates are flattened)
  Result := False;
  AField := Default(TPCDebugField);
  AOffset := 0;
  if (not DoPdbType(AModuleBase, ATypeIndex, LType)) or (LType.Tag <> dttUdt) then
    Exit;
  for LField in LType.Fields do
    if (not LField.IsBase) and (LField.CppName = ACppName) then
    begin
      AField := LField;
      AOffset := LField.Offset;
      Exit(True);
    end;
  for LField in LType.Fields do
    if (not LField.IsBase) and (LField.CppName = '') then
      if DoFindField(AModuleBase, LField.TypeIndex, ACppName, LInner, LInnerOffset) then
      begin
        AField := LInner;
        AOffset := LField.Offset + LInnerOffset;
        Exit(True);
      end;
end;

function TPCDebugRuntime.DoBaseField(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
  const ARecord: TPCRecordType; out AField: TPCDebugField): Boolean;
var
  LType: TPCDebugType;
  LField: TPCDebugField;
begin
  // The record's parent part: a record's PaskalCPP parent is its first data
  // member pcpp_parent (PLAN-RECORDS M10, the emitter's name); an object's
  // or a C/C++ parent is the PDB's base class child
  Result := False;
  AField := Default(TPCDebugField);
  if (not DoPdbType(AModuleBase, ATypeIndex, LType)) or (LType.Tag <> dttUdt) then
    Exit;
  for LField in LType.Fields do
  begin
    if ARecord.HasParentMember() then
    begin
      if (not LField.IsBase) and (LField.CppName = PC_EMT_PARENT_MEMBER) then
      begin
        AField := LField;
        Exit(True);
      end;
    end
    else if LField.IsBase then
    begin
      AField := LField;
      Exit(True);
    end;
  end;
end;

procedure TPCDebugRuntime.DoCollectPointers(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
  const AOffset: Cardinal; const ADepth: Integer; const AFound: TList<TPCDebugField>);
var
  LType: TPCDebugType;
  LMemberType: TPCDebugType;
  LField: TPCDebugField;
  LHit: TPCDebugField;
begin
  // The PDB's own layout, not libc++'s as remembered: a pointer member is
  // taken where it lies, an aggregate member (unique_ptr's compressed pair)
  // is walked into, bases included
  if (AFound.Count >= 2) or (ADepth > PC_DBG_OWNER_DEPTH_MAX) then
    Exit;
  if (not DoPdbType(AModuleBase, ATypeIndex, LType)) or (LType.Tag <> dttUdt) then
    Exit;
  for LField in LType.Fields do
  begin
    if AFound.Count >= 2 then
      Exit;
    if not DoPdbType(AModuleBase, LField.TypeIndex, LMemberType) then
      Continue;
    if LMemberType.Tag = dttPointer then
    begin
      LHit := LField;
      LHit.Offset := AOffset + LField.Offset;
      AFound.Add(LHit);
    end
    else if LMemberType.Tag = dttUdt then
      DoCollectPointers(AModuleBase, LField.TypeIndex, AOffset + LField.Offset, ADepth + 1, AFound);
  end;
end;

function TPCDebugRuntime.DoFindDeepField(const AModuleBase: UInt64; const ATypeIndex: Cardinal;
  const ACppName: string; out AField: TPCDebugField; out AOffset: UInt64): Boolean;
var
  LType: TPCDebugType;
  LField: TPCDebugField;
  LInnerOffset: UInt64;
begin
  // DoFindField's own level first, then each base class
  if DoFindField(AModuleBase, ATypeIndex, ACppName, AField, AOffset) then
    Exit(True);
  Result := False;
  if (not DoPdbType(AModuleBase, ATypeIndex, LType)) or (LType.Tag <> dttUdt) then
    Exit;
  for LField in LType.Fields do
    if LField.IsBase and DoFindDeepField(AModuleBase, LField.TypeIndex, ACppName, AField, LInnerOffset) then
    begin
      AOffset := LField.Offset + LInnerOffset;
      Exit(True);
    end;
end;

function TPCDebugRuntime.DoOwnerTarget(const ASlot: TPCDebugSlot; const AOwner: TPCOwnerType;
  out AAddress: UInt64; out ATypeIndex: Cardinal; out AExpired: Boolean; out AReadable: Boolean): Boolean;
var
  LPointers: TList<TPCDebugField>;
  LPointerType: TPCDebugType;
  LControl: UInt64;
  LControlType: TPCDebugType;
  LOwnersField: TPCDebugField;
  LOwnersType: TPCDebugType;
  LOwnersOffset: UInt64;
  LOwners: UInt64;
begin
  Result := False;
  AAddress := 0;
  ATypeIndex := 0;
  AExpired := False;
  AReadable := False;
  LPointers := TList<TPCDebugField>.Create();
  try
    DoCollectPointers(ASlot.ModuleBase, ASlot.TypeIndex, 0, 0, LPointers);
    if (LPointers.Count < 1) or (not DoPdbType(ASlot.ModuleBase, LPointers[0].TypeIndex, LPointerType)) then
      Exit;
    if not DoReadUInt(ASlot.Address + LPointers[0].Offset, PC_DBG_POINTER_SIZE, AAddress) then
      Exit;
    AReadable := True;
    ATypeIndex := LPointerType.ElementType;
    if AAddress = 0 then
      Exit;
    // A weak's object may be gone while its pointer stays set: it is shown
    // only while an owner holds it (the control block counts owners less one)
    if AOwner.OwnerKind = okWeak then
    begin
      if (LPointers.Count < 2) or
        (not DoReadUInt(ASlot.Address + LPointers[1].Offset, PC_DBG_POINTER_SIZE, LControl)) then
      begin
        AReadable := False;
        Exit;
      end;
      // No control block: nothing was ever watched (nil)
      if LControl = 0 then
        Exit;
      if (not DoPdbType(ASlot.ModuleBase, LPointers[1].TypeIndex, LControlType)) or
        (not DoFindDeepField(ASlot.ModuleBase, LControlType.ElementType, PC_DBG_LIBCXX_SHARED_OWNERS,
          LOwnersField, LOwnersOffset)) or
        (not DoPdbType(ASlot.ModuleBase, LOwnersField.TypeIndex, LOwnersType)) or
        (not DoReadUInt(LControl + LOwnersOffset, Integer(LOwnersType.Length), LOwners)) then
      begin
        AReadable := False;
        Exit;
      end;
      if DoSignExtend(LOwners, Integer(LOwnersType.Length)) < 0 then
      begin
        AExpired := True;
        Exit;
      end;
    end;
    Result := True;
  finally
    LPointers.Free();
  end;
end;

function TPCDebugRuntime.DoRead(const AAddress: UInt64; const ASize: NativeUInt; out ABytes: TBytes): Boolean;
begin
  Result := FTarget.ReadMemory(AAddress, ASize, ABytes) and (NativeUInt(Length(ABytes)) = ASize);
end;

function TPCDebugRuntime.DoReadUInt(const AAddress: UInt64; const ASize: Integer; out AValue: UInt64): Boolean;
var
  LBytes: TBytes;
begin
  // ASize (1, 2, 4, 8) bytes, little endian
  AValue := 0;
  Result := (ASize >= 1) and (ASize <= PC_DBG_POINTER_SIZE) and DoRead(AAddress, ASize, LBytes);
  if Result then
    Move(LBytes[0], AValue, ASize);
end;

function TPCDebugRuntime.DoChildSlot(const AParent: TPCDebugSlot; const ADisplayName: string;
  const AAstType: TPCTypeExpr; const ATypeIndex: Cardinal; const AAddress: UInt64): TPCDebugSlot;
begin
  Result := Default(TPCDebugSlot);
  Result.DisplayName := ADisplayName;
  Result.AstType := AAstType;
  Result.ModuleBase := AParent.ModuleBase;
  Result.TypeIndex := ATypeIndex;
  Result.Address := AAddress;
  Result.HasAddress := True;
end;

function TPCDebugRuntime.DoAddRef(const ASlot: TPCDebugSlot): Integer;
begin
  FRefs.Add(ASlot);
  Result := FRefs.Count;
end;

{ TPCDebugRuntime: values }

function TPCDebugRuntime.DoValue(const ASlot: TPCDebugSlot): TPCDebugValue;
var
  LHasChildren: Boolean;
begin
  Result := Default(TPCDebugValue);
  Result.DisplayName := ASlot.DisplayName;
  if ASlot.TypeName <> '' then
    Result.TypeText := ASlot.TypeName
  else if ASlot.AstType <> nil then
    Result.TypeText := ASlot.AstType.TypeText()
  else
    Result.TypeText := DoPdbTypeName(ASlot.ModuleBase, ASlot.TypeIndex);
  if ASlot.HasConstValue then
  begin
    Result.ValueText := ASlot.ConstValue;
    Result.IsReadable := True;
    Exit;
  end;
  if not ASlot.HasAddress then
  begin
    Result.ValueText := ASlot.Problem;
    if Result.ValueText = '' then
      Result.ValueText := RSDbgValueUnreadable;
    Exit;
  end;
  Result.ValueText := DoValueText(ASlot, False, LHasChildren);
  Result.IsReadable := Result.ValueText <> RSDbgValueUnreadable;
  if LHasChildren and Result.IsReadable then
    Result.ChildrenRef := DoAddRef(ASlot);
end;

function TPCDebugRuntime.DoValueText(const ASlot: TPCDebugSlot; const ASummary: Boolean;
  out AHasChildren: Boolean): string;
var
  LHandled: Boolean;
begin
  // By the PaskalCPP type when there is one; a C / C++ type (opaque, verbatim)
  // or no AST at all: the PDB's own reading
  AHasChildren := False;
  if ASlot.HasConstValue then
    Exit(ASlot.ConstValue);
  if not ASlot.HasAddress then
    Exit(RSDbgValueUnreadable);
  if ASlot.IsBitfield then
    Exit(DoBitfieldText(ASlot));
  if ASlot.AstType <> nil then
  begin
    Result := DoAstText(ASlot, ASlot.AstType.Canon(), ASummary, AHasChildren, LHandled);
    if LHandled then
      Exit;
  end;
  Result := DoRawText(ASlot, ASummary, AHasChildren);
end;

procedure TPCDebugRuntime.DoSetBits(var ASlot: TPCDebugSlot; const AField: TPCDebugField);
begin
  ASlot.IsBitfield := AField.IsBitfield;
  ASlot.BitPosition := AField.BitPosition;
  ASlot.BitWidth := AField.BitWidth;
end;

function TPCDebugRuntime.DoBitfieldText(const ASlot: TPCDebugSlot): string;
var
  LPdb: TPCDebugType;
  LUnit: UInt64;
  LBits: UInt64;
  LMask: UInt64;
  LSigned: Boolean;
  LOrdinal: Int64;
  LType: TPCTypeExpr;
  LEnumerator: TPCDebugEnumerator;
begin
  // The storage unit (the member's type, PDB size), shifted to the field's
  // first bit and masked to its width; a signed type's top bit extends
  if (not DoPdbType(ASlot.ModuleBase, ASlot.TypeIndex, LPdb)) or (not (LPdb.Length in [1, 2, 4, 8])) or
    (ASlot.BitWidth = 0) or (ASlot.BitPosition + ASlot.BitWidth > LPdb.Length * 8) or
    (not DoReadUInt(ASlot.Address, Integer(LPdb.Length), LUnit)) then
    Exit(RSDbgValueUnreadable);
  LBits := LUnit shr ASlot.BitPosition;
  LMask := High(UInt64);
  if ASlot.BitWidth < 64 then
    LMask := (UInt64(1) shl ASlot.BitWidth) - 1;
  LBits := LBits and LMask;

  LType := nil;
  if ASlot.AstType <> nil then
    LType := ASlot.AstType.Canon();
  // Signed: PaskalCPP's signed integers and choices (BNF: a choices field
  // holds every ordinal as a signed value); raw: the PDB's signed types
  if LType is TPCBuiltinType then
    LSigned := TPCBuiltinType(LType).BuiltinToken in [tkKwInt8, tkKwInt16, tkKwInt32, tkKwInt64]
  else if LType is TPCChoicesType then
    LSigned := True
  else
    LSigned := (LPdb.Tag = dttEnum) or
      ((LPdb.Tag = dttBase) and (LPdb.BaseType in [PC_DBG_BT_CHAR, PC_DBG_BT_INT, PC_DBG_BT_LONG]));
  LOrdinal := Int64(LBits);
  if LSigned and (ASlot.BitWidth < 64) and (((LBits shr (ASlot.BitWidth - 1)) and 1) = 1) then
    LOrdinal := Int64(LBits or (not LMask));

  if ((LType is TPCBuiltinType) and (TPCBuiltinType(LType).BuiltinToken = tkKwBool)) or
    ((LType = nil) and (LPdb.Tag = dttBase) and (LPdb.BaseType = PC_DBG_BT_BOOL)) then
  begin
    if LBits <> 0 then
      Exit('true');
    Exit('false');
  end;
  if LType is TPCChoicesType then
    Exit(DoChoiceText(TPCChoicesType(LType), LOrdinal));
  if (LType = nil) and (LPdb.Tag = dttEnum) then
    for LEnumerator in LPdb.Enumerators do
      if LEnumerator.Value = LOrdinal then
        Exit(DoShortName(LEnumerator.CppName));
  if LSigned then
    Result := IntToStr(LOrdinal)
  else
    Result := UIntToStr(LBits);
end;

function TPCDebugRuntime.DoAstText(const ASlot: TPCDebugSlot; const AType: TPCTypeExpr; const ASummary: Boolean;
  out AHasChildren: Boolean; out AHandled: Boolean): string;
var
  LPdb: TPCDebugType;
  LSize: Integer;
  LValue: UInt64;
  LOrdinal: Int64;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
  LTypeIndex: Cardinal;
  LExpired: Boolean;
  LReadable: Boolean;
begin
  AHasChildren := False;
  AHandled := True;
  Result := '';
  if AType is TPCBuiltinType then
    Exit(DoBuiltinText(ASlot, TPCBuiltinType(AType)));

  if AType is TPCChoicesType then
  begin
    // A C++ enum: its size from the PDB (4 when it says nothing)
    LSize := 4;
    if DoPdbType(ASlot.ModuleBase, ASlot.TypeIndex, LPdb) and (LPdb.Length in [1, 2, 4, 8]) then
      LSize := LPdb.Length;
    if not DoReadUInt(ASlot.Address, LSize, LValue) then
      Exit(RSDbgValueUnreadable);
    LOrdinal := DoSignExtend(LValue, LSize);
    Exit(DoChoiceText(TPCChoicesType(AType), LOrdinal));
  end;

  if AType is TPCOwnerType then
  begin
    // PLAN-OBJECT O14: own / ref / weak read as a typed pointer does (the
    // object is the ^ child), a weak whose object is gone as expired
    if DoOwnerTarget(ASlot, TPCOwnerType(AType), LValue, LTypeIndex, LExpired, LReadable) then
    begin
      AHasChildren := True;
      Exit('$' + IntToHex(LValue, 16));
    end;
    if LExpired then
      Exit(RSDbgWeakExpired);
    if not LReadable then
      Exit(RSDbgValueUnreadable);
    Exit('nil');
  end;

  if TPCTypeExpr.PointerOf(AType, LTarget, LIsConst) or (AType is TPCRoutineType) or (AType is TPCNilType) then
  begin
    if not DoReadUInt(ASlot.Address, PC_DBG_POINTER_SIZE, LValue) then
      Exit(RSDbgValueUnreadable);
    if LValue = 0 then
      Exit('nil');
    // A typed pointer's target is its child (^)
    AHasChildren := (LTarget <> nil) and (not (AType is TPCRoutineType));
    Exit('$' + IntToHex(LValue, 16));
  end;

  if (AType is TPCRecordType) or (AType is TPCOverlayType) then
  begin
    AHasChildren := True;
    if ASummary then
      Exit('{...}');
    Exit(DoMemberText(ASlot));
  end;

  if AType is TPCArrayType then
  begin
    AHasChildren := True;
    if ASummary then
      Exit('[...]');
    Exit(DoElementsText(ASlot));
  end;

  if (AType is TPCSetType) and TPCSetType(AType).HasResolvedBounds then
    Exit(DoSetText(ASlot, TPCSetType(AType)));

  // Opaque C / C++, a set with C++ bounds, an error type: the PDB's reading
  AHandled := False;
end;

function TPCDebugRuntime.DoRawText(const ASlot: TPCDebugSlot; const ASummary: Boolean;
  out AHasChildren: Boolean): string;
var
  LType: TPCDebugType;
  LElement: TPCDebugType;
  LValue: UInt64;
  LSize: Integer;
  LOrdinal: Int64;
  LEnumerator: TPCDebugEnumerator;
begin
  AHasChildren := False;
  if not DoPdbType(ASlot.ModuleBase, ASlot.TypeIndex, LType) then
    Exit(RSDbgValueUnreadable);
  LSize := Integer(Min(LType.Length, UInt64(PC_DBG_POINTER_SIZE)));
  case LType.Tag of
    dttBase:
      case LType.BaseType of
        PC_DBG_BT_VOID:
          Result := '';
        PC_DBG_BT_BOOL:
          if DoReadUInt(ASlot.Address, LSize, LValue) then
          begin
            if LValue <> 0 then
              Result := 'true'
            else
              Result := 'false';
          end
          else
            Result := RSDbgValueUnreadable;
        PC_DBG_BT_FLOAT:
          Result := DoFloatText(ASlot.Address, LSize);
        PC_DBG_BT_CHAR, PC_DBG_BT_WCHAR, PC_DBG_BT_CHAR8, PC_DBG_BT_CHAR16, PC_DBG_BT_CHAR32:
          if DoReadUInt(ASlot.Address, LSize, LValue) then
            Result := DoCharText(LValue, DoCharPrefix(LType.BaseType), LSize = 1)
          else
            Result := RSDbgValueUnreadable;
        PC_DBG_BT_UINT, PC_DBG_BT_ULONG:
          Result := DoIntText(ASlot.Address, LSize, False);
      else
        Result := DoIntText(ASlot.Address, LSize, True);
      end;
    dttEnum:
      begin
        if not DoReadUInt(ASlot.Address, LSize, LValue) then
          Exit(RSDbgValueUnreadable);
        LOrdinal := DoSignExtend(LValue, LSize);
        Result := IntToStr(LOrdinal);
        for LEnumerator in LType.Enumerators do
          if LEnumerator.Value = LOrdinal then
            Exit(DoShortName(LEnumerator.CppName));
      end;
    dttPointer:
      begin
        if not DoReadUInt(ASlot.Address, PC_DBG_POINTER_SIZE, LValue) then
          Exit(RSDbgValueUnreadable);
        if LValue = 0 then
          Exit('nil');
        AHasChildren := DoPdbType(ASlot.ModuleBase, LType.ElementType, LElement) and
          (LElement.Tag in [dttBase, dttPointer, dttUdt, dttEnum, dttArray]) and
          not ((LElement.Tag = dttBase) and (LElement.BaseType = PC_DBG_BT_VOID));
        Result := '$' + IntToHex(LValue, 16);
      end;
    dttUdt:
      begin
        if LType.CppName.StartsWith(PC_DBG_LIBCXX_STRING) then
          Exit(DoStringText(ASlot.Address, 1));
        if LType.CppName.StartsWith(PC_DBG_LIBCXX_WSTRING) then
          Exit(DoStringText(ASlot.Address, PC_DBG_WCHAR_SIZE));
        AHasChildren := True;
        if ASummary then
          Exit('{...}');
        Result := DoMemberText(ASlot);
      end;
    dttArray:
      begin
        AHasChildren := True;
        if ASummary then
          Exit('[...]');
        Result := DoElementsText(ASlot);
      end;
  else
    Result := '';
  end;
end;

function TPCDebugRuntime.DoBuiltinText(const ASlot: TPCDebugSlot; const AType: TPCBuiltinType): string;
var
  LValue: UInt64;
begin
  case AType.BuiltinToken of
    tkKwInt8: Result := DoIntText(ASlot.Address, 1, True);
    tkKwInt16: Result := DoIntText(ASlot.Address, 2, True);
    tkKwInt32: Result := DoIntText(ASlot.Address, 4, True);
    tkKwInt64: Result := DoIntText(ASlot.Address, 8, True);
    tkKwUint8: Result := DoIntText(ASlot.Address, 1, False);
    tkKwUint16: Result := DoIntText(ASlot.Address, 2, False);
    tkKwUint32: Result := DoIntText(ASlot.Address, 4, False);
    tkKwUint64: Result := DoIntText(ASlot.Address, 8, False);
    tkKwFloat32: Result := DoFloatText(ASlot.Address, 4);
    tkKwFloat64: Result := DoFloatText(ASlot.Address, 8);
    tkKwBool:
      if DoReadUInt(ASlot.Address, 1, LValue) then
      begin
        if LValue <> 0 then
          Result := 'true'
        else
          Result := 'false';
      end
      else
        Result := RSDbgValueUnreadable;
    tkKwChar:
      if DoReadUInt(ASlot.Address, 1, LValue) then
        Result := DoCharText(LValue, '', True)
      else
        Result := RSDbgValueUnreadable;
    tkKwWchar:
      if DoReadUInt(ASlot.Address, PC_DBG_WCHAR_SIZE, LValue) then
        Result := DoCharText(LValue, 'L', False)
      else
        Result := RSDbgValueUnreadable;
    tkKwString: Result := DoStringText(ASlot.Address, 1);
    tkKwWstring: Result := DoStringText(ASlot.Address, PC_DBG_WCHAR_SIZE);
  else
    Result := RSDbgValueUnreadable;
  end;
end;

function TPCDebugRuntime.DoSignExtend(const AValue: UInt64; const ASize: Integer): Int64;
begin
  case ASize of
    1: Result := ShortInt(Byte(AValue));
    2: Result := SmallInt(Word(AValue));
    4: Result := Integer(Cardinal(AValue));
  else
    Result := Int64(AValue);
  end;
end;

function TPCDebugRuntime.DoIntText(const AAddress: UInt64; const ASize: Integer; const ASigned: Boolean): string;
var
  LValue: UInt64;
begin
  if not DoReadUInt(AAddress, ASize, LValue) then
    Exit(RSDbgValueUnreadable);
  if ASigned then
    Result := IntToStr(DoSignExtend(LValue, ASize))
  else
    Result := UIntToStr(LValue);
end;

function TPCDebugRuntime.DoFloatText(const AAddress: UInt64; const ASize: Integer): string;
var
  LBytes: TBytes;
  LSingle: Single;
  LDouble: Double;
begin
  if (not (ASize in [4, 8])) or (not DoRead(AAddress, ASize, LBytes)) then
    Exit(RSDbgValueUnreadable);
  if ASize = 4 then
  begin
    Move(LBytes[0], LSingle, 4);
    Result := FloatToStr(LSingle, TFormatSettings.Invariant);
  end
  else
  begin
    Move(LBytes[0], LDouble, 8);
    Result := FloatToStr(LDouble, TFormatSettings.Invariant);
  end;
end;

function TPCDebugRuntime.DoEscaped(const ACode: Cardinal; const AQuote: Char; const AOneByte: Boolean): string;
var
  LPlain: Boolean;
  LValue: Cardinal;
begin
  // One character of a value spelled as its C++ literal (literals follow
  // C++, BNF.md sec 10): the literal's own quote and the backslash escaped,
  // the common controls by name, and every code no source character shows
  // as a delimited escape \x{...} (exact: never joined with a hex digit
  // after it; TPCCString.DoDelimited reads it back)
  if ACode = Ord(AQuote) then
    Exit('\' + AQuote);
  if ACode = Ord('\') then
    Exit('\\');
  if ACode = 10 then
    Exit('\n');
  if ACode = 13 then
    Exit('\r');
  if ACode = 9 then
    Exit('\t');

  // C0 controls and DEL
  LPlain := (ACode >= 32) and (ACode <> 127);
  // C1 controls
  if (ACode >= 128) and (ACode < 160) then
    LPlain := False;
  // In a one-byte literal ('x', u8'x') a code past ASCII is a byte, not a character
  if AOneByte and (ACode >= 128) then
    LPlain := False;
  // A lone surrogate or a code past Unicode is no character at all
  if ((ACode >= $D800) and (ACode <= $DFFF)) or (ACode > $10FFFF) then
    LPlain := False;
  if not LPlain then
    Exit('\x{' + IntToHex(ACode, 1) + '}');

  if ACode <= $FFFF then
    Exit(Char(ACode));
  // Past the BMP: the UTF-16 surrogate pair of the code
  LValue := ACode - $10000;
  Result := Char($D800 + (LValue shr 10)) + Char($DC00 + (LValue and $3FF));
end;

function TPCDebugRuntime.DoCharPrefix(const ABaseType: Cardinal): string;
begin
  // The C++ literal prefix of a character type the PDB names
  if ABaseType = PC_DBG_BT_WCHAR then
    Result := 'L'
  else if ABaseType = PC_DBG_BT_CHAR8 then
    Result := 'u8'
  else if ABaseType = PC_DBG_BT_CHAR16 then
    Result := 'u'
  else if ABaseType = PC_DBG_BT_CHAR32 then
    Result := 'U'
  else
    Result := '';
end;

function TPCDebugRuntime.DoCharText(const ACode: UInt64; const APrefix: string; const AOneByte: Boolean): string;
begin
  // A character value as its C++ literal: 'q', '\n', '\x{E9}', L'w'
  Result := APrefix + '''' + DoEscaped(Cardinal(ACode), '''', AOneByte) + '''';
end;

function TPCDebugRuntime.DoQuoted(const AText: string; const APrefix: string; const ATruncated: Boolean): string;
var
  LBuilder: TStringBuilder;
  LIndex: Integer;
  LCode: Cardinal;
begin
  // A string value as its C++ literal ("hi", L"wide"), each character by
  // DoEscaped. AText is decoded Unicode, so a code past ASCII is a character
  LBuilder := TStringBuilder.Create();
  try
    LBuilder.Append(APrefix);
    LBuilder.Append('"');
    LIndex := 1;
    while LIndex <= Length(AText) do
    begin
      LCode := Ord(AText[LIndex]);
      // A surrogate pair is one character: kept as written
      if (LCode >= $D800) and (LCode <= $DBFF) and (LIndex < Length(AText)) and
        (Ord(AText[LIndex + 1]) >= $DC00) and (Ord(AText[LIndex + 1]) <= $DFFF) then
      begin
        LBuilder.Append(AText[LIndex]);
        LBuilder.Append(AText[LIndex + 1]);
        Inc(LIndex, 2);
        Continue;
      end;
      LBuilder.Append(DoEscaped(LCode, '"', False));
      Inc(LIndex);
    end;
    LBuilder.Append('"');
    if ATruncated then
      LBuilder.Append('...');
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

function TPCDebugRuntime.DoStringText(const AAddress: UInt64; const ACharSize: Integer): string;
var
  LFirst: UInt64;
  LSize: UInt64;
  LData: UInt64;
  LCount: UInt64;
  LBytes: TBytes;
  LText: string;
begin
  // libc++ std::basic_string, little endian (debugger-pdb.md e2): bit 0 of
  // the first byte = the long form. Short: the size in that byte's upper
  // seven bits, the characters right after it (one character in). Long:
  // capacity word, size word, data pointer
  if not DoReadUInt(AAddress, 1, LFirst) then
    Exit(RSDbgValueUnreadable);
  if (LFirst and PC_DBG_LIBCXX_LONG_FLAG) = 0 then
  begin
    LSize := LFirst shr 1;
    LData := AAddress + UInt64(ACharSize);
  end
  else
  begin
    if (not DoReadUInt(AAddress + PC_DBG_LIBCXX_SIZE_OFFSET, PC_DBG_POINTER_SIZE, LSize)) or
      (not DoReadUInt(AAddress + PC_DBG_LIBCXX_DATA_OFFSET, PC_DBG_POINTER_SIZE, LData)) then
      Exit(RSDbgValueUnreadable);
  end;
  LCount := Min(LSize, UInt64(PC_DBG_STRING_MAX));
  LText := '';
  if LCount > 0 then
  begin
    if not DoRead(LData, NativeUInt(LCount * UInt64(ACharSize)), LBytes) then
      Exit(RSDbgValueUnreadable);
    try
      if ACharSize = 1 then
        LText := TEncoding.UTF8.GetString(LBytes)
      else
        LText := TEncoding.Unicode.GetString(LBytes);
    except
      on E: Exception do
        // Not valid text (an uninitialised string): its bytes one by one
        LText := TEncoding.ANSI.GetString(LBytes);
    end;
  end;
  // std::wstring is wchar_t text: an L literal
  if ACharSize = 1 then
    Result := DoQuoted(LText, '', LSize > LCount)
  else
    Result := DoQuoted(LText, 'L', LSize > LCount);
end;

function TPCDebugRuntime.DoChoiceText(const AChoices: TPCChoicesType; const AOrdinal: Int64): string;
var
  LValue: TPCChoiceValue;
begin
  for LValue in AChoices.Values do
    if LValue.HasResolvedOrdinal and (LValue.ResolvedOrdinal = AOrdinal) then
      Exit(LValue.ValueName);
  Result := IntToStr(AOrdinal);
end;

function TPCDebugRuntime.DoSetText(const ASlot: TPCDebugSlot; const ASet: TPCSetType): string;
var
  LWords: UInt64;
  LBits: UInt64;
  LBytes: TBytes;
  LBit: UInt64;
  LShown: Integer;
  LElement: TPCTypeExpr;
  LMember: Int64;
  LText: string;
begin
  // ::pcpp::Set<T, LOW, HIGH> (pcpp_runtime.h): pcpp_words, bit i = member LOW + i
  LBits := UInt64(ASet.ResolvedHigh - ASet.ResolvedLow) + 1;
  LWords := Min(UInt64(ASet.ResolvedHigh - ASet.ResolvedLow) div 64 + 1, UInt64(PC_DBG_SET_WORDS_MAX));
  if not DoRead(ASlot.Address, NativeUInt(LWords * 8), LBytes) then
    Exit(RSDbgValueUnreadable);
  LElement := nil;
  if ASet.ElementType <> nil then
    LElement := ASet.ElementType.Canon();
  Result := '[';
  LShown := 0;
  LBit := 0;
  while (LBit < LBits) and (LBit < LWords * 64) do
  begin
    if (LBytes[LBit div 8] and (1 shl (LBit mod 8))) <> 0 then
    begin
      if LShown = PC_DBG_SUMMARY_MAX then
      begin
        Result := Result + ', ...';
        Break;
      end;
      LMember := ASet.ResolvedLow + Int64(LBit);
      if LElement is TPCChoicesType then
        LText := DoChoiceText(TPCChoicesType(LElement), LMember)
      else if (LElement is TPCBuiltinType) and (TPCBuiltinType(LElement).BuiltinToken = tkKwBool) then
      begin
        if LMember <> 0 then
          LText := 'true'
        else
          LText := 'false';
      end
      else if (LElement is TPCBuiltinType) and (TPCBuiltinType(LElement).BuiltinToken = tkKwChar) then
        // A char member is one byte (its bounds may be signed: -128 .. 127)
        LText := DoCharText(Byte(LMember), '', True)
      else
        LText := IntToStr(LMember);
      if LShown > 0 then
        Result := Result + ', ';
      Result := Result + LText;
      Inc(LShown);
    end;
    Inc(LBit);
  end;
  Result := Result + ']';
end;

function TPCDebugRuntime.DoShortName(const ACppName: string): string;
var
  LAt: Integer;
begin
  // A C++ enumerator as written in its scope (pcpp_m_M::TCol::cRed -> cRed)
  LAt := ACppName.LastIndexOf('::');
  if LAt < 0 then
    Result := ACppName
  else
    Result := ACppName.Substring(LAt + 2);
end;

function TPCDebugRuntime.DoMemberText(const ASlot: TPCDebugSlot): string;
var
  LChildren: TArray<TPCDebugSlot>;
  LIndex: Integer;
  LUnused: Boolean;
begin
  // {Name: value, ...}, one level (a nested aggregate shows as {...})
  LChildren := DoChildren(ASlot);
  Result := '{';
  for LIndex := 0 to High(LChildren) do
  begin
    if LIndex = PC_DBG_SUMMARY_MAX then
    begin
      Result := Result + ', ...';
      Break;
    end;
    if LIndex > 0 then
      Result := Result + ', ';
    Result := Result + LChildren[LIndex].DisplayName + ': ' + DoValueText(LChildren[LIndex], True, LUnused);
  end;
  Result := Result + '}';
end;

function TPCDebugRuntime.DoElementsText(const ASlot: TPCDebugSlot): string;
var
  LChildren: TArray<TPCDebugSlot>;
  LIndex: Integer;
  LUnused: Boolean;
begin
  // [value, ...]: the first elements
  LChildren := DoChildren(ASlot);
  Result := '[';
  for LIndex := 0 to High(LChildren) do
  begin
    if LIndex = PC_DBG_SUMMARY_MAX then
    begin
      Result := Result + ', ...';
      Break;
    end;
    if LIndex > 0 then
      Result := Result + ', ';
    Result := Result + DoValueText(LChildren[LIndex], True, LUnused);
  end;
  Result := Result + ']';
end;

{ TPCDebugRuntime: children }

function TPCDebugRuntime.DoArrayLayout(const ASlot: TPCDebugSlot; const AArray: TPCArrayType;
  out AFirst: UInt64; out ACount: Int64; out AElementType: Cardinal; out AElementSize: UInt64;
  out ALow: Int64): Boolean;
var
  LType: TPCDebugType;
  LField: TPCDebugField;
  LInner: TPCDebugType;
  LElement: TPCDebugType;
  LPointer: TPCDebugType;
  LBegin: TPCDebugField;
  LEnd: TPCDebugField;
  LBeginOffset: UInt64;
  LEndOffset: UInt64;
  LBeginValue: UInt64;
  LEndValue: UInt64;
begin
  // A static array is ::pcpp::Array (one member: a C array); a dynamic array
  // is std::vector (__begin_ / __end_ pointers). Layout from the PDB, the
  // low bound from SEM's folded constant
  Result := False;
  AFirst := 0;
  ACount := 0;
  AElementType := 0;
  AElementSize := 0;
  ALow := 0;
  if (not DoPdbType(ASlot.ModuleBase, ASlot.TypeIndex, LType)) or (LType.Tag <> dttUdt) then
    Exit;

  if AArray.IsDynamic then
  begin
    if (not DoFindField(ASlot.ModuleBase, ASlot.TypeIndex, PC_DBG_LIBCXX_VECTOR_BEGIN, LBegin, LBeginOffset)) or
      (not DoFindField(ASlot.ModuleBase, ASlot.TypeIndex, PC_DBG_LIBCXX_VECTOR_END, LEnd, LEndOffset)) then
      Exit;
    if (not DoPdbType(ASlot.ModuleBase, LBegin.TypeIndex, LPointer)) or (LPointer.Tag <> dttPointer) then
      Exit;
    if (not DoPdbType(ASlot.ModuleBase, LPointer.ElementType, LElement)) or (LElement.Length = 0) then
      Exit;
    if (not DoReadUInt(ASlot.Address + LBeginOffset, PC_DBG_POINTER_SIZE, LBeginValue)) or
      (not DoReadUInt(ASlot.Address + LEndOffset, PC_DBG_POINTER_SIZE, LEndValue)) or
      (LEndValue < LBeginValue) then
      Exit;
    AFirst := LBeginValue;
    AElementType := LPointer.ElementType;
    AElementSize := LElement.Length;
    ACount := Int64((LEndValue - LBeginValue) div AElementSize);
    Exit(True);
  end;

  for LField in LType.Fields do
    if (not LField.IsBase) and DoPdbType(ASlot.ModuleBase, LField.TypeIndex, LInner) and
      (LInner.Tag = dttArray) then
    begin
      if not DoPdbType(ASlot.ModuleBase, LInner.ElementType, LElement) then
        Exit;
      AFirst := ASlot.Address + LField.Offset;
      AElementType := LInner.ElementType;
      AElementSize := LElement.Length;
      ACount := LInner.Count;
      if (AArray.LowExpr <> nil) and AArray.LowExpr.HasConstValue then
        ALow := AArray.LowExpr.ConstInt;
      Exit(True);
    end;
  // No C array member in the PDB type: no elements
  Result := True;
end;

procedure TPCDebugRuntime.DoArrayChildren(const ASlot: TPCDebugSlot; const AArray: TPCArrayType;
  const AChildren: TList<TPCDebugSlot>);
var
  LFirst: UInt64;
  LCount: Int64;
  LElementType: Cardinal;
  LElementSize: UInt64;
  LLow: Int64;
  LIndex: Int64;
begin
  if not DoArrayLayout(ASlot, AArray, LFirst, LCount, LElementType, LElementSize, LLow) then
    Exit;
  LIndex := 0;
  while (LIndex < LCount) and (LIndex < PC_DBG_CHILDREN_MAX) do
  begin
    AChildren.Add(DoChildSlot(ASlot, '[' + IntToStr(LLow + LIndex) + ']', AArray.ElementType, LElementType,
      LFirst + UInt64(LIndex) * LElementSize));
    Inc(LIndex);
  end;
end;

procedure TPCDebugRuntime.DoRecordChildren(const ASlot: TPCDebugSlot; const AMembers: TList<TPCMemberItem>;
  const AChildren: TList<TPCDebugSlot>);
var
  LItem: TPCMemberItem;
  LField: TPCField;
  LPdbField: TPCDebugField;
  LOffset: UInt64;
  LChild: TPCDebugSlot;
begin
  // Fields by FieldName in declaration order; an anonymous aggregate's
  // fields are the record's own; methods are not values
  for LItem in AMembers do
  begin
    if LItem is TPCAnonAggregate then
    begin
      DoRecordChildren(ASlot, TPCAnonAggregate(LItem).Members, AChildren);
      Continue;
    end;
    if not (LItem is TPCField) then
      Continue;
    LField := TPCField(LItem);
    if DoFindField(ASlot.ModuleBase, ASlot.TypeIndex, LField.FieldName, LPdbField, LOffset) then
    begin
      LChild := DoChildSlot(ASlot, LField.FieldName, LField.TypeExpr, LPdbField.TypeIndex, ASlot.Address + LOffset);
      DoSetBits(LChild, LPdbField);
    end
    else
    begin
      // Not in the PDB
      LChild := Default(TPCDebugSlot);
      LChild.DisplayName := LField.FieldName;
      LChild.AstType := LField.TypeExpr;
      LChild.Problem := RSDbgValueUnreadable;
    end;
    AChildren.Add(LChild);
  end;
end;

procedure TPCDebugRuntime.DoRawChildren(const ASlot: TPCDebugSlot; const AChildren: TList<TPCDebugSlot>);
var
  LType: TPCDebugType;
  LElement: TPCDebugType;
  LField: TPCDebugField;
  LValue: UInt64;
  LIndex: Cardinal;
  LChild: TPCDebugSlot;
begin
  if not DoPdbType(ASlot.ModuleBase, ASlot.TypeIndex, LType) then
    Exit;
  case LType.Tag of
    dttUdt:
      for LField in LType.Fields do
      begin
        LChild := DoChildSlot(ASlot, LField.CppName, nil, LField.TypeIndex, ASlot.Address + LField.Offset);
        LChild.IsBasePart := LField.IsBase;
        DoSetBits(LChild, LField);
        AChildren.Add(LChild);
      end;
    dttPointer:
      if DoReadUInt(ASlot.Address, PC_DBG_POINTER_SIZE, LValue) and (LValue <> 0) then
        AChildren.Add(DoChildSlot(ASlot, PC_DBG_DEREF_NAME, nil, LType.ElementType, LValue));
    dttArray:
      if DoPdbType(ASlot.ModuleBase, LType.ElementType, LElement) then
      begin
        LIndex := 0;
        while (LIndex < LType.Count) and (LIndex < PC_DBG_CHILDREN_MAX) do
        begin
          AChildren.Add(DoChildSlot(ASlot, '[' + UIntToStr(LIndex) + ']', nil, LType.ElementType,
            ASlot.Address + UInt64(LIndex) * LElement.Length));
          Inc(LIndex);
        end;
      end;
  end;
end;

function TPCDebugRuntime.DoChildren(const ASlot: TPCDebugSlot): TArray<TPCDebugSlot>;
var
  LList: TList<TPCDebugSlot>;
  LType: TPCTypeExpr;
  LRecord: TPCRecordType;
  LBase: TPCDebugField;
  LChild: TPCDebugSlot;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
  LValue: UInt64;
  LPdb: TPCDebugType;
  LTypeIndex: Cardinal;
  LExpired: Boolean;
  LReadable: Boolean;
begin
  Result := nil;
  if not ASlot.HasAddress then
    Exit;
  LList := TList<TPCDebugSlot>.Create();
  try
    LType := nil;
    if ASlot.AstType <> nil then
      LType := ASlot.AstType.Canon();

    if LType is TPCRecordType then
    begin
      LRecord := TPCRecordType(LType);
      // The parent part first (a record's pcpp_parent member, an object's
      // PDB base class child)
      if (LRecord.ParentName <> nil) and DoBaseField(ASlot.ModuleBase, ASlot.TypeIndex, LRecord, LBase) then
      begin
        LChild := DoChildSlot(ASlot, LRecord.ParentName.TypeText(), LRecord.ParentName, LBase.TypeIndex,
          ASlot.Address + LBase.Offset);
        LChild.IsBasePart := True;
        LList.Add(LChild);
      end;
      DoRecordChildren(ASlot, LRecord.Members, LList);
    end
    else if LType is TPCOverlayType then
      DoRecordChildren(ASlot, TPCOverlayType(LType).Members, LList)
    else if LType is TPCArrayType then
      DoArrayChildren(ASlot, TPCArrayType(LType), LList)
    else if LType is TPCOwnerType then
    begin
      // O14: the object an own / ref / live weak holds, named as a deref
      if DoOwnerTarget(ASlot, TPCOwnerType(LType), LValue, LTypeIndex, LExpired, LReadable) then
        LList.Add(DoChildSlot(ASlot, PC_DBG_DEREF_NAME, TPCOwnerType(LType).TargetType, LTypeIndex, LValue));
    end
    else if (LType <> nil) and TPCTypeExpr.PointerOf(LType, LTarget, LIsConst) then
    begin
      if (LTarget <> nil) and DoReadUInt(ASlot.Address, PC_DBG_POINTER_SIZE, LValue) and (LValue <> 0) and
        DoPdbType(ASlot.ModuleBase, ASlot.TypeIndex, LPdb) and (LPdb.Tag = dttPointer) then
        LList.Add(DoChildSlot(ASlot, PC_DBG_DEREF_NAME, LTarget, LPdb.ElementType, LValue));
    end
    else
      DoRawChildren(ASlot, LList);
    Result := LList.ToArray();
  finally
    LList.Free();
  end;
end;

function TPCDebugRuntime.Children(const ARef: Integer): TArray<TPCDebugValue>;
var
  LSlot: TPCDebugSlot;
begin
  Result := nil;
  if (ARef < 1) or (ARef > FRefs.Count) then
    Exit;
  for LSlot in DoChildren(FRefs[ARef - 1]) do
    Result := Result + [DoValue(LSlot)];
end;

{ TPCDebugRuntime: evaluate }

function TPCDebugRuntime.DoNamedSlot(const AFrameId: Integer; const ADisplayName: string;
  out ASlot: TPCDebugSlot): Boolean;
var
  LSlot: TPCDebugSlot;
begin
  // The scope Variables shows: locals (innermost first), params (self
  // included), the module's globals
  for LSlot in DoLocalSlots(AFrameId) do
    if LSlot.DisplayName = ADisplayName then
    begin
      ASlot := LSlot;
      Exit(True);
    end;
  for LSlot in DoParamSlots(AFrameId) do
    if LSlot.DisplayName = ADisplayName then
    begin
      ASlot := LSlot;
      Exit(True);
    end;
  for LSlot in DoGlobalSlots(AFrameId) do
    if LSlot.DisplayName = ADisplayName then
    begin
      ASlot := LSlot;
      Exit(True);
    end;
  ASlot := Default(TPCDebugSlot);
  Result := False;
end;

function TPCDebugRuntime.DoMemberSlot(const ASlot: TPCDebugSlot; const AMemberName: string;
  out AChild: TPCDebugSlot): Boolean;
var
  LChild: TPCDebugSlot;
begin
  // A member of the record itself, else of its parent part (inherited)
  for LChild in DoChildren(ASlot) do
    if (not LChild.IsBasePart) and (LChild.DisplayName = AMemberName) then
    begin
      AChild := LChild;
      Exit(True);
    end;
  for LChild in DoChildren(ASlot) do
    if LChild.IsBasePart and DoMemberSlot(LChild, AMemberName, AChild) then
      Exit(True);
  AChild := Default(TPCDebugSlot);
  Result := False;
end;

function TPCDebugRuntime.DoDerefSlot(const ASlot: TPCDebugSlot; out AChild: TPCDebugSlot): Boolean;
var
  LChild: TPCDebugSlot;
begin
  // A pointer's only child is its target
  for LChild in DoChildren(ASlot) do
    if LChild.DisplayName = PC_DBG_DEREF_NAME then
    begin
      AChild := LChild;
      Exit(True);
    end;
  AChild := Default(TPCDebugSlot);
  Result := False;
end;

function TPCDebugRuntime.DoIndexSlot(const ASlot: TPCDebugSlot; const AIndex: Int64;
  out AChild: TPCDebugSlot): Boolean;
var
  LType: TPCTypeExpr;
  LFirst: UInt64;
  LCount: Int64;
  LElementType: Cardinal;
  LElementSize: UInt64;
  LLow: Int64;
  LPdb: TPCDebugType;
  LElement: TPCDebugType;
begin
  // An element by its index (the array's own bounds, not the C++ offset)
  Result := False;
  AChild := Default(TPCDebugSlot);
  LType := nil;
  if ASlot.AstType <> nil then
    LType := ASlot.AstType.Canon();
  if LType is TPCArrayType then
  begin
    if (not DoArrayLayout(ASlot, TPCArrayType(LType), LFirst, LCount, LElementType, LElementSize, LLow)) or
      (AIndex < LLow) or (AIndex - LLow >= LCount) then
      Exit;
    AChild := DoChildSlot(ASlot, '[' + IntToStr(AIndex) + ']', TPCArrayType(LType).ElementType, LElementType,
      LFirst + UInt64(AIndex - LLow) * LElementSize);
    Exit(True);
  end;
  if (LType = nil) and DoPdbType(ASlot.ModuleBase, ASlot.TypeIndex, LPdb) and (LPdb.Tag = dttArray) and
    DoPdbType(ASlot.ModuleBase, LPdb.ElementType, LElement) and (AIndex >= 0) and (AIndex < LPdb.Count) then
  begin
    AChild := DoChildSlot(ASlot, '[' + IntToStr(AIndex) + ']', nil, LPdb.ElementType,
      ASlot.Address + UInt64(AIndex) * LElement.Length);
    Exit(True);
  end;
end;

function TPCDebugRuntime.DoEvaluate(const AFrameId: Integer; const AText: string; out ASlot: TPCDebugSlot;
  out AProblem: string): Boolean;
var
  LErrors: TErrors;
  LLexer: TPCLexer;
  LStream: TPCTokenStream;
  LTokens: TList<TPCToken>;
  LIndex: Integer;
  LToken: TPCToken;
  LChild: TPCDebugSlot;
  LNegative: Boolean;
  LValue: Int64;
  LPath: string;
begin
  // A designator (BNF postfix expr without calls): name or self, then
  // '.' / '->' member, '[' integer ']', '^'. Lexed by the real lexer; no
  // C++ evaluation, no side effects
  Result := False;
  ASlot := Default(TPCDebugSlot);
  AProblem := Format(RSDbgEvalUnsupported, [AText]);
  LErrors := TErrors.Create();
  LLexer := TPCLexer.Create();
  LStream := TPCTokenStream.Create();
  LTokens := TList<TPCToken>.Create();
  try
    LLexer.SetErrors(LErrors);
    LStream.SetErrors(LErrors);
    if (not LLexer.TokenizeBytes(TEncoding.UTF8.GetBytes(AText), PC_DBG_EVAL_FILENAME, LStream)) or
      LErrors.HasErrors() then
      Exit;
    for LIndex := 0 to LStream.Count() - 1 do
      if LStream.TokenAt(LIndex).Kind <> tkEOF then
        LTokens.Add(LStream.TokenAt(LIndex));
    if LTokens.Count = 0 then
      Exit;

    // The head: a variable visible in the frame, or self
    LToken := LTokens[0];
    if LToken.Kind = tkKwSelf then
      LPath := PC_DBG_SELF_NAME
    else if LToken.Kind = tkIdentifier then
      LPath := LToken.Text
    else
      Exit;
    if not DoNamedSlot(AFrameId, LPath, ASlot) then
    begin
      AProblem := Format(RSDbgEvalUnknownName, [LPath]);
      Exit;
    end;

    LIndex := 1;
    while LIndex < LTokens.Count do
    begin
      LToken := LTokens[LIndex];
      if (LToken.Kind = tkDot) or (LToken.Kind = tkMinusGreater) then
      begin
        // member name = identifier (any keyword is a name here, BNF :496)
        if (LIndex + 1 >= LTokens.Count) or (LTokens[LIndex + 1].Text = '') or
          (not CharInSet(LTokens[LIndex + 1].Text[1], ['A'..'Z', 'a'..'z', '_'])) then
          Exit;
        if LToken.Kind = tkMinusGreater then
        begin
          if not DoDerefSlot(ASlot, LChild) then
          begin
            AProblem := Format(RSDbgEvalNotPointer, [LPath]);
            Exit;
          end;
          ASlot := LChild;
        end
        else if (ASlot.AstType <> nil) and (ASlot.AstType.Canon() is TPCOwnerType) and
          (TPCOwnerType(ASlot.AstType.Canon()).OwnerKind <> okWeak) then
        begin
          // PLAN-OBJECT O14 (Q2): an own / ref is used as its object, LO.X
          // (a weak's member is SM0360: it stays an error here too)
          if not DoDerefSlot(ASlot, LChild) then
          begin
            AProblem := Format(RSDbgEvalNotPointer, [LPath]);
            Exit;
          end;
          ASlot := LChild;
        end;
        if not DoMemberSlot(ASlot, LTokens[LIndex + 1].Text, LChild) then
        begin
          AProblem := Format(RSDbgEvalNoMember, [LPath, LTokens[LIndex + 1].Text]);
          Exit;
        end;
        LPath := LPath + LToken.Text + LTokens[LIndex + 1].Text;
        ASlot := LChild;
        Inc(LIndex, 2);
      end
      else if LToken.Kind = tkCaret then
      begin
        if not DoDerefSlot(ASlot, LChild) then
        begin
          AProblem := Format(RSDbgEvalNotPointer, [LPath]);
          Exit;
        end;
        LPath := LPath + '^';
        ASlot := LChild;
        Inc(LIndex);
      end
      else if LToken.Kind = tkLBracket then
      begin
        // '[' ['-'] integer ']'
        Inc(LIndex);
        LNegative := (LIndex < LTokens.Count) and (LTokens[LIndex].Kind = tkMinus);
        if LNegative then
          Inc(LIndex);
        if (LIndex + 1 >= LTokens.Count) or (LTokens[LIndex].Kind <> tkIntLiteral) or
          (not LTokens[LIndex].HasValue) or (LTokens[LIndex + 1].Kind <> tkRBracket) then
          Exit;
        LValue := Int64(LTokens[LIndex].IntValue);
        if LNegative then
          LValue := -LValue;
        if not DoIndexSlot(ASlot, LValue, LChild) then
        begin
          AProblem := Format(RSDbgEvalBadIndex, [LPath, LValue]);
          Exit;
        end;
        LPath := LPath + '[' + IntToStr(LValue) + ']';
        ASlot := LChild;
        Inc(LIndex, 2);
      end
      else
        Exit;
    end;
    ASlot.DisplayName := AText;
    Result := True;
  finally
    LTokens.Free();
    LStream.Free();
    LLexer.Free();
    LErrors.Free();
  end;
end;

function TPCDebugRuntime.Evaluate(const AFrameId: Integer; const AText: string; out AValue: TPCDebugValue): Boolean;
var
  LSlot: TPCDebugSlot;
  LProblem: string;
begin
  // Watch and hover: nothing is reported, the value says what went wrong
  AValue := Default(TPCDebugValue);
  AValue.DisplayName := AText;
  if not DoFrameValid(AFrameId) then
  begin
    AValue.ValueText := Format(RSDbgEvalUnknownName, [AText]);
    Exit(False);
  end;
  if not DoEvaluate(AFrameId, AText.Trim(), LSlot, LProblem) then
  begin
    AValue.ValueText := LProblem;
    Exit(False);
  end;
  AValue := DoValue(LSlot);
  Result := AValue.IsReadable;
end;

end.
