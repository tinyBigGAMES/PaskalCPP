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

  PaskalCPP Editor - LSP file watchers (main process).

  The paths the LSP server registers (client/registerCapability,
  workspace/didChangeWatchedFiles): what the open files' directives name and
  the units they import. Each path is polled (fs.watchFile: a stat about once
  a second), never watched through an open handle: a folder watched with a
  handle cannot be deleted on Windows (the delete stays pending and its parent
  is "not empty"), and the user deletes build output folders. Polling also
  sees a path that does not exist yet appear, and one that goes. A burst of
  changes is one onChanged call.
*/
'use strict';

const fs = require('fs');
const path = require('path');

// ms between two stats of one path
const PC_WATCH_INTERVAL = 1000;
// ms of quiet after the last change before onChanged (a build writes many)
const PC_WATCH_DELAY = 300;
// A glob character: a pattern holding one names no single path
const PC_WATCH_GLOB_RE = /[*?[\]{}]/;

// The watcher's path for one globPattern: a literal absolute path ('/**' at
// the end allowed); a real glob or a relative pattern names none ('')
function patternPath(APattern) {
  let LText;

  if (typeof APattern !== 'string') {
    return '';
  }
  LText = APattern.replace(/\/\*\*$/, '');
  if (LText === '' || PC_WATCH_GLOB_RE.test(LText) || !path.isAbsolute(LText)) {
    return '';
  }
  return path.normalize(LText);
}

// Two stats of one path differ in what a check can see: it appeared or went
// (a missing path stats as all zeros), or it was written
function statChanged(ACurrent, APrevious) {
  return ACurrent.mtimeMs !== APrevious.mtimeMs ||
    ACurrent.size !== APrevious.size ||
    ACurrent.isDirectory() !== APrevious.isDirectory();
}

// AOpts: { onChanged() }
function createLspWatch(AOpts) {
  // registration id -> [paths]
  const LRegistrations = new Map();
  // path (lowercased) -> { path, listener }
  const LPolled = new Map();
  let LTimer = null;

  function schedule() {
    if (LTimer) {
      clearTimeout(LTimer);
    }
    LTimer = setTimeout(() => {
      LTimer = null;
      AOpts.onChanged();
    }, PC_WATCH_DELAY);
  }

  // The polled set follows the registrations: new paths start, gone ones stop.
  // A new path's first stat is its baseline, so a change between the
  // server's check and that stat would never be seen: one refresh follows
  // whenever a path starts (it cannot loop: the same set registers nothing)
  function sync() {
    const LWanted = new Map();
    let LListener;
    let LStarted = 0;

    for (const LPaths of LRegistrations.values()) {
      for (const LPath of LPaths) {
        LWanted.set(LPath.toLowerCase(), LPath);
      }
    }
    for (const [LKey, LEntry] of LPolled) {
      if (!LWanted.has(LKey)) {
        fs.unwatchFile(LEntry.path, LEntry.listener);
        LPolled.delete(LKey);
      }
    }
    for (const [LKey, LPath] of LWanted) {
      if (LPolled.has(LKey)) {
        continue;
      }
      LListener = (ACurrent, APrevious) => {
        if (statChanged(ACurrent, APrevious)) {
          schedule();
        }
      };
      fs.watchFile(LPath, { interval: PC_WATCH_INTERVAL, persistent: false }, LListener);
      LPolled.set(LKey, { path: LPath, listener: LListener });
      LStarted++;
    }
    // The refresh comes PC_WATCH_DELAY later, after the baselines are taken
    if (LStarted > 0) {
      schedule();
    }
  }

  // AWatchers: the registration's registerOptions.watchers
  function register(AId, AWatchers) {
    const LPaths = [];
    let LPath;

    if (Array.isArray(AWatchers)) {
      for (const LWatcher of AWatchers) {
        LPath = patternPath(LWatcher && LWatcher.globPattern);
        if (LPath !== '') {
          LPaths.push(LPath);
        }
      }
    }
    LRegistrations.set(String(AId), LPaths);
    sync();
  }

  function unregister(AId) {
    LRegistrations.delete(String(AId));
    sync();
  }

  // The server went away: what it registered goes with it
  function clear() {
    if (LTimer) {
      clearTimeout(LTimer);
      LTimer = null;
    }
    LRegistrations.clear();
    sync();
  }

  return {
    register,
    unregister,
    clear,
    // Test hook: the paths polled now
    paths: () => Array.from(LPolled.values()).map((AEntry) => AEntry.path)
  };
}

module.exports = { createLspWatch, patternPath, statChanged };
