#!/usr/bin/env bash
set -euo pipefail

echo "==> Preparing MacSync DMG package..."

APP_NAME="MacSync"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" MacSync/Info.plist 2>/dev/null || echo "1.0.0")
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
APP_BUNDLE="${APP_NAME}.app"

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "==> ${APP_BUNDLE} not found. Running build.sh first..."
    ./build.sh
fi

rm -f "${DMG_NAME}" "${DMG_NAME}.sha256" "MacSync.dmg" "MacSync.dmg.sha256"

if command -v create-dmg >/dev/null 2>&1; then
    echo "==> Building installer DMG with create-dmg..."
    create-dmg \
      --volname "${APP_NAME} v${VERSION}" \
      --volicon "MacSync/AppIcon.icns" \
      --window-pos 200 120 \
      --window-size 660 400 \
      --icon-size 100 \
      --icon "${APP_BUNDLE}" 180 170 \
      --hide-extension "${APP_BUNDLE}" \
      --app-drop-link 480 170 \
      --no-strip \
      "${DMG_NAME}" \
      "${APP_BUNDLE}" || {
        echo "⚠️ create-dmg returned non-zero. Falling back to native hdiutil..."
    }
fi

if [ ! -f "${DMG_NAME}" ]; then
    echo "==> Building installer DMG with native hdiutil..."
    STAGING_DIR="dmg_staging"
    rm -rf "${STAGING_DIR}"
    mkdir -p "${STAGING_DIR}"
    cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
    ln -s /Applications "${STAGING_DIR}/Applications"

    hdiutil create \
      -volname "${APP_NAME} v${VERSION}" \
      -srcfolder "${STAGING_DIR}" \
      -ov \
      -format UDZO \
      "${DMG_NAME}"

    rm -rf "${STAGING_DIR}"
fi

shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256"
cp -f "${DMG_NAME}" "MacSync.dmg"
cp -f "${DMG_NAME}.sha256" "MacSync.dmg.sha256"

echo "✅ DMG Package ready: ${DMG_NAME} (also linked to MacSync.dmg)"
echo "   SHA256: $(cat "${DMG_NAME}.sha256")"
