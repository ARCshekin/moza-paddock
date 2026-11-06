/* Run as steamwebhelper.exe in the managed prefix: no Valve code needed. */
typedef unsigned int U32;
typedef unsigned short U16;
typedef void *PTR;
#define API __declspec(dllimport)
API PTR LoadLibraryW(const U16 *);
API PTR GetProcAddress(PTR,const char *);
API PTR GetStdHandle(U32);
API U16 *GetCommandLineW(void);
API int WriteFile(PTR,const void *,U32,U32 *,PTR);
API void ExitProcess(U32);
static int contains(const U16 *s,const char *word) { for(;*s;s++){U32 n=0;while(word[n] && s[n]==(unsigned char)word[n])n++;if(!word[n])return 1;}return 0; }
static void say(const char *s) { U32 n=0,w;while(s[n])n++;WriteFile(GetStdHandle((U32)-11),s,n,&w,0); }
void main(void) {
    static const U16 name[]={'w','i','n','m','m','.','d','l','l',0};
    PTR module=LoadLibraryW(name);
    if(!module){say("FAIL winmm load\n");ExitProcess(2);}
    U32 (*tick)(void)=(U32 (*)(void))GetProcAddress(module,"timeGetTime");
    if(!tick || !tick()){say("FAIL winmm forwarding\n");ExitProcess(3);}
    const U16 *line=GetCommandLineW();
    int child=contains(line,"--type="), scoped=contains(line,"--expect-browser");
    int injected=contains(line,"--in-process-gpu");
    if(injected != (scoped && !child)){say("FAIL CEF argument scope\n");ExitProcess(4);}
    say("PASS Wine winmm forwarding and CEF IAT command-line scope\n");ExitProcess(0);
}
