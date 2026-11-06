/* Steam-only Wine compatibility shim. Original implementation, MIT.
 * Forward winmm exports; redirect GetCommandLineW imports in the browser
 * executable/libcef to opt into in-process GPU presentation. No code patching.
 */
typedef unsigned char U8;
typedef unsigned short U16;
typedef unsigned int U32;
typedef unsigned long long U64;
typedef void *PTR;
#define API __declspec(dllimport)
API U32 GetModuleFileNameW(PTR, U16 *, U32);
API PTR GetModuleHandleW(const U16 *);
API U16 *GetCommandLineW(void);
API int VirtualProtect(PTR, U64, U32, U32 *);
API int DisableThreadLibraryCalls(PTR);
API PTR CreateFileW(const U16 *, U32, U32, PTR, U32, U32, PTR);
API int WriteFile(PTR, const void *, U32, U32 *, PTR);
API int CloseHandle(PTR);
static U16 command[32768];
static U16 *commandLine(void) { return command; }
static int contains(const U16 *s, const char *word) {
    for (; *s; s++) { U32 i = 0; while (word[i] && s[i] == (U8)word[i]) i++; if (!word[i]) return 1; }
    return 0;
}
static int browser(void) {
    static U16 path[4096]; U32 count = GetModuleFileNameW(0, path, 4096);
    if (!count || count >= 4096) return 0;
    U16 *base = path; for (U16 *p = path; *p; p++) if (*p == '\\' || *p == '/') base = p+1;
    const char *name = "steamwebhelper.exe";
    for (U32 i = 0;; i++) {
        U16 c = base[i]; if (c >= 'A' && c <= 'Z') c += 'a'-'A';
        if (c != (U8)name[i]) return 0;
        if (!c) break;
    }
    const U16 *original = GetCommandLineW();
    if (contains(original, "--type=")) return 0;
    U32 n = 0; while (original[n] && n < 32000) { command[n] = original[n]; n++; }
    if (original[n]) return 0;
    const char *flags = " --in-process-gpu --disable-gpu --disable-gpu-compositing";
    while (*flags) command[n++] = (U8)*flags++;
    command[n] = 0; return 1;
}
static U32 read32(const U8 *p) { return *(const U32 *)p; }
static U32 redirect(PTR module) {
    if (!module) return 0;
    U8 *base = module;
    if (*(U16 *)base != 0x5a4d) return 0;
    U32 pe = read32(base+0x3c);
    if (pe > 0x100000 || read32(base+pe) != 0x4550 || *(U16 *)(base+pe+24) != 0x20b) return 0;
    U32 size = read32(base+pe+24+56), rva = read32(base+pe+24+120), count = 0;
    if (!rva || rva >= size) return 0;
    for (U32 at = rva; at+20 <= size && read32(base+at+12); at += 20) {
        U32 names = read32(base+at), slots = read32(base+at+16);
        if (!names || !slots || names >= size || slots >= size) continue;
        for (U32 i = 0; names+(U64)i*8+8 <= size && slots+(U64)i*8+8 <= size; i++) {
            U64 entry = *(U64 *)(base+names+(U64)i*8);
            if (!entry) break;
            if (entry >> 63 || entry+18 >= size) continue;
            const char *name = (const char *)(base+entry+2), *wanted = "GetCommandLineW";
            U32 j = 0; while (wanted[j] && name[j] == wanted[j]) j++;
            if (wanted[j] || name[j]) continue;
            PTR *slot = (PTR *)(base+slots+(U64)i*8); U32 old, ignored;
            if (VirtualProtect(slot, sizeof(*slot), 4, &old)) {
                *slot = (PTR)commandLine; VirtualProtect(slot, sizeof(*slot), old, &ignored); count++;
            }
        }
    }
    return count;
}
int DllMain(PTR module, U32 reason, PTR reserved) {
    (void)reserved;
    if (reason != 1) return 1;
    DisableThreadLibraryCalls(module);
    if (!browser()) return 1;
    static const U16 cef[] = {'l','i','b','c','e','f','.','d','l','l',0};
    U32 patched = redirect(GetModuleHandleW(0)) + redirect(GetModuleHandleW(cef));
    static const U16 log[] = {'C',':','\\','m','o','z','a','-','s','t','e','a','m','-','c','e','f','.','l','o','g',0};
    PTR file = CreateFileW(log, 0x40000000, 3, 0, 2, 0x80, 0);
    char message[] = "Steam CEF command-line imports redirected: 0\r\n"; U32 written;
    message[43] = (char)('0' + (patched < 10 ? patched : 9));
    WriteFile(file, message, sizeof(message)-1, &written, 0); CloseHandle(file);
    return 1;
}
