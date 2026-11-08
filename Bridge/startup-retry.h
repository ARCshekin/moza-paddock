/* Retry only an early bootstrap exit, before a visible simulator session.
 * A content/runtime crash after a game window appears is never retried. */
static int retry_startup(unsigned int code, int had_window, unsigned long long elapsed_ms, unsigned int attempt) {
    return (code == 1 || code == 53) && !had_window && elapsed_ms < 10000 && attempt < 2;
}

/* Code 6 belongs to the launcher's duplicate-session protocol. Wine truncates
 * child NTSTATUS values to a Unix byte, so reserve that low byte as well.
 * The child's original full code remains in the diagnostic log. */
static unsigned int launcher_exit_code(unsigned int child_code) {
    return (child_code & 255u) == 6u ? 1u : child_code;
}
