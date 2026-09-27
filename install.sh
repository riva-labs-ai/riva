#!/bin/sh
# ---------------------------------------------------------------------------
# Riva installer — macOS, Linux, and WSL2
#
#   curl -fsSL https://rivalabs.ai/install.sh | sh
#
# Installs the `riva` CLI from PyPI into an isolated environment with uv
# (https://docs.astral.sh/uv/). No system Python is needed: if there is no
# Python 3.11+, uv downloads a standalone one into your home directory.
# An existing pipx install of riva is upgraded in place instead.
#
# Environment overrides:
#   UV_NO_MODIFY_PATH=1           don't edit shell rc files (uv and riva PATH setup)
#   RIVA_NO_TELEMETRY=1           skip the anonymous install-count ping
#   INSTALL_FROM_SOURCE=1         editable pip install of the current checkout
#   RIVA_PYTHON=/path/to/python   interpreter for INSTALL_FROM_SOURCE
#
# POSIX sh on purpose: `| sh` is dash on Debian/Ubuntu, not bash.
# ---------------------------------------------------------------------------
set -eu

MIN_MAJOR=3
MIN_MINOR=11
UV_INSTALLER_URL="https://astral.sh/uv/install.sh"
TELEMETRY_URL="https://rivalabs.ai/api/v1/install/track"

if [ -t 1 ]; then
    BOLD=$(printf '\033[1m'); GREEN=$(printf '\033[0;32m'); YELLOW=$(printf '\033[0;33m')
    RED=$(printf '\033[0;31m'); CYAN=$(printf '\033[0;36m'); NC=$(printf '\033[0m')
else
    BOLD=""; GREEN=""; YELLOW=""; RED=""; CYAN=""; NC=""
fi

info() { printf '%s[info]%s  %s\n' "$CYAN$BOLD" "$NC" "$*"; }
ok()   { printf '%s[ok]%s    %s\n' "$GREEN$BOLD" "$NC" "$*"; }
warn() { printf '%s[warn]%s  %s\n' "$YELLOW$BOLD" "$NC" "$*"; }
err()  { printf '%s[error]%s %s\n' "$RED$BOLD" "$NC" "$*" >&2; }
die()  { err "$*"; exit 1; }

banner() {
    printf '\n'
    printf '%s  ____  _\n' "$CYAN$BOLD"
    printf ' |  _ \\(_)_   ____ _\n'
    printf ' | |_) | \\ \\ / / _` |\n'
    printf ' |  _ <| |\\ V / (_| |\n'
    printf ' |_| \\_\\_| \\_/ \\__,_|%s\n' "$NC"
    printf '\n'
    printf '  %sAI Agent Command Center%s — installer\n\n' "$BOLD" "$NC"
}

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------

detect_os() {
    case "$(uname -s)" in
        Darwin) OS="macos" ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then OS="wsl"; else OS="linux"; fi ;;
        *) die "Unsupported OS: $(uname -s). Riva supports macOS, Linux, and WSL2. On Windows, use install.ps1." ;;
    esac
    info "Detected OS: $OS"
}

# ---------------------------------------------------------------------------
# Source install (INSTALL_FROM_SOURCE=1) — needs a system Python 3.11+
# ---------------------------------------------------------------------------

python_ok() {
    "$1" -c "import sys; sys.exit(0 if sys.version_info >= ($MIN_MAJOR, $MIN_MINOR) else 1)" >/dev/null 2>&1
}

find_python() {
    if [ -n "${RIVA_PYTHON:-}" ]; then
        python_ok "$RIVA_PYTHON" || die "RIVA_PYTHON=$RIVA_PYTHON is not Python $MIN_MAJOR.$MIN_MINOR+"
        PYTHON="$RIVA_PYTHON"
    else
        # Prefer explicitly versioned interpreters: on macOS `python3` is often
        # the system 3.9 while a Homebrew 3.12 sits alongside as python3.12.
        PYTHON=""
        for candidate in python3.13 python3.12 python3.11 python3 python; do
            if command -v "$candidate" >/dev/null 2>&1 && python_ok "$candidate"; then
                PYTHON=$(command -v "$candidate")
                break
            fi
        done
    fi
    [ -n "$PYTHON" ] || die "INSTALL_FROM_SOURCE=1 needs Python $MIN_MAJOR.$MIN_MINOR+ (see https://www.python.org/downloads/)."
    ok "$("$PYTHON" --version 2>&1) ($PYTHON)"
}

install_from_source() {
    find_python
    info "Installing from source (editable mode)..."
    "$PYTHON" -m pip install -e ".[test]"
    METHOD="pip"
    RIVA_BIN=$(command -v riva 2>/dev/null || true)
}

# ---------------------------------------------------------------------------
# Existing pipx install — upgrade it rather than creating a second copy
# ---------------------------------------------------------------------------

pipx_has_riva() {
    command -v pipx >/dev/null 2>&1 && pipx list --short 2>/dev/null | grep -q '^riva '
}

upgrade_with_pipx() {
    info "riva is already installed with pipx — upgrading it there..."
    pipx upgrade riva
    METHOD="pipx"
    bin_dir=$(pipx environment --value PIPX_BIN_DIR 2>/dev/null || true)
    [ -n "$bin_dir" ] || bin_dir="$HOME/.local/bin"
    RIVA_BIN="$bin_dir/riva"
}

