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
  UTestCase.JSON - StdApp.JSON reader tests

  TTestCase suite for the reads of TJSON (StdApp.JSON): the strict reads
  (TryGet*: exact JSON type, integer range, literal keys, the empty path,
  object / array views), the lenient reads on numbers no Int64 / Double
  holds (the default, never a raise), string numbers under a ',' decimal
  locale, and dot / [N] paths (nested indices). Inputs are JSON text parsed
  by TJSON.FromString.

  Dependencies: StdApp.TestCase, StdApp.JSON
===============================================================================}

unit UTestCase.JSON;

interface

uses
  StdApp.TestCase;

type

  { TPCJsonTests }
  TPCJsonTests = class(TTestCase)
  private
    // One test per concern; Create registers each under its CLI name
    procedure DoTestStrictTypes();
    procedure DoTestStrictIntegers();
    procedure DoTestStrictContainers();
    procedure DoTestLenientNoRaise();
    procedure DoTestLocale();
    procedure DoTestPaths();
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  StdApp.JSON;

const
  { TEST_JSON_TYPES }
  // One value of each JSON type, and a key with a dot in it
  TEST_JSON_TYPES =
    '{"s": "x", "n": 5, "b": true, "t": "true", "z": null, ' +
    '"o": {"k": 1}, "a": [1, "two", [3, 4]], "dot.key": "lit"}';

  { TEST_JSON_INTS }
  // Integers at and past the Int32 / Int64 bounds, a fraction, an exponent
  TEST_JSON_INTS =
    '{"i32max": 2147483647, "i32min": -2147483648, "i32over": 2147483648, ' +
    '"i64over": 9223372036854775808, "neg": -7, "zero": 0, "frac": 1.5, ' +
    '"exp": 1e3}';

  { TEST_JSON_LENIENT }
  // Numbers TJSONNumber.AsInt64 raises on (StrToInt64) and AsDouble answers
  // INF for (1e999), as a number and as a string
  TEST_JSON_LENIENT =
    '{"frac": 1.5, "huge": 1e40, "inf": 1e999, "sinf": "1e999", "half": 0.5, "zero": 0, ' +
    '"single": 1e300, "u64max": 18446744073709551615, "minus": -1, ' +
    '"u32over": 4294967296, "list": [1.5, 1], "ints": [1, 1.5, 1e40], ' +
    '"dbls": [1e999, 2.5]}';

  { TEST_JSON_LOCALE }
  // A number written as a string, and a number
  TEST_JSON_LOCALE = '{"s": "1.5", "n": 2.5}';

  { TEST_JSON_PATHS }
  // Nested arrays and objects, an empty array
  TEST_JSON_PATHS =
    '{"a": [[1, 2], [3, [4, 5]]], "o": {"p": {"q": "deep"}}, "e": []}';

{ TPCJsonTests }

constructor TPCJsonTests.Create();
begin
  inherited;

  Title := 'JSON';
  RegisterTest('strict_types', DoTestStrictTypes);
  RegisterTest('strict_integers', DoTestStrictIntegers);
  RegisterTest('strict_containers', DoTestStrictContainers);
  RegisterTest('lenient_no_raise', DoTestLenientNoRaise);
  RegisterTest('locale', DoTestLocale);
  RegisterTest('paths', DoTestPaths);
end;

procedure TPCJsonTests.Run();
begin
  inherited;
end;

procedure TPCJsonTests.DoTestStrictTypes();
var
  LJson: TJSON;
  LText: string;
  LFlag: Boolean;
  LNumber: Integer;
begin
  LJson := TJSON.FromString(TEST_JSON_TYPES);
  try
    Check(LJson.IsObject(), 'types: parsed');
    Check(LJson.TryGetString('s', LText) and (LText = 'x'), 'string: s = x');
    Check((not LJson.TryGetString('n', LText)) and (LText = ''),
      'string: a number is no string, out value empty');
    Check(not LJson.TryGetString('z', LText), 'string: null is no string');
    Check(not LJson.TryGetString('o', LText), 'string: an object is no string');
    Check(not LJson.TryGetString('missing', LText), 'string: absent');
    Check(LJson.TryGetBoolean('b', LFlag) and LFlag, 'boolean: b = true');
    Check((not LJson.TryGetBoolean('t', LFlag)) and (not LFlag),
      'boolean: the string "true" is no boolean');
    Check(not LJson.TryGetBoolean('n', LFlag), 'boolean: a number is no boolean');
    Check((not LJson.TryGetInt32('s', LNumber)) and (LNumber = 0),
      'int32: a string is no number, out value 0');
    Check(not LJson.TryGetInt32('b', LNumber), 'int32: a boolean is no number');
    Check(LJson.TryGetString('dot.key', LText, True) and (LText = 'lit'),
      'literal: the key dot.key read whole');
    Check(not LJson.TryGetString('dot.key', LText),
      'path: dot.key is the path dot / key');
  finally
    LJson.Free();
  end;

  // Text that is no JSON: every read answers False, nothing raises
  LJson := TJSON.FromString('{not json');
  try
    Check(not LJson.TryGetString('', LText), 'no JSON: empty path');
    Check(not LJson.TryGetInt32('s', LNumber), 'no JSON: a path');
  finally
    LJson.Free();
  end;

  // TryFromString tells text that is no JSON from the JSON text null
  Check((not TJSON.TryFromString('{not json', LJson)) and (LJson = nil),
    'TryFromString: no JSON gives False and nil');
  if TJSON.TryFromString('null', LJson) then
  begin
    try
      Check(LJson.IsNull() and (not LJson.IsObject()), 'TryFromString: null is JSON, a null value');
    finally
      LJson.Free();
    end;
  end
  else
    Check(False, 'TryFromString: null is JSON');
  if TJSON.TryFromString('{"k": 1}', LJson) then
  begin
    try
      Check(LJson.TryGetInt32('k', LNumber) and (LNumber = 1), 'TryFromString: an object');
    finally
      LJson.Free();
    end;
  end
  else
    Check(False, 'TryFromString: an object is JSON');
