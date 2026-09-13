/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * Tiny Windows 98 guest-side launcher.  This deliberately has no C runtime:
 * WinMainCRTStartup is the PE entry point and every imported routine is
 * declared below.  Keep the imports limited to KERNEL32 and USER32 APIs that
 * shipped with Windows 98.
 */

typedef char CHAR;
typedef CHAR *LPSTR;
typedef const CHAR *LPCSTR;
typedef unsigned char BYTE;
typedef BYTE *LPBYTE;
typedef unsigned short WORD;
typedef unsigned long DWORD;
typedef unsigned int UINT;
typedef int BOOL;
typedef void *HANDLE;
typedef void *HWND;
typedef void *HINSTANCE;
typedef long LRESULT;
typedef unsigned long WPARAM;
typedef long LPARAM;
typedef LRESULT (__stdcall *WNDPROC)(HWND, UINT, WPARAM, LPARAM);

typedef struct _STARTUPINFOA {
    DWORD cb; LPSTR lpReserved; LPSTR lpDesktop; LPSTR lpTitle;
    DWORD dwX; DWORD dwY; DWORD dwXSize; DWORD dwYSize;
    DWORD dwXCountChars; DWORD dwYCountChars; DWORD dwFillAttribute;
    DWORD dwFlags; WORD wShowWindow; WORD cbReserved2; LPBYTE lpReserved2;
    HANDLE hStdInput; HANDLE hStdOutput; HANDLE hStdError;
} STARTUPINFOA;

typedef struct _PROCESS_INFORMATION {
    HANDLE hProcess; HANDLE hThread; DWORD dwProcessId; DWORD dwThreadId;
} PROCESS_INFORMATION;

typedef struct _WNDCLASSA {
    UINT style; WNDPROC lpfnWndProc; int cbClsExtra; int cbWndExtra;
    HINSTANCE hInstance; HANDLE hIcon; HANDLE hCursor; HANDLE hbrBackground;
    LPCSTR lpszMenuName; LPCSTR lpszClassName;
} WNDCLASSA;

typedef struct tagMSG {
    HWND hwnd; UINT message; WPARAM wParam; LPARAM lParam;
    DWORD time; long pt_x; long pt_y;
} MSG;

__declspec(dllimport) DWORD __stdcall GetPrivateProfileStringA(LPCSTR, LPCSTR, LPCSTR, LPSTR, DWORD, LPCSTR);
__declspec(dllimport) BOOL __stdcall WritePrivateProfileStringA(LPCSTR, LPCSTR, LPCSTR, LPCSTR);
__declspec(dllimport) BOOL __stdcall CreateProcessA(LPCSTR, LPSTR, void *, void *, BOOL, DWORD, void *, LPCSTR, STARTUPINFOA *, PROCESS_INFORMATION *);
__declspec(dllimport) DWORD __stdcall WaitForSingleObject(HANDLE, DWORD);
__declspec(dllimport) BOOL __stdcall GetExitCodeProcess(HANDLE, DWORD *);
__declspec(dllimport) BOOL __stdcall CloseHandle(HANDLE);
__declspec(dllimport) DWORD __stdcall GetLastError(void);
__declspec(dllimport) void __stdcall ExitProcess(DWORD);
__declspec(dllimport) BOOL __stdcall ExitWindowsEx(DWORD, DWORD);
__declspec(dllimport) int __stdcall MessageBoxA(HWND, LPCSTR, LPCSTR, unsigned int);
__declspec(dllimport) HINSTANCE __stdcall GetModuleHandleA(LPCSTR);
__declspec(dllimport) unsigned short __stdcall RegisterClassA(const WNDCLASSA *);
__declspec(dllimport) HWND __stdcall CreateWindowExA(DWORD, LPCSTR, LPCSTR, DWORD, int, int, int, int, HWND, HANDLE, HINSTANCE, void *);
__declspec(dllimport) LRESULT __stdcall DefWindowProcA(HWND, UINT, WPARAM, LPARAM);
__declspec(dllimport) BOOL __stdcall GetMessageA(MSG *, HWND, UINT, UINT);
__declspec(dllimport) BOOL __stdcall TranslateMessage(const MSG *);
__declspec(dllimport) LRESULT __stdcall DispatchMessageA(const MSG *);
__declspec(dllimport) void __stdcall PostQuitMessage(int);

#define INFINITE 0xFFFFFFFFUL
#define WAIT_FAILED 0xFFFFFFFFUL
#define EWX_SHUTDOWN 0x00000001UL
#define WM_ENDSESSION 0x0016U
#define ERROR_CLASS_ALREADY_EXISTS 1410UL
#define MB_OK 0x00000000U
#define MB_ICONEXCLAMATION 0x00000030U

#define INI_PATH "C:\\FLASHBACK\\LAUNCH.INI"
#define STATE_PATH "E:\\STATE.INI"
#define PATH_CAPACITY 1024U
#define ARGUMENT_CAPACITY 2048U
#define COMMAND_CAPACITY 4096U

