/*******************************************************************************
 * PaskalCPP™ Programming Language
 *
 * Copyright © 2026-present tinyBigGAMES™ LLC
 * All Rights Reserved.
 *
 * https://paskalcpp.org
 *
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the
 * Mozilla Public License, v. 2.0. If a copy of the MPL
 * was not distributed with this file, You can obtain one
 * at https://mozilla.org/MPL/2.0/.
 *
 * ---
 * The file's own description is the comment below.
 ******************************************************************************/
/* std_hookio_c.c - C source of std_hookio_lib.pcpp (a static library) for
   std_hookio.pcpp (see its header): plain C that reads a file through the
   stdio stream family by its C names, as any C library does (raylib's
   decoders, stb_image, ...). The references sit in an archive member, so the
   HookIO hooks in the program bind them only because the hooks are link-time
   and cover static libraries. One path opens an io:// virtual file, another a
   real file; both run the same reads, and the program compares the bytes.

   std_hookio_c_read fills ABuffer (ACap bytes) from APath with binary-safe
   calls: fseek to the end + ftell for the size, rewind, fgetc, ungetc,
   fread, ferror, feof, then fclose. It returns the number of bytes placed in
   ABuffer, or -1 on any failure; *AReportSize gets the size ftell reported.
   The same calls run on a virtual file and a real one (the program's own
   exe), so the program compares both with the bytes it knows.

   std_hookio_c_readtext reads a text file with fgets (a 6-byte buffer, so
   longer lines split) and returns the line count, the text joined in AText.

   std_hookio_c_write writes ACount bytes of AByte to APath (opened "ab")
   with fwrite and fputc, flushes and closes; it returns the count written
   or -1. The program checks the bytes in the IO.

   Plain fopen / fread / etc. here: the mingw headers declare some of these
   dllimport, so on Windows the program defines the matching import slots with
   HOOKABI_IMPORT_SLOT (fopen, fread, ... in HookIO.pcpp).

   std_hookio_c_big seeks a stream past 4 GiB with the target's 64-bit names
   (Windows _fseeki64 / _ftelli64, Linux fseeko / ftello, both fseeko64 /
   ftello64), reads with fgetc / getc, and asks ftell (a long: 32 bits on
   Windows) there; std_hookio_c_print writes with fprintf, vfprintf (through
   a va_list helper) and, on Windows, __mingw_fprintf;
   std_hookio_c_widewrite writes with the wide names (fputwc, putwc,
   fputws, fwide) under a given locale, mixed with the narrow ones;
   std_hookio_c_scan reads numbers with fscanf and then, by the variant
   asked for, with the target's other scan names (Linux the plain fscanf /
   vfscanf symbols beside the header's __isoc99_ names, Windows
   __mingw_fscanf and fscanf_s, vfscanf on both); std_hookio_c_scanlong
   scans past more whitespace than one stand-in window holds; on Linux
   std_hookio_c_chkread / std_hookio_c_chkprint call glibc's fortified names
   (__fgets_chk, __fgets_unlocked_chk, __fread_chk, __fread_unlocked_chk,
   __fprintf_chk, __vfprintf_chk) by name. Each fills an
   int64_t results array the program checks slot by slot; a slot never
   reached stays STD_HOOKIO_C_UNREACHED. */

/* glibc declares fseeko64 / ftello64 only with this, before any header */
#if defined(__linux__)
#define _LARGEFILE64_SOURCE 1
#endif

#include <errno.h>
#include <locale.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#if defined(_WIN32)
#include <windows.h>
#else
#include <signal.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

/* A result slot the function did not reach */
#define STD_HOOKIO_C_UNREACHED (-2)

/* Reads APath through the stdio stream family into ABuffer; returns the byte
   count, or -1. *AReportSize gets the size ftell reported. */
long std_hookio_c_read(const char *APath, unsigned char *ABuffer, long ACap,
                       long *AReportSize)
{
  FILE *LFile;
  long LSize;
  long LCount;
  int LFirst;

  *AReportSize = -1;
  LFile = fopen(APath, "rb");
  if (LFile == NULL)
    return -1;

  /* Size by seek to the end then ftell, then back to the start */
  if (fseek(LFile, 0, SEEK_END) != 0)
  {
    fclose(LFile);
    return -1;
  }
  LSize = ftell(LFile);
  *AReportSize = LSize;
  rewind(LFile);

  LCount = 0;
  /* The first byte with fgetc, then pushed back so fread sees it again */
  LFirst = fgetc(LFile);
  if (LFirst == EOF)
  {
    fclose(LFile);
    return -1;
  }
  if (ungetc(LFirst, LFile) == EOF)
  {
    fclose(LFile);
    return -1;
  }

  /* Everything with fread (binary safe: no fgets / strlen here, a real file
     holds NUL bytes) */
  while (LCount < ACap)
  {
    size_t LGot = fread(ABuffer + LCount, 1, (size_t)(ACap - LCount), LFile);
    if (LGot == 0)
      break;
    LCount += (long)LGot;
  }
  if (ferror(LFile))
  {
    fclose(LFile);
    return -1;
  }
  /* feof after reading everything available */
  (void)feof(LFile);
  if (fclose(LFile) != 0)
    return -1;
  (void)LSize;
  return LCount;
}

/* Reads the text file APath line by line with fgets into AText (ACap bytes,
   lines joined as read, '\n' kept, NUL-terminated); returns the line count,
   or -1. The lines are short: a buffer of 6 splits a longer one, as fgets
   does. */
long std_hookio_c_readtext(const char *APath, char *AText, long ACap)
{
  FILE *LFile;
  char LLine[6];
  long LLines;
  long LUsed;
  size_t LGot;

  if (ACap <= 0)
    return -1;
  AText[0] = '\0';
  LFile = fopen(APath, "rb");
  if (LFile == NULL)
    return -1;
  LLines = 0;
  LUsed = 0;
  while (fgets(LLine, (int)sizeof(LLine), LFile) != NULL)
  {
    LGot = strlen(LLine);
    if ((LUsed + (long)LGot) >= ACap)
      break;
    memcpy(AText + LUsed, LLine, LGot);
    LUsed += (long)LGot;
    AText[LUsed] = '\0';
    ++LLines;
  }
  /* fgets ended at the end, not on an error */
  if ((!feof(LFile)) || ferror(LFile))
  {
    fclose(LFile);
    return -1;
  }
  if (fclose(LFile) != 0)
    return -1;
  return LLines;
}

/* Writes ACount copies of AByte to APath with the write family; returns the
   count written, or -1. */
long std_hookio_c_write(const char *APath, int AByte, long ACount)
{
  FILE *LFile;
  long LWritten;
  long LHalf;
  unsigned char LChunk[32];
  int LI;

  /* "ab": a registered IO refuses "wb" (it would empty under other handles);
     append writes to a fresh growable IO from its start */
  LFile = fopen(APath, "ab");
  if (LFile == NULL)
    return -1;

  LWritten = 0;
  LHalf = ACount / 2;

  /* The first half with fwrite in chunks */
  for (LI = 0; LI < (int)sizeof(LChunk); ++LI)
    LChunk[LI] = (unsigned char)AByte;
  while (LWritten < LHalf)
  {
    long LWant = LHalf - LWritten;
    size_t LGot;
    if (LWant > (long)sizeof(LChunk))
      LWant = (long)sizeof(LChunk);
    LGot = fwrite(LChunk, 1, (size_t)LWant, LFile);
    if (LGot != (size_t)LWant)
    {
      fclose(LFile);
      return -1;
    }
    LWritten += (long)LGot;
  }

  /* The rest one byte at a time with fputc */
  while (LWritten < ACount)
  {
    if (fputc(AByte, LFile) == EOF)
    {
      fclose(LFile);
      return -1;
    }
    ++LWritten;
  }

  if (fflush(LFile) != 0)
  {
    fclose(LFile);
    return -1;
  }
  if (fclose(LFile) != 0)
    return -1;
  return LWritten;
}

/* Every slot of AResults to STD_HOOKIO_C_UNREACHED */
static void std_hookio_c_unreached(int64_t *AResults, int ACount)
{
  int LI;

  for (LI = 0; LI < ACount; ++LI)
    AResults[LI] = STD_HOOKIO_C_UNREACHED;
}

/* Seeks APath (a stream larger than 4 GiB) to AOffset and around its end
   with the 64-bit names. AResults (7 slots):
     0 the 64-bit tell after the seek to AOffset from the start
     1 fgetc there
     2 ftell there (long: 32 bits on Windows)
     3 errno after that ftell (cleared before it)
     4 ftello64 after fseeko64 to 16 before the end
     5 the 64-bit tell after a seek of 5 from the current place
     6 getc there */
void std_hookio_c_big(const char *APath, int64_t AOffset, int64_t *AResults)
{
  FILE *LFile;

  std_hookio_c_unreached(AResults, 7);
  LFile = fopen(APath, "rb");
  if (LFile == NULL)
    return;

  /* From the start, past 4 GiB: the target's own 64-bit pair */
#if defined(_WIN32)
  if (_fseeki64(LFile, AOffset, SEEK_SET) == 0)
    AResults[0] = _ftelli64(LFile);
#else
  if (fseeko(LFile, (off_t)AOffset, SEEK_SET) == 0)
    AResults[0] = (int64_t)ftello(LFile);
#endif
  AResults[1] = fgetc(LFile);

  /* ftell's long cannot hold this place on Windows (-1, EINVAL as ucrt) */
  errno = 0;
  AResults[2] = ftell(LFile);
  AResults[3] = errno;

  /* From the end with the *64 pair, a name on both targets */
  if (fseeko64(LFile, -16, SEEK_END) == 0)
    AResults[4] = (int64_t)ftello64(LFile);

  /* From the current place, the target's own pair again */
#if defined(_WIN32)
  if (_fseeki64(LFile, 5, SEEK_CUR) == 0)
    AResults[5] = _ftelli64(LFile);
#else
  if (fseeko(LFile, 5, SEEK_CUR) == 0)
    AResults[5] = (int64_t)ftello(LFile);
#endif
  AResults[6] = getc(LFile);
  fclose(LFile);
}

/* Seeks APath to AOffset from the start with the target's 64-bit name (a
   real file may be shorter: both CRTs allow a seek past the end) and reads
   ftell's long there, so a virtual file and a real one compare slot by slot.
   AResults (3 slots):
     0 the 64-bit tell after the seek
     1 ftell there (long: 32 bits on Windows)
     2 errno after that ftell (cleared before it) */
void std_hookio_c_tellpast(const char *APath, int64_t AOffset, int64_t *AResults)
{
  FILE *LFile;

  std_hookio_c_unreached(AResults, 3);
  LFile = fopen(APath, "rb");
  if (LFile == NULL)
    return;
#if defined(_WIN32)
  if (_fseeki64(LFile, AOffset, SEEK_SET) == 0)
    AResults[0] = _ftelli64(LFile);
#else
  if (fseeko(LFile, (off_t)AOffset, SEEK_SET) == 0)
    AResults[0] = (int64_t)ftello(LFile);
#endif
  errno = 0;
  AResults[1] = ftell(LFile);
  AResults[2] = errno;
  fclose(LFile);
}

/* vfprintf through a va_list, as a C library's own logging helper does */
static int std_hookio_c_vprint(FILE *AFile, const char *AFormat, ...)
{
  va_list LArgs;
  int LResult;

  va_start(LArgs, AFormat);
  LResult = vfprintf(AFile, AFormat, LArgs);
  va_end(LArgs);
  return LResult;
}

/* Writes "a1|bx|c3|" to APath (opened "ab") with the printf family.
   AResults (4 slots): 0 fprintf's count, 1 vfprintf's, 2 the third write's
   (Windows __mingw_fprintf, Linux fprintf again: the same bytes on both),
   3 fclose. */
void std_hookio_c_print(const char *APath, int64_t *AResults)
{
  FILE *LFile;

  std_hookio_c_unreached(AResults, 4);
  LFile = fopen(APath, "ab");
  if (LFile == NULL)
    return;
  AResults[0] = fprintf(LFile, "a%d|", 1);
  AResults[1] = std_hookio_c_vprint(LFile, "b%s|", "x");
#if defined(_WIN32)
  AResults[2] = __mingw_fprintf(LFile, "c%d|", 3);
#else
  AResults[2] = fprintf(LFile, "c%d|", 3);
#endif
  AResults[3] = fclose(LFile);
}

/* Wide output rows (PLAN-HOOKABI W1). std_hookio_c_widewrite sets the
   locale ALocale (LC_ALL), opens APath with AMode, runs variant AVariant's
   steps and records after each one (6 slots per step, at most
   STD_HOOKIO_C_WSTEPS steps): the call's value, errno (cleared before),
   ferror, fwide(f, 0), ftell and ftell's errno. Then slot 72: the locale
   was set (1), 73: the open succeeded (1), 74: fclose, 75: the file's size
   read back with "rb", 76: an FNV-1a hash of all its bytes, 77..140 its
   first 64 bytes (-1 past the end). The locale is put back before it
   returns. The program runs it on a handle and on a real file and compares
   every slot. Variants: 0 single characters (ASCII, a 2-byte one, one "C"
   cannot map, one glibc transliterates, a newline), fputws, putwc and the
   real putwc symbol; 1 more text than a buffer holds; 2 narrow first, then
   the wide calls; 3 wide first, then fputs, fwrite, fprintf, fflush,
   fgetc, fputc and putwc; 4 / 5 fwide set wide / byte first; 6 unbuffered; 7 line
   buffered; 8 fseek between writes (an update mode); 9 append; 10 a
   character neither locale's charset maps, then more text; 11 a surrogate
   pair split over two fputwc calls and a lone surrogate. */
#define STD_HOOKIO_C_WSTEPS 12
#define STD_HOOKIO_C_WSLOTS 141

/* One step: AValue, then the stream's state after it */
static void std_hookio_c_wrecord(FILE *AFile, int64_t *AResults, int *AStep, int64_t AValue,
                                 int AErrno)
{
  int64_t *LSlot;

  if (*AStep >= STD_HOOKIO_C_WSTEPS)
    return;
  LSlot = AResults + (*AStep * 6);
  LSlot[0] = AValue;
  LSlot[1] = AErrno;
  LSlot[2] = (ferror(AFile) != 0) ? 1 : 0;
  LSlot[3] = fwide(AFile, 0);
  errno = 0;
  LSlot[4] = (int64_t)ftell(AFile);
  LSlot[5] = errno;
  ++*AStep;
}

/* A call recorded as a step: errno cleared first, read right after it */
#define STD_HOOKIO_C_WSTEP(ACall) \
  do \
  { \
    int64_t LValue; \
    errno = 0; \
    LValue = (int64_t)(ACall); \
    std_hookio_c_wrecord(LFile, AResults, &LStep, LValue, errno); \
  } \
  while (0)

/* The file read back after fclose: size, hash and first bytes */
static void std_hookio_c_wreadback(const char *APath, int64_t *AResults)
{
  FILE *LFile;
  int LByte;
  int64_t LCount = 0;
  uint64_t LHash = 14695981039346656037ULL;

  LFile = fopen(APath, "rb");
  if (LFile == NULL)
    return;
  while ((LByte = fgetc(LFile)) != EOF)
  {
    if (LCount < 64)
      AResults[77 + LCount] = LByte;
    LHash = (LHash ^ (uint64_t)LByte) * 1099511628211ULL;
    ++LCount;
  }
  fclose(LFile);
  AResults[75] = LCount;
  AResults[76] = (int64_t)LHash;
}

