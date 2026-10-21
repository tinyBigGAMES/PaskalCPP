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
  PaskalCPP.Common - Shared types and the token vocabulary

  Central definitions shared across all compiler units: token categories,
  token kinds, token origins, literal facts, the TPCToken record, the
  PaskalCPP and C++23 registration tables, the shared-token list, the
  parser-split piece table, the build directive vocabulary
  (PC_BUILD_DIRECTIVES, PC_DIRECTIVE_VALUES, PC_MESSAGE_SEVERITIES),
  the integer suffix vocabulary (PC_INT_SUFFIXES), and
  TPCVocabulary, which builds the lookup maps
  and runs the startup check (research\cppmix\token-vocab.md).
  It also holds TPCTargetTriple and the probed target data model
  (research\cppmix\filter.md).
  TPCCString decodes plain narrow string literals exactly as clang does
  (research\cppmix\cstring-decode.md).

  Dependencies: StdApp.Base (TBaseObject, TErrors, TSourceRange),
    StdApp.Resources (RSCom*), PaskalCPP.UnicodeNames (TPCUnicodeNames, generated)
  Notes: Do NOT add System.TypInfo to uses -- TTypeKind's tk* values collide.
===============================================================================}

unit PaskalCPP.Common;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base;

const
  { PC_MAJOR_VERSION }
  // PaskalCPP's version: the one place it is written (pcppdev stamps it on
  // the editor and its package.json)
  PC_MAJOR_VERSION = 0;
  { PC_MINOR_VERSION }
  PC_MINOR_VERSION = 2;
  { PC_PATCH_VERSION }
  PC_PATCH_VERSION = 0;
  { PC_VERSION }
  PC_VERSION = (PC_MAJOR_VERSION * 10000) + (PC_MINOR_VERSION * 100) + PC_PATCH_VERSION;
  { PC_VERSION_STR }
  PC_VERSION_STR = '0.2.0';

  { PC_SRC_EXT }
  PC_SRC_EXT = 'pcpp';

  { PC_STD_MODULE_PATH }
  // The standard library's module folder: the compiler adds it as its first
  // module path when it is created (TPCCompiler.Create -> AddModulePath)
  PC_STD_MODULE_PATH = '$P:res/libs/std';

  { PC_RESERVED_PREFIX }
  // The compiler's own C++ names start so (pcpp_parent, pcpp_m_<M>,
  // pcpp_flow_<n> ...): a PaskalCPP declaration's name never does (SM0017,
  // PLAN-RECORDS M11; case-sensitive, as C++ names are)
  PC_RESERVED_PREFIX = 'pcpp_';

  { PC_RESDATA_RESERVED_PREFIX }
  // The compiler's own @addresdata entries (the Linux window icon) use keys
  // that start so: a key a program adds never does (SM0120, PLAN-RESDATA;
  // case-sensitive, as every key is)
  PC_RESDATA_RESERVED_PREFIX = 'pcpp/';
  { PC_RESDATA_EXEICON_KEY }
  // PLAN-RESDATA A6: a non-Windows exe's @exeicon, built in under this key
  // (TPCModule.ExeIconEntry): width, height (uint32, little-endian), then
  // RGBA pixels, rows top to bottom (PaskalCPP.Icon)
  PC_RESDATA_EXEICON_KEY = PC_RESDATA_RESERVED_PREFIX + 'exeicon';
  { PC_RESDATA_EXEICON_FILE }
  // The decoded entry the Compiler writes beside the generated sources; the
  // entry's #embed names it relative to them
  PC_RESDATA_EXEICON_FILE = 'pcpp_exeicon.rgba';

  { PC_RESDATA_KEY_SYMBOL_PREFIX }
  // PLAN-RESDATA A4b: every @addresdata entry also defines a C symbol named
  // this prefix + its key's UTF-8 bytes in lowercase hex (TPCResDataKey), so a
  // second holder of the key in one linked binary (a lib built apart) is the
  // linker's duplicate symbol, which the Compiler reports as SM0121
  PC_RESDATA_KEY_SYMBOL_PREFIX = 'pcpp_rk_';

  { PC_RESDATA_UNIT_NAME }
  // PLAN-RESDATA A5 (WHAT 4): the std unit that reads the entries back, and
  // the routines whose literal key SEM checks against the build's
  // @addresdata keys (SM0122: a key no directive adds)
  PC_RESDATA_UNIT_NAME = 'ResData';

  { PC_RESDATA_UNIT_FILE }
  PC_RESDATA_UNIT_FILE = PC_STD_MODULE_PATH + '/ResData.pcpp';

  { PC_RESDATA_FIND }
  PC_RESDATA_FIND = 'FindResData';

  { PC_RESDATA_HAS }
  PC_RESDATA_HAS = 'HasResData';

  { PC_ERR_VOC_001 }
  // A spelling is registered by both tables but is not in the shared list
  PC_ERR_VOC_001 = 'VC0001';

  { PC_ERR_VOC_002 }
  // A shared-list entry is not registered by both tables (stale list)
  PC_ERR_VOC_002 = 'VC0002';

  { PC_ERR_VOC_003 }
  // A shared spelling has different kinds in the two tables
  PC_ERR_VOC_003 = 'VC0003';

  { PC_ERR_VOC_004 }
  // A spelling is registered twice in one table or in the shared list
  PC_ERR_VOC_004 = 'VC0004';

  { PC_MAX_OPERATOR_LENGTH }
  // Longest operator spelling in either table (<<= >>= <=> ...)
  PC_MAX_OPERATOR_LENGTH = 3;

