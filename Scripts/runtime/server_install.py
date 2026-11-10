"""Pinned local import of Kunos server; never download or redistribute Steam files."""
import json
from pathlib import Path
import shutil
import tempfile
from .managed import ManagedRuntime, checksum

MANIFEST = json.loads(Path(__file__).with_name('server-manifest.json').read_text())


def destination(root):
    return Path(root) / 'ServerRuntime' / MANIFEST['version']


def installed(root):
    executable = destination(root) / MANIFEST['filename']
    return executable.is_file() and checksum(executable) == MANIFEST['sha256']


def sources(root, game=None):
    if game:
        yield Path(game) / 'server/acServer.exe'
        yield Path(game) / 'acServer.exe'
    runtime = ManagedRuntime(root)
    yield runtime.game / 'server/acServer.exe'
    bottles = Path.home() / 'Library/Application Support/CrossOver/Bottles'
    for bottle in sorted(bottles.glob('*')):
        steamapps = bottle / 'drive_c/Program Files (x86)/Steam/steamapps/common'
        yield steamapps / 'assettocorsa/server/acServer.exe'
        yield steamapps / 'Assetto Corsa Dedicated Server/acServer.exe'
    yield runtime.steam / 'steamapps/common/Assetto Corsa Dedicated Server/acServer.exe'


def install(root, game=None):
    target = destination(root)
    if installed(root):
        return target / MANIFEST['filename']
    source = next((p for p in sources(root, game) if p.is_file() and checksum(p) == MANIFEST['sha256']), None)
    if source is None:
        raise RuntimeError('Не найден поддерживаемый acServer.exe. Установите Assetto Corsa в Steam '
                           'или задайте --game <папка игры>. Требуется версия ' + MANIFEST['version'])
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.server-install-', dir=target.parent) as temporary:
        stage = Path(temporary) / 'server'
        stage.mkdir(mode=0o700)
        executable = stage / MANIFEST['filename']
        shutil.copyfile(source, executable)
        if checksum(executable) != MANIFEST['sha256']:
            raise RuntimeError('Файл сервера изменился во время установки; исходная версия сохранена.')
        provenance = dict(MANIFEST, imported_from=str(source))
        (stage / 'installation.json').write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + '\n')
        # No in-place repair of an existing installation; leave unexpected data intact.
        if target.exists():
            if installed(root):
                return target / MANIFEST['filename']
            raise RuntimeError('Повреждена установка сервера: ' + str(target) + '. Переместите её для повторного импорта.')
        stage.rename(target)
    return target / MANIFEST['filename']
