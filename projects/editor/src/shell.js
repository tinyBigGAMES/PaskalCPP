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

  PaskalCPP Editor - shell (window chrome).

  Owns everything around the Monaco editor: title bar toolbar, sashes,
  tab strip rendering, the bottom panel (OUTPUT | PROBLEMS) and the status
  bar. It knows nothing about documents; renderer.js drives it through the
  API returned below, and every toolbar button reports the same command
  string the application menu sends (main.js sendMenu).
*/
'use strict';

var PcShell = (function () {
  var PC_EXPLORER_MIN = 120;
  var PC_EXPLORER_MAX = 600;
  var PC_PANEL_MIN = 60;
  var PC_EDITOR_MIN = 100;

  var gOnCommand = null;

  function byId(AId) {
    return document.getElementById(AId);
  }

  function command(ACommand) {
    if (gOnCommand) {
      gOnCommand(ACommand);
    }
  }

  function setRootVar(AName, AValue) {
    document.documentElement.style.setProperty(AName, AValue);
  }

  function clamp(AValue, AMin, AMax) {
    return Math.max(AMin, Math.min(AMax, AValue));
  }

  // Pixel value of a --fs-* size on the root (CSS or a sash drag)
  function rootPx(AName) {
    return parseFloat(getComputedStyle(document.documentElement).getPropertyValue(AName)) || 0;
  }

  // Tells main.js the layout the user now sees (saved in state.json)
  function reportLayout() {
    window.host.setLayout({
      explorerWidth: rootPx('--pc-explorer-w'),
      panelHeight: rootPx('--pc-panel-h'),
      panelCollapsed: byId('panel').classList.contains('collapsed')
    });
  }

  // Largest panel height the center column allows now (same rule as the
  // horizontal sash: the tab strip + a minimum editor stay above it)
  function maxPanelHeight() {
    var LRect = byId('center').getBoundingClientRect();
    return Math.max(PC_PANEL_MIN, LRect.height - PC_EDITOR_MIN - byId('tabs').offsetHeight);
  }

  function setPanelCollapsed(ACollapsed) {
    byId('panel').classList.toggle('collapsed', ACollapsed);
    byId('panel-toggle').title = ACollapsed ? 'Expand panel' : 'Collapse panel';
  }

  // Applies the saved layout + toolbar choices once at boot. AState =
  // { layout, build } from main.js; null parts keep the defaults. Sizes are
  // clamped against the live window (it may be smaller than when saved).
  function applyUiState(AState) {
    var LLayout = AState ? AState.layout : null;
    var LBuild = AState ? AState.build : null;
    if (LLayout) {
      setRootVar('--pc-explorer-w', clamp(LLayout.explorerWidth, PC_EXPLORER_MIN, PC_EXPLORER_MAX) + 'px');
      setRootVar('--pc-panel-h', clamp(LLayout.panelHeight, PC_PANEL_MIN, maxPanelHeight()) + 'px');
      setPanelCollapsed(LLayout.panelCollapsed);
    }
    if (LBuild) {
      byId('tb-mode').value = LBuild.mode;
      byId('tb-target').value = LBuild.target;
      byId('st-mode').textContent = getBuildMode();
      byId('st-target').textContent = getTarget();
    }
  }

  function reportBuildChoice() {
    window.host.setBuildChoice({ mode: getBuildMode(), target: getTarget() });
  }

  // Generic sash: pointer capture on the handle; AOnMove turns each pointer
  // move into a new size and stores it (CSS custom property)
  // AOnEnd (optional) runs once when the drag ends
  function initSash(ASash, AAxisClass, AOnMove, AOnEnd) {
    ASash.addEventListener('pointerdown', function (AEvent) {
      if (AEvent.button !== 0) {
        return;
      }
      AEvent.preventDefault();
      ASash.setPointerCapture(AEvent.pointerId);
      ASash.classList.add('dragging');
      document.body.classList.add('resizing', AAxisClass);

      function onMove(AMoveEvent) {
        AOnMove(AMoveEvent);
      }

      function onUp(AUpEvent) {
        ASash.releasePointerCapture(AUpEvent.pointerId);
        ASash.classList.remove('dragging');
        document.body.classList.remove('resizing', AAxisClass);
        ASash.removeEventListener('pointermove', onMove);
        ASash.removeEventListener('pointerup', onUp);
        ASash.removeEventListener('pointercancel', onUp);
        if (AOnEnd) {
          AOnEnd();
        }
      }

      ASash.addEventListener('pointermove', onMove);
      ASash.addEventListener('pointerup', onUp);
      ASash.addEventListener('pointercancel', onUp);
    });
  }

  function initSashes() {
    var LExplorer = byId('explorer');
    var LCenter = byId('center');
    var LPanel = byId('panel');

    initSash(byId('sash-v'), 'resizing-v', function (AEvent) {
      var LLeft = LExplorer.getBoundingClientRect().left;
      var LWidth = clamp(AEvent.clientX - LLeft, PC_EXPLORER_MIN, PC_EXPLORER_MAX);
      setRootVar('--pc-explorer-w', LWidth + 'px');
    }, reportLayout);

    initSash(byId('sash-h'), 'resizing-h', function (AEvent) {
      var LRect = LCenter.getBoundingClientRect();
      // Panel grows upward from the bottom of the center column; the tab
      // strip and a minimum editor height stay above it (maxPanelHeight)
      var LHeight = clamp(LRect.bottom - AEvent.clientY, PC_PANEL_MIN, maxPanelHeight());
      LPanel.classList.remove('collapsed');
      setRootVar('--pc-panel-h', LHeight + 'px');
    }, reportLayout);
  }

  function showPanel(AName) {
    var LTabs = document.querySelectorAll('.panel-tab');
    var LBodies;
    var LIndex;
    for (LIndex = 0; LIndex < LTabs.length; LIndex++) {
      LTabs[LIndex].classList.toggle('active', LTabs[LIndex].dataset.panel === AName);
    }
    // Every panel body is #panel-<data-panel name>
    LBodies = document.querySelectorAll('#panel > .panel-body');
    for (LIndex = 0; LIndex < LBodies.length; LIndex++) {
      LBodies[LIndex].classList.toggle('hidden', LBodies[LIndex].id !== 'panel-' + AName);
    }
    // Showing a tab expands a collapsed panel: that is a layout change
    if (byId('panel').classList.contains('collapsed')) {
      setPanelCollapsed(false);
      reportLayout();
    }
  }

  function togglePanel() {
    setPanelCollapsed(!byId('panel').classList.contains('collapsed'));
    reportLayout();
  }

  function initPanel() {
    var LTabs = document.querySelectorAll('.panel-tab');
    var LIndex;
    for (LIndex = 0; LIndex < LTabs.length; LIndex++) {
      LTabs[LIndex].addEventListener('click', function (AEvent) {
        showPanel(AEvent.currentTarget.dataset.panel);
      });
    }
    byId('panel-toggle').addEventListener('click', togglePanel);
    byId('panel-clear').addEventListener('click', clearOutput);
  }

  function initToolbar() {
    var LButtons = document.querySelectorAll('#titlebar [data-cmd]');
    var LIndex;
    for (LIndex = 0; LIndex < LButtons.length; LIndex++) {
      LButtons[LIndex].addEventListener('click', function (AEvent) {
        command(AEvent.currentTarget.dataset.cmd);
      });
    }

    // Logo: the application menu as a popup just below the button
    byId('tb-logo').addEventListener('click', function (AEvent) {
      var LRect = AEvent.currentTarget.getBoundingClientRect();
      window.host.popupMenu(LRect.left, LRect.bottom);
    });

    byId('tb-mode').addEventListener('change', function () {
      byId('st-mode').textContent = getBuildMode();
      reportBuildChoice();
    });
    byId('tb-target').addEventListener('change', function () {
      byId('st-target').textContent = getTarget();
      reportBuildChoice();
    });
  }

  function init(AOnCommand) {
    gOnCommand = AOnCommand;
    initToolbar();
    initSashes();
    initPanel();
  }

  function setTitle(AText) {
    byId('tb-title').textContent = AText;
    document.title = AText;
  }

  // Renders the tab strip. ATabs: [{ label, tooltip, dirty }]; AActive is
  // the index of the shown tab. Click activates, x or middle-click closes.
  function setTabs(ATabs, AActive, AOnActivate, AOnClose) {
    var LStrip = byId('tabs');
    var LNodes = [];
    var LIndex;

    for (LIndex = 0; LIndex < ATabs.length; LIndex++) {
      LNodes.push(makeTab(ATabs[LIndex], LIndex, LIndex === AActive, AOnActivate, AOnClose));
    }
    LStrip.replaceChildren.apply(LStrip, LNodes);
    if (AActive >= 0 && LNodes[AActive]) {
      LNodes[AActive].scrollIntoView({ block: 'nearest', inline: 'nearest' });
    }
  }

  function makeTab(AInfo, AIndex, AIsActive, AOnActivate, AOnClose) {
    var LTab = document.createElement('div');
    var LLabel = document.createElement('span');
    var LClose = document.createElement('button');

    LTab.className = 'tab' + (AIsActive ? ' active' : '') + (AInfo.dirty ? ' dirty' : '');
    LTab.title = AInfo.tooltip;
    LLabel.className = 'tab-label';
    LLabel.textContent = AInfo.label;
    LClose.className = 'tab-close';
    LClose.title = 'Close';

    LTab.addEventListener('click', function () {
      AOnActivate(AIndex);
    });
    // Middle button: suppress the autoscroll cursor, close on release
    LTab.addEventListener('mousedown', function (AEvent) {
      if (AEvent.button === 1) {
        AEvent.preventDefault();
      }
    });
    LTab.addEventListener('auxclick', function (AEvent) {
      if (AEvent.button === 1) {
        AOnClose(AIndex);
      }
    });
    LClose.addEventListener('click', function (AEvent) {
      AEvent.stopPropagation();
      AOnClose(AIndex);
    });

    LTab.appendChild(LLabel);
    LTab.appendChild(LClose);
    return LTab;
  }

  function setCursor(ALine, AColumn) {
    byId('st-pos').textContent = 'Ln ' + ALine + ', Col ' + AColumn;
  }

  function getBuildMode() {
    return byId('tb-mode').value;
  }

  function getTarget() {
    return byId('tb-target').value;
  }

  // OUTPUT draws like a console. Each line is one text node that ends in its
  // '\n' once the line is ended. gOutLine is the line the cursor is on (null:
  // a new line not started yet); gOutCr a pending bare \r: the next text on
  // that line replaces what was there. A line the cursor moved back up onto
  // (ESC[1A) keeps its '\n': text goes in front of it, and a '\n' there moves
  // down to the next line instead of ending it again.
  var gOutLine = null;
  var gOutCr = false;

  // The line's text without its line end, and its line end ('' or '\n')
  function lineEnd(ANode) {
    return ANode.nodeValue.endsWith('\n') ? '\n' : '';
  }

  function lineText(ANode) {
    var LEnd = lineEnd(ANode);
    return ANode.nodeValue.slice(0, ANode.nodeValue.length - LEnd.length);
  }

  function writeLinePart(AOut, AText) {
    var LText;

    if (!gOutLine) {
      gOutLine = document.createTextNode('');
      AOut.appendChild(gOutLine);
    }
    LText = lineText(gOutLine);
    if (gOutCr) {
      LText = '';
      gOutCr = false;
    }
    gOutLine.nodeValue = LText + AText + lineEnd(gOutLine);
  }

  // '\n': end the line, or move down when it already has its line end
  function newLine(AOut) {
    gOutCr = false;
    if (gOutLine && lineEnd(gOutLine) === '\n') {
      gOutLine = gOutLine.nextSibling;
      return;
    }
    writeLinePart(AOut, '\n');
    gOutLine = null;
  }

  // ESC[1A: up one line. On a new line not started yet, the line above is the
  // last one written; at the first line the cursor stays
  function cursorUp(AOut) {
    var LAbove = gOutLine ? gOutLine.previousSibling : AOut.lastChild;
    if (LAbove) {
      gOutLine = LAbove;
    }
  }

  // ESC[2K: the cursor's line becomes empty; its line end stays
  function eraseLine() {
    if (gOutLine) {
      gOutLine.nodeValue = lineEnd(gOutLine);
    }
  }

  function output(AText) {
    var LOut = byId('panel-output');
    // Keep the view pinned to the end only if the user has not scrolled up
    var LAtEnd = LOut.scrollTop + LOut.clientHeight >= LOut.scrollHeight - 4;
    // \r\n is a plain newline; the split keeps each \r / \n and each of the
    // two escapes main.js lets through (PC_LINE_RE) as its own part
    var LParts = AText.replace(/\r\n/g, '\n').split(/(\r|\n|\x1b\[1A|\x1b\[2K)/);
    var LIndex;
    for (LIndex = 0; LIndex < LParts.length; LIndex++) {
      if (LParts[LIndex] === '\n') {
        newLine(LOut);
      } else if (LParts[LIndex] === '\r') {
        gOutCr = true;
      } else if (LParts[LIndex] === '\x1b[1A') {
        cursorUp(LOut);
      } else if (LParts[LIndex] === '\x1b[2K') {
        eraseLine();
      } else if (LParts[LIndex].length > 0) {
        writeLinePart(LOut, LParts[LIndex]);
      }
    }
    if (LAtEnd) {
      LOut.scrollTop = LOut.scrollHeight;
    }
  }

  function outputLine(AText) {
    output(AText + '\n');
  }

  function clearOutput() {
    byId('panel-output').textContent = '';
    gOutLine = null;
    gOutCr = false;
  }

  function setLspState(AText) {
    byId('st-lsp').textContent = 'LSP: ' + AText;
  }

  function setCounts(AErrors, AWarnings) {
    byId('st-counts').textContent = '\u2715 ' + AErrors + ' \u26A0 ' + AWarnings;
    byId('problems-count').textContent = String(AErrors + AWarnings);
  }

  function setBuildState(AText) {
    byId('st-build').textContent = AText;
  }

  // Build / run and the debugger share the build group's Stop and one
  // output folder: which run buttons are on for a build state and a debug
  // state (debug.js: idle | starting | running | stopped). cmd -> enabled,
  // plus continueLabel (F5 continues a stopped program). Pure: probed by
  // scripts\zb_ed\debug_probe.js
  function runButtons(ABuildBusy, ADebugState) {
    var LIdle = ADebugState === 'idle';
    var LStopped = ADebugState === 'stopped';

    return {
      build: !ABuildBusy && LIdle,
      run: !ABuildBusy && LIdle,
      stop: ABuildBusy || !LIdle,
      debugStart: !ABuildBusy && (LIdle || LStopped),
      debugStepOver: LStopped,
      debugStepIn: LStopped,
      debugStepOut: LStopped,
      debugPause: ADebugState === 'running',
      continueLabel: LStopped
    };
  }

  var gBuildBusy = false;
  var gDebugState = 'idle';

  // The build and debug groups from runButtons; the file group is not
  // touched (its state is setFileState's)
  function refreshRunButtons() {
    var LState = runButtons(gBuildBusy, gDebugState);
    var LButtons = document.querySelectorAll('#titlebar .tb-build [data-cmd], #titlebar .tb-debug [data-cmd]');
    var LStart = document.querySelector('#titlebar [data-cmd="debugStart"]');
    var LIndex;

    for (LIndex = 0; LIndex < LButtons.length; LIndex++) {
      LButtons[LIndex].disabled = !LState[LButtons[LIndex].dataset.cmd];
    }
    if (LStart) {
      LStart.querySelector('.tb-label').textContent = LState.continueLabel ? 'Continue' : 'Debug';
      LStart.title = LState.continueLabel ? 'Continue (F5)' : 'Debug (F5)';
      // The icon follows the label: a bug for Debug, play for Continue
      LStart.classList.toggle('tb-continue', LState.continueLabel);
    }
  }

  // A build / run is active (renderer.js)
  function setBusy(ABusy) {
    gBuildBusy = !!ABusy;
    refreshRunButtons();
  }

  // The debug session's state (debug.js)
  function setDebugState(AState) {
    gDebugState = AState || 'idle';
    refreshRunButtons();
  }

  // File buttons: Save while the active tab has unsaved changes, Save All
  // while any tab has, Rename while the active tab has a file (renderer.js
  // refresh)
  function setFileState(ACanSave, ACanSaveAll, ACanRename) {
    document.querySelector('#titlebar [data-cmd="save"]').disabled = !ACanSave;
    document.querySelector('#titlebar [data-cmd="saveAll"]').disabled = !ACanSaveAll;
    document.querySelector('#titlebar [data-cmd="rename"]').disabled = !ACanRename;
  }

  // PROBLEMS list: AList = [{ path, line, col, sev, code, msg }], sev is
  // HINT|WARN|ERROR|FATAL. A row click calls AOnSelect(problem).
  function setProblems(AList, AOnSelect) {
    var LPane = byId('panel-problems');
    var LIndex;
    var LItem;
    var LRow;
    var LIcon;
    var LText;
    var LWhere;

    LPane.textContent = '';
    if (AList.length === 0) {
      LRow = document.createElement('div');
      LRow.className = 'pane-empty';
      LRow.textContent = 'No problems';
      LPane.appendChild(LRow);
      return;
    }
    for (LIndex = 0; LIndex < AList.length; LIndex++) {
      LItem = AList[LIndex];
      LRow = document.createElement('div');
      LRow.className = 'problem-row sev-' + LItem.sev.toLowerCase();
      LRow.title = LItem.path;

      LIcon = document.createElement('span');
      LIcon.className = 'problem-icon';
      if (LItem.sev === 'ERROR' || LItem.sev === 'FATAL') {
        LIcon.textContent = '\u2715';
      } else if (LItem.sev === 'WARN') {
        LIcon.textContent = '\u26A0';
      } else {
        LIcon.textContent = '\u2139';
      }

      LText = document.createElement('span');
      LText.className = 'problem-text';
      // A diagnostic without a code (an LSP one may carry none) shows its text alone
      LText.textContent = LItem.code ? LItem.code + ': ' + LItem.msg : LItem.msg;

      LWhere = document.createElement('span');
      LWhere.className = 'problem-where';
      LWhere.textContent = LItem.path.split(/[\\/]/).pop() + ' [' + LItem.line + ', ' + LItem.col + ']';

      LRow.appendChild(LIcon);
      LRow.appendChild(LText);
      LRow.appendChild(LWhere);
      // Each row keeps its own problem (closure per row, not the loop var)
      LRow.addEventListener('click', makeProblemClick(LItem, AOnSelect));
      LRow.addEventListener('contextmenu', makeProblemMenu(LItem));
      LPane.appendChild(LRow);
    }
  }

  function makeProblemClick(AItem, AOnSelect) {
    return function () {
      AOnSelect(AItem);
    };
  }

  // Right-click: the row's own menu (Report This Error...), built by main
  // with the row's code; main keeps only a diagnostic code
  function makeProblemMenu(AItem) {
    return function (AEvent) {
      AEvent.preventDefault();
      window.host.problemMenu(AItem.code || '');
    };
  }

  return {
    init: init,
    applyUiState: applyUiState,
    setTitle: setTitle,
    setTabs: setTabs,
    setCursor: setCursor,
    getBuildMode: getBuildMode,
    getTarget: getTarget,
    output: output,
    outputLine: outputLine,
    clearOutput: clearOutput,
    showPanel: showPanel,
    setLspState: setLspState,
    setCounts: setCounts,
    setProblems: setProblems,
    setBuildState: setBuildState,
    setBusy: setBusy,
    setDebugState: setDebugState,
    runButtons: runButtons,
    setFileState: setFileState
  };
})();
