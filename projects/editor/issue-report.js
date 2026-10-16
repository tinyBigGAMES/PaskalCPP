/*
  PaskalCPP™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://paskalcpp.org

  SPDX-License-Identifier: MPL-2.0

  This Source Code Form is subject to the terms of the
  Mozilla Public License, v. 2.0. If a copy of the MPL
  was not distributed with this file, You can obtain one
  at https://mozilla.org/MPL/2.0/.

  ---

  PaskalCPP Editor - the issue reporter's rules (main process).

  The reporter is the project's form at <site>/report/ (site = package.json
  about.url, written by pcppdev: one source), opened in a sandboxed modal
  window with version / platform / error_code prefilled. Only those three
  go in the query: no path, no source, no log (issue-reporter\README.md).
  No electron here: scripts\zb_ed\report\check_report.js tests every rule.
*/
'use strict';

const os = require('os');

const PC_REPORT_PATH = '/report/';
const PC_REPORT_TITLE = 'PaskalCPP Issue Reporter';
// Every code the editor shows: two capitals + four digits (LX0006, SM0332, ZB0016)
const PC_CODE_PATTERN = /^[A-Z]{2}[0-9]{4}$/;
// The form's own links (a created issue) open in the user's browser
const PC_LINK_HOST = 'github.com';

function parseUrl(AUrl) {
  try {
    return new URL(String(AUrl));
  } catch (AErr) {
    return null;
  }
}

function isDiagnosticCode(ACode) {
  return typeof ACode === 'string' && PC_CODE_PATTERN.test(ACode);
}

// The form's origin, or '' when the site is not an https URL (an http form
// would send what the person types in the clear)
function reportOrigin(ASiteUrl) {
  const LUrl = parseUrl(ASiteUrl);
  if (!LUrl || LUrl.protocol !== 'https:') {
    return '';
  }
  return LUrl.origin;
}

// The form's URL with its prefilled fields; '' when the site is unusable.
// A code that is not a diagnostic code is left out, never passed through.
function buildReportUrl(ASiteUrl, AVersion, APlatform, ACode) {
  const LOrigin = reportOrigin(ASiteUrl);
  if (LOrigin === '') {
    return '';
  }
  const LUrl = new URL(PC_REPORT_PATH, LOrigin);
  LUrl.searchParams.set('version', String(AVersion || ''));
  LUrl.searchParams.set('platform', String(APlatform || ''));
  if (isDiagnosticCode(ACode)) {
    LUrl.searchParams.set('error_code', ACode);
  }
  return LUrl.toString();
}

// A navigation (or redirect) inside the reporter stays on the form's origin
function isAllowedNavigation(AUrl, AOrigin) {
  const LUrl = parseUrl(AUrl);
  if (!LUrl || !AOrigin) {
    return false;
  }
  return LUrl.origin === AOrigin;
}

// A window the form opens goes to the browser only for https github.com
function isExternalLink(AUrl) {
  const LUrl = parseUrl(AUrl);
  if (!LUrl) {
    return false;
  }
  return LUrl.protocol === 'https:' && LUrl.hostname === PC_LINK_HOST;
}

// The host the editor runs on: OS, CPU, OS release (no path, no user name)
function hostPlatform() {
  return os.platform() + ' ' + os.arch() + ' ' + os.release();
}

// The reporter window: modal to the editor, a remote page with no node,
// no preload, isolated and sandboxed
function reporterWindowOptions(AParent) {
  return {
    parent: AParent,
    modal: true,
    // A minimized modal leaves the editor blocked with nothing on screen
    minimizable: false,
    width: 820,
    height: 820,
    autoHideMenuBar: true,
    title: PC_REPORT_TITLE,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true
    }
  };
}

module.exports = {
  isDiagnosticCode,
  reportOrigin,
  buildReportUrl,
  isAllowedNavigation,
  isExternalLink,
  hostPlatform,
  reporterWindowOptions
};
