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
   calls the clink routines decl_linkage_triple (exported),
   decl_linkage_quad (private) and decl_linkage_half (private, forward +
   full) by their plain C names, which links only because clink gives each
   routine C linkage, whatever its visibility. It also passes a record and
   an opaque typedef BY VALUE to the clink routines decl_linkage_sum and
   decl_linkage_len, calls decl_linkage_sum through a function pointer, and
   hands PaskalCPP a pointer to its own decl_linkage_c_product. The pair is
   8 bytes, so both targets' C ABIs pass it in one register: a callee that
   took it by reference would read it as an address.
   Nothing to check here. */

typedef struct decl_linkage_pair
{
  int x;
  int y;
} decl_linkage_pair;

typedef const char *decl_linkage_text;
typedef int (*decl_linkage_pair_fn)(decl_linkage_pair AP);

int decl_linkage_triple(int AN);
int decl_linkage_quad(int AN);
int decl_linkage_half(int AN);
int decl_linkage_sum(decl_linkage_pair AP);
int decl_linkage_len(decl_linkage_text AT);

static decl_linkage_pair decl_linkage_make(int AX, int AY)
{
  decl_linkage_pair LP;
  LP.x = AX;
  LP.y = AY;
  return LP;
}

int decl_linkage_sum_from_c(int AX, int AY)
{
  return decl_linkage_sum(decl_linkage_make(AX, AY));
}

int decl_linkage_len_from_c(void)
{
  return decl_linkage_len("abcd");
}

int decl_linkage_call_from_c(decl_linkage_pair_fn AFn, int AX, int AY)
{
  return AFn(decl_linkage_make(AX, AY));
}

static int decl_linkage_c_product(decl_linkage_pair AP)
{
  return AP.x * AP.y;
}

decl_linkage_pair_fn decl_linkage_c_product_fn(void)
{
  return decl_linkage_c_product;
}

int decl_linkage_from_c(int AN)
{
  return decl_linkage_triple(AN) + 1;
}

int decl_linkage_quad_from_c(int AN)
{
  return decl_linkage_quad(AN) + 1;
}

int decl_linkage_half_from_c(int AN)
{
  return decl_linkage_half(AN) + 1;
}
