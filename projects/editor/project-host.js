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

  PaskalCPP Editor - projects (main process side).

  A folder is a project when pcpp says so: `pcpp --project-info <folder>`
  prints one JSON line (TPCProject's own load and checks, so the editor and
  the compiler never disagree on "valid"). This file runs that query and
  answers what the rest of main.js asks: which project holds a file, the
  pcpp line for Build / Run / Pack in it, the program a debug session
  launches. A project is the folder whose project.toml is at its root,
  never searched for above it; an invalid project.toml or none = a plain
  folder. Paths from pcpp ('/' form) are made native here, once.
*/
'use strict';

const path = require('path');
const { execFile } = require('child_process');

// The JSON format this file reads (pcpp PaskalCPP.CLI.pas
// PC_CLI_PROJECT_INFO_FORMAT); another one is no project
const PC_PROJECT_INFO_FORMAT = 1;
// A query that has not answered by then is no project (pcpp only reads
// one small file)
const PC_PROJECT_INFO_TIMEOUT_MS = 15000;
// The kinds project.toml names (PaskalCPP.Project.pas PC_PRJ_KIND_TEXT)
const PC_PROJECT_KINDS = ['exe', 'dll', 'lib'];

// Windows paths compare case-insensitively
function pathKey(APath) {
  return path.resolve(APath).toLowerCase();
}

// True when AFile is AFolder or inside it
function isInside(AFolder, AFile) {
  const LFolder = pathKey(AFolder);
  const LFile = pathKey(AFile);
  return LFile === LFolder || LFile.startsWith(LFolder + path.sep);
}

// One field of pcpp's JSON as a native path ('' when missing)
function nativePath(AValue) {
  return typeof AValue === 'string' && AValue !== '' ? path.resolve(AValue) : '';
}

// pcpp's reports, each { severity, code, message } (the location is
// project.toml itself when there is one)
function readReports(AJson) {
  const LReports = [];
  if (!Array.isArray(AJson.reports)) {
    return LReports;
  }
  for (const LItem of AJson.reports) {
    if (LItem && typeof LItem.message === 'string') {
      LReports.push({
        severity: typeof LItem.severity === 'string' ? LItem.severity : 'error',
        code: typeof LItem.code === 'string' ? LItem.code : '',
        message: LItem.message
      });
    }
  }
  return LReports;
}

// The answer for ARoot: { root, project, valid, name, kind, main, output,
// bin, dat, reports, error }. Anything pcpp did not say plainly (another
// format, a field missing, a kind it does not name) is no valid project
function readInfo(ARoot, AJson) {
  const LInfo = {
    root: path.resolve(ARoot), project: false, valid: false, name: '', kind: '',
    main: '', output: '', bin: '', dat: '', reports: [], error: ''
  };

  if (!AJson || AJson.format !== PC_PROJECT_INFO_FORMAT) {
    LInfo.error = 'pcpp --project-info gave an unknown format';
    return LInfo;
  }
  LInfo.project = AJson.project === true;
  LInfo.reports = readReports(AJson);
  if (AJson.valid !== true) {
    return LInfo;
  }
  LInfo.name = typeof AJson.name === 'string' ? AJson.name : '';
  LInfo.kind = PC_PROJECT_KINDS.includes(AJson.kind) ? AJson.kind : '';
  LInfo.main = nativePath(AJson.main);
  LInfo.output = nativePath(AJson.output);
  LInfo.bin = nativePath(AJson.bin);
  LInfo.dat = nativePath(AJson.dat);
  if (LInfo.name === '' || LInfo.kind === '' || LInfo.main === '' || LInfo.output === '') {
    LInfo.error = 'pcpp --project-info left out a field';
    return LInfo;
  }
  LInfo.valid = true;
  return LInfo;
}

// Asks pcpp (ACompiler) about ARoot; always resolves, never rejects: a
// failed query is a folder with no project, its reason in .error
function queryProjectInfo(ACompiler, ARoot) {
  return new Promise((AResolve) => {
    const LRoot = path.resolve(ARoot);
    try {
      execFile(ACompiler, ['--project-info', LRoot],
        { windowsHide: true, timeout: PC_PROJECT_INFO_TIMEOUT_MS, encoding: 'utf8' },
        (AError, AStdout) => {
          let LJson = null;
          let LInfo;
          if (AError) {
            LInfo = readInfo(LRoot, null);
            LInfo.error = 'pcpp --project-info failed: ' + AError.message;
            AResolve(LInfo);
            return;
          }
          try {
            LJson = JSON.parse(String(AStdout).trim());
          } catch (AParseError) {
            LInfo = readInfo(LRoot, null);
            LInfo.error = 'pcpp --project-info printed no JSON: ' + AParseError.message;
            AResolve(LInfo);
            return;
          }
          AResolve(readInfo(LRoot, LJson));
        });
    } catch (AError) {
      const LInfo = readInfo(LRoot, null);
      LInfo.error = 'pcpp --project-info did not start: ' + AError.message;
      AResolve(LInfo);
    }
  });
}

// The valid project of AProjects (an iterable of infos) holding AFile; the
// deepest root wins when projects nest. null = none
function projectOf(AProjects, AFile) {
  let LBest = null;

  if (typeof AFile !== 'string' || !path.isAbsolute(AFile)) {
    return null;
  }
  for (const LInfo of AProjects) {
    if (LInfo.valid && isInside(LInfo.root, AFile)) {
      if (!LBest || LInfo.root.length > LBest.root.length) {
        LBest = LInfo;
      }
    }
  }
  return LBest;
}

// True when AFile (an absolute path) is the project.toml at ARoot
function isProjectFile(ARoot, AFile) {
  return pathKey(AFile) === pathKey(path.join(ARoot, 'project.toml'));
}

// What a debug session launches for AFile: the project's main module in a
// project, else AFile itself. { ok, program, error }; a lib project has
// nothing to launch
function debugProgramFor(AProjects, AFile) {
  const LInfo = projectOf(AProjects, AFile);

  if (!LInfo) {
    return { ok: true, program: AFile, error: '' };
  }
  if (LInfo.kind === 'lib') {
    return { ok: false, program: '', error: 'Project ' + LInfo.name + ' is a lib: there is nothing to debug.' };
  }
  return { ok: true, program: LInfo.main, error: '' };
}

module.exports = { queryProjectInfo, projectOf, isProjectFile, debugProgramFor, PC_PROJECT_KINDS };
