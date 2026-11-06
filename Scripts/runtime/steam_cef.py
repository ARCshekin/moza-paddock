"""Steam-only CEF shim deployment; leaves all Valve executables untouched."""
from pathlib import Path
import json
import os
from .managed import checksum


def atomic_copy(source, destination):
    temporary = destination.with_name(destination.name + '.paddock-new')
    with source.open('rb') as src, temporary.open('wb') as dst:
        for chunk in iter(lambda: src.read(1024 * 1024), b''):
            dst.write(chunk)
        dst.flush()
        os.fsync(dst.fileno())
    temporary.replace(destination)


def install(runtime, shim):
    shim = Path(shim)
    original = runtime.wine_root / 'lib/wine/x86_64-windows/winmm.dll'
    system = runtime.prefix / 'drive_c/windows/system32'
    destination = system / 'winmm.dll'
    alias = system / 'moza_winmm.dll'
    if not shim.is_file() or not original.is_file() or not system.is_dir():
        raise RuntimeError('Build the Steam CEF shim and prepare the Wine prefix first')
    # Scope native loading to the helper only. Run Wine before replacing the
    # file, allowing an automatic wineboot update to finish first.
    key = 'HKCU\\Software\\Wine\\AppDefaults\\steamwebhelper.exe\\DllOverrides'
    for dll in ('winmm', 'moza_winmm'):
        runtime.run(['reg', 'add', key, '/v', dll, '/t', 'REG_SZ', '/d', 'native,builtin', '/f'], timeout=30)
    if not alias.is_file() or checksum(alias) != checksum(original):
        atomic_copy(original, alias)
    if not destination.is_file() or checksum(destination) != checksum(shim):
        atomic_copy(shim, destination)
    (runtime.prefix / 'paddock-steam-cef.json').write_text(json.dumps({
        'shimSHA256': checksum(shim), 'originalSHA256': checksum(original),
        'mode': 'in-process-gpu', 'scope': 'steamwebhelper.exe',
    }, sort_keys=True))


def uninstall(runtime):
    """Restore Wine's original DLL and remove only our two scoped overrides."""
    system = runtime.prefix / 'drive_c/windows/system32'
    original = runtime.wine_root / 'lib/wine/x86_64-windows/winmm.dll'
    if not (runtime.prefix / 'paddock-steam-cef.json').is_file():
        raise RuntimeError('No managed CEF adapter is installed')
    atomic_copy(original, system / 'winmm.dll')
    key = 'HKCU\\Software\\Wine\\AppDefaults\\steamwebhelper.exe\\DllOverrides'
    for dll in ('winmm', 'moza_winmm'):
        runtime.run(['reg', 'delete', key, '/v', dll, '/f'], timeout=30)
    (runtime.prefix / 'paddock-steam-cef.json').unlink()
