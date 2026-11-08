/* Per-game external-display launcher. Win64, no CRT, no global display changes.
 * Uses the non-primary monitor and keeps the game in a borderless full-display
 * window. STARTF_USESHOWWINDOW hides its first ShowWindow until it is placed. */
typedef unsigned int U32;
typedef unsigned short U16;
typedef unsigned long long U64;
typedef long long I64;
typedef void *PTR;
typedef struct { int left, top, right, bottom; } Rect;
typedef struct { U32 size; Rect monitor, work; U32 flags; U16 name[32]; } MonitorInfo;
typedef struct {
    U32 size; U16 *reserved, *desktop, *title;
    U32 x, y, width, height, columns, rows, fill, flags;
    U16 show, reservedBytes; PTR reservedData, input, output, error;
} Startup;
typedef struct { PTR process, thread; U32 pid, tid; } Process;
_Static_assert(sizeof(Startup) == 104 && sizeof(MonitorInfo) == 104, "Win64 ABI");
#define API __declspec(dllimport)
API int EnumDisplayMonitors(PTR, const Rect *, int (*)(PTR, PTR, Rect *, I64), I64);
API int GetMonitorInfoW(PTR, MonitorInfo *);
API int EnumWindows(int (*)(PTR, I64), I64);
API U32 GetWindowThreadProcessId(PTR, U32 *);
API int GetWindowRect(PTR, Rect *);
API int GetClientRect(PTR, Rect *);
API I64 GetWindowLongPtrW(PTR, int);
API I64 SetWindowLongPtrW(PTR, int, I64);
API int SetWindowPos(PTR, PTR, int, int, int, int, U32);
API int IsIconic(PTR);
API int ShowWindow(PTR, int);
API int SetForegroundWindow(PTR);
API int SetProcessDPIAware(void);
API int CreateProcessW(const U16 *, U16 *, PTR, PTR, int, U32, PTR, const U16 *, Startup *, Process *);
API U32 WaitForSingleObject(PTR, U32);
API int GetExitCodeProcess(PTR, U32 *);
API void ExitProcess(U32);
API int CloseHandle(PTR);
API U32 GetLastError(void);
API PTR CreateFileW(const U16 *, U32, U32, PTR, U32, U32, PTR);
API int WriteFile(PTR, const void *, U32, U32 *, PTR);
API PTR LoadLibraryW(const U16 *);
API PTR GetProcAddress(PTR, const char *);
API void Sleep(U32);
API U64 GetTickCount64(void);
API PTR CreateMutexW(PTR, int, const U16 *);
#include "steam-ready.h"
#include "startup-retry.h"
static unsigned char (*steamInitialize)(void);
static int initializeSteam(void) { return steamInitialize && steamInitialize() != 0; }
static PTR logFile;
static Rect target;
static int foundMonitor, hasExternal;
static U32 gamePID;
static PTR gameWindow;

