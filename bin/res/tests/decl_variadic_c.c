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
/* decl_variadic_c.c - C source for decl_variadic.pcpp (see its header): a
   C23 variadic function with no fixed parameter (va_start takes the list
   alone); its first argument is the count of the ints that follow.
   Nothing to check here. */

#include <stdarg.h>

int decl_variadic_csum(...)
{
  va_list LAp;
  int LCount;
  int LTotal;
  int LI;

  va_start(LAp);
  LCount = va_arg(LAp, int);
  LTotal = 0;
  for (LI = 0; LI < LCount; LI++)
    LTotal += va_arg(LAp, int);
  va_end(LAp);
  return LTotal;
}
