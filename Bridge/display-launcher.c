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
    int placed = 0;
    while (WaitForSingleObject(process.process, 25) == 258) {
        if (!gameWindow) EnumWindows(windowCallback, 0);
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
    CloseHandle(process.process); CloseHandle(logFile); ExitProcess(code);
}
