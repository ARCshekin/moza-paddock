#!/bin/bash
# Возвращает включённую UDP-телеметрию в настройках DiRT Rally.
#
# Зачем: игра читает настройки при старте и перезаписывает файл на выходе,
# сбрасывая правку. Сторож ждёт, пока игра закрыта, и возвращает настройку —
# тогда следующий запуск игры её подхватит, в каком порядке ни делай.
CFG="$HOME/Library/Application Support/Feral Interactive/DiRT Rally/VFS/User/AppData/Roaming/My Games/DiRT Rally/hardwaresettings/hardware_settings_config.xml"
MINUTES="${1:-90}"
deadline=$(( $(date +%s) + MINUTES * 60 ))

while [ "$(date +%s)" -lt "$deadline" ]; do
  if ! pgrep -f "DiRT Rally.app/Contents/MacOS/DiRT Rally" > /dev/null; then
    if grep -q '<udp enabled="false"' "$CFG" 2>/dev/null; then
      python3 - "$CFG" << 'PYEOF'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = re.sub(r'(<udp [^/]*?)enabled="[^"]*"', r'\1enabled="true"', s)
s = re.sub(r'(<udp [^/]*?)extradata="[^"]*"', r'\1extradata="3"', s)
p.write_text(s)
PYEOF
      echo "$(date +%H:%M:%S) телеметрия возвращена в настройки"
    fi
  fi
  sleep 2
done
echo "сторож завершил работу"