end;

procedure TPCJsonTests.DoTestStrictIntegers();
var
  LJson: TJSON;
  L32: Integer;
  L64: Int64;
begin
  LJson := TJSON.FromString(TEST_JSON_INTS);
  try
    Check(LJson.IsObject(), 'integers: parsed');
    Check(LJson.TryGetInt32('i32max', L32) and (L32 = High(Integer)), 'int32: High(Integer)');
    Check(LJson.TryGetInt32('i32min', L32) and (L32 = Low(Integer)), 'int32: Low(Integer)');
    Check((not LJson.TryGetInt32('i32over', L32)) and (L32 = 0),
      'int32: 2147483648 is past Integer, out value 0');
    Check(LJson.TryGetInt64('i32over', L64) and (L64 = 2147483648), 'int64: 2147483648');
    Check(not LJson.TryGetInt64('i64over', L64), 'int64: 9223372036854775808 is past Int64');
    Check(LJson.TryGetInt32('neg', L32) and (L32 = -7), 'int32: -7');
    Check(LJson.TryGetInt32('zero', L32) and (L32 = 0), 'int32: 0');
    Check(not LJson.TryGetInt32('frac', L32), 'int32: 1.5 is no integer');
    Check(not LJson.TryGetInt64('frac', L64), 'int64: 1.5 is no integer');
    Check(not LJson.TryGetInt32('exp', L32), 'int32: 1e3 is written with an exponent');
  finally
    LJson.Free();
  end;
end;

procedure TPCJsonTests.DoTestStrictContainers();
var
  LJson: TJSON;
  LObject: TJSON;
  LArray: TJSON;
  LItems: TArray<TJSON>;
  LNumber: Integer;
  LText: string;
begin
  LJson := TJSON.FromString(TEST_JSON_TYPES);
  try
    Check(LJson.TryGetObject('o', LObject) and LObject.TryGetInt32('k', LNumber) and
      (LNumber = 1), 'object: o.k through the view');
    Check((not LJson.TryGetObject('a', LObject)) and (LObject = nil),
      'object: an array is no object, out value nil');
    Check((not LJson.TryGetArray('o', LArray)) and (LArray = nil),
      'array: an object is no array, out value nil');
    Check(not LJson.TryGetArray('missing', LArray), 'array: absent');
    Check(LJson.TryGetInt32('o.k', LNumber) and (LNumber = 1), 'path: o.k');

    // An empty path reads the value itself: the items of an array
    Check(LJson.TryGetArray('a', LArray) and (LArray.Count() = 3), 'array: a has 3 items');
    if LArray <> nil then
    begin
      LItems := LArray.Items();
      Check(Length(LItems) = 3, 'items: 3 views');
      if Length(LItems) = 3 then
      begin
        Check(LItems[0].TryGetInt32('', LNumber) and (LNumber = 1), 'empty path: item 0 = 1');
        Check(LItems[1].TryGetString('', LText) and (LText = 'two'),
          'empty path: item 1 = two');
        Check(LItems[2].TryGetInt32('[1]', LNumber) and (LNumber = 4),
          'item path: item 2 [1] = 4');
      end;
    end;
  finally
    LJson.Free();
  end;
end;

procedure TPCJsonTests.DoTestLenientNoRaise();
var
  LJson: TJSON;
  LInts: TArray<Int64>;
  LInts32: TArray<Integer>;
  LDoubles: TArray<Double>;
