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

  PaskalCPP Editor - preload bridge.

  The only surface the renderer sees: window.host. Every call is a narrow
  IPC request; no Node API reaches the page.
*/
'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('host', {
  openFile: () => ipcRenderer.invoke('file:open'),
  saveFile: (AFilename, AText) => ipcRenderer.invoke('file:save', AFilename, AText),
  saveFileAs: (AText, ASuggested) => ipcRenderer.invoke('file:saveAs', AText, ASuggested),
  renameFile: (AFilename) => ipcRenderer.invoke('file:rename', AFilename),
  // the command-line files: [{ path, text }] at start, then the paths a
  // second launch (pcpp editor <files>) hands over
  initialFiles: () => ipcRenderer.invoke('file:initial'),
  onOpenFiles: (ACallback) => {
    ipcRenderer.on('file:openArgs', (AEvent, APaths) => ACallback(APaths));
  },
  readFile: (AFilename) => ipcRenderer.invoke('file:read', AFilename),
  // Explorer folders: each call resolves to { folders } = the whole list
  openFolder: () => ipcRenderer.invoke('folder:open'),
  closeFolder: (APath) => ipcRenderer.invoke('folder:close', APath),
  closeAllFolders: () => ipcRenderer.invoke('folders:closeAll'),
  folderList: () => ipcRenderer.invoke('folders:list'),
  // The explorer's open folders (roots included), the whole set each time
  setExplorerOpen: (AKeys) => ipcRenderer.send('explorer:open', AKeys),
  examplesFolder: () => ipcRenderer.invoke('folder:examples'),
  showExamples: (AOn) => ipcRenderer.invoke('examples:show', AOn),
  listFolder: (ADir) => ipcRenderer.invoke('folder:list', ADir),
  watchFolders: (ARoots) => ipcRenderer.invoke('folder:watch', ARoots),
  onFolderChanged: (ACallback) => {
    ipcRenderer.on('folder:changed', (AEvent, ADirs) => ACallback(ADirs));
  },
  // The open tabs' files, the whole set each time; changes come back as
  // [{ path, exists }]
  watchFiles: (AFiles) => ipcRenderer.invoke('file:watch', AFiles),
  onFileChanged: (ACallback) => {
    ipcRenderer.on('file:changed', (AEvent, AChanges) => ACallback(AChanges));
  },
  saveSession: (AFiles, AActive) => ipcRenderer.send('session:save', AFiles, AActive),
  loadSession: () => ipcRenderer.invoke('session:load'),
  setDocState: (AState) => ipcRenderer.send('doc:state', AState),
  // About box data; an http(s) link opened in the default browser
  appInfo: () => ipcRenderer.invoke('app:info'),
  openUrl: (AUrl) => ipcRenderer.invoke('url:open', AUrl),
  // Issue reporter: open it (code '' = none), or a PROBLEMS row's own menu
  reportIssue: (ACode) => ipcRenderer.send('report:open', ACode),
  problemMenu: (ACode) => ipcRenderer.send('problem:menu', ACode),
  // Layout + toolbar choices: { layout, build } once at boot, then each change
  getUiState: () => ipcRenderer.invoke('ui:get'),
  setLayout: (ALayout) => ipcRenderer.send('layout:set', ALayout),
  setBuildChoice: (AChoice) => ipcRenderer.send('build:choice', AChoice),
  popupMenu: (AX, AY) => ipcRenderer.send('menu:popup', AX, AY),
  onMenu: (ACallback) => {
    ipcRenderer.on('menu', (AEvent, ACommand) => ACallback(ACommand));
  },
  // Editor settings (data\settings.json): once at boot, then after each save
  // of it; settings:open asks the renderer to open the file in a tab
  getSettings: () => ipcRenderer.invoke('settings:get'),
  onSettingsChanged: (ACallback) => {
    ipcRenderer.on('settings:changed', (AEvent, ASettings) => ACallback(ASettings));
  },
  onSettingsOpen: (ACallback) => {
    ipcRenderer.on('settings:open', (AEvent, APath) => ACallback(APath));
  },
  buildStart: (AOpts) => ipcRenderer.invoke('build:start', AOpts),
  buildStop: () => ipcRenderer.invoke('build:stop'),
  onBuildOutput: (ACallback) => {
    ipcRenderer.on('build:output', (AEvent, AText) => ACallback(AText));
  },
  onBuildExit: (ACallback) => {
    ipcRenderer.on('build:exit', (AEvent, AInfo) => ACallback(AInfo));
  },
  // Run's program terminal (run-term.js): it connected, its output; the
  // TERMINAL tab's keys and size back
  onRunConnect: (ACallback) => {
    ipcRenderer.on('run:connect', () => ACallback());
  },
  onRunOutput: (ACallback) => {
    ipcRenderer.on('run:output', (AEvent, AText) => ACallback(AText));
  },
  runInput: (AText) => ipcRenderer.send('run:input', AText),
  runResize: (ACols, ARows) => ipcRenderer.send('run:resize', ACols, ARows),
  // LSP: JSON-RPC objects both ways; main.js does the framing
  lspSend: (AMsg) => ipcRenderer.send('lsp:send', AMsg),
  lspState: () => ipcRenderer.invoke('lsp:state'),
  onLspMessage: (ACallback) => {
    ipcRenderer.on('lsp:message', (AEvent, AMsg) => ACallback(AMsg));
  },
  onLspState: (ACallback) => {
    ipcRenderer.on('lsp:state', (AEvent, AState) => ACallback(AState));
  },
  // DAP: protocol objects both ways; main.js does the framing and checks a
  // launch. dapStart runs the adapter for one session ({ ok, error })
  dapStart: () => ipcRenderer.invoke('dap:start'),
  dapSend: (AMsg) => ipcRenderer.send('dap:send', AMsg),
  dapStop: () => ipcRenderer.send('dap:stop'),
  dapState: () => ipcRenderer.invoke('dap:state'),
  // A dll source's host exe: remembered ('' = none), picked in main's own
  // dialog ({ ok, canceled, host, error }), forgotten
  dapHostFor: (ASource) => ipcRenderer.invoke('dap:hostFor', ASource),
  dapPickHost: (ASource) => ipcRenderer.invoke('dap:pickHost', ASource),
  dapForgetHost: (ASource) => ipcRenderer.invoke('dap:forgetHost', ASource),
  onDapMessage: (ACallback) => {
    ipcRenderer.on('dap:message', (AEvent, AMsg) => ACallback(AMsg));
  },
  onDapState: (ACallback) => {
    ipcRenderer.on('dap:state', (AEvent, AState) => ACallback(AState));
  }
});