void std_hookio_c_widewrite(const char *APath, const char *AMode, const char *ALocale,
                            int AVariant, int64_t *AResults)
{
  FILE *LFile;
  int LStep = 0;
  int LI;
  char LSaved[256];
  const char *LOld;
  wchar_t LBig[5400];
  wchar_t LLone[3];

  std_hookio_c_unreached(AResults, STD_HOOKIO_C_WSLOTS);
  for (LI = 77; LI < STD_HOOKIO_C_WSLOTS; ++LI)
    AResults[LI] = -1;
  LOld = setlocale(LC_ALL, NULL);
  snprintf(LSaved, sizeof(LSaved), "%s", (LOld != NULL) ? LOld : "C");
  AResults[72] = (setlocale(LC_ALL, ALocale) != NULL) ? 1 : 0;
  LFile = fopen(APath, AMode);
  AResults[73] = (LFile != NULL) ? 1 : 0;
  if (LFile == NULL)
  {
    setlocale(LC_ALL, LSaved);
    return;
  }
  switch (AVariant)
  {
  case 0:
    STD_HOOKIO_C_WSTEP(fputwc(L'A', LFile));
    STD_HOOKIO_C_WSTEP(fputwc(L'\u00e9', LFile));
    STD_HOOKIO_C_WSTEP(fputwc(L'\u20ac', LFile));
    STD_HOOKIO_C_WSTEP(fputwc(L'\u00ab', LFile));
    STD_HOOKIO_C_WSTEP(fputwc(L'\n', LFile));
    STD_HOOKIO_C_WSTEP(fputws(L"x\u00e9y\n", LFile));
    STD_HOOKIO_C_WSTEP(putwc(L'Z', LFile));
    STD_HOOKIO_C_WSTEP((putwc)(L'Q', LFile));
    break;
  case 1:
    for (LI = 0; LI < 5000; ++LI)
      LBig[LI] = L'w';
    LBig[5000] = L'\u00e9';
    for (LI = 5001; LI < 5300; ++LI)
      LBig[LI] = L'v';
    LBig[5300] = L'\0';
    STD_HOOKIO_C_WSTEP(fputws(LBig, LFile));
    STD_HOOKIO_C_WSTEP(fputwc(L'.', LFile));
    STD_HOOKIO_C_WSTEP(fputws(LBig + 4990, LFile));
    STD_HOOKIO_C_WSTEP(fflush(LFile));
    break;
  case 2:
    STD_HOOKIO_C_WSTEP(fputs("ab", LFile));
    STD_HOOKIO_C_WSTEP(fputws(L"cd", LFile));
    STD_HOOKIO_C_WSTEP(fputwc(L'e', LFile));
    STD_HOOKIO_C_WSTEP(putwc(L'\u00e9', LFile));
    STD_HOOKIO_C_WSTEP(fputc('g', LFile));
    STD_HOOKIO_C_WSTEP(fflush(LFile));
    break;
  case 3:
    STD_HOOKIO_C_WSTEP(fputws(L"cd", LFile));
    STD_HOOKIO_C_WSTEP(fputs("ab", LFile));
    STD_HOOKIO_C_WSTEP(fwrite("xy", 1, 2, LFile));
    STD_HOOKIO_C_WSTEP(fprintf(LFile, "%d", 5));
    /* C requires the fflush between a write and a read */
    STD_HOOKIO_C_WSTEP(fflush(LFile));
    STD_HOOKIO_C_WSTEP(fgetc(LFile));
    STD_HOOKIO_C_WSTEP(fputc('!', LFile));
    STD_HOOKIO_C_WSTEP(putwc(L'?', LFile));
    STD_HOOKIO_C_WSTEP(fflush(LFile));
    break;
  case 4:
    STD_HOOKIO_C_WSTEP(fwide(LFile, 1));
    STD_HOOKIO_C_WSTEP(fwide(LFile, -1));
    STD_HOOKIO_C_WSTEP(fwide(LFile, 0));
    STD_HOOKIO_C_WSTEP(fputwc(L'\u00e9', LFile));
    STD_HOOKIO_C_WSTEP(fputs("n", LFile));
    break;
  case 5:
    STD_HOOKIO_C_WSTEP(fwide(LFile, -5));
    STD_HOOKIO_C_WSTEP(fputwc(L'A', LFile));
    STD_HOOKIO_C_WSTEP(fputws(L"B", LFile));
    STD_HOOKIO_C_WSTEP(putwc(L'C', LFile));
    STD_HOOKIO_C_WSTEP(fputs("d", LFile));
    break;
  case 6:
    STD_HOOKIO_C_WSTEP(setvbuf(LFile, NULL, _IONBF, 0));
    STD_HOOKIO_C_WSTEP(fputws(L"ab\u00e9", LFile));
    STD_HOOKIO_C_WSTEP(fputwc(L'\n', LFile));
    break;
  case 7:
    STD_HOOKIO_C_WSTEP(setvbuf(LFile, NULL, _IOLBF, 64));
    STD_HOOKIO_C_WSTEP(fputws(L"ab\ncd", LFile));
    STD_HOOKIO_C_WSTEP(fputwc(L'\n', LFile));
    STD_HOOKIO_C_WSTEP(fputws(L"ef", LFile));
    break;
  case 8:
    STD_HOOKIO_C_WSTEP(fputws(L"hello\u00e9world", LFile));
    STD_HOOKIO_C_WSTEP(fseek(LFile, 0, SEEK_SET));
    STD_HOOKIO_C_WSTEP(fputws(L"HE", LFile));
    STD_HOOKIO_C_WSTEP(fseek(LFile, 0, SEEK_END));
    STD_HOOKIO_C_WSTEP(fputwc(L'!', LFile));
    STD_HOOKIO_C_WSTEP(fseek(LFile, 3, SEEK_SET));
    STD_HOOKIO_C_WSTEP(fputwc(L'L', LFile));
    break;
  case 9:
    STD_HOOKIO_C_WSTEP(fputws(L"app\u00e9", LFile));
    STD_HOOKIO_C_WSTEP(fputwc(L'x', LFile));
    STD_HOOKIO_C_WSTEP(fflush(LFile));
    break;
  case 10:
    STD_HOOKIO_C_WSTEP(fputws(L"ok\u4e2dzz", LFile));
    STD_HOOKIO_C_WSTEP(fflush(LFile));
    STD_HOOKIO_C_WSTEP(fputws(L"after", LFile));
    STD_HOOKIO_C_WSTEP(fputwc(L'\u4e2d', LFile));
    break;
  case 11:
    LLone[0] = (wchar_t)0xD800;
    LLone[1] = L'x';
    LLone[2] = L'\0';
    STD_HOOKIO_C_WSTEP(fputwc((wchar_t)0xD83D, LFile));
    STD_HOOKIO_C_WSTEP(fputwc((wchar_t)0xDE00, LFile));
    STD_HOOKIO_C_WSTEP(fputws(LLone, LFile));
    STD_HOOKIO_C_WSTEP(fflush(LFile));
    break;
  default:
    break;
  }
  errno = 0;
  AResults[74] = fclose(LFile);
  setlocale(LC_ALL, LSaved);
  std_hookio_c_wreadback(APath, AResults);
}

#if defined(__linux__)

/* The plain symbols: glibc's header binds a C call of fscanf / vfscanf to
   __isoc99_fscanf / __isoc99_vfscanf, so these names reach the other ones,
   as code built against an older header does */
extern int std_hookio_c_plain_fscanf(FILE *AFile, const char *AFormat, ...)
  __asm__("fscanf");
extern int std_hookio_c_plain_vfscanf(FILE *AFile, const char *AFormat, va_list AArgs)
  __asm__("vfscanf");

/* vfscanf by its plain symbol, through a va_list */
static int std_hookio_c_plain_vscan(FILE *AFile, const char *AFormat, ...)
{
  va_list LArgs;
  int LResult;

  va_start(LArgs, AFormat);
  LResult = std_hookio_c_plain_vfscanf(AFile, AFormat, LArgs);
  va_end(LArgs);
  return LResult;
}

#endif

/* vfscanf by the header's name, through a va_list */
static int std_hookio_c_vscan(FILE *AFile, const char *AFormat, ...)
{
  va_list LArgs;
  int LResult;

  va_start(LArgs, AFormat);
  LResult = vfscanf(AFile, AFormat, LArgs);
  va_end(LArgs);
  return LResult;
}

/* One "%d" scan by the name AVariant picks: 0 the target's other fscanf
   (Linux the plain symbol, Windows mingw's own __mingw_fscanf), 1 vfscanf by
   the header's name, 2 the target's third name (Linux the plain vfscanf
   symbol, Windows fscanf_s, the secure form) */
static int std_hookio_c_scan_by(FILE *AFile, const int32_t AVariant, int *ANumber)
{
  if (AVariant == 0)
  {
#if defined(_WIN32)
    return __mingw_fscanf(AFile, "%d", ANumber);
#else
    return std_hookio_c_plain_fscanf(AFile, "%d", ANumber);
#endif
  }
  if (AVariant == 1)
    return std_hookio_c_vscan(AFile, "%d", ANumber);
#if defined(_WIN32)
  return fscanf_s(AFile, "%d", ANumber);
#else
  return std_hookio_c_plain_vscan(AFile, "%d", ANumber);
#endif
}

/* Scans APath ("12 34 56;x") with fscanf. AResults (13 slots): 0 the count
   of "%d %d", 1 and 2 its numbers, 3 ftell after it, 4 feof after it (0: the
   scan stopped before the end), 5 the count of "%d" by the name AVariant
   picks (std_hookio_c_scan_by), 6 its number, 7 ftell after it, 8 fgetc (the
   byte the scan stopped at), 9 the count of "%3s" over the rest, 10 its first
   byte, 11 feof after it (1: the scan read past the last byte), 12 ftell
   after it. */
void std_hookio_c_scan(const char *APath, const int32_t AVariant, int64_t *AResults)
{
  FILE *LFile;
  int LFirst;
  int LSecond;
  int LThird;
  char LWord[4];
  int LI;

  std_hookio_c_unreached(AResults, 13);
  LFile = fopen(APath, "rb");
  if (LFile == NULL)
    return;
  LFirst = 0;
  LSecond = 0;
  LThird = 0;
  for (LI = 0; LI < 4; LI++)
    LWord[LI] = 0;
  AResults[0] = fscanf(LFile, "%d %d", &LFirst, &LSecond);
  AResults[1] = LFirst;
  AResults[2] = LSecond;
  AResults[3] = ftell(LFile);
  AResults[4] = (feof(LFile) != 0) ? 1 : 0;
  AResults[5] = std_hookio_c_scan_by(LFile, AVariant, &LThird);
  AResults[6] = LThird;
  AResults[7] = ftell(LFile);
  AResults[8] = fgetc(LFile);
  AResults[9] = fscanf(LFile, "%3s", LWord);
  AResults[10] = (unsigned char)LWord[0];
  AResults[11] = (feof(LFile) != 0) ? 1 : 0;
  AResults[12] = ftell(LFile);
  fclose(LFile);
}

/* Scans APath (more spaces than one stand-in window holds, then "77!") with
   one "%d". AResults (5 slots): 0 the count, 1 the number, 2 ftell after it,
   3 feof after it, 4 fgetc (the byte the scan stopped at). */
void std_hookio_c_scanlong(const char *APath, int64_t *AResults)
{
  FILE *LFile;
  int LNumber;

  std_hookio_c_unreached(AResults, 5);
  LFile = fopen(APath, "rb");
  if (LFile == NULL)
    return;
  LNumber = 0;
  AResults[0] = fscanf(LFile, "%d", &LNumber);
  AResults[1] = LNumber;
  AResults[2] = ftell(LFile);
  AResults[3] = (feof(LFile) != 0) ? 1 : 0;
  AResults[4] = fgetc(LFile);
  fclose(LFile);
}

#if defined(__linux__)
/* glibc's fortified names: what C built with -O2 -D_FORTIFY_SOURCE calls in
   place of fprintf / vfprintf / fgets / fread and their _unlocked forms,
   called here by name with explicit buffer sizes (the build has no fortify
   flags of its own, and glibc fortifies only an optimized build). glibc
   declares them only under _FORTIFY_SOURCE. */
extern int __fprintf_chk(FILE *AFile, int AFlag, const char *AFormat, ...);
extern int __vfprintf_chk(FILE *AFile, int AFlag, const char *AFormat, va_list AArgs);
extern char *__fgets_chk(char *AText, size_t ASize, int ACount, FILE *AFile);
extern char *__fgets_unlocked_chk(char *AText, size_t ASize, int ACount, FILE *AFile);
extern size_t __fread_chk(void *ABuffer, size_t ABufferSize, size_t ASize, size_t ACount,
  FILE *AFile);
extern size_t __fread_unlocked_chk(void *ABuffer, size_t ABufferSize, size_t ASize,
  size_t ACount, FILE *AFile);

/* __vfprintf_chk through a va_list, as a fortified vfprintf call is */
static int std_hookio_c_vprint_chk(FILE *AFile, const char *AFormat, ...)
{
  va_list LArgs;
  int LResult;

  va_start(LArgs, AFormat);
  LResult = __vfprintf_chk(AFile, 1, AFormat, LArgs);
  va_end(LArgs);
  return LResult;
}

/* Reads APath ("abc\nde\nfghijklmnop", 18 bytes) with the fortified read
   names. AResults (14 slots):
     0 / 1 __fgets_chk(16, 16): 1 = the text, its length ("abc\n")
     2 / 3 __fgets_unlocked_chk(size 16, n 64): n past the buffer, a short
           line ("de\n"): no check failure, 1 = the text, its length
     4 / 5 __fread_chk(16, 1 x 5): the count, the first byte ('f')
     6     __fread_unlocked_chk(16, 2 x 4): 3 (6 bytes left, whole pairs)
     7     feof after it
     8     __fgets_chk at the end: 1 = nil
     9     ftell there
     10 / 11 rewind, __fgets_chk(n 0): 1 = nil, ftell (nothing read)
     12 / 13 __fgets_chk(n 1): 1 = nil (glibc's _chk reads min(n - 1, size)
           bytes: none, so nil, where a plain fgets gives ""), ftell */
void std_hookio_c_chkread(const char *APath, int64_t *AResults)
{
  FILE *LFile;
  char LText[16];
  char *LGot;

  std_hookio_c_unreached(AResults, 14);
  LFile = fopen(APath, "rb");
  if (LFile == NULL)
    return;
  LGot = __fgets_chk(LText, sizeof(LText), (int)sizeof(LText), LFile);
  AResults[0] = (LGot == LText) ? 1 : 0;
  AResults[1] = (LGot == LText) ? (int64_t)strlen(LText) : -1;
  LGot = __fgets_unlocked_chk(LText, sizeof(LText), 64, LFile);
  AResults[2] = (LGot == LText) ? 1 : 0;
  AResults[3] = (LGot == LText) ? (int64_t)strlen(LText) : -1;
  memset(LText, 0, sizeof(LText));
  AResults[4] = (int64_t)__fread_chk(LText, sizeof(LText), 1, 5, LFile);
  AResults[5] = (unsigned char)LText[0];
  AResults[6] = (int64_t)__fread_unlocked_chk(LText, sizeof(LText), 2, 4, LFile);
  AResults[7] = (feof(LFile) != 0) ? 1 : 0;
  AResults[8] = (__fgets_chk(LText, sizeof(LText), (int)sizeof(LText), LFile) == NULL) ? 1 : 0;
  AResults[9] = ftell(LFile);
  rewind(LFile);
  AResults[10] = (__fgets_chk(LText, sizeof(LText), 0, LFile) == NULL) ? 1 : 0;
  AResults[11] = ftell(LFile);
  AResults[12] = (__fgets_chk(LText, sizeof(LText), 1, LFile) == NULL) ? 1 : 0;
  AResults[13] = ftell(LFile);
  fclose(LFile);
}

/* Writes "p7|qz|" to APath (opened "ab") with the fortified printf names,
   flag 1 (what -D_FORTIFY_SOURCE=2 passes). AResults (3 slots): 0
   __fprintf_chk's count, 1 __vfprintf_chk's, 2 fclose. */
