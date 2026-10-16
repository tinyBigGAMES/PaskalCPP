{===============================================================================
  PaskalCPP™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://paskalcpp.org

  SPDX-License-Identifier: MPL-2.0

  This Source Code Form is subject to the terms of the
  Mozilla Public License, v. 2.0. If a copy of the MPL
  was not distributed with this file, You can obtain one
  at https://mozilla.org/MPL/2.0/.
-------------------------------------------------------------------------------
  PaskalCPP.LSP.Docs - a /// doc comment rendered as Markdown

  The parser keeps a declaration's doc comment raw (DocText); this unit turns
  it into the Markdown a hover shows (plans\done\PLAN-EDITOR.md E2.6). The body is
  Markdown as written; tags at a line's start give the structured parts:
    @param Name text    @returns text (@return)    @raises text
    @see Name           @deprecated text           @since text
    @example            (the following lines are PaskalCPP code)
  A tag's text runs on over the next lines until a blank line or another
  tag. An unknown @word stays in the text as written.

  Dependencies: System.SysUtils, System.Generics.Collections
===============================================================================}

unit PaskalCPP.LSP.Docs;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  { TPCDocSection }
  // Where the next continuation line of a doc comment goes
  TPCDocSection = (
    dsSummary,
    dsParam,
    dsReturns,
    dsRaises,
    dsSee,
    dsDeprecated,
    dsSince,
    dsExample
  );

  { TPCLspDocs }
  TPCLspDocs = record
  private
    class procedure DoAppend(const AList: TList<string>; const AText: string); static;
    class function DoJoin(const AList: TList<string>): string; static;
    class function DoDedent(const ALines: TList<string>): string; static;
  public
    // The Markdown for a raw doc comment ('' for none): deprecation first,
    // then the summary, Parameters, Returns, Raises, Since, See also and
    // Example, each a paragraph of its own
    class function Markdown(const ADocText: string): string; static;
  end;

implementation

{ TPCLspDocs }

class procedure TPCLspDocs.DoAppend(const AList: TList<string>; const AText: string);
begin
  // A continuation line joins the section's last entry
  if AText = '' then
    Exit;
  if AList.Count = 0 then
    AList.Add(AText)
  else if AList[AList.Count - 1] = '' then
    AList[AList.Count - 1] := AText
  else
    AList[AList.Count - 1] := AList[AList.Count - 1] + ' ' + AText;
end;

class function TPCLspDocs.DoJoin(const AList: TList<string>): string;
begin
  Result := string.Join(' ', AList.ToArray()).Trim();
end;

class function TPCLspDocs.DoDedent(const ALines: TList<string>): string;
var
  LIndent: Integer;
  LLine: string;
  LLead: Integer;
  LOut: TList<string>;
