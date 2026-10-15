#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$PROJECT_DIR/Elaina.app"
mkdir -p "$BUILD_DIR/module-cache" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
for old_bread in bread-00.png bread-01.png bread-02.png bread-03.png; do
    rm -f "$APP_DIR/Contents/Resources/$old_bread"
done
for asset in idle.png walk_0.png walk_1.png walk_2.png walk_3.png broom_0.png broom_1.png broom_2.png broom_3.png broom-animation.json dialogues.json life-animation.json grab-00.png grab-01.png held-00.png held-01.png held-02.png held-03.png release-00.png release-01.png release-02.png release-03.png annoyed-00.png annoyed-01.png bread-progress-00.png bread-progress-01.png bread-progress-02.png bread-progress-03.png bread-progress-04.png bread-progress-05.png bread-progress-06.png bread-progress-07.png bread-progress-08.png bread-progress-09.png; do
    if [[ ! -f "$PROJECT_DIR/Assets/$asset" ]]; then
        echo "Missing asset: $asset" >&2
        exit 1
    fi
    cp "$PROJECT_DIR/Assets/$asset" "$APP_DIR/Contents/Resources/$asset"
done
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
mkdir -p "$APP_DIR/Contents/Resources/Fonts"
for font_resource in Cubic_11.ttf OFL.txt SOURCE.json; do
    cp "$PROJECT_DIR/Assets/Fonts/$font_resource" "$APP_DIR/Contents/Resources/Fonts/$font_resource"
done
if [[ -f "$PROJECT_DIR/Assets/Elaina.icns" ]]; then
    cp "$PROJECT_DIR/Assets/Elaina.icns" "$APP_DIR/Contents/Resources/Elaina.icns"
fi
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
for arch in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -O -whole-module-optimization \
        -module-cache-path "$BUILD_DIR/module-cache" -target "$arch-apple-macos12.0" \
        "$PROJECT_DIR/Sources/PetGeometry.swift" "$PROJECT_DIR/Sources/PetNotifications.swift" \
        "$PROJECT_DIR/Sources/PetPresentation.swift" "$PROJECT_DIR/Sources/PetBehavior.swift" "$PROJECT_DIR/Sources/PetInteractions.swift" "$PROJECT_DIR/Sources/PetFullscreen.swift" "$PROJECT_DIR/Sources/ElainaApp.swift" \
        -framework AppKit -framework QuartzCore -o "$BUILD_DIR/Elaina-$arch"
    xcrun swiftc -swift-version 5 -O -whole-module-optimization \
        -module-cache-path "$BUILD_DIR/module-cache" -target "$arch-apple-macos12.0" \
        "$PROJECT_DIR/Sources/PetNotifications.swift" "$PROJECT_DIR/Sources/ElainaNotify.swift" \
        -o "$BUILD_DIR/elaina-notify-$arch"
done
lipo -create "$BUILD_DIR/Elaina-arm64" "$BUILD_DIR/Elaina-x86_64" -output "$APP_DIR/Contents/MacOS/Elaina"
lipo -create "$BUILD_DIR/elaina-notify-arm64" "$BUILD_DIR/elaina-notify-x86_64" -output "$APP_DIR/Contents/MacOS/elaina-notify"
codesign --force --sign - "$APP_DIR/Contents/MacOS/elaina-notify"
codesign --force --sign - "$APP_DIR"
if [[ "${1:-}" != "--skip-self-test" ]]; then
    "$APP_DIR/Contents/MacOS/Elaina" --self-test
    xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_DIR/module-cache" \
        "$PROJECT_DIR/Sources/PetGeometry.swift" "$PROJECT_DIR/Tests/main.swift" -o "$BUILD_DIR/geometry-tests"
    "$BUILD_DIR/geometry-tests"
    xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_DIR/module-cache" \
        "$PROJECT_DIR/Sources/PetNotifications.swift" "$PROJECT_DIR/Tests/notifications.swift" -o "$BUILD_DIR/notification-tests"
    "$BUILD_DIR/notification-tests"
    xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_DIR/module-cache" \
        "$PROJECT_DIR/Sources/PetPresentation.swift" "$PROJECT_DIR/Sources/PetBehavior.swift" "$PROJECT_DIR/Sources/PetInteractions.swift" "$PROJECT_DIR/Sources/PetFullscreen.swift" \
        "$PROJECT_DIR/Tests/behavior.swift" -framework AppKit -o "$BUILD_DIR/behavior-tests"
    "$BUILD_DIR/behavior-tests"
    SPEECH_APP="$BUILD_DIR/speech-tests.app"
    mkdir -p "$SPEECH_APP/Contents/MacOS" "$SPEECH_APP/Contents/Resources/Fonts"
    cp "$PROJECT_DIR/Assets/Fonts/"* "$SPEECH_APP/Contents/Resources/Fonts/"
    cp "$PROJECT_DIR/Assets/dialogues.json" "$SPEECH_APP/Contents/Resources/"
    cat > "$SPEECH_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>speech-tests</string><key>CFBundleIdentifier</key><string>local.elaina.speech-tests</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
    xcrun swiftc -swift-version 5 -D ELAINA_SPEECH_TEST -module-cache-path "$BUILD_DIR/module-cache" \
        "$PROJECT_DIR/Sources/PetGeometry.swift" "$PROJECT_DIR/Sources/PetNotifications.swift" \
        "$PROJECT_DIR/Sources/PetPresentation.swift" "$PROJECT_DIR/Sources/PetBehavior.swift" \
        "$PROJECT_DIR/Sources/PetInteractions.swift" "$PROJECT_DIR/Sources/PetFullscreen.swift" \
        "$PROJECT_DIR/Sources/ElainaApp.swift" "$PROJECT_DIR/Tests/speech.swift" \
        -framework AppKit -framework QuartzCore -o "$SPEECH_APP/Contents/MacOS/speech-tests"
    "$SPEECH_APP/Contents/MacOS/speech-tests" --render "$BUILD_DIR/speech-qa"
fi
echo "Built: $APP_DIR"
