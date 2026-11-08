#!/bin/zsh
set -eu
cd "${0:A:h:h}"
project_dir=$PWD
bottle=${MOZA_AC_BOTTLE:-Steam-3}
runtime=${MOZA_AC_RUNTIME:-crossover}
runtime_root=${MOZA_AC_ROOT:-"$HOME/Library/Application Support/MozaPaddock"}
game="C:/Program Files (x86)/Steam/steamapps/common/assettocorsa"
bridge="$project_dir/.build/debug/moza-ac-bridge"
game_dir="$HOME/Library/Application Support/CrossOver/Bottles/$bottle/drive_c/Program Files (x86)/Steam/steamapps/common/assettocorsa"
if [[ "$runtime" == standalone ]]; then
    game_dir="$runtime_root/Prefixes/assetto/drive_c/Program Files (x86)/Steam/steamapps/common/assettocorsa"
fi
bridge_pid=""
cleanup_session() {
    local game_status=$?
    # A duplicate helper must not shut down the prefix owned by the first one.
    if [[ "$game_status" == 6 ]]; then return "$game_status"; fi
    if [[ -n "$bridge_pid" ]]; then kill -TERM "$bridge_pid" 2>/dev/null || true; fi
    /usr/bin/python3 "$project_dir/Scripts/paddock-runtime.py" --root "$runtime_root" \
        shutdown --provider "$runtime" --bottle "$bottle" || true
    if [[ "${MOZA_AC_ONLINE:-0}" == 1 ]]; then
        /usr/bin/python3 "$project_dir/Scripts/paddock-online.py" clear-session \
            --documents "${MOZA_AC_DOCUMENTS:-$HOME/Documents/Assetto Corsa}" || true
    fi
    return "$game_status"
}
trap cleanup_session EXIT
mkdir -p build
[[ -x "$bridge" ]] || swift build --product moza-ac-bridge
[[ -f Bridge/build/moza-display-launcher.exe ]] || ./Scripts/build-ac-bridge.sh
cp Bridge/build/moza-display-launcher.exe "$game_dir/moza-display-launcher.exe"
# Exclusive fullscreen chooses Wine's primary monitor. The display launcher
# creates a borderless full-display window on the external monitor instead.
if [[ "${MOZA_AC_KEEP_VIDEO:-0}" != 1 ]]; then
python3 - <<'PY'
from pathlib import Path
import configparser
path = Path.home() / 'Documents/Assetto Corsa/cfg/video.ini'
config = configparser.ConfigParser()
config.optionxform = str
config.read(path)
config['VIDEO']['FULLSCREEN'] = '0'
config['VIDEO']['WIDTH'] = '1920'
config['VIDEO']['HEIGHT'] = '1080'
with path.open('w') as file:
    config.write(file, space_around_delimiters=False)
PY
fi
if pgrep -f '(^|/)moza-ac-bridge( |$)' >/dev/null; then
    print 'Мост MOZA уже запущен; использую его.'
else
    "$bridge" --gain "${MOZA_AC_GAIN:-1}" >> build/ac-bridge-live.log 2>&1 &
    bridge_pid=$!
    print "$bridge_pid" > build/ac-bridge.pid
fi
printf 'Assetto Corsa + MOZA R5. Игровая отдача %.0f%%, плавное включение за 2 секунды.\n' "$(( ${MOZA_AC_GAIN:-1} * 100 ))"
print 'Экран: внешний монитор, отдельное окно без рамок на весь экран.'
print 'Лепестки: левый — вниз, правый — вверх. Начать заезд — кнопка Drive в игре.'
SteamAppId=244210 SteamGameId=244210 /usr/bin/python3 "$project_dir/Scripts/paddock-runtime.py" \
    --root "$runtime_root" wine --provider "$runtime" --bottle "$bottle" \
    --cwd "$game_dir" -- "$game/moza-display-launcher.exe"
