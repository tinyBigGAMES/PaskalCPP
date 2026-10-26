; PaskalCPP™ Programming Language
;
; Copyright © 2026-present tinyBigGAMES™ LLC
; All Rights Reserved.
;
; https://paskalcpp.org
;
; SPDX-License-Identifier: MPL-2.0
;
; This Source Code Form is subject to the terms of the
; Mozilla Public License, v. 2.0. If a copy of the MPL
; was not distributed with this file, You can obtain one
; at https://mozilla.org/MPL/2.0/.
;
; ---
; The file's own description is the comment below.
;
; dir_addsourcefile_ll_linux.ll - LLVM IR dir_addsourcefile_ll builds in on
; Linux: a function returning 9. Not a test.

target triple = "x86_64-unknown-linux5.10.0-gnu2.31.0"

define i32 @dir_asf_ll_nine() {
  ret i32 9
}
