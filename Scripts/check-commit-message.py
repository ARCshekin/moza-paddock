#!/usr/bin/env python3
"""Validate the repository's conventional commit header."""
import re
import sys
from pathlib import Path

PATTERN = re.compile(r"^(feat|fix|refactor|docs|test|build|ci|chore|perf|revert)\([a-z][a-z0-9-]*\): \S.+$")


def valid(message):
    return bool(PATTERN.fullmatch(message.splitlines()[0] if message.splitlines() else ""))


if __name__ == "__main__":
    text = Path(sys.argv[1]).read_text() if len(sys.argv) > 1 else sys.stdin.read()
    if not valid(text):
        print("Expected: <type>(<part>): <description>", file=sys.stderr)
        raise SystemExit(1)
