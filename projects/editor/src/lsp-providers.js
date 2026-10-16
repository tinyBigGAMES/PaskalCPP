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

  PaskalCPP Editor - LSP providers (PcProviders)

  Maps every capability the PaskalCPP LSP server announces to one Monaco
  language provider. Positions: LSP is 0-based line/character (UTF-16),
  Monaco 1-based line/column (UTF-16) - convert with toRange/toLspPosition.

  The renderer owns tabs and models; providers reach them only through the
  hooks given to init():
    lspUriOf(model)   LSP uri the server has the model open under ('' = none)
    flush(model)      send a pending debounced didChange now
    flushAll()        send every tab's pending didChange now (workspace requests)
    loadModels(uris)  make sure a model exists for each uri (closed files)
    openTabs(uris)    open each uri as a tab (rename edits other files)
    modelUri(uri)     LSP uri -> Monaco Uri of its model

  install(caps) (re)registers the providers from the initialize result;
  a restarted server with other capabilities replaces the old set.
*/
var PcProviders = (function () {
  'use strict';

  var PC_LANG = 'pcpp';

  // LSP CompletionItemKind 1..25 -> Monaco CompletionItemKind member name
  var LSP_COMPLETION_KINDS = [
    'Text', 'Method', 'Function', 'Constructor', 'Field', 'Variable',
    'Class', 'Interface', 'Module', 'Property', 'Unit', 'Value', 'Enum',
    'Keyword', 'Snippet', 'Color', 'File', 'Reference', 'Folder',
    'EnumMember', 'Constant', 'Struct', 'Event', 'Operator', 'TypeParameter'
  ];

  var gMonaco = null;
  var gHooks = null;
  // IDisposable per registered provider (install)
  var gRegs = [];

  function toRange(ARange) {
    return new gMonaco.Range(
      ARange.start.line + 1, ARange.start.character + 1,
      ARange.end.line + 1, ARange.end.character + 1);
  }

  function toLspPosition(APosition) {
    return { line: APosition.lineNumber - 1, character: APosition.column - 1 };
  }

  function toLspRange(ARange) {
    return {
      start: { line: ARange.startLineNumber - 1, character: ARange.startColumn - 1 },
      end: { line: ARange.endLineNumber - 1, character: ARange.endColumn - 1 }
    };
  }

  // MarkupContent / string -> Monaco documentation (plain string or markdown)
  function toDocumentation(AValue) {
    if (AValue === undefined || AValue === null) {
      return undefined;
    }
    if (typeof AValue === 'string') {
      return AValue;
    }
    if (AValue.kind === 'markdown') {
      return { value: AValue.value };
    }
    return AValue.value;
  }

  // Hover contents: MarkupContent | MarkedString | MarkedString[]
  function toHoverContents(AContents) {
    var LList = Array.isArray(AContents) ? AContents : [AContents];
    var LOut = [];
    var LIndex;
    var LItem;

    for (LIndex = 0; LIndex < LList.length; LIndex++) {
      LItem = LList[LIndex];
      if (typeof LItem === 'string') {
        LOut.push({ value: LItem });
      } else if (LItem && LItem.language !== undefined) {
        LOut.push({ value: '```' + LItem.language + '\n' + LItem.value + '\n```' });
      } else if (LItem && LItem.value !== undefined) {
        LOut.push({ value: LItem.value });
      }
    }
    return LOut;
  }

  function completionKind(AKind) {
    var LKinds = gMonaco.languages.CompletionItemKind;
    var LName = LSP_COMPLETION_KINDS[(AKind || 1) - 1];

    if (LName && LKinds[LName] !== undefined) {
      return LKinds[LName];
    }
    return LKinds.Text;
  }

  // LSP SymbolKind 1..26 = Monaco SymbolKind 0..25
  function symbolKind(AKind) {
    var LKind = (AKind || 13) - 1;

    if (LKind < 0 || LKind > 25) {
      return gMonaco.languages.SymbolKind.Variable;
    }
    return LKind;
  }

  // Monaco MarkerSeverity (Error 8, Warning 4, Info 2, Hint 1) -> LSP 1..4
  function lspSeverity(ASeverity) {
    if (ASeverity === 8) {
      return 1;
    }
    if (ASeverity === 4) {
      return 2;
    }
    if (ASeverity === 2) {
      return 3;
    }
    return 4;
  }

  // One request for AModel's document. null when the model has no LSP
  // document, the server is not ready, or the request failed: a provider
  // then shows nothing, it never throws into Monaco.
  async function ask(AModel, AMethod, AParams) {
    var LUri = gHooks.lspUriOf(AModel);

    if (!LUri || !PcLsp.isReady()) {
      return null;
    }
    gHooks.flush(AModel);
    AParams.textDocument = { uri: LUri };
    try {
      return await PcLsp.request(AMethod, AParams);
    } catch (LError) {
      return null;
    }
  }

  function askAt(AModel, AMethod, APosition, AExtra) {
    var LParams = AExtra || {};

    LParams.position = toLspPosition(APosition);
    return ask(AModel, AMethod, LParams);
  }

  function addUnique(AList, AValue) {
    if (AValue && AList.indexOf(AValue) < 0) {
      AList.push(AValue);
    }
  }

  // Location | Location[] | LocationLink[] | null -> Monaco locations, with
  // a model loaded for every target file (peek and the opener need one)
  async function toLocations(AResult) {
    var LList = !AResult ? [] : (Array.isArray(AResult) ? AResult : [AResult]);
    var LUris = [];
    var LOut = [];
    var LIndex;
    var LItem;

    for (LIndex = 0; LIndex < LList.length; LIndex++) {
      addUnique(LUris, LList[LIndex].targetUri || LList[LIndex].uri);
    }
    await gHooks.loadModels(LUris);
    for (LIndex = 0; LIndex < LList.length; LIndex++) {
      LItem = LList[LIndex];
      if (LItem.targetUri) {
        LOut.push({
          uri: gHooks.modelUri(LItem.targetUri),
          range: toRange(LItem.targetRange),
          targetSelectionRange: toRange(LItem.targetSelectionRange || LItem.targetRange),
          originSelectionRange: LItem.originSelectionRange ? toRange(LItem.originSelectionRange) : undefined
        });
      } else if (LItem.uri && LItem.range) {
        LOut.push({ uri: gHooks.modelUri(LItem.uri), range: toRange(LItem.range) });
      }
    }
    return LOut;
  }

  // WorkspaceEdit (changes or documentChanges) -> [{ uri, edits }]
  function editGroups(AEdit) {
    var LGroups = [];
    var LUri;
    var LIndex;
    var LChange;

    if (!AEdit) {
      return LGroups;
    }
    if (AEdit.documentChanges) {
      for (LIndex = 0; LIndex < AEdit.documentChanges.length; LIndex++) {
        LChange = AEdit.documentChanges[LIndex];
        // Only text edits: create/rename/delete file operations are not offered
        if (LChange.textDocument && LChange.edits) {
          LGroups.push({ uri: LChange.textDocument.uri, edits: LChange.edits });
        }
      }
    } else if (AEdit.changes) {
      for (LUri in AEdit.changes) {
        if (Object.prototype.hasOwnProperty.call(AEdit.changes, LUri)) {
          LGroups.push({ uri: LUri, edits: AEdit.changes[LUri] });
        }
      }
    }
    return LGroups;
  }

  // WorkspaceEdit -> Monaco WorkspaceEdit. Every file it touches is opened
  // as a tab first, so the edit lands in a model the user can review/save.
  async function toWorkspaceEdit(AEdit) {
    var LGroups = editGroups(AEdit);
    var LUris = [];
    var LEdits = [];
    var LIndex;
    var LEditIndex;
    var LItem;

    for (LIndex = 0; LIndex < LGroups.length; LIndex++) {
      addUnique(LUris, LGroups[LIndex].uri);
    }
    await gHooks.openTabs(LUris);
    for (LIndex = 0; LIndex < LGroups.length; LIndex++) {
      for (LEditIndex = 0; LEditIndex < LGroups[LIndex].edits.length; LEditIndex++) {
        LItem = LGroups[LIndex].edits[LEditIndex];
        LEdits.push({
          resource: gHooks.modelUri(LGroups[LIndex].uri),
          textEdit: { range: toRange(LItem.range), text: LItem.newText },
          versionId: undefined
        });
      }
    }
    return { edits: LEdits };
  }

  function toTextEdits(AList) {
    var LOut = [];
    var LIndex;

    for (LIndex = 0; AList && LIndex < AList.length; LIndex++) {
      LOut.push({ range: toRange(AList[LIndex].range), text: AList[LIndex].newText });
    }
    return LOut;
  }

  function toCompletion(AItem, AWordRange) {
    var LEdit = AItem.textEdit;
    var LRange = AWordRange;

    if (LEdit && LEdit.range) {
      LRange = toRange(LEdit.range);
    } else if (LEdit && LEdit.insert && LEdit.replace) {
      // InsertReplaceEdit
      LRange = { insert: toRange(LEdit.insert), replace: toRange(LEdit.replace) };
    }
    return {
      label: AItem.label,
      kind: completionKind(AItem.kind),
      detail: AItem.detail,
      documentation: toDocumentation(AItem.documentation),
      sortText: AItem.sortText,
      filterText: AItem.filterText,
      insertText: LEdit ? LEdit.newText : (AItem.insertText || AItem.label),
      insertTextRules: AItem.insertTextFormat === 2 ?
        gMonaco.languages.CompletionItemInsertTextRule.InsertAsSnippet : undefined,
      range: LRange
    };
  }

  // DocumentSymbol (hierarchical) or SymbolInformation (flat)
  function toSymbol(AItem) {
    var LChildren = [];
    var LIndex;
    var LRange;

    if (AItem.location) {
      LRange = toRange(AItem.location.range);
      return {
        name: AItem.name,
        detail: '',
        kind: symbolKind(AItem.kind),
        tags: [],
        containerName: AItem.containerName,
        range: LRange,
        selectionRange: LRange
      };
    }
    for (LIndex = 0; AItem.children && LIndex < AItem.children.length; LIndex++) {
      LChildren.push(toSymbol(AItem.children[LIndex]));
    }
    return {
      name: AItem.name,
      detail: AItem.detail || '',
      kind: symbolKind(AItem.kind),
      tags: [],
      range: toRange(AItem.range),
      selectionRange: toRange(AItem.selectionRange || AItem.range),
      children: LChildren
    };
  }

  function toInlayHint(AHint) {
    var LLabel = AHint.label;
    var LParts = [];
    var LIndex;

    if (Array.isArray(LLabel)) {
      for (LIndex = 0; LIndex < LLabel.length; LIndex++) {
        LParts.push({ label: LLabel[LIndex].value, tooltip: toDocumentation(LLabel[LIndex].tooltip) });
      }
      LLabel = LParts;
    }
    return {
      label: LLabel,
      position: { lineNumber: AHint.position.line + 1, column: AHint.position.character + 1 },
      kind: AHint.kind,
      tooltip: toDocumentation(AHint.tooltip),
      paddingLeft: !!AHint.paddingLeft,
      paddingRight: !!AHint.paddingRight
    };
  }

  function toLspDiagnostic(AMarker) {
    var LCode = AMarker.code;

    if (LCode && typeof LCode === 'object') {
      LCode = LCode.value;
    }
    return {
      range: toLspRange(AMarker),
      severity: lspSeverity(AMarker.severity),
      code: LCode,
      source: AMarker.source,
      message: AMarker.message
    };
  }

  function register(AReg) {
    gRegs.push(AReg);
  }

  function hoverProvider() {
    return {
      provideHover: async function (AModel, APosition) {
        var LRes = await askAt(AModel, 'textDocument/hover', APosition);

        if (!LRes || !LRes.contents) {
          return null;
        }
        return {
          contents: toHoverContents(LRes.contents),
          range: LRes.range ? toRange(LRes.range) : undefined
        };
      }
    };
  }

  function completionProvider(ACaps) {
    return {
      triggerCharacters: (ACaps.completionProvider && ACaps.completionProvider.triggerCharacters) || [],
      provideCompletionItems: async function (AModel, APosition) {
        var LRes = await askAt(AModel, 'textDocument/completion', APosition);
        var LItems = !LRes ? [] : (Array.isArray(LRes) ? LRes : (LRes.items || []));
        var LWord = AModel.getWordUntilPosition(APosition);
        var LRange = new gMonaco.Range(APosition.lineNumber, LWord.startColumn,
          APosition.lineNumber, LWord.endColumn);
        var LOut = [];
        var LIndex;

        for (LIndex = 0; LIndex < LItems.length; LIndex++) {
          LOut.push(toCompletion(LItems[LIndex], LRange));
        }
        return { suggestions: LOut, incomplete: !!(LRes && LRes.isIncomplete) };
      }
    };
  }

  function signatureHelpProvider(ACaps) {
    var LCaps = ACaps.signatureHelpProvider;

    return {
      signatureHelpTriggerCharacters: (LCaps && LCaps.triggerCharacters) || [],
      signatureHelpRetriggerCharacters: (LCaps && LCaps.retriggerCharacters) || [],
      provideSignatureHelp: async function (AModel, APosition) {
        var LRes = await askAt(AModel, 'textDocument/signatureHelp', APosition);
        var LSigs = [];
        var LParams;
        var LIndex;
        var LParam;
        var LSig;

        if (!LRes || !LRes.signatures || LRes.signatures.length === 0) {
          return null;
        }
        for (LIndex = 0; LIndex < LRes.signatures.length; LIndex++) {
          LSig = LRes.signatures[LIndex];
          LParams = [];
          for (LParam = 0; LSig.parameters && LParam < LSig.parameters.length; LParam++) {
            LParams.push({
              label: LSig.parameters[LParam].label,
              documentation: toDocumentation(LSig.parameters[LParam].documentation)
            });
          }
          LSigs.push({ label: LSig.label, documentation: toDocumentation(LSig.documentation), parameters: LParams });
        }
        return {
          value: {
            signatures: LSigs,
            activeSignature: LRes.activeSignature || 0,
            activeParameter: LRes.activeParameter || 0
          },
          dispose: function () {}
        };
      }
    };
  }

  function locationProvider(AMethod, AMember) {
    var LProvider = {};

    LProvider[AMember] = async function (AModel, APosition) {
      return toLocations(await askAt(AModel, AMethod, APosition));
    };
    return LProvider;
  }

  function referenceProvider() {
    return {
      provideReferences: async function (AModel, APosition, AContext) {
        return toLocations(await askAt(AModel, 'textDocument/references', APosition, {
          context: { includeDeclaration: !!(AContext && AContext.includeDeclaration) }
        }));
      }
    };
  }

  function highlightProvider() {
    return {
      provideDocumentHighlights: async function (AModel, APosition) {
        var LRes = await askAt(AModel, 'textDocument/documentHighlight', APosition);
        var LOut = [];
        var LIndex;

        for (LIndex = 0; LRes && LIndex < LRes.length; LIndex++) {
          // LSP Text 1 / Read 2 / Write 3 = Monaco 0 / 1 / 2
          LOut.push({ range: toRange(LRes[LIndex].range), kind: (LRes[LIndex].kind || 1) - 1 });
        }
        return LOut;
      }
    };
  }

  function renameProvider() {
    return {
      provideRenameEdits: async function (AModel, APosition, ANewName) {
        var LRes = await askAt(AModel, 'textDocument/rename', APosition, { newName: ANewName });

        if (!LRes) {
          return { edits: [], rejectReason: 'Nothing to rename here.' };
        }
        return toWorkspaceEdit(LRes);
      }
    };
  }

  function foldingProvider() {
    return {
      provideFoldingRanges: async function (AModel) {
        var LRes = await ask(AModel, 'textDocument/foldingRange', {});
        var LOut = [];
        var LIndex;
        var LItem;

        for (LIndex = 0; LRes && LIndex < LRes.length; LIndex++) {
          LItem = LRes[LIndex];
          LOut.push({
            start: LItem.startLine + 1,
            end: LItem.endLine + 1,
            kind: LItem.kind ? gMonaco.languages.FoldingRangeKind.fromValue(LItem.kind) : undefined
          });
        }
        return LOut;
      }
    };
  }

  function symbolProvider() {
    return {
      displayName: 'PaskalCPP',
      provideDocumentSymbols: async function (AModel) {
        var LRes = await ask(AModel, 'textDocument/documentSymbol', {});
        var LOut = [];
        var LIndex;

        for (LIndex = 0; LRes && LIndex < LRes.length; LIndex++) {
          LOut.push(toSymbol(LRes[LIndex]));
        }
        return LOut;
      }
    };
  }

  function formattingProvider() {
    return {
      displayName: 'PaskalCPP',
      provideDocumentFormattingEdits: async function (AModel, AOptions) {
        // Monaco's tabSize / insertSpaces (the model's, set from the settings)
        // plus the other format settings: spec keys and pcpp.* keys
        var LOptions = Object.assign({}, gHooks.formatOptions(), {
          tabSize: AOptions.tabSize,
          insertSpaces: AOptions.insertSpaces
        });
        return toTextEdits(await ask(AModel, 'textDocument/formatting', { options: LOptions }));
      }
    };
  }

  function rangeFormattingProvider() {
    return {
      displayName: 'PaskalCPP',
      provideDocumentRangeFormattingEdits: async function (AModel, ARange, AOptions) {
        var LOptions = Object.assign({}, gHooks.formatOptions(), {
          tabSize: AOptions.tabSize,
          insertSpaces: AOptions.insertSpaces
        });
        return toTextEdits(await ask(AModel, 'textDocument/rangeFormatting',
          { range: toLspRange(ARange), options: LOptions }));
      }
    };
  }

  // Format on save: the server's edits for AModel applied as one undo step;
  // nothing when the server is not ready or refuses (it says why itself)
  async function formatModel(AModel) {
    var LModelOptions = AModel.getOptions();
    var LEdits = await formattingProvider().provideDocumentFormattingEdits(AModel, {
      tabSize: LModelOptions.tabSize,
      insertSpaces: LModelOptions.insertSpaces
    });

    if (LEdits && LEdits.length > 0) {
      AModel.pushEditOperations([], LEdits.map(function (AEdit) {
        return { range: AEdit.range, text: AEdit.text };
      }), function () {
        return null;
      });
    }
  }

  function inlayHintsProvider() {
    return {
      provideInlayHints: async function (AModel, ARange) {
        var LRes = await ask(AModel, 'textDocument/inlayHint', { range: toLspRange(ARange) });
        var LOut = [];
        var LIndex;

        for (LIndex = 0; LRes && LIndex < LRes.length; LIndex++) {
          LOut.push(toInlayHint(LRes[LIndex]));
        }
        return { hints: LOut, dispose: function () {} };
      }
    };
  }

  function semanticTokensProvider(ACaps) {
    var LLegend = ACaps.semanticTokensProvider.legend;

    return {
      getLegend: function () {
        return { tokenTypes: LLegend.tokenTypes, tokenModifiers: LLegend.tokenModifiers };
      },
      provideDocumentSemanticTokens: async function (AModel) {
        var LRes = await ask(AModel, 'textDocument/semanticTokens/full', {});

        if (!LRes || !LRes.data) {
          return null;
        }
        return { data: new Uint32Array(LRes.data), resultId: LRes.resultId };
      },
      releaseDocumentSemanticTokens: function () {}
    };
  }

  function codeActionProvider() {
    return {
      provideCodeActions: async function (AModel, ARange, AContext) {
        var LDiags = [];
        var LActions = [];
        var LRes;
        var LIndex;
        var LItem;

        for (LIndex = 0; AContext.markers && LIndex < AContext.markers.length; LIndex++) {
          LDiags.push(toLspDiagnostic(AContext.markers[LIndex]));
        }
        LRes = await ask(AModel, 'textDocument/codeAction', {
          range: toLspRange(ARange),
          context: { diagnostics: LDiags }
        });
        for (LIndex = 0; LRes && LIndex < LRes.length; LIndex++) {
          LItem = LRes[LIndex];
          // Command-only actions need workspace/executeCommand, which the
          // server does not offer: only edit actions are shown
          if (LItem.edit) {
            LActions.push({
              title: LItem.title,
              kind: LItem.kind,
              isPreferred: !!LItem.isPreferred,
              edit: await toWorkspaceEdit(LItem.edit)
            });
          }
        }
        return { actions: LActions, dispose: function () {} };
      }
    };
  }

  // ---- E9: workspace symbols + call hierarchy. Monaco standalone has no
  // UI for either; these return plain data for the editor's own UI
  // (quickpick.js, calltree.js). Never throw: null / [] on failure.

  // A request that belongs to no single document: every tab's pending
  // didChange goes out first, so positions match what the user sees
  async function askWorkspace(AMethod, AParams) {
    if (!PcLsp.isReady()) {
      return null;
    }
    gHooks.flushAll();
    try {
      return await PcLsp.request(AMethod, AParams);
    } catch (LError) {
      return null;
    }
  }

  // SymbolInformation[] -> [{ name, kind, container, uri, range }], range
  // as a Monaco range. Server filters (case-insensitive substring); the
  // quick pick ranks
  async function workspaceSymbols(AQuery) {
    var LResult = await askWorkspace('workspace/symbol', { query: AQuery });
    var LList = Array.isArray(LResult) ? LResult : [];
    var LOut = [];
    var LIndex;
    var LItem;

    for (LIndex = 0; LIndex < LList.length; LIndex++) {
      LItem = LList[LIndex];
      if (!LItem || !LItem.location || !LItem.location.uri || !LItem.location.range) {
        continue;
      }
      LOut.push({
        name: LItem.name,
        kind: LItem.kind,
        container: LItem.containerName || '',
        uri: LItem.location.uri,
        range: toRange(LItem.location.range)
      });
    }
    return LOut;
  }

  // CallHierarchyItem -> tree node. `item` is kept VERBATIM: the server
  // re-finds the routine from its uri + selectionRange + data.anchor.
  // kind 2 = a module standing in for its top-level blocks: a leaf
  function toCallNode(AItem) {
    return {
      item: AItem,
      name: AItem.name,
      detail: AItem.detail || '',
      isModule: AItem.kind === 2,
      uri: AItem.uri,
      selection: toRange(AItem.selectionRange || AItem.range)
    };
  }

  // The routine at APosition of AModel (declaration or a call of it), or null
  async function prepareCallHierarchy(AModel, APosition) {
    var LResult = await askAt(AModel, 'textDocument/prepareCallHierarchy', APosition);

    if (!Array.isArray(LResult) || LResult.length === 0 || !LResult[0]) {
      return null;
    }
    return toCallNode(LResult[0]);
  }

  // ADirection 'incoming' | 'outgoing' -> [{ node, siteUri, sites }].
  // sites = call ranges (Monaco), always in the CALLER's file: incoming ->
  // the child is the caller (from.uri); outgoing -> ANode is (ANode.uri)
  async function callChildren(ANode, ADirection) {
    var LIncoming = ADirection === 'incoming';
    var LMethod = LIncoming ? 'callHierarchy/incomingCalls' : 'callHierarchy/outgoingCalls';
    var LResult;
    var LList;
    var LOut = [];
    var LIndex;
    var LSite;
    var LCall;
    var LTarget;
    var LSites;

    if (!ANode || ANode.isModule) {
      return LOut;
    }
    LResult = await askWorkspace(LMethod, { item: ANode.item });
    LList = Array.isArray(LResult) ? LResult : [];
    for (LIndex = 0; LIndex < LList.length; LIndex++) {
      LCall = LList[LIndex];
      LTarget = LCall ? (LIncoming ? LCall.from : LCall.to) : null;
      if (!LTarget) {
        continue;
      }
      LSites = [];
      for (LSite = 0; LSite < (LCall.fromRanges || []).length; LSite++) {
        LSites.push(toRange(LCall.fromRanges[LSite]));
      }
      LOut.push({
        node: toCallNode(LTarget),
        siteUri: LIncoming ? LTarget.uri : ANode.uri,
        sites: LSites
      });
    }
    return LOut;
  }

  function init(AMonaco, AHooks) {
    gMonaco = AMonaco;
    gHooks = AHooks;
  }

  // Registers one provider per announced capability; drops the previous set
  function install(ACaps) {
    var LLang = gMonaco.languages;
    var LIndex;

    for (LIndex = 0; LIndex < gRegs.length; LIndex++) {
      gRegs[LIndex].dispose();
    }
    gRegs = [];
    if (!ACaps) {
      return;
    }
    if (ACaps.hoverProvider) {
      register(LLang.registerHoverProvider(PC_LANG, hoverProvider()));
    }
    if (ACaps.completionProvider) {
      register(LLang.registerCompletionItemProvider(PC_LANG, completionProvider(ACaps)));
    }
    if (ACaps.signatureHelpProvider) {
      register(LLang.registerSignatureHelpProvider(PC_LANG, signatureHelpProvider(ACaps)));
    }
    if (ACaps.definitionProvider) {
      register(LLang.registerDefinitionProvider(PC_LANG,
        locationProvider('textDocument/definition', 'provideDefinition')));
    }
    if (ACaps.typeDefinitionProvider) {
      register(LLang.registerTypeDefinitionProvider(PC_LANG,
        locationProvider('textDocument/typeDefinition', 'provideTypeDefinition')));
    }
    if (ACaps.referencesProvider) {
      register(LLang.registerReferenceProvider(PC_LANG, referenceProvider()));
    }
    if (ACaps.documentHighlightProvider) {
      register(LLang.registerDocumentHighlightProvider(PC_LANG, highlightProvider()));
    }
    if (ACaps.renameProvider) {
      register(LLang.registerRenameProvider(PC_LANG, renameProvider()));
    }
    if (ACaps.foldingRangeProvider) {
      register(LLang.registerFoldingRangeProvider(PC_LANG, foldingProvider()));
    }
    if (ACaps.documentSymbolProvider) {
      register(LLang.registerDocumentSymbolProvider(PC_LANG, symbolProvider()));
    }
    if (ACaps.documentFormattingProvider) {
      register(LLang.registerDocumentFormattingEditProvider(PC_LANG, formattingProvider()));
    }
    if (ACaps.documentRangeFormattingProvider) {
      register(LLang.registerDocumentRangeFormattingEditProvider(PC_LANG, rangeFormattingProvider()));
    }
    if (ACaps.inlayHintProvider) {
      register(LLang.registerInlayHintsProvider(PC_LANG, inlayHintsProvider()));
    }
    if (ACaps.semanticTokensProvider && ACaps.semanticTokensProvider.legend) {
      register(LLang.registerDocumentSemanticTokensProvider(PC_LANG, semanticTokensProvider(ACaps)));
    }
    if (ACaps.codeActionProvider) {
      register(LLang.registerCodeActionProvider(PC_LANG, codeActionProvider()));
    }
  }

  return {
    init: init,
    install: install,
    // E9 (quickpick.js / calltree.js data; scripts\editor_nav_test.js)
    workspaceSymbols: workspaceSymbols,
    prepareCallHierarchy: prepareCallHierarchy,
    callChildren: callChildren,
    formatModel: formatModel,
    // Exposed for the headless test (scripts\editor_providers_test.js)
    toRange: toRange,
    toLspPosition: toLspPosition
  };
})();
