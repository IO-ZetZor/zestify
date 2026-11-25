#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_dir=$(mktemp -d /tmp/zestify-drawer.XXXXXX)
trap 'rm -rf -- "$test_dir"' EXIT HUP INT TERM
cp -R "$repo_dir/shell/." "$test_dir/"
sed 's|../../shell/||g' "$repo_dir/tests/quickshell/drawer.qml" > "$test_dir/shell.qml"
# Freeze only the fixture's fullscreen detection so focus checks do not
# depend on which desktop application the user currently has fullscreen.
sed 's/readonly property bool fullscreen: BackgroundLib.isFullscreen(activeWorkspace)/property bool fullscreen: false/' \
    "$test_dir/components/Pill.qml" > "$test_dir/components/Pill.qml.test"
mv "$test_dir/components/Pill.qml.test" "$test_dir/components/Pill.qml"
mkdir -p "$test_dir/config/zestify"
cp "$repo_dir/config/default.json" "$test_dir/config/zestify/config.json"
cat > "$test_dir/capture-stub" <<'EOF'
#!/bin/sh
case "$*" in
    'capture record status')
        if [ -f "$DRAWER_CAPTURE_LOG.recording" ]; then
            printf '{"recording": true, "path": "/tmp/test-recording.mp4"}\n'
        else
            printf '{"recording": false}\n'
        fi ;;
    'capture record toggle')
        printf '%s\n' "$*" >> "$DRAWER_CAPTURE_LOG"
        if [ -f "$DRAWER_CAPTURE_LOG.recording" ]; then
            rm "$DRAWER_CAPTURE_LOG.recording"
            printf '{"ok": true, "recording": false, "path": "/tmp/test-recording.mp4"}\n'
        else
            touch "$DRAWER_CAPTURE_LOG.recording"
            printf '{"ok": true, "recording": true, "path": "/tmp/test-recording.mp4"}\n'
        fi ;;
    'capture screenshot')
        printf '%s\n' "$*" >> "$DRAWER_CAPTURE_LOG"
        printf '{"ok": true, "path": "/tmp/test-screenshot.png"}\n' ;;
    *) printf '{"ok": true}\n' ;;
esac
EOF
chmod +x "$test_dir/capture-stub"
# A separate bus protects the running shell's notification service. Session
# helper commands are stubbed; the fixture never calls the real locker.
QT_NO_XDG_DESKTOP_PORTAL=1 XDG_CONFIG_HOME="$test_dir/config" ZESTI_BIN="$test_dir/capture-stub" PYTHON=/usr/bin/true \
    DRAWER_CAPTURE_LOG="$test_dir/capture.log" DRAWER_SHORTCUT_PREVIEW=/tmp/zestify-shortcuts-preview.png \
    DRAWER_POINTER_SCRIPT="$repo_dir/tests/quickshell/drawer-pointer.py" \
    timeout 90s dbus-run-session qs -p "$test_dir/shell.qml" --no-color
