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

  PaskalCPP Editor - LSP client (renderer).

  JSON-RPC over the preload bridge (window.host.lspSend / onLspMessage /
  onLspState); main.js (lsp-host.js) does the framing. Owns the handshake,
  request ids and the URI form. Every (re)start of the server runs
  initialize + initialized and then calls onReady; which documents are open
  is the caller's business.
*/
'use strict';

var PcLsp = (function () {
  // Bytes FilenameToUri (PaskalCPP.LSP.Server.pas) leaves as they are; all others -> %XX
  var PC_URI_KEEP = /[A-Za-z0-9\/\-_.~]/;

  // { onReady(caps), onDown(), onDiagnostics(uri, diagnostics), onShowMessage(type, message) }
  var gOpts = null;
  var gNextId = 1;
  // id -> { resolve, reject } for requests awaiting a response
  var gPending = {};
  var gReady = false;
  var gHandshaking = false;
  var gCaps = null;
  // Bumped when the server goes down: a handshake from before is stale
  var gGeneration = 0;

  // Byte-identical to PathToUri, so URIs the server sends back compare equal
  // as strings: file:///, '/' separators, UTF-8, upper-case %XX
  function pathToUri(APath) {
    var LBytes = new TextEncoder().encode(APath.replace(/\\/g, '/'));
    var LOut = 'file:///';
    var LIndex;
    var LChar;

    for (LIndex = 0; LIndex < LBytes.length; LIndex++) {
      LChar = String.fromCharCode(LBytes[LIndex]);
      if (LBytes[LIndex] < 128 && PC_URI_KEEP.test(LChar)) {
        LOut += LChar;
      } else {
        LOut += '%' + ('0' + LBytes[LIndex].toString(16).toUpperCase()).slice(-2);
      }
    }
    return LOut;
  }

  function uriToPath(AUri) {
    var LPath = AUri;
    if (LPath.indexOf('file:///') === 0) {
      LPath = LPath.substring(8);
    } else if (LPath.indexOf('file://') === 0) {
      LPath = LPath.substring(7);
    }
    try {
      LPath = decodeURIComponent(LPath);
    } catch (AError) {
      // Malformed escape: keep the raw text rather than lose the location
    }
    return LPath.replace(/\//g, '\\');
  }

  function rejectAll(AReason) {
    var LId;
    var LOld = gPending;
    gPending = {};
    for (LId in LOld) {
      LOld[LId].reject(new Error(AReason));
    }
  }

  function doRequest(AMethod, AParams) {
    var LId = gNextId++;
    return new Promise(function (AResolve, AReject) {
      gPending[LId] = { resolve: AResolve, reject: AReject };
      window.host.lspSend({ jsonrpc: '2.0', id: LId, method: AMethod, params: AParams });
    });
  }

  // Public request: only once the handshake is done
  function request(AMethod, AParams) {
    if (!gReady) {
      return Promise.reject(new Error('LSP not ready'));
    }
    return doRequest(AMethod, AParams);
  }

  function notify(AMethod, AParams) {
    window.host.lspSend({ jsonrpc: '2.0', method: AMethod, params: AParams });
  }

  function onMessage(AMsg) {
    var LEntry;

    if (!AMsg || typeof AMsg !== 'object') {
      return;
    }
    // A response: has an id, no method. Ids we did not issue (the host's
    // own shutdown) are ignored
    if (AMsg.method === undefined && AMsg.id !== undefined) {
      LEntry = gPending[AMsg.id];
      if (!LEntry) {
        return;
      }
      delete gPending[AMsg.id];
      if (AMsg.error) {
        LEntry.reject(new Error(AMsg.error.message || 'LSP error'));
      } else {
        LEntry.resolve(AMsg.result);
      }
      return;
    }
    if (AMsg.method === 'textDocument/publishDiagnostics' && AMsg.params) {
      gOpts.onDiagnostics(AMsg.params.uri, AMsg.params.diagnostics || []);
    }
    if (AMsg.method === 'window/showMessage' && AMsg.params && gOpts.onShowMessage) {
      gOpts.onShowMessage(AMsg.params.type, AMsg.params.message);
    }
  }

  function handshake() {
    var LGeneration;

    // The state can be reported twice (event + initial query)
    if (gReady || gHandshaking) {
      return;
    }
    gHandshaking = true;
    LGeneration = gGeneration;
    doRequest('initialize', {
      processId: null,
      clientInfo: { name: 'PaskalCPP Editor' },
      rootUri: null,
      // The server's file watchers are honoured by the main process
      // (lsp-watch.js): a disk change re-checks the open files
      capabilities: {
        workspace: { didChangeWatchedFiles: { dynamicRegistration: true } }
      }
    }).then(function (AResult) {
      if (LGeneration !== gGeneration) {
        return;
      }
      gCaps = (AResult && AResult.capabilities) || {};
      notify('initialized', {});
      gHandshaking = false;
      gReady = true;
      gOpts.onReady(gCaps);
    }, function () {
      // The server went down mid-handshake; its next 'running' retries
    });
  }

  function onState(AState) {
    if (AState.state === 'running') {
      handshake();
      return;
    }
    // starting / restarting / failed / stopped: nothing the old server
    // knew is valid any more
    gGeneration++;
    gReady = false;
    gHandshaking = false;
    gCaps = null;
    rejectAll('LSP ' + AState.state);
    gOpts.onDown();
  }

  // Subscribe first, then ask: no state change can fall between the two
  function init(AOpts) {
    gOpts = AOpts;
    window.host.onLspMessage(onMessage);
    window.host.onLspState(onState);
    window.host.lspState().then(onState);
  }

  return {
    init: init,
    request: request,
    notify: notify,
    pathToUri: pathToUri,
    uriToPath: uriToPath,
    isReady: function () { return gReady; },
    capabilities: function () { return gCaps; }
  };
})();
