#Requires -Version 7.0
<#
.SYNOPSIS
  Build GitHub Release artifacts: zip (+ MSI when WiX is available).
.EXAMPLE
  ./scripts/Build-Release.ps1
#>
[CmdletBinding()]
param(
    [string]$Version,
    [switch]$SkipMsi
)

$ErrorActionPreference = 'Stop'

function New-MySshWixSource {
    param(
        [Parameter(Mandatory)][string]$StageDir,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$OutFile
    )

    $upgradeCode = 'B7E3C4A1-8F2D-4C9E-9A1B-5D6E7F8A9B0C'
    $files = Get-ChildItem -LiteralPath $StageDir -Recurse -File
    $components = New-Object System.Collections.Generic.List[string]
    $compRefs = New-Object System.Collections.Generic.List[string]

    $uniqueDirs = @(
        $files |
            ForEach-Object { $_.DirectoryName.Substring($StageDir.Length).TrimStart('\') } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )

    $i = 0
    foreach ($f in $files) {
        $i++
        $relDir = $f.DirectoryName.Substring($StageDir.Length).TrimStart('\')
        $dirId = if ([string]::IsNullOrEmpty($relDir)) {
            'INSTALLFOLDER'
        }
        else {
            'dir_' + ($relDir -replace '[^A-Za-z0-9]', '_')
        }
        $compId = "cmp$i"
        $fileId = "fil$i"
        $srcXml = ($f.FullName -replace '&', '&amp;' -replace '"', '&quot;')
        $nameXml = ($f.Name -replace '&', '&amp;' -replace '"', '&quot;')

        $components.Add(@"
      <Component Id="$compId" Directory="$dirId" Guid="*">
        <File Id="$fileId" Source="$srcXml" Name="$nameXml" KeyPath="yes" />
      </Component>
"@)
        $compRefs.Add("      <ComponentRef Id=`"$compId`" />")
    }

    $components.Add(@"
      <Component Id="cmpPath" Directory="INSTALLFOLDER" Guid="*">
        <Environment Id="MysshPath" Name="PATH" Value="[INSTALLFOLDER]bin" Permanent="no" Part="last" Action="set" System="no" />
        <RegistryValue Root="HKCU" Key="Software\myssh" Name="InstallDir" Type="string" Value="[INSTALLFOLDER]" KeyPath="yes" />
      </Component>
"@)
    $compRefs.Add('      <ComponentRef Id="cmpPath" />')

    $tree = @{}
    foreach ($d in $uniqueDirs) {
        $parts = $d.Split('\')
        $node = $tree
        foreach ($p in $parts) {
            if (-not $node.ContainsKey($p)) { $node[$p] = @{} }
            $node = $node[$p]
        }
    }

    function Render-DirTree($node, $parentPath) {
        $xml = ''
        foreach ($name in ($node.Keys | Sort-Object)) {
            $path = if ($parentPath) { "$parentPath\$name" } else { $name }
            $id = 'dir_' + ($path -replace '[^A-Za-z0-9]', '_')
            $nameXml = $name -replace '&', '&amp;'
            $children = Render-DirTree $node[$name] $path
            if ($children) {
                $xml += "            <Directory Id=`"$id`" Name=`"$nameXml`">`n$children`n            </Directory>`n"
            }
            else {
                $xml += "            <Directory Id=`"$id`" Name=`"$nameXml`" />`n"
            }
        }
        return $xml
    }

    $nestedDirs = Render-DirTree $tree ''

    $wxs = @"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package
      Name="myssh"
      Manufacturer="ssugarr"
      Version="$Version"
      UpgradeCode="$upgradeCode"
      Scope="perUser"
      Language="1033">
    <SummaryInformation Description="myssh — Windows SSH CLI (jump-host manager)" />
    <MajorUpgrade DowngradeErrorMessage="A newer version of myssh is already installed." />
    <MediaTemplate EmbedCab="yes" CompressionLevel="high" />

    <StandardDirectory Id="LocalAppDataFolder">
      <Directory Id="ProgramsDir" Name="Programs">
        <Directory Id="INSTALLFOLDER" Name="myssh">
$nestedDirs
        </Directory>
      </Directory>
    </StandardDirectory>

    <ComponentGroup Id="ProductComponents">
$($components -join "`n")
    </ComponentGroup>

    <Feature Id="MainFeature" Title="myssh" Level="1">
$($compRefs -join "`n")
    </Feature>
  </Package>
</Wix>
"@

    [System.IO.File]::WriteAllText($OutFile, $wxs, [System.Text.UTF8Encoding]::new($false))
}

$repo = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $repo 'myssh.psd1'))) {
    throw "Cannot locate repo root from $PSScriptRoot"
}

if (-not $Version) {
    $psd1 = Import-PowerShellDataFile (Join-Path $repo 'myssh.psd1')
    $Version = [string]$psd1.ModuleVersion
}

$dist = Join-Path $repo 'dist'
$stage = Join-Path $dist "myssh-$Version"
$zipPath = Join-Path $dist "myssh-$Version-win-x64.zip"
$msiPath = Join-Path $dist "myssh-$Version-win-x64.msi"

Write-Host "Building myssh $Version release..." -ForegroundColor Cyan

if (Test-Path $dist) {
    Remove-Item -LiteralPath $dist -Recurse -Force
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$include = @(
    'bin', 'Private', 'Public', 'tests',
    'myssh.psd1', 'myssh.psm1',
    'install.ps1', 'uninstall.ps1',
    'LICENSE', 'README.md', 'CHANGELOG.md'
)

foreach ($item in $include) {
    $src = Join-Path $repo $item
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Warning "Missing: $item"
        continue
    }
    $dest = Join-Path $stage $item
    if ((Get-Item -LiteralPath $src).PSIsContainer) {
        Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $src -Destination $dest -Force
    }
}

$setupCmd = @"
@echo off
setlocal
cd /d "%~dp0"
where pwsh >nul 2>nul
if errorlevel 1 (
  echo [myssh] PowerShell 7+ (pwsh) is required.
  echo Install: https://aka.ms/powershell
  pause
  exit /b 1
)
echo Installing myssh $Version as a CLI command...
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
"@
Set-Content -LiteralPath (Join-Path $stage 'Setup.cmd') -Value $setupCmd -Encoding ASCII

$installTxt = @"
myssh $Version — Windows SSH CLI

Install
  1. Unzip
  2. Double-click Setup.cmd
  3. Re-open terminal → myssh version

Or MSI
  Install the .msi, re-open terminal → myssh version
  (Adds myssh to User PATH; no GUI app)

Uninstall
  Zip:   pwsh -File uninstall.ps1
  MSI:   Settings → Apps → myssh
"@
Set-Content -LiteralPath (Join-Path $stage 'INSTALL.txt') -Value $installTxt -Encoding UTF8

Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -Force
Write-Host "  zip: $zipPath" -ForegroundColor Green
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
Set-Content -LiteralPath ($zipPath + '.sha256') -Value "$hash  $(Split-Path $zipPath -Leaf)" -Encoding ASCII

$builtMsi = $false
if (-not $SkipMsi) {
    try {
        $tools = Join-Path $env:USERPROFILE '.dotnet\tools'
        if ($env:Path -notlike "*$tools*") { $env:Path = "$tools;$env:Path" }

        if (-not (Get-Command wix -ErrorAction SilentlyContinue)) {
            Write-Host '  Installing WiX CLI (dotnet tool)...' -ForegroundColor DarkGray
            if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
                throw 'dotnet SDK not found'
            }
            dotnet tool install --global wix --version 5.0.2 | Out-Host
            $env:Path = "$tools;$env:Path"
        }

        # WiX UI not required; ensure extension for UI-less is fine
        $wxs = Join-Path $dist 'myssh.generated.wxs'
        New-MySshWixSource -StageDir $stage -Version $Version -OutFile $wxs
        & wix build $wxs -o $msiPath -arch x64
        if (-not (Test-Path -LiteralPath $msiPath)) { throw 'MSI was not produced' }
        $msiHash = (Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash
        Set-Content -LiteralPath ($msiPath + '.sha256') -Value "$msiHash  $(Split-Path $msiPath -Leaf)" -Encoding ASCII
        Write-Host "  msi: $msiPath" -ForegroundColor Green
        $builtMsi = $true
    }
    catch {
        Write-Warning "MSI build skipped: $($_.Exception.Message)"
    }
}

Write-Host ''
Write-Host 'Artifacts:' -ForegroundColor Cyan
Get-ChildItem -LiteralPath $dist -File | ForEach-Object {
    Write-Host ("  {0}  ({1} KB)" -f $_.Name, [math]::Round($_.Length / 1KB, 1))
}

[pscustomobject]@{
    Version = $Version
    Zip     = $zipPath
    Msi     = $(if ($builtMsi) { $msiPath } else { $null })
    Dist    = $dist
}
