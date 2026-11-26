#Requires -Version 7.0
<#
.SYNOPSIS
    Install myssh for the current user.
.EXAMPLE
    ./install.ps1
#>
[CmdletBinding()]
param(
    [switch]$OfflineCopy
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$bin = Join-Path $root 'bin'
$moduleSource = $root

Write-Host ''
Write-Host 'Installing myssh ...' -ForegroundColor Cyan

# 1) Make module discoverable
$userModuleRoot = Join-Path $HOME 'Documents\PowerShell\Modules'
$targetModule = Join-Path $userModuleRoot 'myssh'
New-Item -ItemType Directory -Force -Path $userModuleRoot | Out-Null

if (Test-Path -LiteralPath $targetModule) {
    Remove-Item -LiteralPath $targetModule -Recurse -Force
}

if ($OfflineCopy) {
    Copy-Item -Path $moduleSource -Destination $targetModule -Recurse -Force
    Write-Host "  module: copied → $targetModule"
}
else {
    try {
        New-Item -ItemType Junction -Path $targetModule -Target $moduleSource -ErrorAction Stop | Out-Null
        Write-Host "  module: linked → $targetModule"
    }
    catch {
        Copy-Item -Path $moduleSource -Destination $targetModule -Recurse -Force
        Write-Host "  module: copied → $targetModule (junction unavailable)"
    }
}

# 2) User PATH: add bin/
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathParts = @()
if ($userPath) {
    $pathParts = $userPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
}
if ($pathParts -notcontains $bin) {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $bin } else { "$userPath;$bin" }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    $env:Path = "$bin;$env:Path"
    Write-Host "  PATH: added $bin"
}
else {
    Write-Host "  PATH: already contains bin"
    if ($env:Path -notlike "*$bin*") {
        $env:Path = "$bin;$env:Path"
    }
}

# 3) Profile autoload for tab completion in interactive shells
$profilePath = $PROFILE.CurrentUserCurrentHost
$profileDir = Split-Path $profilePath -Parent
if (-not (Test-Path -LiteralPath $profileDir)) {
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
}
if (-not (Test-Path -LiteralPath $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

$marker = '# >>> myssh >>>'
$block = @"
$marker
Import-Module myssh -ErrorAction SilentlyContinue
# <<< myssh <<<
"@

$existing = Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue
if ($existing -notmatch [regex]::Escape($marker)) {
    Add-Content -LiteralPath $profilePath -Value "`r`n$block`r`n" -Encoding UTF8
    Write-Host "  profile: Import-Module added"
}
else {
    Write-Host "  profile: already configured"
}

Import-Module (Join-Path $moduleSource 'myssh.psd1') -Force

Write-Host ''
Write-Host '✔ myssh installed' -ForegroundColor Green
Write-Host ''
Write-Host 'Quick start:'
Write-Host '  myssh add              # interactive'
Write-Host '  myssh list'
Write-Host '  myssh <alias>          # connect / jump login'
Write-Host '  myssh help'
Write-Host ''
Write-Host '若新开的终端仍找不到 myssh，请重新打开 Windows Terminal。' -ForegroundColor DarkGray
Write-Host ''
