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

  PaskalCPP Editor - debugger UI (renderer).

  The editor's side of a debug session over PcDap (dap-client.js).
  Breakpoints (e6d): a click in the glyph margin toggles one; each lives
  as a decoration on its file's model, so it moves with edits, and is read
  back from the decoration whenever it is needed. A file -> lines store
  keeps them while the file has no model (tab closed) and re-creates them
  when a model for that file appears. The store is the truth between
  sessions; a session adds what the adapter says (verified line, hollow
  when not verified, @breakpoint lines of the source).
  Session (e6e): command(cmd) runs F5 / F10 / F11 / Shift+F11 / stop. One
  session = one adapter process (PcDap.start); states idle -> starting ->
  running <-> stopped -> idle. The adapter sends no 'continued' event, so a
  run command marks the session running when it is sent. A stop opens the
  top frame that has a source at its line (current-line decoration).
  DEBUG panel (e6f): the stop's stack, the selected frame's scopes and the
  watches, rendered by PcDebugView (debug-panel.js); selecting a frame
  opens its line and reloads both. Every answer is dropped when its stop,
  its selection or its watch run is over by the time it comes.
  Hover (e6g): while stopped, the name chain under the mouse in the selected
  frame's file is evaluated there (context 'hover').
  Terminal (e7 t4): the program runs on a pseudo console; its text goes to
  the TERMINAL tab (PcTerminal), the tab's keys and size come back here
  (terminalInput / terminalResize -> pcppTerminalInput / pcppTerminalResize);
  launch asks for the tab's size.
*/
'use strict';