/* Static storage avoids the compiler's stack-probe helper in a no-CRT PE. */
static char executable[PATH_CAPACITY];
static char working_directory[PATH_CAPACITY];
static char configured_directory[PATH_CAPACITY];
static char arguments[ARGUMENT_CAPACITY];
static char command_line[COMMAND_CAPACITY];
static STARTUPINFOA startup;
static PROCESS_INFORMATION process;
static WNDCLASSA shutdown_class;
static MSG shutdown_message;
static HWND shutdown_window;
static BOOL shutdown_completed;
static const char shutdown_class_name[] = "FlashbackShutdownObserver";

static unsigned int text_length(const char *text) {
    unsigned int count = 0;
    while (text[count] != '\0') { ++count; }
    return count;
}

static void copy_text(char *destination, unsigned int capacity, const char *source) {
    unsigned int index = 0;
    if (capacity == 0) { return; }
    while (source[index] != '\0' && index + 1 < capacity) {
        destination[index] = source[index];
        ++index;
    }
    destination[index] = '\0';
}

static void append_character(char *destination, unsigned int capacity, unsigned int *length, char value) {
    if (*length + 1 < capacity) {
        destination[*length] = value;
        ++*length;
        destination[*length] = '\0';
    }
}

static void append_text(char *destination, unsigned int capacity, unsigned int *length, const char *source) {
    unsigned int index = 0;
    while (source[index] != '\0') {
        append_character(destination, capacity, length, source[index]);
        ++index;
    }
}

/* Quote one Windows command-line argument without invoking a shell. */
static void append_quoted_argument(char *destination, unsigned int capacity, unsigned int *length, const char *argument) {
    unsigned int index = 0;
    append_character(destination, capacity, length, '"');
    while (argument[index] != '\0') {
        unsigned int slashes = 0;
        while (argument[index] == '\\') { ++slashes; ++index; }
        if (argument[index] == '"') {
            while (slashes != 0) { append_character(destination, capacity, length, '\\'); append_character(destination, capacity, length, '\\'); --slashes; }
            append_character(destination, capacity, length, '\\');
            append_character(destination, capacity, length, '"');
            ++index;
        } else {
            while (slashes != 0) { append_character(destination, capacity, length, '\\'); --slashes; }
            if (argument[index] != '\0') { append_character(destination, capacity, length, argument[index]); ++index; }
        }
    }
    /* Backslashes before the closing quote need doubling. */
    index = text_length(argument);
    while (index != 0 && argument[index - 1] == '\\') { append_character(destination, capacity, length, '\\'); --index; }
    append_character(destination, capacity, length, '"');
}

static void decimal(DWORD value, char *destination) {
    char reversed[16];
    unsigned int count = 0;
    unsigned int index = 0;
    do { reversed[count] = (char)('0' + (value % 10)); value /= 10; ++count; } while (value != 0);
    while (count != 0) { --count; destination[index] = reversed[count]; ++index; }
    destination[index] = '\0';
}

static void write_state(const char *key, DWORD value) {
    char value_text[16];
    decimal(value, value_text);
    WritePrivateProfileStringA("State", key, value_text, STATE_PATH);
}

/* Windows broadcasts WM_ENDSESSION only when the requested logoff/shutdown is
 * actually ending this process's session. ExitWindowsEx returning true merely
 * means that Windows accepted the request, so it is intentionally not a
 * completion signal. The hidden top-level window keeps this tiny helper alive
 * long enough to receive the broadcast. */
