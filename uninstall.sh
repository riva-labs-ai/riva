#!/bin/sh
# ---------------------------------------------------------------------------
# Riva uninstaller — macOS, Linux, and WSL2
#
#   curl -fsSL https://rivalabs.ai/uninstall.sh | sh
#
# Undoes install.sh:
#   1. stops the web dashboard / heartbeat daemon
#   2. unlinks the machine from every Riva Server (revokes its API keys)
#   3. removes Riva hooks from Claude Code's settings
#   4. removes the package — uv, pipx and pip installs are all handled
#   5. optionally deletes local config (~/.riva, ~/.config/riva)
#
# Config is kept unless you answer "y" at the prompt or set RIVA_PURGE=1
# (use that for unattended runs, where there is no prompt).
#
# POSIX sh on purpose: `| sh` is dash on Debian/Ubuntu, not bash.
# ---------------------------------------------------------------------------
set -u

if [ -t 1 ]; then
    BOLD=$(printf '\033[1m'); GREEN=$(printf '\033[0;32m'); YELLOW=$(printf '\033[0;33m')
    CYAN=$(printf '\033[0;36m'); NC=$(printf '\033[0m')
else
    BOLD=""; GREEN=""; YELLOW=""; CYAN=""; NC=""
fi

info() { printf '%s[info]%s  %s\n' "$CYAN$BOLD" "$NC" "$*"; }
ok()   { printf '%s[ok]%s    %s\n' "$GREEN$BOLD" "$NC" "$*"; }
warn() { printf '%s[warn]%s  %s\n' "$YELLOW$BOLD" "$NC" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Locate the riva binary even when its bin dir is not on PATH
# ---------------------------------------------------------------------------

find_riva() {
    RIVA_BIN=""
    if have riva; then
        RIVA_BIN=$(command -v riva)
        return
    fi
    if have uv; then
        _dir=$(uv tool dir --bin 2>/dev/null || true)
        [ -n "$_dir" ] && [ -x "$_dir/riva" ] && RIVA_BIN="$_dir/riva" && return
    fi
    for _dir in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
        [ -x "$_dir/riva" ] && RIVA_BIN="$_dir/riva" && return
    done
}

# ---------------------------------------------------------------------------
# 1–3. Tidy up while the CLI still exists
# ---------------------------------------------------------------------------

stop_and_unlink() {
    if [ -z "$RIVA_BIN" ]; then
        warn "riva command not found — skipping web stop, unlink and hook removal."
        return
    fi
    info "Stopping the web dashboard (if running)..."
    "$RIVA_BIN" web stop >/dev/null 2>&1 || true

    info "Unlinking from Riva Servers (revokes this machine's API keys)..."
    if "$RIVA_BIN" link unlink --all >/dev/null 2>&1; then
        ok "Unlinked"
    else
        warn "Could not unlink (not linked, or the server was unreachable). The server will mark this machine offline."
    fi

    info "Removing Riva hooks from Claude Code settings..."
    "$RIVA_BIN" hooks uninstall --all >/dev/null 2>&1 || true
    ok "Hooks removed"
}

# ---------------------------------------------------------------------------
# 4. Remove the package from wherever it was installed
# ---------------------------------------------------------------------------

remove_package() {
    removed=0
    if have uv && uv tool list 2>/dev/null | grep -q '^riva '; then
        info "Removing uv tool install..."
        uv tool uninstall riva && removed=1
    fi
    if have pipx && pipx list --short 2>/dev/null | grep -q '^riva '; then
        info "Removing pipx install..."
        pipx uninstall riva && removed=1
    fi
    for py in python3 python; do
        if have "$py" && "$py" -m pip show riva >/dev/null 2>&1; then
            info "Removing pip install ($py)..."
            "$py" -m pip uninstall -y riva >/dev/null 2>&1 && removed=1
            break
        fi
    done
    if [ "$removed" = 1 ]; then
        ok "Package removed"
    else
        warn "No riva package found via uv, pipx or pip (already removed?)."
    fi
}

# ---------------------------------------------------------------------------
# 5. Local config — keep by default
# ---------------------------------------------------------------------------

purge_config() {
    purge="${RIVA_PURGE:-0}"
    if [ "$purge" != 1 ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
        printf 'Also delete local config and link credentials (~/.riva, ~/.config/riva)? [y/N] ' > /dev/tty
        read -r answer < /dev/tty || answer=""
        case "$answer" in y|Y|yes|YES) purge=1 ;; esac
    fi
    if [ "$purge" = 1 ]; then
        rm -rf "$HOME/.riva" "$HOME/.config/riva"
        ok "Config removed"
    else
        info "Config kept (~/.riva, ~/.config/riva). Set RIVA_PURGE=1 to delete it."
    fi
}

main() {
    printf '\n%sRiva uninstaller%s\n\n' "$BOLD" "$NC"
    find_riva
    stop_and_unlink
    remove_package
    purge_config
    printf '\n%s  Riva has been uninstalled.%s  Reinstall any time: curl -fsSL https://rivalabs.ai/install.sh | sh\n\n' "$GREEN$BOLD" "$NC"
}

main "$@"
