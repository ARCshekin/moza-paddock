#include <assert.h>
#include <stdio.h>
#include <string.h>
#define __declspec(x)
#include "../steam-cef.c"
static const char *fake_name = "C:/Steam/steamwebhelper.exe";
static U16 fake_line[1024];
static int protections;
U32 GetModuleFileNameW(PTR p, U16 *out, U32 cap) { (void)p; U32 i=0; for (; fake_name[i] && i+1<cap; i++) out[i]=(U8)fake_name[i]; out[i]=0; return i; }
PTR GetModuleHandleW(const U16 *p) { (void)p; return 0; }
U16 *GetCommandLineW(void) { return fake_line; }
int VirtualProtect(PTR p, U64 n, U32 mode, U32 *old) { (void)p; (void)n; (void)mode; *old=4; protections++; return 1; }
int DisableThreadLibraryCalls(PTR p) { (void)p; return 1; }
PTR CreateFileW(const U16 *a,U32 b,U32 c,PTR d,U32 e,U32 f,PTR g) { (void)a;(void)b;(void)c;(void)d;(void)e;(void)f;(void)g;return 0; }
int WriteFile(PTR a,const void *b,U32 c,U32 *d,PTR e) { (void)a;(void)b;(void)c;(void)d;(void)e;return 1; }
int CloseHandle(PTR p) { (void)p;return 1; }
static void line(const char *s) { U32 i=0; for (;s[i];i++) fake_line[i]=(U8)s[i]; fake_line[i]=0; }
static void put32(U8 *image, U32 at, U32 value) { memcpy(image+at,&value,4); }
int main(void) {
    line("steamwebhelper.exe -cachedir=example"); assert(browser());
    assert(contains(command, "--in-process-gpu") && contains(command, "--disable-gpu-compositing"));
    line("steamwebhelper.exe --type=renderer"); assert(!browser());
    fake_name="C:/games/acs.exe"; line("acs.exe"); assert(!browser());
    _Alignas(8) U8 image[4096]={0};
    image[0]='M';image[1]='Z';put32(image,0x3c,128);put32(image,128,0x4550);
    image[152]=0x0b; image[153]=2; put32(image,152+56,sizeof(image));put32(image,152+120,512);
    put32(image,512,600);put32(image,512+12,700);put32(image,512+16,640);
    *(U64 *)(image+600)=720;memcpy(image+722,"GetCommandLineW",16);
    *(U64 *)(image+640)=0x1234;
    assert(redirect(image)==1 && *(PTR *)(image+640)==(PTR)commandLine && protections==2);
    memcpy(image+722,"GetTickCount64",15);protections=0;
    assert(redirect(image)==0 && protections==0);
    image[0]=0; assert(redirect(image)==0);assert(redirect(0)==0);
    puts("PASS CEF shim: browser scope, child exclusion, bounded IAT redirection, restored protection");
}
