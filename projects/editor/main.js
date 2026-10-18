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

  PaskalCPP Editor - Electron main process.

  Owns the window, the menu and all file-system access. The renderer has no
  Node access; it reaches the file system only through the IPC handlers
  below, exposed by preload.js.
*/
'use strict';

const { app, BrowserWindow, Menu, dialog, ipcMain, screen, shell } = require('electron');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { createLspHost } = require('./lsp-host');
const { createLspWatch } = require('./lsp-watch');
const { createDapHost, checkLaunchArgs, isHostExe, debugHostKey, validDebugHosts, hostFor } = require('./dap-host');
const { writeFileAtomic } = require('./atomic-write');
const { createRunTerminal } = require('./run-term');
const IssueReport = require('./issue-report');

const PC_FILE_FILTERS = [
  { name: 'PaskalCPP source', extensions: ['pcpp'] },
  { name: 'All files', extensions: ['*'] }
];

// All editor data (state.json, Chromium profile/cache) lives beside the
// exe in <editor>\data, never in AppData: one copy for every launcher.
// A sandboxed launcher (packaged app) gets AppData writes redirected to a
// private copy, which split the state between launches. Must run before
// anything uses userData (single-instance lock, app ready).
app.setPath('userData', path.join(path.dirname(process.execPath), 'data'));

let gWindow = null;
// Renderer-reported unsaved state, checked before the window closes
let gDirty = false;
let gForceClose = false;

// Remembered between launches (state.json in the user-data dir):
// folders = folders shown in the explorer, in the order added (no limit),
// lastDialogDir = where the
// open/save/folder dialogs start, openFiles/activeFile = the tabs,
// showExamples = the EXAMPLES section is shown in the explorer,
// window = the normal (un-maximized) bounds + maximized, layout = explorer
// width / panel height / panel collapsed, build = toolbar mode + target,
// explorerOpen = open explorer folders (roots included, the explorer's keys).
// null = never saved: defaults apply (explorerOpen: every root opens).
// debugHosts = the host exe picked per dll source (dap-host.js debugHostKey).
let gState = { folders: [], lastDialogDir: '', openFiles: [], activeFile: '', showExamples: true,
  window: null, layout: null, build: null, explorerOpen: null, debugHosts: {} };

// Build mode / target lists: PC_BUILD_MODES / PC_RETIRED_BUILD_MODES /
// PC_BUILD_TARGETS (build:start section below; validBuild and savedBuild run
// only after the module has loaded)
const PC_WINDOW_MIN_W = 400;
const PC_WINDOW_MIN_H = 300;

function isNum(AValue) {
  return typeof AValue === 'number' && Number.isFinite(AValue);
}

// A saved window rect, or null when missing or malformed
function validWindow(AData) {
  if (!AData || !isNum(AData.x) || !isNum(AData.y) || !isNum(AData.width) || !isNum(AData.height)) {
    return null;
  }
  if (AData.width < PC_WINDOW_MIN_W || AData.height < PC_WINDOW_MIN_H) {
    return null;
  }
  return { x: AData.x, y: AData.y, width: AData.width, height: AData.height, maximized: AData.maximized === true };
}

// Saved sizes are only range-checked here; the renderer clamps them against
// the live window (shell.js applyUiState)
function validLayout(AData) {
  if (!AData || !isNum(AData.explorerWidth) || !isNum(AData.panelHeight)) {
    return null;
  }
  return { explorerWidth: AData.explorerWidth, panelHeight: AData.panelHeight, panelCollapsed: AData.panelCollapsed === true };
}

function validBuild(AData) {
  if (!AData || PC_BUILD_MODES.indexOf(AData.mode) < 0 || PC_BUILD_TARGETS.indexOf(AData.target) < 0) {
    return null;
  }
  return { mode: AData.mode, target: AData.target };
}

// The build choice as state.json holds it: a retired level name is read as
// its new name (PC_RETIRED_BUILD_MODES), then checked as any choice
function savedBuild(AData) {
  if (AData && typeof AData.mode === 'string' &&
      Object.prototype.hasOwnProperty.call(PC_RETIRED_BUILD_MODES, AData.mode)) {
    return validBuild({ mode: PC_RETIRED_BUILD_MODES[AData.mode], target: AData.target });
  }
  return validBuild(AData);
}

// Open explorer folders (the explorer's keys), or null when missing or malformed
function validExplorerOpen(AValue) {
  if (!Array.isArray(AValue)) {
    return null;
  }
  return AValue.filter((AItem) => typeof AItem === 'string' && AItem !== '');
}

function stateFile() {
  return path.join(app.getPath('userData'), 'state.json');
}

function loadState() {
  try {
    const LData = JSON.parse(fs.readFileSync(stateFile(), 'utf8'));
    if (Array.isArray(LData.folders)) {
      gState.folders = LData.folders.filter((AItem) => typeof AItem === 'string' && AItem !== '');
    } else if (typeof LData.lastFolder === 'string' && LData.lastFolder !== '') {
      // State files from the single-folder explorer
      gState.folders = [LData.lastFolder];
    }
    gState.lastDialogDir = typeof LData.lastDialogDir === 'string' ? LData.lastDialogDir : '';
    // A dialog folder that no longer exists is forgotten, except one in the
    // examples folder (never forgotten; dialogDir skips it while missing)
    if (gState.lastDialogDir !== '' && !isDir(gState.lastDialogDir) &&
      !isUnderExamples(gState.lastDialogDir)) {
      gState.lastDialogDir = '';
    }
    gState.openFiles = Array.isArray(LData.openFiles) ?
      LData.openFiles.filter((AItem) => typeof AItem === 'string') : [];
    gState.activeFile = typeof LData.activeFile === 'string' ? LData.activeFile : '';
    // Missing in older state files: shown
    gState.showExamples = LData.showExamples !== false;
    // Missing or malformed in older state files: null = defaults
    gState.window = validWindow(LData.window);
    gState.layout = validLayout(LData.layout);
    gState.build = savedBuild(LData.build);
    gState.explorerOpen = validExplorerOpen(LData.explorerOpen);
    // Missing or malformed in older state files: none remembered
    gState.debugHosts = validDebugHosts(LData.debugHosts);
  } catch (AErr) {
    // First launch or unreadable file: start with no remembered paths
  }
}

// state.json is written crash-safely: always the whole old or the whole new
// state, never a part (atomic-write.js)
function saveState() {
  try {
    writeFileAtomic(stateFile(), JSON.stringify(gState, null, 2));
  } catch (AErr) {
    process.stderr.write('state.json not saved: ' + AErr.message + '\n');
  }
}

// Editor settings: data\settings.json beside state.json. The user edits it in
// a tab (Preferences > Format Settings); main owns loading it.
// PC_FORMAT_DEFAULTS: the formatting options the editor applies to its models
// and sends with textDocument/formatting (spec keys plus pcpp.* keys).
const PC_FORMAT_DEFAULTS = {
  indentSize: 2,
  useTabs: false,
  spaceAroundAssign: true,
  spaceAroundOperators: true,
  spaceAfterComma: true,
  spaceBeforeColon: false,
  spaceAfterColon: true,
  maxBlankLines: 1,
  trimTrailingWhitespace: true,
  finalNewline: true,
  maxLineLength: 80,
  formatOnSave: false
};

// Integer settings and their allowed ranges
const PC_FORMAT_RANGES = {
  indentSize: [1, 8],
  maxBlankLines: [0, 9],
  maxLineLength: [60, 200]
};

let gSettings = { format: Object.assign({}, PC_FORMAT_DEFAULTS) };

function settingsFile() {
  return path.join(app.getPath('userData'), 'settings.json');
}

function isSettingsFile(AFilename) {
  const LPath = path.resolve(AFilename);
  const LSettings = settingsFile();
  if (process.platform === 'win32') {
    return LPath.toLowerCase() === LSettings.toLowerCase();
  }
  return LPath === LSettings;
}

