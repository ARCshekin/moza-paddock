"""Build an AC-only Wine symbol adapter using the user's installed PDB.

Protocol workaround documented in acc-extension-config#637. Implementation is
local; no third-party proxy code or game-derived symbol tables are distributed.
"""
import re
import shutil
import struct
import subprocess
import uuid
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]


def generate(pdb, output, llvm):
    def dump(flag):
        return subprocess.check_output([str(llvm / 'llvm-pdbutil'), 'dump', flag, str(pdb)], text=True, errors='replace')
    guid = uuid.UUID(re.search(r'GUID: (\{[^}]+\})', dump('-summary'))[1])
    sections = [int(v, 16) for v in re.findall(r'^\s*([0-9A-F]+) virtual address', dump('-section-headers'), re.M)]
    data = bytearray(b'MZCPSMY1' + guid.bytes_le)
    name = None
    count = 0
    for line in dump('-publics').splitlines():
        m = re.search(r'S_PUB32 \[size = \d+\] `(.*)`$', line)
        if m:
            name = m[1]
            continue
        m = re.search(r'flags = (.*), addr = (\d+):(\d+)', line)
        if m and name is not None:
            section, offset = int(m[2]), int(m[3])
            encoded = name.encode() + b'\0'
            if 1 <= section <= len(sections) and len(encoded) <= 4096:
                data += struct.pack('<III', sections[section-1] + offset, int('function' in m[1]), len(encoded)) + encoded
                count += 1
            name = None
    # Local data is absent from the public symbol stream (for example hLibOVR).
    name = None
    for line in dump('-globals').splitlines():
        m = re.search(r'S_[GL]DATA32 \[size = \d+\] `(.*)`$', line)
        if m:
            name = m[1]
            continue
        m = re.search(r'addr = (\d+):(\d+)', line)
        if m and name is not None:
            section, offset = int(m[1]), int(m[2])
            encoded = name.encode() + b'\0'
            if 1 <= section <= len(sections) and len(encoded) <= 4096:
                data += struct.pack('<III', sections[section-1] + offset, 2, len(encoded)) + encoded
            name = None
    if count < 1000:
        raise RuntimeError('PDB public symbol table is incomplete')
    output.write_bytes(data)
    return count


def install(runtime):
    llvm = Path('/opt/homebrew/opt/llvm/bin')
    if not (llvm / 'llvm-pdbutil').is_file():
        raise RuntimeError('CSP Wine compatibility requires Homebrew LLVM')
    real = runtime.wine.parent.parent / 'lib/wine/x86_64-windows/dbghelp.dll'
    # Wine's exact exports vary; forward the installed runtime's own export list.
    exports = subprocess.check_output([str(llvm / 'llvm-readobj'), '--coff-exports', str(real)], text=True)
    names = re.findall(r'^  Name: (\S+)$', exports, re.M)
    if 'SymEnumSymbols' not in names:
        raise RuntimeError('Wine dbghelp export unavailable')
    build = PROJECT / 'Bridge/build/csp'; build.mkdir(parents=True, exist_ok=True)
    definition = build / 'exports.def'
    definition.write_text('LIBRARY dbghelp.dll\nEXPORTS\n' + ''.join(
        n + ('=proxyEnum' if n == 'SymEnumSymbols' else '=moza-dbghelp-wine.' + n) + '\n' for n in names))
    subprocess.run([str(llvm / 'clang'), '--target=x86_64-pc-windows-msvc', '-std=c11', '-O2',
                    '-ffreestanding', '-fno-builtin', '-fno-stack-protector', '-mno-stack-arg-probe',
                    '-Wall', '-Wextra', '-Werror', '-c', str(PROJECT / 'Bridge/csp-symbols.c'),
                    '-o', str(build / 'proxy.obj')], check=True)
    subprocess.run([str(llvm / 'llvm-dlltool'), '-m', 'i386:x86-64', '-d', str(PROJECT / 'Bridge/csp-kernel32.def'),
                    '-l', str(build / 'kernel32.lib')], check=True)
    linker = shutil.which('lld-link') or '/opt/homebrew/opt/lld/bin/lld-link'
    subprocess.run([linker, '/Brepro', '/dll', '/nodefaultlib', '/machine:x64', '/entry:DllMain',
                    '/dynamicbase', '/nxcompat', '/out:' + str(build / 'dbghelp.dll'), '/def:' + str(definition),
                    str(build / 'proxy.obj'), str(build / 'kernel32.lib')], check=True)
    count = generate(runtime.game / 'acs.pdb', build / 'moza-csp-symbols.bin', llvm)
    for source, name in [(real, 'moza-dbghelp-wine.dll'), (build / 'dbghelp.dll', 'dbghelp.dll'),
                         (build / 'moza-csp-symbols.bin', 'moza-csp-symbols.bin')]:
        target = runtime.game / name
        if target.exists():
            backup = runtime.root / 'Backups/CSPSymbols' / str(uuid.uuid4()) / name
            backup.parent.mkdir(parents=True); shutil.copy2(target, backup)
        shutil.copy2(source, target)
    return count