var PcDebug = (function () {
  var gMonaco = null;
  var gEditor = null;
  // renderer services, see init
  var gDeps = null;
  // key (keyOf) -> { path, marks: [{ line, verified, dapId }],
  //                 sources: [{ line, dapId }] }
  // marks = the user's breakpoints; sources = @breakpoint lines the
  // adapter announced (shown, never toggled, never kept past a session)
  var gStore = {};
  // key -> { model, ids: [decoration id] } for every file model; ids =
  // marks' decorations in order, then sources' (harvest / render)
  var gAttached = {};
  // True once a session's breakpoints went to the adapter (startSession,
  // right before requests()): from then on a toggle sends its file at once
  // (sendLive); False when the session ends
  var gLive = false;

  var PC_BP_CLASS = 'pc-bp';
  var PC_BP_HOLLOW_CLASS = 'pc-bp-hollow';
  var PC_BP_SOURCE_CLASS = 'pc-bp-source';

  // One spelling per file: Windows paths compare case-insensitively and
  // either slash names the same file
  function keyOf(APath) {
    return APath ? APath.replace(/\//g, '\\').toLowerCase() : '';
  }

  // A model's key from its own URI, so it is known the moment the model
  // is created (before any tab holds it); '' = not a file
  function keyOfModel(AModel) {
    if (!AModel || !AModel.uri || AModel.uri.scheme !== 'file') {
      return '';
    }
    return keyOf(AModel.uri.fsPath);
  }

  function entryOf(AKey, APath) {
    if (!gStore[AKey]) {
      gStore[AKey] = { path: APath, marks: [], sources: [] };
    } else if (APath) {
      // The spelling the tab uses wins over a URI's (drive letter case)
      gStore[AKey].path = APath;
    }
    return gStore[AKey];
  }

  // Sorted by line, one entry per line. Two marks that edits pushed onto
  // one line merge (verified if either is); a source on a mark's line is
  // the mark's (the adapter places one breakpoint there)
  function normalize(AEntry) {
    var LMarks = [];
    var LSources = [];
    var LByLine = {};
    var LIndex;
    var LMark;
    var LSource;

    AEntry.marks.sort(function (AA, AB) { return AA.line - AB.line; });
    for (LIndex = 0; LIndex < AEntry.marks.length; LIndex++) {
      LMark = AEntry.marks[LIndex];
      if (LByLine[LMark.line]) {
        LByLine[LMark.line].verified = LByLine[LMark.line].verified || LMark.verified;
        continue;
      }
      LByLine[LMark.line] = LMark;
      LMarks.push(LMark);
    }
    AEntry.sources.sort(function (AA, AB) { return AA.line - AB.line; });
    for (LIndex = 0; LIndex < AEntry.sources.length; LIndex++) {
      LSource = AEntry.sources[LIndex];
      if (LByLine[LSource.line]) {
        continue;
      }
      LByLine[LSource.line] = LSource;
      LSources.push(LSource);
    }
    AEntry.marks = LMarks;
    AEntry.sources = LSources;
  }

  // Reads the lines back from the decorations of the file's model (edits
  // moved them); a file with no model keeps the lines it has
  function harvest(AKey) {
    var LAttached = gAttached[AKey];
    var LEntry = gStore[AKey];
    var LAll;
    var LIndex;
    var LRange;

    if (!LAttached || !LEntry) {
      return;
    }
    LAll = LEntry.marks.concat(LEntry.sources);
    for (LIndex = 0; LIndex < LAll.length && LIndex < LAttached.ids.length; LIndex++) {
      LRange = LAttached.model.getDecorationRange(LAttached.ids[LIndex]);
      if (LRange) {
        LAll[LIndex].line = LRange.startLineNumber;
      }
    }
    // Lines that merged leave fewer entries than decorations: render again
    // so the ids stay one per entry, in the store's order
    render(AKey);
  }

  function decoration(ALine, AClass) {
    return {
      range: new gMonaco.Range(ALine, 1, ALine, 1),
      options: {
        glyphMarginClassName: AClass,
        stickiness: gMonaco.editor.TrackedRangeStickiness.NeverGrowsWhenTypingAtEdges
      }
    };
  }

  // Replaces the file model's breakpoint decorations with the store's
  function render(AKey) {
    var LAttached = gAttached[AKey];
    var LEntry = gStore[AKey];
    var LDecos = [];
    var LLast;
    var LIndex;

    if (!LAttached) {
      return;
    }
    if (LEntry) {
      // A file that shrank while it had no model: its last lines move up
      LLast = LAttached.model.getLineCount();
      for (LIndex = 0; LIndex < LEntry.marks.length; LIndex++) {
        LEntry.marks[LIndex].line = Math.min(LEntry.marks[LIndex].line, LLast);
      }
      for (LIndex = 0; LIndex < LEntry.sources.length; LIndex++) {
        LEntry.sources[LIndex].line = Math.min(LEntry.sources[LIndex].line, LLast);
      }
      normalize(LEntry);
      for (LIndex = 0; LIndex < LEntry.marks.length; LIndex++) {
        LDecos.push(decoration(LEntry.marks[LIndex].line,
          LEntry.marks[LIndex].verified ? PC_BP_CLASS : PC_BP_HOLLOW_CLASS));
      }
      for (LIndex = 0; LIndex < LEntry.sources.length; LIndex++) {
        LDecos.push(decoration(LEntry.sources[LIndex].line, PC_BP_SOURCE_CLASS));
      }
    }
    LAttached.ids = LAttached.model.deltaDecorations(LAttached.ids, LDecos);
  }

  function findLine(AList, ALine) {
    var LIndex;

    for (LIndex = 0; LIndex < AList.length; LIndex++) {
      if (AList[LIndex].line === ALine) {
        return LIndex;
      }
    }
    return -1;
  }

  // The file a model shows: its tab's path, else its own file URI
  function modelPath(AModel) {
    return gDeps.pathOfModel(AModel) || (AModel.uri ? AModel.uri.fsPath : '');
  }

  // A user toggle on ALine of AModel's file: a mark there goes, else one
  // comes; an @breakpoint line is the source's and stays as it is.
  // True = the file's breakpoints changed
  function toggle(AModel, ALine) {
    var LKey = keyOfModel(AModel);
    var LPath = modelPath(AModel);
    var LEntry;
    var LIndex;

    if (!LKey || !LPath || !gDeps.isSourcePath(LPath)) {
      return false;
    }
    LEntry = entryOf(LKey, LPath);
    harvest(LKey);
    LIndex = findLine(LEntry.marks, ALine);
    if (LIndex >= 0) {
      LEntry.marks.splice(LIndex, 1);
    } else if (findLine(LEntry.sources, ALine) >= 0) {
      return false;
    } else {
      LEntry.marks.push({ line: ALine, verified: true, dapId: null });
    }
    render(LKey);
    return true;
  }

  // Every file's user lines, as setBreakpoints sends them:
  // [{ path, lines }], a file with none left out
  function requests() {
    var LKey;
    var LEntry;
    var LResult = [];

    for (LKey in gStore) {
      harvest(LKey);
      LEntry = gStore[LKey];
      if (LEntry.marks.length > 0) {
        LResult.push({
          path: LEntry.path,
          lines: LEntry.marks.map(function (AMark) { return AMark.line; })
        });
      }
    }
    return LResult;
  }

  // The lines of one file as setBreakpoints sends them ([] = none)
  function linesOf(APath) {
    var LKey = keyOf(APath);

    harvest(LKey);
    if (!gStore[LKey]) {
      return [];
    }
    return gStore[LKey].marks.map(function (AMark) { return AMark.line; });
  }

  // setBreakpoints' response for APath: entry i answers sent line i (DAP).
  // A mark still on its sent line takes the adapter's line (moved to code)
  // and verified state; a mark the user moved or removed meanwhile is left
  function applyResponse(APath, ASentLines, ABody) {
    var LKey = keyOf(APath);
    var LEntry = gStore[LKey];
    var LAnswers = (ABody && ABody.breakpoints) || [];
    var LIndex;
    var LAt;
    var LAnswer;

    if (!LEntry) {
      return;
    }
    harvest(LKey);
    for (LIndex = 0; LIndex < ASentLines.length && LIndex < LAnswers.length; LIndex++) {
      LAt = findLine(LEntry.marks, ASentLines[LIndex]);
      if (LAt < 0) {
        continue;
      }
      LAnswer = LAnswers[LIndex] || {};
      LEntry.marks[LAt].verified = !!LAnswer.verified;
      LEntry.marks[LAt].dapId = (typeof LAnswer.id === 'number') ? LAnswer.id : null;
      if (typeof LAnswer.line === 'number' && LAnswer.line > 0) {
        LEntry.marks[LAt].line = LAnswer.line;
      }
    }
    render(LKey);
  }

  // A toggle during a session: APath's whole set goes to the adapter now
  // (DAP replaces a file's set), its answer moves / hollows the marks as at
  // the start. Before the session's first send nothing is sent: that send
  // takes every file as it stands. A failure is told, the marks stay
  function sendLive(APath) {
    var LSession = gSession;
    var LLines;

    if (!gLive) {
      return;
    }
    LLines = linesOf(APath);
    PcDap.request('setBreakpoints', {
      source: { path: APath },
      breakpoints: LLines.map(function (ALine) { return { line: ALine }; })
    }).then(function (ABody) {
      if (LSession === gSession) {
        applyResponse(APath, LLines, ABody);
      }
    }).catch(function (AError) {
      if (LSession === gSession) {
        gDeps.outputLine('Debug: setBreakpoints: ' + AError.message);
      }
    });
  }

  function findDapId(AList, AId) {
    var LIndex;

    for (LIndex = 0; LIndex < AList.length; LIndex++) {
      if (AList[LIndex].dapId === AId) {
        return LIndex;
      }
    }
    return -1;
  }

  // The adapter's 'breakpoint' event: { reason, breakpoint }. 'new' = an
  // @breakpoint line of a source file (source.path); 'changed' = a known
  // breakpoint verified / moved (an image loaded); 'removed' drops a
  // source line (the user's marks are only ever removed by the user)
  function onBreakpointEvent(ABody) {
    var LBp = (ABody && ABody.breakpoint) || {};
    var LReason = (ABody && ABody.reason) || '';
    var LKey;
    var LEntry;
    var LAt;

    if (typeof LBp.id !== 'number') {
      return;
    }
    if (LReason === 'new') {
      if (!LBp.source || !LBp.source.path || typeof LBp.line !== 'number') {
        return;
      }
      LKey = keyOf(LBp.source.path);
      LEntry = entryOf(LKey, gStore[LKey] ? '' : LBp.source.path);
      harvest(LKey);
      if (findLine(LEntry.marks, LBp.line) < 0 && findLine(LEntry.sources, LBp.line) < 0) {
        LEntry.sources.push({ line: LBp.line, dapId: LBp.id });
      }
      render(LKey);
      return;
    }
    for (LKey in gStore) {
      LEntry = gStore[LKey];
      harvest(LKey);
      LAt = findDapId(LEntry.marks, LBp.id);
      if (LAt >= 0) {
        if (LReason === 'changed') {
          LEntry.marks[LAt].verified = !!LBp.verified;
          if (typeof LBp.line === 'number' && LBp.line > 0) {
            LEntry.marks[LAt].line = LBp.line;
          }
        }
        render(LKey);
        return;
      }
      LAt = findDapId(LEntry.sources, LBp.id);
      if (LAt >= 0) {
        if (LReason === 'removed') {
          LEntry.sources.splice(LAt, 1);
        } else if (LReason === 'changed' && typeof LBp.line === 'number' && LBp.line > 0) {
          LEntry.sources[LAt].line = LBp.line;
        }
        render(LKey);
        return;
      }
    }
  }

  // A session ended: what only the adapter knew goes (source lines,
  // verified state, ids); the user's lines stay
  function clearSessionMarks() {
    var LKey;
    var LEntry;
    var LIndex;

    for (LKey in gStore) {
      harvest(LKey);
      LEntry = gStore[LKey];
      LEntry.sources = [];
      for (LIndex = 0; LIndex < LEntry.marks.length; LIndex++) {
        LEntry.marks[LIndex].verified = true;
        LEntry.marks[LIndex].dapId = null;
      }
      render(LKey);
    }
  }

  // Every file model gets its breakpoints (a reopened tab, a peek into a
  // closed file); its disposal keeps the lines the edits left
  function onModelCreated(AModel) {
    var LKey = keyOfModel(AModel);

    if (!LKey || gAttached[LKey]) {
      return;
    }
    gAttached[LKey] = { model: AModel, ids: [] };
    render(LKey);
    AModel.onWillDispose(function () {
      if (gAttached[LKey] && gAttached[LKey].model === AModel) {
        harvest(LKey);
        delete gAttached[LKey];
      }
    });
  }

  // --- session (e6e) -----------------------------------------------------

  // E3 debugs win64 only (W5): the CLI refuses another target (DB0012)
  var PC_DEBUG_TARGET = 'x86_64-windows-gnu';
  var PC_CURRENT_LINE_CLASS = 'pc-current-line';
  var PC_CURRENT_ARROW_CLASS = 'pc-current-arrow';

  // idle | starting | running | stopped
  var gState = 'idle';
  // Bumped when a session starts and when it ends: an await that resumes
  // in another session (or none) does nothing
  var gSession = 0;
  // Bumped at every stop and every resume: a stack answer for an older
  // stop is not shown
  var gStopSeq = 0;
  // The thread the last stop named (run commands carry it)
  var gThreadId = 0;
  // The frame shown for the stop: { id, path, line } (null = none)
  var gFrame = null;
  // The current-line decoration: { model, ids }
  var gCurrent = null;
  // What the status shows when the session ends ('' = ended)
  var gEndStatus = '';

  function setState(AState) {
    gState = AState;
    gDeps.setDebugState(AState);
  }

  function isActive() {
    return gState !== 'idle';
  }

  function modelGone(AModel) {
    return typeof AModel.isDisposed === 'function' && AModel.isDisposed();
  }

  function clearCurrentLine() {
    if (gCurrent && !modelGone(gCurrent.model)) {
      gCurrent.model.deltaDecorations(gCurrent.ids, []);
    }
    gCurrent = null;
  }

  // Where a DAP frame is shown: { id, path, line } when it has a source
  // file and a line, else null (runtime, C and system code)
  function placeOf(AFrame) {
    if (AFrame && AFrame.source && AFrame.source.path && AFrame.line > 0) {
      return { id: AFrame.id, path: AFrame.source.path, line: AFrame.line };
    }
    return null;
  }

  // The frame a stop shows: the top one with a source file and a line (a
  // stop in the runtime or in C code shows the .pcpp caller); null = none
  function topSourceFrame(AFrames) {
    var LIndex;
    var LPlace;

    for (LIndex = 0; LIndex < (AFrames || []).length; LIndex++) {
      LPlace = placeOf(AFrames[LIndex]);
      if (LPlace) {
        return LPlace;
      }
    }
    return null;
  }

  // Opens AFrame's file and marks its line, unless the stop is over by
  // then or another frame was selected meanwhile
  async function showFrame(ASession, AStop, AFrame) {
    var LModel;

    await gDeps.openPath(AFrame.path);
    if (ASession !== gSession || AStop !== gStopSeq || AFrame !== gFrame) {
      return;
    }
    LModel = gEditor.getModel();
    // The open failed (reported by openPath): no line to mark
    if (!LModel || keyOfModel(LModel) !== keyOf(AFrame.path)) {
      return;
    }
    clearCurrentLine();
    gCurrent = {
      model: LModel,
      ids: LModel.deltaDecorations([], [{
        range: new gMonaco.Range(AFrame.line, 1, AFrame.line, 1),
        options: {
          isWholeLine: true,
          className: PC_CURRENT_LINE_CLASS,
          glyphMarginClassName: PC_CURRENT_ARROW_CLASS
        }
      }])
    };
    // The caret goes to the stop line too (as VS Code's stop does), without
    // taking the focus: typing in the WATCH box goes on undisturbed
    gEditor.setPosition({ lineNumber: AFrame.line, column: 1 });
    gEditor.revealLineInCenterIfOutsideViewport(AFrame.line);
  }

  // --- DEBUG panel (e6f) -------------------------------------------------

  // The stop's stack (DAP StackFrames) and the frame the panel selected
  // (0 = none)
  var gFrames = [];
  var gSelectedId = 0;
  // Bumped at every frame selection: scopes of an older one are dropped
  var gFrameSeq = 0;
  // Bumped at every watch run: values of an older run are dropped
  var gWatchSeq = 0;
  // Watch expressions: kept for the editor's lifetime, across sessions
  var gWatches = [];
  // The DEBUG panel came up for this session's first stop
  var gPanelShown = false;

  function frameById(AId) {
    var LIndex;

    for (LIndex = 0; LIndex < gFrames.length; LIndex++) {
      if (gFrames[LIndex].id === AId) {
        return gFrames[LIndex];
      }
    }
    return null;
  }

  // The watches as the view shows them with no stop: expressions only
  function unevaluatedWatches() {
    return gWatches.map(function (AExpression) {
      return { expression: AExpression };
    });
  }

  // Every watch evaluated in AFrameId ({ context 'watch' }); a failed one
  // shows the adapter's reason. Dropped when the stop, the selection or
  // the watch run changed meanwhile
  async function evaluateWatches(AFrameId) {
    var LSession = gSession;
    var LStop = gStopSeq;
    var LFrameSeq = gFrameSeq;
    var LWatchSeq = ++gWatchSeq;
    var LList = gWatches.slice();
    var LItems = [];
    var LIndex;
    var LBody;

    for (LIndex = 0; LIndex < LList.length; LIndex++) {
      try {
        LBody = await PcDap.request('evaluate', { expression: LList[LIndex], frameId: AFrameId, context: 'watch' });
        LItems.push({
          expression: LList[LIndex],
          value: LBody.result,
          type: LBody.type || '',
          ref: LBody.variablesReference || 0
        });
      } catch (AError) {
        LItems.push({ expression: LList[LIndex], error: AError.message });
      }
      if (LSession !== gSession || LStop !== gStopSeq || LFrameSeq !== gFrameSeq || LWatchSeq !== gWatchSeq) {
        return;
      }
    }
    PcDebugView.showWatches(LItems);
  }

  // The watches as they stand now: evaluated in the selected frame while
  // stopped, else expressions only
  function refreshWatches() {
    if (gState === 'stopped' && gSelectedId !== 0) {
      evaluateWatches(gSelectedId);
    } else {
      gWatchSeq++;
      PcDebugView.showWatches(unevaluatedWatches());
    }
  }

  // The selected frame's scopes (Parameters and Locals open, Globals
  // closed), then its watches; 0 = no frame: nothing to show
  async function loadFrame(AFrameId) {
    var LSession = gSession;
    var LStop = gStopSeq;
    var LFrameSeq = ++gFrameSeq;
    var LBody;
    var LScopes;

    if (AFrameId === 0) {
      PcDebugView.showScopes([]);
      refreshWatches();
      return;
    }
    try {
      LBody = await PcDap.request('scopes', { frameId: AFrameId });
      LScopes = (LBody.scopes || []).map(function (AScope) {
        return {
          name: AScope.name,
          ref: AScope.variablesReference || 0,
          expanded: AScope.presentationHint === 'arguments' || AScope.presentationHint === 'locals'
        };
      });
    } catch (AError) {
      if (LSession === gSession && LStop === gStopSeq) {
        gDeps.outputLine('Debug: scopes: ' + AError.message);
      }
      LScopes = [];
    }
    if (LSession !== gSession || LStop !== gStopSeq || LFrameSeq !== gFrameSeq) {
      return;
    }
    PcDebugView.showScopes(LScopes);
    refreshWatches();
  }

  // A click in CALL STACK: that frame's line is shown (a frame with no
  // source: no line) and its scopes and watches reloaded
  function selectFrame(AId) {
    var LFrame;

    if (gState !== 'stopped') {
      return;
    }
    LFrame = frameById(AId);
    if (!LFrame) {
      return;
    }
    gSelectedId = AId;
    PcDebugView.select(AId);
    gFrame = placeOf(LFrame);
    if (gFrame) {
      showFrame(gSession, gStopSeq, gFrame);
    } else {
      clearCurrentLine();
    }
    loadFrame(AId);
  }

  // A variable's children for the view (lazy expand); null = the stop is
  // over (the adapter's references die at every resume)
  async function variables(ARef) {
    var LSession = gSession;
    var LStop = gStopSeq;
    var LBody;

    if (gState !== 'stopped') {
      return null;
    }
    LBody = await PcDap.request('variables', { variablesReference: ARef });
    if (LSession !== gSession || LStop !== gStopSeq) {
      return null;
    }
    return LBody.variables || [];
  }

  function addWatch(AExpression) {
    var LText = String(AExpression || '').trim();

    if (LText === '') {
      return;
    }
    gWatches.push(LText);
    refreshWatches();
  }

  function removeWatch(AIndex) {
    if (AIndex < 0 || AIndex >= gWatches.length) {
      return;
    }
    gWatches.splice(AIndex, 1);
    refreshWatches();
  }

  // Running or ended: no stack, no variables, the watches unevaluated
  function clearPanel(AText) {
    gFrames = [];
    gSelectedId = 0;
    gFrameSeq++;
    PcDebugView.showMessage(AText);
    refreshWatches();
  }

  // The stopped program's stack: the panel lists it, its top source frame
  // is selected (scopes, watches) and its line shown
  async function showStop(AThreadId) {
    var LSession = gSession;
    var LStop = gStopSeq;
    var LBody;

    try {
      LBody = await PcDap.request('stackTrace', { threadId: AThreadId, startFrame: 0, levels: 0 });
    } catch (AError) {
      if (LSession === gSession) {
        gDeps.outputLine('Debug: stackTrace: ' + AError.message);
      }
      return;
    }
    if (LSession !== gSession || LStop !== gStopSeq) {
      return;
    }
    gFrame = topSourceFrame(LBody.stackFrames);
    gFrames = LBody.stackFrames || [];
    // No source frame: the top one is selected (its scopes still show)
    gSelectedId = gFrame ? gFrame.id : (gFrames.length > 0 ? gFrames[0].id : 0);
    PcDebugView.showStack(gFrames, gSelectedId);
    // The session's first stop brings the DEBUG panel up; later stops
    // leave the tab the user picked
    if (!gPanelShown) {
      gPanelShown = true;
      gDeps.showPanel('debug');
    }
    loadFrame(gSelectedId);
    if (gFrame) {
      await showFrame(LSession, LStop, gFrame);
    }
  }

  function onStopped(ABody) {
    if (gState === 'idle') {
      return;
    }
    gStopSeq++;
    gThreadId = (typeof ABody.threadId === 'number') ? ABody.threadId : 0;
    gFrame = null;
    clearCurrentLine();
    setState('stopped');
    gDeps.setStatus('paused (' + (ABody.reason || 'stop') + ')');
    if (ABody.description) {
      gDeps.outputLine('Debug: ' + ABody.description);
    }
    showStop(gThreadId);
  }

  // continue / next / stepIn / stepOut on the stopped thread. Refused by
  // the adapter = still stopped: the stop is shown again
  function resume(ACommand) {
    var LSession = gSession;
    var LThreadId = gThreadId;

    if (gState !== 'stopped') {
      return;
    }
    gStopSeq++;
    gFrame = null;
    clearCurrentLine();
    setState('running');
    clearPanel('Running...');
    gDeps.setStatus('debugging');
    PcDap.request(ACommand, { threadId: LThreadId }).catch(function (AError) {
      if (LSession !== gSession || gState !== 'running') {
        return;
      }
      gDeps.outputLine('Debug: ' + ACommand + ': ' + AError.message);
      gStopSeq++;
      setState('stopped');
      gDeps.setStatus('paused');
      showStop(LThreadId);
    });
  }

  // The adapter's output: its own lines (the debug build's status and
  // reports: problems are parsed, OUTPUT) and the program's text: the
  // terminal it runs on (VT sequences kept, TERMINAL)
  function onOutput(ABody) {
    var LText = ABody.output || '';

    if (gState === 'idle' || LText === '') {
      return;
    }
    if (ABody.category === 'stdout' || ABody.category === 'stderr') {
      gDeps.terminalWrite(LText);
    } else if (ABody.category !== 'telemetry') {
      gDeps.output(LText);
    }
  }

  function onExited(ABody) {
    var LCode = (typeof ABody.exitCode === 'number') ? ABody.exitCode : 0;

    if (gState === 'idle') {
      return;
    }
    gDeps.outputLine('[exited ' + LCode + ']');
    gEndStatus = 'exited ' + LCode;
  }

  // Everything a session showed goes; the user's breakpoints stay
  function endSession() {
    var LWasActive = gState !== 'idle';

    gSession++;
    gStopSeq++;
    gLive = false;
    gThreadId = 0;
    gFrame = null;
    gPanelShown = false;
    clearCurrentLine();
    clearSessionMarks();
    if (LWasActive) {
      gDeps.finishProblems();
      setState('idle');
      gDeps.setStatus(gEndStatus || 'debug ended');
    }
    // After setState: idle shows the watches unevaluated
    clearPanel(PcDebugView.idleText);
    gEndStatus = '';
  }

  // Stop: a running adapter is told to end (its end then ends the session,
  // onDapState); without one (still saving) the session ends here
  function stopSession() {
    var LDap;

    if (gState === 'idle') {
      return;
    }
    LDap = PcDap.state().state;
    if (LDap === 'running' || LDap === 'starting') {
      clearCurrentLine();
      gDeps.setStatus('debug: stopping');
      PcDap.stop();
    } else {
      endSession();
    }
  }

  // The adapter process ended (or failed to run): the session is over
  function onDapState(AState) {
    if (gState === 'idle' || !AState) {
      return;
    }
    if (AState.state === 'stopped' || AState.state === 'failed') {
      if (AState.state === 'failed' && AState.detail) {
        gDeps.outputLine('Debug: ' + AState.detail);
      }
      endSession();
    }
  }

  // The adapter's body.error ids a launch failure is matched on (pcpp
  // PaskalCPP.Debug.DAP.pas PC_DAP_ERROR_*): never the message text
  var PC_DAP_ERROR_DLL_NO_HOST = 1;
  var PC_DAP_ERROR_HOST_ON_EXE = 2;

  // launch APath with the host remembered for it (a dll runs in the exe
  // that loads it, W4). A dll without one: the user picks it (main
  // remembers it) and the launch goes again; a host given for an exe:
  // forgotten, launched again without. Each fix is tried once; any other
  // refusal (or a second one) rejects with its reason
  async function launchProgram(ASession, APath) {
    var LHost = await gDeps.debugHostFor(APath);
    var LFixed = false;
    var LPick;
    var LArgs;
    var LSize;

    while (true) {
      try {
        // The program's terminal starts at the TERMINAL tab's size
        LSize = gDeps.terminalSize();
        LArgs = { program: APath, terminalCols: LSize.cols, terminalRows: LSize.rows };
        if (LHost) {
          LArgs.host = LHost;
        }
        await PcDap.request('launch', LArgs);
        return;
      } catch (AError) {
        if (ASession !== gSession || LFixed) {
          throw AError;
        }
        LFixed = true;
        if (AError.id === PC_DAP_ERROR_HOST_ON_EXE && LHost) {
          await gDeps.forgetDebugHost(APath);
          LHost = '';
        } else if (AError.id === PC_DAP_ERROR_DLL_NO_HOST && !LHost) {
          gDeps.outputLine('Debug: ' + AError.message + ': pick the host program.');
          LPick = await gDeps.pickDebugHost(APath);
          if (!LPick || !LPick.ok) {
            throw new Error(LPick && LPick.error ? LPick.error : 'no host program picked');
          }
          LHost = LPick.host;
        } else {
          throw AError;
        }
        if (ASession !== gSession) {
          return;
        }
      }
    }
  }

  // F5 while idle: save as Build does, run the adapter, launch the active
  // .pcpp, send the breakpoints, then let the program go
  async function startSession() {
    var LSession;
    var LOk;
    var LPath;
    var LResult;
    var LFiles;
    var LIndex;
    var LBody;

    if (gState !== 'idle') {
      return;
    }
    if (gDeps.buildBusy()) {
      gDeps.outputLine('Debug: a build is running: stop it first (Shift+F5).');
      return;
    }
    if (gDeps.getTarget() !== PC_DEBUG_TARGET) {
      gDeps.showPanel('output');
      gDeps.outputLine('Debug: debugging runs on ' + PC_DEBUG_TARGET + ' only: pick it as the target.');
      return;
    }
    // Claimed before any await, so a second F5 during the saves is a no-op
    gSession++;
    LSession = gSession;
    gStopSeq++;
    gEndStatus = '';
    setState('starting');
    gDeps.setStatus('debug: starting');
    try {
      LOk = await gDeps.saveForBuild();
    } catch (AError) {
      gDeps.outputLine('Debug: save failed: ' + AError.message);
      LOk = false;
    }
    if (LSession !== gSession) {
      return;
    }
    if (!LOk) {
      endSession();
      return;
    }
    LPath = gDeps.activeTab().path;
    gDeps.clearOutput();
    gDeps.terminalReset();
    gDeps.clearProblems();
    gDeps.showPanel('output');
    gDeps.outputLine('Debug: ' + LPath);
    LResult = await PcDap.start();
    if (LSession !== gSession) {
      return;
    }
    if (!LResult || !LResult.ok) {
      gDeps.outputLine('Debug: ' + ((LResult && LResult.error) || 'the debugger did not start'));
      endSession();
      return;
    }
    try {
      await PcDap.request('initialize', {
        clientID: 'pcpp-editor',
        adapterID: 'pcpp',
        linesStartAt1: true,
        columnsStartAt1: true,
        pathFormat: 'path'
      });
      await launchProgram(LSession, LPath);
      if (LSession !== gSession) {
        return;
      }
      // A toggle from here on is sent by itself (sendLive): requests()
      // runs in this same turn, so nothing falls between the two
      gLive = true;
      LFiles = requests();
      for (LIndex = 0; LIndex < LFiles.length; LIndex++) {
        LBody = await PcDap.request('setBreakpoints', {
          source: { path: LFiles[LIndex].path },
          breakpoints: LFiles[LIndex].lines.map(function (ALine) { return { line: ALine }; })
        });
        if (LSession !== gSession) {
          return;
        }
        applyResponse(LFiles[LIndex].path, LFiles[LIndex].lines, LBody);
      }
      await PcDap.request('setExceptionBreakpoints', { filters: [] });
      if (LSession !== gSession) {
        return;
      }
      // Running before configurationDone goes out: a stop can come first.
      // The program's terminal comes to the front (a stop shows DEBUG)
      if (gState === 'starting') {
        setState('running');
        gDeps.setStatus('debugging');
        gDeps.showPanel('terminal');
      }
      await PcDap.request('configurationDone', {});
    } catch (AError) {
      if (LSession !== gSession) {
        return;
      }
      gDeps.outputLine('Debug: ' + AError.message);
      stopSession();
    }
  }

  // --- hover while stopped (e6g) -------------------------------------------

  // A designator ending at the line's end: names joined by '.' / '->'
  var PC_HOVER_CHAIN_RE = /[A-Za-z_]\w*(?:(?:\.|->)[A-Za-z_]\w*)*$/;

  // The designator a hover names: the name chain that ends at the word
  // under the mouse (hovering C in A.B->C gives A.B->C, hovering A gives
  // A); AWordEnd = the word's endColumn (1-based, exclusive). '' = none
  function hoverExpression(ALineText, AWordEnd) {
    var LHead = String(ALineText || '').substring(0, AWordEnd - 1);
    var LMatch = PC_HOVER_CHAIN_RE.exec(LHead);

    return LMatch ? LMatch[0] : '';
  }

  // A Markdown code fence longer than any backtick run in AText, so the
  // value can never close it
  function fenceOf(AText) {
    var LRuns = String(AText).match(/`+/g) || [];
    var LLongest = 0;
    var LIndex;

    for (LIndex = 0; LIndex < LRuns.length; LIndex++) {
      LLongest = Math.max(LLongest, LRuns[LIndex].length);
    }
    return new Array(Math.max(3, LLongest + 1) + 1).join('`');
  }

  // `expr: type = value` for the word under the mouse, evaluated in the
  // selected frame; only while stopped and only in that frame's file. A
  // refused evaluate (not a name there, a keyword, ...) shows nothing
  async function provideHover(AModel, APosition) {
    var LSession = gSession;
    var LStop = gStopSeq;
    var LFrame = gFrame;
    var LWord;
    var LExpression;
    var LBody;
    var LText;
    var LFence;

    if (gState !== 'stopped' || !LFrame || keyOfModel(AModel) !== keyOf(LFrame.path)) {
      return null;
    }
    LWord = AModel.getWordAtPosition(APosition);
    if (!LWord) {
      return null;
    }
    LExpression = hoverExpression(AModel.getLineContent(APosition.lineNumber), LWord.endColumn);
    if (LExpression === '') {
      return null;
    }
    try {
      LBody = await PcDap.request('evaluate', { expression: LExpression, frameId: LFrame.id, context: 'hover' });
    } catch (AError) {
      return null;
    }
    // The program ran on, or another frame was selected, meanwhile
    if (LSession !== gSession || LStop !== gStopSeq || LFrame !== gFrame) {
      return null;
    }
    LText = LExpression + (LBody.type ? ': ' + LBody.type : '') + ' = ' + LBody.result;
    LFence = fenceOf(LText);
    return {
      range: new gMonaco.Range(APosition.lineNumber, LWord.endColumn - LExpression.length,
        APosition.lineNumber, LWord.endColumn),
      contents: [{ value: LFence + 'pcpp\n' + LText + '\n' + LFence }]
    };
  }

  // The debug commands (menu, keys, toolbar); False = not a debug command
  function command(ACommand) {
    if (ACommand === 'debugStart') {
      if (gState === 'idle') {
        startSession();
      } else if (gState === 'stopped') {
        resume('continue');
      }
      return true;
    }
    if (ACommand === 'debugStepOver') {
      resume('next');
      return true;
    }
    if (ACommand === 'debugStepIn') {
      resume('stepIn');
      return true;
    }
    if (ACommand === 'debugStepOut') {
      resume('stepOut');
      return true;
    }
    if (ACommand === 'debugPause') {
      pause();
      return true;
    }
    if (ACommand === 'debugStop') {
      stopSession();
      return true;
    }
    return false;
  }

  // Pause a running program: the stop comes as a stopped event (reason
  // pause, onStopped). A refused pause is told; the program runs on
  function pause() {
    var LSession = gSession;

    if (gState !== 'running') {
      return;
    }
    PcDap.request('pause', { threadId: gThreadId }).catch(function (AError) {
      if (LSession === gSession && gState === 'running') {
        gDeps.outputLine('Debug: pause: ' + AError.message);
      }
    });
  }

  function onMouseDown(AEvent) {
    var LTarget = AEvent && AEvent.target;

    if (!LTarget || LTarget.type !== gMonaco.editor.MouseTargetType.GUTTER_GLYPH_MARGIN) {
      return;
    }
    if (!LTarget.position || (AEvent.event && !AEvent.event.leftButton)) {
      return;
    }
    toggleAt(gEditor.getModel(), LTarget.position.lineNumber);
  }

  // A gutter click: the mark toggles; during a session the file's set goes
  // to the adapter at once
  function toggleAt(AModel, ALine) {
    if (toggle(AModel, ALine)) {
      sendLive(modelPath(AModel));
    }
  }

  // --- the program's terminal (e7 t4) --------------------------------------

  // The session's program is there to take them: launched (running or
  // stopped; keys typed while stopped wait in its terminal)
  function hasProgram() {
    return (gState === 'running') || (gState === 'stopped');
  }

  // Keys typed in the TERMINAL tab (PcTerminal): to the program
  function terminalInput(AText) {
    if (!hasProgram()) {
      return;
    }
    PcDap.request('pcppTerminalInput', { text: AText }).catch(function (AError) {
      if (hasProgram()) {
        gDeps.outputLine('Debug: ' + AError.message);
      }
    });
  }

  // The TERMINAL tab's new size: the program's terminal follows
  function terminalResize(ACols, ARows) {
    if (!hasProgram()) {
      return;
    }
    PcDap.request('pcppTerminalResize', { cols: ACols, rows: ARows }).catch(function (AError) {
      if (hasProgram()) {
        gDeps.outputLine('Debug: ' + AError.message);
      }
    });
  }

  // ADeps (renderer.js): pathOfModel(model) -> tab path ('' none),
  // isSourcePath(path), activeTab(), openPath(path) (awaitable),
  // saveForBuild() (awaitable, False = not saved / not a .pcpp: reported),
  // output(text) (output panel + problem parse), outputLine(text),
  // clearOutput(), clearProblems(),
  // finishProblems() (the last partial line, markers), showPanel(name),
  // setStatus(text), setDebugState(state) (toolbar), buildBusy(),
  // getTarget(), debugHostFor(source) -> host ('' none), pickDebugHost(source)
  // -> { ok, canceled, host, error }, forgetDebugHost(source) (all awaitable),
  // terminalWrite(text), terminalReset(), terminalSize() -> { cols, rows }
  // (PcTerminal: the program's terminal)
  function init(AMonaco, AEditor, ADeps) {
    var LModels;
    var LIndex;

    gMonaco = AMonaco;
    gEditor = AEditor;
    gDeps = ADeps;
    gEditor.updateOptions({ glyphMargin: true });
    gEditor.onMouseDown(onMouseDown);
    // Subscribe first, then take the models that already exist
    gMonaco.editor.onDidCreateModel(onModelCreated);
    LModels = gMonaco.editor.getModels();
    for (LIndex = 0; LIndex < LModels.length; LIndex++) {
      onModelCreated(LModels[LIndex]);
    }
    PcDap.on('output', onOutput);
    PcDap.on('stopped', onStopped);
    PcDap.on('breakpoint', onBreakpointEvent);
    PcDap.on('exited', onExited);
    // The program is gone: the adapter is told to end (disconnect)
    PcDap.on('terminated', stopSession);
    PcDap.init({ onState: onDapState });
    PcDebugView.init({
      selectFrame: selectFrame,
      variables: variables,
      addWatch: addWatch,
      removeWatch: removeWatch
    });
    // Beside the LSP's hover: Monaco shows both (declaration, value)
    gMonaco.languages.registerHoverProvider('pcpp', { provideHover: provideHover });
  }

  return {
    init: init,
    command: command,
    terminalInput: terminalInput,
    terminalResize: terminalResize,
    isActive: isActive,
    state: function () { return gState; },
    // the frame the stop shows ({ id, path, line }, null = none)
    frame: function () { return gFrame; },
    // the frame the DEBUG panel selected (DAP frame id, 0 = none)
    selectedFrameId: function () { return gSelectedId; },
    watches: function () { return gWatches.slice(); },
    selectFrame: selectFrame,
    variables: variables,
    addWatch: addWatch,
    removeWatch: removeWatch,
    hoverExpression: hoverExpression,
    fenceOf: fenceOf,
    provideHover: provideHover,
    topSourceFrame: topSourceFrame,
    onModelCreated: onModelCreated,
    toggle: toggle,
    toggleAt: toggleAt,
    requests: requests,
    linesOf: linesOf,
    applyResponse: applyResponse,
    onBreakpointEvent: onBreakpointEvent,
    clearSessionMarks: clearSessionMarks
  };
})();
