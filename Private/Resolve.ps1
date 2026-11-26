# Alias resolution with unique prefix matching

function Resolve-MySshName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Map,
        [string]$Kind = 'host'
    )

    if ($Map.Contains($Name)) {
        return $Name
    }

    $matches = @($Map.Keys | Where-Object { $_ -like "$Name*" })
    if ($matches.Count -eq 1) {
        return $matches[0]
    }

    if ($matches.Count -gt 1) {
        Write-MySshError "匹配到多个${Kind}: $($matches -join ', ')"
        Write-MySshHint "  请输入更完整的名称。"
        return $null
    }

    Write-MySshError "未找到${Kind}: $Name"
    if ($Map.Count -gt 0) {
        $sample = @($Map.Keys | Sort-Object | Select-Object -First 8) -join ', '
        Write-MySshHint "  可用: $sample"
    }
    else {
        Write-MySshHint '  还没有任何连接，先用: myssh add'
    }
    return $null
}

function Test-MySshAliasName {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._\-:]*$') {
        Write-MySshError "名称无效: $Name"
        Write-MySshHint "  仅允许字母、数字、点、下划线、短横线、冒号，且不能以符号开头。"
        return $false
    }

    $reserved = @(
        'add', 'list', 'ls', 'show', 'edit', 'rename', 'mv', 'remove', 'rm',
        'connect', 'c', 'password', 'cmd', 'test', 'status',
        'config', 'help', 'version', 'h', '-h', '--help'
    )
    if ($reserved -contains $Name.ToLowerInvariant()) {
        Write-MySshError "名称与命令冲突: $Name"
        return $false
    }

    return $true
}

function Get-MySshHostCompletions {
    param([string]$WordToComplete = '')

    try {
        $cfg = Read-MySshConfig
        @($cfg.hosts.Keys | Where-Object { $_ -like "$WordToComplete*" } | Sort-Object)
    }
    catch {
        @()
    }
}

