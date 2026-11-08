#!/usr/bin/env python3
"""Launch the isolated CSP diagnostic copy; restore shared race/video INIs on exit."""
import argparse
from pathlib import Path
import subprocess
from runtime.managed import ManagedRuntime, DEFAULT_ROOT
from runtime.csp_performance import apply, read_ini, write_ini, video_profile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--car', default='rss_alpine_a525')
    parser.add_argument('--renderer', choices=['dxvk', 'dxmt'], default='dxvk')
    parser.add_argument('--hud', action='store_true')
    parser.add_argument('--gain', type=float, default=1.0)
    args = parser.parse_args()
    if not 0 <= args.gain <= 1:
        parser.error('gain must be between 0 and 1')
    commands = subprocess.check_output(['ps', 'ax', '-o', 'comm='], text=True).splitlines()
    if any(c.strip().lower() == 'acs.exe' or c.strip().lower().endswith('/acs.exe') for c in commands):
        raise RuntimeError('Close the current simulator session first')
    runtime = ManagedRuntime()
    game = DEFAULT_ROOT / 'Trials/assetto-csp'
    car = game / 'content/cars' / args.car
    if '/' in args.car or '\\' in args.car or not car.is_dir():
        parser.error('installed car ID required')
    skins = sorted(p.name for p in (car / 'skins').iterdir() if p.is_dir())
    if not skins:
        raise RuntimeError('Car skin missing')
    apply(game)
    cfg = Path.home() / 'Documents/Assetto Corsa/cfg'
    originals = {cfg / name: (cfg / name).read_bytes() for name in ('race.ini', 'video.ini')}
    recovery = DEFAULT_ROOT / 'Trials/State/config-before-performance'
    recovery.mkdir(exist_ok=True)
    for path, data in originals.items():
        (recovery / path.name).write_bytes(data)
    bridge = None
    try:
        race = read_ini(cfg / 'race.ini')
        for section in race:
            if section == 'RACE' or section.startswith('CAR_'):
                if 'MODEL' in race[section]:
                    race[section]['MODEL'] = args.car
                if 'SKIN' in race[section]:
                    race[section]['SKIN'] = skins[0]
        write_ini(cfg / 'race.ini', race)
        write_ini(cfg / 'video.ini', video_profile(read_ini(cfg / 'video.ini')))
        project = Path(__file__).resolve().parent.parent
        bridge_log = open(project / 'build/ac-bridge-live.log', 'ab')
        bridge = subprocess.Popen([str(project / '.build/debug/moza-ac-bridge'), '--gain', str(args.gain)],
                                  stdout=bridge_log, stderr=subprocess.STDOUT)
        env = runtime.environment()
        env.update(SteamAppId='244210', SteamGameId='244210', DXVK_LOG_LEVEL='warn', DXVK_FRAME_RATE='60')
        env['WINEDLLOVERRIDES'] += ';dbghelp=n,b;dwrite=n,b;d3dcompiler_47=n,b'
        wine = runtime.wine
        if args.renderer == 'dxmt':
            wine = DEFAULT_ROOT / 'Trials/Runtimes/wine-dxmt/Wine Staging.app/Contents/Resources/wine/bin/wine'
            if not wine.is_file():
                raise RuntimeError('Prepare the isolated DXMT engine first')
            env['WINEDLLOVERRIDES'] += ';dxgi=b;winemetal=b'
        if args.hud:
            env['DXVK_HUD'] = 'fps,compiler'
            if args.renderer == 'dxmt':
                env['DXMT_HUD'] = '1'
        with open(DEFAULT_ROOT / 'Trials/State/launcher.log', 'w') as stream:
            result = subprocess.run([str(wine), './moza-display-launcher.exe'], cwd=game,
                                    env=env, stdout=stream, stderr=subprocess.STDOUT)
        return result.returncode
    finally:
        if bridge is not None:
            bridge.terminate()
            try:
                bridge.wait(timeout=5)
            except subprocess.TimeoutExpired:
                bridge.kill(); bridge.wait()
        for path, data in originals.items():
            path.write_bytes(data)


if __name__ == '__main__':
    raise SystemExit(main())
