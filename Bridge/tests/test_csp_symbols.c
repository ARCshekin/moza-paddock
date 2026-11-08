#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#define CSP_SYMBOLS_TEST
#include "../csp-symbols.c"
static enum EmitKind expectedKind;
static int accept(Symbol *s,U32 size,PTR context) {
 (void)size;int *count=context;(*count)++;
 assert(s->size==88 && s->address==0x140001234ull && s->module==0x140000000ull);
 assert(s->tag==(expectedKind==DATA?7:10));
 assert(s->flags==(expectedKind==PUBLIC_FUNCTION?0x400000:0));
 assert(!strcmp(s->name,"example"));return 1;
}
int main(void) {
 U64 *seen=calloc(131072,sizeof(U64));assert(seen);
 assert(remember(seen,"duplicate"));assert(!remember(seen,"duplicate"));assert(remember(seen,"different"));
 char plain[]="GameObject::addGameObject<class GhostCar>";strip(plain);assert(!strcmp(plain,"GameObject::addGameObject<GhostCar>"));
 int count=0;Enumeration e={accept,&count,seen,0};expectedKind=PUBLIC_FUNCTION;assert(emit(&e,0x140000000ull,0x1234,"example",PUBLIC_FUNCTION));assert(count==1);
 expectedKind=DATA;assert(emit(&e,0x140000000ull,0x1234,"example",DATA));assert(count==2);
 unsigned char image[1024]={0};U32 nt=128;memcpy(image+60,&nt,4);
 U32 size=sizeof(image),rva=512,bytes=28,type=2,rsds=600,magic=0x53445352;
 memcpy(image+nt+24+56,&size,4);memcpy(image+nt+184,&rva,4);memcpy(image+nt+188,&bytes,4);
 memcpy(image+rva+12,&type,4);memcpy(image+rva+20,&rsds,4);memcpy(image+rsds,&magic,4);
 unsigned char guid[16]={1,2,3};memcpy(image+rsds+4,guid,16);assert(matches(image,guid));guid[0]++;assert(!matches(image,guid));
 rva=1020;memcpy(image+nt+184,&rva,4);assert(!matches(image,guid));
 free(seen);puts("PASS CSP symbol ABI, public code flags, names, deduplication and executable GUID guard");
}
