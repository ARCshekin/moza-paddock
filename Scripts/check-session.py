#!/usr/bin/env python3
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import patch
import subprocess
from runtime.session import shutdown

with TemporaryDirectory() as temporary:
    root = Path(temporary); prefix = root/'prefix'; prefix.mkdir()
    wine = root/'wine'; wine.touch(); wine.with_name('wineserver').touch()
    runtime = SimpleNamespace(prefix=prefix, wine=wine, steam=prefix/'Steam',
                              environment=lambda: {'WINEPREFIX':'wrong', 'SteamAppId':'244210'})
    calls = []
    def run(arguments, **kwargs):
        assert kwargs['env']['WINEPREFIX'] == str(prefix.resolve())
        assert 'SteamAppId' not in kwargs['env']
        calls.append(arguments)
        if arguments[-1] == '-w' and len(calls) == 2 and calls[0][-1] == '-shutdown':
            raise subprocess.TimeoutExpired(arguments, 4)
        return SimpleNamespace(returncode=0)
    with patch('runtime.session.steam_running', return_value=True), patch('runtime.session.subprocess.run', side_effect=run):
        assert shutdown(runtime)
    assert calls[0][-1] == '-shutdown' and calls[2][-1] == '-k'
    calls.clear()
    with patch('runtime.session.steam_running', return_value=False), patch('runtime.session.subprocess.run', side_effect=run):
        assert shutdown(runtime)
    assert len(calls) == 2 and all('steam.exe' not in str(c) for c in calls)
print('PASS session cleanup: exact prefix, graceful exit, bounded fallback, no unnecessary Steam startup')

# Exercise the real zsh cleanup function with a harmless sleep process and a
# fake runtime command. A rejected duplicate must preserve the first session.
import os
import shlex
source = Path(__file__).with_name('play-assetto.command').read_text()
body = 'cleanup_session() {' + source.split('cleanup_session() {', 1)[1].split('\n}', 1)[0] + '\n}'
with TemporaryDirectory() as temporary:
    root = Path(temporary)
    scripts = root / 'Scripts'; scripts.mkdir()
    marker = root / 'shutdown-called'
    (scripts / 'paddock-runtime.py').write_text('from pathlib import Path\nPath(__file__).parent.parent.joinpath("shutdown-called").touch()\n')
    bridge = subprocess.Popen(['/bin/sleep', '20'])
    try:
        env = dict(os.environ, project_dir=str(root), runtime_root=str(root), runtime='standalone', bottle='fixture', bridge_pid=str(bridge.pid))
        duplicate = subprocess.run(['/bin/zsh', '-c', body + '\nprevious_exit() { return 6; }\nprevious_exit\ncleanup_session'], env=env, capture_output=True)
        assert duplicate.returncode == 6 and bridge.poll() is None and not marker.exists()
        failed = subprocess.run(['/bin/zsh', '-c', body + '\nprevious_exit() { return 1; }\nprevious_exit\ncleanup_session'], env=env, capture_output=True)
        assert failed.returncode == 1 and marker.exists()
        bridge.wait(timeout=2)
    finally:
        if bridge.poll() is None:
            bridge.terminate(); bridge.wait()
print('PASS launcher ownership: duplicate leaves the first bridge/prefix alive; normal cleanup preserves the game exit code')
