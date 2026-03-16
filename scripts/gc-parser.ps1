<#
.SYNOPSIS
    gc-parser.ps1 - Core GC log parser for gc-exorcist (PowerShell edition)
.DESCRIPTION
    Parses JVM GC log files (unified JDK 9+ or legacy JDK <=8 format) and produces
    a structured analysis report. PowerShell equivalent of gc-parser.sh.
.PARAMETER GCLog
    Path to the GC log file to parse
.PARAMETER Format
    Format detection mode: auto (default), unified (JDK 9+), legacy (JDK <=8)
.EXAMPLE
    .\scripts\gc-parser.ps1 gc.log
    .\scripts\gc-parser.ps1 gc.log -Format unified
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$GCLog,

    [Parameter()]
    [ValidateSet("auto", "unified", "legacy")]
    [string]$Format = "auto"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Validate input ---
if (-not (Test-Path $GCLog)) {
    Write-Error "Error: file not found: $GCLog"
    exit 1
}

$fileInfo = Get-Item $GCLog
if ($fileInfo.Length -eq 0) {
    Write-Error "Error: file is empty: $GCLog"
    exit 1
}

$logContent = Get-Content $GCLog -Raw
$logLines = Get-Content $GCLog

# --- Format Detection ---
function Detect-Format {
    $unifiedCount = ($logLines | Where-Object { $_ -match '^\[[0-9]+\.[0-9]+s\]\[' }).Count
    $legacyCount = ($logLines | Where-Object { $_ -match '(^[0-9]{4}-[0-9]{2}-[0-9]{2}T.*\[GC|^[0-9]+\.[0-9]+:.*\[GC)' }).Count

    if ($unifiedCount -gt 0 -and $legacyCount -gt 0) {
        Write-Error "Error: mixed GC log formats detected (unified: $unifiedCount lines, legacy: $legacyCount lines)"
        exit 1
    } elseif ($unifiedCount -gt 0) {
        return "unified"
    } elseif ($legacyCount -gt 0) {
        return "legacy"
    } else {
        Write-Error "Error: unrecognized GC log format"
        exit 1
    }
}

if ($Format -eq "auto") {
    $Format = Detect-Format
}

# --- Detect GC Algorithm ---
function Detect-Algorithm {
    if ($logContent -match '(Using G1|G1 Evacuation Pause|G1 Compaction)') { return "G1" }
    if ($logContent -match '(Using ZGC|Z Garbage Collector)') { return "ZGC" }
    if ($logContent -match '(Using Shenandoah|Shenandoah)') { return "Shenandoah" }
    if ($logContent -match '(Using Parallel|PSYoungGen|ParOldGen)') { return "Parallel" }
    if ($logContent -match '(Using Serial|DefNew|Tenured)') { return "Serial" }
    if ($logContent -match '(Using CMS|ConcurrentMarkSweep|ParNew)') { return "CMS" }
    return "Unknown"
}

$GCAlgorithm = Detect-Algorithm

# =====================================================================
# SHARED STATISTICS FUNCTIONS
# =====================================================================

function Get-Percentile {
    param([double[]]$Values, [int]$P)

    if ($Values.Count -eq 0) { return 0 }
    $sorted = $Values | Sort-Object
    $idx = [Math]::Max(1, [Math]::Min($sorted.Count, [int]([Math]::Round($P / 100.0 * $sorted.Count + 0.5))))
    return $sorted[$idx - 1]
}

function Write-StatsLine {
    param([string]$Label, [double[]]$Durations)

    $count = $Durations.Count
    if ($count -eq 0) { return }

    $sorted = $Durations | Sort-Object
    $min = $sorted[0]
    $max = $sorted[-1]
    $avg = ($sorted | Measure-Object -Average).Average
    $p50 = Get-Percentile -Values $Durations -P 50
    $p95 = Get-Percentile -Values $Durations -P 95
    $p99 = Get-Percentile -Values $Durations -P 99

    "  {0,-14} {1,6}  {2,10:F3}  {3,10:F3}  {4,10:F3}  {5,10:F3}  {6,10:F3}  {7,10:F3}" -f $Label, $count, $min, $avg, $p50, $p95, $p99, $max
}

