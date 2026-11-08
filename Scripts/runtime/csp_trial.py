"""Prepare optional CSP/Metal diagnostics without replacing the default runtime."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from .managed import ManagedRuntime, DEFAULT_ROOT, checksum, extract
from . import csp, csp_symbols
from .csp_performance import apply, read_ini, write_ini

METAL = json.loads(Path(__file__).with_name('csp-metal-manifest.json').read_text())
COMPILER = json.loads(Path(__file__).with_name('csp-directx-manifest.json').read_text())


class TrialRuntime(ManagedRuntime):
    def __init__(self, root=DEFAULT_ROOT):
        super().__init__(root)
        self.base_root = Path(root)
        self.root = self.base_root / 'Trials/State'
        self.logs = self.root / 'Logs'
        self.wine_root = self.base_root / 'Trials/Runtimes/wine-sikarugir-10.0_6/wswine.bundle'
        self.wine = self.wine_root / 'bin/wine'
        self.prefix = self.base_root / 'Trials/Prefixes/assetto-dxmt'

    @property
    def game(self):
        return self.base_root / 'Trials/assetto-csp'

    @property
    def documents(self):
        return self.base_root / 'Trials/Documents/Assetto Corsa'


def download(spec, cache, name):
    target = cache / name
    if target.exists() and checksum(target) == spec['sha256']:
        return target
    partial = target.with_suffix('.partial')
    subprocess.run(['/usr/bin/curl', '-fL', '--retry', '2', '--max-time', '600',
                    spec['url'], '-o', str(partial)], check=True)
    if checksum(partial) != spec['sha256']:
        raise RuntimeError('Prerequisite checksum mismatch: ' + name)
    partial.replace(target)
    return target


def clone(source, target):
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['/bin/cp', '-cR', str(source), str(target)], check=True)


def prepare(root=DEFAULT_ROOT):
    base = ManagedRuntime(root); trial = TrialRuntime(root)
    commands = subprocess.check_output(['ps', 'ax', '-o', 'comm='], text=True).splitlines()
    if any(c.strip().lower() == 'acs.exe' or c.strip().lower().endswith('/acs.exe') for c in commands):
        raise RuntimeError('Close the simulator before preparing the trial')
    if not base.wine.is_file() or not (base.game / 'acs.pdb').is_file():
        raise RuntimeError('Prepare the normal Wine/Steam installation first')
    trial.root.mkdir(parents=True, exist_ok=True)
    cache = base.root / 'Downloads'; cache.mkdir(exist_ok=True)
    archive = download(METAL['wine'], cache, 'wine-sikarugir-10.0_6.tar.xz')
    if not trial.wine.is_file():
        engine = trial.wine_root.parent
        engine.mkdir(parents=True, exist_ok=True)
        extract(archive, engine)
    # The wrapper engine omits common Unix dependencies. Reuse locally installed,
    # pinned Wine 11.21 dependency files, without copying its Windows modules.
    for source in (base.wine_root / 'lib').iterdir():
        if source.name != 'wine':
            clone(source, trial.wine_root / 'lib' / source.name)
    dxmt = download(METAL['dxmt'], cache, 'dxmt-v0.80-builtin.tar.gz')
    with tempfile.TemporaryDirectory(prefix='paddock-dxmt-') as temporary:
        stage = Path(temporary); extract(dxmt, stage)
        package = stage / 'v0.80'
        for arch in ('x86_64-unix', 'x86_64-windows', 'i386-windows'):
            for source in (package / arch).iterdir():
                if not source.is_file() or source.is_symlink():
                    raise RuntimeError('Unexpected DXMT package entry')
                shutil.copyfile(source, trial.wine_root / 'lib/wine' / arch / source.name)
    fresh_prefix = not trial.prefix.exists()
    clone(base.prefix, trial.prefix)
    clone(base.game, trial.game)
    trial.documents.mkdir(parents=True, exist_ok=True)
    clone(Path.home() / 'Documents/Assetto Corsa/cfg', trial.documents / 'cfg')
    shutil.copyfile(trial.wine_root / 'lib/wine/x86_64-windows/winemetal.dll',
                    trial.prefix / 'drive_c/windows/system32/winemetal.dll')
    if fresh_prefix:
        trial.run(['wineboot', '-u'], timeout=120)
    personal = 'Z:' + str(trial.documents.parent).replace('/', '\\')
    for name in ('Shell Folders', 'User Shell Folders'):
        trial.run(['reg', 'add', 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\' + name,
                   '/v', 'Personal', '/t', 'REG_SZ', '/d', personal, '/f'], timeout=30)
    csp.install(trial, base.root / 'Downloads' / ('csp-' + csp.MANIFEST['version'] + '.zip'), configure=False)
    spec = dict(COMPILER, sha256=COMPILER['cabSHA256'])
    cab = download(spec, cache, 'csp-d3dcompiler47-x64.cab')
    data = subprocess.check_output(['/usr/bin/tar', '-xOf', str(cab), COMPILER['member']])
    dll = trial.game / 'd3dcompiler_47.dll'; dll.write_bytes(data)
    if checksum(dll) != COMPILER['dllSHA256']:
        raise RuntimeError('Shader compiler DLL checksum mismatch')
    fonts = trial.game / 'content/fonts/system'; fonts.mkdir(exist_ok=True)
    for source in (trial.game / 'content/fonts').glob('*.ttf'):
        shutil.copyfile(source, fonts / source.name)
    for source, name in [('Verdana.ttf', 'verdana.ttf'), ('Verdana Bold.ttf', 'verdanab.ttf'),
                         ('Verdana Italic.ttf', 'verdanai.ttf'), ('Verdana Bold Italic.ttf', 'verdanaz.ttf')]:
        shutil.copyfile(Path('/System/Library/Fonts/Supplemental') / source, fonts / name)
    csp_symbols.install(trial)
    config = trial.game / 'extension/config/general.ini'; ini = read_ini(config)
    ini['OPTIMIZATIONS'].update(CACHE_ACS='0', CACHING_LOADING2='0'); write_ini(config, ini)
    apply(trial.game)
    marker = dict(wine=METAL['wine']['sha256'], dxmt=METAL['dxmt']['sha256'],
                  csp=csp.MANIFEST['sha256'], pdb=checksum(trial.game / 'acs.pdb'))
    (trial.root / 'prepared.json').write_text(json.dumps(marker, indent=2))
    return trial
