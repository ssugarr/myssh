# Password storage via Windows DPAPI (CurrentUser) — never plaintext in config.json

function Get-MySshSecretsDir {
    Join-Path (Get-MySshHome) 'secrets'
}

function Get-MySshSecretPath {
    param([Parameter(Mandatory)][string]$Alias)
    $safe = ($Alias -replace '[^\w\.\-]', '_')
    Join-Path (Get-MySshSecretsDir) "$safe.dpapi"
}

function Initialize-MySshSecrets {
    $dir = Get-MySshSecretsDir
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Ensure-MySshAskPassScripts | Out-Null
}

function Protect-MySshSecretText {
    param([Parameter(Mandatory)][string]$Text)
    $asm = [System.Reflection.Assembly]::LoadWithPartialName('System.Security.Cryptography.ProtectedData')
    if (-not $asm) {
        Add-Type -AssemblyName System.Security.Cryptography.ProtectedData -ErrorAction SilentlyContinue
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $protected = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Convert]::ToBase64String($protected)
}

function Unprotect-MySshSecretText {
    param([Parameter(Mandatory)][string]$Base64)
    $asm = [System.Reflection.Assembly]::LoadWithPartialName('System.Security.Cryptography.ProtectedData')
    if (-not $asm) {
        Add-Type -AssemblyName System.Security.Cryptography.ProtectedData -ErrorAction SilentlyContinue
    }
    $protected = [Convert]::FromBase64String($Base64)
    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $protected,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Set-MySshPasswordPlain {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$Password
    )
    Initialize-MySshSecrets
    $blob = Protect-MySshSecretText -Text $Password
    $path = Get-MySshSecretPath -Alias $Alias
    [System.IO.File]::WriteAllText($path, $blob, [System.Text.UTF8Encoding]::new($false))
}

function Set-MySshPassword {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][securestring]$Password
    )
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        Set-MySshPasswordPlain -Alias $Alias -Password $plain
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-MySshPasswordPlain {
    param([Parameter(Mandatory)][string]$Alias)

    $path = Get-MySshSecretPath -Alias $Alias
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    try {
        $blob = (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim()
        return (Unprotect-MySshSecretText -Base64 $blob)
    }
    catch {
        Write-MySshWarn "无法解密密码 ($Alias): $($_.Exception.Message)"
        return $null
    }
}

function Test-MySshPasswordSaved {
    param([Parameter(Mandatory)][string]$Alias)
    Test-Path -LiteralPath (Get-MySshSecretPath -Alias $Alias)
}

function Remove-MySshPassword {
    param([Parameter(Mandatory)][string]$Alias)
    $path = Get-MySshSecretPath -Alias $Alias
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
        return $true
    }
    return $false
}

function Rename-MySshPassword {
    param(
        [Parameter(Mandatory)][string]$OldAlias,
        [Parameter(Mandatory)][string]$NewAlias
    )

    $oldPath = Get-MySshSecretPath -Alias $OldAlias
    if (-not (Test-Path -LiteralPath $oldPath)) {
        return $false
    }

    Initialize-MySshSecrets
    $newPath = Get-MySshSecretPath -Alias $NewAlias
    if ((Test-Path -LiteralPath $newPath) -and ($oldPath -ne $newPath)) {
        Remove-Item -LiteralPath $newPath -Force
    }
    if ($oldPath -ne $newPath) {
        Move-Item -LiteralPath $oldPath -Destination $newPath -Force
    }
    return $true
}

function Ensure-MySshAskPassScripts {
    Initialize-MySshHome
    $homeDir = Get-MySshHome
    $ps1 = Join-Path $homeDir 'askpass.ps1'
    $cmd = Join-Path $homeDir 'askpass.cmd'

    $ps1Body = @'
$ErrorActionPreference = "Stop"
$prompt = $env:MYSSH_ASKPASS_PROMPT
if (-not $prompt) { $prompt = ($args -join " ") }

function Get-HomeDir {
    if ($env:MYSSH_HOME -and $env:MYSSH_HOME.Trim()) { return $env:MYSSH_HOME.Trim() }
    Join-Path $HOME ".myssh"
}

function Unprotect-One([string]$Alias) {
    $safe = ($Alias -replace "[^\w\.\-]", "_")
    $path = Join-Path (Get-HomeDir) "secrets\$safe.dpapi"
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    Add-Type -AssemblyName System.Security.Cryptography.ProtectedData -ErrorAction SilentlyContinue | Out-Null
    $blob = (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim()
    $bytes = [Convert]::FromBase64String($blob)
    $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $bytes, $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Text.Encoding]::UTF8.GetString($plain)
}

$cfgPath = Join-Path (Get-HomeDir) "config.json"
if (-not (Test-Path -LiteralPath $cfgPath)) { Write-Output ""; exit 0 }
$cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $cfg.hosts) { Write-Output ""; exit 0 }

