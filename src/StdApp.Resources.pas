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

  StdApp.Resources - Shared resource strings

  Central repository of all user-facing message strings used across
  StdApp units. All error messages, warning text, and format strings
  are declared as resourcestring constants for localization readiness
  and clean separation from logic.

  Categories: severity names, error formats, fatal/IO messages,
  VFS messages, VirtualMemory messages.

  Dependencies: none
  Notes: Error code constants are defined in the unit of their concern,
    not here. This unit holds only the message text.
===============================================================================}

unit StdApp.Resources;

{$I StdApp.Defines.inc}

interface

resourcestring

  //--------------------------------------------------------------------------
  // Severity Names
  //--------------------------------------------------------------------------
  RSSeverityHint    = 'Hint';
  RSSeverityWarning = 'Warning';
  RSSeverityError   = 'Error';
  RSSeverityFatal   = 'Fatal';
  RSSeverityNote    = 'Note';
  RSSeverityUnknown = 'Unknown';

  //--------------------------------------------------------------------------
  // Error Format Strings
  //--------------------------------------------------------------------------
  RSErrorFormatSimple              = '%s %s: %s';
  RSErrorFormatWithLocation        = '%s: %s %s: %s';
  RSErrorFormatRelatedSimple       = '  %s: %s';
  RSErrorFormatRelatedWithLocation = '  %s: %s: %s';
  RSErrorFormatSimpleNoCode        = '%s: %s';
  RSErrorFormatWithLocationNoCode  = '%s: %s: %s';

  //--------------------------------------------------------------------------
  // VFS Messages
  //--------------------------------------------------------------------------
  RSVFSOpenFileFailed      = 'Failed to open file: ''%s''';
  RSVFSInvalidMagic        = 'Invalid VFS archive magic signature';
  RSVFSInvalidVersion      = 'Unsupported VFS archive version: %d';
  RSVFSTruncated           = 'VFS archive is truncated or corrupt';
  RSVFSNotOpen             = 'VFS archive is not open';
  RSVFSEntryNotFound       = 'Entry not found in VFS: ''%s''';
  RSVFSScanDirFailed       = 'Failed to scan directory: ''%s''';
  RSVFSEmptyDirectory      = 'Source directory contains no files: ''%s''';
  RSVFSSourceOpenFailed    = 'Failed to open source file for packing: ''%s''';
  RSVFSException           = 'Unexpected exception in VFS: %s';

  //--------------------------------------------------------------------------
  // VirtualMemory Messages
  //--------------------------------------------------------------------------
  RSVMAllocSizeZero          = 'Cannot allocate a zero-size buffer';
  RSVMCreateMappingFailed    = 'CreateFileMapping failed (error %d)';
  RSVMMappingNameExists      = 'Mapping name "%s" already exists';
  RSVMMapViewFailed          = 'MapViewOfFile failed (error %d)';
  RSVMAllocException         = 'Allocate exception: %s';
  RSVMSharedNameEmpty        = 'OpenShared: mapping name must not be empty';
  RSVMOpenMappingFailed      = 'OpenFileMapping failed for "%s" (error %d)';
  RSVMMapViewNamedFailed     = 'MapViewOfFile failed for "%s" (error %d)';
  RSVMSharedException        = 'OpenShared exception for "%s": %s';
  RSVMUseAllocate            = 'Use Allocate() for anonymous buffers, not Open()';
  RSVMOpenFileFailed         = 'Cannot open file "%s" (error %d)';
  RSVMFileEmpty              = 'File "%s" is empty -- cannot memory-map';
  RSVMCreateMappingNamedFailed = 'CreateFileMapping failed for "%s" (error %d)';
  RSVMOpenException          = 'Open exception for "%s": %s';
  RSVMLoadAlignmentFailed    = 'File size (%d) is not aligned to element size (%d)';
  RSVMLoadException          = 'LoadFromFile exception for "%s": %s';
  RSVMFlushFailed            = 'FlushViewOfFile failed (error %d)';
  RSVMGrowNotAnonymous       = 'Grow is only valid for anonymous (vmAllocate) buffers';
  RSVMGrowNotShared          = 'Grow is not valid for shared consumer mappings';
  RSVMGrowMappingFailed      = 'Grow: CreateFileMapping failed (error %d)';
  RSVMGrowMapViewFailed      = 'Grow: MapViewOfFile failed (error %d)';
  RSVMGrowException          = 'Grow exception: %s';

  //--------------------------------------------------------------------------
  // Crypto Messages
  //--------------------------------------------------------------------------
  RSCryFileNotFound  = 'File not found: %s';
  RSCryFileError     = 'File error: %s';
  RSCryRandomFailed  = 'Secure random generation failed (BCryptGenRandom)';
  RSCryNoSecretKey   = 'No secret key present in key pair';
  RSCryNoPublicKey   = 'No public key present in key pair';
  RSCryBadKeyFile    = 'Invalid or unrecognized key data: %s';
  RSCryBadSigFile    = 'Invalid signature file: %s';
  RSCryKeyIdMismatch = 'Signature key id does not match the public key: %s';
  RSCryVerifyFailed  = 'Signature verification FAILED for: %s';
  RSCrySecKeyComment     = 'apppacker secret key %s';
  RSCrySigDefaultComment = 'signature from apppacker secret key %s';

  //--------------------------------------------------------------------------
  // Packer Messages
  //--------------------------------------------------------------------------
  RSPakManifestNotFound = 'Manifest not found: %s';
  RSPakParseError       = 'Manifest parse error at line %d: %s';
  RSPakNoOutput         = 'Manifest is missing the output: key';
  RSPakSourceMissing    = 'Source directory not found: %s';
  RSPakSourceScan       = 'scan: %s (prefix: %s)';
  RSPakMatched          = 'matched: %d file(s)';
  RSPakNoFiles          = 'Nothing to pack (no files matched include/exclude rules)';
  RSPakAdd              = 'add: %s';
  RSPakDone             = 'done: %d file(s) -> %s';
  RSPakChecksum         = 'checksum: %s';
  RSPakSigned           = 'signed: %s';
  RSPakSecKeyInArchive  = 'FATAL: the configured secret key file is matched by include rules: %s';
  RSPakZipError         = 'Archive build failed: %s';
  RSPakNoSecKey         = 'sign: block present but seckey: is missing';

  //--------------------------------------------------------------------------
  // AppPacker CLI Messages
  //--------------------------------------------------------------------------
  RSCliBanner = 'AppPacker™ %s - manifest-driven release packer';
  RSCliUsage = 'Usage:'#13#10 +
    '  AppPacker <manifest.yml>'#13#10 +
    '  AppPacker pack <manifest.yml>'#13#10 +
    '  AppPacker keygen <basepath>'#13#10 +
    '  AppPacker verify <file> <pubkey-file-or-string>';
  RSCliPacking       = 'packing: %s %s';
  RSCliKeyExists     = 'REFUSED: secret key already exists, will not overwrite: %s';
  RSCliKeygenDone    = 'keypair written: %s / %s';
  RSCliKeyId         = 'key id: %s';
  RSCliPubKey        = 'public key: %s';
  RSCliKeyBackupHint = 'BACK UP the .key file now. It is NOT encrypted. Keep it OUTSIDE any repo.';
  RSCliVerifyOk      = 'verified OK: %s';

