/* Windows keyboard events are restricted to this foreground game process.
 * No macOS event injection or background key repeats. */
#ifdef CFB_TEST
extern int test_game_foreground(void);
extern void test_key(U32, int);
#define game_foreground test_game_foreground
#define game_key test_key
#else
IMPORT PTR GetForegroundWindow(void);
IMPORT U32 GetWindowThreadProcessId(PTR, U32 *);
typedef struct { U32 type, pad; U16 vk, scan; U32 flags, time, pad2; U64 extra, unused; } KeyInput;
_Static_assert(sizeof(KeyInput) == 40, "Win64 INPUT ABI");
IMPORT U32 SendInput(U32, const KeyInput *, int);
static int game_foreground(void) {
    U32 pid = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &pid);
    return pid != 0 && pid == GetCurrentProcessId();
}
static void game_key(U32 vk, int down) {
    U32 flags = (down ? 0u : 2u) | (vk >= 0x25 && vk <= 0x28 ? 1u : 0u);
    KeyInput key = {1,0,(U16)vk,0,flags,0,0,0,0};
    SendInput(1, &key, sizeof(KeyInput));
}
#endif
static U64 keyboardLock;
#ifdef CFB_TEST
extern void test_lock(U64 *);
extern void test_unlock(U64 *);
#define key_lock() test_lock(&keyboardLock)
#define key_unlock() test_unlock(&keyboardLock)
#else
#define key_lock() AcquireSRWLockExclusive(&keyboardLock)
#define key_unlock() ReleaseSRWLockExclusive(&keyboardLock)
#endif
static U32 previousKeys, heldKeys;
static U64 releaseAt[6];
static const U32 actionKeys[] = {0x1b,0x0d,0x25,0x27,0x26,0x28};
static void keyboard_reset(void) {
    key_lock();
    for (U32 i=0;i<6;i++) if (heldKeys & (1u<<i)) game_key(actionKeys[i],0);
    heldKeys=0;
    key_unlock();
}
static void keyboard_actions(U32 actions) {
    key_lock();
    U32 rising = actions & ~previousKeys;
    previousKeys = actions;
    U64 now=unix_ms();
    int foreground=game_foreground();
    for (U32 i=0;i<6;i++) {
        U32 bit=1u<<i;
        if ((heldKeys&bit) && (!foreground || now>=releaseAt[i])) {
            game_key(actionKeys[i],0); heldKeys &= ~bit;
        }
        if ((rising&bit) && foreground) {
            game_key(actionKeys[i],1); heldKeys |= bit; releaseAt[i]=now+60;
        }
    }
    key_unlock();
}
