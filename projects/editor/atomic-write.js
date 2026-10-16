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

  PaskalCPP Editor - crash-safe file writes (main process).

  writeFileAtomic(AFilename, AText): the file is always the whole old or
  the whole new text, never a part of either. A temp file beside it is
  written and flushed to disk, then renamed over it (one step on the same
  volume). A rename Windows refuses for a moment (antivirus or the search
  indexer briefly holding the target) is retried. On any failure the target
  is left as it was, the temp file is removed and the error is thrown.
  Tested by tests\editor\atomic-write-test.js.
*/
'use strict';

const fs = require('fs');

// A refused rename is retried this many times, this far apart
const PC_ATOMIC_RENAME_TRIES = 5;
const PC_ATOMIC_RENAME_WAIT_MS = 20;
// Rename errors that mean "held for a moment by another process"
const PC_ATOMIC_BUSY_CODES = ['EPERM', 'EBUSY', 'EACCES'];

// Blocks the main thread for AMs milliseconds (only between rename retries)
function sleepSync(AMs) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, AMs);
}

// Deletes APath if it can; a temp file that stays is overwritten by the
// next write and never read
function removeQuietly(APath) {
  try {
    fs.unlinkSync(APath);
  } catch (AIgnored) {
    // already gone, or held
  }
}

// Writes every byte of AText (UTF-8) to ATemp and flushes it to disk. On
// failure ATemp is removed and the error thrown.
function writeTemp(ATemp, AText) {
  const LData = Buffer.from(AText, 'utf8');
  const LFd = fs.openSync(ATemp, 'w');
  let LDone = 0;

  try {
    // writeSync may write less than asked: loop until all of it is out
    while (LDone < LData.length) {
      LDone = LDone + fs.writeSync(LFd, LData, LDone, LData.length - LDone);
    }
    // On disk before it takes the real name: a power loss after the rename
    // cannot leave an empty file behind
    fs.fsyncSync(LFd);
  } catch (AErr) {
    try {
      fs.closeSync(LFd);
    } catch (AIgnored) {
      // the write error is the one that matters
    }
    removeQuietly(ATemp);
    throw AErr;
  }
  fs.closeSync(LFd);
}

function writeFileAtomic(AFilename, AText) {
  const LTemp = AFilename + '.tmp';
  let LTry = 1;

  writeTemp(LTemp, AText);
  while (true) {
    try {
      fs.renameSync(LTemp, AFilename);
      return;
    } catch (AErr) {
      const LBusy = !!AErr && PC_ATOMIC_BUSY_CODES.indexOf(AErr.code) >= 0;
      if (!LBusy || LTry >= PC_ATOMIC_RENAME_TRIES) {
        removeQuietly(LTemp);
        throw AErr;
      }
      LTry = LTry + 1;
      sleepSync(PC_ATOMIC_RENAME_WAIT_MS);
    }
  }
}

module.exports = { writeFileAtomic, PC_ATOMIC_RENAME_TRIES, PC_ATOMIC_RENAME_WAIT_MS };
