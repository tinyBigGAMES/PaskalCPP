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
// dir_addsourcefile_cpp.C - C++ source dir_addsourcefile builds in: C++ only
// (a namespace, a struct), so it builds only as C++ (the capital C picks
// C++). Not a test.

namespace dir_asf
{
  struct Box
  {
    int v;
  };
}

extern "C" int dir_asf_twice(int a)
{
  dir_asf::Box b{a};
  return b.v * 2;
}
