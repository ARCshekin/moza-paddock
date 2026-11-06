"""Install game's original Microsoft DirectX redistributables from Steam CABs."""
import json
from pathlib import Path
import shutil
import struct
import subprocess
from .managed import checksum
from .steam_cef import atomic_copy

MANIFEST = json.loads(Path(__file__).with_name('directx-manifest.json').read_text())


def install(runtime, source_steam=None):
    cache = runtime.root / 'Prerequisites/directx-jun2010'
    cache.mkdir(parents=True, exist_ok=True)
    sources = []
    if source_steam:
        source = Path(source_steam)
        sources = [source / 'steamapps/common/Steamworks Shared/_CommonRedist/DirectX/Jun2010',
                   source / 'steamapps/common/assettocorsa/_CommonRedist/DirectX/Jun2010']
    for component in MANIFEST['components']:
        cab = cache / component['cab']
        if not cab.is_file() or checksum(cab) != component['cabSHA256']:
            found = next((folder / component['cab'] for folder in sources
                          if (folder / component['cab']).is_file()), None)
            if found is None:
                raise RuntimeError('Steam DirectX prerequisite missing: ' + component['cab'] +
                                   '. Prepare the runtime from a Steam folder with the game prerequisites installed.')
            if checksum(found) != component['cabSHA256']:
                raise RuntimeError('Unexpected DirectX CAB checksum: ' + str(found))
            atomic_copy(found, cab)
        dll = cache / component['dll']
        if not dll.is_file() or checksum(dll) != component['dllSHA256']:
            data = subprocess.check_output(['/usr/bin/tar', '-xOf', str(cab), component['member']])
            if len(data) < 256 or data[:2] != b'MZ':
                raise RuntimeError('DirectX prerequisite is not a Windows DLL')
            pe = struct.unpack_from('<I', data, 0x3c)[0]
            if pe + 6 > len(data) or data[pe:pe+4] != b'PE\0\0' or struct.unpack_from('<H', data, pe+4)[0] != 0x8664:
                raise RuntimeError('DirectX prerequisite must be an x64 PE image')
            temporary = dll.with_suffix('.new')
            temporary.write_bytes(data)
            if checksum(temporary) != component['dllSHA256']:
                temporary.unlink()
                raise RuntimeError('DirectX DLL checksum mismatch')
            temporary.replace(dll)
        destination = runtime.game / component['dll']
        if not destination.is_file() or checksum(destination) != component['dllSHA256']:
            if destination.is_file():
                backup = runtime.root / 'Backups/DirectX' / (component['dll'] + '.' + checksum(destination) + '.bak')
                backup.parent.mkdir(parents=True, exist_ok=True)
                if not backup.exists():
                    shutil.copy2(destination, backup)
            atomic_copy(dll, destination)
    key = 'HKCU\\Software\\Wine\\AppDefaults\\acs.exe\\DllOverrides'
    for component in MANIFEST['components']:
        runtime.run(['reg', 'add', key, '/v', Path(component['dll']).stem,
                     '/t', 'REG_SZ', '/d', 'native,builtin', '/f'], timeout=30)
