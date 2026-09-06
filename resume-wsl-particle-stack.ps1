#Requires -Version 5.1
<#
.SYNOPSIS
After the WSL installation and Windows restart, import AlmaLinux 9.6
and run install-particle-stack.sh as Linux root.
.NOTES
Run this as the Windows account that will use the distro.
This script does not enable Windows features, reboot, unregister a distro,
change the default distro, or create a Linux account.

The initial image is AlmaLinux 9.6. Normal AlmaLinux 9 package repositories
can advance its minor version; this script does not freeze package updates.
Official image: https://github.com/AlmaLinux/wsl-images/releases/tag/v9.6.20250522.0
WSL import: https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro
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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 initializes PSScriptRoot after -File parameter binding.
if (-not $PSBoundParameters.ContainsKey('StackScript')) {
    $StackScript = Join-Path $PSScriptRoot 'install-particle-stack.sh'
}
$InstallLocation = [IO.Path]::GetFullPath($InstallLocation)
$DownloadDirectory = [IO.Path]::GetFullPath($DownloadDirectory)
$ImageName = 'AlmaLinux-9.6_x64_20250522.0.wsl'
$ImageUrl = 'https://github.com/AlmaLinux/wsl-images/releases/download/v9.6.20250522.0/AlmaLinux-9.6_x64_20250522.0.wsl'
$ImagePath = Join-Path $DownloadDirectory $ImageName

if (-not $SkipStackInstall) {
    if (-not (Test-Path -LiteralPath $StackScript -PathType Leaf)) {
        throw "Installation script not found: $StackScript"
    }
    $StackScript = (Resolve-Path -LiteralPath $StackScript).ProviderPath
}

Write-Host 'Checking WSL. Windows must already have been restarted after enabling WSL.'
& wsl.exe --status
if ($LASTEXITCODE -ne 0) {
    throw 'WSL is not ready. Complete WSL installation and restart Windows, then run this script again.'
}
foreach ($DriveRoot in @([IO.Path]::GetPathRoot($InstallLocation), [IO.Path]::GetPathRoot($DownloadDirectory)) | Select-Object -Unique) {
    if (-not (Test-Path -LiteralPath $DriveRoot -PathType Container)) {
        throw "Drive $DriveRoot is unavailable. Choose an existing local drive with -InstallLocation and -DownloadDirectory. No distribution was imported."
    }
}

# Registration belongs to the current Windows user. Do not reuse a same-name
# distro at another location, or alter any existing distro registration.
$LxssPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
$ExistingDistro = @()
if (Test-Path -LiteralPath $LxssPath) {
    $ExistingDistro = @(
        Get-ChildItem -LiteralPath $LxssPath |
            ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath } |
            Where-Object { $_.DistributionName -eq $DistroName }
    )
}

if ($ExistingDistro.Count -gt 0) {
    $ExistingPath = ([string]$ExistingDistro[0].BasePath) -replace '^\\\\\?\\', ''
    if ($ExistingPath.TrimEnd('\') -ine $InstallLocation.TrimEnd('\')) {
        throw "An existing $DistroName is stored at $ExistingPath. It was left unchanged."
    }
    Write-Host "Reusing the existing $DistroName at $InstallLocation."
} else {
    if (Test-Path -LiteralPath $InstallLocation) {
        if (-not (Test-Path -LiteralPath $InstallLocation -PathType Container)) {
            throw "The installation location is already a file: $InstallLocation"
        }
        if (Get-ChildItem -LiteralPath $InstallLocation -Force | Select-Object -First 1) {
            throw "The unregistered installation directory is not empty: $InstallLocation. Its contents were left unchanged."
        }
    }

    New-Item -ItemType Directory -Path $DownloadDirectory -Force | Out-Null
    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
        $PartialPath = "$ImagePath.partial"
        Write-Host "Downloading the official AlmaLinux 9.6 x64 image to $ImagePath"
        # The final filename is created only after a complete HTTP download.
        # A failed download can be retried; the next attempt replaces .partial.
        $PreviousProtocol = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = $PreviousProtocol -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -Uri $ImageUrl -OutFile $PartialPath
            Move-Item -LiteralPath $PartialPath -Destination $ImagePath
        } finally {
            [Net.ServicePointManager]::SecurityProtocol = $PreviousProtocol
        }
    } else {
        Write-Host "Using the already downloaded image: $ImagePath"
    }

    New-Item -ItemType Directory -Path $InstallLocation -Force | Out-Null
    Write-Host "Importing $DistroName as WSL 2 at $InstallLocation."
    & wsl.exe --import $DistroName $InstallLocation $ImagePath --version 2
    if ($LASTEXITCODE -ne 0) {
        throw "WSL import failed (exit $LASTEXITCODE). Existing files and distro registrations were retained."
    }
}

