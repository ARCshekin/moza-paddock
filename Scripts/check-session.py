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
