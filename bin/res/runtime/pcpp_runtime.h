/*******************************************************************************
 * PaskalCPP™ Programming Language
 *
 * Copyright © 2026-present tinyBigGAMES™ LLC
 * All Rights Reserved.
 *
 * https://paskalcpp.org
 *
 * SPDX-License-Identifier: MPL-2.0 WITH AdditionRef-PaskalCPP-Runtime-Exception
 *
 * This Source Code Form is subject to the terms of the
 * Mozilla Public License, v. 2.0. If a copy of the MPL
 * was not distributed with this file, You can obtain one
 * at https://mozilla.org/MPL/2.0/.
 *
 * This file is covered by the PaskalCPP Runtime Exception
 * (RUNTIME-EXCEPTION.md).
 *
 * ---
 * pcpp_runtime.h - PaskalCPP C++ Runtime
 *
 * The runtime the emitted C++ calls. Every name lives in namespace pcpp
 * (the API: research\runtime\api.md); pcpp_runtime.cpp is its one TU.
 ******************************************************************************/

#pragma once

#include <array>
#include <bit>
#include <compare>
#include <cstdarg>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <format>
#include <iterator>
#include <limits>
#include <memory>
#include <new>
#include <optional>
#include <print>
#include <stdexcept>
#include <string>
#include <string_view>
#include <tuple>
#include <type_traits>
#include <utility>
#include <vector>

// The export attribute of a dll / shared object build (PCPP_BUILD_DLL); empty
// otherwise
#if defined(PCPP_BUILD_DLL)
    #if defined(_WIN32)
        #define PCPP_EXPORT __declspec(dllexport)
    #else
        #define PCPP_EXPORT __attribute__((visibility("default")))
    #endif
#else
    #define PCPP_EXPORT
#endif

namespace pcpp {

/*******************************************************************************
 * Startup
 ******************************************************************************/

// Installs the fault handler, the console and the terminate handler once;
// stores the arguments only when argv is not nullptr (a lib's constructor
// calls init(0, nullptr) before main's init(argc, argv))
void init(int argc, char** argv);

// Runs AEntry (an entry into PaskalCPP code from outside: the emitted main
// and dll / lib hooks) and returns its result; an unhandled raise or C++
// exception out of it is reported (`unhandled exception <code>: <text>`)
// and ends the process with exit code 1, debugged or not
std::int32_t enter(std::int32_t (*AEntry)()) noexcept;

// The number of program arguments (argc - 1, 0 when none)
std::int32_t param_count();

// Argument index (0 = the program); "" out of range
std::string param_str(std::int32_t index);

/*******************************************************************************
 * Exceptions
 ******************************************************************************/

inline constexpr std::int32_t EXC_NONE = 0;
inline constexpr std::int32_t EXC_SOFTWARE = 1;
inline constexpr std::int32_t EXC_DIV_BY_ZERO = 2;
inline constexpr std::int32_t EXC_ACCESS_VIOLATION = 3;
inline constexpr std::int32_t EXC_STACK_OVERFLOW = 4;
inline constexpr std::int32_t EXC_INTEGER_OVERFLOW = 5;
inline constexpr std::int32_t EXC_ILLEGAL_INSTRUCTION = 6;
inline constexpr std::int32_t EXC_BUS_ERROR = 7;
inline constexpr std::int32_t EXC_VARARGS_TYPE = 8;
inline constexpr std::int32_t EXC_VARARGS_INDEX = 9;
inline constexpr std::int32_t EXC_CPP = 10;
inline constexpr std::int32_t EXC_SET_RANGE = 11;
inline constexpr std::int32_t EXC_MEMORY = 12;
inline constexpr std::int32_t EXC_INVALID_CAST = 13;
inline constexpr std::int32_t EXC_UNKNOWN = 99;

// Throws the runtime's exception; its text is copied and travels with it
[[noreturn]] void raise(std::int32_t code, const std::string& msg);

// The last exception a guard of this thread caught (0 / "" before any)
std::int32_t exc_code();
std::string exc_msg();

namespace detail {

// Runs fn(context) under the hardware fault handler and a catch of every C++
// exception. Returns 0 when nothing was caught, 1 when anything was (the
// code and text are then exc_code() / exc_msg()). One non-template routine:
// the fault handler jumps back into its frame
std::int32_t guard_call(void (*fn)(void*), void* context);

} // namespace detail

// Runs body; 0 = nothing caught, 1 = a raise, a C++ exception or a hardware
// fault was caught (a raise with code 0 is still caught)
template <class F>
std::int32_t guard(F&& body) {
    using LBody = std::remove_reference_t<F>;
    void* LContext = const_cast<void*>(static_cast<const volatile void*>(std::addressof(body)));
    return detail::guard_call(
        [](void* AContext) {
            (*static_cast<LBody*>(AContext))();
        },
        LContext);
}

// The except part of a guard that has a finally: except_fn, then finally_fn
// on every path. A raise from except_fn propagates after finally_fn ran; a
// raise from finally_fn replaces one from except_fn
template <class E, class F>
void guard_finally(E&& except_fn, F&& finally_fn) {
    try {
        except_fn();
    }
    catch (...) {
        finally_fn();
        throw;
    }
    finally_fn();
}

// What a guard with no except caught, kept across its finally (a guard in the
// finally overwrites exc_code / exc_msg); pass_on raises it again after the
// finally, so a finally never hides a raise
class Caught {
public:
    // caught = guard's result: nonzero takes what this thread's last guard
    // caught, 0 an empty Caught
    static Caught take(std::int32_t caught);
    // Nothing when empty; else raises it again: the same exception object (a
    // raise keeps its code and text, a C++ exception its type), a hardware
    // fault as a raise of its code and text
    void pass_on() const;

private:
    bool FCaught = false;
    std::exception_ptr FObject;
    std::int32_t FCode = 0;
    std::string FText;
};

// How a flow leaves a guard's lambda (return / leave / skip), dispatched
// after the guard
enum class Flow { None, Return, Leave, Skip };

// Scope guard: runs the callable when the scope ends (va_end); the callable
// must not raise
template <class F>
class Finally {
public:
    explicit Finally(F fn) noexcept(std::is_nothrow_move_constructible_v<F>)
        : FFn(std::move(fn)) {
    }

    Finally(const Finally&) = delete;
    Finally& operator=(const Finally&) = delete;

