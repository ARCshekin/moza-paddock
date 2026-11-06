#!/usr/bin/env python3
"""Install the game-local Win64 bridge and an R5 controls profile, with backups."""
import argparse
import configparser
import datetime
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--bottle", default="Steam-3")
args = parser.parse_args()
bottle = Path.home() / "Library/Application Support/CrossOver/Bottles" / args.bottle
game = bottle / "drive_c/Program Files (x86)/Steam/steamapps/common/assettocorsa"
wine = Path.home() / "Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"
dll = ROOT / "Bridge/build/dinput8.dll"
if not dll.is_file() or not (game / "acs.exe").is_file():
    raise SystemExit("Build Scripts/build-ac-bridge.sh first; check --bottle and installed Assetto Corsa.")
processes = subprocess.check_output(["ps", "ax", "-o", "command="], text=True)
if any(line.strip().lower().endswith("/acs.exe") or line.strip().lower().endswith("\\acs.exe")
       for line in processes.splitlines()):
    raise SystemExit("Exit the running Assetto Corsa session before installing.")

backup = ROOT / "build/ac-backups" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
backup.mkdir(parents=True)
cfg = Path.home() / "Documents/Assetto Corsa/cfg"
cfg.mkdir(parents=True, exist_ok=True)
target = game / "dinput8.dll"
if target.exists():
    shutil.copy2(target, backup / "dinput8.dll")
shutil.copy2(dll, target)
display_launcher = ROOT / "Bridge/build/moza-display-launcher.exe"
if display_launcher.is_file():
    shutil.copy2(display_launcher, game / display_launcher.name)

controls = cfg / "controls.ini"
if controls.exists():
    shutil.copy2(controls, backup / "controls.ini")
else:
    shutil.copy2(game / "cfg/controls.ini", controls)
c = configparser.ConfigParser(strict=False, inline_comment_prefixes=(";",))
c.optionxform = str
c.read(controls)
updates = {
    "HEADER": {"INPUT_METHOD": "WHEEL"},
    "CONTROLLERS": {"CON0": "MOZA R5 Bridge", "PGUID0": "0004346E-0000-0000-0000-504944564944"},
    "STEER": {"JOY": 0, "AXLE": 0, "SCALE": 1, "LOCK": 900, "FF_GAIN": 1,
              "FILTER_FF": 0, "STEER_GAMMA": 1, "STEER_FILTER": 0, "SPEED_SENSITIVITY": 0},
    "THROTTLE": {"JOY": 0, "AXLE": 1, "MIN": -1, "MAX": 1},
    "BRAKES": {"JOY": 0, "AXLE": 5, "MIN": -1, "MAX": 1, "GAMMA": 1},
    "CLUTCH": {"JOY": -1, "AXLE": -1},
    "GEARUP": {"JOY": 0, "BUTTON": 13},
    "GEARDN": {"JOY": 0, "BUTTON": 12},
    "FF_TWEAKS": {"MIN_FF": 0, "CENTER_BOOST_GAIN": 0},
}
for section, values in updates.items():
    if not c.has_section(section):
        c.add_section(section)
    for key, value in values.items():
        c.set(section, key, str(value))
with controls.open("w") as f:
    c.write(f, space_around_delimiters=False)

key = r"HKCU\Software\Wine\AppDefaults\acs.exe\DllOverrides"
previous = subprocess.run([str(wine), "--bottle", args.bottle, "reg", "query", key,
                           "/v", "dinput8"], capture_output=True, text=True)
(backup / "dinput8-override-before.txt").write_text(previous.stdout + previous.stderr)
subprocess.run([str(wine), "--bottle", args.bottle, "reg", "add", key, "/v", "dinput8",
                "/t", "REG_SZ", "/d", "native,builtin", "/f"], check=True)
print(f"Installed: {target}\nControls: {controls}\nBackups: {backup}")
print("Use Scripts/play-assetto.command. Match the wheel's physical rotation to 900 degrees.")
