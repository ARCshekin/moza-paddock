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

# Test the real installer with a deterministic fixture, never user's Steam files.
from runtime import server_install
import hashlib

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary) / 'installation'
    source = Path(temporary) / 'Steam/server/acServer.exe'
    source.parent.mkdir(parents=True)
    payload = b'pinned local server fixture'
    source.write_bytes(payload)
    original = source.parent / 'server_cfg.ini'
    original.write_text('preserve source settings')
    spec = dict(server_install.MANIFEST, sha256=hashlib.sha256(payload).hexdigest())
    with patch.dict(server_install.MANIFEST, spec), patch.object(server_install, 'sources', return_value=iter([source])):
        executable = server_install.install(root)
    assert executable.read_bytes() == payload
    assert original.read_text() == 'preserve source settings'
    provenance = __import__('json').loads(executable.with_name('installation.json').read_text())
    assert provenance['sha256'] == spec['sha256'] and provenance['license']
    with patch.dict(server_install.MANIFEST, spec), patch.object(server_install, 'sources', side_effect=AssertionError('cached install must not scan sources')):
        assert server_install.install(root) == executable
    executable.write_bytes(b'corruption')
    with patch.dict(server_install.MANIFEST, spec), patch.object(server_install, 'sources', return_value=iter([source])):
        try:
            server_install.install(root)
            raise AssertionError('corrupt installation overwritten')
        except RuntimeError:
            pass
    assert executable.read_bytes() == b'corruption'
    assert not list(executable.parent.parent.glob('.server-install-*'))
    with patch.dict(server_install.MANIFEST, spec), patch.object(server_install, 'sources', return_value=iter([executable])):
        try:
            server_install.install(root / 'other')
            raise AssertionError('unknown checksum imported')
        except RuntimeError:
            pass
    assert not (root / 'other/ServerRuntime').exists()
print('PASS pinned server import, provenance, idempotency, corruption and rollback; no downloads')
