@{
    RootModule        = 'myssh.psm1'
    ModuleVersion     = '0.3.1'
    GUID              = 'a6e2c8f1-4b7d-4e9a-9c31-7f0d2b8e5a14'
    Author            = '超凡'
    Description       = 'Windows SSH connection and jump-host manager for personal use'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('myssh')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('ssh', 'jump', 'windows', 'cli')
        }
    }
}
