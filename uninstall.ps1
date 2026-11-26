#Requires -Version 7.0
<#
.SYNOPSIS
    Uninstall myssh for the current user (module, PATH entry, Profile block).
.EXAMPLE
    ./uninstall.ps1
#>
[CmdletBinding()]
param(
    [switch]$KeepConfig
)

$ErrorActionPreference = 'Stop'
$bin = Join-Path $PSScriptRoot 'bin'

Write-Host ''
Write-Host 'Uninstalling myssh ...' -ForegroundColor Cyan

# 1) Remove module from user Modules
$userModuleRoot = Join-Path $HOME 'Documents\PowerShell\Modules'
$targetModule = Join-Path $userModuleRoot 'myssh'
if (Test-Path -LiteralPath $targetModule) {
    Remove-Item -LiteralPath $targetModule -Recurse -Force
    Write-Host "  module: removed $targetModule"
}
else {
    Write-Host '  module: not found (skip)'
}

# 2) Remove bin from user PATH
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath) {
    $parts = @(
        $userPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) |
            Where-Object { $_ -ne $bin -and $_ -ne ($bin.TrimEnd('\') + '\') }
    )
    $newPath = $parts -join ';'
    if ($newPath -ne $userPath) {
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Host "  PATH: removed $bin"
    }
    else {
        Write-Host '  PATH: no myssh bin entry (skip)'
    }
}

# 3) Remove Profile autoload block
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

# 4) Optional: remove ~/.myssh
if (-not $KeepConfig) {
    $cfgHome = if ($env:MYSSH_HOME) { $env:MYSSH_HOME } else { Join-Path $HOME '.myssh' }
    if (Test-Path -LiteralPath $cfgHome) {
        Write-Host ''
        Write-Host "配置目录仍在: $cfgHome" -ForegroundColor DarkGray
        Write-Host '如需一并删除（含加密密码）: Remove-Item -Recurse -Force "$HOME\.myssh"' -ForegroundColor DarkGray
    }
}

Remove-Module myssh -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '✔ myssh uninstalled' -ForegroundColor Green
Write-Host '请重新打开终端使 PATH / Profile 生效。' -ForegroundColor DarkGray
Write-Host ''