// One format setting from the file: kept when its type (and range) matches
// the default's, else the default. Missing keys come out as the default.
function validFormatValue(AKey, AValue) {
  const LDefault = PC_FORMAT_DEFAULTS[AKey];
  const LRange = PC_FORMAT_RANGES[AKey];
  if (typeof LDefault === 'boolean') {
    return typeof AValue === 'boolean' ? AValue : LDefault;
  }
  if (Number.isInteger(AValue) && AValue >= LRange[0] && AValue <= LRange[1]) {
    return AValue;
  }
  return LDefault;
}

function loadSettings() {
  const LFormat = Object.assign({}, PC_FORMAT_DEFAULTS);
  const LRes = readFileSafe(settingsFile());
  if (LRes.ok) {
    try {
      const LData = JSON.parse(LRes.text);
      const LSection = (LData && typeof LData.format === 'object' && LData.format !== null) ?
        LData.format : {};
      for (const LKey of Object.keys(PC_FORMAT_DEFAULTS)) {
        LFormat[LKey] = validFormatValue(LKey, LSection[LKey]);
      }
    } catch (AErr) {
      // Not valid JSON (saved mid-edit, say): every setting keeps its default
    }
  }
  gSettings = { format: LFormat };
}

// Preferences > Format Settings: creates settings.json with the defaults on
// first use (an existing file is never rewritten), then opens it in a tab
function openSettings() {
  const LFile = settingsFile();
  if (!fs.existsSync(LFile)) {
    const LRes = writeFileSafe(LFile, JSON.stringify({ format: PC_FORMAT_DEFAULTS }, null, 2) + '\n');
    if (!LRes.ok) {
      process.stderr.write('settings.json not created: ' + LRes.error + '\n');
      return;
    }
  }
  sendWindow('settings:open', LFile);
}

// Any write, rename or move that touches settings.json re-applies it (a rename
// away from it leaves no file: every setting falls back to its default)
function settingsTouched(...AFilenames) {
  if (AFilenames.some((AName) => AName && isSettingsFile(AName))) {
    loadSettings();
    sendWindow('settings:changed', gSettings);
  }
}

function isDir(APath) {
  try {
    return !!APath && fs.statSync(APath).isDirectory();
  } catch (AErr) {
    return false;
  }
}

function isFile(APath) {
  try {
    return !!APath && fs.statSync(APath).isFile();
  } catch (AErr) {
    return false;
  }
}

// Explorer folders that still exist, in order: what the explorer shows and
// the dialog defaults. A remembered folder that no longer exists is
// forgotten (folders:list at startup, the explorer's root close while
// running), never shown dead; the examples folder is kept, only not shown.
function existingFolders() {
  return gState.folders.filter((AItem) => isDir(AItem));
}

// The most recently added explorer folder that still exists, or ''
function lastAddedFolder() {
  const LList = existingFolders();
  return LList.length > 0 ? LList[LList.length - 1] : '';
}

// Index of APath in gState.folders (Windows paths: case-insensitive), -1 if absent
function folderIndex(APath) {
  const LKey = path.resolve(APath).toLowerCase();
  return gState.folders.findIndex((AItem) => path.resolve(AItem).toLowerCase() === LKey);
}

// Where a dialog opens: last dialog folder, else the newest explorer folder
function dialogDir() {
  if (isDir(gState.lastDialogDir)) {
    return gState.lastDialogDir;
  }
  if (lastAddedFolder()) {
    return lastAddedFolder();
  }
  return undefined;
}

function rememberDialogDir(ADir) {
  gState.lastDialogDir = ADir;
  saveState();
}

// The one way anything reaches the renderer (menu, build, LSP): a window
// being torn down (quit, crash) is skipped, never sent to
function sendWindow(AChannel, AData) {
  if (gWindow && !gWindow.isDestroyed()) {
    gWindow.webContents.send(AChannel, AData);
  }
}

function sendMenu(ACommand) {
  sendWindow('menu', ACommand);
}