void std_hookio_c_chkprint(const char *APath, int64_t *AResults)
{
  FILE *LFile;

  std_hookio_c_unreached(AResults, 3);
  LFile = fopen(APath, "ab");
  if (LFile == NULL)
    return;
  AResults[0] = __fprintf_chk(LFile, 1, "p%d|", 7);
  AResults[1] = std_hookio_c_vprint_chk(LFile, "q%s|", "z");
  AResults[2] = fclose(LFile);
}
#endif

/* Text-mode samples: '\r', '\n' and Ctrl-Z (0x1A) where ucrt's text mode
   treats them apart (a Ctrl-Z escape is closed before a following letter) */
struct std_hookio_c_sample
{
  const char *Bytes;
  long Length;
};

#define STD_HOOKIO_C_SAMPLE(AText) { AText, (long)(sizeof(AText) - 1) }

static const struct std_hookio_c_sample CStdHookioCTextSamples[] = {
  STD_HOOKIO_C_SAMPLE("12\r\n34\rx\r\r\ny" "\x1A" "z\r\n"),
  STD_HOOKIO_C_SAMPLE("5\r\n"),
  STD_HOOKIO_C_SAMPLE("ab\r"),
  STD_HOOKIO_C_SAMPLE("\r"),
  STD_HOOKIO_C_SAMPLE("\r\n\r\n"),
  STD_HOOKIO_C_SAMPLE("7 8\r\n" "\x1A"),
  STD_HOOKIO_C_SAMPLE("\x1A" "abc"),
  STD_HOOKIO_C_SAMPLE("a\r" "\x1A" "b"),
  STD_HOOKIO_C_SAMPLE("\r\r\n\n\r"),
  STD_HOOKIO_C_SAMPLE("x\r\nyy\r\nzzz\r\n"),
  STD_HOOKIO_C_SAMPLE("xy" "\x1A")
};

/* The sample count, for the program's loop */
int std_hookio_c_textcount(void)
{
  return (int)(sizeof(CStdHookioCTextSamples) / sizeof(CStdHookioCTextSamples[0]));
}

/* Sample AIndex's bytes into ABuffer (ACap bytes); its length, or -1 */
long std_hookio_c_textsample(int AIndex, unsigned char *ABuffer, long ACap)
{
  if ((AIndex < 0) || (AIndex >= std_hookio_c_textcount()))
    return -1;
  if (CStdHookioCTextSamples[AIndex].Length > ACap)
    return -1;
  memcpy(ABuffer, CStdHookioCTextSamples[AIndex].Bytes,
         (size_t)CStdHookioCTextSamples[AIndex].Length);
  return CStdHookioCTextSamples[AIndex].Length;
}

/* ACount bytes into a new real file APath (binary); 0, or -1 */
int std_hookio_c_writeraw(const char *APath, const unsigned char *ABytes, long ACount)
{
  FILE *LFile;
  size_t LWritten = 0;

  LFile = fopen(APath, "wb");
  if (LFile == NULL)
    return -1;
  if (ACount > 0)
    LWritten = fwrite(ABytes, 1, (size_t)ACount, LFile);
  if (fclose(LFile) != 0)
    return -1;
  return (LWritten == (size_t)ACount) ? 0 : -1;
}

/* Reads APath opened with AMode by every read form, from the start each
   time. AResults (122 slots): 0-2 one fread of all (count, feof, ftell),
   3-34 the bytes (-1 past the count); 35 ftell after rewind, 36-99 fgetc
   byte by byte (the byte, then ftell, until EOF), 100 feof; 101-104
   fread of 3-byte elements (fseek, count, ftell, feof); 105-108 fgets with
   4 bytes (calls, characters, a place-weighted sum of them, ftell); 109-115
   at the end: ungetc, two fgetc, feof, fseek(0, SEEK_CUR), fgetc, ftell;
   116-120 fscanf "%d %d" (count, both values, ftell, feof); 121 fclose. */
void std_hookio_c_textread(const char *APath, const char *AMode, int64_t *AResults)
{
  FILE *LFile;
  unsigned char LData[64];
  char LLine[4];
  size_t LGot;
  int LI;
  int LChar;
  int64_t LCalls;
  int64_t LChars;
  int64_t LSum;
  int LFirst;
  int LSecond;

  std_hookio_c_unreached(AResults, 122);
  LFile = fopen(APath, AMode);
  if (LFile == NULL)
    return;
  LGot = fread(LData, 1, sizeof(LData), LFile);
  AResults[0] = (int64_t)LGot;
  AResults[1] = (feof(LFile) != 0) ? 1 : 0;
  AResults[2] = ftell(LFile);
  for (LI = 0; LI < 32; ++LI)
    AResults[3 + LI] = (LI < (int)LGot) ? (int64_t)LData[LI] : -1;

  rewind(LFile);
  AResults[35] = ftell(LFile);
  for (LI = 0; LI < 32; ++LI)
  {
    LChar = fgetc(LFile);
    AResults[36 + (2 * LI)] = LChar;
    AResults[37 + (2 * LI)] = ftell(LFile);
    if (LChar == EOF)
      break;
  }
  AResults[100] = (feof(LFile) != 0) ? 1 : 0;

  AResults[101] = fseek(LFile, 0, SEEK_SET);
  AResults[102] = (int64_t)fread(LData, 3, 10, LFile);
  AResults[103] = ftell(LFile);
  AResults[104] = (feof(LFile) != 0) ? 1 : 0;

  fseek(LFile, 0, SEEK_SET);
  LCalls = 0;
  LChars = 0;
  LSum = 0;
  while ((LCalls < 40) && (fgets(LLine, (int)sizeof(LLine), LFile) != NULL))
  {
    for (LI = 0; LLine[LI] != '\0'; ++LI)
    {
      ++LChars;
      LSum += LChars * (int64_t)(unsigned char)LLine[LI];
    }
    ++LCalls;
  }
  AResults[105] = LCalls;
  AResults[106] = LChars;
  AResults[107] = LSum;
  AResults[108] = ftell(LFile);

  AResults[109] = ungetc('Q', LFile);
  AResults[110] = fgetc(LFile);
  AResults[111] = fgetc(LFile);
  AResults[112] = (feof(LFile) != 0) ? 1 : 0;
  AResults[113] = fseek(LFile, 0, SEEK_CUR);
  AResults[114] = fgetc(LFile);
  AResults[115] = ftell(LFile);

  fseek(LFile, 0, SEEK_SET);
  LFirst = -1;
  LSecond = -1;
  AResults[116] = fscanf(LFile, "%d %d", &LFirst, &LSecond);
  AResults[117] = LFirst;
  AResults[118] = LSecond;
  AResults[119] = ftell(LFile);
  AResults[120] = (feof(LFile) != 0) ? 1 : 0;
  AResults[121] = fclose(LFile);
}

/* Writes "a\nb\r\n", '\n', "c\n" and "9\n" to APath opened with AMode
   (fwrite, fputc, fputs, fprintf). AResults (7 slots): the four results,
   ftell, fflush, fclose. */
void std_hookio_c_textwrite(const char *APath, const char *AMode, int64_t *AResults)
{
  FILE *LFile;

  std_hookio_c_unreached(AResults, 7);
  LFile = fopen(APath, AMode);
  if (LFile == NULL)
    return;
  AResults[0] = (int64_t)fwrite("a\nb\r\n", 1, 5, LFile);
  AResults[1] = fputc('\n', LFile);
  AResults[2] = fputs("c\n", LFile);
  AResults[3] = fprintf(LFile, "%d\n", 9);
  AResults[4] = ftell(LFile);
  AResults[5] = fflush(LFile);
  AResults[6] = fclose(LFile);
}

/* Opens APath "r+t", goes to its end and writes 'k' there. AResults (4
   slots): fseek, ftell, fputc, fclose. */
void std_hookio_c_textupdate(const char *APath, int64_t *AResults)
{
  FILE *LFile;

  std_hookio_c_unreached(AResults, 4);
  LFile = fopen(APath, "r+t");
  if (LFile == NULL)
    return;
  AResults[0] = fseek(LFile, 0, SEEK_END);
  AResults[1] = ftell(LFile);
  AResults[2] = fputc('k', LFile);
  AResults[3] = fclose(LFile);
}

/* Long text samples, built here: what ucrt's buffer decides (its 4096-byte
   fills, the 512-byte fill after an fseek, a '\r' at the end of a fill, a
   fill that starts with a lone '\n', a Ctrl-Z after a fill boundary, a
   number that ends a fill). Sample AIndex into ABuffer (ACap bytes); its
   length, or -1. */
#define STD_HOOKIO_C_LONG_COUNT 9

static long std_hookio_c_fill(unsigned char *ABuffer, long AAt, char AByte, long ACount)
{
  long LI;

  for (LI = 0; LI < ACount; ++LI)
    ABuffer[AAt + LI] = (unsigned char)AByte;
  return AAt + ACount;
}

static long std_hookio_c_text(unsigned char *ABuffer, long AAt, const char *AText)
{
  while (*AText != '\0')
  {
    ABuffer[AAt] = (unsigned char)*AText;
    ++AAt;
    ++AText;
  }
  return AAt;
}

int std_hookio_c_longcount(void)
{
  return STD_HOOKIO_C_LONG_COUNT;
}

long std_hookio_c_longsample(int AIndex, unsigned char *ABuffer, long ACap)
{
  long LAt = 0;
  long LI;

  /* Every sample is under 5200 bytes */
  if ((ACap < 5200) || (AIndex < 0) || (AIndex >= STD_HOOKIO_C_LONG_COUNT))
    return -1;
  if (AIndex == 0)
  {
    /* 600 bytes of "ab\r\n": past the small fill, one big fill */
    for (LI = 0; LI < 600; ++LI)
      ABuffer[LI] = (unsigned char)("ab\r\n"[LI % 4]);
    LAt = 600;
  }
  else if (AIndex == 1)
  {
    /* 5000 bytes of "line\r\n": two big fills */
    for (LI = 0; LI < 5000; ++LI)
      ABuffer[LI] = (unsigned char)("line\r\n"[LI % 6]);
    LAt = 5000;
  }
  else if (AIndex == 2)
  {
    /* A '\r' last in the first big fill, its '\n' first in the next */
    LAt = std_hookio_c_fill(ABuffer, 0, 'a', 4095);
    LAt = std_hookio_c_text(ABuffer, LAt, "\r\n");
    LAt = std_hookio_c_fill(ABuffer, LAt, 'b', 100);
  }
  else if (AIndex == 3)
  {
    /* A '\r' last in the small fill after an fseek */
    LAt = std_hookio_c_fill(ABuffer, 0, 'a', 511);
    LAt = std_hookio_c_text(ABuffer, LAt, "\r\n");
    LAt = std_hookio_c_fill(ABuffer, LAt, 'c', 3700);
  }
  else if (AIndex == 4)
  {
    /* A '\r' last in the first big fill, no '\n' after it */
    LAt = std_hookio_c_fill(ABuffer, 0, 'a', 4095);
    LAt = std_hookio_c_text(ABuffer, LAt, "\rx");
    LAt = std_hookio_c_fill(ABuffer, LAt, 'y', 50);
  }
  else if (AIndex == 5)
  {
    /* The second big fill starts with a '\n' no '\r' came before */
    LAt = std_hookio_c_fill(ABuffer, 0, 'a', 4096);
    LAt = std_hookio_c_text(ABuffer, LAt, "\n");
    LAt = std_hookio_c_fill(ABuffer, LAt, 'z', 50);
  }
  else if (AIndex == 6)
  {
    /* "x\r\n" past one big fill, then a Ctrl-Z and more text */
    for (LI = 0; LI < 4200; ++LI)
      ABuffer[LI] = (unsigned char)("x\r\n"[LI % 3]);
    LAt = std_hookio_c_text(ABuffer, 4200, "\x1A" "tail\r\n");
  }
  else if (AIndex == 7)
  {
    /* A Ctrl-Z first in the second big fill */
    LAt = std_hookio_c_fill(ABuffer, 0, 'q', 4096);
    LAt = std_hookio_c_text(ABuffer, LAt, "\x1A" "after");
  }
  else
  {
    /* A number that ends the first big fill: a scan's look-ahead after it
       refills */
    LAt = std_hookio_c_fill(ABuffer, 0, ' ', 4091);
    LAt = std_hookio_c_text(ABuffer, LAt, "12345 67\r\n");
  }
  return LAt;
}

/* The character counts after which std_hookio_c_textlong records ftell */
static const long CStdHookioCLongMarks[] = {
  0, 1, 2, 255, 509, 510, 511, 512, 513, 514, 599, 600, 1023, 2047, 4093,
  4094, 4095, 4096, 4097, 4098, 4099, 4100, 4101, 4150, 4199, 4200, 4201,
  4202, 4500, 4999, 5000
};

#define STD_HOOKIO_C_LONG_MARKS 31

/* fgetc to EOF from where AFile stands: AResults[0] the characters read,
   [1] a place-weighted sum of them, [2] a weighted sum of every ftell,
   [3 .. 3+marks-1] ftell after character N of each mark (unreached: -2),
   [3+marks] ftell after the EOF */
static void std_hookio_c_longpass(FILE *AFile, int64_t *AResults)
{
  uint64_t LBytes = 0;
  uint64_t LPlaces = 0;
  long LCount = 0;
  long LMark;
  int LChar;
  int64_t LPlace;

  for (LMark = 0; LMark < STD_HOOKIO_C_LONG_MARKS; ++LMark)
    AResults[3 + LMark] = -2;
  for (;;)
  {
    LChar = fgetc(AFile);
    if (LChar == EOF)
      break;
    LPlace = ftell(AFile);
    LBytes += (uint64_t)(LCount + 1) * (uint64_t)(unsigned char)LChar;
    LPlaces += (uint64_t)(LCount + 1) * (uint64_t)LPlace;
    for (LMark = 0; LMark < STD_HOOKIO_C_LONG_MARKS; ++LMark)
      if (CStdHookioCLongMarks[LMark] == LCount)
        AResults[3 + LMark] = LPlace;
    ++LCount;
    if (LCount > 8192)
      break;
  }
  AResults[0] = LCount;
  AResults[1] = (int64_t)(LBytes & 0x7FFFFFFFFFFFFFFFULL);
  AResults[2] = (int64_t)(LPlaces & 0x7FFFFFFFFFFFFFFFULL);
  AResults[3 + STD_HOOKIO_C_LONG_MARKS] = ftell(AFile);
}

/* Reads APath (a long sample) opened with AMode through ucrt's buffer
   paths. AResults (95 slots): 0-3 one fread of all (count, feof, ftell, a
   weighted byte sum); 4 ftell after rewind; 5-39 fgetc to EOF after the
   rewind (std_hookio_c_longpass); 40 feof; 41-44 past the EOF after that
   ftell (fgetc, ftell, fgetc, feof); 45 fseek to 0, 46-80 fgetc to EOF
   again (the small fill); 81-88 fseek to 0, fread 700 (count, ftell), fread
   4096 (count, ftell), fgetc, ftell, feof; 89-93 fseek to 0, fgets of 40
   (calls, characters, weighted sum, ftell); 94 fclose. */
