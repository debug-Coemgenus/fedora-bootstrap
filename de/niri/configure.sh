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

# --- SDDM (display manager) ---------------------------------------------------

log "enabling sddm"
systemctl enable --force sddm.service
systemctl set-default graphical.target

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