type

  { TPCTokenCategory }
  TPCTokenCategory = (
    tcKeyword,        // PaskalCPP reserved word
    tcCppKeyword,     // C++23 reserved word PaskalCPP does not register
    tcPrimitive,      // PaskalCPP built-in type name (int32, string, ...)
    tcOperator,       // operator spelling
    tcDelimiter,      // structural punctuation
    tcLiteral,        // number, string or char literal
    tcIdentifier,     // name
    tcDirective,      // @name
    tcPreprocessor,   // one whole # line
    tcVerbatim,       // the text of a cppstart block (tkRawBlock)
    tcSpecial         // EOF, unknown
  );

  { TPCTokenOrigin }
  // Which table produced the token; toNone for names, literals and specials
  TPCTokenOrigin = (
    toNone,
    toPaskal,
    toCpp,
    toShared
  );

  { TPCSharedResolution }
  TPCSharedResolution = (
    srSame,           // one token, same meaning in PaskalCPP and C++
    srPaskalWins      // PaskalCPP meaning only; the C++ meaning is unreachable
  );

  { TPCLiteralBase }
  TPCLiteralBase = (
    lbNone,
    lbDecimal,
    lbHex,
    lbBinary,
    lbOctal
  );

  { TPCLiteralPrefix }
  // Encoding prefix of a string or char literal, named by spelling
  TPCLiteralPrefix = (
    lpNone,
    lpU8,             // u8
    lpLowerU,         // u
    lpUpperU,         // U
    lpUpperL          // L
  );

  { TPCTokenKind }
  // One enum for PaskalCPP and C++. Keyword kinds are tkKw<spelling>
  // (CLAUDE.md forbids keyword-named values); operators are named by
  // spelling, never by role (IDENTITY RULE).
  TPCTokenKind = (
    // -- Specials, names, literals --
    tkEOF,
    tkUnknown,
    tkIdentifier,
    tkDirective,
    tkIntLiteral,
    tkFloatLiteral,
    tkStringLiteral,
    tkCharLiteral,
    tkCppPreprocessor,
    tkRawBlock,

    // -- PaskalCPP keywords (shared ones included) --
    tkKwModule,
    tkKwExe,
    tkKwDll,
    tkKwLib,
    tkKwUnit,
    tkKwImport,
    tkKwInitialize,
    tkKwFinalize,
    tkKwBegin,
    tkKwEnd,
    tkKwVar,
    tkKwConst,
    tkKwType,
    tkKwRoutine,
    tkKwForward,
    tkKwMethod,
    tkKwExported,
    tkKwClink,
    tkKwCpplink,
    tkKwExternal,
    tkKwRecord,
    tkKwObject,
    tkKwOverlay,
    tkKwChoices,
    tkKwArray,
    tkKwOf,
    tkKwPtr,
    tkKwTo,
    tkKwSet,
    tkKwPacked,
    tkKwAlign,
    tkKwIf,
    tkKwThen,
    tkKwElse,
    tkKwWhile,
    tkKwDo,
    tkKwFor,
    tkKwDownto,
    tkKwRepeat,
    tkKwUntil,
    tkKwMatch,
    tkKwGuard,
    tkKwExcept,
    tkKwFinally,
    tkKwReturn,
    tkKwLeave,
    tkKwSkip,
    tkKwOr,
    tkKwAnd,
    tkKwXor,
    tkKwNot,
    tkKwIn,
    tkKwShl,
    tkKwShr,
    tkKwDiv,
    tkKwMod,
    tkKwAddress,
    tkKwTrue,
    tkKwFalse,
    tkKwNil,
    tkKwSelf,
    tkKwParent,
    tkKwVarargs,
    tkKwTest,
    tkKwCpp,
    tkKwCppstart,
    tkKwCppend,

    // -- PaskalCPP primitives (bool and char are shared with C++) --
    tkKwInt8,
    tkKwInt16,
    tkKwInt32,
    tkKwInt64,
    tkKwUint8,
    tkKwUint16,
    tkKwUint32,
    tkKwUint64,
    tkKwFloat32,
    tkKwFloat64,
    tkKwBool,
    tkKwChar,
    tkKwWchar,
    tkKwString,
    tkKwWstring,

    // -- C++23 reserved words PaskalCPP does not register --
    tkKwAlignas,
    tkKwAlignof,
    tkKwAnd_eq,
    tkKwAsm,
    tkKwAuto,
    tkKwBitand,
    tkKwBitor,
    tkKwBreak,
    tkKwCase,
    tkKwCatch,
    tkKwChar8_t,
    tkKwChar16_t,
    tkKwChar32_t,
    tkKwClass,
    tkKwCompl,
    tkKwConcept,
    tkKwConsteval,
    tkKwConstexpr,
    tkKwConstinit,
    tkKwConst_cast,
    tkKwContinue,
    tkKwCo_await,
    tkKwCo_return,
    tkKwCo_yield,
    tkKwDecltype,
    tkKwDefault,
    tkKwDelete,
    tkKwDouble,
    tkKwDynamic_cast,
    tkKwEnum,
    tkKwExplicit,
    tkKwExport,
    tkKwExtern,
    tkKwFloat,
    tkKwFriend,
    tkKwGoto,
    tkKwInline,
    tkKwInt,
    tkKwLong,
    tkKwMutable,
    tkKwNamespace,
    tkKwNew,
    tkKwNoexcept,
    tkKwNot_eq,
    tkKwNullptr,
    tkKwOperator,
    tkKwOr_eq,
    tkKwPrivate,
    tkKwProtected,
    tkKwPublic,
    tkKwRegister,
    tkKwReinterpret_cast,
    tkKwRequires,
    tkKwShort,
    tkKwSigned,
    tkKwSizeof,
    tkKwStatic,
    tkKwStatic_assert,
    tkKwStatic_cast,
    tkKwStruct,
    tkKwSwitch,
    tkKwTemplate,
    tkKwThis,
    tkKwThread_local,
    tkKwThrow,
    tkKwTry,
    tkKwTypedef,
    tkKwTypeid,
    tkKwTypename,
    tkKwUnion,
    tkKwUnsigned,
    tkKwUsing,
    tkKwVirtual,
    tkKwVoid,
    tkKwVolatile,
    tkKwWchar_t,
    tkKwXor_eq,

    // -- Operators and delimiters, named by spelling --
    tkPlus,                   // +
    tkMinus,                  // -
    tkStar,                   // *
    tkSlash,                  // /
    tkPercent,                // %
    tkEqual,                  // =
    tkLessGreater,            // <>   (PaskalCPP only)
    tkLess,                   // <
    tkGreater,                // >
    tkLessEqual,              // <=
    tkGreaterEqual,           // >=
    tkColonEqual,             // :=   (PaskalCPP only)
    tkPlusEqual,              // +=
    tkMinusEqual,             // -=
    tkStarEqual,              // *=
    tkSlashEqual,             // /=
    tkPercentEqual,           // %=
    tkAmpEqual,               // &=
    tkPipeEqual,              // |=
    tkLessLessEqual,          // <<=
    tkGreaterGreaterEqual,    // >>=
    tkCaret,                  // ^
    tkPipe,                   // |
    tkAmp,                    // &
    tkTilde,                  // ~
    tkBang,                   // !
    tkAmpAmp,                 // &&
    tkPipePipe,               // ||
    tkPlusPlus,               // ++
    tkMinusMinus,             // --
    tkLessLess,               // <<
    tkGreaterGreater,         // >>
    tkMinusGreater,           // ->
    tkColonColon,             // ::
    tkColon,                  // :
    tkDot,                    // .
    tkDotDot,                 // ..   (PaskalCPP only)
    tkDotDotDot,              // ...
    tkComma,                  // ,
    tkSemicolon,              // ;
    tkLParen,                 // (
    tkRParen,                 // )
    tkLBracket,               // [
    tkRBracket,               // ]
    tkEqualEqual,             // ==   (C++ only)
    tkBangEqual,              // !=   (C++ only)
    tkLessEqualGreater,       // <=>  (C++ only)
    tkQuestion,               // ?    (C++ only)
    tkLBrace,                 // {    (C++ only)
    tkRBrace                  // }    (C++ only)
  );

  { TPCToken }
  // One token. Text is the exact source slice [Range.StartByteOffset,
  // Range.EndByteOffset), never case-folded or rebuilt; it may contain line
  // splices, so every comparison reads Spelling. Spelling is Text with every
  // splice removed (a raw string keeps its delimiter, body and closer
  // physical); always set, the same string as Text when there is no splice.
  // TriviaStart..StartByteOffset is the leading whitespace/comments.
  // EndLine/EndColumn name the LAST byte (inclusive); columns count bytes,
  // as clang does.
  TPCToken = record
    Kind: TPCTokenKind;
    Category: TPCTokenCategory;
    Origin: TPCTokenOrigin;
    Range: TSourceRange;
    TriviaStart: UInt64;
    Text: string;
    Spelling: string;
    LiteralBase: TPCLiteralBase;      // numbers only
    LiteralPrefix: TPCLiteralPrefix;  // strings and chars only
    IsRawString: Boolean;             // R"d(...)d"
    Suffix: string;                   // literal suffix, splice-free spelling ('' = none)
    IsUserDefined: Boolean;           // suffix is not a standard one: opaque C++ UDL
    HasValue: Boolean;                // IntValue / FloatValue is valid
    IntValue: UInt64;
    FloatValue: Double;

    procedure Clear();
    function ByteLength(): UInt64;
  end;

  { TPCTokenRow }
  // One registration-table row
  TPCTokenRow = record
    Text: string;
    Kind: TPCTokenKind;
    Category: TPCTokenCategory;
  end;

  { TPCSharedRow }
  // One shared-token list row: a spelling both tables register
  TPCSharedRow = record
    Text: string;
    Resolution: TPCSharedResolution;
  end;

  { TPCSplitPiece }
  // A spelling a parser-split can produce, with its kind
  TPCSplitPiece = record
    Text: string;
    Kind: TPCTokenKind;
  end;

  { TPCVocabEntry }
  // A built vocabulary entry. Resolution is meaningful only for toShared.
  TPCVocabEntry = record
    Text: string;
    Kind: TPCTokenKind;
    Category: TPCTokenCategory;
    Origin: TPCTokenOrigin;
    Resolution: TPCSharedResolution;
  end;

  { TPCTripleStatus }
  // Result of TPCTargetTriple.Parse (research\cppmix\filter.md); tsUnsupported = a
  // well-formed triple that is not one of PC_DATA_MODELS (BNF.md sec 2)
  TPCTripleStatus = (tsOk, tsBadShape, tsUnsupported);

  { TPCDataModelRow }
  // One SUPPORTED target and its full data model (research\cppmix\sem\datamodel.md
  // Q3, probed with the bundled zig c++ -dM -E). Target is the zig triple
  // (arch-os-abi), the row's key. The test Conditionals.datamodel_witness checks
  // every row against the bundled clang, so a toolchain change fails there
  TPCDataModelRow = record
    Target: string;
    IntBits: Integer;
    LongBits: Integer;
    LongLongBits: Integer;
    PointerBits: Integer;
    SizeTBits: Integer;
    WCharBits: Integer;
    FloatBits: Integer;
    DoubleBits: Integer;
    IsCharSigned: Boolean;
    IsWCharSigned: Boolean;
  end;

  { TPCAlignKind }
  // A C++ type the emitter writes, as far as its alignment goes
  // (research\paskal-errors\r-b-align.md P7): the builtins (BNF sec 2, the
  // emitter's DoBuiltinText), a pointer (ptr, ptr to T, an address), a
  // routine type (std::add_pointer_t<R(P)>), a dynamic array (std::vector<T>)
  // and a set (::pcpp::Set<T, LOW, HIGH>); akChar16 = a wchar bitfield, which
  // the emitter writes char16_t on every target (F25, TPCField.IsWCharBitfield)
  TPCAlignKind = (akInt8, akInt16, akInt32, akInt64, akUInt8, akUInt16, akUInt32, akUInt64,
    akFloat32, akFloat64, akBool, akChar, akWChar, akChar16, akString, akWString, akPointer,
    akRoutine, akDynArray, akSet);

  { TPCAlignModelRow }
  // One SUPPORTED target's alignment of every TPCAlignKind, in bytes (r-b P7,
  // probed with the bundled zig). The test Conditionals.align_witness compiles
  // a static_assert per kind for every row's target, so a toolchain or
  // runtime change that moves one fails there
  TPCAlignModelRow = record
    Target: string;
    Aligns: array[TPCAlignKind] of Integer;
  end;

  { TPCTargetTriple }
  // An LLVM triple arch-vendor-os-env, exact case (BNF.md sec 2). Arch = '' means not set.
  // Parse accepts only a supported target (a PC_DATA_MODELS row, canonical vendor);
  // the data model accessors read that row and give 0 on an empty triple
  TPCTargetTriple = record
    Arch: string;
    Vendor: string;
    OS: string;
    Env: string;

    function IsEmpty(): Boolean;
    function IsWindows(): Boolean;
    function ToLLVM(): string;
    function ToZig(): string;
    function IntBits(): Integer;
    function LongBits(): Integer;
    function LongLongBits(): Integer;
    function PointerBits(): Integer;
    function SizeTBits(): Integer;
    function WCharBits(): Integer;
    function FloatBits(): Integer;
    function DoubleBits(): Integer;
    function IsCharSigned(): Boolean;
    function IsWCharSigned(): Boolean;
    // The alignment in bytes of a kind on this target (PC_ALIGN_MODELS); 0
    // on an empty triple
    function AlignOf(const AKind: TPCAlignKind): Integer;
    class function Parse(const AText: string; out ATriple: TPCTargetTriple): TPCTripleStatus; static;
    class function DefaultTriple(): TPCTargetTriple; static;
    // The supported targets, comma separated, for messages
    class function SupportedTargetsText(): string; static;
  end;

  { TPCCStringStatus }
  // Result of TPCCString.Decode: csWarning = clang would warn (value kept),
  // csError = clang would reject it, or the value is not valid UTF-8
  TPCCStringStatus = (csOk, csWarning, csError);

  { TPCSpellRun }
  // One run of a decoded string value (P-STRPOS, research\cppmix\sem\prereq-b\strpos.md):
  // the value bytes from ValueOffset on came from the token's Spelling at SpellIndex on
  // (1-based UTF-16 index). IsCopy: copied 1:1, value byte N maps to the code point the
  // bytes before it in the run belong to; not IsCopy: one escape, every byte of it maps
  // to the escape's '\'. Spelling space only: positions are the parser's (TPCValueRun)
  TPCSpellRun = record
    ValueOffset: Integer;
    SpellIndex: Integer;
    IsCopy: Boolean;
  end;

  { TPCCString }
  // Decodes a plain narrow string literal (tkStringLiteral, LiteralPrefix
  // lpNone, no suffix; raw allowed) into the exact bytes clang stores, read
  // as UTF-8 (research\cppmix\cstring-decode.md, cstring-names.md). Reads
  // AToken.Spelling: splices are already removed there and reported by the
  // lexer (LX0201), so Decode neither removes nor reports them. The first
  // error stops (csError, AValue = ''); warnings keep decoding and AReason
  // names the first one (csWarning). Pure: no RTL call that can raise.
  // DecodeChar gives a plain or L char literal its value with the same escape
  // engine (P-CHAR, research\cppmix\sem\pchar.md). The 4-argument Decode also
  // returns the value's spell runs (P-STRPOS), recorded in the same walk.
  TPCCString = record
  private
    class procedure DoAppendByte(var ABytes: TBytes; var ACount: Integer;
      const AByte: Byte); static;
    class procedure DoAppendCodePoint(var ABytes: TBytes; var ACount: Integer;
      const ACodePoint: Cardinal); static;
    class function DoCodePointAt(const AText: string; var AIndex: Integer): Cardinal; static;
    class function DoDigitValue(const AChar: Char; const ABase: Cardinal;
      out AValue: Cardinal): Boolean; static;
    class function DoSimpleEscapeByte(const AChar: Char): Byte; static;
    class function DoReason(const ATemplate: string; const AArg: string): string; static;
    class function DoDelimited(const AText: string; const ALast: Integer;
      var AIndex: Integer; const ABase: Cardinal; const ALimit: Cardinal;
      out AValue: Cardinal; out AOverflow: Boolean; out AReason: string): Boolean; static;
    class function DoEscapeValue(const AText: string; const ALast: Integer;
      var AIndex: Integer; const ANumericLimit: Cardinal; out AValue: Cardinal;
      out AIsNumeric: Boolean; var AWarning: string; out AReason: string): Boolean; static;
    class function DoDecodeEscape(const AText: string; const ALast: Integer;
      var AIndex: Integer; var ABytes: TBytes; var ACount: Integer;
      var AWarning: string; out AReason: string): Boolean; static;
    class procedure DoAddRun(var ARuns: TArray<TPCSpellRun>; var ARunCount: Integer;
      const AValueOffset: Integer; const ASpellIndex: Integer;
      const AIsCopy: Boolean); static;
    class function DoDecodeNormal(const AText: string; var ABytes: TBytes;
      var ACount: Integer; var ARuns: TArray<TPCSpellRun>; var ARunCount: Integer;
      out AWarning: string; out AReason: string): Boolean; static;
    class function DoDecodeRaw(const AText: string; var ABytes: TBytes;
      var ACount: Integer; var ARuns: TArray<TPCSpellRun>; var ARunCount: Integer;
      out AReason: string): Boolean; static;
    class function DoBytesToText(const ABytes: TBytes; const ACount: Integer;
      out AText: string): Boolean; static;
  public
    class function Decode(const AToken: TPCToken; out AValue: string;
      out AReason: string): TPCCStringStatus; overload; static;
    // As Decode, plus the value's spell runs in value order (csError: nil;
    // csWarning: kept with the value)
    class function Decode(const AToken: TPCToken; out AValue: string;
      out AReason: string; out ARuns: TArray<TPCSpellRun>): TPCCStringStatus; overload; static;
    // A char literal (tkCharLiteral, LiteralPrefix lpNone or lpUpperL, no
    // suffix) -> the value clang gives it. Narrow: one element = its byte
    // (0..255, the char's signedness is SEM's); several = a multi-char
    // literal (AIsMultiChar), each byte shifted in, kept to 32 bits. L: exactly
    // one element, its code point or escape value (fit to the target's wchar
    // is SEM's). csWarning: clang warns (value kept, AReason names it).
    class function DecodeChar(const AToken: TPCToken; out AValue: UInt64;
      out AIsMultiChar: Boolean; out AReason: string): TPCCStringStatus; static;
    // True = the character after a '\' starts an escape the decoder knows;
    // False = an unknown escape (the character itself, a warning). The same
    // set as DoEscapeValue's cases (witness: CString.escape_start_parity)
    class function IsEscapeStart(const AChar: Char): Boolean; static;
    // A plain literal's text as C++ is given it (F65): every unknown escape's
    // '\' dropped, which is the value both C++ and Decode give it, so clang
    // never judges a mistake the parser already reported; splices are kept
    // as written (a '\' before optional space / tab / FF / VT and a newline)
    class function CppSpelling(const AText: string): string; static;
  end;

  { TPCCppJumpKind }
  // The C++ jump kinds a cppstart block in a body can leave it by (O-S6b,
  // research\cppmix\sem\prereq-b\jump.md D-J4: goto / co_* / throw not recorded)
  TPCCppJumpKind = (cjReturn, cjBreak, cjContinue);

  { TPCCppJump }
  // One C++ jump of a cppstart block in a body that leaves the block
  // (TPCCppJumpFinder, PaskalCPP.CppJumps); Range = the jump word in the .pcpp file
  TPCCppJump = record
    Kind: TPCCppJumpKind;
    Range: TSourceRange;
  end;

  { TPCFloatFormat }
  // The binary format a floating literal's value is rounded to: binary64
  // (no suffix, C++ double) or binary32 (f / F, C++ float); lexer.md Numbers
  TPCFloatFormat = (ffBinary64, ffBinary32);

  { TPCFloatStatus }
  // Result of TPCFloatDecoder.Decode: fsOverflow = the value rounded to the
  // format is past its largest finite value; fsMalformed = not a floating
  // literal's numeric part (the lexer checks the shape first)
  TPCFloatStatus = (fsOk, fsOverflow, fsMalformed);

  { TPCFloatDecoder }
  // Exact decoder for the numeric part of a C++ floating literal, decimal
  // (1.5e-3, .5, 1.) or hex (0x1.8p3), digit separators already removed and
  // no suffix (research\cppmix\sem\pfloat.md). The value is the literal's
  // exact value rounded ONCE to the format, round to nearest, ties to even,
  // denormals included, as clang does; an underflow gives 0 or a denormal
  // (clang only warns). Exact big-integer arithmetic, no RTL conversion.
  // Pure: no RTL call that can raise.
  TPCFloatDecoder = record
  private type
    { TPCBigNat }
    // Unsigned big integer: little-endian 32-bit limbs, no high zero limbs
    // (zero = empty array)
    TPCBigNat = TArray<Cardinal>;
  private
    class procedure DoTrim(var AValue: TPCBigNat); static;
    class procedure DoMulAdd(var AValue: TPCBigNat; const AMul: Cardinal;
      const AAdd: Cardinal); static;
    class function DoBitLength(const AValue: TPCBigNat): Int64; static;
    class function DoShl(const AValue: TPCBigNat; const ABits: Int64): TPCBigNat; static;
    class function DoCompare(const ALeft: TPCBigNat; const ARight: TPCBigNat): Integer; static;
    class procedure DoSub(var ALeft: TPCBigNat; const ARight: TPCBigNat); static;
    class function DoPow10(const AExp: Int64): TPCBigNat; static;
    class function DoBitLength64(const AValue: UInt64): Integer; static;
    class function DoMakeDouble(const ASignificand: UInt64;
      const AScale: Int64): Double; static;
    class function DoRound(const ANum: TPCBigNat; const ADen: TPCBigNat;
      const AFormat: TPCFloatFormat; out AValue: Double): TPCFloatStatus; static;
  public
    class function Decode(const ANumeric: string; const AFormat: TPCFloatFormat;
      out AValue: Double): TPCFloatStatus; static;
  end;

  { TPCLibraryName }
  // A link library as `@linklibrary` and an `external` clause name it (BNF.md
  // sec 2, user 2026-10-06): a NAME the system linker finds (m, user32), never
  // a file. The one check of that rule (research\cppmix\sem\decls.md Q25a).
  // Pure: no RTL call that can raise
  TPCLibraryName = record
  public
    // False for '', a blank or control character, a path separator or drive
    // colon, or a library file's suffix (.a .lib .so .dll, any case)
    class function IsName(const AText: string): Boolean; static;
  end;

  { TPCResDataKey }
  // A built-in data key <-> its key symbol (PC_RESDATA_KEY_SYMBOL_PREFIX):
  // the emitter writes the symbol, the Compiler reads a linker's duplicate
  // symbol back to the key. Exact: the key's UTF-8 bytes, two lowercase hex
  // digits each, no hash. Pure: no RTL call that can raise
  TPCResDataKey = record
  public
    class function SymbolOf(const AKey: string): string; static;
    // False = not a key symbol (another prefix, odd length, a non-hex digit,
    // bytes that are no UTF-8)
    class function TryKeyOf(const ASymbol: string; out AKey: string): Boolean; static;
  end;

  { TPCSourceLanguage }
  // How a toolchain source file compiles: the language clang picks from its
  // file name. ZigBuild partitions sources by it (each group its own flags),
  // so C libraries, C++23, assembly and LLVM IR coexist in one artifact
  TPCSourceLanguage = (slC, slCpp, slAsm, slLLVMIR);

  { TPCSourceExtRow }
  TPCSourceExtRow = record
    ExtText: string;
    Language: TPCSourceLanguage;
  end;

  { TPCSourceFiles }
  // The one rule of which files the toolchain compiles (PC_SOURCE_EXTS):
  // ZigBuild's source gate and SEM's @addsourcefile check read it. Pure
  TPCSourceFiles = record
  public
    // AFilename's extension, exact case, is a source file's; False = not one
    // (a header, a name clang would take as linker input)
    class function LanguageOf(const AFilename: string; out ALanguage: TPCSourceLanguage): Boolean; static;
    // Every accepted extension, space separated, as a message lists them
    class function ExtensionsText(): string; static;
  end;

  { TPCBuildDirective }
  // One build directive of BNF.md sec 2, in PC_BUILD_DIRECTIVES order: the index of that table
  TPCBuildDirective = (bdOptimize, bdSubsystem, bdTarget, bdAddVerInfo, bdUnitTestMode,
    bdVIMajor, bdVIMinor, bdVIPatch, bdVIProductName, bdVIDescription, bdVIFileName,
    bdVICompanyName, bdVICopyright, bdExeIcon, bdCopyDLL, bdLinkLibrary, bdAddLibraryPath,
    bdAddModulePath, bdAddIncludePath, bdAddSourceFile, bdCppDefine, bdCppUndef, bdBreakpoint, bdMessage,
    bdOutputPath, bdAddResData);

  { TPCDirectiveShape }
  // The argument grammar of one build directive (BNF.md sec 2);
  // dsOneOrTwoCStrings = a string literal, then optionally a second one;
  // dsKeyAndPath = a key string literal, then a path string literal (both
  // required; only the second is a path: IsPath applies to it alone)
  TPCDirectiveShape = (dsNone, dsIdentifier, dsInteger, dsCString, dsOneOrTwoCStrings, dsSeverityText,
    dsKeyAndPath);

  { TPCDirectiveRow }
  // One build directive: name without the @, argument shape and rules.
  // IsPath = the value resolves through TUtils.ResolvePath; IsMainOnly = an
  // error in a unit (BNF.md sec 2); IsFilterChecked = the conditional filter
  // owns its checks (@target), so the parser reports none of its argument errors;
  // IsLibName = the value is a library NAME, checked by TPCLibraryName.IsName
  // (BNF.md sec 2, user 2026-10-06; never IsPath);
  // IsStatement = also a statement wherever one stands (BNF.md sec 5);
  // IsSingle = given at most once per module (BNF.md sec 2: the list directives
  // accumulate)
  TPCDirectiveRow = record
    DirectiveName: string;
    Shape: TPCDirectiveShape;
    IsPath: Boolean;
    IsMainOnly: Boolean;
    IsFilterChecked: Boolean;
    IsLibName: Boolean;
    IsStatement: Boolean;
    IsSingle: Boolean;
  end;

  { TPCDirectiveValue }
  // One accepted value of an identifier directive (BNF.md sec 2)
  TPCDirectiveValue = record
    Directive: TPCBuildDirective;
    ValueText: string;
  end;

  { TPCRetiredValue }
  // A directive value spelling no longer accepted, and the spelling that
  // replaced it (the hint every report of it names)
  TPCRetiredValue = record
    Directive: TPCBuildDirective;
    RetiredText: string;
    CurrentText: string;
  end;

  { TPCIntSuffixWidth }
  // The C++ integer type a standard suffix names (C++23 [lex.icon]): int, long, long long, size
  TPCIntSuffixWidth = (iwInt, iwLong, iwLongLong, iwSize);

  { TPCIntSuffixRow }
  // One standard integer suffix spelling and its meaning (u alone = iwInt, unsigned).
  // No suffix is Default(TPCIntSuffixRow): signed, iwInt
  TPCIntSuffixRow = record
    SuffixText: string;
    IsUnsigned: Boolean;
    SuffixWidth: TPCIntSuffixWidth;
    // Whether a literal with this suffix may take an unsigned type (C++23
    // [lex.icon] table 8): a decimal literal only with a u suffix, a hex,
    // octal or binary literal always. False = its value must fit int64, else
    // no type holds it (LX0006); the lexer and SEM read this one rule
    function MayBeUnsigned(const AIsDecimal: Boolean): Boolean;
  end;

  { TPCContextWord }
  // A word of an object type (PLAN-OBJECT H1): a word only where the grammar
  // expects it (a member of an object type, a type position, after an
  // operand), an identifier everywhere else, so C's read() / write() and a
  // variable named ref keep working. One row each in PC_CONTEXT_WORDS
  TPCContextWord = (cwInit, cwDone, cwEmbed, cwImplements, cwInterface, cwProperty, cwRead, cwWrite,
    cwHidden, cwVirtual, cwOverride, cwFinal, cwAbstract, cwCopy, cwOwn, cwRef, cwWeak, cwIs, cwAs,
    cwOperator, cwDefault);

  { TPCContextWordRow }
  // A context word's spelling (exact case, as every PaskalCPP word) and the
  // token it lexes as: tkIdentifier for a plain word; virtual, operator and
  // default stay the C++ tokens they are (PC_CPP_TOKENS)
  TPCContextWordRow = record
    WordText: string;
    Kind: TPCTokenKind;
    // AToken is this word (the caller knows the position expects it)
    function Matches(const AToken: TPCToken): Boolean;
  end;

  { TPCVocabulary }
  // Builds the word and operator maps from the registration tables and runs
  // the startup check. Wire SetErrors() before Build().
  TPCVocabulary = class(TBaseObject)
  private
    FWords: TDictionary<string, TPCVocabEntry>;
    FOperators: TDictionary<string, TPCVocabEntry>;
    FBuilt: Boolean;

    function DoMapFor(const AText: string): TDictionary<string, TPCVocabEntry>;
    function DoCollectShared(const ARows: array of TPCSharedRow;
      const AShared: TDictionary<string, TPCSharedResolution>): Boolean;
    function DoAddPaskal(const ARows: array of TPCTokenRow): Boolean;
    function DoAddCpp(const ARows: array of TPCTokenRow;
      const AShared: TDictionary<string, TPCSharedResolution>;
      const ACppSpellings: TDictionary<string, Boolean>): Boolean;
    function DoCheckShared(const ARows: array of TPCSharedRow;
      const ACppSpellings: TDictionary<string, Boolean>): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    function Build(): Boolean;
    function BuildFrom(const APaskal: array of TPCTokenRow;
      const ACpp: array of TPCTokenRow;
      const AShared: array of TPCSharedRow): Boolean;
    function IsBuilt(): Boolean;
    function FindWord(const AText: string; out AEntry: TPCVocabEntry): Boolean;
    function FindOperator(const AText: string; out AEntry: TPCVocabEntry): Boolean;

    class function IsSplittable(const AKind: TPCTokenKind): Boolean; static;
    class function FindSplitPiece(const AText: string;
      out AKind: TPCTokenKind): Boolean; static;
    // The registration row of a token kind: PC_PASKAL_TOKENS first, then
    // PC_CPP_TOKENS (a shared spelling is the same text in both). False = the
    // kind has no row (identifiers, literals, end of file)
    class function FindKindRow(const AKind: TPCTokenKind;
      out ARow: TPCTokenRow): Boolean; static;
    // A word that names a builtin type: a tcPrimitive row, or `varargs` (a
    // keyword row: the lexer and DoParsePrimary dispatch on it; BNF sec 4 makes
    // it the pack type). The one predicate for every builtin-word decision (D-R3)
    class function IsBuiltinTypeWord(const AKind: TPCTokenKind): Boolean; static;
    // The build directive spelled ADirectiveName (without the @, exact case);
    // False = none, ADirective = Low(TPCBuildDirective)
    class function FindDirective(const ADirectiveName: string;
      out ADirective: TPCBuildDirective): Boolean; static;
    // AText is one of ADirective's PC_DIRECTIVE_VALUES rows (exact case)
    class function IsDirectiveValue(const ADirective: TPCBuildDirective;
      const AText: string): Boolean; static;
    // ADirective's accepted values in table order, joined by ', ' (for messages)
    class function DirectiveValuesText(const ADirective: TPCBuildDirective): string; static;
    // AText is a retired spelling of one of ADirective's values (PC_RETIRED_VALUES,
    // exact case): ACurrentText = the spelling that replaced it; False = none, ''
    class function FindRetiredValue(const ADirective: TPCBuildDirective;
      const AText: string; out ACurrentText: string): Boolean; static;
    // The standard integer suffix spelled ASuffix (exact case, PC_INT_SUFFIXES); False = none, ARow = Default
    class function FindIntSuffix(const ASuffix: string; out ARow: TPCIntSuffixRow): Boolean; static;
  end;

