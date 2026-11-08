#!/bin/zsh
# Build the Win64 dinput8.dll bridge and run its offline unit tests.
set -eu
cd "${0:A:h:h}"
# Needs Homebrew LLVM (clang, llvm-dlltool, llvm-readobj) and a COFF linker: lld-link
# (`brew install llvm lld`) or the rust-lld that ships with a rustup toolchain.
llvm_bin=${LLVM_BIN:-$(brew --prefix llvm 2>/dev/null || print /opt/homebrew/opt/llvm)/bin}
[[ -x "$llvm_bin/clang" ]] || { print -u2 "LLVM not found; run: brew install llvm lld (or set LLVM_BIN)"; exit 1 }
link=()
for candidate in "$(command -v lld-link || true)" "$llvm_bin/lld-link" "$(brew --prefix lld 2>/dev/null)/bin/lld-link"; do
    [[ -n "$candidate" && -x "$candidate" ]] && { link=("$candidate"); break }
done
if (( ! ${#link} )); then
    for rust_lld in $HOME/.rustup/toolchains/*/lib/rustlib/*/bin/rust-lld(N); do
        link=(env "DYLD_LIBRARY_PATH=${rust_lld:h:h:h:h}" "$rust_lld" -flavor link); break
    done
fi
(( ${#link} )) || { print -u2 "No COFF linker found; run: brew install lld"; exit 1 }
mkdir -p Bridge/build
"$llvm_bin/clang" -std=c11 -g -Wall -Wextra -Wno-unused-function -Wno-missing-field-initializers -fsanitize=address,undefined Bridge/tests/test_bridge.c -o Bridge/build/test-bridge
Bridge/build/test-bridge
"$llvm_bin/clang" --target=x86_64-pc-windows-msvc -std=c11 -O2 -ffreestanding -fno-builtin -fno-stack-protector -Wall -Wextra -Werror -DCFB_USER_ID=$(id -u) -c Bridge/observe.c -o Bridge/build/observe.obj
"$llvm_bin/llvm-dlltool" -m i386:x86-64 -d Bridge/kernel32.def -l Bridge/build/kernel32.lib
"$llvm_bin/llvm-dlltool" -m i386:x86-64 -d Bridge/input-user32.def -l Bridge/build/input-user32.lib
"${link[@]}" /Brepro /dll /nodefaultlib /machine:x64 /entry:DllMain /dynamicbase /nxcompat /out:Bridge/build/dinput8.dll /def:Bridge/exports.def Bridge/build/observe.obj Bridge/build/kernel32.lib Bridge/build/input-user32.lib
"$llvm_bin/llvm-readobj" --file-headers --coff-imports --coff-exports Bridge/build/dinput8.dll > Bridge/build/pe-inspection.txt
python3 - <<'PY'
from pathlib import Path
s=Path('Bridge/build/pe-inspection.txt').read_text()
assert 'IMAGE_FILE_MACHINE_AMD64' in s
assert s.count('Import {')==2 and 'Name: KERNEL32.dll' in s and 'Name: USER32.dll' in s
for export in ['DirectInput8Create','DllCanUnloadNow','DllGetClassObject','DllRegisterServer','DllUnregisterServer']:
    assert export in s
print('PASS: x64 PE dinput8.dll, scoped KERNEL32/USER32 imports')
PY
print "Built Bridge/build/dinput8.dll"
"$llvm_bin/clang" --target=x86_64-pc-windows-msvc -std=c11 -O2 -ffreestanding -fno-builtin -fno-stack-protector -Wall -Wextra -Werror -c Bridge/display-launcher.c -o Bridge/build/display-launcher.obj
"$llvm_bin/clang" -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined Bridge/tests/test_steam_ready.c -o Bridge/build/test-steam-ready
Bridge/build/test-steam-ready
"$llvm_bin/llvm-dlltool" -m i386:x86-64 -d Bridge/display-kernel32.def -l Bridge/build/display-kernel32.lib
"$llvm_bin/llvm-dlltool" -m i386:x86-64 -d Bridge/display-user32.def -l Bridge/build/display-user32.lib
"${link[@]}" /Brepro /nodefaultlib /machine:x64 /entry:main /subsystem:windows /dynamicbase /nxcompat /out:Bridge/build/moza-display-launcher.exe Bridge/build/display-launcher.obj Bridge/build/display-kernel32.lib Bridge/build/display-user32.lib
print "Built Bridge/build/moza-display-launcher.exe"

"$llvm_bin/clang" -std=c11 -O1 -g -Wall -Wextra -Wno-unused-function -Wno-unused-variable -fsanitize=address,undefined Bridge/tests/test_csp_symbols.c -o Bridge/build/test-csp-symbols
Bridge/build/test-csp-symbols
"$llvm_bin/clang" --target=x86_64-pc-windows-msvc -std=c11 -O2 -ffreestanding -fno-builtin -fno-stack-protector -mno-stack-arg-probe -Wall -Wextra -Werror -c Bridge/csp-symbols.c -o Bridge/build/csp-symbols.obj

"$llvm_bin/clang" --target=x86_64-pc-windows-msvc -std=c11 -O2 -ffreestanding -fno-builtin -fno-stack-protector -Wall -Wextra -Werror -c Bridge/runtime-probe.c -o Bridge/build/runtime-probe.obj
"$llvm_bin/llvm-dlltool" -m i386:x86-64 -d Bridge/runtime-kernel32.def -l Bridge/build/runtime-kernel32.lib
"${link[@]}" /Brepro /nodefaultlib /machine:x64 /entry:main /subsystem:console /dynamicbase /nxcompat /out:Bridge/build/moza-runtime-probe.exe Bridge/build/runtime-probe.obj Bridge/build/runtime-kernel32.lib Bridge/build/display-user32.lib
print "Built Bridge/build/moza-runtime-probe.exe"
"$llvm_bin/clang" -std=c11 -g -Wall -Wextra -Werror -fsanitize=address,undefined Bridge/tests/test_steam_cef.c -o Bridge/build/test-steam-cef
Bridge/build/test-steam-cef
"$llvm_bin/clang" --target=x86_64-pc-windows-msvc -std=c11 -O2 -ffreestanding -fno-builtin -fno-stack-protector -Wall -Wextra -Werror -c Bridge/steam-cef.c -o Bridge/build/steam-cef.obj
"$llvm_bin/llvm-dlltool" -m i386:x86-64 -d Bridge/steam-cef-kernel32.def -l Bridge/build/steam-cef-kernel32.lib
"${link[@]}" /Brepro /dll /nodefaultlib /machine:x64 /entry:DllMain /dynamicbase /nxcompat /out:Bridge/build/moza-steam-cef.dll /def:Bridge/steam-cef-exports.def Bridge/build/steam-cef.obj Bridge/build/steam-cef-kernel32.lib
print "Built Bridge/build/moza-steam-cef.dll"

mkdir -p Bridge/build/cef-check
"$llvm_bin/clang" --target=x86_64-pc-windows-msvc -std=c11 -O2 -ffreestanding -fno-builtin -fno-stack-protector -Wall -Wextra -Werror -c Bridge/tests/cef-wine-check.c -o Bridge/build/cef-wine-check.obj
"${link[@]}" /Brepro /nodefaultlib /machine:x64 /entry:main /subsystem:console /dynamicbase /nxcompat /out:Bridge/build/cef-check/steamwebhelper.exe Bridge/build/cef-wine-check.obj Bridge/build/runtime-kernel32.lib
