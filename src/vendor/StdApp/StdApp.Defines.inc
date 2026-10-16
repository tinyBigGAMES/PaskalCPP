{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  SPDX-License-Identifier: MPL-2.0

  This Source Code Form is subject to the terms of the
  Mozilla Public License, v. 2.0. If a copy of the MPL
  was not distributed with this file, You can obtain one
  at https://mozilla.org/MPL/2.0/.

 -------------------------------------------------------------------------------

  StdApp.Defines.inc - Compiler directives and platform guard

  Shared include file for all StdApp units. Sets enum size ( $Z4),
  record alignment ( $A8 ), suppresses platform/deprecation warnings,
  enables automatic inlining, and enforces Win64-only compilation.

  Include via $I StdApp.Defines.inc at the top of every unit.

  Dependencies: none
===============================================================================}

{$Z4}
{$A8}

{$WARN SYMBOL_DEPRECATED OFF}
{$WARN SYMBOL_PLATFORM OFF}

{$WARN UNIT_PLATFORM OFF}
{$WARN UNIT_DEPRECATED OFF}

{$INLINE AUTO}

{$IFNDEF WIN64}
  {$MESSAGE Error 'Unsupported platform'}
{$ENDIF}
