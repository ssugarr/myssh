# UX helpers: colors, messages, prompts, tables

function Get-MySshStyle {
    [CmdletBinding()]
    param()

    $supports = $Host.UI.SupportsVirtualTerminal -or $env:WT_SESSION -or $env:TERM
    if (-not $supports) {
        return [pscustomobject]@{
            Ok     = ''
            Err    = ''
            Warn   = ''
            Dim    = ''
            Accent = ''
            Title  = ''
            Reset  = ''
            Bold   = ''
        }
    }

    return [pscustomobject]@{
        Ok     = $PSStyle.Foreground.Green
        Err    = $PSStyle.Foreground.Red
        Warn   = $PSStyle.Foreground.Yellow
        Dim    = $PSStyle.Foreground.BrightBlack
        Accent = $PSStyle.Foreground.Cyan
        Title  = $PSStyle.Foreground.BrightCyan
        Reset  = $PSStyle.Reset
        Bold   = $PSStyle.Bold
    }
}

function Write-MySshOk {
    param([Parameter(Mandatory)][string]$Message)
    $s = Get-MySshStyle
    Write-Host "$($s.Ok)✔$($s.Reset) $Message"
}

function Write-MySshError {
    param([Parameter(Mandatory)][string]$Message)
    $s = Get-MySshStyle
    Write-Host "$($s.Err)✖$($s.Reset) $Message"
}

function Write-MySshWarn {
    param([Parameter(Mandatory)][string]$Message)
    $s = Get-MySshStyle
    Write-Host "$($s.Warn)!$($s.Reset)  $Message"
}

function Write-MySshInfo {
    param([Parameter(Mandatory)][string]$Message)
    $s = Get-MySshStyle
    Write-Host "$($s.Dim)›$($s.Reset)  $Message"
}

function Write-MySshTitle {
    param([Parameter(Mandatory)][string]$Message)
    $s = Get-MySshStyle
    Write-Host ""
    Write-Host "$($s.Title)$($s.Bold)$Message$($s.Reset)"
}

function Write-MySshHint {
    param([Parameter(Mandatory)][string]$Message)
    $s = Get-MySshStyle
    Write-Host "$($s.Dim)$Message$($s.Reset)"
}

function Read-MySshInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Default,
        [switch]$Required,
        [switch]$Secure
    )

    $s = Get-MySshStyle
    $suffix = if ($Default) { " $($s.Dim)[$Default]$($s.Reset)" } else { '' }
    $label = "$($s.Accent)?$($s.Reset)  $Prompt${suffix}: "

    if ($Secure) {
        $secure = Read-Host -Prompt ($Prompt + $(if ($Default) { " [$Default]" } else { '' })) -AsSecureString
        return $secure
    }

    Write-Host -NoNewline $label
    $value = Read-Host
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = $Default
    }

    if ($Required -and [string]::IsNullOrWhiteSpace($value)) {
        Write-MySshError "该项不能为空。"
        return Read-MySshInput -Prompt $Prompt -Default $Default -Required:$Required
    }

    return $value
}

function Confirm-MySsh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$DefaultYes
    )

    $s = Get-MySshStyle
    $hint = if ($DefaultYes) { 'Y/n' } else { 'y/N' }
    Write-Host -NoNewline "$($s.Warn)?$($s.Reset)  $Message $($s.Dim)($hint)$($s.Reset): "
    $answer = Read-Host

    if ([string]::IsNullOrWhiteSpace($answer)) {
        return [bool]$DefaultYes
    }

    return $answer -match '^(y|yes|是)$'
}

function Format-MySshHostRow {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)]$HostInfo
    )

    $target = if ($HostInfo.user) { "$($HostInfo.user)@$($HostInfo.host)" } else { [string]$HostInfo.host }
    if ($HostInfo.port -and [int]$HostInfo.port -ne 22) {
        $target = "${target}:$($HostInfo.port)"
    }

    $auth = @()
    if ($HostInfo.key) { $auth += 'key' }
    if (Test-MySshPasswordSaved -Alias $Alias) { $auth += 'pass' }
    $authText = if ($auth.Count -gt 0) { $auth -join '+' } else { '-' }

    [pscustomobject]@{
        Alias  = $Alias
        Target = $target
        Jump   = $(if ($HostInfo.jump) { $HostInfo.jump } else { '-' })
        Auth   = $authText
        Desc   = $(if ($HostInfo.description) { $HostInfo.description } else { '' })
    }
}