# ---------------------------------------------------------------------------
# uv
# ---------------------------------------------------------------------------

# The uv installer puts the binary in one of these; its PATH edits only take
# effect in new shells, so look for it directly.
find_uv() {
    UV=""
    if command -v uv >/dev/null 2>&1; then
        UV=$(command -v uv)
        return
    fi
    for dir in "${UV_UNMANAGED_INSTALL:-}" "${UV_INSTALL_DIR:-}" "${UV_INSTALL_DIR:+$UV_INSTALL_DIR/bin}" \
               "${XDG_BIN_HOME:-}" "$HOME/.local/bin" "$HOME/.cargo/bin"; do
        if [ -n "$dir" ] && [ -x "$dir/uv" ]; then
            UV="$dir/uv"
            return
        fi
    done
}

ensure_uv() {
    find_uv
    if [ -n "$UV" ]; then
        ok "$("$UV" --version) ($UV)"
        return
    fi

    info "uv not found — installing it from $UV_INSTALLER_URL ..."
    if command -v curl >/dev/null 2>&1; then
        curl -LsSf "$UV_INSTALLER_URL" | sh
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$UV_INSTALLER_URL" | sh
    else
        die "Neither curl nor wget is available to download uv."
    fi

    find_uv
    [ -n "$UV" ] || die "uv was installed but could not be found. Open a new shell and re-run this installer."
    ok "$("$UV" --version) ($UV)"
}

install_with_uv() {
    ensure_uv
    info "Installing riva from PyPI..."
    # --upgrade makes this idempotent: installs if missing, upgrades if present.
    # uv picks an existing Python 3.11+ or downloads a standalone one.
    "$UV" tool install --upgrade --python ">=$MIN_MAJOR.$MIN_MINOR" riva
    METHOD="uv"
    RIVA_BIN="$("$UV" tool dir --bin)/riva"

    if [ -z "${UV_NO_MODIFY_PATH:-}" ]; then
        "$UV" tool update-shell >/dev/null 2>&1 || warn "Could not update shell PATH; see the note below."
    fi
}

# ---------------------------------------------------------------------------
# Verify + summary
# ---------------------------------------------------------------------------

verify_install() {
    [ -n "${RIVA_BIN:-}" ] && [ -x "$RIVA_BIN" ] || die "Install finished but the riva command could not be found."
    version=$("$RIVA_BIN" --version 2>&1) || die "riva was installed but failed to run: $version"
    ok "$version ($RIVA_BIN)"
}

print_summary() {
    bin_dir=$(dirname "$RIVA_BIN")
    printf '\n%s  Riva installed successfully!%s\n\n' "$GREEN$BOLD" "$NC"

    case ":$PATH:" in
        *":$bin_dir:"*) ;;
        *)
            warn "$bin_dir is not on your PATH in this shell."
            printf '        Open a new terminal, or run:  export PATH="%s:$PATH"\n\n' "$bin_dir"
            ;;
    esac

    # An older `pip install riva` earlier on PATH would shadow the new one.
    other=$(command -v riva 2>/dev/null || true)
    if [ -n "$other" ] && [ "$other" != "$RIVA_BIN" ]; then
        warn "Another riva at $other comes first on your PATH and will be used instead."
        printf '        Remove it (e.g. pip uninstall riva) or put %s earlier on PATH.\n\n' "$bin_dir"
    fi

    printf '  Next step:\n\n'
    printf '    %sriva --help%s          # Explore commands\n' "$BOLD" "$NC"
    printf '    riva scan            # One-shot agent scan\n'
    printf '    riva watch           # Live TUI dashboard\n\n'
    printf '  Alternatively: pip install riva  or  pipx install riva\n\n'
    printf '  Docs: %shttps://github.com/riva-labs-ai/riva%s\n\n' "$CYAN" "$NC"
}

# Anonymous install ping — counts script installs separately from PyPI
# downloads. Sends only OS, install method, and riva version; fire-and-forget,
# at most 3s, errors ignored. Set RIVA_NO_TELEMETRY=1 to skip.
send_install_ping() {
    [ -z "${RIVA_NO_TELEMETRY:-}" ] || return 0
    command -v curl >/dev/null 2>&1 || return 0
    # "riva 0.3.20" -> "0.3.20"; use the binary we just verified, not whatever is on PATH.
    _ver=$("$RIVA_BIN" --version 2>/dev/null | awk '{print $2}')
    printf '  Reporting an anonymous install count (OS, method, version) — set RIVA_NO_TELEMETRY=1 to skip.\n\n'
    # $OS is the detected platform (macos / linux / wsl), matching install.ps1's "windows".
    curl -sf --max-time 3 "$TELEMETRY_URL?os=${OS:-unknown}&method=${METHOD:-unknown}&ver=${_ver:-unknown}" >/dev/null 2>&1 || true
}

# Everything runs from main so a truncated `curl | sh` download executes nothing.
main() {
    banner
    detect_os
    if [ "${INSTALL_FROM_SOURCE:-0}" = "1" ]; then
        install_from_source
    elif pipx_has_riva; then
        upgrade_with_pipx
    else
        install_with_uv
    fi
    verify_install
    print_summary
    send_install_ping
}

main "$@"