function Write-PauseStats {
    param([array]$Events)

    Write-Output "=== PAUSE TIME SUMMARY ==="

    if ($Events.Count -eq 0) {
        Write-Output "(no pause events found)"
        Write-Output ""
        Write-Output "=== PAUSE TIME DISTRIBUTION ==="
        Write-Output "(no data)"
        Write-Output ""
        return
    }

    "  {0,-14} {1,6}  {2,10}  {3,10}  {4,10}  {5,10}  {6,10}  {7,10}" -f "Type", "Count", "Min(ms)", "Avg(ms)", "P50(ms)", "P95(ms)", "P99(ms)", "Max(ms)"
    "  {0,-14} {1,6}  {2,10}  {3,10}  {4,10}  {5,10}  {6,10}  {7,10}" -f "--------------", "------", "----------", "----------", "----------", "----------", "----------", "----------"

    $types = @("Young", "Mixed", "Full", "Remark", "Cleanup")
    foreach ($type in $types) {
        $durs = @($Events | Where-Object { $_.Type -eq $type } | ForEach-Object { $_.DurationMs })
        if ($durs.Count -gt 0) {
            Write-StatsLine -Label $type -Durations $durs
        }
    }

    $allDurs = @($Events | ForEach-Object { $_.DurationMs })
    if ($allDurs.Count -gt 0) {
        Write-StatsLine -Label "Total STW" -Durations $allDurs
    }
    Write-Output ""

    # Pause time distribution
    Write-Output "=== PAUSE TIME DISTRIBUTION ==="
    $b1 = @($allDurs | Where-Object { $_ -lt 10 }).Count
    $b2 = @($allDurs | Where-Object { $_ -ge 10 -and $_ -lt 20 }).Count
    $b3 = @($allDurs | Where-Object { $_ -ge 20 -and $_ -lt 50 }).Count
    $b4 = @($allDurs | Where-Object { $_ -ge 50 -and $_ -lt 100 }).Count
    $b5 = @($allDurs | Where-Object { $_ -ge 100 -and $_ -lt 500 }).Count
    $b6 = @($allDurs | Where-Object { $_ -ge 500 }).Count
    $total = $allDurs.Count

    $labels = @("< 10ms", "10-20ms", "20-50ms", "50-100ms", "100-500ms", "> 500ms")
    $counts = @($b1, $b2, $b3, $b4, $b5, $b6)
    $maxCount = ($counts | Measure-Object -Maximum).Maximum
    if ($maxCount -eq 0) { $maxCount = 1 }
    $barWidth = 40

    for ($i = 0; $i -lt 6; $i++) {
        $barLen = [Math]::Round($counts[$i] / $maxCount * $barWidth)
        $bar = "#" * $barLen
        $bar = $bar.PadRight($barWidth)
        $pct = if ($total -gt 0) { $counts[$i] / $total * 100 } else { 0 }
        "  {0,-12} |{1}| {2,5} ({3,5:F1}%)" -f $labels[$i], $bar, $counts[$i], $pct
    }
    Write-Output ""
}