function Show-MySshHostTable {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Hosts)

    if ($Hosts.Count -eq 0) {
        Write-MySshWarn "还没有保存任何连接。"
        Write-MySshHint "  试试: myssh add"
        return
    }

    Write-MySshTitle "Saved hosts ($($Hosts.Count))"
    $rows = foreach ($name in ($Hosts.Keys | Sort-Object)) {
        Format-MySshHostRow -Alias $name -HostInfo $Hosts[$name]
    }

    $s = Get-MySshStyle
    $fmt = "{0,-16} {1,-32} {2,-14} {3,-10} {4}"
    Write-Host ($s.Dim + ($fmt -f 'ALIAS', 'TARGET', 'JUMP', 'AUTH', 'DESCRIPTION') + $s.Reset)
    foreach ($r in $rows) {
        Write-Host ($fmt -f $r.Alias, $r.Target, $r.Jump, $r.Auth, $r.Desc)
    }
    Write-Host ""
    Write-MySshHint "直连: myssh <alias>   跳板: add 时加 --jump   保存密码: myssh password <alias>"
}

function Show-MySshStatus {
    $cfg = Read-MySshConfig
    $s = Get-MySshStyle

    $passCount = @($cfg.hosts.Keys | Where-Object { Test-MySshPasswordSaved -Alias $_ }).Count
    $jumpCount = @($cfg.hosts.Values | Where-Object { $_.jump }).Count

    Write-MySshTitle 'myssh status'
    Write-Host ("  {0}hosts{1}   {2}  (password saved: {3}, via jump: {4})" -f $s.Dim, $s.Reset, $cfg.hosts.Count, $passCount, $jumpCount)
    Write-Host ("  {0}home{1}    {2}" -f $s.Dim, $s.Reset, (Get-MySshHome))
    Write-Host ""

    if ($cfg.hosts.Count -gt 0) {
        Show-MySshHostTable -Hosts $cfg.hosts
    }
}

function Show-MySshHelp {
    $s = Get-MySshStyle
    Write-Host ""
    Write-Host "$($s.Title)$($s.Bold)myssh$($s.Reset)  —  Windows SSH 连接 / 跳板登录  $($s.Dim)v0.3.0$($s.Reset)"
    Write-Host ""
    Write-Host "$($s.Bold)两种用法$($s.Reset)"
    Write-Host "  1. 直连可达主机           →  myssh <alias>"
    Write-Host "  2. 经跳板登录内网机       →  保存时加 --jump，再 myssh <alias>"
    Write-Host ""
    Write-Host "$($s.Bold)用法$($s.Reset)"
    Write-Host "  myssh <command> [options]"
    Write-Host "  myssh <alias> [remote-cmd]    $($s.Dim)# 登录；可跟远程命令$($s.Reset)"
    Write-Host ""
    Write-Host "$($s.Bold)主机$($s.Reset)"
    Write-Host "  add [alias]                   新增连接（可交互，默认问密码）"
    Write-Host "  list, ls                      列出所有连接"
    Write-Host "  show <alias>                  查看连接详情"
    Write-Host "  edit <alias>                  编辑连接（可改密码）"
    Write-Host "  rename, mv <old> <new>        重命名别名（同步跳板引用/密码）"
    Write-Host "  remove, rm <alias>            删除连接"
    Write-Host "  connect, c <alias> [cmd...]   连接主机 / 执行远程命令"
    Write-Host "  password <alias>              保存/更新登录密码（DPAPI）"
    Write-Host "  password clear <alias>        清除已保存密码"
    Write-Host "  cmd <alias>                   打印等价 ssh 命令"
    Write-Host "  test <alias>                  测试连通性（含自动填密登录）"
    Write-Host ""
    Write-Host "$($s.Bold)其他$($s.Reset)"
    Write-Host "  status                        总览"
    Write-Host "  config                        打开配置目录"
    Write-Host "  help                          显示帮助"
    Write-Host "  version                       显示版本"
    Write-Host ""
    Write-Host "$($s.Bold)示例$($s.Reset)"
    Write-Host "  $($s.Dim)# 直连$($s.Reset)"
    Write-Host "  $($s.Dim)myssh add aliyun --host 1.2.3.4 --user root --no-key --password '***'$($s.Reset)"
    Write-Host "  $($s.Dim)myssh aliyun$($s.Reset)"
    Write-Host "  $($s.Dim)# 跳板登录内网机$($s.Reset)"
    Write-Host "  $($s.Dim)myssh add 36 --host 36.26.1.154 --port 10080 --user zhao --no-key$($s.Reset)"
    Write-Host "  $($s.Dim)myssh add scriptuser --host 116.62.197.239 --port 21122 --user scriptuser --jump 36 --no-key$($s.Reset)"
    Write-Host "  $($s.Dim)myssh scriptuser$($s.Reset)"
    Write-Host "  $($s.Dim)myssh aliyun -- uname -a$($s.Reset)"
    Write-Host ""
}
