#include <assert.h>
#include "../steam-ready.h"
#include "../startup-retry.h"
static unsigned calls, pauses, ready_after;
static int initialize(void) { return ++calls >= ready_after; }
static void pause_ms(unsigned int ms) { assert(ms == 500); pauses++; }
int main(void) {
    ready_after = 3;
    assert(wait_steam_ready(initialize, pause_ms, 40));
    assert(calls == 3 && pauses == 2);
    calls = pauses = 0; ready_after = 100;
    assert(!wait_steam_ready(initialize, pause_ms, 40));
    assert(calls == 40 && pauses == 39);
    assert(!wait_steam_ready(0, pause_ms, 40));
    assert(!wait_steam_ready(initialize, 0, 40));
    assert(!wait_steam_ready(initialize, pause_ms, 0));
    assert(retry_startup(1, 0, 1500, 0));
    assert(retry_startup(53, 0, 1500, 1));
    assert(!retry_startup(1, 0, 1500, 2));
    assert(!retry_startup(1, 1, 1500, 0));
    assert(!retry_startup(1, 0, 10000, 0));
    assert(!retry_startup(99, 0, 1500, 0));
    assert(!retry_startup(0, 0, 1500, 0));
    return 0;
}
