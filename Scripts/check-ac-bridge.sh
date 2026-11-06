#!/bin/zsh
set -eu
cd "${0:A:h:h}"
./Scripts/build-ac-bridge.sh
swift build --product moza-ac-bridge
bin_dir=$(swift build --show-bin-path)
mkdir -p build/native-tests
python3 - <<'PY'
from pathlib import Path
import re
source = Path('Tests/MozaBridgeTests/EffectEngineTests.swift').read_text()
source = source.replace('import XCTest', 'import Foundation').replace('@testable import MozaKit', '')
methods = re.findall(r'func (test\w+)\(\)( throws)?', source)
for name, throws in methods:
    source += '\n' + ('try ' if throws else '') + 'EffectEngineTests().' + name + '()'
source += '\nprint("PASS native bridge: ' + str(len(methods)) + ' effect/shared-memory checks")\n'
Path('build/native-tests/main.swift').write_text(source)
PY
swiftc -I "$bin_dir/CBridgeAtomics.build" \
  Sources/MozaKit/EffectEngine.swift Sources/MozaKit/SharedBridge.swift \
  Bridge/tests/Assertions.swift build/native-tests/main.swift \
  "$bin_dir/CBridgeAtomics.build/cbridge_atomics.c.o" \
  -o build/native-tests/check
build/native-tests/check
