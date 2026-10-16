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

  PaskalCPP Editor - LSP host (main process).

  Runs `pcpp.exe --lsp` and speaks JSON-RPC 2.0 with Content-Length
  framing over its stdio. The host restarts the server after a crash. A
  running server locks pcpp.exe: the compiler is rebuilt with the editor
  closed.
*/
'use strict';

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const PC_LSP_EXE = 'pcpp.exe';
// ms before a crashed server is started again
const PC_LSP_RESTART_DELAY = 1000;
// this many crashes inside PC_LSP_CRASH_WINDOW ms = give up (state failed)
const PC_LSP_CRASH_LIMIT = 5;
const PC_LSP_CRASH_WINDOW = 60000;
// ms the server gets to leave after shutdown/exit before it is killed
const PC_LSP_QUIT_GRACE = 1000;
const PC_LSP_HEADER_END = Buffer.from('\r\n\r\n', 'ascii');
const PC_LSP_LENGTH_RE = /content-length:\s*(\d+)/i;

// Byte-exact Content-Length reader. Pipe chunks split anywhere (inside a
// header, inside a multi-byte UTF-8 character), so bytes are held until a
// whole header + body is present. A header without Content-Length is
// skipped so one bad frame cannot stall the reader.
function createFramer(AOnMessage) {
  let LBuf = Buffer.alloc(0);

  return {
    push: (AChunk) => {
      let LEnd;
      let LStart;
      let LMatch;
      let LLength;
      let LBody;
      let LMsg;

      LBuf = Buffer.concat([LBuf, AChunk]);
      while (true) {
        LEnd = LBuf.indexOf(PC_LSP_HEADER_END);
        if (LEnd < 0) {
          return;
        }
        LStart = LEnd + PC_LSP_HEADER_END.length;
        LMatch = PC_LSP_LENGTH_RE.exec(LBuf.toString('ascii', 0, LEnd));
        if (!LMatch) {
          LBuf = LBuf.subarray(LStart);
          continue;
        }
        LLength = parseInt(LMatch[1], 10);
        if (LBuf.length < LStart + LLength) {
          return;
        }
        LBody = LBuf.toString('utf8', LStart, LStart + LLength);
        LBuf = LBuf.subarray(LStart + LLength);
        try {
          LMsg = JSON.parse(LBody);
        } catch (AError) {
          continue;
        }
        AOnMessage(LMsg);
      }
    }
  };
}

// One outgoing frame; Content-Length counts UTF-8 bytes, not characters
function frameMessage(AMsg) {
  const LBody = Buffer.from(JSON.stringify(AMsg), 'utf8');
  const LHeader = Buffer.from('Content-Length: ' + LBody.length + '\r\n\r\n', 'ascii');
  return Buffer.concat([LHeader, LBody]);
}

// AOpts = { binDir, onMessage(msg), onState({ state, detail }) }
// state: starting | running | restarting | failed | stopped
function createLspHost(AOpts) {
  const LExe = path.join(AOpts.binDir, PC_LSP_EXE);
  let LProc = null;
  let LStopping = false;
  let LCrashes = [];
  let LRestartTimer = null;
  let LState = { state: 'stopped', detail: '' };

  function setState(AState, ADetail) {
    LState = { state: AState, detail: ADetail || '' };
    AOpts.onState(LState);
  }

  function start() {
    let LNew;

    if (LProc || LStopping) {
      return;
    }
    // A missing exe is not a crash: fail now, no restart loop
    if (!fs.existsSync(LExe)) {
      setState('failed', LExe + ' not found');
      return;
    }
    setState('starting');
    try {
      LNew = spawn(LExe, ['--lsp'], {
        cwd: AOpts.binDir,
        windowsHide: true,
        // stderr is not part of the protocol; `--log` is the trace channel
        stdio: ['pipe', 'pipe', 'ignore']
      });
    } catch (AError) {
      setState('failed', AError.message);
      return;
    }
    LProc = LNew;
    const LFramer = createFramer(AOpts.onMessage);
    LNew.stdout.on('data', (AChunk) => LFramer.push(AChunk));
    // A write racing the server's death (EPIPE); 'exit' does the recovery
    LNew.stdin.on('error', () => {});
    LNew.on('spawn', () => {
      if (LProc === LNew) {
        setState('running');
      }
    });
    // 'error' (spawn failed / kill failed) and 'exit' may both fire: onGone
    // acts once per process
    LNew.on('error', (AError) => onGone(LNew, AError.message));
    // A killed process has no code, only the signal
    LNew.on('exit', (ACode, ASignal) => onGone(LNew, 'exit ' + (ACode !== null ? ACode : ASignal)));
  }

  function onGone(AProc, ADetail) {
    let LNow;

    if (LProc !== AProc) {
      return;
    }
    LProc = null;
    if (LStopping) {
      setState('stopped');
      return;
    }
    LNow = Date.now();
    LCrashes = LCrashes.filter((ATime) => LNow - ATime < PC_LSP_CRASH_WINDOW);
    LCrashes.push(LNow);
    if (LCrashes.length >= PC_LSP_CRASH_LIMIT) {
      setState('failed', ADetail);
      return;
    }
    setState('restarting', ADetail);
    LRestartTimer = setTimeout(() => {
      LRestartTimer = null;
      start();
    }, PC_LSP_RESTART_DELAY);
  }

  function send(AMsg) {
    if (!LProc || LStopping) {
      return false;
    }
    try {
      LProc.stdin.write(frameMessage(AMsg));
    } catch (AError) {
      return false;
    }
    return true;
  }

  // LSP exit protocol: shutdown request, exit notification, end of stdin
  // (the server also leaves on EOF); a hung server is killed after the grace
  function stop() {
    let LProcNow;
    let LKill;

    LStopping = true;
    if (LRestartTimer) {
      clearTimeout(LRestartTimer);
      LRestartTimer = null;
    }
    if (!LProc) {
      setState('stopped');
      return;
    }
    LProcNow = LProc;
    try {
      LProcNow.stdin.write(frameMessage({ jsonrpc: '2.0', id: 'pc-shutdown', method: 'shutdown' }));
      LProcNow.stdin.write(frameMessage({ jsonrpc: '2.0', method: 'exit' }));
      LProcNow.stdin.end();
    } catch (AError) {
      // The kill below covers a dead pipe
    }
    LKill = setTimeout(() => {
      if (LProcNow.exitCode === null) {
        LProcNow.kill();
      }
    }, PC_LSP_QUIT_GRACE);
    // Never keep the app alive just for this timer
    LKill.unref();
  }

  function begin() {
    LStopping = false;
    start();
  }

  return {
    start: begin,
    stop: stop,
    send: send,
    state: () => LState,
    // Test hook: the live process (null when none)
    proc: () => LProc
  };
}

module.exports = { createFramer, frameMessage, createLspHost };
