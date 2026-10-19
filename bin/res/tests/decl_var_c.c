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
/* decl_var_c.c - C source for decl_var.pcpp (see its header): the C symbol
   its external variable binds, and a reader that sees what PaskalCPP wrote.
   Nothing to check here. */

int decl_var_counter = 41;

int decl_var_read(void)
{
  return decl_var_counter;
}
