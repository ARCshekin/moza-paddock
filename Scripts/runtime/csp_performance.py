"""Graphics-only CSP profile for the isolated macOS test installation."""
import configparser
from pathlib import Path
import shutil

MODULES = ('grass_fx', 'extra_fx', 'lighting_fx', 'weather_fx', 'smart_mirror',
           'dxgi_tweaks', 'reflections_fx', 'particles_fx', 'smart_shadows', 'colorful_shadowing', 'shadowed_wheels')


def read_ini(path):
    ini = configparser.ConfigParser(interpolation=None, strict=False, inline_comment_prefixes=(';',))
    ini.optionxform = str
    ini.read(path, encoding='utf-8-sig')
    return ini


def write_ini(path, ini):
    with Path(path).open('w') as stream:
        ini.write(stream, space_around_delimiters=False)


def apply(game):
    config = Path(game) / 'extension/config'
    backup = Path(game) / 'moza-profile-backup'
    backup.mkdir(exist_ok=True)
    for name in MODULES:
        path = config / (name + '.ini')
        if not path.is_file():
            continue
        if not (backup / path.name).exists():
            shutil.copyfile(path, backup / path.name)
        ini = read_ini(path)
        if 'BASIC' not in ini:
            continue
        ini['BASIC']['ENABLED'] = '0'
        if 'ENABLED2' in ini['BASIC']:
            ini['BASIC']['ENABLED2'] = '0'
        write_ini(path, ini)


def video_profile(ini):
    # Keep the display's 1920x1080 dimensions. No physics, controls or AI changes.
    values = {'VIDEO': {'AASAMPLES': '1', 'ANISOTROPIC': '4', 'SHADOW_MAP_SIZE': '512', 'VSYNC': '0'},
              'ASSETTOCORSA': {'WORLD_DETAIL': '3'},
              'MIRROR': {'SIZE': '256', 'HQ': '0'},
              'CUBEMAP': {'SIZE': '256', 'FACES_PER_FRAME': '0'},
              'POST_PROCESS': {'ENABLED': '0'}, 'EFFECTS': {'SMOKE': '1'}}
    for section, settings in values.items():
        if section not in ini:
            ini[section] = {}
        ini[section].update(settings)
    return ini
