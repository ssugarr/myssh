# Host CRUD + connect / test / cmd

function Get-MySshDefaultKeyPath {
    foreach ($name in @('id_ed25519', 'id_rsa', 'id_ecdsa')) {
        $candidate = Join-Path $HOME ".ssh\$name"
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return ''
}

function Invoke-MySshHostAdd {
    param(
        [string]$Alias,
        [string]$HostName,
        [string]$User,
        [string]$Port,
        [string]$Key,
        [string]$Jump,
        [string]$Description,
        [string]$Password,
        [switch]$NoKey,
        [switch]$Force
    )

    $cfg = Read-MySshConfig
    # CLI mode: alias + host already given → don't prompt for optional fields
    $interactive = -not ($Alias -and $HostName)

    if (-not $Alias) {
        $Alias = Read-MySshInput -Prompt '别名 (alias)' -Required
    }
    if (-not (Test-MySshAliasName -Name $Alias)) {
        return
    }

    if ($cfg.hosts.Contains($Alias) -and -not $Force) {
        if ($interactive) {
            if (-not (Confirm-MySsh "连接 '$Alias' 已存在，要覆盖吗？")) {
                Write-MySshInfo '已取消。'
                return
            }
        }
        else {
            Write-MySshError "连接 '$Alias' 已存在。加 --force 可覆盖。"
            return
        }
    }

    if (-not $HostName) {
        $HostName = Read-MySshInput -Prompt '主机地址 (host)' -Required
    }
    if (-not $User) {
        $defaultUser = $env:USERNAME
        if ($interactive) {
            $User = Read-MySshInput -Prompt '用户名' -Default $defaultUser
        }
        else {
            $User = $defaultUser
        }
    }
    if (-not $Port) {
        if ($interactive) {
            $Port = Read-MySshInput -Prompt '端口' -Default '22'
        }
        else {
            $Port = '22'
        }
    }
    # --- auth: password / key / both ---
    $pendingSecure = $null
    if ($interactive -and -not $NoKey -and -not $Key -and -not $Password) {
        Write-MySshHint '认证方式: password=密码  key=密钥  both=都要'
        $auth = Read-MySshInput -Prompt '认证方式' -Default 'password'
        $wantKey = $false
        $wantPassword = $false
        switch -Regex ($auth.Trim().ToLowerInvariant()) {
            '^(k|key|密钥)$' { $wantKey = $true }
            '^(b|both|all|都)$' { $wantKey = $true; $wantPassword = $true }
            default { $wantPassword = $true } # password
        }
        if ($wantKey) {
            $keyDefault = Get-MySshDefaultKeyPath
            $Key = Read-MySshInput -Prompt '私钥路径' -Default $keyDefault
        }
        else {
            $Key = ''
        }
        if ($wantPassword) {
            $pendingSecure = Read-Host -Prompt '登录密码（将 DPAPI 加密保存）' -AsSecureString
            if (-not $pendingSecure -or $pendingSecure.Length -eq 0) {
                Write-MySshWarn '未输入密码，稍后可用: myssh password <alias>'
                $pendingSecure = $null
            }
        }
    }
    else {
        if ($NoKey) {
            $Key = ''
        }
        elseif (-not $Key) {
            # CLI without --no-key: keep previous convenience of default key
            $Key = Get-MySshDefaultKeyPath
        }
    }

    if ($interactive -and -not $Jump) {
        if ($cfg.hosts.Count -gt 0) {
            Write-MySshHint ("已有主机: " + (($cfg.hosts.Keys | Sort-Object) -join ', '))
        }
        $Jump = Read-MySshInput -Prompt '跳板机别名 (可空，内网机才需要)'
    }
    if ($interactive -and -not $Description) {
        $Description = Read-MySshInput -Prompt '备注 (可空)'
    }

    $portNum = 22
    if (-not [int]::TryParse("$Port", [ref]$portNum) -or $portNum -lt 1 -or $portNum -gt 65535) {
        Write-MySshError "端口无效: $Port"
        return
    }

    $entry = [ordered]@{
        host = $HostName.Trim()
        user = $User.Trim()
        port = $portNum
    }

    if ($Key) {
        $entry.key = (Expand-MySshPath $Key.Trim())
        if (-not (Test-Path -LiteralPath $entry.key)) {
            Write-MySshWarn "私钥文件不存在: $($entry.key)"
        }
    }
    if ($Jump) {
        $entry.jump = $Jump.Trim()
        if (-not $cfg.hosts.Contains($entry.jump) -and $entry.jump -notmatch '[@.]') {
            Write-MySshWarn "跳板 '$($entry.jump)' 尚未保存为连接，连接时将按原始地址传递。"
        }
    }
    if ($Description) {
        $entry.description = $Description.Trim()
    }

    $cfg.hosts[$Alias] = $entry
    Save-MySshConfig -Config $cfg

    $passwordSaved = $false
    if ($pendingSecure) {
        Set-MySshPassword -Alias $Alias -Password $pendingSecure
        $passwordSaved = $true
    }
    elseif ($Password) {
        Set-MySshPasswordPlain -Alias $Alias -Password $Password
        $passwordSaved = $true
    }

    Write-MySshOk "已保存连接: $Alias → $($entry.user)@$($entry.host):$($entry.port)"
    if ($passwordSaved) {
        Write-MySshHint "  密码已加密保存，连接: myssh $Alias"
    }
    else {
        Write-MySshHint "  连接: myssh $Alias"
        if (-not $entry.key) {
            Write-MySshHint "  保存密码免输入: myssh password $Alias"
        }
    }
}

function Invoke-MySshHostList {
    $cfg = Read-MySshConfig
    Show-MySshHostTable -Hosts $cfg.hosts
}

function Invoke-MySshHostShow {
    param([Parameter(Mandatory)][string]$Alias)

    $cfg = Read-MySshConfig
    $name = Resolve-MySshName -Name $Alias -Map $cfg.hosts -Kind '连接'
    if (-not $name) { return }

    $h = $cfg.hosts[$name]
    $s = Get-MySshStyle
    Write-MySshTitle "Host: $name"
    $rows = @(
        @{ K = 'Alias'; V = $name }
        @{ K = 'Host'; V = $h.host }
        @{ K = 'User'; V = $(if ($h.user) { $h.user } else { '-' }) }
        @{ K = 'Port'; V = $(if ($h.port) { $h.port } else { 22 }) }
        @{ K = 'Key'; V = $(if ($h.key) { $h.key } else { '-' }) }
        @{ K = 'Pass'; V = $(if (Test-MySshPasswordSaved -Alias $name) { 'saved (DPAPI)' } else { '-' }) }
        @{ K = 'Jump'; V = $(if ($h.jump) { $h.jump } else { '-' }) }
        @{ K = 'Desc'; V = $(if ($h.description) { $h.description } else { '-' }) }
    )
    foreach ($r in $rows) {
        Write-Host ("  {0}{1,-6}{2} {3}" -f $s.Dim, $r.K, $s.Reset, $r.V)
    }

    $sshArgs = Get-MySshHostArgs -HostInfo $h -AllHosts $cfg.hosts
    Write-Host ""
    Write-Host ("  {0}Command{1} {2}" -f $s.Dim, $s.Reset, (Format-MySshCommandLine -ArgumentList $sshArgs))
    Write-Host ""
}

function Invoke-MySshHostEdit {
    param([Parameter(Mandatory)][string]$Alias)

    $cfg = Read-MySshConfig
    $name = Resolve-MySshName -Name $Alias -Map $cfg.hosts -Kind '连接'
    if (-not $name) { return }

    $h = $cfg.hosts[$name]
    Write-MySshTitle "编辑连接: $name"
    Write-MySshHint "直接回车保留原值。"

    $hostName = Read-MySshInput -Prompt '主机地址' -Default $h.host -Required
    $user = Read-MySshInput -Prompt '用户名' -Default $(if ($h.user) { $h.user } else { '' })
    $port = Read-MySshInput -Prompt '端口' -Default $(if ($h.port) { [string]$h.port } else { '22' })

    $hasPass = Test-MySshPasswordSaved -Alias $name
    Write-MySshHint ("当前认证: " + $(if ($h.key -and $hasPass) { 'key+pass' } elseif ($h.key) { 'key' } elseif ($hasPass) { 'pass' } else { '无' }))
    Write-MySshHint '认证方式: password / key / both / keep=保持不变'
    $auth = Read-MySshInput -Prompt '认证方式' -Default 'keep'
    $key = $(if ($h.key) { [string]$h.key } else { '' })
    $pendingSecure = $null
    $clearKey = $false
    $clearPass = $false

    switch -Regex ($auth.Trim().ToLowerInvariant()) {
        '^(keep|kep|原|不变)$' { }
        '^(p|password|密码)$' {
            $clearKey = $true
            $key = ''
            $pendingSecure = Read-Host -Prompt '新密码（DPAPI 加密）' -AsSecureString
        }
        '^(key|密钥)$' {
            $keyDefault = if ($h.key) { $h.key } else { Get-MySshDefaultKeyPath }
            $key = Read-MySshInput -Prompt '私钥路径' -Default $keyDefault
            if ($hasPass -and (Confirm-MySsh '清除已保存密码？')) { $clearPass = $true }
        }
        '^(b|both|都)$' {
            $keyDefault = if ($h.key) { $h.key } else { Get-MySshDefaultKeyPath }
            $key = Read-MySshInput -Prompt '私钥路径' -Default $keyDefault
            $pendingSecure = Read-Host -Prompt '新密码（DPAPI 加密）' -AsSecureString
        }
        default {
            Write-MySshWarn "未识别认证方式，保持原认证不变。"
        }
    }

    $jump = Read-MySshInput -Prompt '跳板机' -Default $(if ($h.jump) { $h.jump } else { '' })
    $desc = Read-MySshInput -Prompt '备注' -Default $(if ($h.description) { $h.description } else { '' })

    if ($auth -match '^(keep|kep|原|不变)$' -or $auth.Trim() -eq '') {
        if ($hasPass -and (Confirm-MySsh '更新已保存的密码？')) {
            $pendingSecure = Read-Host -Prompt '新密码' -AsSecureString
        }
    }

    $noKey = $clearKey -or (-not $key)
    Invoke-MySshHostAdd -Alias $name -HostName $hostName -User $user -Port $port -Key $key -Jump $jump -Description $desc -NoKey:$noKey -Force

    if ($clearPass) {
        Remove-MySshPassword -Alias $name | Out-Null
        Write-MySshOk "已清除密码: $name"
    }
    if ($pendingSecure -and $pendingSecure.Length -gt 0) {
        Set-MySshPassword -Alias $name -Password $pendingSecure
        Write-MySshOk "已更新密码: $name"
    }
}

function Invoke-MySshHostRename {
    param(
        [Parameter(Mandatory)][string]$OldAlias,
        [Parameter(Mandatory)][string]$NewAlias,
        [switch]$Force
    )

    $cfg = Read-MySshConfig
    $old = Resolve-MySshName -Name $OldAlias -Map $cfg.hosts -Kind '连接'
    if (-not $old) { return }

    if (-not (Test-MySshAliasName -Name $NewAlias)) {
        return
    }
    if ($old -eq $NewAlias) {
        Write-MySshWarn '新旧别名相同，无需重命名。'
        return
    }
    if ($cfg.hosts.Contains($NewAlias) -and -not $Force) {
        Write-MySshError "目标别名已存在: $NewAlias（加 --force 可覆盖）"
        return
    }

    if ($cfg.hosts.Contains($NewAlias) -and $Force) {
        $cfg.hosts.Remove($NewAlias)
        Remove-MySshPassword -Alias $NewAlias | Out-Null
    }

    $cfg.hosts[$NewAlias] = $cfg.hosts[$old]
    $cfg.hosts.Remove($old)

    foreach ($key in @($cfg.hosts.Keys)) {
        if ($cfg.hosts[$key].jump -eq $old) {
            $cfg.hosts[$key].jump = $NewAlias
        }
    }

    Save-MySshConfig -Config $cfg
    Rename-MySshPassword -OldAlias $old -NewAlias $NewAlias | Out-Null
    Write-MySshOk "已重命名: $old → $NewAlias"
}

function Invoke-MySshHostRemove {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [switch]$Force
    )

    $cfg = Read-MySshConfig
    $name = Resolve-MySshName -Name $Alias -Map $cfg.hosts -Kind '连接'
    if (-not $name) { return }

    if (-not $Force) {
        if (-not (Confirm-MySsh "确定删除连接 '$name'？")) {
            Write-MySshInfo '已取消。'
            return
        }
    }

    $cfg.hosts.Remove($name)
    Save-MySshConfig -Config $cfg
    Remove-MySshPassword -Alias $name | Out-Null
    Write-MySshOk "已删除连接: $name"
}

