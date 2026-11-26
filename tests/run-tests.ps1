#Requires -Version 7.0
<#
.SYNOPSIS
  Isolated unit/integration tests for myssh (does not touch ~/.myssh).
#>
$ErrorActionPreference = 'Stop'
$failed = 0
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if ($Condition) {
        Write-Host "  PASS  $Name" -ForegroundColor Green
        $script:passed++
    }
    else {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        $script:failed++
    }
}

function Assert-Eq {
    param($Expected, $Actual, [string]$Name)
    if ("$Expected" -eq "$Actual") {
        Assert-True $true $Name
    }
    else {
        Write-Host "  FAIL  $Name (expected='$Expected' actual='$Actual')" -ForegroundColor Red
        $script:failed++
    }
}

$testRoot = Join-Path $env:TEMP ("myssh-test-" + [guid]::NewGuid().ToString('N'))
$env:MYSSH_HOME = $testRoot
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$moduleRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $moduleRoot 'myssh.psd1') -Force
Get-ChildItem (Join-Path $moduleRoot 'Private\*.ps1') | ForEach-Object { . $_.FullName }

Write-Host "`n== Config / home isolation ==" -ForegroundColor Cyan
Assert-Eq $testRoot (Get-MySshHome) 'MYSSH_HOME isolation'
Initialize-MySshHome
Assert-True (Test-Path -LiteralPath $testRoot) 'home dir created'
$null = Read-MySshConfig
Assert-True (Test-Path -LiteralPath (Join-Path $testRoot 'config.json')) 'config.json created'

Write-Host "`n== Alias validation ==" -ForegroundColor Cyan
Assert-True (Test-MySshAliasName 'prod') 'alias prod ok'
Assert-True (Test-MySshAliasName '36') 'alias 36 ok'
Assert-True (-not (Test-MySshAliasName 'add')) 'reserved add rejected'
Assert-True (Test-MySshAliasName 'myjump') 'alias myjump ok'

Write-Host "`n== Host CRUD + jump ==" -ForegroundColor Cyan
myssh add bastion --host 10.0.0.1 --user jump --port 22 --no-key --force | Out-Null
myssh add app --host 10.0.0.8 --user app --port 22 --jump bastion --no-key --desc 'via bastion' --force | Out-Null
myssh add direct --host example.com --user root --port 2222 --no-key --force | Out-Null

$cfg = Read-MySshConfig
Assert-Eq 3 $cfg.hosts.Count '3 hosts saved'
Assert-Eq 'bastion' $cfg.hosts['app'].jump 'app jump'
Assert-True (-not $cfg.Contains('tunnels') -or $null -eq $cfg.tunnels -or $cfg.tunnels.Count -eq 0) 'no tunnels in config'

Save-MySshConfig -Config $cfg
$cfg2 = Read-MySshConfig
Assert-Eq 3 $cfg2.hosts.Count 'config round-trip count'
Assert-Eq 'bastion' $cfg2.hosts['app'].jump 'config round-trip jump'

Write-Host "`n== SSH args / proxy jump ==" -ForegroundColor Cyan
$argsApp = Get-MySshHostArgs -HostInfo $cfg2.hosts['app'] -AllHosts $cfg2.hosts
$lineApp = Format-MySshCommandLine -ArgumentList $argsApp
Assert-True ($lineApp -match '-F NUL') 'uses -F NUL'
Assert-True ($lineApp -match 'ProxyCommand=') 'has ProxyCommand'
Assert-True ($lineApp -match 'jump@10\.0\.0\.1') 'jump in proxy'
Assert-True ($lineApp -match 'app@10\.0\.0\.8') 'destination'
Assert-True ($lineApp -notmatch ' -J ') 'uses ProxyCommand not -J'
Assert-True ($lineApp -notmatch ' -L ') 'no port-forward flags'

Write-Host "`n== Password DPAPI ==" -ForegroundColor Cyan
Set-MySshPasswordPlain -Alias 'direct' -Password 'Secret#123'
Assert-True (Test-MySshPasswordSaved -Alias 'direct') 'password file exists'
Assert-Eq 'Secret#123' (Get-MySshPasswordPlain -Alias 'direct') 'password round-trip'
Ensure-MySshAskPassScripts | Out-Null
$env:MYSSH_ASKPASS_PROMPT = "root@example.com's password:"
$got = & pwsh -NoProfile -File (Join-Path $testRoot 'askpass.ps1')
Assert-Eq 'Secret#123' $got 'askpass matches by host'
Remove-Item Env:MYSSH_ASKPASS_PROMPT -ErrorAction SilentlyContinue

Set-MySshPasswordPlain -Alias 'bastion' -Password 'jump-pass'
Set-MySshPasswordPlain -Alias 'app' -Password 'app-pass'
$ok = Enable-MySshAskPass -Alias 'app' -AllHosts (Read-MySshConfig).hosts
Assert-True $ok 'enable askpass for jump chain'
$order = @(Get-Content (Join-Path $testRoot 'askpass.order'))
Assert-Eq 'bastion' $order[0] 'order jump first'
Assert-Eq 'app' $order[1] 'order target second'
Disable-MySshAskPass

Write-Host "`n== Rename + jump refs ==" -ForegroundColor Cyan
myssh rename bastion gate --force | Out-Null
$cfgR = Read-MySshConfig
Assert-True ($cfgR.hosts.Contains('gate')) 'renamed host exists'
Assert-Eq 'gate' $cfgR.hosts['app'].jump 'jump ref updated'
Assert-True (Test-MySshPasswordSaved -Alias 'gate') 'password moved'

Write-Host "`n== Passthrough split ==" -ForegroundColor Cyan
$sp1 = Split-MySshPassthroughArgs -Passthrough @('-v', 'uname', '-a')
Assert-Eq '-v' $sp1.Options[0] 'option -v'
Assert-Eq 'uname' $sp1.RemoteCommand[0] 'remote uname'
$sp2 = Split-MySshPassthroughArgs -Passthrough @('--', 'ls', '-la')
Assert-Eq 'ls' $sp2.RemoteCommand[0] 'remote after --'

Write-Host "`n== CLI surface ==" -ForegroundColor Cyan
$help = myssh help *>&1 | Out-String
Assert-True ($help -match '跳板') 'help mentions jump'
Assert-True ($help -notmatch 'tunnel add') 'help has no tunnel add'
$ver = myssh version *>&1 | Out-String
Assert-True ($ver -match '0\.3\.0') 'version 0.3.0'
$tun = myssh tunnel *>&1 | Out-String
Assert-True ($tun -match '已移除' -or $tun -match '跳板') 'tunnel command guides to jump'
$status = myssh status *>&1 | Out-String
Assert-True ($status -match 'myssh status') 'status works'
Assert-True ($status -notmatch 'tunnels') 'status has no tunnels line'

$bin = Join-Path $moduleRoot 'bin\myssh.ps1'
$binOut = & pwsh -NoProfile -File $bin version *>&1 | Out-String
Assert-True ($binOut -match '0\.3\.0') 'bin entrypoint version'

myssh remove direct --force | Out-Null
Assert-True (-not ((Read-MySshConfig).hosts.Contains('direct'))) 'host removed'

Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item Env:MYSSH_HOME -ErrorAction SilentlyContinue

Write-Host ""
Write-Host ("Results: {0} passed, {1} failed" -f $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 } else { exit 0 }
