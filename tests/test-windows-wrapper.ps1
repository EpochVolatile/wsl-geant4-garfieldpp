# Exercises wrapper forwarding/status reporting with a stub, without WSL.
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepositoryDirectory = Split-Path $PSScriptRoot -Parent
$FixtureDirectory = Join-Path ([IO.Path]::GetTempPath()) ('particle-wrapper-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $FixtureDirectory
$FixtureWrapper = Join-Path $FixtureDirectory 'run-particle-stack-after-reboot.ps1'
$FixtureResume = Join-Path $FixtureDirectory 'resume-wsl-particle-stack.ps1'
Copy-Item -LiteralPath (Join-Path $RepositoryDirectory 'run-particle-stack-after-reboot.ps1') -Destination $FixtureWrapper
[IO.File]::WriteAllText($FixtureResume, @'
[CmdletBinding()]
param([string]$DistroName, [string]$InstallLocation, [string]$DownloadDirectory, [string]$StackScript, [switch]$SkipStackInstall)
$WrapperCase.Captured = $PSBoundParameters
if ($WrapperCase.Fail) { throw 'Simulated installer failure.' }
'@)

function Test-WrapperCase {
    param([string]$Name, [hashtable]$Parameters = @{}, [switch]$Fail)
    $WrapperCase = @{
        Fail = [bool]$Fail
        Captured = @{}
        Statuses = New-Object 'System.Collections.Generic.List[object]'
        TranscriptStarts = 0
        TranscriptStops = 0
    }
    function Start-Transcript { param([string]$Path, [switch]$Append); $WrapperCase.TranscriptStarts++ }
    function Stop-Transcript { $WrapperCase.TranscriptStops++ }
    function Set-Content {
        param([string]$LiteralPath, [string]$Encoding, [Parameter(ValueFromPipeline = $true)][string]$Value)
        process {
            if ((Split-Path $LiteralPath -Leaf) -ne 'deployment-status.json') { throw 'Unexpected status destination.' }
            $WrapperCase.Statuses.Add(($Value | ConvertFrom-Json))
        }
    }
    $Failure = ''
    try { & $FixtureWrapper @Parameters } catch { $Failure = $_.Exception.Message }
    if ($Fail -and $Failure -ne 'Simulated installer failure.') { throw "${Name}: installer failure was not propagated." }
    if (-not $Fail -and $Failure) { throw "${Name}: $Failure" }
    if ($WrapperCase.Captured.Count -ne $Parameters.Count) { throw "${Name}: unexpected forwarded parameter count." }
    foreach ($Key in $Parameters.Keys) {
        if ($WrapperCase.Captured[$Key] -ne $Parameters[$Key]) { throw "${Name}: parameter $Key was changed or lost." }
    }
    $FinalStatus = 'completed'
    if ($Fail) { $FinalStatus = 'failed' }
    if ($WrapperCase.Statuses.Count -ne 2 -or $WrapperCase.Statuses[0].Status -ne 'installing' -or $WrapperCase.Statuses[1].Status -ne $FinalStatus) {
        throw "${Name}: incorrect deployment status sequence."
    }
    if ($WrapperCase.TranscriptStarts -ne 1 -or $WrapperCase.TranscriptStops -ne 1) { throw "${Name}: transcript was not closed." }
    "PASS: $Name"
}

try {
    Test-WrapperCase 'Wrapper preserves continuation defaults'
    Test-WrapperCase 'Wrapper forwards all custom options' -Parameters @{
        DistroName = 'Particle-Lab'; InstallLocation = 'C:\WSL\Particle Lab'; DownloadDirectory = 'C:\WSL\Image Cache'
        StackScript = 'C:\Examples\custom install.sh'; SkipStackInstall = $true
    }
    Test-WrapperCase 'Wrapper records and propagates installer failure' -Fail
    $Tokens = $null
    $ParseErrors = $null
    $EnableAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RepositoryDirectory 'enable-wsl.ps1'), [ref]$Tokens, [ref]$ParseErrors)
    if ($ParseErrors.Count -or -not $EnableAst.ScriptRequirements.IsElevationRequired) { throw 'WSL enablement must parse and require administrator rights.' }
    'PASS: WSL enablement declares its administrator requirement'

    # A child launched with -File binds defaults differently from & script.ps1
    # on Windows PowerShell 5.1. Exercise that actual process startup mode.
    $TestPowerShell = (Get-Process -Id $PID).Path
    [IO.File]::WriteAllText($FixtureResume, @'
[CmdletBinding()]
param([switch]$SkipStackInstall)
if (-not $SkipStackInstall) { throw 'Expected the forwarded import-only switch.' }
'@)
    $FileModeOutput = @(& $TestPowerShell -NoProfile -ExecutionPolicy Bypass -File $FixtureWrapper -SkipStackInstall 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Wrapper -File startup failed: $($FileModeOutput -join [Environment]::NewLine)" }
    $FileModeStatus = Get-Content -LiteralPath (Join-Path $FixtureDirectory 'deployment-status.json') -Raw | ConvertFrom-Json
    if ($FileModeStatus.Status -ne 'completed') { throw 'Wrapper -File startup did not complete.' }
    'PASS: Wrapper starts through native PowerShell -File with default paths'

    # Use the continuation's real parameter/init code, stopping before its first
    # WSL command, so this regression check remains independent of WSL being installed.
    $ResumePath = Join-Path $RepositoryDirectory 'resume-wsl-particle-stack.ps1'
    $ResumeAst = [System.Management.Automation.Language.Parser]::ParseFile($ResumePath, [ref]$Tokens, [ref]$ParseErrors)
    $FirstWslCommand = $ResumeAst.Find({ param($Node)
        $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'wsl.exe'
    }, $true)
    if (-not $FirstWslCommand) { throw 'Could not find the boundary before the first WSL command.' }
    $ResumePrefix = [IO.File]::ReadAllText($ResumePath).Substring(0, $FirstWslCommand.Extent.StartOffset)
    $FixtureProbe = Join-Path $FixtureDirectory 'resume-file-mode-probe.ps1'
    [IO.File]::WriteAllText($FixtureProbe, $ResumePrefix + @'
if ($StackScript -ne (Join-Path $PSScriptRoot 'install-particle-stack.sh')) { throw 'Default installer path was not resolved beside the script.' }
'@)
    $FileModeOutput = @(& $TestPowerShell -NoProfile -ExecutionPolicy Bypass -File $FixtureProbe -SkipStackInstall 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Continuation -File default binding failed: $($FileModeOutput -join [Environment]::NewLine)" }
    'PASS: Continuation resolves its default installer path in native PowerShell -File mode'
} finally {
    # Remove only known fixture files created above, then the empty directory.
    foreach ($FixtureName in @('run-particle-stack-after-reboot.ps1', 'resume-wsl-particle-stack.ps1', 'resume-file-mode-probe.ps1', 'deployment-status.json', 'particle-stack-install.log')) {
        $FixturePath = Join-Path $FixtureDirectory $FixtureName
        if (Test-Path -LiteralPath $FixturePath) { Remove-Item -LiteralPath $FixturePath -Force }
    }
    Remove-Item -LiteralPath $FixtureDirectory
}
