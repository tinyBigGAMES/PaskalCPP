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
/* std_hookabi_c.c - C source of std_hookabi_lib.pcpp (a static library) for
   std_hookabi.pcpp (see its header): plain C that calls fopen and stat by
   their C names, as any C library does. The references sit in an archive
   member, so a hook in the program binds them only if a link-time hook
   covers static libraries, which is the case HookABI exists for.
   Each returns 1 when the real function did its job, 0 when not.
   Windows adds fopen_s and _access: the mingw headers declare both
   dllimport, so this code calls them through __imp_fopen_s / __imp__access,
   the import slots the program defines with HOOKABI_IMPORT_SLOT. stat is
   declared there with the asm name stat64i32 (libmingwex), so the call
   below references stat64i32, which the program hooks on Windows. */

#include <stdio.h>
#include <sys/stat.h>
#if defined(_WIN32)
#include <io.h>
#endif

int std_hookabi_c_fopen(const char *APath)
{
  FILE *LFile = fopen(APath, "rb");
  if (LFile == NULL)
    return 0;
  fclose(LFile);
  return 1;
}

int std_hookabi_c_stat(const char *APath)
{
  struct stat LInfo;
  if (stat(APath, &LInfo) != 0)
    return 0;
  return LInfo.st_size > 0 ? 1 : 0;
}

#if defined(_WIN32)

int std_hookabi_c_fopen_s(const char *APath)
{
  FILE *LFile = NULL;
  if (fopen_s(&LFile, APath, "rb") != 0)
    return 0;
  if (LFile == NULL)
    return 0;
  fclose(LFile);
  return 1;
}

int std_hookabi_c_access(const char *APath)
{
  /* Mode 0: the path exists */
  return _access(APath, 0) == 0 ? 1 : 0;
}

#endif
