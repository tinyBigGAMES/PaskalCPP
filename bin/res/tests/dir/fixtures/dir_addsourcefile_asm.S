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
/* dir_addsourcefile_asm.S - assembly dir_addsourcefile_asm builds in: a
   preprocessor warning (the marked line), then a function returning 7. */

#warning dir_addsourcefile_asm: a preprocessor warning /* // WARN ZB0016@2 */
  .text
  .globl dir_asf_asm_seven
dir_asf_asm_seven:
  movl $7, %eax
  ret
