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
/* dir_addsourcefile_err_asm.S - assembly dir_addsourcefile_err_asm and
   dir_addsourcefile_err_mixed build in: an instruction that does not exist,
   the assembler's error at this file's line and column (the marked line). */

  .text
  bogus_instruction /* // ERROR ZB0016@3 */
