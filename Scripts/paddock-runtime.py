#!/usr/bin/env python3
"""CLI boundary shared by SwiftUI and play-assetto.command."""
import argparse
import json
import os
import subprocess
from pathlib import Path
import sys
from runtime.managed import ManagedRuntime, DEFAULT_ROOT, STEAM_RELATIVE, application_arguments


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=DEFAULT_ROOT)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('status')
    shutdown = sub.add_parser('shutdown')
    shutdown.add_argument('--provider', choices=['standalone', 'crossover'], default='standalone')
    shutdown.add_argument('--bottle', default='Steam-3')
    cleanup = sub.add_parser('cleanup-logs')
    cleanup.add_argument('--wait-game-pid', type=int)
    install = sub.add_parser('install')
    install.add_argument('--cache', type=Path)
    prepare = sub.add_parser('prepare')
    prepare.add_argument('--source-steam', type=Path)
    wine = sub.add_parser('wine')
    wine.add_argument('--provider', choices=['standalone', 'crossover'], required=True)
    wine.add_argument('--bottle', default='Steam-3')
    wine.add_argument('--cwd', type=Path)
    wine.add_argument('arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    runtime = ManagedRuntime(args.root)
    if args.action == 'shutdown':
        from runtime.session import shutdown
        if args.provider == 'crossover':
            runtime.prefix = Path.home() / 'Library/Application Support/CrossOver/Bottles' / args.bottle
            runtime.wine = Path.home() / 'Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine'
        if not shutdown(runtime):
            raise RuntimeError('Wine session did not finish shutting down')
        print('Session Steam and Wine processes closed.')
    elif args.action == 'status':
        print(json.dumps(runtime.status()))
    elif args.action == 'cleanup-logs':
        import time
        from runtime.logfiles import trim_launcher
        if args.wait_game_pid:
            for _ in range(43200):
                state = subprocess.run(['/bin/ps', '-p', str(args.wait_game_pid), '-o', 'comm='], capture_output=True, text=True)
                if state.returncode != 0 or not state.stdout.strip().lower().endswith('acs.exe'):
                    break
                time.sleep(1)
            # Let the display helper, shell and native app close their handles.
            for _ in range(30):
                if trim_launcher(runtime.root):
                    print('Launcher diagnostic log compacted; head and tail retained.')
                    return
                time.sleep(1)
        else:
            print('Launcher log compacted.' if trim_launcher(runtime.root) else 'Log is small or still open.')
    elif args.action == 'install':
        runtime.install(args.cache)
        print('Independent Wine runtime installed.')
    elif args.action == 'prepare':
        runtime.prepare(args.source_steam)
        print('Independent Steam prefix prepared.')
    else:
        arguments = args.arguments
        if arguments and arguments[0] == '--':
            arguments = arguments[1:]
        if not arguments:
            parser.error('Wine command is required after --')
        if args.provider == 'standalone':
            if not runtime.wine.is_file():
                raise RuntimeError('Install Wine in the Launch environment tab first')
            arguments = application_arguments(arguments)
            if arguments[0].replace('\\', '/').rsplit('/', 1)[-1].lower() == 'steam.exe':
                from runtime.steam_cef import install as install_steam_cef
                install_steam_cef(runtime, Path(__file__).resolve().parent.parent / 'Bridge/build/moza-steam-cef.dll')
            if arguments[0].replace('\\', '/').rsplit('/', 1)[-1].lower() in ('acs.exe', 'moza-display-launcher.exe'):
                from runtime.directx import install as install_directx
                source = Path.home() / ('Library/Application Support/CrossOver/Bottles/' + args.bottle) / STEAM_RELATIVE
                install_directx(runtime, source)
            runtime.logs.mkdir(parents=True, exist_ok=True)
            if args.cwd:
                os.chdir(args.cwd)
            os.execve(str(runtime.wine), [str(runtime.wine)] + arguments, runtime.environment())
        else:
            wine = Path.home() / 'Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine'
            prefix = ['--bottle', args.bottle]
            if args.cwd:
                prefix += ['--workdir', 'C:/' + str(STEAM_RELATIVE / 'steamapps/common/assettocorsa').split('drive_c/', 1)[1]]
            if arguments[0].lower().endswith('.exe'):
                prefix += ['--cx-app']
            os.execv(str(wine), [str(wine)] + prefix + arguments)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Runtime error: ' + str(error), file=sys.stderr)
        sys.exit(1)