    ~Finally() {
        FFn();
    }

private:
    F FFn;
};

// PLAN-OBJECT O5 (D5): the member every object that declares a done holds,
// pcpp_live. A move leaves the source not live, so its done does not run
// on what moved out (the destination's does); a fresh object is live. Its
// moves are the object's (defaulted moves move it); a copy is a new, live
// object (the object's own copy builds it)
class Live {
public:
    Live() noexcept = default;
    Live(const Live&) noexcept {
    }
    Live(Live&& other) noexcept : FLive(other.FLive) {
        other.FLive = false;
    }
    Live& operator=(const Live&) noexcept {
        return *this;
    }
    Live& operator=(Live&& other) noexcept {
        FLive = other.FLive;
        other.FLive = false;
        return *this;
    }
    friend void swap(Live& a, Live& b) noexcept {
        bool tmp = a.FLive;
        a.FLive = b.FLive;
        b.FLive = tmp;
    }
    explicit operator bool() const noexcept {
        return FLive;
    }

private:
    bool FLive = true;
};

/*******************************************************************************
 * Memory. In a debug build (PCPP_DEBUG) every block get_mem / resize_mem
 * hands out and every block free_mem / resize_mem(p, 0) releases is counted;
 * at shutdown (an exe or lib: after main's finalizers; a dll: after
 * pcpp_dll_finalize) the runtime prints
 *   [Heap] Allocs: <n>, Frees: <n>, Leaked: <n>
 ******************************************************************************/

// size 0 = nullptr; a negative size or an allocation that fails raises
// EXC_MEMORY
void* get_mem(std::int64_t size);

// A negative size or a reallocation that fails raises EXC_MEMORY (p is then
// untouched); size 0 frees p and returns nullptr
void* resize_mem(void* p, std::int64_t size);

void free_mem(void* p);

namespace detail {
// Raises EXC_MEMORY for setlength: "negative length N", or "out of memory
// (length N)" when the container cannot hold N
[[noreturn]] void raise_length(std::int64_t length, bool negative);
} // namespace detail

// setlength(v, n) (PLAN-INTRINSICS I2): the new length of a dynamic array
// (std::vector) or a string (std::string / std::wstring), added elements
// value-initialized. A negative n raises EXC_MEMORY, as get_mem's negative
// size does, and so does a length the container cannot hold (its
// length_error / bad_alloc); v is then untouched. An element type's own
// exception passes through as it is
template <typename T>
void set_length(T& v, const std::int64_t length) {
    if (length < 0) {
        detail::raise_length(length, true);
    }
    try {
        v.resize(static_cast<typename T::size_type>(length));
    } catch (const std::length_error&) {
        detail::raise_length(length, false);
    } catch (const std::bad_alloc&) {
        detail::raise_length(length, false);
    }
}

/*******************************************************************************
 * Owners (PLAN-OBJECT O6, D4): own T / ref T / weak T are Own<T> / Ref<T> /
 * Weak<T>. make_own / make_ref build the object on the heap; in a debug build
 * each object counts in the [Heap] report as a block, and one still alive at
 * shutdown adds `[Heap] Leaked object created at <file>(<line>)` (its
 * creation site). Access through a nil own / ref raises EXC_ACCESS_VIOLATION
 ******************************************************************************/

// Debug build: an object built at file(line) (counted as an alloc) / released
// (counted as a free; an address never tracked counts nothing). Release
// builds: nothing
void track_object(const void* p, const char* file, std::int32_t line) noexcept;
void untrack_object(const void* p) noexcept;

// The deleter of every owner: releases the object (its done runs) and tracks
// the release at the most derived object's address
struct OwnDelete {
    template <class T>
    void operator()(T* p) const noexcept {
        if constexpr (std::is_polymorphic_v<T>) {
            untrack_object(dynamic_cast<const void*>(p));
        } else {
            untrack_object(static_cast<const void*>(p));
        }
        delete p;
    }
};

template <class T>
using Own = std::unique_ptr<T, OwnDelete>;

template <class T>
using Ref = std::shared_ptr<T>;

template <class T>
using Weak = std::weak_ptr<T>;

template <class T, class... A>
Own<T> make_own(const char* file, std::int32_t line, A&&... args) {
    T* LObject = new T(std::forward<A>(args)...);
    track_object(LObject, file, line);
    return Own<T>(LObject);
}

template <class T, class... A>
Ref<T> make_ref(const char* file, std::int32_t line, A&&... args) {
    T* LObject = new T(std::forward<A>(args)...);
    track_object(LObject, file, line);
    return Ref<T>(LObject, OwnDelete{});
}

// create(P) (BNF sec 7, PLAN-INTRINSICS I3): a value-initialized T (every
// byte of a record / overlay zeroed) on the heap, tracked as an owner's
// object is, at its create's file(line); the emitter assigns the result to P
template <class T>
T* create(const char* file, std::int32_t line) {
    T* LObject = new T{};
    track_object(LObject, file, line);
    return LObject;
}

// destroy(P): releases what create built (nothing for nil), tracked at the
// most derived object's address as the owner deleter does; the emitter then
// sets P to nil
template <class T>
void destroy(T* p) {
    if (p == nullptr) {
        return;
    }
    if constexpr (std::is_polymorphic_v<T>) {
        untrack_object(dynamic_cast<const void*>(p));
    } else {
        untrack_object(static_cast<const void*>(p));
    }
    delete p;
}

// alive(W) / lock(W): the object a weak watches still exists / a ref to it
// (nil when it is gone)
template <class T>
bool alive(const Weak<T>& watcher) noexcept {
    return !watcher.expired();
}

template <class T>
Ref<T> lock(const Weak<T>& watcher) noexcept {
    return watcher.lock();
}

[[noreturn]] void raise_nil_owner();

// The object an own / ref holds; nil raises
template <class P>
auto& deref(const P& owner) {
    if (!owner) {
        raise_nil_owner();
    }
    return *owner;
}

/*******************************************************************************
 * is / as (PLAN-OBJECT O12, D15): X is T / X as T on a polymorphic object, a
 * pointer to one, an Own or a Ref. is_a: the object X denotes is a T (or a
 * descendant); nil is never one. as_a keeps X's kind: a pointer gives a T*
 * (const kept) and a Ref a Ref<T> (nil stays nil), an object and an Own the
 * object itself as T& (const kept; a nil Own raises as deref does). An object
 * that is not a T raises EXC_INVALID_CAST naming T
 ******************************************************************************/

[[noreturn]] void raise_invalid_cast(const char* target);

namespace detail {

// Which owner a C++ type is: 0 none, 1 an Own (unique_ptr), 2 a Ref (shared_ptr)
template <class X>
inline constexpr int owner_kind = 0;

template <class T, class D>
inline constexpr int owner_kind<std::unique_ptr<T, D>> = 1;

template <class T>
inline constexpr int owner_kind<std::shared_ptr<T>> = 2;

// PLAN-OBJECT O13b: dynamic_cast when From is polymorphic; otherwise the
// static answer (a From is a To: the pointer, else none). An is / as on an
// object whose polymorphism only clang knows (a C++ base) then never fails
// inside the runtime: the emitter's check reports SM0271 at the operand
template <class To, class From>
To* poly_cast(From* p) noexcept {
    if constexpr (std::is_polymorphic_v<std::remove_cv_t<From>>) {
        return dynamic_cast<To*>(p);
    } else if constexpr (std::is_base_of_v<std::remove_cv_t<To>, std::remove_cv_t<From>>) {
        return static_cast<To*>(p);
    } else {
        return nullptr;
    }
}

}  // namespace detail

template <class T, class X>
bool is_a(const X& x) noexcept {
    if constexpr (std::is_pointer_v<X>) {
        return detail::poly_cast<const T>(x) != nullptr;
    } else if constexpr (detail::owner_kind<X> != 0) {
        return detail::poly_cast<const T>(x.get()) != nullptr;
    } else {
        return detail::poly_cast<const T>(std::addressof(x)) != nullptr;
    }
}

template <class T, class X>
decltype(auto) as_a(X&& x, const char* target) {
    using LPlain = std::remove_cvref_t<X>;
    if constexpr (std::is_pointer_v<LPlain>) {
        using LTo = std::conditional_t<std::is_const_v<std::remove_pointer_t<LPlain>>, const T, T>;
        if (x == nullptr) {
            return static_cast<LTo*>(nullptr);
        }
        LTo* LResult = detail::poly_cast<LTo>(x);
        if (LResult == nullptr) {
            raise_invalid_cast(target);
        }
        return LResult;
    } else if constexpr (detail::owner_kind<LPlain> == 2) {
        if (!x) {
            return Ref<T>();
        }
        // The aliasing constructor: shares x's ownership, points at the T
        T* LPointer = detail::poly_cast<T>(x.get());
        if (LPointer == nullptr) {
            raise_invalid_cast(target);
        }
        return Ref<T>(x, LPointer);
    } else if constexpr (detail::owner_kind<LPlain> == 1) {
        T* LResult = detail::poly_cast<T>(std::addressof(deref(x)));
        if (LResult == nullptr) {
            raise_invalid_cast(target);
        }
        return static_cast<T&>(*LResult);
    } else {
        using LTo = std::conditional_t<std::is_const_v<std::remove_reference_t<X>>, const T, T>;
        LTo* LResult = detail::poly_cast<LTo>(std::addressof(x));
        if (LResult == nullptr) {
            raise_invalid_cast(target);
        }
        return static_cast<LTo&>(*LResult);
    }
}

/*******************************************************************************
 * Arithmetic: div / mod truncate (C++ / and %, C++'s result type); a zero
 * divisor raises EXC_DIV_BY_ZERO, a signed min / -1 EXC_INTEGER_OVERFLOW
 ******************************************************************************/

namespace detail {

// Raises when a / b or a % b has no defined C++ result
template <class A, class B>
constexpr void check_divide(const A a, const B b) {
    using LResult = decltype(a / b);
    if (b == 0) {
        raise(EXC_DIV_BY_ZERO, "Divide by zero");
    }
    // The overflow is in the type C++ computes in: int8 -128 div -1 is int 128
    if constexpr (std::is_signed_v<LResult>) {
        if ((static_cast<LResult>(b) == static_cast<LResult>(-1)) &&
            (static_cast<LResult>(a) == std::numeric_limits<LResult>::min())) {
            raise(EXC_INTEGER_OVERFLOW, "Numeric overflow");
        }
    }
}

} // namespace detail

template <class A, class B>
constexpr auto Div(const A a, const B b) {
    detail::check_divide(a, b);
    return a / b;
}

template <class A, class B>
constexpr auto Mod(const A a, const B b) {
    detail::check_divide(a, b);
    return a % b;
}

// target %= value with Mod's checks; target is evaluated once (the caller's
// reference)
template <class T, class V>
constexpr T& ModAssign(T& target, const V value) {
    detail::check_divide(target, value);
    target %= value;
    return target;
}

/*******************************************************************************
 * Text
 ******************************************************************************/

// Wide text (UTF-16 on Windows, UTF-32 on Linux) as UTF-8; a lone surrogate
// or a value past U+10FFFF becomes U+FFFD
std::string utf8(const std::wstring& text);

// One wide character as UTF-8, through the same codec: a lone surrogate half
// or a value past U+10FFFF becomes U+FFFD (print / println of a wchar)
std::string utf8(wchar_t c);

// A C string to print: nullptr prints nil
constexpr std::string_view CStr(const char* text) {
    if (text == nullptr) {
        return std::string_view("nil");
    }
    return std::string_view(text);
}

// A wide C string to print: nullptr prints nil, else its text as UTF-8
std::string WCStr(const wchar_t* text);

// print / println of an array whose elements need their own print form
// (PLAN-PASKAL-ERRORS E7): a vector of every element through f, which
// std::format formats as a range (a transform view it does not)
template <class R, class F>
auto print_map(const R& range, F f) {
    std::vector<std::remove_cvref_t<decltype(f(*std::begin(range)))>> result;
    result.reserve(std::size(range));
    for (const auto& element : range) {
        result.push_back(f(element));
    }
    return result;
}

// Whether std::format takes a T (E7): a plain constant, so the emitter's
// static_assert on it fails with its own message alone (asserted on the
// concept itself, clang explains the concept and reports a step of that
// explanation as a second error)
template <class T>
inline constexpr bool printable = std::formattable<T, char>;

// A print argument of a C/C++ type (E7): itself when std::format takes it,
// else a placeholder, so std::format never instantiates a formatter it does
// not have; the emitter's static_assert beside it reports SM0425 at the
// argument (the only report, whatever the error budget)
template <class T>
decltype(auto) print_arg(const T& value) {
    if constexpr (printable<T>) {
        return (value);
    } else {
        return std::string_view("?");
    }
}

// Array elements that print as text (E7; formatters after the namespace):
// alone as their text, inside a range quoted as a char / string element is;
// a nil pointer prints nil, unquoted (a nil is not text)
struct PrintWChar {
    wchar_t value;
};

struct PrintCStr {
    const char* value;
};

struct PrintWCStr {
    const wchar_t* value;
};

namespace detail {

// A string's debug form ("..." with C++23's escapes) re-quoted as a char's
// debug form ('...': a single quote escaped, a double quote not)
inline std::string quote_as_char(const std::string& debug) {
    std::string result = "'";
    for (std::size_t i = 1; i + 1 < debug.size(); ++i) {
        if (debug[i] == '\\' && i + 2 < debug.size()) {
            // An escape: \" becomes ", every other one is kept whole
            if (debug[i + 1] == '"') {
                result += '"';
            } else {
                result += debug[i];
                result += debug[i + 1];
            }
            ++i;
        } else if (debug[i] == '\'') {
            result += "\\'";
        } else {
            result += debug[i];
        }
    }
    result += "'";
    return result;
}

} // namespace detail

/*******************************************************************************
 * Format arguments by C++ type (PLAN-VENDOR 1d: SysUtils.FormatStr, a C++
 * variadic template). print / println decide each argument's form from the
 * AST (TPCTypeExpr.PrintFormOfArg, the emitter writes it); a C++ routine sees
 * only C++ types, so format_arg gives the same text by the C++ type each
 * PaskalCPP type is emitted as: a wchar (and a wchar bitfield read as
 * char16_t) and a wstring as UTF-8, a ptr to char / wchar as its text (nil
 * prints nil), a typed or routine pointer as its address, an array whose
 * elements need a form element by element (print_map with the Print*
 * elements, nested arrays too), anything else itself. format_arg_t<T> is the
 * type it returns: a std::format_string over those types checks the call
 ******************************************************************************/

namespace detail {

// Whether a type is an array print / println format element by element: it
// has begin / end (a static or dynamic array, a string)
template <class V>
concept format_range = requires(const V& range) { std::begin(range); std::end(range); };

// Whether an element (of an array) needs its own print form
template <class E>
consteval bool format_element_mapped() {
    using V = std::remove_cv_t<E>;
    if constexpr (std::is_same_v<V, wchar_t> || std::is_same_v<V, char16_t> ||
                  std::is_same_v<V, std::wstring>) {
        return true;
    } else if constexpr (std::is_pointer_v<V>) {
        // char / wchar pointers print as text, the others as their address;
        // an untyped pointer prints as itself
        return !std::is_void_v<std::remove_cv_t<std::remove_pointer_t<V>>>;
    } else if constexpr (format_range<V>) {
        return format_element_mapped<
            std::remove_cvref_t<decltype(*std::begin(std::declval<const V&>()))>>();
    } else {
        return false;
    }
}

// Whether a pointer type points to (const) C
template <class P, class C>
inline constexpr bool points_to =
    std::is_pointer_v<P> && std::is_same_v<std::remove_cv_t<std::remove_pointer_t<P>>, C>;

// One element of an array in its print form (print / println's element rule)
template <class E>
auto format_element(const E& element) {
    using V = std::remove_cv_t<E>;
    if constexpr (std::is_same_v<V, wchar_t>) {
        return PrintWChar{element};
    } else if constexpr (std::is_same_v<V, char16_t>) {
        return PrintWChar{static_cast<wchar_t>(element)};
    } else if constexpr (std::is_same_v<V, std::wstring>) {
        return utf8(element);
    } else if constexpr (points_to<V, char>) {
        return PrintCStr{element};
    } else if constexpr (points_to<V, wchar_t>) {
        return PrintWCStr{element};
    } else if constexpr (std::is_pointer_v<V> && std::is_function_v<std::remove_pointer_t<V>>) {
        return reinterpret_cast<const void*>(element);
    } else if constexpr (std::is_pointer_v<V> && format_element_mapped<V>()) {
        return static_cast<const void*>(element);
    } else if constexpr (format_range<V> && format_element_mapped<V>()) {
        // A nested array whose elements need a form
        return print_map(element, [](const auto& inner) { return format_element(inner); });
    } else {
        return element;
    }
}

} // namespace detail

// One format argument in its print form; a value that needs none is returned
// as the caller's reference (no copy)
template <class T>
decltype(auto) format_arg(const T& value) {
    using V = std::remove_cv_t<T>;
    if constexpr (std::is_same_v<V, wchar_t>) {
        return utf8(value);
    } else if constexpr (std::is_same_v<V, char16_t>) {
        return utf8(static_cast<wchar_t>(value));
    } else if constexpr (std::is_same_v<V, std::wstring>) {
        return utf8(value);
    } else if constexpr (std::is_array_v<V> &&
                         std::is_same_v<std::remove_cv_t<std::remove_extent_t<V>>, wchar_t>) {
        // A wide string literal (L"..."): its text up to the terminator
        return utf8(std::wstring(value));
    } else if constexpr (detail::points_to<V, char>) {
        return CStr(value);
    } else if constexpr (detail::points_to<V, wchar_t>) {
        return WCStr(value);
    } else if constexpr (std::is_pointer_v<V> && std::is_function_v<std::remove_pointer_t<V>>) {
        return reinterpret_cast<const void*>(value);
    } else if constexpr (std::is_pointer_v<V> && detail::format_element_mapped<V>()) {
        return static_cast<const void*>(value);
    } else if constexpr (!std::is_array_v<V> && detail::format_range<V> &&
                         detail::format_element_mapped<V>()) {
        // An array (static or dynamic) whose elements need a form
        return print_map(value, [](const auto& element) { return detail::format_element(element); });
    } else if constexpr (printable<V>) {
        return (value);
    } else {
        // No std::formatter (a PaskalCPP record / object / overlay, a C/C++
        // type without one; PLAN-VENDOR 1e): the frontend reports SM0425 at
        // the caller's argument (BuildOutput asks at the instantiation
        // notes), and the placeholder keeps std::format from instantiating
        // the missing formatter, so this is the only report
        static_assert(printable<V>, "pcpp:SM0425");
        return std::string_view("?");
    }
}

// The type format_arg gives a T: what a std::format_string is checked against
template <class T>
using format_arg_t = decltype(::pcpp::format_arg(std::declval<const T&>()));

/*******************************************************************************
 * Static arrays (PLAN-RECORDS A8b, F-A8a): Array<T, N> is a PaskalCPP static
 * array of N elements. Plain data (one public C array, no constructors, no
 * initializers), so a packed record packs it as written (PLAN-RECORDS M9).
 * The emitter indexes it with the built-in [] on that C array
 * (a.pcpp_items[i]): an element of an array that sits misaligned is read and
 * written as any packed field is, never through a member call on a
 * misaligned object (std::array's operator[] was one). An aggregate:
 * Array<T, N> A{} is all zero, Array<T, N>{a, b, c} as written. size / begin /
 * end make it a range (len, print), == and <=> compare element by element (as
 * std::array did), [] is for mixed C++ only
 *
 * F47: no type is max_object_size bytes or more on any supported target
 * (clang refuses such a struct; PaskalCPP.Common PC_MAX_OBJECT_SIZE, the same
 * value, witnessed by Conditionals.size_witness). Array checks its count x
 * element size where it is instantiated (the element is complete only there):
 * past the cap it names detail::array_check<false, ...>, deprecated with the
 * frontend's marker, inside a region that makes the warning fatal, so the TU
 * stops before the array is laid out. The frontend reports it as SM0277 at
 * the use clang's instantiation note names
 ******************************************************************************/

inline constexpr std::size_t max_object_size = 1152921504606846975ull;

namespace detail {

template <bool FITS, class T, std::size_t N>
struct array_check {
    using type = int;
};

template <class T, std::size_t N>
struct [[deprecated("pcpp:SM0277")]] array_check<false, T, N> {
    using type = int;
};

} // namespace detail

template <class T, std::size_t N>
struct Array {
#pragma clang diagnostic push
#pragma clang diagnostic fatal "-Wdeprecated-declarations"
    using pcpp_size_check = typename detail::array_check<(N <= max_object_size / sizeof(T)), T, N>::type;
#pragma clang diagnostic pop

