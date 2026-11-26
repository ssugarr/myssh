#!/usr/bin/env pwsh
# CLI entrypoint — works from PATH without Import-Module first
$ErrorActionPreference = 'Stop'
$moduleManifest = Join-Path (Split-Path $PSScriptRoot -Parent) 'myssh.psd1'
Import-Module $moduleManifest -Force
myssh @args
exit $LASTEXITCODE
