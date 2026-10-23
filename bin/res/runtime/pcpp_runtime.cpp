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
 * pcpp_runtime.cpp - PaskalCPP C++ Runtime
 *
 * The runtime's one TU (API: research\runtime\api.md).
 ******************************************************************************/

#include "pcpp_runtime.h"

#include <algorithm>
#include <atomic>
#include <csetjmp>
#include <cstring>
#include <exception>
#include <mutex>
#include <new>
#include <unordered_map>

#if defined(_WIN32)
    #include <windows.h>
    #include <io.h>
    #include <fcntl.h>
    #include <malloc.h>
#else
    #include <signal.h>
    #include <pthread.h>
    #include <unistd.h>
    #include <dlfcn.h>
    #include <sys/resource.h>
    #if defined(__linux__)
        #include <sys/syscall.h>
    #endif
#endif

namespace pcpp {

#if defined(PCPP_DEBUG)
// The debug build's leak report (Memory, below)
void detail_report_leaks() noexcept;
#endif

namespace {

#if defined(PCPP_DEBUG) && !defined(PCPP_BUILD_DLL)
// Set by init (an exe, or a lib whose host called init): report at exit
std::atomic<bool> g_report_leaks_at_exit{false};

// The exe's leak report runs in this object's destructor. It is built before
// every other static object of the program (init_priority 101, the first one
// a program may use), so it is destroyed after them: a module variable that
// holds an own / ref object frees it before the report counts (an atexit
// call from init ran before them and reported it leaked)
struct LeakReporter {
    ~LeakReporter() {
        if (g_report_leaks_at_exit.load(std::memory_order_relaxed)) {
            detail_report_leaks();
        }
    }
};
[[gnu::init_priority(101)]] LeakReporter g_leak_reporter;
#endif

/*******************************************************************************
 * Exception state
 ******************************************************************************/

// The runtime's C++ exception: a raise. It owns its text, which travels with
// the throw (R21)
struct RuntimeException {
    std::int32_t Code;
    std::string Text;
};

// The last exception a guard of this thread caught (its code; the text and
// the C++ exception object itself, nullptr for a hardware fault, so
// Caught::pass_on raises the same one again)
thread_local std::int32_t t_exc_code = 0;

// This thread's text and exception object. Linux: they live in the thread's
// ThreadState (below), never in a thread_local with a destructor: glibc
// keeps a shared object loaded while any thread holds a thread_local it must
// destroy (__cxa_thread_atexit_impl), so a pcpp-built .so could never be
// unloaded by dlclose while such a thread lives. nullptr only when the
// state cannot be made (out of memory).
std::string* thread_exc_text() noexcept;
std::exception_ptr* thread_exc_object() noexcept;

#if defined(_WIN32)
thread_local std::string t_exc_text;
thread_local std::exception_ptr t_exc_object;

std::string* thread_exc_text() noexcept {
    return &t_exc_text;
}

std::exception_ptr* thread_exc_object() noexcept {
    return &t_exc_object;
}
#endif

// The one setter, noexcept: a text that cannot be copied leaves a fixed one,
// the code is kept. Never called from a fault handler
void set_exc(const std::int32_t code, const char* text) noexcept {
    std::string* LText = thread_exc_text();
    t_exc_code = code;
    if (LText == nullptr) {
        return;
    }
    try {
        LText->assign(text != nullptr ? text : "");
    }
    catch (...) {
        LText->clear();
    }
}

// The thread's exception object set (nothing when the state cannot be made)
void set_exc_object(const std::exception_ptr& object) noexcept {
    std::exception_ptr* LObject = thread_exc_object();
    if (LObject != nullptr) {
        *LObject = object;
    }
}

// One text per fault code, the same on every target
const char* fault_text(const std::int32_t code) noexcept {
    switch (code) {
        case EXC_DIV_BY_ZERO:         return "Divide by zero";
        case EXC_ACCESS_VIOLATION:    return "Access violation";
        case EXC_STACK_OVERFLOW:      return "Stack overflow";
        case EXC_INTEGER_OVERFLOW:    return "Numeric overflow";
        case EXC_ILLEGAL_INSTRUCTION: return "Illegal instruction";
        case EXC_BUS_ERROR:           return "Bus error";
        default:                      return "Hardware exception";
    }
}

/*******************************************************************************
 * Hardware faults
 ******************************************************************************/

#if defined(_WIN32)

// The VEH handler runs with no signal mask to restore: plain setjmp / longjmp
using JumpBuffer = jmp_buf;

#else

// POSIX: a fault handler runs with its signal blocked, and longjmp does not
// restore the mask (glibc, musl): the next fault of that kind would kill the
// process. sigsetjmp(buf, 1) saves the mask at guard entry; siglongjmp
// restores it
using JumpBuffer = sigjmp_buf;

#endif

// The innermost guard of this thread; nullptr outside every guard
thread_local JumpBuffer* t_jump_target = nullptr;

// A hardware fault outside every guard ends the program as an unhandled raise
// does, the same on every target: `unhandled exception <code>: <text>` on
// stderr, exit code 1 (TODO.md #13 (b), user ok 2026-10-15). It runs in a
// signal handler (POSIX) or with a broken stack (a stack overflow), so it
// builds the line in a fixed buffer and writes it with one system call: no
// allocation, no stdio. Output the program had not flushed yet stays lost
// (no stdio flush is safe here, and none happens on either target)
[[noreturn]] void report_unguarded_fault(const std::int32_t code) noexcept {
    static const char PREFIX[] = "unhandled exception ";
    char LLine[96];
    std::size_t LLen = 0;

    for (std::size_t LI = 0; PREFIX[LI] != '\0'; ++LI) {
        LLine[LLen++] = PREFIX[LI];
    }

    // The code in decimal (fault codes are small and positive)
    char LDigits[12];
    std::size_t LCount = 0;
    std::uint32_t LValue = static_cast<std::uint32_t>(code);
    do {
        LDigits[LCount++] = static_cast<char>('0' + (LValue % 10));
        LValue /= 10;
    } while ((LValue != 0) && (LCount < sizeof(LDigits)));
    while (LCount > 0) {
        LLine[LLen++] = LDigits[--LCount];
    }

    LLine[LLen++] = ':';
    LLine[LLen++] = ' ';
    const char* LText = fault_text(code);
    for (std::size_t LI = 0; (LText[LI] != '\0') && (LLen < sizeof(LLine) - 1); ++LI) {
        LLine[LLen++] = LText[LI];
    }
    LLine[LLen++] = '\n';

#if defined(_WIN32)
    HANDLE LErr = GetStdHandle(STD_ERROR_HANDLE);
    if ((LErr != nullptr) && (LErr != INVALID_HANDLE_VALUE)) {
        DWORD LWritten = 0;
        WriteFile(LErr, LLine, static_cast<DWORD>(LLen), &LWritten, nullptr);
    }
    // TerminateProcess, not exit: no DLL detach (a dll's finalize) and no
    // static destructor runs after the fault
    TerminateProcess(GetCurrentProcess(), 1);
    // Not reached; ends the noreturn path for the compiler
    std::_Exit(1);
#else
    ssize_t LIgnored = write(STDERR_FILENO, LLine, LLen);
    static_cast<void>(LIgnored);
    _exit(1);
#endif
}

#if defined(_WIN32)

// The exception codes that are hardware faults
bool is_hardware_fault(const DWORD code) noexcept {
    switch (code) {
        case EXCEPTION_ACCESS_VIOLATION:
        case EXCEPTION_INT_DIVIDE_BY_ZERO:
        case EXCEPTION_FLT_DIVIDE_BY_ZERO:
        case EXCEPTION_STACK_OVERFLOW:
        case EXCEPTION_INT_OVERFLOW:
        case EXCEPTION_ILLEGAL_INSTRUCTION:
        case EXCEPTION_PRIV_INSTRUCTION:
        case EXCEPTION_IN_PAGE_ERROR:
        case EXCEPTION_FLT_INVALID_OPERATION:
        case EXCEPTION_FLT_OVERFLOW:
        case EXCEPTION_FLT_UNDERFLOW:
            return true;
        default:
            return false;
    }
}

// A Windows exception code as an EXC_ code
std::int32_t fault_code(const DWORD code) noexcept {
    switch (code) {
        case EXCEPTION_ACCESS_VIOLATION:
        case EXCEPTION_IN_PAGE_ERROR:
            return EXC_ACCESS_VIOLATION;
        case EXCEPTION_INT_DIVIDE_BY_ZERO:
        case EXCEPTION_FLT_DIVIDE_BY_ZERO:
            return EXC_DIV_BY_ZERO;
        case EXCEPTION_STACK_OVERFLOW:
            return EXC_STACK_OVERFLOW;
        case EXCEPTION_INT_OVERFLOW:
        case EXCEPTION_FLT_OVERFLOW:
        case EXCEPTION_FLT_UNDERFLOW:
            return EXC_INTEGER_OVERFLOW;
        case EXCEPTION_ILLEGAL_INSTRUCTION:
        case EXCEPTION_PRIV_INSTRUCTION:
            return EXC_ILLEGAL_INSTRUCTION;
        default:
            return EXC_UNKNOWN;
    }
}

// Vectored exception handler: a hardware fault inside a guard jumps back to
// the guard with its code; everything else continues the search
LONG WINAPI veh_handler(PEXCEPTION_POINTERS ep) {
    const DWORD LCode = ep->ExceptionRecord->ExceptionCode;
    if ((t_jump_target == nullptr) || !is_hardware_fault(LCode)) {
        return EXCEPTION_CONTINUE_SEARCH;
    }
    longjmp(*t_jump_target, fault_code(LCode));
}

// Top-level filter: a hardware fault no guard and no C++ handler took. Windows
// calls it only when no debugger is attached, so under a debugger the fault
// still stops it at the faulting line (second chance)
LONG WINAPI unguarded_fault_filter(PEXCEPTION_POINTERS ep) {
    const DWORD LCode = ep->ExceptionRecord->ExceptionCode;
    if (!is_hardware_fault(LCode)) {
        return EXCEPTION_CONTINUE_SEARCH;
    }
    report_unguarded_fault(fault_code(LCode));
}

// The vectored handler this copy of the runtime added and the unhandled
// filter it replaced: a dll's copy removes the one and puts the other back
// when it unloads (restore_fault_handlers), so nothing is left pointing into
// unloaded code
PVOID g_veh_handle = nullptr;
LPTOP_LEVEL_EXCEPTION_FILTER g_previous_filter = nullptr;
bool g_filter_set = false;

void install_fault_handler() {
    // A function-local static is initialized exactly once, thread-safely
    static const bool s_installed = []() {
        g_veh_handle = AddVectoredExceptionHandler(1, veh_handler);
        g_previous_filter = SetUnhandledExceptionFilter(unguarded_fault_filter);
        g_filter_set = true;
        return true;
    }();
    static_cast<void>(s_installed);
}

#if defined(PCPP_BUILD_DLL)
// A dll detaching (DLL_PROCESS_DETACH): its vectored handler removed; the
// unhandled filter back to the one it replaced while the filter is still
// this copy's (a filter set after ours is its owner's and stays), never a
// previous one whose module is gone (another dll's copy, unloaded first)
void restore_fault_handlers() noexcept {
    if (g_veh_handle != nullptr) {
        RemoveVectoredExceptionHandler(g_veh_handle);
        g_veh_handle = nullptr;
    }
    if (g_filter_set) {
        LPTOP_LEVEL_EXCEPTION_FILTER LBack = g_previous_filter;
        HMODULE LOwner = nullptr;
        if ((LBack != nullptr) && !GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, reinterpret_cast<LPCWSTR>(LBack), &LOwner)) {
            LBack = nullptr;
        }
        const LPTOP_LEVEL_EXCEPTION_FILTER LNow = SetUnhandledExceptionFilter(LBack);
        if (LNow != unguarded_fault_filter) {
            SetUnhandledExceptionFilter(LNow);
        }
        g_filter_set = false;
    }
}
#endif

// After a fault, once the guard's frame is back: a caught stack overflow used
// up the thread's guard page; without re-arming it the next overflow on this
// thread is an unrecoverable access violation
void after_fault(const std::int32_t code) {
    if (code == EXC_STACK_OVERFLOW) {
        _resetstkoflw();
    }
}

#else

// Per-thread alternate signal stack: a stack overflow raises SIGSEGV with the
// thread's own stack exhausted, so the handler can only run on another one.
// The holder disables and frees it when the thread exits. The thread's stack
// bounds are kept with it, to tell a stack overflow from other SIGSEGVs
struct AltStack {
    void* Mem = nullptr;
    std::uintptr_t StackLo = 0;
    std::uintptr_t StackHi = 0;

