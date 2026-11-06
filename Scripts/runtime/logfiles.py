"""Bound the app-owned launcher diagnostic log while no writer has it open."""
from pathlib import Path
import os
import subprocess


def trim_launcher(root, limit=8 * 1024 * 1024):
    path = Path(root) / 'launcher.log'
    if not path.is_file() or path.stat().st_size <= limit:
        return False
    owners = subprocess.run(['/usr/sbin/lsof', '-t', str(path)], capture_output=True)
    if owners.returncode == 0 and owners.stdout.strip():
        return False  # Never replace a log under a running game/launcher.
    with path.open('rb') as source:
        first = source.read(128 * 1024)
        source.seek(-2 * 1024 * 1024, os.SEEK_END)
        last = source.read()
    temporary = path.with_name(path.name + '.paddock-trim')
    temporary.write_bytes(first + b'\n[MOZA Paddock: repeated diagnostics trimmed]\n' + last)
    temporary.replace(path)
    return True