static LRESULT __stdcall shutdown_window_proc(HWND window, UINT message, WPARAM w_param, LPARAM l_param) {
    (void)window;
    (void)l_param;
    if (message == WM_ENDSESSION) {
        if (w_param != 0) {
            WritePrivateProfileStringA("State", "shutdown", "completed", STATE_PATH);
            /* Flush the profile mapping before Windows tears the process down. */
            WritePrivateProfileStringA((LPCSTR)0, (LPCSTR)0, (LPCSTR)0, STATE_PATH);
            shutdown_completed = 1;
        }
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(window, message, w_param, l_param);
}

static BOOL create_shutdown_observer(void) {
    unsigned int index;
    for (index = 0; index < sizeof(shutdown_class); ++index) { ((BYTE *)&shutdown_class)[index] = 0; }
    shutdown_class.lpfnWndProc = shutdown_window_proc;
    shutdown_class.hInstance = GetModuleHandleA((LPCSTR)0);
    shutdown_class.lpszClassName = shutdown_class_name;
    if (RegisterClassA(&shutdown_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) { return 0; }
    shutdown_window = CreateWindowExA(0, shutdown_class_name, shutdown_class_name, 0, 0, 0, 0, 0,
                                      (HWND)0, (HANDLE)0, shutdown_class.hInstance, (void *)0);
    return shutdown_window != (HWND)0;
}

static void executable_directory(const char *executable, char *directory, unsigned int capacity) {
    unsigned int length = text_length(executable);
    while (length != 0) {
        --length;
        if (executable[length] == '\\' || executable[length] == '/') {
            unsigned int index;
            if (length + 1 >= capacity) { directory[0] = '\0'; return; }
            for (index = 0; index < length; ++index) { directory[index] = executable[index]; }
            directory[length] = '\0';
            return;
        }
    }
    directory[0] = '\0';
}

static BOOL is_absolute_windows_path(const char *path) {
    return (path[0] >= 'A' && path[0] <= 'Z' && path[1] == ':' && (path[2] == '\\' || path[2] == '/')) ||
           (path[0] >= 'a' && path[0] <= 'z' && path[1] == ':' && (path[2] == '\\' || path[2] == '/')) ||
           (path[0] == '\\' && path[1] == '\\');
}

void WinMainCRTStartup(void) {
    unsigned int command_length = 0;
    DWORD result;
    DWORD exit_code;
    unsigned int index;

    if (GetPrivateProfileStringA("Launch", "executable", "", executable, PATH_CAPACITY, INI_PATH) == 0 || !is_absolute_windows_path(executable)) {
        MessageBoxA((HWND)0, "Configure an absolute executable path in C:\\FLASHBACK\\LAUNCH.INI, then start Flashback again.", "Flashback setup required", MB_OK | MB_ICONEXCLAMATION);
        write_state("error", 1);
        ExitProcess(1);
    }
    GetPrivateProfileStringA("Launch", "workingDirectory", "", configured_directory, PATH_CAPACITY, INI_PATH);
    GetPrivateProfileStringA("Launch", "arguments", "", arguments, ARGUMENT_CAPACITY, INI_PATH);
    if (configured_directory[0] != '\0' && !is_absolute_windows_path(configured_directory)) {
        MessageBoxA((HWND)0, "The workingDirectory value in C:\\FLASHBACK\\LAUNCH.INI must be an absolute path.", "Flashback setup required", MB_OK | MB_ICONEXCLAMATION);
        write_state("error", 1);
        ExitProcess(1);
    }
    if (configured_directory[0] != '\0') { copy_text(working_directory, PATH_CAPACITY, configured_directory); }
    else { executable_directory(executable, working_directory, PATH_CAPACITY); }

    if (text_length(executable) * 2U + text_length(arguments) + 3U >= COMMAND_CAPACITY) {
        write_state("error", 2);
        ExitProcess(2);
    }
    command_line[0] = '\0';
    append_quoted_argument(command_line, COMMAND_CAPACITY, &command_length, executable);
    if (arguments[0] != '\0') { append_character(command_line, COMMAND_CAPACITY, &command_length, ' '); append_text(command_line, COMMAND_CAPACITY, &command_length, arguments); }
    for (index = 0; index < sizeof(startup); ++index) { ((BYTE *)&startup)[index] = 0; }
    for (index = 0; index < sizeof(process); ++index) { ((BYTE *)&process)[index] = 0; }
    startup.cb = sizeof(startup);

    if (!CreateProcessA(executable, command_line, (void *)0, (void *)0, 0, 0, (void *)0,
                        working_directory[0] == '\0' ? (LPCSTR)0 : working_directory, &startup, &process)) {
        write_state("error", GetLastError());
        ExitProcess(3);
    }
    write_state("started", 1);
    result = WaitForSingleObject(process.hProcess, INFINITE);
    if (result == WAIT_FAILED) {
        write_state("error", GetLastError());
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        ExitProcess(4);
    }
    if (!GetExitCodeProcess(process.hProcess, &exit_code)) {
        write_state("error", GetLastError());
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        ExitProcess(5);
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    write_state("exit", exit_code);
    /* A game error is not a clean game session and must never ask Windows to
       close. The host treats this as recoverable diagnostic evidence. */
    if (exit_code != 0) {
        write_state("error", exit_code);
        ExitProcess(6);
    }
    if (!create_shutdown_observer()) {
        write_state("error", GetLastError());
        ExitProcess(7);
    }
    WritePrivateProfileStringA("State", "shutdown", "requested", STATE_PATH);
    /* This API only confirms that Windows accepted the request. It does not
       prove shutdown completed; the host must not promote a disk checkpoint
       from this marker or an emulator EXIT 0 alone. */
    if (!ExitWindowsEx(EWX_SHUTDOWN, 0)) {
        write_state("error", GetLastError());
        ExitProcess(8);
    }
    while (GetMessageA(&shutdown_message, (HWND)0, 0, 0) > 0) {
        TranslateMessage(&shutdown_message);
        DispatchMessageA(&shutdown_message);
    }
    if (!shutdown_completed) { write_state("error", 9); ExitProcess(9); }
    ExitProcess(0);
}
