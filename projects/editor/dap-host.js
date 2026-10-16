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

  PaskalCPP Editor - DAP host (main process).

  Runs `pcpp.exe --dap` for one debug session and passes Debug Adapter
  Protocol messages over its stdio (Content-Length framing, the LSP host's
  framer). One process is one session: no restart. A running adapter locks
  pcpp.exe as the LSP server does: the compiler is rebuilt with the editor
  closed.
*/
'use strict';

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { createFramer, frameMessage } = require('./lsp-host');

const PC_DAP_EXE = 'pcpp.exe';
// ms the adapter gets to leave after disconnect before it is killed
const PC_DAP_QUIT_GRACE = 2000;
// the host's own disconnect request: a seq the renderer's client never uses
// (it counts up from 1)
const PC_DAP_HOST_SEQ = 2147483647;

// AOpts = { binDir, onMessage(msg), onState({ state, detail }) }
// state: starting | running | stopped | failed
function createDapHost(AOpts) {
  const LExe = path.join(AOpts.binDir, PC_DAP_EXE);
  let LProc = null;
  let LState = { state: 'stopped', detail: '' };

  function setState(AState, ADetail) {
    LState = { state: AState, detail: ADetail || '' };
    AOpts.onState(LState);
  }

  // False when a session already runs or the adapter cannot start (the
  // state says why)
  function start() {
    let LNew;

    if (LProc) {
      return false;
    }
    if (!fs.existsSync(LExe)) {
      setState('failed', LExe + ' not found');
      return false;
    }
    setState('starting');
    try {
      LNew = spawn(LExe, ['--dap'], {
        cwd: AOpts.binDir,
        windowsHide: true,
        // stderr is not part of the protocol
        stdio: ['pipe', 'pipe', 'ignore']
      });
    } catch (AError) {
      setState('failed', AError.message);
      return false;
    }
    LProc = LNew;
    const LFramer = createFramer(AOpts.onMessage);
    LNew.stdout.on('data', (AChunk) => LFramer.push(AChunk));
    // A write racing the adapter's end (EPIPE); 'exit' reports it
    LNew.stdin.on('error', () => {});
    LNew.on('spawn', () => {
      if (LProc === LNew) {
        setState('running');
      }
    });
    // 'error' and 'exit' may both fire: onGone acts once per process
    LNew.on('error', (AError) => onGone(LNew, 'failed', AError.message));
    LNew.on('exit', (ACode, ASignal) => onGone(LNew, 'stopped', 'exit ' + (ACode !== null ? ACode : ASignal)));
    return true;
  }

  function onGone(AProc, AState, ADetail) {
    if (LProc !== AProc) {
      return;
    }
    LProc = null;
    setState(AState, ADetail);
  }

  function send(AMsg) {
    if (!LProc) {
      return false;
    }
    try {
      LProc.stdin.write(frameMessage(AMsg));
    } catch (AError) {
      return false;
    }
    return true;
  }

  // The session's end: disconnect (the adapter ends the program), end of
  // stdin (the adapter also leaves on EOF); a hung adapter is killed after
  // the grace
  function stop() {
    let LProcNow;
    let LKill;

    if (!LProc) {
      return;
    }
    LProcNow = LProc;
    try {
      LProcNow.stdin.write(frameMessage({
        seq: PC_DAP_HOST_SEQ,
        type: 'request',
        command: 'disconnect',
        arguments: { terminateDebuggee: true }
      }));
      LProcNow.stdin.end();
    } catch (AError) {
      // The kill below covers a dead pipe
    }
    LKill = setTimeout(() => {
      if (LProcNow.exitCode === null) {
        LProcNow.kill();
      }
    }, PC_DAP_QUIT_GRACE);
    // Never keep the app alive just for this timer
    LKill.unref();
  }

  return {
    start: start,
    stop: stop,
    send: send,
    state: () => LState,
    // Test hook: the live process (null when none)
    proc: () => LProc
  };
}

// A debug host: an absolute path to an existing .exe (a launch's "host",
// a host picked in the dialog)
function isHostExe(APath) {
  return typeof APath === 'string' && path.isAbsolute(APath) &&
    path.extname(APath).toLowerCase() === '.exe' && fs.existsSync(APath);
}

// A launch's arguments as the editor may send them: program = a saved
// .pcpp, host = an existing .exe, args = strings; nothing else passes.
// { args } when they hold, { args: null, error } when not
function checkLaunchArgs(AArgs) {
  const LArgs = AArgs || {};
  const LOut = {};

  if (typeof LArgs.program !== 'string' || !path.isAbsolute(LArgs.program) ||
      path.extname(LArgs.program).toLowerCase() !== '.pcpp' || !fs.existsSync(LArgs.program)) {
    return { args: null, error: 'Not a saved .pcpp file: ' + String(LArgs.program) };
  }
  LOut.program = LArgs.program;
  if (LArgs.host !== undefined) {
    if (!isHostExe(LArgs.host)) {
      return { args: null, error: 'Not an existing .exe: ' + String(LArgs.host) };
    }
    LOut.host = LArgs.host;
  }
  if (LArgs.args !== undefined) {
    if (!Array.isArray(LArgs.args) || !LArgs.args.every((AArg) => typeof AArg === 'string')) {
      return { args: null, error: 'Program arguments must be strings.' };
    }
    LOut.args = LArgs.args;
  }
  return { args: LOut, error: '' };
}

// Remembered debug hosts (e6h; main.js keeps them in state.json): one exe
// per dll source, keyed by the source's resolved path (case-insensitive on
// Windows: either spelling of one file is one entry)
function debugHostKey(ASource) {
  const LPath = path.resolve(String(ASource));
  return process.platform === 'win32' ? LPath.toLowerCase() : LPath;
}

// The remembered hosts as read from a state file: key -> absolute .exe
// path; anything else is dropped ({} when missing or malformed)
function validDebugHosts(AData) {
  const LOut = {};

  if (!AData || typeof AData !== 'object' || Array.isArray(AData)) {
    return LOut;
  }
  for (const LKey of Object.keys(AData)) {
    const LHost = AData[LKey];
    if (LKey !== '' && typeof LHost === 'string' && path.isAbsolute(LHost) &&
        path.extname(LHost).toLowerCase() === '.exe') {
      LOut[LKey] = LHost;
    }
  }
  return LOut;
}

// The host remembered for ASource while its exe still exists ('' = none).
// An entry whose exe is gone is dropped from AHosts: { host, changed }
function hostFor(AHosts, ASource) {
  const LKey = debugHostKey(ASource);
  const LHost = AHosts[LKey];

  if (typeof LHost !== 'string') {
    return { host: '', changed: false };
  }
  if (fs.existsSync(LHost)) {
    return { host: LHost, changed: false };
  }
  delete AHosts[LKey];
  return { host: '', changed: true };
}

module.exports = { createDapHost, checkLaunchArgs, isHostExe, debugHostKey, validDebugHosts, hostFor };
