[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$Owner,

    [string]$RepoName = 'ClashMetaForAndroid-override-yaml',

    [ValidateSet('public', 'private', 'internal')]
    [string]$Visibility = 'private',

    [string]$SourceDir = (Get-Location).Path,

    [string]$Branch = 'main',

    [switch]$TriggerBuild,

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
    return Join-Path -Path $Directory -ChildPath ('publish-cmfa-override-fork-{0}.log' -f $stamp)
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

function Invoke-Logged {
    param(
        [string]$LogPath,
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory
    )
    Write-Log -Path $LogPath -Message ('RUN {0} {1}' -f $FilePath, ($ArgumentList -join ' '))
    Push-Location -LiteralPath $WorkingDirectory
    try {
        $output = & $FilePath @ArgumentList 2>&1
        $exit = $LASTEXITCODE
        $output | ForEach-Object { Write-Log -Path $LogPath -Message ('OUT {0}' -f $_) }
        if ($exit -ne 0) {
            throw ('Command failed with exit code {0}: {1}' -f $exit, $FilePath)
        }
    } finally {
        Pop-Location
    }
}

function Assert-Command {
    param([string]$Name)
    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw ('Required command not found on PATH: {0}' -f $Name)
    }
}

$logPath = New-LogFile -Directory $LogDir
Write-Log -Path $logPath -Message 'Starting repository publish workflow.'
Write-Log -Path $logPath -Message ('SourceDir={0}' -f $SourceDir)
Write-Log -Path $logPath -Message ('Target={0}/{1}' -f $Owner, $RepoName)

Assert-Command -Name 'git'
Assert-Command -Name 'gh'

try {
    & gh auth status 2>&1 | ForEach-Object { Write-Log -Path $logPath -Message ('gh auth: {0}' -f $_) }
} catch {
    $_ | Out-String | Add-Content -LiteralPath $logPath -Encoding UTF8
    throw 'GitHub CLI is not authenticated. Run gh auth login, then rerun this script.'
}

if (-not (Test-Path -LiteralPath (Join-Path -Path $SourceDir -ChildPath '.git'))) {
    Invoke-Logged -LogPath $logPath -FilePath 'git' -ArgumentList @('init') -WorkingDirectory $SourceDir
}

Push-Location -LiteralPath $SourceDir
try {
    Invoke-Logged -LogPath $logPath -FilePath 'git' -ArgumentList @('checkout', '-B', $Branch) -WorkingDirectory $SourceDir
    Invoke-Logged -LogPath $logPath -FilePath 'git' -ArgumentList @('add', '.') -WorkingDirectory $SourceDir

    $status = & git status --porcelain
    if ($status) {
        Invoke-Logged -LogPath $logPath -FilePath 'git' -ArgumentList @('commit', '-m', 'Add profile YAML override support') -WorkingDirectory $SourceDir
    } else {
        Write-Log -Path $logPath -Message 'No local changes to commit.'
    }

    $repoFullName = '{0}/{1}' -f $Owner, $RepoName
    $repoExists = $true
    & gh repo view $repoFullName *> $null
    if ($LASTEXITCODE -ne 0) {
        $repoExists = $false
    }

    if (-not $repoExists) {
        $createArgs = @('repo', 'create', $repoFullName, '--source', $SourceDir, '--remote', 'origin', '--push')
        if ($Visibility -eq 'public') { $createArgs += '--public' }
        elseif ($Visibility -eq 'internal') { $createArgs += '--internal' }
        else { $createArgs += '--private' }
        if ($PSCmdlet.ShouldProcess($repoFullName, 'Create GitHub repository and push source')) {
            Invoke-Logged -LogPath $logPath -FilePath 'gh' -ArgumentList $createArgs -WorkingDirectory $SourceDir
        }
    } else {
        $remoteUrl = 'https://github.com/{0}.git' -f $repoFullName
        $remoteNames = & git remote
        if ($remoteNames -contains 'origin') {
            Invoke-Logged -LogPath $logPath -FilePath 'git' -ArgumentList @('remote', 'set-url', 'origin', $remoteUrl) -WorkingDirectory $SourceDir
        } else {
            Invoke-Logged -LogPath $logPath -FilePath 'git' -ArgumentList @('remote', 'add', 'origin', $remoteUrl) -WorkingDirectory $SourceDir
        }
        if ($PSCmdlet.ShouldProcess($repoFullName, 'Push source')) {
            Invoke-Logged -LogPath $logPath -FilePath 'git' -ArgumentList @('push', '-u', 'origin', $Branch) -WorkingDirectory $SourceDir
        }
    }

    if ($TriggerBuild) {
        if ($PSCmdlet.ShouldProcess($repoFullName, 'Trigger build workflow')) {
            Invoke-Logged -LogPath $logPath -FilePath 'gh' -ArgumentList @('workflow', 'run', 'build-override-apk.yml', '--repo', $repoFullName, '--ref', $Branch) -WorkingDirectory $SourceDir
        }
    }
} catch {
    $_ | Out-String | Add-Content -LiteralPath $logPath -Encoding UTF8
    throw
} finally {
    Pop-Location
    Write-Log -Path $logPath -Message ('Publish log written to {0}' -f $logPath)
}