void std_hookio_c_textlong(const char *APath, const char *AMode, int64_t *AResults)
{
  static unsigned char LData[8192];
  char LLine[40];
  FILE *LFile;
  size_t LGot;
  size_t LI;
  uint64_t LSum = 0;
  int64_t LCalls;
  int64_t LChars;

  std_hookio_c_unreached(AResults, 95);
  LFile = fopen(APath, AMode);
  if (LFile == NULL)
    return;
  LGot = fread(LData, 1, sizeof(LData), LFile);
  AResults[0] = (int64_t)LGot;
  AResults[1] = (feof(LFile) != 0) ? 1 : 0;
  AResults[2] = ftell(LFile);
  for (LI = 0; LI < LGot; ++LI)
    LSum += (uint64_t)(LI + 1) * (uint64_t)LData[LI];
  AResults[3] = (int64_t)(LSum & 0x7FFFFFFFFFFFFFFFULL);

  rewind(LFile);
  AResults[4] = ftell(LFile);
  std_hookio_c_longpass(LFile, AResults + 5);
  AResults[40] = (feof(LFile) != 0) ? 1 : 0;
  AResults[41] = fgetc(LFile);
  AResults[42] = ftell(LFile);
  AResults[43] = fgetc(LFile);
  AResults[44] = (feof(LFile) != 0) ? 1 : 0;

  AResults[45] = fseek(LFile, 0, SEEK_SET);
  std_hookio_c_longpass(LFile, AResults + 46);

  AResults[81] = fseek(LFile, 0, SEEK_SET);
  AResults[82] = (int64_t)fread(LData, 1, 700, LFile);
  AResults[83] = ftell(LFile);
  AResults[84] = (int64_t)fread(LData, 1, 4096, LFile);
  AResults[85] = ftell(LFile);
  AResults[86] = fgetc(LFile);
  AResults[87] = ftell(LFile);
  AResults[88] = (feof(LFile) != 0) ? 1 : 0;

  AResults[89] = fseek(LFile, 0, SEEK_SET);
  LCalls = 0;
  LChars = 0;
  LSum = 0;
  while ((LCalls < 400) && (fgets(LLine, (int)sizeof(LLine), LFile) != NULL))
  {
    for (LI = 0; LLine[LI] != '\0'; ++LI)
    {
      ++LChars;
      LSum += (uint64_t)LChars * (uint64_t)(unsigned char)LLine[LI];
    }
    ++LCalls;
  }
  AResults[90] = LCalls;
  AResults[91] = LChars;
  AResults[92] = (int64_t)(LSum & 0x7FFFFFFFFFFFFFFFULL);
  AResults[93] = ftell(LFile);
  AResults[94] = fclose(LFile);
}

/* A failed fseek after a read to the end: does feof stay? AResults (6
   slots): fread of all (count), feof, fseek(-1, SEEK_SET), feof, errno is
   EINVAL (1 / 0), fclose. */
void std_hookio_c_seekfail(const char *APath, const char *AMode, int64_t *AResults)
{
  static unsigned char LData[8192];
  FILE *LFile;

  std_hookio_c_unreached(AResults, 6);
  LFile = fopen(APath, AMode);
  if (LFile == NULL)
    return;
  AResults[0] = (int64_t)fread(LData, 1, sizeof(LData), LFile);
  AResults[1] = (feof(LFile) != 0) ? 1 : 0;
  errno = 0;
  AResults[2] = fseek(LFile, -1, SEEK_SET);
  AResults[3] = (feof(LFile) != 0) ? 1 : 0;
  AResults[4] = (errno == EINVAL) ? 1 : 0;
  AResults[5] = fclose(LFile);
}

/* ungetc and scans on APath opened with AMode, where ucrt's buffer decides
   the result. AResults (53 slots): 0-3 right after the open: ungetc('A'),
   ftell, fgetc, ftell; 4-10 fseek to 0, ungetc('B'), ungetc('C') (the
   second at the buffer's front), ftell, two fgetc, ftell; 11-22 fseek to
   0, fgetc, ungetc('\n'), ftell, fgetc, ftell, ungetc of the first byte
   (or 'x' after EOF), ftell, fread of all (count, weighted byte sum, feof,
   ftell); 23-28 at the end: ungetc('Z'), feof, ftell, two fgetc, feof;
   29-34 fseek to 0, fscanf "%d" (count, ftell, feof), fgetc, ftell; 35-40
   fseek to 0, fgetc, fscanf "%3s" (count, ftell), fgetc, ftell; 41-46
   rewind (a big fill), fscanf "%d %d" (count, both values, ftell, feof);
   47-51 fseek to 0 (a small fill), fscanf "%d" (count, ftell), fgetc,
   ftell; 52 fclose. */
void std_hookio_c_textunget(const char *APath, const char *AMode, int64_t *AResults)
{
  static unsigned char LData[8192];
  FILE *LFile;
  char LWord[4];
  size_t LGot;
  size_t LI;
  uint64_t LSum = 0;
  int LFirst;
  int LNumber;
  int LSecond;

  std_hookio_c_unreached(AResults, 53);
  LFile = fopen(APath, AMode);
  if (LFile == NULL)
    return;
  AResults[0] = ungetc('A', LFile);
  AResults[1] = ftell(LFile);
  AResults[2] = fgetc(LFile);
  AResults[3] = ftell(LFile);

  AResults[4] = fseek(LFile, 0, SEEK_SET);
  AResults[5] = ungetc('B', LFile);
  AResults[6] = ungetc('C', LFile);
  AResults[7] = ftell(LFile);
  AResults[8] = fgetc(LFile);
  AResults[9] = fgetc(LFile);
  AResults[10] = ftell(LFile);

  AResults[11] = fseek(LFile, 0, SEEK_SET);
  LFirst = fgetc(LFile);
  AResults[12] = LFirst;
  AResults[13] = ungetc('\n', LFile);
  AResults[14] = ftell(LFile);
  AResults[15] = fgetc(LFile);
  AResults[16] = ftell(LFile);
  AResults[17] = ungetc((LFirst == EOF) ? 'x' : LFirst, LFile);
  AResults[18] = ftell(LFile);
  LGot = fread(LData, 1, sizeof(LData), LFile);
  AResults[19] = (int64_t)LGot;
  for (LI = 0; LI < LGot; ++LI)
    LSum += (uint64_t)(LI + 1) * (uint64_t)LData[LI];
  AResults[20] = (int64_t)(LSum & 0x7FFFFFFFFFFFFFFFULL);
  AResults[21] = (feof(LFile) != 0) ? 1 : 0;
  AResults[22] = ftell(LFile);

  AResults[23] = ungetc('Z', LFile);
  AResults[24] = (feof(LFile) != 0) ? 1 : 0;
  AResults[25] = ftell(LFile);
  AResults[26] = fgetc(LFile);
  AResults[27] = fgetc(LFile);
  AResults[28] = (feof(LFile) != 0) ? 1 : 0;

  AResults[29] = fseek(LFile, 0, SEEK_SET);
  LNumber = -1;
  AResults[30] = fscanf(LFile, "%d", &LNumber);
  AResults[31] = ftell(LFile);
  AResults[32] = (feof(LFile) != 0) ? 1 : 0;
  AResults[33] = fgetc(LFile);
  AResults[34] = ftell(LFile);

  AResults[35] = fseek(LFile, 0, SEEK_SET);
  AResults[36] = fgetc(LFile);
  AResults[37] = fscanf(LFile, "%3s", LWord);
  AResults[38] = ftell(LFile);
  AResults[39] = fgetc(LFile);
  AResults[40] = ftell(LFile);

  rewind(LFile);
  AResults[41] = 0;
  LNumber = -1;
  LSecond = -1;
  AResults[42] = fscanf(LFile, "%d %d", &LNumber, &LSecond);
  AResults[43] = LNumber;
  AResults[44] = LSecond;
  AResults[45] = ftell(LFile);
  AResults[46] = (feof(LFile) != 0) ? 1 : 0;

  AResults[47] = fseek(LFile, 0, SEEK_SET);
  LNumber = -1;
  AResults[48] = fscanf(LFile, "%d", &LNumber);
  AResults[49] = ftell(LFile);
  AResults[50] = fgetc(LFile);
  AResults[51] = ftell(LFile);
  AResults[52] = fclose(LFile);
}

/* The setvbuf sample: 10000 bytes, 60-byte lines ending "\r\n", letters
   a..z otherwise. Returns its length. */
long std_hookio_c_svsample(unsigned char *ABuffer, long ACap)
{
  long LI;

  if (ACap < 10000)
    return -1;
  for (LI = 0; LI < 10000; ++LI)
  {
    if ((LI % 60) == 58)
      ABuffer[LI] = '\r';
    else if ((LI % 60) == 59)
      ABuffer[LI] = '\n';
    else
      ABuffer[LI] = (unsigned char)('a' + (LI % 26));
  }
  return 10000;
}

#define STD_HOOKIO_C_SV_VARIANTS 25
#define STD_HOOKIO_C_SV_ARRAY 8192

int std_hookio_c_svcount(void)
{
  return STD_HOOKIO_C_SV_VARIANTS;
}

/* A weighted sum of every byte of the caller's setvbuf array: what the
   target CRT filled it with (fill sizes, places) */
static int64_t std_hookio_c_svarray(const unsigned char *AArray)
{
  uint64_t LSum = 0;
  long LI;

  for (LI = 0; LI < STD_HOOKIO_C_SV_ARRAY; ++LI)
    LSum += (uint64_t)(LI + 1) * (uint64_t)AArray[LI];
  return (int64_t)(LSum & 0x7FFFFFFFFFFFFFFFULL);
}

/* fread of ACount bytes: AResults[0] the count, [1] a weighted sum */
static void std_hookio_c_svread(FILE *AFile, size_t ACount, int64_t *AResults)
{
  static unsigned char LData[4096];
  uint64_t LSum = 0;
  size_t LGot;
  size_t LI;

  LGot = fread(LData, 1, ACount, AFile);
  for (LI = 0; LI < LGot; ++LI)
    LSum += (uint64_t)(LI + 1) * (uint64_t)LData[LI];
  AResults[0] = (int64_t)LGot;
  AResults[1] = (int64_t)(LSum & 0x7FFFFFFFFFFFFFFFULL);
}

/* The setvbuf call of AVariant on AFile; AArray is the caller's array.
   Variants: 0 _IONBF; 1-4 _IOFBF without an array at 2, 3, 600, 5000; 5
   _IOLBF without an array at 100; 6-12 _IOFBF with the array at 2, 3, 100,
   600, 999, 4096, 5000; 13 the array at 0; 14 mode 99; 15-16 _IOFBF
   without an array at 0 and 1; 17 setbuf without an array; 18 setbuf with
   it (8192 bytes hold either BUFSIZ); 19-21 after ten fgetc, _IOFBF at 100
   without an array, _IONBF, the array at 64; 22 after two fgetc and an
   ungetc of the second byte, the array at 64; 23 the same with an ungetc
   of 'Z' (another byte); 24 _IONBF then _IOFBF without an array at 0.
   Returns setvbuf's result (setbuf: 0); *APre gets a weighted sum of the
   bytes read before it (or -1). */
static int std_hookio_c_svset(FILE *AFile, int AVariant, char *AArray, int64_t *APre)
{
  static const size_t CNoArray[] = {2, 3, 600, 5000};
  static const size_t CArray[] = {2, 3, 100, 600, 999, 4096, 5000};
  uint64_t LSum = 0;
  int LI;
  int LChar;

  *APre = -1;
  if (AVariant == 0)
    return setvbuf(AFile, NULL, _IONBF, 0);
  if ((AVariant >= 1) && (AVariant <= 4))
    return setvbuf(AFile, NULL, _IOFBF, CNoArray[AVariant - 1]);
  if (AVariant == 5)
    return setvbuf(AFile, NULL, _IOLBF, 100);
  if ((AVariant >= 6) && (AVariant <= 12))
    return setvbuf(AFile, AArray, _IOFBF, CArray[AVariant - 6]);
  if (AVariant == 13)
    return setvbuf(AFile, AArray, _IOFBF, 0);
  if (AVariant == 14)
    return setvbuf(AFile, NULL, 99, 0);
  if (AVariant == 15)
    return setvbuf(AFile, NULL, _IOFBF, 0);
  if (AVariant == 16)
    return setvbuf(AFile, NULL, _IOFBF, 1);
  if (AVariant == 17)
  {
    setbuf(AFile, NULL);
    return 0;
  }
  if (AVariant == 18)
  {
    setbuf(AFile, AArray);
    return 0;
  }
  if ((AVariant >= 19) && (AVariant <= 21))
  {
    for (LI = 0; LI < 10; ++LI)
    {
      LChar = fgetc(AFile);
      LSum += (uint64_t)(LI + 1) * (uint64_t)(LChar + 1);
    }
    *APre = (int64_t)LSum;
    if (AVariant == 19)
      return setvbuf(AFile, NULL, _IOFBF, 100);
    if (AVariant == 20)
      return setvbuf(AFile, NULL, _IONBF, 0);
    return setvbuf(AFile, AArray, _IOFBF, 64);
  }
  if ((AVariant == 22) || (AVariant == 23))
  {
    fgetc(AFile);
    LChar = fgetc(AFile);
    *APre = ungetc((AVariant == 22) ? LChar : 'Z', AFile);
    return setvbuf(AFile, AArray, _IOFBF, 64);
  }
  setvbuf(AFile, NULL, _IONBF, 0);
  return setvbuf(AFile, NULL, _IOFBF, 0);
}

/* setvbuf / setbuf of AVariant (std_hookio_c_svset) on APath opened with
   AMode, then one fixed sequence whose results show the buffer the target
   CRT made. AResults (37 slots): 0 the setvbuf result, 1 errno right after
   (cleared before), 2 the sum of what was read before it; 3-5 fgetc,
   ftell, the array sum; 6-9 fread 250 (count, sum), ftell, array; 10-13
   fread 3000 (count, sum), ftell, array; 14-18 fseek to 3000, ftell, fgetc,
   ftell, array; 19-22 fseek to 7001, fgetc, ftell, array; 23-27
   ungetc('Q'), ftell, fgetc, fgetc, ftell; 28-30 fgets of 100 (a weighted
   sum), ftell, array; 31-34 fseek to the end, fgetc, feof, ftell; 35
   rewind then fgetc; 36 fclose. */
void std_hookio_c_setvbuf(const char *APath, const char *AMode, int AVariant,
  int64_t *AResults)
{
  static unsigned char LArray[STD_HOOKIO_C_SV_ARRAY];
  char LLine[100];
  FILE *LFile;
  uint64_t LSum = 0;
  int LI;

  std_hookio_c_unreached(AResults, 37);
  memset(LArray, '#', sizeof(LArray));
  LFile = fopen(APath, AMode);
  if (LFile == NULL)
    return;
  errno = 0;
  AResults[0] = std_hookio_c_svset(LFile, AVariant, (char *)LArray, &AResults[2]);
  AResults[1] = errno;

  AResults[3] = fgetc(LFile);
  AResults[4] = ftell(LFile);
  AResults[5] = std_hookio_c_svarray(LArray);

  std_hookio_c_svread(LFile, 250, AResults + 6);
  AResults[8] = ftell(LFile);
  AResults[9] = std_hookio_c_svarray(LArray);

  std_hookio_c_svread(LFile, 3000, AResults + 10);
  AResults[12] = ftell(LFile);
  AResults[13] = std_hookio_c_svarray(LArray);

  AResults[14] = fseek(LFile, 3000, SEEK_SET);
  AResults[15] = ftell(LFile);
  AResults[16] = fgetc(LFile);
  AResults[17] = ftell(LFile);
  AResults[18] = std_hookio_c_svarray(LArray);

  AResults[19] = fseek(LFile, 7001, SEEK_SET);
  AResults[20] = fgetc(LFile);
  AResults[21] = ftell(LFile);
  AResults[22] = std_hookio_c_svarray(LArray);

  AResults[23] = ungetc('Q', LFile);
  AResults[24] = ftell(LFile);
  AResults[25] = fgetc(LFile);
  AResults[26] = fgetc(LFile);
  AResults[27] = ftell(LFile);

  if (fgets(LLine, (int)sizeof(LLine), LFile) != NULL)
    for (LI = 0; LLine[LI] != '\0'; ++LI)
      LSum += (uint64_t)(LI + 1) * (uint64_t)(unsigned char)LLine[LI];
  AResults[28] = (int64_t)LSum;
  AResults[29] = ftell(LFile);
  AResults[30] = std_hookio_c_svarray(LArray);

  AResults[31] = fseek(LFile, 0, SEEK_END);
  AResults[32] = fgetc(LFile);
  AResults[33] = (feof(LFile) != 0) ? 1 : 0;
  AResults[34] = ftell(LFile);
  rewind(LFile);
  AResults[35] = fgetc(LFile);
  AResults[36] = fclose(LFile);
}