    T pcpp_items[N];

    static constexpr std::size_t size() noexcept {
        return N;
    }

    constexpr T* data() noexcept {
        return pcpp_items;
    }

    constexpr const T* data() const noexcept {
        return pcpp_items;
    }

    constexpr T* begin() noexcept {
        return pcpp_items;
    }

    constexpr const T* begin() const noexcept {
        return pcpp_items;
    }

    constexpr T* end() noexcept {
        return pcpp_items + N;
    }

    constexpr const T* end() const noexcept {
        return pcpp_items + N;
    }

    constexpr T& operator[](const std::size_t i) noexcept {
        return pcpp_items[i];
    }

    constexpr const T& operator[](const std::size_t i) const noexcept {
        return pcpp_items[i];
    }

    friend constexpr bool operator==(const Array&, const Array&) = default;
    friend constexpr auto operator<=>(const Array&, const Array&) = default;
};

/*******************************************************************************
 * Sets: Set<T, LOW, HIGH> holds members LOW..HIGH (ordinals, at most 65536)
 * as a word array; constexpr, trivially copyable, an ascending range of T.
 * An aggregate with no initializers (plain data, PLAN-RECORDS M9): write
 * Set S{} for the empty set; Set S; leaves its words unset, as for any C
 * struct
 ******************************************************************************/

template <class T, std::int64_t LOW, std::int64_t HIGH>
class Set;

// [] where no set type is known: converts to every Set, the empty one
// (value-initialized: every word zero). A conversion operator, not a Set
// constructor: Set is an aggregate (PLAN-RECORDS M9: plain data packs as a
// field of a packed record)
struct EmptySet {
    template <class T, std::int64_t LOW, std::int64_t HIGH>
    constexpr operator Set<T, LOW, HIGH>() const noexcept {
        return Set<T, LOW, HIGH>{};
    }
};

// lo..hi inside a set literal; lo > hi adds nothing
template <class T>
struct SetSpan {
    T lo;
    T hi;
};

template <class T, std::size_t N>
class SetItems;

namespace detail {

// The ordinal of a set element: a choice its underlying value, bool / char /
// an integer the value. Fits is false for an unsigned value past the int64
// range (it is in no set): ordinals compare without a signed / unsigned wrap
struct SetOrdinal {
    bool Fits;
    std::int64_t Value;
};

template <class U>
constexpr SetOrdinal set_ordinal(const U value) noexcept {
    if constexpr (std::is_enum_v<U>) {
        return set_ordinal(static_cast<std::underlying_type_t<U>>(value));
    }
    else if constexpr (std::is_same_v<U, bool>) {
        return SetOrdinal{true, value ? 1 : 0};
    }
    else {
        static_assert(std::is_integral_v<U>, "a set element is an integer, a choice, bool or char");
        if constexpr (std::is_unsigned_v<U>) {
            if (static_cast<std::uint64_t>(value) > static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max())) {
                return SetOrdinal{false, 0};
            }
        }
        return SetOrdinal{true, static_cast<std::int64_t>(value)};
    }
}

// One item of a set literal: an element (Lo = Hi) or a span; Empty = a span
// whose lo is above its hi
struct SetRange {
    bool Empty;
    SetOrdinal Lo;
    SetOrdinal Hi;
};

// An item as its ordinals: an integer, choice, bool or char value directly
// (so 300 into a 0..255 set is out of range, not wrapped), anything else
// through T
template <class T, class A>
constexpr SetRange set_range(const A& item) noexcept {
    if constexpr (std::is_same_v<A, SetSpan<T>>) {
        return SetRange{item.hi < item.lo, set_ordinal(item.lo), set_ordinal(item.hi)};
    }
    else if constexpr (std::is_integral_v<A> || std::is_enum_v<A>) {
        return SetRange{false, set_ordinal(item), set_ordinal(item)};
    }
    else {
        return SetRange{false, set_ordinal(static_cast<T>(item)), set_ordinal(static_cast<T>(item))};
    }
}

[[noreturn]] void raise_set_range(const SetOrdinal& value, std::int64_t low, std::int64_t high);

} // namespace detail

