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

  PaskalCPP Editor - explorer (file tree).

  Roots: the opened folders (any number, a list main.js owns and remembers
  between launches; setFolders shows exactly that list) and the bundled
  EXAMPLES; each has a close x (the caller's callbacks decide what closing
  means). Folders load lazily on first expand; all file
  system access is main.js (window.host.listFolder). Clicking a file calls
  the AOnOpenFile callback given to init; the explorer never opens
  documents itself. The active tab's file is highlighted via setActive.
  main.js watches the shown roots (window.host.watchFolders) and reports
  changed directories; each loaded one is re-listed in place, keeping
  expanded folders. The refresh button re-lists everything loaded.
  Which folders are open (roots included) is remembered between launches
  (window.host.setExplorerOpen); at startup the tree comes back as it was
  left and the restored active tab is not revealed (endRestore ends that).
*/
'use strict';

var PcExplorer = (function () {
  var PC_INDENT_BASE = 8;
  var PC_INDENT_STEP = 12;

  var gOnOpenFile = null;
  var gOnOpenFolder = null;
  var gOnCloseFolder = null;
  var gOnCloseExamples = null;
  var gActiveKey = '';
  // Lower-cased file path -> its rows (a file can show in both roots when
  // the opened folder overlaps EXAMPLES), for the active highlight
  var gRows = {};
  // Lower-cased dir path -> the listings showing it: { container, dir,
  // depth, nodes (entry name -> node), seq, loading (newest list promise) }.
  // One per loaded (expanded at least once) directory, so a change on disk
  // can re-list exactly it. A list, because the same dir can show in both
  // roots.
  var gDirs = {};
  // Folder roots shown, in order: { key (lower-cased path), path, box (its
  // section element) }; with the EXAMPLES root, handed to main.js to watch
  var gFolderRoots = [];
  var gExamplesRoot = '';
  // The official examples folder (main.js names it even while hidden or
  // missing): its open folders are never forgotten
  var gExamplesHome = '';
  // Active file path (as given); a root added later that holds it reveals
  // it there (retryReveal)
  var gActivePath = '';
  // Newest reveal: an older one still walking the tree stops
  var gRevealSeq = 0;
  // Open folders, roots included: revealKey -> true. main.js stores the
  // whole set (state.json). gRemembered = a set was ever saved; never saved
  // = every root opens (first launch).
  var gExpanded = {};
  var gRemembered = false;
  // Startup: roots and tabs come back as they were left, nothing is
  // revealed. Ends once init has shown the roots AND the renderer has
  // restored its tabs (endRestore), in either order.
  var gRestoring = true;
  var gInitDone = false;
  var gRestoreEnded = false;

  function byId(AId) {
    return document.getElementById(AId);
  }

  // Windows paths compare case-insensitively
  function pathKey(APath) {
    return APath ? APath.toLowerCase() : '';
  }

  function baseName(APath) {
    var LParts = APath.split(/[\\/]/);
    return LParts[LParts.length - 1] || APath;
  }

  function isSource(AName) {
    return AName.toLowerCase().endsWith('.pcpp');
  }

  function makeMessageRow(AText, ADepth) {
    var LRow = document.createElement('div');
    LRow.className = 'tree-msg';
    LRow.style.paddingLeft = (PC_INDENT_BASE + ADepth * PC_INDENT_STEP + 16) + 'px';
    LRow.textContent = AText;
    return LRow;
  }

  // The listing record of AContainer showing ADir, created on first load
  function dirListing(AContainer, ADir, ADepth) {
    var LKey = pathKey(ADir);
    var LList = gDirs[LKey] || [];
    var LIndex;
    var LListing;

    for (LIndex = 0; LIndex < LList.length; LIndex++) {
      if (LList[LIndex].container === AContainer) {
        return LList[LIndex];
      }
    }
    LListing = { container: AContainer, dir: ADir, depth: ADepth, nodes: {}, seq: 0 };
    LList.push(LListing);
    gDirs[LKey] = LList;
    return LListing;
  }

  // Listings whose container left the document (parent re-listed without
  // it, root replaced) can never show again: forget them
  function pruneDirs() {
    var LKey;
    for (LKey in gDirs) {
      gDirs[LKey] = gDirs[LKey].filter(function (AListing) {
        return AListing.container.isConnected;
      });
      if (gDirs[LKey].length === 0) {
        delete gDirs[LKey];
      }
    }
  }

  // True when ADir is one of the folder roots shown (EXAMPLES is not one)
  function isFolderRoot(ADir) {
    var LKey = pathKey(ADir);
    var LIndex;

    for (LIndex = 0; LIndex < gFolderRoots.length; LIndex++) {
      if (gFolderRoots[LIndex].key === LKey) {
        return true;
      }
    }
    return false;
  }

  // True when APath is the official examples folder or inside it
  function isExamplesPath(APath) {
    var LHome = revealKey(gExamplesHome);
    var LKey = revealKey(APath);

    return LHome !== '' && (LKey === LHome || LKey.indexOf(LHome + '\\') === 0);
  }

  function showMessage(AListing, AText) {
    AListing.nodes = {};
    AListing.container.replaceChildren(makeMessageRow(AText, AListing.depth));
  }

  // Fills AContainer with the entries of ADir (one level). A re-list is a
  // diff: an entry still present keeps its node, so expanded subfolders
  // and the active highlight survive; new entries get new nodes, gone
  // ones are dropped.
  async function loadChildren(AContainer, ADir, ADepth) {
    var LListing = dirListing(AContainer, ADir, ADepth);
    var LSeq;
    var LRes;
    var LNodes = {};
    var LOrder = [];
    var LIndex;
    var LEntry;
    var LNodeKey;
    var LNode;

    // Only the newest of overlapping re-lists of one listing may apply
    LListing.seq = LListing.seq + 1;
    LSeq = LListing.seq;
    LRes = await window.host.listFolder(ADir);
    if (LSeq !== LListing.seq || !AContainer.isConnected) {
      return;
    }

    // A directory that no longer exists is never shown dead:
    // - the EXAMPLES root: its section is hidden, not closed by its x, so
    //   nothing about the official folder is forgotten;
    // - a folder root at the examples folder: hidden the same way, by
    //   showing main.js's list again (main.js keeps it, shows only what
    //   exists);
    // - any other folder root: forgotten, as by its x;
    // - a subfolder: shows nothing; its row goes with its parent's re-list
    //   (the same disk change).
    if (!LRes.ok && LRes.missing) {
      if (ADepth === 0 && byId('tree-examples').contains(AContainer)) {
        setExamples('');
        return;
      }
      if (ADepth === 0 && isFolderRoot(ADir)) {
        if (isExamplesPath(ADir)) {
          window.host.folderList().then(function (AList) {
            setFolders(AList.ok ? AList.folders : []);
          });
        } else {
          folderCloser(ADir)();
        }
        return;
      }
      LListing.nodes = {};
      AContainer.replaceChildren();
      pruneRows();
      pruneDirs();
      return;
    }

    if (!LRes.ok) {
      showMessage(LListing, 'Cannot read folder: ' + (LRes.error || ''));
    } else if (LRes.entries.length === 0) {
      showMessage(LListing, '(empty)');
    } else {
      for (LIndex = 0; LIndex < LRes.entries.length; LIndex++) {
        LEntry = LRes.entries[LIndex];
        // Exact name + kind: a case-only rename or a file replaced by a
        // folder of the same name is a new node
        LNodeKey = (LEntry.isDir ? 'd:' : 'f:') + LEntry.name;
        LNode = LListing.nodes[LNodeKey];
        if (!LNode) {
          LNode = makeNode(LEntry, ADepth);
        }
        LNodes[LNodeKey] = LNode;
        LOrder.push(LNode);
      }
      LListing.nodes = LNodes;
      AContainer.replaceChildren.apply(AContainer, LOrder);
    }
    pruneRows();
    pruneDirs();
  }

  // Every (re-)list goes through here: the listing keeps the newest list
  // promise, so a reveal can wait for a listing still in flight
  function startLoad(AContainer, ADir, ADepth) {
    var LListing = dirListing(AContainer, ADir, ADepth);
    LListing.loading = loadChildren(AContainer, ADir, ADepth);
    return LListing.loading;
  }

  // Waits until AListing has no newer list in flight: a re-list started
  // while waiting supersedes the awaited one (its seq guard drops it)
  async function settled(AListing) {
    var LLoad;
    do {
      LLoad = AListing.loading;
      await LLoad;
    } while (AListing.loading !== LLoad);
  }

  // Re-lists every shown listing of each dir in ADirs that is loaded;
  // dirs never expanded load fresh on their first expand anyway
  function relistDirs(ADirs) {
    var LIndex;
    var LList;
    var LItem;

    for (LIndex = 0; LIndex < ADirs.length; LIndex++) {
      LList = gDirs[pathKey(ADirs[LIndex])] || [];
      for (LItem = 0; LItem < LList.length; LItem++) {
        startLoad(LList[LItem].container, LList[LItem].dir, LList[LItem].depth);
      }
    }
  }

  // Re-lists everything loaded (the refresh button)
  function refresh() {
    var LKey;
    var LDirs = [];
    for (LKey in gDirs) {
      LDirs.push(gDirs[LKey][0].dir);
    }
    relistDirs(LDirs);
  }

  function watchRoots() {
    var LRoots = [];
    var LIndex;
    for (LIndex = 0; LIndex < gFolderRoots.length; LIndex++) {
      LRoots.push(gFolderRoots[LIndex].path);
    }
    if (gExamplesRoot) {
      LRoots.push(gExamplesRoot);
    }
    // Watch failures leave the refresh button as the fallback
    window.host.watchFolders(LRoots).catch(function () {});
  }

  // Hands the whole open set to main.js (state.json)
  function saveOpen() {
    window.host.setExplorerOpen(Object.keys(gExpanded));
  }

  // Records that the folder APath was opened or collapsed; saved only on a
  // change (a restore re-opening a remembered folder is none)
  function rememberOpen(APath, AOpen) {
    var LKey = revealKey(APath);
    if (!!gExpanded[LKey] === AOpen) {
      return;
    }
    if (AOpen) {
      gExpanded[LKey] = true;
    } else {
      delete gExpanded[LKey];
    }
    saveOpen();
  }

  // Forgets open folders no shown root holds any more (a closed root takes
  // its folders with it). Not during startup: EXAMPLES arrives after the
  // folder roots.
  function pruneOpen() {
    var LRoots = [];
    var LKey;
    var LIndex;
    var LHeld;
    var LChanged = false;

    if (gRestoring) {
      return;
    }
    for (LIndex = 0; LIndex < gFolderRoots.length; LIndex++) {
      LRoots.push(revealKey(gFolderRoots[LIndex].path));
    }
    if (gExamplesRoot) {
      LRoots.push(revealKey(gExamplesRoot));
    }
    // The official examples folder holds its open folders even while
    // EXAMPLES is closed or missing: they are never forgotten
    if (gExamplesHome) {
      LRoots.push(revealKey(gExamplesHome));
    }
    for (LKey in gExpanded) {
      LHeld = false;
      for (LIndex = 0; LIndex < LRoots.length; LIndex++) {
        if (LKey === LRoots[LIndex] || LKey.indexOf(LRoots[LIndex] + '\\') === 0) {
          LHeld = true;
        }
      }
      if (!LHeld) {
        delete gExpanded[LKey];
        LChanged = true;
      }
    }
    if (LChanged) {
      saveOpen();
    }
  }

  // Whether a root section shown for the first time starts open: at
  // startup as remembered (every root when never saved), afterwards always
  // (a folder the user just opened)
  function rootStartsOpen(APath) {
    if (gRestoring && gRemembered) {
      return !!gExpanded[revealKey(APath)];
    }
    return true;
  }

  function makeNode(AEntry, ADepth) {
    var LNode = document.createElement('div');
    var LRow = document.createElement('div');
    var LChevron = document.createElement('span');
    var LLabel = document.createElement('span');
    var LChildren;
    var LLoaded = false;

    LRow.className = 'tree-row';
    LRow.style.paddingLeft = (PC_INDENT_BASE + ADepth * PC_INDENT_STEP) + 'px';
    LRow.title = AEntry.path;
    LChevron.className = 'tree-chevron';
    LLabel.className = 'tree-label';
    LLabel.textContent = AEntry.name;
    LRow.appendChild(LChevron);
    LRow.appendChild(LLabel);
    LNode.appendChild(LRow);
    LNode.pcRow = LRow;

    if (AEntry.isDir) {
      LRow.classList.add('dir');
      LChevron.textContent = '\u203A';
      LChildren = document.createElement('div');
      LChildren.className = 'tree-children hidden';
      LNode.appendChild(LChildren);
      // Opens the folder (lists it on the first open); resolves to its
      // listing once listed. The one open path: a click and a reveal alike.
      LNode.pcExpand = async function () {
        var LListing;
        LChildren.classList.toggle('hidden', false);
        LRow.classList.toggle('expanded', true);
        rememberOpen(AEntry.path, true);
        if (!LLoaded) {
          LLoaded = true;
          startLoad(LChildren, AEntry.path, ADepth + 1);
        }
        LListing = dirListing(LChildren, AEntry.path, ADepth + 1);
        await settled(LListing);
        return LListing;
      };
      LRow.addEventListener('click', function () {
        if (LChildren.classList.contains('hidden')) {
          LNode.pcExpand();
        } else {
          LChildren.classList.toggle('hidden', true);
          LRow.classList.toggle('expanded', false);
          rememberOpen(AEntry.path, false);
        }
      });
      // A folder left open opens again; its own listing then reopens the
      // open folders below it (lazy, one level at a time)
      if (gExpanded[revealKey(AEntry.path)]) {
        LNode.pcExpand();
      }
    } else {
      LRow.classList.add('file');
      if (isSource(AEntry.name)) {
        LRow.classList.add('source');
      }
      addRow(pathKey(AEntry.path), LRow);
      if (pathKey(AEntry.path) === gActiveKey) {
        LRow.classList.add('active');
      }
      LRow.addEventListener('click', function () {
        if (gOnOpenFile) {
          gOnOpenFile(AEntry.path);
        }
      });
    }
    return LNode;
  }

  // One root section: a collapsible header and its first level, open when
  // AOpen. The first level is listed either way, so a reveal can walk a
  // collapsed root. AOnClose (optional) adds a close button to the header.
  function fillRoot(AContainer, ALabel, APath, AOnClose, AOpen) {
    var LHeader = document.createElement('div');
    var LChevron = document.createElement('span');
    var LLabel = document.createElement('span');
    var LChildren = document.createElement('div');
    var LClose;

    LHeader.className = AOpen ? 'tree-root-header expanded' : 'tree-root-header';
    LHeader.title = APath;
    LChevron.className = 'tree-chevron';
    LChevron.textContent = '\u203A';
    LLabel.textContent = ALabel;
    LHeader.appendChild(LChevron);
    LHeader.appendChild(LLabel);
    if (AOnClose) {
      LClose = document.createElement('span');
      LClose.className = 'tree-root-close';
      LClose.title = 'Close Folder';
      LClose.textContent = '\u00D7';
      LClose.addEventListener('click', function (AEvent) {
        // Closing must not also toggle the header
        AEvent.stopPropagation();
        AOnClose();
      });
      LHeader.appendChild(LClose);
    }
    LChildren.className = AOpen ? 'tree-children' : 'tree-children hidden';
    LHeader.addEventListener('click', function () {
      var LOpen = LChildren.classList.contains('hidden');
      LChildren.classList.toggle('hidden', !LOpen);
      LHeader.classList.toggle('expanded', LOpen);
      rememberOpen(APath, LOpen);
    });

    AContainer.replaceChildren(LHeader, LChildren);
    startLoad(LChildren, APath, 0);
    // A root shown open is an open folder (first launch, a folder just opened)
    if (AOpen) {
      rememberOpen(APath, true);
    }
    // Opens a collapsed section; resolves to its first-level listing once
    // listed (the root step of a reveal)
    AContainer.pcExpand = async function () {
      var LListing = dirListing(LChildren, APath, 0);
      LChildren.classList.toggle('hidden', false);
      LHeader.classList.toggle('expanded', true);
      rememberOpen(APath, true);
      await settled(LListing);
      return LListing;
    };
  }

  // The folder pane while no folder root is shown: "No folder open" and
  // the Open Folder button only when NO folder is open at all; EXAMPLES
  // shown is an open folder, so the pane stays empty then
  function showNoFolder() {
    var LContainer = byId('tree-folder');

    if (gExamplesRoot) {
      LContainer.replaceChildren();
    } else {
      fillNoFolder(LContainer);
    }
  }

  function fillNoFolder(AContainer) {
    var LBox = document.createElement('div');
    var LText = document.createElement('div');
    var LButton = document.createElement('button');

    LBox.className = 'tree-nofolder';
    LText.textContent = 'No folder open';
    LButton.className = 'tree-open-btn';
    LButton.textContent = 'Open Folder';
    LButton.addEventListener('click', function () {
      if (gOnOpenFolder) {
        gOnOpenFolder();
      }
    });
    LBox.appendChild(LText);
    LBox.appendChild(LButton);
    AContainer.replaceChildren(LBox);
  }

  function addRow(AKey, ARow) {
    if (!gRows[AKey]) {
      gRows[AKey] = [];
    }
    gRows[AKey].push(ARow);
  }

  // Rows of a rebuilt root are no longer in the document: forget them
  function pruneRows() {
    var LKey;
    for (LKey in gRows) {
      gRows[LKey] = gRows[LKey].filter(function (ARow) {
        return ARow.isConnected;
      });
      if (gRows[LKey].length === 0) {
        delete gRows[LKey];
      }
    }
  }

  // The x of the root showing APath
  function folderCloser(APath) {
    return function () {
      if (gOnCloseFolder) {
        gOnCloseFolder(APath);
      }
    };
  }

  // Shows exactly the folder roots in APaths, in that order (main.js owns
  // the list). A diff, like loadChildren: a root still listed keeps its
  // section, so its expanded folders survive; new roots get a section,
  // gone ones are dropped. Empty list = "No folder open".
  function setFolders(APaths) {
    var LContainer = byId('tree-folder');
    var LOld = gFolderRoots;
    var LNew = [];
    var LBoxes = [];
    var LAdded = [];
    var LSeen = {};
    var LIndex;
    var LOldIndex;
    var LPath;
    var LKey;
    var LRoot;

    for (LIndex = 0; LIndex < APaths.length; LIndex++) {
      LPath = APaths[LIndex];
      if (typeof LPath !== 'string' || LPath === '') {
        continue;
      }
      LKey = pathKey(LPath);
      if (LSeen[LKey]) {
        continue;
      }
      LSeen[LKey] = true;
      LRoot = null;
      for (LOldIndex = 0; LOldIndex < LOld.length; LOldIndex++) {
        if (LOld[LOldIndex].key === LKey) {
          LRoot = LOld[LOldIndex];
        }
      }
      if (!LRoot) {
        LRoot = { key: LKey, path: LPath, box: document.createElement('div') };
        LRoot.box.className = 'tree-root';
        fillRoot(LRoot.box, baseName(LPath).toUpperCase(), LPath, folderCloser(LPath), rootStartsOpen(LPath));
        LAdded.push(LPath);
      }
      LNew.push(LRoot);
      LBoxes.push(LRoot.box);
    }

    gFolderRoots = LNew;
    if (LBoxes.length === 0) {
      // During init EXAMPLES is not known yet: setExamples (always next in
      // init) decides, so the box never flashes before EXAMPLES arrives
      if (gInitDone) {
        showNoFolder();
      } else {
        LContainer.replaceChildren();
      }
    } else {
      LContainer.replaceChildren.apply(LContainer, LBoxes);
    }
    pruneRows();
    pruneDirs();
    pruneOpen();
    watchRoots();
    retryReveal(LAdded);
  }

  // EXAMPLES section: shown for a path, removed for '' (closed by the user,
  // or the examples folder missing)
  function setExamples(APath) {
    var LContainer = byId('tree-examples');
    // The same root shown again keeps its open state; a new one starts as
    // any new root does
    var LKept = !!APath && pathKey(APath) === pathKey(gExamplesRoot);
    var LOpen;

    if (APath) {
      LOpen = LKept ? !!gExpanded[revealKey(APath)] : rootStartsOpen(APath);
      fillRoot(LContainer, 'EXAMPLES', APath, function () {
        if (gOnCloseExamples) {
          gOnCloseExamples();
        }
      }, LOpen);
    } else {
      LContainer.replaceChildren();
    }
    pruneRows();
    pruneDirs();
    gExamplesRoot = APath || '';
    // With no folder root, EXAMPLES shown or gone decides the No-folder box
    if (gFolderRoots.length === 0) {
      showNoFolder();
    }
    pruneOpen();
    watchRoots();
    retryReveal(APath && !LKept ? [APath] : []);
  }

  function markRows(AKey, AOn) {
    var LList = gRows[AKey] || [];
    var LIndex;
    for (LIndex = 0; LIndex < LList.length; LIndex++) {
      LList[LIndex].classList.toggle('active', AOn);
    }
  }

  function setActive(APath) {
    var LKey = pathKey(APath);

    markRows(gActiveKey, false);
    markRows(LKey, true);
    // The same file again (every tab-state sync, e.g. a dirty edit): leave
    // the tree as the user left it
    if (LKey === gActiveKey) {
      return;
    }
    gActiveKey = LKey;
    gActivePath = APath || '';
    // Startup: the restored active tab keeps the tree as it was left
    if (!gRestoring) {
      reveal();
    }
  }

  // Lower-cased, backslash-separated, no trailing separator
  function revealKey(APath) {
    return pathKey(APath).replace(/\//g, '\\').replace(/\\+$/, '');
  }

  // The section showing APath: the first folder root containing it, else
  // EXAMPLES; null when no shown root contains it
  function revealRoot(APath) {
    var LFile = revealKey(APath);
    var LRoots = [];
    var LIndex;

    for (LIndex = 0; LIndex < gFolderRoots.length; LIndex++) {
      LRoots.push({ path: gFolderRoots[LIndex].path, box: gFolderRoots[LIndex].box });
    }
    if (gExamplesRoot) {
      LRoots.push({ path: gExamplesRoot, box: byId('tree-examples') });
    }
    for (LIndex = 0; LIndex < LRoots.length; LIndex++) {
      if (LFile.indexOf(revealKey(LRoots[LIndex].path) + '\\') === 0) {
        return LRoots[LIndex];
      }
    }
    return null;
  }

  // The node of AListing's entry of kind AKind ('d:' / 'f:') named
  // ALowerName, any case
  function findNode(AListing, AKind, ALowerName) {
    var LKey;
    for (LKey in AListing.nodes) {
      if (LKey.substring(0, 2) === AKind && LKey.substring(2).toLowerCase() === ALowerName) {
        return AListing.nodes[LKey];
      }
    }
    return null;
  }

  // Shows the active file: opens its section and every folder above it
  // (listing unloaded ones in order), then scrolls its row into view. A
  // missing folder or file (deleted, unreadable) stops silently; a newer
  // reveal stops this one.
  async function reveal() {
    var LPath = gActivePath;
    var LSeq;
    var LRoot;
    var LParts;
    var LListing;
    var LIndex;
    var LNode;

    gRevealSeq = gRevealSeq + 1;
    LSeq = gRevealSeq;
    if (!LPath) {
      return;
    }
    LRoot = revealRoot(LPath);
    if (!LRoot || !LRoot.box.pcExpand) {
      return;
    }
    // Names below the root: folders, then the file
    LParts = revealKey(LPath).substring(revealKey(LRoot.path).length + 1).split('\\');
    LListing = await LRoot.box.pcExpand();
    for (LIndex = 0; LIndex < LParts.length - 1; LIndex++) {
      if (LSeq !== gRevealSeq) {
        return;
      }
      LNode = findNode(LListing, 'd:', LParts[LIndex]);
      if (!LNode) {
        return;
      }
      LListing = await LNode.pcExpand();
    }
    if (LSeq !== gRevealSeq) {
      return;
    }
    LNode = findNode(LListing, 'f:', LParts[LParts.length - 1]);
    if (!LNode) {
      return;
    }
    LNode.pcRow.scrollIntoView({ block: 'nearest' });
  }

  // Roots just shown (APaths) may hold the active file no root showed
  // before (its folder closed, then opened again): reveal it there. Not at
  // startup (the tree comes back as it was left) and not for a root that
  // was already shown (the user's collapsed folders stay collapsed).
  function retryReveal(APaths) {
    var LRoot;
    var LIndex;

    if (gRestoring || !gActivePath) {
      return;
    }
    LRoot = revealRoot(gActivePath);
    if (!LRoot) {
      return;
    }
    for (LIndex = 0; LIndex < APaths.length; LIndex++) {
      if (pathKey(APaths[LIndex]) === pathKey(LRoot.path)) {
        reveal();
        return;
      }
    }
  }

  // Ends startup once both halves are done: init has shown the roots and
  // the renderer has restored its tabs. Folders of roots no longer shown
  // are forgotten now that every root is known.
  function finishRestore() {
    if (!gRestoring || !gInitDone || !gRestoreEnded) {
      return;
    }
    gRestoring = false;
    pruneOpen();
  }

  // The renderer has restored the previous session's tabs
  function endRestore() {
    gRestoreEnded = true;
    finishRestore();
  }

  async function init(AOnOpenFile, AOnOpenFolder, AOnCloseFolder, AOnCloseExamples) {
    var LExamples;
    var LFolders;
    var LIndex;

    gOnOpenFile = AOnOpenFile;
    gOnOpenFolder = AOnOpenFolder;
    gOnCloseFolder = AOnCloseFolder;
    gOnCloseExamples = AOnCloseExamples;
    byId('explorer-open').addEventListener('click', function () {
      if (gOnOpenFolder) {
        gOnOpenFolder();
      }
    });
    byId('explorer-refresh').addEventListener('click', function () {
      refresh();
    });
    // main.js watches the shown roots and reports changed directories
    window.host.onFolderChanged(function (ADirs) {
      if (Array.isArray(ADirs)) {
        relistDirs(ADirs);
      }
    });

    LFolders = await window.host.folderList();
    // Open folders of the previous session (null = never saved)
    if (LFolders.ok && Array.isArray(LFolders.expanded)) {
      gRemembered = true;
      for (LIndex = 0; LIndex < LFolders.expanded.length; LIndex++) {
        gExpanded[LFolders.expanded[LIndex]] = true;
      }
    }
    setFolders(LFolders.ok ? LFolders.folders : []);

    LExamples = await window.host.examplesFolder();
    // The path comes back even when EXAMPLES is closed or missing
    gExamplesHome = LExamples.path || '';
    setExamples(LExamples.ok ? LExamples.path : '');
    gInitDone = true;
    finishRestore();
  }

  return {
    init: init,
    endRestore: endRestore,
    setFolders: setFolders,
    setExamples: setExamples,
    setActive: setActive,
    refresh: refresh
  };
})();
