# myssh — Windows SSH connection & jump-host manager

$ErrorActionPreference = 'Stop'

$private = Join-Path $PSScriptRoot 'Private'
$public = Join-Path $PSScriptRoot 'Public'

foreach ($file in (Get-ChildItem -Path $private -Filter '*.ps1' | Sort-Object Name)) {
    . $file.FullName
}

foreach ($file in (Get-ChildItem -Path $public -Filter '*.ps1' | Sort-Object Name)) {
    . $file.FullName
}

Export-ModuleMember -Function myssh
