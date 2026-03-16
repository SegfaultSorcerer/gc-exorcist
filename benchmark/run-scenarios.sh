#!/usr/bin/env bash
#
# Runs gc-exorcist benchmark scenarios and captures GC logs.
#
# Usage:
#   ./run-scenarios.sh                    # Run all scenarios (300s each)
#   ./run-scenarios.sh <scenario-name>    # Run a single scenario
#   DURATION=60 ./run-scenarios.sh        # Run all scenarios for 60s each
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

DURATION="${DURATION:-300}"
LOG_DIR="$SCRIPT_DIR/logs"
JAR="$SCRIPT_DIR/target/gc-exorcist-benchmark-0.1.0-SNAPSHOT.jar"

# Scenario definitions: name -> JVM flags
declare -A SCENARIO_FLAGS
SCENARIO_FLAGS=(
    ["undersized-heap"]="-Xmx256m -Xms256m -XX:+UseG1GC"
    ["humongous-allocation"]="-Xmx1g -XX:+UseG1GC -XX:G1HeapRegionSize=4m"
    ["metaspace-exhaustion"]="-Xmx512m -XX:MetaspaceSize=32m -XX:MaxMetaspaceSize=64m -XX:+UseG1GC"
    ["memory-leak"]="-Xmx512m -XX:+UseG1GC"
    ["high-allocation-rate"]="-Xmx1g -XX:+UseG1GC"
    ["evacuation-failure"]="-Xmx512m -XX:+UseG1GC -XX:G1ReservePercent=5"
    ["system-gc-abuse"]="-Xmx512m -XX:+UseG1GC"
    ["wrong-gc-for-workload"]="-Xmx1g -XX:+UseParallelGC"
)

# Ordered list for consistent execution order
SCENARIOS=(
    "undersized-heap"
    "humongous-allocation"
    "metaspace-exhaustion"
    "memory-leak"
    "high-allocation-rate"
    "evacuation-failure"
    "system-gc-abuse"
    "wrong-gc-for-workload"
)

build() {
    echo "==> Building benchmark application..."
    mvn -f "$SCRIPT_DIR/pom.xml" package -DskipTests -q
    echo "==> Build complete."
}

run_scenario() {
    local name="$1"
    local flags="${SCENARIO_FLAGS[$name]}"
    local log_file="$LOG_DIR/${name}.log"

    local gc_logging="-Xlog:gc*,gc+phases=debug,gc+heap=debug,gc+humongous=debug,safepoint:file=${log_file}:time,uptime,level,tags"

    echo ""
    echo "================================================================"
    echo "  Scenario: $name"
    echo "  Duration: ${DURATION}s"
    echo "  JVM flags: $flags"
    echo "  GC log: $log_file"
    echo "================================================================"

    # shellcheck disable=SC2086
    java $flags \
        $gc_logging \
        -jar "$JAR" \
        --scenario="$name" \
        --duration="$DURATION" \
        --server.port=0 \
        || true  # Don't fail the script if a scenario exits with OOM

    echo "==> Scenario '$name' finished. GC log saved to: $log_file"
}

# --- Main ---

mkdir -p "$LOG_DIR"

# Build first
build

if [[ $# -gt 0 ]]; then
    # Run a single scenario
    SCENARIO_NAME="$1"
    if [[ -z "${SCENARIO_FLAGS[$SCENARIO_NAME]+x}" ]]; then
        echo "Error: Unknown scenario '$SCENARIO_NAME'"
        echo "Available scenarios:"
        for s in "${SCENARIOS[@]}"; do
            echo "  - $s"
        done
        exit 1
    fi
    run_scenario "$SCENARIO_NAME"
else
    # Run all scenarios
    echo "Running all ${#SCENARIOS[@]} scenarios for ${DURATION}s each..."
    echo "Total estimated time: $(( ${#SCENARIOS[@]} * DURATION / 60 )) minutes"
    echo ""

    for scenario in "${SCENARIOS[@]}"; do
        run_scenario "$scenario"
    done

    echo ""
    echo "================================================================"
    echo "  All scenarios complete!"
    echo "  GC logs saved to: $LOG_DIR/"
    echo "================================================================"
    ls -lh "$LOG_DIR/"
fi
