"""Close only the Wine prefix used by an Assetto session."""
from pathlib import Path
import subprocess


def steam_running(prefix):
    processes = subprocess.check_output(['/bin/ps', '-axo', 'pid=,comm='], text=True).splitlines()
    candidates = []
    for line in processes:
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[1].replace('\\', '/').rsplit('/', 1)[-1].lower() == 'steam.exe':
            candidates.append(parts[0])
    for pid in candidates:
        opened = subprocess.run(['/usr/sbin/lsof', '-p', pid, '-Fn'], capture_output=True, text=True, timeout=5)
        if any(line.startswith('n' + str(prefix) + '/') for line in opened.stdout.splitlines()):
            return True
    return False


def shutdown(runtime):
    prefix = Path(runtime.prefix).resolve()
    wine = Path(runtime.wine)
    server = wine.with_name('wineserver')
    if not prefix.is_dir() or not wine.is_file() or not server.is_file():
        raise RuntimeError('Cannot identify the session Wine environment')
    env = runtime.environment()
    env['WINEPREFIX'] = str(prefix)
    for name in ('SteamAppId', 'SteamGameId'):
        env.pop(name, None)
    def run(arguments, timeout):
        try:
            return subprocess.run(arguments, env=env, stdin=subprocess.DEVNULL,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                  timeout=timeout).returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False
    # Do not start a new Steam instance merely to ask it to exit.
    if steam_running(prefix):
        run([str(wine)] + getattr(runtime, 'steam_shutdown_arguments', [str(runtime.steam / 'steam.exe'), '-shutdown']), 8)
        run([str(server), '-w'], 4)  # Give Steam time to flush its state.
    # Prefix-scoped wineserver shutdown also removes CEF, explorer and services.
    stopped = run([str(server), '-k'], 4)
    return run([str(server), '-w'], 5) and stopped
