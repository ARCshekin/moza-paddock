/* Retry only an early bootstrap exit, before a visible simulator session.
 * A content/runtime crash after a game window appears is never retried. */
static int retry_startup(unsigned int code, int had_window, unsigned long long elapsed_ms, unsigned int attempt) {
    return (code == 1 || code == 53) && !had_window && elapsed_ms < 10000 && attempt < 2;
}
