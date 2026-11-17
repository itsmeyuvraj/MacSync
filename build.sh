#!/usr/bin/env bash
set -euo pipefail

echo "==> Building MacSync Native Application..."

SDK_PATH="$(xcrun --show-sdk-path)"
MACRO_PLUGIN_PATH="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins"

swiftc \
  -sdk "${SDK_PATH}" \
  -plugin-path "${MACRO_PLUGIN_PATH}" \
  -target arm64-apple-macosx14.0 \
  -O \
  -I /opt/homebrew/opt/libmtp/include \
  -L /opt/homebrew/opt/libmtp/lib \
  -lmtp \
  -import-objc-header MacSync/Bridging-Header.h \
  MacSync/Models/MTPModels.swift \
  MacSync/Services/MTPService.swift \
  MacSync/Services/LocalFileService.swift \
  MacSync/Controllers/QuickLookController.swift \
  MacSync/ViewModels/AppViewModel.swift \
  MacSync/Views/FilePaneViews.swift \
  MacSync/Views/ContentView.swift \
  MacSync/App.swift \
  -o MacSyncBinary

echo "==> Assembling MacSync.app bundle..."
mkdir -p MacSync.app/Contents/MacOS MacSync.app/Contents/Resources MacSync.app/Contents/Frameworks
cp MacSync/Info.plist MacSync.app/Contents/Info.plist
if [ -f "MacSync/AppIcon.icns" ]; then
    cp MacSync/AppIcon.icns MacSync.app/Contents/Resources/AppIcon.icns
fi
mv MacSyncBinary MacSync.app/Contents/MacOS/MacSync
chmod +x MacSync.app/Contents/MacOS/MacSync

echo "==> Bundling Homebrew libmtp & libusb dylibs into standalone App Bundle..."
if [ -d "/opt/homebrew" ]; then
    BREW_PREFIX="/opt/homebrew"
elif [ -d "/usr/local" ]; then
    BREW_PREFIX="/usr/local"
else
    BREW_PREFIX="$(brew --prefix 2>/dev/null || echo '/opt/homebrew')"
fi

FRAMEWORKS_DIR="MacSync.app/Contents/Frameworks"
LIBMTP_SRC="${BREW_PREFIX}/opt/libmtp/lib/libmtp.9.dylib"
LIBUSB_SRC="${BREW_PREFIX}/opt/libusb/lib/libusb-1.0.0.dylib"
[ ! -f "${LIBMTP_SRC}" ] && LIBMTP_SRC="${BREW_PREFIX}/lib/libmtp.9.dylib"
[ ! -f "${LIBUSB_SRC}" ] && LIBUSB_SRC="${BREW_PREFIX}/lib/libusb-1.0.0.dylib"

cp -f "${LIBMTP_SRC}" "${FRAMEWORKS_DIR}/libmtp.9.dylib"
cp -f "${LIBUSB_SRC}" "${FRAMEWORKS_DIR}/libusb-1.0.0.dylib"
chmod 755 "${FRAMEWORKS_DIR}"/*.dylib

# Update internal IDs and dependency paths to @rpath
install_name_tool -id @rpath/libusb-1.0.0.dylib "${FRAMEWORKS_DIR}/libusb-1.0.0.dylib"
install_name_tool -id @rpath/libmtp.9.dylib "${FRAMEWORKS_DIR}/libmtp.9.dylib"
install_name_tool -change "${BREW_PREFIX}/opt/libusb/lib/libusb-1.0.0.dylib" @rpath/libusb-1.0.0.dylib "${FRAMEWORKS_DIR}/libmtp.9.dylib" 2>/dev/null || true
install_name_tool -change "${BREW_PREFIX}/lib/libusb-1.0.0.dylib" @rpath/libusb-1.0.0.dylib "${FRAMEWORKS_DIR}/libmtp.9.dylib" 2>/dev/null || true

# Update main executable rpath and dylib link
install_name_tool -add_rpath @executable_path/../Frameworks "MacSync.app/Contents/MacOS/MacSync" 2>/dev/null || true
install_name_tool -change "${BREW_PREFIX}/opt/libmtp/lib/libmtp.9.dylib" @rpath/libmtp.9.dylib "MacSync.app/Contents/MacOS/MacSync" 2>/dev/null || true
install_name_tool -change "${BREW_PREFIX}/lib/libmtp.9.dylib" @rpath/libmtp.9.dylib "MacSync.app/Contents/MacOS/MacSync" 2>/dev/null || true

# Codesign bundled dylibs
codesign --force --sign - "${FRAMEWORKS_DIR}/libusb-1.0.0.dylib"
codesign --force --sign - "${FRAMEWORKS_DIR}/libmtp.9.dylib"

echo "==> Code signing with USB and filesystem entitlements..."
codesign --force --deep --sign - --entitlements MacSync/MacSync.entitlements MacSync.app

# Refresh LaunchServices icon registration and touch bundle
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f MacSync.app 2>/dev/null || true
touch MacSync.app

echo "✅ Build complete: MacSync.app is ready!"
echo "   Launch with: open MacSync.app"
