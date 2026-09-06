# Exercises continuation behavior without touching WSL, D:, registry, or network.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$TargetScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'resume-wsl-particle-stack.ps1'

# Decode the captured process command line with Windows itself, so the test
# checks argument preservation rather than repeating the script's quoting.
if (-not ('WslTestCommandLine' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WslTestCommandLine {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CommandLineToArgvW(string commandLine, out int argc);
    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr memory);
    public static string[] Parse(string commandLine) {
        int argc;
        IntPtr memory = CommandLineToArgvW(commandLine, out argc);
        if (memory == IntPtr.Zero) { throw new InvalidOperationException("Command-line parsing failed."); }
        try {
            string[] result = new string[argc];
            for (int i = 0; i < argc; i++) {
                result[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(memory, i * IntPtr.Size));
            }
            return result;
        } finally { LocalFree(memory); }
    }
}
'@
}

function Test-ContinuationCase {
    param(
        [string]$Name,
        [string]$Scenario,
        [bool]$ExpectImport,
        [bool]$ExpectStack,
        [string]$ExpectedError = '',
        [switch]$SkipStackInstall,
        [hashtable]$Parameters = @{}
    )
    $CaseState = @{
        Scenario = $Scenario
        Calls = New-Object 'System.Collections.Generic.List[string]'
        Imports = 0
        StackRuns = 0
        Downloads = 0
        Changes = 0
        LinuxScript = '/mnt/c/example/particle stack ' + [char]0x4e2d + [char]0x6587 + '/install-particle-stack.sh'
        DistroName = 'AlmaLinux-9.6'
        InstallLocation = 'D:\WSL\AlmaLinux-9.6'
        DownloadDirectory = 'D:\WSL\Downloads'
    }
    foreach ($ParameterName in @('DistroName', 'InstallLocation', 'DownloadDirectory')) {
        if ($Parameters.ContainsKey($ParameterName)) { $CaseState[$ParameterName] = $Parameters[$ParameterName] }
    }
    if ($Scenario -eq 'reuse') {
        $CaseState.LinuxScript = '/mnt/c/quoted" and slash\"/example config/install-particle-stack.sh'
    }
    function Test-Path {
        param([string]$LiteralPath, [string]$PathType)
        if ($LiteralPath -match '^[A-Za-z]:\\$') { return $CaseState.Scenario -ne 'missingdrive' }
        if ($LiteralPath.EndsWith('install-particle-stack.sh')) { return $true }
        if ($LiteralPath.StartsWith('HKCU:')) {
            return $CaseState.Scenario -in @('reuse', 'conflict')
        }
        if ($LiteralPath -eq $CaseState.InstallLocation) {
            return $CaseState.Scenario -eq 'nonempty'
        }
        return $false
    }
    function Resolve-Path {
        param([string]$LiteralPath)
        return [pscustomobject]@{ ProviderPath = $LiteralPath }
    }
    function Get-ChildItem {
        param([string]$LiteralPath, [switch]$Force)
        if ($LiteralPath.StartsWith('HKCU:')) {
            return [pscustomobject]@{ PSPath = 'MockRegistryDistro' }
        }
        if ($CaseState.Scenario -eq 'nonempty') { return 'existing-user-data' }
    }
    function Get-ItemProperty {
        param([string]$LiteralPath)
        $BasePath = '\\?\' + $CaseState.InstallLocation
        if ($CaseState.Scenario -eq 'conflict') { $BasePath = 'C:\OtherExistingDistro' }
        return [pscustomobject]@{ DistributionName = $CaseState.DistroName; BasePath = $BasePath }
    }
    function New-Item {
        param([string]$ItemType, [string]$Path, [switch]$Force)
        $CaseState.Changes++
    }
    function Move-Item {
        param([string]$LiteralPath, [string]$Destination)
        $CaseState.Changes++
    }
    function Invoke-WebRequest {
        param([switch]$UseBasicParsing, [string]$Uri, [string]$OutFile)
        if (-not $Uri.StartsWith('https://github.com/AlmaLinux/wsl-images/releases/download/')) {
            throw 'Test encountered a nonofficial download URL.'
        }
        if ((Split-Path $OutFile -Parent) -ne $CaseState.DownloadDirectory) {
            throw 'Download did not use the requested cache directory.'
        }
        $CaseState.Downloads++
        $CaseState.Changes++
    }
    function wsl.exe {
        $WslArguments = @($args)
        $CaseState.Calls.Add(($WslArguments -join ' '))
        Set-Variable -Name LASTEXITCODE -Scope 1 -Value 0
        if ($WslArguments[0] -eq '--status' -and $CaseState.Scenario -eq 'notready') {
            Set-Variable -Name LASTEXITCODE -Scope 1 -Value 50
        } elseif ($WslArguments[0] -eq '--import') {
            $CaseState.Imports++
            if ($WslArguments[1] -ne $CaseState.DistroName -or $WslArguments[2] -ne $CaseState.InstallLocation -or $WslArguments[-1] -ne '2') {
                throw 'Test detected an unexpected import location or WSL version.'
            }
            if ($CaseState.Scenario -eq 'importfailure') {
                Set-Variable -Name LASTEXITCODE -Scope 1 -Value 1
            }
        } elseif ($WslArguments -contains 'cat') {
            if ($CaseState.Scenario -eq 'wronglinux') {
                return @('ID=ubuntu', 'VERSION_ID="24.04"', 'PRETTY_NAME="Ubuntu 24.04"')
            }
            return @('ID=almalinux', 'VERSION_ID="9.6"', 'PRETTY_NAME="AlmaLinux 9.6"')
        } elseif ($WslArguments -contains 'wslpath') {
            return $CaseState.LinuxScript
        } elseif ($WslArguments -contains 'bash' -and $WslArguments -notcontains '-lc') {
            throw 'Installer must use Start-Process with separate output logs.'
        }
    }
    function Start-Process {
        param(
            [string]$FilePath, [string[]]$ArgumentList, [string]$WindowStyle,
            [string]$RedirectStandardOutput, [string]$RedirectStandardError,
            [switch]$Wait, [switch]$PassThru
        )
        if ($FilePath -ne 'wsl.exe' -or $WindowStyle -ne 'Hidden' -or -not $Wait -or -not $PassThru) {
            throw 'Installer must wait for a hidden WSL process and retain its exit status.'
        }
        if (($ArgumentList -join ' ') -notmatch '^--distribution .+ --user root --exec bash ') {
            throw 'WSL option and command tokens must remain unquoted.'
        }
        $ExpectedLogDirectory = Split-Path $TargetScript -Parent
        if ($RedirectStandardOutput -ne (Join-Path $ExpectedLogDirectory 'particle-stack-linux.log') -or
            $RedirectStandardError -ne (Join-Path $ExpectedLogDirectory 'particle-stack-linux.err.log')) {
            throw 'Installer output must use separate workspace log files.'
        }
        $DecodedArguments = [WslTestCommandLine]::Parse('wsl.exe ' + ($ArgumentList -join ' '))
        $ExpectedArguments = @('wsl.exe', '--distribution', $CaseState.DistroName, '--user', 'root', '--exec', 'bash', $CaseState.LinuxScript)
        if ($DecodedArguments.Count -ne $ExpectedArguments.Count) {
            throw 'Installer command line changed the number of arguments.'
        }
        for ($ArgumentIndex = 0; $ArgumentIndex -lt $ExpectedArguments.Count; $ArgumentIndex++) {
            if ($DecodedArguments[$ArgumentIndex] -cne $ExpectedArguments[$ArgumentIndex]) {
                throw "Installer argument $ArgumentIndex did not survive Windows command-line parsing."
            }
        }
        $CaseState.Calls.Add(($DecodedArguments -join ' '))
        $CaseState.StackRuns++
        $InstallerExitCode = 0
        if ($CaseState.Scenario -eq 'stackfailure') { $InstallerExitCode = 23 }
        return [pscustomobject]@{ ExitCode = $InstallerExitCode }
    }
    function Write-Host { param([Parameter(ValueFromRemainingArguments = $true)]$Values) }

    $CaughtError = ''
    try {
        & $TargetScript -SkipStackInstall:$SkipStackInstall @Parameters
    } catch {
        $CaughtError = $_.Exception.Message
    }
    if ($ExpectedError) {
        if ($CaughtError -notlike "*$ExpectedError*") {
            throw "${Name}: expected error containing '$ExpectedError'; got '$CaughtError'."
        }
    } elseif ($CaughtError) {
        throw "${Name}: unexpected error: $CaughtError"
    }
    if ($CaseState.Imports -ne [int]$ExpectImport -or $CaseState.StackRuns -ne [int]$ExpectStack) {
        throw "${Name}: wrong import/stack count: $($CaseState.Imports)/$($CaseState.StackRuns)"
    }
    if ($Scenario -in @('reuse', 'conflict', 'nonempty', 'notready', 'missingdrive') -and $CaseState.Changes -ne 0) {
        throw "${Name}: unexpected host modification."
    }
    if ($CaseState.Calls -match '--unregister|--shutdown|--terminate|--set-default') {
        throw "${Name}: unexpected distro mutation command."
    }
    return "PASS: $Name"
}

