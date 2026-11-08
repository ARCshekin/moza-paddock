/* A live Steam account can appear in the registry before the client IPC is ready.
 * Only the real, game-provided Steam API decides readiness. */
static int wait_steam_ready(int (*initialize)(void), void (*pause_ms)(unsigned int), unsigned int attempts) {
    if (!initialize || !pause_ms || !attempts) return 0;
    for (unsigned int i = 0; i < attempts; i++) {
        if (initialize()) return 1;
        if (i + 1 < attempts) pause_ms(500);
    }
    return 0;
}