#define STD_HOOKIO_C_FR_VARIANTS 4

int std_hookio_c_frcount(void)
{
  return STD_HOOKIO_C_FR_VARIANTS;
}

/* fflush on a stream opened for reading (APath, AMode). Before it, by
   AVariant: 0 ten fgetc; 1 two fgetc and an ungetc of the second byte; 2
   two fgetc and an ungetc of 'Z' (another byte); 3 the caller's array of
   64 bytes as the buffer (setvbuf), then ten fgetc. AResults (14 slots): 0
   the fflush result, 1 ftell, 2-4 three fgetc, 5 ftell, 6-7 fread 300
   (count, weighted sum), 8 ftell, 9 the array's weighted sum, 10 fseek by
   100 from the caller's place, 11 ftell, 12 fgetc, 13 fclose. */
void std_hookio_c_fflushread(const char *APath, const char *AMode, int AVariant,
  int64_t *AResults)
{
  static unsigned char LArray[STD_HOOKIO_C_SV_ARRAY];
  FILE *LFile;
  int LI;
  int LChar;

  std_hookio_c_unreached(AResults, 14);
  memset(LArray, '#', sizeof(LArray));
  LFile = fopen(APath, AMode);
  if (LFile == NULL)
    return;
  if (AVariant == 3)
    setvbuf(LFile, (char *)LArray, _IOFBF, 64);
  if ((AVariant == 1) || (AVariant == 2))
  {
    fgetc(LFile);
    LChar = fgetc(LFile);
    ungetc((AVariant == 1) ? LChar : 'Z', LFile);
  }
  else
    for (LI = 0; LI < 10; ++LI)
      fgetc(LFile);
  AResults[0] = fflush(LFile);
  AResults[1] = ftell(LFile);
  AResults[2] = fgetc(LFile);
  AResults[3] = fgetc(LFile);
  AResults[4] = fgetc(LFile);
  AResults[5] = ftell(LFile);
  std_hookio_c_svread(LFile, 300, AResults + 6);
  AResults[8] = ftell(LFile);
  AResults[9] = std_hookio_c_svarray(LArray);
  AResults[10] = fseek(LFile, 100, SEEK_CUR);
  AResults[11] = ftell(LFile);
  AResults[12] = fgetc(LFile);
  AResults[13] = fclose(LFile);
}

/* glibc's fill rule for a line-buffered (or unbuffered) stream: a
   line-buffered stdout holding text is flushed before the fill. APath is
   opened "rb" and set _IOLBF; stdout is set _IOLBF and given text with no
   newline. AResults (3 slots): 0 the text waits in stdout before the read
   (1 / 0), 1 it is gone after one fgetc (1 / 0), 2 that fgetc. stdout is
   set back to full buffering, and the line ends. Windows has no such rule:
   only the line is printed (slots stay unreached). */
void std_hookio_c_svstdout(const char *APath, int64_t *AResults)
{
  FILE *LFile;

  std_hookio_c_unreached(AResults, 3);
  fflush(stdout);
#if defined(__linux__)
  LFile = fopen(APath, "rb");
  if (LFile == NULL)
    return;
  setvbuf(LFile, NULL, _IOLBF, 0);
  /* stdout gets an array of its own: glibc's _IOLBF with no array keeps
     whatever buffer stdout has, and an unbuffered stdout (stdbuf -o0, or
     a terminal set so) has only its 1-byte short buffer, where the text
     never waits (measured: the check failed under stdbuf -o0 for the real
     file and the handle alike). Static: stdout keeps using it after. */
  static char LStdoutBuffer[4096];
  setvbuf(stdout, LStdoutBuffer, _IOLBF, sizeof(LStdoutBuffer));
  fputs("setvbuf line flush:", stdout);
  AResults[0] = (stdout->_IO_write_ptr > stdout->_IO_write_base) ? 1 : 0;
  AResults[2] = fgetc(LFile);
  AResults[1] = (stdout->_IO_write_ptr == stdout->_IO_write_base) ? 1 : 0;
  fclose(LFile);
  setvbuf(stdout, NULL, _IOFBF, 0);
#else
  (void)LFile;
  (void)APath;
  fputs("setvbuf line flush:", stdout);
#endif
  fputs(" checked\n", stdout);
  fflush(stdout);
}

/* The write rows: HookIO's write side against the C runtime's own FILE on a
   real file of the same bytes. The sample: STD_HOOKIO_C_W_SAMPLE bytes, a
   '\n' every 37th byte, a '\r' before every third of them, a lone '\r'
   every 101st byte, letters elsewhere, no Ctrl-Z (ucrt cuts a trailing one
   off a text file opened for update). */
#define STD_HOOKIO_C_W_SAMPLE 6000
#define STD_HOOKIO_C_W_SLOTS 48
#define STD_HOOKIO_C_W_RECORDS 45
#define STD_HOOKIO_C_W_VARIANTS 17

long std_hookio_c_wsample(unsigned char *ABuffer, long ACap)
{
  long LI;

  if (ACap < STD_HOOKIO_C_W_SAMPLE)
    return -1;
  for (LI = 0; LI < STD_HOOKIO_C_W_SAMPLE; ++LI)
  {
    if ((LI % 37) == 36)
      ABuffer[LI] = '\n';
    else if (((LI % 37) == 35) && (((LI / 37) % 3) == 0))
      ABuffer[LI] = '\r';
    else if ((LI % 101) == 100)
      ABuffer[LI] = '\r';
    else
      ABuffer[LI] = (unsigned char)('a' + ((LI * 7) % 26));
  }
  return STD_HOOKIO_C_W_SAMPLE;
}

int std_hookio_c_wcount(void)
{
  return STD_HOOKIO_C_W_VARIANTS;
}

/* The variants whose sequence C leaves undefined (a write right after a
   read, a read or an ungetc right after a write, with no fflush or fseek
   between): 7, 10 and 13. They run on update modes only; with ADefined set,
   std_hookio_c_writes makes the call C requires there. */
int std_hookio_c_wundefined(int AVariant)
{
  return ((AVariant == 7) || (AVariant == 10) || (AVariant == 13)) ? 1 : 0;
}

/* What another reader of APath sees now (fopen "rb", read to its end):
   AOut[0] its size (-1: it could not open), AOut[1] the weighted sum of its
   bytes */
static void std_hookio_c_wpeek(const char *APath, int64_t *AOut)
{
  FILE *LFile;
  uint64_t LSum = 0;
  int64_t LSize = 0;
  int LChar;

  AOut[0] = -1;
  AOut[1] = 0;
  LFile = fopen(APath, "rb");
  if (LFile == NULL)
    return;
  LChar = fgetc(LFile);
  while (LChar != EOF)
  {
    ++LSize;
    LSum += (uint64_t)LSize * (uint64_t)(unsigned char)LChar;
    LChar = fgetc(LFile);
  }
  fclose(LFile);
  AOut[0] = LSize;
  AOut[1] = (int64_t)LSum;
}

/* One record into the next slot (records past STD_HOOKIO_C_W_RECORDS are
   dropped: a variant records fewer) */
#define STD_HOOKIO_C_WREC(AValue) \
  do \
  { \
    if (LSlot < STD_HOOKIO_C_W_RECORDS) \
      AResults[LSlot] = (int64_t)(AValue); \
    ++LSlot; \
  } while (0)

/* The stream's state: ftell, ferror, feof (3 records) */
#define STD_HOOKIO_C_WSTATE() \
  do \
  { \
    STD_HOOKIO_C_WREC(ftell(LFile)); \
    STD_HOOKIO_C_WREC((ferror(LFile) != 0) ? 1 : 0); \
    STD_HOOKIO_C_WREC((feof(LFile) != 0) ? 1 : 0); \
  } while (0)

/* What another reader sees (2 records) */
#define STD_HOOKIO_C_WPEEK() \
  do \
  { \
    std_hookio_c_wpeek(APath, LPeek); \
    STD_HOOKIO_C_WREC(LPeek[0]); \
    STD_HOOKIO_C_WREC(LPeek[1]); \
  } while (0)

/* AVariant's write sequence on APath opened with AMode (an update or an
   append mode). The data written: letters with a '\n' every 50th byte.
   Records (up to 45 slots) by variant:
    0 ten fputc: buffered, then fflush
    1 fwrite of 100, 5000 (past the buffer: whole buffers straight to the
      file) and 4096 bytes
    2 sixty fputs of "ab\ncd\n", then fflush
    3 setvbuf with the caller's array (64 bytes): fwrite 100, fputc,
      fwrite 10, the array's weighted sum after each
    4 setvbuf _IONBF: fputc, fwrite 7, fputs "q\n"
    5 setvbuf _IOLBF (512): fputs "abc", "\n", "x\ny", fputc '\n'
    6 fprintf: 10 lines, then 300 more (past a buffer), then fflush
    7 ten fgetc, then fputc (undefined unless the reads met the end, which
      C allows: ADefined then adds fseek(0, SEEK_CUR) only when they did
      not), fflush, fseek to 0, fread 20
    8 fread to the end (two of 4000), then fputc (allowed at the end),
      fflush
    9 ten fgetc, then fwrite 5, fflush
   10 three fputc, then fgetc (undefined: ADefined adds fflush), again,
      fflush
   11 three fputc, fseek(0, SEEK_CUR), fgetc
   12 fwrite 50, rewind, fread 60
   13 three fputc, then ungetc 'Z' (undefined: ADefined adds fflush),
      fgetc, fflush
   14 five fputc, fwrite 3000, fseek to the end (ftell with bytes pending,
      an append stream's included)
   15 fwrite 30, then fclose with no fflush
   16 fseek to the end, fwrite 20, fseek back 10, fputc, fflush
   Then slot 45 is fclose and 46-47 what another reader sees after it. */