Test-ContinuationCase 'WSL not ready stops before host changes' 'notready' $false $false 'WSL is not ready'
Test-ContinuationCase 'Fresh WSL 2 import to D and installer execution' 'fresh' $true $true
Test-ContinuationCase 'Existing distro resumes without redownload or import' 'reuse' $false $true
Test-ContinuationCase 'Conflicting existing distro remains untouched' 'conflict' $false $false 'left unchanged'
Test-ContinuationCase 'Unregistered nonempty directory remains untouched' 'nonempty' $false $false 'not empty'
Test-ContinuationCase 'Import failure stops before installer' 'importfailure' $true $false 'WSL import failed'
Test-ContinuationCase 'Unexpected Linux release stops before installer' 'wronglinux' $true $false 'not AlmaLinux 9'
Test-ContinuationCase 'Installer failure is surfaced' 'stackfailure' $true $true 'exit 23'
Test-ContinuationCase 'Import-only option skips installer' 'fresh' $true $false -SkipStackInstall
Test-ContinuationCase 'Custom distro and C-drive locations reach import and installer' 'fresh' $true $true -Parameters @{
    DistroName = 'Particle-Lab'; InstallLocation = 'C:\WSL\Particle Lab'; DownloadDirectory = 'C:\WSL\Image Cache'
}
Test-ContinuationCase 'Custom registered distro resumes in the requested directory' 'reuse' $false $true -Parameters @{
    DistroName = 'Particle-Lab'; InstallLocation = 'C:\WSL\Particle Lab'; DownloadDirectory = 'C:\WSL\Image Cache'
}
Test-ContinuationCase 'Unavailable drive reports parameters before host changes' 'missingdrive' $false $false 'Choose an existing local drive'
