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

log "common configuration complete"
