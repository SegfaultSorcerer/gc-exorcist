#!/usr/bin/env bash
# gc-parser.sh - Core GC log parser for gc-exorcist
# Usage: ./scripts/gc-parser.sh <gc-log-file> [--format auto|unified|legacy]
# Requires: bash 3.2+, awk, sort, mktemp
# Compatible with macOS (BSD awk) and Linux (GNU awk)

set -euo pipefail

# --- Globals ---
TMPDIR_GC=""
FORMAT="auto"
GC_LOG=""

# --- Cleanup ---
cleanup() {
    if [ -n "$TMPDIR_GC" ] && [ -d "$TMPDIR_GC" ]; then
        rm -rf "$TMPDIR_GC"
    fi
}
trap cleanup EXIT

# --- Usage ---
usage() {
    echo "Usage: $0 <gc-log-file> [--format auto|unified|legacy]"
    echo ""
    echo "Options:"
    echo "  --format   Format detection mode: auto (default), unified (JDK 9+), legacy (JDK <=8)"
    exit 1
}

# --- Argument parsing ---
if [ $# -lt 1 ]; then
    usage
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --format)
            if [ $# -lt 2 ]; then
                echo "Error: --format requires a value (auto|unified|legacy)" >&2
                exit 1
            fi
            FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$GC_LOG" ]; then
                GC_LOG="$1"
            else
                echo "Error: unexpected argument '$1'" >&2
                usage
            fi
            shift
            ;;
    esac
done

if [ -z "$GC_LOG" ]; then
    echo "Error: no GC log file specified" >&2
    usage
fi

if [ ! -f "$GC_LOG" ]; then
    echo "Error: file not found: $GC_LOG" >&2
    exit 1
fi

if [ ! -s "$GC_LOG" ]; then
    echo "Error: file is empty: $GC_LOG" >&2
    exit 1
fi

case "$FORMAT" in
    auto|unified|legacy) ;;
    *)
        echo "Error: invalid format '$FORMAT'. Use auto, unified, or legacy." >&2
        exit 1
        ;;
esac

# --- Setup temp directory ---
TMPDIR_GC="$(mktemp -d)"

# --- Format Detection ---
detect_format() {
    local unified_count legacy_count
    unified_count=$(grep -cE '^\[[0-9]+\.[0-9]+s\]\[' "$GC_LOG" 2>/dev/null || true)
    legacy_count=$(grep -cE '(^[0-9]{4}-[0-9]{2}-[0-9]{2}T.*\[GC|^[0-9]+\.[0-9]+:.*\[GC)' "$GC_LOG" 2>/dev/null || true)

    # Treat empty counts as 0
    unified_count="${unified_count:-0}"
    legacy_count="${legacy_count:-0}"

    if [ "$unified_count" -gt 0 ] && [ "$legacy_count" -gt 0 ]; then
        echo "Error: mixed GC log formats detected (unified: $unified_count lines, legacy: $legacy_count lines)" >&2
        exit 1
    elif [ "$unified_count" -gt 0 ]; then
        echo "unified"
    elif [ "$legacy_count" -gt 0 ]; then
        echo "legacy"
    else
        echo "Error: unrecognized GC log format" >&2
        exit 1
    fi
}

if [ "$FORMAT" = "auto" ]; then
    FORMAT="$(detect_format)"
fi

# --- Detect GC Algorithm ---
detect_algorithm() {
    local log="$1"
    if grep -qiE '(Using G1|G1 Evacuation Pause|G1 Compaction)' "$log" 2>/dev/null; then
        echo "G1"
    elif grep -qiE '(Using ZGC|Z Garbage Collector)' "$log" 2>/dev/null; then
        echo "ZGC"
    elif grep -qiE '(Using Shenandoah|Shenandoah)' "$log" 2>/dev/null; then
        echo "Shenandoah"
    elif grep -qiE '(Using Parallel|PSYoungGen|ParOldGen)' "$log" 2>/dev/null; then
        echo "Parallel"
    elif grep -qiE '(Using Serial|DefNew|Tenured)' "$log" 2>/dev/null; then
        echo "Serial"
    elif grep -qiE '(Using CMS|ConcurrentMarkSweep|ParNew)' "$log" 2>/dev/null; then
        echo "CMS"
    else
        echo "Unknown"
    fi
}

GC_ALGORITHM="$(detect_algorithm "$GC_LOG")"