function buildMenu() {
  // Accelerators for new/open/save/saveAs/build/run/stop/gotoSymbol/
  // callHierarchy are also bound on
  // the Monaco editor (src/renderer.js PC_APP_KEYS) - keep the two in step
  const LTemplate = [
    {
      label: 'File',
      submenu: [
        { label: 'New', accelerator: 'CmdOrCtrl+N', click: () => sendMenu('new') },
        { label: 'Open...', accelerator: 'CmdOrCtrl+O', click: () => sendMenu('open') },
        { label: 'Open Folder...', click: () => sendMenu('openFolder') },
        { label: 'Close All Folders', click: () => sendMenu('closeAllFolders') },
        // Tick follows gState.showExamples: rebuildMenu() after every change
        { label: 'Show Examples', type: 'checkbox', checked: gState.showExamples,
          click: () => sendMenu('toggleExamples') },
        { type: 'separator' },
        { label: 'Save', accelerator: 'CmdOrCtrl+S', click: () => sendMenu('save') },
        { label: 'Save As...', accelerator: 'CmdOrCtrl+Shift+S', click: () => sendMenu('saveAs') },
        { label: 'Save All', click: () => sendMenu('saveAll') },
        { label: 'Rename...', click: () => sendMenu('rename') },
        { type: 'separator' },
        { role: 'quit' }
      ]
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' }, { role: 'redo' }, { type: 'separator' },
        { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' },
        { type: 'separator' },
        { label: 'Find', accelerator: 'CmdOrCtrl+F', click: () => sendMenu('find') },
        { label: 'Replace', accelerator: 'CmdOrCtrl+H', click: () => sendMenu('replace') },
        { type: 'separator' },
        // Shift+Alt+F is also Monaco's own binding: not added to PC_APP_KEYS
        { label: 'Format Document', accelerator: 'Shift+Alt+F', click: () => sendMenu('formatDocument') }
      ]
    },
    {
      label: 'Go',
      submenu: [
        { label: 'Go to Symbol in Workspace...', accelerator: 'CmdOrCtrl+T', click: () => sendMenu('gotoSymbol') },
        { label: 'Show Call Hierarchy', accelerator: 'Shift+Alt+H', click: () => sendMenu('callHierarchy') }
      ]
    },
    {
      label: 'Build',
      submenu: [
        { label: 'Build', accelerator: 'CmdOrCtrl+B', click: () => sendMenu('build') },
        { label: 'Run', accelerator: 'CmdOrCtrl+F5', click: () => sendMenu('run') },
        { label: 'Stop', accelerator: 'Shift+F5', click: () => sendMenu('stop') }
      ]
    },
    {
      label: 'Debug',
      submenu: [
        { label: 'Start Debugging / Continue', accelerator: 'F5', click: () => sendMenu('debugStart') },
        { label: 'Step Over', accelerator: 'F10', click: () => sendMenu('debugStepOver') },
        { label: 'Step Into', accelerator: 'F11', click: () => sendMenu('debugStepIn') },
        { label: 'Step Out', accelerator: 'Shift+F11', click: () => sendMenu('debugStepOut') },
        { label: 'Pause', accelerator: 'F6', click: () => sendMenu('debugPause') },
        { type: 'separator' },
        // Shift+F5 is Build > Stop's: it stops the session when one runs
        { label: 'Stop Debugging', click: () => sendMenu('debugStop') }
      ]
    },
    {
      label: 'View',
      submenu: [
        { role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
        { role: 'toggleDevTools' }
      ]
    },
    {
      label: 'Preferences',
      submenu: [
        // main owns settings.json: it handles the click itself
        { label: 'Format Settings', click: () => openSettings() }
      ]
    },
    {
      label: 'Help',
      submenu: [
        // main owns the reporter window: it handles the click itself
        { label: 'Report Issue...', click: () => openIssueReporter('') },
        { type: 'separator' },
        { label: 'About PaskalCPP', click: () => sendMenu('about') }
      ]
    }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(LTemplate));
}

// Re-applies the menu after a state change its items show (checkbox
// ticks). setApplicationMenu re-attaches the bar, so hide it again.
function rebuildMenu() {
  buildMenu();
  if (gWindow && !gWindow.isDestroyed()) {
    gWindow.setMenuBarVisibility(false);
  }
}

// http(s) links open in the user's default browser; every other scheme
// (file:, javascript:, ...) is refused. true = handed to the browser.
function openWebUrl(AUrl) {
  let LProtocol = '';
  try {
    LProtocol = new URL(String(AUrl)).protocol;
  } catch (AErr) {
    return false;
  }
  if (LProtocol !== 'http:' && LProtocol !== 'https:') {
    return false;
  }
  shell.openExternal(String(AUrl)).catch((AErr) => {
    process.stderr.write('link not opened: ' + AErr.message + '\n');
  });
  return true;
}

function readFileSafe(AFilename) {
  try {
    // Strip a UTF-8 BOM: sources may carry one, Monaco should not show it
    let LText = fs.readFileSync(AFilename, 'utf8');
    if (LText.charCodeAt(0) === 0xFEFF) {
      LText = LText.slice(1);
    }
    return { ok: true, path: AFilename, text: LText };
  } catch (AErr) {
    return { ok: false, error: String(AErr && AErr.message ? AErr.message : AErr) };
  }
}

function writeFileSafe(AFilename, AText) {
  try {
    // Every file is written as plain UTF-8, no BOM (the C / C++ norm; the
    // PaskalCPP lexer and clang read a file with or without one)
    fs.writeFileSync(AFilename, AText, 'utf8');
    return { ok: true, path: AFilename };
  } catch (AErr) {
    return { ok: false, error: String(AErr && AErr.message ? AErr.message : AErr) };
  }
}

ipcMain.handle('file:open', async () => {
  const LRes = await dialog.showOpenDialog(gWindow, {
    defaultPath: dialogDir(),
    properties: ['openFile'],
    filters: PC_FILE_FILTERS
  });
  if (LRes.canceled || LRes.filePaths.length === 0) {
    return { ok: false, canceled: true };
  }
  rememberDialogDir(path.dirname(LRes.filePaths[0]));
  return readFileSafe(LRes.filePaths[0]);
});

ipcMain.handle('file:save', async (AEvent, AFilename, AText) => {
  const LRes = writeFileSafe(AFilename, AText);
  // Saving settings.json in a tab applies it at once (the editor is its only
  // writer: no file watch)
  if (LRes.ok) {
    settingsTouched(AFilename);
  }
  return LRes;
});

ipcMain.handle('file:saveAs', async (AEvent, AText, ASuggested) => {
  // A bare suggested name (Untitled-1.pcpp) goes into the remembered folder
  let LDefault = ASuggested || 'untitled.pcpp';
  if (!path.isAbsolute(LDefault) && dialogDir()) {
    LDefault = path.join(dialogDir(), LDefault);
  }
  const LRes = await dialog.showSaveDialog(gWindow, {
    defaultPath: LDefault,
    filters: PC_FILE_FILTERS
  });
  if (LRes.canceled || !LRes.filePath) {
    return { ok: false, canceled: true };
  }
  rememberDialogDir(path.dirname(LRes.filePath));
  const LWrite = writeFileSafe(LRes.filePath, AText);
  if (LWrite.ok) {
    settingsTouched(LRes.filePath);
  }
  return LWrite;
});

// Rename (or move) a file on disk. The dialog asks before replacing an
// existing file. A move across drives cannot rename: copy, then delete.
ipcMain.handle('file:rename', async (AEvent, AFilename) => {
  const LRes = await dialog.showSaveDialog(gWindow, {
    title: 'Rename File',
    buttonLabel: 'Rename',
    defaultPath: AFilename,
    filters: PC_FILE_FILTERS
  });
  if (LRes.canceled || !LRes.filePath) {
    return { ok: false, canceled: true };
  }
  if (path.resolve(LRes.filePath) === path.resolve(AFilename)) {
    return { ok: true, path: AFilename };
  }
  try {
    try {
      fs.renameSync(AFilename, LRes.filePath);
    } catch (AErr) {
      if (!AErr || AErr.code !== 'EXDEV') {
        throw AErr;
      }
      fs.copyFileSync(AFilename, LRes.filePath);
      fs.unlinkSync(AFilename);
    }
  } catch (AErr) {
    return { ok: false, error: String(AErr && AErr.message ? AErr.message : AErr) };
  }
  rememberDialogDir(path.dirname(LRes.filePath));
  settingsTouched(AFilename, LRes.filePath);
  return { ok: true, path: LRes.filePath };
});

// Explorer: read a file by path (no dialog)
ipcMain.handle('file:read', async (AEvent, AFilename) => {
  return readFileSafe(AFilename);
});

// Explorer folders: main.js owns the list; every call below returns the
// folders of the list that exist ({ folders }) and the explorer shows
// exactly that.

// Open Folder adds a root (no limit); a folder already open is not added twice
ipcMain.handle('folder:open', async () => {
  const LRes = await dialog.showOpenDialog(gWindow, {
    defaultPath: lastAddedFolder() || dialogDir(),
    properties: ['openDirectory']
  });
  if (LRes.canceled || LRes.filePaths.length === 0) {
    return { ok: false, canceled: true, folders: existingFolders() };
  }
  if (folderIndex(LRes.filePaths[0]) < 0) {
    gState.folders.push(LRes.filePaths[0]);
  }
  // rememberDialogDir saves the state, folders included
  rememberDialogDir(LRes.filePaths[0]);
  return { ok: true, path: LRes.filePaths[0], folders: existingFolders() };
});

// The explorer folders from the previous session, and which of its folders
// were open (expanded: null = never saved). A remembered folder or open
// folder that no longer exists is forgotten here, and the state saved, so
// a moved or deleted folder never comes back as a dead root. The official
// examples folder is the exception: kept in the state, only not shown.
ipcMain.handle('folders:list', async () => {
  const LKept = (AItem) => isDir(AItem) || isUnderExamples(AItem);
  const LFolders = gState.folders.filter(LKept);
  const LOpen = gState.explorerOpen ? gState.explorerOpen.filter(LKept) : null;

  if (LFolders.length !== gState.folders.length ||
    (LOpen && LOpen.length !== gState.explorerOpen.length)) {
    gState.folders = LFolders;
    gState.explorerOpen = LOpen;
    saveState();
  }
  return { ok: true, folders: existingFolders(),
    expanded: gState.explorerOpen ? gState.explorerOpen.slice() : null };
});

// The explorer's open folders, the whole set, on every open / collapse / close
ipcMain.on('explorer:open', (AEvent, AKeys) => {
  gState.explorerOpen = validExplorerOpen(AKeys) || [];
  saveState();
});

// A root's x: remove that one folder
ipcMain.handle('folder:close', async (AEvent, APath) => {
  const LIndex = typeof APath === 'string' ? folderIndex(APath) : -1;
  if (LIndex >= 0) {
    gState.folders.splice(LIndex, 1);
    saveState();
  }
  return { ok: true, folders: existingFolders() };
});

// File > Close All Folders
ipcMain.handle('folders:closeAll', async () => {
  gState.folders = [];
  saveState();
  return { ok: true, folders: [] };
});

// Open tabs: the renderer reports its file tabs whenever the set changes
ipcMain.on('session:save', (AEvent, AFiles, AActive) => {
  gState.openFiles = Array.isArray(AFiles) ? AFiles.filter((AItem) => typeof AItem === 'string') : [];
  gState.activeFile = typeof AActive === 'string' ? AActive : '';
  saveState();
});

// Tabs of the previous session that still exist on disk; the active tab
// only when it is one of them. The renderer reports the tabs it restored
// (session:save), so a missing file is forgotten from the state too.
ipcMain.handle('session:load', async () => {
  const LFiles = gState.openFiles.filter((AItem) => {
    try {
      return fs.statSync(AItem).isFile();
    } catch (AErr) {
      return false;
    }
  });
  const LActive = LFiles.indexOf(gState.activeFile) >= 0 ? gState.activeFile : '';

  return { files: LFiles, active: LActive };
});

// Bundled examples: <editor>\resources -> <editor> -> bin\res -> examples.
// The official folder: while it is missing it is not shown, but nothing
// about it is ever forgotten (its open folders, a dialog folder in it).
function examplesDir() {
  return path.resolve(process.resourcesPath, '..', '..', 'examples');
}

// True when APath is the examples folder or inside it (case-insensitive)
function isUnderExamples(APath) {
  const LRoot = examplesDir().toLowerCase();
  const LKey = path.resolve(APath).toLowerCase();
  return LKey === LRoot || LKey.startsWith(LRoot + path.sep);
}

// { ok: true, path } shown; { ok: false, hidden: true, path } while the
// user has closed EXAMPLES; { ok: false, path } while it is missing. The
// path always comes back, so the explorer knows the official folder.
function examplesResult() {
  const LDir = examplesDir();
  if (!gState.showExamples) {
    return { ok: false, hidden: true, path: LDir };
  }
  return isDir(LDir) ? { ok: true, path: LDir } : { ok: false, path: LDir };
}

ipcMain.handle('folder:examples', async () => examplesResult());

// Show / hide EXAMPLES (explorer x, File > Show Examples); remembered, and
// the menu tick follows. AOn = true / false, or null = flip (the menu item:
// only main.js knows the remembered setting). Returns what folder:examples
// would now return.
ipcMain.handle('examples:show', async (AEvent, AOn) => {
  if (AOn === null) {
    gState.showExamples = !gState.showExamples;
  } else {
    gState.showExamples = AOn === true;
  }
  saveState();
  rebuildMenu();
  return examplesResult();
});

// Folders first, then .pcpp files, then everything else; each group
// alphabetical. Dot-entries are hidden.
function entryRank(AEntry) {
  if (AEntry.isDir) {
    return 0;
  }
  return path.extname(AEntry.name).toLowerCase() === '.pcpp' ? 1 : 2;
}

ipcMain.handle('folder:list', async (AEvent, ADir) => {
  try {
    const LEntries = fs.readdirSync(ADir, { withFileTypes: true })
      .filter((AItem) => !AItem.name.startsWith('.'))
      .map((AItem) => ({
        name: AItem.name,
        path: path.join(ADir, AItem.name),
        isDir: AItem.isDirectory()
      }));
    LEntries.sort((AA, AB) => {
      const LRank = entryRank(AA) - entryRank(AB);
      if (LRank !== 0) {
        return LRank;
      }
      return AA.name.localeCompare(AB.name, undefined, { sensitivity: 'base' });
    });
    return { ok: true, entries: LEntries };
  } catch (AErr) {
    // missing = the directory is gone (deleted, moved, replaced by a file);
    // any other failure (access denied, ...) is a real read error
    const LMissing = !!AErr && (AErr.code === 'ENOENT' || AErr.code === 'ENOTDIR');
    return { ok: false, missing: LMissing, error: String(AErr && AErr.message ? AErr.message : AErr) };
  }
});

// Explorer roots watched for changes on disk (resolved root -> FSWatcher).
// The explorer names the roots it shows (folder:watch); every change is
// reported to it as the directories whose entries may have changed,
// coalesced and debounced, so the tree never shows a stale listing no
// matter who changed the disk (Save As, Rename, a build, another program).
const PC_WATCH_WINDOW_MS = 150;
const gWatchers = new Map();
const gChangedDirs = new Set();
let gChangedTimer = null;

function flushChangedDirs() {
  const LDirs = Array.from(gChangedDirs);

  gChangedTimer = null;
  gChangedDirs.clear();
  if (LDirs.length > 0 && gWindow && !gWindow.isDestroyed()) {
    gWindow.webContents.send('folder:changed', LDirs);
  }
}

function noteFolderChange(ARoot, AFilename) {
  if (AFilename) {
    // AFilename is relative to the watched root; its parent is the
    // directory whose listing changed
    gChangedDirs.add(path.dirname(path.join(ARoot, AFilename.toString())));
  } else {
    // No name given (watcher error, event overflow): re-list the root
    gChangedDirs.add(ARoot);
  }
  // Fixed window, not a sliding debounce: the first change arms the timer
  // and later ones join the set, so a steady stream of writes (a build)
  // cannot postpone the report forever
  if (!gChangedTimer) {
    gChangedTimer = setTimeout(flushChangedDirs, PC_WATCH_WINDOW_MS);
  }
}

function stopWatcher(ARoot) {
  const LWatcher = gWatchers.get(ARoot);

  gWatchers.delete(ARoot);
  if (LWatcher) {
    try {
      LWatcher.close();
    } catch (AErr) {
      // already closed
    }
  }
}

function startWatcher(ARoot) {
  let LWatcher;

  try {
    LWatcher = fs.watch(ARoot, { recursive: true }, (AType, AFilename) => {
      noteFolderChange(ARoot, AFilename);
    });
  } catch (AErr) {
    return String(AErr && AErr.message ? AErr.message : AErr);
  }
  // The root itself went away or became unreadable: stop, re-list it so
  // the explorer shows the failure
  LWatcher.on('error', () => {
    stopWatcher(ARoot);
    noteFolderChange(ARoot, null);
  });
  gWatchers.set(ARoot, LWatcher);
  return '';
}

// Replaces the watched set with ARoots (existing directories only)
ipcMain.handle('folder:watch', async (AEvent, ARoots) => {
  const LWanted = new Set();
  const LErrors = [];

  if (Array.isArray(ARoots)) {
    for (const LRoot of ARoots) {
      if (typeof LRoot === 'string' && isDir(LRoot)) {
        LWanted.add(path.resolve(LRoot));
      }
    }
  }
  for (const LRoot of Array.from(gWatchers.keys())) {
    if (!LWanted.has(LRoot)) {
      stopWatcher(LRoot);
    }
  }
  for (const LRoot of LWanted) {
    if (!gWatchers.has(LRoot)) {
      const LError = startWatcher(LRoot);
      if (LError) {
        LErrors.push(LRoot + ': ' + LError);
      }
    }
  }
  return { ok: LErrors.length === 0, watching: Array.from(gWatchers.keys()), errors: LErrors };
});

// Open tabs' files watched for changes on disk (resolved directory ->
// { watcher, names: lowercase file name -> the path the renderer gave }).
// The renderer names its tabs' files (file:watch); every change is reported
// as [{ path, exists }] in the renderer's own spelling, coalesced in the
// same fixed window as the folders. A file is watched through its parent
// directory, not recursive, filtered by name: a watch on the file itself
// ends when the file is replaced by a rename (an atomic save, git) or
// deleted, a directory watch sees both. Its own set, independent of the
// explorer roots, so a file opened from outside every root is covered.
const gFileWatchers = new Map();
const gChangedFiles = new Set();
let gFileTimer = null;

function flushChangedFiles() {
  const LChanges = [];

  gFileTimer = null;
  for (const LFile of gChangedFiles) {
    LChanges.push({ path: LFile, exists: isFile(LFile) });
  }
  gChangedFiles.clear();
  if (LChanges.length > 0 && gWindow && !gWindow.isDestroyed()) {
    gWindow.webContents.send('file:changed', LChanges);
  }
}

function noteFileChange(ADir, AFilename) {
  const LEntry = gFileWatchers.get(ADir);
  let LPath;

  if (!LEntry) {
    return;
  }
  if (AFilename) {
    // A directory watch names the entry relative to the directory: its
    // base name. Only the watched files of this directory are reported.
    LPath = LEntry.names.get(path.basename(AFilename.toString()).toLowerCase());
    if (!LPath) {
      return;
    }
    gChangedFiles.add(LPath);
  } else {
    // No name given (watcher error, event overflow): every watched file
    // of the directory may have changed
    for (const LName of LEntry.names.values()) {
      gChangedFiles.add(LName);
    }
  }
  if (!gFileTimer) {
    gFileTimer = setTimeout(flushChangedFiles, PC_WATCH_WINDOW_MS);
  }
}

function stopFileWatcher(ADir) {
  const LEntry = gFileWatchers.get(ADir);

  gFileWatchers.delete(ADir);
  if (LEntry) {
    try {
      LEntry.watcher.close();
    } catch (AErr) {
      // already closed
    }
  }
}

function startFileWatcher(ADir, ANames) {
  let LWatcher;

  try {
    LWatcher = fs.watch(ADir, { recursive: false }, (AType, AFilename) => {
      noteFileChange(ADir, AFilename);
    });
  } catch (AErr) {
    return String(AErr && AErr.message ? AErr.message : AErr);
  }
  // The directory went away or became unreadable: report its files (the
  // renderer sees them missing), then stop. The renderer names its files
  // again after a deletion, which watches the directory once it is back.
  LWatcher.on('error', () => {
    noteFileChange(ADir, null);
    stopFileWatcher(ADir);
  });
  gFileWatchers.set(ADir, { watcher: LWatcher, names: ANames });
  return '';
}

// Replaces the watched file set with AFiles (absolute paths; a directory
// that does not exist is skipped)
ipcMain.handle('file:watch', async (AEvent, AFiles) => {
  const LWanted = new Map();
  const LErrors = [];
  let LDir;
  let LNames;

  if (Array.isArray(AFiles)) {
    for (const LFile of AFiles) {
      if (typeof LFile === 'string' && path.isAbsolute(LFile)) {
        LDir = path.resolve(path.dirname(LFile));
        LNames = LWanted.get(LDir);
        if (!LNames) {
          LNames = new Map();
          LWanted.set(LDir, LNames);
        }
        LNames.set(path.basename(LFile).toLowerCase(), LFile);
      }
    }
  }
  for (const LDirKey of Array.from(gFileWatchers.keys())) {
    if (!LWanted.has(LDirKey)) {
      stopFileWatcher(LDirKey);
    }
  }
  for (const [LDirKey, LDirNames] of LWanted) {
    if (gFileWatchers.has(LDirKey)) {
      // Same directory, the file set may differ: just swap the names
      gFileWatchers.get(LDirKey).names = LDirNames;
    } else if (isDir(LDirKey)) {
      const LError = startFileWatcher(LDirKey, LDirNames);
      if (LError) {
        LErrors.push(LDirKey + ': ' + LError);
      }
    }
  }
  return { ok: LErrors.length === 0, watching: Array.from(gFileWatchers.keys()), errors: LErrors };
});

// The files named on a command line (pcpp editor <files>): every argument
// that is an existing file, resolved against ADir. Switches (Chromium's
// included) and '.' are not files.
function argFiles(AArgs, ADir) {
  const LFiles = [];
  for (const LArg of AArgs) {
    if (LArg.startsWith('-') || LArg === '.') {
      continue;
    }
    const LFull = path.resolve(ADir, LArg);
    try {
      if (fs.statSync(LFull).isFile() && !LFiles.includes(LFull)) {
        LFiles.push(LFull);
      }
    } catch (AErr) {
      // not a file: ignored
    }
  }
  return LFiles;
}

// The files on this instance's command line open at start, each in a tab
ipcMain.handle('file:initial', async () => {
  return argFiles(process.argv.slice(1), process.cwd())
    .map(readFileSafe)
    .filter((ARes) => ARes.ok);
});

ipcMain.on('doc:state', (AEvent, AState) => {
  gDirty = !!AState.dirty;
  if (gWindow) {
    gWindow.setTitle((gDirty ? '* ' : '') + AState.title + ' - PaskalCPP Editor');
  }
});

// The logo button in the custom title bar opens the (hidden) application
// menu as a popup, so the menu stays the single command registry
ipcMain.on('menu:popup', (AEvent, AX, AY) => {
  const LMenu = Menu.getApplicationMenu();
  if (gWindow && LMenu) {
    LMenu.popup({ window: gWindow, x: Math.round(AX), y: Math.round(AY) });
  }
});

// The issue reporter: the project's form (issue-report.js holds the rules)
// in a sandboxed modal window. One at a time: another request focuses it.
let gReporter = null;

function reporterUnavailable(AMessage, ADetail, AUrl) {
  if (!gWindow || gWindow.isDestroyed()) {
    return;
  }
  const LButtons = AUrl ? ['Open in Browser', 'Close'] : ['Close'];
  dialog.showMessageBox(gWindow, {
    type: 'error',
    title: 'Report Issue',
    message: AMessage,
    detail: ADetail,
    buttons: LButtons,
    defaultId: 0,
    cancelId: LButtons.length - 1
  }).then((AResult) => {
    if (AUrl && AResult.response === 0) {
      openWebUrl(AUrl);
    }
  }).catch((AErr) => {
    process.stderr.write('report message not shown: ' + AErr.message + '\n');
  });
}

// ACode = the diagnostic code of a PROBLEMS row ('' from the toolbar and
// Help); anything that is not a diagnostic code is left out of the form
function openIssueReporter(ACode) {
  if (!gWindow || gWindow.isDestroyed()) {
    return;
  }
  if (gReporter && !gReporter.isDestroyed()) {
    gReporter.focus();
    return;
  }
  const LPkg = appPackage();
  const LSite = (LPkg.about && LPkg.about.url) || '';
  const LOrigin = IssueReport.reportOrigin(LSite);
  const LUrl = IssueReport.buildReportUrl(LSite, LPkg.version || '', IssueReport.hostPlatform(), ACode);
  if (LUrl === '') {
    reporterUnavailable('The issue reporter is not available.',
      'This build carries no https site address (package.json about.url).', '');
    return;
  }

  const LWin = new BrowserWindow(IssueReport.reporterWindowOptions(gWindow));
  gReporter = LWin;
  // The application menu would send its commands to the editor from here
  LWin.removeMenu();

  // A window the form opens: github.com (a created issue) goes to the
  // browser, everything else is refused
  LWin.webContents.setWindowOpenHandler((ADetails) => {
    if (IssueReport.isExternalLink(ADetails.url)) {
      openWebUrl(ADetails.url);
    }
    return { action: 'deny' };
  });

  // Navigations and redirects stay on the form's origin (Electron 44: the
  // url is on the event; the positional argument is the older form)
  const LGuard = (AEvent, ANavUrl) => {
    const LTarget = AEvent.url || ANavUrl;
    if (!IssueReport.isAllowedNavigation(LTarget, LOrigin)) {
      AEvent.preventDefault();
    }
  };
  LWin.webContents.on('will-navigate', LGuard);
  LWin.webContents.on('will-redirect', LGuard);

  // The page cannot be reached (offline, DNS, TLS): close and say so, with
  // the address to open in a browser. -3 (ERR_ABORTED) is a stopped load.
  LWin.webContents.on('did-fail-load', (AEvent, AErrorCode, ADescription, AFailedUrl, AIsMainFrame) => {
    if (!AIsMainFrame || AErrorCode === -3) {
      return;
    }
    if (!LWin.isDestroyed()) {
      LWin.close();
    }
    reporterUnavailable('The issue reporter could not be reached.',
      ADescription + ' (' + AErrorCode + ')\n' + LUrl, LUrl);
  });

  LWin.on('closed', () => {
    if (gReporter === LWin) {
      gReporter = null;
    }
  });

  // A failed load is reported by did-fail-load; the promise only rejects too
  LWin.loadURL(LUrl).catch(() => {});
}

// The toolbar button (renderer command 'reportIssue')
ipcMain.on('report:open', (AEvent, ACode) => {
  openIssueReporter(typeof ACode === 'string' ? ACode : '');
});

// A right-click on a PROBLEMS row: its own menu, carrying the row's code
ipcMain.on('problem:menu', (AEvent, ACode) => {
  if (!gWindow || gWindow.isDestroyed()) {
    return;
  }
  const LCode = typeof ACode === 'string' ? ACode : '';
  Menu.buildFromTemplate([
    { label: 'Report This Error...', click: () => openIssueReporter(LCode) }
  ]).popup({ window: gWindow });
});

// Build / run: pcpp.exe lives in repo\bin, three levels above the editor's
// resources dir (res\editor\resources -> res\editor -> res -> bin). It is
// spawned with cwd = repo\bin so its default 'output' dir matches a console
// build. One build/run at a time; with -r pcpp.exe blocks until the program
// exits, so Stop kills the whole process tree (compiler + program).
const PC_BIN_DIR = path.resolve(process.resourcesPath, '..', '..', '..');
const PC_COMPILER = path.join(PC_BIN_DIR, 'pcpp.exe');
// pcpp -opt <level> (PC_DIRECTIVE_VALUES optimize) and -t <triple> (the
// official targets, DESIGN.md sec 7); the first of each is the default
const PC_BUILD_MODES = ['debug', 'safe', 'fast', 'small'];
// A toolbar level saved before the 2026-10-18 rename (PC_RETIRED_VALUES in
// PaskalCPP.Common): mapped once when state.json is read, saved in the new
// name by the next saveState; pcpp itself never takes an old name
const PC_RETIRED_BUILD_MODES = { release_safe: 'safe', release_fast: 'fast', release_small: 'small' };
const PC_BUILD_TARGETS = ['x86_64-windows-gnu', 'x86_64-linux-gnu'];
// Any CSI escape (colours, cursor moves, clear line, DEC private modes) -
// OUTPUT is plain text
const PC_ESC_RE = /\x1b\[[0-9;?]*[A-Za-z]/g;
// The two CSI escapes OUTPUT performs instead of stripping: ESC[1A (cursor up
// one line) and ESC[2K (erase the line), as pcpp's in-place progress draws
// (PaskalCPP.CLI DoProgress); shell.js output() acts on them
const PC_LINE_RE = /^\x1b\[(?:1A|2K)$/;
// Any OSC sequence (a program run through pcpp -r comes over a pseudoconsole,
// which sets the window title: ESC ] 0;title BEL), ended by BEL or ESC \
const PC_OSC_RE = /\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g;
// An escape cut off at the end of a chunk: ESC, ESC [ params with no final,
// or an OSC with no terminator yet (its body may end in the ESC of an ESC \
// still to come; a complete ESC \ ends it, so it is never held)
const PC_ESC_TAIL_RE = /\x1b(\[[0-9;?]*|\](?:[^\x07\x1b]|\x1b(?!\\))*)?$/;

// { proc, stopped } while a build/run is active, else null
let gBuild = null;

// One filter per stream: pipe chunks split anywhere, so an escape or a
// \r\n pair can straddle two chunks. The unfinished tail is held back and
// prepended to the next chunk; flush() releases it when the stream ends.
function createOutputFilter() {
  let LHeld = '';

  function clean(AText) {
    // OSC and CSI escapes stripped, except the line redraw OUTPUT performs
    // (PC_LINE_RE: line up, erase line); bare \r passes to the renderer too
    return AText.replace(PC_OSC_RE, '').replace(PC_ESC_RE, (AMatch) =>
      (PC_LINE_RE.test(AMatch) ? AMatch : ''));
  }

  return {
    push: (AText) => {
      let LText = LHeld + AText;
      const LMatch = PC_ESC_TAIL_RE.exec(LText);
      LHeld = '';
      if (LMatch) {
        LHeld = LText.slice(LMatch.index);
        LText = LText.slice(0, LMatch.index);
      }
      // A trailing \r may be the first half of \r\n: decide next chunk
      if (LText.endsWith('\r')) {
        LHeld = '\r' + LHeld;
        LText = LText.slice(0, -1);
      }
      return clean(LText);
    },
    flush: () => {
      const LText = LHeld.replace(PC_ESC_TAIL_RE, '');
      LHeld = '';
      return clean(LText);
    }
  };
}

// Filtered text only; an all-held chunk yields '' and sends nothing
function sendText(AText) {
  if (AText.length > 0) {
    sendWindow('build:output', AText);
  }
}

function stopBuild() {
  if (!gBuild) {
    return false;
  }
  gBuild.stopped = true;
  try {
    if (process.platform === 'win32') {
      // /T takes the Electron game started by -r down with the compiler
      spawn('taskkill', ['/PID', String(gBuild.proc.pid), '/T', '/F'], { windowsHide: true });
    } else {
      gBuild.proc.kill();
    }
  } catch (AError) {
    sendWindow('build:output', 'Stop failed: ' + AError.message + '\n');
    return false;
  }
  return true;
}

// LSP: one server for the editor's lifetime (lsp-host.js runs pcpp.exe
// --lsp itself, so pcpp is rebuilt with the editor closed); every message
// and state change is relayed to the renderer as it happens
let gLsp = null;
// The server's file watchers (lsp-watch.js): main answers its
// register / unregister requests itself; a change goes back to it as
// workspace/didChangeWatchedFiles
let gLspWatch = null;
const PC_LSP_REGISTER = 'client/registerCapability';
const PC_LSP_UNREGISTER = 'client/unregisterCapability';
const PC_LSP_WATCHED = 'workspace/didChangeWatchedFiles';

function onLspWatchRequest(AMsg) {
  const LParams = AMsg.params || {};
  let LList;

  if (AMsg.method === PC_LSP_REGISTER) {
    LList = Array.isArray(LParams.registrations) ? LParams.registrations : [];
    for (const LItem of LList) {
      if (LItem && LItem.method === PC_LSP_WATCHED) {
        gLspWatch.register(LItem.id, LItem.registerOptions && LItem.registerOptions.watchers);
      }
    }
  } else {
    // LSP 3.17 spells it 'unregisterations'; the corrected spelling is taken too
    LList = LParams.unregisterations || LParams.unregistrations;
    for (const LItem of (Array.isArray(LList) ? LList : [])) {
      if (LItem && LItem.method === PC_LSP_WATCHED) {
        gLspWatch.unregister(LItem.id);
      }
    }
  }
  gLsp.send({ jsonrpc: '2.0', id: AMsg.id, result: null });
}

function onLspMessage(AMsg) {
  if (AMsg && typeof AMsg === 'object' && AMsg.id !== undefined &&
      (AMsg.method === PC_LSP_REGISTER || AMsg.method === PC_LSP_UNREGISTER)) {
    onLspWatchRequest(AMsg);
    return;
  }
  sendWindow('lsp:message', AMsg);
}

function onLspState(AState) {
  // A stopped or restarting server's watchers are not its successor's
  if (AState && AState.state !== 'running') {
    gLspWatch.clear();
  }
  sendWindow('lsp:state', AState);
}

ipcMain.on('lsp:send', (AEvent, AMsg) => {
  if (gLsp && AMsg && typeof AMsg === 'object') {
    gLsp.send(AMsg);
  }
});

ipcMain.handle('lsp:state', () => (gLsp ? gLsp.state() : { state: 'stopped', detail: '' }));

// DAP: one debug session at a time (dap-host.js runs pcpp.exe --dap for
// it); messages and state changes are relayed as they happen. A session and
// a build / run refuse each other: both build into pcpp's output folder
let gDap = null;

function dapRunning() {
  return !!(gDap && gDap.proc());
}

ipcMain.handle('dap:start', () => {
  if (gBuild) {
    return { ok: false, error: 'A build or run is already active.' };
  }
  if (!gDap || !gDap.start()) {
    return { ok: false, error: gDap ? (gDap.state().detail || 'A debug session is already active.') : 'No debugger.' };
  }
  return { ok: true, error: '' };
});

// A launch is rebuilt from what checkLaunchArgs passes (build:start's rule:
// the renderer is not trusted with what pcpp builds and runs)
ipcMain.on('dap:send', (AEvent, AMsg) => {
  let LCheck;

  if (!gDap || !AMsg || typeof AMsg !== 'object') {
    return;
  }
  if (AMsg.type === 'request' && AMsg.command === 'launch') {
    LCheck = checkLaunchArgs(AMsg.arguments);
    if (!LCheck.args) {
      // Answered here as the adapter would: the renderer waits for it
      sendWindow('dap:message', {
        seq: 0, type: 'response', request_seq: AMsg.seq, success: false, command: 'launch', message: LCheck.error
      });
      return;
    }
    gDap.send({ seq: AMsg.seq, type: 'request', command: 'launch', arguments: LCheck.args });
    return;
  }
  gDap.send(AMsg);
});

ipcMain.on('dap:stop', () => {
  if (gDap) {
    gDap.stop();
  }
});

ipcMain.handle('dap:state', () => (gDap ? gDap.state() : { state: 'stopped', detail: '' }));

// Debug hosts of dll sources (e6h). The renderer names the source only:
// the host comes from state.json or from main's own dialog, never from the
// renderer (the launch check still requires an existing .exe)
function isSourceArg(ASource) {
  return typeof ASource === 'string' && path.isAbsolute(ASource);
}

// The host remembered for ASource ('' = none; one whose exe is gone is
// forgotten)
ipcMain.handle('dap:hostFor', (AEvent, ASource) => {
  let LRes;

  if (!isSourceArg(ASource)) {
    return '';
  }
  LRes = hostFor(gState.debugHosts, ASource);
  if (LRes.changed) {
    saveState();
  }
  return LRes.host;
});

// Asks for ASource's host exe and remembers it: { ok, canceled, host, error }
ipcMain.handle('dap:pickHost', async (AEvent, ASource) => {
  let LRes;
  let LHost;

  if (!isSourceArg(ASource)) {
    return { ok: false, canceled: false, host: '', error: 'Not a source path: ' + String(ASource) };
  }
  LRes = await dialog.showOpenDialog(gWindow, {
    title: 'Host program (.exe) that loads the dll of ' + path.basename(ASource),
    defaultPath: dialogDir() || path.dirname(ASource),
    filters: [{ name: 'Programs', extensions: ['exe'] }],
    properties: ['openFile']
  });
  if (LRes.canceled || LRes.filePaths.length === 0) {
    return { ok: false, canceled: true, host: '', error: '' };
  }
  LHost = LRes.filePaths[0];
  // A typed name can get past the dialog's filter
  if (!isHostExe(LHost)) {
    return { ok: false, canceled: false, host: '', error: 'Not an existing .exe: ' + LHost };
  }
  gState.debugHosts[debugHostKey(ASource)] = LHost;
  // rememberDialogDir saves the state, the host included
  rememberDialogDir(path.dirname(LHost));
  return { ok: true, canceled: false, host: LHost, error: '' };
});

// Forgets ASource's host (the program is an exe now)
ipcMain.handle('dap:forgetHost', (AEvent, ASource) => {
  const LKey = isSourceArg(ASource) ? debugHostKey(ASource) : '';

  if (LKey === '' || !(LKey in gState.debugHosts)) {
    return false;
  }
  delete gState.debugHosts[LKey];
  saveState();
  return true;
});

// AOpts = { file, mode, target, run, cols, rows }; everything is validated
// here, the renderer is not trusted with the command line. A Run's program
// gets the TERMINAL tab as its terminal (run-term.js: cols / rows its size
// now): its output comes as run:output after run:connect, keys and sizes go
// back by run:input / run:resize; pcpp's own lines stay in OUTPUT
ipcMain.handle('build:start', async (AEvent, AOpts) => {
  const LOpts = AOpts || {};
  const LArgs = [];
  let LProc;
  let LFinished = false;
  let LOutFilter;
  let LErrFilter;
  let LTerminal = null;

  if (gBuild) {
    return { ok: false, error: 'A build or run is already active.' };
  }
  if (dapRunning()) {
    return { ok: false, error: 'A debug session is active: stop it first (Shift+F5).' };
  }
  if (typeof LOpts.file !== 'string' || !path.isAbsolute(LOpts.file) ||
      path.extname(LOpts.file).toLowerCase() !== '.pcpp' || !fs.existsSync(LOpts.file)) {
    return { ok: false, error: 'Not a saved .pcpp file: ' + String(LOpts.file) };
  }
  if (!PC_BUILD_MODES.includes(LOpts.mode) || !PC_BUILD_TARGETS.includes(LOpts.target)) {
    return { ok: false, error: 'Invalid optimize level or target.' };
  }
  if (!fs.existsSync(PC_COMPILER)) {
    return { ok: false, error: 'Compiler not found: ' + PC_COMPILER };
  }

  // --defaults: the toolbar's level / target only stand in where the source
  // has no @optimize / @target (the source wins in the editor; from the
  // command line -opt / -t override it). --progress: pcpp draws its
  // 'Building <name>... Ns' line in place over the pipe, as on a console
  // (OUTPUT redraws it: PC_LINE_RE)
  LArgs.push(LOpts.file, '-opt', LOpts.mode, '-t', LOpts.target, '--defaults', '--progress');
  if (LOpts.run === true) {
    LTerminal = createRunTerminal({
      onConnect: () => sendWindow('run:connect'),
      onOutput: (AText) => sendWindow('run:output', AText)
    }, LOpts.cols, LOpts.rows);
    try {
      await LTerminal.listen();
    } catch (AError) {
      LTerminal.close();
      return { ok: false, error: 'The program\'s terminal cannot open: ' + AError.message };
    }
    LArgs.push('-r', '--terminal', LTerminal.name);
  }

  // Echoed from here so it is always the first OUTPUT line (send order holds)
  sendWindow('build:output', '> pcpp ' + LArgs.join(' ') + '\n');
  try {
    LProc = spawn(PC_COMPILER, LArgs, {
      cwd: PC_BIN_DIR,
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
  } catch (AError) {
    if (LTerminal !== null) {
      LTerminal.close();
    }
    return { ok: false, error: AError.message };
  }
  gBuild = { proc: LProc, stopped: false, terminal: LTerminal };

  // Both 'error' and 'close' can fire for one process: report exit once
  function finish(ACode) {
    let LStopped;
    if (LFinished) {
      return;
    }
    LFinished = true;
    LStopped = gBuild ? gBuild.stopped : false;
    gBuild = null;
    if (LTerminal !== null) {
      LTerminal.close();
    }
    sendWindow('build:exit', { code: ACode, stopped: LStopped });
  }

  // setEncoding decodes UTF-8 across chunk boundaries (banner glyphs, emoji)
  LProc.stdout.setEncoding('utf8');
  LProc.stderr.setEncoding('utf8');
  LOutFilter = createOutputFilter();
  LErrFilter = createOutputFilter();
  LProc.stdout.on('data', (AText) => sendText(LOutFilter.push(AText)));
  LProc.stderr.on('data', (AText) => sendText(LErrFilter.push(AText)));
  LProc.on('error', (AError) => {
    sendWindow('build:output', 'Failed to start compiler: ' + AError.message + '\n');
    finish(-1);
  });
  // 'close' fires after both streams ended: release any held tails first
  LProc.on('close', (ACode) => {
    sendText(LOutFilter.flush());
    sendText(LErrFilter.flush());
    finish(ACode === null ? -1 : ACode);
  });

  return { ok: true, command: 'pcpp ' + LArgs.join(' ') };
});

ipcMain.handle('build:stop', async () => stopBuild());

// The TERMINAL tab's keys and size, for a Run's program (nothing without one)
ipcMain.on('run:input', (AEvent, AText) => {
  if (gBuild && gBuild.terminal && typeof AText === 'string') {
    gBuild.terminal.input(AText);
  }
});

ipcMain.on('run:resize', (AEvent, ACols, ARows) => {
  if (gBuild && gBuild.terminal && Number.isInteger(ACols) && Number.isInteger(ARows)) {
    gBuild.terminal.resize(ACols, ARows);
  }
});

// The packed package.json carries the version and the About strings
// pcppdev wrote from PaskalCPP.Common (one source): the About box and the
// issue reporter both read it here
function appPackage() {
  try {
    return require('./package.json');
  } catch (AErr) {
    return {};
  }
}

// About box
ipcMain.handle('app:info', async () => {
  const LPkg = appPackage();
  const LAbout = LPkg.about || {};
  return {
    product: LAbout.product || '',
    version: LPkg.version || '',
    copyright: LAbout.copyright || '',
    url: LAbout.url || '',
    electron: process.versions.electron,
    chrome: process.versions.chrome,
    node: process.versions.node
  };
});

// A link the renderer draws itself (About box): http(s) only
ipcMain.handle('url:open', async (AEvent, AUrl) => openWebUrl(AUrl));

// Layout + toolbar choices: the renderer applies them once at boot and
// reports every change (sash drag end, panel collapse, dropdown change)
ipcMain.handle('ui:get', async () => ({ layout: gState.layout, build: gState.build }));
ipcMain.handle('settings:get', async () => gSettings);

ipcMain.on('layout:set', (AEvent, AData) => {
  const LLayout = validLayout(AData);
  if (LLayout) {
    gState.layout = LLayout;
    saveState();
  }
});

ipcMain.on('build:choice', (AEvent, AData) => {
  const LBuild = validBuild(AData);
  if (LBuild) {
    gState.build = LBuild;
    saveState();
  }
});

// True when ARect overlaps some display's work area by a grabbable amount:
// a rect saved on an unplugged monitor is dropped (default placement)
function isOnScreen(ARect) {
  const LMinOverlapW = 100;
  const LMinOverlapH = 50;
  return screen.getAllDisplays().some((ADisplay) => {
    const LArea = ADisplay.workArea;
    const LOverlapW = Math.min(ARect.x + ARect.width, LArea.x + LArea.width) - Math.max(ARect.x, LArea.x);
    const LOverlapH = Math.min(ARect.y + ARect.height, LArea.y + LArea.height) - Math.max(ARect.y, LArea.y);
    return LOverlapW >= LMinOverlapW && LOverlapH >= LMinOverlapH;
  });
}

// Maximized state as the user left it: a minimized window reports
// isMaximized() false, so track the maximize / unmaximize events instead
let gMaximized = false;

// Saves the window: on each change and on a real close
function rememberWindow() {
  const LBounds = gWindow.getNormalBounds();
  gState.window = { x: LBounds.x, y: LBounds.y, width: LBounds.width, height: LBounds.height, maximized: gMaximized };
  saveState();
}

function createWindow() {
  // Saved bounds only when still on a display; otherwise default size,
  // centered (Electron centers a window created without x/y)
  const LSaved = gState.window && isOnScreen(gState.window) ? gState.window : null;
  gWindow = new BrowserWindow({
    x: LSaved ? LSaved.x : undefined,
    y: LSaved ? LSaved.y : undefined,
    width: LSaved ? LSaved.width : 1280,
    height: LSaved ? LSaved.height : 800,
    backgroundColor: '#1e1e1e',
    title: 'PaskalCPP Editor',
    // Window/taskbar/Alt+Tab icon (the exe file's own icon is embedded in editor.exe)
    icon: path.join(__dirname, 'assets', 'icon.ico'),
    // Frameless: our HTML title bar, Windows draws min/max/close over it.
    // Overlay colours match --pc-bg-chrome / --pc-fg in src/editor.css.
    titleBarStyle: 'hidden',
    titleBarOverlay: { color: '#181818', symbolColor: '#cccccc', height: 32 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });

  gMaximized = LSaved !== null && LSaved.maximized;
  gWindow.on('maximize', () => { gMaximized = true; rememberWindow(); });
  gWindow.on('unmaximize', () => { gMaximized = false; rememberWindow(); });
  // Saved on each change like the Delphi IDE: 'moved' / 'resized' fire once
  // when a move / resize ends (Windows), never during the drag
  gWindow.on('moved', rememberWindow);
  gWindow.on('resized', rememberWindow);
  // The window is created visible (never hidden: a missed ready-to-show
  // would leave it invisible); a saved maximized state is applied at once
  if (gMaximized) {
    gWindow.maximize();
  }

  // The menu bar is hidden; its accelerators stay registered (R2 D2)
  gWindow.setMenuBarVisibility(false);

  // The editor window never navigates away. A link that asks for a new
  // window (Ctrl+click in Monaco) opens in the user's default browser when
  // it is http(s); the window itself is always denied.
  gWindow.webContents.on('will-navigate', (AEvent) => AEvent.preventDefault());
  gWindow.webContents.setWindowOpenHandler((ADetails) => {
    openWebUrl(ADetails.url);
    return { action: 'deny' };
  });

  gWindow.on('close', (AEvent) => {
    if (!gDirty || gForceClose) {
      rememberWindow();
      return;
    }
    const LChoice = dialog.showMessageBoxSync(gWindow, {
      type: 'warning',
      buttons: ['Discard changes', 'Cancel'],
      defaultId: 1,
      cancelId: 1,
      message: 'You have unsaved changes.',
      detail: 'Close the editor and discard them?'
    });
    if (LChoice === 0) {
      gForceClose = true;
      rememberWindow();
    } else {
      AEvent.preventDefault();
    }
  });

  gWindow.on('closed', () => { gWindow = null; });
  gWindow.loadFile(path.join(__dirname, 'index.html'));
}

// One instance per profile: a second launch would fight the first over the
// user-data cache ("Unable to move the cache"). It focuses the running one
// and hands it the files on its command line.
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', (AEvent, AArgv, AWorkingDirectory) => {
    if (gWindow) {
      if (gWindow.isMinimized()) {
        gWindow.restore();
      }
      gWindow.focus();
    }
    const LFiles = argFiles(AArgv.slice(1), AWorkingDirectory);
    if (LFiles.length > 0) {
      sendWindow('file:openArgs', LFiles);
    }
  });

  app.whenReady().then(() => {
    loadState();
    loadSettings();
    buildMenu();
    createWindow();
    gLspWatch = createLspWatch({
      onChanged: () => {
        if (gLsp) {
          gLsp.send({ jsonrpc: '2.0', method: PC_LSP_WATCHED, params: { changes: [] } });
        }
      }
    });
    gLsp = createLspHost({
      binDir: PC_BIN_DIR,
      onMessage: onLspMessage,
      onState: onLspState
    });
    gLsp.start();
    // Started per session (dap:start), never here
    gDap = createDapHost({
      binDir: PC_BIN_DIR,
      onMessage: (AMsg) => sendWindow('dap:message', AMsg),
      onState: (AState) => sendWindow('dap:state', AState)
    });
  });
}

app.on('window-all-closed', () => app.quit());

// Never leave pcpp.exe, a running game, the LSP or a debug session behind
// the editor
app.on('before-quit', () => {
  stopBuild();
  if (gLsp) {
    gLsp.stop();
  }
  if (gDap) {
    gDap.stop();
  }
});