function Write-HeapUtilization {
    param([array]$Events)

    Write-Output "=== HEAP UTILIZATION ==="

    $heapEvents = @($Events | Where-Object { $_.HeapBefore -ne "" -and $_.HeapAfter -ne "" })
    if ($heapEvents.Count -eq 0) {
        Write-Output "(no heap data found)"
        Write-Output ""
        return
    }

    $n = $heapEvents.Count
    $sumBefore = ($heapEvents | ForEach-Object { [double]$_.HeapBefore } | Measure-Object -Sum).Sum
    $sumAfter = ($heapEvents | ForEach-Object { [double]$_.HeapAfter } | Measure-Object -Sum).Sum
    $maxBefore = ($heapEvents | ForEach-Object { [double]$_.HeapBefore } | Measure-Object -Maximum).Maximum
    $maxAfter = ($heapEvents | ForEach-Object { [double]$_.HeapAfter } | Measure-Object -Maximum).Maximum

    "  events_with_heap_data: $n"
    "  heap_before_gc_avg:    {0:F1} MB" -f ($sumBefore / $n)
    "  heap_before_gc_max:    {0:F1} MB" -f $maxBefore
    "  heap_after_gc_avg:     {0:F1} MB" -f ($sumAfter / $n)
    "  heap_after_gc_max:     {0:F1} MB" -f $maxAfter

    $lastCap = $heapEvents[-1].HeapTotal
    if ($lastCap -ne "" -and [double]$lastCap -gt 0) {
        "  heap_capacity:         {0:F1} MB" -f ([double]$lastCap)
    }

    # Detect upward drift
    if ($n -ge 4) {
        $quarter = [Math]::Floor($n / 4)
        if ($quarter -ge 1) {
            $firstQAvg = ($heapEvents[0..($quarter-1)] | ForEach-Object { [double]$_.HeapAfter } | Measure-Object -Average).Average
            $lastQAvg = ($heapEvents[($n-$quarter)..($n-1)] | ForEach-Object { [double]$_.HeapAfter } | Measure-Object -Average).Average
            if ($lastQAvg -gt $firstQAvg * 1.2) {
                "  ** DRIFT DETECTED: after-GC occupancy trending up ({0:F1} MB -> {1:F1} MB avg)" -f $firstQAvg, $lastQAvg
                "     This may indicate a memory leak."
            }
        }
    }
    Write-Output ""
}

function Write-Rates {
    param([array]$Events)

    Write-Output "=== ALLOCATION RATE ==="

    $numericEvents = @($Events | Where-Object { $_.Timestamp -match '^[0-9]+\.[0-9]+$' -and $_.HeapBefore -ne "" -and $_.HeapAfter -ne "" })

    if ($numericEvents.Count -lt 2) {
        Write-Output "  (insufficient data)"
        Write-Output ""
        Write-Output "=== PROMOTION RATE ==="
        Write-Output "  (insufficient data or no promotion observed)"
        Write-Output ""
        return
    }

    $rates = @()
    for ($i = 1; $i -lt $numericEvents.Count; $i++) {
        $dt = [double]$numericEvents[$i].Timestamp - [double]$numericEvents[$i-1].Timestamp
        $alloc = [double]$numericEvents[$i].HeapBefore - [double]$numericEvents[$i-1].HeapAfter
        if ($alloc -gt 0 -and $dt -gt 0) {
            $rates += ($alloc / $dt)
        }
    }

    if ($rates.Count -gt 0) {
        $avgRate = ($rates | Measure-Object -Average).Average
        $maxRate = ($rates | Measure-Object -Maximum).Maximum
        $minRate = ($rates | Measure-Object -Minimum).Minimum
        "  samples:  $($rates.Count)"
        "  avg:      {0:F1} MB/s" -f $avgRate
        "  max:      {0:F1} MB/s" -f $maxRate
        "  min:      {0:F1} MB/s" -f $minRate
    } else {
        Write-Output "  (insufficient data)"
    }
    Write-Output ""

    Write-Output "=== PROMOTION RATE ==="
    $youngEvents = @($numericEvents | Where-Object { $_.Type -eq "Young" })
    $promoRates = @()
    for ($i = 1; $i -lt $youngEvents.Count; $i++) {
        $dt = [double]$youngEvents[$i].Timestamp - [double]$youngEvents[$i-1].Timestamp
        $promo = [double]$youngEvents[$i].HeapAfter - [double]$youngEvents[$i-1].HeapAfter
        if ($promo -gt 0 -and $dt -gt 0) {
            $promoRates += ($promo / $dt)
        }
    }

    if ($promoRates.Count -gt 0) {
        $avgRate = ($promoRates | Measure-Object -Average).Average
        $maxRate = ($promoRates | Measure-Object -Maximum).Maximum
        "  samples:  $($promoRates.Count)"
        "  avg:      {0:F1} MB/s" -f $avgRate
        "  max:      {0:F1} MB/s" -f $maxRate
    } else {
        Write-Output "  (insufficient data or no promotion observed)"
    }
    Write-Output ""
}