# =====================================================================
# SHARED STATISTICS FUNCTIONS
# =====================================================================

# Compute percentile from a sorted file
# Usage: percentile_val <sorted_file> <p> (p in 0-100)
percentile_val() {
    local sorted_file="$1"
    local p="$2"
    local count
    count=$(wc -l < "$sorted_file" | tr -d ' ')
    if [ "$count" -eq 0 ]; then
        echo "0"
        return
    fi
    awk -v p="$p" -v n="$count" 'BEGIN {
        idx = int(p/100 * n + 0.5)
        if (idx < 1) idx = 1
        if (idx > n) idx = n
    }
    NR == idx { printf "%.3f", $1 }' "$sorted_file"
}

# Print stats line for a given type
# Args: label, pause_file (unsorted, one value per line)
print_stats_line() {
    local label="$1"
    local pfile="$2"

    local count
    count=$(wc -l < "$pfile" | tr -d ' ')
    if [ "$count" -eq 0 ]; then
        return
    fi

    sort -n "$pfile" > "${TMPDIR_GC}/sorted_pause.tmp"
    local sfile="${TMPDIR_GC}/sorted_pause.tmp"

    local min max avg p50 p95 p99
    min=$(head -1 "$sfile")
    max=$(tail -1 "$sfile")
    avg=$(awk '{ s += $1 } END { printf "%.3f", s/NR }' "$sfile")
    p50=$(percentile_val "$sfile" 50)
    p95=$(percentile_val "$sfile" 95)
    p99=$(percentile_val "$sfile" 99)

    printf "  %-14s %6d  %10.3f  %10.3f  %10.3f  %10.3f  %10.3f  %10.3f\n" \
        "$label" "$count" "$min" "$avg" "$p50" "$p95" "$p99" "$max"
}

compute_pause_stats() {
    local events_file="$1"

    echo "=== PAUSE TIME SUMMARY ==="

    if [ ! -s "$events_file" ]; then
        echo "(no pause events found)"
        echo ""
        echo "=== PAUSE TIME DISTRIBUTION ==="
        echo "(no data)"
        echo ""
        return
    fi

    # Split durations by type
    awk -F'\t' '$2 == "Young"  { print $7 }' "$events_file" > "${TMPDIR_GC}/dur_young.tmp"
    awk -F'\t' '$2 == "Mixed"  { print $7 }' "$events_file" > "${TMPDIR_GC}/dur_mixed.tmp"
    awk -F'\t' '$2 == "Full"   { print $7 }' "$events_file" > "${TMPDIR_GC}/dur_full.tmp"
    awk -F'\t' '$2 == "Remark" { print $7 }' "$events_file" > "${TMPDIR_GC}/dur_remark.tmp"
    awk -F'\t' '$2 == "Cleanup"{ print $7 }' "$events_file" > "${TMPDIR_GC}/dur_cleanup.tmp"
    awk -F'\t' '{ print $7 }' "$events_file" > "${TMPDIR_GC}/dur_total.tmp"

    printf "  %-14s %6s  %10s  %10s  %10s  %10s  %10s  %10s\n" \
        "Type" "Count" "Min(ms)" "Avg(ms)" "P50(ms)" "P95(ms)" "P99(ms)" "Max(ms)"
    printf "  %-14s %6s  %10s  %10s  %10s  %10s  %10s  %10s\n" \
        "--------------" "------" "----------" "----------" "----------" "----------" "----------" "----------"

    print_stats_line "Young" "${TMPDIR_GC}/dur_young.tmp"
    print_stats_line "Mixed" "${TMPDIR_GC}/dur_mixed.tmp"
    print_stats_line "Full" "${TMPDIR_GC}/dur_full.tmp"
    print_stats_line "Remark" "${TMPDIR_GC}/dur_remark.tmp"
    print_stats_line "Cleanup" "${TMPDIR_GC}/dur_cleanup.tmp"
    print_stats_line "Total STW" "${TMPDIR_GC}/dur_total.tmp"
    echo ""

    # --- Pause time distribution ---
    echo "=== PAUSE TIME DISTRIBUTION ==="
    awk '
    BEGIN { b1=0; b2=0; b3=0; b4=0; b5=0; b6=0; total=0 }
    {
        v = $1 + 0
        if (v < 10) b1++
        else if (v < 20) b2++
        else if (v < 50) b3++
        else if (v < 100) b4++
        else if (v < 500) b5++
        else b6++
        total++
    }
    END {
        if (total == 0) { print "(no data)"; exit }
        max_count = b1
        if (b2 > max_count) max_count = b2
        if (b3 > max_count) max_count = b3
        if (b4 > max_count) max_count = b4
        if (b5 > max_count) max_count = b5
        if (b6 > max_count) max_count = b6

        bar_width = 40
        if (max_count == 0) max_count = 1

        split("< 10ms,10-20ms,20-50ms,50-100ms,100-500ms,> 500ms", labels, ",")
        counts[1] = b1; counts[2] = b2; counts[3] = b3
        counts[4] = b4; counts[5] = b5; counts[6] = b6

        for (i = 1; i <= 6; i++) {
            bar_len = int(counts[i] / max_count * bar_width + 0.5)
            bar = ""
            for (j = 0; j < bar_len; j++) bar = bar "#"
            # Pad bar to bar_width
            while (length(bar) < bar_width) bar = bar " "
            pct = counts[i] / total * 100
            printf "  %-12s |%s| %5d (%5.1f%%)\n", labels[i], bar, counts[i], pct
        }
    }' "${TMPDIR_GC}/dur_total.tmp"
    echo ""
}