$candidates = @()
foreach ($p in $cfg.hosts.PSObject.Properties) {
    $pw = Unprotect-One $p.Name
    if (-not $pw) { continue }
    $candidates += [pscustomobject]@{
        Alias = $p.Name
        Host  = [string]$p.Value.host
        User  = [string]$p.Value.user
        Password = $pw
    }
}

foreach ($c in $candidates) {
    if ($c.User -and $c.Host -and $prompt -match [regex]::Escape(("$($c.User)@$($c.Host)"))) {
        [Console]::Out.Write($c.Password)
        exit 0
    }
}
foreach ($c in $candidates) {
    if ($c.Host -and $prompt -match [regex]::Escape($c.Host)) {
        [Console]::Out.Write($c.Password)
        exit 0
    }
}

$orderFile = Join-Path (Get-HomeDir) "askpass.order"
if (Test-Path -LiteralPath $orderFile) {
    $lines = @(Get-Content -LiteralPath $orderFile | Where-Object { $_ -and $_.Trim() })
    if ($lines.Count -gt 0) {
        $next = $lines[0].Trim()
        $rest = @($lines | Select-Object -Skip 1)
        if ($rest.Count -gt 0) {
            Set-Content -LiteralPath $orderFile -Value ($rest -join [Environment]::NewLine) -Encoding UTF8
        } else {
            Remove-Item -LiteralPath $orderFile -Force -ErrorAction SilentlyContinue
        }
        $pw = Unprotect-One $next
        if ($pw) { [Console]::Out.Write($pw); exit 0 }
    }
}

Write-Output ""
exit 0
'@

    $cmdBody = @"
@echo off
set "MYSSH_ASKPASS_PROMPT=%*"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$ps1"
"@

    [System.IO.File]::WriteAllText($ps1, $ps1Body, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($cmd, $cmdBody, [System.Text.UTF8Encoding]::new($false))
    return $cmd
}

function Enable-MySshAskPass {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][System.Collections.IDictionary]$AllHosts
    )

    $order = [System.Collections.Generic.List[string]]::new()
    if (-not $AllHosts.Contains($Alias)) {
        return $false
    }

    $h = $AllHosts[$Alias]
    if ($h.jump -and (Test-MySshPasswordSaved -Alias ([string]$h.jump))) {
        $order.Add([string]$h.jump)
    }
    if (Test-MySshPasswordSaved -Alias $Alias) {
        $order.Add($Alias)
    }

    if ($order.Count -eq 0) {
        return $false
    }

    $ask = Ensure-MySshAskPassScripts
    $orderFile = Join-Path (Get-MySshHome) 'askpass.order'
    Set-Content -LiteralPath $orderFile -Value ($order -join [Environment]::NewLine) -Encoding UTF8

    $env:SSH_ASKPASS = $ask
    $env:SSH_ASKPASS_REQUIRE = 'force'
    $env:DISPLAY = '1'
    return $true
}

function Disable-MySshAskPass {
    param([switch]$KeepOrder)

    Remove-Item Env:SSH_ASKPASS -ErrorAction SilentlyContinue
    Remove-Item Env:SSH_ASKPASS_REQUIRE -ErrorAction SilentlyContinue
    Remove-Item Env:MYSSH_ASKPASS_PROMPT -ErrorAction SilentlyContinue
    if (-not $KeepOrder) {
        $orderFile = Join-Path (Get-MySshHome) 'askpass.order'
        Remove-Item -LiteralPath $orderFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-MySshPasswordSet {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [string]$Password
    )

    $cfg = Read-MySshConfig
    $name = Resolve-MySshName -Name $Alias -Map $cfg.hosts -Kind '连接'
    if (-not $name) { return }

    if ($Password) {
        Set-MySshPasswordPlain -Alias $name -Password $Password
    }
    else {
        $secure = Read-Host -Prompt "为 '$name' 设置密码" -AsSecureString
        if (-not $secure -or $secure.Length -eq 0) {
            Write-MySshInfo '已取消。'
            return
        }
        Set-MySshPassword -Alias $name -Password $secure
    }

    Write-MySshOk "已保存密码: $name（DPAPI 加密，仅当前 Windows 用户可读）"
    Write-MySshHint "  下次 myssh $name 将自动填写密码"
}

function Invoke-MySshPasswordClear {
    param([Parameter(Mandatory)][string]$Alias)

    $cfg = Read-MySshConfig
    $name = Resolve-MySshName -Name $Alias -Map $cfg.hosts -Kind '连接'
    if (-not $name) { return }

    if (Remove-MySshPassword -Alias $name) {
        Write-MySshOk "已清除密码: $name"
    }
    else {
        Write-MySshWarn "没有已保存的密码: $name"
    }
}
