# ---------------------------------------------------------------------------
# Riva installer — Windows (PowerShell 5.1+)
#
#   irm https://rivalabs.ai/install.ps1 | iex
#
# Installs the `riva` CLI from PyPI into an isolated environment with uv
# (https://docs.astral.sh/uv/). No system Python is needed: if there is no
# Python 3.11+, uv downloads a standalone one into your profile.
# An existing pipx install of riva is upgraded in place instead.
#
# Set $env:UV_NO_MODIFY_PATH = '1' to skip PATH changes.
# Set $env:RIVA_NO_TELEMETRY = '1' to skip the anonymous install-count ping.
#
# Note: the live TUI (`riva watch`) needs a POSIX terminal. For the full
# feature set on Windows, run install.sh inside WSL2 instead.
# ---------------------------------------------------------------------------

# Wrapped in a scriptblock so `iex` of a truncated download runs nothing, and
# so errors `return` instead of `exit` (which would close the user's shell).
& {
    # Not 'Stop': on Windows PowerShell 5.1 a native command writing to a
    # redirected stderr would throw. Exit codes are checked explicitly instead.
    $ErrorActionPreference = 'Continue'
    $UvInstallerUrl = 'https://astral.sh/uv/install.ps1'
    $TelemetryUrl = 'https://rivalabs.ai/api/v1/install/track'

    function Info($msg) { Write-Host "[info]  $msg" -ForegroundColor Cyan }
    function Ok($msg)   { Write-Host "[ok]    $msg" -ForegroundColor Green }
    function Warn($msg) { Write-Host "[warn]  $msg" -ForegroundColor Yellow }
    function Err($msg)  { Write-Host "[error] $msg" -ForegroundColor Red }

    Write-Host ''
    Write-Host '  ____  _'                -ForegroundColor Cyan
    Write-Host ' |  _ \(_)_   ____ _'     -ForegroundColor Cyan
    Write-Host ' | |_) | \ \ / / _` |'    -ForegroundColor Cyan
    Write-Host ' |  _ <| |\ V / (_| |'    -ForegroundColor Cyan
    Write-Host ' |_| \_\_| \_/ \__,_|'    -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  AI Agent Command Center - installer'
    Write-Host ''

    $Riva = $null
    $Method = $null

    # -----------------------------------------------------------------------
    # Existing pipx install — upgrade it rather than creating a second copy
    # -----------------------------------------------------------------------

    $pipxHasRiva = $false
    if (Get-Command pipx -ErrorAction SilentlyContinue) {
        $pipxHasRiva = [bool]((pipx list --short 2>$null) -match '^riva ')
    }

    if ($pipxHasRiva) {
        Info 'riva is already installed with pipx - upgrading it there...'
        pipx upgrade riva
        if ($LASTEXITCODE -ne 0) { Err 'pipx failed to upgrade riva (see output above).'; return }
        $Method = 'pipx'
        $BinDir = pipx environment --value PIPX_BIN_DIR 2>$null
        if (-not $BinDir) { $BinDir = Join-Path $HOME '.local\bin' }
        $Riva = Join-Path $BinDir 'riva.exe'
    } else {

        # -------------------------------------------------------------------
        # uv
        # -------------------------------------------------------------------

        # The uv installer's PATH change only reaches new sessions, so look
        # in its install locations directly.
        function Find-Uv {
            $cmd = Get-Command uv -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Source }
            $dirs = @($env:UV_UNMANAGED_INSTALL, $env:UV_INSTALL_DIR, $env:XDG_BIN_HOME,
                      (Join-Path $HOME '.local\bin'), (Join-Path $HOME '.cargo\bin'))
            foreach ($d in $dirs) {
                if ($d -and (Test-Path (Join-Path $d 'uv.exe'))) { return (Join-Path $d 'uv.exe') }
            }
            return $null
        }

        $Uv = Find-Uv
        if (-not $Uv) {
            Info "uv not found - installing it from $UvInstallerUrl ..."
            # Run in a child process, as Astral documents, so the installer
            # can't alter this session or exit it.
            powershell -NoProfile -ExecutionPolicy ByPass -Command "irm $UvInstallerUrl | iex"
            $Uv = Find-Uv
            if (-not $Uv) {
                Err 'uv was installed but could not be found. Open a new terminal and re-run this installer.'
                return
            }
        }
        Ok "$(& $Uv --version) ($Uv)"

        # -------------------------------------------------------------------
        # riva
        # -------------------------------------------------------------------

        Info 'Installing riva from PyPI...'
        # --upgrade makes this idempotent: installs if missing, upgrades if present.
        # uv picks an existing Python 3.11+ or downloads a standalone one.
        & $Uv tool install --upgrade --python '>=3.11' riva
        if ($LASTEXITCODE -ne 0) { Err 'uv failed to install riva (see output above).'; return }
        $Method = 'uv'

        $BinDir = & $Uv tool dir --bin
        $Riva = Join-Path $BinDir 'riva.exe'

        if (-not $env:UV_NO_MODIFY_PATH) {
            & $Uv tool update-shell *> $null
        }
    }

    # -----------------------------------------------------------------------
    # Verify + summary
    # -----------------------------------------------------------------------

    if (-not (Test-Path $Riva)) { Err "Install finished but $Riva was not found."; return }
    $RivaVersion = & $Riva --version 2>&1
    if ($LASTEXITCODE -ne 0) { Err "riva was installed but failed to run: $RivaVersion"; return }
    Ok "$RivaVersion ($Riva)"

    Write-Host ''
    Write-Host '  Riva installed successfully!' -ForegroundColor Green
    Write-Host ''
    $BinDir = Split-Path $Riva
    if (-not (($env:Path -split ';') -contains $BinDir)) {
        Warn "$BinDir is not on PATH in this session - open a new terminal to use 'riva'."
        Write-Host ''
    }
    $other = Get-Command riva -ErrorAction SilentlyContinue
    if ($other -and $other.Source -ne $Riva) {
        Warn "Another riva at $($other.Source) comes first on PATH and will be used instead."
        Write-Host "        Remove it (e.g. pip uninstall riva) or put $BinDir earlier on PATH."
        Write-Host ''
    }
    Write-Host '  Next step:'
    Write-Host ''
    Write-Host '    riva --help          # Explore commands'
    Write-Host '    riva scan            # One-shot agent scan'
    Write-Host ''
    Write-Host '  Alternatively: pip install riva  or  pipx install riva'
    Write-Host ''
    Write-Host '  Tip: for the live TUI (riva watch) and full feature set, use WSL2.'
    Write-Host '  Docs: https://github.com/sarkar-ai-taken/riva' -ForegroundColor Cyan
    Write-Host ''

    # Anonymous install ping — counts script installs separately from PyPI
    # downloads. Sends only OS, install method, and riva version; fire-and-
    # forget, at most 3s, errors ignored.
    if (-not $env:RIVA_NO_TELEMETRY) {
        Write-Host '  Reporting an anonymous install count (OS, method, version) - set RIVA_NO_TELEMETRY=1 to skip.'
        Write-Host ''
        # "riva 0.3.20" -> "0.3.20"; from the binary we just verified, not PATH.
        $ver = ("$RivaVersion" -replace '^riva\s+', '').Trim()
        if (-not $ver) { $ver = 'unknown' }
        $q = 'os=windows&method={0}&ver={1}' -f [uri]::EscapeDataString($Method), [uri]::EscapeDataString($ver)
        try { Invoke-RestMethod "${TelemetryUrl}?$q" -TimeoutSec 3 -ErrorAction Stop | Out-Null } catch {}
    }
}
