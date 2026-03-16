<#
.SYNOPSIS
    gc-capture.ps1 - Enable or adjust GC logging on a running JVM process without restart.
.DESCRIPTION
    PowerShell equivalent of gc-capture.sh.
    Commands: enable, disable, status, snapshot
    Requires: jcmd (JDK 9+ for dynamic GC logging)
.PARAMETER Command
    The action to perform: enable, disable, status, snapshot
.PARAMETER PID
    The process ID of the target JVM
.PARAMETER OutputDir
    Directory for GC log files (default: .gc-exorcist\logs\)
.EXAMPLE
    .\scripts\gc-capture.ps1 enable 12345
    .\scripts\gc-capture.ps1 status 12345
    .\scripts\gc-capture.ps1 snapshot 12345
    .\scripts\gc-capture.ps1 disable 12345
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("enable", "disable", "status", "snapshot", "help")]
    [string]$Command,

    [Parameter(Position=1)]
    [string]$PID,

    [Parameter(Position=2)]
    [string]$OutputDir = ".gc-exorcist\logs"
)

# --- Helpers ---
function Write-Info  { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Green }
function Write-Warn  { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Err   { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Show-Usage {
    Write-Host "Usage: .\gc-capture.ps1 <command> <PID> [output-dir]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  enable  <PID> [output-dir]  Enable GC logging on running JVM (JDK 9+)"
    Write-Host "  disable <PID>               Disable GC logging"
    Write-Host "  status  <PID>               Check current GC logging configuration"
    Write-Host "  snapshot <PID>              Get current GC/heap info without enabling logging"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  output-dir   Directory for GC log files (default: .gc-exorcist\logs\)"
    exit 1
}

function Test-Jcmd {
    if (-not (Get-Command "jcmd" -ErrorAction SilentlyContinue)) {
        Write-Err "jcmd not found. Install a JDK (not just a JRE) and ensure it is on your PATH."
        exit 1
    }
}

function Test-JavaPID {
    param([string]$ProcessId)

    if ([string]::IsNullOrWhiteSpace($ProcessId)) {
        Write-Err "PID is required."
        Show-Usage
    }

    if ($ProcessId -notmatch '^\d+$') {
        Write-Err "Invalid PID: '$ProcessId' (must be a number)."
        exit 1
    }

    # Check process exists
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) {
        Write-Err "Process $ProcessId not found."
        exit 1
    }

    # Check it's a Java process via jcmd
    try {
        $result = & jcmd $ProcessId VM.version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "jcmd failed"
        }
    } catch {
        Write-Err "Process $ProcessId does not appear to be a Java process, or jcmd cannot attach to it."
        exit 1
    }
}

function Get-JdkMajorVersion {
    param([string]$ProcessId)

    $versionOutput = & jcmd $ProcessId VM.version 2>&1 | Out-String
    if ($versionOutput -match '(\d+)\.\d+\.\d+') {
        return [int]$Matches[1]
    }
    if ($versionOutput -match 'JDK (\d+)') {
        return [int]$Matches[1]
    }
    if ($versionOutput -match '1\.(\d+)') {
        $minor = [int]$Matches[1]
        if ($minor -le 8) { return $minor }
    }
    return 0
}

# --- Commands ---

function Invoke-Enable {
    param([string]$ProcessId, [string]$Dir)

    Test-Jcmd
    Test-JavaPID -ProcessId $ProcessId

    $jdkVersion = Get-JdkMajorVersion -ProcessId $ProcessId

    if ($jdkVersion -gt 0 -and $jdkVersion -le 8) {
        Write-Err "Dynamic GC logging is not supported on JDK 8 and earlier."
        Write-Host ""
        Write-Warn "For JDK 8, add these flags at JVM startup instead:"
        Write-Host "  -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCTimeStamps"
        Write-Host "  -XX:+PrintHeapAtGC -XX:+PrintTenuringDistribution"
        Write-Host "  -Xloggc:$Dir\gc.log"
        Write-Host "  -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=5 -XX:GCLogFileSize=20M"
        exit 1
    }

    if (-not (Test-Path $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $Dir "gc_${ProcessId}_${timestamp}.log"

    Write-Info "Enabling GC logging for PID $ProcessId"
    Write-Info "Output file: $logFile"

    $result = & jcmd $ProcessId VM.log output="$logFile" what=gc*=info decorators=time,uptime,level,tags 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host $result
        Write-Info "GC logging enabled successfully."
        Write-Info "Log file: $logFile"
        Write-Host ""
        Write-Host "Tip: Run '/gc-analyze' on the log file after collecting data." -ForegroundColor Cyan
        Write-Host "Tip: Run '.\gc-capture.ps1 disable $ProcessId' to stop logging." -ForegroundColor Cyan
    } else {
        Write-Err "Failed to enable GC logging."
        Write-Host $result
        exit 1
    }
}

function Invoke-Disable {
    param([string]$ProcessId)

    Test-Jcmd
    Test-JavaPID -ProcessId $ProcessId

    Write-Info "Disabling GC logging for PID $ProcessId"

    $result = & jcmd $ProcessId VM.log disable 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host $result
        Write-Info "GC logging disabled."
    } else {
        Write-Err "Failed to disable GC logging."
        Write-Host $result
        exit 1
    }
}

function Invoke-Status {
    param([string]$ProcessId)

    Test-Jcmd
    Test-JavaPID -ProcessId $ProcessId

    Write-Info "Current VM.log configuration for PID ${ProcessId}:"
    Write-Host ""
    & jcmd $ProcessId VM.log list 2>&1
}

function Invoke-Snapshot {
    param([string]$ProcessId)

    Test-Jcmd
    Test-JavaPID -ProcessId $ProcessId

    Write-Host "=== Heap Info (PID: $ProcessId) ===" -ForegroundColor Cyan
    try { & jcmd $ProcessId GC.heap_info 2>&1 } catch { Write-Warn "GC.heap_info not available for this JVM." }
    Write-Host ""

    Write-Host "=== VM Flags (PID: $ProcessId) ===" -ForegroundColor Cyan
    try { & jcmd $ProcessId VM.flags 2>&1 } catch { Write-Warn "VM.flags not available." }
    Write-Host ""

    Write-Host "=== GC-Related Flags ===" -ForegroundColor Cyan
    $flags = & jcmd $ProcessId VM.flags 2>&1 | Out-String
    $gcFlags = $flags -split "`n" | Where-Object { $_ -match '(GC|Heap|Region|RAM|NewSize|OldSize|Metaspace|Survivor)' }
    if ($gcFlags) {
        $gcFlags | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "  (none matched)"
    }
    Write-Host ""
}

# --- Main ---

switch ($Command) {
    "enable" {
        if ([string]::IsNullOrWhiteSpace($PID)) { Write-Err "PID is required for 'enable'."; Show-Usage }
        Invoke-Enable -ProcessId $PID -Dir $OutputDir
    }
    "disable" {
        if ([string]::IsNullOrWhiteSpace($PID)) { Write-Err "PID is required for 'disable'."; Show-Usage }
        Invoke-Disable -ProcessId $PID
    }
    "status" {
        if ([string]::IsNullOrWhiteSpace($PID)) { Write-Err "PID is required for 'status'."; Show-Usage }
        Invoke-Status -ProcessId $PID
    }
    "snapshot" {
        if ([string]::IsNullOrWhiteSpace($PID)) { Write-Err "PID is required for 'snapshot'."; Show-Usage }
        Invoke-Snapshot -ProcessId $PID
    }
    "help" {
        Show-Usage
    }
}
