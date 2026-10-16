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

  PaskalCPP Editor - the TERMINAL tab's side of Run (main process).

  Run starts `pcpp <file> -r --terminal <pipe>`: pcpp connects to this named
  pipe when its program starts (StdApp.Utils TPtyPipeHost) and writes the
  program's terminal output to it raw (UTF-8, VT kept). Keys and the tab's
  size go back as frames: a kind byte, the payload's length (u32 LE), the
  payload (keys: UTF-8; resize: cols, rows as u16 LE). Keys typed before the
  program connects wait; the size goes first on connection.
  No electron here: scripts\zb_ed\run_term_probe.js drives real pcpp with it.
*/
'use strict';

const net = require('net');
const { StringDecoder } = require('string_decoder');

// = PTY_FRAME_KEYS / PTY_FRAME_RESIZE / PTY_FRAME_HEAD / PTY_SIDE_MAX
// (StdApp.Utils)
const PC_FRAME_KEYS = 0x4B;
const PC_FRAME_RESIZE = 0x52;
const PC_FRAME_HEAD = 5;
const PC_SIDE_MAX = 32767;

let gNextId = 0;

function side(AValue) {
  const LValue = Math.floor(Number(AValue));
  if (!Number.isFinite(LValue) || LValue < 1) {
    return 1;
  }
  return Math.min(LValue, PC_SIDE_MAX);
}

function frame(AKind, APayload) {
  const LHead = Buffer.alloc(PC_FRAME_HEAD);
  LHead[0] = AKind;
  LHead.writeUInt32LE(APayload.length, 1);
  return Buffer.concat([LHead, APayload]);
}

// Keys as the terminal spells them (Enter = '\r')
function keysFrame(AText) {
  return frame(PC_FRAME_KEYS, Buffer.from(String(AText), 'utf8'));
}

function resizeFrame(ACols, ARows) {
  const LPayload = Buffer.alloc(4);
  LPayload.writeUInt16LE(side(ACols), 0);
  LPayload.writeUInt16LE(side(ARows), 2);
  return frame(PC_FRAME_RESIZE, LPayload);
}

// One run's terminal. AHandlers: onConnect() (the program started),
// onOutput(text), onClose() (pcpp let go: the program ended). ACols / ARows:
// the tab's size now
function createRunTerminal(AHandlers, ACols, ARows) {
  const LName = '\\\\.\\pipe\\pcpp-run-' + process.pid + '-' + Date.now() + '-' + (++gNextId);
  const LDecoder = new StringDecoder('utf8');
  let LSocket = null;
  let LClosed = false;
  let LPending = [];
  let LCols = side(ACols);
  let LRows = side(ARows);

  function send(AFrame) {
    if (LSocket !== null) {
      LSocket.write(AFrame);
    } else if (!LClosed) {
      LPending.push(AFrame);
    }
  }

  // Only the first connection is the program's: one run, one terminal
  const LServer = net.createServer((ASocket) => {
    if (LSocket !== null || LClosed) {
      ASocket.destroy();
      return;
    }
    LSocket = ASocket;
    LSocket.write(resizeFrame(LCols, LRows));
    LPending.forEach((AFrame) => LSocket.write(AFrame));
    LPending = [];
    if (AHandlers.onConnect) {
      AHandlers.onConnect();
    }
    LSocket.on('data', (AData) => {
      const LText = LDecoder.write(AData);
      if (LText !== '' && AHandlers.onOutput) {
        AHandlers.onOutput(LText);
      }
    });
    LSocket.on('error', () => {});
    LSocket.on('close', () => {
      const LTail = LDecoder.end();
      if (LTail !== '' && AHandlers.onOutput) {
        AHandlers.onOutput(LTail);
      }
      if (AHandlers.onClose) {
        AHandlers.onClose();
      }
    });
  });

  return {
    name: LName,
    // Resolves once pcpp can connect
    listen: function () {
      return new Promise((AResolve, AReject) => {
        LServer.once('error', AReject);
        LServer.listen(LName, () => {
          LServer.removeListener('error', AReject);
          AResolve();
        });
      });
    },
    input: function (AText) {
      if (typeof AText === 'string' && AText !== '') {
        send(keysFrame(AText));
      }
    },
    resize: function (ACols, ARows) {
      LCols = side(ACols);
      LRows = side(ARows);
      if (LSocket !== null) {
        LSocket.write(resizeFrame(LCols, LRows));
      }
    },
    close: function () {
      LClosed = true;
      LPending = [];
      if (LSocket !== null) {
        LSocket.destroy();
      }
      LServer.close();
    }
  };
}

module.exports = {
  createRunTerminal: createRunTerminal,
  keysFrame: keysFrame,
  resizeFrame: resizeFrame
};
