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
// dir_addsourcefile_cpp.C - C++ source for dir_addsourcefile.pcpp (see its
// header): C++ only (a namespace, a struct), so it builds only as C++.
// Nothing to check here.

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
