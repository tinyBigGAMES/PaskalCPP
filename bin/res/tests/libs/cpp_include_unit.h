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
/* cpp_include_unit.h - a header beside cpp_include_unit.pcpp (res\tests\libs),
   quoted after its cpp header;: found from the unit's own TU and from every
   importer's TU, with no directive (cpp_include_quoted.pcpp).

   Nothing to check here: cpp_include_quoted.pcpp checks it. */

#ifndef CPP_INCLUDE_UNIT_H
#define CPP_INCLUDE_UNIT_H

static inline int cpp_include_unit_value(void)
{
  return 11;
}

#endif
