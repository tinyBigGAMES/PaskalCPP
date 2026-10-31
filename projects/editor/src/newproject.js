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

  PaskalCPP Editor - New Project dialog (renderer).

  File > New Project. One form: the name, the type (exe / dll / lib) and
  the folder to make it in (Browse asks main.js for it; it starts at the
  last folder a dialog used). Create hands the three to main.js
  (window.host.newProject), which runs pcpp init there; the dialog stays
  open and busy until pcpp answers. A failure is shown IN the dialog with
  pcpp's own lines, so nothing fails silently; success closes it and the
  caller's onCreated opens the project. Esc, Cancel or a click on the
  backdrop closes it (not while pcpp runs); Enter is Create.
*/
'use strict';

var PcNewProject = (function () {
  var PC_NP_KINDS = [
    { kind: 'exe', text: 'exe - a program' },
    { kind: 'dll', text: 'dll - a shared library' },
    { kind: 'lib', text: 'lib - a static library' }
  ];

  var gRoot = null;
  var gName = null;
  var gKind = null;
  var gParent = null;
  var gBrowse = null;
  var gCreate = null;
  var gCancel = null;
  var gError = null;
  var gBusy = false;
  var gOnCreated = null;
  var gOnClose = null;

  function isOpen() {
    return !!gRoot && !gRoot.classList.contains('hidden');
  }

  // One labelled row: the caption above its control
  function field(ABox, ACaption, AControl) {
    var LLabel = document.createElement('label');
    var LCaption = document.createElement('span');

    LLabel.className = 'np-field';
    LCaption.className = 'np-caption';
    LCaption.textContent = ACaption;
    LLabel.appendChild(LCaption);
    LLabel.appendChild(AControl);
    ABox.appendChild(LLabel);
  }

  function makeButton(AClass, AText, AOnClick) {
    var LButton = document.createElement('button');
    LButton.className = AClass;
    LButton.textContent = AText;
    LButton.type = 'button';
    LButton.addEventListener('click', AOnClick);
    return LButton;
  }

  function makeKindSelect() {
    var LSelect = document.createElement('select');
    var LIndex;
    var LOption;

    LSelect.className = 'np-input';
    for (LIndex = 0; LIndex < PC_NP_KINDS.length; LIndex++) {
      LOption = document.createElement('option');
      LOption.value = PC_NP_KINDS[LIndex].kind;
      LOption.textContent = PC_NP_KINDS[LIndex].text;
      LSelect.appendChild(LOption);
    }
    return LSelect;
  }

  // Builds the form inside #newproject (index.html) on first use
  function ensureDom() {
    var LBox;
    var LTitle;
    var LFolderRow;
    var LButtons;

    if (gRoot) {
      return;
    }
    gRoot = document.getElementById('newproject');
    LBox = document.createElement('div');
    LBox.className = 'np-box';

    LTitle = document.createElement('div');
    LTitle.className = 'np-title';
    LTitle.textContent = 'New Project';
    LBox.appendChild(LTitle);

    gName = document.createElement('input');
    gName.className = 'np-input';
    gName.type = 'text';
    gName.spellcheck = false;
    gName.placeholder = 'MyGame';
    field(LBox, 'Name', gName);

    gKind = makeKindSelect();
    field(LBox, 'Type', gKind);

    LFolderRow = document.createElement('div');
    LFolderRow.className = 'np-folder';
    gParent = document.createElement('input');
    gParent.className = 'np-input';
    gParent.type = 'text';
    gParent.spellcheck = false;
    gParent.placeholder = 'The folder the project folder goes in';
    gBrowse = makeButton('np-button', 'Browse...', browse);
    LFolderRow.appendChild(gParent);
    LFolderRow.appendChild(gBrowse);
    field(LBox, 'Create in', LFolderRow);

    gError = document.createElement('pre');
    gError.className = 'np-error hidden';
    LBox.appendChild(gError);

    LButtons = document.createElement('div');
    LButtons.className = 'np-buttons';
    gCancel = makeButton('np-button', 'Cancel', function () {
      close();
    });
    gCreate = makeButton('np-button np-primary', 'Create', create);
    LButtons.appendChild(gCancel);
    LButtons.appendChild(gCreate);
    LBox.appendChild(LButtons);

    gRoot.appendChild(LBox);
    // A press on the dimmed backdrop (not the box) closes
    gRoot.addEventListener('mousedown', function (AEvent) {
      if (AEvent.target === gRoot) {
        close();
      }
    });
    gRoot.addEventListener('keydown', function (AEvent) {
      if (AEvent.key === 'Escape') {
        AEvent.preventDefault();
        close();
      } else if (AEvent.key === 'Enter' && AEvent.target.tagName !== 'BUTTON') {
        // Enter on a button presses that button (its own click)
        AEvent.preventDefault();
        create();
      }
    });
  }

  function showError(AText) {
    gError.textContent = AText;
    gError.classList.toggle('hidden', AText === '');
  }

  // pcpp is running: nothing in the form can change or close it
  function setBusy(ABusy) {
    gBusy = ABusy;
    gName.disabled = ABusy;
    gKind.disabled = ABusy;
    gParent.disabled = ABusy;
    gBrowse.disabled = ABusy;
    gCreate.disabled = ABusy;
    gCancel.disabled = ABusy;
    gCreate.textContent = ABusy ? 'Creating...' : 'Create';
  }

  async function browse() {
    var LRes;

    if (gBusy) {
      return;
    }
    LRes = await window.host.pickProjectParent(gParent.value.trim());
    if (LRes && LRes.ok) {
      gParent.value = LRes.path;
    }
    gParent.focus();
  }

  // The form's own checks first (pcpp checks the name's rules itself), then
  // main.js runs pcpp init; its answer stays in the dialog on a failure
  async function create() {
    var LName = gName.value.trim();
    var LParent = gParent.value.trim();
    var LRes;
    var LText;

    if (gBusy) {
      return;
    }
    if (LName === '') {
      showError('Type the project name.');
      gName.focus();
      return;
    }
    if (LParent === '') {
      showError('Pick the folder to make the project in (Browse...).');
      gParent.focus();
      return;
    }
    showError('');
    setBusy(true);
    try {
      LRes = await window.host.newProject({ name: LName, kind: gKind.value, parent: LParent });
    } catch (AError) {
      LRes = { ok: false, error: 'New Project failed: ' + AError.message, output: '' };
    }
    setBusy(false);
    if (!LRes || !LRes.ok) {
      LText = (LRes && LRes.error) || 'New Project failed.';
      if (LRes && LRes.output) {
        LText += '\n\n' + LRes.output.trim();
      }
      showError(LText);
      gName.focus();
      return;
    }
    finish(LRes);
  }

  // Success: the dialog closes, then the caller opens the project
  function finish(ARes) {
    var LOnCreated = gOnCreated;

    gRoot.classList.add('hidden');
    gOnCreated = null;
    gOnClose = null;
    if (LOnCreated) {
      LOnCreated(ARes);
    }
  }

  function close() {
    var LOnClose = gOnClose;

    if (!isOpen() || gBusy) {
      return;
    }
    gRoot.classList.add('hidden');
    gOnCreated = null;
    gOnClose = null;
    if (LOnClose) {
      LOnClose();
    }
  }

  // AOnCreated(result): pcpp init made the project ({ root, main, folders,
  // output }); AOnClose: closed without one (the caller restores focus)
  async function open(AOnCreated, AOnClose) {
    var LParent;

    ensureDom();
    if (isOpen()) {
      return;
    }
    gOnCreated = AOnCreated || null;
    gOnClose = AOnClose || null;
    gName.value = '';
    gKind.value = PC_NP_KINDS[0].kind;
    showError('');
    setBusy(false);
    // The folder starts where the last dialog was ('' = none yet)
    try {
      LParent = await window.host.projectDefaultParent();
    } catch (AError) {
      LParent = '';
    }
    gParent.value = typeof LParent === 'string' ? LParent : '';
    gRoot.classList.remove('hidden');
    gName.focus();
  }

  return {
    open: open,
    close: close,
    isOpen: isOpen
  };
})();
