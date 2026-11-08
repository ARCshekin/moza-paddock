#!/usr/bin/env python3
"""Bounded network operations for the native server browser."""
import argparse
import json
from online.servers import directory, inspect


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['list', 'inspect'])
    parser.add_argument('--query', default='')
    parser.add_argument('--page', type=int, default=1)
    parser.add_argument('--address', default='')
    args = parser.parse_args()
    try:
        print(json.dumps(directory(args.query, args.page) if args.action == 'list' else inspect(args.address)))
        return 0
    except Exception as error:
        # Do not dump response bodies or server-provided markup into the UI/log.
        print(json.dumps({'error': f'Не удалось получить данные сервера: {error}'}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
