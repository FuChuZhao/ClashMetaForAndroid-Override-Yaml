[CmdletBinding()]
param(
    [string]$SourceDir = (Get-Location).Path,
    [string]$LogDir = (Join-Path -Path (Get-Location).Path -ChildPath 'logs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-LogFile {
    param([string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return Join-Path -Path $Directory -ChildPath ('probe-cmfa-build-env-{0}.log' -f $stamp)
}

function Write-Log {
    param(
        [string]$Path,
        [string]$Message
    )
    $line = '[{0}] {1}' -f (Get-Date -Format 's'), $Message
    $line | Add-Content -LiteralPath $Path -Encoding UTF8
    Write-Output $line
}

function Test-CommandAvailable {
    param([string]$Name)
    $cmd = Get-Command -Name $Name -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

$logPath = New-LogFile -Directory $LogDir
Write-Log -Path $logPath -Message 'Starting CMFA build environment probe.'
Write-Log -Path $logPath -Message ('SourceDir={0}' -f $SourceDir)

$required = @('git', 'gh')
foreach ($tool in $required) {
    if (Test-CommandAvailable -Name $tool) {
        $version = (& $tool --version 2>&1 | Select-Object -First 1)
        Write-Log -Path $logPath -Message ('OK {0}: {1}' -f $tool, $version)
    } else {
        Write-Log -Path $logPath -Message ('MISSING {0}' -f $tool)
    }
}

if (Test-CommandAvailable -Name 'gh') {
    try {
        $authStatus = & gh auth status 2>&1
        $authStatus | ForEach-Object { Write-Log -Path $logPath -Message ('gh auth: {0}' -f $_) }
    } catch {
        $_ | Out-String | Add-Content -LiteralPath $logPath -Encoding UTF8
        Write-Log -Path $logPath -Message 'gh auth status failed. Run gh auth login before repository setup.'
    }
}

$workflowPath = Join-Path -Path $SourceDir -ChildPath '.github/workflows/build-override-apk.yml'
if (Test-Path -LiteralPath $workflowPath) {
    Write-Log -Path $logPath -Message ('OK workflow: {0}' -f $workflowPath)
} else {
    Write-Log -Path $logPath -Message ('MISSING workflow: {0}' -f $workflowPath)
}

$gradlewPath = Join-Path -Path $SourceDir -ChildPath 'gradlew'
if (Test-Path -LiteralPath $gradlewPath) {
    Write-Log -Path $logPath -Message ('OK gradlew: {0}' -f $gradlewPath)
} else {
    Write-Log -Path $logPath -Message ('MISSING gradlew: {0}' -f $gradlewPath)
}

Write-Log -Path $logPath -Message ('Probe log written to {0}' -f $logPath)
