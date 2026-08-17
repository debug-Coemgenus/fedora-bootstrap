#!/usr/bin/env bash
#
# de/niri/configure.sh - niri desktop environment configuration.
#
# Called by bootstrap.sh after niri packages are installed.
# Configures SDDM and niri portals.

set -euo pipefail

log()  { printf '[configure:niri] %s\n' "$*"; }
fail() { printf '[configure:niri] ERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "must be run as root"
[[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]] \
    || fail "SUDO_USER not set - cannot configure the user's systemd session"

TARGET_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)" \
    || fail "user not found: $SUDO_USER"
TARGET_UID="$(id -u "$SUDO_USER")" \
    || fail "could not determine UID for: $SUDO_USER"

# --- SDDM (display manager) ---------------------------------------------------

log "enabling sddm"
systemctl enable --force sddm.service
systemctl set-default graphical.target
runuser -u "$SUDO_USER" -- env \
    HOME="$TARGET_HOME" \
    XDG_CONFIG_HOME="$TARGET_HOME/.config" \
    XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
    systemctl --user add-wants niri.service dms

# --- niri portals configuration -----------------------------------------------

command -v wget >/dev/null 2>&1 || fail "wget not found in PATH"

log "installing niri-portals.conf"
PORTALS_CONF_TMP="$(mktemp)"
wget -q -O "$PORTALS_CONF_TMP" \
    "https://raw.githubusercontent.com/niri-wm/niri/main/resources/niri-portals.conf" \
    || { rm -f "$PORTALS_CONF_TMP"; fail "failed to download niri-portals.conf"; }
grep -qF 'org.freedesktop.impl.portal.FileChooser' "$PORTALS_CONF_TMP" \
    || printf '%s\n' 'org.freedesktop.impl.portal.FileChooser=gtk;' >> "$PORTALS_CONF_TMP"
install -D -m 0644 "$PORTALS_CONF_TMP" /usr/share/xdg-desktop-portal/niri-portals.conf
rm -f "$PORTALS_CONF_TMP"

log "niri configuration complete"
