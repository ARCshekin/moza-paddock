"""Independent Wine prefix management. No CrossOver binaries are imported."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile

MANIFEST = json.loads(Path(__file__).with_name('manifest.json').read_text())
HOME = Path.home()
DEFAULT_ROOT = HOME / 'Library/Application Support/MozaPaddock'
STEAM_RELATIVE = Path('drive_c/Program Files (x86)/Steam')


def checksum(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def verified_archive(path, spec):
    if checksum(path) != spec['sha256']:
        raise RuntimeError('SHA-256 does not match the pinned runtime: ' + str(path))


def validate_archive(path):
    """Validate all names and link targets before extracting a trusted, pinned tar."""
    with tarfile.open(path) as archive:
        members = archive.getmembers()
        if len(members) > 100000 or sum(m.size for m in members) > 8 * 1024**3:
            raise RuntimeError('Runtime archive is too large')
        names = set()
        for member in members:
            name = PurePosixPath(member.name)
            if name.is_absolute() or '..' in name.parts or str(name) in names:
                raise RuntimeError('Unsafe or duplicate runtime archive path')
            names.add(str(name))
            if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                raise RuntimeError('Unsupported archive entry')
            if member.issym() or member.islnk():
                target = PurePosixPath(member.linkname)
                if target.is_absolute():
                    raise RuntimeError('Absolute link in runtime archive')
                resolved = os.path.normpath(str(name.parent / target if member.issym() else target))
                if resolved == '..' or resolved.startswith('../'):
                    raise RuntimeError('Runtime archive link escapes destination')


def extract(path, destination):
    validate_archive(path)
    subprocess.run(['/usr/bin/tar', '-xpf', str(path), '-C', str(destination)], check=True)


def application_arguments(arguments):
    """Use software compositing for Steam CEF only; games keep hardware D3D11."""
    result = list(arguments)
    if result and result[0].replace('\\', '/').rsplit('/', 1)[-1].lower() == 'steam.exe':
        if '-cef-disable-gpu' not in result:
            result.append('-cef-disable-gpu')
    return result


class ManagedRuntime:
    def __init__(self, root=DEFAULT_ROOT):
        self.root = Path(root)
        self.runtime = self.root / 'Runtimes' / ('wine-' + MANIFEST['wine']['version'])
        self.prefix = self.root / 'Prefixes/assetto'
        self.wine_root = self.runtime / MANIFEST['wine']['bundle'] / 'Contents/Resources/wine'
        self.wine = self.wine_root / 'bin/wine'
        self.dxvk = self.runtime / MANIFEST['dxvk']['directory']
        self.logs = self.root / 'Logs'

    @property
    def steam(self):
        return self.prefix / STEAM_RELATIVE

    @property
    def game(self):
        return self.steam / 'steamapps/common/assettocorsa'

    def status(self):
        return dict(version=MANIFEST['wine']['version'], installed=self.wine.is_file(),
                    prepared=(self.prefix / 'paddock-ready.json').is_file(),
                    gameInstalled=(self.game / 'acs.exe').is_file(), prefix=str(self.prefix),
                    wine=str(self.wine), game=str(self.game))

    def install(self, cache=None):
        if self.wine.is_file() and self.dxvk.is_dir():
            return
        cache = Path(cache) if cache else self.root / 'Downloads'
        cache.mkdir(parents=True, exist_ok=True)
        self.runtime.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.install-', dir=self.runtime.parent) as stage:
            for spec in MANIFEST.values():
                archive = cache / spec['archive']
                if not archive.is_file() or checksum(archive) != spec['sha256']:
                    partial = archive.with_suffix(archive.suffix + '.partial')
                    print('Downloading ' + spec['archive'], flush=True)
                    subprocess.run(['/usr/bin/curl', '-fL', '--retry', '2', '--connect-timeout', '30',
                                    '--max-time', '3600', '-o', str(partial), spec['url']], check=True)
                    verified_archive(partial, spec)
                    partial.replace(archive)
                verified_archive(archive, spec)
                extract(archive, stage)
            expected = Path(stage) / MANIFEST['wine']['bundle'] / 'Contents/Resources/wine/bin/wine'
            if not expected.is_file():
                raise RuntimeError('Wine executable missing from verified download')
            wine_lib = expected.parent.parent / 'lib/wine'
            dxvk = Path(stage) / MANIFEST['dxvk']['directory']
            for architecture in ('x86_64-windows', 'i386-windows'):
                for dll in ('d3d11.dll', 'd3d10core.dll'):
                    destination = wine_lib / architecture / dll
                    if not destination.is_file():
                        raise RuntimeError('Unexpected Wine builtin layout: ' + str(destination))
                    shutil.copy2(dxvk / architecture / dll, destination)
            if self.runtime.exists():
                raise RuntimeError('Incomplete runtime already exists; move it aside before reinstalling: ' + str(self.runtime))
            Path(stage).rename(self.runtime)

    def environment(self):
        env = os.environ.copy()
        # Never inherit another Wine distribution's loader or prefix.
        for name in list(env):
            if name.startswith(('CX_', 'DYLD_', 'WINE')):
                env.pop(name)
        env.update(WINEPREFIX=str(self.prefix), WINEARCH='win64', WINEDEBUG='-all',
                   WINEDLLOVERRIDES='dinput8=n,b;d3d11,d3d10core=b;mscoree,mshtml=',
                   DXVK_LOG_PATH=str(self.logs), DXVK_STATE_CACHE_PATH=str(self.logs),
                   MVK_CONFIG_RESUME_LOST_DEVICE='1')
        return env

    def run(self, args, cwd=None, timeout=None):
        self.logs.mkdir(parents=True, exist_ok=True)
        return subprocess.run([str(self.wine)] + list(args), env=self.environment(),
                              cwd=cwd, check=True, timeout=timeout)

    def prepare(self, source_steam=None):
        if not self.wine.is_file():
            raise RuntimeError('Install the independent Wine runtime first')
        self.prefix.parent.mkdir(parents=True, exist_ok=True)
        with (self.root / 'prepare.log').open('a') as log:
            subprocess.run([str(self.wine), 'wineboot', '-u'], env=self.environment(),
                           stdout=log, stderr=log, check=True, timeout=180)
        if source_steam and not (self.game / 'acs.exe').is_file():
            self.import_steam(Path(source_steam))
        if not (self.game / 'acs.exe').is_file():
            raise RuntimeError('Select a Windows Steam folder with Assetto Corsa installed')
        # Preserve existing macOS Documents/Assetto Corsa settings via Wine shell folders.
        personal = 'Z:' + str(HOME / 'Documents').replace('/', '\\')
        for key in ('User Shell Folders', 'Shell Folders'):
            self.run(['reg', 'add', 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\' + key,
                      '/v', 'Personal', '/t', 'REG_SZ', '/d', personal, '/f'], timeout=30)
        self.run(['reg', 'add', 'HKCU\\Software\\Wine\\DllOverrides', '/v', 'dinput8',
                  '/t', 'REG_SZ', '/d', 'native,builtin', '/f'], timeout=30)
        marker = self.prefix / 'paddock-ready.json'
        temporary = marker.with_suffix('.tmp')
        temporary.write_text(json.dumps(dict(wine=MANIFEST['wine']['version'], dxvk=MANIFEST['dxvk']['version'])))
        temporary.replace(marker)

    def import_steam(self, source):
        source = source.resolve()
        if not (source / 'steam.exe').is_file() or not (source / 'steamapps/common/assettocorsa/acs.exe').is_file():
            raise RuntimeError('Source must be Windows Steam with Assetto Corsa installed')
        if self.steam.exists():
            raise RuntimeError('Steam destination already exists; it will not be overwritten')
        self.steam.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.steam-import-', dir=self.steam.parent) as stage:
            target = Path(stage) / 'Steam'
            target.mkdir()
            # APFS clones keep a fully independent copy without duplicating game blocks.
            # Never copy Windows system directories or CrossOver runtime components.
            for item in source.iterdir():
                if item.name in ('steamapps', 'logs', 'dumps', 'depotcache', 'appcache'):
                    continue
                if item.is_symlink():
                    continue
                subprocess.run(['/bin/cp', '-cR', str(item), str(target / item.name)], check=True)
            apps = target / 'steamapps'
            (apps / 'common').mkdir(parents=True)
            subprocess.run(['/bin/cp', '-cR', str(source / 'steamapps/common/assettocorsa'),
                            str(apps / 'common/assettocorsa')], check=True)
            manifest = source / 'steamapps/appmanifest_244210.acf'
            if manifest.is_file():
                shutil.copy2(manifest, apps)
            target.rename(self.steam)