compute_heap_utilization() {
    local events_file="$1"

    echo "=== HEAP UTILIZATION ==="

    if [ ! -s "$events_file" ]; then
        echo "(no heap data found)"
        echo ""
        return
    fi

    awk -F'\t' '
    $4 != "" && $5 != "" {
        n++
        sum_before += ($4 + 0)
        sum_after += ($5 + 0)
        if (($4 + 0) > max_before) max_before = ($4 + 0)
        if (($5 + 0) > max_after) max_after = ($5 + 0)
        total_cap = ($6 + 0)
        after_vals[n] = ($5 + 0)
    }
    END {
        if (n == 0) { print "(no heap data)"; exit }
        printf "  events_with_heap_data: %d\n", n
        printf "  heap_before_gc_avg:    %.1f MB\n", sum_before/n
        printf "  heap_before_gc_max:    %.1f MB\n", max_before
        printf "  heap_after_gc_avg:     %.1f MB\n", sum_after/n
        printf "  heap_after_gc_max:     %.1f MB\n", max_after
        if (total_cap > 0) printf "  heap_capacity:         %.1f MB\n", total_cap

        # Detect upward drift in after-GC occupancy
        if (n >= 4) {
            quarter = int(n/4)
            first_q_avg = 0; last_q_avg = 0
            for (i = 1; i <= quarter; i++) first_q_avg += after_vals[i]
            for (i = n - quarter + 1; i <= n; i++) last_q_avg += after_vals[i]
            first_q_avg /= quarter
            last_q_avg /= quarter
            if (last_q_avg > first_q_avg * 1.2) {
                printf "  ** DRIFT DETECTED: after-GC occupancy trending up (%.1f MB -> %.1f MB avg)\n", first_q_avg, last_q_avg
                printf "     This may indicate a memory leak.\n"
            }
        }
    }' "$events_file"
    echo ""
}

compute_rates() {
    local events_file="$1"

    echo "=== ALLOCATION RATE ==="
    if [ ! -s "$events_file" ]; then
        echo "  (no data)"
        echo ""
        echo "=== PROMOTION RATE ==="
        echo "  (no data)"
        echo ""
        return
    fi

    # Allocation rate: delta of heap_before between consecutive events / time delta
    awk -F'\t' '
    $1 != "" && $4 != "" && $1 ~ /^[0-9]/ {
        # Convert timestamp to numeric seconds
        ts_str = $1
        # If it looks like uptime (just a number), use directly
        if (ts_str ~ /^[0-9]+\.[0-9]+$/) {
            ts = ts_str + 0
        } else {
            # Skip non-numeric timestamps for rate calc
            next
        }
        hb = $4 + 0
        ha = $5 + 0
        if (prev_ts != "" && ts > prev_ts) {
            dt = ts - prev_ts
            alloc = hb - prev_ha
            if (alloc > 0 && dt > 0) {
                rate = alloc / dt
                count++
                sum_rate += rate
                if (rate > max_rate) max_rate = rate
                if (count == 1 || rate < min_rate) min_rate = rate
            }
        }
        prev_ts = ts
        prev_ha = ha
    }
    END {
        if (count == 0) { print "  (insufficient data)"; exit }
        printf "  samples:  %d\n", count
        printf "  avg:      %.1f MB/s\n", sum_rate/count
        printf "  max:      %.1f MB/s\n", max_rate
        printf "  min:      %.1f MB/s\n", min_rate
    }' "$events_file"
    echo ""

    echo "=== PROMOTION RATE ==="
    awk -F'\t' '
    $2 == "Young" && $5 != "" && $1 ~ /^[0-9]+\.[0-9]+$/ {
        ha = $5 + 0
        ts = $1 + 0
        if (prev_young_ha != "" && ts > prev_young_ts) {
            dt = ts - prev_young_ts
            promo = ha - prev_young_ha
            if (promo > 0 && dt > 0) {
                rate = promo / dt
                count++
                sum_rate += rate
                if (rate > max_rate) max_rate = rate
            }
        }
        prev_young_ha = ha
        prev_young_ts = ts
    }
    END {
        if (count == 0) { print "  (insufficient data or no promotion observed)"; exit }
        printf "  samples:  %d\n", count
        printf "  avg:      %.1f MB/s\n", sum_rate/count
        printf "  max:      %.1f MB/s\n", max_rate
    }' "$events_file"
    echo ""
}