begin
  // The example keeps its own indentation, less the indent all its lines
  // share; blank lines at its end are dropped
  while (ALines.Count > 0) and (ALines[ALines.Count - 1].Trim() = '') do
    ALines.Delete(ALines.Count - 1);

  LIndent := MaxInt;
  for LLine in ALines do
  begin
    if LLine.Trim() = '' then
      Continue;
    LLead := Length(LLine) - Length(LLine.TrimLeft());
    if LLead < LIndent then
      LIndent := LLead;
  end;
  if LIndent = MaxInt then
    LIndent := 0;

  LOut := TList<string>.Create();
  try
    for LLine in ALines do
    begin
      if LLine.Trim() = '' then
        LOut.Add('')
      else
        LOut.Add(LLine.Substring(LIndent));
    end;
    Result := string.Join(#10, LOut.ToArray());
  finally
    LOut.Free();
  end;
end;

class function TPCLspDocs.Markdown(const ADocText: string): string;
var
  LSummary: TList<string>;
  LParamNames: TList<string>;
  LParamTexts: TList<string>;
  LReturns: TList<string>;
  LRaises: TList<string>;
  LSee: TList<string>;
  LDeprecated: TList<string>;
  LSince: TList<string>;
  LExample: TList<string>;
  LParts: TList<string>;
  LSection: TPCDocSection;
  LLine: string;
  LTrimmed: string;
  LTag: string;
  LRest: string;
  LSpace: Integer;
  LIndex: Integer;
  LItems: TList<string>;
  LText: string;
begin
  Result := '';
  if ADocText.Trim() = '' then
    Exit;

  LSummary := TList<string>.Create();
  LParamNames := TList<string>.Create();
  LParamTexts := TList<string>.Create();
  LReturns := TList<string>.Create();
  LRaises := TList<string>.Create();
  LSee := TList<string>.Create();
  LDeprecated := TList<string>.Create();
  LSince := TList<string>.Create();
  LExample := TList<string>.Create();
  LParts := TList<string>.Create();
  LItems := TList<string>.Create();
  try
    LSection := dsSummary;
    for LLine in ADocText.Split([#10]) do
    begin
      LTrimmed := LLine.Trim();

      // A tag: '@' then a word at the line's start
      LTag := '';
      LRest := '';
      if LTrimmed.StartsWith('@') then
      begin
        LSpace := LTrimmed.IndexOf(' ');
        if LSpace < 0 then
          LTag := LTrimmed.Substring(1)
        else
        begin
          LTag := LTrimmed.Substring(1, LSpace - 1);
          LRest := LTrimmed.Substring(LSpace + 1).Trim();
        end;
      end;

      if LTag = 'param' then
      begin
        // The first word names the parameter; the rest describes it
        LSpace := LRest.IndexOf(' ');
        if LSpace < 0 then
        begin
          LParamNames.Add(LRest);
          LParamTexts.Add('');
        end
        else
        begin
          LParamNames.Add(LRest.Substring(0, LSpace));
          LParamTexts.Add(LRest.Substring(LSpace + 1).Trim());
        end;
        LSection := dsParam;
      end
      else if (LTag = 'returns') or (LTag = 'return') then
      begin
        LReturns.Add(LRest);
        LSection := dsReturns;
      end
      else if LTag = 'raises' then
      begin
        LRaises.Add(LRest);
        LSection := dsRaises;
      end
      else if LTag = 'see' then
      begin
        LSee.Add(LRest);
        LSection := dsSee;
      end
      else if LTag = 'deprecated' then
      begin
        LDeprecated.Add(LRest);
        LSection := dsDeprecated;
      end
      else if LTag = 'since' then
      begin
        LSince.Add(LRest);
        LSection := dsSince;
      end
      else if LTag = 'example' then
      begin
        if LRest <> '' then
          LExample.Add(LRest);
        LSection := dsExample;
      end
      else if LSection = dsExample then
        // Code, as written (a blank line belongs to it too; an unknown @word
        // is code: PaskalCPP's own @directives may appear in an example)
        LExample.Add(LLine)
      else if LTag <> '' then
      begin
        // An unknown @word is text, as written, and ends a tag's run
        LSummary.Add(LLine);
        LSection := dsSummary;
      end
      else if LTrimmed = '' then
      begin
        // A blank line ends a tag's text and separates summary paragraphs
        LSection := dsSummary;
        LSummary.Add('');
      end
      else if LSection = dsParam then
        LParamTexts[LParamTexts.Count - 1] := (LParamTexts[LParamTexts.Count - 1] + ' ' + LTrimmed).Trim()
      else if LSection = dsReturns then
        DoAppend(LReturns, LTrimmed)
      else if LSection = dsRaises then
        DoAppend(LRaises, LTrimmed)
      else if LSection = dsSee then
        DoAppend(LSee, LTrimmed)
      else if LSection = dsDeprecated then
        DoAppend(LDeprecated, LTrimmed)
      else if LSection = dsSince then
        DoAppend(LSince, LTrimmed)
      else
        // Summary text, an unknown @word included, as written
        LSummary.Add(LLine);
    end;

    // Each part is a paragraph of its own
    if LDeprecated.Count > 0 then
      LParts.Add('**Deprecated:** ' + DoJoin(LDeprecated));
    LText := string.Join(#10, LSummary.ToArray()).Trim();
    if LText <> '' then
      LParts.Add(LText);
    if LParamNames.Count > 0 then
    begin
      LItems.Clear();
      LItems.Add('**Parameters**');
      for LIndex := 0 to LParamNames.Count - 1 do
      begin
        if LParamTexts[LIndex] = '' then
          LItems.Add('- `' + LParamNames[LIndex] + '`')
        else
          LItems.Add('- `' + LParamNames[LIndex] + '`: ' + LParamTexts[LIndex]);
      end;
      LParts.Add(string.Join(#10, LItems.ToArray()));
    end;
    if LReturns.Count > 0 then
      LParts.Add('**Returns:** ' + DoJoin(LReturns));
    if LRaises.Count > 0 then
      LParts.Add('**Raises:** ' + DoJoin(LRaises));
    if LSince.Count > 0 then
      LParts.Add('**Since:** ' + DoJoin(LSince));
    if LSee.Count > 0 then
    begin
      LItems.Clear();
      for LText in LSee do
        if LText.Trim() <> '' then
          LItems.Add('`' + LText.Trim() + '`');
      if LItems.Count > 0 then
        LParts.Add('**See also:** ' + string.Join(', ', LItems.ToArray()));
    end;
    if LExample.Count > 0 then
    begin
      LText := DoDedent(LExample);
      if LText <> '' then
        LParts.Add('**Example**' + #10 + '```pcpp' + #10 + LText + #10 + '```');
    end;

    Result := string.Join(#10#10, LParts.ToArray());
  finally
    LItems.Free();
    LParts.Free();
    LExample.Free();
    LSince.Free();
    LDeprecated.Free();
    LSee.Free();
    LRaises.Free();
    LReturns.Free();
    LParamTexts.Free();
    LParamNames.Free();
    LSummary.Free();
  end;
end;

end.