static U32 string(char *out, U32 n, const char *s) { while (*s) out[n++] = *s++; return n; }
static U32 number(char *out, U32 n, int v) {
    if (v < 0) { out[n++] = '-'; v = -v; }
    char b[16]; U32 k = 0;
    do { b[k++] = (char)('0' + v % 10); v /= 10; } while (v);
    while (k) out[n++] = b[--k];
    return n;
}
static void logRect(const char *label, Rect r) {
    char b[256]; U32 n = string(b, 0, label), written;
    n = number(b, n, r.left); n = string(b, n, ","); n = number(b, n, r.top);
    n = string(b, n, " "); n = number(b, n, r.right - r.left);
    n = string(b, n, "x"); n = number(b, n, r.bottom - r.top);
    b[n++] = '\r'; b[n++] = '\n';
    WriteFile(logFile, b, n, &written, 0);
}
static void logExit(U32 code, U32 attempt, U64 elapsed) {
    char b[256]; U32 n = string(b, 0, "Simulator exit code="), written;
    n = number(b, n, (int)code); n = string(b, n, " attempt=");
    n = number(b, n, (int)attempt); n = string(b, n, " elapsed_ms=");
    n = number(b, n, elapsed > 2147483647 ? 2147483647 : (int)elapsed);
    b[n++] = '\r'; b[n++] = '\n'; WriteFile(logFile, b, n, &written, 0);
}
static int monitorCallback(PTR monitor, PTR dc, Rect *rect, I64 context) {
    (void)dc; (void)rect; (void)context;
    MonitorInfo info = {0}; info.size = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info)) return 1;
    int external = !(info.flags & 1);
    logRect(external ? "External monitor: " : "Primary monitor: ", info.monitor);
    if (!foundMonitor || (external && !hasExternal)) {
        target = info.monitor; foundMonitor = 1; hasExternal = external;
    }
    return 1;
}
static int windowCallback(PTR window, I64 context) {
    (void)context;
    U32 pid = 0;
    GetWindowThreadProcessId(window, &pid);
    if (pid != gamePID || (GetWindowLongPtrW(window, -16) & 0x40000000)) return 1;
    Rect r;
    if (GetClientRect(window, &r) && r.right >= 300 && r.bottom >= 200) {
        gameWindow = window; return 0;
    }
    return 1;
}
static int same(Rect a, Rect b) {
    return a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom;
}
void main(void) {
    static const U16 logName[] = {'m','o','z','a','-','d','i','s','p','l','a','y','.','l','o','g',0};
    static const U16 mutexName[] = {'L','o','c','a','l','\\','M','o','z','a','P','a','d','d','o','c','k','.','A','s','s','e','t','t','o','S','e','s','s','i','o','n',0};
    PTR sessionMutex = CreateMutexW(0, 0, mutexName);
    if (!sessionMutex || GetLastError() == 183) {
        ExitProcess(6);

    }
    logFile = CreateFileW(logName, 0x40000000, 3, 0, 2, 0x80, 0);
    SetProcessDPIAware();
    EnumDisplayMonitors(0, 0, monitorCallback, 0);
    if (!foundMonitor) ExitProcess(2);
    // Do not silently launch on the laptop if Wine cached only one display.
    if (!hasExternal) {
        logRect("External display unavailable; restart bottle: ", target);
        CloseHandle(logFile); ExitProcess(4);
    }
    logRect("Selected display: ", target);
    static const U16 steamName[] = {'.','/','s','t','e','a','m','_','a','p','i','6','4','.','d','l','l',0};
    PTR steam = LoadLibraryW(steamName);
    steamInitialize = steam ? (unsigned char (*)(void))GetProcAddress(steam, "SteamAPI_Init") : 0;
    void (*shutdown)(void) = steam ? (void (*)(void))GetProcAddress(steam, "SteamAPI_Shutdown") : 0;
    if (!shutdown || !wait_steam_ready(initializeSteam, Sleep, 60)) {
        logRect("Steam API unavailable; sign in and retry: ", (Rect){0});
        CloseHandle(logFile); ExitProcess(5);
    }
    /* Keep this API connection alive until the child exits. Releasing it
     * before CreateProcess can race Steam's game-process handoff. */
    void (*callbacks)(void) = (void (*)(void))GetProcAddress(steam, "SteamAPI_RunCallbacks");
    logRect("Steam API ready: ", (Rect){0});
    U32 attempt = 0;
launch_child:
    gameWindow = 0;
    U64 started = GetTickCount64();
    Startup startup = {0}; Process process = {0};
    startup.size = sizeof(startup);
    startup.flags = 1 | 2 | 4; /* USESHOWWINDOW, USESIZE, USEPOSITION */
    startup.show = 0; /* SW_HIDE until placed on the external display */
    startup.x = (U32)target.left; startup.y = (U32)target.top;
    startup.width = (U32)(target.right - target.left); startup.height = (U32)(target.bottom - target.top);
    U16 command[] = {'a','c','s','.','e','x','e',0};
    if (!CreateProcessW(0, command, 0, 0, 0, 0, 0, 0, &startup, &process)) {
        logRect("CreateProcess failed: ", (Rect){(int)GetLastError(), 0, 0, 0});
        ExitProcess(3);
    }
    CloseHandle(process.thread); gamePID = process.pid;
    int placed = 0, sawWindow = 0;
    while (WaitForSingleObject(process.process, 25) == 258) {
        if (callbacks) callbacks();
        if (!gameWindow) EnumWindows(windowCallback, 0);
        if (gameWindow) sawWindow = 1;
        if (!gameWindow || IsIconic(gameWindow)) continue;
        Rect current;
        if (!GetWindowRect(gameWindow, &current)) { gameWindow = 0; continue; }
        U64 style = (U64)GetWindowLongPtrW(gameWindow, -16);
        if (!placed || !same(current, target) || (style & 0x00c40000)) {
            SetWindowLongPtrW(gameWindow, -16, (I64)((style & ~0x00cf0000ull) | 0x80000000ull));
            SetWindowPos(gameWindow, 0, target.left, target.top,
                         target.right - target.left, target.bottom - target.top,
                         0x20 | 0x10 | 0x04); /* FRAMECHANGED, NOACTIVATE, NOZORDER */
            if (!placed) { ShowWindow(gameWindow, 5); SetForegroundWindow(gameWindow); }
            if (GetWindowRect(gameWindow, &current)) logRect("Game window: ", current);
            placed = 1;
        }
    }
    U32 code = 0;
    GetExitCodeProcess(process.process, &code);
    U64 elapsed = GetTickCount64() - started;
    logExit(code, attempt, elapsed);
    CloseHandle(process.process);
    if (retry_startup(code, sawWindow, elapsed, attempt)) {
        attempt++;
        logRect("Retrying early Steam bootstrap exit: ", (Rect){(int)code, (int)attempt, (int)code, (int)attempt});
        Sleep(2000);
        goto launch_child;
    }
    shutdown(); CloseHandle(sessionMutex); CloseHandle(logFile); ExitProcess(launcher_exit_code(code));
}
