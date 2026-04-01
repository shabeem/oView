#!/bin/bash
# OView Installer — double-click this file to install OView

echo "==========================="
echo "  OView Installer"
echo "==========================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/OView.app"

if [ ! -d "$APP_PATH" ]; then
    # Check common locations
    for dir in ~/Downloads ~/Desktop; do
        if [ -d "$dir/OView.app" ]; then
            APP_PATH="$dir/OView.app"
            break
        fi
    done
fi

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: OView.app not found."
    echo "Make sure OView.app is in the same folder as this script."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

echo "Found: $APP_PATH"
echo ""

# Remove macOS quarantine
echo "Removing quarantine flag..."
xattr -cr "$APP_PATH"

# Reset Screen Recording permission for clean start
echo "Resetting Screen Recording permission..."
tccutil reset ScreenCapture com.oview.app 2>/dev/null

# Copy to Applications
echo "Copying to /Applications..."
cp -R "$APP_PATH" /Applications/OView.app 2>/dev/null
xattr -cr /Applications/OView.app 2>/dev/null

echo ""
echo "Done! Launching OView..."
echo ""
echo "IMPORTANT: When prompted, grant Screen Recording permission,"
echo "then quit and reopen OView."
echo ""

open /Applications/OView.app 2>/dev/null || open "$APP_PATH"

read -p "Press Enter to close..."
