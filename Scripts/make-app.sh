#!/bin/bash
# Собирает MozaControl.app из SwiftPM-продукта. Полный Xcode не требуется —
# бандл собирается вручную, подписывается ad-hoc подписью.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/MozaControl.app"
BINARY=".build/${CONFIG}/MozaControl"

echo "Сборка (${CONFIG})…"
swift build -c "${CONFIG}" --product MozaControl

echo "Сборка бандла ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BINARY}" "${APP}/Contents/MacOS/MozaControl"

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MozaControl</string>
    <key>CFBundleDisplayName</key>
    <string>MOZA Control</string>
    <key>CFBundleExecutable</key>
    <string>MozaControl</string>
    <key>CFBundleIdentifier</key>
    <string>house.moza.control</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <!-- Только иконка в строке меню, без значка в Dock. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string></string>
</dict>
</plist>
PLIST

# Ad-hoc подпись: без неё macOS не даёт приложению доступ к устройствам.
# Приложение НЕ в песочнице — в песочнице IOKit-доступ к HID молча не работает.
codesign --force --sign - --timestamp=none "${APP}" >/dev/null 2>&1

echo "Готово: ${APP}"
echo "Запуск: open ${APP}"
