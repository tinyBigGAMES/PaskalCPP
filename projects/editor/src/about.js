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

  PaskalCPP Editor - About box (renderer).

  Help > About. Shows what main.js reports (window.host.appInfo): product,
  version, copyright and site (written by pcppdev from PaskalCPP.Common), plus
  the Electron / Chromium / Node versions. The site opens in the user's
  default browser (window.host.openUrl). Esc, Enter, OK or a click on the
  backdrop closes it; the caller's onClose restores focus.
*/
'use strict';

var PcAbout = (function () {
  var gRoot = null;
  var gBox = null;
  var gOnClose = null;

  function isOpen() {
    return !!gRoot && !gRoot.classList.contains('hidden');
  }

  function line(AClass, AText) {
    var LLine = document.createElement('div');
    LLine.className = AClass;
    LLine.textContent = AText;
    return LLine;
  }

  // Builds the box inside #about (index.html) on first use
  function ensureDom() {
    if (gRoot) {
      return;
    }
    gRoot = document.getElementById('about');
    gBox = document.createElement('div');
    gBox.className = 'ab-box';
    gRoot.appendChild(gBox);
    // A press on the dimmed backdrop (not the box) closes
    gRoot.addEventListener('mousedown', function (AEvent) {
      if (AEvent.target === gRoot) {
        close();
      }
    });
    gRoot.addEventListener('keydown', function (AEvent) {
      if (AEvent.key === 'Escape' || AEvent.key === 'Enter') {
        AEvent.preventDefault();
        close();
      }
    });
  }

  function addLink(AUrl) {
    var LLink = document.createElement('a');
    LLink.className = 'ab-link';
    LLink.href = '#';
    LLink.title = AUrl;
    // Shown without the scheme and trailing slash: paskalcpp.org
    LLink.textContent = AUrl.replace(/^https?:\/\//, '').replace(/\/$/, '');
    LLink.addEventListener('click', function (AEvent) {
      AEvent.preventDefault();
      window.host.openUrl(AUrl);
    });
    gBox.appendChild(LLink);
  }

  function render(AInfo) {
    var LLogo = document.createElement('img');
    var LButton = document.createElement('button');

    gBox.textContent = '';
    LLogo.className = 'ab-logo';
    LLogo.src = 'assets/icon.ico';
    LLogo.alt = '';
    LLogo.draggable = false;
    gBox.appendChild(LLogo);
    gBox.appendChild(line('ab-product', AInfo.product || 'PaskalCPP Editor'));
    if (AInfo.version) {
      gBox.appendChild(line('ab-version', 'Version ' + AInfo.version));
    }
    if (AInfo.copyright) {
      gBox.appendChild(line('ab-copyright', AInfo.copyright));
    }
    if (AInfo.url) {
      addLink(AInfo.url);
    }
    if (AInfo.electron) {
      gBox.appendChild(line('ab-runtime', 'Electron ' + AInfo.electron +
        '  |  Chromium ' + AInfo.chrome + '  |  Node ' + AInfo.node));
    }
    LButton.className = 'ab-ok';
    LButton.textContent = 'OK';
    LButton.addEventListener('click', close);
    gBox.appendChild(LButton);
  }

  function close() {
    var LOnClose = gOnClose;
    if (!isOpen()) {
      return;
    }
    gRoot.classList.add('hidden');
    gOnClose = null;
    if (LOnClose) {
      LOnClose();
    }
  }

  // AOnClose: called once when the box closes (the caller restores focus)
  async function open(AOnClose) {
    var LInfo;
    ensureDom();
    gOnClose = AOnClose || null;
    try {
      LInfo = await window.host.appInfo();
    } catch (LError) {
      LInfo = {};
    }
    render(LInfo || {});
    gRoot.classList.remove('hidden');
    gBox.querySelector('.ab-ok').focus();
  }

  return {
    open: open,
    close: close,
    isOpen: isOpen
  };
})();
