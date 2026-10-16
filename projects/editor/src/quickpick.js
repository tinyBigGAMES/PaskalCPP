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

  PaskalCPP Editor - quick pick overlay (renderer).

  A generic "type to filter, pick one" box (Ctrl+T). Knows nothing about
  the LSP: open(opts) takes
    source(query) -> Promise<{ entries: [{ label, description, ... }] } |
                             { message }>
    onPick(entry), onClose() (cancelled: Esc / click outside), placeholder.
  Entries come back to onPick as given. No DOM is touched until the first
  open(), so rank() can be tested headless.
*/
'use strict';

var PcQuickPick = (function () {
  var PC_QP_DEBOUNCE_MS = 120;
  var PC_QP_MAX_ROWS = 200;

  var gRoot = null;
  var gInput = null;
  var gList = null;
  var gOpts = null;
  var gEntries = [];
  var gSelected = -1;
  var gTimer = null;
  // Bumped per query and on close: a response to an older query is dropped
  var gSeq = 0;

  // Pure: best matches first, case-insensitive. exact > prefix > substring
  // (earlier match first) > shorter label > alphabetical. New array.
  function rank(AEntries, AQuery) {
    var LQuery = (AQuery || '').toLowerCase();
    var LKeyed = [];
    var LIndex;
    var LLabel;
    var LPos;
    var LClass;

    for (LIndex = 0; LIndex < AEntries.length; LIndex++) {
      LLabel = String(AEntries[LIndex].label || '').toLowerCase();
      LPos = LQuery === '' ? 0 : LLabel.indexOf(LQuery);
      if (LQuery === '') {
        LClass = 1;
      } else if (LLabel === LQuery) {
        LClass = 0;
      } else if (LPos === 0) {
        LClass = 1;
      } else if (LPos > 0) {
        LClass = 2;
      } else {
        LClass = 3;
      }
      LKeyed.push({ entry: AEntries[LIndex], cls: LClass, pos: LPos < 0 ? 1e9 : LPos, label: LLabel });
    }
    LKeyed.sort(function (AA, AB) {
      if (AA.cls !== AB.cls) {
        return AA.cls - AB.cls;
      }
      if (AA.pos !== AB.pos) {
        return AA.pos - AB.pos;
      }
      if (AA.label.length !== AB.label.length) {
        return AA.label.length - AB.label.length;
      }
      if (AA.label < AB.label) {
        return -1;
      }
      return AA.label > AB.label ? 1 : 0;
    });
    return LKeyed.map(function (AKeyed) {
      return AKeyed.entry;
    });
  }

  function isOpen() {
    return !!gRoot && !gRoot.classList.contains('hidden');
  }

  // Builds the box inside #quickpick (index.html) on first use
  function ensureDom() {
    var LBox;

    if (gRoot) {
      return;
    }
    gRoot = document.getElementById('quickpick');
    LBox = document.createElement('div');
    LBox.className = 'qp-box';
    gInput = document.createElement('input');
    gInput.className = 'qp-input';
    gInput.type = 'text';
    gInput.spellcheck = false;
    gList = document.createElement('div');
    gList.className = 'qp-list';
    LBox.appendChild(gInput);
    LBox.appendChild(gList);
    gRoot.appendChild(LBox);

    gInput.addEventListener('input', schedule);
    gInput.addEventListener('keydown', onKey);
    // A press on the dimmed backdrop (not the box) cancels
    gRoot.addEventListener('mousedown', function (AEvent) {
      if (AEvent.target === gRoot) {
        close(true);
      }
    });
  }

  function onKey(AEvent) {
    if (AEvent.key === 'ArrowDown') {
      AEvent.preventDefault();
      setSelected(Math.min(gSelected + 1, gEntries.length - 1));
    } else if (AEvent.key === 'ArrowUp') {
      AEvent.preventDefault();
      setSelected(Math.max(gSelected - 1, 0));
    } else if (AEvent.key === 'Enter') {
      AEvent.preventDefault();
      pick(gSelected);
    } else if (AEvent.key === 'Escape') {
      AEvent.preventDefault();
      close(true);
    }
  }

  function schedule() {
    clearTimeout(gTimer);
    gTimer = setTimeout(runQuery, PC_QP_DEBOUNCE_MS);
  }

  async function runQuery() {
    var LSeq = ++gSeq;
    var LQuery = gInput.value;
    var LResult;

    gTimer = null;
    try {
      LResult = await gOpts.source(LQuery);
    } catch (LError) {
      LResult = { message: 'Search failed' };
    }
    // Closed, reopened or typed on since: this answer is stale
    if (LSeq !== gSeq || !isOpen()) {
      return;
    }
    render(LResult || {});
  }

  function render(AResult) {
    var LIndex;
    var LRow;
    var LLabel;
    var LDesc;

    gEntries = (AResult.entries || []).slice(0, PC_QP_MAX_ROWS);
    gSelected = -1;
    gList.textContent = '';
    if (gEntries.length === 0) {
      LRow = document.createElement('div');
      LRow.className = 'pane-empty';
      LRow.textContent = AResult.message || 'No results';
      gList.appendChild(LRow);
      return;
    }
    for (LIndex = 0; LIndex < gEntries.length; LIndex++) {
      LRow = document.createElement('div');
      LRow.className = 'qp-row';
      LLabel = document.createElement('span');
      LLabel.className = 'qp-label';
      LLabel.textContent = gEntries[LIndex].label;
      LDesc = document.createElement('span');
      LDesc.className = 'qp-desc';
      LDesc.textContent = gEntries[LIndex].description || '';
      LRow.appendChild(LLabel);
      LRow.appendChild(LDesc);
      // Keep focus in the input; each row keeps its own index
      LRow.addEventListener('mousedown', preventBlur);
      LRow.addEventListener('click', makePick(LIndex));
      gList.appendChild(LRow);
    }
    setSelected(0);
  }

  function preventBlur(AEvent) {
    AEvent.preventDefault();
  }

  function makePick(AIndex) {
    return function () {
      pick(AIndex);
    };
  }

  function setSelected(AIndex) {
    var LRows = gList.querySelectorAll('.qp-row');
    var LIndex;

    if (LRows.length === 0) {
      return;
    }
    gSelected = AIndex;
    for (LIndex = 0; LIndex < LRows.length; LIndex++) {
      LRows[LIndex].classList.toggle('selected', LIndex === AIndex);
    }
    LRows[AIndex].scrollIntoView({ block: 'nearest' });
  }

  function pick(AIndex) {
    var LEntry = gEntries[AIndex];
    var LOpts = gOpts;

    if (!LEntry || !LOpts) {
      return;
    }
    close(false);
    LOpts.onPick(LEntry);
  }

  // ACancelled: Esc / backdrop -> onClose (the caller restores focus)
  function close(ACancelled) {
    var LOpts = gOpts;

    if (!isOpen()) {
      return;
    }
    gSeq++;
    clearTimeout(gTimer);
    gTimer = null;
    gRoot.classList.add('hidden');
    gEntries = [];
    gSelected = -1;
    gOpts = null;
    if (ACancelled && LOpts && LOpts.onClose) {
      LOpts.onClose();
    }
  }

  // Reopening while open just restarts with the new options
  function open(AOpts) {
    ensureDom();
    gOpts = AOpts;
    gInput.placeholder = AOpts.placeholder || '';
    gInput.value = '';
    gList.textContent = '';
    gRoot.classList.remove('hidden');
    gInput.focus();
    clearTimeout(gTimer);
    runQuery();
  }

  return {
    open: open,
    close: function () {
      close(true);
    },
    isOpen: isOpen,
    rank: rank
  };
})();
