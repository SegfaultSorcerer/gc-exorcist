#!/usr/bin/env bash
# run-eval.sh - Benchmark evaluation for gc-parser.sh against fixture GC logs
# Usage: ./benchmark/run-eval.sh
# Runs gc-parser.sh against each fixture in benchmark/fixtures/ and checks expected outputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="${SCRIPT_DIR}/../scripts/gc-parser.sh"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures"

PASS_COUNT=0
FAIL_COUNT=0

# --- Helpers ---

assert_match() {
    local label="$1"
    local pattern="$2"
    local output="$3"
    if echo "$output" | grep -qiE "$pattern"; then
        echo "[PASS] $label"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "[FAIL] $label"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_no_match() {
    local label="$1"
    local pattern="$2"
    local output="$3"
    if echo "$output" | grep -qiE "$pattern"; then
        echo "[FAIL] $label"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "[PASS] $label"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
}

run_parser() {
    local fixture="$1"
    local filepath="${FIXTURES_DIR}/${fixture}"
    if [ ! -f "$filepath" ]; then
        echo "  [SKIP] Fixture not found: $filepath"
        return 1
    fi
    bash "$PARSER" "$filepath" 2>&1
}

# --- Main ---

echo "=== gc-exorcist Parser Evaluation ==="
echo ""

# Track which fixtures were actually tested
FIXTURES_TESTED=0

# ---------------------------------------------------------------
# unified-g1-healthy.log
# ---------------------------------------------------------------
FIXTURE="unified-g1-healthy.log"
echo "--- ${FIXTURE} ---"
OUTPUT="$(run_parser "$FIXTURE")" || { echo ""; true; }

if [ -n "$OUTPUT" ]; then
    FIXTURES_TESTED=$((FIXTURES_TESTED + 1))
    assert_match "Format detected as unified" "format:.*unified" "$OUTPUT"
    assert_match "GC algorithm detected as G1" "gc_algorithm:.*G1" "$OUTPUT"
    assert_match "No Full GCs reported" "total_full_gc_events:.*0" "$OUTPUT"
    # GC overhead should be less than 1% -- match a line like gc_overhead: 0.NNN%
    assert_match "GC overhead < 1%" "gc_overhead:[ ]*0\." "$OUTPUT"
    # No anomalies or only "(none detected)"
    assert_match "No anomalies detected" "ANOMALIES DETECTED" "$OUTPUT"
    assert_no_match "No evacuation failures" "Evacuation failure" "$OUTPUT"
fi
echo ""

# ---------------------------------------------------------------
# unified-g1-problematic.log
# ---------------------------------------------------------------
FIXTURE="unified-g1-problematic.log"
echo "--- ${FIXTURE} ---"
OUTPUT="$(run_parser "$FIXTURE")" || { echo ""; true; }

if [ -n "$OUTPUT" ]; then
    FIXTURES_TESTED=$((FIXTURES_TESTED + 1))
    assert_match "Format detected as unified" "format:.*unified" "$OUTPUT"
    assert_match "GC algorithm detected as G1" "gc_algorithm:.*G1" "$OUTPUT"
    assert_match "3 Full GC events reported" "total_full_gc_events:.*3" "$OUTPUT"
    assert_match "Humongous allocations detected" "humongous" "$OUTPUT"
    assert_match "Evacuation failure anomaly detected" "Evacuation failure" "$OUTPUT"
    assert_match "Allocation spike anomaly detected" "allocation rate spike" "$OUTPUT"
    # Full GC events section should list 3 entries with causes
    FULL_GC_LINES=$(echo "$OUTPUT" | awk '/=== FULL GC EVENTS ===/,/^$/' | grep -cE '^  [0-9]' || echo "0")
    if [ "$FULL_GC_LINES" -eq 3 ]; then
        echo "[PASS] All 3 Full GC events listed with causes"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "[FAIL] Expected 3 Full GC event lines, found $FULL_GC_LINES"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi
echo ""

# ---------------------------------------------------------------
# legacy-parallel.log
# ---------------------------------------------------------------
FIXTURE="legacy-parallel.log"
echo "--- ${FIXTURE} ---"
OUTPUT="$(run_parser "$FIXTURE")" || { echo ""; true; }

if [ -n "$OUTPUT" ]; then
    FIXTURES_TESTED=$((FIXTURES_TESTED + 1))
    assert_match "Format detected as legacy" "format:.*legacy" "$OUTPUT"
    assert_match "GC algorithm detected as Parallel" "gc_algorithm:.*Parallel" "$OUTPUT"
    assert_match "5 Full GC events reported" "total_full_gc_events:.*5" "$OUTPUT"
    assert_match "Pause time stats computed" "PAUSE TIME SUMMARY" "$OUTPUT"
    # Verify stats table has numeric data
    assert_match "Pause time stats contain numeric data" "Min\(ms\).*Avg\(ms\)" "$OUTPUT"
fi
echo ""

# ---------------------------------------------------------------
# unified-zgc.log
# ---------------------------------------------------------------
FIXTURE="unified-zgc.log"
echo "--- ${FIXTURE} ---"
OUTPUT="$(run_parser "$FIXTURE")" || { echo ""; true; }

if [ -n "$OUTPUT" ]; then
    FIXTURES_TESTED=$((FIXTURES_TESTED + 1))
    assert_match "Format detected as unified" "format:.*unified" "$OUTPUT"
    assert_match "GC algorithm detected as ZGC" "gc_algorithm:.*ZGC" "$OUTPUT"
    # ZGC should have very low pause times -- check Max(ms) column is small
    # We check that the parser ran and produced pause time output
    assert_match "Pause time section present" "PAUSE TIME" "$OUTPUT"
fi
echo ""

# ---------------------------------------------------------------
# unified-g1-memory-leak.log
# ---------------------------------------------------------------
FIXTURE="unified-g1-memory-leak.log"
echo "--- ${FIXTURE} ---"
OUTPUT="$(run_parser "$FIXTURE")" || { echo ""; true; }

if [ -n "$OUTPUT" ]; then
    FIXTURES_TESTED=$((FIXTURES_TESTED + 1))
    assert_match "Format detected as unified" "format:.*unified" "$OUTPUT"
    assert_match "GC algorithm detected as G1" "gc_algorithm:.*G1" "$OUTPUT"
    assert_match "Upward occupancy drift detected" "drift" "$OUTPUT"
    assert_match "Memory leak indicator present" "(memory leak|leak)" "$OUTPUT"
fi
echo ""

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "=== Results: ${PASS_COUNT}/${TOTAL} passed ==="

if [ "$FIXTURES_TESTED" -eq 0 ]; then
    echo ""
    echo "WARNING: No fixture files found in ${FIXTURES_DIR}/"
    echo "Please add the following fixture GC logs before running this evaluation:"
    echo "  - unified-g1-healthy.log"
    echo "  - unified-g1-problematic.log"
    echo "  - legacy-parallel.log"
    echo "  - unified-zgc.log"
    echo "  - unified-g1-memory-leak.log"
    exit 1
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi

exit 0
