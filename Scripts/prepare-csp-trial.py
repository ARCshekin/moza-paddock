#!/usr/bin/env python3
"""Prepare the optional separate CSP/Metal test installation."""
from runtime.csp_trial import prepare

if __name__ == '__main__':
    runtime = prepare()
    print('Prepared CSP test copy:', runtime.game)
    print('Launch: python3 Scripts/play-csp-trial.py --renderer dxmt --hud')
