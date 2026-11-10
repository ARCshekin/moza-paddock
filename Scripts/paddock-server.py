#!/usr/bin/env python3
"""Run a user-installed Kunos server in its own prefix; no game/Steam shutdown."""
import argparse
import json
import os
from pathlib import Path
from runtime.managed import ManagedRuntime
from runtime.server_install import install


def invocation(root, directory):
    runtime = ManagedRuntime(root)
    if not runtime.wine.is_file():
        raise RuntimeError('Сначала установите бесплатный Wine в Настройки → Запуск.')
    if not (directory / 'acServer.exe').is_file():
        raise RuntimeError('Не найден acServer.exe в папке сервера.')
    runtime.prefix = root / 'Prefixes/server'
    runtime.prefix.parent.mkdir(parents=True, exist_ok=True)
    env = runtime.environment()
    env['WINEDLLOVERRIDES'] = 'mscoree,mshtml='
    return str(runtime.wine), [str(runtime.wine), str(directory / 'acServer.exe')], env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', nargs='?', choices=['run', 'install'], default='run')
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--game', type=Path)
    parser.add_argument('--directory', type=Path)
    args = parser.parse_args()
    if args.action == 'install':
        executable = install(args.root.resolve(), args.game)
        print(json.dumps({'executable': str(executable)}))
        return
    if args.directory is None:
        parser.error('--directory is required for run')
    executable, arguments, env = invocation(args.root.resolve(), args.directory.resolve())
    os.chdir(args.directory)
    os.execve(executable, arguments, env)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        raise SystemExit(str(error))
