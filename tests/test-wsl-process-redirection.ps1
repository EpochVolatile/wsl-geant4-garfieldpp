# Manual integration test: requires an existing WSL distro and creates only a
# temporary output probe plus two test logs. Never runs the particle installer.
#Requires -Version 5.1
[CmdletBinding()]
param([string]$DistroName = 'AlmaLinux-9.6')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$TargetScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'resume-wsl-particle-stack.ps1'
$UnicodeText = [string][char]0x4e2d + [char]0x6587
$ProbeDirectory = Join-Path ([IO.Path]::GetTempPath()) ('particle-wsl-probe-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $ProbeDirectory
$ProbeScript = Join-Path $ProbeDirectory "wsl log probe $UnicodeText.sh"
$ProbeBody = "#!/bin/bash`nprintf 'WSL_STDOUT $UnicodeText\n'`nprintf 'WSL_STDERR $UnicodeText\n' >&2`nprintf 'SCRIPT=%s\n' `"`$0`"`nexit 23`n"
[IO.File]::WriteAllText($ProbeScript, $ProbeBody, (New-Object Text.UTF8Encoding($false)))
$PreviousConsoleEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    $LinuxScript = ((& wsl.exe --distribution $DistroName --user root --exec wslpath -a -u $ProbeScript) -join "`n").Trim()
    if ($LASTEXITCODE -ne 0) { throw 'wslpath failed for the harmless probe.' }
    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($TargetScript, [ref]$Tokens, [ref]$ParseErrors)
    if ($ParseErrors.Count) { throw 'The continuation script did not parse.' }
    $QuoteAssignment = $Ast.Find({ param($Node)
        $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $Node.Left.Extent.Text -eq '$InstallerCommandLine'
    }, $true)
    $ProcessAssignment = $Ast.Find({ param($Node)
        $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $Node.Left.Extent.Text -eq '$InstallerProcess'
    }, $true)
    $InstallerArguments = @('--distribution', $DistroName, '--user', 'root', '--exec', 'bash', $LinuxScript)
    $InstallerCommandLine = & ([scriptblock]::Create($QuoteAssignment.Right.Extent.Text))
    $InstallerLog = Join-Path $PSScriptRoot 'wsl-output-probe.log'
    $InstallerErrorLog = Join-Path $PSScriptRoot 'wsl-error-probe.log'
    $InstallerProcess = & ([scriptblock]::Create($ProcessAssignment.Right.Extent.Text))
    $Stdout = Get-Content -LiteralPath $InstallerLog -Raw -Encoding UTF8
    $Stderr = Get-Content -LiteralPath $InstallerErrorLog -Raw -Encoding UTF8
    if ($InstallerProcess.ExitCode -ne 23) { throw "Expected exit 23; got $($InstallerProcess.ExitCode)." }
    if (-not $Stdout.Contains("WSL_STDOUT $UnicodeText") -or -not $Stdout.Contains("SCRIPT=$LinuxScript")) {
        throw "Unexpected stdout: $Stdout"
    }
    if (-not $Stderr.Contains("WSL_STDERR $UnicodeText")) { throw "Unexpected stderr: $Stderr" }
    'PASS: Real WSL process preserved the Unicode/spaced script path, wrote both logs, and returned exit 23.'
} finally {
    [Console]::OutputEncoding = $PreviousConsoleEncoding
    Remove-Item -LiteralPath $ProbeScript -Force
    Remove-Item -LiteralPath $ProbeDirectory
}
