function myssh {
    <#
    .SYNOPSIS
        Manage SSH host profiles and jump-host logins on Windows.
    .DESCRIPTION
        Save SSH connections, connect by alias, and log in through a jump host (--jump).
    .EXAMPLE
        myssh add prod --host 1.2.3.4 --user root --no-key
    .EXAMPLE
        myssh add app --host 10.0.0.8 --user app --jump 36 --no-key
        myssh app
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Command,

        [Parameter(Position = 1)]
        [string]$Name,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest,

        [string]$HostName,
        [string]$SshHost,

        [string]$User,
        [string]$Port,
        [string]$Key,
        [string]$Jump,
        [string]$Description,
        [string]$Password,

        [switch]$Force,
        [switch]$NoKey,
        [switch]$Help
    )

    if ($SshHost -and -not $HostName) { $HostName = $SshHost }

    try {
        if ($Help -or $Command -in @('help', '-h', '--help', '/?')) {
            Show-MySshHelp
            return
        }

        if (-not $Command) {
            Show-MySshStatus
            return
        }

        $cmd = $Command.ToLowerInvariant()

        $parsed = ConvertFrom-MySshRestArgs -Rest $Rest
        if ($parsed.Host -and -not $HostName) { $HostName = $parsed.Host }
        if ($parsed.User -and -not $User) { $User = $parsed.User }
        if ($parsed.Port -and -not $Port) { $Port = $parsed.Port }
        if ($parsed.Key -and -not $Key) { $Key = $parsed.Key }
        if ($parsed.Jump -and -not $Jump) { $Jump = $parsed.Jump }
        if ($parsed.Description -and -not $Description) { $Description = $parsed.Description }
        if ($parsed.Password -and -not $Password) { $Password = $parsed.Password }
        if ($parsed.Force) { $Force = $true }
        if ($parsed.NoKey) { $NoKey = $true }
        $extraSsh = $parsed.Passthrough

        switch ($cmd) {
            'version' {
                Write-Host ("myssh " + (Get-MySshVersion))
                return
            }
            'status' {
                Show-MySshStatus
                return
            }
            'config' {
                Initialize-MySshHome
                $dir = Get-MySshHome
                Write-MySshInfo "配置目录: $dir"
                if (Get-Command explorer.exe -ErrorAction SilentlyContinue) {
                    Start-Process explorer.exe -ArgumentList $dir
                }
                return
            }
            { $_ -in @('list', 'ls') } {
                Invoke-MySshHostList
                return
            }
            { $_ -in @('rename', 'mv') } {
                $newName = $null
                if ($parsed.Positionals -and $parsed.Positionals.Count -gt 0) {
                    $newName = [string]$parsed.Positionals[0]
                }
                elseif ($Rest -and $Rest.Count -gt 0) {
                    $newName = @($Rest | Where-Object { $_ -notlike '-*' }) | Select-Object -First 1
                }
                if (-not $Name -or -not $newName) {
                    Write-MySshError '用法: myssh rename <old> <new>'
                    return
                }
                Invoke-MySshHostRename -OldAlias $Name -NewAlias $newName -Force:$Force
                return
            }
            'add' {
                Invoke-MySshHostAdd -Alias $Name -HostName $HostName -User $User -Port $Port -Key $Key -Jump $Jump -Description $Description -Password $Password -NoKey:$NoKey -Force:$Force
                return
            }
            'password' {
                if (-not $Name) {
                    Write-MySshError '用法: myssh password <alias>  或  myssh password clear <alias>'
                    return
                }
                if ($Name -eq 'clear') {
                    $target = $null
                    if ($parsed.Positionals -and $parsed.Positionals.Count -gt 0) {
                        $target = [string]$parsed.Positionals[0]
                    }
                    elseif ($Rest -and $Rest.Count -gt 0) {
                        $target = $Rest[0]
                    }
                    if (-not $target) {
                        Write-MySshError '用法: myssh password clear <alias>'
                        return
                    }
                    Invoke-MySshPasswordClear -Alias $target
                    return
                }
                $pw = $Password
                if (-not $pw -and $parsed.Password) { $pw = $parsed.Password }
                if (-not $pw -and $Rest) {
                    $maybe = @($Rest | Where-Object { $_ -notlike '-*' })
                    if ($maybe.Count -eq 1 -and $maybe[0] -ne $Name) { $pw = $maybe[0] }
                }
                Invoke-MySshPasswordSet -Alias $Name -Password $pw
                return
            }
            'show' {
                if (-not $Name) { Write-MySshError '用法: myssh show <alias>'; return }
                Invoke-MySshHostShow -Alias $Name
                return
            }
            'edit' {
                if (-not $Name) { Write-MySshError '用法: myssh edit <alias>'; return }
                Invoke-MySshHostEdit -Alias $Name
                return
            }
            { $_ -in @('remove', 'rm') } {
                if (-not $Name) { Write-MySshError '用法: myssh remove <alias>'; return }
                Invoke-MySshHostRemove -Alias $Name -Force:$Force
                return
            }
            { $_ -in @('connect', 'c') } {
                if (-not $Name) { Write-MySshError '用法: myssh connect <alias> [cmd...]'; return }
                Invoke-MySshHostConnect -Alias $Name -SshExtraArgs $extraSsh
                return
            }
            'cmd' {
                if (-not $Name) { Write-MySshError '用法: myssh cmd <alias>'; return }
                Invoke-MySshHostCmd -Alias $Name
                return
            }
            'test' {
                if (-not $Name) { Write-MySshError '用法: myssh test <alias>'; return }
                Invoke-MySshHostTest -Alias $Name
                return
            }
            { $_ -in @('tunnel', 'tunnels') } {
                Write-MySshWarn '端口转发隧道已移除。你要的跳板登录请用: myssh add ... --jump <跳板别名>'
                Write-MySshHint '  例如: myssh add app --host 10.0.0.8 --user app --jump 36 --no-key'
                Write-MySshHint '  然后: myssh app'
                return
            }
            default {
                $cfg = Read-MySshConfig
                if ($cfg.hosts.Contains($Command) -or (@($cfg.hosts.Keys | Where-Object { $_ -like "$Command*" }).Count -eq 1)) {
                    $extra = @()
                    if ($Name) { $extra += $Name }
                    if ($Rest) { $extra += $Rest }
                    Invoke-MySshHostConnect -Alias $Command -SshExtraArgs $extra
                    return
                }

                Write-MySshError "未知命令: $Command"
                Write-MySshHint '  输入 myssh help 查看用法。'
            }
        }
    }
    catch {
        Write-MySshError $_.Exception.Message
    }
}

