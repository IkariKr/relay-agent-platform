Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-DelegateCommandPath {
    param([Parameter(Mandatory = $true)][string]$CommandName)

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Required command '$CommandName' was not found on PATH."
    }

    if (
        $command.CommandType -eq "ExternalScript" -and
        [System.IO.Path]::GetExtension($command.Source).Equals(".ps1", [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        $scriptPath = $command.Source
        $basePath = Join-Path `
            ([System.IO.Path]::GetDirectoryName($scriptPath)) `
            ([System.IO.Path]::GetFileNameWithoutExtension($scriptPath))

        foreach ($candidate in @("$basePath.cmd", "$basePath.exe")) {
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    return $command.Source
}

function Stop-DelegateProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $taskkill = Get-Command taskkill.exe -ErrorAction SilentlyContinue
    if ($taskkill) {
        & $taskkill.Source /PID $ProcessId /T /F | Out-Host
        return
    }

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Id $ProcessId -Force
    }
}

function Join-DelegateProcessArguments {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $escaped = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') {
            '"' + ($argument -replace '"', '\"') + '"'
        }
        else {
            $argument
        }
    }

    return ($escaped -join " ")
}

function New-DelegateRunContext {
    param([Parameter(Mandatory = $true)][string]$BackendName)

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $runId = [System.Guid]::NewGuid().ToString("N").Substring(0, 12)
    $logRoot = Join-Path ([System.IO.Path]::GetTempPath()) $BackendName
    if (-not (Test-Path -LiteralPath $logRoot)) {
        New-Item -ItemType Directory -Path $logRoot | Out-Null
    }

    [pscustomobject]@{
        Timestamp = $timestamp
        RunId = $runId
        LogRoot = $logRoot
    }
}

function Invoke-DelegateAttempt {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$StdoutPath,
        [Parameter(Mandatory = $true)][string]$StderrPath,
        [Parameter(Mandatory = $true)][int]$Timeout,
        [Parameter(Mandatory = $true)][int]$IdleTimeout,
        [Parameter(Mandatory = $true)][int]$Poll,
        [Parameter(Mandatory = $true)][int]$StatusInterval
    )

    $startTime = Get-Date
    $lastActivityTime = $startTime
    $lastStatusTime = $startTime
    $lastStdoutLength = 0
    $lastStderrLength = 0
    $process = $null

    try {
        $argumentLine = Join-DelegateProcessArguments -Arguments $Arguments
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList $argumentLine `
            -WorkingDirectory (Get-Location).Path `
            -RedirectStandardOutput $StdoutPath `
            -RedirectStandardError $StderrPath `
            -NoNewWindow `
            -PassThru

        Write-Host "$Label PID: $($process.Id)"

        while (-not $process.HasExited) {
            $waitMilliseconds = [Math]::Min($Poll * 1000, 1000)
            [void]$process.WaitForExit($waitMilliseconds)

            $now = Get-Date
            $elapsedSeconds = [int]($now - $startTime).TotalSeconds
            $stdoutLength = if (Test-Path -LiteralPath $StdoutPath) { (Get-Item -LiteralPath $StdoutPath).Length } else { 0 }
            $stderrLength = if (Test-Path -LiteralPath $StderrPath) { (Get-Item -LiteralPath $StderrPath).Length } else { 0 }

            if ($stdoutLength -ne $lastStdoutLength -or $stderrLength -ne $lastStderrLength) {
                $lastActivityTime = $now
                $lastStdoutLength = $stdoutLength
                $lastStderrLength = $stderrLength
            }

            $idleSeconds = [int]($now - $lastActivityTime).TotalSeconds

            if (($now - $lastStatusTime).TotalSeconds -ge $StatusInterval) {
                Write-Host "$Label still running: elapsed=${elapsedSeconds}s idle=${idleSeconds}s pid=$($process.Id)"
                $lastStatusTime = $now
            }

            if ($Timeout -gt 0 -and $elapsedSeconds -ge $Timeout) {
                Write-Warning "$Label exceeded TimeoutSeconds=$Timeout. Killing process tree and returning exit code 124."
                Stop-DelegateProcessTree -ProcessId $process.Id
                return 124
            }

            if ($idleSeconds -ge $IdleTimeout) {
                Write-Warning "$Label produced no output for IdleTimeoutSeconds=$IdleTimeout. Killing process tree and returning exit code 125."
                Stop-DelegateProcessTree -ProcessId $process.Id
                return 125
            }
        }

        $process.WaitForExit()
        return $process.ExitCode
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-DelegateProcessTree -ProcessId $process.Id
        }
    }
}

function Write-DelegateLogs {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$StdoutPath,
        [Parameter(Mandatory = $true)][string]$StderrPath,
        [Parameter(Mandatory = $true)][int]$TailLines,
        [Parameter(Mandatory = $true)][bool]$FullLog
    )

    Write-Host ""
    if ($FullLog) {
        Write-Host "$Label stdout:"
    }
    else {
        Write-Host "$Label stdout tail ($TailLines lines):"
    }
    if (Test-Path -LiteralPath $StdoutPath) {
        if ($FullLog) {
            Get-Content -LiteralPath $StdoutPath
        }
        else {
            Get-Content -LiteralPath $StdoutPath -Tail $TailLines
        }
    }

    Write-Host ""
    if ($FullLog) {
        Write-Host "$Label stderr:"
    }
    else {
        Write-Host "$Label stderr tail ($TailLines lines):"
    }
    if (Test-Path -LiteralPath $StderrPath) {
        if ($FullLog) {
            Get-Content -LiteralPath $StderrPath
        }
        else {
            Get-Content -LiteralPath $StderrPath -Tail $TailLines
        }
    }
}

function Write-DelegatePostRunStatus {
    param([string]$Workdir = (Get-Location).Path)

    $gitPath = Get-Command git -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "Post-run git status:"
    if ($gitPath) {
        & $gitPath.Source -C $Workdir status --short
    }
    else {
        Write-Host "git not found on PATH."
    }
}

Export-ModuleMember -Function `
    Resolve-DelegateCommandPath, `
    Stop-DelegateProcessTree, `
    Join-DelegateProcessArguments, `
    New-DelegateRunContext, `
    Invoke-DelegateAttempt, `
    Write-DelegateLogs, `
    Write-DelegatePostRunStatus
