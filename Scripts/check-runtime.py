#!/usr/bin/env python3
"""Offline checks: downloads and Wine processes are never started."""
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
sys.path.insert(0, str(Path(__file__).parent))
import runtime.managed as managed
from runtime.managed import ManagedRuntime, checksum, verified_archive, validate_archive, MANIFEST, application_arguments


def rejected(call):
    try:
        call()
    except RuntimeError:
        return
    raise AssertionError('Expected rejection')


with tempfile.TemporaryDirectory() as folder:
    root = Path(folder)
    data = root / 'download'
    data.write_bytes(b'pinned artifact')
    verified_archive(data, {'sha256': checksum(data)})
    rejected(lambda: verified_archive(data, {'sha256': '0' * 64}))
    print('PASS checksum mismatch rejected before installation')
    archive = root / 'test.tar'
    def tar_entry(name, link=None):
        with tarfile.open(archive, 'w') as tar:
            entry = tarfile.TarInfo(name)
            if link is not None:
                entry.type = tarfile.SYMTYPE; entry.linkname = link
            tar.addfile(entry)
    tar_entry('../outside')
    rejected(lambda: validate_archive(archive))
    tar_entry('bundle/link', '../../outside')
    rejected(lambda: validate_archive(archive))
    tar_entry('bundle/link', '/outside')
    rejected(lambda: validate_archive(archive))
    tar_entry('bundle/Versions/Current', 'A')
    validate_archive(archive)
    print('PASS unsafe tar names/links rejected; framework links accepted')
    assert application_arguments(['C:/Program Files (x86)/Steam/steam.exe', '-silent'])[-1] == '-cef-disable-gpu'
    assert application_arguments(['C:\\Steam\\Steam.exe', '-cef-disable-gpu']).count('-cef-disable-gpu') == 1
    assert application_arguments(['C:/games/acs.exe']) == ['C:/games/acs.exe']
    assert application_arguments(['reg', 'query']) == ['reg', 'query']
    print('PASS CEF workaround applies only to Steam and is idempotent')
    runtime = ManagedRuntime(root / 'data')
    assert not any(runtime.status()[k] for k in ['installed', 'prepared', 'gameInstalled'])
    env = runtime.environment()
    assert env['WINEPREFIX'] == str(root / 'data/Prefixes/assetto')
    assert 'CrossOver' not in env['WINEPREFIX'] and 'CrossOver' not in str(runtime.wine)
    assert env['WINEDLLOVERRIDES'].startswith('dinput8=n,b;')
    print('PASS separate prefix and independent binary resolution')
    source = root / 'Source Steam'
    game = source / 'steamapps/common/assettocorsa'
    game.mkdir(parents=True)
    for name in ['steam.exe', 'client.txt']:
        (source / name).write_text(name)
    (game / 'acs.exe').write_text('game fixture')
    (source / 'steamapps/appmanifest_244210.acf').write_text('fixture')
    (source / 'logs').mkdir(); (source / 'logs/private.log').write_text('not imported')
    (source / 'steamapps/common/other-game').mkdir()
    (source / 'steamapps/common/other-game/private').write_text('not imported')
    runtime.import_steam(source)
    assert (runtime.game / 'acs.exe').read_text() == 'game fixture'
    assert not (runtime.steam / 'logs').exists()
    assert not (runtime.steam / 'steamapps/common/other-game').exists()
    (runtime.game / 'acs.exe').write_text('independent change')
    assert (game / 'acs.exe').read_text() == 'game fixture'
    rejected(lambda: runtime.import_steam(source))
    assert (runtime.game / 'acs.exe').read_text() == 'independent change'
    print('PASS APFS import is independent, scoped and refuses overwrite')
    assert all(s['url'].startswith('https://github.com/') and len(s['sha256']) == 64 and s['license'] for s in MANIFEST.values())
    print('PASS dependency versions checksums and licenses pinned')
    original_manifest = dict(MANIFEST)
    cache = root / 'cache'; cache.mkdir()
    try:
        # Build miniature pinned artifacts to exercise the actual atomic installer.
        for component in ('wine', 'dxvk'):
            artifact = cache / (component + '.tar')
            with tarfile.open(artifact, 'w') as tar:
                entries = {}
                if component == 'wine':
                    base = 'Wine Staging.app/Contents/Resources/wine/'
                    entries[base + 'bin/wine'] = b'#!/bin/sh\nexit 0\n'
                    for arch in ('x86_64-windows', 'i386-windows'):
                        for dll in ('d3d11.dll', 'd3d10core.dll'):
                            entries[base + 'lib/wine/' + arch + '/' + dll] = b'original'
                else:
                    for arch in ('x86_64-windows', 'i386-windows'):
                        for dll in ('d3d11.dll', 'd3d10core.dll'):
                            entries['DXVK/' + arch + '/' + dll] = b'patched builtin'
                for name, content in entries.items():
                    entry = tarfile.TarInfo(name); entry.size = len(content); entry.mode = 0o755
                    tar.addfile(entry, io.BytesIO(content))
            MANIFEST[component] = dict(original_manifest[component], archive=artifact.name, sha256=checksum(artifact))
        MANIFEST['dxvk']['directory'] = 'DXVK'
        installed = ManagedRuntime(root / 'installed')
        installed.install(cache)
        assert installed.wine.is_file() and installed.wine.stat().st_mode & 0o111
        assert (installed.wine_root / 'lib/wine/x86_64-windows/d3d11.dll').read_bytes() == b'patched builtin'
        installed.install(cache)  # Idempotent; no second extraction/download.
        assert not list(installed.runtime.parent.glob('.install-*'))
        print('PASS verified installation is atomic, executable and idempotent')
    finally:
        MANIFEST.clear(); MANIFEST.update(original_manifest)
print('All runtime checks passed; no Steam account, game or hardware touched.')