template <class T, std::int64_t LOW, std::int64_t HIGH>
class Set {
    static_assert(LOW <= HIGH, "a set's low bound is above its high bound");
    static_assert((LOW > std::numeric_limits<std::int64_t>::max() - 65535) || (HIGH <= LOW + 65535),
        "a set has at most 65536 members");

public:
    // Members, and the words that hold them
    static constexpr std::size_t BITS = static_cast<std::size_t>(HIGH - LOW) + 1;
    static constexpr std::size_t WORDS = static_cast<std::size_t>((HIGH - LOW) / 64) + 1;

    // Ascending members, each as a T
    class Iterator {
    public:
        using iterator_concept = std::forward_iterator_tag;
        using iterator_category = std::input_iterator_tag;
        using value_type = T;
        using difference_type = std::ptrdiff_t;
        using reference = T;
        using pointer = void;

        constexpr Iterator() noexcept = default;

        constexpr T operator*() const noexcept {
            return static_cast<T>(LOW + static_cast<std::int64_t>(FBit));
        }

        constexpr Iterator& operator++() noexcept {
            FBit = FSet->next_bit(FBit + 1);
            return *this;
        }

        constexpr Iterator operator++(int) noexcept {
            Iterator LBefore = *this;
            ++*this;
            return LBefore;
        }

        friend constexpr bool operator==(const Iterator&, const Iterator&) noexcept = default;

    private:
        friend class Set;

        constexpr Iterator(const Set* ASet, const std::size_t ABit) noexcept
            : FSet(ASet), FBit(ABit) {
        }

        const Set* FSet = nullptr;
        std::size_t FBit = 0;
    };

    // Out of LOW..HIGH (or no int64 ordinal) = false
    template <class U>
    constexpr bool contains(const U value) const noexcept {
        const detail::SetOrdinal LOrdinal = detail::set_ordinal(value);
        if (!LOrdinal.Fits || (LOrdinal.Value < LOW) || (LOrdinal.Value > HIGH)) {
            return false;
        }
        const std::size_t LBit = static_cast<std::size_t>(LOrdinal.Value - LOW);
        return ((pcpp_words[LBit / 64] >> (LBit % 64)) & 1u) != 0;
    }

    constexpr Iterator begin() const noexcept {
        return Iterator(this, next_bit(0));
    }

    constexpr Iterator end() const noexcept {
        return Iterator(this, BITS);
    }

    // Union, intersection, difference
    friend constexpr Set operator|(const Set& a, const Set& b) noexcept {
        Set LResult{};
        for (std::size_t LI = 0; LI < WORDS; LI++) {
            LResult.pcpp_words[LI] = a.pcpp_words[LI] | b.pcpp_words[LI];
        }
        return LResult;
    }

    friend constexpr Set operator&(const Set& a, const Set& b) noexcept {
        Set LResult{};
        for (std::size_t LI = 0; LI < WORDS; LI++) {
            LResult.pcpp_words[LI] = a.pcpp_words[LI] & b.pcpp_words[LI];
        }
        return LResult;
    }

    friend constexpr Set operator-(const Set& a, const Set& b) noexcept {
        Set LResult{};
        for (std::size_t LI = 0; LI < WORDS; LI++) {
            LResult.pcpp_words[LI] = a.pcpp_words[LI] & ~b.pcpp_words[LI];
        }
        return LResult;
    }

    // Compound union, intersection, difference (PaskalCPP's S += T, S *= T,
    // S -= T are written |= &= -=; PLAN-RECORDS F-A8c). Word by word, so
    // S |= S and S -= S are right. Member functions: still an aggregate
    constexpr Set& operator|=(const Set& b) noexcept {
        for (std::size_t LI = 0; LI < WORDS; LI++) {
            pcpp_words[LI] |= b.pcpp_words[LI];
        }
        return *this;
    }

    constexpr Set& operator&=(const Set& b) noexcept {
        for (std::size_t LI = 0; LI < WORDS; LI++) {
            pcpp_words[LI] &= b.pcpp_words[LI];
        }
        return *this;
    }

