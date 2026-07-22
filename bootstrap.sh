#!/usr/bin/env bash
#
# bootstrap.sh - Fedora system bootstrap.
#
# Steps:
#   1. enable the COPR repositories listed in coprs.list
#   2. install the packages listed in packages.list
#   3. install/update the DevPod CLI
#   4. create the personal directory structure in the invoking user's home
#   5. append xdg-spec.txt to the invoking user's ~/.bash_profile
#   6. run configure.sh
#
# List file format: one entry per line. Blank lines and '#' comments
# (whole-line or inline) are ignored, e.g.:
#
#   vim-enhanced    # the editor

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COPRS_FILE="$SCRIPT_DIR/coprs.list"
PACKAGES_FILE="$SCRIPT_DIR/packages.list"
XDG_FILE="$SCRIPT_DIR/xdg-spec.txt"

log()  { printf '[bootstrap] %s\n' "$*"; }
fail() { printf '[bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

# as_user CMD... - run a command as the invoking user, with their home set.
# runuser preserves the caller's environment, and sudo may leave HOME
# pointing at /root - so set HOME explicitly.
as_user() {
    runuser -u "$SUDO_USER" -- env HOME="$USER_HOME" "$@"
}

# read_list FILE - print the entries of a list file, one per line.
# Blank lines and '#' comments (whole-line and inline) are stripped.
read_list() {
    local line
    # '|| [[ -n "$line" ]]' also handles a last line without trailing newline
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"                       # strip comments
        line="${line#"${line%%[![:space:]]*}"}"  # trim leading whitespace
        line="${line%"${line##*[![:space:]]}"}"  # trim trailing whitespace
        if [[ -n "$line" ]]; then
            printf '%s\n' "$line"
        fi
    done < "$1"
}

# --- Assertions -------------------------------------------------------------

[[ $EUID -eq 0 ]]         || fail "must be run as root (try: sudo $0)"

# Several steps write to the home directory of the user who invoked sudo.
[[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]] \
    || fail "SUDO_USER not set - run as 'sudo ./bootstrap.sh' from your user account"
USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)" || fail "user not found: $SUDO_USER"
[[ -d "$USER_HOME" ]] || fail "home directory not found: ${USER_HOME:-<empty>}"

[[ -r /etc/os-release ]]  || fail "cannot read /etc/os-release"

# shellcheck source=/dev/null
. /etc/os-release
[[ "${ID:-}" == "fedora" ]] || fail "only Fedora is supported (detected: '${ID:-unknown}')"

command -v dnf >/dev/null 2>&1 || fail "dnf not found in PATH"
[[ -f "$COPRS_FILE" ]]         || fail "missing file: $COPRS_FILE"
[[ -f "$PACKAGES_FILE" ]]      || fail "missing file: $PACKAGES_FILE"
[[ -f "$XDG_FILE" ]]           || fail "missing file: $XDG_FILE"

log "Fedora ${VERSION_ID:-?} detected - starting bootstrap"

# --- Enable COPR repositories ------------------------------------------------

# 'dnf copr' is provided by dnf-plugins-core
dnf install -y dnf-plugins-core

while IFS= read -r repo; do
    log "enabling COPR: $repo"
    dnf copr enable -y "$repo"
done < <(read_list "$COPRS_FILE")

# --- Install packages ---------------------------------------------------------

mapfile -t packages < <(read_list "$PACKAGES_FILE")

if ((${#packages[@]} > 0)); then
    log "installing ${#packages[@]} package(s)"
    dnf install -y "${packages[@]}"
else
    log "no packages to install"
fi

# --- Install DevPod CLI ---------------------------------------------------------
# Downloads the latest release; re-running also updates an existing install.

command -v curl >/dev/null 2>&1 || fail "curl not found in PATH"
[[ "$(uname -m)" == "x86_64" ]] \
    || fail "the devpod download URL below is amd64-only (detected arch: $(uname -m))"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log "downloading devpod CLI"
curl -fSL -o "$TMP_DIR/devpod" \
    "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-amd64"
install -c -m 0755 "$TMP_DIR/devpod" /usr/local/bin

# --- Create personal directory structure -------------------------------------------

log "creating personal directories in $USER_HOME"
as_user mkdir -p \
    "$USER_HOME/Education" \
    "$USER_HOME/Projects" \
    "$USER_HOME/Programs/executables"

# Add Programs/executables to PATH (prepended, so it takes priority)
BASHRC="$USER_HOME/.bashrc"
PATH_MARKER="# fedora-bootstrap: executables-path"

if grep -qF "$PATH_MARKER" "$BASHRC" 2>/dev/null; then
    log "executables PATH already in $BASHRC - skipping"
else
    log "adding Programs/executables to PATH in $BASHRC"
    {
        printf '\n%s\n' "$PATH_MARKER"
        printf '%s\n' 'export PATH="$HOME/Programs/executables:$PATH"'
    } >> "$BASHRC"
    # the file may have been created by root - give it to the real user
    chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$BASHRC"
fi

# --- Append xdg-spec.txt to the user's .bash_profile -----------------------------

BASH_PROFILE="$USER_HOME/.bash_profile"
XDG_MARKER="# fedora-bootstrap: xdg-spec"

if grep -qF "$XDG_MARKER" "$BASH_PROFILE" 2>/dev/null; then
    log "xdg-spec already in $BASH_PROFILE - skipping"
else
    log "appending xdg-spec.txt to $BASH_PROFILE"
    {
        printf '\n%s\n' "$XDG_MARKER"
        cat "$XDG_FILE"
    } >> "$BASH_PROFILE"
    # the file may have been created by root - give it to the real user
    chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$BASH_PROFILE"
fi

# --- Post-install configuration ------------------------------------------------

log "running configure.sh"
bash "$SCRIPT_DIR/configure.sh"

log "bootstrap complete"
printf '\n'
log "Next steps"
log "────────────────────────────────────────"
log "SDDM + GNOME Keyring"
log "  For SDDM to unlock the keyring on login, edit:"
log "    /etc/pam.d/sddm"
log "  Find:"
log "    -auth  optional  pam_gnome_keyring.so"
log "  Remove the leading '-' so it becomes:"
log "    auth   optional  pam_gnome_keyring.so"
printf '\n'