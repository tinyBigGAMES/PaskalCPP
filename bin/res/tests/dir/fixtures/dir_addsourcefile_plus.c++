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
// dir_addsourcefile_plus.c++ - C++ source dir_addsourcefile builds in: .c++
// is C++ (a lambda builds only as C++). Not a test.

extern "C" int dir_asf_plus(int a)
{
  auto LNext = [](int x) { return x + 1; };
  return LNext(a);
}