function Split-MySshPassthroughArgs {
    param([string[]]$Passthrough)

    $options = [System.Collections.Generic.List[string]]::new()
    $remote = [System.Collections.Generic.List[string]]::new()
    if (-not $Passthrough) {
        return [pscustomobject]@{ Options = @(); RemoteCommand = @() }
    }

    $mode = 'opt' # opt | remote
    foreach ($a in $Passthrough) {
        if ($null -eq $a) { continue }
        if ($a -eq '--') {
            $mode = 'remote'
            continue
        }
        if ($mode -eq 'remote') {
            $remote.Add([string]$a)
            continue
        }
        if ([string]$a -like '-*') {
            $options.Add([string]$a)
        }
        else {
            $mode = 'remote'
            $remote.Add([string]$a)
        }
    }

    return [pscustomobject]@{
        Options       = $options.ToArray()
        RemoteCommand = $remote.ToArray()
    }
}

function Invoke-MySshHostConnect {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [string[]]$SshExtraArgs
    )

    $cfg = Read-MySshConfig
    $name = Resolve-MySshName -Name $Alias -Map $cfg.hosts -Kind '连接'
    if (-not $name) { return }

    $h = $cfg.hosts[$name]
    $split = Split-MySshPassthroughArgs -Passthrough $SshExtraArgs
    $sshArgs = Get-MySshHostArgs -HostInfo $h -AllHosts $cfg.hosts -ExtraArgs $split.Options -RemoteCommand $split.RemoteCommand
    $exe = Get-MySshExecutable

    $usedAskPass = Enable-MySshAskPass -Alias $name -AllHosts $cfg.hosts
    $remoteHint = if ($split.RemoteCommand.Count -gt 0) { " → $($split.RemoteCommand -join ' ')" } else { '' }
    if ($usedAskPass) {
        Write-MySshInfo "连接 $name ($($h.user)@$($h.host))$remoteHint ...（自动填密）"
    }
    else {
        Write-MySshInfo "连接 $name ($($h.user)@$($h.host))$remoteHint ..."
        if (-not $h.key) {
            Write-MySshHint "  未保存密码。可执行: myssh password $name"
        }
    }

    try {
        & $exe @sshArgs
        $code = $LASTEXITCODE
        if ($code -ne 0 -and $null -ne $code) {
            Write-MySshError "ssh 退出码: $code"
        }
    }
    finally {
        Disable-MySshAskPass
    }
}

