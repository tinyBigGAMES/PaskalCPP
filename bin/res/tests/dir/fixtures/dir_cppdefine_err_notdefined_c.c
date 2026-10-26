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
#ifndef DIR_CPPDEF_ON
#error DIR_CPPDEF_ON is not defined: the @cppdefine macros do not reach this file /* // ERROR ZB0016@2 */
#endif

/* dir_cppdefine_err_notdefined_c.c - C source dir_cppdefine_err_notdefined
   builds in without DIR_CPPDEF_ON: its #error fires (the marked line). */

int dir_cppdef_value(void)
{
  return DIR_CPPDEF_V;
}
