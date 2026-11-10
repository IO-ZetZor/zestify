#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_dir=$(mktemp -d /tmp/zestify-lock-pull.XXXXXX)
trap 'rm -rf -- "$test_dir"' EXIT HUP INT TERM

# Quickshell resolves local imports inside its configuration root.
cp -R "$repo_dir/shell/." "$test_dir/"
sed 's|../../shell/||g' "$repo_dir/tests/quickshell/lockpull.qml" > "$test_dir/shell.qml"

# Exercise lock-state transitions without invoking the real locker.
ZESTI_BIN=/usr/bin/true PYTHON=/usr/bin/true \
    LOCK_PULL_TEST_SCRIPT="$repo_dir/tests/quickshell/lockpull-pointer.py" \
    timeout 20s qs -p "$test_dir/shell.qml" --no-color
