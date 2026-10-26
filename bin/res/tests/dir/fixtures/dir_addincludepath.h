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
/* dir_addincludepath.h - a header only dir\fixtures holds: found through
   @addincludepath (dir_addincludepath, dir_addincludepath_byunit).
   Not a test. */

#ifndef DIR_ADDINCLUDEPATH_H
#define DIR_ADDINCLUDEPATH_H

#define DIR_ADDINCLUDEPATH_TWICE(AValue) ((AValue) * 2)

static inline int dir_addincludepath_value(void)
{
  return 30;
}

#endif
