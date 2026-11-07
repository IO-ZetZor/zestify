#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PURGE=0

for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        -h|--help)
            cat <<'EOF'
usage: uninstall.sh [--purge]
EOF
            exit 0
            ;;
        *)
            printf 'unknown option: %s\n' "$arg" >&2
            exit 2
            ;;
    esac
done

say() {
    printf '%s\n' "$*"
}

CONFIG_DIR="$HOME/.config/zestify"
STATE_DIR="$HOME/.local/state/zestify"
CACHE_DIR="$HOME/.cache/zestify"
QUICKSHELL_LINK="$HOME/.config/quickshell/zestify"
ZESTI_LINK="$HOME/.local/bin/zesti"
ZESTIFY_LINK="$HOME/.local/bin/zestify"
HYPR_CONF="$HOME/.config/hypr/conf"
AUTOSTART="$HYPR_CONF/autostart.lua"
BINDS="$HYPR_CONF/binds.lua"

say "Zestify uninstaller"

# Stop the Zestify shell if it is running (compat entry point accepted too).
if command -v zesti >/dev/null 2>&1; then
    zesti shell stop >/dev/null 2>&1 || true
elif command -v zestify >/dev/null 2>&1; then
    zestify shell stop >/dev/null 2>&1 || true
fi
pkill -f 'qs -c zestify' >/dev/null 2>&1 || true

if [[ -L "$QUICKSHELL_LINK" ]]; then
    rm -f -- "$QUICKSHELL_LINK"
fi
if [[ -L "$ZESTI_LINK" ]]; then
    rm -f -- "$ZESTI_LINK"
fi
if [[ -L "$ZESTIFY_LINK" ]]; then
    rm -f -- "$ZESTIFY_LINK"
fi
rm -f -- "$HYPR_CONF/zestify.lua"

python3 - "$BINDS" "$AUTOSTART" <<'PY'
import sys
from pathlib import Path


def drop_block(path: Path, begin: str, end: str) -> None:
    if not path.exists():
        return
    kept = []
    inside = False
    for line in path.read_text().splitlines(keepends=True):
        if begin in line:
            inside = True
            continue
        if end in line:
            inside = False
            continue
        if not inside:
            kept.append(line)
    path.write_text("".join(kept))


def drop_autostart_block(path: Path) -> None:
    if not path.exists():
        return
    kept = []
    inside = False
    for line in path.read_text().splitlines(keepends=True):
        if ">>> zestify-autostart >>>" in line:
            inside = True
            continue
        if "<<< zestify-autostart <<<" in line:
            inside = False
            continue
        if not inside:
            kept.append(line)
    path.write_text("".join(kept))


binds = Path(sys.argv[1])
autostart = Path(sys.argv[2])
drop_block(binds, ">>> zestify-binds >>>", "<<< zestify-binds <<<")
drop_autostart_block(autostart)
PY

if (( PURGE )); then
    rm -rf -- "$CONFIG_DIR" "$STATE_DIR" "$CACHE_DIR"
fi

say "uninstalled"
