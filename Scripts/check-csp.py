#!/usr/bin/env python3
"""Offline CSP symbol/profile regressions; never reads a live prefix or HID."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import struct
from runtime.csp_symbols import generate
from runtime.csp_performance import apply, read_ini, video_profile

with TemporaryDirectory() as temporary:
    root = Path(temporary)
    public = '\n'.join(f'S_PUB32 [size = 48] `?test{i}@@3HA`\n flags = none, addr = 0001:{i*4}' for i in range(1001))
    responses = {'-summary': 'GUID: {9BEE7421-88FE-47C4-B56C-15496409A8DE}',
                 '-section-headers': '1000 virtual address', '-publics': public,
                 '-globals': 'S_LDATA32 [size = 24] `privateHelper`\n type = 0x1234, addr = 0001:4008'}
    def dump(command, **kwargs):
        return responses[command[2]]
    output = root / 'symbols.bin'
    with patch('runtime.csp_symbols.subprocess.check_output', side_effect=dump):
        assert generate(root / 'fixture.pdb', output, root) == 1001
    blob = output.read_bytes(); offset = 24; rows = []
    while offset < len(blob):
        address, kind, size = struct.unpack_from('<III', blob, offset); offset += 12
        name = blob[offset:offset+size-1].decode(); offset += size
        rows.append((address, kind, name))
    assert rows[0] == (0x1000, 0, '?test0@@3HA')
    assert rows[-1] == (0x1000+4008, 2, 'privateHelper')
    print('PASS symbol generation includes public variables and private data, with section-relative addresses')
    game = root / 'game'; config = game / 'extension/config'; config.mkdir(parents=True)
    path = config / 'reflections_fx.ini'
    original = '[BASIC]\nENABLED=1\nENABLED2=1\n[OTHER]\nKEEP=42\n'
    path.write_text(original)
    apply(game); apply(game)
    assert read_ini(path)['BASIC']['ENABLED2'] == '0'
    assert read_ini(path)['OTHER']['KEEP'] == '42'
    assert (game / 'moza-profile-backup/reflections_fx.ini').read_text() == original
    video = root / 'video.ini'; video.write_text('[VIDEO]\nWIDTH=1920\nHEIGHT=1080\n[CONTROLS]\nKEEP=7\n')
    settings = video_profile(read_ini(video))
    assert settings['VIDEO']['WIDTH'] == '1920' and settings['VIDEO']['HEIGHT'] == '1080'
    assert settings['CONTROLS']['KEEP'] == '7'
    print('PASS lightweight profile preserves display size, unrelated settings and the original config backup')
print('All CSP fixture checks passed; no live game or hardware changed.')