//--------------------------------------------------------------------------
  // PaskalCPP.ZigBuild - status, error, and warning messages
  //--------------------------------------------------------------------------
  RSZigBuildTargetPlatform = 'Target platform: %s';
  RSZigBuildOptimizeLevel  = 'Optimize level: %s';
  RSZigBuildSubsystem      = 'Subsystem: %s';
  RSZigBuildSaving         = 'Saving build file...';
  RSZigBuildBuilding       = 'Building %s...';
  RSZigBuildSucceeded      = 'Build succeeded.';
  RSZigBuildFailedWithCode = 'Build failed with exit code %d.';
  RSZigBuildOutput         = 'Output: %s';
  RSZigBuildCopying        = 'Copying %s...';
  RSZigBuildZigNotFound    = 'Zig compiler not found: %s';
  RSZigBuildFailed         = 'Zig build failed with exit code %d.';
  RSZigBuildCannotRunLib   = 'Cannot run a library target.';
  RSZigBuildCannotRunCross = 'Cannot run cross-compiled target: %s';
  RSZigBuildNoProjectName  = 'No project name specified.';
  RSZigBuildExeNotFound    = 'Executable not found: %s';
  RSZigBuildRunFailed      = 'Program exited with code %d.';
  RSZigBuildRunning        = 'Running %s...';
  { RSZigBuildRunStartFailed }
  RSZigBuildRunStartFailed = 'Cannot start %s: %s';
  { RSZigBuildZigStartFailed }
  RSZigBuildZigStartFailed = 'Cannot start zig (%s): %s';
  RSZigBuildFileNotFound   = 'Build file not found: %s';
  RSZigBuildSaveFailed     = 'Failed to save build file: %s';
  RSZigBuildNoOutputPath   = 'No output path specified.';
  RSZigBuildNoSources      = 'No source files specified.';
  { RSZigBuildManifestFailed }
  RSZigBuildManifestFailed = 'Failed to add manifest to executable: %s';
  { RSZigBuildIconNotFound }
  RSZigBuildIconNotFound   = 'Icon file not found: %s';
  { RSZigBuildIconFailed }
  RSZigBuildIconFailed = 'Failed to apply icon %s: %s';
  { RSZigBuildVersionInfoFailed }
  RSZigBuildVersionInfoFailed = 'Failed to apply version info: %s';
  { RSZigBuildIconNotWindows }
  RSZigBuildIconNotWindows = 'Icon ignored: target %s does not take Windows resources';
  { RSZigBuildVersionInfoNotWindows }
  RSZigBuildVersionInfoNotWindows = 'Version info ignored: target %s does not take Windows resources';
  { RSZigBuildIconNotExe }
  RSZigBuildIconNotExe = 'Icon ignored: only an executable takes an icon';
  { RSZigBuildVersionInfoNotLib }
  RSZigBuildVersionInfoNotLib = 'Version info ignored: a static library takes no resources';
  RSZigBuildPublishing     = 'Publishing %s to %s...';
  RSZigBuildPublishError   = 'Failed to publish to %s: %s';
  { RSZigBuildDiagFilePrepare }
  RSZigBuildDiagFilePrepare = 'Cannot prepare the diagnostics file %s: %s';
  { RSZigBuildDiagFileIsDir }
  RSZigBuildDiagFileIsDir = 'a directory is in the way';
  { RSZigBuildClearFailed }
  RSZigBuildClearFailed = 'Failed to clear %s: %s';
  { RSZigBuildClearStillPresent }
  RSZigBuildClearStillPresent = 'the directory is still present';
  { RSZigBuildClearFileStillPresent }
  RSZigBuildClearFileStillPresent = 'the file is still present';
  { RSZigBuildClearLink }
  RSZigBuildClearLink = 'it is a link (junction or symbolic link): nothing deleted through it';
  { RSZigBuildCopyFailed }
  RSZigBuildCopyFailed = 'Failed to copy %s: %s';
  { RSZigBuildLoadFailed }
  RSZigBuildLoadFailed = 'Failed to read build file %s: %s';
  { RSZigBuildEmptySource }
  RSZigBuildEmptySource = 'An empty %s was given: nothing to copy';
  { RSZigBuildCopyCollision }
  RSZigBuildCopyCollision = '%s and %s would both be copied to %s: neither is copied';
  { RSZigBuildSourceMissing }
  RSZigBuildSourceMissing = 'File to copy not found: %s';
  { RSZigBuildStaleRemoving }
  RSZigBuildStaleRemoving = 'Removing %s: an earlier build put it there, this build does not produce it';
  { RSZigBuildStaleRemove }
  RSZigBuildStaleRemove = 'Could not remove %s (an earlier build put it there, this build does not produce it): %s';
  { RSZigBuildInstalledRecordRead }
  RSZigBuildInstalledRecordRead = 'Could not read the record of earlier build files %s: files it names are not removed: %s';
  { RSZigBuildInstalledRecordWrite }
  RSZigBuildInstalledRecordWrite = 'Could not write the record of build files %s: a later build cannot remove them: %s';
  { RSZigBuildLegacyRecordRemove }
  RSZigBuildLegacyRecordRemove = 'Could not remove the old record %s (replaced by %s): %s';
  { RSZigBuildBadTarget }
  RSZigBuildBadTarget = 'Unknown target "%s": a target is <arch>-<os>[-<abi>] in zig''s names, e.g. x86_64-windows-gnu';
  { RSZigBuildUnknownLine }
  RSZigBuildUnknownLine = 'Line %d of %s is not a line PaskalCPP writes; it is ignored: %s';
  { RSZigBuildConfigLoadFailed }
  RSZigBuildConfigLoadFailed = 'Cannot read %s (left unchanged; using the default toolchain path): %s';
  { RSZigBuildConfigSaveFailed }
  RSZigBuildConfigSaveFailed = 'Cannot write %s: %s';
  { RSZigBuildConfigBadToolchain }
  RSZigBuildConfigBadToolchain = '%s: toolchain_path ''%s'' is not a usable path (using the default toolchain path): %s';
  { RSZigBuildConfigNotSaved }
  RSZigBuildConfigNotSaved = 'Not saving %s: it could not be read, so it is left unchanged';
  { RSZigBuildBadPath }
  RSZigBuildBadPath = 'Invalid %s "%s": %s';
  { RSZigBuildBadProjectName }
  RSZigBuildBadProjectName = 'Invalid project name "%s": a project name must be a valid file name';
  { RSZigBuildRootTooLong }
  RSZigBuildRootTooLong = 'Output folder too long for the zig toolchain (%d characters, the limit is %d): %s';
  { RSZigBuildWhatOutputPath }
  RSZigBuildWhatOutputPath = 'output path';
  { RSZigBuildWhatSourceFile }
  RSZigBuildWhatSourceFile = 'source file';
  { RSZigBuildNotSource }
  RSZigBuildNotSource = 'Not a source file the toolchain compiles: %s (the extension, exact case, must be one of %s)';
  { RSZigBuildWhatSourceBase }
  RSZigBuildWhatSourceBase = 'source base path';
  { RSZigBuildWhatIncludePath }
  RSZigBuildWhatIncludePath = 'include path';
  { RSZigBuildWhatLibraryPath }
  RSZigBuildWhatLibraryPath = 'library path';
  { RSZigBuildWhatCopyDLL }
  RSZigBuildWhatCopyDLL = 'DLL to copy';
  { RSZigBuildWhatPublishSource }
  RSZigBuildWhatPublishSource = 'file to publish';
  { RSZigBuildWhatPublishDest }
  RSZigBuildWhatPublishDest = 'publish directory';
  { RSZigBuildWhatExeIcon }
  RSZigBuildWhatExeIcon = 'icon file';
  { RSZigBuildWhatExecutable }
  RSZigBuildWhatExecutable = 'executable';
  { RSZigBuildWhatBuildFile }
  RSZigBuildWhatBuildFile = 'build file';
  { RSZigBuildWhatToolchainPath }
  RSZigBuildWhatToolchainPath = 'toolchain path';
  { RSZigBuildWhatBuildConfig }
  RSZigBuildWhatBuildConfig = 'build config file';

  { RSComVocNotShared }
  RSComVocNotShared = 'Token "%s" is registered by PaskalCPP and C++ but is missing from the shared-token list';
  { RSComVocStaleShared }
  RSComVocStaleShared = 'Shared-token list entry "%s" is not registered by both PaskalCPP and C++';
  { RSComVocKindMismatch }
  RSComVocKindMismatch = 'Token "%s" has different kinds in the PaskalCPP and C++ tables';
  { RSComVocDuplicate }
  RSComVocDuplicate = 'Token "%s" is registered twice in the %s table';
  { RSComVocTablePaskal }
  RSComVocTablePaskal = 'PaskalCPP';
  { RSComVocTableCpp }
  RSComVocTableCpp = 'C++';
  { RSComVocTableShared }
  RSComVocTableShared = 'shared-token';

  { RSComCStrNotPlain }
  RSComCStrNotPlain = 'Internal error: not a plain narrow string literal';
  { RSComCStrOctalRange }
  RSComCStrOctalRange = 'octal escape sequence out of range';
  { RSComCStrHexRange }
  RSComCStrHexRange = 'hex escape sequence out of range';
  { RSComCStrNoHexDigits }
  RSComCStrNoHexDigits = '\%s used with no following hex digits';
  { RSComCStrDelimEmpty }
  RSComCStrDelimEmpty = 'delimited escape sequence cannot be empty';
  { RSComCStrInvalidDigit }
  RSComCStrInvalidDigit = 'invalid digit ''%s'' in escape sequence';
  { RSComCStrExpectedBrace }
  RSComCStrExpectedBrace = 'expected ''{'' after ''\%s'' escape sequence';
  { RSComCStrExpectedClose }
  RSComCStrExpectedClose = 'expected ''}''';
  { RSComCStrIncompleteUcn }
  RSComCStrIncompleteUcn = 'incomplete universal character name';
  { RSComCStrInvalidUcn }
  RSComCStrInvalidUcn = 'invalid universal character';
  { RSComCStrUnknownName }
  RSComCStrUnknownName = '''%s'' is not a valid Unicode character name';
  { RSComCStrUnknownEscape }
  RSComCStrUnknownEscape = 'unknown escape sequence ''\%s''';
  { RSComCStrNotUtf8 }
  RSComCStrNotUtf8 = 'string value is not valid UTF-8';
  { RSComCharNotPlain }
  RSComCharNotPlain = 'Internal error: not a plain or L character literal';
  { RSComCharEmpty }
  RSComCharEmpty = 'empty character constant';
  { RSComCharTooLarge }
  RSComCharTooLarge = 'character too large for enclosing character literal type';
  { RSComCharWideMulti }
  RSComCharWideMulti = 'wide character literals may not contain multiple characters';
  { RSComCharMulti }
  RSComCharMulti = 'multi-character character constant';
  { RSComCharTooLong }
  RSComCharTooLong = 'character constant too long for its type';

  { RSTksSplitPiece }
  RSTksSplitPiece = 'Internal error: split piece "%s" has no token kind';

  { RSLexUnterminatedString }
  RSLexUnterminatedString = 'Unterminated string or character literal';
  { RSLexUnterminatedRaw }
  RSLexUnterminatedRaw = 'Unterminated raw string literal';
  { RSLexUnterminatedComment }
  RSLexUnterminatedComment = 'Unterminated block comment';
  { RSLexInvalidChar }
  RSLexInvalidChar = 'Invalid character in source: %s';
  { RSLexMalformedNumber }
  RSLexMalformedNumber = 'Malformed numeric literal: %s';
  { RSLexNumberOverflow }
  RSLexNumberOverflow = 'Numeric literal out of range: %s';
  { RSLexNumberSignedOverflow }
  RSLexNumberSignedOverflow = 'Numeric literal out of range: %s does not fit int64, and a decimal literal is unsigned only with a u suffix; write %s';
  { RSLexInvalidOctal }
  RSLexInvalidOctal = 'Invalid digit in octal literal: %s';
  { RSLexHashNotAtLineStart }
  RSLexHashNotAtLineStart = '''%s'' must be the first token on its line';
  { RSLexDirectiveNoName }
  RSLexDirectiveNoName = '''@'' must be followed by a directive name';
  { RSLexRawDelimiter }
  RSLexRawDelimiter = 'Invalid raw string delimiter (at most 16 characters; no space, parenthesis, backslash or control character)';
  { RSLexInvalidUtf8 }
  RSLexInvalidUtf8 = 'Invalid UTF-8 byte sequence';
  { RSLexFileError }
  RSLexFileError = 'Cannot read source file "%s": %s';
  { RSLexCppstartNoCppend }
  RSLexCppstartNoCppend = '''cppstart'' block has no matching ''cppend''';
  { RSLexOctalHint }
  RSLexOctalHint = 'Leading zero: %s is an octal literal';
  { RSLexCppstartTrailingSplice }
  RSLexCppstartTrailingSplice = '''cppstart'' block ends in a line splice that would join the next emitted line';
  { RSLexSpliceWhitespace }
  RSLexSpliceWhitespace = 'Backslash and newline separated by space';
  { RSLexEscapedCommentEnd }
  RSLexEscapedCommentEnd = 'Escaped newline between */ characters at block comment end';
  { RSLexNestedCommentOpen }
  RSLexNestedCommentOpen = '''/*'' within block comment';

  { RSAstDuplicateModule }
  RSAstDuplicateModule = 'Module "%s" is declared more than once';

  { RSAstNotBuiltinToken }
  RSAstNotBuiltinToken = 'Internal error: %s is not a builtin type token';

  { RSAstNoSpelling }
  RSAstNoSpelling = 'Internal error: token kind %s has no spelling';

  { RSAstCanonCycle }
  RSAstCanonCycle = 'Internal error: type "%s" resolves to itself';

  { RSAstSigLength }
  RSAstSigLength = '(string, wstring or array)';
  { RSAstSigType }
  RSAstSigType = '(a type)';
  { RSAstSigWString }
  RSAstSigWString = '(wstring)';
  { RSAstSigNone }
  RSAstSigNone = '()';
  { RSAstSigInt32 }
  RSAstSigInt32 = '(int32)';
  { RSAstSigInt64 }
  RSAstSigInt64 = '(int64)';
  { RSAstSigPointer }
  RSAstSigPointer = '(pointer)';
  { RSAstSigPointerInt64 }
  RSAstSigPointerInt64 = '(pointer, int64)';
  { RSAstSigResize }
  RSAstSigResize = '(dynamic array or string variable, int64)';
  { RSAstSigHeapPtrVar }
  RSAstSigHeapPtrVar = '(record, overlay or C/C++ pointer variable)';
  { RSAstSigHeapPtr }
  RSAstSigHeapPtr = '(record, overlay or C/C++ pointer)';
  { RSAstSigWeak }
  RSAstSigWeak = '(weak T)';
  { RSAstSigString }
  RSAstSigString = '(string)';
  { RSAstSigInt32String }
  RSAstSigInt32String = '(int32, string)';
  { RSAstSigBool }
  RSAstSigBool = '(bool)';
  { RSAstSigInt64Pair }
  RSAstSigInt64Pair = '(int64, int64)';
  { RSAstSigUInt64Pair }
  RSAstSigUInt64Pair = '(uint64, uint64)';
  { RSAstSigFloat64Pair }
  RSAstSigFloat64Pair = '(float64, float64)';
  { RSAstSigStringPair }
  RSAstSigStringPair = '(string, string)';
  { RSAstSigBoolPair }
  RSAstSigBoolPair = '(bool, bool)';
  { RSAstSigPointerPair }
  RSAstSigPointerPair = '(pointer, pointer)';
  { RSAstSigIndexType }
  RSAstSigIndexType = '(integer, a type)';

  { RSCndNeedSymbol }
  RSCndNeedSymbol = '%s needs an identifier';
  { RSCndNoOpener }
  RSCndNoOpener = '%s without a matching @ifdef or @ifndef';
  { RSCndAfterElse }
  RSCndAfterElse = '%s after @else';
  { RSCndUnterminated }
  RSCndUnterminated = '%s is not closed by @endif';
  { RSCndTargetPlace }
  RSCndTargetPlace = '@target must stand in the directive prologue, right after the module header';
  { RSCndTargetInBranch }
  RSCndTargetInBranch = '@target cannot stand inside a conditional branch';
  { RSCndTargetLate }
  RSCndTargetLate = '@target must come before the first conditional directive';
  { RSCndTargetDuplicate }
  RSCndTargetDuplicate = '@target is given more than once';
  { RSCndTargetNeedString }
  RSCndTargetNeedString = '@target needs a plain string literal';
  { RSCndTargetShape }
  RSCndTargetShape = 'Malformed target triple "%s": expected arch-vendor-os-env or arch-os-env';
  { RSCndTargetUnsupported }
  RSCndTargetUnsupported = 'Target "%s" is not supported; supported targets: %s';
  { RSCndTargetMismatch }
  RSCndTargetMismatch = 'Imported module target "%s" differs from the main module target "%s"';
  { RSParExpected }
  RSParExpected = 'expected %s, found ''%s''';
  { RSParEndOfFile }
  RSParEndOfFile = 'end of file';
  { RSParWhatModuleName }
  RSParWhatModuleName = 'a module name';
  { RSParWhatUnitName }
  RSParWhatUnitName = 'a unit name';
  { RSParNeedKind }
  RSParNeedKind = 'expected a module kind (exe, dll, lib, unit), found ''%s''';
  { RSParNameMismatch }
  RSParNameMismatch = 'module name ''%s'' must match its file name ''%s''';
  { RSParUnitMain }
  RSParUnitMain = 'a unit cannot be the main module';
  { RSParUnknownDirective }
  RSParUnknownDirective = 'unknown build directive ''@%s''';
  { RSParDirectiveShape }
  RSParDirectiveShape = '''@%s'' expects %s';
  { RSParShapeNone }
  RSParShapeNone = 'no argument';
  { RSParShapeIdentifier }
  RSParShapeIdentifier = 'an identifier';
  { RSParShapeInteger }
  RSParShapeInteger = 'an integer without a suffix';
  { RSParShapeCString }
  RSParShapeCString = 'a string literal';
  { RSParShapeCStrings }
  RSParShapeCStrings = 'a string literal, then optionally a second one';
  { RSParShapeSeverity }
  RSParShapeSeverity = 'a severity (hint, warn, error, fatal) and a string literal';
  { RSParSeverity }
  RSParSeverity = '''@message'' severity must be hint, warn, error or fatal, found ''%s''';
  { RSParDirectivePlace }
  RSParDirectivePlace = 'build directives stand only in the directive prologue';
  { RSParBadString }
  RSParBadString = 'invalid string literal: %s';
  { RSParBadChar }
  RSParBadChar = 'invalid character literal: %s';
  { RSParNotPlainString }
  RSParNotPlainString = 'only a plain "..." string literal is allowed here';
  { RSParImportPlace }
  RSParImportPlace = 'import must follow the directive prologue, in one import clause';
  { RSParImportCycle }
  RSParImportCycle = 'import cycle: %s';
  { RSParUnitNotFound }
  RSParUnitNotFound = 'unit ''%s'' not found (searched: %s)';
  { RSParImportKind }
  RSParImportKind = '''%s'' is a %s module; only units can be imported';
  { RSParDuplicateImport }
  RSParDuplicateImport = 'duplicate import ''%s''';
  { RSParAfterEnd }
  RSParAfterEnd = 'unexpected ''%s'' after the module''s end';
  { RSParStringWarning }
  RSParStringWarning = 'string literal: %s';
  { RSParCharWarning }
  RSParCharWarning = 'character literal: %s';
  { RSParPathResolve }
  RSParPathResolve = '''@%s'' path ''%s'' cannot be resolved: %s';
  { RSParModulePathResolve }
  RSParModulePathResolve = 'module path ''%s'' cannot be resolved: %s';
  { RSParMainOnly }
  RSParMainOnly = '''@%s'' is set by the main module only; a unit cannot set it';
  { RSParCppTarget }
  RSParCppTarget = 'expected header or source after ''%s'', found ''%s''';
  { RSParWhatCppBlock }
  RSParWhatCppBlock = 'the text of a cppstart block';
  { RSParNoBody }
  RSParNoBody = 'a %s module has no begin body';
  { RSParNeedBody }
  RSParNeedBody = 'an exe module needs a begin body';
  { RSParSectionOrder }
  RSParSectionOrder = 'initialize and finalize stand at most once each, initialize first';
  { RSParTestPlace }
  RSParTestPlace = 'test blocks follow the module''s end.';
  { RSParShapeType }
  RSParShapeType = 'a type';
  { RSParShapeName }
  RSParShapeName = 'a name';
  { RSParShapeParam }
  RSParShapeParam = 'a parameter';
  { RSParShapeTemplateArg }
  RSParShapeTemplateArg = 'a template argument';
  { RSParShapeMember }
  RSParShapeMember = 'a member or ''end''';
  { RSParShapeMethod }
  RSParShapeMethod = '''method'' (the words before it: [virtual | override] [final])';
  { RSParShapeForward }
  RSParShapeForward = '''routine'' or ''type''';
  { RSParExportedTarget }
  RSParExportedTarget = '''exported'' must precede a var, const or type block, a routine or a forward, found ''%s''';
  { RSParExportedLocal }
  RSParExportedLocal = '''exported'' is written at module level only: a ''%s'' block here is the body''s own';
  { RSParMethodBlocks }
  RSParMethodBlocks = 'a method body takes only var blocks before its begin, found ''%s''';
  { RSParTestBlocks }
  RSParTestBlocks = 'a test takes at most one var block before its begin, found ''%s''';
  { RSParDeclareAsType }
  RSParDeclareAsType = 'a ''%s'' type is declared in a type block (type TName = ...;) and used by its name';
  { RSParPrimitivePtr }
  RSParPrimitivePtr = '''%s'' is a PaskalCPP type and takes no C++ ''*''; write ptr to %s';
  { RSParPrimitiveRef }
  RSParPrimitiveRef = '''%s'' is a PaskalCPP type and takes no C++ ''%s''; pass it as a var or const parameter';
  { RSParPrimitiveCv }
  RSParPrimitiveCv = '''%s'' is a PaskalCPP type and takes no C++ ''%s''; use the C++ type (int32_t, std::string) there';
  { RSParQualifiedPtr }
  RSParQualifiedPtr = '''%s'' is a qualified PaskalCPP name and takes no C++ ''*''; write ptr to %s';
  { RSParQualifiedSuffix }
  RSParQualifiedSuffix = '''%s'' is a qualified PaskalCPP name and takes no C++ ''%s''';
  { RSParRepeatedCv }
  RSParRepeatedCv = '''%s'' is repeated';
  { RSParRefNotLast }
  RSParRefNotLast = 'a reference (& or &&) stands last and once, found ''%s''';
  { RSParTemplateArgsOpen }
  RSParTemplateArgsOpen = 'template arguments not closed: expected ''>'', found ''%s''';
  { RSParRecordPrefix }
  RSParRecordPrefix = '''%s'' is out of order: a record takes (parent), packed, align(...), in that order, each once';
  { RSParNotOnAggregate }
  RSParNotOnAggregate = '''%s'' is not allowed on %s';
  { RSParMemberNotAllowed }
  RSParMemberNotAllowed = '''%s'' is not allowed in %s';
  { RSParLifecycleWord }
  RSParLifecycleWord = '''%s'' does not go before init, copy or done: they are never hidden, virtual, override or final';
  { RSParInitShape }
  RSParInitShape = 'an init has no result type and no ''...'': write init(<parameters>);';
  { RSParCopyShape }
  RSParCopyShape = 'a copy has no result type and no ''...'': write copy(const ASource: <its type>);';
  { RSParDoneShape }
  RSParDoneShape = 'a done has no parameters and no result type: write done;';
  { RSParEmptyChoices }
  RSParEmptyChoices = 'choices need at least one value';
  { RSParElaboratedName }
  RSParElaboratedName = '''%s'' must be followed by a name, found ''%s''';
  { RSParDecltypeGroup }
  RSParDecltypeGroup = '''decltype'' needs a balanced ( ... ), found ''%s''';
  { RSParNeverClosed }
  // the opener, the closer it lacks (PR0063, F56: reported at the opener)
  RSParNeverClosed = '''%s'' is never closed: its ''%s'' is missing';
  { RSParAggRecord }
  RSParAggRecord = 'a record';
  { RSParAggObject }
  RSParAggObject = 'an object';
  { RSParAggInterface }
  RSParAggInterface = 'an interface';
  { RSParInterfaceField }
  RSParInterfaceField = 'an interface holds methods and properties only: field ''%s'' is not allowed in it';
  { RSParInterfaceBody }
  RSParInterfaceBody = 'an interface method has no body: write method <name>(<parameters>)[: <type>]; and implement it in the object';
  { RSParOperatorSymbol }
  RSParOperatorSymbol = 'a type declares operator + - * / div mod = <> < <= > >= or in, found %s';
  { RSParOperatorShape }
  RSParOperatorShape = 'an operator takes its operands only: write operator <op>(<parameters>): <type>; without ...';
  { RSParPropertyNoRead }
  RSParPropertyNoRead = 'property ''%s'' starts its accessors with read, found %s: write read <field>; or read begin ... end;';
  { RSParPropertyRead }
  RSParPropertyRead = 'the read of ''%s'' takes a field name or a body, found %s: write read <field>; or read begin ... end;';
  { RSParPropertyIndex }
  RSParPropertyIndex = 'the index of ''%s'' is one parameter, [const AIndex: <type>], found %s';
  { RSParPropertyIndexBinding }
  RSParPropertyIndexBinding = 'indexed property ''%s'' has accessor bodies: a field holds no index (write read begin ... end;)';
  { RSParInterfacePropertyBody }
  RSParInterfacePropertyBody = 'an interface property''s accessors have no body: write property %s: <type> read; [write;] and implement it in the object';
  { RSParShapeProperty }
  RSParShapeProperty = '''property'' (the words before it: [virtual | override] [final])';
  { RSParPropertyWrite }
  RSParPropertyWrite = 'the write of ''%s'' takes a field name or a value name and a body, found %s: write write <field>; or write(AValue) begin ... end;';
  { RSParAggOverlay }
  RSParAggOverlay = 'an overlay';
  { RSParAggAnonRecord }
  RSParAggAnonRecord = 'an anonymous record';
  { RSParAggAnonOverlay }
  RSParAggAnonOverlay = 'an anonymous overlay';
  { RSParShapeExpression }
  RSParShapeExpression = 'an expression';
  { RSParShapeCppTypeName }
  RSParShapeCppTypeName = 'a C++ type name';
  { RSParNoChain }
  RSParNoChain = 'comparisons do not chain; join them with and, found ''%s''';
  { RSParCppOperator }
  RSParCppOperator = '''%s'' is C++: PaskalCPP writes %s';
  { RSParXorEqHint }
  RSParXorEqHint = '''X := X xor Y''';
  { RSParCastOneArg }
  RSParCastOneArg = '''%s(...)'' takes exactly one argument';
  { RSParNestedTooDeep }
  RSParNestedTooDeep = 'nested too deeply: more than %d levels';
  { RSParNamedCastArgs }
  RSParNamedCastArgs = '''%s'' takes exactly one type in < >, found ''%s''';
  { RSParNewPrimitive }
  RSParNewPrimitive = '''%s'' is a PaskalCPP type: new takes a C++ type name (int32_t, std::string)';
  { RSParLambdaBody }
  RSParLambdaBody = 'a lambda needs a { ... } body, found ''%s''';
  { RSParOpaqueParens }
  RSParOpaqueParens = '''%s'' needs parentheses: write %s(...), found ''%s''';
  { RSParCppExprLineBreak }
  RSParCppExprLineBreak = 'a line break in cpp("...") would break the line mapping; use a raw string, cpp(R"(...)")';
  { RSParCastOperand }
  RSParCastOperand = 'expected an expression after the cast, found ''%s''';
  { RSParEqStatement }
  RSParEqStatement = '''='' compares and assigns nothing: use '':=''';
  { RSParCppStatement }
  RSParCppStatement = '''%s'' is a C++ statement, not allowed in a body: use %s';
  { RSParPlacementInBody }
  RSParPlacementInBody = '''cpp header'' / ''cpp source'' set the placement at module level only; in a body C++ stays in place';
  { RSParCppBlockHeaderInBody }
  RSParCppBlockHeaderInBody = 'a cppstart block in a body stays in place: write ''cppstart source''';
  { RSParGuardEmpty }
  RSParGuardEmpty = 'a guard needs ''except'', ''finally'' or both';
  { RSParBareSet }
  RSParBareSet = 'a set names its range or element type: declare ''TName = set of 0..255;'' or ''set of <type>'' in a type block';
  { RSParLibName }
  RSParLibName = '''%s'' is not a library name: %s takes a name such as m or user32, never a file or a path';
  { RSParValueMapSpellIndex }
  // Invariant (compiler defect, never a program error): a string part's spell
  // run names a spelling index the source walk did not reach (DoSpellOffsetAt)
  RSParValueMapSpellIndex = 'string value map: spell index %d has no source offset (%d spelling units)';
  { RSParShapeStatement }
  RSParShapeStatement = 'a statement';
  { RSParShapeToDownto }
  RSParShapeToDownto = '''to'' or ''downto''';
  { RSBdoDiagFileUnreadable }
  RSBdoDiagFileUnreadable = 'Cannot read the diagnostics file %s: %s';
  { RSSdgBadSignature }
  RSSdgBadSignature = 'not a clang serialized diagnostics file (bad signature)';
  { RSSdgTruncated }
  RSSdgTruncated = 'truncated at bit %d';
  { RSSdgBadVbr }
  RSSdgBadVbr = 'variable-width value too long at bit %d';
  { RSSdgBadWidth }
  RSSdgBadWidth = 'invalid field width %d at bit %d';
  { RSSdgBadAbbrevEncoding }
  RSSdgBadAbbrevEncoding = 'invalid abbreviation encoding %d at bit %d';
  { RSSdgBadAbbrev }
  RSSdgBadAbbrev = 'invalid abbreviation at bit %d';
  { RSSdgUnknownAbbrev }
  RSSdgUnknownAbbrev = 'unknown abbreviation id %d at bit %d';
  { RSSdgUnexpectedBlock }
  RSSdgUnexpectedBlock = 'unexpected block %d at bit %d';
  { RSSdgBadRecord }
  RSSdgBadRecord = 'malformed %s record at bit %d';
  { RSSdgNoDiagRecord }
  RSSdgNoDiagRecord = 'diagnostic block without a diagnostic record at bit %d';
  { RSSdgSecondDiagRecord }
  RSSdgSecondDiagRecord = 'second diagnostic record in one block at bit %d';
  { RSSdgUnknownLevel }
  RSSdgUnknownLevel = 'unknown diagnostic level %d at bit %d';
  { RSSdgUnknownId }
  RSSdgUnknownId = 'unknown %s id %d at bit %d';
  { RSSdgTooDeep }
  RSSdgTooDeep = 'notes nested deeper than %d at bit %d';
  { RSSdgVersion }
  RSSdgVersion = 'unsupported format version %d';
  { RSSdgNoVersion }
  RSSdgNoVersion = 'missing format version';
  { RSSdgBadText }
  RSSdgBadText = 'undecodable text: %s';
  { RSSdgFileRead }
  RSSdgFileRead = 'cannot read %s: %s';

  { RSSemCoreOwnDecl }
  RSSemCoreOwnDecl = '''%s'' is used in its own declaration';
  { RSSemCoreUsedBefore }
  RSSemCoreUsedBefore = '''%s'' is used before its declaration: declare it first or add forward';
  { RSSemCoreTypeSelf }
  RSSemCoreTypeSelf = 'type ''%s'' names itself: declare it first or add forward';
  { RSSemCoreDuplicate }
  RSSemCoreDuplicate = '''%s'' is already declared in this scope';
  { RSSemCoreFirstDecl }
  RSSemCoreFirstDecl = 'the first declaration of ''%s''';
  { RSSemCoreReservedName }
  RSSemCoreReservedName = '''%s'': names starting with %s are reserved for the compiler';
  { RSSemCoreBareMember }
  RSSemCoreBareMember = '''%s'' is a member of ''%s'': write self.%s';
  { RSSemCoreHiddenOutside }
  RSSemCoreHiddenOutside = '''%s'' is hidden in ''%s'': only the methods of ''%s'' and of its descendants reach it';
  { RSSemCoreHiddenThrough }
  RSSemCoreHiddenThrough = '''%s'' is hidden in ''%s'': a method of ''%s'' reaches it only through self or a ''%s'' value';
  { RSSemCoreModuleNoName }
  RSSemCoreModuleNoName = '''%s'' has no ''%s''';
  { RSSemCoreNotExported }
  RSSemCoreNotExported = '''%s'' is not exported by ''%s''';
  { RSSemCoreImportAmbiguous }
  // A bare name two imported units export (PLAN-IMPORT-RESOLUTION, SM0020):
  // name, first unit, second unit, then each qualified form
  RSSemCoreImportAmbiguous = '''%s'' is in ''%s'' and ''%s'': write %s.%s or %s.%s';
  { RSSemCoreImportHolder }
  // The note at each candidate: name, its unit
  RSSemCoreImportHolder = '''%s'' is declared in ''%s'' here';
  { RSSemCoreNotModule }
  RSSemCoreNotModule = '''%s'' is not an imported module';
  { RSSemCoreQualifiedParts }
  RSSemCoreQualifiedParts = 'a qualified type has exactly two parts: Module.Type';
  { RSSemCoreNoMember }
  RSSemCoreNoMember = '''%s'' has no member ''%s''';
  { RSSemCoreNoChoice }
  RSSemCoreNoChoice = 'choices ''%s'' has no value ''%s''';
  { RSSemCoreOutsideMethod }
  RSSemCoreOutsideMethod = '''%s'' outside a method';
  { RSSemCoreNoParent }
  RSSemCoreNoParent = 'parent: ''%s'' has no parent type';
  { RSSemCoreParentMember }
  RSSemCoreParentMember = '''parent'' reaches the parent''s members: write parent.<member>';
  { RSSemCoreNotType }
  RSSemCoreNotType = '''%s'' is not a type';
  { RSSemCoreArrowQualified }
  RSSemCoreArrowQualified = '''%s'' is a module or a type: reach its names with ''.''';
  { RSSemModValue }
  RSSemModValue = '''%s'' is not a value of @%s: %s';
  { RSSemModValueRetired }
  RSSemModValueRetired = '''%s'' is no longer a value of @%s: write ''%s''';
  { RSSemModVersion }
  RSSemModVersion = '@%s takes 0..65535, got %s';
  { RSSemModDuplicate }
  RSSemModDuplicate = '@%s is already given at line %s';
  { RSSemModNotApplied }
  RSSemModNotApplied = '@%s does not apply to %s: not used';
  { RSSemModWhereNotExe }
  RSSemModWhereNotExe = 'a module that is not an exe';
  { RSSemModWhereLib }
  RSSemModWhereLib = 'a lib module';
  { RSSemModWhereNotWindows }
  RSSemModWhereNotWindows = 'a target that is not Windows';
  { RSSemModNoVerInfo }
  RSSemModNoVerInfo = '@%s has no effect without @addverinfo on';
  { RSSemModNoFile }
  RSSemModNoFile = '''%s'' is not an existing file';
  { RSSemModNoDir }
  RSSemModNoDir = '''%s'' is not an existing directory';
  { RSSemModNotSource }
  RSSemModNotSource = '''%s'' is not a source file the toolchain compiles: the extension, exact case, must be one of %s';
  { RSSemModMacroName }
  RSSemModMacroName = '''%s'' is not a C/C++ macro name: a letter or _, then letters, digits and _';
  { RSSemModMacroReserved }
  RSSemModMacroReserved = '''%s'' is reserved: %s names belong to the compiler and the runtime';
  { RSSemModMacroLines }
  RSSemModMacroLines = 'the value of @cppdefine "%s" is more than one line';
  { RSSemModMacroConflict }
  RSSemModMacroConflict = '%s conflicts with %s at %s:%d: one name has one meaning in the build';
  { RSSemModPathCheck }
  RSSemModPathCheck = 'cannot check ''%s'': %s';
  { RSSemModMessage }
  RSSemModMessage = '%s';
  { RSSemModBreakpoint }
  RSSemModBreakpoint = '@breakpoint in the prologue has no effect';
  { RSSemModTestMode }
  RSSemModTestMode = '@unitTestMode in a dll or lib module: no program runs the tests';
  { RSSemModTestEmpty }
  RSSemModTestEmpty = 'a test name is empty';
  { RSSemModTestDup }
  RSSemModTestDup = 'test ''%s'' is already declared at line %s';
  { RSSemModTestNoRun }
  RSSemModTestNoRun = 'test blocks of a dll or lib module never run';
  { RSSemTypeNoConvertCast }
  RSSemTypeNoConvertCast = '''%s'' does not convert implicitly to ''%s''; write %s';
  { RSSemTypeNoConvert }
  RSSemTypeNoConvert = '''%s'' does not convert implicitly to ''%s''';
  { RSSemTypeSetNoMember }
  RSSemTypeSetNoMember = 'overload set ''%s'' has no member of type ''%s''';
  { RSSemTypeRoutineClink }
  RSSemTypeRoutineClink = 'clink here, cpplink in ''%s''';
  { RSSemTypeRoutineCpplink }
  RSSemTypeRoutineCpplink = 'cpplink here, clink in ''%s''';
  { RSSemTypeRoutineVariadic }
  RSSemTypeRoutineVariadic = 'takes ''...'' here, not in ''%s''';
  { RSSemTypeRoutineNotVariadic }
  RSSemTypeRoutineNotVariadic = 'takes no ''...'' here, ''%s'' does';
  { RSSemTypeRoutineCount }
  RSSemTypeRoutineCount = 'parameter count %d here, %d in ''%s''';
  { RSSemTypeRoutineParam }
  RSSemTypeRoutineParam = 'parameter %d is ''%s'' here, ''%s'' in ''%s''';
  { RSSemTypeRoutineReturn }
  RSSemTypeRoutineReturn = 'returns ''%s'' here, ''%s'' in ''%s''';
  { RSSemTypeRoutineNoReturn }
  RSSemTypeRoutineNoReturn = 'returns no value here, ''%s'' in ''%s''';
  { RSSemTypeRoutineReturnNone }
  RSSemTypeRoutineReturnNone = 'returns ''%s'' here, no value in ''%s''';
  { RSSemTypeNotFit }
  RSSemTypeNotFit = '%s does not fit in ''%s'' (%s..%s)';
  { RSSemTypeNotConstant }
  RSSemTypeNotConstant = '%s must be a constant';
  { RSSemTypePosConst }
  RSSemTypePosConst = 'a const value';
  { RSSemTypePosChoice }
  RSSemTypePosChoice = 'a choice value';
  { RSSemTypePosSetBound }
  RSSemTypePosSetBound = 'a set range bound';
  { RSSemTypePosArrayBound }
  RSSemTypePosArrayBound = 'a static array bound';
  { RSSemTypePosLabel }
  RSSemTypePosLabel = 'a match label';
  { RSSemTypePosBitWidth }
  RSSemTypePosBitWidth = 'a bitfield width';
  { RSSemTypePosAlign }
  RSSemTypePosAlign = 'an align value';
  { RSSemTypeOpTwo }
  RSSemTypeOpTwo = 'operator ''%s'' does not take ''%s'' and ''%s''';
  { RSSemTypeOpOne }
  RSSemTypeOpOne = 'operator ''%s'' does not take ''%s''';
  { RSSemTypeNotComparable }
  RSSemTypeNotComparable = 'operator ''%s'' cannot compare ''%s'': records and overlays are not comparable, compare their fields';
  { RSSemTypeObjectNotComparable }
  RSSemTypeObjectNotComparable = 'operator ''%s'' cannot compare ''%s'': an object compares only through an operator its type declares (operator = / <> / < / <= / > / >=)';
  { RSSemTypeNotAssignable }
  RSSemTypeNotAssignable = '''%s'' cannot be assigned';
  { RSSemTypeUntypedPointer }
  RSSemTypeUntypedPointer = '''%s'' is an untyped ptr and points at no type: cast it to a typed pointer first (ptr to T(%s))';
  { RSSemTypeNoAddress }
  // the operand (F57: address of a value that is not stored)
  RSSemTypeNoAddress = '''%s'' has no address: only a variable, a field, an element or a dereference has one';
  { RSSemTypeNoPointerCast }
  RSSemTypeNoPointerCast = '''%s'' cannot be cast to ''%s'': a pointer cast takes a pointer that keeps const, or an integer of pointer width';
  { RSSemTypeSetMixed }
  RSSemTypeSetMixed = 'set literal elements are of different ordinal types: ''%s'' and ''%s''';
  { RSSemTypeSetElement }
  RSSemTypeSetElement = '''%s'' is not an ordinal type: a set holds integers, chars, bools or choices';
  { RSSemTypeLowHigh }
  RSSemTypeLowHigh = 'low bound %s exceeds high bound %s';
  { RSSemTypeNotElement }
  RSSemTypeNotElement = '''in'': ''%s'' is not the element type of ''%s''';
  { RSSemTypeNotIndexable }
  RSSemTypeNotIndexable = '''%s'' cannot be indexed';
  { RSSemTypeIndexNotInt }
  RSSemTypeIndexNotInt = 'an index is an integer, got ''%s''';
  { RSSemTypeIndexFamily }
  // array type, its bound type, the index type
  RSSemTypeIndexFamily = 'an index of ''%s'' is a ''%s'' value, got ''%s''';
  { RSSemTypeIndexOutside }
  // the index, the array type, its low and high bound
  RSSemTypeIndexOutside = 'index %s is outside ''%s'' (%s..%s)';
  { RSSemTypeTooLarge }
  // the type, the most bytes a type holds (F47: SEM's folded count, the
  // runtime's Array check and clang's record text, one text)
  RSSemTypeTooLarge = '''%s'' is too large: a type holds at most %s bytes';
  { RSSemTypeCondition }
  RSSemTypeCondition = 'a condition is bool, got ''%s''';
  { RSSemTypeNotValue }
  RSSemTypeNotValue = '''%s'' is a type, not a value';
  { RSSemTypeModuleNotValue }
  RSSemTypeModuleNotValue = '''%s'' is a module, not a value';
  { RSSemTypeSignedToUnsigned }
  // operator, the signed operand's type, the unsigned type, the cast to write
  RSSemTypeSignedToUnsigned = '''%s'' would convert signed ''%s'' to unsigned ''%s'': write %s(...)';
  { RSSemTypeConstOverflow }
  RSSemTypeConstOverflow = 'constant overflows ''%s''';
  { RSSemTypeDivZero }
  RSSemTypeDivZero = '''%s'' by zero';
  { RSSemTypeMinDivMinusOne }
  // the minimum, the operator, the type
  RSSemTypeMinDivMinusOne = '''%s %s -1'' overflows ''%s''';
  { RSSemTypeShiftCount }
  RSSemTypeShiftCount = 'shift count %s outside 0..%d';
  { RSSemDeclForwardOnly }
  RSSemDeclForwardOnly = '''%s'' is only forward-declared: use ptr to ''%s'' or declare it first';
  { RSSemDeclExternalInit }
  RSSemDeclExternalInit = 'an external variable takes no initializer';
  { RSSemDeclExternalLocal }
  RSSemDeclExternalLocal = 'an external variable is declared at module level only';
  { RSSemDeclForwardNoFull }
  RSSemDeclForwardNoFull = 'forward type ''%s'' has no full declaration here';
  { RSSemDeclForwardAfterFull }
  RSSemDeclForwardAfterFull = '''%s'' is already declared: a forward after its full declaration declares nothing';
  { RSSemDeclFullDecl }
  RSSemDeclFullDecl = 'the full declaration of ''%s''';
  { RSSemDeclForwardKind }
  RSSemDeclForwardKind = 'a forward type is completed by a record, object or overlay';
  { RSSemDeclForwardDiffer }
  RSSemDeclForwardDiffer = 'forward and full declaration of ''%s'' differ: %s';
  { RSSemDeclTheForward }
  RSSemDeclTheForward = 'the forward declaration of ''%s''';
  { RSSemDeclFactExported }
  RSSemDeclFactExported = 'one is exported, the other is not';
  { RSSemDeclParentKind }
  RSSemDeclParentKind = '''%s'' cannot be the parent of %s';
  { RSSemDeclWhatRecord }
  RSSemDeclWhatRecord = 'a record';
  { RSSemDeclWhatObject }
  RSSemDeclWhatObject = 'an object';
  { RSSemDeclWhatInterface }
  RSSemDeclWhatInterface = 'an interface';
  { RSSemDeclParentInterface }
  RSSemDeclParentInterface = '''%s'' is an interface: an object names it after implements, not as its parent';
  { RSSemDeclInterfaceValue }
  RSSemDeclInterfaceValue = '''%s'' is an interface: it is reached through var, const, ptr to, own or ref, never held by value or created';
  { RSSemDeclInterfaceRepeat }
  RSSemDeclInterfaceRepeat = 'method ''%s'' of interface ''%s'' is already declared by its parent ''%s''';
  { RSSemDeclNotInterface }
  RSSemDeclNotInterface = '''%s'' is not an interface: implements names interfaces only';
  { RSSemDeclImplementsTwice }
  RSSemDeclImplementsTwice = '''%s'' is named twice after implements of ''%s''';
  { RSSemDeclMissingMethod }
  RSSemDeclMissingMethod = '''%s'' does not implement ''%s.%s'': declare virtual method %s with its parameters and result';
  { RSSemDeclImplementsPlain }
  RSSemDeclImplementsPlain = '''%s.%s'' implements ''%s.%s'': write ''virtual method %s''';
  { RSSemDeclImplementsSignature }
  RSSemDeclImplementsSignature = '''%s.%s'' does not implement ''%s.%s'': its parameter modes, types and result differ';
  { RSSemDeclImplementsHidden }
  RSSemDeclImplementsHidden = '''%s.%s'' implements ''%s.%s'': an interface member is never hidden';
  { RSSemDeclEmbedType }
  RSSemDeclEmbedType = 'embed ''%s'' holds ''%s'': an embed is a record, an overlay or an object, whose members its object reaches';
  { RSSemDeclEmbedShared }
  RSSemDeclEmbedShared = '''%s'' is reached through two embeds, ''%s'' and ''%s'': name one, as %s.%s.%s';
  { RSSemDeclEmbedSharedFace }
  RSSemDeclEmbedSharedFace = '''%s'' does not implement ''%s.%s'': two embeds, ''%s'' and ''%s'', have it; declare virtual method %s';
  { RSSemDeclEmbedReaches }
  RSSemDeclEmbedReaches = '''%s'' reaches ''%s'' here';
  { RSSemDeclPropertyNoField }
  RSSemDeclPropertyNoField = 'property ''%s'' binds ''%s'', which is no field of ''%s'': name a field, or write the accessor with a body';
  { RSSemDeclPropertyFieldType }
  RSSemDeclPropertyFieldType = 'property ''%s'' is ''%s'', and its field ''%s'' is ''%s'': a bound field has the property''s type';
  { RSSemDeclPropertyReadCall }
  RSSemDeclPropertyReadCall = 'the read of ''%s'' cannot call method ''%s'' through self: a read changes nothing of its object';
  { RSSemDeclPropertyReadChange }
  RSSemDeclPropertyReadChange = 'the read of ''%s'' cannot change ''%s'': a read changes nothing of its object';
  { RSSemDeclConstMethodChange }
  RSSemDeclConstMethodChange = '''%s'' is a const method: it cannot change ''%s'' (it changes nothing of its object)';
  { RSSemDeclConstMethodCall }
  RSSemDeclConstMethodCall = '''%s'' is a const method: it cannot call ''%s'' through self, which is not const';
  { RSSemDeclConstDiffers }
  RSSemDeclConstDiffers = '''%s'' must be %s, as ''%s'' of ''%s'' is: an override or an implementing method keeps the const of the method it continues';
  { RSSemDeclConstWord }
  RSSemDeclConstWord = 'a const method';
  { RSSemDeclNotConstWord }
  RSSemDeclNotConstWord = 'a method that is not const';
  { RSSemDeclPropertyOwnRead }
  RSSemDeclPropertyOwnRead = 'the read of ''%s'' reads the property again, forever: read its field';
  { RSSemDeclPropertyOwnWrite }
  RSSemDeclPropertyOwnWrite = 'the write of ''%s'' assigns the property again, forever: assign its field';
  { RSSemDeclPropertyNoWrite }
  RSSemDeclPropertyNoWrite = 'property ''%s'' has no write: it is read-only';
  { RSSemDeclPropertyAssignValue }
  RSSemDeclPropertyAssignValue = 'an assignment to property ''%s'' is a statement: its write has no value';
  { RSSemDeclPropertyNeedsIndex }
  RSSemDeclPropertyNeedsIndex = 'property ''%s'' is indexed: write %s[<index>]';
  { RSSemDeclPropertyDefaultIndex }
  RSSemDeclPropertyDefaultIndex = 'property ''%s'' has no index: default names an indexed property, which LO[i] means';
  { RSSemDeclPropertyDefaultTwice }
  RSSemDeclPropertyDefaultTwice = 'property ''%s'' is a second default of ''%s'': ''%s'' is its default already';
  { RSSemDeclMissingProperty }
  RSSemDeclMissingProperty = '''%s'' does not implement ''%s.%s'': declare virtual property %s with its type and accessors';
  { RSSemDeclImplementsPlainProperty }
  RSSemDeclImplementsPlainProperty = '''%s.%s'' implements ''%s.%s'': write ''virtual property %s''';
  { RSSemDeclImplementsPropertyShape }
  RSSemDeclImplementsPropertyShape = '''%s.%s'' does not implement ''%s.%s'': its type, index or write differ';
  { RSSemDeclPropNeedsOverride }
  RSSemDeclPropNeedsOverride = '''%s'' is virtual in ''%s'': write ''override property %s''';
  { RSSemDeclPropOverridesNothing }
  RSSemDeclPropOverridesNothing = '''%s'' overrides nothing: no level above ''%s'' has a virtual property ''%s''';
  { RSSemDeclPropOverrideType }
  RSSemDeclPropOverrideType = '''%s'' must have the type and index of ''%s.%s'' it overrides';
  { RSSemDeclPropOverrideWrite }
  RSSemDeclPropOverrideWrite = '''%s'' has a write, and ''%s.%s'' it overrides has none: an override restates the read, and its write only where the base has one';
  { RSSemDeclPropFinalNotVirtual }
  RSSemDeclPropFinalNotVirtual = '''final'' closes a virtual property: write ''virtual final property'' or ''override final property''';
  { RSSemDeclPropAbstractNotVirtual }
  RSSemDeclPropAbstractNotVirtual = 'an abstract accessor is virtual: write ''virtual property %s''';
  { RSSemDeclPropertyStorage }
  RSSemDeclPropertyStorage = '''%s'' is a property, not storage: %s needs a variable (read it into one, or assign the property)';
  { RSSemDeclParentName }
  RSSemDeclParentName = '''%s'' reuses a name of the parent chain';
  { RSSemDeclAlignPower }
  RSSemDeclAlignPower = 'align %s is not a power of two';
  { RSSemDeclAlignMax }
  RSSemDeclAlignMax = 'align %s exceeds %d';
  { RSSemDeclAlignNatural }
  RSSemDeclAlignNatural = 'align %s is below the natural alignment %s of ''%s'', lower it with packed';
  { RSSemDeclPackedField }
  RSSemDeclPackedField = 'field ''%s'' of packed record ''%s'' cannot be packed: ''%s'' holds a string or dynamic array';
  { RSSemDeclPackedParent }
  RSSemDeclPackedParent = 'the parent of packed record ''%s'' cannot be packed: ''%s'' holds a string or dynamic array';
  { RSSemDeclPackedFieldCpp }
  RSSemDeclPackedFieldCpp = 'field ''%s'' of packed record ''%s'' cannot be packed: ''%s'' is not plain data';
  { RSSemDeclPackedParentCpp }
  RSSemDeclPackedParentCpp = 'the parent of packed record ''%s'' cannot be packed: ''%s'' is not plain data';
  { RSSemDeclOverlayField }
  RSSemDeclOverlayField = 'field ''%s'' of ''%s'' cannot share an overlay''s storage: ''%s'' holds a string or dynamic array, hold a ptr to it';
  { RSSemDeclOverlayFieldCpp }
  RSSemDeclOverlayFieldCpp = 'field ''%s'' of ''%s'' cannot share an overlay''s storage: ''%s'' is not plain data, hold a ptr to it';
  { RSSemExprMisalignedVar }
  RSSemExprMisalignedVar = 'var parameter ''%s'' cannot take ''%s'': a packed record holds it, it may be misaligned';
  { RSSemExprMisalignedRef }
  RSSemExprMisalignedRef = 'reference parameter ''%s'' cannot take ''%s'': a packed record holds it, it may be misaligned';
  { RSSemExprMisalignedAddress }
  RSSemExprMisalignedAddress = 'cannot take the address of ''%s'': a packed record holds it, it may be misaligned';
  { RSSemExprMisalignedUpcast }
  RSSemExprMisalignedUpcast = '''%s'' cannot be used as ''%s'': packed ''%s'' holds that part, it may be misaligned';
  { RSSemExprMisalignedCompound }
  RSSemExprMisalignedCompound = '''%s'' cannot write to ''%s'': a packed record holds it, it may be misaligned';
  { RSSemExprTypeTestOperand }
  RSSemExprTypeTestOperand = '''%s'' tests a polymorphic object (one with a virtual method) or a ptr to, own or ref of one; ''%s'' is %s';
  { RSSemExprTypeTestTarget }
  RSSemExprTypeTestTarget = '''%s %s'': ''%s'' is not an object or an interface type';
  { RSSemExprTypeTestNever }
  RSSemExprTypeTestNever = '''%s'' never holds: a %s is never a %s';
  { RSSemExprTypeTestExact }
  RSSemExprTypeTestExact = '''%s'' holds exactly a %s, never a %s: only a var or const parameter, a deref, self, or a ptr, own or ref may hold a descendant';
  { RSSemExprTypeTestWeak }
  RSSemExprTypeTestWeak = '''%s'' is a weak: test lock(%s) instead';
  { RSSemDeclBitfieldType }
  RSSemDeclBitfieldType = 'a bitfield is an integer, bool, char, wchar or choices field';
  { RSSemDeclBitfieldWidth }
  RSSemDeclBitfieldWidth = 'bitfield width %s outside 1..%d';
  { RSSemDeclBitfieldOrdinals }
  RSSemDeclBitfieldOrdinals = 'bitfield width %s does not hold the ordinals of ''%s'' as signed values';
  { RSSemDeclSetIntegers }
  RSSemDeclSetIntegers = 'a set of integers names its range: set of 0..255';
  { RSSemDeclSetWChar }
  RSSemDeclSetWChar = 'set of wchar: its size differs by target: write set of 0..65535';
  { RSSemDeclSetFamily }
  RSSemDeclSetFamily = 'set range bounds are of different ordinal families';
  { RSSemDeclSetCount }
  RSSemDeclSetCount = 'a set has at most %d members, this one %s';
  { RSSemDeclArrayBounds }
  RSSemDeclArrayBounds = 'array bounds are integer, char or choices of one family';
  { RSSemDeclBoundOrder }
  RSSemDeclBoundOrder = 'low bound %s is above high bound %s';
  { RSSemDeclSetElement }
  RSSemDeclSetElement = 'a set element is char, bool or choices: ''%s'' is not';
  { RSSemDeclFactLinkage }
  RSSemDeclFactLinkage = 'one is clink, the other is not';
  { RSSemDeclFactParamName }
  RSSemDeclFactParamName = 'parameter %d is ''%s'' in one and ''%s'' in the other';
  { RSSemDeclFactParamMode }
  RSSemDeclFactParamMode = 'parameter ''%s'' is passed differently (var / const)';
  { RSSemDeclFactVariadic }
  RSSemDeclFactVariadic = 'one is variadic, the other is not';
  { RSSemDeclFactReturn }
  RSSemDeclFactReturn = 'their return types differ';
  { RSSemDeclRoutineNoFull }
  RSSemDeclRoutineNoFull = 'forward routine ''%s'' has no matching full declaration';
  { RSSemDeclNearestFull }
  RSSemDeclNearestFull = 'the nearest full declaration of ''%s''';
  { RSSemDeclOverloadLinkage }
  RSSemDeclOverloadLinkage = '''%s'' is overloaded: C linkage dropped, it gets C++ linkage';
  { RSSemDeclSameParams }
  RSSemDeclSameParams = '''%s'' is already declared with these parameter types: overloads differ in their parameter types';
  { RSSemDeclFirstOverload }
  RSSemDeclFirstOverload = 'the first declaration of ''%s'' with these parameter types';
  { RSSemDeclVariadicOverload }
  RSSemDeclVariadicOverload = '''%s'' is variadic: a variadic routine cannot share its name with another routine';
  { RSSemDeclNeedsOverride }
  RSSemDeclNeedsOverride = '''%s'' is virtual in ''%s'': write ''override method %s''';
  { RSSemDeclOverridesNothing }
  RSSemDeclOverridesNothing = '''%s'' overrides nothing: no level above ''%s'' has a virtual method ''%s''';
  { RSSemDeclOverrideCppSignature }
  RSSemDeclOverrideCppSignature = '''%s'' overrides no virtual ''%s'' of ''%s'': take its parameters, result and const (write ''override const method %s'' when it is const)';
  { RSSemDeclOverrideSignature }
  RSSemDeclOverrideSignature = '''%s'' must take the parameters and return the type of ''%s.%s'' it overrides';
  { RSSemDeclOverrideFinal }
  RSSemDeclOverrideFinal = '''%s.%s'' is final: it cannot be overridden';
  { RSSemDeclFinalNotVirtual }
  RSSemDeclFinalNotVirtual = '''final'' closes a virtual method: write ''virtual final method'' or ''override final method''';
  { RSSemDeclAbstractNotVirtual }
  RSSemDeclAbstractNotVirtual = 'an abstract method is virtual: write ''virtual method %s''';
  { RSSemDeclAbstractValue }
  RSSemDeclAbstractValue = '''%s'' is abstract (''%s.%s'' has no body): it cannot be held by value or created';
  { RSSemDeclFinalParent }
  RSSemDeclFinalParent = '''%s'' is final: no type may extend it';
  { RSSemDeclAbstractCall }
  RSSemDeclAbstractCall = '''%s.%s'' is abstract: it has no body to call';
  { RSSemDeclOneDone }
  RSSemDeclOneDone = '''%s'' declares done twice: an object has one done';
  { RSSemDeclInitByName }
  RSSemDeclInitByName = 'init runs when an object is built: it is never called (only parent.init(...) and self.<field>.init(...) begin an init)';
  { RSSemDeclDoneByName }
  RSSemDeclDoneByName = 'done runs when an object ends: it is never called';
  { RSSemDeclCopyByName }
  RSSemDeclCopyByName = 'copy runs when an object is copied (:=, a value argument): it is never called';
  { RSSemDeclOneCopy }
  RSSemDeclOneCopy = '''%s'' declares copy twice: an object has one copy';
  { RSSemDeclCopyShape }
  RSSemDeclCopyShape = 'copy takes one const parameter of its own type: write copy(const ASource: %s);';
  { RSSemDeclCopyParent }
  RSSemDeclCopyParent = '''%s'' cannot copy its parent part: ''%s'' cannot be copied (give it a copy)';
  { RSSemDeclCopyParentInit }
  RSSemDeclCopyParentInit = 'copy copies the parent part with the parent''s own copy: parent.init(...) is not written in a copy';
  { RSSemDeclRecordHoldsObject }
  RSSemDeclRecordHoldsObject = 'field ''%s'': a record or an overlay holds no object (''%s'' is one): it is plain data, hold a ptr to the object';
  { RSSemDeclRecordHoldsOwner }
  RSSemDeclRecordHoldsOwner = 'field ''%s'': a record or an overlay holds no object (''%s'' holds one): it is plain data, hold a ptr to the object';
  { RSSemDeclOwnerTarget }
  RSSemDeclOwnerTarget = '''%s'': own, ref and weak hold an object, and ''%s'' is none';
  { RSSemDeclWeakNew }
  RSSemDeclWeakNew = '''%s'' builds nothing: a weak watches an object a ref holds (build it with ref %s(...))';
  { RSSemDeclParentInitFirst }
  RSSemDeclParentInitFirst = 'parent.init(...) is the first statement of an init';
  { RSSemDeclFieldInitOrder }
  RSSemDeclFieldInitOrder = 'self.%s.init(...) comes after self.%s.init(...): fields are built in declaration order';
  { RSSemDeclFieldInitTwice }
  RSSemDeclFieldInitTwice = 'self.%s.init(...) is written twice: a field is built once';
  { RSSemDeclLeadArgEarly }
  RSSemDeclLeadArgEarly = '''%s'' does not exist yet: the arguments of %s(...) run before the object is built';
  { RSSemDeclParentNeedsInit }
  RSSemDeclParentNeedsInit = '''%s'' has no init without arguments: begin every init of ''%s'' with parent.init(...)';
  { RSSemDeclFieldNeedsInit }
  RSSemDeclFieldNeedsInit = 'field ''%s'': ''%s'' has no init without arguments: begin every init of ''%s'' with self.%s.init(...)';
  { RSSemDeclVirtualInLifecycle }
  RSSemDeclVirtualInLifecycle = '''%s'' is virtual: in an init or a done a call does not dispatch, call a plain method or parent.%s()';
  { RSSemDeclNoDefaultInit }
  RSSemDeclNoDefaultInit = '''%s'' has no init without arguments: build it with arguments, %s(...)';
  { RSSemDeclInitArgsNotObject }
  RSSemDeclInitArgsNotObject = '''%s'' takes no init arguments: only an object has an init';
  { RSSemDeclNoInitTakes }
  RSSemDeclNoInitTakes = 'no init of ''%s'' takes (%s)';
  { RSSemDeclNoInitDeclared }
  RSSemDeclNoInitDeclared = '''%s'' declares no init: it is built without arguments';
  { RSSemDeclInitAmbiguous }
  RSSemDeclInitAmbiguous = 'the arguments (%s) fit more than one init of ''%s'': convert them to pick one';
  { RSSemDeclInitHere }
  RSSemDeclInitHere = 'an init of ''%s'': %s';
  { RSSemDeclMemberHere }
  RSSemDeclMemberHere = '''%s.%s'' is declared here';
  { RSSemDeclVariadicFixed }
  RSSemDeclVariadicFixed = '''%s'' has C linkage and a body: it needs a fixed parameter before ''...'' (C reads the extra arguments from the last fixed one)';
  { RSSemDeclOtherOverload }
  RSSemDeclOtherOverload = 'another declaration of ''%s''';
  { RSSemDeclLibConst }
  RSSemDeclLibConst = '''%s'' must be a const string (external library)';
  { RSSemDeclLibName }
  RSSemDeclLibName = '''%s'' is not a library name: external takes a name such as m or user32, never a file or a path';
  { RSSemCallArgCount }
  // callee, its parameter count, the argument count (F51)
  RSSemCallArgCount = '''%s'' takes %d argument(s), %d given';
  { RSSemCallNotCallable }
  // the callee, its type (F58: a PaskalCPP value whose type is no routine type)
  RSSemCallNotCallable = '''%s'' is not callable: its type ''%s'' is not a routine type';
  { RSSemCallArgCountVariadic }
  // callee, its fixed parameter count, the argument count (F51: a `...` routine)
  RSSemCallArgCountVariadic = '''%s'' takes at least %d argument(s), %d given';
  { RSSemCallArgCast }
  // argument number, callee, argument type, parameter type, the cast to write
  RSSemCallArgCast = 'argument %d of ''%s'': ''%s'' does not convert implicitly to ''%s''; write %s';
  { RSSemCallArgNoConvert }
  RSSemCallArgNoConvert = 'argument %d of ''%s'': ''%s'' does not convert implicitly to ''%s''';
  { RSSemCallArgSetNoMember }
  RSSemCallArgSetNoMember = 'argument %d of ''%s'': overload set ''%s'' has no member of type ''%s''';
  { RSSemCallArgNotFit }
  // argument number, callee, the constant's value, parameter type, its lowest and highest value
  RSSemCallArgNotFit = 'argument %d of ''%s'': %s does not fit in ''%s'' (%s..%s)';
  { RSSemCallVarParam }
  RSSemCallVarParam = 'var parameter ''%s'' needs a variable of type ''%s''';
  { RSSemCallNoValue }
  RSSemCallNoValue = '''%s'' calls a procedure: it has no value';
  { RSSemCallCastArgs }
  RSSemCallCastArgs = 'a cast ''%s(...)'' takes exactly one argument, given %d';
  { RSSemCallIntrinsicStmt }
  RSSemCallIntrinsicStmt = '''%s'' is a statement, not a value';
  { RSSemCallIntrinsicSig }
  RSSemCallIntrinsicSig = '''%s'' takes %s';
  { RSSemCallSizeValue }
  RSSemCallSizeValue = 'size needs a type, got the value ''%s''';
  { RSSemCallTypeArg }
  RSSemCallTypeArg = '''%s'' takes no type argument: only size does';
  { RSSemCallIntrinsicNotCalled }
  RSSemCallIntrinsicNotCalled = '''%s'' is an intrinsic: it is called, never used as a value';
  { RSSemCallMethodValue }
  RSSemCallMethodValue = '''%s'' is a method: it runs on its object and has no routine value, call it';
  { RSSemCoreBareChoice }
  RSSemCoreBareChoice = '''%s'' is a choice value: write %s';
  { RSSemStmtCppJumpFinally }
  RSSemStmtCppJumpFinally = 'C++ %s in a finally body leaves only the finally''s hidden function';
  { RSSemCallVarargsOutside }
  RSSemCallVarargsOutside = '%s outside a variadic routine';
  { RSSemCallVarargsClink }
  RSSemCallVarargsClink = '%s.%s needs a cpplink variadic: a C caller passes no types or count';
  { RSSemCallVarargsValue }
  RSSemCallVarargsValue = '''%s'' is not a value: use %s.%s, %s, %s, %s or %s';
  { RSSemCallVarargsCountCall }
  RSSemCallVarargsCountCall = '''%s'' is a value, not a call: write it without ()';
  { RSSemCallUnprintable }
  RSSemCallUnprintable = '''%s'' cannot be printed: print the fields of a record, object or overlay';
  { RSSemCallNoAddress }
  RSSemCallNoAddress = '''%s'' cannot be printed: an overload set or a method has no single address';
  { RSSemCallNoFormatter }
  RSSemCallNoFormatter = '''%s'' cannot be printed: the C/C++ type has no std::formatter';
  { RSSemCallNoFormatterArgs }
  // the callee as written (PLAN-VENDOR 1e: a C++ routine's call, several C/C++ arguments)
  RSSemCallNoFormatterArgs = 'an argument of ''%s'' cannot be printed: its C/C++ type has no std::formatter';
  { RSSemCallFormatMismatch }
  // the format string literal as written, the argument count after it (PLAN-VENDOR 1e)
  RSSemCallFormatMismatch = 'format string %s does not fit the %d argument(s) after it: each {} takes the next argument, and its format spec must suit that argument''s type';
  { RSSemCallFormatNotLiteral }
  // the format value as written (PLAN-VENDOR 1e)
  RSSemCallFormatNotLiteral = 'format string ''%s'' is not a string literal: a format string is checked against its arguments when the program is built, so write the text itself';
  { RSSemCallOverloadNone }
  RSSemCallOverloadNone = 'no overload of ''%s'' takes (%s)';
  { RSSemCallOverloadMember }
  RSSemCallOverloadMember = 'an overload of ''%s'': %s';
  { RSSemCallVarargsType }
  RSSemCallVarargsType = '''%s'' is only the type of a variadic routine''s local, set from a %s()';
  { RSSemCallRecordKind }
  RSSemCallRecordKind = 'a record literal needs a record with no C/C++ parent: ''%s'' is not one';
  { RSSemCallRecordNoField }
  RSSemCallRecordNoField = 'record literal: ''%s'' has no field ''%s''';
  { RSSemCallRecordTwice }
  RSSemCallRecordTwice = 'record literal: field ''%s'' is given twice';
  { RSSemCallRecordOrder }
  RSSemCallRecordOrder = 'record literal: ''%s'' comes before ''%s'' in ''%s''';
  { RSSemCallConstObject }
  RSSemCallConstObject = 'method ''%s'' may change its object, which is const here: pass it var';
  { RSSemCallNoCopy }
  RSSemCallNoCopy = '''%s'' would be copied here, and ''%s'' cannot be copied: pass it var / const, return it from a local, or give ''%s'' a copy';
  { RSSemCallCreateObject }
  RSSemCallCreateObject = 'create does not build an object (''%s'' is one): write own %s(...) or ref %s(...)';
  { RSSemCallDestroyObject }
  RSSemCallDestroyObject = 'destroy does not free an object (''%s'' is one): the own or ref that holds it frees it';
  { RSSemCallWeakMember }
  RSSemCallWeakMember = '''%s.%s'': a weak may watch an object that is gone: read it through lock(%s), which is nil then';
  { RSSemCallNoCopyOwn }
  RSSemCallNoCopyOwn = '''%s'' would be copied here, and ''%s'' cannot be copied (an own is the sole owner of its object): pass it var / const, return it from a local, or hold a ref';
  { RSSemCallNoCopyDone }
  RSSemCallNoCopyDone = '''%s'' has a done and no copy';
  { RSSemCallNoCopyParent }
  RSSemCallNoCopyParent = '''%s'' cannot be copied because its parent ''%s'' cannot';
  { RSSemCallNoCopyField }
  RSSemCallNoCopyField = '''%s'' cannot be copied because field ''%s'' holds ''%s''';
  { RSSemCallSlice }
  RSSemCallSlice = '''%s'' would be cut down to its ''%s'' part here (it is polymorphic): pass it var / const, or through a pointer';
  { RSSemCallSliceHeld }
  RSSemCallSliceHeld = '''%s'' may hold a descendant of ''%s'' (it is polymorphic): a copy keeps only its ''%s'' part; pass it var / const, or through a pointer';
  { RSSemCallOperatorNone }
  RSSemCallOperatorNone = 'no operator %s declared for these operands takes (%s)';
  { RSSemCallOperatorMember }
  RSSemCallOperatorMember = 'operator %s of ''%s'' takes (%s)';
  { RSSemCallOperatorAmbiguous }
  RSSemCallOperatorAmbiguous = 'several operators %s take (%s) alike: give the operands their exact parameter types';
  { RSSemDeclOperatorArity }
  RSSemDeclOperatorArity = 'operator %s takes %s';
  { RSSemDeclOperatorArityBinary }
  RSSemDeclOperatorArityBinary = 'two operands';
  { RSSemDeclOperatorArityMinus }
  RSSemDeclOperatorArityMinus = 'one operand (the unary minus) or two';
  { RSSemDeclOperatorOwnType }
  RSSemDeclOperatorOwnType = 'operator %s of ''%s'' takes no ''%s'': one of its operands is the type that declares it';
  { RSSemDeclOperatorBool }
  RSSemDeclOperatorBool = 'operator %s gives a bool, not ''%s''';
  { RSSemDeclOperatorTwice }
  RSSemDeclOperatorTwice = 'operator %s of ''%s'' is declared twice with these operand types';
  { RSSemDeclOperatorHere }
  RSSemDeclOperatorHere = 'operator %s of ''%s'' is declared here';
  { RSSemDeclOperatorVar }
  RSSemDeclOperatorVar = 'operator %s takes its operands by value or const, not var (''%s'')';
  { RSSemDeclOperatorPair }
  RSSemDeclOperatorPair = 'operator %s of ''%s'' needs its pair: declare operator %s with the same operand types';
  { RSSemCallSliceAssign }
  RSSemCallSliceAssign = '''%s'' may hold a descendant of ''%s'' (it is polymorphic): assigning to it would replace only its ''%s'' part; set its fields instead';
  { RSSemStmtForNotVar }
  RSSemStmtForNotVar = 'for needs a variable: ''%s'' is %s';
  { RSSemStmtKindConst }
  RSSemStmtKindConst = 'a constant';
  { RSSemStmtKindConstParam }
  RSSemStmtKindConstParam = 'a const parameter';
  { RSSemStmtKindType }
  RSSemStmtKindType = 'a type';
  { RSSemStmtKindRoutine }
  RSSemStmtKindRoutine = 'a routine';
  { RSSemStmtKindField }
  RSSemStmtKindField = 'a field';
  { RSSemStmtKindChoice }
  RSSemStmtKindChoice = 'a choice value';
  { RSSemStmtKindModule }
  RSSemStmtKindModule = 'a module';
  { RSSemStmtKindOther }
  RSSemStmtKindOther = 'not a variable';
  { RSSemStmtForType }
  RSSemStmtForType = 'a for iterator is an integer, char, wchar or a choice, got ''%s''';
  { RSSemStmtIteratorWrite }
  RSSemStmtIteratorWrite = '''%s'' is the for iterator: the loop body cannot write it';
  { RSSemStmtMatchSubject }
  RSSemStmtMatchSubject = 'a match subject is an integer, char, wchar or a choice, got ''%s''';
  { RSSemStmtLabelRange }
  RSSemStmtLabelRange = 'match label %s is outside ''%s'': it never matches';
  { RSSemStmtLabelRepeat }
  RSSemStmtLabelRepeat = 'match label %s repeats a label of the arm at line %s';
  { RSSemStmtFirstLabel }
  RSSemStmtFirstLabel = 'the first label covering it: %s';
  { RSSemStmtNotCovered }
  RSSemStmtNotCovered = 'match on ''%s'' does not cover: %s';
  { RSSemStmtLeaveOutside }
  RSSemStmtLeaveOutside = 'leave outside a loop or match';
  { RSSemStmtSkipOutside }
  RSSemStmtSkipOutside = 'skip outside a loop';
  { RSSemStmtJumpFinally }
  RSSemStmtJumpFinally = '%s cannot jump out of finally';
  { RSSemStmtReturnNeeds }
  RSSemStmtReturnNeeds = 'return needs a value of type ''%s''';
  { RSSemStmtReturnNoValue }
  RSSemStmtReturnNoValue = 'return takes no value here';
  { RSSemStmtMissingReturn }
  RSSemStmtMissingReturn = 'missing return: ''%s'' can reach its end without returning a value';
  { RSSemStmtNoEffect }
  RSSemStmtNoEffect = 'statement has no effect';
  { RSSemStmtCppJumpGuard }
  RSSemStmtCppJumpGuard = 'C++ %s in a guard body leaves only the guard''s hidden function';
  { RSSemStmtCppJumpExcept }
  RSSemStmtCppJumpExcept = 'C++ %s in the except body of a guard with finally leaves only the except''s hidden function';
  { RSSemStmtExcOutside }
  RSSemStmtExcOutside = '''%s'' outside an except body';

  { RSCwrPreambleLate }
  RSCwrPreambleLate = 'Internal error: a C++ preamble line after the first .pcpp line';

  { RSCwrLineZero }
  RSCwrLineZero = 'Internal error: .pcpp line 0 given to the C++ writer';

  { RSCwrLineBack }
  RSCwrLineBack = 'Internal error: .pcpp line %d written after line %d';
  { RSCwrLineNotBack }
  RSCwrLineNotBack = 'Internal error: return to .pcpp line %d, which is not before line %d';

  { RSCwrLineBreak }
  RSCwrLineBreak = 'Internal error: C++ text with a line break on .pcpp line %d';

  { RSCwrLineClosed }
  RSCwrLineClosed = 'Internal error: C++ text after a # line on .pcpp line %d';

  { RSCwrPreprocMidLine }
  RSCwrPreprocMidLine = 'Internal error: a # line that does not start its C++ line (.pcpp line %d)';

  { RSCwrPeerColumns }
  RSCwrPeerColumns = 'Internal error: C++ text that must start its line meets the other file''s text on .pcpp line %d';

  { RSCwrBorrowUnbalanced }
  RSCwrBorrowUnbalanced = 'Internal error: EndBorrowed without BeginBorrowed';

  { RSCwrEncoding }
  RSCwrEncoding = 'Internal error: C++ text not encodable as UTF-8: %s';

  //--------------------------------------------------------------------------
  // PaskalCPP.Emitter (PLAN-EMITTER A4)
  //--------------------------------------------------------------------------

  { RSEmtFolder }
  RSEmtFolder = 'Cannot create the output folder ''%s'': %s';

  { RSEmtEmptyPath }
  RSEmtEmptyPath = 'the path is empty';

  { RSEmtWriteFile }
  RSEmtWriteFile = 'Cannot write ''%s'': %s';

  { RSEmtInternal }
  RSEmtInternal = 'Internal error while emitting module ''%s'': %s';

  { RSEmtNoRule }
  RSEmtNoRule = 'no C++ rule for a %s on .pcpp line %d';

  { RSEmtRunOpen }
  RSEmtRunOpen = 'a namespace run is still open before global C++ on .pcpp line %d';

  { RSEmtModuleTarget }
  RSEmtModuleTarget = 'a module-level C++ span with no file target on .pcpp line %d';

  { RSEmtNoImport }
  RSEmtNoImport = 'import ''%s'' has no module';

  { RSEmtMissingNode }
  RSEmtMissingNode = 'a required %s is missing on .pcpp line %d';

  { RSEmtNoTokenRule }
  RSEmtNoTokenRule = 'no C++ spelling for the token %s';

  // PaskalCPP.Compiler (PLAN-COMPILER A-CMP)

  { RSCmpSourceNotFound }
  RSCmpSourceNotFound = 'source file not found: %s';

  { RSCmpPathFailed }
  RSCmpPathFailed = 'cannot use the path %s: %s';

  { RSCmpCompiling }
  RSCmpCompiling = 'Compiling %s';

  { RSCmpNoRun }
  RSCmpNoRun = 'a %s cannot be run: auto-run skipped';

  { RSCmpBadOption }
  RSCmpBadOption = 'bad value ''%s'' for option %s (expected %s)';
  { RSCmpBadOptionRetired }
  RSCmpBadOptionRetired = '''%s'' is no longer a value of option %s: write ''%s''';

  { RSCmpUnknownOption }
  RSCmpUnknownOption = 'unknown option ''%s''';

  { RSCmpInternalError }
  RSCmpInternalError = 'internal error: %s';
  { RSCmpRemovedStaleRuntime }
  RSCmpRemovedStaleRuntime = 'Removed %s: this lib no longer uses the runtime';
  { RSCmpStaleRuntime }
  RSCmpStaleRuntime = 'cannot remove the stale runtime library %s (this lib no longer uses the runtime): %s';
  { RSCmpRecordFailed }
  RSCmpRecordFailed = 'cannot write the output record %s: %s (pcpp --clean will refuse this folder)';
  { RSCmpCleanBadFolder }
  RSCmpCleanBadFolder = 'cannot use the folder %s: %s';
  { RSCmpCleanRefused }
  RSCmpCleanRefused = 'refusing to clean %s: %s';
  { RSCmpCleanNotFolder }
  RSCmpCleanNotFolder = 'it is not a folder';
  { RSCmpCleanIsLink }
  RSCmpCleanIsLink = 'it is a link (junction or symbolic link)';
  { RSCmpCleanDriveRoot }
  RSCmpCleanDriveRoot = 'it is the root of a drive';
  { RSCmpCleanNoRecord }
  RSCmpCleanNoRecord = 'it holds no %s, so it is not a pcpp output folder';
  { RSCmpCleanBadRecord }
  RSCmpCleanBadRecord = '%s cannot be read: %s';
  { RSCmpCleanRecordNotJson }
  RSCmpCleanRecordNotJson = '%s is not a JSON object';
  { RSCmpCleanRecordFormat }
  RSCmpCleanRecordFormat = '%s does not have format %d (a newer pcpp may have written it)';
  { RSCmpCleanRecordKey }
  RSCmpCleanRecordKey = '%s has no text for "%s"';
  { RSCmpCleanOtherFolder }
  RSCmpCleanOtherFolder = '%s was written for another output folder: %s';
  { RSCmpCleanNoBuildZig }
  RSCmpCleanNoBuildZig = 'it holds no build.zig';
  { RSCmpCleanBuildZigBad }
  RSCmpCleanBuildZigBad = 'its build.zig is not one pcpp wrote (%s)';
  { RSCmpCleanProjectMismatch }
  RSCmpCleanProjectMismatch = '%s names the project %s, build.zig names %s';
  { RSCmpCleanNoGenerated }
  RSCmpCleanNoGenerated = 'its build.zig builds nothing from this folder''s generated folder';
  { RSCmpCleanGeneratedElsewhere }
  RSCmpCleanGeneratedElsewhere = 'its build.zig builds %s, outside this folder';
  { RSCmpCleanHoldsSource }
  RSCmpCleanHoldsSource = 'it holds the source %s (the project''s own folder or above it)';
  { RSCmpCleanTargetLink }
  RSCmpCleanTargetLink = '%s is a link (junction or symbolic link)';

  // PaskalCPP.CLI (PLAN-COMPILER A-CLI)

  { RSPcCliBannerTitle }
  RSPcCliBannerTitle = '%s v%s';

  { RSPcCliBannerCopyright }
  RSPcCliBannerCopyright = '%s, All Rights Reserved.';

  { RSPcCliHelpUsageHeader }
  RSPcCliHelpUsageHeader = 'USAGE:';

  { RSPcCliHelpSourceArg }
  RSPcCliHelpSourceArg = '<source>';

  { RSPcCliHelpOptionsArg }
  RSPcCliHelpOptionsArg = '[OPTIONS]';

  { RSPcCliHelpRequiredHeader }
  RSPcCliHelpRequiredHeader = 'REQUIRED:';

  { RSPcCliHelpSource }
  RSPcCliHelpSource = 'Main module (.pcpp)';

  { RSPcCliHelpOptionsHeader }
  RSPcCliHelpOptionsHeader = 'OPTIONS:';

  { RSPcCliHelpRun }
  RSPcCliHelpRun = 'Run after building (executables only)';

  { RSPcCliHelpOutput }
  RSPcCliHelpOutput = 'Set output directory (wins over @outputpath; default: output)';

  { RSPcCliHelpTarget }
  RSPcCliHelpTarget = 'Set target triple: x86_64-windows-gnu (default), x86_64-linux-gnu';

  { RSPcCliHelpOptimize }
  RSPcCliHelpOptimize = 'Set optimize level: debug, safe, fast, small';

  { RSPcCliHelpHelp }
  RSPcCliHelpHelp = 'Display this help message';

  { RSPcCliHelpExamplesHeader }
  RSPcCliHelpExamplesHeader = 'EXAMPLES:';

  { RSPcCliSeeHelp }
  RSPcCliSeeHelp = 'Run %s -h to see available options';

  { RSPcCliNeedsPath }
  RSPcCliNeedsPath = 'Error: %s requires a path argument';

  { RSPcCliNeedsTarget }
  RSPcCliNeedsTarget = 'Error: %s requires a target argument (x86_64-windows-gnu, x86_64-linux-gnu)';

  { RSPcCliNeedsOptimize }
  RSPcCliNeedsOptimize = 'Error: %s requires an optimize level argument (debug, safe, fast, small)';

  { RSPcCliUnknownFlag }
  RSPcCliUnknownFlag = 'Error: Unknown flag: %s';

  { RSPcCliUnexpectedArg }
  RSPcCliUnexpectedArg = 'Error: Unexpected argument: %s';

  { RSPcCliSourceRequired }
  RSPcCliSourceRequired = 'Error: Source file is required';

  { RSPcCliSourceNotFound }
  RSPcCliSourceNotFound = 'Error: Source file not found: %s';

  { RSPcCliBadSource }
  RSPcCliBadSource = 'Error: Cannot use the source path %s: %s';

  { RSPcCliFailed }
  RSPcCliFailed = 'Failed.';

  { RSPcCliFatalError }
  RSPcCliFatalError = 'Fatal Error: %s';

  { RSPcCliBuildProgress }
  RSPcCliBuildProgress = 'Building %s... %ds';

  { RSPcCliException }
  RSPcCliException = 'EXCEPTION: %s';

  { RSPcCliHelpDefaults }
  RSPcCliHelpDefaults = '-opt / -t only apply where the source has no @optimize / @target (the editor passes this)';

  { RSPcCliHelpProgress }
  RSPcCliHelpProgress = 'Draw the build progress in place even when output is piped (the editor passes this)';

  { RSPcCliHelpEditor }
  RSPcCliHelpEditor = 'Start the PaskalCPP Editor with the files given';

  { RSPcCliEditorFailed }
  RSPcCliEditorFailed = 'Cannot start the editor: %s';

  { RSPcCliHelpLsp }
  RSPcCliHelpLsp = 'Run the language server on stdin/stdout (takes no other argument)';

  { RSPcCliLspAlone }
  RSPcCliLspAlone = 'Error: --lsp takes no other argument';

  { RSPcCliHelpDebug }
  RSPcCliHelpDebug = 'Build debug, then debug it in the console debugger (x86_64-windows-gnu)';
  { RSPcCliHelpHost }
  RSPcCliHelpHost = 'With -d on a dll: the exe that loads it';
  { RSPcCliNeedsHost }
  RSPcCliNeedsHost = 'Error: %s requires the host executable';
  { RSPcCliDebugWithRun }
  RSPcCliDebugWithRun = 'Error: -r and -d cannot be used together';
  { RSPcCliDebugWithOptimize }
  RSPcCliDebugWithOptimize = 'Error: -d builds debug; -opt cannot be used with it';
  { RSPcCliHostWithoutDebug }
  RSPcCliHostWithoutDebug = 'Error: --host is used with -d only';
  { RSPcCliHelpTerminal }
  RSPcCliHelpTerminal = 'With -r: the program''s terminal is the named pipe an editor listens on';
  { RSPcCliNeedsPipe }
  RSPcCliNeedsPipe = 'Error: %s requires the named pipe (\\.\pipe\...)';
  { RSPcCliTerminalWithoutRun }
  RSPcCliTerminalWithoutRun = 'Error: --terminal is used with -r only';
  { RSPcCliHelpArgs }
  RSPcCliHelpArgs = 'Everything after -- is passed, as written, to the program -r or -d runs';
  { RSPcCliArgsWithoutRun }
  RSPcCliArgsWithoutRun = 'Error: -- (program arguments) is used with -r or -d only';
  { RSPcCliBadHost }
  RSPcCliBadHost = 'Error: invalid host %s: %s';
  { RSPcCliDebugLib }
  RSPcCliDebugLib = 'Error: a static library cannot be debugged on its own: debug the program that links it';
  { RSPcCliDebugDllNoHost }
  RSPcCliDebugDllNoHost = 'Error: a dll is debugged in the exe that loads it: add --host <exe>';
  { RSPcCliDebugHostOnExe }
  RSPcCliDebugHostOnExe = 'Error: --host is for a dll; this program is an exe';
  { RSPcCliHelpDap }
  RSPcCliHelpDap = 'Run the debug adapter (DAP) on stdin/stdout (takes no other argument)';
  { RSPcCliHelpClean }
  RSPcCliHelpClean = 'Clear a pcpp output folder (default: the current folder), after checks and a y/N question';
  { RSPcCliHelpDryRun }
  RSPcCliHelpDryRun = 'With --clean: check and list what would be deleted, delete nothing';
  { RSPcCliDryRunWithoutClean }
  RSPcCliDryRunWithoutClean = 'Error: --dry-run is used with --clean only';
  { RSPcCliCleanWithOption }
  RSPcCliCleanWithOption = 'Error: --clean builds nothing and takes no %s';
  { RSPcCliCleanHeader }
  RSPcCliCleanHeader = 'pcpp output folder %s. To delete:';
  { RSPcCliCleanTarget }
  RSPcCliCleanTarget = '  %s  (%d files, %s)';
  { RSPcCliCleanEmpty }
  RSPcCliCleanEmpty = 'Nothing to clean in %s.';
  { RSPcCliCleanDryRun }
  RSPcCliCleanDryRun = 'Dry run: nothing deleted.';
  { RSPcCliCleanNotConsole }
  RSPcCliCleanNotConsole = 'Error: --clean asks a person, and stdin is not a console: nothing deleted';
  { RSPcCliCleanAsk }
  RSPcCliCleanAsk = 'Delete these %d? [y/N] ';
  { RSPcCliCleanNothing }
  RSPcCliCleanNothing = 'Nothing deleted.';
  { RSPcCliCleanDone }
  RSPcCliCleanDone = 'Deleted %d.';
  { RSPcCliCleanFailed }
  RSPcCliCleanFailed = 'Clean failed.';
  { RSPcCliDapAlone }
  RSPcCliDapAlone = 'Error: --dap takes no other argument';

  //--------------------------------------------------------------------------
  // LSP server (PaskalCPP.LSP.Server)
  //--------------------------------------------------------------------------

  { RSLspParseError }
  RSLspParseError = 'Invalid JSON';
  { RSLspInvalidRequest }
  RSLspInvalidRequest = 'Invalid JSON-RPC message';
  { RSLspNotInitialized }
  RSLspNotInitialized = 'The server is not initialized';
  { RSLspShutDown }
  RSLspShutDown = 'The server is shut down';
  { RSLspAlreadyInitialized }
  RSLspAlreadyInitialized = 'The server is already initialized';
  { RSLspMethodNotFound }
  RSLspMethodNotFound = 'Unhandled method "%s"';
  { RSLspInternalError }
  RSLspInternalError = 'Internal error in "%s": %s';
  { RSLspMalformed }
  RSLspMalformed = 'A message with a malformed header was skipped';
  { RSLspBadParams }
  RSLspBadParams = 'Invalid parameters for "%s"';

  //--------------------------------------------------------------------------
  // LSP formatter (PaskalCPP.LSP.Formatter)
  //--------------------------------------------------------------------------

  { RSLspFmtInternal }
  RSLspFmtInternal = 'Formatting failed: %s';
  { RSLspFmtRefuseSyntax }
  RSLspFmtRefuseSyntax = 'The file has syntax errors: it was not formatted';
  { RSLspFmtRefuseVerify }
  RSLspFmtRefuseVerify = 'Formatting would change the code: nothing was changed';
  { RSLspFmtGapInvariant }
  RSLspFmtGapInvariant = 'Token offsets overlap at byte %d';

  //--------------------------------------------------------------------------
  // Debugger (PaskalCPP.Debug.*)
  //--------------------------------------------------------------------------

  { RSDbgProgramNotFound }
  RSDbgProgramNotFound = 'Program to debug not found: %s';
  { RSDbgHostNotFound }
  RSDbgHostNotFound = 'Host program not found: %s';
  { RSDbgStartFailed }
  RSDbgStartFailed = 'Cannot start %s under the debugger: %s';
  { RSDbgLoopFailed }
  RSDbgLoopFailed = 'The debug loop failed: %s';
  { RSDbgReadFailed }
  RSDbgReadFailed = 'Cannot read the program''s memory at $%x: %s';
  { RSDbgPatchFailed }
  RSDbgPatchFailed = 'Cannot patch the program''s code at $%x: %s';
  { RSDbgContextFailed }
  RSDbgContextFailed = 'Cannot get or set the context of thread %d: %s';
  { RSDbgHostExitedEarly }
  RSDbgHostExitedEarly = 'The host exited (code %d) before it loaded %s';
  { RSDbgPauseFailed }
  RSDbgPauseFailed = 'Cannot pause the program: %s';
  { RSDbgSymInitFailed }
  RSDbgSymInitFailed = 'The symbol handler cannot start: %s';
  { RSDbgSymNotOpen }
  RSDbgSymNotOpen = 'The symbol handler is not open';
  { RSDbgDbgHelpEntryMissing }
  RSDbgDbgHelpEntryMissing = '%s has no entry point %s';
  { RSDbgSymLoadFailed }
  RSDbgSymLoadFailed = 'Cannot load the symbols of %s: %s';
  { RSDbgNoDebugInfo }
  RSDbgNoDebugInfo = 'No line numbers for %s: its .pdb must be beside it (build with -opt debug)';
  { RSDbgSymLookupFailed }
  RSDbgSymLookupFailed = 'Symbol lookup failed (%s): %s';
  { RSDbgNoSources }
  RSDbgNoSources = 'No sources for the program: C++ names and types are shown';
  { RSDbgRunning }
  RSDbgRunning = 'The program is running: the command needs it stopped';
  { RSDbgNoEntry }
  RSDbgNoEntry = '%s did not reach its entry stop';
  { RSDbgSourceUnreadable }
  RSDbgSourceUnreadable = 'Cannot read %s (C++ names are shown for it): %s';
  { RSDbgNoCode }
  RSDbgNoCode = 'No code at %s:%d';
  { RSDbgBpPending }
  RSDbgBpPending = 'Pending: its code is not loaded yet';
  { RSDbgValueUnreadable }
  RSDbgValueUnreadable = '<unreadable>';
  { RSDbgWeakExpired }
  // PLAN-OBJECT O14: a weak whose object is gone (alive(W) = false)
  RSDbgWeakExpired = 'expired';
  { RSDbgEvalUnsupported }
  RSDbgEvalUnsupported = 'Cannot show %s: only a name, then .member, ->member, [integer] and ^';
  { RSDbgEvalUnknownName }
  RSDbgEvalUnknownName = 'No variable named %s here';
  { RSDbgEvalNoMember }
  RSDbgEvalNoMember = '%s has no member %s';
  { RSDbgEvalNotPointer }
  RSDbgEvalNotPointer = '%s is not a pointer, or it is nil';
  { RSDbgEvalBadIndex }
  RSDbgEvalBadIndex = '%s has no element [%d]';
  { RSDbgNotWin64 }
  RSDbgNotWin64 = 'Debugging needs the %s target; this program builds for %s';

  //--------------------------------------------------------------------------
  // PaskalCPP.Debug.REPL (the console debugger, pcpp -d)
  //--------------------------------------------------------------------------
  { RSDbgReplTitle }
  RSDbgReplTitle = 'PaskalCPP debugger';
  { RSDbgReplProgram }
  RSDbgReplProgram = 'Program: %s';
  { RSDbgReplHost }
  RSDbgReplHost = 'Host: %s';
  { RSDbgReplHint }
  RSDbgReplHint = 'Type h for the commands';
  { RSDbgReplSourceBreakpoints }
  RSDbgReplSourceBreakpoints = '%d breakpoint(s) from @breakpoint';
  { RSDbgReplStopped }
  RSDbgReplStopped = 'Stopped (%s) in %s at %s:%d';
  { RSDbgReplStoppedNoLine }
  RSDbgReplStoppedNoLine = 'Stopped (%s) in %s';
  { RSDbgReplReasonEntry }
  RSDbgReplReasonEntry = 'entry';
  { RSDbgReplReasonBreakpoint }
  RSDbgReplReasonBreakpoint = 'breakpoint';
  { RSDbgReplReasonStep }
  RSDbgReplReasonStep = 'step';
  { RSDbgReplReasonPause }
  RSDbgReplReasonPause = 'pause';
  { RSDbgReplReasonException }
  RSDbgReplReasonException = 'exception $%.8x';
  { RSDbgReplReasonFirstChance }
  RSDbgReplReasonFirstChance = 'exception $%.8x, first chance';
  { RSDbgReplExited }
  RSDbgReplExited = 'Program exited with code %d';
  { RSDbgReplStillRunning }
  RSDbgReplStillRunning = 'Still running after %d ms; q ends it';
  { RSDbgReplNotRunning }
  RSDbgReplNotRunning = 'The program is not running: r starts it again';
  { RSDbgReplHeldAtEntry }
  RSDbgReplHeldAtEntry = 'Held at entry (no breakpoint would stop it): set one with b, c runs the program';
  { RSDbgReplAtEntry }
  RSDbgReplAtEntry = 'The program has not started yet: c runs it';
  { RSDbgReplUnknown }
  RSDbgReplUnknown = 'Unknown command: %s (h shows the commands)';
  { RSDbgReplBpUsage }
  RSDbgReplBpUsage = 'Usage: b <file>:<line>, or b <line> for the current file';
  { RSDbgReplBpUnknownFile }
  RSDbgReplBpUnknownFile = 'No module of the program is named %s';
  { RSDbgReplBpBadPath }
  RSDbgReplBpBadPath = 'Invalid file %s: %s';
  { RSDbgReplBpSet }
  RSDbgReplBpSet = 'Breakpoint #%d at %s:%d';
  { RSDbgReplBpMoved }
  RSDbgReplBpMoved = 'Breakpoint #%d at %s:%d (code at line %d)';
  { RSDbgReplBpPending }
  RSDbgReplBpPending = 'Breakpoint #%d at %s:%d (%s)';
  { RSDbgReplBpNextRun }
  RSDbgReplBpNextRun = 'Breakpoint #%d at %s:%d (placed at the next run)';
  { RSDbgReplBpNone }
  RSDbgReplBpNone = 'No breakpoints';
  { RSDbgReplBpDeleted }
  RSDbgReplBpDeleted = 'Breakpoint #%d deleted';
  { RSDbgReplBpNoId }
  RSDbgReplBpNoId = 'No breakpoint #%s (bl lists them)';
  { RSDbgReplBpCleared }
  RSDbgReplBpCleared = 'All breakpoints deleted';
  { RSDbgReplFrame }
  RSDbgReplFrame = '%s#%d %s at %s:%d';
  { RSDbgReplFrameNoLine }
  RSDbgReplFrameNoLine = '%s#%d %s ($%x)';
  { RSDbgReplFrameBad }
  RSDbgReplFrameBad = 'No frame %s (bt lists them)';
  { RSDbgReplNoFrames }
  RSDbgReplNoFrames = 'No stack frames';
  { RSDbgReplScopeParams }
  RSDbgReplScopeParams = 'Params:';
  { RSDbgReplScopeLocals }
  RSDbgReplScopeLocals = 'Locals:';
  { RSDbgReplScopeGlobals }
  RSDbgReplScopeGlobals = 'Globals:';
  { RSDbgReplNoValues }
  RSDbgReplNoValues = '  (none)';
  { RSDbgReplValue }
  RSDbgReplValue = '  %s: %s = %s';
  { RSDbgReplValueNoType }
  RSDbgReplValueNoType = '  %s = %s';
  { RSDbgReplEval }
  RSDbgReplEval = '%s = %s';
  { RSDbgReplEvalUsage }
  RSDbgReplEvalUsage = 'Usage: p <name>, then members (.x), elements ([n]) or targets (^)';
  { RSDbgReplThread }
  RSDbgReplThread = '%sThread %d%s';
  { RSDbgReplThreadMain }
  RSDbgReplThreadMain = ' (main)';
  { RSDbgReplSourceUnreadable }
  RSDbgReplSourceUnreadable = 'Source %s cannot be read: %s';
  { RSDbgReplInputFailed }
  RSDbgReplInputFailed = 'Input cannot be read: %s';
  { RSDbgReplHelp }
  RSDbgReplHelp =
    'Commands:' + #13#10 +
    '  b <file>:<line>  set a breakpoint (b <line>: in the current file)' + #13#10 +
    '  bl               list the breakpoints' + #13#10 +
    '  bd <n>           delete breakpoint n' + #13#10 +
    '  bc               delete every breakpoint' + #13#10 +
    '  c                continue' + #13#10 +
    '  n                step over (the next line)' + #13#10 +
    '  s                step into' + #13#10 +
    '  finish           step out' + #13#10 +
    '  bt               the call stack' + #13#10 +
    '  f <n>            select frame n (locals and p look at it)' + #13#10 +
    '  locals           the variables of the selected frame' + #13#10 +
    '  p <expr>         print a name, a member, an element or a target' + #13#10 +
    '  src              the source around the selected frame' + #13#10 +
    '  threads          the threads' + #13#10 +
    '  r                run the program again' + #13#10 +
    '  Ctrl+C           pause the running program' + #13#10 +
    '  h                this help' + #13#10 +
    '  q                quit (ends the program)';

  // PaskalCPP.Debug.DAP: the debug adapter (pcpp --dap)
  { RSDbgDapMalformed }
  RSDbgDapMalformed = 'A message with a bad header was skipped';
  { RSDbgDapNotRequest }
  RSDbgDapNotRequest = 'A message that is not a DAP request was skipped';
  { RSDbgDapUnknownCommand }
  RSDbgDapUnknownCommand = 'Unsupported request: %s';
  { RSDbgDapNotLaunched }
  RSDbgDapNotLaunched = 'No program is being debugged';
  { RSDbgDapLaunchTwice }
  RSDbgDapLaunchTwice = 'A program is already being debugged';
  { RSDbgDapNoProgram }
  RSDbgDapNoProgram = 'launch needs "program": a .pcpp source, or a built .exe or .dll';
  { RSDbgDapBadArgument }
  RSDbgDapBadArgument = '%s: argument "%s" is not valid';
  { RSDbgDapBadPath }
  RSDbgDapBadPath = 'Invalid path %s: %s';
  { RSDbgDapLib }
  RSDbgDapLib = 'A static library cannot be debugged on its own: debug the program that links it';
  { RSDbgDapDllNoHost }
  RSDbgDapDllNoHost = 'A dll is debugged in the exe that loads it: launch it with "host"';
  { RSDbgDapHostOnExe }
  RSDbgDapHostOnExe = '"host" is for a dll; this program is an exe';
  { RSDbgDapBuildFailed }
  RSDbgDapBuildFailed = 'The program did not build';
  { RSDbgDapLaunchFailed }
  RSDbgDapLaunchFailed = 'The program could not be started';
  { RSDbgDapRequestFailed }
  RSDbgDapRequestFailed = '%s failed';
  { RSDbgDapBadFrame }
  RSDbgDapBadFrame = 'Frame %d is not valid: the program ran since';
  { RSDbgDapBadReference }
  RSDbgDapBadReference = 'Variables reference %d is not valid: the program ran since';
  { RSDbgDapScopeParams }
  RSDbgDapScopeParams = 'Parameters';
  { RSDbgDapScopeLocals }
  RSDbgDapScopeLocals = 'Locals';
  { RSDbgDapScopeGlobals }
  RSDbgDapScopeGlobals = 'Globals';
  { RSDbgDapThreadMain }
  RSDbgDapThreadMain = 'Main thread (%d)';
  { RSDbgDapThread }
  RSDbgDapThread = 'Thread %d';
  { RSDbgDapExceptionAll }
  RSDbgDapExceptionAll = 'All exceptions (first chance)';
  { RSDbgDapException }
  RSDbgDapException = 'Exception $%.8x';
  { RSDbgDapExceptionFirstChance }
  RSDbgDapExceptionFirstChance = 'Exception $%.8x (first chance)';

  //--------------------------------------------------------------------------
  // pcppdev (UPCPPDev): the project's dev tool, never shipped
  //--------------------------------------------------------------------------

  { RSPcDevBanner }
  RSPcDevBanner = 'PaskalCPP Dev Tool v%s';
  { RSPcDevHelpUsageHeader }
  RSPcDevHelpUsageHeader = 'USAGE:';
  { RSPcDevHelpVerbsArg }
  RSPcDevHelpVerbsArg = '<verb> [<verb> ...]';
  { RSPcDevHelpVerbsHeader }
  RSPcDevHelpVerbsHeader = 'VERBS:';
  { RSPcDevHelpEditorAsar }
  RSPcDevHelpEditorAsar = 'Pack repo\projects\editor into the editor''s app.asar';
  { RSPcDevHelpVerInfo }
  RSPcDevHelpVerInfo = 'Stamp editor.exe and pcpp.exe with the PaskalCPP version (%s) and icon';
  { RSPcDevHelpHelp }
  RSPcDevHelpHelp = 'Display this help message';
  { RSPcDevUnknownArg }
  RSPcDevUnknownArg = 'Error: unknown argument: %s';
  { RSPcDevException }
  RSPcDevException = 'EXCEPTION: %s';
  { RSPcDevSourceNotFound }
  RSPcDevSourceNotFound = 'Editor source not found: %s has no package.json';
  { RSPcDevRuntimeNotFound }
  RSPcDevRuntimeNotFound = 'Editor runtime not found: %s';
  { RSPcDevPackageNotObject }
  RSPcDevPackageNotObject = 'Editor package.json is not a JSON object: %s';
  { RSPcDevPackageFailed }
  RSPcDevPackageFailed = 'Cannot prepare package.json from %s: %s';
  { RSPcDevAsarFailed }
  RSPcDevAsarFailed = 'Cannot write %s: %s';
  { RSPcDevTempNotRemoved }
  RSPcDevTempNotRemoved = 'Cannot remove a packing temp file: %s';
  { RSPcDevPacked }
  RSPcDevPacked = 'Packed %s (%d files, %d bytes, version %s)';
  { RSPcDevUnpackedRemoved }
  RSPcDevUnpackedRemoved = 'Removed unpacked %s';
  { RSPcDevUnpackedNotRemoved }
  RSPcDevUnpackedNotRemoved = 'Cannot remove %s (it shadows app.asar): %s';
  { RSPcDevIconNotFound }
  RSPcDevIconNotFound = 'Editor icon not found: %s';
  { RSPcDevIconStamped }
  RSPcDevIconStamped = 'Icon %s stamped on %s';
  { RSPcDevIconFailed }
  RSPcDevIconFailed = 'Cannot stamp the icon on %s (is it running?): %s';
  { RSPcDevVersionStamped }
  RSPcDevVersionStamped = 'Version %s stamped on %s';
  { RSPcDevVersionFailed }
  RSPcDevVersionFailed = 'Cannot stamp the version on %s (is it running?): %s';
  { RSPcDevExeNotFound }
  RSPcDevExeNotFound = 'Program to stamp not found: %s';

implementation

end.