function Write-Overhead {
    param([array]$Events, [double]$DurationS)

    Write-Output "=== GC OVERHEAD ==="

    $totalStwMs = 0
    if ($Events.Count -gt 0) {
        $totalStwMs = ($Events | ForEach-Object { $_.DurationMs } | Measure-Object -Sum).Sum
    }

    if ($DurationS -gt 0) {
        $overhead = ($totalStwMs / 1000) / $DurationS * 100
        "  total_stw_time: {0:F3}ms" -f $totalStwMs
        "  total_runtime:  {0:F3}s" -f $DurationS
        "  gc_overhead:    {0:F3}%" -f $overhead
    } else {
        "  total_stw_time: {0:F3}ms" -f $totalStwMs
        Write-Output "  gc_overhead:    (cannot compute - zero duration)"
    }
    Write-Output ""
}

function Write-FullGCEvents {
    param([array]$Events)

    Write-Output "=== FULL GC EVENTS ==="

    $fullEvents = @($Events | Where-Object { $_.Type -eq "Full" })
    if ($fullEvents.Count -eq 0) {
        Write-Output "  (none)"
        Write-Output ""
        return
    }

    "  {0,-14}  {1,-30}  {2,10}  {3,10}  {4,12}" -f "Timestamp", "Cause", "Before(MB)", "After(MB)", "Duration(ms)"
    "  {0,-14}  {1,-30}  {2,10}  {3,10}  {4,12}" -f "--------------", "------------------------------", "----------", "----------", "------------"
    foreach ($evt in $fullEvents) {
        "  {0,-14}  {1,-30}  {2,10}  {3,10}  {4,12:F3}" -f $evt.Timestamp, $evt.Cause, $evt.HeapBefore, $evt.HeapAfter, $evt.DurationMs
    }
    Write-Output ""
}

function Write-Humongous {
    Write-Output "=== HUMONGOUS ALLOCATIONS ==="
    if ($GCAlgorithm -eq "G1") {
        $hLines = @($logLines | Where-Object { $_ -match '(gc,humongous|humongous object|Humongous)' })
        "  humongous_log_lines: $($hLines.Count)"
        if ($hLines.Count -gt 0) {
            Write-Output "  (showing up to 5 examples):"
            $hLines | Select-Object -First 5 | ForEach-Object { "    $_" }
        }
    } else {
        Write-Output "  (only applicable to G1 GC)"
    }
    Write-Output ""
}

function Write-Safepoints {
    Write-Output "=== SAFEPOINT SUMMARY ==="
    $spLines = @($logLines | Where-Object { $_ -match 'safepoint' })
    if ($spLines.Count -gt 0) {
        "  safepoint_entries: $($spLines.Count)"
        $spLines | Select-Object -First 5 | ForEach-Object { "    $_" }
    } else {
        Write-Output "  (no safepoint data found)"
    }
    Write-Output ""
}

