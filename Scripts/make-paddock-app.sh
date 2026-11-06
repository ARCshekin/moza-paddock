#!/bin/zsh
set -eu
cd "${0:A:h:h}"
configuration=${1:-release}
swift build -c "$configuration" --product MozaPaddock
swift build --product moza-ac-bridge
[[ -f Bridge/build/moza-display-launcher.exe && -f Bridge/build/moza-runtime-probe.exe ]] || ./Scripts/build-ac-bridge.sh
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
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Local MOZA / Assetto Corsa companion</string>
</dict></plist>
PLIST
codesign --force --sign - --timestamp=none "$app"
print "Built $app"
