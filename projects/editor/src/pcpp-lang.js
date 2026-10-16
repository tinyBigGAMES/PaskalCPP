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

  PaskalCPP Editor - PaskalCPP for Monaco (Monarch tokenizer).

  The word lists are not written here: they come from the language server
  (pcpp --lsp, initialize: capabilities.experimental.pcppWords, from
  PaskalCPP.Common's PC_PASKAL_TOKENS) through setWords. PaskalCPP is
  case-sensitive. The literal, comment, # line and cppstart rules follow
  PaskalCPP.Lexer (research\cppmix\lexer.md). This tokenizer gives instant
  colouring; the LSP's semantic tokens refine it once the server sends them.
*/
'use strict';

var PcLang = (function () {
  // Empty until the server's words arrive (setWords)
  var WORDS = { keywords: [], types: [] };
  // The monaco register() was given: setWords re-sets the tokenizer with it
  var gMonaco = null;

  // pp-number body after its first digit (or '.' digit): a signed exponent
  // (tried first, or 'e' alone would match as a letter and stop at the sign),
  // digits, letters, '_', a ' separator before a digit / letter, a '.' not
  // followed by another '.' (so 1..5 is 1 .. 5)
  var PP_TAIL = "(?:[eEpP][+\\-]|[0-9A-Za-z_]|'[0-9A-Za-z]|\\.(?!\\.))*";

  var MONARCH = {
    defaultToken: '',
    tokenPostfix: '.pcpp',
    ignoreCase: false,
    keywords: WORDS.keywords,
    types: WORDS.types,

    tokenizer: {
      root: [
        // # line (only trivia before it on the line); a line splice continues it
        [/^\s*(#|%:)/, { token: 'keyword.directive', next: '@preproc' }],

        { include: '@whitespace' },

        // cppstart header|source ... cppend: the block is C++ text
        [/cppstart\b/, { token: 'keyword', next: '@cppTarget' }],

        { include: '@literals' },

        // @directive: @ + identifier, exact case
        [/@[A-Za-z_]\w*/, 'annotation'],

        [/[A-Za-z_]\w*/, {
          cases: {
            '@keywords': 'keyword',
            '@types': 'type',
            '@default': 'identifier'
          }
        }],

        [/:=|\.\.|<>|<=|>=|::|->|<<|>>|\+\+|--|&&|\|\||[+\-*\/%=<>&|^~!?]=?/, 'operator'],
        [/[()\[\]{}]/, '@brackets'],
        [/[;,.:]/, 'delimiter']
      ],

      whitespace: [
        [/[ \t\f\v\r\n]+/, ''],
        [/\/\*/, 'comment', '@blockComment'],
        [/\/\/.*\\$/, 'comment', '@lineCommentSplice'],
        [/\/\/.*$/, 'comment']
      ],

      // Strings, chars and numbers; shared by the root and the cppstart block
      literals: [
        // Raw string: prefix R" delimiter ( ... ) delimiter "
        [/((?:u8|u|U|L)?R)(")([^ ()\\\t"]{0,16})(\()/, ['string', 'string', 'string', { token: 'string', next: '@raw.$3' }]],
        // Unterminated on its line (a trailing splice continues it instead)
        [/(?:u8|u|U|L)?"(?:[^"\\]|\\.)*$/, 'string.invalid'],
        [/(?:u8|u|U|L)?'(?:[^'\\]|\\.)*$/, 'string.invalid'],
        [/(?:u8|u|U|L)?"/, 'string', '@string'],
        [/(?:u8|u|U|L)?'/, 'string', '@char'],
        // Numbers (C++ pp-number shape; any suffix is part of the token)
        [new RegExp('(?:\\d|\\.\\d)' + PP_TAIL), {
          cases: {
            '~0[xX].*': 'number.hex',
            '~0[bB].*': 'number',
            '~[^eE]*(?:\\.|[eE][+\\-]?\\d).*': 'number.float',
            '@default': 'number'
          }
        }]
      ],

      string: [
        [/[^\\"]+/, 'string'],
        [/\\$/, 'string.escape'],
        [/\\./, 'string.escape'],
        // closing quote + a touching UD suffix ("abc"s)
        [/"\w*/, 'string', '@pop']
      ],
      char: [
        [/[^\\']+/, 'string'],
        [/\\$/, 'string.escape'],
        [/\\./, 'string.escape'],
        [/'\w*/, 'string', '@pop']
      ],
      // $S2 = the raw delimiter (state raw.<delimiter>), as Monaco's cpp tokenizer
      raw: [
        [/(.*)(\))([^ ()\\\t"]*)(")/, {
          cases: {
            '$3==$S2': ['string', 'string', 'string', { token: 'string', next: '@pop' }],
            '@default': ['string', 'string', 'string', 'string']
          }
        }],
        [/.*$/, 'string']
      ],

      // Not nesting (C++ rule)
      blockComment: [
        [/[^*]+/, 'comment'],
        [/\*\//, 'comment', '@pop'],
        [/\*/, 'comment']
      ],
      // A // comment whose line ends in a splice continues on the next line
      lineCommentSplice: [
        [/.*\\$/, 'comment'],
        [/.*$/, 'comment', '@pop']
      ],

      // # line: runs to the end of the logical line
      preproc: [
        [/.*\\$/, 'keyword.directive'],
        [/.*$/, 'keyword.directive', '@pop']
      ],

      // cppstart's target word, then the C++ block up to cppend
      cppTarget: [
        { include: '@whitespace' },
        [/(header|source)\b/, { token: 'keyword', switchTo: '@cppBlock' }],
        [/\S/, { token: '@rematch', next: '@pop' }]
      ],
      cppBlock: [
        [/^\s*(#|%:)/, { token: 'keyword.directive', next: '@preproc' }],
        { include: '@whitespace' },
        { include: '@literals' },
        [/[A-Za-z_]\w*/, {
          cases: {
            'cppend': { token: 'keyword', next: '@pop' },
            '@default': 'verbatim'
          }
        }],
        [/./, 'verbatim']
      ]
    }
  };

  var CONFIG = {
    comments: { lineComment: '//', blockComment: ['/*', '*/'] },
    brackets: [['(', ')'], ['[', ']'], ['{', '}']],
    autoClosingPairs: [
      { open: '(', close: ')' },
      { open: '[', close: ']' },
      { open: '{', close: '}' },
      { open: '"', close: '"', notIn: ['string', 'comment'] },
      { open: "'", close: "'", notIn: ['string', 'comment'] },
      { open: '/*', close: ' */', notIn: ['string'] }
    ],
    surroundingPairs: [
      { open: '(', close: ')' },
      { open: '[', close: ']' },
      { open: '{', close: '}' },
      { open: '"', close: '"' },
      { open: "'", close: "'" }
    ],
    indentationRules: {
      // A line opening a block, or a bare section header (var / const / type)
      increaseIndentPattern: /^\s*((.*\b(begin|repeat|record|object|overlay|choices|guard|except|finally|then|do|else|of|cppstart\s+(header|source))\b\s*)|((var|const|type|import)\s*))$/,
      decreaseIndentPattern: /^\s*(end\b|until\b|else\b|except\b|finally\b|cppend\b)/
    }
  };

  var THEME = {
    base: 'vs-dark',
    inherit: true,
    rules: [
      { token: 'keyword', foreground: '569CD6' },
      { token: 'keyword.directive', foreground: 'C586C0' },
      { token: 'type', foreground: '4EC9B0' },
      { token: 'annotation', foreground: 'C586C0' },
      { token: 'string.invalid', foreground: 'F44747' },
      { token: 'string.escape', foreground: 'D7BA7D' },
      { token: 'number.hex', foreground: 'B5CEA8' },
      { token: 'number.float', foreground: 'B5CEA8' },
      // cppstart block text: C++ (no PaskalCPP intelligence)
      { token: 'verbatim', foreground: 'BCBCBC' },
      // LSP semantic token types and modifiers; colours follow the Monarch
      // rules above. keyword, comment, string, number, type match existing
      // rules / the vs-dark base.
      { token: 'namespace', foreground: '4EC9B0' },
      { token: 'struct', foreground: '4EC9B0' },
      { token: 'class', foreground: '4EC9B0' },
      { token: 'enum', foreground: '4EC9B0' },
      { token: 'enumMember', foreground: '4FC1FF' },
      { token: 'parameter', foreground: '9CDCFE' },
      { token: 'variable', foreground: '9CDCFE' },
      { token: 'variable.readonly', foreground: '4FC1FF' },
      { token: 'property', foreground: '9CDCFE' },
      { token: 'function', foreground: 'DCDCAA' },
      { token: 'method', foreground: 'DCDCAA' },
      { token: 'operator', foreground: 'D4D4D4' },
      { token: 'macro', foreground: 'C586C0' }
    ],
    // Scrollbar slider = VS Code dark; same values as editor.css --pc-scroll-thumb*
    colors: {
      'scrollbarSlider.background': '#79797966',
      'scrollbarSlider.hoverBackground': '#646464b3',
      'scrollbarSlider.activeBackground': '#bfbfbf66'
    }
  };

  function register(AMonaco) {
    gMonaco = AMonaco;
    AMonaco.languages.register({ id: 'pcpp', extensions: ['.pcpp'], aliases: ['PaskalCPP', 'pcpp'] });
    AMonaco.languages.setMonarchTokensProvider('pcpp', MONARCH);
    AMonaco.languages.setLanguageConfiguration('pcpp', CONFIG);
    AMonaco.editor.defineTheme('pcpp-dark', THEME);
  }

  // The server's keyword and builtin type lists ({ keywords, types }); a
  // missing or malformed list leaves the current one. Setting the tokenizer
  // again makes Monaco re-colour every open pcpp model
  function setWords(AWords) {
    if (!AWords || !Array.isArray(AWords.keywords) || !Array.isArray(AWords.types)) {
      return;
    }
    WORDS = { keywords: AWords.keywords.slice(), types: AWords.types.slice() };
    MONARCH.keywords = WORDS.keywords;
    MONARCH.types = WORDS.types;
    if (gMonaco) {
      gMonaco.languages.setMonarchTokensProvider('pcpp', MONARCH);
    }
  }

  return { register: register, setWords: setWords };
})();
