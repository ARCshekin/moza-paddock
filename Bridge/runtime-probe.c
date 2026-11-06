/* Standalone D3D11 smoke check: no game, Steam account or HID access. */
typedef unsigned int U32;
typedef long long I64;
typedef void *PTR;
#define API __declspec(dllimport)
API PTR LoadLibraryW(const unsigned short *);
API PTR GetProcAddress(PTR, const char *);
API PTR GetStdHandle(U32);
API int WriteFile(PTR, const void *, U32, U32 *, PTR);
API void ExitProcess(U32);
API int EnumDisplayMonitors(PTR, const void *, int (*)(PTR, PTR, PTR, I64), I64);
static U32 monitors;
static int monitor(PTR a, PTR b, PTR c, I64 d) { (void)a; (void)b; (void)c; (void)d; monitors++; return 1; }
static void output(const char *s) { U32 size = 0, written; while (s[size]) size++; WriteFile(GetStdHandle((U32)-11), s, size, &written, 0); }
static void hex(U32 value) { char s[11] = "0x00000000"; for (int i = 0; i < 8; i++) s[9-i] = "0123456789abcdef"[(value >> (i*4)) & 15]; output(s); }
void main(void) {
    static const unsigned short name[] = {'d','3','d','1','1','.','d','l','l',0};
    PTR module = LoadLibraryW(name);
    if (!module) { output("D3D11 library unavailable\n"); ExitProcess(2); }
    typedef int (*CreateDevice)(PTR, U32, PTR, U32, const U32 *, U32, U32, PTR *, U32 *, PTR *);
    CreateDevice create = (CreateDevice)GetProcAddress(module, "D3D11CreateDevice");
    if (!create) { output("D3D11CreateDevice missing\n"); ExitProcess(3); }
    PTR device = 0, context = 0; U32 level = 0;
    int result = create(0, 1, 0, 0, 0, 0, 7, &device, &level, &context);
    output("D3D11 HRESULT="); hex((U32)result); output(" featureLevel="); hex(level); output("\n");
    EnumDisplayMonitors(0, 0, monitor, 0);
    output("Monitor count="); hex(monitors); output("\n");
    if (context) ((U32 (*)(PTR))(*(PTR **)context)[2])(context);
    if (device) ((U32 (*)(PTR))(*(PTR **)device)[2])(device);
    ExitProcess(result < 0 ? 4 : 0);
}