void std_hookio_c_writes(const char *APath, const char *AMode, int AVariant, int ADefined,
  int64_t *AResults)
{
  static unsigned char LArray[STD_HOOKIO_C_SV_ARRAY];
  static unsigned char LData[STD_HOOKIO_C_W_SAMPLE];
  FILE *LFile;
  int64_t LPeek[2];
  int LSlot = 0;
  int LI;
  int LLast = 0;

  std_hookio_c_unreached(AResults, STD_HOOKIO_C_W_SLOTS);
  memset(LArray, '#', sizeof(LArray));
  for (LI = 0; LI < STD_HOOKIO_C_W_SAMPLE; ++LI)
    LData[LI] = ((LI % 50) == 49) ? (unsigned char)'\n' : (unsigned char)('A' + (LI % 23));
  LFile = fopen(APath, AMode);
  if (LFile == NULL)
    return;
  switch (AVariant)
  {
  case 0:
    for (LI = 0; LI < 10; ++LI)
      LLast = fputc('a' + LI, LFile);
    STD_HOOKIO_C_WREC(LLast);
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WREC(fflush(LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WPEEK();
    break;
  case 1:
    STD_HOOKIO_C_WREC(fwrite(LData, 1, 100, LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WREC(fwrite(LData + 100, 1, 5000, LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WREC(fwrite(LData, 1, 4096, LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WPEEK();
    break;
  case 2:
    for (LI = 0; LI < 60; ++LI)
      LLast = fputs("ab\ncd\n", LFile);
    STD_HOOKIO_C_WREC(LLast);
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WREC(fflush(LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WPEEK();
    break;
  case 3:
    STD_HOOKIO_C_WREC(setvbuf(LFile, (char *)LArray, _IOFBF, 64));
    STD_HOOKIO_C_WREC(fwrite(LData, 1, 100, LFile));
    STD_HOOKIO_C_WREC(std_hookio_c_svarray(LArray));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WREC(fputc('Z', LFile));
    STD_HOOKIO_C_WREC(std_hookio_c_svarray(LArray));
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WREC(fwrite(LData, 1, 10, LFile));
    STD_HOOKIO_C_WREC(std_hookio_c_svarray(LArray));
    STD_HOOKIO_C_WPEEK();
    break;
  case 4:
    STD_HOOKIO_C_WREC(setvbuf(LFile, NULL, _IONBF, 0));
    STD_HOOKIO_C_WREC(fputc('x', LFile));
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WREC(fwrite(LData, 1, 7, LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WREC(fputs("q\n", LFile));
    STD_HOOKIO_C_WPEEK();
    break;
  case 5:
    STD_HOOKIO_C_WREC(setvbuf(LFile, NULL, _IOLBF, 512));
    STD_HOOKIO_C_WREC(fputs("abc", LFile));
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WREC(fputs("\n", LFile));
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WREC(fputs("x\ny", LFile));
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WREC(fputc('\n', LFile));
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WSTATE();
    break;
  case 6:
    for (LI = 0; LI < 10; ++LI)
      LLast = fprintf(LFile, "line %d of %s\n", LI, "ten");
    STD_HOOKIO_C_WREC(LLast);
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WPEEK();
    for (LI = 0; LI < 300; ++LI)
      LLast = fprintf(LFile, "row %03d: %s\n", LI, "a formatted line");
    STD_HOOKIO_C_WREC(LLast);
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WREC(fflush(LFile));
    STD_HOOKIO_C_WPEEK();
    break;
  case 7:
    for (LI = 0; LI < 10; ++LI)
      LLast = fgetc(LFile);
    STD_HOOKIO_C_WREC(LLast);
    /* C requires a positioning call here only when the reads did not meet
       the end (C11 7.21.5.3); after the end the turn is defined as is */
    if (ADefined && (!feof(LFile)))
      fseek(LFile, 0, SEEK_CUR);
    STD_HOOKIO_C_WREC(fputc('Q', LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WREC(fflush(LFile));
    STD_HOOKIO_C_WPEEK();
    STD_HOOKIO_C_WREC(fseek(LFile, 0, SEEK_SET));
    std_hookio_c_svread(LFile, 20, AResults + LSlot);
    LSlot += 2;
    break;
  case 8:
    /* std_hookio_c_svread reads into 4096 bytes: to the end in two reads */
    std_hookio_c_svread(LFile, 4000, AResults + LSlot);
    LSlot += 2;
    std_hookio_c_svread(LFile, 4000, AResults + LSlot);
    LSlot += 2;
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WREC(fputc('E', LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WREC(fflush(LFile));
    STD_HOOKIO_C_WPEEK();
    break;
  case 9:
    for (LI = 0; LI < 10; ++LI)
      LLast = fgetc(LFile);
    STD_HOOKIO_C_WREC(LLast);
    STD_HOOKIO_C_WREC(fwrite(LData, 1, 5, LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WREC(fflush(LFile));
    STD_HOOKIO_C_WPEEK();
    break;
  case 10:
    for (LI = 0; LI < 3; ++LI)
      LLast = fputc('W', LFile);
    STD_HOOKIO_C_WREC(LLast);
    if (ADefined)
      fflush(LFile);
    STD_HOOKIO_C_WREC(fgetc(LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WREC(fgetc(LFile));
    STD_HOOKIO_C_WREC(fflush(LFile));
    STD_HOOKIO_C_WPEEK();
    break;
  case 11:
    for (LI = 0; LI < 3; ++LI)
      LLast = fputc('S', LFile);
    STD_HOOKIO_C_WREC(LLast);
    STD_HOOKIO_C_WREC(fseek(LFile, 0, SEEK_CUR));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WREC(fgetc(LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WPEEK();
    break;
  case 12:
    STD_HOOKIO_C_WREC(fwrite(LData, 1, 50, LFile));
    rewind(LFile);
    STD_HOOKIO_C_WSTATE();
    std_hookio_c_svread(LFile, 60, AResults + LSlot);
    LSlot += 2;
    STD_HOOKIO_C_WPEEK();
    break;
  case 13:
    for (LI = 0; LI < 3; ++LI)
      LLast = fputc('U' + LI, LFile);
    STD_HOOKIO_C_WREC(LLast);
    if (ADefined)
      fflush(LFile);
    STD_HOOKIO_C_WREC(ungetc('Z', LFile));
    STD_HOOKIO_C_WREC(fgetc(LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WREC(fflush(LFile));
    STD_HOOKIO_C_WPEEK();
    break;
  case 14:
    for (LI = 0; LI < 5; ++LI)
      LLast = fputc('p', LFile);
    STD_HOOKIO_C_WREC(LLast);
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WREC(fwrite(LData, 1, 3000, LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WREC(fseek(LFile, 0, SEEK_END));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WPEEK();
    break;
  case 15:
    STD_HOOKIO_C_WREC(fwrite(LData, 1, 30, LFile));
    STD_HOOKIO_C_WPEEK();
    break;
  case 16:
    STD_HOOKIO_C_WREC(fseek(LFile, 0, SEEK_END));
    STD_HOOKIO_C_WREC(fwrite(LData, 1, 20, LFile));
    STD_HOOKIO_C_WREC(fseek(LFile, -10, SEEK_CUR));
    STD_HOOKIO_C_WREC(fputc('!', LFile));
    STD_HOOKIO_C_WSTATE();
    STD_HOOKIO_C_WREC(fflush(LFile));
    STD_HOOKIO_C_WPEEK();
    break;
  default:
    break;
  }
  AResults[STD_HOOKIO_C_W_RECORDS] = fclose(LFile);
  std_hookio_c_wpeek(APath, LPeek);
  AResults[STD_HOOKIO_C_W_RECORDS + 1] = LPeek[0];
  AResults[STD_HOOKIO_C_W_RECORDS + 2] = LPeek[1];
}

/* Reads on a write-only stream and fread / fwrite counts whose product
   overflows size_t, on APath opened with AMode (an append mode). AResults
   (20 slots, errno 0 before each step): 0-2 fgetc, ferror, errno; 3-5
   fread 5000 (past a buffer: the descriptor's own read), ferror, errno;
   6 ungetc 'Q'; 7-9 fgetc, ferror, errno; 10-12 fread of 2 elements of
   SIZE_MAX / 2 + 1 bytes (ucrt refuses, glibc's product wraps to 0), ferror,
   errno; 13-15 the same fwrite; 16 fclose. clearerr before each step.
   AStale (the handle only: a real ucrt FILE hands back whatever its buffer
   holds there): then 17 fputc 'w', 18-19 fgetc, ferror with that byte
   still in the buffer. */
void std_hookio_c_wronly(const char *APath, const char *AMode, int AStale, int64_t *AResults)
{
  static unsigned char LData[5000];
  const size_t LHuge = (SIZE_MAX / 2) + 1;
  FILE *LFile;

  std_hookio_c_unreached(AResults, 20);
  LFile = fopen(APath, AMode);
  if (LFile == NULL)
    return;
  errno = 0;
  AResults[0] = fgetc(LFile);
  AResults[1] = (ferror(LFile) != 0) ? 1 : 0;
  AResults[2] = errno;
  clearerr(LFile);
  errno = 0;
  AResults[3] = (int64_t)fread(LData, 1, sizeof(LData), LFile);
  AResults[4] = (ferror(LFile) != 0) ? 1 : 0;
  AResults[5] = errno;
  clearerr(LFile);
  AResults[6] = ungetc('Q', LFile);
  errno = 0;
  AResults[7] = fgetc(LFile);
  AResults[8] = (ferror(LFile) != 0) ? 1 : 0;
  AResults[9] = errno;
  clearerr(LFile);
  errno = 0;
  AResults[10] = (int64_t)fread(LData, LHuge, 2, LFile);
  AResults[11] = (ferror(LFile) != 0) ? 1 : 0;
  AResults[12] = errno;
  clearerr(LFile);
  errno = 0;
  AResults[13] = (int64_t)fwrite(LData, LHuge, 2, LFile);
  AResults[14] = (ferror(LFile) != 0) ? 1 : 0;
  AResults[15] = errno;
  clearerr(LFile);
  if (AStale)
  {
    AResults[17] = fputc('w', LFile);
    AResults[18] = fgetc(LFile);
    AResults[19] = (ferror(LFile) != 0) ? 1 : 0;
  }
  AResults[16] = fclose(LFile);
}

/* fscanf on a write-only stream (APath opened with AMode, an append mode).
   AResults (11 slots, errno 0 before each scan): 0-3 fscanf "%c" (result,
   ferror, feof, errno); 4 ungetc 'Q' (clearerr first); 5-9 fscanf "%c%c"
   (result, the first char, ferror, feof, errno: glibc's scan refuses a
   write-only stream up front, EBADF, no ferror, the ungot 'Q' left alone;
   ucrt refuses the ungetc, and its scan through _filbuf); 10 fclose. */
void std_hookio_c_wscan(const char *APath, const char *AMode, int64_t *AResults)
{
  FILE *LFile;
  char LFirst = 0;
  char LSecond = 0;

  std_hookio_c_unreached(AResults, 11);
  LFile = fopen(APath, AMode);
  if (LFile == NULL)
    return;
  errno = 0;
  AResults[0] = fscanf(LFile, "%c", &LFirst);
  AResults[1] = (ferror(LFile) != 0) ? 1 : 0;
  AResults[2] = (feof(LFile) != 0) ? 1 : 0;
  AResults[3] = errno;
  clearerr(LFile);
  AResults[4] = ungetc('Q', LFile);
  LFirst = 0;
  errno = 0;
  AResults[5] = fscanf(LFile, "%c%c", &LFirst, &LSecond);
  AResults[6] = LFirst;
  AResults[7] = (ferror(LFile) != 0) ? 1 : 0;
  AResults[8] = (feof(LFile) != 0) ? 1 : 0;
  AResults[9] = errno;
  AResults[10] = fclose(LFile);
}

/* The exit flush: a handle left open at exit with unflushed bytes. The IO
   behind it is a memory IO over GStdHookioCExitArray (std_hookio_c_exitarray);
   std_hookio_c_exitleave writes "EXITFLUSH" (9 bytes, kept in the CRT's
   buffer) and never closes. std_hookio_c_exitarm, called before any
   HookIO open, registers the check with atexit: it runs after the exit
   flush (statics made after it are destroyed first) and ends the program
   with exit code 97 when the bytes did not land. It uses no stdio: the
   program's own exit is under way. Once both checks pass it calls the
   release the program handed std_hookio_c_exitarm, which unregisters and
   closes what the exit rows left open, so the heap report counts none. */
static unsigned char GStdHookioCExitArray[16];

unsigned char *std_hookio_c_exitarray(void)
{
  return GStdHookioCExitArray;
}

static int std_hookio_c_exittempleft(void);

/* The program's release, called by the exit check after it passed */
static void (*GStdHookioCExitRelease)(void) = NULL;

/* The exit check: 97 when the flushed bytes did not land, 96 when the D
   file left open (std_hookio_c_exittemp) was not removed; then the release */
static void std_hookio_c_exitcheck(void)
{
  if (memcmp(GStdHookioCExitArray, "EXITFLUSH", 9) != 0)
    _Exit(97);
  if (std_hookio_c_exittempleft())
    _Exit(96);
  if (GStdHookioCExitRelease != NULL)
    GStdHookioCExitRelease();
}

int std_hookio_c_exitarm(void (*ARelease)(void))
{
  GStdHookioCExitRelease = ARelease;
  return atexit(std_hookio_c_exitcheck);
}

int std_hookio_c_exitleave(const char *APath)
{
  FILE *LFile;

  LFile = fopen(APath, "r+b");
  if (LFile == NULL)
    return -1;
  return (fwrite("EXITFLUSH", 1, 9, LFile) == 9) ? 0 : -1;
}

/* "w" over a file another handle has open: a second handle opens APath "rb"
   first, then "w" empties it and writes "xy"; the second handle then reads
   what is there. Slots (8): "w" opened (1 / 0), fwrite's count, fclose of
   "w", the second handle's fread count of up to 8 bytes, its first two
   bytes, its feof, its fclose. */
void std_hookio_c_wover(const char *APath, int64_t *AResults)
{
  FILE *LSecond;
  FILE *LFile;
  unsigned char LBytes[8] = {0};

  std_hookio_c_unreached(AResults, 8);
  LSecond = fopen(APath, "rb");
  if (LSecond == NULL)
    return;
  LFile = fopen(APath, "w");
  AResults[0] = (LFile != NULL) ? 1 : 0;
  if (LFile != NULL)
  {
    AResults[1] = (int64_t)fwrite("xy", 1, 2, LFile);
    AResults[2] = fclose(LFile);
  }
  AResults[3] = (int64_t)fread(LBytes, 1, 8, LSecond);
  AResults[4] = LBytes[0];
  AResults[5] = LBytes[1];
  AResults[6] = (feof(LSecond) != 0) ? 1 : 0;
  AResults[7] = fclose(LSecond);
}

/* fopen of APath in AMode while the file cannot be shortened. A real file
   on Windows is mapped by a handle of its own first (SetEndOfFile then
   fails, as tests\probe\hookabi\trunc_refuse.c measured on ucrt); a HookIO
   path has no file to map and opens as it is. Slots (5): opened (1 / 0),
   errno right after the open, ftell after fseek to the end, fgetc after
   rewind, fclose. Returns 1 when a mapping was held during the open. */
int std_hookio_c_noshorten(const char *APath, const char *AMode, int64_t *AResults)
{
  FILE *LFile;
  int LMapped = 0;
#if defined(_WIN32)
  HANDLE LHandle;
  HANDLE LMap = NULL;
  void *LView = NULL;
#endif

  std_hookio_c_unreached(AResults, 5);
#if defined(_WIN32)
  LHandle = CreateFileA(APath, GENERIC_READ | GENERIC_WRITE,
                        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                        OPEN_EXISTING, 0, NULL);
  if (LHandle != INVALID_HANDLE_VALUE)
  {
    LMap = CreateFileMappingA(LHandle, NULL, PAGE_READWRITE, 0, 0, NULL);
    if (LMap != NULL)
      LView = MapViewOfFile(LMap, FILE_MAP_WRITE, 0, 0, 0);
    LMapped = (LView != NULL) ? 1 : 0;
  }
#endif
  errno = 0;
  LFile = fopen(APath, AMode);
  AResults[1] = errno;
  AResults[0] = (LFile != NULL) ? 1 : 0;
  if (LFile != NULL)
  {
    if (fseek(LFile, 0, SEEK_END) == 0)
      AResults[2] = ftell(LFile);
    rewind(LFile);
    AResults[3] = fgetc(LFile);
    AResults[4] = fclose(LFile);
  }
#if defined(_WIN32)
  if (LView != NULL)
    UnmapViewOfFile(LView);
  if (LMap != NULL)
    CloseHandle(LMap);
  if (LHandle != INVALID_HANDLE_VALUE)
    CloseHandle(LHandle);
#endif
  return LMapped;
}

/* Windows: ucrt keeps per-descriptor state that no open resets (lowio
   osfinfo.cpp sets it only when a descriptor block is created): read.cpp
   sets utf8translations / startpos on a UTF-8 text read, and ftell of a
   later stream on the SAME descriptor number reads them (ftell.cpp, the
   UTF-8 path: a write-only stream then gives -1). A row's real file must
   start as in a fresh process, so before a ccs= open the lowest free
   descriptor (the one that open takes, _alloc_osfhnd) runs one UTF-8 read
   with no translation, which clears both. APath names a writable folder:
   the scratch file is APath + ".fh", removed after. Linux: nothing. */
static void std_hookio_c_freshfh(const char *APath)
{
#if defined(_WIN32)
  static const unsigned char CBomAb[] = { 0xEF, 0xBB, 0xBF, 'a', 'b' };
  char LScratch[1024];
  FILE *LFile;
  int LErrno = errno;

  /* A virtual path has no descriptor (HookIO's ftell keeps its own state) */
  if (strncmp(APath, "io:", 3) == 0)
    return;
  snprintf(LScratch, sizeof(LScratch), "%s.fh", APath);
  LFile = fopen(LScratch, "wb");
  if (LFile != NULL)
  {
    fwrite(CBomAb, 1, sizeof(CBomAb), LFile);
    fclose(LFile);
    LFile = fopen(LScratch, "r,ccs=UTF-8");
    if (LFile != NULL)
    {
      fgetwc(LFile);
      fgetwc(LFile);
      fclose(LFile);
    }
  }
  remove(LScratch);
  errno = LErrno;
#else
  (void)APath;
#endif
}

/* fopen of APath in AMode (the mode-string rows): what the open gives and
   what the handle then allows. Slots (9): opened (1 / 0), errno when the
   open failed (0 when it opened), fread's count of up to 8 bytes, the first
   4 of them packed low byte first, ftell after the read, fputc 'k' (after
   the fseek C requires between a read and a write), ferror after it, ftell
   after it, fclose. */
void std_hookio_c_mode(const char *APath, const char *AMode, int64_t *AResults)
{
  FILE *LFile;
  unsigned char LBytes[8] = {0};

  std_hookio_c_unreached(AResults, 9);
  std_hookio_c_freshfh(APath);
  errno = 0;
  LFile = fopen(APath, AMode);
  AResults[0] = (LFile != NULL) ? 1 : 0;
  AResults[1] = (LFile != NULL) ? 0 : errno;
  if (LFile == NULL)
    return;
  AResults[2] = (int64_t)fread(LBytes, 1, 8, LFile);
  AResults[3] = (int64_t)LBytes[0] | ((int64_t)LBytes[1] << 8) | ((int64_t)LBytes[2] << 16)
                | ((int64_t)LBytes[3] << 24);
  AResults[4] = ftell(LFile);
  fseek(LFile, 0, SEEK_CUR);
  AResults[5] = fputc('k', LFile);
  AResults[6] = (ferror(LFile) != 0) ? 1 : 0;
  AResults[7] = ftell(LFile);
  AResults[8] = fclose(LFile);
}

/* Two handles on APath, the first in AFirst, the second in ASecond (ucrt's
   D: delete on the last close, and its share rules). A probe opens APath
   "rb" after the first handle closes and again after the second does
   (closed at once when it opens). Slots (8): first opened (1 / 0), its
   errno (0 when it opened), second opened, its errno, the first probe's
   errno (0: the file was there), the second probe's, fclose of the first,
   of the second (-2 when that handle never opened). */
void std_hookio_c_temppair(const char *APath, const char *AFirst, const char *ASecond,
  int64_t *AResults)
{
  FILE *LFirst;
  FILE *LSecond;
  FILE *LProbe;

  std_hookio_c_unreached(AResults, 8);
  errno = 0;
  LFirst = fopen(APath, AFirst);
  AResults[0] = (LFirst != NULL) ? 1 : 0;
  AResults[1] = (LFirst != NULL) ? 0 : errno;
  errno = 0;
  LSecond = fopen(APath, ASecond);
  AResults[2] = (LSecond != NULL) ? 1 : 0;
  AResults[3] = (LSecond != NULL) ? 0 : errno;
  AResults[6] = (LFirst != NULL) ? fclose(LFirst) : -2;
  errno = 0;
  LProbe = fopen(APath, "rb");
  AResults[4] = (LProbe != NULL) ? 0 : errno;
  if (LProbe != NULL)
    fclose(LProbe);
  AResults[7] = (LSecond != NULL) ? fclose(LSecond) : -2;
  errno = 0;
  LProbe = fopen(APath, "rb");
  AResults[5] = (LProbe != NULL) ? 0 : errno;
  if (LProbe != NULL)
    fclose(LProbe);
}

/* Windows: sets (AOn 1) or clears (AOn 0) the read-only attribute of the
   real file APath; 0, or -1. Linux: -1 (not used there). */
int std_hookio_c_readonly(const char *APath, int AOn)
{
#if defined(_WIN32)
  return SetFileAttributesA(APath, AOn ? FILE_ATTRIBUTE_READONLY : FILE_ATTRIBUTE_NORMAL) ? 0 : -1;
#else
  (void)APath;
  (void)AOn;
  return -1;
#endif
}

/* A D handle left open at exit (Windows): std_hookio_c_exittemp opens
   APath "rD" and never closes it; the file behind it, ARealFile, must be
   gone when the exit check runs (after the exit flush), else the program
   ends with exit code 96. Like the exit flush check, no stdio at exit. */
static char GStdHookioCExitTempFile[1024];

int std_hookio_c_exittemp(const char *APath, const char *ARealFile)
{
  FILE *LFile;

  if (strlen(ARealFile) >= sizeof(GStdHookioCExitTempFile))
    return -1;
  LFile = fopen(APath, "rD");
  if (LFile == NULL)
    return -1;
  strcpy(GStdHookioCExitTempFile, ARealFile);
  return 0;
}

/* 1 when the D file is still there at exit */
static int std_hookio_c_exittempleft(void)
{
#if defined(_WIN32)
  if (GStdHookioCExitTempFile[0] == '\0')
    return 0;
  return GetFileAttributesA(GStdHookioCExitTempFile) != INVALID_FILE_ATTRIBUTES;
#else
  return 0;
#endif
}

/* 1 when the two real files hold the same bytes, or when neither exists;
   0 when they differ or only one exists. */
int std_hookio_c_samebytes(const char *AFirst, const char *ASecond)
{
  FILE *LFirst;
  FILE *LSecond;
  int LOne;
  int LTwo;
  int LSame = 1;

  LFirst = fopen(AFirst, "rb");
  LSecond = fopen(ASecond, "rb");
  if ((LFirst == NULL) || (LSecond == NULL))
  {
    LSame = (LFirst == NULL) && (LSecond == NULL);
    if (LFirst != NULL)
      fclose(LFirst);
    if (LSecond != NULL)
      fclose(LSecond);
    return LSame;
  }
  do
  {
    LOne = fgetc(LFirst);
    LTwo = fgetc(LSecond);
    if (LOne != LTwo)
      LSame = 0;
  }
  while (LSame && (LOne != EOF));
  fclose(LFirst);
  fclose(LSecond);
  return LSame;
}

/* The length of APath's folder part (up to its last '/' or '\\', without
   it); -1 when it has none. */
long std_hookio_c_dirlen(const char *APath)
{
  long LLast = -1;
  long LI;

  for (LI = 0; APath[LI] != '\0'; ++LI)
  {
    if ((APath[LI] == '/') || (APath[LI] == '\\'))
      LLast = LI;
  }
  return (LLast > 0) ? LLast : -1;
}

/* An FNV-1a hash of a wide string's characters up to its terminator, so a
   read string compares as one slot */
static int64_t std_hookio_c_whash(const wchar_t *AText)
{
  uint64_t LHash = 14695981039346656037ULL;
  long LI;

  for (LI = 0; AText[LI] != L'\0'; ++LI)
    LHash = (LHash ^ (uint64_t)(uint32_t)AText[LI]) * 1099511628211ULL;
  return (int64_t)(LHash & 0x7FFFFFFFFFFFFFFFULL);
}

/* fgetws as one step value: the read text's hash, -1 for NULL */
static int64_t std_hookio_c_wline(FILE *AFile, int ACount)
{
  wchar_t LLine[4200];
  wchar_t *LGot;

  LLine[0] = L'\0';
  LGot = fgetws(LLine, ACount, AFile);
  if (LGot == NULL)
    return -1;
  return std_hookio_c_whash(LLine);
}

/* AChars fgetwc calls as one step value: the hash of what was read, the
   count read folded in; stops at WEOF */
static int64_t std_hookio_c_wrun(FILE *AFile, int AChars)
{
  uint64_t LHash = 14695981039346656037ULL;
  wint_t LChar;
  int LI;

  for (LI = 0; LI < AChars; ++LI)
  {
    LChar = fgetwc(AFile);
    if (LChar == WEOF)
      break;
    LHash = (LHash ^ (uint64_t)(uint32_t)LChar) * 1099511628211ULL;
  }
  return (int64_t)((LHash ^ (uint64_t)LI) & 0x7FFFFFFFFFFFFFFFULL);
}

/* Wide input rows (PLAN-HOOKABI W2). The sample std_hookio_c_wrsample
   gives for AVariant is written to a real file and into a memory IO by the
   program; std_hookio_c_wideread sets ALocale, opens APath with AMode and
   reads it with the wide names, recording after each step as
   std_hookio_c_widewrite does (slots 0..71, 72 locale set, 73 opened, 74
   fclose; 75..140 the bytes read back, the file unchanged). Variants: 0
   fgetwc / getwc / the getwc symbol over ASCII, a 2-byte and a 3-byte
   character, CRLF, to the end; 1 fgetws with short and long counts; 2
   ungetwc after a read, twice in a row; 3 ungetwc on a byte-oriented
   stream, then the byte names; 4 a wide read, then the byte names; 5 more
   than a buffer holds, by fgetwc and fgetws; 6 a byte no locale maps; 7 a
   character cut off by the end; 8 fseek and ftell around ungetwc and to a
   character boundary (the fseek from the current place right after the
   ungetwc by std_hookio_c_seekcur_ungot: on Linux both glibc and the handle
   abort it; the SEEK_SET target is a character boundary in the active
   locale, since glibc loops forever on a seek toward a mid-character byte); 9 fgetws counts 1 and 2; 10 CR runs; 11 a
   Ctrl-Z inside the text. */
long std_hookio_c_wrsample(int AVariant, unsigned char *ABuffer, long ACap)
{
  static const char CMixed[] = "A\xC3\xA9\xE2\x82\xAC\r\nxy\nlast";
  static const char CBad[] = "a\xFF" "b\xC3\x28" "c";
  static const char CCut[] = "ab\xC3";
  static const char CCr[] = "a\r\r\nb\r\rc\r";
  static const char CCtrlZ[] = "ab\x1A" "cd\r\n";
  const char *LText = CMixed;
  long LLength = (long)(sizeof(CMixed) - 1);
  long LI;

  if (AVariant == 5)
  {
    /* 5000 'w', an e-acute (2 bytes), then 'v' to 6000 bytes, lines of 70 */
    if (ACap < 6000)
      return -1;
    for (LI = 0; LI < 6000; ++LI)
      ABuffer[LI] = ((LI % 70) == 69) ? '\n' : ((LI < 5000) ? 'w' : 'v');
    ABuffer[5000] = 0xC3;
    ABuffer[5001] = 0xA9;
    return 6000;
  }
  if (AVariant == 6)
  {
    LText = CBad;
    LLength = (long)(sizeof(CBad) - 1);
  }
  if (AVariant == 7)
  {
    LText = CCut;
    LLength = (long)(sizeof(CCut) - 1);
  }
  if (AVariant == 10)
  {
    LText = CCr;
    LLength = (long)(sizeof(CCr) - 1);
  }
  if (AVariant == 11)
  {
    LText = CCtrlZ;
    LLength = (long)(sizeof(CCtrlZ) - 1);
  }
  if (LLength > ACap)
    return -1;
  memcpy(ABuffer, LText, (size_t)LLength);
  return LLength;
}

/* Value of a step whose fseek killed its process with SIGABRT */
#define STD_HOOKIO_C_ABORTED 1000

/* fseek(AFile, 0, SEEK_CUR) right after an ungetwc. Windows: the call
   itself. Linux: glibc aborts it on a wide stream holding an ungot wide
   character (ioseekoff.c, measured by tests\probe\hookabi\wread8_real.c),
   so it runs in a child process (no core file) and the parent's stream is
   left as it was: STD_HOOKIO_C_ABORTED when the child died by SIGABRT,
   100 + its exit code (0: fseek succeeded, 1: it failed) otherwise, -1
   when the child could not be run. */
static int64_t std_hookio_c_seekcur_ungot(FILE *AFile)
{
#if defined(_WIN32)
  return (int64_t)fseek(AFile, 0, SEEK_CUR);
#else
  pid_t LChild;
  int LStatus;
  struct rlimit LNoCore;

  LChild = fork();
  if (LChild < 0)
    return -1;
  if (LChild == 0)
  {
    LNoCore.rlim_cur = 0;
    LNoCore.rlim_max = 0;
    setrlimit(RLIMIT_CORE, &LNoCore);
    _exit((fseek(AFile, 0, SEEK_CUR) == 0) ? 0 : 1);
  }
  if (waitpid(LChild, &LStatus, 0) != LChild)
    return -1;
  errno = 0;
  if (WIFSIGNALED(LStatus) && (WTERMSIG(LStatus) == SIGABRT))
    return STD_HOOKIO_C_ABORTED;
  if (WIFEXITED(LStatus))
    return 100 + WEXITSTATUS(LStatus);
  return -1;
#endif
}

void std_hookio_c_wideread(const char *APath, const char *AMode, const char *ALocale,
                           int AVariant, int64_t *AResults)
{
  FILE *LFile;
  int LStep = 0;
  int LI;
  char LSaved[256];
  const char *LOld;
  unsigned char LBytes[4];
  long LSeekTarget;

  /* Variant 8's SEEK_SET target (step 10) must land on a character
     boundary in the active locale: byte 2 is inside the sample's e-acute
     under a UTF-8 locale (glibc then loops forever converting toward a
     mid-character byte; a real file can never be the comparison), so a
     UTF-8 locale seeks to byte 6 (the CR, a boundary), "C" keeps byte 2. */
  LSeekTarget = (strstr(ALocale, "UTF") != NULL) ? 6 : 2;

  std_hookio_c_unreached(AResults, STD_HOOKIO_C_WSLOTS);
  for (LI = 77; LI < STD_HOOKIO_C_WSLOTS; ++LI)
    AResults[LI] = -1;
  LOld = setlocale(LC_ALL, NULL);
  snprintf(LSaved, sizeof(LSaved), "%s", (LOld != NULL) ? LOld : "C");
  AResults[72] = (setlocale(LC_ALL, ALocale) != NULL) ? 1 : 0;
  /* A text-mode fgetwc converts with mbtowc, whose conversion state is one
     static of the CRT (ucrt convert\mbtowc.cpp internal_state under UTF-8;
     glibc likewise), shared by the handle and the real file. A row ending
     inside a multibyte character leaves it partial for the next row, so
     every run starts from the initial state, as a fresh process does. */
  mbtowc(NULL, NULL, 0);
  LFile = fopen(APath, AMode);
  AResults[73] = (LFile != NULL) ? 1 : 0;
  if (LFile == NULL)
  {
    setlocale(LC_ALL, LSaved);
    return;
  }
  switch (AVariant)
  {
  case 0:
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(getwc(LFile));
    STD_HOOKIO_C_WSTEP((getwc)(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wrun(LFile, 100));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(feof(LFile));
    break;
  case 1:
    STD_HOOKIO_C_WSTEP(std_hookio_c_wline(LFile, 3));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wline(LFile, 64));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wline(LFile, 64));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wline(LFile, 64));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wline(LFile, 64));
    STD_HOOKIO_C_WSTEP(feof(LFile));
    break;
  case 2:
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(ungetwc(L'Z', LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(ungetwc(L'Q', LFile));
    STD_HOOKIO_C_WSTEP(ungetwc(L'R', LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(ungetwc(L'\u00e9', LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(ungetwc(WEOF, LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    break;
  case 3:
    STD_HOOKIO_C_WSTEP(fgetc(LFile));
    STD_HOOKIO_C_WSTEP(ungetwc(L'b', LFile));
    STD_HOOKIO_C_WSTEP(fgetc(LFile));
    STD_HOOKIO_C_WSTEP(ungetwc(L'\u00e9', LFile));
    STD_HOOKIO_C_WSTEP(fgetc(LFile));
    STD_HOOKIO_C_WSTEP(fgetc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    break;
  case 4:
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetc(LFile));
    LBytes[0] = 0;
    LBytes[1] = 0;
    STD_HOOKIO_C_WSTEP((int64_t)fread(LBytes, 1, 2, LFile) * 65536 + LBytes[0] * 256 + LBytes[1]);
    STD_HOOKIO_C_WSTEP(ungetc('U', LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    break;
  case 5:
    STD_HOOKIO_C_WSTEP(std_hookio_c_wrun(LFile, 4090));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wrun(LFile, 20));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wline(LFile, 4096));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wrun(LFile, 900));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(ungetwc(L'K', LFile));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wline(LFile, 4096));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wrun(LFile, 3000));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    break;
  case 6:
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP((clearerr(LFile), 0));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    break;
  case 7:
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(feof(LFile));
    break;
  case 8:
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(ungetwc(L'K', LFile));
    STD_HOOKIO_C_WSTEP(std_hookio_c_seekcur_ungot(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fseek(LFile, 0, SEEK_SET));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fseek(LFile, 0, SEEK_END));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fseek(LFile, LSeekTarget, SEEK_SET));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    break;
  case 9:
    STD_HOOKIO_C_WSTEP(std_hookio_c_wline(LFile, 1));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wline(LFile, 2));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wline(LFile, 2));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    break;
  case 10:
  case 11:
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(feof(LFile));
    break;
  default:
    break;
  }
  errno = 0;
  AResults[74] = fclose(LFile);
  setlocale(LC_ALL, LSaved);
  std_hookio_c_wreadback(APath, AResults);
}

/* ccs= rows (PLAN-HOOKABI W3). The samples a file holds before the open:
   0 plain "ab\r\ncd", 1 a UTF-8 BOM then "h", e-acute, CRLF, "x", 2 a
   UTF-16LE BOM then "hi" CRLF, 3 a UTF-16BE BOM then "h", 4 empty. */
long std_hookio_c_ccssample(int AIndex, unsigned char *ABuffer, long ACap)
{
  static const unsigned char CPlain[] = { 'a', 'b', '\r', '\n', 'c', 'd' };
  static const unsigned char CUtf8[] = { 0xEF, 0xBB, 0xBF, 'h', 0xC3, 0xA9, '\r', '\n', 'x' };
  static const unsigned char CUtf16[] = { 0xFF, 0xFE, 'h', 0, 'i', 0, '\r', 0, '\n', 0 };
  static const unsigned char CBig[] = { 0xFE, 0xFF, 0, 'h' };
  const unsigned char *LBytes = CPlain;
  long LLength = (long)sizeof(CPlain);

  if (AIndex == 1)
  {
    LBytes = CUtf8;
    LLength = (long)sizeof(CUtf8);
  }
  if (AIndex == 2)
  {
    LBytes = CUtf16;
    LLength = (long)sizeof(CUtf16);
  }
  if (AIndex == 3)
  {
    LBytes = CBig;
    LLength = (long)sizeof(CBig);
  }
  if (AIndex == 4)
    LLength = 0;
  if (LLength > ACap)
    return -1;
  if (LLength > 0)
    memcpy(ABuffer, LBytes, (size_t)LLength);
  return LLength;
}

int std_hookio_c_ccscount(void)
{
  return 5;
}

/* Opens APath with AMode (a ccs= mode string) and runs the wide names it
   allows, recording each step as std_hookio_c_widewrite does: a mode that
   reads takes 4 fgetwc and one fgetws; a mode that writes (after an fseek
   to the end when it also read) fputws, fputwc and fputc, then fflush.
   Slots: 0..71 the steps, 72 errno after the fopen (cleared before), 73
   opened, 74 fclose, 75..140 the bytes read back. */
void std_hookio_c_ccs(const char *APath, const char *AMode, int64_t *AResults)
{
  FILE *LFile;
  int LStep = 0;
  int LI;
  int LReads;
  int LWrites;

  std_hookio_c_unreached(AResults, STD_HOOKIO_C_WSLOTS);
  for (LI = 77; LI < STD_HOOKIO_C_WSLOTS; ++LI)
    AResults[LI] = -1;
  LReads = (AMode[0] == 'r') || (strchr(AMode, '+') != NULL);
  LWrites = (AMode[0] == 'w') || (AMode[0] == 'a') || (strchr(AMode, '+') != NULL);
  std_hookio_c_freshfh(APath);
  errno = 0;
  LFile = fopen(APath, AMode);
  AResults[72] = errno;
  AResults[73] = (LFile != NULL) ? 1 : 0;
  if (LFile == NULL)
  {
    std_hookio_c_wreadback(APath, AResults);
    return;
  }
  if (LReads)
  {
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(fgetwc(LFile));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wline(LFile, 16));
  }
  if (LWrites)
  {
    if (LReads)
      STD_HOOKIO_C_WSTEP(fseek(LFile, 0, SEEK_END));
    STD_HOOKIO_C_WSTEP(fputws(L"h\u00e9\nx", LFile));
    STD_HOOKIO_C_WSTEP(fputwc(L'\n', LFile));
    STD_HOOKIO_C_WSTEP(fputc('n', LFile));
    STD_HOOKIO_C_WSTEP(fflush(LFile));
  }
  errno = 0;
  AResults[74] = fclose(LFile);
  std_hookio_c_wreadback(APath, AResults);
}

/* Wide printf / scanf rows (PLAN-HOOKABI W4). The plain symbols: glibc's
   header binds fwscanf / vfwscanf to __isoc99_*, these names reach the
   others, as code built against an older header does. */
#if defined(__linux__)
extern int std_hookio_c_plain_fwscanf(FILE *AFile, const wchar_t *AFormat, ...)
  __asm__("fwscanf");
extern int std_hookio_c_plain_vfwscanf(FILE *AFile, const wchar_t *AFormat, va_list AArgs)
  __asm__("vfwscanf");
extern int __fwprintf_chk(FILE *AFile, int AFlag, const wchar_t *AFormat, ...);
#endif

/* vfwprintf through a va_list, as a C library's own helper does */
static int std_hookio_c_wvprint(FILE *AFile, const wchar_t *AFormat, ...)
{
  va_list LArgs;
  int LResult;

  va_start(LArgs, AFormat);
  LResult = vfwprintf(AFile, AFormat, LArgs);
  va_end(LArgs);
  return LResult;
}

/* vfwscanf through a va_list */
static int std_hookio_c_wvscan(FILE *AFile, const wchar_t *AFormat, ...)
{
  va_list LArgs;
  int LResult;

  va_start(LArgs, AFormat);
  LResult = vfwscanf(AFile, AFormat, LArgs);
  va_end(LArgs);
  return LResult;
}

#if defined(__linux__)
/* The plain vfwscanf symbol through a va_list */
static int std_hookio_c_wvscan_plain(FILE *AFile, const wchar_t *AFormat, ...)
{
  va_list LArgs;
  int LResult;

  va_start(LArgs, AFormat);
  LResult = std_hookio_c_plain_vfwscanf(AFile, AFormat, LArgs);
  va_end(LArgs);
  return LResult;
}
#endif

/* Sets ALocale, opens APath with AMode (an update mode), writes with the
   wide printf names, rewinds and reads it back with the wide scan names,
   recording each step as std_hookio_c_widewrite does (slots 72 locale set,
   73 opened, 74 fclose, 75..140 the bytes read back). */
void std_hookio_c_wformat(const char *APath, const char *AMode, const char *ALocale,
                          int64_t *AResults)
{
  FILE *LFile;
  int LStep = 0;
  int LI;
  char LSaved[256];
  const char *LOld;
  int LNumber;
  int LGot;
  wchar_t LWord[16];
  wchar_t LChar;

  std_hookio_c_unreached(AResults, STD_HOOKIO_C_WSLOTS);
  for (LI = 77; LI < STD_HOOKIO_C_WSLOTS; ++LI)
    AResults[LI] = -1;
  LOld = setlocale(LC_ALL, NULL);
  snprintf(LSaved, sizeof(LSaved), "%s", (LOld != NULL) ? LOld : "C");
  AResults[72] = (setlocale(LC_ALL, ALocale) != NULL) ? 1 : 0;
  LFile = fopen(APath, AMode);
  AResults[73] = (LFile != NULL) ? 1 : 0;
  if (LFile == NULL)
  {
    setlocale(LC_ALL, LSaved);
    return;
  }
  STD_HOOKIO_C_WSTEP(fwprintf(LFile, L"%d|%ls|%c|", 42, L"h\u00e9", 'x'));
  STD_HOOKIO_C_WSTEP(std_hookio_c_wvprint(LFile, L"%5.2f;%lc;\n", 3.14159, (wint_t)L'\u00e9'));
#if defined(__linux__)
  STD_HOOKIO_C_WSTEP(__fwprintf_chk(LFile, 1, L"<%d>%ls\n", 7, L"tail"));
#else
  STD_HOOKIO_C_WSTEP(fwprintf(LFile, L"<%d>%ls\n", 7, L"tail"));
#endif
  STD_HOOKIO_C_WSTEP(fflush(LFile));
  STD_HOOKIO_C_WSTEP((rewind(LFile), 0));
  LNumber = -1;
  LGot = fwscanf(LFile, L"%d|", &LNumber);
  STD_HOOKIO_C_WSTEP((int64_t)LGot * 1000 + LNumber);
  LWord[0] = L'\0';
  LGot = std_hookio_c_wvscan(LFile, L"%2ls", LWord);
  STD_HOOKIO_C_WSTEP((LGot == 1) ? std_hookio_c_whash(LWord) : (int64_t)(-100 - LGot));
  LChar = 0;
  LGot = fwscanf(LFile, L"%*[^;];%lc", &LChar);
  STD_HOOKIO_C_WSTEP((int64_t)LGot * 0x1000000 + (int64_t)(uint32_t)LChar);
  LNumber = -1;
#if defined(__linux__)
  LGot = std_hookio_c_plain_fwscanf(LFile, L";\n<%d>", &LNumber);
  STD_HOOKIO_C_WSTEP((int64_t)LGot * 1000 + LNumber);
  LWord[0] = L'\0';
  LGot = std_hookio_c_wvscan_plain(LFile, L"%3ls", LWord);
  STD_HOOKIO_C_WSTEP((LGot == 1) ? std_hookio_c_whash(LWord) : (int64_t)(-100 - LGot));
#else
  LGot = fwscanf(LFile, L";\n<%d>", &LNumber);
  STD_HOOKIO_C_WSTEP((int64_t)LGot * 1000 + LNumber);
  LWord[0] = L'\0';
  LGot = std_hookio_c_wvscan(LFile, L"%3ls", LWord);
  STD_HOOKIO_C_WSTEP((LGot == 1) ? std_hookio_c_whash(LWord) : (int64_t)(-100 - LGot));
#endif
  STD_HOOKIO_C_WSTEP(fgetwc(LFile));
  LNumber = -1;
  LGot = fwscanf(LFile, L"%d", &LNumber);
  STD_HOOKIO_C_WSTEP((int64_t)LGot * 1000 + LNumber);
  errno = 0;
  AResults[74] = fclose(LFile);
  setlocale(LC_ALL, LSaved);
  std_hookio_c_wreadback(APath, AResults);
}

/* The CRT-lock-free names (PLAN-HOOKABI R5): ucrt's _nolock forms, glibc's
   *_unlocked ones and its fortified wide line reads. Sets ALocale, opens
   APath with AMode (an update mode) and runs variant AVariant (0 the byte
   names, 1 the wide names), recording each step as std_hookio_c_widewrite
   does (72 locale set, 73 opened, 74 the close, 75..140 the bytes read
   back). The close is the target's own _nolock / plain fclose. */
#if defined(__linux__)
#if !defined(__USE_GNU)
/* glibc declares these only for _GNU_SOURCE, which this file does not set
   (it would change which scan names the other rows reach) */
extern char *fgets_unlocked(char *AText, int ACount, FILE *AFile);
extern int fputs_unlocked(const char *AText, FILE *AFile);
extern wint_t fgetwc_unlocked(FILE *AFile);
extern wint_t getwc_unlocked(FILE *AFile);
extern wint_t fputwc_unlocked(wchar_t AChar, FILE *AFile);
extern wint_t putwc_unlocked(wchar_t AChar, FILE *AFile);
extern wchar_t *fgetws_unlocked(wchar_t *AText, int ACount, FILE *AFile);
extern int fputws_unlocked(const wchar_t *AText, FILE *AFile);
#endif
extern wchar_t *__fgetws_chk(wchar_t *AText, size_t ASize, int ACount, FILE *AFile);
extern wchar_t *__fgetws_unlocked_chk(wchar_t *AText, size_t ASize, int ACount, FILE *AFile);

/* A wide line read by one of the fortified names as one step value */
static int64_t std_hookio_c_wlinechk(FILE *AFile, int AUnlocked)
{
  wchar_t LLine[8];
  wchar_t *LGot;

  LLine[0] = L'\0';
  if (AUnlocked)
    LGot = __fgetws_unlocked_chk(LLine, 8, 8, AFile);
  else
    LGot = __fgetws_chk(LLine, 8, 8, AFile);
  if (LGot == NULL)
    return -1;
  return std_hookio_c_whash(LLine);
}

/* fgets_unlocked / fgetws_unlocked as one step value. Every byte starts at
   zero: a short line ("\n") writes only LLine[0..1], and the hash reads
   LLine[2] too, which must not be the stack's leftover */
static int64_t std_hookio_c_linenolock(FILE *AFile)
{
  char LLine[8] = {0};

  if (fgets_unlocked(LLine, 4, AFile) == NULL)
    return -1;
  return (int64_t)LLine[0] * 65536 + (int64_t)LLine[1] * 256 + LLine[2];
}

static int64_t std_hookio_c_wlinenolock(FILE *AFile)
{
  wchar_t LLine[8];

  LLine[0] = L'\0';
  if (fgetws_unlocked(LLine, 8, AFile) == NULL)
    return -1;
  return std_hookio_c_whash(LLine);
}
#endif

/* AWant bytes by the target's lock-free fread as one step value: the
   count, then the bytes */
static int64_t std_hookio_c_readnolock(FILE *AFile, size_t AWant)
{
  unsigned char LBytes[4];
  size_t LGot;

  LBytes[0] = 0;
  LBytes[1] = 0;
  LBytes[2] = 0;
#if defined(_WIN32)
  LGot = _fread_nolock(LBytes, 1, AWant, AFile);
#else
  LGot = fread_unlocked(LBytes, 1, AWant, AFile);
#endif
  return (int64_t)LGot * 0x1000000 + (int64_t)LBytes[0] * 65536 + (int64_t)LBytes[1] * 256 + LBytes[2];
}

void std_hookio_c_nolock(const char *APath, const char *AMode, const char *ALocale,
                         int AVariant, int64_t *AResults)
{
  FILE *LFile;
  int LStep = 0;
  int LI;
  char LSaved[256];
  const char *LOld;

  std_hookio_c_unreached(AResults, STD_HOOKIO_C_WSLOTS);
  for (LI = 77; LI < STD_HOOKIO_C_WSLOTS; ++LI)
    AResults[LI] = -1;
  LOld = setlocale(LC_ALL, NULL);
  snprintf(LSaved, sizeof(LSaved), "%s", (LOld != NULL) ? LOld : "C");
  AResults[72] = (setlocale(LC_ALL, ALocale) != NULL) ? 1 : 0;
  LFile = fopen(APath, AMode);
  AResults[73] = (LFile != NULL) ? 1 : 0;
  if (LFile == NULL)
  {
    setlocale(LC_ALL, LSaved);
    return;
  }
#if defined(_WIN32)
  if (AVariant == 0)
  {
    STD_HOOKIO_C_WSTEP(_fputc_nolock('a', LFile));
    STD_HOOKIO_C_WSTEP(_putc_nolock('b', LFile));
    STD_HOOKIO_C_WSTEP(_fwrite_nolock("cdef", 1, 4, LFile));
    STD_HOOKIO_C_WSTEP(_fflush_nolock(LFile));
    STD_HOOKIO_C_WSTEP(_fseek_nolock(LFile, 0, SEEK_SET));
    STD_HOOKIO_C_WSTEP(_fgetc_nolock(LFile));
    STD_HOOKIO_C_WSTEP(_getc_nolock(LFile));
    STD_HOOKIO_C_WSTEP(_ungetc_nolock('Z', LFile));
    STD_HOOKIO_C_WSTEP(std_hookio_c_readnolock(LFile, 3));
    STD_HOOKIO_C_WSTEP(_ftell_nolock(LFile));
    STD_HOOKIO_C_WSTEP(_fseeki64_nolock(LFile, -2, SEEK_END));
    STD_HOOKIO_C_WSTEP(_ftelli64_nolock(LFile));
  }
  else
  {
    STD_HOOKIO_C_WSTEP(_fputwc_nolock(L'A', LFile));
    STD_HOOKIO_C_WSTEP(_putwc_nolock(L'\u00e9', LFile));
    STD_HOOKIO_C_WSTEP(_fputwc_nolock(L'\n', LFile));
    STD_HOOKIO_C_WSTEP(_fflush_nolock(LFile));
    STD_HOOKIO_C_WSTEP(_fseek_nolock(LFile, 0, SEEK_SET));
    STD_HOOKIO_C_WSTEP(_fgetwc_nolock(LFile));
    STD_HOOKIO_C_WSTEP(_getwc_nolock(LFile));
    STD_HOOKIO_C_WSTEP(_ungetwc_nolock(L'Q', LFile));
    STD_HOOKIO_C_WSTEP(_fgetwc_nolock(LFile));
    STD_HOOKIO_C_WSTEP(_fgetwc_nolock(LFile));
    STD_HOOKIO_C_WSTEP(_ftell_nolock(LFile));
  }
  errno = 0;
  AResults[74] = _fclose_nolock(LFile);
#else
  if (AVariant == 0)
  {
    STD_HOOKIO_C_WSTEP(fputc_unlocked('a', LFile));
    STD_HOOKIO_C_WSTEP(putc_unlocked('b', LFile));
    STD_HOOKIO_C_WSTEP(fwrite_unlocked("cdef", 1, 4, LFile));
    STD_HOOKIO_C_WSTEP(fputs_unlocked("gh\n", LFile));
    STD_HOOKIO_C_WSTEP(fflush_unlocked(LFile));
    STD_HOOKIO_C_WSTEP(fseek(LFile, 0, SEEK_SET));
    STD_HOOKIO_C_WSTEP(fgetc_unlocked(LFile));
    STD_HOOKIO_C_WSTEP(getc_unlocked(LFile));
    STD_HOOKIO_C_WSTEP(std_hookio_c_readnolock(LFile, 3));
    STD_HOOKIO_C_WSTEP(std_hookio_c_linenolock(LFile));
    STD_HOOKIO_C_WSTEP(std_hookio_c_linenolock(LFile) * 4 + feof_unlocked(LFile) * 2 + ferror_unlocked(LFile));
    STD_HOOKIO_C_WSTEP((clearerr_unlocked(LFile), feof_unlocked(LFile)));
  }
  else
  {
    STD_HOOKIO_C_WSTEP(fputwc_unlocked(L'A', LFile));
    STD_HOOKIO_C_WSTEP(putwc_unlocked(L'\u00e9', LFile));
    STD_HOOKIO_C_WSTEP(fputws_unlocked(L"xy\nzw\n", LFile));
    STD_HOOKIO_C_WSTEP(fflush_unlocked(LFile));
    STD_HOOKIO_C_WSTEP(fseek(LFile, 0, SEEK_SET));
    STD_HOOKIO_C_WSTEP(fgetwc_unlocked(LFile));
    STD_HOOKIO_C_WSTEP(getwc_unlocked(LFile));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wlinenolock(LFile));
    STD_HOOKIO_C_WSTEP(fseek(LFile, 0, SEEK_SET));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wlinechk(LFile, 0));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wlinechk(LFile, 1));
    STD_HOOKIO_C_WSTEP(std_hookio_c_wlinechk(LFile, 1));
  }
  errno = 0;
  AResults[74] = fclose(LFile);
#endif
  setlocale(LC_ALL, LSaved);
  std_hookio_c_wreadback(APath, AResults);
}