function Write-Anomalies {
    param([array]$Events)

    Write-Output "=== ANOMALIES DETECTED ==="
    $foundAnomaly = $false

    # Evacuation failures
    $evacFail = @($logLines | Where-Object { $_ -match '(Evacuation Failure|To-space exhausted|to-space overflow)' }).Count
    if ($evacFail -gt 0) {
        "  [!] Evacuation failures detected: $evacFail occurrences"
        $foundAnomaly = $true
    }

    # Promotion failed
    $promoFail = @($logLines | Where-Object { $_ -match 'promotion failed' }).Count
    if ($promoFail -gt 0) {
        "  [!] Promotion failures detected: $promoFail occurrences"
        $foundAnomaly = $true
    }

    # Concurrent mode failure
    $cmf = @($logLines | Where-Object { $_ -match 'concurrent mode failure' }).Count
    if ($cmf -gt 0) {
        "  [!] CMS concurrent mode failures: $cmf occurrences"
        $foundAnomaly = $true
    }

    # High allocation rate spikes
    $numericEvents = @($Events | Where-Object { $_.Timestamp -match '^[0-9]+\.[0-9]+$' -and $_.HeapBefore -ne "" })
    if ($numericEvents.Count -ge 3) {
        $rates = @()
        for ($i = 1; $i -lt $numericEvents.Count; $i++) {
            $dt = [double]$numericEvents[$i].Timestamp - [double]$numericEvents[$i-1].Timestamp
            $alloc = [double]$numericEvents[$i].HeapBefore - [double]$numericEvents[$i-1].HeapAfter
            if ($alloc -gt 0 -and $dt -gt 0) {
                $rates += ($alloc / $dt)
            }
        }
        if ($rates.Count -ge 2) {
            $avgRate = ($rates | Measure-Object -Average).Average
            $spikes = @($rates | Where-Object { $_ -gt $avgRate * 3 }).Count
            if ($spikes -gt 0) {
                "  [!] High allocation rate spikes: $spikes events exceeded 3x average rate ({0:F1} MB/s)" -f $avgRate
                $foundAnomaly = $true
            }
        }
    }

    # Multiple Full GCs
    $fullCount = @($Events | Where-Object { $_.Type -eq "Full" }).Count
    if ($fullCount -gt 2) {
        "  [!] Multiple Full GC events ($fullCount) detected - may indicate promotion pressure"
        $foundAnomaly = $true
    }

    # Upward occupancy drift
    $heapEvents = @($Events | Where-Object { $_.HeapAfter -ne "" })
    $n = $heapEvents.Count
    if ($n -ge 4) {
        $quarter = [Math]::Floor($n / 4)
        if ($quarter -ge 1) {
            $firstQAvg = ($heapEvents[0..($quarter-1)] | ForEach-Object { [double]$_.HeapAfter } | Measure-Object -Average).Average
            $lastQAvg = ($heapEvents[($n-$quarter)..($n-1)] | ForEach-Object { [double]$_.HeapAfter } | Measure-Object -Average).Average
            if ($lastQAvg -gt $firstQAvg * 1.2) {
                "  [!] Upward occupancy drift: after-GC heap trending up ({0:F1} -> {1:F1} MB avg)" -f $firstQAvg, $lastQAvg
                "       Possible memory leak."
                $foundAnomaly = $true
            }
        }
    }

    if (-not $foundAnomaly) {
        Write-Output "  (none detected)"
    }
    Write-Output ""
}

# =====================================================================
# UNIFIED FORMAT PARSING (JDK 9+)
# =====================================================================