function ConvertFrom-MySshRestArgs {
    param([string[]]$Rest)

    $result = [ordered]@{
        Host        = $null
        User        = $null
        Port        = $null
        Key         = $null
        Jump        = $null
        Description = $null
        Password    = $null
        Force       = $false
        NoKey       = $false
        Passthrough = [System.Collections.Generic.List[string]]::new()
        Positionals = [System.Collections.Generic.List[string]]::new()
    }

    if (-not $Rest) { return [pscustomobject]$result }

    $i = 0
    while ($i -lt $Rest.Count) {
        $token = $Rest[$i]
        $next = if ($i + 1 -lt $Rest.Count) { $Rest[$i + 1] } else { $null }

        switch -Regex ($token) {
            '^(--host|-H)$' { if ($null -eq $next -or $next.StartsWith('-')) { throw "参数 $token 需要值" }; $result.Host = $next; $i += 2; continue }
            '^(--user|-u)$' { if ($null -eq $next -or $next.StartsWith('-')) { throw "参数 $token 需要值" }; $result.User = $next; $i += 2; continue }
            '^(--port|-p)$' { if ($null -eq $next -or $next.StartsWith('-')) { throw "参数 $token 需要值" }; $result.Port = $next; $i += 2; continue }
            '^(--key|-i)$' { if ($null -eq $next -or $next.StartsWith('-')) { throw "参数 $token 需要值" }; $result.Key = $next; $i += 2; continue }
            '^(--jump|-J)$' { if ($null -eq $next -or $next.StartsWith('-')) { throw "参数 $token 需要值" }; $result.Jump = $next; $i += 2; continue }
            '^(--desc|--description|-d)$' { if ($null -eq $next -or $next.StartsWith('-')) { throw "参数 $token 需要值" }; $result.Description = $next; $i += 2; continue }
            '^(--password|--pass)$' { if ($null -eq $next -or $next.StartsWith('-')) { throw "参数 $token 需要值" }; $result.Password = $next; $i += 2; continue }
            '^(--force|-f)$' { $result.Force = $true; $i += 1; continue }
            '^(--no-key|--nokey)$' { $result.NoKey = $true; $i += 1; continue }
            '^--$' {
                $i += 1
                while ($i -lt $Rest.Count) {
                    $result.Passthrough.Add($Rest[$i])
                    $i += 1
                }
                break
            }
            default {
                $result.Positionals.Add($token)
                $result.Passthrough.Add($token)
                $i += 1
            }
        }
    }

    return [pscustomobject]$result
}

Register-ArgumentCompleter -CommandName myssh -ParameterName Command -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $cmds = @(
        'add', 'list', 'ls', 'show', 'edit', 'rename', 'mv', 'remove', 'rm',
        'connect', 'c', 'password', 'cmd', 'test', 'status',
        'config', 'help', 'version'
    )
    $hosts = Get-MySshHostCompletions -WordToComplete $wordToComplete
    ($cmds + $hosts) |
        Where-Object { $_ -like "$wordToComplete*" } |
        Sort-Object -Unique |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

Register-ArgumentCompleter -CommandName myssh -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $cmd = $null
    if ($fakeBoundParameters.ContainsKey('Command')) {
        $cmd = [string]$fakeBoundParameters['Command']
    }

    $values = switch -Regex ($cmd) {
        '^(password)$' { @('clear') + (Get-MySshHostCompletions -WordToComplete $wordToComplete) }
        default { Get-MySshHostCompletions -WordToComplete $wordToComplete }
    }

    $values |
        Where-Object { $_ -like "$wordToComplete*" } |
        Sort-Object -Unique |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}
