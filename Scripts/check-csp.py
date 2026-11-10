#!/usr/bin/env python3
"""Offline CSP installation checks: no Wine, live game or downloads."""
import hashlib
import struct
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import patch
import zipfile
from runtime.csp import MANIFEST, install

with TemporaryDirectory() as temporary:
    root = Path(temporary)
    dll = bytearray(512); dll[:2] = b'MZ'; struct.pack_into('<I', dll, 0x3c, 128)
    dll[128:132] = b'PE\0\0'; struct.pack_into('<H', dll, 132, 0x8664)
    archive = root / 'fixture.zip'
    with zipfile.ZipFile(archive, 'w') as target:
        target.writestr('dwrite.dll', dll)
        target.writestr('extension/config/general.ini', '[BASIC]\nENABLED=1\n')
    runtime = SimpleNamespace(root=root / 'store', game=root / 'game')
    (runtime.game / 'extension').mkdir(parents=True)
    (runtime.game / 'extension/user.ini').write_text('keep user settings')
    (runtime.game / 'dwrite.dll').write_bytes(b'original dll')
    with patch('runtime.csp.subprocess.check_output', return_value='C:/game/moza-display-launcher.exe\n'):
        try:
            install(runtime, archive, configure=False)
            raise AssertionError('active launch allowed CSP mutation')
        except RuntimeError:
            pass
    assert not runtime.root.exists()
    sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    with patch.dict(MANIFEST, sha256=sha), patch('runtime.csp.subprocess.check_output', return_value=''):
        marker = install(runtime, archive, configure=False)
    assert (runtime.game / 'dwrite.dll').read_bytes() == dll
    assert (runtime.game / 'extension/user.ini').read_text() == 'keep user settings'
    assert (Path(marker['backup']) / 'dwrite.dll').read_bytes() == b'original dll'
    def failing_reg(*args, **kwargs):
        raise RuntimeError('fixture registry failure')
    runtime.run = failing_reg
    (runtime.game / 'dwrite.dll').write_bytes(b'previous working dll')
    with patch.dict(MANIFEST, sha256=sha), patch('runtime.csp.subprocess.check_output', return_value=''):
        try:
            install(runtime, archive)
            raise AssertionError('registry failure ignored')
        except RuntimeError:
            pass
    assert (runtime.game / 'dwrite.dll').read_bytes() == b'previous working dll'
    assert (runtime.game / 'extension/user.ini').read_text() == 'keep user settings'
print('PASS CSP rejects active game preparation, validates archive/PE, backs up and rolls back without Wine')