const
  { PC_CONTEXT_WORDS }
  // The object type's words (PLAN-OBJECT H1), in TPCContextWord order. Read
  // by the parser (TPCParser.DoIsWord), the LSP and the formatter; never
  // registered as tokens (Lexer.context_words witnesses each row's kind)
  PC_CONTEXT_WORDS: array[TPCContextWord] of TPCContextWordRow = (
    (WordText: 'init';       Kind: tkIdentifier),
    (WordText: 'done';       Kind: tkIdentifier),
    (WordText: 'embed';      Kind: tkIdentifier),
    (WordText: 'implements'; Kind: tkIdentifier),
    (WordText: 'interface';  Kind: tkIdentifier),
    (WordText: 'property';   Kind: tkIdentifier),
    (WordText: 'read';       Kind: tkIdentifier),
    (WordText: 'write';      Kind: tkIdentifier),
    (WordText: 'hidden';     Kind: tkIdentifier),
    (WordText: 'virtual';    Kind: tkKwVirtual),
    (WordText: 'override';   Kind: tkIdentifier),
    (WordText: 'final';      Kind: tkIdentifier),
    (WordText: 'abstract';   Kind: tkIdentifier),
    (WordText: 'copy';       Kind: tkIdentifier),
    (WordText: 'own';        Kind: tkIdentifier),
    (WordText: 'ref';        Kind: tkIdentifier),
    (WordText: 'weak';       Kind: tkIdentifier),
    (WordText: 'is';         Kind: tkIdentifier),
    (WordText: 'as';         Kind: tkIdentifier),
    (WordText: 'operator';   Kind: tkKwOperator),
    (WordText: 'default';    Kind: tkKwDefault)
  );

  { PC_PASKAL_TOKENS }
  // Every PaskalCPP spelling (BNF.md terminals, token-vocab.md)
  PC_PASKAL_TOKENS: array[0..125] of TPCTokenRow = (
    // keywords
    (Text: 'module';   Kind: tkKwModule;   Category: tcKeyword),
    (Text: 'exe';      Kind: tkKwExe;      Category: tcKeyword),
    (Text: 'dll';      Kind: tkKwDll;      Category: tcKeyword),
    (Text: 'lib';      Kind: tkKwLib;      Category: tcKeyword),
    (Text: 'unit';     Kind: tkKwUnit;     Category: tcKeyword),
    (Text: 'import';   Kind: tkKwImport;   Category: tcKeyword),
    (Text: 'initialize'; Kind: tkKwInitialize; Category: tcKeyword),
    (Text: 'finalize'; Kind: tkKwFinalize; Category: tcKeyword),
    (Text: 'begin';    Kind: tkKwBegin;    Category: tcKeyword),
    (Text: 'end';      Kind: tkKwEnd;      Category: tcKeyword),
    (Text: 'var';      Kind: tkKwVar;      Category: tcKeyword),
    (Text: 'const';    Kind: tkKwConst;    Category: tcKeyword),
    (Text: 'type';     Kind: tkKwType;     Category: tcKeyword),
    (Text: 'routine';  Kind: tkKwRoutine;  Category: tcKeyword),
    (Text: 'forward';  Kind: tkKwForward;  Category: tcKeyword),
    (Text: 'method';   Kind: tkKwMethod;   Category: tcKeyword),
    (Text: 'exported'; Kind: tkKwExported; Category: tcKeyword),
    (Text: 'clink';    Kind: tkKwClink;    Category: tcKeyword),
    (Text: 'cpplink';  Kind: tkKwCpplink;  Category: tcKeyword),
    (Text: 'external'; Kind: tkKwExternal; Category: tcKeyword),
    (Text: 'record';   Kind: tkKwRecord;   Category: tcKeyword),
    (Text: 'object';   Kind: tkKwObject;   Category: tcKeyword),
    (Text: 'overlay';  Kind: tkKwOverlay;  Category: tcKeyword),
    (Text: 'choices';  Kind: tkKwChoices;  Category: tcKeyword),
    (Text: 'array';    Kind: tkKwArray;    Category: tcKeyword),
    (Text: 'of';       Kind: tkKwOf;       Category: tcKeyword),
    (Text: 'ptr';      Kind: tkKwPtr;      Category: tcKeyword),
    (Text: 'to';       Kind: tkKwTo;       Category: tcKeyword),
    (Text: 'set';      Kind: tkKwSet;      Category: tcKeyword),
    (Text: 'packed';   Kind: tkKwPacked;   Category: tcKeyword),
    (Text: 'align';    Kind: tkKwAlign;    Category: tcKeyword),
    (Text: 'if';       Kind: tkKwIf;       Category: tcKeyword),
    (Text: 'then';     Kind: tkKwThen;     Category: tcKeyword),
    (Text: 'else';     Kind: tkKwElse;     Category: tcKeyword),
    (Text: 'while';    Kind: tkKwWhile;    Category: tcKeyword),
    (Text: 'do';       Kind: tkKwDo;       Category: tcKeyword),
    (Text: 'for';      Kind: tkKwFor;      Category: tcKeyword),
    (Text: 'downto';   Kind: tkKwDownto;   Category: tcKeyword),
    (Text: 'repeat';   Kind: tkKwRepeat;   Category: tcKeyword),
    (Text: 'until';    Kind: tkKwUntil;    Category: tcKeyword),
    (Text: 'match';    Kind: tkKwMatch;    Category: tcKeyword),
    (Text: 'guard';    Kind: tkKwGuard;    Category: tcKeyword),
    (Text: 'except';   Kind: tkKwExcept;   Category: tcKeyword),
    (Text: 'finally';  Kind: tkKwFinally;  Category: tcKeyword),
    (Text: 'return';   Kind: tkKwReturn;   Category: tcKeyword),
    (Text: 'leave';    Kind: tkKwLeave;    Category: tcKeyword),
    (Text: 'skip';     Kind: tkKwSkip;     Category: tcKeyword),
    (Text: 'or';       Kind: tkKwOr;       Category: tcKeyword),
    (Text: 'and';      Kind: tkKwAnd;      Category: tcKeyword),
    (Text: 'xor';      Kind: tkKwXor;      Category: tcKeyword),
    (Text: 'not';      Kind: tkKwNot;      Category: tcKeyword),
    (Text: 'in';       Kind: tkKwIn;       Category: tcKeyword),
    (Text: 'shl';      Kind: tkKwShl;      Category: tcKeyword),
    (Text: 'shr';      Kind: tkKwShr;      Category: tcKeyword),
    (Text: 'div';      Kind: tkKwDiv;      Category: tcKeyword),
    (Text: 'mod';      Kind: tkKwMod;      Category: tcKeyword),
    (Text: 'address';  Kind: tkKwAddress;  Category: tcKeyword),
    (Text: 'true';     Kind: tkKwTrue;     Category: tcKeyword),
    (Text: 'false';    Kind: tkKwFalse;    Category: tcKeyword),
    (Text: 'nil';      Kind: tkKwNil;      Category: tcKeyword),
    (Text: 'self';     Kind: tkKwSelf;     Category: tcKeyword),
    (Text: 'parent';   Kind: tkKwParent;   Category: tcKeyword),
    (Text: 'varargs';  Kind: tkKwVarargs;  Category: tcKeyword),
    (Text: 'test';     Kind: tkKwTest;     Category: tcKeyword),
    (Text: 'cpp';      Kind: tkKwCpp;      Category: tcKeyword),
    (Text: 'cppstart'; Kind: tkKwCppstart; Category: tcKeyword),
    (Text: 'cppend';   Kind: tkKwCppend;   Category: tcKeyword),
    // primitives
    (Text: 'int8';     Kind: tkKwInt8;     Category: tcPrimitive),
    (Text: 'int16';    Kind: tkKwInt16;    Category: tcPrimitive),
    (Text: 'int32';    Kind: tkKwInt32;    Category: tcPrimitive),
    (Text: 'int64';    Kind: tkKwInt64;    Category: tcPrimitive),
    (Text: 'uint8';    Kind: tkKwUint8;    Category: tcPrimitive),
    (Text: 'uint16';   Kind: tkKwUint16;   Category: tcPrimitive),
    (Text: 'uint32';   Kind: tkKwUint32;   Category: tcPrimitive),
    (Text: 'uint64';   Kind: tkKwUint64;   Category: tcPrimitive),
    (Text: 'float32';  Kind: tkKwFloat32;  Category: tcPrimitive),
    (Text: 'float64';  Kind: tkKwFloat64;  Category: tcPrimitive),
    (Text: 'bool';     Kind: tkKwBool;     Category: tcPrimitive),
    (Text: 'char';     Kind: tkKwChar;     Category: tcPrimitive),
    (Text: 'wchar';    Kind: tkKwWchar;    Category: tcPrimitive),
    (Text: 'string';   Kind: tkKwString;   Category: tcPrimitive),
    (Text: 'wstring';  Kind: tkKwWstring;  Category: tcPrimitive),
    // operators
    (Text: '+';   Kind: tkPlus;                Category: tcOperator),
    (Text: '-';   Kind: tkMinus;               Category: tcOperator),
    (Text: '*';   Kind: tkStar;                Category: tcOperator),
    (Text: '/';   Kind: tkSlash;               Category: tcOperator),
    (Text: '%';   Kind: tkPercent;             Category: tcOperator),
    (Text: '=';   Kind: tkEqual;               Category: tcOperator),
    (Text: '<>';  Kind: tkLessGreater;         Category: tcOperator),
    (Text: '<';   Kind: tkLess;                Category: tcOperator),
    (Text: '>';   Kind: tkGreater;             Category: tcOperator),
    (Text: '<=';  Kind: tkLessEqual;           Category: tcOperator),
    (Text: '>=';  Kind: tkGreaterEqual;        Category: tcOperator),
    (Text: ':=';  Kind: tkColonEqual;          Category: tcOperator),
    (Text: '+=';  Kind: tkPlusEqual;           Category: tcOperator),
    (Text: '-=';  Kind: tkMinusEqual;          Category: tcOperator),
    (Text: '*=';  Kind: tkStarEqual;           Category: tcOperator),
    (Text: '/=';  Kind: tkSlashEqual;          Category: tcOperator),
    (Text: '%=';  Kind: tkPercentEqual;        Category: tcOperator),
    (Text: '&=';  Kind: tkAmpEqual;            Category: tcOperator),
    (Text: '|=';  Kind: tkPipeEqual;           Category: tcOperator),
    (Text: '<<='; Kind: tkLessLessEqual;       Category: tcOperator),
    (Text: '>>='; Kind: tkGreaterGreaterEqual; Category: tcOperator),
    (Text: '^';   Kind: tkCaret;               Category: tcOperator),
    (Text: '|';   Kind: tkPipe;                Category: tcOperator),
    (Text: '&';   Kind: tkAmp;                 Category: tcOperator),
    (Text: '~';   Kind: tkTilde;               Category: tcOperator),
    (Text: '!';   Kind: tkBang;                Category: tcOperator),
    (Text: '&&';  Kind: tkAmpAmp;              Category: tcOperator),
    (Text: '||';  Kind: tkPipePipe;            Category: tcOperator),
    (Text: '++';  Kind: tkPlusPlus;            Category: tcOperator),
    (Text: '--';  Kind: tkMinusMinus;          Category: tcOperator),
    (Text: '<<';  Kind: tkLessLess;            Category: tcOperator),
    (Text: '>>';  Kind: tkGreaterGreater;      Category: tcOperator),
    (Text: '->';  Kind: tkMinusGreater;        Category: tcOperator),
    (Text: '::';  Kind: tkColonColon;          Category: tcOperator),
    // delimiters
    (Text: ':';   Kind: tkColon;               Category: tcDelimiter),
    (Text: '.';   Kind: tkDot;                 Category: tcDelimiter),
    (Text: '..';  Kind: tkDotDot;              Category: tcDelimiter),
    (Text: '...'; Kind: tkDotDotDot;           Category: tcDelimiter),
    (Text: ',';   Kind: tkComma;               Category: tcDelimiter),
    (Text: ';';   Kind: tkSemicolon;           Category: tcDelimiter),
    (Text: '(';   Kind: tkLParen;              Category: tcDelimiter),
    (Text: ')';   Kind: tkRParen;              Category: tcDelimiter),
    (Text: '[';   Kind: tkLBracket;            Category: tcDelimiter),
    (Text: ']';   Kind: tkRBracket;            Category: tcDelimiter)
  );

  { PC_CPP_TOKENS }
  // Every C++23 reserved word and operator spelling. Deliberately absent:
  // ^= ->* .* (token-vocab.md), # (whole-line token), contextual words. The
  // digraphs <: :> <% %> carry the canonical kind and come after the canonical
  // rows, so FindKindRow keeps returning [ ] { }; %: and %:%: are hash
  // punctuators like # and ## (the lexer's DoMatchHash), never rows
  PC_CPP_TOKENS: array[0..142] of TPCTokenRow = (
    // reserved words
    (Text: 'alignas';          Kind: tkKwAlignas;          Category: tcCppKeyword),
    (Text: 'alignof';          Kind: tkKwAlignof;          Category: tcCppKeyword),
    (Text: 'and';              Kind: tkKwAnd;              Category: tcCppKeyword),
    (Text: 'and_eq';           Kind: tkKwAnd_eq;           Category: tcCppKeyword),
    (Text: 'asm';              Kind: tkKwAsm;              Category: tcCppKeyword),
    (Text: 'auto';             Kind: tkKwAuto;             Category: tcCppKeyword),
    (Text: 'bitand';           Kind: tkKwBitand;           Category: tcCppKeyword),
    (Text: 'bitor';            Kind: tkKwBitor;            Category: tcCppKeyword),
    (Text: 'bool';             Kind: tkKwBool;             Category: tcCppKeyword),
    (Text: 'break';            Kind: tkKwBreak;            Category: tcCppKeyword),
    (Text: 'case';             Kind: tkKwCase;             Category: tcCppKeyword),
    (Text: 'catch';            Kind: tkKwCatch;            Category: tcCppKeyword),
    (Text: 'char';             Kind: tkKwChar;             Category: tcCppKeyword),
    (Text: 'char8_t';          Kind: tkKwChar8_t;          Category: tcCppKeyword),
    (Text: 'char16_t';         Kind: tkKwChar16_t;         Category: tcCppKeyword),
    (Text: 'char32_t';         Kind: tkKwChar32_t;         Category: tcCppKeyword),
    (Text: 'class';            Kind: tkKwClass;            Category: tcCppKeyword),
    (Text: 'compl';            Kind: tkKwCompl;            Category: tcCppKeyword),
    (Text: 'concept';          Kind: tkKwConcept;          Category: tcCppKeyword),
    (Text: 'const';            Kind: tkKwConst;            Category: tcCppKeyword),
    (Text: 'consteval';        Kind: tkKwConsteval;        Category: tcCppKeyword),
    (Text: 'constexpr';        Kind: tkKwConstexpr;        Category: tcCppKeyword),
    (Text: 'constinit';        Kind: tkKwConstinit;        Category: tcCppKeyword),
    (Text: 'const_cast';       Kind: tkKwConst_cast;       Category: tcCppKeyword),
    (Text: 'continue';         Kind: tkKwContinue;         Category: tcCppKeyword),
    (Text: 'co_await';         Kind: tkKwCo_await;         Category: tcCppKeyword),
    (Text: 'co_return';        Kind: tkKwCo_return;        Category: tcCppKeyword),
    (Text: 'co_yield';         Kind: tkKwCo_yield;         Category: tcCppKeyword),
    (Text: 'decltype';         Kind: tkKwDecltype;         Category: tcCppKeyword),
    (Text: 'default';          Kind: tkKwDefault;          Category: tcCppKeyword),
    (Text: 'delete';           Kind: tkKwDelete;           Category: tcCppKeyword),
    (Text: 'do';               Kind: tkKwDo;               Category: tcCppKeyword),
    (Text: 'double';           Kind: tkKwDouble;           Category: tcCppKeyword),
    (Text: 'dynamic_cast';     Kind: tkKwDynamic_cast;     Category: tcCppKeyword),
    (Text: 'else';             Kind: tkKwElse;             Category: tcCppKeyword),
    (Text: 'enum';             Kind: tkKwEnum;             Category: tcCppKeyword),
    (Text: 'explicit';         Kind: tkKwExplicit;         Category: tcCppKeyword),
    (Text: 'export';           Kind: tkKwExport;           Category: tcCppKeyword),
    (Text: 'extern';           Kind: tkKwExtern;           Category: tcCppKeyword),
    (Text: 'false';            Kind: tkKwFalse;            Category: tcCppKeyword),
    (Text: 'float';            Kind: tkKwFloat;            Category: tcCppKeyword),
    (Text: 'for';              Kind: tkKwFor;              Category: tcCppKeyword),
    (Text: 'friend';           Kind: tkKwFriend;           Category: tcCppKeyword),
    (Text: 'goto';             Kind: tkKwGoto;             Category: tcCppKeyword),
    (Text: 'if';               Kind: tkKwIf;               Category: tcCppKeyword),
    (Text: 'inline';           Kind: tkKwInline;           Category: tcCppKeyword),
    (Text: 'int';              Kind: tkKwInt;              Category: tcCppKeyword),
    (Text: 'long';             Kind: tkKwLong;             Category: tcCppKeyword),
    (Text: 'mutable';          Kind: tkKwMutable;          Category: tcCppKeyword),
    (Text: 'namespace';        Kind: tkKwNamespace;        Category: tcCppKeyword),
    (Text: 'new';              Kind: tkKwNew;              Category: tcCppKeyword),
    (Text: 'noexcept';         Kind: tkKwNoexcept;         Category: tcCppKeyword),
    (Text: 'not';              Kind: tkKwNot;              Category: tcCppKeyword),
    (Text: 'not_eq';           Kind: tkKwNot_eq;           Category: tcCppKeyword),
    (Text: 'nullptr';          Kind: tkKwNullptr;          Category: tcCppKeyword),
    (Text: 'operator';         Kind: tkKwOperator;         Category: tcCppKeyword),
    (Text: 'or';               Kind: tkKwOr;               Category: tcCppKeyword),
    (Text: 'or_eq';            Kind: tkKwOr_eq;            Category: tcCppKeyword),
    (Text: 'private';          Kind: tkKwPrivate;          Category: tcCppKeyword),
    (Text: 'protected';        Kind: tkKwProtected;        Category: tcCppKeyword),
    (Text: 'public';           Kind: tkKwPublic;           Category: tcCppKeyword),
    (Text: 'register';         Kind: tkKwRegister;         Category: tcCppKeyword),
    (Text: 'reinterpret_cast'; Kind: tkKwReinterpret_cast; Category: tcCppKeyword),
    (Text: 'requires';         Kind: tkKwRequires;         Category: tcCppKeyword),
    (Text: 'return';           Kind: tkKwReturn;           Category: tcCppKeyword),
    (Text: 'short';            Kind: tkKwShort;            Category: tcCppKeyword),
    (Text: 'signed';           Kind: tkKwSigned;           Category: tcCppKeyword),
    (Text: 'sizeof';           Kind: tkKwSizeof;           Category: tcCppKeyword),
    (Text: 'static';           Kind: tkKwStatic;           Category: tcCppKeyword),
    (Text: 'static_assert';    Kind: tkKwStatic_assert;    Category: tcCppKeyword),
    (Text: 'static_cast';      Kind: tkKwStatic_cast;      Category: tcCppKeyword),
    (Text: 'struct';           Kind: tkKwStruct;           Category: tcCppKeyword),
    (Text: 'switch';           Kind: tkKwSwitch;           Category: tcCppKeyword),
    (Text: 'template';         Kind: tkKwTemplate;         Category: tcCppKeyword),
    (Text: 'this';             Kind: tkKwThis;             Category: tcCppKeyword),
    (Text: 'thread_local';     Kind: tkKwThread_local;     Category: tcCppKeyword),
    (Text: 'throw';            Kind: tkKwThrow;            Category: tcCppKeyword),
    (Text: 'true';             Kind: tkKwTrue;             Category: tcCppKeyword),
    (Text: 'try';              Kind: tkKwTry;              Category: tcCppKeyword),
    (Text: 'typedef';          Kind: tkKwTypedef;          Category: tcCppKeyword),
    (Text: 'typeid';           Kind: tkKwTypeid;           Category: tcCppKeyword),
    (Text: 'typename';         Kind: tkKwTypename;         Category: tcCppKeyword),
    (Text: 'union';            Kind: tkKwUnion;            Category: tcCppKeyword),
    (Text: 'unsigned';         Kind: tkKwUnsigned;         Category: tcCppKeyword),
    (Text: 'using';            Kind: tkKwUsing;            Category: tcCppKeyword),
    (Text: 'virtual';          Kind: tkKwVirtual;          Category: tcCppKeyword),
    (Text: 'void';             Kind: tkKwVoid;             Category: tcCppKeyword),
    (Text: 'volatile';         Kind: tkKwVolatile;         Category: tcCppKeyword),
    (Text: 'wchar_t';          Kind: tkKwWchar_t;          Category: tcCppKeyword),
    (Text: 'while';            Kind: tkKwWhile;            Category: tcCppKeyword),
    (Text: 'xor';              Kind: tkKwXor;              Category: tcCppKeyword),
    (Text: 'xor_eq';           Kind: tkKwXor_eq;           Category: tcCppKeyword),
    // operators
    (Text: '+';   Kind: tkPlus;                Category: tcOperator),
    (Text: '-';   Kind: tkMinus;               Category: tcOperator),
    (Text: '*';   Kind: tkStar;                Category: tcOperator),
    (Text: '/';   Kind: tkSlash;               Category: tcOperator),
    (Text: '%';   Kind: tkPercent;             Category: tcOperator),
    (Text: '^';   Kind: tkCaret;               Category: tcOperator),
    (Text: '&';   Kind: tkAmp;                 Category: tcOperator),
    (Text: '|';   Kind: tkPipe;                Category: tcOperator),
    (Text: '~';   Kind: tkTilde;               Category: tcOperator),
    (Text: '!';   Kind: tkBang;                Category: tcOperator),
    (Text: '=';   Kind: tkEqual;               Category: tcOperator),
    (Text: '<';   Kind: tkLess;                Category: tcOperator),
    (Text: '>';   Kind: tkGreater;             Category: tcOperator),
    (Text: '+=';  Kind: tkPlusEqual;           Category: tcOperator),
    (Text: '-=';  Kind: tkMinusEqual;          Category: tcOperator),
    (Text: '*=';  Kind: tkStarEqual;           Category: tcOperator),
    (Text: '/=';  Kind: tkSlashEqual;          Category: tcOperator),
    (Text: '%=';  Kind: tkPercentEqual;        Category: tcOperator),
    (Text: '&=';  Kind: tkAmpEqual;            Category: tcOperator),
    (Text: '|=';  Kind: tkPipeEqual;           Category: tcOperator),
    (Text: '<<';  Kind: tkLessLess;            Category: tcOperator),
    (Text: '>>';  Kind: tkGreaterGreater;      Category: tcOperator),
    (Text: '<<='; Kind: tkLessLessEqual;       Category: tcOperator),
    (Text: '>>='; Kind: tkGreaterGreaterEqual; Category: tcOperator),
    (Text: '==';  Kind: tkEqualEqual;          Category: tcOperator),
    (Text: '!=';  Kind: tkBangEqual;           Category: tcOperator),
    (Text: '<=';  Kind: tkLessEqual;           Category: tcOperator),
    (Text: '>=';  Kind: tkGreaterEqual;        Category: tcOperator),
    (Text: '<=>'; Kind: tkLessEqualGreater;    Category: tcOperator),
    (Text: '&&';  Kind: tkAmpAmp;              Category: tcOperator),
    (Text: '||';  Kind: tkPipePipe;            Category: tcOperator),
    (Text: '++';  Kind: tkPlusPlus;            Category: tcOperator),
    (Text: '--';  Kind: tkMinusMinus;          Category: tcOperator),
    (Text: '->';  Kind: tkMinusGreater;        Category: tcOperator),
    (Text: '::';  Kind: tkColonColon;          Category: tcOperator),
    (Text: '?';   Kind: tkQuestion;            Category: tcOperator),
    // delimiters
    (Text: ',';   Kind: tkComma;               Category: tcDelimiter),
    (Text: ';';   Kind: tkSemicolon;           Category: tcDelimiter),
    (Text: ':';   Kind: tkColon;               Category: tcDelimiter),
    (Text: '.';   Kind: tkDot;                 Category: tcDelimiter),
    (Text: '...'; Kind: tkDotDotDot;           Category: tcDelimiter),
    (Text: '(';   Kind: tkLParen;              Category: tcDelimiter),
    (Text: ')';   Kind: tkRParen;              Category: tcDelimiter),
    (Text: '[';   Kind: tkLBracket;            Category: tcDelimiter),
    (Text: ']';   Kind: tkRBracket;            Category: tcDelimiter),
    (Text: '{';   Kind: tkLBrace;              Category: tcDelimiter),
    (Text: '}';   Kind: tkRBrace;              Category: tcDelimiter),
    // digraphs (research\cppmix\digraphs\d2-vocabulary.md)
    (Text: '<:';  Kind: tkLBracket;            Category: tcDelimiter),
    (Text: ':>';  Kind: tkRBracket;            Category: tcDelimiter),
    (Text: '<%';  Kind: tkLBrace;              Category: tcDelimiter),
    (Text: '%>';  Kind: tkRBrace;              Category: tcDelimiter)
  );

  { PC_SHARED_TOKENS }
  // Every spelling BOTH tables register, with its resolution
  // (token-vocab.md "Shared-token list"). Anything else in both tables, or
  // anything here not in both, is a fatal startup error.
  PC_SHARED_TOKENS: array[0..55] of TPCSharedRow = (
    // symbols, same meaning
    (Text: '+';   Resolution: srSame),
    (Text: '-';   Resolution: srSame),
    (Text: '*';   Resolution: srSame),
    (Text: '%';   Resolution: srSame),
    (Text: '&';   Resolution: srSame),
    (Text: '|';   Resolution: srSame),
    (Text: '~';   Resolution: srSame),
    (Text: '!';   Resolution: srSame),
    (Text: '<';   Resolution: srSame),
    (Text: '>';   Resolution: srSame),
    (Text: '+=';  Resolution: srSame),
    (Text: '-=';  Resolution: srSame),
    (Text: '*=';  Resolution: srSame),
    (Text: '/=';  Resolution: srSame),
    (Text: '%=';  Resolution: srSame),
    (Text: '&=';  Resolution: srSame),
    (Text: '|=';  Resolution: srSame),
    (Text: '<<';  Resolution: srSame),
    (Text: '>>';  Resolution: srSame),
    (Text: '<<='; Resolution: srSame),
    (Text: '>>='; Resolution: srSame),
    (Text: '<=';  Resolution: srSame),
    (Text: '>=';  Resolution: srSame),
    (Text: '&&';  Resolution: srSame),
    (Text: '||';  Resolution: srSame),
    (Text: '++';  Resolution: srSame),
    (Text: '--';  Resolution: srSame),
    (Text: '->';  Resolution: srSame),
    (Text: '::';  Resolution: srSame),
    (Text: ':';   Resolution: srSame),
    (Text: '.';   Resolution: srSame),
    (Text: '...'; Resolution: srSame),
    (Text: ',';   Resolution: srSame),
    (Text: ';';   Resolution: srSame),
    (Text: '(';   Resolution: srSame),
    (Text: ')';   Resolution: srSame),
    (Text: '[';   Resolution: srSame),
    (Text: ']';   Resolution: srSame),
    // symbols, PaskalCPP meaning only
    (Text: '/';   Resolution: srPaskalWins),
    (Text: '=';   Resolution: srPaskalWins),
    (Text: '^';   Resolution: srPaskalWins),
    // words, same meaning
    (Text: 'and';    Resolution: srSame),
    (Text: 'or';     Resolution: srSame),
    (Text: 'not';    Resolution: srSame),
    (Text: 'xor';    Resolution: srSame),
    (Text: 'const';  Resolution: srSame),
    (Text: 'true';   Resolution: srSame),
    (Text: 'false';  Resolution: srSame),
    (Text: 'char';   Resolution: srSame),
    (Text: 'bool';   Resolution: srSame),
    // words, PaskalCPP meaning only (C++ statement forms not allowed in bodies)
    (Text: 'if';     Resolution: srPaskalWins),
    (Text: 'else';   Resolution: srPaskalWins),
    (Text: 'for';    Resolution: srPaskalWins),
    (Text: 'while';  Resolution: srPaskalWins),
    (Text: 'do';     Resolution: srPaskalWins),
    (Text: 'return'; Resolution: srPaskalWins)
  );

  { PC_SPLIT_PIECES }
  // Every spelling a parser-split of >> >= >>= <> can present
  // (>> -> > >; >= -> > =; >>= -> > >= -> > =; <> -> < >)
  PC_SPLIT_PIECES: array[0..3] of TPCSplitPiece = (
    (Text: '>';  Kind: tkGreater),
    (Text: '<';  Kind: tkLess),
    (Text: '=';  Kind: tkEqual),
    (Text: '>='; Kind: tkGreaterEqual)
  );

  { PC_TARGET_X86_64_WINDOWS_GNU }
  // A supported target, named by its zig triple (BNF.md sec 2, DESIGN.md sec 7)
  PC_TARGET_X86_64_WINDOWS_GNU = 'x86_64-windows-gnu';
  { PC_TARGET_X86_64_LINUX_GNU }
  PC_TARGET_X86_64_LINUX_GNU = 'x86_64-linux-gnu';

  { PC_DATA_MODELS }
  // One row per supported target (research\cppmix\sem\datamodel.md Q3, probed
  // 2026-10-06). Adding a target = adding a row; the witness test covers it
  PC_DATA_MODELS: array[0..1] of TPCDataModelRow = (
    (Target: PC_TARGET_X86_64_WINDOWS_GNU; IntBits: 32; LongBits: 32; LongLongBits: 64;
      PointerBits: 64; SizeTBits: 64; WCharBits: 16; FloatBits: 32; DoubleBits: 64;
      IsCharSigned: True; IsWCharSigned: False),
    (Target: PC_TARGET_X86_64_LINUX_GNU; IntBits: 32; LongBits: 64; LongLongBits: 64;
      PointerBits: 64; SizeTBits: 64; WCharBits: 32; FloatBits: 32; DoubleBits: 64;
      IsCharSigned: True; IsWCharSigned: True)
  );

  { PC_ALIGN_MODELS }
  // One row per supported target (research\paskal-errors\r-b-align.md P7,
  // probed 2026-10-12): Aligns in TPCAlignKind order. wchar_t is 2 on
  // windows-gnu, 4 on linux-gnu; libc++'s string / vector are 8; a set's
  // words are uint64 at every range. Adding a target = adding a row; the
  // witness test covers it
  PC_ALIGN_MODELS: array[0..1] of TPCAlignModelRow = (
    (Target: PC_TARGET_X86_64_WINDOWS_GNU;
      Aligns: (1, 2, 4, 8, 1, 2, 4, 8, 4, 8, 1, 1, 2, 2, 8, 8, 8, 8, 8, 8)),
    (Target: PC_TARGET_X86_64_LINUX_GNU;
      Aligns: (1, 2, 4, 8, 1, 2, 4, 8, 4, 8, 1, 1, 4, 2, 8, 8, 8, 8, 8, 8))
  );

  { PC_ALIGN_CPP_TEXT }
  // The C++ spelling of each kind as the emitter writes it, compiled by the
  // witness (alignof of each, against the real runtime header). A pointer to
  // void, a routine taking nothing, a vector of int32 and a set of 0..7 stand
  // for every instance of their kind (P7: no target, element or range moves
  // them)
  PC_ALIGN_CPP_TEXT: array[TPCAlignKind] of string = (
    'std::int8_t',
    'std::int16_t',
    'std::int32_t',
    'std::int64_t',
    'std::uint8_t',
    'std::uint16_t',
    'std::uint32_t',
    'std::uint64_t',
    'float',
    'double',
    'bool',
    'char',
    'wchar_t',
    'char16_t',
    'std::string',
    'std::wstring',
    'void*',
    'std::add_pointer_t<void()>',
    'std::vector<std::int32_t>',
    '::pcpp::Set<std::int64_t, 0, 7>'
  );

  { PC_ALIGN_MAX }
  // The largest align every supported target takes: windows-gnu refuses
  // 16384 and more, linux-gnu takes it (probed; parity, DESIGN sec 7). SEM
  // judges a folded value against it (SM0312), the emitter's check a C++ one
  PC_ALIGN_MAX = 8192;

  { PC_FRONTEND_CHECK_NATURAL }
  // The messages of the checks the emitter writes into a record whose align
  // SEM could not judge (a C/C++ leaf, a C++ align value): each static_assert
  // fails with its text. The frontend recognizes it and reports the code from
  // the AST (PLAN-PASKAL-ERRORS E3 / F31, r-b-align.md D2): a marker only says
  // which check failed, never what the record is. NATURAL = align(n) below
  // the natural alignment clang computed (SM0311)
  PC_FRONTEND_CHECK_NATURAL = 'pcpp:SM0311';
  { PC_FRONTEND_CHECK_POWER }
  // A C++ align value that is not a power of two (SM0310)
  PC_FRONTEND_CHECK_POWER = 'pcpp:SM0310';
  { PC_FRONTEND_CHECK_MAX }
  // A C++ align value above PC_ALIGN_MAX (SM0312)
  PC_FRONTEND_CHECK_MAX = 'pcpp:SM0312';
  { PC_FRONTEND_CHECK_PRINT }
  // A print / println argument of a C/C++ type std::format cannot take (it
  // has no std::formatter): the emitter's check at the argument (E7, SM0425)
  PC_FRONTEND_CHECK_PRINT = 'pcpp:SM0425';
  { PC_FRONTEND_CHECK_PACKED }
  // A packed record's field (or parent) of a type only clang lays out that
  // does not pack, ::pcpp::packs_as_field (PLAN-RECORDS M9, SM0331)
  PC_FRONTEND_CHECK_PACKED = 'pcpp:SM0331';
  { PC_FRONTEND_CHECK_OVERLAY }
  // An overlay's field (or a field of an anonymous record in one) of a type
  // only clang knows that is not trivial C++ data, ::pcpp::fits_overlay
  // (PLAN-COMPLIANCE F34, SM0313)
  PC_FRONTEND_CHECK_OVERLAY = 'pcpp:SM0313';
  { PC_FRONTEND_CHECK_POLY }
  // PLAN-OBJECT O13b: a rule that depends on whether an object is
  // polymorphic, where only clang knows (a C/C++ base): the emitter's
  // static_assert around the expression; the expression's ResolvedPolyCheck
  // gives the code, ResolvedPolyText the message
  PC_FRONTEND_CHECK_POLY = 'pcpp:poly';
  { PC_FRONTEND_FLAG_OVERRIDE }
  // PLAN-OBJECT O13b (D7 across D14): clang's warning group, as its serialized
  // diagnostics name it (no -W), for a method that overrides a virtual
  // without `override`. The emitter makes it an error only inside the class
  // of an object whose chain reaches C/C++ (PC_EMT_OVERRIDE_CHECK_*), so
  // only a C++ parent's virtual can raise it; reported as SM0332
  PC_FRONTEND_FLAG_OVERRIDE = 'suggest-override';
  { PC_CLANG_OVERRIDE_HIDES }
  // PLAN-OBJECT O13b (4): clang's error texts for an `override` method that
  // overrides no C++ virtual (they carry no warning group). The Compiler
  // owns one only at the name of a PaskalCPP override method on a chain
  // reaching C/C++ with no PaskalCPP base (TPCAst.CppOverrideAt): HIDES =
  // a virtual of that name with the other const (SM0389), the other two =
  // no virtual of that name (SM0333). Witnessed by the bundled clang:
  // Compliance type_object_cpp_err_override_const / _override_nothing
  PC_CLANG_OVERRIDE_HIDES = 'non-virtual member function marked ''override'' hides virtual member function';
  { PC_CLANG_OVERRIDE_NOTHING }
  PC_CLANG_OVERRIDE_NOTHING = 'marked ''override'' but does not override any member functions';
  { PC_CLANG_OVERRIDE_NOT_VIRTUAL }
  PC_CLANG_OVERRIDE_NOT_VIRTUAL = 'only virtual member functions can be marked ''override''';
  { PC_CLANG_FORMAT_STRING }
  // PLAN-VENDOR 1e: clang's error text when a std::format_string argument
  // (println's format, a C++ routine's: SysUtils.FormatStr) cannot be checked
  // against its arguments: the message holds both parts. The Compiler owns it
  // only at an argument of a PaskalCPP call (TPCAst.CallAt): a string literal
  // that does not fit = SM0502, any other value = SM0500. Witnessed by the
  // bundled clang: Compliance intr_print_err_format, std_sysutils_format_err_*
  PC_CLANG_FORMAT_STRING = 'call to consteval function ''std::basic_format_string<';
  { PC_CLANG_NOT_CONSTANT }
  PC_CLANG_NOT_CONSTANT = ' is not a constant expression';
  { PC_CLANG_UNKNOWN_TYPE }
  // clang's error text at a type name it does not know. The Compiler owns it
  // only at a PaskalCPP type spelled as an imported unit (TPCAst.UnitTypeAt):
  // SM0013 there. Witnessed by the bundled clang: Compliance
  // type_alias_err_module
  PC_CLANG_UNKNOWN_TYPE = 'unknown type name ''';

  { PC_MAX_OBJECT_SIZE }
  // F47: the largest size in bytes a type has on every supported target. clang
  // refuses a struct or union of 2^60 bytes or more (probed both targets,
  // scripts\zb_cmpl\f4\array\f47\p2_out.txt), and every PaskalCPP static array
  // is ::pcpp::Array, a struct, so it is the static array's limit too. SEM
  // judges a folded count past it (no element is smaller than one byte,
  // SM0277); the runtime's ::pcpp::max_object_size holds the same value and
  // judges count x element size inside ::pcpp::Array. Witness: the hooked
  // Conditionals.size_witness (both targets: the runtime's value, the edge,
  // clang's record text)
  PC_MAX_OBJECT_SIZE = UInt64(1152921504606846975);
  { PC_FRONTEND_CHECK_SIZE }
  // The runtime's check inside ::pcpp::Array (F47): count x element size past
  // PC_MAX_OBJECT_SIZE. It fires where the array is instantiated (the element
  // is complete only there), inside the runtime header, so BuildOutput hands
  // the frontend clang's first instantiation note it claims (the use)
  PC_FRONTEND_CHECK_SIZE = 'pcpp:SM0277';
  { PC_CLANG_RECORD_TOO_LARGE }
  // clang's own error for a struct / union past the cap, at its name, with no
  // warning group: owned only at a PaskalCPP record's, overlay's or object's
  // name (F47, TPCAst.SizeCheckAt). Witnessed by Conditionals.size_witness
  PC_CLANG_RECORD_TOO_LARGE = ' is too large, which exceeds maximum allowed size of ';

  { PC_SOURCE_EXTS }
  // The file name extensions the bundled clang compiles, exact case, and as
  // what (probed on both targets, scripts\zb_asf\probe_exts.py: .C / .CPP /
  // .C++ are C++, .h / .hpp are headers, any other name is linker input that
  // compiles nothing). TPCSourceFiles reads it
  PC_SOURCE_EXTS: array[0..12] of TPCSourceExtRow = (
    (ExtText: '.c';   Language: slC),
    (ExtText: '.C';   Language: slCpp),
    (ExtText: '.cc';  Language: slCpp),
    (ExtText: '.cp';  Language: slCpp),
    (ExtText: '.cpp'; Language: slCpp),
    (ExtText: '.CPP'; Language: slCpp),
    (ExtText: '.cxx'; Language: slCpp),
    (ExtText: '.CXX'; Language: slCpp),
    (ExtText: '.c++'; Language: slCpp),
    (ExtText: '.C++'; Language: slCpp),
    (ExtText: '.S';   Language: slAsm),
    (ExtText: '.s';   Language: slAsm),
    (ExtText: '.ll';  Language: slLLVMIR)
  );

  { PC_BUILD_DIRECTIVES }
  // BNF.md sec 2, exact case. IsMainOnly: sec 2 "Build directives in an imported unit".
  // Indexed by TPCBuildDirective: an enum value without a row does not compile
  PC_BUILD_DIRECTIVES: array[TPCBuildDirective] of TPCDirectiveRow = (
    (DirectiveName: 'optimize';      Shape: dsIdentifier;   IsPath: False; IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'subsystem';     Shape: dsIdentifier;   IsPath: False; IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'target';        Shape: dsCString;      IsPath: False; IsMainOnly: False; IsFilterChecked: True;  IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'addverinfo';    Shape: dsIdentifier;   IsPath: False; IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'unitTestMode';  Shape: dsIdentifier;   IsPath: False; IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'vimajor';       Shape: dsInteger;      IsPath: False; IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'viminor';       Shape: dsInteger;      IsPath: False; IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'vipatch';       Shape: dsInteger;      IsPath: False; IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'viproductname'; Shape: dsCString;      IsPath: False; IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'videscription'; Shape: dsCString;      IsPath: False; IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'vifilename';    Shape: dsCString;      IsPath: False; IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'vicompanyname'; Shape: dsCString;      IsPath: False; IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'vicopyright';   Shape: dsCString;      IsPath: False; IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'exeicon';       Shape: dsCString;      IsPath: True;  IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    (DirectiveName: 'copydll';       Shape: dsCString;      IsPath: True;  IsMainOnly: False; IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: False),
    (DirectiveName: 'linklibrary';   Shape: dsCString;      IsPath: False; IsMainOnly: False; IsFilterChecked: False; IsLibName: True;  IsStatement: False; IsSingle: False),
    (DirectiveName: 'addlibrarypath'; Shape: dsCString;     IsPath: True;  IsMainOnly: False; IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: False),
    (DirectiveName: 'addmodulepath'; Shape: dsCString;      IsPath: True;  IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: False),
    (DirectiveName: 'addincludepath'; Shape: dsCString;     IsPath: True;  IsMainOnly: False; IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: False),
    (DirectiveName: 'addsourcefile'; Shape: dsCString;      IsPath: True;  IsMainOnly: False; IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: False),
    (DirectiveName: 'cppdefine';     Shape: dsOneOrTwoCStrings; IsPath: False; IsMainOnly: False; IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: False),
    (DirectiveName: 'cppundef';      Shape: dsCString;      IsPath: False; IsMainOnly: False; IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: False),
    (DirectiveName: 'breakpoint';    Shape: dsNone;         IsPath: False; IsMainOnly: False; IsFilterChecked: False; IsLibName: False; IsStatement: True;  IsSingle: False),
    (DirectiveName: 'message';       Shape: dsSeverityText; IsPath: False; IsMainOnly: False; IsFilterChecked: False; IsLibName: False; IsStatement: True;  IsSingle: False),
    // The build's output folder (user 2026-10-14): the source says where it
    // builds, the same from the CLI and the editor; an explicit -o wins
    (DirectiveName: 'outputpath';    Shape: dsCString;      IsPath: True;  IsMainOnly: True;  IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: True),
    // A file built into the binary under a key (PLAN-RESDATA, user 2026-10-19):
    // any module; the path (the second value) resolves as every build path
    (DirectiveName: 'addresdata';    Shape: dsKeyAndPath;   IsPath: True;  IsMainOnly: False; IsFilterChecked: False; IsLibName: False; IsStatement: False; IsSingle: False)
  );

  { PC_DIRECTIVE_VALUES }
  // BNF.md sec 2 values, exact case (sem\module.md); the Compiler maps these
  // spellings to ZigBuild
  PC_DIRECTIVE_VALUES: array[0..9] of TPCDirectiveValue = (
    // zig 0.17's own names (std.lang.Optimize), user 2026-10-18
    (Directive: bdOptimize;     ValueText: 'debug'),
    (Directive: bdOptimize;     ValueText: 'safe'),
    (Directive: bdOptimize;     ValueText: 'fast'),
    (Directive: bdOptimize;     ValueText: 'small'),
    (Directive: bdSubsystem;    ValueText: 'console'),
    (Directive: bdSubsystem;    ValueText: 'gui'),
    (Directive: bdAddVerInfo;   ValueText: 'on'),
    (Directive: bdAddVerInfo;   ValueText: 'off'),
    (Directive: bdUnitTestMode; ValueText: 'on'),
    (Directive: bdUnitTestMode; ValueText: 'off')
  );

  { PC_RETIRED_VALUES }
  // Spellings no longer accepted (a clean break, user 2026-10-18): each is an
  // error whose hint names CurrentText. Read by SEM's @optimize check and the
  // Compiler's option keys (pcpp -opt, the editor)
  PC_RETIRED_VALUES: array[0..2] of TPCRetiredValue = (
    (Directive: bdOptimize; RetiredText: 'release_safe';  CurrentText: 'safe'),
    (Directive: bdOptimize; RetiredText: 'release_fast';  CurrentText: 'fast'),
    (Directive: bdOptimize; RetiredText: 'release_small'; CurrentText: 'small')
  );

  { PC_MESSAGE_SEVERITIES }
  // @message severity words (BNF.md sec 2), by the TErrors severity each reports at
  PC_MESSAGE_SEVERITIES: array[TErrorSeverity] of string = ('hint', 'warn', 'error', 'fatal');

  { PC_INT_SUFFIXES }
  // Every standard integer suffix spelling C++23 accepts (BNF.md sec 9) and its meaning
  PC_INT_SUFFIXES: array[0..31] of TPCIntSuffixRow = (
    (SuffixText: 'u';   IsUnsigned: True;  SuffixWidth: iwInt),
    (SuffixText: 'U';   IsUnsigned: True;  SuffixWidth: iwInt),
    (SuffixText: 'l';   IsUnsigned: False; SuffixWidth: iwLong),
    (SuffixText: 'L';   IsUnsigned: False; SuffixWidth: iwLong),
    (SuffixText: 'll';  IsUnsigned: False; SuffixWidth: iwLongLong),
    (SuffixText: 'LL';  IsUnsigned: False; SuffixWidth: iwLongLong),
    (SuffixText: 'z';   IsUnsigned: False; SuffixWidth: iwSize),
    (SuffixText: 'Z';   IsUnsigned: False; SuffixWidth: iwSize),
    (SuffixText: 'ul';  IsUnsigned: True;  SuffixWidth: iwLong),
    (SuffixText: 'uL';  IsUnsigned: True;  SuffixWidth: iwLong),
    (SuffixText: 'ull'; IsUnsigned: True;  SuffixWidth: iwLongLong),
    (SuffixText: 'uLL'; IsUnsigned: True;  SuffixWidth: iwLongLong),
    (SuffixText: 'uz';  IsUnsigned: True;  SuffixWidth: iwSize),
    (SuffixText: 'uZ';  IsUnsigned: True;  SuffixWidth: iwSize),
    (SuffixText: 'Ul';  IsUnsigned: True;  SuffixWidth: iwLong),
    (SuffixText: 'UL';  IsUnsigned: True;  SuffixWidth: iwLong),
    (SuffixText: 'Ull'; IsUnsigned: True;  SuffixWidth: iwLongLong),
    (SuffixText: 'ULL'; IsUnsigned: True;  SuffixWidth: iwLongLong),
    (SuffixText: 'Uz';  IsUnsigned: True;  SuffixWidth: iwSize),
    (SuffixText: 'UZ';  IsUnsigned: True;  SuffixWidth: iwSize),
    (SuffixText: 'lu';  IsUnsigned: True;  SuffixWidth: iwLong),
    (SuffixText: 'lU';  IsUnsigned: True;  SuffixWidth: iwLong),
    (SuffixText: 'Lu';  IsUnsigned: True;  SuffixWidth: iwLong),
    (SuffixText: 'LU';  IsUnsigned: True;  SuffixWidth: iwLong),
    (SuffixText: 'llu'; IsUnsigned: True;  SuffixWidth: iwLongLong),
    (SuffixText: 'llU'; IsUnsigned: True;  SuffixWidth: iwLongLong),
    (SuffixText: 'LLu'; IsUnsigned: True;  SuffixWidth: iwLongLong),
    (SuffixText: 'LLU'; IsUnsigned: True;  SuffixWidth: iwLongLong),
    (SuffixText: 'zu';  IsUnsigned: True;  SuffixWidth: iwSize),
    (SuffixText: 'zU';  IsUnsigned: True;  SuffixWidth: iwSize),
    (SuffixText: 'Zu';  IsUnsigned: True;  SuffixWidth: iwSize),
    (SuffixText: 'ZU';  IsUnsigned: True;  SuffixWidth: iwSize)
  );

implementation

uses
  StdApp.Resources,
  PaskalCPP.UnicodeNames;

{ TPCToken }

procedure TPCToken.Clear();
begin
  Kind := tkUnknown;
  Category := tcSpecial;
  Origin := toNone;
  Range.Clear();
  TriviaStart := 0;
  Text := '';
  Spelling := '';
  LiteralBase := lbNone;
  LiteralPrefix := lpNone;
  IsRawString := False;
  Suffix := '';
  IsUserDefined := False;
  HasValue := False;
  IntValue := 0;
  FloatValue := 0.0;
end;

function TPCToken.ByteLength(): UInt64;
begin
  Result := Range.EndByteOffset - Range.StartByteOffset;
end;

{ TPCIntSuffixRow }

function TPCIntSuffixRow.MayBeUnsigned(const AIsDecimal: Boolean): Boolean;
begin
  // Decimal: int / long / long long (signed) unless a u suffix asks for the
  // unsigned ones; other bases list both signed and unsigned candidates
  if AIsDecimal then
    Result := IsUnsigned
  else
    Result := True;
end;

{ TPCContextWordRow }

function TPCContextWordRow.Matches(const AToken: TPCToken): Boolean;
begin
  // A plain word is an identifier spelled exactly so (Spelling: splices
  // removed, as every identifier compares); a C++ word is its token kind
  if AToken.Kind <> Kind then
    Exit(False);
  if Kind <> tkIdentifier then
    Exit(True);
  Result := AToken.Spelling = WordText;
end;

{ TPCVocabulary }

constructor TPCVocabulary.Create();
begin
  inherited;

  FWords := TDictionary<string, TPCVocabEntry>.Create();
  FOperators := TDictionary<string, TPCVocabEntry>.Create();
  FBuilt := False;
end;

destructor TPCVocabulary.Destroy();
begin
  FOperators.Free();
  FWords.Free();

  inherited;
end;

function TPCVocabulary.DoMapFor(const AText: string): TDictionary<string, TPCVocabEntry>;
begin
  // Words start with a letter or underscore; every other spelling is an operator
  if (AText <> '') and CharInSet(AText[1], ['A'..'Z', 'a'..'z', '_']) then
    Result := FWords
  else
    Result := FOperators;
end;

function TPCVocabulary.DoCollectShared(const ARows: array of TPCSharedRow;
  const AShared: TDictionary<string, TPCSharedResolution>): Boolean;
var
  LI: Integer;
begin
  Result := True;
  for LI := Low(ARows) to High(ARows) do
  begin
    if AShared.ContainsKey(ARows[LI].Text) then
    begin
      FErrors.Add(esFatal, PC_ERR_VOC_004, RSComVocDuplicate,
        [ARows[LI].Text, RSComVocTableShared]);
      Result := False;
    end
    else
      AShared.Add(ARows[LI].Text, ARows[LI].Resolution);
  end;
end;

function TPCVocabulary.DoAddPaskal(const ARows: array of TPCTokenRow): Boolean;
var
  LI: Integer;
  LMap: TDictionary<string, TPCVocabEntry>;
  LEntry: TPCVocabEntry;
begin
  Result := True;
  for LI := Low(ARows) to High(ARows) do
  begin
    LMap := DoMapFor(ARows[LI].Text);
    if LMap.ContainsKey(ARows[LI].Text) then
    begin
      FErrors.Add(esFatal, PC_ERR_VOC_004, RSComVocDuplicate,
        [ARows[LI].Text, RSComVocTablePaskal]);
      Result := False;
      Continue;
    end;

    LEntry.Text := ARows[LI].Text;
    LEntry.Kind := ARows[LI].Kind;
    LEntry.Category := ARows[LI].Category;
    LEntry.Origin := toPaskal;
    LEntry.Resolution := srSame;
    LMap.Add(LEntry.Text, LEntry);
  end;
end;

function TPCVocabulary.DoAddCpp(const ARows: array of TPCTokenRow;
  const AShared: TDictionary<string, TPCSharedResolution>;
  const ACppSpellings: TDictionary<string, Boolean>): Boolean;
var
  LI: Integer;
  LMap: TDictionary<string, TPCVocabEntry>;
  LEntry: TPCVocabEntry;
  LResolution: TPCSharedResolution;
begin
  Result := True;
  for LI := Low(ARows) to High(ARows) do
  begin
    // A spelling twice in the C++ table is a duplicate, whatever PaskalCPP has
    if ACppSpellings.ContainsKey(ARows[LI].Text) then
    begin
      FErrors.Add(esFatal, PC_ERR_VOC_004, RSComVocDuplicate,
        [ARows[LI].Text, RSComVocTableCpp]);
      Result := False;
      Continue;
    end;
    // Record the registration BEFORE the checks below: ACppSpellings holds
    // what the C++ table registers, not which rows passed. DoCheckShared
    // reads it, so a row failing VC0001/VC0003 is not also reported VC0002.
    ACppSpellings.Add(ARows[LI].Text, True);

    LMap := DoMapFor(ARows[LI].Text);
    if LMap.TryGetValue(ARows[LI].Text, LEntry) then
    begin
      // Registered by PaskalCPP too: must be listed, with the same kind.
      // The PaskalCPP row's kind and category stand; the origin is shared.
      if not AShared.TryGetValue(ARows[LI].Text, LResolution) then
      begin
        FErrors.Add(esFatal, PC_ERR_VOC_001, RSComVocNotShared, [ARows[LI].Text]);
        Result := False;
        Continue;
      end;
      if LEntry.Kind <> ARows[LI].Kind then
      begin
        FErrors.Add(esFatal, PC_ERR_VOC_003, RSComVocKindMismatch, [ARows[LI].Text]);
        Result := False;
        Continue;
      end;
      LEntry.Origin := toShared;
      LEntry.Resolution := LResolution;
      LMap.AddOrSetValue(LEntry.Text, LEntry);
    end
    else
    begin
      LEntry.Text := ARows[LI].Text;
      LEntry.Kind := ARows[LI].Kind;
      LEntry.Category := ARows[LI].Category;
      LEntry.Origin := toCpp;
      LEntry.Resolution := srSame;
      LMap.Add(LEntry.Text, LEntry);
    end;
  end;
end;

function TPCVocabulary.DoCheckShared(const ARows: array of TPCSharedRow;
  const ACppSpellings: TDictionary<string, Boolean>): Boolean;
var
  LI: Integer;
  LEntry: TPCVocabEntry;
  LInPaskal: Boolean;
  LInCpp: Boolean;
begin
  // A listed spelling that is not registered by BOTH tables is a stale entry.
  // Registration is tested directly, never through Origin: a row that failed
  // its kind check (VC0003) keeps Origin toPaskal yet is registered by both.
  Result := True;
  for LI := Low(ARows) to High(ARows) do
  begin
    // PaskalCPP registers it when the map holds it from the Paskal table
    // (origin toPaskal or toShared); toCpp means only the C++ table did
    LInPaskal := False;
    if DoMapFor(ARows[LI].Text).TryGetValue(ARows[LI].Text, LEntry) then
      LInPaskal := LEntry.Origin <> toCpp;
    LInCpp := ACppSpellings.ContainsKey(ARows[LI].Text);

    if not (LInPaskal and LInCpp) then
    begin
      FErrors.Add(esFatal, PC_ERR_VOC_002, RSComVocStaleShared, [ARows[LI].Text]);
      Result := False;
    end;
  end;
end;

function TPCVocabulary.BuildFrom(const APaskal: array of TPCTokenRow;
  const ACpp: array of TPCTokenRow;
  const AShared: array of TPCSharedRow): Boolean;
var
  LShared: TDictionary<string, TPCSharedResolution>;
  LCppSpellings: TDictionary<string, Boolean>;
  LOk: Boolean;
begin
  FWords.Clear();
  FOperators.Clear();
  FBuilt := False;

  LShared := TDictionary<string, TPCSharedResolution>.Create();
  try
    // Every spelling the C++ table registers; filled by DoAddCpp, read by
    // DoCheckShared (registration, independent of which rows passed)
    LCppSpellings := TDictionary<string, Boolean>.Create();
    try
      // Every check runs, so one startup reports every table defect at once
      LOk := DoCollectShared(AShared, LShared);
      LOk := DoAddPaskal(APaskal) and LOk;
      LOk := DoAddCpp(ACpp, LShared, LCppSpellings) and LOk;
      LOk := DoCheckShared(AShared, LCppSpellings) and LOk;
    finally
      LCppSpellings.Free();
    end;
  finally
    LShared.Free();
  end;

  FBuilt := LOk;
  Result := LOk;
end;

function TPCVocabulary.Build(): Boolean;
begin
  if FBuilt then
    Exit(True);

  Result := BuildFrom(PC_PASKAL_TOKENS, PC_CPP_TOKENS, PC_SHARED_TOKENS);
end;

function TPCVocabulary.IsBuilt(): Boolean;
begin
  Result := FBuilt;
end;

function TPCVocabulary.FindWord(const AText: string; out AEntry: TPCVocabEntry): Boolean;
begin
  Result := FWords.TryGetValue(AText, AEntry);
end;

function TPCVocabulary.FindOperator(const AText: string; out AEntry: TPCVocabEntry): Boolean;
begin
  Result := FOperators.TryGetValue(AText, AEntry);
end;

class function TPCVocabulary.FindKindRow(const AKind: TPCTokenKind;
  out ARow: TPCTokenRow): Boolean;
var
  LI: Integer;
begin
  ARow := Default(TPCTokenRow);
  for LI := Low(PC_PASKAL_TOKENS) to High(PC_PASKAL_TOKENS) do
  begin
    if PC_PASKAL_TOKENS[LI].Kind = AKind then
    begin
      ARow := PC_PASKAL_TOKENS[LI];
      Exit(True);
    end;
  end;
  for LI := Low(PC_CPP_TOKENS) to High(PC_CPP_TOKENS) do
  begin
    if PC_CPP_TOKENS[LI].Kind = AKind then
    begin
      ARow := PC_CPP_TOKENS[LI];
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TPCVocabulary.IsBuiltinTypeWord(const AKind: TPCTokenKind): Boolean;
var
  LRow: TPCTokenRow;
begin
  // `varargs` is a keyword row (the lexer and DoParsePrimary dispatch on its
  // kind) that also names the pack type (BNF sec 4); every other builtin type
  // word is a tcPrimitive row
  if AKind = tkKwVarargs then
    Exit(True);
  Result := FindKindRow(AKind, LRow) and (LRow.Category = tcPrimitive);
end;

class function TPCVocabulary.FindDirective(const ADirectiveName: string;
  out ADirective: TPCBuildDirective): Boolean;
var
  LDirective: TPCBuildDirective;
begin
  // One row per directive, exact case (BNF.md sec 2)
  for LDirective := Low(TPCBuildDirective) to High(TPCBuildDirective) do
  begin
    if PC_BUILD_DIRECTIVES[LDirective].DirectiveName = ADirectiveName then
    begin
      ADirective := LDirective;
      Exit(True);
    end;
  end;
  ADirective := Low(TPCBuildDirective);
  Result := False;
end;

class function TPCVocabulary.IsDirectiveValue(const ADirective: TPCBuildDirective;
  const AText: string): Boolean;
var
  LI: Integer;
begin
  for LI := Low(PC_DIRECTIVE_VALUES) to High(PC_DIRECTIVE_VALUES) do
  begin
    if (PC_DIRECTIVE_VALUES[LI].Directive = ADirective) and
      (PC_DIRECTIVE_VALUES[LI].ValueText = AText) then
      Exit(True);
  end;
  Result := False;
end;

class function TPCVocabulary.DirectiveValuesText(const ADirective: TPCBuildDirective): string;
var
  LI: Integer;
  LText: string;
begin
  LText := '';
  for LI := Low(PC_DIRECTIVE_VALUES) to High(PC_DIRECTIVE_VALUES) do
  begin
    if PC_DIRECTIVE_VALUES[LI].Directive = ADirective then
    begin
      if LText <> '' then
        LText := LText + ', ';
      LText := LText + PC_DIRECTIVE_VALUES[LI].ValueText;
    end;
  end;
  Result := LText;
end;

class function TPCVocabulary.FindRetiredValue(const ADirective: TPCBuildDirective;
  const AText: string; out ACurrentText: string): Boolean;
var
  LI: Integer;
begin
  ACurrentText := '';
  for LI := Low(PC_RETIRED_VALUES) to High(PC_RETIRED_VALUES) do
  begin
    if (PC_RETIRED_VALUES[LI].Directive = ADirective) and
      (PC_RETIRED_VALUES[LI].RetiredText = AText) then
    begin
      ACurrentText := PC_RETIRED_VALUES[LI].CurrentText;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TPCVocabulary.FindIntSuffix(const ASuffix: string; out ARow: TPCIntSuffixRow): Boolean;
var
  LI: Integer;
begin
  ARow := Default(TPCIntSuffixRow);
  Result := False;
  for LI := Low(PC_INT_SUFFIXES) to High(PC_INT_SUFFIXES) do
  begin
    if PC_INT_SUFFIXES[LI].SuffixText = ASuffix then
    begin
      ARow := PC_INT_SUFFIXES[LI];
      Exit(True);
    end;
  end;
end;

class function TPCVocabulary.IsSplittable(const AKind: TPCTokenKind): Boolean;
begin
  // Only these four may be split inside template arguments (token-vocab.md)
  case AKind of
    tkGreaterGreater,
    tkGreaterEqual,
    tkGreaterGreaterEqual,
    tkLessGreater:
      Result := True;
  else
    Result := False;
  end;
end;

class function TPCVocabulary.FindSplitPiece(const AText: string;
  out AKind: TPCTokenKind): Boolean;
var
  LI: Integer;
begin
  Result := False;
  AKind := tkUnknown;
  for LI := Low(PC_SPLIT_PIECES) to High(PC_SPLIT_PIECES) do
  begin
    if PC_SPLIT_PIECES[LI].Text = AText then
    begin
      AKind := PC_SPLIT_PIECES[LI].Kind;
      Exit(True);
    end;
  end;
end;

{ TPCTargetTriple }

function DoFindDataModel(const ATarget: string; out ARow: TPCDataModelRow): Boolean;
var
  LI: Integer;
begin
  // Exact-case lookup of a zig triple (arch-os-abi) in the supported targets
  Result := False;
  ARow := Default(TPCDataModelRow);
  for LI := Low(PC_DATA_MODELS) to High(PC_DATA_MODELS) do
  begin
    if PC_DATA_MODELS[LI].Target = ATarget then
    begin
      ARow := PC_DATA_MODELS[LI];
      Exit(True);
    end;
  end;
end;

function DoModelOf(const ATriple: TPCTargetTriple; out ARow: TPCDataModelRow): Boolean;
begin
  // The row of a parsed triple; False (zeroed row) for an empty one
  ARow := Default(TPCDataModelRow);
  if ATriple.IsEmpty() then
    Exit(False);
  Result := DoFindDataModel(ATriple.ToZig(), ARow);
end;

function DoCanonicalVendor(const AOS: string): string;
begin
  // LLVM's canonical vendor per OS (BNF.md sec 2)
  if AOS = 'windows' then
    Result := 'pc'
  else
    Result := 'unknown';
end;

function TPCTargetTriple.IsEmpty(): Boolean;
begin
  Result := Arch = '';
end;

function TPCTargetTriple.IsWindows(): Boolean;
begin
  Result := OS = 'windows';
end;

function TPCTargetTriple.ToLLVM(): string;
begin
  Result := Arch + '-' + Vendor + '-' + OS + '-' + Env;
end;

function TPCTargetTriple.ToZig(): string;
begin
  // Zig rejects the vendor (probe tests\probe\zb_triple.c)
  Result := Arch + '-' + OS + '-' + Env;
end;

function TPCTargetTriple.IntBits(): Integer;
var
  LRow: TPCDataModelRow;
begin
  DoModelOf(Self, LRow);
  Result := LRow.IntBits;
end;

function TPCTargetTriple.LongBits(): Integer;
var
  LRow: TPCDataModelRow;
begin
  DoModelOf(Self, LRow);
  Result := LRow.LongBits;
end;

function TPCTargetTriple.LongLongBits(): Integer;
var
  LRow: TPCDataModelRow;
begin
  DoModelOf(Self, LRow);
  Result := LRow.LongLongBits;
end;

function TPCTargetTriple.PointerBits(): Integer;
var
  LRow: TPCDataModelRow;
begin
  DoModelOf(Self, LRow);
  Result := LRow.PointerBits;
end;

function TPCTargetTriple.SizeTBits(): Integer;
var
  LRow: TPCDataModelRow;
begin
  DoModelOf(Self, LRow);
  Result := LRow.SizeTBits;
end;

function TPCTargetTriple.WCharBits(): Integer;
var
  LRow: TPCDataModelRow;
begin
  DoModelOf(Self, LRow);
  Result := LRow.WCharBits;
end;

function TPCTargetTriple.FloatBits(): Integer;
var
  LRow: TPCDataModelRow;
begin
  DoModelOf(Self, LRow);
  Result := LRow.FloatBits;
end;

function TPCTargetTriple.DoubleBits(): Integer;
var
  LRow: TPCDataModelRow;
begin
  DoModelOf(Self, LRow);
  Result := LRow.DoubleBits;
end;

function TPCTargetTriple.IsCharSigned(): Boolean;
var
  LRow: TPCDataModelRow;
begin
  // A zeroed row (empty triple) reads False
  DoModelOf(Self, LRow);
  Result := LRow.IsCharSigned;
end;

function TPCTargetTriple.IsWCharSigned(): Boolean;
var
  LRow: TPCDataModelRow;
begin
  // A zeroed row (empty triple) reads False
  DoModelOf(Self, LRow);
  Result := LRow.IsWCharSigned;
end;

function TPCTargetTriple.AlignOf(const AKind: TPCAlignKind): Integer;
var
  LI: Integer;
  LTarget: string;
begin
  // The kind's alignment in the row of this triple's target (exact zig
  // triple, as DoFindDataModel); 0 for an empty triple
  Result := 0;
  if IsEmpty() then
    Exit;
  LTarget := ToZig();
  for LI := Low(PC_ALIGN_MODELS) to High(PC_ALIGN_MODELS) do
  begin
    if PC_ALIGN_MODELS[LI].Target = LTarget then
      Exit(PC_ALIGN_MODELS[LI].Aligns[AKind]);
  end;
end;

class function TPCTargetTriple.Parse(const AText: string;
  out ATriple: TPCTargetTriple): TPCTripleStatus;
var
  LParts: TArray<string>;
  LPart: string;
  LRow: TPCDataModelRow;
begin
  // arch-vendor-os-env, or arch-os-env normalized to four parts; exact case;
  // no empty part. Only a supported target is taken: its zig triple is a
  // PC_DATA_MODELS row and its vendor the canonical one, so one target has one
  // spelling (BNF.md sec 2; sem\module.md "@target")
  ATriple := Default(TPCTargetTriple);
  LParts := AText.Split(['-']);
  if (Length(LParts) <> 3) and (Length(LParts) <> 4) then
    Exit(tsBadShape);
  for LPart in LParts do
  begin
    if LPart = '' then
      Exit(tsBadShape);
  end;

  ATriple.Arch := LParts[0];
  if Length(LParts) = 4 then
  begin
    ATriple.Vendor := LParts[1];
    ATriple.OS := LParts[2];
    ATriple.Env := LParts[3];
  end
  else
  begin
    ATriple.OS := LParts[1];
    ATriple.Env := LParts[2];
    ATriple.Vendor := DoCanonicalVendor(ATriple.OS);
  end;

  if (ATriple.Vendor <> DoCanonicalVendor(ATriple.OS)) or
    (not DoFindDataModel(ATriple.ToZig(), LRow)) then
  begin
    ATriple := Default(TPCTargetTriple);
    Exit(tsUnsupported);
  end;
  Result := tsOk;
end;

class function TPCTargetTriple.DefaultTriple(): TPCTargetTriple;
begin
  // The default target, parsed from its one spelling (a row, so always tsOk;
  // Conditionals.triple asserts it)
  Parse(PC_TARGET_X86_64_WINDOWS_GNU, Result);
end;

class function TPCTargetTriple.SupportedTargetsText(): string;
var
  LI: Integer;
begin
  // Every row's target, in table order: a new row reaches the messages
  Result := '';
  for LI := Low(PC_DATA_MODELS) to High(PC_DATA_MODELS) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + PC_DATA_MODELS[LI].Target;
  end;
end;

{ TPCCString }

class procedure TPCCString.DoAppendByte(var ABytes: TBytes; var ACount: Integer;
  const AByte: Byte);
begin
  // Decode presizes the buffer; growing by doubling covers any miscount
  if ACount >= Length(ABytes) then
    SetLength(ABytes, (Length(ABytes) * 2) + 16);
  ABytes[ACount] := AByte;
  Inc(ACount);
end;

class procedure TPCCString.DoAppendCodePoint(var ABytes: TBytes; var ACount: Integer;
  const ACodePoint: Cardinal);
begin
  // UTF-8 encoding of one code point. Callers reject surrogates and values
  // past U+10FFFF first; DoBytesToText rejects any that slip through, so a
  // wrong value can never come out silently.
  if ACodePoint < $80 then
    DoAppendByte(ABytes, ACount, Byte(ACodePoint))
  else if ACodePoint < $800 then
  begin
    DoAppendByte(ABytes, ACount, Byte($C0 or (ACodePoint shr 6)));
    DoAppendByte(ABytes, ACount, Byte($80 or (ACodePoint and $3F)));
  end
  else if ACodePoint < $10000 then
  begin
    DoAppendByte(ABytes, ACount, Byte($E0 or (ACodePoint shr 12)));
    DoAppendByte(ABytes, ACount, Byte($80 or ((ACodePoint shr 6) and $3F)));
    DoAppendByte(ABytes, ACount, Byte($80 or (ACodePoint and $3F)));
  end
  else
  begin
    DoAppendByte(ABytes, ACount, Byte($F0 or ((ACodePoint shr 18) and $07)));
    DoAppendByte(ABytes, ACount, Byte($80 or ((ACodePoint shr 12) and $3F)));
    DoAppendByte(ABytes, ACount, Byte($80 or ((ACodePoint shr 6) and $3F)));
    DoAppendByte(ABytes, ACount, Byte($80 or (ACodePoint and $3F)));
  end;
end;

class procedure TPCCString.DoAddRun(var ARuns: TArray<TPCSpellRun>; var ARunCount: Integer;
  const AValueOffset: Integer; const ASpellIndex: Integer; const AIsCopy: Boolean);
begin
  // Grown by doubling; Decode trims once
  if ARunCount >= Length(ARuns) then
    SetLength(ARuns, (Length(ARuns) * 2) + 8);
  ARuns[ARunCount].ValueOffset := AValueOffset;
  ARuns[ARunCount].SpellIndex := ASpellIndex;
  ARuns[ARunCount].IsCopy := AIsCopy;
  Inc(ARunCount);
end;

class function TPCCString.DoCodePointAt(const AText: string; var AIndex: Integer): Cardinal;
begin
  // The code point at AIndex (a UTF-16 surrogate pair is one); AIndex steps
  // past it. A lone surrogate comes back as is (the source is validated
  // UTF-8, so none occurs; DoBytesToText would reject it).
  Result := Ord(AText[AIndex]);
  if (Result >= $D800) and (Result <= $DBFF) and (AIndex < Length(AText)) and
    (Ord(AText[AIndex + 1]) >= $DC00) and (Ord(AText[AIndex + 1]) <= $DFFF) then
  begin
    Result := $10000 + ((Result - $D800) shl 10) +
      (Cardinal(Ord(AText[AIndex + 1])) - $DC00);
    Inc(AIndex, 2);
  end
  else
    Inc(AIndex);
end;

class function TPCCString.DoDigitValue(const AChar: Char; const ABase: Cardinal;
  out AValue: Cardinal): Boolean;
begin
  // An octal (ABase 8) or hex (ABase 16, either case: clang) digit
  AValue := 0;
  if (AChar >= '0') and (AChar <= '9') then
    AValue := Ord(AChar) - Ord('0')
  else if (ABase = 16) and (AChar >= 'a') and (AChar <= 'f') then
    AValue := Ord(AChar) - Ord('a') + 10
  else if (ABase = 16) and (AChar >= 'A') and (AChar <= 'F') then
    AValue := Ord(AChar) - Ord('A') + 10
  else
    Exit(False);
  Result := AValue < ABase;
end;

class function TPCCString.DoSimpleEscapeByte(const AChar: Char): Byte;
begin
  // The control escapes; \e and \E are the GNU escape ($1B)
  case AChar of
    'a': Result := $07;
    'b': Result := $08;
    'f': Result := $0C;
    'n': Result := $0A;
    'r': Result := $0D;
    't': Result := $09;
    'v': Result := $0B;
  else
    Result := $1B;
  end;
end;

class function TPCCString.DoReason(const ATemplate: string; const AArg: string): string;
begin
  // Fills the one %s of an RSComCStr* template; String.Replace cannot raise
  // (Format can)
  Result := ATemplate.Replace('%s', AArg);
end;

class function TPCCString.DoDelimited(const AText: string; const ALast: Integer;
  var AIndex: Integer; const ABase: Cardinal; const ALimit: Cardinal;
  out AValue: Cardinal; out AOverflow: Boolean; out AReason: string): Boolean;
var
  LDigit: Cardinal;
  LCount: Integer;
  LStart: Integer;
  LAcc: UInt64;
begin
  // AText[AIndex] is the '{' of \o{} \x{} \u{}. Reads ABase digits up to the
  // '}' (any count, leading zeros fine). A value past ALimit sets AOverflow
  // while the digits are still consumed (clang never wraps). The accumulator
  // is UInt64 and stops growing at the first overflow, so any Cardinal
  // ALimit (a wide char's $FFFFFFFF too) is safe. AIndex ends past the '}'.
  // Order as probed: a bad digit, then a missing '}', then empty.
  Result := False;
  AValue := 0;
  AOverflow := False;
  AReason := '';
  LCount := 0;
  LAcc := 0;
  Inc(AIndex);
  while (AIndex <= ALast) and (AText[AIndex] <> '}') do
  begin
    if not DoDigitValue(AText[AIndex], ABase, LDigit) then
    begin
      LStart := AIndex;
      DoCodePointAt(AText, AIndex);
      AReason := DoReason(RSComCStrInvalidDigit, Copy(AText, LStart, AIndex - LStart));
      Exit;
    end;
    if not AOverflow then
    begin
      LAcc := (LAcc * ABase) + LDigit;
      if LAcc > ALimit then
        AOverflow := True;
    end;
    Inc(LCount);
    Inc(AIndex);
  end;
  if AIndex > ALast then
  begin
    AReason := RSComCStrExpectedClose;
    Exit;
  end;
  if LCount = 0 then
  begin
    AReason := RSComCStrDelimEmpty;
    Exit;
  end;

  // Step past the '}'
  Inc(AIndex);
  if not AOverflow then
    AValue := Cardinal(LAcc);
  Result := True;
end;

class function TPCCString.DoEscapeValue(const AText: string; const ALast: Integer;
  var AIndex: Integer; const ANumericLimit: Cardinal; out AValue: Cardinal;
  out AIsNumeric: Boolean; var AWarning: string; out AReason: string): Boolean;
var
  LChar: Char;
  LValue: Cardinal;
  LAcc: UInt64;
  LDigit: Cardinal;
  LCount: Integer;
  LWant: Integer;
  LOverflow: Boolean;
  LStart: Integer;
  LNameEnd: Integer;
  LCharName: string;
begin
  // The one escape engine. AText[AIndex] is the character after '\' (AIndex
  // <= ALast: the caller checked); steps AIndex past the escape and returns
  // its value. AIsNumeric = an octal or hex escape: a code unit, at most
  // ANumericLimit ($FF narrow, $FFFFFFFF wide). Otherwise a code point
  // (simple escapes, quotes, \u \U \N, an unknown escape's character).
  // False = error (AReason). An unknown escape sets AWarning when none is
  // set yet.
  Result := False;
  AReason := '';
  AValue := 0;
  AIsNumeric := False;
  LChar := AText[AIndex];
  case LChar of
    '"', '''', '?', '\':
      begin
        AValue := Ord(LChar);
        Inc(AIndex);
      end;

    'a', 'b', 'f', 'n', 'r', 't', 'v', 'e', 'E':
      begin
        AValue := DoSimpleEscapeByte(LChar);
        Inc(AIndex);
      end;

    '0'..'7':
      begin
        // 1-3 octal digits, greedy (\1011 = 'A' '1', \18 = $01 '8')
        LValue := 0;
        LCount := 0;
        while (AIndex <= ALast) and (LCount < 3) and
          DoDigitValue(AText[AIndex], 8, LDigit) do
        begin
          LValue := (LValue * 8) + LDigit;
          Inc(LCount);
          Inc(AIndex);
        end;
        // Three octal digits reach 511 at most: no accumulator overflow
        if LValue > ANumericLimit then
        begin
          AReason := RSComCStrOctalRange;
          Exit;
        end;
        AValue := LValue;
        AIsNumeric := True;
      end;

    'o':
      begin
        // \o{octal+} only
        Inc(AIndex);
        if (AIndex > ALast) or (AText[AIndex] <> '{') then
        begin
          AReason := DoReason(RSComCStrExpectedBrace, 'o');
          Exit;
        end;
        if not DoDelimited(AText, ALast, AIndex, 8, ANumericLimit, LValue, LOverflow, AReason) then
          Exit;
        if LOverflow then
        begin
          AReason := RSComCStrOctalRange;
          Exit;
        end;
        AValue := LValue;
        AIsNumeric := True;
      end;

    'x':
      begin
        // \x{hex+} or greedy hex digits; the value is a code unit, not a code
        // point. The greedy accumulator is UInt64 and stops at the first
        // overflow, so a $FFFFFFFF limit is safe
        Inc(AIndex);
        if (AIndex <= ALast) and (AText[AIndex] = '{') then
        begin
          if not DoDelimited(AText, ALast, AIndex, 16, ANumericLimit, LValue, LOverflow, AReason) then
            Exit;
        end
        else
        begin
          LAcc := 0;
          LCount := 0;
          LOverflow := False;
          while (AIndex <= ALast) and DoDigitValue(AText[AIndex], 16, LDigit) do
          begin
            if not LOverflow then
            begin
              LAcc := (LAcc * 16) + LDigit;
              if LAcc > ANumericLimit then
                LOverflow := True;
            end;
            Inc(LCount);
            Inc(AIndex);
          end;
          if LCount = 0 then
          begin
            AReason := DoReason(RSComCStrNoHexDigits, 'x');
            Exit;
          end;
          LValue := Cardinal(LAcc);
        end;
        if LOverflow then
        begin
          AReason := RSComCStrHexRange;
          Exit;
        end;
        AValue := LValue;
        AIsNumeric := True;
      end;

    'u', 'U':
      begin
        // \u{hex+}, or exactly 4 (\u) / 8 (\U) hex digits; \U has no braced
        // form (\U{ = no digits, probed)
        Inc(AIndex);
        if (LChar = 'u') and (AIndex <= ALast) and (AText[AIndex] = '{') then
        begin
          if not DoDelimited(AText, ALast, AIndex, 16, $10FFFF, LValue, LOverflow, AReason) then
            Exit;
        end
        else
        begin
          if LChar = 'u' then
            LWant := 4
          else
            LWant := 8;
          LValue := 0;
          LCount := 0;
          LOverflow := False;
          while (AIndex <= ALast) and (LCount < LWant) and
            DoDigitValue(AText[AIndex], 16, LDigit) do
          begin
            if not LOverflow then
            begin
              LValue := (LValue * 16) + LDigit;
              if LValue > $10FFFF then
                LOverflow := True;
            end;
            Inc(LCount);
            Inc(AIndex);
          end;
          // Zero digits and a short run are different faults in clang
          if LCount = 0 then
          begin
            AReason := DoReason(RSComCStrNoHexDigits, LChar);
            Exit;
          end;
          if LCount < LWant then
          begin
            AReason := RSComCStrIncompleteUcn;
            Exit;
          end;
        end;
        // A surrogate or a value past U+10FFFF is not a character
        if LOverflow or ((LValue >= $D800) and (LValue <= $DFFF)) then
        begin
          AReason := RSComCStrInvalidUcn;
          Exit;
        end;
        AValue := LValue;
      end;

    'N':
      begin
        // \N{name}: the name runs to the next '}', matched exactly
        Inc(AIndex);
        if (AIndex > ALast) or (AText[AIndex] <> '{') then
        begin
          AReason := DoReason(RSComCStrExpectedBrace, 'N');
          Exit;
        end;
        LStart := AIndex + 1;
        LNameEnd := LStart;
        while (LNameEnd <= ALast) and (AText[LNameEnd] <> '}') do
          Inc(LNameEnd);
        if LNameEnd > ALast then
        begin
          AReason := RSComCStrIncompleteUcn;
          Exit;
        end;
        if LNameEnd = LStart then
        begin
          AReason := RSComCStrDelimEmpty;
          Exit;
        end;
        LCharName := Copy(AText, LStart, LNameEnd - LStart);
        if not TPCUnicodeNames.Lookup(LCharName, LValue) then
        begin
          AReason := DoReason(RSComCStrUnknownName, LCharName);
          Exit;
        end;
        AIndex := LNameEnd + 1;
        AValue := LValue;
      end;
  else
    begin
      // Unknown escape (\q, \(, \8, a multi-byte character): the character
      // itself, backslash dropped, and a warning (-Wunknown-escape-sequence)
      LStart := AIndex;
      AValue := DoCodePointAt(AText, AIndex);
      if AWarning = '' then
        AWarning := DoReason(RSComCStrUnknownEscape, Copy(AText, LStart, AIndex - LStart));
    end;
  end;
  Result := True;
end;

class function TPCCString.DoDecodeEscape(const AText: string; const ALast: Integer;
  var AIndex: Integer; var ABytes: TBytes; var ACount: Integer;
  var AWarning: string; out AReason: string): Boolean;
var
  LValue: Cardinal;
  LIsNumeric: Boolean;
begin
  // A narrow string's escape: its value from the one engine (numeric escapes
  // at most $FF), appended as one byte (octal / hex) or as the UTF-8 of a
  // code point. False = error (AReason)
  Result := DoEscapeValue(AText, ALast, AIndex, $FF, LValue, LIsNumeric, AWarning, AReason);
  if not Result then
    Exit;
  if LIsNumeric then
    DoAppendByte(ABytes, ACount, Byte(LValue))
  else
    DoAppendCodePoint(ABytes, ACount, LValue);
end;

class function TPCCString.DoDecodeNormal(const AText: string; var ABytes: TBytes;
  var ACount: Integer; var ARuns: TArray<TPCSpellRun>; var ARunCount: Integer;
  out AWarning: string; out AReason: string): Boolean;
var
  LIndex: Integer;
  LLast: Integer;
  LInCopy: Boolean;
begin
  // AText is '"' body '"' (Decode checked the shape); LLast = last body char.
  // Runs (P-STRPOS): an escape is always its own run at its '\'; a copied
  // code point extends the current copy run, or starts one (first, or after
  // an escape). Splices are gone from the Spelling: the parser splits a copy
  // run where one sat in the file
  Result := False;
  AWarning := '';
  AReason := '';
  LInCopy := False;
  LLast := Length(AText) - 1;
  LIndex := 2;
  while LIndex <= LLast do
  begin
    if AText[LIndex] = '\' then
    begin
      DoAddRun(ARuns, ARunCount, ACount, LIndex, False);
      LInCopy := False;
      Inc(LIndex);
      // A '\' cannot end the body: it would have escaped the closing quote
      if LIndex > LLast then
      begin
        AReason := RSComCStrNotPlain;
        Exit;
      end;
      if not DoDecodeEscape(AText, LLast, LIndex, ABytes, ACount, AWarning, AReason) then
        Exit;
    end
    else
    begin
      if not LInCopy then
      begin
        DoAddRun(ARuns, ARunCount, ACount, LIndex, True);
        LInCopy := True;
      end;
      DoAppendCodePoint(ABytes, ACount, DoCodePointAt(AText, LIndex));
    end;
  end;
  Result := True;
end;

class function TPCCString.DoDecodeRaw(const AText: string; var ABytes: TBytes;
  var ACount: Integer; var ARuns: TArray<TPCSpellRun>; var ARunCount: Integer;
  out AReason: string): Boolean;
var
  LOpen: Integer;
  LDelimiter: string;
  LBodyFirst: Integer;
  LBodyLast: Integer;
  LIndex: Integer;
  LInCopy: Boolean;
  LCodePoint: Cardinal;
begin
  // AText is R"d(body)d" (prefix splices already removed). The body is
  // copied as written: splices kept, CR LF -> LF, a lone CR kept (probed).
  Result := False;
  AReason := RSComCStrNotPlain;
  if not AText.StartsWith('R"') then
    Exit;
  LOpen := Pos('(', AText, 3);
  if LOpen = 0 then
    Exit;
  LDelimiter := Copy(AText, 3, LOpen - 3);
  if not AText.EndsWith(')' + LDelimiter + '"') then
    Exit;
  // Length = body + 2 * delimiter + 5, so the body ends 2 + delimiter
  // before the end; an empty body has LBodyLast = LOpen
  LBodyFirst := LOpen + 1;
  LBodyLast := Length(AText) - Length(LDelimiter) - 2;
  if LBodyLast < LOpen then
    Exit;
  AReason := '';

  // Runs (P-STRPOS): one copy run per line of the body. The dropped CR of a
  // CR LF ends the run and the LF starts its own at its own index (value LF
  // is 1 byte, file CR LF 2: without the break the bytes after it would map
  // one column left); an appended LF / lone CR ends the run (the next byte
  // sits on the next .pcpp line). A raw body keeps `\`+newline as content
  LInCopy := False;
  LIndex := LBodyFirst;
  while LIndex <= LBodyLast do
  begin
    if (AText[LIndex] = #13) and (LIndex < LBodyLast) and (AText[LIndex + 1] = #10) then
    begin
      Inc(LIndex);
      LInCopy := False;
    end
    else
    begin
      if not LInCopy then
      begin
        DoAddRun(ARuns, ARunCount, ACount, LIndex, True);
        LInCopy := True;
      end;
      LCodePoint := DoCodePointAt(AText, LIndex);
      DoAppendCodePoint(ABytes, ACount, LCodePoint);
      if (LCodePoint = 10) or (LCodePoint = 13) then
        LInCopy := False;
    end;
  end;
  Result := True;
end;

class function TPCCString.DoBytesToText(const ABytes: TBytes; const ACount: Integer;
  out AText: string): Boolean;
var
  LText: string;
  LCharCount: Integer;
  LIndex: Integer;
  LLead: Byte;
  LNeed: Integer;
  LMin: Cardinal;
  LCodePoint: Cardinal;
  LK: Integer;
begin
  // Strict UTF-8 (RFC 3629): no overlong form, no surrogate, nothing past
  // U+10FFFF, no truncated sequence or stray continuation byte. Builds the
  // UTF-16 text itself (TEncoding would replace bad bytes silently). UTF-16
  // units never outnumber UTF-8 bytes. AText = '' on failure.
  Result := False;
  AText := '';
  SetLength(LText, ACount);
  LCharCount := 0;
  LIndex := 0;
  while LIndex < ACount do
  begin
    LLead := ABytes[LIndex];
    if LLead < $80 then
    begin
      LCodePoint := LLead;
      LNeed := 0;
      LMin := 0;
    end
    else if (LLead and $E0) = $C0 then
    begin
      LCodePoint := LLead and $1F;
      LNeed := 1;
      LMin := $80;
    end
    else if (LLead and $F0) = $E0 then
    begin
      LCodePoint := LLead and $0F;
      LNeed := 2;
      LMin := $800;
    end
    else if (LLead and $F8) = $F0 then
    begin
      LCodePoint := LLead and $07;
      LNeed := 3;
      LMin := $10000;
    end
    else
      Exit;

    // Every continuation byte must exist and be 10xxxxxx
    if LIndex + LNeed >= ACount then
      Exit;
    for LK := 1 to LNeed do
    begin
      if (ABytes[LIndex + LK] and $C0) <> $80 then
        Exit;
      LCodePoint := (LCodePoint shl 6) or Cardinal(ABytes[LIndex + LK] and $3F);
    end;
    if (LCodePoint < LMin) or (LCodePoint > $10FFFF) or
      ((LCodePoint >= $D800) and (LCodePoint <= $DFFF)) then
      Exit;

    // One UTF-16 unit, or a surrogate pair past U+FFFF
    if LCodePoint < $10000 then
    begin
      Inc(LCharCount);
      LText[LCharCount] := Char(LCodePoint);
    end
    else
    begin
      Inc(LCharCount);
      LText[LCharCount] := Char($D800 + ((LCodePoint - $10000) shr 10));
      Inc(LCharCount);
      LText[LCharCount] := Char($DC00 + ((LCodePoint - $10000) and $3FF));
    end;
    LIndex := LIndex + LNeed + 1;
  end;
  SetLength(LText, LCharCount);
  AText := LText;
  Result := True;
end;

class function TPCCString.Decode(const AToken: TPCToken; out AValue: string;
  out AReason: string): TPCCStringStatus;
var
  LRuns: TArray<TPCSpellRun>;
begin
  // One walk, one decoder: the runs are discarded here (P-STRPOS)
  Result := Decode(AToken, AValue, AReason, LRuns);
end;

class function TPCCString.Decode(const AToken: TPCToken; out AValue: string;
  out AReason: string; out ARuns: TArray<TPCSpellRun>): TPCCStringStatus;
var
  LText: string;
  LBytes: TBytes;
  LCount: Integer;
  LRuns: TArray<TPCSpellRun>;
  LRunCount: Integer;
  LWarning: string;
  LOk: Boolean;
begin
  AValue := '';
  AReason := RSComCStrNotPlain;
  ARuns := nil;
  Result := csError;

  // Invariant guard: callers report PR0009 for anything else before calling
  if (AToken.Kind <> tkStringLiteral) or (AToken.LiteralPrefix <> lpNone) or
    (AToken.Suffix <> '') then
    Exit;

  LText := AToken.Spelling;
  LWarning := '';
  LCount := 0;
  LRuns := nil;
  LRunCount := 0;
  // A UTF-16 unit of the spelling yields at most 3 bytes (a surrogate pair
  // 4 for 2 units; an escape fewer bytes than its characters)
  SetLength(LBytes, (Length(LText) * 3) + 4);

  if AToken.IsRawString then
    LOk := DoDecodeRaw(LText, LBytes, LCount, LRuns, LRunCount, AReason)
  else
  begin
    // Shape: '"' body '"'
    if (Length(LText) < 2) or (LText[1] <> '"') or (LText[Length(LText)] <> '"') then
      Exit;
    LOk := DoDecodeNormal(LText, LBytes, LCount, LRuns, LRunCount, LWarning, AReason);
  end;
  if not LOk then
    Exit;

  if not DoBytesToText(LBytes, LCount, AValue) then
  begin
    AReason := RSComCStrNotUtf8;
    Exit;
  end;

  // Built in a local, trimmed once, assigned last: csError leaves ARuns nil
  SetLength(LRuns, LRunCount);
  ARuns := LRuns;

  if LWarning <> '' then
  begin
    AReason := LWarning;
    Exit(csWarning);
  end;
  AReason := '';
  Result := csOk;
end;

class function TPCCString.DecodeChar(const AToken: TPCToken; out AValue: UInt64;
  out AIsMultiChar: Boolean; out AReason: string): TPCCStringStatus;
var
  LText: string;
  LIsWide: Boolean;
  LIndex: Integer;
  LLast: Integer;
  LLimit: Cardinal;
  LElement: Cardinal;
  LIsNumeric: Boolean;
  LCount: Integer;
  LMulti: UInt64;
  LWarning: string;
begin
  // Values as clang computes them, probed on both official targets
  // (scripts\zb_sem\char_probe.txt, research\cppmix\sem\pchar.md)
  AValue := 0;
  AIsMultiChar := False;
  AReason := RSComCharNotPlain;
  Result := csError;

  // Invariant guard: the parser calls it only for these (u8 / u / U chars and
  // user-defined char literals stay opaque, sem\types.md)
  if (AToken.Kind <> tkCharLiteral) or (AToken.Suffix <> '') or
    ((AToken.LiteralPrefix <> lpNone) and (AToken.LiteralPrefix <> lpUpperL)) then
    Exit;
  LIsWide := AToken.LiteralPrefix = lpUpperL;

  // Shape: [L] '\'' body '\''; LIndex = first body char, LLast = last
  LText := AToken.Spelling;
  if LIsWide then
    LIndex := 3
  else
    LIndex := 2;
  if (Length(LText) < LIndex) or (LText[LIndex - 1] <> '''') or
    (LText[Length(LText)] <> '''') then
    Exit;
  LLast := Length(LText) - 1;

  // A narrow numeric escape is one byte; a wide one is a code unit whose fit
  // to the target's wchar_t SEM checks (the parser knows no target width)
  if LIsWide then
    LLimit := $FFFFFFFF
  else
    LLimit := $FF;

  LWarning := '';
  LCount := 0;
  LMulti := 0;
  LElement := 0;
  while LIndex <= LLast do
  begin
    // One element: an escape, or one source character (a code point)
    if LText[LIndex] = '\' then
    begin
      Inc(LIndex);
      // A '\' cannot end the body: it would have escaped the closing quote
      // (an earlier escape cleared AReason, so it is set again here)
      if LIndex > LLast then
      begin
        AReason := RSComCharNotPlain;
        Exit;
      end;
      if not DoEscapeValue(LText, LLast, LIndex, LLimit, LElement, LIsNumeric,
        LWarning, AReason) then
        Exit;
    end
    else
    begin
      LElement := DoCodePointAt(LText, LIndex);
      LIsNumeric := False;
    end;

    // C++23: a narrow element no single byte encodes is ill-formed (e-acute
    // as a source character, '\u00E9'); a numeric escape is at most $FF
    if (not LIsWide) and (not LIsNumeric) and (LElement > $7F) then
    begin
      AReason := RSComCharTooLarge;
      Exit;
    end;
    Inc(LCount);

    // Multi-char value (clang): each element's byte shifted in, 32 bits kept
    LMulti := ((LMulti shl 8) or (LElement and $FF)) and $FFFFFFFF;
  end;

  if LCount = 0 then
  begin
    AReason := RSComCharEmpty;
    Exit;
  end;
  if LIsWide then
  begin
    if LCount > 1 then
    begin
      AReason := RSComCharWideMulti;
      Exit;
    end;
    AValue := LElement;
  end
  else if LCount = 1 then
    AValue := LElement
  else
  begin
    AValue := LMulti;
    AIsMultiChar := True;
    // F66: clang warns on every multi-char literal (-Wmultichar), and again
    // past 4 elements; PaskalCPP names one, the first warning kept first
    if LWarning = '' then
    begin
      if LCount > 4 then
        LWarning := RSComCharTooLong
      else
        LWarning := RSComCharMulti;
    end;
  end;

  if LWarning <> '' then
  begin
    AReason := LWarning;
    Exit(csWarning);
  end;
  AReason := '';
  Result := csOk;
end;

class function TPCCString.IsEscapeStart(const AChar: Char): Boolean;
begin
  // DoEscapeValue's cases; every other character is an unknown escape
  case AChar of
    '"', '''', '?', '\',
    'a', 'b', 'f', 'n', 'r', 't', 'v', 'e', 'E',
    '0'..'7', 'o', 'x', 'u', 'U', 'N':
      Result := True;
  else
    Result := False;
  end;
end;

class function TPCCString.CppSpelling(const AText: string): string;
var
  LBuilder: TStringBuilder;
  LIndex: Integer;
  LNext: Integer;
  LLength: Integer;

  // The index just past a splice starting at AAt ('\', then optional space /
  // tab / FF / VT, then CR LF, LF or CR); AAt itself when none starts there
  function DoSpliceEnd(const AAt: Integer): Integer;
  var
    LP: Integer;
  begin
    Result := AAt;
    if (AAt > LLength) or (AText[AAt] <> '\') then
      Exit;
    LP := AAt + 1;
    while (LP <= LLength) and CharInSet(AText[LP], [' ', #9, #11, #12]) do
      Inc(LP);
    if LP > LLength then
      Exit;
    if AText[LP] = #13 then
    begin
      Inc(LP);
      if (LP <= LLength) and (AText[LP] = #10) then
        Inc(LP);
      Result := LP;
    end
    else if AText[LP] = #10 then
      Result := LP + 1;
  end;

begin
  // Splices go first (phase 2 before escapes): a '\' that starts one is not
  // an escape. An escape's next character is read past any splices between
  // them; an unknown one loses its '\', every other character is copied
  LLength := Length(AText);
  LBuilder := TStringBuilder.Create(LLength);
  try
    LIndex := 1;
    while LIndex <= LLength do
    begin
      if AText[LIndex] <> '\' then
      begin
        LBuilder.Append(AText[LIndex]);
        Inc(LIndex);
        Continue;
      end;

      // A splice: copied as written
      LNext := DoSpliceEnd(LIndex);
      if LNext > LIndex then
      begin
        LBuilder.Append(AText, LIndex - 1, LNext - LIndex);
        LIndex := LNext;
        Continue;
      end;

      // An escape: find its character past the splices after the '\'
      LNext := LIndex + 1;
      while DoSpliceEnd(LNext) > LNext do
        LNext := DoSpliceEnd(LNext);
      if (LNext <= LLength) and (not IsEscapeStart(AText[LNext])) then
      begin
        // Unknown: the splices are kept, the '\' goes; the character is
        // copied by the next round
        LBuilder.Append(AText, LIndex, LNext - LIndex - 1);
        LIndex := LNext;
      end
      else
      begin
        // Known (or the text ends): '\', the splices and the character as
        // written, so a '\\' is never read as two escapes
        if LNext <= LLength then
          Inc(LNext);
        LBuilder.Append(AText, LIndex - 1, LNext - LIndex);
        LIndex := LNext;
      end;
    end;
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

const
  { PC_FLOAT_PRECISION }
  // Significand bits per format, the hidden bit included
  PC_FLOAT_PRECISION: array[TPCFloatFormat] of Integer = (53, 24);

  { PC_FLOAT_MIN_EXP }
  // Exponent of the smallest normal value per format
  PC_FLOAT_MIN_EXP: array[TPCFloatFormat] of Integer = (-1022, -126);

  { PC_FLOAT_MAX_EXP }
  // Exponent of the largest finite value per format
  PC_FLOAT_MAX_EXP: array[TPCFloatFormat] of Integer = (1023, 127);

  { PC_FLOAT_EXP_CAP }
  // A parsed exponent saturates here: any exponent this large is past every
  // format's range, so the cap never changes a result
  PC_FLOAT_EXP_CAP: Int64 = 1000000000000000;

  { PC_FLOAT_DEC_OVERFLOW_EXP }
  // A decimal value of at least 10^309 (> 2^1024) overflows every format
  PC_FLOAT_DEC_OVERFLOW_EXP = 309;

  { PC_FLOAT_DEC_ZERO_EXP }
  // A decimal value below 10^-400 (< 2^-1075, half the smallest binary64
  // denormal) rounds to 0 in every format
  PC_FLOAT_DEC_ZERO_EXP = -400;

{ TPCFloatDecoder }

class procedure TPCFloatDecoder.DoTrim(var AValue: TPCBigNat);
var
  LLength: Integer;
begin
  LLength := Length(AValue);
  while (LLength > 0) and (AValue[LLength - 1] = 0) do
    Dec(LLength);
  SetLength(AValue, LLength);
end;

class procedure TPCFloatDecoder.DoMulAdd(var AValue: TPCBigNat; const AMul: Cardinal;
  const AAdd: Cardinal);
var
  LI: Integer;
  LCarry: UInt64;
  LProduct: UInt64;
begin
  // AValue := AValue * AMul + AAdd, in place. Each step fits UInt64:
  // (2^32 - 1) * (2^32 - 1) + (2^32 - 1) < 2^64
  LCarry := AAdd;
  for LI := 0 to High(AValue) do
  begin
    LProduct := UInt64(AValue[LI]) * UInt64(AMul) + LCarry;
    AValue[LI] := Cardinal(LProduct and $FFFFFFFF);
    LCarry := LProduct shr 32;
  end;
  if LCarry <> 0 then
  begin
    SetLength(AValue, Length(AValue) + 1);
    AValue[High(AValue)] := Cardinal(LCarry);
  end;
end;

class function TPCFloatDecoder.DoBitLength(const AValue: TPCBigNat): Int64;
var
  LTop: Cardinal;
begin
  Result := 0;
  if Length(AValue) = 0 then
    Exit;
  Result := Int64(Length(AValue) - 1) * 32;
  LTop := AValue[High(AValue)];
  while LTop <> 0 do
  begin
    Inc(Result);
    LTop := LTop shr 1;
  end;
end;

class function TPCFloatDecoder.DoShl(const AValue: TPCBigNat; const ABits: Int64): TPCBigNat;
var
  LLimbs: Integer;
  LBits: Integer;
  LI: Integer;
  LWide: UInt64;
  LCarry: Cardinal;
  LResult: TPCBigNat;
begin
  // AValue * 2^ABits (ABits >= 0) as a NEW array: dynamic arrays share
  // storage on assignment, so a copy is always made through here. Built in a
  // local: a managed Result may alias the caller's destination, which may be
  // the array AValue refers to
  LResult := nil;
  if Length(AValue) > 0 then
  begin
    LLimbs := Integer(ABits div 32);
    LBits := Integer(ABits mod 32);
    SetLength(LResult, Length(AValue) + LLimbs + 1);
    for LI := 0 to High(LResult) do
      LResult[LI] := 0;
    LCarry := 0;
    for LI := 0 to High(AValue) do
    begin
      LWide := UInt64(AValue[LI]) shl LBits;
      LResult[LI + LLimbs] := Cardinal(LWide and $FFFFFFFF) or LCarry;
      LCarry := Cardinal(LWide shr 32);
    end;
    LResult[Length(AValue) + LLimbs] := LCarry;
    DoTrim(LResult);
  end;
  Result := LResult;
end;

class function TPCFloatDecoder.DoCompare(const ALeft: TPCBigNat;
  const ARight: TPCBigNat): Integer;
var
  LI: Integer;
begin
  // Both trimmed: the longer one is larger
  if Length(ALeft) <> Length(ARight) then
  begin
    if Length(ALeft) < Length(ARight) then
      Exit(-1);
    Exit(1);
  end;
  for LI := High(ALeft) downto 0 do
  begin
    if ALeft[LI] <> ARight[LI] then
    begin
      if ALeft[LI] < ARight[LI] then
        Exit(-1);
      Exit(1);
    end;
  end;
  Result := 0;
end;

class procedure TPCFloatDecoder.DoSub(var ALeft: TPCBigNat; const ARight: TPCBigNat);
var
  LI: Integer;
  LBorrow: Int64;
  LDiff: Int64;
begin
  // ALeft := ALeft - ARight, in place; the caller guarantees ALeft >= ARight
  LBorrow := 0;
  for LI := 0 to High(ALeft) do
  begin
    LDiff := Int64(ALeft[LI]) - LBorrow;
    if LI <= High(ARight) then
      LDiff := LDiff - Int64(ARight[LI]);
    if LDiff < 0 then
    begin
      LDiff := LDiff + $100000000;
      LBorrow := 1;
    end
    else
      LBorrow := 0;
    ALeft[LI] := Cardinal(LDiff);
  end;
  DoTrim(ALeft);
end;

class function TPCFloatDecoder.DoPow10(const AExp: Int64): TPCBigNat;
var
  LI: Int64;
  LResult: TPCBigNat;
begin
  // 10^AExp, AExp >= 0 (bounded by Decode's early outs); built in a fresh
  // local, never in a Result that may alias the caller's destination
  SetLength(LResult, 1);
  LResult[0] := 1;
  LI := 0;
  while LI < AExp do
  begin
    DoMulAdd(LResult, 10, 0);
    Inc(LI);
  end;
  Result := LResult;
end;

class function TPCFloatDecoder.DoBitLength64(const AValue: UInt64): Integer;
var
  LValue: UInt64;
begin
  Result := 0;
  LValue := AValue;
  while LValue <> 0 do
  begin
    Inc(Result);
    LValue := LValue shr 1;
  end;
end;

class function TPCFloatDecoder.DoMakeDouble(const ASignificand: UInt64;
  const AScale: Int64): Double;
var
  LLength: Integer;
  LTopExp: Int64;
  LSignificand: UInt64;
  LBits: UInt64;
begin
  // ASignificand * 2^AScale is exactly a binary64 value (DoRound guarantees
  // it: ASignificand < 2^53, a binary32 value is a normal binary64): its IEEE
  // bit pattern is built directly, no RTL arithmetic that could round
  Result := 0.0;
  if ASignificand = 0 then
    Exit;
  LLength := DoBitLength64(ASignificand);
  LTopExp := LLength - 1 + AScale;
  if LTopExp >= -1022 then
  begin
    // normal: the leading 1 moves to bit 52 and is dropped (hidden bit)
    LSignificand := ASignificand shl (53 - LLength);
    LBits := (UInt64(LTopExp + 1023) shl 52) or
      (LSignificand and ((UInt64(1) shl 52) - 1));
  end
  else
  begin
    // binary64 denormal (AScale = -1074): the significand is the fraction
    // field as it stands, the exponent field 0
    LBits := ASignificand shl Integer(AScale + 1074);
  end;
  Move(LBits, Result, SizeOf(Double));
end;

class function TPCFloatDecoder.DoRound(const ANum: TPCBigNat; const ADen: TPCBigNat;
  const AFormat: TPCFloatFormat; out AValue: Double): TPCFloatStatus;
var
  LPrecision: Integer;
  LExp: Int64;
  LScale: Int64;
  LRem: TPCBigNat;
  LDen: TPCBigNat;
  LShifted: TPCBigNat;
  LBit: Integer;
  LSignificand: UInt64;
  LCmp: Integer;
begin
  // ANum / ADen (> 0) -> the nearest value of AFormat, ties to even
  AValue := 0.0;
  LPrecision := PC_FLOAT_PRECISION[AFormat];

  // LExp = floor(log2(ANum / ADen)). The bit lengths put the quotient in
  // (2^(LExp - 1), 2^(LExp + 1)); one comparison picks the side
  LExp := DoBitLength(ANum) - DoBitLength(ADen);
  if LExp >= 0 then
    LCmp := DoCompare(ANum, DoShl(ADen, LExp))
  else
    LCmp := DoCompare(DoShl(ANum, -LExp), ADen);
  if LCmp < 0 then
    Dec(LExp);

  // Weight of the significand's last bit: LPrecision - 1 bits below the
  // leading one, held at the denormal scale below the smallest normal
  if LExp < PC_FLOAT_MIN_EXP[AFormat] then
    LScale := PC_FLOAT_MIN_EXP[AFormat] - (LPrecision - 1)
  else
    LScale := LExp - (LPrecision - 1);
  if LScale >= 0 then
  begin
    LRem := DoShl(ANum, 0);
    LDen := DoShl(ADen, LScale);
  end
  else
  begin
    LRem := DoShl(ANum, -LScale);
    LDen := DoShl(ADen, 0);
  end;

  // Long division one bit at a time; the quotient is below 2^LPrecision
  // (the value is below 2^(LExp + 1) and LScale >= LExp - (LPrecision - 1))
  LSignificand := 0;
  for LBit := LPrecision - 1 downto 0 do
  begin
    LShifted := DoShl(LDen, LBit);
    if DoCompare(LRem, LShifted) >= 0 then
    begin
      DoSub(LRem, LShifted);
      LSignificand := LSignificand or (UInt64(1) shl LBit);
    end;
  end;

  // Round by the remainder: above half goes up, exactly half goes to even
  LCmp := DoCompare(DoShl(LRem, 1), LDen);
  if (LCmp > 0) or ((LCmp = 0) and ((LSignificand and 1) = 1)) then
    Inc(LSignificand);
  if LSignificand = (UInt64(1) shl LPrecision) then
  begin
    // the rounding carried out of the significand: one bit up the scale
    LSignificand := LSignificand shr 1;
    Inc(LScale);
  end;

  if (LSignificand <> 0) and
    (DoBitLength64(LSignificand) - 1 + LScale > PC_FLOAT_MAX_EXP[AFormat]) then
    Exit(fsOverflow);
  AValue := DoMakeDouble(LSignificand, LScale);
  Result := fsOk;
end;

class function TPCFloatDecoder.Decode(const ANumeric: string;
  const AFormat: TPCFloatFormat; out AValue: Double): TPCFloatStatus;
var
  LLength: Integer;
  LIndex: Integer;
  LIsHex: Boolean;
  LRadix: Cardinal;
  LChar: Char;
  LDigit: Cardinal;
  LMantissa: TPCBigNat;
  LDigits: Integer;
  LFracDigits: Integer;
  LSigDigits: Integer;
  LSeenDot: Boolean;
  LExpNegative: Boolean;
  LExpDigits: Integer;
  LExpValue: Int64;
  LScaleExp: Int64;
  LBitLength: Int64;
  LI: Int64;
  LNum: TPCBigNat;
  LDen: TPCBigNat;
  LOne: TPCBigNat;
begin
  AValue := 0.0;
  LLength := Length(ANumeric);
  LIndex := 1;
  LIsHex := (LLength >= 2) and (ANumeric[1] = '0') and CharInSet(ANumeric[2], ['x', 'X']);
  if LIsHex then
  begin
    LRadix := 16;
    LIndex := 3;
  end
  else
    LRadix := 10;

  // Significand: every digit before and after the point goes into one
  // integer; LFracDigits counts those after it, LSigDigits those from the
  // first non-zero digit on
  LMantissa := nil;
  LDigits := 0;
  LFracDigits := 0;
  LSigDigits := 0;
  LSeenDot := False;
  while LIndex <= LLength do
  begin
    LChar := ANumeric[LIndex];
    if LChar = '.' then
    begin
      if LSeenDot then
        Exit(fsMalformed);
      LSeenDot := True;
      Inc(LIndex);
      Continue;
    end;
    if CharInSet(LChar, ['0'..'9']) then
      LDigit := Ord(LChar) - Ord('0')
    else if (LRadix = 16) and CharInSet(LChar, ['a'..'f']) then
      LDigit := Ord(LChar) - Ord('a') + 10
    else if (LRadix = 16) and CharInSet(LChar, ['A'..'F']) then
      LDigit := Ord(LChar) - Ord('A') + 10
    else
      Break;
    DoMulAdd(LMantissa, LRadix, LDigit);
    Inc(LDigits);
    if LSeenDot then
      Inc(LFracDigits);
    if (LSigDigits > 0) or (LDigit <> 0) then
      Inc(LSigDigits);
    Inc(LIndex);
  end;
  if LDigits = 0 then
    Exit(fsMalformed);

  // Exponent: p (hex, required) or e (decimal, optional), decimal digits
  LExpValue := 0;
  if (LIndex <= LLength) and
    ((LIsHex and CharInSet(ANumeric[LIndex], ['p', 'P'])) or
    ((not LIsHex) and CharInSet(ANumeric[LIndex], ['e', 'E']))) then
  begin
    Inc(LIndex);
    LExpNegative := False;
    if (LIndex <= LLength) and CharInSet(ANumeric[LIndex], ['+', '-']) then
    begin
      LExpNegative := ANumeric[LIndex] = '-';
      Inc(LIndex);
    end;
    LExpDigits := 0;
    while (LIndex <= LLength) and CharInSet(ANumeric[LIndex], ['0'..'9']) do
    begin
      if LExpValue < PC_FLOAT_EXP_CAP then
        LExpValue := LExpValue * 10 + (Ord(ANumeric[LIndex]) - Ord('0'));
      Inc(LExpDigits);
      Inc(LIndex);
    end;
    if LExpDigits = 0 then
      Exit(fsMalformed);
    if LExpNegative then
      LExpValue := -LExpValue;
  end
  else if LIsHex then
    Exit(fsMalformed);   // a hex float needs its p exponent
  if LIndex <= LLength then
    Exit(fsMalformed);

  // Zero, whatever the exponent
  if Length(LMantissa) = 0 then
    Exit(fsOk);

  SetLength(LOne, 1);
  LOne[0] := 1;
  LDen := LOne;
  if LIsHex then
  begin
    // value = mantissa * 2^LScaleExp, in [2^(LBitLength - 1 + LScaleExp),
    // 2^(LBitLength + LScaleExp))
    LScaleExp := LExpValue - 4 * Int64(LFracDigits);
    LBitLength := DoBitLength(LMantissa);
    if LBitLength - 1 + LScaleExp > PC_FLOAT_MAX_EXP[AFormat] then
      Exit(fsOverflow);
    // below half the smallest denormal (2^(MinExp - Precision)): rounds to 0
    if LBitLength + LScaleExp <= PC_FLOAT_MIN_EXP[AFormat] - PC_FLOAT_PRECISION[AFormat] then
      Exit(fsOk);
    if LScaleExp >= 0 then
      LNum := DoShl(LMantissa, LScaleExp)
    else
    begin
      LNum := DoShl(LMantissa, 0);
      LDen := DoShl(LOne, -LScaleExp);
    end;
  end
  else
  begin
    // value = mantissa * 10^LScaleExp, in [10^(LSigDigits - 1 + LScaleExp),
    // 10^(LSigDigits + LScaleExp))
    LScaleExp := LExpValue - LFracDigits;
    if LSigDigits - 1 + LScaleExp >= PC_FLOAT_DEC_OVERFLOW_EXP then
      Exit(fsOverflow);
    if LSigDigits + LScaleExp <= PC_FLOAT_DEC_ZERO_EXP then
      Exit(fsOk);
    LNum := DoShl(LMantissa, 0);
    if LScaleExp >= 0 then
    begin
      LI := 0;
      while LI < LScaleExp do
      begin
        DoMulAdd(LNum, 10, 0);
        Inc(LI);
      end;
    end
    else
      LDen := DoPow10(-LScaleExp);
  end;

  Result := DoRound(LNum, LDen, AFormat, AValue);
end;

{ TPCSourceFiles }

class function TPCSourceFiles.LanguageOf(const AFilename: string; out ALanguage: TPCSourceLanguage): Boolean;
var
  LExtension: string;
  LRow: TPCSourceExtRow;
begin
  // Exact case, as clang reads the name: '.c' is C, '.C' is C++
  ALanguage := slCpp;
  LExtension := ExtractFileExt(AFilename);
  for LRow in PC_SOURCE_EXTS do
  begin
    if LRow.ExtText = LExtension then
    begin
      ALanguage := LRow.Language;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TPCSourceFiles.ExtensionsText(): string;
var
  LRow: TPCSourceExtRow;
begin
  Result := '';
  for LRow in PC_SOURCE_EXTS do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + LRow.ExtText;
  end;
end;

{ TPCLibraryName }

class function TPCLibraryName.IsName(const AText: string): Boolean;
const
  { PC_LIB_FILE_SUFFIXES }
  PC_LIB_FILE_SUFFIXES: array[0..3] of string = ('.a', '.lib', '.so', '.dll');
var
  LChar: Char;
  LLower: string;
  LSuffix: string;
begin
  if AText = '' then
    Exit(False);

  // A name holds no blank, control character, path separator or drive colon
  for LChar in AText do
  begin
    if (LChar <= ' ') or (LChar = '/') or (LChar = '\') or (LChar = ':') then
      Exit(False);
  end;

  // A library FILE's suffix means the user named a file, not a library
  LLower := AText.ToLower();
  for LSuffix in PC_LIB_FILE_SUFFIXES do
  begin
    if LLower.EndsWith(LSuffix) then
      Exit(False);
  end;

  Result := True;
end;

{ TPCResDataKey }

class function TPCResDataKey.SymbolOf(const AKey: string): string;
const
  { PC_HEX_DIGITS }
  PC_HEX_DIGITS: string = '0123456789abcdef';
var
  LBytes: TBytes;
  LByte: Byte;
  LBuilder: TStringBuilder;
begin
  // The key's UTF-8 bytes (a valid key: SEM's SM0119), two digits each
  LBytes := TEncoding.UTF8.GetBytes(AKey);
  LBuilder := TStringBuilder.Create(Length(PC_RESDATA_KEY_SYMBOL_PREFIX) + Length(LBytes) * 2);
  try
    LBuilder.Append(PC_RESDATA_KEY_SYMBOL_PREFIX);
    for LByte in LBytes do
    begin
      LBuilder.Append(PC_HEX_DIGITS.Chars[LByte shr 4]);
      LBuilder.Append(PC_HEX_DIGITS.Chars[LByte and $0F]);
    end;
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

class function TPCResDataKey.TryKeyOf(const ASymbol: string; out AKey: string): Boolean;
var
  LHex: string;
  LBytes: TBytes;
  LI: Integer;
  LHigh: Integer;
  LLow: Integer;

  function DoDigit(const AChar: Char): Integer;
  begin
    // Lowercase only: SymbolOf writes no other digit
    if (AChar >= '0') and (AChar <= '9') then
      Result := Ord(AChar) - Ord('0')
    else if (AChar >= 'a') and (AChar <= 'f') then
      Result := Ord(AChar) - Ord('a') + 10
    else
      Result := -1;
  end;

begin
  AKey := '';
  Result := False;
  if not ASymbol.StartsWith(PC_RESDATA_KEY_SYMBOL_PREFIX) then
    Exit;
  LHex := ASymbol.Substring(Length(PC_RESDATA_KEY_SYMBOL_PREFIX));
  if (LHex = '') or (Length(LHex) mod 2 <> 0) then
    Exit;

  SetLength(LBytes, Length(LHex) div 2);
  for LI := 0 to High(LBytes) do
  begin
    LHigh := DoDigit(LHex.Chars[LI * 2]);
    LLow := DoDigit(LHex.Chars[LI * 2 + 1]);
    if (LHigh < 0) or (LLow < 0) then
      Exit;
    LBytes[LI] := Byte((LHigh shl 4) or LLow);
  end;

  // Strict UTF-8 (it raises on bytes that are no UTF-8): such bytes name no key
  try
    AKey := TEncoding.UTF8.GetString(LBytes);
  except
    on E: Exception do
    begin
      AKey := '';
      Exit;
    end;
  end;
  Result := True;
end;

end.