function Invoke-MySshHostCmd {
    param([Parameter(Mandatory)][string]$Alias)

    $cfg = Read-MySshConfig
    $name = Resolve-MySshName -Name $Alias -Map $cfg.hosts -Kind '连接'
    if (-not $name) { return }

    $sshArgs = Get-MySshHostArgs -HostInfo $cfg.hosts[$name] -AllHosts $cfg.hosts
    $line = Format-MySshCommandLine -ArgumentList $sshArgs
    Write-Host $line
    try {
        Set-Clipboard -Value $line
        Write-MySshHint '已复制到剪贴板。'
    }
    catch {
        # Clipboard may be unavailable in some hosts; ignore.
    }
}

function Invoke-MySshHostTest {
    param([Parameter(Mandatory)][string]$Alias)

    $cfg = Read-MySshConfig
    $name = Resolve-MySshName -Name $Alias -Map $cfg.hosts -Kind '连接'
    if (-not $name) { return }

    $h = $cfg.hosts[$name]
    $exe = Get-MySshExecutable

    Write-MySshInfo "测试 $name (TCP $($h.host):$(if ($h.port) { $h.port } else { 22 })) ..."
    $port = if ($h.port) { [int]$h.port } else { 22 }
    try {
        $tcp = Test-NetConnection -ComputerName $h.host -Port $port -WarningAction SilentlyContinue
        if (-not $tcp.TcpTestSucceeded) {
            Write-MySshError "TCP 不通: $($h.host):$port"
            return
        }
        Write-MySshOk "TCP 可达: $($h.host):$port"
    }
    catch {
        Write-MySshWarn "TCP 检测跳过: $($_.Exception.Message)"
    }

    $hasKey = [bool]$h.key
    $hasPass = Test-MySshPasswordSaved -Alias $name
    $jumpPass = $false
    if ($h.jump) {
        $jumpPass = Test-MySshPasswordSaved -Alias ([string]$h.jump)
    }

    if (-not $hasKey -and -not $hasPass) {
        Write-MySshHint "  未配置私钥/密码，跳过自动登录探测。请用: myssh $name"
        Write-MySshHint "  或: myssh password $name"
        return
    }

    Write-MySshInfo "探测 SSH 登录 ..."
    $batch = $hasKey -and -not $hasPass -and -not $jumpPass
    $probeArgs = Get-MySshHostArgs -HostInfo $h -AllHosts $cfg.hosts -Batch:$batch
    $usedAskPass = $false
    if ($hasPass -or $jumpPass) {
        $usedAskPass = Enable-MySshAskPass -Alias $name -AllHosts $cfg.hosts
    }

    try {
        $allProbe = @($probeArgs) + @('exit')
        & $exe @allProbe 2>$null
        $code = $LASTEXITCODE
    }
    finally {
        if ($usedAskPass) { Disable-MySshAskPass }
    }

    if ($code -eq 0) {
        Write-MySshOk "SSH 登录正常: $name"
    }
    else {
        Write-MySshError "SSH 登录失败: $name (exit $code)"
        Write-MySshHint "  可用 myssh cmd $name 查看完整命令后手动排查。"
    }
}
