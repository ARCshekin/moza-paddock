#!/bin/zsh
set -eu
cd "${0:A:h:h}"
if [[ -f build/ac-bridge.pid ]]; then
    bridge_pid=$(cat build/ac-bridge.pid)
    if [[ "$bridge_pid" == <-> ]] && ps -p "$bridge_pid" -o command= | /usr/bin/grep -q 'moza-ac-bridge'; then
        kill -TERM "$bridge_pid"
        print 'Отдача и мост управления остановлены.'
    else
        print 'Мост уже остановлен.'
    fi
else
    print 'Мост не запускался этим комплектом.'
fi