function Parse-Unified {
    # Extract timestamps
    $tsMatches = [regex]::Matches($logContent, '\[([0-9]+\.[0-9]+)s\]')
    $firstTs = 0.0
    $lastTs = 0.0
    if ($tsMatches.Count -gt 0) {
        $firstTs = [double]$tsMatches[0].Groups[1].Value
        $lastTs = [double]$tsMatches[$tsMatches.Count - 1].Groups[1].Value
    }
    $durationS = $lastTs - $firstTs

    # Extract pause lines
    $pauseLines = @($logLines | Where-Object { $_ -match 'Pause (Young|Full|Remark|Cleanup)' })
    $totalGCEvents = $pauseLines.Count
    $totalFullGCEvents = @($pauseLines | Where-Object { $_ -match 'Pause Full' }).Count

    # Parse each pause line
    $events = @()
    foreach ($line in $pauseLines) {
        $evt = @{
            Timestamp = ""
            Type = ""
            Cause = ""
            HeapBefore = ""
            HeapAfter = ""
            HeapTotal = ""
            DurationMs = 0.0
        }

        # Timestamp
        if ($line -match '\[([0-9]+\.[0-9]+)s\]') {
            $evt.Timestamp = $Matches[1]
        }

        # Pause type
        if ($line -match 'Pause Full') { $evt.Type = "Full" }
        elseif ($line -match 'Pause Remark') { $evt.Type = "Remark" }
        elseif ($line -match 'Pause Cleanup') { $evt.Type = "Cleanup" }
        elseif ($line -match 'Pause Young.*Mixed') { $evt.Type = "Mixed" }
        elseif ($line -match 'Pause Young') { $evt.Type = "Young" }

        # Cause
        $rest = $line
        switch ($evt.Type) {
            "Full"    { if ($rest -match 'Pause Full\s*\(([^)]+)\)') { $evt.Cause = $Matches[1] } }
            "Remark"  { if ($rest -match 'Pause Remark\s*\(([^)]+)\)') { $evt.Cause = $Matches[1] } }
            "Cleanup" { if ($rest -match 'Pause Cleanup\s*\(([^)]+)\)') { $evt.Cause = $Matches[1] } }
            default   { if ($rest -match 'Pause Young\s*\(([^)]+)\)') { $evt.Cause = $Matches[1] } }
        }

        # Heap: NNM->NNM(NNNM)
        if ($line -match '(\d+)M->(\d+)M\((\d+)M\)') {
            $evt.HeapBefore = $Matches[1]
            $evt.HeapAfter = $Matches[2]
            $evt.HeapTotal = $Matches[3]
        } elseif ($line -match '(\d+)K->(\d+)K\((\d+)K\)') {
            $evt.HeapBefore = [Math]::Round([double]$Matches[1] / 1024, 1)
            $evt.HeapAfter = [Math]::Round([double]$Matches[2] / 1024, 1)
            $evt.HeapTotal = [Math]::Round([double]$Matches[3] / 1024, 1)
        } elseif ($line -match '(\d+)G->(\d+)G\((\d+)G\)') {
            $evt.HeapBefore = [double]$Matches[1] * 1024
            $evt.HeapAfter = [double]$Matches[2] * 1024
            $evt.HeapTotal = [double]$Matches[3] * 1024
        }

        # Duration in ms
        if ($line -match '(\d+\.\d+)ms') {
            $evt.DurationMs = [double]$Matches[1]
        } elseif ($line -match '(\d+)ms') {
            $evt.DurationMs = [double]$Matches[1]
        }

        if ($evt.Timestamp -ne "" -and $evt.DurationMs -gt 0) {
            $events += [PSCustomObject]$evt
        }
    }

    # Output metadata
    Write-Output "=== GC LOG METADATA ==="
    Write-Output "format: unified (JDK 9+)"
    Write-Output "gc_algorithm: $GCAlgorithm"
    "duration: {0:F3}s" -f $durationS
    Write-Output "total_gc_events: $totalGCEvents"
    Write-Output "total_full_gc_events: $totalFullGCEvents"
    Write-Output ""

    # Heap configuration
    Write-Output "=== HEAP CONFIGURATION ==="
    $heapConfig = @($logLines | Where-Object { $_ -match '(Heap Region Size|Min Capacity|Initial Capacity|Max Capacity|InitialHeapSize|MaxHeapSize|NewSize|MaxNewSize|OldSize)' } | Select-Object -First 10)
    if ($heapConfig.Count -gt 0) {
        foreach ($hcLine in $heapConfig) {
            # Strip the unified log prefix
            $hcLine -replace '^\[.*?\]\s*', ''
        }
    } else {
        Write-Output "(not detected)"
    }
    Write-Output ""

    # All shared sections
    Write-PauseStats -Events $events
    Write-HeapUtilization -Events $events
    Write-Rates -Events $events
    Write-Overhead -Events $events -DurationS $durationS
    Write-FullGCEvents -Events $events
    Write-Humongous
    Write-Safepoints
    Write-Anomalies -Events $events
}

# =====================================================================
# LEGACY FORMAT PARSING (JDK <= 8)
# =====================================================================

