#!/bin/zsh
# Confirmed Alpine profile: independent Wine + DXMT, separate from Audi.
set -eu
cd "${0:A:h:h}"
exec /usr/bin/python3 Scripts/play-csp-trial.py --renderer dxmt --hud
