#!/bin/sh
# install-daemon.sh — install or uninstall the Odyssey sidecar launchd agent
# Usage: install-daemon.sh install | uninstall

set -e

LABEL="com.odyssey.sidecar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# Locate bun
BUN_PATH="$HOME/.bun/bin/bun"
if [ ! -f "$BUN_PATH" ]; then
    BUN_PATH="$(command -v bun 2>/dev/null || true)"
fi
if [ -z "$BUN_PATH" ] || [ ! -f "$BUN_PATH" ]; then
    echo "Error: bun not found. Install bun first: https://bun.sh" >&2
    exit 1
fi

# Locate sidecar index.ts — sibling of this script's app bundle
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# When bundled, script is at Contents/Resources/install-daemon.sh
APP_BUNDLE="$(echo "$SCRIPT_DIR" | sed 's|/Contents/Resources$||')"
SIDECAR_INDEX="$APP_BUNDLE/Contents/Resources/sidecar/src/index.ts"
if [ ! -f "$SIDECAR_INDEX" ]; then
    # Fallback: look relative to script in dev builds
    SIDECAR_INDEX="$(dirname "$SCRIPT_DIR")/src/index.ts"
fi
if [ ! -f "$SIDECAR_INDEX" ]; then
    echo "Error: sidecar/src/index.ts not found at $SIDECAR_INDEX" >&2
    exit 1
fi

case "$1" in
install)
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BUN_PATH</string>
        <string>run</string>
        <string>$SIDECAR_INDEX</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.odyssey/logs/sidecar-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.odyssey/logs/sidecar-daemon-err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>$HOME</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
EOF
    mkdir -p "$HOME/.odyssey/logs"
    launchctl load "$PLIST"
    echo "Odyssey sidecar daemon installed and started."
    ;;
uninstall)
    if [ -f "$PLIST" ]; then
        launchctl unload "$PLIST" 2>/dev/null || true
        rm -f "$PLIST"
        echo "Odyssey sidecar daemon removed."
    else
        echo "Daemon plist not found — nothing to uninstall."
    fi
    ;;
*)
    echo "Usage: $0 install | uninstall" >&2
    exit 1
    ;;
esac