    constexpr Set& operator-=(const Set& b) noexcept {
        for (std::size_t LI = 0; LI < WORDS; LI++) {
            pcpp_words[LI] &= ~b.pcpp_words[LI];
        }
        return *this;
    }

    friend constexpr bool operator==(const Set&, const Set&) noexcept = default;

    // a <= b: a is a subset of b; a >= b: a is a superset of b
    friend constexpr bool operator<=(const Set& a, const Set& b) noexcept {
        for (std::size_t LI = 0; LI < WORDS; LI++) {
            if ((a.pcpp_words[LI] & ~b.pcpp_words[LI]) != 0) {
                return false;
            }
        }
        return true;
    }

    friend constexpr bool operator>=(const Set& a, const Set& b) noexcept {
        return b <= a;
    }

private:
    template <class U, std::size_t N>
    friend class SetItems;

    // The first member at or after bit ABit; BITS when there is none
    constexpr std::size_t next_bit(const std::size_t ABit) const noexcept {
        std::size_t LBit = ABit;
        while (LBit < BITS) {
            const std::uint64_t LRest = pcpp_words[LBit / 64] >> (LBit % 64);
            if (LRest != 0) {
                LBit += static_cast<std::size_t>(std::countr_zero(LRest));
                return (LBit < BITS) ? LBit : BITS;
            }
            // Nothing left in this word: the next word's first bit
            LBit = (LBit / 64 + 1) * 64;
        }
        return BITS;
    }

    // Adds the members ALo..AHi (both inside LOW..HIGH, ALo <= AHi)
    constexpr void add_range(const std::int64_t ALo, const std::int64_t AHi) noexcept {
        for (std::int64_t LValue = ALo; LValue <= AHi; LValue++) {
            const std::size_t LBit = static_cast<std::size_t>(LValue - LOW);
            pcpp_words[LBit / 64] |= std::uint64_t(1) << (LBit % 64);
        }
    }

public:
    // The words, bit i = member LOW + i. Public and with no initializer, so
    // Set is an aggregate that packs as a field (M9); not API: the members
    // above are
    std::uint64_t pcpp_words[WORDS];
};

namespace detail {

// An integer element type: integers of every width and signedness are one
// ordinal family (a set literal [AN] with AN: int32 goes into set of 0..99);
// bool and char each stay their own
template <class U>
inline constexpr bool set_integer_v = std::is_integral_v<U> && !std::is_same_v<U, bool> &&
    !std::is_same_v<U, char> && !std::is_same_v<U, wchar_t>;

} // namespace detail

// A set literal's items (ordinals); converts to every Set of its element
// type, and an integer literal to every integer Set. An item outside the
// set's bounds raises EXC_SET_RANGE
template <class T, std::size_t N>
class SetItems {
public:
    constexpr explicit SetItems(const std::array<detail::SetRange, N>& AItems) noexcept
        : FItems(AItems) {
    }

    // `x in [a, b..c]` with no set type around the literal (F54): x is one of
    // its items, by Set::contains' ordinal rule (no int64 ordinal = false)
    template <class U>
    constexpr bool contains(const U value) const noexcept {
        const detail::SetOrdinal LOrdinal = detail::set_ordinal(value);
        if (!LOrdinal.Fits) {
            return false;
        }
        for (const detail::SetRange& LItem : FItems) {
            if (LItem.Empty || !LItem.Lo.Fits || !LItem.Hi.Fits) {
                continue;
            }
            if ((LOrdinal.Value >= LItem.Lo.Value) && (LOrdinal.Value <= LItem.Hi.Value)) {
                return true;
            }
        }
        return false;
    }

    template <class U, std::int64_t LOW, std::int64_t HIGH>
        requires(std::is_same_v<U, T> || (detail::set_integer_v<U> && detail::set_integer_v<T>))
    constexpr operator Set<U, LOW, HIGH>() const {
        Set<U, LOW, HIGH> LResult{};
        for (const detail::SetRange& LItem : FItems) {
            if (LItem.Empty) {
                continue;
            }
            if (!LItem.Lo.Fits || (LItem.Lo.Value < LOW) || (LItem.Lo.Value > HIGH)) {
                detail::raise_set_range(LItem.Lo, LOW, HIGH);
            }
            if (!LItem.Hi.Fits || (LItem.Hi.Value > HIGH)) {
                detail::raise_set_range(LItem.Hi, LOW, HIGH);
            }
            LResult.add_range(LItem.Lo.Value, LItem.Hi.Value);
        }
        return LResult;
    }

private:
    std::array<detail::SetRange, N> FItems;
};

// make_set<T>(e, SetSpan<T>{lo, hi}, ...): a set literal of element type T
template <class T, class... A>
constexpr SetItems<T, sizeof...(A)> make_set(const A&... items) noexcept {
    return SetItems<T, sizeof...(A)>(std::array<detail::SetRange, sizeof...(A)>{detail::set_range<T>(items)...});
}

static_assert(std::is_trivially_copyable_v<Set<std::int32_t, 0, 63>>);
static_assert(std::is_trivially_copyable_v<Set<bool, 0, 1>>);
static_assert(std::is_trivially_copyable_v<Set<std::int32_t, 0, 65535>>);
static_assert(std::is_aggregate_v<Set<std::int32_t, 0, 63>>);

/*******************************************************************************
 * Packed fields (PLAN-RECORDS M9; research\drop-object\a0-packs-trait.md):
 * packs_as_field<T> is true when clang packs a field of type T inside a
 * [[gnu::packed]] struct (it does so only for plain data). Measured, not
 * modelled: a packed {char; T} is one byte larger than a packed {T} exactly
 * when the T field sits at offset 1. The emitter asserts it for a field type
 * of a packed record that SEM cannot judge (a C/C++ type), "pcpp:SM0331"
 ******************************************************************************/

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpacked-non-pod"
template <class T>
struct pack_probe {
    struct [[gnu::packed]] WithByte {
        char C;
        T F;
    };
    struct [[gnu::packed]] Alone {
        T F;
    };
};
#pragma clang diagnostic pop

template <class T>
inline constexpr bool packs_as_field = sizeof(typename pack_probe<T>::WithByte) ==
    sizeof(typename pack_probe<T>::Alone) + 1;

static_assert(packs_as_field<Set<std::int32_t, 0, 63>>);
static_assert(packs_as_field<std::int32_t>);

/*******************************************************************************
 * Overlay fields (PLAN-COMPLIANCE F34): an overlay is a C++ union, and a
 * union member must be trivial data (trivially default-constructible and
 * trivially copyable, which takes a trivial destructor), or the union's own
 * special members are deleted. fits_overlay<T> asks exactly that; every
 * PaskalCPP leaf SEM lets through is one. For an overlay field's type SEM
 * cannot judge (a C/C++ type) the emitter names overlay_check<fits_overlay<T>>
 * in a region where -Wdeprecated-declarations is FATAL: the false one is
 * deprecated "pcpp:SM0313" (the marker is PC_FRONTEND_CHECK_OVERLAY, Common;
 * the type_overlay_err_cpp_* compliance files witness both spellings), so
 * clang stops the TU there, before the union's deleted members
 ******************************************************************************/

template <class T>
inline constexpr bool fits_overlay = std::is_trivially_default_constructible_v<T> &&
    std::is_trivially_copyable_v<T>;

template <bool FITS>
struct overlay_check {};

template <>
struct [[deprecated("pcpp:SM0313")]] overlay_check<false> {};

static_assert(fits_overlay<Set<std::int32_t, 0, 63>>);
static_assert(fits_overlay<Array<std::int32_t, 4>>);
static_assert(fits_overlay<std::int32_t>);
static_assert(!fits_overlay<std::string>);

/*******************************************************************************
 * Varargs (cpplink): a call packs its extra arguments with
 * Pack(Slot<T>((e)), slot((e)), ...) into a VarStore; the routine reads them
 * through its VarArgs, by type, checked at run time
 ******************************************************************************/

namespace detail {

// The type's name as clang spells the canonical template argument
template <class T>
constexpr std::string_view va_raw_name() {
    constexpr std::string_view LText = __PRETTY_FUNCTION__;
    constexpr std::size_t LStart = LText.find("[T = ") + 5;
    constexpr std::size_t LEnd = LText.rfind(']');
    return LText.substr(LStart, LEnd - LStart);
}

} // namespace detail

// A type's identity in a pack, a NUL-terminated name: a PaskalCPP builtin its
// PaskalCPP spelling (keyed by the canonical type, so no typedef splits it),
// every other type clang's name for it
template <class T>
struct VaName {
    static constexpr std::string_view Raw = detail::va_raw_name<T>();
    static constexpr std::array<char, Raw.size() + 1> Buffer = []() {
        std::array<char, Raw.size() + 1> LBuf{};
        for (std::size_t LI = 0; LI < Raw.size(); ++LI) {
            LBuf[LI] = Raw[LI];
        }
        return LBuf;
    }();
    static constexpr const char* Value = Buffer.data();
};

