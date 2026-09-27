# ---------------------------------------------------------------------------
# Riva uninstaller — Windows (PowerShell 5.1+)
#
#   irm https://rivalabs.ai/uninstall.ps1 | iex
#
# Undoes install.ps1: stops the web dashboard, unlinks the machine from every
# Riva Server (revoking its API keys), removes Claude Code hooks, and removes
# the package whether it came from uv, pipx or pip.
#
# Local config (~\.riva, ~\.config\riva) is kept unless you answer "y" at the
# prompt or set $env:RIVA_PURGE = '1' for unattended runs.
# ---------------------------------------------------------------------------

& {
    $ErrorActionPreference = 'Continue'

    function Info($m) { Write-Host "[info]  $m" -ForegroundColor Cyan }
    function Ok($m)   { Write-Host "[ok]    $m" -ForegroundColor Green }
    function Warn($m) { Write-Host "[warn]  $m" -ForegroundColor Yellow }
    function Have($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

    Write-Host ''
    Write-Host 'Riva uninstaller'
    Write-Host ''

    # --- Locate riva even if its bin dir is not on PATH -----------------------
    $Riva = $null
    $cmd = Get-Command riva -ErrorAction SilentlyContinue
    if ($cmd) { $Riva = $cmd.Source }
    elseif (Have 'uv') {
        $bin = & uv tool dir --bin 2>$null
        if ($bin -and (Test-Path (Join-Path $bin 'riva.exe'))) { $Riva = Join-Path $bin 'riva.exe' }
    }
    if (-not $Riva) {
        foreach ($d in @((Join-Path $HOME '.local\bin'), (Join-Path $HOME '.cargo\bin'))) {
            if (Test-Path (Join-Path $d 'riva.exe')) { $Riva = Join-Path $d 'riva.exe'; break }
        }
    }

    # --- 1-3. Tidy up while the CLI still exists ------------------------------
    if ($Riva) {
        Info 'Stopping the web dashboard (if running)...'
        & $Riva web stop *> $null
        Info 'Unlinking from Riva Servers (revokes this machine''s API keys)...'
        & $Riva link unlink --all *> $null
        if ($LASTEXITCODE -eq 0) { Ok 'Unlinked' } else { Warn 'Could not unlink (not linked, or the server was unreachable).' }
        Info 'Removing Riva hooks from Claude Code settings...'
        & $Riva hooks uninstall --all *> $null
        Ok 'Hooks removed'
    } else {
        Warn 'riva command not found - skipping web stop, unlink and hook removal.'
    }

    # --- 4. Remove the package -------------------------------------------------
    $removed = $false
    if ((Have 'uv') -and ((& uv tool list 2>$null) -match '^riva ')) {
        Info 'Removing uv tool install...'
        & uv tool uninstall riva
        if ($LASTEXITCODE -eq 0) { $removed = $true }
    }
    if ((Have 'pipx') -and ((& pipx list --short 2>$null) -match '^riva ')) {
        Info 'Removing pipx install...'
        & pipx uninstall riva
        if ($LASTEXITCODE -eq 0) { $removed = $true }
    }
    foreach ($py in @('py', 'python', 'python3')) {
        if (-not (Have $py)) { continue }
        $flags = @(); if ($py -eq 'py') { $flags = @('-3') }
        & $py @flags -m pip show riva *> $null
        if ($LASTEXITCODE -eq 0) {
            Info "Removing pip install ($py)..."
            & $py @flags -m pip uninstall -y riva *> $null
            if ($LASTEXITCODE -eq 0) { $removed = $true }
            break
        }
    }
    if ($removed) { Ok 'Package removed' } else { Warn 'No riva package found via uv, pipx or pip (already removed?).' }

    # --- 5. Local config -------------------------------------------------------
    $purge = ($env:RIVA_PURGE -eq '1')
    if (-not $purge -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        $answer = Read-Host 'Also delete local config and link credentials (~\.riva, ~\.config\riva)? [y/N]'
        if ($answer -match '^(y|yes)$') { $purge = $true }
    }
    if ($purge) {
        foreach ($d in @((Join-Path $HOME '.riva'), (Join-Path $HOME '.config\riva'))) {
            if (Test-Path $d) { Remove-Item -Recurse -Force $d }
        }
        Ok 'Config removed'
    } else {
        Info 'Config kept (~\.riva, ~\.config\riva). Set $env:RIVA_PURGE = ''1'' to delete it.'
    }

    Write-Host ''
    Write-Host '  Riva has been uninstalled.  Reinstall any time: irm https://rivalabs.ai/install.ps1 | iex' -ForegroundColor Green
    Write-Host ''
}
