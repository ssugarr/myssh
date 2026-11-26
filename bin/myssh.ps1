#!/usr/bin/env pwsh
# CLI entrypoint — works from PATH without Import-Module first
$ErrorActionPreference = 'Stop'
$moduleManifest = Join-Path (Split-Path $PSScriptRoot -Parent) 'myssh.psd1'
Import-Module $moduleManifest -Force
myssh @args
$code = $LASTEXITCODE
if ($null -eq $code) { $code = 0 }
exit $code