template <> struct VaName<std::int8_t> { static constexpr const char* Value = "int8"; };
template <> struct VaName<std::int16_t> { static constexpr const char* Value = "int16"; };
template <> struct VaName<std::int32_t> { static constexpr const char* Value = "int32"; };
template <> struct VaName<std::int64_t> { static constexpr const char* Value = "int64"; };
template <> struct VaName<std::uint8_t> { static constexpr const char* Value = "uint8"; };
template <> struct VaName<std::uint16_t> { static constexpr const char* Value = "uint16"; };
template <> struct VaName<std::uint32_t> { static constexpr const char* Value = "uint32"; };
template <> struct VaName<std::uint64_t> { static constexpr const char* Value = "uint64"; };
template <> struct VaName<float> { static constexpr const char* Value = "float32"; };
template <> struct VaName<double> { static constexpr const char* Value = "float64"; };
template <> struct VaName<bool> { static constexpr const char* Value = "bool"; };
template <> struct VaName<char> { static constexpr const char* Value = "char"; };
template <> struct VaName<wchar_t> { static constexpr const char* Value = "wchar"; };
template <> struct VaName<std::string> { static constexpr const char* Value = "string"; };
template <> struct VaName<std::wstring> { static constexpr const char* Value = "wstring"; };
template <> struct VaName<void*> { static constexpr const char* Value = "ptr"; };

// One packed argument: its type identity and its value (inside a VarStore)
struct VaItem {
    const char* TypeName;
    const void* Value;
};

// Two identities name one type when the pointers match (same module) or the
// names do (a pack built in one module, read in another)
inline bool VaSameType(const char* AStored, const char* AWanted) noexcept {
    return (AStored == AWanted) || (std::strcmp(AStored, AWanted) == 0);
}

// EXC_VARARGS_TYPE: varargs.<member>(<wanted>): argument <i> is <stored>
[[noreturn]] void VaRaiseType(const char* AMember, std::int32_t AIndex, const char* AStored, const char* AWanted);

// EXC_VARARGS_INDEX: varargs.<member>: argument <i> does not exist (count <n>)
[[noreturn]] void VaRaiseIndex(const char* AMember, std::int32_t AIndex, std::int32_t ACount);

template <class... Ts>
class VarStore;

// The view a variadic routine receives (pcpp_va) and a varargs local holds:
// the caller's packed items, their count and a cursor. Valid while the call
// runs (the store is a temporary of the call statement)
class VarArgs {
public:
    VarArgs() noexcept = default;

    std::int32_t Count() const noexcept {
        return FCount;
    }

    void Reset() noexcept {
        FCursor = 0;
    }

    // An independent view, cursor included
    VarArgs Copy() const noexcept {
        return *this;
    }

    // The next argument; the cursor advances only when the read succeeds
    template <class T>
    const T& Next() {
        const T& LValue = Read<T>("next", FCursor);
        ++FCursor;
        return LValue;
    }

    // Argument AIndex (zero-based); the cursor stays
    template <class T>
    const T& Get(const std::int32_t AIndex) const {
        return Read<T>("get", AIndex);
    }

private:
    template <class... Ts>
    friend class VarStore;

    VarArgs(const VaItem* AItems, const std::int32_t ACount) noexcept
        : FItems(AItems), FCount(ACount) {
    }

    template <class T>
    const T& Read(const char* AMember, const std::int32_t AIndex) const {
        const char* LWanted = VaName<T>::Value;
        if ((AIndex < 0) || (AIndex >= FCount)) {
            VaRaiseIndex(AMember, AIndex, FCount);
        }
        if (!VaSameType(FItems[AIndex].TypeName, LWanted)) {
            VaRaiseType(AMember, AIndex, FItems[AIndex].TypeName, LWanted);
        }
        return *static_cast<const T*>(FItems[AIndex].Value);
    }

    const VaItem* FItems = nullptr;
    std::int32_t FCount = 0;
    std::int32_t FCursor = 0;
};

// The caller's pack: a copy of every argument (value semantics, as a by-value
// parameter) and its items, which point into the store itself: built in place
// (Pack returns it as a prvalue), never copied or moved
template <class... Ts>
class VarStore {
public:
    template <class... U>
    explicit VarStore(std::in_place_t, U&&... AValues)
        : FValues(std::forward<U>(AValues)...) {
        DoFill(std::index_sequence_for<Ts...>{});
    }

    VarStore(const VarStore&) = delete;
    VarStore& operator=(const VarStore&) = delete;

    operator VarArgs() const noexcept {
        return VarArgs(FItems.data(), static_cast<std::int32_t>(sizeof...(Ts)));
    }

private:
    template <std::size_t... I>
    void DoFill(std::index_sequence<I...>) noexcept {
        ((FItems[I] = VaItem{VaName<Ts>::Value, &std::get<I>(FValues)}), ...);
    }

    std::tuple<Ts...> FValues;
    std::array<VaItem, sizeof...(Ts)> FItems{};
};

// One argument of a cpplink variadic call, of type T: Slot<T>((e)) with a
// spelled type, slot((e)) deducing the decayed type
template <class T>
struct Slot {
    T Value;

    template <class U>
    explicit Slot(U&& AValue)
        : Value(std::forward<U>(AValue)) {
    }
};

template <class E>
Slot<std::decay_t<E>> slot(E&& AValue) {
    return Slot<std::decay_t<E>>(std::forward<E>(AValue));
}

template <class... T>
VarStore<T...> Pack(Slot<T>... ASlots) {
    return VarStore<T...>(std::in_place, std::move(ASlots.Value)...);
}

/*******************************************************************************
 * A call limited to some members of an overload set (SEM F18: the members
 * PaskalCPP's conversions accept): overloads(static_cast<R(*)(P...)>(&f), ...)
 * is called with the arguments; each member's call operator takes that
 * member's own parameter types, so C++ ranks exactly these members as it
 * would rank them by name, and never sees the ones left out
 ******************************************************************************/

namespace detail {

template <class S>
struct OverloadMember;

template <class R, class... A>
struct OverloadMember<R(A...)> {
    R (*Fn)(A...);

    R operator()(A... AArgs) const {
        return Fn(static_cast<A&&>(AArgs)...);
    }
};

template <class... M>
struct OverloadSet : M... {
    using M::operator()...;
};

} // namespace detail

template <class... S>
constexpr auto overloads(S*... AFns) {
    return detail::OverloadSet<detail::OverloadMember<S>...>{detail::OverloadMember<S>{AFns}...};
}

/*******************************************************************************
 * Record extensions (PLAN-RECORDS M10 / M12 / M13): a PaskalCPP record's
 * parent is its first member pcpp_parent, never a C++ base class. The emitter
 * writes `using pcpp_record = void;` in every record (an object is no record
 * here: it keeps its C++ base class), `using pcpp_parent_t = P;` in an
 * extension of the record P and `using pcpp_cpp_base_t = C;` in a record that
 * derives from the C/C++ type C. What inheritance gave for free is written
 * through them: the pointer upcast and downcast, and the ranking of an
 * overload call whose members take a record, or a pointer to one, at
 * different levels of its chain (ranked_overloads)
 ******************************************************************************/

namespace detail {

template <class T>
struct ParentOf {
    using type = void;
};

template <class T>
    requires requires { typename std::remove_const_t<T>::pcpp_parent_t; }
struct ParentOf<T> {
    using raw = typename std::remove_const_t<T>::pcpp_parent_t;
    using type = std::conditional_t<std::is_const_v<T>, const raw, raw>;
};

template <class T>
struct CppBaseOf {
    using type = void;
};

template <class T>
    requires requires { typename std::remove_const_t<T>::pcpp_cpp_base_t; }
struct CppBaseOf<T> {
    using raw = typename std::remove_const_t<T>::pcpp_cpp_base_t;
    using type = std::conditional_t<std::is_const_v<T>, const raw, raw>;
};

} // namespace detail

// T's parent record, const kept; void for a root record
template <class T>
using parent_t = typename detail::ParentOf<T>::type;

// The C/C++ type a root record derives from, const kept; void for none
template <class T>
using cpp_base_t = typename detail::CppBaseOf<T>::type;

// A PaskalCPP record (not an object, not a C/C++ type)
template <class T>
concept record = requires { typename std::remove_const_t<T>::pcpp_record; };

