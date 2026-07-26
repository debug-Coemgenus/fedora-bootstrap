#!/usr/bin/env bash
#
# configure.sh - post-install system configuration (common to all DEs).
#
# Called by bootstrap.sh (as root) after repositories and packages
# are set up. DE-specific configuration lives in de/<name>/configure.sh.

set -euo pipefail

log()  { printf '[configure] %s\n' "$*"; }
fail() { printf '[configure] ERROR: %s\n' "$*" >&2; exit 1; }

# --- Assertions -------------------------------------------------------------

[[ $EUID -eq 0 ]] || fail "must be run as root (normally called by bootstrap.sh)"

# --- DevPod: use podman as backend -----------------------------------------------

command -v podman >/dev/null 2>&1 || fail "podman not installed (add it to packages.list)"
command -v devpod >/dev/null 2>&1 || fail "devpod not installed (run bootstrap.sh first)"

[[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]] \
    || fail "SUDO_USER not set - run as 'sudo ./bootstrap.sh' from your user account"
USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)" || fail "user not found: $SUDO_USER"
[[ -d "$USER_HOME" ]] || fail "home directory not found: ${USER_HOME:-<empty>}"

as_user() {
    runuser -u "$SUDO_USER" -- env HOME="$USER_HOME" "$@"
}

log "configuring devpod to use podman"
as_user devpod provider add docker -o DOCKER_PATH=podman \
    || as_user devpod provider set-options docker --option DOCKER_PATH=podman
as_user devpod provider use docker

log "common configuration complete"
