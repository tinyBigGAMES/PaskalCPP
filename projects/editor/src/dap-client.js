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

  PaskalCPP Editor - DAP client (renderer).

  Debug Adapter Protocol over the preload bridge (window.host.dapStart /
  dapSend / dapStop / onDapMessage / onDapState); main.js (dap-host.js) does
  the framing and checks a launch. Owns the request sequence numbers and
  the event listeners; what a session does is debug.js's business.
*/
'use strict';

var PcDap = (function () {
  // { onState(state) }
  var gOpts = null;
  var gSeq = 0;
  // seq -> { resolve, reject } for requests awaiting a response
  var gPending = {};
  // event name -> [listener]
  var gListeners = {};
  var gState = { state: 'stopped', detail: '' };
  // start()'s resolve while the adapter is starting
  var gStartWaiter = null;

  function rejectAll(AReason) {
    var LSeq;
    var LOld = gPending;
    gPending = {};
    for (LSeq in LOld) {
      LOld[LSeq].reject(new Error(AReason));
    }
  }

  // A failed response as an Error: its message, and .id = DAP's
  // body.error.id when the adapter gave one (0 = none). A client acts on
  // the id, never on the message text
  function failure(AMsg) {
    var LError = new Error(AMsg.message || (AMsg.command + ' failed'));
    var LId = AMsg.body && AMsg.body.error && AMsg.body.error.id;

    LError.id = (typeof LId === 'number') ? LId : 0;
    return LError;
  }

  // Resolves with the response's body ({} when it has none); a response
  // with success false rejects with failure(response)
  function request(ACommand, AArguments) {
    var LSeq;

    if (gState.state !== 'running') {
      return Promise.reject(new Error('No debug session'));
    }
    gSeq++;
    LSeq = gSeq;
    return new Promise(function (AResolve, AReject) {
      gPending[LSeq] = { resolve: AResolve, reject: AReject };
      window.host.dapSend({ seq: LSeq, type: 'request', command: ACommand, arguments: AArguments || {} });
    });
  }

  // A listener for one event name; returns the call that removes it
  function on(AEvent, AListener) {
    if (!gListeners[AEvent]) {
      gListeners[AEvent] = [];
    }
    gListeners[AEvent].push(AListener);
    return function () {
      var LList = gListeners[AEvent] || [];
      var LIndex = LList.indexOf(AListener);
      if (LIndex >= 0) {
        LList.splice(LIndex, 1);
      }
    };
  }

  function dispatch(AEvent, ABody) {
    var LList = (gListeners[AEvent] || []).slice();
    var LIndex;

    for (LIndex = 0; LIndex < LList.length; LIndex++) {
      try {
        LList[LIndex](ABody || {});
      } catch (AError) {
        // One listener's failure must not stop the others
        console.error('dap listener ' + AEvent + ': ' + AError.message);
      }
    }
  }

  function onMessage(AMsg) {
    var LEntry;

    if (!AMsg || typeof AMsg !== 'object') {
      return;
    }
    // A response to a request we did not issue (the host's own disconnect)
    // is ignored
    if (AMsg.type === 'response') {
      LEntry = gPending[AMsg.request_seq];
      if (!LEntry) {
        return;
      }
      delete gPending[AMsg.request_seq];
      if (AMsg.success) {
        LEntry.resolve(AMsg.body || {});
      } else {
        LEntry.reject(failure(AMsg));
      }
      return;
    }
    if (AMsg.type === 'event' && typeof AMsg.event === 'string') {
      dispatch(AMsg.event, AMsg.body);
    }
  }

  function onState(AState) {
    var LWaiter;

    gState = AState || { state: 'stopped', detail: '' };
    // starting / stopped / failed: nothing a request waited for will come
    if (gState.state !== 'running') {
      rejectAll('Debug session ' + gState.state);
    }
    // A start waits for running, or for the end that came instead
    if (gStartWaiter && gState.state !== 'starting') {
      LWaiter = gStartWaiter;
      gStartWaiter = null;
      LWaiter(gState.state === 'running' ? { ok: true, error: '' } :
        { ok: false, error: gState.detail || ('Debugger ' + gState.state) });
    }
    if (gOpts && gOpts.onState) {
      gOpts.onState(gState);
    }
  }

  // Runs the adapter for one session: { ok, error }, resolved once it runs
  // (requests are taken from then on) or could not start. The 'running'
  // state comes as its own event, after dapStart's answer
  function start() {
    gSeq = 0;
    return window.host.dapStart().then(function (AResult) {
      if (!AResult || !AResult.ok || gState.state === 'running') {
        return AResult || { ok: false, error: 'No debugger' };
      }
      return new Promise(function (AResolve) {
        gStartWaiter = AResolve;
      });
    });
  }

  function stop() {
    window.host.dapStop();
  }

  // Subscribe first, then ask: no state change can fall between the two
  function init(AOpts) {
    gOpts = AOpts;
    window.host.onDapMessage(onMessage);
    window.host.onDapState(onState);
    window.host.dapState().then(onState);
  }

  return {
    init: init,
    start: start,
    stop: stop,
    request: request,
    on: on,
    state: function () { return gState; },
    isRunning: function () { return gState.state === 'running'; }
  };
})();
