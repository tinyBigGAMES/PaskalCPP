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
 PaskalCPP.Semantics - Semantic pass: resolution and checks on the AST

  TPCSemantics.Analyze walks every module in TPCAst.ModuleAt order (dependency
  order: an import is analyzed before its importer) and writes every result
  into the AST's Resolved* fields; the pass-internal frame stack holds no fact.
  Reports go through TErrors with SM codes. A failed check reports once and
  poisons the node (ResolvedType := ErrorType); the walk stops only at the
  TErrors budget (C1). Spec: research\cppmix\sem\, plan plans\PLAN-SEMANTICS.md.

  Dependencies: StdApp.Base (TBaseObject, TErrors), StdApp.Resources (RSSem*),
    StdApp.Utils (TUtils.StripLongPathPrefix), PaskalCPP.Common, PaskalCPP.AST
    (never Parser, Emitter, ZigBuild, SourceText)
===============================================================================}

unit PaskalCPP.Semantics;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  PaskalCPP.Common,
  PaskalCPP.AST,
  PaskalCPP.Scopes;

const
  { PC_ERR_SEM_001 }
  PC_ERR_SEM_001 = 'SM0001';   // <name> is used in its own declaration
  { PC_ERR_SEM_002 }
  PC_ERR_SEM_002 = 'SM0002';   // <name> is used before its declaration
  { PC_ERR_SEM_003 }
  PC_ERR_SEM_003 = 'SM0003';   // type <T> names itself
  { PC_ERR_SEM_004 }
  PC_ERR_SEM_004 = 'SM0004';   // <name> is already declared in this scope
  { PC_ERR_SEM_005 }
  PC_ERR_SEM_005 = 'SM0005';   // <Mod> has no <Name>
  { PC_ERR_SEM_006 }
  PC_ERR_SEM_006 = 'SM0006';   // <Name> is not exported by <Mod>
  { PC_ERR_SEM_007 }
  PC_ERR_SEM_007 = 'SM0007';   // <head> is not an imported module
  { PC_ERR_SEM_008 }
  PC_ERR_SEM_008 = 'SM0008';   // a qualified type has exactly two parts
  { PC_ERR_SEM_009 }
  PC_ERR_SEM_009 = 'SM0009';   // <T> has no member <m>
  { PC_ERR_SEM_010 }
  PC_ERR_SEM_010 = 'SM0010';   // choices <T> has no value <v>
  { PC_ERR_SEM_011 }
  PC_ERR_SEM_011 = 'SM0011';   // self / parent outside a method
  { PC_ERR_SEM_012 }
  PC_ERR_SEM_012 = 'SM0012';   // parent: <T> has no parent type
  { PC_ERR_SEM_013 }
  PC_ERR_SEM_013 = 'SM0013';   // <name> is not a type
  { PC_ERR_SEM_014 }
  PC_ERR_SEM_014 = 'SM0014';   // '->' on a module or a type
  { PC_ERR_SEM_015 }
  PC_ERR_SEM_015 = 'SM0015';   // <v> is a choice value: write <T>.<v>
  { PC_ERR_SEM_016 }
  PC_ERR_SEM_016 = 'SM0016';   // parent outside parent.<member>
  { PC_ERR_SEM_017 }
  PC_ERR_SEM_017 = 'SM0017';   // <name>: names starting with pcpp_ are reserved for the compiler (M11)
  { PC_ERR_SEM_018 }
  PC_ERR_SEM_018 = 'SM0018';   // <m> is a member of <T>: write self.<m> (PLAN-OBJECT D9)
  { PC_ERR_SEM_019 }
  PC_ERR_SEM_019 = 'SM0019';   // <m> is hidden in <T> (PLAN-OBJECT D10)
  { PC_ERR_SEM_020 }
  PC_ERR_SEM_020 = 'SM0020';   // <name> is in two imported units: write a.<name> or b.<name> (PLAN-IMPORT-RESOLUTION)
  { PC_ERR_SEM_100 }
  PC_ERR_SEM_100 = 'SM0100';   // <value> is not a value of @<dir>: <accepted>
  { PC_ERR_SEM_101 }
  PC_ERR_SEM_101 = 'SM0101';   // @<vi*> takes 0..65535
  { PC_ERR_SEM_102 }
  PC_ERR_SEM_102 = 'SM0102';   // @<dir> is already given at line <n>
  { PC_ERR_SEM_103 }
  PC_ERR_SEM_103 = 'SM0103';   // @<dir> does not apply to <kind / target>: not used
  { PC_ERR_SEM_104 }
  PC_ERR_SEM_104 = 'SM0104';   // @<vi*> has no effect without @addverinfo on
  { PC_ERR_SEM_105 }
  PC_ERR_SEM_105 = 'SM0105';   // <path> is not an existing file
  { PC_ERR_SEM_106 }
  PC_ERR_SEM_106 = 'SM0106';   // <path> is not an existing directory
  { PC_ERR_SEM_107 }
  PC_ERR_SEM_107 = 'SM0107';   // cannot check <path>: <E.Message>
  { PC_ERR_SEM_108 }
  PC_ERR_SEM_108 = 'SM0108';   // the @message text, at its severity
  { PC_ERR_SEM_109 }
  PC_ERR_SEM_109 = 'SM0109';   // @breakpoint in the prologue has no effect
  { PC_ERR_SEM_110 }
  PC_ERR_SEM_110 = 'SM0110';   // @unitTestMode in a dll / lib (no program runs the tests)
  { PC_ERR_SEM_111 }
  PC_ERR_SEM_111 = 'SM0111';   // a test name is empty
  { PC_ERR_SEM_112 }
  PC_ERR_SEM_112 = 'SM0112';   // test <name> is already declared at line <n>
  { PC_ERR_SEM_113 }
  PC_ERR_SEM_113 = 'SM0113';   // test blocks of a dll / lib never run
  { PC_ERR_SEM_114 }
  PC_ERR_SEM_114 = 'SM0114';   // @addsourcefile <path>: not a name the toolchain compiles
  { PC_ERR_SEM_115 }
  PC_ERR_SEM_115 = 'SM0115';   // @cppdefine / @cppundef <name>: not a C macro name
  { PC_ERR_SEM_116 }
  PC_ERR_SEM_116 = 'SM0116';   // <name>: PCPP_ names are the compiler's and the runtime's
  { PC_ERR_SEM_117 }
  PC_ERR_SEM_117 = 'SM0117';   // the value of @cppdefine <name> is more than one line
  { PC_ERR_SEM_118 }
  PC_ERR_SEM_118 = 'SM0118';   // <this one> conflicts with <earlier one> at <file>:<line>
  { PC_ERR_SEM_200 }
  PC_ERR_SEM_200 = 'SM0200';   // <from> does not convert implicitly to <to>[; write <cast>] | <constant> does not fit in <to> (<low>..<high>)
  { PC_ERR_SEM_202 }
  PC_ERR_SEM_202 = 'SM0202';   // <position> must be a constant
  { PC_ERR_SEM_250 }
  PC_ERR_SEM_250 = 'SM0250';   // operator <op> does not take <T> [and <U>]
  // SM0251 SM0256-SM0259: constant folding (F27, research\paskal-errors\
  // r-a-folding.md; meanings research\cppmix\sem\split.md :116 :121-:124)
  { PC_ERR_SEM_251 }
  PC_ERR_SEM_251 = 'SM0251';   // <op> would convert signed <T> to unsigned <U>; write <cast>
  { PC_ERR_SEM_256 }
  PC_ERR_SEM_256 = 'SM0256';   // constant overflows <T>
  { PC_ERR_SEM_257 }
  PC_ERR_SEM_257 = 'SM0257';   // division / modulo by zero
  { PC_ERR_SEM_258 }
  PC_ERR_SEM_258 = 'SM0258';   // <min> div|mod -1 overflows <T>
  { PC_ERR_SEM_259 }
  PC_ERR_SEM_259 = 'SM0259';   // shift count <n> outside 0..<w-1>
  { PC_ERR_SEM_252 }
  PC_ERR_SEM_252 = 'SM0252';   // operator <op> cannot compare <T>: a record / overlay / object (or an array of one) with no declared operator for it (O15)
  { PC_ERR_SEM_255 }
  PC_ERR_SEM_255 = 'SM0255';   // <target> cannot be assigned
  { PC_ERR_SEM_265 }
  PC_ERR_SEM_265 = 'SM0265';   // <from> cannot be cast to <to>: a pointer cast (type_pointer, PLAN-COMPLIANCE F48)
  { PC_ERR_SEM_253 }
  PC_ERR_SEM_253 = 'SM0253';   // <x> is an untyped ptr: ^ / [i] need a typed pointer (type_pointer, PLAN-COMPLIANCE F49)
  { PC_ERR_SEM_254 }
  PC_ERR_SEM_254 = 'SM0254';   // address of a value that is not stored (expr_unary_postfix, PLAN-COMPLIANCE F57)
  { PC_ERR_SEM_260 }
  PC_ERR_SEM_260 = 'SM0260';   // <T> cannot be indexed
  { PC_ERR_SEM_261 }
  PC_ERR_SEM_261 = 'SM0261';   // an index is an integer, got <T>
  { PC_ERR_SEM_263 }
  PC_ERR_SEM_263 = 'SM0263';   // a condition is bool, got <T>
  { PC_ERR_SEM_266 }
  PC_ERR_SEM_266 = 'SM0266';   // set literal elements are of different ordinal types
  { PC_ERR_SEM_267 }
  PC_ERR_SEM_267 = 'SM0267';   // low bound <l> exceeds high bound <h>
  { PC_ERR_SEM_268 }
  PC_ERR_SEM_268 = 'SM0268';   // in: <T> is not the element type of <S>
  { PC_ERR_SEM_269 }
  PC_ERR_SEM_269 = 'SM0269';   // <T> is a type / a module, not a value
  { PC_ERR_SEM_270 }
  PC_ERR_SEM_270 = 'SM0270';   // a reference or pointer to a value that may be misaligned (a packed record holds it, M8)
  { PC_ERR_SEM_271 }
  PC_ERR_SEM_271 = 'SM0271';   // is / as on what is not a polymorphic object or a ptr / own / ref of one (O12)
  { PC_ERR_SEM_272 }
  PC_ERR_SEM_272 = 'SM0272';   // is / as names a type that is not an object or an interface (O12)
  { PC_ERR_SEM_273 }
  PC_ERR_SEM_273 = 'SM0273';   // is / as never holds: no object is both types (O12)
  { PC_ERR_SEM_274 }
  PC_ERR_SEM_274 = 'SM0274';   // is / as never holds: the operand holds exactly its type (O12)
  { PC_ERR_SEM_275 }
  PC_ERR_SEM_275 = 'SM0275';   // is / as on a weak: test lock(W) (O12)
  { PC_ERR_SEM_276 }
  PC_ERR_SEM_276 = 'SM0276';   // index <i> is outside <T> (<lo>..<hi>): a constant index of a static array (F45)
  { PC_ERR_SEM_277 }
  PC_ERR_SEM_277 = 'SM0277';   // <T> is too large: a type holds at most PC_MAX_OBJECT_SIZE bytes (F47)

  // DECLS (SM0300-SM0399; research\cppmix\sem\split.md DECLS table)
  { PC_ERR_SEM_300 }
  PC_ERR_SEM_300 = 'SM0300';   // <T> is only forward-declared: use ptr to <T> or declare it first
  { PC_ERR_SEM_301 }
  PC_ERR_SEM_301 = 'SM0301';   // an external variable takes no initializer
  { PC_ERR_SEM_302 }
  PC_ERR_SEM_302 = 'SM0302';   // an external variable is declared at module level only
  { PC_ERR_SEM_303 }
  PC_ERR_SEM_303 = 'SM0303';   // forward type <T> has no full declaration here
  { PC_ERR_SEM_304 }
  PC_ERR_SEM_304 = 'SM0304';   // <T> is already declared (forward after its full)
  { PC_ERR_SEM_305 }
  PC_ERR_SEM_305 = 'SM0305';   // a forward type is completed by a record, object or overlay
  { PC_ERR_SEM_306 }
  PC_ERR_SEM_306 = 'SM0306';   // forward and full declaration of <name> differ: <fact>
  { PC_ERR_SEM_307 }
  PC_ERR_SEM_307 = 'SM0307';   // forward routine <name> has no matching full declaration
  { PC_ERR_SEM_308 }
  PC_ERR_SEM_308 = 'SM0308';   // <T> cannot be the parent of a record / object
  { PC_ERR_SEM_309 }
  PC_ERR_SEM_309 = 'SM0309';   // <name> reuses a name of the parent chain
  // SM0310-SM0312 SM0314-SM0316: BNF sec 3 limits, one on every target
  // (DESIGN sec 7). SM0311 (natural alignment) is SEM's when every leaf of
  // the record's layout has an alignment PaskalCPP knows on the target
  // (PC_ALIGN_MODELS, PLAN-PASKAL-ERRORS E2); a C/C++ leaf leaves it to the
  // emitted check, reported in the same words (E3). SM0313 (an overlay
  // member is trivial data) is SEM's for every PaskalCPP leaf; a C/C++ leaf
  // leaves it to the emitted check, reported in the same words (F34: clang
  // rejected it in C++ words at the variable, DESIGN sec 5)
  { PC_ERR_SEM_310 }
  PC_ERR_SEM_310 = 'SM0310';   // align <n> is not a power of two
  { PC_ERR_SEM_311 }
  PC_ERR_SEM_311 = 'SM0311';   // align <n> is below the natural alignment <m> of <T>, lower it with packed
  { PC_ERR_SEM_312 }
  PC_ERR_SEM_312 = 'SM0312';   // align <n> exceeds 8192
  { PC_ERR_SEM_313 }
  PC_ERR_SEM_313 = 'SM0313';   // an overlay's field holds a string / wstring / dynamic array, or a C/C++ type that is not trivial data (F34)
  { PC_ERR_SEM_314 }
  PC_ERR_SEM_314 = 'SM0314';   // a bitfield is an integer, bool, char, wchar or choices field
  { PC_ERR_SEM_315 }
  PC_ERR_SEM_315 = 'SM0315';   // bitfield width <n> outside 1..<bits>
  { PC_ERR_SEM_316 }
  PC_ERR_SEM_316 = 'SM0316';   // bitfield width <n> does not hold the ordinals of <T> as signed values
  { PC_ERR_SEM_318 }
  PC_ERR_SEM_318 = 'SM0318';   // a set of integers names its range: set of 0..255
  { PC_ERR_SEM_319 }
  PC_ERR_SEM_319 = 'SM0319';   // set of wchar: its size differs by target
  { PC_ERR_SEM_320 }
  PC_ERR_SEM_320 = 'SM0320';   // set range bounds are of different ordinal families
  { PC_ERR_SEM_321 }
  PC_ERR_SEM_321 = 'SM0321';   // a set has at most 65536 members
  { PC_ERR_SEM_322 }
  PC_ERR_SEM_322 = 'SM0322';   // array bounds are integer, char or choices of one family
  { PC_ERR_SEM_323 }
  PC_ERR_SEM_323 = 'SM0323';   // <name> is overloaded: C linkage dropped (warning, R-LINK)
  { PC_ERR_SEM_324 }
  PC_ERR_SEM_324 = 'SM0324';   // <name> is already declared with these parameter types (R-DECL; sem\split.md)
  { PC_ERR_SEM_325 }
  PC_ERR_SEM_325 = 'SM0325';   // a clink variadic routine with a body needs a fixed parameter before ... (BNF sec 3; sem\split.md)
  { PC_ERR_SEM_326 }
  PC_ERR_SEM_326 = 'SM0326';   // <name> must be a const string (external library)
  { PC_ERR_SEM_327 }
  PC_ERR_SEM_327 = 'SM0327';   // external takes a library name, not a file
  { PC_ERR_SEM_328 }
  PC_ERR_SEM_328 = 'SM0328';   // low bound above high bound (set range, static array)
  { PC_ERR_SEM_329 }
  PC_ERR_SEM_329 = 'SM0329';   // a set element is char, bool or choices
  { PC_ERR_SEM_330 }
  PC_ERR_SEM_330 = 'SM0330';   // a cpplink variadic routine cannot share its name with another routine (V4)
  { PC_ERR_SEM_331 }
  PC_ERR_SEM_331 = 'SM0331';   // a field of a packed record must pack: no string / wstring / dynamic array held (M9)
  { PC_ERR_SEM_332 }
  PC_ERR_SEM_332 = 'SM0332';   // a method of a parent's virtual method name: write override (PLAN-OBJECT D7)
  { PC_ERR_SEM_333 }
  PC_ERR_SEM_333 = 'SM0333';   // override of no virtual method of the parent chain (D7)
  { PC_ERR_SEM_334 }
  PC_ERR_SEM_334 = 'SM0334';   // an override takes the overridden method's parameters and result (D7)
  { PC_ERR_SEM_335 }
  PC_ERR_SEM_335 = 'SM0335';   // override of a final method (D7)
  { PC_ERR_SEM_336 }
  PC_ERR_SEM_336 = 'SM0336';   // final on a method that is not virtual or override (D7)
  { PC_ERR_SEM_337 }
  PC_ERR_SEM_337 = 'SM0337';   // abstract on a method that is not virtual or override (D7)
  { PC_ERR_SEM_338 }
  PC_ERR_SEM_338 = 'SM0338';   // an abstract object held by value or created (D7)
  { PC_ERR_SEM_339 }
  PC_ERR_SEM_339 = 'SM0339';   // a final object named as a parent (D7)
  { PC_ERR_SEM_340 }
  PC_ERR_SEM_340 = 'SM0340';   // parent.M() of an abstract method: no body to call (D7)
  { PC_ERR_SEM_341 }
  PC_ERR_SEM_341 = 'SM0341';   // an object has one done (PLAN-OBJECT D3)
  { PC_ERR_SEM_342 }
  PC_ERR_SEM_342 = 'SM0342';   // init is never called by name (D3)
  { PC_ERR_SEM_343 }
  PC_ERR_SEM_343 = 'SM0343';   // done is never called by name (D3)
  { PC_ERR_SEM_344 }
  PC_ERR_SEM_344 = 'SM0344';   // parent.init(...) is an init's first statement (D3)
  { PC_ERR_SEM_345 }
  PC_ERR_SEM_345 = 'SM0345';   // self.F.init(...) in declaration order, each field once (D3)
  { PC_ERR_SEM_346 }
  PC_ERR_SEM_346 = 'SM0346';   // a leading init call's argument names self, parent or a local (D3)
  { PC_ERR_SEM_347 }
  PC_ERR_SEM_347 = 'SM0347';   // the parent / an object field needs init arguments every init gives (D3)
  { PC_ERR_SEM_348 }
  PC_ERR_SEM_348 = 'SM0348';   // a virtual method called through self in an init or a done (D3)
  { PC_ERR_SEM_349 }
  PC_ERR_SEM_349 = 'SM0349';   // an object with no init without arguments built without them (D3)
  { PC_ERR_SEM_350 }
  PC_ERR_SEM_350 = 'SM0350';   // init arguments on a type that is no object (D3)
  { PC_ERR_SEM_351 }
  PC_ERR_SEM_351 = 'SM0351';   // no init of the object takes the arguments (D3)
  { PC_ERR_SEM_352 }
  PC_ERR_SEM_352 = 'SM0352';   // the arguments fit more than one init (D3)
  { PC_ERR_SEM_353 }
  PC_ERR_SEM_353 = 'SM0353';   // copy takes one const parameter of its own type (O5)
  { PC_ERR_SEM_354 }
  PC_ERR_SEM_354 = 'SM0354';   // an object declares copy twice (O5)
  { PC_ERR_SEM_355 }
  PC_ERR_SEM_355 = 'SM0355';   // a copy whose parent cannot be copied (O5)
  { PC_ERR_SEM_356 }
  PC_ERR_SEM_356 = 'SM0356';   // parent.init(...) in a copy (O5)
  { PC_ERR_SEM_357 }
  PC_ERR_SEM_357 = 'SM0357';   // a record / overlay field holds an object (O5, H3)
  { PC_ERR_SEM_358 }
  PC_ERR_SEM_358 = 'SM0358';   // own / ref / weak of a type that is no object (O6)
  { PC_ERR_SEM_359 }
  PC_ERR_SEM_359 = 'SM0359';   // weak T(...): a weak builds no object (O6)
  { PC_ERR_SEM_360 }
  PC_ERR_SEM_360 = 'SM0360';   // W.X on a weak: read it through lock(W) (O6, Q3)
  { PC_ERR_SEM_361 }
  PC_ERR_SEM_361 = 'SM0361';   // create / destroy on an object: own / ref hold it (O6, D4)
  { PC_ERR_SEM_362 }
  PC_ERR_SEM_362 = 'SM0362';   // a name after implements is not an interface (O7)
  { PC_ERR_SEM_363 }
  PC_ERR_SEM_363 = 'SM0363';   // an interface named twice after implements (O7)
  { PC_ERR_SEM_364 }
  PC_ERR_SEM_364 = 'SM0364';   // an object does not implement an interface's method (O7)
  { PC_ERR_SEM_365 }
  PC_ERR_SEM_365 = 'SM0365';   // the method that implements an interface's is not virtual (O7, user 2026-10-13)
  { PC_ERR_SEM_366 }
  PC_ERR_SEM_366 = 'SM0366';   // the method that implements an interface's has another signature (O7)
  { PC_ERR_SEM_367 }
  PC_ERR_SEM_367 = 'SM0367';   // the method that implements an interface's is hidden (O7)
  { PC_ERR_SEM_368 }
  PC_ERR_SEM_368 = 'SM0368';   // an interface repeats a method of its parent interface (O7)
  { PC_ERR_SEM_369 }
  PC_ERR_SEM_369 = 'SM0369';   // an embed's type is not a record, an overlay or an object (O8, D2)
  { PC_ERR_SEM_370 }
  PC_ERR_SEM_370 = 'SM0370';   // a name two embeds share, at the use (O8, D2)
  { PC_ERR_SEM_371 }
  PC_ERR_SEM_371 = 'SM0371';   // a property's read / write binds a name that is no field of its object (O9, D12)
  { PC_ERR_SEM_372 }
  PC_ERR_SEM_372 = 'SM0372';   // a property's bound field has another type than the property (O9)
  { PC_ERR_SEM_373 }
  PC_ERR_SEM_373 = 'SM0373';   // a property's read changes self (an assignment, a method call through self) (O9)
  { PC_ERR_SEM_374 }
  PC_ERR_SEM_374 = 'SM0374';   // a property read in its own read, or assigned in its own write: use the field (O9)
  { PC_ERR_SEM_375 }
  PC_ERR_SEM_375 = 'SM0375';   // a property without write is assigned (O9)
  { PC_ERR_SEM_376 }
  PC_ERR_SEM_376 = 'SM0376';   // a property used as storage: address of it (a var parameter is SM0405) (O9)
  { PC_ERR_SEM_377 }
  PC_ERR_SEM_377 = 'SM0377';   // an assignment to a property used as a value (it is a statement) (O9)
  { PC_ERR_SEM_378 }
  PC_ERR_SEM_378 = 'SM0378';   // an indexed property used without its index (O10)
  { PC_ERR_SEM_379 }
  PC_ERR_SEM_379 = 'SM0379';   // default on a property with no index, or a second default in a type (O10)
  { PC_ERR_SEM_380 }
  PC_ERR_SEM_380 = 'SM0380';   // an operator with the wrong number of operands (O11)
  { PC_ERR_SEM_381 }
  PC_ERR_SEM_381 = 'SM0381';   // an operator none of whose operands is the declaring type (O11)
  { PC_ERR_SEM_382 }
  PC_ERR_SEM_382 = 'SM0382';   // a comparison / in operator that does not give bool (O11)
  { PC_ERR_SEM_383 }
  PC_ERR_SEM_383 = 'SM0383';   // an operator declared twice with the same operand types (O11)
  { PC_ERR_SEM_384 }
  PC_ERR_SEM_384 = 'SM0384';   // an operator operand passed var (O11)
  { PC_ERR_SEM_386 }
  PC_ERR_SEM_386 = 'SM0386';   // = without <> (or <> without =) of the same operand types (O11)
  { PC_ERR_SEM_387 }
  PC_ERR_SEM_387 = 'SM0387';   // a const method changes self (O13b (3))
  { PC_ERR_SEM_388 }
  PC_ERR_SEM_388 = 'SM0388';   // a const method calls a method that is not const through self (O13b (3))
  { PC_ERR_SEM_389 }
  PC_ERR_SEM_389 = 'SM0389';   // an override / implementer does not keep the const of the method it continues (O13b (3))
  { PC_ERR_SEM_400 }
  PC_ERR_SEM_400 = 'SM0400';   // <x> is not callable: its PaskalCPP type is no routine type (expr_call_member, PLAN-COMPLIANCE F58)
  { PC_ERR_SEM_401 }
  PC_ERR_SEM_401 = 'SM0401';   // <name> takes <n> arguments, <m> given (F51: a PaskalCPP routine / routine type; at least <n> with `...`)
  { PC_ERR_SEM_402 }
  PC_ERR_SEM_402 = 'SM0402';   // no overload of <name> takes (<argument types>) by PaskalCPP's conversions (F18; R-RANK 4, sem\split.md)
  { PC_ERR_SEM_404 }
  PC_ERR_SEM_404 = 'SM0404';   // argument <i> of a PaskalCPP routine does not convert implicitly[; write <cast>] | its constant does not fit
  { PC_ERR_SEM_405 }
  PC_ERR_SEM_405 = 'SM0405';   // var parameter <p> needs a variable of type <T>
  { PC_ERR_SEM_406 }
  PC_ERR_SEM_406 = 'SM0406';   // a procedure call has no value
  { PC_ERR_SEM_408 }
  PC_ERR_SEM_408 = 'SM0408';   // <intrinsic> is a statement, not a value
  { PC_ERR_SEM_409 }
  PC_ERR_SEM_409 = 'SM0409';   // <intrinsic> takes <signature>
  { PC_ERR_SEM_410 }
  PC_ERR_SEM_410 = 'SM0410';   // size needs a type, got a value
  { PC_ERR_SEM_411 }
  PC_ERR_SEM_411 = 'SM0411';   // only size takes a type argument
  { PC_ERR_SEM_412 }
  PC_ERR_SEM_412 = 'SM0412';   // a cast <T>(...) takes exactly one argument
  { PC_ERR_SEM_413 }
  PC_ERR_SEM_413 = 'SM0413';   // a record literal needs a PaskalCPP record with no C/C++ parent (M14)
  { PC_ERR_SEM_414 }
  PC_ERR_SEM_414 = 'SM0414';   // record literal: <T> has no field <f>
  { PC_ERR_SEM_415 }
  PC_ERR_SEM_415 = 'SM0415';   // record literal: field <f> is given twice
  { PC_ERR_SEM_416 }
  PC_ERR_SEM_416 = 'SM0416';   // record literal: <f> comes before <g> in <T>
  { PC_ERR_SEM_417 }
  PC_ERR_SEM_417 = 'SM0417';   // varargs outside a variadic routine
  { PC_ERR_SEM_418 }
  PC_ERR_SEM_418 = 'SM0418';   // varargs.<member> needs a cpplink variadic
  { PC_ERR_SEM_421 }
  PC_ERR_SEM_421 = 'SM0421';   // varargs is not a value: use a member
  { PC_ERR_SEM_422 }
  PC_ERR_SEM_422 = 'SM0422';   // varargs is only the type of a variadic routine's local, set from copy()
  { PC_ERR_SEM_423 }
  PC_ERR_SEM_423 = 'SM0423';   // <intrinsic> is an intrinsic: it is called, never a value
  { PC_ERR_SEM_424 }
  PC_ERR_SEM_424 = 'SM0424';   // varargs.count / a varargs local's count is a value, not a call (BNF sec 6)
  { PC_ERR_SEM_425 }
  PC_ERR_SEM_425 = 'SM0425';   // <T> cannot be printed (a record / object / overlay, or an array of one; E7)
  { PC_ERR_SEM_426 }
  PC_ERR_SEM_426 = 'SM0426';   // a method called through a const object: it may change it, pass it var (PLAN-OBJECT)
  { PC_ERR_SEM_427 }
  PC_ERR_SEM_427 = 'SM0427';   // a value whose type cannot be copied would be copied (O5, D5)
  { PC_ERR_SEM_428 }
  PC_ERR_SEM_428 = 'SM0428';   // a polymorphic object by value to a base: slicing (O5, D6)
  { PC_ERR_SEM_429 }
  PC_ERR_SEM_429 = 'SM0429';   // an assignment into a polymorphic object that may be a descendant (TODO.md 8 (a))
  { PC_ERR_SEM_430 }
  PC_ERR_SEM_430 = 'SM0430';   // no declared operator takes the operands (O11)
  { PC_ERR_SEM_431 }
  PC_ERR_SEM_431 = 'SM0431';   // several declared operators take the operands alike (O11)
  { PC_ERR_SEM_432 }
  PC_ERR_SEM_432 = 'SM0432';   // a method named as a value (O13, F-A5a)
  { PC_ERR_SEM_500 }
  PC_ERR_SEM_500 = 'SM0500';   // PRINT: a format string that is not a string literal (clang's check, the Compiler reports; PLAN-VENDOR 1e)
  { PC_ERR_SEM_502 }
  PC_ERR_SEM_502 = 'SM0502';   // PRINT: a format string literal does not fit its arguments (clang's check, the Compiler reports; PLAN-VENDOR 1e)
  { PC_ERR_SEM_600 }
  PC_ERR_SEM_600 = 'SM0600';   // for needs a variable: <name> is <kind>
  { PC_ERR_SEM_601 }
  PC_ERR_SEM_601 = 'SM0601';   // a for iterator is an integer, char, wchar or a choice, got <T>
  { PC_ERR_SEM_602 }
  PC_ERR_SEM_602 = 'SM0602';   // <name> is the for iterator: the loop body cannot write it
  { PC_ERR_SEM_603 }
  PC_ERR_SEM_603 = 'SM0603';   // a match subject is an integer, char, wchar or a choice, got <T>
  { PC_ERR_SEM_604 }
  PC_ERR_SEM_604 = 'SM0604';   // match label <v> is outside <T>
  { PC_ERR_SEM_605 }
  PC_ERR_SEM_605 = 'SM0605';   // match label <v> repeats a label of the arm at line <n> (note)
  { PC_ERR_SEM_606 }
  PC_ERR_SEM_606 = 'SM0606';   // match on <T> does not cover: <values> (warning)
  { PC_ERR_SEM_607 }
  PC_ERR_SEM_607 = 'SM0607';   // leave outside a loop or match
  { PC_ERR_SEM_608 }
  PC_ERR_SEM_608 = 'SM0608';   // skip outside a loop
  { PC_ERR_SEM_609 }
  PC_ERR_SEM_609 = 'SM0609';   // <leave|skip|return> cannot jump out of finally
  { PC_ERR_SEM_610 }
  PC_ERR_SEM_610 = 'SM0610';   // return needs a value of type <T>
  { PC_ERR_SEM_611 }
  PC_ERR_SEM_611 = 'SM0611';   // return takes no value here
  { PC_ERR_SEM_612 }
  PC_ERR_SEM_612 = 'SM0612';   // missing return
  { PC_ERR_SEM_613 }
  PC_ERR_SEM_613 = 'SM0613';   // statement has no effect
  { PC_ERR_SEM_614 }
  PC_ERR_SEM_614 = 'SM0614';   // C++ <jump> in a guard body leaves only the guard's hidden function
  { PC_ERR_SEM_615 }
  PC_ERR_SEM_615 = 'SM0615';   // <exccode|excmsg> outside an except body
  { PC_SET_MAX_MEMBERS }
  // The most members a set holds (Q25b)
  PC_SET_MAX_MEMBERS = 65536;
  { PC_BITFIELD_BYTE_BITS }
  // A bool / char bitfield is at most 8 bits on every target (probed: 9
  // fails on windows-gnu, linux-gnu takes it; an integer over its bits too)
  PC_BITFIELD_BYTE_BITS = 8;
  { PC_BITFIELD_WCHAR_BITS }
  // A wchar bitfield is at most 16 bits on every target: wchar is 16 bits on
  // windows-gnu and 32 on linux-gnu (probed: 17 fails on Windows only)
  PC_BITFIELD_WCHAR_BITS = 16;

type
  { TPCVerInfoState }
  // What the module's @addverinfo means for its @vi* directives (D-A2-4)
  TPCVerInfoState = (vsOff, vsSilent, vsOn);

  { TPCOrdinalKind }
  // The ordinal family of a type (decls.md sets / arrays / bitfields): every
  // PaskalCPP integer type is one family; okNone = no PaskalCPP ordinal
  TPCOrdinalKind = (okNone, okInteger, okBool, okChar, okWChar, okChoices);

  { TPCCastClass }
  // What an explicit cast can take or give (semantics.md "Expression rules",
  // casts row): the SM0200 hint names a cast only between legal classes
  TPCCastClass = (ccNone, ccInteger, ccFloat, ccOrdinal, ccChoices, ccPointer, ccString);

  { TPCSignatureDiff }
  // The first difference between two signatures (DoSignatureDiff, the one
  // rule, PLAN-RECORDS R5), in the order it is checked; sdSame = one signature
  TPCSignatureDiff = (sdSame, sdLinkage, sdVariadic, sdCount, sdParamMode, sdParamType, sdReturn);

  { TPCCallTarget }
  // One signature a call can bind: a routine (Decl) or a routine type's
  // value (Decl nil); Params and ReturnType are the declaration's own nodes
  TPCCallTarget = record
    Decl: TPCRoutine;
    Params: TList<TPCParam>;
    IsVariadic: Boolean;
    ReturnType: TPCTypeExpr;
  end;

  { TPCFlowKind }
  // One entry kind of the statement context stack (statements.md :89-92): a
  // loop, a match, an except list, a finally list, a guard body (the guard's
  // hidden function)
  TPCFlowKind = (fwLoop, fwMatch, fwExcept, fwFinally, fwGuardBody);

  { TPCFlowKinds }
  TPCFlowKinds = set of TPCFlowKind;

  { TPCFlowEntry }
  // One entry of the context stack: walk state like TPCScopeFrame, never a
  // program fact (what a jump resolves to is written into the AST)
  TPCFlowEntry = record
    FlowKind: TPCFlowKind;
    Owner: TPCStmt;               // the loop, match or guard
  end;

  { TPCMatchSpan }
  // One known match label as a closed interval of 128-bit two's complement
  // pairs (DoConstWide): the overlap and coverage checks compare these
  TPCMatchSpan = record
    LowHigh: Int64;
    LowLow: UInt64;
    HighHigh: Int64;
    HighLow: UInt64;
    LabelNode: TPCMatchLabel;
  end;

  { TPCSemantics }
  TPCSemantics = class(TBaseObject)
  private
    FAst: TPCAst;
    FModule: TPCModule;
    // Every path a directive check tested against the disk (DoCheckPath), in
    // check order, as stored (ResolvedText): what a disk change can flip
    FDiskPaths: TArray<string>;
    FFrames: TList<TPCScopeFrame>;
    // Walk state like FFrames (no program fact): the type declarations whose
    // TypeDef is being analyzed, innermost last. A field or parent of one of
    // them by value is incomplete (C++: the type completes at its end)
    FDefining: TList<TPCTypeDecl>;
    // PLAN-OBJECT O6: owner types whose object type was still only
    // forward-declared when they were walked; judged once its full is known
    // (DoCheckPendingOwners, at each list end). Non-owning
    FPendingOwners: TList<TPCOwnerType>;
    // Statement walk state (A8 STMT, statements.md :89-92), no program fact:
    // the context stack of the routine being checked (each routine starts
    // its own), that routine (nil = the module body or a test body) and the
    // for iterators being looped over (Q13)
    FFlow: TList<TPCFlowEntry>;
    FRoutine: TPCRoutine;
    FIterators: TList<TPCNode>;
    // PLAN-OBJECT O9: the assignment that is the current expression statement
    // (nil = none), and the target an assignment is resolving (a property
    // there is written: DoPropertyRead leaves it to DoPropertyAssign)
    FStmtAssign: TPCAssign;
    FAssignTarget: TPCExpr;
    // O10: the base an index is resolving (an indexed property there is
    // reached through its index: DoPropertyRead leaves it to DoIndexedProperty)
    FIndexBase: TPCExpr;
    // The first @cppdefine / @cppundef seen for each macro name, across the
    // program's modules (SM0118); lives for one Analyze
    FCppMacros: TDictionary<string, TPCDirective>;
    // The varargs type node a variadic routine's local is being declared
    // with (SM0422: every other varargs type node is an error)
    FVarargsLocal: TPCTypeExpr;
    // Depth of the recovered nodes SEM is inside (PLAN-RECOVERY): while > 0
    // nothing is reported; resolution runs as usual (hover, definition)
    FRecoveredDepth: Integer;

    // Reports (C1: DoStopped is the only early stop)
    function DoStopped(): Boolean;
    function DoReportAt(const ANode: TPCNode; const ASeverity: TErrorSeverity; const ACode: string;
      const AMessage: string; const AArgs: array of const): Boolean;
    function DoReportRange(const ARange: TSourceRange; const ASeverity: TErrorSeverity;
      const ACode: string; const AMessage: string; const AArgs: array of const): Boolean;
    function DoEnterRecovered(const ANode: TPCNode): Boolean;
    procedure DoLeaveRecovered();
    function DoError(const ANode: TPCNode; const ACode: string; const AMessage: string;
      const AArgs: array of const): Boolean;
    function DoWarning(const ANode: TPCNode; const ACode: string; const AMessage: string;
      const AArgs: array of const): Boolean;
    procedure DoNote(const ANode: TPCNode; const AMessage: string; const AArgs: array of const);
    procedure DoPoison(const AExpr: TPCExpr);
    function DoIsPoisoned(const AExpr: TPCExpr): Boolean;

    // Frames (the scope rule itself: PaskalCPP.Scopes, TPCScopes)
    procedure DoPushFrame(const AFrame: TPCScopeFrame);
    procedure DoPopFrame();
    function DoTopIndex(): Integer;
    procedure DoLookup(const AName: string; const AFound: TList<TPCNode>); overload;
    procedure DoLookup(const AName: string; const AFound: TList<TPCNode>;
      out AFrameKind: TPCFrameKind); overload;
    // PLAN-OBJECT D9: a member of the method's object named bare: SM0018 at
    // AAt ("write self.X"); the caller poisons
    procedure DoBareMember(const AAt: TPCNode; const AName: string);
    // PLAN-OBJECT D10 (TPCScopes.HiddenReach, C++'s protected rule): AMember,
    // found in ASearched (canonical; spelled ASearchedText), cannot be named
    // from here; AReport = SM0019 at AAt. AThroughParent = a parent.<member>
    // access: it reaches through self
    function DoHiddenBlocks(const AAt: TPCNode; const AMember: TPCNode; const AName: string;
      const ASearched: TPCTypeExpr; const ASearchedText: string; const AThroughParent: Boolean;
      const AReport: Boolean): Boolean;
    // The spelling of ALevel on AStart's parent chain (AStart spelled AStartText)
    function DoLevelText(const AStart: TPCTypeExpr; const AStartText: string;
      const ALevel: TPCTypeExpr): string;
    function DoResolvedKindOf(const ADecl: TPCNode): TPCResolvedKind;
    function DoOwnItem(const AName: string): TPCStmt;
    function DoUsedLater(const AName: string): TPCNode;
    function DoIntrinsicOf(const AName: string): TPCIntrinsicKind;
    function DoMethodOwner(out ATypeDecl: TPCTypeDecl): TPCRecordType;
    function DoInMethodOf(const ADecl: TPCTypeDecl): Boolean;
    function DoOwnValue(const AName: string): TPCChoiceValue;
    function DoResolveOwnType(const ADecl: TPCTypeDecl; const AAt: TPCNode): TPCTypeDecl;
    function DoModuleMember(const AModule: TPCModule; const AName: string;
      const AFound: TList<TPCNode>): Boolean;
    function DoChoiceMember(const AChoices: TPCChoicesType; const AName: string): TPCChoiceValue;
    function DoAllRoutines(const AFound: TList<TPCNode>): Boolean;
    function DoListChoice(const AList: TList<TPCStmt>; const ACount: Integer; const AName: string;
      const AModuleName: string; const AExportedOnly: Boolean; out ASpelling: string): Boolean;
    function DoChoiceSpelling(const AName: string; out ASpelling: string): Boolean;
    // The import step of a bare name the frames, the intrinsics and the
    // used-before scan left alone (PLAN-IMPORT-RESOLUTION): the module's own
    // imports, through the one rule TPCScopes.FindImported. False = no
    // imported unit exports AName. True with AFound filled = one unit's
    // declarations (an overload set stays that unit's set); True with AFound
    // empty = two or more units export it: SM0020 at ARange when AReport, a
    // note at each candidate's declaration
    function DoImportedName(const ARange: TSourceRange; const AReport: Boolean; const AName: string;
      const AFound: TList<TPCNode>): Boolean;
    // What a lookup found, bound on a bare value name: one declaration, or a
    // routine set (any member spells it for the emitter); anything else
    // poisons it (a repeat was SM0004; an ambiguous import was SM0020)
    procedure DoBindFound(const AName: TPCName; const AFound: TList<TPCNode>);
    // The same in a type position: one type declaration, else SM0013 (an
    // empty AFound was reported already)
    procedure DoBindFoundType(const AType: TPCNamedType; const ALookupName: string;
      const AFound: TList<TPCNode>);

    // Duplicates (SM0004)
    procedure DoReportDuplicate(const ALater: TPCNode; const AFirst: TPCNode; const AName: string);
    procedure DoCheckDuplicate(const ADecl: TPCDecl);
    procedure DoCheckReservedNames(const AModule: TPCModule);
    procedure DoCheckParamDuplicates(const AParams: TList<TPCParam>);
    procedure DoCheckMemberDuplicates(const ATypeMembers: TList<TPCMemberItem>;
      const AItems: TList<TPCMemberItem>);

    // Module prologue, body directives, test names (A2 MODULE, sem\module.md)
    procedure DoMarkNoEffect(const ADirective: TPCDirective; const ASeverity: TErrorSeverity;
      const ACode: string; const AMessage: string; const AArgs: array of const);
    function DoNotApplied(const AModule: TPCModule; const ADirective: TPCDirective;
      out AWhere: string): Boolean;
    function DoVerInfoOf(const AModule: TPCModule): TPCVerInfoState;
    function DoCheckChoice(const ADirective: TPCDirective): Boolean;
    procedure DoCheckVersionInfo(const ADirective: TPCDirective; const AState: TPCVerInfoState);
    procedure DoCheckPath(const AArg: TPCDirectiveArg; const ADirectory: Boolean);
    // APath into FDiskPaths, once
    procedure DoAddDiskPath(const APath: string);
    procedure DoCheckSourceFile(const AArg: TPCDirectiveArg);
    class function DoIsMacroName(const AText: string): Boolean; static;
    class function DoMacroText(const ADirective: TPCDirective): string; static;
    class function DoSameMacro(const AFirst: TPCDirective; const ASecond: TPCDirective): Boolean; static;
    procedure DoCheckCppMacro(const ADirective: TPCDirective);
    procedure DoReportMessage(const ADirective: TPCDirective);
    procedure DoCheckDirective(const AModule: TPCModule; const ADirective: TPCDirective;
      const AVerInfo: TPCVerInfoState);
    function DoCheckFixedRule(const AModule: TPCModule; const ADirective: TPCDirective): Boolean;
    function DoCheckValue(const ADirective: TPCDirective): Boolean;
    function DoReportNotApplied(const AModule: TPCModule; const ADirective: TPCDirective): Boolean;
    procedure DoCheckUse(const ADirective: TPCDirective; const AVerInfo: TPCVerInfoState);

    // Literal and value leaf types (A3a TYPES-A, sem\types.md, datamodel.md, folding.md)
    function DoModelTarget(): TPCTargetTriple;
    function DoNamedTypeOf(const ADecl: TPCTypeDecl): TPCNamedType;
    function DoValueTypeOf(const AType: TPCTypeExpr): TPCTypeExpr;
    function DoIntLiteralToken(const ALiteral: TPCLiteral): TPCTokenKind;
    procedure DoIntLiteral(const ALiteral: TPCLiteral);
    procedure DoFloatLiteral(const ALiteral: TPCLiteral);
    procedure DoCharLiteral(const ALiteral: TPCLiteral);
    procedure DoStringLiteral(const ALiteral: TPCLiteral);
    procedure DoLiteral(const ALiteral: TPCLiteral);
    procedure DoTypeLeaf(const AExpr: TPCExpr; const ADecl: TPCNode; const AKind: TPCResolvedKind);
    function DoChoicesNamedType(const AChoices: TPCChoicesType): TPCTypeExpr;

    // Type classes, equality, implicit conversion, constants, const / choice
    // leaf values (A3b TYPES-A, sem\types.md, folding.md, semantics.md :99-132)
    function DoIsOpaqueTier(const AType: TPCTypeExpr): Boolean;
    function DoIsErrorType(const AType: TPCTypeExpr): Boolean;
    function DoHoldsErrorPart(const AType: TPCTypeExpr): Boolean;
    function DoNamesRecoveredDecl(const AType: TPCTypeExpr): Boolean;
    function DoBuiltinOf(const AType: TPCTypeExpr; out AToken: TPCTokenKind): Boolean;
    function DoIntTypeInfo(const AToken: TPCTokenKind; out ABits: Integer; out AIsUnsigned: Boolean): Boolean;
    function DoSetOf(const AType: TPCTypeExpr; out ARange: TPCSetType; out AElement: TPCTypeExpr): Boolean;
    function DoSameConst(const AFirst: TPCExpr; const ASecond: TPCExpr): Boolean;
    function DoSameBound(const AFirst: TPCExpr; const ASecond: TPCExpr; const AOpaqueBySpelling: Boolean): Boolean;
    function DoSameTypeAs(const AFirst: TPCTypeExpr; const ASecond: TPCTypeExpr;
      const AOpaqueBySpelling: Boolean): Boolean;
    function DoSameType(const AFirst: TPCTypeExpr; const ASecond: TPCTypeExpr): Boolean;
    function DoSameSignatureType(const AFirst: TPCTypeExpr; const ASecond: TPCTypeExpr): Boolean;
    function DoSignatureDiff(const AFirst: TPCSignature; const ASecond: TPCSignature;
      const AOpaqueBySpelling: Boolean; out AParam: Integer): TPCSignatureDiff;
    function DoSameSignature(const AFirst: TPCSignature; const ASecond: TPCSignature;
      const AOpaqueBySpelling: Boolean): Boolean;
    function DoFitsMantissa(const AMagnitude: UInt64; const ABits: Integer): Boolean;
    function DoConstFits(const AValue: TPCExpr; const AToken: TPCTokenKind): Boolean;
    function DoFloatFitsSingle(const AValue: Double): Boolean;
    function DoUIntToDouble(const AValue: UInt64): Double;
    function DoConvertsImplicitly(const AValue: TPCExpr; const ATo: TPCTypeExpr): Boolean;
    function DoIsRoutineValue(const AValue: TPCExpr): Boolean;
    procedure DoRoutinesOfValue(const AValue: TPCExpr; const ARoutines: TList<TPCRoutine>);
    function DoRoutineValueFit(const AValue: TPCExpr; const ATo: TPCTypeExpr; out AFit: TPCRoutine): Boolean;
    procedure DoBindRoutineValue(const AValue: TPCExpr; const ATo: TPCTypeExpr);
    procedure DoNoteRoutineValue(const AValue: TPCExpr; const ATo: TPCTypeExpr);
    function DoCastClass(const AType: TPCTypeExpr; out ABits: Integer): TPCCastClass;
    function DoIsPrimary(const AExpr: TPCExpr): Boolean;
    function DoCastHint(const AValue: TPCExpr; const ATo: TPCTypeExpr; out AHint: string): Boolean;
    function DoPointerCastTakes(const AFromType: TPCTypeExpr; const ATo: TPCTypeExpr): Boolean;
    function DoConstNotFit(const AValue: TPCExpr; const ATo: TPCTypeExpr; out AValueText: string;
      out ALowText: string; out AHighText: string): Boolean;
    procedure DoCheckConvert(const AValue: TPCExpr; const ATo: TPCTypeExpr);
    function DoCheckConstant(const AExpr: TPCExpr; const APosition: string): Boolean;
    procedure DoConstLeaf(const AExpr: TPCExpr; const ADecl: TPCConstDecl);
    procedure DoChoiceLeaf(const AExpr: TPCExpr; const AValue: TPCChoiceValue);

    // TYPES-B: expressions (semantics.md "Expression rules", folding.md "Operators")
    function DoTokenOf(const AExpr: TPCExpr; out AToken: TPCTokenKind): Boolean;
    function DoIsIntegerToken(const AToken: TPCTokenKind): Boolean;
    function DoStringWidth(const AExpr: TPCExpr): Integer;
    function DoNotValue(const AExpr: TPCExpr): Boolean;
    function DoOperandsReady(const ANode: TPCExpr; const AOperands: array of TPCExpr): Boolean;
    procedure DoReportOperands(const ANode: TPCExpr; const AOpText: string; const ALeft: TPCExpr;
      const ARight: TPCExpr);
    function DoIsUncomparable(const AType: TPCTypeExpr): Boolean;
    function DoCheckComparable(const ANode: TPCExpr; const AOpText: string; const ALeft: TPCExpr;
      const ARight: TPCExpr): Boolean;
    function DoBinaryType(const ANode: TPCExpr; const AOp: TPCBinaryOp; const ALeft: TPCExpr;
      const ARight: TPCExpr): TPCTypeExpr;
    function DoInType(const ANode: TPCExpr; const ALeft: TPCExpr; const ARight: TPCExpr): TPCTypeExpr;
    function DoValueSigned(const AExpr: TPCExpr): Int64;
    // F27 constant folding (research\paskal-errors\r-a-folding.md D1-D6)
    function DoFoldInfo(const AToken: TPCTokenKind; out ABits: Integer; out AIsUnsigned: Boolean): Boolean;
    function DoFoldOperand(const AExpr: TPCExpr; out AToken: TPCTokenKind): Boolean;
    function DoPromotedToken(const AToken: TPCTokenKind): TPCTokenKind;
    function DoCommonToken(const ALeft: TPCTokenKind; const ARight: TPCTokenKind): TPCTokenKind;
    // PLAN-ARITH A1: the type C++ gives a numeric operator's result (one rule
    // for typing and folding)
    function DoIsNumericToken(const AToken: TPCTokenKind): Boolean;
    function DoNumericResult(const AOp: TPCBinaryOp; const ALeftToken: TPCTokenKind; const ARightToken: TPCTokenKind;
      out AResult: TPCTokenKind): Boolean;
    function DoUnaryResult(const AOp: TPCUnaryOp; const AToken: TPCTokenKind; out AResult: TPCTokenKind): Boolean;
    // PLAN-ARITH A2: no hidden conversion of an operand (binary operators)
    // or of a compound assignment's value
    function DoArithResult(const ANode: TPCExpr; const AOp: TPCBinaryOp; const ALeft: TPCExpr;
      const ARight: TPCExpr; const AResult: TPCTokenKind): TPCTypeExpr;
    function DoCheckNumericCompound(const AAssign: TPCAssign; const ATarget: TPCExpr;
      const AValue: TPCExpr): Boolean;
    function DoConstPattern(const AExpr: TPCExpr): UInt64;
    function DoMinOf(const ABits: Integer): Int64;
    procedure DoStoreFolded(const AExpr: TPCExpr; const AToken: TPCTokenKind; const APattern: UInt64;
      const ASetType: Boolean);
    function DoFoldSignedness(const ANode: TPCExpr; const AOpText: string; const AOperand: TPCExpr;
      const APromoted: TPCTokenKind; const ACommon: TPCTokenKind): Boolean;
    function DoSignedFold(const AOp: TPCBinaryOp; const ALeft: Int64; const ARight: Int64; const ABits: Integer;
      out AResult: Int64): Boolean;
    procedure DoFoldArith(const ABinary: TPCBinary; const ALeftToken: TPCTokenKind; const ARightToken: TPCTokenKind);
    procedure DoFoldShift(const ABinary: TPCBinary; const ALeftToken: TPCTokenKind; const ARightToken: TPCTokenKind);
    procedure DoFoldBinary(const ABinary: TPCBinary);
    function DoFoldUnary(const AUnary: TPCUnary; const AOperand: TPCExpr): Boolean;
    procedure DoFoldConversion(const AExpr: TPCExpr; const AOperand: TPCExpr; const ATarget: TPCTypeExpr);
    procedure DoFoldTernary(const ATernary: TPCTernary);
    procedure DoBinary(const ABinary: TPCBinary);
    function DoIsAssignable(const AExpr: TPCExpr): Boolean;
    function DoIsAddressable(const AExpr: TPCExpr; out AIsConst: Boolean): Boolean;
    procedure DoUnary(const AUnary: TPCUnary);
    procedure DoAssign(const AAssign: TPCAssign);
    function DoCheckSetAssign(const AAssign: TPCAssign): Boolean;
    function DoCheckCondition(const AExpr: TPCExpr): Boolean;
    procedure DoTernary(const ATernary: TPCTernary);
    function DoCheckIndex(const AIndex: TPCIndex; const ABase: TPCExpr; const AIndexExpr: TPCExpr): Boolean;
    function DoIndexInRange(const AIndex: TPCIndex; const ABase: TPCExpr; const AIndexExpr: TPCExpr): Boolean;
    procedure DoIndex(const AIndex: TPCIndex);
    function DoConvertsFrom(const AFrom: TPCTypeExpr; const AValue: TPCExpr; const ATo: TPCTypeExpr): Boolean;
    function DoOwnerConverts(const AFrom: TPCOwnerType; const ATo: TPCOwnerType): Boolean;
    function DoIsOrdinalType(const AType: TPCTypeExpr): Boolean;
    function DoSetLiteralFits(const ALiteral: TPCSetLiteral; const ASetType: TPCTypeExpr): Boolean;
    procedure DoCast(const ACast: TPCCast);
    procedure DoSetLiteral(const ALiteral: TPCSetLiteral);
    procedure DoValueMember(const AMember: TPCMember);

    // DECLS: declarations (research\cppmix\sem\decls.md "Rules per node")
    procedure DoCheckComplete(const AType: TPCTypeExpr; const AIsMember: Boolean);
    procedure DoCheckVarDecl(const ADecl: TPCVarDecl);
    procedure DoForwardType(const ADecl: TPCTypeDecl);
    procedure DoFullType(const ADecl: TPCTypeDecl);
    procedure DoUnpairedForwards(const AList: TList<TPCStmt>);
    // DECLS A5c: routines (decls.md TPCRoutine / External lib, calls.md R-DECL)
    function DoSameParamTypes(const AFirst: TPCRoutine; const ASecond: TPCRoutine): Boolean;
    function DoParamFact(const AForward: TPCRoutine; const AFull: TPCRoutine; out AFact: string): Boolean;
    function DoRoutineFact(const AForward: TPCRoutine; const AFull: TPCRoutine; out AFact: string): Boolean;
    procedure DoPairRoutine(const AFull: TPCRoutine);
    function DoWrittenClink(const AMember: TPCRoutine): Boolean;
    procedure DoSetLinkage(const AMember: TPCRoutine; const ALinkage: TPCLinkage);
    procedure DoCollectMembers(const AList: TList<TPCStmt>; const AName: string;
      const AMembers: TList<TPCRoutine>);
    function DoNearestFull(const AList: TList<TPCStmt>; const AForward: TPCRoutine): TPCRoutine;
    function DoJudgedOverload(const AMember: TPCRoutine): Boolean;
    function DoCheckDistinctParams(const AMembers: TList<TPCRoutine>): Boolean;
    procedure DoCheckOverloadLinkage(const AMembers: TList<TPCRoutine>);
    procedure DoCheckVariadicSet(const AMembers: TList<TPCRoutine>);
    procedure DoCheckVariadicFixed(const AMembers: TList<TPCRoutine>);
    procedure DoCheckOverloads(const AList: TList<TPCStmt>; const AMembers: TList<TPCRoutine>);
    procedure DoRoutineSets(const AList: TList<TPCStmt>);
    class function DoAnyRecovered(const ARoutines: TList<TPCRoutine>): Boolean; static;
    procedure DoResolveExternalLib(const ADecl: TPCDecl; var AExternal: TPCExternal);
    // DECLS A5b: layout, parents, overlays, bitfields, sets, arrays
    function DoOrdinalKindOf(const AType: TPCTypeExpr): TPCOrdinalKind;
    function DoSameOrdinalFamily(const AFirst: TPCTypeExpr; const ASecond: TPCTypeExpr): Boolean;
    function DoFoldedInteger(const AExpr: TPCExpr): Boolean;
    procedure DoConstWide(const AExpr: TPCExpr; out AHigh: Int64; out ALow: UInt64);
    function DoConstText(const AExpr: TPCExpr): string;
    function DoBoundsReversed(const ALowExpr: TPCExpr; const AHighExpr: TPCExpr): Boolean;
    function DoCountTooLarge(const ALowExpr: TPCExpr; const AHighExpr: TPCExpr): Boolean;
    function DoMemberCount(const ALowExpr: TPCExpr; const AHighExpr: TPCExpr; out AText: string): Boolean;
    procedure DoCheckAlign(const ARecord: TPCRecordType);
    function DoFoldedAlign(const AExpr: TPCExpr; out AValue: UInt64): Boolean;
    class function DoIsAlignValue(const AValue: UInt64): Boolean; static;
    function DoAlignOfKind(const AKind: TPCAlignKind): UInt64;
    function DoBuiltinAlign(const AToken: TPCTokenKind): UInt64;
    function DoTypeAlign(const AType: TPCTypeExpr; const AVisited: TList<TPCTypeExpr>): UInt64;
    function DoMembersAlign(const AMembers: TList<TPCMemberItem>; const AVisited: TList<TPCTypeExpr>): UInt64;
    function DoNaturalAlign(const ARecord: TPCRecordType; const AVisited: TList<TPCTypeExpr>): UInt64;
    procedure DoCheckNaturalAlign(const ARecord: TPCRecordType);
    function DoDefiningName(const AType: TPCTypeExpr): string;
    procedure DoCheckPackedFields(const AMembers: TList<TPCMemberItem>; const AInPacked: Boolean;
      const AName: string);
    procedure DoCheckPackedRecord(const ARecord: TPCRecordType);
    procedure DoCheckOverlayFields(const AMembers: TList<TPCMemberItem>; const AInOverlay: Boolean;
      const AName: string);
    procedure DoCheckBitfield(const AField: TPCField);
    procedure DoCheckBitfieldStore(const AValue: TPCExpr; const AField: TPCField);
    procedure DoCheckParent(const ARecord: TPCRecordType);
    procedure DoResolveDispatch(const ARecord: TPCRecordType);
    procedure DoCheckDispatch(const ARecord: TPCRecordType);
    procedure DoCheckDispatchMethod(const ARecord: TPCRecordType; const AItem: TPCMethodItem);
    procedure DoCheckInterfaceRepeats(const AFace: TPCRecordType; const AParent: TPCTypeExpr);
    procedure DoCheckImplements(const ARecord: TPCRecordType);
    procedure DoCheckImplementsFace(const ARecord: TPCRecordType; const AName: TPCNamedType;
      const AFace: TPCRecordType);
    // PLAN-OBJECT O8 (D2): embeds. DoPromote = a member access's embed lookup
    // (False = reported / poisoned: stop); DoImplementsByEmbed = an interface
    // method an embed provides (False = none does: the caller reports)
    function DoPromote(const AMember: TPCMember; const ARecord: TPCTypeExpr; const ASearchedText: string;
      const AFound: TList<TPCNode>; out AEmbedType: TPCTypeExpr; out AEmbedText: string;
      out AHops: Integer): Boolean;
    function DoImplementsByEmbed(const ARecord: TPCRecordType; const AName: TPCNamedType;
      const AWant: TPCRoutine; const AOwner: string): Boolean;
    procedure DoCheckEmbed(const AField: TPCField);
    class function DoEmbedPathText(const APath: TArray<TPCField>): string; static;
    function DoParentMethod(const ARecord: TPCRecordType; const AName: string): TPCMethodItem;
    // PLAN-OBJECT O10: a property's dispatch (as a method's)
    function DoParentProperty(const ARecord: TPCRecordType; const AName: string): TPCPropertyItem;
    function DoRunningWrite(const ASearched: TPCTypeExpr; const AProperty: TPCPropertyItem): TPCAccessorItem;
    function DoAbstractAccessor(const ARecord: TPCRecordType; const AProperty: TPCPropertyItem): TPCAccessorItem;
    function DoPropertyOwnerName(const AFrom: TPCTypeExpr; const AProperty: TPCPropertyItem): string;
    function DoSamePropertyShape(const AFirst: TPCPropertyItem; const ASecond: TPCPropertyItem): Boolean;
    procedure DoCheckDispatchProperty(const ARecord: TPCRecordType; const AProperty: TPCPropertyItem);
    function DoMethodOwnerName(const AFrom: TPCTypeExpr; const AFromText: string;
      const AItem: TPCRoutineMember): string;
    function DoSignatureReported(const ARoutine: TPCRoutine): Boolean;
    procedure DoCheckConcrete(const AType: TPCTypeExpr; const AAt: TPCNode);
    function DoParentAbstract(const AMember: TPCMember; const ARecord: TPCTypeExpr;
      const AFound: TPCNode; const ASearchedText: string): Boolean;
    function DoIsConstObject(const AMember: TPCMember): Boolean;
    function DoInReadAccessor(): Boolean;
    // O13b (3): self is const here (a read accessor or a const method), and
    // the one report for a change of it / a call through it there
    function DoInConstSelf(): Boolean;
    procedure DoConstSelfChange(const ANode: TPCNode; const ATargetText: string);
    procedure DoConstSelfCall(const ANode: TPCNode; const AMethodText: string);
    class function DoIsConstMethodDecl(const ADecl: TPCNode): Boolean; static;
    function DoConstNotKept(const AHave: TPCRoutine; const AWant: TPCRoutine; const AWantOwner: string): Boolean;
    function DoInOwnAccessor(const AAccessor: TPCAccessorItem): Boolean;
    class function DoRootsAtSelf(const AExpr: TPCExpr): Boolean; static;
    function DoIsBoundPropertyRead(const AExpr: TPCExpr): Boolean;
    class function DoIsPropertyAccess(const AExpr: TPCExpr): Boolean; static;
    function DoIsConstBase(const ABase: TPCExpr; const AAccess: TPCMemberAccess): Boolean;
    procedure DoPropertyRead(const AMember: TPCMember; const AProperty: TPCPropertyItem; const AHops: Integer);
    procedure DoPropertyAssign(const AAssign: TPCAssign; const AProperty: TPCPropertyItem;
      const ATarget: TPCExpr; const ABase: TPCExpr; const AAccess: TPCMemberAccess; const AAt: TPCNode;
      const AEmbedded: Boolean);
    function DoIndexedProperty(const AIndex: TPCIndex): Boolean;
    function DoDefaultProperty(const ARecord: TPCRecordType): TPCPropertyItem;
    procedure DoCheckImplementsProperty(const ARecord: TPCRecordType; const AName: TPCNamedType;
      const AFace: TPCRecordType; const AWant: TPCPropertyItem);
    // PLAN-OBJECT D3: init / done
    function DoOwnInits(const ARecord: TPCRecordType): TList<TPCInitItem>;
    function DoNeedsInitArgs(const ARecord: TPCRecordType): Boolean;
    function DoInitWithoutArgs(const ARecord: TPCRecordType): TPCInitItem;
    function DoIsLeadInitStmt(const ARecord: TPCRecordType; const AStmt: TPCStmt; out ACall: TPCCall;
      out AField: TPCField): Boolean;
    procedure DoMarkLeadInits(const ARecord: TPCRecordType; const AItem: TPCInitItem);
    procedure DoCheckLeadArgs(const ACall: TPCCall);
    procedure DoLeadInitCall(const ACall: TPCCall);
    function DoBuildWith(const ACall: TPCCall; const ARecord: TPCRecordType; const ATypeText: string): Boolean;
    procedure DoConstruct(const ADecl: TPCVarDecl);
    procedure DoCheckDefaultBuild(const AType: TPCTypeExpr; const AAt: TPCNode);
    function DoLeadsWith(const ARecord: TPCRecordType; const AItem: TPCInitItem; const AField: TPCField): Boolean;
    procedure DoCheckLifecycle(const ARecord: TPCRecordType);
    // PLAN-OBJECT O11 (D13)
    procedure DoCheckOperators(const ARecord: TPCRecordType);
    procedure DoCollectOperators(const AType: TPCTypeExpr; const AOp: TPCBinaryOp; const AUnary: Boolean;
      const AFound: TList<TPCOperatorItem>);
    function DoDeclaredOperator(const ANode: TPCExpr; const AOp: TPCBinaryOp; const AUnary: Boolean;
      const AOperands: array of TPCExpr; out AOperator: TPCOperatorItem): Boolean;
    function DoArgsTake(const AArgs: TList<TPCExpr>; const AParams: TList<TPCParam>;
      const AIsVariadic: Boolean): Boolean;
    function DoExactOperands(const AArgs: TList<TPCExpr>; const AItem: TPCOperatorItem): Boolean;
    function DoOperatorTypesText(const AItem: TPCOperatorItem): string;
    function DoOperandTypesText(const AArgs: TList<TPCExpr>): string;
    procedure DoNoteOperators(const AItems: TList<TPCOperatorItem>);
    // PLAN-OBJECT O5 (D5 / D6 / H3)
    function DoCheckCopyMember(const ARecord: TPCRecordType; const AName: string): TPCCopyItem;
    function DoHoldsObject(const AType: TPCTypeExpr; out AObject: TPCTypeExpr): Boolean;
    // PLAN-OBJECT O6 (D4)
    procedure DoCheckOwnerTarget(const AOwner: TPCOwnerType);
    function DoPendingForward(const AType: TPCTypeExpr): TPCTypeDecl;
    procedure DoCheckPendingOwners();
    function DoHoldsOwner(const AType: TPCTypeExpr; out AOwner: TPCTypeExpr): Boolean;
    function DoCheckCopy(const AValue: TPCExpr; const ATo: TPCTypeExpr): Boolean;
    procedure DoNoteMoveOnly(const AType: TPCTypeExpr);
    function DoCheckSlice(const AValue: TPCExpr; const ATo: TPCTypeExpr): Boolean;
    function DoCheckSliceCopy(const AValue: TPCExpr; const ATo: TPCTypeExpr): Boolean;
    function DoMayHoldDescendant(const ATarget: TPCExpr): Boolean;
    function DoMayBeDescendant(const AValue: TPCExpr): Boolean;
    function DoCheckSliceAssign(const ATarget: TPCExpr): Boolean;
    // PLAN-OBJECT O13b: polymorphism only clang knows (a C/C++ base)
    procedure DoNotePoly(const AExpr: TPCExpr; const AKind: TPCPolyCheck; const AType: TPCTypeExpr;
      const AText: string);
    procedure DoNoteCppPoly(const AValue: TPCExpr; const ATo: TPCTypeExpr);
    procedure DoMarkMove(const AValue: TPCExpr);
    procedure DoCheckParentNames(const AMembers: TList<TPCMemberItem>; const AParent: TPCTypeExpr);
    procedure DoCheckSetType(const ASet: TPCSetType);
    procedure DoResolveElementBounds(const ASet: TPCSetType; const AType: TPCTypeExpr;
      const AKind: TPCOrdinalKind);
    procedure DoResolveRangeBounds(const ASet: TPCSetType; const ALow: TPCExpr; const AHigh: TPCExpr);
    class function DoWideFitsInt64(const AHigh: Int64; const ALow: UInt64): Boolean; static;
    procedure DoCheckArrayBounds(const AArray: TPCArrayType);
    procedure DoChoiceOrdinal(const AValue: TPCChoiceValue; var ANext: Int64; var AKnown: Boolean;
      var APastMax: Boolean);

    // The walk
    procedure DoAnalyzeModule(const AModule: TPCModule);
    procedure DoModuleDirectives(const AModule: TPCModule);
    procedure DoCheckTestName(const AModule: TPCModule; const AIndex: Integer);
    procedure DoBodyDirective(const ADirective: TPCDirective);
    procedure DoItemList(const AList: TList<TPCStmt>; const AFirst: Boolean);
    procedure DoNestedList(const AOwner: TPCStmt; const AList: TList<TPCStmt>);
    procedure DoStmt(const AStmt: TPCStmt);
    procedure DoRoutine(const ARoutine: TPCRoutine);
    procedure DoBlock(const ABlock: TPCBlock);
    procedure DoTest(const ATest: TPCTest);
    procedure DoTypeDecl(const ADecl: TPCTypeDecl);
    procedure DoTypeExpr(const AType: TPCTypeExpr);
    procedure DoMemberItem(const AOwner: TPCTypeExpr; const AItem: TPCMemberItem);
    procedure DoProperty(const AOwner: TPCTypeExpr; const AProperty: TPCPropertyItem);
    procedure DoCheckPropertyBindings(const ARecord: TPCRecordType);
    procedure DoChoicesType(const AChoices: TPCChoicesType);
    procedure DoExpr(const AExpr: TPCExpr);
    procedure DoNodeChildren(const ANode: TPCNode);
    procedure DoResolveName(const AName: TPCName);
    procedure DoResolveNamedType(const AType: TPCNamedType);
    procedure DoResolveQualifiedType(const AType: TPCNamedType);
    procedure DoResolveMember(const AMember: TPCMember);
    procedure DoSpecial(const ASpecial: TPCSpecial; const AIsMemberBase: Boolean);
    procedure DoCallMirror(const ACall: TPCCall);
    // CALLS A6a: callee kinds, arity, R-RANK (C++'s pick), legality on the
    // winner, Q9 type casts (research\cppmix\sem\calls.md)
    function DoInTest(): Boolean;
    function DoRoutineTarget(const ARoutine: TPCRoutine): TPCCallTarget;
    function DoTypeTarget(const AType: TPCRoutineType): TPCCallTarget;
    procedure DoCallCandidates(const ACall: TPCCall; const ATargets: TList<TPCCallTarget>);
    procedure DoCalleeDecls(const ACallee: TPCExpr; const AFound: TList<TPCNode>);
    function DoCalleeText(const ACall: TPCCall): string;
    function DoArgsReady(const ACall: TPCCall): Boolean;
    procedure DoCheckArgs(const ACall: TPCCall; const ATarget: TPCCallTarget);
    procedure DoBindTarget(const ACall: TPCCall; const ATarget: TPCCallTarget);
    procedure DoPickTarget(const ACall: TPCCall; const ATargets: TList<TPCCallTarget>);
    function DoTargetTakes(const ACall: TPCCall; const ATarget: TPCCallTarget): Boolean;
    // PLAN-RECORDS A4: the upcast (R4) and the marks the emitter reads (M10 / M12 / M13)
    function DoVarTakes(const AArg: TPCExpr; const ATo: TPCTypeExpr): Boolean;
    function DoConstTakes(const AArg: TPCExpr; const ATo: TPCTypeExpr): Boolean;
    function DoUpcastHops(const AFrom: TPCTypeExpr; const ATo: TPCTypeExpr): Integer;
    procedure DoNoteUpcast(const AValue: TPCExpr; const ATo: TPCTypeExpr);
    procedure DoNoteComparedUpcast(const ALeft: TPCExpr; const ARight: TPCExpr);
    function DoTernaryBaseType(const ATernary: TPCTernary): TPCTypeExpr;
    function DoIsNilAndPointer(const ANil: TPCTypeExpr; const APointer: TPCTypeExpr): Boolean;
    function DoUpcastSideType(const AExtension: TPCTypeExpr; const ABase: TPCTypeExpr): TPCTypeExpr;
    function DoTakesAtBase(const ACall: TPCCall; const ATargets: TList<TPCCallTarget>): Boolean;
    // PLAN-RECORDS A8: "may be misaligned" (M8, F-R4f) and the sites that ask it
    function DoMayBeMisaligned(const AValue: TPCExpr): Boolean;
    function DoPartMisaligned(const ARecord: TPCTypeExpr; const AHops: Integer): Boolean;
    function DoPointerUpcastMisaligned(const AFrom: TPCTypeExpr; const AHops: Integer): Boolean;
    procedure DoReportPointerUpcast(const AValue: TPCExpr; const ATo: TPCTypeExpr);
    function DoCppRefParam(const AType: TPCTypeExpr; out AIsConst: Boolean): Boolean;
    procedure DoNoteMisalignedArgs(const ACall: TPCCall; const ATargets: TList<TPCCallTarget>);
    procedure DoNoteMisalignedArg(const ACall: TPCCall; const AArg: TPCExpr; const AIndex: Integer;
      const ATargets: TList<TPCCallTarget>);
    procedure DoNoteMisalignedPrint(const ACall: TPCCall);
    procedure DoNoteMisalignedOperand(const AValue: TPCExpr);
    function DoArgTypesText(const ACall: TPCCall): string;
    function DoParamTypesText(const ATarget: TPCCallTarget): string;
    function DoParamText(const AParam: TPCParam): string;
    procedure DoPickOverload(const ACall: TPCCall; const ATargets: TList<TPCCallTarget>);
    procedure DoOverloadSetType(const ACall: TPCCall; const ATargets: TList<TPCCallTarget>);
    procedure DoTypeCall(const ACall: TPCCall);
    // CALLS A6b: intrinsics, size(T), type arguments (calls.md, semantics.md :194-209)
    function DoIntrinsicValueType(const AValue: TPCIntrinsicValue): TPCTypeExpr;
    function DoIntrinsicArgFits(const AArg: TPCExpr; const AClass: TPCIntrinsicArg): Boolean;
    procedure DoReportIntrinsicSig(const ACall: TPCCall; const AAt: TPCNode);
    procedure DoSizeCall(const ACall: TPCCall);
    procedure DoIntrinsic(const ACall: TPCCall);
    function DoIsVarargsReceiver(const ACall: TPCCall): Boolean;
    procedure DoTypeArgCall(const ACall: TPCCall);
    // CALLS A6c: record literals (calls.md :224-225)
    function DoFieldIndex(const ARecord: TPCRecordType; const AName: string; out AField: TPCField): Integer;
    function DoFieldCount(const ARecord: TPCRecordType): Integer;
    function DoIsLiteralRecord(const AType: TPCTypeExpr): Boolean;
    function DoChainFieldIndex(const ARecord: TPCRecordType; const AName: string; out AField: TPCField;
      out AHops: Integer): Integer;
    procedure DoRecordLiteral(const ALiteral: TPCRecordLiteral);
    // CALLS A6d: varargs (BNF.md sec 6, Q30, research\cppmix\sem\varargs.md)
    function DoIsVarargsCopy(const AExpr: TPCExpr): Boolean;
    procedure DoVarargsExpr(const AVarargs: TPCVarargs);
    procedure DoOwnerNew(const ANew: TPCOwnerNew);
    // PLAN-OBJECT O12 (D15): is / as
    procedure DoTypeTest(const ATest: TPCTypeTest);
    function DoTypeTestObject(const ATest: TPCTypeTest; out AObject: TPCRecordType; out AObjectType: TPCTypeExpr;
      out AForm: TPCTypeExpr; out AConstTarget: Boolean): Boolean;
    function DoTypeTestTarget(const ATest: TPCTypeTest; out ATarget: TPCRecordType): Boolean;
    class function DoMayBeBoth(const AFrom: TPCRecordType; const ATo: TPCRecordType): Boolean; static;
    function DoTypeTestResult(const ATest: TPCTypeTest; const AForm: TPCTypeExpr; const AConstTarget: Boolean): TPCTypeExpr;
    class function DoIsObjectCast(const AExpr: TPCExpr): Boolean; static;
    function DoReadType(const ACall: TPCCall; const ASlot: Integer; out AType: TPCTypeExpr): Boolean;
    procedure DoVarargsLocalCall(const ACall: TPCCall);
    procedure DoVarDeclStmt(const ADecl: TPCVarDecl);
    procedure DoCall(const ACall: TPCCall);
    // STMT A8: statements (research\cppmix\sem\statements.md "Rules")
    procedure DoPushFlow(const AKind: TPCFlowKind; const AOwner: TPCStmt);
    procedure DoPopFlow();
    function DoInFlow(const AKind: TPCFlowKind): Boolean;
    function DoInnermost(const AKinds: TPCFlowKinds): Integer;
    procedure DoFlowList(const AKind: TPCFlowKind; const AOwner: TPCStmt; const AList: TList<TPCStmt>);
    function DoCheckIteratorWrite(const ATarget: TPCExpr): Boolean;
    function DoNotVariableText(const ADecl: TPCNode): string;
    function DoBindIterator(const AFor: TPCFor): TPCTypeExpr;
    procedure DoForStmt(const AFor: TPCFor);
    function DoMatchSubjectType(const ASubject: TPCExpr): TPCTypeExpr;
    function DoWideLess(const AFirstHigh: Int64; const AFirstLow: UInt64; const ASecondHigh: Int64;
      const ASecondLow: UInt64): Boolean;
    function DoSpansOverlap(const AFirst: TPCMatchSpan; const ASecond: TPCMatchSpan): Boolean;
    function DoLabelText(const ALabel: TPCMatchLabel): string;
    function DoCheckLabelBound(const ABound: TPCExpr; const ASubjectType: TPCTypeExpr): Boolean;
    function DoCheckMatchLabel(const ALabel: TPCMatchLabel; const ASubjectType: TPCTypeExpr;
      const ASpans: TList<TPCMatchSpan>): Boolean;
    procedure DoCheckCoverage(const AMatch: TPCMatch; const ASubjectType: TPCTypeExpr;
      const ASpans: TList<TPCMatchSpan>);
    procedure DoMatchStmt(const AMatch: TPCMatch);
    procedure DoGuardStmt(const AGuard: TPCGuard);
    function DoJumpOut(const AJump: TPCStmt; const ATargetIndex: Integer; const AEscape: TPCGuardEscape): Boolean;
    procedure DoLeaveStmt(const ALeave: TPCLeave);
    procedure DoSkipStmt(const ASkip: TPCSkip);
    procedure DoReturnStmt(const AReturn: TPCReturn);
    function DoIsCppTyped(const AExpr: TPCExpr): Boolean;
    function DoHasEffect(const AExpr: TPCExpr): Boolean;
    procedure DoExprStmt(const AStmt: TPCExprStmt);
    procedure DoVerbatimStmt(const AStmt: TPCVerbatimStmt);
    function DoStmtReturns(const AStmt: TPCStmt): Boolean;
    function DoListReturns(const AList: TList<TPCStmt>): Boolean;
    class function DoHasRecoveredTarget(const ATargets: TList<TPCCallTarget>): Boolean; static;
    procedure DoCheckReturnPath(const ARoutine: TPCRoutine);
  protected
    // The one file-system read of the pass (Q28); may raise: the caller
    // reports SM0107. A testbed subclass overrides it (F-A2-5)
    function DoPathExists(const APath: string; const ADirectory: Boolean): Boolean; virtual;
  public
    constructor Create(); override;
    // Analyzes every module of AAst, also a tree the parser reported errors on
    procedure Analyze(const AAst: TPCAst);
    // The last Analyze's directive paths tested against the disk, each once,
    // without the long-path prefix (the LSP server watches them)
    function DiskPaths(): TArray<string>;
    // The SM0311 message, the one text of both paths (PLAN-PASKAL-ERRORS
    // r-b D1): SEM's report and the emitted check the Compiler reports
    // (E3). AValueText = the align value as the user reads it, ANatural the
    // natural alignment in bytes, ATypeName the record's PaskalCPP name
    class function AlignNaturalText(const AValueText: string; const ANatural: UInt64;
      const ATypeName: string): string; static;
    // SM0310 / SM0312's messages, the same way (F31: a C++ align value is
    // judged by the emitted check)
    class function AlignPowerText(const AValueText: string): string; static;
    class function AlignMaxText(const AValueText: string): string; static;
    // SM0277's message (F47): a type too large to exist, ATypeText its
    // PaskalCPP spelling; one text for SEM's folded count, the runtime's
    // Array check and clang's record text (the Compiler reports those two)
    class function TooLargeText(const ATypeText: string): string; static;
    // SM0425's message for a print argument of a C/C++ type with no
    // std::formatter: the emitted check's text (E7; SEM cannot judge it)
    class function PrintNoFormatterText(const ATypeText: string): string; static;
    // PLAN-VENDOR 1e: SM0425's message for an argument with no print form (a
    // record / object / overlay, an overload set or a method; PrintFormOfArg),
    // one routine for SEM's print check and the Compiler's report of a C++
    // routine's argument (the runtime's format_arg check); '' = it has a form
    class function UnprintableArgText(const AArg: TPCExpr): string; static;
    // SM0425 at a C++ routine's call when the argument with no std::formatter
    // cannot be told apart (several C/C++ arguments: PLAN-VENDOR 1e)
    class function NoFormatterArgsText(const ACalleeText: string): string; static;
    // SM0502 / SM0500's messages (PLAN-VENDOR 1e: clang's check of a
    // std::format_string argument, reported by the Compiler)
    class function FormatMismatchText(const AFormatText: string; const ACount: Integer): string; static;
    class function FormatNotLiteralText(const AFormatText: string): string; static;
    // SM0332's message (PLAN-OBJECT O13b): a method that overrides a virtual
    // of AOwner without `override`; one text for SEM and the emitted check
    // (a C/C++ parent's virtual, which only clang sees)
    class function NeedsOverrideText(const AName: string; const AOwner: string): string; static;
    // SM0333 / SM0334's messages for an override on a chain reaching C/C++
    // that clang finds overrides nothing (O13b (4)): ARecordName the object,
    // ACppParent the C/C++ class (SM0333's text is SEM's own too)
    class function OverridesNothingText(const AName: string; const ARecordName: string): string; static;
    class function OverrideCppSignatureText(const AName: string; const ACppParent: string): string; static;
    // SM0331's message (PLAN-RECORDS M9), both paths: AFieldName the field
    // ('' = the record's parent), ARecordName the packed record, ATypeText
    // the field's type; AByClang = the emitted check's (a C/C++ leaf that is
    // not plain data), else SEM's (a string / dynamic array held)
    class function PackedFieldText(const AFieldName: string; const ARecordName: string;
      const ATypeText: string; const AByClang: Boolean): string; static;
    // SM0313's message (F34), one routine for SEM and the Compiler's report
    // of the emitted overlay-field check: AName the type declaring the field
    // (an overlay, or a record / object holding an anonymous overlay);
    // AByClang = the emitted check's (a C/C++ leaf that is not plain data)
    class function OverlayFieldText(const AFieldName: string; const AName: string;
      const ATypeText: string; const AByClang: Boolean): string; static;
  end;

  { TPCSemanticsClass }
  // Lets the testbed run a subclass through the same harness
  TPCSemanticsClass = class of TPCSemantics;

implementation

uses
  System.IOUtils,
  System.Math,
  StdApp.Utils,
  StdApp.Resources;

const
  { PC_SEM_VALUE_GUI }
  // The @subsystem value applicability depends on (a PC_DIRECTIVE_VALUES spelling)
  PC_SEM_VALUE_GUI = 'gui';
  { PC_SEM_VALUE_ON }
  // The @addverinfo value applicability and the @vi* rule depend on
  PC_SEM_VALUE_ON = 'on';
  { PC_SEM_RESERVED_MACRO_PREFIX }
  // @cppdefine / @cppundef: the compiler sets PCPP_BUILD_DLL / PCPP_DEBUG and
  // the runtime reads PCPP_* names, so a program defines none of them
  PC_SEM_RESERVED_MACRO_PREFIX = 'PCPP_';

{ TPCSemantics }

constructor TPCSemantics.Create();
begin
  inherited;

  FAst := nil;
  FModule := nil;
  FDiskPaths := nil;
  FFrames := nil;
  FDefining := nil;
  FPendingOwners := nil;
  FFlow := nil;
  FCppMacros := nil;
  FRoutine := nil;
  FIterators := nil;
  FVarargsLocal := nil;
  FRecoveredDepth := 0;
end;

procedure TPCSemantics.Analyze(const AAst: TPCAst);
var
  LIndex: Integer;
begin
  // Each module once, in dependency order (TPCAst.ModuleAt)
  FAst := AAst;
  FDiskPaths := nil;
  FFrames := TList<TPCScopeFrame>.Create();
  FDefining := TList<TPCTypeDecl>.Create();
  FPendingOwners := TList<TPCOwnerType>.Create();
  FFlow := TList<TPCFlowEntry>.Create();
  FIterators := TList<TPCNode>.Create();
  FCppMacros := TDictionary<string, TPCDirective>.Create();
  FRoutine := nil;
  FRecoveredDepth := 0;
  try
    for LIndex := 0 to AAst.ModuleCount() - 1 do
    begin
      if DoStopped() then
        Break;
      DoAnalyzeModule(AAst.ModuleAt(LIndex));
    end;
  finally
    FCppMacros.Free();
    FCppMacros := nil;
    FIterators.Free();
    FIterators := nil;
    FFlow.Free();
    FFlow := nil;
    FRoutine := nil;
    FDefining.Free();
    FDefining := nil;
    FPendingOwners.Free();
    FPendingOwners := nil;
    FFrames.Free();
    FFrames := nil;
    FAst := nil;
    FModule := nil;
  end;
end;

function TPCSemantics.DoStopped(): Boolean;
begin
  Result := FErrors.ReachedMaxErrors();
end;

function TPCSemantics.DoReportAt(const ANode: TPCNode; const ASeverity: TErrorSeverity;
  const ACode: string; const AMessage: string; const AArgs: array of const): Boolean;
begin
  // Nothing is reported on a node the parser kept marked (PLAN-RECOVERY):
  // its report is the parser's
  if ANode.IsRecovered then
    Exit(False);
  Result := DoReportRange(ANode.Range, ASeverity, ACode, AMessage, AArgs);
end;

function TPCSemantics.DoReportRange(const ARange: TSourceRange;
  const ASeverity: TErrorSeverity; const ACode: string; const AMessage: string;
  const AArgs: array of const): Boolean;
var
  LBefore: Integer;
begin
  // The one place SEM reports. True = TErrors kept the item (an error past
  // the budget is dropped), so a note is attached only to its own report
  // (F-A1a-2). Inside a recovered node nothing is reported (D-R3-1)
  if FRecoveredDepth > 0 then
    Exit(False);
  LBefore := FErrors.Count();
  FErrors.Add(ARange, ASeverity, ACode, AMessage, AArgs);
  Result := FErrors.Count() > LBefore;
end;

function TPCSemantics.DoEnterRecovered(const ANode: TPCNode): Boolean;
begin
  // A node the parser reported inside (IsRecovered) or an error node: SEM
  // reports nothing while inside it. True = entered: the caller pairs it
  // with DoLeaveRecovered in a finally
  Result := ANode.IsRecovered or (ANode is TPCErrorStmt) or (ANode is TPCErrorExpr) or
    (ANode is TPCErrorMember);
  if Result then
    Inc(FRecoveredDepth);
end;

procedure TPCSemantics.DoLeaveRecovered();
begin
  Dec(FRecoveredDepth);
end;

function TPCSemantics.DoError(const ANode: TPCNode; const ACode: string; const AMessage: string;
  const AArgs: array of const): Boolean;
begin
  Result := DoReportAt(ANode, esError, ACode, AMessage, AArgs);
end;

function TPCSemantics.DoWarning(const ANode: TPCNode; const ACode: string; const AMessage: string;
  const AArgs: array of const): Boolean;
begin
  Result := DoReportAt(ANode, esWarning, ACode, AMessage, AArgs);
end;

procedure TPCSemantics.DoNote(const ANode: TPCNode; const AMessage: string; const AArgs: array of const);
begin
  // A note belongs to a report; inside a recovered node there is none
  if FRecoveredDepth > 0 then
    Exit;
  FErrors.AddRelated(ANode.Range, AMessage, AArgs);
end;

procedure TPCSemantics.DoPoison(const AExpr: TPCExpr);
begin
  // A poisoned node keeps no folded value: a position that wants a value
  // never takes the value of a reported expression (C1)
  if AExpr = nil then
    Exit;
  AExpr.ResolvedType := FAst.ErrorType();
  AExpr.HasConstValue := False;
  AExpr.HasConstFloat := False;
end;

function TPCSemantics.DoIsPoisoned(const AExpr: TPCExpr): Boolean;
begin
  Result := (AExpr <> nil) and (AExpr.ResolvedType is TPCErrorType);
end;

procedure TPCSemantics.DoPushFrame(const AFrame: TPCScopeFrame);
begin
  FFrames.Add(AFrame);
end;

procedure TPCSemantics.DoPopFrame();
begin
  FFrames.Delete(FFrames.Count - 1);
end;

function TPCSemantics.DoTopIndex(): Integer;
begin
  Result := FFrames.Count - 1;
end;

procedure TPCSemantics.DoLookup(const AName: string; const AFound: TList<TPCNode>);
var
  LFrameKind: TPCFrameKind;
begin
  DoLookup(AName, AFound, LFrameKind);
end;

procedure TPCSemantics.DoLookup(const AName: string; const AFound: TList<TPCNode>;
  out AFrameKind: TPCFrameKind);
var
  LIndex: Integer;
begin
  // Innermost frame first; the first frame with any match wins (scopes.md
  // Lookup 1-2), then a forward whose full declaration is also found drops.
  // AFrameKind = the frame that matched (fkMembers: a method's member named
  // bare, PLAN-OBJECT D9); fkSystem when none did
  AFound.Clear();
  AFrameKind := fkSystem;
  for LIndex := FFrames.Count - 1 downto 0 do
  begin
    TPCScopes.Collect(FFrames[LIndex], AName, AFound);
    if AFound.Count > 0 then
    begin
      AFrameKind := FFrames[LIndex].FrameKind;
      Break;
    end;
  end;
  TPCScopes.CollapseForwards(AFound);
end;

procedure TPCSemantics.DoBareMember(const AAt: TPCNode; const AName: string);
var
  LOwner: TPCRecordType;
  LTypeDecl: TPCTypeDecl;
  LOwnerText: string;
begin
  // Members are reached through self (D9): a local or parameter of the same
  // name still wins (an inner frame), an outer name never binds silently
  LOwner := DoMethodOwner(LTypeDecl);
  if LTypeDecl <> nil then
    LOwnerText := LTypeDecl.DeclName
  else if LOwner <> nil then
    LOwnerText := LOwner.TypeText()
  else
    LOwnerText := '?';
  DoError(AAt, PC_ERR_SEM_018, RSSemCoreBareMember, [AName, LOwnerText, AName]);
end;

function TPCSemantics.DoHiddenBlocks(const AAt: TPCNode; const AMember: TPCNode; const AName: string;
  const ASearched: TPCTypeExpr; const ASearchedText: string; const AThroughParent: Boolean;
  const AReport: Boolean): Boolean;
var
  LOwner: TPCRecordType;
  LTypeDecl: TPCTypeDecl;
  LSearched: TPCTypeExpr;
  LLevel: TPCTypeExpr;
  LReach: TPCHiddenReach;
  LOwnerText: string;
  LLevelText: string;
begin
  // parent.<member> names self's inherited member (the emitter writes
  // Parent::member on this): searched through self's own type
  LOwner := DoMethodOwner(LTypeDecl);
  LSearched := ASearched;
  if AThroughParent then
    LSearched := LOwner;
  LReach := TPCScopes.HiddenReach(AMember, LSearched, LOwner, LLevel);
  Result := LReach <> hrVisible;
  if (not Result) or (not AReport) then
    Exit;
  LLevelText := DoLevelText(ASearched, ASearchedText, LLevel);
  if LTypeDecl <> nil then
    LOwnerText := LTypeDecl.DeclName
  else if LOwner <> nil then
    LOwnerText := LOwner.TypeText()
  else
    LOwnerText := '';
  if LReach = hrOutside then
    DoError(AAt, PC_ERR_SEM_019, RSSemCoreHiddenOutside, [AName, LLevelText, LLevelText])
  else
    DoError(AAt, PC_ERR_SEM_019, RSSemCoreHiddenThrough, [AName, LLevelText, LOwnerText, LOwnerText]);
end;

function TPCSemantics.DoLevelText(const AStart: TPCTypeExpr; const AStartText: string;
  const ALevel: TPCTypeExpr): string;
var
  LType: TPCTypeExpr;
  LVisited: TList<TPCTypeExpr>;
begin
  // Each level is named by the ParentName of the level below it
  Result := AStartText;
  LVisited := TList<TPCTypeExpr>.Create();
  try
    LType := AStart;
    while (LType is TPCRecordType) and (LType <> ALevel) and (not LVisited.Contains(LType)) do
    begin
      LVisited.Add(LType);
      if TPCRecordType(LType).ParentName = nil then
        Exit;
      Result := TPCRecordType(LType).ParentName.TypeText();
      LType := TPCRecordType(LType).ParentName.Canon();
    end;
  finally
    LVisited.Free();
  end;
end;

function TPCSemantics.DoResolvedKindOf(const ADecl: TPCNode): TPCResolvedKind;
begin
  // The one class -> kind map every resolver uses
  if ADecl is TPCVarDecl then
    Result := rkVar
  else if ADecl is TPCConstDecl then
    Result := rkConst
  else if ADecl is TPCTypeDecl then
    Result := rkType
  else if ADecl is TPCRoutine then
    Result := rkRoutine
  else if ADecl is TPCParam then
    Result := rkParam
  else if ADecl is TPCImport then
    Result := rkModule
  else if ADecl is TPCField then
    Result := rkField
  else if ADecl is TPCChoiceValue then
    Result := rkChoiceValue
  else
    Result := rkNone;
end;

function TPCSemantics.DoOwnItem(const AName: string): TPCStmt;
var
  LIndex: Integer;
  LCurrent: TPCStmt;
begin
  // The item being declared whose own declaration uses its name (scopes.md
  // point of declaration): innermost frame first
  Result := nil;
  for LIndex := FFrames.Count - 1 downto 0 do
  begin
    LCurrent := FFrames[LIndex].Current;
    if (LCurrent is TPCDecl) and (TPCDecl(LCurrent).DeclName = AName) then
      Exit(LCurrent);
  end;
end;

function TPCSemantics.DoUsedLater(const AName: string): TPCNode;
begin
  // A name declared later in a frame on the chain (scopes.md used-before):
  // the one rule lives in TPCScopes (the LSP's completion reads it too)
  Result := TPCScopes.DeclaredLater(FFrames, AName);
end;

function TPCSemantics.DoIntrinsicOf(const AName: string): TPCIntrinsicKind;
var
  LKind: TPCIntrinsicKind;
begin
  Result := ikNone;
  for LKind := Succ(ikNone) to High(TPCIntrinsicKind) do
  begin
    if PC_INTRINSIC_NAMES[LKind] = AName then
      Exit(LKind);
  end;
end;

function TPCSemantics.DoMethodOwner(out ATypeDecl: TPCTypeDecl): TPCRecordType;
var
  LIndex: Integer;
begin
  Result := nil;
  ATypeDecl := nil;
  for LIndex := FFrames.Count - 1 downto 0 do
  begin
    if FFrames[LIndex].FrameKind = fkMembers then
    begin
      if FFrames[LIndex].Owner is TPCRecordType then
        Result := TPCRecordType(FFrames[LIndex].Owner);
      ATypeDecl := FFrames[LIndex].TypeDecl;
      Exit;
    end;
  end;
end;

function TPCSemantics.DoInMethodOf(const ADecl: TPCTypeDecl): Boolean;
var
  LIndex: Integer;
begin
  // Inside a method of that object: its name is the complete type (F-A1c-1)
  Result := False;
  for LIndex := FFrames.Count - 1 downto 0 do
  begin
    if (FFrames[LIndex].FrameKind = fkMembers) and (FFrames[LIndex].TypeDecl = ADecl) then
      Exit(True);
  end;
end;

function TPCSemantics.DoOwnValue(const AName: string): TPCChoiceValue;
var
  LFrame: TPCScopeFrame;
  LChoices: TPCChoicesType;
begin
  // A choice value's own name inside its own value expression
  Result := nil;
  if FFrames.Count = 0 then
    Exit;
  LFrame := FFrames[DoTopIndex()];
  if LFrame.FrameKind <> fkChoices then
    Exit;
  LChoices := TPCChoicesType(LFrame.Owner);
  if (LFrame.FirstCount < LChoices.Values.Count) and (LChoices.Values[LFrame.FirstCount] <> nil) and
    (LChoices.Values[LFrame.FirstCount].ValueName = AName) then
    Result := LChoices.Values[LFrame.FirstCount];
end;

function TPCSemantics.DoResolveOwnType(const ADecl: TPCTypeDecl; const AAt: TPCNode): TPCTypeDecl;
var
  LFound: TList<TPCNode>;
  LNode: TPCNode;
begin
  // A type item's own name inside its own definition: the complete type in a
  // method, else a visible forward, else SM0003
  if DoInMethodOf(ADecl) then
    Exit(ADecl);
  Result := nil;
  LFound := TList<TPCNode>.Create();
  try
    DoLookup(ADecl.DeclName, LFound);
    for LNode in LFound do
    begin
      if (LNode is TPCTypeDecl) and TPCTypeDecl(LNode).IsForward then
        Exit(TPCTypeDecl(LNode));
    end;
  finally
    LFound.Free();
  end;
  DoError(AAt, PC_ERR_SEM_003, RSSemCoreTypeSelf, [ADecl.DeclName]);
end;

function TPCSemantics.DoModuleMember(const AModule: TPCModule; const AName: string;
  const AFound: TList<TPCNode>): Boolean;
begin
  // The imported module is complete (analyzed first): TPCScopes owns the rule
  Result := TPCScopes.ModuleMember(AModule, AName, AFound);
end;

function TPCSemantics.DoChoiceMember(const AChoices: TPCChoicesType; const AName: string): TPCChoiceValue;
var
  LValue: TPCChoiceValue;
begin
  Result := nil;
  for LValue in AChoices.Values do
  begin
    if (LValue <> nil) and (LValue.ValueName = AName) then
      Exit(LValue);
  end;
end;

function TPCSemantics.DoAllRoutines(const AFound: TList<TPCNode>): Boolean;
var
  LNode: TPCNode;
begin
  Result := AFound.Count > 0;
  for LNode in AFound do
  begin
    if not (LNode is TPCRoutine) then
      Exit(False);
  end;
end;

procedure TPCSemantics.DoReportDuplicate(const ALater: TPCNode; const AFirst: TPCNode; const AName: string);
begin
  // A half-written declaration is mid-typing: no duplicate is judged against
  // it (PLAN-RECOVERY)
  if ALater.IsRecovered or AFirst.IsRecovered then
    Exit;
  if DoError(ALater, PC_ERR_SEM_004, RSSemCoreDuplicate, [AName]) then
    DoNote(AFirst, RSSemCoreFirstDecl, [AName]);
end;

procedure TPCSemantics.DoCheckDuplicate(const ADecl: TPCDecl);
var
  LFound: TList<TPCNode>;
  LIndex: Integer;
  LNode: TPCNode;
  LDrop: Boolean;
begin
  // Top frame only (an outer same name is hiding). An earlier routine never
  // makes a later routine a duplicate (A5 rules on overloads / forwards), nor
  // a forward type pair (D-A1c-3)
  if FFrames.Count = 0 then
    Exit;
  LFound := TList<TPCNode>.Create();
  try
    TPCScopes.Collect(FFrames[DoTopIndex()], ADecl.DeclName, LFound);
    for LIndex := LFound.Count - 1 downto 0 do
    begin
      LNode := LFound[LIndex];
      LDrop := LNode = ADecl;
      if (ADecl is TPCRoutine) and (LNode is TPCRoutine) then
        LDrop := True;
      if (ADecl is TPCTypeDecl) and (LNode is TPCTypeDecl) and
        (TPCTypeDecl(ADecl).IsForward or TPCTypeDecl(LNode).IsForward) then
        LDrop := True;
      if LDrop then
        LFound.Delete(LIndex);
    end;
    if LFound.Count > 0 then
      DoReportDuplicate(ADecl, LFound[0], ADecl.DeclName);
  finally
    LFound.Free();
  end;
end;

procedure TPCSemantics.DoCheckReservedNames(const AModule: TPCModule);
var
  LPending: TList<TPCNode>;
  LChildren: TList<TPCNode>;
  LIndex: Integer;
  LNode: TPCNode;
  LName: string;
  LRange: TSourceRange;
begin
  // M11 (PLAN-RECORDS A9): a PaskalCPP declaration (module, item, local,
  // parameter, field, choice value, routine, type) never starts its name
  // with pcpp_, the compiler's own C++ names (case-sensitive, as C++ names
  // are). One walk over the module's own nodes (a work list, as
  // TPCAst.ModuleNamesRuntime); a recovered or error node is not judged
  // (PLAN-RECOVERY). A C/C++ name in mixed C++ is clang's
  LPending := TList<TPCNode>.Create();
  LChildren := TList<TPCNode>.Create();
  try
    LPending.Add(AModule);
    while LPending.Count > 0 do
    begin
      LNode := LPending[LPending.Count - 1];
      LPending.Delete(LPending.Count - 1);
      if (LNode = nil) or LNode.IsRecovered or (LNode is TPCErrorStmt) or (LNode is TPCErrorExpr) or
        (LNode is TPCErrorMember) then
        Continue;
      if TPCAst.DeclaredName(LNode, LName, LRange) and LName.StartsWith(PC_RESERVED_PREFIX) then
        DoReportRange(LRange, esError, PC_ERR_SEM_017, RSSemCoreReservedName, [LName, PC_RESERVED_PREFIX]);
      // Children pushed last-first: the next popped is the first child, so
      // the reports come in source order
      LChildren.Clear();
      LNode.EnumChildren(
        procedure(const AChild: TPCNode)
        begin
          LChildren.Add(AChild);
        end);
      for LIndex := LChildren.Count - 1 downto 0 do
        LPending.Add(LChildren[LIndex]);
    end;
  finally
    LChildren.Free();
    LPending.Free();
  end;
end;

procedure TPCSemantics.DoCheckParamDuplicates(const AParams: TList<TPCParam>);
var
  LIndex: Integer;
  LEarlier: Integer;
begin
  if AParams = nil then
    Exit;
  for LIndex := 1 to AParams.Count - 1 do
  begin
    if AParams[LIndex] = nil then
      Continue;
    for LEarlier := 0 to LIndex - 1 do
    begin
      if (AParams[LEarlier] <> nil) and (AParams[LEarlier].ParamName = AParams[LIndex].ParamName) then
      begin
        DoReportDuplicate(AParams[LIndex], AParams[LEarlier], AParams[LIndex].ParamName);
        Break;
      end;
    end;
  end;
end;

procedure TPCSemantics.DoCheckMemberDuplicates(const ATypeMembers: TList<TPCMemberItem>;
  const AItems: TList<TPCMemberItem>);
var
  LItem: TPCMemberItem;
  LNode: TPCNode;
  LName: string;
  LFound: TList<TPCNode>;
begin
  // Any field / method name repeated in one type, anonymous aggregates
  // hoisted (decls.md :106); the parent chain is A5's SM0309
  if AItems = nil then
    Exit;
  LFound := TList<TPCNode>.Create();
  try
    for LItem in AItems do
    begin
      LNode := nil;
      LName := '';
      if LItem is TPCField then
      begin
        LNode := LItem;
        LName := TPCField(LItem).FieldName;
      end
      else if (LItem is TPCMethodItem) and (TPCMethodItem(LItem).Routine <> nil) then
      begin
        LNode := TPCMethodItem(LItem).Routine;
        LName := TPCMethodItem(LItem).Routine.DeclName;
      end
      // PLAN-OBJECT O9: a property's name is a member name too
      else if LItem is TPCPropertyItem then
      begin
        LNode := LItem;
        LName := TPCPropertyItem(LItem).PropName;
      end
      else if LItem is TPCAnonAggregate then
        DoCheckMemberDuplicates(ATypeMembers, TPCAnonAggregate(LItem).Members);
      if LNode = nil then
        Continue;
      LFound.Clear();
      TPCScopes.CollectMembersNamed(ATypeMembers, LName, LFound);
      if (LFound.Count > 0) and (LFound[0] <> LNode) then
        DoReportDuplicate(LNode, LFound[0], LName);
    end;
  finally
    LFound.Free();
  end;
end;

function TPCSemantics.DoModelTarget(): TPCTargetTriple;
begin
  // The analyzed module's data model: a unit carries its main's triple. An
  // empty triple (the filter reported the @target) reads the default target's
  // row, and target-dependent checks stay silent (D-A3a-1)
  if FModule.ResolvedTarget.IsEmpty() then
    Result := TPCTargetTriple.DefaultTriple()
  else
    Result := FModule.ResolvedTarget;
end;

function TPCSemantics.DoNamedTypeOf(const ADecl: TPCTypeDecl): TPCNamedType;
var
  LType: TPCNamedType;
begin
  // One SEM-built name node per type declaration (a choice value's or self's
  // type); its Canon is the declaration's TypeDef through the rkType rule.
  // Arena-owned and never reported on, so it carries no Range
  if ADecl.ResolvedNamedType <> nil then
    Exit(ADecl.ResolvedNamedType);
  LType := FAst.NewNode<TPCNamedType>();
  LType.Parts := [ADecl.DeclName];
  LType.ResolvedKind := rkType;
  LType.ResolvedDecl := ADecl;
  ADecl.ResolvedNamedType := LType;
  Result := LType;
end;

function TPCSemantics.DoValueTypeOf(const AType: TPCTypeExpr): TPCTypeExpr;
begin
  // A declared type the parser dropped or CORE could not resolve: error, no
  // report (CORE reported it, C1 cascade; D-A3a-3)
  if AType = nil then
    Exit(FAst.ErrorType());
  if (AType is TPCNamedType) and (TPCNamedType(AType).ResolvedKind = rkNone) then
    Exit(FAst.ErrorType());
  Result := AType;
end;

function TPCSemantics.DoIntLiteralToken(const ALiteral: TPCLiteral): TPCTokenKind;
var
  LRow: TPCIntSuffixRow;
  LTarget: TPCTargetTriple;
  LIsDecimal: Boolean;
  LWidths: TArray<Integer>;
  LWidth: Integer;
  LValue: UInt64;
begin
  // C++23 [lex.icon] table 8, so the type SEM folds in is the one clang
  // computes the emitted literal in (F30, user 2026-10-12 "ok" = (b)): the
  // first candidate that holds the value. The candidates start at the
  // suffix's width (int, long, long long; z = size_t's width), a decimal
  // literal without u lists the signed ones, a hex / octal / binary one each
  // signed type then its unsigned twin, a u suffix the unsigned ones only.
  // The widths are the target's data model: long is 32 bits on windows-gnu,
  // 64 on linux-gnu, exactly as clang types `5l`
  LRow := Default(TPCIntSuffixRow);
  if (ALiteral.Suffix <> '') and not TPCVocabulary.FindIntSuffix(ALiteral.Suffix, LRow) then
    LRow := Default(TPCIntSuffixRow);
  LTarget := DoModelTarget();
  LIsDecimal := ALiteral.LiteralBase = lbDecimal;
  case LRow.SuffixWidth of
    iwInt:
      LWidths := [LTarget.IntBits(), LTarget.LongBits(), LTarget.LongLongBits()];
    iwLong:
      LWidths := [LTarget.LongBits(), LTarget.LongLongBits()];
    iwLongLong:
      LWidths := [LTarget.LongLongBits()];
  else
    LWidths := [LTarget.SizeTBits()];
  end;
  LValue := ALiteral.IntValue;
  for LWidth in LWidths do
  begin
    // The signed candidate of this width (none with a u suffix)
    if not LRow.IsUnsigned then
    begin
      if LValue <= (UInt64(1) shl (LWidth - 1)) - 1 then
      begin
        if LWidth <= 32 then
          Exit(tkKwInt32);
        Exit(tkKwInt64);
      end;
    end;
    // Its unsigned twin (a u suffix, or a non-decimal base)
    if LRow.IsUnsigned or not LIsDecimal then
    begin
      if (LWidth >= 64) or (LValue <= (UInt64(1) shl LWidth) - 1) then
      begin
        if LWidth <= 32 then
          Exit(tkKwUint32);
        Exit(tkKwUint64);
      end;
    end;
  end;
  // No candidate holds it: the lexer reported LX0006 (F19); uint64 keeps the
  // value without a second report
  Result := tkKwUint64;
end;

procedure TPCSemantics.DoIntLiteral(const ALiteral: TPCLiteral);
var
  LToken: TPCTokenKind;
  LBits: Integer;
  LIsUnsigned: Boolean;
begin
  // The literal's VALUE is PaskalCPP data: the no-loss conversion rule and
  // the bounds, labels and ordinals read it. Its type is C++23's
  // (DoIntLiteralToken), so a constant expression folds in the type clang
  // computes it in. A user-defined literal is C++ only (opaque)
  if ALiteral.IsUserDefined then
  begin
    ALiteral.ResolvedType := FAst.OpaqueType();
    Exit;
  end;
  // Cannot occur (a bad number is tkUnknown, never an integer literal without
  // a value): kept nil-safe, no report
  if not ALiteral.HasValue then
  begin
    ALiteral.ResolvedType := FAst.ErrorType();
    Exit;
  end;
  LToken := DoIntLiteralToken(ALiteral);
  DoIntTypeInfo(LToken, LBits, LIsUnsigned);
  ALiteral.ResolvedType := FAst.BuiltinType(LToken);
  ALiteral.HasConstValue := True;
  ALiteral.ConstIsUnsigned := LIsUnsigned;
  if LIsUnsigned then
    ALiteral.ConstUInt := ALiteral.IntValue
  else
    ALiteral.ConstInt := Int64(ALiteral.IntValue);
end;

procedure TPCSemantics.DoFloatLiteral(const ALiteral: TPCLiteral);
begin
  // l, f16 (Lexer PC_FLOAT_SUFFIXES): the lexer gives them no value (opaque);
  // f32 / f64 / f128 / bf16 never get here (LX0005, PC_FLOAT_SUFFIXES_REFUSED)
  if ALiteral.IsUserDefined or (not ALiteral.HasValue) then
  begin
    ALiteral.ResolvedType := FAst.OpaqueType();
    Exit;
  end;
  // A value exists only for '', f and F; it is already rounded to its format
  if ALiteral.Suffix = '' then
    ALiteral.ResolvedType := FAst.BuiltinType(tkKwFloat64)
  else
    ALiteral.ResolvedType := FAst.BuiltinType(tkKwFloat32);
  ALiteral.HasConstFloat := True;
  ALiteral.ConstFloat := ALiteral.FloatValue;
end;

procedure TPCSemantics.DoCharLiteral(const ALiteral: TPCLiteral);
var
  LTarget: TPCTargetTriple;
  LBits: Integer;
  LValue: Int64;
begin
  // 'a' is a char, L'a' a wchar, each with its value (bounds, labels and sets
  // read it). u8 / u / U, user-defined and multi-char literals are C++ only
  if ALiteral.IsUserDefined or ALiteral.IsMultiChar or
    (ALiteral.LiteralPrefix in [lpU8, lpLowerU, lpUpperU]) then
  begin
    ALiteral.ResolvedType := FAst.OpaqueType();
    Exit;
  end;
  // PR0054 reported a char the parser could not decode
  if not ALiteral.HasValue then
  begin
    ALiteral.ResolvedType := FAst.ErrorType();
    Exit;
  end;
  LTarget := DoModelTarget();
  if ALiteral.LiteralPrefix = lpNone then
  begin
    // char: a byte above 127 is negative where char is signed
    ALiteral.ResolvedType := FAst.BuiltinType(tkKwChar);
    LValue := Int64(ALiteral.IntValue);
    if LTarget.IsCharSigned() and (ALiteral.IntValue > 127) then
      LValue := LValue - 256;
  end
  else
  begin
    // L: a value the target's wchar_t cannot hold is clang's to report
    LBits := LTarget.WCharBits();
    if (LBits < 64) and (ALiteral.IntValue >= (UInt64(1) shl LBits)) then
    begin
      ALiteral.ResolvedType := FAst.OpaqueType();
      Exit;
    end;
    ALiteral.ResolvedType := FAst.BuiltinType(tkKwWchar);
    LValue := Int64(ALiteral.IntValue);
    if LTarget.IsWCharSigned() and (ALiteral.IntValue >= (UInt64(1) shl (LBits - 1))) then
      LValue := LValue - (Int64(1) shl LBits);
  end;
  ALiteral.HasConstValue := True;
  ALiteral.ConstIsUnsigned := False;
  ALiteral.ConstInt := LValue;
end;

procedure TPCSemantics.DoStringLiteral(const ALiteral: TPCLiteral);
var
  LPart: TPCLiteralPart;
  LIsWide: Boolean;
begin
  // The parser reported a literal with no part
  if Length(ALiteral.Parts) = 0 then
  begin
    ALiteral.ResolvedType := FAst.ErrorType();
    Exit;
  end;
  // C++ concatenation: one L part makes the whole literal wide; a u8 / u / U
  // or user-defined part is C++ only (opaque). Raw does not change the type
  LIsWide := False;
  for LPart in ALiteral.Parts do
  begin
    if LPart.IsUserDefined or (LPart.LiteralPrefix in [lpU8, lpLowerU, lpUpperU]) then
    begin
      ALiteral.ResolvedType := FAst.OpaqueType();
      Exit;
    end;
    if LPart.LiteralPrefix = lpUpperL then
      LIsWide := True;
  end;
  ALiteral.ResolvedType := FAst.StringLiteralType(LIsWide);
end;

procedure TPCSemantics.DoLiteral(const ALiteral: TPCLiteral);
begin
  // A literal's value is folded where it is typed (folding.md D1); every
  // literal is a constant, folded or not
  ALiteral.IsConstExpr := True;
  case ALiteral.LiteralKind of
    lkInteger:
      DoIntLiteral(ALiteral);
    lkFloat:
      DoFloatLiteral(ALiteral);
    lkChar:
      DoCharLiteral(ALiteral);
    lkString:
      DoStringLiteral(ALiteral);
    lkBool:
      begin
        // The parser set the value (1 / 0)
        ALiteral.ResolvedType := FAst.BuiltinType(tkKwBool);
        ALiteral.HasConstValue := ALiteral.HasValue;
        ALiteral.ConstInt := Int64(ALiteral.IntValue);
      end;
    lkNil:
      ALiteral.ResolvedType := FAst.NilType();
  end;
end;

procedure TPCSemantics.DoTypeLeaf(const AExpr: TPCExpr; const ADecl: TPCNode;
  const AKind: TPCResolvedKind);
begin
  // CORE reported it
  if DoIsPoisoned(AExpr) then
    Exit;
  if AKind = rkOpaque then
  begin
    AExpr.ResolvedType := FAst.OpaqueType();
    Exit;
  end;
  // An overload set: A6
  if ADecl = nil then
    Exit;
  // A declaration the parser could not finish: the use keeps its
  // resolution (hover, definition) and is poisoned with no report
  if ADecl.IsRecovered then
  begin
    DoPoison(AExpr);
    Exit;
  end;
  // The tree type node the user wrote (D-A3a-3); a const or choice value
  // also carries its value (A3b, folding.md "Leaves")
  case AKind of
    rkVar:
      AExpr.ResolvedType := DoValueTypeOf(TPCVarDecl(ADecl).TypeExpr);
    rkConst:
      begin
        AExpr.ResolvedType := DoValueTypeOf(TPCConstDecl(ADecl).TypeExpr);
        DoConstLeaf(AExpr, TPCConstDecl(ADecl));
      end;
    rkParam:
      AExpr.ResolvedType := DoValueTypeOf(TPCParam(ADecl).TypeExpr);
    rkField:
      AExpr.ResolvedType := DoValueTypeOf(TPCField(ADecl).TypeExpr);
    rkChoiceValue:
      begin
        // Inside its own value list a value is its ordinal, an int32 (C++'s
        // enum default; the emitter writes every ordinal folded, so `B = A * 2`
        // never reaches clang); anywhere else it is a value of its choices type
        if FFrames[DoTopIndex()].FrameKind = fkChoices then
          AExpr.ResolvedType := FAst.BuiltinType(tkKwInt32)
        else
          AExpr.ResolvedType := DoValueTypeOf(TPCChoiceValue(ADecl).ResolvedChoices);
        DoChoiceLeaf(AExpr, TPCChoiceValue(ADecl));
      end;
  else
    // rkType / rkModule (A4), rkRoutine / rkIntrinsic (A6), rkNone: not
    // typed here, each has one later owner (D-A3a-5)
  end;
end;

function TPCSemantics.DoChoicesNamedType(const AChoices: TPCChoicesType): TPCTypeExpr;
var
  LCurrent: TPCStmt;
begin
  // DoTypeDecl -> DoTypeExpr pushes no frame, so a declared choices type is
  // the TypeDef of the top frame's Current; else it is anonymous
  LCurrent := FFrames[DoTopIndex()].Current;
  if (LCurrent is TPCTypeDecl) and (TPCTypeDecl(LCurrent).TypeDef = AChoices) then
    Exit(DoNamedTypeOf(TPCTypeDecl(LCurrent)));
  Result := AChoices;
end;

function TPCSemantics.DoIsOpaqueTier(const AType: TPCTypeExpr): Boolean;
begin
  // The opaque tier (types.md "Two tiers", G3): clang owns the meaning; the
  // one rule is the AST's (TPCScopes reads it too)
  Result := TPCTypeExpr.IsOpaqueTier(AType);
end;

function TPCSemantics.DoIsErrorType(const AType: TPCTypeExpr): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // A type the parser dropped or CORE reported: nothing more is reported on it (C1)
  if AType = nil then
    Exit(True);
  LCanon := AType.Canon();
  // A type the parser kept marked, or naming a declaration it kept marked, is
  // reported on no further (PLAN-RECOVERY)
  Result := (LCanon is TPCErrorType) or
    ((LCanon is TPCNamedType) and (TPCNamedType(LCanon).ResolvedKind = rkNone)) or
    ((LCanon <> nil) and LCanon.IsRecovered) or DoNamesRecoveredDecl(AType) or
    DoHoldsErrorPart(LCanon);
end;

function TPCSemantics.DoHoldsErrorPart(const AType: TPCTypeExpr): Boolean;
var
  LParam: TPCParam;
begin
  // A type built from parts (ptr to T, array of T, set of T, a routine type's
  // parameters and result) holding a part already reported is reported on no
  // further either: one report per mistake (C1). An absent part that the
  // grammar allows (untyped ptr, a range set, a procedure) is no error
  Result := False;
  if AType is TPCPointerType then
    Exit((TPCPointerType(AType).TargetType <> nil) and DoIsErrorType(TPCPointerType(AType).TargetType));
  if AType is TPCOwnerType then
    Exit(DoIsErrorType(TPCOwnerType(AType).TargetType));
  if AType is TPCArrayType then
    Exit(DoIsErrorType(TPCArrayType(AType).ElementType));
  if AType is TPCSetType then
    Exit((TPCSetType(AType).ElementType <> nil) and DoIsErrorType(TPCSetType(AType).ElementType));
  if AType is TPCRoutineType then
  begin
    for LParam in TPCRoutineType(AType).Params do
    begin
      if (LParam = nil) or DoIsErrorType(LParam.TypeExpr) then
        Exit(True);
    end;
    Result := (TPCRoutineType(AType).ReturnType <> nil) and DoIsErrorType(TPCRoutineType(AType).ReturnType);
  end;
end;

function TPCSemantics.DoNamesRecoveredDecl(const AType: TPCTypeExpr): Boolean;
var
  LType: TPCTypeExpr;
begin
  // Through every alias (Canon ran first: no cycle) to a type declaration
  // the parser kept marked (PLAN-RECOVERY)
  LType := AType;
  while (LType is TPCNamedType) and (TPCNamedType(LType).ResolvedDecl <> nil) do
  begin
    if TPCNamedType(LType).ResolvedDecl.IsRecovered then
      Exit(True);
    LType := TPCNamedType(LType).ResolvedDecl.TypeDef;
  end;
  Result := False;
end;

function TPCSemantics.DoBuiltinOf(const AType: TPCTypeExpr; out AToken: TPCTokenKind): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  AToken := tkUnknown;
  if AType = nil then
    Exit(False);
  LCanon := AType.Canon();
  Result := LCanon is TPCBuiltinType;
  if Result then
    AToken := TPCBuiltinType(LCanon).BuiltinToken;
end;

function TPCSemantics.DoIntTypeInfo(const AToken: TPCTokenKind; out ABits: Integer;
  out AIsUnsigned: Boolean): Boolean;
begin
  // The eight PaskalCPP integer types; every other token is no integer
  Result := True;
  AIsUnsigned := (AToken = tkKwUint8) or (AToken = tkKwUint16) or (AToken = tkKwUint32) or
    (AToken = tkKwUint64);
  case AToken of
    tkKwInt8, tkKwUint8:
      ABits := 8;
    tkKwInt16, tkKwUint16:
      ABits := 16;
    tkKwInt32, tkKwUint32:
      ABits := 32;
    tkKwInt64, tkKwUint64:
      ABits := 64;
  else
    ABits := 0;
    Result := False;
  end;
end;

function TPCSemantics.DoSetOf(const AType: TPCTypeExpr; out ARange: TPCSetType;
  out AElement: TPCTypeExpr): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // A tree set type or a derived one (types.md G8): ARange is the range form
  // (set of low..high), AElement the element type otherwise
  ARange := nil;
  AElement := nil;
  if AType = nil then
    Exit(False);
  LCanon := AType.Canon();
  if LCanon is TPCSetType then
  begin
    if TPCSetType(LCanon).IsRangeForm then
      ARange := TPCSetType(LCanon)
    else
      AElement := TPCSetType(LCanon).ElementType;
    Exit(True);
  end;
  if (LCanon is TPCDerivedType) and (TPCDerivedType(LCanon).DerivedKind = dkSetOf) then
  begin
    AElement := TPCDerivedType(LCanon).Target;
    Exit(True);
  end;
  Result := False;
end;

function TPCSemantics.DoSameConst(const AFirst: TPCExpr; const ASecond: TPCExpr): Boolean;
begin
  // Two folded integers with one value (a signed and an unsigned one meet
  // only at a value both forms hold); an unfolded one is never the same
  if (AFirst = nil) or (ASecond = nil) or not AFirst.HasConstValue or not ASecond.HasConstValue then
    Exit(False);
  if AFirst.ConstIsUnsigned = ASecond.ConstIsUnsigned then
  begin
    if AFirst.ConstIsUnsigned then
      Exit(AFirst.ConstUInt = ASecond.ConstUInt);
    Exit(AFirst.ConstInt = ASecond.ConstInt);
  end;
  if AFirst.ConstIsUnsigned then
    Exit((ASecond.ConstInt >= 0) and (UInt64(ASecond.ConstInt) = AFirst.ConstUInt));
  Result := (AFirst.ConstInt >= 0) and (UInt64(AFirst.ConstInt) = ASecond.ConstUInt);
end;

function TPCSemantics.DoSameBound(const AFirst: TPCExpr; const ASecond: TPCExpr;
  const AOpaqueBySpelling: Boolean): Boolean;
begin
  // A type's bound (array, set range): two folded values compare by value;
  // a bound SEM could not fold is a C/C++ constant (a constant expression
  // was checked where it was written): clang's to judge, as an opaque type
  // is (F26), or, for two declarations of one routine, the bound its
  // spelling names
  if (AFirst = nil) or (ASecond = nil) then
    Exit(False);
  if AFirst.HasConstValue and ASecond.HasConstValue then
    Exit(DoSameConst(AFirst, ASecond));
  if not AOpaqueBySpelling then
    Exit(True);
  Result := (not AFirst.HasConstValue) and (not ASecond.HasConstValue) and
    (AFirst.ExprText() = ASecond.ExprText());
end;

function TPCSemantics.DoSameType(const AFirst: TPCTypeExpr; const ASecond: TPCTypeExpr): Boolean;
begin
  // A C type at any depth is clang's to judge (types.md "Two tiers"): ptr to
  // size_t and ptr to size_t are two nodes, not two types
  Result := DoSameTypeAs(AFirst, ASecond, False);
end;

function TPCSemantics.DoSameSignatureType(const AFirst: TPCTypeExpr; const ASecond: TPCTypeExpr): Boolean;
begin
  // Two declarations of one routine (forward pairing, R-DECL): a C type is the
  // type its spelling names; a type already reported matches (C1: no cascade)
  Result := DoSameTypeAs(AFirst, ASecond, True);
end;

function TPCSemantics.DoSameTypeAs(const AFirst: TPCTypeExpr; const ASecond: TPCTypeExpr;
  const AOpaqueBySpelling: Boolean): Boolean;
var
  LFirst: TPCTypeExpr;
  LSecond: TPCTypeExpr;
  LFirstTarget: TPCTypeExpr;
  LSecondTarget: TPCTypeExpr;
  LFirstConst: Boolean;
  LSecondConst: Boolean;
  LFirstRange: TPCSetType;
  LSecondRange: TPCSetType;
begin
  // semantics.md "Types": builtin by token; pointer, array, set and routine
  // types structurally; record, object, overlay and choices nominally (one
  // Canon node). The opaque tier at any depth: clang's to judge (True), or,
  // for two declarations of one routine, the type its spelling names. An
  // error type matches there (C1); elsewhere the callers judge it
  if AOpaqueBySpelling and (DoIsErrorType(AFirst) or DoIsErrorType(ASecond)) then
    Exit(True);
  if (AFirst = nil) or (ASecond = nil) then
    Exit(False);
  LFirst := AFirst.Canon();
  LSecond := ASecond.Canon();
  if LFirst = LSecond then
    Exit(True);
  if DoIsOpaqueTier(LFirst) or DoIsOpaqueTier(LSecond) then
  begin
    if not AOpaqueBySpelling then
      Exit(True);
    Exit(DoIsOpaqueTier(LFirst) and DoIsOpaqueTier(LSecond) and (LFirst.TypeText() = LSecond.TypeText()));
  end;
  if (LFirst is TPCBuiltinType) and (LSecond is TPCBuiltinType) then
    Exit(TPCBuiltinType(LFirst).BuiltinToken = TPCBuiltinType(LSecond).BuiltinToken);
  if TPCTypeExpr.PointerOf(LFirst, LFirstTarget, LFirstConst) and TPCTypeExpr.PointerOf(LSecond, LSecondTarget, LSecondConst) then
  begin
    if LFirstConst <> LSecondConst then
      Exit(False);
    if (LFirstTarget = nil) or (LSecondTarget = nil) then
      Exit((LFirstTarget = nil) and (LSecondTarget = nil));
    Exit(DoSameTypeAs(LFirstTarget, LSecondTarget, AOpaqueBySpelling));
  end;
  // PLAN-OBJECT O6: own / ref / weak structurally, the kind and the object held
  if (LFirst is TPCOwnerType) and (LSecond is TPCOwnerType) then
    Exit((TPCOwnerType(LFirst).OwnerKind = TPCOwnerType(LSecond).OwnerKind) and
      DoSameTypeAs(TPCOwnerType(LFirst).TargetType, TPCOwnerType(LSecond).TargetType, AOpaqueBySpelling));
  if (LFirst is TPCArrayType) and (LSecond is TPCArrayType) then
  begin
    if TPCArrayType(LFirst).IsDynamic <> TPCArrayType(LSecond).IsDynamic then
      Exit(False);
    // A static array: the same bounds (DoSameBound: a C/C++ one is clang's)
    if not TPCArrayType(LFirst).IsDynamic and
      (not DoSameBound(TPCArrayType(LFirst).LowExpr, TPCArrayType(LSecond).LowExpr, AOpaqueBySpelling) or
      not DoSameBound(TPCArrayType(LFirst).HighExpr, TPCArrayType(LSecond).HighExpr, AOpaqueBySpelling)) then
      Exit(False);
    Exit(DoSameTypeAs(TPCArrayType(LFirst).ElementType, TPCArrayType(LSecond).ElementType, AOpaqueBySpelling));
  end;
  if DoSetOf(LFirst, LFirstRange, LFirstTarget) and DoSetOf(LSecond, LSecondRange, LSecondTarget) then
  begin
    if (LFirstRange <> nil) or (LSecondRange <> nil) then
      Exit((LFirstRange <> nil) and (LSecondRange <> nil) and
        DoSameBound(LFirstRange.LowExpr, LSecondRange.LowExpr, AOpaqueBySpelling) and
        DoSameBound(LFirstRange.HighExpr, LSecondRange.HighExpr, AOpaqueBySpelling));
    Exit(DoSameTypeAs(LFirstTarget, LSecondTarget, AOpaqueBySpelling));
  end;
  // Routine types: one signature (DoSignatureDiff: the meant linkage, F-R3b)
  if (LFirst is TPCRoutineType) and (LSecond is TPCRoutineType) then
    Exit(DoSameSignature(TPCRoutineType(LFirst).Signature(), TPCRoutineType(LSecond).Signature(), AOpaqueBySpelling));
  Result := False;
end;

function TPCSemantics.DoSignatureDiff(const AFirst: TPCSignature; const ASecond: TPCSignature;
  const AOpaqueBySpelling: Boolean; out AParam: Integer): TPCSignatureDiff;
var
  LIndex: Integer;
begin
  // The one signature rule (PLAN-RECORDS R5): two routine types, or a
  // routine value and a routine type, are one signature when the meant
  // linkage (M7 / F-R3b: no word = cpplink), varargs, the parameter count,
  // each parameter's mode and type and the result agree. The first
  // difference in this order is the note a mismatch carries; AParam = its
  // 0-based parameter (sdParamMode / sdParamType), else -1
  AParam := -1;
  if AFirst.Linkage <> ASecond.Linkage then
    Exit(sdLinkage);
  if AFirst.IsVariadic <> ASecond.IsVariadic then
    Exit(sdVariadic);
  if AFirst.Params.Count <> ASecond.Params.Count then
    Exit(sdCount);
  for LIndex := 0 to AFirst.Params.Count - 1 do
  begin
    AParam := LIndex;
    // A parameter the parser dropped never matches
    if (AFirst.Params[LIndex] = nil) or (ASecond.Params[LIndex] = nil) then
      Exit(sdParamType);
    if AFirst.Params[LIndex].ParamMode <> ASecond.Params[LIndex].ParamMode then
      Exit(sdParamMode);
    if not DoSameTypeAs(AFirst.Params[LIndex].TypeExpr, ASecond.Params[LIndex].TypeExpr, AOpaqueBySpelling) then
      Exit(sdParamType);
  end;
  AParam := -1;
  if (AFirst.ReturnType = nil) and (ASecond.ReturnType = nil) then
    Exit(sdSame);
  if (AFirst.ReturnType = nil) or (ASecond.ReturnType = nil) then
    Exit(sdReturn);
  if not DoSameTypeAs(AFirst.ReturnType, ASecond.ReturnType, AOpaqueBySpelling) then
    Exit(sdReturn);
  Result := sdSame;
end;

function TPCSemantics.DoSameSignature(const AFirst: TPCSignature; const ASecond: TPCSignature;
  const AOpaqueBySpelling: Boolean): Boolean;
var
  LParam: Integer;
begin
  Result := DoSignatureDiff(AFirst, ASecond, AOpaqueBySpelling, LParam) = sdSame;
end;

function TPCSemantics.DoFitsMantissa(const AMagnitude: UInt64; const ABits: Integer): Boolean;
var
  LValue: UInt64;
begin
  // An integer is exact in a binary float format when its significant bits,
  // after its trailing zero bits, fit the format's mantissa (24 / 53 bits)
  LValue := AMagnitude;
  while (LValue <> 0) and ((LValue and 1) = 0) do
    LValue := LValue shr 1;
  Result := LValue < (UInt64(1) shl ABits);
end;

function TPCSemantics.DoConstFits(const AValue: TPCExpr; const AToken: TPCTokenKind): Boolean;
var
  LNegative: Boolean;
  LMagnitude: UInt64;
  LBits: Integer;
  LIsUnsigned: Boolean;
begin
  // A folded integer as sign + magnitude; -(int64 min) does not fit Int64,
  // so the magnitude of a negative value is taken one step at a time
  if AValue.ConstIsUnsigned then
  begin
    LNegative := False;
    LMagnitude := AValue.ConstUInt;
  end
  else if AValue.ConstInt < 0 then
  begin
    LNegative := True;
    LMagnitude := UInt64(-(AValue.ConstInt + 1)) + 1;
  end
  else
  begin
    LNegative := False;
    LMagnitude := UInt64(AValue.ConstInt);
  end;
  if DoIntTypeInfo(AToken, LBits, LIsUnsigned) then
  begin
    if LIsUnsigned then
    begin
      if LNegative then
        Exit(False);
      if LBits = 64 then
        Exit(True);
      Exit(LMagnitude <= (UInt64(1) shl LBits) - 1);
    end;
    // Signed N bits: -2^(N-1) .. 2^(N-1) - 1
    if LNegative then
      Exit(LMagnitude <= UInt64(1) shl (LBits - 1));
    Exit(LMagnitude <= (UInt64(1) shl (LBits - 1)) - 1);
  end;
  if AToken = tkKwFloat32 then
    Exit(DoFitsMantissa(LMagnitude, 24));
  if AToken = tkKwFloat64 then
    Exit(DoFitsMantissa(LMagnitude, 53));
  Result := False;
end;

function TPCSemantics.DoFloatFitsSingle(const AValue: Double): Boolean;
var
  LSingle: Single;
begin
  // Q7: a float64 constant converts to float32 when float32 holds it
  // exactly. NaN never; an infinity is exact; a finite value past float32's
  // range is not (checked first: converting it would overflow)
  if IsNan(AValue) then
    Exit(False);
  if IsInfinite(AValue) then
    Exit(True);
  if Abs(AValue) > MaxSingle then
    Exit(False);
  LSingle := AValue;
  Result := Double(LSingle) = AValue;
end;

function TPCSemantics.DoUIntToDouble(const AValue: UInt64): Double;
begin
  // A UInt64 past Int64 is converted through its upper 63 bits, so no signed
  // conversion ever sees it; exact for every value the mantissa holds
  if AValue <= UInt64(High(Int64)) then
    Exit(Int64(AValue));
  Result := Int64(AValue shr 1);
  Result := Result * 2.0 + (AValue and 1);
end;

function TPCSemantics.DoConvertsImplicitly(const AValue: TPCExpr; const ATo: TPCTypeExpr): Boolean;
var
  LFit: TPCRoutine;
begin
  // A routine named as a value has no ResolvedType: its signature decides
  // (PLAN-RECORDS R5); every other value by its type
  if DoIsRoutineValue(AValue) then
    Exit(DoRoutineValueFit(AValue, ATo, LFit));
  Result := DoConvertsFrom(AValue.ResolvedType, AValue, ATo);
end;

function TPCSemantics.DoIsRoutineValue(const AValue: TPCExpr): Boolean;
var
  LRoutine: TPCRoutine;
begin
  // A routine or an overload set named as a value: SEM checks it against
  // the type it goes into (R5). A method keeps its path (PLAN-OBJECT)
  Result := TPCExpr.RoutineValueOf(AValue, LRoutine) in [rvRoutine, rvSet];
end;

procedure TPCSemantics.DoRoutinesOfValue(const AValue: TPCExpr; const ARoutines: TList<TPCRoutine>);
var
  LRoutine: TPCRoutine;
  LFound: TList<TPCNode>;
  LNode: TPCNode;
begin
  // The routines a routine value may be: its one routine, or every member
  // of its set in declaration order (the set a call by that name searches:
  // DoCalleeDecls, so a value and a call see the same members)
  ARoutines.Clear();
  case TPCExpr.RoutineValueOf(AValue, LRoutine) of
    rvRoutine:
      ARoutines.Add(LRoutine);
    rvSet:
      begin
        LFound := TList<TPCNode>.Create();
        try
          DoCalleeDecls(AValue, LFound);
          for LNode in LFound do
          begin
            if LNode is TPCRoutine then
              ARoutines.Add(TPCRoutine(LNode));
          end;
        finally
          LFound.Free();
        end;
      end;
  end;
end;

function TPCSemantics.DoRoutineValueFit(const AValue: TPCExpr; const ATo: TPCTypeExpr; out AFit: TPCRoutine): Boolean;
var
  LTo: TPCTypeExpr;
  LRoutines: TList<TPCRoutine>;
  LRoutine: TPCRoutine;
begin
  // R5 / D1: a routine value converts to a routine type of its signature
  // (DoSameSignature); an overload set to the one member that has it (SM0324
  // keeps two members from sharing one); to a C/C++ type always (clang's);
  // to anything else never. AFit = the routine that converts (nil: none, or
  // a C/C++ target)
  AFit := nil;
  if ATo = nil then
    Exit(False);
  LTo := ATo.Canon();
  if DoIsOpaqueTier(LTo) then
    Exit(True);
  if not (LTo is TPCRoutineType) then
    Exit(False);
  Result := False;
  LRoutines := TList<TPCRoutine>.Create();
  try
    DoRoutinesOfValue(AValue, LRoutines);
    for LRoutine in LRoutines do
    begin
      if DoSameSignature(LRoutine.Signature(), TPCRoutineType(LTo).Signature(), False) then
      begin
        AFit := LRoutine;
        Exit(True);
      end;
    end;
  finally
    LRoutines.Free();
  end;
end;

procedure TPCSemantics.DoBindRoutineValue(const AValue: TPCExpr; const ATo: TPCTypeExpr);
var
  LFit: TPCRoutine;
begin
  // An overload set accepted by a routine type is bound to the member it
  // converts to (ResolvedDecl; ResolvedSetMember stays: the emitter writes
  // the same name, clang takes the same member by the target's type).
  // Hover and definition then name that member
  if (TPCExpr.RoutineValueOf(AValue, LFit) <> rvSet) or not DoRoutineValueFit(AValue, ATo, LFit) or (LFit = nil) then
    Exit;
  if AValue is TPCName then
    TPCName(AValue).ResolvedDecl := LFit
  else if AValue is TPCMember then
    TPCMember(AValue).ResolvedDecl := LFit;
end;

procedure TPCSemantics.DoNoteRoutineValue(const AValue: TPCExpr; const ATo: TPCTypeExpr);
var
  LRoutines: TList<TPCRoutine>;
  LRoutine: TPCRoutine;
  LTo: TPCRoutineType;
  LTypeText: string;
  LParam: Integer;
  LNoteAt: TPCNode;
begin
  // The one note of a rejected routine value (R5): an overload set lists
  // every member (as SM0402); a lone routine names its first difference
  // from the routine type, at its declaration (a parameter's at that
  // parameter); a target that is no routine type gets none
  LRoutines := TList<TPCRoutine>.Create();
  try
    DoRoutinesOfValue(AValue, LRoutines);
    if LRoutines.Count > 1 then
    begin
      for LRoutine in LRoutines do
        DoNote(LRoutine, RSSemCallOverloadMember, [AValue.ExprText(), DoParamTypesText(DoRoutineTarget(LRoutine))]);
      Exit;
    end;
    if (LRoutines.Count = 0) or (ATo = nil) or not (ATo.Canon() is TPCRoutineType) then
      Exit;
    LRoutine := LRoutines[0];
    LTo := TPCRoutineType(ATo.Canon());
    LTypeText := ATo.TypeText();
    case DoSignatureDiff(LRoutine.Signature(), LTo.Signature(), False, LParam) of
      sdLinkage:
        begin
          if LRoutine.MeantLinkage() = lnC then
            DoNote(LRoutine, RSSemTypeRoutineClink, [LTypeText])
          else
            DoNote(LRoutine, RSSemTypeRoutineCpplink, [LTypeText]);
        end;
      sdVariadic:
        begin
          if LRoutine.IsVariadic then
            DoNote(LRoutine, RSSemTypeRoutineVariadic, [LTypeText])
          else
            DoNote(LRoutine, RSSemTypeRoutineNotVariadic, [LTypeText]);
        end;
      sdCount:
        DoNote(LRoutine, RSSemTypeRoutineCount, [LRoutine.Params.Count, LTo.Params.Count, LTypeText]);
      sdParamMode, sdParamType:
        begin
          LNoteAt := LRoutine.Params[LParam];
          if LNoteAt = nil then
            LNoteAt := LRoutine;
          DoNote(LNoteAt, RSSemTypeRoutineParam,
            [LParam + 1, DoParamText(LRoutine.Params[LParam]), DoParamText(LTo.Params[LParam]), LTypeText]);
        end;
      sdReturn:
        begin
          if LRoutine.ReturnType = nil then
            DoNote(LRoutine, RSSemTypeRoutineNoReturn, [LTo.ReturnType.TypeText(), LTypeText])
          else if LTo.ReturnType = nil then
            DoNote(LRoutine, RSSemTypeRoutineReturnNone, [LRoutine.ReturnType.TypeText(), LTypeText])
          else
            DoNote(LRoutine, RSSemTypeRoutineReturn,
              [LRoutine.ReturnType.TypeText(), LTo.ReturnType.TypeText(), LTypeText]);
        end;
    end;
  finally
    LRoutines.Free();
  end;
end;

function TPCSemantics.DoOwnerConverts(const AFrom: TPCOwnerType; const ATo: TPCOwnerType): Boolean;
var
  LFromTarget: TPCTypeExpr;
  LToTarget: TPCTypeExpr;
begin
  // PLAN-OBJECT O6 (D4): an owner converts to the same kind, an own to a ref
  // (it gives its object to the shared owners) and a ref to a weak (it
  // watches), holding the same object type or an ancestor of it. An own that
  // reaches an ancestor frees the object through the ancestor: only a
  // polymorphic one has the virtual done that frees all of it. A weak never
  // converts to a ref (lock(W) does, Q3)
  Result := False;
  if (AFrom.TargetType = nil) or (ATo.TargetType = nil) then
    Exit;
  if not ((AFrom.OwnerKind = ATo.OwnerKind) or ((AFrom.OwnerKind = okOwn) and (ATo.OwnerKind = okRef)) or
    ((AFrom.OwnerKind = okRef) and (ATo.OwnerKind = okWeak))) then
    Exit;
  LFromTarget := AFrom.TargetType.Canon();
  LToTarget := ATo.TargetType.Canon();
  if DoIsOpaqueTier(LFromTarget) or DoIsOpaqueTier(LToTarget) or DoSameType(LFromTarget, LToTarget) then
    Exit(True);
  if not TPCScopes.Derives(LFromTarget, LToTarget) then
    Exit;
  // O13b: an ancestor whose polymorphism is clang's passes; the emitted
  // check judges it (DoNoteCppPoly, pcOwnUpcast)
  if (AFrom.OwnerKind = okOwn) and (ATo.OwnerKind = okOwn) then
    Exit(TPCRecordType(LToTarget).ResolvedIsPolymorphic or TPCRecordType(LToTarget).PolymorphismIsClangs());
  Result := True;
end;

function TPCSemantics.DoConvertsFrom(const AFrom: TPCTypeExpr; const AValue: TPCExpr;
  const ATo: TPCTypeExpr): Boolean;
var
  LFrom: TPCTypeExpr;
  LTo: TPCTypeExpr;
  LFromTarget: TPCTypeExpr;
  LToTarget: TPCTypeExpr;
  LFromConst: Boolean;
  LToConst: Boolean;
  LFromToken: TPCTokenKind;
  LToToken: TPCTokenKind;
  LStringToken: TPCTokenKind;
  LCharToken: TPCTokenKind;
  LFromBits: Integer;
  LToBits: Integer;
  LFromUnsigned: Boolean;
  LToUnsigned: Boolean;
begin
  // semantics.md "Implicit conversion" [user: nothing hidden]: only when
  // every source value is exactly representable in the target
  // AValue (nil = a type alone, no constant) carries the folded value
  LFrom := AFrom.Canon();
  LTo := ATo.Canon();
  if DoIsOpaqueTier(LFrom) or DoIsOpaqueTier(LTo) then
    Exit(True);
  if DoSameType(LFrom, LTo) then
    Exit(True);
  // PLAN-RECORDS R4: a record extension converts to its base (the base part
  // is copied, or bound: the emitter's conversion operators, M10)
  if TPCScopes.Extends(LFrom, LTo) then
    Exit(True);
  // PLAN-OBJECT O5 / D6: a descendant object that is not polymorphic
  // converts to its ancestor by value (C++ copies its base part: nothing
  // dispatches, nothing is lost); a polymorphic one never does (SM0428,
  // DoCheckSlice)
  if TPCScopes.Derives(LFrom, LTo) and not TPCRecordType(LFrom).ResolvedIsPolymorphic then
    Exit(True);
  // A set literal -> any set whose element type holds every element
  if (AValue is TPCSetLiteral) and (LTo is TPCSetType) or
    ((AValue is TPCSetLiteral) and (LTo is TPCDerivedType) and (TPCDerivedType(LTo).DerivedKind = dkSetOf)) then
    Exit(DoSetLiteralFits(TPCSetLiteral(AValue), LTo));
  // nil -> every pointer and every routine type (user 2026-10-07), and every
  // own / ref / weak (PLAN-OBJECT O6: holds nothing)
  if LFrom is TPCNilType then
    Exit(TPCTypeExpr.PointerOf(LTo, LToTarget, LToConst) or (LTo is TPCRoutineType) or (LTo is TPCOwnerType));
  if (LFrom is TPCOwnerType) and (LTo is TPCOwnerType) then
    Exit(DoOwnerConverts(TPCOwnerType(LFrom), TPCOwnerType(LTo)));
  // A string literal -> string / ptr to const char; wide: wstring / ptr to const wchar
  if LFrom is TPCStringLiteralType then
  begin
    if TPCStringLiteralType(LFrom).IsWide then
    begin
      LStringToken := tkKwWstring;
      LCharToken := tkKwWchar;
    end
    else
    begin
      LStringToken := tkKwString;
      LCharToken := tkKwChar;
    end;
    if DoBuiltinOf(LTo, LToToken) then
      Exit(LToToken = LStringToken);
    Exit(TPCTypeExpr.PointerOf(LTo, LToTarget, LToConst) and LToConst and DoBuiltinOf(LToTarget, LToToken) and
      (LToToken = LCharToken));
  end;
  // Pointers: a typed one -> the untyped ptr, and const added to the same
  // target or a base record's (R4); const is never dropped (C++ rejects it:
  // clang would report it)
  if TPCTypeExpr.PointerOf(LFrom, LFromTarget, LFromConst) and TPCTypeExpr.PointerOf(LTo, LToTarget, LToConst) then
  begin
    if LFromConst and not LToConst then
      Exit(False);
    if LToTarget = nil then
      Exit(True);
    // ... and a pointer to a record extension to a pointer to its base (R4;
    // one level of pointer only: ptr to ptr to TExt stays its own type), or
    // to a descendant object to a pointer to its ancestor (PLAN-OBJECT D6:
    // C++ converts it, the object keeps its dynamic type)
    Exit((LFromTarget <> nil) and (DoSameType(LFromTarget, LToTarget) or
      TPCScopes.Extends(LFromTarget, LToTarget) or TPCScopes.Derives(LFromTarget, LToTarget)));
  end;
  if not DoBuiltinOf(LFrom, LFromToken) or not DoBuiltinOf(LTo, LToToken) then
    Exit(False);
  if DoIntTypeInfo(LFromToken, LFromBits, LFromUnsigned) then
  begin
    // A folded integer constant -> any numeric type that holds it exactly
    if (AValue <> nil) and AValue.HasConstValue and DoConstFits(AValue, LToToken) then
      Exit(True);
    if DoIntTypeInfo(LToToken, LToBits, LToUnsigned) then
    begin
      // The same signedness widens; unsigned -> a wider signed; signed -> unsigned never
      if LFromUnsigned = LToUnsigned then
        Exit(LToBits >= LFromBits);
      Exit(LFromUnsigned and (LToBits > LFromBits));
    end;
    if LToToken = tkKwFloat32 then
      Exit(LFromBits <= 16);
    if LToToken = tkKwFloat64 then
      Exit(LFromBits <= 32);
    Exit(False);
  end;
  // A folded float64 constant -> float32 when float32 holds it exactly (Q7);
  // a float never converts to an integer (user 2026-10-07: always a cast)
  if LFromToken = tkKwFloat64 then
    Exit((AValue <> nil) and AValue.HasConstFloat and (LToToken = tkKwFloat32) and DoFloatFitsSingle(AValue.ConstFloat));
  Result := (LFromToken = tkKwFloat32) and (LToToken = tkKwFloat64);
end;

function TPCSemantics.DoCastClass(const AType: TPCTypeExpr; out ABits: Integer): TPCCastClass;
var
  LToken: TPCTokenKind;
  LIsUnsigned: Boolean;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
begin
  ABits := 0;
  if DoBuiltinOf(AType, LToken) then
  begin
    if DoIntTypeInfo(LToken, ABits, LIsUnsigned) then
      Exit(ccInteger);
    if (LToken = tkKwFloat32) or (LToken = tkKwFloat64) then
      Exit(ccFloat);
    if (LToken = tkKwChar) or (LToken = tkKwWchar) or (LToken = tkKwBool) then
      Exit(ccOrdinal);
    if (LToken = tkKwString) or (LToken = tkKwWstring) then
      Exit(ccString);
    Exit(ccNone);
  end;
  if (AType <> nil) and (AType.Canon() is TPCChoicesType) then
    Exit(ccChoices);
  if TPCTypeExpr.PointerOf(AType, LTarget, LIsConst) then
    Exit(ccPointer);
  Result := ccNone;
end;

function TPCSemantics.DoIsPrimary(const AExpr: TPCExpr): Boolean;
begin
  // An operand a postfix or a C-style cast takes without parentheses
  Result := (AExpr is TPCName) or (AExpr is TPCMember) or (AExpr is TPCLiteral) or
    (AExpr is TPCCall) or (AExpr is TPCSpecial) or (AExpr is TPCVerbatimExpr);
end;

function TPCSemantics.DoCastHint(const AValue: TPCExpr; const ATo: TPCTypeExpr; out AHint: string): Boolean;
var
  LFromClass: TPCCastClass;
  LToClass: TPCCastClass;
  LFromBits: Integer;
  LToBits: Integer;
  LToCanon: TPCTypeExpr;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
  LFromToken: TPCTokenKind;
  LToken: TPCTokenKind;
  LText: string;
  LOperand: string;
  LPointerBits: Integer;
begin
  // The cast the SM0200 message names: only a cast PaskalCPP checks
  // (semantics.md casts row: numeric <-> numeric, char / bool / choices <->
  // integer, pointer <-> pointer / an integer of pointer width), and
  // LS.c_str() for a string into a char pointer. A builtin or pointer cast is
  // spelled with the target's Canon (an alias is no cast word), a choices
  // cast C-style with the user's named type. False = no cast expresses it
  AHint := '';
  LFromClass := DoCastClass(AValue.ResolvedType, LFromBits);
  LToClass := DoCastClass(ATo, LToBits);
  LToCanon := ATo.Canon();
  LText := AValue.ExprText();
  if DoIsPrimary(AValue) then
    LOperand := LText
  else
    LOperand := '(' + LText + ')';
  LPointerBits := DoModelTarget().PointerBits();
  Result := False;
  case LToClass of
    ccInteger:
      Result := (LFromClass in [ccInteger, ccFloat, ccOrdinal, ccChoices]) or
        ((LFromClass = ccPointer) and (LToBits = LPointerBits));
    ccFloat:
      Result := LFromClass in [ccInteger, ccFloat];
    ccOrdinal:
      Result := LFromClass = ccInteger;
    ccChoices:
      begin
        // An anonymous choices type has no name to cast to
        Result := (LFromClass = ccInteger) and (ATo is TPCNamedType);
        if Result then
          AHint := '(' + ATo.TypeText() + ')' + LOperand;
        Exit;
      end;
    ccPointer:
      begin
        if LFromClass = ccString then
        begin
          // string / wstring into ptr to const char / wchar
          DoBuiltinOf(AValue.ResolvedType, LFromToken);
          Result := TPCTypeExpr.PointerOf(LToCanon, LTarget, LIsConst) and LIsConst and DoBuiltinOf(LTarget, LToken) and
            (((LFromToken = tkKwString) and (LToken = tkKwChar)) or
            ((LFromToken = tkKwWstring) and (LToken = tkKwWchar)));
          if Result then
            AHint := LOperand + '.c_str()';
          Exit;
        end;
        // Only a cast the pointer cast takes is named (one rule, the cast's
        // own check: a hint that drops const led to clang's "casts away
        // qualifiers", type_pointer F48)
        Result := DoPointerCastTakes(AValue.ResolvedType, ATo);
      end;
  end;
  if Result then
    AHint := LToCanon.TypeText() + '(' + LText + ')';
end;

function TPCSemantics.DoPointerCastTakes(const AFromType: TPCTypeExpr; const ATo: TPCTypeExpr): Boolean;
var
  LFromClass: TPCCastClass;
  LFromBits: Integer;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
  LFromTarget: TPCTypeExpr;
  LFromConst: Boolean;
begin
  // The one pointer-cast rule (BNF.md sec 6 pointer cast, F48): ptr to T(x)
  // takes a pointer that keeps const (typed or untyped) or an integer of
  // pointer width (semantics.md casts row); nothing else, nil included (it
  // is nullptr and converts with no cast). The emitter writes the cast as a
  // reinterpret_cast / static_cast, which C++ refuses for a const drop.
  // Asked by the cast's own check (DoCast) and by the SM0200 hint (DoCastHint)
  Result := False;
  if (AFromType = nil) or (ATo = nil) then
    Exit;
  if not TPCTypeExpr.PointerOf(ATo.Canon(), LTarget, LIsConst) or (LTarget = nil) then
    Exit;
  LFromClass := DoCastClass(AFromType, LFromBits);
  if LFromClass = ccPointer then
  begin
    TPCTypeExpr.PointerOf(AFromType, LFromTarget, LFromConst);
    Exit(LIsConst or not LFromConst);
  end;
  Result := (LFromClass = ccInteger) and (LFromBits = DoModelTarget().PointerBits());
end;

function TPCSemantics.DoConstNotFit(const AValue: TPCExpr; const ATo: TPCTypeExpr; out AValueText: string;
  out ALowText: string; out AHighText: string): Boolean;
var
  LFromToken: TPCTokenKind;
  LToToken: TPCTokenKind;
  LBits: Integer;
  LIsUnsigned: Boolean;
begin
  // A folded integer constant into an integer type that cannot hold it
  // (user 2026-10-11): the message is the value and the type's range. A
  // cast hint would be wrong advice: int8(300) is not 300. Result False =
  // not this case (the caller reports the plain conversion error)
  Result := False;
  AValueText := '';
  ALowText := '';
  AHighText := '';
  if (AValue = nil) or (not AValue.HasConstValue) or (AValue.ResolvedType = nil) or (ATo = nil) then
    Exit;
  if (not DoBuiltinOf(AValue.ResolvedType.Canon(), LFromToken)) or
     (not DoIntTypeInfo(LFromToken, LBits, LIsUnsigned)) then
    Exit;
  if (not DoBuiltinOf(ATo.Canon(), LToToken)) or (not DoIntTypeInfo(LToToken, LBits, LIsUnsigned)) then
    Exit;
  if DoConstFits(AValue, LToToken) then
    Exit;

  // The value as folded (sign + digits)
  if AValue.ConstIsUnsigned then
    AValueText := UIntToStr(AValue.ConstUInt)
  else
    AValueText := IntToStr(AValue.ConstInt);

  // The target's range: unsigned 0 .. 2^N - 1, signed -2^(N-1) .. 2^(N-1) - 1
  if LIsUnsigned then
  begin
    ALowText := '0';
    if LBits = 64 then
      AHighText := UIntToStr(High(UInt64))
    else
      AHighText := UIntToStr((UInt64(1) shl LBits) - 1);
  end
  else if LBits = 64 then
  begin
    ALowText := IntToStr(Low(Int64));
    AHighText := IntToStr(High(Int64));
  end
  else
  begin
    ALowText := '-' + UIntToStr(UInt64(1) shl (LBits - 1));
    AHighText := UIntToStr((UInt64(1) shl (LBits - 1)) - 1);
  end;
  Result := True;
end;

procedure TPCSemantics.DoCheckConvert(const AValue: TPCExpr; const ATo: TPCTypeExpr);
var
  LHint: string;
  LValueText: string;
  LLowText: string;
  LHighText: string;
  LRoutine: TPCRoutine;
  LReported: Boolean;
begin
  // The one implicit-conversion check (SM0200): a value into a declared
  // type. Nothing to check: no value, a reported value or type (C1), or a
  // value its typing area has not typed (an operator before TYPES-B). A type
  // or module name is no value at all (SM0269)
  // A routine value is typed by its signature (R5).
  if DoNotValue(AValue) then
    Exit;
  if (AValue = nil) or ((AValue.ResolvedType = nil) and not DoIsRoutineValue(AValue)) or DoIsPoisoned(AValue) or
    DoIsErrorType(ATo) then
    Exit;
  if DoConvertsImplicitly(AValue, ATo) then
  begin
    // PLAN-RECORDS M12 (1): an accepted pointer upcast is written by the emitter
    DoNoteUpcast(AValue, ATo);
    DoBindRoutineValue(AValue, ATo);
    // PLAN-OBJECT O5 / D5: a value position copies an lvalue
    DoCheckCopy(AValue, ATo);
    Exit;
  end;
  // D6: a polymorphic object by value to its base (SM0428, not SM0200)
  if DoCheckSlice(AValue, ATo) then
    Exit;
  // R5 / D1: a routine value into a type it does not convert to (no
  // ResolvedType: the routine's signature is printed), one note
  if DoIsRoutineValue(AValue) then
  begin
    if TPCExpr.RoutineValueOf(AValue, LRoutine) = rvSet then
      LReported := DoError(AValue, PC_ERR_SEM_200, RSSemTypeSetNoMember, [AValue.ExprText(), ATo.TypeText()])
    else
      LReported := DoError(AValue, PC_ERR_SEM_200, RSSemTypeNoConvert, [LRoutine.Signature().Text(), ATo.TypeText()]);
    if LReported then
      DoNoteRoutineValue(AValue, ATo);
    DoPoison(AValue);
    Exit;
  end;
  if DoConstNotFit(AValue, ATo, LValueText, LLowText, LHighText) then
    DoError(AValue, PC_ERR_SEM_200, RSSemTypeNotFit, [LValueText, ATo.TypeText(), LLowText, LHighText])
  else if DoCastHint(AValue, ATo, LHint) then
    DoError(AValue, PC_ERR_SEM_200, RSSemTypeNoConvertCast,
      [AValue.ResolvedType.TypeText(), ATo.TypeText(), LHint])
  else
    DoError(AValue, PC_ERR_SEM_200, RSSemTypeNoConvert, [AValue.ResolvedType.TypeText(), ATo.TypeText()]);
  DoPoison(AValue);
end;

function TPCSemantics.DoCheckConstant(const AExpr: TPCExpr; const APosition: string): Boolean;
var
  LIsCpp: Boolean;
begin
  // The one constant check (SM0202, folding.md "Positions"): a position that
  // takes a constant takes a PaskalCPP constant (a literal, a const, a choice
  // value, an expression of those) or opaque C++ (clang judges it). True =
  // PaskalCPP knows the value; PaskalCPP computes no value C++ computes
  Result := (AExpr <> nil) and (AExpr.HasConstValue or AExpr.HasConstFloat);
  if Result or (AExpr = nil) or (AExpr.ResolvedType = nil) or DoIsPoisoned(AExpr) then
    Exit;
  if AExpr.IsConstExpr then
    Exit;
  // Opaque C++ standing alone (a C++ name, call or verbatim) is clang's; an
  // operator node or a PaskalCPP variable is PaskalCPP's even when opaque
  LIsCpp := DoIsOpaqueTier(AExpr.ResolvedType) and not ((AExpr is TPCBinary) or (AExpr is TPCUnary) or
    (AExpr is TPCTernary) or (AExpr is TPCCast));
  if LIsCpp and (AExpr is TPCName) and (TPCName(AExpr).ResolvedKind in [rkVar, rkParam, rkField]) then
    LIsCpp := False;
  if LIsCpp then
    Exit;
  DoError(AExpr, PC_ERR_SEM_202, RSSemTypeNotConstant, [APosition]);
  DoPoison(AExpr);
end;

procedure TPCSemantics.DoConstLeaf(const AExpr: TPCExpr; const ADecl: TPCConstDecl);
var
  LValue: TPCExpr;
  LToken: TPCTokenKind;
  LBits: Integer;
  LIsUnsigned: Boolean;
begin
  // A const is a constant; its folded value is CONVERTED to its declared
  // type (folding.md "Leaves"): the value passed the exact conversion check
  // (SM0200 at the declaration), so only its form changes
  AExpr.IsConstExpr := True;
  LValue := ADecl.ValueExpr;
  if (LValue = nil) or DoIsPoisoned(LValue) or (AExpr.ResolvedType = nil) or DoIsPoisoned(AExpr) or
    DoIsOpaqueTier(AExpr.ResolvedType) then
    Exit;
  if DoBuiltinOf(AExpr.ResolvedType, LToken) and DoIntTypeInfo(LToken, LBits, LIsUnsigned) then
  begin
    if not LValue.HasConstValue then
      Exit;
    AExpr.HasConstValue := True;
    AExpr.ConstIsUnsigned := LIsUnsigned;
    if LIsUnsigned and LValue.ConstIsUnsigned then
      AExpr.ConstUInt := LValue.ConstUInt
    else if LIsUnsigned then
      AExpr.ConstUInt := UInt64(LValue.ConstInt)
    else if LValue.ConstIsUnsigned then
      AExpr.ConstInt := Int64(LValue.ConstUInt)
    else
      AExpr.ConstInt := LValue.ConstInt;
    Exit;
  end;
  if (LToken = tkKwFloat32) or (LToken = tkKwFloat64) then
  begin
    // A float const: its float value, or the integer constant it converted
    if LValue.HasConstFloat then
      AExpr.ConstFloat := LValue.ConstFloat
    else if LValue.HasConstValue and LValue.ConstIsUnsigned then
      AExpr.ConstFloat := DoUIntToDouble(LValue.ConstUInt)
    else if LValue.HasConstValue then
      AExpr.ConstFloat := LValue.ConstInt
    else
      Exit;
    AExpr.HasConstFloat := True;
    Exit;
  end;
  // bool, char, wchar, a choices type: a value of the same type, copied
  if LValue.HasConstValue then
  begin
    AExpr.HasConstValue := True;
    AExpr.ConstIsUnsigned := LValue.ConstIsUnsigned;
    AExpr.ConstInt := LValue.ConstInt;
    AExpr.ConstUInt := LValue.ConstUInt;
  end;
end;

procedure TPCSemantics.DoChoiceLeaf(const AExpr: TPCExpr; const AValue: TPCChoiceValue);
begin
  // A choice value is a constant; its value is its ordinal once DECLS has
  // numbered it (folding.md "Leaves": rkChoiceValue)
  AExpr.IsConstExpr := True;
  if DoIsPoisoned(AExpr) or not AValue.HasResolvedOrdinal then
    Exit;
  AExpr.HasConstValue := True;
  AExpr.ConstIsUnsigned := False;
  AExpr.ConstInt := AValue.ResolvedOrdinal;
end;

const
  { PC_SEM_BINARY_TEXT }
  // The PaskalCPP spelling a message gives each binary operator
  PC_SEM_BINARY_TEXT: array[TPCBinaryOp] of string = (
    'or', 'and', '=', '<>', '<', '>', '<=', '>=', '<=>', 'in', '+', '-', '|',
    'xor', 'shl', 'shr', '*', '/', 'div', 'mod', '&'
  );

  { PC_SEM_UNARY_TEXT }
  // The PaskalCPP spelling a message gives each unary operator
  PC_SEM_UNARY_TEXT: array[TPCUnaryOp] of string = (
    'not', '~', '-', '+', 'address of', '^', '++', '--', '++', '--'
  );

function TPCSemantics.DoTokenOf(const AExpr: TPCExpr; out AToken: TPCTokenKind): Boolean;
begin
  AToken := tkUnknown;
  if AExpr = nil then
    Exit(False);
  Result := DoBuiltinOf(AExpr.ResolvedType, AToken);
end;

function TPCSemantics.DoIsIntegerToken(const AToken: TPCTokenKind): Boolean;
var
  LBits: Integer;
  LIsUnsigned: Boolean;
begin
  Result := DoIntTypeInfo(AToken, LBits, LIsUnsigned);
end;

function TPCSemantics.DoStringWidth(const AExpr: TPCExpr): Integer;
var
  LToken: TPCTokenKind;
  LCanon: TPCTypeExpr;
begin
  // 1 narrow string, 2 wide string, 3 char, 4 wchar, 0 none of the string family
  Result := 0;
  if (AExpr = nil) or (AExpr.ResolvedType = nil) then
    Exit;
  LCanon := AExpr.ResolvedType.Canon();
  if LCanon is TPCStringLiteralType then
  begin
    if TPCStringLiteralType(LCanon).IsWide then
      Exit(2);
    Exit(1);
  end;
  if not DoTokenOf(AExpr, LToken) then
    Exit;
  if LToken = tkKwString then
    Result := 1
  else if LToken = tkKwWstring then
    Result := 2
  else if LToken = tkKwChar then
    Result := 3
  else if LToken = tkKwWchar then
    Result := 4;
end;

function TPCSemantics.DoNotValue(const AExpr: TPCExpr): Boolean;
var
  LKind: TPCResolvedKind;
  LRoutine: TPCRoutine;
begin
  // SM0269, its one reporter (the owner D-A3a-5 named): a name or member that
  // names a type or a module stands where a value is consumed (an operand,
  // :=, an initializer, a condition). Reported once and poisoned (C1). A
  // callee, a cast, a member base and an intrinsic's type argument are not
  // value positions: they never ask
  Result := False;
  if (AExpr = nil) or DoIsPoisoned(AExpr) then
    Exit;
  // SM0408, its one reporter: a statement-only intrinsic (typed void by
  // DoIntrinsic) where a value is consumed
  if (AExpr is TPCCall) and (TPCCall(AExpr).ResolvedKind = rkIntrinsic) and
    (AExpr.ResolvedType is TPCVoidType) then
  begin
    DoError(AExpr, PC_ERR_SEM_408, RSSemCallIntrinsicStmt, [PC_INTRINSIC_NAMES[TPCCall(AExpr).IntrinsicKind]]);
    DoPoison(AExpr);
    Exit(True);
  end;
  // SM0406, its one reporter: a procedure call (typed void by DoBindTarget)
  // where a value is consumed
  if (AExpr is TPCCall) and (AExpr.ResolvedType is TPCVoidType) then
  begin
    DoError(AExpr, PC_ERR_SEM_406, RSSemCallNoValue, [AExpr.ExprText()]);
    DoPoison(AExpr);
    Exit(True);
  end;
  // SM0409: a varargs local's call word not called (L.next): the member's
  // shape, as L.next() is told (DoVarargsLocalCall); left alone it reaches
  // clang as a C++ member function name
  if (AExpr is TPCMember) and (TPCMember(AExpr).ResolvedVarargs in [vaNext, vaGet, vaReset, vaCopy]) then
  begin
    if TPCMember(AExpr).ResolvedVarargs = vaNext then
      DoError(AExpr, PC_ERR_SEM_409, RSSemCallIntrinsicSig, [AExpr.ExprText(), RSAstSigType])
    else if TPCMember(AExpr).ResolvedVarargs = vaGet then
      DoError(AExpr, PC_ERR_SEM_409, RSSemCallIntrinsicSig, [AExpr.ExprText(), RSAstSigIndexType])
    else
      DoError(AExpr, PC_ERR_SEM_409, RSSemCallIntrinsicSig, [AExpr.ExprText(), RSAstSigNone]);
    DoPoison(AExpr);
    Exit(True);
  end;
  // SM0432, its one reporter (PLAN-OBJECT O13, F-A5a): a method named where
  // a value is consumed (LO.M, parent.M, a method set). A routine type holds
  // a plain routine's address, and a method runs on its object, so it has no
  // routine value; left alone it reaches clang as a C++ member function name
  // that is not called. print / println keep SM0425 (they never ask)
  if TPCExpr.RoutineValueOf(AExpr, LRoutine) = rvMethod then
  begin
    DoError(AExpr, PC_ERR_SEM_432, RSSemCallMethodValue, [AExpr.ExprText()]);
    DoPoison(AExpr);
    Exit(True);
  end;
  if AExpr is TPCName then
    LKind := TPCName(AExpr).ResolvedKind
  else if AExpr is TPCMember then
    LKind := TPCMember(AExpr).ResolvedKind
  else
    Exit;
  if LKind = rkType then
    DoError(AExpr, PC_ERR_SEM_269, RSSemTypeNotValue, [AExpr.ExprText()])
  else if LKind = rkModule then
    DoError(AExpr, PC_ERR_SEM_269, RSSemTypeModuleNotValue, [AExpr.ExprText()])
  // SM0423, its one reporter: an intrinsic name not called (no C++ entity
  // of that name is emitted, so clang would report it, not PaskalCPP)
  else if LKind = rkIntrinsic then
    DoError(AExpr, PC_ERR_SEM_423, RSSemCallIntrinsicNotCalled, [AExpr.ExprText()])
  else
    Exit;
  DoPoison(AExpr);
  Result := True;
end;

function TPCSemantics.DoOperandsReady(const ANode: TPCExpr; const AOperands: array of TPCExpr): Boolean;
var
  LOperand: TPCExpr;
  LOther: TPCExpr;
begin
  // True = every operand is a typed PaskalCPP value. A type or module name is
  // SM0269; a dropped or reported operand poisons the node silently (C1); an
  // operand no area typed yet leaves the node untyped (D-A3b-1); an opaque
  // one makes the node clang's: opaque, and a constant when every other
  // operand is one (clang judges the opaque side's constness too)
  for LOperand in AOperands do
  begin
    if DoNotValue(LOperand) then
    begin
      DoPoison(ANode);
      Exit(False);
    end;
  end;
  for LOperand in AOperands do
  begin
    if (LOperand = nil) or DoIsPoisoned(LOperand) then
    begin
      DoPoison(ANode);
      Exit(False);
    end;
  end;
  for LOperand in AOperands do
  begin
    if LOperand.ResolvedType = nil then
      Exit(False);
  end;
  for LOperand in AOperands do
  begin
    if DoIsErrorType(LOperand.ResolvedType) then
    begin
      DoPoison(ANode);
      Exit(False);
    end;
  end;
  for LOperand in AOperands do
  begin
    if DoIsOpaqueTier(LOperand.ResolvedType) then
    begin
      ANode.ResolvedType := FAst.OpaqueType();
      ANode.IsConstExpr := True;
      for LOther in AOperands do
      begin
        if not (LOther.IsConstExpr or DoIsOpaqueTier(LOther.ResolvedType)) then
          ANode.IsConstExpr := False;
      end;
      Exit(False);
    end;
  end;
  Result := True;
end;

procedure TPCSemantics.DoReportOperands(const ANode: TPCExpr; const AOpText: string; const ALeft: TPCExpr;
  const ARight: TPCExpr);
begin
  if ARight = nil then
    DoError(ANode, PC_ERR_SEM_250, RSSemTypeOpOne, [AOpText, ALeft.ResolvedType.TypeText()])
  else
    DoError(ANode, PC_ERR_SEM_250, RSSemTypeOpTwo,
      [AOpText, ALeft.ResolvedType.TypeText(), ARight.ResolvedType.TypeText()]);
  DoPoison(ANode);
end;

function TPCSemantics.DoIsUncomparable(const AType: TPCTypeExpr): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // SM0252 (user 2026-10-13): a record or an overlay has no
  // comparison; an array compares element by element, so an array (static or
  // dynamic, nested too) of records or overlays has none either. A C/C++ type
  // is clang's (opaque, never reaches here).
  // PLAN-OBJECT H4 (O15): an object compares only through an operator its
  // type declares, as a record does (DoDeclaredOperator runs before the
  // built-in rules, so a declared one never reaches here). A record or an
  // object whose chain reaches a C/C++ parent may compare through that C++
  // base's operators: clang's (F20, a C/C++ parent's members are clang's)
  Result := False;
  if AType = nil then
    Exit;
  LCanon := AType.Canon();
  if LCanon is TPCArrayType then
    Exit(DoIsUncomparable(TPCArrayType(LCanon).ElementType));
  if LCanon is TPCOverlayType then
    Exit(True);
  if LCanon is TPCRecordType then
    Exit(not TPCScopes.ReachesOpaque(LCanon));
end;

function TPCSemantics.DoCheckComparable(const ANode: TPCExpr; const AOpText: string; const ALeft: TPCExpr;
  const ARight: TPCExpr): Boolean;
var
  LOperand: TPCExpr;
  LLeaf: TPCTypeExpr;
begin
  // SM0252 at the operator, naming the first operand that has no comparison;
  // False = reported, ANode poisoned
  LOperand := nil;
  if DoIsUncomparable(ALeft.ResolvedType) then
    LOperand := ALeft
  else if DoIsUncomparable(ARight.ResolvedType) then
    LOperand := ARight;
  if LOperand = nil then
    Exit(True);
  // The text names what has no comparison: an object (or an array of them)
  // compares through an operator its type declares (O15), a record or an
  // overlay through its fields
  LLeaf := LOperand.ResolvedType.Canon();
  while LLeaf is TPCArrayType do
    LLeaf := TPCArrayType(LLeaf).ElementType.Canon();
  if (LLeaf is TPCRecordType) and TPCRecordType(LLeaf).IsObject then
    DoError(ANode, PC_ERR_SEM_252, RSSemTypeObjectNotComparable, [AOpText, LOperand.ResolvedType.TypeText()])
  else
    DoError(ANode, PC_ERR_SEM_252, RSSemTypeNotComparable, [AOpText, LOperand.ResolvedType.TypeText()]);
  DoPoison(ANode);
  Result := False;
end;

function TPCSemantics.DoBinaryType(const ANode: TPCExpr; const AOp: TPCBinaryOp; const ALeft: TPCExpr;
  const ARight: TPCExpr): TPCTypeExpr;
var
  LLeftToken: TPCTokenKind;
  LRightToken: TPCTokenKind;
  LHasTokens: Boolean;
  LLeftRange: TPCSetType;
  LRightRange: TPCSetType;
  LLeftElement: TPCTypeExpr;
  LRightElement: TPCTypeExpr;
  LLeftSet: Boolean;
  LRightSet: Boolean;
  LLeftWidth: Integer;
  LRightWidth: Integer;
  LLeftString: Boolean;
  LRightString: Boolean;
  LTakes: Boolean;
  LNumeric: TPCTokenKind;
begin
  // PaskalCPP's own operator meanings, on PaskalCPP-typed operands (neither
  // is opaque: DoOperandsReady). PLAN-ARITH A1: an arithmetic / bitwise /
  // shift operator on two PaskalCPP numeric operands has the type C++ gives
  // it (DoNumericResult), so the conversion check judges where it goes (BNF
  // 6 "No hidden conversions"); any other operand pair keeps C++'s typing
  // (opaque, clang's). A comparison is bool; two folded PaskalCPP constants
  // then fold in the same result type (DoFoldBinary, F27). nil = reported,
  // ANode poisoned
  Result := nil;
  // F40: a choice value has no arithmetic: only a comparison and in take one
  // (inside its own list a value is its int32 number, not of the type). It
  // reached clang as "invalid operands" in C++ words
  if (not (AOp in [boEq, boNotEq, boLess, boGreater, boLessEq, boGreaterEq, boThreeWay, boIn])) and
    (((ALeft.ResolvedType <> nil) and (ALeft.ResolvedType.Canon() is TPCChoicesType)) or
    ((ARight.ResolvedType <> nil) and (ARight.ResolvedType.Canon() is TPCChoicesType))) then
  begin
    DoReportOperands(ANode, PC_SEM_BINARY_TEXT[AOp], ALeft, ARight);
    Exit;
  end;
  // F55 (DESIGN sec 5): a string / wstring value has PaskalCPP meanings only:
  // a comparison with the string family of its width (a string or a string
  // literal), + of the string family of one width (concatenation, below) and
  // in (DoInType judges it). Any other operator or operand reached clang as
  // "invalid operands" in C++ words. A string literal on its own stays as it
  // was (beside a C pointer it is C++'s comparison)
  LLeftWidth := DoStringWidth(ALeft);
  LRightWidth := DoStringWidth(ARight);
  LLeftString := DoTokenOf(ALeft, LLeftToken) and ((LLeftToken = tkKwString) or (LLeftToken = tkKwWstring));
  LRightString := DoTokenOf(ARight, LRightToken) and ((LRightToken = tkKwString) or (LRightToken = tkKwWstring));
  if LLeftString or LRightString then
  begin
    if AOp in [boEq, boNotEq, boLess, boGreater, boLessEq, boGreaterEq, boThreeWay] then
      LTakes := (LLeftWidth in [1, 2]) and (LLeftWidth = LRightWidth)
    else if AOp = boAdd then
      LTakes := (LLeftWidth <> 0) and (LRightWidth <> 0) and
        (((LLeftWidth - 1) mod 2) = ((LRightWidth - 1) mod 2))
    else
      LTakes := AOp = boIn;
    if not LTakes then
    begin
      DoReportOperands(ANode, PC_SEM_BINARY_TEXT[AOp], ALeft, ARight);
      Exit;
    end;
  end;
  LHasTokens := DoTokenOf(ALeft, LLeftToken) and DoTokenOf(ARight, LRightToken);
  LLeftSet := DoSetOf(ALeft.ResolvedType, LLeftRange, LLeftElement);
  LRightSet := DoSetOf(ARight.ResolvedType, LRightRange, LRightElement);
  case AOp of
    boLogOr, boLogAnd:
      begin
        // or / and are logical: bool operands only
        if LHasTokens and (LLeftToken = tkKwBool) and (LRightToken = tkKwBool) then
          Exit(FAst.BuiltinType(tkKwBool));
      end;
    boBitXor:
      begin
        // xor: logical on two bools, C++'s ^ on two integers
        if LHasTokens and (LLeftToken = tkKwBool) and (LRightToken = tkKwBool) then
          Exit(FAst.BuiltinType(tkKwBool));
        if LHasTokens and DoIsIntegerToken(LLeftToken) and DoIsIntegerToken(LRightToken) and
          DoNumericResult(AOp, LLeftToken, LRightToken, LNumeric) then
          Exit(DoArithResult(ANode, AOp, ALeft, ARight, LNumeric));
      end;
    boEq, boNotEq, boLess, boGreater, boLessEq, boGreaterEq:
      begin
        // SM0252: records / overlays (and arrays of them) do not compare
        if not DoCheckComparable(ANode, PC_SEM_BINARY_TEXT[AOp], ALeft, ARight) then
          Exit(nil);
        // PLAN-ARITH A2: two numbers compare in their common type, each
        // converting to it (int32 < uint32 compared as unsigned: -1 < 1u
        // was silently false)
        if LHasTokens and DoNumericResult(boAdd, LLeftToken, LRightToken, LNumeric) and
          (DoArithResult(ANode, boAdd, ALeft, ARight, LNumeric) = nil) then
          Exit(nil);
        // PLAN-RECORDS F-A4c: an extension pointer compared with its base's
        DoNoteComparedUpcast(ALeft, ARight);
        Exit(FAst.BuiltinType(tkKwBool));
      end;
    boThreeWay:
      begin
        if not DoCheckComparable(ANode, PC_SEM_BINARY_TEXT[AOp], ALeft, ARight) then
          Exit(nil);
        if LHasTokens and DoNumericResult(boAdd, LLeftToken, LRightToken, LNumeric) and
          (DoArithResult(ANode, boAdd, ALeft, ARight, LNumeric) = nil) then
          Exit(nil);
        DoNoteComparedUpcast(ALeft, ARight);
        Exit(FAst.OpaqueType());
      end;
    boIn:
      Exit(DoInType(ANode, ALeft, ARight));
    boAdd, boSub, boMul:
      begin
        if LLeftSet or LRightSet then
        begin
          // Union / difference / intersection: two sets of one type; a set
          // literal takes the other operand's set type when it fits it
          if LLeftSet and LRightSet then
          begin
            if DoSameType(ALeft.ResolvedType, ARight.ResolvedType) then
              Exit(ALeft.ResolvedType);
            if (ARight is TPCSetLiteral) and DoSetLiteralFits(TPCSetLiteral(ARight), ALeft.ResolvedType) then
              Exit(ALeft.ResolvedType);
            if (ALeft is TPCSetLiteral) and DoSetLiteralFits(TPCSetLiteral(ALeft), ARight.ResolvedType) then
              Exit(ARight.ResolvedType);
          end;
        end
        else
        begin
          // String concatenation of one width keeps its string type (a value
          // PaskalCPP converts); every other pair is C++ arithmetic
          LLeftWidth := DoStringWidth(ALeft);
          LRightWidth := DoStringWidth(ARight);
          if (AOp = boAdd) and ((LLeftWidth in [1, 2]) or (LRightWidth in [1, 2])) and (LLeftWidth <> 0) and
            (LRightWidth <> 0) and (((LLeftWidth - 1) mod 2) = ((LRightWidth - 1) mod 2)) then
          begin
            if ((LLeftWidth - 1) mod 2) = 0 then
              Exit(FAst.BuiltinType(tkKwString));
            Exit(FAst.BuiltinType(tkKwWstring));
          end;
          // PLAN-ARITH A1 / A2: two numeric operands give C++'s result type,
          // each converting to it (DoArithResult); a bool, char or wchar
          // operand has no arithmetic (reported below). Any other pair (a
          // pointer, C/C++) stays C++'s
          if LHasTokens and DoIsNumericToken(LLeftToken) and DoIsNumericToken(LRightToken) then
          begin
            if DoNumericResult(AOp, LLeftToken, LRightToken, LNumeric) then
              Exit(DoArithResult(ANode, AOp, ALeft, ARight, LNumeric));
          end
          else
            Exit(FAst.OpaqueType());
        end;
      end;
    boDiv, boBitAnd, boBitOr:
      begin
        // A set has no / (F-A8c: nor /=); & | on sets stay C++'s
        // (::pcpp::Set's operators). PLAN-ARITH A1 / A2: two numeric
        // operands give C++'s result type (/ of two integers float64), each
        // converting to it (DoArithResult); a float with & |, and a bool,
        // char or wchar operand (& | on two bools included: and / or are
        // the logical words) have no PaskalCPP operator: reported below.
        // Any other pair stays C++'s
        if not ((AOp = boDiv) and (LLeftSet or LRightSet)) then
        begin
          if LHasTokens and DoIsNumericToken(LLeftToken) and DoIsNumericToken(LRightToken) then
          begin
            if DoNumericResult(AOp, LLeftToken, LRightToken, LNumeric) then
              Exit(DoArithResult(ANode, AOp, ALeft, ARight, LNumeric));
          end
          else
            Exit(FAst.OpaqueType());
        end;
      end;
    boIntDiv, boMod, boShl, boShr:
      begin
        // div / mod / shl / shr are integer operators (PLAN-ARITH A1: C++'s
        // result type)
        if LHasTokens and DoIsIntegerToken(LLeftToken) and DoIsIntegerToken(LRightToken) and
          DoNumericResult(AOp, LLeftToken, LRightToken, LNumeric) then
          Exit(DoArithResult(ANode, AOp, ALeft, ARight, LNumeric));
      end;
  end;
  DoReportOperands(ANode, PC_SEM_BINARY_TEXT[AOp], ALeft, ARight);
end;

function TPCSemantics.DoInType(const ANode: TPCExpr; const ALeft: TPCExpr; const ARight: TPCExpr): TPCTypeExpr;
var
  LRange: TPCSetType;
  LElement: TPCTypeExpr;
begin
  // `in`: the right is a PaskalCPP set, the left converts to its element type
  if not DoSetOf(ARight.ResolvedType, LRange, LElement) then
  begin
    DoReportOperands(ANode, PC_SEM_BINARY_TEXT[boIn], ALeft, ARight);
    Exit(nil);
  end;
  if (LRange <> nil) and (LRange.LowExpr <> nil) then
    LElement := LRange.LowExpr.ResolvedType;
  if (LElement <> nil) and not DoIsErrorType(LElement) and not DoConvertsImplicitly(ALeft, LElement) then
  begin
    DoError(ANode, PC_ERR_SEM_268, RSSemTypeNotElement,
      [ALeft.ResolvedType.TypeText(), ARight.ResolvedType.TypeText()]);
    DoPoison(ANode);
    Exit(nil);
  end;
  Result := FAst.BuiltinType(tkKwBool);
end;

function TPCSemantics.DoValueSigned(const AExpr: TPCExpr): Int64;
begin
  if AExpr.ConstIsUnsigned then
    Exit(Int64(AExpr.ConstUInt));
  Result := AExpr.ConstInt;
end;

// The fold routines compute C++'s modular results on purpose (unsigned
// wrap, two's complement patterns): overflow and range checks are off for
// them only, and restored after (signed overflow is checked explicitly)
{$IFOPT Q+}
  {$DEFINE PC_SEM_FOLD_Q}
  {$Q-}
{$ENDIF}
{$IFOPT R+}
  {$DEFINE PC_SEM_FOLD_R}
  {$R-}
{$ENDIF}

function TPCSemantics.DoFoldInfo(const AToken: TPCTokenKind; out ABits: Integer;
  out AIsUnsigned: Boolean): Boolean;
var
  LTarget: TPCTargetTriple;
begin
  // The width and signedness of a folded value of AToken: the eight
  // integers, bool (0 / 1), char (the data model's signedness) and wchar
  // (the target's width and signedness); nothing else folds as an integer
  if DoIntTypeInfo(AToken, ABits, AIsUnsigned) then
    Exit(True);
  Result := True;
  LTarget := DoModelTarget();
  case AToken of
    tkKwBool:
      begin
        ABits := 8;
        AIsUnsigned := True;
      end;
    tkKwChar:
      begin
        ABits := 8;
        AIsUnsigned := not LTarget.IsCharSigned();
      end;
    tkKwWchar:
      begin
        ABits := LTarget.WCharBits();
        AIsUnsigned := not LTarget.IsWCharSigned();
      end;
  else
    begin
      ABits := 0;
      AIsUnsigned := False;
    end;
  end;
  if ABits = 0 then
    Result := False;
end;

function TPCSemantics.DoFoldOperand(const AExpr: TPCExpr; out AToken: TPCTokenKind): Boolean;
var
  LBits: Integer;
  LIsUnsigned: Boolean;
begin
  // A folded integer-family constant (never a float, a string or a choice)
  AToken := tkUnknown;
  if (AExpr = nil) or not AExpr.HasConstValue then
    Exit(False);
  Result := DoTokenOf(AExpr, AToken) and DoFoldInfo(AToken, LBits, LIsUnsigned);
end;

function TPCSemantics.DoPromotedToken(const AToken: TPCTokenKind): TPCTokenKind;
var
  LBits: Integer;
  LIsUnsigned: Boolean;
begin
  // Integral promotion (C++23 [conv.prom]): the 32 / 64-bit integers stay;
  // everything narrower (bool, char, wchar on both supported targets, the 8 /
  // 16-bit integers) becomes int32
  if DoIntTypeInfo(AToken, LBits, LIsUnsigned) and (LBits >= 32) then
    Exit(AToken);
  Result := tkKwInt32;
end;

function TPCSemantics.DoCommonToken(const ALeft: TPCTokenKind; const ARight: TPCTokenKind): TPCTokenKind;
var
  LLeftBits: Integer;
  LRightBits: Integer;
  LLeftUnsigned: Boolean;
  LRightUnsigned: Boolean;
begin
  // The usual arithmetic conversions of two promoted integers (C++23
  // [expr.arith.conv]; the same on every target: fixed-width types)
  if ALeft = ARight then
    Exit(ALeft);
  DoIntTypeInfo(ALeft, LLeftBits, LLeftUnsigned);
  DoIntTypeInfo(ARight, LRightBits, LRightUnsigned);
  if LLeftUnsigned = LRightUnsigned then
  begin
    if LLeftBits >= LRightBits then
      Exit(ALeft);
    Exit(ARight);
  end;
  // One unsigned, one signed: the unsigned one wins at the same or a higher
  // rank; a wider signed one holds every value of the unsigned one
  if LLeftUnsigned then
  begin
    if LLeftBits >= LRightBits then
      Exit(ALeft);
    Exit(ARight);
  end;
  if LRightBits >= LLeftBits then
    Exit(ARight);
  Result := ALeft;
end;

function TPCSemantics.DoIsNumericToken(const AToken: TPCTokenKind): Boolean;
var
  LBits: Integer;
  LIsUnsigned: Boolean;
begin
  // A PaskalCPP builtin C++ computes with: the eight integers, bool, char,
  // wchar (DoFoldInfo's integral family) and the two floats
  Result := DoFoldInfo(AToken, LBits, LIsUnsigned) or (AToken = tkKwFloat32) or (AToken = tkKwFloat64);
end;

function TPCSemantics.DoNumericResult(const AOp: TPCBinaryOp; const ALeftToken: TPCTokenKind;
  const ARightToken: TPCTokenKind; out AResult: TPCTokenKind): Boolean;
var
  LLeftFloat: Boolean;
  LRightFloat: Boolean;
  LLeftInteger: Boolean;
  LRightInteger: Boolean;
  LBits: Integer;
  LIsUnsigned: Boolean;
begin
  // PLAN-ARITH A1 (BNF 6 "No hidden conversions" on non-constant operands):
  // the type C++23 gives an arithmetic / bitwise / shift result on two
  // PaskalCPP numeric operands ([expr.arith.conv]: integral promotion, then
  // the usual arithmetic conversions; an integer meeting a float becomes
  // that float), so the conversion check judges where it goes. `/` of two
  // integers is real division (BNF 6, the emitter writes
  // static_cast<double>): float64. A shift is the promoted left operand's
  // type. False = C++ has no such operator for the pair (a float with a
  // bitwise operator, div / mod or a shift) or PaskalCPP gives the pair no
  // arithmetic (PLAN-ARITH A2: a bool, char or wchar operand; write
  // int32(LC) + 1): the caller reports it. DoFoldArith / DoFoldShift read
  // the same rule
  AResult := tkUnknown;
  Result := False;
  LLeftFloat := (ALeftToken = tkKwFloat32) or (ALeftToken = tkKwFloat64);
  LRightFloat := (ARightToken = tkKwFloat32) or (ARightToken = tkKwFloat64);
  LLeftInteger := DoIntTypeInfo(ALeftToken, LBits, LIsUnsigned);
  LRightInteger := DoIntTypeInfo(ARightToken, LBits, LIsUnsigned);
  if not (LLeftFloat or LLeftInteger) or not (LRightFloat or LRightInteger) then
    Exit;
  if LLeftFloat or LRightFloat then
  begin
    if not (AOp in [boAdd, boSub, boMul, boDiv]) then
      Exit;
    if (ALeftToken = tkKwFloat64) or (ARightToken = tkKwFloat64) then
      AResult := tkKwFloat64
    else
      AResult := tkKwFloat32;
    Exit(True);
  end;
  case AOp of
    boShl, boShr:
      AResult := DoPromotedToken(ALeftToken);
    boDiv:
      AResult := tkKwFloat64;
    boAdd, boSub, boMul, boIntDiv, boMod, boBitAnd, boBitOr, boBitXor:
      AResult := DoCommonToken(DoPromotedToken(ALeftToken), DoPromotedToken(ARightToken));
  else
    Exit;
  end;
  Result := True;
end;

function TPCSemantics.DoUnaryResult(const AOp: TPCUnaryOp; const AToken: TPCTokenKind;
  out AResult: TPCTokenKind): Boolean;
var
  LIsFloat: Boolean;
  LIsInteger: Boolean;
  LBits: Integer;
  LIsUnsigned: Boolean;
begin
  // PLAN-ARITH A1: - + ~ on a PaskalCPP numeric operand: C++'s promoted type
  // (a float stays itself); ++ / -- keep the operand's type (the caller uses
  // the operand's own type node). False = no such C++ operator: ~ of a float,
  // ++ / -- of a bool (C++17 removed them). PLAN-ARITH A2: - + ~ take only
  // the eight integers and the floats (a bool, char or wchar is no number:
  // int32(LC)); ++ / -- of a char / wchar is its ordinal step and stays
  AResult := tkUnknown;
  Result := False;
  if not DoIsNumericToken(AToken) then
    Exit;
  LIsFloat := (AToken = tkKwFloat32) or (AToken = tkKwFloat64);
  LIsInteger := DoIntTypeInfo(AToken, LBits, LIsUnsigned);
  case AOp of
    uoNegate, uoPlus:
      begin
        if LIsFloat then
          AResult := AToken
        else if LIsInteger then
          AResult := DoPromotedToken(AToken)
        else
          Exit;
      end;
    uoBitNot:
      begin
        if not LIsInteger then
          Exit;
        AResult := DoPromotedToken(AToken);
      end;
    uoPreInc, uoPreDec, uoPostInc, uoPostDec:
      begin
        if AToken = tkKwBool then
          Exit;
        AResult := AToken;
      end;
  else
    Exit;
  end;
  Result := True;
end;

function TPCSemantics.DoArithResult(const ANode: TPCExpr; const AOp: TPCBinaryOp; const ALeft: TPCExpr;
  const ARight: TPCExpr; const AResult: TPCTokenKind): TPCTypeExpr;
var
  LLeftToken: TPCTokenKind;
  LRightToken: TPCTokenKind;
  LReported: Boolean;
begin
  // PLAN-ARITH A2 (BNF 6 "No hidden conversions"): C++ converts each operand
  // of an arithmetic / bitwise operator to the result type (DoNumericResult:
  // the usual arithmetic conversions; float64 for `/`), so each one must
  // convert implicitly to it: int32 + uint32 (the int32 becomes uint32),
  // int64 / 2 (float64 cannot hold every int64), int32 * float32. Else
  // SM0200 at that operand with the cast hint (DoCheckConvert), the node
  // poisoned (nil). A constant operand converts as a constant (it fits).
  // A shift's count is not converted ([expr.shift]); two folded constants
  // are judged by the fold (SM0251 / SM0256, one report)
  Result := FAst.BuiltinType(AResult);
  if AOp in [boShl, boShr] then
    Exit;
  if DoFoldOperand(ALeft, LLeftToken) and DoFoldOperand(ARight, LRightToken) then
    Exit;
  LReported := False;
  if not DoConvertsImplicitly(ALeft, Result) then
  begin
    DoCheckConvert(ALeft, Result);
    LReported := True;
  end;
  if not DoConvertsImplicitly(ARight, Result) then
  begin
    DoCheckConvert(ARight, Result);
    LReported := True;
  end;
  if LReported then
  begin
    DoPoison(ANode);
    Result := nil;
  end;
end;

function TPCSemantics.DoCheckNumericCompound(const AAssign: TPCAssign; const ATarget: TPCExpr;
  const AValue: TPCExpr): Boolean;
var
  LTargetToken: TPCTokenKind;
  LValueToken: TPCTokenKind;
  LOp: TPCBinaryOp;
  LResult: TPCTokenKind;
begin
  // PLAN-ARITH A2 (Q2): `T OP= V` on a PaskalCPP number computes T OP V and
  // stores it back in T's type, so the operator must take the pair
  // (DoNumericResult: no bool / char / wchar arithmetic, no float bitwise /
  // mod / shift) and V converts implicitly to T's type (LI8 += 1 fits,
  // LI8 += LBig is SM0200), as LI8++ works in the target's type. `/` is real
  // division (BNF 6): its float64 result never goes back into an integer, so
  // `/=` on an integer target is SM0250 (write LI := LI div 2). A shift's
  // count is not converted. Any other target or value (a pointer, a string,
  // C/C++) stays C++'s. False = reported
  Result := True;
  if not DoTokenOf(ATarget, LTargetToken) or not DoTokenOf(AValue, LValueToken) then
    Exit;
  if not DoIsNumericToken(LTargetToken) or not DoIsNumericToken(LValueToken) then
    Exit;
  case AAssign.Op of
    aoAddAssign:
      LOp := boAdd;
    aoSubAssign:
      LOp := boSub;
    aoMulAssign:
      LOp := boMul;
    aoDivAssign:
      LOp := boDiv;
    aoModAssign:
      LOp := boMod;
    aoBitAndAssign:
      LOp := boBitAnd;
    aoBitOrAssign:
      LOp := boBitOr;
    aoShlAssign:
      LOp := boShl;
    aoShrAssign:
      LOp := boShr;
  else
    Exit;
  end;
  if not DoNumericResult(LOp, LTargetToken, LValueToken, LResult) or
    ((LOp = boDiv) and DoIsIntegerToken(LTargetToken)) then
  begin
    DoReportOperands(AAssign, AAssign.OpText(), ATarget, AValue);
    Exit(False);
  end;
  if LOp in [boShl, boShr] then
    Exit;
  DoCheckConvert(AValue, ATarget.ResolvedType);
  Result := not DoIsPoisoned(AValue);
end;

function TPCSemantics.DoConstPattern(const AExpr: TPCExpr): UInt64;
begin
  // A folded value as a 64-bit two's complement pattern (signed values are
  // stored sign-extended, unsigned ones zero-extended)
  if AExpr.ConstIsUnsigned then
    Exit(AExpr.ConstUInt);
  Result := UInt64(AExpr.ConstInt);
end;

function TPCSemantics.DoMinOf(const ABits: Integer): Int64;
begin
  // The lowest value of a signed ABits-bit integer
  if ABits >= 64 then
    Exit(Low(Int64));
  Result := -(Int64(1) shl (ABits - 1));
end;

procedure TPCSemantics.DoStoreFolded(const AExpr: TPCExpr; const AToken: TPCTokenKind; const APattern: UInt64;
  const ASetType: Boolean);
var
  LBits: Integer;
  LIsUnsigned: Boolean;
  LPattern: UInt64;
  LMask: UInt64;
begin
  // The value APattern converted to AToken (C++20: modulo 2^N, read with
  // the type's signedness; bool: <> 0). ASetType: the node's type becomes
  // AToken (an operator's result); a cast keeps the type it names
  DoFoldInfo(AToken, LBits, LIsUnsigned);
  AExpr.HasConstValue := True;
  AExpr.IsConstExpr := True;
  if ASetType then
    AExpr.ResolvedType := FAst.BuiltinType(AToken);
  if AToken = tkKwBool then
  begin
    AExpr.ConstIsUnsigned := False;
    AExpr.ConstInt := Ord(APattern <> 0);
    Exit;
  end;
  LPattern := APattern;
  if LBits < 64 then
  begin
    LMask := (UInt64(1) shl LBits) - 1;
    LPattern := LPattern and LMask;
    // A signed value with its top bit set is negative: sign-extend it
    if (not LIsUnsigned) and (((LPattern shr (LBits - 1)) and 1) = 1) then
      LPattern := LPattern or (not LMask);
  end;
  AExpr.ConstIsUnsigned := LIsUnsigned;
  if LIsUnsigned then
    AExpr.ConstUInt := LPattern
  else
    AExpr.ConstInt := Int64(LPattern);
end;

function TPCSemantics.DoFoldSignedness(const ANode: TPCExpr; const AOpText: string; const AOperand: TPCExpr;
  const APromoted: TPCTokenKind; const ACommon: TPCTokenKind): Boolean;
var
  LBits: Integer;
  LIsUnsigned: Boolean;
  LCommonText: string;
begin
  // Q8 (folding.md :184-197): a signed operand the usual arithmetic
  // conversions would make unsigned is an error naming the cast, unless it
  // is a folded constant >= 0 (it converts exactly). False = reported, ANode
  // poisoned
  Result := True;
  DoIntTypeInfo(APromoted, LBits, LIsUnsigned);
  if LIsUnsigned or AOperand.ConstIsUnsigned or (AOperand.ConstInt >= 0) then
    Exit;
  LCommonText := FAst.BuiltinType(ACommon).TypeText();
  DoError(AOperand, PC_ERR_SEM_251, RSSemTypeSignedToUnsigned,
    [AOpText, AOperand.ResolvedType.TypeText(), LCommonText, LCommonText]);
  DoPoison(ANode);
  Result := False;
end;

function TPCSemantics.DoSignedFold(const AOp: TPCBinaryOp; const ALeft: Int64; const ARight: Int64;
  const ABits: Integer; out AResult: Int64): Boolean;
var
  LMax: Int64;
  LNegative: Boolean;
  LLeftMag: UInt64;
  LRightMag: UInt64;
  LLimit: UInt64;
  LMag: UInt64;
begin
  // + - * of two signed ABits-bit values; False = the exact result is
  // outside the type (C++: undefined, SM0256)
  AResult := 0;
  if ABits < 64 then
  begin
    // 32-bit operands: the exact result fits Int64
    case AOp of
      boAdd:
        AResult := ALeft + ARight;
      boSub:
        AResult := ALeft - ARight;
    else
      AResult := ALeft * ARight;
    end;
    LMax := (Int64(1) shl (ABits - 1)) - 1;
    Exit((AResult >= -LMax - 1) and (AResult <= LMax));
  end;

  // 64-bit: checked before computing
  case AOp of
    boAdd:
      begin
        if ((ARight > 0) and (ALeft > High(Int64) - ARight)) or
          ((ARight < 0) and (ALeft < Low(Int64) - ARight)) then
          Exit(False);
        AResult := ALeft + ARight;
        Exit(True);
      end;
    boSub:
      begin
        if ((ARight < 0) and (ALeft > High(Int64) + ARight)) or
          ((ARight > 0) and (ALeft < Low(Int64) + ARight)) then
          Exit(False);
        AResult := ALeft - ARight;
        Exit(True);
      end;
  end;

  // Multiplication by magnitudes: |a| * |b| <= 2^63 - 1 (same signs) or
  // 2^63 (different signs); the magnitude of a negative value is taken one
  // step at a time, since -(int64 min) does not fit Int64
  if (ALeft = 0) or (ARight = 0) then
    Exit(True);
  LNegative := (ALeft < 0) <> (ARight < 0);
  if ALeft < 0 then
    LLeftMag := UInt64(-(ALeft + 1)) + 1
  else
    LLeftMag := UInt64(ALeft);
  if ARight < 0 then
    LRightMag := UInt64(-(ARight + 1)) + 1
  else
    LRightMag := UInt64(ARight);
  if LNegative then
    LLimit := UInt64(High(Int64)) + 1
  else
    LLimit := UInt64(High(Int64));
  if LLeftMag > LLimit div LRightMag then
    Exit(False);
  LMag := LLeftMag * LRightMag;
  if not LNegative then
    AResult := Int64(LMag)
  else if LMag = UInt64(High(Int64)) + 1 then
    AResult := Low(Int64)
  else
    AResult := -Int64(LMag);
  Result := True;
end;

procedure TPCSemantics.DoFoldArith(const ABinary: TPCBinary; const ALeftToken: TPCTokenKind;
  const ARightToken: TPCTokenKind);
var
  LLeft: TPCExpr;
  LRight: TPCExpr;
  LLeftPromoted: TPCTokenKind;
  LRightPromoted: TPCTokenKind;
  LCommon: TPCTokenKind;
  LBits: Integer;
  LIsUnsigned: Boolean;
  LOpText: string;
  LA: UInt64;
  LB: UInt64;
  LSigned: Int64;
  LTruth: Boolean;
begin
  // Comparisons, + - *, div, mod, & | xor: both operands promoted, then
  // converted to their common type (folding.md "Operators"), computed there
  LLeft := ABinary.Left;
  LRight := ABinary.Right;
  LOpText := PC_SEM_BINARY_TEXT[ABinary.Op];
  LLeftPromoted := DoPromotedToken(ALeftToken);
  LRightPromoted := DoPromotedToken(ARightToken);
  // A comparison computes in the common type and gives bool; an arithmetic /
  // bitwise operator's result type is DoNumericResult's (PLAN-ARITH A1: the
  // one rule DoBinaryType typed the node with)
  if ABinary.Op in [boEq, boNotEq, boLess, boGreater, boLessEq, boGreaterEq] then
    LCommon := DoCommonToken(LLeftPromoted, LRightPromoted)
  else if not DoNumericResult(ABinary.Op, ALeftToken, ARightToken, LCommon) then
    Exit;
  DoIntTypeInfo(LCommon, LBits, LIsUnsigned);
  if LIsUnsigned then
  begin
    if not DoFoldSignedness(ABinary, LOpText, LLeft, LLeftPromoted, LCommon) then
      Exit;
    if not DoFoldSignedness(ABinary, LOpText, LRight, LRightPromoted, LCommon) then
      Exit;
  end;
  // Every operand value is exact in the common type now: its pattern is it
  LA := DoConstPattern(LLeft);
  LB := DoConstPattern(LRight);

  case ABinary.Op of
    boEq, boNotEq, boLess, boGreater, boLessEq, boGreaterEq:
      begin
        case ABinary.Op of
          boEq:
            LTruth := LA = LB;
          boNotEq:
            LTruth := LA <> LB;
        else
          begin
            if LIsUnsigned then
            begin
              case ABinary.Op of
                boLess:
                  LTruth := LA < LB;
                boGreater:
                  LTruth := LA > LB;
                boLessEq:
                  LTruth := LA <= LB;
              else
                LTruth := LA >= LB;
              end;
            end
            else
            begin
              case ABinary.Op of
                boLess:
                  LTruth := Int64(LA) < Int64(LB);
                boGreater:
                  LTruth := Int64(LA) > Int64(LB);
                boLessEq:
                  LTruth := Int64(LA) <= Int64(LB);
              else
                LTruth := Int64(LA) >= Int64(LB);
              end;
            end;
          end;
        end;
        DoStoreFolded(ABinary, tkKwBool, Ord(LTruth), True);
      end;
    boAdd, boSub, boMul:
      begin
        if LIsUnsigned then
        begin
          // Unsigned: modulo 2^N (DoStoreFolded truncates)
          case ABinary.Op of
            boAdd:
              DoStoreFolded(ABinary, LCommon, LA + LB, True);
            boSub:
              DoStoreFolded(ABinary, LCommon, LA - LB, True);
          else
            DoStoreFolded(ABinary, LCommon, LA * LB, True);
          end;
          Exit;
        end;
        if not DoSignedFold(ABinary.Op, Int64(LA), Int64(LB), LBits, LSigned) then
        begin
          DoError(ABinary, PC_ERR_SEM_256, RSSemTypeConstOverflow, [FAst.BuiltinType(LCommon).TypeText()]);
          DoPoison(ABinary);
          Exit;
        end;
        DoStoreFolded(ABinary, LCommon, UInt64(LSigned), True);
      end;
    boIntDiv, boMod:
      begin
        // Truncation toward zero (Delphi's div / mod are C++'s); a zero
        // divisor at the divisor, min div|mod -1 at the operator
        if LB = 0 then
        begin
          DoError(LRight, PC_ERR_SEM_257, RSSemTypeDivZero, [LOpText]);
          DoPoison(ABinary);
          Exit;
        end;
        if LIsUnsigned then
        begin
          if ABinary.Op = boIntDiv then
            DoStoreFolded(ABinary, LCommon, LA div LB, True)
          else
            DoStoreFolded(ABinary, LCommon, LA mod LB, True);
          Exit;
        end;
        if (Int64(LA) = DoMinOf(LBits)) and (Int64(LB) = -1) then
        begin
          DoError(ABinary, PC_ERR_SEM_258, RSSemTypeMinDivMinusOne,
            [IntToStr(Int64(LA)), LOpText, FAst.BuiltinType(LCommon).TypeText()]);
          DoPoison(ABinary);
          Exit;
        end;
        if ABinary.Op = boIntDiv then
          DoStoreFolded(ABinary, LCommon, UInt64(Int64(LA) div Int64(LB)), True)
        else
          DoStoreFolded(ABinary, LCommon, UInt64(Int64(LA) mod Int64(LB)), True);
      end;
    boBitAnd:
      DoStoreFolded(ABinary, LCommon, LA and LB, True);
    boBitOr:
      DoStoreFolded(ABinary, LCommon, LA or LB, True);
    boBitXor:
      DoStoreFolded(ABinary, LCommon, LA xor LB, True);
  end;
end;

procedure TPCSemantics.DoFoldShift(const ABinary: TPCBinary; const ALeftToken: TPCTokenKind;
  const ARightToken: TPCTokenKind);
var
  LLeft: TPCExpr;
  LRight: TPCExpr;
  LPromoted: TPCTokenKind;
  LBits: Integer;
  LIsUnsigned: Boolean;
  LCount: UInt64;
  LInRange: Boolean;
  LA: UInt64;
begin
  // shl / shr: the result is the PROMOTED LEFT type; the count 0 .. width - 1
  // (C++: undefined otherwise; SM0259 at the count); shl is C++20 modular,
  // shr on a signed value arithmetic (folding.md :100-103)
  LLeft := ABinary.Left;
  LRight := ABinary.Right;
  if not DoNumericResult(ABinary.Op, ALeftToken, ARightToken, LPromoted) then
    Exit;
  DoIntTypeInfo(LPromoted, LBits, LIsUnsigned);
  if LRight.ConstIsUnsigned then
  begin
    LCount := LRight.ConstUInt;
    LInRange := LCount < UInt64(LBits);
  end
  else
  begin
    LCount := UInt64(LRight.ConstInt);
    LInRange := (LRight.ConstInt >= 0) and (LRight.ConstInt < LBits);
  end;
  if not LInRange then
  begin
    DoError(LRight, PC_ERR_SEM_259, RSSemTypeShiftCount, [DoConstText(LRight), LBits - 1]);
    DoPoison(ABinary);
    Exit;
  end;
  LA := DoConstPattern(LLeft);
  if ABinary.Op = boShl then
    DoStoreFolded(ABinary, LPromoted, LA shl LCount, True)
  else if LIsUnsigned or (Int64(LA) >= 0) then
    DoStoreFolded(ABinary, LPromoted, LA shr LCount, True)
  else
    // Arithmetic shift of a negative value: shift the complement in
    DoStoreFolded(ABinary, LPromoted, not ((not LA) shr LCount), True);
end;

procedure TPCSemantics.DoFoldBinary(const ABinary: TPCBinary);
var
  LLeftToken: TPCTokenKind;
  LRightToken: TPCTokenKind;
  LLeftTrue: Boolean;
  LRightTrue: Boolean;
begin
  // F27: an operator of two folded PaskalCPP constants folds in C++23's
  // result type (r-a-folding.md D1); called after DoBinaryType typed it. Any
  // other operand (opaque, a float, a string, a choice) leaves it unfolded
  if not DoFoldOperand(ABinary.Left, LLeftToken) or not DoFoldOperand(ABinary.Right, LRightToken) then
    Exit;
  case ABinary.Op of
    boLogOr, boLogAnd:
      begin
        // DoBinaryType took two bools
        LLeftTrue := ABinary.Left.ConstInt <> 0;
        LRightTrue := ABinary.Right.ConstInt <> 0;
        if ABinary.Op = boLogOr then
          DoStoreFolded(ABinary, tkKwBool, Ord(LLeftTrue or LRightTrue), True)
        else
          DoStoreFolded(ABinary, tkKwBool, Ord(LLeftTrue and LRightTrue), True);
      end;
    boBitXor:
      begin
        // xor of two bools is logical (DoBinaryType), of two integers C++'s ^
        if (LLeftToken = tkKwBool) and (LRightToken = tkKwBool) then
          DoStoreFolded(ABinary, tkKwBool, Ord((ABinary.Left.ConstInt <> 0) <> (ABinary.Right.ConstInt <> 0)), True)
        else
          DoFoldArith(ABinary, LLeftToken, LRightToken);
      end;
    boShl, boShr:
      DoFoldShift(ABinary, LLeftToken, LRightToken);
    boEq, boNotEq, boLess, boGreater, boLessEq, boGreaterEq, boAdd, boSub, boMul, boIntDiv, boMod,
      boBitAnd, boBitOr:
      DoFoldArith(ABinary, LLeftToken, LRightToken);
  end;
end;

function TPCSemantics.DoFoldUnary(const AUnary: TPCUnary; const AOperand: TPCExpr): Boolean;
var
  LToken: TPCTokenKind;
  LPromoted: TPCTokenKind;
  LBits: Integer;
  LIsUnsigned: Boolean;
  LA: UInt64;
begin
  // - + ~ of a folded constant, on its promoted type (r-a D5): signed -min
  // overflows (SM0256), unsigned - is modulo. True = folded or reported
  Result := False;
  if not DoFoldOperand(AOperand, LToken) then
    Exit;
  // PLAN-ARITH A1: the type DoUnary types an unfolded one with (one rule)
  if not DoUnaryResult(AUnary.Op, LToken, LPromoted) then
    Exit;
  DoIntTypeInfo(LPromoted, LBits, LIsUnsigned);
  LA := DoConstPattern(AOperand);
  case AUnary.Op of
    uoPlus:
      DoStoreFolded(AUnary, LPromoted, LA, True);
    uoBitNot:
      DoStoreFolded(AUnary, LPromoted, not LA, True);
    uoNegate:
      begin
        if (not LIsUnsigned) and (Int64(LA) = DoMinOf(LBits)) then
        begin
          DoError(AUnary, PC_ERR_SEM_256, RSSemTypeConstOverflow, [FAst.BuiltinType(LPromoted).TypeText()]);
          DoPoison(AUnary);
          Exit(True);
        end;
        DoStoreFolded(AUnary, LPromoted, UInt64(0) - LA, True);
      end;
  else
    Exit;
  end;
  Result := True;
end;

procedure TPCSemantics.DoFoldConversion(const AExpr: TPCExpr; const AOperand: TPCExpr; const ATarget: TPCTypeExpr);
var
  LToken: TPCTokenKind;
  LTarget: TPCTokenKind;
  LBits: Integer;
  LIsUnsigned: Boolean;
  LFromChoice: Boolean;
begin
  // A cast of a folded integer-family constant to a PaskalCPP integer, bool,
  // char or wchar type: the C++23 conversion (modulo 2^N; to bool <> 0).
  // The node keeps the type it names (an alias stays the alias). F38: a
  // choice value converts as its ordinal (int32(TColor.cBlue)), and a cast
  // to a choices type converts through the type's underlying integer, as
  // C++ converts to an enum with a fixed underlying type ((TColor)9); a
  // choice is still never an arithmetic operand (DoFoldOperand)
  LFromChoice := (AOperand <> nil) and AOperand.HasConstValue and not DoIsPoisoned(AOperand) and
    (AOperand.ResolvedType <> nil) and (AOperand.ResolvedType.Canon() is TPCChoicesType);
  if (not LFromChoice) and not DoFoldOperand(AOperand, LToken) then
    Exit;
  if (ATarget <> nil) and (ATarget.Canon() is TPCChoicesType) then
  begin
    if TPCChoicesType(ATarget.Canon()).UnderlyingBits() = 64 then
      LTarget := tkKwInt64
    else
      LTarget := tkKwInt32;
    DoStoreFolded(AExpr, LTarget, DoConstPattern(AOperand), False);
    Exit;
  end;
  if (ATarget = nil) or not DoBuiltinOf(ATarget, LTarget) or not DoFoldInfo(LTarget, LBits, LIsUnsigned) then
    Exit;
  DoStoreFolded(AExpr, LTarget, DoConstPattern(AOperand), False);
end;

procedure TPCSemantics.DoFoldTernary(const ATernary: TPCTernary);
var
  LChosen: TPCExpr;
begin
  // ?: with a folded condition and branches of one type: the chosen
  // branch's value (C++ evaluates only that one; the other need not fold)
  if not ATernary.Condition.HasConstValue or DoIsOpaqueTier(ATernary.ResolvedType) then
    Exit;
  if ATernary.Condition.ConstInt <> 0 then
    LChosen := ATernary.ThenExpr
  else
    LChosen := ATernary.ElseExpr;
  if not LChosen.HasConstValue then
    Exit;
  ATernary.HasConstValue := True;
  ATernary.ConstIsUnsigned := LChosen.ConstIsUnsigned;
  ATernary.ConstInt := LChosen.ConstInt;
  ATernary.ConstUInt := LChosen.ConstUInt;
end;

{$IFDEF PC_SEM_FOLD_Q}
  {$Q+}
  {$UNDEF PC_SEM_FOLD_Q}
{$ENDIF}
{$IFDEF PC_SEM_FOLD_R}
  {$R+}
  {$UNDEF PC_SEM_FOLD_R}
{$ENDIF}

procedure TPCSemantics.DoBinary(const ABinary: TPCBinary);
var
  LType: TPCTypeExpr;
  LOperator: TPCOperatorItem;
begin
  DoExpr(ABinary.Left);
  DoExpr(ABinary.Right);
  if not DoOperandsReady(ABinary, [ABinary.Left, ABinary.Right]) then
    Exit;
  // PLAN-OBJECT O11 (D13 / H4): an operator an operand's type declares runs
  // instead of the built-in one (a record declaring = / <> compares)
  if DoDeclaredOperator(ABinary, ABinary.Op, False, [ABinary.Left, ABinary.Right], LOperator) then
  begin
    ABinary.ResolvedOperator := LOperator;
    Exit;
  end;
  // A constant expression for the shape check (SM0202); two folded
  // PaskalCPP constants also fold (F27), else the value is clang's
  ABinary.IsConstExpr := ABinary.Left.IsConstExpr and ABinary.Right.IsConstExpr;
  LType := DoBinaryType(ABinary, ABinary.Op, ABinary.Left, ABinary.Right);
  if LType = nil then
    Exit;
  ABinary.ResolvedType := LType;
  // PLAN-RECORDS A8c (M8): an operator on a static array / set operand binds
  // a reference to it (or calls a member: `in`)
  DoNoteMisalignedOperand(ABinary.Left);
  DoNoteMisalignedOperand(ABinary.Right);
  DoFoldBinary(ABinary);
end;

function TPCSemantics.DoIsAssignable(const AExpr: TPCExpr): Boolean;
var
  LKind: TPCResolvedKind;
  LDecl: TPCNode;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
begin
  // semantics.md := row: a variable, a var / plain param, a field, an index,
  // a deref; never a const decl, a const param or a literal. Opaque C++ is clang's
  if (AExpr = nil) or (AExpr.ResolvedType = nil) then
    Exit(False);
  // PLAN-OBJECT O9 / O10: a property is no storage (whatever its type)
  if DoIsPropertyAccess(AExpr) then
    Exit(False);
  if DoIsOpaqueTier(AExpr.ResolvedType) or (AExpr is TPCVerbatimExpr) then
    Exit(True);
  // parent (only ever a '.' base: SM0016) is self seen as its parent type:
  // parent.Z is self's field Z, assignable as self.Z is
  // PLAN-OBJECT O9: in a property's read self is const (emitted const)
  if AExpr is TPCSpecial then
    Exit((TPCSpecial(AExpr).SpecialKind in [skSelf, skParent]) and not DoInConstSelf());
  if AExpr is TPCIndex then
  begin
    if TPCTypeExpr.PointerOf(TPCIndex(AExpr).Base.ResolvedType, LTarget, LIsConst) then
      Exit(not LIsConst);
    Exit(DoIsAssignable(TPCIndex(AExpr).Base));
  end;
  if AExpr is TPCUnary then
  begin
    if TPCUnary(AExpr).Op <> uoDeref then
      Exit(False);
    TPCTypeExpr.PointerOf(TPCUnary(AExpr).Operand.ResolvedType, LTarget, LIsConst);
    Exit(not LIsConst);
  end;
  // PLAN-OBJECT O12: `X as T` on an object is that object (assignable when X
  // is); on an own the object it holds (on the heap, never const); a ptr /
  // ref result and `is` are values
  if AExpr is TPCTypeTest then
  begin
    if not DoIsObjectCast(AExpr) then
      Exit(False);
    LTarget := TPCTypeTest(AExpr).Operand.ResolvedType;
    if (LTarget <> nil) and (LTarget.Canon() is TPCOwnerType) then
      Exit(True);
    Exit(DoIsAssignable(TPCTypeTest(AExpr).Operand));
  end;
  if AExpr is TPCName then
  begin
    LKind := TPCName(AExpr).ResolvedKind;
    LDecl := TPCName(AExpr).ResolvedDecl;
  end
  else if AExpr is TPCMember then
  begin
    LKind := TPCMember(AExpr).ResolvedKind;
    LDecl := TPCMember(AExpr).ResolvedDecl;
    // A field of a value is assignable when the value is; through -> when the target is not const
    if LKind = rkField then
    begin
      if TPCMember(AExpr).Access = maArrow then
      begin
        TPCTypeExpr.PointerOf(TPCMember(AExpr).Base.ResolvedType, LTarget, LIsConst);
        Exit(not LIsConst);
      end;
      // PLAN-OBJECT O6: a field of the object an own / ref holds (on the
      // heap, never const), whatever the owner itself is
      if (TPCMember(AExpr).Base.ResolvedType <> nil) and
        (TPCMember(AExpr).Base.ResolvedType.Canon() is TPCOwnerType) then
        Exit(True);
      Exit(DoIsAssignable(TPCMember(AExpr).Base));
    end;
  end
  else
    Exit(False);
  case LKind of
    rkVar, rkField, rkOpaque:
      Result := True;
    rkParam:
      Result := (LDecl is TPCParam) and (TPCParam(LDecl).ParamMode <> pmConst);
  else
    Result := False;
  end;
end;

function TPCSemantics.DoIsAddressable(const AExpr: TPCExpr; out AIsConst: Boolean): Boolean;
var
  LKind: TPCResolvedKind;
begin
  // An lvalue PaskalCPP knows: a named value, a field, an index, a deref
  AIsConst := False;
  if (AExpr = nil) or (AExpr.ResolvedType = nil) then
    Exit(False);
  // PLAN-OBJECT O9 / O10: a property is no lvalue (its read gives a value)
  if DoIsPropertyAccess(AExpr) then
    Exit(False);
  if DoIsOpaqueTier(AExpr.ResolvedType) or (AExpr is TPCVerbatimExpr) then
    Exit(True);
  // PLAN-OBJECT O12: `X as T` whose result is the object (DoIsObjectCast)
  if (AExpr is TPCIndex) or ((AExpr is TPCUnary) and (TPCUnary(AExpr).Op = uoDeref)) or
    ((AExpr is TPCSpecial) and (TPCSpecial(AExpr).SpecialKind in [skSelf, skParent])) or DoIsObjectCast(AExpr) then
  begin
    AIsConst := not DoIsAssignable(AExpr);
    Exit(True);
  end;
  if AExpr is TPCName then
    LKind := TPCName(AExpr).ResolvedKind
  else if AExpr is TPCMember then
    LKind := TPCMember(AExpr).ResolvedKind
  else
    Exit(False);
  case LKind of
    rkVar, rkField, rkParam, rkConst, rkOpaque:
      begin
        AIsConst := (LKind = rkConst) or not DoIsAssignable(AExpr);
        Result := True;
      end;
  else
    Result := False;
  end;
end;

procedure TPCSemantics.DoUnary(const AUnary: TPCUnary);
var
  LOperand: TPCExpr;
  LToken: TPCTokenKind;
  LHasToken: Boolean;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
  LDerived: TPCDerivedType;
  LOperator: TPCOperatorItem;
  LNumeric: TPCTokenKind;
begin
  DoExpr(AUnary.Operand);
  LOperand := AUnary.Operand;
  if not DoOperandsReady(AUnary, [LOperand]) then
    Exit;
  LHasToken := DoTokenOf(LOperand, LToken);
  // F59 (expr_unary_postfix, DESIGN sec 5; F55's rule for the binary
  // operators): a string / wstring value takes no unary arithmetic (- + ~ ++
  // --): SM0250 at the expression; it was typed opaque and reached clang
  if LHasToken and ((LToken = tkKwString) or (LToken = tkKwWstring)) and
    (AUnary.Op in [uoNegate, uoPlus, uoBitNot, uoPreInc, uoPreDec, uoPostInc, uoPostDec]) then
  begin
    DoReportOperands(AUnary, PC_SEM_UNARY_TEXT[AUnary.Op], LOperand, nil);
    Exit;
  end;
  case AUnary.Op of
    uoLogNot:
      begin
        // not is logical: a bool operand
        if not LHasToken or (LToken <> tkKwBool) then
        begin
          DoReportOperands(AUnary, PC_SEM_UNARY_TEXT[AUnary.Op], LOperand, nil);
          Exit;
        end;
        AUnary.ResolvedType := FAst.BuiltinType(tkKwBool);
        AUnary.IsConstExpr := LOperand.IsConstExpr;
        // not of a folded bool folds (F27)
        if LOperand.HasConstValue then
          DoStoreFolded(AUnary, tkKwBool, Ord(LOperand.ConstInt = 0), True);
      end;
    uoNegate:
      begin
        // PLAN-OBJECT O11: a unary minus the operand's type declares
        if DoDeclaredOperator(AUnary, boSub, True, [LOperand], LOperator) then
        begin
          AUnary.ResolvedOperator := LOperator;
          Exit;
        end;
        // -C of a folded constant folds on its promoted type (F27, r-a D5);
        // PLAN-ARITH A1: a numeric operand is C++'s promoted type, so the
        // conversion check judges it (-LI8 is int32); anything else is C++'s
        AUnary.IsConstExpr := LOperand.IsConstExpr;
        if DoFoldUnary(AUnary, LOperand) then
          Exit;
        // PLAN-ARITH A2: a bool, char or wchar has no minus (SM0250)
        if LHasToken and DoIsNumericToken(LToken) and not DoUnaryResult(AUnary.Op, LToken, LNumeric) then
        begin
          DoReportOperands(AUnary, PC_SEM_UNARY_TEXT[AUnary.Op], LOperand, nil);
          Exit;
        end;
        if LHasToken and DoUnaryResult(AUnary.Op, LToken, LNumeric) then
          AUnary.ResolvedType := FAst.BuiltinType(LNumeric)
        else
          AUnary.ResolvedType := FAst.OpaqueType();
      end;
    uoAddressOf:
      begin
        // PLAN-OBJECT O9: a property is no storage: it has no address
        if DoIsPropertyAccess(LOperand) then
        begin
          DoError(LOperand, PC_ERR_SEM_376, RSSemDeclPropertyStorage,
            [LOperand.ExprText(), PC_SEM_UNARY_TEXT[AUnary.Op]]);
          DoPoison(AUnary);
          Exit;
        end;
        // The address of a PaskalCPP lvalue points to its type. F57
        // (expr_unary_postfix, DESIGN sec 5): a PaskalCPP value that is not
        // stored (a call result, an operator's or a cast's result, a literal
        // but a string one, which C++ stores) has none: SM0254 at the
        // operand; it was typed opaque and reached clang in C++ words. A name
        // or a member that is no lvalue (a routine, a method) keeps clang's
        // judgment, as before
        if not DoIsAddressable(LOperand, LIsConst) then
        begin
          if not ((LOperand is TPCName) or (LOperand is TPCMember) or
            ((LOperand is TPCLiteral) and (TPCLiteral(LOperand).LiteralKind = lkString))) then
          begin
            DoError(LOperand, PC_ERR_SEM_254, RSSemTypeNoAddress, [LOperand.ExprText()]);
            DoPoison(AUnary);
            Exit;
          end;
          AUnary.ResolvedType := FAst.OpaqueType();
          Exit;
        end;
        // A SEM-built type (types.md G8): non-owning, never a tree child
        LDerived := FAst.NewNode<TPCDerivedType>();
        LDerived.DerivedKind := dkPointerTo;
        LDerived.Target := LOperand.ResolvedType;
        LDerived.IsConstTarget := LIsConst;
        AUnary.ResolvedType := LDerived;
        // PLAN-RECORDS M8: a pointer to what may be misaligned is SM0270 (a
        // typed pointer promises an aligned target); the expression keeps
        // its type, one report
        if DoMayBeMisaligned(LOperand) then
          DoError(LOperand, PC_ERR_SEM_270, RSSemExprMisalignedAddress, [LOperand.ExprText()]);
      end;
    uoDeref:
      begin
        // ^ needs a pointer
        if not TPCTypeExpr.PointerOf(LOperand.ResolvedType, LTarget, LIsConst) then
        begin
          DoReportOperands(AUnary, PC_SEM_UNARY_TEXT[AUnary.Op], LOperand, nil);
          Exit;
        end;
        // F49 (SM0253): an untyped ptr points at no type; it reached clang
        // as "indirection not permitted on operand of type 'void *'" (both
        // targets, scripts\zb_cmpl\f4\pointer\p2_out.txt)
        if LTarget = nil then
        begin
          DoError(LOperand, PC_ERR_SEM_253, RSSemTypeUntypedPointer, [LOperand.ExprText(), LOperand.ExprText()]);
          DoPoison(AUnary);
          Exit;
        end;
        AUnary.ResolvedType := DoValueTypeOf(LTarget);
      end;
  else
    begin
      // ~, +, ++, --: C++'s operators, typed and judged by clang; ++ / --
      // on the for iterator inside its loop is a write (Q13 (a)). F39: none
      // takes a choices value, a PaskalCPP type with no arithmetic (it
      // reached clang in C++ words)
      if (LOperand.ResolvedType <> nil) and (LOperand.ResolvedType.Canon() is TPCChoicesType) then
      begin
        DoReportOperands(AUnary, PC_SEM_UNARY_TEXT[AUnary.Op], LOperand, nil);
        Exit;
      end;
      if AUnary.Op in [uoPreInc, uoPreDec, uoPostInc, uoPostDec] then
      begin
        // PLAN-OBJECT O9: ++ / -- write their operand in place: a property
        // is no storage (X := X + 1 runs its write)
        if DoIsPropertyAccess(LOperand) then
        begin
          DoError(LOperand, PC_ERR_SEM_376, RSSemDeclPropertyStorage,
            [LOperand.ExprText(), PC_SEM_UNARY_TEXT[AUnary.Op]]);
          DoPoison(AUnary);
          Exit;
        end;
        // ... and in a read self is const
        if DoInConstSelf() and DoRootsAtSelf(LOperand) then
        begin
          DoConstSelfChange(LOperand, LOperand.ExprText());
          DoPoison(AUnary);
          Exit;
        end;
        DoCheckIteratorWrite(LOperand);
      end;
      // PLAN-ARITH A1: on a numeric operand ~ + are C++'s promoted type and
      // ++ / -- the operand's own type; ~ of a float and ++ / -- of a bool
      // have no C++ operator (they reached clang in C++ words): SM0250. A2:
      // nor ~ / + of a bool, char or wchar (no number: int32(LC))
      if LHasToken and DoIsNumericToken(LToken) and not DoUnaryResult(AUnary.Op, LToken, LNumeric) then
      begin
        DoReportOperands(AUnary, PC_SEM_UNARY_TEXT[AUnary.Op], LOperand, nil);
        Exit;
      end;
      AUnary.IsConstExpr := LOperand.IsConstExpr and (AUnary.Op in [uoBitNot, uoPlus]);
      // ~C / +C of a folded constant fold (F27); the rest stays C++'s
      if (AUnary.Op in [uoBitNot, uoPlus]) and DoFoldUnary(AUnary, LOperand) then
        Exit;
      if LHasToken and DoIsNumericToken(LToken) then
      begin
        if AUnary.Op in [uoPreInc, uoPreDec, uoPostInc, uoPostDec] then
          AUnary.ResolvedType := LOperand.ResolvedType
        else
          AUnary.ResolvedType := FAst.BuiltinType(LNumeric);
      end
      else
        AUnary.ResolvedType := FAst.OpaqueType();
    end;
  end;
end;

procedure TPCSemantics.DoAssign(const AAssign: TPCAssign);
var
  LTarget: TPCExpr;
  LValue: TPCExpr;
  LToken: TPCTokenKind;
  LRange: TPCSetType;
  LElement: TPCTypeExpr;
  LSavedTarget: TPCExpr;
  LMember: TPCMember;
begin
  // semantics.md := row: the target is assignable (SM0255) and the value
  // converts to it (SM0200). A compound assignment's operator is C++'s
  // (clang types it), except on a PaskalCPP set (DoCheckSetAssign); its
  // value is still a value position (SM0269)
  // PLAN-OBJECT O9: the target is resolved as one (a property there is
  // written, not read: DoPropertyRead leaves it to DoPropertyAssign)
  LSavedTarget := FAssignTarget;
  FAssignTarget := AAssign.Target;
  try
    DoExpr(AAssign.Target);
  finally
    FAssignTarget := LSavedTarget;
  end;
  DoExpr(AAssign.ValueExpr);
  LTarget := AAssign.Target;
  LValue := AAssign.ValueExpr;
  if DoNotValue(LTarget) then
  begin
    DoPoison(AAssign);
    Exit;
  end;
  if (LTarget = nil) or (LValue = nil) or DoIsPoisoned(LTarget) then
  begin
    DoPoison(AAssign);
    Exit;
  end;
  if (LTarget.ResolvedType = nil) or DoIsErrorType(LTarget.ResolvedType) then
    Exit;
  // PLAN-OBJECT O9 / O10: a property's write: `LO.X := v`, `LO.Items[i] :=
  // v` (on the member's object), `LO[i] := v` (a default property)
  if (LTarget is TPCMember) and (TPCMember(LTarget).ResolvedKind = rkProperty) then
  begin
    DoPropertyAssign(AAssign, TPCPropertyItem(TPCMember(LTarget).ResolvedDecl), LTarget, TPCMember(LTarget).Base,
      TPCMember(LTarget).Access, TPCMember(LTarget).Member, Length(TPCMember(LTarget).ResolvedEmbedPath) > 0);
    Exit;
  end;
  if (LTarget is TPCIndex) and (TPCIndex(LTarget).ResolvedProperty <> nil) then
  begin
    if TPCIndex(LTarget).Base is TPCMember then
      LMember := TPCMember(TPCIndex(LTarget).Base)
    else
      LMember := nil;
    if (LMember <> nil) and (LMember.ResolvedKind = rkProperty) then
      DoPropertyAssign(AAssign, TPCIndex(LTarget).ResolvedProperty, LTarget, LMember.Base, LMember.Access,
        LMember.Member, Length(LMember.ResolvedEmbedPath) > 0)
    else
      DoPropertyAssign(AAssign, TPCIndex(LTarget).ResolvedProperty, LTarget, TPCIndex(LTarget).Base, maDot,
        LTarget, False);
    Exit;
  end;
  // PLAN-OBJECT O9: a property's read is const: it changes nothing of self
  if DoInConstSelf() and DoRootsAtSelf(LTarget) then
  begin
    DoConstSelfChange(LTarget, LTarget.ExprText());
    DoPoison(AAssign);
    Exit;
  end;
  if not DoIsAssignable(LTarget) then
  begin
    DoError(LTarget, PC_ERR_SEM_255, RSSemTypeNotAssignable, [LTarget.ExprText()]);
    DoPoison(AAssign);
    Exit;
  end;
  // Q13 (a): an assignment to the for iterator inside its loop
  DoCheckIteratorWrite(LTarget);
  AAssign.ResolvedType := LTarget.ResolvedType;
  if AAssign.Op = aoAssign then
  begin
    // A varargs local is set from a copy only (Q30, SM0422)
    if DoBuiltinOf(LTarget.ResolvedType, LToken) and (LToken = tkKwVarargs) and not DoIsVarargsCopy(LValue) then
    begin
      DoError(LValue, PC_ERR_SEM_422, RSSemCallVarargsType, [PC_VARARGS_WORDS[vaPlain], PC_VARARGS_WORDS[vaCopy]]);
      Exit;
    end;
    // TODO.md 8 (a): a polymorphic object that may be a descendant is never
    // assigned whole (only its base part would change)
    if DoCheckSliceAssign(LTarget) then
    begin
      DoPoison(AAssign);
      Exit;
    end;
    DoCheckConvert(LValue, LTarget.ResolvedType);
    // F38: a constant stored into a bitfield is held by its width
    if (LTarget is TPCMember) and (TPCMember(LTarget).ResolvedDecl is TPCField) then
      DoCheckBitfieldStore(LValue, TPCField(TPCMember(LTarget).ResolvedDecl));
    Exit;
  end;
  if DoNotValue(LValue) then
  begin
    DoPoison(AAssign);
    Exit;
  end;
  // F39: a choices value has no arithmetic, so no compound assignment takes
  // one (it reached clang as "invalid operands" in C++ words)
  if LTarget.ResolvedType.Canon() is TPCChoicesType then
  begin
    if (LValue.ResolvedType <> nil) and not DoIsErrorType(LValue.ResolvedType) then
      DoReportOperands(AAssign, AAssign.OpText(), LTarget, LValue)
    else
      DoPoison(AAssign);
    Exit;
  end;
  // PLAN-RECORDS F-A8c: a compound assignment to a PaskalCPP set is the
  // set's own operator (DoCheckSetAssign); every other one stays C++'s
  if DoSetOf(LTarget.ResolvedType, LRange, LElement) and not DoCheckSetAssign(AAssign) then
    Exit;
  // PLAN-ARITH A2 (Q2): a compound assignment to a PaskalCPP number stores
  // in the target's type: no hidden conversion of the value
  if not DoCheckNumericCompound(AAssign, LTarget, LValue) then
  begin
    DoPoison(AAssign);
    Exit;
  end;
  // M8 (the A8d sweep): the operator of a compound assignment to a PaskalCPP
  // aggregate (a set's member, a person's C++ operator for a record or an
  // array) takes the target by reference: one that may be misaligned is
  // SM0270. A scalar's built-in operator writes a packed field as it is; a
  // C/C++ target's operator is C++'s (A8c)
  if not LTarget.ResolvedType.IsScalarOrPointer() and not DoIsOpaqueTier(LTarget.ResolvedType) and
    DoMayBeMisaligned(LTarget) then
  begin
    DoError(LTarget, PC_ERR_SEM_270, RSSemExprMisalignedCompound, [AAssign.OpText(), LTarget.ExprText()]);
    DoPoison(AAssign);
    Exit;
  end;
  // ... and the value by const reference when it is an aggregate (A8c): a
  // value that may be misaligned is copied
  DoNoteMisalignedOperand(LValue);
end;

function TPCSemantics.DoCheckSetAssign(const AAssign: TPCAssign): Boolean;
begin
  // A compound assignment to a PaskalCPP set means what its binary operator
  // means (DoBinaryType): += -= *= are union / difference / intersection,
  // the value converting to the target's set type (a set literal included);
  // &= |= stay C++'s, as & | do; /= %= <<= >>= have no set meaning (SM0250).
  // The emitter writes ::pcpp::Set's member operators (|= -= &=). False =
  // reported (DoAssign stops)
  Result := False;
  case AAssign.Op of
    aoDivAssign, aoModAssign, aoShlAssign, aoShrAssign:
      begin
        if (AAssign.ValueExpr.ResolvedType <> nil) and not DoIsErrorType(AAssign.ValueExpr.ResolvedType) then
          DoReportOperands(AAssign, AAssign.OpText(), AAssign.Target, AAssign.ValueExpr)
        else
          DoPoison(AAssign);
        Exit;
      end;
    aoAddAssign, aoSubAssign, aoMulAssign:
      begin
        DoCheckConvert(AAssign.ValueExpr, AAssign.Target.ResolvedType);
        if DoIsPoisoned(AAssign.ValueExpr) then
          Exit;
      end;
  end;
  Result := True;
end;

function TPCSemantics.DoCheckCondition(const AExpr: TPCExpr): Boolean;
var
  LToken: TPCTokenKind;
begin
  // SM0263: a condition is bool (?: here; if / while / repeat call it too);
  // a type or module name is no value (SM0269)
  if DoNotValue(AExpr) then
    Exit(False);
  Result := True;
  if (AExpr = nil) or DoIsPoisoned(AExpr) or (AExpr.ResolvedType = nil) or DoIsErrorType(AExpr.ResolvedType) or
    DoIsOpaqueTier(AExpr.ResolvedType) then
    Exit;
  if DoTokenOf(AExpr, LToken) and (LToken = tkKwBool) then
    Exit;
  DoError(AExpr, PC_ERR_SEM_263, RSSemTypeCondition, [AExpr.ResolvedType.TypeText()]);
  DoPoison(AExpr);
  Result := False;
end;

procedure TPCSemantics.DoTernary(const ATernary: TPCTernary);
begin
  // ?: is C++'s conditional: clang types and judges it. Its type is the
  // branches' one PaskalCPP type when they share it, the base of an extension (R4), else opaque
  DoExpr(ATernary.Condition);
  // F53 (DESIGN sec 5): the condition is bool, as if / while / repeat's
  // (SM0263, poisoned: the ternary then reports nothing more)
  DoCheckCondition(ATernary.Condition);
  DoExpr(ATernary.ThenExpr);
  DoExpr(ATernary.ElseExpr);
  if not DoOperandsReady(ATernary, [ATernary.Condition, ATernary.ThenExpr, ATernary.ElseExpr]) then
    Exit;
  ATernary.IsConstExpr := ATernary.Condition.IsConstExpr and ATernary.ThenExpr.IsConstExpr and
    ATernary.ElseExpr.IsConstExpr;
  if DoSameType(ATernary.ThenExpr.ResolvedType, ATernary.ElseExpr.ResolvedType) then
    ATernary.ResolvedType := ATernary.ThenExpr.ResolvedType
  else
    ATernary.ResolvedType := DoTernaryBaseType(ATernary);
  // A folded condition with branches of one type folds to the chosen one (F27)
  DoFoldTernary(ATernary);
end;

function TPCSemantics.DoCheckIndex(const AIndex: TPCIndex; const ABase: TPCExpr; const AIndexExpr: TPCExpr): Boolean;
var
  LCanon: TPCTypeExpr;
  LBound: TPCTypeExpr;
  LToken: TPCTokenKind;
begin
  // SM0261: a static array is indexed by its bounds' family (SM0322 allows an
  // integer, a char or one choices type); a dynamic array, a string or a
  // pointer by an integer. An untyped, reported or opaque index, or an
  // opaque bound, is not judged here (clang judges the emitted index)
  Result := True;
  if (AIndexExpr.ResolvedType = nil) or DoIsErrorType(AIndexExpr.ResolvedType) or
    DoIsOpaqueTier(AIndexExpr.ResolvedType) then
    Exit;
  LCanon := ABase.ResolvedType.Canon();
  LBound := nil;
  if (LCanon is TPCArrayType) and not TPCArrayType(LCanon).IsDynamic and (TPCArrayType(LCanon).LowExpr <> nil) then
  begin
    LBound := TPCArrayType(LCanon).LowExpr.ResolvedType;
    if (LBound = nil) or DoIsErrorType(LBound) or DoIsOpaqueTier(LBound) then
      Exit;
  end;
  if (LBound <> nil) and (DoOrdinalKindOf(LBound) in [okChar, okChoices]) then
  begin
    if DoSameOrdinalFamily(LBound, AIndexExpr.ResolvedType) then
      Exit(DoIndexInRange(AIndex, ABase, AIndexExpr));
    DoError(AIndexExpr, PC_ERR_SEM_261, RSSemTypeIndexFamily,
      [ABase.ResolvedType.TypeText(), LBound.TypeText(), AIndexExpr.ResolvedType.TypeText()]);
  end
  else
  begin
    if DoTokenOf(AIndexExpr, LToken) and DoIsIntegerToken(LToken) then
      Exit(DoIndexInRange(AIndex, ABase, AIndexExpr));
    DoError(AIndexExpr, PC_ERR_SEM_261, RSSemTypeIndexNotInt, [AIndexExpr.ResolvedType.TypeText()]);
  end;
  DoPoison(AIndex);
  Result := False;
end;

function TPCSemantics.DoIndexInRange(const AIndex: TPCIndex; const ABase: TPCExpr; const AIndexExpr: TPCExpr): Boolean;
var
  LArray: TPCArrayType;
begin
  // F45 (SM0276): a static array indexed by a constant outside its folded
  // bounds is a PaskalCPP error at the index; C++ only warns, in its words,
  // and reads or writes past the array. A bound or an index SEM did not fold
  // (a C++ value, a variable) is not judged here
  Result := True;
  if not (ABase.ResolvedType.Canon() is TPCArrayType) then
    Exit;
  LArray := TPCArrayType(ABase.ResolvedType.Canon());
  if LArray.IsDynamic or (not DoFoldedInteger(AIndexExpr)) or (not DoFoldedInteger(LArray.LowExpr)) or
    (not DoFoldedInteger(LArray.HighExpr)) then
    Exit;
  // index < low, or index > high (DoBoundsReversed: its first above its second)
  if not (DoBoundsReversed(LArray.LowExpr, AIndexExpr) or DoBoundsReversed(AIndexExpr, LArray.HighExpr)) then
    Exit;
  DoError(AIndexExpr, PC_ERR_SEM_276, RSSemTypeIndexOutside,
    [AIndexExpr.BoundText(), ABase.ResolvedType.TypeText(), LArray.LowExpr.BoundText(), LArray.HighExpr.BoundText()]);
  DoPoison(AIndex);
  Result := False;
end;

procedure TPCSemantics.DoIndex(const AIndex: TPCIndex);
var
  LBase: TPCExpr;
  LIndexExpr: TPCExpr;
  LCanon: TPCTypeExpr;
  LToken: TPCTokenKind;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
  LSavedBase: TPCExpr;
  LSavedTarget: TPCExpr;
begin
  // semantics.md index row: an array, string or typed pointer, indexed by
  // its index family (DoCheckIndex). What an untyped pointer indexes is clang's.
  // PLAN-OBJECT O10: the base may be an indexed property (FIndexBase lets
  // DoPropertyRead take it); an index that is an assignment's target makes
  // that property the written one (FAssignTarget)
  LSavedBase := FIndexBase;
  LSavedTarget := FAssignTarget;
  FIndexBase := AIndex.Base;
  if AIndex = FAssignTarget then
    FAssignTarget := AIndex.Base;
  try
    DoExpr(AIndex.Base);
  finally
    FIndexBase := LSavedBase;
    FAssignTarget := LSavedTarget;
  end;
  DoExpr(AIndex.IndexExpr);
  LBase := AIndex.Base;
  LIndexExpr := AIndex.IndexExpr;
  if (LIndexExpr = nil) or DoIsPoisoned(LIndexExpr) then
  begin
    DoPoison(AIndex);
    Exit;
  end;
  if not DoOperandsReady(AIndex, [LBase]) then
    Exit;
  // O10: an indexed property, or an object's default property
  if DoIndexedProperty(AIndex) then
    Exit;
  if not DoCheckIndex(AIndex, LBase, LIndexExpr) then
    Exit;
  LCanon := LBase.ResolvedType.Canon();
  if LCanon is TPCArrayType then
    AIndex.ResolvedType := DoValueTypeOf(TPCArrayType(LCanon).ElementType)
  else if DoTokenOf(LBase, LToken) and (LToken = tkKwString) then
    AIndex.ResolvedType := FAst.BuiltinType(tkKwChar)
  else if DoTokenOf(LBase, LToken) and (LToken = tkKwWstring) then
    AIndex.ResolvedType := FAst.BuiltinType(tkKwWchar)
  else if TPCTypeExpr.PointerOf(LCanon, LTarget, LIsConst) then
  begin
    // F49 (SM0253): an untyped ptr is indexed only through a typed pointer,
    // as it is read through one (DoUnary uoDeref)
    if LTarget = nil then
    begin
      DoError(LBase, PC_ERR_SEM_253, RSSemTypeUntypedPointer, [LBase.ExprText(), LBase.ExprText()]);
      DoPoison(AIndex);
    end
    else
      AIndex.ResolvedType := DoValueTypeOf(LTarget);
  end
  else
  begin
    DoError(AIndex, PC_ERR_SEM_260, RSSemTypeNotIndexable, [LBase.ResolvedType.TypeText()]);
    DoPoison(AIndex);
  end;
end;

function TPCSemantics.DoIndexedProperty(const AIndex: TPCIndex): Boolean;
var
  LBase: TPCExpr;
  LProperty: TPCPropertyItem;
  LRecord: TPCTypeExpr;
  LText: string;
begin
  // PLAN-OBJECT O10 (D12): `LO.Items[i]` (the base an indexed property's
  // member) or `LO[i]` on an object with a default property (also through
  // an own / ref) reads or writes that property; the index converts to the
  // index parameter's type (SM0200 / SM0404's rules: DoCheckConvert). A
  // hidden default property is reached where a hidden member is (SM0019);
  // `self[i]` read in its own read runs it forever (SM0374). Writes
  // ResolvedProperty; True = this was a property access (judged here)
  Result := False;
  LBase := AIndex.Base;
  if (LBase is TPCMember) and (TPCMember(LBase).ResolvedKind = rkProperty) then
  begin
    LProperty := TPCPropertyItem(TPCMember(LBase).ResolvedDecl);
    // A plain property's value is indexed as any value of its type
    if LProperty.IndexParam = nil then
      Exit;
  end
  else
  begin
    if (LBase.ResolvedType.Canon() is TPCOwnerType) and
      (TPCOwnerType(LBase.ResolvedType.Canon()).OwnerKind = okWeak) then
      Exit;
    LRecord := TPCScopes.MemberRecord(LBase.ResolvedType, maDot);
    if not ((LRecord is TPCRecordType) and TPCRecordType(LRecord).IsObject) then
      Exit;
    LProperty := DoDefaultProperty(TPCRecordType(LRecord));
    if LProperty = nil then
      Exit;
    Result := True;
    LText := LBase.ResolvedType.TypeText();
    if LBase.ResolvedType.Canon() is TPCOwnerType then
      LText := TPCOwnerType(LBase.ResolvedType.Canon()).TargetType.TypeText();
    if DoHiddenBlocks(AIndex, LProperty, LProperty.PropName, LRecord, LText,
      (LBase is TPCSpecial) and (TPCSpecial(LBase).SpecialKind = skParent), True) then
    begin
      DoPoison(AIndex);
      Exit;
    end;
    if (AIndex <> FAssignTarget) and DoInOwnAccessor(LProperty.ReadItem) and (LBase is TPCSpecial) then
    begin
      DoError(AIndex, PC_ERR_SEM_374, RSSemDeclPropertyOwnRead, [LProperty.PropName]);
      DoPoison(AIndex);
      Exit;
    end;
  end;
  Result := True;
  AIndex.ResolvedProperty := LProperty;
  AIndex.ResolvedType := DoValueTypeOf(LProperty.TypeExpr);
  if LProperty.IsRecovered or (LProperty.IndexParam.TypeExpr = nil) then
  begin
    DoPoison(AIndex);
    Exit;
  end;
  DoCheckConvert(AIndex.IndexExpr, DoValueTypeOf(LProperty.IndexParam.TypeExpr));
end;

function TPCSemantics.DoDefaultProperty(const ARecord: TPCRecordType): TPCPropertyItem;
var
  LLevel: TPCTypeExpr;
  LItem: TPCMemberItem;
  LDepth: Integer;
begin
  // O10: the default property of ARecord's chain, nearest level first (one
  // per level: SM0379); nil = none. Bounded: a chain never loops
  Result := nil;
  LLevel := ARecord;
  LDepth := 0;
  while (LLevel is TPCRecordType) and (LDepth < 256) do
  begin
    for LItem in TPCRecordType(LLevel).Members do
    begin
      if (LItem is TPCPropertyItem) and TPCPropertyItem(LItem).IsDefault and
        (TPCPropertyItem(LItem).IndexParam <> nil) then
        Exit(TPCPropertyItem(LItem));
    end;
    if TPCRecordType(LLevel).ParentName = nil then
      Exit;
    LLevel := TPCRecordType(LLevel).ParentName.Canon();
    Inc(LDepth);
  end;
end;

function TPCSemantics.DoIsOrdinalType(const AType: TPCTypeExpr): Boolean;
var
  LToken: TPCTokenKind;
begin
  // What a set holds: integers, char, wchar, bool, choices
  if AType = nil then
    Exit(False);
  if DoBuiltinOf(AType, LToken) then
    Exit(DoIsIntegerToken(LToken) or (LToken = tkKwChar) or (LToken = tkKwWchar) or (LToken = tkKwBool));
  Result := AType.Canon() is TPCChoicesType;
end;

function TPCSemantics.DoSetLiteralFits(const ALiteral: TPCSetLiteral; const ASetType: TPCTypeExpr): Boolean;
var
  LRange: TPCSetType;
  LElement: TPCTypeExpr;
  LItem: TPCSetElement;
  LValue: TPCExpr;
  LToken: TPCTokenKind;
  LKind: TPCOrdinalKind;
begin
  // Every element converts to the set's element type; in a range set
  // (set of L..H) every element is of the bounds' family (a char range takes
  // chars, a choices range values of its type, else an integer: DoCheckIndex's
  // rule; F50, type_set: 'a' into set of 'a'..'z' was SM0200), inside L..H
  // once both fold
  if not DoSetOf(ASetType, LRange, LElement) then
    Exit(False);
  LKind := okInteger;
  if (LRange <> nil) and (LRange.LowExpr <> nil) and (LRange.LowExpr.ResolvedType <> nil) then
    LKind := DoOrdinalKindOf(LRange.LowExpr.ResolvedType);
  for LItem in ALiteral.Elements do
  begin
    if LItem = nil then
      Continue;
    for LValue in [LItem.LowExpr, LItem.HighExpr] do
    begin
      if (LValue = nil) or (LValue.ResolvedType = nil) or DoIsErrorType(LValue.ResolvedType) or
        DoIsOpaqueTier(LValue.ResolvedType) then
        Continue;
      if LRange <> nil then
      begin
        if LKind in [okChar, okChoices] then
        begin
          if not DoSameOrdinalFamily(LRange.LowExpr.ResolvedType, LValue.ResolvedType) then
            Exit(False);
        end
        else if not (DoTokenOf(LValue, LToken) and DoIsIntegerToken(LToken)) then
          Exit(False);
        if LValue.HasConstValue and (LRange.LowExpr <> nil) and LRange.LowExpr.HasConstValue and
          (DoValueSigned(LValue) < DoValueSigned(LRange.LowExpr)) then
          Exit(False);
        if LValue.HasConstValue and (LRange.HighExpr <> nil) and LRange.HighExpr.HasConstValue and
          (DoValueSigned(LValue) > DoValueSigned(LRange.HighExpr)) then
          Exit(False);
      end
      else if (LElement <> nil) and not DoConvertsImplicitly(LValue, LElement) then
        Exit(False);
    end;
  end;
  Result := True;
end;

procedure TPCSemantics.DoSetLiteral(const ALiteral: TPCSetLiteral);
var
  LItem: TPCSetElement;
  LValue: TPCExpr;
  LFirst: TPCExpr;
  LToken: TPCTokenKind;
  LFirstToken: TPCTokenKind;
  LSameFamily: Boolean;
  LIsConst: Boolean;
  LDerived: TPCDerivedType;
begin
  // semantics.md set literal row: elements of one ordinal type, ranges low <=
  // high when folded; the type is `set of` the first element's type
  LFirst := nil;
  LIsConst := True;
  for LItem in ALiteral.Elements do
  begin
    if LItem = nil then
      Continue;
    DoExpr(LItem.LowExpr);
    DoExpr(LItem.HighExpr);
  end;
  for LItem in ALiteral.Elements do
  begin
    if LItem = nil then
      Continue;
    for LValue in [LItem.LowExpr, LItem.HighExpr] do
    begin
      if LValue = nil then
        Continue;
      if DoIsPoisoned(LValue) then
      begin
        DoPoison(ALiteral);
        Exit;
      end;
      LIsConst := LIsConst and LValue.IsConstExpr;
      if (LValue.ResolvedType = nil) or DoIsErrorType(LValue.ResolvedType) or DoIsOpaqueTier(LValue.ResolvedType) then
        Continue;
      if not DoIsOrdinalType(LValue.ResolvedType) then
      begin
        DoError(LValue, PC_ERR_SEM_266, RSSemTypeSetElement, [LValue.ResolvedType.TypeText()]);
        DoPoison(ALiteral);
        Exit;
      end;
      if LFirst = nil then
      begin
        LFirst := LValue;
        Continue;
      end;
      // Integers of any width are one ordinal family; every other kind is its own type
      DoTokenOf(LFirst, LFirstToken);
      DoTokenOf(LValue, LToken);
      LSameFamily := (DoIsIntegerToken(LFirstToken) and DoIsIntegerToken(LToken)) or
        DoSameType(LFirst.ResolvedType, LValue.ResolvedType);
      if not LSameFamily then
      begin
        DoError(LValue, PC_ERR_SEM_266, RSSemTypeSetMixed,
          [LFirst.ResolvedType.TypeText(), LValue.ResolvedType.TypeText()]);
        DoPoison(ALiteral);
        Exit;
      end;
    end;
    if (LItem.LowExpr <> nil) and (LItem.HighExpr <> nil) and LItem.LowExpr.HasConstValue and
      LItem.HighExpr.HasConstValue and (DoValueSigned(LItem.LowExpr) > DoValueSigned(LItem.HighExpr)) then
    begin
      DoError(LItem.LowExpr, PC_ERR_SEM_267, RSSemTypeLowHigh, [LItem.LowExpr.ExprText(), LItem.HighExpr.ExprText()]);
      DoPoison(ALiteral);
      Exit;
    end;
  end;
  // An empty literal (Target nil) fits every set (DoSetLiteralFits)
  LDerived := FAst.NewNode<TPCDerivedType>();
  LDerived.DerivedKind := dkSetOf;
  if LFirst <> nil then
    LDerived.Target := LFirst.ResolvedType;
  ALiteral.ResolvedType := LDerived;
  ALiteral.IsConstExpr := LIsConst;
end;

procedure TPCSemantics.DoCast(const ACast: TPCCast);
var
  LOperand: TPCExpr;
  LTarget: TPCTypeExpr;
begin
  // A cast has its target type; its legality is C++'s (clang judges the
  // emitted cast); a folded constant's value is PaskalCPP's (below)
  DoTypeExpr(ACast.TargetType);
  DoExpr(ACast.Operand);
  LTarget := ACast.TargetType;
  LOperand := ACast.Operand;
  if (LTarget = nil) or (LOperand = nil) or DoIsErrorType(LTarget) or DoIsPoisoned(LOperand) then
  begin
    DoPoison(ACast);
    Exit;
  end;
  ACast.ResolvedType := LTarget;
  // F48 (type_pointer): a pointer cast takes what its one rule takes
  // (DoPointerCastTakes), or a string literal into a ptr to const char /
  // wchar (it converts with no cast, and C++ takes it); anything else
  // reached clang in C++ words (a const drop: "casts away qualifiers", both
  // targets, scripts\zb_cmpl\f4\pointer\p1_out.txt). An opaque operand is
  // clang's
  if (ACast.CastKind = ckPointer) and (LOperand.ResolvedType <> nil) and
    not DoIsOpaqueTier(LOperand.ResolvedType) and not DoPointerCastTakes(LOperand.ResolvedType, LTarget) and
    not ((LOperand is TPCLiteral) and not (LOperand.ResolvedType is TPCNilType) and
    DoConvertsImplicitly(LOperand, LTarget)) then
  begin
    DoError(LOperand, PC_ERR_SEM_265, RSSemTypeNoPointerCast,
      [LOperand.ResolvedType.TypeText(), LTarget.TypeText()]);
    DoPoison(ACast);
    Exit;
  end;
  // PLAN-RECORDS F-A4b / F-A6a (r4e, a6r): an explicit upcast (ptr to T(x), a
  // C-style or a static cast) is written through the upcast as an implicit
  // one is, a downcast through the runtime downcast (its hops: the upcast's
  // from the target back to the operand); a reinterpret / const / dynamic
  // cast keeps its C++ meaning
  if ACast.CastKind in [ckPointer, ckCStyle, ckStatic] then
  begin
    DoNoteUpcast(LOperand, LTarget);
    if LOperand.ResolvedType <> nil then
      ACast.ResolvedDowncastHops := DoUpcastHops(LTarget, LOperand.ResolvedType);
  end;
  ACast.IsConstExpr := LOperand.IsConstExpr or
    ((LOperand.ResolvedType <> nil) and DoIsOpaqueTier(LOperand.ResolvedType));
  // A builtin / C-style cast of a folded constant to a PaskalCPP integer,
  // bool, char or wchar type folds (F27); the named casts and pointer casts
  // are spelled C++ and stay clang's (folding.md :112-115)
  if ACast.CastKind in [ckBuiltin, ckCStyle] then
    DoFoldConversion(ACast, LOperand, LTarget);
end;

procedure TPCSemantics.DoValueMember(const AMember: TPCMember);
var
  LBase: TPCExpr;
  LBaseType: TPCTypeExpr;
  LCanon: TPCTypeExpr;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
  LToken: TPCTokenKind;
  LFound: TList<TPCNode>;
  LPart: string;
  LRecord: TPCTypeExpr;
  LKind: TPCVarargsKind;
  LHops: Integer;
  LSearchedText: string;
  LDeclItem: TPCMemberItem;
  LPromoted: Boolean;
  LEmbedType: TPCTypeExpr;
  LEmbedText: string;
begin
  // A member of a value (D-A1c-1): a record / object / overlay field or
  // method through '.', the same through '->' on a typed pointer; a member of
  // a string or of opaque C++ is opaque (clang judges LS.c_str())
  LBase := AMember.Base;
  if (AMember.Member = nil) or (LBase = nil) or DoIsPoisoned(AMember) or (AMember.ResolvedKind <> rkNone) then
    Exit;
  // A module head is CORE's (SM0005 / SM0006); a type head that named no
  // choice value (`TPoint.X`) reads a member of a type: not a value (D-A1c-6)
  if ((LBase is TPCName) and (TPCName(LBase).ResolvedKind = rkType)) or
    ((LBase is TPCMember) and (TPCMember(LBase).ResolvedKind = rkType)) then
  begin
    DoNotValue(LBase);
    DoPoison(AMember);
    Exit;
  end;
  if (LBase is TPCName) and (TPCName(LBase).ResolvedKind = rkModule) then
    Exit;
  if (LBase is TPCMember) and (TPCMember(LBase).ResolvedKind = rkModule) then
    Exit;
  LBaseType := LBase.ResolvedType;
  if LBaseType = nil then
    Exit;
  if DoIsErrorType(LBaseType) then
  begin
    DoPoison(AMember);
    Exit;
  end;
  if DoIsOpaqueTier(LBaseType) then
  begin
    AMember.ResolvedType := FAst.OpaqueType();
    Exit;
  end;
  LPart := AMember.Member.PartText;
  LCanon := LBaseType.Canon();
  LSearchedText := LBaseType.TypeText();
  // PLAN-OBJECT O6 (Q2): an own / ref is read as its object (`LO.X`; nil
  // raises at run time); a weak is read through lock(W) (SM0360)
  if (AMember.Access = maDot) and (LCanon is TPCOwnerType) then
  begin
    if TPCOwnerType(LCanon).OwnerKind = okWeak then
    begin
      DoError(AMember, PC_ERR_SEM_360, RSSemCallWeakMember, [LBase.ExprText(), LPart, LBase.ExprText()]);
      DoPoison(AMember);
      Exit;
    end;
    LTarget := TPCOwnerType(LCanon).TargetType;
    if (LTarget = nil) or DoIsErrorType(LTarget) then
    begin
      DoPoison(AMember);
      Exit;
    end;
    if DoIsOpaqueTier(LTarget) then
    begin
      AMember.ResolvedType := FAst.OpaqueType();
      Exit;
    end;
    LCanon := LTarget.Canon();
    LSearchedText := LTarget.TypeText();
  end
  else if AMember.Access = maArrow then
  begin
    if not TPCTypeExpr.PointerOf(LCanon, LTarget, LIsConst) or (LTarget = nil) then
    begin
      DoReportOperands(AMember, '->', LBase, nil);
      Exit;
    end;
    if DoIsOpaqueTier(LTarget) then
    begin
      AMember.ResolvedType := FAst.OpaqueType();
      Exit;
    end;
    LCanon := LTarget.Canon();
    LSearchedText := LTarget.TypeText();
  end
  else if TPCTypeExpr.PointerOf(LCanon, LTarget, LIsConst) then
  begin
    // '.' on a pointer: C++ has no such member; write P^.X or P->X
    DoReportOperands(AMember, '.', LBase, nil);
    Exit;
  end;
  if DoBuiltinOf(LCanon, LToken) and ((LToken = tkKwString) or (LToken = tkKwWstring)) then
  begin
    AMember.ResolvedType := FAst.OpaqueType();
    Exit;
  end;
  // A varargs local (BNF.md sec 6): count is an int32; next / get / reset /
  // copy are typed at their call (DoVarargsLocalCall). The member's kind is
  // written on the node: the emitter lowers it as the same member of varargs
  if DoBuiltinOf(LCanon, LToken) and (LToken = tkKwVarargs) then
  begin
    for LKind := vaCount to vaCopy do
    begin
      if LPart = PC_VARARGS_WORDS[LKind] then
        AMember.ResolvedVarargs := LKind;
    end;
    if AMember.ResolvedVarargs = vaCount then
      AMember.ResolvedType := FAst.BuiltinType(tkKwInt32)
    else if AMember.ResolvedVarargs = vaPlain then
    begin
      DoError(AMember, PC_ERR_SEM_009, RSSemCoreNoMember, [LBaseType.TypeText(), LPart]);
      DoPoison(AMember);
    end;
    Exit;
  end;
  LFound := TList<TPCNode>.Create();
  try
    LHops := 0;
    // The record the access searches: the one rule (TPCScopes.MemberRecord).
    // The parent members stepped through are written for the emitter (M10)
    LRecord := TPCScopes.MemberRecord(LBaseType, AMember.Access);
    if LRecord <> nil then
      TPCScopes.FindMember(LRecord, LPart, LFound, LHops);
    // PLAN-OBJECT O8 (D2): a name the chain does not declare may be an
    // embed's member, reached through its embeds (DoPromote: shared = SM0370,
    // a hidden embed on the way = SM0019); the checks below then judge the
    // member in the last embedded type, as `self.F.X` would. An embed's name
    // is found before a C/C++ parent's (PaskalCPP sees no C++ member; parent.X
    // names that one)
    LPromoted := False;
    if (LFound.Count = 0) and (LRecord <> nil) then
    begin
      if not DoPromote(AMember, LRecord, LSearchedText, LFound, LEmbedType, LEmbedText, LHops) then
        Exit;
      if LFound.Count > 0 then
      begin
        LPromoted := True;
        LRecord := LEmbedType;
        LSearchedText := LEmbedText;
      end;
    end;
    // A name no PaskalCPP level declares, on a record whose parent chain
    // reaches C/C++ (record(CPoint)): that parent's member is clang's (F20),
    // typed opaque as a string's members are; reached through the member
    // parents up to the record that derives from C/C++
    if (LFound.Count = 0) and (LRecord <> nil) and TPCScopes.ReachesOpaque(LRecord, LHops) then
    begin
      AMember.ResolvedParentHops := LHops;
      AMember.ResolvedType := FAst.OpaqueType();
      Exit;
    end;
    if LFound.Count = 0 then
    begin
      // PLAN-OBJECT D3: an object's init / done is never named (its leading
      // init calls never reach here: DoLeadInitCall)
      if (LRecord is TPCRecordType) and TPCRecordType(LRecord).IsObject and
        ((LPart = PC_CONTEXT_WORDS[cwInit].WordText) or (LPart = PC_CONTEXT_WORDS[cwDone].WordText) or
        (LPart = PC_CONTEXT_WORDS[cwCopy].WordText)) then
      begin
        // O5: a copy is an init's kind of member (SM0342 too)
        if LPart = PC_CONTEXT_WORDS[cwInit].WordText then
          DoError(AMember.Member, PC_ERR_SEM_342, RSSemDeclInitByName, [])
        else if LPart = PC_CONTEXT_WORDS[cwCopy].WordText then
          DoError(AMember.Member, PC_ERR_SEM_342, RSSemDeclCopyByName, [])
        else
          DoError(AMember.Member, PC_ERR_SEM_343, RSSemDeclDoneByName, []);
        DoPoison(AMember);
        Exit;
      end;
      DoError(AMember, PC_ERR_SEM_009, RSSemCoreNoMember, [LBaseType.TypeText(), LPart]);
      DoPoison(AMember);
      Exit;
    end;
    // PLAN-OBJECT D10: a hidden member reached from where it may not be. A
    // member is lone: methods do not overload within a type (SM0004), and a
    // level declaring a name twice was reported there
    if (LFound.Count = 1) and DoHiddenBlocks(AMember.Member, LFound[0], LPart, LRecord, LSearchedText,
      (LBase is TPCSpecial) and (TPCSpecial(LBase).SpecialKind = skParent) and not LPromoted, True) then
    begin
      DoPoison(AMember);
      Exit;
    end;
    // PLAN-OBJECT O9: a property is read through its read; an assignment
    // target is judged by DoAssign (DoPropertyAssign)
    if LFound[0] is TPCPropertyItem then
    begin
      DoPropertyRead(AMember, TPCPropertyItem(LFound[0]), LHops);
      Exit;
    end;
    if LFound[0] is TPCField then
    begin
      AMember.ResolvedDecl := LFound[0];
      AMember.ResolvedKind := rkField;
      AMember.ResolvedParentHops := LHops;
      AMember.ResolvedType := DoValueTypeOf(TPCField(LFound[0]).TypeExpr);
      // A field the parser could not finish: resolved, poisoned silently
      if TPCField(LFound[0]).IsRecovered then
        DoPoison(AMember);
    end
    else
    begin
      // A method: the overload pick is A6's
      AMember.ResolvedKind := rkRoutine;
      if LFound.Count = 1 then
        AMember.ResolvedDecl := LFound[0];
      // PLAN-OBJECT D7: parent.M runs that level's own body
      // (an embed's method is its own object's: dispatched as usual)
      if (LFound.Count = 1) and (not LPromoted) and (LBase is TPCSpecial) and
        (TPCSpecial(LBase).SpecialKind = skParent) and
        DoParentAbstract(AMember, LRecord, LFound[0], LSearchedText) then
      begin
        DoPoison(AMember);
        Exit;
      end;
      // PLAN-OBJECT O9: a property's read is const: no method through self;
      // O13b (3): nor in a const method, except a const method
      if DoInConstSelf() and DoRootsAtSelf(LBase) and
        not ((LFound.Count = 1) and DoIsConstMethodDecl(LFound[0])) then
      begin
        DoConstSelfCall(AMember, LPart);
        DoPoison(AMember);
        Exit;
      end;
      // A method may change its object (methods are emitted non-const): one
      // reached through a const object is PaskalCPP's error, not clang's
      // "not marked const" (user 2026-10-13, decision (a)); a const method
      // changes nothing (O13b (3))
      if DoIsConstObject(AMember) and not ((LFound.Count = 1) and DoIsConstMethodDecl(LFound[0])) then
      begin
        DoError(AMember, PC_ERR_SEM_426, RSSemCallConstObject, [LPart]);
        DoPoison(AMember);
        Exit;
      end;
      // PLAN-OBJECT D3: in an init or a done the object is not yet (or no
      // longer) its own type, so a virtual method called through self would
      // not dispatch: SM0348. An embed is built before the body runs and dies
      // after it: its own methods dispatch as usual
      if (LFound.Count = 1) and (not LPromoted) and (FRoutine <> nil) and
        (FRoutine.RoutineKind in [rnInit, rnDone, rnCopy]) and
        (LBase is TPCSpecial) and (TPCSpecial(LBase).SpecialKind = skSelf) then
      begin
        LDeclItem := TPCScopes.MemberItemOf(TPCScopes.DeclaringLevel(LRecord, LFound[0]), LFound[0]);
        if (LDeclItem is TPCMethodItem) and TPCMethodItem(LDeclItem).IsDispatched() then
        begin
          DoError(AMember, PC_ERR_SEM_348, RSSemDeclVirtualInLifecycle, [LPart, LPart]);
          DoPoison(AMember);
        end;
      end;
    end;
  finally
    LFound.Free();
  end;
end;

function TPCSemantics.DoParentAbstract(const AMember: TPCMember; const ARecord: TPCTypeExpr;
  const AFound: TPCNode; const ASearchedText: string): Boolean;
var
  LLevel: TPCTypeExpr;
  LItem: TPCMemberItem;
begin
  // `parent.M` names the parent level's own M (BNF sec 4): an abstract M has
  // no body to call (SM0340 at the member); a reported method stays silent
  Result := False;
  LLevel := TPCScopes.DeclaringLevel(ARecord, AFound);
  if LLevel = nil then
    Exit;
  LItem := TPCScopes.MemberItemOf(LLevel, AFound);
  if not ((LItem is TPCMethodItem) and TPCMethodItem(LItem).IsAbstract) then
    Exit;
  DoError(AMember, PC_ERR_SEM_340, RSSemDeclAbstractCall,
    [DoMethodOwnerName(ARecord, ASearchedText, TPCMethodItem(LItem)), AMember.Member.PartText]);
  Result := True;
end;

function TPCSemantics.DoIsConstObject(const AMember: TPCMember): Boolean;
begin
  // The object a member access reaches is const (DoIsConstBase)
  Result := DoIsConstBase(AMember.Base, AMember.Access);
end;

function TPCSemantics.DoIsConstBase(const ABase: TPCExpr; const AAccess: TPCMemberAccess): Boolean;
var
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
begin
  // The object reached on ABase is const: through '->', a pointer to const;
  // through '.', a base that is a const lvalue (a const parameter or
  // declaration, or a field / index / deref of one: DoIsAddressable's rule).
  // A value that is no lvalue (a call result) is a temporary C++ lets a
  // method change, so it is not const here
  Result := False;
  if (ABase = nil) or (ABase.ResolvedType = nil) then
    Exit;
  if AAccess = maArrow then
  begin
    if TPCTypeExpr.PointerOf(ABase.ResolvedType.Canon(), LTarget, LIsConst) then
      Result := LIsConst;
    Exit;
  end;
  // PLAN-OBJECT O6: the object an own / ref holds is never const (a const
  // owner cannot be pointed elsewhere; its object can still change)
  if ABase.ResolvedType.Canon() is TPCOwnerType then
    Exit;
  // PLAN-OBJECT O9: a bound property's read is its field by const reference
  if DoIsBoundPropertyRead(ABase) then
    Exit(True);
  if DoIsAddressable(ABase, LIsConst) then
    Result := LIsConst;
end;

function TPCSemantics.DoInReadAccessor(): Boolean;
begin
  // PLAN-OBJECT O9: the walk is inside a property's inline read (emitted
  // const: self is const there)
  Result := (FRoutine <> nil) and (FRoutine.RoutineKind = rnRead);
end;

function TPCSemantics.DoInConstSelf(): Boolean;
begin
  // O13b (3): self is const in a property's inline read (O9) and in a
  // const method; both are emitted as C++ const member functions
  Result := DoInReadAccessor() or ((FRoutine <> nil) and (FRoutine.RoutineKind = rnMethod) and FRoutine.IsConst);
end;

procedure TPCSemantics.DoConstSelfChange(const ANode: TPCNode; const ATargetText: string);
begin
  // A write to self's storage where self is const: SM0373 in a read (O9),
  // SM0387 in a const method (O13b (3)); the caller poisons
  if DoInReadAccessor() then
    DoError(ANode, PC_ERR_SEM_373, RSSemDeclPropertyReadChange, [FRoutine.DeclName, ATargetText])
  else
    DoError(ANode, PC_ERR_SEM_387, RSSemDeclConstMethodChange, [FRoutine.DeclName, ATargetText]);
end;

procedure TPCSemantics.DoConstSelfCall(const ANode: TPCNode; const AMethodText: string);
begin
  // A method that is not const called through self where self is const:
  // SM0373 in a read (O9), SM0388 in a const method (O13b (3))
  if DoInReadAccessor() then
    DoError(ANode, PC_ERR_SEM_373, RSSemDeclPropertyReadCall, [FRoutine.DeclName, AMethodText])
  else
    DoError(ANode, PC_ERR_SEM_388, RSSemDeclConstMethodCall, [FRoutine.DeclName, AMethodText]);
end;

class function TPCSemantics.DoIsConstMethodDecl(const ADecl: TPCNode): Boolean;
begin
  // A const method's routine (O13b (3)): it may be called through a const
  // object or self
  Result := (ADecl is TPCRoutine) and (TPCRoutine(ADecl).RoutineKind = rnMethod) and TPCRoutine(ADecl).IsConst;
end;

function TPCSemantics.DoConstNotKept(const AHave: TPCRoutine; const AWant: TPCRoutine;
  const AWantOwner: string): Boolean;
var
  LWord: string;
begin
  // O13b (3): an override, or a method that implements an interface's,
  // keeps the const of the method it continues (C++ overrides a const member
  // function only with a const one): SM0389 at AHave's name, a note at AWant.
  // True = reported
  Result := False;
  if (AHave = nil) or (AWant = nil) or (AHave.IsConst = AWant.IsConst) then
    Exit;
  if AWant.IsConst then
    LWord := RSSemDeclConstWord
  else
    LWord := RSSemDeclNotConstWord;
  if DoReportRange(AHave.NameRange, esError, PC_ERR_SEM_389, RSSemDeclConstDiffers,
    [AHave.DeclName, LWord, AWant.DeclName, AWantOwner]) then
    DoNote(AWant, RSSemDeclMemberHere, [AWantOwner, AWant.DeclName]);
  Result := True;
end;

function TPCSemantics.DoInOwnAccessor(const AAccessor: TPCAccessorItem): Boolean;
begin
  // The walk is inside AAccessor's own inline routine
  Result := (AAccessor <> nil) and (AAccessor.Routine <> nil) and (FRoutine = AAccessor.Routine);
end;

class function TPCSemantics.DoRootsAtSelf(const AExpr: TPCExpr): Boolean;
var
  LExpr: TPCExpr;
  LBase: TPCExpr;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
begin
  // A place in self's own storage: self / parent, or a field / an element of
  // one ('.' and indexing). A deref, '->', or the object an own / ref holds
  // leaves self's storage (a const method may change those)
  LExpr := AExpr;
  while LExpr <> nil do
  begin
    if LExpr is TPCSpecial then
      Exit(TPCSpecial(LExpr).SpecialKind in [skSelf, skParent]);
    if (LExpr is TPCMember) and (TPCMember(LExpr).Access = maDot) and
      (TPCMember(LExpr).ResolvedKind in [rkField, rkNone]) then
      LBase := TPCMember(LExpr).Base
    else if LExpr is TPCIndex then
      LBase := TPCIndex(LExpr).Base
    else
      Exit(False);
    if (LBase = nil) or (LBase.ResolvedType = nil) then
      Exit(False);
    if (LBase.ResolvedType.Canon() is TPCOwnerType) or TPCTypeExpr.PointerOf(LBase.ResolvedType, LTarget, LIsConst) then
      Exit(False);
    LExpr := LBase;
  end;
  Result := False;
end;

function TPCSemantics.DoIsBoundPropertyRead(const AExpr: TPCExpr): Boolean;
begin
  // A read of a property that gives its bound field by const reference
  // (TPCPropertyItem.ReadsByReference): it is the field, read-only
  Result := (AExpr is TPCMember) and (TPCMember(AExpr).ResolvedKind = rkProperty) and
    (TPCMember(AExpr).ResolvedDecl is TPCPropertyItem) and
    TPCPropertyItem(TPCMember(AExpr).ResolvedDecl).ReadsByReference();
end;

class function TPCSemantics.DoIsPropertyAccess(const AExpr: TPCExpr): Boolean;
begin
  // A property read or written: `LO.X`, `LO.Items[i]`, `LO[i]` (a default
  // property): never storage (O9 / O10)
  Result := ((AExpr is TPCMember) and (TPCMember(AExpr).ResolvedKind = rkProperty)) or
    ((AExpr is TPCIndex) and (TPCIndex(AExpr).ResolvedProperty <> nil));
end;

procedure TPCSemantics.DoPropertyRead(const AMember: TPCMember; const AProperty: TPCPropertyItem;
  const AHops: Integer);
begin
  // PLAN-OBJECT O9 / D12: a property's value is what its read gives: a value
  // of its type, never storage (no var, no address: SM0405 / SM0376). Read
  // through self in its own read it runs that read again, forever: SM0374
  // (an assignment target is DoPropertyAssign's: FAssignTarget)
  AMember.ResolvedDecl := AProperty;
  AMember.ResolvedKind := rkProperty;
  AMember.ResolvedParentHops := AHops;
  AMember.ResolvedType := DoValueTypeOf(AProperty.TypeExpr);
  if AProperty.IsRecovered then
  begin
    DoPoison(AMember);
    Exit;
  end;
  // O10: an indexed property is reached through its index (LO.Items[i]:
  // DoIndexedProperty, FIndexBase)
  if (AProperty.IndexParam <> nil) and (AMember <> FIndexBase) then
  begin
    DoError(AMember.Member, PC_ERR_SEM_378, RSSemDeclPropertyNeedsIndex, [AProperty.PropName, AProperty.PropName]);
    DoPoison(AMember);
    Exit;
  end;
  if (AMember = FAssignTarget) or not DoInOwnAccessor(AProperty.ReadItem) then
    Exit;
  if (AMember.Base is TPCSpecial) and (Length(AMember.ResolvedEmbedPath) = 0) then
  begin
    DoError(AMember.Member, PC_ERR_SEM_374, RSSemDeclPropertyOwnRead, [AProperty.PropName]);
    DoPoison(AMember);
  end;
end;

procedure TPCSemantics.DoPropertyAssign(const AAssign: TPCAssign; const AProperty: TPCPropertyItem;
  const ATarget: TPCExpr; const ABase: TPCExpr; const AAccess: TPCMemberAccess; const AAt: TPCNode;
  const AEmbedded: Boolean);
var
  LRecord: TPCTypeExpr;
  LWrite: TPCAccessorItem;
  LText: string;
  LRange: TPCSetType;
  LElement: TPCTypeExpr;
begin
  // PLAN-OBJECT O9 / O10 (D12): `X := v` runs X's write with v (a value of
  // X's type), `X OP= v` reads, operates and writes (object, index, value,
  // read, write, once each). ATarget = the member (`LO.X`) or the index
  // (`LO.Items[i]`, `LO[i]`), ABase / AAccess = the object it is reached on,
  // AAt = where a report about the property goes (its name, or the default
  // property's index). A statement only (SM0377: the write has no value);
  // never in a read (SM0373: self is const there); a write-less property is
  // read-only (SM0375: the write that runs, DoRunningWrite); assigned
  // through self in its own write it runs that write again (SM0374); a
  // hidden write is reached where a hidden member is (SM0019); a const
  // object has no write (SM0255)
  AAssign.ResolvedType := ATarget.ResolvedType;
  if AAssign <> FStmtAssign then
  begin
    DoError(AAssign, PC_ERR_SEM_377, RSSemDeclPropertyAssignValue, [AProperty.PropName]);
    DoPoison(AAssign);
    Exit;
  end;
  if DoInConstSelf() and DoRootsAtSelf(ABase) then
  begin
    DoConstSelfChange(ATarget, ATarget.ExprText());
    DoPoison(AAssign);
    Exit;
  end;
  // O10: the write that runs (an override may restate its read only)
  LRecord := TPCScopes.MemberRecord(ABase.ResolvedType, AAccess);
  LWrite := nil;
  if LRecord <> nil then
    LWrite := DoRunningWrite(LRecord, AProperty);
  if LWrite = nil then
  begin
    DoError(AAt, PC_ERR_SEM_375, RSSemDeclPropertyNoWrite, [AProperty.PropName]);
    DoPoison(AAssign);
    Exit;
  end;
  if DoInOwnAccessor(LWrite) and (ABase is TPCSpecial) and not AEmbedded then
  begin
    DoError(AAt, PC_ERR_SEM_374, RSSemDeclPropertyOwnWrite, [AProperty.PropName]);
    DoPoison(AAssign);
    Exit;
  end;
  if LWrite.IsHidden and not AProperty.IsHidden then
  begin
    // The searched type's text as DoValueMember prints it (an owner's object)
    LText := ABase.ResolvedType.TypeText();
    if ABase.ResolvedType.Canon() is TPCOwnerType then
      LText := TPCOwnerType(ABase.ResolvedType.Canon()).TargetType.TypeText();
    if (LRecord <> nil) and DoHiddenBlocks(AAt, LWrite, AProperty.PropName, LRecord,
      LText, (ABase is TPCSpecial) and (TPCSpecial(ABase).SpecialKind = skParent), True) then
    begin
      DoPoison(AAssign);
      Exit;
    end;
  end;
  if DoIsConstBase(ABase, AAccess) then
  begin
    DoError(ATarget, PC_ERR_SEM_255, RSSemTypeNotAssignable, [ATarget.ExprText()]);
    DoPoison(AAssign);
    Exit;
  end;
  if AAssign.Op = aoAssign then
  begin
    DoCheckConvert(AAssign.ValueExpr, ATarget.ResolvedType);
    Exit;
  end;
  if DoNotValue(AAssign.ValueExpr) then
  begin
    DoPoison(AAssign);
    Exit;
  end;
  // A compound one means what it means on a value of the type (a set's own
  // operator: DoCheckSetAssign; every other one is C++'s on the value read)
  if DoSetOf(ATarget.ResolvedType, LRange, LElement) then
    DoCheckSetAssign(AAssign);
end;

function TPCSemantics.DoOwnInits(const ARecord: TPCRecordType): TList<TPCInitItem>;
var
  LItem: TPCMemberItem;
begin
  // PLAN-OBJECT D3: the inits a type declares itself, in declaration order
  // (C++ inherits no constructor); a copy is no init (O5: it never builds a
  // construction). The caller frees the list
  Result := TList<TPCInitItem>.Create();
  if ARecord = nil then
    Exit;
  for LItem in ARecord.Members do
  begin
    if (LItem is TPCInitItem) and not (LItem is TPCCopyItem) then
      Result.Add(TPCInitItem(LItem));
  end;
end;

function TPCSemantics.DoInitWithoutArgs(const ARecord: TPCRecordType): TPCInitItem;
var
  LInits: TList<TPCInitItem>;
  LInit: TPCInitItem;
begin
  // The init a type is built with when no argument is given: the one that
  // takes none; nil = none declared
  Result := nil;
  LInits := DoOwnInits(ARecord);
  try
    for LInit in LInits do
    begin
      if (LInit.Routine <> nil) and (LInit.Routine.Params.Count = 0) then
        Exit(LInit);
    end;
  finally
    LInits.Free();
  end;
end;

function TPCSemantics.DoNeedsInitArgs(const ARecord: TPCRecordType): Boolean;
var
  LInits: TList<TPCInitItem>;
begin
  // A type that declares inits and none taking no argument: nothing builds
  // it without arguments (C++ has no default constructor then)
  LInits := DoOwnInits(ARecord);
  try
    Result := (LInits.Count > 0) and (DoInitWithoutArgs(ARecord) = nil);
  finally
    LInits.Free();
  end;
end;

function TPCSemantics.DoIsLeadInitStmt(const ARecord: TPCRecordType; const AStmt: TPCStmt;
  out ACall: TPCCall; out AField: TPCField): Boolean;
var
  LCall: TPCCall;
  LMember: TPCMember;
  LAccess: TPCMember;
  LItem: TPCMemberItem;
begin
  // A statement `parent.init(...);` (AField nil) or `self.F.init(...);`
  // with F a field ARecord declares itself (AField = F), told by its shape
  // alone: what F's type is, DoLeadInitCall judges
  Result := False;
  ACall := nil;
  AField := nil;
  if not (AStmt is TPCExprStmt) or not (TPCExprStmt(AStmt).Expr is TPCCall) then
    Exit;
  LCall := TPCCall(TPCExprStmt(AStmt).Expr);
  if not (LCall.Callee is TPCMember) then
    Exit;
  LMember := TPCMember(LCall.Callee);
  if (LMember.Access <> maDot) or (LMember.Member = nil) or
    (LMember.Member.PartText <> PC_CONTEXT_WORDS[cwInit].WordText) then
    Exit;
  if (LMember.Base is TPCSpecial) and (TPCSpecial(LMember.Base).SpecialKind = skParent) then
  begin
    ACall := LCall;
    Exit(True);
  end;
  if not (LMember.Base is TPCMember) then
    Exit;
  LAccess := TPCMember(LMember.Base);
  if (LAccess.Access <> maDot) or (LAccess.Member = nil) or not (LAccess.Base is TPCSpecial) or
    (TPCSpecial(LAccess.Base).SpecialKind <> skSelf) then
    Exit;
  for LItem in ARecord.Members do
  begin
    if (LItem is TPCField) and (TPCField(LItem).FieldName = LAccess.Member.PartText) then
    begin
      ACall := LCall;
      AField := TPCField(LItem);
      Exit(True);
    end;
  end;
end;

procedure TPCSemantics.DoMarkLeadInits(const ARecord: TPCRecordType; const AItem: TPCInitItem);
var
  LStmt: TPCStmt;
  LCall: TPCCall;
  LField: TPCField;
  LLastField: TPCField;
  LCount: Integer;
begin
  // D3: an init begins with its leading init calls, parent.init(...) first,
  // then self.F.init(...) for the type's own fields in declaration order,
  // each once; the run ends at the first other statement. Marked before the
  // body is walked (TPCCall.IsLeadInit / ResolvedInitField,
  // TPCInitItem.ResolvedLeadCount): DoExpr hands them to DoLeadInitCall and
  // never walks their '.init' (SM0342 is for every other use). A misplaced
  // one is reported (SM0344 / SM0345), poisoned, and ends the run
  AItem.ResolvedLeadCount := 0;
  if (AItem.Routine = nil) or (AItem.Routine.Body = nil) then
    Exit;
  LCount := 0;
  LLastField := nil;
  for LStmt in AItem.Routine.Body.Stmts do
  begin
    if not DoIsLeadInitStmt(ARecord, LStmt, LCall, LField) then
      Break;
    // O5: a copy's parent part is the parent's own copy (`: Base(ASource)`)
    if (LField = nil) and (AItem is TPCCopyItem) then
    begin
      DoError(LCall, PC_ERR_SEM_356, RSSemDeclCopyParentInit, []);
      DoPoison(LCall.Callee);
      DoPoison(LCall);
      Break;
    end;
    if (LField = nil) and (LCount > 0) then
    begin
      DoError(LCall, PC_ERR_SEM_344, RSSemDeclParentInitFirst, []);
      DoPoison(LCall.Callee);
      DoPoison(LCall);
      Break;
    end;
    if (LField <> nil) and (LLastField <> nil) and
      (ARecord.Members.IndexOf(LField) <= ARecord.Members.IndexOf(LLastField)) then
    begin
      if LField = LLastField then
        DoError(LCall, PC_ERR_SEM_345, RSSemDeclFieldInitTwice, [LField.FieldName])
      else
        DoError(LCall, PC_ERR_SEM_345, RSSemDeclFieldInitOrder, [LField.FieldName, LLastField.FieldName]);
      DoPoison(LCall.Callee);
      DoPoison(LCall);
      Break;
    end;
    if LField <> nil then
      LLastField := LField;
    LCall.IsLeadInit := True;
    LCall.ResolvedInitField := LField;
    Inc(LCount);
  end;
  AItem.ResolvedLeadCount := LCount;
end;

procedure TPCSemantics.DoCheckLeadArgs(const ACall: TPCCall);
var
  LArg: TPCExpr;
  LVisit: TPCNodeVisitor;
  LText: string;
begin
  // D3: a leading init call runs in the C++ member-init list, before the
  // object and the init's locals exist: its arguments name neither self,
  // parent nor a local of the init (SM0346 at the name). Parameters,
  // constants and module names are there
  LText := DoCalleeText(ACall);
  LVisit :=
    procedure(const ANode: TPCNode)
    begin
      if (ANode is TPCSpecial) and (TPCSpecial(ANode).SpecialKind in [skSelf, skParent]) then
        DoError(ANode, PC_ERR_SEM_346, RSSemDeclLeadArgEarly, [TPCSpecial(ANode).ExprText(), LText])
      else if (ANode is TPCName) and (TPCName(ANode).ResolvedDecl is TPCVarDecl) and (FRoutine <> nil) and
        FRoutine.Decls.Contains(TPCStmt(TPCName(ANode).ResolvedDecl)) then
        DoError(ANode, PC_ERR_SEM_346, RSSemDeclLeadArgEarly, [TPCName(ANode).ExprText(), LText]);
      ANode.EnumChildren(LVisit);
    end;
  try
    for LArg in ACall.Args do
    begin
      if LArg <> nil then
        LVisit(LArg);
    end;
  finally
    // The visitor captures itself: clear it to break the reference cycle
    LVisit := nil;
  end;
end;

procedure TPCSemantics.DoLeadInitCall(const ACall: TPCCall);
var
  LMember: TPCMember;
  LArg: TPCExpr;
  LPart: TPCTypeExpr;
  LCanon: TPCTypeExpr;
begin
  // D3: parent.init(...) / self.F.init(...) at the start of an init
  // (DoMarkLeadInits): its base is typed as a member base (parent) or a
  // member access (self.F), its arguments as any call's, and the part's
  // init is picked (DoBuildWith); its '.init' is never walked as a member.
  // A part that is no object is SM0350
  LMember := TPCMember(ACall.Callee);
  if LMember.Base is TPCSpecial then
    DoSpecial(TPCSpecial(LMember.Base), True)
  else
    DoExpr(LMember.Base);
  for LArg in ACall.Args do
    DoExpr(LArg);
  DoCheckLeadArgs(ACall);
  ACall.ResolvedType := FAst.VoidType();
  LPart := LMember.Base.ResolvedType;
  if (LPart = nil) or DoIsPoisoned(LMember.Base) or DoIsErrorType(LPart) then
  begin
    DoPoison(ACall);
    Exit;
  end;
  // A C/C++ part (a field of a C++ class type, a C++ parent) is built by its
  // C++ constructor: clang judges the arguments (DESIGN sec 2)
  if DoIsOpaqueTier(LPart) then
    Exit;
  LCanon := LPart.Canon();
  if not ((LCanon is TPCRecordType) and TPCRecordType(LCanon).IsObject) then
  begin
    DoError(ACall, PC_ERR_SEM_350, RSSemDeclInitArgsNotObject, [LPart.TypeText()]);
    DoPoison(ACall);
    Exit;
  end;
  if DoBuildWith(ACall, TPCRecordType(LCanon), LPart.TypeText()) and (ACall.ResolvedInit <> nil) then
  begin
    LMember.ResolvedKind := rkRoutine;
    LMember.ResolvedDecl := ACall.ResolvedInit.Routine;
    ACall.ResolvedKind := rkRoutine;
    ACall.ResolvedDecl := ACall.ResolvedInit.Routine;
  end;
end;

function TPCSemantics.DoBuildWith(const ACall: TPCCall; const ARecord: TPCRecordType; const ATypeText: string): Boolean;
var
  LInits: TList<TPCInitItem>;
  LTaken: TList<TPCInitItem>;
  LExact: TList<TPCInitItem>;
  LInit: TPCInitItem;
  LIndex: Integer;
  LSame: Boolean;
begin
  // D3: the init a construction (TPCVarDecl.InitCall) or a leading init call
  // runs, from the part's own inits. None declared: built without arguments
  // (SM0351 for any). Of the inits PaskalCPP's conversions accept
  // (DoTargetTakes, the overload rule, arity included): none = SM0351 with
  // every init a note; several = the one whose parameter types are the
  // arguments' own types, else SM0352 with the candidates as notes; one =
  // written (ResolvedInit), its arguments checked (DoCheckArgs). True = the
  // call is resolved (ResolvedInit may stay nil: no init declared)
  Result := False;
  LInits := DoOwnInits(ARecord);
  LTaken := TList<TPCInitItem>.Create();
  LExact := TList<TPCInitItem>.Create();
  try
    if LInits.Count = 0 then
    begin
      if ACall.Args.Count > 0 then
      begin
        DoError(ACall, PC_ERR_SEM_351, RSSemDeclNoInitDeclared, [ATypeText]);
        DoPoison(ACall);
        Exit;
      end;
      Exit(True);
    end;
    if not DoArgsReady(ACall) then
      Exit;
    for LInit in LInits do
    begin
      if (LInit.Routine <> nil) and DoTargetTakes(ACall, DoRoutineTarget(LInit.Routine)) then
        LTaken.Add(LInit);
    end;
    if LTaken.Count > 1 then
    begin
      for LInit in LTaken do
      begin
        LSame := True;
        for LIndex := 0 to LInit.Routine.Params.Count - 1 do
        begin
          if (LInit.Routine.Params[LIndex] = nil) or (ACall.Args[LIndex].ResolvedType = nil) or
            not DoSameType(ACall.Args[LIndex].ResolvedType, DoValueTypeOf(LInit.Routine.Params[LIndex].TypeExpr)) then
            LSame := False;
        end;
        if LSame then
          LExact.Add(LInit);
      end;
      if LExact.Count = 1 then
      begin
        LTaken.Clear();
        LTaken.Add(LExact[0]);
      end;
    end;
    if LTaken.Count = 0 then
    begin
      if DoError(ACall, PC_ERR_SEM_351, RSSemDeclNoInitTakes, [ATypeText, DoArgTypesText(ACall)]) then
      begin
        for LInit in LInits do
        begin
          if LInit.Routine <> nil then
            DoNote(LInit.Routine, RSSemDeclInitHere, [ATypeText, DoParamTypesText(DoRoutineTarget(LInit.Routine))]);
        end;
      end;
      DoPoison(ACall);
      Exit;
    end;
    if LTaken.Count > 1 then
    begin
      if DoError(ACall, PC_ERR_SEM_352, RSSemDeclInitAmbiguous, [DoArgTypesText(ACall), ATypeText]) then
      begin
        for LInit in LTaken do
          DoNote(LInit.Routine, RSSemDeclInitHere, [ATypeText, DoParamTypesText(DoRoutineTarget(LInit.Routine))]);
      end;
      DoPoison(ACall);
      Exit;
    end;
    ACall.ResolvedInit := LTaken[0];
    DoCheckArgs(ACall, DoRoutineTarget(LTaken[0].Routine));
    Result := True;
  finally
    LExact.Free();
    LTaken.Free();
    LInits.Free();
  end;
end;

procedure TPCSemantics.DoConstruct(const ADecl: TPCVarDecl);
var
  LCanon: TPCTypeExpr;
  LArg: TPCExpr;
  LIsObject: Boolean;
begin
  // D3 / Q1: a variable of an object type is built by an init: with its
  // list (`LV: T(args)`: DoBuildWith on TPCVarDecl.InitCall), else by the
  // init taking no argument (ResolvedInit; SM0349 when the type has inits
  // and none of them takes none). A list on any other type is SM0350. An
  // array variable builds every element without arguments
  // (DoCheckDefaultBuild); a copy (`= value`) and an external variable are
  // built elsewhere
  if ADecl.InitCall <> nil then
  begin
    for LArg in ADecl.InitCall.Args do
      DoExpr(LArg);
    ADecl.InitCall.ResolvedType := FAst.VoidType();
  end;
  if (ADecl.TypeExpr = nil) or DoIsErrorType(ADecl.TypeExpr) then
    Exit;
  LCanon := ADecl.TypeExpr.Canon();
  LIsObject := (LCanon is TPCRecordType) and TPCRecordType(LCanon).IsObject;
  if ADecl.InitCall <> nil then
  begin
    // A C/C++ type's list goes to its C++ constructor: clang judges it
    // (DESIGN sec 2), nothing is picked here
    if DoIsOpaqueTier(ADecl.TypeExpr) then
      Exit;
    if not LIsObject then
    begin
      DoError(ADecl.InitCall, PC_ERR_SEM_350, RSSemDeclInitArgsNotObject, [ADecl.TypeExpr.TypeText()]);
      Exit;
    end;
    if DoBuildWith(ADecl.InitCall, TPCRecordType(LCanon), ADecl.TypeExpr.TypeText()) and
      (ADecl.InitCall.ResolvedInit <> nil) then
    begin
      ADecl.InitCall.ResolvedKind := rkRoutine;
      ADecl.InitCall.ResolvedDecl := ADecl.InitCall.ResolvedInit.Routine;
    end;
    Exit;
  end;
  if (ADecl.InitExpr <> nil) or ADecl.ExternalClause.IsExternal then
    Exit;
  if LIsObject then
  begin
    ADecl.ResolvedInit := DoInitWithoutArgs(TPCRecordType(LCanon));
    if (ADecl.ResolvedInit = nil) and DoNeedsInitArgs(TPCRecordType(LCanon)) then
      DoError(ADecl.TypeExpr, PC_ERR_SEM_349, RSSemDeclNoDefaultInit,
        [ADecl.TypeExpr.TypeText(), ADecl.TypeExpr.TypeText()]);
    Exit;
  end;
  DoCheckDefaultBuild(ADecl.TypeExpr, ADecl.TypeExpr);
end;

procedure TPCSemantics.DoCheckDefaultBuild(const AType: TPCTypeExpr; const AAt: TPCNode);
var
  LCanon: TPCTypeExpr;
begin
  // D3: what C++ builds without arguments (an array's elements, the object
  // create builds): an object type that has inits needs one taking none
  // (SM0349 at AAt; an array reports at its element type)
  if (AType = nil) or DoIsErrorType(AType) then
    Exit;
  if AType is TPCArrayType then
  begin
    DoCheckDefaultBuild(TPCArrayType(AType).ElementType, TPCArrayType(AType).ElementType);
    Exit;
  end;
  LCanon := AType.Canon();
  if (LCanon is TPCRecordType) and TPCRecordType(LCanon).IsObject and DoNeedsInitArgs(TPCRecordType(LCanon)) then
    DoError(AAt, PC_ERR_SEM_349, RSSemDeclNoDefaultInit, [AType.TypeText(), AType.TypeText()]);
end;

function TPCSemantics.DoLeadsWith(const ARecord: TPCRecordType; const AItem: TPCInitItem;
  const AField: TPCField): Boolean;
var
  LStmt: TPCStmt;
  LCall: TPCCall;
  LField: TPCField;
begin
  // The init's statements build that part (AField nil = the parent): a
  // leading call, or one written out of place (already reported: SM0344 /
  // SM0345 / SM0342), so a part is never reported missing as well
  Result := False;
  if (AItem.Routine = nil) or (AItem.Routine.Body = nil) then
    Exit;
  for LStmt in AItem.Routine.Body.Stmts do
  begin
    if DoIsLeadInitStmt(ARecord, LStmt, LCall, LField) and (LField = AField) then
      Exit(True);
  end;
end;

procedure TPCSemantics.DoCheckLifecycle(const ARecord: TPCRecordType);
var
  LItem: TPCMemberItem;
  LDone: TPCDoneItem;
  LInits: TList<TPCInitItem>;
  LRoutines: TList<TPCRoutine>;
  LInit: TPCInitItem;
  LParent: TPCTypeExpr;
  LField: TPCField;
  LFieldType: TPCTypeExpr;
  LName: string;
  LCopy: TPCCopyItem;
begin
  // D3, after the members: one done (SM0341 at each later one); the inits
  // differ in their parameter types (SM0324, the overload rule); a parent
  // or an own object field that has no init without arguments is built by
  // a leading call of every init (SM0347 at an init lacking it, or at the
  // parent / the field when the type declares no init). O5: a copy builds
  // such a field the same way (SM0347 at the copy lacking it)
  if not ARecord.IsObject then
    Exit;
  // The fact the emitter reads for a field of this type (no `{}`)
  ARecord.ResolvedNeedsInitArgs := DoNeedsInitArgs(ARecord);
  LName := DoDefiningName(ARecord);
  LDone := nil;
  for LItem in ARecord.Members do
  begin
    if not (LItem is TPCDoneItem) then
      Continue;
    if LDone <> nil then
      DoError(LItem, PC_ERR_SEM_341, RSSemDeclOneDone, [LName])
    else
      LDone := TPCDoneItem(LItem);
  end;
  // O5: one copy of the right shape, its parent copyable; it builds the
  // type's own fields as an init does (the field rule below asks it too)
  LCopy := DoCheckCopyMember(ARecord, LName);
  LInits := DoOwnInits(ARecord);
  LRoutines := TList<TPCRoutine>.Create();
  try
    for LInit in LInits do
    begin
      if LInit.Routine <> nil then
        LRoutines.Add(LInit.Routine);
    end;
    DoCheckDistinctParams(LRoutines);
    if (ARecord.ParentName <> nil) and not DoIsErrorType(ARecord.ParentName) and
      not DoIsOpaqueTier(ARecord.ParentName) then
    begin
      LParent := ARecord.ParentName.Canon();
      if (LParent is TPCRecordType) and TPCRecordType(LParent).IsObject and
        DoNeedsInitArgs(TPCRecordType(LParent)) then
      begin
        if LInits.Count = 0 then
          DoError(ARecord.ParentName, PC_ERR_SEM_347, RSSemDeclParentNeedsInit, [ARecord.ParentName.TypeText(), LName])
        else
        begin
          for LInit in LInits do
          begin
            if not DoLeadsWith(ARecord, LInit, nil) then
              DoError(LInit, PC_ERR_SEM_347, RSSemDeclParentNeedsInit, [ARecord.ParentName.TypeText(), LName]);
          end;
        end;
      end;
    end;
    for LItem in ARecord.Members do
    begin
      if not (LItem is TPCField) then
        Continue;
      LField := TPCField(LItem);
      if (LField.TypeExpr = nil) or DoIsErrorType(LField.TypeExpr) then
        Continue;
      LFieldType := LField.TypeExpr.Canon();
      if not ((LFieldType is TPCRecordType) and TPCRecordType(LFieldType).IsObject and
        DoNeedsInitArgs(TPCRecordType(LFieldType))) then
        Continue;
      if LInits.Count = 0 then
        DoError(LField, PC_ERR_SEM_347, RSSemDeclFieldNeedsInit,
          [LField.FieldName, LField.TypeExpr.TypeText(), LName, LField.FieldName])
      else
      begin
        for LInit in LInits do
        begin
          if not DoLeadsWith(ARecord, LInit, LField) then
            DoError(LInit, PC_ERR_SEM_347, RSSemDeclFieldNeedsInit,
              [LField.FieldName, LField.TypeExpr.TypeText(), LName, LField.FieldName]);
        end;
      end;
      if (LCopy <> nil) and not DoLeadsWith(ARecord, LCopy, LField) then
        DoError(LCopy, PC_ERR_SEM_347, RSSemDeclFieldNeedsInit,
          [LField.FieldName, LField.TypeExpr.TypeText(), LName, LField.FieldName]);
    end;
  finally
    LRoutines.Free();
    LInits.Free();
  end;
end;

function TPCSemantics.DoCheckCopyMember(const ARecord: TPCRecordType; const AName: string): TPCCopyItem;
var
  LItem: TPCMemberItem;
  LParam: TPCParam;
  LParamType: TPCTypeExpr;
  LShapeOk: Boolean;
begin
  // O5 / D5, after the members: the copy the object declares (nil = none).
  // One (SM0354 at each later one); it takes one const parameter of the
  // object's own type (SM0353 there); its parent part is the parent's copy,
  // so a parent that cannot be copied is SM0355 at the parent
  Result := nil;
  for LItem in ARecord.Members do
  begin
    if not (LItem is TPCCopyItem) then
      Continue;
    if Result <> nil then
      DoError(LItem, PC_ERR_SEM_354, RSSemDeclOneCopy, [AName])
    else
      Result := TPCCopyItem(LItem);
  end;
  if (Result = nil) or (Result.Routine = nil) then
    Exit;
  LShapeOk := Result.Routine.Params.Count = 1;
  LParam := nil;
  if Result.Routine.Params.Count > 0 then
    LParam := Result.Routine.Params[0];
  if LShapeOk then
  begin
    if (LParam = nil) or (LParam.TypeExpr = nil) or DoIsErrorType(LParam.TypeExpr) then
      LShapeOk := True
    else
    begin
      LParamType := LParam.TypeExpr.Canon();
      LShapeOk := (LParam.ParamMode = pmConst) and (LParamType = ARecord);
    end;
  end;
  if not LShapeOk then
  begin
    if LParam <> nil then
      DoError(LParam, PC_ERR_SEM_353, RSSemDeclCopyShape, [AName])
    else
      DoError(Result, PC_ERR_SEM_353, RSSemDeclCopyShape, [AName]);
  end;
  if (ARecord.ParentName = nil) or DoIsErrorType(ARecord.ParentName) or DoIsOpaqueTier(ARecord.ParentName) then
    Exit;
  if TPCTypeExpr.MoveOnlyReasonOf(ARecord.ParentName) <> nil then
  begin
    if DoError(ARecord.ParentName, PC_ERR_SEM_355, RSSemDeclCopyParent, [AName, ARecord.ParentName.TypeText()]) then
      DoNoteMoveOnly(ARecord.ParentName);
  end;
end;

procedure TPCSemantics.DoOwnerNew(const ANew: TPCOwnerNew);
var
  LArg: TPCExpr;
  LTarget: TPCTypeExpr;
  LCanon: TPCTypeExpr;
  LRecord: TPCRecordType;
begin
  // PLAN-OBJECT O6 (D4, Q1): `own T(args)` / `ref T(args)` builds a T on the
  // heap with the init the arguments pick (DoBuildWith, as `LV: T(args)`), or
  // the one taking none (SM0349 when T has inits and none takes none); an
  // abstract T is SM0338 (DoCheckConcrete). A weak builds nothing: SM0359. A
  // C/C++ class's arguments go to its C++ constructor (clang's). The
  // expression's type is the owner type as written
  DoTypeExpr(ANew.OwnerType);
  if ANew.InitCall <> nil then
  begin
    for LArg in ANew.InitCall.Args do
      DoExpr(LArg);
    ANew.InitCall.ResolvedType := FAst.VoidType();
  end;
  ANew.ResolvedType := ANew.OwnerType;
  if (ANew.OwnerType = nil) or (ANew.InitCall = nil) or DoIsErrorType(ANew.OwnerType) then
    Exit;
  if ANew.OwnerType.OwnerKind = okWeak then
  begin
    DoError(ANew.OwnerType, PC_ERR_SEM_359, RSSemDeclWeakNew, [ANew.OwnerType.TypeText(), ANew.OwnerType.TargetType.TypeText()]);
    DoPoison(ANew);
    Exit;
  end;
  LTarget := ANew.OwnerType.TargetType;
  if DoIsOpaqueTier(LTarget) then
    Exit;
  LCanon := LTarget.Canon();
  if not ((LCanon is TPCRecordType) and TPCRecordType(LCanon).IsObject) then
    Exit;
  LRecord := TPCRecordType(LCanon);
  DoCheckConcrete(LTarget, LTarget);
  if ANew.InitCall.Args.Count > 0 then
  begin
    if DoBuildWith(ANew.InitCall, LRecord, LTarget.TypeText()) and (ANew.InitCall.ResolvedInit <> nil) then
    begin
      ANew.ResolvedInit := ANew.InitCall.ResolvedInit;
      ANew.InitCall.ResolvedKind := rkRoutine;
      ANew.InitCall.ResolvedDecl := ANew.InitCall.ResolvedInit.Routine;
    end;
    Exit;
  end;
  ANew.ResolvedInit := DoInitWithoutArgs(LRecord);
  if (ANew.ResolvedInit = nil) and DoNeedsInitArgs(LRecord) then
    DoError(LTarget, PC_ERR_SEM_349, RSSemDeclNoDefaultInit, [LTarget.TypeText(), LTarget.TypeText()]);
end;

procedure TPCSemantics.DoTypeTest(const ATest: TPCTypeTest);
var
  LObject: TPCRecordType;
  LObjectType: TPCTypeExpr;
  LTarget: TPCRecordType;
  LForm: TPCTypeExpr;
  LConstTarget: Boolean;
  LPointee: TPCTypeExpr;
  LConst: Boolean;
  LIsPointer: Boolean;
begin
  // PLAN-OBJECT O12 (D15): `X is T` / `X as T`. X is a polymorphic object,
  // or a ptr to / own / ref of one (SM0271; a weak SM0275); T an object or an
  // interface (SM0272). A test no object can pass is reported: no object is
  // both types (SM0273), or X holds exactly its declared type (SM0274: a
  // variable, a field, a call's result; DoMayBeDescendant). A C/C++ operand
  // or target is clang's. The type: bool for is; for as the operand's kind
  // holding T (DoTypeTestResult). A dynamic test is never a constant
  DoExpr(ATest.Operand);
  DoTypeExpr(ATest.TargetType);
  if not DoOperandsReady(ATest, [ATest.Operand]) then
  begin
    ATest.IsConstExpr := False;
    Exit;
  end;
  if (ATest.TargetType = nil) or DoIsErrorType(ATest.TargetType) then
  begin
    DoPoison(ATest);
    Exit;
  end;
  if not DoTypeTestObject(ATest, LObject, LObjectType, LForm, LConstTarget) then
    Exit;
  if (LObject <> nil) and not DoIsOpaqueTier(ATest.TargetType) then
  begin
    if not DoTypeTestTarget(ATest, LTarget) then
      Exit;
    if not DoMayBeBoth(LObject, LTarget) then
    begin
      DoError(ATest, PC_ERR_SEM_273, RSSemExprTypeTestNever,
        [ATest.ExprText(), LObjectType.TypeText(), ATest.TargetType.TypeText()]);
      DoPoison(ATest);
      Exit;
    end;
    // An object read in place (not through a pointer or an owner) is a
    // descendant only where DoMayBeDescendant says it may be
    LIsPointer := TPCTypeExpr.PointerOf(LForm, LPointee, LConst);
    if (not LIsPointer) and (not (LForm is TPCOwnerType)) and (not DoMayBeDescendant(ATest.Operand)) and
      (LObject <> LTarget) and (not TPCScopes.Derives(LObject, LTarget)) then
    begin
      DoError(ATest.Operand, PC_ERR_SEM_274, RSSemExprTypeTestExact,
        [ATest.Operand.ExprText(), LObjectType.TypeText(), ATest.TargetType.TypeText()]);
      DoPoison(ATest);
      Exit;
    end;
  end;
  ATest.ResolvedType := DoTypeTestResult(ATest, LForm, LConstTarget);
end;

function TPCSemantics.DoTypeTestObject(const ATest: TPCTypeTest; out AObject: TPCRecordType;
  out AObjectType: TPCTypeExpr; out AForm: TPCTypeExpr; out AConstTarget: Boolean): Boolean;
var
  LPointee: TPCTypeExpr;
  LCanon: TPCTypeExpr;
begin
  // The object an is / as operand denotes. AForm = the operand's own type
  // (Canon: an object, a pointer, an own / ref), AObjectType = the object's
  // type as written, AObject its record (nil: a C/C++ type, clang's);
  // AConstTarget = a ptr to const. False = reported (SM0271 / SM0275), the
  // test poisoned
  AObject := nil;
  AConstTarget := False;
  AForm := ATest.Operand.ResolvedType.Canon();
  AObjectType := ATest.Operand.ResolvedType;
  if AForm is TPCOwnerType then
  begin
    if TPCOwnerType(AForm).OwnerKind = okWeak then
    begin
      DoError(ATest.Operand, PC_ERR_SEM_275, RSSemExprTypeTestWeak,
        [ATest.Operand.ExprText(), ATest.Operand.ExprText()]);
      DoPoison(ATest);
      Exit(False);
    end;
    AObjectType := TPCOwnerType(AForm).TargetType;
  end
  else if TPCTypeExpr.PointerOf(AForm, LPointee, AConstTarget) then
    AObjectType := LPointee;
  if (AObjectType <> nil) and DoIsOpaqueTier(AObjectType) then
    Exit(True);
  if AObjectType <> nil then
  begin
    LCanon := AObjectType.Canon();
    if (LCanon is TPCRecordType) and TPCRecordType(LCanon).IsObject and
      (TPCRecordType(LCanon).ResolvedIsPolymorphic or TPCRecordType(LCanon).IsInterface) then
    begin
      AObject := TPCRecordType(LCanon);
      Exit(True);
    end;
    // O13b: polymorphic through a C/C++ base, which only clang sees: the
    // emitted check judges SM0271 in the same words
    if (LCanon is TPCRecordType) and TPCRecordType(LCanon).PolymorphismIsClangs() then
    begin
      AObject := TPCRecordType(LCanon);
      DoNotePoly(ATest.Operand, pcIsPolymorphic, AObjectType, Format(RSSemExprTypeTestOperand,
        [ATest.WordText(), ATest.Operand.ExprText(), ATest.Operand.ResolvedType.TypeText()]));
      Exit(True);
    end;
  end;
  // An untyped ptr (nil included) points at no object type
  DoError(ATest.Operand, PC_ERR_SEM_271, RSSemExprTypeTestOperand,
    [ATest.WordText(), ATest.Operand.ExprText(), ATest.Operand.ResolvedType.TypeText()]);
  DoPoison(ATest);
  Result := False;
end;

function TPCSemantics.DoTypeTestTarget(const ATest: TPCTypeTest; out ATarget: TPCRecordType): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // The T of is / as: an object or an interface (an interface is a record
  // with IsObject and IsInterface, O7). Anything else is SM0272 at T (a ptr
  // to / own / ref T too: the result keeps the operand's kind), poisoned
  ATarget := nil;
  LCanon := ATest.TargetType.Canon();
  if (LCanon is TPCRecordType) and TPCRecordType(LCanon).IsObject then
  begin
    ATarget := TPCRecordType(LCanon);
    Exit(True);
  end;
  DoError(ATest.TargetType, PC_ERR_SEM_272, RSSemExprTypeTestTarget,
    [ATest.WordText(), ATest.TargetType.TypeText(), ATest.TargetType.TypeText()]);
  DoPoison(ATest);
  Result := False;
end;

class function TPCSemantics.DoMayBeBoth(const AFrom: TPCRecordType; const ATo: TPCRecordType): Boolean;
begin
  // Some object can be a AFrom (or a descendant of one) and a ATo at once.
  // One parent, any number of interfaces (D2): AFrom at or below ATo always
  // is; a final AFrom has no descendant, so only that; an interface ATo may
  // be implemented by a descendant of a non-final AFrom; an interface AFrom
  // by any object ATo or a descendant of it (none when ATo is final and does
  // not implement it); two objects are one chain only when ATo is below AFrom
  if (AFrom = ATo) or TPCScopes.Derives(AFrom, ATo) then
    Exit(True);
  if AFrom.IsFinal then
    Exit(False);
  if ATo.IsInterface then
    Exit(True);
  if AFrom.IsInterface then
    Exit((not ATo.IsFinal) or TPCScopes.Derives(ATo, AFrom));
  Result := TPCScopes.Derives(ATo, AFrom);
end;

function TPCSemantics.DoTypeTestResult(const ATest: TPCTypeTest; const AForm: TPCTypeExpr;
  const AConstTarget: Boolean): TPCTypeExpr;
var
  LPointer: TPCPointerType;
  LRef: TPCOwnerType;
  LPointee: TPCTypeExpr;
  LConst: Boolean;
begin
  // `is` is a bool; `as` keeps the operand's kind holding T (SEM builds the
  // ptr / ref type around the T as written, as lock(W) builds its ref): a ptr
  // to S -> a ptr to T (const kept), a ref S -> a ref T, an own S and an
  // object -> T itself (an lvalue: DoIsObjectCast)
  if not ATest.IsCast then
    Exit(FAst.BuiltinType(tkKwBool));
  if (AForm is TPCOwnerType) and (TPCOwnerType(AForm).OwnerKind = okRef) then
  begin
    LRef := FAst.NewNode<TPCOwnerType>();
    LRef.OwnerKind := okRef;
    LRef.TargetType := ATest.TargetType;
    Exit(LRef);
  end;
  if TPCTypeExpr.PointerOf(AForm, LPointee, LConst) then
  begin
    LPointer := FAst.NewNode<TPCPointerType>();
    LPointer.TargetType := ATest.TargetType;
    LPointer.IsConstTarget := AConstTarget;
    Exit(LPointer);
  end;
  Result := ATest.TargetType;
end;

class function TPCSemantics.DoIsObjectCast(const AExpr: TPCExpr): Boolean;
var
  LCanon: TPCTypeExpr;
  LPointee: TPCTypeExpr;
  LConst: Boolean;
begin
  // `X as T` whose result is the object itself (an object or an own
  // operand), an lvalue; a ptr / ref result is a value (DoTypeTestResult)
  Result := False;
  if not ((AExpr is TPCTypeTest) and TPCTypeTest(AExpr).IsCast and (AExpr.ResolvedType <> nil)) then
    Exit;
  LCanon := AExpr.ResolvedType.Canon();
  Result := not ((LCanon is TPCOwnerType) or TPCTypeExpr.PointerOf(LCanon, LPointee, LConst));
end;

function TPCSemantics.DoPendingForward(const AType: TPCTypeExpr): TPCTypeDecl;
var
  LType: TPCTypeExpr;
begin
  // The forward type declaration AType names (through aliases) whose full has
  // not come yet; nil = none (the type is known, or it is no forward)
  Result := nil;
  LType := AType;
  while (LType is TPCNamedType) and (TPCNamedType(LType).ResolvedKind = rkType) and
    (TPCNamedType(LType).ResolvedDecl <> nil) do
  begin
    if TPCNamedType(LType).ResolvedDecl.IsForward then
    begin
      if TPCNamedType(LType).ResolvedDecl.ResolvedFull = nil then
        Result := TPCNamedType(LType).ResolvedDecl;
      Exit;
    end;
    LType := TPCNamedType(LType).ResolvedDecl.TypeDef;
  end;
end;

procedure TPCSemantics.DoCheckPendingOwners();
var
  LIndex: Integer;
  LOwner: TPCOwnerType;
begin
  // PLAN-OBJECT O6: at a list end, each waiting owner type whose forward got
  // its full is judged now; one whose forward never gets one stays silent
  // (SM0303 reports the forward)
  if (FPendingOwners = nil) or (FPendingOwners.Count = 0) then
    Exit;
  for LIndex := FPendingOwners.Count - 1 downto 0 do
  begin
    LOwner := FPendingOwners[LIndex];
    if DoPendingForward(LOwner.TargetType) = nil then
    begin
      FPendingOwners.Delete(LIndex);
      DoCheckOwnerTarget(LOwner);
    end;
  end;
end;

procedure TPCSemantics.DoCheckOwnerTarget(const AOwner: TPCOwnerType);
var
  LCanon: TPCTypeExpr;
begin
  // PLAN-OBJECT O6 (D4): own / ref / weak hold an object (a PaskalCPP object
  // type; a C/C++ class is clang's): anything else is SM0358 at the type held.
  // An object type still only forward-declared is judged once its full is
  // known (FPendingOwners)
  if (AOwner.TargetType = nil) or DoIsErrorType(AOwner.TargetType) or DoIsOpaqueTier(AOwner.TargetType) then
    Exit;
  if DoPendingForward(AOwner.TargetType) <> nil then
  begin
    // Inside a recovered node nothing is reported (PLAN-RECOVERY): not queued
    if (FRecoveredDepth = 0) and not FPendingOwners.Contains(AOwner) then
      FPendingOwners.Add(AOwner);
    Exit;
  end;
  LCanon := AOwner.TargetType.Canon();
  if (LCanon is TPCRecordType) and TPCRecordType(LCanon).IsObject then
    Exit;
  DoError(AOwner.TargetType, PC_ERR_SEM_358, RSSemDeclOwnerTarget,
    [AOwner.TypeText(), AOwner.TargetType.TypeText()]);
end;

function TPCSemantics.DoHoldsOwner(const AType: TPCTypeExpr; out AOwner: TPCTypeExpr): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // PLAN-OBJECT O6 (H3): the own / ref / weak AType is, or an array of it
  // holds (each level of array), spelled as written there (AOwner)
  Result := False;
  AOwner := nil;
  if (AType = nil) or DoIsErrorType(AType) or DoIsOpaqueTier(AType) then
    Exit;
  LCanon := AType.Canon();
  if LCanon is TPCArrayType then
    Exit(DoHoldsOwner(TPCArrayType(LCanon).ElementType, AOwner));
  if LCanon is TPCOwnerType then
  begin
    AOwner := AType;
    Result := True;
  end;
end;

function TPCSemantics.DoHoldsObject(const AType: TPCTypeExpr; out AObject: TPCTypeExpr): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // The object AType is, or an array of it holds (each level of array),
  // spelled as written there (AObject); a pointer, C/C++ type or anything
  // else holds none
  Result := False;
  AObject := nil;
  if (AType = nil) or DoIsErrorType(AType) or DoIsOpaqueTier(AType) then
    Exit;
  LCanon := AType.Canon();
  if LCanon is TPCArrayType then
    Exit(DoHoldsObject(TPCArrayType(LCanon).ElementType, AObject));
  if (LCanon is TPCRecordType) and TPCRecordType(LCanon).IsObject then
  begin
    AObject := AType;
    Result := True;
  end;
end;

procedure TPCSemantics.DoNoteMoveOnly(const AType: TPCTypeExpr);
var
  LObject: TPCTypeExpr;
  LReason: TPCNode;
  LName: string;
begin
  // The note under SM0427 / SM0355: why the object AType is (or holds)
  // cannot be copied, at the part that makes it so (its done, its parent,
  // a field: TPCRecordType.MoveOnlyReason)
  if not DoHoldsObject(AType, LObject) then
    Exit;
  LReason := TPCRecordType(LObject.Canon()).MoveOnlyReason();
  LName := LObject.TypeText();
  if LReason is TPCDoneItem then
    DoNote(LReason, RSSemCallNoCopyDone, [LName])
  else if LReason is TPCField then
    DoNote(LReason, RSSemCallNoCopyField, [LName, TPCField(LReason).FieldName, TPCField(LReason).TypeExpr.TypeText()])
  else if LReason is TPCTypeExpr then
    DoNote(LReason, RSSemCallNoCopyParent, [LName, TPCTypeExpr(LReason).TypeText()]);
end;

function TPCSemantics.DoCheckCopy(const AValue: TPCExpr; const ATo: TPCTypeExpr): Boolean;
var
  LIsConst: Boolean;
  LObject: TPCTypeExpr;
begin
  // D5, the one copy check of every by-value position (an assignment, a
  // value argument, a return, an initializer): a value that is an lvalue (a
  // variable, a parameter, a field, an index, a deref, self) is copied into
  // ATo; a call result, a construction or a returned local (DoMarkMove) is
  // moved. When ATo cannot be copied (TPCTypeExpr.MoveOnlyReasonOf) that is
  // SM0427 at the value with the reason as a note, poisoned; ?: copies the
  // branch it takes. False = reported
  Result := True;
  if (AValue = nil) or (ATo = nil) or AValue.ResolvedIsMoved or DoIsPoisoned(AValue) or DoIsErrorType(ATo) then
    Exit;
  if AValue is TPCTernary then
  begin
    Result := DoCheckCopy(TPCTernary(AValue).ThenExpr, ATo);
    if not DoCheckCopy(TPCTernary(AValue).ElseExpr, ATo) then
      Result := False;
    Exit;
  end;
  // O13b: D6 where the polymorphism is clang's (an emitted check)
  DoNoteCppPoly(AValue, ATo);
  // PLAN-OBJECT O9: a bound property's read is its field: copied as one
  if (AValue.ResolvedType = nil) or not (DoIsAddressable(AValue, LIsConst) or DoIsBoundPropertyRead(AValue)) then
    Exit;
  // PLAN-OBJECT O6: an own (or an array of own) is the sole owner: a named
  // one copied anywhere (into an own, or a ref it would share) is SM0427
  // with its own hint, no note (the own is the reason)
  if DoHoldsOwner(AValue.ResolvedType, LObject) and (TPCTypeExpr.MoveOnlyReasonOf(AValue.ResolvedType) <> nil) then
  begin
    DoError(AValue, PC_ERR_SEM_427, RSSemCallNoCopyOwn, [AValue.ExprText(), AValue.ResolvedType.TypeText()]);
    DoPoison(AValue);
    Exit(False);
  end;
  // D6 by the dynamic type: a copy of what may be a descendant slices
  if DoCheckSliceCopy(AValue, ATo) then
    Exit(False);
  if TPCTypeExpr.MoveOnlyReasonOf(ATo) = nil then
    Exit;
  if not DoHoldsObject(ATo, LObject) then
    Exit;
  if DoError(AValue, PC_ERR_SEM_427, RSSemCallNoCopy, [AValue.ExprText(), ATo.TypeText(), LObject.TypeText()]) then
    DoNoteMoveOnly(ATo);
  DoPoison(AValue);
  Result := False;
end;

function TPCSemantics.DoCheckSlice(const AValue: TPCExpr; const ATo: TPCTypeExpr): Boolean;
var
  LFrom: TPCTypeExpr;
begin
  // D6: a polymorphic object reaches a base by var / const or through a
  // pointer, never by value (C++ would cut it to the base part and lose
  // its dynamic type): SM0428 at the value, poisoned. True = reported (a
  // value of a non-polymorphic descendant converts: DoConvertsFrom)
  Result := False;
  if (AValue = nil) or (AValue.ResolvedType = nil) or (ATo = nil) or DoIsErrorType(ATo) or
    DoIsOpaqueTier(AValue.ResolvedType) or DoIsOpaqueTier(ATo) then
    Exit;
  LFrom := AValue.ResolvedType.Canon();
  if not ((LFrom is TPCRecordType) and TPCRecordType(LFrom).IsObject and TPCRecordType(LFrom).ResolvedIsPolymorphic) then
    Exit;
  if not TPCScopes.Derives(LFrom, ATo) then
    Exit;
  DoError(AValue, PC_ERR_SEM_428, RSSemCallSlice, [AValue.ResolvedType.TypeText(), ATo.TypeText()]);
  DoPoison(AValue);
  Result := True;
end;

function TPCSemantics.DoCheckSliceCopy(const AValue: TPCExpr; const ATo: TPCTypeExpr): Boolean;
var
  LType: TPCTypeExpr;
  LRecord: TPCRecordType;
begin
  // D6 by the dynamic type (2026-10-14, found in O12): DoCheckSlice judges
  // the static types; a polymorphic, non-final object read where it may be
  // a descendant (DoMayBeDescendant: a var / const parameter, a deref, self,
  // X as T) copied by value into its own type keeps only that part too:
  // SM0428 at the value, poisoned. Asked by DoCheckCopy, the one copy check
  // of every by-value position. A final object has no descendant; a C/C++
  // type is clang's. True = reported
  Result := False;
  if (AValue.ResolvedType = nil) or DoIsOpaqueTier(AValue.ResolvedType) or DoIsOpaqueTier(ATo) then
    Exit;
  LType := AValue.ResolvedType.Canon();
  if not (LType is TPCRecordType) then
    Exit;
  LRecord := TPCRecordType(LType);
  if (not LRecord.IsObject) or (not LRecord.ResolvedIsPolymorphic) or LRecord.IsFinal then
    Exit;
  if not DoMayBeDescendant(AValue) then
    Exit;
  DoError(AValue, PC_ERR_SEM_428, RSSemCallSliceHeld,
    [AValue.ExprText(), AValue.ResolvedType.TypeText(), ATo.TypeText()]);
  DoPoison(AValue);
  Result := True;
end;

function TPCSemantics.DoMayHoldDescendant(const ATarget: TPCExpr): Boolean;
var
  LName: TPCName;
  LCanon: TPCTypeExpr;
  LPointee: TPCTypeExpr;
  LIsConst: Boolean;
begin
  // TODO.md 8 (a): the places whose object may be a descendant of their
  // declared type: a var parameter (the caller passes any descendant), a
  // deref (`P^`, `*P`) and an index on a typed pointer (the pointee may be a
  // descendant), and self (a method runs on a descendant too). A variable, a
  // field or an array element holds exactly its declared type
  Result := False;
  if ATarget is TPCName then
  begin
    LName := TPCName(ATarget);
    Result := (LName.ResolvedKind = rkParam) and (LName.ResolvedDecl is TPCParam) and
      (TPCParam(LName.ResolvedDecl).ParamMode = pmVar);
  end
  else if ATarget is TPCUnary then
    Result := TPCUnary(ATarget).Op = uoDeref
  else if ATarget is TPCSpecial then
    Result := TPCSpecial(ATarget).SpecialKind = skSelf
  else if (ATarget is TPCIndex) and (TPCIndex(ATarget).Base <> nil) and (TPCIndex(ATarget).Base.ResolvedType <> nil) then
  begin
    LCanon := TPCIndex(ATarget).Base.ResolvedType.Canon();
    Result := TPCTypeExpr.PointerOf(LCanon, LPointee, LIsConst);
  end
  // PLAN-OBJECT O12: `X as T` is the object X denotes: a T or a descendant
  else if DoIsObjectCast(ATarget) then
    Result := True;
end;

function TPCSemantics.DoMayBeDescendant(const AValue: TPCExpr): Boolean;
var
  LName: TPCName;
begin
  // PLAN-OBJECT O12: the places an object READ may be a descendant of its
  // declared type: DoMayHoldDescendant's, and a const parameter (passed by
  // reference: the caller passes any descendant, DoConstTakes). A variable,
  // a field, an element or a call's result is exactly its type
  if DoMayHoldDescendant(AValue) then
    Exit(True);
  Result := False;
  if not (AValue is TPCName) then
    Exit;
  LName := TPCName(AValue);
  Result := (LName.ResolvedKind = rkParam) and (LName.ResolvedDecl is TPCParam) and
    (TPCParam(LName.ResolvedDecl).ParamMode = pmConst);
end;

function TPCSemantics.DoCheckSliceAssign(const ATarget: TPCExpr): Boolean;
var
  LType: TPCTypeExpr;
  LRecord: TPCRecordType;
begin
  // TODO.md 8 (a), the assignment side of D6: `T := X` into a polymorphic
  // object reached where it may be a descendant (DoMayHoldDescendant) runs
  // the base type's operator=, which replaces only the base part and leaves
  // the descendant's own fields as they were: SM0429 at the target. A final
  // object has no descendants; a C/C++ type is clang's. True = reported
  Result := False;
  if (ATarget = nil) or (ATarget.ResolvedType = nil) or DoIsOpaqueTier(ATarget.ResolvedType) then
    Exit;
  LType := ATarget.ResolvedType.Canon();
  if not (LType is TPCRecordType) then
    Exit;
  LRecord := TPCRecordType(LType);
  // O13b: a polymorphism only clang knows (a C/C++ base): the same rule,
  // judged by the emitted check
  if LRecord.PolymorphismIsClangs() and not LRecord.IsFinal and DoMayHoldDescendant(ATarget) then
  begin
    DoNotePoly(ATarget, pcSliceAssign, ATarget.ResolvedType, Format(RSSemCallSliceAssign,
      [ATarget.ExprText(), ATarget.ResolvedType.TypeText(), ATarget.ResolvedType.TypeText()]));
    Exit;
  end;
  if not (LRecord.IsObject and LRecord.ResolvedIsPolymorphic) or LRecord.IsFinal then
    Exit;
  if not DoMayHoldDescendant(ATarget) then
    Exit;
  DoError(ATarget, PC_ERR_SEM_429, RSSemCallSliceAssign, [ATarget.ExprText(), ATarget.ResolvedType.TypeText(),
    ATarget.ResolvedType.TypeText()]);
  Result := True;
end;

procedure TPCSemantics.DoNotePoly(const AExpr: TPCExpr; const AKind: TPCPolyCheck; const AType: TPCTypeExpr;
  const AText: string);
begin
  // PLAN-OBJECT O13b: the rule AKind is judged by clang's view of AType's
  // polymorphism (the emitted check); AText is the message the Compiler
  // reports when it fails, built here with SEM's own words. One check per
  // expression: the first rule that asks keeps it
  if (AExpr = nil) or (AType = nil) or (AExpr.ResolvedPolyCheck <> pcNone) then
    Exit;
  AExpr.ResolvedPolyCheck := AKind;
  AExpr.ResolvedPolyType := AType;
  AExpr.ResolvedPolyText := AText;
end;

procedure TPCSemantics.DoNoteCppPoly(const AValue: TPCExpr; const ATo: TPCTypeExpr);
var
  LFrom: TPCTypeExpr;
  LTo: TPCTypeExpr;
  LFromTarget: TPCTypeExpr;
  LToTarget: TPCTypeExpr;
  LRecord: TPCRecordType;
begin
  // PLAN-OBJECT O13b, D6 where only clang knows the polymorphism (an object
  // whose chain reaches C/C++ and no PaskalCPP level is virtual): SEM let
  // the value pass as the non-polymorphic object it may be, and marks the
  // rule a polymorphic one breaks, so clang judges it with the C++ class
  // in view (one by-value position each, asked by DoCheckCopy):
  // - an own handed to an own of an ancestor needs the ancestor polymorphic
  //   (DoOwnerConverts let it through; SM0200's words);
  // - a value converted to an ancestor slices when polymorphic (SM0428);
  // - a copy from where a descendant may be slices too (SM0428, held)
  if (AValue = nil) or (AValue.ResolvedType = nil) or (ATo = nil) or DoIsPoisoned(AValue) then
    Exit;
  LFrom := AValue.ResolvedType.Canon();
  LTo := ATo.Canon();
  if (LFrom is TPCOwnerType) and (LTo is TPCOwnerType) then
  begin
    if (TPCOwnerType(LFrom).OwnerKind <> okOwn) or (TPCOwnerType(LTo).OwnerKind <> okOwn) or
      (TPCOwnerType(LFrom).TargetType = nil) or (TPCOwnerType(LTo).TargetType = nil) then
      Exit;
    LFromTarget := TPCOwnerType(LFrom).TargetType.Canon();
    LToTarget := TPCOwnerType(LTo).TargetType.Canon();
    if (LToTarget is TPCRecordType) and TPCRecordType(LToTarget).PolymorphismIsClangs() and
      not DoSameType(LFromTarget, LToTarget) and TPCScopes.Derives(LFromTarget, LToTarget) then
      DoNotePoly(AValue, pcOwnUpcast, TPCOwnerType(LTo).TargetType,
        Format(RSSemTypeNoConvert, [AValue.ResolvedType.TypeText(), ATo.TypeText()]));
    Exit;
  end;
  if not ((LFrom is TPCRecordType) and TPCRecordType(LFrom).PolymorphismIsClangs()) then
    Exit;
  LRecord := TPCRecordType(LFrom);
  if (LTo is TPCRecordType) and not DoSameType(LFrom, LTo) and TPCScopes.Derives(LFrom, LTo) then
  begin
    DoNotePoly(AValue, pcSlice, AValue.ResolvedType,
      Format(RSSemCallSlice, [AValue.ResolvedType.TypeText(), ATo.TypeText()]));
    Exit;
  end;
  if (not LRecord.IsFinal) and (not AValue.ResolvedIsMoved) and DoMayBeDescendant(AValue) then
    DoNotePoly(AValue, pcSliceHeld, AValue.ResolvedType,
      Format(RSSemCallSliceHeld, [AValue.ExprText(), AValue.ResolvedType.TypeText(), ATo.TypeText()]));
end;

procedure TPCSemantics.DoMarkMove(const AValue: TPCExpr);
var
  LName: TPCName;
  LMoved: Boolean;
begin
  // D5: `return X;` where X is a local variable or a value parameter of the
  // routine being checked: X ends there, so it is moved (ResolvedIsMoved,
  // written std::move by the emitter), never copied. Only for a type that
  // cannot be copied: every other value C++ copies or moves as it likes
  if (FRoutine = nil) or not (AValue is TPCName) or (AValue.ResolvedType = nil) then
    Exit;
  LName := TPCName(AValue);
  LMoved := False;
  if (LName.ResolvedKind = rkVar) and (LName.ResolvedDecl is TPCVarDecl) then
    LMoved := FRoutine.Decls.Contains(TPCStmt(LName.ResolvedDecl))
  else if (LName.ResolvedKind = rkParam) and (LName.ResolvedDecl is TPCParam) then
    LMoved := (TPCParam(LName.ResolvedDecl).ParamMode = pmNone) and
      FRoutine.Params.Contains(TPCParam(LName.ResolvedDecl));
  if LMoved and (TPCTypeExpr.MoveOnlyReasonOf(AValue.ResolvedType) <> nil) then
    AValue.ResolvedIsMoved := True;
end;

procedure TPCSemantics.DoCheckComplete(const AType: TPCTypeExpr; const AIsMember: Boolean);
var
  LType: TPCTypeExpr;
  LDecl: TPCTypeDecl;
begin
  // The one by-value completeness check (SM0300, decls.md TPCVarDecl): a
  // forward with no full yet, or (AIsMember: a field or a parent) a type still
  // being defined, cannot be held by value. An array holds its element by
  // value, a pointer never. Canon first: it raises on an alias cycle (an
  // invariant), so the walk below always ends
  if (AType = nil) or DoIsErrorType(AType) then
    Exit;
  if AType is TPCArrayType then
  begin
    // A dynamic array member of the type being defined is std::vector of an
    // incomplete type: legal since C++17, so only the forward rule applies
    DoCheckComplete(TPCArrayType(AType).ElementType, AIsMember and not TPCArrayType(AType).IsDynamic);
    Exit;
  end;
  AType.Canon();
  LType := AType;
  while (LType is TPCNamedType) and (TPCNamedType(LType).ResolvedKind = rkType) and
    (TPCNamedType(LType).ResolvedDecl <> nil) do
  begin
    LDecl := TPCNamedType(LType).ResolvedDecl;
    if LDecl.IsForward then
    begin
      if LDecl.ResolvedFull = nil then
      begin
        DoError(AType, PC_ERR_SEM_300, RSSemDeclForwardOnly, [AType.TypeText(), AType.TypeText()]);
        Exit;
      end;
      LDecl := LDecl.ResolvedFull;
    end;
    // A field position exists only directly in a type definition (a method's
    // Decls hold var blocks only: RSParMethodBlocks), so every FDefining entry
    // is still open there
    if AIsMember and FDefining.Contains(LDecl) then
    begin
      DoError(AType, PC_ERR_SEM_300, RSSemDeclForwardOnly, [AType.TypeText(), AType.TypeText()]);
      Exit;
    end;
    LType := LDecl.TypeDef;
  end;
end;

procedure TPCSemantics.DoCheckVarDecl(const ADecl: TPCVarDecl);
begin
  // decls.md TPCVarDecl: by value; an external variable has no initializer
  // and lives at module level (Q23)
  DoCheckComplete(ADecl.TypeExpr, False);
  DoCheckConcrete(ADecl.TypeExpr, ADecl.TypeExpr);
  if not ADecl.ExternalClause.IsExternal then
    Exit;
  DoResolveExternalLib(ADecl, ADecl.ExternalClause);
  if ADecl.InitExpr <> nil then
    DoError(ADecl.InitExpr, PC_ERR_SEM_301, RSSemDeclExternalInit, []);
  if FFrames[DoTopIndex()].FrameKind <> fkModule then
    DoError(ADecl, PC_ERR_SEM_302, RSSemDeclExternalLocal, []);
end;

procedure TPCSemantics.DoForwardType(const ADecl: TPCTypeDecl);
var
  LFound: TList<TPCNode>;
  LNode: TPCNode;
begin
  // A forward after its full declares nothing (SM0304): it names that full,
  // so its uses resolve and no SM0303 follows. A second forward of one name
  // is a duplicate (decls.md TPCTypeDecl: CORE leaves type pairs to DECLS)
  LFound := TList<TPCNode>.Create();
  try
    TPCScopes.Collect(FFrames[DoTopIndex()], ADecl.DeclName, LFound);
    for LNode in LFound do
    begin
      if (LNode <> ADecl) and (LNode is TPCTypeDecl) and not TPCTypeDecl(LNode).IsForward then
      begin
        ADecl.ResolvedFull := TPCTypeDecl(LNode);
        if DoError(ADecl, PC_ERR_SEM_304, RSSemDeclForwardAfterFull, [ADecl.DeclName]) then
          DoNote(LNode, RSSemDeclFullDecl, [ADecl.DeclName]);
        Exit;
      end;
    end;
    for LNode in LFound do
    begin
      if (LNode <> ADecl) and (LNode is TPCTypeDecl) and TPCTypeDecl(LNode).IsForward then
      begin
        DoReportDuplicate(ADecl, LNode, ADecl.DeclName);
        Exit;
      end;
    end;
  finally
    LFound.Free();
  end;
end;

procedure TPCSemantics.DoFullType(const ADecl: TPCTypeDecl);
var
  LFound: TList<TPCNode>;
  LNode: TPCNode;
  LForward: TPCTypeDecl;
  LFirst: TPCTypeDecl;
begin
  // A full declaration completes every earlier same-named forward of its
  // frame that has none (D-A1b-2: types pair by name). The first forward is
  // the one its kind (SM0305, Q22) and export (SM0306) are judged against
  LFirst := nil;
  LFound := TList<TPCNode>.Create();
  try
    TPCScopes.Collect(FFrames[DoTopIndex()], ADecl.DeclName, LFound);
    for LNode in LFound do
    begin
      if (LNode = ADecl) or not (LNode is TPCTypeDecl) then
        Continue;
      LForward := TPCTypeDecl(LNode);
      if not LForward.IsForward or (LForward.ResolvedFull <> nil) then
        Continue;
      LForward.ResolvedFull := ADecl;
      if LFirst = nil then
        LFirst := LForward;
    end;
  finally
    LFound.Free();
  end;
  if LFirst = nil then
    Exit;
  if not ((ADecl.TypeDef is TPCRecordType) or (ADecl.TypeDef is TPCOverlayType)) then
  begin
    if DoError(ADecl, PC_ERR_SEM_305, RSSemDeclForwardKind, []) then
      DoNote(LFirst, RSSemDeclTheForward, [ADecl.DeclName]);
  end;
  if LFirst.IsExported <> ADecl.IsExported then
  begin
    if DoError(ADecl, PC_ERR_SEM_306, RSSemDeclForwardDiffer, [ADecl.DeclName, RSSemDeclFactExported]) then
      DoNote(LFirst, RSSemDeclTheForward, [ADecl.DeclName]);
  end;
end;

procedure TPCSemantics.DoUnpairedForwards(const AList: TList<TPCStmt>);
var
  LItem: TPCStmt;
begin
  // At the end of a list: a forward type whose full never came (SM0303;
  // spec: the full follows in the SAME frame list)
  if AList = nil then
    Exit;
  for LItem in AList do
  begin
    if DoStopped() then
      Exit;
    if (LItem is TPCTypeDecl) and TPCTypeDecl(LItem).IsForward and (TPCTypeDecl(LItem).ResolvedFull = nil) then
      DoError(LItem, PC_ERR_SEM_303, RSSemDeclForwardNoFull, [TPCTypeDecl(LItem).DeclName]);
  end;
end;

function TPCSemantics.DoSameParamTypes(const AFirst: TPCRoutine; const ASecond: TPCRoutine): Boolean;
var
  LIndex: Integer;
begin
  // Forward pairing (decls.md TPCRoutine Forward): the same parameter count
  // and Canon-equal types; modes, names and the rest are facts checked after
  if AFirst.Params.Count <> ASecond.Params.Count then
    Exit(False);
  for LIndex := 0 to AFirst.Params.Count - 1 do
  begin
    // A parameter the parser dropped matches (C1: it was reported)
    if (AFirst.Params[LIndex] = nil) or (ASecond.Params[LIndex] = nil) then
      Continue;
    if not DoSameSignatureType(AFirst.Params[LIndex].TypeExpr, ASecond.Params[LIndex].TypeExpr) then
      Exit(False);
  end;
  Result := True;
end;

function TPCSemantics.DoParamFact(const AForward: TPCRoutine; const AFull: TPCRoutine; out AFact: string): Boolean;
var
  LIndex: Integer;
  LForward: TPCParam;
  LFull: TPCParam;
begin
  // The first parameter a paired forward and full spell differently: its
  // name, then its mode (the counts are equal: they paired)
  AFact := '';
  for LIndex := 0 to AForward.Params.Count - 1 do
  begin
    LForward := AForward.Params[LIndex];
    LFull := AFull.Params[LIndex];
    if (LForward = nil) or (LFull = nil) then
      Continue;
    if LForward.ParamName <> LFull.ParamName then
    begin
      AFact := Format(RSSemDeclFactParamName, [LIndex + 1, LForward.ParamName, LFull.ParamName]);
      Exit(True);
    end;
    if LForward.ParamMode <> LFull.ParamMode then
    begin
      AFact := Format(RSSemDeclFactParamMode, [LForward.ParamName]);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TPCSemantics.DoRoutineFact(const AForward: TPCRoutine; const AFull: TPCRoutine; out AFact: string): Boolean;
begin
  // The first fact a paired forward and full disagree on (decls.md TPCRoutine
  // Forward): linkage by meaning (not written = C++), export, `...`, the
  // parameters, the return type; False = they match
  AFact := '';
  if (AForward.Linkage = lnC) <> (AFull.Linkage = lnC) then
    AFact := RSSemDeclFactLinkage
  else if AForward.IsExported <> AFull.IsExported then
    AFact := RSSemDeclFactExported
  else if AForward.IsVariadic <> AFull.IsVariadic then
    AFact := RSSemDeclFactVariadic
  else if DoParamFact(AForward, AFull, AFact) then
    Exit(True)
  else if (AForward.ReturnType = nil) <> (AFull.ReturnType = nil) then
    AFact := RSSemDeclFactReturn
  else if (AForward.ReturnType <> nil) and not DoSameSignatureType(AForward.ReturnType, AFull.ReturnType) then
    AFact := RSSemDeclFactReturn;
  Result := AFact <> '';
end;

procedure TPCSemantics.DoPairRoutine(const AFull: TPCRoutine);
var
  LFound: TList<TPCNode>;
  LNode: TPCNode;
  LForward: TPCRoutine;
  LFact: string;
begin
  // A full routine completes the first earlier forward of its frame with the
  // same name and parameter types (routines pair by signature); a full that
  // pairs with none is a new overload (R-DECL at the list end)
  LFound := TList<TPCNode>.Create();
  try
    TPCScopes.Collect(FFrames[DoTopIndex()], AFull.DeclName, LFound);
    for LNode in LFound do
    begin
      if (LNode = AFull) or not (LNode is TPCRoutine) then
        Continue;
      LForward := TPCRoutine(LNode);
      if not LForward.IsForward or (LForward.ResolvedFull <> nil) or not DoSameParamTypes(LForward, AFull) then
        Continue;
      LForward.ResolvedFull := AFull;
      if DoRoutineFact(LForward, AFull, LFact) then
      begin
        if DoError(AFull, PC_ERR_SEM_306, RSSemDeclForwardDiffer, [AFull.DeclName, LFact]) then
          DoNote(LForward, RSSemDeclTheForward, [AFull.DeclName]);
      end;
      Exit;
    end;
  finally
    LFound.Free();
  end;
end;

function TPCSemantics.DoWrittenClink(const AMember: TPCRoutine): Boolean;
begin
  // A member of an overload set is written clink when its forward or its full says so
  Result := (AMember.Linkage = lnC) or
    (AMember.IsForward and (AMember.ResolvedFull <> nil) and (AMember.ResolvedFull.Linkage = lnC));
end;

procedure TPCSemantics.DoSetLinkage(const AMember: TPCRoutine; const ALinkage: TPCLinkage);
begin
  // A member is its forward and its full: both carry one linkage
  AMember.ResolvedLinkage := ALinkage;
  if AMember.IsForward and (AMember.ResolvedFull <> nil) then
    AMember.ResolvedFull.ResolvedLinkage := ALinkage;
end;

procedure TPCSemantics.DoCollectMembers(const AList: TList<TPCStmt>; const AName: string;
  const AMembers: TList<TPCRoutine>);
var
  LItem: TPCStmt;
  LOther: TPCStmt;
  LPaired: Boolean;
begin
  // The overload set of a name in one list (R-LINK): every routine of that
  // name in list order, a forward and its full counted once (as the forward)
  AMembers.Clear();
  for LItem in AList do
  begin
    if not (LItem is TPCRoutine) or (TPCRoutine(LItem).DeclName <> AName) then
      Continue;
    LPaired := False;
    for LOther in AList do
    begin
      if (LOther is TPCRoutine) and TPCRoutine(LOther).IsForward and (TPCRoutine(LOther).ResolvedFull = LItem) then
        LPaired := True;
    end;
    if not LPaired then
      AMembers.Add(TPCRoutine(LItem));
  end;
end;

function TPCSemantics.DoNearestFull(const AList: TList<TPCStmt>; const AForward: TPCRoutine): TPCRoutine;
var
  LIndex: Integer;
  LAt: Integer;
  LBest: Integer;
  LItem: TPCStmt;
begin
  // The full routine of the same name closest to the forward in its list (the
  // SM0307 note); nil when the list has none
  Result := nil;
  LAt := AList.IndexOf(AForward);
  LBest := -1;
  for LIndex := 0 to AList.Count - 1 do
  begin
    LItem := AList[LIndex];
    if not (LItem is TPCRoutine) or TPCRoutine(LItem).IsForward or
      (TPCRoutine(LItem).DeclName <> AForward.DeclName) then
      Continue;
    if (LBest < 0) or (Abs(LIndex - LAt) < Abs(LBest - LAt)) then
    begin
      LBest := LIndex;
      Result := TPCRoutine(LItem);
    end;
  end;
end;

function TPCSemantics.DoJudgedOverload(const AMember: TPCRoutine): Boolean;
var
  LParam: TPCParam;
begin
  // A member R-DECL compares: not an unpaired forward (SM0307's), not variadic
  // (SM0330's), and no parameter whose type was already reported (a reported
  // type matches any other in DoSameSignatureType: C1, no cascade)
  Result := False;
  if (AMember.IsForward and (AMember.ResolvedFull = nil)) or AMember.IsVariadic then
    Exit;
  for LParam in AMember.Params do
  begin
    if (LParam = nil) or DoIsErrorType(LParam.TypeExpr) then
      Exit;
  end;
  Result := True;
end;

function TPCSemantics.DoCheckDistinctParams(const AMembers: TList<TPCRoutine>): Boolean;
var
  LIndex: Integer;
  LEarlier: Integer;
  LMember: TPCRoutine;
  LFirst: TPCRoutine;
begin
  // R-DECL (SM0324, user 2026-10-12: "they must have diff param types"):
  // overloads differ in their parameter TYPES. DoSameParamTypes is the one
  // rule (forward pairing reads it too): count and types; names, modes
  // (var / const), linkage and the return type do not make an overload. One
  // error per member that repeats an earlier member's types, the earlier one
  // as a note. Not judged here: an unpaired forward (SM0307's) and a variadic
  // member (SM0330's: it shares its name with nothing). True = a proper set
  Result := True;
  for LIndex := 1 to AMembers.Count - 1 do
  begin
    if DoStopped() then
      Exit(False);
    LMember := AMembers[LIndex];
    if not DoJudgedOverload(LMember) then
      Continue;
    for LEarlier := 0 to LIndex - 1 do
    begin
      LFirst := AMembers[LEarlier];
      if not DoJudgedOverload(LFirst) or not DoSameParamTypes(LFirst, LMember) then
        Continue;
      Result := False;
      if DoError(LMember, PC_ERR_SEM_324, RSSemDeclSameParams, [LMember.DeclName]) then
        DoNote(LFirst, RSSemDeclFirstOverload, [LMember.DeclName]);
      Break;
    end;
  end;
end;

procedure TPCSemantics.DoCheckOverloadLinkage(const AMembers: TList<TPCRoutine>);
var
  LMember: TPCRoutine;
  LOther: TPCRoutine;
  LAny: Boolean;
  LIndex: Integer;
begin
  // R-LINK (decls.md, Q20): a set of two or more with any member written
  // clink gets C++ linkage for every member; one warning per member written
  // clink, the first other member as a note. Runs after R-DECL, on a proper
  // set only (user 2026-10-12: valid overloads written clink are promoted)
  if AMembers.Count < 2 then
    Exit;
  LAny := False;
  for LMember in AMembers do
  begin
    if DoWrittenClink(LMember) then
      LAny := True;
  end;
  if not LAny then
    Exit;
  for LMember in AMembers do
    DoSetLinkage(LMember, lnCpp);
  for LIndex := 0 to AMembers.Count - 1 do
  begin
    if not DoWrittenClink(AMembers[LIndex]) then
      Continue;
    if LIndex = 0 then
      LOther := AMembers[1]
    else
      LOther := AMembers[0];
    if DoWarning(AMembers[LIndex], PC_ERR_SEM_323, RSSemDeclOverloadLinkage, [AMembers[LIndex].DeclName]) then
      DoNote(LOther, RSSemDeclOtherOverload, [LOther.DeclName]);
  end;
end;

procedure TPCSemantics.DoCheckVariadicSet(const AMembers: TList<TPCRoutine>);
var
  LOther: TPCRoutine;
  LIndex: Integer;
begin
  // V4 (user 2026-10-08, "Forbid it"): a cpplink variadic routine packs its
  // extra arguments at the call site, so it cannot share its name with another
  // routine of its list (a call would be packed by one member and call the
  // wrong one). One error per such member, the first other member as a note.
  // Runs after R-LINK: ResolvedLinkage is final (a clink member of a set of
  // two or more already has C++ linkage)
  if AMembers.Count < 2 then
    Exit;
  for LIndex := 0 to AMembers.Count - 1 do
  begin
    if DoStopped() then
      Exit;
    if not AMembers[LIndex].IsVariadic or (AMembers[LIndex].ResolvedLinkage = lnC) then
      Continue;
    if LIndex = 0 then
      LOther := AMembers[1]
    else
      LOther := AMembers[0];
    if DoError(AMembers[LIndex], PC_ERR_SEM_330, RSSemDeclVariadicOverload, [AMembers[LIndex].DeclName]) then
      DoNote(LOther, RSSemDeclOtherOverload, [LOther.DeclName]);
  end;
end;

procedure TPCSemantics.DoCheckVariadicFixed(const AMembers: TList<TPCRoutine>);
var
  LMember: TPCRoutine;
begin
  // BNF sec 3 (probed 2026-10-07, sem\decls.md P7): a variadic routine that
  // keeps C linkage reads its extra arguments with va_start from its last
  // fixed parameter, so one WITH A BODY needs a fixed parameter before '...'
  // (an external one may be declared without; a cpplink one carries a typed
  // pack). Runs after R-LINK: ResolvedLinkage is final. At the '...' token
  // (the parser's VariadicRange); DoRoutineSets judges no set holding a
  // recovered member
  for LMember in AMembers do
  begin
    if DoStopped() then
      Exit;
    if LMember.IsVariadic and (LMember.ResolvedLinkage = lnC) and (LMember.Body <> nil) and
      (LMember.Params.Count = 0) then
      DoReportRange(LMember.VariadicRange, esError, PC_ERR_SEM_325, RSSemDeclVariadicFixed,
        [LMember.DeclName]);
  end;
end;

procedure TPCSemantics.DoCheckOverloads(const AList: TList<TPCStmt>; const AMembers: TList<TPCRoutine>);
var
  LMember: TPCRoutine;
  LFull: TPCRoutine;
begin
  // A forward no full paired with is SM0307 (one report per declaration).
  // Two members with the same parameter types are SM0324 (DoCheckDistinctParams)
  for LMember in AMembers do
  begin
    if DoStopped() then
      Exit;
    if LMember.IsForward and (LMember.ResolvedFull = nil) then
    begin
      LFull := DoNearestFull(AList, LMember);
      if DoError(LMember, PC_ERR_SEM_307, RSSemDeclRoutineNoFull, [LMember.DeclName]) and (LFull <> nil) then
        DoNote(LFull, RSSemDeclNearestFull, [LMember.DeclName]);
    end;
  end;
end;

procedure TPCSemantics.DoRoutineSets(const AList: TList<TPCStmt>);
var
  LNames: TList<string>;
  LMembers: TList<TPCRoutine>;
  LItem: TPCStmt;
  LName: string;
begin
  // At the end of a list, every routine of it analyzed and paired: per name
  // (first appearance order) R-DECL (SM0324), R-LINK on a proper set, then
  // SM0330 / SM0325, then SM0307
  if AList = nil then
    Exit;
  LNames := TList<string>.Create();
  LMembers := TList<TPCRoutine>.Create();
  try
    for LItem in AList do
    begin
      if (LItem is TPCRoutine) and not LNames.Contains(TPCRoutine(LItem).DeclName) then
        LNames.Add(TPCRoutine(LItem).DeclName);
    end;
    for LName in LNames do
    begin
      if DoStopped() then
        Exit;
      DoCollectMembers(AList, LName, LMembers);
      // A set holding a routine the parser could not finish is not judged
      if DoAnyRecovered(LMembers) then
        Continue;
      // R-DECL first: only a proper overload set is promoted to C++ linkage
      if DoCheckDistinctParams(LMembers) then
        DoCheckOverloadLinkage(LMembers);
      DoCheckVariadicSet(LMembers);
      DoCheckVariadicFixed(LMembers);
      DoCheckOverloads(AList, LMembers);
    end;
  finally
    LMembers.Free();
    LNames.Free();
  end;
end;

procedure TPCSemantics.DoResolveExternalLib(const ADecl: TPCDecl; var AExternal: TPCExternal);
var
  LFound: TList<TPCNode>;
  LConst: TPCConstDecl;
  LValue: string;
begin
  // decls.md External lib: a "..." library is the parser's (PR0055 when it is
  // no name); an identifier names a visible const whose value is a plain
  // string literal, a library NAME (Q25a: TPCLibraryName, the one check)
  AExternal.ResolvedLib := '';
  if not AExternal.IsExternal then
    Exit;
  if AExternal.LibKind = elCString then
  begin
    if TPCLibraryName.IsName(AExternal.LibText) then
      AExternal.ResolvedLib := AExternal.LibText;
    Exit;
  end;
  if AExternal.LibKind <> elIdentifier then
    Exit;
  LConst := nil;
  LFound := TList<TPCNode>.Create();
  try
    DoLookup(AExternal.LibText, LFound);
    // An imported unit's const names a library too (PLAN-IMPORT-RESOLUTION);
    // two units export it = SM0020 at the name, and nothing more
    if (LFound.Count = 0) and
      DoImportedName(AExternal.LibRange, not ADecl.IsRecovered, AExternal.LibText, LFound) and
      (LFound.Count = 0) then
      Exit;
    if (LFound.Count = 1) and (LFound[0] is TPCConstDecl) then
      LConst := TPCConstDecl(LFound[0]);
  finally
    LFound.Free();
  end;
  if (LConst = nil) or not (LConst.ValueExpr is TPCLiteral) or
    (TPCLiteral(LConst.ValueExpr).LiteralKind <> lkString) or
    not TPCLiteral(LConst.ValueExpr).DecodedValue(LValue) then
  begin
    // At the library's name (the parser's LibRange, as PR0055 for a "..."),
    // never the whole declaration: its clause may sit lines below its start.
    // Nothing on a recovered declaration (DoReportAt's rule)
    if not ADecl.IsRecovered then
      DoReportRange(AExternal.LibRange, esError, PC_ERR_SEM_326, RSSemDeclLibConst, [AExternal.LibText]);
    Exit;
  end;
  if not TPCLibraryName.IsName(LValue) then
  begin
    if not ADecl.IsRecovered then
      DoReportRange(AExternal.LibRange, esError, PC_ERR_SEM_327, RSSemDeclLibName, [LValue]);
    Exit;
  end;
  AExternal.ResolvedLib := LValue;
end;

function TPCSemantics.DoOrdinalKindOf(const AType: TPCTypeExpr): TPCOrdinalKind;
var
  LToken: TPCTokenKind;
  LBits: Integer;
  LIsUnsigned: Boolean;
begin
  // The ordinal family a type belongs to; an error or opaque type has none
  Result := okNone;
  if (AType = nil) or DoIsErrorType(AType) or DoIsOpaqueTier(AType) then
    Exit;
  if AType.Canon() is TPCChoicesType then
    Exit(okChoices);
  if not DoBuiltinOf(AType, LToken) then
    Exit;
  if DoIntTypeInfo(LToken, LBits, LIsUnsigned) then
    Result := okInteger
  else if LToken = tkKwBool then
    Result := okBool
  else if LToken = tkKwChar then
    Result := okChar
  else if LToken = tkKwWchar then
    Result := okWChar;
end;

function TPCSemantics.DoSameOrdinalFamily(const AFirst: TPCTypeExpr; const ASecond: TPCTypeExpr): Boolean;
var
  LKind: TPCOrdinalKind;
begin
  // Bounds of one family (decls.md sets / arrays): integer, char, or one
  // choices type (one Canon node)
  LKind := DoOrdinalKindOf(AFirst);
  if (LKind = okNone) or (LKind <> DoOrdinalKindOf(ASecond)) then
    Exit(False);
  if LKind = okChoices then
    Exit(AFirst.Canon() = ASecond.Canon());
  Result := (LKind = okInteger) or (LKind = okChar);
end;

function TPCSemantics.DoFoldedInteger(const AExpr: TPCExpr): Boolean;
begin
  // A folded integer value that was not reported (a poisoned node holds none)
  Result := (AExpr <> nil) and AExpr.HasConstValue and not DoIsPoisoned(AExpr);
end;

procedure TPCSemantics.DoConstWide(const AExpr: TPCExpr; out AHigh: Int64; out ALow: UInt64);
begin
  // A folded integer as a 128-bit two's complement pair (AHigh signed, ALow
  // unsigned): a signed and an unsigned value compare without overflow
  if AExpr.ConstIsUnsigned then
  begin
    AHigh := 0;
    ALow := AExpr.ConstUInt;
    Exit;
  end;
  if AExpr.ConstInt < 0 then
    AHigh := -1
  else
    AHigh := 0;
  ALow := UInt64(AExpr.ConstInt);
end;

function TPCSemantics.DoConstText(const AExpr: TPCExpr): string;
begin
  // A folded integer as the user reads it: the AST's one spelling
  // (TPCAst.FoldedText), which the emitter and the frontend check print too
  TPCAst.FoldedText(AExpr, Result);
end;

function TPCSemantics.DoBoundsReversed(const ALowExpr: TPCExpr; const AHighExpr: TPCExpr): Boolean;
var
  LLowHigh: Int64;
  LLowLow: UInt64;
  LHighHigh: Int64;
  LHighLow: UInt64;
begin
  // low > high for two folded integers of either signedness
  DoConstWide(ALowExpr, LLowHigh, LLowLow);
  DoConstWide(AHighExpr, LHighHigh, LHighLow);
  Result := (LLowHigh > LHighHigh) or ((LLowHigh = LHighHigh) and (LLowLow > LHighLow));
end;

function TPCSemantics.DoCountTooLarge(const ALowExpr: TPCExpr; const AHighExpr: TPCExpr): Boolean;
var
  LLowHigh: Int64;
  LLowLow: UInt64;
  LHighHigh: Int64;
  LHighLow: UInt64;
  LBelowZero: UInt64;
begin
  // F47: a static array of high - low + 1 elements past PC_MAX_OBJECT_SIZE
  // exists on no target (no element is smaller than one byte). Judged on
  // DoConstWide's pairs with no wrapping arithmetic, so a full Int64 range
  // (2^64 elements) is too large and never a count of 0. The caller checked
  // low <= high. count > cap <=> high - low >= cap
  DoConstWide(ALowExpr, LLowHigh, LLowLow);
  DoConstWide(AHighExpr, LHighHigh, LHighLow);
  if LLowHigh = LHighHigh then
    // Both on one side of 0: the low words subtract without a borrow
    Result := (LHighLow - LLowLow) >= PC_MAX_OBJECT_SIZE
  else if (LLowHigh = -1) and (LHighHigh = 0) then
  begin
    // A negative low, a high at or above 0: high + |low|. Each is judged
    // alone first, so the sum of two values below the cap cannot wrap
    LBelowZero := (not LLowLow) + 1;
    Result := (LHighLow >= PC_MAX_OBJECT_SIZE) or (LBelowZero >= PC_MAX_OBJECT_SIZE) or
      ((LHighLow + LBelowZero) >= PC_MAX_OBJECT_SIZE);
  end
  else
    // A bound past 64 bits: wider than any cap
    Result := True;
end;

function TPCSemantics.DoMemberCount(const ALowExpr: TPCExpr; const AHighExpr: TPCExpr; out AText: string): Boolean;

  function DoDecimalSum(const AFirst: string; const ASecond: string): string;
  var
    LFirstIndex: Integer;
    LSecondIndex: Integer;
    LCarryDigit: Integer;
    LDigit: Integer;
  begin
    // Two non-negative decimal texts added digit by digit (a count past 64 bits)
    Result := '';
    LFirstIndex := Length(AFirst);
    LSecondIndex := Length(ASecond);
    LCarryDigit := 0;
    while (LFirstIndex > 0) or (LSecondIndex > 0) or (LCarryDigit > 0) do
    begin
      LDigit := LCarryDigit;
      if LFirstIndex > 0 then
      begin
        LDigit := LDigit + Ord(AFirst[LFirstIndex]) - Ord('0');
        Dec(LFirstIndex);
      end;
      if LSecondIndex > 0 then
      begin
        LDigit := LDigit + Ord(ASecond[LSecondIndex]) - Ord('0');
        Dec(LSecondIndex);
      end;
      Result := Chr(Ord('0') + (LDigit mod 10)) + Result;
      LCarryDigit := LDigit div 10;
    end;
  end;

const
  { POW64_TEXT }
  POW64_TEXT = '18446744073709551616';
var
  LLowNegative: Boolean;
  LHighNegative: Boolean;
  LHighValue: UInt64;
  LLowValue: UInt64;
  LMagnitude: UInt64;
  LDiff: UInt64;
  LCount: UInt64;
  LCarry: Boolean;
begin
  // high - low + 1 for folded bounds with low <= high (the caller checked
  // DoBoundsReversed first). The difference passes 64 bits only for a
  // negative low and a high past High(Int64); it is computed without
  // wrapping arithmetic: LCarry = the count holds 2^64 on top of LCount.
  // Result = more members than PC_SET_MAX_MEMBERS
  LLowNegative := (not ALowExpr.ConstIsUnsigned) and (ALowExpr.ConstInt < 0);
  LHighNegative := (not AHighExpr.ConstIsUnsigned) and (AHighExpr.ConstInt < 0);
  LCarry := False;
  if LHighNegative then
    // both negative (low <= high): an Int64 difference never overflows
    LDiff := UInt64(AHighExpr.ConstInt - ALowExpr.ConstInt)
  else
  begin
    if AHighExpr.ConstIsUnsigned then
      LHighValue := AHighExpr.ConstUInt
    else
      LHighValue := UInt64(AHighExpr.ConstInt);
    if not LLowNegative then
    begin
      // both >= 0 and high >= low
      if ALowExpr.ConstIsUnsigned then
        LLowValue := ALowExpr.ConstUInt
      else
        LLowValue := UInt64(ALowExpr.ConstInt);
      LDiff := LHighValue - LLowValue;
    end
    else
    begin
      // |low| is 1 .. 2^63; high + |low| may pass 64 bits
      LMagnitude := UInt64(-(ALowExpr.ConstInt + 1)) + 1;
      if LHighValue > High(UInt64) - LMagnitude then
      begin
        LCarry := True;
        LDiff := LHighValue - (High(UInt64) - LMagnitude) - 1;
      end
      else
        LDiff := LHighValue + LMagnitude;
    end;
  end;
  // + 1: past High(UInt64) only when no carry was taken yet
  if LCarry then
    LCount := LDiff + 1
  else if LDiff = High(UInt64) then
  begin
    LCarry := True;
    LCount := 0;
  end
  else
    LCount := LDiff + 1;
  if LCarry then
    AText := DoDecimalSum(POW64_TEXT, UIntToStr(LCount))
  else
    AText := UIntToStr(LCount);
  Result := LCarry or (LCount > PC_SET_MAX_MEMBERS);
end;

procedure TPCSemantics.DoCheckAlign(const ARecord: TPCRecordType);
var
  LExpr: TPCExpr;
  LValue: UInt64;
  LIsPower: Boolean;
begin
  // BNF sec 3: align(n) is a power of two (SM0310) and at most PC_ALIGN_MAX
  // on every target (SM0312, parity). Not below the record's natural
  // alignment is DoCheckNaturalAlign's (SM0311: it reads the fields' types,
  // so it runs after the members). A non-constant was reported by
  // DoCheckConstant (poisoned: no value)
  LExpr := ARecord.AlignExpr;
  if not DoFoldedAlign(LExpr, LValue) then
    Exit;
  // A power of two has exactly one bit set
  LIsPower := (LValue <> 0) and ((LValue and (LValue - 1)) = 0);
  if not LIsPower then
    DoError(LExpr, PC_ERR_SEM_310, AlignPowerText(DoConstText(LExpr)), [])
  else if LValue > PC_ALIGN_MAX then
    DoError(LExpr, PC_ERR_SEM_312, AlignMaxText(DoConstText(LExpr)), []);
end;

function TPCSemantics.DoFoldedAlign(const AExpr: TPCExpr; out AValue: UInt64): Boolean;
begin
  // An align value SEM folded, as an unsigned count: a value at or below 0
  // reads 0 (no power of two). False = no value: no align clause, a C++
  // value (the emitter's check judges it: SM0310 / SM0312 / SM0311, F31), or
  // a non-constant DoCheckConstant reported (poisoned)
  AValue := 0;
  if not DoFoldedInteger(AExpr) then
    Exit(False);
  if AExpr.ConstIsUnsigned then
    AValue := AExpr.ConstUInt
  else if AExpr.ConstInt > 0 then
    AValue := UInt64(AExpr.ConstInt);
  Result := True;
end;

class function TPCSemantics.DoIsAlignValue(const AValue: UInt64): Boolean;
begin
  // A value DoCheckAlign accepts: a power of two (one bit set) at most
  // PC_ALIGN_MAX. Any other value was reported there and is judged no further
  Result := (AValue <> 0) and ((AValue and (AValue - 1)) = 0) and (AValue <= PC_ALIGN_MAX);
end;

function TPCSemantics.DoAlignOfKind(const AKind: TPCAlignKind): UInt64;
begin
  // The kind's alignment on the module's target (PC_ALIGN_MODELS, read
  // through DoModelTarget); 0 = unknown. wchar is the one kind whose
  // alignment moves with the target: with no target (the filter reported
  // the @target) it is unknown, as every target-dependent check stays
  // silent (D-A3a-1)
  if (AKind = akWChar) and FModule.ResolvedTarget.IsEmpty() then
    Exit(0);
  Result := UInt64(Max(0, DoModelTarget().AlignOf(AKind)));
end;

function TPCSemantics.DoBuiltinAlign(const AToken: TPCTokenKind): UInt64;
begin
  // A builtin as the emitter writes it (DoBuiltinText). The varargs pack
  // (::pcpp::VarArgs) is only a routine local (SM0422): no row, unknown
  case AToken of
    tkKwInt8:
      Result := DoAlignOfKind(akInt8);
    tkKwInt16:
      Result := DoAlignOfKind(akInt16);
    tkKwInt32:
      Result := DoAlignOfKind(akInt32);
    tkKwInt64:
      Result := DoAlignOfKind(akInt64);
    tkKwUint8:
      Result := DoAlignOfKind(akUInt8);
    tkKwUint16:
      Result := DoAlignOfKind(akUInt16);
    tkKwUint32:
      Result := DoAlignOfKind(akUInt32);
    tkKwUint64:
      Result := DoAlignOfKind(akUInt64);
    tkKwFloat32:
      Result := DoAlignOfKind(akFloat32);
    tkKwFloat64:
      Result := DoAlignOfKind(akFloat64);
    tkKwBool:
      Result := DoAlignOfKind(akBool);
    tkKwChar:
      Result := DoAlignOfKind(akChar);
    tkKwWchar:
      Result := DoAlignOfKind(akWChar);
    tkKwString:
      Result := DoAlignOfKind(akString);
    tkKwWstring:
      Result := DoAlignOfKind(akWString);
    tkKwPtr:
      Result := DoAlignOfKind(akPointer);
  else
    Result := 0;
  end;
end;

function TPCSemantics.DoTypeAlign(const AType: TPCTypeExpr; const AVisited: TList<TPCTypeExpr>): UInt64;
var
  LCanon: TPCTypeExpr;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
  LArray: TPCArrayType;
  LRecord: TPCRecordType;
  LNatural: UInt64;
  LValue: UInt64;
begin
  // The alignment of a type as the emitter writes it (r-b-align.md "Natural
  // alignment rule"); 0 = unknown, clang alone lays it out: a C/C++ type or
  // name (the opaque tier), a forward with no full, a type CORE reported, a
  // by-value cycle (SM0300 reported), anything without a row
  Result := 0;
  if DoIsErrorType(AType) or DoIsOpaqueTier(AType) then
    Exit;
  LCanon := AType.Canon();
  if LCanon is TPCBuiltinType then
    Exit(DoBuiltinAlign(TPCBuiltinType(LCanon).BuiltinToken));
  // ptr, ptr to T, an address of (one pointer rule); a routine type is a
  // function pointer
  if TPCTypeExpr.PointerOf(LCanon, LTarget, LIsConst) then
    Exit(DoAlignOfKind(akPointer));
  if LCanon is TPCRoutineType then
    Exit(DoAlignOfKind(akRoutine));
  if LCanon is TPCArrayType then
  begin
    // std::vector<T> holds its elements elsewhere; ::pcpp::Array<T, N> (a C
    // array member) is its element's alignment (P7)
    LArray := TPCArrayType(LCanon);
    if LArray.IsDynamic then
      Exit(DoAlignOfKind(akDynArray));
    Exit(DoTypeAlign(LArray.ElementType, AVisited));
  end;
  if LCanon is TPCSetType then
    Exit(DoAlignOfKind(akSet));
  if LCanon is TPCChoicesType then
  begin
    // enum class : std::int32_t / std::int64_t (UnderlyingBits, the one rule)
    if TPCChoicesType(LCanon).UnderlyingBits() = 64 then
      Exit(DoAlignOfKind(akInt64));
    Exit(DoAlignOfKind(akInt32));
  end;
  if LCanon is TPCRecordType then
  begin
    // A record / object: its align value when it has one (the stricter of
    // the value and its natural alignment, P3), else its natural alignment.
    // An align value SEM has no number for (a C++ value, one DoCheckAlign
    // reported) leaves it unknown
    LRecord := TPCRecordType(LCanon);
    LNatural := DoNaturalAlign(LRecord, AVisited);
    if (LNatural = 0) or (LRecord.AlignExpr = nil) then
      Exit(LNatural);
    if not DoFoldedAlign(LRecord.AlignExpr, LValue) or not DoIsAlignValue(LValue) then
      Exit(0);
    if LValue > LNatural then
      Exit(LValue);
    Exit(LNatural);
  end;
  if LCanon is TPCOverlayType then
  begin
    // A union: its strictest member. AVisited stops a by-value cycle
    if AVisited.Contains(LCanon) then
      Exit(0);
    AVisited.Add(LCanon);
    try
      Result := DoMembersAlign(TPCOverlayType(LCanon).Members, AVisited);
    finally
      AVisited.Remove(LCanon);
    end;
  end;
end;

function TPCSemantics.DoMembersAlign(const AMembers: TList<TPCMemberItem>;
  const AVisited: TList<TPCTypeExpr>): UInt64;
var
  LMember: TPCMemberItem;
  LAggregate: TPCAnonAggregate;
  LAlign: UInt64;
begin
  // The strictest alignment of a member list, at least 1 (an empty record
  // is 1, P3): a field its type's (a bitfield its declared type's, P8), an
  // anonymous aggregate its members' (a packed anonymous record 1); methods
  // hold no data. A member clang alone lays out, or one the parser skipped
  // (an error member), makes the list unknown (0)
  Result := 1;
  if AMembers = nil then
    Exit;
  for LMember in AMembers do
  begin
    // A method, an init or a done holds no data
    if LMember is TPCRoutineMember then
      Continue;
    if (LMember is TPCField) and TPCField(LMember).IsWCharBitfield() then
      // Written char16_t on every target (F25): its alignment, not wchar's
      LAlign := DoAlignOfKind(akChar16)
    else if LMember is TPCField then
      LAlign := DoTypeAlign(TPCField(LMember).TypeExpr, AVisited)
    else if LMember is TPCAnonAggregate then
    begin
      LAggregate := TPCAnonAggregate(LMember);
      LAlign := DoMembersAlign(LAggregate.Members, AVisited);
      if (LAlign <> 0) and LAggregate.IsPacked then
        LAlign := 1;
    end
    else
      LAlign := 0;
    if LAlign = 0 then
      Exit(0);
    if LAlign > Result then
      Result := LAlign;
  end;
end;

function TPCSemantics.DoNaturalAlign(const ARecord: TPCRecordType; const AVisited: TList<TPCTypeExpr>): UInt64;
var
  LMembers: UInt64;
  LParent: UInt64;
begin
  // The record's natural alignment (r-b rule), written into the AST once
  // (ResolvedNaturalAlign; the emitter reads it, E3) and read from there
  // when asked again: the strictest of its parent's alignment and its
  // members'. packed lowers it to 1 (P2), a parent held as a member included
  // (PLAN-RECORDS M10: plain data, r4b pk_parent); a packed record with a C++
  // base class (a C/C++ parent, an object's) is unknown (clang never packs a
  // base: the emitted check judges it). Unknown anywhere = 0
  if ARecord.IsNaturalAlignComputed then
    Exit(ARecord.ResolvedNaturalAlign);
  // A record on the current path holds itself by value (SM0300 reported)
  if AVisited.Contains(ARecord) then
    Exit(0);
  AVisited.Add(ARecord);
  try
    LMembers := DoMembersAlign(ARecord.Members, AVisited);
    LParent := 1;
    if ARecord.ParentName <> nil then
      LParent := DoTypeAlign(ARecord.ParentName, AVisited);
    if (LMembers = 0) or (LParent = 0) then
      Result := 0
    else if ARecord.IsPacked and (ARecord.ParentName <> nil) and not ARecord.HasParentMember() then
      Result := 0
    else if ARecord.IsPacked then
      Result := 1
    else if LParent > LMembers then
      Result := LParent
    else
      Result := LMembers;
    // PLAN-OBJECT D7: a polymorphic object holds a vtable pointer (Itanium
    // and the mingw ABI alike: at offset 0, pointer-aligned)
    if (Result <> 0) and ARecord.IsObject and ARecord.ResolvedIsPolymorphic and
      (DoAlignOfKind(akPointer) > Result) then
      Result := DoAlignOfKind(akPointer);
  finally
    AVisited.Remove(ARecord);
  end;
  ARecord.ResolvedNaturalAlign := Result;
  ARecord.IsNaturalAlignComputed := True;
end;

procedure TPCSemantics.DoCheckNaturalAlign(const ARecord: TPCRecordType);
var
  LVisited: TList<TPCTypeExpr>;
  LNatural: UInt64;
  LValue: UInt64;
  LName: string;
begin
  // BNF sec 3: align(n) is not below the record's natural alignment, lower
  // it with packed (SM0311, PLAN-PASKAL-ERRORS E2). Every record gets its
  // natural alignment into the AST (the emitter reads it); SEM judges when
  // it is known on the module's target, a C/C++ leaf (0) is the emitted
  // check's (E3). After the members: the fields' types are resolved. A
  // packed record takes any align (P2); a value DoCheckAlign reported is
  // judged no further
  LVisited := TList<TPCTypeExpr>.Create();
  try
    LNatural := DoNaturalAlign(ARecord, LVisited);
  finally
    LVisited.Free();
  end;
  if (ARecord.AlignExpr = nil) or ARecord.IsPacked or (LNatural = 0) then
    Exit;
  if not DoFoldedAlign(ARecord.AlignExpr, LValue) or not DoIsAlignValue(LValue) then
    Exit;
  if LValue >= LNatural then
    Exit;
  LName := DoDefiningName(ARecord);
  DoError(ARecord.AlignExpr, PC_ERR_SEM_311,
    AlignNaturalText(DoConstText(ARecord.AlignExpr), LNatural, LName), []);
end;

function TPCSemantics.DoDefiningName(const AType: TPCTypeExpr): string;
begin
  // A record / overlay is always a type declaration's TypeDef (BNF sec 4):
  // the innermost one being defined names it, else its own spelling
  if (FDefining.Count > 0) and (FDefining.Last.TypeDef = AType) then
    Result := FDefining.Last.DeclName
  else
    Result := AType.TypeText();
end;

procedure TPCSemantics.DoCheckPackedRecord(const ARecord: TPCRecordType);
var
  LName: string;
begin
  // PLAN-RECORDS M9: a packed record packs as written, so each field (and a
  // parent held as a member, M10) must be plain data: a string / wstring /
  // dynamic array held by value never packs (SM0331 here). A leaf only clang
  // lays out is the emitted check's (TPCFieldPacking fpClangDecides). After
  // the members: the fields' types are resolved
  LName := DoDefiningName(ARecord);
  if ARecord.IsPacked and ARecord.HasParentMember() and
    (ARecord.ParentName.FieldPacking() = fpNeverPacks) then
    DoError(ARecord.ParentName, PC_ERR_SEM_331,
      PackedFieldText('', LName, ARecord.ParentName.TypeText(), False), []);
  DoCheckPackedFields(ARecord.Members, ARecord.IsPacked, LName);
end;

procedure TPCSemantics.DoCheckPackedFields(const AMembers: TList<TPCMemberItem>; const AInPacked: Boolean;
  const AName: string);
var
  LMember: TPCMemberItem;
  LField: TPCField;
  LAggregate: TPCAnonAggregate;
begin
  // The fields packed where they stand: those of a packed record, of an
  // anonymous record inside one, and of a packed anonymous record in one;
  // methods hold no data. A field that shares an overlay's storage (an
  // anonymous overlay and everything in it) is the overlay rule's: a string /
  // wstring / dynamic array there is SM0313 packed or not (F34: one report
  // per mistake; the emitter still asserts both checks for a C/C++ leaf)
  if AMembers = nil then
    Exit;
  for LMember in AMembers do
  begin
    if LMember is TPCField then
    begin
      LField := TPCField(LMember);
      if AInPacked and (LField.TypeExpr <> nil) and (LField.TypeExpr.FieldPacking() = fpNeverPacks) then
        DoError(LField, PC_ERR_SEM_331,
          PackedFieldText(LField.FieldName, AName, LField.TypeExpr.TypeText(), False), []);
    end
    else if (LMember is TPCAnonAggregate) and not TPCAnonAggregate(LMember).IsOverlay then
    begin
      LAggregate := TPCAnonAggregate(LMember);
      DoCheckPackedFields(LAggregate.Members, AInPacked or LAggregate.IsPacked, AName);
    end;
  end;
end;

procedure TPCSemantics.DoCheckOverlayFields(const AMembers: TList<TPCMemberItem>; const AInOverlay: Boolean;
  const AName: string);
var
  LMember: TPCMemberItem;
  LField: TPCField;
  LAggregate: TPCAnonAggregate;
  LObject: TPCTypeExpr;
begin
  // PLAN-COMPLIANCE F34: a field that shares an overlay's storage (one of an
  // overlay, of an anonymous overlay anywhere, of an anonymous record inside
  // either) is a C++ union member: its type must be trivial data, or the
  // union's special members are deleted and clang fails in C++ words. A
  // string / wstring / dynamic array held at any depth is SM0313 here; a leaf
  // only clang knows is the emitted check's (TPCOverlayFit ofClangDecides).
  // An object or owner held is SM0357's (DoMemberItem): not reported twice.
  // A bitfield's type is an integer or choices: trivial. After the members:
  // the fields' types are resolved
  if AMembers = nil then
    Exit;
  for LMember in AMembers do
  begin
    if LMember is TPCField then
    begin
      LField := TPCField(LMember);
      if AInOverlay and (LField.TypeExpr <> nil) and (LField.TypeExpr.OverlayFit() = ofNeverFits) and
        not DoHoldsObject(LField.TypeExpr, LObject) and not DoHoldsOwner(LField.TypeExpr, LObject) then
        DoError(LField, PC_ERR_SEM_313,
          OverlayFieldText(LField.FieldName, AName, LField.TypeExpr.TypeText(), False), []);
    end
    else if LMember is TPCAnonAggregate then
    begin
      LAggregate := TPCAnonAggregate(LMember);
      DoCheckOverlayFields(LAggregate.Members, AInOverlay or LAggregate.IsOverlay, AName);
    end;
  end;
end;

class function TPCSemantics.AlignNaturalText(const AValueText: string; const ANatural: UInt64;
  const ATypeName: string): string;
begin
  // Formatted here and passed on as a finished message (no '%' in a number
  // or a PaskalCPP identifier); the count as text: Format's %d is Int64's
  Result := Format(RSSemDeclAlignNatural, [AValueText, UIntToStr(ANatural), ATypeName]);
end;

class function TPCSemantics.AlignPowerText(const AValueText: string): string;
begin
  // SM0310's message, one routine for SEM and the emitted check (F31)
  Result := Format(RSSemDeclAlignPower, [AValueText]);
end;

class function TPCSemantics.TooLargeText(const ATypeText: string): string;
begin
  // SM0277's message: the arguments SEM's own report formats with (F47); the
  // cap as text (Format's %d is Int64's)
  Result := Format(RSSemTypeTooLarge, [ATypeText, UIntToStr(PC_MAX_OBJECT_SIZE)]);
end;

class function TPCSemantics.NeedsOverrideText(const AName: string; const AOwner: string): string;
begin
  // SM0332's message, one routine for SEM (a PaskalCPP ancestor's virtual)
  // and the Compiler's report of clang's -Wsuggest-override (O13b)
  Result := Format(RSSemDeclNeedsOverride, [AName, AOwner, AName]);
end;

class function TPCSemantics.OverridesNothingText(const AName: string; const ARecordName: string): string;
begin
  // SM0333's message: SEM's (no PaskalCPP level) and the Compiler's (clang:
  // no C/C++ virtual of the name either, O13b (4))
  Result := Format(RSSemDeclOverridesNothing, [AName, ARecordName, AName]);
end;

class function TPCSemantics.OverrideCppSignatureText(const AName: string; const ACppParent: string): string;
begin
  // SM0334's message when clang finds a C/C++ virtual of the name that this
  // override does not match (parameters, result or const; O13b (4))
  Result := Format(RSSemDeclOverrideCppSignature, [AName, AName, ACppParent, AName]);
end;

class function TPCSemantics.AlignMaxText(const AValueText: string): string;
begin
  // SM0312's message, one routine for SEM and the emitted check (F31)
  Result := Format(RSSemDeclAlignMax, [AValueText, PC_ALIGN_MAX]);
end;

class function TPCSemantics.PrintNoFormatterText(const ATypeText: string): string;
begin
  // SM0425 for a C/C++ type std::format has no formatter for (E7)
  Result := Format(RSSemCallNoFormatter, [ATypeText]);
end;

class function TPCSemantics.UnprintableArgText(const AArg: TPCExpr): string;
var
  LForm: TPCPrintForm;
begin
  // The argument's print form decides (TPCTypeExpr.PrintFormOfArg, the one
  // rule print / println and the emitter read)
  Result := '';
  if AArg = nil then
    Exit;
  LForm := TPCTypeExpr.PrintFormOfArg(AArg);
  if (LForm = pfUnprintable) and (AArg.ResolvedType <> nil) then
    Result := Format(RSSemCallUnprintable, [AArg.ResolvedType.TypeText()])
  else if LForm = pfNoAddress then
    Result := Format(RSSemCallNoAddress, [AArg.ExprText()]);
end;

class function TPCSemantics.NoFormatterArgsText(const ACalleeText: string): string;
begin
  // SM0425 at the call: one of its C/C++ arguments has no std::formatter
  Result := Format(RSSemCallNoFormatterArgs, [ACalleeText]);
end;

class function TPCSemantics.FormatMismatchText(const AFormatText: string; const ACount: Integer): string;
begin
  // SM0502: AFormatText is the literal as written, ACount the arguments after it
  Result := Format(RSSemCallFormatMismatch, [AFormatText, ACount]);
end;

class function TPCSemantics.FormatNotLiteralText(const AFormatText: string): string;
begin
  // SM0500: AFormatText is the value as written
  Result := Format(RSSemCallFormatNotLiteral, [AFormatText]);
end;

class function TPCSemantics.PackedFieldText(const AFieldName: string; const ARecordName: string;
  const ATypeText: string; const AByClang: Boolean): string;
begin
  // SM0331, one routine for SEM and the emitted packed-field check (M9)
  if AFieldName = '' then
  begin
    if AByClang then
      Result := Format(RSSemDeclPackedParentCpp, [ARecordName, ATypeText])
    else
      Result := Format(RSSemDeclPackedParent, [ARecordName, ATypeText]);
  end
  else if AByClang then
    Result := Format(RSSemDeclPackedFieldCpp, [AFieldName, ARecordName, ATypeText])
  else
    Result := Format(RSSemDeclPackedField, [AFieldName, ARecordName, ATypeText]);
end;

class function TPCSemantics.OverlayFieldText(const AFieldName: string; const AName: string;
  const ATypeText: string; const AByClang: Boolean): string;
begin
  // SM0313, one routine for SEM and the emitted overlay-field check (F34)
  if AByClang then
    Result := Format(RSSemDeclOverlayFieldCpp, [AFieldName, AName, ATypeText])
  else
    Result := Format(RSSemDeclOverlayField, [AFieldName, AName, ATypeText]);
end;

procedure TPCSemantics.DoCheckBitfield(const AField: TPCField);
var
  LExpr: TPCExpr;
  LType: TPCTypeExpr;
  LKind: TPCOrdinalKind;
  LToken: TPCTokenKind;
  LBits: Integer;
  LIsUnsigned: Boolean;
  LInRange: Boolean;
  LWidth: Int64;
  LMax: Int64;
  LMin: Int64;
  LValue: TPCChoiceValue;
begin
  // BNF sec 3: a bitfield is an integer, bool, char, wchar or choices field
  // (SM0314); its width is 1 .. its type's bits, the same on every target
  // (SM0315: wchar 16, bool / char 8, a choices type its UnderlyingBits); a
  // choices field holds every ordinal as a signed value (SM0316: clang
  // takes a narrower one and the value changes). A C type's bitfield is
  // clang's. A choices type is always declared before the field (no forward
  // choices, SM0305; a name sees only the items before it), so its
  // ordinals are resolved by now
  LExpr := AField.BitWidthExpr;
  if not DoFoldedInteger(LExpr) then
    Exit;
  LType := AField.TypeExpr;
  if (LType = nil) or DoIsErrorType(LType) or DoIsOpaqueTier(LType) then
    Exit;
  LKind := DoOrdinalKindOf(LType);
  if LKind = okNone then
  begin
    DoError(AField, PC_ERR_SEM_314, RSSemDeclBitfieldType, []);
    Exit;
  end;
  if LKind = okInteger then
  begin
    // An okInteger type is a builtin integer token (DoOrdinalKindOf)
    DoBuiltinOf(LType, LToken);
    DoIntTypeInfo(LToken, LBits, LIsUnsigned);
  end
  else if LKind = okWChar then
    LBits := PC_BITFIELD_WCHAR_BITS
  else if LKind = okChoices then
    LBits := TPCChoicesType(LType.Canon()).UnderlyingBits()
  else
    LBits := PC_BITFIELD_BYTE_BITS;
  if LExpr.ConstIsUnsigned then
    LInRange := (LExpr.ConstUInt >= 1) and (LExpr.ConstUInt <= UInt64(LBits))
  else
    LInRange := (LExpr.ConstInt >= 1) and (LExpr.ConstInt <= LBits);
  if not LInRange then
  begin
    DoError(LExpr, PC_ERR_SEM_315, RSSemDeclBitfieldWidth, [DoConstText(LExpr), LBits]);
    Exit;
  end;
  if LKind <> okChoices then
    Exit;
  if LExpr.ConstIsUnsigned then
    LWidth := Int64(LExpr.ConstUInt)
  else
    LWidth := LExpr.ConstInt;
  // The signed range of LWidth bits (1 .. 64): -2^(w-1) .. 2^(w-1) - 1. At
  // 64 bits every Int64 fits (the shift would overflow): nothing to check
  if LWidth >= 64 then
    Exit;
  LMax := (Int64(1) shl (LWidth - 1)) - 1;
  LMin := -LMax - 1;
  for LValue in TPCChoicesType(LType.Canon()).Values do
  begin
    if (LValue <> nil) and LValue.HasResolvedOrdinal and
      ((LValue.ResolvedOrdinal < LMin) or (LValue.ResolvedOrdinal > LMax)) then
    begin
      DoError(LExpr, PC_ERR_SEM_316, RSSemDeclBitfieldOrdinals, [DoConstText(LExpr), LType.TypeText()]);
      Exit;
    end;
  end;
end;

procedure TPCSemantics.DoCheckBitfieldStore(const AValue: TPCExpr; const AField: TPCField);
var
  LType: TPCTypeExpr;
  LToken: TPCTokenKind;
  LTypeBits: Integer;
  LIsUnsigned: Boolean;
  LWidth: Int64;
  LLow: Int64;
  LHigh: Int64;
  LValueHigh: Int64;
  LValueLow: UInt64;
  LBoundHigh: Int64;
  LBoundLow: UInt64;
  LFits: Boolean;
begin
  // F38: a constant stored into a PaskalCPP bitfield (an assignment, a
  // record literal's field) must be held by the field's width, or the store
  // changes it (clang reported that in C++ words). Signed: a signed integer,
  // char on a signed-char target, a choices type (BNF sec 4: its ordinals
  // as signed values); unsigned: an unsigned integer, wchar (char16_t, F25);
  // bool holds 0 / 1 at any width. SM0200 "does not fit" at the value, with
  // the field's range. Not judged: a width SEM reported (SM0315) or did not
  // fold, a C/C++ field type, a value that is no folded integer
  if (AField = nil) or (AField.BitWidthExpr = nil) or not DoFoldedInteger(AValue) or
    not DoFoldedInteger(AField.BitWidthExpr) then
    Exit;
  LType := AField.TypeExpr;
  if (LType = nil) or DoIsErrorType(LType) or DoIsOpaqueTier(LType) then
    Exit;
  case DoOrdinalKindOf(LType) of
    okInteger:
      begin
        // An okInteger type is a builtin integer token (DoOrdinalKindOf)
        DoBuiltinOf(LType, LToken);
        DoIntTypeInfo(LToken, LTypeBits, LIsUnsigned);
      end;
    okChar:
      begin
        LTypeBits := PC_BITFIELD_BYTE_BITS;
        LIsUnsigned := not DoModelTarget().IsCharSigned();
      end;
    okWChar:
      begin
        LTypeBits := PC_BITFIELD_WCHAR_BITS;
        LIsUnsigned := True;
      end;
    okChoices:
      begin
        LTypeBits := TPCChoicesType(LType.Canon()).UnderlyingBits();
        LIsUnsigned := False;
      end;
  else
    // bool, or no PaskalCPP ordinal (SM0314 reported it)
    Exit;
  end;
  if AField.BitWidthExpr.ConstIsUnsigned then
  begin
    if AField.BitWidthExpr.ConstUInt > UInt64(LTypeBits) then
      Exit;
    LWidth := Int64(AField.BitWidthExpr.ConstUInt);
  end
  else
    LWidth := AField.BitWidthExpr.ConstInt;
  // A width outside 1 .. the type's bits is SM0315's; at 64 bits every
  // value the conversion took fits
  if (LWidth < 1) or (LWidth > LTypeBits) or (LWidth >= 64) then
    Exit;
  if LIsUnsigned then
  begin
    LLow := 0;
    LHigh := (Int64(1) shl LWidth) - 1;
  end
  else
  begin
    LHigh := (Int64(1) shl (LWidth - 1)) - 1;
    LLow := -LHigh - 1;
  end;
  // The value and each bound as 128-bit pairs (DoConstWide's form), so a
  // signed and an unsigned value compare without overflow
  DoConstWide(AValue, LValueHigh, LValueLow);
  if LLow < 0 then
    LBoundHigh := -1
  else
    LBoundHigh := 0;
  LBoundLow := UInt64(LLow);
  LFits := (LValueHigh > LBoundHigh) or ((LValueHigh = LBoundHigh) and (LValueLow >= LBoundLow));
  LBoundHigh := 0;
  LBoundLow := UInt64(LHigh);
  LFits := LFits and ((LValueHigh < LBoundHigh) or ((LValueHigh = LBoundHigh) and (LValueLow <= LBoundLow)));
  if LFits then
    Exit;
  DoError(AValue, PC_ERR_SEM_200, RSSemTypeNotFit,
    [DoConstText(AValue), LType.TypeText() + ' : ' + DoConstText(AField.BitWidthExpr), IntToStr(LLow),
    IntToStr(LHigh)]);
  DoPoison(AValue);
end;

procedure TPCSemantics.DoCheckParent(const ARecord: TPCRecordType);
var
  LParent: TPCNamedType;
  LCanon: TPCTypeExpr;
  LWhat: string;
begin
  // decls.md TPCRecordType: a record's parent is a record, an object's an
  // object, or opaque C++ (a C struct: its members are clang's). A forward
  // with no full yet is no record (Canon stops at it): a C++ base is complete
  LParent := ARecord.ParentName;
  if (LParent = nil) or DoIsErrorType(LParent) or DoIsOpaqueTier(LParent) then
    Exit;
  LCanon := LParent.Canon();
  // PLAN-OBJECT O7: an interface's parent is an interface; an object's never
  // is one (it is named after implements: the hint)
  if (LCanon is TPCRecordType) and (TPCRecordType(LCanon).IsObject = ARecord.IsObject) and
    (TPCRecordType(LCanon).IsInterface = ARecord.IsInterface) then
  begin
    // PLAN-OBJECT D7: a final object is no parent
    if ARecord.IsObject and TPCRecordType(LCanon).IsFinal then
      DoError(LParent, PC_ERR_SEM_339, RSSemDeclFinalParent, [LParent.TypeText()]);
    // An interface repeats none of its parent's methods (SM0368)
    if ARecord.IsInterface then
      DoCheckInterfaceRepeats(ARecord, LCanon)
    else
      DoCheckParentNames(ARecord.Members, LCanon);
    Exit;
  end;
  if (LCanon is TPCRecordType) and TPCRecordType(LCanon).IsInterface and not ARecord.IsInterface and
    ARecord.IsObject then
  begin
    DoError(LParent, PC_ERR_SEM_308, RSSemDeclParentInterface, [LParent.TypeText()]);
    Exit;
  end;
  if ARecord.IsInterface then
    LWhat := RSSemDeclWhatInterface
  else if ARecord.IsObject then
    LWhat := RSSemDeclWhatObject
  else
    LWhat := RSSemDeclWhatRecord;
  DoError(LParent, PC_ERR_SEM_308, RSSemDeclParentKind, [LParent.TypeText(), LWhat]);
end;

procedure TPCSemantics.DoCheckInterfaceRepeats(const AFace: TPCRecordType; const AParent: TPCTypeExpr);
var
  LMember: TPCMemberItem;
  LRoutine: TPCRoutine;
  LFound: TList<TPCNode>;
  LParentText: string;
begin
  // PLAN-OBJECT O7: a method of an interface reuses no name of its parent
  // interfaces (SM0368 at the name, the parent's method as a note): an
  // interface method is declared once along the chain
  LParentText := AFace.ParentName.TypeText();
  LFound := TList<TPCNode>.Create();
  try
    for LMember in AFace.Members do
    begin
      if not (LMember is TPCMethodItem) or (TPCMethodItem(LMember).Routine = nil) then
        Continue;
      LRoutine := TPCMethodItem(LMember).Routine;
      LFound.Clear();
      TPCScopes.FindMember(AParent, LRoutine.DeclName, LFound);
      if LFound.Count = 0 then
        Continue;
      if DoReportRange(LRoutine.NameRange, esError, PC_ERR_SEM_368, RSSemDeclInterfaceRepeat,
        [LRoutine.DeclName, DoDefiningName(AFace), LParentText]) then
        DoNote(LFound[0], RSSemDeclMemberHere, [LParentText, LRoutine.DeclName]);
    end;
  finally
    LFound.Free();
  end;
end;

procedure TPCSemantics.DoResolveDispatch(const ARecord: TPCRecordType);
var
  LMember: TPCMemberItem;
  LParent: TPCTypeExpr;
  LFound: TList<TPCNode>;
  LNode: TPCNode;
  LLevel: TPCTypeExpr;
  LItem: TPCMemberItem;
  LAccessor: TPCAccessorItem;
begin
  // PLAN-OBJECT D7, the facts the words and the names give, written before
  // the members are walked (a method body may declare a local of this type):
  // polymorphic = a dispatched method here or a polymorphic PaskalCPP parent;
  // abstract = the nearest declaration of some method name is abstract (an
  // override below a level hides that level's: AllMembers keeps one level per
  // name, nearest first). A C/C++ parent's virtuals are clang's (O13)
  ARecord.ResolvedIsPolymorphic := False;
  ARecord.ResolvedAbstract := nil;
  ARecord.ResolvedDerivesFromCpp := False;
  if not ARecord.IsObject then
    Exit;
  // O13b: a chain reaching a C/C++ class (its virtuals are clang's)
  ARecord.ResolvedDerivesFromCpp := TPCScopes.ReachesOpaque(ARecord);
  if (ARecord.ParentName <> nil) and not DoIsErrorType(ARecord.ParentName) and
    not DoIsOpaqueTier(ARecord.ParentName) then
  begin
    LParent := ARecord.ParentName.Canon();
    if (LParent is TPCRecordType) and TPCRecordType(LParent).IsObject then
      ARecord.ResolvedIsPolymorphic := TPCRecordType(LParent).ResolvedIsPolymorphic;
  end;
  for LMember in ARecord.Members do
  begin
    if (LMember is TPCMethodItem) and TPCMethodItem(LMember).IsDispatched() then
      ARecord.ResolvedIsPolymorphic := True;
    // O10: a dispatched property's accessors are virtual
    if (LMember is TPCPropertyItem) and TPCPropertyItem(LMember).IsDispatched() then
      ARecord.ResolvedIsPolymorphic := True;
  end;
  // PLAN-OBJECT O7: an object that implements an interface has its vtable
  if ARecord.Implements.Count > 0 then
    ARecord.ResolvedIsPolymorphic := True;
  LFound := TList<TPCNode>.Create();
  try
    TPCScopes.AllMembers(ARecord, LFound);
    for LNode in LFound do
    begin
      // O10: the nearest property of a name is abstract when its read is, or
      // the write that runs for it (its own, else the overridden one's)
      if LNode is TPCPropertyItem then
      begin
        LAccessor := DoAbstractAccessor(ARecord, TPCPropertyItem(LNode));
        if LAccessor <> nil then
        begin
          ARecord.ResolvedAbstract := LAccessor;
          Exit;
        end;
        Continue;
      end;
      if not (LNode is TPCRoutine) then
        Continue;
      LLevel := TPCScopes.DeclaringLevel(ARecord, LNode);
      if LLevel = nil then
        Continue;
      LItem := TPCScopes.MemberItemOf(LLevel, LNode);
      if (LItem is TPCMethodItem) and TPCMethodItem(LItem).IsAbstract then
      begin
        ARecord.ResolvedAbstract := TPCMethodItem(LItem);
        Exit;
      end;
    end;
  finally
    LFound.Free();
  end;
end;

procedure TPCSemantics.DoCheckDispatch(const ARecord: TPCRecordType);
var
  LMember: TPCMemberItem;
begin
  // PLAN-OBJECT D7, after the members (the signatures are resolved): each
  // method's words against the parent chain. An interface's methods carry
  // the grammar's words (O7): its chain rule is SM0368 (DoCheckParent)
  if (not ARecord.IsObject) or ARecord.IsInterface then
    Exit;
  for LMember in ARecord.Members do
  begin
    if DoStopped() then
      Exit;
    if LMember is TPCMethodItem then
      DoCheckDispatchMethod(ARecord, TPCMethodItem(LMember))
    // PLAN-OBJECT O10: a property's words, as a method's
    else if LMember is TPCPropertyItem then
      DoCheckDispatchProperty(ARecord, TPCPropertyItem(LMember));
  end;
end;

procedure TPCSemantics.DoCheckImplements(const ARecord: TPCRecordType);
var
  LName: TPCNamedType;
  LFace: TPCTypeExpr;
  LSeen: TList<TPCTypeExpr>;
begin
  // PLAN-OBJECT O7 (D8), after the members: each name after implements is an
  // interface (SM0362), named once (SM0363), and the object (its chain) has
  // every method of the interface's chain (DoCheckImplementsFace). A C/C++
  // name is clang's (O13)
  ARecord.ResolvedForwards.Clear();
  ARecord.ResolvedEmbedForwards.Clear();
  ARecord.ResolvedPropertyForwards.Clear();
  if (not ARecord.IsObject) or ARecord.IsInterface or (ARecord.Implements.Count = 0) then
    Exit;
  LSeen := TList<TPCTypeExpr>.Create();
  try
    for LName in ARecord.Implements do
    begin
      if DoStopped() then
        Exit;
      if DoIsErrorType(LName) or DoIsOpaqueTier(LName) then
        Continue;
      LFace := LName.Canon();
      if not ((LFace is TPCRecordType) and TPCRecordType(LFace).IsInterface) then
      begin
        DoError(LName, PC_ERR_SEM_362, RSSemDeclNotInterface, [LName.TypeText()]);
        Continue;
      end;
      if LSeen.Contains(LFace) then
      begin
        DoError(LName, PC_ERR_SEM_363, RSSemDeclImplementsTwice, [LName.TypeText(), DoDefiningName(ARecord)]);
        Continue;
      end;
      LSeen.Add(LFace);
      DoCheckImplementsFace(ARecord, LName, TPCRecordType(LFace));
    end;
  finally
    LSeen.Free();
  end;
end;

procedure TPCSemantics.DoCheckImplementsFace(const ARecord: TPCRecordType; const AName: TPCNamedType;
  const AFace: TPCRecordType);
var
  LNeeded: TList<TPCNode>;
  LFound: TList<TPCNode>;
  LNode: TPCNode;
  LWant: TPCRoutine;
  LWantItem: TPCMemberItem;
  LHaveItem: TPCMemberItem;
  LHave: TPCMethodItem;
  LLevel: TPCTypeExpr;
  LWantLevel: TPCTypeExpr;
  LMethodName: string;
  LOwner: string;
  LHaveOwner: string;
begin
  // Every method of AFace's chain (AllMembers: one per name, nearest first)
  // against the object's chain (FindMember): none = SM0364; found, it is not
  // hidden (SM0367), it is dispatched (SM0365: write virtual, user
  // 2026-10-13) and its signature is the interface's (SM0366: modes, types,
  // result: C++'s override rule). One report per interface method, at the
  // implements name, the other side as a note. A name no PaskalCPP level
  // declares on a chain reaching C/C++ is clang's (O13)
  LNeeded := TList<TPCNode>.Create();
  LFound := TList<TPCNode>.Create();
  try
    TPCScopes.AllMembers(AFace, LNeeded);
    for LNode in LNeeded do
    begin
      if DoStopped() then
        Exit;
      // PLAN-OBJECT O10 (D8): an interface property, as a method
      if LNode is TPCPropertyItem then
      begin
        DoCheckImplementsProperty(ARecord, AName, AFace, TPCPropertyItem(LNode));
        Continue;
      end;
      if not (LNode is TPCRoutine) then
        Continue;
      LWant := TPCRoutine(LNode);
      LMethodName := LWant.DeclName;
      LWantLevel := TPCScopes.DeclaringLevel(AFace, LNode);
      if LWantLevel = nil then
        Continue;
      LWantItem := TPCScopes.MemberItemOf(LWantLevel, LNode);
      if not (LWantItem is TPCMethodItem) then
        Continue;
      LOwner := DoMethodOwnerName(AFace, AName.TypeText(), TPCMethodItem(LWantItem));
      LFound.Clear();
      TPCScopes.FindMember(ARecord, LMethodName, LFound);
      if (LFound.Count = 0) or not (LFound[0] is TPCRoutine) then
      begin
        // PLAN-OBJECT O8 (D2): an embed may provide it (forwarded), found
        // before a C/C++ parent's, as a member access finds it
        if (LFound.Count = 0) and DoImplementsByEmbed(ARecord, AName, LWant, LOwner) then
          Continue;
        if (LFound.Count = 0) and TPCScopes.ReachesOpaque(ARecord) then
          Continue;
        if DoError(AName, PC_ERR_SEM_364, RSSemDeclMissingMethod,
          [DoDefiningName(ARecord), LOwner, LMethodName, LMethodName]) then
          DoNote(LWant, RSSemDeclMemberHere, [LOwner, LMethodName]);
        Continue;
      end;
      LLevel := TPCScopes.DeclaringLevel(ARecord, LFound[0]);
      if LLevel = nil then
        Continue;
      LHaveItem := TPCScopes.MemberItemOf(LLevel, LFound[0]);
      if not (LHaveItem is TPCMethodItem) then
        Continue;
      LHave := TPCMethodItem(LHaveItem);
      LHaveOwner := DoMethodOwnerName(ARecord, DoDefiningName(ARecord), LHave);
      if LHave.IsHidden then
      begin
        if DoError(AName, PC_ERR_SEM_367, RSSemDeclImplementsHidden, [LHaveOwner, LMethodName, LOwner, LMethodName]) then
          DoNote(LHave.Routine, RSSemDeclMemberHere, [LHaveOwner, LMethodName]);
        Continue;
      end;
      if not LHave.IsDispatched() then
      begin
        if DoError(AName, PC_ERR_SEM_365, RSSemDeclImplementsPlain,
          [LHaveOwner, LMethodName, LOwner, LMethodName, LMethodName]) then
          DoNote(LHave.Routine, RSSemDeclMemberHere, [LHaveOwner, LMethodName]);
        Continue;
      end;
      // A signature with a reported part was reported once already
      if DoSignatureReported(LHave.Routine) or DoSignatureReported(LWant) then
        Continue;
      if not DoSameSignature(LHave.Routine.Signature(), LWant.Signature(), True) then
      begin
        if DoError(AName, PC_ERR_SEM_366, RSSemDeclImplementsSignature, [LHaveOwner, LMethodName, LOwner, LMethodName]) then
        begin
          DoNote(LHave.Routine, RSSemDeclMemberHere, [LHaveOwner, LMethodName]);
          DoNote(LWant, RSSemDeclMemberHere, [LOwner, LMethodName]);
        end;
        Continue;
      end;
      // O13b (3): the implementing method keeps the interface's const
      if DoConstNotKept(LHave.Routine, LWant, LOwner) then
        Continue;
      // The facts the emitter writes from: a method of this object overrides
      // the interface's in C++ (override). One a level above declares whose
      // level does not derive from the interface would leave it pure: a
      // forwarding override here (an abstract one keeps the object abstract,
      // SEM's ResolvedAbstract: nothing to forward to)
      if LLevel = ARecord then
        LHave.ResolvedImplements := TPCMethodItem(LWantItem)
      else if (not LHave.IsAbstract) and (not TPCScopes.Derives(LLevel, LWantLevel)) and
        (not ARecord.ResolvedForwards.Contains(LHave)) then
        ARecord.ResolvedForwards.Add(LHave);
    end;
  finally
    LFound.Free();
    LNeeded.Free();
  end;
end;

procedure TPCSemantics.DoCheckImplementsProperty(const ARecord: TPCRecordType; const AName: TPCNamedType;
  const AFace: TPCRecordType; const AWant: TPCPropertyItem);
var
  LFound: TList<TPCNode>;
  LHave: TPCPropertyItem;
  LLevel: TPCTypeExpr;
  LWantLevel: TPCTypeExpr;
  LName: string;
  LOwner: string;
  LHaveOwner: string;
begin
  // PLAN-OBJECT O10 (D12, D8): an interface property against the object's
  // chain, as a method (DoCheckImplementsFace): none = SM0364; found, it is
  // not hidden (SM0367), it is dispatched (SM0365: write virtual property),
  // its type and index are the interface's and it has a write where the
  // interface does (SM0366). Writes ResolvedImplements for the object's own
  // property, ResolvedPropertyForwards for an inherited one whose level does
  // not derive from the interface. A name no PaskalCPP level declares on a
  // chain reaching C/C++ is clang's (O13)
  LName := AWant.PropName;
  LWantLevel := TPCScopes.DeclaringLevel(AFace, AWant);
  if LWantLevel = nil then
    Exit;
  LOwner := DoLevelText(AFace, AName.TypeText(), LWantLevel);
  LFound := TList<TPCNode>.Create();
  try
    TPCScopes.FindMember(ARecord, LName, LFound);
    if (LFound.Count = 0) or not (LFound[0] is TPCPropertyItem) then
    begin
      if (LFound.Count = 0) and TPCScopes.ReachesOpaque(ARecord) then
        Exit;
      if DoError(AName, PC_ERR_SEM_364, RSSemDeclMissingProperty, [DoDefiningName(ARecord), LOwner, LName, LName]) then
        DoNote(AWant, RSSemDeclMemberHere, [LOwner, LName]);
      Exit;
    end;
    LHave := TPCPropertyItem(LFound[0]);
  finally
    LFound.Free();
  end;
  LLevel := TPCScopes.DeclaringLevel(ARecord, LHave);
  if LLevel = nil then
    Exit;
  LHaveOwner := DoPropertyOwnerName(ARecord, LHave);
  if LHave.IsHidden then
  begin
    if DoError(AName, PC_ERR_SEM_367, RSSemDeclImplementsHidden, [LHaveOwner, LName, LOwner, LName]) then
      DoNote(LHave, RSSemDeclMemberHere, [LHaveOwner, LName]);
    Exit;
  end;
  if not LHave.IsDispatched() then
  begin
    if DoError(AName, PC_ERR_SEM_365, RSSemDeclImplementsPlainProperty, [LHaveOwner, LName, LOwner, LName, LName]) then
      DoNote(LHave, RSSemDeclMemberHere, [LHaveOwner, LName]);
    Exit;
  end;
  // A type with a reported part was reported once already
  if DoIsErrorType(LHave.TypeExpr) or DoIsErrorType(AWant.TypeExpr) then
    Exit;
  if not DoSamePropertyShape(LHave, AWant) or
    ((DoRunningWrite(AFace, AWant) <> nil) and (DoRunningWrite(ARecord, LHave) = nil)) then
  begin
    if DoError(AName, PC_ERR_SEM_366, RSSemDeclImplementsPropertyShape, [LHaveOwner, LName, LOwner, LName]) then
    begin
      DoNote(LHave, RSSemDeclMemberHere, [LHaveOwner, LName]);
      DoNote(AWant, RSSemDeclMemberHere, [LOwner, LName]);
    end;
    Exit;
  end;
  if LLevel = ARecord then
    LHave.ResolvedImplements := AWant
  else if (DoAbstractAccessor(ARecord, LHave) = nil) and (not TPCScopes.Derives(LLevel, LWantLevel)) and
    (not ARecord.ResolvedPropertyForwards.Contains(LHave)) then
    ARecord.ResolvedPropertyForwards.Add(LHave);
end;

function TPCSemantics.DoPromote(const AMember: TPCMember; const ARecord: TPCTypeExpr; const ASearchedText: string;
  const AFound: TList<TPCNode>; out AEmbedType: TPCTypeExpr; out AEmbedText: string;
  out AHops: Integer): Boolean;
var
  LHits: TList<TPCPromotedHit>;
  LHit: TPCPromotedHit;
  LEmbed: TPCField;
  LSearched: TPCTypeExpr;
  LSearchedText: string;
  LThroughParent: Boolean;
  LName: string;
  LFirst: string;
  LSecond: string;
begin
  // FindPromoted from the searched record. None = nothing here (the caller
  // goes on to its other rules). Two at the nearest depth = SM0370 at the
  // member name, each reach as a note: the person names one. One = every
  // embed on the path is a member this access reaches too, so a hidden one
  // blocks as a hidden field would (SM0019, judged level by level from the
  // searched type down); then the path is written on the node and the member
  // handed back with the type it is searched in
  Result := True;
  AEmbedType := nil;
  AEmbedText := '';
  AHops := 0;
  LName := AMember.Member.PartText;
  LHits := TList<TPCPromotedHit>.Create();
  try
    TPCScopes.FindPromoted(ARecord, LName, LHits);
    if LHits.Count = 0 then
      Exit;
    if LHits.Count > 1 then
    begin
      LFirst := DoEmbedPathText(LHits[0].Path);
      LSecond := DoEmbedPathText(LHits[1].Path);
      if DoError(AMember.Member, PC_ERR_SEM_370, RSSemDeclEmbedShared,
        [LName, LFirst, LSecond, AMember.Base.ExprText(), LFirst, LName]) then
      begin
        for LHit in LHits do
          DoNote(LHit.Member, RSSemDeclEmbedReaches, [DoEmbedPathText(LHit.Path), LName]);
      end;
      DoPoison(AMember);
      Exit(False);
    end;
    LHit := LHits[0];
    LSearched := ARecord;
    LSearchedText := ASearchedText;
    LThroughParent := (AMember.Base is TPCSpecial) and (TPCSpecial(AMember.Base).SpecialKind = skParent);
    for LEmbed in LHit.Path do
    begin
      if DoHiddenBlocks(AMember.Member, LEmbed, LEmbed.FieldName, LSearched, LSearchedText, LThroughParent, True) then
      begin
        DoPoison(AMember);
        Exit(False);
      end;
      LSearched := LEmbed.TypeExpr.Canon();
      LSearchedText := LEmbed.TypeExpr.TypeText();
      LThroughParent := False;
    end;
    AMember.ResolvedEmbedPath := LHit.Path;
    AFound.Add(LHit.Member);
    AEmbedType := LSearched;
    AEmbedText := LSearchedText;
    AHops := LHit.Hops;
  finally
    LHits.Free();
  end;
end;

function TPCSemantics.DoImplementsByEmbed(const ARecord: TPCRecordType; const AName: TPCNamedType;
  const AWant: TPCRoutine; const AOwner: string): Boolean;
var
  LHits: TList<TPCPromotedHit>;
  LHit: TPCPromotedHit;
  LLast: TPCTypeExpr;
  LLevel: TPCTypeExpr;
  LItem: TPCMemberItem;
  LHave: TPCMethodItem;
  LHaveOwner: string;
  LForward: TPCEmbedForward;
  LKnown: TPCEmbedForward;
  LMethodName: string;
begin
  // An interface method no level of the object's chain declares, provided
  // by an embed (FindPromoted): the object forwards to it (the emitter's
  // forwarding override is the virtual one), so the embedded method need not
  // be virtual. Two embeds having it = SM0370 at the implements name; a
  // hidden method = SM0367 (the object could not call it); another signature
  // = SM0366 (both sides as notes). A hidden embed is the object's own
  // member: its forwarding override reaches it. False = no embed has a
  // method of that name (the caller reports SM0364)
  Result := False;
  LMethodName := AWant.DeclName;
  LHits := TList<TPCPromotedHit>.Create();
  try
    TPCScopes.FindPromoted(ARecord, LMethodName, LHits);
    if (LHits.Count = 0) or not (LHits[0].Member is TPCRoutine) then
      Exit;
    Result := True;
    if LHits.Count > 1 then
    begin
      if DoError(AName, PC_ERR_SEM_370, RSSemDeclEmbedSharedFace, [DoDefiningName(ARecord), AOwner, LMethodName,
        DoEmbedPathText(LHits[0].Path), DoEmbedPathText(LHits[1].Path), LMethodName]) then
      begin
        for LHit in LHits do
          DoNote(LHit.Member, RSSemDeclEmbedReaches, [DoEmbedPathText(LHit.Path), LMethodName]);
      end;
      Exit;
    end;
    LHit := LHits[0];
    if LHit.Path[High(LHit.Path)].TypeExpr = nil then
      Exit;
    LLast := LHit.Path[High(LHit.Path)].TypeExpr.Canon();
    LLevel := TPCScopes.DeclaringLevel(LLast, LHit.Member);
    LItem := TPCScopes.MemberItemOf(LLevel, LHit.Member);
    if not (LItem is TPCMethodItem) then
      Exit;
    LHave := TPCMethodItem(LItem);
    LHaveOwner := DoDefiningName(ARecord) + '.' + DoEmbedPathText(LHit.Path);
    if LHave.IsHidden then
    begin
      if DoError(AName, PC_ERR_SEM_367, RSSemDeclImplementsHidden, [LHaveOwner, LMethodName, AOwner, LMethodName]) then
        DoNote(LHave.Routine, RSSemDeclMemberHere, [LHaveOwner, LMethodName]);
      Exit;
    end;
    // A signature with a reported part was reported once already
    if DoSignatureReported(LHave.Routine) or DoSignatureReported(AWant) then
      Exit;
    if not DoSameSignature(LHave.Routine.Signature(), AWant.Signature(), True) then
    begin
      if DoError(AName, PC_ERR_SEM_366, RSSemDeclImplementsSignature, [LHaveOwner, LMethodName, AOwner, LMethodName]) then
      begin
        DoNote(LHave.Routine, RSSemDeclMemberHere, [LHaveOwner, LMethodName]);
        DoNote(AWant, RSSemDeclMemberHere, [AOwner, LMethodName]);
      end;
      Exit;
    end;
    // O13b (3): the implementing method keeps the interface's const
    if DoConstNotKept(LHave.Routine, AWant, AOwner) then
      Exit;
    // Two interfaces asking for one method of one signature: one override
    // in C++ overrides both
    for LKnown in ARecord.ResolvedEmbedForwards do
    begin
      if LKnown.Method = LHave then
        Exit;
    end;
    LForward.Method := LHave;
    LForward.Path := LHit.Path;
    ARecord.ResolvedEmbedForwards.Add(LForward);
  finally
    LHits.Free();
  end;
end;

procedure TPCSemantics.DoCheckEmbed(const AField: TPCField);
var
  LCanon: TPCTypeExpr;
begin
  // PLAN-OBJECT O8 (D2): an embed's members are reached on its object, so
  // PaskalCPP must see them: a record, an overlay or an object (an interface
  // is never held by value: SM0338, DoCheckConcrete). Anything else is SM0369
  // at the type. A reported type, or a name not resolved to a full type
  // (SM0303's), was reported once already
  if (AField.TypeExpr = nil) or DoIsErrorType(AField.TypeExpr) then
    Exit;
  // A C/C++ type's members are clang's: PaskalCPP cannot reach them
  if not DoIsOpaqueTier(AField.TypeExpr) then
  begin
    LCanon := AField.TypeExpr.Canon();
    if (LCanon = nil) or (LCanon is TPCRecordType) or (LCanon is TPCOverlayType) or (LCanon is TPCNamedType) then
      Exit;
  end;
  DoError(AField.TypeExpr, PC_ERR_SEM_369, RSSemDeclEmbedType, [AField.FieldName, AField.TypeExpr.TypeText()]);
end;

class function TPCSemantics.DoEmbedPathText(const APath: TArray<TPCField>): string;
var
  LEmbed: TPCField;
begin
  // The embeds of a path as the person writes them: F.G
  Result := '';
  for LEmbed in APath do
  begin
    if Result <> '' then
      Result := Result + '.';
    Result := Result + LEmbed.FieldName;
  end;
end;

procedure TPCSemantics.DoCheckDispatchMethod(const ARecord: TPCRecordType; const AItem: TPCMethodItem);
var
  LRoutine: TPCRoutine;
  LBase: TPCMethodItem;
  LName: string;
  LOwner: string;
  LAt: TSourceRange;
  LInside: Boolean;
begin
  // D7: final and abstract need dispatch (SM0336 / SM0337); a parent's
  // virtual method name is continued only by override (SM0332, no quiet
  // hiding); override needs a virtual method above (SM0333), not final
  // (SM0335), with the same signature (SM0334: modes, types, result: C++'s
  // override rule). A name no PaskalCPP level declares may be a C/C++ base's:
  // clang's (O13). A method the parser recovered reports nothing
  LRoutine := AItem.Routine;
  if LRoutine = nil then
    Exit;
  LName := LRoutine.DeclName;
  LInside := DoEnterRecovered(AItem);
  try
    if AItem.IsFinal and not AItem.IsDispatched() then
      DoReportRange(AItem.FinalRange, esError, PC_ERR_SEM_336, RSSemDeclFinalNotVirtual, []);
    if AItem.IsAbstract and not AItem.IsDispatched() then
      DoReportRange(AItem.AbstractRange, esError, PC_ERR_SEM_337, RSSemDeclAbstractNotVirtual, [LName]);
    LBase := DoParentMethod(ARecord, LName);
    if not AItem.IsOverride then
    begin
      if (LBase = nil) or not LBase.IsDispatched() then
        Exit;
      if AItem.IsVirtual then
        LAt := AItem.VirtualRange
      else
        LAt := LRoutine.NameRange;
      LOwner := DoMethodOwnerName(ARecord, DoDefiningName(ARecord), LBase);
      if DoReportRange(LAt, esError, PC_ERR_SEM_332, NeedsOverrideText(LName, LOwner), []) then
        DoNote(LBase.Routine, RSSemDeclMemberHere, [LOwner, LName]);
      Exit;
    end;
    if (LBase = nil) or not LBase.IsDispatched() then
    begin
      if (LBase = nil) and TPCScopes.ReachesOpaque(ARecord) then
        Exit;
      if DoReportRange(AItem.OverrideRange, esError, PC_ERR_SEM_333,
        OverridesNothingText(LName, DoDefiningName(ARecord)), []) and (LBase <> nil) then
        DoNote(LBase.Routine, RSSemDeclMemberHere, [DoMethodOwnerName(ARecord, DoDefiningName(ARecord), LBase), LName]);
      Exit;
    end;
    LOwner := DoMethodOwnerName(ARecord, DoDefiningName(ARecord), LBase);
    if LBase.IsFinal then
    begin
      if DoReportRange(AItem.OverrideRange, esError, PC_ERR_SEM_335, RSSemDeclOverrideFinal, [LOwner, LName]) then
        DoNote(LBase.Routine, RSSemDeclMemberHere, [LOwner, LName]);
      Exit;
    end;
    // A signature with a reported part was reported once already
    if DoSignatureReported(LRoutine) or DoSignatureReported(LBase.Routine) then
      Exit;
    if not DoSameSignature(LRoutine.Signature(), LBase.Routine.Signature(), True) then
    begin
      if DoReportRange(LRoutine.NameRange, esError, PC_ERR_SEM_334, RSSemDeclOverrideSignature, [LName, LOwner, LName]) then
        DoNote(LBase.Routine, RSSemDeclMemberHere, [LOwner, LName]);
      Exit;
    end;
    // O13b (3): an override keeps the const of the method it overrides
    if DoConstNotKept(LRoutine, LBase.Routine, LOwner) then
      Exit;
    AItem.ResolvedOverrides := LBase;
  finally
    if LInside then
      DoLeaveRecovered();
  end;
end;

function TPCSemantics.DoParentMethod(const ARecord: TPCRecordType; const AName: string): TPCMethodItem;
var
  LParent: TPCTypeExpr;
  LFound: TList<TPCNode>;
  LLevel: TPCTypeExpr;
  LItem: TPCMemberItem;
begin
  // The method named AName of the nearest PaskalCPP object level above
  // ARecord (FindMember's walk from the parent); nil = none, or a field of
  // that name (SM0309's)
  Result := nil;
  if (ARecord.ParentName = nil) or DoIsErrorType(ARecord.ParentName) or DoIsOpaqueTier(ARecord.ParentName) then
    Exit;
  LParent := ARecord.ParentName.Canon();
  if not ((LParent is TPCRecordType) and TPCRecordType(LParent).IsObject) then
    Exit;
  LFound := TList<TPCNode>.Create();
  try
    TPCScopes.FindMember(LParent, AName, LFound);
    if (LFound.Count = 0) or not (LFound[0] is TPCRoutine) then
      Exit;
    LLevel := TPCScopes.DeclaringLevel(LParent, LFound[0]);
    if LLevel = nil then
      Exit;
    LItem := TPCScopes.MemberItemOf(LLevel, LFound[0]);
    if LItem is TPCMethodItem then
      Result := TPCMethodItem(LItem);
  finally
    LFound.Free();
  end;
end;

function TPCSemantics.DoParentProperty(const ARecord: TPCRecordType; const AName: string): TPCPropertyItem;
var
  LParent: TPCTypeExpr;
  LFound: TList<TPCNode>;
begin
  // PLAN-OBJECT O10: the property named AName of the nearest PaskalCPP
  // object level above ARecord (DoParentMethod's walk); nil = none, or
  // another kind of member of that name
  Result := nil;
  if (ARecord.ParentName = nil) or DoIsErrorType(ARecord.ParentName) or DoIsOpaqueTier(ARecord.ParentName) then
    Exit;
  LParent := ARecord.ParentName.Canon();
  if not ((LParent is TPCRecordType) and TPCRecordType(LParent).IsObject) then
    Exit;
  LFound := TList<TPCNode>.Create();
  try
    TPCScopes.FindMember(LParent, AName, LFound);
    if (LFound.Count > 0) and (LFound[0] is TPCPropertyItem) then
      Result := TPCPropertyItem(LFound[0]);
  finally
    LFound.Free();
  end;
end;

function TPCSemantics.DoRunningWrite(const ASearched: TPCTypeExpr; const AProperty: TPCPropertyItem): TPCAccessorItem;
var
  LProperty: TPCPropertyItem;
  LLevel: TPCTypeExpr;
  LDepth: Integer;
begin
  // PLAN-OBJECT O10: the write that runs for AProperty (found on ASearched's
  // chain): its own, else, for an override restating its read only, the
  // overridden property's, up the levels by name (a body is walked before
  // ResolvedOverrides is written); nil = read-only. Bounded: a chain never
  // loops, the bound guards a recovered tree
  Result := nil;
  LProperty := AProperty;
  LDepth := 0;
  while (LProperty <> nil) and (LDepth < 256) do
  begin
    if LProperty.WriteItem <> nil then
      Exit(LProperty.WriteItem);
    if not LProperty.IsOverride then
      Exit;
    LLevel := TPCScopes.DeclaringLevel(ASearched, LProperty);
    if not (LLevel is TPCRecordType) then
      Exit;
    LProperty := DoParentProperty(TPCRecordType(LLevel), LProperty.PropName);
    Inc(LDepth);
  end;
end;

function TPCSemantics.DoAbstractAccessor(const ARecord: TPCRecordType; const AProperty: TPCPropertyItem): TPCAccessorItem;
var
  LWrite: TPCAccessorItem;
begin
  // The abstract accessor that runs for AProperty (the nearest property of
  // its name on ARecord's chain): its read, else the write that runs; nil =
  // none
  Result := nil;
  if (AProperty.ReadItem <> nil) and AProperty.ReadItem.IsAbstract then
    Exit(AProperty.ReadItem);
  LWrite := DoRunningWrite(ARecord, AProperty);
  if (LWrite <> nil) and LWrite.IsAbstract then
    Result := LWrite;
end;

function TPCSemantics.DoPropertyOwnerName(const AFrom: TPCTypeExpr; const AProperty: TPCPropertyItem): string;
var
  LLevel: TPCTypeExpr;
begin
  // The level of AFrom's chain that declares AProperty, as DoMethodOwnerName
  // spells a method's
  LLevel := TPCScopes.DeclaringLevel(AFrom, AProperty);
  if LLevel = nil then
    Exit(DoDefiningName(AFrom));
  Result := DoLevelText(AFrom, DoDefiningName(AFrom), LLevel);
end;

function TPCSemantics.DoSamePropertyShape(const AFirst: TPCPropertyItem; const ASecond: TPCPropertyItem): Boolean;
begin
  // O10: an override's type and index are its base's (C++'s override rule:
  // the accessors' signatures); an unfolded bound is compared by spelling
  Result := DoSameTypeAs(AFirst.TypeExpr, ASecond.TypeExpr, True);
  if not Result then
    Exit;
  if (AFirst.IndexParam = nil) <> (ASecond.IndexParam = nil) then
    Exit(False);
  if AFirst.IndexParam = nil then
    Exit;
  Result := (AFirst.IndexParam.ParamMode = ASecond.IndexParam.ParamMode) and
    DoSameTypeAs(AFirst.IndexParam.TypeExpr, ASecond.IndexParam.TypeExpr, True);
end;

procedure TPCSemantics.DoCheckDispatchProperty(const ARecord: TPCRecordType; const AProperty: TPCPropertyItem);
var
  LBase: TPCPropertyItem;
  LName: string;
  LOwner: string;
  LAt: TSourceRange;
  LInside: Boolean;
  LIndex: Integer;
  LAccessor: TPCAccessorItem;
begin
  // PLAN-OBJECT O10 (D12 + D7): a property's words follow a method's: final
  // and an abstract accessor need dispatch (SM0336 / SM0337); a parent's
  // virtual property name is continued only by override (SM0332); override
  // needs a virtual property above (SM0333), not final (SM0335), of the same
  // type and index (SM0334), and a write only where the base has one (SM0334:
  // an override may restate its read only, the base's write runs). Writes
  // ResolvedOverrides. A recovered property reports nothing
  LName := AProperty.PropName;
  LInside := DoEnterRecovered(AProperty);
  try
    if AProperty.IsFinal and not AProperty.IsDispatched() then
      DoReportRange(AProperty.FinalRange, esError, PC_ERR_SEM_336, RSSemDeclPropFinalNotVirtual, []);
    for LIndex := 0 to 1 do
    begin
      if LIndex = 0 then
        LAccessor := AProperty.ReadItem
      else
        LAccessor := AProperty.WriteItem;
      if (LAccessor <> nil) and LAccessor.IsAbstract and not AProperty.IsDispatched() then
        DoReportRange(LAccessor.AbstractRange, esError, PC_ERR_SEM_337, RSSemDeclPropAbstractNotVirtual, [LName]);
    end;
    LBase := DoParentProperty(ARecord, LName);
    if not AProperty.IsOverride then
    begin
      if (LBase = nil) or not LBase.IsDispatched() then
        Exit;
      if AProperty.IsVirtual then
        LAt := AProperty.VirtualRange
      else
        LAt := AProperty.NameRange;
      LOwner := DoPropertyOwnerName(ARecord, LBase);
      if DoReportRange(LAt, esError, PC_ERR_SEM_332, RSSemDeclPropNeedsOverride, [LName, LOwner, LName]) then
        DoNote(LBase, RSSemDeclMemberHere, [LOwner, LName]);
      Exit;
    end;
    if (LBase = nil) or not LBase.IsDispatched() then
    begin
      if (LBase = nil) and TPCScopes.ReachesOpaque(ARecord) then
        Exit;
      if DoReportRange(AProperty.OverrideRange, esError, PC_ERR_SEM_333, RSSemDeclPropOverridesNothing,
        [LName, DoDefiningName(ARecord), LName]) and (LBase <> nil) then
        DoNote(LBase, RSSemDeclMemberHere, [DoPropertyOwnerName(ARecord, LBase), LName]);
      Exit;
    end;
    LOwner := DoPropertyOwnerName(ARecord, LBase);
    if LBase.IsFinal then
    begin
      if DoReportRange(AProperty.OverrideRange, esError, PC_ERR_SEM_335, RSSemDeclOverrideFinal, [LOwner, LName]) then
        DoNote(LBase, RSSemDeclMemberHere, [LOwner, LName]);
      Exit;
    end;
    // A type with a reported part was reported once already
    if DoIsErrorType(AProperty.TypeExpr) or DoIsErrorType(LBase.TypeExpr) then
      Exit;
    if not DoSamePropertyShape(AProperty, LBase) then
    begin
      if DoReportRange(AProperty.NameRange, esError, PC_ERR_SEM_334, RSSemDeclPropOverrideType, [LName, LOwner, LName]) then
        DoNote(LBase, RSSemDeclMemberHere, [LOwner, LName]);
      Exit;
    end;
    if (AProperty.WriteItem <> nil) and (DoRunningWrite(ARecord, LBase) = nil) then
    begin
      if DoReportRange(AProperty.WriteItem.WordRange, esError, PC_ERR_SEM_334, RSSemDeclPropOverrideWrite,
        [LName, LOwner, LName]) then
        DoNote(LBase, RSSemDeclMemberHere, [LOwner, LName]);
      Exit;
    end;
    AProperty.ResolvedOverrides := LBase;
  finally
    if LInside then
      DoLeaveRecovered();
  end;
end;

function TPCSemantics.DoMethodOwnerName(const AFrom: TPCTypeExpr; const AFromText: string;
  const AItem: TPCRoutineMember): string;
var
  LLevel: TPCTypeExpr;
begin
  // The level of AFrom's chain that declares AItem, spelled as the level
  // below it names it (DoLevelText); AFromText names AFrom itself
  LLevel := TPCScopes.DeclaringLevel(AFrom, AItem.Routine);
  if LLevel = nil then
    Exit(AFromText);
  Result := DoLevelText(AFrom, AFromText, LLevel);
end;

function TPCSemantics.DoSignatureReported(const ARoutine: TPCRoutine): Boolean;
var
  LParam: TPCParam;
begin
  // A parameter or result type that was reported (one report per mistake)
  for LParam in ARoutine.Params do
  begin
    if (LParam = nil) or DoIsErrorType(LParam.TypeExpr) then
      Exit(True);
  end;
  Result := (ARoutine.ReturnType <> nil) and DoIsErrorType(ARoutine.ReturnType);
end;

procedure TPCSemantics.DoCheckConcrete(const AType: TPCTypeExpr; const AAt: TPCNode);
var
  LCanon: TPCTypeExpr;
  LAbstract: TPCRoutineMember;
  LOwner: string;
begin
  // D7: an abstract object (TPCRecordType.ResolvedAbstract) is never held by
  // value: a variable, a field, a value parameter, a result, an array
  // element, the object create builds (SM0338 at AAt: the type, or create's
  // argument). var / const parameters and pointers reach it (D6)
  if (AType = nil) or DoIsErrorType(AType) then
    Exit;
  if AType is TPCArrayType then
  begin
    // A type position reports at the element type itself
    if AAt = AType then
      DoCheckConcrete(TPCArrayType(AType).ElementType, TPCArrayType(AType).ElementType)
    else
      DoCheckConcrete(TPCArrayType(AType).ElementType, AAt);
    Exit;
  end;
  LCanon := AType.Canon();
  if not ((LCanon is TPCRecordType) and TPCRecordType(LCanon).IsObject) then
    Exit;
  // PLAN-OBJECT O7: an interface (even one with no method) is never a value
  if TPCRecordType(LCanon).IsInterface then
  begin
    DoError(AAt, PC_ERR_SEM_338, RSSemDeclInterfaceValue, [AType.TypeText()]);
    Exit;
  end;
  LAbstract := TPCRecordType(LCanon).ResolvedAbstract;
  if (LAbstract = nil) or (LAbstract.Routine = nil) then
    Exit;
  LOwner := DoMethodOwnerName(LCanon, AType.TypeText(), LAbstract);
  if DoError(AAt, PC_ERR_SEM_338, RSSemDeclAbstractValue, [AType.TypeText(), LOwner, LAbstract.Routine.DeclName]) then
    DoNote(LAbstract.Routine, RSSemDeclMemberHere, [LOwner, LAbstract.Routine.DeclName]);
end;

procedure TPCSemantics.DoCheckParentNames(const AMembers: TList<TPCMemberItem>; const AParent: TPCTypeExpr);
var
  LItem: TPCMemberItem;
  LNode: TPCNode;
  LName: string;
  LFound: TList<TPCNode>;
begin
  // decls.md :106-107 (Q24): a member name is unique across the parent chain,
  // except a method reusing a parent METHOD name. Anonymous aggregates are
  // hoisted (S21): their members are the type's
  if AMembers = nil then
    Exit;
  LFound := TList<TPCNode>.Create();
  try
    for LItem in AMembers do
    begin
      if DoStopped() then
        Exit;
      LNode := nil;
      LName := '';
      if LItem is TPCField then
      begin
        LNode := LItem;
        LName := TPCField(LItem).FieldName;
      end
      else if (LItem is TPCMethodItem) and (TPCMethodItem(LItem).Routine <> nil) then
      begin
        LNode := TPCMethodItem(LItem).Routine;
        LName := TPCMethodItem(LItem).Routine.DeclName;
      end
      // PLAN-OBJECT O9 / O10: a property's name too; a property may reuse a
      // parent PROPERTY name (the dispatch rules judge it, as a method's)
      else if LItem is TPCPropertyItem then
      begin
        LNode := LItem;
        LName := TPCPropertyItem(LItem).PropName;
      end
      else if LItem is TPCAnonAggregate then
        DoCheckParentNames(TPCAnonAggregate(LItem).Members, AParent);
      if LNode = nil then
        Continue;
      LFound.Clear();
      TPCScopes.FindMember(AParent, LName, LFound);
      if LFound.Count = 0 then
        Continue;
      if (LNode is TPCRoutine) and (LFound[0] is TPCRoutine) then
        Continue;
      if (LNode is TPCPropertyItem) and (LFound[0] is TPCPropertyItem) then
        Continue;
      if DoError(LNode, PC_ERR_SEM_309, RSSemDeclParentName, [LName]) then
        DoNote(LFound[0], RSSemCoreFirstDecl, [LName]);
    end;
  finally
    LFound.Free();
  end;
end;

procedure TPCSemantics.DoCheckSetType(const ASet: TPCSetType);
var
  LType: TPCTypeExpr;
  LKind: TPCOrdinalKind;
  LLow: TPCExpr;
  LHigh: TPCExpr;
  LText: string;
begin
  // decls.md TPCSetType. Element form: char, bool or choices (an integer or
  // wchar names its range: SM0318 / SM0319; no ordinal at all: SM0329).
  // Range form: both bounds of one family (SM0320), low <= high (SM0328),
  // at most PC_SET_MAX_MEMBERS members (SM0321)
  if not ASet.IsRangeForm then
  begin
    LType := ASet.ElementType;
    if (LType = nil) or DoIsErrorType(LType) or DoIsOpaqueTier(LType) then
      Exit;
    LKind := DoOrdinalKindOf(LType);
    if LKind = okInteger then
      DoError(LType, PC_ERR_SEM_318, RSSemDeclSetIntegers, [])
    else if LKind = okWChar then
      DoError(LType, PC_ERR_SEM_319, RSSemDeclSetWChar, [])
    else if LKind = okNone then
      DoError(LType, PC_ERR_SEM_329, RSSemDeclSetElement, [LType.TypeText()])
    else
      DoResolveElementBounds(ASet, LType, LKind);
    Exit;
  end;
  LLow := ASet.LowExpr;
  LHigh := ASet.HighExpr;
  // A bound the parser dropped or SM0202 reported: nothing more (C1). An
  // opaque C++ bound is clang's (it judges the emitted set's range)
  if (LLow = nil) or (LHigh = nil) or DoIsPoisoned(LLow) or DoIsPoisoned(LHigh) or
    (LLow.ResolvedType = nil) or (LHigh.ResolvedType = nil) or
    DoIsOpaqueTier(LLow.ResolvedType) or DoIsOpaqueTier(LHigh.ResolvedType) then
    Exit;
  if not DoSameOrdinalFamily(LLow.ResolvedType, LHigh.ResolvedType) then
  begin
    DoError(ASet, PC_ERR_SEM_320, RSSemDeclSetFamily, []);
    Exit;
  end;
  if not (DoFoldedInteger(LLow) and DoFoldedInteger(LHigh)) then
    Exit;
  if DoBoundsReversed(LLow, LHigh) then
  begin
    DoError(LLow, PC_ERR_SEM_328, RSSemDeclBoundOrder, [LLow.BoundText(), LHigh.BoundText()]);
    Exit;
  end;
  if DoMemberCount(LLow, LHigh, LText) then
    DoError(ASet, PC_ERR_SEM_321, RSSemDeclSetCount, [PC_SET_MAX_MEMBERS, LText])
  else
    DoResolveRangeBounds(ASet, LLow, LHigh);
end;

procedure TPCSemantics.DoResolveElementBounds(const ASet: TPCSetType; const AType: TPCTypeExpr;
  const AKind: TPCOrdinalKind);
var
  LCanon: TPCTypeExpr;
  LValue: TPCChoiceValue;
  LLow: Int64;
  LHigh: Int64;
  LAny: Boolean;
begin
  // PLAN-EMITTER A2b: the member range of an element-form set, written into
  // the AST so the emitter never derives it. char = 0 .. 255 (W2: one member
  // per byte value, the same on every target)
  if AKind = okBool then
  begin
    LLow := 0;
    LHigh := 1;
  end
  else if AKind = okChar then
  begin
    LLow := 0;
    LHigh := 255;
  end
  else if AKind = okChoices then
  begin
    LCanon := AType.Canon();
    if not (LCanon is TPCChoicesType) then
      Exit;
    // min / max ordinal; a value without one (reported) leaves no bounds
    LAny := False;
    LLow := 0;
    LHigh := 0;
    for LValue in TPCChoicesType(LCanon).Values do
    begin
      if (LValue = nil) or (not LValue.HasResolvedOrdinal) then
        Exit;
      if (not LAny) or (LValue.ResolvedOrdinal < LLow) then
        LLow := LValue.ResolvedOrdinal;
      if (not LAny) or (LValue.ResolvedOrdinal > LHigh) then
        LHigh := LValue.ResolvedOrdinal;
      LAny := True;
    end;
    if not LAny then
      Exit;
  end
  else
    Exit;
  ASet.HasResolvedBounds := True;
  ASet.ResolvedLow := LLow;
  ASet.ResolvedHigh := LHigh;
end;

procedure TPCSemantics.DoResolveRangeBounds(const ASet: TPCSetType; const ALow: TPCExpr; const AHigh: TPCExpr);
var
  LLowHigh: Int64;
  LLowLow: UInt64;
  LHighHigh: Int64;
  LHighLow: UInt64;
begin
  // PLAN-EMITTER A2b: both bounds folded and checked (order, count); kept
  // only when each fits Int64 (its wide form's high word is 0 or -1 with the
  // matching sign bit), else the emitter spells the bound expressions
  DoConstWide(ALow, LLowHigh, LLowLow);
  DoConstWide(AHigh, LHighHigh, LHighLow);
  if (not DoWideFitsInt64(LLowHigh, LLowLow)) or (not DoWideFitsInt64(LHighHigh, LHighLow)) then
    Exit;
  ASet.HasResolvedBounds := True;
  ASet.ResolvedLow := Int64(LLowLow);
  ASet.ResolvedHigh := Int64(LHighLow);
end;

class function TPCSemantics.DoWideFitsInt64(const AHigh: Int64; const ALow: UInt64): Boolean;
begin
  // A DoConstWide pair is an Int64 when its high word is the sign extension
  // of the low word's top bit: 0 with the top bit clear, -1 with it set
  if AHigh = 0 then
    Result := ALow <= UInt64(High(Int64))
  else if AHigh = -1 then
    Result := ALow > UInt64(High(Int64))
  else
    Result := False;
end;

procedure TPCSemantics.DoCheckArrayBounds(const AArray: TPCArrayType);
var
  LLow: TPCExpr;
  LHigh: TPCExpr;
begin
  // decls.md TPCArrayType: static bounds integer, char or choices of one
  // family (SM0322), low <= high when both fold (SM0328). An opaque bound is
  // clang's (CHECKS position)
  if AArray.IsDynamic then
    Exit;
  LLow := AArray.LowExpr;
  LHigh := AArray.HighExpr;
  if (LLow = nil) or (LHigh = nil) or DoIsPoisoned(LLow) or DoIsPoisoned(LHigh) or
    (LLow.ResolvedType = nil) or (LHigh.ResolvedType = nil) or
    DoIsOpaqueTier(LLow.ResolvedType) or DoIsOpaqueTier(LHigh.ResolvedType) then
    Exit;
  if not DoSameOrdinalFamily(LLow.ResolvedType, LHigh.ResolvedType) then
  begin
    DoError(AArray, PC_ERR_SEM_322, RSSemDeclArrayBounds, []);
    Exit;
  end;
  if not (DoFoldedInteger(LLow) and DoFoldedInteger(LHigh)) then
    Exit;
  if DoBoundsReversed(LLow, LHigh) then
    DoError(LLow, PC_ERR_SEM_328, RSSemDeclBoundOrder, [LLow.BoundText(), LHigh.BoundText()])
  else if DoCountTooLarge(LLow, LHigh) then
    // F47: more elements than any type holds bytes. A count that fits is
    // judged by the runtime's Array with the element's size in view
    DoError(AArray, PC_ERR_SEM_277, RSSemTypeTooLarge, [AArray.TypeText(), UIntToStr(PC_MAX_OBJECT_SIZE)]);
end;

procedure TPCSemantics.DoChoiceOrdinal(const AValue: TPCChoiceValue; var ANext: Int64; var AKnown: Boolean;
  var APastMax: Boolean);
var
  LExpr: TPCExpr;
  LOrdinal: Int64;
begin
  // ResolvedOrdinal (decls.md TPCChoicesType): a value given as a PaskalCPP
  // constant, else the previous + 1 from 0. Every value is numbered or
  // reported: the emitter writes each ordinal folded, and the underlying
  // type, a bitfield's width and the print form read them (F41 / F42: an
  // unnumbered value was the emitter's internal error EM0003). A value that
  // follows a reported one is not numbered (AKnown False; nothing is emitted)
  LExpr := AValue.ValueExpr;
  if LExpr <> nil then
  begin
    AKnown := False;
    APastMax := False;
    if DoIsPoisoned(LExpr) then
      Exit;
    // A choice value is an integer (PaskalCPP's conversion rule)
    DoCheckConvert(LExpr, FAst.BuiltinType(tkKwInt64));
    if DoIsPoisoned(LExpr) then
      Exit;
    // F42: a value only clang can compute (C++, cpp("...")) has no number
    // PaskalCPP can write: a choice value is a PaskalCPP constant (SM0202)
    if not LExpr.HasConstValue then
    begin
      DoError(LExpr, PC_ERR_SEM_202, RSSemTypeNotConstant, [RSSemTypePosChoice]);
      DoPoison(LExpr);
      Exit;
    end;
    if LExpr.ConstIsUnsigned then
      LOrdinal := Int64(LExpr.ConstUInt)
    else
      LOrdinal := LExpr.ConstInt;
  end
  else
  begin
    // F41: the value after the largest int64 has no number (SM0256 at its
    // name); the values after it follow a reported one
    if APastMax then
    begin
      DoError(AValue, PC_ERR_SEM_256, RSSemTypeConstOverflow, [FAst.BuiltinType(tkKwInt64).TypeText()]);
      APastMax := False;
      AKnown := False;
      Exit;
    end;
    if not AKnown then
      Exit;
    LOrdinal := ANext;
  end;
  AValue.ResolvedOrdinal := LOrdinal;
  AValue.HasResolvedOrdinal := True;
  APastMax := LOrdinal = High(Int64);
  AKnown := not APastMax;
  if AKnown then
    ANext := LOrdinal + 1;
end;

procedure TPCSemantics.DoAnalyzeModule(const AModule: TPCModule);
var
  LIndex: Integer;
begin
  // The order never changes: prologue, Decls, initialize, finalize, body, tests
  if AModule = nil then
    Exit;
  FModule := AModule;
  DoPushFrame(TPCScopes.SystemFrame());
  DoPushFrame(TPCScopes.ModuleFrame(AModule));
  try
    DoModuleDirectives(AModule);
    if not DoStopped() then
      DoCheckReservedNames(AModule);
    if not DoStopped() then
      DoItemList(AModule.Decls, True);
    if (not DoStopped()) and (AModule.InitRoutine <> nil) then
      DoRoutine(AModule.InitRoutine);
    if (not DoStopped()) and (AModule.FinalRoutine <> nil) then
      DoRoutine(AModule.FinalRoutine);
    if (not DoStopped()) and AModule.HasBody and (AModule.Body <> nil) then
      DoBlock(AModule.Body);
    for LIndex := 0 to AModule.Tests.Count - 1 do
    begin
      if DoStopped() then
        Break;
      DoCheckTestName(AModule, LIndex);
      DoTest(AModule.Tests[LIndex]);
    end;
  finally
    DoPopFrame();
    DoPopFrame();
  end;

  // After the walk: the rule reads the Resolved* facts it just wrote
  // (linkage, call targets, argument types; r10 D-R10-1)
  AModule.ResolvedUsesRuntime := TPCAst.ModuleNamesRuntime(AModule);
end;

procedure TPCSemantics.DoMarkNoEffect(const ADirective: TPCDirective;
  const ASeverity: TErrorSeverity; const ACode: string; const AMessage: string;
  const AArgs: array of const);
begin
  // Every report that says a directive is not applied sets the flag the
  // Compiler reads (D-A2-5): it never re-derives applicability
  ADirective.ResolvedNoEffect := True;
  DoReportAt(ADirective, ASeverity, ACode, AMessage, AArgs);
end;

function TPCSemantics.DoNotApplied(const AModule: TPCModule; const ADirective: TPCDirective;
  out AWhere: string): Boolean;
var
  LWindows: Boolean;
  LValue: string;
begin
  // The one applicability rule (module.md :164-172). An empty triple: the
  // filter reported the @target, nothing target-dependent is said
  AWhere := '';
  LWindows := AModule.ResolvedTarget.IsEmpty() or AModule.ResolvedTarget.IsWindows();
  LValue := '';
  if ADirective.Args.Count > 0 then
    LValue := ADirective.Args[0].ResolvedText;
  if ((ADirective.DirectiveKind = bdSubsystem) and (LValue = PC_SEM_VALUE_GUI)) or
    (ADirective.DirectiveKind = bdExeIcon) then
  begin
    if AModule.ModuleKind <> mkExe then
      AWhere := RSSemModWhereNotExe
    else if not LWindows then
      AWhere := RSSemModWhereNotWindows;
  end
  else if (ADirective.DirectiveKind = bdAddVerInfo) and (LValue = PC_SEM_VALUE_ON) then
  begin
    if AModule.ModuleKind = mkLib then
      AWhere := RSSemModWhereLib
    else if not LWindows then
      AWhere := RSSemModWhereNotWindows;
  end;
  Result := AWhere <> '';
end;

function TPCSemantics.DoVerInfoOf(const AModule: TPCModule): TPCVerInfoState;
var
  LDirective: TPCDirective;
  LWhere: string;
begin
  // The FIRST @addverinfo decides for every @vi*, whatever the order; a later
  // one is SM0102 (D-A2-4)
  for LDirective in AModule.Directives do
  begin
    if (LDirective = nil) or (LDirective.DirectiveKind <> bdAddVerInfo) then
      Continue;
    if (LDirective.Args.Count = 0) or (LDirective.Args[0].ResolvedText <> PC_SEM_VALUE_ON) then
      Exit(vsOff);
    if DoNotApplied(AModule, LDirective, LWhere) then
      Exit(vsSilent);
    Exit(vsOn);
  end;
  Result := vsOff;
end;

function TPCSemantics.DoCheckChoice(const ADirective: TPCDirective): Boolean;
var
  LArg: TPCDirectiveArg;
  LCurrent: string;
begin
  // An identifier directive: the parser builds exactly one argument (nil-safe rule)
  if ADirective.Args.Count <> 1 then
    Exit(False);
  LArg := ADirective.Args[0];
  if TPCVocabulary.IsDirectiveValue(ADirective.DirectiveKind, LArg.ResolvedText) then
    Exit(True);
  // A retired spelling (PC_RETIRED_VALUES) names the one that replaced it
  if TPCVocabulary.FindRetiredValue(ADirective.DirectiveKind, LArg.ResolvedText, LCurrent) then
  begin
    DoError(LArg, PC_ERR_SEM_100, RSSemModValueRetired, [LArg.ResolvedText,
      ADirective.DirectiveName, LCurrent]);
    Exit(False);
  end;
  DoError(LArg, PC_ERR_SEM_100, RSSemModValue, [LArg.ResolvedText, ADirective.DirectiveName,
    TPCVocabulary.DirectiveValuesText(ADirective.DirectiveKind)]);
  Result := False;
end;

procedure TPCSemantics.DoCheckVersionInfo(const ADirective: TPCDirective;
  const AState: TPCVerInfoState);
begin
  // vsSilent: the @addverinfo report already says it (C1), no second report
  if AState = vsOff then
    DoMarkNoEffect(ADirective, esWarning, PC_ERR_SEM_104, RSSemModNoVerInfo,
      [ADirective.DirectiveName])
  else if AState = vsSilent then
    ADirective.ResolvedNoEffect := True;
end;

procedure TPCSemantics.DoCheckPath(const AArg: TPCDirectiveArg; const ADirectory: Boolean);
var
  LPlain: string;
  LExists: Boolean;
begin
  // The check takes ResolvedText as stored; a message names the plain
  // spelling a person reads (D-A2-9). A check that raises is SM0107
  LPlain := AArg.ResolvedText;
  try
    LPlain := TUtils.StripLongPathPrefix(AArg.ResolvedText);
    // Recorded before the read: a path whose check raises can still appear
    DoAddDiskPath(LPlain);
    LExists := DoPathExists(AArg.ResolvedText, ADirectory);
  except
    on E: Exception do
    begin
      DoError(AArg, PC_ERR_SEM_107, RSSemModPathCheck, [LPlain, E.Message]);
      Exit;
    end;
  end;
  if LExists then
    Exit;
  if ADirectory then
    DoError(AArg, PC_ERR_SEM_106, RSSemModNoDir, [LPlain])
  else
    DoError(AArg, PC_ERR_SEM_105, RSSemModNoFile, [LPlain]);
end;

procedure TPCSemantics.DoAddDiskPath(const APath: string);
var
  LPath: string;
begin
  // Each path once, the same path spelled in another case counting as one
  if APath = '' then
    Exit;
  for LPath in FDiskPaths do
  begin
    if SameText(LPath, APath) then
      Exit;
  end;
  FDiskPaths := FDiskPaths + [APath];
end;

function TPCSemantics.DiskPaths(): TArray<string>;
begin
  Result := FDiskPaths;
end;

procedure TPCSemantics.DoCheckSourceFile(const AArg: TPCDirectiveArg);
var
  LLanguage: TPCSourceLanguage;
begin
  // @addsourcefile: a name the toolchain compiles (TPCSourceFiles, exact case:
  // a .h is no TU, a .C is C++), then an existing file; one report each
  if not TPCSourceFiles.LanguageOf(AArg.ResolvedText, LLanguage) then
  begin
    DoError(AArg, PC_ERR_SEM_114, RSSemModNotSource,
      [TUtils.StripLongPathPrefix(AArg.ResolvedText), TPCSourceFiles.ExtensionsText()]);
    Exit;
  end;
  DoCheckPath(AArg, False);
end;

class function TPCSemantics.DoIsMacroName(const AText: string): Boolean;
var
  LIndex: Integer;
begin
  // A C / C++ macro name: a letter or _, then letters, digits and _ (the
  // name clang's -D / -U takes; anything else would make a broken flag)
  if AText = '' then
    Exit(False);
  if not CharInSet(AText.Chars[0], ['A'..'Z', 'a'..'z', '_']) then
    Exit(False);
  for LIndex := 1 to AText.Length - 1 do
  begin
    if not CharInSet(AText.Chars[LIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Exit(False);
  end;
  Result := True;
end;

class function TPCSemantics.DoMacroText(const ADirective: TPCDirective): string;
begin
  // The directive as a message names it: @cppundef "N", @cppdefine "N" [ "V" ]
  Result := '@' + ADirective.DirectiveName + ' "' + ADirective.Args[0].ResolvedText + '"';
  if ADirective.Args.Count > 1 then
    Result := Result + ' "' + ADirective.Args[1].ResolvedText + '"';
end;

class function TPCSemantics.DoSameMacro(const AFirst: TPCDirective; const ASecond: TPCDirective): Boolean;
begin
  // The same directive with the same value (a name alone is not the same
  // as the name with a value: -DN is N=1)
  if AFirst.DirectiveKind <> ASecond.DirectiveKind then
    Exit(False);
  if AFirst.Args.Count <> ASecond.Args.Count then
    Exit(False);
  Result := (AFirst.Args.Count < 2) or (AFirst.Args[1].ResolvedText = ASecond.Args[1].ResolvedText);
end;

procedure TPCSemantics.DoCheckCppMacro(const ADirective: TPCDirective);
var
  LName: string;
  LPrevious: TPCDirective;
begin
  // @cppdefine / @cppundef (BNF sec 2): a C macro name, not PCPP_ (the
  // compiler's and the runtime's), a one-line value, and one meaning per name
  // across the program (clang's answer to two would depend on the flag order).
  // An argument the parser reported (no value) is not judged again
  if (ADirective.Args.Count = 0) or (not ADirective.Args[0].HasValue) then
    Exit;
  if (ADirective.Args.Count > 1) and (not ADirective.Args[1].HasValue) then
    Exit;
  LName := ADirective.Args[0].ResolvedText;
  if not DoIsMacroName(LName) then
  begin
    DoError(ADirective.Args[0], PC_ERR_SEM_115, RSSemModMacroName, [LName]);
    Exit;
  end;
  if LName.StartsWith(PC_SEM_RESERVED_MACRO_PREFIX) then
  begin
    DoError(ADirective.Args[0], PC_ERR_SEM_116, RSSemModMacroReserved, [LName, PC_SEM_RESERVED_MACRO_PREFIX]);
    Exit;
  end;
  if (ADirective.Args.Count > 1) and
    (ADirective.Args[1].ResolvedText.Contains(#10) or ADirective.Args[1].ResolvedText.Contains(#13)) then
  begin
    DoError(ADirective.Args[1], PC_ERR_SEM_117, RSSemModMacroLines, [LName]);
    Exit;
  end;
  if FCppMacros.TryGetValue(LName, LPrevious) then
  begin
    if not DoSameMacro(LPrevious, ADirective) then
      DoError(ADirective.Args[0], PC_ERR_SEM_118, RSSemModMacroConflict,
        [DoMacroText(ADirective), DoMacroText(LPrevious),
        TUtils.StripLongPathPrefix(LPrevious.Range.Filename), LPrevious.Range.StartLine]);
    Exit;
  end;
  FCppMacros.Add(LName, ADirective);
end;

procedure TPCSemantics.DoReportMessage(const ADirective: TPCDirective);
var
  LSeverity: TErrorSeverity;
begin
  // At the user's severity; a fatal reports and the walk goes on (D-A2-7, C1).
  // A text without a value was reported by the parser
  if (ADirective.Args.Count <> 2) or (not ADirective.Args[1].HasValue) then
    Exit;
  for LSeverity := Low(TErrorSeverity) to High(TErrorSeverity) do
  begin
    if PC_MESSAGE_SEVERITIES[LSeverity] = ADirective.Args[0].ResolvedText then
    begin
      DoReportAt(ADirective, LSeverity, PC_ERR_SEM_108, RSSemModMessage,
        [ADirective.Args[1].ResolvedText]);
      Exit;
    end;
  end;
end;

procedure TPCSemantics.DoCheckDirective(const AModule: TPCModule;
  const ADirective: TPCDirective; const AVerInfo: TPCVerInfoState);
begin
  // D-A2-3 after the duplicate check: the first rule that reports or skips
  // ends it (fixed rules, value, applicability, then the use)
  if DoCheckFixedRule(AModule, ADirective) then
    Exit;
  if not DoCheckValue(ADirective) then
    Exit;
  if DoReportNotApplied(AModule, ADirective) then
    Exit;
  DoCheckUse(ADirective, AVerInfo);
end;

function TPCSemantics.DoCheckFixedRule(const AModule: TPCModule;
  const ADirective: TPCDirective): Boolean;
begin
  // True = handled. A dll / lib runs no tests, whatever the value (Q26); the
  // two statement directives have one rule each in the prologue
  Result := True;
  if (ADirective.DirectiveKind = bdUnitTestMode) and (AModule.ModuleKind in [mkDll, mkLib]) then
    DoMarkNoEffect(ADirective, esError, PC_ERR_SEM_110, RSSemModTestMode, [])
  else if ADirective.DirectiveKind = bdBreakpoint then
    DoMarkNoEffect(ADirective, esWarning, PC_ERR_SEM_109, RSSemModBreakpoint, [])
  else if ADirective.DirectiveKind = bdMessage then
    DoReportMessage(ADirective)
  else
    Result := False;
end;

function TPCSemantics.DoCheckValue(const ADirective: TPCDirective): Boolean;
var
  LArg: TPCDirectiveArg;
begin
  // True = the value is valid, go on. The choice directives take one of
  // their PC_DIRECTIVE_VALUES; every other kind takes one argument, and one
  // without a value was reported by the parser or the lexer (F-A2-1, F-A2-2)
  if ADirective.DirectiveKind in [bdOptimize, bdSubsystem, bdAddVerInfo, bdUnitTestMode] then
    Exit(DoCheckChoice(ADirective));
  if ADirective.Args.Count = 0 then
    Exit(False);
  LArg := ADirective.Args[0];
  if not LArg.HasValue then
    Exit(False);
  if (ADirective.DirectiveKind in [bdVIMajor, bdVIMinor, bdVIPatch]) and
    (LArg.IntValue > 65535) then
  begin
    DoError(LArg, PC_ERR_SEM_101, RSSemModVersion, [ADirective.DirectiveName, LArg.Text]);
    Exit(False);
  end;
  Result := True;
end;

function TPCSemantics.DoReportNotApplied(const AModule: TPCModule;
  const ADirective: TPCDirective): Boolean;
var
  LWhere: string;
begin
  // True = reported as not applied (SM0103): a setting not used is not
  // checked for existence (D-A2-3)
  Result := DoNotApplied(AModule, ADirective, LWhere);
  if Result then
    DoMarkNoEffect(ADirective, esWarning, PC_ERR_SEM_103, RSSemModNotApplied,
      [ADirective.DirectiveName, LWhere]);
end;

procedure TPCSemantics.DoCheckUse(const ADirective: TPCDirective;
  const AVerInfo: TPCVerInfoState);
begin
  // The eight @vi* named one by one (never an enum range); the paths are
  // checked for existence (Q28); @linklibrary's whole rule is PR0055
  if ADirective.DirectiveKind in [bdVIMajor, bdVIMinor, bdVIPatch, bdVIProductName,
    bdVIDescription, bdVIFileName, bdVICompanyName, bdVICopyright] then
    DoCheckVersionInfo(ADirective, AVerInfo)
  else if ADirective.DirectiveKind in [bdExeIcon, bdCopyDLL] then
    DoCheckPath(ADirective.Args[0], False)
  else if ADirective.DirectiveKind in [bdAddLibraryPath, bdAddModulePath, bdAddIncludePath] then
    DoCheckPath(ADirective.Args[0], True)
  else if ADirective.DirectiveKind = bdAddSourceFile then
    DoCheckSourceFile(ADirective.Args[0])
  else if (ADirective.DirectiveKind = bdCppDefine) or (ADirective.DirectiveKind = bdCppUndef) then
    DoCheckCppMacro(ADirective);
end;

procedure TPCSemantics.DoModuleDirectives(const AModule: TPCModule);
var
  LVerInfo: TPCVerInfoState;
  LFirst: array[TPCBuildDirective] of TPCDirective;
  LKind: TPCBuildDirective;
  LDirective: TPCDirective;
  LRow: TPCDirectiveRow;
begin
  // The prologue in source order, one report per directive (D-A2-3). A
  // main-only directive in a unit is PR0023's alone, @target the filter's
  // (D-A2-2); a single directive given again is SM0102 at the later one
  LVerInfo := DoVerInfoOf(AModule);
  for LKind := Low(TPCBuildDirective) to High(TPCBuildDirective) do
    LFirst[LKind] := nil;
  for LDirective in AModule.Directives do
  begin
    if DoStopped() then
      Break;
    if LDirective = nil then
      Continue;
    LKind := LDirective.DirectiveKind;
    LRow := PC_BUILD_DIRECTIVES[LKind];
    if (LRow.IsMainOnly and (AModule.ModuleKind = mkUnit)) or (LKind = bdTarget) then
      Continue;
    if LRow.IsSingle and (LFirst[LKind] <> nil) then
    begin
      DoMarkNoEffect(LDirective, esError, PC_ERR_SEM_102, RSSemModDuplicate,
        [LDirective.DirectiveName, UIntToStr(LFirst[LKind].Range.StartLine)]);
      Continue;
    end;
    if LRow.IsSingle then
      LFirst[LKind] := LDirective;
    DoCheckDirective(AModule, LDirective, LVerInfo);
  end;
end;

procedure TPCSemantics.DoCheckTestName(const AModule: TPCModule; const AIndex: Integer);
var
  LTest: TPCTest;
  LOther: TPCTest;
  LName: string;
  LOtherName: string;
  LEarlier: Integer;
begin
  // A name without a value was reported by the parser: no name rule. Tests of
  // different modules may share a name (module.md :196)
  LTest := AModule.Tests[AIndex];
  // A test the parser could not finish is not judged (PLAN-RECOVERY)
  if (LTest = nil) or LTest.IsRecovered then
    Exit;
  if (LTest.TestName <> nil) and LTest.TestName.DecodedValue(LName) then
  begin
    if LName = '' then
      DoError(LTest.TestName, PC_ERR_SEM_111, RSSemModTestEmpty, [])
    else
    begin
      for LEarlier := 0 to AIndex - 1 do
      begin
        LOther := AModule.Tests[LEarlier];
        if (LOther <> nil) and (not LOther.IsRecovered) and (LOther.TestName <> nil) and
          LOther.TestName.DecodedValue(LOtherName) and (LOtherName = LName) then
        begin
          DoError(LTest.TestName, PC_ERR_SEM_112, RSSemModTestDup,
            [LName, UIntToStr(LOther.TestName.Range.StartLine)]);
          Break;
        end;
      end;
    end;
  end;
  // A unit's tests run through an importing exe: no report there (module.md :198-201)
  if AModule.ModuleKind in [mkDll, mkLib] then
    DoWarning(LTest, PC_ERR_SEM_113, RSSemModTestNoRun, []);
end;

procedure TPCSemantics.DoBodyDirective(const ADirective: TPCDirective);
begin
  // A body @message reports here, once (each body is analyzed once); a body
  // @breakpoint marks its line for EMIT (statements.md :146)
  if (ADirective <> nil) and (ADirective.DirectiveKind = bdMessage) then
    DoReportMessage(ADirective);
end;

function TPCSemantics.DoPathExists(const APath: string; const ADirectory: Boolean): Boolean;
begin
  if ADirectory then
    Result := TDirectory.Exists(APath)
  else
    Result := TFile.Exists(APath);
end;

procedure TPCSemantics.DoItemList(const AList: TList<TPCStmt>; const AFirst: Boolean);
var
  LIndex: Integer;
  LTop: Integer;
  LItem: TPCStmt;
  LCount: Integer;
begin
  // Each item sees the items before it; a routine also sees itself (its own
  // params, return type and body: recursion)
  if AList = nil then
    Exit;
  LTop := DoTopIndex();
  for LIndex := 0 to AList.Count - 1 do
  begin
    if DoStopped() then
      Break;
    LItem := AList[LIndex];
    LCount := TPCScopes.VisibleCount(AList, LIndex);
    if AFirst then
      FFrames.List[LTop].FirstCount := LCount
    else
      FFrames.List[LTop].SecondCount := LCount;
    FFrames.List[LTop].Current := LItem;
    if LItem is TPCDecl then
      DoCheckDuplicate(TPCDecl(LItem));
    DoStmt(LItem);
    FFrames.List[LTop].Current := nil;
  end;
  if AFirst then
    FFrames.List[LTop].FirstCount := AList.Count
  else
    FFrames.List[LTop].SecondCount := AList.Count;
  DoUnpairedForwards(AList);
  DoCheckPendingOwners();
  DoRoutineSets(AList);
end;

procedure TPCSemantics.DoNestedList(const AOwner: TPCStmt; const AList: TList<TPCStmt>);
begin
  if AList = nil then
    Exit;
  DoPushFrame(TPCScopes.ListFrame(AOwner, AList));
  try
    DoItemList(AList, True);
  finally
    DoPopFrame();
  end;
end;

procedure TPCSemantics.DoStmt(const AStmt: TPCStmt);
var
  LInside: Boolean;
begin
  // Dispatch by class; a nil child is skipped (the parser reported it). A
  // node the parser recovered is walked silently (PLAN-RECOVERY)
  if AStmt = nil then
    Exit;
  LInside := DoEnterRecovered(AStmt);
  try
    if AStmt is TPCTypeDecl then
      DoTypeDecl(TPCTypeDecl(AStmt))
    else if AStmt is TPCVarDecl then
      DoVarDeclStmt(TPCVarDecl(AStmt))
    else if AStmt is TPCConstDecl then
    begin
      // A const value is a constant (folding.md CHECKS), then it converts
      // implicitly to the declared type; a reported value is not checked twice
      DoTypeExpr(TPCConstDecl(AStmt).TypeExpr);
      DoCheckComplete(TPCConstDecl(AStmt).TypeExpr, False);
      DoExpr(TPCConstDecl(AStmt).ValueExpr);
      DoCheckConstant(TPCConstDecl(AStmt).ValueExpr, RSSemTypePosConst);
      DoCheckConvert(TPCConstDecl(AStmt).ValueExpr, TPCConstDecl(AStmt).TypeExpr);
    end
    else if AStmt is TPCRoutine then
      DoRoutine(TPCRoutine(AStmt))
    else if AStmt is TPCBlock then
      DoNestedList(AStmt, TPCBlock(AStmt).Stmts)
    else if AStmt is TPCIf then
    begin
      DoExpr(TPCIf(AStmt).Condition);
      DoCheckCondition(TPCIf(AStmt).Condition);
      DoNestedList(AStmt, TPCIf(AStmt).ThenStmts);
      if TPCIf(AStmt).HasElse then
        DoNestedList(AStmt, TPCIf(AStmt).ElseStmts);
    end
    else if AStmt is TPCWhile then
    begin
      DoExpr(TPCWhile(AStmt).Condition);
      DoCheckCondition(TPCWhile(AStmt).Condition);
      DoFlowList(fwLoop, AStmt, TPCWhile(AStmt).Stmts);
    end
    else if AStmt is TPCFor then
      DoForStmt(TPCFor(AStmt))
    else if AStmt is TPCRepeat then
    begin
      // The until condition is in the enclosing frame (scopes.md)
      DoFlowList(fwLoop, AStmt, TPCRepeat(AStmt).Stmts);
      DoExpr(TPCRepeat(AStmt).Condition);
      DoCheckCondition(TPCRepeat(AStmt).Condition);
    end
    else if AStmt is TPCMatch then
      DoMatchStmt(TPCMatch(AStmt))
    else if AStmt is TPCGuard then
      DoGuardStmt(TPCGuard(AStmt))
    else if AStmt is TPCReturn then
      DoReturnStmt(TPCReturn(AStmt))
    else if AStmt is TPCLeave then
      DoLeaveStmt(TPCLeave(AStmt))
    else if AStmt is TPCSkip then
      DoSkipStmt(TPCSkip(AStmt))
    else if AStmt is TPCExprStmt then
      DoExprStmt(TPCExprStmt(AStmt))
    else if AStmt is TPCVerbatimStmt then
      DoVerbatimStmt(TPCVerbatimStmt(AStmt))
    else if AStmt is TPCDirective then
      DoBodyDirective(TPCDirective(AStmt))
    else if AStmt is TPCErrorStmt then
    begin
      // Recovered tokens: a fragment the parser kept (a repeated section, a
      // header block in a body: A7) resolves silently; nothing else
      if TPCErrorStmt(AStmt).Fragment is TPCStmt then
        DoStmt(TPCStmt(TPCErrorStmt(AStmt).Fragment));
    end;
  finally
    if LInside then
      DoLeaveRecovered();
  end;
end;

const
  { PC_SEM_JUMP_TEXT }
  // The PaskalCPP word a message gives each jump (SM0609)
  PC_SEM_JUMP_TEXT: array[TPCGuardEscape] of string = (
    'return', 'leave', 'skip'
  );

  { PC_SEM_CPP_JUMP_TEXT }
  // The C++ word a message gives each C++ jump (SM0614)
  PC_SEM_CPP_JUMP_TEXT: array[TPCCppJumpKind] of string = (
    'return', 'break', 'continue'
  );

procedure TPCSemantics.DoPushFlow(const AKind: TPCFlowKind; const AOwner: TPCStmt);
var
  LEntry: TPCFlowEntry;
begin
  LEntry.FlowKind := AKind;
  LEntry.Owner := AOwner;
  FFlow.Add(LEntry);
end;

procedure TPCSemantics.DoPopFlow();
begin
  FFlow.Delete(FFlow.Count - 1);
end;

function TPCSemantics.DoInFlow(const AKind: TPCFlowKind): Boolean;
var
  LIndex: Integer;
begin
  // Any entry of the kind on the stack: a guard nested in an except list
  // keeps its parent's Except entry below its own (statements.md :152-153)
  for LIndex := FFlow.Count - 1 downto 0 do
  begin
    if FFlow[LIndex].FlowKind = AKind then
      Exit(True);
  end;
  Result := False;
end;

function TPCSemantics.DoInnermost(const AKinds: TPCFlowKinds): Integer;
var
  LIndex: Integer;
begin
  // The index of the innermost entry of one of the kinds; -1 = none
  for LIndex := FFlow.Count - 1 downto 0 do
  begin
    if FFlow[LIndex].FlowKind in AKinds then
      Exit(LIndex);
  end;
  Result := -1;
end;

procedure TPCSemantics.DoFlowList(const AKind: TPCFlowKind; const AOwner: TPCStmt; const AList: TList<TPCStmt>);
begin
  // A construct's own list is checked with its entry on the stack
  DoPushFlow(AKind, AOwner);
  try
    DoNestedList(AOwner, AList);
  finally
    DoPopFlow();
  end;
end;

function TPCSemantics.DoCheckIteratorWrite(const ATarget: TPCExpr): Boolean;
begin
  // Q13 (a): a write SEM can see to a for iterator inside its loop (an
  // assignment, ++ / --, a var argument) is an error at the write; a write
  // through a pointer or inside C++ cannot be seen. True = reported
  Result := False;
  if (FIterators = nil) or not (ATarget is TPCName) or (TPCName(ATarget).ResolvedDecl = nil) then
    Exit;
  if not FIterators.Contains(TPCName(ATarget).ResolvedDecl) then
    Exit;
  DoError(ATarget, PC_ERR_SEM_602, RSSemStmtIteratorWrite, [ATarget.ExprText()]);
  Result := True;
end;

function TPCSemantics.DoNotVariableText(const ADecl: TPCNode): string;
begin
  // What a for name binds to when it is no variable (SM0600)
  if ADecl is TPCConstDecl then
    Result := RSSemStmtKindConst
  else if ADecl is TPCParam then
    Result := RSSemStmtKindConstParam
  else if ADecl is TPCTypeDecl then
    Result := RSSemStmtKindType
  else if ADecl is TPCRoutine then
    Result := RSSemStmtKindRoutine
  else if ADecl is TPCField then
    Result := RSSemStmtKindField
  else if ADecl is TPCChoiceValue then
    Result := RSSemStmtKindChoice
  else if ADecl is TPCImport then
    Result := RSSemStmtKindModule
  else
    Result := RSSemStmtKindOther;
end;

function TPCSemantics.DoBindIterator(const AFor: TPCFor): TPCTypeExpr;
var
  LFound: TList<TPCNode>;
  LDecl: TPCNode;
  LType: TPCTypeExpr;
  LFrameKind: TPCFrameKind;
begin
  // statements.md :96-100, BNF.md sec 5: the name binds to a var or a
  // non-const parameter declared before the loop (for never declares one).
  // A name PaskalCPP does not know is a C/C++ variable: clang judges it.
  // nil = no PaskalCPP type to check the bounds against
  Result := nil;
  AFor.ResolvedIteratorOpaque := False;
  LFound := TList<TPCNode>.Create();
  try
    DoLookup(AFor.IteratorName, LFound, LFrameKind);
    // A member named bare (PLAN-OBJECT D9): self.X is no iterator either
    if (LFound.Count > 0) and (LFrameKind = fkMembers) then
    begin
      DoBareMember(AFor, AFor.IteratorName);
      Exit;
    end;
    if LFound.Count = 0 then
    begin
      if DoUsedLater(AFor.IteratorName) <> nil then
      begin
        DoError(AFor, PC_ERR_SEM_002, RSSemCoreUsedBefore, [AFor.IteratorName]);
        Exit;
      end;
      // An imported unit's var is declared before the loop too
      // (PLAN-IMPORT-RESOLUTION); two units = SM0020; none = a C/C++
      // variable, clang judges it (BNF sec 5): the emitter's C++ form
      if not DoImportedName(AFor.Range, True, AFor.IteratorName, LFound) then
      begin
        AFor.ResolvedIteratorOpaque := True;
        Exit;
      end;
      if LFound.Count = 0 then
        Exit;
    end;
    if LFound.Count > 1 then
    begin
      // An overload set names routines; any other repeat was SM0004
      if DoAllRoutines(LFound) then
        DoError(AFor, PC_ERR_SEM_600, RSSemStmtForNotVar, [AFor.IteratorName, RSSemStmtKindRoutine]);
      Exit;
    end;
    LDecl := LFound[0];
  finally
    LFound.Free();
  end;
  if LDecl is TPCVarDecl then
    LType := TPCVarDecl(LDecl).TypeExpr
  else if (LDecl is TPCParam) and (TPCParam(LDecl).ParamMode <> pmConst) then
    LType := TPCParam(LDecl).TypeExpr
  else
  begin
    DoError(AFor, PC_ERR_SEM_600, RSSemStmtForNotVar, [AFor.IteratorName, DoNotVariableText(LDecl)]);
    Exit;
  end;
  AFor.ResolvedIterator := LDecl;
  // Q13 (a): a nested for over the same iterator writes it
  if FIterators.Contains(LDecl) then
    DoError(AFor, PC_ERR_SEM_602, RSSemStmtIteratorWrite, [AFor.IteratorName]);
  LType := DoValueTypeOf(LType);
  if DoIsErrorType(LType) then
    Exit;
  if DoIsOpaqueTier(LType) or (DoOrdinalKindOf(LType) in [okInteger, okChar, okWChar, okChoices]) then
    Exit(LType);
  DoError(AFor, PC_ERR_SEM_601, RSSemStmtForType, [LType.TypeText()]);
end;

procedure TPCSemantics.DoForStmt(const AFor: TPCFor);
var
  LType: TPCTypeExpr;
  LAdded: Boolean;
begin
  // The bounds are in the enclosing scope, then the iterator binds and the
  // bounds convert to its type (a choice iterator takes values of that
  // choice only). The body is checked with a Loop entry and the iterator
  // marked as looped over (Q13)
  DoExpr(AFor.StartExpr);
  DoExpr(AFor.EndExpr);
  LType := DoBindIterator(AFor);
  if LType <> nil then
  begin
    DoCheckConvert(AFor.StartExpr, LType);
    DoCheckConvert(AFor.EndExpr, LType);
  end;
  LAdded := (AFor.ResolvedIterator <> nil) and not FIterators.Contains(AFor.ResolvedIterator);
  if LAdded then
    FIterators.Add(AFor.ResolvedIterator);
  try
    DoFlowList(fwLoop, AFor, AFor.Stmts);
  finally
    if LAdded then
      FIterators.Remove(AFor.ResolvedIterator);
  end;
end;

function TPCSemantics.DoMatchSubjectType(const ASubject: TPCExpr): TPCTypeExpr;
begin
  // statements.md :106-107: an integer, char, wchar or a choice (no C++
  // switch on a string; a bool is clang's -Wswitch-bool). nil = nothing to
  // check the labels against: a reported or C/C++ subject (clang judges)
  Result := nil;
  if DoNotValue(ASubject) then
    Exit;
  if (ASubject = nil) or DoIsPoisoned(ASubject) or (ASubject.ResolvedType = nil) or
    DoIsErrorType(ASubject.ResolvedType) or DoIsOpaqueTier(ASubject.ResolvedType) then
    Exit;
  if DoOrdinalKindOf(ASubject.ResolvedType) in [okInteger, okChar, okWChar, okChoices] then
    Exit(ASubject.ResolvedType);
  DoError(ASubject, PC_ERR_SEM_603, RSSemStmtMatchSubject, [ASubject.ResolvedType.TypeText()]);
  DoPoison(ASubject);
end;

function TPCSemantics.DoWideLess(const AFirstHigh: Int64; const AFirstLow: UInt64; const ASecondHigh: Int64;
  const ASecondLow: UInt64): Boolean;
begin
  // First < second for two 128-bit two's complement pairs (DoConstWide)
  Result := (AFirstHigh < ASecondHigh) or ((AFirstHigh = ASecondHigh) and (AFirstLow < ASecondLow));
end;

function TPCSemantics.DoSpansOverlap(const AFirst: TPCMatchSpan; const ASecond: TPCMatchSpan): Boolean;
begin
  // Two closed intervals share a value unless one ends before the other starts
  Result := not (DoWideLess(AFirst.HighHigh, AFirst.HighLow, ASecond.LowHigh, ASecond.LowLow) or
    DoWideLess(ASecond.HighHigh, ASecond.HighLow, AFirst.LowHigh, AFirst.LowLow));
end;

function TPCSemantics.DoLabelText(const ALabel: TPCMatchLabel): string;
begin
  // A label as written: low, or low..high
  Result := ALabel.LowExpr.ExprText();
  if ALabel.HighExpr <> nil then
    Result := Result + '..' + ALabel.HighExpr.ExprText();
end;

function TPCSemantics.DoCheckLabelBound(const ABound: TPCExpr; const ASubjectType: TPCTypeExpr): Boolean;
var
  LToken: TPCTokenKind;
  LBits: Integer;
  LIsUnsigned: Boolean;
begin
  // One label bound against the subject's type. Q18 (a): a known value
  // outside an integer subject's range never matches (checked before the
  // conversion, whose message would only name the types); then it converts
  // implicitly (a choice subject: values of that choice only). True = its
  // value is known and it was not reported
  if (ABound = nil) or DoIsPoisoned(ABound) then
    Exit(False);
  if DoFoldedInteger(ABound) and DoBuiltinOf(ASubjectType, LToken) and
    DoIntTypeInfo(LToken, LBits, LIsUnsigned) and not DoConstFits(ABound, LToken) then
  begin
    DoError(ABound, PC_ERR_SEM_604, RSSemStmtLabelRange, [DoConstText(ABound), ASubjectType.TypeText()]);
    DoPoison(ABound);
    Exit(False);
  end;
  DoCheckConvert(ABound, ASubjectType);
  Result := DoFoldedInteger(ABound);
end;

function TPCSemantics.DoCheckMatchLabel(const ALabel: TPCMatchLabel; const ASubjectType: TPCTypeExpr;
  const ASpans: TList<TPCMatchSpan>): Boolean;
var
  LLowKnown: Boolean;
  LHighKnown: Boolean;
  LHigh: TPCExpr;
  LSpan: TPCMatchSpan;
  LPrevious: TPCMatchSpan;
begin
  // statements.md :108-113: constant bounds of the subject's type; a known
  // range low > high is an error (clang only warns); two known labels that
  // share a value are an error naming the first. True = the label's values
  // are known (the coverage check counts it)
  Result := False;
  DoExpr(ALabel.LowExpr);
  DoExpr(ALabel.HighExpr);
  DoCheckConstant(ALabel.LowExpr, RSSemTypePosLabel);
  DoCheckConstant(ALabel.HighExpr, RSSemTypePosLabel);
  if ASubjectType = nil then
    Exit;
  LLowKnown := DoCheckLabelBound(ALabel.LowExpr, ASubjectType);
  LHighKnown := True;
  if ALabel.HighExpr <> nil then
    LHighKnown := DoCheckLabelBound(ALabel.HighExpr, ASubjectType);
  if not (LLowKnown and LHighKnown) then
    Exit;
  LHigh := ALabel.HighExpr;
  if LHigh = nil then
    LHigh := ALabel.LowExpr;
  if DoBoundsReversed(ALabel.LowExpr, LHigh) then
  begin
    // An empty range covers nothing: known, no span
    DoError(ALabel.LowExpr, PC_ERR_SEM_267, RSSemTypeLowHigh, [ALabel.LowExpr.ExprText(), LHigh.ExprText()]);
    Exit(True);
  end;
  DoConstWide(ALabel.LowExpr, LSpan.LowHigh, LSpan.LowLow);
  DoConstWide(LHigh, LSpan.HighHigh, LSpan.HighLow);
  LSpan.LabelNode := ALabel;
  for LPrevious in ASpans do
  begin
    if DoSpansOverlap(LSpan, LPrevious) then
    begin
      if DoError(ALabel.LowExpr, PC_ERR_SEM_605, RSSemStmtLabelRepeat,
        [DoLabelText(ALabel), UIntToStr(LPrevious.LabelNode.Range.StartLine)]) then
        DoNote(LPrevious.LabelNode, RSSemStmtFirstLabel, [DoLabelText(LPrevious.LabelNode)]);
      Exit(True);
    end;
  end;
  ASpans.Add(LSpan);
  Result := True;
end;

procedure TPCSemantics.DoCheckCoverage(const AMatch: TPCMatch; const ASubjectType: TPCTypeExpr;
  const ASpans: TList<TPCMatchSpan>);
var
  LChoices: TPCChoicesType;
  LValue: TPCChoiceValue;
  LPoint: TPCMatchSpan;
  LSpan: TPCMatchSpan;
  LCovered: Boolean;
  LMissing: string;
begin
  // Q15 (a): a choice subject, no else, every label known: the values no
  // label covers are named in a WARNING (EMIT writes default: break;, O-S6c)
  if (ASubjectType = nil) or AMatch.HasElse or not (ASubjectType.Canon() is TPCChoicesType) then
    Exit;
  LChoices := TPCChoicesType(ASubjectType.Canon());
  LMissing := '';
  for LValue in LChoices.Values do
  begin
    if LValue = nil then
      Continue;
    // A value DECLS could not number: coverage unknown
    if not LValue.HasResolvedOrdinal then
      Exit;
    if LValue.ResolvedOrdinal < 0 then
      LPoint.LowHigh := -1
    else
      LPoint.LowHigh := 0;
    LPoint.LowLow := UInt64(LValue.ResolvedOrdinal);
    LPoint.HighHigh := LPoint.LowHigh;
    LPoint.HighLow := LPoint.LowLow;
    LCovered := False;
    for LSpan in ASpans do
    begin
      if DoSpansOverlap(LPoint, LSpan) then
      begin
        LCovered := True;
        Break;
      end;
    end;
    if LCovered then
      Continue;
    if LMissing <> '' then
      LMissing := LMissing + ', ';
    LMissing := LMissing + LValue.ValueName;
  end;
  if LMissing <> '' then
    DoWarning(AMatch, PC_ERR_SEM_606, RSSemStmtNotCovered, [ASubjectType.TypeText(), LMissing]);
end;

procedure TPCSemantics.DoMatchStmt(const AMatch: TPCMatch);
var
  LSubjectType: TPCTypeExpr;
  LSpans: TList<TPCMatchSpan>;
  LArm: TPCMatchArm;
  LLabel: TPCMatchLabel;
  LAllKnown: Boolean;
begin
  // statements.md :106-117: the subject; per arm its labels, then its list
  // with a Match entry; the else list; then the coverage of a choice match
  DoExpr(AMatch.Subject);
  LSubjectType := DoMatchSubjectType(AMatch.Subject);
  LAllKnown := LSubjectType <> nil;
  LSpans := TList<TPCMatchSpan>.Create();
  DoPushFlow(fwMatch, AMatch);
  try
    for LArm in AMatch.Arms do
    begin
      if LArm = nil then
      begin
        LAllKnown := False;
        Continue;
      end;
      for LLabel in LArm.Labels do
      begin
        if (LLabel = nil) or not DoCheckMatchLabel(LLabel, LSubjectType, LSpans) then
          LAllKnown := False;
      end;
      DoNestedList(AMatch, LArm.Stmts);
    end;
    if AMatch.HasElse then
      DoNestedList(AMatch, AMatch.ElseStmts);
    if LAllKnown and not DoStopped() then
      DoCheckCoverage(AMatch, LSubjectType, LSpans);
  finally
    DoPopFlow();
    LSpans.Free();
  end;
end;

procedure TPCSemantics.DoGuardStmt(const AGuard: TPCGuard);
begin
  // statements.md :118-122: the guard body is the guard's hidden function
  // (a GuardBody entry: a jump out of it is written to ResolvedEscapes);
  // the except and finally lists have their own entries
  AGuard.ResolvedEscapes := [];
  AGuard.ResolvedExceptEscapes := [];
  DoFlowList(fwGuardBody, AGuard, AGuard.GuardStmts);
  if AGuard.HasExcept then
    DoFlowList(fwExcept, AGuard, AGuard.ExceptStmts);
  if AGuard.HasFinally then
    DoFlowList(fwFinally, AGuard, AGuard.FinallyStmts);
end;

function TPCSemantics.DoJumpOut(const AJump: TPCStmt; const ATargetIndex: Integer;
  const AEscape: TPCGuardEscape): Boolean;
var
  LIndex: Integer;
  LEntry: TPCFlowEntry;
  LGuard: TPCGuard;
begin
  // The entries a jump leaves, innermost first, down to its target (-1 =
  // the routine: a return). Q14 (a): leaving a finally list is an error;
  // every guard body it leaves records the flow (a nested guard's escape
  // that also leaves the outer guard is in both sets). False = reported
  for LIndex := FFlow.Count - 1 downto ATargetIndex + 1 do
  begin
    LEntry := FFlow[LIndex];
    if LEntry.FlowKind = fwFinally then
    begin
      DoError(AJump, PC_ERR_SEM_609, RSSemStmtJumpFinally, [PC_SEM_JUMP_TEXT[AEscape]]);
      Exit(False);
    end;
    if LEntry.FlowKind = fwGuardBody then
    begin
      LGuard := TPCGuard(LEntry.Owner);
      Include(LGuard.ResolvedEscapes, AEscape);
    end
    else if LEntry.FlowKind = fwExcept then
    begin
      // The except list is a lambda when the guard has a finally: the
      // emitter dispatches these like the body's (PLAN-EMITTER A7)
      LGuard := TPCGuard(LEntry.Owner);
      Include(LGuard.ResolvedExceptEscapes, AEscape);
    end;
  end;
  Result := True;
end;

procedure TPCSemantics.DoLeaveStmt(const ALeave: TPCLeave);
var
  LTarget: Integer;
begin
  // statements.md :123-125: the innermost loop or match
  LTarget := DoInnermost([fwLoop, fwMatch]);
  if LTarget < 0 then
  begin
    DoError(ALeave, PC_ERR_SEM_607, RSSemStmtLeaveOutside, []);
    Exit;
  end;
  if DoJumpOut(ALeave, LTarget, geLeave) then
    ALeave.ResolvedJumpTarget := FFlow[LTarget].Owner;
end;

procedure TPCSemantics.DoSkipStmt(const ASkip: TPCSkip);
var
  LTarget: Integer;
begin
  // statements.md :126-128: the innermost loop (a match is passed over:
  // continue reaches the loop through a switch)
  LTarget := DoInnermost([fwLoop]);
  if LTarget < 0 then
  begin
    DoError(ASkip, PC_ERR_SEM_608, RSSemStmtSkipOutside, []);
    Exit;
  end;
  if DoJumpOut(ASkip, LTarget, geSkip) then
    ASkip.ResolvedJumpTarget := FFlow[LTarget].Owner;
end;

procedure TPCSemantics.DoReturnStmt(const AReturn: TPCReturn);
var
  LReturnType: TPCTypeExpr;
begin
  // statements.md :129-132: the routine being checked (nil = module or test
  // body); no jump out of finally (Q14); a function returns a value that
  // converts to its return type, everything else returns none
  DoExpr(AReturn.ValueExpr);
  AReturn.ResolvedRoutine := FRoutine;
  DoJumpOut(AReturn, -1, geReturn);
  LReturnType := nil;
  if FRoutine <> nil then
    LReturnType := FRoutine.ReturnType;
  if LReturnType = nil then
  begin
    if AReturn.ValueExpr <> nil then
      DoError(AReturn.ValueExpr, PC_ERR_SEM_611, RSSemStmtReturnNoValue, []);
    Exit;
  end;
  if AReturn.ValueExpr = nil then
  begin
    if not DoIsErrorType(LReturnType) then
      DoError(AReturn, PC_ERR_SEM_610, RSSemStmtReturnNeeds, [LReturnType.TypeText()]);
    Exit;
  end;
  // PLAN-OBJECT O5 / D5: a returned local is moved, not copied
  DoMarkMove(AReturn.ValueExpr);
  DoCheckConvert(AReturn.ValueExpr, LReturnType);
end;

function TPCSemantics.DoIsCppTyped(const AExpr: TPCExpr): Boolean;
begin
  // A value whose type is C/C++'s (opaque tier)
  Result := (AExpr <> nil) and (AExpr.ResolvedType <> nil) and DoIsOpaqueTier(AExpr.ResolvedType);
end;

function TPCSemantics.DoHasEffect(const AExpr: TPCExpr): Boolean;
begin
  // Q16 (a): an assignment, a call (PaskalCPP, intrinsic, C++), ++ / --,
  // new, delete, verbatim C++, a varargs step, a ?: whose both branches have
  // one, a cast of one that has. An operator, index, member or braced init
  // on a C/C++ value is C++'s (an overloaded operator acts: std::cout << X),
  // and so is a C/C++ name (a macro): clang judges. A reported or missing
  // expression is not judged (C1)
  if (AExpr = nil) or DoIsPoisoned(AExpr) then
    Exit(True);
  if (AExpr is TPCAssign) or (AExpr is TPCCall) or (AExpr is TPCNew) or (AExpr is TPCDelete) or
    (AExpr is TPCVerbatimExpr) or (AExpr is TPCOwnerNew) then
    Exit(True);
  if AExpr is TPCUnary then
    Exit((TPCUnary(AExpr).Op in [uoPreInc, uoPreDec, uoPostInc, uoPostDec]) or
      DoIsCppTyped(TPCUnary(AExpr).Operand));
  if AExpr is TPCTernary then
    Exit(DoHasEffect(TPCTernary(AExpr).ThenExpr) and DoHasEffect(TPCTernary(AExpr).ElseExpr));
  if AExpr is TPCCast then
    Exit(DoHasEffect(TPCCast(AExpr).Operand));
  // PLAN-OBJECT O12: is / as act as a cast does: through their operand
  if AExpr is TPCTypeTest then
    Exit(DoHasEffect(TPCTypeTest(AExpr).Operand));
  if AExpr is TPCVarargs then
    Exit(TPCVarargs(AExpr).VarargsKind in [vaNext, vaReset, vaCopy]);
  if AExpr is TPCBinary then
    Exit(DoIsCppTyped(TPCBinary(AExpr).Left) or DoIsCppTyped(TPCBinary(AExpr).Right));
  if AExpr is TPCIndex then
    Exit(DoIsCppTyped(TPCIndex(AExpr).Base));
  if AExpr is TPCBracedInit then
    Exit(DoIsCppTyped(AExpr));
  if AExpr is TPCMember then
    Exit(TPCMember(AExpr).ResolvedKind = rkOpaque);
  if AExpr is TPCName then
    Exit(TPCName(AExpr).ResolvedKind = rkOpaque);
  Result := False;
end;

procedure TPCSemantics.DoExprStmt(const AStmt: TPCExprStmt);
var
  LSaved: TPCAssign;
begin
  // An expression statement has an effect (Q16 (a)). PLAN-OBJECT O9: an
  // assignment that is the statement itself is marked (a property's write
  // has no value: DoPropertyAssign)
  LSaved := FStmtAssign;
  if AStmt.Expr is TPCAssign then
    FStmtAssign := TPCAssign(AStmt.Expr)
  else
    FStmtAssign := nil;
  try
    DoExpr(AStmt.Expr);
  finally
    FStmtAssign := LSaved;
  end;
  if not DoHasEffect(AStmt.Expr) then
    DoError(AStmt.Expr, PC_ERR_SEM_613, RSSemStmtNoEffect, []);
end;

procedure TPCSemantics.DoVerbatimStmt(const AStmt: TPCVerbatimStmt);
var
  LJump: TPCCppJump;
  LIndex: Integer;
  LKind: TPCFlowKind;
  LTakers: TPCFlowKinds;
  LLeft: TPCFlowKind;
  LLeavesGuard: Boolean;
begin
  // Q17 (a): a C++ jump leaving a cppstart block inside a guard body leaves
  // only the guard's hidden function: a return always, a break / continue
  // when no PaskalCPP loop (a break: or match) inside the guard body takes
  // it. A finally body is a hidden function too (pcpp::Finally's lambda,
  // user 2026-10-07). Verbatim C++ is otherwise never looked into
  for LJump in AStmt.Verbatim.EscapingJumps do
  begin
    case LJump.Kind of
      cjBreak:
        LTakers := [fwLoop, fwMatch];
      cjContinue:
        LTakers := [fwLoop];
    else
      LTakers := [];
    end;
    LLeavesGuard := False;
    LLeft := fwGuardBody;
    for LIndex := FFlow.Count - 1 downto 0 do
    begin
      LKind := FFlow[LIndex].FlowKind;
      if LKind in LTakers then
        Break;
      // An except list is a hidden function too when its guard has a
      // finally (the finally must run after it on every path)
      if (LKind = fwGuardBody) or (LKind = fwFinally) or
        ((LKind = fwExcept) and TPCGuard(FFlow[LIndex].Owner).HasFinally) then
      begin
        LLeavesGuard := True;
        LLeft := LKind;
        Break;
      end;
    end;
    if LLeavesGuard and (LLeft = fwFinally) then
      DoReportRange(LJump.Range, esError, PC_ERR_SEM_614, RSSemStmtCppJumpFinally, [PC_SEM_CPP_JUMP_TEXT[LJump.Kind]])
    else if LLeavesGuard and (LLeft = fwExcept) then
      DoReportRange(LJump.Range, esError, PC_ERR_SEM_614, RSSemStmtCppJumpExcept, [PC_SEM_CPP_JUMP_TEXT[LJump.Kind]])
    else if LLeavesGuard then
      DoReportRange(LJump.Range, esError, PC_ERR_SEM_614, RSSemStmtCppJumpGuard, [PC_SEM_CPP_JUMP_TEXT[LJump.Kind]]);
  end;
end;

function TPCSemantics.DoStmtReturns(const AStmt: TPCStmt): Boolean;
var
  LArm: TPCMatchArm;
  LJump: TPCCppJump;
  LCall: TPCCall;
begin
  // Q12 (a), statements.md :133-139: whether a statement provably returns.
  // A statement the parser dropped is not judged (C1)
  if AStmt = nil then
    Exit(True);
  if AStmt is TPCReturn then
    Exit(True);
  if AStmt is TPCExprStmt then
  begin
    if not (TPCExprStmt(AStmt).Expr is TPCCall) then
      Exit(False);
    LCall := TPCCall(TPCExprStmt(AStmt).Expr);
    Exit((LCall.IntrinsicKind = ikRaise) or (LCall.IntrinsicKind = ikRaiseCode));
  end;
  if AStmt is TPCBlock then
    Exit(DoListReturns(TPCBlock(AStmt).Stmts));
  if AStmt is TPCIf then
    Exit(TPCIf(AStmt).HasElse and DoListReturns(TPCIf(AStmt).ThenStmts) and
      DoListReturns(TPCIf(AStmt).ElseStmts));
  if AStmt is TPCMatch then
  begin
    if not TPCMatch(AStmt).HasElse or not DoListReturns(TPCMatch(AStmt).ElseStmts) then
      Exit(False);
    for LArm in TPCMatch(AStmt).Arms do
    begin
      if (LArm <> nil) and not DoListReturns(LArm.Stmts) then
        Exit(False);
    end;
    Exit(True);
  end;
  if AStmt is TPCGuard then
    Exit(DoListReturns(TPCGuard(AStmt).GuardStmts) and
      (not TPCGuard(AStmt).HasExcept or DoListReturns(TPCGuard(AStmt).ExceptStmts)));
  // A cppstart block returns when the parser recorded an escaping C++
  // return in it (O-S6b); clang checks the rest
  if AStmt is TPCVerbatimStmt then
  begin
    for LJump in TPCVerbatimStmt(AStmt).Verbatim.EscapingJumps do
    begin
      if LJump.Kind = cjReturn then
        Exit(True);
    end;
  end;
  Result := False;
end;

function TPCSemantics.DoListReturns(const AList: TList<TPCStmt>): Boolean;
var
  LStmt: TPCStmt;
begin
  // The last statement decides; an empty list does not return. A list
  // holding a statement the parser could not finish is not judged: that
  // statement may have returned (PLAN-RECOVERY)
  if (AList = nil) or (AList.Count = 0) then
    Exit(False);
  for LStmt in AList do
  begin
    if (LStmt <> nil) and (LStmt.IsRecovered or (LStmt is TPCErrorStmt)) then
      Exit(True);
  end;
  Result := DoStmtReturns(AList[AList.Count - 1]);
end;

class function TPCSemantics.DoHasRecoveredTarget(const ATargets: TList<TPCCallTarget>): Boolean;
var
  LTarget: TPCCallTarget;
begin
  // A routine type's value has no Decl: a marked routine type is already an
  // error type (DoIsErrorType) and poisoned before the targets are built
  for LTarget in ATargets do
  begin
    if (LTarget.Decl <> nil) and LTarget.Decl.IsRecovered then
      Exit(True);
  end;
  Result := False;
end;

class function TPCSemantics.DoAnyRecovered(const ARoutines: TList<TPCRoutine>): Boolean;
var
  LRoutine: TPCRoutine;
begin
  // True when one routine of a set is one the parser could not finish
  for LRoutine in ARoutines do
  begin
    if (LRoutine <> nil) and LRoutine.IsRecovered then
      Exit(True);
  end;
  Result := False;
end;

procedure TPCSemantics.DoCheckReturnPath(const ARoutine: TPCRoutine);
var
  LRange: TSourceRange;
begin
  // Q12 (a): a function's body ends in a statement that returns; reported
  // at the body's `end` (its range ends on that token's last byte)
  if (ARoutine.ReturnType = nil) or (ARoutine.Body = nil) or DoStopped() then
    Exit;
  if DoListReturns(ARoutine.Body.Stmts) then
    Exit;
  LRange := ARoutine.Body.Range;
  LRange.StartLine := LRange.EndLine;
  LRange.StartColumn := LRange.EndColumn;
  LRange.StartByteOffset := LRange.EndByteOffset;
  if (LRange.EndColumn >= 3) and (LRange.EndByteOffset >= 3) then
  begin
    LRange.StartColumn := LRange.EndColumn - 2;
    LRange.StartByteOffset := LRange.EndByteOffset - 3;
  end;
  DoReportRange(LRange, esError, PC_ERR_SEM_612, RSSemStmtMissingReturn, [ARoutine.DeclName]);
end;

procedure TPCSemantics.DoRoutine(const ARoutine: TPCRoutine);
var
  LParam: TPCParam;
  LSavedFlow: TList<TPCFlowEntry>;
  LSavedRoutine: TPCRoutine;
  LInside: Boolean;
begin
  // Params and return type in the ENCLOSING frame; then the routine's frame.
  // A routine the parser recovered is walked silently (PLAN-RECOVERY)
  if ARoutine = nil then
    Exit;
  LInside := DoEnterRecovered(ARoutine);
  try
    DoCheckParamDuplicates(ARoutine.Params);
    for LParam in ARoutine.Params do
    begin
      // PLAN-OBJECT O9: a write's value type is its property's, judged there
      if (LParam <> nil) and not LParam.IsTypeBorrowed then
      begin
        DoTypeExpr(LParam.TypeExpr);
        DoCheckComplete(LParam.TypeExpr, False);
        // PLAN-OBJECT D7: a value parameter holds its object by value
        if LParam.ParamMode = pmNone then
          DoCheckConcrete(LParam.TypeExpr, LParam.TypeExpr);
      end;
    end;
    // ... and a read's result type
    if ARoutine.RoutineKind <> rnRead then
    begin
      DoTypeExpr(ARoutine.ReturnType);
      DoCheckComplete(ARoutine.ReturnType, False);
      DoCheckConcrete(ARoutine.ReturnType, ARoutine.ReturnType);
    end;
    // Linkage by meaning (decls.md: never overwrite Linkage); R-LINK may demote
    // it at the list end. A full pairs with its forward once its parameter
    // types are resolved and before its body (a call in it sees one routine)
    if ARoutine.Linkage = lnC then
      ARoutine.ResolvedLinkage := lnC
    else
      ARoutine.ResolvedLinkage := lnCpp;
    if not ARoutine.IsForward and (FFrames[DoTopIndex()].Current = ARoutine) then
      DoPairRoutine(ARoutine);
    DoResolveExternalLib(ARoutine, ARoutine.ExternalClause);
    DoPushFrame(TPCScopes.RoutineFrame(ARoutine));
    // A routine is checked with its own context stack (a jump never leaves a
    // routine) and is the routine its returns belong to
    LSavedFlow := FFlow;
    LSavedRoutine := FRoutine;
    FFlow := TList<TPCFlowEntry>.Create();
    FRoutine := ARoutine;
    try
      DoItemList(ARoutine.Decls, True);
      if ARoutine.Body <> nil then
        DoItemList(ARoutine.Body.Stmts, False);
      DoCheckReturnPath(ARoutine);
    finally
      FFlow.Free();
      FFlow := LSavedFlow;
      FRoutine := LSavedRoutine;
      DoPopFrame();
    end;
  finally
    if LInside then
      DoLeaveRecovered();
  end;
end;

procedure TPCSemantics.DoBlock(const ABlock: TPCBlock);
begin
  // The module body: one list over the module frame
  if ABlock <> nil then
    DoNestedList(ABlock, ABlock.Stmts);
end;

procedure TPCSemantics.DoTest(const ATest: TPCTest);
var
  LInside: Boolean;
begin
  if ATest = nil then
    Exit;
  // A test the parser recovered is walked silently (PLAN-RECOVERY)
  LInside := DoEnterRecovered(ATest);
  try
    DoPushFrame(TPCScopes.TestFrame(ATest));
    try
      DoItemList(ATest.Decls, True);
      if ATest.Body <> nil then
        DoItemList(ATest.Body.Stmts, False);
    finally
      DoPopFrame();
    end;
  finally
    if LInside then
      DoLeaveRecovered();
  end;
end;

procedure TPCSemantics.DoTypeDecl(const ADecl: TPCTypeDecl);
begin
  // A full declaration completes its forwards BEFORE its TypeDef is analyzed
  // (a method body reaches members through the forward); until its end the
  // type is being defined (FDefining: a field of it by value is incomplete)
  if ADecl.IsForward then
  begin
    DoForwardType(ADecl);
    Exit;
  end;
  DoFullType(ADecl);
  FDefining.Add(ADecl);
  try
    DoTypeExpr(ADecl.TypeDef);
  finally
    FDefining.Delete(FDefining.Count - 1);
  end;
  // An alias holds its type by value (decls.md TPCVarDecl position list)
  if (ADecl.TypeDef is TPCNamedType) or (ADecl.TypeDef is TPCArrayType) then
    DoCheckComplete(ADecl.TypeDef, False);
end;

procedure TPCSemantics.DoTypeExpr(const AType: TPCTypeExpr);
var
  LParam: TPCParam;
  LItem: TPCMemberItem;
  LPart: TPCNamePart;
  LFace: TPCNamedType;
  LInside: Boolean;
begin
  if AType = nil then
    Exit;
  // A type definition the parser recovered is walked silently (PLAN-RECOVERY)
  LInside := DoEnterRecovered(AType);
  try
    if AType is TPCNamedType then
      DoResolveNamedType(TPCNamedType(AType))
    else if AType is TPCPointerType then
      DoTypeExpr(TPCPointerType(AType).TargetType)
    else if AType is TPCOwnerType then
    begin
      DoTypeExpr(TPCOwnerType(AType).TargetType);
      DoCheckOwnerTarget(TPCOwnerType(AType));
    end
    else if AType is TPCArrayType then
    begin
      // A static bound is a constant (CHECKS); a dynamic array has none (nil)
      DoExpr(TPCArrayType(AType).LowExpr);
      DoExpr(TPCArrayType(AType).HighExpr);
      DoCheckConstant(TPCArrayType(AType).LowExpr, RSSemTypePosArrayBound);
      DoCheckConstant(TPCArrayType(AType).HighExpr, RSSemTypePosArrayBound);
      DoTypeExpr(TPCArrayType(AType).ElementType);
      DoCheckArrayBounds(TPCArrayType(AType));
    end
    else if AType is TPCSetType then
    begin
      // A range bound sizes the set (NEEDS); the element form has none (nil)
      DoTypeExpr(TPCSetType(AType).ElementType);
      DoExpr(TPCSetType(AType).LowExpr);
      DoExpr(TPCSetType(AType).HighExpr);
      DoCheckConstant(TPCSetType(AType).LowExpr, RSSemTypePosSetBound);
      DoCheckConstant(TPCSetType(AType).HighExpr, RSSemTypePosSetBound);
      DoCheckSetType(TPCSetType(AType));
    end
    else if AType is TPCRecordType then
    begin
      DoCheckMemberDuplicates(TPCRecordType(AType).Members, TPCRecordType(AType).Members);
      DoTypeExpr(TPCRecordType(AType).ParentName);
      // PLAN-OBJECT O7: the interfaces named after implements
      for LFace in TPCRecordType(AType).Implements do
        DoTypeExpr(LFace);
      // PLAN-OBJECT D7: polymorphic / abstract before the members (a body may
      // hold a local of this type), the override rules after them
      DoResolveDispatch(TPCRecordType(AType));
      DoExpr(TPCRecordType(AType).AlignExpr);
      DoCheckConstant(TPCRecordType(AType).AlignExpr, RSSemTypePosAlign);
      DoCheckAlign(TPCRecordType(AType));
      for LItem in TPCRecordType(AType).Members do
        DoMemberItem(AType, LItem);
      // After the members: the parent's names read resolved types, and so
      // does the natural alignment (SM0311)
      DoCheckParent(TPCRecordType(AType));
      DoCheckDispatch(TPCRecordType(AType));
      // PLAN-OBJECT O7: every interface method present, virtual, same signature
      DoCheckImplements(TPCRecordType(AType));
      // PLAN-OBJECT D3: init / done (the inits' leading calls are marked)
      DoCheckLifecycle(TPCRecordType(AType));
      // PLAN-OBJECT O11: each operator's shape, = / <> as a pair
      DoCheckOperators(TPCRecordType(AType));
      // PLAN-OBJECT O9: each property's bound fields
      DoCheckPropertyBindings(TPCRecordType(AType));
      DoCheckNaturalAlign(TPCRecordType(AType));
      DoCheckPackedRecord(TPCRecordType(AType));
      // F34: the fields of an anonymous overlay in it share storage
      DoCheckOverlayFields(TPCRecordType(AType).Members, False, DoDefiningName(AType));
    end
    else if AType is TPCOverlayType then
    begin
      DoCheckMemberDuplicates(TPCOverlayType(AType).Members, TPCOverlayType(AType).Members);
      for LItem in TPCOverlayType(AType).Members do
        DoMemberItem(AType, LItem);
      // F34: every field shares the overlay's storage, a packed anonymous
      // record's too: the overlay rule judges them (DoCheckPackedFields)
      DoCheckOverlayFields(TPCOverlayType(AType).Members, True, DoDefiningName(AType));
    end
    else if AType is TPCRoutineType then
    begin
      // Parameter names unique: one rule with TPCRoutine (decls.md TPCRoutineType)
      DoCheckParamDuplicates(TPCRoutineType(AType).Params);
      for LParam in TPCRoutineType(AType).Params do
      begin
        if LParam <> nil then
          DoTypeExpr(LParam.TypeExpr);
      end;
      DoTypeExpr(TPCRoutineType(AType).ReturnType);
    end
    else if AType is TPCChoicesType then
      DoChoicesType(TPCChoicesType(AType))
    else if AType is TPCCppType then
    begin
      // C++ name parts are never looked up (T11); only their template args (G7)
      for LPart in TPCCppType(AType).NameParts do
      begin
        if LPart <> nil then
          DoNodeChildren(LPart);
      end;
    end;
    // The varargs type is only a variadic routine's local (Q30); every other
    // TPCBuiltinType and the shared instances: nothing
    if (AType is TPCBuiltinType) and (TPCBuiltinType(AType).BuiltinToken = tkKwVarargs) and
      (AType <> FVarargsLocal) then
      DoError(AType, PC_ERR_SEM_422, RSSemCallVarargsType, [PC_VARARGS_WORDS[vaPlain], PC_VARARGS_WORDS[vaCopy]]);
  finally
    if LInside then
      DoLeaveRecovered();
  end;
end;

procedure TPCSemantics.DoMemberItem(const AOwner: TPCTypeExpr; const AItem: TPCMemberItem);
var
  LItem: TPCMemberItem;
  LTypeDecl: TPCTypeDecl;
  LCurrent: TPCStmt;
  LInside: Boolean;
  LObject: TPCTypeExpr;
begin
  if AItem = nil then
    Exit;
  // A member the parser recovered (or an error member) is walked silently
  // (PLAN-RECOVERY); an error member has no branch: nothing in it to walk
  LInside := DoEnterRecovered(AItem);
  try
    if AItem is TPCField then
    begin
      DoTypeExpr(TPCField(AItem).TypeExpr);
      DoCheckComplete(TPCField(AItem).TypeExpr, True);
      DoCheckConcrete(TPCField(AItem).TypeExpr, TPCField(AItem).TypeExpr);
      // PLAN-OBJECT O8: an embed holds a type whose members PaskalCPP reaches
      if TPCField(AItem).IsEmbed then
        DoCheckEmbed(TPCField(AItem));
      // PLAN-OBJECT D3: an array field builds its elements without arguments
      // (an object field is built by the inits: DoCheckLifecycle)
      if TPCField(AItem).TypeExpr is TPCArrayType then
        DoCheckDefaultBuild(TPCField(AItem).TypeExpr, TPCField(AItem).TypeExpr);
      // PLAN-OBJECT H3 (O5): a record or an overlay (anonymous ones in them
      // too) is plain data, C layout: it holds no object, by value or in an
      // array (a ptr to one is fine)
      // ... nor own / ref / weak of one (O6, H3)
      if not ((AOwner is TPCRecordType) and TPCRecordType(AOwner).IsObject) then
      begin
        if DoHoldsObject(TPCField(AItem).TypeExpr, LObject) then
          DoError(TPCField(AItem).TypeExpr, PC_ERR_SEM_357, RSSemDeclRecordHoldsObject,
            [TPCField(AItem).FieldName, LObject.TypeText()])
        else if DoHoldsOwner(TPCField(AItem).TypeExpr, LObject) then
          DoError(TPCField(AItem).TypeExpr, PC_ERR_SEM_357, RSSemDeclRecordHoldsOwner,
            [TPCField(AItem).FieldName, LObject.TypeText()]);
      end;
      DoExpr(TPCField(AItem).BitWidthExpr);
      DoCheckConstant(TPCField(AItem).BitWidthExpr, RSSemTypePosBitWidth);
      DoCheckBitfield(TPCField(AItem));
    end
    else if AItem is TPCAnonAggregate then
    begin
      for LItem in TPCAnonAggregate(AItem).Members do
        DoMemberItem(AOwner, LItem);
    end
    else if AItem is TPCPropertyItem then
      // PLAN-OBJECT O9: its type once (the accessors borrow it), then each
      // accessor: a binding's field, an inline one's body as a method's
      DoProperty(AOwner, TPCPropertyItem(AItem))
    else if (AItem is TPCRoutineMember) and (TPCRoutineMember(AItem).Routine <> nil) then
    begin
      // The method (an init, a done) sees its object's members: method ->
      // members -> module (Q1)
      LCurrent := FFrames[DoTopIndex()].Current;
      LTypeDecl := nil;
      if (LCurrent is TPCTypeDecl) and (TPCTypeDecl(LCurrent).TypeDef = AOwner) then
        LTypeDecl := TPCTypeDecl(LCurrent);
      // PLAN-OBJECT O11: an operator is called by its type's name (T::...).
      // Every type that holds members is a type block's: one written in a
      // type expr position is the parser's PR0026, kept as a recovered node
      // and walked silently (O15: SM0385 retired, it could not fire)
      if (AItem is TPCOperatorItem) and (LTypeDecl <> nil) then
        TPCOperatorItem(AItem).ResolvedOwner := DoNamedTypeOf(LTypeDecl);
      // PLAN-OBJECT D3: an init's leading init calls are marked before its
      // body is walked (DoMarkLeadInits)
      if (AItem is TPCInitItem) and (AOwner is TPCRecordType) then
        DoMarkLeadInits(TPCRecordType(AOwner), TPCInitItem(AItem));
      DoPushFrame(TPCScopes.MembersFrame(AOwner, LTypeDecl));
      try
        DoRoutine(TPCRoutineMember(AItem).Routine);
      finally
        DoPopFrame();
      end;
    end;
  finally
    if LInside then
      DoLeaveRecovered();
  end;
end;

procedure TPCSemantics.DoProperty(const AOwner: TPCTypeExpr; const AProperty: TPCPropertyItem);
begin
  // PLAN-OBJECT O9 / D12: the property's type (held by value: a value
  // parameter and a result of it), then each inline accessor as a method is
  // walked (DoMemberItem: its type's members, then its routine). Bindings
  // are judged after the members (DoCheckPropertyBindings)
  // O10: an index parameter is a parameter of both accessors (by value or
  // const, as a routine's)
  if AProperty.IndexParam <> nil then
  begin
    DoTypeExpr(AProperty.IndexParam.TypeExpr);
    DoCheckComplete(AProperty.IndexParam.TypeExpr, False);
    if AProperty.IndexParam.ParamMode = pmNone then
      DoCheckConcrete(AProperty.IndexParam.TypeExpr, AProperty.IndexParam.TypeExpr);
  end;
  DoTypeExpr(AProperty.TypeExpr);
  DoCheckComplete(AProperty.TypeExpr, False);
  DoCheckConcrete(AProperty.TypeExpr, AProperty.TypeExpr);
  if (AProperty.ReadItem <> nil) and not AProperty.ReadItem.IsBinding() then
    DoMemberItem(AOwner, AProperty.ReadItem);
  if (AProperty.WriteItem <> nil) and not AProperty.WriteItem.IsBinding() then
    DoMemberItem(AOwner, AProperty.WriteItem);
end;

procedure TPCSemantics.DoCheckPropertyBindings(const ARecord: TPCRecordType);
var
  LItem: TPCMemberItem;
  LProperty: TPCPropertyItem;
  LIndex: Integer;
  LAccessor: TPCAccessorItem;
  LFound: TList<TPCNode>;
  LField: TPCField;
  LDefault: TPCPropertyItem;
begin
  // PLAN-OBJECT O9: after the members (a binding may name a later field). A
  // binding names a field of the object's chain (SM0371) of the property's
  // type exactly (SM0372); written to ResolvedField. A recovered property
  // stays silent (DoReportRange)
  LDefault := nil;
  for LItem in ARecord.Members do
  begin
    if not (LItem is TPCPropertyItem) then
      Continue;
    LProperty := TPCPropertyItem(LItem);
    // O10: `default` names the type's one indexed property LO[i] means
    // (SM0379: on a property with no index, or a second one in the type)
    if LProperty.IsDefault and not LProperty.IsRecovered then
    begin
      if LProperty.IndexParam = nil then
        DoReportRange(LProperty.DefaultRange, esError, PC_ERR_SEM_379, RSSemDeclPropertyDefaultIndex,
          [LProperty.PropName])
      else if LDefault <> nil then
      begin
        if DoReportRange(LProperty.DefaultRange, esError, PC_ERR_SEM_379, RSSemDeclPropertyDefaultTwice,
          [LProperty.PropName, DoDefiningName(ARecord), LDefault.PropName]) then
          DoNote(LDefault, RSSemDeclMemberHere, [DoDefiningName(ARecord), LDefault.PropName]);
      end
      else
        LDefault := LProperty;
    end;
    for LIndex := 0 to 1 do
    begin
      if LIndex = 0 then
        LAccessor := LProperty.ReadItem
      else
        LAccessor := LProperty.WriteItem;
      if (LAccessor = nil) or not LAccessor.IsBinding() or LAccessor.IsRecovered or LProperty.IsRecovered then
        Continue;
      LFound := TList<TPCNode>.Create();
      try
        TPCScopes.FindMember(ARecord, LAccessor.FieldName, LFound);
        LField := nil;
        if (LFound.Count = 1) and (LFound[0] is TPCField) then
          LField := TPCField(LFound[0]);
      finally
        LFound.Free();
      end;
      if LField = nil then
      begin
        DoReportRange(LAccessor.FieldRange, esError, PC_ERR_SEM_371, RSSemDeclPropertyNoField,
          [LProperty.PropName, LAccessor.FieldName, DoDefiningName(ARecord)]);
        Continue;
      end;
      LAccessor.ResolvedField := LField;
      if (LField.TypeExpr <> nil) and (LProperty.TypeExpr <> nil) and not DoIsErrorType(LField.TypeExpr) and
        not DoIsErrorType(LProperty.TypeExpr) and not DoSameTypeAs(LField.TypeExpr, LProperty.TypeExpr, True) then
        DoReportRange(LAccessor.FieldRange, esError, PC_ERR_SEM_372, RSSemDeclPropertyFieldType,
          [LProperty.PropName, LProperty.TypeExpr.TypeText(), LField.FieldName, LField.TypeExpr.TypeText()]);
    end;
  end;
end;

procedure TPCSemantics.DoChoicesType(const AChoices: TPCChoicesType);
var
  LIndex: Integer;
  LEarlier: Integer;
  LValue: TPCChoiceValue;
  LType: TPCTypeExpr;
  LNext: Int64;
  LKnown: Boolean;
  LPastMax: Boolean;
begin
  // Every value's type first, before any value expression is analyzed: a
  // value names only earlier ones (and an import was analyzed whole first)
  LNext := 0;
  LKnown := True;
  LPastMax := False;
  LType := DoChoicesNamedType(AChoices);
  for LValue in AChoices.Values do
  begin
    if LValue <> nil then
      LValue.ResolvedChoices := LType;
  end;
  // A value expression sees the values before it (fkChoices innermost)
  DoPushFrame(TPCScopes.ChoicesFrame(AChoices));
  try
    for LIndex := 0 to AChoices.Values.Count - 1 do
    begin
      if DoStopped() then
        Break;
      LValue := AChoices.Values[LIndex];
      FFrames.List[DoTopIndex()].FirstCount := LIndex;
      if LValue = nil then
        Continue;
      for LEarlier := 0 to LIndex - 1 do
      begin
        if (AChoices.Values[LEarlier] <> nil) and (AChoices.Values[LEarlier].ValueName = LValue.ValueName) then
        begin
          DoReportDuplicate(LValue, AChoices.Values[LEarlier], LValue.ValueName);
          Break;
        end;
      end;
      // The value is a constant; its ordinal is written now, so a later
      // value naming it carries it (DoChoiceLeaf)
      DoExpr(LValue.ValueExpr);
      DoCheckConstant(LValue.ValueExpr, RSSemTypePosChoice);
      DoChoiceOrdinal(LValue, LNext, LKnown, LPastMax);
    end;
  finally
    DoPopFrame();
  end;
end;

function TPCSemantics.DoFieldIndex(const ARecord: TPCRecordType; const AName: string; out AField: TPCField): Integer;
var
  LItem: TPCMemberItem;
  LIndex: Integer;
begin
  // A designated initializer names the record's own fields (a member of an
  // anonymous overlay or record is not one): their declaration position
  // among them; -1 = no such field
  AField := nil;
  LIndex := 0;
  for LItem in ARecord.Members do
  begin
    if not (LItem is TPCField) then
      Continue;
    if TPCField(LItem).FieldName = AName then
    begin
      AField := TPCField(LItem);
      Exit(LIndex);
    end;
    Inc(LIndex);
  end;
  Result := -1;
end;

function TPCSemantics.DoFieldCount(const ARecord: TPCRecordType): Integer;
var
  LItem: TPCMemberItem;
begin
  // The fields DoFieldIndex numbers (the record's own: no anonymous member)
  Result := 0;
  for LItem in ARecord.Members do
  begin
    if LItem is TPCField then
      Inc(Result);
  end;
end;

function TPCSemantics.DoIsLiteralRecord(const AType: TPCTypeExpr): Boolean;
var
  LLevel: TPCRecordType;
  LVisited: TList<TPCRecordType>;
begin
  // A record literal's type (PLAN-RECORDS M14): a PaskalCPP record whose
  // every parent level is a PaskalCPP record held as a member (M10). A
  // C/C++ parent anywhere on the chain is a base class no designated
  // initializer reaches; an object is no record
  Result := False;
  if not (AType is TPCRecordType) then
    Exit;
  LLevel := TPCRecordType(AType);
  LVisited := TList<TPCRecordType>.Create();
  try
    while (LLevel <> nil) and not LVisited.Contains(LLevel) do
    begin
      LVisited.Add(LLevel);
      if LLevel.IsObject then
        Exit(False);
      if LLevel.ParentName = nil then
        Exit(True);
      if not LLevel.HasParentMember() then
        Exit(False);
      LLevel := LLevel.ParentRecord();
    end;
  finally
    LVisited.Free();
  end;
end;

function TPCSemantics.DoChainFieldIndex(const ARecord: TPCRecordType; const AName: string; out AField: TPCField;
  out AHops: Integer): Integer;
var
  LLevels: TList<TPCRecordType>;
  LOffsets: TArray<Integer>;
  LLevel: TPCRecordType;
  LIndex: Integer;
  LOffset: Integer;
  LLocal: Integer;
begin
  // PLAN-RECORDS M14: a literal on an extension names the fields of every
  // member-parent level, the nearest level first (as a member lookup). The
  // declaration order runs root first: a level's fields come after all of
  // its parents' (the emitter's nesting order). AHops = the levels up to the
  // record declaring AField; -1 = no such field
  AField := nil;
  AHops := 0;
  Result := -1;
  LLevels := TList<TPCRecordType>.Create();
  try
    LLevel := ARecord;
    while (LLevel <> nil) and not LLevels.Contains(LLevel) do
    begin
      LLevels.Add(LLevel);
      LLevel := LLevel.ParentRecord();
    end;
    SetLength(LOffsets, LLevels.Count);
    LOffset := 0;
    for LIndex := LLevels.Count - 1 downto 0 do
    begin
      LOffsets[LIndex] := LOffset;
      LOffset := LOffset + DoFieldCount(LLevels[LIndex]);
    end;
    for LIndex := 0 to LLevels.Count - 1 do
    begin
      LLocal := DoFieldIndex(LLevels[LIndex], AName, AField);
      if AField <> nil then
      begin
        AHops := LIndex;
        Result := LOffsets[LIndex] + LLocal;
        Exit;
      end;
    end;
  finally
    LLevels.Free();
  end;
end;

procedure TPCSemantics.DoRecordLiteral(const ALiteral: TPCRecordLiteral);
var
  LCanon: TPCTypeExpr;
  LRecord: TPCRecordType;
  LInit: TPCFieldInit;
  LField: TPCField;
  LIndex: Integer;
  LHops: Integer;
  LLastIndex: Integer;
  LLast: TPCField;
  LSeen: TList<TPCField>;
begin
  // calls.md :224-225, BNF.md sec 6: a PaskalCPP record whose parents are
  // PaskalCPP records (PLAN-RECORDS M14; emitted as a C++20 designated
  // initializer, an inherited field inside its parent's braces); each named
  // field exists on some level, is named once and in declaration order (root
  // first), and its value converts implicitly; an omitted field is
  // value-initialized. A C/C++ type is clang's (DESIGN.md sec 2)
  DoNodeChildren(ALiteral);
  if (ALiteral.RecordType = nil) or DoIsErrorType(ALiteral.RecordType) then
    Exit;
  ALiteral.ResolvedType := ALiteral.RecordType;
  if DoIsOpaqueTier(ALiteral.RecordType) then
    Exit;
  LCanon := ALiteral.RecordType.Canon();
  if not DoIsLiteralRecord(LCanon) then
  begin
    DoError(ALiteral.RecordType, PC_ERR_SEM_413, RSSemCallRecordKind, [ALiteral.RecordType.TypeText()]);
    DoPoison(ALiteral);
    Exit;
  end;
  LRecord := TPCRecordType(LCanon);
  LLastIndex := -1;
  LLast := nil;
  LSeen := TList<TPCField>.Create();
  try
    for LInit in ALiteral.Inits do
    begin
      if LInit = nil then
        Continue;
      LIndex := DoChainFieldIndex(LRecord, LInit.FieldName, LField, LHops);
      if LField = nil then
      begin
        DoError(LInit, PC_ERR_SEM_414, RSSemCallRecordNoField, [ALiteral.RecordType.TypeText(), LInit.FieldName]);
        Continue;
      end;
      LInit.ResolvedField := LField;
      LInit.ResolvedParentHops := LHops;
      if LSeen.Contains(LField) then
        DoError(LInit, PC_ERR_SEM_415, RSSemCallRecordTwice, [LInit.FieldName])
      else if LIndex < LLastIndex then
        DoError(LInit, PC_ERR_SEM_416, RSSemCallRecordOrder,
          [LInit.FieldName, LLast.FieldName, ALiteral.RecordType.TypeText()])
      else
      begin
        LLastIndex := LIndex;
        LLast := LField;
      end;
      LSeen.Add(LField);
      DoCheckConvert(LInit.ValueExpr, DoValueTypeOf(LField.TypeExpr));
      // F38: a constant into a bitfield is held by its width
      DoCheckBitfieldStore(LInit.ValueExpr, LField);
    end;
  finally
    LSeen.Free();
  end;
end;

procedure TPCSemantics.DoExpr(const AExpr: TPCExpr);
var
  LInside: Boolean;
begin
  if AExpr = nil then
    Exit;
  // An error expression is walked silently (PLAN-RECOVERY)
  LInside := DoEnterRecovered(AExpr);
  try
    // CORE resolves first; typing runs after it (D-A1b-1)
    if AExpr is TPCName then
    begin
      DoResolveName(TPCName(AExpr));
      DoTypeLeaf(AExpr, TPCName(AExpr).ResolvedDecl, TPCName(AExpr).ResolvedKind);
    end
    else if AExpr is TPCLiteral then
      DoLiteral(TPCLiteral(AExpr))
    else if AExpr is TPCVerbatimExpr then
      // Verbatim C++ is never looked into: opaque tier
      AExpr.ResolvedType := FAst.OpaqueType()
    else if AExpr is TPCMember then
    begin
      // parent.<member> is the one form of parent (a member qualifier): its
      // base is checked as such; any other parent is SM0016 (DoSpecial)
      if (TPCMember(AExpr).Base is TPCSpecial) and (TPCMember(AExpr).Access = maDot) then
        DoSpecial(TPCSpecial(TPCMember(AExpr).Base), True)
      else
        DoExpr(TPCMember(AExpr).Base);
      if TPCMember(AExpr).Member <> nil then
        DoNodeChildren(TPCMember(AExpr).Member);
      DoResolveMember(TPCMember(AExpr));
      // A module or choice member CORE resolved; a value base keeps rkNone (A4)
      DoTypeLeaf(AExpr, TPCMember(AExpr).ResolvedDecl, TPCMember(AExpr).ResolvedKind);
      // A value base is TYPES-B's (D-A1c-1)
      DoValueMember(TPCMember(AExpr));
    end
    else if AExpr is TPCSpecial then
      DoSpecial(TPCSpecial(AExpr), False)
    else if (AExpr is TPCCall) and TPCCall(AExpr).IsLeadInit then
      // PLAN-OBJECT D3: a leading init call (DoMarkLeadInits): its '.init'
      // is never walked as a member
      DoLeadInitCall(TPCCall(AExpr))
    else if AExpr is TPCCall then
    begin
      DoNodeChildren(AExpr);
      DoCallMirror(TPCCall(AExpr));
      DoCall(TPCCall(AExpr));
    end
    else if AExpr is TPCBinary then
      DoBinary(TPCBinary(AExpr))
    else if AExpr is TPCUnary then
      DoUnary(TPCUnary(AExpr))
    else if AExpr is TPCAssign then
      DoAssign(TPCAssign(AExpr))
    else if AExpr is TPCTernary then
      DoTernary(TPCTernary(AExpr))
    else if AExpr is TPCIndex then
      DoIndex(TPCIndex(AExpr))
    else if AExpr is TPCCast then
      DoCast(TPCCast(AExpr))
    else if AExpr is TPCSetLiteral then
      DoSetLiteral(TPCSetLiteral(AExpr))
    else if AExpr is TPCRecordLiteral then
      DoRecordLiteral(TPCRecordLiteral(AExpr))
    else if AExpr is TPCVarargs then
      DoVarargsExpr(TPCVarargs(AExpr))
    else if AExpr is TPCOwnerNew then
      DoOwnerNew(TPCOwnerNew(AExpr))
    else if AExpr is TPCTypeTest then
      DoTypeTest(TPCTypeTest(AExpr))
    else if (AExpr is TPCNew) or (AExpr is TPCDelete) or (AExpr is TPCBracedInit) then
    begin
      // C++ forms: opaque tier (semantics.md new / delete / braced init row)
      DoNodeChildren(AExpr);
      AExpr.ResolvedType := FAst.OpaqueType();
    end
    else if AExpr is TPCErrorExpr then
    begin
      // What parsed before the failure resolves silently (the depth is up);
      // the expression itself is poison: nothing is judged against it
      DoNodeChildren(AExpr);
      DoPoison(AExpr);
    end
    else
      DoNodeChildren(AExpr);
  finally
    if LInside then
      DoLeaveRecovered();
  end;
end;

procedure TPCSemantics.DoNodeChildren(const ANode: TPCNode);
begin
  // Generic descent: expressions and types; an expression owns no statement
  if ANode = nil then
    Exit;
  ANode.EnumChildren(
    procedure(const AChild: TPCNode)
    begin
      if AChild is TPCExpr then
        DoExpr(TPCExpr(AChild))
      else if AChild is TPCTypeExpr then
        DoTypeExpr(TPCTypeExpr(AChild))
      else if not (AChild is TPCStmt) then
        DoNodeChildren(AChild);
    end);
end;

function TPCSemantics.DoListChoice(const AList: TList<TPCStmt>; const ACount: Integer; const AName: string;
  const AModuleName: string; const AExportedOnly: Boolean; out ASpelling: string): Boolean;
var
  LIndex: Integer;
  LDecl: TPCTypeDecl;
  LValue: TPCChoiceValue;
begin
  // A choices type among the first ACount items of a list that has a value
  // AName; ASpelling = how the user reaches it (Mod.TColor.cRed for an import)
  Result := False;
  ASpelling := '';
  if AList = nil then
    Exit;
  for LIndex := 0 to Min(ACount, AList.Count) - 1 do
  begin
    if not (AList[LIndex] is TPCTypeDecl) then
      Continue;
    LDecl := TPCTypeDecl(AList[LIndex]);
    if (AExportedOnly and not LDecl.IsExported) or not (LDecl.TypeDef is TPCChoicesType) then
      Continue;
    for LValue in TPCChoicesType(LDecl.TypeDef).Values do
    begin
      if (LValue = nil) or (LValue.ValueName <> AName) then
        Continue;
      ASpelling := LDecl.DeclName + '.' + AName;
      if AModuleName <> '' then
        ASpelling := AModuleName + '.' + ASpelling;
      Exit(True);
    end;
  end;
end;

function TPCSemantics.DoChoiceSpelling(const AName: string; out ASpelling: string): Boolean;
var
  LIndex: Integer;
  LFrame: TPCScopeFrame;
  LImport: TPCImport;
begin
  // A name no scope declares that is the value of a visible choices type: a
  // choice value is reached through its type only (scopes.md :128-129: the
  // emitted enum class), so the bare name is a PaskalCPP mistake, not C++
  for LIndex := FFrames.Count - 1 downto 0 do
  begin
    LFrame := FFrames[LIndex];
    if DoListChoice(LFrame.First, LFrame.FirstCount, AName, '', False, ASpelling) or
      DoListChoice(LFrame.Second, LFrame.SecondCount, AName, '', False, ASpelling) then
      Exit(True);
    if LFrame.Imports = nil then
      Continue;
    for LImport in LFrame.Imports do
    begin
      if (LImport <> nil) and (LImport.ImportedModule <> nil) and
        DoListChoice(LImport.ImportedModule.Decls, LImport.ImportedModule.Decls.Count, AName, LImport.ModuleName,
        True, ASpelling) then
        Exit(True);
    end;
  end;
  ASpelling := '';
  Result := False;
end;

function TPCSemantics.DoImportedName(const ARange: TSourceRange; const AReport: Boolean; const AName: string;
  const AFound: TList<TPCNode>): Boolean;
var
  LIndex: Integer;
  LImports: TList<TPCImport>;
  LHolders: TList<TPCImport>;
  LFound: TList<TPCNode>;
  LOfHolder: TList<TPCNode>;
  LHolder: TPCImport;
  LNode: TPCNode;
begin
  Result := False;
  // The module frame holds this module's own import clause; a unit's own
  // imports are never followed (FindImported reads each unit's own decls)
  LImports := nil;
  for LIndex := 0 to FFrames.Count - 1 do
  begin
    if FFrames[LIndex].FrameKind = fkModule then
    begin
      LImports := FFrames[LIndex].Imports;
      Break;
    end;
  end;
  if LImports = nil then
    Exit;
  LHolders := TList<TPCImport>.Create();
  LFound := TList<TPCNode>.Create();
  try
    TPCScopes.FindImported(LImports, AName, LFound, LHolders);
    if LHolders.Count = 0 then
      Exit;
    Result := True;
    if LHolders.Count = 1 then
    begin
      AFound.AddRange(LFound);
      Exit;
    end;
    // Two units or more: no order decides between them, the use qualifies
    if not AReport then
      Exit;
    if not DoReportRange(ARange, esError, PC_ERR_SEM_020, RSSemCoreImportAmbiguous,
      [AName, LHolders[0].ModuleName, LHolders[1].ModuleName, LHolders[0].ModuleName, AName,
      LHolders[1].ModuleName, AName]) then
      Exit;
    LOfHolder := TList<TPCNode>.Create();
    try
      for LHolder in LHolders do
      begin
        LOfHolder.Clear();
        TPCScopes.ModuleMember(LHolder.ImportedModule, AName, LOfHolder);
        for LNode in LOfHolder do
          DoNote(LNode, RSSemCoreImportHolder, [AName, LHolder.ModuleName]);
      end;
    finally
      LOfHolder.Free();
    end;
  finally
    LFound.Free();
    LHolders.Free();
  end;
end;

procedure TPCSemantics.DoBindFound(const AName: TPCName; const AFound: TList<TPCNode>);
begin
  if AFound.Count = 1 then
  begin
    AName.ResolvedDecl := AFound[0];
    AName.ResolvedKind := DoResolvedKindOf(AFound[0]);
  end
  else if (AFound.Count > 1) and DoAllRoutines(AFound) then
  begin
    // An overload set lives in one frame or one unit: any member spells its
    // qualification for the emitter (PLAN-EMITTER H2); A6 picks at the call
    AName.ResolvedKind := rkRoutine;
    AName.ResolvedSetMember := TPCRoutine(AFound[0]);
  end
  else
    DoPoison(AName);
end;

procedure TPCSemantics.DoBindFoundType(const AType: TPCNamedType; const ALookupName: string;
  const AFound: TList<TPCNode>);
begin
  if AFound.Count = 1 then
  begin
    if AFound[0] is TPCTypeDecl then
    begin
      AType.ResolvedKind := rkType;
      AType.ResolvedDecl := TPCTypeDecl(AFound[0]);
    end
    else
      DoError(AType, PC_ERR_SEM_013, RSSemCoreNotType, [ALookupName]);
  end
  else if (AFound.Count > 1) and DoAllRoutines(AFound) then
    DoError(AType, PC_ERR_SEM_013, RSSemCoreNotType, [ALookupName]);
end;

procedure TPCSemantics.DoResolveName(const AName: TPCName);
var
  LName: string;
  LSpelling: string;
  LOwn: TPCStmt;
  LDecl: TPCTypeDecl;
  LFound: TList<TPCNode>;
  LFrameKind: TPCFrameKind;
begin
  // A :: name or several parts is C++: opaque (clang judges it)
  if AName.HasLeadingScope or (AName.Parts.Count <> 1) or (AName.Parts[0] = nil) then
  begin
    AName.ResolvedKind := rkOpaque;
    DoNodeChildren(AName);
    Exit;
  end;
  LName := AName.Parts[0].PartText;

  if DoOwnValue(LName) <> nil then
  begin
    DoError(AName, PC_ERR_SEM_001, RSSemCoreOwnDecl, [LName]);
    DoPoison(AName);
    Exit;
  end;
  LOwn := DoOwnItem(LName);
  if (LOwn is TPCVarDecl) or (LOwn is TPCConstDecl) then
  begin
    DoError(AName, PC_ERR_SEM_001, RSSemCoreOwnDecl, [LName]);
    DoPoison(AName);
    Exit;
  end;
  if LOwn is TPCTypeDecl then
  begin
    LDecl := DoResolveOwnType(TPCTypeDecl(LOwn), AName);
    if LDecl <> nil then
    begin
      AName.ResolvedDecl := LDecl;
      AName.ResolvedKind := rkType;
    end
    else
      DoPoison(AName);
    DoNodeChildren(AName);
    Exit;
  end;

  LFound := TList<TPCNode>.Create();
  try
    DoLookup(LName, LFound, LFrameKind);
    if (LFound.Count > 0) and (LFrameKind = fkMembers) then
    begin
      DoBareMember(AName, LName);
      DoPoison(AName);
      Exit;
    end;
    // Order (PLAN-IMPORT-RESOLUTION): the module's own frames, the system
    // scope's intrinsics, an own name used before its declaration, the
    // module's own imports, a bare choice value, then C/C++ (opaque)
    if LFound.Count > 0 then
      DoBindFound(AName, LFound)
    else if DoIntrinsicOf(LName) <> ikNone then
      AName.ResolvedKind := rkIntrinsic
    else if DoUsedLater(LName) <> nil then
    begin
      DoError(AName, PC_ERR_SEM_002, RSSemCoreUsedBefore, [LName]);
      DoPoison(AName);
    end
    else if DoImportedName(AName.Range, True, LName, LFound) then
      DoBindFound(AName, LFound)
    else if DoChoiceSpelling(LName, LSpelling) then
    begin
      DoError(AName, PC_ERR_SEM_015, RSSemCoreBareChoice, [LName, LSpelling]);
      DoPoison(AName);
    end
    else
      AName.ResolvedKind := rkOpaque;
  finally
    LFound.Free();
  end;
  DoNodeChildren(AName);
end;

procedure TPCSemantics.DoResolveNamedType(const AType: TPCNamedType);
var
  LName: string;
  LOwn: TPCStmt;
  LDecl: TPCTypeDecl;
  LFound: TList<TPCNode>;
  LSpelling: string;
begin
  if Length(AType.Parts) <> 1 then
  begin
    DoResolveQualifiedType(AType);
    Exit;
  end;
  LName := AType.Parts[0];

  LOwn := DoOwnItem(LName);
  if LOwn is TPCTypeDecl then
  begin
    LDecl := DoResolveOwnType(TPCTypeDecl(LOwn), AType);
    if LDecl <> nil then
    begin
      AType.ResolvedKind := rkType;
      AType.ResolvedDecl := LDecl;
    end;
    Exit;
  end;
  if (LOwn is TPCVarDecl) or (LOwn is TPCConstDecl) then
  begin
    DoError(AType, PC_ERR_SEM_001, RSSemCoreOwnDecl, [LName]);
    Exit;
  end;

  LFound := TList<TPCNode>.Create();
  try
    // DoResolveName's order, without the intrinsics (none is a type)
    DoLookup(LName, LFound);
    if LFound.Count > 0 then
      DoBindFoundType(AType, LName, LFound)
    else if DoUsedLater(LName) <> nil then
      DoError(AType, PC_ERR_SEM_002, RSSemCoreUsedBefore, [LName])
    else if DoImportedName(AType.Range, True, LName, LFound) then
      DoBindFoundType(AType, LName, LFound)
    else if DoChoiceSpelling(LName, LSpelling) then
      // A visible choice value wins over C/C++ (PROJECT.md): it is a value,
      // never a type, so it is no opaque C++ type name either
      DoError(AType, PC_ERR_SEM_013, RSSemCoreNotType, [LName])
    else
      AType.ResolvedKind := rkOpaque;
  finally
    LFound.Free();
  end;
end;

procedure TPCSemantics.DoResolveQualifiedType(const AType: TPCNamedType);
var
  LHead: string;
  LFound: TList<TPCNode>;
  LModule: TPCModule;
begin
  // Module.Type: modules do not nest and there are no nested types (T3)
  if Length(AType.Parts) >= 3 then
  begin
    DoError(AType, PC_ERR_SEM_008, RSSemCoreQualifiedParts, []);
    Exit;
  end;
  LHead := AType.Parts[0];
  LFound := TList<TPCNode>.Create();
  try
    DoLookup(LHead, LFound);
    if (LFound.Count <> 1) or not (LFound[0] is TPCImport) then
    begin
      DoError(AType, PC_ERR_SEM_007, RSSemCoreNotModule, [LHead]);
      Exit;
    end;
    LModule := TPCImport(LFound[0]).ImportedModule;
    if LModule = nil then
      Exit;
    LFound.Clear();
    if not DoModuleMember(LModule, AType.Parts[1], LFound) then
      DoError(AType, PC_ERR_SEM_005, RSSemCoreModuleNoName, [LHead, AType.Parts[1]])
    else if LFound.Count = 0 then
      DoError(AType, PC_ERR_SEM_006, RSSemCoreNotExported, [AType.Parts[1], LHead])
    else if (LFound.Count = 1) and (LFound[0] is TPCTypeDecl) then
    begin
      AType.ResolvedKind := rkType;
      AType.ResolvedDecl := TPCTypeDecl(LFound[0]);
    end
    else if (LFound.Count = 1) or DoAllRoutines(LFound) then
      DoError(AType, PC_ERR_SEM_013, RSSemCoreNotType, [AType.TypeText()]);
  finally
    LFound.Free();
  end;
end;

procedure TPCSemantics.DoResolveMember(const AMember: TPCMember);
var
  LBase: TPCExpr;
  LPart: string;
  LImport: TPCImport;
  LFound: TList<TPCNode>;
  LDecl: TPCTypeDecl;
  LChoices: TPCChoicesType;
  LValue: TPCChoiceValue;
begin
  // Module.Name and Choices.Value; a value base, self / parent and an opaque
  // base are A4's (D-A1c-1, D-A1c-6). What the head names is the one rule
  // (TPCScopes.HeadImport / HeadTypeDecl / ChoicesOf; completion reads it too)
  LBase := AMember.Base;
  if (AMember.Member = nil) or (LBase = nil) then
    Exit;
  LPart := AMember.Member.PartText;
  if DoIsPoisoned(LBase) then
  begin
    DoPoison(AMember);
    Exit;
  end;

  // (1) a module head
  LImport := TPCScopes.HeadImport(LBase);
  if LImport <> nil then
  begin
    if AMember.Access = maArrow then
    begin
      DoError(AMember, PC_ERR_SEM_014, RSSemCoreArrowQualified, [LBase.ExprText()]);
      DoPoison(AMember);
      Exit;
    end;
    if LImport.ImportedModule = nil then
      Exit;
    LFound := TList<TPCNode>.Create();
    try
      if not DoModuleMember(LImport.ImportedModule, LPart, LFound) then
      begin
        DoError(AMember, PC_ERR_SEM_005, RSSemCoreModuleNoName, [LImport.ModuleName, LPart]);
        DoPoison(AMember);
      end
      else if LFound.Count = 0 then
      begin
        DoError(AMember, PC_ERR_SEM_006, RSSemCoreNotExported, [LPart, LImport.ModuleName]);
        DoPoison(AMember);
      end
      else if LFound.Count = 1 then
      begin
        AMember.ResolvedDecl := LFound[0];
        AMember.ResolvedKind := DoResolvedKindOf(LFound[0]);
      end
      else if DoAllRoutines(LFound) then
        AMember.ResolvedKind := rkRoutine
      else
        DoPoison(AMember);
    finally
      LFound.Free();
    end;
    Exit;
  end;

  // (2) a type head: only a choices type has names reached with '.'
  LDecl := TPCScopes.HeadTypeDecl(LBase);
  if LDecl <> nil then
  begin
    if AMember.Access = maArrow then
    begin
      DoError(AMember, PC_ERR_SEM_014, RSSemCoreArrowQualified, [LBase.ExprText()]);
      DoPoison(AMember);
      Exit;
    end;
    // A forward and its full declaration carry one name (the message's)
    LChoices := TPCScopes.ChoicesOf(LDecl);
    if LChoices <> nil then
    begin
      LValue := DoChoiceMember(LChoices, LPart);
      if LValue <> nil then
      begin
        AMember.ResolvedDecl := LValue;
        AMember.ResolvedKind := rkChoiceValue;
      end
      else
      begin
        DoError(AMember, PC_ERR_SEM_010, RSSemCoreNoChoice, [LDecl.DeclName, LPart]);
        DoPoison(AMember);
      end;
    end;
  end;
end;

procedure TPCSemantics.DoSpecial(const ASpecial: TPCSpecial; const AIsMemberBase: Boolean);
var
  LOwner: TPCRecordType;
  LTypeDecl: TPCTypeDecl;
  LName: string;
begin
  // this / nullptr are C++ spellings, opaque tier (F-S9c)
  if not (ASpecial.SpecialKind in [skSelf, skParent]) then
  begin
    ASpecial.ResolvedType := FAst.OpaqueType();
    Exit;
  end;
  LOwner := DoMethodOwner(LTypeDecl);
  // PLAN-OBJECT O11: an operator is a static routine of its type: no self
  if (FRoutine <> nil) and (FRoutine.RoutineKind = rnOperator) then
    LOwner := nil;
  if LOwner = nil then
  begin
    DoError(ASpecial, PC_ERR_SEM_011, RSSemCoreOutsideMethod, [ASpecial.ExprText()]);
    DoPoison(ASpecial);
    Exit;
  end;
  if (ASpecial.SpecialKind = skParent) and (LOwner.ParentName = nil) then
  begin
    if LTypeDecl <> nil then
      LName := LTypeDecl.DeclName
    else
      LName := LOwner.TypeText();
    DoError(ASpecial, PC_ERR_SEM_012, RSSemCoreNoParent, [LName]);
    DoPoison(ASpecial);
    Exit;
  end;
  // parent is a member qualifier (type_object, 2026-10-12): parent.<member>
  // names the inherited member itself (the emitter writes Parent::member);
  // as a value, an address or a '->' base it has no meaning of its own
  if (ASpecial.SpecialKind = skParent) and (not AIsMemberBase) then
  begin
    DoError(ASpecial, PC_ERR_SEM_016, RSSemCoreParentMember, []);
    DoPoison(ASpecial);
    Exit;
  end;
  // self is the method's object (its declaration's one TPCNamedType, or the
  // anonymous object type); parent is the object's parent type (F-A1c-5)
  if ASpecial.SpecialKind = skParent then
    ASpecial.ResolvedType := DoValueTypeOf(LOwner.ParentName)
  else if LTypeDecl <> nil then
    ASpecial.ResolvedType := DoNamedTypeOf(LTypeDecl)
  else
    ASpecial.ResolvedType := LOwner;
end;

procedure TPCSemantics.DoCallMirror(const ACall: TPCCall);
var
  LCallee: TPCExpr;
begin
  // The call carries its callee name's resolution (scopes.md "What S2 writes")
  LCallee := ACall.Callee;
  if not ((LCallee is TPCName) or (LCallee is TPCMember)) then
    Exit;
  if DoIsPoisoned(LCallee) then
  begin
    DoPoison(ACall);
    Exit;
  end;
  if LCallee is TPCName then
  begin
    ACall.ResolvedDecl := TPCName(LCallee).ResolvedDecl;
    ACall.ResolvedKind := TPCName(LCallee).ResolvedKind;
    if (ACall.ResolvedKind = rkIntrinsic) and (TPCName(LCallee).Parts.Count = 1) then
      ACall.IntrinsicKind := DoIntrinsicOf(TPCName(LCallee).Parts[0].PartText);
  end
  else
  begin
    ACall.ResolvedDecl := TPCMember(LCallee).ResolvedDecl;
    ACall.ResolvedKind := TPCMember(LCallee).ResolvedKind;
  end;
end;

function TPCSemantics.DoInTest(): Boolean;
var
  LIndex: Integer;
begin
  // A call inside a TPCTest body (D-A1c-5): its frame is on the stack
  for LIndex := FFrames.Count - 1 downto 0 do
  begin
    if FFrames[LIndex].FrameKind = fkTest then
      Exit(True);
  end;
  Result := False;
end;

function TPCSemantics.DoRoutineTarget(const ARoutine: TPCRoutine): TPCCallTarget;
begin
  Result.Decl := ARoutine;
  Result.Params := ARoutine.Params;
  Result.IsVariadic := ARoutine.IsVariadic;
  Result.ReturnType := ARoutine.ReturnType;
end;

function TPCSemantics.DoTypeTarget(const AType: TPCRoutineType): TPCCallTarget;
begin
  // A routine value: one signature, no overloads (R-CALLEE)
  Result.Decl := nil;
  Result.Params := AType.Params;
  Result.IsVariadic := AType.IsVariadic;
  Result.ReturnType := AType.ReturnType;
end;

procedure TPCSemantics.DoCallCandidates(const ACall: TPCCall; const ATargets: TList<TPCCallTarget>);
var
  LFound: TList<TPCNode>;
  LNode: TPCNode;
begin
  // R-RANK 1: the set the callee's own resolution searched (DoCalleeDecls).
  // One routine = the callee already names it
  if ACall.ResolvedDecl is TPCRoutine then
  begin
    ATargets.Add(DoRoutineTarget(TPCRoutine(ACall.ResolvedDecl)));
    Exit;
  end;
  LFound := TList<TPCNode>.Create();
  try
    DoCalleeDecls(ACall.Callee, LFound);
    for LNode in LFound do
    begin
      if LNode is TPCRoutine then
        ATargets.Add(DoRoutineTarget(TPCRoutine(LNode)));
    end;
  finally
    LFound.Free();
  end;
end;

procedure TPCSemantics.DoCalleeDecls(const ACallee: TPCExpr; const AFound: TList<TPCNode>);
var
  LMember: TPCMember;
  LBase: TPCExpr;
  LRecord: TPCTypeExpr;
begin
  // R-RANK 1, the one lookup of what a routine name may be (a call's
  // candidates, a routine value's set: R5): the first frame that has the
  // name; a module's exported set; the first class on the parent chain
  // that has it
  if (ACallee is TPCName) and (TPCName(ACallee).Parts.Count = 1) then
  begin
    DoLookup(TPCName(ACallee).Parts[0].PartText, AFound);
    // No frame has it, yet it resolved to a routine: DoResolveName took the
    // import step, so the one unit that exports it holds the set (an
    // ambiguous name was reported there and poisoned: not rkRoutine)
    if (AFound.Count = 0) and (TPCName(ACallee).ResolvedKind = rkRoutine) then
      DoImportedName(ACallee.Range, False, TPCName(ACallee).Parts[0].PartText, AFound);
  end
  else if (ACallee is TPCMember) and (TPCMember(ACallee).Member <> nil) then
  begin
    LMember := TPCMember(ACallee);
    LBase := LMember.Base;
    if (LBase is TPCName) and (TPCName(LBase).ResolvedKind = rkModule) and
      (TPCName(LBase).ResolvedDecl is TPCImport) and
      (TPCImport(TPCName(LBase).ResolvedDecl).ImportedModule <> nil) then
      DoModuleMember(TPCImport(TPCName(LBase).ResolvedDecl).ImportedModule, LMember.Member.PartText, AFound)
    else
    begin
      LRecord := nil;
      if LMember.Base <> nil then
        LRecord := TPCScopes.MemberRecord(LMember.Base.ResolvedType, LMember.Access);
      if LRecord <> nil then
        TPCScopes.FindMember(LRecord, LMember.Member.PartText, AFound);
      // PLAN-OBJECT O8: a method an embed provides, as DoValueMember
      // resolved it (one: methods do not overload within a type)
      if (AFound.Count = 0) and (Length(LMember.ResolvedEmbedPath) > 0) and (LMember.ResolvedDecl <> nil) then
        AFound.Add(LMember.ResolvedDecl);
    end;
  end;
end;

function TPCSemantics.DoCalleeText(const ACall: TPCCall): string;
begin
  // A construction's argument list (TPCVarDecl.InitCall, PLAN-OBJECT D3)
  // has no callee: its arguments go to an init
  if ACall.Callee <> nil then
    Result := ACall.Callee.ExprText()
  else
    Result := PC_CONTEXT_WORDS[cwInit].WordText;
end;

function TPCSemantics.DoArgsReady(const ACall: TPCCall): Boolean;
var
  LArg: TPCExpr;
  LReady: Boolean;
begin
  // Every argument is a value position: a type / module name is SM0269, a
  // procedure call SM0406 (DoNotValue, each reported once). A dropped or
  // reported argument leaves the call unchecked (C1)
  LReady := True;
  for LArg in ACall.Args do
  begin
    if DoNotValue(LArg) then
      LReady := False;
  end;
  for LArg in ACall.Args do
  begin
    if (LArg = nil) or DoIsPoisoned(LArg) or ((LArg.ResolvedType <> nil) and DoIsErrorType(LArg.ResolvedType)) then
      LReady := False;
  end;
  Result := LReady;
end;

procedure TPCSemantics.DoCheckArgs(const ACall: TPCCall; const ATarget: TPCCallTarget);
var
  LIndex: Integer;
  LArg: TPCExpr;
  LParam: TPCParam;
  LTo: TPCTypeExpr;
  LHint: string;
  LValueText: string;
  LLowText: string;
  LHighText: string;
  LRoutine: TPCRoutine;
  LReported: Boolean;
  LTargets: TList<TPCCallTarget>;
begin
  // The one routine SEM bound (a lone routine, or the one member of an
  // overload set that takes the arguments: DoPickOverload):
  // a var parameter takes a variable of its type or of an extension of it (SM0405); every other
  // argument converts to its parameter by PaskalCPP's no-loss rule, the
  // rule of every value position (SM0404, as SM0200). The arguments a `...`
  // takes are clang's.
  // F51 (DESIGN sec 5): the argument count is PaskalCPP's: exactly the
  // parameters, at least the fixed ones with `...` (SM0401 at the call, the
  // one report: a shifted argument is the same mistake, so none are judged)
  if ATarget.IsVariadic and (ACall.Args.Count < ATarget.Params.Count) then
  begin
    DoError(ACall, PC_ERR_SEM_401, RSSemCallArgCountVariadic,
      [DoCalleeText(ACall), ATarget.Params.Count, ACall.Args.Count]);
    Exit;
  end;
  if not ATarget.IsVariadic and (ACall.Args.Count <> ATarget.Params.Count) then
  begin
    DoError(ACall, PC_ERR_SEM_401, RSSemCallArgCount,
      [DoCalleeText(ACall), ATarget.Params.Count, ACall.Args.Count]);
    Exit;
  end;
  for LIndex := 0 to Min(ACall.Args.Count, ATarget.Params.Count) - 1 do
  begin
    LArg := ACall.Args[LIndex];
    LParam := ATarget.Params[LIndex];
    if LParam = nil then
      Continue;
    // Q13 (a): a var argument writes the for iterator inside its loop
    if (LParam.ParamMode = pmVar) and DoCheckIteratorWrite(LArg) then
      Continue;
    if (LArg = nil) or ((LArg.ResolvedType = nil) and not DoIsRoutineValue(LArg)) or (LParam.TypeExpr = nil) or
      DoIsErrorType(LParam.TypeExpr) then
      Continue;
    LTo := DoValueTypeOf(LParam.TypeExpr);
    // PLAN-RECORDS M12 (1): the pointer upcast this argument needs (a C/C++
    // parameter type too, r4d O4c); a var parameter takes no upcast
    if LParam.ParamMode <> pmVar then
      DoNoteUpcast(LArg, LTo);
    if DoIsOpaqueTier(LArg.ResolvedType) or DoIsOpaqueTier(LTo) then
      Continue;
    if LParam.ParamMode = pmVar then
    begin
      if not DoVarTakes(LArg, LTo) then
        DoError(LArg, PC_ERR_SEM_405, RSSemCallVarParam, [LParam.ParamName, LTo.TypeText()]);
      Continue;
    end;
    if (LParam.ParamMode = pmConst) and DoConstTakes(LArg, LTo) then
      Continue;
    if DoConvertsImplicitly(LArg, LTo) then
    begin
      DoBindRoutineValue(LArg, LTo);
      // PLAN-OBJECT O5 / D5: a value parameter copies an lvalue argument (a
      // const one binds it: no copy)
      if LParam.ParamMode = pmNone then
        DoCheckCopy(LArg, LTo);
      Continue;
    end;
    // D6: a polymorphic object by value to its base (SM0428, not SM0404)
    if DoCheckSlice(LArg, LTo) then
      Continue;
    // R5 / D1: a routine value its parameter's type does not take, one note
    if DoIsRoutineValue(LArg) then
    begin
      if TPCExpr.RoutineValueOf(LArg, LRoutine) = rvSet then
        LReported := DoError(LArg, PC_ERR_SEM_404, RSSemCallArgSetNoMember,
          [LIndex + 1, DoCalleeText(ACall), LArg.ExprText(), LTo.TypeText()])
      else
        LReported := DoError(LArg, PC_ERR_SEM_404, RSSemCallArgNoConvert,
          [LIndex + 1, DoCalleeText(ACall), LRoutine.Signature().Text(), LTo.TypeText()]);
      if LReported then
        DoNoteRoutineValue(LArg, LTo);
      Continue;
    end;
    if DoConstNotFit(LArg, LTo, LValueText, LLowText, LHighText) then
      DoError(LArg, PC_ERR_SEM_404, RSSemCallArgNotFit,
        [LIndex + 1, DoCalleeText(ACall), LValueText, LTo.TypeText(), LLowText, LHighText])
    else if DoCastHint(LArg, LTo, LHint) then
      DoError(LArg, PC_ERR_SEM_404, RSSemCallArgCast,
        [LIndex + 1, DoCalleeText(ACall), LArg.ResolvedType.TypeText(), LTo.TypeText(), LHint])
    else
      DoError(LArg, PC_ERR_SEM_404, RSSemCallArgNoConvert,
        [LIndex + 1, DoCalleeText(ACall), LArg.ResolvedType.TypeText(), LTo.TypeText()]);
  end;
  // PLAN-RECORDS M8: what may be misaligned never binds a reference
  LTargets := TList<TPCCallTarget>.Create();
  try
    LTargets.Add(ATarget);
    DoNoteMisalignedArgs(ACall, LTargets);
  finally
    LTargets.Free();
  end;
end;

procedure TPCSemantics.DoBindTarget(const ACall: TPCCall; const ATarget: TPCCallTarget);
begin
  // The pick, written to the call AND its callee name (scopes.md Lookup); the
  // call's value is the return type, a procedure's is void (SM0406 where a
  // value is consumed)
  if ATarget.Decl <> nil then
  begin
    ACall.ResolvedDecl := ATarget.Decl;
    ACall.ResolvedKind := rkRoutine;
    if ACall.Callee is TPCName then
    begin
      TPCName(ACall.Callee).ResolvedDecl := ATarget.Decl;
      TPCName(ACall.Callee).ResolvedKind := rkRoutine;
    end
    else if ACall.Callee is TPCMember then
    begin
      TPCMember(ACall.Callee).ResolvedDecl := ATarget.Decl;
      TPCMember(ACall.Callee).ResolvedKind := rkRoutine;
    end;
  end;
  if ATarget.ReturnType = nil then
    ACall.ResolvedType := FAst.VoidType()
  else
    ACall.ResolvedType := DoValueTypeOf(ATarget.ReturnType);
end;

procedure TPCSemantics.DoPickTarget(const ACall: TPCCall; const ATargets: TList<TPCCallTarget>);
begin
  // One routine: bound, its arguments checked. An overload set: the members
  // PaskalCPP's conversions accept, then clang picks among them (DoPickOverload)
  if ATargets.Count = 0 then
    Exit;
  if ATargets.Count = 1 then
  begin
    DoBindTarget(ACall, ATargets[0]);
    DoCheckArgs(ACall, ATargets[0]);
    Exit;
  end;
  DoPickOverload(ACall, ATargets);
end;

function TPCSemantics.DoTargetTakes(const ACall: TPCCall; const ATarget: TPCCallTarget): Boolean;
begin
  // F18: ATarget takes the call's arguments (DoArgsTake, the one rule)
  Result := DoArgsTake(ACall.Args, ATarget.Params, ATarget.IsVariadic);
end;

function TPCSemantics.DoArgsTake(const AArgs: TList<TPCExpr>; const AParams: TList<TPCParam>;
  const AIsVariadic: Boolean): Boolean;
var
  LIndex: Integer;
  LArg: TPCExpr;
  LParam: TPCParam;
  LTo: TPCTypeExpr;
begin
  // F18: the parameters take the arguments by PaskalCPP's own rules, the
  // ones DoCheckArgs reports with, reporting nothing: the argument count (a
  // variadic member: at least its fixed parameters), a var parameter a
  // variable of its type, every other argument (a routine value too, R5) PaskalCPP's implicit
  // conversion. An opaque C/C++ type on either side, or a parameter already
  // reported, is taken (clang judges it; C1). The arguments are ready
  // (DoArgsReady ran first). A call's members (DoTargetTakes) and a
  // declared operator's operands (PLAN-OBJECT O11) ask this one rule
  Result := False;
  if AIsVariadic then
  begin
    if AArgs.Count < AParams.Count then
      Exit;
  end
  else if AArgs.Count <> AParams.Count then
    Exit;
  for LIndex := 0 to AParams.Count - 1 do
  begin
    LArg := AArgs[LIndex];
    LParam := AParams[LIndex];
    if (LParam = nil) or (LParam.TypeExpr = nil) or DoIsErrorType(LParam.TypeExpr) or
      (LArg = nil) or ((LArg.ResolvedType = nil) and not DoIsRoutineValue(LArg)) then
      Continue;
    LTo := DoValueTypeOf(LParam.TypeExpr);
    if DoIsOpaqueTier(LArg.ResolvedType) or DoIsOpaqueTier(LTo) then
      Continue;
    if LParam.ParamMode = pmVar then
    begin
      if not DoVarTakes(LArg, LTo) then
        Exit;
      Continue;
    end;
    if (LParam.ParamMode = pmConst) and DoConstTakes(LArg, LTo) then
      Continue;
    if not DoConvertsImplicitly(LArg, LTo) then
      Exit;
  end;
  Result := True;
end;

procedure TPCSemantics.DoCollectOperators(const AType: TPCTypeExpr; const AOp: TPCBinaryOp; const AUnary: Boolean;
  const AFound: TList<TPCOperatorItem>);
var
  LCanon: TPCTypeExpr;
  LMember: TPCMemberItem;
  LItem: TPCOperatorItem;
begin
  // PLAN-OBJECT O11: the operators AOp (unary or binary) an operand's record
  // / object declares, judged ones only (a recovered or an unnamed one is
  // never picked), each once (both operands may be of one type)
  if AType = nil then
    Exit;
  LCanon := AType.Canon();
  if not (LCanon is TPCRecordType) then
    Exit;
  for LMember in TPCRecordType(LCanon).Members do
  begin
    if not (LMember is TPCOperatorItem) then
      Continue;
    LItem := TPCOperatorItem(LMember);
    if LItem.IsRecovered or (LItem.Routine = nil) or (LItem.ResolvedOwner = nil) then
      Continue;
    if (LItem.Op <> AOp) or (LItem.IsUnary() <> AUnary) then
      Continue;
    if not AFound.Contains(LItem) then
      AFound.Add(LItem);
  end;
end;

function TPCSemantics.DoExactOperands(const AArgs: TList<TPCExpr>; const AItem: TPCOperatorItem): Boolean;
var
  LIndex: Integer;
begin
  // Every operand has its parameter's exact type (the tie-break among
  // several operators that take the operands, as DoBuildWith's for inits)
  Result := True;
  for LIndex := 0 to AArgs.Count - 1 do
  begin
    if not DoSameType(AArgs[LIndex].ResolvedType, DoValueTypeOf(AItem.Routine.Params[LIndex].TypeExpr)) then
      Exit(False);
  end;
end;

function TPCSemantics.DoOperatorTypesText(const AItem: TPCOperatorItem): string;
var
  LParam: TPCParam;
begin
  // `TVec3, float32`: the operand types an operator takes, as written
  Result := '';
  for LParam in AItem.Routine.Params do
  begin
    if Result <> '' then
      Result := Result + ', ';
    if LParam.TypeExpr <> nil then
      Result := Result + LParam.TypeExpr.TypeText();
  end;
end;

function TPCSemantics.DoOperandTypesText(const AArgs: TList<TPCExpr>): string;
var
  LArg: TPCExpr;
begin
  // `TVec3, int32`: the operands' types
  Result := '';
  for LArg in AArgs do
  begin
    if Result <> '' then
      Result := Result + ', ';
    if LArg.ResolvedType <> nil then
      Result := Result + LArg.ResolvedType.TypeText();
  end;
end;

procedure TPCSemantics.DoNoteOperators(const AItems: TList<TPCOperatorItem>);
var
  LItem: TPCOperatorItem;
begin
  // One note per operator considered, at its declaration
  for LItem in AItems do
    DoNote(LItem.Routine, RSSemCallOperatorMember,
      [LItem.OpText, LItem.ResolvedOwner.TypeText(), DoOperatorTypesText(LItem)]);
end;

function TPCSemantics.DoDeclaredOperator(const ANode: TPCExpr; const AOp: TPCBinaryOp; const AUnary: Boolean;
  const AOperands: array of TPCExpr; out AOperator: TPCOperatorItem): Boolean;
var
  LFound: TList<TPCOperatorItem>;
  LTaken: TList<TPCOperatorItem>;
  LExact: TList<TPCOperatorItem>;
  LArgs: TList<TPCExpr>;
  LOperand: TPCExpr;
  LItem: TPCOperatorItem;
  LPicked: TPCOperatorItem;
  LIndex: Integer;
  LParam: TPCParam;
  LTo: TPCTypeExpr;
begin
  // PLAN-OBJECT O11 (D13): an operator an operand's record / object
  // declares runs instead of the built-in one. False = none is declared for
  // AOp (the built-in rules judge the node). True = handled: the operator
  // that takes the operands by the call rule (DoArgsTake; several: the one
  // with their exact types) is AOperator and the node's type is its result,
  // or none / several take them (SM0430 / SM0431 + a note per operator, the
  // node poisoned, AOperator nil). Which one runs is PaskalCPP's: the emitter
  // calls it by name, C++ never picks
  AOperator := nil;
  Result := False;
  LFound := TList<TPCOperatorItem>.Create();
  LTaken := TList<TPCOperatorItem>.Create();
  LExact := TList<TPCOperatorItem>.Create();
  LArgs := TList<TPCExpr>.Create();
  try
    for LOperand in AOperands do
    begin
      LArgs.Add(LOperand);
      DoCollectOperators(LOperand.ResolvedType, AOp, AUnary, LFound);
    end;
    if LFound.Count = 0 then
      Exit;
    Result := True;
    for LItem in LFound do
    begin
      if DoArgsTake(LArgs, LItem.Routine.Params, False) then
        LTaken.Add(LItem);
    end;
    if LTaken.Count = 0 then
    begin
      if DoError(ANode, PC_ERR_SEM_430, RSSemCallOperatorNone, [LFound[0].OpText, DoOperandTypesText(LArgs)]) then
        DoNoteOperators(LFound);
      DoPoison(ANode);
      Exit;
    end;
    if LTaken.Count = 1 then
      LPicked := LTaken[0]
    else
    begin
      for LItem in LTaken do
      begin
        if DoExactOperands(LArgs, LItem) then
          LExact.Add(LItem);
      end;
      if LExact.Count <> 1 then
      begin
        if DoError(ANode, PC_ERR_SEM_431, RSSemCallOperatorAmbiguous,
          [LTaken[0].OpText, DoOperandTypesText(LArgs)]) then
          DoNoteOperators(LTaken);
        DoPoison(ANode);
        Exit;
      end;
      LPicked := LExact[0];
    end;
    // The operands bind as a call's arguments do: an extension's upcast, a
    // value parameter copies (D5), what may be misaligned is passed copied (M8)
    for LIndex := 0 to LArgs.Count - 1 do
    begin
      LParam := LPicked.Routine.Params[LIndex];
      if (LParam = nil) or (LParam.TypeExpr = nil) then
        Continue;
      LTo := DoValueTypeOf(LParam.TypeExpr);
      DoNoteUpcast(LArgs[LIndex], LTo);
      if (LParam.ParamMode = pmNone) and not DoIsOpaqueTier(LTo) then
        DoCheckCopy(LArgs[LIndex], LTo);
      if DoMayBeMisaligned(LArgs[LIndex]) then
        LArgs[LIndex].ResolvedIsCopied := True;
    end;
    AOperator := LPicked;
    ANode.ResolvedType := DoValueTypeOf(LPicked.Routine.ReturnType);
  finally
    LArgs.Free();
    LExact.Free();
    LTaken.Free();
    LFound.Free();
  end;
end;

procedure TPCSemantics.DoCheckOperators(const ARecord: TPCRecordType);
var
  LIndex: Integer;
  LOtherIndex: Integer;
  LItem: TPCOperatorItem;
  LOther: TPCOperatorItem;
  LParam: TPCParam;
  LOwnText: string;
  LArity: string;
  LBad: Boolean;
  LOwnsOne: Boolean;
  LResult: TPCTypeExpr;
  LPairOp: TPCBinaryOp;
  LPairText: string;
  LHasPair: Boolean;
begin
  // PLAN-OBJECT O11 (D13), after the members (the operand types resolved):
  // each operator's shape (SM0380 operand count, SM0384 a var operand,
  // SM0381 no operand of the declaring type, SM0382 a comparison / in that
  // gives no bool), no two of one symbol with one set of operand types
  // (SM0383), and = / <> as a pair (SM0386)
  for LIndex := 0 to ARecord.Members.Count - 1 do
  begin
    if not (ARecord.Members[LIndex] is TPCOperatorItem) then
      Continue;
    LItem := TPCOperatorItem(ARecord.Members[LIndex]);
    if LItem.IsRecovered or (LItem.Routine = nil) or (LItem.ResolvedOwner = nil) then
      Continue;
    LOwnText := LItem.ResolvedOwner.TypeText();
    if not ((LItem.Routine.Params.Count = 2) or LItem.IsUnary()) then
    begin
      if LItem.Op = boSub then
        LArity := RSSemDeclOperatorArityMinus
      else
        LArity := RSSemDeclOperatorArityBinary;
      DoReportRange(LItem.Routine.NameRange, esError, PC_ERR_SEM_380, RSSemDeclOperatorArity, [LItem.OpText, LArity]);
      Continue;
    end;
    LBad := False;
    for LParam in LItem.Routine.Params do
    begin
      if (LParam <> nil) and (LParam.ParamMode = pmVar) then
      begin
        DoError(LParam, PC_ERR_SEM_384, RSSemDeclOperatorVar, [LItem.OpText, LParam.ParamName]);
        LBad := True;
      end;
    end;
    // A reported operand or result type was reported once already
    if LBad or DoSignatureReported(LItem.Routine) then
      Continue;
    LOwnsOne := False;
    for LParam in LItem.Routine.Params do
    begin
      if DoValueTypeOf(LParam.TypeExpr).Canon() = ARecord then
        LOwnsOne := True;
    end;
    if not LOwnsOne then
    begin
      DoReportRange(LItem.Routine.NameRange, esError, PC_ERR_SEM_381, RSSemDeclOperatorOwnType,
        [LItem.OpText, LOwnText, LOwnText]);
      Continue;
    end;
    if LItem.Op in [boEq, boNotEq, boLess, boLessEq, boGreater, boGreaterEq, boIn] then
    begin
      LResult := DoValueTypeOf(LItem.Routine.ReturnType).Canon();
      if not ((LResult is TPCBuiltinType) and (TPCBuiltinType(LResult).BuiltinToken = tkKwBool)) then
      begin
        DoError(LItem.Routine.ReturnType, PC_ERR_SEM_382, RSSemDeclOperatorBool,
          [LItem.OpText, LItem.Routine.ReturnType.TypeText()]);
        Continue;
      end;
    end;
    // One symbol, one set of operand types: the earlier one as a note
    LBad := False;
    for LOtherIndex := 0 to LIndex - 1 do
    begin
      if not (ARecord.Members[LOtherIndex] is TPCOperatorItem) then
        Continue;
      LOther := TPCOperatorItem(ARecord.Members[LOtherIndex]);
      if LOther.IsRecovered or (LOther.Routine = nil) or (LOther.Op <> LItem.Op) or
        (LOther.IsUnary() <> LItem.IsUnary()) then
        Continue;
      if DoSameParamTypes(LOther.Routine, LItem.Routine) then
      begin
        if DoReportRange(LItem.Routine.NameRange, esError, PC_ERR_SEM_383, RSSemDeclOperatorTwice,
          [LItem.OpText, LOwnText]) then
          DoNote(LOther.Routine, RSSemDeclOperatorHere, [LOther.OpText, LOwnText]);
        LBad := True;
        Break;
      end;
    end;
    if LBad then
      Continue;
    // = and <> come as a pair of the same operand types (D13): a type never
    // has one meaning of = and the built-in or no meaning of <>
    if not (LItem.Op in [boEq, boNotEq]) then
      Continue;
    if LItem.Op = boEq then
    begin
      LPairOp := boNotEq;
      LPairText := '<>';
    end
    else
    begin
      LPairOp := boEq;
      LPairText := '=';
    end;
    LHasPair := False;
    for LOtherIndex := 0 to ARecord.Members.Count - 1 do
    begin
      if not (ARecord.Members[LOtherIndex] is TPCOperatorItem) then
        Continue;
      LOther := TPCOperatorItem(ARecord.Members[LOtherIndex]);
      if (LOther.Routine <> nil) and (LOther.Op = LPairOp) and DoSameParamTypes(LOther.Routine, LItem.Routine) then
        LHasPair := True;
    end;
    if not LHasPair then
      DoReportRange(LItem.Routine.NameRange, esError, PC_ERR_SEM_386, RSSemDeclOperatorPair,
        [LItem.OpText, LOwnText, LPairText]);
  end;
end;

function TPCSemantics.DoVarTakes(const AArg: TPCExpr; const ATo: TPCTypeExpr): Boolean;
begin
  // The one var-parameter rule (F-R4c: DoCheckArgs and DoTargetTakes wrote
  // it twice): a variable of the parameter's type, or of a record extension
  // of it (PLAN-RECORDS R4: the extension's base part is the variable)
  Result := DoIsAssignable(AArg) and (DoSameType(AArg.ResolvedType, ATo) or
    TPCScopes.Extends(AArg.ResolvedType, ATo) or TPCScopes.Derives(AArg.ResolvedType, ATo));
end;

function TPCSemantics.DoConstTakes(const AArg: TPCExpr; const ATo: TPCTypeExpr): Boolean;
begin
  // PLAN-OBJECT D6: a const parameter of an object type binds a descendant
  // object (a C++ reference: no copy, no slicing); every other const
  // argument converts as a value does (DoConvertsImplicitly)
  Result := TPCScopes.Derives(AArg.ResolvedType, ATo);
end;

function TPCSemantics.DoUpcastHops(const AFrom: TPCTypeExpr; const ATo: TPCTypeExpr): Integer;
var
  LFromTarget: TPCTypeExpr;
  LToTarget: TPCTypeExpr;
  LFromConst: Boolean;
  LToConst: Boolean;
  LHops: Integer;
begin
  // PLAN-RECORDS M10 / M12 (1): a pointer to a record extension used as a
  // pointer to a level above it: the parent members between them (the
  // emitter writes ::pcpp::upcast<N>). A C/C++ target: the levels to the
  // record that derives from C/C++ (C++ converts from there, r4d O4c).
  // 0 = no upcast. Const is not judged here (DoConvertsFrom judges it)
  Result := 0;
  if (AFrom = nil) or (ATo = nil) then
    Exit;
  if not TPCTypeExpr.PointerOf(AFrom.Canon(), LFromTarget, LFromConst) or
    not TPCTypeExpr.PointerOf(ATo.Canon(), LToTarget, LToConst) or (LFromTarget = nil) or (LToTarget = nil) then
    Exit;
  if DoIsOpaqueTier(LToTarget) then
  begin
    if TPCScopes.ReachesOpaque(LFromTarget, LHops) then
      Result := LHops;
    Exit;
  end;
  if TPCScopes.Extends(LFromTarget, LToTarget, LHops) then
    Result := LHops;
end;

procedure TPCSemantics.DoNoteUpcast(const AValue: TPCExpr; const ATo: TPCTypeExpr);
begin
  // The one writer of TPCExpr.ResolvedUpcastHops: a value that goes into
  // ATo (an accepted conversion, a lone routine's argument, a compared or
  // ?: operand, an explicit cast). A reported value may keep a mark: the
  // emitter never runs with errors
  if (AValue = nil) or (AValue.ResolvedType = nil) then
    Exit;
  AValue.ResolvedUpcastHops := DoUpcastHops(AValue.ResolvedType, ATo);
  // F-R4f (M12 (4)): a pointer upcast to a part that may sit misaligned is
  // SM0270 (a value / const upcast copies the part out: the operators)
  if (AValue.ResolvedUpcastHops > 0) and DoPointerUpcastMisaligned(AValue.ResolvedType, AValue.ResolvedUpcastHops) then
    DoReportPointerUpcast(AValue, ATo);
end;

procedure TPCSemantics.DoNoteComparedUpcast(const ALeft: TPCExpr; const ARight: TPCExpr);
begin
  // Two pointers of one record chain compared: C++ no longer relates them
  // (M10; r4e tern T_CTRL 'comparison of distinct pointer types'), so the
  // extension side is written as its base (r4e tern c1 / c2)
  if (ALeft = nil) or (ARight = nil) then
    Exit;
  DoNoteUpcast(ALeft, ARight.ResolvedType);
  if ALeft.ResolvedUpcastHops = 0 then
    DoNoteUpcast(ARight, ALeft.ResolvedType);
end;

function TPCSemantics.DoUpcastSideType(const AExtension: TPCTypeExpr; const ABase: TPCTypeExpr): TPCTypeExpr;
var
  LTarget: TPCTypeExpr;
  LExtensionConst: Boolean;
  LBaseConst: Boolean;
begin
  // ?: of an extension pointer and a base pointer: the base side's type,
  // unless only the extension side is const (C++'s composite type is then
  // a pointer to const base, r4e tern p4: opaque, clang types it)
  LExtensionConst := False;
  LBaseConst := False;
  TPCTypeExpr.PointerOf(AExtension.Canon(), LTarget, LExtensionConst);
  TPCTypeExpr.PointerOf(ABase.Canon(), LTarget, LBaseConst);
  if LExtensionConst and not LBaseConst then
    Result := FAst.OpaqueType()
  else
    Result := ABase;
end;

function TPCSemantics.DoIsNilAndPointer(const ANil: TPCTypeExpr; const APointer: TPCTypeExpr): Boolean;
var
  LCanon: TPCTypeExpr;
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
begin
  // ANil is nil's type and APointer a pointer or a routine type (C++'s
  // composite pointer type of T* and nullptr_t is T*)
  Result := False;
  if (ANil = nil) or (APointer = nil) or not (ANil is TPCNilType) then
    Exit;
  LCanon := APointer.Canon();
  Result := (LCanon is TPCRoutineType) or TPCTypeExpr.PointerOf(LCanon, LTarget, LIsConst);
end;

function TPCSemantics.DoTernaryBaseType(const ATernary: TPCTernary): TPCTypeExpr;
var
  LThen: TPCTypeExpr;
  LElse: TPCTypeExpr;
begin
  // R4 rule 4 (r4e tern): a record and its extension meet at the base (C++
  // converts through the conversion operators: v1-v5); pointers to them
  // meet at the base pointer, the upcast written on the extension side
  // (p1-p5). A pointer (or a routine type) and nil meet at the pointer, as
  // C++'s composite pointer type does (found by PLAN-RECORDS A6: typed
  // opaque, a later upcast of the result was never marked). Every other
  // pair of different types stays opaque (C++'s ?:)
  LThen := ATernary.ThenExpr.ResolvedType;
  LElse := ATernary.ElseExpr.ResolvedType;
  if DoIsNilAndPointer(LThen, LElse) then
    Exit(LElse);
  if DoIsNilAndPointer(LElse, LThen) then
    Exit(LThen);
  if TPCScopes.Extends(LThen, LElse) then
    Exit(LElse);
  if TPCScopes.Extends(LElse, LThen) then
    Exit(LThen);
  DoNoteUpcast(ATernary.ThenExpr, LElse);
  if ATernary.ThenExpr.ResolvedUpcastHops > 0 then
    Exit(DoUpcastSideType(LThen, LElse));
  DoNoteUpcast(ATernary.ElseExpr, LThen);
  if ATernary.ElseExpr.ResolvedUpcastHops > 0 then
    Exit(DoUpcastSideType(LElse, LThen));
  Result := FAst.OpaqueType();
end;

function TPCSemantics.DoTakesAtBase(const ACall: TPCCall; const ATargets: TList<TPCCallTarget>): Boolean;
var
  LTarget: TPCCallTarget;
  LIndex: Integer;
  LArg: TPCExpr;
  LParam: TPCParam;
  LTo: TPCTypeExpr;
begin
  // PLAN-RECORDS M12 (2) / M13 (r4d, r4e): some accepted member takes an
  // argument at a level above its record (a record of any mode: Extends; a
  // pointer to a record: an upcast, a C/C++ base included). C++ ranks those
  // only through the overloads form's ranking tags once records are plain
  // members (M10; r4e run 1: AMBIGUOUS where inheritance picked)
  Result := False;
  for LTarget in ATargets do
  begin
    for LIndex := 0 to Min(ACall.Args.Count, LTarget.Params.Count) - 1 do
    begin
      LArg := ACall.Args[LIndex];
      LParam := LTarget.Params[LIndex];
      if (LArg = nil) or (LArg.ResolvedType = nil) or (LParam = nil) or (LParam.TypeExpr = nil) then
        Continue;
      LTo := DoValueTypeOf(LParam.TypeExpr);
      if TPCScopes.Extends(LArg.ResolvedType, LTo) or (DoUpcastHops(LArg.ResolvedType, LTo) > 0) then
        Exit(True);
    end;
  end;
end;

function TPCSemantics.DoMayBeMisaligned(const AValue: TPCExpr): Boolean;
var
  LVisited: TList<TPCTypeExpr>;
  LAlign: UInt64;
begin
  // PLAN-RECORDS M8: a packed level places the value (TPCExpr.OnPackedPath,
  // the AST's placement rule) and its type needs more than 1 byte of
  // alignment, or SEM does not know its alignment (0: a C/C++ type, clang
  // alone lays it out)
  Result := False;
  if (AValue = nil) or (AValue.ResolvedType = nil) or not AValue.OnPackedPath() then
    Exit;
  LVisited := TList<TPCTypeExpr>.Create();
  try
    LAlign := DoTypeAlign(AValue.ResolvedType, LVisited);
  finally
    LVisited.Free();
  end;
  Result := LAlign <> 1;
end;

function TPCSemantics.DoPartMisaligned(const ARecord: TPCTypeExpr; const AHops: Integer): Boolean;
var
  LCanon: TPCTypeExpr;
begin
  // F-R4f (M12 (4)): the part AHops member-parent levels up of a record may
  // sit misaligned in it (TPCRecordType.ParentPartMayBeMisaligned, the one
  // rule the emitter's conversion operators read too)
  Result := False;
  if (ARecord = nil) or (AHops <= 0) then
    Exit;
  LCanon := ARecord.Canon();
  if LCanon is TPCRecordType then
    Result := TPCRecordType(LCanon).ParentPartMayBeMisaligned(AHops);
end;

function TPCSemantics.DoPointerUpcastMisaligned(const AFrom: TPCTypeExpr; const AHops: Integer): Boolean;
var
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
begin
  // A pointer upcast AHops levels up yields a pointer to a part that may be
  // misaligned: the record a ptr to TExt points to may sit anywhere when a
  // level of it is packed
  Result := False;
  if (AFrom = nil) or not TPCTypeExpr.PointerOf(AFrom.Canon(), LTarget, LIsConst) or (LTarget = nil) then
    Exit;
  Result := DoPartMisaligned(LTarget, AHops);
end;

procedure TPCSemantics.DoReportPointerUpcast(const AValue: TPCExpr; const ATo: TPCTypeExpr);
var
  LTarget: TPCTypeExpr;
  LIsConst: Boolean;
begin
  // SM0270 for a pointer upcast DoPointerUpcastMisaligned holds: the
  // message names the packed record the pointer points to
  if not TPCTypeExpr.PointerOf(AValue.ResolvedType.Canon(), LTarget, LIsConst) or (LTarget = nil) then
    Exit;
  DoError(AValue, PC_ERR_SEM_270, RSSemExprMisalignedUpcast, [AValue.ExprText(), ATo.TypeText(), LTarget.TypeText()]);
end;

function TPCSemantics.DoCppRefParam(const AType: TPCTypeExpr; out AIsConst: Boolean): Boolean;
var
  LCanon: TPCTypeExpr;
  LCpp: TPCCppType;
begin
  // A C++ lvalue reference parameter type (`std::int32_t&`, `const T&`):
  // C++ binds it to the argument itself. AIsConst = it refers to const (the
  // last pointer level's cv, else the type's own). An rvalue reference
  // takes no lvalue (clang's)
  AIsConst := False;
  Result := False;
  if AType = nil then
    Exit;
  LCanon := AType.Canon();
  if not (LCanon is TPCCppType) then
    Exit;
  LCpp := TPCCppType(LCanon);
  if LCpp.RefKind <> rfLValue then
    Exit;
  if Length(LCpp.PointerLevels) > 0 then
    AIsConst := cqConst in LCpp.PointerLevels[High(LCpp.PointerLevels)]
  else
    AIsConst := (cqConst in LCpp.LeadCv) or (cqConst in LCpp.TrailCv);
  Result := True;
end;

procedure TPCSemantics.DoNoteMisalignedArgs(const ACall: TPCCall; const ATargets: TList<TPCCallTarget>);
var
  LIndex: Integer;
begin
  // M8 at a call: every argument against every member that may take it (one
  // for a bound routine, the accepted members of an overload set)
  if (ACall = nil) or (ATargets = nil) or (ATargets.Count = 0) then
    Exit;
  for LIndex := 0 to ACall.Args.Count - 1 do
    DoNoteMisalignedArg(ACall, ACall.Args[LIndex], LIndex, ATargets);
end;

procedure TPCSemantics.DoNoteMisalignedArg(const ACall: TPCCall; const AArg: TPCExpr; const AIndex: Integer;
  const ATargets: TList<TPCCallTarget>);
var
  LTarget: TPCCallTarget;
  LParam: TPCParam;
  LTo: TPCTypeExpr;
  LHops: Integer;
  LIsConst: Boolean;
  LMisaligned: Boolean;
  LCopy: Boolean;
  LTakesVar: Boolean;
  LExactTaker: Boolean;
begin
  // A member that binds a writable reference to an argument that may be
  // misaligned (var, a C++ non-const reference) is SM0270, and so is one
  // taking the argument at a base part that may be (F-R4f: a var upcast, a
  // pointer upcast inside the ranked form). A member that binds a const
  // reference (a const aggregate, a const C++ reference, the variadic
  // tail's slot, the ranked form's record argument) gets a copy instead
  if (AArg = nil) or (AArg.ResolvedType = nil) or DoIsPoisoned(AArg) then
    Exit;
  LMisaligned := DoMayBeMisaligned(AArg);
  LCopy := False;
  // Several accepted members: clang ranks them, the closest level first
  // (M12 (2) / M13), so a member taking the argument at its own level
  // (no upcast) is the one an upcast member never beats
  LExactTaker := False;
  if ATargets.Count > 1 then
  begin
    for LTarget in ATargets do
    begin
      if (AIndex >= LTarget.Params.Count) or (LTarget.Params[AIndex] = nil) or
        (LTarget.Params[AIndex].TypeExpr = nil) then
        Continue;
      LTo := DoValueTypeOf(LTarget.Params[AIndex].TypeExpr);
      if not TPCScopes.Extends(AArg.ResolvedType, LTo) and (DoUpcastHops(AArg.ResolvedType, LTo) = 0) then
        LExactTaker := True;
    end;
  end;
  for LTarget in ATargets do
  begin
    if AIndex >= LTarget.Params.Count then
    begin
      // A cpplink variadic slot binds Slot(U&&); a C `...` copies anyway
      if LTarget.IsVariadic then
        LCopy := True;
      Continue;
    end;
    LParam := LTarget.Params[AIndex];
    if (LParam = nil) or (LParam.TypeExpr = nil) or DoIsErrorType(LParam.TypeExpr) then
      Continue;
    LTo := DoValueTypeOf(LParam.TypeExpr);
    if LParam.ParamMode = pmVar then
    begin
      // A member that does not take it is SM0405's (DoCheckArgs) or not a
      // taker at all; a C/C++ type on either side is clang's to accept, the
      // reference is still formed
      LTakesVar := DoVarTakes(AArg, LTo) or
        ((DoIsOpaqueTier(AArg.ResolvedType) or DoIsOpaqueTier(LTo)) and DoIsAssignable(AArg));
      if not LTakesVar then
        Continue;
      if LMisaligned then
      begin
        DoError(AArg, PC_ERR_SEM_270, RSSemExprMisalignedVar, [LParam.ParamName, AArg.ExprText()]);
        Exit;
      end;
      if not LExactTaker and TPCScopes.Extends(AArg.ResolvedType, LTo, LHops) and
        DoPartMisaligned(AArg.ResolvedType, LHops) then
      begin
        DoError(AArg, PC_ERR_SEM_270, RSSemExprMisalignedUpcast,
          [AArg.ExprText(), LTo.TypeText(), AArg.ResolvedType.TypeText()]);
        Exit;
      end;
      Continue;
    end;
    if DoCppRefParam(LTo, LIsConst) then
    begin
      if LMisaligned and not LIsConst then
      begin
        DoError(AArg, PC_ERR_SEM_270, RSSemExprMisalignedRef, [LParam.ParamName, AArg.ExprText()]);
        Exit;
      end;
      LCopy := True;
      Continue;
    end;
    // The ranked overloads form (M12 (2) / M13): a record argument goes by
    // its address (::pcpp::argr / rank_value), a pointer is upcast inside
    // the ranking tags (ResolvedUpcastHops stays 0 there)
    if ACall.ResolvedRanksExtensions then
    begin
      if AArg.ResolvedType.Canon() is TPCRecordType then
        LCopy := True;
      LHops := DoUpcastHops(AArg.ResolvedType, LTo);
      if not LExactTaker and (LHops > 0) and DoPointerUpcastMisaligned(AArg.ResolvedType, LHops) then
      begin
        DoReportPointerUpcast(AArg, LTo);
        Exit;
      end;
    end;
    // const T& for anything but a scalar / pointer (the emitter's E10 rule)
    if (LParam.ParamMode = pmConst) and not LParam.TypeExpr.IsScalarOrPointer() then
      LCopy := True;
  end;
  if LMisaligned and LCopy then
    AArg.ResolvedIsCopied := True;
end;

procedure TPCSemantics.DoNoteMisalignedPrint(const ACall: TPCCall);
var
  LArg: TPCExpr;
begin
  // M8: print / println hand every argument to std::format by reference
  // (Args&&, print_map's const R&, the opaque check's const auto&): one that
  // may be misaligned is copied
  for LArg in ACall.Args do
  begin
    if DoMayBeMisaligned(LArg) then
      LArg.ResolvedIsCopied := True;
  end;
end;

procedure TPCSemantics.DoNoteMisalignedOperand(const AValue: TPCExpr);
begin
  // PLAN-RECORDS A8c (M8): an operand the emitted C++ binds to a const
  // reference or calls a member on: len's std::ssize, the runtime operators of
  // a static array (== <=>) and a set (| & - == <= >=, contains for `in`). One
  // that may sit misaligned is copied (the emitter's auto(x)). A scalar or a
  // pointer is loaded, never bound; a C/C++ operand's operator is C++'s, its
  // reference kind clang's (a copy could drop a write through a non-const one)
  if (AValue = nil) or (AValue.ResolvedType = nil) or DoIsPoisoned(AValue) then
    Exit;
  if AValue.ResolvedType.IsScalarOrPointer() or DoIsOpaqueTier(AValue.ResolvedType) then
    Exit;
  if DoMayBeMisaligned(AValue) then
    AValue.ResolvedIsCopied := True;
end;

function TPCSemantics.DoArgTypesText(const ACall: TPCCall): string;
var
  LArg: TPCExpr;
begin
  // The arguments' PaskalCPP types as SM0402 prints them: 'int32, string literal'
  Result := '';
  for LArg in ACall.Args do
  begin
    if Result <> '' then
      Result := Result + ', ';
    if (LArg <> nil) and (LArg.ResolvedType <> nil) then
      Result := Result + LArg.ResolvedType.TypeText()
    else
      Result := Result + '?';
  end;
end;

function TPCSemantics.DoParamTypesText(const ATarget: TPCCallTarget): string;
var
  LParam: TPCParam;
begin
  // A member's parameters as its note prints them: '(var int32; string; ...)',
  // the PaskalCPP spellings (TypeText), each with its mode
  Result := '';
  for LParam in ATarget.Params do
  begin
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + DoParamText(LParam);
  end;
  if ATarget.IsVariadic then
  begin
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + '...';
  end;
  Result := '(' + Result + ')';
end;

function TPCSemantics.DoParamText(const AParam: TPCParam): string;
begin
  // One parameter as a note prints it: its mode word and PaskalCPP type
  // ('var int32'); '?' for one the parser dropped
  if AParam = nil then
    Exit('?');
  Result := '';
  if AParam.ParamMode = pmVar then
    Result := 'var '
  else if AParam.ParamMode = pmConst then
    Result := 'const ';
  if AParam.TypeExpr <> nil then
    Result := Result + AParam.TypeExpr.TypeText()
  else
    Result := Result + '?';
end;

procedure TPCSemantics.DoPickOverload(const ACall: TPCCall; const ATargets: TList<TPCCallTarget>);
var
  LTaken: TList<TPCCallTarget>;
  LTarget: TPCCallTarget;
  LRanks: Boolean;
begin
  // F18 (user 2026-10-12: validate overloads from the AST): a call to an
  // overload set considers only the members that take its arguments by
  // PaskalCPP's conversions (DoTargetTakes); which of them is called stays
  // clang's (C++ ranking). None = SM0402 at the call, every member a note,
  // the call poisoned. One = bound and checked as a lone routine. Fewer than
  // all = written on the call (TPCCall.ResolvedCandidates): the emitter
  // calls through exactly those, so clang never sees a member PaskalCPP
  // rejects (C++ ranks pointer -> bool above -> std::string: Kind("lit")
  // would call Kind(bool) silently). Every member = no limit, unless they
  // rank by extension (DoTakesAtBase)
  LTaken := TList<TPCCallTarget>.Create();
  try
    for LTarget in ATargets do
    begin
      // A member with no declaration (a routine value) is never in a set
      if LTarget.Decl = nil then
      begin
        DoOverloadSetType(ACall, ATargets);
        Exit;
      end;
      if DoTargetTakes(ACall, LTarget) then
        LTaken.Add(LTarget);
    end;
    if LTaken.Count = 0 then
    begin
      if DoError(ACall, PC_ERR_SEM_402, RSSemCallOverloadNone, [DoCalleeText(ACall), DoArgTypesText(ACall)]) then
      begin
        for LTarget in ATargets do
          DoNote(LTarget.Decl, RSSemCallOverloadMember, [DoCalleeText(ACall), DoParamTypesText(LTarget)]);
      end;
      DoPoison(ACall);
      Exit;
    end;
    // M12 (2) / M13: members that take an argument at a base level are
    // ranked by clang through tags: every accepted member is written
    LRanks := (LTaken.Count > 1) and DoTakesAtBase(ACall, LTaken);
    ACall.ResolvedRanksExtensions := LRanks;
    if (LTaken.Count < ATargets.Count) or LRanks then
    begin
      for LTarget in LTaken do
        ACall.ResolvedCandidates.Add(LTarget.Decl);
    end;
    if LTaken.Count = 1 then
    begin
      DoBindTarget(ACall, LTaken[0]);
      DoCheckArgs(ACall, LTaken[0]);
      Exit;
    end;
    // PLAN-RECORDS M8: every accepted member binds as its parameters do
    DoNoteMisalignedArgs(ACall, LTaken);
    DoOverloadSetType(ACall, LTaken);
  finally
    LTaken.Free();
  end;
end;

procedure TPCSemantics.DoOverloadSetType(const ACall: TPCCall; const ATargets: TList<TPCCallTarget>);
var
  LIndex: Integer;
  LFirst: TPCTypeExpr;
  LOther: TPCTypeExpr;
begin
  // An overload set: clang picks the member (no ResolvedDecl). The call's
  // value is the members' one return type, void when none returns, else opaque
  LFirst := ATargets[0].ReturnType;
  for LIndex := 1 to ATargets.Count - 1 do
  begin
    LOther := ATargets[LIndex].ReturnType;
    if ((LFirst = nil) <> (LOther = nil)) or ((LFirst <> nil) and not DoSameType(LFirst, LOther)) then
    begin
      ACall.ResolvedType := FAst.OpaqueType();
      Exit;
    end;
  end;
  if LFirst = nil then
    ACall.ResolvedType := FAst.VoidType()
  else
    ACall.ResolvedType := DoValueTypeOf(LFirst);
end;

procedure TPCSemantics.DoTypeCall(const ACall: TPCCall);
var
  LDecl: TPCTypeDecl;
  LArg: TPCExpr;
begin
  // `TAlias(LX)`: a cast to a PaskalCPP type (calls.md Q9) takes one
  // argument; its legality is C++'s (clang judges the emitted cast)
  if not (ACall.ResolvedDecl is TPCTypeDecl) then
    Exit;
  LDecl := TPCTypeDecl(ACall.ResolvedDecl);
  if LDecl.IsForward and (LDecl.ResolvedFull <> nil) then
    LDecl := LDecl.ResolvedFull;
  if ACall.Args.Count <> 1 then
  begin
    DoError(ACall, PC_ERR_SEM_412, RSSemCallCastArgs, [DoCalleeText(ACall), ACall.Args.Count]);
    DoPoison(ACall);
    Exit;
  end;
  ACall.ResolvedType := DoNamedTypeOf(LDecl);
  LArg := ACall.Args[0];
  if DoNotValue(LArg) then
    Exit;
  if (LArg = nil) or DoIsPoisoned(LArg) or (LArg.ResolvedType = nil) then
    Exit;
  ACall.IsConstExpr := LArg.IsConstExpr or DoIsOpaqueTier(LArg.ResolvedType);
  // A conversion of a folded constant to an integer-family alias folds (F27)
  DoFoldConversion(ACall, LArg, ACall.ResolvedType);
end;

function TPCSemantics.DoIntrinsicValueType(const AValue: TPCIntrinsicValue): TPCTypeExpr;
begin
  // The type an intrinsic call has (semantics.md :194-206); getmem and
  // resizemem give an untyped ptr, the shared node of the AST
  case AValue of
    ivStatement:
      Result := FAst.VoidType();
    ivInt32:
      Result := FAst.BuiltinType(tkKwInt32);
    ivInt64:
      Result := FAst.BuiltinType(tkKwInt64);
    ivString:
      Result := FAst.BuiltinType(tkKwString);
    ivPointer:
      Result := FAst.UntypedPointerType();
    ivBool:
      Result := FAst.BuiltinType(tkKwBool);
    ivLocked:
      // typed from the weak argument once it fits (DoIntrinsic); opaque until then
      Result := FAst.OpaqueType();
  else
    Result := nil;
  end;
end;

function TPCSemantics.DoIntrinsicArgFits(const AArg: TPCExpr; const AClass: TPCIntrinsicArg): Boolean;
var
  LType: TPCTypeExpr;
  LCanon: TPCTypeExpr;
  LTarget: TPCTypeExpr;
  LToken: TPCTokenKind;
begin
  // One argument against its class (TPCIntrinsicArg). An opaque or an
  // untyped argument is clang's (C3): it fits
  LType := AArg.ResolvedType;
  if (LType = nil) or DoIsOpaqueTier(LType) then
    Exit(True);
  LCanon := LType.Canon();
  case AClass of
    iaLength:
      Result := (LCanon is TPCStringLiteralType) or (LCanon is TPCArrayType) or
        (DoBuiltinOf(LCanon, LToken) and ((LToken = tkKwString) or (LToken = tkKwWstring)));
    iaWString:
      Result := DoConvertsImplicitly(AArg, FAst.BuiltinType(tkKwWstring));
    iaString:
      Result := DoConvertsImplicitly(AArg, FAst.BuiltinType(tkKwString));
    iaBool:
      Result := DoConvertsImplicitly(AArg, FAst.BuiltinType(tkKwBool));
    iaInt32:
      Result := DoConvertsImplicitly(AArg, FAst.BuiltinType(tkKwInt32));
    iaInt64:
      Result := DoConvertsImplicitly(AArg, FAst.BuiltinType(tkKwInt64));
    iaUInt64:
      Result := DoConvertsImplicitly(AArg, FAst.BuiltinType(tkKwUint64));
    iaFloat64:
      Result := DoConvertsImplicitly(AArg, FAst.BuiltinType(tkKwFloat64));
    iaPointer:
      Result := DoConvertsImplicitly(AArg, FAst.UntypedPointerType());
    iaResizable:
      begin
        Result := ((LCanon is TPCArrayType) and TPCArrayType(LCanon).IsDynamic) or
          (DoBuiltinOf(LCanon, LToken) and ((LToken = tkKwString) or (LToken = tkKwWstring)));
        Result := Result and DoIsAssignable(AArg);
      end;
    iaHeapPtrVar:
      Result := (TPCTypeExpr.HeapTargetOf(LType, LTarget) <> htNone) and DoIsAssignable(AArg);
    iaHeapPtr:
      Result := TPCTypeExpr.HeapTargetOf(LType, LTarget) <> htNone;
    iaWeak:
      Result := (LCanon is TPCOwnerType) and (TPCOwnerType(LCanon).OwnerKind = okWeak);
  else
    Result := False;
  end;
end;

procedure TPCSemantics.DoReportIntrinsicSig(const ACall: TPCCall; const AAt: TPCNode);
begin
  // SM0409 at the argument that does not fit, or at the call for a wrong
  // count; the call is poisoned (C1)
  DoError(AAt, PC_ERR_SEM_409, RSSemCallIntrinsicSig,
    [PC_INTRINSIC_NAMES[ACall.IntrinsicKind], TPCIntrinsicSigs.SigText(ACall.IntrinsicKind)]);
  DoPoison(ACall);
end;

procedure TPCSemantics.DoSizeCall(const ACall: TPCCall);
var
  LArg: TPCExpr;
  LKind: TPCResolvedKind;
begin
  // size(T) -> int64 (semantics.md :195-197): the TypeArg, or the one
  // argument when it names a type (rkType; rkOpaque is clang's). Its value
  // is C++'s sizeof: a constant clang computes, never PaskalCPP. The
  // argument is no value position: DoNotValue never asks
  if ACall.Args.Count + Ord(ACall.TypeArg <> nil) <> 1 then
  begin
    DoReportIntrinsicSig(ACall, ACall);
    Exit;
  end;
  ACall.ResolvedType := FAst.BuiltinType(tkKwInt64);
  ACall.IsConstExpr := True;
  if ACall.TypeArg <> nil then
    Exit;
  LArg := ACall.Args[0];
  // A reported argument: the call keeps its type and stays a constant (C1)
  if (LArg = nil) or DoIsPoisoned(LArg) then
    Exit;
  LKind := rkNone;
  if LArg is TPCName then
    LKind := TPCName(LArg).ResolvedKind
  else if LArg is TPCMember then
    LKind := TPCMember(LArg).ResolvedKind;
  if (LKind <> rkType) and (LKind <> rkOpaque) then
  begin
    DoError(LArg, PC_ERR_SEM_410, RSSemCallSizeValue, [LArg.ExprText()]);
    DoPoison(ACall);
  end;
end;

procedure TPCSemantics.DoIntrinsic(const ACall: TPCCall);
var
  LSig: TPCIntrinsicSig;
  LIndex: Integer;
  LText: string;
  LTarget: TPCTypeExpr;
  LLocked: TPCOwnerType;
begin
  // calls.md intrinsics (semantics.md :194-209): the PC_INTRINSIC_SIGS row,
  // then the value type. A statement-only intrinsic is typed VoidType, so
  // DoNotValue reports it where a value is consumed (SM0408)
  if ACall.IntrinsicKind = ikNone then
    Exit;
  // exccode / excmsg read the exception an except list handles
  // (statements.md :152-153): an except list on the context stack
  if ((ACall.IntrinsicKind = ikExcCode) or (ACall.IntrinsicKind = ikExcMsg)) and not DoInFlow(fwExcept) then
    DoError(ACall, PC_ERR_SEM_615, RSSemStmtExcOutside, [DoCalleeText(ACall)]);
  // Of the intrinsics only size gets a TypeArg: the parser makes one for the
  // name size alone (TPCParser.DoTypeArgSlot)
  if ACall.IntrinsicKind = ikSize then
  begin
    DoSizeCall(ACall);
    Exit;
  end;
  LSig := PC_INTRINSIC_SIGS[ACall.IntrinsicKind];
  ACall.ResolvedType := DoIntrinsicValueType(LSig.Value);
  // print / println are std::print / std::println: their format string is
  // C++'s (clang checks it at compile time). Every argument after the format
  // prints by its type (TPCTypeExpr.PrintFormOfArg, PLAN-PASKAL-ERRORS E7):
  // a record, object or overlay, or an array of one, has no form, nor has a
  // routine name with no single address (an overload set, a method): SM0425
  // at the argument (a poisoned argument was reported already)
  if (ACall.IntrinsicKind = ikPrint) or (ACall.IntrinsicKind = ikPrintLn) then
  begin
    for LIndex := 1 to ACall.Args.Count - 1 do
    begin
      if DoIsPoisoned(ACall.Args[LIndex]) then
        Continue;
      LText := UnprintableArgText(ACall.Args[LIndex]);
      if LText <> '' then
        DoError(ACall.Args[LIndex], PC_ERR_SEM_425, '%s', [LText]);
    end;
    // PLAN-RECORDS M8: std::format takes its arguments by reference
    DoNoteMisalignedPrint(ACall);
    Exit;
  end;
  // A reported argument: no verdict from it (C1); the call keeps its type
  if not DoArgsReady(ACall) then
    Exit;
  if ACall.Args.Count <> LSig.ArgCount then
  begin
    DoReportIntrinsicSig(ACall, ACall);
    Exit;
  end;
  for LIndex := 0 to ACall.Args.Count - 1 do
  begin
    if not DoIntrinsicArgFits(ACall.Args[LIndex], LSig.Args[LIndex]) then
    begin
      DoReportIntrinsicSig(ACall, ACall.Args[LIndex]);
      Exit;
    end;
  end;
  // PLAN-RECORDS A8c (M8): len is std::ssize, which binds its argument to a
  // const reference
  if ACall.IntrinsicKind = ikLen then
    DoNoteMisalignedOperand(ACall.Args[0]);
  // PLAN-OBJECT O6 (Q3): lock(W) is a ref T to the object W watches (nil
  // when it is gone): a ref type SEM builds from the weak's object type
  if (ACall.IntrinsicKind = ikLock) and (ACall.Args[0].ResolvedType <> nil) and
    (ACall.Args[0].ResolvedType.Canon() is TPCOwnerType) then
  begin
    LLocked := FAst.NewNode<TPCOwnerType>();
    LLocked.OwnerKind := okRef;
    LLocked.TargetType := TPCOwnerType(ACall.Args[0].ResolvedType.Canon()).TargetType;
    ACall.ResolvedType := LLocked;
  end;
  // PLAN-OBJECT O6 (D4): create / destroy are retired for objects: an object
  // on the heap is held by an own / ref, which frees it (SM0361 at the
  // argument, naming the replacement). A record, overlay or C/C++ pointer
  // stays theirs (TPCTypeExpr.HeapTargetOf, F36)
  if ((ACall.IntrinsicKind = ikCreate) or (ACall.IntrinsicKind = ikDestroy)) and
    (TPCTypeExpr.HeapTargetOf(ACall.Args[0].ResolvedType, LTarget) = htObject) then
  begin
    if ACall.IntrinsicKind = ikCreate then
      DoError(ACall.Args[0], PC_ERR_SEM_361, RSSemCallCreateObject,
        [LTarget.TypeText(), LTarget.TypeText(), LTarget.TypeText()])
    else
      DoError(ACall.Args[0], PC_ERR_SEM_361, RSSemCallDestroyObject, [LTarget.TypeText()]);
    DoPoison(ACall);
  end;
end;

function TPCSemantics.DoIsVarargsReceiver(const ACall: TPCCall): Boolean;
var
  LToken: TPCTokenKind;
begin
  // `LVa.next(T)` / `LVa.get(I, T)` on a varargs local (Q30,
  // varargs-forms.md F-R2): its type argument is A6d's
  Result := (ACall.Callee is TPCMember) and (TPCMember(ACall.Callee).Base <> nil) and
    DoBuiltinOf(TPCMember(ACall.Callee).Base.ResolvedType, LToken) and (LToken = tkKwVarargs);
end;

procedure TPCSemantics.DoTypeArgCall(const ACall: TPCCall);
begin
  // A type argument on a call that is no intrinsic (calls.md :226-228):
  // SM0411 (a varargs local's next / get never comes here: DoCall gives it
  // to DoVarargsLocalCall), except an opaque callee (a C/C++ macro may take
  // a type: clang's, DESIGN.md sec 2)
  if (ACall.ResolvedKind = rkOpaque) or
    ((ACall.Callee.ResolvedType <> nil) and DoIsOpaqueTier(ACall.Callee.ResolvedType)) then
  begin
    ACall.ResolvedType := FAst.OpaqueType();
    Exit;
  end;
  DoError(ACall.TypeArg, PC_ERR_SEM_411, RSSemCallTypeArg, [DoCalleeText(ACall)]);
  DoPoison(ACall);
end;

function TPCSemantics.DoIsVarargsCopy(const AExpr: TPCExpr): Boolean;
begin
  // varargs.copy() or LOther.copy() on a varargs local: what sets a varargs
  // local (Q30). A reported value is not judged (C1)
  if (AExpr = nil) or DoIsPoisoned(AExpr) then
    Exit(True);
  if AExpr is TPCVarargs then
    Exit(TPCVarargs(AExpr).VarargsKind = vaCopy);
  Result := (AExpr is TPCCall) and DoIsVarargsReceiver(TPCCall(AExpr)) and
    (TPCMember(TPCCall(AExpr).Callee).Member <> nil) and
    (TPCMember(TPCCall(AExpr).Callee).Member.PartText = PC_VARARGS_WORDS[vaCopy]);
end;

procedure TPCSemantics.DoVarargsExpr(const AVarargs: TPCVarargs);
begin
  // BNF.md sec 6, Q30: varargs is the pack of the variadic routine being
  // checked (SM0417); always a member, never a value (SM0421); a clink
  // variadic gets only the unchecked next(T): a C caller passes no types or
  // count (SM0418). count -> int32, next(T) / get(I, T) -> T with an
  // integer index, reset() -> nothing, copy() -> varargs
  DoNodeChildren(AVarargs);
  if (FRoutine = nil) or not FRoutine.IsVariadic then
  begin
    DoError(AVarargs, PC_ERR_SEM_417, RSSemCallVarargsOutside, [PC_VARARGS_WORDS[vaPlain]]);
    DoPoison(AVarargs);
    Exit;
  end;
  if AVarargs.VarargsKind = vaPlain then
  begin
    // The words come from the one table (PC_VARARGS_WORDS)
    DoError(AVarargs, PC_ERR_SEM_421, RSSemCallVarargsValue, [PC_VARARGS_WORDS[vaPlain],
      PC_VARARGS_WORDS[vaPlain], PC_VARARGS_WORDS[vaCount], PC_VARARGS_WORDS[vaNext],
      PC_VARARGS_WORDS[vaGet], PC_VARARGS_WORDS[vaReset], PC_VARARGS_WORDS[vaCopy]]);
    DoPoison(AVarargs);
    Exit;
  end;
  if (FRoutine.ResolvedLinkage = lnC) and (AVarargs.VarargsKind <> vaNext) then
  begin
    DoError(AVarargs, PC_ERR_SEM_418, RSSemCallVarargsClink, [PC_VARARGS_WORDS[vaPlain],
      PC_VARARGS_WORDS[AVarargs.VarargsKind]]);
    DoPoison(AVarargs);
    Exit;
  end;
  case AVarargs.VarargsKind of
    vaCount:
      AVarargs.ResolvedType := FAst.BuiltinType(tkKwInt32);
    vaNext:
      AVarargs.ResolvedType := DoValueTypeOf(AVarargs.ReadType);
    vaGet:
      begin
        DoCheckConvert(AVarargs.IndexExpr, FAst.BuiltinType(tkKwInt32));
        AVarargs.ResolvedType := DoValueTypeOf(AVarargs.ReadType);
      end;
    vaReset:
      AVarargs.ResolvedType := FAst.VoidType();
    vaCopy:
      AVarargs.ResolvedType := FAst.BuiltinType(tkKwVarargs);
  end;
end;

function TPCSemantics.DoReadType(const ACall: TPCCall; const ASlot: Integer; out AType: TPCTypeExpr): Boolean;
var
  LArg: TPCExpr;
  LKind: TPCResolvedKind;
  LDecl: TPCNode;
begin
  // The type a varargs local's next / get reads (varargs-forms.md F-R2): the
  // TypeArg at its slot, or the argument at the slot naming a type (a C/C++
  // type is clang's). False = the call has another shape
  AType := nil;
  if ACall.TypeArg <> nil then
  begin
    if (ACall.TypeArgIndex <> ASlot) or (ACall.Args.Count <> ASlot) then
      Exit(False);
    AType := DoValueTypeOf(ACall.TypeArg);
    Exit(True);
  end;
  if ACall.Args.Count <> ASlot + 1 then
    Exit(False);
  LArg := ACall.Args[ASlot];
  if (LArg = nil) or DoIsPoisoned(LArg) then
  begin
    AType := FAst.ErrorType();
    Exit(True);
  end;
  LKind := rkNone;
  LDecl := nil;
  if LArg is TPCName then
  begin
    LKind := TPCName(LArg).ResolvedKind;
    LDecl := TPCName(LArg).ResolvedDecl;
  end
  else if LArg is TPCMember then
  begin
    LKind := TPCMember(LArg).ResolvedKind;
    LDecl := TPCMember(LArg).ResolvedDecl;
  end;
  if LKind = rkOpaque then
  begin
    AType := FAst.OpaqueType();
    Exit(True);
  end;
  if (LKind <> rkType) or not (LDecl is TPCTypeDecl) then
    Exit(False);
  AType := DoNamedTypeOf(TPCTypeDecl(LDecl));
  Result := True;
end;

procedure TPCSemantics.DoVarargsLocalCall(const ACall: TPCCall);
var
  LWord: string;
  LType: TPCTypeExpr;
begin
  // A member call on a varargs local: the members of varargs (BNF.md sec
  // 6), same types; a call of another shape takes the member's signature
  // (SM0409). An unknown member was SM0009 (DoValueMember)
  LWord := TPCMember(ACall.Callee).Member.PartText;
  if LWord = PC_VARARGS_WORDS[vaNext] then
  begin
    if DoReadType(ACall, 0, LType) then
      ACall.ResolvedType := LType
    else
      DoError(ACall, PC_ERR_SEM_409, RSSemCallIntrinsicSig, [DoCalleeText(ACall), RSAstSigType]);
  end
  else if LWord = PC_VARARGS_WORDS[vaGet] then
  begin
    if DoReadType(ACall, 1, LType) then
    begin
      DoCheckConvert(ACall.Args[0], FAst.BuiltinType(tkKwInt32));
      ACall.ResolvedType := LType;
    end
    else
      DoError(ACall, PC_ERR_SEM_409, RSSemCallIntrinsicSig, [DoCalleeText(ACall), RSAstSigIndexType]);
  end
  else if (ACall.Args.Count <> 0) or (ACall.TypeArg <> nil) then
    DoError(ACall, PC_ERR_SEM_409, RSSemCallIntrinsicSig, [DoCalleeText(ACall), RSAstSigNone])
  else if LWord = PC_VARARGS_WORDS[vaCopy] then
    ACall.ResolvedType := FAst.BuiltinType(tkKwVarargs)
  else
    ACall.ResolvedType := FAst.VoidType();
  if ACall.ResolvedType = nil then
    DoPoison(ACall);
end;

procedure TPCSemantics.DoVarDeclStmt(const ADecl: TPCVarDecl);
var
  LLocal: Boolean;
begin
  // A local of a variadic routine may be of type varargs (written as the
  // word itself), set only from a copy (Q30, SM0422); every other varargs
  // type is SM0422 in DoTypeExpr
  LLocal := (FRoutine <> nil) and FRoutine.IsVariadic and (ADecl.TypeExpr is TPCBuiltinType) and
    (TPCBuiltinType(ADecl.TypeExpr).BuiltinToken = tkKwVarargs);
  if LLocal then
    FVarargsLocal := ADecl.TypeExpr;
  try
    DoTypeExpr(ADecl.TypeExpr);
  finally
    FVarargsLocal := nil;
  end;
  // PLAN-OBJECT D3 / Q1: the init the variable is built with
  DoConstruct(ADecl);
  DoExpr(ADecl.InitExpr);
  if LLocal and (ADecl.InitExpr <> nil) and not DoIsVarargsCopy(ADecl.InitExpr) then
    DoError(ADecl.InitExpr, PC_ERR_SEM_422, RSSemCallVarargsType, [PC_VARARGS_WORDS[vaPlain], PC_VARARGS_WORDS[vaCopy]])
  else
    DoCheckConvert(ADecl.InitExpr, ADecl.TypeExpr);
  DoCheckVarDecl(ADecl);
end;

procedure TPCSemantics.DoCall(const ACall: TPCCall);
var
  LTargets: TList<TPCCallTarget>;
  LType: TPCTypeExpr;
begin
  // R-CALLEE: what the callee is decides the rules (calls.md "Callee kinds")
  if (ACall.Callee = nil) or DoIsPoisoned(ACall) then
    Exit;
  ACall.ResolvedInTest := DoInTest();
  if DoIsPoisoned(ACall.Callee) then
    Exit;
  // SM0424, its one reporter: count is no call (BNF.md sec 6), written on
  // varargs or on a varargs local (TPCMember.ResolvedVarargs, DoValueMember);
  // left alone it reaches clang as a call of an int32
  if ((ACall.Callee is TPCVarargs) and (TPCVarargs(ACall.Callee).VarargsKind = vaCount)) or
    ((ACall.Callee is TPCMember) and (TPCMember(ACall.Callee).ResolvedVarargs = vaCount)) then
  begin
    DoError(ACall, PC_ERR_SEM_424, RSSemCallVarargsCountCall, [DoCalleeText(ACall)]);
    DoPoison(ACall);
    Exit;
  end;
  // A member call on a varargs local: the varargs members (its type argument included)
  if DoIsVarargsReceiver(ACall) then
  begin
    DoVarargsLocalCall(ACall);
    Exit;
  end;
  if ACall.ResolvedKind = rkIntrinsic then
  begin
    DoIntrinsic(ACall);
    Exit;
  end;
  if ACall.TypeArg <> nil then
  begin
    DoTypeArgCall(ACall);
    Exit;
  end;
  if ACall.ResolvedKind = rkOpaque then
  begin
    ACall.ResolvedType := FAst.OpaqueType();
    Exit;
  end;
  if ACall.ResolvedKind = rkType then
  begin
    DoTypeCall(ACall);
    Exit;
  end;
  // A module is no value, so no callee either (SM0269)
  if ACall.ResolvedKind = rkModule then
  begin
    DoError(ACall, PC_ERR_SEM_269, RSSemTypeModuleNotValue, [DoCalleeText(ACall)]);
    DoPoison(ACall);
    Exit;
  end;
  LTargets := TList<TPCCallTarget>.Create();
  try
    if ACall.ResolvedKind = rkRoutine then
      DoCallCandidates(ACall, LTargets)
    else
    begin
      // A value: callable only through a routine type (no overloads)
      LType := ACall.Callee.ResolvedType;
      if LType = nil then
        Exit;
      if DoIsErrorType(LType) then
      begin
        DoPoison(ACall);
        Exit;
      end;
      if DoIsOpaqueTier(LType) then
      begin
        ACall.ResolvedType := FAst.OpaqueType();
        Exit;
      end;
      // F58 (expr_call_member, DESIGN sec 5): any other PaskalCPP value is
      // no routine: SM0400 at the call (it was typed opaque and reached clang
      // in C++ words). A record / object whose chain reaches
      // a C/C++ parent may take a C++ operator() from it: clang's, as its
      // members are (F20)
      if not (LType.Canon() is TPCRoutineType) then
      begin
        if (LType.Canon() is TPCRecordType) and TPCScopes.ReachesOpaque(LType.Canon()) then
        begin
          ACall.ResolvedType := FAst.OpaqueType();
          Exit;
        end;
        DoError(ACall, PC_ERR_SEM_400, RSSemCallNotCallable, [DoCalleeText(ACall), LType.TypeText()]);
        DoPoison(ACall);
        Exit;
      end;
      LTargets.Add(DoTypeTarget(TPCRoutineType(LType.Canon())));
    end;
    // A routine the parser could not finish is never judged against: the
    // call keeps its resolution, poisoned (PLAN-RECOVERY)
    if DoHasRecoveredTarget(LTargets) then
    begin
      DoPoison(ACall);
      Exit;
    end;
    if not DoArgsReady(ACall) then
    begin
      // A reported argument: no pick from it (C1); one candidate still types the call
      if LTargets.Count = 1 then
        DoBindTarget(ACall, LTargets[0])
      else
        DoPoison(ACall);
      Exit;
    end;
    DoPickTarget(ACall, LTargets);
  finally
    LTargets.Free();
  end;
end;

end.