function Parse-Legacy {
    # Extract timestamps
    $durationS = 0.0
    $hasUptime = @($logLines | Where-Object { $_ -match '^[0-9]+\.[0-9]+:' }).Count

    if ($hasUptime -gt 0) {
        $uptimeMatches = [regex]::Matches($logContent, '(?m)^(\d+\.\d+):')
        if ($uptimeMatches.Count -ge 2) {
            $firstTs = [double]$uptimeMatches[0].Groups[1].Value
            $lastTs = [double]$uptimeMatches[$uptimeMatches.Count - 1].Groups[1].Value
            $durationS = $lastTs - $firstTs
        }
    } else {
        $dateMatches = [regex]::Matches($logContent, '(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+)')
        if ($dateMatches.Count -ge 2) {
            try {
                $ft = [datetime]::ParseExact($dateMatches[0].Groups[1].Value.Substring(0,23), "yyyy-MM-ddTHH:mm:ss.fff", $null)
                $lt = [datetime]::ParseExact($dateMatches[$dateMatches.Count-1].Groups[1].Value.Substring(0,23), "yyyy-MM-ddTHH:mm:ss.fff", $null)
                $durationS = ($lt - $ft).TotalSeconds
                if ($durationS -lt 0) { $durationS += 86400 }
            } catch {
                $durationS = 0.0
            }
        }
    }

    # Extract GC lines
    $gcLines = @($logLines | Where-Object { $_ -match '\[(GC|Full GC)' })
    $totalGCEvents = $gcLines.Count
    $totalFullGCEvents = @($gcLines | Where-Object { $_ -match '\[Full GC' }).Count

    # Parse each GC line
    $events = @()
    foreach ($line in $gcLines) {
        $evt = @{
            Timestamp = ""
            Type = "Young"
            Cause = ""
            HeapBefore = ""
            HeapAfter = ""
            HeapTotal = ""
            DurationMs = 0.0
        }

        # Timestamp
        if ($line -match '^(\d+\.\d+):') {
            $evt.Timestamp = $Matches[1]
        } elseif ($line -match '(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+)') {
            $evt.Timestamp = $Matches[1]
        }

        # Type
        if ($line -match '\[Full GC') { $evt.Type = "Full" }

        # Cause
        if ($evt.Type -eq "Full") {
            if ($line -match '\[Full GC\s*\(([^)]+)\)') { $evt.Cause = $Matches[1] }
        } else {
            if ($line -match '\[GC\s*\(([^)]+)\)') { $evt.Cause = $Matches[1] }
        }

        # Heap - find last NNK->NNK(NNK) pattern (the overall heap, not region-specific)
        $heapMatches = [regex]::Matches($line, '(\d+)K->(\d+)K\((\d+)K\)')
        if ($heapMatches.Count -gt 0) {
            $lastMatch = $heapMatches[$heapMatches.Count - 1]
            $evt.HeapBefore = [Math]::Round([double]$lastMatch.Groups[1].Value / 1024, 1)
            $evt.HeapAfter = [Math]::Round([double]$lastMatch.Groups[2].Value / 1024, 1)
            $evt.HeapTotal = [Math]::Round([double]$lastMatch.Groups[3].Value / 1024, 1)
        } else {
            $heapMatches = [regex]::Matches($line, '(\d+)M->(\d+)M\((\d+)M\)')
            if ($heapMatches.Count -gt 0) {
                $lastMatch = $heapMatches[$heapMatches.Count - 1]
                $evt.HeapBefore = $lastMatch.Groups[1].Value
                $evt.HeapAfter = $lastMatch.Groups[2].Value
                $evt.HeapTotal = $lastMatch.Groups[3].Value
            }
        }

        # Duration: real=N.NN secs
        if ($line -match 'real=(\d+\.\d+) secs') {
            $evt.DurationMs = [double]$Matches[1] * 1000
        } elseif ($line -match ', (\d+\.\d+) secs\]') {
            $evt.DurationMs = [double]$Matches[1] * 1000
        }

        if ($evt.Timestamp -ne "" -and $evt.DurationMs -gt 0) {
            $events += [PSCustomObject]$evt
        }
    }

    # Output metadata
    Write-Output "=== GC LOG METADATA ==="
    Write-Output "format: legacy (JDK <=8)"
    Write-Output "gc_algorithm: $GCAlgorithm"
    "duration: {0:F3}s" -f $durationS
    Write-Output "total_gc_events: $totalGCEvents"
    Write-Output "total_full_gc_events: $totalFullGCEvents"
    Write-Output ""

    # Heap configuration
    Write-Output "=== HEAP CONFIGURATION ==="
    $heapConfig = @($logLines | Where-Object { $_ -match '(MaxHeapSize|InitialHeapSize|NewSize|MaxNewSize|CommandLine)' } | Select-Object -First 10)
    if ($heapConfig.Count -gt 0) {
        $heapConfig
    } else {
        Write-Output "(not detected)"
    }
    Write-Output ""

    # All shared sections
    Write-PauseStats -Events $events
    Write-HeapUtilization -Events $events
    Write-Rates -Events $events
    Write-Overhead -Events $events -DurationS $durationS
    Write-FullGCEvents -Events $events
    Write-Humongous
    Write-Safepoints
    Write-Anomalies -Events $events
}

# =====================================================================
# MAIN
# =====================================================================

if ($Format -eq "unified") {
    Parse-Unified
} elseif ($Format -eq "legacy") {
    Parse-Legacy
}
