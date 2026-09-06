#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
Install WSL without a Linux distribution from an elevated PowerShell window.
.NOTES
Open PowerShell with Run as administrator, then run this script.
The script does not restart Windows. Save your work and restart manually
before running run-particle-stack-after-reboot.ps1 as your usual account.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$taskLog = Join-Path $PSScriptRoot 'enable-wsl.log'
$taskStatusFile = Join-Path $PSScriptRoot 'enable-wsl-status.json'
Start-Transcript -Path $taskLog -Force
try {
    Write-Output 'Installing stable WSL, without a default distribution.'
    & "$env:WINDIR\System32\wsl.exe" --install --no-distribution --web-download
    $taskInstallExit = $LASTEXITCODE
    if ($taskInstallExit -notin @(0, 3010, 1641)) { throw "WSL install returned $taskInstallExit" }
    $taskFeatures = @('VirtualMachinePlatform', 'Microsoft-Windows-Subsystem-Linux') | ForEach-Object {
        $taskFeature = Get-WindowsOptionalFeature -Online -FeatureName $_
        [pscustomobject]@{ Name = $taskFeature.FeatureName; State = [string]$taskFeature.State }
    }
    [pscustomobject]@{
        ExitCode = $taskInstallExit
        Features = $taskFeatures
        FinishedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $taskStatusFile -Encoding utf8
    Write-Output 'WSL installation completed. Save your work and restart Windows manually before continuing.'
} catch {
    [pscustomobject]@{ Error = $_.Exception.Message; FinishedAt = (Get-Date).ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath $taskStatusFile -Encoding utf8
    throw
} finally { Stop-Transcript }