compute_overhead() {
    local events_file="$1"
    local duration_s="$2"

    echo "=== GC OVERHEAD ==="

    if [ ! -s "$events_file" ]; then
        echo "  gc_overhead: 0.000%"
        echo ""
        return
    fi

    local total_stw_ms
    total_stw_ms=$(awk -F'\t' '{ s += $7 } END { printf "%.3f", s+0 }' "$events_file")

    local duration_positive
    duration_positive=$(awk -v d="$duration_s" 'BEGIN { print (d+0 > 0) ? "1" : "0" }')

    if [ "$duration_positive" = "1" ]; then
        local overhead
        overhead=$(awk -v stw="$total_stw_ms" -v dur="$duration_s" 'BEGIN { printf "%.3f", (stw / 1000) / dur * 100 }')
        echo "  total_stw_time: ${total_stw_ms}ms"
        echo "  total_runtime:  ${duration_s}s"
        echo "  gc_overhead:    ${overhead}%"
    else
        echo "  total_stw_time: ${total_stw_ms}ms"
        echo "  gc_overhead:    (cannot compute - zero duration)"
    fi
    echo ""
}

list_full_gc_events() {
    local events_file="$1"

    echo "=== FULL GC EVENTS ==="

    if [ ! -s "$events_file" ]; then
        echo "  (none)"
        echo ""
        return
    fi

    local full_count
    full_count=$(awk -F'\t' '$2 == "Full" { c++ } END { print c+0 }' "$events_file")

    if [ "$full_count" -eq 0 ]; then
        echo "  (none)"
        echo ""
        return
    fi

    printf "  %-14s  %-30s  %10s  %10s  %12s\n" "Timestamp" "Cause" "Before(MB)" "After(MB)" "Duration(ms)"
    printf "  %-14s  %-30s  %10s  %10s  %12s\n" "--------------" "------------------------------" "----------" "----------" "------------"
    awk -F'\t' '$2 == "Full" {
        printf "  %-14s  %-30s  %10s  %10s  %12.3f\n", $1, $3, $4, $5, $7
    }' "$events_file"
    echo ""
}

detect_humongous() {
    local log="$1"

    echo "=== HUMONGOUS ALLOCATIONS ==="
    if [ "$GC_ALGORITHM" = "G1" ]; then
        local hcount
        hcount=$(grep -ciE '(gc,humongous|humongous object|Humongous)' "$log" 2>/dev/null || echo "0")
        echo "  humongous_log_lines: $hcount"
        if [ "$hcount" -gt 0 ]; then
            echo "  (showing up to 5 examples):"
            grep -iE '(gc,humongous|humongous object|Humongous)' "$log" 2>/dev/null | head -5 | sed 's/^/    /'
        fi
    else
        echo "  (only applicable to G1 GC)"
    fi
    echo ""
}

parse_safepoints() {
    local log="$1"

    echo "=== SAFEPOINT SUMMARY ==="
    local sp_count
    sp_count=$(grep -ciE 'safepoint' "$log" 2>/dev/null | head -1 || echo "0")
    sp_count=$(echo "$sp_count" | tr -d '[:space:]')
    sp_count="${sp_count:-0}"
    if [ "$sp_count" -gt 0 ]; then
        echo "  safepoint_entries: $sp_count"
        grep -iE 'safepoint' "$log" 2>/dev/null | head -5 | sed 's/^/    /'
    else
        echo "  (no safepoint data found)"
    fi
    echo ""
}

