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

  PaskalCPP Editor - the TERMINAL tab (renderer).

  The debugged program's terminal (PLAN-EDITOR e7 t4): xterm.js 6.0.0
  (vendor/xterm, loaded before Monaco's AMD loader so it sets its globals)
  in #panel-terminal. The adapter runs the program on a pseudo console and
  relays its text with the VT sequences kept: write() shows it as a
  terminal would. Keys typed here and the tab's size go back through the
  callbacks init takes (debug.js sends them to the adapter as
  pcppTerminalInput / pcppTerminalResize). The tab fits itself whenever its
  box changes: shown, the panel's sash, the window.
*/
'use strict';

var PcTerminal = (function () {
  var gTerm = null;
  var gFit = null;
  var gHost = null;
  // callbacks, see init
  var gDeps = null;
  // The size last handed to onResize: a fit that changes nothing sends nothing
  var gCols = 0;
  var gRows = 0;

  // Before the tab was ever measured (= PC_DBG_TERMINAL_COLS / _ROWS,
  // PaskalCPP.Debug.Target)
  var PC_TERM_COLS = 120;
  var PC_TERM_ROWS = 30;
  var PC_TERM_SCROLLBACK = 5000;
  var PC_TERM_FONT_SIZE = 12;

  function cssVar(AName) {
    return getComputedStyle(document.documentElement).getPropertyValue(AName).trim();
  }

  // The tab is laid out (shown, the panel not collapsed): a fit can measure it
  function isMeasurable() {
    return (gHost !== null) && (gHost.offsetWidth > 0) && (gHost.offsetHeight > 0);
  }

  function fit() {
    if ((gTerm === null) || !isMeasurable()) {
      return;
    }
    gFit.fit();
    if ((gTerm.cols === gCols) && (gTerm.rows === gRows)) {
      return;
    }
    gCols = gTerm.cols;
    gRows = gTerm.rows;
    if (gDeps && gDeps.onResize) {
      gDeps.onResize(gCols, gRows);
    }
  }

  function onData(AText) {
    if (gDeps && gDeps.onInput) {
      gDeps.onInput(AText);
    }
  }

  // ADeps: onInput(text): keys typed here, as the terminal spells them
  // (Enter = '\r'); onResize(cols, rows): the tab's size changed
  function init(ADeps) {
    gDeps = ADeps;
    gHost = document.getElementById('panel-terminal');
    gTerm = new Terminal({
      cols: PC_TERM_COLS,
      rows: PC_TERM_ROWS,
      fontFamily: cssVar('--pc-font-code'),
      fontSize: PC_TERM_FONT_SIZE,
      scrollback: PC_TERM_SCROLLBACK,
      // terminal.unicode (the width tables) is a proposed xterm API
      allowProposedApi: true,
      theme: {
        background: cssVar('--pc-bg-panel'),
        foreground: cssVar('--pc-fg'),
        cursor: cssVar('--pc-fg'),
        selectionBackground: cssVar('--pc-bg-active')
      }
    });
    gFit = new FitAddon.FitAddon();
    gTerm.loadAddon(gFit);
    // Unicode 11 widths: xterm's default Unicode 6 tables count an emoji as
    // one cell, so each one is drawn over the next; Unicode 11 gives it two
    gTerm.loadAddon(new Unicode11Addon.Unicode11Addon());
    gTerm.unicode.activeVersion = '11';
    gTerm.open(gHost);
    gTerm.onData(onData);
    // One observer for every change of the tab's box
    new ResizeObserver(function () {
      fit();
    }).observe(gHost);
  }

  // The program's text (VT sequences kept)
  function write(AText) {
    if (gTerm !== null) {
      gTerm.write(AText);
    }
  }

  // A new session starts on an empty terminal
  function reset() {
    if (gTerm !== null) {
      gTerm.reset();
    }
  }

  // The size a launch asks for: the tab's own once it was measured
  function size() {
    fit();
    if ((gCols > 0) && (gRows > 0)) {
      return { cols: gCols, rows: gRows };
    }
    return { cols: PC_TERM_COLS, rows: PC_TERM_ROWS };
  }

  function focus() {
    if (gTerm !== null) {
      gTerm.focus();
    }
  }

  return {
    init: init,
    write: write,
    reset: reset,
    size: size,
    focus: focus
  };
})();
