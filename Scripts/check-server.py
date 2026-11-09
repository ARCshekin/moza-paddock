#!/usr/bin/env python3
"""Offline server launch checks: fake binary only, never execute Wine."""
import importlib.util
import os
from pathlib import Path
import tempfile
from unittest.mock import patch
from runtime.managed import ManagedRuntime

spec = importlib.util.spec_from_file_location('paddock_server', Path(__file__).with_name('paddock-server.py'))
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary) / 'store with spaces'
    folder = root / 'Servers/test'
    folder.mkdir(parents=True)
    (folder / 'acServer.exe').write_bytes(b'fixture')
    runtime = ManagedRuntime(root)
    try:
        server.invocation(root, folder)
        raise AssertionError('Missing Wine accepted')
    except RuntimeError:
        pass
    runtime.wine.parent.mkdir(parents=True)
    runtime.wine.write_bytes(b'fixture')
    with patch.dict(os.environ, {'WINEPREFIX': '/do-not-touch', 'CX_BOTTLE': 'do-not-touch'}):
        executable, arguments, env = server.invocation(root, folder)
    assert executable == str(runtime.wine)
    assert arguments == [str(runtime.wine), str(folder / 'acServer.exe')]
    assert env['WINEPREFIX'] == str(root / 'Prefixes/server')
    assert env['WINEPREFIX'] != str(runtime.prefix)
    assert 'CX_BOTTLE' not in env
    assert 'dinput8' not in env['WINEDLLOVERRIDES']
    assert not (root / 'Prefixes/assetto').exists()
print('PASS dedicated server invocation isolates prefix and retains paths without shell interpolation')
