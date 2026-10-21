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
/* cpp_include_quoted.h - a header beside cpp_include_quoted.pcpp: found by
   #include "..." with no directive (cpp_include_quoted.pcpp), never by
   #include <...> (cpp_include_err_angle.pcpp).

   Nothing to check here: cpp_include_quoted.pcpp checks it. */

#ifndef CPP_INCLUDE_QUOTED_H
#define CPP_INCLUDE_QUOTED_H

#define CPP_INCLUDE_QUOTED_TWICE(AValue) ((AValue) * 2)

static inline int cpp_include_quoted_value(void)
{
  return 7;
}

#endif