# Perform a real Linux launch before attempting package installation.
$OsReleaseLines = @(& wsl.exe --distribution $DistroName --user root --exec cat /etc/os-release)
if ($LASTEXITCODE -ne 0) {
    throw 'The distro did not start successfully as AlmaLinux 9. Package installation was not started.'
}
$OsRelease = @{}
foreach ($OsReleaseLine in $OsReleaseLines) {
    if ($OsReleaseLine -match '^([A-Z_]+)=(.*)$') {
        $OsRelease[$Matches[1]] = $Matches[2].Trim('"')
    }
}
if ($OsRelease['ID'] -ne 'almalinux' -or $OsRelease['VERSION_ID'] -notmatch '^9(?:\.|$)') {
    throw 'The running distro is not AlmaLinux 9. Package installation was not started.'
}
Write-Host $OsRelease['PRETTY_NAME']

if (-not $SkipStackInstall) {
    $PreviousConsoleEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        $LinuxScriptOutput = @(& wsl.exe --distribution $DistroName --user root --exec wslpath -a -u $StackScript)
        if ($LASTEXITCODE -ne 0) {
            throw "Could not translate the Windows script path for WSL: $StackScript"
        }
        $LinuxScript = ($LinuxScriptOutput -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($LinuxScript)) {
            throw 'wslpath returned an empty path.'
        }
        Write-Host "Running the particle stack installer as Linux root: $LinuxScript"
        # WSL parses its option tokens before the Linux command. Leave simple
        # tokens unquoted; quote values containing spaces or embedded quotes.
        # Start-Process joins ArgumentList into one Windows command line.
        $InstallerArguments = @('--distribution', $DistroName, '--user', 'root', '--exec', 'bash', $LinuxScript)
        $InstallerCommandLine = ($InstallerArguments | ForEach-Object {
            if ($_ -and $_ -notmatch '[\s"]') {
                $_
            } else {
                '"' + (($_ -replace '(\\*)"', '${1}${1}\"') -replace '(\\+)$', '${1}${1}') + '"'
            }
        }) -join ' '
        $InstallerLog = Join-Path $PSScriptRoot 'particle-stack-linux.log'
        $InstallerErrorLog = Join-Path $PSScriptRoot 'particle-stack-linux.err.log'
        Write-Host "Linux installer output: $InstallerLog"
        Write-Host "Linux installer errors: $InstallerErrorLog"
        $InstallerProcess = Start-Process -FilePath 'wsl.exe' -ArgumentList $InstallerCommandLine -WindowStyle Hidden -RedirectStandardOutput $InstallerLog -RedirectStandardError $InstallerErrorLog -Wait -PassThru
        if ($InstallerProcess.ExitCode -ne 0) {
            throw "Particle stack installation failed (exit $($InstallerProcess.ExitCode)). See $InstallerLog and $InstallerErrorLog, then rerun this script to continue."
        }
    } finally {
        [Console]::OutputEncoding = $PreviousConsoleEncoding
    }
}

& wsl.exe --list --verbose
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read the final WSL distribution list.'
}
Write-Host ''
Write-Host "AlmaLinux is available at $InstallLocation. Initial administration uses Linux root."
Write-Host "Open it with: wsl -d $DistroName -u root"
if ($SkipStackInstall) {
    Write-Host 'Only the distro was prepared; the particle stack installer was skipped.'
} else {
    Write-Host "The particle stack installer exited successfully. See $InstallerLog and $InstallerErrorLog for its verification output."
}