detect_anomalies() {
    local log="$1"
    local events_file="$2"

    echo "=== ANOMALIES DETECTED ==="
    local found_anomaly=0

    # Evacuation failures
    local evac_fail
    evac_fail=$(grep -ciE '(Evacuation Failure|To-space exhausted|to-space overflow)' "$log" 2>/dev/null | head -1 || echo "0")
    evac_fail=$(echo "$evac_fail" | tr -d '[:space:]')
    evac_fail="${evac_fail:-0}"
    if [ "$evac_fail" -gt 0 ]; then
        echo "  [!] Evacuation failures detected: $evac_fail occurrences"
        found_anomaly=1
    fi

    # Promotion failed
    local promo_fail
    promo_fail=$(grep -ciE 'promotion failed' "$log" 2>/dev/null | head -1 || echo "0")
    promo_fail=$(echo "$promo_fail" | tr -d '[:space:]')
    promo_fail="${promo_fail:-0}"
    if [ "$promo_fail" -gt 0 ]; then
        echo "  [!] Promotion failures detected: $promo_fail occurrences"
        found_anomaly=1
    fi

    # Concurrent mode failure (CMS)
    local cmf
    cmf=$(grep -ciE 'concurrent mode failure' "$log" 2>/dev/null | head -1 || echo "0")
    cmf=$(echo "$cmf" | tr -d '[:space:]')
    cmf="${cmf:-0}"
    if [ "$cmf" -gt 0 ]; then
        echo "  [!] CMS concurrent mode failures: $cmf occurrences"
        found_anomaly=1
    fi

    # High allocation rate spikes
    if [ -s "$events_file" ]; then
        local spike_output
        spike_output=$(awk -F'\t' '
        $1 ~ /^[0-9]+\.[0-9]+$/ && $4 != "" {
            ts = $1 + 0; hb = $4 + 0; ha = $5 + 0
            if (prev_ts != "" && ts > prev_ts) {
                dt = ts - prev_ts
                alloc = hb - prev_ha
                if (alloc > 0 && dt > 0) {
                    rate = alloc / dt
                    rates[++n] = rate
                    sum += rate
                }
            }
            prev_ts = ts; prev_ha = ha
        }
        END {
            if (n < 2) exit
            avg = sum / n
            spikes = 0
            for (i = 1; i <= n; i++) {
                if (rates[i] > avg * 3) spikes++
            }
            if (spikes > 0) {
                printf "  [!] High allocation rate spikes: %d events exceeded 3x average rate (%.1f MB/s)\n", spikes, avg
            }
        }' "$events_file")
        if [ -n "$spike_output" ]; then
            echo "$spike_output"
            found_anomaly=1
        fi
    fi

    # Multiple Full GCs
    if [ -s "$events_file" ]; then
        local full_count
        full_count=$(awk -F'\t' '$2 == "Full" { c++ } END { print c+0 }' "$events_file")
        if [ "$full_count" -gt 2 ]; then
            echo "  [!] Multiple Full GC events ($full_count) detected - may indicate promotion pressure"
            found_anomaly=1
        fi
    fi

    # Upward occupancy drift
    if [ -s "$events_file" ]; then
        local drift_output
        drift_output=$(awk -F'\t' '
        $5 != "" {
            n++
            after_vals[n] = $5 + 0
        }
        END {
            if (n < 4) exit
            q = int(n/4)
            if (q < 1) exit
            first_avg = 0; last_avg = 0
            for (i = 1; i <= q; i++) first_avg += after_vals[i]
            for (i = n-q+1; i <= n; i++) last_avg += after_vals[i]
            first_avg /= q; last_avg /= q
            if (last_avg > first_avg * 1.2) {
                printf "  [!] Upward occupancy drift: after-GC heap trending up (%.1f -> %.1f MB avg)\n", first_avg, last_avg
                printf "       Possible memory leak.\n"
            }
        }' "$events_file")
        if [ -n "$drift_output" ]; then
            echo "$drift_output"
            found_anomaly=1
        fi
    fi

    if [ "$found_anomaly" -eq 0 ]; then
        echo "  (none detected)"
    fi
    echo ""
}

# =====================================================================
# UNIFIED FORMAT PARSING (JDK 9+)
# Uses only POSIX awk features (no GNU capture groups)
# =====================================================================
parse_unified() {
    local log="$1"

    # --- Timestamps: extract seconds from [NNN.NNNs] ---
    local first_ts last_ts duration_s
    first_ts=$(grep -oE '^\[[0-9]+\.[0-9]+s\]' "$log" | head -1 | tr -d '[]s')
    last_ts=$(grep -oE '^\[[0-9]+\.[0-9]+s\]' "$log" | tail -1 | tr -d '[]s')
    if [ -n "$first_ts" ] && [ -n "$last_ts" ]; then
        duration_s=$(awk -v a="$first_ts" -v b="$last_ts" 'BEGIN { printf "%.3f", b - a }')
    else
        duration_s="0.000"
    fi

    # --- Extract pause events ---
    # Filter out gc,start lines — only keep main event lines (which have heap/duration info)
    grep -E 'Pause (Young|Full|Remark|Cleanup)' "$log" | grep -v 'gc,start' > "${TMPDIR_GC}/pause_lines.txt" 2>/dev/null || true

    local total_gc_events
    total_gc_events=$(wc -l < "${TMPDIR_GC}/pause_lines.txt" | tr -d ' ')

    local total_full_gc_events
    total_full_gc_events=$(grep -c 'Pause Full' "${TMPDIR_GC}/pause_lines.txt" 2>/dev/null || echo "0")

    # --- Parse each pause line using POSIX-compatible awk ---
    awk '
    {
        line = $0

        # Extract timestamp from [NNN.NNNs]
        ts = ""
        if (match(line, /\[[0-9]+\.[0-9]+s\]/)) {
            ts = substr(line, RSTART+1, RLENGTH-3)
        }

        # Extract pause type
        ptype = ""
        if (index(line, "Pause Full") > 0) ptype = "Full"
        else if (index(line, "Pause Remark") > 0) ptype = "Remark"
        else if (index(line, "Pause Cleanup") > 0) ptype = "Cleanup"
        else if (index(line, "Pause Young") > 0) {
            if (index(line, "Mixed") > 0) ptype = "Mixed"
            else ptype = "Young"
        }

        # Extract cause - text in first parentheses after pause type keyword
        cause = ""
        rest = line
        # Remove everything up to and including the pause type
        if (ptype == "Full") sub(/.*Pause Full/, "", rest)
        else if (ptype == "Remark") sub(/.*Pause Remark/, "", rest)
        else if (ptype == "Cleanup") sub(/.*Pause Cleanup/, "", rest)
        else sub(/.*Pause Young/, "", rest)
        if (match(rest, /\([^)]+\)/)) {
            cause = substr(rest, RSTART+1, RLENGTH-2)
        }

        # Extract heap: NNM->NNM(NNNM)
        heap_before = ""
        heap_after = ""
        heap_total = ""
        if (match(line, /[0-9]+M->[0-9]+M\([0-9]+M\)/)) {
            hstr = substr(line, RSTART, RLENGTH)
            gsub(/[^0-9]/, " ", hstr)
            n_nums = split(hstr, nums)
            if (n_nums >= 3) { heap_before = nums[1]; heap_after = nums[2]; heap_total = nums[3] }
        } else if (match(line, /[0-9]+K->[0-9]+K\([0-9]+K\)/)) {
            hstr = substr(line, RSTART, RLENGTH)
            gsub(/[^0-9]/, " ", hstr)
            n_nums = split(hstr, nums)
            if (n_nums >= 3) { heap_before = nums[1] / 1024; heap_after = nums[2] / 1024; heap_total = nums[3] / 1024 }
        } else if (match(line, /[0-9]+G->[0-9]+G\([0-9]+G\)/)) {
            hstr = substr(line, RSTART, RLENGTH)
            gsub(/[^0-9]/, " ", hstr)
            n_nums = split(hstr, nums)
            if (n_nums >= 3) { heap_before = nums[1] * 1024; heap_after = nums[2] * 1024; heap_total = nums[3] * 1024 }
        }

        # Extract duration in ms
        dur_ms = ""
        if (match(line, /[0-9]+\.[0-9]+ms/)) {
            dstr = substr(line, RSTART, RLENGTH-2)
            dur_ms = dstr
        } else if (match(line, /[0-9]+ms/)) {
            dstr = substr(line, RSTART, RLENGTH-2)
            dur_ms = dstr
        }

        if (dur_ms != "" && ts != "") {
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", ts, ptype, cause, heap_before, heap_after, heap_total, dur_ms
        }
    }
    ' "${TMPDIR_GC}/pause_lines.txt" > "${TMPDIR_GC}/parsed_events.tsv" 2>/dev/null || true

    # --- Output metadata ---
    echo "=== GC LOG METADATA ==="
    echo "format: unified (JDK 9+)"
    echo "gc_algorithm: $GC_ALGORITHM"
    echo "duration: ${duration_s}s"
    echo "total_gc_events: $total_gc_events"
    echo "total_full_gc_events: $total_full_gc_events"
    echo ""

    # --- Heap Configuration ---
    echo "=== HEAP CONFIGURATION ==="
    grep -E '(Heap Region Size|Min Capacity|Initial Capacity|Max Capacity|InitialHeapSize|MaxHeapSize|NewSize|MaxNewSize|OldSize)' "$log" 2>/dev/null | head -10 | sed 's/^.*\] //' || echo "(not detected)"
    echo ""

    # --- All shared sections ---
    compute_pause_stats "${TMPDIR_GC}/parsed_events.tsv"
    compute_heap_utilization "${TMPDIR_GC}/parsed_events.tsv"
    compute_rates "${TMPDIR_GC}/parsed_events.tsv"
    compute_overhead "${TMPDIR_GC}/parsed_events.tsv" "$duration_s"
    list_full_gc_events "${TMPDIR_GC}/parsed_events.tsv"
    detect_humongous "$log"
    parse_safepoints "$log"
    detect_anomalies "$log" "${TMPDIR_GC}/parsed_events.tsv"
}

# =====================================================================
# LEGACY FORMAT PARSING (JDK <= 8)
# =====================================================================
parse_legacy() {
    local log="$1"

    # --- Timestamps ---
    local first_ts last_ts duration_s

    # Check for uptimestamp format: N.NNN:
    local has_uptime
    has_uptime=$(grep -cE '^[0-9]+\.[0-9]+:' "$log" 2>/dev/null || echo "0")
    has_uptime="${has_uptime:-0}"

    if [ "$has_uptime" -gt 0 ]; then
        first_ts=$(grep -oE '^[0-9]+\.[0-9]+' "$log" | head -1)
        last_ts=$(grep -oE '^[0-9]+\.[0-9]+' "$log" | tail -1)
        if [ -n "$first_ts" ] && [ -n "$last_ts" ]; then
            duration_s=$(awk -v a="$first_ts" -v b="$last_ts" 'BEGIN { printf "%.3f", b - a }')
        else
            duration_s="0.000"
        fi
    else
        # Try datestamp
        first_ts=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+' "$log" 2>/dev/null | head -1)
        last_ts=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+' "$log" 2>/dev/null | tail -1)
        if [ -n "$first_ts" ] && [ -n "$last_ts" ]; then
            duration_s=$(awk -v ft="$first_ts" -v lt="$last_ts" 'BEGIN {
                split(ft, a, /[T:.]/); split(lt, b, /[T:.]/);
                fs = a[4]*3600 + a[5]*60 + a[6] + a[7]/1000;
                ls = b[4]*3600 + b[5]*60 + b[6] + b[7]/1000;
                d = ls - fs;
                if (d < 0) d += 86400;
                printf "%.3f", d
            }')
        else
            duration_s="0.000"
        fi
    fi

    # --- Extract GC lines ---
    grep -E '\[(GC|Full GC)' "$log" > "${TMPDIR_GC}/gc_lines.txt" 2>/dev/null || true

    local total_gc_events
    total_gc_events=$(wc -l < "${TMPDIR_GC}/gc_lines.txt" | tr -d ' ')

    local total_full_gc_events
    total_full_gc_events=$(grep -c '\[Full GC' "${TMPDIR_GC}/gc_lines.txt" 2>/dev/null || echo "0")

    # --- Parse each GC line using POSIX-compatible awk ---
    awk '
    {
        line = $0

        # Extract timestamp
        ts = ""
        if (match(line, /^[0-9]+\.[0-9]+/)) {
            ts = substr(line, RSTART, RLENGTH)
        } else if (match(line, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9]+/)) {
            ts = substr(line, RSTART, RLENGTH)
        }

        # Determine type
        ptype = "Young"
        if (index(line, "[Full GC") > 0) ptype = "Full"

        # Extract cause from (cause) after [GC or [Full GC
        cause = ""
        rest = line
        if (ptype == "Full") {
            idx = index(rest, "[Full GC")
            if (idx > 0) rest = substr(rest, idx + 8)
        } else {
            idx = index(rest, "[GC")
            if (idx > 0) rest = substr(rest, idx + 3)
        }
        # Look for (cause) - first paren group
        if (match(rest, /^ *\([^)]+\)/)) {
            cause = substr(rest, RSTART, RLENGTH)
            gsub(/^[ (]+/, "", cause)
            gsub(/[)]+$/, "", cause)
        }

        # Extract overall heap - find last NNK->NNK(NNK) or NNM->NNM(NNM) pattern
        heap_before = ""
        heap_after = ""
        heap_total = ""

        # Try K format - find all occurrences, keep last
        tmp = line
        while (match(tmp, /[0-9]+K->[0-9]+K\([0-9]+K\)/)) {
            hstr = substr(tmp, RSTART, RLENGTH)
            tmp = substr(tmp, RSTART + RLENGTH)
            gsub(/[^0-9]/, " ", hstr)
            n_nums = split(hstr, nums)
            if (n_nums >= 3) { heap_before = nums[1] / 1024; heap_after = nums[2] / 1024; heap_total = nums[3] / 1024 }
        }

        # If no K format found, try M format
        if (heap_before == "") {
            tmp = line
            while (match(tmp, /[0-9]+M->[0-9]+M\([0-9]+M\)/)) {
                hstr = substr(tmp, RSTART, RLENGTH)
                tmp = substr(tmp, RSTART + RLENGTH)
                gsub(/[^0-9]/, " ", hstr)
                n_nums = split(hstr, nums)
                if (n_nums >= 3) { heap_before = nums[1]; heap_after = nums[2]; heap_total = nums[3] }
            }
        }

        # Extract real time: real=N.NN secs
        dur_ms = ""
        if (match(line, /real=[0-9]+\.[0-9]+ secs/)) {
            rstr = substr(line, RSTART+5, RLENGTH-10)
            dur_ms = rstr * 1000
        }

        # Fallback: N.NNNNNNN secs] at end
        if (dur_ms == "" && match(line, /, [0-9]+\.[0-9]+ secs\]/)) {
            rstr = substr(line, RSTART+2, RLENGTH-8)
            dur_ms = rstr * 1000
        }

        if (ts != "" && dur_ms != "") {
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%.3f\n", ts, ptype, cause, heap_before, heap_after, heap_total, dur_ms
        }
    }
    ' "${TMPDIR_GC}/gc_lines.txt" > "${TMPDIR_GC}/parsed_events.tsv" 2>/dev/null || true

    # --- Output metadata ---
    echo "=== GC LOG METADATA ==="
    echo "format: legacy (JDK <=8)"
    echo "gc_algorithm: $GC_ALGORITHM"
    echo "duration: ${duration_s}s"
    echo "total_gc_events: $total_gc_events"
    echo "total_full_gc_events: $total_full_gc_events"
    echo ""

    # --- Heap Configuration ---
    echo "=== HEAP CONFIGURATION ==="
    grep -iE '(Heap|Memory|CommandLine)' "$log" 2>/dev/null | grep -iE '(MaxHeapSize|InitialHeapSize|NewSize|MaxNewSize|command)' | head -10 || echo "(not detected)"
    echo ""

    # --- All shared sections ---
    compute_pause_stats "${TMPDIR_GC}/parsed_events.tsv"
    compute_heap_utilization "${TMPDIR_GC}/parsed_events.tsv"
    compute_rates "${TMPDIR_GC}/parsed_events.tsv"
    compute_overhead "${TMPDIR_GC}/parsed_events.tsv" "$duration_s"
    list_full_gc_events "${TMPDIR_GC}/parsed_events.tsv"
    detect_humongous "$log"
    parse_safepoints "$log"
    detect_anomalies "$log" "${TMPDIR_GC}/parsed_events.tsv"
}

# =====================================================================
# MAIN
# =====================================================================

if [ "$FORMAT" = "unified" ]; then
    parse_unified "$GC_LOG"
elif [ "$FORMAT" = "legacy" ]; then
    parse_legacy "$GC_LOG"
fi
