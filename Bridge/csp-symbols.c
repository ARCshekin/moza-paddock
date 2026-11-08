/* AC-scoped dbghelp adapter. Supplements Wine's enumeration from the user's
 * PDB, never modifies game code or downloads a symbol table. */
#ifndef CSP_SYMBOLS_TEST
void *memset(void *destination, int value, unsigned long long size) {
 volatile unsigned char *p=destination; while(size--)*p++=(unsigned char)value; return destination;
}
#endif
typedef unsigned int U32;
typedef unsigned short U16;
typedef unsigned long long U64;
typedef void *PTR;
#ifndef CSP_SYMBOLS_TEST
#define API __declspec(dllimport)
#else
#define API extern
#endif
API int WriteFile(PTR, const void *, U32, U32 *, PTR);
API PTR LoadLibraryA(const char *);
API PTR GetModuleHandleA(const char *);
API PTR GetProcAddress(PTR, const char *);
API U32 GetModuleFileNameW(PTR, U16 *, U32);
API PTR CreateFileW(const U16 *, U32, U32, PTR, U32, U32, PTR);
API U32 GetFileSize(PTR, U32 *);
API int ReadFile(PTR, void *, U32, U32 *, PTR);
API int CloseHandle(PTR);
API PTR GetProcessHeap(void);
API PTR HeapAlloc(PTR, U32, U64);
API int HeapFree(PTR, U32, PTR);
typedef struct {
 U32 size, type; U64 reserved[2]; U32 index, bytes; U64 module;
 U32 flags; U64 value, address; U32 reg, scope, tag, length, capacity; char name[1];
} Symbol;
_Static_assert(__builtin_offsetof(Symbol,name)==84 && sizeof(Symbol)==88, "SYMBOL_INFO ABI");
typedef int (*Callback)(Symbol *, U32, PTR);
typedef int (*Enum)(PTR, U64, const char *, Callback, PTR);
static PTR self;
#ifndef CSP_SYMBOLS_TEST
int DllMain(PTR module, U32 reason, PTR reserved) { (void)reserved; if(reason==1)self=module; return 1; }
#endif
static U32 length(const char *s) { U32 n=0; while(s[n]) n++; return n; }
#ifndef CSP_SYMBOLS_TEST
static void trace(const char *text) {
 static const U16 path[]={'m','o','z','a','-','c','s','p','-','s','y','m','b','o','l','s','.','l','o','g',0};
 PTR f=CreateFileW(path,4,3,0,4,0x80,0); U32 written;
 WriteFile(f,text,length(text),&written,0);CloseHandle(f);
}
static void traceNumber(U32 n) { char b[12]; U32 i=11;b[i]=0;do{b[--i]=(char)('0'+n%10);n/=10;}while(n);trace(b+i);trace("\n"); }
#endif
static U64 hash(const char *s) { U64 h=14695981039346656037ull; while(*s) {h^=(unsigned char)*s++;h*=1099511628211ull;} return h?h:1; }
static int remember(U64 *seen,const char *name) {
 U64 h=hash(name); U32 slot=(U32)h&131071;
 for(U32 i=0;i<131072;i++,slot=(slot+1)&131071) {
  if(seen[slot]==h) return 0;
  if(!seen[slot]) {seen[slot]=h;return 1;}
 } return 0;
}
typedef struct { Callback callback; PTR context; U64 *seen; int cancelled; } Enumeration;
static int record(Symbol *s,U32 size,PTR context) {
 Enumeration *e=context; if(s->tag==5||s->tag==7)remember(e->seen,s->name);
 int result=e->callback(s,size,e->context); if(!result)e->cancelled=1; return result;
}
enum EmitKind { PUBLIC_DATA, FUNCTION, PUBLIC_FUNCTION, DATA };
static int emit(Enumeration *e,U64 base,U32 rva,const char *name,enum EmitKind kind) {
 union { U64 align; unsigned char bytes[sizeof(Symbol)+4096]; } storage={0};
 Symbol *s=(Symbol *)storage.bytes; U32 n=length(name); if(n>=4096)return 1;
 s->size=sizeof(Symbol);s->module=base;s->address=base+rva;s->tag=kind==FUNCTION?5:(kind==DATA?7:10);
 s->flags=kind==FUNCTION?0x800:(kind==PUBLIC_FUNCTION?0x400000:0);s->length=n;s->capacity=4096;
 for(U32 i=0;i<=n;i++)s->name[i]=name[i];
 return e->callback(s,0,e->context);
}
static void strip(char *s) {
 const char *words[]={"class ","struct ","enum ","union "};
 for(U32 w=0;w<4;w++)for(U32 i=0;s[i];) {
  U32 j=0;while(words[w][j]&&s[i+j]==words[w][j])j++;
  if(!words[w][j]&&(!i||s[i-1]=='<'||s[i-1]==','||s[i-1]=='('||s[i-1]==' ')) {
   U32 k=i;do{s[k]=s[k+j];}while(s[k++]);
  } else i++;
 }
}
/* Compare table GUID to the loaded executable's RSDS record. */
static int matches(unsigned char *base,unsigned char *guid) {
 U32 nt=*(U32 *)(base+60); if(nt>4096)return 0;
 U32 imageSize=*(U32 *)(base+nt+24+56);
 U32 rva=*(U32 *)(base+nt+184),size=*(U32 *)(base+nt+188);
 if(size>4096||rva>imageSize||size>imageSize-rva)return 0;
 for(U32 i=0;i+28<=size;i+=28) {
  unsigned char *d=base+rva+i; U32 data=*(U32 *)(d+20);
  if(*(U32 *)(d+12)!=2||data>imageSize||imageSize-data<24)continue;
  unsigned char *rsds=base+data;if(*(U32 *)rsds!=0x53445352)continue;
  for(U32 j=0;j<16;j++)if(rsds[4+j]!=guid[j])return 0;
  return 1;
 } return 0;
}
#ifndef CSP_SYMBOLS_TEST
int proxyEnum(PTR process,U64 base,const char *mask,Callback callback,PTR context) {
 trace("CSP symbols mask: "); if(mask)trace(mask); trace("\n");
 PTR real=LoadLibraryA("moza-dbghelp-wine.dll");
 Enum original=(Enum)GetProcAddress(real,"SymEnumSymbols"); if(!original)return 0;
 /* CSP requests this exact module-wide enumeration; every other call passes through. */
 const char *expected="acs!*";U32 i=0;while(mask&&expected[i]&&mask[i]==expected[i])i++;
 if(!mask||expected[i]||mask[i])return original(process,base,mask,callback,context);
 unsigned char *image=GetModuleHandleA("acs.exe");
 U16 path[1024];U32 n=GetModuleFileNameW(self,path,1024);if(!n||n>=1000)return original(process,base,mask,callback,context);
 while(n&&path[n-1]!='\\')n--;
 const char *name="moza-csp-symbols.bin";for(i=0;name[i];i++)path[n+i]=(U16)name[i];path[n+i]=0;
 PTR file=CreateFileW(path,0x80000000,1,0,3,0x80,0);
 if(file==(PTR)-1)return original(process,base,mask,callback,context);
 U32 size=GetFileSize(file,0),read=0;PTR heap=GetProcessHeap();
 unsigned char *table=size>=24&&size<16000000?HeapAlloc(heap,0,size):0;
 int valid=table&&ReadFile(file,table,size,&read,0)&&read==size;
 CloseHandle(file);
 if(valid)valid=*(U64 *)table==0x31594d5350435a4dull&&image&&matches(image,table+8);
 trace(valid?"CSP symbols: table accepted\n":"CSP symbols: table rejected\n");
 U64 *seen=valid?HeapAlloc(heap,8,131072*8):0;
 if(!seen) {if(table)HeapFree(heap,0,table);return original(process,base,mask,callback,context);}
 Enumeration e={callback,context,seen,0};int result=original(process,base,mask,record,&e);
 trace("Original result: ");traceNumber((U32)result);
 trace(e.cancelled?"Enumeration cancelled\n":"Enumeration completed\n");
 typedef U32 (*Undecorate)(const char *,char *,U32,U32);
 Undecorate undecorate=(Undecorate)GetProcAddress(real,"UnDecorateSymbolName");
 U32 publics=0,functions=0;
 for(U32 offset=24;!e.cancelled&&offset+12<=size;) {
  U32 rva=*(U32 *)(table+offset),function=*(U32 *)(table+offset+4),bytes=*(U32 *)(table+offset+8);offset+=12;
  if(!bytes||bytes>4096||bytes>size-offset||table[offset+bytes-1])break;
  char *symbol=(char *)(table+offset);offset+=bytes;
  publics++;
  if(function==2) {
   if(remember(seen,symbol)&&!emit(&e,(U64)image,rva,symbol,DATA))break;
   continue;
  }
  if(!emit(&e,(U64)image,rva,symbol,function?PUBLIC_FUNCTION:PUBLIC_DATA))break;
  if(symbol[0]=='?'&&undecorate) {
   char plain[4096];if(undecorate(symbol,plain,sizeof(plain),0x1000)) {
    strip(plain);if(remember(seen,plain)){functions++; if(!emit(&e,(U64)image,rva,plain,function?FUNCTION:DATA))break;}
   }
  }
 }
 trace("Publics: ");traceNumber(publics);trace("Functions: ");traceNumber(functions);
 trace("Supplement completed\n");
 HeapFree(heap,0,seen);HeapFree(heap,0,table);return result;
}

#endif
