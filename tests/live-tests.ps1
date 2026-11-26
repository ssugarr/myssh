#Requires -Version 7.0
<#
.SYNOPSIS
  Live tests against real saved hosts in ~/.myssh (aliyun / 36 / scriptuser).
#>
$ErrorActionPreference = 'Stop'
Remove-Item Env:MYSSH_HOME -ErrorAction SilentlyContinue

$failed = 0
$passed = 0
function Assert-True([bool]$c, [string]$n) {
    if ($c) { Write-Host "  PASS  $n" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $n" -ForegroundColor Red; $script:failed++ }
}

$moduleRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $moduleRoot 'myssh.psd1') -Force
Get-ChildItem (Join-Path $moduleRoot 'Private\*.ps1') | ForEach-Object { . $_.FullName }

Write-Host "`n== Preflight ==" -ForegroundColor Cyan
$cfg = Read-MySshConfig
foreach ($a in @('aliyun', '36', 'scriptuser')) {
    Assert-True ($cfg.hosts.Contains($a)) "host exists: $a"
    Assert-True (Test-MySshPasswordSaved -Alias $a) "password saved: $a"
}
Assert-True ($cfg.hosts['scriptuser'].jump -eq '36') 'scriptuser uses jump 36'

Write-Host "`n== myssh test (TCP + login) ==" -ForegroundColor Cyan
foreach ($a in @('aliyun', '36', 'scriptuser')) {
    Write-Host "--- $a ---"
    myssh test $a
}

function Invoke-Remote([string]$Alias, [string]$Cmd) {
    $cfg = Read-MySshConfig
    $name = Resolve-MySshName -Name $Alias -Map $cfg.hosts -Kind '连接'
    $args = Get-MySshHostArgs -HostInfo $cfg.hosts[$name] -AllHosts $cfg.hosts -RemoteCommand @($Cmd)
    $exe = Get-MySshExecutable
    $null = Enable-MySshAskPass -Alias $name -AllHosts $cfg.hosts
    try {
        $out = & $exe @args 2>&1 | Out-String
        return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
    }
    finally { Disable-MySshAskPass }
}

Write-Host "`n== Auto password / jump login ==" -ForegroundColor Cyan
$r1 = Invoke-Remote 'aliyun' 'echo LIVE_ALIYUN; whoami'
Assert-True ($r1.Exit -eq 0 -and $r1.Out -match 'LIVE_ALIYUN') 'aliyun auto login'
$r2 = Invoke-Remote '36' 'echo LIVE_36; whoami'
Assert-True ($r2.Exit -eq 0 -and $r2.Out -match 'LIVE_36') '36 auto login'
$r3 = Invoke-Remote 'scriptuser' 'echo LIVE_JUMP; whoami'
Assert-True ($r3.Exit -eq 0 -and $r3.Out -match 'LIVE_JUMP') 'scriptuser jump auto login'

Write-Host "`n== cmd shows ProxyCommand ==" -ForegroundColor Cyan
$cmdOut = myssh cmd scriptuser *>&1 | Out-String
Assert-True ($cmdOut -match 'ProxyCommand=') 'cmd shows proxy jump'
Assert-True ($cmdOut -notmatch ' -L ') 'cmd has no -L tunnel'

Write-Host ""
Write-Host ("Live results: {0} passed, {1} failed" -f $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 } else { exit 0 }
