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

  PaskalCPP Editor - DEBUG panel (bottom panel, DEBUG tab).

  Renders into #panel-debug: CALL STACK, VARIABLES, WATCH. Knows nothing
  about DAP: what it shows comes from PcDebug (debug.js), every action goes
  back through the callbacks init() takes:
    selectFrame(frameId)
    variables(ref) -> Promise<[{ name, value, type, variablesReference }]>
                      (null = the stop is over: nothing is shown)
    addWatch(expression), removeWatch(index)
  A frame = a DAP StackFrame (id, name, source, line, presentationHint).
  A scope = { name, ref, expanded }. A watch = { expression, value, type,
  ref, error } (value undefined and no error = not evaluated: no stop).
  Children load on the first expand and stay cached per row.
*/
'use strict';

var PcDebugView = (function () {
  var PC_DV_INDENT_PX = 14;
  var PC_DV_BASE_PX = 6;
  var PC_DV_IDLE_TEXT = 'Not debugging';

  var gCallbacks = null;
  // Bumped per pane by every show*: children loads of an older tree are
  // dropped when they answer
  var gGeneration = { vars: 0, watch: 0 };
  // CALL STACK rows: [{ id, row }] (select toggles 'active')
  var gFrameRows = [];

  function byId(AId) {
    return document.getElementById(AId);
  }

  // Last segment of a path, either slash (display only)
  function fileName(APath) {
    var LParts = String(APath || '').split(/[\\/]/);

    return LParts[LParts.length - 1];
  }

  function makeSpan(AClass, AText) {
    var LSpan = document.createElement('span');

    LSpan.className = AClass;
    LSpan.textContent = AText;
    return LSpan;
  }

  function makeEmpty(ADepth, AText) {
    var LRow = document.createElement('div');

    LRow.className = 'dv-empty';
    LRow.style.paddingLeft = (PC_DV_BASE_PX + ADepth * PC_DV_INDENT_PX + 18) + 'px';
    LRow.textContent = AText;
    return LRow;
  }

  // --- CALL STACK ----------------------------------------------------------

  function makeFrameRow(AFrame, ASelectedId) {
    var LRow = document.createElement('div');
    var LWhere = '';

    LRow.className = 'dv-row dv-frame';
    // Runtime, C and C++ frames come subtle (the adapter's W3 hint)
    if (AFrame.presentationHint === 'subtle') {
      LRow.classList.add('dv-subtle');
    }
    if (AFrame.id === ASelectedId) {
      LRow.classList.add('active');
    }
    LRow.style.paddingLeft = (PC_DV_BASE_PX + 4) + 'px';
    LRow.appendChild(makeSpan('dv-name', AFrame.name || '?'));
    if (AFrame.source && AFrame.source.path) {
      LWhere = fileName(AFrame.source.path) + ':' + AFrame.line;
      LRow.title = AFrame.source.path + ':' + AFrame.line;
    }
    LRow.appendChild(makeSpan('dv-where', LWhere));
    LRow.addEventListener('click', function () {
      gCallbacks.selectFrame(AFrame.id);
    });
    return LRow;
  }

  function showStack(AFrames, ASelectedId) {
    var LPane = byId('dbg-stack');
    var LIndex;
    var LRow;

    LPane.textContent = '';
    gFrameRows = [];
    if (!AFrames || AFrames.length === 0) {
      LPane.appendChild(makeEmpty(0, 'No frames'));
      return;
    }
    for (LIndex = 0; LIndex < AFrames.length; LIndex++) {
      LRow = makeFrameRow(AFrames[LIndex], ASelectedId);
      gFrameRows.push({ id: AFrames[LIndex].id, row: LRow });
      LPane.appendChild(LRow);
    }
  }

  function select(AId) {
    var LIndex;

    for (LIndex = 0; LIndex < gFrameRows.length; LIndex++) {
      gFrameRows[LIndex].row.classList.toggle('active', gFrameRows[LIndex].id === AId);
    }
  }

  // --- VARIABLES / WATCH trees ---------------------------------------------

  // AEntry: { name, value, type, ref, error, isScope, removeIndex }
  // (removeIndex >= 0 = a watch row: it gets a remove button)
  // Item: { el, row, twisty, children, entry, depth, pane, generation,
  //         loaded, expanded }
  function makeItem(AEntry, ADepth, APane, AGeneration) {
    var LItem = {
      el: document.createElement('div'),
      row: document.createElement('div'),
      twisty: document.createElement('span'),
      children: document.createElement('div'),
      entry: AEntry,
      depth: ADepth,
      pane: APane,
      generation: AGeneration,
      loaded: false,
      expanded: false
    };
    var LRemove;

    LItem.row.className = 'dv-row';
    LItem.row.style.paddingLeft = (PC_DV_BASE_PX + ADepth * PC_DV_INDENT_PX) + 'px';
    LItem.twisty.className = 'dv-twisty';
    LItem.twisty.textContent = AEntry.ref > 0 ? '\u25B8' : '';
    LItem.row.appendChild(LItem.twisty);
    LItem.row.appendChild(makeSpan(AEntry.isScope ? 'dv-name dv-scope' : 'dv-name', AEntry.name));
    if (AEntry.error) {
      LItem.row.appendChild(makeSpan('dv-sep', ': '));
      LItem.row.appendChild(makeSpan('dv-value dv-error', AEntry.error));
    } else if (AEntry.value !== undefined) {
      LItem.row.appendChild(makeSpan('dv-sep', ': '));
      LItem.row.appendChild(makeSpan('dv-value', AEntry.value));
    }
    if (AEntry.type) {
      LItem.row.title = AEntry.name + ': ' + AEntry.type;
    }
    if (AEntry.removeIndex >= 0) {
      LRemove = document.createElement('button');
      LRemove.className = 'dv-remove';
      LRemove.title = 'Remove watch';
      LRemove.textContent = '\u00D7';
      LRemove.addEventListener('click', function (AEvent) {
        AEvent.stopPropagation();
        gCallbacks.removeWatch(AEntry.removeIndex);
      });
      LItem.row.appendChild(LRemove);
    }
    LItem.children.className = 'dv-children hidden';
    LItem.el.appendChild(LItem.row);
    LItem.el.appendChild(LItem.children);
    LItem.row.addEventListener('click', function () {
      toggle(LItem);
    });
    return LItem;
  }

  async function toggle(AItem) {
    var LList;
    var LIndex;
    var LVar;

    if (!(AItem.entry.ref > 0)) {
      return;
    }
    AItem.expanded = !AItem.expanded;
    AItem.twisty.textContent = AItem.expanded ? '\u25BE' : '\u25B8';
    AItem.children.classList.toggle('hidden', !AItem.expanded);
    if (!AItem.expanded || AItem.loaded) {
      return;
    }
    AItem.loaded = true;
    AItem.children.appendChild(makeEmpty(AItem.depth + 1, 'Loading...'));
    try {
      LList = await gCallbacks.variables(AItem.entry.ref);
    } catch (AError) {
      if (AItem.generation === gGeneration[AItem.pane]) {
        AItem.children.textContent = '';
        AItem.children.appendChild(makeEmpty(AItem.depth + 1, AError.message));
      }
      return;
    }
    // A newer tree replaced this one, or the stop is over (null)
    if (AItem.generation !== gGeneration[AItem.pane] || LList === null) {
      return;
    }
    AItem.children.textContent = '';
    if (LList.length === 0) {
      AItem.children.appendChild(makeEmpty(AItem.depth + 1, 'No children'));
      return;
    }
    for (LIndex = 0; LIndex < LList.length; LIndex++) {
      LVar = LList[LIndex];
      AItem.children.appendChild(makeItem({
        name: LVar.name,
        value: LVar.value,
        type: LVar.type,
        ref: LVar.variablesReference || 0,
        removeIndex: -1
      }, AItem.depth + 1, AItem.pane, AItem.generation).el);
    }
  }

  function showScopes(AScopes) {
    var LPane = byId('dbg-vars');
    var LGeneration = ++gGeneration.vars;
    var LIndex;
    var LItem;

    LPane.textContent = '';
    if (!AScopes || AScopes.length === 0) {
      LPane.appendChild(makeEmpty(0, 'No variables'));
      return;
    }
    for (LIndex = 0; LIndex < AScopes.length; LIndex++) {
      LItem = makeItem({
        name: AScopes[LIndex].name,
        ref: AScopes[LIndex].ref,
        isScope: true,
        removeIndex: -1
      }, 0, 'vars', LGeneration);
      LPane.appendChild(LItem.el);
      if (AScopes[LIndex].expanded) {
        toggle(LItem);
      }
    }
  }

  function showWatches(AItems) {
    var LPane = byId('dbg-watch');
    var LGeneration = ++gGeneration.watch;
    var LIndex;
    var LWatch;

    LPane.textContent = '';
    if (!AItems || AItems.length === 0) {
      LPane.appendChild(makeEmpty(0, 'Type an expression above, Enter adds it'));
      return;
    }
    for (LIndex = 0; LIndex < AItems.length; LIndex++) {
      LWatch = AItems[LIndex];
      LPane.appendChild(makeItem({
        name: LWatch.expression,
        value: LWatch.value,
        type: LWatch.type,
        ref: LWatch.ref || 0,
        error: LWatch.error || '',
        removeIndex: LIndex
      }, 0, 'watch', LGeneration).el);
    }
  }

  // Running / ended: the stack and the variables show AText (pending
  // children loads are dropped); the watches are shown by showWatches
  function showMessage(AText) {
    var LStack = byId('dbg-stack');
    var LVars = byId('dbg-vars');

    gGeneration.vars++;
    gFrameRows = [];
    LStack.textContent = '';
    LStack.appendChild(makeEmpty(0, AText));
    LVars.textContent = '';
    LVars.appendChild(makeEmpty(0, AText));
  }

  function onWatchKey(AEvent) {
    var LInput = AEvent.currentTarget;
    var LText = String(LInput.value || '').trim();

    if (AEvent.key === 'Enter') {
      AEvent.preventDefault();
      if (LText !== '') {
        gCallbacks.addWatch(LText);
      }
      LInput.value = '';
    } else if (AEvent.key === 'Escape') {
      LInput.value = '';
    }
  }

  function init(ACallbacks) {
    gCallbacks = ACallbacks;
    byId('dbg-watch-input').addEventListener('keydown', onWatchKey);
    showMessage(PC_DV_IDLE_TEXT);
    showWatches([]);
  }

  return {
    init: init,
    showStack: showStack,
    select: select,
    showScopes: showScopes,
    showWatches: showWatches,
    showMessage: showMessage,
    idleText: PC_DV_IDLE_TEXT
  };
})();
