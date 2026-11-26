# Build ssh.exe argument lists from host definitions (incl. jump/ProxyCommand)

function Get-MySshExecutable {
    $cmd = Get-Command ssh -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    $fallback = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
    if (Test-Path -LiteralPath $fallback) {
        return $fallback
    }
    throw "未找到 ssh.exe。请安装 Windows OpenSSH 客户端。"
}

function Get-MySshHostArgs {
    param(
        [Parameter(Mandatory)]$HostInfo,
        [Parameter(Mandatory)][System.Collections.IDictionary]$AllHosts,
        [string[]]$ExtraArgs,
        [string[]]$RemoteCommand,
        [switch]$Batch
    )

    $args = [System.Collections.Generic.List[string]]::new()

    # Self-contained: ignore user ssh_config (avoids ACL/permission breakage on Windows)
    $args.Add('-F')
    $args.Add('NUL')

    if ($HostInfo.port) {
        $args.Add('-p')
        $args.Add([string]$HostInfo.port)
    }

    if ($HostInfo.key) {
        $keyPath = Expand-MySshPath $HostInfo.key
        $args.Add('-i')
        $args.Add($keyPath)
        $args.Add('-o')
        $args.Add('IdentitiesOnly=yes')
    }

    if ($HostInfo.jump) {
        $proxy = Get-MySshProxyCommand -Jump $HostInfo.jump -AllHosts $AllHosts
        if ($proxy) {
            $args.Add('-o')
            $args.Add("ProxyCommand=$proxy")
        }
    }

    if ($HostInfo.options) {
        foreach ($opt in @($HostInfo.options)) {
            if (-not [string]::IsNullOrWhiteSpace($opt)) {
                $args.Add('-o')
                $args.Add([string]$opt)
            }
        }
    }

    # Comfortable defaults for interactive Windows use
    $args.Add('-o')
    $args.Add('ServerAliveInterval=30')
    $args.Add('-o')
    $args.Add('ServerAliveCountMax=3')

    if ($Batch) {
        $args.Add('-o')
        $args.Add('BatchMode=yes')
        $args.Add('-o')
        $args.Add('ConnectTimeout=8')
    }

    if ($ExtraArgs) {
        foreach ($a in $ExtraArgs) {
            if (-not [string]::IsNullOrEmpty($a)) {
                $args.Add($a)
            }
        }
    }

    $destination = if ($HostInfo.user) {
        "$($HostInfo.user)@$($HostInfo.host)"
    }
    else {
        [string]$HostInfo.host
    }
    $args.Add($destination)

    # ssh [options] destination [command...]
    if ($RemoteCommand) {
        foreach ($a in $RemoteCommand) {
            if (-not [string]::IsNullOrEmpty($a)) {
                $args.Add($a)
            }
        }
    }

    return $args.ToArray()
}

function Resolve-MySshJumpSpec {
    param(
        [Parameter(Mandatory)][string]$Jump,
        [Parameter(Mandatory)][System.Collections.IDictionary]$AllHosts
    )

    if ($AllHosts.Contains($Jump)) {
        $j = $AllHosts[$Jump]
        $spec = if ($j.user) { "$($j.user)@$($j.host)" } else { [string]$j.host }
        if ($j.port -and [int]$j.port -ne 22) {
            $spec = "${spec}:$($j.port)"
        }
        return $spec
    }

    return $Jump
}

function Get-MySshProxyCommand {
    param(
        [Parameter(Mandatory)][string]$Jump,
        [Parameter(Mandatory)][System.Collections.IDictionary]$AllHosts
    )

    $exe = Get-MySshExecutable
    # Quote path for ProxyCommand if needed
    $exeQ = if ($exe -match '\s') { "`"$exe`"" } else { $exe }

    if ($AllHosts.Contains($Jump)) {
        $j = $AllHosts[$Jump]
        $parts = [System.Collections.Generic.List[string]]::new()
        $parts.Add($exeQ)
        $parts.Add('-F')
        $parts.Add('NUL')
        $parts.Add('-W')
        $parts.Add('%h:%p')
        if ($j.port) {
            $parts.Add('-p')
            $parts.Add([string]$j.port)
        }
        if ($j.key) {
            $keyPath = Expand-MySshPath $j.key
            $parts.Add('-i')
            $parts.Add("`"$keyPath`"")
            $parts.Add('-o')
            $parts.Add('IdentitiesOnly=yes')
        }
        $dest = if ($j.user) { "$($j.user)@$($j.host)" } else { [string]$j.host }
        $parts.Add($dest)
        return ($parts -join ' ')
    }

    # Raw jump: user@host:port or host:port or host
    $user = $null
    $hostPort = $Jump
    if ($Jump -match '^([^@]+)@(.+)$') {
        $user = $Matches[1]
        $hostPort = $Matches[2]
    }
    $jumpHost = $hostPort
    $jumpPort = $null
    if ($hostPort -match '^(.+):(\d+)$') {
        $jumpHost = $Matches[1]
        $jumpPort = $Matches[2]
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($exeQ)
    $parts.Add('-F')
    $parts.Add('NUL')
    $parts.Add('-W')
    $parts.Add('%h:%p')
    if ($jumpPort) {
        $parts.Add('-p')
        $parts.Add($jumpPort)
    }
    $dest = if ($user) { "$user@$jumpHost" } else { $jumpHost }
    $parts.Add($dest)
    return ($parts -join ' ')
}

function Format-MySshCommandLine {
    param(
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [string]$Executable = 'ssh'
    )

    $parts = foreach ($a in $ArgumentList) {
        if ($a -match '[\s"]') {
            '"' + ($a -replace '"', '\"') + '"'
        }
        else {
            $a
        }
    }
    return ($Executable + ' ' + ($parts -join ' '))
}

function Get-MySshArgumentListString {
    param([Parameter(Mandatory)][string[]]$ArgumentList)
    return ((Format-MySshCommandLine -ArgumentList $ArgumentList -Executable '').Trim())
}
