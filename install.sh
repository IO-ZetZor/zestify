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

# Caelestia is NOT a runtime dependency of Zestify. Only the core shell,
# desktop, and locking tools are required.
missing=()
for dep in qs python3 ffmpeg hyprlock jq brightnessctl wpctl; do
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

run cp "$ROOT/hypr/zestify.lua" "$HYPR_CONF/zestify.lua"

if [[ -f "$BINDS" ]] && grep -Fq -- '>>> zestify-binds >>>' "$BINDS"; then
    say "binds block already present"
else
    if (( ! DRY_RUN )); then
        [[ -f "$BINDS" ]] || : > "$BINDS"
        backup "$BINDS"
    fi
    say "appending zestify-binds block to $BINDS"
    if (( ! DRY_RUN )); then
        cat >> "$BINDS" <<'EOF'

-- >>> zestify-binds >>>
dofile(os.getenv("HOME") .. "/.config/hypr/conf/zestify.lua")
-- <<< zestify-binds <<<
EOF
    fi
fi

if [[ -f "$AUTOSTART" ]] && grep -Fq -- '>>> zestify-autostart >>>' "$AUTOSTART"; then
    say "autostart block already present"
else
    if (( ! DRY_RUN )); then
        [[ -f "$AUTOSTART" ]] || : > "$AUTOSTART"
        backup "$AUTOSTART"
        python3 - "$AUTOSTART" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text() if path.exists() else ""
begin = ">>> zestify-autostart >>>"
end = "<<< zestify-autostart <<<"
if begin in text:
    sys.exit(0)

lines = text.splitlines(keepends=True)
for index, line in enumerate(lines):
    stripped = line.lstrip()
    if stripped.startswith('hl.exec_cmd("caelestia shell")') and not stripped.startswith("--"):
        indent = line[: len(line) - len(stripped)]
        block = (
            f"{indent}-- {begin}\n"
            f"{indent}-- {stripped}\n"
            f'{indent}hl.exec_cmd("zesti shell start")\n'
            f"{indent}-- {end}\n"
        )
        lines[index : index + 1] = [block]
        path.write_text("".join(lines))
        break
else:
    if text and not text.endswith("\n"):
        text += "\n"
    if text:
        text += "\n"
    text += (
        f"-- {begin}\n"
        'hl.exec_cmd("zesti shell start")\n'
        f"-- {end}\n"
    )
    path.write_text(text)
PY
    else
        say "would replace the Caelestia autostart line with zesti shell start"
    fi
fi

# Copy-only migration of Caelestia state into Zestify-owned state.
run python3 "$ROOT/scripts/migrate-state.py" || true

if (( START )); then
    run "$ZESTI_LINK" shell start
else
    say "skipping start (--no-start)"
fi

say "installed"