    ~AltStack() {
        if (Mem != nullptr) {
            stack_t LStack;
            std::memset(&LStack, 0, sizeof(LStack));
            LStack.ss_flags = SS_DISABLE;
            sigaltstack(&LStack, nullptr);
            std::free(Mem);
        }
    }
};

// Everything a thread keeps that needs destroying, made at its first use and
// destroyed by the key's destructor when the thread exits (pthread keys
// pin no shared object). Only t_state, a plain pointer, is thread_local.
// The library's unload deletes the key (no destructor of this library runs
// after it) and frees the unloading thread's own state; a thread still
// alive then keeps its alternate stack installed (malloc'd memory, valid)
// and its state is left behind.
struct ThreadState {
    std::string ExcText;
    std::exception_ptr ExcObject;
    AltStack Alt;
};

thread_local ThreadState* t_state = nullptr;
pthread_key_t g_state_key;
pthread_once_t g_state_once = PTHREAD_ONCE_INIT;
bool g_state_key_made = false;

void destroy_thread_state(void* state) {
    delete static_cast<ThreadState*>(state);
}

void make_state_key() {
    g_state_key_made = pthread_key_create(&g_state_key, destroy_thread_state) == 0;
}

// This thread's state, made on first use; nullptr when it cannot be made
ThreadState* thread_state() noexcept {
    if (t_state != nullptr) {
        return t_state;
    }
    pthread_once(&g_state_once, make_state_key);
    if (!g_state_key_made) {
        return nullptr;
    }
    ThreadState* LState = new (std::nothrow) ThreadState();
    if (LState == nullptr) {
        return nullptr;
    }
    if (pthread_setspecific(g_state_key, LState) != 0) {
        delete LState;
        return nullptr;
    }
    t_state = LState;
    return LState;
}

// The unloading thread's own state, then the key (pcpp_dll_finalize)
void release_thread_states() noexcept {
    if (!g_state_key_made) {
        return;
    }
    if (t_state != nullptr) {
        pthread_setspecific(g_state_key, nullptr);
        delete t_state;
        t_state = nullptr;
    }
    pthread_key_delete(g_state_key);
    g_state_key_made = false;
}

std::string* thread_exc_text() noexcept {
    ThreadState* LState = thread_state();
    return (LState != nullptr) ? &LState->ExcText : nullptr;
}

std::exception_ptr* thread_exc_object() noexcept {
    ThreadState* LState = thread_state();
    return (LState != nullptr) ? &LState->ExcObject : nullptr;
}

// The thread's alternate stack record; a zeroed fallback when the state
// cannot be made (no stack recorded: no overflow detection on that thread)
AltStack& thread_alt_stack() noexcept {
    static AltStack s_none;
    ThreadState* LState = thread_state();
    return (LState != nullptr) ? LState->Alt : s_none;
}

constexpr std::size_t ALT_STACK_SIZE = 64 * 1024;
// A SIGSEGV this close to the low end of the thread's stack is a stack overflow
constexpr std::uintptr_t STACK_GUARD_SLACK = 64 * 1024;

void record_stack_bounds() {
    pthread_attr_t LAttr;
    if (pthread_getattr_np(pthread_self(), &LAttr) == 0) {
        void* LAddr = nullptr;
        std::size_t LSize = 0;
        if (pthread_attr_getstack(&LAttr, &LAddr, &LSize) == 0) {
            thread_alt_stack().StackLo = reinterpret_cast<std::uintptr_t>(LAddr);
            thread_alt_stack().StackHi = reinterpret_cast<std::uintptr_t>(LAddr) + LSize;
        }
        pthread_attr_destroy(&LAttr);
    }
#if defined(__linux__)
    // The main thread's stack grows on demand up to RLIMIT_STACK. glibc reports
    // that limit as the stack size; musl reports only what is mapped now, so a
    // later overflow would fall below the recorded bounds. Take the limit from
    // the kernel, whatever the libc
    if ((thread_alt_stack().StackHi != 0) && (syscall(SYS_gettid) == getpid())) {
        struct rlimit LLimit;
        if ((getrlimit(RLIMIT_STACK, &LLimit) == 0) && (LLimit.rlim_cur != RLIM_INFINITY) &&
            (static_cast<std::uintptr_t>(LLimit.rlim_cur) < thread_alt_stack().StackHi)) {
            const std::uintptr_t LLo = thread_alt_stack().StackHi - static_cast<std::uintptr_t>(LLimit.rlim_cur);
            if (LLo < thread_alt_stack().StackLo) {
                thread_alt_stack().StackLo = LLo;
            }
        }
    }
#endif
}

bool is_stack_overflow(void* fault_addr) {
    const std::uintptr_t LAddr = reinterpret_cast<std::uintptr_t>(fault_addr);
    // Runs in the signal handler: reads the state that exists, never makes it
    const std::uintptr_t LLo = (t_state != nullptr) ? t_state->Alt.StackLo : 0;
    if (LLo == 0) {
        return false;
    }
    const std::uintptr_t LBelow = (LLo > STACK_GUARD_SLACK) ? (LLo - STACK_GUARD_SLACK) : 0;
    return (LAddr >= LBelow) && (LAddr < LLo + STACK_GUARD_SLACK);
}

// A fault signal as an EXC_ code
std::int32_t signal_fault_code(const int sig, const siginfo_t* info) noexcept {
    std::int32_t LCode = EXC_UNKNOWN;
    switch (sig) {
        case SIGFPE:
            if ((info->si_code == FPE_INTOVF) || (info->si_code == FPE_FLTOVF) || (info->si_code == FPE_FLTUND)) {
                LCode = EXC_INTEGER_OVERFLOW;
            }
            else if ((info->si_code == FPE_INTDIV) || (info->si_code == FPE_FLTDIV)) {
                LCode = EXC_DIV_BY_ZERO;
            }
            break;
        case SIGSEGV:
            LCode = is_stack_overflow(info->si_addr) ? EXC_STACK_OVERFLOW : EXC_ACCESS_VIOLATION;
            break;
        case SIGBUS:
            LCode = EXC_BUS_ERROR;
            break;
        case SIGILL:
            LCode = EXC_ILLEGAL_INSTRUCTION;
            break;
        default:
            break;
    }
    return LCode;
}

void signal_handler(int sig, siginfo_t* info, void* uctx) {
    static_cast<void>(uctx);

    if (t_jump_target == nullptr) {
        // A signal sent by a process (kill, raise, sigqueue: si_code <= 0)
        // is no fault of the program: it gets its default action, as without
        // the runtime. Returning alone would re-run a faulting instruction
        // forever
        if (info->si_code <= 0) {
            signal(sig, SIG_DFL);
            ::raise(sig);
            return;
        }
        // A fault outside every guard: reported as an unhandled exception,
        // as on Windows
        report_unguarded_fault(signal_fault_code(sig, info));
    }

    siglongjmp(*t_jump_target, signal_fault_code(sig, info));
}

// The fault signals the runtime handles, and what each one's handler was
// before this copy of the runtime installed its own: a shared library's
// copy puts them back when it unloads (restore_fault_handlers), so no
// handler is left pointing into unmapped code
constexpr int FAULT_SIGNALS[] = { SIGFPE, SIGSEGV, SIGBUS, SIGILL };
struct sigaction g_previous_actions[4];
bool g_previous_saved[4] = { false, false, false, false };

void install_fault_handler() {
    // Process-wide handlers, installed exactly once (thread-safe local static)
    static const bool s_installed = []() {
        struct sigaction LAction;
        std::memset(&LAction, 0, sizeof(LAction));
        LAction.sa_sigaction = signal_handler;
        sigemptyset(&LAction.sa_mask);
        // SA_SIGINFO: si_code / si_addr. SA_ONSTACK: run on the alternate stack
        LAction.sa_flags = SA_SIGINFO | SA_ONSTACK;
        for (int LI = 0; LI < 4; ++LI) {
            g_previous_saved[LI] = sigaction(FAULT_SIGNALS[LI], &LAction, &g_previous_actions[LI]) == 0;
        }
        return true;
    }();
    static_cast<void>(s_installed);

    // Per-thread alternate stack, once per thread. A stack the program already
    // installed on this thread is kept
    if (thread_alt_stack().StackLo == 0) {
        stack_t LCurrent;
        if ((sigaltstack(nullptr, &LCurrent) == 0) && ((LCurrent.ss_flags & SS_DISABLE) == 0)) {
            record_stack_bounds();
            return;
        }
        void* LMem = std::malloc(ALT_STACK_SIZE);
        if (LMem == nullptr) {
            return;
        }
        stack_t LStack;
        std::memset(&LStack, 0, sizeof(LStack));
        LStack.ss_sp = LMem;
        LStack.ss_size = ALT_STACK_SIZE;
        if (sigaltstack(&LStack, nullptr) != 0) {
            std::free(LMem);
            return;
        }
        thread_alt_stack().Mem = LMem;
        record_stack_bounds();
    }
}

#if defined(PCPP_BUILD_DLL)
// A shared library unloading (so_unload): each fault signal whose handler is
// still this copy's goes back to the one it replaced, the program's own
// runtime's or the default. A handler someone installed after ours is theirs
// and stays. A previous handler that is no longer mapped (another library's
// copy, unloaded first) is never put back: the default instead.
void restore_fault_handlers() noexcept {
    for (int LI = 0; LI < 4; ++LI) {
        struct sigaction LNow;
        if (!g_previous_saved[LI] || (sigaction(FAULT_SIGNALS[LI], nullptr, &LNow) != 0)) {
            continue;
        }
        if (((LNow.sa_flags & SA_SIGINFO) != 0) && (LNow.sa_sigaction == signal_handler)) {
            struct sigaction LBack = g_previous_actions[LI];
            void* LEntry = ((LBack.sa_flags & SA_SIGINFO) != 0)
                ? reinterpret_cast<void*>(LBack.sa_sigaction)
                : reinterpret_cast<void*>(LBack.sa_handler);
            Dl_info LInfo;
            const bool LSpecial = (LBack.sa_handler == SIG_DFL) || (LBack.sa_handler == SIG_IGN);
            if (!LSpecial && (dladdr(LEntry, &LInfo) == 0)) {
                std::memset(&LBack, 0, sizeof(LBack));
                LBack.sa_handler = SIG_DFL;
                sigemptyset(&LBack.sa_mask);
            }
            sigaction(FAULT_SIGNALS[LI], &LBack, nullptr);
        }
        g_previous_saved[LI] = false;
    }
}
#endif

void after_fault(const std::int32_t code) {
    static_cast<void>(code);
}

#endif

/*******************************************************************************
 * Startup
 ******************************************************************************/

int g_argc = 0;
char** g_argv = nullptr;

void setup_console() {
#if defined(_WIN32)
    // UTF-8 code pages, binary stdout / stderr, VT sequences
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCP(CP_UTF8);
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
    HANDLE LOut = GetStdHandle(STD_OUTPUT_HANDLE);
    if (LOut != INVALID_HANDLE_VALUE) {
        DWORD LMode = 0;
        if (GetConsoleMode(LOut, &LMode)) {
            SetConsoleMode(LOut, LMode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        }
    }
#endif
}

// An unguarded raise or C++ exception: its code and text to stderr, exit 1.
// AException = the exception reported (nullptr: std::terminate without one).
// The ONE report: enter's catch and the terminate handler both end here
[[noreturn]] void report_unhandled(std::exception_ptr AException) noexcept {
    std::int32_t LCode = EXC_UNKNOWN;
    const char* LText = "std::terminate was called";
    std::string LOwned;
    try {
        std::exception_ptr LPending = AException;
        if (LPending) {
            try {
                std::rethrow_exception(LPending);
            }
            catch (const RuntimeException& e) {
                LCode = e.Code;
                LOwned = e.Text;
                LText = LOwned.c_str();
            }
            catch (const std::exception& e) {
                LCode = EXC_CPP;
                LOwned = e.what();
                LText = LOwned.c_str();
            }
            catch (...) {
                LCode = EXC_CPP;
                LText = "unknown C++ exception";
            }
        }
    }
    catch (...) {
        LText = "out of memory while reporting an exception";
    }
    // _Exit flushes nothing: what the program printed comes first, as written
    // (a pipe or a file holds stdout in its buffer)
    std::fflush(stdout);
    std::fprintf(stderr, "unhandled exception %d: %s\n", static_cast<int>(LCode), LText);
    std::fflush(stderr);
    std::_Exit(1);
}

// std::terminate without enter (a noexcept violation, a destructor throwing
// during unwinding): the same report
[[noreturn]] void on_terminate() noexcept {
    report_unhandled(std::current_exception());
}

} // namespace

void init(int argc, char** argv) {
    static const bool s_once = []() {
        install_fault_handler();
        setup_console();
        std::set_terminate(on_terminate);
#if defined(PCPP_DEBUG) && !defined(PCPP_BUILD_DLL)
        // Reported by g_leak_reporter's destructor: after main returns and
        // after every module variable is destroyed (a dll reports from its
        // own detach, below)
        g_report_leaks_at_exit.store(true, std::memory_order_relaxed);
#endif
        return true;
    }();
    static_cast<void>(s_once);
    if (argv != nullptr) {
        g_argc = argc;
        g_argv = argv;
    }
}

std::int32_t enter(std::int32_t (*AEntry)()) noexcept {
    // Every entry into PaskalCPP code from outside runs here (the emitter
    // writes main and the dll / lib hooks through it): an unhandled raise is
    // caught and reported by the runtime itself, never through the OS's
    // top-level filter, which Windows skips while a debugger is attached
    try {
        return AEntry();
    }
    catch (...) {
        report_unhandled(std::current_exception());
    }
}

std::int32_t param_count() {
    return (g_argc > 0) ? (g_argc - 1) : 0;
}

std::string param_str(const std::int32_t index) {
    if ((g_argv == nullptr) || (index < 0) || (index >= g_argc) || (g_argv[index] == nullptr)) {
        return std::string();
    }
    return std::string(g_argv[index]);
}

/*******************************************************************************
 * Exceptions
 ******************************************************************************/

[[noreturn]] void raise(const std::int32_t code, const std::string& msg) {
    // A text that cannot be copied throws std::bad_alloc instead: EXC_CPP
    throw RuntimeException{code, msg};
}

std::int32_t exc_code() {
    return t_exc_code;
}

std::string exc_msg() {
    const std::string* LText = thread_exc_text();
    return (LText != nullptr) ? *LText : std::string();
}

std::int32_t detail::guard_call(void (*fn)(void*), void* context) {
    install_fault_handler();

    JumpBuffer LBuffer;
    JumpBuffer* LOuter = t_jump_target;
    t_jump_target = &LBuffer;

    // 0 on the first return; a fault handler jumps back with the fault's code
#if defined(_WIN32)
    const int LJumped = setjmp(LBuffer);
#else
    const int LJumped = sigsetjmp(LBuffer, 1);
#endif

    if (LJumped == 0) {
        try {
            fn(context);
            t_jump_target = LOuter;
            return 0;
        }
        catch (const RuntimeException& e) {
            t_jump_target = LOuter;
            set_exc(e.Code, e.Text.c_str());
            set_exc_object(std::current_exception());
            return 1;
        }
        catch (const std::exception& e) {
            t_jump_target = LOuter;
            // Copied while the exception lives: it dies with this arm
            set_exc(EXC_CPP, e.what());
            set_exc_object(std::current_exception());
            return 1;
        }
        catch (...) {
            t_jump_target = LOuter;
            set_exc(EXC_CPP, "unknown C++ exception");
            set_exc_object(std::current_exception());
            return 1;
        }
    }

    // Reached through the fault handler; the text is set here, in normal context
    t_jump_target = LOuter;
    after_fault(LJumped);
    set_exc(LJumped, fault_text(LJumped));
    set_exc_object(nullptr);
    return 1;
}

Caught Caught::take(const std::int32_t caught) {
    // Copied now: a guard inside the finally overwrites the thread's last
    // caught exception
    Caught LCaught;
    if (caught != 0) {
        LCaught.FCaught = true;
        const std::exception_ptr* LObject = thread_exc_object();
        const std::string* LText = thread_exc_text();
        if (LObject != nullptr) {
            LCaught.FObject = *LObject;
        }
        LCaught.FCode = t_exc_code;
        if (LText != nullptr) {
            LCaught.FText = *LText;
        }
    }
    return LCaught;
}

void Caught::pass_on() const {
    if (!FCaught) {
        return;
    }
    // The same exception object (a raise keeps its code and text, a C++
    // exception its type); a hardware fault goes on as a raise of its code
    if (FObject) {
        std::rethrow_exception(FObject);
    }
    raise(FCode, FText);
}

/*******************************************************************************
 * Memory
 ******************************************************************************/

namespace {

#if defined(PCPP_DEBUG)

// Debug build: blocks handed out and blocks released (Myrissa's
// RT_AllocCount / RT_FreeCount; atomic: any thread may allocate)
std::atomic<std::uint64_t> g_alloc_count{0};
std::atomic<std::uint64_t> g_free_count{0};

#endif

void count_alloc() noexcept {
#if defined(PCPP_DEBUG)
    g_alloc_count.fetch_add(1, std::memory_order_relaxed);
#endif
}

void count_free() noexcept {
#if defined(PCPP_DEBUG)
    g_free_count.fetch_add(1, std::memory_order_relaxed);
#endif
}

#if defined(PCPP_DEBUG)

// PLAN-OBJECT O6: where a live own / ref object was built
struct ObjectSite {
    const char* File;
    std::int32_t Line;
};

// The live own / ref objects by address. Built on first use and never
// destroyed: the leak report runs at exit, after static destructors of
// objects built later than its registration
struct ObjectRegistry {
    std::mutex Lock;
    std::unordered_map<const void*, ObjectSite> Live;
};

ObjectRegistry& object_registry() noexcept {
    static ObjectRegistry* LRegistry = new ObjectRegistry();
    return *LRegistry;
}

#endif

} // namespace

void track_object(const void* p, const char* file, const std::int32_t line) noexcept {
#if defined(PCPP_DEBUG)
    if (p == nullptr) {
        return;
    }
    ObjectRegistry& LRegistry = object_registry();
    {
        std::lock_guard<std::mutex> LGuard(LRegistry.Lock);
        try {
            LRegistry.Live[p] = ObjectSite{file, line};
        } catch (...) {
            // The registry could not grow: the object is still counted
        }
    }
    count_alloc();
#else
    (void)p;
    (void)file;
    (void)line;
#endif
}

void untrack_object(const void* p) noexcept {
#if defined(PCPP_DEBUG)
    if (p == nullptr) {
        return;
    }
    ObjectRegistry& LRegistry = object_registry();
    std::lock_guard<std::mutex> LGuard(LRegistry.Lock);
    if (LRegistry.Live.erase(p) > 0) {
        count_free();
    }
#else
    (void)p;
#endif
}

void raise_nil_owner() {
    raise(EXC_ACCESS_VIOLATION, "access through a nil own / ref");
}

void raise_invalid_cast(const char* target) {
    raise(EXC_INVALID_CAST, std::string("invalid cast: the object is not a ") + target);
}

#if defined(PCPP_DEBUG)

// The leak report, once at shutdown (registered by init in an exe or lib;
// called after pcpp_dll_finalize in a dll); every own / ref object still
// alive names its creation site, in file and line order
void detail_report_leaks() noexcept {
    const std::uint64_t LAllocs = g_alloc_count.load(std::memory_order_relaxed);
    const std::uint64_t LFrees = g_free_count.load(std::memory_order_relaxed);
    std::fprintf(stdout, "[Heap] Allocs: %llu, Frees: %llu, Leaked: %lld\n", static_cast<unsigned long long>(LAllocs),
        static_cast<unsigned long long>(LFrees), static_cast<long long>(LAllocs - LFrees));
    ObjectRegistry& LRegistry = object_registry();
    std::lock_guard<std::mutex> LGuard(LRegistry.Lock);
    try {
        std::vector<ObjectSite> LSites;
        LSites.reserve(LRegistry.Live.size());
        for (const auto& LEntry : LRegistry.Live) {
            LSites.push_back(LEntry.second);
        }
        std::sort(LSites.begin(), LSites.end(), [](const ObjectSite& a, const ObjectSite& b) {
            const int LByFile = std::strcmp(a.File, b.File);
            if (LByFile != 0) {
                return LByFile < 0;
            }
            return a.Line < b.Line;
        });
        for (const ObjectSite& LSite : LSites) {
            std::fprintf(stdout, "[Heap] Leaked object created at %s(%d)\n", LSite.File, static_cast<int>(LSite.Line));
        }
    } catch (...) {
        // No memory left for the list: the counts above still stand
    }
    std::fflush(stdout);
}

#endif

void* get_mem(const std::int64_t size) {
    if (size == 0) {
        return nullptr;
    }
    if (size < 0) {
        raise(EXC_MEMORY, std::format("negative memory size {}", size));
    }
    void* LBlock = std::malloc(static_cast<std::size_t>(size));
    if (LBlock == nullptr) {
        raise(EXC_MEMORY, std::format("out of memory ({} bytes)", size));
    }
    count_alloc();
    return LBlock;
}

void* resize_mem(void* p, const std::int64_t size) {
    if (size < 0) {
        raise(EXC_MEMORY, std::format("negative memory size {}", size));
    }
    if (size == 0) {
        // Releases p (a block, or nothing for nullptr)
        free_mem(p);
        return nullptr;
    }
    // A failed realloc leaves p as it was
    void* LBlock = std::realloc(p, static_cast<std::size_t>(size));
    if (LBlock == nullptr) {
        raise(EXC_MEMORY, std::format("out of memory ({} bytes)", size));
    }
    // From nothing it is a new block; a block moved or grown is still one
    if (p == nullptr) {
        count_alloc();
    }
    return LBlock;
}

void free_mem(void* p) {
    if (p == nullptr) {
        return;
    }
    std::free(p);
    count_free();
}

[[noreturn]] void detail::raise_length(const std::int64_t length, const bool negative) {
    if (negative) {
        raise(EXC_MEMORY, std::format("negative length {}", length));
    }
    raise(EXC_MEMORY, std::format("out of memory (length {})", length));
}

/*******************************************************************************
 * Text
 ******************************************************************************/

namespace {

// Encodes the scalar value cp (never a surrogate, at most 0x10FFFF); returns
// the bytes written
std::size_t encode_utf8(const std::uint32_t cp, char* out) {
    if (cp < 0x80) {
        out[0] = static_cast<char>(cp);
        return 1;
    }
    if (cp < 0x800) {
        out[0] = static_cast<char>(0xC0 | (cp >> 6));
        out[1] = static_cast<char>(0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        out[0] = static_cast<char>(0xE0 | (cp >> 12));
        out[1] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
        out[2] = static_cast<char>(0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = static_cast<char>(0xF0 | (cp >> 18));
    out[1] = static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
    out[2] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
    out[3] = static_cast<char>(0x80 | (cp & 0x3F));
    return 4;
}

} // namespace

std::string utf8(const std::wstring& text) {
    std::string LResult;
    LResult.reserve(text.size());
    char LBuf[4];
    std::size_t LI = 0;
    while (LI < text.size()) {
        std::uint32_t LCp = static_cast<std::uint32_t>(text[LI]);
        LI++;
        if constexpr (sizeof(wchar_t) == 2) {
            // UTF-16: a valid pair is one code point, a lone surrogate U+FFFD
            if ((LCp >= 0xD800) && (LCp <= 0xDBFF) && (LI < text.size()) &&
                (static_cast<std::uint32_t>(text[LI]) >= 0xDC00) &&
                (static_cast<std::uint32_t>(text[LI]) <= 0xDFFF)) {
                LCp = 0x10000 + ((LCp - 0xD800) << 10) + (static_cast<std::uint32_t>(text[LI]) - 0xDC00);
                LI++;
            }
            else if ((LCp >= 0xD800) && (LCp <= 0xDFFF)) {
                LCp = 0xFFFD;
            }
        }
        else {
            // UTF-32: a surrogate or a value past U+10FFFF is not a character
            if (((LCp >= 0xD800) && (LCp <= 0xDFFF)) || (LCp > 0x10FFFF)) {
                LCp = 0xFFFD;
            }
        }
        LResult.append(LBuf, encode_utf8(LCp, LBuf));
    }
    return LResult;
}

std::string utf8(const wchar_t c) {
    // One code unit: a surrogate half alone is not a character (U+FFFD)
    return utf8(std::wstring(1, c));
}

std::string WCStr(const wchar_t* text) {
    if (text == nullptr) {
        return std::string("nil");
    }
    return utf8(std::wstring(text));
}

/*******************************************************************************
 * Sets
 ******************************************************************************/

[[noreturn]] void detail::raise_set_range(const SetOrdinal& value, const std::int64_t low, const std::int64_t high) {
    if (value.Fits) {
        raise(EXC_SET_RANGE, std::format("set element {} is out of range {}..{}", value.Value, low, high));
    }
    raise(EXC_SET_RANGE, std::format("set element above {} is out of range {}..{}",
        std::numeric_limits<std::int64_t>::max(), low, high));
}

/*******************************************************************************
 * Varargs
 ******************************************************************************/

[[noreturn]] void VaRaiseType(const char* AMember, const std::int32_t AIndex, const char* AStored,
    const char* AWanted) {
    raise(EXC_VARARGS_TYPE, std::format("varargs.{}({}): argument {} is {}", AMember, AWanted, AIndex, AStored));
}

[[noreturn]] void VaRaiseIndex(const char* AMember, const std::int32_t AIndex, const std::int32_t ACount) {
    raise(EXC_VARARGS_INDEX, std::format("varargs.{}: argument {} does not exist (count {})", AMember, AIndex,
        ACount));
}

/*******************************************************************************
 * Unit tests
 ******************************************************************************/

namespace {

struct TestInfo {
    const char* TestName;
    void (*Fn)();
    const char* File;
    std::int32_t Line;
};

std::vector<TestInfo> g_tests;

// The running test's state: failed, and the lines that say why
bool g_test_failed = false;
std::string g_test_report;

// Records one failure of the running test
void test_record(const std::string& message, const char* file, const std::int32_t line) {
    g_test_failed = true;
    g_test_report += std::format("  \xF0\x9F\x94\xB4 {}:{}: {}\n", file, line, message);
}

// A failure outside a test block: reported, then the program ends with exit
// code 1 on every target (as an unhandled raise; std::abort's status differs
// by target: 0xC0000409 on Windows, 134 on Linux)
[[noreturn]] void assert_report(const std::string& message, const char* file, const std::int32_t line) {
    // _Exit flushes nothing: what the program printed comes first
    std::fflush(stdout);
    std::fprintf(stderr, "%s:%d: %s\n", file, static_cast<int>(line), message.c_str());
    std::fflush(stderr);
    std::_Exit(1);
}

// One check per kind: the failure message, empty when the check holds
std::string check_assert(const bool condition) {
    return condition ? std::string() : std::string("testAssert failed");
}

std::string check_true(const bool condition) {
    return condition ? std::string() : std::string("testAssertTrue failed: expected true, got false");
}

std::string check_false(const bool condition) {
    return !condition ? std::string() : std::string("testAssertFalse failed: expected false, got true");
}

std::string check_nil(const void* pointer) {
    return (pointer == nullptr) ? std::string() : std::format("testAssertNil failed: expected nil, got {}", pointer);
}

std::string check_not_nil(const void* pointer) {
    return (pointer != nullptr) ? std::string() : std::string("testAssertNotNil failed: expected not nil, got nil");
}

std::string check_fail(const std::string& message) {
    return std::format("testFail: {}", message);
}

std::string check_equal_int(const std::int64_t expected, const std::int64_t actual) {
    return (expected == actual) ? std::string()
        : std::format("testAssertEqualInt failed: expected {}, got {}", expected, actual);
}

std::string check_equal_uint(const std::uint64_t expected, const std::uint64_t actual) {
    return (expected == actual) ? std::string()
        : std::format("testAssertEqualUInt failed: expected {}, got {}", expected, actual);
}

std::string check_equal_float(const double expected, const double actual) {
    // Relative tolerance, absolute when expected is 0 (Myra)
    const double LDiff = (expected > actual) ? (expected - actual) : (actual - expected);
    const double LScale = (expected < 0) ? -expected : expected;
    const double LLimit = (expected == 0) ? 1e-9 : 1e-9 * LScale;
    return (LDiff <= LLimit) ? std::string()
        : std::format("testAssertEqualFloat failed: expected {}, got {}", expected, actual);
}

std::string check_equal_str(const std::string& expected, const std::string& actual) {
    return (expected == actual) ? std::string()
        : std::format("testAssertEqualStr failed: expected \"{}\", got \"{}\"", expected, actual);
}

std::string check_equal_bool(const bool expected, const bool actual) {
    return (expected == actual) ? std::string()
        : std::format("testAssertEqualBool failed: expected {}, got {}", expected, actual);
}

std::string check_equal_ptr(const void* expected, const void* actual) {
    return (expected == actual) ? std::string()
        : std::format("testAssertEqualPtr failed: expected {}, got {}", expected, actual);
}

// Runs one registered test: its function, under the guard mechanism
void run_one(void* context) {
    (*static_cast<void (**)()>(context))();
}

} // namespace

void register_test(const char* name, void (*fn)(), const char* file, const std::int32_t line) {
    g_tests.push_back(TestInfo{name, fn, file, line});
}

std::int32_t run_tests() {
    std::int32_t LPassed = 0;
    std::int32_t LFailed = 0;

    // Box-drawing header (UTF-8)
    std::string LBar;
    for (int LI = 0; LI < 62; LI++) {
        LBar += "\xE2\x95\x90";
    }
    std::printf("\n\xE2\x95\x94%s\xE2\x95\x97\n", LBar.c_str());
    std::printf("\xE2\x95\x91                     Unit Test Runner                         \xE2\x95\x91\n");
    std::printf("\xE2\x95\x9A%s\xE2\x95\x9D\n\n", LBar.c_str());
    std::printf("Running %d test(s)...\n\n", static_cast<int>(g_tests.size()));

    for (const TestInfo& LTest : g_tests) {
        g_test_failed = false;
        g_test_report.clear();
        void (*LFn)() = LTest.Fn;
        if (detail::guard_call(run_one, static_cast<void*>(&LFn)) != 0) {
            test_record(std::format("test raised exception {}: {}", exc_code(), exc_msg()), LTest.File, LTest.Line);
        }
        if (g_test_failed) {
            std::printf("\xE2\x9D\x8C FAIL: %s\n%s", LTest.TestName, g_test_report.c_str());
            LFailed++;
        }
        else {
            std::printf("\xE2\x9C\x85 PASS: %s\n", LTest.TestName);
            LPassed++;
        }
    }

    std::string LLine;
    for (int LI = 0; LI < 64; LI++) {
        LLine += "\xE2\x95\x90";
    }
    std::printf("\n%s\nResults: %d passed, %d failed, %d total\n%s\n", LLine.c_str(), static_cast<int>(LPassed),
        static_cast<int>(LFailed), static_cast<int>(g_tests.size()), LLine.c_str());
    std::fflush(stdout);
    // The exit code is the failed count, at most 255 on every target: Linux
    // keeps only the low 8 bits of an exit status, so 256 failures read as 0
    // (a pass) there; the Results line above holds the real count
    constexpr std::int32_t LExitMax = 255;
    return (LFailed > LExitMax) ? LExitMax : LFailed;
}

// test_<kind> records a failure; assert_<kind> reports it and exits 1

void test_assert(const bool condition, const char* file, const std::int32_t line) {
    const std::string LMessage = check_assert(condition);
    if (!LMessage.empty()) {
        test_record(LMessage, file, line);
    }
}

void assert_assert(const bool condition, const char* file, const std::int32_t line) {
    const std::string LMessage = check_assert(condition);
    if (!LMessage.empty()) {
        assert_report(LMessage, file, line);
    }
}

void test_assert_true(const bool condition, const char* file, const std::int32_t line) {
    const std::string LMessage = check_true(condition);
    if (!LMessage.empty()) {
        test_record(LMessage, file, line);
    }
}

void assert_assert_true(const bool condition, const char* file, const std::int32_t line) {
    const std::string LMessage = check_true(condition);
    if (!LMessage.empty()) {
        assert_report(LMessage, file, line);
    }
}

void test_assert_false(const bool condition, const char* file, const std::int32_t line) {
    const std::string LMessage = check_false(condition);
    if (!LMessage.empty()) {
        test_record(LMessage, file, line);
    }
}

void assert_assert_false(const bool condition, const char* file, const std::int32_t line) {
    const std::string LMessage = check_false(condition);
    if (!LMessage.empty()) {
        assert_report(LMessage, file, line);
    }
}

void test_assert_nil(const void* pointer, const char* file, const std::int32_t line) {
    const std::string LMessage = check_nil(pointer);
    if (!LMessage.empty()) {
        test_record(LMessage, file, line);
    }
}

void assert_assert_nil(const void* pointer, const char* file, const std::int32_t line) {
    const std::string LMessage = check_nil(pointer);
    if (!LMessage.empty()) {
        assert_report(LMessage, file, line);
    }
}

void test_assert_not_nil(const void* pointer, const char* file, const std::int32_t line) {
    const std::string LMessage = check_not_nil(pointer);
    if (!LMessage.empty()) {
        test_record(LMessage, file, line);
    }
}

void assert_assert_not_nil(const void* pointer, const char* file, const std::int32_t line) {
    const std::string LMessage = check_not_nil(pointer);
    if (!LMessage.empty()) {
        assert_report(LMessage, file, line);
    }
}

void test_fail(const std::string& message, const char* file, const std::int32_t line) {
    test_record(check_fail(message), file, line);
}

void assert_fail(const std::string& message, const char* file, const std::int32_t line) {
    assert_report(check_fail(message), file, line);
}

void test_assert_equal_int(const std::int64_t expected, const std::int64_t actual, const char* file,
    const std::int32_t line) {
    const std::string LMessage = check_equal_int(expected, actual);
    if (!LMessage.empty()) {
        test_record(LMessage, file, line);
    }
}

void assert_assert_equal_int(const std::int64_t expected, const std::int64_t actual, const char* file,
    const std::int32_t line) {
    const std::string LMessage = check_equal_int(expected, actual);
    if (!LMessage.empty()) {
        assert_report(LMessage, file, line);
    }
}

void test_assert_equal_uint(const std::uint64_t expected, const std::uint64_t actual, const char* file,
    const std::int32_t line) {
    const std::string LMessage = check_equal_uint(expected, actual);
    if (!LMessage.empty()) {
        test_record(LMessage, file, line);
    }
}

void assert_assert_equal_uint(const std::uint64_t expected, const std::uint64_t actual, const char* file,
    const std::int32_t line) {
    const std::string LMessage = check_equal_uint(expected, actual);
    if (!LMessage.empty()) {
        assert_report(LMessage, file, line);
    }
}

void test_assert_equal_float(const double expected, const double actual, const char* file, const std::int32_t line) {
    const std::string LMessage = check_equal_float(expected, actual);
    if (!LMessage.empty()) {
        test_record(LMessage, file, line);
    }
}

void assert_assert_equal_float(const double expected, const double actual, const char* file,
    const std::int32_t line) {
    const std::string LMessage = check_equal_float(expected, actual);
    if (!LMessage.empty()) {
        assert_report(LMessage, file, line);
    }
}

void test_assert_equal_str(const std::string& expected, const std::string& actual, const char* file,
    const std::int32_t line) {
    const std::string LMessage = check_equal_str(expected, actual);
    if (!LMessage.empty()) {
        test_record(LMessage, file, line);
    }
}

void assert_assert_equal_str(const std::string& expected, const std::string& actual, const char* file,
    const std::int32_t line) {
    const std::string LMessage = check_equal_str(expected, actual);
    if (!LMessage.empty()) {
        assert_report(LMessage, file, line);
    }
}

void test_assert_equal_bool(const bool expected, const bool actual, const char* file, const std::int32_t line) {
    const std::string LMessage = check_equal_bool(expected, actual);
    if (!LMessage.empty()) {
        test_record(LMessage, file, line);
    }
}

void assert_assert_equal_bool(const bool expected, const bool actual, const char* file, const std::int32_t line) {
    const std::string LMessage = check_equal_bool(expected, actual);
    if (!LMessage.empty()) {
        assert_report(LMessage, file, line);
    }
}

void test_assert_equal_ptr(const void* expected, const void* actual, const char* file, const std::int32_t line) {
    const std::string LMessage = check_equal_ptr(expected, actual);
    if (!LMessage.empty()) {
        test_record(LMessage, file, line);
    }
}

void assert_assert_equal_ptr(const void* expected, const void* actual, const char* file, const std::int32_t line) {
    const std::string LMessage = check_equal_ptr(expected, actual);
    if (!LMessage.empty()) {
        assert_report(LMessage, file, line);
    }
}

} // namespace pcpp

/*******************************************************************************
 * Built-in data (PLAN-RESDATA): the bounds of this image's section and its
 * key-ordered index. This TU is linked once into every exe and dll, so each
 * image has exactly one pair of bounds and reads only its own entries
 ******************************************************************************/

#if defined(_WIN32)
// COFF: the linker sorts a section's $ groups by name, so these two zero
// records bracket every .pcppres$m contribution. Both are 32 bytes and
// 32-aligned (ResEntry), so the records between them line up
__attribute__((section(".pcppres$a"), used)) static const ::pcpp::ResEntry pcpp_resdata_begin = {};
__attribute__((section(".pcppres$z"), used)) static const ::pcpp::ResEntry pcpp_resdata_end = {};
#else
// ELF: the linker defines these for a section named as a C identifier. Weak:
// an image without entries has no section, both are then nullptr. Hidden: the
// reference must resolve inside this image, never to a dll's section
extern "C" const ::pcpp::ResEntry __start_pcppres[] __attribute__((weak, visibility("hidden")));
extern "C" const ::pcpp::ResEntry __stop_pcppres[] __attribute__((weak, visibility("hidden")));
#endif

namespace pcpp {

namespace {

// The section's records with a key, sorted by key (byte-wise: char_traits<char>
// compares as unsigned char). Walked by address, not by pointer arithmetic
// across objects; a record with key nullptr is the linker's padding (or a
// marker) and is skipped
std::vector<const ResEntry*> resdata_build_index() {
    std::uintptr_t LFrom;
    std::uintptr_t LTo;
#if defined(_WIN32)
    LFrom = reinterpret_cast<std::uintptr_t>(&pcpp_resdata_begin) + sizeof(ResEntry);
    LTo = reinterpret_cast<std::uintptr_t>(&pcpp_resdata_end);
#else
    LFrom = reinterpret_cast<std::uintptr_t>(__start_pcppres);
    LTo = reinterpret_cast<std::uintptr_t>(__stop_pcppres);
#endif
    std::vector<const ResEntry*> LResult;
    for (std::uintptr_t LAt = LFrom; LAt + sizeof(ResEntry) <= LTo; LAt += sizeof(ResEntry)) {
        const ResEntry* LEntry = reinterpret_cast<const ResEntry*>(LAt);
        if (LEntry->key != nullptr) {
            LResult.push_back(LEntry);
        }
    }
    // stable: two records of one key (only hand-written C++ records: the
    // linker refuses a key two PaskalCPP holders add, its key symbol pcpp_rk_)
    // keep their place, so a lookup finds the same one on every run
    std::stable_sort(LResult.begin(), LResult.end(), [](const ResEntry* ALeft, const ResEntry* ARight) {
        return std::string_view(ALeft->key) < std::string_view(ARight->key);
    });
    return LResult;
}

// Built on the first call (a function-local static: thread-safe)
const std::vector<const ResEntry*>& resdata_index() {
    static const std::vector<const ResEntry*> LIndex = resdata_build_index();
    return LIndex;
}

} // namespace

const ResEntry* resdata_find(const std::string_view key) {
    const std::vector<const ResEntry*>& LIndex = resdata_index();
    const auto LAt = std::lower_bound(LIndex.begin(), LIndex.end(), key, [](const ResEntry* AEntry, const std::string_view AKey) {
        return std::string_view(AEntry->key) < AKey;
    });
    if (LAt == LIndex.end() || std::string_view((*LAt)->key) != key) {
        return nullptr;
    }
    return *LAt;
}

std::int64_t resdata_count() {
    return static_cast<std::int64_t>(resdata_index().size());
}

const char* resdata_key_at(const std::int64_t index) {
    const std::vector<const ResEntry*>& LIndex = resdata_index();
    if (index < 0 || index >= static_cast<std::int64_t>(LIndex.size())) {
        return nullptr;
    }
    return LIndex[static_cast<std::size_t>(index)]->key;
}

} // namespace pcpp

/*******************************************************************************
 * DLL / shared object entry (PCPP_BUILD_DLL): the emitted main module defines
 * the two hooks
 ******************************************************************************/

#if defined(PCPP_BUILD_DLL)

extern "C" void pcpp_dll_initialize();
extern "C" void pcpp_dll_finalize();

#if defined(_WIN32)

// The entry point Windows names; it must be global
extern "C" BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    static_cast<void>(instance);
    static_cast<void>(reserved);
    if (reason == DLL_PROCESS_ATTACH) {
        pcpp_dll_initialize();
    }
    else if (reason == DLL_PROCESS_DETACH) {
        pcpp_dll_finalize();
        // No fault handler of this dll may stay installed once it is gone
        pcpp::restore_fault_handlers();
#if defined(PCPP_DEBUG)
        // The dll's own heap counts, after its finalizers
        pcpp::detail_report_leaks();
#endif
    }
    return TRUE;
}

#else

// This library's C++ ABI exit handle (the compiler emits it hidden, one per
// shared object) and libc's finalizer. The library's own __cxa_atexit
// registrations carry &__dso_handle, so finalizing it runs and removes
// exactly this library's module-static / local-static destructors.
extern "C" void* __dso_handle;
extern "C" void __cxa_finalize(void*);

namespace pcpp {
namespace {

__attribute__((constructor)) void so_load() {
    pcpp_dll_initialize();
}

__attribute__((destructor)) void so_unload() {
    pcpp_dll_finalize();
    // Run and remove this library's own C++ static destructors now, while its
    // code is still mapped: a destructor left on libc's exit list would run
    // against unmapped code at process exit (glibc does not always finalize a
    // dlclosed object's handlers on unload)
    __cxa_finalize(&__dso_handle);
    // No fault handler of this library may stay installed once it is gone
    restore_fault_handlers();
    // No thread-state destructor of this library may run once it is gone
    release_thread_states();
#if defined(PCPP_DEBUG)
    // The shared object's own counts, after its finalizers
    detail_report_leaks();
#endif
}

} // namespace
} // namespace pcpp

#endif

#endif
