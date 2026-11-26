#Requires -Version 7.0
<#
.SYNOPSIS
    Uninstall myssh CLI for the current user.
.EXAMPLE
    ./uninstall.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\myssh'
$bin = Join-Path $installRoot 'bin'
$scriptRoot = $PSScriptRoot

Write-Host ''
Write-Host 'Uninstalling myssh ...' -ForegroundColor Cyan

# 1) Remove PowerShell module
$userModuleRoot = Join-Path $HOME 'Documents\PowerShell\Modules'
$targetModule = Join-Path $userModuleRoot 'myssh'
if (Test-Path -LiteralPath $targetModule) {
    Remove-Item -LiteralPath $targetModule -Recurse -Force
    Write-Host "  module: removed $targetModule"
}
else {
    Write-Host '  module: not found (skip)'
}

# 2) Remove install tree
if (Test-Path -LiteralPath $installRoot) {
    Remove-Item -LiteralPath $installRoot -Recurse -Force
    Write-Host "  files: removed $installRoot"
}
else {
    Write-Host '  files: install dir not found (skip)'
}

# 3) Clean User PATH (install bin + any ...\myssh\bin + this script's bin if run from a zip)
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath) {
    $removeBins = @(
        $bin,
        (Join-Path $scriptRoot 'bin')
    )
    $parts = @(
        $userPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) |
            Where-Object {
                $p = $_
                -not ($removeBins -contains $p) -and
                $p -notmatch '[\\/]myssh[\\/]bin\\?$' -and
                $p -notmatch '[\\/]Programs[\\/]myssh[\\/]bin\\?$'
            }
    )
    $newPath = $parts -join ';'
    if ($newPath -ne $userPath) {
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Host '  PATH: cleaned myssh entries'
    }
    else {
        Write-Host '  PATH: no myssh entry (skip)'
    }
}

# 4) Remove Profile block
$profilePath = $PROFILE.CurrentUserCurrentHost
if (Test-Path -LiteralPath $profilePath) {
    $raw = Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue
    if ($raw -and $raw -match '(?s)# >>> myssh >>>.*?# <<< myssh <<<\s*') {
        $updated = [regex]::Replace($raw, '(?s)\r?\n?# >>> myssh >>>.*?# <<< myssh <<<\r?\n?', "`r`n")
        Set-Content -LiteralPath $profilePath -Value $updated.TrimEnd() -Encoding UTF8
        Write-Host '  profile: myssh block removed'
    }
    else {
        Write-Host '  profile: no myssh block (skip)'
    }
}

Remove-Module myssh -Force -ErrorAction SilentlyContinue

$cfgHome = if ($env:MYSSH_HOME) { $env:MYSSH_HOME } else { Join-Path $HOME '.myssh' }
if (Test-Path -LiteralPath $cfgHome) {
    Write-Host ''
    Write-Host "Config kept: $cfgHome" -ForegroundColor DarkGray
    Write-Host 'Delete secrets/config:  Remove-Item -Recurse -Force "$HOME\.myssh"' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host '✔ myssh uninstalled' -ForegroundColor Green
Write-Host 'Re-open your terminal so PATH changes apply.' -ForegroundColor DarkGray
Write-Host ''
