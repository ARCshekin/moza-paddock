"""Install a pinned official CSP package into the independent game only."""
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import uuid
from .managed import checksum

MANIFEST = json.loads(Path(__file__).with_name('csp-manifest.json').read_text())


def install(runtime, archive=None):
    # No shader/runtime DLL replacement while a simulator process is running.
    commands = subprocess.check_output(['/bin/ps', 'ax', '-o', 'command='], text=True).splitlines()
    if any(c.strip().lower() == 'acs.exe' or c.strip().lower().endswith(('/acs.exe', '\\acs.exe')) for c in commands):
        raise RuntimeError('Close Assetto Corsa before installing CSP')
    cache = runtime.root / 'Downloads'; cache.mkdir(parents=True, exist_ok=True)
    archive = Path(archive) if archive else cache / ('csp-' + MANIFEST['version'] + '.zip')
    if not archive.is_file():
        partial = archive.with_suffix('.partial')
        subprocess.run(['/usr/bin/curl', '-fL', '--retry', '2', '--max-time', '900',
                        MANIFEST['url'], '-o', str(partial)], check=True)
        if checksum(partial) != MANIFEST['sha256']:
            raise RuntimeError('CSP download checksum mismatch')
        partial.replace(archive)
    if checksum(archive) != MANIFEST['sha256']:
        raise RuntimeError('CSP archive checksum mismatch')
    spec = importlib.util.spec_from_file_location('paddock_mods', Path(__file__).parent.parent / 'paddock-mods.py')
    mods = importlib.util.module_from_spec(spec); spec.loader.exec_module(mods)
    backup = runtime.root / 'Backups/CSP' / str(uuid.uuid4())
    with tempfile.TemporaryDirectory(prefix='paddock-csp-') as temporary:
        stage = Path(temporary)
        mods.extract_zip(archive, stage); mods.check_tree(stage)
        if {p.name for p in stage.iterdir()} != {'dwrite.dll', 'extension'}:
            raise RuntimeError('Unexpected official CSP package structure')
        dll = (stage / 'dwrite.dll').read_bytes()
        if len(dll) < 256 or dll[:2] != b'MZ': raise RuntimeError('Invalid CSP DLL')
        pe = struct.unpack_from('<I', dll, 0x3c)[0]
        if pe+6 > len(dll) or dll[pe:pe+4] != b'PE\0\0' or struct.unpack_from('<H', dll, pe+4)[0] != 0x8664:
            raise RuntimeError('CSP DLL must be x64 PE')
        completed = []
        try:
            for name in ('extension', 'dwrite.dll'):
                target = runtime.game / name
                if target.is_symlink(): raise RuntimeError('CSP target contains a symlink')
                had_old = target.exists()
                if had_old:
                    backup.mkdir(parents=True, exist_ok=True)
                    if target.is_dir():
                        mods.check_tree(target)
                        shutil.copytree(target, backup / name)
                    else: shutil.copy2(target, backup / name)
                completed.append((target, had_old))
                if (stage / name).is_dir(): shutil.copytree(stage / name, target, dirs_exist_ok=True)
                else: shutil.copy2(stage / name, target)
            runtime.run(['reg', 'add', 'HKCU\\Software\\Wine\\AppDefaults\\acs.exe\\DllOverrides',
                         '/v', 'dwrite', '/t', 'REG_SZ', '/d', 'native,builtin', '/f'], timeout=30)
        except Exception:
            for target, had_old in reversed(completed):
                if target.is_dir(): shutil.rmtree(target)
                elif target.exists(): target.unlink()
                if had_old: shutil.move(str(backup / target.name), str(target))
            raise
    marker = dict(version=MANIFEST['version'], sha256=MANIFEST['sha256'], backup=str(backup),
                  components=[dict(name=target.name, hadOld=old) for target, old in completed])
    (runtime.root / 'csp-installed.json').write_text(json.dumps(marker, sort_keys=True))
    return marker
