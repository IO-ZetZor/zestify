#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_dir=$(mktemp -d /tmp/zestify-drawer.XXXXXX)
trap 'rm -rf -- "$test_dir"' EXIT HUP INT TERM
cp -R "$repo_dir/shell/." "$test_dir/"
sed 's|../../shell/||g' "$repo_dir/tests/quickshell/drawer.qml" > "$test_dir/shell.qml"
# Freeze only the fixture's fullscreen detection so focus checks do not
# depend on which desktop application the user currently has fullscreen.
sed 's/readonly property bool fullscreen: BackgroundLib.isFullscreen(activeWorkspace)/readonly property bool fullscreen: false/' \
    "$test_dir/components/Pill.qml" > "$test_dir/components/Pill.qml.test"
mv "$test_dir/components/Pill.qml.test" "$test_dir/components/Pill.qml"
mkdir -p "$test_dir/config/zestify"
cp "$repo_dir/config/default.json" "$test_dir/config/zestify/config.json"
# A separate bus protects the running shell's notification service. Session
# helper commands are stubbed; the fixture never calls the real locker.
QT_NO_XDG_DESKTOP_PORTAL=1 XDG_CONFIG_HOME="$test_dir/config" ZESTI_BIN=/usr/bin/true PYTHON=/usr/bin/true \
    DRAWER_POINTER_SCRIPT="$repo_dir/tests/quickshell/drawer-pointer.py" \
    timeout 30s dbus-run-session qs -p "$test_dir/shell.qml" --no-color