namespace detail {

// F-R4f: an extension that aligns below its parent (a packed one) may hold
// its parent misaligned. No pointer or reference to that parent is formed:
// SEM rejects a pointer / var upcast of it (SM0270), a value / const one
// copies the parent out
template <class R>
constexpr bool ParentAlignsAbove() {
    // a root has no parent (alignof(void) is no expression)
    if constexpr (std::is_void_v<parent_t<R>>) {
        return false;
    } else {
        return alignof(R) < alignof(parent_t<R>);
    }
}

template <class R>
inline constexpr bool ParentMayBeMisaligned = ParentAlignsAbove<R>();

// One parent level up; nil stays nil
template <class T>
constexpr parent_t<T>* Up1(T* AP) noexcept {
    static_assert(!ParentMayBeMisaligned<std::remove_const_t<T>>, "pcpp: a pointer to a packed extension's parent");
    return AP != nullptr ? &AP->pcpp_parent : nullptr;
}

// The record N parent levels above T, const kept; void past a root
template <class T, int N>
struct UpN {
    using type = typename UpN<parent_t<T>, N - 1>::type;
};

template <class T>
struct UpN<T, 0> {
    using type = T;
};

template <int N>
struct UpN<void, N> {
    using type = void;
};

template <>
struct UpN<void, 0> {
    using type = void;
};

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Winvalid-offsetof"

// Every level's pcpp_parent at offset 0: an extension and its parent share
// one address (a record holding a C++ class may not be standard layout:
// offsetof is still exact for it, a class with no base and no virtual)
template <class T, int N>
constexpr bool ParentAtZero() {
    if constexpr (N == 0) {
        return true;
    } else if constexpr (std::is_void_v<parent_t<T>>) {
        return false;
    } else {
        return offsetof(std::remove_const_t<T>, pcpp_parent) == 0 && ParentAtZero<parent_t<T>, N - 1>();
    }
}

#pragma clang diagnostic pop

} // namespace detail

// A pointer to an extension, N parent levels up (PLAN-RECORDS M12 (1)): nil
// stays nil, the argument is read once, const is kept
template <int N, class T>
constexpr auto upcast(T* AP) noexcept {
    if constexpr (N == 0) {
        return AP;
    } else {
        return upcast<N - 1>(detail::Up1(AP));
    }
}

namespace detail {

// P is the record N parent levels above TP's, or a C/C++ type that record
// derives from (C++ relates those two by static_cast)
template <int N, class TP, class P>
concept DowncastSource = std::is_pointer_v<TP> &&
    (std::is_same_v<std::remove_const_t<typename UpN<std::remove_pointer_t<TP>, N>::type>, std::remove_const_t<P>> ||
     std::is_base_of_v<std::remove_const_t<P>, std::remove_const_t<typename UpN<std::remove_pointer_t<TP>, N>::type>>);

} // namespace detail

// The pointer TP to the extension N parent levels below AP's record
// (PLAN-RECORDS F-A4b / F-A6a, an explicit ptr to TExt(P)): the same address,
// nil stays nil. AP points to that record, or to a C/C++ type it derives from
// (taken through C++'s static_cast); const is never cast away. Anything else
// has no candidate: the cast is clang's, at the call
template <int N, class TP, class P>
    requires(detail::DowncastSource<N, TP, P> && (std::is_const_v<std::remove_pointer_t<TP>> || !std::is_const_v<P>))
TP downcast(P* AP) noexcept {
    using T = std::remove_pointer_t<TP>;
    using L = typename detail::UpN<T, N>::type;
    static_assert(detail::ParentAtZero<T, N>(), "pcpp: a record's parent member is not at offset 0");
    if constexpr (std::is_same_v<std::remove_const_t<L>, std::remove_const_t<P>>) {
        return reinterpret_cast<TP>(AP);
    } else {
        return reinterpret_cast<TP>(static_cast<L*>(AP));
    }
}

// nil in a ranked overload call (M12): converts to every pointer and every
// pointer rank (a plain nullptr would rank a raw pointer parameter above a
// record pointer's rank)
struct Nil {
    template <class T>
    constexpr operator T*() const noexcept {
        return nullptr;
    }
};

inline constexpr Nil nil{};

namespace detail {

// Ranks: a record pointer, a record pointer variable or a record value in a
// ranked overload call. Each rank derives its parent's rank, so clang ranks a
// TExt2 argument to the TExt member above the TBase member exactly as C++
// inheritance did; a chain's root rank converts past the last record (to an
// untyped pointer, or to the C/C++ type the root record derives from)
struct PtrRankEnd {};
struct ConstPtrRankEnd {};
struct ValueRankEnd {};

template <class R>
struct PtrRank;

template <class R>
struct ConstPtrRank;

template <class R>
struct ValueRank;

template <class R>
using PtrRankUp = std::conditional_t<std::is_void_v<parent_t<R>>, PtrRankEnd, PtrRank<parent_t<R>>>;

template <class R>
using ConstPtrRankUp = std::conditional_t<std::is_void_v<parent_t<R>>, ConstPtrRankEnd, ConstPtrRank<parent_t<R>>>;

template <class R>
using ValueRankUp = std::conditional_t<std::is_void_v<parent_t<R>>, ValueRankEnd, ValueRank<parent_t<R>>>;

// A pointer to const R
template <class R>
struct ConstPtrRank : virtual ConstPtrRankUp<R> {
    const R* cp = nullptr;

    ConstPtrRank() = default;

    ConstPtrRank(Nil) {
    }

    operator const cpp_base_t<R>*() const noexcept
        requires std::is_void_v<parent_t<R>>
    {
        return cp;
    }
};

// A pointer to R (it also converts as a pointer to const R)
template <class R>
struct PtrRank : PtrRankUp<R>, virtual ConstPtrRank<R> {
    R* p = nullptr;

    PtrRank() = default;

    PtrRank(Nil) {
    }

    operator cpp_base_t<R>*() const noexcept
        requires std::is_void_v<parent_t<R>>
    {
        return p;
    }
};

// A pointer variable (a var parameter takes the variable itself)
template <class R>
struct VarPtrRank : PtrRank<R> {
    R** pp = nullptr;
};

template <class R>
struct VarConstPtrRank : ConstPtrRank<R> {
    const R** pp = nullptr;
};

template <class L, class O>
void FillPtr(O& AO, L* AP) {
    static_cast<PtrRank<L>&>(AO).p = AP;
    static_cast<ConstPtrRank<L>&>(AO).cp = AP;
    if constexpr (!std::is_void_v<parent_t<L>>) {
        FillPtr<parent_t<L>>(AO, Up1(AP));
    }
}

template <class L, class O>
void FillConstPtr(O& AO, const L* AP) {
    static_cast<ConstPtrRank<L>&>(AO).cp = AP;
    if constexpr (!std::is_void_v<parent_t<L>>) {
        FillConstPtr<parent_t<L>>(AO, Up1(AP));
    }
}

// The aligned copy of a parent that may sit misaligned (F-R4f); empty otherwise
template <class R>
struct ValueRankCopy {};

template <class R>
    requires ParentMayBeMisaligned<R>
struct ValueRankCopy<R> {
    std::remove_const_t<parent_t<R>> parent_copy;
};

struct NoCppBase {};

template <class R>
using CppBaseOrNone = std::conditional_t<std::is_void_v<cpp_base_t<R>>, NoCppBase, cpp_base_t<R>>;

// A record value or variable: the argument's level R. It may hold copies of
// parents (pointers into itself), so it is never copied or moved: built in
// place by rank_value, alive to the end of the call's full expression
template <class R>
struct ValueRank : ValueRankUp<R>, ValueRankCopy<R> {
    R* p = nullptr;

    explicit ValueRank(R* AP);
    ValueRank(const ValueRank&) = delete;
    ValueRank& operator=(const ValueRank&) = delete;

    // the root level past the last record: its C/C++ base by reference
    operator CppBaseOrNone<R>&() const noexcept
        requires(std::is_void_v<parent_t<R>> && !std::is_void_v<cpp_base_t<R>>)
    {
        return *p;
    }

protected:
    ValueRank() = default;
};

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Winvalid-offsetof"

template <class L, class O>
void FillValue(O& AO, L* AP) {
    static_cast<ValueRank<L>&>(AO).p = AP;
    if constexpr (!std::is_void_v<parent_t<L>>) {
        using P = std::remove_const_t<parent_t<L>>;
        if constexpr (ParentMayBeMisaligned<L>) {
            // F-R4f: copied out byte for byte (a packed record holds plain
            // data only, M9), never bound where it sits
            static_assert(std::is_trivially_copyable_v<P>, "pcpp: a packed extension's parent is not plain data");
            P& LCopy = static_cast<ValueRankCopy<L>&>(AO).parent_copy;
            std::memcpy(static_cast<void*>(&LCopy), reinterpret_cast<const unsigned char*>(AP) + offsetof(L, pcpp_parent),
                sizeof(P));
            FillValue<P>(AO, &LCopy);
        } else {
            FillValue<P>(AO, &AP->pcpp_parent);
        }
    }
}

#pragma clang diagnostic pop

template <class R>
ValueRank<R>::ValueRank(R* AP) {
    FillValue<R>(*this, AP);
}

// How a ranked member takes each parameter type: a record pointer, pointer
// variable or record (any mode) as its rank; every other type as declared
template <class A>
struct RankParam {
    using type = A;

