# Config & state persistence under ~/.myssh

function Get-MySshVersion {
    '0.4.0'
}

function Get-MySshHome {
    if ($env:MYSSH_HOME -and -not [string]::IsNullOrWhiteSpace($env:MYSSH_HOME)) {
        return $env:MYSSH_HOME.Trim()
    }
    Join-Path $HOME '.myssh'
}

function Get-MySshConfigPath {
    Join-Path (Get-MySshHome) 'config.json'
}

function Initialize-MySshHome {
    $homeDir = Get-MySshHome
    if (-not (Test-Path -LiteralPath $homeDir)) {
        New-Item -ItemType Directory -Path $homeDir -Force | Out-Null
    }
}

function New-MySshConfigObject {
    [ordered]@{
        version = 1
        hosts   = [ordered]@{}
    }
}

function ConvertTo-MySshOrderedHashtable {
    param($InputObject)

    if ($null -eq $InputObject) {
        return [ordered]@{}
    }

    if ($InputObject -is [hashtable] -or $InputObject -is [System.Collections.Specialized.OrderedDictionary]) {
        return $InputObject
    }

    $result = [ordered]@{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $value = $prop.Value
        if ($value -is [System.Management.Automation.PSCustomObject]) {
            $result[$prop.Name] = ConvertTo-MySshOrderedHashtable $value
        }
        elseif ($value -is [System.Collections.IDictionary]) {
            $child = [ordered]@{}
            foreach ($key in $value.Keys) {
                $child[$key] = $value[$key]
            }
            $result[$prop.Name] = $child
        }
        else {
            $result[$prop.Name] = $value
        }
    }
    return $result
}

function Read-MySshConfig {
    Initialize-MySshHome
    $path = Get-MySshConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        $cfg = New-MySshConfigObject
        Save-MySshConfig -Config $cfg
        return $cfg
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return New-MySshConfigObject
        }
        $json = $raw | ConvertFrom-Json
        $cfg = ConvertTo-MySshOrderedHashtable $json

        if (-not $cfg.Contains('hosts') -or $null -eq $cfg.hosts) {
            $cfg.hosts = [ordered]@{}
        }
        else {
            $hosts = [ordered]@{}
            foreach ($key in @($cfg.hosts.Keys)) {
                $hosts[$key] = ConvertTo-MySshOrderedHashtable $cfg.hosts[$key]
            }
            $cfg.hosts = $hosts
        }

        # Drop legacy tunnels key if present (feature removed)
        if ($cfg.Contains('tunnels')) {
            $cfg.Remove('tunnels')
        }

        if (-not $cfg.Contains('version')) {
            $cfg.version = 1
        }

        return $cfg
    }
    catch {
        Write-MySshError "配置文件损坏: $path"
        Write-MySshHint "  可手动修复，或删除后重建: Remove-Item '$path'"
        throw
    }
}

function ConvertTo-MySshJsonObject {
    param($InputObject)

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $obj = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $obj[[string]$key] = ConvertTo-MySshJsonObject $InputObject[$key]
        }
        return [pscustomobject]$obj
    }
    return $InputObject
}

function Save-MySshConfig {
    param([Parameter(Mandatory)]$Config)

    Initialize-MySshHome
    $path = Get-MySshConfigPath
    $payload = ConvertTo-MySshJsonObject $Config
    $json = $payload | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Expand-MySshPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    $expanded = $Path.Trim()
    if ($expanded.StartsWith('~/') -or $expanded.StartsWith('~\') ) {
        $expanded = Join-Path $HOME $expanded.Substring(2)
    }
    elseif ($expanded -eq '~') {
        $expanded = $HOME
    }

    return [System.IO.Path]::GetFullPath($expanded)
}