begin
  LJson := TJSON.FromString(TEST_JSON_LENIENT);
  try
    try
      Check(LJson.IsObject(), 'lenient: parsed');
      Check(LJson.Get('frac').AsInt32(-1) = -1, 'AsInt32: 1.5 is the default');
      Check(LJson.Get('frac').AsInt64(-1) = -1, 'AsInt64: 1.5 is the default');
      Check(LJson.Get('huge').AsInt64(-1) = -1, 'AsInt64: 1e40 is the default');
      Check(LJson.Get('frac').AsUInt32(7) = 7, 'AsUInt32: 1.5 is the default');
      Check(LJson.Get('u32over').AsUInt32(7) = 7, 'AsUInt32: 4294967296 is past Cardinal');
      Check(LJson.Get('u64max').AsUInt64(7) = High(UInt64), 'AsUInt64: High(UInt64) whole');
      Check(LJson.Get('minus').AsUInt64(7) = 7, 'AsUInt64: -1 is the default');
      Check(LJson.Get('half').AsBoolean(False), 'AsBoolean: 0.5 is True');
      Check(not LJson.Get('zero').AsBoolean(True), 'AsBoolean: 0 is False');
      Check(LJson.Get('inf').AsBoolean(True) and (not LJson.Get('inf').AsBoolean(False)),
        'AsBoolean: 1e999 is the default');
      Check(LJson.Get('inf').AsDouble(-1) = -1, 'AsDouble: 1e999 is the default (got %g, text %s)',
        [LJson.Get('inf').AsDouble(-1), LJson.Get('inf').ToString()]);
      Check(LJson.Get('sinf').AsDouble(-1) = -1, 'AsDouble: the string "1e999" is the default');
      Check(LJson.Get('sinf').AsSingle(-1) = -1, 'AsSingle: the string "1e999" is the default');
      Check(LJson.Get('frac').AsDouble(-1) = 1.5, 'AsDouble: 1.5');
      Check(LJson.Get('single').AsSingle(-1) = -1, 'AsSingle: 1e300 is past Single');
      Check(LJson.Get('frac').AsSingle(-1) = 1.5, 'AsSingle: 1.5');
      Check(LJson.Get('list').Contains(1), 'Contains: 1 found past 1.5');
      Check(not LJson.Get('list').Contains(2), 'Contains: 2 absent');

      LInts := LJson.Get('ints').AsInt64Array();
      Check((Length(LInts) = 3) and (LInts[0] = 1) and (LInts[1] = 0) and (LInts[2] = 0),
        'AsInt64Array: [1, 1.5, 1e40] = [1, 0, 0]');
      LInts32 := LJson.Get('ints').AsInt32Array();
      Check((Length(LInts32) = 3) and (LInts32[0] = 1) and (LInts32[1] = 0) and
        (LInts32[2] = 0), 'AsInt32Array: [1, 1.5, 1e40] = [1, 0, 0]');
      LDoubles := LJson.Get('dbls').AsDoubleArray();
      Check((Length(LDoubles) = 2) and (LDoubles[0] = 0.0) and (LDoubles[1] = 2.5),
        'AsDoubleArray: [1e999, 2.5] = [0, 2.5]');
    except
      on E: Exception do
        Check(False, 'lenient: raised %s', [E.Message]);
    end;
  finally
    LJson.Free();
  end;
end;

procedure TPCJsonTests.DoTestLocale();
var
  LJson: TJSON;
  LSaved: Char;
begin
  // A string number is read with JSON's '.', whatever the machine's locale
  LSaved := FormatSettings.DecimalSeparator;
  FormatSettings.DecimalSeparator := ',';
  try
    LJson := TJSON.FromString(TEST_JSON_LOCALE);
    try
      Check(LJson.Get('s').AsDouble(-1) = 1.5, 'locale ,: AsDouble of the string "1.5"');
      Check(LJson.Get('s').AsSingle(-1) = 1.5, 'locale ,: AsSingle of the string "1.5"');
      Check(LJson.Get('n').AsDouble(-1) = 2.5, 'locale ,: AsDouble of the number 2.5');
    finally
      LJson.Free();
    end;
  finally
    FormatSettings.DecimalSeparator := LSaved;
  end;
end;

procedure TPCJsonTests.DoTestPaths();
var
  LJson: TJSON;
  LNumber: Integer;
  LText: string;
begin
  LJson := TJSON.FromString(TEST_JSON_PATHS);
  try
    Check(LJson.TryGetInt32('a[0][1]', LNumber) and (LNumber = 2), 'path: a[0][1] = 2');
    Check(LJson.TryGetInt32('a[1][1][0]', LNumber) and (LNumber = 4), 'path: a[1][1][0] = 4');
    Check(LJson.TryGetString('o.p.q', LText) and (LText = 'deep'), 'path: o.p.q = deep');
    Check(not LJson.TryGetInt32('a[2]', LNumber), 'path: a[2] is past the end');
    Check(not LJson.TryGetInt32('a[0', LNumber), 'path: an unclosed bracket is no path');
    Check(not LJson.TryGetInt32('a[0]x', LNumber), 'path: text after [N] is no path');
    Check(not LJson.TryGetInt32('e[0]', LNumber), 'path: an empty array has no [0]');
    Check(LJson.Has('a[1][1]') and (not LJson.Has('a[1][2]')), 'Has: nested index');
    Check(LJson.Get('a[1][0]').AsInt32(-1) = 3, 'Get: nested index');
    Check(LJson.Has('o', True) and (not LJson.Has('o.p', True)),
      'Has literal: no dot splitting');
  finally
    LJson.Free();
  end;
end;

end.
