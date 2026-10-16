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

  PaskalCPP Editor - call hierarchy tree (bottom panel, CALL HIERARCHY tab).

  Renders into #panel-calls. Knows nothing about the LSP: init() takes
    fetchChildren(node, 'incoming'|'outgoing') -> Promise<[{ node, siteUri, sites }]>
    jump(uri, range)
  A node: { name, detail, isModule, uri, selection } (lsp-providers.js
  toCallNode). Children load lazily on first expand and stay cached per
  row; a module node (main / init / finalize / test blocks) is a leaf.
  Row click = jump to the first call site; root row = the declaration.
*/
'use strict';

var PcCallTree = (function () {
  var PC_CT_INDENT_PX = 16;
  var PC_CT_BASE_PX = 8;

  var gFetch = null;
  var gJump = null;
  var gRoot = null;
  var gDirection = 'incoming';
  // Bumped per render / message: children of an older tree are dropped
  var gGeneration = 0;

  function pane() {
    return document.getElementById('panel-calls');
  }

  function init(AFetch, AJump) {
    gFetch = AFetch;
    gJump = AJump;
  }

  // File name of a file:/// uri (display only)
  function uriFileName(AUri) {
    var LLast = String(AUri || '').split('/').pop();

    try {
      return decodeURIComponent(LLast);
    } catch (LError) {
      return LLast;
    }
  }

  function showMessage(AText) {
    var LPane = pane();
    var LRow = document.createElement('div');

    gGeneration++;
    gRoot = null;
    LPane.textContent = '';
    LRow.className = 'pane-empty';
    LRow.textContent = AText;
    LPane.appendChild(LRow);
  }

  function show(ANode) {
    gRoot = ANode;
    render();
  }

  function setDirection(ADirection) {
    if (gDirection === ADirection) {
      return;
    }
    gDirection = ADirection;
    if (gRoot) {
      render();
    }
  }

  // Refetch from the stored root item: positions of an edited file are
  // re-resolved by the server (an item whose declaration moved -> none)
  function refresh() {
    if (gRoot) {
      render();
    }
  }

  function makeButton(AClass, AText, ATitle, AOnClick) {
    var LButton = document.createElement('button');

    LButton.className = AClass;
    LButton.textContent = AText;
    LButton.title = ATitle;
    LButton.addEventListener('click', AOnClick);
    return LButton;
  }

  function makeHeader() {
    var LHeader = document.createElement('div');
    var LTitle = document.createElement('span');
    var LSpacer = document.createElement('span');
    var LIn;
    var LOut;

    LHeader.className = 'ct-header';
    LTitle.className = 'ct-title';
    LTitle.textContent = (gDirection === 'incoming' ? 'Callers of ' : 'Calls from ') + gRoot.name;
    LSpacer.className = 'panel-spacer';
    LIn = makeButton('ct-dir', 'Incoming', 'Show callers', function () {
      setDirection('incoming');
    });
    LOut = makeButton('ct-dir', 'Outgoing', 'Show calls', function () {
      setDirection('outgoing');
    });
    LIn.classList.toggle('active', gDirection === 'incoming');
    LOut.classList.toggle('active', gDirection === 'outgoing');
    LHeader.appendChild(LTitle);
    LHeader.appendChild(LSpacer);
    LHeader.appendChild(LIn);
    LHeader.appendChild(LOut);
    LHeader.appendChild(makeButton('panel-icon', '\u21BB', 'Refresh', refresh));
    return LHeader;
  }

  function render() {
    var LPane = pane();
    var LList = document.createElement('div');
    var LGeneration = ++gGeneration;
    var LRootItem;

    LPane.textContent = '';
    LPane.appendChild(makeHeader());
    LList.className = 'ct-list';
    LPane.appendChild(LList);
    // The root's "site" is its own declaration
    LRootItem = makeItem({ node: gRoot, siteUri: gRoot.uri, sites: [gRoot.selection] }, 0, LGeneration);
    LList.appendChild(LRootItem.el);
    toggle(LRootItem);
  }

  // { el, row, twisty, children, entry, depth, generation, loaded, expanded }
  function makeItem(AEntry, ADepth, AGeneration) {
    var LItem = {
      el: document.createElement('div'),
      row: document.createElement('div'),
      twisty: document.createElement('span'),
      children: document.createElement('div'),
      entry: AEntry,
      depth: ADepth,
      generation: AGeneration,
      loaded: false,
      expanded: false
    };
    var LName = document.createElement('span');
    var LDetail = document.createElement('span');
    var LWhere = document.createElement('span');
    var LSite = AEntry.sites.length > 0 ? AEntry.sites[0] : AEntry.node.selection;

    LItem.row.className = 'ct-row';
    LItem.row.style.paddingLeft = (PC_CT_BASE_PX + ADepth * PC_CT_INDENT_PX) + 'px';
    LItem.row.title = AEntry.node.detail || AEntry.node.name;
    LItem.twisty.className = 'ct-twisty';
    LItem.twisty.textContent = AEntry.node.isModule ? '' : '\u25B8';
    LName.className = 'ct-name';
    LName.textContent = AEntry.node.name;
    LDetail.className = 'ct-detail';
    LDetail.textContent = AEntry.node.isModule ? '(module)' : AEntry.node.detail;
    LWhere.className = 'ct-where';
    LWhere.textContent = uriFileName(AEntry.siteUri) + ' [' + LSite.startLineNumber + ']' +
      (AEntry.sites.length > 1 ? ' \u00D7' + AEntry.sites.length : '');
    LItem.children.className = 'ct-children hidden';

    LItem.row.appendChild(LItem.twisty);
    LItem.row.appendChild(LName);
    LItem.row.appendChild(LDetail);
    LItem.row.appendChild(LWhere);
    LItem.el.appendChild(LItem.row);
    LItem.el.appendChild(LItem.children);

    LItem.twisty.addEventListener('click', function (AEvent) {
      AEvent.stopPropagation();
      toggle(LItem);
    });
    LItem.row.addEventListener('click', function () {
      gJump(AEntry.siteUri, LSite);
    });
    LItem.row.addEventListener('dblclick', function () {
      toggle(LItem);
    });
    return LItem;
  }

  function makeEmpty(ADepth, AText) {
    var LRow = document.createElement('div');

    LRow.className = 'ct-empty';
    LRow.style.paddingLeft = (PC_CT_BASE_PX + ADepth * PC_CT_INDENT_PX + 20) + 'px';
    LRow.textContent = AText;
    return LRow;
  }

  async function toggle(AItem) {
    var LList;
    var LIndex;

    if (AItem.entry.node.isModule) {
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
    LList = await gFetch(AItem.entry.node, gDirection);
    // A newer tree (show / direction / refresh) replaced this one
    if (AItem.generation !== gGeneration) {
      return;
    }
    AItem.children.textContent = '';
    if (LList.length === 0) {
      AItem.children.appendChild(makeEmpty(AItem.depth + 1,
        gDirection === 'incoming' ? 'No callers' : 'No calls'));
      return;
    }
    for (LIndex = 0; LIndex < LList.length; LIndex++) {
      AItem.children.appendChild(makeItem(LList[LIndex], AItem.depth + 1, AItem.generation).el);
    }
  }

  return {
    init: init,
    show: show,
    showMessage: showMessage,
    refresh: refresh
  };
})();
