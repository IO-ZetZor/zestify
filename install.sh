#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DRY_RUN=0
START=1
PURGE=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --no-start) START=0 ;;
        --purge) PURGE=1 ;;
        -h|--help)
            cat <<'EOF'
usage: install.sh [--dry-run] [--no-start] [--purge]
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

run() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    if (( ! DRY_RUN )); then
        "$@"
    fi
}

backup() {
    local file=$1
    (( DRY_RUN )) && return 0
    cp -p -- "$file" "$file.zestify.bak.$(date +%s)"
}

# The previous shell is NOT a runtime dependency of Zestify. Only the core
# shell and desktop tools are required. Quickshell provides session locking and PAM.
missing=()
for dep in qs python3 ffmpeg jq brightnessctl wpctl; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        missing+=("$dep")
    fi
done
if (( ${#missing[@]} > 0 )); then
    printf 'missing dependencies: %s\n' "${missing[*]}" >&2
    exit 1
fi

CONFIG_DIR="$HOME/.config/zestify"
STATE_DIR="$HOME/.local/state/zestify"
CACHE_DIR="$HOME/.cache/zestify"
QUICKSHELL_LINK="$HOME/.config/quickshell/zestify"
ZESTI_LINK="$HOME/.local/bin/zesti"
ZESTIFY_LINK="$HOME/.local/bin/zestify"
HYPR_CONF="$HOME/.config/hypr/conf"
AUTOSTART="$HYPR_CONF/autostart.lua"
BINDS="$HYPR_CONF/binds.lua"

say "Zestify installer"
say "  repository: $ROOT"
say "  home:       $HOME"

if (( PURGE )); then
    run rm -rf -- "$CONFIG_DIR" "$STATE_DIR" "$CACHE_DIR"
fi

run mkdir -p "$HOME/.config/quickshell" "$HOME/.local/bin" "$CONFIG_DIR" "$STATE_DIR" "$CACHE_DIR" "$HYPR_CONF"

if [[ -e "$QUICKSHELL_LINK" && ! -L "$QUICKSHELL_LINK" ]]; then
    say "refusing to replace non-symlink $QUICKSHELL_LINK" >&2
    exit 1
fi
run ln -sfn "$ROOT/shell" "$QUICKSHELL_LINK"
run ln -sfn "$ROOT/bin/zesti" "$ZESTI_LINK"
run ln -sfn "$ROOT/bin/zestify" "$ZESTIFY_LINK"

if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
    run cp "$ROOT/config/default.json" "$CONFIG_DIR/config.json"
fi
if [[ ! -f "$CONFIG_DIR/cava.conf" ]]; then
    run cp "$ROOT/config/cava.conf" "$CONFIG_DIR/cava.conf"
fi

if [[ -f "$HYPR_CONF/zestify.lua" ]]; then
    backup "$HYPR_CONF/zestify.lua"
fi
run cp "$ROOT/hypr/zestify.lua" "$HYPR_CONF/zestify.lua"

say "updating Zestify keybind and autostart blocks"
if (( ! DRY_RUN )); then
    python3 - "$BINDS" "$AUTOSTART" <<'PY'
import re
import shutil
import sys
import time
from pathlib import Path


def update(path, name, body):
    text = path.read_text() if path.exists() else ""
    begin = f">>> zestify-{name} >>>"
    end = f"<<< zestify-{name} <<<"
    pattern = re.compile(r"^([ \t]*)-- " + re.escape(begin)
                         + r"[^\n]*\n.*?^[ \t]*-- " + re.escape(end)
                         + r"[^\n]*(?:\n|$)", re.M | re.S)

    def block(indent, comments="", at_login=False):
        commands = body
        if at_login:
            commands = ['hl.on("hyprland.start", function()', *["    " + line for line in body], 'end)']
        return (f"{indent}-- {begin}\n" + comments
                + "".join(indent + line + "\n" for line in commands)
                + f"{indent}-- {end}\n")

    if begin in text:
        if not pattern.search(text):
            raise SystemExit(f"incomplete Zestify block in {path}; refusing to overwrite")
        def replace(match):
            comments = "".join(line + "\n" for line in match.group().splitlines()
                               if line.lstrip().startswith('-- hl.exec_cmd("caelestia shell")'))
            # Preserve the block's callback structure; indentation is not Lua scope.
            at_login = name == "autostart" and bool(re.search(
                r'hl\.on\(\s*[\'"]hyprland\.start[\'"]', match.group()))
            return block(match.group(1), comments, at_login=at_login)
        updated = pattern.sub(replace, text)
    elif name == "autostart":
        old = re.compile(r'^([ \t]*)(hl\.exec_cmd\("caelestia shell"\))[^\n]*(?:\n|$)', re.M)
        if old.search(text):
            updated = old.sub(lambda m: block(m.group(1), f"{m.group(1)}-- {m.group(2)}\n"), text)
        else:
            # No existing callback: register for login, not every config reload.
            updated = text.rstrip("\n") + "\n\n" + block("", at_login=True)
    else:
        updated = text.rstrip("\n") + "\n\n" + block("")
    if updated != text:
        if path.exists():
            shutil.copy2(path, str(path) + f".zestify.bak.{time.time_ns()}")
        path.write_text(updated)


update(Path(sys.argv[1]), "binds", ['require("conf.zestify")'])
update(Path(sys.argv[2]), "autostart", ['hl.exec_cmd(require("conf.zestify").command("shell start"))'])
PY
fi

# Copy-only migration of legacy shell state into Zestify-owned state.
run python3 "$ROOT/scripts/migrate-state.py" || true

if (( START )); then
    run "$ZESTI_LINK" shell start
else
    say "skipping start (--no-start)"
fi

say "installed"
