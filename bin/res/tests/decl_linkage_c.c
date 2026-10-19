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
/* decl_linkage_c.c - C source for decl_linkage.pcpp (see its header): it
   calls the clink routine decl_linkage_triple by its plain C name, which
   links only because clink gives the routine C linkage.
   Nothing to check here. */

int decl_linkage_triple(int AN);

int decl_linkage_from_c(int AN)
{
  return decl_linkage_triple(AN) + 1;
}
