#!/usr/bin/env bash
# Apply a previously built and reviewed install stage. Never stop the running DM.
set -euo pipefail
export PATH=/usr/bin:/bin

if [[ $# != 1 || $EUID != 0 ]]; then
    printf 'usage: sudo bash auth/install-default.sh ABSOLUTE_STAGE_DIRECTORY\n' >&2
    exit 2
fi
stage=$(realpath -- "$1")
[[ -c /dev/tty7 ]] || { printf 'The login VT /dev/tty7 is unavailable.\n' >&2; exit 1; }
for required in usr/bin/zestify-dm usr/bin/zestify-greeter etc/zestify-dm/config.json etc/zestify-dm/theme.json \
    etc/pam.d/zestify-dm etc/pam.d/zestify-greeter usr/lib/systemd/system/zestify-dm.service \
    usr/lib/sysusers.d/zestify-dm.conf usr/lib/tmpfiles.d/zestify-dm.conf; do
    [[ -f "$stage/$required" ]] || { printf 'Missing staged file: %s\n' "$required" >&2; exit 1; }
done
"$stage/usr/bin/zestify-dm" --check-config "$stage/etc/zestify-dm/config.json"
"$stage/usr/bin/zestify-greeter" --check-theme "$stage/etc/zestify-dm/theme.json"

previous_dm=$(readlink -f /etc/systemd/system/display-manager.service || true)
case "$previous_dm" in
    /usr/lib/systemd/system/sddm.service|/usr/lib/systemd/system/zestify-dm.service|"") ;;
    *) printf 'Default display manager changed since preparation: %s\n' "$previous_dm" >&2; exit 1 ;;
esac
sddm_running=0
if systemctl is-active --quiet sddm.service; then sddm_running=1; fi
boot_target=$(systemctl get-default)
backup="/var/lib/zestify-dm/backup-$(date -u +%Y%m%dT%H%M%SZ)-$$"
install -d -m700 -- "$backup"
printf '%s\n' "$previous_dm" > "$backup/previous-display-manager.txt"
printf '%s\n' "$boot_target" > "$backup/previous-boot-target.txt"

files=(usr/bin/zestify-dm usr/bin/zestify-greeter etc/zestify-dm/config.json etc/zestify-dm/theme.json
       etc/pam.d/zestify-dm etc/pam.d/zestify-greeter usr/lib/systemd/system/zestify-dm.service
       usr/lib/sysusers.d/zestify-dm.conf usr/lib/tmpfiles.d/zestify-dm.conf)
for relative in "${files[@]}" etc/systemd/system/display-manager.service; do
    if [[ -e "/$relative" || -L "/$relative" ]]; then
        install -d -m700 -- "$backup/$(dirname -- "$relative")"
        cp -a --no-dereference -- "/$relative" "$backup/$relative"
    fi
done
printf 'Backup: %s\n' "$backup"

# This is an Arch-specific integration. Dependency installation must succeed
# before any display-manager configuration is changed.
pacman -S --needed --noconfirm cage
[[ -x /usr/bin/cage && -x /usr/bin/Hyprland && -x /usr/bin/dbus-run-session ]]

for relative in "${files[@]}"; do
    mode=644
    case "$relative" in usr/bin/*) mode=755 ;; esac
    install -Dm"$mode" -- "$stage/$relative" "/$relative"
done
shopt -s nullglob
for asset in "$stage/usr/share/zestify-dm/assets/"*; do
    [[ -f "$asset" ]]
    install -Dm644 -- "$asset" "/usr/share/zestify-dm/assets/$(basename -- "$asset")"
done
for preset in "$stage/usr/share/zestify-dm/themes/"*.json; do
    install -Dm644 -- "$preset" "/usr/share/zestify-dm/themes/$(basename -- "$preset")"
done
systemd-sysusers /usr/lib/sysusers.d/zestify-dm.conf
systemd-tmpfiles --create /usr/lib/tmpfiles.d/zestify-dm.conf
getent passwd zestify-greeter
runuser -u zestify-greeter -- test -r /etc/zestify-dm/theme.json
for asset in /usr/share/zestify-dm/assets/*; do runuser -u zestify-greeter -- test -r "$asset"; done
/usr/bin/zestify-dm --check-config /etc/zestify-dm/config.json
runuser -u zestify-greeter -- /usr/bin/zestify-greeter --check-theme /etc/zestify-dm/theme.json
systemd-analyze verify /usr/lib/systemd/system/zestify-dm.service
systemctl daemon-reload

changed_default=0
restore_default() {
    local status=$?
    if (( status != 0 && changed_default )); then
        printf 'Default switch failed; restoring the previous display manager.\n' >&2
        if [[ -n "$previous_dm" ]]; then systemctl enable --force "$(basename -- "$previous_dm")"; fi
        systemctl set-default "$boot_target"
        systemctl daemon-reload
    fi
    return "$status"
}
trap restore_default EXIT
changed_default=1
if [[ "$previous_dm" == /usr/lib/systemd/system/sddm.service ]]; then systemctl disable sddm.service; fi
systemctl enable --force zestify-dm.service
if [[ "$boot_target" != graphical.target ]]; then systemctl set-default graphical.target; fi
systemctl daemon-reload
[[ $(readlink -f /etc/systemd/system/display-manager.service) == /usr/lib/systemd/system/zestify-dm.service ]]
systemctl is-enabled --quiet zestify-dm.service
if (( sddm_running )); then systemctl is-active --quiet sddm.service; fi
changed_default=0
printf 'Zestify is the default display manager for the next boot. The current session was not stopped.\n'
printf 'Restore SDDM from a console with: sudo systemctl enable --force sddm.service\n'
