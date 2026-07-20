#!/usr/bin/env bash
#
# configure.sh - post-install system configuration.
#
# Called by bootstrap.sh (as root) after repositories and packages
# are set up. Add your configuration steps below.

set -euo pipefail

log()  { printf '[configure] %s\n' "$*"; }
fail() { printf '[configure] ERROR: %s\n' "$*" >&2; exit 1; }

# --- Assertions -------------------------------------------------------------

[[ $EUID -eq 0 ]] || fail "must be run as root (normally called by bootstrap.sh)"

# --- SDDM (display manager) ---------------------------------------------------
# The sddm package itself is installed via packages.list.

log "enabling sddm"
# --force replaces any previously enabled display manager (e.g. gdm)
systemctl enable --force sddm.service
systemctl set-default graphical.target

# --- niri portals configuration ----------------------------------------------------
# niri uses xdg-desktop-portal-gtk (fallback), xdg-desktop-portal-gnome
# (screencast) and gnome-keyring (secrets). niri-portals.conf tells
# xdg-desktop-portal to use those backends for the niri session.
# Download to a temp file first so a failed download can't clobber an
# existing config.

command -v wget >/dev/null 2>&1 || fail "wget not found in PATH"

log "installing niri-portals.conf"
PORTALS_CONF_TMP="$(mktemp)"
wget -q -O "$PORTALS_CONF_TMP" \
    "https://raw.githubusercontent.com/niri-wm/niri/main/resources/niri-portals.conf" \
    || { rm -f "$PORTALS_CONF_TMP"; fail "failed to download niri-portals.conf"; }
# Pin file choosers to the gtk backend - the gnome one needs nautilus
grep -qF 'org.freedesktop.impl.portal.FileChooser' "$PORTALS_CONF_TMP" \
    || printf '%s\n' 'org.freedesktop.impl.portal.FileChooser=gtk;' >> "$PORTALS_CONF_TMP"
install -D -m 0644 "$PORTALS_CONF_TMP" /usr/share/xdg-desktop-portal/niri-portals.conf
rm -f "$PORTALS_CONF_TMP"

# --- DevPod: use podman as backend -----------------------------------------------
# Podman is a drop-in CLI replacement for docker, so the official docker
# provider is used with DOCKER_PATH=podman (rootless, no socket needed).
# DevPod's config is per-user, so the CLI must run as the invoking user.

command -v podman >/dev/null 2>&1 || fail "podman not installed (add it to packages.list)"
command -v devpod >/dev/null 2>&1 || fail "devpod not installed (run bootstrap.sh first)"

[[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]] \
    || fail "SUDO_USER not set - run as 'sudo ./bootstrap.sh' from your user account"
USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)" || fail "user not found: $SUDO_USER"
[[ -d "$USER_HOME" ]] || fail "home directory not found: ${USER_HOME:-<empty>}"

# as_user CMD... - run a command as the invoking user, with their home set.
# runuser preserves the caller's environment, and sudo may leave HOME
# pointing at /root - devpod would write its config to the wrong place.
as_user() {
    runuser -u "$SUDO_USER" -- env HOME="$USER_HOME" "$@"
}

log "configuring devpod to use podman"
# On re-runs 'add' fails because the provider exists - fall back to set-options
as_user devpod provider add docker -o DOCKER_PATH=podman \
    || as_user devpod provider set-options docker --option DOCKER_PATH=podman
as_user devpod provider use docker

log "configuration complete"
