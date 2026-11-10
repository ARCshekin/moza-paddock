#!/usr/bin/env python3
"""Bounded network operations for the native server browser."""
import argparse
import json
from online.servers import directory, inspect, clear_session


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['list', 'inspect', 'lan', 'clear-session'])
    parser.add_argument('--query', default='')
    parser.add_argument('--page', type=int, default=1)
    parser.add_argument('--address', default='')
    parser.add_argument('--documents')
    parser.add_argument('--ports', default='9600-9610')
    parser.add_argument('--target', action='append')
    args = parser.parse_args()
    try:
        if args.action == 'clear-session':
            if not args.documents:
                parser.error('--documents is required')
            clear_session(args.documents)
            return 0
        if args.action == 'lan':
            from online.lan import discover
            result = discover(args.ports, args.target)
        else:
            result = directory(args.query, args.page) if args.action == 'list' else inspect(args.address)
        print(json.dumps(result))
        return 0
    except Exception as error:
        # Do not dump response bodies or server-provided markup into the UI/log.
        print(json.dumps({'error': f'Не удалось получить данные сервера: {error}'}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
