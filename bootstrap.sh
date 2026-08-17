#!/usr/bin/env bash
# bootstrap.sh - Fedora system bootstrap.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DE_DIR="$SCRIPT_DIR/de"
COPRS_FILE="$SCRIPT_DIR/coprs.list"
PACKAGES_FILE="$SCRIPT_DIR/packages.list"
XDG_FILE="$SCRIPT_DIR/xdg-spec.txt"

log()  { printf '[bootstrap] %s\n' "$*"; }
fail() { printf '[bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

as_user() {
    runuser -u "$SUDO_USER" -- env HOME="$USER_HOME" "$@"
}

read_list() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ -n "$line" ]]; then
            printf '%s\n' "$line"
        fi
    done < "$1"
}

# --- Desktop environment selection --------------------------------------------

SELECTED_DE=""

select_de() {
    local de_dirs=()

    if [[ -d "$DE_DIR" ]]; then
        for d in "$DE_DIR"/*/; do
            [[ -d "$d" ]] && de_dirs+=("$(basename "$d")")
        done
    fi

    printf '\n[bootstrap] Select desktop environment:\n'
    printf '  1) Niri\n'
    printf '  2) None\n'
    printf '\nChoice [1-2]: '

    local choice
    read -r choice

    case "$choice" in
        1)
            if [[ -d "$DE_DIR/niri" ]]; then
                SELECTED_DE="niri"
            else
                fail "niri module not found in $DE_DIR/niri"
            fi
            ;;
        2)
            SELECTED_DE="none"
            ;;
        *)
            fail "invalid selection: '$choice' (expected 1 or 2)"
            ;;
    esac

    log "selected desktop environment: $SELECTED_DE"
}

# --- Assertions -------------------------------------------------------------

[[ $EUID -eq 0 ]]         || fail "must be run as root (try: sudo $0)"

[[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]] \
    || fail "SUDO_USER not set - run as 'sudo ./bootstrap.sh' from your user account"
USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)" || fail "user not found: $SUDO_USER"
[[ -d "$USER_HOME" ]] || fail "home directory not found: ${USER_HOME:-<empty>}"

[[ -r /etc/os-release ]]  || fail "cannot read /etc/os-release"

. /etc/os-release
[[ "${ID:-}" == "fedora" ]] || fail "only Fedora is supported (detected: '${ID:-unknown}')"

command -v dnf >/dev/null 2>&1 || fail "dnf not found in PATH"
[[ -f "$PACKAGES_FILE" ]]      || fail "missing file: $PACKAGES_FILE"
[[ -f "$XDG_FILE" ]]           || fail "missing file: $XDG_FILE"

select_de

log "Fedora ${VERSION_ID:-?} detected - starting bootstrap (DE: $SELECTED_DE)"

# --- Enable COPR repositories ------------------------------------------------

dnf install -y dnf-plugins-core

if [[ -f "$COPRS_FILE" ]]; then
    while IFS= read -r repo; do
        log "enabling COPR: $repo"
        dnf copr enable -y "$repo"
    done < <(read_list "$COPRS_FILE")
fi

if [[ "$SELECTED_DE" != "none" ]]; then
    DE_COPRS="$DE_DIR/$SELECTED_DE/coprs.list"
    if [[ -f "$DE_COPRS" ]]; then
        while IFS= read -r repo; do
            log "enabling COPR ($SELECTED_DE): $repo"
            dnf copr enable -y "$repo"
        done < <(read_list "$DE_COPRS")
    fi
fi

# --- Install packages ---------------------------------------------------------

mapfile -t packages < <(read_list "$PACKAGES_FILE")

if [[ "$SELECTED_DE" != "none" ]]; then
    DE_PACKAGES="$DE_DIR/$SELECTED_DE/packages.list"
    if [[ -f "$DE_PACKAGES" ]]; then
        mapfile -t de_packages < <(read_list "$DE_PACKAGES")
        packages+=("${de_packages[@]}")
    fi
fi

if ((${#packages[@]} > 0)); then
    log "installing ${#packages[@]} package(s)"
    dnf install -y "${packages[@]}"
else
    log "no packages to install"
fi

# --- Create personal directory structure -------------------------------------------

log "creating personal directories in $USER_HOME"
as_user mkdir -p \
    "$USER_HOME/Education" \
    "$USER_HOME/Projects" \
    "$USER_HOME/Programs/exe"

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
    chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$BASH_PROFILE"
fi

# --- Post-install configuration ------------------------------------------------

log "running configure.sh (common)"
bash "$SCRIPT_DIR/configure.sh"

if [[ "$SELECTED_DE" != "none" ]]; then
    DE_CONFIGURE="$DE_DIR/$SELECTED_DE/configure.sh"
    if [[ -f "$DE_CONFIGURE" ]]; then
        log "running $SELECTED_DE configuration"
        bash "$DE_CONFIGURE"
    fi
fi

log "bootstrap complete"

# --- Post-install instructions --------------------------------------------------

if [[ "$SELECTED_DE" == "niri" ]]; then
    printf '\n'
    log "Next steps"
    log "────────────────────────────────────────"
    log "SDDM + GNOME Keyring"
    log "  For SDDM to unlock the keyring on login, edit:"
    log "    /etc/pam.d/sddm"
    log "  Find:"
    log "    -auth     optional  pam_gnome_keyring.so"
    log "  Remove the leading '-' so it becomes:"
    log "    auth      optional  pam_gnome_keyring.so"
    log "  Find:"
    log "    -session  optional  pam_gnome_keyring.so  auto_start"
    log "  Remove the leading '-' so it becomes:"
    log "    session   optional  pam_gnome_keyring.so  auto_start"
    printf '\n'
fi
