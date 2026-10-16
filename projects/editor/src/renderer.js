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

  PaskalCPP Editor - renderer.

  Documents and tabs. One Monaco editor, one model per tab; switching a tab
  swaps the model and restores that tab's view state. A tab's identity is
  its file path (tab.path), never the model Uri: models are created without
  a Uri, so Save As keeps the model (and its undo history) and no two tabs
  can collide on a Uri. File access goes through window.host (preload.js).
  Dirty state is the model's alternative version id against the id at the
  last open/save, so undoing back to the saved text is clean.
*/
'use strict';

var PcEditor = (function () {
  var gMonaco = null;
  var gEditor = null;
  // Tab: { path, untitledName, model, viewState, savedVersion, diskText,
  // diskState } (diskText / diskState: onDiskChanges)
  var gTabs = [];
  var gActive = -1;
  var gUntitledCount = 0;
  // Session sync state (syncSession)
  var gSessionReady = false;
  var gLastSession = '';
  // The tab files main.js watches, as last sent (syncFileWatch), and the
  // queue that handles disk changes one at a time (onDiskChanges)
  var gLastWatch = '';
  var gDiskQueue = Promise.resolve();

  function baseName(APath) {
    var LParts = APath.split(/[\\/]/);
    return LParts[LParts.length - 1];
  }

  // Windows paths compare case-insensitively
  function samePath(AA, AB) {
    return !!AA && !!AB && AA.toLowerCase() === AB.toLowerCase();
  }

  function tabLabel(ATab) {
    return ATab.path ? baseName(ATab.path) : ATab.untitledName;
  }

  // The text differs from what was last loaded / saved
  function modelDirty(ATab) {
    return ATab.model.getAlternativeVersionId() !== ATab.savedVersion;
  }

  // Unsaved: edited, or the file was deleted on disk (a save recreates it)
  function isDirty(ATab) {
    return modelDirty(ATab) || ATab.diskState === 'deleted';
  }

  // What the tab strip adds to the label of a tab whose file moved on disk
  function diskSuffix(ATab) {
    if (ATab.diskState === 'deleted') {
      return ' (deleted)';
    }
    if (ATab.diskState === 'changed') {
      return ' (changed on disk)';
    }
    return '';
  }

  function anyDirty() {
    var LIndex;
    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      if (isDirty(gTabs[LIndex])) {
        return true;
      }
    }
    return false;
  }

  function activeTab() {
    return gTabs[gActive];
  }

  function findTab(APath) {
    var LIndex;
    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      if (samePath(gTabs[LIndex].path, APath)) {
        return LIndex;
      }
    }
    return -1;
  }

  // An untitled tab nobody has typed into; opening a file replaces it
  function isPristineUntitled(ATab) {
    return !ATab.path && ATab.model.getValueLength() === 0 && !isDirty(ATab);
  }

  function refresh() {
    var LList = [];
    var LIndex;
    var LTab = activeTab();
    var LDirty;

    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      LList.push({
        label: tabLabel(gTabs[LIndex]) + diskSuffix(gTabs[LIndex]),
        tooltip: (gTabs[LIndex].path || gTabs[LIndex].untitledName) + diskSuffix(gTabs[LIndex]),
        dirty: isDirty(gTabs[LIndex])
      });
    }
    PcShell.setTabs(LList, gActive, activateTab, closeTab);

    LDirty = isDirty(LTab);
    PcShell.setTitle((LDirty ? '* ' : '') + tabLabel(LTab) + ' - PaskalCPP Editor');
    PcShell.setFileState(LDirty, anyDirty(), !!LTab.path);
    // main.js guards the window close with this: any tab unsaved
    window.host.setDocState({ title: tabLabel(LTab), dirty: anyDirty() });
    PcExplorer.setActive(LTab.path);
    syncSession();
    syncFileWatch();
    // Every tab-set/path change passes through here: keep the server's
    // open documents in step
    syncLspDocs();
  }

  // Names the file tabs to main.js (file:watch) when the set changed, so a
  // change on disk reaches the tab (onDiskChanges)
  function syncFileWatch() {
    var LFiles = [];
    var LIndex;
    var LKey;

    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      if (gTabs[LIndex].path) {
        LFiles.push(gTabs[LIndex].path);
      }
    }
    LKey = JSON.stringify(LFiles);
    if (LKey !== gLastWatch) {
      gLastWatch = LKey;
      window.host.watchFiles(LFiles);
    }
  }

  // Disk changes from main.js: [{ path, exists }], handled one at a time in
  // arrival order (a prompt waits for the one before it)
  function onDiskChanges(AChanges) {
    var LIndex;

    for (LIndex = 0; LIndex < AChanges.length; LIndex++) {
      queueDiskChange(AChanges[LIndex].path, AChanges[LIndex].exists);
    }
  }

  function queueDiskChange(APath, AExists) {
    gDiskQueue = gDiskQueue.then(function () {
      return handleDiskChange(APath, AExists);
    }).catch(function (AErr) {
      PcShell.outputLine('File watch: ' + String(AErr && AErr.message ? AErr.message : AErr));
    });
  }

  // One file changed on disk. Nothing happens when the disk text is the text
  // this tab last loaded or wrote (diskText), so the editor's own saves are
  // silent. Otherwise:
  //   clean tab -> the new text replaces the old in one undoable edit,
  //                cursor and scroll kept, the tab stays clean
  //   dirty tab -> the tab is marked changed on disk and asks: reload (the
  //                edits are lost) or keep mine (the next save overwrites)
  //   deleted   -> the text stays, the tab is marked deleted and unsaved;
  //                a save recreates the file
  async function handleDiskChange(APath, AExists) {
    var LIndex = findTab(APath);
    var LTab;
    var LRes;

    if (LIndex < 0) {
      return;
    }
    LTab = gTabs[LIndex];
    if (!AExists) {
      if (LTab.diskState !== 'deleted') {
        LTab.diskState = 'deleted';
        LTab.diskText = null;
        // Name the files again: main.js stopped watching a directory that
        // went away and starts again once it is back (file:watch)
        gLastWatch = '';
        refresh();
      }
      return;
    }
    LRes = await window.host.readFile(LTab.path);
    // Unreadable now (mid-replace by another program): its next change
    // brings another notice. The tab may have closed during the read.
    if (!LRes.ok || gTabs.indexOf(LTab) < 0) {
      return;
    }
    if (LRes.text === LTab.diskText) {
      return;
    }
    if (!modelDirty(LTab)) {
      reloadTab(LTab, LRes.text);
      return;
    }
    LTab.diskText = LRes.text;
    LTab.diskState = 'changed';
    refresh();
    if (window.confirm(tabLabel(LTab) + ' changed on disk.\n\n' +
        'OK: reload it from disk (your unsaved edits are lost)\n' +
        'Cancel: keep your edits (the next save overwrites the file)')) {
      if (gTabs.indexOf(LTab) >= 0) {
        reloadTab(LTab, LRes.text);
      }
      return;
    }
    // Kept: unsaved until the next save, even if every edit is undone (the
    // saved version is the old disk text, no longer the file's)
    LTab.savedVersion = -1;
    refresh();
  }

  // Replaces the tab's text with the disk's in one undoable edit (undo brings
  // the old text back, as unsaved); cursor, selection and scroll are kept
  function reloadTab(ATab, AText) {
    var LActive = gEditor.getModel() === ATab.model;
    var LView = null;

    if (ATab.model.getValue() !== AText) {
      if (LActive) {
        LView = gEditor.saveViewState();
      }
      ATab.model.pushStackElement();
      ATab.model.pushEditOperations([], [{ range: ATab.model.getFullModelRange(), text: AText }], function () {
        return null;
      });
      ATab.model.pushStackElement();
      if (LActive) {
        gEditor.restoreViewState(LView);
      }
    }
    ATab.savedVersion = ATab.model.getAlternativeVersionId();
    ATab.diskText = AText;
    ATab.diskState = '';
    refresh();
  }

  // Reports the file tabs to main.js (state.json) when the set or the
  // active one changed. Off until start() has restored the previous
  // session, or the startup Untitled tab would overwrite the saved list.
  function syncSession() {
    var LFiles = [];
    var LIndex;
    var LActive;
    var LKey;

    if (!gSessionReady) {
      return;
    }
    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      if (gTabs[LIndex].path) {
        LFiles.push(gTabs[LIndex].path);
      }
    }
    LActive = activeTab().path || '';
    LKey = JSON.stringify([LFiles, LActive]);
    if (LKey !== gLastSession) {
      gLastSession = LKey;
      window.host.saveSession(LFiles, LActive);
    }
  }

  // A save passes the text it wrote (ADiskText) and the model version that
  // text is (AVersion), both taken BEFORE the write: an edit made while the
  // write was in flight is not on disk and must stay unsaved. Left out =
  // the tab's text as it is now (open, rename: already on disk).
  function markSaved(ATab, ADiskText, AVersion) {
    ATab.savedVersion = (AVersion !== undefined) ? AVersion : ATab.model.getAlternativeVersionId();
    ATab.diskText = (ADiskText !== undefined) ? ADiskText : ATab.model.getValue();
    ATab.diskState = '';
    refresh();
  }

  function activateTab(AIndex) {
    var LTab = gTabs[AIndex];
    var LPos;

    // Keep the outgoing tab's cursor/scroll/folding
    if (gActive >= 0 && gActive !== AIndex && gTabs[gActive]) {
      gTabs[gActive].viewState = gEditor.saveViewState();
    }
    gActive = AIndex;
    if (gEditor.getModel() !== LTab.model) {
      gEditor.setModel(LTab.model);
      gEditor.restoreViewState(LTab.viewState);
    }
    LPos = gEditor.getPosition();
    if (LPos) {
      PcShell.setCursor(LPos.lineNumber, LPos.column);
    }
    refresh();
    gEditor.focus();
  }

  // Every model carries a URI: file tabs the LSP document URI (parsed, so
  // Monaco routes definition / references / rename edits to it), untitled
  // tabs untitled:<name>. A model's URI is fixed at creation, so a tab whose
  // path changes gets a new model (retargetTab). Map a model back to its LSP
  // URI with lspUriOfModel, never model.uri.toString() (Monaco re-encodes).
  function documentUri(APath, AUntitledName) {
    if (APath) {
      return gMonaco.Uri.parse(PcLsp.pathToUri(APath));
    }
    return gMonaco.Uri.from({ scheme: 'untitled', path: AUntitledName });
  }

  // uri string (model.uri.toString()) -> LSP uri, for models loaded from
  // disk without a tab (peek into a closed file). A tab opening that file
  // adopts the model (takeModel).
  var gBackgroundModels = {};

  // PaskalCPP sources: .pcpp files, and untitled tabs (they save as .pcpp).
  // Only these get the 'pcpp' language and reach the LSP: one rule for both.
  function isSourcePath(APath) {
    return !APath || /\.pcpp$/i.test(APath);
  }

  // Monaco language for a tab's file: 'pcpp' for PaskalCPP sources, else the
  // language Monaco registers for the extension (python, json, ...), else
  // plain text
  function languageOf(APath) {
    var LExt;
    var LLangs;
    var LIndex;

    if (isSourcePath(APath)) {
      return 'pcpp';
    }
    LExt = (APath.match(/\.[^.\\\/]+$/) || [''])[0].toLowerCase();
    if (LExt) {
      LLangs = gMonaco.languages.getLanguages();
      for (LIndex = 0; LIndex < LLangs.length; LIndex++) {
        if (LLangs[LIndex].id !== 'pcpp' && (LLangs[LIndex].extensions || []).indexOf(LExt) >= 0) {
          return LLangs[LIndex].id;
        }
      }
    }
    return 'plaintext';
  }

  // A tab's model for AUri (the file APath, '' / null = untitled): adopts a
  // background model, else creates one, in APath's language.
  // Invariant: no other TAB holds AUri (findTab / doSaveAs guarantee it).
  function takeModel(AUri, AText, APath) {
    var LModel = gMonaco.editor.getModel(AUri);
    var LKey = AUri.toString();
    var LLanguage = languageOf(APath);

    if (LModel) {
      if (!gBackgroundModels[LKey]) {
        throw new Error('takeModel: ' + LKey + ' already belongs to a tab');
      }
      delete gBackgroundModels[LKey];
      if (LModel.getValue() !== AText) {
        LModel.setValue(AText);
      }
      if (LModel.getLanguageId() !== LLanguage) {
        gMonaco.editor.setModelLanguage(LModel, LLanguage);
      }
      return LModel;
    }
    return gMonaco.editor.createModel(AText, LLanguage, AUri);
  }

  function bindModel(ATab) {
    ATab.model.onDidChangeContent(refresh);
    ATab.model.onDidChangeContent(function (AEvent) {
      dropEditedErrorLines(ATab, AEvent);
    });
    ATab.model.onDidChangeContent(function () {
      scheduleLspChange(ATab);
    });
  }

  // Gives ATab a model for APath (Save As, a reused Untitled). The old
  // model's undo history goes with it: Monaco cannot change a model's URI.
  function retargetTab(ATab, APath, AText) {
    var LOld = ATab.model;
    var LView;

    clearTimeout(ATab.lspTimer);
    ATab.lspTimer = null;
    ATab.path = APath;
    ATab.untitledName = '';
    ATab.model = takeModel(documentUri(APath, ''), AText, APath);
    ATab.errorDecos = [];
    ATab.errorLines = [];
    bindModel(ATab);
    // Same text in the new model: keep cursor, selection and scroll
    if (gEditor.getModel() === LOld) {
      LView = gEditor.saveViewState();
      gEditor.setModel(ATab.model);
      gEditor.restoreViewState(LView);
    }
    LOld.dispose();
  }

  function addTab(APath, AText) {
    var LTab = {
      path: APath,
      untitledName: '',
      model: null,
      viewState: null,
      savedVersion: 0,
      // The text last loaded from or written to the file (null: none / the
      // file is gone) and '' | 'changed' | 'deleted' (handleDiskChange)
      diskText: APath ? AText : null,
      diskState: '',
      // Error-line tint decoration ids and their last known lines (applyErrorLines)
      errorDecos: [],
      errorLines: [],
      // URI the LSP server has this tab open under ('' = not open) and the
      // pending debounced didChange (syncLspDocs / scheduleLspChange)
      lspUri: '',
      lspTimer: null
    };
    if (!APath) {
      gUntitledCount++;
      LTab.untitledName = 'Untitled-' + gUntitledCount;
    }
    LTab.model = takeModel(documentUri(APath, LTab.untitledName), AText, APath);
    LTab.savedVersion = LTab.model.getAlternativeVersionId();
    bindModel(LTab);
    gTabs.push(LTab);
    // Problems from the last build that belong to this file
    applyMarkers(LTab);
    activateTab(gTabs.length - 1);
  }

  function openDocument(APath, AText) {
    var LIndex = findTab(APath);
    var LTab;

    if (LIndex >= 0) {
      activateTab(LIndex);
      return;
    }
    // A lone untouched Untitled tab is replaced instead of kept beside it
    if (gTabs.length === 1 && isPristineUntitled(gTabs[0])) {
      LTab = gTabs[0];
      retargetTab(LTab, APath, AText);
      gEditor.setPosition({ lineNumber: 1, column: 1 });
      markSaved(LTab);
      applyMarkers(LTab);
      gEditor.focus();
      return;
    }
    addTab(APath, AText);
  }

  function closeTab(AIndex) {
    var LTab = gTabs[AIndex];

    if (isDirty(LTab) && !window.confirm('Discard unsaved changes to ' + tabLabel(LTab) + '?')) {
      return;
    }
    removeTab(AIndex);
  }

  // Removes without asking. The editor is moved to another model before
  // the closed one is disposed; the last tab closing leaves a new Untitled.
  function removeTab(AIndex) {
    var LTab = gTabs[AIndex];

    gTabs.splice(AIndex, 1);
    if (gTabs.length === 0) {
      gActive = -1;
      addTab(null, '');
    } else if (AIndex === gActive) {
      gActive = -1;
      activateTab(Math.min(AIndex, gTabs.length - 1));
    } else {
      if (AIndex < gActive) {
        gActive--;
      }
      refresh();
    }
    LTab.model.dispose();
  }

  function showError(AAction, ARes) {
    if (ARes && !ARes.ok && !ARes.canceled) {
      window.alert(AAction + ' failed: ' + (ARes.error || 'unknown error'));
    }
  }

  async function doOpen() {
    var LRes = await window.host.openFile();
    if (LRes.ok) {
      openDocument(LRes.path, LRes.text);
    } else {
      showError('Open', LRes);
    }
  }

  // Explorer click: an open tab is just shown, otherwise the file is read
  async function openPath(APath) {
    var LIndex = findTab(APath);
    var LRes;

    if (LIndex >= 0) {
      activateTab(LIndex);
      return;
    }
    LRes = await window.host.readFile(APath);
    if (LRes.ok) {
      openDocument(LRes.path, LRes.text);
    } else {
      showError('Open', LRes);
    }
  }

  // Several files in turn (an open one is just shown); the last is active
  async function openPaths(APaths) {
    var LIndex;

    for (LIndex = 0; LIndex < APaths.length; LIndex++) {
      await openPath(APaths[LIndex]);
    }
  }

  // Adds a folder root; main.js returns the whole list either way
  async function doOpenFolder() {
    var LRes = await window.host.openFolder();
    if (LRes.ok) {
      PcExplorer.setFolders(LRes.folders);
    }
  }

  // Open tabs stay open: they are files, not folders
  async function doCloseFolder(APath) {
    var LRes = await window.host.closeFolder(APath);
    PcExplorer.setFolders(LRes.folders);
  }

  async function doCloseAllFolders() {
    var LRes = await window.host.closeAllFolders();
    PcExplorer.setFolders(LRes.folders);
  }

  // AOn = true / false, or null = flip (File > Show Examples); main.js owns
  // the remembered setting and the menu tick
  async function doShowExamples(AOn) {
    var LRes = await window.host.showExamples(AOn);
    PcExplorer.setExamples(LRes.ok ? LRes.path : '');
  }

  async function doSaveAs() {
    var LTab = activeTab();
    var LRes;
    var LOther;
    var LText;
    var LVersion;

    await formatBeforeSave(LTab);
    LText = LTab.model.getValue();
    LVersion = LTab.model.getAlternativeVersionId();
    LRes = await window.host.saveFileAs(LText, LTab.path || (LTab.untitledName + '.pcpp'));
    if (!LRes.ok) {
      showError('Save', LRes);
      return false;
    }
    // Another tab showing the file just overwritten is stale: drop it
    // first, its model holds the URI this tab's new model takes
    LOther = findOtherTab(LTab, LRes.path);
    if (LOther >= 0) {
      removeTab(LOther);
    }
    if (LTab.path !== LRes.path) {
      // A new model, so the version taken before the write means nothing
      // in it: it holds the tab's text as it is now, saved only if that is
      // the text written (-1 = never matches: an edit made during the write)
      retargetTab(LTab, LRes.path, LTab.model.getValue());
      LVersion = (LTab.model.getValue() === LText) ? LTab.model.getAlternativeVersionId() : -1;
    }
    markSaved(LTab, LText, LVersion);
    return true;
  }

  // Rename: the file is renamed (or moved) on disk and the tab follows it.
  // Unsaved edits are saved first so the renamed file matches the tab.
  async function doRename() {
    var LTab = activeTab();
    var LRes;
    var LOther;

    if (!LTab.path) {
      return false;
    }
    if (isDirty(LTab) && !(await doSave())) {
      return false;
    }
    LRes = await window.host.renameFile(LTab.path);
    if (!LRes.ok) {
      showError('Rename', LRes);
      return false;
    }
    if (samePath(LTab.path, LRes.path)) {
      return true;
    }
    // A tab showing the file just replaced is stale: drop it first, its
    // model holds the URI this tab's new model takes
    LOther = findOtherTab(LTab, LRes.path);
    if (LOther >= 0) {
      removeTab(LOther);
    }
    retargetTab(LTab, LRes.path, LTab.model.getValue());
    markSaved(LTab);
    return true;
  }

  function findOtherTab(ATab, APath) {
    var LIndex;
    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      if (gTabs[LIndex] !== ATab && samePath(gTabs[LIndex].path, APath)) {
        return LIndex;
      }
    }
    return -1;
  }

  async function doSave() {
    var LTab = activeTab();
    var LRes;
    var LText;
    var LVersion;

    if (!LTab.path) {
      return await doSaveAs();
    }
    await formatBeforeSave(LTab);
    LText = LTab.model.getValue();
    LVersion = LTab.model.getAlternativeVersionId();
    LRes = await window.host.saveFile(LTab.path, LText);
    if (LRes.ok) {
      markSaved(LTab, LText, LVersion);
      return true;
    }
    showError('Save', LRes);
    return false;
  }

  // The compiler reads from disk: the active tab must be a saved .pcpp, and
  // every other dirty file-backed tab is saved too, or an edited unit open in
  // another tab would build stale. False = build must not start.
  // AWhat names the caller in its report ('Build', 'Debug')
  async function saveForBuild(AWhat) {
    var LTab = activeTab();

    if (!LTab.path || isDirty(LTab)) {
      if (!(await doSave())) {
        return false;
      }
    }
    // Saved above, so the path is set; a file path must be a PaskalCPP source
    if (!LTab.path || !isSourcePath(LTab.path)) {
      PcShell.showPanel('output');
      PcShell.outputLine(AWhat + ': the active file is not a .pcpp source: ' + LTab.path);
      return false;
    }
    return await saveDirtyFileTabs(LTab);
  }

  // Writes every dirty tab that has a file, except ASkip (null = none).
  // False = a save failed (reported); the remaining tabs were not tried.
  async function saveDirtyFileTabs(ASkip) {
    var LIndex;
    var LTab;
    var LRes;
    var LText;
    var LVersion;

    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      LTab = gTabs[LIndex];
      if (LTab !== ASkip && LTab.path && isDirty(LTab)) {
        await formatBeforeSave(LTab);
        LText = LTab.model.getValue();
        LVersion = LTab.model.getAlternativeVersionId();
        LRes = await window.host.saveFile(LTab.path, LText);
        if (!LRes.ok) {
          showError('Save', LRes);
          return false;
        }
        markSaved(LTab, LText, LVersion);
      }
    }
    return true;
  }

  // Save All: file tabs are written in place, then each dirty Untitled tab
  // is shown and gets a Save As dialog (Cancel stops there). The tab that
  // was active is shown again at the end.
  async function doSaveAll() {
    var LActive = activeTab();
    var LUntitled = [];
    var LIndex;

    if (!(await saveDirtyFileTabs(null))) {
      return false;
    }
    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      if (!gTabs[LIndex].path && isDirty(gTabs[LIndex])) {
        LUntitled.push(gTabs[LIndex]);
      }
    }
    for (LIndex = 0; LIndex < LUntitled.length; LIndex++) {
      // A Save As over another open file removes that tab: skip if gone
      if (gTabs.indexOf(LUntitled[LIndex]) < 0) {
        continue;
      }
      activateTab(gTabs.indexOf(LUntitled[LIndex]));
      if (!(await doSaveAs())) {
        return false;
      }
    }
    LIndex = gTabs.indexOf(LActive);
    if (LIndex >= 0) {
      activateTab(LIndex);
    }
    return true;
  }

  // True while pcpp.exe is running (build, or build + game with -r)
  var gBuildActive = false;
  var gBuildRun = false;
  // True while a Run's program is connected to the TERMINAL tab (run:connect
  // to build:exit): the tab's keys and size are its; otherwise the debug
  // session's
  var gRunTerminal = false;

  // Problems from the last build. Compiler line format (research R1):
  //   [SEV] <abs path, forward slashes>(<line>,<col>) <CODE>: <message>
  var PC_PROBLEM_RE = /^\[(HINT|WARN|ERROR|FATAL)\]\s+(.+)\((\d+),(\d+)\)\s+([A-Z]+\d+):\s+(.*)$/;
  var PC_MARKER_OWNER = 'pc-build';
  var gProblems = [];
  // Output text after the last newline, completed by the next chunk
  var gLineBuf = '';

  function parseProblemLine(ALine) {
    // A bare \r redraws the line: only the text after the last one is shown
    var LText = ALine.replace(/\r+$/, '');
    var LMatch;
    LText = LText.slice(LText.lastIndexOf('\r') + 1);
    LMatch = PC_PROBLEM_RE.exec(LText);
    // With -r the compile phase ends at this line and the game starts
    if (gBuildRun && LText.indexOf('Build succeeded.') >= 0) {
      PcShell.setBuildState('running');
    }
    if (!LMatch) {
      return;
    }
    gProblems.push({
      sev: LMatch[1],
      // Tabs hold Windows paths; the compiler prints forward slashes
      path: LMatch[2].replace(/\//g, '\\'),
      line: parseInt(LMatch[3], 10),
      // pcpp prints the editor's column (UTF-16 units, as Monaco counts)
      col: parseInt(LMatch[4], 10),
      code: LMatch[5],
      msg: LMatch[6]
    });
  }

  function feedProblemText(AText) {
    var LLines = (gLineBuf + AText).split('\n');
    var LIndex;
    gLineBuf = LLines.pop();
    for (LIndex = 0; LIndex < LLines.length; LIndex++) {
      parseProblemLine(LLines[LIndex]);
    }
  }

  function markerSeverity(ASev) {
    if (ASev === 'ERROR' || ASev === 'FATAL') {
      return gMonaco.MarkerSeverity.Error;
    }
    if (ASev === 'WARN') {
      return gMonaco.MarkerSeverity.Warning;
    }
    return gMonaco.MarkerSeverity.Hint;
  }

  // Squiggles for one tab from gProblems. Called for every open tab after a
  // build and for each tab opened later, so a file opened after the build
  // still shows its problems.
  function applyMarkers(ATab) {
    var LMarkers = [];
    var LIndex;
    var LItem;

    for (LIndex = 0; LIndex < gProblems.length; LIndex++) {
      LItem = gProblems[LIndex];
      if (samePath(LItem.path, ATab.path)) {
        LMarkers.push({
          severity: markerSeverity(LItem.sev),
          message: LItem.code ? LItem.code + ': ' + LItem.msg : LItem.msg,
          startLineNumber: LItem.line,
          startColumn: LItem.col,
          endLineNumber: LItem.line,
          // Cover the word at the column; fall back to one character
          endColumn: markerEndColumn(ATab.model, LItem.line, LItem.col)
        });
      }
    }
    gMonaco.editor.setModelMarkers(ATab.model, PC_MARKER_OWNER, LMarkers);
    applyErrorLines(ATab);
  }

  // Delphi-style tint on every ERROR/FATAL line of this tab, plus a mark in
  // the scrollbar ruler. Model decorations, so inactive tabs keep theirs.
  // A tinted line clears when edited (dropEditedErrorLines) or on the next
  // build; the squiggle stays until the next build.
  function applyErrorLines(ATab) {
    var LDecos = [];
    var LSeen = {};
    var LIndex;
    var LItem;
    var LRuler = getComputedStyle(document.documentElement).getPropertyValue('--pc-error').trim();

    for (LIndex = 0; LIndex < gProblems.length; LIndex++) {
      LItem = gProblems[LIndex];
      if ((LItem.sev === 'ERROR' || LItem.sev === 'FATAL') && samePath(LItem.path, ATab.path) &&
          LItem.line >= 1 && LItem.line <= ATab.model.getLineCount() && !LSeen[LItem.line]) {
        // One decoration per line, however many errors share it
        LSeen[LItem.line] = true;
        LDecos.push({
          range: new gMonaco.Range(LItem.line, 1, LItem.line, 1),
          options: {
            isWholeLine: true,
            className: 'pc-error-line',
            stickiness: gMonaco.editor.TrackedRangeStickiness.NeverGrowsWhenTypingAtEdges,
            overviewRuler: { color: LRuler, position: gMonaco.editor.OverviewRulerLane.Right }
          }
        });
      }
    }
    ATab.errorDecos = ATab.model.deltaDecorations(ATab.errorDecos, LDecos);
    rememberErrorLines(ATab);
  }

  // Change events report ranges in PRE-edit line numbers, while decoration
  // ranges are already POST-edit. Each tint's line is recorded after every
  // update, so the next edit is compared against where the line was.
  function rememberErrorLines(ATab) {
    var LIndex;
    var LRange;
    ATab.errorLines = [];
    for (LIndex = 0; LIndex < ATab.errorDecos.length; LIndex++) {
      LRange = ATab.model.getDecorationRange(ATab.errorDecos[LIndex]);
      ATab.errorLines.push(LRange ? LRange.startLineNumber : -1);
    }
  }

  // Content-change listener: an edit touching a tinted line clears its tint
  function dropEditedErrorLines(ATab, AEvent) {
    var LKeep = [];
    var LDrop = [];
    var LIndex;
    var LChange;
    var LLine;
    var LHit;

    if (ATab.errorDecos.length === 0) {
      return;
    }
    for (LIndex = 0; LIndex < ATab.errorDecos.length; LIndex++) {
      LLine = ATab.errorLines[LIndex];
      LHit = LLine < 1;
      for (LChange = 0; !LHit && LChange < AEvent.changes.length; LChange++) {
        LHit = AEvent.changes[LChange].range.startLineNumber <= LLine &&
          AEvent.changes[LChange].range.endLineNumber >= LLine;
      }
      if (LHit) {
        LDrop.push(ATab.errorDecos[LIndex]);
      } else {
        LKeep.push(ATab.errorDecos[LIndex]);
      }
    }
    if (LDrop.length > 0) {
      ATab.model.deltaDecorations(LDrop, []);
      ATab.errorDecos = LKeep;
    }
    // Survivors may have moved (lines inserted/deleted above them)
    rememberErrorLines(ATab);
  }

  function markerEndColumn(AModel, ALine, ACol) {
    var LWord;
    if (ALine < 1 || ALine > AModel.getLineCount()) {
      return ACol + 1;
    }
    LWord = AModel.getWordAtPosition({ lineNumber: ALine, column: ACol });
    if (LWord && LWord.endColumn > ACol) {
      return LWord.endColumn;
    }
    return ACol + 1;
  }

  function countProblems(AList, ASevs) {
    var LCount = 0;
    var LIndex;
    for (LIndex = 0; LIndex < AList.length; LIndex++) {
      if (ASevs.indexOf(AList[LIndex].sev) >= 0) {
        LCount++;
      }
    }
    return LCount;
  }

  // PROBLEMS = build items + LSP items. A build item the LSP also reports
  // (same file, line, column, code) is listed once, as the live LSP item.
  function allProblems() {
    var LLsp = [];
    var LList = [];
    var LUri;
    var LIndex;
    var LOther;
    var LDup;

    for (LUri in gLspProblems) {
      LLsp = LLsp.concat(gLspProblems[LUri]);
    }
    for (LIndex = 0; LIndex < gProblems.length; LIndex++) {
      LDup = false;
      for (LOther = 0; !LDup && LOther < LLsp.length; LOther++) {
        LDup = samePath(LLsp[LOther].path, gProblems[LIndex].path) &&
          LLsp[LOther].line === gProblems[LIndex].line &&
          LLsp[LOther].col === gProblems[LIndex].col &&
          LLsp[LOther].code === gProblems[LIndex].code;
      }
      if (!LDup) {
        LList.push(gProblems[LIndex]);
      }
    }
    return LList.concat(LLsp);
  }

  function publishProblems() {
    var LAll = allProblems();
    var LIndex;
    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      applyMarkers(gTabs[LIndex]);
      applyLspMarkers(gTabs[LIndex]);
    }
    PcShell.setProblems(LAll, jumpToProblem);
    PcShell.setCounts(countProblems(LAll, ['ERROR', 'FATAL']), countProblems(LAll, ['WARN']));
  }

  function clearProblems() {
    gProblems = [];
    gLineBuf = '';
    publishProblems();
  }

  // LSP documents: only tabs with a path (the server resolves imports from
  // the file's folder). Full sync, didChange debounced per tab.
  var PC_LSP_MARKER_OWNER = 'pc-lsp';
  var PC_LSP_CHANGE_DELAY = 300;
  // uri -> tab, for every document the server has open
  var gLspOpen = {};
  // uri -> [{ path, line, col, endLine, endCol, sev, code, msg }]
  var gLspProblems = {};

  function lspOpen(ATab, AUri) {
    ATab.lspUri = AUri;
    gLspOpen[AUri] = ATab;
    PcLsp.notify('textDocument/didOpen', {
      textDocument: {
        uri: AUri,
        languageId: 'pcpp',
        version: ATab.model.getVersionId(),
        text: ATab.model.getValue()
      }
    });
  }

  function lspClose(AUri) {
    var LTab = gLspOpen[AUri];
    delete gLspOpen[AUri];
    if (LTab && LTab.lspUri === AUri) {
      LTab.lspUri = '';
      clearTimeout(LTab.lspTimer);
      LTab.lspTimer = null;
    }
    delete gLspProblems[AUri];
    PcLsp.notify('textDocument/didClose', { textDocument: { uri: AUri } });
  }

  // Opens new/renamed tabs, closes documents whose tab is gone or renamed;
  // republishes PROBLEMS when a closed document took problems with it
  function syncLspDocs() {
    var LLive = {};
    var LIndex;
    var LTab;
    var LUri;
    var LDropped = false;

    if (!PcLsp.isReady()) {
      return;
    }
    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      LTab = gTabs[LIndex];
      // Only Pascal sources go to the server (isSourcePath)
      LUri = LTab.path && isSourcePath(LTab.path) ? PcLsp.pathToUri(LTab.path) : '';
      if (LTab.lspUri !== LUri) {
        // Save As / a reused Untitled: the old document goes first
        if (LTab.lspUri) {
          LDropped = LDropped || !!gLspProblems[LTab.lspUri];
          lspClose(LTab.lspUri);
        }
        if (LUri) {
          lspOpen(LTab, LUri);
        }
      }
      if (LUri) {
        LLive[LUri] = true;
      }
    }
    for (LUri in gLspOpen) {
      if (!LLive[LUri]) {
        LDropped = LDropped || !!gLspProblems[LUri];
        lspClose(LUri);
      }
    }
    if (LDropped) {
      publishProblems();
    }
  }

  function scheduleLspChange(ATab) {
    if (!ATab.lspUri) {
      return;
    }
    clearTimeout(ATab.lspTimer);
    ATab.lspTimer = setTimeout(function () {
      ATab.lspTimer = null;
      sendLspChange(ATab);
    }, PC_LSP_CHANGE_DELAY);
  }

  function sendLspChange(ATab) {
    // The tab may have been closed or renamed while waiting
    if (!ATab.lspUri || gLspOpen[ATab.lspUri] !== ATab || ATab.model.isDisposed()) {
      return;
    }
    PcLsp.notify('textDocument/didChange', {
      textDocument: { uri: ATab.lspUri, version: ATab.model.getVersionId() },
      contentChanges: [{ text: ATab.model.getValue() }]
    });
  }

  // Sends a pending debounced didChange now, so a request that follows
  // (hover, completion, ...) is answered against the text on screen
  function flushLspChange(AModel) {
    var LTab = tabOfModel(AModel);

    if (LTab && LTab.lspTimer) {
      clearTimeout(LTab.lspTimer);
      LTab.lspTimer = null;
      sendLspChange(LTab);
    }
  }

  // Every tab's pending didChange (for a request that belongs to no
  // single document: workspace symbols, call hierarchy)
  function flushAllLspChanges() {
    var LIndex;

    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      flushLspChange(gTabs[LIndex].model);
    }
  }

  function tabOfModel(AModel) {
    var LIndex;

    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      if (gTabs[LIndex].model === AModel) {
        return gTabs[LIndex];
      }
    }
    return null;
  }

  // The LSP document URI of a tab or background model ('' = none: untitled,
  // or a tab the server does not have open yet)
  function lspUriOfModel(AModel) {
    var LTab = tabOfModel(AModel);

    if (LTab) {
      return LTab.lspUri;
    }
    return gBackgroundModels[AModel.uri.toString()] || '';
  }

  function modelOfLspUri(ALspUri) {
    return gMonaco.editor.getModel(gMonaco.Uri.parse(ALspUri));
  }

  // Makes sure every LSP uri in AUris has a model (peek / references into
  // closed files): tabs already do, other files are read from disk into a
  // background model, refreshed from disk on every call
  async function loadModels(AUris) {
    var LIndex;
    var LUri;
    var LModel;
    var LRes;

    for (LIndex = 0; LIndex < AUris.length; LIndex++) {
      LUri = AUris[LIndex];
      LModel = modelOfLspUri(LUri);
      if (LModel && !gBackgroundModels[LModel.uri.toString()]) {
        continue;
      }
      LRes = await window.host.readFile(PcLsp.uriToPath(LUri));
      if (!LRes.ok) {
        continue;
      }
      // A tab may have opened the file while the read was pending
      LModel = modelOfLspUri(LUri);
      if (LModel && !gBackgroundModels[LModel.uri.toString()]) {
        continue;
      }
      if (LModel) {
        if (LModel.getValue() !== LRes.text) {
          LModel.setValue(LRes.text);
        }
      } else {
        LModel = gMonaco.editor.createModel(LRes.text, 'pcpp', gMonaco.Uri.parse(LUri));
        gBackgroundModels[LModel.uri.toString()] = LUri;
      }
    }
  }

  // Opens every file in AUris as a tab (rename edits files as dirty tabs,
  // the user saves them), then returns to the tab that was active
  async function openTabs(AUris) {
    var LActive = activeTab();
    var LIndex;
    var LPath;

    for (LIndex = 0; LIndex < AUris.length; LIndex++) {
      LPath = PcLsp.uriToPath(AUris[LIndex]);
      if (findTab(LPath) < 0) {
        await openPath(LPath);
      }
    }
    LIndex = gTabs.indexOf(LActive);
    if (LIndex >= 0) {
      activateTab(LIndex);
    }
  }

  // Editor opener: a definition / reference in another file opens (or
  // shows) its tab and reveals the target
  async function openAt(ALspUri, ASelection) {
    var LPath = PcLsp.uriToPath(ALspUri);
    var LSel = ASelection;

    await openPath(LPath);
    if (findTab(LPath) !== gActive || !LSel) {
      return;
    }
    if (LSel.startLineNumber === undefined) {
      LSel = new gMonaco.Range(LSel.lineNumber, LSel.column, LSel.lineNumber, LSel.column);
    }
    gEditor.setSelection(LSel);
    gEditor.revealRangeInCenterIfOutsideViewport(LSel);
    gEditor.focus();
  }

  // Monaco resource -> LSP uri of the file it shows ('' = untitled / none).
  // Providers load a model for every target before returning it, so the
  // opener always finds one.
  function lspUriOfResource(AResource) {
    var LModel = gMonaco.editor.getModel(AResource);
    var LTab;

    if (!LModel) {
      return '';
    }
    LTab = tabOfModel(LModel);
    if (LTab) {
      return LTab.path && isSourcePath(LTab.path) ? PcLsp.pathToUri(LTab.path) : '';
    }
    return gBackgroundModels[LModel.uri.toString()] || '';
  }

  function lspSeverity(ASeverity) {
    if (ASeverity === 1) {
      return 'ERROR';
    }
    if (ASeverity === 2) {
      return 'WARN';
    }
    return 'HINT';
  }

  // window/showMessage (a formatting refusal, say): the output panel, the
  // editor's own message area
  function onLspShowMessage(AType, AMessage) {
    PcShell.showPanel('output');
    PcShell.outputLine('LSP: ' + AMessage);
  }

  // Format on save (settings.json format.formatOnSave): a Pascal model is
  // formatted before its text is written
  async function formatBeforeSave(ATab) {
    if (gFormat && gFormat.formatOnSave && ATab.model.getLanguageId() === 'pcpp') {
      await PcProviders.formatModel(ATab.model);
    }
  }

  function onLspDiagnostics(AUri, ADiagnostics) {
    var LTab = gLspOpen[AUri];
    var LList = [];
    var LIndex;
    var LDiag;

    // Late diagnostics for a document already closed
    if (!LTab) {
      if (gLspProblems[AUri]) {
        delete gLspProblems[AUri];
        publishProblems();
      }
      return;
    }
    for (LIndex = 0; LIndex < ADiagnostics.length; LIndex++) {
      LDiag = ADiagnostics[LIndex];
      // LSP is 0-based with an exclusive end; Monaco and PROBLEMS are 1-based
      LList.push({
        path: LTab.path,
        line: LDiag.range.start.line + 1,
        col: LDiag.range.start.character + 1,
        endLine: LDiag.range.end.line + 1,
        endCol: LDiag.range.end.character + 1,
        sev: lspSeverity(LDiag.severity),
        code: LDiag.code !== undefined ? String(LDiag.code) : '',
        msg: LDiag.message
      });
    }
    gLspProblems[AUri] = LList;
    publishProblems();
  }

  // Squiggles from the server, exact ranges, owner separate from the build
  function applyLspMarkers(ATab) {
    var LList = ATab.lspUri ? (gLspProblems[ATab.lspUri] || []) : [];
    var LMarkers = [];
    var LIndex;
    var LItem;
    var LEndCol;

    for (LIndex = 0; LIndex < LList.length; LIndex++) {
      LItem = LList[LIndex];
      LEndCol = LItem.endCol;
      // An empty range would draw nothing: widen it to the word
      if (LItem.endLine === LItem.line && LEndCol <= LItem.col) {
        LEndCol = markerEndColumn(ATab.model, LItem.line, LItem.col);
      }
      LMarkers.push({
        severity: markerSeverity(LItem.sev),
        message: LItem.code ? LItem.code + ': ' + LItem.msg : LItem.msg,
        startLineNumber: LItem.line,
        startColumn: LItem.col,
        endLineNumber: LItem.endLine,
        endColumn: LEndCol
      });
    }
    gMonaco.editor.setModelMarkers(ATab.model, PC_LSP_MARKER_OWNER, LMarkers);
  }

  // A (re)started server knows no documents: open every tab again, then
  // (re)register the providers from its capabilities - registering makes
  // Monaco ask again (semantic tokens, folding), so documents come first
  function onLspReady(ACaps) {
    var LIndex;
    gLspOpen = {};
    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      gTabs[LIndex].lspUri = '';
    }
    syncLspDocs();
    // The instant colouring takes PaskalCPP's words from the server
    PcLang.setWords(ACaps && ACaps.experimental && ACaps.experimental.pcppWords);
    PcProviders.install(ACaps);
  }

  // Server gone: its documents and diagnostics are gone with it
  function onLspDown() {
    var LIndex;
    for (LIndex = 0; LIndex < gTabs.length; LIndex++) {
      clearTimeout(gTabs[LIndex].lspTimer);
      gTabs[LIndex].lspTimer = null;
      gTabs[LIndex].lspUri = '';
    }
    gLspOpen = {};
    gLspProblems = {};
    publishProblems();
  }

  // Open (or show) the problem's file and put the cursor on it
  async function jumpToProblem(AItem) {
    var LTab;
    await openPath(AItem.path);
    LTab = activeTab();
    if (!LTab || !samePath(LTab.path, AItem.path)) {
      return;
    }
    gEditor.setPosition({ lineNumber: AItem.line, column: AItem.col });
    gEditor.revealPositionInCenter({ lineNumber: AItem.line, column: AItem.col });
    gEditor.focus();
  }

  function firstError() {
    var LIndex;
    for (LIndex = 0; LIndex < gProblems.length; LIndex++) {
      if (gProblems[LIndex].sev === 'ERROR' || gProblems[LIndex].sev === 'FATAL') {
        return gProblems[LIndex];
      }
    }
    return null;
  }

  async function doBuild(ARun) {
    var LTab;
    var LRes;
    var LSize;

    if (gBuildActive) {
      return;
    }
    // A debug session builds into the same output folder (main.js refuses
    // too); refused here before the session's output is cleared
    if (PcDebug.isActive()) {
      PcShell.outputLine('Build: a debug session is active: stop it first (Shift+F5).');
      return;
    }
    // Claimed before any await, so a second Build/Run during the saves is a no-op
    gBuildActive = true;
    try {
      LRes = await saveForBuild('Build');
    } catch (AError) {
      PcShell.outputLine('Build: save failed: ' + AError.message);
      LRes = false;
    }
    if (!LRes) {
      gBuildActive = false;
      return;
    }
    LTab = activeTab();
    PcShell.clearOutput();
    clearProblems();
    PcShell.showPanel('output');
    // Busy BEFORE the request: output and even build:exit (instant failure)
    // can arrive ahead of the invoke reply
    gBuildRun = ARun;
    PcShell.setBusy(true);
    PcShell.setBuildState('building');
    // A Run's program starts at the TERMINAL tab's size
    LSize = PcTerminal.size();
    LRes = await window.host.buildStart({
      file: LTab.path,
      mode: PcShell.getBuildMode(),
      target: PcShell.getTarget(),
      run: ARun,
      cols: LSize.cols,
      rows: LSize.rows
    });
    if (!LRes.ok) {
      // Nothing was spawned, so no build:exit will follow
      gBuildActive = false;
      gBuildRun = false;
      PcShell.setBusy(false);
      PcShell.outputLine(LRes.error);
      PcShell.setBuildState('failed');
    }
  }

  function doStop() {
    if (gBuildActive) {
      window.host.buildStop();
    }
  }

  function onBuildOutput(AText) {
    PcShell.output(AText);
    feedProblemText(AText);
  }

  // A Run's program started on the TERMINAL tab: an empty terminal, in front
  function onRunConnect() {
    gRunTerminal = true;
    PcTerminal.reset();
    PcShell.showPanel('terminal');
    PcTerminal.focus();
  }

  // The TERMINAL tab's keys and size: a Run's program while one runs, else
  // the debug session's (each ignores them without a program)
  function onTerminalInput(AText) {
    if (gRunTerminal) {
      window.host.runInput(AText);
    } else {
      PcDebug.terminalInput(AText);
    }
  }

  function onTerminalResize(ACols, ARows) {
    if (gRunTerminal) {
      window.host.runResize(ACols, ARows);
    } else {
      PcDebug.terminalResize(ACols, ARows);
    }
  }

  // Status bar LSP slot: state, plus why when there is a reason
  function showLspState(AState) {
    if (AState.detail) {
      PcShell.setLspState(AState.state + ' (' + AState.detail + ')');
    } else {
      PcShell.setLspState(AState.state);
    }
  }

  // The compiler's output has ended (a build, a debug session's build): a
  // last line without a trailing newline is still a line; then the markers
  function finishProblemText() {
    if (gLineBuf.length > 0) {
      parseProblemLine(gLineBuf);
      gLineBuf = '';
    }
    publishProblems();
  }

  // A build (Build, Run or a debug session's) writes files other open
  // documents' directives name (a dll's output, a library, an @outputpath
  // folder): the server checks every open buffer again, so its reports follow
  // the disk (a stale SM0105 / SM0106 after the dll was built)
  function notifyDiskChanged() {
    if (PcLsp.isReady()) {
      PcLsp.notify('workspace/didChangeWatchedFiles', { changes: [] });
    }
  }

  // The debugger's build ended: its problem text, then the disk refresh
  function finishDebugBuild() {
    finishProblemText();
    notifyDiskChanged();
  }

  function onBuildExit(AInfo) {
    var LState;
    var LError;

    gBuildActive = false;
    gBuildRun = false;
    gRunTerminal = false;
    PcShell.setBusy(false);
    finishProblemText();
    if (AInfo.stopped) {
      LState = 'stopped';
    } else if (AInfo.code === 0) {
      LState = 'ok';
    } else {
      LState = 'failed (exit ' + AInfo.code + ')';
    }
    PcShell.setBuildState(LState);
    PcShell.outputLine('[' + LState + ']');
    notifyDiskChanged();
    // A failed build takes you to its first error
    LError = firstError();
    if (!AInfo.stopped && AInfo.code !== 0 && LError) {
      jumpToProblem(LError);
    }
  }

  // Ctrl+T: pick a top-level symbol of the open documents (and the units
  // they import) and jump to it
  function doGotoSymbol() {
    PcQuickPick.open({
      placeholder: 'Go to symbol in workspace',
      source: gotoSymbolSource,
      onPick: function (AEntry) {
        openAt(AEntry.uri, AEntry.range);
      },
      onClose: function () {
        gEditor.focus();
      }
    });
  }

  // Quick pick source: { entries } or { message }
  async function gotoSymbolSource(AQuery) {
    var LCaps = PcLsp.capabilities();
    var LSymbols;
    var LEntries = [];
    var LIndex;

    if (!PcLsp.isReady() || !LCaps || !LCaps.workspaceSymbolProvider) {
      return { message: 'Language server not ready' };
    }
    LSymbols = await PcProviders.workspaceSymbols(AQuery);
    for (LIndex = 0; LIndex < LSymbols.length; LIndex++) {
      LEntries.push({
        label: LSymbols[LIndex].name,
        description: LSymbols[LIndex].container,
        uri: LSymbols[LIndex].uri,
        range: LSymbols[LIndex].range
      });
    }
    if (LEntries.length === 0) {
      return { message: AQuery ? 'No matching symbols' : 'No symbols in the open documents' };
    }
    return { entries: PcQuickPick.rank(LEntries, AQuery) };
  }

  // Shift+Alt+H: call hierarchy of the routine at the cursor, in the panel
  async function doCallHierarchy() {
    var LTab = activeTab();
    var LCaps = PcLsp.capabilities();
    var LNode;

    PcShell.showPanel('calls');
    if (!PcLsp.isReady() || !LCaps || !LCaps.callHierarchyProvider) {
      PcCallTree.showMessage('Language server not ready');
      return;
    }
    if (!LTab || !lspUriOfModel(LTab.model)) {
      PcCallTree.showMessage('The language server has no data for this tab');
      return;
    }
    LNode = await PcProviders.prepareCallHierarchy(LTab.model, gEditor.getPosition());
    if (!LNode) {
      PcCallTree.showMessage('No routine at the cursor');
      return;
    }
    PcCallTree.show(LNode);
  }

  function runAction(AId) {
    var LAction = gEditor.getAction(AId);
    if (LAction) {
      LAction.run();
    }
  }

  // Format settings from main (settings.json 'format' section); null until boot
  var gFormat = null;

  // Indent settings are Monaco MODEL options: every Pascal model follows them
  function applyModelIndent(AModel) {
    if (gFormat && AModel.getLanguageId() === 'pcpp') {
      AModel.updateOptions({ tabSize: gFormat.indentSize, insertSpaces: !gFormat.useTabs });
    }
  }

  function applySettings(ASettings) {
    gFormat = ASettings && ASettings.format ? ASettings.format : null;
    gMonaco.editor.getModels().forEach(applyModelIndent);
  }

  // The format settings as LSP FormattingOptions keys (lsp-providers.js adds
  // tabSize / insertSpaces from the model)
  function formatOptions() {
    if (!gFormat) {
      return {};
    }
    return {
      trimTrailingWhitespace: gFormat.trimTrailingWhitespace,
      insertFinalNewline: gFormat.finalNewline,
      'pcpp.spaceAroundAssign': gFormat.spaceAroundAssign,
      'pcpp.spaceAroundOperators': gFormat.spaceAroundOperators,
      'pcpp.spaceAfterComma': gFormat.spaceAfterComma,
      'pcpp.spaceBeforeColon': gFormat.spaceBeforeColon,
      'pcpp.spaceAfterColon': gFormat.spaceAfterColon,
      'pcpp.maxBlankLines': gFormat.maxBlankLines,
      'pcpp.maxLineLength': gFormat.maxLineLength
    };
  }

  // Help > About: the box restores editor focus when it closes
  function doAbout() {
    PcAbout.open(function () {
      gEditor.focus();
    });
  }

  function onMenu(ACommand) {
    if (ACommand === 'new') {
      addTab(null, '');
    } else if (ACommand === 'open') {
      doOpen();
    } else if (ACommand === 'openFolder') {
      doOpenFolder();
    } else if (ACommand === 'closeAllFolders') {
      doCloseAllFolders();
    } else if (ACommand === 'toggleExamples') {
      doShowExamples(null);
    } else if (ACommand === 'save') {
      doSave();
    } else if (ACommand === 'saveAs') {
      doSaveAs();
    } else if (ACommand === 'saveAll') {
      doSaveAll();
    } else if (ACommand === 'rename') {
      doRename();
    } else if (ACommand === 'find') {
      runAction('actions.find');
    } else if (ACommand === 'replace') {
      runAction('editor.action.startFindReplaceAction');
    } else if (ACommand === 'formatDocument') {
      runAction('editor.action.formatDocument');
    } else if (ACommand === 'build') {
      doBuild(false);
    } else if (ACommand === 'run') {
      doBuild(true);
    } else if (ACommand === 'stop') {
      // One Stop: the debug session's, else the build / run's
      if (PcDebug.isActive()) {
        PcDebug.command('debugStop');
      } else {
        doStop();
      }
    } else if (PcDebug.command(ACommand)) {
      // debugStart / debugStepOver / debugStepIn / debugStepOut / debugPause / debugStop
      return;
    } else if (ACommand === 'gotoSymbol') {
      doGotoSymbol();
    } else if (ACommand === 'callHierarchy') {
      doCallHierarchy();
    } else if (ACommand === 'about') {
      doAbout();
    } else if (ACommand === 'reportIssue') {
      // Toolbar button: the reporter with no code (main owns the window)
      window.host.reportIssue('');
    }
  }

  // App shortcuts, bound on the editor as well as on the application menu
  // (main.js buildMenu - keep the two in step). While Monaco has focus it
  // may own a chord (Ctrl+B) and swallow it before the menu accelerator
  // sees it; binding here runs the command and consumes the key, so the
  // menu never double-fires. Outside the editor the menu handles it.
  var PC_APP_KEYS = [
    { cmd: 'new', ctrl: true, shift: false, key: 'KeyN' },
    { cmd: 'open', ctrl: true, shift: false, key: 'KeyO' },
    { cmd: 'save', ctrl: true, shift: false, key: 'KeyS' },
    { cmd: 'saveAs', ctrl: true, shift: true, key: 'KeyS' },
    { cmd: 'build', ctrl: true, shift: false, key: 'KeyB' },
    // F5 is the debugger's (W2); run without debugging = Ctrl+F5 (VS / VS Code)
    { cmd: 'run', ctrl: true, shift: false, key: 'F5' },
    { cmd: 'stop', ctrl: false, shift: true, key: 'F5' },
    { cmd: 'debugStart', ctrl: false, shift: false, key: 'F5' },
    { cmd: 'debugStepOver', ctrl: false, shift: false, key: 'F10' },
    { cmd: 'debugStepIn', ctrl: false, shift: false, key: 'F11' },
    { cmd: 'debugStepOut', ctrl: false, shift: true, key: 'F11' },
    { cmd: 'debugPause', ctrl: false, shift: false, key: 'F6' },
    { cmd: 'gotoSymbol', ctrl: true, shift: false, key: 'KeyT' },
    // alt is optional: absent = false
    { cmd: 'callHierarchy', ctrl: false, shift: true, alt: true, key: 'KeyH' }
  ];

  function registerAppKeys() {
    var LIndex;
    for (LIndex = 0; LIndex < PC_APP_KEYS.length; LIndex++) {
      registerAppKey(PC_APP_KEYS[LIndex]);
    }
  }

  function registerAppKey(AEntry) {
    var LBinding = gMonaco.KeyCode[AEntry.key];
    if (AEntry.ctrl) {
      LBinding = LBinding | gMonaco.KeyMod.CtrlCmd;
    }
    if (AEntry.shift) {
      LBinding = LBinding | gMonaco.KeyMod.Shift;
    }
    if (AEntry.alt) {
      LBinding = LBinding | gMonaco.KeyMod.Alt;
    }
    gEditor.addCommand(LBinding, function () {
      onMenu(AEntry.cmd);
    });
  }

  async function start(AMonaco) {
    var LInitial;
    var LExplorerReady;

    gMonaco = AMonaco;
    // model: null - every document model comes from addTab
    gEditor = gMonaco.editor.create(document.getElementById('editor'), {
      model: null,
      theme: 'pcpp-dark',
      automaticLayout: true,
      fontFamily: 'Consolas, "Cascadia Mono", monospace',
      fontSize: 14,
      tabSize: 2,
      insertSpaces: true,
      detectIndentation: false,
      renderWhitespace: 'selection',
      bracketPairColorization: { enabled: true },
      minimap: { enabled: true },
      // VS Code sizes; no shadow line under the scrolled top
      scrollbar: { verticalScrollbarSize: 14, horizontalScrollbarSize: 10, useShadows: false },
      // LSP semantic tokens recolour Monarch's instant colouring (theme
      // rules in pcpp-lang.js); parameter-name inlay hints on
      'semanticHighlighting.enabled': true,
      inlayHints: { enabled: 'on' },
      // Completion is the server's alone: Monaco's words scraped from the
      // file (comments included) would fill the list where the server says
      // nothing fits (inside a string, a C/C++ name)
      wordBasedSuggestions: 'off'
    });

    // Definition / references / peek into another file: open its tab
    gMonaco.editor.registerEditorOpener({
      openCodeEditor: function (ASource, AResource, ASelection) {
        var LUri = lspUriOfResource(AResource);

        if (!LUri) {
          return false;
        }
        return openAt(LUri, ASelection).then(function () {
          return true;
        });
      }
    });

    gEditor.onDidChangeCursorPosition(function (AEvent) {
      PcShell.setCursor(AEvent.position.lineNumber, AEvent.position.column);
    });
    // Toolbar buttons and the (hidden) application menu share one handler
    PcShell.init(onMenu);
    // Saved layout + build mode / target (state.json), before any tab opens
    PcShell.applyUiState(await window.host.getUiState());
    registerAppKeys();
    window.host.onMenu(onMenu);
    window.host.onBuildOutput(onBuildOutput);
    window.host.onBuildExit(onBuildExit);
    window.host.onRunConnect(onRunConnect);
    window.host.onRunOutput(PcTerminal.write);
    // Subscribe first, then ask: no state change can fall between the two
    window.host.onLspState(showLspState);
    window.host.lspState().then(showLspState);
    // Settings: subscribe first, then ask; models created later get the indent too
    gMonaco.editor.onDidCreateModel(applyModelIndent);
    window.host.onSettingsChanged(applySettings);
    window.host.onSettingsOpen(openPath);
    // files a second launch (pcpp editor <files>) hands over, each in a tab
    window.host.onOpenFiles(openPaths);
    // an open tab's file changed on disk (main.js watches the tabs' files)
    window.host.onFileChanged(onDiskChanges);
    applySettings(await window.host.getSettings());
    // Providers register on onLspReady; tabs and models stay in this unit
    PcProviders.init(gMonaco, {
      lspUriOf: lspUriOfModel,
      flush: flushLspChange,
      loadModels: loadModels,
      flushAll: flushAllLspChanges,
      openTabs: openTabs,
      formatOptions: formatOptions,
      modelUri: function (ALspUri) {
        return gMonaco.Uri.parse(ALspUri);
      }
    });
    // CALL HIERARCHY tab: data from the LSP, jumps through the opener
    PcCallTree.init(PcProviders.callChildren, openAt);
    PcLsp.init({
      onReady: onLspReady,
      onDown: onLspDown,
      onDiagnostics: onLspDiagnostics,
      onShowMessage: onLspShowMessage
    });
    // The program's terminal (TERMINAL tab): a Run's program or the debug
    // session's gets its keys and size
    PcTerminal.init({
      onInput: onTerminalInput,
      onResize: onTerminalResize
    });
    // Debugger UI: breakpoints in the glyph margin of every file model
    // (debug.js subscribes to model creation itself) and the session
    PcDebug.init(gMonaco, gEditor, {
      pathOfModel: function (AModel) {
        var LTab = tabOfModel(AModel);
        return (LTab && LTab.path) || '';
      },
      isSourcePath: isSourcePath,
      activeTab: activeTab,
      openPath: openPath,
      saveForBuild: function () { return saveForBuild('Debug'); },
      output: onBuildOutput,
      outputLine: PcShell.outputLine,
      clearOutput: PcShell.clearOutput,
      clearProblems: clearProblems,
      finishProblems: finishDebugBuild,
      showPanel: PcShell.showPanel,
      setStatus: PcShell.setBuildState,
      setDebugState: PcShell.setDebugState,
      buildBusy: function () { return gBuildActive; },
      getTarget: PcShell.getTarget,
      // A dll source's host exe: main remembers and picks it (W4)
      debugHostFor: window.host.dapHostFor,
      pickDebugHost: window.host.dapPickHost,
      forgetDebugHost: window.host.dapForgetHost,
      terminalWrite: PcTerminal.write,
      terminalReset: PcTerminal.reset,
      terminalSize: PcTerminal.size
    });
    // Nothing is running at start: only Stop is disabled
    PcShell.setBusy(false);
    // Runs alongside the tab restore; awaited before startup ends
    LExplorerReady = PcExplorer.init(openPath, doOpenFolder, doCloseFolder, function () {
      doShowExamples(false);
    });

    addTab(null, '');
    await restoreSession();
    // Restored tabs leave the explorer as it was left; from here a newly
    // active tab (the command-line file included) is revealed
    await LExplorerReady;
    PcExplorer.endRestore();
    // every command-line file opens; the last one is active
    LInitial = await window.host.initialFiles();
    LInitial.forEach(function (AFile) {
      openDocument(AFile.path, AFile.text);
    });
    gSessionReady = true;
    syncSession();
  }

  // Reopens the previous session's file tabs and its active tab. A file
  // that fails to read is skipped silently: it vanished or is locked.
  async function restoreSession() {
    var LSession = await window.host.loadSession();
    var LIndex;
    var LRes;

    for (LIndex = 0; LIndex < LSession.files.length; LIndex++) {
      LRes = await window.host.readFile(LSession.files[LIndex]);
      if (LRes.ok) {
        openDocument(LRes.path, LRes.text);
      }
    }
    LIndex = findTab(LSession.active);
    if (LIndex >= 0) {
      activateTab(LIndex);
    }
  }

  return { start: start };
})();
