#!/bin/zsh
set -eu
cd "${0:A:h:h}"
configuration=release
install_server=1
for argument in "$@"; do
    case "$argument" in
        release|debug) configuration="$argument" ;;
        --without-server) install_server=0 ;;
        *) print -u2 "Usage: $0 [release|debug] [--without-server]"; exit 2 ;;
    esac
done
if (( install_server )); then
    python3 Scripts/paddock-server.py install --root "$HOME/Library/Application Support/MozaPaddock"
    python3 Scripts/paddock-runtime.py --root "$HOME/Library/Application Support/MozaPaddock" install
fi
swift build -c "$configuration" --product MozaPaddock
swift build --product moza-ac-bridge
[[ -f Bridge/build/moza-display-launcher.exe && -f Bridge/build/moza-runtime-probe.exe && -f Bridge/build/moza-steam-cef.dll ]] || ./Scripts/build-ac-bridge.sh
app="$PWD/build/MozaPaddock.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/$configuration/MozaPaddock" "$app/Contents/MacOS/MozaPaddock.new"
mv -f "$app/Contents/MacOS/MozaPaddock.new" "$app/Contents/MacOS/MozaPaddock"
print -r -- "$PWD" > "$app/Contents/Resources/project-path.txt"
if [[ ! -f build/Paddock.icns || Scripts/paddock-icon.swift -nt build/Paddock.icns ]]; then
    swift Scripts/paddock-icon.swift build/Paddock.iconset
    iconutil -c icns build/Paddock.iconset -o build/Paddock.icns
fi
cp build/Paddock.icns "$app/Contents/Resources/Paddock.icns"
server_tools="$app/Contents/Resources/ServerTools"
mkdir -p "$server_tools/runtime" "$server_tools/online"
cp Scripts/paddock-server.py Scripts/paddock-online.py Scripts/paddock-runtime.py Scripts/paddock-mods.py "$server_tools/"
cp Scripts/runtime/*.py Scripts/runtime/*.json "$server_tools/runtime/"
cp Scripts/online/*.py "$server_tools/online/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MozaPaddock</string>
<key>CFBundleDisplayName</key><string>MOZA Paddock</string>
<key>CFBundleExecutable</key><string>MozaPaddock</string>
<key>CFBundleIdentifier</key><string>house.moza.paddock</string>
<key>CFBundleIconFile</key><string>Paddock.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSLocalNetworkUsageDescription</key><string>Поиск серверов Assetto Corsa в вашей локальной сети.</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Local MOZA / Assetto Corsa companion</string>
</dict></plist>
PLIST
codesign --force --sign - --timestamp=none "$app"
print "Built $app"