    static A&& get(std::remove_reference_t<A>& AV) noexcept {
        return static_cast<A&&>(AV);
    }
};

template <record R>
struct RankParam<R*> {
    using type = const PtrRank<R>&;

    static R* get(const PtrRank<R>& AT) noexcept {
        return AT.p;
    }
};

template <record R>
struct RankParam<const R*> {
    using type = const ConstPtrRank<R>&;

    static const R* get(const ConstPtrRank<R>& AT) noexcept {
        return AT.cp;
    }
};

template <record R>
struct RankParam<R*&> {
    using type = const VarPtrRank<R>&;

    static R*& get(const VarPtrRank<R>& AT) noexcept {
        return *AT.pp;
    }
};

template <record R>
struct RankParam<const R*&> {
    using type = const VarConstPtrRank<R>&;

    static const R*& get(const VarConstPtrRank<R>& AT) noexcept {
        return *AT.pp;
    }
};

template <record R>
struct RankParam<R> {
    using type = const ValueRank<R>&;

    static R& get(const ValueRank<R>& AT) noexcept {
        return *AT.p;
    }
};

template <record R>
struct RankParam<const R&> {
    using type = const ValueRank<R>&;

    static const R& get(const ValueRank<R>& AT) noexcept {
        return *AT.p;
    }
};

template <record R>
struct RankParam<R&> {
    using type = const ValueRank<R>&;

    static R& get(const ValueRank<R>& AT) noexcept {
        return *AT.p;
    }
};

template <class S>
struct RankedMember;

template <class R, class... A>
struct RankedMember<R(A...)> {
    R (*Fn)(A...);

    R operator()(typename RankParam<A>::type... AArgs) const {
        return Fn(RankParam<A>::get(AArgs)...);
    }
};

} // namespace detail

// The arguments of a ranked overload call: a record pointer, a record
// pointer variable (a member may take it by var), a record value or variable
template <record X>
detail::PtrRank<X> rank_ptr(X* AP) {
    detail::PtrRank<X> LRank;
    detail::FillPtr<X>(LRank, AP);
    return LRank;
}

template <record X>
detail::ConstPtrRank<X> rank_ptr(const X* AP) {
    detail::ConstPtrRank<X> LRank;
    detail::FillConstPtr<X>(LRank, AP);
    return LRank;
}

template <record X>
detail::VarPtrRank<X> rank_ptr_var(X*& AV) {
    detail::VarPtrRank<X> LRank;
    detail::FillPtr<X>(LRank, AV);
    LRank.pp = &AV;
    return LRank;
}

template <record X>
detail::VarConstPtrRank<X> rank_ptr_var(const X*& AV) {
    detail::VarConstPtrRank<X> LRank;
    detail::FillConstPtr<X>(LRank, AV);
    LRank.pp = &AV;
    return LRank;
}

// A const or temporary record only reaches a value or const member (SEM takes
// a var member for a variable only), so const is cast away for the address
template <record X>
detail::ValueRank<std::remove_const_t<X>> rank_value(X& AV) {
    return detail::ValueRank<std::remove_const_t<X>>(const_cast<std::remove_const_t<X>*>(&AV));
}

template <record X>
detail::ValueRank<X> rank_value(X&& AV) {
    return detail::ValueRank<X>(&AV);
}

// An overload call whose members take a record (or a pointer to one) at
// different levels of its chain (SEM: TPCCall.ResolvedRanksExtensions): as
// overloads, each member's call operator taking the ranks in place of its
// record parameters, so clang ranks the members as inheritance did
template <class... S>
constexpr auto ranked_overloads(S*... AFns) {
    return detail::OverloadSet<detail::RankedMember<S>...>{detail::RankedMember<S>{AFns}...};
}

/*******************************************************************************
 * Unit tests (unitTestMode): main registers every test block, run_tests runs
 * them and returns the number that failed (the exit code). In a test block
 * test_<kind> records a failure and the test goes on; outside one
 * assert_<kind> prints "<file>:<line>: <message>" to stderr and ends the
 * program with exit code 1
 ******************************************************************************/

void register_test(const char* name, void (*fn)(), const char* file, std::int32_t line);

// Runs every registered test in order, each under the guard mechanism (a
// raise or a fault fails that test), prints the report; the failed count
std::int32_t run_tests();

void test_assert(bool condition, const char* file, std::int32_t line);
void assert_assert(bool condition, const char* file, std::int32_t line);
void test_assert_true(bool condition, const char* file, std::int32_t line);
void assert_assert_true(bool condition, const char* file, std::int32_t line);
void test_assert_false(bool condition, const char* file, std::int32_t line);
void assert_assert_false(bool condition, const char* file, std::int32_t line);
void test_assert_nil(const void* pointer, const char* file, std::int32_t line);
void assert_assert_nil(const void* pointer, const char* file, std::int32_t line);
void test_assert_not_nil(const void* pointer, const char* file, std::int32_t line);
void assert_assert_not_nil(const void* pointer, const char* file, std::int32_t line);
void test_fail(const std::string& message, const char* file, std::int32_t line);
void assert_fail(const std::string& message, const char* file, std::int32_t line);
void test_assert_equal_int(std::int64_t expected, std::int64_t actual, const char* file, std::int32_t line);
void assert_assert_equal_int(std::int64_t expected, std::int64_t actual, const char* file, std::int32_t line);
void test_assert_equal_uint(std::uint64_t expected, std::uint64_t actual, const char* file, std::int32_t line);
void assert_assert_equal_uint(std::uint64_t expected, std::uint64_t actual, const char* file, std::int32_t line);

// Equal when |expected - actual| <= 1e-9 * |expected| (1e-9 absolute when
// expected is 0)
void test_assert_equal_float(double expected, double actual, const char* file, std::int32_t line);
void assert_assert_equal_float(double expected, double actual, const char* file, std::int32_t line);
void test_assert_equal_str(const std::string& expected, const std::string& actual, const char* file,
    std::int32_t line);
void assert_assert_equal_str(const std::string& expected, const std::string& actual, const char* file,
    std::int32_t line);
void test_assert_equal_bool(bool expected, bool actual, const char* file, std::int32_t line);
void assert_assert_equal_bool(bool expected, bool actual, const char* file, std::int32_t line);
void test_assert_equal_ptr(const void* expected, const void* actual, const char* file, std::int32_t line);
void assert_assert_equal_ptr(const void* expected, const void* actual, const char* file, std::int32_t line);

} // namespace pcpp

/*******************************************************************************
 * Formatters of the print elements (E7). parse / format are templates over
 * the context (a range formats its elements through another context);
 * set_debug_format is how a range asks for the quoted form
 ******************************************************************************/

template <>
struct std::formatter<pcpp::PrintWChar, char> {
    std::formatter<std::string_view, char> text;
    bool debug = false;

    template <class ParseContext>
    constexpr auto parse(ParseContext& ctx) {
        return text.parse(ctx);
    }

    constexpr void set_debug_format() {
        debug = true;
    }

    template <class FormatContext>
    auto format(const pcpp::PrintWChar& arg, FormatContext& ctx) const {
        const std::string utf = pcpp::utf8(arg.value);
        if (!debug) {
            return text.format(std::string_view(utf), ctx);
        }
        return std::format_to(ctx.out(), "{}",
            pcpp::detail::quote_as_char(std::format("{:?}", std::string_view(utf))));
    }
};

template <>
struct std::formatter<pcpp::PrintCStr, char> {
    std::formatter<std::string_view, char> text;
    bool debug = false;

    template <class ParseContext>
    constexpr auto parse(ParseContext& ctx) {
        return text.parse(ctx);
    }

    constexpr void set_debug_format() {
        debug = true;
    }

    template <class FormatContext>
    auto format(const pcpp::PrintCStr& arg, FormatContext& ctx) const {
        if (arg.value == nullptr) {
            if (debug) {
                return std::format_to(ctx.out(), "nil");
            }
            return text.format(std::string_view("nil"), ctx);
        }
        if (!debug) {
            return text.format(std::string_view(arg.value), ctx);
        }
        return std::format_to(ctx.out(), "{:?}", std::string_view(arg.value));
    }
};

template <>
struct std::formatter<pcpp::PrintWCStr, char> {
    std::formatter<std::string_view, char> text;
    bool debug = false;

    template <class ParseContext>
    constexpr auto parse(ParseContext& ctx) {
        return text.parse(ctx);
    }

    constexpr void set_debug_format() {
        debug = true;
    }

    template <class FormatContext>
    auto format(const pcpp::PrintWCStr& arg, FormatContext& ctx) const {
        const std::string utf = pcpp::WCStr(arg.value);
        if (arg.value == nullptr && debug) {
            return std::format_to(ctx.out(), "nil");
        }
        if (!debug) {
            return text.format(std::string_view(utf), ctx);
        }
        return std::format_to(ctx.out(), "{:?}", std::string_view(utf));
    }
};
