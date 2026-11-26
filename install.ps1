#Requires -Version 7.0
<#
.SYNOPSIS
    Install myssh as a CLI command for the current user.
.DESCRIPTION
    Copies the package to %LOCALAPPDATA%\Programs\myssh, adds bin to User PATH,
    registers the PowerShell module, and optionally updates the Profile for tab completion.
.EXAMPLE
    ./install.ps1
.EXAMPLE
    ./install.ps1 -OfflineCopy
#>
[CmdletBinding()]
param(
    # Kept for compatibility; install always materializes a stable local copy.
    [switch]$OfflineCopy
)

$ErrorActionPreference = 'Stop'
$sourceRoot = $PSScriptRoot
$binSource = Join-Path $sourceRoot 'bin'

if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'myssh.psd1'))) {
    throw "myssh.psd1 not found next to install.ps1"
}

$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\myssh'
$bin = Join-Path $installRoot 'bin'

Write-Host ''
Write-Host 'Installing myssh ...' -ForegroundColor Cyan

# 1) Materialize a stable install tree (so unzip folder can be deleted)
if (Test-Path -LiteralPath $installRoot) {
    Remove-Item -LiteralPath $installRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $installRoot -Force | Out-Null

$copyNames = @(
    'bin', 'Private', 'Public', 'tests',
    'myssh.psd1', 'myssh.psm1',
    'install.ps1', 'uninstall.ps1',
    'LICENSE', 'README.md', 'CHANGELOG.md'
)
foreach ($name in $copyNames) {
    $src = Join-Path $sourceRoot $name
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dst = Join-Path $installRoot $name
    if ((Get-Item -LiteralPath $src).PSIsContainer) {
        Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}
Write-Host "  files: $installRoot"

# 2) Register PowerShell module (copy, not junction — stable after source deletion)
$userModuleRoot = Join-Path $HOME 'Documents\PowerShell\Modules'
$targetModule = Join-Path $userModuleRoot 'myssh'
New-Item -ItemType Directory -Force -Path $userModuleRoot | Out-Null
if (Test-Path -LiteralPath $targetModule) {
    Remove-Item -LiteralPath $targetModule -Recurse -Force
}
Copy-Item -Path $installRoot -Destination $targetModule -Recurse -Force
# Module folder should be the module root (psd1 at top). Copy-Item of installRoot creates myssh\... with nested content — good.
Write-Host "  module: $targetModule"

# 3) User PATH → install bin
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathParts = @()
if ($userPath) {
    $pathParts = $userPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
}
# Remove stale myssh bin entries (old project path or previous install)
$pathParts = @($pathParts | Where-Object {
        $_ -ne $bin -and
        $_ -ne $binSource -and
        $_ -notmatch '[\\/]myssh[\\/]bin\\?$'
    })
$pathParts = @($bin) + $pathParts
$newPath = $pathParts -join ';'
[Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
$env:Path = "$bin;$env:Path"
Write-Host "  PATH: $bin"

# 4) Profile autoload for tab completion
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
    Write-Host '  profile: Import-Module added'
}
else {
    Write-Host '  profile: already configured'
}

Import-Module (Join-Path $installRoot 'myssh.psd1') -Force

Write-Host ''
Write-Host '✔ myssh installed as a CLI command' -ForegroundColor Green
Write-Host ''
Write-Host 'Next:'
Write-Host '  1. Re-open your terminal'
Write-Host '  2. Run:  myssh version'
Write-Host '  3. Try:  myssh help'
Write-Host ''
Write-Host 'Uninstall:'
Write-Host ("  pwsh -File ""{0}""" -f (Join-Path $installRoot 'uninstall.ps1'))
Write-Host ''
