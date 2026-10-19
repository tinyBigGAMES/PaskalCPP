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
/* lib_plain_host.c - the C consumer of lib_plain, built by another toolchain
   (see lib_plain.pcpp's header). Nothing to check here. */

#include <stdio.h>

int lib_plain_add(int a, int b);

int main(void)
{
  printf("from C: lib_plain_add(2, 3) = %d\n", lib_plain_add(2, 3));
  return 0;
}
