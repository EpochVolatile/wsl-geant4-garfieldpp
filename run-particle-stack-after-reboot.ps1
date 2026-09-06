#Requires -Version 5.1
<#
.SYNOPSIS
Run the WSL continuation with a transcript and deployment status file.
.NOTES
Run manually after restarting Windows, as the account that will own the distro.
Parameters are forwarded to resume-wsl-particle-stack.ps1. The default Linux
installer is install-particle-stack.sh beside these PowerShell scripts.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$DistroName = 'AlmaLinux-9.6',
    [ValidatePattern('^[A-Za-z]:[\\/]')]
    [string]$InstallLocation = 'D:\WSL\AlmaLinux-9.6',
    [ValidatePattern('^[A-Za-z]:[\\/]')]
    [string]$DownloadDirectory = 'D:\WSL\Downloads',
    [string]$StackScript,
    [switch]$SkipStackInstall
)

$ErrorActionPreference = 'Stop'
$taskStatusPath = Join-Path $PSScriptRoot 'deployment-status.json'
$taskLogPath = Join-Path $PSScriptRoot 'particle-stack-install.log'
Start-Transcript -Path $taskLogPath -Append
try {
    [pscustomobject]@{ Status = 'installing'; StartedAt = (Get-Date).ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath $taskStatusPath -Encoding utf8
    & (Join-Path $PSScriptRoot 'resume-wsl-particle-stack.ps1') @PSBoundParameters
    [pscustomobject]@{ Status = 'completed'; FinishedAt = (Get-Date).ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath $taskStatusPath -Encoding utf8
} catch {
    [pscustomobject]@{
        Status = 'failed'
        Error = $_.Exception.Message
        FinishedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $taskStatusPath -Encoding utf8
    throw
} finally { Stop-Transcript }
